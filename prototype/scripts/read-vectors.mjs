// 읽기 도움 함수의 벡터 뽑기(한 벌 P3 과제 5a) — Node가 정답이다. Rust `lay::cal` · `lay::read` · `lay::f4`가 같은 답을 내는지
// prototype/engine/tests/lay_read.rs가 이 파일(prototype/engine/tests/fixtures/lay/read-vectors.json)로 견준다.
// 정답지 자료(이음매 ①)가 닿지 않는 갈래 — 날짜 글의 꼴(정규식) · 보조 달력 · 미정 · 이설 · 확실성 · 오류 · 알림 글 — 를 함수마다 표본으로 지킨다.
// 사용(작업 폴더에서): node prototype/scripts/read-vectors.mjs
//   시간대가 Asia/Seoul이 아니면 스스로 TZ=Asia/Seoul을 정한 자식 프로세스로 다시 돈다(js-vectors.mjs와 같음). 같은 Node 판이면 같은 바이트가 나온다.
//
// 꼴: { now, calendar: { tables: { <달력 id>: { intl, start, year0, months, … } } }, cases: [{ fn, in, out, warn?, hits? }], f4files: [{ file, sha, warn }] }
//   now: 정답지와 같은 시각(2026-10-15T12:00:00+09:00 · Asia/Seoul)으로 시계를 고정해 실은 웹 코드의 HT.CURRENT_YEAR · HT.NOW_T(Rust read::Ctx와 견줌).
//   hits(cal.parse 표본만): 그 표본을 읽는 동안 실제로 맞은 calendar.js 정규식의 이름(RegExp.prototype.exec를 감싸 셈 — 아래 REGEX_NAMES).
//     Rust 검사가 갈래마다 '맞은 표본 ≥ 1'을 단언한다(손으로 옮긴 RE_BC_MID · RE_NUM의 가름표 셋 · \s의 넓은 빈칸 · LEAD의 옮기기 포함).
//   in · out은 JSON 글(열쇠 차례가 뜻이므로 글로 둔다 — Rust는 js::parse로 읽고 js::stringify로 견준다). out이 undefined면 "undefined".
//   calendar는 export/calendar.mjs의 buildTable로 1400 ~ 2100년을 뜬 보조 달력 표(Rust는 lay::cal::Tables::from_cache로 읽어 ICU 대신 쓴다).
//   f4files: 정답지 자료의 형식 4 파일마다 HT.F4.down(원본)의 JSON.stringify SHA-256 앞 12자와 알림 — 내린 팩 전체(열쇠 차례까지)를 지킨다.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TZ = 'Asia/Seoul';
const self = fileURLToPath(import.meta.url);
if (process.env.TZ !== TZ) {
  const r = spawnSync(process.execPath, [self, ...process.argv.slice(2)], { env: { ...process.env, TZ }, stdio: 'inherit' });
  process.exit(r.status ?? 1);
}
const here = path.dirname(self);
// 시계 고정 — core.js가 싣는 순간 HT.CURRENT_YEAR · HT.NOW_T를 세므로 base.mjs를 가져오기 **전에**(oracle/one.mjs와 같은 시각).
const NOW_TEXT = '2026-10-15T12:00:00+09:00';
(await import('./oracle/clock.mjs')).installClock(NOW_TEXT);
const { bootWeb } = await import('./export/base.mjs');
const { buildTable, wantedCalendars } = await import('./export/calendar.mjs');
const outFile = path.resolve(here, '..', 'engine', 'tests', 'fixtures', 'lay', 'read-vectors.json');
const fixDir = path.resolve(here, '..', 'fixtures', 'oracle');

const HT = bootWeb();
const now = { text: NOW_TEXT, currentYear: HT.CURRENT_YEAR, nowT: HT.NOW_T };
const cases = [];
const text = v => (v === undefined ? 'undefined' : JSON.stringify(v));
/** 함수 하나를 부르고 알림을 모은다 — args는 JSON 값(넘기기 전에 새로 풀어 원본이 바뀌어도 다음 표본에 새지 않게). */
function add(fn, args, call) {
  const warn = [];
  const input = JSON.stringify(args);
  const out = call(JSON.parse(input), m => warn.push(m));
  cases.push(warn.length ? { fn, in: input, out: text(out), warn } : { fn, in: input, out: text(out) });
}

// ── 정규식 맞음 세기(cal.parse 표본만) — calendar.js의 정규식을 원본(source)으로 알아본다. 모르는 정규식이 맞으면 멈춘다(이름표를 고치라고) ──
const REGEX_NAMES = [
  ['fullwidth', s => s === '[０-９]'], ['comma', s => s.startsWith('(\\d),(?=')], ['spaces', s => s === '\\s+'],
  ['lead', s => s.startsWith('^((?:기원전')], ['tail', s => s.startsWith('\\s*[(（]')], ['calWordHead', s => s.startsWith('^\\s*[:：]?\\s*[-')],
  ['calWordCut', s => s === '^\\s*[:：]?\\s*'], ['calWordTail', s => s === '\\s$'], ['approxTail', s => s.startsWith('\\s*(?:경')], ['approxHead', s => s.startsWith('^(?:c\\.')],
  ['bcHead', s => s.startsWith('^(?:기원전')], ['bcTail', s => s.startsWith('\\s*(?:기원전')], ['adHead', s => s.startsWith('^(?:기원후')],
  ['bcMid', s => s.startsWith('^(\\d+)\\s*(?:년\\s*)?(?:기원전')], ['cent', s => s.startsWith('^(\\d+)\\s*세기')], ['ko', s => s.startsWith('^(\\d+)\\s*년')],
  ['num', s => s.startsWith('^(\\d+)(?:\\s*([-./])')],
  ['icu', s => s === '^(\\d+)(bis)?$'], // intlParts의 ICU 달 글 — Rust는 표를 쓰므로 세지 않음
];
let hits = null;
// 과제 5b — core.js에서 손으로 옮긴 정규식(원본 source로 알아봄)과 맞은 갈래의 이름. add5b 표본마다 hits로 싣는다(Rust 검사가 '<함수>/<갈래>'마다 맞은 표본 ≥ 1을 단언).
// 그 밖의 정규식(5a가 지키는 calendar.js · core.js의 것)은 세지 않고 source만 모아 끝에 보인다(빠뜨린 손 옮김이 없는지 사람이 본다).
const REGEX_5B = [
  [s => s === '^(미상|미정|불명|모름|\\?|unknown)$', r => `unknownWord:${r[1].toLowerCase()}`],
  [s => s === '^([^:@]+?)\\s*:\\s*([^@]+?)\\s*(?:@\\s*(.+))?$',
    r => (r[3] === undefined ? (r[2].trim() ? 'personRef:plain' : 'personRef:wsLeader') : r[3].trim() ? (r[2].trim() ? 'personRef:at' : 'personRef:wsLeader') : 'personRef:wsStart')],
  [s => s === '^[123]$', r => `degreeDigit:${r[0]}`],
  [s => s === '조계|조차|租界|租借|거류지|居留地|공사관 ?구역|특구|왜관|倭館', r => `zone:${r[0]}`],
  [s => s === '[,，、·]', r => `succParts:${r[0]}`],
  [s => s === '[,，]', r => `commaList:${r[0]}`],
];
let hits5b = null;
const others5b = new Set();
// 과제 5c — core.js에서 손으로 옮긴 정규식(정규식 그 자체 — 원본에 글자 그대로 있는지 add5c 앞에서 본다)과 맞은 갈래의 이름(이름 하나나 여럿).
// add5c 표본마다 hits로 싣는다(Rust 검사가 '<함수>/<갈래>'마다 맞은 표본 ≥ 1을 단언). 그 밖의 정규식은 source만 모아 끝에 보인다.
const wsName = c => (c === ',' ? 'comma' : c === ch(0xff0c) ? 'fullComma' : c === ch(0x3001) ? 'ideoComma' : c === ';' ? 'semi' : c === ch(0xff1b) ? 'fullSemi' : c === ch(10) ? 'lf' : 'ws');
const REGEX_5C = [
  [/[;；\n]/, r => `signerSplit:${wsName(r[0])}`],
  [/^(.+?)\s*[(（]\s*([^()（）]*?)\s*[)）]$/, r => [`signer:${r[0].endsWith(ch(0xff09)) ? 'fullClose' : 'asciiClose'}`].concat(r[2] === '' ? ['signer:emptyTitle'] : [])],
  [/^\s*(제\s*\d+\s*[조관항]|article\s+\d+|art\.\s*\d+)\s*[.:：]?\s*/i,
    r => [/^제/.test(r[1]) ? `head:je${r[1].slice(-1)}` : /^article/i.test(r[1]) ? 'head:article' : 'head:art.'].concat(/[.:：]/.test(r[0].slice(r[0].indexOf(r[1]) + r[1].length)) ? ['head:punct'] : [])],
  [/^\s*art/i, () => 'artNo:art'], // 번호가 article · art. 꼴(splitArticle이 번호 글의 빈칸을 한 칸으로 접는 갈래 — 제…조 꼴은 빈칸을 지움)
  [/^[(（【[]\s*([^)）】\]\n]{1,60}?)\s*[)）】\]]\s*/, r => [`title:${r[0][0]}`].concat(r[1].trim() === '' ? ['title:wsOnly'] : [])],
  [/^(true|예|네|불평등)$/i, r => `unequal:${r[1].toLowerCase()}`],
  [/[,，、]/, r => `langSplit:${wsName(r[0])}`],
  [/^[^:]+:.+$/, () => 'party:colon'],
  [/:(.*)/, () => 'party:split'],
  [/\r?\n/, r => `lawLines:${r[0].length === 2 ? 'crlf' : 'lf'}`],
  [/[,，\s]/g, r => `strip:${wsName(r[0])}`],
  [/^(true|예|네|당선|이김|승리)$/i, r => `won:${r[1].toLowerCase()}`],
  [/[,，\s]+/, r => `coordSplit:${wsName(r[0][0])}`],
  [/^\s*U\+([0-9A-F]{1,6})\s*(?:[-–~]\s*(?:U\+)?([0-9A-F]{1,6}))?\s*$/i,
    r => (r[2] === undefined ? ['range:single'] : [`range:sep${(r[0].match(/[-–~]/) || [''])[0] === '-' ? 'Hyphen' : /~/.test(r[0]) ? 'Tilde' : 'Dash'}`].concat(/[-–~]\s*u\+/i.test(r[0]) ? ['range:uPlus2'] : []))],
  [/^none$/i, () => 'none'],
  [/^data:font\/(woff2|woff|ttf|otf);base64,([A-Za-z0-9+/]+={0,2})$/, r => `font:${r[1]}`],
  [/^[A-Za-z]{4}$/, () => 'script4'],
  [/^[^/]+\/[^/]+$/, () => 'target'],
  [/["'\\/]/, r => `badId:${r[0] === '"' ? 'dq' : r[0] === "'" ? 'sq' : r[0] === '/' ? 'slash' : 'bs'}`],
  [/\r/g, () => 'cr'],
  [/[,，]/, r => `comma:${wsName(r[0])}`],
];
let hits5c = null;
const others5c = new Set();
const realExec = RegExp.prototype.exec;
RegExp.prototype.exec = function (s) {
  const r = realExec.call(this, s);
  if (hits5b && r) {
    const hit = REGEX_5B.find(([test]) => test(this.source));
    if (hit) hits5b.add(hit[1](r));
    else others5b.add(this.source);
  }
  if (hits5c && r) {
    const hit = REGEX_5C.find(([re]) => re.source === this.source);
    if (hit) {
      const h = hits5c;
      hits5c = null; // 이름을 짓는 동안 쓰는 정규식은 세지 않는다
      try { [].concat(hit[1](r)).forEach(name => h.add(name)); } finally { hits5c = h; }
    } else others5c.add(this.source);
  }
  if (hits && r) {
    const hit = REGEX_NAMES.find(([, test]) => test(this.source));
    if (!hit) throw new Error(`이름표에 없는 정규식이 맞았습니다: /${this.source}/`);
    let name = hit[0];
    if (name === 'num') name = `num${r[2] ?? ''}`; // 가름표(-, ., /)마다 — Rust는 가름표마다 정규식이 따로다
    if (name === 'spaces' && [...r[0]].some(c => c !== ' ')) hits.add('spacesWide'); // 보통 빈칸 말고 탭 · NBSP · 전각 빈칸 · BOM · 줄 끝 …
    if (name !== 'icu') hits.add(name);
  }
  return r;
};
/** cal.parse 하나 — 맞은 정규식 이름을 hits로 싣는다. LEAD가 기원전 말을 달력 말 뒤로 옮긴 경우(lead 다음 달력 앞말이 맞음)는 leadMove도. */
function addParse(v) {
  hits = new Set();
  add('cal.parse', [v], ([x]) => parseOut(HT.cal.parse(x)));
  const h = hits;
  hits = null;
  if (h.has('lead') && h.has('calWordHead')) h.add('leadMove');
  cases[cases.length - 1].hits = [...h].sort();
}

// ── 보조 달력 표(1400 ~ 2100년) ──
const fromJ = HT.cal.jdnCivil(1400, 1, 1);
const toJ = HT.cal.jdnCivil(2100, 1, 1);
const tables = {};
for (const c of wantedCalendars(HT)) tables[c.id] = Object.assign({ intl: c.intl }, buildTable(HT, c, fromJ, toJ));

// ── cal.parse: 날짜 글(정규식 갈래마다) ──
const parseOut = r => (r == null ? null : !r.ok ? { ok: false, error: r.error }
  : { ok: true, t: r.t, prec: r.prec, cal: r.cal, y: r.y, m: r.m ?? null, leap: !!r.leap, d: r.d ?? null, h: r.h ?? null, mi: r.mi ?? null, J: r.J ?? null, text: r.text, fine: r.fine, span: r.span ?? null, last: r.last ?? null });
const dateTexts = [
  1592, -108, 1592.5, -0.25, 0, '', '   ', null, true, '1592', ' 1592 ', '기원전 108', '기원전108', 'BC 108', 'bc 108', 'B.C. 108', 'B.C.E. 108', 'BCE 108', '108 BC', '108 B.C.', '108BCE',
  '108 bc E', '서기전 57', '기원후 5', '서기 5', 'AD 5', 'A.D. 5', 'CE 5', 'C.E. 5', 'ad5', '-108', '- 108', '0', '0년', '0-01-01',
  '1592-05-23', '1592.5.23', '1592/5/23', '1592-05', '1592.5.23.', '1592.5.', '1592-5/23', '1592 - 05 - 23', '1592년 5월 23일', '1592년5월23일', '1592년 5월', '1592년',
  '1592년 윤4월 13일', '1592-윤04-13', '1592년 5월 23일 14시 30분', '1592년 5월 23일 14시', '1592-05-23 14:30', '1592-05-23T14:30', '1592-05-23t14:30', '1592-05-23 오후 2시',
  '1592-05-23 오전 12시', '1592-05-23 2:30 PM', '1592-05-23 2:30 pm', '1592-05-23 12:00 AM', '1592-05-23 PM 2:30', '1592-05-23 25:00', '1592-05-23 23:60', '1592-05 14시',
  '1592-13-01', '1592-05-32', '1592-02-30', '1600-02-29', '1700-02-29', '1582-10-10', '1582-10-15', '1582-10-04', '그레고리력 1582-10-04', '율리우스력 1582-10-20',
  '양력 1592-05-23', '서력 1592', '1592 양력', '1592-05-23 (양력)', '1592-05-23（양력）', '1592 (모르는 말)', '3세기', '3세기 중반', '3세기 초엽', '3세기 초', '3세기 중', '3세기 말엽',
  '3세기 전반', '3세기 후반', '기원전 2세기 말', '기원전 1세기', '1세기 초', '21세기 후반', '0세기', '3 세기 말', '음력 3세기', '1,592', '12,345년', '1,5923', '１５９２-０５-２３',
  '1592경', '1592 무렵', '1592년 쯤', 'c. 1592', 'ca. 1592', 'C. 1592', '약 1592', '약1592년', '미정', '현재', 'abc', '1592-05-23 extra', '99999999999999999999',
  '1'.repeat(400), '기원전 1년 12월 31일', '기원전 1-12-31',
  // 보조 달력(표로 — 1400 ~ 2100년)
  '음력 1592-04-13', '음력 1592년 윤3월 1일', '음력 1592-윤03-01', '1592-04-13 (음력)', '1592-04-13 음력', '음 1592.4.13', '음력: 1592-04-13', '기원전 음력 100-01-01',
  '한국 음력 1700-01-01', '중국 음력 1592-04-13', '농력 1600-12-30', '음력 1600-02-30', '음력 1601년 윤1월 1일', '이슬람력 1000-08-11', 'AH 1000-08-11', 'ah 1000-08-11',
  '히즈라력 1100-01-01', '이슬람력 0-01-01', '움알쿠라 1440-09-01', '움 알쿠라 1440-09-30', '페르시아력 1371-01-01', '이란력 1371-12-30', '페르시아력 1371-07', '음력 1592',
  '음력 1592-04', '이슬람력 1000-08-11 10:30', '음력 1592-04-13 오후 3시',
  // 리메이크 6단계 걸음 4(D10) — 달력 다섯: 히브리력(티슈리 = 1월 · 윤년은 13달) · 에티오피아력 · 콥트력(13째 달 5 · 6일) · 사카력 · 불기(해만 서력 + 543 — 1582년 10월은 21일)
  '히브리력 5784-01-01', '히브리력 5784-07-14', '유대력 5784-13-29', '히브리력 5783-13-01', '히브리력 5784-14-01', '히브리력 5784', '히브리력 5784-13',
  '에티오피아력 2016-01-01', '에티오피아력 2015-13-06', '에티오피아력 2016-13-06', '에티오피아력 2016-13', '에티오피아력 2016-13-05 오후 3시', '콥트력 1740-01-01', '콥트력 1739-13-06',
  '사카력 1945-01-01', '인도 국정력 1946-12-30', '사카력 1945-13-01', '불기 2567-02-29', '타이 불기 2566-02-29', '불기 2125-10-10', '불기 2125-10', '2100-03-01 (불기)', '에티오피아력 0-01-01',
  // 고침 1회차 — RE_BC_MID(손으로 옮긴 앞보기)에 실제로 맞는 꼴: 숫자 · (년) · 기원전 말 뒤에 가름표 · 빈칸 · 끝이 아닌 나머지
  '108 BC-03-15', '108 BC.3.15', '108 B.C./3/15', '108년 기원전 3월 15일', '57 B.C. 5', '57기원전-1-1', '108 bce-3',
  // 고침 1회차 — JS \s의 넓은 빈칸(탭 · 줄 끝 · NBSP · 전각 빈칸 · BOM · U+2028 · U+2003 · VT · FF)
  '1592\u3000년 5월', '\t1592-05-23\n', '\ufeff1592\ufeff', '1592\u00a0-\u00a005-23', '1592년\u20285월', '1592-05-23\u2003오후\u20032시', '음력\u00a01592-04-13',
  '1592\u000b년', '1592\u000c-05', '기원전\u3000108', '3세기\u00a0말', '1592-05-23\u3000(양력)',
  // 고침 1회차 — LEAD가 기원전 말을 달력 말 뒤로 옮기는 꼴(표 안 · 서력 달력)
  '기원전 율리우스력 44-03-15', 'BC 그레고리력 1-01-01', '서기전 양력 57', 'B.C. 율리우스력 44',
  // 과제 5b(5a 검토의 얹힌 몫 2) — 쉼표 지우기에 쉼표가 여럿인 꼴
  '1,234,567', '1,234,567년', '2,026-01-01',
];
// 과제 5b(5a 검토의 얹힌 몫 1) — JS \s의 빈칸 목록 가운데 위 표본에 없던 것(U+1680 · U+2000 ~ 200A · U+202F · U+205F · U+2029). 날 글자 · 이스케이프 글을
// 소스에 두지 않으려고 코드 포인트로 만든다(편집기가 글자를 바꾸면 표본이 조용히 달라지므로).
for (const cp of [0x1680, 0x2000, 0x2001, 0x2002, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x202f, 0x205f, 0x2029]) {
  const c = String.fromCharCode(cp);
  dateTexts.push(`1592${c}년 5월`, `1592-05-23${c}오후${c}2시`);
}
for (const v of dateTexts) addParse(v);

// ── 날짜 칸 · 끝 · 미정 ──
const readDateOut = d => (d == null ? null : { t: d.t, at: d.at ?? null, prec: d.prec ?? null, cal: d.cal ?? null, error: d.error ?? null });
for (const [v, at] of [[1592, null], [1592, '1592-05-23'], [1593, '1592-05-23'], ['', '1592-05-23'], [null, '1592-05-23'], [null, '  '], ['미정', null], ['현재', null],
  ['진행 중', null], ['3세기 말', null], [266, '3세기 말'], [300, '3세기 말'], [1592.5, null], ['1592-05-23', null], ['1592-05-23', '1600-01-01'], [1592, 5], [null, null],
  ['nope', null], [1592, '1592'], [1592, '1592-05'], ['음력 1592-04-13', null], [1592.3876, '음력 1592-04-13']]) {
  add('readDate', [v, at], ([a, b]) => readDateOut(HT.readDate(a, b)));
}
for (const [end, at] of [[1592, null], [1592, '1592-05-23'], [1592.4, null], [300, '3세기 말'], [267, '3세기 말'], [-101, '기원전 2세기 말'], [1592, ''], [2000, '21세기'], [1950, '20세기 중반'],
  ['1600', null], ['300', '3세기 말'], [' 267 ', '3세기 말'], [true, null], [null, '3세기 말'], ['x', null]]) {
  add('endBound', [end, at], ([a, b]) => HT.endBound(a, b));
}
for (const v of [1592, '1592', '기원전 57', 'x', '', null, '3세기', true]) add('parseYear', [v], ([x]) => { const t = HT.parseYear(x); return Number.isNaN(t) ? 'NaN' : t; });
for (const c of [{ start: '미정' }, { start: '미정', startHint: 1590 }, { startUnknown: true, start: 1590 }, { startUnknown: true, start: 1590, startAuto: true }, { startUnknown: true, startHint: '기원전 3' },
  { start: 'unknown', startHint: '' }, { start: 1592 }, { start: '1592-05-23' }, { start: 'abc' }, {}, null, { start: 'TBD', startHint: 'x' }]) {
  add('readCellEdge', [c, 'start'], ([x, k]) => { const d = HT.readCellEdge(x, k); return d == null ? null : d.unknown ? { unknown: true, t: d.t } : readDateOut(d); });
}

// ── 글 판정(손으로 옮긴 정규식) ──
const words = ['미정', ' 미정 ', '불명', '모름', '?', 'unknown', 'UNKNOWN', 'Unknown', 'un\u212anown', 'tbd', 'TBD', '미정?', '', null, 0, '현재', '진행 중', '진행중', '진행\u3000중', '진행  중',
  'present', 'PRESENT', 'pre\u017fent', 'now', 'Now', 'ongoing', 'ongoing ', '현재까지', '\ufeff현재\ufeff', 'x', ['미정'], true];
for (const v of words) {
  add('isUnknownText', [v], ([x]) => HT.isUnknownText(x));
  add('isOngoingText', [v], ([x]) => HT.isOngoingText(x));
}
for (const v of ['korea', 'k', 'a-b_c.d', '-a', '_a', '.a', 'a b', '', 'A'.repeat(64), 'A'.repeat(65), '가', 'a:b', 'a/b', '0', 'Z9']) add('ID_RE', [v], ([x]) => HT.ID_RE.test(x));
for (const v of ['#abc', '#ABC', '#abcdef', '#AbCdEf', '#abcd', '#ab', 'abc', '#ggg', '#abc ', ' #abc', null, 123, '#0f0']) add('isColor', [v], ([x]) => HT.isColor(x));
for (const v of ['', 'a', 'korea', '한국1592고구려', '𠀀', 'hayeon412아홉 불씨 할거', 'x'.repeat(200)]) {
  add('hash', [v], ([x]) => HT.hash(x));
  add('autoColor', [v], ([x]) => HT.autoColor(x));
}
for (const v of ['ko', 'KO', 'zh-Hant', 'x-elvish', 'X-Elvish', 'x', 'x-', 'ko-', '-ko', 'k', 'abcdefghi', 'ko-abcdefghi', 'ko-1', 'k\u212a', ' ko ', '', 123, 'la-x-a1']) add('isLangTag', [v], ([x]) => HT.isLangTag(x));
for (const v of ['고구려', 'korea:고구려', 'korea: 고구려 ', 'korea:', ':고구려', 'ko rea:고구려', 'a.b-c_d:x', 'korea:고\n구려', ' korea:고구려 ', '', '  ', 'a:b:c',
  { polity: '고구려' }, { polity: ' 고구려 ', track: ' korea ' }, { name: '백제' }, { polity: '', name: '신라' }, { track: 'korea' }, [], 5, null, true]) {
  add('readScopeRef', [v], ([x]) => HT.readScopeRef(x));
}
add('readScopeRefs', [['a', 'korea:b', '', null, { polity: 'c' }]], ([x]) => HT.readScopeRefs(x));
add('readScopeRefs', ['a'], ([x]) => HT.readScopeRefs(x));
for (const v of ['tributary', '조공', '조공·책봉국', '명목', '명목상 소속', '구성국', '동군', '동군 연합', '책봉국', '번진', ' 괴뢰 ', 'state', '', null, 'xyz', '보호령']) add('relationId', [v], ([x]) => HT.relationId(x));
for (const v of ['era', '시대', '나라', 'realm', ' 국가 ', 'xyz', '', null, 'office']) add('F4.typeId', [v], ([x]) => HT.F4.typeId(x));
for (const v of ['start', 'northSouth', '시작', '남북', 'North-South', 'NORTHSOUTH', '북 → 남', '__proto__', 'constructor', '', null, 'xyz']) add('readRowOrder', [v], ([x]) => HT.readRowOrder(x));

// ── 이설 · 확실성 · 연대 폭 ──
const alts = [
  [{ start: 1590, label: '다른 설' }, { start: 1590, end: 1590 }, { end: 1600 }, { label: '', note: '' }, { note: '근거만' }, { start: 'abc' }, { start: 1590, end: 'abc' },
    { start: 1590, ongoing: true, end: 1600 }, { start: 1590, end: '현재' }, null, 'x', [1, 2], { start: '1590-03-01', end: '1592-05-23', label: 'a', source: 's', note: 'n' }],
  [{ start: 1600, end: 1590 }, { birth: 1550, death: 1600 }, { birth: 1600, death: 1550 }, { end: 1500 }, { start: 1700 }],
];
for (const list of alts) for (const mode of ['item', 'cell', 'figure']) {
  add(`readAlternatives:${mode}`, [list, null], ([x], w) => HT.readAlternatives(x, { mode, warn: w }));
}
add('readAlternatives:cell', [alts[1], { start: 1550, end: 1650 }], ([x, base], w) => HT.readAlternatives(x, { mode: 'cell', warn: w, base }));
add('readAlternatives:cell', [alts[1], { start: 1550, end: 1650, endUnknown: true }], ([x, base], w) => HT.readAlternatives(x, { mode: 'cell', warn: w, base }));
add('readAlternatives:cell', [[{ end: 1500 }, { start: 1700 }], { start: 1550, end: 1650, ongoing: true }], ([x, base], w) => HT.readAlternatives(x, { mode: 'cell', warn: w, base }));
add('readAlternatives:figure', [[{ birth: 1700 }, { death: 1500 }, { end: 1500 }], { birth: 1600, death: 1650, start: 1620 }], ([x, base], w) => HT.readAlternatives(x, { mode: 'figure', warn: w, base }));
// 고침 1회차 — 통설 값이 글이면 HT.endBound는 그해 끝으로 올리지 않는다('1600' < 1600.5 → 뒤집힘)
add('readAlternatives:cell', [[{ start: 1600.5 }, { end: 1500 }, { start: 1600 }], { start: '1550', end: '1600' }], ([x, base], w) => HT.readAlternatives(x, { mode: 'cell', warn: w, base }));
const uncs = [
  { certainty: 'estimated', startRange: [1590, 1580], startRangeAt: ['1590-01-01', null], start: 1585, alternatives: [{ start: 1600 }] },
  { certainty: 'accepted', endRange: [1600, 1610], end: 1620, start: 1590 },
  { certainty: 'weird', legendary: true, debate: ' 쟁점 ', startRange: 'x', endRange: [1, 'a'] },
  { legendary: true },
  { start: '3세기', end: '4세기 말' },
  { start: '3세기', ongoing: true },
  { start: '3세기' },
  { start: 250, startAt: '3세기', end: 399, endAt: '4세기 말' },
  { start: 1592, startRange: [1590, 1595], end: '3세기 말' },
  { alternatives: [{ start: 1590, label: 'x' }, { end: 1500 }], start: 1592, end: 1600, startUnknown: true },
  null, [1],
];
for (const x of uncs) for (const mode of ['item', 'cell', 'figure', 'epoch']) {
  add(`readUncertain:${mode}`, [x, 1592, 1600], ([v, start, end], w) => HT.readUncertain(v, { mode, warn: w, start, end }));
}
add('readUncertain:cell', [uncs[9], null, null], ([v, start, end], w) => HT.readUncertain(v, { mode: 'cell', warn: w, start, end }));

// ── 이름 목록 · 간지 · 팩 정보 · 모아 보기 판 ──
const namesIn = [
  ['원어', { text: 'Name', lang: 'en', kind: 'roman' }, { name: '옛', kind: '옛이름', start: 1500, end: 1400 }, { text: 'x', lang: 'k\u212a', kind: '현지 어' }, { text: 'x', lang: 'k\u212a', kind: '현지 어' },
    '', null, { text: '' }, { text: 'y', start: '미정', end: 'abc', note: ' 메모 ' }, [1], { text: 'z', start: '1592-05-23', end: '1600' }, { text: 'z', start: '1592-05-23' }],
  'Single', '', null,
];
for (const v of namesIn) add('readNames', [v], ([x], w) => HT.readNames(x, w));
for (const v of [null, false, true, '끔', ' off ', 'false', '', 'x', 5, [1], { names: ['갑', '을'] }, { names: '갑, 을，병', start: '기원전 3', label: ' 순환 ' },
  { names: ['a'], start: 1 }, { names: ['가'.repeat(25), '나'], start: 0 }, { names: Array.from({ length: 250 }, (_, i) => `n${i}`), start: 'x', label: 'L'.repeat(25), extra: 1 },
  { names: [null, ' ', 'a', 'b'], start: '1592-05-23', startAt: '1592-05-23' }]) {
  add('readYearCycle', [v], ([x], w) => HT.readYearCycle(x, w));
}
// 문화권별 주기 줄 — 육십갑자 예약 값(6단계 결정 16: 예약 글 · 표지만 · 고친 이름 · 모르는 표지 · 펴진 줄 다시 읽기) · 이름 돌림 · 연호 눈금 · 겹침 · 틀린 줄
for (const v of [null, 'x', [
  { sphere: 'a', names: '육십갑자', start: 99, label: '간지' }, { names: ' sexagenary ' }, { sphere: 'c', builtin: 'sexagenary', era: '겹침' }, { sphere: 'd', names: ['갑', '을'], start: 4, builtin: 'sexagenary' },
  { sphere: 'e', names: '갑, 을', start: 1, builtin: 'xyz' }, { sphere: 'f', names: Array.from({ length: 60 }, (_, k) => HT.ganji(4 + k)), start: 4, builtin: ' sexagenary ' },
  { sphere: 'g', builtin: 'sexagenary', names: '' }, { sphere: 'j', names: [' 육십갑자 '] }, { sphere: 'k', names: ['육십갑자', '을'] }, { sphere: 'h', era: '빙원', from: 300, step: 10 }, { sphere: 'a', era: '겹친 줄', from: 1 }, { sphere: 'bad id!', names: '육십갑자' }, 5, { sphere: 'i' },
]]) add('readYearCycles', [v], ([x], w) => HT.readYearCycles(x, w));
for (const raw of [
  { category: 'world', tags: ['a', 'a', ' b ', '', 'x'.repeat(30), 'c', 'd', 'e', 'f'], summary: 's'.repeat(130), highlights: ['h1', '', 'h2'], cover: 'data:image/png;base64,AAAA==',
    relations: [{ type: 'needs', id: 'other', name: ' 다른 팩 ' }, { type: 'needs', id: 'other' }, { type: 'bad', id: 'x' }, { type: 'after', id: 'self' }, { type: 'conflicts', id: 'bad id' }, null],
    changelog: [{ version: '1.0', date: '2026-10-14', note: '첫 판' }, { version: '' }, { version: '0.9', date: '어제' }, null], created: '2026-10-01', updated: '2026/10/14' },
  { category: '', tags: 'x', cover: 'data:image/gif;base64,AAAA', highlights: null },
  { category: 'nope', cover: 'data:image/jpeg;base64,===', relations: 'x', changelog: [] },
  { cover: ' data:image/webp;base64,AbC+/= ', tags: [] },
  {},
]) add('readPackInfo', [raw, 'self'], ([x, id], w) => HT.readPackInfo(x, w, id));
for (const s of [null, '', 'x', [1], { density: '1' }, { density: -1 }, { density: '빽빽하게' }, { density: '7' }, { density: ' -0 ' }, { lens: 'ember' }, { lens: 5 }, { lens: '' },
  { show: { houses: true, nope: true, ranks: 'yes' } }, { show: [] }, { show: null }, { unknown: 1, density: 2 }]) {
  add('readViewSettings', [s], ([x], w) => HT.readViewSettings(x, w));
}
{
  const views = [
    { name: '판', members: ['a', 'korea:b', 'a', { polity: 'a', track: '' }], start: 1500, end: 1600, settings: { density: 0 }, names: ['Board'], color: '#abc', description: ' d ', note: 'n', wiki: ' w ' },
    { name: '판', members: 'x', id: 'bad id', start: 'abc' },
    { id: 'v1', name: '둘', members: ['y'], start: 1600, end: 1500 },
    { id: 'v1', name: '셋', members: ['z'], end: 1600 },
    { name: '넷', members: [] },
    { name: '', members: ['q'] },
    null, 'x',
    { name: '다섯', members: ['r'], start: 1500, ongoing: true, end: 1600 },
    { name: '여섯', members: ['s'], start: '1592-05-23', end: '현재' },
  ];
  add('readViews', [views], ([x]) => {
    const notes = [];
    const out = HT.readViews(x, { err: (m, i) => notes.push(['err', m, i]), warn: (m, i) => notes.push(['warn', m, i]) });
    return { out, notes };
  });
}

// ── 정규화(5a 몫 — 머리 · 트랙 · 분류 · 민족 · 시대 구분 · 대범위 · 모아 보기 판 · 간지 / 5b 몫 — 시대 · 기관 · 문화 · 왕조 · 가문 · 지위 사전) ──
// 팩 전체(열쇠 차례까지 — 5a · 5b는 KEYS 거르개로 넓혀 왔고 과제 5c가 걷었다)와 알림 · 오류를 모두 견준다.
const norm = raw => { const r = HT.normalizePack(raw); return { pack: r.pack, errors: r.errors, warnings: r.warnings }; };
for (const raw of [
  null, [], 'x',
  { format: 'nope', formatVersion: 9, id: 'bad id', name: '' },
  { format: 'history-timeline-dlc', id: 'user', name: 'u' },
  {
    format: 'history-timeline-dlc', formatVersion: 3, id: 'syn', name: ' 시험 ', version: '', author: 7, description: null, requires: ['a', '', ' b ', 3],
    tracks: [{ id: 't1', name: '하나', color: '#ABC', order: '5', description: ' d ', wiki: ' w ', sphere: 'steppe' }, { id: 't1' }, { id: 'bad id' }, null, 0, { id: 't2', order: '', sphere: 'mars' },
      { id: 't3', order: [], color: 'red' }, { id: 't4', order: 'x' }],
    categories: [{ id: 'war' }, { id: 'c1', name: '갈래', color: '#123456' }, { id: 'c1' }, {}],
    peoples: [{ id: 'p1', name: '겨레', parent: ' 위 ', color: '#fff', order: 2, rowOrder: '북 → 남' }, { id: 'p2', rowOrder: 'start' }, { id: 'p3', rowOrder: 'zig' }, { id: 'p1' }, { name: '이름만' }],
    epochs: [{ name: '고대', start: -500, end: 500 }, { name: '고대', start: -500, end: 500 }, { name: '중세', start: 500, end: '미정', endHint: 1500, track: 't1', within: '그릇', color: '#ddd', note: 'n' },
      { name: '근세', start: '미정', end: 1800 }, { name: '근대', start: 1800, ongoing: true, alternatives: [{ start: 1790, label: '설' }, { end: 1900 }] }, { name: '같은', start: 1900, end: 1900 },
      { name: '거꾸로', start: 2000, end: 1990 }, { name: '없음', start: 'abc' }, { start: 1 }, { name: '트랙없음', start: 1, track: 'nope' }, { id: 'ep-x', name: '정한 id', start: 3 },
      { id: 'ep-x', name: '겹친 id', start: 4 }, { id: 'bad id', name: '나쁜 id', start: 5 }, { name: '시작미정', start: '미정' }, 'x', { name: '세기', start: '3세기', end: '4세기 말' }],
    scopes: [{ track: 't1', name: '모음', members: ['가', 't1:가', 't2:나', { polity: '다' }], start: 400, end: 500, host: '가', within: '모음', label: ' 짧게 ', color: '#eee', default: true, description: 'd' },
      { track: 't1', epoch: '고대', members: '라' }, { track: 't1', name: '빈', members: [] }, { track: 'nope', name: 'x', members: ['a'] }, { name: '', members: ['a'], track: 't1' },
      { track: 't1', name: '끝만', members: ['m'], end: 500 }, { track: 't1', name: '모음', members: ['n'], start: 400 }, { track: 't1', name: '나쁜 기간', members: ['o'], start: 'x' }, null],
    views: [{ name: '판', members: ['가'] }, 'x'],
    yearCycle: { names: ['갑', '을'], start: 4 },
  },
  { format: 'history-timeline-dlc', id: 'v-only', name: 'v', views: 'x', yearCycle: true },
  { format: 'history-timeline-dlc', id: 'v-only2', name: 'v', views: [{ name: '판', members: ['가'] }] },
  { format: 'history-timeline-dlc', id: 'empty', name: 'e', tracks: [{ id: 't' }] },
  // 가상 세계 문화권(HT.FANTASY_SPHERES — 맞추기 과제 S): 일곱 모두 · 다듬기 · 대소문자 다름 · 실제 문화권과 섞임 · 이름(id가 아님)은 모름
  { format: 'history-timeline-dlc', id: 'fantasy', name: 'f', tracks: [
    ...['ember-basin', 'frost-ridge', 'jade-canopy', 'crimson-canyon', 'prism-strait', 'coral-archipelago', 'white-spire'].map((sphere, i) => ({ id: `f${i}`, sphere })),
    { id: 'g1', sphere: ' frost-ridge ' }, { id: 'g2', sphere: 'Frost-Ridge' }, { id: 'g3', sphere: 'steppe' }, { id: 'g4', sphere: '등불 분지권' }, { id: 'g5', sphere: 'fantasy' }] },
  { format: 'history-timeline-dlc', formatVersion: 4, id: 'f4', name: 'f4', tracks: [{ id: 't' }], epochs: [], objects: [
    { type: 'era', name: '시대', start: 1, end: 100, track: 't' }, { type: 'era', name: '공통 시대', start: 1, end: 100 }, { name: '나라', start: 1, end: 50, track: 't', within: ['시대'] },
    { name: '안 나라', start: 10, end: 40, within: '나라' }, { type: 'era', name: '시대', id: 'e2', start: 100, end: 200, track: 't', within: '시대' }] },
]) add('normalizePack', [raw], ([x]) => norm(x));

// ── 과제 5b: 띠(시대) · 기관 · 문화 · 왕조 · 가문 · 지위 사전과 그 도움 함수 ──
// add5b: add와 같고, 그 표본을 읽는 동안 맞은 손 옮김 정규식의 갈래(REGEX_5B)를 hits로 싣는다.
function add5b(fn, args, call) {
  hits5b = new Set();
  add(fn, args, call);
  const h = hits5b;
  hits5b = null;
  if (h.size) cases[cases.length - 1].hits = [...h].sort();
}
const ch = cp => String.fromCharCode(cp); // 날 글자를 소스에 두지 않으려고
const KELVIN = ch(0x212a);
// ('constructor' 같은 물려받은 이름은 웹이 함수를 돌려줘 JSON에 담기지 않는다 — 알려진 차이로 read/vocab.rs 머리말에 적음 · 표본에서 뺌)
for (const v of ['attested', 'semi', '반전설', '반(半)전설', '전설', '신화', '논쟁', '실재 논쟁', '부정', '부정됨', '실재', ' legendary ', '', null, 'xyz', 5]) {
  add5b('historicity', [v], ([x]) => HT.historicity(x));
}
for (const v of ['direct', '직접', '직접 승계', '간접', '부흥 계승', '부분', 'partial', '부분 계승', '', null, 'xyz', 7]) add5b('successionType', [v], ([x]) => HT.successionType(x));
for (const v of [1, 2, 3, 4, 0, 2.5, '1', '2', '3', ' 3 ', '4', '12', '약', '강함', '중간', 'WEAK', 'Medium', 'strong', `wea${KELVIN}`, 'xyz', '', null, true, [2]]) {
  add5b('succDegree', [v], ([x]) => HT.succDegree(x));
}
for (const v of ['elite', '지배층', '유민', '영토', ' 문화 ', 'xyz', '', null]) add5b('succPart', [v], ([x]) => HT.succPart(x));
for (const v of ['X', ' X ', '', null, 5, [], {}, { from: ' A ', type: '직접', note: ' n ' }, { from: 'A', type: 'partial' }, { from: 'A', type: '부분', degree: '강', parts: '지배층, 백성，영역、제도·문화' },
  { from: 'A', type: 'partial', degree: 'x', parts: ['백성', '백성', 'xyz', '', '유민', null] }, { from: 'A', type: 'partial', degree: 7 }, { from: 'A', type: 'direct', degree: 3, parts: ['elite'] },
  { from: 'A', type: 'partial', parts: 'xyz' }, { from: 'A', type: 'partial', degree: '', parts: '' }, { from: 'A', type: 'partial', parts: ['culture', 'elite', '제도'] }, { from: 'A', type: '부분 계승', degree: 1, parts: 5 },
  { from: 'A', type: 'partial', degree: ' strong ' },
  // 나라 승계의 방식(how — 6단계 결정 15): 이름 · id · 낱말(띄어쓰기 무시) · 모르는 방식 · 물려받은 이름 · 수 · 빈 글 · 부분 승계와 함께(열쇠 차례)
  { from: 'A', type: '직접', how: '선양', note: 'n' }, { from: 'A', type: 'partial', degree: 3, parts: ['elite'], how: 'split', note: 'n' }, { from: 'A', how: '외계 침공' },
  { from: 'A', how: ' 승계 주장 ' }, { from: 'A', how: 'constructor' }, { from: 'A', how: 7 }, { from: 'A', how: '' }, { from: 'A', how: null }, { from: 'A', type: 'revival', how: 'rename' }]) {
  add5b('normalizeSucc', [v], ([x], w) => HT.normalizeSucc(x, w));
}
for (const v of ['marriage', '혼인', '상속', '정복', '갈라짐', '합쳐짐', '개명', '주장', '선양', '결혼', '분 열', '합병', '국호 변경', '승계주장', '양위', 'unknown', '미상', 'xyz', '', null, 5, 'toString']) add('succHow', [v], ([x]) => HT.succHow(x));
for (const v of ['state', '국가', '조공', '조공국', '괴뢰국', '괴뢰 정권', '번진', '부마국', ' 시대 ', '시대 이름', 'xyz', '', null, 'overlay', '나라']) add5b('polityKindId', [v], ([x]) => HT.polityKindId(x));
for (const v of ['main', '정도', '공동', '공동 정도', '5경', '행재', '망명', 'secondary', 'xyz', '', null]) add5b('capitalRole', [v], ([x]) => HT.capitalRole(x));
for (const v of [['한성', 1392, 1897, '배도'], ['한성', 1392, null, '메모'], ['한성', '미정', 1400], ['', 1392], ['한성'], ['한성', 'abc'], ['x', 1500, 1600, '피난'], ['x', '3세기', '4세기 말'],
  { city: '개경', start: 919, end: 1392, role: '정도', as: '송악', label: ' 고려 전기 ', group: 'g', event: 'e', note: 'n' }, { name: '평양', start: 427 },
  { city: 'x', start: '미정', startHint: 1500, end: 1400 }, { city: 'x', start: '미정', end: '미정', endHint: 1300 }, { city: 'x', start: 1500, end: '미정', endHint: 1400 },
  { city: 'x', start: 1500, end: 1400 }, { city: 'x', start: '1592-05-23', end: '1593-01-01', certainty: 'estimated' }, { city: 'x', start: 1500, as: 'x' }, { city: 'x', start: 1500, as: ' y ' },
  { city: 'x', start: 1500, alternatives: [{ start: 1400 }, { end: 1300 }] }, { city: 'x', start: 1500, certainty: 'weird' }, null, 'x', { city: 'x', start: '미정', end: '미정' },
  { city: 'x', start: 1500, role: 'xyz', extra: '공동' }, { city: 'x', start: 1500, note: '', extra: '메모 글' }, { city: 'x', start: 1500, startAuto: true }, { city: 'x', startUnknown: true, start: 1500, startAuto: true }]) {
  add5b('normalizeCapital', [v], ([x], w) => HT.normalizeCapital(x, w));
}
for (const v of [['x', 1500, 1600, 'x'], { city: 'x', start: 1500, certainty: 'weird' }]) add5b('normalizeCapital:nowarn', [v], ([x]) => HT.normalizeCapital(x));
for (const v of [[{ ordinal: 3 }, {}, { ordinalUnknown: true, ordinal: 5 }, {}, { ordinal: 10 }, {}], [{}, {}, {}], [], [{ ordinalUnknown: true }, { ordinal: 2 }, {}]]) {
  add5b('numberLeaders', [v], ([x]) => HT.numberLeaders(x));
}
for (const v of [[{ start: 3 }, { end: 2 }, { start: 2 }, {}, { start: 1 }, { end: 5, start: null }], [{}, {}], [{ start: 'x' }, { start: 2 }], [{ end: 3 }, { start: 3 }, { end: 3 }, { start: 3, end: 1 }], []]) {
  add5b('sortCells', [v], ([x]) => HT.sortCells(x));
}
for (const v of [null, '', 'x', 5, true, false, {}, { spans: 'x' },
  [{ scheme: 'A', note: 'n', spans: [['전기', 100, 200], ['중기', null, 300], { name: '후기', start: 300, end: '미정' }] }, { scheme: 'A', note: 'n2', spans: [['x', 1, 2]] }, { scheme: 'B', spans: [] }],
  [{ name: 'a', start: 10, end: 20, scheme: 'S' }, { name: 'b', start: 5, scheme: 'S' }, ['c', 15, 25], { name: '', start: 1 }, 'x', null, { title: 't', start: 'abc' }, { name: 'd', start: 30, end: 20 },
    { name: 'e', start: '미정', startHint: 40, end: 35 }, { name: 'f', start: 50, end: 60, certainty: 'weird', alternatives: [{ start: 1 }] }, { name: 'g' }, { name: 'h' }, { name: 'i', end: 'xyz' }],
  [{ scheme: '', spans: [['a', 1, 5], ['b', 1, 6]] }, { scheme: 'X', spans: [['c', 1, 2]] }],
  [{ scheme: 'Y', spans: [{ name: 'u', start: '미정', end: '미정', endHint: 9 }, ['v', '1592-05-23', '1593-01-01', ' m ']] }],
  { scheme: 'Z', spans: [['one', 1, 2]] }]) {
  add5b('readPhases', [v], ([x]) => HT.readPhases(x));
}
for (const v of [null, '', 'x', {},
  [{ name: '왕', id: 'king', tier: 7, aliases: ['국왕', '왕', ' 국왕 ', ''], description: ' d ' }, { name: '황제', tier: '8' }, { name: '황제' }, { name: 'x', id: 'bad id' }, { name: '' }, null, [1], 'x',
    { name: 'y', tier: 'abc' }, { name: 'z', tier: '' }, { name: 'w', aliases: '가, 나,가' }, { name: 'v', id: 'king' }, { name: 'u', tier: 0, aliases: 5 }]]) {
  add5b('readRankDefs', [v], ([x]) => HT.readRankDefs(x));
}
for (const v of [null, '', 'x', {},
  [['왕', 100, 200, 'n'], '공', { rank: '후', start: 50 }, { name: '', start: 1 }, null, 5, { name: 'a', start: 'abc' }, { name: 'b', start: 300, end: 250 }, { name: 'c', start: '미정', startHint: 400, end: 350 },
    { name: 'd', start: '미정', end: '미정' }, { name: 'e', start: 500, end: '미정', endHint: 450 }, { name: 'f', start: 600, end: 700, certainty: 'weird' }, { name: 'g', end: 650 }, { name: 'h', start: 800, end: 'xyz' }],
  [{ name: 'first' }, { name: 'second', start: 10 }, { name: 'third', start: 5 }],
  [{ name: 'a', start: 1, end: 10 }, { name: 'b', start: 5 }], [{ name: 'a', start: 1, end: 10 }, { name: 'b', start: '미정', end: 8 }], [{ name: 'a', start: 1 }, { name: 'b', start: 1 }],
  [{ name: 'a', start: 5, end: 10 }, { name: 'b', start: '미정', end: 3 }], [{ name: 'a', start: '1592-05-23', end: '1600-01-01' }, { name: 'b', start: '미정' }]]) {
  add5b('readRanks', [v], ([x]) => HT.readRanks(x));
}
// 6단계 걸음 2(세계사 결정 D2 · D3 · D8): 종교(지위 변천과 같은 몸 · 글의 낱말만 다름) · 지도자 표기 낱말 · 이름 번호 · 문화권 사전의 낱말 · 이름 번호가 있는 줄의 대수 · 기본 표기의 'n세'
for (const v of [null, '', 'x', {},
  [['옛 신앙', null, 180, 'n'], { faith: '새 교회', start: 180 }, { name: '' }, 5, { name: 'a', start: 'abc' }, { name: 'b', start: 300, end: 250 }, { name: 'c', start: '미정', end: '미정' }, { name: 'd', end: 650 }, { name: 'e', start: 600, end: 700, certainty: 'weird' }],
  [{ name: 'a', start: 1, end: 10 }, { name: 'b', start: 5 }], [{ name: 'a', start: 5, end: 10 }, { name: 'b', start: '미정', end: 3 }], [{ name: 'x', start: '미정', startHint: 400, end: 350 }], [{ name: 'a', start: 1 }, { name: 'b', start: 1 }]]) {
  add('readFaiths', [v], ([x]) => HT.readFaiths(x));
}
for (const v of [null, '', 'x', 5, [], ['치세명'], {}, { temple: ' 치세명 ', title: '', given: '본명' }, { temple: 7, era: 'x', given: null }, { bad: 1, worse: 2 }, { title: ' ' }, { given: ['본', '명'] }]) {
  add('readLeaderLabels', [v], ([x], w) => HT.readLeaderLabels(x, w));
}
for (const v of [null, '', ' ', 3, '4', ' 5 ', 0, -1, 1.5, '1.5', '여덟', true, [2], {}, '1e2', 'Infinity', 1e21, '0x10']) {
  add('readRegnal', [v], ([x]) => { const n = HT.readRegnal(x); return Number.isNaN(n) ? 'NaN' : n; });
}
for (const v of [[{ id: 'mist-sea', name: '안개 바다권', order: 1, leaderLabels: { temple: '치세명', title: ' ', bad: 1 } }, { id: 'ash', leaderLabels: '치세명' }, { id: 'ice', leaderLabels: { given: '본명' }, description: ' d ' }, { id: 'mist-sea', leaderLabels: { temple: 'x' } }]]) {
  add('readSpheres', [v], ([x]) => HT.readSpheres(x));
}
for (const v of [[{}, { regnal: 2 }, {}], [{ ordinal: 3, regnal: 1 }, {}, { ordinalUnknown: true }, {}], [{ regnal: null }, {}, {}]]) add('numberLeaders', [v], ([x]) => HT.numberLeaders(x));
for (const v of [{ name: '헨리', regnal: 8 }, { temple: '태조', regnal: 1 }, { name: '', given: '이도', regnal: 4 }, { name: '세종' }, { regnal: 3 }, { name: '서리', regnal: 3, ordinal: 12 }]) add('leaderLabel', [v], ([x]) => HT.leaderLabel(x));
const partOfs = ['고조선', ' 고조선 ', '', null, { polity: 'single' },
  ['a', '', null, 5, { polity: 'b', start: 100, end: 200, note: ' n ', relation: '조공', nest: true }, { to: 'c', start: '미정', end: '미정', endHint: 300 }, { name: 'd', start: 'abc', end: 'xyz' },
    { polity: '', certainty: 'weird' }, { polity: 'e', relation: 'xyz', nest: 'yes', certainty: 'estimated', alternatives: [{ start: 1 }] }, [1], { polity: 'f', start: '1592-05-23', note: 0 },
    { polity: 'g', relation: 'member', nest: false, start: '미정', startHint: 50, end: 40 }, { polity: 7 }]];
for (const v of partOfs) {
  add5b('readPartOf', [v], ([x], w) => HT.readPartOf(x, { warn: w }));
  add5b('readPartOf:relation', [v], ([x], w) => HT.readPartOf(x, { relation: true, warn: w }));
}
const unknownWords = [true, false, '미상', ' 미정 ', '불명', '모름', '?', 'unknown', 'UNKNOWN', `un${KELVIN}nown`, '미상?', '', null, 3, ['미상'], 'tbd'];
for (const v of unknownWords) {
  add5b('isUnknownOrdinal', [v], ([x]) => HT.isUnknownOrdinal(x));
  add5b('isUnknownWho', [v], ([x]) => HT.isUnknownWho(x));
}
for (const v of ['son', '아들', '왕자', '작은 아버지', ' 사위 ', 'xyz', '', null]) add5b('kinId', [v], ([x]) => HT.kinId(x));
for (const v of ['hereditary', '세습', '섭정 뒤 오름', '섭정뒤', '섭정 뒤', 'xyz']) add5b('accessionHow', [v], ([x]) => HT.accessionHow(x));
for (const v of ['father', '부', '양 아버지', '후손', 'xyz']) add5b('parentRole', [v], ([x]) => HT.parentRole(x));
const personRefs = ['고려', 'a@b', ':x', 'a:', 'a:b', 'a : b', ' a:b ', 'a:b@1592', 'a: b @ 1592-05-23', 'a:@1592', 'a: @1592', 'a:b@', `a:b@x${ch(10)}y`, `a:b@ ${ch(10)} 1592`,
  'a:b:c', 'a:b@c@d', `a${ch(10)}b:c`, '고려:태조@918', `고려${ch(0x3000)}:${ch(0x3000)}태조`, 'a:b@abc', 5, 0, null, '', '  ', { polity: '고려', leader: '태조' }, { polity: '', leader: 'x' },
  { name: 'x' }, { polity: 'p', name: 'l' }, { polity: ' p ', leader: ' l ', track: ' t ', start: '918-07-25', startAt: 'x' }, { polity: 'p', leader: 'l', start: '' }, { polity: 'p', leader: 'l', start: 'abc' },
  { polity: 'p' }, [], true];
for (const v of personRefs) add5b('readPersonRef', [v], ([x]) => HT.readPersonRef(x));
// 정규식 그 자체(다듬지 않은 글 — readPersonRef는 늘 다듬어 넘기므로 닿지 않는 갈래: 빈칸뿐인 뒤쪽 · 앞 빈칸): 원본 core.js에 같은 정규식이 있는지 먼저 본다
const PERSON_RE_SRC = '/^([^:@]+?)\\s*:\\s*([^@]+?)\\s*(?:@\\s*(.+))?$/';
if (!fs.readFileSync(path.resolve(here, '..', '..', 'js', 'core.js'), 'utf8').includes(PERSON_RE_SRC)) throw new Error('core.js의 readPersonRef 정규식이 바뀌었습니다 — 표본을 고치세요');
const PERSON_RE = /^([^:@]+?)\s*:\s*([^@]+?)\s*(?:@\s*(.+))?$/;
for (const v of ['a:b@ ', 'a:b@  ', `a:b@ ${ch(10)}`, 'a:  ', ' :b', ' a :b', 'a: ', 'a:b ', 'a:b @ x ', `a:b@${ch(0x2029)}`, 'a:b', 'a:b@1', 'a: @1', 'x']) {
  add5b('personCellRe', [v], ([x]) => { const m = x.match(PERSON_RE); return m ? [m[1], m[2], m[3] ?? null] : null; });
}
for (const v of [null, '', 'x', { polity: 'a', leader: 'b' }, { polity: 'a', leader: 'b', start: 918 }, { polity: 'a', leader: 'b', start: 918, startAt: '918-07-25' }, { leader: 'b' }, 0, { polity: 'a', leader: 'b', start: 0 }]) {
  add5b('personRefText', [v], ([x]) => HT.personRefText(x));
}
for (const v of [null, '', '미상', ' unknown ', 'x', 5, [1], {}, { kin: '아들', how: '세습', from: '고려:태조', note: ' n ' }, { kin: 'xyz', how: '찬탈' }, { kinUnknown: true, how: '미상', from: '미상' },
  { from: { polity: 'a' } }, { fromUnknown: true }, { kin: ' ', how: '' }, { from: 'name' }, { from: ':x' }, { from: 0 }, { kin: '작은 아버지', how: '섭정 뒤' }]) {
  add5b('readAccession', [v], ([x], w) => HT.readAccession(x, w));
}
const kinRows = [null, '', 'x', '미상', [
  'a', { who: '미상' }, { whoUnknown: true, as: '부' }, { name: 'b', as: '양아버지', certainty: '추정', note: ' n ' }, { who: 'c', as: 'ancestor', gen: 3.6 }, { who: 'd', as: 'father', gen: 2 },
  { who: 'e', as: 'ancestor', gen: 'x' }, { who: 'f', as: 'ancestor', gen: 0 }, { who: 'g', certainty: 'weird' }, { who: 'h', certainty: 'accepted' }, { who: 'i', certainty: '통설' }, {}, { who: '' }, null, 5, [1],
  { who: { polity: 'p', leader: 'l', start: 900 } }, { who: 'p:l@900', gen: 2, as: '몇대손' }, { whoUnknown: true, gen: 2 }, { who: 'j', as: '후손', gen: '' }]];
for (const v of kinRows) add5b('readParents', [v], ([x], w) => HT.readParents(x, w));
for (const v of [null, '', 'x', ['a', { who: 'b', start: 1500, end: 1520, note: 'n' }, { who: 'c', start: '미정', end: '1600-03-01' }, { who: 'd', start: 'abc', end: 'xyz' }, { who: 'e', start: 1600, end: 1500 },
  { who: '미상', start: 1, end: 2 }, {}, { who: 'f', startUnknown: true, startHint: 1400, endUnknown: true }, { who: 'g', start: '1592-05-23', end: '1592-05-23' }]]) {
  add5b('readSpouses', [v], ([x], w) => HT.readSpouses(x, w));
}
for (const v of [null, '', '  ', 38.5, '38.5', ' 38.5 ', 'x', true, [1], {}, '1e3', 0, '0x10']) {
  add5b('readNorthSouth', [v], ([x]) => { const n = HT.readNorthSouth(x); return Number.isNaN(n) ? 'NaN' : n; });
}
// 정규화(합성) — 시대의 모든 갈래(옛 형식의 기관 · 문화 · 왕조 · 지도자 · 내각 · 연호 · 도읍 · 시기 · 지위 · 미정 · 이설 · 실재성 · 부분 승계 · 사람 잇기 · 소속 · 접기) · 기관의 크기 짐작 · 가문 · 지위 사전
const zoneNames = ['상하이 공동 조계', '조차지', '租界', '租借地', '거류지', '居留地', '일본 공사관 구역', '공사관구역', '경제 특구', '부산 왜관', '倭館', '그냥 기관'];
const head = (id, more) => Object.assign({ format: 'history-timeline-dlc', formatVersion: 3, id, name: id, tracks: [{ id: 't1' }, { id: 't2' }] }, more);
for (const raw of [
  head('p5b', {
    rankDefs: 'x',
    houses: [{ name: '왕씨', surname: '왕', seat: '개성', founder: '왕건', parent: ' 본가 ', track: 't1', people: 'p', tags: '가, 나，가', color: '#abc', description: 'd', wiki: 'w', names: ['Wang', { text: '' }] },
      { name: '왕씨' }, { id: 'bad id', name: 'x' }, {}, null, 'x', [1], { id: 'h1', tags: ['a', 'a', ''], color: 'red' }, { id: 'h1', name: '겹침' }],
    periods: [
      { kind: 'overlay', name: '통감부', track: 't1', start: 1906, end: 1910, partOf: '대한제국' },
      { kind: 'overlay', title: '부산 왜관', track: 't1', start: 1607, end: 1876, host: [{ polity: '조선', start: '미정', end: '미정' }], scale: 'agency' },
      { kind: 'culture', name: '빗살무늬', track: 't1', start: -8000, end: -1500, successors: 'a, b,,', succeeds: ['x', { from: 'y', type: 'direct' }, { from: '' }, 5, null], people: '예맥', color: '#ddd' },
      { kind: 'dynasty', title: '카페 왕조', track: 't1', start: 987, end: 1328, partOf: ['프랑스'], house: '카페가', names: ['Capétiens'] },
      { kind: 'dynasty', name: '빈 왕조', track: 't1', start: 1 },
      {
        name: '고려', track: 't1', start: 918, end: 1392, kind: '조공국', wiki: ' w ', certainty: 'accepted', historicity: '실재', historicityNote: ' 근거 ',
        partOf: [{ polity: '송', relation: '조공', start: 962, end: 1126 }, { polity: '요', relation: 'xyz', nest: 'yes' }, 'x', 5],
        leaders: [['태조', 918, 943], { temple: '혜종', start: 943, end: 945, ordinal: 2, person: 'p1', accession: { kin: '아들', how: '세습' }, parents: [{ who: '태조', as: '부' }, { who: '' }], spouses: ['x', { who: 'y', start: 950, end: 940 }],
          house: '왕씨', rank: '왕', dynasty: 'd', names: ['Hyejong', ''], certainty: 'estimated', alternatives: [{ start: 944 }] }, { title: '정종', start: 945, end: 949 }, { given: '소', start: 949, end: 975, ordinalUnknown: true },
          { name: '경종', start: 975, end: 981 }, { name: '성종', start: 981, end: 997, ordinal: '미상' }, { name: '목종', start: 997, end: 1009, ordinal: 7.4 }, { name: '현종', start: '미정', end: '미정' },
          { name: '', start: 1 }, { name: 'x', start: 'abc' }, { name: 'y' }, { name: 'z', start: 1010, end: 'abc' }, { name: 'w', start: 1020, person: '미상' }, { name: 'v', start: 1030, person: { polity: 'a' } },
          { name: 'u', start: 1040, accession: 'x', person: '고려:태조@918' }, { name: 't', start: 1050, accession: '미상', parents: '미상', spouses: [{ whoUnknown: true }] }, 'str', 5, null, { name: 's', start: 1060, certainty: 'weird' }],
        cabinets: [['내각1', 1000, 1010, 'n'], { name: '내각2', start: 1010, house: '왕씨', person: 'p2', names: ['C2'], accession: { kin: '아들' } }, { name: '내각3', start: '미정', end: '미정' }],
        people: '고려인', house: '왕씨',
        succeeds: ['태봉', { from: '태봉' }, { from: '신라', type: '부분 승계', degree: '강', parts: '지배층, 영토, 무엇' }, { from: '' }, null],
        eras: [['천수', 918, 933], { name: '광덕', start: 950, end: 951, house: 'x', person: 'y', names: ['Gwangdeok'] }, { name: '빈 연호' }],
        capitals: [['개경', 919], { city: '서경', start: 922, role: '배도' }, ['', 1], { city: '강화', start: 1232, end: 1270, role: '피난', certainty: 'weird' }, { city: 'x', start: '미정', end: '미정' }, 'y'],
        phases: [{ scheme: '학설A', spans: [['전기', 918, 1170], ['후기', 1170, 1400]] }, { scheme: '학설A', spans: [] }, 'x'],
        ranks: [['왕', null, null], { name: '황제', start: 900 }, { name: '', start: 1 }],
        color: '#123', description: 'd', names: [{ text: 'Goryeo', lang: 'en', kind: 'roman' }, { text: 'x', lang: 'bad tag!' }], tags: '왕조, 나라，왕조', northSouth: '38.5',
      },
      { title: '이름은 title', track: 't1', start: 1, kind: 'xyz', historicity: '전설', northSouth: 'x', partOf: [{ polity: 'p', nest: true, start: 1 }], leaders: [], reigns: [['x', 1, 2]] },
      { name: 'p3', track: 't1', start: 1, partOf: [{ polity: 'q', nest: true }], reigns: [['r1', 1, 2]] },
      { name: 'p4', track: 't1', start: 1, partOf: [{ polity: 'q', start: '미정', end: '미정' }], historicity: 'xyz', kind: 'state' },
      { name: 'p4b', track: 't1', start: 1, partOf: [{ polity: 'q', nest: true }, { polity: 'r', nest: true }], kind: '나라' },
      { name: 'p5', track: 'nope', start: 1 }, { name: '', track: 't1', start: 1 }, null, [1, 2], 'x', { name: 'p6', track: 't1', start: 'abc' },
      { name: 'p7', track: 't1', start: 1, end: 10, ongoing: true, phases: [['a', 1, 100]], ranks: [['r', 1, 100]] },
      { name: 'p8', track: 't1', start: '미정', startHint: 5, end: 10, phases: [['a', -100, 5]], ranks: [{ name: 'r', start: -50, end: 20 }] },
      { name: 'p8b', track: 't1', start: 5, end: '미정', phases: [['a', 5, 900]] },
      { name: 'p8c', track: 't1', start: 5, phases: [['a', 5, 6]] },
      { name: 'p8d', track: 't1', start: '1592-05-23', end: '1592-12-01', ranks: [['r', '1592-06-01', '1592-12-31']] },
      { name: 'p9', track: 't2', start: 100, kind: 'vassal', historicity: 'legendary', northSouth: 40, tags: ['a', 'a', ' ', 'b'], legendary: true, debate: ' 쟁점 ' },
      { id: 'p-fixed', name: 'p10', track: 't1', start: 5 }, { id: 'p-fixed', name: 'p11', track: 't1', start: 6 }, { id: 'bad id', name: 'p12', track: 't1', start: 7 },
      { name: 'p13', track: 't1', start: 1, end: 3, phases: 'x', ranks: 'y', capitals: 'z', leaders: 'w', succeeds: 's', partOf: '' },
      // 과제 5c(얹힌 몫 5c-2) — 5b 갈래 덮개: 날짜 글 칸의 startAt · endAt · 칸 미정의 배치용 연도 · 도읍 미정의 startHint · checkPartOf의 객체 하나 · 트랙 없는 옛 형식 overlay
      { name: 'p20', track: 't1', start: 1392, end: 1500, leaders: [{ name: 'd1', start: '1392-07-17', end: '1400-01-01' }], cabinets: [{ name: 'd1', start: '1392-07-17', end: '1400-01-01' }],
        eras: [{ name: 'd1', start: '1392-07-17', end: '1400-01-01' }, { name: 'h1', start: '미정', startHint: 1000 }], capitals: [{ city: 'x', start: '미정', startHint: 1500 }],
        partOf: { polity: 'q', relation: 'xyz' } },
      { kind: 'overlay', name: 'o' },
    ],
    organs: [{ name: '조선총독부', track: 't1', start: 1910, end: 1945, host: '조선', scale: 'agency', color: '#abc', description: 'd', note: 'n', wiki: 'w', certainty: 'estimated' },
      ...zoneNames.map((name, k) => ({ name, track: 't1', start: 1863 + k, end: 1941, partOf: k === 0 ? [{ polity: '청', start: 1863, end: 1912 }, { polity: '중화민국', start: '미정', end: '미정' }] : undefined })),
      { name: 'zone 적음', track: 't1', start: 1, scale: 'zone', host: 'h' }, { name: 'x', track: 'nope', start: 1 }, null, {}, { title: 't', track: 't1', start: 1, end: 0 }],
    cultures: [{ name: '고인돌', track: 't1', start: -1500, end: -300, successors: ['a', '', ' b '], certainty: 'estimated', startRange: [-1600, -1400] },
      { name: 'c2', track: 't1', start: 1, color: '#fff', description: 'd', wiki: 'w', succeeds: 'x', people: ' 맥 ' }, { name: 'c3', start: 1 }, 'x'],
    dynasties: [{ name: '부르봉', track: 't1', start: 1589, end: 1792, polities: [{ polity: '프랑스', start: 1589, end: 1792 }], house: 'x', color: '#abc', description: 'd', note: 'n', wiki: 'w', names: ['Bourbon'] },
      { name: 'y2', track: 't1', start: 1, rules: '스페인' }, { name: 'y3', track: 't1', start: 1 }, { name: 'y4', track: 't1', start: 1, host: [{ polity: 'h', start: '미정', end: '미정' }] }, { title: '', track: 't1', start: 1 }],
  }),
  head('rd', { rankDefs: [{ name: '왕', tier: 7 }, { name: '왕' }] }),
  head('h-only', { houses: [{ name: '가문만' }] }),
  head('c-only', { cultures: [{ name: '문화만', track: 't1', start: 1 }] }),
]) add5b('normalizePack', [raw], ([x]) => norm(x));

// ── 과제 5c: 사건 · 인물 · 이름 · 문서 · 단체 · 렌즈 재료와 그 도움 함수 ──
// add5c: add와 같고, 그 표본을 읽는 동안 맞은 손 옮김 정규식의 갈래(REGEX_5C)를 hits로 싣는다(Rust 검사가 '<함수>/<갈래>'마다 맞은 표본 ≥ 1을 단언).
// REGEX_5C의 정규식은 원본 core.js에 글자 그대로 있어야 한다(바뀌면 멈춤 — 손 옮김을 다시 볼 때).
function add5c(fn, args, call) {
  hits5c = new Set();
  add(fn, args, call);
  const h = hits5c;
  hits5c = null;
  if (h.size) cases[cases.length - 1].hits = [...h].sort();
}
{
  const coreText = fs.readFileSync(path.resolve(here, '..', '..', 'js', 'core.js'), 'utf8');
  for (const [re] of REGEX_5C) if (!coreText.includes(String(re))) throw new Error(`core.js에 정규식 ${re}가 없습니다 — 손 옮김과 표본을 다시 보세요`);
}
const NL = ch(10);
const CR = ch(13);
const LS = ch(0x2028);
const IDEO = ch(0x3000);
const ENDASH = ch(0x2013);
const b64 = head => Buffer.from([...head].map(c => c.charCodeAt(0)).concat([0, 0])).toString('base64');
const PNG = 'data:image/png;base64,';

// 낱말 표(조약 · 단체 · 법)
for (const v of ['peace', '강화', '강화 조약', ' 평화 ', 'xyz', '', null, 'constructor']) add5c('treatyType', [v], ([x]) => HT.treatyType(x));
for (const v of ['expired', '기한 만료', '기한만료', '파기', 'xyz', '']) add5c('treatyEndReason', [v], ([x]) => HT.treatyEndReason(x));
for (const v of ['territory', '영토', '배상금', '군 대', 'xyz', '']) add5c('articleTag', [v], ([x]) => HT.articleTag(x));
for (const v of ['faction', '붕당·파벌', '붕당', '실권 집단', '연맹', '모임', '', null]) add5c('groupType', [v], ([x]) => HT.groupType(x));
for (const v of ['split', '갈라짐', '갈라져 나옴', '?', '방식 미상', 'xyz', '']) add5c('groupHow', [v], ([x]) => HT.groupHow(x));
for (const v of ['enact', '개정', '공포', '혁 파', 'xyz', '']) add5c('lawAct', [v], ([x]) => HT.lawAct(x));

// 서명자 · 조항 · 조약
for (const v of [
  `A(왕); B（대신）; C ( 직함 ) ; D(); E (  )`, `F(x)${NL}G`, 'H(I)(J)', 'K)(L)', 'M(N)O', '(P)', `Q${IDEO}(R)`, 'S（T)', `U${LS}V(W)`, 'X(Y)；Z(1)',
  [{ name: ' U ', title: ' t ' }, { name: '' }, { title: 'x' }, null, 5, 'V(W)', [1]], { name: 'X' }, { name: 'Y', title: '' }, 5, ' ', '', null,
]) add5c('readSigners', [v], ([x]) => HT.readSigners(x));
const articleText = [
  '전문 글', '제1조 (목적) 이 조약은', '둘째 줄', '제 2 관【정의】 정의 글', '제3항: 본문', 'Article 4. Text four', 'ART. 5 : five', 'Art.6：six', 'article5 nope',
  '제6조( ) 빈 제목', `제7조 [긴] 대괄호`, `제8조 (${'x'.repeat(61)}) 긴 제목`, `제9조${CR}`, '(', '줄) 바뀜', '제10조（전각）본문', '제11조(', ')', '제12조', '', 'ARTICLE  13 Big',
].join(NL);
for (const v of [articleText, '', null, 5, `제1조 (a)${CR}${NL}제2조 (b)`, '번호 없는 글만', `${NL}${NL}제1조`]) add5c('splitArticles', [v], ([x]) => HT.splitArticles(x));
for (const v of [
  null, 'x', [1], {}, { formal: '' },
  { formal: ' 정식 ', type: '강화 조약', unequal: '불평등', ratified: '1592-05-23', effective: 'abc', endReason: '기한 만료', place: ' 장소 ', languages: `한문, 만주어，몽골어、`,
    parties: ['갑', 'korea:을', { track: 't', polity: '병', side: 2.6, role: ' 주 ', signatories: 'A(왕); B' }, { name: 'x:y' }, { polity: '', side: 'z' }, '', null, { side: -1, polity: 'q' }, ':z', 'a:', `a${NL}b:c`, `d:e${NL}f`, 5],
    articles: `제1조 하나${NL}제2조 (제목) 둘`, concludes: ' c ', supersedes: 's' },
  { type: 'xyz', endReason: 'xyz', unequal: true, ratified: '음력 1592-04-13', ratifiedAt: '음력 1592-04-13', effective: 1600, effectiveAt: '1600-03-01',
    articles: ['제1조 (목적) 본문', { no: ' 2 ', title: 't', tag: '할양', text: ` a${CR}${NL}b ` }, { tag: 'xyz' }, {}, null, 5, [1], { text: 7 }] },
  { unequal: 'TRUE', parties: 'single', languages: ['a', ' ', null, 5] },
  { unequal: '네', parties: { polity: 'obj', side: '1' } },
  { unequal: 'no', parties: [{ polity: 'p', side: 0 }, { polity: 'p2', side: '' }, { track: 'tt' }], articles: 5 },
  { unequal: '예', concludes: 'e1' },
]) add5c('readTreaty', [v], ([x], w) => HT.readTreaty(x, w));
for (const v of [
  null, 'x', {}, [1],
  { name: ' 법 ', act: '공포', articles: `제1조${CR}${NL}제2조${NL}${NL} 제3조 ${CR}${CR}${NL}제4조${CR}x`, note: ' n ' },
  { act: 'xyz', articles: ['a', 5, { no: '1', title: 't', text: `x${CR}y` }, {}, null, [1], ' ', true] },
  { articles: 7, act: ' ' },
]) add5c('readLaw', [v], ([x], w) => HT.readLaw(x, w));
for (const v of [
  null, {}, [1], 'x',
  { office: ' 왕 ', results: ['갑', ['을', '1,234', '5', '당선'], { who: '병', votes: ch(0xff11), seats: -1, won: 'YES' }, { name: '정', votes: ` 12${IDEO}345 `, seats: '3，000', won: 'True' },
    { votes: '5' }, { won: true }, { seats: ' ' }, {}, null, 5, { who: '무', votes: 'x', seats: true }, ['기', null, '', '이김'], { who: '경', won: '승리' }, { who: '신', won: '예' }, { who: '임', won: '네' }, { who: '계', won: 'true' }], note: 'n' },
  { results: { who: 'single', won: true } }, { results: 'x' }, { office: '', note: '' },
]) add5c('readElection', [v], ([x], w) => HT.readElection(x, w));

// 주제 사전 · 주제 꼬리표
for (const v of [
  null, '', 'x', 5,
  [{ name: '세제', id: 'tax', color: '#abc', kind: ' 갈래 ', description: 'd', names: ['Tax', { text: '' }] }, { id: 'faction', hidden: true }, { id: 'bad id', hidden: true }, { name: 'n', id: 'bad id' },
    { name: 'n' }, { name: 'n' }, { hidden: true }, {}, null, [1], 'x', { name: 'h', hidden: true, color: '#fff', kind: 'k' }, { id: 'tax', name: '중복' }, { id: 'faction', hidden: true }, { name: 'c', color: 'red' }],
]) add5c('readThemeDefs', [v], ([x]) => HT.readThemeDefs(x));
for (const v of [null, '', 'a, b，a', ['a', ' b ', null, {}, [1], 5, '', 'a'], 5, {}, true]) add5c('readThemeList', [v], ([x]) => HT.readThemeList(x));

// 단체의 나라 줄 · 앞선 단체 · 제도 칸
const polityRows = [
  'a', 'korea:b', ' ', '', null, 5, { polity: 'c', track: ' t ', start: 100, end: 200, role: ' 맹주 ', note: ' n ' }, { name: 'd', start: '미정', end: '미정', endHint: 300 }, { polity: 'k:e' },
  { polity: '' }, { polity: 'f', start: 'abc', end: 'xyz' }, { polity: 'g', start: 300, end: 200 }, { polity: 'h', start: '미정', startHint: 400, end: 350 }, [1], { polity: 'i', start: '1592-05-23', end: '1593-01-01' },
  { track: 'tt', polity: 'k:j' }, { polity: 'l', role: '' },
];
for (const v of [polityRows, 'x', '', null, { polity: 'single' }]) {
  add5c('readPolityRows:role', [v], ([x], w) => HT.readPolityRows(x, { role: true, warn: w, what: '구성 나라' }));
  add5c('readPolityRows', [v], ([x], w) => HT.readPolityRows(x, { warn: w, what: '있던 나라' }));
}
for (const v of [['a', ' a ', { group: 'b', how: '분열', note: ' n ' }, { name: 'c', how: 'xyz' }, { group: '' }, '', null, 5, [1], { group: 'd', how: '?' }, { group: 'e', how: ' ' }], 'single', '', null, { group: 'x' }]) {
  add5c('readGroupFrom', [v], ([x], w) => HT.readGroupFrom(x, w));
}
for (const [p, t] of [['a', 't'], ['k:b', 't'], [{ polity: 'c', track: '' }, 't'], [{ name: 'd' }, ''], [{ track: 'x', polity: 'e' }, 't'], ['', 't'], [null, 't'], [[1], ''], ['  ', ''], [{}, 't'], [5, 't'], [{ polity: ' f ', track: ' g ' }, null]]) {
  add5c('readInstPolity', [p, t], ([x, y]) => HT.readInstPolity(x, y));
}
for (const v of [
  null, '', 'x', {},
  [['과거', 100, 200, '메모'], '이름만', { name: 'b', start: '미정', startHint: 150, end: 120 }, { title: 'c', start: 300, end: 250 }, { name: 'd', start: 300, end: '3세기 말' }, { name: 'e', start: 'abc' },
    { name: '' }, null, 5, { name: 'f', from: 'k:p', note: ' n ' }, { name: 'g', from: { polity: 'q', name: ' 원 제도 ', track: 't' } }, { name: 'h', from: { name: 'only' } }, { name: 'i', from: [1] },
    { name: 'j', start: 100, certainty: 'weird' }, { name: 'k', start: 100 }, { name: 'l', start: 90, end: 150 }, { name: 'm', from: '' }, { name: 'n', from: 7 }, { name: 'o', start: '미정', end: '미정' }],
  [{ name: 'p', start: '3세기', end: '4세기 말' }, { name: 'q', start: 500, end: '미정', endHint: 450 }],
]) add5c('readInstSpans', [v], ([x]) => HT.readInstSpans(x));

// 글자 범위 · 구성원 · 좌표 · 자리 · 문서 키
for (const v of ['U+4E00', 'u+4e00-9fff', ` U+F1A00 ${ENDASH} F1A0B `, 'U+10~U+20', 'U+10-u+20', 'U+1234567', 'U+', 'U+20-10', 'U+110000', 'U+10FFFF', 'U+4E00-', 'U+4E00-U+', 'x', null,
  'U+4E00 9FFF', 'U+ 4E00', `${IDEO}U+AC00${IDEO}`, 'U+0-0', 'U+ABCDEF', 'U+4E00--9FFF', 5]) {
  add5c('parseRange', [v], ([x]) => HT.parseRange(x));
}
for (const v of [['a', ' a ', '미상', { polity: 'p', leader: 'l' }, { polity: 'p', leader: 'l' }, 5, true, [1], {}, null, '', 'k:l@900', ' ', 'p:l'], 'a, b，미상', '', null, { polity: 'p', leader: 'l', start: 900 }, 7]) {
  add5c('readGroupPeople', [v], ([x], w) => HT.readGroupPeople(x, w));
}
for (const v of [[1, 2], ['1', '2'], '1, 2', '1，2', ' 1 2 ', '1,,2', [1], [1, 2, 3], ['', 2], [null, 2], ['a', 2], [[5], 2], 'x', null, 5, '1e3, -2', `3${IDEO}4`, ['0x10', ' 2 '], '']) {
  add5c('readCoords', [v], ([x]) => HT.readCoords(x));
}
for (const v of [0, 1, 0.5, 0.12345, 0.0005, '0.3', ' 0.3 ', '', ' ', -0.1, 1.1, 'x', null, true, [0.5], '1e-1']) add5c('readSpot', [v], ([x]) => HT.readSpot(x));
for (const v of ['a', '', '//x', 'a//b', 'a/b', 'x'.repeat(299), 'x'.repeat(300), 'cell:a:leaders:x@1//sub', ' ', '/', 'a///b']) add5c('docKeyValid', [v], ([x]) => HT.docKey.valid(x));

// 문서 그림 · 지도 · 글꼴(형식 3 목록 — report.err · warn을 차례대로 싣는다)
const reportOf = read => ([x]) => {
  const notes = [];
  const out = read(x, { err: (m, i) => notes.push(['err', m, i]), warn: (m, i) => notes.push(['warn', m, i]) });
  return { out, notes };
};
add5c('readImages', [[
  { name: '그림', src: ` ${PNG}AAAA `, caption: 'c', alt: 'a'.repeat(510), credit: ' cr ', width: 100, height: '200' }, { name: '그림', src: `${PNG}BBBB`, width: 0, height: 1.5 },
  { id: 'bad id', src: 'x' }, { id: 'img2', src: '' }, { id: 'img2b', src: 'data:image/gif;base64,AA' }, { id: 'g3', src: `${PNG}CC` }, { id: 'g3', src: `${PNG}DD` }, {}, null, [1],
  { name: 'w', src: `${PNG}EE`, width: 'x', height: 20001 }, { name: 'v', src: 5 }, { id: 'u', src: `${PNG}FF==`, width: '20000', caption: ' ' },
]], reportOf(HT.readImages));
const square = [[0, 0], [10, 0], [10, 10], [0, 0]];
const tri = [[0, 0], [1, 0], [1, 1]];
add5c('readMaps', [[
  { name: '대륙', size: [1000, 800], image: `${PNG}AAAA`, levels: ['나라', { id: '도', name: '도 이름' }, { name: '군' }, '나라', {}, 5], regions: [
    { id: 'r1', name: '하나', level: '나라', shape: square, start: 100, end: 200, names: ['One'], note: ' n ' },
    { id: 'r2', level: '도', parent: 'r1', shape: [[[0, 0], [5, 0], [5, 5]], [[1, 1], [2, 1]], 'x', [[0, 0], [1, 'a'], [2, 2]], []] },
    { id: 'r3', level: '군', parent: 'r4', shape: tri }, { id: 'r4', level: '군', parent: 'r3', shape: tri },
    { id: 'r5', level: '나라', parent: 'r2', shape: [[0, 0], [2000, 0], [1, 1]] }, { id: 'r6', parent: 'r6', shape: tri },
    { id: 'r7', parent: 'nope', level: 'xyz', shape: tri, start: 'abc' }, { id: 'r1', shape: tri }, { shape: [] }, null, { id: 'r8', shape: [] }, { id: 'r9', shape: 'x' },
    { id: 'r10', shape: [[0, 0], [1, 0]] }, { id: 'r11', shape: tri, end: 50 }, { id: 'r12', shape: [[0, 0], [1, 0], [0, 0]] }, { id: 'r13', parent: 'r12', level: '도', shape: tri, start: 10, end: 5 },
    { id: 'r14', shape: [[0, 0], [1], [1, 1]] }, { id: 'r15', shape: tri, start: 1, end: 1 }, { id: 'r16', parent: 'r2', level: '군', shape: tri, start: '1592-05-23', ongoing: true }],
  frames: [
    { year: 300, owners: { r1: '갑', r2: 'k:을', r3: null, r4: ' None ', nope: 'x', r5: '', r6: 5, r7: { polity: 'p', track: 't' } }, image: 'data:image/jpeg;base64,BBBB', note: ' n ' },
    { year: '1592-05-23' }, { year: 300, note: 'dup' }, { year: 'abc' }, { year: '' }, null, { year: 100, owners: 'x' }, { year: 50, owners: [1], image: 'bad' }, { year: '1592-05-23', yearAt: '1592-05-23' }, [1]],
  places: ['a', { id: 'b' }, { name: 'c' }, 'a', '', null, 5, [1]], description: ' d ', note: 'n', source: 's', wiki: ' w ' },
  { name: '경위', crs: 'lonlat', size: [1, 2], image: `${PNG}AAAA`, regions: [{ id: 'l1', shape: [[200, 0], [1, 1], [2, 2]] }, { id: 'l2', shape: [[[0, 0], [1, 0], [1, 1]], [[0, 0], [0, 100], [1, 1]]] }],
    frames: [{ year: 1, image: 'x' }], levels: 'x', places: 'x' },
  { name: 'x', crs: 'mercator' }, { name: 'y' }, { name: 'z', size: [0, 1] }, { name: '' }, null, [1], 'x', { name: 'w', size: [1, '2'] },
  { id: 'bad id', name: 'q', size: [1, 1], regions: 'x', frames: 'x' }, { id: 'm1', name: 'r', size: [1, 1] }, { id: 'm1', name: 's', size: [1, 1] }, { name: 'q', size: [1, 1], image: 'nope', crs: ' image ' },
]], reportOf(HT.readMaps));
const fontOf = (id, fmt, head, more) => Object.assign({ id, family: id, src: `data:font/${fmt};base64,${b64(head)}`, license: 'OFL' }, more);
const ZERO1 = String.fromCharCode(0, 1, 0, 0);
add5c('readFonts', [[
  fontOf('f1', 'woff2', 'wOF2', { family: ' 글꼴 ', license: ' OFL ', scripts: 'hang, LATN, hani, Hang, abc, ab12, ', ranges: 'U+4E00-9FFF, u+ac00, U+4E00-U+9FFF, bad, U+20-10, ', note: ' n ' }),
  fontOf('f2', 'woff', 'wOFF', { scripts: ['Kore', '', null, 5], ranges: ['U+F1A00-F1A0B', 7] }), fontOf('f3', 'ttf', 'true'), fontOf('f4', 'otf', ZERO1), fontOf('f4b', 'ttf', 'OTTO'), fontOf('f4c', 'ttf', ZERO1),
  fontOf('f4d', 'otf', 'true'), fontOf('f4e', 'otf', 'OTTO'), fontOf('f5', 'otf', 'wOF2'), { id: 'f6', family: 'f', src: 'data:font/woff3;base64,AAAA', license: 'x' },
  { id: 'f7', family: 'g', src: 'data:font/ttf;base64,AA==', license: 'x' }, { id: 'f1', family: 'dup', license: 'x' }, { id: 'bad id' }, { id: 'f8', family: '' }, { id: 'f9', family: 'x', license: '' },
  { id: 'f10', family: 'x', license: 'l', src: 5 }, null, [1], fontOf('f11', 'woff2', 'wOF2'), fontOf('f12', 'woff2', 'wOF2', { scripts: 5, ranges: 'U+30' }),
  { id: 'f13', family: 'x', license: 'l', src: ' data:font/woff2;base64,d09GMgAA=== ' },
]], reportOf(HT.readFonts));

// 정규화(합성) — 5c 몫: 주제 · 성씨 · 지명 사전 · 지도 · 글꼴 · 문서 그림 · 사건 · 인물 · 단체 · 제도 · 패치 · 문서 · 영토(정답지에 패치 · 글꼴 · 영토가 없고, 정답지는 알림을 보지 않는다)
const head5c = (id, more) => Object.assign({ format: 'history-timeline-dlc', formatVersion: 3, id, name: id, tracks: [{ id: 't1' }, { id: 't2' }], categories: [{ id: 'c1' }] }, more);
for (const raw of [
  head5c('p5c', {
    themes: [{ name: '세제', id: 'tax' }, { name: '' }],
    surnames: [{ name: '이', names: ['Lee'], description: ' d ', wiki: ' w ' }, { name: '이' }, { name: '김', id: 'bad id' }, { name: '' }, null, [1], 'x', { name: '박', id: 'sn-park' }, { name: '최', id: 'sn-park' }],
    places: [{ name: '한양', names: ['Hanyang'], at: [127, 37.5], parent: '조선 땅', note: ' n ', description: 'd', wiki: 'w' }, { name: '개경', at: '126.5, 37.9' }, { name: '평양', at: 'x', parent: '평양' },
      { name: 'p4', id: 'pl-x', parent: 'pl-x', at: '' }, { name: 'p4', id: 'pl-x' }, { name: '' }, { name: 'q', id: 'bad id' }, null, 5, { name: 'r', at: [1, 2, 3] }, { name: 's', at: null }],
    maps: [{ name: '작은 지도', size: [10, 10], regions: [{ id: 'a', shape: tri }] }],
    fonts: [fontOf('ff', 'woff2', 'wOF2')],
    images: [{ name: '그림', src: `${PNG}AAAA` }, { id: 'bad id', src: 'x' }],
    events: [
      { title: '사건', track: 't1', start: 1592, end: 1598, category: 'c1', importance: '3', spot: '0.25', polity: ' 조선 ',
        perspectives: [{ track: 't2', title: '다른 쪽', description: '', source: 's' }, { track: '', title: 'x' }, { track: 't1' }, null, 'x', [1], { track: 't1', description: 'only d' }],
        parent: 'p', polities: ['a', '', 3], tracks: ['t2'], certainty: 'estimated', date: ' 날짜 ', description: 'd', wiki: ' w ', tags: 'a, b,, a', source: 's', figures: 'f1, f2，f1',
        treaty: { type: '강화' }, theme: '세제, 법', law: { name: '법', act: '제정' }, election: { office: '왕' }, place: '한양', names: ['Event'] },
      { name: '이름만', track: 't1', start: '1600-03-01', category: 'nope', importance: 5, spot: 2 },
      { title: 'x', track: 't1', start: 1, importance: '', spot: '' },
      { title: 'y', track: 't1', start: 2, importance: 0, tags: ['a', '', ' b '], figures: ['x', 'x'], treaty: { type: 'xyz', unequal: '예' }, law: { act: 'xyz' }, election: { results: [{ votes: 1 }] }, theme: ['a', 'a'] },
      { title: '', track: 't1', start: 1 }, { title: 'z', track: 'nope', start: 1 }, { title: 'w', track: 't1', start: 'abc' }, null, 'x', [1],
      { id: 'e-fixed', title: 'v', track: 't1', start: 3, category: 'war' }, { id: 'e-fixed', title: 'u', track: 't1', start: 4 }, { id: 'bad id', title: 't', track: 't1', start: 5 },
      { title: 'treaty', track: 't1', start: 1600, end: '현재', treaty: { parties: ['a', 'b'], articles: '제1조 (목적) x' }, spot: 0.5, alternatives: [{ start: 1599 }] },
      { title: '미정', track: 't2', start: '미정', startHint: 1700, end: 1710, importance: '1', law: 'x', election: [1], treaty: 'x' },
    ],
    figures: [
      { name: '이순신', track: 't1', birth: 1545, death: 1598, start: 1576, end: 1598, aka: '여해, 이순신', role: ' 장군 ',
        service: ['t1:조선', { polity: '수군', office: '통제사', start: 1593, end: 1597, note: ' n ', certainty: 'estimated' }, { track: 't2', name: '명', title: '도독', start: '미정', startHint: 1600, end: 1598 },
          { polity: 'x', start: 1600, end: 1500 }, { polity: 'y', start: 'abc' }, { polity: '' }, 5, null, 'only', ':x', { polity: 'z', start: 1500, end: '미정', endHint: 1400 }],
        house: '덕수 이씨', importance: 3, description: 'd', tags: 'a,b', source: 's', wiki: 'w', alternatives: [{ birth: 1546 }, { death: 1500 }], names: ['Yi'], parents: ['이정', { who: '미상', as: '부' }],
        spouses: ['방씨'], order: '2' },
      { name: '미정', track: 't1', start: '미정', startHint: 1600, end: '미정', endHint: 1550 },
      { name: '미정2', track: 't1', start: '미정', startHint: 1700, end: 1650 },
      { name: '미정3', track: 't1', start: 1700, end: '미정', endHint: 1650 },
      { name: '진행', track: 't1', start: 1900, end: '현재' },
      { name: '진행2', track: 't1', start: 1900, ongoing: true, end: 'abc' },
      { name: '날짜 틀림', track: 't1', birth: 'abc' },
      { name: '날짜 틀림2', track: 't1', start: '3세기', end: 'xyz' },
      { name: '거꾸로', track: 't1', birth: 1600, death: 1500 },
      { name: '거꾸로2', track: 't1', start: 1600, end: 1500 },
      { name: '날짜 없음', track: 't1' },
      { name: '계보', track: 't1', lineageOnly: true, parents: [{ who: '이정' }], importance: 3, service: ['x'] },
      { name: '계보', track: 't1', lineageOnly: true, parents: [{ who: '미상' }] },
      { name: '계보', track: 't1', lineageOnly: true },
      { name: '계보', track: 't1', lineageOnly: true, parents: [{ who: { polity: 'p', leader: 'l', start: 900 } }] },
      { name: '잘못', track: 't1', lineageOnly: 'yes', birth: 1500, order: 1.5, importance: 7 },
      { name: '서비스만', track: 't1', service: [{ polity: 'p', start: 1500 }] },
      { name: '서비스 빈', track: 't1', service: [{ polity: 'p' }] },
      { title: 'title로', track: 't1', birth: '1545-04-28', death: '1598-12-16' },
      { name: '', track: 't1' }, { name: 'x', track: 'nope' }, null, 'x',
      { name: '미정 힌트 없음', track: 't1', start: '미정', birth: 1500 },
      { name: '미정 힌트만', track: 't1', start: '미정', startHint: 1500 },
      { id: 'f-fixed', name: 'a', track: 't1', birth: 1 }, { id: 'f-fixed', name: 'b', track: 't1', birth: 2 },
      { name: 'order0', track: 't1', birth: 3, order: 0, lineageOnly: false, importance: '' },
      { name: '세기', track: 't2', birth: '16세기', death: '17세기 초', alternatives: [{ start: 1600, end: 1500 }, { birth: 'x' }] },
    ],
    groups: [
      { name: '동인', track: 't1', start: 1575, end: 1591, type: '붕당', within: '조선', from: ['사림', { group: '동인' }, { name: 'gr-x' }], power: [['집권', 1575, 1580], { name: '재집권', start: 1585, names: ['x'] }],
        people: '유성룡, 김효원，미상', members: ['a'], event: ' 을해당론 ', names: ['East'], certainty: 'estimated', color: '#abc', description: 'd', note: 'n', wiki: 'w' },
      { name: '연합', track: 't1', start: 1600, type: 'coalition', members: ['a'] },
      { name: '연합2', track: 't1', start: 1600, type: '동맹' },
      { name: '자유', track: 't1', start: 1600, type: '모임', within: [{ polity: 'a', start: 1600 }, 'k:b'], members: [{ polity: 'c', role: '맹주' }, 'd'], people: [{ polity: 'p', leader: 'l' }, 5] },
      { name: '', track: 't1', start: 1 }, { name: 'x', track: 't1', start: 'abc' }, [1], null, { name: 'y', track: 'nope', start: 1 },
      { id: 'gr-self', name: '자기', track: 't1', start: 1, from: ['gr-self', '자기', 'other'] },
      { name: '연합3', track: 't2', start: 1, type: 'coalition', members: ['a', 'b'], within: [] },
    ],
    institutions: [
      { theme: '세제', polity: '조선', track: 't1', family: ' 대동법 ', spans: [['공납', 1392, 1608], ['대동법', 1608, 1894]], names: ['Tax'], description: 'd', wiki: 'w' },
      { theme: ['병제', 'x'], polity: 'k:고려', spans: [['a', 1, 2]] },
      { theme: '', polity: 'a', spans: [['a', 1, 2]] },
      { theme: 't', polity: '', spans: [] },
      { theme: 't', polity: { polity: 'p', track: 'tt' }, spans: 'x' },
      { theme: 't', polity: 'p', spans: [{ name: '' }] },
      { theme: 't', polity: 'p', track: 't2', spans: [['a', 5, 4]] },
      null, [1], { theme: 't' }, {},
      { theme: '세제', polity: '조선', track: 't1', spans: [['b', 1, 2]] },
    ],
    patches: [
      { target: 'base/p1', note: ' 메모 ', hide: false, set: { start: '미정', startHint: 1500, end: '1600-03-01', name: ' 새 이름 ', bogus: 1, birth: '미정', death: 'abc', startRange: ['1490', 1510],
        endRange: [1, 'x'], alternatives: [{ end: 1700 }, { start: 1400 }, null, { end: ' ' }, { ongoing: true }], leaders: [['왕', 1500, 1520]], capitals: [['도성', 1500]], service: 'k:p', aka: 'a,b', figures: ['x'],
        spot: '0.5', names: ['N'], place: ' ', parents: ['p'], lineageOnly: 'yes', order: '3', spouses: ['s'], northSouth: '38', kind: '조공국', succeeds: ['x'], partOf: [{ polity: 'q', relation: 'xyz' }],
        phases: [['전기', 1500, 1550]], ranks: 'x', treaty: null, theme: 'a, b', law: { name: 'l' }, election: {}, type: '정당', within: '조선', from: 'g', power: [['p', 1, 2]], members: ['m'],
        people: ['p1', 'p1'], family: 5, event: ' e ', spans: [['s', 1, 2]], historicity: '전설' } },
      { target: 'base/p2', hide: 1 },
      { target: 'bad' }, { target: 'a/b/c' }, { target: '/x' }, { target: 'x/' }, { target: '' },
      { target: 'p5c/x', set: { color: '#abc' } },
      { target: 'base/p3' },
      { target: 'base/p4', set: { startHint: 1500 } },
      { target: 'base/p5', set: { start: '미정', startHint: 'abc' } },
      { target: 'base/p6', set: { endHint: '', end: '미정', endUnknown: true } },
      { target: 'base/p7', set: { end: '미정', endHint: 1600, endAt: 'x' } },
      { target: 'base/p7b', set: { start: '1500', startUnknown: true, startHint: '1490' } },
      { target: 'base/p8', set: { start: null, startAt: 'x', end: '', endAt: 'y' } },
      { target: 'base/p9', set: { startRange: null, startRangeAt: ['x'], endRange: ['1600-01-01', '1590-01-01'], endRangeAt: [null, null] } },
      { target: 'base/p9b', set: { startRange: [1500, 1510], startRangeAt: ['1500-03-01'], endRange: 'x' } },
      { target: 'base/p10', set: { alternatives: [{ end: 1700 }], birth: 1500 } },
      { target: 'base/p11', set: { alternatives: [{ birth: 1 }, { ongoing: true }] } },
      { target: 'base/p11b', set: { alternatives: 'x', role: 'r' } },
      { target: 'base/p12', set: { spot: 2, order: '', lineageOnly: null, northSouth: '', kind: 'xyz', phases: null, ranks: [], historicity: 'xyz' } },
      { target: 'base/p13', set: { order: 1.5, northSouth: 'x', phases: 'x', ranks: [{ name: '' }], historicity: '실재', treaty: { type: '강화' }, theme: ['a', 'a', ''], law: null, election: { office: 'x' },
        within: [], spans: [{ name: '' }], people: 'not array', members: null, from: null } },
      { target: 'base/p14', set: [1, 2] },
      { target: 'base/p15', set: 'x' },
      { target: 'base/p16', set: { phases: [], kind: 'culture', reigns: [['r', 1, 2]], cabinets: [['c', 1, 2]], eras: [['e', 1, 2]], historicity: '', lineageOnly: true, northSouth: 38.5 } },
      { target: 'base/p17', set: { birthAt: '1500-01-01', birth: 1500, deathAt: 'abc', death: 1600, endAt: '1600' } },
      { target: 'base/p18', set: { phases: {}, ranks: [5], spans: 'x', type: ' 붕당 ', theme: 7, order: null, place: '서울' } },
      { target: 'base/p19', set: { leaders: 'x', capitals: 'y', power: 'z', people: ['미상', 'a'], within: ['a', 'b'], kind: '부마국', historicity: 'attested' } },
      null, 'x', [1],
    ],
    documents: { 'base//역사': '본문', ' key ': ' 공백 키 ', key: '덮음', '': 'x', a: '', b: '  ', c: 5, '//x': 'bad', ['x'.repeat(300)]: 'long', ['y'.repeat(299)]: 'ok',
      'cell:p1:leaders:왕@1500': 'c', 0: 'zero', d: null },
    territory: { basemap: '', generateOver: ' gp ', unitPacks: ['u1', '', 5],
      units: [{ id: 'u1', name: '단위', cells: ['c1', '', 'c2'], level: ' 도 ', parent: 'p', parentName: 'pn', source: 's', confidence: 'c', description: 'd', start: '1500', end: '현재' },
        { id: 'u2', cells: [] }, { id: 'a/b', cells: ['x'] }, { id: '', cells: ['x'] }, null, 0, { id: 'u3', cells: ['x'], start: 'abc', end: 1600.5 }, { id: "q'", cells: ['x'] }, { id: `b${ch(92)}`, cells: ['x'] }],
      names: { c1: [[1500, '', '이름', '상위'], [1400, 1450, '앞'], ['abc', 1, 'x'], [1, 2], 'x', [1300, '현재', '']], c2: 'x', c3: [], c4: [['1200', '1250-01-01', ' 옛 이름 ']] },
      polities: [{ id: 'tp1', name: '정권', color: '#abc', track: 't1', period: 'p', kind: 'vassal', start: '1500', end: '현재', description: 'd' }, { id: 'tp1', name: 'dup' }, { id: 'a"b' }, { name: '없음' },
        null, { id: 'tp2', kind: 'xyz', start: 'abc', end: 'xyz' }, { id: 'tp3', name: 5 }, { id: 'tp4', kind: 'culture', start: 1500, end: '' }],
      ownership: { c1: [[1500, 1600, 'tp1', 'occupied', 'tp2'], [1550, '현재', 'tp1'], [1700, 1600, 'x'], [1, 2, ''], { start: 1400, end: 1450, polity: 'p', status: '', by: 'b' }, null, 'x', [1300]],
        c2: 'x', c3: [[1, 2, 'p', '', 'b']], c4: [{ start: 1, end: 3, polity: 'q', status: 's' }, [2, 4, 'r', 'st', 'by', 'extra']] } },
  }),
  head5c('th-only', { tracks: [], themes: [{ name: '주제' }] }),
  head5c('sn-only', { tracks: [], surnames: [{ name: '김' }] }),
  head5c('pl-only', { tracks: [], places: [{ name: '서울' }] }),
  head5c('img-only', { tracks: [], images: [{ name: '그림', src: `${PNG}AAAA` }] }),
  head5c('font-only', { tracks: [], fonts: [fontOf('f1', 'woff2', 'wOF2')] }),
  head5c('map-only', { tracks: [], maps: [{ name: '지도', size: [1, 1] }], fonts: 'x', images: 'x' }),
  head5c('ev-only', { events: [{ title: 'e', track: 't1', start: 1 }] }),
  head5c('fig-only', { figures: [{ name: 'f', track: 't1', birth: 1 }] }),
  head5c('gr-only', { groups: [{ name: 'g', track: 't1', start: 1 }] }),
  head5c('in-only', { institutions: [{ theme: 't', polity: 'p', spans: [['a', 1, 2]] }] }),
  head5c('pa-only', { patches: [{ target: 'x/y', hide: true }] }),
  head5c('doc-only', { documents: { a: 'b' } }),
  head5c('doc-bad', { documents: ['x'] }),
  head5c('ter-only', { territory: { ownership: { c: [[1, 2, 'p']] } } }),
  head5c('ter-units', { territory: { units: [{ id: 'u', cells: ['c'] }] } }),
  head5c('ter-empty', { territory: { generateOver: 'x' } }),
  head5c('ter-bad', { territory: ['x'] }),
  head5c('ter-ongoing', { territory: { polities: [{ id: 'p' }], ownership: { c: [[2020, null, 'p'], [2026, '', 'q'], [2030, '현재', 'r']] } } }),
  head5c('fatal-5c', { id: 'bad id', events: [{ title: 'e', track: 't1', start: 1 }] }),
]) add5c('normalizePack', [raw], ([x]) => norm(x));

// ── 형식 4 내림(합성) ──
for (const j4 of [
  null,
  { formatVersion: 4, periods: [], objects: 'x' },
  { formatVersion: 4, objects: [null, 'x', [1],
    { id: 'a', name: '갑', type: '나라', track: 't', start: 1, end: 100, partOf: [{ of: '미상', relation: 'tributary' }], offices: [{ name: '지도자', cells: [['왕', 1, 10]] }, { name: '내각', cells: [] }, { name: '셋째', cells: [['x', 1, 2]] }] },
    { id: 'b', name: '을', type: 'xyz', display: 'nope', within: [{ of: '갑' }], partOf: [{ of: '갑', relation: '조공' }], start: 5, end: 9 },
    { id: 'c', name: '병', within: ['갑', '을'], partOf: '갑' },
    { id: 'z', name: '구역', type: 'dependency', display: 'inside', within: '갑' },
    { id: 'g', name: '무리', type: 'league', display: 'mark', within: ['갑'], persons: ['p'], succeeds: [{ from: '앞 무리', type: 'direct', note: 'n' }, 'x'] },
    { id: 'r', name: '실권', type: 'regime', display: 'mark', subtype: 'faction' },
    { id: 'era1', name: '앞 시대', type: 'era', track: 't', start: 1, end: 50 },
    { id: 'era2', name: '뒤 시대', type: 'era', track: 't', start: 50, end: 100, within: '앞 시대' },
    { id: 'mv', name: '옮김', track: 't', start: 1, end: 100, within: [{ of: 'era1', end: 50 }, { of: 'era2', start: 50 }], offices: [{ name: '지도자', cells: [['왕1', 10, 60], { name: '왕2', start: 60, end: 90 }] }], succeeds: [{ from: 'x' }] },
    { id: 'after', name: '뒤', track: 't', start: 100, end: 120, succeeds: [{ from: '옮김' }] },
    { id: 'era3', name: '빈 시대', type: 'era', members: ['t2:밖'], track: 't' },
    { id: 'era4', name: '이름표', type: 'era', within: 'era1', track: 't', alternatives: [{ start: 1 }], label: 'l', default: true, host: 'h' },
    { name: '띠 시대', type: 'era', display: 'band', start: 1, end: 2 },
  ], events: [{ title: 'e', polity: '옮김', start: 70 }, { title: 'f', polity: 'mv', start: 10 }, 'x'] },
  // 최상위 간지 줄 고르기(6단계 결정 16): 문화권 없는 줄만 · 내장 육십갑자 전체 줄은 비운 것과 같음 · 고른 줄의 표지 칸은 뺌
  { formatVersion: 4, objects: [], yearCycles: [{ sphere: 'a', names: ['한', '둘'], start: 1, label: '두해' }, { sphere: 'b', era: '빙원', from: 300 }] },
  { formatVersion: 4, objects: [], yearCycles: [{ names: '육십갑자' }, { sphere: 'a', names: ['한', '둘'], start: 1 }] },
  { formatVersion: 4, objects: [], yearCycles: [{ builtin: 'sexagenary', label: '간지' }] },
  { formatVersion: 4, objects: [], yearCycles: [{ sphere: 'a', names: ['한', '둘'], start: 1 }, { sphere: '', names: ['갑', '을'], start: 1, builtin: 'xyz' }] },
  { formatVersion: 4, objects: [], yearCycle: false, yearCycles: [{ names: ['갑', '을'], start: 1 }] },
]) add('F4.down', [j4], ([x], w) => HT.F4.down(x, w));

// ── 형식 4 내림 — 상대를 모르는 섬김의 종류 되살리기(periodOf: `x.of === UNKNOWN && o.type === 'state' && STATE_DEPENDENT.includes(rel)` → kind = rel) ──
// 맞추기 과제 S 고침 1회차: 위 합성 표본의 '미상'은 type '나라'(realm)라 이 갈래에 들지 않았다 — 국가(type 없음 · 'state' · '국가')인 표본과 그 짝(종속이 아닌 관계 ·
// of가 미상이 아님 · 관계 없음 · 국가가 아님)을 표본 하나에 객체 하나씩 둔다. lay_read가 'kind가 되살아난 출력 ≥ 1 · 되살아나지 않은 짝 ≥ 1'을 단언한다.
const f4one = o => ({ formatVersion: 4, objects: [{ id: 'host', name: '을', track: 't', start: 1, end: 100 }, Object.assign({ id: 'x', name: '갑', track: 't', start: 10, end: 50 }, o)] });
for (const o of [
  { partOf: [{ of: '미상', relation: 'tributary' }] }, // type 없음 → 국가 → 조공국으로 되살림
  { type: 'state', partOf: [{ of: '미상', relation: '조공' }] }, // 낱말 → relationId
  { type: '국가', partOf: [{ of: '미상', relation: '속국' }] }, // 한국어 종류 이름 → state
  { type: ' state ', partOf: [{ of: ' 미상 ', relation: 'protectorate' }] }, // refOf · typeId가 다듬음
  { partOf: [{ of: '미상', relation: '식민지' }, { of: '을', relation: '조공', start: 20, end: 30 }] }, // 되살림 + 상대가 있는 줄은 남음
  { partOf: [{ of: '미상', relation: 'tributary' }, { of: '미상', relation: 'frontier' }] }, // 둘이면 뒤의 것
  { type: 'state', partOf: [{ of: '미상', relation: '점령지' }], within: [{ of: '을' }] }, // 그릇 줄과 함께
  { type: 'state', display: 'band', partOf: [{ of: '미상', relation: 'tributary' }] }, // 띠로 그리는 국가 — kind는 era로 시작해 되살림이 덮음
  // 짝(되살리지 않음)
  { type: 'state', partOf: [{ of: '미상', relation: 'member' }] }, // 종속이 아닌 관계(구성국)
  { type: 'state', partOf: [{ of: '미상', relation: 'nominal' }] }, // 명목상 — 종속 kind가 아님
  { type: 'state', partOf: [{ of: '미상', relation: 'xyz' }] }, // 모르는 관계 글
  { type: 'state', partOf: [{ of: '미상' }] }, // 관계 없음
  { type: 'state', partOf: '미상' }, // 글 하나
  { type: 'state', partOf: [{ of: '을', relation: 'tributary' }] }, // of가 미상이 아님
  { type: 'state', partOf: [{ of: '미상 국', relation: 'tributary' }] }, // 미상과 비슷한 다른 이름
  { type: 'realm', partOf: [{ of: '미상', relation: 'tributary' }] }, // 국가가 아님(나라)
  { type: 'principality', partOf: [{ of: '미상', relation: 'vassal' }] }, // 국가가 아님(제후국 — 제 종류 fief)
]) add('F4.down:unknown', [f4one(o)], ([x], w) => HT.F4.down(x, w));

// ── 칸 · 소속 구간의 정통성(4단계 배치 갈래 걸음 4 — 계약 1-1 구역 57 · 58): 정규화가 지도자 · 내각 · 직위 줄 더의 칸과 시대의 소속 줄에서 status를 지킴(한국어 → id) ·
// 연호 · 집권 칸 · 기관의 host · 왕조의 polities는 받지 않음 · 모르는 값은 알리고 뺌(소속 줄은 warn을 줄 때만) · 패치의 지도자 칸도 같은 읽기 ──
for (const v of [[{ polity: 'a', status: 'rival' }, { polity: 'b', status: ' 섭정 ' }, { polity: 'c', status: 'x' }, { polity: '', status: 'y' }, { polity: 'd', status: '' }, { polity: 'e', status: 5 },
  { polity: 'f', status: null }, { polity: 'g', status: 'legit', start: 1, end: 2, certainty: 'weird' }]]) {
  add5b('readPartOf', [v], ([x], w) => HT.readPartOf(x, { warn: w }));
  add5b('readPartOf:relation', [v], ([x], w) => HT.readPartOf(x, { relation: true, warn: w }));
}
add5b('normalizePack', [{
  format: 'history-timeline-dlc', formatVersion: 3, id: 'legit', name: '정통성', tracks: [{ id: 't1' }],
  periods: [
    { name: '윗나라', track: 't1', start: 1, end: 500 },
    { name: '섬나라', track: 't1', start: 100, end: 400, status: '대립',
      leaders: [{ name: '갑', start: 100, end: 150, status: '공동' }, { name: '을', start: 150, end: 200, status: 'regent' }, { name: '병', start: 200, status: '반쪽' }, ['정', 300, 400]],
      cabinets: [{ name: '내각', start: 120, end: 180, status: 'claim' }, { name: '내각2', start: 180, status: 7 }],
      offices: [{ name: '재상', cells: [{ name: '무', start: 130, status: '명목' }, { name: '기', start: 160, status: 'nope' }] }, { name: '서기', from: '윗나라' }],
      eras: [{ name: '연호', start: 100, status: 'rival' }],
      partOf: [{ polity: '윗나라', start: 100, end: 200, status: 'claim' }, { polity: '윗나라', start: 250, status: '모름' }, { polity: '윗나라', start: 300, status: 'joint' }] },
    { kind: 'overlay', name: '관청', track: 't1', start: 100, end: 200, host: [{ polity: '윗나라', status: 'rival' }] },
    { kind: 'dynasty', name: '왕가', track: 't1', start: 100, end: 300, polities: [{ polity: '윗나라', status: 'rival' }] },
  ],
  groups: [{ name: '무리', track: 't1', start: 100, end: 200, power: [{ name: '권신', start: 120, status: 'rival' }] }],
  patches: [{ target: 'legit/섬나라', set: { leaders: [{ name: '패치왕', start: 100, status: '섭정' }, { name: '패치왕2', start: 200, status: 'z' }] } }],
}], ([x]) => norm(x));

// ── 정답지 자료의 형식 4 파일 — 내린 팩 전체(열쇠 차례까지)의 지문 ──
const f4files = [];
for (const file of fs.readdirSync(path.join(fixDir, 'f4')).sort()) {
  const bytes = fs.readFileSync(path.join(fixDir, 'f4', file));
  const raw = JSON.parse(zlib.inflateSync(bytes.subarray(52)).toString('utf8'));
  if (Number(raw.formatVersion) !== 4) continue;
  const warn = [];
  const down = JSON.stringify(HT.F4.down(raw, m => warn.push(m)));
  f4files.push({ file: `f4/${file}`, sha: crypto.createHash('sha256').update(down).digest('hex').slice(0, 12), bytes: down.length, warn });
}
// JSON 꼴의 형식 4 파일 — nest-scene.f4.json · f4-moves.json(옮겨 앉기의 그릇 밖 토막 · 토막 난 상대를 가리킨 섬김 · 실권)과, 형식 4로 등록된 내장 팩을 굳힌 것
// (엔진이 이 파일을 f4::down으로 내려 읽음 · 형식 3이면 건너뜀)
for (const file of ['nest-scene.f4.json', 'f4-moves.json', 'east-asia.json']) {
  const raw = JSON.parse(fs.readFileSync(path.join(fixDir, file), 'utf8'));
  if (Number(raw.formatVersion) !== 4) continue;
  const warn = [];
  const down = JSON.stringify(HT.F4.down(raw, m => warn.push(m)));
  f4files.push({ file, sha: crypto.createHash('sha256').update(down).digest('hex').slice(0, 12), bytes: down.length, warn });
}

fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, `${JSON.stringify({ now, calendar: { tables }, cases, f4files }, null, 1)}\n`);
console.log(`read-vectors: 표본 ${cases.length}개 · 형식 4 파일 ${f4files.length}개 → ${path.relative(process.cwd(), outFile)}`);
console.log(`5b 표본에서 맞은 그 밖의 정규식(5a가 지키는 것이어야 함): ${[...others5b].map(s => `/${s}/`).join(' ')}`);
console.log(`5c 표본에서 맞은 그 밖의 정규식(5a · 5b가 지키는 것이어야 함): ${[...others5c].map(s => `/${s}/`).join(' ')}`);

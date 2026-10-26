// 검사 자료로 커밋하는 **잘린 달력 표**를 뽑는다(한 벌 P3 과제 5c 덧붙임 · 판정 R18 · 과제 8-틀 고침 1회차(R24 ①)로 넓힘) — Rust 검사가 git 밖 파일(prototype/results/calendar-cache.json)에 기대지 않게.
// 덮는 범위 둘(달력마다 하나로 이어 뜬다):
//   ① 읽기: 정답지 자료 전부(prototype/fixtures/oracle/list.json — Rust 검사가 읽는 입력 파일 그대로. 선택 자료 · `"calClip": true` 표지 자료는 뺀다 — 판정 R64-2)와 읽기 벡터(prototype/engine/tests/fixtures/lay/read-vectors.json의 표본 입력)에
//      든 글을 모두 `HT.cal.parse`로 읽어 보며 ICU에 물은 날 번호(달력마다)를 모아 그 둘레(앞뒤 한 해씩 더한 서력 해 경계).
//   ② 내보내기 calendar 모듈(export/calendar.mjs): 정답지 자료마다 모델(contextOf — 시각은 정답지와 같게 고정)의 해 범위 ± 100년(`dataYears` — 아래 옮겨 적음)을
//      `jdnCivil`로 날 번호로 바꾼 [fromJ, toJ) — 그 모듈이 `sliceTable(wide, c, fromJ, toJ)`로 자르는 인자와 같은 규칙. 달력은 `wantedCalendars` 모두(2026-10-24 리메이크 6단계 걸음 4에 다섯에서 열로).
// 표는 export/calendar.mjs의 buildTable로 뜨고, 넓게 떠 둔 표가 있으면 sliceTable로 자른 것과 글자까지 같은지 본다(같은 규칙 — calendar-cache-check.mjs가 지키는 약속).
// 꼴은 calendar-cache.json(warm-calendar.mjs)과 같다 — Rust는 `lay::cal::Tables::from_cache`로 읽는다(과제 17의 '저장소 안 표'와 같은 길: `Opts.calendar`). 자른 표의 원문(start · end · year0 · months)은
// `Tables::raw(id)`로도 꺼낼 수 있어 Rust의 calendar 모듈이 같은 `sliceTable` 규칙으로 제 몫을 자른다.
// 왜 서력 해 경계로 넓히나(①): 보조 달력 날짜 하나를 읽을 때 웹(intlJdn)도 Rust도 짐작한 날 ± 800일 안을 이분 탐색한다 — 물은 날 번호가 곧 Rust가 물을 날 번호지만,
// 해 경계로 넓혀 두면 표본을 조금 고쳐도 표를 다시 뽑지 않아도 된다.
// 사용(작업 폴더에서): node prototype/scripts/calendar-slice.mjs   — 같은 Node(ICU) 판이면 같은 바이트가 나온다. read-vectors.mjs를 다시 뽑았거나 정답지 자료의 해 범위가 바뀌었으면 이것도 다시 돌린다.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const prototypeDir = path.resolve(here, '..');
const rootDir = path.resolve(prototypeDir, '..');
const fixDir = path.join(prototypeDir, 'fixtures', 'oracle');
const vectorsFile = path.join(prototypeDir, 'engine', 'tests', 'fixtures', 'lay', 'read-vectors.json');
const outFile = path.join(prototypeDir, 'engine', 'tests', 'fixtures', 'lay', 'calendar-slice.json');
const cacheFile = path.join(prototypeDir, 'results', 'calendar-cache.json');

/** 정답지가 고정하는 '오늘'(layout-oracle.mjs의 ORACLE_NOW · Rust tests/common/oracle.rs와 같은 값) — 모델의 해 범위(진행 중 정권의 끝)가 이 시각에 달린다. */
const ORACLE_NOW = '2026-10-15T12:00:00+09:00';
// base.mjs(→ core.js가 싣는 순간 new Date().getFullYear()를 셈)를 가져오기 **전에** 시각을 고정한다(oracle/one.mjs와 같은 길).
(await import('./oracle/clock.mjs')).installClock(ORACLE_NOW);

// ICU에 묻는 자리(js/calendar.js의 intlParts → Intl.DateTimeFormat#formatToParts)를 감싸 달력마다 물은 날 번호를 모은다 — 웹 코드를 싣기 전에.
const asked = new Map(); // ICU 달력 이름(intl) → 날 번호 Set
const realParts = Intl.DateTimeFormat.prototype.formatToParts;
Intl.DateTimeFormat.prototype.formatToParts = function (date) {
  const intl = this.resolvedOptions().calendar;
  if (intl !== 'gregory') {
    const J = Math.round(date.getTime() / 864e5) + 2440588;
    if (!asked.has(intl)) asked.set(intl, new Set());
    asked.get(intl).add(J);
  }
  return realParts.call(this, date);
};

const { bootWeb, contextOf } = await import('./export/base.mjs');
const { buildTable, sliceTable, wantedCalendars } = await import('./export/calendar.mjs');
const HT = bootWeb();

/** 값 안의 글을 모두 날짜로 읽어 본다(날짜가 아닌 글은 곧 실패 — 보조 달력 날짜만 ICU에 묻는다). */
const seen = { strings: 0 };
const walk = v => {
  if (typeof v === 'string') { seen.strings++; HT.cal.parse(v); return; }
  if (Array.isArray(v)) { v.forEach(walk); return; }
  if (v && typeof v === 'object') for (const x of Object.values(v)) walk(x);
};
const readRaw = async file => {
  const bytes = fs.readFileSync(file);
  return /\.htpack$/i.test(file) ? (await HT.packFile.parse(new Uint8Array(bytes))).raw : JSON.parse(bytes.toString('utf8'));
};

// 1) 정답지 자료 — Rust 검사(tests/common/oracle.rs의 inputs)가 읽는 파일 그대로: sample · 굳힌 내장 팩(file) · file · extra(선택 자료는 있으면).
const list = JSON.parse(fs.readFileSync(path.join(fixDir, 'list.json'), 'utf8'));
const abs = file => (path.isAbsolute(file) ? file : path.join(fixDir, file));
/** 자료 하나의 입력 파일(첫째가 기본 DLC) — Rust `inputs()`와 같은 차례. */
const inputsOf = f => {
  const files = [];
  if (f.base.sample) files.push(path.join(rootDir, 'samples', `${f.base.sample}.json`));
  else if (f.base.file) files.push(abs(f.base.file));
  else if (f.base.builtin) files.push(path.join(fixDir, `${f.base.builtin}.json`)); // 내장 팩만 적은 자료 — Rust inputs()처럼 굳힌 <내장>.json
  for (const x of f.extra || []) files.push(abs(x));
  return files;
};
/** 판정 R64-2: `"calClip": true` 표지 자료(`synth-calclip`) — 자료 해 ± 100년이 일부러 저장소 달력 표(−3500 ~ 2500년) 밖(−8100 ~ 10099년)이라 이 표에 넣으면 표가 4배(2.2MB)로 불고
 *  '표가 자료를 덮지 못할 때 겹치는 구간만 싣는다'를 보는 검사가 의미를 잃는다 — 그 자료의 보조 달력 날짜도 없다(양력만). `<이름>@f4`는 `@f4`를 뗀 이름의 표지를 따른다. */
const clipNames = new Set(list.filter(f => f.calClip === true).map(f => f.name));
const isCalClip = f => clipNames.has(f.name.replace(/@f4$/, ''));
const files = new Set();
for (const f of list) {
  if (f.optional) continue; // 선택 자료(감독 PC에만 있는 파일)는 넣지 않는다 — 어느 PC에서 뽑아도 같은 바이트가 나오게(그 자료에는 보조 달력 날짜가 없다 — 보고서)
  if (isCalClip(f)) continue; // 달력 잘림 자료도 넣지 않는다(위)
  for (const file of inputsOf(f)) files.add(file);
}
const used = [];
/** 선택 자료가 아닌 자료의 입력이 없으면 멈춘다(과제 Y — 8-틀 재검토: 조용히 건너뛰면 그 자료의 보조 달력 날짜 둘레가 빠진 표가 커밋된다). */
const mustExist = file => {
  if (!fs.existsSync(file)) throw new Error(`calendar-slice: 정답지 자료(선택 자료 아님)의 입력 파일이 없습니다 — ${path.relative(rootDir, file).split(path.sep).join('/')}`);
};
for (const file of [...files].sort()) {
  mustExist(file);
  walk(await readRaw(file));
  used.push(path.relative(rootDir, file).split(path.sep).join('/'));
}
// 2) 읽기 벡터의 표본 입력(JSON 글 — 열쇠 차례째로).
const vectors = JSON.parse(fs.readFileSync(vectorsFile, 'utf8'));
for (const c of vectors.cases) walk(JSON.parse(c.in));

// 3) 내보내기 calendar 모듈이 자료마다 자르는 범위(export/calendar.mjs의 dataYears · contribute 181 ~ 185줄 — 그 모듈은 내보내지 않으므로 여기 옮겨 적음 · PAD_YEARS = 100).
/** 자료가 놓인 해의 범위(연표 연도) — 띠 · 사건 · 시대 구분 · 인물의 양 끝 ± 100년(export/calendar.mjs의 dataYears 그대로). */
function dataYears(model) {
  const PAD_YEARS = 100;
  let lo = Infinity, hi = -Infinity;
  const see = (a, b) => {
    if (Number.isFinite(a) && a < lo) lo = a;
    if (Number.isFinite(b) && b > hi) hi = b;
  };
  for (const p of model.periods || []) see(p.startRange ? p.startRange[0] : p.start, p.endRange ? p.endRange[1] : p.endY);
  for (const e of model.events || []) see(e.start, e.endY != null ? e.endY : e.start);
  for (const e of model.epochs || []) see(e.start, e.endY != null ? e.endY : e.end);
  for (const f of model.figures || []) see(f.birth != null ? f.birth : f.start, f.death != null ? f.death : f.endY);
  if (!Number.isFinite(lo) || !Number.isFinite(hi)) return [1, 1];
  return [Math.floor(lo) - PAD_YEARS, Math.ceil(hi) + PAD_YEARS];
}
let moduleJ = null; // [fromJ, toJ) — 자료 모두를 덮는 하나(달력마다 같은 범위를 자른다)
const moduleYears = [];
for (const f of list) {
  if (f.optional || isCalClip(f)) continue; // 선택 자료 · 달력 잘림 자료(위)는 모듈 범위에 넣지 않는다
  const inputs = inputsOf(f);
  inputs.forEach(mustExist);
  const raws = [];
  for (const file of inputs) raws.push(await readRaw(file));
  const ctx = contextOf(HT, raws, inputs.slice(1).map(x => path.basename(x)));
  const [loYear, hiYear] = dataYears(ctx.model);
  const fromJ = HT.cal.jdnCivil(loYear, 1, 1);
  const toJ = HT.cal.jdnCivil(hiYear === -1 ? 1 : hiYear + 1, 1, 1);
  moduleYears.push(`${f.name} ${loYear}~${hiYear}`);
  moduleJ = moduleJ ? [Math.min(moduleJ[0], fromJ), Math.max(moduleJ[1], toJ)] : [fromJ, toJ];
}

// 4) 달력마다 ①(물은 날의 둘레 — 앞뒤 한 해씩 더한 서력 해 경계)과 ②(모듈의 범위)를 합친 하나의 범위를 뜬다.
const yearOfJ = J => HT.cal.civilOf(J).y;
const jdnOfYear = y => HT.cal.jdnCivil(y === 0 ? 1 : y, 1, 1); // 서력에는 0년이 없다
let wide = null;
try {
  const c = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
  if (c.icu === (process.versions.icu || '')) wide = c.tables;
} catch { /* 넓게 떠 둔 표가 없음 — 견주기만 건너뛴다 */ }
const tables = {};
const notes = [];
for (const c of wantedCalendars(HT)) {
  const js = asked.get(c.intl);
  let fromJ = moduleJ ? moduleJ[0] : null, toJ = moduleJ ? moduleJ[1] : null;
  if (js && js.size) {
    const lo = Math.min(...js), hi = Math.max(...js);
    let loY = yearOfJ(lo) - 1, hiY = yearOfJ(hi) + 1;
    if (loY === 0) loY = -1;
    if (hiY === 0) hiY = 1;
    const a = jdnOfYear(loY), b = jdnOfYear(hiY === -1 ? 1 : hiY + 1);
    fromJ = fromJ == null ? a : Math.min(fromJ, a);
    toJ = toJ == null ? b : Math.max(toJ, b);
  }
  if (fromJ == null) continue; // 이 달력을 읽는 자료도, 모듈의 범위도 없다 — 표를 싣지 않는다
  const askedN = js ? js.size : 0; // 자료 · 벡터가 물은 날 수 — 표를 뜨는 동안(buildTable도 ICU에 묻는다) 늘기 전에 잰다
  const t = buildTable(HT, c, fromJ, toJ);
  if (t.bad) throw new Error(`${c.id}: ICU가 답하지 못했습니다 — ${t.bad}`);
  if (wide && wide[c.id]) {
    const cut = sliceTable(wide[c.id], c, fromJ, toJ);
    if (cut && JSON.stringify(cut) !== JSON.stringify(t)) throw new Error(`${c.id}: 넓게 떠 둔 표에서 자른 것과 바로 뜬 것이 다릅니다`);
    if (cut) notes.push(`${c.id} = calendar-cache.json에서 자른 것과 같음`);
  }
  tables[c.id] = Object.assign({ intl: c.intl, years: [yearOfJ(fromJ), yearOfJ(toJ - 1)], asked: askedN }, t);
}
const body = {
  note: '잘린 달력 표(검사 자료) — node prototype/scripts/calendar-slice.mjs가 정답지 자료 · 읽기 벡터의 보조 달력 날짜 둘레와 내보내기 calendar 모듈의 범위(자료 해 ± 100년 · 국제화 달력 모두)를 떠서 씀. calendar-cache.json과 같은 꼴.',
  v: 2, icu: process.versions.icu || '', inputs: used, tables,
};
const text = `${JSON.stringify(body)}\n`;
fs.writeFileSync(outFile, text);
console.log(`calendar-slice: ${path.relative(process.cwd(), outFile)} · ${text.length}자 · 입력 ${used.length}개 · 글 ${seen.strings}개를 읽어 봄 · 모듈 범위 자료 ${moduleYears.length}개`);
for (const [id, t] of Object.entries(tables)) console.log(`  ${id}: ${t.years[0]}~${t.years[1]}년 · 달 ${t.count}개 · 물은 날 ${t.asked}개`);
console.log(`  모듈 해 범위: ${moduleYears.join(' · ')}`);
if (notes.length) console.log(`  ${notes.join(' · ')}`);

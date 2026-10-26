// JS 값 층의 벡터 뽑기(한 벌 P3 과제 3) — Node가 정답이다. Rust `lay::js`(prototype/engine/src/lay/js.rs)가 같은 답을 내는지
// prototype/engine/tests/lay_js.rs가 이 파일(prototype/engine/tests/fixtures/lay/js-vectors.json)로 견준다.
// 사용(작업 폴더에서): node prototype/scripts/js-vectors.mjs
//   시간대가 Asia/Seoul이 아니면 스스로 TZ=Asia/Seoul을 정한 자식 프로세스로 다시 돈다(Git Bash의 export TZ는 node에 넘어가지 않으므로).
//   같은 Node 판이면 몇 번을 뽑아도 같은 바이트가 나온다(무작위 대신 정한 씨앗의 mulberry32).
//
// 갈래(열여섯)와 견주는 Rust 검사:
//   num · round · int · coerce · str · keys · sort · minute · local · json · seam · cmp16 · hidden → tests/lay_js.rs(JS 값 층 — 과제 3 · 4 · 6)
//   regex(뜻 차이 규칙의 표본) · wiki(js/wiki.js의 정규식 · 함수 · 렌더 · 견본 문서 · 날짜 글 when) → tests/lay_wiki.rs(과제 12a · 12b — 갈래 C · regex 1.13.1 들인 뒤)
//   entities(groupDigits · toFixed1 · 계보 뼈대 kin · kinCollect) → tests/lay_m_entities.rs(과제 13 — 갈래 D)
//   cmp16은 갈래 안에 다시 갈래(case · korea · script · punct · nfd · empty · prefix · astral)가 있다 — 아래 해당 절.
// ICU 판 가드(과제 Y): wiki.when(보조 달력 날짜 글)의 답은 이 Node의 ICU로 셈하고 Rust 검사는 잘린 달력 표(tests/fixtures/lay/calendar-slice.json — 뜬 ICU 판이
//   `icu`에 적힘)로 읽는다 — 판이 다르면 날 번호가 갈릴 수 있어 시작하자마자 멈춘다(그 판의 Node로 돌리거나 calendar-slice.mjs로 표를 다시 뜰 것).
//
// 값을 적는 꼴('짓기 꼴' — JSON에 없는 JS 값과 열쇠 차례 · 고리를 적으려고):
//   null · 참거짓 · 수 · 글 · 배열은 그대로 · {"$u":0} undefined · {"$num":"NaN"|"Infinity"|"-Infinity"|"-0"}
//   {"$s16":[코드 단위…]} 외톨이 서로게이트가 든 글 · {"$o":[[열쇠, 값]…]} 객체(넣는 차례대로) · {"$a":[…]} 배열
//   {"$map":[[열쇠, 값]…]} Map(set 차례대로) · {"$set":[…]} Set(add 차례대로) · 앞의 넷은 "$id":"이름"을 붙일 수 있고 {"$see":"이름"}이 그 객체를 가리킨다(고리 · 나눠 가짐).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TZ = 'Asia/Seoul';
const self = fileURLToPath(import.meta.url);
if (process.env.TZ !== TZ) {
  const r = spawnSync(process.execPath, [self, ...process.argv.slice(2)], { env: { ...process.env, TZ }, stdio: 'inherit' });
  process.exit(r.status ?? 1);
}
if (new Date(0).getTimezoneOffset() !== -540) throw new Error(`시간대가 ${TZ}(UTC+9)이 아닙니다 — 오프셋 ${new Date(0).getTimezoneOffset()}분`);

const here = path.dirname(self);
const { minute, bootWeb } = await import('./export/base.mjs');
const { seam } = await import('./oracle/seam.mjs');
const outFile = path.resolve(here, '..', 'engine', 'tests', 'fixtures', 'lay', 'js-vectors.json');
const sliceIcu = JSON.parse(fs.readFileSync(path.resolve(here, '..', 'engine', 'tests', 'fixtures', 'lay', 'calendar-slice.json'), 'utf8')).icu;
if (sliceIcu !== (process.versions.icu || '')) throw new Error(`ICU 판이 잘린 달력 표와 다릅니다 — 이 Node ${process.versions.icu || '(없음)'} · calendar-slice.json ${sliceIcu}(머리말의 ICU 판 가드)`);

// ── 짓기 꼴 ↔ JS 값 ──
/** 짓기 꼴을 JS 값으로(Rust 검사의 같은 이름 함수와 같은 뜻). */
function build(e, ids = new Map()) {
  if (e === null || typeof e !== 'object') return e;
  if (Array.isArray(e)) return e.map(x => build(x, ids));
  if ('$u' in e) return undefined;
  if ('$num' in e) return Number(e.$num);
  if ('$s16' in e) return String.fromCharCode(...e.$s16);
  if ('$see' in e) {
    if (!ids.has(e.$see)) throw new Error(`짓기 꼴: 앞에 없는 $see ${e.$see}`);
    return ids.get(e.$see);
  }
  const keep = v => { if (e.$id) ids.set(e.$id, v); return v; };
  if ('$o' in e) { const o = keep({}); for (const [k, x] of e.$o) o[k] = build(x, ids); return o; }
  if ('$a' in e) { const a = keep([]); for (const x of e.$a) a.push(build(x, ids)); return a; }
  if ('$map' in e) { const m = keep(new Map()); for (const [k, x] of e.$map) m.set(build(k, ids), build(x, ids)); return m; }
  if ('$set' in e) { const s = keep(new Set()); for (const x of e.$set) s.add(build(x, ids)); return s; }
  throw new Error(`짓기 꼴이 아닙니다: ${JSON.stringify(e)}`);
}
/** 수 하나를 적는다 — NaN · ±Infinity · -0은 글로. */
const numOut = x => (Number.isNaN(x) ? 'NaN' : x === Infinity ? 'Infinity' : x === -Infinity ? '-Infinity' : Object.is(x, -0) ? '-0' : x);
const units = s => Array.from({ length: s.length }, (_, i) => s.charCodeAt(i));
/** 원시 값을 짓기 꼴로(글은 외톨이 서로게이트가 있으면 코드 단위로). */
function enc(v) {
  if (v === undefined) return { $u: 0 };
  if (typeof v === 'number') { const n = numOut(v); return typeof n === 'string' ? { $num: n } : n; }
  if (typeof v === 'string') return v.isWellFormed() ? v : { $s16: units(v) };
  if (v === null || typeof v === 'boolean') return v;
  throw new Error(`원시 값이 아닙니다: ${typeof v}`);
}

/** 정한 씨앗의 고른 수(0 이상 1 미만) — mulberry32. */
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const V = {};

// ── num: String(n) · JSON.stringify(n) ──
{
  const list = [0, -0, 1, -1, 0.1 + 0.2, 1e21, 1e-7, 5e-7, 123456789.125, 2 ** 53 + 2, -2.5, 1 / 3, NaN, Infinity,
    -Infinity, 5e-324, 1.7976931348623157e308, 1e-6, 1.2e-6, 123e-20, 1e20, 999999999999999900000, 4.35, 0.1, 100, 1.5e300, -1e-7,
    2 ** 31, 2 ** 32 - 1, 0.000123, 2 ** -1074 * 3, 9007199254740993, 1e16, 12345678901234567890, 0.5, 25, 1e100, 2.5e-5];
  const r = rng(3);
  const view = new DataView(new ArrayBuffer(8));
  for (let i = 0; i < 300; i++) { // 비트 무작위 — 모든 크기
    view.setUint32(0, Math.floor(r() * 2 ** 32)); view.setUint32(4, Math.floor(r() * 2 ** 32));
    const x = view.getFloat64(0);
    if (Number.isFinite(x)) list.push(x);
  }
  for (let i = 0; i < 200; i++) list.push(Math.round((r() - 0.5) * 10 ** Math.floor(r() * 12)) / 10 ** Math.floor(r() * 8)); // 십진 모양
  V.num = list.map(n => [numOut(n), String(n), JSON.stringify(n)]);
}

// ── round: Math.round ──
V.round = [-2.5, -2.4, -0.5, 0.5, 2.5, 1e15 + 0.5, -431287200.5,
  0.49999999999999994, -0.49999999999999994, -0, 0, 0.3, -0.3, 4503599627370495.5, -4503599627370495.5, 2 ** 53, NaN, Infinity, -Infinity, 1.5, -1.5, 3.7, -3.7]
  .map(x => [numOut(x), numOut(Math.round(x))]);

// ── int: x | 0 · x >>> 0 ──
V.int = [2 ** 31, 2 ** 32 + 5, -1, 3.9, -3.9, NaN,
  Infinity, -Infinity, -0, 2 ** 31 - 1, -(2 ** 31), -(2 ** 31) - 1, 2 ** 53, 2 ** 64, -(2 ** 40) - 0.5, 4294967295.5, 1e21]
  .map(x => [numOut(x), x | 0, x >>> 0]);

// ── coerce: Number · parseInt(_, 10) · parseInt(_) · parseFloat · String · Boolean · == null ──
{
  const inputs = ['', ' 12 ', '12a', '0x1f', null, { $u: 0 }, true, '1e3',
    false, 0, { $num: '-0' }, { $num: 'NaN' }, 12.5, '  -0  ', 'Infinity', '-Infinity', '+Infinity', 'infinity', '+5', '-5', '.5', '5.', '.',
    '0b101', '0o17', '0X1F', '-0x10', '  7 ﻿', '  8 　', '​9', '1_000', 'inf', 'nan', '1e', '1e+', '1e-3x', '  42abc',
    '0.0000001', '123456789012345678901234567890', '0x', '00012', '-.5e-3', '1,5', '가', '१२', '\t\n\v\f\r 3',
    [], [5], ['1', '2'], [null], [[3]], [{ $u: 0 }, 'x'], { $o: [] }, { $map: [] }, { $set: [] }];
  V.coerce = inputs.map(e => {
    const x = build(e);
    return [e, numOut(Number(x)), numOut(parseInt(x, 10)), numOut(parseInt(x)), numOut(parseFloat(x)), enc(String(x)), Boolean(x), x == null];
  });
}

// ── str: length · slice · charCodeAt · [i] · indexOf · 짝 비교(<) ──
{
  const strings = ['임진왜란', '𠀀가', 'a𠀀b', '', 'abc', '가'];
  const slices = [[1, 3], [-2, Infinity], [0, -1], [2, 1], [NaN, 2], [1.5, 3.9], [-99, 99]];
  const needles = [['b', 0], ['가', 0], ['', 2], ['𠀀', 0], ['\udc00', 0], ['a', 1], ['', 99], ['가', -5]];
  V.str = {
    one: strings.map(s => ({
      s, length: s.length, code1: numOut(s.charCodeAt(1)), at2: s[2] === undefined ? { $u: 0 } : enc(s[2]),
      slices: slices.map(([a, b]) => [numOut(a), numOut(b), units(s.slice(a, b))]),
      indexOf: needles.map(([n, from]) => [enc(n), from, s.indexOf(n, from)]),
    })),
    less: [],
  };
  const cmp = ['임진왜란', '𠀀가', 'a𠀀b', '', 'abc', 'ab', 'ｚ', '', '가나', '가', 'A', 'a', '\ud840'];
  for (const a of cmp) for (const b of cmp) V.str.less.push([enc(a), enc(b), a < b]);
}

// ── keys: JSON.stringify(JSON.parse(글)) — 정수 모양 열쇠가 먼저 ──
V.keys = ['{"b":1,"2":0,"a":1,"10":2,"-1":3,"01":4}',
  '{"4294967295":1,"4294967294":2,"a":0,"0":1}',
  '{"1.5":0,"1":1,"-0":2,"0":3," 1":4,"1 ":5,"+1":6,"1e2":7}',
  '{"a":1,"b":2,"a":3}',
  '{"z":{"9":0,"8":1,"y":2,"x":3},"3":[{"1":1,"0":0}]}',
  '{"__proto__":1,"constructor":2}']
  .map(t => [t, JSON.stringify(JSON.parse(t))]);

// ── sort: 안정 · 비교가 NaN · 비교 없는 sort() · 일관되지 않은 비교(V8 TimSort의 차례까지) ──
{
  const r = rng(7);
  const pick = n => Math.floor(r() * n);
  const cases = [];
  /** 객체 {id, k}의 정렬 — 비교 부름 수와 차례 체크섬도 적는다(알고리즘이 같아야 같다). */
  function objCase(name, cmpName, keys) {
    const items = keys.map((k, id) => ({ id, k: k === null ? undefined : k }));
    let calls = 0, sum = 0;
    const base = cmpName === 'sub' ? (a, b) => a.k - b.k : (a, b) => ((a.id * 7 + b.id * 11) % 5) - 2;
    items.sort((a, b) => { calls++; sum = (sum * 31 + a.id * 4096 + b.id) % 1000000007; return base(a, b); });
    cases.push({ name, cmp: cmpName, keys, out: items.map(o => o.id), calls, sum });
  }
  objCase('같은 값 열', 'sub', Array(10).fill(1));
  objCase('둘씩 같음', 'sub', [2, 1, 2, 1, 3, 1, 2, 3, 1, 2]);
  objCase('NaN 작게', 'sub', [3, null, 1, 2, null, 0, 5, 4]);
  objCase('NaN 사이', 'sub', [5, 4, null, 3, 2, null, 1, 0, null, 7, 6]);
  for (const n of [40, 63, 64, 65, 100, 257, 1000, 3000]) {
    objCase(`무작위 ${n} · 15% 없음`, 'sub', Array.from({ length: n }, () => (r() < 0.15 ? null : pick(20))));
  }
  for (const n of [200, 1500]) {
    let v = 0;
    objCase(`오르는 덩이 ${n} · 5% 없음`, 'sub', Array.from({ length: n }, (_, i) => (r() < 0.05 ? null : (i % 50 === 0 ? (v = pick(100)) : v++))));
    objCase(`내리는 덩이 ${n} · 5% 없음`, 'sub', Array.from({ length: n }, (_, i) => (r() < 0.05 ? null : (i % 70 === 0 ? (v = 1000 + pick(100)) : v--))));
  }
  for (const n of [300, 2000]) objCase(`모두 다름 ${n}`, 'sub', Array.from({ length: n }, () => pick(1e6) / 7));
  for (const n of [10, 100, 600]) objCase(`엇갈린 비교 ${n}`, 'weird', Array.from({ length: n }, () => 0));
  /** 원시 값 배열의 정렬 — 'num'은 (a, b) => a - b, 'none'은 비교 없는 sort(). */
  function valCase(name, cmpName, input) {
    const arr = build(input);
    if (cmpName === 'num') arr.sort((a, b) => a - b); else arr.sort();
    cases.push({ name, cmp: cmpName, input, out: arr.map(enc) });
  }
  valCase('undefined는 끝으로', 'num', [3, { $u: 0 }, 1, { $u: 0 }, 2, null, { $num: 'NaN' }, 0]);
  valCase('글 차례', 'none', ['b', 'A', '가', '𠀀', 'a', 'ｚ', 'ab', '']);
  valCase('수도 글 차례', 'none', [10, 9, 1, 100, -1, { $num: '-0' }, 0.5, 1e21, { $num: 'NaN' }, { $num: 'Infinity' }]);
  valCase('null과 undefined', 'none', [null, 'n', { $u: 0 }, 'nu', 'nulm', true, false]);
  V.sort = cases;
}

// ── minute: base.mjs의 minute ──
{
  const r = rng(11);
  const list = [-2500.5, -1, -0.5, 0, 1, 99.25, 1582.8, 1970, 2026.99, 300000,
    NaN, Infinity, -Infinity, -0, 0.5, -1.5, -0.999, 1969.999, 2000.5, 275759, 275759.5, 275760, -271820, -271821, -271822, -1e6, 1e300];
  for (let i = 0; i < 300; i++) list.push((r() - 0.5) * 10000 * (i % 3 === 0 ? 1 : 0.01) + (i % 5 === 0 ? 0 : r()));
  V.minute = list.map(y => { const m = minute(y); return [numOut(y), m === null ? null : numOut(m)]; });
}

// ── local: 지역(Asia/Seoul) 연 · 월(0부터) · 일과 오프셋 ──
V.local = ['2026-10-15T03:00:00Z', '2026-10-14T14:59:59.999Z', '2026-10-14T15:00:00Z', '2025-12-31T14:59:59.999Z', '2025-12-31T15:00:00Z',
  '2028-02-28T15:00:00Z', '1970-01-01T00:00:00Z', '2000-02-29T12:00:00Z']
  .map(t => { const ms = Date.parse(t); const d = new Date(ms); return [ms, d.getFullYear(), d.getMonth(), d.getDate(), d.getTimezoneOffset()]; });

// ── json: JSON.stringify(짓기 꼴) · JSON.parse(글)의 됨/안 됨과 다시 쓴 글 ──
{
  const stringify = [
    { $o: [['a', { $u: 0 }], ['b', 1], ['2', 'x'], ['c', [1, { $u: 0 }, { $num: 'NaN' }, null, { $num: '-0' }, { $num: 'Infinity' }]], ['d', { $o: [['10', 1], ['9', 2], ['x', { $o: [] }]] }]] },
    [],
    [[[]], { $o: [] }, ''],
    'ㄱ"\\\n\t\u0001\u001f \u007f가𠀀/<>',
    { $s16: [0xd800, 0x41, 0xdc00, 0xd83d, 0xde00, 0xdfff] },
    [1e21, 5e-7, 1e-7, 0.1, 0.30000000000000004, 123456789.125, -1e-7, 2 ** 53 + 2],
    { $o: [['m', { $map: [[1, 2]] }], ['s', { $set: [1] }], ['u', { $u: 0 }]] },
    { $o: [['1', 'a'], ['0', 'b'], ['x', true], ['4294967294', false], ['4294967295', null]] },
    { $num: '-0' }, true, null, { $num: 'NaN' },
  ];
  const parse = ['', ' \t\n\r1 ', '01', '1.', '.5', '-', '-0', '1E+2', '1e', '[1,]', '{"a":1,}', "'a'", '"\t"', 'NaN', '[1 2]', '{a:1}',
    '"\\x"', 'tru', 'true', 'null', '"\\u12"', ' [1] x', '"\\u2028"', '"\\ud800"', '"\\ud83d\\ude00"', '1e400', '-1e400', '[]', '{}', '"\\/"',
    '{"a":[1,{"b":null}],"c":"\\"q\\""}', ' 1', '[1]﻿', '" "', '"a\u0000"', '123456789012345678901234567890', '0.1e-400', '-0.0',
    '{"":1,"":2}', '[\n]', '{"a" : 1 , "b":[ ] }'];
  V.json = {
    stringify: stringify.map(e => [e, JSON.stringify(build(e))]),
    parse: parse.map(t => { try { return [t, true, JSON.stringify(JSON.parse(t))]; } catch { return [t, false, null]; } }),
  };
}

// ── seam: oracle/seam.mjs의 덤프 ──
V.seam = [
  ['uid 있는 것을 둘이 가리킴', { $o: [['a', { $o: [['uid', 'u1'], ['n', 1]], $id: 'x' }], ['b', { $see: 'x' }], ['c', [{ $see: 'x' }]]] }],
  ['스스로를 가리킴', { $o: [['uid', 'root'], ['self', { $see: 'r' }], ['list', [{ $see: 'r' }]]], $id: 'r' }],
  ['uid 없는 고리', { $o: [['k', { $o: [['back', { $see: 'top' }]] }]], $id: 'top' }],
  ['같은 uid의 사본 둘', { $o: [['p', { $o: [['uid', 'same'], ['v', 1]] }], ['q', { $o: [['uid', 'same'], ['v', 1]] }]] }],
  ['배열을 둘이 가리킴', { $o: [['a', { $a: [1, 2], $id: 'arr' }], ['b', { $see: 'arr' }]] }],
  ['Map', { $o: [['m', { $map: [['k', { $o: [['uid', 'mv']], $id: 'mv' }], [{ $o: [['key', 1]], $id: 'ok' }, 'objkey'], [{ $see: 'ok' }, 'again'], [{ $num: 'NaN' }, 1], [{ $num: 'NaN' }, 2], [0, 3], [{ $num: '-0' }, 4], ['mvref', { $see: 'mv' }]] }]] }],
  ['Set', { $o: [['s', { $set: [1, 1, { $num: '-0' }, 0, { $num: 'NaN' }, { $num: 'NaN' }, 'a', { $o: [['uid', 7]], $id: 'n7' }, { $see: 'n7' }, { $u: 0 }, null] }], ['again', { $see: 'n7' }]] }],
  ['undefined · NaN · 열쇠 차례', { $o: [['z', { $u: 0 }], ['10', [{ $u: 0 }, { $num: 'NaN' }, { $num: 'Infinity' }, { $num: '-0' }, 1e21, 5e-7]], ['2', 'x'], ['a', null], ['b', false]] }],
  ['Map 안의 Map', { $map: [[{ $map: [], $id: 'inner' }, { $set: [{ $see: 'inner' }] }]] }],
  ['맨 위 undefined', { $u: 0 }],
  ['맨 위 수', 1.5],
  ['uid가 글인 배열 원소', [{ $o: [['uid', 'e'], ['w', 'ㄱ']], $id: 'e' }, { $o: [['x', { $see: 'e' }]] }, { $see: 'e' }]],
].map(([name, e]) => [name, e, seam(build(e))]);

// ── regex: 뜻 차이 규칙의 표본(Rust 쪽은 tests/lay_wiki.rs — 과제 12a) ──
V.regex = [
  ['\\s', '', '﻿'], ['\\s', '', ' '], ['\\s', '', '　'], ['\\s', '', ' '], ['\\s', '', '​'], ['\\s', '', '᠎'],
  ['\\w', '', '가'], ['\\w', 'u', '가'], ['\\w', 'iu', 'ſ'], ['\\d', '', '٣'], ['\\d', 'u', '٣'], ['\\b', '', '가a'], ['a\\b', '', 'a가'],
  ['.', '', '\r'], ['.', '', '\n'], ['.', '', ' '], ['.', '', ' '], ['.', 's', '\n'], ['^.$', '', '𠀀'], ['^.$', 'u', '𠀀'],
  ['a', 'i', 'A'], ['ſ', 'i', 'S'], ['ſ', 'iu', 'S'], ['K', 'i', 'k'], ['K', 'iu', 'k'], ['ß', 'i', 'SS'], ['가', 'i', '가'],
].map(([src, flags, input]) => [src, flags, input, new RegExp(src, flags).test(input)]);

// ── wiki: js/wiki.js(HT.namu — 문서 렌더러)의 정규식마다 표본 글 · 함수 · 렌더 · 견본 문서(한 벌 P3 과제 12a · 갈래 C — Rust lay::m::docs::wiki · tests/lay_wiki.rs) ──
// re     [id, 갈래, 글, 답] — 답: 맞음 목록 [[UTF-16 자리, 통째, 무리 1, …] …](참여하지 않은 무리는 null · 전역(g)이 아니면 첫 맞음 하나) · 안 맞으면 null.
//        갈래 = 표본이 밟는 정규식 갈래(선택지 · 뜻 차이 규칙 — `\s` · `\w` · `\d` · `\b` · `.` · i 깃발 · 되짚기). 빈 글은 '안 맞아야 하는 표본'.
//        정규식 표(WIKI_RE)는 원본 파일에 그 글자 그대로 있어야 하고(뽑을 때 확인), wiki.js 1 ~ 511줄(캔버스 79 ~ 104줄 뺌)의 정규식 글자를 모두 덮어야 한다.
//        갈래마다 맞은 표본이 하나 이상 · 빈 갈래 표본은 안 맞음(뽑을 때 · Rust 검사가 다시 단언).
// fn     [함수, 입력, 답] — fileSpec · files · links · figureHTML · toolbarHTML · 상수(HELP · SHORTCUTS · FIGURE)
// render [글, 시각(HT_ORACLE_NOW 꼴), 그림 함수를 주나, 고리 함수를 주나, 답 {html, toc, categories}] — 고리 · 그림 함수는 아래 WIKI_LINK · WIKI_IMAGE(Rust 검사에 같은 함수)
// sample [문서 열쇠, sha12(JSON.stringify(렌더 답))] — 견본 등불 연대기(samples/sample-lantern.json)의 문서 · wiki 칸 모두(시각은 정답지 시각)
{
  const { createHash } = await import('node:crypto');
  const { installClock } = await import('./oracle/clock.mjs');
  const HT = bootWeb();
  const { runScript } = await import('./export/base.mjs');
  if (!HT.namu) runScript('js/wiki.js');
  const namu = HT.namu;
  const root = path.resolve(here, '..', '..');
  const fileText = new Map();
  const textOf = f => { if (!fileText.has(f)) fileText.set(f, fs.readFileSync(path.join(root, f), 'utf8')); return fileText.get(f); };
  const B = String.raw;
  // [id, 파일, 정규식 글자(슬래시 사이 — 원본 그대로), 깃발, 갈래 목록, 표본 [[갈래, 글] …]]
  const WIKI_RE = [
    ['esc', 'js/wiki.js', B`[&<>"']`, 'g', ['&', '<', '>', '"', "'"], [['&', 'a&b'], ['<', '<x>'], ['>', 'a>'], ['"', '"q"'], ["'", "it's"], ['', '가 abc']]],
    ['style.bad', 'js/wiki.js', B`url\s*\(|expression|javascript:|@import|behavior\s*:`, 'gi', ['url', 'expression', 'javascript', 'import', 'behavior', '\\s'],
      [['url', 'url(x)'], ['url', 'URL  ('], ['\\s', 'url\u{FEFF}('], ['expression', 'eXpReSsIoN(1)'], ['javascript', 'JavaScript:alert'], ['import', 'a @IMPORT x'], ['behavior', 'behavior : a'],
        ['', 'expre\u{17F}\u{17F}ion'], ['', 'url\u{180E}('], ['', 'color:red']]],
    ['style.keep', 'js/wiki.js', B`[^\w\s#%.,:;()\-'"!]`, 'g', ['기호', '유니코드 글자', '유니코드 숫자'],
      [['기호', 'a<b>c'], ['기호', 'a{b}&c'], ['유니코드 글자', 'color:가red'], ['유니코드 글자', 'x\u{20000}y\u{E9}'], ['유니코드 숫자', 'width:\u{663}px'], ['', 'color: #fff; width: 10%'], ['', 'a\u{FEFF}b\u{3000}c_1']]],
    ['color.hex', 'js/wiki.js', B`^#[0-9a-f]{3,8}$`, 'i', ['소문자', '대문자'], [['소문자', '#abc'], ['대문자', '#ABCDEF12'], ['', '#ab'], ['', '#abcdefabc'], ['', 'abc'], ['', '#\u{FF41}\u{FF42}\u{FF43}']]],
    ['color.name', 'js/wiki.js', B`^[a-z]{3,20}$`, 'i', ['소문자', '대문자'], [['소문자', 'red'], ['대문자', 'DarkBlue'], ['', 're'], ['', 'abcdefghijklmnopqrstu'], ['', 'red1'], ['', '\u{17F}ed'], ['', 'Kel\u{212A}']]],
    ['file', 'js/wiki.js', B`\[\[((?:파일|이미지|file)\s*:[^\]]*?)\]\]`, 'gi', ['파일', '이미지', 'file', '\\s'],
      [['파일', '앞 [[파일:a.png]] 뒤'], ['이미지', '[[이미지 : b|width=10]]'], ['file', '[[FILE:c]][[file:d]]'], ['\\s', '[[파일\u{3000}:e\n f]]'], ['', '[[\u{FB01}le:x]]'], ['', '[[파일x:y]]'], ['', '[[파일:a]b]]']]],
    ['file.head', 'js/wiki.js', B`^(파일|이미지|file)\s*:\s*`, 'i', ['파일', '이미지', 'file', '\\s'],
      [['파일', '파일:a'], ['이미지', '이미지 : b'], ['file', 'File:c'], ['\\s', 'file\u{A0}:\u{2028}c'], ['', '\u{FB01}le:x'], ['', 'x파일:a']]],
    ['file.opt', 'js/wiki.js', B`^(width|align)\s*=\s*(.+)$`, 'i', ['width', 'align', '.'],
      [['width', 'width=50%'], ['align', 'ALIGN = center'], ['.', 'width= 가\u{A0}'], ['', 'width=1\u{2028}'], ['', 'width=1\r'], ['', 'height=1'], ['', 'width=']]],
    ['file.width', 'js/wiki.js', B`^\d{1,4}(px|%)?$`, '', ['수', 'px', '%'], [['수', '50'], ['px', '1600px'], ['%', '100%'], ['', '12345'], ['', '\u{663}'], ['', '50PX'], ['', '']]],
    ['file.pct', 'js/wiki.js', B`%$`, '', ['%'], [['%', '50%'], ['', '%50']]],
    ['file.align', 'js/wiki.js', B`^(left|center|right)$`, '', ['left', 'center', 'right'], [['left', 'left'], ['center', 'center'], ['right', 'right'], ['', 'Left'], ['', 'lefty']]],
    ['restore', 'js/wiki.js', '\x01(\\d+)\x01', 'g', ['자리'], [['자리', 'a\x010\x01b\x0112\x01'], ['', '\x01a\x01'], ['', '\x01\u{663}\x01']]],
    ['brace', 'js/wiki.js', B`\{\{\{([\s\S]*?)\}\}\}`, 'g', ['한 줄', '여러 줄'], [['한 줄', 'a {{{+1 큰}}} b {{{x}}}'], ['한 줄', '{{{{x}}}}'], ['여러 줄', '{{{a\nb}}}'], ['', '{{ {x}}}']]],
    ['fn.inner', 'js/wiki.js', B`^(\S*)\s?([\s\S]*)$`, '', ['이름', '이름 없음', '빈칸'],
      [['이름', '가 각주 글'], ['이름', '\u{20000}가\n둘째'], ['이름 없음', ' 각주 글'], ['이름 없음', ''], ['빈칸', 'a\u{FEFF}b c']]],
    ['tag', 'js/wiki.js', B`<[^>]+>`, 'g', ['꼬리표'], [['꼬리표', 'a<b>c</b>'], ['', '<>'], ['', 'a < b']]],
    ['link', 'js/wiki.js', B`\[\[([^\]|]+?)(?:\|([^\]]*?))?\]\]`, 'g', ['이름', '표시 글', '빈 표시'],
      [['이름', '[[가]] [[나#다]]'], ['이름', '[[\u{20000}]]'], ['표시 글', '[[가|보일 글]]'], ['표시 글', '[[a|b|c]]'], ['빈 표시', '[[가|]]'], ['', '[[|a]]'], ['', '[[가]나]]']]],
    ['link.figure', 'js/wiki.js', B`^인물\s*:\s*`, '', ['인물'], [['인물', '인물 : 가'], ['인물', '인물:\u{3000}가'], ['', ' 인물:가']]],
    ['link.cat', 'js/wiki.js', B`^(분류|category):`, 'i', ['분류', 'category'], [['분류', '분류:가'], ['category', 'CATEGORY:a'], ['', '분류 :가'], ['', 'categories:a']]],
    ['link.file', 'js/wiki.js', B`^(파일|이미지|file):`, 'i', ['파일', '이미지', 'file'], [['파일', '파일:a'], ['이미지', '이미지:b'], ['file', 'FiLe:c'], ['', '파일 :a']]],
    ['link.http', 'js/wiki.js', B`^https?:\/\/`, 'i', ['http', 'https'], [['http', 'http://a'], ['https', 'HTTPS://b'], ['', 'ftp://c'], ['', 'https:/d']]],
    ['link.proto', 'js/wiki.js', B`^\/\/`, '', ['//'], [['//', '//a.b'], ['', '/a']]],
    ['bold', 'js/wiki.js', B`&#39;&#39;&#39;([\s\S]+?)&#39;&#39;&#39;`, 'g', ['굵게', '여러 줄'],
      [['굵게', '&#39;&#39;&#39;가&#39;&#39;&#39; &#39;&#39;&#39;나&#39;&#39;&#39;'], ['여러 줄', '&#39;&#39;&#39;a\nb&#39;&#39;&#39;'], ['', '&#39;&#39;&#39;&#39;&#39;&#39;']]],
    ['italic', 'js/wiki.js', B`&#39;&#39;([\s\S]+?)&#39;&#39;`, 'g', ['기울임'], [['기울임', '&#39;&#39;가&#39;&#39;'], ['', '&#39;가&#39;']]],
    ['strike', 'js/wiki.js', B`~~([^~\n]+?)~~`, 'g', ['취소'], [['취소', '~~가~~ ~~나~~'], ['', '~~a\nb~~'], ['', '~~~~']]],
    ['dash', 'js/wiki.js', B`(^|[^-])--([^-\n][^\n]*?[^-\n]|[^-\n])--(?!-)`, 'g', ['^', '[^-]', '긴 글', '한 글자', '(?!-)', '서로게이트'],
      [['^', '--가나--'], ['[^-]', 'a--b--'], ['긴 글', 'x--가나다--y'], ['한 글자', 'x--가--y --z--'], ['(?!-)', 'a--bc--- d--'], ['서로게이트', 'x--\u{20000}--y--z'],
        ['서로게이트', '\u{20000}--a\u{20001}--'], ['', 'a---b---'], ['', '--\n--'], ['', '----']]],
    ['under', 'js/wiki.js', B`__([^_\n]+?)__`, 'g', ['밑줄'], [['밑줄', '__가__ __b__'], ['', '____']]],
    ['sup', 'js/wiki.js', B`\^\^([^^\n]+?)\^\^`, 'g', ['위첨자'], [['위첨자', '^^2^^'], ['', '^^^^']]],
    ['sub', 'js/wiki.js', B`,,([^,\n]+?),,`, 'g', ['아래첨자'], [['아래첨자', ',,2,,'], ['', ',,,,']]],
    ['br', 'js/wiki.js', B`\[br\]`, 'gi', ['br'], [['br', '[br][BR]'], ['', '[b r]']]],
    ['date', 'js/wiki.js', B`\[(?:date|datetime)\]`, 'gi', ['date', 'datetime'], [['date', '[date]'], ['datetime', '[DateTime]'], ['', '[dates]']]],
    ['age', 'js/wiki.js', B`\[age\((\d{4})-(\d{1,2})-(\d{1,2})\)\]`, 'gi', ['age'],
      [['age', '[age(2000-1-02)]'], ['age', '[AGE(1999-12-31)]'], ['', '[age(99-1-1)]'], ['', '[age(2000-123-1)]'], ['', '[age(\u{662}000-1-1)]']]],
    ['macro', 'js/wiki.js', B`\[(?:include|youtube|nicovideo|kakaotv|vimeo|navertv|ruby)\([^\]]*\)\]`, 'gi', ['include', 'youtube', 'nicovideo', 'kakaotv', 'vimeo', 'navertv', 'ruby'],
      [['include', '[include(틀:가)]'], ['youtube', '[YouTube(abc)]'], ['nicovideo', '[nicovideo()]'], ['kakaotv', '[kakaotv(1)]'], ['vimeo', '[vimeo(x)]'], ['navertv', '[navertv(y)]'],
        ['ruby', '[ruby(글,ruby=루)]'], ['', '[\u{212A}akaotv(1)]'], ['', '[include(a]b)]']]],
    ['toc', 'js/wiki.js', B`\[(?:목차|tableofcontents)\]`, 'gi', ['목차', 'tableofcontents'], [['목차', '[목차]'], ['tableofcontents', '[TableOfContents]'], ['', '[목 차]']]],
    ['foot', 'js/wiki.js', B`\[(?:각주|footnote)\]`, 'gi', ['각주', 'footnote'], [['각주', '[각주]'], ['footnote', '[FOOTNOTE]'], ['', '[각주 ]']]],
    ['size', 'js/wiki.js', B`^([+-])(\d)\s([\s\S]*)$`, '', ['+', '-', '\\s'],
      [['+', '+2 크게'], ['-', '-1 작게\n둘째'], ['\\s', '+1\u{3000}가'], ['', '+12 x'], ['', '+\u{663} x'], ['', '*1 x']]],
    ['color', 'js/wiki.js', B`^#([0-9a-fA-F]{3,8}|[a-zA-Z]{3,20})(?:,#[0-9a-fA-F]{3,8})?\s([\s\S]*)$`, '', ['16진', '이름', '어두운 색', '되짚기'],
      [['16진', '#f00 빨강'], ['이름', '#red 빨강'], ['어두운 색', '#fff,#000 글'], ['되짚기', '#abcdefgh x'], ['', '#ab x'], ['', '#red'], ['', '#가나다 x']]],
    ['color.ishex', 'js/wiki.js', B`^[0-9a-fA-F]{3,8}$`, '', ['16진'], [['16진', 'AbC'], ['', 'red']]],
    ['block.head', 'js/wiki.js', B`^#!(folding|wiki|syntax|html)\b([^\n]*)\n?([\s\S]*)$`, '', ['folding', 'wiki', 'syntax', 'html', '\\b'],
      [['folding', '#!folding 제목\n속\n둘째'], ['wiki', '#!wiki style="a"\n속'], ['wiki', '#!wiki'], ['syntax', '#!syntax js\ncode'], ['html', '#!html<b>'], ['\\b', '#!folding가\n속'],
        ['', '#!foldingx\n속'], ['', '#!fold\n'], ['', ' #!wiki']]],
    ['box.style', 'js/wiki.js', B`style="([^"]*)"`, '', ['style'], [['style', 'x style="color:red" y style="b"'], ['', 'style=red']]],
    ['cell.opt', 'js/wiki.js', B`^<([^<>\n]*)>`, '', ['선택'], [['선택', '<-2>a'], ['선택', '<>x'], ['', '<a<b>'], ['', 'a<b>'], ['', '<a\nb>']]],
    ['cell.colspan', 'js/wiki.js', B`^-(\d+)$`, '', ['-'], [['-', '-2'], ['', '-2x'], ['', '-\u{662}']]],
    ['cell.rowspan', 'js/wiki.js', B`^\|(\d+)$`, '', ['|'], [['|', '|3'], ['', '|']]],
    ['cell.rowspan2', 'js/wiki.js', B`^(?:\^\||v\|)(\d+)$`, '', ['^|', 'v|'], [['^|', '^|2'], ['v|', 'v|3'], ['', 'V|3']]],
    ['cell.bgcolor', 'js/wiki.js', B`^bgcolor=(.+)$`, 'i', ['bgcolor'], [['bgcolor', 'bgcolor=#fff'], ['bgcolor', 'BGCOLOR=red'], ['', 'bgcolor='], ['', 'bgcolor=a\u{2029}']]],
    ['cell.color', 'js/wiki.js', B`^color=(.+)$`, 'i', ['color'], [['color', 'color=#000'], ['', 'colour=#000']]],
    ['cell.width', 'js/wiki.js', B`^width=(\d+%?|\d+px)$`, 'i', ['수', '%', 'px'], [['수', 'width=100'], ['%', 'WIDTH=50%'], ['px', 'width=20PX'], ['', 'width=20em'], ['', 'width=%']]],
    ['cell.height', 'js/wiki.js', B`^height=(\d+%?|\d+px)$`, 'i', ['수', '%', 'px'], [['수', 'height=3'], ['%', 'height=3%'], ['px', 'height=3px'], ['', 'height=3pt']]],
    ['cell.rowbgcolor', 'js/wiki.js', B`^rowbgcolor=(.+)$`, 'i', ['rowbgcolor'], [['rowbgcolor', 'rowbgcolor=#eee'], ['', 'row bgcolor=#eee']]],
    ['cell.rowcolor', 'js/wiki.js', B`^rowcolor=(.+)$`, 'i', ['rowcolor'], [['rowcolor', 'ROWCOLOR=blue'], ['', 'rowcolor']]],
    ['cell.table.bgcolor', 'js/wiki.js', B`^table\s*bgcolor=(.+)$`, 'i', ['붙임', '\\s'], [['붙임', 'tablebgcolor=#fff'], ['\\s', 'table\u{A0}bgcolor=#fff'], ['', 'table-bgcolor=#fff']]],
    ['cell.table.bordercolor', 'js/wiki.js', B`^table\s*bordercolor=(.+)$`, 'i', ['붙임', '\\s'], [['붙임', 'tablebordercolor=red'], ['\\s', 'TABLE  BORDERCOLOR=red'], ['', 'table bordercolour=red']]],
    ['cell.table.width', 'js/wiki.js', B`^table\s*width=(\d+%?|\d+px)$`, 'i', ['수', '%', 'px'], [['수', 'table width=500'], ['%', 'table width=100%'], ['px', 'tablewidth=300px'], ['', 'table width=a']]],
    ['cell.table.align', 'js/wiki.js', B`^table\s*align=(left|center|right)$`, 'i', ['left', 'center', 'right'],
      [['left', 'table align=left'], ['center', 'table align=CENTER'], ['right', 'tablealign=right'], ['', 'table align=middle']]],
    ['cell.skip', 'js/wiki.js', B`^(nopad|table)`, 'i', ['nopad', 'table'], [['nopad', 'nopad'], ['table', 'TableX'], ['', 'x table']]],
    ['cell.lead', 'js/wiki.js', B`^\s`, '', ['빈칸', '유니코드 빈칸'], [['빈칸', ' a'], ['유니코드 빈칸', '\u{FEFF}a'], ['', 'a '], ['', '\u{200B}a']]],
    ['cell.trail', 'js/wiki.js', B`\s$`, '', ['빈칸', '유니코드 빈칸'], [['빈칸', 'a '], ['유니코드 빈칸', 'a\u{3000}'], ['', 'a'], ['', 'a \n x']]],
    ['nl', 'js/wiki.js', B`\n`, 'g', ['줄'], [['줄', 'a\nb\n'], ['', 'a\rb\u{2028}']]],
    ['crlf', 'js/wiki.js', B`\r\n?`, 'g', ['\\r', '\\r\\n'], [['\\r', 'a\rb'], ['\\r\\n', 'a\r\nb\r\r\n'], ['', 'a\nb']]],
    ['block.ph', 'js/wiki.js', '^\\s*\x01\\d+\x01\\s*$', '', ['자리'], [['자리', ' \x013\x01 '], ['자리', '\x0110\x01\u{2029}'], ['', 'a\x013\x01'], ['', '\x01\x01']]],
    ['block.foot', 'js/wiki.js', B`^\s*\[(각주|footnote)\]\s*$`, 'i', ['각주', 'footnote'], [['각주', ' [각주] '], ['footnote', '[Footnote]'], ['', '[각주] x']]],
    ['block.toc', 'js/wiki.js', B`^\s*\[(목차|tableofcontents)\]\s*$`, 'i', ['목차', 'tableofcontents'], [['목차', '[목차]'], ['tableofcontents', '  [TABLEOFCONTENTS]\t'], ['', 'x[목차]']]],
    ['heading', 'js/wiki.js', B`^(={1,6})(#?) (.+?) \2\1\s*$`, '', ['=', '#', '되짚기', '\\s'],
      [['=', '== 가 =='], ['=', '====== 6 ======'], ['=', '== \u{20000} =='], ['#', '==# 접힌 #== '], ['#', '=# a # b #='], ['되짚기', '== a == b =='], ['\\s', '== a ==\u{2028}'],
        ['', '======= 7 ======='], ['', '== a ==='], ['', '=== a =='], ['', '==a=='], ['', '== a\u{2028}b =='], ['', '=# a #=x']]],
    ['hr', 'js/wiki.js', B`^-{4,9}\s*$`, '', ['----'], [['----', '----'], ['----', '---------  '], ['', '---'], ['', '----------']]],
    ['table.line', 'js/wiki.js', B`^\s*\|\|`, '', ['||'], [['||', '|| a ||'], ['||', ' \u{A0}||'], ['', '| |']]],
    ['quote', 'js/wiki.js', B`^>`, '', ['>'], [['>', '> 인용'], ['', ' > x']]],
    ['quote.head', 'js/wiki.js', B`^>\s?`, '', ['>', '\\s'], [['>', '>a'], ['>', '> a'], ['\\s', '>\u{3000}a'], ['', 'a>']]],
    ['list', 'js/wiki.js', B`^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?(.*)$`, '', ['*', '1.', '1.#n', 'a.', 'A.', 'i.', 'I.'],
      [['*', ' * 가'], ['*', ' *'], ['1.', '  1. 둘'], ['1.', ' 1.#x'], ['1.#n', ' 1.#5 다섯'], ['a.', ' a. 가'], ['A.', ' A.가'], ['i.', ' i. x'], ['I.', '   I. y'],
        ['', ' * a\u{2028}b'], ['', '* a'], ['', ' - a']]],
    ['list.more', 'js/wiki.js', B`^ {2,}\S`, '', ['들여쓴 줄'], [['들여쓴 줄', '  a'], ['들여쓴 줄', '  \u{20000}'], ['', ' a'], ['', '   ']]],
    ['list.head', 'js/wiki.js', B`^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?`, '', ['*', '1.', '1.#n', 'a.', 'A.', 'i.', 'I.'],
      [['*', ' * a'], ['1.', '  1.x'], ['1.#n', ' 1.#3'], ['a.', ' a.'], ['A.', ' A. '], ['i.', ' i.b'], ['I.', ' I.'], ['', 'a. x']]],
    ['image.line', 'js/wiki.js', B`\[\[(?:파일|이미지|file)\s*:`, 'i', ['파일', '이미지', 'file', '\\s'],
      [['파일', 'x [[파일:a]]'], ['이미지', '[[이미지 :'], ['file', '[[File:'], ['\\s', '[[file\u{FEFF}:'], ['', '[[파일a:']]],
    ['list.start', 'js/wiki.js', B`#(\d+)`, '', ['#n'], [['#n', '1.#12'], ['', '1.']]],
    ['hnum', 'js/wiki.js', B`<span class="wk-hnum" data-toc="(\d+)"><\/span>`, 'g', ['자리'],
      [['자리', '<span class="wk-hnum" data-toc="3"></span>x<span class="wk-hnum" data-toc="12"></span>'], ['', '<span class="wk-hnum" data-toc=""></span>']]],
    ['toc.ph', 'js/wiki.js', '\x02TOC\x02', 'g', ['자리'], [['자리', 'a\x02TOC\x02b\x02TOC\x02'], ['', 'TOC']]],
    ['foot.ph', 'js/wiki.js', '\x02FOOT\x02', 'g', ['자리'], [['자리', '\x02FOOT\x02'], ['', '\x02FOOT']]],
    ['links', 'js/wiki.js', B`\[\[([^\]|]+?)(?:\|[^\]]*?)?\]\]`, 'g', ['이름', '표시 글'], [['이름', '[[가]] [[나#다]]'], ['표시 글', '[[가|b]] [[c|]]'], ['', '[[|x]]']]],
    ['links.skip', 'js/wiki.js', B`^(분류|파일|이미지|category|file|https?:)`, 'i', ['분류', '파일', '이미지', 'category', 'file', 'http:', 'https:'],
      [['분류', '분류:가'], ['파일', '파일'], ['이미지', '이미지들'], ['category', 'Category'], ['file', 'files'], ['http:', 'HTTP://x'], ['https:', 'https:'], ['', 'xfile'], ['', 'http']]],
  ];
  // 원본에 그 글자 그대로 있는가 · wiki.js의 정규식 글자를 모두 덮는가(1 ~ 511줄 — 79 ~ 104줄 fitImage는 캔버스라 옮기지 않음)
  for (const [id, file, src, flags] of WIKI_RE) if (!textOf(file).includes(`/${src}/${flags}`)) throw new Error(`wiki 정규식 ${id}: ${file}에 /${src}/${flags}가 없습니다`);
  {
    const literal = /(^|[(,=:?!&|\[{;]\s*|return\s+)\/((?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^\/\n\[\\])+)\/([dgimsuy]*)/g;
    const have = new Set(WIKI_RE.filter(r => r[1] === 'js/wiki.js').map(r => `/${r[2]}/${r[3]}`));
    textOf('js/wiki.js').split('\n').forEach((line, i) => {
      if (i + 1 > 511 || (i + 1 >= 79 && i + 1 <= 104)) return;
      for (const m of line.matchAll(literal)) if (!have.has(`/${m[2]}/${m[3]}`)) throw new Error(`wiki.js ${i + 1}줄의 정규식 /${m[2]}/${m[3]}에 표본이 없습니다`);
    });
  }
  // docs 모듈 · 날짜 글이 쓰는 정규식(core.js · docs.mjs · calendar.js — 과제 12b · Rust lay::m::docs · docs::when). 틀로 만든 정규식(docPrefixRe · cellKeyRe)은 원본의 틀 글로 확인한다.
  const docKinds = HT.CELL_KINDS.filter(k => k.doc !== false).map(k => k.list).join('|');
  const DOCS_RE = [
    ['docKey.prefix', 'js/core.js', `^(${HT.DOC_PREFIXES.join('|')}):(.+)$`, '', ['people', 'track', 'category', 'house', 'view', 'map', 'surname', 'place'],
      [['people', 'people:p-1'], ['track', 'track:korea'], ['category', 'category:war'], ['house', 'house:h-on'], ['view', 'view:v1'], ['map', 'map:m1'], ['surname', 'surname:kim'],
        ['place', 'place:a:b'], ['', 'people:'], ['', 'people:a\nb'], ['', 'people:a\u{2028}'], ['', 'peoples:a'], ['', 'cell:x:leaders:a@1'], ['', 'lantern-chronicle/p-1']],
      'new RegExp(`^(${src}):(.+)$`)'],
    ['docKey.cell', 'js/core.js', `^cell:(.+?):(${docKinds}):(.+)@(-?\\d+)$`, '', ['leaders', 'cabinets', 'eras', 'capitals', 'phases', '음수', '되짚기'],
      [['leaders', 'cell:lantern-chronicle/p-1:leaders:세종@1418'], ['cabinets', 'cell:x:cabinets:김 내각@1894'], ['eras', 'cell:x:eras:가@57'], ['capitals', 'cell:x:capitals:한성@1394'],
        ['phases', 'cell:x:phases:전기 (체계)@-100'], ['음수', 'cell:x:eras:나@-57'], ['되짚기', 'cell:a:b:leaders:x@1'], ['되짚기', 'cell:x:leaders:a@b@12'], ['', 'cell:x:ranks:a@1'],
        ['', 'cell:x:leaders:a@1.5'], ['', 'cell:x:leaders:a'], ['', 'cell::leaders:a@1']],
      'full: new RegExp(`^cell:(.+?):(${src}):(.+)@(-?\\\\d+)$`)'],
    ['docImage.head', 'js/core.js', B`^(파일|이미지|file)\s*:\s*`, 'i', ['파일', '이미지', 'file'], [['파일', '파일:a'], ['이미지', '이미지 : b'], ['file', 'FILE:c'], ['', 'x파일:a']]],
    ['docs.image', 'prototype/scripts/export/docs.mjs', B`^data:(image\/(png|jpeg|webp));base64,`, '', ['png', 'jpeg', 'webp'],
      [['png', 'data:image/png;base64,AAA'], ['jpeg', 'data:image/jpeg;base64,'], ['webp', 'data:image/webp;base64,QQ=='], ['', 'data:image/gif;base64,'], ['', 'DATA:image/png;base64,'], ['', ' data:image/png;base64,']]],
    ['docs.figure', 'prototype/scripts/export/docs.mjs', B`^인물\s*:\s*(.+)$`, '', ['인물'], [['인물', '인물: 가'], ['인물', '인물:  '], ['', '인물:'], ['', '인물:a\nb'], ['', '인물a']]],
    ['docs.group', 'prototype/scripts/export/docs.mjs', B`^단체\s*:\s*(.+)$`, '', ['단체'], [['단체', '단체 : 청림'], ['', '단체:']]],
    ['describe.year', 'js/calendar.js', B`^(기원전 )?\d+년 `, '', ['기원후', '기원전'], [['기원후', '1592년 5월 23일'], ['기원전', '기원전 57년 3월'], ['', '1592년'], ['', '년 5월']]],
  ];
  for (const [id, file, src, flags, branches, samples, literal] of DOCS_RE) {
    if (!textOf(file).includes(literal || `/${src}/${flags}`)) throw new Error(`docs 정규식 ${id}: ${file}에 ${literal || `/${src}/${flags}`}가 없습니다`);
    WIKI_RE.push([id, file, src, flags, branches, samples]);
  }
  // 답의 꼴은 원본이 그 정규식을 쓰는 꼴 그대로 — 't': `.test`(참거짓) · WIKI_SUB의 것: `.replace(정규식, 그 글)`의 답 · 나머지: 맞음 목록(전역이면 콜백이 받는 맞음 모두 ·
  // 아니면 `.match`의 첫 맞음). 서로게이트 짝을 반쪽씩 맞추는 JS(코드 단위)와 글자 단위인 Rust가 맞음 자리로는 갈려도 쓰는 꼴의 답은 같아야 하므로 쓰는 꼴로 견준다.
  const WIKI_TEST = new Set(['color.hex', 'color.name', 'file.width', 'file.pct', 'file.align', 'link.cat', 'link.file', 'link.http', 'link.proto', 'color.ishex', 'cell.skip', 'cell.lead',
    'cell.trail', 'block.ph', 'block.foot', 'block.toc', 'hr', 'table.line', 'quote', 'list.more', 'list.head', 'image.line', 'links.skip']);
  const WIKI_SUB = { 'style.bad': '', 'style.keep': '', 'file.head': '', tag: '', 'link.figure': '', bold: '<b>$1</b>', italic: '<i>$1</i>', strike: '<s>$1</s>', dash: '$1<s>$2</s>',
    under: '<u>$1</u>', sup: '<sup>$1</sup>', sub: '<sub>$1</sub>', br: '<br>', macro: '', toc: '\x02TOC\x02', foot: '\x02FOOT\x02', nl: '<br>', crlf: '\n', 'quote.head': '', 'docImage.head': '', 'describe.year': '' };
  for (const id of [...WIKI_TEST, ...Object.keys(WIKI_SUB)]) if (!WIKI_RE.some(r => r[0] === id)) throw new Error(`wiki 정규식 표에 없는 id ${id}`);
  const answerOf = (id, re, text) => {
    if (WIKI_TEST.has(id)) { re.lastIndex = 0; return re.test(text); }
    if (id in WIKI_SUB) return enc(text.replace(re, WIKI_SUB[id]));
    const out = [];
    const row = m => [m.index, ...Array.from(m, g => (g === undefined ? null : enc(g)))];
    if (re.global) { re.lastIndex = 0; for (const m of text.matchAll(re)) out.push(row(m)); }
    else { const m = re.exec(text); if (m) out.push(row(m)); }
    return out.length ? out : null;
  };
  const reRows = [];
  for (const [id, , src, flags, branches, samples] of WIKI_RE) {
    const hit = new Set();
    for (const [branch, text] of samples) {
      const matched = new RegExp(src, flags.replace('g', '')).test(text);
      if (branch && !branches.includes(branch)) throw new Error(`wiki 정규식 ${id}: 모르는 갈래 ${branch}`);
      if (branch && !matched) throw new Error(`wiki 정규식 ${id}: 갈래 ${branch}의 표본 ${JSON.stringify(text)}이(가) 맞지 않습니다`);
      if (!branch && matched) throw new Error(`wiki 정규식 ${id}: 안 맞아야 할 표본 ${JSON.stringify(text)}이(가) 맞았습니다`);
      if (branch) hit.add(branch);
      if (!text.isWellFormed()) throw new Error(`wiki 정규식 ${id}: 표본은 외톨이 서로게이트 없이 — ${JSON.stringify(text)}`);
      reRows.push([id, branch, text, answerOf(id, new RegExp(src, flags), text)]);
    }
    for (const b of branches) if (!hit.has(b)) throw new Error(`wiki 정규식 ${id}: 갈래 ${b}에 맞은 표본이 없습니다`);
  }

  // 고리 · 그림 함수(Rust 검사 tests/lay_wiki.rs의 wiki_link · wiki_image와 같은 뜻)
  const WIKI_LINK = name => (name.startsWith('없') ? { missing: true } : name.includes('빈') ? { uid: `u/${name}`, empty: true } : name.includes('무') ? null : name.includes('제목') ? { uid: `u/${name}`, title: `T<${name}>` } : { uid: `u/${name}` });
  const WIKI_IMAGE = name => (name.includes('없음') ? null : name.includes('빈그림') ? { uid: `img/${name}` } : {
    uid: name.includes('아이디') ? '' : `img/${name}`, id: name.includes('아이디') ? `id-${name}` : '', name, src: `data:image/png;base64,QUJD${name.length}`,
    width: name.includes('작') ? 0 : 64 + name.length, height: name.includes('납작') ? 0 : 32, caption: name.includes('캡') ? `캡션 <${name}> & 글` : '',
    credit: name.includes('출처') ? '출처 "글"' : '', alt: name.includes('대체') ? `대체 '${name}'` : '',
  });
  const render = (text, now, image = true, link = true) => {
    const RealDate = globalThis.Date;
    installClock(now);
    try {
      const opts = {};
      if (link) opts.link = WIKI_LINK;
      if (image) opts.image = WIKI_IMAGE;
      const r = namu.render(text, opts);
      return { html: r.html, toc: r.toc, categories: r.categories };
    } finally { globalThis.Date = RealDate; }
  };
  const NOW = '2026-10-15T12:00:00+09:00';
  const NOW_UTC_EVE = '2026-10-15T08:30:00+09:00'; // UTC로는 하루 전(2026-10-14T23:30Z) — [date]는 UTC 날짜 · [age]는 지역 날짜
  const NOW_LEAP = '2028-02-29T00:30:00+09:00'; // 지역은 윤날 · UTC는 2월 28일
  const RENDER = [
    ['== 개요 ==\n[목차]\n본문 \'\'\'굵게\'\'\' \'\'기울임\'\' ~~취소~~ --줄--, __밑줄__ ^^위^^ ,,아래,, [br] 끝\n=== 둘째 ===\n==== 셋째 ====\n== 다시 ==\n===# 접힌 #===', NOW],
    ['=== 셋째부터 ===\n== 둘 ==\n==== 넷 ====\n===== 다섯 =====\n=== 셋 ===\n====== 여섯 ======\n[tableofcontents]\n== 끝 ==', NOW],
    ['[[가]] [[나|보일 글]] [[없는 것]] [[빈 문서]] [[무엇]] [[제목 있음]] [[인물: 이름]] [[인물:둘|표시]] [[분류:첫째]] [[category: 둘째 :x]] [[파일:a.png]] [[https://a.b/c|바깥]] [[//c.d]] [[#앵커]] [[다#앵커]] [[ 공백 ]] [[a|]]', NOW],
    ['각주 하나[* 첫 각주] 둘[*가 이름 각주] 셋[*가 같은 이름] 넷[* [[가]] 고리 각주] 다섯[*<b>꼬리표</b>] 여섯[*  두 칸] 일곱[*] 여덟[* [* 안의 각주]]\n[각주]\n뒤', NOW],
    ['각주만[* 끝에 붙음]\n[[분류:가]]\n[[분류:나]]', NOW],
    ['{{{#!folding 접기 [[가]]\n속 글 \'\'\'굵게\'\'\'\n}}}\n{{{#!folding\n제목 없음}}}\n{{{#!wiki style="color:red; background:url(x); width:10%" 덤\n상자 속 [[나]]\n}}}\n{{{#!wiki\n}}}\n{{{#!syntax js\nconst a = "<b>";\n}}}\n{{{#!html <i>그대로</i>}}}\n{{{+2 큰 여러\n줄}}}\n{{{코드\n여러 줄 <a>}}}', NOW],
    ['인라인 {{{+1 크게}}} {{{-2 작게 [[가]]}}} {{{#f00 빨강}}} {{{#red 빨강}}} {{{#fff,#000 두 색}}} {{{#abcdefgh 이름}}} {{{#가나 아님}}} {{{코드 <b>}}} {{{#!wiki 한 줄}}} {{{{넷}}}}', NOW],
    ['||<-2> 합침 ||\n|| 왼쪽 ||<|2>세로|| 가운데 ||\n||<^|3>a||<v|2>b||<:>c||<(>d||<)>e||\n||<bgcolor=#eee><color=red>색||<bgcolor=red;x>나쁨||<width=50%><height=20px>크기||\n||<rowbgcolor=#ddd><rowcolor=blue>줄||<table bgcolor=#fff><table bordercolor=#000><table width=100%><table align=center>표||<nopad>무시||<알 수 없음>글||\n||<-1>하나||<-99999999999999999999999>큼||', NOW],
    ['|| 여러\n줄 칸 || 둘 ||\n|| 셋 ||\n||<tablealign=left>a||\n|| 끝나지 않음', NOW],
    ['> 인용 [[가]]\n>> 겹 인용\n> 다시\n바깥\n> 둘째 인용', NOW],
    [' * 하나\n * 둘\n  이어진 줄\n  * 안쪽\n   1. 번호\n   1. 번호 둘\n * 셋\n 1.#5 다섯부터\n 1. 여섯\n a. 가\n A. 나\n i. 다\n I. 라\n * 별\n\n 1. 새 목록', NOW],
    ['그림 앞 [[파일:둘.png|width=50%|align=center]] 그림 뒤\n[[파일:없음.png]][[이미지:캡 출처 대체.png|align=left]]\n[[파일:빈그림]]\n[[file:아이디 작 납작|width=200px]]\n[[파일:]]\n * [[파일:목록 속]]\n|| [[파일:표 속]] ||', NOW],
    ['그림 함수 없음 [[파일:둘.png]] 글\n[[파일:셋.png]]', NOW, false],
    ['고리 함수 없음 [[가]] [[나|표시]]', NOW, true, false],
    ['날짜 [date] [datetime] [DATE] 나이 [age(2000-10-15)] [age(2000-10-16)] [age(2000-10-14)] [age(0099-01-01)] [age(2000-13-40)] [age(1980-02-29)] [AGE(2026-12-31)]', NOW],
    // 0 ~ 99년은 `new Date(y, …)`가 1900년대로 읽는다(MakeDate) — 경계(0 · 99 · 100) · 달 넘침으로 2000년 · 달 모자람으로 1899년 · 없는 윤날(1909-02-29 → 3월 1일) · 생일 앞뒤(판정 R61 · M5)
    ['나이 0 ~ 99년 [age(0000-01-01)] [age(0000-0-0)] [age(0050-10-15)] [age(0050-10-16)] [age(0099-12-31)] [age(0099-13-01)] [age(0100-01-01)] [age(0009-2-29)] [age(0026-10-15)]', NOW],
    ['날짜 [date] 나이 [age(2000-10-15)] [age(2000-10-16)]', NOW_UTC_EVE],
    ['날짜 [date] 나이 [age(2000-02-29)] [age(2001-03-01)] [age(2004-02-29)]', NOW_LEAP],
    ['[include(틀:가)] [youtube(x)] [ruby(글, ruby=루)] [목차] [각주] 글 [br]', NOW],
    ['----\n---------\n----------\n---\n 1\x017\x01 \n\x010\x01', NOW],
    ['줄\r\n바꿈\r옛 줄\n\n\n문단 둘\u{2028}같은 줄\n== a\u{2028}b ==\n== \u{20000} ==', NOW],
    ['--시작-- a--b-- x--가나다--y a--bc--- d-- x--\u{20000}--y--z', NOW],
    ['== [[가|표시 제목]] 과 [[나]] ==\n== {{{+1 큰 제목}}} ==\n본문', NOW],
    ['', NOW],
    ['   \n\t\n', NOW],
  ];
  const renderRows = RENDER.map(([text, now, image = true, link = true]) => {
    const r = render(text, now, image, link);
    if (!r.html.isWellFormed()) throw new Error(`wiki 렌더 표본의 답에 외톨이 서로게이트 — ${JSON.stringify(text)}`);
    return [text, now, image, link, r];
  });

  const fnRows = [];
  for (const x of ['파일:a.png', '파일 : 가 나 |width=50%|align=CENTER', 'file:x|width=0', 'file:x|width=12345', 'file:x|width=200%', 'file:x|WIDTH = 30PX', 'image:x', '이미지:y|align=middle|align=left',
    'file:z|width=\u{663}', 'file:w|foo=bar|width=10', '파일:', 'file:a| width=5 ', 'file:a|width=007', 'file:a|width=\u{2028}', 'FILE\u{3000}:\u{A0}b|align=Right'])
    fnRows.push(['fileSpec', x, namu.fileSpec(x)]);
  for (const x of ['[[파일:a.png]] 글 [[이미지:b|width=10]] [[파일:a.png]]', '', '글만', '[[file:x|align=left]][[파일:y]]', '[[\u{FB01}le:z]]']) fnRows.push(['files', x, namu.files(x)]);
  for (const x of ['[[가]] [[나|보임]] [[가]] [[분류:x]] [[파일:y]] [[https://z]] [[다#앵커]] [[ 라 ]] [[#앵커만]] [[http:x]] [[category:c]] [[이미지들]] [[filed]]', '', '[[a|b|c]] [[ a ]]'])
    fnRows.push(['links', x, namu.links(x)]);
  const figSpecs = [
    [{ name: 'a', width: '', align: '' }, null],
    [{ name: 'a<b>', width: '50%', align: 'center' }, WIKI_IMAGE('캡 출처 대체')],
    [{ name: 'b', width: '', align: 'left' }, { uid: 'img/b' }],
    [{ name: 'c', width: '120px', align: 'right' }, WIKI_IMAGE('작')],
    [{ name: 'd', width: '', align: '' }, WIKI_IMAGE('출처만')],
    [{ name: 'e', width: '', align: '' }, WIKI_IMAGE('아이디')],
    [{ name: 'f&', width: '', align: '' }, { src: 'data:image/png;base64,x', width: 10, height: 20.5, name: 'g' }],
    [{ name: 'h', width: '', align: '' }, { src: 'x"y', caption: '', credit: '', alt: '' }],
  ];
  for (const [spec, g] of figSpecs) fnRows.push(['figureHTML', [spec, g], namu.figureHTML(spec, g)]);
  for (const o of [{}, { compact: true }, { image: true }, { compact: true, image: true }]) fnRows.push(['toolbarHTML', o, namu.toolbarHTML(o)]);
  fnRows.push(['HELP', null, namu.HELP], ['SHORTCUTS', null, namu.SHORTCUTS], ['FIGURE', null, namu.FIGURE]);
  // docs.mjs의 sizeOf(내보내지 않는 함수 — 원본 글을 그대로 떠서 돌림 · Rust docs::size_of): 그림 사전에 width · height가 없을 때 base64 머리(atob)에서 픽셀 크기를 읽는다.
  // 정답지 자료의 그림은 모두 크기가 적혀 있어 닿지 않으므로 여기서 png · webp(VP8 · VP8L · VP8X · 모르는 조각) · jpeg(SOF0 · DHT 건너 SOF2 · 깨진 마디) · 못 푸는 base64를 견준다.
  {
    const src = textOf('prototype/scripts/export/docs.mjs');
    const a = src.indexOf('function sizeOf(b64)');
    const b = src.indexOf('\n}\n', a);
    if (a < 0 || b < 0) throw new Error('docs.mjs에 sizeOf가 없습니다');
    const sizeOf = new Function(`${src.slice(a, b + 2)}; return sizeOf;`)();
    const b64 = bytes => Buffer.from(bytes).toString('base64');
    const pad = (head, n) => [...head, ...Array(Math.max(0, n - head.length)).fill(0)];
    const at = (arr, pos, vals) => { const out = arr.slice(); vals.forEach((v, k) => { out[pos + k] = v; }); return out; };
    const riff = chunk => pad([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, ...chunk.split('').map(c => c.charCodeAt(0))], 40);
    const samples = [
      ...(JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8')).images || []).map(g => g.src.slice(g.src.indexOf(',') + 1)),
      b64(at(pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52], 33), 16, [0x80, 0, 0, 1, 0, 0, 1, 0x2c])),
      b64(at(riff('VP8 '), 26, [0x2c, 0xc1, 0x90, 0x41])),
      b64(at(riff('VP8L'), 21, [0xff, 0xff, 0xff, 0xff])),
      b64(at(riff('VP8X'), 24, [0x10, 0x20, 0x03, 0x40, 0x50, 0x06])),
      b64(riff('ABCD')),
      b64([0xff, 0xd8, 0xff, 0xe0, 0, 16, ...Array(14).fill(1), 0xff, 0xc0, 0, 17, 8, 0x01, 0xe0, 0x02, 0x80, ...Array(12).fill(0)]),
      b64([0xff, 0xd8, 0xff, 0xc4, 0, 4, 0, 0, 0xff, 0xc2, 0, 17, 8, 0, 0x30, 0, 0x40, ...Array(12).fill(0)]),
      b64([0xff, 0xd8, 0x00, 0xc0, 0, 17, 8, 0, 0x30, 0, 0x40, ...Array(12).fill(0)]),
      b64([0xff, 0xd8, 0xff, 0xc0, 0, 17]),
      'ab$c', 'QQ=', 'QUJDRA', ' iVBO Rw0K\tGgoAAAANSUhEUgAAAEAAAABA', '', '가가가가', 'R0lGODlhAQABAAAAACw=',
    ];
    for (const x of samples) fnRows.push(['sizeOf', x, sizeOf(x)]);
  }

  // 견본 문서: documents의 값(글 또는 {text}) · 어디든 wiki 칸(글) — 적힌 차례
  const sample = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
  const docs = [];
  for (const [k, v] of Object.entries(sample.documents || {})) docs.push([`documents/${k}`, typeof v === 'string' ? v : (v && v.text) || '']);
  const walk = (x, at) => {
    if (Array.isArray(x)) x.forEach((y, i) => walk(y, `${at}/${i}`));
    else if (x && typeof x === 'object') for (const [k, v] of Object.entries(x)) { if (k === 'wiki' && typeof v === 'string') docs.push([`${at}/wiki`, v]); else if (k !== 'documents' || at) walk(v, `${at}/${k}`); }
  };
  walk(sample, '');
  const sha12 = t => createHash('sha256').update(t).digest('hex').slice(0, 12);
  const sampleRows = docs.map(([key, text]) => [key, sha12(JSON.stringify(render(text, NOW)))]);
  if (sampleRows.length < 200) throw new Error(`견본 문서가 ${sampleRows.length}개뿐입니다`);

  // 날짜 글(docs · metro의 when — HT.cal.describe · cal.formatT · HT.formatDate · HT.formatRange · HT.altText · 고침 1회차): 다른 달력 날짜를 사람이 읽는 글로.
  // 정답지 자료에는 닿는 날짜 글이 없어(서력 날짜만) 여기가 유일한 그물이다 — 잘린 표 tests/fixtures/lay/calendar-slice.json이 덮는 날짜(−2433 ~ 2127년)로만.
  // 행 [종류, 갈래, 입력, 답] — 갈래(WHEN_BRANCHES)마다 행이 하나 이상(뽑을 때 · Rust 검사가 단언).
  const WHEN_BRANCHES = ['음력', '윤달', '해 바뀜', '같은 해 줄임', '연월', '부터', '중국 음력', '이슬람력', '움 알쿠라', '페르시아력', '그레고리력', '율리우스력', '양력',
    'x', '시', '분', '세기', '기원전', '못 읽음', 'formatT', 'formatDate', 'formatRange', '인물', 'altText',
    // 과제 Y(갈래 C 재검토 Minor): 다른 달력 + 시 · 서력 해만 · 자정 직전의 시 자름(Math.min(23, …)) · 값이 수가 아닌 formatDate · 세기 글의 마지막 해 · 인물의 미정 · 생몰만 적은 이설
    '다른 달력 시', '서력 해만', '자정 직전', '글 값', '세기 끝', '인물 미정', '생몰 이설'];
  const whenRows = [];
  {
    const cal = HT.cal;
    const ok = text => { const r = cal.parse(text); if (!r || !r.ok) throw new Error(`날짜 글을 읽지 못함: ${text}`); return r; };
    let leap = '';
    for (let y = 1590; y < 1700 && !leap; y++) for (let m = 1; m <= 12 && !leap; m++) { const t = `음력 ${y}-윤${String(m).padStart(2, '0')}-10`; const r = cal.parse(t); if (r && r.ok) leap = t; }
    if (!leap) throw new Error('윤달 표본을 찾지 못함');
    const describe = [
      ['음력', '음력 1592-04-13'], ['같은 해 줄임', '음력 1592년 4월 13일'], ['윤달', leap], ['해 바뀜', '음력 1592-12-20'], ['연월', '음력 1592-04'], ['부터', '음력 1600'],
      ['중국 음력', '중국 음력 1644-03-19'], ['이슬람력', '이슬람력 1000-01-01'], ['움 알쿠라', '움알쿠라 1440-09-01'], ['페르시아력', '페르시아력 1300-01-01'],
      ['그레고리력', '그레고리력 1500-03-01'], ['율리우스력', '율리우스력 1700-02-29'], ['양력', '1592-05-23'], ['양력', '1592년 5월'], ['x', 1592.5], ['x', -56.25],
      ['시', '1592-05-23 13시'], ['분', '1592-05-23 13:05'], ['분', '음력 1592-04-13 9시 30분'], ['세기', '3세기 중반'], ['세기', '기원전 2세기'],
      ['기원전', '기원전 57-04-01'], ['기원전', '음력 기원전 100-01-01'], ['못 읽음', '음력 1592-13-01'],
      ['다른 달력 시', '음력 1592-04-13 15시'], ['다른 달력 시', '이슬람력 1000-01-01 9시'], ['서력 해만', '1592'], ['서력 해만', '기원전 57'],
    ];
    for (const [b, text] of describe) {
      const r = cal.parse(text);
      if (b !== '못 읽음') ok(text);
      whenRows.push(['describe', b, text, cal.describe(r)]);
    }
    for (const [t, prec] of [[1592.5, 'y'], [1592.5, 'm'], [1592.5, 'd'], [1592.5, 'x'], [1592.5, 'h'], [1592.5, 'min'], [-56.3, 'd'], [1592.999, 'min'], [0.5, 'd'], [2028.16, 'h'], [null, 'd']])
      whenRows.push(['formatT', 'formatT', [t, prec], cal.formatT(t, prec)]);
    { // 자정 직전(하루의 0.9999) — 분이 1440으로 반올림돼도 시는 Math.min(23, …)으로 23에 머문다(분은 60)
      const J = cal.jdnCivil(1592, 5, 23);
      for (const prec of ['h', 'min']) { const t = cal.tOf(J, 0.9999); whenRows.push(['formatT', '자정 직전', [t, prec], cal.formatT(t, prec)]); }
    }
    const lunar = ok('음력 1592-04-13');
    const islamic = ok('이슬람력 1000-01-01');
    for (const [t, at] of [[lunar.t, '음력 1592-04-13'], [lunar.t + 0.5, '음력 1592-04-13'], [1592, ''], [1592, null], [null, null], [-108, null], [islamic.t, '이슬람력 1000-01-01'], [ok('1592-05-23').t, '1592-05-23']])
      whenRows.push(['formatDate', 'formatDate', [t, at], HT.formatDate(t, at)]);
    // 값이 수가 아님: 날짜 글이 있으면(atFits가 참 — typeof t !== 'number') 그 글로, 없으면 HT.formatYear(글) — `y + 1e-9`가 글 잇기라 '1592'는 '1년'
    for (const [t, at] of [['1592', null], ['1592', '1592-05-23'], [null, '1592-05-23'], [true, null]])
      whenRows.push(['formatDate', '글 값', [t, at], HT.formatDate(t, at)]);
    { // 세기로 적은 끝 — 값이 구간의 마지막 해(r.last)여도 날짜 글이 맞는다(atFits)
      const c = ok('3세기 말');
      whenRows.push(['formatDate', '세기 끝', [c.last, '3세기 말'], HT.formatDate(c.last, '3세기 말')]);
    }
    const end = ok('1598-11-19');
    const items = [
      { start: lunar.t, startAt: '음력 1592-04-13', end: end.t, endAt: '1598-11-19' },
      { start: lunar.t, startAt: '음력 1592-04-13', ongoing: true },
      { start: 1592, endUnknown: true },
      { startUnknown: true, start: 1590, end: 1600 },
      { start: 1592, end: 1592 },
      { start: 1592 },
      { start: -57, end: 668 },
      { kind: 'figure', start: lunar.t, startAt: '음력 1592-04-13', endY: end.t, endYAt: '1598-11-19' },
      { kind: 'figure', start: 1592, endY: 1592 },
      { kind: 'figure', start: 1592, ongoing: true },
    ];
    for (const it of items) whenRows.push(['formatRange', it.kind === 'figure' ? '인물' : 'formatRange', it, HT.formatRange(it)]);
    for (const it of [{ kind: 'figure', startUnknown: true, start: 1590, endY: 1600 }, { kind: 'figure', start: 1592, endUnknown: true, endY: 1600 }])
      whenRows.push(['formatRange', '인물 미정', it, HT.formatRange(it)]);
    const alts = [
      [{ start: lunar.t, startAt: '음력 1592-04-13', label: '근거' }, { start: 1590, end: 1600 }],
      [{ end: islamic.t, endAt: '이슬람력 1000-01-01', label: '다른 끝' }, { start: 1580, startUnknown: true }],
      [{ ongoing: true, label: '아직' }, { start: 1590, startAt: null }],
      [{ start: 1600 }, { start: 1590, end: 1610, ongoing: true }],
      [{ label: '글만' }, { start: 1590, end: 1600 }],
      [{ start: 1595, end: 1595, label: '한 해' }, { start: 1590, end: 1600, endUnknown: true }],
    ];
    for (const [a, base] of alts) whenRows.push(['altText', 'altText', [a, base], HT.altText(a, base) ?? null]);
    // 생몰만 적은 이설(인물이 아닌 갈래 — altDated는 참이고 칸의 구간은 통설로 채워진다)
    for (const [a, base] of [[{ birth: 1588, death: 1640, label: '생몰만' }, { start: 1590, end: 1600 }], [{ death: 1640, label: '죽음만' }, { start: 1590, endUnknown: true }]])
      whenRows.push(['altText', '생몰 이설', [a, base], HT.altText(a, base) ?? null]);
    for (const r of whenRows) if (typeof r[3] === 'string' && !r[3].isWellFormed()) throw new Error(`날짜 글 답에 외톨이 서로게이트 — ${JSON.stringify(r[2])}`);
    const seen = new Set(whenRows.map(r => r[1]));
    for (const b of WHEN_BRANCHES) if (!seen.has(b)) throw new Error(`날짜 글 갈래 ${b}에 행이 없습니다`);
  }

  V.wiki = { re: reRows, branches: WIKI_RE.map(r => [r[0], r[4]]), fn: fnRows, render: renderRows, sample: sampleRows, when: whenRows, whenBranches: [WHEN_BRANCHES] };
}

// ── cmp16: HT.cmp16(a, b) — 글 비교의 UTF-16 코드 단위 차례(js/core.js · ICU `localeCompare` 대신 — 한 벌 P3 과제 4) ──
// 행 [a, b, HT.cmp16(a, b), 코드 포인트(UTF-8 바이트) 차례일 때의 부호]. 뒤의 부호는 'UTF-16 차례가 코드 포인트 차례와 갈리는 쌍'이 갈래마다 몇인지 세려는 것(Rust 검사가 하한을 단언).
// 정답지가 지나지 않는 곳(core.js 셋 · timeline.js 승계선)의 유일한 그물이라, ICU와도 코드 포인트와도 갈리기 쉬운 쌍을 갈래별로 모았다. 쌍은 두 방향으로 적는다.
{
  const HT = bootWeb(); // 정답은 웹 코드의 HT.cmp16 그 자체
  const NFD = t => t.normalize('NFD');
  const cpSign = (a, b) => {
    const x = Array.from(a, c => c.codePointAt(0));
    const y = Array.from(b, c => c.codePointAt(0));
    for (let i = 0; i < Math.min(x.length, y.length); i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
    return Math.sign(x.length - y.length);
  };
  const group = pairs => pairs.flatMap(([a, b]) => (a === b ? [[a, b]] : [[a, b], [b, a]])).map(([a, b]) => {
    const r = HT.cmp16(a, b);
    if (r !== (a < b ? -1 : a > b ? 1 : 0)) throw new Error(`HT.cmp16이 JS 글 비교와 다릅니다: ${JSON.stringify([a, b])} → ${r}`);
    return [enc(a), enc(b), r, cpSign(a, b)];
  });
  V.cmp16 = {
    // 대소문자: UTF-16은 대문자(65 ~ 90)가 소문자(97 ~ 122)보다 앞 — ICU는 a < B
    case: group([['K', 'e'], ['Kb', 'ea'], ['A', 'a'], ['Z', 'a'], ['a', 'B'], ['ab', 'Ab'], ['Zebra', 'apple'], ['x', 'X'], ['abc', 'abC'], ['east-asia', 'East-asia'], ['KoreanTimeLine', 'koreanTimeLine']]),
    // 실자료 꼴의 uid(승계선 정렬이 견주는 q.uid)
    korea: group([['KoreanTimeLine/p-mu6ofeucoxk8', 'east-asia-base/korea-pwch5w0'], ['KoreanTimeLine/p-mu6ofeucoxk8', 'east-asia-base/korea-p3c8dvg'], ['KoreanTimeLine/p-a', 'KoreanTimeLine/p-b'],
      ['east-asia-base/korea-p128h1al', 'east-asia-base/korea-p3c8dvg'], ['east-asia-base/korea-p128h1al', 'east-asia-base/korea-p128h1am'], ['lantern-chronicle/p-1', 'east-asia-base/korea-p1'],
      ['east-asia-base/china-p9', 'east-asia-base/korea-p1'], ['east-asia-base/korea-p10', 'east-asia-base/korea-p9'], ['east-asia-base/korea-p1', 'east-asia-base/korea-p1']]),
    // 한글 · 영문 · 한자 섞임 — UTF-16: 영문 < BMP 한자(4E00~) < 한글 음절(AC00~) < 전각 영문(FF21~) · 확장 한자는 서로게이트(D840~)라 한글 뒤 · 전각 영문 앞
    script: group([['가', 'a'], ['가', 'A'], ['가', '一'], ['漢', '가'], ['서울', 'Seoul'], ['한양', '漢陽'], ['漢陽', 'Seoul'], ['가', '𠀀'], ['𠀀', 'a'], ['a가', 'a一'], ['1가', '가1'], ['ｚ', '가'], ['ｚ', '𠀀'], ['가나다', '가나다라'], ['임진왜란', '임진왜란 ']]),
    // 기호 — UTF-16은 ASCII 값 차례('-' 45 < '/' 47 < ':' 58 < '_' 95 < '~' 126), ICU는 '_' < '-'
    punct: group([['_', '-'], ['a_b', 'a-b'], ['a_b', 'aB'], ['a-b', 'a/b'], ['x_1', 'x-1'], ['a b', 'a_b'], ['a.b', 'a-b'], ['a:b', 'a;b'], ['(a)', '[a]'], ['~', 'a'], ['~', 'Z'], ['a~', 'a'], ['a/b', 'a_b']]),
    // 같은 글자 다른 꼴(NFC ↔ NFD) — ICU는 같다(0), UTF-16은 코드 단위가 달라 같지 않다
    nfd: group([['한', NFD('한')], ['é', NFD('é')], ['Å', NFD('Å')], ['한a', NFD('한') + 'a'], ['가', NFD('가')], [NFD('é'), 'f'], ['é', 'f'], [NFD('한'), NFD('한')], ['한', '한']]),
    // 빈 글 — 날 NUL · 외톨이 서로게이트도 소스에는 이스케이프로만 적는다(날 글자는 UTF-8 소스에서 U+FFFD로 바뀌어 버린다)
    empty: group([['', ''], ['', 'a'], ['', '가'], ['', ' '], ['', '\0'], ['', '𠀀'], ['', '\u{d800}']]),
    // 앞부분이 같은 글(짧은 쪽이 앞)
    prefix: group([['ab', 'abc'], ['east-asia', 'east-asia-base'], ['가', '가나'], ['a', 'a '], ['abc', 'abd'], ['a', 'a\0'], ['p-1', 'p-10'], ['p-10', 'p-2'], ['KoreanTimeLine', 'KoreanTimeLine/'], ['a𠀀', 'a𠀀b'], ['𠀀', '𠀀𠀀']]),
    // BMP 사용 영역 · 호환 영역(U+E000 ~ U+FFFF) ↔ 서로게이트 짝(U+10000 넘음): UTF-16 차례는 서로게이트(D800 ~ DFFF)가 E000 ~ FFFF보다 앞이라
    // 코드 포인트(UTF-8) 차례와 거꾸로다. 외톨이 서로게이트(D800 ~ DFFF 하나만 있는 글)는 짓기 꼴 `$s16` 행이 된다 — 모두 이스케이프로 적는다.
    astral: group([['\u{e000}', '\u{10000}'], ['\u{ffff}', '\u{10000}'], ['\u{f8ff}', '\u{1f600}'], ['\u{fffd}', '\u{20000}'], ['\u{ff5a}', '\u{20000}'], ['\u{e000}', '\u{10ffff}'], ['\u{fb00}', '\u{10000}'],
      ['\u{fffe}', '\u{10000}'], ['\u{d7ff}', '\u{10000}'], ['\u{e000}\u{10000}', '\u{10000}\u{e000}'], ['a\u{e000}', 'a\u{10000}'], ['\u{10000}', '\u{10001}'], ['\u{1f600}', '\u{1f601}'],
      ['\u{10000}', '\u{d800}'], ['\u{d800}', '\u{dc00}'], ['\u{dc00}', '\u{e000}'], ['\u{dbff}\u{dfff}', '\u{e000}'], ['\u{d7ff}', '\u{d800}'], ['\u{10ffff}', '\u{ffff}'], ['가', '\u{10000}'],
      ['\u{d800}\u{d800}', '\u{d800}\u{dc00}'], ['\u{d800}', '\u{d800}\u{d800}'], ['\u{dc00}', '\u{d800}'], ['\u{e000}', '\u{d800}'], ['\u{ffff}', '\u{dc00}']]),
  };
}

// ── hidden: 열거되지 않는 속성(Object.defineProperty — 한 벌 P3 과제 6 고침 1회차: Rust Obj::define_hidden · hidden) ──
// 행: [객체(JSON 글 — 열쇠 차례), 할 일 [['def' | 'set', 열쇠, 값(JSON 값)] · ['del', 열쇠]], 물을 열쇠들, 답 { keys: Object.keys, json: JSON.stringify,
//      assign: JSON.stringify(Object.assign({}, o)), get: 열쇠마다 JSON 글(없으면 'undefined'), has: 열쇠마다 k in o }]
const hiddenCase = (text, ops, ask) => {
  const o = JSON.parse(text);
  for (const [op, k, v] of ops) {
    if (op === 'def') Object.defineProperty(o, k, { value: v, enumerable: false, writable: true, configurable: true });
    else if (op === 'set') o[k] = v;
    else if (op === 'del') delete o[k];
  }
  const show = x => (x === undefined ? 'undefined' : JSON.stringify(x));
  return [text, ops, ask, { keys: Object.keys(o), json: JSON.stringify(o), assign: JSON.stringify(Object.assign({}, o)), get: ask.map(k => show(o[k])), has: ask.map(k => k in o) }];
};
V.hidden = [
  hiddenCase('{"a":1,"north":2}', [['def', 'north', 3]], ['north', 'a']),
  hiddenCase('{"a":1}', [['def', 'north', 3], ['set', 'north', 4]], ['north', 'a']),
  hiddenCase('{"a":1}', [['def', 'x', 1], ['del', 'x']], ['x']),
  hiddenCase('{"a":1,"b":2}', [['def', 'b', 9], ['set', 'c', 3], ['set', 'b', 10]], ['b', 'c']),
  hiddenCase('{"0":1}', [['def', '1', 2], ['set', '1', 5]], ['1', '0']),
  hiddenCase('{"cellBounds":{"k":1},"z":0}', [['def', 'cellBounds', { lo: 1 }], ['def', 'cellBounds', { lo: 2 }]], ['cellBounds', 'z']),
  hiddenCase('{"a":1}', [['def', 'h', 1], ['del', 'h'], ['set', 'h', 2]], ['h']),
];

// ── entities: 모듈 entities(갈래 D — 한 벌 P3 과제 13)의 정답지가 다 지나지 않는 셈 ──
// groupDigits: [입력(짓기 꼴), HT.groupDigits(입력)] — 과제 4 보고 §4의 표 + 씨앗 고정 무작위(정수 · 소수 셋째 자리 경계 · 넷째 자리 · 큰 수 · 작은 수). 정답지는 1000 미만만 지난다.
// toFixed1: [x, x.toFixed(1)] — 의석 막대의 득표율 글(entities.mjs 1165 · 1184줄).
// kin: [기록 JSON(recordOf), 상한, splitKin 덩어리들(JSON 글), joinKin(덩어리들)(JSON 글)] — 마디 5만을 넘는 뼈대가 정답지에 없어 작은 상한으로 나누기 · 합치기를 지킨다.
// kinCollect: 견본 등불 연대기 모델을 정답지와 같은 '오늘'(2026-10-15 · 서울 — HT.CURRENT_YEAR · HT.NOW_T를 그 값으로 두고 지음)로 짓고 kinCollect(model, HT, { limit })를
//   상한 8 · 5 · 20으로 — 덩어리 길 전체(chunkUid · homeOf · chunkAt · personAt.chunk · houseKin.chunk · extraFar · root)를 Node와 견준다(갈래 D 검토 1 · 2 · 판정 R27). 행(둘째 칸이 상한):
//   ['record', 상한, uid, rootUid, houseId|null, polityUid|null, 본문 JSON 글] · ['person', 상한, 사람 열쇠, 뼈대 열쇠, 번호, member, chunk|null] · ['cell', 상한, 칸 열쇠, 뼈대 열쇠, 번호] ·
//   ['house', 상한, 가문 id, x_kin JSON 글] · ['chunkAt', 상한, 뼈대 열쇠, 한 벌 번호, chunk|null](뿌리 기록마다 0 ~ n−1) · ['notes', 상한, 집계 JSON 글]
{
  const HT = globalThis.HT && globalThis.HT.groupDigits ? globalThis.HT : bootWeb();
  const { recordOf, splitKin, joinKin } = await import('./export/kin.mjs');
  const r = rng(13013);
  const gd = [0, -0, 7, 999, 1000, 12345, 1234567, -1234567, 1e9, 123456789012, 0.5, 1.5, 1234.5678, 0.0005, 0.0004, -0.0005, 1.0005, 1.005, 0.9996, 999999.9996, -0.0001,
    0.1 + 0.2, 1 / 3, 1e21, 1.5e21, 1e-7, 2 ** 53, -(2 ** 53), 1.7976931348623157e308, 5e-324, NaN, Infinity, -Infinity, '12345', '', null, undefined, true, '1,234', 999.9995, 99.9996, 0.00049, 0.00051];
  for (let i = 0; i < 120; i++) gd.push(Math.floor(r() * 10 ** Math.floor(r() * 13)) * (r() < 0.2 ? -1 : 1));
  for (let i = 0; i < 120; i++) gd.push(Math.round(r() * 1e7) / 10 ** (1 + Math.floor(r() * 6)));
  for (let i = 0; i < 40; i++) gd.push((Math.floor(r() * 1e6) + 0.0005) * (r() < 0.5 ? 1 : 1e-3));
  for (let i = 0; i < 20; i++) gd.push(r() * 10 ** (Math.floor(r() * 600) - 300));
  const tf = [0, -0, 0.05, 0.15, 0.25, 0.35, 0.45, 1.25, 2.675, 33.33333, 66.66667, 99.95, 99.94999, 100, 12.345, 1e-7, -0.04, -1.25, 50, 1 / 3 * 100, 2 / 3 * 100];
  for (let i = 0; i < 200; i++) tf.push(Math.round(r() * 1e9) / 1e7);
  for (let i = 0; i < 60; i++) { const v = r() * 3000, t = Math.floor(r() * 3000) + 1; tf.push((100 * Math.floor(v)) / t); }
  /* 앞 차례 숲(부모가 늘 앞) — 열 꼴 뼈대 */
  const skelOf = (n, seed) => {
    const q = rng(seed);
    const par = [], gen = [], bits = [], edge = [], branch = [], color = [], color2 = [], name = [], sub = [], key = [];
    let path = [];
    for (let i = 0; i < n; i++) {
      let p = -1;
      if (i > 0 && q() > 0.04) { const d = Math.floor(q() * path.length); p = path[d]; path = path.slice(0, d + 1); } else path = [];
      path.push(i);
      par.push(p);
      gen.push(p < 0 ? 0 : gen[p] + 1);
      bits.push((q() < 0.8 ? 1 : 0) | (q() < 0.12 ? 16 : 0) | (q() < 0.2 ? 32 : 0) | (q() < 0.05 ? 2 : 0));
      edge.push(Math.floor(q() * 3));
      branch.push(Math.floor(q() * 3) - 1);
      color.push(Math.floor(q() * 3));
      color2.push(q() < 0.1 ? 1 + Math.floor(q() * 2) : 0);
      name.push(`사람${i}`);
      sub.push(q() < 0.5 ? `${i}대 · 1${i}~1${i + 9}` : '');
      key.push(q() < 0.1 ? `u:${i}` : `f:p/${i}`);
    }
    const size = new Array(n).fill(1);
    for (let i = n - 1; i > 0; i--) if (par[i] >= 0) size[par[i]] += size[i];
    const extra = [];
    for (let k = 0; k < Math.floor(n / 4); k++) { const a = Math.floor(q() * n), b = Math.floor(q() * n); if (a !== b) extra.push(Math.min(a, b), Math.max(a, b), Math.floor(q() * 7), 1 + Math.floor(q() * 3)); }
    const branches = [{ uid: 'house:root', name: '본가', color: '#a0bcc5', at: 0, up: -1 }];
    for (let i = 1; i < n; i++) if (bits[i] & 16 && branches.length < 6) branches.push({ uid: `house:b${i}`, name: `분가${i}`, color: '#d1a9b9', at: i, up: 0 });
    const cells = {};
    for (let i = 0; i < n; i++) if (bits[i] & 32) cells[`p/x${i % 5}|leader:${i}`] = i;
    return { v: 1, uid: 'kin:root', n, par, size, gen, bits, edge, branch, color, color2, name, sub, key, extra, colors: ['', '#a0bcc5', '#d1a9b9'], branches, cells, stubs: {}, warnings: ['처음 경고'] };
  };
  const kin = [];
  for (const [n, limit, seed] of [[12, 50, 1], [30, 8, 2], [40, 12, 3], [60, 10, 4], [25, 4, 5], [80, 20, 6], [18, 1, 7], [50, 49, 8]]) {
    const rec = recordOf(skelOf(n, seed), 'kin:root');
    const parts = splitKin(rec, limit);
    kin.push([JSON.stringify(rec), limit, parts.map(x => JSON.stringify(x)), JSON.stringify(joinKin(parts))]);
  }
  const { kinCollect } = await import('./export/kin.mjs');
  const keepNow = [HT.CURRENT_YEAR, HT.NOW_T];
  const kc = [];
  try {
    HT.CURRENT_YEAR = 2026;
    HT.NOW_T = HT.cal.tOf(HT.cal.jdnCivil(2026, 10, 15));
    const raw = JSON.parse(fs.readFileSync(path.resolve(here, '..', '..', 'samples', 'sample-lantern.json'), 'utf8'));
    const model = HT.buildModel([HT.normalizePack(raw).pack], null, { groupBands: true });
    for (const limit of [8, 5, 20]) {
      const k = kinCollect(model, HT, { limit });
      for (const r of k.records) kc.push(['record', limit, r.uid, r.rootUid, r.houseId ?? null, r.polityUid ?? null, JSON.stringify(r.body)]);
      for (const [key, a] of k.personAt) kc.push(['person', limit, key, a.key, a.at, a.member, a.chunk ?? null]);
      for (const [cell, a] of k.cellAt) kc.push(['cell', limit, cell, a[0], a[1]]);
      for (const [id, o] of k.houseKin) kc.push(['house', limit, id, JSON.stringify(o)]);
      for (const r of k.records) if (r.uid === r.rootUid) for (let i = 0; i < HT.kinSkeleton(model, r.rootUid).n; i++) kc.push(['chunkAt', limit, r.rootUid, i, k.chunkAt(r.rootUid, i).chunk ?? null]);
      kc.push(['notes', limit, JSON.stringify(k.notes)]);
    }
  } finally {
    [HT.CURRENT_YEAR, HT.NOW_T] = keepNow;
  }
  V.entities = { groupDigits: gd.map(x => [enc(x), HT.groupDigits(x)]), toFixed1: tf.map(x => [enc(x), x.toFixed(1)]), kin, kinCollect: kc };
}

// ── 쓰기: 갈래마다 한 줄에 한 행 ──
const head = {
  도구: 'node prototype/scripts/js-vectors.mjs', 시간대: TZ, ICU: process.versions.icu || '',
  뜻: 'Node가 낸 JS 값의 뜻 — Rust lay::js가 같은 답을 내야 한다(tests/lay_js.rs). 값을 적는 꼴은 도구 머리말의 짓기 꼴.',
};
const rows = (list, indent = '  ') => `[\n${list.map(x => indent + JSON.stringify(x)).join(',\n')}\n${indent.slice(2)}]`;
const parts = [`"$vectors":${JSON.stringify(head)}`];
for (const [k, v] of Object.entries(V)) {
  if (Array.isArray(v)) parts.push(`${JSON.stringify(k)}:${rows(v)}`);
  else parts.push(`${JSON.stringify(k)}:{\n${Object.entries(v).map(([kk, vv]) => `  ${JSON.stringify(kk)}:${rows(vv, '    ')}`).join(',\n')}\n}`);
}
fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, `{\n${parts.join(',\n')}\n}\n`);
const count = Object.fromEntries(Object.entries(V).map(([k, v]) => [k, Array.isArray(v) ? v.length : Object.values(v).reduce((n, l) => n + l.length, 0)]));
console.log(`js-vectors: ${path.relative(process.cwd(), outFile)} — ${Object.entries(count).map(([k, n]) => `${k} ${n}`).join(' · ')}`);

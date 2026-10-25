// 날짜 글 검사의 기준값: 지금 연표의 js/calendar.js를 노드에서 그대로 돌려 기준값을 뜬다. js는 읽기만 한다.
// 쓰는 법: node prototype/scripts/dates-reference.mjs > <내보낼 곳>.json
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const prototypeDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(prototypeDir, '..');

const noop = () => {};
globalThis.window = globalThis;
globalThis.document = { documentElement: {}, body: {}, addEventListener: noop };
vm.runInThisContext(fs.readFileSync(path.join(root, 'js', 'calendar.js'), 'utf8'), { filename: 'js/calendar.js' });
const HT = globalThis.HT;
const cal = HT.cal;

/** 내보내기(scripts/export/base.mjs)의 해 좌표 → 분 투영 그대로. */
function minute(y) {
  if (!Number.isFinite(y)) return null;
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}
/** 지금의 search_parse.dart가 쓰는 투영(프롤렙틱 그레고리력 곧바로). */
function minuteGreg(astroYear, m = 1, d = 1, h = 0, mi = 0) {
  const t = new Date(0);
  t.setUTCFullYear(astroYear, m - 1, d); t.setUTCHours(h, mi, 0, 0);
  return Math.round(t.getTime() / 60000);
}

const out = { cases: [], lunar: [], julian: [], random: [], ganji: [] };

/** 날짜 글 하나를 지금 연표로 읽은 값. */
function read(text) {
  const r = cal.parse(text);
  if (!r || !r.ok) return { text, ok: false, error: r ? r.error : '없음' };
  return {
    text, ok: true, cal: r.cal, prec: r.prec, y: r.y, m: r.m ?? null, leap: !!r.leap, d: r.d ?? null,
    h: r.h ?? null, mi: r.mi ?? null, J: r.J ?? null, t: r.t, std: r.text,
    describe: cal.describe(r), formatT: cal.formatT(r.t, r.prec === 'min' ? 'min' : r.prec),
    minute: minute(r.t),
  };
}

// ── ① 음력 · 중국 음력 · 이슬람력 · 페르시아력으로 적은 날짜 글 ────────────────────────────────
for (const text of [
  '음력 1592-04-13', '음력 1592년 4월 13일', '음력 1592년 윤4월 13일', '음 1592.4.13', '한국 음력 1592-04-13',
  '음력:1592-04-13', '1592-04-13 음력', '1592-04-13 (음력)', '기원전 음력 100-01-01', '음력 기원전 100-01-01',
  '중국 음력 1592-04-13', '농력 1592-04-13', '음력 300-12-15', '음력 301-윤05-01', '음력 304-윤03-01',
  '음력 1592-04', '음력 1592', '음력 1592-04-13 14:30', '음력 299-11-23',
  '이슬람력 1000-08-11', '페르시아력 971-03-02', '율리우스력 1000-03-15', '그레고리력 1000-03-15',
  '음력 301-윤06-01', '음력 1592-04-31', '음력 1592-13-01',
]) out.cases.push(read(text));

// ── ② 1582년 앞뒤 · 율리우스력 경계 ──────────────────────────────────────────────────────────
for (const text of [
  '1582-10-04', '1582-10-05', '1582-10-14', '1582-10-15', '1582-10-16', '1583-01-01',
  '1500-02-28', '1500-03-01', '1500-12-31', '1000-01-01', '1000-03-15', '1000-12-31',
  '900-03-01', '300-01-01', '300-01-23', '100-03-01', '기원전 100-03-01', '기원전 1-12-31', '1-01-01',
  '1600-02-29', '1500-02-29', '1700-02-29',
]) out.julian.push(read(text));

// ── ③ 무작위 대조 ────────────────────────────────────────────────────────────────────────────
let seed = 20260922;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
for (let i = 0; i < 400; i++) {
  const y = Math.floor(rnd() * 3400) - 1600;
  const yy = y === 0 ? 1 : y;
  const m = 1 + Math.floor(rnd() * 12);
  const d = 1 + Math.floor(rnd() * 28);
  const text = `${yy < 0 ? `기원전 ${-yy}` : yy}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  const r = read(text);
  if (!r.ok) continue;
  out.random.push({ ...r, minuteGreg: minuteGreg(cal.toAstro(r.y), r.m, r.d) });
}

// ── ④ 음력 되짚기(달의 시작 표와 맞대어 볼 값) ──────────────────────────────────────────────
for (let i = 0; i < 300; i++) {
  const J = 1829518 + Math.floor(rnd() * 3000);
  const p = cal.partsIn('dangi', J);
  out.lunar.push({ J, y: p.y, m: p.m, leap: !!p.leap, d: p.d, t: cal.tOf(J), civil: cal.civilOf(J) });
}

// ── ⑤ 일진 · 요일 ───────────────────────────────────────────────────────────────────────────
for (const J of [1830655, 2299160, 2299161, 2433283, 1829518, 1721424]) {
  out.ganji.push({ J, ganji: cal.dayGanji(J), week: '일월화수목금토'[(((J + 1) % 7) + 7) % 7], civil: cal.civilOf(J) });
}

process.stdout.write(JSON.stringify(out, null, 1));

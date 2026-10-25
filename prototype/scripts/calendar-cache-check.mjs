// 미리 떠 둔 달력 표(export/calendar.mjs '미리 떠 둔 표')의 검사: 넓은 표에서 잘라 낸 표가 바로 뜬 표와 글자까지 같은가 · 덮지 못하는 범위는
// 자르지 않는가 · 내보내기(contribute)가 표 파일을 쓸 때와 안 쓸 때 같은 항목 기록을 싣는가 · 두 번째부터는 다시 뜨지 않는가.
// 사용: node prototype/scripts/calendar-cache-check.mjs   (20초 남짓 — 표 파일은 임시 폴더에만 쓴다)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { bootWeb, loadContext, prototype } from './export/base.mjs';
import { buildTable, sliceTable, warmTables, wantedCalendars, contribute, monthDays } from './export/calendar.mjs';

const HT = bootWeb();
const wanted = wantedCalendars(HT);
assert.ok(wanted.length >= 2, `ICU 달력이 모자랍니다(${wanted.map(c => c.id).join(' · ')})`);
const J = y => HT.cal.jdnCivil(y, 1, 1);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'ht-cal-cache-'));
process.on('exit', () => fs.rmSync(scratch, { recursive: true, force: true }));
let n = 0;

// 1) 잘라 낸 표 = 바로 뜬 표. 넓은 표는 −1000~1500년, 자를 범위는 그 안의 여러 꼴(0년 언저리 · 달의 한가운데 · 달의 첫날 · 하루짜리 · 양 끝에 붙은 것).
const wide = warmTables(HT, wanted, -1000, 1500, '').tables;
for (const c of wanted) {
  const w = wide[c.id];
  const second = w.start + monthDays(w.months.charCodeAt(1)); // 둘째 달의 첫날
  const ranges = [[J(-900), J(1401)], [J(-2), J(2)], [J(-1), J(1)], [J(1), J(2)], [second, second + 1], [second - 1, second + 400], [J(600) + 17, J(600) + 18],
    [w.start, w.end], [w.start, J(-999)], [J(1499), w.end], [w.start + 3, w.end - 3]];
  for (const [from, to] of ranges) {
    const cut = sliceTable(w, c, from, to);
    assert.ok(cut, `${c.id}: 덮는 범위인데 자르지 못했습니다(${from}~${to})`);
    assert.deepEqual(cut, buildTable(HT, c, from, to), `${c.id}: 잘라 낸 표가 바로 뜬 표와 다릅니다(${from}~${to})`);
    n++;
  }
  // 덮지 못하는 범위 — 앞 · 뒤로 하루라도 넘으면 자르지 않는다.
  assert.equal(sliceTable(w, c, w.start - 1, J(0 + 1)), null, `${c.id}: 앞이 모자란데 잘랐습니다`);
  assert.equal(sliceTable(w, c, J(1), w.end + 1), null, `${c.id}: 뒤가 모자란데 잘랐습니다`);
  assert.equal(sliceTable(null, c, J(1), J(2)), null);
  n += 3;
}

// 2) 내보내기: 표 파일 없이(off) · 표 파일로(처음 = 넓혀 뜸 → 둘째 = 잘라 씀) 실은 항목 기록이 같다.
const ctx = await loadContext(); // 등불 연대기 견본
const run = env => {
  process.env.HT_CALENDAR_CACHE = env;
  ctx.notes = {};
  const out = { entities: [] };
  const t0 = Date.now();
  contribute(ctx, out);
  return { entities: out.entities, notes: ctx.notes.calendar, ms: Date.now() - t0 };
};
const file = path.join(scratch, 'calendar-cache.json');
const live = run('off');
const first = run(file);
assert.ok(fs.existsSync(file), '표 파일을 쓰지 않았습니다');
const second = run(file);
assert.deepEqual(first.entities, live.entities, '표 파일로 처음 실은 것이 바로 뜬 것과 다릅니다');
assert.deepEqual(second.entities, live.entities, '표 파일로 두 번째 실은 것이 바로 뜬 것과 다릅니다');
assert.ok(Object.values(second.notes.달력).every(x => x.표 === '잘라 씀'), `두 번째에 다시 떴습니다: ${JSON.stringify(second.notes.달력)}`);
const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
assert.equal(saved.icu, process.versions.icu);
assert.ok(saved.years[0] % 500 === 0 && saved.years[1] % 500 === 0, `넓힌 범위가 500년 단위가 아닙니다: ${saved.years}`);
n += 5;

// 3) ICU 판이 다른 표 파일은 쓰지 않고 다시 뜬다(같은 답).
fs.writeFileSync(file, JSON.stringify({ ...saved, icu: 'other' }));
const stale = run(file);
assert.deepEqual(stale.entities, live.entities);
assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).icu, process.versions.icu, 'ICU 판이 다른 표 파일을 갈지 않았습니다');
n += 2;

// 4) 기본 자리(공용 표 prototype/results/calendar-cache.json)는 갈지 않는다(판정 R64 넘김 · 과제 testinfra): HT_CALENDAR_CACHE 없이 내보내면
//    공용 표의 바이트(또는 없음)가 그대로이고, 공용 표가 없거나 모자라면 TMP의 사본(ht-calendar-cache-<ICU>.json)에 뜬다 — 같은 답.
{
  const shared = path.join(prototype, 'results', 'calendar-cache.json');
  const stamp = () => (fs.existsSync(shared) ? fs.readFileSync(shared).toString('base64') : null);
  const before = stamp();
  const keep = { HT_CALENDAR_CACHE: process.env.HT_CALENDAR_CACHE, TMP: process.env.TMP, TEMP: process.env.TEMP, TMPDIR: process.env.TMPDIR };
  delete process.env.HT_CALENDAR_CACHE;
  Object.assign(process.env, { TMP: scratch, TEMP: scratch, TMPDIR: scratch });
  let viaShared;
  try {
    ctx.notes = {};
    const out = { entities: [] };
    contribute(ctx, out);
    viaShared = out.entities;
  } finally {
    for (const [k, v] of Object.entries(keep)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  }
  assert.ok(stamp() === before, `공용 달력 표(${shared})를 갈았습니다`);
  assert.deepEqual(viaShared, live.entities, '공용 표 자리로 실은 것이 바로 뜬 것과 다릅니다');
  const side = path.join(scratch, `ht-calendar-cache-${process.versions.icu || 'none'}.json`);
  if (before === null) assert.ok(fs.existsSync(side), `공용 표가 없는데 사본(${side})에 뜨지 않았습니다`);
  n += 2;
}

console.log(`달력 표 검사 ${n}건 통과 — 바로 뜸 ${live.ms}ms · 처음(넓혀 뜸) ${first.ms}ms · 두 번째(잘라 씀) ${second.ms}ms`);

// 견본 등불 연대기(samples/sample-lantern.json)를 지금 연표의 정규화기와 줄 배치기(_layoutTrack)에 그대로 통과시켜, 그 결과(트랙 · 줄 · 띠 · 칸 · 사건)를
// 새 저장소가 가져올 JSON으로 내보낸다. "줄 배치는 넣을 때 한 번"의 시연이다. 웹 코드는 읽기만 하고, 화면(DOM)은 만들지 않는다.
// 사용(옛 2판 시연 — 지금 도구는 export-layout.mjs): node prototype/scripts/export/_v2-원본.mjs   → prototype/results/compat/lantern-layout.json · sample-lantern.htpack
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..'); // export/ 아래로 옮겨 온 뒤의 자리
const root = path.resolve(prototype, '..');
const output = path.join(prototype, 'results', 'compat');
fs.mkdirSync(output, { recursive: true });

// 배치 계산은 자료만 쓰지만, timeline.js는 불러올 때 글자 폭 재는 캔버스를 하나 만든다 — 그만큼만 흉내 낸다.
const noop = () => {};
const el = () => ({
  style: {}, dataset: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false },
  appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop, querySelector: () => null, querySelectorAll: () => [],
  getContext: () => ({ measureText: text => ({ width: String(text).length * 7 }), font: '' }),
});
globalThis.window = globalThis;
globalThis.document = { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop };
globalThis.localStorage = { getItem: () => null, setItem: noop, removeItem: noop };
globalThis.matchMedia = () => ({ matches: false, addEventListener: noop });
globalThis.getComputedStyle = () => ({ getPropertyValue: () => '' });
globalThis.requestAnimationFrame = noop;
globalThis.cancelAnimationFrame = noop;
for (const file of ['js/calendar.js', 'js/core.js', 'js/packfile.js', 'js/timeline.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(root, file), 'utf8'), { filename: file });
}
const HT = globalThis.HT;
assert.equal(typeof HT.Timeline, 'function', 'HT.Timeline을 불러오지 못했습니다');

const raw = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const model = HT.buildModel([HT.normalizePack(raw).pack], null);

// 생성자를 건너뛰고(진짜 화면 요소를 요구한다) 배치가 읽는 상태만 기본값으로 채운다 — js/timeline.js의 constructor와 같은 값.
const tl = Object.create(HT.Timeline.prototype);
Object.assign(tl, {
  show: { leaders: true, cabinets: true, eras: true, capitals: true, ganji: true, succession: true, partOf: true, epochs: true },
  folded: new Set(), foldedPeoples: new Set(), foldedEras: new Set(), expandedHosts: new Set(), scopesOn: {},
  density: 0, _bird: null, _lod: new Map(), gutter: 196, depth: 1, hiLayout: null, highlight: null, selected: null,
});
// setData의 준비 구간(트랙별로 띠와 사건을 나누고 왕조 · 속국 이름표를 정리)을 그대로 따른다.
tl._data = { tracks: model.tracks, periods: model.periods, events: model.events, epochs: model.epochs, categories: model.categories, scopes: model.scopes, figures: [] };
tl._setScopes(model.scopes);
tl._cats = new Map();
(model.categories && model.categories.length ? model.categories : HT.DEFAULT_CATEGORIES).forEach((c, i) => tl._cats.set(c.id, { name: c.name, color: c.color, i }));
for (const e of model.events) {
  const id = e.category || 'etc';
  if (!tl._cats.has(id)) tl._cats.set(id, { name: id, color: e.color || '#a4b1b7', i: 1000 + tl._cats.size });
}
tl.epochs = model.epochs || [];
const byId = new Map();
tl.tracks = model.tracks.map(t => {
  const tr = Object.assign({}, t, { periods: [], events: [], figures: [] });
  byId.set(t.id, tr);
  return tr;
});
tl._cityUses = new Map();
tl._dynUids = new Set();
for (const p of model.periods) {
  if (p.polityKind === 'dynasty') tl._dynUids.add(p.uid);
  else if (byId.has(p.track)) byId.get(p.track).periods.push(p);
}
tl._proxies = HT.Timeline.depProxies(model.periods);
for (const e of model.events) {
  const places = e.placements && e.placements.length ? e.placements : [{ track: e.track, polityUid: e.polityUid }];
  places.forEach((place, i) => {
    const tr = byId.get(place.track);
    if (tr) tr.events.push(Object.assign({}, e, { _place: place, _sec: i > 0, _pi: i }));
  });
}
for (const tr of tl.tracks) tl._layoutTrack(tr);

// 해(실수) → 정수 분. compat-check.mjs와 같은 투영(그 해의 양 끝 날짜 사이를 비례로).
function minute(y) {
  if (!Number.isFinite(y)) return null;
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}
const color = (text, fallback = 0xa4b1b7) => (/^#[0-9a-f]{6}$/i.test(text || '') ? parseInt(text.slice(1), 16) : fallback);
const STRIP = { dynasty: 0, leader: 1, cabinet: 2, organ: 3 };

const out = { name: raw.name, tracks: [], epochs: [], periods: [], cells: [], events: [] };
const skipped = { hidden: 0, overlayWithoutHost: 0, under: 0, noRow: 0 };
for (const e of model.epochs || []) {
  const start = minute(e.start), end = minute(e.endY ?? e.end ?? e.start);
  if (start != null && end != null && end >= start) out.epochs.push({ start, end, color: color(e.color, 0xc8b193), name: e.name || '' });
}
tl.tracks.forEach((tr, trackIndex) => {
  // 줄의 자리: 띠 위의 틈(책갈피 탭 자리 · 민족 사이 틈)을 그 줄의 몫으로 넣고, 트랙 위아래 여백은 첫 줄 · 끝 줄에 넣는다.
  const rows = [];
  for (let r = 0; r < tr.rows; r++) {
    const geo = tr.geos[r] || tr.geo;
    const slotTop = r === 0 ? 0 : tr.rowTop[r] - tr.rowGap[r];
    const slotEnd = r === tr.rows - 1 ? tr.height : tr.rowTop[r + 1] - tr.rowGap[r + 1];
    const bandTop = Math.round(tr.rowTop[r] - slotTop);
    const at = (top, h) => (h > 0 ? Math.round(bandTop + top) : -1);
    rows.push({
      height: Math.round(slotEnd - slotTop), bandTop, bandH: Math.round(geo.rowH),
      dynTop: at(geo.dynastyTop, geo.dynastyH), leadTop: at(geo.leaderTop, geo.leaderH), cabTop: at(geo.cabinetTop, geo.cabinetH),
      textTop: Math.round(bandTop + geo.textTop), lines: geo.lines, railTop: Math.round(bandTop + geo.railTop), organTop: at(geo.organTop, geo.organH),
    });
  }
  out.tracks.push({ name: tr.name || tr.id, rows });
  const inTrack = new Map(tr.periods.map(p => [p.uid, p]));
  const bandOf = new Map(); // uid → out.periods의 번호
  for (const p of tr.periods) {
    if (p._overlay) continue;
    if (p._hidden) { skipped.hidden++; continue; }
    if (p._row == null || p._row < 0 || p._row >= tr.rows) { skipped[p._underRows ? 'under' : 'noRow']++; continue; }
    const start = minute(p.start), end = minute(p.endY);
    assert.ok(start != null && end != null && start <= end, `띠의 기간 오류: ${p.name}`);
    bandOf.set(p.uid, out.periods.length);
    out.periods.push({ uid: p.uid, track: trackIndex, row: p._row, start, end, fuzzy: (p.startUnknown ? 1 : 0) | (p.endUnknown ? 2 : 0), color: color(p.color), name: p.name || '' });
    const cell = (kind, c, name) => {
      const s = minute(c.start ?? p.start), e = minute(c.endY ?? c.end ?? p.endY);
      if (s == null || e == null || !name) return;
      out.cells.push({ period: p.uid, kind, start: Math.max(s, start), end: Math.max(Math.max(s, start), Math.min(e, end)), name });
    };
    for (const d of p.dynasties || []) cell(STRIP.dynasty, d, (d.dynasty && d.dynasty.name) || d.name || (typeof d.dynasty === 'string' ? d.dynasty : ''));
    for (const c of p.leaders || []) cell(STRIP.leader, c, c.name || c.temple || c.title || c.given);
    for (const c of p.cabinets || []) cell(STRIP.cabinet, c, c.name);
  }
  // 기관(얹히는 조직)은 제 줄 없이 주인 띠의 기관 단에 칸으로 들어간다.
  // 지금 연표는 같은 때에 겹치는 기관을 여러 단(_zoneLane)에 나눠 놓지만 2단계의 기관 단은 하나라서,
  // 먼저 시작한 기관을 두고 그것과 겹치는 기관은 싣지 않는다(겹침 금지). 뺀 수를 남긴다.
  const organEnd = new Map(); // 주인 띠 uid → 마지막으로 실은 기관의 끝
  for (const p of tr.periods.filter(p => p._overlay).sort((a, b) => a.start - b.start || a.endY - b.endY)) {
    const host = (p.hosts || []).map(h => h.host).find(h => h && bandOf.has(h.uid));
    if (!host) { skipped.overlayWithoutHost++; continue; }
    const band = out.periods[bandOf.get(host.uid)];
    const s = Math.max(minute(p.start), band.start), e = Math.min(minute(p.endY), band.end);
    if (e < s || out.tracks[trackIndex].rows[band.row].organTop < 0) continue;
    if (organEnd.has(host.uid) && s <= organEnd.get(host.uid)) { skipped.overlayOverlap = (skipped.overlayOverlap || 0) + 1; continue; }
    organEnd.set(host.uid, e);
    out.cells.push({ period: host.uid, kind: STRIP.organ, start: s, end: e, name: p.name || '' });
  }
  for (const e of tr.events) {
    const row = e._row == null || e._row < 0 ? tr.commonRow : e._row;
    assert.ok(row >= 0 && row < tr.rows, `사건의 줄이 없습니다: ${e.title}`);
    const start = minute(e.start), end = minute(e.endY ?? e.start);
    out.events.push({
      uid: e.uid + (e._pi ? `#${e._pi}` : ''), track: trackIndex, row, start, end: start == null ? null : Math.max(end ?? start, start),
      importance: Math.min(3, Math.max(1, e.importance || 1)), title: e.title ?? e.name ?? '', body: e.description ?? '',
    });
  }
  void inTrack;
});

// 자체 점검
const periodsByRow = new Map();
for (const p of out.periods) {
  assert.ok(p.row < out.tracks[p.track].rows.length);
  const key = `${p.track}/${p.row}`;
  if (!periodsByRow.has(key)) periodsByRow.set(key, []);
  periodsByRow.get(key).push(p);
}
// 지금 연표는 승계국이 있는 바탕 문화를 승계국 띠 밑에 겹쳐 깐다. 2단계의 새 그림에는 그 겹쳐 깔림이 없으므로(3단계 몫)
// 같은 줄에서 겹치는 앞 띠의 끝을 뒤 띠의 시작 앞에서 끊고, 끊은 수와 보기를 남긴다.
const overlaps = [];
const bandByUid = new Map(out.periods.map(p => [p.uid, p]));
for (const [key, list] of periodsByRow) {
  list.sort((a, b) => a.start - b.start || a.end - b.end);
  for (let i = 1; i < list.length; i++) {
    const before = list[i - 1], after = list[i];
    if (after.start > before.end) continue;
    // 끝과 시작이 같은 분인 승계는 겹침이 아니다 — 양 끝 포함 규칙에 맞게 1분만 물린다.
    if (after.start < before.end) overlaps.push(`${key}: ${before.name} ↔ ${after.name}`);
    before.end = Math.max(before.start, after.start - 1);
    before.fuzzy &= ~2;
  }
}
out.cells = out.cells.filter(c => c.start <= bandByUid.get(c.period).end);
for (const c of out.cells) c.end = Math.min(c.end, bandByUid.get(c.period).end);
// 같은 띠 · 같은 단의 칸끼리는 겹치지 않게: 먼저 시작한 칸을 두고, 1분만 물린 이음매는 끝을 당기고, 정말 겹치는 칸은 뺀다.
const stripEnd = new Map();
const keptCells = [];
for (const c of [...out.cells].sort((a, b) => (a.period < b.period ? -1 : a.period > b.period ? 1 : 0) || a.kind - b.kind || a.start - b.start || a.end - b.end)) {
  const key = `${c.period}/${c.kind}`, last = stripEnd.get(key);
  if (last && c.start <= last.end) {
    if (c.start === last.end && last.end > last.start) last.end = c.start - 1;
    else { skipped.cellOverlap = (skipped.cellOverlap || 0) + 1; continue; }
  }
  stripEnd.set(key, c);
  keptCells.push(c);
}
out.cells = keptCells;
for (const c of out.cells) {
  const band = bandByUid.get(c.period);
  assert.ok(band && c.start >= band.start && c.end <= band.end && c.start <= c.end, `칸이 띠 밖입니다: ${c.name}`);
}
assert.equal(out.events.filter(e => !e.uid.includes('#')).length, model.events.length, '사건 수가 모델과 다릅니다');

// 원본 전용 팩도 함께 만들어 둔다(가져오기가 원본을 그대로 보존한다).
const pack = path.join(output, 'sample-lantern.htpack');
if (!fs.existsSync(pack)) fs.writeFileSync(pack, await HT.packFile.build(raw));
fs.writeFileSync(path.join(output, 'lantern-layout.json'), JSON.stringify(out) + '\n');
const kinds = [0, 1, 2, 3].map(k => out.cells.filter(c => c.kind === k).length);
console.log(JSON.stringify({
  트랙: out.tracks.length, 줄: out.tracks.reduce((n, t) => n + t.rows.length, 0), 띠: out.periods.length,
  칸: { 왕조: kinds[0], 지도자: kinds[1], 내각: kinds[2], 기관: kinds[3] }, 시대구분: out.epochs.length,
  사건: out.events.length, 모델사건: model.events.length, 날짜미정: out.events.filter(e => e.start == null).length,
  뺀것: skipped, 같은줄겹침: overlaps.length, 겹침보기: overlaps.slice(0, 3),
  트랙높이: out.tracks.map(t => t.rows.reduce((n, r) => n + r.height, 0)),
}, null, 1));

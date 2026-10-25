// 내보내기의 바탕: 지금 연표의 정규화기와 줄 배치기(_layoutTrack)를 화면(DOM) 없이 노드에서 그대로 돌려, 모듈들이 읽을 문맥을 만든다.
// 웹 코드는 읽기만 한다. 모듈은 `export function contribute(ctx, out)` 하나를 내보내고, 제 몫의 값만 out에 더한다(계약: docs/계약-아카이브-3단계.md 4절).
//
// 브라우저 겸용 갈래(2026-10-12 ~ 10-22 · 메이커의 줄 배치 내보내기가 웹 일꾼(Web Worker)에서 이 파일과 모듈들을 그대로 불렀다 — 그 단추는 걷었고
// 연표 앱이 .htpack을 바로 받으므로, 지금 브라우저에서 이 파일을 부르는 곳은 없다. 아래의 '브라우저' · '일꾼'은 그 옛 길을 뜻한다.
// 이 파일은 정답지(P3 Rust 배치)를 뽑는 노드 도구가 쓰므로 노드 출력이 바이트 하나도 바뀌면 안 되어, 쓰이지 않는 갈래를 지우지 않고 그대로 둔다):
//   · 노드 전용 부분(파일 읽기 · vm · 경로 · 노드의 assert)은 **이 파일에만** 둔다. 모듈은 노드 내장을 직접 부르지 않고 여기의 `assert` ·
//     `runScript` · `node`를 쓴다. 노드에서는 예전과 같은 것(node:assert/strict · vm.runInThisContext)이라 결과가 1바이트도 달라지지 않는다.
//   · 브라우저(일꾼)에는 화면이 없으므로 노드와 **같은 흉내**(stubElement · installStubs — 글자 폭 = 글자 수 × 7)를 깔고 같은 웹 코드를 싣는다.
//   · 문맥 만들기(contextOf) · 모듈 돌리기(runModules)도 여기 하나 — 노드 도구(export-layout.mjs 같은 것)들이 함께 쓴다.
const NODE = typeof process === 'object' && process !== null && !!(process.versions && process.versions.node);
/** 노드 전용 도구 묶음 — 브라우저(메이커의 일꾼)에서는 null. 노드 내장은 이 파일 밖에서 부르지 않는다. */
export const node = NODE
  ? { fs: (await import('node:fs')).default, path: (await import('node:path')).default, vm: (await import('node:vm')).default, url: await import('node:url') }
  : null;
const { fs, path, vm } = node || {};

/** 노드에서는 node:assert/strict 그대로. 브라우저에서는 모듈들이 쓰는 둘(ok · equal — 엄격한 같음)만 같은 뜻으로. */
export const assert = NODE
  ? (await import('node:assert/strict')).default
  : {
      ok(value, message) {
        if (!value) throw Object.assign(new Error(message || '점검에 걸렸습니다'), { name: 'AssertionError' });
      },
      equal(actual, expected, message) {
        if (!Object.is(actual, expected)) throw Object.assign(new Error(message || `${actual} !== ${expected}`), { name: 'AssertionError' });
      },
    };

/** 노드: 폴더 경로 · 브라우저: 그 폴더의 주소(끝에 '/'). */
export const prototype = NODE ? path.resolve(path.dirname(node.url.fileURLToPath(import.meta.url)), '..', '..') : new URL('../../', import.meta.url).href;
export const root = NODE ? path.resolve(prototype, '..') : new URL('../../../', import.meta.url).href;

/** 웹의 고전 스크립트(js/… · packs/…)를 전역에서 한 번 돌린다 — 노드는 vm.runInThisContext, 브라우저 일꾼은 importScripts(같은 전역 스크립트 뜻). */
export function runScript(rel) {
  if (NODE) vm.runInThisContext(fs.readFileSync(path.join(root, rel), 'utf8'), { filename: rel });
  else globalThis.importScripts(new URL(rel, root).href);
}

/** export/ 아래의 모듈 하나를 부른다(노드 · 브라우저 같은 주소 셈). */
export const importModule = name => import(new URL(`./${name}.mjs`, import.meta.url).href);

/** 차례대로 부를 모듈(있는 것만 — 노드 도구는 파일이 있는지 보고, 일꾼은 모두 있다고 본다). 늦은 차례(contributeLate)도 같은 차례. */
export const MODULES = ['tracks', 'axis', 'bands', 'strips', 'events', 'hangs', 'figures', 'persons', 'rails', 'links', 'scopes', 'labels', 'minibars', 'docs', 'calendar', 'entities', 'power', 'variants', 'boards', 'metro', 'lens'];
// 'persons'(사람 띠 — 리메이크 3단계 · 계약 1-1 초안)는 out.sphereLines만 쓰므로 어느 자리여도 옛 출력이 그대로다 — 사람 모듈(figures) 뒤에 둔다.
// 'lens'(렌즈 — D5 결정 5 A · 6 B의 새 앱 몫)는 맨 끝: 앞선 모듈이 실은 칸 · 일반 항목 · 변형 뒤에 덧붙이기만 하므로 옛 출력의 자리가 그대로다.
// 'power'(집권 단 · 실권 단 · 명목 지도자 · 연합의 겹 탭 — D5 결정 1 ~ 3 + 덧판의 새 앱 몫)는 'variants' 앞: 소속을 펼친 · 대범위를 켠 배치에서만 그려지는 띠의
// 단체 칸도 변형 판으로 실려야 해서(variants.mjs의 REPLAY에 든다) 기본 판이 먼저 있어야 한다. 단체 자료가 없으면 아무것도 싣지 않으므로 옛 출력은 바이트까지 그대로다.

/** 해(실수) → 정수 분. 그 해의 양 끝 날짜 사이를 비례로(2단계의 compat-check.mjs · export-layout.mjs와 같은 투영). */
export function minute(y) {
  if (!Number.isFinite(y)) return null;
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}
export const color = (text, fallback = 0xa4b1b7) => (/^#[0-9a-f]{6}$/i.test(text || '') ? parseInt(text.slice(1), 16) : fallback);

const noop = () => {};
/** 화면 요소 흉내 — 배치 셈이 닿는 만큼만. 글자 폭은 글자 수 × 7(노드 · 일꾼이 같은 값이라 줄 배치가 같다). */
export const stubElement = () => ({
  style: { setProperty: noop }, dataset: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false },
  appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop, querySelector: () => null, querySelectorAll: () => [],
  getContext: () => ({ measureText: text => ({ width: String(text).length * 7 }), font: '' }), innerHTML: '',
});

/** 배치 계산은 자료만 쓰지만, timeline.js는 불러올 때 글자 폭 재는 캔버스를 하나 만든다 — 그만큼만 흉내 낸다(노드 · 메이커의 일꾼 공용). */
export function installStubs() {
  const el = stubElement;
  globalThis.window = globalThis;
  globalThis.document = { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop };
  globalThis.localStorage = { getItem: () => null, setItem: noop, removeItem: noop };
  globalThis.matchMedia = () => ({ matches: false, addEventListener: noop });
  globalThis.getComputedStyle = () => ({ getPropertyValue: () => '' });
  globalThis.requestAnimationFrame = noop;
  globalThis.cancelAnimationFrame = noop;
}

/** 흉내를 깔고 웹 코드(달력 · 핵심 · 팩 파일 · 연표)를 싣는다 — 돌려주는 값: HT. 노드 · 일꾼 공용. */
export function bootWeb() {
  installStubs();
  for (const file of ['js/calendar.js', 'js/core.js', 'js/packfile.js', 'js/timeline.js']) runScript(file);
  const HT = globalThis.HT;
  assert.equal(typeof HT.Timeline, 'function', 'HT.Timeline을 불러오지 못했습니다');
  // 옮겨 앉기의 토막 내기(리메이크 2부 · core.js splitMoves): 형식 4의 기간 있는 시대 그릇 듦을 토막으로 — 새 앱으로 내보낼 때만(웹 · 메이커는 예전처럼 소속).
  HT.F4.split = true;
  return HT;
}

/** 환경 변수 HT_EXPORT_SAMPLE=<samples 아래 이름>(예: sample-lantern — '.json'은 붙여도 되고 빼도 된다)이 가리키는 견본 파일. 없으면 등불 연대기(유일한 견본). (노드 전용) */
export function sampleFile() {
  const name = (process.env.HT_EXPORT_SAMPLE || '').trim().replace(/\.json$/i, '');
  if (!name) return path.join(root, 'samples', 'sample-lantern.json');
  assert.ok(/^[\w.-]+$/.test(name), `HT_EXPORT_SAMPLE은 samples 아래 파일 이름이어야 합니다: ${name}`);
  const file = path.join(root, 'samples', `${name}.json`);
  assert.ok(fs.existsSync(file), `견본이 없습니다: samples/${name}.json`);
  return file;
}

/** 견본을 읽어 모델을 만들고, 지금 연표의 배치기를 통과시킨 연표 객체(tl)를 돌려준다. 보기 조건은 '모두 켠 · 자동 밀도 · 아무것도 접지 않음'. (노드 전용)
    견본은 HT_EXPORT_SAMPLE(형식 3 견본 — 그 견본 하나를 기본 DLC로) · 없으면 등불 연대기. HT_EXPORT_PACK(내장 DLC)이 있으면 그것이 먼저다. */
export async function loadContext(sample = sampleFile()) {
  const HT = bootWeb();
  // 내장 DLC(packs/<이름>/*.js — HT.definePack · extendPack …으로 채우는 꼴)는 index.html이 싣는 차례 그대로 돌려 모은다.
  // 환경 변수 HT_EXPORT_PACK=<packs 아래 폴더 이름>(예: east-asia). 없으면 견본 JSON(등불 연대기).
  const builtin = process.env.HT_EXPORT_PACK || '';
  // HT_EXPORT_PACK=- : 기본 DLC 없이 — 얹는 DLC(HT_EXPORT_EXTRA)의 첫째가 기본 자리에 선다(기본팩을 끄거나 뺀 서재 · add-dlc.mjs).
  if (builtin === '-') {
    const files = (process.env.HT_EXPORT_EXTRA || '').split(';').map(s => s.trim()).filter(Boolean);
    assert.ok(files.length, 'HT_EXPORT_PACK=- 이면 HT_EXPORT_EXTRA에 DLC가 하나 이상 있어야 합니다');
    const raws = [];
    for (const file of files) raws.push((await HT.packFile.parse(new Uint8Array(fs.readFileSync(file)))).raw);
    return contextOf(HT, raws, files.slice(1));
  }
  let raw;
  if (builtin) {
    const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
    const files = [...html.matchAll(/<script src="(packs\/[^"]+\.js)"/g)].map(m => m[1]).filter(f => f.startsWith(`packs/${builtin}/`));
    assert.ok(files.length, `index.html에 packs/${builtin}/ 의 스크립트가 없습니다`);
    for (const file of files) runScript(file);
    const packs = HT.getBuiltinPacks();
    assert.equal(packs.length, 1, `내장 DLC가 하나여야 합니다(지금 ${packs.length}개)`);
    raw = packs[0];
  } else {
    raw = JSON.parse(fs.readFileSync(sample, 'utf8'));
  }
  // 더 얹는 DLC: 환경 변수 HT_EXPORT_EXTRA=<.htpack 경로>;<경로>… (메이커가 내보낸 파일 그대로). 기본 DLC 뒤에 차례대로 얹어
  // 지금 연표가 DLC 여러 벌을 켰을 때와 같은 모형을 만든다 — 줄 배치는 전체를 두고 셈하므로 DLC를 더하면 다시 내보내야 한다.
  const extraFiles = (process.env.HT_EXPORT_EXTRA || '').split(';').map(s => s.trim()).filter(Boolean);
  const raws = [raw];
  for (const file of extraFiles) raws.push((await HT.packFile.parse(new Uint8Array(fs.readFileSync(file)))).raw);
  return contextOf(HT, raws, extraFiles);
}

/** 문맥 만들기(노드 · 메이커의 일꾼 공용): 원본 DLC 목록(raws — 첫째가 기본, 나머지는 켠 차례)을 정규화해 모델을 짓고,
    지금 연표의 배치기를 통과시킨다. labels = 둘째부터의 이름(읽지 못할 때의 알림에). */
export function contextOf(HT, raws, labels = []) {
  const el = stubElement;
  const raw = raws[0];
  const packs = raws.map((r, i) => {
    const norm = HT.normalizePack(r);
    assert.ok(norm.pack, `DLC를 읽을 수 없습니다(${i === 0 ? '기본' : labels[i - 1]}): ${(norm.errors || []).map(e => e.msg).join(' · ')}`);
    return norm.pack;
  });
  const ids = new Set();
  for (const p of packs) {
    assert.ok(!ids.has(p.id), `같은 id의 DLC가 둘입니다: ${p.id}`);
    ids.add(p.id);
  }
  const model = HT.buildModel(packs, null, { groupBands: true }); // 단체의 띠(리메이크 조각 ④ — 실권 정권 · 숨은 단체 띠)는 내보내기에서만
  // 항목이 어느 DLC에서 왔는가(순번 · 기본 DLC = 0): packId → uid의 앞머리(`<DLC id>/…`) → 트랙은 그 트랙을 처음 말한 DLC.
  const packIndex = new Map(packs.map((p, i) => [p.id, i]));
  const trackPack = new Map();
  packs.forEach((p, i) => { for (const t of p.tracks || []) if (t && t.id && !trackPack.has(t.id)) trackPack.set(t.id, i); });
  const packOf = x => {
    if (!x) return 0;
    if (x.packId && packIndex.has(x.packId)) return packIndex.get(x.packId);
    if (typeof x.uid === 'string' && x.uid.includes('/') && packIndex.has(x.uid.split('/')[0])) return packIndex.get(x.uid.split('/')[0]);
    return 0;
  };

  // 생성자를 건너뛰고(진짜 화면 요소를 요구한다) 배치가 읽는 상태만 기본값으로 채운다 — js/timeline.js의 constructor와 같은 값.
  // groups(표시 체크 '단체' — HT.SHOW_DEFAULTS와 같이 기본 켬): 집권 단 · 실권 단(줄 단위 덧단 13 + 2)과 연합의 겹 탭 · 명목 지도자를 웹과 같게 셈한다.
  // 새 앱이 그 칸을 그리므로(설계 7-8 11-3 · 구현 기록 13절) 켠다 — 단체 자료가 없는 줄은 덧단이 없어 옛 배치와 1px도 같다.
  const tl = Object.create(HT.Timeline.prototype);
  Object.assign(tl, {
    show: { leaders: true, cabinets: true, eras: true, capitals: true, ganji: true, succession: true, partOf: true, epochs: true, groups: true },
    folded: new Set(), foldedPeoples: new Set(), foldedEras: new Set(), expandedHosts: new Set(), expandedGroups: new Set(), foldedHangs: new Set(), scopesOn: {},
    axisOpen: new Set(['eras', 'capitals']), openCapSec: new Set(), altCal: '', _calOpen: false, axisEl: el(), opts: {},
    density: 0, _bird: null, _lod: new Map(), gutter: 196, depth: 1, hiLayout: null, highlight: null, selected: null,
    packRows: true, // 줄 채우기(리메이크 2부 — 겹치지 않는 승계 사슬은 한 줄에 · js/timeline.js packChains) — 새 앱만
  });
  // setData의 준비 구간(트랙별로 띠와 사건을 나누고 왕조 · 속국 이름표를 정리)을 그대로 따른다.
  tl._data = { tracks: model.tracks, periods: model.periods, events: model.events, epochs: model.epochs, categories: model.categories, scopes: model.scopes, figures: model.figures || [] };
  tl._setScopes(model.scopes);
  // 리메이크 2부: 기본 배치는 **모든 그릇을 풀어 둔다**(자료의 default도) — 그래야 모든 그릇이 변형(`scope:<uid>`)이 되어 새 앱이 펼침 · 접힘 · 풀림을 다 할 수 있다.
  // 처음에 켤 그릇(default)은 새 앱이 처음 열 때 켠다(archive_app `_openDefaultScopes`). 웹 연표의 scopeOn(기록 없으면 default)과는 일부러 다르다.
  tl.scopesOn = Object.fromEntries((model.scopes || []).map(s => [s.uid, false]));
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
  for (const p of model.periods) {
    for (const c of p.capitals || []) {
      if (!tl._cityUses.has(c.city)) tl._cityUses.set(c.city, []);
      tl._cityUses.get(c.city).push({ p, c });
    }
  }
  tl._dynUids = new Set();
  for (const p of model.periods) {
    if (p.polityKind === 'dynasty') tl._dynUids.add(p.uid);
    else if (byId.has(p.track)) byId.get(p.track).periods.push(p);
  }
  // 인물의 활동 막대: 섬긴 정권마다 하나, 그 정권의 트랙에(setData와 같은 규칙). 줄 · 단은 _layoutTrack이 정한다.
  for (const f of tl._data.figures) {
    (f.services || []).forEach((s, i) => {
      const tr = s.shown && s.polity ? byId.get(s.polity.track) : null;
      if (tr) tr.figures.push({ f, s, i, row: null, lvl: -1, band: null });
    });
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
  tl.depth = Math.max(1, ...tl.tracks.map(tr => tr.depth || 1));
  return { HT, raw, raws, packs, packOf, trackPack, model, tl, trackIndex: new Map(tl.tracks.map((tr, i) => [tr.id, i])) };
}

/** 모듈을 차례로 돌려 가져오기 JSON 3판(out)을 만든다 — 노드 도구(export-layout.mjs)와 메이커의 일꾼이 같은 길을 쓴다.
    skip: 건너뛸 모듈 이름 · has(name): 그 모듈이 있는가(노드 도구는 파일이 있는지 본다) · progress(name, i, n): 모듈을 부르기 전마다(메이커의 진행 글).
    끝에 공통 점검(가리키는 곳이 있는가)을 한다. */
export async function runModules(ctx, { skip = new Set(), has = () => true, progress = null } = {}) {
  ctx.shared = {}; // 모듈끼리 나눠 쓰는 것(예: 띠의 uid → out.periods의 순번)
  ctx.notes = {}; // 모듈이 남기는 집계 · 뺀 것의 기록(끝에 찍는다)
  // packs: 이 배치에 든 DLC(첫째가 기본). 가져오기가 DLC마다 자료집 줄을 하나씩 만들고, 항목은 uid의 앞머리 · `pack` 열쇠로 제 DLC에 붙는다.
  // version(DLC의 판) · category(팩 분류 — 지도팩 'map' …)는 있을 때만 싣는다(가져오기가 meta.pack_info로 남긴다 — A2의 조합 대조 · DLC 카드).
  const packInfo = p => {
    const o = { id: p.id, name: p.name || p.id };
    if (typeof p.version === 'string' && p.version.trim()) o.version = p.version.trim();
    if (typeof p.category === 'string' && p.category.trim()) o.category = p.category.trim();
    return o;
  };
  const out = { name: ctx.raw.name, packs: ctx.packs.map(packInfo), categories: [], tracks: [], epochs: [], axis: [], periods: [], cells: [], events: [], items: [], entities: [] };
  // D4 간지 설정: 처음 고른 순환과 DLC 차례의 후보를 함께 싣는다. 앱에서 DLC를 끄면 다음 후보를 고를 수 있게 한다.
  // 정상화된 팩의 false는 '끔'이고, 적지 않은 값과 다르다. 설정이 없으면 옛 내보내기 열쇠를 하나도 늘리지 않는다.
  if (ctx.model.yearCycle) {
    out.yearCycle = JSON.parse(JSON.stringify(ctx.model.yearCycle));
    out.yearCycles = ctx.packs.filter(p => p.yearCycle !== undefined && p.yearCycle !== null).map(p =>
      Object.assign(p.yearCycle === false ? { off: true } : JSON.parse(JSON.stringify(p.yearCycle)), { packId: p.id, packName: p.name }));
  }
  const live = MODULES.filter(name => !skip.has(name) && has(name));
  for (const [i, name] of live.entries()) {
    if (progress) await progress(name, i, live.length);
    const mod = await importModule(name);
    await mod.contribute(ctx, out);
  }
  // 늦은 차례: 모든 모듈이 제 몫을 실은 뒤에 한 번 더 — 남이 실은 항목 기록에 값을 얹는 모듈이 쓴다(docs의 x_docs · x_cellDocs).
  for (const name of live) {
    const mod = await importModule(name);
    if (mod.contributeLate) await mod.contributeLate(ctx, out);
  }

  // 공통 점검: 줄 · 띠 · 칸 · 사건 · 일반 항목이 가리키는 곳이 있어야 한다.
  const rowsOf = out.tracks.map(t => t.rows.length);
  const periodUids = new Set(out.periods.map(p => p.uid));
  for (const p of out.periods) assert.ok(p.track < rowsOf.length && p.row < rowsOf[p.track] && p.start <= p.end, `띠의 자리 오류: ${p.name}`);
  for (const c of out.cells) assert.ok(periodUids.has(c.period) && c.start <= c.end, `칸이 가리키는 띠가 없거나 기간이 뒤집혔습니다: ${c.name}`);
  for (const e of out.events) assert.ok(e.track < rowsOf.length && e.row < rowsOf[e.track], `사건의 줄이 없습니다: ${e.title}`);
  for (const it of out.items) assert.ok(it.section >= 16 && it.track < rowsOf.length && it.row <= it.row2 && it.row2 < rowsOf[it.track] && it.start <= it.end, `일반 항목의 자리 오류: 구역 ${it.section} ${it.name}`);
  return out;
}

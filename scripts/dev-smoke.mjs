// 개발용 빠른 검사 (브라우저 없이): node scripts/dev-smoke.mjs [--json]
// 핵심 코드(calendar · core · 기본팩)를 노드에서 돌려 ① 기본팩과 samples/*.json 이 오류 없이 정규화되는지
// ② 정규화 → 내보내기(packToJSON) → 다시 정규화를 돌아도 자료가 줄지 않는지(왕복) ③ 모델이 만들어지는지
// ⑨ 바탕 표(날짜 칸 · 항목 목록 · 폼 · 형식 버전)가 서로 맞는지 ⑩ 메이커의 작업본 계산(HT.draft: 추가 · 고침 · 패치 · 숨김 · 문서 · 판 올림 · 옛 "내 수정"의 이사)이 맞는지
// ⑪ 두 화면(index.html 보기 전용 · dlc-maker.html 메이커)의 뼈대가 맞는지 봅니다. 화면(연표 · 메이커)의 동작은 검사하지 못합니다 — 그것은 브라우저에서.
// 블록 번호(④ ~)는 파일 안의 차례대로입니다 — 새 블록은 끝에 다음 번호로. 번호 없는 블록(플래그 탭 · 실재성 · 대범위와 그 검토 반영 — ⑩과 ⑪ 사이)은 합칠 때 그 자리에 들어온 것입니다.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { createHash } from 'node:crypto';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const noop = () => {};
const el = () => ({ style: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false }, appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop, querySelector: () => null, querySelectorAll: () => [], getContext: () => ({ measureText: t => ({ width: String(t).length * 7 }), font: '' }) });
const store = new Map();
const g = globalThis;
g.window = g;
g.document = { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop, removeEventListener: noop, getAnimations: () => [] };
g.localStorage = { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
g.matchMedia = () => ({ matches: false, addEventListener: noop, addListener: noop });
g.getComputedStyle = () => ({ getPropertyValue: () => '' });
g.requestAnimationFrame = cb => setTimeout(() => cb(Date.now()), 0);
g.cancelAnimationFrame = id => clearTimeout(id);
if (!g.navigator) g.navigator = { userAgent: 'node' };

const load = rel => vm.runInThisContext(readFileSync(join(root, rel), 'utf8'), { filename: rel });
['js/calendar.js', 'js/core.js'].forEach(load);
/* 기본팩 파일은 index.html 이 부르는 순서 그대로 (relations.js 는 모든 트랙 뒤에 와야 함) */
[...readFileSync(join(root, 'index.html'), 'utf8').matchAll(/<script src="(packs\/[^"]+)"/g)].forEach(m => load(m[1]));
const HT = g.HT;

const sortKeys = v => (Array.isArray(v) ? v.map(sortKeys) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sortKeys(v[k])])) : v);
const canon = v => JSON.stringify(sortKeys(v));
const hash = s => createHash('sha1').update(s).digest('hex').slice(0, 10);
const out = { packs: [], problems: [] };

const packs = [];
for (const raw of HT.getBuiltinPacks()) {
  const r = HT.normalizePack(raw);
  if (!r.pack) out.problems.push(`기본팩 ${raw.id}: 정규화 실패 — ${r.errors.map(e => e.msg).join(' / ')}`);
  else packs.push(r.pack);
  out.packs.push({ id: raw.id, errors: r.errors.length, warnings: r.warnings.length });
}
/* --skip=글자: 파일 이름에 그 글자가 든 견본은 건너뜁니다 (새 견본을 빼고 옛 모델 해시가 그대로인지 볼 때 — 여러 번 적어도 됨) */
const skipSamples = process.argv.filter(a => a.startsWith('--skip=')).map(a => a.slice(7)).filter(Boolean);
for (const f of readdirSync(join(root, 'samples')).filter(f => f.endsWith('.json')).sort()) {
  if (skipSamples.some(s => f.includes(s))) continue;
  const raw = JSON.parse(readFileSync(join(root, 'samples', f), 'utf8'));
  const a = HT.normalizePack(raw);
  if (!a.pack) {
    out.problems.push(`${f}: 정규화 실패 — ${a.errors.map(e => e.msg).join(' / ')}`);
    continue;
  }
  const json = HT.packToJSON(a.pack);
  const b = HT.normalizePack(JSON.parse(JSON.stringify(json)));
  const same = b.pack && canon(HT.packToJSON(b.pack)) === canon(json);
  if (!same) out.problems.push(`${f}: 왕복(정규화 → 내보내기 → 정규화)에서 자료가 달라짐`);
  out.packs.push({ id: raw.id, file: f, errors: a.errors.length, warnings: a.warnings.length, roundtrip: !!same, hash: hash(canon(json)) });
  packs.push(a.pack);
}

let model = null;
try {
  model = HT.buildModel(packs, null);
} catch (e) {
  out.problems.push(`buildModel 예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
}
if (model) {
  const pick = x => ({ uid: x.uid, kind: x.kind, itemKind: x.itemKind, polityKind: x.polityKind, start: x.start, endY: x.endY, track: x.track, name: x.name || x.title, row: undefined });
  out.model = {
    tracks: model.tracks.length,
    periods: model.periods.length,
    events: model.events.length,
    epochs: model.epochs.length,
    peoples: model.peoples.length,
    extra: Object.fromEntries(['houses', 'figures', 'scopes', 'ranks'].filter(k => Array.isArray(model[k])).map(k => [k, model[k].length])),
    hash: hash(canon(model.periods.map(pick).concat(model.events.map(pick)))),
  };
}

/* ④ 칸 종류 표(HT.CELL_KINDS): 줄마다 갖출 것 · 문서 키가 표에서 나오는지(문서 없는 종류는 빠지고, 표에 더한 종류는 곧바로 풀림) ·
   모델의 모든 칸이 놓이는 구간(HT.cellSpan — 칸 조명이 칠하는 구간)이 거꾸로 되지 않는지 · 표시 체크(뷰어 SHOW_TOGGLES)가 기본값 표 · 화면에 있는지 */
{
  const bad = msg => out.problems.push(`칸 종류 표: ${msg}`);
  const ids = new Set();
  for (const K of HT.CELL_KINDS) {
    if (!K.id || !K.list || !K.name || typeof K.title !== 'function') bad(`"${K.id || K.list}" 줄에 id · list · name · title 가운데 빠진 것이 있음`);
    if (ids.has(K.id) || ids.has(K.list)) bad(`"${K.id}"이(가) 두 번 나옴`);
    ids.add(K.id).add(K.list);
    if (HT.cellKind(K.id) !== K || HT.cellKind(K.list) !== K) bad(`HT.cellKind가 "${K.id}" 줄을 찾지 못함`);
  }
  const cellOf = list => HT.docKey.cell('어느팩/어느나라', list, { name: '어느 칸', start: -57.5 });
  for (const K of HT.CELL_KINDS.filter(k => k.doc !== false)) {
    const key = cellOf(K.list);
    const p = HT.docKey.parse(`${key}//하위`);
    if (p.type !== 'cell' || p.cellKind !== K.list || p.uid !== '어느팩/어느나라' || p.name !== '어느 칸' || p.start !== -58 || p.sub !== '하위') bad(`"${K.list}" 칸의 문서 키가 풀리지 않음 (${key})`);
    const rel = HT.docKey.relative(key, '어느팩');
    if (rel !== `cell:어느나라:${K.list}:어느 칸@-58` || HT.docKey.absolute(rel, '어느팩') !== key) bad(`"${K.list}" 칸의 문서 키가 상대 ↔ 절대 키를 오가지 못함 (${rel})`);
  }
  HT.CELL_KINDS.push({ id: 'smokeA', list: 'smokeAs', name: '검사', title: c => c.name }, { id: 'smokeB', list: 'smokeBs', name: '검사', doc: false, title: c => c.name });
  if (HT.docKey.parse(cellOf('smokeAs')).type !== 'cell') bad('표에 더한 종류의 문서 키가 곧바로 풀리지 않음');
  if (HT.docKey.parse(cellOf('smokeBs')).type === 'cell') bad('문서를 달지 않는 종류(doc: false)의 키가 칸 문서로 풀림');
  HT.CELL_KINDS.splice(-2, 2);
  if (HT.docKey.parse(cellOf('smokeAs')).type === 'cell') bad('표에서 뺀 종류의 문서 키가 아직 풀림');
  if (model) {
    let cells = 0;
    for (const p of model.periods)
      for (const K of HT.CELL_KINDS)
        HT.cellsOf(p, K).forEach((c, i) => {
          cells++;
          const sp = HT.cellSpan(c, p);
          if (!(sp.end >= sp.start) && !(HT.endBound(sp.end, sp.endAt) >= sp.start)) bad(`${p.name} ${K.name} ${i + 1}번째 칸(${c.name})이 놓이는 구간이 거꾸로임 (${sp.start} ~ ${sp.end})`);
        });
    if (!cells) bad('모델에 칸이 하나도 없음 — HT.cellsOf가 목록을 찾지 못함');
  }
  if (HT.SHOW_DEFAULTS.spotEcho !== false) bad('조명 메아리(spotEcho)의 기본값이 끔(false)이 아님');
  const viewerSrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const indexHtml = readFileSync(join(root, 'index.html'), 'utf8');
  const makerHtml0 = readFileSync(join(root, 'dlc-maker.html'), 'utf8'); // 메이커도 같은 화면(viewer.js)이라 표시 체크가 모두 있어야 함 (없으면 체크를 묶는 줄에서 멈춤)
  const toggles = [...viewerSrc.matchAll(/(?:const SHOW_TOGGLES = |Object\.assign\(SHOW_TOGGLES, )\{([^}]*)\}/g)].flatMap(m => [...m[1].matchAll(/(\w+): '(\w+)'/g)].map(x => [x[1], x[2]]));
  if (!toggles.length) bad('뷰어의 표시 체크 표(SHOW_TOGGLES)를 찾지 못함');
  for (const [id, key] of toggles) {
    if (!(key in HT.SHOW_DEFAULTS)) bad(`표시 체크 "${key}"의 기본값이 HT.SHOW_DEFAULTS에 없음`);
    if (!indexHtml.includes(`id="${id}"`)) bad(`표시 체크 "${id}"이(가) index.html에 없음`);
    if (!makerHtml0.includes(`id="${id}"`)) bad(`표시 체크 "${id}"이(가) dlc-maker.html에 없음`);
  }
}

/* ⑤ 가문: 표시 기본값(끔) · 문서 키 "house:id"가 풀리고 DLC id가 붙지 않는지 · 모델이 짐작한 값(houseId …)이 팩(내보내는 파일)에 섞이지 않는지 ·
   견본(lantern-chronicle)이 있으면 풀이 규칙(적은 가문 → 국성 · 본가 → 분가 · 여러 나라에 걸친 가문의 구성원) */
{
  const bad = msg => out.problems.push(`가문: ${msg}`);
  if (HT.SHOW_DEFAULTS.houses !== false) bad('가문 줄(houses)의 기본값이 끔(false)이 아님');
  const pk = HT.docKey.parse('house:어느가문//하위');
  if (pk.type !== 'house' || pk.id !== '어느가문' || pk.sub !== '하위') bad('문서 키 "house:id"가 가문으로 풀리지 않음');
  if (HT.docKey.absolute('house:어느가문', '어느팩') !== 'house:어느가문' || HT.docKey.relative('house:어느가문', '어느팩') !== 'house:어느가문') bad('가문 문서 키에 DLC id가 붙음');
  for (const p of packs) if (/"house(Id|Name|Color|Auto)"/.test(JSON.stringify(HT.packToJSON(p)))) bad(`${p.id}: 모델이 풀어낸 가문 값이 팩에 섞임`);
  const sp = packs.find(p => p.id === 'lantern-chronicle');
  if (sp) {
    const m = HT.buildModel([sp], null);
    const H = name => m.houses.find(h => h.name === name) || {};
    const P = name => m.periods.find(p => p.name === name);
    const L = (p, name) => (P(p).leaders || []).find(c => c.name === name) || {};
    if (!H('휘씨').id || !H('휘씨 본파').id || H('휘씨 본파').parentId !== H('휘씨').id || H('휘씨 남파').parentId !== H('휘씨').id) bad('본가 → 분가(id로 적은 본가)가 이어지지 않음');
    // 견본 2.0.1은 인물 · 지도자가 가문 목록에 있는 id · 이름만 적음(2.0.0의 목록 밖 id 넷은 2.0.1에서 온담씨 · 단목씨로 잇고 물새씨 · 백탑 대단장가를 더함) — 새 가문(auto)이 생기지 않아야 함
    const autos = m.houses.filter(h => h.auto);
    if (autos.length) bad(`가문 목록에 있는 이름 · id만 쓴 견본에 새 가문(auto)이 생김: ${autos.map(h => h.name)}`);
    if (P('등불 왕국').houseId !== H('휘씨').id) bad('국성이 풀리지 않음');
    if (L('등불 왕국', '휘명왕').houseId !== H('휘씨').id || !L('등불 왕국', '휘명왕').houseAuto) bad('가문을 적지 않은 지도자가 국성으로 짐작되지 않음');
    if (L('등불 왕국', '단등왕').houseId !== H('서목씨').id || L('등불 왕국', '단등왕').houseAuto) bad('지도자에게 적은 가문이 국성보다 앞서지 않음');
    if (new Set((H('휘씨 남파').members || []).map(x => x.item.name)).size < 3) bad('여러 나라에 걸친 가문(휘씨 남파)의 구성원이 여러 나라에서 모이지 않음');
    if (!m.docs.has('house:h-hwi') || !m.docs.has('house:h-ondam')) bad('가문의 문서(houses[].wiki · documents의 house:id)가 문서 색인에 없음');
  }
  /* 형식 버전: 가문을 쓰는 꼴이 모두 2로 나가는지 (패치의 국성 · 패치의 옛 이름 reigns의 가문 · 가문 문서만 담은 DLC · 가문 사전만 담은 DLC) — 옛 꼴 왕조의 house만이면 1 */
  const one = (extra, label) => {
    const r = HT.normalizePack(Object.assign({ format: 'history-timeline-dlc', formatVersion: 2, id: 'smoke-house-ver', name: '검사' }, extra));
    if (!r.pack) {
      bad(`${label}: 검사 팩을 읽지 못함 — ${r.errors.map(e => e.msg).join(' / ')}`);
      return null;
    }
    return { pack: r.pack, ver: HT.packToJSON(r.pack).formatVersion, empty: r.warnings.some(w => /하나도 없습니다/.test(w.msg)) };
  };
  const ver = (extra, want, label) => {
    const x = one(extra, label);
    if (x && x.ver !== want) bad(`${label}이(가) 형식 버전 ${want}로 나가지 않음 (${x.ver})`);
  };
  ver({ patches: [{ target: '다른팩/어느나라', set: { house: '어느 가문' } }] }, 2, '국성을 고치는 패치(set.house)');
  ver({ patches: [{ target: '다른팩/어느나라', set: { reigns: [{ name: '갑', start: 10, end: 20, house: '어느 가문' }] } }] }, 2, '패치의 옛 이름 reigns에 적은 가문');
  ver({ documents: { 'house:다른가문': '본문', 'house:다른가문//하위': '본문' } }, 2, '가문 문서만 담은 DLC');
  ver({ tracks: [{ id: 't', name: '검사 땅' }], dynasties: [{ id: 'd', track: 't', name: '검사 왕조', start: 10, end: 20, house: '본가 왕조' }] }, 1, '옛 꼴 왕조의 house만 쓴 DLC');
  const only = one({ houses: [{ id: 'h-a', name: '가 가문' }] }, '가문 사전만 담은 DLC');
  if (only && only.ver !== 2) bad(`가문 사전만 담은 DLC가 형식 버전 2로 나가지 않음 (${only.ver})`);
  if (only && only.empty) bad('가문 사전만 담은 DLC에 "하나도 없습니다" 경고가 뜸');
}

/* ⑥ 칸이 품는 끝(HT.cellSpan의 hi — 칸 조명 · 그 시기의 사건 · "이 시기로"): 사람이 적은 연도만의 끝은 그 해에 다음 칸이 시작하면 그 시작까지
   (경계 해는 뒤 칸의 것 — 칸의 경계 HT.cellBounds, 자세한 경우는 ㊱), 이어받는 칸이 없으면 그해 끝까지,
   끝을 비워 다음 정도의 시작에서 끌어낸 도읍의 끝은 다음 칸이 시작하는 순간 그대로(연표처럼 다음 칸과 겹치지 않게), 정권 끝까지인 칸은 그해 끝까지 ·
   모델이 풀어낸 표시(endYNext)가 팩(내보내는 파일)에 섞이지 않는지 */
{
  const bad = msg => out.problems.push(`칸이 품는 끝: ${msg}`);
  const r = HT.normalizePack({
    format: 'history-timeline-dlc',
    formatVersion: 1,
    id: 'smoke-cell-hi',
    name: '검사',
    tracks: [{ id: 't', name: '검사 땅' }],
    periods: [{ id: 'p', track: 't', name: '검사 나라', start: 300, end: 500, leaders: [['갑', 300, 350], ['을', 350]], capitals: [['가', 300], ['나', 380], ['다', 420, null, '배도']] }],
  });
  if (!r.pack) bad(`검사 팩을 읽지 못함 — ${r.errors.map(e => e.msg).join(' / ')}`);
  else {
    const p = HT.buildModel([r.pack], null).periods.find(x => x.name === '검사 나라');
    const cap = name => (p.capitals || []).find(c => c.city === name);
    const hi = c => (c ? HT.cellSpan(c, p).hi : NaN);
    if (hi(cap('가')) !== 380) bad(`끝을 비운 도읍의 끝이 다음 정도의 시작(380)이 아님 (${hi(cap('가'))}) — 다음 칸과 한 해가 겹침`);
    if (hi(cap('나')) !== HT.endBound(500, null)) bad(`다음 정도가 없는 도읍의 끝이 정권의 끝 해의 끝이 아님 (${hi(cap('나'))})`);
    if (hi(cap('다')) !== HT.endBound(500, null)) bad(`배도의 끝이 정권의 끝 해의 끝이 아님 (${hi(cap('다'))})`);
    if (hi((p.leaders || [])[0]) !== 350) bad(`연도만 적은 지도자의 끝 해(350)에 다음 지도자가 시작하는데 끝이 그 시작(350)이 아님 (${hi((p.leaders || [])[0])}) — 경계 해가 두 칸에 모두 듦`);
    if (hi((p.leaders || [])[1]) !== HT.endBound(500, null)) bad('이어받는 칸이 없는 지도자(끝을 비움 — 정권 끝까지)의 끝이 그해 끝까지가 아님');
    if (/endYNext/.test(JSON.stringify(HT.packToJSON(r.pack)))) bad('모델이 풀어낸 도읍 표시(endYNext)가 팩에 섞임');
  }
}

/* ⑦ 칸의 미정: 칸(지도자 · 내각 · 연호 · 도읍)과 소속 기간의 "미정" 읽기(글 · 짧은 꼴 · startHint · startUnknown과 숫자) · 파일에 남는 꼴 · 형식 버전 2 ·
   모델의 자리 잡기(앞 칸의 끝 → 앞 칸의 끝도 비었으면 가운데 → 정권의 시작 · 다음 칸의 시작 → 정권의 끝) · 짐작한 자리(startAuto · endAuto)가 파일 · 폼 · 내보내기 비교에 섞이지 않는지 ·
   한 줄 글("이름 미정~538") · 경고(시작 · 끝 모두 미정이고 배치용 연도 없음) · 옛 자료에는 미정 표시가 하나도 생기지 않는지 */
{
  const bad = msg => out.problems.push(`칸의 미정: ${msg}`);
  const r = HT.normalizePack({
    format: 'history-timeline-dlc',
    formatVersion: 2,
    id: 'smoke-cell-unk',
    name: '검사',
    tracks: [{ id: 't', name: '검사 땅' }],
    periods: [
      { id: 'up', track: 't', name: '위 나라', start: 300, end: 700 },
      {
        id: 'p', track: 't', name: '검사 나라', start: 400, end: 640,
        leaders: [['갑', 400, 452], { name: '을', start: 452, end: '미정' }, ['병', 488, 530], { name: '정', start: '미정', end: 575 }, ['무', 575]],
        cabinets: [{ name: '가', start: '미정', end: '미정' }],
        eras: [['아', 400, 460], { name: '한', start: '미정', startHint: 470, end: '모름', endHint: '505' }, { name: '저', startUnknown: true, start: 520 }],
        capitals: [['샘', 400], ['바위', '미정', 538], ['구름', 538], { city: '곁', start: '?', role: '배도' }],
        partOf: [{ polity: '위 나라', start: 400, end: '미정' }, { polity: '위 나라', start: '미정', startHint: 520 }],
      },
    ],
    patches: [{ target: '다른팩/어느나라', set: { leaders: [['하나', '미정', 10]] } }],
  });
  if (!r.pack) bad(`검사 팩을 읽지 못함 — ${r.errors.map(e => e.msg).join(' / ')}`);
  else {
    const P = r.pack.periods.find(x => x.id === 'p');
    const L = n => P.leaders.find(c => c.name === n) || {};
    if (!L('을').endUnknown || 'end' in L('을')) bad('끝이 "미정"인 지도자가 endUnknown으로만 남지 않음');
    if (!L('정').startUnknown || 'start' in L('정') || L('정').end !== 575) bad('시작이 "미정"인 지도자의 파일 꼴이 { startUnknown, end }가 아님');
    const han = P.eras.find(c => c.name === '한') || {};
    if (!(han.startUnknown && han.start === 470 && han.endUnknown && han.end === 505)) bad(`startHint · endHint("모름"도)가 배치용 연도(start · end 숫자)로 남지 않음 (${JSON.stringify(han)})`);
    const jeo = P.eras.find(c => c.name === '저') || {};
    if (!(jeo.startUnknown && jeo.start === 520)) bad('startUnknown: true와 함께 적은 숫자가 배치용 연도로 읽히지 않음');
    const bawi = P.capitals.find(c => c.city === '바위') || {};
    if (!(bawi.startUnknown && !('start' in bawi) && bawi.end === 538)) bad(`짧은 꼴 ["도시", "미정", 538]이 읽히지 않음 (${JSON.stringify(bawi)})`);
    const part = HT.readPartOf(P.partOf);
    if (!(part[0].endUnknown && part[1].startUnknown && part[1].start === 520)) bad('소속 기간의 "미정"이 읽히지 않음');
    if (!r.warnings.some(w => /모두 미정/.test(w.msg) && /"가"/.test(w.msg))) bad('시작 · 끝이 모두 미정이고 배치용 연도가 없는 칸에 경고가 없음');
    const patchL = ((r.pack.patches[0] || {}).set || {}).leaders || [];
    if (!(patchL[0] && patchL[0].startUnknown && patchL[0].end === 10)) bad('패치의 칸 목록에서 "미정"이 다시 읽히지 않음');
    const json = HT.packToJSON(r.pack);
    if (json.formatVersion !== 2 || !HT.usesCellUnknown(json)) bad('칸의 미정을 쓴 파일이 형식 버전 2로 나가지 않음');
    const again = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (!again.pack || canon(HT.packToJSON(again.pack)) !== canon(json)) bad('칸의 미정을 쓴 파일이 왕복(내보내기 → 읽기)에서 달라짐');
    for (const p of packs) if (HT.usesCellUnknown(p) && p.id !== 'lantern-chronicle') bad(`${p.id}: 미정을 쓰지 않은 팩인데 칸의 미정으로 봄`);
    const m = HT.buildModel([r.pack], null);
    const p = m.periods.find(x => x.name === '검사 나라');
    const M = (k, n) => (p[k] || []).find(c => (c.name || c.city) === n) || {};
    const near = (a, b) => Math.abs(a - b) < 1e-9;
    if (!(near(M('leaders', '을').end, 488) && M('leaders', '을').endAuto)) bad(`끝이 미정인 지도자가 다음 지도자의 시작(488)까지 놓이지 않음 (${M('leaders', '을').end})`);
    if (!near(HT.cellSpan(M('leaders', '을'), p).hi, 488)) bad('다음 칸의 시작에서 끌어낸 끝이 그 순간까지가 아님 (다음 칸과 한 해가 겹침)');
    if (!(near(M('leaders', '정').start, 530) && M('leaders', '정').startAuto)) bad(`시작이 미정인 지도자가 앞 지도자의 끝(530)에 놓이지 않음 (${M('leaders', '정').start})`);
    if (!(near(M('eras', '한').start, 470) && near(M('eras', '한').end, 505) && !M('eras', '한').startAuto && !M('eras', '한').endAuto)) bad('배치용 연도가 있는 연호가 그 자리에 놓이지 않음');
    if (!(near(M('cabinets', '가').start, 400) && M('cabinets', '가').end == null && near(HT.cellSpan(M('cabinets', '가'), p).end, 640))) bad('시작 · 끝이 모두 미정이고 이웃이 없는 내각이 정권 전체 기간에 놓이지 않음');
    if (!(near(M('capitals', '바위').start, 469) && M('capitals', '바위').startAuto && near(M('capitals', '샘').endY, 469))) bad(`끝을 비운 앞 정도 뒤의 시작 미정 도읍이 둘 사이 가운데(469)에 놓이지 않음 (${M('capitals', '바위').start} · ${M('capitals', '샘').endY})`);
    if (!(near(M('capitals', '곁').start, 400) && M('capitals', '곁').startAuto)) bad('시작이 미정인 배도가 정권의 시작에 놓이지 않음');
    if (!(p.hosts.length === 2 && near(p.hosts[0].end, 520) && p.hosts[0].endUnknown && near(p.hosts[1].start, 520) && p.hosts[1].startUnknown)) bad('소속 기간의 미정이 앞뒤 소속에 맞춰 놓이지 않음');
    if (/Auto"/.test(JSON.stringify(HT.packToJSON(r.pack)))) bad('모델이 짐작한 자리(startAuto · endAuto)가 팩에 섞임');
    /* 모델의 칸을 다시 넣어도 파일의 꼴이 나옴 — 수정 폼(HT.formCell) · 내보내기 비교(HT.normalizeCapital) */
    const fc = HT.formCell('leaders', M('leaders', '정'));
    if (!(fc.startUnknown && !('start' in fc))) bad('수정 폼이 모델이 짐작한 시작을 자료로 채움');
    const fh = HT.formCell('eras', M('eras', '한'));
    if (!(fh.startUnknown && fh.start === 470)) bad('수정 폼이 배치용 연도를 버림');
    if (canon(HT.normalizeCapital(M('capitals', '바위'))) !== canon(HT.normalizeCapital(bawi))) bad('모델의 도읍과 파일의 도읍을 내보내기 비교가 다른 값으로 봄');
    for (const k of HT.CELL_CHAIN) if (canon(HT.cellsFileForm(p[k])) !== canon(P[k])) bad(`모델의 ${k} 목록에서 짐작한 자리를 빼도 파일의 꼴과 같지 않음 (내보내기 비교가 고치지 않은 칸을 고친 것으로 봄)`);
    if (!M('capitals', '샘').endYAuto || canon(HT.normalizeCapital(M('capitals', '샘'))) !== canon(HT.normalizeCapital(P.capitals.find(c => c.city === '샘')))) bad('시작 미정인 다음 정도에서 짐작한 끝(endYAuto)이 표시되지 않거나 파일의 꼴에 섞임');
    /* 한 줄 글 */
    const probs = [];
    const tc = HT.textToCells('첫째 이름 미정~538 메모 글\n둘째 540~미정\n셋째 ?~', '검사', probs);
    if (probs.length || !(tc[0] && tc[0].name === '첫째 이름' && tc[0].startUnknown && tc[0].end === 538 && tc[0].note === '메모 글' && tc[1].endUnknown && tc[2].startUnknown && !tc[2].endUnknown)) bad(`한 줄 글 "이름 미정~538 메모"가 읽히지 않음 (${probs.join(' / ') || JSON.stringify(tc)})`);
    if (HT.cellsToText(tc) !== '첫째 이름 미정~538 메모 글\n둘째 540~미정\n셋째 미정~') bad(`칸 → 한 줄 글에 "미정"이 나오지 않음 (${HT.cellsToText(tc)})`);
  }
  /* 검토 반영: ① 왕조의 polities · 기관의 host는 나란히 갈 수 있어 앞뒤로 이어 붙이지 않음(미정인 쪽은 비운 쪽처럼 그 항목 기간의 처음 · 끝)
     ② 끝을 비운 정도 뒤에 끝도 없이 오는 시작 미정 도읍(["도시", "미정"])은 앞 정도의 시작과 다음 정도의 시작 사이 가운데 · 임시 · 공동은 그때 정도의 시작과 제 끝 사이 가운데
     (이어지는 칸 — 지도자도 같은 규칙) ③ 끝만 미정인 소속 하나는 접히지 않고 제 줄로 ④ 시작 · 끝 모두 미정인 소속 기간에 경고 */
  {
    const q = HT.normalizePack({
      format: 'history-timeline-dlc', formatVersion: 2, id: 'smoke-cell-unk-2', name: '검사',
      tracks: [{ id: 't', name: '검사 땅' }],
      periods: [
        { id: 'a', track: 't', name: '가 나라', start: 850, end: 1800, leaders: [['갑', 850], { name: '을', start: '미정' }, ['병', 1100]] },
        { id: 'b', track: 't', name: '나 나라', start: 850, end: 1100 },
        { id: 'c', track: 't', name: '다 나라', start: 400, end: 640, capitals: [['샘', 400], ['바위', '미정'], ['구름', 538]] },
        { id: 'd', track: 't', name: '라 나라', start: 400, end: 640, capitals: [['샘', 400], ['뜰', '미정', 480, '임시'], ['구름', 500]] },
        { id: 'e', track: 't', name: '마 나라', start: 900, end: 1000, partOf: [{ polity: '가 나라', end: '미정' }] },
        { id: 'f', track: 't', name: '바 나라', start: 900, end: 1000, partOf: [{ polity: '가 나라', start: '미정', end: '불명' }] },
      ],
      dynasties: [
        { id: 'y1', track: 't', name: '첫 왕가', start: 900, end: 1000, polities: [{ polity: '가 나라', start: 900, end: 1000 }, { polity: '나 나라', start: '미정', end: 1000 }] },
        { id: 'y2', track: 't', name: '둘째 왕가', start: 1453, end: 1700, polities: [{ polity: '가 나라', start: 1453, end: '미정' }, { polity: '나 나라', start: 1516, end: 1700 }] },
        { id: 'y3', track: 't', name: '셋째 왕가', start: 1200, end: 1300, polities: [{ polity: '가 나라', start: '미정', end: '미정' }] },
      ],
      organs: [{ id: 'g', track: 't', name: '검사 기관', start: 900, end: 1000, host: [{ polity: '가 나라', start: 900, end: '미정' }, { polity: '나 나라', start: 950 }] }],
    });
    if (!q.pack) bad(`검사 팩 2를 읽지 못함 — ${q.errors.map(e => e.msg).join(' / ')}`);
    else {
      const m = HT.buildModel([q.pack], null);
      const P = n => m.periods.find(x => x.name === n) || {};
      const near = (a, b) => Math.abs(a - b) < 1e-9;
      const dyn = (p, n) => (P(p).dynasties || []).filter(d => d.dynasty.name === n).map(d => `${d.start}~${d.end}`).join(',');
      if (dyn('나 나라', '첫 왕가') !== '900~1000') bad(`왕조의 나란한 polities에서 시작 미정인 쪽이 앞 칸의 끝(1000)으로 이어 붙음 — 나 나라의 왕조 칸 ${dyn('나 나라', '첫 왕가') || '없음'} (900~1000이어야)`);
      if (dyn('가 나라', '둘째 왕가') !== '1453~1700') bad(`왕조의 나란한 polities에서 끝 미정인 쪽이 다음 칸의 시작(1516)에서 잘림 — ${dyn('가 나라', '둘째 왕가')}`);
      const y1h = (P('첫 왕가').hosts || [])[1] || {};
      if (!(y1h.start == null && y1h.startUnknown && !y1h.startAuto)) bad('왕조의 polities에서 시작 미정인 쪽이 비운 쪽처럼(자리 없음 + 미정 표시) 남지 않음');
      const gh = (P('검사 기관').hosts || []).find(h => h.host.name === '가 나라') || {};
      if (!(gh.end == null && gh.endUnknown)) bad(`기관의 host에서 끝 미정인 쪽이 다음 host의 시작으로 잘림 (${gh.end})`);
      const cap = (p, n) => (P(p).capitals || []).find(c => c.city === n) || {};
      if (!(near(cap('다 나라', '바위').start, 469) && cap('다 나라', '바위').startAuto && near(cap('다 나라', '샘').endY, 469) && cap('다 나라', '샘').endYAuto))
        bad(`끝을 비운 정도 뒤의 ["도시", "미정"]이 앞 정도의 시작과 다음 정도의 시작 사이 가운데(469)에 놓이지 않음 (${cap('다 나라', '바위').start} · 앞 정도 끝 ${cap('다 나라', '샘').endY})`);
      if (!(near(cap('라 나라', '뜰').start, 440) && near(cap('라 나라', '샘').endY, 500)))
        bad(`시작 미정인 임시 도읍이 그때 정도의 시작과 제 끝 사이 가운데(440)에 놓이지 않음 (${cap('라 나라', '뜰').start} · 정도 끝 ${cap('라 나라', '샘').endY})`);
      const eul = (P('가 나라').leaders || []).find(c => c.name === '을') || {};
      if (!(near(eul.start, 975) && eul.startAuto)) bad(`끝을 비운 지도자 뒤에 끝도 없이 오는 시작 미정 지도자가 앞 지도자의 시작과 다음 지도자의 시작 사이 가운데(975)에 놓이지 않음 (${eul.start})`);
      if (P('마 나라').singleHost !== false) bad('끝만 미정인 소속 하나가 상위 정권 띠 아래로 접힘 (상국 띠의 이름표로 그려져야 끝이 옅어짐)');
      const w = q.warnings.map(x => x.msg);
      for (const [who, what] of [['바 나라', '소속'], ['셋째 왕가', '다스린 정권']])
        if (!w.some(x => x.includes(`"${who}"`) && x.includes(what) && /모두 미정/.test(x))) bad(`시작 · 끝이 모두 미정인 ${what} 기간에 경고가 없음 (${who})`);
      if (w.some(x => x.includes('"검사 기관"') && /모두 미정/.test(x))) bad('한쪽만 미정인 기관의 host에 경고가 뜸');
    }
  }
  /* 옛 자료(이 기능 전의 견본 · 기본팩): 모델의 칸에 미정 · 짐작 표시가 하나도 없어야 함 (1px도 같게).
     파일의 칸 목록을 그대로 쓰는 종류(지도자 · 내각 · 연호 · 도읍)와 소속만 봅니다 — 모델 전용 목록을 items로 돌려주는 종류(시기 · 지위)는
     경계를 채운 사본이라 startAuto · endAuto가 "비운 쪽을 이웃 · 정권에서 채움"이라는 제 뜻으로 늘 붙습니다 */
  const old = packs.filter(p => !HT.usesCellUnknown(p));
  if (old.length) {
    const m = HT.buildModel(old, null);
    const flagged = m.periods.flatMap(p => HT.CELL_KINDS.filter(K => !K.items).flatMap(K => HT.cellsOf(p, K)).concat(p.hosts || [])).filter(c => c.startUnknown || c.endUnknown || c.startAuto || c.endAuto || c.endYAuto);
    if (flagged.length) bad(`옛 자료의 칸 ${flagged.length}개에 미정 · 짐작 표시가 생김`);
  }
  const sp = packs.find(p => p.id === 'lantern-chronicle');
  if (sp && !HT.usesCellUnknown(sp)) bad('칸의 미정을 쓴 견본(lantern-chronicle)을 칸의 미정을 쓴 팩으로 보지 않음');
}

/* ⑧ 조약: 사건의 treaty 규격 읽기(서명자 글 ↔ 목록이 같은 값 · 한국어 종류/끝난 까닭/조항 분류 · 글로 적은 조항 · "트랙:이름" 당사국 · 비준/발효 날짜 글) ·
   다시 읽어도 같음 · 모르는 값은 경고 · 빈 규격은 없음 · 패치(통째 교체 · 다시 정규화 · null이면 뗌) · 형식 버전 2 ·
   모델(itemKind 'treaty' · 당사국이 함께 겪은 자리에 · 제 자리는 제 트랙의 당사국 · 끝낸 전쟁 · 대체 관계 · 원래 treaty는 그대로 · 모델 전용 칸이 파일에 섞이지 않음) ·
   조항 한꺼번에 붙여넣기 · 내 수정으로 조약을 떼고 얹기 · 옛 자료에는 조약이 하나도 생기지 않음 */
{
  const bad = msg => out.problems.push(`조약: ${msg}`);
  const warns = [];
  const T = raw => HT.readTreaty(raw, m => warns.push(m));
  const a = T({ type: '강화', endReason: '폐기', parties: [{ polity: '갑 나라', side: '1', signatories: '가나(재상); 다라' }, 'tb:을 나라'], articles: ['제1조 (경계) 시내를 경계로 한다.', { no: '제2조', tag: '배상', text: '곡식을 보낸다.' }], ratified: '902-09-01', languages: '갑말, 을말' });
  const b = T({ type: 'peace', endReason: 'abrogated', parties: [{ polity: '갑 나라', side: 1, signatories: [{ name: '가나', title: '재상' }, { name: '다라' }] }, { track: 'tb', polity: '을 나라' }], articles: [{ no: '제1조', title: '경계', text: '시내를 경계로 한다.' }, { no: '제2조', tag: 'indemnity', text: '곡식을 보낸다.' }], ratified: 902.6657534246575, ratifiedAt: '902-09-01', languages: ['갑말', '을말'] });
  if (canon(a) !== canon(b)) bad(`글로 적은 꼴(서명자 글 · 한국어 낱말 · 글 조항 · "트랙:이름")과 목록 꼴이 같은 값이 되지 않음\n   ${canon(a)}\n   ${canon(b)}`);
  if (canon(T(a)) !== canon(a)) bad('정리한 조약 규격을 다시 읽으면 달라짐');
  if (warns.length) bad(`바른 조약 규격에 경고가 뜸: ${warns.join(' / ')}`);
  if (T({}) !== null || T({ parties: [], articles: [] }) !== null || T(null) !== null) bad('빈 조약 규격이 없는 것(null)으로 읽히지 않음');
  warns.length = 0;
  const c = T({ type: '모르는종류', endReason: '모름', parties: [{ role: '주인 없는 역할' }, { polity: '병 나라', side: '갑' }], articles: [{ tag: '없는분류', text: '본문' }] });
  if (warns.length !== 5 || (c && (c.type || c.endReason || c.parties.length !== 1 || c.parties[0].side || c.articles[0].tag))) bad(`모르는 값이 빠지며 경고가 뜨지 않음 (${warns.length}건)`);
  const arts = HT.splitArticles('앞글\n제1조(목적) 가\n나\n제 2 관 다\nArticle 3. 라');
  if (canon(arts) !== canon([{ no: '', title: '', text: '앞글' }, { no: '제1조', title: '목적', text: '가\n나' }, { no: '제2관', title: '', text: '다' }, { no: 'Article 3', title: '', text: '라' }])) bad(`조항 한꺼번에 붙여넣기가 조항 번호로 나누지 못함 (${canon(arts)})`);
  if (HT.signersText(HT.readSigners('가나(재상); 다라')) !== '가나(재상); 다라') bad('서명자 글 ↔ 목록이 왕복하지 않음');
  if (!HT.PATCHABLE.includes('treaty')) bad('패치할 수 있는 칸에 treaty가 없음');
  if (!HT.FORMS.treaty || HT.FORMS.treaty.list !== 'events' || HT.ITEM_WORDS.treaty !== '조약') bad('조약 폼(HT.FORMS.treaty — 목록 events) · 부르는 말(ITEM_WORDS.treaty)이 없음');
  /* 파일 · 패치 · 모델 */
  const r = HT.normalizePack({
    format: 'history-timeline-dlc', formatVersion: 2, id: 'smoke-treaty', name: '검사',
    tracks: [{ id: 'ta', name: '가 땅' }, { id: 'tb', name: '나 땅' }],
    periods: [{ id: 'big', track: 'ta', name: '큰 나라', start: 800, end: 1000 }, { id: 'small', track: 'ta', name: '작은 나라', start: 850, end: 950 }, { id: 'nb', track: 'tb', name: '나 나라', start: 700, end: 1100 }],
    events: [
      { id: 'war', track: 'ta', title: '검사 전쟁', start: 870, end: 874, polity: '큰 나라' },
      { id: 'tr1', track: 'ta', title: '첫 약조', start: 874, end: 900, treaty: { parties: [{ polity: '큰 나라', side: 1 }, { track: 'tb', side: 2 }], concludes: '검사 전쟁' } },
      { id: 'tr2', track: 'tb', title: '둘째 약조', start: 900, treaty: { parties: ['나 땅', '큰 나라', { polity: '없는 나라' }], supersedes: 'tr1', effective: 901 } },
    ],
    patches: [{ target: '다른팩/어느사건', set: { treaty: { type: '동맹', parties: '갑 나라' } } }, { target: '다른팩/딴사건', set: { treaty: null } }],
  });
  if (!r.pack) bad(`검사 팩을 읽지 못함 — ${r.errors.map(e => e.msg).join(' / ')}`);
  else {
    const ps = r.pack.patches;
    if (!(ps[0].set.treaty && ps[0].set.treaty.type === 'alliance' && ps[0].set.treaty.parties[0].polity === '갑 나라')) bad('패치의 조약 규격이 다시 정규화되지 않음');
    if (!('treaty' in ps[1].set) || ps[1].set.treaty !== null) bad('조약을 떼는 패치(treaty: null)가 남지 않음');
    const json = HT.packToJSON(r.pack);
    if (json.formatVersion !== 2) bad('조약을 쓴 파일이 형식 버전 2로 나가지 않음');
    if (/treatyRefs|treatyBackRefs|itemKind/.test(JSON.stringify(json))) bad('모델 전용 칸이 팩에 섞임');
    const only = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id: 'smoke-treaty-off', name: '검사', patches: [{ target: '다른팩/딴사건', set: { treaty: null } }] });
    /* 떼는 패치(treaty: null)도 2 — 옛 앱은 treaty를 "패치할 수 없는 칸"으로 버려 그 패치를 "바꿀 내용이 없습니다"로 건너뛰므로, 새 형식 안내가 뜨게 */
    if (!only.pack || HT.packToJSON(only.pack).formatVersion !== 2) bad('조약을 떼기만 하는 패치가 형식 버전 2로 나가지 않음');
    const before = canon(r.pack.events);
    const m = HT.buildModel([r.pack], null);
    if (canon(r.pack.events) !== before) bad('모델을 만들면서 원래 팩의 사건(treaty)이 바뀜');
    const E = id => m.byUid.get(`smoke-treaty/${id}`);
    if (E('war').itemKind !== 'event' || E('tr1').itemKind !== 'treaty' || HT.itemWord(E('tr1')) !== '조약') bad('treaty 칸이 있는 사건만 조약(itemKind treaty)이 되지 않음');
    const pl = e => e.placements.map(p => `${p.track}/${p.polityName}`).join(' | ');
    if (pl(E('tr1')) !== 'ta/큰 나라 | tb/나 나라') bad(`조약의 자리가 제 트랙의 당사국 + 다른 당사국이 아님 (${pl(E('tr1'))}) — 해로 짐작하면 더 짧은 작은 나라에 놓임`);
    if (pl(E('tr2')) !== 'tb/나 나라 | ta/큰 나라') bad(`트랙 이름 · 모든 트랙에서 찾은 당사국이 자리에 들지 않음 (${pl(E('tr2'))})`);
    const refs = E('tr2').treatyRefs;
    if (!refs || refs.parties.length !== 3 || refs.parties[2].uid !== null || refs.parties[2].name !== '없는 나라') bad('찾지 못한 당사국이 이름만으로 남지 않음');
    if (E('tr1').treatyRefs.concludes !== 'smoke-treaty/war' || !(E('war').treatyBackRefs && E('war').treatyBackRefs.concludedBy[0] === 'smoke-treaty/tr1')) bad('끝낸 전쟁 ↔ 끝낸 조약이 이어지지 않음');
    if (E('tr2').treatyRefs.supersedes !== 'smoke-treaty/tr1' || E('tr1').treatyBackRefs.supersededBy[0] !== 'smoke-treaty/tr2') bad('대체한 조약 ↔ 대체된 조약이 이어지지 않음');
    /* 내 수정: DLC 조약의 규격을 떼면(null) 보통 사건, 내 사건에 규격을 얹으면 조약 */
    const user = HT.blankUser();
    user.overrides['smoke-treaty/tr1'] = { treaty: null };
    user.events.push({ id: 'u1', track: 'ta', title: '내 약조', start: 880, treaty: HT.readTreaty({ parties: ['tb:나 나라'] }) });
    const m2 = HT.buildModel([r.pack], user);
    if (m2.byUid.get('smoke-treaty/tr1').itemKind !== 'event' || m2.byUid.get('smoke-treaty/tr1').treatyRefs) bad('내 수정으로 뗀 조약이 보통 사건으로 돌아가지 않음');
    if (m2.byUid.get('user/u1').itemKind !== 'treaty' || !m2.byUid.get('user/u1').placements.some(p => p.track === 'tb')) bad('내 사건에 얹은 조약 규격이 조약 · 당사국 자리가 되지 않음');
  }
  /* 폼의 한 칸 글로는 되살릴 수 없는 서명자 · 언어(괄호가 든 이름 · 괄호가 든 직함 · ';'이 든 이름 · 쉼표가 든 언어):
     목록 → 폼 글(당사국 줄의 value · data-list) → 목록이 그대로여야 하고(열어서 그대로 저장하면 고친 것이 아님), 사람이 고친 글은 다시 나눔 */
  {
    const unesc = s => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
    const signers = [{ name: '가나(별명)' }, { name: '다', title: '대신(겸직)' }, { name: '라; 마' }, { name: '바 "사"', title: '<아>' }];
    const row = HT.treatyPartyRowHTML([], { polity: '갑 나라', signatories: signers });
    const input = (row.match(/<input class="p-sign"[^>]*>/) || [''])[0];
    const attr = n => unesc((input.match(new RegExp(` ${n}="([^"]*)"`)) || [, ''])[1]);
    const back = HT.readSigners(HT.keepListText(attr('value'), attr('data-list'), HT.signersText));
    if (canon(back) !== canon(signers)) bad(`괄호 · ';'이 든 서명자가 폼 글을 거치며 바뀜\n   ${canon(signers)}\n   ${canon(back)}`);
    if (canon(HT.readSigners(HT.keepListText('자(차)', attr('data-list'), HT.signersText))) !== canon([{ name: '자', title: '차' }])) bad('고친 서명자 글을 다시 나누지 않음');
    const langs = ['갑말, 을말', '병말'];
    if (canon(HT.readTreaty({ languages: HT.keepListText(langs.join(', '), JSON.stringify(langs), l => l.join(', ')) }).languages) !== canon(langs)) bad('쉼표가 든 언어가 폼 글을 거치며 쪼개짐');
    if (canon(HT.readTreaty({ languages: HT.keepListText('갑말, 정말', JSON.stringify(langs), l => l.join(', ')) }).languages) !== canon(['갑말', '정말'])) bad('고친 언어 글을 다시 나누지 않음');
  }
  /* 조약 규격은 사건에만: 시대를 가리킨 패치 · 내 수정의 treaty는 모델에서 버리고(상세의 조약 배지 · 날짜 표 · 고침 상자에 나오지 않게), 사건에는 그대로 */
  {
    const base = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id: 'smoke-tr-base', name: '검사', tracks: [{ id: 'ta', name: '가 땅' }], periods: [{ id: 'pa', track: 'ta', name: '가 나라', start: 800, end: 900 }, { id: 'pb', track: 'ta', name: '나 나라', start: 900, end: 1000 }], events: [{ id: 'ea', track: 'ta', title: '검사 사건', start: 850 }] }).pack;
    const pt = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 2, id: 'smoke-tr-patch', name: '검사', patches: [{ target: 'smoke-tr-base/pa', set: { treaty: { type: '동맹' } } }, { target: 'smoke-tr-base/pb', set: { treaty: { type: '동맹' }, note: '메모' } }, { target: 'smoke-tr-base/ea', set: { treaty: { type: '동맹' } } }] }).pack;
    const user = HT.blankUser();
    user.overrides['smoke-tr-base/pb'] = { treaty: { type: 'peace' } };
    const m = HT.buildModel([base, pt], user);
    const pa = m.byUid.get('smoke-tr-base/pa');
    const pb = m.byUid.get('smoke-tr-base/pb');
    if ('treaty' in pa || 'treaty' in pb) bad('시대를 가리킨 패치 · 내 수정의 조약 규격이 모델의 시대에 남음');
    if (pa.patchedBy && pa.patchedBy.length) bad('조약 규격만 담은 패치가 시대에 빈 고침 상자를 만듦');
    if (!pb.patchedBy || pb.patchedBy.length !== 1 || 'treaty' in pb.patchedBy[0].before || pb.note !== '메모') bad('조약 규격과 다른 칸을 함께 담은 패치에서 시대의 다른 칸이 적용되지 않거나 고침 상자에 조약 규격이 남음');
    if (m.byUid.get('smoke-tr-base/ea').itemKind !== 'treaty') bad('사건을 가리킨 조약 패치가 조약이 되지 않음');
  }
  /* 옛 자료(조약 이전의 견본 · 기본팩): 조약이 하나도 생기지 않아야 함 */
  const old = packs.filter(p => !(p.events || []).some(e => e.treaty) && !(p.patches || []).some(x => x.set && 'treaty' in x.set));
  if (old.length && HT.buildModel(old, null).events.some(e => e.itemKind === 'treaty' || e.treatyRefs)) bad('옛 자료의 사건이 조약이 됨');
  const sp = packs.find(p => p.id === 'lantern-chronicle');
  if (sp) {
    const m = HT.buildModel([sp], null);
    const E = id => m.byUid.get(`lantern-chronicle/${id}`) || {};
    if (m.events.filter(e => e.itemKind === 'treaty').length !== 12) bad(`견본(lantern-chronicle)의 조약 12건이 조약(itemKind treaty)이 되지 않음 (${m.events.filter(e => e.itemKind === 'treaty').length})`);
    // 견본 2.0.0: 호반성 항복 문서는 더는 전쟁을 끝내지 않음 — 끝낸 전쟁은 유리항 개항 조약 → 해협 렌즈 전쟁, 대체는 대륙 기본 조약 → 연합 조약
    const sur = m.events.find(e => e.title === '유리항 개항 조약') || {};
    if (!sur.treatyRefs || sur.treatyRefs.concludes !== 'lantern-chronicle/e-lens-war-1176' || !((E('e-lens-war-1176').treatyBackRefs || {}).concludedBy || []).includes(sur.uid)) bad('견본의 끝낸 전쟁 ↔ 끝낸 조약(유리항 개항 조약 → 해협 렌즈 전쟁)이 이어지지 않음');
    const uni = m.events.find(e => e.title === '자유 등불 대륙 평화·공공 등대망 기본 조약') || {};
    if (!uni.treatyRefs || uni.treatyRefs.supersedes !== 'lantern-chronicle/e-tr-1402' || !((E('e-tr-1402').treatyBackRefs || {}).supersededBy || []).includes(uni.uid)) bad('견본의 대체한 조약 ↔ 대체된 조약(대륙 기본 조약 → 연합 조약)이 이어지지 않음');
  }
}

/* ⑨ 바탕 표: 날짜 칸 목록 · 내 데이터 목록 · 폼 표 · 형식 버전이 서로 맞는지 */
{
  const bad = msg => out.problems.push(`바탕 표: ${msg}`);
  for (const k of HT.DATE_KEYS) for (const n of [k, `${k}At`]) if (!HT.PATCHABLE.includes(n)) bad(`날짜 칸 "${n}"이(가) 패치할 수 있는 칸 목록에 없음`);
  for (const { list, kind } of HT.USER_LISTS) {
    const F = HT.FORMS[kind];
    if (!F || F.list !== list) bad(`내 데이터 목록 "${list}"과(와) 폼 "${kind}"이(가) 맞지 않음`);
    else if (!F.nameKey || typeof F.fresh !== 'function' || typeof F.filterKeys !== 'function') bad(`폼 "${kind}"에 nameKey · fresh · filterKeys 가운데 빠진 것이 있음`);
    if (!Array.isArray(HT.blankUser()[list])) bad(`빈 내 데이터에 "${list}" 목록이 없음`);
  }
  /* 내 항목을 목록마다 하나씩 넣으면 모델에 그 수만큼 늘어야 함 (목록 하나가 통째로 빠지는 일을 잡음) */
  if (model) {
    const track = model.tracks[0].id;
    const user = HT.blankUser();
    for (const { list, kind } of HT.USER_LISTS) {
      const x = Object.assign(HT.FORMS[kind].fresh({ track, start: 1000 }), { id: `smoke-${kind}`, [HT.FORMS[kind].nameKey]: `검사 ${kind}` });
      user[list].push(x);
    }
    const m2 = HT.buildModel(packs, user);
    let added = m2.periods.length + m2.events.length - model.periods.length - model.events.length;
    added += (m2.figures || []).length - (model.figures || []).length; // 인물은 시대 · 사건 밖의 목록(model.figures)
    if (added !== HT.USER_LISTS.length) bad(`내 항목 ${HT.USER_LISTS.length}개를 넣었는데 모델에는 ${added}개만 늘어남`);
    for (const { kind } of HT.USER_LISTS) if (!m2.byUid.has(`user/smoke-${kind}`)) bad(`내 ${kind} 항목이 모델에 없음`);
  }
  /* 형식 버전: 새 열쇠를 쓰지 않은 파일은 1, 새 열쇠 목록에 든 칸을 쓰면 2 — 읽는 버전까지는 경고가 없고, 그보다 새 파일에는 경고가 떠야 함.
     읽는 버전은 새 열쇠를 읽기 시작한 뒤에만 2: 목록이 빈 채로 2이면 이 프로그램이 2인 파일을 경고 없이 열어 새 칸을 조용히 버리고,
     목록이 찼는데 1이면 이 프로그램이 만든 파일을 이 프로그램이 열 때 경고가 뜹니다 */
  /* 형식 3: 버전 3의 목록(HT.NEW_FORMAT_KEYS_V3)이 차 있으면 읽는 버전은 3 — 비었는데 3이거나 찼는데 3이 아니면 문제 */
  const v3Keys = (HT.NEW_FORMAT_KEYS_V3 || []).length;
  if (HT.FORMAT_VERSION !== (v3Keys ? HT.FORMAT_VERSION_V3 : HT.NEW_FORMAT_KEYS.length ? HT.FORMAT_VERSION_NEW : HT.FORMAT_VERSION_OLD))
    bad(`읽는 형식 버전이 ${HT.FORMAT_VERSION}인데 새 열쇠 목록은 ${HT.NEW_FORMAT_KEYS.length}개 · 버전 3의 목록은 ${v3Keys}개 — 새 열쇠를 처음 읽는 단계에서만 올림`);
  /* 형식 버전의 짜임은 하나 — 버전 2의 열쇠는 HT.NEW_FORMAT_KEYS(길 글 · 함수), 버전 3의 열쇠는 HT.NEW_FORMAT_KEYS_V3. 한때 갈래마다 따로 둔 { v, key } 줄 꼴이 다시 들어오면 잡음 */
  if (HT.NEW_FORMAT_KEYS.some(k => k && typeof k === 'object')) bad('새 열쇠 목록(HT.NEW_FORMAT_KEYS)에 { v, key } 줄이 있음 — 버전 3의 열쇠는 HT.NEW_FORMAT_KEYS_V3에 적음');
  if (typeof HT.formatVersionOf !== 'function' || 'FORMAT_VERSION_3' in HT) bad('형식 버전 도우미가 하나로 맞춰지지 않음 (HT.formatVersionOf · HT.FORMAT_VERSION_V3)');
  const sample = packs.find(p => p.periods.length && p.events.length);
  if (sample) {
    const keep = HT.NEW_FORMAT_KEYS.slice();
    const keep3 = HT.NEW_FORMAT_KEYS_V3.slice(); // 기본팩이 형식 3의 문화권(spheres)을 쓰므로(2026-10-23) 버전 2 검사 동안은 버전 3 열쇠를 비움
    const ver = keys => {
      HT.NEW_FORMAT_KEYS.splice(0, Infinity, ...keys);
      HT.NEW_FORMAT_KEYS_V3.splice(0, Infinity);
      const v = HT.packToJSON(sample).formatVersion;
      HT.NEW_FORMAT_KEYS.splice(0, Infinity, ...keep);
      HT.NEW_FORMAT_KEYS_V3.splice(0, Infinity, ...keep3);
      return v;
    };
    if (!HT.usesNewFormat(sample) && ver(keep) !== 1) bad('새 열쇠를 쓰지 않은 파일이 formatVersion 1로 나가지 않음');
    if (ver(['periods[]']) !== 2) bad("새 열쇠 'periods[]'(목록에 항목이 있음)를 쓴 파일이 2로 나가지 않음");
    if (ver(['periods[].name']) !== 2) bad("새 칸 'periods[].name'을 쓴 파일이 2로 나가지 않음");
    if (ver(['periods[].없는칸', '없는목록[]', 'periods[].name.안쪽']) !== 1) bad('쓰지 않은 열쇠인데 2로 나감');
    if (ver([p => p.events.length > 0]) !== 2) bad('함수로 적은 새 형식 검사가 통하지 않음');
    const again = HT.normalizePack(Object.assign(HT.packToJSON(sample), { formatVersion: HT.FORMAT_VERSION }));
    if (again.warnings.some(w => /새로운 형식/.test(w.msg))) bad(`formatVersion ${HT.FORMAT_VERSION}인 파일을 읽을 때 "더 새로운 형식" 경고가 뜸`);
    /* 읽는 형식의 다음 판 — 형식 4는 내려 읽으므로(리메이크 1a · HT.F4) 미래 판은 5부터 */
    const newer = HT.normalizePack(Object.assign(HT.packToJSON(sample), { formatVersion: HT.F4.VERSION + 1 }));
    if (!newer.warnings.some(w => /새로운 형식/.test(w.msg))) bad(`더 새로운 형식(${HT.F4.VERSION + 1})의 파일인데 경고가 없음`);
  }
}

/* ⑩ 메이커의 작업본 계산(HT.draft — 순수 함수라 여기서 그대로 돕니다): 새 항목 → 제 항목 고침 → 기본팩 항목 고침이 패치로 → 원래 값으로 되돌리면 패치가 사라짐
   → 숨김 → 문서 → 쓰인 트랙 · 민족 싣기 → 판 올림 → 검사 통과 → 고친 것 세기, 그리고 옛 "내 수정"(덧씌움)의 이사 */
if (model) {
  const bad = msg => out.problems.push(`작업본: ${msg}`);
  const D = HT.draft;
  const base = packs.filter(p => p.id === 'east-asia-base');
  const baseModel = HT.buildModel(base, null);
  /* 폼이 내놓는 꼴 흉내 (HT.readPeriodForm · HT.readEventForm — 비운 칸은 undefined, 목록은 빈 배열, 색은 "따로 지정"을 껐으면 undefined) */
  const periodForm = (p, over) => Object.assign({ name: p.name, start: p.start, startAt: HT.atOf(p, 'start') || null, end: p.end ?? null, endAt: HT.atOf(p, 'end') || null, ongoing: !!p.ongoing, startUnknown: p.startUnknown || undefined, endUnknown: p.endUnknown || undefined, track: p.track, kind: p.polityKind === 'state' ? undefined : p.polityKind, partOf: p.partOf, color: p.colorAuto ? undefined : p.color, description: p.description || '', legendary: undefined, reigns: undefined, leaders: (p.leaders || []).map(c => { const { dynastyAuto, ...rest } = c; return rest; }), cabinets: p.cabinets || [], people: p.people || '', succeeds: p.succeeds || [], eras: p.eras || [], capitals: (p.capitals || []).map(c => HT.normalizeCapital(c)), wiki: undefined, certainty: p.certainty, debate: p.debate || '', startRange: p.startRange || null, endRange: p.endRange || null, startRangeAt: null, endRangeAt: null, alternatives: p.alternatives || [] }, over);
  const eventForm = (e, over) => Object.assign({ title: e.title, start: e.start, startAt: HT.atOf(e, 'start') || null, end: e.end ?? null, endAt: HT.atOf(e, 'end') || null, ongoing: !!e.ongoing, startUnknown: undefined, endUnknown: undefined, track: e.track, category: e.category === 'etc' ? '' : e.category, importance: e.importance || 2, date: e.date || '', description: e.description || '', tags: e.tags || [], source: e.source || '', parent: e.parent || '', polities: e.polities || [], tracks: e.tracks || [], perspectives: e.perspectives || [], wiki: undefined, certainty: e.certainty, debate: e.debate || '', startRange: e.startRange || null, endRange: e.endRange || null, startRangeAt: null, endRangeAt: null, alternatives: e.alternatives || [] }, over);
  // 나라(국가) 종류만 — 옛 '내 수정' 이사 검사가 덧씌움의 kind를 비워(null) '종류는 고치지 않음'으로 쓰므로. 지도자 줄이 긴 첫 띠가 국가가 아닐 수 있음(실권 정권 · 단체 — 기본팩 자료에 따라)
  const per = baseModel.periods.find(p => p.itemKind === 'period' && p.polityKind === 'state' && (p.leaders || []).length > 3 && p.description && p.people);
  const ev = baseModel.events.find(e => e.description);
  const ev2 = baseModel.events.find(e => e !== ev);
  const draft = D.blank({ id: 'smoke-dlc', name: '검사 DLC' });
  const modelOf = d => HT.buildModel(base.concat([HT.normalizePack(d).pack]), null);
  try {
    /* 새 항목: uid는 처음부터 "<DLC id>/<항목 id>" · 쓰인 트랙 · 민족은 작업본 목록에 실림 */
    const pid = D.addItem(draft, 'period', periodForm({ name: '검사 시대', start: 100, end: 200, track: per.track, polityKind: 'state', people: per.people, certainty: 'accepted', colorAuto: true }, { wiki: '시대 본문' }));
    const eid = D.addItem(draft, 'event', eventForm({ title: '검사 사건', start: 150, track: per.track, category: 'war', importance: 3, certainty: 'accepted' }));
    D.ensureRefs(draft, baseModel);
    if (!draft.tracks.some(t => t.id === per.track)) bad('새 항목의 트랙이 작업본의 트랙 목록에 실리지 않음');
    if (!draft.peoples.some(p => p.name === per.people || p.id === per.people)) bad('새 시대의 민족이 작업본의 민족 목록에 실리지 않음');
    if ('wiki' in draft.periods[0] || 'end' in draft.events[0] || 'tags' in draft.events[0]) bad('제 항목에 빈 칸이나 본문(wiki)이 그대로 남음');
    let m = modelOf(draft);
    if (!m.byUid.has(`smoke-dlc/${pid}`) || !m.byUid.has(`smoke-dlc/${eid}`)) bad('새 항목이 모델에 "<DLC id>/<항목 id>"로 들어가지 않음');
    /* 제 항목 고침: 그 자리에서 · 폼에 없는 칸(polity)은 그대로 · 비운 칸은 지워짐 */
    draft.events[0].polity = '검사 시대';
    D.updateOwn(draft, eid, eventForm(m.byUid.get(`smoke-dlc/${eid}`), { title: '고친 검사 사건', description: '', end: 160 }), m.byUid.get(`smoke-dlc/${eid}`));
    const own = draft.events[0];
    if (own.title !== '고친 검사 사건' || own.end !== 160 || own.polity !== '검사 시대' || 'description' in own || draft.patches.length) bad(`제 항목 고침이 그 자리에서 되지 않음: ${JSON.stringify(own)}`);
    if (D.updateOwn(draft, 'no-such-id', {}) !== false) bad('없는 제 항목을 고쳤다고 함');
    /* 열어서 그대로 저장해도 자료가 달라지지 않음: 폼은 확실성을 늘 내놓고(기본값은 적지 않음) 색을 파스텔로 맞춰 내놓음(적힌 색 그대로 둠) — 남의 항목에서도 패치가 생기지 않음 */
    draft.periods[0].color = '#b3362f';
    D.updateOwn(draft, pid, { color: HT.pastel('#b3362f'), certainty: 'accepted', legendary: undefined });
    if (draft.periods[0].color !== '#b3362f' || 'certainty' in draft.periods[0]) bad(`그대로 저장했는데 색이나 확실성이 바뀜: ${JSON.stringify(draft.periods[0])}`);
    D.updateOwn(draft, pid, { color: '#9dbea8', certainty: 'legend' });
    if (draft.periods[0].color !== '#9dbea8' || draft.periods[0].certainty !== 'legend') bad('색 · 확실성을 고쳤는데 적히지 않음');
    D.updateOwn(draft, pid, { color: undefined, certainty: 'accepted' });
    const fake = { uid: 'other/x', color: '#c78d8a', polityKind: 'culture', successors: [{ to: { name: '어느 나라' } }], certainty: 'accepted' };
    if (D.patchForeign(draft, fake, { color: HT.pastel('#c78d8a'), successors: ['어느 나라'], certainty: 'accepted' })) bad(`손대지 않은 색 · 승계한 국가가 패치로 잡힘: ${JSON.stringify(draft.patches)}`);
    /* 남의 항목(기본팩) 고침: 바뀐 칸만 패치로 — 지도자 · 도읍 · 색 · 분류처럼 손대지 않은 칸은 담기지 않음 */
    D.patchForeign(draft, per, periodForm(per, { description: '패치로 고친 설명' }));
    const keys = Object.keys((draft.patches[0] || {}).set || {});
    if (draft.patches.length !== 1 || draft.patches[0].target !== per.uid || keys.join() !== 'description') bad(`기본팩 시대의 설명만 고쳤는데 패치의 칸이 [${keys}]`);
    D.patchForeign(draft, ev, eventForm(ev, { title: '패치로 고친 제목', end: ev.start + 1 }));
    const evSet = (draft.patches.find(p => p.target === ev.uid) || {}).set || {};
    if (evSet.title !== '패치로 고친 제목' || evSet.end !== ev.start + 1 || !('endAt' in evSet) || 'category' in evSet || 'description' in evSet) bad(`기본팩 사건의 패치가 어긋남: ${JSON.stringify(evSet)}`);
    m = modelOf(draft);
    if (m.byUid.get(per.uid).description !== '패치로 고친 설명' || !(m.byUid.get(per.uid).patchedBy || []).some(p => p.id === 'smoke-dlc')) bad('패치가 모델에 적용되지 않음');
    /* 다시 고치면 그 대상의 패치를 통째로 갈아 쓰고(손으로 적은 메모와 폼에 없는 칸은 이어받음), 원래 값으로 되돌리면 패치가 사라짐 */
    Object.assign(draft.patches.find(p => p.target === ev.uid), { note: '손으로 적은 메모' }).set.polity = '어느 정권';
    D.patchForeign(draft, ev, eventForm(ev, { title: '다시 고친 제목' }));
    const again = draft.patches.filter(p => p.target === ev.uid);
    if (again.length !== 1 || again[0].set.title !== '다시 고친 제목' || 'end' in again[0].set || again[0].set.polity !== '어느 정권' || again[0].note !== '손으로 적은 메모') bad(`패치를 통째로 갈아 쓰지 않음: ${JSON.stringify(again)}`);
    delete again[0].set.polity;
    D.patchForeign(draft, ev, eventForm(ev));
    D.patchForeign(draft, per, periodForm(per));
    if (draft.patches.length) bad(`원래 값으로 되돌렸는데 패치가 남음: ${JSON.stringify(draft.patches)}`);
    /* 숨김 · 풀기 */
    D.patchForeign(draft, ev2, eventForm(ev2, { title: '숨기기 전에 고침' }));
    D.hideForeign(draft, ev2.uid);
    if (draft.patches.length !== 1 || !draft.patches[0].hide || draft.patches[0].set) bad('숨김이 그 대상의 패치 하나(hide)로 바뀌지 않음');
    if (modelOf(draft).byUid.has(ev2.uid)) bad('숨긴 항목이 모델에 남음');
    D.unhide(draft, ev2.uid);
    if (draft.patches.length || !modelOf(draft).byUid.has(ev2.uid)) bad('숨김을 풀어도 돌아오지 않음');
    /* 문서: 제 항목은 상대 키 · 남의 항목과 하위 문서는 절대 키 · 빈 글이면 지움 · 제 항목을 지우면 문서도 함께 */
    D.setDoc(draft, `smoke-dlc/${pid}`, '시대 문서');
    D.setDoc(draft, `smoke-dlc/${pid}//역사`, '하위 문서');
    D.setDoc(draft, per.uid, '남의 항목 문서');
    D.setDoc(draft, `people:${baseModel.peoples[0].id}`, '민족 문서');
    if (draft.documents[pid] !== '시대 문서' || draft.documents[`${pid}//역사`] !== '하위 문서' || draft.documents[per.uid] !== '남의 항목 문서') bad(`문서 키가 어긋남: ${Object.keys(draft.documents)}`);
    m = modelOf(draft);
    if ((m.docs.get(`smoke-dlc/${pid}`) || {}).text !== '시대 문서' || (m.docs.get(per.uid) || {}).text !== '남의 항목 문서') bad('문서가 모델의 문서 색인에 들어가지 않음');
    D.setDoc(draft, per.uid, '  ');
    if (per.uid in draft.documents) bad('빈 글로 저장했는데 문서가 남음');
    /* 판 올림 · 검사 · 왕복 */
    if (D.bumpVersion('1.0.3') !== '1.0.4' || D.bumpVersion('2.1') !== '2.1.1' || D.bumpVersion('') !== '1.0.1' || D.bumpVersion('1.0.9') !== '1.0.10') bad('판 올림이 어긋남');
    if (D.newerVersion('1.0.3', '1.0.12') !== '1.0.12' || D.newerVersion('2.0.0', '1.9.9') !== '2.0.0' || D.newerVersion('1.0.0', '') !== '1.0.0' || D.newerVersion('베타', '1.0.0') !== '베타') bad('판 견주기가 어긋남');
    const r = HT.normalizePack(draft);
    if (!r.pack || r.errors.length) bad(`작업본이 검사를 통과하지 못함: ${r.errors.map(e => e.msg).join(' / ')}`);
    else {
      const json = HT.packToJSON(r.pack);
      const back = D.clean(JSON.parse(JSON.stringify(json)));
      if (canon(HT.packToJSON(HT.normalizePack(back).pack)) !== canon(json)) bad('반영한 DLC를 다시 작업본으로 열면 자료가 달라짐');
      /* 고친 것: 설치본이 없으면 든 것이 모두 고침 · 같은 내용이면 0 (판 번호는 보지 않음) · 하나 고치면 1 */
      if (!D.isDirty(draft, null) || D.isDirty(draft, Object.assign({}, json, { version: '9.9.9' }))) bad('고친 것 세기가 어긋남 (설치본 없음 / 같은 내용)');
      D.updateOwn(draft, eid, { description: '하나 더 고침' });
      const ch = D.changes(HT.normalizePack(draft).pack, HT.normalizePack(json).pack);
      if (ch.length !== 1 || ch[0].type !== 'edit' || ch[0].list !== 'events') bad(`하나 고쳤는데 고친 것이 ${JSON.stringify(ch)}`);
      if (D.changes(null, null)[0].type !== 'error') bad('검사를 통과하지 못한 작업본이 고친 것으로 잡히지 않음');
    }
    D.removeOwn(draft, pid);
    if (draft.periods.length || pid in draft.documents || `${pid}//역사` in draft.documents) bad('제 항목을 지웠는데 항목이나 그 문서가 남음');
    /* id 없는 옛 꼴의 파일: 작업본으로 열면 정규화가 매길 id와 같은 id를 받고, 옛 꼴의 시대(kind: overlay)는 기관 목록으로 */
    const rawNoId = { format: HT.FORMAT, id: 'smoke-noid', name: 'id 없는 DLC', tracks: [{ id: 't1', name: '트랙' }], periods: [{ track: 't1', name: '가', start: 1, end: 5 }, { track: 't1', name: '나', start: 2, end: 3, kind: 'overlay', partOf: '가' }], events: [{ track: 't1', title: '다', start: '기원전 3' }, { track: 't1', title: '다', start: '기원전 3' }] };
    const want = HT.normalizePack(rawNoId).pack;
    const cleaned = D.clean(rawNoId);
    const ids = l => l.map(x => x.id).join();
    if (ids(cleaned.periods) !== ids(want.periods) || ids(cleaned.organs) !== ids(want.organs) || ids(cleaned.events) !== ids(want.events)) bad(`id 없는 항목의 id가 정규화와 다름: ${ids(cleaned.periods)}|${ids(cleaned.organs)}|${ids(cleaned.events)} ↔ ${ids(want.periods)}|${ids(want.organs)}|${ids(want.events)}`);

    /* 옛 "내 수정"(덧씌움)의 이사: 옛 뷰어의 "수정 내용을 DLC로"와 같은 DLC (바뀐 칸만 패치 · 숨김 · 상대 키 문서 · 쓰인 트랙 · 민족) → 설치 · 켬 · 원본은 남기고 비움 */
    const track = per.track;
    const user = Object.assign(HT.blankUser(), {
      periods: [{ id: 'u-p1', track, name: '옛 내 시대', start: 100, end: 200, people: per.people, wiki: '옛 시대 본문' }],
      events: [{ id: 'u-e1', track, title: '옛 내 사건', start: 150, startAt: '0150-03-01', category: 'war', importance: 3 }],
      organs: [{ id: 'u-g1', track, name: '옛 내 기관', start: 120, end: 130, host: '옛 내 시대' }],
      overrides: { [per.uid]: Object.assign(periodForm(per, { description: '옛 고침', color: per.color }), { startUnknown: null, endUnknown: null, kind: null, legendary: null, reigns: null, wiki: null }), 'nope/none': { title: 'x' } },
      hidden: { [ev2.uid]: true, 'nope/none2': true },
      wiki: { 'user/u-p1': '옛 시대 본문', [per.uid]: '옛 남의 항목 문서', 'user/u-e1//뒷이야기': '옛 하위 문서' },
    });
    const moved = D.fromUser(JSON.parse(JSON.stringify(user)), base, { id: 'my-edits', name: '내 수정' });
    const mp = HT.normalizePack(moved);
    /* 옛 색: 새 시대(u-p1)가 같은 트랙의 자동 색 차례를 바꾸므로, 옛 폼이 굳혀 둔 색이 옛 화면의 색으로 담깁니다 · 없는 DLC(nope)의 고침 · 숨김도 패치로 (그 DLC를 설치하면 얹힘) */
    const oldColor = HT.buildModel(base, user).byUid.get(per.uid).color;
    const expectPatches = canon([{ target: per.uid, set: { description: '옛 고침', color: oldColor } }, { target: 'nope/none', set: { title: 'x' } }, { target: ev2.uid, hide: true }, { target: 'nope/none2', hide: true }]);
    if (!mp.pack || mp.errors.length) bad(`옛 내 수정으로 만든 DLC가 검사를 통과하지 못함: ${mp.errors.map(e => e.msg).join(' / ')}`);
    else {
      if (canon(mp.pack.patches) !== expectPatches) bad(`옛 내 수정의 패치가 어긋남: ${JSON.stringify(mp.pack.patches)}`);
      if (mp.pack.periods.length !== 1 || mp.pack.events.length !== 1 || mp.pack.organs.length !== 1 || mp.pack.periods[0].wiki) bad('옛 내 수정의 항목이 그대로 옮겨지지 않음');
      if (canon(Object.keys(mp.pack.documents).sort()) !== canon(['u-p1', 'u-e1//뒷이야기', per.uid].sort())) bad(`옛 내 수정의 문서 키가 어긋남: ${Object.keys(mp.pack.documents)}`);
      if (!mp.pack.tracks.some(t => t.id === track) || !mp.pack.peoples.length) bad('옛 내 수정이 쓴 트랙 · 민족이 DLC에 실리지 않음');
    }
    store.clear();
    if (D.migrateUser() !== null) bad('옮길 것이 없는데 이사가 돎');
    store.set(HT.KEYS.user, JSON.stringify(user));
    const res = D.migrateUser();
    const inst = JSON.parse(store.get(HT.KEYS.installed) || '[]');
    if (!res || !res.ok || inst.length !== 1 || inst[0].id !== 'my-edits' || store.has(HT.KEYS.user) || canon(JSON.parse(store.get(HT.KEYS.userBackup))) !== canon(user) || !(JSON.parse(store.get(HT.KEYS.packState))['my-edits'] || {}).enabled)
      bad(`옛 내 수정의 이사가 어긋남: ${JSON.stringify(res && { ok: res.ok, message: res.message })}`);
    else if (canon(inst[0]) !== canon(HT.packToJSON(HT.normalizePack(D.fromUser(user, base, { id: 'my-edits', name: '내 수정', description: inst[0].description })).pack))) bad('이사로 설치된 DLC가 같은 규칙으로 만든 DLC와 다름');
    if (D.migrateUser() !== null) bad('이사가 두 번 돎');
    /* 이미 «내 수정»이 있으면 거기에 합침: 항목은 더하고, 같은 대상의 패치는 새것이 이김 (앞의 고침을 품은 채로), 판이 오름 */
    store.set(HT.KEYS.user, JSON.stringify(Object.assign(HT.blankUser(), { events: [{ id: 'u-e2', track, title: '둘째 이사의 사건', start: 170 }], overrides: { [per.uid]: Object.assign(periodForm(per, { description: '옛 고침', people: '', color: per.color }), { kind: null, wiki: null }) } })));
    const res2 = D.migrateUser();
    const inst2 = JSON.parse(store.get(HT.KEYS.installed) || '[]');
    const p2 = inst2[0] && (inst2[0].patches || []).find(p => p.target === per.uid);
    if (!res2 || !res2.ok || inst2.length !== 1 || inst2[0].events.length !== 2 || inst2[0].periods.length !== 1 || !p2 || p2.set.description !== '옛 고침' || !('people' in p2.set) || !(inst2[0].patches || []).some(p => p.hide) || inst2[0].version !== '1.0.1')
      bad(`둘째 이사가 «내 수정»에 합쳐지지 않음: ${JSON.stringify(inst2[0] && { v: inst2[0].version, ev: inst2[0].events.length, p2 })}`);
    /* 만들기에 실패하면 아무것도 지우지 않음 */
    store.clear();
    store.set(HT.KEYS.user, JSON.stringify(Object.assign(HT.blankUser(), { events: [{ id: 'u-bad', track, title: '', start: null }] })));
    const res3 = D.migrateUser();
    if (!res3 || res3.ok || !store.has(HT.KEYS.user) || store.has(HT.KEYS.installed) || store.has(HT.KEYS.userBackup)) bad('담기지 못한 항목이 있는데도 옛 내 수정을 지움');
    store.clear();
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* 간지 탭(js/timeline.js · css/common.css는 화면이 있어야 돌므로 글로만 읽음 — 예전 '플래그 탭'을 2026-09-22 감독 결정(묶음 3 · 1번 L)으로 바꾼 것):
   책갈피 탭이 띠 윗 테두리 두께(G.bw)만큼만 띠 밑으로 들어가는지(화면의 높이 = G.tab + G.bw · toSVG는 탭 모양을 띠보다 먼저 그리고 아랫변이 y − G.tab + 0.5 + G.tab + G.bw − 0.5 = y + G.bw),
   탭의 발이 띠의 둥근 모서리가 끝나는 곳부터(x1 + G.radius — 모서리 밑 조각 at-corner는 없음) · 뒤 장의 탭(_hostTabs)이 화면 · 그림 모두에 있는지 ·
   모양 블록이 띠보다 아래 층 · 칠은 띠와 같은 섞임(--tm) · 선은 띠 테두리(--edge) · 글자가 보이는 칸 안(10px) · 고리 위의 탭은 아래 1px를 자름 · 움직임 토큰만 쓰는지 —
   다른 가지와 합칠 때 옛 모양(필름 · 모서리 밑 · G.tab + 3 · 손으로 적은 시간)이 되살아나면 잡습니다 */
{
  const bad = msg => out.problems.push(`간지 탭: ${msg}`);
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  // 2026-10-22 메이커 미리보기 서고 2단(한 장 꼬리표): 화면의 탭은 띠 위로 솟지 않고 탭 자리(G.tab) 안의 아래 TAG.head(14px) 이름 색줄이 된다 — 줄 몫은 그대로
  // 2026-10-23 서고 3단(메이커만 — opts.seogo): 이름 색줄이 띠 안(top 0)이 되고 내보내기 쪽은 그대로 −TAG.head
  if (!/class="tl-tab[^\n]*top:\$\{seogo \? 0 : -TAG\.head\}px;[^\n]*height:\$\{TAG\.head\}px/.test(tsrc)) bad('화면의 꼬리표 이름 색줄이 탭 자리 안의 TAG.head 높이가 아님(_drawTrack — 서고 3단은 띠 안 top 0)');
  if (/height(:|=")\$\{G\.tab \+ \d+\}/.test(tsrc)) bad('책갈피 탭이 띠 안으로 깊이 들어감(높이 G.tab + n)');
  if (!/const d = tabBump\(tx, y - G\.tab \+ 0\.5, tp\.width, G\.tab \+ G\.bw - 0\.5,/.test(tsrc)) bad('그림 내보내기(toSVG)의 탭 윤곽이 띠 윗변 밑 G.bw까지가 아님');
  const svgTab = tsrc.indexOf('const tabFits = !!tp.mode;'); // 그림 내보내기의 탭 (화면과 같은 결정 tabParts — 통합 마무리 g2)
  if (svgTab < 0 || !(tsrc.indexOf('const d = tabBump(tx, ', svgTab) < tsrc.indexOf('body += bandSvg;', svgTab))) bad('그림 내보내기(toSVG)의 탭 모양이 띠보다 먼저(밑에) 그려지지 않음');
  /* 평지 맞춤(감독 답 ④ "둥근 네모 평지 시작부분부터 끝이랑 맞게"): 발은 모서리가 끝나는 곳부터, 오른쪽 평지 끝을 넘지 않음 — 화면 · 그림 · 화면 밖 줄 모두 */
  const flat = tsrc.match(/const flatL = Math\.max\(x1 \+ G\.radius, 6\);/g) || [];
  if (flat.length < 3) bad(`탭의 발이 띠의 둥근 모서리가 끝나는 곳(x1 + G.radius)부터가 아님 — 화면 · 그림 · 뒤 장 탭(${flat.length}곳)`);
  if ((tsrc.match(/Math\.min\(x2 - G\.radius, W - 6\)/g) || []).length < 3) bad('탭이 오른쪽 평지 끝(x2 − G.radius)을 넘을 수 있음 — 화면 · 화면 밖 줄 · 그림');
  if (/'at-corner'|atCorner/.test(tsrc) || /\.at-corner/.test(csrc)) bad('옛 모서리 밑 조각(at-corner)이 남음 — 간지 탭은 모서리 뒤의 평지에서 솟음');
  if (!/if \(!bird\) rows\[p\._row\] \+= this\._hostTabs\(p, X, W, x1, tabEnd, tabR\);/.test(tsrc)) bad('화면에 뒤 장의 탭(상국 탭 — _hostTabs)이 없음');
  if (!/if \(!bird\) body \+= this\._hostTabsSVG\(p, X, W, GW, x1,/.test(tsrc)) bad('그림 내보내기에 뒤 장의 탭(_hostTabsSVG)이 없음');
  const at = csrc.indexOf('/* ── 플래그 탭 ──');
  if (at < 0) bad("common.css에 '플래그 탭'(책갈피 탭의 층 · 자리) 블록이 없음");
  else {
    const next = csrc.indexOf('/* ── 실재성 ──', at);
    const block = csrc.slice(at, next < 0 ? csrc.length : next);
    if (!/\.tl-lane \.tl-tab \{[^}]*z-index: -1;/.test(block)) bad('탭이 띠보다 아래 층(z-index: -1)이 아님');
    if (!/\.tl-lane \.tl-tab \{[^}]*border: 0;[^}]*background: transparent;/.test(block)) bad('탭 상자에 테두리나 바탕이 있음(모양은 안의 svg가 그려야 함)');
    if (!/\.tl-lane \.tl-tab > svg \.f \{ fill: color-mix\(in srgb, var\(--c\) var\(--tm\), var\(--paper\)\);/.test(block)) bad('탭의 칠이 띠 바탕과 같은 섞임(--tm)이 아님');
    if (!/\.tl-lane \.tl-tab > svg \.s \{ fill: none; stroke: var\(--edge\);/.test(block)) bad('탭의 선이 띠 테두리(--edge)가 아님');
    if (!/\.tl-lane \.tl-tab \{[^}]*font-size: 9px;/.test(block)) bad('탭 글자가 9px가 아님(보이는 칸 안 — 감독 선택 2026-10-13 "글자 한 단계 작게": 10 → 9)');
    if (!/\.tl-lane \.tl-tab\.has-pin \{[^}]*clip-path: inset\(0 0 1px\);/.test(block)) bad('고리 위로 올라온 탭이 띠의 윗 테두리를 덮음(has-pin의 아래 1px 자르기가 없음)');
    if (!/\.tl-lane \.tl-htab \{[^}]*z-index: -2;/.test(block)) bad('뒤 장의 탭(.tl-htab)이 책갈피 탭보다 아래 층(z −2)이 아님');
    if (/transition:[^;}]*[\d.]+m?s\b/.test(block)) bad('탭의 전환에 손으로 적은 시간이 있음(움직임 토큰만)');
  }
  /* 상국 탭의 자리(상국 표기 C — 건의 8의 2번 · 2026-10-14 · 노드에서 _hostTabPlan을 직접 — 모델 없이 가짜 정권으로): 관계가 끝나는 쪽 — 탭 오른쪽 끝 = min(뒤 장 끝 − 둥근 값, 화면 오른쪽 − 6) ·
     탭 왼쪽은 뒤 장 왼쪽 + 둥근 값 · 제 이름 탭(from) · 앞 상국 탭(+ TAB.gap) 뒤에만(안 되면 탭 없이 뒤 장만) · 접힌 소속 · 왕조 상국은 없음 */
  if (!HT.Timeline) vm.runInThisContext(readFileSync(join(root, 'js/timeline.js'), 'utf8'), { filename: 'js/timeline.js' });
  const TL = HT.Timeline;
  if (!TL || !TL.TAB || typeof TL.tabBump !== 'function' || !TL.prototype || typeof TL.prototype._hostTabPlan !== 'function') bad('Timeline.TAB · tabBump · _hostTabPlan이 없음');
  else {
    const X = y => y; // 1년 = 1px
    const host = (name, kind = 'state') => ({ uid: 'u-' + name, name, polityKind: kind, color: '#bba395' });
    const plan = (p, from, flatR, W = 2000) => TL.prototype._hostTabPlan.call({}, p, X, W, 100, from, flatR);
    const RAD = (TL.PLATE && TL.PLATE.radius) || 10; // 뒤 장의 둥근 값 — 탭은 뒤 장의 평평한 윗변 안
    const p = { name: '속', start: 100, endY: 900, polityKind: 'tributary', hosts: [{ host: host('갑'), start: 300, end: 600, relation: 'tributary' }, { host: host('을'), start: 305, end: 700, relation: 'colony' }, { host: host('왕가', 'dynasty'), start: 400, end: 500 }] };
    const r = plan(p, 150, 890);
    if (r.length !== 2) bad(`뒤 장의 탭 수가 2가 아님(${r.length}) — 왕조 상국은 빼야 함`);
    else {
      if (Math.abs(r[0].x + r[0].w - (600 - RAD)) > 1e-9) bad(`첫 상국 탭의 오른쪽 끝이 관계가 끝나는 해(600)의 뒤 장 평평한 윗변 끝(${600 - RAD})이 아닌 ${r[0].x + r[0].w}`);
      if (Math.abs(r[1].x + r[1].w - (700 - RAD)) > 1e-9) bad(`둘째 상국 탭의 오른쪽 끝이 ${700 - RAD}가 아닌 ${r[1].x + r[1].w}`);
      if (r[1].x < r[0].x + r[0].w + TL.TAB.gap - 1e-9) bad('둘째 상국 탭이 앞 탭과 TAB.gap 안으로 닿음');
      if (r[0].seg.look !== 'loose' || r[1].seg.look !== 'owned') bad(`상국 탭의 칠(look)이 이름표의 자와 다름(${r[0].seg.look} · ${r[1].seg.look})`);
    }
    const edgeR = plan(p, 150, 890, 650); // 화면 폭 650 — '을'(~700)의 끝이 화면 오른쪽 밖: 탭은 화면 끝 6px 안에 붙음
    if (edgeR.length !== 2 || Math.abs(edgeR[1].x + edgeR[1].w - 644) > 1e-9) bad(`관계 끝이 화면 밖인 상국 탭이 화면 오른쪽 끝(644)에 붙지 않음: ${JSON.stringify(edgeR.map(q => q.x + q.w))}`);
    if (plan(Object.assign({}, p, { hosts: [{ host: host('갑'), start: 300, end: 330, relation: 'tributary' }] }), 150, 890).length) bad('뒤 장보다 넓은 상국 탭을 그림(뒤 장의 평평한 윗변 안에 들지 않으면 탭 없이 뒤 장만)');
    if (plan(Object.assign({}, p, { singleHost: true }), 150, 890).length) bad('상위 띠 아래에 접힌 소속(singleHost)에도 상국 탭을 그림');
    const late = plan(p, 600, 2000); // 제 이름 탭이 600까지 — '갑' 탭(관계 끝 590)은 자리가 없어 빠지고 '을'만
    if (late.length !== 1 || late[0].seg.h.host.name !== '을' || late.some(q => q.x < 600)) bad('제 이름 탭 오른쪽(from)보다 앞에 상국 탭이 섬(또는 자리가 없는 탭을 비켜 그림)');
  }
}

/* 실재성 (docs/구상-체제-확장.md 8-4 마): 한국어도 읽는지 · 옛 칸 legendary(연대의 전승)의 뜻이 그대로인지 · 새 칸을 쓴 파일만 형식 2인지 · 패치 · 시대 폼에 칸이 있는지,
   그리고 연표(글로만 읽음)가 안개를 띠 자신이 아니라 띠 밑(::before)에 그려 띠 안의 칸을 가리지 않는지 */
{
  const bad = msg => out.problems.push(`실재성: ${msg}`);
  const ids = HT.HISTORICITY.map(h => h.id).join(',');
  if (ids !== 'attested,semi,legendary,disputed,refuted') bad(`실재성 표가 다름 (${ids})`);
  for (const [w, id] of [['전설', 'legendary'], ['반전설', 'semi'], ['논쟁', 'disputed'], ['부정됨', 'refuted'], ['refuted', 'refuted'], ['모르는 말', '']]) if (HT.historicity(w) !== id) bad(`"${w}"을(를) "${id}"(으)로 읽지 않음`);
  const base = { format: HT.FORMAT, formatVersion: 1, id: 'smoke-hs', name: 'smoke', tracks: [{ id: 'smoke-t', name: 't' }] };
  const one = extra => HT.normalizePack(Object.assign({}, base, { periods: [Object.assign({ name: '가', track: 'smoke-t', start: 1, end: 9 }, extra)] }));
  const legacy = one({ legendary: true });
  if (!legacy.pack || legacy.pack.periods[0].certainty !== 'legend' || 'historicity' in legacy.pack.periods[0]) bad('옛 칸 legendary: true가 연대의 전승이 아니게 읽힘');
  if (legacy.pack && HT.packToJSON(legacy.pack).formatVersion !== 1) bad('옛 칸만 쓴 파일이 형식 1로 나가지 않음');
  const ko = one({ historicity: '전설', historicityNote: '근거' });
  if (!ko.pack || ko.pack.periods[0].historicity !== 'legendary' || ko.pack.periods[0].historicityNote !== '근거') bad('한국어 실재성 · 근거 글을 읽지 못함');
  if (ko.pack && HT.packToJSON(ko.pack).formatVersion !== 2) bad('실재성을 쓴 파일이 형식 2로 나가지 않음');
  const plain = one({ historicity: 'attested' });
  if (!plain.pack || 'historicity' in plain.pack.periods[0]) bad('실재(attested)를 기본값으로 비우지 않음');
  const patch = HT.normalizePack(Object.assign({}, base, { patches: [{ target: 'x/y', set: { historicity: '부정' } }] }));
  if (!patch.pack || !patch.pack.patches[0] || patch.pack.patches[0].set.historicity !== 'refuted') bad('패치의 실재성을 읽지 못함');
  else if (HT.packToJSON(patch.pack).formatVersion !== 2) bad('실재성을 고치는 패치가 형식 2로 나가지 않음');
  /* 실재로 되돌리는 패치(null로 읽힘)와 근거 글을 지우는 패치('')도 형식 2 — 옛 앱은 그 칸을 버려 패치가 통째로 사라지므로 */
  for (const set of [{ historicity: '' }, { historicity: '실재' }, { historicityNote: '' }]) {
    const r = HT.normalizePack(Object.assign({}, base, { patches: [{ target: 'x/y', set }] }));
    if (!r.pack || !r.pack.patches[0]) bad(`패치 ${JSON.stringify(set)}을(를) 읽지 못함`);
    else if (HT.packToJSON(r.pack).formatVersion !== 2) bad(`실재성을 지우는 패치 ${JSON.stringify(set)}이(가) 형식 2로 나가지 않음 (옛 앱이 버림)`);
  }
  const form = HT.periodFieldsHTML({ tracks: [] });
  if (!/name="historicity"/.test(form) || !/name="historicityNote"/.test(form)) bad('시대 폼에 실재성 칸이 없음 (형식에 있는 칸 = 폼에 있는 칸)');
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  const at = csrc.indexOf('/* ── 실재성 ──');
  if (at < 0) bad("common.css에 '실재성' 블록이 없음");
  else {
    const next = csrc.indexOf('/* ── ', at + 10);
    const block = csrc.slice(at, next < 0 ? csrc.length : next);
    if (/\.tl-band:is\(\.hs-legendary, \.hs-semi\) \{[^}]*mask-image/.test(block)) bad('안개가 띠 자신을 가림(띠 안의 칸까지 옅어짐) — 띠 밑(::before)에만');
    if (!/\.hs-semi\)::before \{[^}]*mask-image/.test(block)) bad('안개(띠 밑 ::before의 가림막)가 없음');
    if (/transition:[^;}]*[\d.]+m?s\b/.test(block)) bad('손으로 적은 시간이 있음(움직임 토큰만)');
    if (!/\.hs-refuted\.cert-legend[^{]*\{[^}]*repeating-linear-gradient/.test(block)) bad('부정된 나라의 전승 연대 빗금이 없음 (회색 바탕이 연대의 빗금을 덮음)');
  }
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  if (!/_rowPeopleChip\(tr, r\)/.test(tsrc) || !/class="tl-pchip["$]/.test(tsrc)) bad('민족 딱지(8-4 사)의 도우미 _rowPeopleChip · .tl-pchip이 없음');
}

/* 대범위 (docs/구상-체제-확장.md 7 · 8-4 바): 형식 읽기("이름" · "트랙:이름" · 객체, 빈 이름 · 빈 구성 정권은 오류, 본국 · 다른 트랙은 경고) · 형식 2 ·
   모델(구성 정권 · 역참조 · 본국 · 비운 기간은 같은 트랙 구성 정권의 범위 · 시대 구분에서 물려받기) · 폼의 칸(형식에 있는 칸 = 폼에 있는 칸),
   그리고 연표(글로만 읽음)가 두 간격 공식에 같은 도우미를 더하는지 · 묶음 차례를 옮기기 전의 시작 해(start0)로 정하는지 · 다시 배치할 때 대범위를 싣는지 · 모양 블록이 토큰만 쓰는지 */
{
  const bad = msg => out.problems.push(`대범위: ${msg}`);
  const base = {
    format: HT.FORMAT, formatVersion: 1, id: 'smoke-sc', name: 'smoke', tracks: [{ id: 'smoke-t', name: 't' }, { id: 'smoke-u', name: 'u' }],
    periods: [{ name: 'A', track: 'smoke-t', start: 1, end: 5 }, { name: 'B', track: 'smoke-t', start: 2, end: 9 }, { name: 'C', track: 'smoke-u', start: 2, end: 9 }],
  };
  const one = extra => HT.normalizePack(Object.assign({}, base, extra));
  const r = one({ scopes: [{ track: 'smoke-t', name: 'S', members: ['A', 'smoke-u:C', { polity: 'B' }, 'A'], host: 'B', default: false }] });
  const s = r.pack && r.pack.scopes && r.pack.scopes[0];
  if (!s) bad('대범위를 읽지 못함');
  else {
    if (JSON.stringify(s.members) !== JSON.stringify(['A', { track: 'smoke-u', polity: 'C' }, 'B'])) bad(`구성 정권을 "이름" · "트랙:이름" · 객체로 읽지 못함 (${JSON.stringify(s.members)})`);
    if ('default' in s) bad('끔(default: false)을 파일에 적음 — 기본이 끔');
    if (!/^s-/.test(s.id)) bad(`자동 id가 s-로 시작하지 않음 (${s.id})`);
    if (!r.warnings.some(w => /구성 정권에도/.test(w.msg))) bad('상징적 본국이 구성 정권에 든 것을 경고하지 않음');
    if (!r.warnings.some(w => /다른 트랙/.test(w.msg))) bad('다른 트랙의 구성 정권을 경고하지 않음');
    if (HT.packToJSON(r.pack).formatVersion !== 2) bad('대범위를 쓴 파일이 형식 2로 나가지 않음');
    const m = HT.buildModel([r.pack], null);
    const ms = m.scopes && m.scopes[0];
    if (!ms || ms.itemKind !== 'scope' || HT.itemKindOf(ms) !== 'scope' || m.byUid.get(ms.uid) !== ms || HT.itemWord(ms) !== '대범위') bad('모델의 대범위(model.scopes · byUid · itemKind scope)가 없음');
    else {
      if (ms.members.map(p => p.name).join(',') !== 'A,C') bad(`구성 정권이 정권 객체 목록이 아님 — 본국은 빠져야 함 (${ms.members.map(p => p.name).join(',')})`);
      if (!ms.members[0].scopes || ms.members[0].scopes[0] !== ms) bad('정권 쪽 역참조(p.scopes)가 없음');
      if (!ms.host || ms.host.name !== 'B' || !(ms.host.hostedScopes || []).includes(ms)) bad('상징적 본국(host · hostedScopes)을 풀지 못함');
      if (!ms.warnings.some(w => /다른 트랙/.test(w))) bad('모델 검사에 다른 트랙의 구성 정권 경고가 없음');
      if (ms.start !== 1 || ms.endY !== 5 || !ms.startAuto || ms.rangeFrom !== 'members') bad('기간을 비웠을 때 같은 트랙 구성 정권의 범위로 채우지 않음(startAuto 표시와 함께)');
      if (JSON.stringify(ms.memberRefs) !== JSON.stringify(s.members)) bad('원문(memberRefs)이 보존되지 않음');
    }
  }
  const e = one({ scopes: [{ track: 'smoke-t', members: ['A'] }, { track: 'smoke-t', name: 'N' }] });
  if (e.errors.filter(x => x.kind === 'scopes').length !== 2) bad('이름 · 구성 정권이 빈 대범위를 오류로 보지 않음');
  const ep = one({ epochs: [{ name: 'E', track: 'smoke-t', start: 1, end: 9, color: '#a0bcc5' }], scopes: [{ track: 'smoke-t', epoch: 'E', members: ['A', 'B'] }] });
  const em = ep.pack && HT.buildModel([ep.pack], null).scopes[0];
  if (!em || em.name !== 'E' || !em.nameAuto || em.start !== 1 || em.endY !== 9 || em.color !== '#a0bcc5' || !em.colorAuto || !em.epoch || !(em.epoch.scopes || []).includes(em)) bad('시대 구분에서 이름 · 기간 · 색을 물려받지 않음');
  if (packs.some(p => !(p.scopes || []).length && 'scopes' in p)) bad('대범위를 쓰지 않은 파일에 빈 목록이 생김(옛 파일이 달라짐)');
  const F = HT.FORMS.scope;
  if (!F || !F.nameKey || typeof F.fresh !== 'function' || typeof F.filterKeys !== 'function') bad('폼(HT.FORMS.scope)에 nameKey · fresh · filterKeys 가운데 빠진 것이 있음');
  else {
    const html = F.html({ tracks: [], epochs: [] });
    for (const k of ['name', 'track', 'label', 'start', 'end', 'ongoing', 'host', 'epoch', 'useColor', 'color', 'default', 'description', 'note', 'wiki']) if (!new RegExp(`name="${k}"`).test(html)) bad(`폼에 "${k}" 칸이 없음 (형식에 있는 칸 = 폼에 있는 칸)`);
    if (!/data-scope-members/.test(html) || !/data-scope-epoch-import/.test(html)) bad('폼에 구성 정권 줄 · 시대 구분에서 가져오기가 없음');
  }
  if (HT.USER_LISTS.some(l => l.kind === 'scope')) bad('대범위가 내 데이터 목록에 있음 (시대 구분처럼 연표에서는 고치지 않음)');
  if (model) for (const sc of model.scopes || []) if (sc.warnings.length) bad(`견본의 ${sc.uid}: ${sc.warnings.join(' / ')}`);
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  if ((tsrc.match(/\+ this\._scopePad\(tr, r, /g) || []).length !== 2) bad('두 간격 공식(_layoutTrack · _foldRows)의 끝에 같은 도우미(_scopePad)가 없음');
  if (!/start: c\.start0/.test(tsrc)) bad('민족 묶음의 차례를 옮기기 전의 시작 해(start0)로 정하지 않음 — 켜고 끌 때 다른 묶음이 자리를 바꿈');
  if (!/this\._data = \{[^}\n]*scopes/.test(tsrc)) bad('다시 배치(relayout · toggleScope)할 때 대범위를 싣지 않음(setData의 this._data)');
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  const at = csrc.indexOf('/* ── 대범위 ──');
  if (at < 0) bad("common.css에 '대범위' 블록이 없음");
  else {
    const next = csrc.indexOf('/* ── ', at + 10);
    const block = csrc.slice(at, next < 0 ? csrc.length : next);
    if (/transition:[^;}]*[\d.]+m?s\b/.test(block) || /animation:[^;}]*[\d.]+m?s\b/.test(block)) bad('손으로 적은 시간이 있음(움직임 토큰만)');
    if (!/\.tl-lanes > \.tl-scope \{[^}]*pointer-events: none;/.test(block)) bad('테두리 몸통이 누름을 가로챔(pointer-events: none이 아님)');
  }
}

/* 대범위 ② 모여드는 움직임 (docs/구상-체제-확장.md 7-3 — 연표는 화면이 있어야 돌므로 글로만 읽음): 높이 전환과 같은 호출에서 출발하는지(setData의 _applyFlip 바로 다음 한 줄),
   토글 한 번에만 도는지(자료 갱신에는 없음 — _gatherReq) · 스크롤 0px로 트랙 위쪽을 붙잡고 밀려남 알림을 비우는지 · 줄 번호로 이어받는 접힘 기억을 끊는지 ·
   다시 그려지는 것을 같은 시계에 다시 붙이는지(_drawTrack 끝의 한 줄 · 네모를 줄별 <g data-row>로) · 움직임의 길이 · 곡선이 토큰(HT.motion.T · C)뿐인지 */
{
  const bad = msg => out.problems.push(`모여드는 움직임: ${msg}`);
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  if (!/this\._applyFlip\(before(, clock)?\);\n\s*(this\._squash\(before, clock\);[^\n]*\n\s*)?this\._gather\(before\);/.test(tsrc)) bad('setData에서 _applyFlip 바로 다음에 _gather(before)가 없음 (높이 전환과 같은 호출에서 출발해야 함)');
  if (!/this\._gatherReq = [^\n]*this\._gatherFirst\(/.test(tsrc) || !/const req = this\._gatherReq;\n\s*this\._gatherReq = null;/.test(tsrc)) bad('모여듦이 토글 한 번에만 돌지 않음 (toggleScope의 _gatherReq — 주기적 setData에는 없어야 함)');
  const tg = tsrc.slice(tsrc.indexOf('    toggleScope(uid, force) {'), tsrc.indexOf('    _uidRow(tr, uid) {'));
  if (!/\{ trackId: s\.track, row: -1 \}/.test(tg)) bad('toggleScope가 트랙 위쪽을 붙잡지 않음 (스크롤 0px)');
  if (!/this\._jump = null;/.test(tg)) bad("toggleScope가 정권별 '밀려남 알림'을 비우지 않음");
  if (!/tr\._rowMemo = false;/.test(tg)) bad('toggleScope가 줄 번호로 이어받는 접힘 기억을 끊지 않음');
  if (/this\.relayout\(\)/.test(tg)) bad('toggleScope가 relayout을 거침 (밀려남 알림이 뜸)');
  if (!/if \(tr\._gather\) this\._gatherDraw\(tr\);/.test(tsrc)) bad('_drawTrack 끝에 모여듦을 다시 붙이는 한 줄(_gatherDraw)이 없음');
  if (!/<g data-row="\$\{r\}">/.test(tsrc)) bad('건국·멸망 네모가 줄별 <g data-row>로 묶이지 않음 (줄과 같은 거리로 옮길 수 없음)');
  const at = tsrc.indexOf('/* ---------- 모여드는 움직임');
  const end = tsrc.indexOf('/* ---------- 그림으로 내보내기');
  if (at < 0 || end < at) bad("timeline.js에 '모여드는 움직임' 덩어리가 toSVG 바로 앞에 없음");
  else {
    const block = tsrc.slice(at, end);
    for (const m of block.matchAll(/(duration|delay): ([^,}]+)/g)) if (/\d{2,}/.test(m[2].replace(/M\.T\.\w+/g, ''))) bad(`손으로 적은 시간이 있음 (${m[0]})`);
    for (const m of block.matchAll(/easing: ([^,}]+)/g)) if (!/M\.C\.|'ease-in'/.test(m[1])) bad(`토큰이 아닌 곡선이 있음 (${m[0]})`);
    if (!/M\.T\.move : M\.T\.in/.test(block) || !/M\.C\.spring : M\.C\.ease/.test(block)) bad('줄의 이동이 T.move · C.spring(떠오름은 T.in · C.ease)이 아님');
    if (!/playbackRate = M\.rate/.test(block)) bad('느리게 보기에서 모여듦이 함께 느려지지 않음 (playbackRate)');
    if (!/reduceMotion\(\)/.test(block)) bad('동작 줄이기에서 모여듦을 건너뛰지 않음');
  }
}

/* 모여드는 움직임 검토 반영 (글로만 읽음): 누른 본국 줄은 창이 어디에 열려 있든 붙잡는지(붙잡았다는 표시는 실제로 붙잡았을 때만) ·
   붙잡은 채 가려지는 것(보이던 고른 줄 · 켠 테두리)은 같은 판정으로 데려오는지 · 동작 줄이기에서도 누른 줄이 먼저인지 ·
   끄던 대범위를 도중에 다시 켜면 새 테두리 · 왼쪽 칸이 잔상의 밝기에서 이어 떠오르는지 */
{
  const bad = msg => out.problems.push(`모여드는 움직임 검토: ${msg}`);
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const fn = name => {
    const at = tsrc.indexOf(`\n    ${name}(`);
    return at < 0 ? '' : tsrc.slice(at, tsrc.indexOf('\n    }\n', at));
  };
  const gather = fn('_gather');
  if (/let held = !!req\.pressUid/.test(gather) || !/let held = false;/.test(gather)) bad('_gather가 누르기만 해도 붙잡았다고 봄 (창이 열린 항목 · 켠 테두리를 데려오지 않게 됨)');
  if (!/held = this\._gatherHold\(tr, req, plan, members, ownerOf\);/.test(gather)) bad('_gather가 _gatherHold의 결과(실제로 붙잡았는가)를 그대로 쓰지 않음');
  if (!/this\._pressStill\(tr, req\)/.test(gather)) bad('동작 줄이기에서 창이 열려 있을 때 누른 본국 줄을 붙잡지 않음 (_pressStill)');
  const hold = fn('_gatherHold');
  if (!/if \(pressed\) \[row, uid\] = \[hp\._row, hp\.uid\];\n\s*else if \(a && a\.tr === tr\)/.test(hold)) bad('_gatherHold에서 누른 본국 줄이 창이 열린 항목보다 먼저가 아님');
  if (!/this\._pressScroll\(/.test(hold)) bad('_gatherHold가 누른 줄을 붙잡을 때 가려지는 것의 데려오기(_pressScroll)를 싣지 않음');
  const ps = fn('_pressScroll');
  if (!/this\._revealTo\(a, f\)/.test(ps) || !/this\._scopeMiss\(tr, req\.uid, sF\)/.test(ps)) bad('_pressScroll이 보이던 고른 줄 · 켠 테두리를 데려오지 않음');
  if (!/this\._scopeMiss\(tr, uid, this\.bodyEl\.scrollTop\)/.test(fn('_gatherReveal'))) bad('_gatherReveal과 붙잡기의 테두리 판정이 한 곳(_scopeMiss)이 아님');
  if (!/el\._ghost === s\.uid/.test(fn('_gatherFirst')) || !/el\._ghost = uid;/.test(fn('_gatherGhost'))) bad('끄던 대범위를 다시 켤 때 잔상의 밝기를 읽지 않음');
  if (!/el\.classList\.remove\('is-born'\);\n\s*this\._gatherAnim\(el, g, 0, 0, F\.reborn\[k\]\);/.test(gather)) bad('다시 켠 테두리 · 왼쪽 칸이 밝기 0부터 다시 떠오름 (번쩍임)');
}

/* 대범위 검토 반영 (글로만 읽음): 켠 대범위로 떠난 정권이 옛 상위 아래에 또 놓이지 않는지(소속 줄 · '▸ n' 개수 · 검색으로 가기) ·
   본국 줄에 매달린 가지의 머리 몫 · 선이 이름표를 비켜 가는지 · '직접 승계만'에서 부흥선 묶음이 숨는지 · 민족 칸이 한 단일 때 가지 안의 딱지가 가는 띠인지 */
{
  const bad = msg => out.problems.push(`대범위 검토: ${msg}`);
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const fn = (from, to) => tsrc.slice(tsrc.indexOf(from), tsrc.indexOf(to, tsrc.indexOf(from) + from.length));
  if (!/const pushMembers = host => \{[\s\S]{0,200}!\(m\._scope && m\._host !== host\)/.test(tsrc)) bad('펼친 옛 상위 아래에 대범위로 떠난 정권을 또 놓음 (pushMembers — 빈 줄 + 가지, 두 번)');
  if (!/const nMem = [^\n]*!\(m\._scope && m\._host !== p\)/.test(tsrc)) bad("본국 띠의 '▸ n'이 대범위로 떠난 정권까지 셈");
  if (!/const gathered = q =>/.test(fn('    focusOn(item) {', '    render() {'))) bad('검색 · 여기로 가기가 대범위로 모인 정권의 옛 상위를 펼침 (focusOn)');
  if (!/G\.scopeHead \+ 2 \+ tab/.test(fn('    _scopeHead(tr, r) {', '    _scopeBox(tr, b) {'))) bad('본국 줄에 매달린 가지의 머리 몫이 0 — 되돌아가는 승계선이 이름표를 지남 (_scopeHead)');
  const dl = fn('    _drawLinks(tr, X, W) {', '    _setScopes(list) {');
  if (!/crossesLab\(pts\)/.test(dl) || !/labAt\(\[x, y1\], \[x, y2\]\)/.test(dl)) bad('승계선 · 소속선이 대범위 이름표를 비켜 가지 않음 (_drawLinks — _scopeLabelRect)');
  if (!/this\.show\.succession === 'direct'/.test(fn('    _drawScopes(tr, X, W) {', '    _hollowHTML('))) bad("'직접 승계만'에서도 부흥선 묶음을 그림 (_drawScopes)");
  if (!/const thin = this\.depth === 1 && !!c\.scope;/.test(tsrc) || !/\.tl-pchip\.is-thin \{/.test(readFileSync(join(root, 'css/common.css'), 'utf8'))) bad('민족 칸이 한 단일 때 가지 안의 딱지가 대범위 칸 전체를 덮음 (이름이 사라짐)');
}

/* ⑪ 두 화면의 뼈대 (글로만 읽음): 연표는 보기 전용 — 편집 요소가 없어야 하고, 메이커에는 메이커 부품이 뷰어보다 먼저 읽혀야 하며 부품이 찾는 요소가 다 있어야 함 */
{
  const bad = msg => out.problems.push(`화면: ${msg}`);
  const view = readFileSync(join(root, 'index.html'), 'utf8');
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  const makerSrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (!/<body data-app="view">/.test(view)) bad('index.html의 body에 data-app="view"가 없음');
  if (!/<body data-app="make"[ >]/.test(make)) bad('dlc-maker.html의 body에 data-app="make"가 없음'); // 작업실: class="mk-shell"이 뒤에 붙음
  for (const id of ['editorDialog', 'editorForm', 'wikiEditor', 'wikiText', 'wikiEdit', 'addPeriodBtn', 'addEventBtn', 'editModeBtn', 'exportDialog']) if (view.includes(`id="${id}"`)) bad(`보기 전용인 index.html에 편집 요소 #${id}이(가) 있음`);
  if (view.includes('src="js/maker.js"')) bad('index.html이 메이커 부품을 읽음');
  if (!(make.indexOf('src="js/maker.js"') > 0 && make.indexOf('src="js/maker.js"') < make.indexOf('src="js/viewer.js"'))) bad('dlc-maker.html에서 js/maker.js가 js/viewer.js보다 먼저 읽히지 않음');
  for (const [, id] of makerSrc.matchAll(/\$\('#([A-Za-z]+)'\)/g)) if (!make.includes(`id="${id}"`)) bad(`메이커 부품이 찾는 #${id}이(가) dlc-maker.html에 없음`);
  const packsOf = html => [...html.matchAll(/<script src="(packs\/[^"]+)"/g)].map(m => m[1]).join();
  if (packsOf(view) !== packsOf(make)) bad('두 화면이 읽는 기본팩 파일이 다름');
}

/* ⑫ 메이커 도구(js/maker.js의 HT.makerKit — 순수 계산): 바탕 자료의 열 설정표(쓰는 곳 · id/이름 바꿈 때 참조 따라 고치기 · 중첩 참조) · DLC id 바꾸기 ·
   표 붙여넣기 · 시대 구분 폼이 작업본에 들어가는지. 메이커 부품(화면)은 부르지 않습니다 — 그것은 브라우저에서 */
{
  const bad = msg => out.problems.push(`메이커 도구: ${msg}`);
  try {
    load('js/maker.js');
    const kit = HT.makerKit;
    const D = HT.draft;
    if (!kit || typeof HT.makerPlugin !== 'function') bad('js/maker.js가 HT.makerKit · HT.makerPlugin을 만들지 않음');
    else {
      /* 트랙 id 바꿈: 항목 · 시대 구분의 track · 사건의 "함께 겪은 쪽"(트랙:정권) · 나라별 명칭 · 패치의 track · 트랙 문서가 모두 따라감 */
      const d = D.clean({
        format: HT.FORMAT, id: 'smoke-kit', name: '도구 검사', version: '1.0.0',
        tracks: [{ id: 't1', name: '가 트랙' }, { id: 't2', name: '나 트랙' }],
        peoples: [{ id: 'pa', name: '가 민족' }, { id: 'pb', name: '나 민족', parent: '가 민족' }],
        epochs: [{ id: 'ep1', name: '가 시기', track: 't1', start: 10, end: 50 }],
        periods: [{ id: 'p1', track: 't1', name: '가 나라', start: 1, end: 100, people: '가 민족', leaders: [{ name: '첫 임금', start: 1, house: 'h1' }, { name: '둘째 임금', start: 40, house: 'h2' }] }],
        events: [{ id: 'e1', track: 't2', title: '가 사건', start: 20, tracks: ['t1', 't1:가 나라', 't10'], perspectives: [{ track: 't1', title: '다른 이름' }] }],
        patches: [{ target: 'other-dlc/x', set: { track: 't1' } }, { target: 'smoke-kit/p1', set: { description: '제 항목 패치' } }],
        documents: { 'track:t1': '트랙 문서', 'track:t1//역사': '하위', p1: '시대 문서', 'smoke-kit/e1': '절대 키 문서' },
      });
      const T = kit.BASE_TABLES;
      const users = kit.findUsers(d, T.tracks, d.tracks[0]);
      if (users.length !== 4 || kit.usageText(users) !== '시대 구분 1 · 객체 1 · 사건 1 · 패치 1') bad(`트랙의 쓰는 곳이 어긋남: ${kit.usageText(users)} (${users.length})`);
      const n = kit.renameRefs(d, T.tracks, 'id', 't1', 't9');
      d.tracks[0].id = 't9';
      const ev = d.events[0];
      if (d.periods[0].track !== 't9' || d.epochs[0].track !== 't9' || ev.tracks.join() !== 't9,t9:가 나라,t10' || ev.perspectives[0].track !== 't9' || d.patches[0].set.track !== 't9' || ev.track !== 't2')
        bad(`트랙 id를 바꿨는데 참조가 따라가지 않음: ${JSON.stringify({ p: d.periods[0].track, ep: d.epochs[0].track, tracks: ev.tracks, view: ev.perspectives[0].track, patch: d.patches[0].set.track })}`);
      if (!('track:t9' in d.documents) || !('track:t9//역사' in d.documents) || 'track:t1' in d.documents || n !== 8) bad(`트랙 id 바꿈의 문서 · 고친 수가 어긋남: ${Object.keys(d.documents)} · ${n}`);
      /* 민족 이름 바꿈: 이름으로 적은 시대의 민족 · 다른 민족의 상위 민족이 따라감 (id로 적은 곳은 그대로) */
      const m2 = kit.renameRefs(d, T.peoples, 'name', '가 민족', '가 겨레');
      if (d.periods[0].people !== '가 겨레' || d.peoples[1].parent !== '가 겨레' || m2 !== 2) bad(`민족 이름을 바꿨는데 참조가 따라가지 않음: ${d.periods[0].people} · ${d.peoples[1].parent} · ${m2}`);
      /* 중첩 참조를 설정 한 덩어리로: 통합 때 가문(houses)이 지도자 칸의 house를 가리키는 모양 */
      const houses = { word: '가문', idBase: 'house', cols: [kit.COL.id, kit.COL.name], refs: { id: [{ list: 'periods', path: 'leaders[].house' }] } };
      if (kit.findUsers(d, houses, { id: 'h1' }).length !== 1 || kit.renameRefs(d, houses, 'id', 'h1', 'h7') !== 1 || d.periods[0].leaders[0].house !== 'h7' || d.periods[0].leaders[1].house !== 'h2')
        bad(`중첩 참조(leaders[].house)가 따라가지 않음: ${JSON.stringify(d.periods[0].leaders)}`);
      /* DLC id 바꾸기: 제 문서는 상대 키로(새 id를 따라감) · 제 항목을 가리킨 패치 대상도 · 검사 통과 · 모델의 uid가 새 id로 */
      kit.renameDlc(d, 'smoke-kit2');
      if (d.id !== 'smoke-kit2' || !('e1' in d.documents) || 'smoke-kit/e1' in d.documents || d.patches[1].target !== 'smoke-kit2/p1' || d.patches[0].target !== 'other-dlc/x') bad(`DLC id 바꾸기가 어긋남: ${JSON.stringify({ id: d.id, docs: Object.keys(d.documents), t: d.patches.map(p => p.target) })}`);
      const rp = HT.normalizePack(d);
      if (!rp.pack || rp.errors.length) bad(`바꾼 작업본이 검사를 통과하지 못함: ${rp.errors.map(e => e.msg).join(' / ')}`);
      else {
        const mm = HT.buildModel([rp.pack], null);
        if (!mm.byUid.has('smoke-kit2/p1') || (mm.docs.get('smoke-kit2/e1') || {}).text !== '절대 키 문서' || (mm.byUid.get('smoke-kit2/p1') || {}).description !== '제 항목 패치') bad('id를 바꾼 작업본의 모델에서 항목 · 문서 · 패치가 새 id를 따라가지 않음');
      }
      /* 표 붙여넣기: 사건 3줄(하나는 날짜 못 읽음 → 건너뜀) · 없는 트랙 · 분류는 새로 · 미정 · 음력 달력 열 */
      const tracks = [{ id: 't2', name: '나 트랙' }];
      const cats = HT.DEFAULT_CATEGORIES.map(c => ({ id: c.id, name: c.name }));
      const txt = '제목\t시작\t끝\t트랙\t분류\t중요도\t달력\n첫 사건\t120\t\t나 트랙\t정치\t3\t\n둘째 사건\t미정\t130\t새 트랙\t새 분류\t★\t\n셋째 사건\t가나다\t\t\t\t\t\n넷째 사건\t0150-03-01\t\tt2\t\t\t음력';
      const r = kit.analyzePaste(txt, 'event', { tracks, categories: cats, defaultTrack: 't2' });
      if (r.error || r.items.length !== 3 || r.problems.length !== 1 || r.newTracks.length !== 1 || r.newCats.length !== 1) bad(`붙여넣기 결과가 어긋남: ${JSON.stringify({ e: r.error, n: r.items.length, p: r.problems, nt: r.newTracks, nc: r.newCats })}`);
      else {
        const [a, b, c] = r.items;
        if (a.track !== 't2' || a.category !== 'politics' || a.importance !== 3 || a.start !== 120) bad(`붙여넣은 첫 줄이 어긋남: ${JSON.stringify(a)}`);
        if (!b.startUnknown || b.start !== 130 || b.track !== r.newTracks[0].id || b.category !== r.newCats[0].id || b.importance !== 1) bad(`붙여넣은 미정 줄이 어긋남: ${JSON.stringify(b)}`);
        if (!/^음력/.test(c.startAt || '')) bad(`달력 열(음력)이 날짜에 붙지 않음: ${JSON.stringify(c)}`);
        /* 작업본에 넣으면 검사를 통과 */
        const pd = D.blank({ id: 'smoke-paste', name: '붙여넣기 검사' });
        pd.tracks.push({ id: 't2', name: '나 트랙' }, ...r.newTracks);
        pd.categories.push(...r.newCats);
        r.items.forEach(obj => D.addItem(pd, 'event', obj));
        const pr = HT.normalizePack(pd);
        if (!pr.pack || pr.errors.length || pr.pack.events.length !== 3) bad(`붙여넣은 사건이 검사를 통과하지 못함: ${pr.errors.map(e => e.msg).join(' / ')}`);
      }
      const ph = kit.analyzePaste('아무개\t언제\n가\t1', 'event', { tracks, categories: cats });
      if (!ph.error) bad('머리글이 없는 표인데 알리지 않음');
      const pp = kit.analyzePaste('이름\t시작\t끝\t종류\t전승\n가 나라\t-300\t현재\t종속국\t예', 'period', { tracks, categories: cats, defaultTrack: 't2' });
      if (pp.items.length !== 1 || pp.items[0].kind !== 'vassal' || !pp.items[0].ongoing || pp.items[0].certainty !== 'legend' || pp.items[0].start !== -300) bad(`붙여넣은 시대가 어긋남: ${JSON.stringify(pp.items[0])}`);
      /* 시대 구분 폼: HT.FORMS에 들어가되 연표의 추가 길에는 없고(add: false), 작업본에 넣으면 시대 구분으로 */
      const F = HT.FORMS.epoch;
      if (!F || F.list !== 'epochs' || F.add !== false || typeof F.fresh !== 'function') bad('시대 구분 폼이 HT.FORMS에 없거나 설정이 어긋남');
      else {
        const ed = D.blank({ id: 'smoke-epoch', name: '시대 구분 검사' });
        const id = D.addItem(ed, 'epoch', Object.assign(F.fresh({ start: 100 }), { name: '가 시기', note: '', color: undefined, ongoing: false }));
        const er = HT.normalizePack(ed);
        if (!er.pack || er.pack.epochs.length !== 1 || er.pack.epochs[0].id !== id || er.pack.epochs[0].end !== 200 || 'track' in er.pack.epochs[0]) bad(`시대 구분 폼으로 넣은 것이 어긋남: ${JSON.stringify(er.pack && er.pack.epochs)}`);
      }
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ⑬ 검토 반영(메이커 ① 뼈대): 패치로 단 문서(set.wiki)는 열어서 그대로 저장해도 남고, 문서를 고치거나 지우면 documents 하나로 ·
   견본 밖의 색을 건 패치는 열어서 그대로 저장해도 색이 바래지 않음 · 바탕 판의 지문(설치본과 그것을 가져온 작업본이 같은 지문)과 설치본이 바뀌었을 때 할 일 */
if (model) {
  const bad = msg => out.problems.push(`검토 반영: ${msg}`);
  try {
    const D = HT.draft;
    const kit = HT.makerKit;
    const base = packs.filter(p => p.id === 'east-asia-base');
    const bm = HT.buildModel(base, null);
    const modelOf = d => HT.buildModel(base.concat([HT.normalizePack(d).pack]), null);
    const per = bm.periods.find(p => p.itemKind === 'period' && !bm.docs.has(p.uid) && !p.colorAuto) || bm.periods.find(p => p.itemKind === 'period' && !bm.docs.has(p.uid));
    const docOf = (d, uid) => (modelOf(d).docs.get(uid) || {}).text || '';
    /* 패치로 단 문서: 폼(보이는 문서가 채워짐)을 그대로 저장 → 패치의 본문이 남음 · 문서를 고치면 documents로 옮겨 가고 본문만 담던 패치는 사라짐 · 문서를 지우면 옛 본문이 되살아나지 않음 */
    const wd = D.blank({ id: 'smoke-wiki', name: '문서 검사' });
    wd.patches.push({ target: per.uid, set: { wiki: '패치로 단 문서' } });
    const shown = docOf(wd, per.uid);
    D.patchForeign(wd, per, { name: per.name, description: per.description || '', wiki: shown });
    if (shown !== '패치로 단 문서' || docOf(wd, per.uid) !== '패치로 단 문서') bad(`패치로 단 문서를 열어 그대로 저장했더니 문서가 달라짐: ${JSON.stringify(wd.patches)} · ${JSON.stringify(wd.documents)}`);
    D.setDoc(wd, per.uid, '고친 문서');
    if (wd.patches.length || wd.documents[per.uid] !== '고친 문서' || docOf(wd, per.uid) !== '고친 문서') bad(`패치로 단 문서를 고쳤는데 documents 하나로 모이지 않음: ${JSON.stringify(wd.patches)} · ${JSON.stringify(wd.documents)}`);
    wd.patches.push({ target: per.uid, set: { description: '패치 설명', wiki: '옛 본문' } });
    D.setDoc(wd, per.uid, '');
    if (wd.patches.length !== 1 || 'wiki' in wd.patches[0].set || wd.patches[0].set.description !== '패치 설명' || docOf(wd, per.uid)) bad(`문서를 지웠는데 패치의 옛 본문이 남거나 다른 칸까지 지워짐: ${JSON.stringify(wd.patches)}`);
    /* 견본 밖의 색을 건 패치: 편집 창은 보이는 색을 한 번 더 파스텔로 맞춰 담음 — 세 번 열어 그대로 저장해도 패치의 색은 그대로 · 고치면 고친 색 · 원래 색으로 되돌리면 패치가 사라짐 */
    const cd = D.blank({ id: 'smoke-color', name: '색 검사' });
    cd.patches.push({ target: per.uid, set: { color: '#b3362f' } });
    const formColor = d => HT.pastel(modelOf(d).byUid.get(per.uid).color); // HT.setSwatch가 폼에 담는 값
    const colorForm = color => ({ name: per.name, description: per.description || '', color });
    for (let i = 0; i < 3; i++) D.patchForeign(cd, per, colorForm(formColor(cd)));
    if (cd.patches.length !== 1 || cd.patches[0].set.color !== '#b3362f') bad(`패치의 색이 열어서 저장할 때마다 바뀜: ${JSON.stringify(cd.patches)}`);
    D.patchForeign(cd, per, colorForm('#9dbea8'));
    if ((cd.patches[0] || { set: {} }).set.color !== '#9dbea8') bad('패치의 색을 고쳤는데 적히지 않음');
    D.patchForeign(cd, per, colorForm(per.colorAuto ? undefined : HT.pastel(per.color)));
    if (cd.patches.length) bad(`원래 색으로 되돌렸는데 패치가 남음: ${JSON.stringify(cd.patches)}`);
    /* 손으로 적은 패치(본문 · 색 · 설명 · 메모)를 열어 그대로 저장하면 패치는 글자 하나 다르지 않음 (칸의 차례까지) */
    const hd = D.blank({ id: 'smoke-hand', name: '손 패치 검사' });
    hd.patches.push({ target: per.uid, set: { wiki: '손으로 단 문서', color: '#b3362f', description: '손으로 고친 설명' }, note: '메모' });
    const before = JSON.stringify(hd.patches);
    const hm = modelOf(hd).byUid.get(per.uid);
    D.patchForeign(hd, per, { name: hm.name, description: hm.description, color: HT.pastel(hm.color), wiki: docOf(hd, per.uid) });
    if (JSON.stringify(hd.patches) !== before) bad(`손으로 적은 패치를 열어 그대로 저장했더니 달라짐: ${before} → ${JSON.stringify(hd.patches)}`);
    /* 바탕 판의 지문: 설치본(정규화)과 그것을 가져온 작업본(D.clean → 정규화)은 같은 지문 · 한 칸만 달라도 다른 지문 */
    for (const p of packs) {
      const json = HT.packToJSON(p);
      const inst = HT.normalizePack(JSON.parse(JSON.stringify(json))).pack;
      const mine = HT.normalizePack(D.clean(JSON.parse(JSON.stringify(json)))).pack;
      if (!kit.packSig(inst) || kit.packSig(inst) !== kit.packSig(mine)) bad(`${p.id}: 설치본과 그것을 가져온 작업본의 지문이 다름`);
      const other = HT.normalizePack(Object.assign(JSON.parse(JSON.stringify(json)), { description: `${json.description || ''} 고침` })).pack;
      if (kit.packSig(other) === kit.packSig(inst)) bad(`${p.id}: 설명을 고쳤는데 지문이 같음`);
    }
    /* 설치본이 바뀌었을 때 할 일: 적어 둔 바탕 · 지금 설치본 · 작업본의 지문으로 */
    const F = kit.followOrigin;
    const never = () => {
      throw new Error('작업본의 지문을 셀 필요가 없는데 셈');
    };
    const table = [
      [null, null, never, 'mark'], // 설치본 없이 시작
      [{ sig: 'A' }, null, never, 'same'], // 설치본이 지워짐 — 작업본은 그대로
      [{ sig: 'A' }, 'A', never, 'same'],
      [{ sig: 'A' }, 'B', 'A', 'adopt'], // 고친 것이 없으면 새 설치본으로
      [{ sig: 'A' }, 'B', 'C', 'drift'], // 고친 것이 있으면 알림
      [{ sig: 'A' }, 'B', 'B', 'mark'], // 이미 같은 내용
      [{ sig: 'A' }, 'B', null, 'drift'], // 작업본이 검사를 통과하지 못함
      [{ sig: null }, 'B', 'C', 'drift'], // 새로 시작했는데 같은 id가 따로 설치됨
      [null, 'B', 'B', 'mark'], // 기록이 없는 옛 작업본 — 설치본과 같으면 바탕으로
      [null, 'B', 'C', 'drift'], // 기록이 없는 옛 작업본 — 다르면 알림
    ];
    for (const [rec, cur, mine, want] of table) {
      const got = F(rec, cur, mine);
      if (got !== want) bad(`설치본이 바뀌었을 때 할 일이 어긋남: ${JSON.stringify({ rec, cur, mine: typeof mine === 'function' ? '(셀 필요 없음)' : mine })} → ${got} (바란 것 ${want})`);
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ⑭ 큰 입력 창(js/fieldpop.js — 긴 글 칸의 [크게] · Alt+Enter): 메이커가 core · wiki · platform 뒤, viewer · maker 앞에 읽고(연표는 읽지 않음 — 일방통행 뒤로 메이커 전용), 서비스 워커가 캐시에 담으며,
   노드에서 읽어도 멈추지 않고(창은 처음 열 때 만듦) 공개 API가 있는지 · 한 줄 칸으로 돌려보낼 글의 줄바꿈이 빈칸이 되는지. 창의 동작(비추기 · 다시 묶기)은 브라우저에서 */
{
  const bad = msg => out.problems.push(`큰 입력 창: ${msg}`);
  try {
    const scripts = html => [...html.matchAll(/<script src="([^"]+)"/g)].map(m => m[1]);
    if (scripts(readFileSync(join(root, 'index.html'), 'utf8')).includes('js/fieldpop.js')) bad('보기 전용인 index.html이 js/fieldpop.js를 읽음 (큰 입력 창은 메이커 전용)');
    for (const page of ['dlc-maker.html']) {
      const s = scripts(readFileSync(join(root, page), 'utf8'));
      const at = s.indexOf('js/fieldpop.js');
      if (at < 0) {
        bad(`${page}이(가) js/fieldpop.js를 읽지 않음`);
        continue;
      }
      for (const before of ['js/core.js', 'js/wiki.js', 'js/platform.js']) if (!(s.indexOf(before) >= 0 && s.indexOf(before) < at)) bad(`${page}: ${before}이(가) js/fieldpop.js보다 먼저 읽히지 않음`);
      for (const after of ['js/viewer.js', 'js/maker.js']) if (s.includes(after) && s.indexOf(after) < at) bad(`${page}: ${after}이(가) js/fieldpop.js보다 먼저 읽힘`);
    }
    if (!readFileSync(join(root, 'sw.js'), 'utf8').includes("'js/fieldpop.js'")) bad('sw.js의 PRECACHE에 js/fieldpop.js가 없음');
    load('js/fieldpop.js');
    const P = HT.fieldPop;
    if (!P) bad('js/fieldpop.js가 HT.fieldPop을 만들지 않음');
    else {
      for (const k of ['attach', 'open', 'close', 'detach', 'check', 'isOpen', 'oneLine']) if (typeof P[k] !== 'function') bad(`HT.fieldPop.${k}이(가) 없음`);
      if (P.isOpen() || P.bound || P.closed) bad('읽기만 했는데 창이 열려 있음');
      if (P.outside !== false) bad('읽기만 했는데 새 브라우저 창으로 꺼내져 있음 (또는 outside가 없음)');
      if (P.oneLine('가\n나\r\n다\r라') !== '가 나 다 라') bad('한 줄 칸으로 돌려보낼 글의 줄바꿈이 빈칸이 되지 않음');
      if (!Array.isArray(P.INPUTS) || !P.INPUTS.every(s => s.startsWith('input'))) bad('Alt+Enter로 여는 한 줄 칸 목록(INPUTS)은 input 선택자여야 함');
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ⑮ 종류와 소속 관계: 새 칸(relation · nest) · 새 종류 · 부흥 승계를 쓴 파일만 2로 나가는지, 한국어 환산 · 경고 · "상위 띠 아래에 접기" 규칙(singleHost)이 맞는지.
   함께, 형식 1인 팩만으로 만든 모델의 해시를 따로 적습니다 — 새 견본이 늘어도 옛 자료의 모델이 그대로인지 이 값으로 봅니다 */
{
  const bad = msg => out.problems.push(`종류·소속 관계: ${msg}`);
  if (model) {
    const pick = x => ({ uid: x.uid, kind: x.kind, itemKind: x.itemKind, polityKind: x.polityKind, start: x.start, endY: x.endY, track: x.track, name: x.name || x.title, row: undefined });
    const m1 = HT.buildModel(packs.filter(p => !HT.usesNewFormat(p)), null);
    out.model.hashV1 = hash(canon(m1.periods.map(pick).concat(m1.events.map(pick))));
  }
  const mk = periods => ({ format: HT.FORMAT, id: 'smoke-kinds', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }], periods });
  const host = { id: 'h', track: 'smoke-t', name: '상위', start: 0, end: 500 };
  const r = HT.normalizePack(mk([
    host,
    { id: 'a', track: 'smoke-t', name: '가', kind: '괴뢰국', start: 10, end: 90, partOf: [{ polity: '상위', relation: '괴뢰' }] },
    { id: 'b', track: 'smoke-t', name: '나', start: 10, end: 90, partOf: [{ polity: '상위', relation: '없는관계' }] },
    { id: 'c', track: 'smoke-t', name: '다', start: 10, end: 90, partOf: [{ polity: '상위', relation: 'colony', nest: true, start: 20 }] },
    { id: 'd', track: 'smoke-t', name: '라', start: 10, end: 90, partOf: [{ polity: '상위', relation: 'puppet', nest: true }] },
    { id: 'e', track: 'smoke-t', name: '마', start: 10, end: 90, partOf: [{ polity: '상위', relation: 'member' }] },
    { id: 'f', track: 'smoke-t', name: '바', start: 10, end: 90, partOf: [{ polity: '상위', nest: false }] },
    { id: 'g', track: 'smoke-t', name: '사', kind: 'movement', start: 100, end: 120, succeeds: [{ from: '가', type: '부흥' }] },
  ]));
  if (!r.pack) bad('검사용 팩이 정규화되지 않음');
  else {
    const P = Object.fromEntries(r.pack.periods.map(p => [p.id, p]));
    if (P.a.kind !== 'puppet' || P.a.partOf[0].relation !== 'puppet') bad('한국어 종류 · 소속 관계가 id로 바뀌지 않음');
    if (P.b.partOf !== '상위' || !r.warnings.some(w => /없는관계/.test(w.msg))) bad('모르는 소속 관계를 버리고 경고하지 않음');
    if (!r.warnings.some(w => /"다"/.test(w.msg) && /접기/.test(w.msg))) bad('기간이 있는 소속의 nest: true에 경고가 없음');
    if (P.g.succeeds[0].type !== 'revival') bad('승계 종류 부흥(revival)이 남지 않음');
    if (HT.packToJSON(r.pack).formatVersion !== 2) bad('새 칸을 쓴 검사용 팩이 formatVersion 2로 나가지 않음');
    const m = HT.buildModel([r.pack], null);
    const S = Object.fromEntries(m.periods.map(p => [p.id, p]));
    const want = { a: false, b: true, c: false, d: true, e: true, f: false };
    for (const [id, single] of Object.entries(want)) if (S[id].singleHost !== single) bad(`"${S[id].name}"의 접힘(singleHost)이 ${single}이어야 하는데 ${S[id].singleHost}`);
    if (S.a.hosts[0].relation !== 'puppet' || S.d.hosts[0].nest !== true) bad('모델의 hosts에 relation · nest가 실리지 않음');
    if (!S.g.predecessors.some(e => e.type === 'revival')) bad('모델의 승계에 부흥(revival)이 없음');
  }
  const organs = HT.normalizePack(Object.assign(mk([host]), { organs: [{ id: 'o', track: 'smoke-t', name: '기관', start: 10, end: 20, host: [{ polity: '상위', relation: 'puppet', nest: true }] }] }));
  if (!organs.pack || JSON.stringify(organs.pack.organs[0].host).includes('relation') || JSON.stringify(organs.pack.organs[0].host).includes('nest')) bad('기관의 host가 relation · nest를 받아들임 (시대의 partOf에서만 받아야 함)');
  for (const k of HT.POLITY_KINDS) if (!k.family || !/ — /.test(k.hint) || (k.id !== 'state' && !k.short)) bad(`종류 "${k.id}"에 family · short · ' — 모양' 꼴의 hint 가운데 빠진 것이 있음`);
  for (const x of HT.RELATIONS) if (!x.name || !x.short || !(x.hollow || [0, 1, 2, 3].includes(x.autonomy))) bad(`소속 관계 "${x.id}"의 이름 · 짧은 이름 · 자율성이 올바르지 않음`); // 자율성이 상국 띠의 속국 이름표 자리를 정함 (㉜)
  /* 묶음 3 · 3번(2026-09-22): 새 종류 셋(복속 세력 · 기미 · 직할령)과 시대마다의 낱말이 종류 · 소속 관계로 읽히고, 그 종류를 쓴 팩은 형식 2로 나가며, 이름에 왜관이 든 기관은 구역으로 읽히는지 */
  for (const [w, id] of [['복속 세력', 'client'], ['부용', 'client'], ['기미주', 'frontier'], ['토사', 'frontier'], ['군현', 'prefecture'], ['도호부', 'prefecture'], ['부마국', 'vassal'], ['번', 'fief'], ['특별행정구', 'dominion'], ['절도사', 'warlord'], ['직할령·군현', 'prefecture'], ['복속', 'client']])
    if (HT.polityKindId(w) !== id) bad(`종류 낱말 "${w}"이(가) ${id}로 읽히지 않음(${HT.polityKindId(w) || '없음'})`);
  for (const [w, id] of [['복속', 'client'], ['기미', 'frontier'], ['직할', 'prefecture'], ['군현', 'prefecture'], ['부마국', 'vassal'], ['번', 'fief'], ['특별행정구', 'dominion'], ['절도사', 'nominal']])
    if (HT.relationId(w) !== id) bad(`소속 관계 낱말 "${w}"이(가) ${id}로 읽히지 않음(${HT.relationId(w) || '없음'})`);
  if (HT.relationOfKind('client') !== 'client' || (HT.relationInfo('client') || {}).autonomy !== 3 || (HT.relationInfo('prefecture') || {}).autonomy !== 0 || (HT.relationInfo('frontier') || {}).autonomy !== 3) bad('새 종류(복속 세력 · 기미 · 직할령)의 소속 관계 · 자율성이 맞지 않음');
  if (HT.kindFamily('client') !== 'dependent' || HT.kindFamily('prefecture') !== 'dependent' || HT.kindFamily('frontier') !== 'dependent') bad('새 종류 셋이 종속 갈래가 아님');
  const k3 = HT.normalizePack(mk([host, { id: 'k1', track: 'smoke-t', name: '옥저', kind: '복속 세력', start: 10, end: 90, partOf: [{ polity: '상위', relation: '복속' }] }]));
  if (!k3.pack || k3.pack.periods[1].kind !== 'client' || k3.pack.periods[1].partOf[0].relation !== 'client') bad('"복속 세력" · "복속"이 client로 읽히지 않음');
  else if (HT.packToJSON(k3.pack).formatVersion !== 2) bad('새 종류(client)를 쓴 팩이 formatVersion 2로 나가지 않음');
  const wae = HT.normalizePack(Object.assign(mk([host]), { organs: [{ id: 'z', track: 'smoke-t', name: '부산 왜관', start: 10, end: 20, host: '상위' }] }));
  if (!wae.pack || wae.pack.organs[0].scale !== 'zone') bad('이름에 왜관이 든 기관이 구역(zone)으로 읽히지 않음');
}

/* ⑮-2 종류와 소속 관계(검토 고침): 패치의 set.kind · set.succeeds도 시대처럼 한국어를 id로 읽는지(그런 파일은 2로, 옛 값만 쓴 패치는 1 그대로),
   true/false가 아닌 nest에 경고하는지, 관계를 적은 소속의 상위 정권이 다른 트랙이면 nest: true여도 접히지 않는지(관계 없는 옛 자료는 예전 그대로) */
{
  const bad = msg => out.problems.push(`종류·소속 관계(고침): ${msg}`);
  const base = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-kinds2', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }, { id: 'smoke-u', name: '다른 트랙' }], periods: [
    { id: 'h', track: 'smoke-t', name: '상위', start: 0, end: 500 },
    { id: 'old', track: 'smoke-t', name: '옛 나라', start: 100, end: 200 },
    { id: 'x', track: 'smoke-u', name: '가', start: 10, end: 90, partOf: [{ polity: '상위', relation: 'puppet', nest: true }] },
    { id: 'y', track: 'smoke-u', name: '나', start: 10, end: 90, partOf: [{ polity: '상위' }] },
    { id: 'z', track: 'smoke-t', name: '다', start: 10, end: 90, partOf: [{ polity: '상위', relation: 'puppet', nest: true }] },
    { id: 'w', track: 'smoke-t', name: '라', start: 10, end: 90, partOf: [{ polity: '상위', nest: 'true' }] },
  ] });
  if (!base.pack) bad('검사용 팩이 정규화되지 않음');
  else {
    if (!base.warnings.some(w => /"라"/.test(w.msg) && /nest/.test(w.msg))) bad('true/false가 아닌 nest에 경고가 없음');
    if (base.pack.periods.find(p => p.id === 'w').partOf !== '상위') bad('true/false가 아닌 nest가 버려지지 않음');
    const S = Object.fromEntries(HT.buildModel([base.pack], null).periods.map(p => [p.id, p]));
    if (S.x.singleHost !== false) bad('상위 정권이 다른 트랙인데 관계를 적은 소속(nest: true)이 접힘으로 남음 — 관계가 띠 어디에도 안 보임');
    if (S.y.singleHost !== true) bad('관계를 적지 않은 옛 자료의 다른 트랙 소속이 예전과 달라짐');
    if (S.z.singleHost !== true) bad('같은 트랙 상위 정권의 nest: true가 접히지 않음');
    const patch = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-kinds2-patch', name: '검사 패치', patches: [
      { target: 'smoke-kinds2/old', set: { kind: '괴뢰국', succeeds: [{ from: '상위', type: '부흥', note: '메모' }] } },
      { target: 'smoke-kinds2/z', set: { kind: '없는종류', succeeds: ['상위'] } },
      { target: 'smoke-kinds2/w', set: { partOf: [{ polity: '상위', relation: '없는관계', nest: 1 }] } },
    ] });
    const sets = patch.pack ? patch.pack.patches.map(x => x.set) : [];
    if (!patch.pack || sets[0].kind !== 'puppet' || sets[0].succeeds[0].type !== 'revival' || sets[0].succeeds[0].note !== '메모') bad('패치의 한국어 종류("괴뢰국") · 승계 종류("부흥")가 id로 바뀌지 않음');
    else {
      if (sets[1].succeeds[0].from !== '상위' || sets[1].succeeds[0].type !== 'indirect') bad('패치의 승계를 글("상위")로 적은 것을 읽지 못함');
      if (!patch.warnings.some(w => /없는종류/.test(w.msg))) bad('패치의 모르는 정권 종류에 경고가 없음');
      if (!patch.warnings.some(w => /없는관계/.test(w.msg)) || !patch.warnings.some(w => /nest/.test(w.msg))) bad('패치의 모르는 소속 관계 · 잘못 적은 nest에 경고가 없음');
      if (HT.packToJSON(patch.pack).formatVersion !== 2) bad('패치에 새 종류 · 부흥을 쓴 파일이 formatVersion 2로 나가지 않음');
      const S2 = Object.fromEntries(HT.buildModel([base.pack, patch.pack], null).periods.map(p => [p.id, p]));
      if (S2.old.polityKind !== 'puppet') bad(`패치로 바꾼 종류가 괴뢰국이어야 하는데 ${S2.old.polityKind}`);
      if (!S2.old.predecessors.some(e => e.type === 'revival' && e.from.id === 'h')) bad('패치로 적은 부흥 승계가 모델에 없음');
    }
    const plain = { kind: 'vassal', succeeds: [{ from: '상위', type: 'direct' }] };
    const old = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-kinds2-old', name: '옛 패치', patches: [{ target: 'smoke-kinds2/old', set: plain }] });
    if (!old.pack || JSON.stringify(old.pack.patches[0].set) !== JSON.stringify(plain) || HT.packToJSON(old.pack).formatVersion !== 1) bad('옛 값만 쓴 패치의 종류 · 승계가 달라지거나 formatVersion 1로 나가지 않음');
  }
}

/* ⑯ 인물: 견본의 활동 시기 짐작(startAuto · endAuto) · 섬긴 정권 풀기(다른 트랙 · 자동 배정) · 사건의 관련 인물 · 읽기 규칙(날짜 하나 이상 · 이름) ·
   패치(섬긴 기록의 "트랙:정권" 글과 생몰 날짜 글을 다시 읽음) · 내 수정(짐작한 시작을 비워 저장해도 짐작이 그대로) · 숨김 */
{
  const bad = msg => out.problems.push(`인물: ${msg}`);
  const sample = packs.find(p => p.id === 'lantern-chronicle');
  if (!sample) {
    if (!skipSamples.some(s => 'sample-lantern.json'.includes(s))) bad('견본 sample-lantern이 없음'); // --skip=로 뺐으면 이 블록은 건너뜁니다
  } else {
    const m = HT.buildModel([sample], null);
    const F = Object.fromEntries((m.figures || []).map(f => [f.id, f]));
    const want = {
      'f-seorin': { start: 405, endY: 460, startAuto: true, endAuto: true, services: ['등불 왕국', '윗물국'] }, // 섬긴 기간에서 짐작
      'f-ar-nunbora': { start: 772, endY: 803, startAuto: true, endAuto: true, services: ['설족 칸국', '설원 제국', '하연 총관부'] }, // 다른 트랙의 정권
      'f-galmuri': { start: 1362, endY: 1408, startAuto: true, endAuto: true, services: ['하연 부흥국', '하연 연합 왕국'] },
    };
    for (const [id, w] of Object.entries(want)) {
      const f = F[id];
      if (!f) {
        bad(`견본 인물 ${id}이(가) 모델에 없음`);
        continue;
      }
      for (const k of ['start', 'endY', 'startAuto', 'endAuto']) if (f[k] !== w[k]) bad(`${f.name}의 ${k}가 ${w[k]}이어야 하는데 ${f[k]}`);
      const got = f.services.filter(s => s.polity).map(s => s.polityName);
      if (got.join('|') !== w.services.join('|')) bad(`${f.name}의 섬긴 정권이 ${w.services.join(', ')}이어야 하는데 ${got.join(', ')}`);
    }
    if (!m.byUid.has('lantern-chronicle/f-ar-nunbora') || HT.itemKindOf(m.byUid.get('lantern-chronicle/f-ar-nunbora')) !== 'figure') bad("byUid의 인물 갈래가 'figure'가 아님");
    const league = m.periods.find(p => p.id === 'p-league');
    // 물새 이랑 · 바울 미르 · 닻 바위(이름으로) · 물새 파랑(id p-league로 — 2.0.1에서 바로잡음)
    if (!league || (league.servedBy || []).length !== 4) bad(`산호 해상 동맹을 섬긴 인물(servedBy)이 4이어야 하는데 ${league ? (league.servedBy || []).length : '정권 없음'}`);
    const ev = m.events.find(e => e.id === 'e-conquest');
    if (!ev || (ev.figureRefs || []).map(r => r.uid).join('|') !== 'lantern-chronicle/f-ar-nunbora') bad('사건의 관련 인물(figureRefs)이 풀리지 않음');
    if (!F['f-ar-nunbora'] || !F['f-ar-nunbora'].events.includes(ev)) bad('인물 쪽 관련 사건(events)이 채워지지 않음');
    /* 내 수정: 짐작한 시작을 비운 채 저장(start: null) → 짐작이 그대로 · 숨김 → 모델에서 빠짐 */
    const user = HT.blankUser();
    user.overrides['lantern-chronicle/f-ar-nunbora'] = { start: null, startAt: null, importance: 5 };
    user.hidden['lantern-chronicle/f-dat-bawi'] = true;
    const mu = HT.buildModel([sample], user);
    const nb = mu.byUid.get('lantern-chronicle/f-ar-nunbora');
    if (!nb || nb.start !== 772 || !nb.startAuto || nb.importance !== 5) bad('내 수정으로 시작을 비운 인물의 짐작 시작이 사라지거나 수정이 들지 않음');
    if (mu.byUid.has('lantern-chronicle/f-dat-bawi')) bad('숨긴 인물이 모델에 남음');
  }
  const mk = extra => Object.assign({ format: HT.FORMAT, id: 'smoke-fig', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }], periods: [{ id: 'p', track: 'smoke-t', name: '나라', start: 0, end: 500 }, { id: 'q', track: 'smoke-t', name: '뒤 나라', start: 500, end: 900 }] }, extra);
  const r = HT.normalizePack(mk({ figures: [
    { id: 'f-a', track: 'smoke-t', name: '갑', birth: 100, death: '0170-03-01', service: ['나라', 'smoke-t:뒤 나라', { office: '관직만' }], importance: 5 },
    { track: 'smoke-t', name: '을' },
    { track: 'smoke-t', birth: 10 },
    { track: 'smoke-t', name: '병', birth: 10, death: 5 },
  ] }));
  if (!r.pack) bad('검사용 팩이 정규화되지 않음');
  else {
    const f = r.pack.figures[0];
    if ((f.service || []).map(s => `${s.track || ''}:${s.polity}`).join('|') !== ':나라|smoke-t:뒤 나라') bad('섬긴 기록의 "정권" · "트랙:정권" 글을 읽지 못하거나 정권 없는 줄을 버리지 않음');
    if (f.importance !== 2 || !r.warnings.some(w => /중요도/.test(w.msg))) bad('범위 밖 중요도를 2로 바꾸고 경고하지 않음');
    if (!/^170-03-01$/.test(f.deathAt || '')) bad(`사망 날짜 글(deathAt)이 남지 않음: ${f.deathAt}`);
    if (r.pack.figures.length !== 1 || r.errors.length !== 3) bad(`날짜 없는 인물 · 이름 없는 인물 · 사망이 앞선 인물이 오류로 빠져야 하는데 인물 ${r.pack.figures.length} · 오류 ${r.errors.length}`);
    if (!/^f-/.test(HT.normalizePack(mk({ figures: [{ track: 'smoke-t', name: '정', birth: 30 }] })).pack.figures[0].id)) bad("자동 id가 'f-'로 시작하지 않음");
    const id1 = HT.normalizePack(mk({ figures: [{ track: 'smoke-t', name: '정', birth: 30, service: ['나라'] }] })).pack.figures[0].id;
    const id2 = HT.normalizePack(mk({ figures: [{ track: 'smoke-t', name: '정', birth: 30, start: 40, service: ['뒤 나라'] }] })).pack.figures[0].id;
    if (id1 !== id2) bad('섬긴 기록 · 활동 시기를 고쳤는데 자동 id가 바뀜 (씨앗은 트랙 + 이름 + 생년)');
    /* 섬긴 기록이 없는 인물: 생몰만 적으면 생몰이 활동(짐작) · 활동만 적으면 그대로 — 둘 다 활동 가운데 해의 같은 트랙 정권에 자동 배정 */
    const ma = HT.buildModel([HT.normalizePack(mk({ figures: [{ id: 'f-j', track: 'smoke-t', name: '정', birth: 30, death: 90 }, { id: 'f-m', track: 'smoke-t', name: '무', start: 600, end: 700 }] })).pack], null);
    const fj = ma.byUid.get('smoke-fig/f-j') || {};
    const fm = ma.byUid.get('smoke-fig/f-m') || {};
    if (fj.start !== 30 || fj.endY !== 90 || !fj.startAuto || !fj.endAuto) bad('생몰만 적은 인물의 활동이 생몰에서 짐작되지 않음');
    if (fm.start !== 600 || fm.endY !== 700 || fm.startAuto || fm.endAuto) bad('활동만 적은 인물의 활동이 적은 그대로가 아님');
    if (!(fj.services || [])[0] || !fj.services[0].auto || fj.services[0].polityName !== '나라' || !(fm.services || [])[0] || !fm.services[0].auto || fm.services[0].polityName !== '뒤 나라') bad('섬긴 기록이 없는 인물이 활동 가운데 해의 정권에 자동 배정(auto)되지 않음');
    /* 패치: 다른 DLC의 인물을 고침 — 섬긴 기록 글 · 날짜 글을 다시 읽고, 패치를 쓴 파일은 2로 */
    const p = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-fig-patch', name: '검사 패치', patches: [{ target: 'smoke-fig/f-a', set: { service: ['smoke-t:뒤 나라'], birth: '0090-05-05' } }] });
    const set = p.pack && p.pack.patches[0].set;
    if (!set || !Array.isArray(set.service) || set.service[0].polity !== '뒤 나라' || typeof set.birth !== 'number' || !/^90-05-05$/.test(set.birthAt || '')) bad('패치의 섬긴 기록 · 생몰 날짜 글이 다시 읽히지 않음');
    if (p.pack && HT.packToJSON(p.pack).formatVersion !== 2) bad('인물을 고치는 패치를 쓴 파일이 formatVersion 2로 나가지 않음');
    if (p.pack) {
      const mp = HT.buildModel([r.pack, p.pack], null);
      const fa = mp.byUid.get('smoke-fig/f-a');
      if (!fa || fa.polityName !== '뒤 나라' || !fa.patchedBy) bad('패치가 인물의 섬긴 정권을 바꾸지 못함');
    }
  }
  if (HT.normalizePack(mk({ events: [{ id: 'e', track: 'smoke-t', title: '일', start: 10, figures: '갑, 을' }] })).pack.events[0].figures.join('|') !== '갑|을') bad('사건의 관련 인물을 쉼표 글로 읽지 못함');
}

/* ⑯-2 인물 폼: 섬긴 기록 줄의 트랙이 지금 목록에 없어도(꺼 둔 DLC의 트랙) 그 값이 골라진 채 남음 — 폼을 한 번 거쳐 저장해도 트랙이 인물의 트랙으로 바뀌지 않게 */
{
  const bad = msg => out.problems.push(`인물 폼: ${msg}`);
  const tracks = [{ id: 'smoke-t', name: '검사 트랙' }];
  const trackSel = html => (html.match(/<select class="v-track"[\s\S]*?<\/select>/) || [''])[0]; // 줄의 트랙 고르기만 (줄 안의 이설 상자에도 고르기가 있음 — ㊳)
  const lost = trackSel(HT.serviceRowHTML(tracks, { track: 'smoke-gone', polity: '나라' }));
  if (!/<option value="smoke-gone" selected>/.test(lost)) bad('목록에 없는 트랙이 섬긴 기록 줄의 고르기에 골라진 채 남지 않음');
  const kept = trackSel(HT.serviceRowHTML(tracks, { track: 'smoke-t', polity: '나라' }));
  if ((kept.match(/<option /g) || []).length !== 2 || !/<option value="smoke-t" selected>/.test(kept)) bad('목록에 있는 트랙의 줄에 선택지가 더 생기거나 골라지지 않음');
  if (/selected/.test(trackSel(HT.serviceRowHTML(tracks, { polity: '나라' })))) bad('트랙을 비운 줄이 인물의 트랙이 아닌 것을 고름');
}

/* ⑰ 시기 구분(학계): 체계 목록으로 정리(납작한 꼴은 체계별로 묶음) · 쓴 파일만 2로 · 패치도 같은 꼴로 · 겹침 경고 ·
   모델의 경계 채우기(첫 시작 = 정권 시작 · 빈 끝 = 다음 시작 · 마지막 끝 = 정권 끝 · 알 수 없는 경계는 고르게 나눔) · 칸 참조는 펼친 순번 · 체계가 다르면 문서 키도 다름 */
{
  const bad = msg => out.problems.push(`시기 구분: ${msg}`);
  const K = HT.cellKind('phase');
  if (!K || K.list !== 'phases' || typeof K.items !== 'function') bad('칸 종류 표에 phase(목록 phases · items)가 없음');
  if (!HT.PATCHABLE.includes('phases')) bad('패치할 수 있는 칸에 phases가 없음');
  if (HT.SHOW_DEFAULTS.phases !== true) bad('표시 체크 phases의 기본값이 켬(true)이 아님');
  const mk = (periods, extra = {}) => Object.assign({ format: HT.FORMAT, id: 'smoke-phases', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }], periods }, extra);
  const r = HT.normalizePack(mk([
    { id: 'a', track: 'smoke-t', name: '가', start: 100, end: 500, phases: [
      { scheme: '갑', spans: [['앞', null, 200], ['가운데', 200, null], ['뒤', null, null], ['끝', 400, null]] },
      { scheme: '을', spans: [{ name: '앞', start: 100, end: 300 }, { name: '뒤', start: 300, end: '미정' }] },
    ] },
    { id: 'b', track: 'smoke-t', name: '나', start: 100, end: 500, phases: [{ name: '하나', end: 250, scheme: '병' }, { name: '둘', start: 250, scheme: '병' }, { name: '셋', start: 150, end: 180, scheme: '정' }] },
    { id: 'c', track: 'smoke-t', name: '다', start: 100, end: 500, phases: [{ spans: [['겹1', 100, 300], ['겹2', 250, 400]] }] },
    { id: 'd', track: 'smoke-t', name: '라', start: 100, end: 500 },
  ], { patches: [{ target: 'smoke-other/x', set: { phases: [{ name: '패치 시기', start: 120 }] } }] }));
  if (!r.pack) bad('검사용 팩이 정규화되지 않음');
  else {
    const P = Object.fromEntries(r.pack.periods.map(p => [p.id, p]));
    if (!Array.isArray(P.a.phases) || P.a.phases.length !== 2 || P.a.phases[1].spans[1].endUnknown !== true) bad('체계 목록 · 미정 끝이 남지 않음');
    if (!P.b.phases || P.b.phases.map(g => g.scheme).join() !== '병,정' || P.b.phases[0].spans.length !== 2) bad('납작한 꼴이 체계별로(처음 나온 차례대로) 묶이지 않음');
    if (!r.warnings.some(w => /"다"/.test(w.msg) && /겹칩니다/.test(w.msg))) bad('한 체계 안의 겹침에 경고가 없음');
    if (r.warnings.some(w => /"가"|"나"|"라"/.test(w.msg) && /겹칩니다/.test(w.msg))) bad('겹치지 않는 시기에 겹침 경고가 뜸');
    if (!r.warnings.some(w => /"가"/.test(w.msg) && /고르게 나눠/.test(w.msg))) bad('끝도 시작도 빈 경계에 알림이 없음');
    if (P.d.phases !== undefined) bad('시기 구분이 없는 시대에 phases 칸이 생김');
    const pt = r.pack.patches[0];
    if (!pt || !Array.isArray(pt.set.phases) || !pt.set.phases[0].spans || pt.set.phases[0].spans[0].name !== '패치 시기') bad('패치의 phases가 같은 꼴로 정리되지 않음');
    const json = HT.packToJSON(r.pack);
    if (json.formatVersion !== 2) bad('시기 구분을 쓴 파일이 formatVersion 2로 나가지 않음');
    const again = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (!again.pack || JSON.stringify(HT.packToJSON(again.pack)) !== JSON.stringify(json)) bad('시기 구분의 왕복(정규화 → 내보내기 → 정규화)에서 자료가 달라짐');
    const m = HT.buildModel([r.pack], null);
    const S = Object.fromEntries(m.periods.map(p => [p.id, p]));
    const cells = HT.cellsOf(S.a, 'phase');
    const at = name => cells.find(c => c.name === name && c.scheme === '갑');
    if (!S.a.phaseSchemes || cells.length !== 6 || cells.some((c, i) => c.ci !== i)) bad('칸 참조(펼친 순번)가 HT.cellsOf의 차례와 맞지 않음');
    else {
      if (at('앞').start !== 100 || at('앞').end !== 200) bad('첫 시기의 빈 시작이 정권 시작으로 채워지지 않음');
      if (at('가운데').end !== 300 || at('뒤').start !== 300 || !at('뒤').guess) bad('알 수 없는 경계가 앞뒤 사이를 고르게 나눈 자리로 채워지지 않음');
      if (at('끝').end !== 500) bad('마지막 시기의 빈 끝이 정권 끝으로 채워지지 않음');
      if (S.a.phases[0].spans[0].start !== undefined) bad('모델이 원문 phases에 짐작 값을 써 넣음 (짐작 값은 phaseSchemes에만)');
      const k1 = HT.docKey.cell(S.a.uid, 'phases', cells.find(c => c.name === '앞' && c.scheme === '갑'));
      const k2 = HT.docKey.cell(S.a.uid, 'phases', cells.find(c => c.name === '앞' && c.scheme === '을'));
      if (k1 === k2) bad('체계가 다른 같은 이름 · 같은 해의 시기가 같은 문서 키를 가짐');
      if (HT.docKey.parse(k1).type !== 'cell' || HT.docKey.parse(k1).cellKind !== 'phases') bad(`시기의 문서 키가 칸 문서로 풀리지 않음 (${k1})`);
    }
    if (S.d.phaseSchemes) bad('시기 구분이 없는 시대에 phaseSchemes가 생김');
  }
}

/* ⑰-2 시기 구분 고침: 여러 줄 붙여넣기(띄어 쓴 이름 · 빈 시작 · 빈 끝 뒤 메모 · 여러 낱말 날짜 · 옛 꼴) ·
   폼에서 이름이 같은 체계(둘 다 비운 것도)는 저장을 막음 · 패치의 목록이 아닌 값 · 모두 읽히지 않은 목록은 무시(대상 그대로), 빈 목록은 비움(형식 2) */
{
  const bad = msg => out.problems.push(`시기 구분 고침: ${msg}`);
  const pr = [];
  const got = HT.textToPhases(['앞 시기 ~427', '말기 300~ 메모', '가운데 시기 기원전 100~서기 50 메모 글', '뒤 시기 100-200 갑~을', '~300'].join('\n'), pr);
  const want = [['앞 시기', '', '427', ''], ['말기', '300', '', '메모'], ['가운데 시기', '기원전 100', '서기 50', '메모 글'], ['뒤 시기', '100', '200', '갑~을']];
  if (JSON.stringify(got.map(c => [c.name, c.start, c.end, c.note])) !== JSON.stringify(want)) bad(`붙여넣기 해석이 안내문의 꼴과 다름 (${JSON.stringify(got)})`);
  if (pr.length !== 1 || !/5번째 줄: 이름이 없습니다/.test(pr[0])) bad(`이름 없는 줄의 알림이 맞지 않음 (${JSON.stringify(pr)})`);
  const input = value => ({ value });
  const row = name => ({ querySelector: q => input(q === '.c-name' ? name : '') });
  const box = (scheme, note, names) => ({ querySelector: q => input(q === '.ps-name' ? scheme : note), querySelectorAll: () => names.map(row) });
  const readForm = boxes => {
    const problems = [];
    HT.readPhaseRows({ querySelectorAll: () => boxes }, problems);
    return problems;
  };
  if (!readForm([box('', '가', ['앞', '뒤']), box('', '나', ['처음'])]).some(m => /둘 이상/.test(m))) bad('폼에서 이름을 비운 체계 둘이 알림 없이 합쳐짐');
  if (!readForm([box('갑', '', ['앞']), box(' 갑 ', '', ['뒤'])]).some(m => /둘 이상/.test(m))) bad('폼에서 이름이 같은 체계 둘이 알림 없이 합쳐짐');
  if (readForm([box('', '', ['앞']), box('을', '', ['뒤'])]).length) bad('이름이 다른 체계 둘(하나는 비움)의 저장이 막힘');
  const patched = set => HT.normalizePack({ format: HT.FORMAT, id: 'smoke-phases-fix', name: '검사', tracks: [{ id: 't', name: 't' }], periods: [{ id: 'a', track: 't', name: '가', start: 100, end: 500 }], patches: [{ target: 'smoke-other/x', set: Object.assign({ name: '새 이름' }, set) }] }).pack;
  for (const set of [{ phases: 'abc' }, { phases: [{ spans: [['', 1, 2]] }] }, { ranks: 'abc' }, { ranks: [{}] }]) {
    const p = patched(set);
    const k = Object.keys(set)[0];
    if (!p || !p.patches[0] || k in p.patches[0].set) bad(`패치의 읽을 수 없는 ${k}(${JSON.stringify(set[k])})가 무시되지 않고 대상을 비움`);
  }
  for (const k of ['phases', 'ranks']) {
    const p = patched({ [k]: [] });
    if (!p || !Array.isArray(p.patches[0].set[k]) || p.patches[0].set[k].length) bad(`패치의 빈 ${k}([])가 "비움"으로 남지 않음`);
    else if (HT.packToJSON(p).formatVersion !== 2) bad(`패치로 ${k}를 비우는 파일이 formatVersion 2로 나가지 않음`);
  }
}

/* ⑱ 지위: 지위 사전(rankDefs — id로만 합침 · 먼저 정의가 이김 · 맨 끝에 내장 사전) · 지위 변천(name 기준, rank도 읽음 · 첫 칸만 시작을 비울 수 있음) ·
   지도자의 지위(rank) · 쓴 파일만 2로 · 패치도 같은 꼴로 · 모델의 지위 구간(끝 채움 · 지도자에게서 끌어냄)과 rankAuto · 짙기 네 묶음 · 지위 칸에는 문서 없음 */
{
  const bad = msg => out.problems.push(`지위: ${msg}`);
  const K = HT.cellKind('rank');
  if (!K || K.list !== 'ranks' || typeof K.items !== 'function' || K.doc !== false) bad('칸 종류 표에 rank(목록 ranks · items · 문서 없음)가 없음');
  if (!HT.PATCHABLE.includes('ranks')) bad('패치할 수 있는 칸에 ranks가 없음');
  if (HT.SHOW_DEFAULTS.ranks !== true) bad('표시 체크 ranks의 기본값이 켬(true)이 아님');
  if (HT.docKey.parse(HT.docKey.cell('어느팩/어느나라', 'ranks', { name: '왕', start: 100 })).type === 'cell') bad('지위 칸의 문서 키가 칸 문서로 풀림 (지위 칸에는 문서를 달지 않음)');
  const mk = (periods, extra = {}) => Object.assign({ format: HT.FORMAT, id: 'smoke-ranks', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }], periods }, extra);
  const r = HT.normalizePack(mk([
    { id: 'a', track: 'smoke-t', name: '가', start: 100, end: 500, ranks: [['공', null, 200], { rank: '왕', start: 200 }, { name: '빈시작' }, ['황제', 400]], leaders: [{ name: '가1', start: 100, end: 150 }, { name: '가2', start: 150, end: 250, rank: '대왕' }, { name: '가3', start: 250, end: 500 }] },
    { id: 'b', track: 'smoke-t', name: '나', start: 100, end: 500, leaders: [{ name: '나0', start: 100, end: 120 }, { name: '나1', start: 120, end: 200, rank: '후' }, { name: '나2', start: 200, end: 260 }, { name: '나3', start: 260, end: 330, rank: '공작' }, { name: '나4', start: 330, end: 400, rank: '공작' }, { name: '나5', start: 400, end: 500, rank: '대통령' }] },
    { id: 'c', track: 'smoke-t', name: '다', start: 100, end: 500 },
  ], { rankDefs: [{ id: 'king', name: '대왕', tier: 7 }, { id: 'king', name: '또왕', tier: 3 }, { name: '족장', tier: 'x' }], patches: [{ target: 'smoke-other/x', set: { ranks: [{ rank: '패치 지위' }] } }] }));
  if (!r.pack) bad('검사용 팩이 정규화되지 않음');
  else {
    const P = Object.fromEntries(r.pack.periods.map(p => [p.id, p]));
    const names = (P.a.ranks || []).map(c => c.name).join();
    if (names !== '공,왕,황제') bad(`지위 변천이 이름 기준 · 시작 순으로 정리되지 않음 (${names})`);
    else {
      if (P.a.ranks[0].start !== undefined) bad('첫 칸의 빈 시작이 파일에서 채워짐 (정권 시작은 모델에서만)');
      if (P.a.ranks[1].name !== '왕' || P.a.ranks[1].rank !== undefined) bad('rank 열쇠가 name으로 저장되지 않음');
    }
    if (!r.warnings.some(w => /"가"/.test(w.msg) && /빈시작/.test(w.msg) && /시작이 없어/.test(w.msg))) bad('둘째 칸부터의 빈 시작에 알림이 없음');
    if (!P.a.leaders || P.a.leaders[1].rank !== '대왕' || P.a.leaders[0].rank !== undefined) bad('지도자의 지위(rank)가 남지 않거나 빈 칸이 생김');
    const defs = r.pack.rankDefs || [];
    if (defs.length !== 2 || defs[0].name !== '대왕' || !defs[1].id || defs[1].tier !== undefined) bad('지위 사전의 id 중복 · 읽을 수 없는 서열 처리가 올바르지 않음');
    if (!r.warnings.some(w => /중복/.test(w.msg) && /king/.test(w.msg))) bad('지위 사전의 같은 id에 알림이 없음');
    if (P.c.ranks !== undefined) bad('지위가 없는 시대에 ranks 칸이 생김');
    const pt = r.pack.patches[0];
    if (!pt || !Array.isArray(pt.set.ranks) || pt.set.ranks[0].name !== '패치 지위') bad('패치의 ranks가 같은 꼴로 정리되지 않음');
    const json = HT.packToJSON(r.pack);
    if (json.formatVersion !== 2) bad('지위를 쓴 파일이 formatVersion 2로 나가지 않음');
    const again = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (!again.pack || canon(HT.packToJSON(again.pack)) !== canon(json)) bad('지위의 왕복(정규화 → 내보내기 → 정규화)에서 자료가 달라짐'); // 열쇠 차례는 보지 않음 (대수를 채운 지도자는 두 번째에 ordinal 자리가 바뀜)
    for (const [what, extra] of [['지위 사전만', { rankDefs: [{ id: 'x', name: '가짜' }] }], ['지도자의 지위만', { periods: [{ id: 'z', track: 'smoke-t', name: '라', start: 1, end: 9, leaders: [{ name: '라1', start: 1, rank: '왕' }] }] }]]) {
      const q = HT.normalizePack(mk([], extra));
      if (!q.pack || HT.packToJSON(q.pack).formatVersion !== 2) bad(`${what} 쓴 파일이 formatVersion 2로 나가지 않음`);
      if (what === '지위 사전만' && q.warnings.some(w => /하나도 없습니다/.test(w.msg))) bad('지위 사전만 담은 DLC에 "빈 DLC" 경고가 뜸');
    }
    /* 모델: 사전은 켠 DLC(먼저 정의가 이김) → 내장. 뒤 팩의 같은 id는 버려짐 */
    const later = HT.normalizePack(Object.assign(mk([]), { id: 'smoke-ranks-2', rankDefs: [{ id: 'king', name: '늦은왕', tier: 1 }, { id: 'duke', name: '공', tier: 5, aliases: ['제후', '공작'] }] })).pack;
    const m = HT.buildModel([r.pack, later], null);
    const md = m.rankDefs || [];
    if ((HT.findRank(md, 'king') || {}).name !== '대왕' || HT.findRank(md, '늦은왕')) bad('지위 사전이 먼저 정의한 것이 이기게 합쳐지지 않음');
    if ((HT.findRank(md, '제후') || {}).id !== 'duke' || !HT.findRank(md, '황제') || HT.findRank(md, '왕')) bad('사전 찾기(id → 이름 → 별칭) · 내장 사전 채우기가 올바르지 않음');
    const lv = n => (HT.findRank(md, n) || {}).level;
    if (!(lv('황제') === 4 && lv('남') === 1 && lv('대통령') === 0 && lv('후') < lv('공'))) bad(`짙기 네 묶음이 서열을 따르지 않음 (황제 ${lv('황제')} · 남 ${lv('남')} · 대통령 ${lv('대통령')})`);
    const S = Object.fromEntries(m.periods.map(p => [p.id, p]));
    const A = S.a.rankSpans || [];
    if (A.length !== 3 || A[0].start !== 100 || !A[0].startAuto || A[0].end !== 200 || A[1].end !== 400 || A[2].end !== 500 || !A[2].endAuto) bad('지위 구간의 빈 시작 · 끝이 정권 시작 · 다음 지위 · 정권 끝으로 채워지지 않음');
    if (HT.cellsOf(S.a, 'rank') !== S.a.rankSpans || A.some((c, i) => c.i !== i)) bad('칸 참조(순번)가 HT.cellsOf의 차례와 맞지 않음');
    if (S.a.ranks[0].start !== undefined || S.a.ranks[0].end !== 200 || S.a.ranks[2].end !== undefined) bad('모델이 원문 ranks에 짐작 값을 써 넣음 (짐작 값은 rankSpans에만)');
    const L = S.a.leaders;
    if (L[0].rankAuto !== '공' || L[1].rankAuto !== undefined || L[2].rankAuto !== '왕' || (r.pack.periods[0].leaders[0].rankAuto !== undefined)) bad('지도자의 rankAuto가 시작한 해의 지위로 (모델 사본에만) 채워지지 않음');
    const B = S.b.rankSpans || [];
    if (B.map(c => `${c.name}@${c.start}-${c.end}`).join() !== '후@120-260,공작@260-400,대통령@400-500' || !B.every(c => c.derived)) bad(`지도자에게서 끌어낸 지위 구간이 올바르지 않음 (${B.map(c => `${c.name}@${c.start}-${c.end}`).join()})`);
    if (B[1] && (B[1].id !== 'duke' || B[1].name !== '공작')) bad('별칭으로 찾은 지위가 사전의 서열을 빌리되 적은 글을 그대로 쓰지 않음');
    if (S.b.leaders[0].rankAuto !== undefined || S.b.leaders[2].rankAuto !== '후') bad('끌어낸 지위의 rankAuto가 올바르지 않음 (지위를 적지 않은 지도자는 앞 지위를 이음)');
    if (S.c.rankSpans) bad('지위가 없는 시대에 rankSpans가 생김');
  }
}

/* ⑲ 통합(메이커 갈아엎기 × 종류 · 인물 · 가문 · 미정 · 조약 · 시기 · 지위): 작업본이 새 목록을 담고(인물 추가 · 비운 id는 읽기와 같은 씨앗) ·
   패치로 바꿀 수 있는 칸에 새 칸이 있고 · 모델이 짐작하거나 이어 붙인 값(인물의 활동 시작 · 칸의 미정 자리 · 지도자 칸의 가문)은 "고치지 않은 것"으로 (열어서 그대로 저장하면 패치 0 — 폼을 거친 전수 검사는 브라우저에서) */
{
  const bad = msg => out.problems.push(`통합(작업본): ${msg}`);
  const D = HT.draft;
  for (const k of ['aka', 'role', 'service', 'figures', 'birth', 'birthAt', 'phases', 'ranks', 'treaty', 'house']) if (!HT.PATCHABLE.includes(k)) bad(`패치로 바꿀 수 있는 칸에 "${k}"이(가) 없음`);
  for (const k of ['figures', 'houses', 'rankDefs']) if (!D.LISTS.includes(k)) bad(`작업본의 목록에 "${k}"이(가) 없음`);
  const tr = packs[0].tracks[0].id;
  const d = D.blank({ id: 'smoke-integ' });
  const id = D.addItem(d, 'figure', { name: '시험 인물', track: tr, birth: 600, death: 650 });
  if (!D.findOwn(d, id) || d.figures.length !== 1) bad('인물을 작업본에 넣지 못함 (HT.draft.addItem)');
  const tracks = [{ id: tr, name: '시험 트랙' }];
  const noId = D.clean({ id: 'smoke-integ', tracks, figures: [{ name: '이름만', track: tr, birth: 612 }] });
  const read = HT.normalizePack(Object.assign({}, noId, { figures: [{ name: '이름만', track: tr, birth: 612 }] })).pack;
  if (!read || !read.figures || noId.figures[0].id !== read.figures[0].id) bad('id를 비운 인물에 작업본이 준 id가 파일을 읽을 때의 id와 다름 (문서 · 패치가 떨어짐)');
  const m = HT.buildModel(packs, null);
  const strip = c => Object.fromEntries(Object.entries(c).filter(([k]) => !/Auto$|^house(Id|Name|Color)$|^endY/.test(k)));
  const withHouse = m.periods.find(p => (p.leaders || []).some(c => c.houseId));
  if (!withHouse) bad('가문이 이어진 지도자 칸이 있는 견본을 찾지 못함');
  else if (D.patchForeign(D.blank({ id: 'smoke-integ' }), withHouse, { leaders: HT.cellsFileForm(withHouse.leaders).map(strip) })) bad('모델이 지도자 칸에 이어 붙인 가문(houseId …) 때문에 고치지 않은 지도자가 패치로 나감');
  const guessed = m.figures.find(f => f.startAuto);
  if (!guessed) bad('활동 시작을 짐작한 인물이 견본에 없음');
  else if (D.patchForeign(D.blank({ id: 'smoke-integ' }), guessed, { start: undefined, startAt: undefined })) bad('짐작한 활동 시작(startAuto)을 비워 둔 인물이 패치로 나감');
  const unk = m.periods.find(p => (p.leaders || []).some(c => c.startAuto || c.endAuto));
  if (unk && D.patchForeign(D.blank({ id: 'smoke-integ' }), unk, { leaders: HT.cellsFileForm(unk.leaders).map(strip) })) bad('칸의 미정 — 모델이 짐작한 자리 때문에 고치지 않은 지도자가 패치로 나감');
  /* 가문의 직접 본문(houses[].wiki): 문서를 적었다가 지우면 빈 문서여야 합니다 (옛 본문이 되살아나지 않게 — 본문의 자리는 documents 하나) */
  const hd = D.blank({ id: 'smoke-integ' });
  hd.houses = [{ id: 'smoke-h', name: '시험 가문', wiki: '옛 본문' }];
  D.setDoc(hd, 'house:smoke-h', '새 본문');
  D.setDoc(hd, 'house:smoke-h', '');
  const hr = HT.normalizePack(D.clean(hd)).pack;
  const hh = hr && HT.buildModel([hr], null).houses.find(h => h.id === 'smoke-h');
  if (!hh || hh.wiki) bad(`제 가문의 문서를 지웠는데 다시 읽으면 옛 본문이 되살아남 (${hh ? hh.wiki : '가문 없음'})`);
}

/* ⑳ 통합(플래그 탭 · 실재성 · 민족 딱지 · 대범위 × 메이커 갈아엎기 · 종류 · 지위): 실재성이 작업본의 패치 칸이고 되돌리는 패치도 형식 2로 나가는지(작업본 → 반영 · 파일로 길) ·
   대범위가 메이커의 추가 메뉴에 끼어 저장이 깨지지 않는지(작업본의 항목 목록에 없으면 메뉴에도 없음) · 두 화면에 실재성 · 대범위 칩 줄이 있는지 ·
   책갈피 탭의 딱지 차례(이름 → 종류 · 관계 → 실재성 → 지위)가 화면과 그림 내보내기에서 같은지 · 견본의 부흥 세력이 부흥 승계(revival)로 본국을 가리켜 부흥선 묶음이 생기는지 */
{
  const bad = msg => out.problems.push(`통합(실재성 · 대범위): ${msg}`);
  const D = HT.draft;
  for (const k of ['historicity', 'historicityNote']) if (!HT.PATCHABLE.includes(k)) bad(`패치로 바꿀 수 있는 칸에 "${k}"이(가) 없음`);
  const tr = { id: 'smoke-t', name: 't' };
  const other = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-other', name: 'o', tracks: [tr], periods: [{ id: 'p1', name: '가', track: 'smoke-t', start: 1, end: 9, historicity: 'legendary', historicityNote: '근거' }] }).pack;
  const base = HT.buildModel([other], null).byUid.get('smoke-other/p1');
  const same = { historicity: 'legendary', historicityNote: '근거' };
  if (D.patchForeign(D.blank({ id: 'smoke-hs' }), base, same)) bad('실재성을 그대로 둔 남의 나라가 패치로 나감');
  const d = D.blank({ id: 'smoke-hs' });
  const pt = D.patchForeign(d, base, { historicity: undefined, historicityNote: '근거' });
  if (!pt || !('historicity' in pt.set) || pt.set.historicity !== null) bad(`실재로 되돌린 패치가 historicity: null이 아님 (${JSON.stringify(pt)})`);
  else {
    const json = HT.packToJSON(HT.normalizePack(D.clean(d)).pack);
    if (json.formatVersion !== 2 || !(json.patches[0].set && 'historicity' in json.patches[0].set)) bad('작업본에서 실재로 되돌린 패치가 반영 · 파일로 길에서 형식 2가 아니거나 칸이 빠짐 (옛 앱이 패치를 버림)');
  }
  if (HT.FORMS.scope && HT.FORMS.scope.add !== false && !D.LISTS.includes('scopes')) bad('대범위가 메이커의 추가 메뉴에 있는데 작업본의 목록에 없음 (저장하면 깨짐)');
  const withScope = D.clean({ id: 'smoke-sc2', tracks: [tr], periods: [{ name: '가', track: 'smoke-t', start: 1, end: 9 }], scopes: [{ track: 'smoke-t', name: 'S', members: ['가'] }] });
  const wsj = HT.packToJSON(HT.normalizePack(withScope).pack);
  if (!(wsj.scopes || []).length) bad('작업본에 실린 대범위가 반영 · 파일로 길에서 사라짐');
  /* 검토 반영: 바탕 자료에서 트랙 id를 바꾸면 작업본에 실린 대범위의 트랙 · "트랙:이름" · { track }도 따라가고(트랙 없는 "이름"은 정권 이름이라 그대로) · 쓰는 곳에 대범위가 셈해짐 */
  const kit = HT.makerKit;
  if (kit) {
    const ds = D.clean({ id: 'smoke-sc3', tracks: [{ id: 't1', name: '가' }, { id: 't2', name: '나' }], periods: [{ name: '가', track: 't1', start: 1, end: 9 }],
      scopes: [{ track: 't1', name: 'S', members: ['가', 't1:나', { track: 't1', polity: '다' }, 't1', 't2:라'], host: 't1:본' }, { track: 't2', name: 'T', members: ['마'], host: { track: 't1', polity: '본' } }] });
    const users = kit.findUsers(ds, kit.BASE_TABLES.tracks, ds.tracks[0]);
    if (kit.usageText(users) !== '객체 1 · 대범위 2') bad(`트랙의 쓰는 곳에 대범위가 셈해지지 않음: ${kit.usageText(users)}`);
    const nr = kit.renameRefs(ds, kit.BASE_TABLES.tracks, 'id', 't1', 't9');
    ds.tracks[0].id = 't9';
    const [s1, s2] = ds.scopes;
    if (nr !== 6 || s1.track !== 't9' || JSON.stringify(s1.members) !== JSON.stringify(['가', 't9:나', { track: 't9', polity: '다' }, 't1', 't2:라']) || s1.host !== 't9:본' || s2.track !== 't2' || s2.host.track !== 't9')
      bad(`트랙 id를 바꿨는데 대범위가 따라가지 않음: ${nr} · ${JSON.stringify(ds.scopes)}`);
    else {
      const rn = HT.normalizePack(ds);
      if (rn.errors.length || !(rn.pack.scopes || []).length) bad(`트랙 id를 바꾼 작업본의 대범위가 검사를 통과하지 못함: ${rn.errors.map(e => e.msg).join(' / ')}`);
    }
  }
  /* 검토 반영: 메이커에서 편집 창이 붙어 있을 때 대범위를 열면 openDetail ↔ openEditorFor가 서로를 부르지 않게(대범위는 편집 창에서 고칠 수 없는 것으로) */
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  /* (통합 마무리 f2에서 바뀜: 제 대범위는 편집 창으로 — 판단을 paneEditable 하나로 모아, 남의 대범위 · 시대 구분만 상세로) */
  if (!/if \(paneEditable\(uid\)\) return void openEditorFor\(uid\)/.test(vsrc) || !/if \(!paneEditable\(uid\)\) return openDetail\(uid\)/.test(vsrc) || !/function paneEditable\(uid\) \{[\s\S]{0,200}\(x\.kind !== 'epoch' && x\.kind !== 'scope'\) \|\| maker\.isOwn\(x\)/.test(vsrc))
    bad('openDetail · openEditorFor가 편집 창에서 고칠 수 있는지를 한 판단(paneEditable)으로 가리지 않음 — 둘이 어긋나면 대범위 · 시대 구분에서 서로를 부르며 끝없이 돎');
  for (const f of ['index.html', 'dlc-maker.html']) {
    const html = readFileSync(join(root, f), 'utf8');
    for (const id of ['historicityGroup', 'historicityChips', 'scopeGroup', 'scopeChips']) if (!new RegExp(`id="${id}"`).test(html)) bad(`${f}에 #${id}가 없음 (필터 칩 줄 — 두 화면이 같은 viewer.js)`);
  }
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  if (!/\$\{tabName\(p\.name\)\}\$\{kd\}\$\{hsd\}\$\{rkTag\}/.test(tsrc)) bad('책갈피 탭의 딱지 차례가 이름 → 종류 · 관계 → 실재성 → 지위가 아님 (_drawTrack)');
  if (!/const chips = tp\.mode !== 'full' \? \[\] : tp\.kds[^\n]*tp\.hs \?[^\n]*tp\.rk \?/.test(tsrc) || !/const d = tabBump\(tx, [^\n]*tp\.width,/.test(tsrc)) bad('그림 내보내기의 탭 폭이 종류 딱지 · 실재성 딱지 · 지위 딱지를 함께 셈하지 않음 (toSVG)');
  /* 검토 반영: 할거 단추는 소속 단추처럼 그 줄의 geo(시기 · 지위 단만큼 내려간 첫 글줄) · 모여드는 움직임에서 인물 막대는 제 띠와 함께 · 부흥 세력의 깃대가 실재성 안개를 덮지 않음 */
  if (!/this\._scopeBtnsHTML\(tr, p, X, W, x2, (geoOf\(p\._row\)|gr),/.test(tsrc)) bad('할거 단추가 트랙 공통 geo로 세로 자리를 잡음 — 시기 · 지위 단이 있는 줄에서 첫 글줄 위에 겹침');
  if (!/\/\^\(b\|tab\|m\|mb\|fd\|hb\)\$\/\.test\(pre\) \? rest : \/\^\(f\|o\|sb\|hg\|hl\|ht\)\$\/\.test\(pre\) \? el\.getAttribute\('data-band'\)/.test(tsrc)) bad('모여드는 움직임에서 인물 막대(f · fd) · 기관 칸(o) · 할거 단추(sb) · 속국 이름표(hg · hl)가 제 띠와 함께 옮겨지지 않음 (_gatherDraw)');
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  if (!/\.tl-band\.kind-movement:not\([^)]*\.hs-legendary, \.hs-semi, \.hs-refuted\)::before/.test(csrc)) bad('부흥 세력의 깃대 규칙이 전설 · 반전설 · 부정됨 띠의 안개(::before)를 덮음');
  if (!/:is\(\.hs-legendary, \.hs-semi\):is\([^)]*\.fam-dep[^)]*\) \{ --fog: 10%; \}/.test(csrc)) bad('종속 갈래 · 망명 · 부흥 세력 띠의 안개가 보통 띠보다 짙음 (--fog 목록)');
  if (model) {
    const sc = (model.scopes || []).find(s => s.afterHost && s.host);
    if (!sc) bad('견본에 본국이 끝난 뒤의 대범위(부흥 운동)가 없음');
    else if (!sc.members.some(p => (p.predecessors || []).some(e => e.from === sc.host && e.type === 'revival'))) bad('견본의 부흥 세력이 본국을 부흥(revival)으로 잇지 않음 — 부흥선 묶음이 그려지지 않음');
  }
}

/* ㉑ 지위 변천 · 섬긴 기록 · 활동 시기의 미정(칸의 미정과 같은 규칙) + 인물 창의 서명한 조약:
   "미정" 글 · 짧은 꼴 · startHint · startUnknown과 숫자를 읽어 파일에는 startUnknown(+ 배치용 연도 숫자)으로 남기고, 둘째 칸부터도 시작이 미정이면 버리지 않음 ·
   모델이 배치용 연도 → 앞 지위의 끝 → 정권의 처음으로 자리를 잡고(HT.placeCells) 미정 표시를 지위 구간 · 섬긴 구간에 싣는지 · 왕복 · 형식 2 ·
   폼 줄이 '미정'과 배치용 연도(data-start-hint)를 담는지 · 조약 서명자 ↔ 인물이 양쪽으로 이어지는지(signedTreaties) · 옛 지위 변천은 미정 표시가 없는지 */
{
  const bad = msg => out.problems.push(`지위 · 섬긴 기록의 미정: ${msg}`);
  const mk = (extra = {}) => Object.assign({ format: HT.FORMAT, id: 'smoke-unk2', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }] }, extra);
  const src = mk({
    periods: [
      { id: 'a', track: 'smoke-t', name: '가', start: 100, end: 500, ranks: [['공', null, 200], ['왕', '미정', 300], { name: '황제', start: 320, end: '모름', endHint: 420 }, { name: '왕', startUnknown: true }] },
      { id: 'b', track: 'smoke-t', name: '나', start: 100, end: 500, ranks: [{ name: '백', start: '미정', startHint: 150, end: 250 }, ['공', 250], { name: '둘다', start: '미정', end: '미정' }] },
    ],
    figures: [
      { id: 'f-a', track: 'smoke-t', name: '갑', start: 120, service: [{ polity: '가', office: '장군', start: '미정', end: 180 }, { polity: '가', start: 200, end: '미정', endHint: 260 }] },
      { id: 'f-b', track: 'smoke-t', name: '을', start: '미정', startHint: 330, end: 380, service: ['나'] },
      { id: 'f-c', track: 'smoke-t', name: '병', birth: 400, death: 460, start: '?', end: '불명' },
    ],
    events: [{ id: 'e-t', track: 'smoke-t', title: '검사 조약', start: 350, category: 'diplomacy', treaty: { parties: [{ polity: '가', side: 1, signatories: '갑(장군)' }, { polity: '나', side: 2, signatories: [{ name: '을' }, { name: '없는 사람' }] }] } }],
    patches: [{ target: 'smoke-other/x', set: { ranks: [['패치 지위', '미정', 50]], service: [{ polity: '어느 나라', start: '미정', end: 90 }] } }],
  });
  const r = HT.normalizePack(src);
  if (!r.pack) bad(`검사용 팩이 정규화되지 않음 (${r.errors.map(e => e.msg).join(' / ')})`);
  else {
    const P = Object.fromEntries(r.pack.periods.map(p => [p.id, p]));
    const A = P.a.ranks || [];
    if (A.map(c => c.name).join() !== '공,왕,황제,왕') bad(`시작이 미정인 지위가 빠지거나 차례가 틀림 (${A.map(c => c.name).join()})`);
    else {
      if (!A[1].startUnknown || 'start' in A[1] || A[1].end !== 300) bad(`짧은 꼴 ["왕", "미정", 300]이 startUnknown + 끝으로 남지 않음 (${JSON.stringify(A[1])})`);
      if (!A[2].endUnknown || A[2].end !== 420) bad(`"모름" + endHint가 endUnknown + 배치용 연도로 남지 않음 (${JSON.stringify(A[2])})`);
      if (!A[3].startUnknown || 'start' in A[3]) bad(`startUnknown: true가 남지 않음 (${JSON.stringify(A[3])})`);
    }
    const B = P.b.ranks || [];
    if (!B[0] || !B[0].startUnknown || B[0].start !== 150) bad(`startHint가 배치용 연도(start 숫자)로 남지 않음 (${JSON.stringify(B[0])})`);
    if (!r.warnings.some(w => /둘다/.test(w.msg) && /모두 미정/.test(w.msg))) bad('시작 · 끝이 모두 미정이고 배치용 연도가 없는 지위에 알림이 없음');
    const [fa, fb, fc] = r.pack.figures;
    if (!fa.service[0].startUnknown || 'start' in fa.service[0] || fa.service[0].end !== 180) bad(`섬긴 기록의 시작 "미정"이 startUnknown으로 남지 않음 (${JSON.stringify(fa.service[0])})`);
    if (!fa.service[1].endUnknown || fa.service[1].end !== 260) bad(`섬긴 기록의 끝 "미정" + endHint가 배치용 연도로 남지 않음 (${JSON.stringify(fa.service[1])})`);
    if (!fb.startUnknown || fb.start !== 330 || fb.end !== 380) bad(`활동 시작의 "미정" + startHint가 startUnknown + 배치용 연도로 남지 않음 (${JSON.stringify(fb)})`);
    if (!fc.startUnknown || !fc.endUnknown || 'start' in fc || 'end' in fc) bad(`활동 시기의 "?" · "불명"이 미정으로 남지 않음 (${JSON.stringify(fc)})`);
    const ps = (r.pack.patches[0] || {}).set || {};
    if (!ps.ranks || !ps.ranks[0].startUnknown || ps.ranks[0].end !== 50) bad(`패치의 지위 변천이 같은 규칙으로 다시 정리되지 않음 (${JSON.stringify(ps.ranks)})`);
    if (!ps.service || !ps.service[0].startUnknown || ps.service[0].end !== 90) bad(`패치의 섬긴 기록이 같은 규칙으로 다시 정리되지 않음 (${JSON.stringify(ps.service)})`);
    /* 왕복 · 형식 */
    const json = HT.packToJSON(r.pack);
    const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (!back.pack || canon(HT.packToJSON(back.pack)) !== canon(json)) bad('정규화 → 내보내기 → 정규화에서 미정 칸이 달라짐');
    if (json.formatVersion !== 2) bad('미정을 쓴 지위 변천 · 인물이 형식 2로 나가지 않음');
    /* 모델: 자리 잡기와 표시 */
    const m = HT.buildModel([r.pack], null);
    const pa = m.periods.find(p => p.name === '가');
    const pb = m.periods.find(p => p.name === '나');
    const sp = (pa && pa.rankSpans) || [];
    const at = i => (sp[i] ? [sp[i].start, sp[i].end, !!sp[i].startUnknown, !!sp[i].endUnknown].join() : '');
    if (at(0) !== '100,200,false,false') bad(`첫 지위(시작 비움)의 자리가 정권 시작 ~ 적은 끝이 아님 (${at(0)})`);
    if (at(1) !== '200,300,true,false') bad(`시작이 미정인 지위가 앞 지위의 끝에 놓이지 않음 (${at(1)})`);
    if (at(2) !== '320,420,false,true') bad(`끝이 미정인 지위가 배치용 연도까지 놓이지 않음 (${at(2)})`);
    if (at(3) !== '420,500,true,false') bad(`시작이 미정인 마지막 지위가 앞 지위의 끝 ~ 정권 끝에 놓이지 않음 (${at(3)})`);
    if (sp[1] && !sp[1].startAuto) bad('짐작한 시작에 startAuto 표시가 없음');
    if (pa && pa.ranks && pa.ranks.some(c => c.startAuto || c.endAuto)) bad('모델이 짐작한 자리가 원문 p.ranks에 섞임');
    const sb = (pb && pb.rankSpans) || [];
    if (!sb[0] || sb[0].start !== 150 || !sb[0].startUnknown || sb[0].startAuto) bad(`배치용 연도가 있는 미정인 첫 지위가 그 자리에 놓이지 않음 (${sb[0] && [sb[0].start, sb[0].startAuto]})`);
    if (sp[1] && !(HT.cellSpan(sp[1], pa).hi > 300 && HT.cellSpan(sp[1], pa).hi < 301)) bad(`시작이 미정인 지위의 적은 끝(300)이 조명에서 그해 끝까지가 아님 (${HT.cellSpan(sp[1], pa).hi})`);
    const F = Object.fromEntries(m.figures.map(f => [f.name, f]));
    const s0 = F['갑'] && F['갑'].services[0];
    if (!s0 || s0.from !== 120 || !s0.fromUnknown || s0.toUnknown) bad(`시작이 미정인 섬긴 기록이 비운 것과 같은 자리(활동 시작)에 미정 표시와 함께 놓이지 않음 (${s0 && [s0.from, s0.fromUnknown]})`);
    const s1 = F['갑'] && F['갑'].services[1];
    if (!s1 || s1.to !== 260 || !s1.toUnknown) bad('끝이 미정인 섬긴 기록이 배치용 연도까지 놓이지 않음');
    const fbm = F['을'];
    if (!fbm || fbm.start !== 330 || fbm.startAuto || !fbm.services[0].fromUnknown || HT.figureRange(fbm) !== `미정 ~ ${HT.formatDate(380)}`) bad(`활동 시작이 미정인 인물의 자리 · 물려받은 섬긴 기간의 미정 · 기간 글이 틀림 (${fbm && [fbm.start, HT.figureRange(fbm)]})`);
    const fcm = F['병'];
    if (!fcm || fcm.start !== 400 || fcm.endY !== 460 || !fcm.startAuto || HT.figureRange(fcm) !== '미정 ~ 미정') bad(`배치용 연도 없는 미정 활동 시기가 생몰에 놓이지 않거나 글이 '미정 ~ 미정'이 아님 (${fcm && [fcm.start, fcm.endY, HT.figureRange(fcm)]})`);
    /* 서명한 조약: 조약 창의 서명자 → 인물 · 인물 창 → 조약 */
    const tr = m.events.find(e => e.title === '검사 조약');
    const signers = tr && tr.treatyRefs ? tr.treatyRefs.parties.flatMap(p => p.signatories) : [];
    if (!signers.find(s => s.name === '갑' && s.figureUid === (F['갑'] || {}).uid)) bad('조약의 서명자가 같은 이름의 인물과 이어지지 않음');
    const signed = (F['을'] || {}).signedTreaties || [];
    if (signed.length !== 1 || signed[0].event !== tr || signed[0].party.name !== '나') bad(`인물 쪽에 서명한 조약(signedTreaties — 조약 · 당사국)이 없음 (${signed.length})`);
    if ((F['병'] || {}).signedTreaties) bad('서명하지 않은 인물에 서명한 조약이 생김');
    if (tr && tr.treaty && JSON.stringify(tr.treaty).includes('figureUid')) bad('서명자의 인물 연결이 원래 treaty 칸(파일)에 섞임');
  }
  /* 폼 줄 (글로만): 미정이면 칸에 '미정', 배치용 연도는 줄의 data-start-hint · data-end-hint에 — fill → read 왕복에서 줄지 않게 */
  const rk = HT.rankRowHTML(HT.formCell('ranks', { name: '왕', startUnknown: true, start: 470, end: '미정' }));
  if (!/data-start-hint="470"/.test(rk) || (rk.match(/value="미정"/g) || []).length !== 2) bad('지위 변천 줄이 미정과 배치용 연도를 담지 않음');
  if (/data-start-hint/.test(HT.rankRowHTML(HT.formCell('ranks', { name: '왕', start: 470 })))) bad('미정이 아닌 지위 줄에 배치용 연도가 붙음');
  const sv = HT.serviceRowHTML([], { polity: '가', startUnknown: true, start: 120, end: 180 });
  if (!/data-start-hint="120"/.test(sv) || !/value="미정"/.test(sv)) bad('섬긴 기록 줄이 미정과 배치용 연도를 담지 않음');
  const ff = HT.figureFieldsHTML({ tracks: [{ id: 'smoke-t', name: '검사' }] });
  if (!/name="startUnknown"/.test(ff) || !/name="endUnknown"/.test(ff)) bad('인물 폼의 활동 시작 · 끝에 미정 체크가 없음');
  /* 옛 자료: 미정이 없는 지위 변천은 모델이 자리 잡기를 지나지 않아 미정 표시가 없음 (그리는 모습이 1px도 같게) */
  if (model) for (const p of model.periods) if ((p.rankSpans || []).some(c => 'startUnknown' in c || 'endUnknown' in c) && !(p.ranks || []).some(c => c.startUnknown || c.endUnknown)) bad(`미정이 없는 지위 변천(${p.name})의 구간에 미정 표시가 붙음`);
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  if (!/const unk = unkCell\(c, j && strip\[j - 1\]\.it, jl, w, text \? textWidth\(text, (9\.5|fs), 600\) : null/.test(tsrc)) bad('연표의 지위 칸이 칸의 미정 모습(unkCell)을 쓰지 않음 (_rankCells)'); // fs = 9.5 (렌즈로 지도자 칸 자리에 그릴 때만 11.5 — 설계 7-8 결정 5 A)
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  if (!/서명한 조약 <small>/.test(vsrc) || !/x\.signedTreaties/.test(vsrc)) bad('인물 창에 서명한 조약 목록이 없음 (figureDetailHTML)');
}

/* ㉒ 통합 마무리(그림 내보내기 · 작은 빈틈 · 범례): 책갈피 탭의 글을 화면과 그림 내보내기가 같은 함수(Timeline.tabParts)로 정하는지 — 노드에서 js/timeline.js를 읽어
   기본팩 + 모든 견본의 정권마다 여러 폭으로 돌려 옛 종류(연맹 · 조직 · 시대 — 종속국은 ㉜부터 딱지 없음)에도 딱지 · 실재성 딱지 · 지위 딱지는 다 들어갈 때만 · 폭이 늘면 글이 줄지 않음 · 탭 폭을 넘지 않음을 보고,
   글로 읽어: 그림 내보내기가 옛 종류의 딱지를 빼던 규칙이 없어졌는지 · 속국 이름표의 미정 끝 · 시기 칸과 가문 줄의 옅어짐 · 접힌 줄의 이름 · 잘린 미정 띠의 모서리(시작 쪽 cut-l만 — 끝 쪽은 옛 화면 그대로) ·
   가문 줄의 미정 · 모여드는 움직임의 기관 칸과 할거 단추(data-band) · 키보드로 누른 단추(click detail 0) · 승계선의 이름표 비키기 · 전설 + 전승 연대 빗금의 제외 목록 ·
   표 보기 CSV의 실재성 열 · 조명 메아리 설명(범례 · 표시 체크)이 시기 · 지위 칸과 인물을 말하는지 */
{
  const bad = msg => out.problems.push(`통합 마무리(탭 · 그림 · 빈틈): ${msg}`);
  try {
    if (!HT.Timeline) vm.runInThisContext(readFileSync(join(root, 'js/timeline.js'), 'utf8'), { filename: 'js/timeline.js' });
  } catch (e) {
    bad(`js/timeline.js를 노드에서 읽지 못함 — ${e.message}`);
  }
  const TL = HT.Timeline;
  if (!TL || typeof TL.tabParts !== 'function' || typeof TL.tabRank !== 'function') bad('Timeline.tabParts · tabRank(책갈피 탭의 글 — 화면 · 그림 공용)가 없음');
  else if (model) {
    const OLD = { federation: '연맹', org: '조직', era: '시대' }; // 종속국(vassal)은 종속 갈래라 딱지 없음 — 상국 띠의 속국 이름표로 (㉜)
    const rank = { '': 0, short: 1, full: 2 };
    let seenOld = 0;
    let seenRk = 0;
    for (const p of model.periods) {
      if (p.polityKind === 'dynasty' || !p.name) continue;
      const rk = TL.tabRank(p, {}, 0);
      if (rk && TL.tabRank(p, { ranks: false }, 0)) bad(`${p.name}: 표시 체크 '지위'를 꺼도 탭에 지위 딱지가 붙음`);
      let prev = -1;
      for (const room of [0, 6, 12, 24, 48, 96, 192, 384, 768]) {
        const t = TL.tabParts(p, room, rk);
        if (rank[t.mode] < prev) bad(`${p.name}: 탭이 넓어졌는데 글이 줄어듦 (${room}px)`);
        prev = rank[t.mode];
        if (t.mode && t.width > room + 1e-9) bad(`${p.name}: 탭의 글이 탭 폭을 넘음 (${t.width.toFixed(1)} > ${room})`);
        if (t.rk && t.mode !== 'full') bad(`${p.name}: 이름을 줄였는데 지위 딱지가 남음`);
      }
      const full = TL.tabParts(p, 1e6, rk);
      if (full.mode !== 'full') bad(`${p.name}: 넉넉한 탭에 이름이 다 들어가지 않음`);
      if (rk && full.rk !== rk) bad(`${p.name}: 넉넉한 탭에 지위 딱지가 없음`);
      if (rk) seenRk++;
      if (OLD[p.polityKind]) {
        seenOld++;
        if (!full.kds.length || full.kds[0].t !== OLD[p.polityKind]) bad(`${p.name}: 옛 종류(${p.polityKind})의 탭 딱지가 없음 — 그림 내보내기와 화면이 다름`);
      }
      const hs = HT.historicityOf(p);
      if (hs && full.hsTag !== HT.historicityTag(hs)) bad(`${p.name}: 실재성 딱지가 탭에 없음`);
    }
    if (!seenOld) bad('견본에 옛 종류(연맹 · 조직체 · 시대 이름)의 정권이 없어 탭 딱지를 보지 못함');
    if (!seenRk) bad('견본에 지위가 하나뿐인 정권이 없어 탭의 지위 딱지를 보지 못함');
  }
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const svgSrc = tsrc.slice(tsrc.indexOf('    toSVG({'));
  const drawSrc = tsrc.slice(tsrc.indexOf('    _drawTrack(tr, X, W) {'), tsrc.indexOf('    _laneKey(tr, cats, row) {'));
  const tabCall = /const tp = tabParts\(p, [^\n]*tabRank\(p, this\.show, geoOf\(p\._row\)\.rankH\), TAB\.ext \* 2\);/; // 간지 탭(묶음 3 · 1번)의 어깨 몫까지 같은 호출
  if (!tabCall.test(drawSrc) || !tabCall.test(svgSrc)) bad('화면(_drawTrack)과 그림 내보내기(toSVG)가 같은 탭 결정(tabParts · tabRank)을 부르지 않음');
  if (/oldKind/.test(svgSrc)) bad('그림 내보내기가 아직 옛 종류의 탭 딱지를 뺌 (화면에는 있음)');
  if (!/const fl = \(s, jl, w\) => \(s\.h\.startUnknown && !jl \? Math\.min\(FADE, w \* 0\.4\) : 0\);/.test(tsrc)) bad('그림 내보내기의 속국 이름표에서 미정인 소속 끝이 옅어지지 않음');
  if (!/fill="\$\{PAPER\}" fill-opacity="0\.8" stroke="\$\{mixHex\(MUTED, PAPER, 0\.7\)\}"\$\{mask\}/.test(svgSrc)) bad('그림 내보내기의 시기 칸이 미정인 끝에서 옅어지지 않음');
  if (!/fill="\$\{edge\(hr\.color, 0\.72\)\}"\$\{mask\}/.test(svgSrc)) bad('그림 내보내기의 가문 줄이 미정 칸과 함께 옅어지지 않음');
  if (!/tr\.groups\.find\(x => x\.first === row && x\.folded\)/.test(svgSrc)) bad('그림 내보내기의 접힌 줄 이름이 화면(접힌 묶음 · 대범위 가지의 이름)과 다름');
  if (!/x1 < -1 && p\.startUnknown \? ' cut-l' : ''/.test(drawSrc)) bad('시작 미정 띠가 화면 왼쪽을 넘을 때 모서리를 펴지 않음 (cut-l — 탭 아래 틈)');
  if (/cut-r/.test(drawSrc)) bad('끝이 미정인 띠가 화면 오른쪽을 넘을 때도 모서리를 폄 (cut-r — 옛 자료의 화면이 바뀜, 지시는 탭이 붙는 왼쪽만)');
  if (!/unks\.get\(u\.first\)/.test(tsrc) || !/tl-houseline\$\{[^\n]*unk-s/.test(tsrc)) bad('화면의 가문 줄이 미정 칸과 함께 옅어지지 않음');
  if (!/data-k="o:[^\n]*data-band="\$\{esc\(host\.uid\)\}"/.test(tsrc) || !/data-k="sb:[^\n]*data-band="\$\{esc\(p\.uid\)\}"/.test(tsrc)) bad('기관 칸 · 할거 단추에 그려지는 띠(data-band)가 없음 — 모여드는 움직임에서 제 띠를 따라가지 못함');
  if (!/if \(e\.detail !== 0 \|\| !e\.target\.closest\) return;/.test(tsrc) || !/pressButton\(b, \(\) => \{\}\)/.test(tsrc)) bad('연표의 단추(민족 딱지 …)를 키보드(Enter · Space)로 누를 수 없음');
  if (!/xv = lab\.r \+ 6 \+ k \* 5;/.test(tsrc)) bad('승계선의 세로 통로가 대범위 이름표를 비켜 가지 않음');
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  if (!/\.tl-lane \.tl-band\.unk-s\.cut-l \{ border-top-left-radius: 0; border-bottom-left-radius: 0; \}/.test(csrc)) bad("common.css에 잘린 미정 띠의 모서리 규칙(cut-l)이 없음");
  if (/cut-r/.test(csrc)) bad('common.css에 끝 쪽 잘린 미정 띠의 모서리 규칙(cut-r)이 남음 — 옛 자료의 화면이 바뀜');
  if (!/\.tl-houseline:is\(\.unk-s, \.unk-e\) \{/.test(csrc)) bad('common.css에 가문 줄의 미정 규칙이 없음');
  if (!/\.tl-lane \.tl-band:is\(\.hs-legendary, \.hs-semi\)\.cert-legend:not\(\.kind-vassal, \.fam-dep, \.kind-exile, \.kind-movement, \.kind-federation, \.kind-org, \.kind-era, \.unk-s, \.unk-e\)::before/.test(csrc)) bad('전설 · 반전설 + 전승 연대의 종속 갈래 띠에 안개 빗금이 생김 (보통 종속 띠의 전승에는 빗금 없음)');
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  if (!/head\.push\('실재성'\)/.test(vsrc) || !/HT\.historicityOf\(x\) \? HT\.historicityName\(HT\.historicityOf\(x\)\) : '', \/\/ 실재성/.test(vsrc)) bad('표 보기 CSV에 실재성 열이 없음 (표에는 딱지로 보임)');
  if (!/칸 기간 조명: 띠 안의 지도자·내각·시기·지위 칸/.test(vsrc) || !/인물 창을 열면 활동한 띠마다/.test(vsrc)) bad('범례의 칸 기간 조명 · 조명 메아리 설명에 시기 · 지위 칸 · 인물이 없음');
  const indexHtml = readFileSync(join(root, 'index.html'), 'utf8');
  if (!/왕조 · 시기 · 지위\)이나 인물을 골라[^"]*"><input id="spotEchoToggle" type="checkbox"> 같은 시기를 타국에도<\/label>/.test(indexHtml)) bad("index.html의 표시 체크 '같은 시기를 타국에도' 설명에 시기 · 지위 칸 · 인물이 없거나 이름이 다름");
}

/* ㉓ 검토 반영(지위 변천 · 섬긴 기록의 미정): 시작이 미정인 칸을 목록 맨 끝에 적어도 제 끝의 자리에 서는지(HT.sortCells와 같은 차례 —
   같은 해에 끝나는 칸이 그해에 시작하는 칸보다 앞) · 지도자 칸과 같은 자리에 놓이는지 · 앞 칸 안에서 끝나 피할 수 없이 겹치면 알리는지 ·
   미정인 시작의 배치용 연도가 적은 끝보다 뒤면 적은 끝이 아니라 배치용 연도를 버리는지(지위 · 섬긴 기록 · 시기 · 도읍 — 인물 활동 시기와 같은 규칙) ·
   인물 폼이 미정 체크를 날짜 칸보다 먼저 채우는지(처음부터 미정 모양 — 글로만) */
{
  const bad = msg => out.problems.push(`지위 · 섬긴 기록의 미정 검토 반영: ${msg}`);
  const P = { start: 0, end: 700 };
  const spansOf = ranks => ((HT.resolveRanks(Object.assign({ ranks }, P), HT.RANKS) || {}).spans || []).map(s => `${s.name}:${s.start}~${s.end}`).join(' ');
  const leadersOf = list => HT.placeCells(HT.sortCells(list), P).map(c => `${c.name}:${c.start}~${c.end}`).join(' ');
  for (const [what, tail] of [['끝이 다음 지위의 시작보다 앞섬', 350], ['끝이 다음 지위의 시작과 같은 해', 400]]) {
    const ranks = [['공', 100, 200], ['황제', 400], { name: '왕', start: '미정', end: tail }];
    const rr = HT.readRanks(ranks);
    if (rr.list.map(c => c.name).join() !== '공,왕,황제') bad(`맨 끝에 적은 시작 미정 지위가 제 끝의 자리에 서지 않음 — ${what} (${rr.list.map(c => c.name).join()})`);
    const want = `공:100~200 왕:200~${tail} 황제:400~700`;
    if (spansOf(ranks) !== want) bad(`맨 끝에 적은 시작 미정 지위가 앞 지위의 끝에서 시작하지 않음 — ${what} (${spansOf(ranks)})`);
    const cells = [{ name: '공', start: 100, end: 200 }, { name: '황제', start: 400 }, { name: '왕', startUnknown: true, end: tail }];
    if (leadersOf(cells) !== `공:100~200 왕:200~${tail} 황제:400~undefined`) bad(`지도자 칸(HT.sortCells + HT.placeCells)이 같은 자리에 놓지 않음 — ${what} (${leadersOf(cells)})`);
    if (rr.warnings.length) bad(`겹치지 않는 지위에 알림이 뜸 (${rr.warnings.join(' / ')})`);
  }
  if (!HT.readRanks([['공', 100, 300], { name: '왕', start: '미정', end: 250 }]).warnings.some(w => /겹칩니다/.test(w))) bad('앞 지위 안에서 끝나 피할 수 없이 겹치는 시작 미정 지위에 알림이 없음');
  if (HT.readRanks([['공', 100, 300], { name: '왕', start: '미정', end: 300 }]).warnings.length) bad('앞 지위의 끝에서 끝나는 시작 미정 지위(겹치지 않음)에 알림이 뜸');
  if (canon(HT.sortCells([{ start: 350 }, { startUnknown: true, end: 350 }, { startUnknown: true }])) !== canon([{ startUnknown: true, end: 350 }, { start: 350 }, { startUnknown: true }])) bad('HT.sortCells가 같은 해에 끝나는 시작 미정 칸을 그해에 시작하는 칸 앞에 두지 않음');
  /* 거꾸로 된 배치용 연도: 짐작(배치용 연도)을 버리고 적은 날짜는 남김 */
  const r1 = HT.readRanks([{ name: '공', start: '미정', startHint: 400, end: 380 }]);
  if (canon(r1.list) !== canon([{ name: '공', startUnknown: true, end: 380 }]) || !r1.warnings.some(w => /시작의 배치용 연도를 버렸습니다/.test(w))) bad(`지위: 미정인 시작의 배치용 연도가 적은 끝보다 뒤일 때 적은 끝을 버림 (${canon(r1.list)})`);
  const r2 = HT.readRanks([{ name: '공', start: 300, end: '미정', endHint: 250 }]);
  if (canon(r2.list) !== canon([{ name: '공', start: 300, endUnknown: true }])) bad(`지위: 미정인 끝의 배치용 연도가 시작보다 앞일 때 그 배치용 연도를 버리지 않음 (${canon(r2.list)})`);
  const r3 = HT.readRanks([{ name: '공', start: 300, end: 250 }]);
  if (canon(r3.list) !== canon([{ name: '공', start: 300 }])) bad(`지위: 적은 끝이 적은 시작보다 앞일 때 예전처럼 끝을 비우지 않음 (${canon(r3.list)})`);
  const sv = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-unk3', name: '검사', tracks: [{ id: 'smoke-t', name: '검사 트랙' }], figures: [{ id: 'f-x', track: 'smoke-t', name: '정', start: 470, service: [{ polity: '가', start: '미정', startHint: 500, end: 480 }] }] });
  const s0 = sv.pack && sv.pack.figures[0].service[0];
  if (!s0 || canon(s0) !== canon({ polity: '가', startUnknown: true, end: 480 }) || !sv.warnings.some(w => /시작의 배치용 연도를 버렸습니다/.test(w.msg))) bad(`섬긴 기록: 미정인 시작의 배치용 연도가 적은 끝보다 뒤일 때 적은 끝을 버림 (${canon(s0)})`);
  const ph = HT.readPhases([{ name: '가', start: '미정', startHint: 400, end: 380 }]);
  if (!ph.list[0] || canon(ph.list[0].spans) !== canon([{ name: '가', startUnknown: true, end: 380 }])) bad(`시기: 미정인 시작의 배치용 연도가 적은 끝보다 뒤일 때 적은 끝을 버림 (${canon(ph.list[0] && ph.list[0].spans)})`);
  const cp = HT.normalizeCapital({ city: '가', start: '미정', startHint: 400, end: 380 });
  if (canon(cp) !== canon({ city: '가', startUnknown: true, end: 380 })) bad(`도읍: 미정인 시작의 배치용 연도가 적은 끝보다 뒤일 때 적은 끝을 버림 (${canon(cp)})`);
  /* 인물 폼: 미정 체크를 날짜 칸보다 먼저 (HT.fillRangeFields와 같은 차례) */
  const csrc = readFileSync(join(root, 'js/core.js'), 'utf8');
  const ffs = csrc.slice(csrc.indexOf('  HT.fillFigureForm = (form, f, { titles = null } = {}) => {'), csrc.indexOf('  HT.readServiceRows = (form, problems) =>'));
  const iChk = ffs.indexOf('el.startUnknown.checked = !!f.startUnknown');
  const iEndChk = ffs.indexOf('el.endUnknown.checked = !f.ongoing && !!f.endUnknown');
  const iWrite = ffs.indexOf("HT.writeDateField(form, 'start',");
  if (iChk < 0 || iEndChk < 0 || iWrite < 0 || iChk > iWrite || iEndChk > iWrite) bad('인물 폼이 활동 시기의 미정 체크를 날짜 칸보다 뒤에 채움 — 열었을 때 미정 모양 · 안내 줄이 안 나옴 (HT.fillFigureForm)');
}

/* ㉔ 통합 마무리(메이커 배선 f1): 바탕 자료의 지위 사전(rankDefs) · 가문(houses) 칸 — 견본 sample-lantern을 작업본으로 열고
   (인물 · 패치 · 하위 문서 · 가져온 기본 지위 · id와 별칭과 {rank}로 적은 지위의 참조를 더해) id · 이름을 바꾸면 모든 참조가 따라가는지(id로 적은 참조는 이름을 바꿔도 · 별칭은 그대로) ·
   정규화 오류 0 · 쓰는 곳 세기 · 가문 구성원과 지위 구간이 그대로인지, 비운 id를 작업본이 읽기와 같은 값으로 채우는지(내보내는 파일은 그대로),
   사건 폼의 조약 규격(끝낸 전쟁 · 대체한 조약)에 사건 제목 자동 완성이 들어가는지 */
{
  const bad = msg => out.problems.push(`통합 마무리(바탕 자료 · 자동 완성): ${msg}`);
  const kit = HT.makerKit;
  const D = HT.draft;
  try {
    const T = kit && kit.BASE_TABLES;
    if (!T || !T.houses || !T.rankDefs) bad('바탕 자료에 가문 · 지위 칸이 없음');
    else {
      for (const k of ['houses', 'rankDefs']) if (!D.LISTS.includes(k)) bad(`작업본의 목록에 ${k}가 없음 (바탕 자료에서 고친 것이 작업본에 실리지 않음)`);
      if (T.houses.docPrefix !== 'house' || T.rankDefs.docPrefix) bad('가문의 문서 머리글이 house가 아니거나 지위 사전에 문서가 달림');
      const rawL = JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8'));
      if (canon(HT.packToJSON(HT.normalizePack(rawL).pack)) !== canon(HT.packToJSON(HT.normalizePack(D.clean(rawL)).pack))) bad(`${rawL.id}: 작업본으로 열어 그대로 내보낸 파일이 원본과 다름`);
      const ren = (d, t, row, key, to) => {
        const n = kit.renameRefs(d, t, key, row[key], to);
        row[key] = to; // 바탕 자료 창이 그 칸에 새 값을 적는 것과 같게
        return n;
      };
      const count = users => Object.fromEntries([...new Set(users.map(u => u.list))].map(l => [l, users.filter(u => u.list === l).length]));

      /* 가문: 비운 id는 읽기와 같은 값 · 쓰는 곳 · id와 이름 바꾸기 (견본은 모두 id로 적었으므로 아무도 id로 가리키지 않는 '휘씨 본파'의 id를 비워 봄) */
      const strip = JSON.parse(JSON.stringify(rawL));
      delete strip.houses.find(h => h.id === 'h-hwi-bon').id;
      const dh = D.clean(strip);
      const bon = dh.houses.find(h => h.name === '휘씨 본파');
      const bonWant = HT.normalizePack(JSON.parse(JSON.stringify(strip))).pack.houses.find(h => h.name === '휘씨 본파');
      if (!bon || !bonWant || !bon.id || bon.id !== bonWant.id) bad(`id를 비운 가문에 작업본이 읽기와 다른 id를 줌: ${bon && bon.id} / ${bonWant && bonWant.id}`);
      dh.figures.push({ id: 'f-kit', track: 'hayeon', name: '가상 인물', birth: 1500, house: '휘씨 남파' });
      dh.patches.push({ target: 'other-dlc/x', set: { house: 'h-hwi-nam', leaders: [{ name: '갑', start: 1, house: '휘씨 남파' }], cabinets: [{ name: '을', start: 2, house: 'h-hwi-nam' }] } });
      dh.documents['house:h-hwi//계보'] = '하위 문서';
      const r0 = HT.normalizePack(dh);
      const m0 = r0.pack && HT.buildModel([r0.pack], null);
      const nam = dh.houses.find(h => h.id === 'h-hwi-nam');
      const hwi = dh.houses.find(h => h.id === 'h-hwi');
      const seo = dh.houses.find(h => h.id === 'h-seomok');
      const arh = dh.houses.find(h => h.id === 'h-ar');
      const ue = count(kit.findUsers(dh, T.houses, nam));
      // 견본 2.0.0: 남파는 시대 4(부흥국 · 연합 왕국 · 공화국 · 적석 재건) · 인물 2(남강군 · 시온)와 더한 인물 1 · 분가 1(청림지파) · 더한 패치 1
      if (JSON.stringify(ue) !== JSON.stringify({ periods: 4, figures: 3, houses: 1, patches: 1 })) bad(`가문(분가)의 쓰는 곳이 어긋남: ${JSON.stringify(ue)}`);
      const us = count(kit.findUsers(dh, T.houses, hwi));
      if (JSON.stringify(us) !== JSON.stringify({ periods: 1, figures: 11, houses: 2 }) || kit.usageText(kit.findUsers(dh, T.houses, hwi)) !== '객체 1 · 사람 11 · 가문 2') bad(`가문(본가)의 쓰는 곳이 어긋남: ${JSON.stringify(us)}`);
      const nh = [ren(dh, T.houses, nam, 'id', 'h-nam'), ren(dh, T.houses, nam, 'name', '남파'), ren(dh, T.houses, seo, 'name', '서목 집안'), ren(dh, T.houses, hwi, 'id', 'h-h'), ren(dh, T.houses, arh, 'id', 'h-a')];
      // 칸 단위: 남파 id 12(시대 7칸 · 인물 2 · 청림지파의 본가 · 패치 2) · 남파 이름 2 · 서목씨 이름 0 · 휘씨 id 14 + 문서 2 · 아르씨 id 15
      if (nh.join() !== '12,2,0,16,15') bad(`가문 id · 이름을 바꿀 때 따라 고친 곳의 수가 어긋남: ${nh.join()} (12,2,0,16,15여야 함)`);
      const P = id => dh.periods.find(p => p.id === id);
      const pt = dh.patches[dh.patches.length - 1].set;
      const seen = {
        연합국성: P('p-union').house, 쌍등왕: P('p-jeokseok2').leaders.find(c => c.name === '쌍등왕').house, 내각: P('p-union').cabinets.find(c => c.name === '휘 소담 내각').house, 단등왕: P('p-lantern').leaders.find(c => c.name === '단등왕').house,
        등불국성: P('p-lantern').house, 인물: dh.figures.find(f => f.id === 'f-kit').house, 남강군: dh.figures.find(f => f.id === 'f-namgang').house, 설왕조: dh.dynasties.find(x => x.id === 'd-seol').house, 남파의본가: nam.parent, 본파의본가: bon && bon.parent, 패치: [pt.house, pt.leaders[0].house, pt.cabinets[0].house].join('|'),
      };
      const want = { 연합국성: 'h-nam', 쌍등왕: 'h-nam', 내각: 'h-nam', 단등왕: 'h-seomok', 등불국성: 'h-h', 인물: '남파', 남강군: 'h-nam', 설왕조: 'h-a', 남파의본가: 'h-h', 본파의본가: 'h-h', 패치: 'h-nam|남파|h-nam' };
      if (JSON.stringify(seen) !== JSON.stringify(want)) bad(`가문 id · 이름을 바꿨는데 참조가 어긋남: ${JSON.stringify(seen)}`);
      if (!('house:h-h' in dh.documents) || !('house:h-h//계보' in dh.documents) || 'house:h-hwi' in dh.documents) bad(`가문 id를 바꿨는데 문서(house:id)가 따라가지 않음: ${Object.keys(dh.documents)}`);
      const r1 = HT.normalizePack(dh);
      if (!r1.pack || r1.errors.length || r1.warnings.length !== r0.warnings.length) bad(`가문을 바꾼 작업본의 검사가 어긋남: 오류 ${r1.errors.map(e => e.msg).join(' / ')} · 경고 ${r0.warnings.length} → ${r1.warnings.length}`);
      else if (m0) {
        const m1 = HT.buildModel([r1.pack], null);
        const idMap = { 'h-hwi-nam': 'h-nam', 'h-hwi': 'h-h', 'h-ar': 'h-a' };
        const sig = (m, map) => m.houses.map(h => `${map[h.id] || h.id}:${h.members.length}:${h.auto ? 'auto' : ''}:${h.parentId ? map[h.parentId] || h.parentId : ''}`).sort().join(',');
        if (sig(m0, idMap) !== sig(m1, {})) bad(`가문을 바꾼 뒤 가문 구성원 · 자동 가문 · 본가가 달라짐 (따라가지 못한 참조가 있음): ${sig(m0, idMap)} → ${sig(m1, {})}`);
        if ((m1.docs.get('house:h-h') || {}).text !== rawL.documents['house:h-hwi']) bad('가문 id를 바꾼 뒤 모델에서 그 가문의 문서가 떨어짐');
      }

      /* 지위 사전: 쓰는 곳(id · 이름 · 별칭) · id와 이름 바꾸기(칸의 세 꼴 — [이름, …] · { name } · { rank }) · 별칭은 세기만 */
      const dr = D.clean(rawL);
      const Q = id => dr.periods.find(p => p.id === id);
      Q('p-league').leaders[0].rank = 'pilot'; // id로 적은 지도자의 지위
      Q('p-khanate').ranks = [['칸']]; // [이름, …] 꼴 — 견본 2.0.0은 지위 변천을 모두 { name } 꼴로 적으므로 이 꼴은 여기서 만듦
      Q('p-north').ranks = [['대칸']]; // 별칭으로 적은 지위
      Q('p-coral').ranks = [{ rank: '왕' }]; // { rank } 꼴 — 아래에서 가져오는 기본 지위(왕)를 가리킴
      dr.patches.push({ target: 'other-dlc/y', set: { ranks: [{ name: '칸', start: 1 }], leaders: [{ name: '병', start: 1, rank: 'khan' }] } });
      dr.rankDefs.push(JSON.parse(JSON.stringify(HT.RANKS.find(r => r.id === 'king')))); // 바탕 자료의 "기본 지위 가져오기"와 같은 꼴
      if (!T.rankDefs.builtin || !T.rankDefs.builtin().some(r => r.id === 'king')) bad('지위 칸의 가져오기 후보에 기본 지위가 없음');
      const q0 = HT.normalizePack(dr);
      const n0 = q0.pack && HT.buildModel([q0.pack], null);
      const R = id => dr.rankDefs.find(r => r.id === id);
      const khan = R('khan');
      const pilot = R('pilot');
      const lamp = R('lamp-king');
      const king = R('king');
      const uses = [khan, pilot, lamp, king].map(r => kit.usageText(kit.findUsers(dr, T.rankDefs, r))).join(' / ');
      // 견본 2.0.0: 왕(king)을 쓰는 시대가 여덟(윗물 · 아랫물 · 부흥국 · 연합 왕국 · 적석 · 적석 재건 · 산호 섬나라 · 서해 삼부 왕국)
      if (uses !== '패치 1 · 객체 2 / 객체 1 / 객체 1 / 객체 8') bad(`지위의 쓰는 곳이 어긋남 (id · 이름 · 별칭): ${uses}`);
      const nr = [ren(dr, T.rankDefs, khan, 'id', 'khan2'), ren(dr, T.rankDefs, khan, 'name', '큰 칸'), ren(dr, T.rankDefs, pilot, 'name', '뱃길 우두'), ren(dr, T.rankDefs, lamp, 'name', '등불 임금'), ren(dr, T.rankDefs, king, 'name', '큰 왕'), kit.renameRefs(dr, T.rankDefs, 'aliases', '대칸', '큰 대칸')];
      if (nr.join() !== '1,2,1,1,8,0') bad(`지위 id · 이름을 바꿀 때 따라 고친 곳의 수가 어긋남: ${nr.join()} (1,2,1,1,8,0이어야 함)`);
      const rp = dr.patches[dr.patches.length - 1].set;
      const got = JSON.stringify([Q('p-khanate').ranks, Q('p-north').ranks, Q('p-lantern').ranks[0].name, Q('p-league').ranks, Q('p-league').leaders[0].rank, Q('p-coral').ranks, Q('p-jeokseok').ranks[1].name, Q('p-upper').ranks, rp.ranks[0].name, rp.leaders[0].rank]);
      if (got !== JSON.stringify([[['큰 칸']], [['대칸']], '등불 임금', [{ name: '뱃길 우두' }], 'pilot', [{ rank: '큰 왕' }], '큰 왕', [{ name: '큰 왕' }], '큰 칸', 'khan2']))
        bad(`지위 id · 이름을 바꿨는데 참조가 어긋남: ${got}`);
      const q1 = HT.normalizePack(dr);
      if (!q1.pack || q1.errors.length || q1.warnings.length !== q0.warnings.length) bad(`지위를 바꾼 작업본의 검사가 어긋남: 오류 ${q1.errors.map(e => e.msg).join(' / ')} · 경고 ${q0.warnings.length} → ${q1.warnings.length}`);
      else if (n0) {
        const n1 = HT.buildModel([q1.pack], null);
        const idMap = { khan: 'khan2' };
        const sig = (m, map) => m.periods.filter(p => p.rankSpans).map(p => `${p.id}:${p.rankSpans.map(s => (s.def ? map[s.def.id] || s.def.id : '-')).join('>')}`).sort().join(',');
        if (sig(n0, idMap) !== sig(n1, {})) bad(`지위를 바꾼 뒤 지위 구간이 가리키는 사전이 달라짐 (따라가지 못한 참조가 있음): ${sig(n0, idMap)} → ${sig(n1, {})}`);
        const co = n1.periods.find(p => p.id === 'p-coral');
        if (!co || !co.rankSpans[0].def || co.rankSpans[0].def.name !== '큰 왕' || co.rankSpans[0].name !== '큰 왕') bad('가져와 이름을 바꾼 기본 지위가 그 칸에 이어지지 않음');
      }
    }
    /* 사건 폼의 조약 규격: 끝낸 전쟁 · 대체한 조약에 사건 제목 자동 완성(선택 인자 — 없어도 폼이 그려짐) · 편집 창이 목록을 넘김 */
    const html = HT.FORMS.event.html({ tracks: [], categories: [], eventTitles: ['가 사건', '가 사건', ''], treatyTitles: ['나 조약'] });
    if (!/name="trConcludes"[^>]*list="mkTreatyEventList"/.test(html) || !/name="trSupersedes"[^>]*list="mkTreatyTreatyList"/.test(html)) bad('조약 규격의 끝낸 전쟁 · 대체한 조약 칸에 자동 완성 목록이 붙지 않음');
    if (!html.includes('<datalist id="mkTreatyEventList"><option value="가 사건"></option></datalist>') || !html.includes('<datalist id="mkTreatyTreatyList"><option value="나 조약"></option></datalist>')) bad('조약 규격의 사건 제목 자동 완성 목록이 어긋남 (겹친 제목 · 빈 제목은 한 번 · 빼야 함)');
    if (!HT.FORMS.treaty.html({ tracks: [], categories: [] }).includes('<datalist id="mkTreatyEventList"></datalist>')) bad('목록을 넘기지 않은 조약 폼이 그려지지 않음');
    if (!/F\.html\(\{[^\n]*eventTitles, treatyTitles \}\)/.test(readFileSync(join(root, 'js/viewer.js'), 'utf8'))) bad('편집 창(fillEditor)이 폼에 사건 제목 목록을 넘기지 않음');
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ㉕ 통합 마무리(메이커 배선 f2): 메이커의 대범위 편집 — 작업본의 목록 · 항목 목록에 scopes(추가 메뉴에 있고 단축키 없음 · 바탕 자료의 대범위 칸) ·
   비운 id를 작업본이 HT.normalizePack과 같은 값으로 채우는지(씨앗 트랙 + 이름 + 시작 해 · "미정" 시작 · 시대 구분만 적은 것 · 겹친 id의 "-2" 차례) ·
   작업본에 대범위 추가 → 고침 → 반영(형식 2) · 파일 왕복 · 지우면 문서도 · 트랙 참조를 두 번 보지 않는지 · 검사의 대범위 경고와 '승계 줄이 나뉘는' 알림(HT.makerKit.scopeChecks) ·
   편집 창 · 상세 · 우클릭이 한 판단(paneEditable)을 쓰고 폼에 시대 구분 · 정권 목록을 넘기는지(글로만 읽음) */
{
  const bad = msg => out.problems.push(`통합 마무리(대범위 편집): ${msg}`);
  const kit = HT.makerKit;
  const D = HT.draft;
  try {
    if (!D.LISTS.includes('scopes')) bad('작업본의 목록에 scopes가 없음');
    if (!HT.FORMS.scope || HT.FORMS.scope.add === false || HT.FORMS.scope.key) bad('대범위가 메이커의 추가 메뉴에 없거나 단축키가 붙음');
    if (!kit.itemLists().includes('scopes') || kit.kindOfList('scopes') !== 'scope' || kit.listWord('scopes') !== '대범위') bad('메이커의 항목 목록(itemLists · kindOfList)에 대범위가 없음');
    if (!kit.BASE_TABLES.scopes || kit.BASE_TABLES.scopes.form !== 'scope') bad('바탕 자료에 대범위 칸(편집 창의 폼으로 고침)이 없음');
    if (HT.USER_LISTS.some(l => l.list === 'scopes')) bad('대범위가 내 데이터 목록에 들어감 (연표에서는 고치지 않음)');
    const trackSpecs = kit.BASE_TABLES.tracks.refs.id.filter(s => [].concat(typeof s.list === 'function' ? s.list() : s.list).includes('scopes') && s.path === 'track');
    if (trackSpecs.length !== 1) bad(`트랙 id 바꾸기가 대범위의 트랙 칸을 ${trackSpecs.length}번 봄 (한 번이어야 함)`);

    /* 비운 id: 작업본이 채운 id = 파일을 읽을 때 매길 id (반영 뒤 uid가 바뀌지 않게) */
    const rawS = JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8'));
    const strip = JSON.parse(JSON.stringify(rawS));
    for (const s of strip.scopes) delete s.id;
    strip.scopes.push(
      { track: 'hayeon', name: '미정 대범위', start: '미정', startHint: 455, end: 500, members: ['갈대 공국'] },
      { track: 'hayeon', name: '미정 대범위', start: '미정', end: 470, members: ['윗물국'] },
      { track: 'hayeon', name: '아홉 불씨 할거', start: 412, end: 600, members: ['갈대 공국'] }, // 첫 대범위와 같은 씨앗 → "-2"
      { track: 'sanho', epoch: '해상 동맹기', start: '1100-03', members: ['새물섬'] },
      { id: 'p-reed', track: 'hayeon', name: '같은 id', members: ['갈대 공국'] } // 시대와 같은 id를 적은 대범위 — 읽기는 대범위가 먼저라 시대 쪽이 "-2"
    );
    const nStrip = HT.normalizePack(JSON.parse(JSON.stringify(strip)));
    const cl = D.clean(strip);
    const nClean = HT.normalizePack(cl);
    const ids = p => (p.scopes || []).map(s => s.id).join(',');
    if (!nStrip.pack || !nClean.pack) bad('id를 비운 대범위 견본이 검사를 통과하지 못함');
    else {
      if (cl.scopes.map(s => s.id).join(',') !== ids(nStrip.pack)) bad(`작업본이 채운 대범위 id가 읽기와 다름: ${cl.scopes.map(s => s.id).join(',')} ≠ ${ids(nStrip.pack)}`);
      if (canon(HT.packToJSON(nClean.pack)) !== canon(HT.packToJSON(nStrip.pack))) bad('id를 비운 대범위 견본을 작업본으로 열면 내보낸 파일이 읽기와 달라짐 (시대 · 대범위의 id 차례)');
      if (nClean.warnings.length !== nStrip.warnings.length - 1) bad(`작업본으로 연 뒤의 경고 수가 어긋남 (${nStrip.warnings.length} → ${nClean.warnings.length} — 겹친 id 경고 하나만 사라져야 함)`);
    }

    /* 추가 → 고침 → 반영 · 파일 왕복 → 지우기 */
    const d = D.clean(rawS);
    const id = D.addItem(d, 'scope', { name: '새 대범위', track: 'hayeon', label: '시대', start: 430, end: 480, members: ['윗물국', 'hayeon:아랫물국', { track: 'hayeon', polity: '갈대 공국' }], description: '', note: '', default: true });
    if (!/^s-/.test(id) || !D.findOwn(d, id) || D.findOwn(d, id).list !== 'scopes') bad(`작업본에 넣은 대범위가 scopes 목록에 없음 (${id})`);
    D.setDoc(d, `${d.id}/${id}`, '문서 본문');
    const r1 = HT.normalizePack(d);
    const s1 = r1.pack && r1.pack.scopes.find(s => s.id === id);
    if (!s1 || s1.members.length !== 3 || s1.default !== true) bad('작업본에 넣은 대범위가 정규화에서 빠지거나 칸이 줄어듦');
    const ch = D.changes(r1.pack, HT.normalizePack(rawS).pack);
    if (!ch.some(c => c.list === 'scopes' && c.type === 'add' && /대범위 추가/.test(c.label))) bad(`반영하지 않은 고침에 새 대범위가 잡히지 않음: ${JSON.stringify(ch.map(c => c.label))}`);
    const json = HT.packToJSON(r1.pack);
    const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (json.formatVersion < 2 || !back.pack || canon(HT.packToJSON(back.pack)) !== canon(json)) bad('대범위를 더한 작업본의 파일 왕복이 다르거나 형식 2 이상이 아님');
    const mb = HT.buildModel([back.pack], null);
    if (!mb.byUid.get(`${d.id}/${id}`) || mb.byUid.get(`${d.id}/${id}`).members.length !== 3 || !mb.docs.get(`${d.id}/${id}`)) bad('반영한 대범위가 모델(구성 정권 셋 · 문서)에 없음');
    D.updateOwn(d, id, { name: '고친 대범위', start: undefined, end: undefined, members: ['윗물국'], label: undefined });
    const s2 = HT.normalizePack(d).pack.scopes.find(s => s.id === id);
    if (!s2 || s2.name !== '고친 대범위' || 'start' in s2 || 'label' in s2 || s2.members.length !== 1) bad(`제 대범위를 고친 것이 작업본에 그대로 담기지 않음: ${JSON.stringify(s2)}`);
    D.removeOwn(d, id);
    if (D.findOwn(d, id) || Object.keys(d.documents).some(k => k.includes(id))) bad('제 대범위를 지웠는데 항목이나 문서가 남음');
    const blank = D.clean(D.blank({ id: 'smoke-sc4' }));
    if (!Array.isArray(blank.scopes) || 'scopes' in HT.packToJSON(HT.normalizePack(Object.assign(blank, { tracks: [{ id: 't', name: 't' }], events: [{ title: 'e', track: 't', start: 1 }] })).pack)) bad('빈 작업본의 대범위 자리가 없거나, 빈 목록이 파일에 나감 (옛 파일이 달라짐)');

    /* 검사: 모델에서야 아는 경고 · 그려지지 않는 대범위 · 승계 줄이 나뉘는 알림 (파일 검사와 겹치는 경고는 한 번만) */
    const cp = {
      format: HT.FORMAT, id: 'smoke-sc5', name: 's', tracks: [{ id: 'a', name: 'a' }, { id: 'b', name: 'b' }],
      periods: [
        { id: 'p1', name: '가', track: 'a', start: 1, end: 10, people: '갑' },
        { id: 'p2', name: '나', track: 'a', start: 10, end: 20, people: '갑', succeeds: ['가'] },
        { id: 'p3', name: '다', track: 'a', start: 20, end: 30, people: '갑', succeeds: [{ from: '나', type: 'direct' }] },
        { id: 'p4', name: '라', track: 'a', start: 20, end: 30, people: '을', succeeds: ['나'] },
        { id: 'p5', name: '마', track: 'b', start: 1, end: 9 },
      ],
      scopes: [
        { id: 'sa', track: 'a', name: 'A', members: ['나', '없는 나라', 'b:마'] },
        { id: 'sb', track: 'a', name: 'B', members: ['나', '다'], host: '가' },
        { id: 'sc', track: 'a', name: 'C', members: ['없는 나라'] },
      ],
    };
    const cr = HT.normalizePack(cp);
    const cm = HT.buildModel([cr.pack], null);
    const sc = kit.scopeChecks(cr.pack, cm, cp.scopes, cr.warnings);
    const of = (list, i) => list.filter(x => x.kind === 'scopes' && x.index === i).map(x => x.msg);
    if (!of(sc.warnings, 0).some(m => /없는 나라/.test(m)) || of(sc.warnings, 0).some(m => /다른 트랙에 있어/.test(m))) bad(`대범위 경고가 어긋남 (찾지 못한 구성 정권이 없거나 파일 검사의 '다른 트랙' 경고를 또 적음): ${JSON.stringify(of(sc.warnings, 0))}`);
    if (!of(sc.warnings, 2).some(m => /그려지지 않습니다/.test(m))) bad('기간을 정할 수 없어 그려지지 않는 대범위를 알리지 않음');
    const n0 = of(sc.notes, 0);
    if (n0.length !== 2 || !n0.some(m => /«나».*«가»/.test(m)) || !n0.some(m => /«나».*«다»/.test(m))) bad(`승계 줄이 나뉘는 알림이 어긋남 (같은 민족의 앞 · 뒤 정권 둘이어야 함 — 다른 민족 «라»는 빼고): ${JSON.stringify(n0)}`);
    if (of(sc.notes, 1).length) bad(`구성 정권끼리 · 상징적 본국과의 승계를 '줄이 나뉨'으로 알림: ${JSON.stringify(of(sc.notes, 1))}`);

    /* 화면 쪽(글로만 읽음) */
    const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
    const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
    if (!/F\.html\(\{[^\n]*\.\.\.scopeArgs, eventTitles, treatyTitles \}\)/.test(vsrc) || !/const scopeArgs = [\s\S]{0,120}epochs:[\s\S]{0,400}polities:/.test(vsrc)) bad('편집 창이 대범위 폼에 시대 구분 · 정권 목록을 넘기지 않음');
    if (!/if \(x && paneEditable\(x\.uid\)\) \{\s*items\.push\(\{ label: '✎ 수정'/.test(vsrc)) bad('우클릭의 수정 · 삭제 줄이 편집 창과 다른 판단을 씀');
    if (!/function scopeDetailHTML[\s\S]{0,4000}maker && maker\.isOwn\(x\) \? '<button class="btn btn-sm" data-act="edit"/.test(vsrc)) bad('대범위 상세에 제 대범위의 수정 단추가 없음');
    if (!/shown\.kind !== 'epoch' && shown\.kind !== 'scope'\) timeline\.setAnchor/.test(vsrc)) bad('대범위를 편집 창에 열 때 제 줄이 없는 대범위에 세로 닻을 걺');
    if (!/const sc = kit\.scopeChecks\(fresh, model, draft\.scopes, check\.warnings\)/.test(msrc)) bad('메이커의 검사가 대범위 검사를 싣지 않음');
    const form = HT.FORMS.scope.html({ tracks: [{ id: 'a', name: 'a' }], polityNames: ['가'], epochs: [], polities: [{ name: '가', track: 'a', trackName: 'a' }] });
    if (!/<datalist id="mkPolityList" data-polities="/.test(form)) bad('대범위 폼이 정권 목록(트랙 기준 자동 완성)을 싣지 않음');
    if (!HT.FORMS.scope.html({ tracks: [] }).includes('<datalist id="mkPolityList">')) bad('정권 목록 없이 대범위 폼이 그려지지 않음');
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ㉖ 검토 반영(메이커 배선 f1): ① 켜져 있는 다른 DLC에도 같은 id로 있는 가문 · 지위(가져온 것)는 그쪽 정의가 먼저 쓰이므로(먼저 정의가 이김) 이름을 바꿔도
   가리키던 곳을 따라 고치지 않아야 참조가 끊기지 않음 — kit.shadowOf와 바탕 자료 창이 그것으로 이름 따라가기를 건너뛰는지 ·
   ② 이름 없는 지위 줄은 파일에서 빠지므로 검사의 경고가 그 줄의 차례를 싣고(검사 창에서 그 줄로), 표가 그 줄의 이름 칸에 표시하는지 */
{
  const bad = msg => out.problems.push(`검토 반영(바탕 자료의 먼저 쓰이는 정의 · 이름 없는 지위): ${msg}`);
  const kit = HT.makerKit;
  const D = HT.draft;
  try {
    const T = kit.BASE_TABLES;
    const head = { format: 'history-timeline-dlc', formatVersion: 2, version: '1' };
    const oth = HT.normalizePack(Object.assign({ id: 'oth', name: '다른 팩', tracks: [{ id: 't', name: 'T' }], houses: [{ id: 'h-x', name: '가람' }], rankDefs: [{ id: 'r-x', name: '대장', tier: 5 }, { id: 'r-y', name: '소장', tier: 1 }] }, head)).pack;
    if (typeof kit.shadowOf !== 'function') bad('kit.shadowOf가 없음');
    else {
      if (kit.shadowOf([oth], 'houses', 'h-x') !== oth || kit.shadowOf([oth], 'rankDefs', 'r-x') !== oth) bad('다른 팩에도 있는 id를 찾지 못함');
      if (kit.shadowOf([oth], 'houses', 'h-z') || kit.shadowOf([oth], 'houses', '') || kit.shadowOf(null, 'houses', 'h-x')) bad('다른 팩에 없는 id · 빈 id를 다른 팩의 것으로 봄');
      /* 가져온 가문 · 지위의 이름을 바꿈 — 바탕 자료 창처럼, 다른 팩이 먼저 쓰이는 줄은 이름을 따라 고치지 않음 */
      const d = D.clean(Object.assign({ id: 'mine', name: '내 팩', tracks: [{ id: 't', name: 'T' }], periods: [{ id: 'p', track: 't', name: '가', start: 1, end: 50, house: '가람', ranks: [['대장', null, null]] }] }, head));
      d.houses.push({ id: 'h-x', name: '가람' });
      d.rankDefs.push({ id: 'r-x', name: '대장', tier: 5 });
      for (const [list, row, to] of [['houses', d.houses[0], '새가람'], ['rankDefs', d.rankDefs[0], '큰대장']]) {
        const shadow = kit.shadowOf([oth], list, row.id);
        if (!shadow) bad(`가져온 ${list}의 줄을 다른 팩이 먼저 쓰는 줄로 보지 않음`);
        if (!shadow) kit.renameRefs(d, T[list], 'name', row.name, to);
        row.name = to;
      }
      const r = HT.normalizePack(d);
      const m = r.pack && HT.buildModel([oth, r.pack], null);
      const p = m && m.periods.find(x => x.id === 'p');
      if (!p || p.houseId !== 'h-x' || !p.rankSpans || !p.rankSpans[0].def || p.rankSpans[0].def.id !== 'r-x' || p.rankSpans[0].def.tier !== 5)
        bad(`다른 팩이 먼저 쓰는 가문 · 지위의 이름을 바꾼 뒤 참조가 끊김: 가문 ${p && p.houseId} · 지위 ${p && p.rankSpans && p.rankSpans[0].def ? p.rankSpans[0].def.id : '-'}`);
      const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
      if (!/const shadow = col\.type === 'id' \|\| !follow\.length \|\| !from \|\| !to \? null : kit\.shadowOf\(others, baseTab, r\.x\.id\);/.test(msrc) || !/const n = from && to && !shadow \? kit\.renameRefs\(/.test(msrc))
        bad('바탕 자료 창이 다른 팩이 먼저 쓰는 줄의 이름을 따라 고침 (kit.shadowOf로 건너뛰지 않음)');
      if (!/const shadow = byName \? kit\.shadowOf\(others, list, x\.id\) : null;/.test(msrc) || !msrc.includes('class="mk-shadow-tag"')) bad("바탕 자료 표가 다른 팩이 먼저 쓰는 줄에 '다른 DLC 우선'을 붙이지 않음");
      if (!/다른 DLC의 지위는 가져와도 그 DLC가 켜져 있는 동안에는 그쪽 정의가 먼저/.test(T.rankDefs.lead)) bad('지위 칸의 안내 글이 다른 DLC의 지위를 가져와 고칠 수 있는 것처럼 말함');
    }
    /* 이름 없는 지위 줄: 경고가 그 줄의 차례를 실음 · 표가 이름 칸에 표시 */
    const dn = D.clean(Object.assign({ id: 'mine2', name: '내 팩', tracks: [{ id: 't', name: 'T' }], periods: [{ id: 'p', track: 't', name: '가', start: 1, end: 5 }] }, head));
    dn.rankDefs.push({ id: 'rank-a', name: '갑', tier: 2 }, { id: 'rank', tier: 5, aliases: ['을'] }, { id: 'rank-b', name: '병', tier: 'x' });
    const rn = HT.normalizePack(dn);
    const rw = rn.warnings.filter(w => w.kind === 'rankDefs');
    if (!rw.some(w => /이름이 없어/.test(w.msg) && w.index === 1)) bad(`이름 없는 지위 줄의 경고가 그 줄의 차례(1)를 싣지 않음: ${JSON.stringify(rw)}`);
    if (!rw.some(w => /서열/.test(w.msg) && w.index === 2)) bad(`읽을 수 없는 서열의 경고가 그 줄의 차례(2)를 싣지 않음: ${JSON.stringify(rw)}`);
    const whole = HT.normalizePack(Object.assign({ id: 'mine3', name: '내 팩', rankDefs: '갑' }, head)).warnings.filter(w => w.kind === 'rankDefs');
    if (whole.length !== 1 || whole[0].index !== undefined) bad(`목록이 아닌 지위 사전의 경고가 줄을 가리킴: ${JSON.stringify(whole)}`);
    if (typeof T.rankDefs.dropped !== 'function' || !T.rankDefs.dropped({ id: 'rank' }) || !T.rankDefs.dropped({ id: 'rank', name: '  ' }) || T.rankDefs.dropped({ id: 'rank', name: '갑' })) bad('지위 칸이 이름 없는 줄을 빠지는 줄로 표시하지 않음');
    if (T.houses.dropped) bad('가문 칸이 이름 없는 줄을 빠지는 줄로 표시함 (가문은 id를 이름으로 삼아 남음)');
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ㉗ 검토 반영(메이커 배선 f2): ① 검사 창의 대범위 경고가 파일 검사와 겹치는 것을 대범위 통째가 아니라 정권마다 가리는지 — 파일 검사는 "트랙:정권"으로 적은
   다른 트랙의 정권만 알리므로, 트랙 없이 id · uid로 적어 다른 트랙에서 찾아진 정권의 경고는 남아야 함(같은 이름이 둘이면 하나만 빠짐) ·
   ② [고친 것]의 줄 이름: 이름을 비우고 시대 구분만 적은 대범위는 id가 아니라 시대 구분으로 */
{
  const bad = msg => out.problems.push(`검토 반영(대범위 검사 · 고친 것의 이름): ${msg}`);
  const kit = HT.makerKit;
  const D = HT.draft;
  try {
    const cp = {
      format: HT.FORMAT, id: 'smoke-sc6', name: 's', tracks: [{ id: 'a', name: 'a' }, { id: 'b', name: 'b' }, { id: 'c', name: 'c' }],
      periods: [
        { id: 'p1', name: '가', track: 'a', start: 1, end: 10 },
        { id: 'p5', name: '마', track: 'b', start: 1, end: 9 },
        { id: 'p6', name: '바', track: 'c', start: 1, end: 9 },
        { id: 'p7', name: '마', track: 'c', start: 1, end: 9 },
      ],
      scopes: [
        { id: 's0', track: 'a', name: 'A', members: ['가', 'b:마', 'p6'] }, // b:마는 파일 검사가 · p6(트랙 c의 바)은 모델만 알림
        { id: 's1', track: 'a', name: 'B', members: ['가', 'b:마', 'smoke-sc6/p7'] }, // 같은 이름 "마" 둘 — 파일 검사가 알린 하나만 빠짐
        { id: 's2', track: 'a', name: 'C', members: ['가', 'b:마', 'c:바'] }, // 둘 다 파일 검사가 알림 — 모델 경고는 모두 빠짐
      ],
    };
    const cr = HT.normalizePack(cp);
    const cm = HT.buildModel([cr.pack], null);
    const sc = kit.scopeChecks(cr.pack, cm, cp.scopes, cr.warnings);
    const other = i => sc.warnings.filter(x => x.index === i && /다른 트랙에 있어 모이지 않습니다/.test(x.msg)).map(x => x.msg);
    if (other(0).length !== 1 || !/"바"/.test(other(0)[0])) bad(`트랙 없이 id로 적은 다른 트랙의 구성 정권 경고가 파일 검사의 경고에 묻혀 사라짐: ${JSON.stringify(other(0))}`);
    if (other(1).length !== 1 || !/"마"/.test(other(1)[0])) bad(`같은 이름의 다른 트랙 정권 둘 가운데 파일 검사가 알린 하나만 빠지지 않음: ${JSON.stringify(other(1))}`);
    if (other(2).length) bad(`파일 검사가 이미 알린 다른 트랙의 정권을 또 적음: ${JSON.stringify(other(2))}`);
    const noFile = kit.scopeChecks(cr.pack, cm, cp.scopes, []);
    if (noFile.warnings.filter(x => x.index === 0 && /다른 트랙에 있어/.test(x.msg)).length !== 2) bad('파일 검사의 경고 없이 부르면 다른 트랙의 구성 정권 경고를 모두 싣지 않음');

    /* [고친 것]의 줄 이름 */
    const head = { format: 'history-timeline-dlc', formatVersion: 2, version: '1' };
    const d = D.clean(Object.assign({ id: 'smoke-sc7', name: 's', tracks: [{ id: 't', name: 'T' }], epochs: [{ id: 'e1', name: '빈 이름 시대', track: 't', start: 1, end: 20 }], periods: [{ id: 'p1', name: '가', track: 't', start: 1, end: 10 }] }, head));
    const before = HT.normalizePack(JSON.parse(JSON.stringify(d))).pack;
    D.addItem(d, 'scope', { track: 't', epoch: '빈 이름 시대', members: ['가'] });
    const after = HT.normalizePack(d).pack;
    const add = D.changes(after, before).filter(c => c.list === 'scopes').map(c => c.label);
    const del = D.changes(before, after).filter(c => c.list === 'scopes').map(c => c.label);
    if (add.join() !== '대범위 추가 · 빈 이름 시대' || del.join() !== '대범위 삭제 · 빈 이름 시대') bad(`이름을 비운 대범위가 [고친 것]에 시대 구분이 아닌 이름으로 나옴: ${JSON.stringify(add.concat(del))}`);
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ㉘ 통합 마무리 검토(f × g): 파일에 배치용 연도를 startHint · endHint로 적은 제 항목(시대 · 사건 · 인물 활동 시기 · 대범위)을 편집 창에서 고쳐 저장하면
   폼의 숫자 칸(= 배치용 연도)이 작업본에 들어가고 옛 startHint · endHint는 걷혀야 함 — 남아 있으면 읽을 때 그것이 먼저라(HT.readCellEdge · readRange) 고친 연도가 버려짐.
   고치지 않고 그대로 저장하면 내보내는 파일은 그대로 */
{
  const bad = msg => out.problems.push(`통합 마무리 검토(배치용 연도 고치기): ${msg}`);
  const D = HT.draft;
  try {
    const raw = {
      format: HT.FORMAT, formatVersion: 2, id: 'smoke-hint', name: 's', version: '1.0.0', tracks: [{ id: 't', name: 'T' }],
      periods: [{ id: 'p1', track: 't', name: '가', start: '미정', startHint: 100, end: '미정', endHint: 500 }],
      events: [{ id: 'e1', track: 't', title: '나', start: '미정', startHint: 150, end: 300 }],
      figures: [{ id: 'f1', track: 't', name: '다', start: '미정', startHint: 120, end: 300 }],
      scopes: [{ id: 's1', track: 't', name: '라', start: '미정', startHint: 110, end: 400, members: ['가'] }],
    };
    const exp = d => canon(HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(d))).pack));
    /* 폼이 내놓는 꼴: 미정 체크 + 숫자 칸(배치용 연도) */
    const forms = { p1: h => ({ start: h, startUnknown: true, end: 500, endUnknown: true }), e1: h => ({ start: h, startUnknown: true, end: 300 }), f1: h => ({ start: h, startUnknown: true, end: 300 }), s1: h => ({ start: h, startUnknown: true, end: 400 }) };
    const was = { p1: 100, e1: 150, f1: 120, s1: 110 };
    const same = D.clean(JSON.parse(JSON.stringify(raw)));
    const orig = exp(same);
    for (const id of Object.keys(forms)) D.updateOwn(same, id, forms[id](was[id]));
    if (exp(same) !== orig) bad('배치용 연도를 고치지 않고 그대로 저장했는데 내보내는 파일이 달라짐');
    const d = D.clean(JSON.parse(JSON.stringify(raw)));
    for (const id of Object.keys(forms)) D.updateOwn(d, id, forms[id](was[id] + 30));
    D.updateOwn(d, 'p1', { start: 130, startUnknown: true, end: 540, endUnknown: true });
    const pk = HT.normalizePack(d).pack;
    const got = { p1: pk.periods[0].start, e1: pk.events[0].start, f1: pk.figures[0].start, s1: pk.scopes[0].start };
    for (const id of Object.keys(was)) if (got[id] !== was[id] + 30) bad(`${id}: 폼에서 고친 배치용 연도(${was[id] + 30})가 옛 startHint(${was[id]})에 밀려 버려짐 — 읽은 값 ${got[id]}`);
    if (pk.periods[0].end !== 540) bad(`시대의 끝 배치용 연도(540)가 옛 endHint(500)에 밀려 버려짐 — 읽은 값 ${pk.periods[0].end}`);
    if (d.periods[0].startHint != null || d.figures[0].startHint != null) bad('폼으로 저장한 뒤에도 작업본에 옛 startHint가 남음');
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ㉙ 합친 뒤 검토 고침(integ): 옛 "내 수정"의 이사 · 바탕 자료의 참조 따라가기 · 표 붙여넣기 · 형식 버전 · 패치 읽기
   ① 이사: 이름을 바꾼 남의 문화는 상대 국가의 succeeds(옛 이름)에서 온 승계선을 지킴(승계한 국가를 패치에 함께) · 없는 DLC의 고침 · 숨김은 앞(⑩)에서
   ② 트랙 id를 바꾸면 조약 당사국의 "트랙:이름" 글(당사국 줄이 글 · 트랙 칸이 빈 줄의 polity)도 따라감 (트랙 칸이 있는 줄의 polity는 이름 그대로)
   ③ 시대 구분의 이름을 바꾸면 그 이름으로 적은 대범위도 따라감 · 쓰는 곳
   ④ 표 붙여넣기의 종류 낱말이 파일 읽기와 같은 종류 · 시작 "미정" + 끝 연도의 끝이 남음(붙여넣기 · 파일 · 폼 모두)
   ⑤ 버전 2의 패치 칸을 비우는 패치도 형식 2 · 패치의 phases/ranks: null은 무시하고 알림 · 패치의 startHint는 "미정" + 숫자로 */
{
  const bad = msg => out.problems.push(`합친 뒤 검토 고침: ${msg}`);
  const D = HT.draft;
  const kit = HT.makerKit;
  const smp = f => JSON.parse(readFileSync(join(root, 'samples', f), 'utf8'));
  try {
    /* ① (견본의 문화는 제 successors를 적으므로, 상대 국가의 succeeds로만 이어진 문화는 여기서 짓는 작은 팩으로) */
    const ku = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-cult', name: '검사', tracks: [{ id: 't', name: 'T' }], cultures: [{ id: 'cult2', track: 't', name: '옛 문화', start: -500, end: -100 }], periods: [{ id: 'p', track: 't', name: '뒤 나라', start: -100, end: 100, succeeds: ['옛 문화'] }] }).pack;
    const kb = HT.buildModel([ku], null);
    const cult = kb.byUid.get('smoke-cult/cult2');
    if (cult && !Array.isArray(cult.successorNames) && cult.successors.length) {
      const names = cult.successors.map(e => e.to.name);
      const moved = D.fromUser(Object.assign(HT.blankUser(), { overrides: { [cult.uid]: { name: '고친 문화 이름', start: cult.start, end: cult.end, track: cult.track, successors: names } } }), [ku], { id: 'my-edits', name: '내 수정' });
      const p = (moved.patches || []).find(x => x.target === cult.uid);
      const after = HT.buildModel([ku, HT.normalizePack(moved).pack], null).byUid.get(cult.uid);
      if (!p || canon(p.set.successors) !== canon(names) || after.successors.length !== names.length) bad(`이름을 바꾼 문화의 승계선이 이사 뒤 끊김: ${JSON.stringify(p && p.set)}`);
      if (Object.keys(D.fromUser(Object.assign(HT.blankUser(), { overrides: { [cult.uid]: { name: cult.name, successors: names } } }), [ku], { id: 'my-edits', name: '내 수정' }).patches.find(x => x.target === cult.uid) || {}).length) bad('이름을 바꾸지 않은 문화에 패치가 생김');
    } else bad('검사 팩의 문화(cult2) 승계선을 찾지 못해 검사하지 못함');
    /* ② 견본(sample-lantern)의 적석 트랙 — 견본의 당사국은 모두 { track, polity } 줄이라 "트랙:이름" 글은 검사 사건 · 패치에 더함 */
    const tr = smp('sample-lantern.json');
    const usedBase = kit.findUsers(tr, kit.BASE_TABLES.tracks, { id: 'jeokseok' }).length;
    tr.events.push({ id: 'smoke-tx', title: '검사 조약', start: 710, track: 'hayeon', treaty: { type: 'alliance', parties: [{ polity: 'jeokseok:적석 왕국' }, { track: 'jeokseok', polity: 'jeokseok:그대로' }, 'jeokseok:적석 왕국'] } });
    tr.patches = [{ target: '딴팩/딴사건', set: { treaty: { type: 'alliance', parties: ['jeokseok:적석 왕국'] } } }];
    const usedBefore = kit.findUsers(tr, kit.BASE_TABLES.tracks, { id: 'jeokseok' }).length;
    kit.renameRefs(tr, kit.BASE_TABLES.tracks, 'id', 'jeokseok', 'jeokseok2');
    const sec = tr.events.find(e => e.id === 'e-tr-412');
    const tx = tr.events.find(e => e.id === 'smoke-tx');
    if (!sec || sec.treaty.parties[3].track !== 'jeokseok2' || sec.treaty.parties[3].polity !== '적석 왕국') bad(`조약 당사국 줄의 트랙 칸이 트랙 id를 따라가지 않음: ${JSON.stringify(sec && sec.treaty.parties[3])}`);
    if (tx.treaty.parties[0].polity !== 'jeokseok2:적석 왕국' || tx.treaty.parties[2] !== 'jeokseok2:적석 왕국' || tx.treaty.parties[1].polity !== 'jeokseok:그대로' || tx.treaty.parties[1].track !== 'jeokseok2') bad(`당사국 줄의 polity · track이 규칙대로 바뀌지 않음: ${JSON.stringify(tx.treaty.parties)}`);
    if (tr.patches[0].set.treaty.parties[0] !== 'jeokseok2:적석 왕국') bad('패치의 조약 당사국 글이 트랙 id를 따라가지 않음');
    if (usedBefore - usedBase !== 2) bad(`트랙의 쓰는 곳에 조약 당사국 글이 셈해지지 않음 (${usedBase} → ${usedBefore})`);
    /* ③ */
    const sc = smp('sample-lantern.json');
    const ep = sc.epochs.find(e => sc.scopes.some(s => s.epoch === e.name));
    if (ep) {
      const n0 = kit.BASE_TABLES.epochs.uses(sc, ep).length;
      const before = Object.assign({}, ep);
      ep.name = `${ep.name} 고침`;
      const n = kit.renameEpochRefs(sc, before, before.name, ep.name);
      if (!n0 || n !== n0 || sc.scopes.some(s => s.epoch === before.name)) bad(`시대 구분의 이름을 바꿨는데 대범위가 따라가지 않음 (쓰는 곳 ${n0} · 고친 수 ${n})`);
      const m = HT.buildModel([HT.normalizePack(sc).pack], null);
      if (m.scopes.some(s => s.warnings.some(w => /시대 구분/.test(w)))) bad('시대 구분 이름을 바꾼 뒤 대범위가 시대 구분을 찾지 못함');
    } else bad('견본에서 이름으로 가리킨 시대 구분을 찾지 못해 검사하지 못함');
    /* ④ */
    const words = Object.keys(HT.KIND_WORDS).concat(HT.POLITY_KINDS.map(k => k.name));
    const pasted = kit.analyzePaste(['이름\t시작\t끝\t종류'].concat(words.map((w, i) => `나라${i}\t${100 + i}\t${200 + i}\t${w}`)).join('\n'), 'period', { tracks: [{ id: 't', name: 'T' }], defaultTrack: 't' });
    const filed = HT.normalizePack({ format: HT.FORMAT, formatVersion: 2, id: 'smoke-kw', name: 's', tracks: [{ id: 't', name: 'T' }], periods: words.map((w, i) => ({ id: `p${i}`, name: `나라${i}`, start: 100 + i, end: 200 + i, track: 't', kind: w })) }).pack;
    const diff = words.filter((w, i) => (pasted.items[i] && pasted.items[i].kind || 'state') !== (filed.periods[i].kind || 'state'));
    if (diff.length) bad(`표 붙여넣기와 파일 읽기의 종류가 다른 낱말: ${diff.join(', ')}`);
    const pu = kit.analyzePaste('이름\t시작\t끝\n가 나라\t미정\t600', 'period', { tracks: [{ id: 't', name: 'T' }], defaultTrack: 't' }).items[0];
    const pn = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-su', name: 's', tracks: [{ id: 't', name: 'T' }], periods: [Object.assign({ id: 'a' }, pu), { id: 'b', track: 't', name: '나', start: '미정', end: 600 }] }).pack;
    if (!pu || pu.end !== 600 || pn.periods.some(p => p.end !== 600 || !p.startUnknown)) bad(`시작 미정 + 끝 연도에서 끝이 버려짐: ${JSON.stringify(pu)} ${JSON.stringify(pn && pn.periods)}`);
    /* ⑤ */
    for (const set of [{ figures: null }, { role: null }, { aka: [] }, { service: null }, { birth: null }, { treaty: null }]) {
      const r = HT.normalizePack({ format: HT.FORMAT, formatVersion: 1, id: 'smoke-v2', name: 's', patches: [{ target: '딴팩/딴것', set }] });
      if (!r.pack || HT.packToJSON(r.pack).formatVersion !== 2) bad(`버전 2의 칸을 비우는 패치가 형식 1로 나감: ${JSON.stringify(set)}`);
    }
    const hn = HT.normalizePack({ format: HT.FORMAT, formatVersion: 1, id: 'smoke-hn', name: 's', patches: [{ target: '딴팩/딴것', set: { description: 'x' } }, { target: '딴팩/딴것2', set: { house: null } }] });
    if (!hn.pack || HT.packToJSON(hn.pack).formatVersion !== 1) bad('옛 칸만 고치는 패치(국성 비우기 포함)가 형식 2로 나감');
    for (const k of ['phases', 'ranks']) {
      const r = HT.normalizePack({ format: HT.FORMAT, formatVersion: 2, id: 'smoke-nl', name: 's', patches: [{ target: '딴팩/딴것', set: { description: 'x', [k]: null } }] });
      if (!r.pack || k in r.pack.patches[0].set || !r.warnings.some(w => /목록이어야/.test(w.msg))) bad(`패치의 ${k}: null이 대상의 것을 지우거나 알림이 없음`);
    }
    const hp = HT.normalizePack({ format: HT.FORMAT, formatVersion: 1, id: 'smoke-hp', name: 's', patches: [{ target: '딴팩/딴것', set: { start: '미정', startHint: -900 } }] });
    const hs = hp.pack && hp.pack.patches[0].set;
    if (!hs || hs.start !== -900 || hs.startUnknown !== true || hp.warnings.length) bad(`패치의 startHint가 배치용 연도로 읽히지 않음: ${JSON.stringify(hs)} ${hp.warnings.map(w => w.msg)}`);
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
}

/* ㉚ 일방통행(2026-09-19 감독 결정): 메이커 → 연표('연표로 ↗')의 한 방향뿐 — 연표에서 메이커로 가는 길(메뉴 · 단축키 · DLC 관리의 단추 · 항목 넘겨주기)이 없는지 코드 글로 읽어 봅니다.
   연표의 편집 함수는 그대로 거절하되 거절 글에 메이커 안내가 없어야 하고, 넘겨받기(K.handoff · 'ht:handoff')는 어느 파일에도 남지 않아야 합니다. 화면의 동작은 브라우저에서 */
{
  const bad = msg => out.problems.push(`일방통행: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const viewerSrc = src('js/viewer.js');
  const makerSrc = src('js/maker.js');
  const view = src('index.html');
  if (/openPage\(\s*['"`]dlc-maker/.test(viewerSrc)) bad("js/viewer.js가 openPage('dlc-maker.html')로 메이커를 엶");
  for (const f of ['js/viewer.js', 'js/core.js', 'js/wiki.js', 'js/timeline.js', 'index.html']) if (src(f).includes('메이커에서 고치기')) bad(`${f}에 '메이커에서 고치기'가 남아 있음`);
  if (/maker:\s*'Shift\+M'/.test(viewerSrc) || /k === 'M'\)/.test(viewerSrc) || /KEYS\.maker\b/.test(viewerSrc)) bad('연표에 메이커로 가는 단축키(Shift+M)가 남아 있음');
  if (/DLC 메이커를 열어/.test(viewerSrc) || !/\$\{!maker \|\| p\.builtin \|\| editing \? '' :/.test(viewerSrc)) bad("DLC 관리의 '이 DLC 고치기' 단추가 연표에도 나옴 (메이커에서만)");
  const deny = (viewerSrc.match(/const denyEdit = \(\) => \{[\s\S]*?\};/) || [''])[0];
  if (!deny || /메이커/.test(deny)) bad('보기 전용 거절 알림이 없거나 메이커를 가리킴');
  for (const f of ['js/core.js', 'js/viewer.js', 'js/maker.js', 'js/platform.js']) if (/handoff/i.test(src(f))) bad(`${f}에 넘겨주기 · 넘겨받기(handoff)가 남아 있음`);
  if (/\bhandoff\s*:/.test(src('js/core.js')) || 'handoff' in HT.KEYS) bad('HT.KEYS에 handoff 열쇠가 남아 있음');
  for (const f of ['js/maker.js', 'js/fieldpop.js']) if (view.includes(`src="${f}"`)) bad(`index.html이 ${f}를 읽음 (메이커 전용)`);
  if (view.includes('href="css/maker.css"')) bad('index.html이 css/maker.css를 읽음 (메이커 전용)');
  if (/href="dlc-maker\.html"/.test(view)) bad('index.html에 메이커를 여는 링크가 있음');
  // '연표로 ↗'(2026-10-16 감독 "미리보기 하려면 그냥 앱에서 확인하게 해. 본 프로그램"): 컴퓨터의 메이커 앱은 본 프로그램(연표 앱) 미리보기, 휴대폰은 알림, 브라우저는 예전 웹 연표 창 — 여전히 한 방향
  const toTimeline = (makerSrc.match(/async function toTimeline\(\) \{[\s\S]*?\n    \}/) || [''])[0];
  if (!/\{ label: '연표로 ↗', run: toTimeline \}/.test(makerSrc)) bad("메이커 메뉴의 '연표로 ↗'가 toTimeline으로 이어지지 않음");
  if (!toTimeline || !/HT\.platform\.previewInApp\(/.test(toTimeline) || !/HT\.platform\.openPage\('index\.html'\)/.test(toTimeline) || !/HT\.platform\.canPreviewApp/.test(toTimeline)) bad("toTimeline이 본 프로그램 미리보기(previewInApp) · 브라우저의 웹 연표 창(openPage('index.html'))으로 가르지 않음");
  if (!/<button (?=[^>]*data-cmd="to-timeline")[^>]*>연표로/.test(src('dlc-maker.html'))) bad("메이커 줄의 '연표로' 단추(data-cmd=\"to-timeline\")가 없음");
  // 연표(보기 전용)에 뜨는 글이 '추가하세요'라고 하지 않는지 — 그런 글은 메이커일 때만(같은 줄에서 maker ? … 로 가름)
  viewerSrc.split('\n').forEach((line, i) => {
    if (/추가하세요/.test(line) && !/\bmaker\b[^'`]*\?[^]*추가하세요/.test(line)) bad(`js/viewer.js ${i + 1}줄: 연표에도 뜨는 글이 '추가하세요'라고 함 (메이커일 때만)`);
  });
  // 메이커의 '연표로'가 메이커 창을 연표 미리보기로 바꿔 버리지 않는지 — 미리보기에는 메이커로 돌아가는 길이 없습니다.
  // PC에 설치한 PWA는 새 창으로 열고, 같은 창에서 옮기는 것은 모바일(뒤로 단추가 있음)뿐이며 그때도 편집 창의 저장하지 않은 고침을 먼저 묻습니다(HT.platform.beforeLeave)
  const runPlatform = ({ standalone = false, ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } = {}) => {
    const calls = [];
    const w = {
      HT: {},
      matchMedia: q => ({ matches: standalone && /standalone/.test(q) }),
      navigator: { userAgent: ua, maxTouchPoints: 0 },
      location: { protocol: 'file:', assign: u => calls.push(`assign ${u}`) },
      history: { state: null, pushState() {}, back() {} },
      document: { addEventListener() {}, dispatchEvent() {}, documentElement: { dataset: {} } },
      addEventListener() {},
      open: u => calls.push(`open ${u}`),
      setTimeout,
    };
    w.window = w;
    vm.createContext(w);
    vm.runInContext(src('js/platform.js'), w, { filename: 'js/platform.js' });
    return { P: w.HT.platform, calls };
  };
  try {
    const pwa = runPlatform({ standalone: true });
    await pwa.P.openPage('index.html');
    if (pwa.P.name !== 'pwa' || pwa.P.singleWindow || pwa.calls.join() !== 'open index.html') bad(`PC에 설치한 PWA에서 '연표로'가 새 창으로 열리지 않음: ${pwa.P.name} · ${pwa.calls.join()}`);
    const phone = runPlatform({ ua: 'Mozilla/5.0 (Linux; Android 14)' });
    phone.P.beforeLeave = async () => false;
    await phone.P.openPage('index.html');
    phone.P.beforeLeave = async () => true;
    await phone.P.openPage('index.html');
    if (!phone.P.singleWindow || phone.calls.join() !== 'assign index.html') bad(`모바일에서 '연표로'가 떠나기 전 확인(beforeLeave)을 따르지 않음: ${phone.calls.join()}`);
    if (pwa.P.canPreviewApp || phone.P.canPreviewApp) bad('Tauri가 아닌 곳(PWA · 휴대폰 웹)에서 본 프로그램 미리보기(canPreviewApp)가 켜짐');
  } catch (e) {
    bad(`js/platform.js를 시험으로 읽지 못함: ${e && e.message}`);
  }
  if (!/HT\.platform\.beforeLeave = \(\) => ctx\.leaveEditor\(/.test(makerSrc)) bad('메이커가 떠나기 전 확인(HT.platform.beforeLeave → 편집 창의 저장하지 않은 고침 묻기)을 두지 않음');
}

/* ㉛ 모바일 앱 분리(2026-09-20): 이 작업 줄은 Windows 앱 · 웹 · PWA만 포장하고 네이티브 모바일은 별도 가지에 보존합니다.
   안드로이드 전용 경로 · 빌드 명령 · 설정이 다시 섞이지 않는지, 일반 웹의 화면 방향 · 휴대폰 파일 선택과 PWA 파일 받기가 남는지 봅니다.
   Windows의 파일 저장 취소(null · 거절)는 아무것도 쓰지 않고, 고른 경로에 저장하며, 열기는 파일 이름 · 내용과 취소를 그대로 돌려줘야 합니다. */
{
  const bad = msg => out.problems.push(`모바일 앱 분리: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const platformSrc = src('js/platform.js');
  // 보관해 둔 소스·이전 빌드 산출물은 남을 수 있습니다. 앱을 만들 수 있는 진입 파일이 섞였는지 검사합니다.
  for (const f of ['src-tauri/gen/android/settings.gradle', 'src-tauri/gen/android/settings.gradle.kts', 'src-tauri/gen/android/app/build.gradle.kts', 'src-tauri/gen/android/app/build.gradle', 'scripts/android.mjs']) if (existsSync(join(root, f))) bad(`PC·웹 작업 줄에 모바일 빌드 진입 파일이 남아 있음: ${f}`);
  const pkg = JSON.parse(src('package.json'));
  if (Object.entries(pkg.scripts || {}).some(([key, value]) => /^android:/.test(key) || /\btauri\s+android\b|scripts\/android\.mjs/.test(value))) bad('npm 명령에 안드로이드 빌드 경로가 남아 있음');
  if ('android' in (JSON.parse(src('src-tauri/tauri.conf.json')).bundle || {})) bad('Tauri 설정에 안드로이드 포장이 남아 있음');
  if (JSON.parse(src('manifest.webmanifest')).orientation !== 'any') bad('일반 웹/PWA의 화면 방향이 자유롭지 않음');
  if (/HTAndroid|ht:android-files|\bCapacitor\b|\bcapacitor\b|\bCAP\b/.test(platformSrc)) bad('공용 플랫폼 코드에 네이티브 모바일 연결이 남아 있음');

  // 실제 파일이나 대화상자 대신 호출만 기록합니다. Windows와 휴대폰 브라우저는 같은 공용 코드를 각각의 환경으로 읽습니다.
  const runPlatform = ({ save = () => null, open = () => null, native = true, inputEvent = 'change' } = {}) => {
    const calls = [];
    const on = {};
    const w = {
      HT: {},
      matchMedia: () => ({ matches: false }),
      navigator: { userAgent: native ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' : 'Mozilla/5.0 (Linux; Android 15) Mobile', maxTouchPoints: native ? 0 : 5 },
      location: { protocol: 'file:', assign() {} },
      history: { state: null, pushState() {}, back() {} },
      document: {
        addEventListener() {},
        dispatchEvent: e => calls.push(`${e.type} ${(e.detail || []).map(f => `${f.name}:${f.size}`).join(',')}`),
        documentElement: { dataset: {} },
        createElement: () => ({
          files: [],
          listeners: {},
          addEventListener(type, fn) { this.listeners[type] = fn; },
          click() { calls.push('input.click'); this.listeners[inputEvent]?.(); },
        }),
        body: { appendChild() {} },
      },
      launchQueue: { setConsumer: fn => (on.files = fn) },
      addEventListener: (type, fn) => (on[type] = fn),
      setTimeout,
      CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options && options.detail; } },
      File,
    };
    if (native) w.__TAURI__ = {
      dialog: {
        save: async () => save(),
        open: async options => {
          calls.push(`dialog.open ${options.multiple} ${options.filters.flatMap(f => f.extensions).join(',')}`);
          return open();
        },
      },
      fs: {
        writeFile: async (path, bytes) => calls.push(`write ${path} ${bytes.length}`),
        mkdir: async () => calls.push('mkdir'),
        readFile: async path => { calls.push(`read ${path}`); return new TextEncoder().encode('{"id":"sample"}'); },
      },
      path: { appDataDir: async () => (calls.push('appDataDir'), 'C:/앱자료') },
    };
    w.window = w;
    vm.createContext(w);
    vm.runInContext(platformSrc, w, { filename: 'js/platform.js' });
    return { P: w.HT.platform, calls, on };
  };
  try {
    for (const [label, save] of [['null', () => null], ['거절', () => Promise.reject('File picker cancelled')]]) {
      const cancel = runPlatform({ save });
      const result = await cancel.P.saveFile('a.json', new Blob(['{}']));
      if (result !== false || cancel.calls.length) bad(`Windows 저장 취소(${label}) 뒤 파일을 씀: ${result} · ${cancel.calls.join()}`);
    }
    const ok = runPlatform({ save: () => 'C:/자료/저장.json' });
    const saved = await ok.P.saveFile('저장.json', new Blob(['{"x":1}']));
    if (ok.P.name !== 'tauri' || saved !== true || ok.calls.join() !== 'write C:/자료/저장.json 7') bad(`Windows에서 고른 자리에 저장하지 않음: ${saved} · ${ok.calls.join()}`);

    const picker = runPlatform({ open: () => ['C:/자료/하나.json', { path: 'C:/자료/둘.json' }] });
    const files = await picker.P.openFiles('.json', true);
    if (picker.calls.join('|') !== 'dialog.open true json|read C:/자료/하나.json|read C:/자료/둘.json' || files.map(f => f.name).join() !== '하나.json,둘.json' || (await Promise.all(files.map(f => f.text()))).some(text => text !== '{"id":"sample"}')) bad('Windows 파일 열기가 경로 · 이름 · 내용을 보존하지 않음');
    const cancelOpen = runPlatform();
    const noFiles = await cancelOpen.P.openFiles('.json', false);
    if (noFiles.length || cancelOpen.calls.join() !== 'dialog.open false json') bad('Windows 파일 열기를 취소했는데 파일을 읽음');

    const phone = runPlatform({ native: false, inputEvent: 'cancel' });
    // cancel 듣개가 빠져도 검사 전체가 끝없이 기다리지 않게 짧은 한도를 둡니다.
    let timer;
    const cancelled = await Promise.race([phone.P.openFiles('.json', true), new Promise(resolve => { timer = setTimeout(() => resolve(null), 100); })]);
    clearTimeout(timer);
    if (!phone.P.mobile || !phone.P.singleWindow || !Array.isArray(cancelled) || cancelled.length || phone.calls.join() !== 'input.click') bad('휴대폰 브라우저의 파일 선택 취소가 빈 목록으로 끝나지 않음');
    phone.calls.length = 0;
    if (typeof phone.on.files !== 'function') bad('PWA 파일 연결 프로그램의 받는 길이 없음');
    else {
      await phone.on.files({ files: [{ getFile: async () => new File(['{"id":"x"}'], '받은.json', { type: 'application/json' }) }] });
      if (phone.calls.join() !== 'ht:files 받은.json:10') bad(`PWA가 받은 파일을 연표로 넘기지 않음: ${phone.calls.join()}`);
    }
  } catch (e) {
    bad(`Windows · 웹 플랫폼 동작을 읽지 못함: ${e && e.message}`);
  }
}

/* 동군연합 이음줄(건의 8의 6-다 · 2026-10-14): HT.unionPairs가 같은 사람이 같은 때 두 나라의 지도자인 짝을 찾는다 —
   견본 sample-lantern의 동군연합 왕 셋(인물 휘 시온 1130 ~ 1161 — 하연 부흥국 · 청림 왕령지의 겸임(service), 쌍등왕 1270 ~ 1301 · 겹등왕 1301 ~ 1330 — 하연 부흥국 · 적석 왕국(재건), 줄은 가운데). 같은 나라의 복위는 짝이 아니다 */
{
  const bad = msg => out.problems.push(`동군연합: ${msg}`);
  try {
    const smp = f => JSON.parse(readFileSync(join(root, 'samples', f), 'utf8'));
    const m = HT.buildModel([HT.normalizePack(smp('sample-lantern.json')).pack], null);
    const u = typeof HT.unionPairs === 'function' ? HT.unionPairs(m) : null;
    if (!u) bad('HT.unionPairs(같은 사람이 같은 때 두 나라의 지도자인 짝)가 없음');
    else {
      const got = u.map(x => `${x.name}:${[x.a.p.name, x.b.p.name].sort().join('·')}:${x.s}-${x.e}@${x.mid}`).join(' | ');
      if (got !== '휘 시온:청림 왕령지·하연 부흥국:1130-1161@1145.5 | 쌍등왕:적석 왕국(재건)·하연 부흥국:1270-1301@1285.5 | 겹등왕:적석 왕국(재건)·하연 부흥국:1301-1330@1315.5')
        bad(`견본 sample-lantern의 짝이 다름: ${got}`);
      if (u.some(x => x.a.p === x.b.p)) bad('같은 나라의 두 칸(복위)을 짝으로 셈');
    }
  } catch (e) {
    bad(`셈 실패: ${e.message}`);
  }
}

/* ㉜ 종속 뒤집기(2026-09-20 감독 결정 — 상국 띠가 속국을 품음): 속국 띠 안에 상국(옛 예속 띠)을 그리지 않고 상국 띠에 속국 이름표를 답니다 —
   스스로 다스린 관계(자율성 3 · 2 · 명목상 · 관계를 적지 않은 소속 · 구성국 · 동군연합)는 상국 띠 아래에 매달린 탭, 상국이 다스린 관계(1 · 0)는 상국 띠 안 맨 아래 칸.
   노드에서 Timeline.depProxies를 견본 sample-lantern과 트랙이 다른 상국 · 속국(여기서 만든 팩)에 돌려 이름표의 자리 · 모양 · 기간 · 줄(같은 줄에서 겹치지 않음 · 밖 ↔ 안을 옮긴 속국이
   띠에 가장 가까운 줄)을 보고, 접힌 소속 · 기관의 소속을 빼는지, 관계를 적지 않은 소속이 종류에서 빌리는지(종속 갈래가 아니면 예속이 아닌 소속) 봅니다.
   글로 읽어: 속국 띠에 예속 띠를 그리던 코드가 없는지 · 상국 줄의 높이(품은 칸 줄 수 · 매달린 줄 수 — 사건 글줄과 겹치지 않게) · 누르면 속국(data-uid) · 모여드는 움직임에서 제 상국 띠를
   따라감(data-band) · 그림 내보내기 · 탭에 종속 갈래 딱지가 없는지 · 종속 갈래 띠가 점선이 아닌지(화면 · 그림 · 범례) · 범례 · 종류 설명 · 소속선은 접힌 소속에만 */
{
  const bad = msg => out.problems.push(`종속 뒤집기: ${msg}`);
  const TL = HT.Timeline;
  const smp = f => JSON.parse(readFileSync(join(root, 'samples', f), 'utf8'));
  if (!TL || typeof TL.depProxies !== 'function') bad('Timeline.depProxies(상국 띠의 속국 이름표 목록)가 없음');
  else {
    try {
      const m = HT.buildModel([HT.normalizePack(smp('sample-lantern.json')).pack], null);
      const P = name => m.periods.find(p => p.name === name);
      const px = TL.depProxies(m.periods);
      const tags = host => {
        const v = px.get(P(host).uid);
        return v ? Object.fromEntries(v.items.map(it => [it.p.name, it.segs.map(s => `${s.side}:${s.look}`).join(' ')])) : {};
      };
      const want = {
        '설원 제국': { '빛나루 자유시': 'out:loose', '하연 총관부': 'in:owned', '적석 왕국': 'out:firm out:firm', '청림 대공국': 'out:loose' }, // 조공(시작 미정) · 직할령 · 봉신 → 보호국 · 조공(다른 트랙)
        '등불 왕국': { '설족 칸국': 'out:nominal', '산호 섬나라': 'out:loose', '백로 수해 변경부': 'out:loose' }, // 명목상 · 조공 · 기미(접어 두었어도 예속 관계라 이름표)
        '아랫물국': { '갈대 공국': 'out:loose' },
        '산호 해상 동맹': { '빛나루 자유시': 'out:plain', '백사만 해협 개항령': 'out:firm in:owned' }, // 구성국(접지 않음) · 보호령 → 식민지(밖 → 안)
        '하연 부흥국': { '적석 왕국(재건)': 'out:plain', '청림 왕령지': 'out:plain out:firm', '백사만 해협 개항령': 'in:held' }, // 동군연합 · 동군연합 → 종속 · 위임통치
        '청림 대공국': { '은가지 자치령': 'out:loose' }, // 봉국 (견본 2.0.0부터 — 아래 셋도)
        '하연 연합 왕국': { '청림 생태 자치연방': 'out:plain', '백사만 자유시 연방': 'out:plain' }, // 구성국 둘 (다른 트랙)
        '하연 공화국': { '청림 생태 자치연방': 'out:plain', '백사만 자유시 연방': 'out:plain', '서해 입헌 연방': 'out:plain' }, // 구성국 셋 (다른 트랙)
      };
      for (const [host, exp] of Object.entries(want)) {
        const got = tags(host);
        if (canon(got) !== canon(exp)) bad(`${host}의 속국 이름표가 다름: ${JSON.stringify(got)}`);
      }
      if ([...px.keys()].map(u => m.byUid.get(u).name).sort().join() !== Object.keys(want).sort().join()) bad(`이름표가 달린 상국이 다름: ${[...px.keys()].map(u => m.byUid.get(u).name).join(', ')}`);
      /* 접어 둔 소속: 예속이 아닌 소속(구성국)은 이름표 없음 */
      if (tags('산호 해상 동맹')['새물섬']) bad('상위 띠 아래에 접힌 구성국 새물섬에 이름표가 달림');
      for (const dep of ['적석 왕국', '하연 총관부', '갈대 공국', '설족 칸국']) if (px.has(P(dep).uid)) bad(`속국 ${dep} 쪽에 이름표가 생김 (속국 띠 안에는 상국을 그리지 않음)`);
      const sb = px.get(P('설원 제국').uid).items.find(it => it.p.name === '적석 왕국');
      if (!sb || canon(sb.segs.map(s => [s.a, s.b])) !== canon([[790, 860], [860, 1031]])) bad(`적석 왕국 이름표의 기간이 다름: ${sb && JSON.stringify(sb.segs.map(s => [s.a, s.b]))}`);
      /* 줄: 같은 상국 · 같은 쪽의 같은 줄은 기간이 겹치지 않고, 줄 수 = 쓴 줄 수 */
      for (const [uid, v] of px) {
        for (const [key, lane, n] of [['out', 'outLane', v.outLanes], ['inn', 'inLane', v.inLanes]]) {
          const list = v.items.filter(it => it[key]);
          const used = new Set(list.map(it => it[lane]));
          if (used.size !== n) bad(`${m.byUid.get(uid).name}: ${key} 줄 수(${n})가 쓴 줄(${[...used]})과 다름`);
          for (const a of list) for (const b of list) if (a !== b && a[lane] === b[lane] && a[key][0] < b[key][1] && b[key][0] < a[key][1]) bad(`${m.byUid.get(uid).name}: ${a.p.name} · ${b.p.name}의 이름표가 같은 줄에서 겹침`);
        }
      }
      /* 트랙이 다른 상국 · 관계를 적지 않은 소속(종속 갈래 종류면 종류에서 빌림, 아니면 예속이 아닌 소속) · 기관의 소속은 빼기 */
      const cp = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 2, id: 'smoke-dep', name: '검사', version: '1.0.0', tracks: [{ id: 'ta', name: '가' }, { id: 'tb', name: '나' }],
        periods: [
          { id: 'big', track: 'ta', name: '큰 나라', start: 100, end: 900 },
          { id: 'small', track: 'tb', name: '작은 나라', start: 150, end: 850, partOf: [{ track: 'ta', polity: '큰 나라', relation: 'tributary', start: 200, end: 500 }, { track: 'ta', polity: '큰 나라', relation: 'colony', start: 500, end: 850 }] },
          { id: 'lent', track: 'tb', name: '빌린 식민지', kind: 'colony', start: 300, end: 600, partOf: [{ track: 'ta', polity: '큰 나라', start: 300, end: 600 }] },
          { id: 'old', track: 'tb', name: '옛 소속', start: 300, end: 700, partOf: [{ track: 'ta', polity: '큰 나라', start: 300, end: 400 }, { track: 'ta', polity: '큰 나라', start: 500, end: 700 }] },
          { id: 'org', track: 'ta', name: '관청', kind: 'overlay', start: 300, end: 400, partOf: ['큰 나라'] },
        ] });
      if (!cp.pack) bad(`검사용 팩을 읽지 못함 — ${cp.errors.map(e => e.msg).join(' / ')}`);
      else {
        const cm = HT.buildModel([cp.pack], null);
        const cx = TL.depProxies(cm.periods);
        const big = cm.periods.find(p => p.name === '큰 나라');
        const got = cx.has(big.uid) ? Object.fromEntries(cx.get(big.uid).items.map(it => [it.p.name, it.segs.map(s => `${s.side}:${s.look}:${s.a}-${s.b}`).join(' ')])) : {};
        const exp = { '작은 나라': 'out:loose:200-500 in:owned:500-850', '빌린 식민지': 'in:owned:300-600', '옛 소속': 'out:plain:300-400 out:plain:500-700' };
        if (canon(got) !== canon(exp)) bad(`트랙이 다른 상국의 이름표가 다름: ${JSON.stringify(got)}`);
        if ([...cx.keys()].some(u => u !== big.uid)) bad('상국이 아닌 정권(속국 · 기관)에 이름표가 생김');
        const sm = cx.has(big.uid) && cx.get(big.uid).items.find(it => it.p.name === '작은 나라');
        if (!sm || sm.outLane !== 0 || sm.inLane !== 0) bad(`밖에서 안으로 옮긴 작은 나라가 띠에 가장 가까운 줄을 받지 못함 (밖 ${sm && sm.outLane} · 안 ${sm && sm.inLane})`);
      }
    } catch (e) {
      bad(`견본으로 속국 이름표를 만들지 못함 — ${e.message}`);
    }
  }
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const vcss = readFileSync(join(root, 'css/viewer.css'), 'utf8');
  const drawSrc = tsrc.slice(tsrc.indexOf('    _drawTrack(tr, X, W) {'), tsrc.indexOf('    _laneKey(tr, cats, row) {'));
  const svgSrc = tsrc.slice(tsrc.indexOf('    toSVG({'));
  if (/depH && !p\.singleHost && p\.hosts && p\.hosts\.length/.test(tsrc)) bad('속국 띠 안에 상국의 예속 띠를 그리는 코드가 남음 (화면 · 그림)');
  if (!/this\._depCells\(p, X, ox, iw, (geoOf\(p\._row\)|gr)\.depTop - BW, cut, depRowLanes\((geoOf\(p\._row\)|gr)\)\)/.test(drawSrc)) bad('상국 띠 안에 품은 칸(_depCells)을 그리지 않거나, 칸의 줄 자리를 그 줄의 줄 수로 재지 않음');
  if (!/const pu = \/\^\(b\|tab\|m\|mb\|fd\|hb\)\$\/\.test\(pre\) \? rest : \/\^\(f\|o\|sb\|hg\|hl\|ht\)\$\/\.test\(pre\)/.test(tsrc)) bad('모여드는 움직임에서 매달린 탭 · 세로 끈이 제 상국 띠를 따라가지 않음 (data-band를 읽지 않음)');
  if (!/data-k="hg:\$\{key\}:\$\{sk\}"/.test(tsrc)) bad('매달린 탭의 모핑 열쇠가 화면에 보이는 차례라, 옆으로 끌면 잔상이 생김');
  if (!/\.tl\.is-picked \.tl-lane \.tl-band:has\(> \.tl-dep\.is-selected\)/.test(csrc)) bad('고른 속국의 품은 칸이 상국 띠의 흐림에 묻힘');
  if (!/const hang = \(tr\.hangRowLanes\.get\(host\._row\) \|\| 0\) \* HANG\.pitch;/.test(tsrc)) bad('소속선이 상국 띠 아래에 매달린 이름표 줄을 지나감');
  if (/예속 띠/.test(readFileSync(join(root, 'js/core.js'), 'utf8'))) bad('메이커 · 편집 폼의 글이 아직 옛 예속 띠를 말함');
  if (!/rows\[p\._row\] \+= this\._depHangs\(tr, p, X, W, geoOf\(p\._row\), lit, ox\)/.test(drawSrc)) bad('상국 띠 아래에 매달린 탭(_depHangs)을 그리지 않음');
  if (!/class="tl-hang [^"]*" data-k="hg:[^"]*" data-uid="\$\{esc\(it\.p\.uid\)\}" data-row="\$\{row\}" data-band="\$\{esc\(p\.uid\)\}"/.test(tsrc)) bad('매달린 탭에 누르면 속국(data-uid) · 모여드는 움직임에서 제 상국 띠를 따라가는 표시(data-band) · 열쇠(data-k)가 없음');
  if (!/class="tl-dep is-\$\{s\.look\}[^"]*" data-uid="\$\{esc\(it\.p\.uid\)\}"/.test(tsrc)) bad('품은 칸을 눌러도 속국이 골라지지 않음 (data-uid)');
  if (!/const hl = tr\.hangRowLanes\.get\(r\) \|\| 0;[\s\S]{0,200}\(hl \+ zl \? hl \* HANG\.pitch \+ zl \* \(G\.zoneTab \+ G\.zoneGap\) \+ 3 : 0\)/.test(tsrc)) bad('상국 줄 아래에 매달린 탭의 자리(줄 높이)가 없음');
  if (!/class="tl-mem tl-hangbtn\$\{open \? ' is-open' : ''\}" data-k="hb:\$\{esc\(p\.uid\)\}" data-fold-hangs="\$\{esc\(p\.uid\)\}" data-row="\$\{p\._row\}"/.test(drawSrc) || !/else if \(hangs\) this\.toggleHangs\(hangs\.dataset\.foldHangs\);/.test(tsrc)) bad('상국 띠에 매달린 속국 이름표의 접기 단추(▾ 속국 n · data-fold-hangs → toggleHangs)가 없음');
  if (!/tr\.foldedRows\.has\(p\._row\) \|\| this\._hangsFolded\(p\.uid\)\) continue;/.test(tsrc) || !/p\._dep\.outLanes && !this\._hangsFolded\(p\.uid\)\) rows\[p\._row\] \+= this\._depHangs/.test(drawSrc)) bad('매달린 탭을 접어도 그 상국의 줄이 낮아지지 않거나 탭이 그려짐 (hangRowLanes · _depHangs가 foldedHangs를 보지 않음)');
  if (!/return n \? n \* \(G\.dep \+ G\.slotGap\) - G\.slotGap : 0;/.test(tsrc)) bad('상국 띠 안의 품은 칸 자리가 줄 수만큼 늘지 않음 (사건 글줄 · 막대와 겹침)');
  if (!/this\._depSVG\(tr, p, X, W, GW, y, bandH, geoOf\(p\._row\)/.test(svgSrc)) bad('그림 내보내기에 속국 이름표가 없음');
  if (/isDepKind\(p\.polityKind\) \|\| p\.startUnknown/.test(svgSrc)) bad('그림 내보내기의 종속 갈래 띠가 아직 점선');
  if (!/if \(!p\.singleHost\) continue;/.test(tsrc)) bad('이름표가 달린 소속에도 소속선을 그음 (매달린 탭을 가로지름)');
  if (!/if \(depLinkBlocked\(p\._dep, it, X, x\)\) continue;/.test(tsrc)) bad('세로 끈이 다른 속국의 이름표를 가로질러도 그음');
  if (/\.fam-dep \{[^}]*border-style: dashed/.test(csrc) || /\.tl-tab\.fam-dep \{ border-style: dashed/.test(csrc) || /kind-vassal[^{]*\{[^}]*dashed/.test(csrc)) bad('화면의 종속 갈래 띠 · 탭이 아직 점선 (점선은 추정 · 미정 연대의 몫)');
  if (/\.lg\.(fam-dep|k-vassal) \{[^}]*dashed/.test(vcss)) bad('범례의 종속 갈래 견본이 아직 점선');
  if (!/상국 띠 아래에 매달린 이름표/.test(vsrc) || !/상국 띠 안 맨 아래의 이름표/.test(vsrc) || /예속 띠\(띠 안 아래쪽\)/.test(vsrc)) bad('범례가 속국 이름표(매달린 탭 · 품은 칸)를 말하지 않음');
  if (TL && typeof TL.tabParts === 'function')
    for (const k of HT.POLITY_KINDS.filter(k => k.family === 'dependent')) {
      const t = TL.tabParts({ name: '가', polityKind: k.id, hosts: [] }, 1e6, null);
      if (t.kds.length) bad(`${k.name}의 책갈피 탭에 글자 딱지가 붙음 ("${t.kds[0].t}")`);
    }
  if (HT.POLITY_KINDS.some(k => k.family === 'dependent' && k.id !== 'client' && /점선 테두리|딱지 "/.test(k.hint))) // 복속 세력(client)만 조직체의 점선 테두리를 빌림(묶음 3 · 3번) bad('종속 갈래 종류의 설명(hint)이 아직 점선 테두리 · 딱지를 말함');
  if (HT.DEP_MIX || HT.depMix) bad('옛 예속 띠의 짙기 표(HT.DEP_MIX · depMix)가 남음');
}

/* ㉝ 글 손질(2026-09-19 감독 결정 — 건의 2 · 6 · 3 · 5의 낱말):
   ① 연표(보기 전용)에는 수정 내역 상자(🩹 «DLC»이(가) 고침)가 없음 — viewer.js의 patchHTML을 떼어 작은 검사 팩 · 패치(날짜 글로 시작 · 확실성)로 돌려
      !maker면 빈 글인지, 메이커의 상자에는 속 이름(날짜의 짝 칸 startAt …)이나 전후 글이 같은 줄이 없는지
   ② 칸 종류 표에 기간 낱말(span · during)이 없고, 칸 · 시기 · 지위 창은 이름 아래 날짜만(앞말 없이) · 칸 창의 사건 제목은 '이 시기의 사건'
   ③ 앱 파일(js · css · index.html · dlc-maker.html — 주석까지)에 특정 체제 낱말(재위 · 즉위 · 퇴위 · 재임 · 임기)과 옛 낱말 '계승'이 없는지
      (옛 파일 · 옛 붙여넣기의 승계 종류를 읽는 낱말 표 한 줄만 예외 — KEEP)
   ④ 한국어 승계 종류가 옛 낱말('직접 계승' …)과 새 낱말('직접 승계' …)을 모두 받는지 ⑤ 표시 체크 · 칸 창 스위치의 '같은 시기를 타국에도' · 범례의 실제 이름 예시
   (검토 반영) ① 줄을 뺄지는 글이 아니라 값으로 — 지도자 한 명의 이름만 바꾼 패치에도 지도자 줄이 남고(개수가 같아도 '1개 고침'), 두 DLC가 차례로 고친 칸의
      앞 상자는 그 DLC가 넣은 값까지, 메이커 '고친 것' 목록의 칸 수는 상자와 같은 규칙(HT.patchChanges)
   ⑥ 끝을 비워 진행 중인 정권의 끝까지 가는 칸(지도자 · 시기 · 지위 …)의 기간 글은 끝이 '현재' (계산된 오늘의 해를 끝난 해처럼 적지 않게 — HT.cellToNow) */
{
  const bad = msg => out.problems.push(`글 손질: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const viewerSrc = src('js/viewer.js');
  /* ① 수정 내역 */
  const a = viewerSrc.indexOf('  const FIELD_NAMES = {'), b = viewerSrc.indexOf('  function successionHTML(x) {');
  if (a < 0 || b < a) bad('viewer.js에서 수정 내역 글(FIELD_NAMES … patchHTML)을 찾지 못함');
  else {
    const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
    const whenText = (t, at) => (t == null || !isFinite(t) ? '' : HT.formatDate(t, at));
    const patchHTMLOf = maker =>
      new Function('HT', 'maker', 'state', 'esc', 'whenText', 'trackOf', 'precOf', `${viewerSrc.slice(a, b)}\nreturn patchHTML;`)(HT, maker, { model: { categoryMap: new Map() } }, esc, whenText, id => ({ id, name: id }), () => 'y');
    /* 합성 팩(지도자 셋인 정권 하나)과 그것을 고치는 패치 — 패치 DLC 견본이 없어졌으므로 여기서 짓는 작은 팩으로 봄 */
    const syn = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id: 'smoke-pb', name: 'x', tracks: [{ id: 't', name: 't' }], periods: [{ id: 'p', track: 't', name: '가', start: 1000, end: 1300, leaders: [['일', 1000, 1050], ['이', 1050, 1100], ['삼', 1100]] }] }).pack;
    const pp = (id, set) => HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id, name: id, tracks: [], periods: [], events: [], patches: [{ target: 'smoke-pb/p', set }] }).pack;
    const x = HT.buildModel([syn, pp('pb0', { start: '0990-03-01', certainty: 'estimated' })], null).byUid.get('smoke-pb/p'); // 날짜 글로 적은 시작(짝 칸 startAt) · 확실성
    if (!x || !(x.patchedBy || []).length) bad('검사 패치가 정권에 patchedBy를 달지 않아 검사하지 못함');
    else
      try {
        if (patchHTMLOf(null)(x) !== '') bad('연표(!maker)의 상세에 수정 내역 상자가 나옴 (patchHTML은 메이커에서만)');
        const box = patchHTMLOf({ isDraftId: () => false })(x);
        if (!/🩹/.test(box)) bad('메이커의 상세에 수정 내역 상자가 없음');
        const lines = (box.match(/<div class="desc">([\s\S]*?)<\/div>/) || ['', ''])[1].split('<br>').filter(l => !/^<i>/.test(l));
        const raw = lines.filter(l => /^[A-Za-z]+:/.test(l));
        if (raw.length) bad(`메이커의 수정 내역에 속 이름이 드러남: ${raw.join(' / ')}`);
        const same = lines.filter(l => {
          const m = l.match(/^[^:]+: (.*) → <b>(.*)<\/b>$/);
          return m && m[1] === m[2];
        });
        if (same.length) bad(`메이커의 수정 내역에 전후 글이 같은 줄이 낌: ${same.join(' / ')}`);
        /* 시작 · 확실성을 고친 패치: 짝 칸 startAt은 제 줄 없이 */
        if (lines.map(l => l.split(':')[0]).join() !== '시작,확실성') bad(`메이커의 수정 내역 줄이 '시작 · 확실성'이 아님: ${lines.join(' / ')}`);
        if (typeof HT.patchChanges !== 'function' || HT.patchChanges(x, 0).length !== 2) bad(`검사 패치가 고친 칸 수(HT.patchChanges)가 상자의 줄 수(2)와 다름`);
        /* 값으로 견주기: 합성 팩의 지도자 한 명 이름만 + 종류 · 두 DLC가 차례로 시작 · 기본값과 같은 목록 */
        const descOf = (packs2, n) => (patchHTMLOf({ isDraftId: () => false })(HT.buildModel([syn, ...packs2], null).byUid.get('smoke-pb/p')).match(/<div class="desc">([\s\S]*?)<\/div>/g) || [])[n] || '';
        const d1 = descOf([pp('pb1', { leaders: syn.periods[0].leaders.map((c, i) => (i === 1 ? Object.assign({}, c, { name: '둘' }) : c)), kind: 'puppet' })], 0);
        if (!/지도자: <b>3개<\/b> \(1개 고침\)/.test(d1) || !/종류: /.test(d1)) bad(`지도자 한 명의 이름만 바꾼 패치의 상자에 지도자 줄('3개 (1개 고침)')이 없음: ${d1}`);
        const d2 = descOf([pp('pb2', { start: 1010 }), pp('pb3', { start: 1020 })], 0);
        if (!/시작: 1000년 → <b>1010년<\/b>/.test(d2)) bad(`두 DLC가 차례로 시작을 고쳤을 때 앞 DLC의 상자가 제 값(1010년)이 아님: ${d2}`);
        const d3 = descOf([pp('pb4', { leaders: syn.periods[0].leaders })], 0);
        if (/지도자/.test(d3)) bad(`기본값과 같은 지도자 목록을 담은 패치의 상자에 지도자 줄이 낌: ${d3}`);
        if (/filter\(k => !HT\.DATE_AT_KEYS\.includes\(k\)\)\.length\}칸/.test(src('js/maker.js')) || !/고침 \$\{patchCount\(p\)\}칸/.test(src('js/maker.js'))) bad("메이커 '고친 것' 목록의 칸 수가 상자와 같은 규칙(HT.patchChanges)이 아님");
      } catch (e) {
        bad(`patchHTML을 떼어 돌리지 못함: ${e && e.message}`);
      }
  }
  /* ② 칸 창은 연도만 */
  const worded = HT.CELL_KINDS.filter(k => 'span' in k || 'during' in k).map(k => k.id);
  if (worded.length) bad(`칸 종류 표에 기간 낱말(span · during)이 남음: ${worded.join(', ')}`);
  const cellFn = viewerSrc.slice(viewerSrc.indexOf('  function cellDetailHTML(x, ref) {'), viewerSrc.indexOf('  function cellEvents('));
  if (/K\.span|K\.during/.test(viewerSrc)) bad('칸 창이 칸 종류 표의 기간 낱말(K.span · K.during)을 읽음');
  if (!/<p class="when">\$\{esc\(when\)\}/.test(cellFn)) bad('칸 창의 날짜 줄에 앞말이 붙음 (이름 아래 날짜만)');
  const ownFn = viewerSrc.slice(viewerSrc.indexOf('  function ownEventsHTML('), viewerSrc.indexOf('\n  }', viewerSrc.indexOf('  function ownEventsHTML(')));
  if (!/ownEventsHTML\(evs\)/.test(cellFn) || !/<h3>이 시기의 사건 <small>/.test(ownFn)) bad("칸 창의 사건 제목이 '이 시기의 사건'이 아님"); // 목록은 칸 · 시기 창이 함께 쓰는 ownEventsHTML(㊲ — 숨은 소속의 사건도)
  if (/<p class="when">기간 /.test(viewerSrc)) bad("시기 · 지위 창의 날짜 줄에 '기간 '이 붙음");
  /* ③ 앱 파일의 낱말 */
  const WORDS = /재위|즉위|퇴위|재임|임기|계승/;
  const KEEP = [/^\s*Object\.assign\(SUCCESSION_WORDS, \{ '직접 계승': 'direct', '간접 계승': 'indirect', '부흥 계승': 'revival', '부분 계승': 'partial' \}\); \/\/ 옛 낱말$/]; // js/core.js — 옛 파일 · 옛 붙여넣기의 승계 종류
  const listDir = (d, ext) => readdirSync(join(root, d)).filter(f => f.endsWith(ext)).map(f => `${d}/${f}`);
  const appFiles = [...listDir('js', '.js'), ...listDir('css', '.css'), 'index.html', 'dlc-maker.html'];
  const left = [];
  for (const f of appFiles) src(f).split('\n').forEach((l, i) => WORDS.test(l) && !KEEP.some(r => r.test(l)) && left.push(`${f}:${i + 1} «${l.match(WORDS)[0]}»`));
  if (left.length) bad(`앱 파일에 특정 체제 낱말 · 옛 낱말이 남음: ${left.slice(0, 8).join(' · ')}${left.length > 8 ? ` 외 ${left.length - 8}곳` : ''}`);
  if (!KEEP.every(r => src('js/core.js').split('\n').some(l => r.test(l)))) bad('옛 승계 낱말을 읽는 줄(js/core.js)이 없어짐 — 예외 목록(KEEP)도 함께 고칠 것');
  /* ④ 승계 종류의 한국어 낱말: 옛 낱말도 새 낱말도 */
  for (const [w, id] of [['직접 계승', 'direct'], ['직접 승계', 'direct'], ['간접 계승', 'indirect'], ['간접 승계', 'indirect'], ['부흥 계승', 'revival'], ['부흥 승계', 'revival'], ['직접', 'direct'], ['부흥', 'revival'], ['부분', 'partial'], ['부분 승계', 'partial'], ['부분 계승', 'partial']])
    if (HT.successionType(w) !== id) bad(`승계 종류 "${w}"를 ${id}로 읽지 못함 (${HT.successionType(w)})`);
  if (HT.successionName('direct') !== '직접 승계' || HT.successionName('indirect') !== '간접 승계') bad(`승계 종류의 화면 이름이 '직접 승계' · '간접 승계'가 아님 (${HT.successionName('direct')} · ${HT.successionName('indirect')})`);
  const pk = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id: 'smoke-succ', name: 'x', tracks: [{ id: 't', name: 't' }], periods: [{ track: 't', name: '가', start: 1, end: 5 }, { track: 't', name: '나', start: 5, end: 9, succeeds: [{ from: '가', type: '직접 계승' }] }, { track: 't', name: '다', start: 9, end: 12, succeeds: [{ from: '나', type: '직접 승계' }] }] });
  if (!pk.pack || pk.pack.periods.map(p => (p.succeeds || []).map(s => s.type).join()).join('|') !== '|direct|direct') bad(`파일의 승계 종류 글('직접 계승' · '직접 승계')을 direct로 읽지 못함 (${pk.pack && JSON.stringify(pk.pack.periods.map(p => p.succeeds))})`);
  /* ⑤ 타국 · 실제 이름 예시 */
  const oldEcho = appFiles.filter(f => src(f).includes('같은 시기를 다른 나라에도'));
  if (oldEcho.length) bad(`'같은 시기를 다른 나라에도'가 남음: ${oldEcho.join(', ')}`);
  for (const f of ['index.html', 'dlc-maker.html']) {
    if (!/<input id="spotEchoToggle" type="checkbox"> 같은 시기를 타국에도<\/label>/.test(src(f))) bad(`${f}의 표시 체크가 '같은 시기를 타국에도'가 아님`);
    if (!/<input id="linkToggle" type="checkbox" checked> 승계선<\/label>/.test(src(f))) bad(`${f}의 표시 체크가 '승계선'이 아님`);
    if (!/title="띠 위쪽에 지도자 칸을 보여 줍니다"><input id="leaderToggle"/.test(src(f))) bad(`${f}의 지도자 체크 풍선이 중립 글이 아님`);
  }
  /* 창 안의 스위치는 칸 · 시기 · 지위 · 왕조 · 인물 창이 함께 쓰는 echoSwitchHTML 하나(㊲) */
  if ((viewerSrc.match(/data-spot-echo\$\{echoOn\(\) \? ' checked' : ''\}> 같은 시기를 타국에도<\/label>/g) || []).length !== 1 || (viewerSrc.match(/\$\{echoSwitchHTML\(\)\}/g) || []).length !== 5) bad("칸 · 시기 · 지위 · 왕조 · 인물 창의 스위치가 '같은 시기를 타국에도'가 아님");
  if (/통감부/.test(viewerSrc)) bad('범례에 실제 역사 이름 예시(통감부)가 남음');
  if (!/service: '활동 기록'/.test(viewerSrc) || /'섬김'|>섬긴 기록 </.test(viewerSrc)) bad("인물 창의 '섬긴 기록 · 섬김'이 '활동 기록 · 활동'으로 바뀌지 않음");
  /* ⑥ 진행 중인 정권의 끝까지 가는 칸 */
  if (typeof HT.cellToNow !== 'function') bad('HT.cellToNow가 없음');
  else {
    const on = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id: 'smoke-now', name: 'x', tracks: [{ id: 't', name: 't' }], periods: [
      { id: 'q', track: 't', name: '가', start: 1948, ongoing: true, leaders: [['갑', 1948, 1960], ['을', 2025]], phases: [{ spans: [['앞', 1948, 1990], ['뒤', 1990]] }], ranks: [['공화국', 1948]] },
      { id: 'r', track: 't', name: '나', start: 1000, end: 1100, leaders: [['병', 1000]] },
    ] }).pack;
    const m2 = on && HT.buildModel([on], null);
    const q = m2 && m2.byUid.get('smoke-now/q'), r = m2 && m2.byUid.get('smoke-now/r');
    if (!q || !r) bad('진행 중인 정권의 칸 검사용 팩을 만들지 못함');
    else {
      if (!HT.cellToNow(q.leaders[1], q) || HT.cellToNow(q.leaders[0], q) || HT.cellToNow(r.leaders[0], r)) bad('HT.cellToNow가 끝을 비운 마지막 지도자(진행 중인 정권)만 고르지 않음');
      const ph = (q.phaseSchemes || [])[0];
      if (!ph || !/ ~ 현재$/.test(HT.phaseRangeText(ph.spans[1], q)) || / ~ 현재$/.test(HT.phaseRangeText(ph.spans[0], q))) bad(`진행 중인 정권의 마지막 시기 글이 '~ 현재'가 아님: ${ph && HT.phaseRangeText(ph.spans[1], q)}`);
      if (!(q.rankSpans || []).length || !HT.cellToNow(q.rankSpans[q.rankSpans.length - 1], q)) bad('진행 중인 정권의 마지막 지위가 끝을 현재로 보지 않음');
    }
  }
  if (!/const when = HT\.formatRange\(\{[^}]*ongoing: HT\.cellToNow\(c, x\) \}\)/.test(cellFn)) bad("칸 창의 날짜 줄이 진행 중인 정권의 끝까지 가는 칸을 '~ 현재'로 적지 않음");
  if (!/const cellWhen = \(c, useEndY = c\.end == null, p = null\) =>[^\n]*\n[^\n]*ongoing: HT\.cellToNow\(c, p\)/.test(viewerSrc) || !/const rankRange = \(c, p\) => [^\n]*ongoing: HT\.cellToNow\(c, p\)/.test(viewerSrc)) bad("칸 목록 · 지위 목록의 기간 글이 진행 중인 정권의 끝까지 가는 칸을 '~ 현재'로 적지 않음");
}

/* ㉞ 승계 이음매(2026-09-19 감독 결정 — 건의 5 'A 최종안: 관문 + 환승 다리, 다리 색 반반'): 노드에서 js/timeline.js의 공개 도우미로 기하를 확인합니다.
   ① 줄 만들기(chainRows): 같은 해에 시작하는 무리는 직접 승계로 이은 수 → 이은 수가 가장 많은 배치(한 선대의 줄을 둘이 다투면 직접이 먼저 · 직접 · 간접 선대를 함께 둔 후대는 직접 쪽 줄 —
      같은 점수면 예전 규칙) · 곧바로 이어지는 쌍만 _seamL · _seamR(미정 · 연대 폭인 끝은 빼고)
   ② 네모 비키기(_squares · seamPush): 이음매 쪽 네모가 3·clamp(1 − 틈/12)px 더 안으로 — 틈에 따라 끊김 없이, 네모 하나뿐인 좁은 띠는 비키지 않음
   ③ 다리(seamBridge): 기본팩 + 모든 견본의 곧바로 이어지는 쌍마다 여러 배율에서 — 조각은 두 네모 사이(각 네모 + 1px 밖)에만 · 양 끝이 칠로 끝남 · 이음매에서 왼쪽 반은 선대 · 오른쪽 반은 후대 ·
      점선은 이음매 한가운데가 빔 · 부흥은 이음매 위 고리 · 문은 테두리 ± 0.5px를 덮고(맞닿으면 한 문) 네모에 닿지 않으며 띠의 곧은 테두리 구간(둥근 모서리 10px 밖) 안
   ④ 관문(gatePiece) · 가는 선(부분 승계 — 종류 표의 thin · 밀도의 가는 선 값 G.thin)
   ⑤ 사건 글자와의 간격 ≥ 1.5px: 네모(와 내림줄 · 오름줄) 둘레 3.5 + 1.5px를 글자가 비켜 감 — 글줄이 하나면 그 글줄(+ 점), 둘 이상이면 네모가 걸친 두 글줄 · 화면과 그림 내보내기가 같은 도우미(_sqZones) ·
      접힌 하위 사건 수 알약도 이름 폭에
   ⑥ 글로 읽어: 올리거나 고를 때 승계선 · 소속선은 굵기 그대로(색만) · 그림 내보내기가 네모 · 선 · 다리를 그림 · 범례 견본 · 메이커 승계 줄은 소속 줄처럼 짧은 칸 이름(예시 값 없음) · 상세 목록의 연도 줄바꿈 금지 · 어두운 화면의 문 ·
      띠 위 조각은 누름을 밑의 띠로 · 그림 내보내기의 가림막이 전설 · 반전설 띠에서는 안개만큼 · 범례 글이 낱말 중간에서 꺾이지 않음
   ⑦ 띠 위 조각의 길이(_linkPlan을 가짜 트랙으로): 관문은 네모 ↔ 제 띠 테두리의 짧은 끝뿐 — 연대 폭이 있는 끝(네모가 끝 해에 섬)은 관문 · 다리 없이 띠 뒤 선만(획이 연대 폭 구간의 사건 점을 가로지르지 않게),
      맞닿은 두 띠에서 관문이 한쪽만 서는 반쪽 다리 없음 */
{
  const bad = msg => out.problems.push(`승계 이음매: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  try {
    if (!HT.Timeline) vm.runInThisContext(src('js/timeline.js'), { filename: 'js/timeline.js' });
  } catch (e) {
    bad(`js/timeline.js를 노드에서 읽지 못함 — ${e.message}`);
  }
  const TL = HT.Timeline || {};
  const need = ['SUCC_KINDS', 'succKind', 'chainRows', 'seamPush', 'seamBridge', 'gatePiece', 'beatRuns', 'thinOf', 'seamSample'];
  const miss = need.filter(k => !TL[k]);
  if (miss.length) bad(`Timeline에 이음매 도우미가 없음: ${miss.join(', ')}`);
  else {
    const { chainRows, seamPush, seamBridge, gatePiece, thinOf, succKind, SQ_CLEAR, G } = TL;
    const near = (a, b, e = 1e-6) => Math.abs(a - b) <= e;
    const sqOf = (p, X, lines = 2) => TL.prototype._squares.call({ W: Infinity }, p, X, lines);
    const P = (name, start, endY, pre = [], extra = {}) => Object.assign({ name, uid: name, start, endY, predecessors: pre }, extra);
    /* ① 줄 만들기 · 이음매 표시 */
    {
      const q = P('앞', 0, 100);
      const a = P('긴 간접', 100, 400, [{ from: q, type: 'indirect' }]);
      const b = P('짧은 직접', 100, 150, [{ from: q, type: 'direct' }]);
      const rows = chainRows([q, a, b]);
      const rq = rows.find(r => r.includes(q));
      if (!rq || !rq.includes(b) || rq.includes(a)) bad(`같은 해에 시작하는 두 후대 가운데 직접 승계가 선대의 줄을 잇지 않음: ${rows.map(r => r.map(x => x.name).join('→')).join(' | ')}`);
      if (q._seamR !== b || b._seamL !== q || a._seamL) bad('곧바로 이어지는 쌍의 이음매 표시(_seamR · _seamL)가 어긋남');
      const q2 = P('앞2', 0, 100);
      const r1 = P('긴 부흥', 100, 400, [{ from: q2, type: 'revival' }]);
      const i1 = P('짧은 간접', 100, 150, [{ from: q2, type: 'indirect' }]);
      const rows2 = chainRows([q2, r1, i1]);
      if (!rows2.find(r => r.includes(q2)).includes(r1)) bad('같은 급(부흥 · 간접)끼리는 예전처럼 byStart 차례(긴 나라)가 아님');
      const q3 = P('끝 미정', 0, 100, [], { endUnknown: true });
      const p3 = P('뒤', 100, 200, [{ from: q3, type: 'direct' }]);
      chainRows([q3, p3]);
      if (q3._seamR || p3._seamL) bad('끝이 미정인 쌍에 이음매 표시가 붙음 (사라지는 꼬리에는 다리를 놓지 않음)');
      const lone = P('홀로', 100, 130);
      chainRows([P('앞4', 0, 100), lone]);
      if (lone._seamL) bad('승계가 없는 이웃에 이음매 표시가 붙음');
      /* 직접 · 간접 선대를 함께 둔 후대: 직접 선대의 줄로 — 간접 선대의 줄은 그 줄을 이을 다른 후대에게 (검토에서 나온 퇴행: X → A | Y | B) */
      const names = rows => rows.map(r => r.map(x => x.name).join('→')).join(' | ');
      const X = P('X', 0, 100);
      const Y = P('Y', 10, 100);
      const A = P('A', 100, 200, [{ from: X, type: 'indirect' }, { from: Y, type: 'direct' }]);
      const B = P('B', 100, 300, [{ from: X, type: 'indirect' }]);
      for (const order of [[X, Y, B, A], [X, Y, A, B]]) {
        const got = names(chainRows(order));
        if (got !== 'X→B | Y→A' || A._seamL !== Y) bad(`직접 · 간접 선대를 함께 둔 후대가 직접 선대의 줄을 잇지 않음 (${order.map(x => x.name).join(',')}): ${got}`);
      }
      /* 두 줄을 모두 직접으로 이을 수 있으면 둘 다 — 먼저 놓이는 후대가 다른 후대의 하나뿐인 줄을 차지하지 않게 */
      const X2 = P('X2', 0, 100);
      const Y2 = P('Y2', 10, 100);
      const A2 = P('A2', 100, 300, [{ from: X2, type: 'direct' }, { from: Y2, type: 'direct' }]);
      const B2 = P('B2', 100, 200, [{ from: X2, type: 'direct' }]);
      const got2 = names(chainRows([X2, Y2, A2, B2]));
      if (got2 !== 'X2→B2 | Y2→A2') bad(`두 후대가 두 선대의 줄을 모두 잇지 않음: ${got2}`);
      /* 연대 폭이 있는 끝(네모가 끝 해에 서서 테두리와 떨어짐)은 이음매 표시 없음 — 비키기 · 다리 없이 띠 뒤 선만 */
      const q5 = P('끝 폭', 0, 90, [], { endRange: [80, 100] });
      const p5 = P('뒤5', 100, 200, [{ from: q5, type: 'direct' }]);
      const r5 = P('시작 폭', 210, 300, [{ from: p5, type: 'direct' }], { startRange: [200, 220] });
      chainRows([q5, p5, r5]);
      if (q5._seamR || p5._seamL || p5._seamR || r5._seamL) bad('연대 폭이 있는 끝의 쌍에 이음매 표시가 붙음');
    }
    /* ② 네모 비키기 */
    {
      if (!near(seamPush(0), 3) || !near(seamPush(6), 1.5) || !near(seamPush(12), 0) || !near(seamPush(40), 0)) bad(`seamPush(0 · 6 · 12 · 40)가 3 · 1.5 · 0 · 0이 아님`);
      let jump = 0;
      for (let g = 0; g < 20; g += 0.05) jump = Math.max(jump, Math.abs(seamPush(g + 0.05) - seamPush(g)));
      if (jump > 0.02) bad(`네모 비키기가 틈에 따라 이어지지 않음 (0.05px에 ${jump.toFixed(3)}px)`);
      const X = y => y * 2;
      for (const gy of [0, 1, 3, 6, 20]) {
        const q = P('가', 0, 100);
        const p = P('나', 100 + gy, 300, [{ from: q, type: 'direct' }]);
        chainRows([q, p]);
        const e = seamPush(X(100 + gy) - X(100));
        const m = G.bw + 2 + G.sq / 2;
        const sq = sqOf(q, X);
        const sp = sqOf(p, X);
        if (!near(sq.ec, X(100) - m - e) || !near(sp.fc, X(100 + gy) + m + e)) bad(`틈 ${gy * 2}px에서 네모가 ${e.toFixed(2)}px 비켜 앉지 않음 (ec ${sq.ec} · fc ${sp.fc})`);
      }
      const q = P('좁은 앞', 0, 100);
      const n = P('좁은 띠', 100, 106.5, [{ from: q, type: 'direct' }]);
      const r = P('좁은 뒤', 106.5, 200, [{ from: n, type: 'direct' }]);
      chainRows([q, n, r]);
      const sn = sqOf(n, y => y * 2);
      if (sn.showF && (sn.fc - 3.5 < 200 + 1 - 1e-6 || sn.fc + 3.5 > 213 - 1 + 1e-6)) bad(`네모 하나뿐인 좁은 띠의 네모가 띠 테두리에 걸림 (fc ${sn.fc}, 띠 200 ~ 213)`);
    }
    /* ③ 다리 — 기본팩 + 견본의 실제 쌍, 여러 배율 (가는 선인 부분 승계도 같은 규칙으로 — 굵기 · 자리는 ㊸) */
    const bridgeCheck = (q, p, X, type, where) => {
      const sq = sqOf(q, X);
      const sp = sqOf(p, X);
      const qe = X(q.endRange ? q.endRange[1] : q.endY);
      const pf = X(p.startRange ? p.startRange[0] : p.start);
      const xa = sq.ec + G.sq / 2 + 1;
      const xb = sp.fc - G.sq / 2 - 1;
      if (!(sq.showE && sp.showF && xa <= qe - 1.5 && xb >= pf + 1.5)) return false; // 네모가 없거나 테두리에 붙은 먼 보기 — 다리 없음(규칙)
      const y = 30;
      const kind = succKind(type);
      const sg = G.thin;
      const br = seamBridge({ qe, pf, xa, xb, y, kind, sg });
      const mid = (qe + pf) / 2;
      const say = msg => bad(`${where} ${q.name} → ${p.name} (${type}, 틈 ${(pf - qe).toFixed(2)}px): ${msg}`);
      if (!br.segs.length) return say('다리 조각이 없음'), true;
      const thin = thinOf(kind, sg);
      const doorH = 4.4;
      const lineY = thin && thin.crisp ? Math.floor(y) + 0.5 : y; // 부분 승계의 1px 선은 픽셀 칸 가운데(.5)에 (timeline.js crispAt)
      if (br.segs.some(s => s.x2 < s.x1 || s.y1 !== s.y2 || !near(s.y1, lineY) || (thin ? s.w !== thin.w : s.w != null))) say('다리 조각이 가로 한 획(가는 선이면 제 굵기 · 픽셀 칸 가운데)이 아님');
      {
        const segs = br.segs;
        const lo = Math.min(...segs.map(s => s.x1));
        const hi = Math.max(...segs.map(s => s.x2));
        if (!near(lo, xa, 1e-6) || !near(hi, xb, 1e-6)) say(`다리가 두 네모(+1px) 사이를 꼭 채우지 않음 [${lo.toFixed(2)}, ${hi.toFixed(2)}] ≠ [${xa.toFixed(2)}, ${xb.toFixed(2)}]`);
        if (segs.some(s => (s.side === 'q' ? s.x2 > mid + 1e-6 : s.x1 < mid - 1e-6))) say('이음매 왼쪽이 선대 · 오른쪽이 후대 색이 아님');
        if (!kind.beat) {
          const cover = segs.reduce((w, s) => w + (s.x2 - s.x1), 0);
          if (!near(cover, xb - xa, 1e-6)) say('실선 다리가 끊김');
        } else {
          const inner = segs.filter(s => s.x1 < mid && s.x2 > mid);
          const gapL = Math.max(...segs.filter(s => s.x2 <= mid + 1e-9).map(s => s.x2), -Infinity);
          const gapR = Math.min(...segs.filter(s => s.x1 >= mid - 1e-9).map(s => s.x1), Infinity);
          if (inner.length || !near(gapR - gapL, kind.beat[1], 1e-6) || !near((gapL + gapR) / 2, mid, 1e-6)) say(`점선 다리의 이음매 한가운데가 박자의 빔(${kind.beat[1]}px)이 아님`);
          if (segs.some(s => s.x2 - s.x1 < 1.5)) say('점선 다리에 1.5px보다 짧은 칠이 있음');
        }
      }
      if (kind.ring ? !br.ring || !near(br.ring.x, mid) || br.ring.y !== y : br.ring) say('부흥의 고리가 이음매 위에 없음(또는 부흥이 아닌데 고리)');
      const doorsOk = pf - qe < 0.5 ? br.doors.length === 1 && br.doors[0].seam && near(br.doors[0].x, qe - 1.5) && near(br.doors[0].x + br.doors[0].w, pf + 1.5) : br.doors.length === 2 && near(br.doors[0].x, qe - 1.5) && near(br.doors[0].w, 2) && near(br.doors[1].x, pf - 0.5) && near(br.doors[1].w, 2);
      if (!doorsOk) say(`문이 테두리 ± 0.5px를 덮지 않음: ${JSON.stringify(br.doors)}`);
      if (br.doors.some(d => d.x < sq.ec + G.sq / 2 + 0.8 || d.x + d.w > sp.fc - G.sq / 2 - 0.8)) say('문이 네모(테두리 굵기 포함)에 닿음');
      if (br.doors.some(d => !near(d.y + d.h / 2, y) || !near(d.h, doorH))) say(`문의 높이가 선 가운데 ${doorH}px가 아님`);
      return true;
    };
    let seen = 0;
    const byType = { direct: 0, indirect: 0, revival: 0, partial: 0 };
    if (model) {
      const bs = p => (p.startRange ? p.startRange[0] : p.start);
      const be = p => (p.endRange ? p.endRange[1] : p.endY);
      const groups = new Map();
      for (const p of model.periods) {
        if (p.polityKind === 'dynasty' || p.polityKind === 'overlay' || p.endY == null) continue;
        p._seamL = p._seamR = null;
        const key = `${p.track}|${(p.peoplePath || []).map(x => x.id).join('/')}`;
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(p);
      }
      for (const list of groups.values()) {
        list.sort((a, b) => bs(a) - bs(b) || be(b) - be(a));
        for (const row of chainRows(list))
          for (let k = 1; k < row.length; k++) {
            const q = row[k - 1];
            const p = row[k];
            if (p._seamL !== q) continue;
            const se = p.predecessors.find(e => e.from === q) || {};
            const type = se.type;
            for (const kpx of [0.25, 0.7, 2, 6, 20]) if (bridgeCheck(q, p, y => y * kpx, type, `${kpx}px/년`)) (seen++, (byType[type] = (byType[type] || 0) + 1));
          }
      }
      for (const p of model.periods) p._seamL = p._seamR = null;
    }
    /* 합성 쌍: 네 종류 × 틈 0 ~ 넓음 (견본에 없는 부흥 맞닿음도 · 부분 승계는 정도 셋 — 정도가 달라도 선은 같음) */
    for (const type of ['direct', 'indirect', 'revival', 'partial'])
      for (const gy of [0, 0.1, 0.5, 2, 3, 6, 30])
        for (const degree of type === 'partial' ? [1, 2, 3] : [null]) {
          const q = P('합성 앞', 0, 100);
          const edge = { from: q, type, degree };
          const p = P('합성 뒤', 100 + gy, 250, [edge]);
          chainRows([q, p]);
          if (bridgeCheck(q, p, y => y * 2, type, '합성')) (seen++, byType[type]++);
        }
    if (seen < 200 || !byType.direct || !byType.indirect || !byType.revival || !byType.partial) bad(`다리를 본 쌍이 너무 적음 (${seen}개 · ${JSON.stringify(byType)})`);
    {
      const br = seamBridge({ qe: 100, pf: 100, xa: 95, xb: 105, y: 0, kind: succKind('indirect') });
      if (br.segs.map(s => (s.x2 - s.x1).toFixed(2)).join(',') !== '3.00,3.00') bad(`맞닿은 간접 승계의 다리가 3 · 4 · 3이 아님: ${JSON.stringify(br.segs)}`);
      /* 가장 작은 띠(글줄 하나 · 칸 없음)에서도 문이 곧은 테두리 구간(모서리 10px 밖) 안: 줄 높이 = 여백 + 글줄 + 여백, 네모 높이 = 글줄 가운데 */
      const rowH = G.inset * 2 + G.line;
      const ay = G.inset + G.line / 2;
      if (ay - 2.2 < 10 || ay + 2.2 > rowH - 10) bad(`가장 낮은 띠에서 문이 둥근 모서리에 걸림 (높이 ${rowH} · 네모 ${ay})`);
    }
    /* ④ 관문 · 가는 선 */
    {
      const gh = gatePiece({ a: 90.5, b: 100.5, at: 20, vertical: false, border: [99, 100], kind: succKind('direct') });
      if (!near(gh.door.x, 98.5) || !near(gh.door.w, 2) || !near(gh.door.h, 4.4) || gh.segs.length !== 1 || gh.segs[0].x1 !== 90.5 || gh.segs[0].x2 !== 100.5) bad(`가로 관문의 자리가 어긋남: ${JSON.stringify(gh)}`);
      const gv = gatePiece({ a: 34.5, b: 60.5, at: 40, vertical: true, border: [59, 60], kind: succKind('indirect') });
      if (!near(gv.door.y, 58.5) || !near(gv.door.h, 2) || !near(gv.door.w, 4.4) || gv.segs.some(s => s.x1 !== 40 || s.x2 !== 40) || gv.segs[0].y1 !== 34.5 || gv.segs[gv.segs.length - 1].y2 !== 60.5) bad(`세로 관문(내림줄)의 자리가 어긋남: ${JSON.stringify(gv)}`);
      /* 부분 승계(종류 표의 넷째 줄 — 가는 실선 하나): 다리 · 관문이 한 획 · 밀도의 가는 선 굵기 · 다른 승계와 같은 문 (자세한 것은 ㊸) */
      const partial = TL.SUCC_KINDS.partial || {};
      const sg = TL.G.thin || { w: 1 };
      if (!TL.SUCC_KINDS.partial || !TL.G.thin) bad('승계선 종류 표에 부분 승계가 없거나 밀도에 가는 선 값(G.thin)이 없음');
      if (thinOf(partial, sg) !== sg || thinOf(succKind('direct'), sg) !== null) bad('가는 선의 종류가 부분 승계뿐이 아님(thinOf)');
      const bp = seamBridge({ qe: 100, pf: 100, xa: 95, xb: 105, y: 0, kind: partial, sg });
      if (bp.segs.length !== 2 || bp.segs.some(s => s.w !== sg.w) || !near(bp.doors[0].h, 4.4)) bad(`가는 선의 다리 · 문이 어긋남: ${bp.segs.length}조각 · 문 높이 ${bp.doors[0].h}`);
      if (Object.keys(TL.SUCC_KINDS).join() !== 'direct,indirect,revival,partial' || TL.SUCC_KINDS.direct.dash || TL.SUCC_KINDS.indirect.dash !== '5 4' || !TL.SUCC_KINDS.revival.ring || !TL.SUCC_KINDS.partial.thin || TL.SUCC_KINDS.partial.dash || TL.SUCC_KINDS.partial.strands) bad('승계선 종류 표(SUCC_KINDS)가 직접 실선 · 간접 5 4 점선 · 부흥 고리 · 부분 가는 실선 하나가 아님');
      const legend = TL.seamSample('revival');
      if (!/class="tl-door is-seam"/.test(legend) || (legend.match(/class="tl-seg"/g) || []).length < 2 || !/tl-seg is-ring/.test(legend) || !/tl-sq is-fall/.test(legend)) bad('범례의 다리 견본이 문 · 다리 · 고리 · 네모를 그리지 않음');
    }
    /* ⑤ 사건 글자와의 간격 */
    {
      const one = [];
      const two = [[], [], []];
      const nd = [];
      TL.prototype._sqZones.call({}, { fc: 10, ec: 50, showF: true, showE: true }, [one], nd);
      TL.prototype._sqZones.call({}, { fc: 10, ec: 50, showF: true, showE: false }, two.slice(0, 2), null);
      const half = G.sq / 2 + SQ_CLEAR;
      if (SQ_CLEAR < 1.5 || JSON.stringify(one) !== JSON.stringify([[10 - half, 10 + half, 2], [50 - half, 50 + half, 2]]) || nd.length !== 2) bad(`글줄 하나인 줄의 네모 자리(네모 + 1.5px · 점 밀어내기 · 표시 2 = 점 쪽 끝 ~ 글자 끝이 비킴)가 어긋남: ${JSON.stringify(one)}`);
      if (two[0].length !== 1 || two[1].length !== 1 || two[2].length || two[0][0][2] !== 1 || two[1][0][2] !== 1) bad('글줄 둘 이상인 줄에서 네모가 걸친 두 글줄만 · 글자만(표시 1 — 점은 네모와 닿지 않음) 비켜 가지 않음 (㊷ ①: 이름을 숨기지 않고)');
    }
    /* ⑦ 띠 위 조각의 길이 — 가짜 트랙(줄 높이 29 · 글줄 하나)에서 _linkPlan */
    {
      const plan = (list, rowOf, X) => {
        for (const p of list) p._seamL = p._seamR = null;
        chainRows(list.slice());
        const n = Math.max(...list.map(rowOf)) + 1;
        const rowPeriods = Array.from({ length: n }, () => []);
        for (const p of list) rowPeriods[(p._row = rowOf(p))].push(p);
        const tr = { id: 't', periods: list, rows: n, rowTop: Array.from({ length: n }, (_, i) => 12 + i * 40), rowHs: Array(n).fill(29), rowGap: Array(n).fill(11), geo: { lines: 1, textTop: 4, lineH: 21 }, geos: null, hiddenRows: new Set(), foldedRows: new Set(), commonRow: -1, scopeBranches: [], rowPeriods, eventsByRow: [] };
        return TL.prototype._linkPlan.call(Object.assign(Object.create(TL.prototype), { show: { succession: 'all', partOf: false }, W: 3000 }), tr, X, 3000);
      };
      const T = (name, start, endY, pre = [], extra = {}) => P(name, start, endY, pre, Object.assign({ track: 't', color: '#bba395' }, extra));
      const X = y => y * 2;
      const lines = pl => pl.top.filter(t => t.line);
      const span = t => Math.max(...t.line.segs.map(s => Math.max(s.x1, s.x2))) - Math.min(...t.line.segs.map(s => Math.min(s.x1, s.x2)));
      const gateMax = G.bw + 1 + seamPush(0, true) + 0.5 + 0.5; // 네모 + 1px ↔ 테두리 밖 0.5px (직접이 아닌 이음매의 6px까지 — 묶음 5 · 7번)
      try {
        /* 보통 맞닿음: 다리 한 묶음 (대조) */
        const a = T('보통 앞', 100, 300);
        const b = T('보통 뒤', 300, 400, [{ from: a, type: 'direct' }]);
        const pa = plan([a, b], () => 0, X);
        if (!lines(pa).some(t => t.line.segs.some(s => s.side))) bad('가짜 트랙의 보통 맞닿음에 다리가 없음 (검사 틀 확인)');
        /* 연대 폭이 있는 끝: 같은 줄 맞닿음 · 틈 · 다른 줄(해가 겹쳐 돌아감) — 띠 위 조각이 연대 폭 구간을 가로지르지 않음 */
        const cases = [
          ['같은 줄 맞닿음', T('폭 앞', 100, 280, [], { endRange: [270, 320] }), q => T('폭 뒤', 320, 400, [{ from: q, type: 'direct' }]), () => 0],
          ['같은 줄 틈', T('폭 앞2', 100, 250, [], { endRange: [240, 300] }), q => T('폭 뒤2', 330, 400, [{ from: q, type: 'indirect' }], { startRange: [300, 340] }), () => 0],
          ['다른 줄', T('폭 앞3', 100, 280, [], { endRange: [270, 330] }), q => T('폭 뒤3', 250, 400, [{ from: q, type: 'direct' }]), (p, q) => (p === q ? 0 : 1)],
        ];
        for (const [what, q, mk, row] of cases) {
          const p = mk(q);
          const pl = plan([q, p], x => row(x, q), X);
          const long = lines(pl).filter(t => span(t) > gateMax);
          if (long.length) bad(`연대 폭이 있는 끝(${what})에 띠 위 조각이 길게 그어짐 — ${long.map(t => span(t).toFixed(1)).join(' · ')}px (관문은 ${gateMax}px까지)`);
          if (pl.top.some(t => t.uid === q.uid)) bad(`연대 폭이 있는 끝(${what})의 선대 쪽에 관문 · 문이 섬`);
        }
        /* 맞닿은 두 띠(이음매 표시 없음 — 선대 끝에 연대 폭)에서 후대 쪽 관문만 서는 반쪽 다리 없음 */
        const q6 = T('반쪽 앞', 100, 280, [], { endRange: [270, 320] });
        const p6 = T('반쪽 뒤', 320, 400, [{ from: q6, type: 'direct' }]);
        if (plan([q6, p6], () => 0, X).top.length) bad('맞닿은 두 띠에서 한쪽 관문만 서서 반쪽 다리가 됨');
        /* 연대 폭이 있어도 틈이 있으면 후대 쪽 관문은 그대로 (띠 뒤 선이 틈에서 보이고 후대 네모까지 이어짐) */
        const q7 = T('틈 앞', 100, 280, [], { endRange: [270, 300] });
        const p7 = T('틈 뒤', 330, 400, [{ from: q7, type: 'direct' }]);
        const pl7 = plan([q7, p7], () => 0, X);
        if (!pl7.top.some(t => t.uid === p7.uid && t.line) || pl7.top.some(t => t.uid === q7.uid)) bad('틈이 있는 연대 폭 쌍에서 후대 쪽 관문만 서지 않음');
      } catch (e) {
        bad(`가짜 트랙의 _linkPlan이 멈춤 — ${e.message}`);
      }
    }
  }
  /* ⑥ 글로 읽어 (도우미가 없어도 따로 봄) */
  {
    const tsrc = src('js/timeline.js');
    const csrc = src('css/common.css');
    const drawSrc = tsrc.slice(tsrc.indexOf('    _drawTrack(tr, X, W) {'), tsrc.indexOf('    _laneKey(tr, cats, row) {'));
    const svgSrc = tsrc.slice(tsrc.indexOf('    toSVG({'));
    const zoneCall = /this\._sqZones\(sq1 \|\| this\._squares\(p, X, nL\), reserved\[p\._row\]\.slice\(0, nL === 1 \? 1 : 2\), nL === 1 \? noDot\[p\._row\] : null\)/;
    if (!zoneCall.test(drawSrc)) bad('화면의 사건 배치가 모든 줄에서 네모 자리를 비켜 가지 않음 (_sqZones)');
    if (!/this\._sqZones\(this\._squares\(p, X, nL, W\), reserved\[p\._row\]\.slice\(0, nL === 1 \? 1 : 2\), nL === 1 \? noDot\[p\._row\] : null\)/.test(svgSrc) || !/const ctx = \{ bandBounds: bounds, expanded: new Set\(\), reserved, noDot \}/.test(svgSrc)) bad('그림 내보내기의 사건 배치가 네모 자리를 비켜 가지 않음');
    if (!/for \(const z of plan\.zones\) for \(const k of z\.lines\)/.test(drawSrc) || !/for \(const z of plan\.zones\) for \(const zk of z\.lines\)/.test(svgSrc)) bad('내림줄 · 오름줄의 자리(zones)를 사건 글자가 비켜 가지 않음');
    if (!/kn \? textWidth\(String\(kn\), size \* 0\.82\) \+ 18 : 0/.test(tsrc)) bad('접힌 하위 사건 수 알약이 이름 폭에 들지 않음 — 뒤의 연도가 네모에 걸침');
    if (!/body \+= this\._marksSVG\(tr, plan, X, W, GW, top, \{ PAPER, edge \}\)/.test(svgSrc) || !/this\._backSVG\(plan, holes,/.test(svgSrc)) bad('그림 내보내기에 건국 · 멸망 네모 · 승계선 · 다리 · 소속선이 없음');
    if (!/const plan = \(tr\._plan = this\._linkPlan\(tr, X, W\)\);/.test(drawSrc)) bad('화면이 사건을 놓기 전에 승계선의 자리(_linkPlan)를 정하지 않음');
    if (!/\.tl-link\.is-hot, \.tl-link\.is-selected, \.tl-link:hover \{ opacity: 1; \}/.test(csrc) || /\.tl-link[^{]*\{[^}]*stroke-width: 2\.4/.test(csrc) || /\.tl-part:hover \{[^}]*stroke-width/.test(csrc)) bad('올리거나 고를 때 승계선 · 소속선이 굵어짐 (색만 짙게)');
    if (!/\.tl-marks \.tl-link:not\(\.is-hot, \.is-selected, :hover\) \{ opacity: \.9; \}/.test(csrc) || !/\.tl-seg \{ fill: none; stroke: var\(--edge\); stroke-linecap: butt; \}/.test(csrc)) bad('띠 위 층의 다리 · 관문이 테두리색 .9가 아님');
    if (!/@media \(prefers-color-scheme: dark\) \{\s*\.tl-door\.is-seam \{ fill: color-mix\(in srgb, color-mix\(in srgb, var\(--da\) var\(--ka\), var\(--paper\)\) 50%, color-mix\(in srgb, var\(--db\) var\(--kb\), var\(--paper\)\)\); \}/.test(csrc)) bad('어두운 화면에서 이음매 문이 두 띠 바탕의 중간색이 아님');
    if (!/\.tl-band \.tl-lanesep \{ position: absolute; left: 14px; right: 14px;/.test(csrc)) bad('분류 글줄 구분선이 비켜 앉은 네모에 닿음 (여백 14px)');
    const succRow = HT.succRowHTML ? HT.succRowHTML({}) : '';
    const ph = [...succRow.matchAll(/placeholder="([^"]*)"/g)].map(m => m[1]).join(' · ');
    if (!succRow || ph !== '이어받은 정권 · 메모 (선택)' || !/class="s-from"[^>]*aria-label="이어받은 정권"/.test(succRow) || !/class="s-note"[^>]*aria-label="메모"/.test(succRow)) bad(`메이커 승계 줄의 칸 이름이 소속 줄처럼 짧은 칸 이름(흐린 글자 — 예시 값 없음) + aria-label이 아님: ${ph}`);
    if (!/^\.tl-marks \.tl-link\.is-top \{ pointer-events: none; \}/m.test(csrc)) bad('띠 위 조각(관문 · 다리)이 누름을 가로챔 — 띠 안을 지나는 획 위를 누르면 고름이 풀림');
    if (!/fill="\$\{fog \? `url\(#hs-h-\$\{fogId\}\)` : '#000'\}"/.test(svgSrc) || !/id="hs-h-legendary"/.test(tsrc) || !/id="hs-h-semi"/.test(tsrc)) bad('그림 내보내기가 전설 · 반전설 띠 뒤의 선을 통째로 가림 (화면은 안개만큼 비침)');
    if (!/const fogId = hs === 'refuted' \? 'legendary' : hs;/.test(svgSrc)) bad('그림 내보내기의 부정된 띠가 전설과 같은 안개(회색)가 아님 (묶음 5 · 5번)');
    if (!/\.legend li > span:last-child, \.legend \.lg-note \{ word-break: keep-all;/.test(src('css/viewer.css'))) bad('범례 글이 낱말 중간에서 꺾임 (keep-all)');
    if (!/^\.succ-list small \{[^}]*white-space: nowrap;/m.test(src('css/viewer.css'))) bad('상세 창 승계 목록의 연도 칸이 줄바꿈됨');
    if (!/HT\.Timeline\.seamSample\(type\)/.test(src('js/viewer.js'))) bad('범례에 맞닿은 승계(다리) 견본이 없음');
  }
}

/* ㉟ 조감(2026-09-20 감독 결정 — 건의 1 'A안(띠 14px · 띠 안 이름 + 사건 점 · 개수 알약)을 기본으로 · B · C는 설정에서 · 축소하면 조감(기본 끔)'):
   노드에서 js/timeline.js의 공개 값 묶음과 배치(_layoutTrack) · 띠 안 이름(_birdName) · 점과 알약(_placeRow) · 승계선(_linkPlan)을 가짜 this로 돌려 봅니다.
   ① 값 묶음: 모양 셋(a · b 14px · c 8px, 이름 · 점 여부) · 문(승계선이 테두리를 지나는 자리)이 곧은 테두리 안(문 높이 ≤ 띠 − 모서리 × 2) · 내림줄의 문이 모서리 밖 ·
      줄 사이 6px 이상(소속선이 그어지는 틈) · 탭 · 바탕 문화 단 0 · 접힌 줄에 가는 막대 세 단이 듦 · 대범위 머리에 이름표(11px)가 듦 · 자동 조감의 문턱 = 사건 이름이 모두 꺼지는 넓이(2,600년)
   ② 배치(기본팩 + 견본 sample-lantern, 11트랙): 기본팩 트랙의 세 밀도(넉넉 · 자동 · 빽빽) 줄 높이 · 위 틈 · 트랙 높이가 고치기 전과 같음(해시) · 조감 세 모양의 모든 줄이 띠 하나 높이(접힌 줄은 14) · 줄 사이는 6 · 12(민족 경계)
      · 전체 높이가 빽빽하게의 1/3.5 이하
   ③ 띠 안 이름: 띠 시작(미정이면 제 시작)에서 6px · 들 폭은 띠 전체(화면에 잘리지 않음) · 이름 → 첫 글자 → 없음 · 문턱 두 개(더 긴 모양은 8px 여유가 더 있어야 · 지금 모양은 딱 드는 동안 그대로)
   ④ 점 · 알약: 조감 — 이름 자리의 점은 옮기지 않고 숨김 · 짧은 끝(3px)과 테두리를 비킬 폭이 없는 좁은 띠의 점은 숨김 · 알약은 제 띠 안쪽 5px 안 · 바탕 문화 같은 그려지지 않는 띠의 점은 숨김,
      보통 밀도(덤 — 목업이 찾은 흠) — 제 크기의 알약 · 점이 들지 않는 좁은 띠는 조감 크기의 작은 알약 · 점(.is-sm)으로, 그것도 안 들 때만 숨김(띠 밖으로 나가지 않게) · 묶음은 한 띠 안에서만(자리 선이 이웃 띠로 넘어가지 않게)
   ⑤ 승계선(조감 — 네모 없음): 곧바로 이어지면 두 짧은 끝 사이의 다리(맞닿으면 한 문 · 문 높이 a 4.4 · c 3 · 띠 가운데 높이) · 다른 줄로 맞닿으면 멸망 네모 자리(끝에서 7px)의 내림줄
   ⑥ 세로 이름 줄이기: 괄호 · '족'을 떼고 한 낱말 고유 이름은 첫 글자까지('흉노족' → '흉노' → '흉'), 여러 낱말은 첫 낱말까지만('초기 유력 이민족' → '초기', 뜻 없는 '초' 아님)
   ⑦ 글로 읽어: 두 화면의 밀도 목록 넷째 '조감' · 조감 모양(머리 '조감' 한 번) · 축소하면 조감 · 조감 단추(선 아이콘) · V 키 · 설정 저장(ui.birdShape · birdAuto · birdFrom) · 조감 CSS(눈금은 띠 뒤 · 점 5px · 알약 10px · 띠 안 이름) ·
      그림 내보내기의 조감 · 밀도가 바뀌면 한 시계로 흐름(_squash — 움직임 줄이기면 없음) · 움직임 원칙 · README · 용어집
   ⑧ 검토에서 고친 것 — 움직임 줄이기의 확대도 정착 · 조감 왕복은 보던 줄로 · 잔상은 옛 모습 그대로 새 띠 위에서 · 띠 안 이름은 화면 안에 다 들 때만 · 줄 이름 폭은 글자 사이까지 (아래 ⑧) */
{
  const bad = msg => out.problems.push(`조감: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  try {
    if (!HT.Timeline) vm.runInThisContext(src('js/timeline.js'), { filename: 'js/timeline.js' });
  } catch (e) {
    bad(`js/timeline.js를 노드에서 읽지 못함 — ${e.message}`);
  }
  const TL = HT.Timeline || {};
  if (!TL.BIRD || !TL.G_BIRD) bad('Timeline에 조감 값 묶음(BIRD · G_BIRD)이 없음');
  else {
    const { BIRD, G_BIRD, BIRD_AUTO, BIRD_NAME, STUB, chainRows } = TL;
    /* ① 값 묶음 */
    if (BIRD.a.h !== 21 || BIRD.b.h !== 21 || BIRD.c.h !== 8) bad(`띠 높이가 a 21 · b 21 · c 8이 아님 (${BIRD.a.h} · ${BIRD.b.h} · ${BIRD.c.h})`);
    if (!BIRD.a.name || !BIRD.a.dots || !BIRD.b.name || BIRD.b.dots || BIRD.c.name || BIRD.c.dots) bad('모양이 a 이름 + 점 · b 이름만 · c 띠 · 선만이 아님');
    for (const [k, b] of Object.entries(BIRD)) {
      if (b.door > b.h - 2 * b.radius + 1e-9) bad(`모양 ${k}: 문(${b.door})이 곧은 테두리(${b.h} − 모서리 ${b.radius} × 2) 밖으로 나감`);
      if (TL.G.bw + 2 + TL.G.sq / 2 + 0.5 - b.door / 2 < b.radius - 1e-9) bad(`모양 ${k}: 내림줄의 문이 띠 모서리에 걸림`);
    }
    if (G_BIRD.gap < 6 || G_BIRD.memberGap < 6) bad('줄 사이가 6px보다 좁음 — 이웃 줄 사이의 소속선이 사라짐(틈 5.5px 미만)');
    if (G_BIRD.tab !== 0 || G_BIRD.hem !== 0) bad('조감에 책갈피 탭 · 바탕 문화 단 자리가 남음');
    if (2 * G_BIRD.miniPitch + G_BIRD.mini > G_BIRD.foldedGroup) bad('접힌 줄(14px)에 가는 막대 세 단이 들지 않음');
    if (G_BIRD.scopeHead < 11.5) bad('대범위 머리에 이름표(높이 11)가 들지 않음');
    if (BIRD_AUTO !== 2600 || !/this\._past\('imp3', 2600 \/ span, 1\)/.test(src('js/timeline.js'))) bad('자동 조감의 문턱이 사건 이름이 모두 꺼지는 넓이(2,600년)와 다름');
    if (STUB !== 3 || BIRD_NAME.inset !== 6) bad('짧은 끝(3px) · 띠 안 이름 자리(띠 시작 6px)가 바뀜');
    /* ② 배치 — 가짜 this로 _layoutTrack (setData가 트랙에 정권 · 사건을 나누는 것과 같게) */
    const lay = (density, shape = null) => {
      const t = Object.assign(Object.create(TL.prototype), { folded: new Set(), foldedPeoples: new Set(), foldedEras: new Set(), expandedHosts: new Set(), scopesOn: {}, show: Object.assign({}, HT.SHOW_DEFAULTS), density, view: { start: -2500, end: 2100 }, _lod: new Map(), leaderMode: 'auto', birdShape: shape || 'a', birdAuto: false, _bird: shape ? BIRD[shape] : null });
      t._proxies = TL.depProxies(model.periods); // 실제 화면과 같은 상국 이름표 자리까지 계산
      t._setScopes(model.scopes || []);
      t._cats = new Map((model.categories && model.categories.length ? model.categories : HT.DEFAULT_CATEGORIES).map((c, i) => [c.id, { name: c.name, color: c.color, i }]));
      t._dynUids = new Set(model.periods.filter(p => p.polityKind === 'dynasty').map(p => p.uid));
      const map = new Map();
      const tracks = model.tracks.map(x => {
        const tr = Object.assign({}, x, { periods: [], events: [], figures: [] });
        map.set(x.id, tr);
        return tr;
      });
      for (const p of model.periods) if (p.polityKind !== 'dynasty' && map.has(p.track)) map.get(p.track).periods.push(p);
      for (const e of model.events) {
        const places = e.placements && e.placements.length ? e.placements : [{ track: e.track, polityUid: e.polityUid }];
        places.forEach((place, i) => map.has(place.track) && map.get(place.track).events.push(Object.assign({}, e, { _place: place, _sec: i > 0, _pi: i })));
      }
      for (const tr of tracks) t._layoutTrack(tr);
      return tracks;
    };
    try {
      const sig = trs => trs.map(tr => [tr.id, tr.rows, tr.height, tr.baseRowHs.join(','), tr.baseRowGap.join(',')].join('|')).join('\n');
      // 기본팩 트랙만의 배치 지문 — 견본이 바뀌어도 그대로여야 함(2026-10-14 옛 견본 27개를 지우고 sample-lantern 하나로 바꿀 때, 옛 견본을 넣은 채로 잰 기본팩 트랙만의 값과 같음을 확인).
      // 옛 지문(옛 견본 트랙 가운데 뒤에 더한 것을 정규식으로 뺀 꼴): 61ea0fe081 · 그 전 12815106fe · c64db47f24 · 12px 판 5fc1639d64 · 6120c09f9e · 7542e41c97 — 형식1 자료 지문 cbc4381cf1과 별개다.
      // 통합 최소3px: 자료·줄 배정은 그대로이고 G의 칸 높이·단 사이 틈·탭·이름단과 dep 표시 높이만 변경했다. 2026-10-14 매달린 속국 이름표 한 줄 23 → 13(건의 8의 나 · 안 B).
      const baseIds = new Set(HT.getBuiltinPacks().map(r => r.id));
      const baseTracks = new Set(packs.filter(p => baseIds.has(p.id)).flatMap(p => (p.tracks || []).map(t => t.id)));
      const three = hash([-1, 0, 1].map(d => hash(sig(lay(d).filter(tr => baseTracks.has(tr.id))))).join());
      if (three !== 'c50f5614ed') bad(`기본팩 트랙의 세 밀도(넉넉 · 자동 · 빽빽) 줄 배치가 최소3px 기준과 다름 (해시 ${three} ≠ c50f5614ed) — 줄 높이 · 위 틈 · 트랙 높이`);
      /* 모든 트랙(기본팩 + 견본 sample-lantern)을 넣은 기준값: 세 밀도 + 조감 a · b · c (옛 견본 27개 때의 값 2b8daddbef · 그 전 2ac4fa977f)
         견본 2.0.0(트랙 7 — 기본팩 4와 합쳐 11트랙)으로 바꾸며 ed7ed88123 — 같은 코드에 견본 1.0.0을 넣으면 옛 값 055d37e4a6 그대로임을 확인(바뀐 것은 견본뿐) */
      const every = hash([-1, 0, 1].map(d => hash(sig(lay(d)))).concat(['a', 'b', 'c'].map(sh => hash(sig(lay(2, sh))))).join());
      // 조감 a/b도 이름 글줄 둘레3px를 위해 높이21, 글 없는 c는8 그대로.
      if (every !== 'ed7ed88123') bad(`모든 트랙을 넣은 줄 배치(세 밀도 + 조감 a · b · c)가 최소3px 기준과 다름 (해시 ${every} ≠ ed7ed88123)`);
      const dense = lay(1).reduce((s, tr) => s + tr.height, 0);
      for (const sh of ['a', 'b', 'c']) {
        const trs = lay(2, sh);
        const off = [];
        for (const tr of trs)
          tr.baseRowHs.forEach((h, r) => {
            if (h !== (tr.foldedRows.has(r) ? G_BIRD.foldedGroup : BIRD[sh].h)) off.push(`${tr.id}#${r} 높이 ${h}`);
            const gp = tr.baseRowGap[r];
            if (r > 0 && ![G_BIRD.gap, G_BIRD.memberGap, G_BIRD.gap + G_BIRD.groupGap].includes(gp) && !(tr.scopeBranches || []).length) off.push(`${tr.id}#${r} 위 틈 ${gp}`); // 대범위가 있는 트랙은 머리 · 발 여백이 더해짐
          });
        if (off.length) bad(`조감 ${sh}: 줄이 띠 하나 높이 · 6px 틈이 아님 — ${off.slice(0, 3).join(' · ')}`);
        const tot = trs.reduce((s, tr) => s + tr.height, 0);
        if (tot * 3.5 > dense) bad(`조감 ${sh}: 전체 높이(${tot})가 빽빽하게(${dense})의 1/3.5보다 큼`);
      }
    } catch (e) {
      bad(`가짜 this로 배치하다 멈춤 — ${e.message}`);
    }
    /* ③ 띠 안 이름 (노드의 글자 폭 = 한 자 7px — 스텁) */
    try {
      const fake = Object.assign(Object.create(TL.prototype), { _bird: BIRD.a });
      const X = y => y;
      const band = (w, extra = {}) => Object.assign({ uid: 'n', name: '가나다', start: 100, endY: 100 + w }, extra);
      const need = 21;
      const nm = (w, prev, extra) => fake._birdName(band(w, extra), X, prev ? new Map([['n', prev]]) : null, null);
      if (nm(need + 12).mode !== 'full' || nm(need + 11.9).mode !== 'short' || nm(6.9 + 12 - 0.1).mode !== '') bad('띠 안 이름이 들 폭(띠 − 양옆 6px)에 따라 이름 → 첫 글자 → 없음이 아님');
      if (nm(need + 12 + 7.9, 'short').mode !== 'short' || nm(need + 12 + 8, 'short').mode !== 'full') bad('띠 안 이름의 문턱이 두 개가 아님 (더 긴 모양은 8px 여유가 더 있어야)');
      if (nm(need + 12, 'full').mode !== 'full' || nm(need + 11.9, 'full').mode !== 'short') bad('띠 안 이름이 딱 드는 동안 그대로 · 모자라면 곧바로 줄지 않음');
      if (nm(200).l !== 106 || nm(200, null, { startUnknown: true, startRange: [60, 100] }).l !== 106) bad('띠 안 이름이 띠 시작(미정이면 제 시작)에서 6px에 고정되지 않음');
    } catch (e) {
      bad(`띠 안 이름을 재다 멈춤 — ${e.message}`);
    }
    /* ④ 점 · 알약 (가짜 줄 하나 — 띠 A 100~400 · 좁은 띠 N 500~516 · 이웃한 띠 B 400~700) */
    try {
      const fake = Object.assign(Object.create(TL.prototype), { view: { start: 0, end: 1000 }, selected: null, highlight: null, lens: '', _bird: null });
      const tr = { id: 't', geos: null, geo: { lines: 1, font: 11.5, lineH: 21, textTop: 0 }, rowCats: null };
      const ev = (uid, x, pol) => ({ uid, title: uid, start: x, endY: x, importance: 2, _place: { polityUid: pol }, placements: [] });
      const run = (bird, list, bounds, zones = []) =>
        fake._placeRow.call(Object.assign(fake, { _bird: bird }), list, y => y, 1000, tr, { bandBounds: new Map(Object.entries(bounds)), expanded: new Set(), reserved: [[[]]], noDot: [[]], minImp: 99, bird: bird ? { zones: [zones], common: -1 } : null }, 0);
      const shown = placed => placed.filter(it => !it.hidden).map(it => it.e.uid);
      let r = run(BIRD.a, [ev('in-name', 120, 'A'), ev('free', 200, 'A'), ev('narrow', 508, 'N'), ev('under', 250, 'U')], { A: [100, 400], N: [500, 516] }, [[103, 140]]);
      if (shown(r).join() !== 'free') bad(`조감: 이름 자리 · 좁은 띠 · 그려지지 않는 띠의 점이 숨지 않음 (보인 점 ${shown(r).join()})`);
      r = run(BIRD.a, [ev('c1', 300, 'A'), ev('c2', 305, 'A'), ev('c3', 396, 'A'), ev('c4', 398, 'A')], { A: [100, 400] });
      const pill = (r.clusters || [])[0];
      if (!pill || r.clusters.some(c => c.x - c.w / 2 < 100 + 5 - 1e-9 || c.x + c.w / 2 > 400 - 5 + 1e-9)) bad('조감: 알약이 제 띠 안쪽 5px 안에 들지 않음');
    } catch (e) {
      bad(`점 · 알약을 놓다 멈춤 — ${e.message}`);
    }
    /* ⑤ 승계선 (가짜 트랙 — 줄 높이는 모양의 띠 높이, 줄 사이 6) */
    try {
      const plan = (shape, list, rowOf) => {
        for (const p of list) p._seamL = p._seamR = null;
        chainRows(list.slice());
        const h = BIRD[shape].h;
        const n = Math.max(...list.map(rowOf)) + 1;
        const rowPeriods = Array.from({ length: n }, () => []);
        for (const p of list) rowPeriods[(p._row = rowOf(p))].push(p);
        const tr = { id: 't', periods: list, rows: n, rowTop: Array.from({ length: n }, (_, i) => 4 + i * (h + 6)), rowHs: Array(n).fill(h), rowGap: Array(n).fill(6), geo: { lines: 1, textTop: 0, lineH: h }, geos: null, hiddenRows: new Set(), foldedRows: new Set(), commonRow: -1, scopeBranches: [], rowPeriods, eventsByRow: [], _bnmZ: [] };
        return { tr, pl: TL.prototype._linkPlan.call(Object.assign(Object.create(TL.prototype), { show: { succession: 'all', partOf: false }, W: 3000, _bird: BIRD[shape] }), tr, y => y * 2, 3000) };
      };
      const Pp = (name, start, endY, pre = []) => ({ uid: name, name, start, endY, track: 't', color: '#bba395', predecessors: pre.map(([from, type]) => ({ from, type })), successors: [] });
      for (const sh of ['a', 'c']) {
        const q = Pp('앞', 100, 300);
        const p = Pp('뒤', 300, 500, [[q, 'direct']]);
        const { tr, pl } = plan(sh, [q, p], () => 0);
        const mid = tr.rowTop[0] + BIRD[sh].h / 2;
        const doors = pl.top.filter(t => t.door);
        const segs = pl.top.filter(t => t.line).flatMap(t => t.line.segs);
        if (doors.length !== 1 || !doors[0].door.seam || Math.abs(doors[0].door.h - BIRD[sh].door) > 1e-6 || doors[0].door.y < tr.rowTop[0] + BIRD[sh].radius - 1e-6 || doors[0].door.y + doors[0].door.h > tr.rowTop[0] + BIRD[sh].h - BIRD[sh].radius + 1e-6) bad(`조감 ${sh}: 맞닿은 승계에 곧은 테두리 안의 문 하나가 없음`);
        if (!segs.length || segs.some(s => s.y1 !== mid || Math.min(s.x1, s.x2) < 600 - STUB - 1e-6 || Math.max(s.x1, s.x2) > 600 + STUB + 1e-6)) bad(`조감 ${sh}: 다리가 두 짧은 끝(띠 끝 ± 3px) 사이 · 띠 가운데 높이가 아님`);
        if (pl.back.some(b => b.k === 'link')) bad(`조감 ${sh}: 곧바로 이어지는 승계에 띠 뒤 선이 남음`);
      }
      {
        const q = Pp('위', 100, 300);
        const p = Pp('아래', 300, 500, [[q, 'direct']]);
        const { tr, pl } = plan('a', [q, p], x => (x === q ? 0 : 1));
        const link = pl.back.find(b => b.k === 'link');
        const vx = link && link.pts[0][0];
        if (!link || Math.abs(vx - (600 - 7)) > 1e-6 || link.pts[link.pts.length - 1][0] !== 600 + STUB) bad(`조감: 다른 줄로 맞닿은 승계가 멸망 네모 자리(끝에서 7px)의 내림줄 └ · 후대의 짧은 끝이 아님 (${link ? JSON.stringify(link.pts) : '선 없음'})`);
        const vdoor = pl.top.find(t => t.door && t.row === 0);
        if (!vdoor || vdoor.door.x + vdoor.door.w > 600 - BIRD.a.radius + 1e-6) bad('조감: 내림줄의 문이 띠 모서리에 걸림');
        if (tr.rowTop[1] - (tr.rowTop[0] + tr.rowHs[0]) !== 6) bad('가짜 트랙의 줄 사이가 6이 아님');
      }
    } catch (e) {
      bad(`조감 승계선을 짓다 멈춤 — ${e.message}`);
    }
  }
  /* ④의 보통 밀도 몫 · ⑥ (조감 값 묶음이 없어도 따로 봄 — 덤으로 고친 흠이 되살아나면 잡음) */
  if (TL.prototype && TL.prototype._placeRow)
    try {
      const fake = Object.assign(Object.create(TL.prototype), { view: { start: 0, end: 1000 }, selected: null, highlight: null, lens: '', _bird: null });
      const tr = { id: 't', geos: null, geo: { lines: 1, font: 11.5, lineH: 21, textTop: 0 }, rowCats: null };
      const ev = (uid, x, pol) => ({ uid, title: uid, start: x, endY: x, importance: 2, _place: { polityUid: pol }, placements: [] });
      const run = (list, bounds) => fake._placeRow.call(fake, list, y => y, 1000, tr, { bandBounds: new Map(Object.entries(bounds)), expanded: new Set(), reserved: [[[]]], noDot: [[]], minImp: 99, bird: null }, 0);
      const shown = placed => placed.filter(it => !it.hidden).map(it => it.e.uid);
      let r = run([ev('n1', 505, 'N'), ev('n2', 510, 'N')], { N: [500, 516] });
      if (shown(r).length || (r.clusters || []).length) bad('보통 밀도: 작은 알약도 들지 않는 좁은 띠에 알약 · 점이 남음 (띠 밖으로 나감)');
      /* 제 크기가 안 드는 좁은 띠는 숨기지 않고 작게(조감 크기 — .is-sm): 20px 띠의 알약 · 13px 띠의 점 — 10px 띠의 점만 숨김 (검토: 숨기기만 하면 첫 화면의 20세기 사건이 206 → 136개로 사라짐) */
      r = run([ev('s1', 605, 'S'), ev('s2', 612, 'S')], { S: [600, 620] });
      const sp = (r.clusters || [])[0];
      if (!sp || !sp.sm || sp.w !== 14 || sp.x - sp.w / 2 < 600 + 2 - 1e-9 || sp.x + sp.w / 2 > 620 - 2 + 1e-9) bad(`보통 밀도: 제 크기의 알약이 안 드는 20px 띠에 작은 알약(폭 14 · 띠 안쪽 2px 안)이 없음 (${sp ? JSON.stringify({ sm: sp.sm, w: sp.w, x: sp.x }) : '알약 없음'})`);
      r = run([ev('d1', 706, 'D'), ev('d2', 856, 'E')], { D: [700, 713], E: [850, 860] });
      const d1 = r.find(it => it.e.uid === 'd1');
      const d2 = r.find(it => it.e.uid === 'd2');
      if (!d1 || d1.hidden || !d1.sm || Math.abs(d1.x - 706.5) > 1e-6) bad('보통 밀도: 제 크기의 점이 안 드는 13px 띠에 작은 점(띠 가운데)이 없음');
      if (!d2 || !d2.hidden) bad('보통 밀도: 작은 점(5px + 둘레 2px)도 안 드는 10px 띠에 점이 남음');
      r = run([ev('w1', 300, 'A')], { A: [100, 400] });
      if (r[0].sm || r[0].hidden) bad('보통 밀도: 넓은 띠의 점이 작아지거나 숨음');
      r = run([ev('a1', 390, 'A'), ev('b1', 395, 'B')], { A: [100, 400], B: [380, 700] }); // 겹쳐 놓인 띠(기관이 얹힌 띠 등)의 가까운 두 점
      if ((r.clusters || []).some(c => new Set(c.members.map(m => m.e._place.polityUid)).size > 1)) bad('보통 밀도: 이웃한 띠의 점이 한 알약으로 묶임 (자리 선이 이웃 띠로 넘어감)');
    } catch (e) {
      bad(`보통 밀도의 점 · 알약을 놓다 멈춤 — ${e.message}`);
    }
  /* ⑧ 검토에서 고친 것 (2026-09-20):
     ⓐ 움직임 줄이기의 휠 · 키 · 단추 확대와 이동도 정착을 예약 (자동 조감 · 줄 접힘 · 밀려난 것 알림 — 예전에는 +/− · 확대 단추로 자동 조감이 켜지지 않았음)
     ⓑ 조감에 들 때 보던 줄을 기억했다가 나올 때 그 줄을 그때의 자리에 (V · V 한 번의 왕복에 조감 가운데 줄로 가 버리던 것) — 그 사이 손으로 옮기거나 고르면 잊음
     ⓒ 밀도가 바뀔 때의 잔상은 새 띠 껍데기 위(z 1)에서 옛 모습(옛 글자 크기 · 조감 여부) 그대로 옅어짐 — 조감 전용 모양은 살아 있는 줄 · 조감 잔상에만
     ⓓ 조감의 띠 안 이름은 화면(그림) 안에 다 들 때만 · ⓔ 긴 줄 이름의 연도 빼기는 글자 사이까지 잰 화면 폭으로
     ⓕ 비용: 흐르는 내내 화면 밖인 트랙은 줄 안의 움직임 없이 · 흐르는 동안 화면에 드는 트랙은 늘 그림 · 빈 줄 접힘은 다시 짓기 전의 폭으로
     ⓖ 민족 칸 · 딱지의 바뀐 글은 칸이 그 글이 들 높이에 닿을 때부터 떠오름 */
  if (TL.prototype && TL.prototype.zoomAt)
    try {
      const calls = [];
      const z = Object.assign(Object.create(TL.prototype), { W: 1000, view: { start: 0, end: 1000 }, extent: { min: 0, max: 1000 }, _glide: null });
      Object.assign(z, { _beginJump: () => calls.push('jump'), _settleSoon: () => calls.push('settle'), setView: () => calls.push('view'), _glideTo: () => calls.push('glide') });
      const mm = globalThis.matchMedia;
      globalThis.matchMedia = () => ({ matches: true });
      z.zoomAt(1.6, 500, { smooth: true });
      z.panBy(10, { smooth: true });
      const reduced = calls.splice(0).join();
      globalThis.matchMedia = mm;
      z.zoomAt(1.6, 500, { smooth: true });
      if (reduced !== 'jump,view,settle,jump,view,settle') bad(`ⓐ 움직임 줄이기의 확대 · 이동이 정착을 예약하지 않음 (+/− · 확대 단추로 자동 조감이 켜지지 않음 — ${reduced})`);
      if (calls.join() !== 'glide') bad('ⓐ 움직임을 켠 확대가 미끄러짐(_glideTo)이 아님');
    } catch (e) {
      bad(`ⓐ 확대 · 이동을 부르다 멈춤 — ${e.message}`);
    }
  if (TL.prototype && TL.prototype._snapshot)
    try {
      /* 가짜 트랙 둘(줄 넷씩, 줄 높이 100) · 화면 높이 400 — 조감에 들 때의 가운데 줄을 기억하고, 스크롤이 바뀐(조감 배치) 뒤 나올 때 그 줄 · 그 자리를 붙잡는지 */
      const mk = (id, top) => ({ id, rows: 4, folded: false, hiddenRows: new Set(), el: { isConnected: true, offsetTop: top, getBoundingClientRect: () => ({ height: 400 }) }, laneEls: [0, 100, 200, 300].map(o => ({ offsetTop: o })) });
      const t = Object.assign(Object.create(TL.prototype), { tracks: [mk('a', 0), mk('b', 400)], bodyEl: { scrollTop: 300, clientHeight: 400 }, anchorUid: null, _pressHold: null });
      t._snapshot(false, 'in'); // 스크롤 300 · 가운데(500)는 b#1 (화면 200px)
      const back = t._birdBack;
      if (!back || back.id !== 'b' || back.row !== 1 || back.off !== 200) bad(`ⓑ 조감에 들 때 보던 줄(가운데 b#1 · 화면 200px)을 기억하지 않음 (${JSON.stringify(back)})`);
      t.bodyEl.scrollTop = 0; // 조감에서 내용이 줄어 스크롤이 깎임 — 이제 가운데는 a#2
      const out1 = t._snapshot(false, 'out').hold;
      if (!out1 || out1.id !== 'b' || out1.row !== 1 || out1.off !== 200) bad(`ⓑ 조감에서 나올 때 조감 가운데 줄로 감 — 들기 전에 보던 줄 · 자리가 아님 (${JSON.stringify(out1)})`);
      if (t._birdBack) bad('ⓑ 조감에서 나온 뒤에도 기억이 남음');
      t.bodyEl.scrollTop = 300;
      t._snapshot(false, 'in');
      t.bodyEl.scrollTop = 0;
      t._applyStates = t.render = () => {};
      t.setSelected('x');
      const out2 = t._snapshot(false, 'out').hold;
      if (!out2 || out2.id !== 'a' || out2.row !== 2) bad(`ⓑ 조감에서 무엇을 고른 뒤에도 들기 전의 줄로 돌아감 (${JSON.stringify(out2)})`);
    } catch (e) {
      bad(`ⓑ 조감 왕복의 붙잡을 줄을 재다 멈춤 — ${e.message}`);
    }
  if (TL.prototype && TL.prototype._squashAway)
    try {
      /* ⓕ 비용: 흐르는 내내 화면(높이 800 · 위아래 여유) 밖인 트랙만 줄 안의 움직임을 건너뜀 — 트랙 위 · 높이 · 스크롤이 진행값에 곧게(스크롤은 p*에서 꺾여) 가므로 출발 · 꺾임 · 도착으로 셈 */
      const t = Object.create(TL.prototype);
      const tr = { height: 100 };
      const plan = (top, s0, sF, pe = 1) => ({ tops: new Map([[tr, top]]), s0, sF, pe, H: 800 });
      const away = (o, pl) => t._squashAway(o, tr, pl);
      if (!away({ top: 5000, h: 400 }, plan(4000, 0, 0))) bad('ⓕ 흐르는 내내 화면 아래 먼 트랙의 줄 안 움직임을 건너뛰지 않음 (밀도를 바꾼 첫 그림이 두세 배 늦어짐)');
      if (away({ top: 3000, h: 400 }, plan(100, 2000, 400))) bad('ⓕ 흐르는 동안 화면을 지나가는 트랙(출발에는 아래 · 도착에는 위 — 화면 밖)을 건너뜀');
      if (away({ top: 2000, h: 100 }, plan(4000, 0, 2800, 0.5))) bad('ⓕ 스크롤이 꺾이는 자리(p*)에서만 화면에 드는 트랙을 건너뜀');
      if (away({ top: 100, h: 400 }, plan(100, 0, 0)) || t._squashAway({ top: 9000, h: 1 }, tr, null)) bad('ⓕ 화면 안의 트랙(또는 셈할 길이 없을 때)을 건너뜀');
    } catch (e) {
      bad(`ⓕ 화면 밖 트랙을 가리다 멈춤 — ${e.message}`);
    }
  {
    const tsrc = src('js/timeline.js');
    const csrc = src('css/common.css');
    if (!/const flowing = !!tr\._squash && HT\.motion\.now\(\) < tr\._squash\.g\.until;\s*const off = tr\.el && !flowing && /.test(tsrc)) bad('ⓕ 흐르는 동안 화면에 드는 트랙을 다 흐른 뒤의 자리로 가려 그리지 않음 (맨 아래에서 조감으로 가면 새 줄 안의 것 없이 잔상만)');
    if (!/const W = Math\.max\(60, \(before\.bw != null \? before\.bw : this\.bodyEl\.clientWidth\) - this\.gutter\);/.test(tsrc)) bad('ⓕ 빈 줄 접힘(_foldAhead)이 조감 표시를 바꾼 옛 DOM 전체를 다시 재게 함 (다시 짓기 전의 폭을 쓰지 않음)');
    if (!/^\.tl-sqz \{ position: absolute; left: -4px; right: -4px; bottom: 0; z-index: 1;/m.test(csrc)) bad('ⓒ 잔상이 새 띠 껍데기 뒤에 있어 옛 칸 · 점이 옅어지지 못하고 가려짐 (.tl-sqz z-index 1)');
    if (/^\.tl\.is-bird(-c)? \.tl-(ev|clu|row|lanekey)\b/m.test(csrc)) bad('ⓒ 조감 전용 모양이 잔상(.tl-sqz · .tl-sqz-rows)에도 걸리는 꼴로 남음 — 살아 있는 줄과 조감 잔상(.was-bird)에만');
    if (!/wrap\.className = `\$\{S\.bird \? `tl-sqz was-bird was-bird-\$\{S\.bird\}` : 'tl-sqz'\}\$\{this\._bird \? ' to-bird' : ''\}`;/.test(tsrc) || !/for \(const \[k, v\] of o\.vars\) wrap\.style\.setProperty\(k, v\);/.test(tsrc) || !/if \(sq\.bird\) old\.classList\.add\('was-bird', `was-bird-\$\{sq\.bird\}`\);[^\n]*\n\s*for \(const \[k, v\] of o\.vars\) old\.style\.setProperty\(k, v\);/.test(tsrc)) bad('ⓒ 잔상이 옛 글자 크기 · 조감 여부를 지니지 않음 (새 트랙의 값을 물려받아 옛 이름이 커지며 넘침)');
    if (!/if \(nm\.l >= -0\.5 && nm\.l \+ nm\.w <= W \+ 0\.5\) rows\[p\._row\] \+= `<span class="tl-bnm/.test(tsrc) || !/if \(nm\.text && nm\.l >= -0\.5 && nm\.l \+ nm\.w <= W \+ 0\.5\) \{/.test(tsrc)) bad('ⓓ 조감의 띠 안 이름이 화면 가장자리에 반쯤 잘린 채 그려짐 (화면 · 그림 안에 다 들 때만)');
    if (!/const nameW = \(t, s\) => textWidth\(t, s, wt\) \+ ls \* \[\.\.\.t\]\.length;/.test(tsrc)) bad('ⓔ 긴 줄 이름의 폭을 글자 사이 없이 재어 들어가는 연도도 뺌');
    if (!/if \(text\) this\._squashText\(el, old, h, g\);/.test(tsrc) || !/this\._squashRun\(g, span, \[\{ opacity: 0, offset: 0 \}\], M\.T\.in, M\.C\.ease, 'backwards', f > 0 \? M\.T\.move \* bezierTimeAt\(M\.C\.spring, f\) : 0\);/.test(tsrc)) bad('ⓖ 조감에서 나올 때 민족 칸 · 딱지의 바뀐 글이 아직 자라는 칸에 잘린 채 보임 (칸이 그 글이 들 높이에 닿을 때부터 떠오르게)');
  }
  {
    /* ⑥ 세로 이름 줄이기 */
    const sn = n => (TL.shortNames ? TL.shortNames(n) : []).join('/');
    if (sn('초기 유력 이민족') !== '초기 유력 이민족/초기' || sn('여진-만주족') !== '여진-만주족/여진' || sn('한(삼한)') !== '한(삼한)/한' || sn('참족') !== '참족/참' || sn('한민족') !== '한민족/한' || sn('흉노족') !== '흉노족/흉노/흉' || sn('몽골계') !== '몽골계/몽')
      bad(`세로 이름 줄이기가 뜻이 남는 차례(괄호 · '족' 떼기 · 첫 낱말)가 아님: ${['초기 유력 이민족', '여진-만주족', '한(삼한)', '참족'].map(sn).join(' | ')}`);
  }
  /* ⑦ 글로 읽어 */
  {
    const tsrc = src('js/timeline.js');
    const csrc = src('css/common.css');
    const vsrc = src('js/viewer.js');
    for (const f of ['index.html', 'dlc-maker.html']) {
      const h = src(f);
      if (!/<select id="densitySelect"[^>]*>[\s\S]*?<option value="2">조감<\/option>[\s\S]*?<\/select>/.test(h)) bad(`${f}: 밀도 목록에 넷째 '조감'이 없음`);
      if (!/<span class="filter-sub">조감<\/span>\s*<select id="birdShapeSelect"[\s\S]*?value="a" selected>이름 \+ 점<\/option>[\s\S]*?value="b">이름만<\/option>[\s\S]*?value="c">띠 · 선만<\/option>/.test(h)) bad(`${f}: 조감 모양 목록(머리 '조감' 한 번 + a 이름 + 점 · b 이름만 · c 띠 · 선만 — 건의 8 이름만 쓰기)이 없음`);
      if (!/<input id="birdAutoToggle" type="checkbox"> 축소하면 조감/.test(h)) bad(`${f}: '축소하면 조감' 체크가 없음 (기본 끔)`);
      if (!/class="zoom-controls"[\s\S]*?id="birdBtn" data-zoom="bird"[^>]*aria-pressed="false"[^>]*data-icon="bird"[^>]*><\/button>/.test(h)) bad(`${f}: 확대 단추 옆 조감 단추(선 아이콘 bird)가 없음`);
      for (const [z, ic] of [['in', 'plus'], ['out', 'minus'], ['fit', 'expand']]) if (!new RegExp(`class="zoom-controls"[\\s\\S]*?data-zoom="${z}"[^>]*data-icon="${ic}"[^>]*></button>`).test(h)) bad(`${f}: 확대 묶음의 ${z} 단추가 선 아이콘(${ic})이 아님 (건의 8)`);
    }
    if (!/bird: 'V'/.test(vsrc) || !/v: \(\) => toggleBird\(\)/.test(vsrc)) bad('V 키가 조감 ↔ 직전 밀도가 아님');
    if (!/birdShape: 'a', birdAuto: false, birdFrom: 0/.test(vsrc)) bad('설정 기본값에 조감 모양(a) · 자동 조감(끔) · 직전 밀도가 없음');
    if (!/if \(v === 2 && state\.ui\.density !== 2\) state\.ui\.birdFrom = state\.ui\.density \|\| 0;/.test(vsrc)) bad('조감에 들어갈 때 직전 밀도를 적어 두지 않음 (↕ · V로 돌아갈 곳)');
    if (!/\.tl\.is-bird \.tl-grid \{ z-index: auto; \}/.test(csrc)) bad('조감에서 세기 눈금이 띠 위를 지남 (띠 안 이름을 가로지름)');
    if (!/^:is\(\.tl\.is-bird \.tl-lane > \.tl-ev, \.tl-sqz\.was-bird > \.tl-sqz-in > \.tl-ev, \.tl-ev\.is-sm\) \.d \{ width: 5px; height: 5px; box-shadow: 0 0 0 2px/m.test(csrc) || !/^:is\(\.tl\.is-bird \.tl-lane > \.tl-clu, \.tl-sqz\.was-bird > \.tl-sqz-in > \.tl-clu, \.tl-clu\.is-sm\) b \{ height: 10px;/m.test(csrc)) bad('조감의 점(5px + 둘레 2px) · 알약(높이 10)이 띠 안쪽 12px에 맞지 않음 (보통 밀도의 작은 점 · 알약 .is-sm도 같은 크기)');
    if (!/^\.tl-bnm \{ position: absolute; top: 0; height: 100%;/m.test(csrc)) bad('띠 안 이름(.tl-bnm)의 모양이 없음');
    const svgSrc = tsrc.slice(tsrc.indexOf('    toSVG({'));
    if (!/const bird = this\._bird;/.test(svgSrc) || !/this\._birdName\(p, X\)/.test(svgSrc) || !/Object\.assign\(ctx, \{ minImp: 99, bird: \{ zones: bzones, common: tr\.commonRow \} \}\)/.test(svgSrc)) bad('그림 내보내기가 조감을 화면과 같게 그리지 않음 (띠 안 이름 · 점 · 이름 자리)');
    if (!/squash: squash && !reduceMotion\(\) \? this\._squashFirst\(\) : null/.test(tsrc) || !/this\._applyFlip\(before, clock\);\n\s*this\._squash\(before, clock\);/.test(tsrc)) bad('밀도가 바뀔 때 한 시계로 흐르지 않음 (_squash — 움직임 줄이기면 없음)');
    if (!/_squashRun\(g, el, kf, duration, easing, fill = 'backwards', delay = 0\) \{[\s\S]{0,200}a\.startTime = g\.tl;/.test(tsrc)) bad('흐름의 움직임들이 한 시각에 못 박히지 않음 (_squashRun)');
    if (!/if \(this\._birdSettle\(\)\) return true;/.test(tsrc)) bad('자동 조감이 정착 때 한 번이 아님 (_birdSettle)');
    const mp = src('docs/움직임-원칙.md');
    if (!/\| 밀도 바꾸기 \(조감 포함\) \|/.test(mp)) bad('움직임 원칙 문서의 움직임 목록에 밀도 바꾸기(조감)가 없음');
    if (!/조감/.test(src('README.md')) || !/\*\*조감\*\*/.test(src('docs/용어집.md'))) bad('README · 용어집에 조감이 없음');
  }
}

/* ㊱ 칸 조명 범위의 상호배타(2026-09-19 감독 결정 — 건의 7 '따로 지도자 칸에서 정하는 게 아니라면 상호배타적으로'): 칸의 경계(HT.cellBounds · HT.chainBounds)
   ① 경우별: 연도만(끝 해 = 다음 시작 해 → 경계 해는 뒤 칸의 것) · 날짜(한쪽만 날짜면 날짜가 경계 — 앞 칸의 끝 날짜 · 뒤 칸의 시작 날짜) · 포함식(1450 → 1451은 그대로) ·
      일부러 겹침(뒤 칸이 앞 칸의 끝 해보다 먼저 시작 · 시작이 같은 여러 해짜리 둘 — 적힌 그대로) · 같은 해 셋(늘이지 않음 — 폭 0, 그해는 이어 가는 칸의 것) ·
      이어 가는 칸 없는 한 해짜리 둘(서로를 뒤 칸으로 삼지 않음 — 마지막 칸이 그해를 가짐) · 맞닿은 날짜(24일에 끝 · 25일에 시작 — 24일까지 앞 칸, 틈 없음) ·
      임시 도읍(정도가 다시 이어지는 자리까지) · 진행 중 · 내각 · 연호 · 시기(체계마다 따로) · 지위, 배도는 넣지 않음
   ② 경계 해의 연도만 적은 사건은 한쪽 목록에만(HT.spanHit — 날짜로 나뉜 해면 그해 한가운데), 활동 기록은 인물 조명과 같은 [시작, 끝)(HT.spanMeets)
   ③ 모델 안에서만 쓰는 값(p.cellBounds — 열거되지 않음)이 팩 · 내보내기 · 정권 사본에 섞이지 않음
   ④ 기본팩: 모든 칸 무리에서 경계가 겹치지 않고, 맞닿은 이웃(끝 해 = 다음 시작 해)은 앞 칸의 끝 = 뒤 칸의 시작 = 적힌 시작(연표의 칸 그림과 같은 자리)
   ⑤ 화면 코드가 경계를 쓰는지(칸 창 · 시기 창 · 지위 창 · 조명 · 이 시기로 · 이 시기의 인물 · 같은 시기의 지도자 · 같은 해 보기 · 줄 이름표) · 경계 안내는 메이커에서만 */
{
  const bad = msg => out.problems.push(`칸의 경계: ${msg}`);
  const near = (a, b) => Math.abs(a - b) < 1e-9;
  const T = s => HT.cal.parse(s).t;
  const fns = ['cellBounds', 'chainBounds', 'cellChains', 'cellBound', 'spanHit', 'spanMeets'].filter(f => typeof HT[f] !== 'function');
  if (fns.length) bad(`칸의 경계 함수가 없음: ${fns.map(f => `HT.${f}`).join(' · ')}`);
  const pk = fns.length ? {} : HT.normalizePack({
    format: 'history-timeline-dlc',
    formatVersion: 1,
    id: 'smoke-bounds',
    name: '검사',
    tracks: [{ id: 't', name: '검사 땅' }],
    periods: [
      {
        id: 'p', track: 't', name: '가 나라', start: 300, end: 500,
        leaders: [['갑', 300, 350], ['을', 350, 360], ['병', 360, '370-03-01'], ['정', 370, 380], ['무', 380, 390], ['기', 391, 400], ['경', 400, 430], ['신', 420, 440], ['임', 440, 440], ['계', 440, 440], ['자', 440]],
        cabinets: [['ㄱ', 300, 350], { name: 'ㄴ', start: '350-02-25', end: 360 }, ['ㄷ', 360, 380], ['ㄹ', 360, 390]],
        eras: [['아', 300, 350], ['야', 350]],
        capitals: [['개', 300], ['강', 400, 420, '임시'], ['바', 460], ['곁', 430, null, '배도']],
        phases: [{ scheme: '하나', spans: [['앞', 300, 400], ['뒤', 401]] }, { scheme: '둘', spans: [['첫', 300, 400], ['둘째', 400]] }],
        ranks: [['공', 300, 350], ['왕', 350]],
      },
      { id: 'q', track: 't', name: '나 나라', start: 2000, ongoing: true, leaders: [['하', 2000, 2025], ['호', 2025]] },
    ],
    events: [
      { id: 'e1', track: 't', polity: 'p', title: '경계 해 사건', start: 350 },
      { id: 'e2', track: 't', polity: 'p', title: '경계 해 1월 사건', start: '370-01-10' },
      { id: 'e3', track: 't', polity: 'p', title: '경계 해 여름 사건', start: '370-07-10' },
      { id: 'e4', track: 't', polity: 'p', title: '두 칸에 걸친 사건', start: 345, end: 355 },
      { id: 'e5', track: 't', polity: 'p', title: '같은 해 셋의 사건', start: 440 },
      { id: 'e6', track: 't', polity: 'p', title: '날짜로 나뉜 해의 연도만 사건', start: 370 },
    ],
  });
  if (fns.length);
  else if (!pk.pack) bad(`검사 팩을 읽지 못함 — ${pk.errors.map(e => e.msg).join(' / ')}`);
  else {
    const m = HT.buildModel([pk.pack], null);
    const p = m.byUid.get('smoke-bounds/p');
    const q = m.byUid.get('smoke-bounds/q');
    const sp = (x, kind, name) => {
      const list = HT.cellsOf(x, kind);
      const i = list.findIndex(c => (c.name || c.city) === name);
      return i < 0 ? null : Object.assign(HT.cellSpan(list[i], x, `${kind}:${i}`), { ref: `${kind}:${i}`, c: list[i] });
    };
    const want = (x, kind, name, lo, hi, why) => {
      const s = sp(x, kind, name);
      if (!s) return bad(`${kind} "${name}"을(를) 찾지 못함`);
      if (!near(s.lo, lo) || !near(s.hi, hi)) bad(`${why}: ${kind} "${name}"의 구간이 [${lo}, ${hi})가 아님 ([${s.lo}, ${s.hi}))`);
    };
    const yearEnd = y => HT.endBound(y, null);
    want(p, 'leader', '갑', 300, 350, '연도만(끝 350 → 다음 시작 350) — 경계 해는 뒤 칸의 것');
    want(p, 'leader', '을', 350, 360, '연도만 — 뒤 칸의 시작 해부터');
    want(p, 'leader', '병', 360, T('370-03-01'), '끝 날짜 — 그 날짜(0시)까지');
    want(p, 'leader', '정', T('370-03-01'), 380, '한쪽만 날짜(앞 칸의 끝 날짜 + 뒤 칸의 시작 해) — 날짜가 경계');
    want(p, 'leader', '무', 380, yearEnd(390), '포함식(끝 390 → 다음 391) — 그해 끝까지 그대로');
    want(p, 'leader', '기', 391, 400, '포함식의 뒤 칸 — 적힌 시작부터');
    want(p, 'leader', '경', 400, yearEnd(430), '일부러 겹침(뒤 칸이 앞 칸의 끝 해보다 먼저 시작) — 적힌 그대로');
    want(p, 'leader', '신', 420, 440, '같은 해 셋의 앞 칸 — 그 해에 시작하는 첫 칸까지');
    want(p, 'leader', '임', 440, 440, '같은 해 셋(440–440) — 늘이지 않음(폭 0)');
    want(p, 'leader', '계', 440, 440, '같은 해 셋(440–440) — 늘이지 않음(폭 0)');
    want(p, 'leader', '자', 440, yearEnd(500), '같은 해 셋의 마지막 — 그해부터 정권 끝 해 끝까지');
    want(p, 'cabinet', 'ㄱ', 300, T('350-02-25'), '한쪽만 날짜(앞 칸의 끝 해 + 뒤 칸의 시작 날짜) — 날짜가 경계');
    want(p, 'cabinet', 'ㄴ', T('350-02-25'), 360, '뒤 칸의 시작 날짜부터');
    want(p, 'cabinet', 'ㄷ', 360, yearEnd(380), '시작이 같은 여러 해짜리 둘(일부러 겹침) — 적힌 그대로');
    want(p, 'cabinet', 'ㄹ', 360, yearEnd(390), '시작이 같은 여러 해짜리 둘(일부러 겹침) — 적힌 그대로');
    want(p, 'era', '아', 300, 350, '연호 — 경계 해는 뒤 칸의 것');
    want(p, 'capital', '강', 400, 420, '임시 도읍 — 정도가 다시 이어지는 자리(끝 해의 1월 1일)까지');
    want(p, 'capital', '개', 300, 460, '정도(끝을 비움 — 다음 정도의 시작까지, 임시 도읍 구멍은 덮은 채 그대로)');
    want(p, 'capital', '곁', 430, yearEnd(500), '배도는 칸의 경계에 넣지 않음');
    want(p, 'phase', '앞', 300, yearEnd(400), '시기는 체계마다 따로 — 다른 체계의 400년 시작이 이 체계의 끝을 자르지 않음');
    want(p, 'phase', '첫', 300, 400, '시기(같은 체계 안) — 경계 해는 뒤 시기의 것');
    want(p, 'rank', '공', 300, 350, '지위 — 경계 해는 뒤 지위의 것');
    want(q, 'leader', '하', 2000, 2025, '진행 중인 정권 — 경계 해는 뒤 칸의 것');
    want(q, 'leader', '호', 2025, q.endY, '진행 중인 정권의 마지막 칸 — 오늘까지');
    /* ② 사건 · 활동 기록 */
    const who = e => HT.cellsOf(p, 'leader').filter((c, i) => {
      const s = HT.cellSpan(c, p, `leader:${i}`);
      return HT.spanHit(e, s.lo, s.hi);
    }).map(c => c.name).join(',');
    const ev = id => m.byUid.get(`smoke-bounds/${id}`);
    if (who(ev('e1')) !== '을') bad(`경계 해(350)의 연도만 적은 사건이 뒤 칸 한 곳에만 들지 않음 (${who(ev('e1'))})`);
    if (who(ev('e2')) !== '병') bad(`날짜로 나뉜 해(370-03-01)의 1월 사건이 앞 칸에만 들지 않음 (${who(ev('e2'))})`);
    if (who(ev('e3')) !== '정') bad(`날짜로 나뉜 해의 7월 사건이 뒤 칸에만 들지 않음 (${who(ev('e3'))})`);
    if (who(ev('e4')) !== '갑,을') bad(`두 칸에 걸친 사건(345–355)이 두 칸 모두에 들지 않음 (${who(ev('e4'))})`);
    if (who(ev('e5')) !== '자') bad(`같은 해 셋의 해(440) 사건이 이어 가는 칸 한 곳에만 들지 않음 (${who(ev('e5'))})`);
    if (who(ev('e6')) !== '정') bad(`날짜(370-03-01)로 나뉜 해의 연도만 적은 사건이 그해 한가운데가 속한 뒤 칸 한 곳에만 들지 않음 (${who(ev('e6'))})`);
    const mid = T('370-03-01');
    if (HT.spanHit({ start: 370, endY: 370 }, 360, mid) || !HT.spanHit({ start: 370, endY: 370 }, mid, 380) || !HT.spanHit({ start: 370, endY: 370 }, 300, T('370-09-01'))) bad('HT.spanHit이 연도만 적은 한 해짜리 사건을 그해 한가운데 한 점으로 보지 않음');
    const g = sp(p, 'leader', '갑');
    const e2 = sp(p, 'leader', '을');
    if (!HT.spanMeets(320, 350, g.lo, g.hi) || HT.spanMeets(320, 350, e2.lo, e2.hi)) bad('350년에 끝난 활동 기록([320, 350))이 350년에 시작한 칸과도 겹치거나 앞 칸과 겹치지 않음 — 인물 조명과 같은 [시작, 끝)이 아님');
    if (!HT.spanMeets(350, 350, e2.lo, e2.hi) || HT.spanMeets(350, 350, g.lo, g.hi)) bad('시작과 끝이 같은 활동 기록(350)이 그 해의 칸 한 곳에만 들지 않음');
    if (!HT.spanMeets(440, 440, 430, 441) || HT.spanMeets(440, 440, 300, 440)) bad('HT.spanMeets의 폭 0 처리가 한 점으로 보지 않음');
    /* 경계 이웃: prev · next */
    const b = HT.cellBound(p, sp(p, 'leader', '을').ref);
    if (!b || b.prev.join() !== sp(p, 'leader', '갑').ref || !b.next.includes(sp(p, 'leader', '병').ref)) bad(`경계의 앞뒤 이웃(prev · next)이 맞지 않음 (${b && b.prev} / ${b && b.next})`);
    /* ③ 모델 안에서만 */
    if (!(p.cellBounds instanceof Map) || Object.keys(p).includes('cellBounds') || /cellBounds/.test(JSON.stringify(p)) || /cellBounds/.test(JSON.stringify(HT.packToJSON(pk.pack)))) bad('칸의 경계(p.cellBounds)가 열거되지 않는 모델 전용 값이 아님 — 팩 · 내보내기 · 사본에 섞일 수 있음');
    if (Object.assign({}, p).cellBounds) bad('정권을 복사한 사본에 칸의 경계가 따라감 (옛 목록으로 만든 경계가 새 칸에 쓰일 수 있음)');
    /* 순수 함수(이설 · 메아리가 함께 씀) */
    const cb = HT.chainBounds([{ start: 10, end: 20, hi: yearEnd(20) }, { start: 20, end: 30, hi: yearEnd(30) }]);
    if (!(near(cb[0].hi, 20) && near(cb[1].lo, 20) && near(cb[1].hi, yearEnd(30)))) bad(`HT.chainBounds(칸 무리 하나)가 경계 해를 뒤 칸에 주지 않음 (${JSON.stringify(cb)})`);
    const S = (start, end, startAt = null, endAt = null) => ({ start, startAt, end, endAt, hi: HT.endBound(end, endAt) });
    /* 정권 마지막 해에 한 해짜리 칸 둘(이어 가는 칸 없음): 서로를 뒤 칸으로 삼아 둘 다 폭 0이 되면 그해가 어느 칸에도 들지 않음 — 한쪽으로만 이어 마지막 칸이 그해를 가짐 */
    const two = HT.chainBounds([S(1930, 1945), S(1945, 1945), S(1945, 1945)]);
    if (!(near(two[0].hi, 1945) && near(two[1].lo, 1945) && near(two[1].hi, 1945) && near(two[2].lo, 1945) && near(two[2].hi, yearEnd(1945)))) bad(`마지막 해의 한 해짜리 칸 둘 — 그해를 마지막 칸이 갖지 않음 (${JSON.stringify(two.map(b => [b.lo, b.hi]))})`);
    if (two[2].next.length || two[1].prev.includes(2)) bad('같은 해에 시작해 그해에 끝난 칸 둘이 서로를 뒤 칸으로 삼음 (시작이 이른 쪽 → 늦은 쪽, 같으면 목록 차례로 한쪽만)');
    const withNext = HT.chainBounds([S(1930, 1945), S(1945, 1945), S(1945, 1945), S(1945, 1950)]);
    if (!(near(withNext[2].hi, 1945) && near(withNext[3].lo, 1945))) bad('이어 가는 칸이 있는 같은 해 셋이 달라짐 (그해는 이어 가는 칸의 것)');
    /* 맞닿은 날짜: 끝 "1988-02-24"(그날 0시) · 시작 "1988-02-25" — 24일이 어느 칸에도 들지 않던 틈 없이, 끝난 날까지 앞 칸 */
    const d24 = T('1988-02-24');
    const d25 = T('1988-02-25');
    const tb = HT.chainBounds([S(1980, d24, null, '1988-02-24'), S(d25, 1993, '1988-02-25')]);
    if (!(near(tb[0].hi, d25) && near(tb[1].lo, d25))) bad(`맞닿은 날짜(24일에 끝 · 25일에 시작)의 경계가 뒤 칸의 시작이 아님 — 24일이 어느 칸에도 들지 않음 (${JSON.stringify(tb.map(b => [b.lo, b.hi]))})`);
    if (!HT.spanHit({ start: d24, startAt: '1988-02-24', endY: d24 }, tb[0].lo, tb[0].hi) || HT.spanHit({ start: d24, startAt: '1988-02-24', endY: d24 }, tb[1].lo, tb[1].hi)) bad('맞닿은 날짜의 끝난 날(24일) 사건이 앞 칸 한 곳에만 들지 않음');
    const tm = HT.chainBounds([S(1980, T('1988-02'), null, '1988-02'), S(T('1988-03'), 1993, '1988-03')]);
    if (!near(tm[0].hi, T('1988-03'))) bad('맞닿은 달(2월에 끝 · 3월에 시작)의 2월이 어느 칸에도 들지 않음');
    const ty = HT.chainBounds([S(1440, 1450), S(1451, 1460)]);
    if (!(near(ty[0].hi, yearEnd(1450)) && !ty[0].next.length)) bad('포함식 연도(1450 → 1451)가 맞닿음으로 이어짐 — 연도만 적은 끝은 그대로 그해 끝까지');
  }
  /* ④ 기본팩 */
  if (model && !fns.length) {
    let touch = 0;
    for (const p of model.periods)
      for (const g of HT.cellChains(p)) {
        const B = g.map(x => x.ref && HT.cellBound(p, x.ref));
        for (let i = 0; i < g.length; i++)
          for (let j = 0; j < g.length; j++) {
            if (i === j || !B[i] || !B[j]) continue;
            const a = g[i].sp;
            const z = g[j].sp;
            const intended = z.start < a.start || (z.start < Math.floor(a.end) && a.end > z.start + 1); // 적힌 값이 한 해 넘게 겹치는 칸(공동 통치 · 섭정 · 대립)
            if (i < j && !intended && B[i].hi > B[i].lo && B[j].hi > B[j].lo && B[i].lo < B[j].hi && B[j].lo < B[i].hi) bad(`기본팩 ${p.name}: ${g[i].ref} "${g[i].c.name}"와(과) ${g[j].ref} "${g[j].c.name}"의 경계가 겹침`);
            if (!a.exact && Number.isInteger(a.end) && a.end === z.start && z.start > a.start && !a.endAt && !z.startAt) {
              touch++;
              if (!(B[i].hi === z.start && B[j].lo === z.start)) bad(`기본팩 ${p.name}: 맞닿은 이웃 ${g[i].ref} → ${g[j].ref}의 경계가 뒤 칸의 적힌 시작(${z.start})이 아님`);
            }
          }
      }
    if (touch < 100) bad(`기본팩에서 맞닿은 이웃 칸을 거의 찾지 못함 (${touch}쌍 — 칸 무리 HT.cellChains가 비었는지)`);
  }
  /* ⑤ 화면 코드 */
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const fnOf = (src, head) => {
    const i = src.indexOf(head);
    return i < 0 ? '' : src.slice(i, src.indexOf('\n  }', i));
  };
  /* 칸 창의 사건은 연표의 강조와 같은 계산(HT.echoEvents — ㊲)으로, 그 안에서 칸의 경계와 짝인 HT.spanHit */
  if (!/spotCalc\(\[\{ uid: x\.uid, start: lo, end: hi \}\], false\)\.own/.test(fnOf(vsrc, '  function cellEvents(')) || !/HT\.spanHit\(e, s\.start, s\.end\)/.test(readFileSync(join(root, 'js/core.js'), 'utf8'))) bad('칸 창의 사건(cellEvents)이 칸의 경계와 짝인 HT.spanHit을 쓰지 않음');
  if (!/HT\.spanMeets\(r\.service\.start, r\.service\.endY, lo, hi\)/.test(fnOf(vsrc, '  function cellFiguresHTML('))) bad('이 시기의 인물이 활동 기록의 [시작, 끝)과 칸의 경계로 겹침을 보지 않음');
  const cellHtml = fnOf(vsrc, '  function cellDetailHTML(');
  if (!/cellSpanOf\(x, c, `\$\{kind\}:\$\{i\}`\)/.test(cellHtml) || !/cellEvents\(x, lo, hi\)/.test(cellHtml) || !/cellFiguresHTML\(x, lo, hi\)/.test(cellHtml)) bad('칸 창이 칸의 경계(lo · hi)로 사건 · 인물을 고르지 않음');
  if (!/cellEvents\(x, lo, hi\)/.test(fnOf(vsrc, '  function phaseDetailHTML('))) bad('시기 창이 칸의 경계로 사건을 고르지 않음');
  if (!/const \{ lo, hi \} = cellSpanOf\(x, c, opts\.cell\);[\s\S]{0,200}start: lo, end: hi/.test(vsrc)) bad('칸 조명(setSpotlight)이 칸의 경계 [lo, hi)를 칠하지 않음');
  if (!/const \{ lo: s, hi: e2 \} = cellSpanOf\(x, ref\.c, state\.cell\)/.test(vsrc)) bad("'이 시기로'가 칸의 경계로 맞추지 않음");
  if (!/HT\.spanMeets\(s\.start, s\.endY, lo, hi\)/.test(fnOf(vsrc, '  function figureDetailHTML('))) bad('인물 창의 같은 시기의 지도자가 칸의 경계와 활동 기록의 [시작, 끝)으로 겹침을 보지 않음');
  if (!/cellIn\(p, c, `phase:\$\{c\.ci\}`, a, b\)/.test(vsrc) || !/cellIn\(p, c, `rank:\$\{c\.i\}`, a, b\)/.test(vsrc)) bad('같은 해 보기의 시기 · 지위가 칸의 경계를 쓰지 않음 (바뀐 해에 두 시기가 모두 나옴)');
  if (!/HT\.cellSpan\(c, pick, `\$\{kind\}:\$\{i\}`\)/.test(tsrc) || !/atCenter2\(pick\.leaders \|\| \[\], 'leader'/.test(tsrc) || !/atCenter2\(pick\.rankSpans \|\| \[\], 'rank'/.test(tsrc)) bad('줄 이름표의 그때 지도자 · 지위가 칸의 경계를 쓰지 않음 (바뀐 해의 1월 1일에 앞 사람이 잡힘)');
  const note = fnOf(vsrc, '  function boundNoteHTML(');
  if (!note || !/^\s*function boundNoteHTML\(x, c, ref\) \{\s*if \(!maker\) return '';/.test(note)) bad('칸 창의 경계 안내가 메이커에서만 뜨지 않음 (연표는 보기 전용 — 날짜를 적으라는 말을 하지 않게)');
  for (const f of ['cellDetailHTML', 'phaseDetailHTML', 'rankDetailHTML']) if (!/boundNoteHTML\(x, c, `/.test(fnOf(vsrc, `  function ${f}(`))) bad(`${f}에 칸의 경계 안내가 없음`);
}

/* ㊲ 같은 시기 타국(2026-09-19 감독 결정 — 건의 3 '같은 시기를 다른 나라에도 적용시키면 그 시기 다른 국가의 사건도 뜨게' · 8번 C안 '같은 짙기로' · 조명 끝 모양
   '그 범위가 본 띠에서 라운드면 라운드, 중간이라서 네모로 표현되면 그냥 네모'): HT.echoSpans · HT.echoBandSpans · HT.echoEvents(창과 연표가 같은 답)
   ① 순수 함수: 메아리 기간 합치기 · 띠마다 제 조명을 빼고 띠가 있던 구간으로 자르기
   ② HT.echoEvents 경우별: 제 것(조명의 정권 · 숨은 소속 — member) · 메아리(다른 띠 · 띠가 없던 해는 아님 · 같은 띠라도 제 조명 밖) · 함께 겪은 사건(제 자리가 하나라도 있으면 제 목록,
      아니면 주 자리의 묶음에 '함께') · 정권이 없는 사건(트랙 묶음) · 하위 사건(부모 줄의 포함 n — 연표의 점 열쇠는 그대로) · 접힌 띠(folded) · 경계 해(한가운데 한 점) ·
      메아리를 끄면 제 것만 · 묶음 차례(연표 위에서 아래로)
   ③ 연표 코드: 칠은 HT.echoSpans · HT.echoBandSpans로(창과 같은 계산), 메아리 사건은 흐리지 않되 이름 우선순위 · 부모 펼침에는 넣지 않음, 알약 표시, 흐린 띠의 조명 구간(has-lit)
   ④ CSS: 칠은 네모 + 띠 모양의 틀(.tl-spots — 반지름 inherit · overflow hidden), 메아리 칠 = 제 조명(한 단계 옅게 하던 보정 없음), 띠의 불투명도 규칙마다 --bt가 같은 값, 사건 밝기 전환
   ③' 흐리지 않는 구간을 다른 칸으로 옮길 때(lit-sw) 옛 구간 · 새 구간을 따로(--lo · --ln — 가림 판을 갈아 끼우는 프레임에 튀지 않게) · 되돌아가기(lit-back) ·
      왕조 · 인물 창의 강조는 사건 배치에 쓰지 않음(layout: false — 스위치로 이름표 · 부모 펼침이 바뀌지 않게) · 같은 자리 사건 더미(has-more)에도 묶음 표시
   ⑤ 화면 코드 · 글: 강조는 나중에 건 쪽(창이 열린 뒤에 검색하면 검색 강조, 검색 결과를 눌러 연 창은 창의 강조 — 창을 닫거나 검색어를 비우면 되살림) · 필터를 바꿔도 창의 강조가 남음 · 왕조 · 인물 창에도 스위치와 묶음 · 설명 글에서 '한 단계 옅게'가 없어짐 */
{
  const bad = msg => out.problems.push(`같은 시기 타국: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const fns = ['echoSpans', 'echoBandSpans', 'echoEvents'].filter(f => typeof HT[f] !== 'function');
  if (fns.length) bad(`함수가 없음: ${fns.map(f => `HT.${f}`).join(' · ')}`);
  else {
    /* ① */
    const J = x => JSON.stringify(x);
    if (J(HT.echoSpans([{ uid: 'a', start: 300, end: 350 }, { uid: 'b', start: 340, end: 400 }, { uid: 'c', start: 400, end: 420 }, { uid: 'd', start: 500, end: 510 }])) !== J([[300, 420], [500, 510]])) bad(`메아리 기간을 합치지 못함 (${J(HT.echoSpans([{ uid: 'a', start: 300, end: 350 }, { uid: 'b', start: 340, end: 400 }]))})`);
    if (J(HT.echoBandSpans([[300, 420]], [[330, 360]], 320, 400)) !== J([[320, 330], [360, 400]])) bad(`띠의 메아리 구간이 제 조명을 빼고 띠가 있던 구간으로 잘리지 않음 (${J(HT.echoBandSpans([[300, 420]], [[330, 360]], 320, 400))})`);
    if (HT.echoBandSpans([[300, 420]], [[300, 420]]).length) bad('제 조명과 같은 구간의 메아리가 남음(두 번 칠함)');
    /* ② 가상의 띠 표 — 연표의 echoBands 모양: A 트랙에 가(띠) · 가의 숨은 소속 나(가의 띠 안에) · 마(접힌 줄), B 트랙에 다(350~) · 라(300~ · 제 조명도 있음) */
    const bandTab = {
      가: { band: '가', start: 300, end: 500, order: 0.2, drawn: true, folded: false, hidden: false, name: '가', track: 'A' },
      나: { band: '가', start: 300, end: 500, order: 0.2, drawn: true, folded: false, hidden: true, name: '가', track: 'A' },
      사: { band: '가', start: 300, end: 500, order: 0.2, drawn: true, folded: false, hidden: true, name: '가', track: 'A' }, // 가의 띠 안에 숨은 또 하나의 소속(조명이 이 소속에 걸림 — 그 소속을 섬긴 인물의 창처럼)
      마: { band: '마', start: 300, end: 500, order: 0.6, drawn: false, folded: true, hidden: false, name: '마', track: 'A' },
      다: { band: '다', start: 350, end: 500, order: 1.5, drawn: true, folded: false, hidden: false, name: '다', track: 'B' },
      라: { band: '라', start: 300, end: 500, order: 1.3, drawn: true, folded: false, hidden: false, name: '라', track: 'B' },
    };
    const bandOf = u => bandTab[u] || null;
    const ev = (uid, polity, start, end, more = {}) => Object.assign({ kind: 'event', uid, title: uid, track: bandTab[polity] ? bandTab[polity].track : 'B', start, end: end ?? null, endY: end ?? start, importance: 2, placements: [{ track: bandTab[polity] ? bandTab[polity].track : 'B', polityUid: polity, polityName: polity }] }, more);
    const events = [
      ev('own', '가', 330),
      ev('member', '나', 335),
      ev('edge', '가', 360), // 경계 해 — 조명 [320, 360)의 끝 해는 한가운데(360.5)로 봐서 들지 않고, 메아리 기간에도 없음
      ev('gap', '가', 305), // 가 띠의 제 조명 밖 · 다른 조명(라 300~310)의 메아리 — 같은 띠라도 메아리
      ev('echo-da', '다', 380),
      ev('before-da', '다', 320), // 다 띠가 없던 해(350 전) — 메아리 아님
      ev('echo-ra', '라', 390),
      ev('own-ra', '라', 305), // 라의 제 조명(300~310) 안 — 제 것
      ev('shared-own', '다', 340, null, { placements: [{ track: 'B', polityUid: '다', polityName: '다' }, { track: 'A', polityUid: '가', polityName: '가' }] }),
      ev('shared-echo', '다', 385, null, { placements: [{ track: 'B', polityUid: '다', polityName: '다' }, { track: 'B', polityUid: '라', polityName: '라' }] }),
      ev('common', null, 370, null, { track: 'B', placements: [{ track: 'B', polityUid: null }] }),
      ev('parent', '다', 360, 395),
      ev('child', '다', 390, null, { parentUid: 'parent' }),
      ev('folded', '마', 380),
      ev('late', '다', 450),
      ev('hidden-track', null, 380, null, { track: 'B', placements: [{ track: 'B', polityUid: '다', polityName: '다' }, { track: 'Z', polityUid: 'z', polityName: 'z' }].slice(1) }), // 꺼 둔 트랙(Z)의 자리뿐 — 연표에 없으므로 메아리 아님
      ev('host-in-member', '가', 430), // 숨은 소속 사의 조명(420~440)이 칠해진 가 띠의 자리 — 가의 사건은 제 것도 메아리도 아님(그 자리는 제 조명이라 메아리 칠을 빼므로)
    ];
    const spots = [{ uid: '가', start: 320, end: 360 }, { uid: '라', start: 300, end: 310 }, { uid: '가', start: 370, end: 400 }, { uid: '사', start: 420, end: 440 }];
    const r = HT.echoEvents({ events, spots, echo: true, bandOf, trackOrder: t => (t === 'A' ? 0 : 1), trackShown: t => t !== 'Z' });
    const own = r.own.map(o => `${o.e.uid}${o.member ? `(${o.member})` : ''}`).join(',');
    if (own !== 'own-ra,own,member(나),shared-own') bad(`제 것이 다름: ${own}`);
    const rows = r.groups.map(g => `${g.key}${g.folded ? '*' : ''}:${g.rows.map(x => `${x.e.uid}${x.kids ? `+${x.kids}` : ''}${x.with.length ? `[${x.with.join('|')}]` : ''}`).join(',')}`).join(' / ');
    const want = 'b:가:gap / b:마*:folded / b:라:echo-ra / b:다:parent+1,echo-da,shared-echo[라] / t:B:common';
    if (rows !== want) bad(`메아리 묶음이 다름: ${rows} (기대 ${want})`);
    if (!r.echoKeys.has('child:0') || !r.echo.has('child')) bad('묶음에서 부모 줄로 센 하위 사건이 연표의 메아리(점 열쇠)에서 빠짐');
    if (!r.echoKeys.has('shared-echo:0') || !r.echoKeys.has('shared-echo:1')) bad('함께 겪은 사건의 두 자리가 모두 메아리 점이 아님');
    for (const u of ['before-da', 'late', 'own', 'shared-own', 'edge', 'host-in-member', 'hidden-track']) if (r.echo.has(u) || r.ownUids.has(u) !== ['own', 'shared-own'].includes(u)) bad(`메아리 · 제 것이 아니어야(이어야) 할 사건: ${u}`);
    if (r.count !== 7) bad(`줄 수 ${r.count} (기대 7 — 하위 사건은 부모 줄에)`);
    const off = HT.echoEvents({ events, spots, echo: false, bandOf });
    if (off.echo.size || off.groups.length || off.own.length !== r.own.length) bad('메아리를 끄면 제 것만 남아야 함');
  }
  /* ③ 연표 코드 */
  const tsrc = src('js/timeline.js');
  const draw = tsrc.slice(tsrc.indexOf('    _drawTrack(tr, X, W) {'));
  if (!/HT\.echoBandSpans\(this\._echoSpans\(\), own\.map\(s => \[s\.start, s\.end\]\), bandStart\(p\), bandEnd\(p\)\)/.test(draw)) bad('연표의 메아리 칠이 창과 같은 계산(HT.echoBandSpans)을 쓰지 않음');
  if (!/return HT\.echoSpans\(this\.spots\)/.test(tsrc)) bad('연표의 메아리 기간(맨 위 괄호)이 HT.echoSpans가 아님');
  const prio = (tsrc.match(/const prio = e => [^\n]*/) || [''])[0];
  if (!prio || /echo/.test(prio)) bad('사건 이름 우선순위에 메아리가 들어감(켜는 순간 이름이 바뀌고 그림 내보내기도 달라짐)');
  const hitLine = (tsrc.match(/const hit = this\.hiLayout && e\.children[^\n]*/) || [''])[0];
  if (!hitLine || /this\.echo/.test(hitLine)) bad('부모 사건의 저절로 펼침이 배치용 강조(hiLayout)를 보지 않거나 메아리 사건이 부모를 펼침');
  if (!/this\.hiLayout && this\.hiLayout\.has\(e\.uid\)/.test(prio)) bad('사건 이름 우선순위가 배치용 강조(hiLayout)를 보지 않음 — 왕조 · 인물 창의 스위치가 이름표를 바꿈');
  if (!/this\.hiLayout = set && opts\.layout !== false \? set : null;/.test(tsrc)) bad('setHighlight에 layout(배치에 쓰지 않는 강조)이 없음');
  /* ③' 흐리지 않는 구간 옮기기 */
  const litFn = tsrc.slice(tsrc.indexOf('    _litState(uid, track, cols) {'), tsrc.indexOf('    _litFrame() {'));
  if (!/lit-sw\$\{s\.back \? ' lit-back' : ''\}/.test(litFn) || !/from: st\.cols, to: cols/.test(litFn) || !/litSame\(cols, st\.from\)/.test(litFn) || !/if \(st\.shownSw\) \{/.test(litFn)) bad('_litState가 다른 칸으로 옮길 때 옛 구간 · 새 구간을 따로 두지 않음(lit-sw · lit-back · 가라앉은 뒤 한 프레임)');
  if (!/lit\.to \? litSegs\(litPx\(lit\.to\), litPx\(lit\.from\)\)/.test(draw) || !/litMask\(maskSegs, BW, iw, width\)/.test(draw)) bad('옮기는 동안의 가림 판이 옛 구간(--lo) · 새 구간(--ln)으로 나뉘지 않음');
  const apply = tsrc.slice(tsrc.indexOf('    _applyStates() {'), tsrc.indexOf('    /* ---------- 그리기 ---------- */'));
  if (!/is-echo-hit/.test(apply) || !/is-dim', !!hi && !m && !lit/.test(apply) || !/echo-out/.test(apply) || !/querySelectorAll\('\[data-cluster\]'\)/.test(apply)) bad('_applyStates가 메아리 사건(흐리지 않음 · 옅어질 때 echo-out) · 묶음 표시(알약 · 같은 자리 사건 더미 — [data-cluster])를 다루지 않음');
  if (!/'is-echo-hit', 'echo-out', 'is-hit'\]/.test(tsrc)) bad('다시 그려도 메아리 상태가 남도록 KEEP_CLASS에 넣지 않음');
  if (!/<i class="tl-spots">\$\{spotHtml\}<\/i>/.test(draw) || !/has-lit/.test(draw) || !/litSegs\(this\._litCols, null\)/.test(draw)) bad('조명 칠이 띠 모양의 틀(.tl-spots)에 들지 않거나 흐린 띠의 조명 구간(has-lit)이 없음');
  for (const f of ['_cells(list', '_phaseCells(p', '_rankCells(p']) if (!/this\._litCls\(/.test(tsrc.slice(tsrc.indexOf(`    ${f}`), tsrc.indexOf('\n    }\n', tsrc.indexOf(`    ${f}`))))) bad(`${f.split('(')[0]}의 칸이 조명 구간의 밝기(lit-in · lit-part)를 받지 않음`);
  /* ④ CSS */
  const css = src('css/common.css');
  const rule = sel => (css.match(new RegExp(`(^|\\n)${sel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} \\{([^}]*)\\}`)) || [])[2] || '';
  if (!/border-radius: inherit/.test(rule('.tl-spots')) || !/overflow: hidden/.test(rule('.tl-spots')) || !/inset: -1px/.test(rule('.tl-spots'))) bad('조명의 틀(.tl-spots)이 띠의 모서리 모양(반지름 inherit · 넘침 가림 · 테두리만큼 넓힘)을 따르지 않음');
  if (/border-radius: (?!0)/.test(rule('.tl-spot')) || /radius/.test(rule('.tl-spot.at-s')) || /radius/.test(rule('.tl-spot.at-e'))) bad('조명 칠에 제 둥근 모서리가 남음 (띠 중간에서 끊긴 끝은 네모)');
  if (/--echo-bg|--echo-line/.test(css)) bad("메아리 칠에 '한 단계 옅게'(--echo-bg · --echo-line) 보정이 남음 — 제 조명과 같은 짙기");
  if (!/@property --bo /.test(css) || !/@property --la /.test(css) || !/\.tl \.tl-lane \.tl-band\.has-lit \{ opacity: 1; --la: 1;/.test(css)) bad('흐린 띠의 조명 구간(has-lit)의 CSS가 없음');
  {
    const sw = css.indexOf('.tl .tl-lane .tl-band.has-lit.lit-sw {');
    const back = css.indexOf('.tl .tl-lane .tl-band.has-lit.lit-sw.lit-back {');
    const out2 = css.indexOf('.tl .tl-lane .tl-band.has-lit.lit-sw.lit-out {');
    const ok =
      /@property --lo /.test(css) && /@property --ln /.test(css) && /--la: var\(--bt\); --lo: var\(--la\); --ln: var\(--bo\);/.test(rule('.tl-band')) &&
      sw > 0 && /^\.tl \.tl-lane \.tl-band\.has-lit\.lit-sw \{ --lo: var\(--bt\); --ln: 1;[^}]*--lo var\(--t-out\)[^}]*--ln var\(--t-in\)/.test(css.slice(sw)) &&
      back > sw && /^[^{]*\{ --lo: 1; --ln: var\(--bt\);[^}]*--lo var\(--t-in\)[^}]*--ln var\(--t-out\)/.test(css.slice(back)) &&
      out2 > back && /^[^{]*\{ --lo: var\(--bt\); --ln: var\(--bt\);[^}]*--lo var\(--t-out\)[^}]*--ln var\(--t-out\)/.test(css.slice(out2));
    if (!ok) bad('다른 칸으로 옮길 때의 옛 구간 · 새 구간(--lo · --ln — lit-sw · lit-back · 물러남이 뒤에서 이김)의 CSS가 없거나 다름');
  }
  if (!/\.tl\.is-filtered \.tl-ev\.is-dim:not\(\.is-hit\), \.tl\.is-filtered \.tl-band\.is-dim \{ opacity: \.2; \}/.test(css) || !/\.tl-ev\.has-more\.is-hit:not\(:hover, \.is-carded\) \.d \{/.test(css) || !/\.tl\.is-picked\.is-filtered \.tl-ev\.is-dim\.is-hit > :not\(\.d\) \{ opacity: calc\(\.2 \/ \.45\); \}/.test(css)) bad('같은 자리 사건 더미(has-more)의 묶음 표시(겹 고리 짙게 · 점은 흐리지 않고 이름만 .2)가 없음');
  /* 띠의 불투명도를 주는 규칙마다 --bt가 같은 값(가림의 바깥 밝기 = 흐린 띠와 같게) */
  /* 규칙의 대상이 띠 자신인 선택자(괄호 안 · 자식 · ::before는 뺌 · 조명 구간의 규칙은 제 몫) */
  const bandSubject = sel => {
    const t = sel.replace(/\([^()]*\)/g, '').trim().split(/\s+/).pop();
    return /\.tl-band\b/.test(t) && !/::|has-lit|lit-done|lit-out/.test(t);
  };
  let opRules = 0;
  for (const m of css.matchAll(/(^|\n)([^{}\n@]*)\{([^}]*)\}/g)) {
    const op = (m[3].match(/(^|[\s;])opacity: ([\d.]+)/) || [])[2];
    const sels = m[2].replace(/\([^()]*\)/g, '').split(',').filter(bandSubject); // 괄호 안의 쉼표(:not(… , …))로 가르지 않게
    if (op == null || !sels.length) continue;
    opRules++;
    const bt = (m[3].match(/--bt: ([\d.]+)/) || [])[1] || (sels.length === 1 && sels[0].trim() === '.tl.is-filtered .tl-band.is-dim' && (css.match(/\.tl\.is-filtered \.tl-band\.is-dim \{ --bt: ([\d.]+); \}/) || [])[1]);
    if (bt !== op) bad(`띠의 불투명도 규칙에 --bt가 없거나 다름: ${m[2].trim()} (opacity ${op} · --bt ${bt})`);
  }
  if (opRules < 4) bad(`띠의 불투명도 규칙을 찾지 못함 (${opRules}개)`);
  if (!/\.tl\.is-filtered \.tl-band\.is-dim \{ --bt: \.2; \}/.test(css)) bad('흐린 띠(.2)의 --bt가 없음');
  if (!/\.tl\.is-filtered \.tl-ev\.is-echo-hit \{ transition: opacity var\(--t-in\)/.test(css) || !/\.tl\.is-filtered \.tl-ev\.is-dim\.echo-out \{ transition: opacity var\(--t-out\)/.test(css)) bad('메아리 사건의 밝기 바뀜에 --t-in · --t-out 전환이 없음');
  /* ⑤ 화면 코드 · 글 */
  const vsrc = src('js/viewer.js');
  const fn = head => { const i = vsrc.indexOf(head); return i < 0 ? '' : vsrc.slice(i, vsrc.indexOf('\n  }', i)); };
  const runSearch = fn('  function runSearch() {');
  if (/timeline\.setHighlight\(null\)/.test(runSearch.slice(0, runSearch.indexOf('const terms'))) || !/spotHighlight\(\)/.test(runSearch)) bad('검색어를 비우면(필터를 바꿔도) 창의 강조까지 지움');
  if (!/if \(searchOwns\(\)\) return res;/.test(fn('  function spotHighlight(')) || !/const searchOwns = \(\) => !!searchInput\.value\.trim\(\) && \(hiOwner === 'search' \|\| !state\.spotKind\);/.test(vsrc)) bad('창의 강조와 검색 강조 가운데 나중에 건 쪽이 이기지 않음(searchOwns)');
  if (!/addEventListener\('input', \(\) => \{\s*hiOwner = 'search';/.test(vsrc) || !/hiOwner = 'spot';[^\n]*\n\s*leaveDetail\(kind\);/.test(fn('  function openDetail('))) bad("검색어 입력이 강조를 검색으로, 창 열기가 창으로 가져가지 않음 — 검색 결과를 눌러 연 창의 강조가 걸리지 않음");
  if (!/if \(searchOwns\(\)\) timeline\.setHighlight\(hi\.size \? hi : null\);/.test(runSearch)) bad('검색(필터 바꿈 · 입력칸 누름)이 창이 가진 강조를 덮음');
  if (!/layout: k\.always/.test(fn('  function spotHighlight('))) bad('왕조 · 인물 창의 강조가 사건 배치에 쓰임(layout: k.always 없음)');
  if (!/refreshHighlight\(\)/.test(fn('  function leaveDetail(')) || /timeline\.setHighlight\(null\)/.test(fn('  function leaveDetail('))) bad('창을 닫을 때 검색 강조를 되살리지 않음(refreshHighlight)');
  if (!/lit: echo/.test(fn('  function spotHighlight(')) || !/!k\.always && !echo/.test(fn('  function spotHighlight('))) bad('칸 창은 늘 · 왕조 · 인물 창은 메아리가 켜졌을 때만 강조하는 규칙이 없음');
  for (const id of ['cell', 'dynasty', 'figure']) if (!new RegExp(`state\\.spotKind = \\{ id: '${id}'`).test(vsrc)) bad(`${id} 창이 조명의 사건 계산(spotKind)을 두지 않음`);
  if ((vsrc.match(/\$\{echoSlotHTML\(\)\}/g) || []).length !== 5) bad("칸 · 시기 · 지위 · 왕조 · 인물 창에 '같은 시기 타국' 자리가 없음");
  if (!/같은 시기 타국 <small>/.test(fn('  function echoBoxHTML(')) || !/ECHO_MAX = 40/.test(vsrc) || !/ECHO_EACH = 5/.test(vsrc)) bad("'같은 시기 타국' 묶음(40건이 넘으면 나라마다 5건)이 없음");
  if (!/onLayout: \(\) => state\.spotKind && spotHighlight\(\)/.test(vsrc) || !/this\.opts\.onLayout\(\)/.test(tsrc)) bad('접기 · 펼치기로 띠가 바뀌어도 조명의 사건을 다시 세지 않음');
  const texts = ['js/viewer.js', 'index.html', 'dlc-maker.html', 'README.md', 'DLC-형식.md', 'docs/용어집.md'].filter(f => /한 단계 옅게|타국의 띠 안에도 옅게/.test(src(f)));
  if (texts.length) bad(`설명 글에 '한 단계 옅게' · '띠 안에도 옅게'가 남음: ${texts.join(', ')}`);
  for (const f of ['index.html', 'dlc-maker.html']) if (!/id="spotEchoToggle"/.test(src(f)) || !/그 시기 타국의 사건/.test((src(f).match(/<label class="check" title="([^"]*)"><input id="spotEchoToggle"/) || [])[1] || '')) bad(`${f}의 표시 체크 풍선이 새 동작(그 시기 타국의 사건)을 말하지 않음`);
}
/* ㊳ 모든 것에 이설 · 모호한 칸(2026-09-19 감독 결정 — 건의 4 '연호 등 모든 것에 이설을 추가할 수 있게 하고' · '이설이 아니라 자체가 모호하면 띠 같이 흐려지게'):
   ① 칸(지도자 · 내각 · 연호 · 도읍 · 시기 · 지위 · 소속 줄 · 왕조 구간 · 활동 기록) · 시대 구분 · 인물의 alternatives와 칸의 certainty · startRange · endRange를
      읽는 함수가 하나(HT.readUncertain) — 견본 sample-lantern(지도자 · 연호 · 시기 · 소속 줄 · 인물 · 활동 기록 · 시대 구분의 이설, 지도자 · 도읍의 확실성)을 읽고 → 내보내고 → 다시 읽어도 같고, 옛 알림 글도 그대로
   ② 칸 이설은 한쪽만 있어도 됨(빈 쪽은 통설 값 — HT.altSpan) · 날짜 없이 근거만 적은 견해는 어디든 받음 · 항목의 이설은 예전처럼 시작부터(끝만 적으면 뺌) · 다시 읽어도 같은 꼴
   ③ 모델의 칸 사본(도읍 · 시기 · 지위 · 소속 hosts · 왕조 구간 · 인물 services)이 값을 넘겨받음 · 칸 이설이 정권의 이설(수 · 범위)을 바꾸지 않음 · 글만 있는 견해는 범위에 들지 않음
   ④ 폼: 칸 줄(이설 상자 포함) · 이설 줄을 채웠다 다시 읽으면 같은 꼴(출처 · 메모 · 현재까지가 남음 — 예전에는 떨어짐), 항목의 이설은 제 상자만(칸의 이설이 빨려 들지 않음)
   ⑤ 패치: 칸 목록을 손대지 않고 폼을 거치면 패치 0건 · 칸 하나에 이설을 더하면 그 목록만 · 수정 내역은 '이설 · 연대 폭만' · 패치의 이설 날짜 글을 풂
   ⑥ 형식 버전: 칸의 새 열쇠 · 시대 구분의 이설 · 시작 없는 이설이면 2, 기본팩은 그대로 */
{
  const bad = msg => out.problems.push(`모든 것에 이설: ${msg}`);
  const file = 'sample-lantern.json';
  const raw = JSON.parse(readFileSync(join(root, 'samples', file), 'utf8'));
  const r = HT.normalizePack(raw);
  if (!r.pack || r.errors.length || r.warnings.length) bad(`견본 ${file}이 오류 · 경고 없이 읽히지 않음 (${[...r.errors, ...r.warnings].map(w => w.msg).join(' / ')})`);
  const per = id => (r.pack ? r.pack.periods.find(p => p.id === id) : null);
  const P = per('p-lantern'); // 등불 왕국: 지도자 · 연호 · 시기의 이설, 지도자 · 도읍의 확실성
  const PJ = per('p-jeokseok'); // 적석 왕국: 소속 줄의 이설
  const J = x => JSON.stringify(x);
  try {
  if (!P || !PJ || !per('p-empire') || !per('p-coral')) bad('견본의 등불 왕국 · 적석 왕국 · 설원 제국 · 산호 섬나라가 없음');
  else {
    /* ① 칸마다 읽힘 */
    const L = P.leaders;
    const mujin = L.find(c => c.name === '무진왕') || {};
    if (J(mujin.alternatives) !== J([{ label: '411년설', end: 411, source: '윤슬, 『물안개기』', note: '겨울에 죽고 이듬해 봄에야 알렸다고 적음' }]))
      bad(`지도자의 이설(한쪽만 · 출처 · 메모)이 그대로 읽히지 않음: ${J(mujin.alternatives)}`);
    const first = per('p-coral').leaders[0];
    if (L[0].certainty !== 'legend' || first.certainty !== 'estimated' || J(first.startRange) !== '[120,140]') bad('모호한 지도자 칸(확실성 · 시작 폭)이 읽히지 않음');
    if (J(P.eras[3].alternatives) !== J([{ label: '411년설', end: 411, source: '윤슬, 『물안개기』' }]) || J(per('p-empire').eras[3].alternatives) !== J([{ start: 962, label: '늦게 선포했다는 설' }])) bad('연호의 이설이 읽히지 않음');
    if (P.capitals[0].certainty !== 'legend') bad('도읍의 확실성이 읽히지 않음 (HT.normalizeCapital)');
    if (J(P.phases[1].spans[1].alternatives) !== J([{ label: '만화왕이 죽은 해를 경계로 보는 설', end: 340 }])) bad('시기의 이설이 읽히지 않음 (HT.readPhases)');
    const part = Array.isArray(PJ.partOf) ? PJ.partOf[0] : null;
    if (!part || J(part.alternatives) !== J([{ start: 788, label: '정복한 해에 이미 신속했다는 설' }])) bad(`소속 줄의 이설이 읽히지 않음 (HT.readPartOf): ${J(PJ.partOf)}`);
    const fig = r.pack.figures[0];
    if (J(fig.alternatives) !== J([{ label: '윗물골 묘지석의 386년설', birth: 386, source: '윗물골 묘지석' }]) || J(r.pack.figures[4].alternatives) !== J([{ label: '늦은 사망설', death: 1066, source: '적석관 비문' }])) bad(`인물의 이설(생몰)이 읽히지 않음: ${J(fig.alternatives)}`);
    if (!(fig.service[1].alternatives || []).length) bad('활동 기록의 이설이 읽히지 않음');
    if ((r.pack.epochs[0].alternatives || []).length !== 2) bad('시대 구분의 이설(날짜 · 글만)이 읽히지 않음');
    /* 왕복 · 형식 버전 */
    const json = HT.packToJSON(r.pack);
    const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (!back.pack || canon(HT.packToJSON(back.pack)) !== canon(json)) bad('읽기 → 내보내기 → 다시 읽기에서 이설 · 모호함이 달라짐');
    if (json.formatVersion < 2 || !HT.usesCellUncertainty(json)) bad('칸의 이설을 쓴 견본이 칸의 이설을 쓴 것(형식 버전 2 이상)으로 잡히지 않음');
  }
  } catch (e) {
    bad(`① 읽기 — 검사 도중 오류: ${e.message}`);
  }
  try {
  /* ② 읽기 규칙 */
  const warns = [];
  const read = (list, mode) => HT.readAlternatives(list, { mode, warn: m => warns.push(m) });
  if (read([{ end: 5, label: '가' }], 'item').length || !warns.some(w => /시작이 없어 뺐습니다/.test(w))) bad('항목의 이설인데 끝만 적은 것을 받음 (항목은 시작부터 — 사건 · 시대 띠의 이설 그림이 시작을 씀)');
  if (J(read([{ label: '나', note: '다' }], 'item')) !== J([{ label: '나', note: '다' }])) bad('항목의 글만 있는 견해를 받지 않음');
  if (J(read([{ start: 3, end: 3 }], 'item')) !== J([{ start: 3, label: '다른 견해' }])) bad('항목의 이설에서 시작과 같은 끝을 예전처럼 비우지 않음');
  if (J(read([{ start: 3, end: 3 }], 'cell')) !== J([{ start: 3, label: '다른 견해', end: 3 }])) bad('칸의 이설에서 시작과 같은 끝이 사라짐 (비우면 통설의 끝으로 채워져 뜻이 바뀜)');
  warns.length = 0;
  if (read([{ start: 10, end: 5 }, { start: '아무 글' }, {}], 'cell').length || warns.length !== 3) bad(`칸의 잘못된 이설(거꾸로 · 읽을 수 없음 · 빈 것)을 알림 없이 받음: ${J(warns)}`);
  if (read([{ birth: 10, death: 5 }], 'figure').length) bad('인물의 이설에서 사망이 출생보다 앞서는데 받음');
  const once = read([{ start: '기원전 57', end: '1592-05-23', label: '가', source: '나', note: '다' }, { end: '현재', start: 1 }], 'cell');
  if (J(read(once, 'cell')) !== J(once) || once[0].start !== HT.parseYear('기원전 57') || once[0].endAt !== '1592-05-23' || once[1].ongoing !== true) bad(`이설을 다시 읽으면 꼴이 달라지거나 날짜 글 · 현재까지가 풀리지 않음: ${J(once)}`);
  const oldMsg = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-alt-old', name: '검사', tracks: [{ id: 't', name: 't' }], events: [{ id: 'e', track: 't', title: '사건', start: 100, alternatives: [{ start: '아무 글' }] }] });
  if (!oldMsg.warnings.some(w => w.msg === '사건 #1 "사건": 이설 #1의 연도를 읽을 수 없어 뺐습니다.')) bad('항목의 이설 알림 글이 예전과 달라짐');
  const lead = { start: 352, end: 410 };
  const f1 = HT.altSpan({ end: 408, label: '가' }, lead);
  if (f1.start !== 352 || f1.end !== 408 || f1.own.start || !f1.own.end) bad('한쪽만 있는 칸 이설의 빈 쪽이 통설 값으로 채워지지 않음 (HT.altSpan)');
  if (HT.altWhen({ label: '가' }, lead) !== '' || HT.altText({ label: '가' }, lead) !== '가') bad('글만 있는 견해의 날짜 글이 비지 않음');
  if (HT.altWhen({ birth: 328, label: '가' }, { birth: 330, death: 395, start: 352, end: 390 }, { figure: true }) !== `생몰 ${HT.formatYear(328)} ~ ${HT.formatYear(395)}`) bad('인물 이설의 날짜 글이 적은 쪽(생몰)만 보이지 않음');
  } catch (e) {
    bad(`② 읽기 규칙 — 검사 도중 오류: ${e.message}`);
  }
  try {
  /* ③ 모델 */
  const mAll = HT.buildModel(packs.concat(r.pack ? [r.pack] : []).filter((p, i, a) => a.findIndex(q => q.id === p.id) === i), null);
  const MP = mAll.byUid.get('lantern-chronicle/p-lantern');
  const MPJ = mAll.byUid.get('lantern-chronicle/p-jeokseok');
  if (!MP || !MPJ) bad('견본의 나라가 모델에 없음');
  else {
    if (MP.alternatives || MP.spanMin !== MP.start || MP.spanMax !== MP.endY) bad('칸의 이설이 정권의 이설 · 범위로 번짐 (정권에는 이설이 없음)');
    if (MP.capitals[0].certainty !== 'legend') bad('모델의 도읍(HT.resolveCapitals)에 확실성이 없음');
    if (!(MP.phaseSchemes[1].spans[1].alternatives || []).length) bad('모델의 시기(phaseSchemes)에 이설이 없음');
    if (!(MPJ.hosts[0].alternatives || []).length) bad('모델의 소속(hosts)에 이설이 없음');
    if (((MP.leaders.find(c => c.name === '무진왕') || {}).alternatives || []).length !== 1 || MP.leaders[0].certainty !== 'legend') bad('모델의 지도자 칸에 이설 · 확실성이 없음');
    const MF = mAll.figures.find(f => f.uid === 'lantern-chronicle/f-seorin');
    if (!MF || (MF.alternatives || []).length !== 1 || !(MF.services[1].alternatives || []).length) bad('모델의 인물 · 활동 기록(services)에 이설이 없음');
    const ME = mAll.events.find(e => e.uid === 'lantern-chronicle/e-extinguish');
    if (!ME || ME.spanMin !== 411 || ME.spanMax !== 412) bad(`날짜가 있는 견해가 사건의 범위를 넓히지 않음 (spanMin ${ME && ME.spanMin} · spanMax ${ME && ME.spanMax})`);
    const MEp = mAll.epochs.find(e => e.uid === 'lantern-chronicle/ep-mist');
    if (!MEp || (MEp.alternatives || []).length !== 2) bad('모델의 시대 구분에 이설이 없음');
    else if (HT.datedAlts(MEp).length !== 1) bad('그림에 쓰는 이설(HT.datedAlts)이 글만 있는 견해를 거르지 않음');
  }
  } catch (e) {
    bad(`③ 모델 — 검사 도중 오류: ${e.message}`);
  }
  /* ④ 폼 — 작은 HTML 읽개로 폼의 줄을 만들어 읽음 (브라우저 없이: 태그 · 속성 · 자식, 선택자 '.a' '[b]' '[b="c"]' 'tag'와 그 조합 · 띄어 쓴 자손) */
  const unesc = s => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const miniDom = html => {
    const root0 = { tag: '#root', attrs: {}, kids: [], parent: null };
    const VOID = new Set(['input', 'br', 'img', 'hr', 'meta', 'link']);
    let cur = root0;
    for (const m of html.matchAll(/<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:\s+[^\s=>]+(?:="[^"]*")?)*)\s*\/?>|([^<]+)/g)) {
      if (m[4] != null) continue;
      const tag = m[2].toLowerCase();
      if (m[1]) {
        let n = cur;
        while (n && n.tag !== tag) n = n.parent;
        if (n) cur = n.parent;
        continue;
      }
      const attrs = {};
      for (const a of m[3].matchAll(/([^\s=>]+)(?:="([^"]*)")?/g)) attrs[a[1]] = a[2] == null ? '' : unesc(a[2]);
      const node = { tag, attrs, kids: [], parent: cur };
      cur.kids.push(node);
      if (!VOID.has(tag)) cur = node;
    }
    const simple = (n, sel) => {
      for (const part of sel.match(/[a-z][a-z0-9-]*|\.[\w-]+|\[[^\]]+\]/gi) || []) {
        if (part[0] === '.') { if (!(n.attrs.class || '').split(/\s+/).includes(part.slice(1))) return false; }
        else if (part[0] === '[') {
          const [, k, v] = part.match(/^\[([^=\]]+)(?:="([^"]*)")?\]$/);
          if (!(k in n.attrs) || (v != null && n.attrs[k] !== v)) return false;
        } else if (n.tag !== part.toLowerCase()) return false;
      }
      return true;
    };
    const matches = (n, sel) => {
      const parts = sel.trim().split(/\s+/);
      if (!simple(n, parts[parts.length - 1])) return false;
      let i = parts.length - 2;
      for (let p = n.parent; p && i >= 0; p = p.parent) if (p.tag !== '#root' && simple(p, parts[i])) i--;
      return i < 0;
    };
    const all = n => n.kids.flatMap(k => [k, ...all(k)]);
    const wrap = n => {
      if (!n) return null;
      if (n.w) return n.w;
      const w = (n.w = {
        tagName: n.tag.toUpperCase(),
        get children() { return n.kids.map(wrap); },
        get parentElement() { return wrap(n.parent); },
        classList: { contains: c => (n.attrs.class || '').split(/\s+/).includes(c) },
        dataset: Object.fromEntries(Object.entries(n.attrs).filter(([k]) => k.startsWith('data-')).map(([k, v]) => [k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase()), v])),
        matches: sel => matches(n, sel),
        querySelector: sel => wrap(all(n).find(k => matches(k, sel))),
        querySelectorAll: sel => all(n).filter(k => matches(k, sel)).map(wrap),
        get value() {
          if (n.tag === 'select') {
            const opts = all(n).filter(k => k.tag === 'option');
            return ((opts.find(o => 'selected' in o.attrs) || opts[0] || { attrs: {} }).attrs.value) ?? '';
          }
          return n.attrs.value ?? '';
        },
      });
      return w;
    };
    return wrap(root0);
  };
  /* 폼 · 패치 시험용 사본: 칸의 이름 목록(names — 형식 3)은 줄 안 상자를 ':scope >' 선택자로 읽어 위의 작은 읽개가 따라가지 못하므로 뺀 사본으로 봄 */
  const rawF = JSON.parse(JSON.stringify(raw));
  for (const p of rawF.periods || []) for (const k of ['leaders', 'cabinets', 'eras', 'capitals']) for (const c of p[k] || []) if (c && typeof c === 'object' && !Array.isArray(c)) delete c.names;
  const rF = HT.normalizePack(rawF).pack;
  const PF = rF ? rF.periods.find(p => p.id === 'p-lantern') : null;
  try {
  if (PF && PJ) {
    const P = PF;
    const cellsFor = kind => (kind === 'leaders' ? P.leaders : P[kind]).map(c => HT.cellRowHTML(kind, HT.formCell(kind, c))).join('');
    const dom = miniDom(['leaders', 'cabinets', 'eras', 'capitals', 'ranks'].map(k => `<div class="cell-rows" data-cells="${k}">${cellsFor(k)}</div>`).join('') +
      `<div class="phase-schemes" data-phases>${P.phases.map(g => HT.phaseSchemeHTML(g)).join('')}</div>` +
      `<div class="succ-rows" data-parts data-relation>${HT.readPartOf(PJ.partOf, { relation: true }).map(s => HT.partOfRowHTML(s, { relation: true })).join('')}</div>` + // 소속 줄은 적석 왕국의 것(이설 · 관계)
      `<div class="alt-rows" data-alts="">${HT.altRowHTML({ start: 290, label: '정권의 이설', ongoing: true, source: '가', note: '나' })}</div>`);
    const problems = [];
    const back = {
      leaders: HT.readCellRows(dom, 'leaders', '지도자', problems), cabinets: HT.readCellRows(dom, 'cabinets', '내각', problems), eras: HT.readCellRows(dom, 'eras', '연호', problems),
      capitals: HT.readCellRows(dom, 'capitals', '도읍', problems), ranks: HT.readCellRows(dom, 'ranks', '지위', problems), phases: HT.readPhaseRows(dom, problems), partOf: HT.readPartOfRows(dom, problems),
    };
    if (problems.length) bad(`폼을 채우고 그대로 읽었는데 문제가 남: ${problems.join(' / ')}`);
    const capsCanon = list => canon(list.map(c => HT.normalizeCapital(c)));
    for (const k of ['leaders', 'cabinets', 'eras', 'ranks', 'phases']) if (canon(back[k]) !== canon(P[k])) bad(`폼의 ${k} 줄을 채웠다 읽으니 달라짐 (이설 · 출처 · 메모 · 확실성 · 연대 폭): ${J(back[k])}`);
    if (capsCanon(back.capitals) !== capsCanon(P.capitals)) bad('폼의 도읍 줄을 채웠다 읽으니 이설 · 확실성이 달라짐');
    if (canon(HT.compactPartOf(back.partOf)) !== canon(PJ.partOf)) bad(`폼의 소속 줄을 채웠다 읽으니 이설 · 관계가 달라짐: ${J(back.partOf)}`);
    /* 항목 자신의 이설은 제 상자만 — 칸 줄 안의 이설 여덟 개가 정권의 이설로 빨려 들지 않음 · 현재까지 · 출처 · 메모가 남음 */
    const own = HT.readUncertainty(Object.assign(dom, { elements: { certainty: { value: 'accepted' }, debate: { value: '' } } }), problems).alternatives; // 사건 · 시대 폼과 같은 길 (HT.readUncertainty)
    if (J(own) !== J([{ start: 290, label: '정권의 이설', ongoing: true, source: '가', note: '나' }])) bad(`항목의 이설 줄이 칸의 이설까지 읽거나 출처 · 메모 · 현재까지를 떨어뜨림: ${J(own)}`);
    /* 인물의 이설 줄(출생 · 사망 칸) · 활동 기록 줄 */
    const fdom = miniDom(`<div class="alt-rows" data-alts="figure">${r.pack.figures[0].alternatives.map(a => HT.altRowHTML(a, { mode: 'figure' })).join('')}</div><div class="succ-rows" data-services>${r.pack.figures[0].service.map(s => HT.serviceRowHTML([], s)).join('')}</div>`);
    if (J(HT.readAlternativesField(fdom, problems)) !== J(r.pack.figures[0].alternatives)) bad('인물의 이설 줄을 채웠다 읽으니 달라짐 (생몰 칸)');
    if (canon(HT.readServiceRows(fdom, problems)) !== canon(r.pack.figures[0].service)) bad('활동 기록 줄을 채웠다 읽으니 이설이 달라짐');
    /* 글로 적힌 기원전 날짜("기원전 57" — 파일 그대로의 칸)도 기원 고르기가 글과 맞게 채워져 되읽으면 같은 해 */
    const bc = miniDom(`<div class="alt-rows" data-alts="">${HT.altRowHTML({ start: '기원전 57', end: -40, label: '가' })}</div>`);
    const bcBack = HT.readAlternativesField(bc, problems);
    if (!bcBack.length || bcBack[0].start !== HT.parseYear('기원전 57') || bcBack[0].end !== -40) bad(`글로 적힌 기원전 날짜가 이설 줄을 거치며 기원후로 바뀜: ${J(bcBack)}`);
    /* 칸의 이설 상자에서 잘못 적은 연대 폭은 저장을 막음 */
    const badBox = miniDom(`<div data-cells="eras">${HT.cellRowHTML('eras', { name: '가', start: 1, startRange: [0, null] })}</div>`); // 늦은 쪽을 비운 연대 폭
    const pr2 = [];
    HT.readCellRows(badBox, 'eras', '연호', pr2);
    if (!pr2.some(m => /1번째 줄: 시작 연대 폭은/.test(m))) bad(`칸의 연대 폭 한쪽만 적었는데 알리지 않음: ${J(pr2)}`);
    /* ⑤ 패치: 남의 나라를 폼으로 열어 저장만 → 패치 0건, 지도자 하나에 이설을 더함 → 지도자 목록만 */
    const D = HT.draft;
    const draft = D.blank({ id: 'smoke-alt-dlc', name: '검사 DLC' });
    const MP2 = HT.buildModel([rF], null).byUid.get('lantern-chronicle/p-lantern');
    const formOf = over => Object.assign({ name: MP2.name, start: MP2.start, startAt: null, end: MP2.end, endAt: null, ongoing: false, track: MP2.track, description: MP2.description, leaders: back.leaders, cabinets: back.cabinets, eras: back.eras, capitals: back.capitals, ranks: back.ranks, phases: back.phases, partOf: P.partOf, certainty: 'accepted', alternatives: [] }, over);
    D.patchForeign(draft, MP2, formOf());
    if (draft.patches.length) bad(`이설이 있는 칸 목록을 손대지 않고 폼을 거쳤는데 패치가 생김: ${J(draft.patches)}`);
    const more = back.leaders.map((c, i) => (i === 0 ? Object.assign({}, c, { alternatives: [{ end: 353, label: '하나 더' }] }) : c));
    D.patchForeign(draft, MP2, formOf({ leaders: more }));
    const set = (draft.patches[0] || {}).set || {};
    if (draft.patches.length !== 1 || Object.keys(set).join() !== 'leaders') bad(`지도자 하나에 이설을 더했는데 패치의 칸이 [${Object.keys(set)}]`);
    const pm = HT.buildModel([rF, HT.normalizePack(draft).pack], null).byUid.get(MP2.uid);
    const ch = HT.patchChanges(pm, 0).find(c => c.k === 'leaders');
    if (!ch || ch.edited !== 1 || ch.uncEdited !== 1) bad(`수정 내역이 '지도자 21개 (1개 고침 — 이설 · 연대 폭만)'이 아님: ${J(ch && { edited: ch.edited, uncEdited: ch.uncEdited })}`);
    if (((pm.leaders[0].alternatives || [])[0] || {}).end !== 353) bad('패치로 더한 지도자의 이설이 모델에 없음');
  }
  } catch (e) {
    bad(`④ 폼 · ⑤ 패치 — 검사 도중 오류: ${e.message}`);
  }
  try {
  const pk = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-alt-p', name: '검사', tracks: [{ id: 't', name: 't' }], patches: [{ target: 'x/y', set: { alternatives: [{ start: '기원전 57', label: '가' }, { death: 60, label: '나' }] } }] });
  const ps = pk.pack && pk.pack.patches[0].set.alternatives;
  if (!ps || ps[0].start !== HT.parseYear('기원전 57') || ps[1].death !== 60) bad(`패치의 이설 날짜 글이 풀리지 않거나 인물의 생몰 이설이 빠짐: ${J(ps)}`);
  const evTarget = HT.buildModel([HT.normalizePack({ format: HT.FORMAT, id: 'x', name: 'x', tracks: [{ id: 't', name: 't' }], events: [{ id: 'y', track: 't', title: '가', start: 1 }] }).pack, pk.pack], null).byUid.get('x/y');
  if (!evTarget || evTarget.alternatives.length !== 1 || !isFinite(evTarget.spanMin)) bad('사건을 가리킨 패치의 이설에서 시작이 없는 것(생몰)을 거르지 않음');
  } catch (e) {
    bad(`⑤ 패치의 이설 — 검사 도중 오류: ${e.message}`);
  }
  try {
  /* ⑥ 형식 버전 */
  const ver = x => HT.packToJSON(HT.normalizePack(Object.assign({ format: HT.FORMAT, id: 'smoke-alt-v', name: '검사', tracks: [{ id: 't', name: 't' }] }, x)).pack).formatVersion;
  const per = cell => ({ periods: [Object.assign({ id: 'p', track: 't', name: '가', start: 1, end: 100 }, cell)] });
  if (ver(per({ eras: [{ name: '가', start: 1, end: 9, alternatives: [{ end: 8 }] }] })) !== 2) bad('연호에 이설을 적었는데 형식 버전 1로 나감 (옛 앱은 칸의 이설을 말없이 버림)');
  if (ver(per({ leaders: [{ name: '가', start: 1, certainty: 'estimated' }] })) !== 2) bad('지도자 칸에 확실성을 적었는데 형식 버전 1로 나감');
  if (ver(per({ partOf: [{ polity: '나', start: 1, end: 5, startRange: [1, 3] }] })) !== 2) bad('소속 줄에 연대 폭을 적었는데 형식 버전 1로 나감');
  if (ver({ epochs: [{ id: 'e', name: '가', start: 1, alternatives: [{ start: 2 }] }] }) !== 2) bad('시대 구분에 이설을 적었는데 형식 버전 1로 나감');
  if (ver({ events: [{ id: 'e', track: 't', title: '가', start: 1, alternatives: [{ label: '글만' }] }] }) !== 2) bad('사건에 글만 있는 견해를 적었는데 형식 버전 1로 나감 (옛 앱은 버림)');
  if (ver({ events: [{ id: 'e', track: 't', title: '가', start: 1, alternatives: [{ start: 2, end: 3, label: '예전 꼴' }] }] }) !== 1) bad('예전 꼴의 사건 이설만 있는데 형식 버전 2로 나감');
  if (ver({ patches: [{ target: 'x/y', set: { leaders: [{ name: '가', start: 1, alternatives: [{ start: 2 }] }] } }] }) !== 2) bad('패치의 지도자 칸에 이설을 적었는데 형식 버전 1로 나감');
  for (const raw0 of HT.getBuiltinPacks()) {
    const j = HT.packToJSON(HT.normalizePack(raw0).pack);
    if (HT.usesCellUncertainty(j)) bad(`칸의 이설을 쓰지 않은 기본팩 ${raw0.id}이 칸의 이설을 쓴 것으로 잡힘`);
  }
  } catch (e) {
    bad(`⑥ 형식 버전 — 검사 도중 오류: ${e.message}`);
  }
  try {
  /* 화면 뼈대: 칸 줄 끝의 [이설] 단추와 줄 안의 상자 · 칸 창 · 시대 구분 창 · 인물 창의 '다른 견해' · 정권 상세의 '이설 n' 딱지 */
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const csrc = readFileSync(join(root, 'js/core.js'), 'utf8');
  const html = HT.cellRowHTML('leaders', { name: '가', start: 1 });
  if (!/data-calt-toggle[^>]*>이설<\/button><button type="button" class="icon-btn" data-cell-del/.test(html) || !/<div class="cell-alts" hidden>/.test(html) || /placeholder/.test(html.slice(html.indexOf('cell-alts')))) bad('칸 줄 끝에 [이설] 단추 · 접힌 상자가 없거나 상자에 회색 예시 글이 있음');
  if (/placeholder/.test(HT.altRowHTML({}, { mode: 'figure' }))) bad('이설 줄에 회색 예시 글(placeholder)이 남음');
  if ((vsrc.match(/altHTML\(c, \{ base: cellBase\(x, c, \{ start, end, endAt \}\) \}\)/g) || []).length !== 3 || !/altHTML\(x, \{ base: figureBase\(x\), figure: true \}\)/.test(vsrc)) bad("칸 · 시기 · 지위 창과 인물 창에 '다른 견해' 상자가 없음");
  if ((vsrc.match(/\$\{altTagHTML\(c\)\}/g) || []).length !== 4) bad("정권 상세의 칸 목록(지도자 · 내각 · 연호 · 도읍 · 시기 · 지위)에 '이설 n' 딱지가 없음");
  if (/form\.querySelectorAll\('\.alt-row'\)/.test(csrc) || /form\.querySelector\('\.alt-row:last-child/.test(csrc)) bad('폼 전체에서 이설 줄을 찾는 곳이 남음 (칸의 이설이 정권의 이설로 빨려 듦)');
  } catch (e) {
    bad(`화면 뼈대 — 검사 도중 오류: ${e.message}`);
  }
}
/* ㊴ 칸의 이설 · 모호한 칸의 연표 그림(2026-09-19 감독 결정 — 건의 4 뒷부분 '기본적으로 유령 구분선을 쓰고, 이설이 아니라 자체가 모호하면 띠 같이 흐려지게, 점선 등'):
   ① 자리를 정하는 순수 함수(Timeline.altEdges · altMarks · altRowPlan — 화면과 그림 내보내기가 함께 씀): 이설의 경계 해(통설과 같은 쪽 · 글만 있는 견해는 없음),
      진짜 구분선 · 칸 끝에서 3px 안 · 띠 밖 · 미정 꼬리 안이면 선 대신 '이설 있음', 선이 이름표에 닿으면 적게 움직이는 쪽으로 3px 비킴(비킬 자리가 없거나 앞글자만인 칸이면 '이설 있음'),
      같은 자리의 선은 하나, 모호한 칸의 무늬는 이름표 글자를 비키고 연대 폭 안의 구분선은 점선
   ② 연표 코드: 모든 칸 종류(지도자 · 내각 · 시기 · 지위 · 왕조 · 속국 이름표(품은 칸 · 매달린 탭) · 인물 막대 · 날짜 칸의 연호 · 도읍)가 한 계획(_altPlan)을 부르고, 날짜 칸도 키로 이어 씀(morph),
      띠 · 인물 막대의 속은 한 겹 더 morph(유령선 · 이설 조명이 떠오르고 옅어짐), 이설 조명은 조명(spots)과 다른 층(메아리 · 맨 위 괄호에 들지 않음), 그림 내보내기도 같은 계획 ·
      시대 띠의 이설 고리 · 사건 이설의 끝
   ③ CSS · 범례 · 표시 체크의 글 */
{
  const bad = msg => out.problems.push(`칸 이설의 그림: ${msg}`);
  const J2 = x => JSON.stringify(x);
  try {
    if (!HT.Timeline) vm.runInThisContext(readFileSync(join(root, 'js/timeline.js'), 'utf8'), { filename: 'js/timeline.js' });
  } catch (e) {
    bad(`js/timeline.js를 노드에서 읽지 못함 — ${e.message}`);
  }
  const TL = HT.Timeline || {};
  try {
    if (typeof TL.altEdges !== 'function' || typeof TL.altMarks !== 'function' || typeof TL.altRowPlan !== 'function') bad('Timeline.altEdges · altMarks · altRowPlan(화면 · 그림 공용 순수 함수)이 없음');
    else {
      /* ① 경계 해 */
      const base = { start: 352, end: 410 };
      const ys = TL.altEdges({ alternatives: [{ start: 350, end: 412, label: '갑' }, { end: 408, label: '을' }, { label: '글만' }, { start: 352, end: 410, label: '같음' }, { start: 350, label: '같은 해 둘째' }] }, base).map(e => `${e.side}${e.y}`);
      if (ys.join(',') !== 's350,e412,e408') bad(`이설의 경계 해가 틀림 (통설과 같은 쪽 · 글만 있는 견해 · 같은 해는 빠져야 함): ${ys}`);
      if (TL.altEdges({ alternatives: [{ ongoing: true, label: '현재까지' }] }, base, 700).map(e => e.y).join() !== '700') bad('현재까지인 이설의 끝이 그 정권의 끝(now)으로 서지 않음');
      /* ① 선 · 이설 있음 · 비킴 */
      const cells = () => [
        { l: 0, r: 100, ink: { c: 50, w: 30 } },
        { l: 100, r: 200, ink: { c: 150, w: 30 } },
      ];
      const M = (marks, o) => TL.altMarks(cells(), marks, o || {});
      let r = M([{ x: 98, owner: 0, key: 'a' }]);
      if (r.lines.length || !r.has.has(0)) bad('진짜 구분선에서 3px 안의 이설이 선으로 그려짐 (선 대신 이름 밑 이설 있음이어야 함)');
      r = M([{ x: 94, owner: 0, key: 'a' }]);
      if (r.lines.length !== 1 || r.has.size) bad('진짜 구분선에서 6px 떨어진 이설이 선으로 그려지지 않음');
      r = M([{ x: 60, owner: 0, key: 'a' }]);
      if (r.lines.length !== 1 || r.shift.get(0) !== -8) bad(`선이 이름표에 닿을 때 적게 움직이는 쪽으로 3px 비키지 않음 (옮김 ${r.shift.get(0)} — 기대 -8)`);
      const fixed = cells();
      fixed[0].fixed = true;
      r = TL.altMarks(fixed, [{ x: 60, owner: 0, key: 'a' }], {});
      if (r.lines.length || !r.has.has(0)) bad('앞글자만 보이는 칸(이름표를 옮길 수 없음)의 글자에 선이 그어짐');
      const tight = [{ l: 0, r: 40, ink: { c: 20, w: 30 } }];
      r = TL.altMarks(tight, [{ x: 20, owner: 0, key: 'a' }], {});
      if (r.lines.length || !r.has.has(0)) bad('이름표를 비킬 자리가 없는 칸에 선이 그대로 그어짐');
      r = M([{ x: 150, owner: 1, key: 'a' }, { x: 151, owner: 0, key: 'b' }]);
      if (r.lines.length !== 1) bad('같은 자리의 이설(앞 칸의 끝 = 뒤 칸의 시작) 선이 둘로 겹쳐 그려짐');
      r = M([{ x: 70, owner: 0, key: 'a' }], { lo: 80, hi: 200 });
      if (r.lines.length || !r.has.has(0)) bad('띠 밖의 이설 경계가 선으로 그려짐');
      const faded = cells();
      faded[0].fade = [[0, 30]];
      r = TL.altMarks(faded, [{ x: 20, owner: 0, key: 'a' }], {});
      if (r.lines.length || !r.has.has(0)) bad('칸의 미정 꼬리(옅어지는 끝) 안에 선이 그어짐');
      r = M([{ x: 94, owner: 0, key: 'a' }, { x: 98, owner: 0, key: 'b' }]);
      if (r.lines.length !== 1 || r.has.size) bad('선이 하나라도 그어진 칸에 이름 밑 이설 있음이 또 붙음');
      const seen = [];
      M([{ x: 94, owner: 0, key: 'k1' }], { far: (k, d) => (seen.push([k, Math.round(d)]), d >= 3) });
      if (J2(seen) !== J2([['k1', 6]])) bad(`3px 문턱을 화면의 두 문턱 함수(far — 키 · 거리)에 맡기지 않음: ${J2(seen)}`);
      /* ① 모호한 칸: 이어 붙은 두 칸에 걸친 연대 폭 — 무늬는 두 칸 모두 · 글자 비킴 · 사이 구분선 점선 */
      const X = y => (y - 300) * 2;
      const row = [
        { l: X(300), r: X(410), jr: true, c: { name: '가' }, key: 'leader:0', base: { start: 300, end: 410 }, ink: null },
        { l: X(410), r: X(500), jl: true, c: { certainty: 'estimated', startRange: [400, 420] }, key: 'leader:1', base: { start: 410, end: 500 }, ink: null },
      ];
      const plan = TL.altRowPlan(row, { X, h: 20, far: (k, d) => d >= 3, alt: true });
      const z0 = plan.zones.get(0);
      const z1 = plan.zones.get(1);
      if (!z0 || !z1 || !z0.layers.length || !z1.layers.length) bad('연대 폭이 이웃 칸에 걸치는데 두 칸 모두에 무늬가 없음');
      else {
        if (!z1.zl || z0.zl) bad('연대 폭 안의 사이 구분선(뒤 칸의 왼쪽)만 점선이어야 함');
        if (z0.layers.some(q => q.kind !== 'estimated')) bad('추정 연대의 무늬가 세로 줄(estimated)이 아님');
      }
      const lab = TL.altRowPlan([{ l: 0, r: 200, c: { certainty: 'legend' }, key: 'x', base: { start: 0, end: 100 }, ink: { text: '가나', size: 11.5, wt: 600 } }], { X: y => y, h: 20, far: () => true });
      const zl = lab.zones.get(0);
      if (!zl || zl.layers.length !== 2 || zl.layers.some(q => q.kind !== 'legend')) bad(`확실성만 적은 칸(전승)의 무늬가 칸 전체(이름표 양옆 두 조각 · 빗금)가 아님: ${J2(zl)}`);
      const noAlt = TL.altRowPlan([{ l: 0, r: 200, c: { alternatives: [{ start: 50, label: '가' }] }, key: 'x', base: { start: 0, end: 100 }, ink: null }], { X: y => y * 2, h: 20, far: () => true, alt: false });
      if (noAlt.lines.length) bad("'이설' 체크를 끄면(alt: false) 유령선이 남음");
    }
  } catch (e) {
    bad(`① 순수 함수 — 검사 도중 오류: ${e.message}`);
  }
  try {
    /* ② 연표 코드 */
    const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
    const at = (a, b) => tsrc.slice(tsrc.indexOf(a), b ? tsrc.indexOf(b, tsrc.indexOf(a)) : undefined);
    const body = {
      지도자내각: at('    _cells(list, kind, p, X, ox, iw, top, h, clip = {}) {', '    shownBandOf('),
      시기: at('    _phaseCells(p, X, ox, iw, top, clip = {}) {', '    _rankCells('),
      지위: at('    _rankCells(p, X, ox, iw, top, clip = {}) {', '    _drawTrack('),
      왕조: at('    _dynCells(p, X, ox, iw, top, h, clip = {}) {', '    /** 칸 한 줄의'),
      품은칸: at('    _depCells(', '    _depHangs('),
      매달린이름표: at('    _depHangs(', '    _depSVG('),
      인물막대: at('    _figureBars(tr, X, W) {', '    /** 시기 구분(학계) 단'),
      연호: at('      /* 나라별 연호 */', '      /* 접힌 연호·도읍 묶음'),
      도읍: at('      /* 나라별 도읍:', '      if (this._hotCity)'),
    };
    for (const [k, src] of Object.entries(body)) {
      if (!src) bad(`연표 코드에서 ${k} 그리기를 찾지 못함`);
      else if (!/this\._altPlan\(/.test(src) || !/this\._altMarksHTML\(/.test(src)) bad(`${k} 칸이 유령 구분선 계획(_altPlan · _altMarksHTML)을 부르지 않음`);
    }
    if ((body.연호.match(/morph\(el, html \+ marks, fx\)/g) || []).length !== 1 || (body.도읍.match(/morph\(el, html \+ marks, fx\)/g) || []).length !== 1) bad('날짜 칸(연호 · 도읍)이 키로 이어 쓰지 않음(innerHTML) — 유령선이 팍 나타남');
    if (!/data-k="\$\{esc\(u\.key\)\}"/.test(body.연호)) bad('연호 칸에 키(data-k)가 없음');
    if (!/const DEEP = el => el\.classList\.contains\('tl-band'\) \|\| el\.classList\.contains\('tl-fig'\)/.test(tsrc) || !/morph\(o, inner, d, null, 1\)/.test(tsrc)) bad('띠 · 인물 막대의 속을 한 겹 더 morph하지 않음 — 유령선 · 이설 조명이 떠오르거나 옅어지지 않음');
    if (!/if \(depth\) \{[\s\S]{0,400}if \(!c\.dataset\.k\) c\.remove\(\);/.test(tsrc)) bad('속 morph가 키 없는 옛 요소를 먼저 치우지 않음 — 키가 붙은 표식이 옮겨 끼워지며 색 전환이 끊김');
    /* 이설 조명: 칸을 다 그린 뒤(그은 유령선을 보고) 조명 틀 바로 뒤에 끼움 — 조명(litYears · 메아리)과 다른 층 */
    const spotBlk = at('          for (const s of own) paint(s.start, s.end, false);', '        /* 분류별 글줄 사이의 아주 옅은 구분선 */');
    if (!/const altSpot = this\._altSpotsHTML\(p, tr, altOwn, X, ox, iw, gr, BW, this\._caltAt\);\s*if \(altSpot\) inner = inner\.slice\(0, altCut\) \+ altSpot \+ inner\.slice\(altCut\);/.test(spotBlk) || /litYears/.test(spotBlk.slice(spotBlk.indexOf('const altSpot'))) || /litYears/.test(at('    _altSpotsHTML(', '    /** 지도자·내각 칸.'))) bad('이설 조명이 칸 조명과 다른 층이 아님');
    if (/altspot|altSpot/i.test(at('    _echoSpans() {', '    /** (공개) 정권마다'))) bad('이설 조명이 메아리 기간(_echoSpans)에 들어감');
    const svg = tsrc.slice(tsrc.indexOf('    toSVG({'));
    if ((svg.match(/svgPlan\(/g) || []).length < 6) bad('그림 내보내기가 칸 종류마다 같은 계획(svgPlan — altRowPlan)을 부르지 않음 (지도자 · 내각 · 시기 · 지위 · 기관 · 왕조 · 인물)');
    const depSvg = at('    _depSVG(', '    _hollowHTML(');
    if (!/svgPlan\(/.test(depSvg) || !/svgAlt\(/.test(depSvg) || !/this\._depSVG\([^;]*\bsvgPlan\b[^;]*\bsvgAlt\b/.test(svg)) bad('그림 내보내기의 속국 이름표가 같은 이설 계획(svgPlan · svgAlt)을 받지 않음');
    if (!/stroke-dasharray="1 2"/.test(svg)) bad("그림 내보내기의 유령 구분선이 1px 점선('1 2')이 아님");
    if (!/<circle cx="\$\{n\(GW \+ ax \+ 0\.5\)\}" cy="\$\{n\(y \+ 1\)\}" r="3\.25"/.test(svg)) bad('그림 내보내기에 시대 띠의 이설 고리가 없음');
    if (!/altEnds\(ev, alts, it\.rx2, C, X\)/.test(svg) || !/data-k="ae:/.test(tsrc)) bad('사건 이설의 끝에 점선 세로바가 없음 (화면 · 그림)');
    if (!/for \(const y of \[a\.start, a\.end\]\)/.test(at('  const beadsOf = ', '    const edges = [];'))) bad('점 사건 이설의 끝에 구슬이 없음');
    /* ③ CSS · 범례 · 표시 체크 */
    const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
    const rule = sel => (csrc.match(new RegExp(`\\n${sel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} \\{[^}]*\\}`)) || [''])[0];
    if (!/pointer-events: none/.test(rule('.tl-calt')) || !/repeating-linear-gradient\(to bottom, var\(--gc\) 0 1px, transparent 1px 3px\)/.test(rule('.tl-calt'))) bad('유령 구분선이 누름을 받거나 1px 점(1 켜고 2 끔)이 아님');
    if (!/@property --gc \{ syntax: '<color>'/.test(csrc) || !/transition: --gc var\(--t-in\)/.test(csrc)) bad('조명된 칸의 유령선이 색만 짙어지는 전환(--gc)이 없음');
    if (!/\.tl-altspot \{[^}]*pointer-events: none/.test(csrc) || /\.tl-altspot[^{]*\{[^}]*border-(top|bottom)(-width|-style|-color)?:/.test(csrc)) bad('이설 조명이 누름을 받거나 위아래 선이 있음 (띠 테두리와 겹침)');
    if (!/\.tl-band \.tl-cell\.z-l[^{]*\{ border-left-style: dotted; \}/.test(csrc)) bad('모호한 칸의 연대 폭 안 구분선이 점선이 아님');
    const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
    if (!/class="lg-calt"/.test(vsrc) || !/class="lg-altspot"/.test(vsrc) || !/class="lg-czone"/.test(vsrc)) bad('범례에 유령 구분선 · 이설 조명 · 모호한 칸이 없음');
    const ihtml = readFileSync(join(root, 'index.html'), 'utf8');
    if (!/칸의 유령 구분선\(칸을 누르면 그 이설 기간도\)"><input id="altToggle"/.test(ihtml)) bad("표시 체크 '이설'의 설명에 칸의 유령 구분선이 없음");
  } catch (e) {
    bad(`② ③ 코드 — 검사 도중 오류: ${e.message}`);
  }
}
/* ㊵ 칸 이설의 반박 검토에서 나온 것(2026-09-20 — 648e35b · ee6b130 검토):
   ① 이설 조명의 좌우 점선이 보임(--gc는 물려받지 않는 변수라 가상 요소가 다시 받아 옴) ② 시작이 미정인 칸의 '다른 견해' 첫 줄이 '—'가 아님
   ③ 한쪽만 적은 이설의 빈 쪽을 통설 값으로 채우면 앞뒤가 뒤집히는 것 — 파일 · 폼은 빼고 알림, 읽을 때 모르는 끝(풀어 둔 끝)과 뒤집히면 연표에 그리지 않음, 채우는 쪽이 미정이면 견주지 않음
   ④ '이설' 체크를 끄면 생몰 고리도 없음 ⑤ 가문 줄이 있는 지도자 칸의 '이설 있음'은 그 줄 위에만 ⑥ 저장 뒤 펼쳐 두던 상자는 줄의 정체로 되살림
   ⑦ 이설 · 모호함이 없는 줄은 계획을 세우지 않음 ⑧ 시작 없는 이설을 담은 패치(인물로 보이지 않는 것)는 읽을 때 알림 · 알림 글의 조사
   ⑨ '확실'은 모호함이 아님(무늬 · 딱지 · 단추 글 · 범례) ⑩ 동작 줄이기에서는 상자가 내려오지 않음 ⑪ 기관 · 구역 · 왕조 항목 자신의 이설도 칸의 유령선 */
{
  const bad = msg => out.problems.push(`칸 이설 검토: ${msg}`);
  const J2 = x => JSON.stringify(x);
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const csrcCore = readFileSync(join(root, 'js/core.js'), 'utf8');
  try {
    /* ① */
    const pseudo = (csrc.match(/\n\.tl-altspot\.d-l::before, \.tl-altspot\.d-r::after \{[^}]*\}/) || [''])[0];
    if (!pseudo) bad('이설 조명의 좌우 점선 규칙을 찾지 못함');
    else if (/@property --gc \{[^}]*inherits: false/.test(csrc) && !/--gc: inherit/.test(pseudo) && !/--gc:\s*color-mix/.test(pseudo)) bad('이설 조명의 좌우 점선이 물려받지 않는 --gc를 다시 받지 않음 — 가상 요소에서는 초깃값(투명)이라 점선이 보이지 않음');
    /* ② */
    if (!/const baseAt = [^;]*base\.end != null \? \{ t: base\.end/.test(vsrc)) bad("시작이 미정인 칸의 '다른 견해' 첫 줄이 끝으로도 가지 않음");
    if (!/: when\s*\? `<li class="\$\{main \? 'is-main ' : ''\}is-text"><div class="alt-static"><b class="is-when">\$\{when\}<\/b>/.test(vsrc)) bad("누를 해가 없는 날짜 줄이 글만 있는 견해의 틀('—')로 그려짐");
    /* ③ 파일 */
    const P = extra => HT.normalizePack(Object.assign({ format: 'history-timeline-dlc', formatVersion: 2, id: 'rv37', name: 'rv37', version: '1', tracks: [{ id: 'tr', name: 'T', color: '#a0bcc5' }] }, extra));
    let r = P({ periods: [{ id: 'p', track: 'tr', name: 'P', start: 300, end: 500, leaders: [{ name: 'A', start: 352, end: 410, alternatives: [{ end: 340, label: '끝만' }, { start: 420, label: '시작만' }, { start: 350, label: '맞음' }] }, { name: 'B', start: '미정', startHint: 415, end: 480, alternatives: [{ end: 412, label: '미정 쪽' }] }] }] });
    const A = r.pack.periods[0].leaders.find(c => c.name === 'A').alternatives.map(a => a.label);
    const B = (r.pack.periods[0].leaders.find(c => c.name === 'B').alternatives || []).map(a => a.label);
    if (J2(A) !== J2(['맞음'])) bad(`한쪽만 적은 이설이 칸의 연대와 뒤집혀도 남음: ${J2(A)}`);
    if (r.warnings.filter(w => /앞서 뺐습니다|늦어 뺐습니다/.test(w.msg || w)).length !== 2) bad(`뒤집힌 한쪽 이설을 뺄 때 알림이 둘이 아님: ${J2(r.warnings.map(w => w.msg || w))}`);
    if (J2(B) !== J2(['미정 쪽'])) bad(`채우는 쪽이 미정인데 뒤집혔다고 뺌 (배치용 연도는 주장이 아님): ${J2(B)}`);
    r = P({ figures: [{ id: 'f', track: 'tr', name: 'F', birth: 300, death: 360, start: 320, end: 355, alternatives: [{ death: 290, label: '가' }, { end: 310, label: '나' }, { death: 350, label: '맞음' }] }] });
    if (J2(r.pack.figures[0].alternatives.map(a => a.label)) !== J2(['맞음'])) bad('인물의 한쪽 이설이 생몰 · 활동 시기와 뒤집혀도 남음');
    if (!r.warnings.some(w => /활동 끝이 이 인물의 활동 시작보다 앞서/.test(w.msg || w))) bad("인물의 뒤집힌 이설 알림이 '활동 시작 · 활동 끝'으로 말하지 않음");
    /* ③ 연표 · 상세: 읽을 때 모르는 끝(풀어 둔 끝)과 뒤집힘 */
    if (typeof HT.altFlipped !== 'function') bad('HT.altFlipped(연표 · 상세가 다시 보는 함수)가 없음');
    else {
      const f = [HT.altFlipped({ start: 420 }, { start: 352, end: 410 }), HT.altFlipped({ start: 400 }, { start: 352, end: 410 }), HT.altFlipped({ start: 420 }, { start: 352, ongoing: true }), HT.altFlipped({ end: 340 }, { start: 352, startUnknown: true, end: 410 }), HT.altFlipped({ label: '글만' }, { start: 1, end: 0 })];
      if (J2(f) !== J2([true, false, false, false, false])) bad(`HT.altFlipped가 틀림 (뒤집힘 · 맞음 · 현재까지 · 미정 · 글만): ${J2(f)}`);
    }
    const TL = HT.Timeline || {};
    if (TL.altEdges && TL.altEdges({ alternatives: [{ start: 420, label: '뒤집힘' }, { end: 405, label: '맞음' }] }, { start: 352, end: 410 }).map(e => e.y).join() !== '405') bad('뒤집힌 이설에 유령 구분선이 그어짐');
    if (!/HT\.altFlipped\(a, base\)\) return;/.test(tsrc)) bad('뒤집힌 이설에도 이설 조명이 칠해짐');
    if (!/const flip = HT\.altFlipped\(a, base, keys\)/.test(vsrc)) bad("상세 창의 '다른 견해'가 뒤집힌 이설을 누르는 줄로 둠 (까닭 없이)");
    /* ③ 폼 */
    if (!/const flip = mode !== 'item' && base && altFlipSide\(d, ongoing, base, Object\.keys\(d\)\);/.test(csrcCore)) bad('메이커 폼이 한쪽만 적은 이설의 뒤집힘을 막지 않음');
    if ((csrcCore.match(/HT\.readCellAlts\(row, problems, [^)]*, (o|\{ start: d\.start)/g) || []).length !== 8) bad('칸 줄마다 그 줄의 시작 · 끝을 이설 상자에 넘기지 않음'); // 8 = 기존 6 + 단체의 집권 기간 줄 · 제도 칸 줄 (형식 버전 3)
    if (!/HT\.readAlternativesField\(form, problems, figure\)/.test(csrcCore)) bad('인물 폼이 생몰 · 활동 시기를 이설 줄에 넘기지 않음');
    /* ④ */
    if (!/const lifeAlt = \(this\.showAlt && !this\._bird \? f\.alternatives \|\| \[\] : \[\]\)/.test(tsrc)) bad("'이설' 체크를 꺼도 생몰 고리가 남음");
    /* ⑤ */
    if (TL.altRowPlan) {
      const row = hm => [{ l: 0, r: 200, c: { alternatives: [{ end: 99.9, label: '가' }] }, key: 'leader:0', base: { start: 0, end: 100 }, ink: { text: '가나다', size: 11.5, wt: 600, lh: 14.95 }, hasMax: hm }];
      const X = y => y * 2;
      const free = TL.altRowPlan(row(undefined), { X, h: 20, far: (k, d) => d >= 3 });
      const tight = TL.altRowPlan(row(20 - 5), { X, h: 20, far: (k, d) => d >= 3 });
      if (!free.has.length) bad("'이설 있음' 시험 칸에 점선이 없음 (시험이 틀림)");
      else if (tight.has.some(q => q.y > 15)) bad(`가문 줄이 있는 칸의 '이설 있음'이 가문 줄(h-3)과 1px 떨어지지 않음: y ${tight.has.map(q => q.y)}`);
      /* ⑦ */
      const empty = TL.altRowPlan([{ l: 0, r: 100, c: { name: '가', certainty: 'certain', alternatives: [{ label: '글만' }] }, key: 'x', base: null, ink: { text: '가', size: 11, wt: 600 } }], { X, h: 20, far: () => true });
      if (empty.lines.length || empty.has.length || empty.shift.size || empty.zones.size) bad("그릴 것이 없는 칸('확실' · 글만 있는 견해)에 표식이 생김");
      /* ⑨ 확실 + 연대 폭 = 추정의 무늬 */
      const cz = TL.altRowPlan([{ l: 0, r: 200, c: { certainty: 'certain', startRange: [10, 40] }, key: 'x', base: null, ink: null }], { X, h: 20, far: () => true }).zones.get(0);
      if (!cz || cz.layers.some(q => q.kind !== 'estimated')) bad(`'확실'인데 연대 폭을 적은 칸의 무늬가 추정(세로 줄)이 아님: ${J2(cz)}`);
    }
    if (!/hasMax: houseMax\(kind, c, h\)/.test(tsrc) || !/hasMax: kindC === 'leader' && this\.show\.houses && u\.it\.c\.houseId \? cH - 5/.test(tsrc)) bad("가문 줄이 있는 지도자 칸의 '이설 있음' 한계를 화면 · 그림에 넘기지 않음");
    /* ⑥ */
    if (!/alts: caltSigs\(/.test(vsrc) || /keep\.alts\[i\]/.test(vsrc)) bad('저장 뒤 펼쳐 두던 이설 상자를 줄 순번으로 되살림 — 줄 차례가 바뀌면 다른 줄에서 열림');
    /* ⑦ */
    if (!/if \(!row\.some\(u => u\.c && HT\.drawsUncertainty\(u\.c\)\)\) \{ \/\/ 줄에 그릴 이설 · 모호함이 없으면 계산하지 않음/.test(tsrc) || !/if \(!\(c && c\.alternatives && c\.alternatives\.length\)\) return null;/.test(tsrc)) bad('이설 · 모호함이 없는 줄도 프레임마다 계획 · 통설 구간을 셈함');
    /* ⑧ */
    r = P({ patches: [{ target: 'xx/ev', set: { alternatives: [{ end: 460, label: '끝만' }, { start: 400, end: 'abc', label: '읽을 수 없는 끝' }] } }] });
    const pw = r.warnings.map(w => w.msg || w);
    if (!pw.some(w => /이설 #1에 시작이 없어, 고치는 대상이 사건 · 시대면 쓰이지 않습니다/.test(w))) bad(`시작 없는 이설을 담은 패치를 읽을 때 알리지 않음: ${J2(pw)}`);
    if (pw.some(w => /을\(를\)|이\(가\)/.test(w) && /이설/.test(w))) bad(`이설 알림 글의 조사가 겹침: ${J2(pw)}`);
    r = P({ patches: [{ target: 'xx/f', set: { death: 500, alternatives: [{ end: 460, label: '끝만' }] } }] });
    if (r.warnings.some(w => /시작이 없어/.test(w.msg || w))) bad('인물을 고치는 패치(사망이 있음)의 끝만 적은 이설에도 사건 · 시대 알림이 붙음');
    /* ⑨ */
    if (typeof HT.isFuzzy !== 'function' || HT.isFuzzy({ certainty: 'certain' }) || !HT.isFuzzy({ certainty: 'legend' }) || !HT.isFuzzy({ endRange: [1, 2] })) bad("HT.isFuzzy가 '확실'을 모호함으로 셈");
    if (!/HT\.isFuzzy\(u\) \? ' · 모호'/.test(csrcCore)) bad("[이설] 단추가 '확실'에도 '모호'라고 적음");
    if (!/const fuzzy = HT\.isFuzzy\(c\);/.test(vsrc)) bad("나라 상세 목록이 '확실'에 모호 딱지(점선)를 붙임");
    if (!/\$\{cellAlt \? `<li>/.test(vsrc) || !/\$\{cellFuzzy \? `/.test(vsrc)) bad('범례의 유령선 · 모호한 칸 줄을 따로 띄우지 않음 (글만 있는 견해만 있어도 뜸)');
    /* ⑩ */
    if (!/still = matchMedia\('\(prefers-reduced-motion: reduce\)'\)\.matches;/.test(csrcCore) || !/const lift = want && from < 0\.01 && !still \? -3 : 0;/.test(csrcCore)) bad('동작 줄이기에서도 이설 상자가 위에서 내려옴');
    /* ⑪ */
    if (typeof TL.dynCellOf !== 'function') bad('Timeline.dynCellOf(왕조 칸에 왕조 항목 자신의 이설을 더함)가 없음');
    else {
      const y = { start: 410, endY: 561, alternatives: [{ start: 405, end: 566, label: '넓게' }] };
      const first = TL.dynCellOf({ start: 410, end: 480, alternatives: [{ start: 408, label: '줄의 것' }] }, y).alternatives.map(a => `${a.start ?? ''}~${a.end ?? ''}`);
      const mid = TL.dynCellOf({ start: 480, end: 500 }, y).alternatives || [];
      const last = TL.dynCellOf({ start: 500, end: 561 }, y).alternatives.map(a => `${a.start ?? ''}~${a.end ?? ''}`);
      if (J2(first) !== J2(['408~', '405~']) || mid.length || J2(last) !== J2(['~566'])) bad(`왕조 항목 자신의 이설이 그 끝에 닿은 칸에만 더해지지 않음: ${J2({ first, mid, last })}`);
    }
    if ((tsrc.match(/dynCellOf\(d, y\)|dynCellOf\(d, yy\)/g) || []).length !== 2) bad('왕조 칸(화면 · 그림)이 왕조 항목 자신의 이설을 쓰지 않음');
    if (!/key: `org:\$\{p\.uid\}:\$\{h\.host\.uid\}`/.test(tsrc) || !/key: `org:\$\{p\.uid\}`/.test(tsrc)) bad('기관 · 구역 칸(화면 · 그림)이 항목 자신의 이설을 그리지 않음');
    if (!/const DEEP = el => el\.classList\.contains\('tl-band'\) \|\| el\.classList\.contains\('tl-fig'\) \|\| el\.classList\.contains\('tl-org'\);/.test(tsrc)) bad('기관 칸의 속을 한 겹 더 morph하지 않음 — 유령선이 팍 나타남');
    const dlcDoc = readFileSync(join(root, 'DLC-형식.md'), 'utf8');
    if (/그리는 것은 준비 중입니다/.test(dlcDoc)) bad("DLC-형식.md에 '연표 그림은 준비 중'이라는 옛 글이 남음");
  } catch (e) {
    bad(`검사 도중 오류: ${e.message}`);
  }
}
/* ㊶ 두 갈래가 만나는 곳(2026-09-20 교차 검토 — 선 · 배치 갈래(승계 이음매 · 조감)와 조명 · 칸 갈래(같은 시기 타국 · 모든 것에 이설)를 합친 2aa5706):
   ① 밀도 흐름 × 조명: 잔상에서 조명 틀(.tl-spots) · 이설 조명을 비우고 새 띠에서 다시 떠오르게 하지 않음, 흐린 띠의 조명 구간(has-lit)은 잔상에도 가림 판을 남김(벗기면 흐린 칸이 번쩍 밝아짐)
   ② 조감 × 이설: 화면 · 그림 내보내기가 같은 조건(조감에서는 시대 띠의 이설 고리 · 이설 조명 없음), 크기가 그대로인 맨 위 날짜 칸의 유령선은 조감에서도 그대로
   ③ 승계 이음매 × 고름: 문이 제 승계선과 함께 옅어짐(선만 .14로 옅어지고 문이 테두리를 연 채 남지 않게)
   ④ 조감 × 흐림: 띠 안 이름이 띠의 흐림을 따름(흐리지 않는 조명 구간에 든 이름은 그대로) ⑤ 조감 · 작은 알약 × 묶음 표시(is-hit) · 풀린 더미의 is-hit이 남지 않음
   ⑥ 이음매 × 경계 해: 곧바로 이어지는 승계 쌍의 경계 해는 뒤 나라의 것(앞 나라 마지막 칸이 후대의 첫해를 가지지 않음 — 건의 7의 규칙을 나라 경계에도)
   ⑦ 이설 조명의 점선은 그은 유령선이 있을 때만 · 띠 끝의 네모 · 관문 자리에서는 긋지 않음 ⑧ 네모 자리를 비켜 옮긴 알약이 이웃 점에 닿지 않음 */
{
  const bad = msg => out.problems.push(`두 갈래 교차: ${msg}`);
  const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
  const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  try {
    /* ① — _drawTrack이 조명을 담는 클래스 이름이 잔상 숨김 · 새 띠 떠오름 제외에 모두 들어 있어야 */
    const frame = (tsrc.match(/<i class="(tl-spots)">\$\{spotHtml\}<\/i>/) || [])[1];
    const alt = /<i class="(tl-altspot)\$\{/.test(tsrc) ? 'tl-altspot' : null;
    if (!frame || !alt) bad('조명 틀(.tl-spots) · 이설 조명(.tl-altspot)을 그리는 곳을 찾지 못함');
    const hide = (csrc.match(/\n(\.tl-sqz \.tl-band::before, [^{]*)\{ visibility: hidden; \}/) || [])[1] || '';
    if (frame && !new RegExp(`\\.tl-sqz \\.tl-band > :is\\([^)]*\\.${frame}\\b`).test(hide)) bad(`잔상이 조명 틀(.${frame})을 숨기지 않음 — 흐르는 동안 조명이 두 겹으로 짙어짐`);
    if (alt && !new RegExp(`\\.tl-sqz:not\\(\\.to-bird\\) \\.tl-band > \\.${alt}\\b`).test(hide)) bad('잔상이 이설 조명을 숨기지 않음 (조감으로 가는 잔상만 칸과 함께 옅어져야)');
    if (/\n\.tl-sqz \.tl-band \{[^}]*mask-image: none/.test(csrc) || !/\n\.tl-sqz \.tl-band:not\(\.has-lit\) \{ -webkit-mask-image: none !important; mask-image: none !important; \}/.test(csrc)) bad('잔상이 흐린 띠의 조명 구간(has-lit)의 가림 판까지 벗김 — 흐린 칸이 온 밝기로 번쩍 떠오름');
    if (!/const keep = wasBird \? '\.tl-zone, \.tl-spot, \.tl-spots' : '\.tl-zone, \.tl-spot, \.tl-spots, \.tl-altspot';/.test(tsrc) || !/this\._squashIn\(res\.born, sq\.g, !!sq\.bird\)/.test(tsrc)) bad('새 띠의 조명 틀 · 이설 조명이 흐름 뒤에 0에서 다시 떠오름 (_squashIn의 제외 목록)');
    /* ② */
    if (!/if \(this\.showAlt && !bird\) \{ \/\/ 조감에서는 다른 견해 고리 없음/.test(tsrc)) bad('화면의 시대 띠 이설 고리가 조감에서도 그려짐');
    if (!/if \(this\.showAlt && !bird\)\s*for \(const a of HT\.datedAlts\(p\)\)/.test(tsrc.slice(tsrc.indexOf('    toSVG({')))) bad('그림 내보내기가 조감에서도 시대 띠의 이설 고리를 그림 (화면은 그리지 않음 — 14px 띠 밖으로 나감)');
    if (!/_altSpotsHTML\(p, tr, own, X, ox, iw, gr, BW[^)]*\) \{\s*if \(!this\.showAlt \|\| this\._bird \|\| !own\.length\) return '';/.test(tsrc)) bad('조감에서도 이설 조명을 그림');
    if ((tsrc.match(/this\._altPlan\(null, (erow|crow), \{ X, lo: -Infinity, hi: Infinity, h, now: null, alt: this\.showAlt \}\)/g) || []).length !== 2) bad("맨 위 날짜 칸(연호 · 도읍)의 유령선이 조감에서 꺼짐 (날짜 칸은 조감에서도 크기가 그대로 — '이설' 체크만 봐야)");
    /* ③ */
    if (!/const ends = d\.from \? ` data-from="\$\{esc\(d\.from\)\}" data-to="\$\{esc\(d\.to\)\}"` : '';/.test(tsrc) || (tsrc.match(/from: meta\.from, to: meta\.to/g) || []).length < 2) bad('문이 제 승계선의 양 끝(data-from/to)을 모름');
    if (!/querySelectorAll\('\.tl-link, \.tl-door\[data-from\]'\)\.forEach\(el => el\.classList\.toggle\('is-selected'/.test(tsrc) || !/\n\.tl\.is-picked \.tl-door\[data-from\]:not\(\.is-selected, \.is-lit\) \{ opacity: \.14; \}/.test(csrc)) bad('다른 것을 고른 동안 승계선은 옅어지는데 문은 그대로 — 테두리에 선 없는 흰 틈(어두운 화면은 흐린 띠 위의 밝은 조각)');
    if (!/\n\.tl\.is-picked \.tl-marks \.tl-link\.is-lit:not\(\.is-selected, \.is-hot, :hover\) \{ opacity: \.9; \}/.test(csrc) || !/this\._doorHTML\(t\.door, lit\(t\)\) : this\._topLineHTML\(t\.line, lit\(t\)\)/.test(tsrc) || !/put\(p\._row, p, \{ seam: true, line:/.test(tsrc)) bad('흐리지 않는 조명 구간(같은 시기 타국)의 승계 이음매가 고른 동안 .14로 옅어짐 — 그 시기의 띠는 제 조명의 띠와 같은 밝기인데 다리 · 문만 사라짐');
    /* ④ */
    if (!/<span class="tl-bnm\$\{hsc\}\$\{nLit \? ' is-lit' : ''\}" data-k="bn:\$\{esc\(p\.uid\)\}" data-uid="\$\{esc\(p\.uid\)\}"/.test(tsrc)) bad('조감의 띠 안 이름이 흐림(is-dim)을 받지 못함 (data-uid 없음)');
    if (!/\n\.tl\.is-filtered \.tl-bnm\.is-dim:not\(\.is-lit\) \{ opacity: \.25; \}/.test(csrc) || !/\n\.tl\.is-picked \.tl-bnm \{ opacity: \.5; \}/.test(csrc)) bad('조감의 띠 안 이름이 책갈피 탭과 같은 흐림을 따르지 않음');
    /* ⑤ */
    const pillHit = csrc.indexOf(':is(.tl.is-bird .tl-lane > .tl-clu, .tl-sqz.was-bird > .tl-sqz-in > .tl-clu, .tl-clu.is-sm).is-hit:not(:hover, .is-carded) b {');
    const pillBase = csrc.indexOf(':is(.tl.is-bird .tl-lane > .tl-clu, .tl-sqz.was-bird > .tl-sqz-in > .tl-clu, .tl-clu.is-sm) b {');
    if (pillHit < 0 || pillHit < pillBase) bad('조감 · 작은 알약에서 묶음 표시(is-hit)가 알약 규칙(명시도 0,4,1)에 덮여 사라짐');
    else if (/0 0 0 3px/.test(csrc.slice(pillHit, csrc.indexOf('}', pillHit)))) bad('조감 · 작은 알약의 묶음 표시가 바깥 고리(14px 띠 밖으로 나감)');
    if (!/querySelectorAll\('\.is-hit:not\(\[data-cluster\]\)'\)\.forEach\(el => el\.classList\.remove\('is-hit'\)\)/.test(tsrc)) bad('확대로 풀린 같은 자리 사건 더미에 is-hit이 남음 (다른 칸을 고르면 흐려야 할 점이 .45로 밝게 남음)');
    /* ⑥ 기본팩의 승계 이음매 */
    if (model) {
      let seams = 0;
      const over = [];
      for (const p of model.periods) {
        if (p.packId !== 'east-asia-base' || p.endUnknown || p.endRange || p.ongoing || p.endAt) continue;
        for (const e of p.successors || []) {
          const q = e.to;
          if (!q || q.startUnknown || q.startRange || q.startAt || q.start !== p.endY) continue;
          for (const K of ['leader', 'cabinet', 'era', 'capital'])
            HT.cellsOf(p, K).forEach((c, i) => {
              if (!c || c.endAt || c.endYAt || (c.end ?? c.endY ?? p.endY) !== p.endY) return;
              seams++;
              const sp = HT.cellSpan(c, p, `${K}:${i}`);
              if (sp.hi > q.start + 1e-9) over.push(`${p.name} ${c.name} → ${q.name} ${q.start}`);
            });
        }
      }
      if (seams < 5) bad(`기본팩에서 곧바로 이어지는 승계 쌍의 마지막 칸을 거의 찾지 못함 (${seams}개)`);
      if (over.length) bad(`승계 이음매의 경계 해가 앞 나라 마지막 칸에 남음(후대의 첫해를 가짐 — 칸 조명 · 타국 메아리가 1년 겹침): ${over.slice(0, 3).join(' · ')}${over.length > 3 ? ` 외 ${over.length - 3}` : ''}`);
    }
    /* ⑦ */
    const asrc = tsrc.slice(tsrc.indexOf('    _altSpotsHTML('), tsrc.indexOf('    /** 지도자·내각 칸.'));
    if (!/const lineL = dl && a0 >= 0 && clear\(a0\) && \(!own \|\| ghost\(s\.cell, a0\)\);/.test(asrc) || !/const lineR = dr && b0 <= iw && clear\(b0 - 1\) && \(!own \|\| ghost\(s\.cell, b0 - 1\)\);/.test(asrc)) bad('이설 조명의 점선이 유령선을 긋지 않는 폭에서도 · 멸망 네모 · 관문 자리에서도 그어짐');
    if (!/if \(this\._caltAt && u\.key\)/.test(tsrc)) bad('유령선을 그을 때 그 자리를 적어 두지 않음 (이설 조명의 점선이 볼 곳)');
    /* ⑧ */
    if (!/if \(Math\.abs\(cx0 - mid\) > 0\.5\) \{/.test(tsrc) || !/return list\.some\(it => !r\.includes\(it\) && Math\.abs\(it\.x - c\) < half \+ dotR\(it, bird \|\| !!it\.sm\) - 0\.25\);/.test(tsrc)) bad('글자를 비켜 옮긴 알약이 같은 글줄의 이웃 점에 닿는지 보지 않음');
    if (!/else if \(rowCats\) noDot\[p\._row\]\.push\(\[bx - 3, bx \+ memW \+ 3, 1, 0\]\);/.test(tsrc) || !/if \(ln != null && laneOf\(e\) !== ln\) continue;/.test(tsrc)) bad('분류별 글줄의 첫 글줄 점이 소속 단추 밑에 가려짐 (그 글줄의 점은 다른 글줄로 갈 수 없음 — 단추 오른쪽으로)');
  } catch (e) {
    bad(`검사 도중 오류: ${e.message}`);
  }
}
/* ㊷ 결과 사진을 찍던 중 찾은 것(2026-09-20 — 감독이 보기 전 마무리):
   ① 사건 이름을 잃지 않음 — 62ff5c7(승계 이음매 ⑨)의 퇴행: 글줄 둘 이상인 줄의 네모 자리(네모 ± 5px)를 점까지 포함한 이름 전체로 막아, 점이 네모 바로 밑에 붙은 건국 해의 사건
      (6·25 전쟁 · 메이지 유신 · 신해혁명 · 중일 전쟁 · 중화인민공화국 수립 · 한양 천도 · 박당강 전투 …)이 점만 남고 이름을 잃음. ㉞의 글자-네모 간격 검사는 이름이 숨으면 통과했으므로,
      여기서는 가짜 줄(네모가 글자만 비킴 · 글줄 하나인 줄의 네모도 점 쪽에는 문턱 없이 · 연도를 떼면 드는 이름 · 알약을 떼야 드는 이름)과 함께
      기본팩 + 모든 견본을 승계 이음매 해 31곳 × 두 폭 × 세 밀도로 그림 내보내기와 같은 배치에 돌려: 예전 규칙(두 글줄 줄의 네모 자리 없음)으로 붙는 이름은 지금도 붙고
      (예전 자리의 글자가 네모 + 1.5px에 걸치던 것만 빼고) · 붙은 이름의 글자는 네모 + 1.5px에 걸치지 않고(이름 수도 셈 — 숨어서 통과하지 않게) · 기본팩의 일곱 이름이 그 해 보기에 붙음
   ② 조감 띠 안 이름 자리에서는 조명 칠 · 가림 판의 경계가 이름 밖으로(nameSnap — 이름 가운데가 든 토막이 이름 자리를 덮거나, 가운데가 밖이면 모든 토막이 이름 밖에서 끝남)
   ③ 칸 이름표는 조명 경계를 비켜 이름 가운데가 든 쪽으로(litShift) · 비킬 자리가 없으면 칸 전체를 흐린 쪽 밝기로 고르게(lit-flat)
   ④ 상세 창 사건 목록의 날짜 칸이 창 전체에서 한 너비(기간 사건과 한 해 사건의 이름이 같은 자리에서 시작)
   ⑤ 부정된 나라에 닿는 승계선의 문도 선과 함께 옅게(화면 · 그림 내보내기) */
{
  const bad = msg => out.problems.push(`결과 사진 검토: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  try {
    if (!HT.Timeline) vm.runInThisContext(src('js/timeline.js'), { filename: 'js/timeline.js' });
    const TL = HT.Timeline;
    const tsrc = src('js/timeline.js');
    const csrc = src('css/common.css');
    /* ① 가짜 줄 (노드의 글자 폭 = 한 자 7px) */
    const fake = () => Object.assign(Object.create(TL.prototype), { view: { start: 0, end: 1000 }, selected: null, highlight: null, lens: '', _bird: null });
    const ev = (uid, x, extra = {}) => Object.assign({ uid, title: uid, start: x, endY: x, importance: 2, _place: { polityUid: 'A' }, placements: [] }, extra);
    const trOf = lines => ({ id: 't', geos: null, geo: { lines, font: 11.5, lineH: 21, textTop: 0 }, rowCats: null });
    const place = (list, lines, reserved, noDot = [], extra = {}) => fake()._placeRow(list, y => y, 1000, trOf(lines), Object.assign({ bandBounds: new Map([['A', [100, 600]]]), expanded: new Set(), reserved: [reserved], noDot: [noDot], minImp: 1, bird: null }, extra), 0);
    const half = TL.G.sq / 2 + TL.SQ_CLEAR;
    {
      /* 두 글줄 줄: 건국 네모가 띠 시작 9.2px(이음매로 비켜 앉은 자리), 건국 해의 사건 점은 띠 시작 9px — 점이 네모 바로 밑 */
      const lanes = [[], []];
      TL.prototype._sqZones.call({}, { fc: 109.2, ec: 590, showF: true, showE: true }, lanes, null);
      const [it] = place([ev('건국 해', 100)], 2, lanes);
      if (!it || !it.label) bad('글줄 둘 이상인 줄에서 점이 건국 네모 바로 밑인 사건이 이름을 잃음 (네모 자리는 글자만 비켜야 — 점은 두 글줄 사이의 네모와 닿지 않음)');
      else if (!it.ink || it.ink[0] < 109.2 + half - 1e-9) bad(`네모 밑 사건의 글자가 네모 + 1.5px에 걸침 (글자 ${it.ink && it.ink[0].toFixed(1)} · 네모 끝 ${(109.2 + half).toFixed(1)})`);
    }
    {
      /* 연도를 붙이면 앞의 막힌 자리에 닿고, 떼면 드는 이름 → 연도 없이 (둘째 차례) */
      const x = 109;
      const lanes = [[[x + 40, x + 60]], [[x + 40, x + 60]]];
      const [it] = place([ev('가나', 100)], 2, lanes);
      if (!it || !it.label || it.yr !== '') bad(`연도를 떼면 드는 이름이 연도 없이 붙지 않음 (${it ? `label ${it.label} · 연도 '${it.yr}'` : '없음'})`);
      if (!/\}\);\n {6}for \(const f of late\) f\(\);/.test(tsrc)) bad('연도를 뗀 이름 · 좁힌 여백이 모든 사건의 첫째 차례 뒤(둘째 차례)가 아님 — 첫째 차례의 이름 자리를 빼앗을 수 있음');
    }
    {
      /* 접힌 하위 사건 수 알약까지 붙이면 막히고, 알약을 떼면 드는 이름 → 알약 없이 (noCnt) */
      const x = 109;
      const [it] = place([ev('가나', 100, { children: [{}] })], 1, [[[x + 45, x + 60]]]);
      if (!it || !it.label || !it.noCnt) bad(`알약을 떼야 드는 이름이 알약 없이 붙지 않음 (${it ? `label ${it.label} · noCnt ${it.noCnt}` : '없음'})`);
      if (!/!it\.noCnt \? `<i class="cnt">/.test(tsrc)) bad('알약을 뗀 이름(noCnt)도 화면에 알약을 그림');
    }
    {
      /* 글줄 하나인 줄: 점은 네모 둘레 밖(네모 끝 + 8)으로 밀리고 이름은 점 쪽에 문턱(새로 붙는 이름의 4px) 없이 — 예전에는 기억이 없는 이름이 영영 붙지 않았음 */
      const one = [[]];
      const nd = [];
      TL.prototype._sqZones.call({}, { fc: 106.5, ec: 590, showF: true, showE: true }, one, nd);
      const [it] = place([ev('가나', 100)], 1, one, nd, { prevLab: new Map(), newLab: new Map() });
      if (!it || !it.label) bad('글줄 하나인 줄에서 네모 둘레 밖으로 밀린 점의 이름이 새로 붙지 못함 (점 쪽에 이름 문턱 4px)');
      else if (it.solid[0] < 106.5 + half - 1e-9 && it.solid[1] > 106.5 - half) bad('글줄 하나인 줄의 이름이 네모 + 1.5px에 걸침');
    }
    /* 기본팩 + 모든 견본 × 승계 이음매 해 31곳 × 두 폭 × 세 밀도 (그림 내보내기의 배치 — 기억 없는 한 번 그리기) */
    if (model) {
      const make = (density, view, oldRules) => {
        const t = Object.assign(Object.create(TL.prototype), { folded: new Set(), foldedPeoples: new Set(), foldedEras: new Set(), expandedHosts: new Set(), scopesOn: {}, show: Object.assign({}, HT.SHOW_DEFAULTS), density, view, _lod: new Map(), leaderMode: 'auto', birdShape: 'a', birdAuto: false, _bird: null, gutter: 200, depth: 1 });
        t._setScopes(model.scopes || []);
        t._cats = new Map((model.categories && model.categories.length ? model.categories : HT.DEFAULT_CATEGORIES).map((c, i) => [c.id, { name: c.name, color: c.color, i }]));
        t._dynUids = new Set(model.periods.filter(p => p.polityKind === 'dynasty').map(p => p.uid));
        const map = new Map();
        t.tracks = model.tracks.map(x => {
          const tr = Object.assign({}, x, { periods: [], events: [], figures: [] });
          map.set(x.id, tr);
          return tr;
        });
        for (const p of model.periods) if (p.polityKind !== 'dynasty' && map.has(p.track)) map.get(p.track).periods.push(p);
        for (const e of model.events) {
          const places = e.placements && e.placements.length ? e.placements : [{ track: e.track, polityUid: e.polityUid }];
          places.forEach((place, i) => map.has(place.track) && map.get(place.track).events.push(Object.assign({}, e, { _place: place, _sec: i > 0, _pi: i })));
        }
        for (const tr of t.tracks) t._layoutTrack(tr);
        /* 예전 규칙(e52fdb2 — 62ff5c7 전): 글줄 하나인 줄만 네모 자리(점까지 막는 보통 구간), 글줄 둘 이상인 줄은 네모 자리 없음 */
        if (oldRules)
          t._sqZones = (sq, lanes, noDot) => {
            if (!noDot) return;
            for (const [c, on, dir] of [[sq.fc, sq.showF, 1], [sq.ec, sq.showE, -1]]) {
              if (!on) continue;
              for (const res of lanes) res.push([c - half, c + half]);
              noDot.push([c - half, c + half, dir]);
            }
          };
        const got = new Map();
        const res = new Map();
        const orig = t._placeRow;
        t._placeRow = function (list, X, W, tr, ctx, row) {
          const r = orig.apply(this, arguments);
          for (const it of r) if (it.label) got.set(`${tr.id}|${it.e.uid}|${it.e._pi || 0}`, { it, tr: tr.id, row });
          res.set(`${tr.id}|${row}`, ctx.reserved[row] || []);
          return r;
        };
        t.toSVG({ width: 1920 });
        return { got, res };
      };
      const sqHit = (it, zones) => (zones[it.sub] || []).some(([a, b, f]) => (f === 1 ? a < it.ink[1] && it.ink[0] < b : f === 2 ? a < it.solid[1] && it.solid[0] < b : false));
      const years = [918, 1392, 1897, 8, 220, 420, 618, 907, 1127, 1271, 1368, 1636, 1912, 1949, 592, 710, 794, 1185, 1573, 1603, 1868, 1926, 1989, 2019, 1009, 1225, 1400, 1407, 1802, 1945, 1976];
      const lost = [];
      const onSq = [];
      let named = 0;
      const titles = new Map();
      for (const d of [-1, 0, 1])
        for (const y of years)
          for (const span of [60, 200]) {
            const v = { start: y - span / 2, end: y + span / 2 };
            const now = make(d, v, false);
            const old = make(d, v, true);
            named += now.got.size;
            titles.set(`${d}|${v.start}|${v.end}`, new Set([...now.got.values()].map(g => g.it.e.title)));
            for (const [k, g] of now.got) if (sqHit(g.it, now.res.get(`${g.tr}|${g.row}`))) onSq.push(`${g.it.e.title}@${d}|${v.start}~${v.end}`);
            for (const [k, g] of old.got) {
              if (now.got.has(k)) continue;
              if (sqHit(g.it, now.res.get(`${g.tr}|${g.row}`))) continue; // 예전 자리의 글자가 네모 + 1.5px에 걸치던 이름 — 지금 규칙이 막는 것이 맞음
              lost.push(`${g.it.e.title}@${d}|${v.start}~${v.end}`);
            }
          }
      if (named < 2000) bad(`이음매 해 보기에 붙은 사건 이름이 너무 적음 (${named} — 이름이 숨어서 겹침 검사를 통과하지 않는지)`);
      if (lost.length) bad(`예전 규칙(두 글줄 줄의 네모 자리 없음)으로는 네모에 걸치지 않고 붙던 이름을 잃음 ${lost.length}건: ${lost.slice(0, 4).join(' · ')}${lost.length > 4 ? ' …' : ''}`);
      if (onSq.length) bad(`붙은 이름의 글자가 네모 + 1.5px에 걸침 ${onSq.length}건: ${onSq.slice(0, 3).join(' · ')}`);
      /* 결과 사진이 잃었다고 짚은 기본팩의 일곱 이름 (검사를 만든 날의 기본팩 — 사건을 지우거나 이름을 바꾸면 건너뜀) */
      const seven = [['6·25 전쟁', '0|1797|1997'], ['메이지 유신', '0|1838|1898'], ['신해혁명', '0|1797|1997'], ['중일 전쟁', '0|1797|1997'], ['중화인민공화국 수립', '0|1919|1979'], ['한양 천도', '0|1292|1492'], ['박당강 전투', '0|818|1018']];
      const miss = seven.filter(([t, k]) => model.events.some(e => e.title === t && e.packId === 'east-asia-base') && !titles.get(k).has(t));
      if (miss.length) bad(`기본팩의 중요 사건 이름이 그 해 보기에 붙지 않음: ${miss.map(([t, k]) => `${t}(${k})`).join(' · ')}`);
    }
    /* ② 조감 띠 안 이름 자리 × 조명 경계 */
    {
      const snap = HT.Timeline.nameSnap;
      if (!snap) bad('Timeline.nameSnap이 없음');
      else {
        const J = v => JSON.stringify(v);
        if (J(snap([[50, 200]], [40, 90])) !== J([[40, 200]])) bad(`이름 가운데가 든 토막이 이름 자리를 덮지 않음: ${J(snap([[50, 200]], [40, 90]))}`);
        if (J(snap([[70, 200]], [40, 90])) !== J([[90, 200]])) bad(`이름 가운데가 밖이면 토막이 이름 밖에서 시작하지 않음: ${J(snap([[70, 200]], [40, 90]))}`);
        if (J(snap([[10, 60, true], [60, 200, false]], [40, 90])) !== J([[10, 40, true], [40, 200, false]])) bad(`맞닿은 두 토막의 경계가 이름 안에 남음: ${J(snap([[10, 60, true], [60, 200, false]], [40, 90]))}`);
        if (J(snap([[10, 60]], [40, 90])) !== J([[10, 40]])) bad('이름 가운데가 밖이면 토막이 이름 앞에서 끝나지 않음');
      }
      const draw = tsrc.slice(tsrc.indexOf('    _drawTrack(tr, X, W) {'), tsrc.indexOf('    _laneKey(tr, cats, row) {'));
      if (!/spotSegs = nameSnap\(spotSegs, bnBox\);/.test(draw) || !/const litPx = cols => nameSnap\(mergeCols\(/.test(draw) || !/const nm = bnm0;/.test(draw)) bad('조감 띠 안 이름 자리에서 조명 칠 · 가림 판의 경계를 옮기지 않음 (칠 · 판 · 이름이 같은 자리를 봐야)');
    }
    /* ③ 칸 이름표 × 조명 경계 */
    {
      const ls = HT.Timeline.litShift;
      if (!ls) bad('Timeline.litShift가 없음');
      else {
        const mk = (l, r, text, extra = {}) => Object.assign({ l, r, ink: { text, size: 11.5, wt: 600 }, bl: 1, br: 1 }, extra);
        const P = () => ({ shift: new Map(), lines: [] });
        const w = 21; // 세 글자 (노드의 글자 폭)
        let pl = ls([mk(0, 200, '가나다')], P(), [100]);
        let c = 100 + (pl.shift.get(0) || 0);
        if (!(c - w / 2 >= 100 + 4 - 1e-9)) bad(`경계가 이름 가운데에 있을 때 이름이 경계 오른쪽(가운데가 든 쪽)으로 비키지 않음 (가운데 ${c})`);
        pl = ls([mk(0, 200, '가나다')], P(), [105]);
        c = 100 + (pl.shift.get(0) || 0);
        if (!(c + w / 2 <= 105 - 4 + 1e-9) || c > 100) bad(`이름 가운데가 경계 왼쪽이면 왼쪽으로 비키지 않음 (가운데 ${c})`);
        pl = ls([mk(0, 200, '가나다')], P(), [30]);
        if (pl.shift.get(0)) bad('경계가 이름에서 먼 칸의 이름을 옮김');
        pl = ls([mk(0, 30, '가나다')], P(), [15]);
        if (!pl.litDim || !pl.litDim.has(0)) bad('비킬 자리가 없는 칸 이름이 흐린 쪽 밝기로 고르게(litDim)가 되지 않음');
        pl = ls([mk(0, 200, '가나다', { fixed: true })], P(), [100]);
        if (!pl.litDim || !pl.litDim.has(0) || pl.shift.get(0)) bad('칸을 채운 이름(앞글자 …)이 옮겨지거나 흐린 쪽으로 고르게 되지 않음');
        pl = ls([mk(0, 200, '가나다', { fixed: true, litL: 40 })], P(), [110]); // 이름 가운데 = 딱지 끝(40)과 칸 안쪽 끝(199) 사이의 가운데 119.5
        c = 119.5 + (pl.shift.get(0) || 0);
        if (!pl.shift.get(0) || c - w / 2 < 110 + 4 - 1e-9) bad(`딱지가 붙은 시기 이름이 딱지 뒤의 자리 안에서 비키지 않음 (가운데 ${c})`);
        pl = ls([mk(0, 200, '가나다')], { shift: new Map(), lines: [{ x: 118, owner: 0 }] }, [100]);
        c = 100 + (pl.shift.get(0) || 0);
        if (Math.abs(c - 118) < w / 2 + 3) bad('조명 경계를 비킨 이름이 유령선에 닿음');
      }
      const lc = TL.prototype._litCls.call({ _litCols: [[50, 150]] }, 0, 100, true);
      if (lc.cls !== ' lit-flat' || !/calc\(var\(--bo\) \* var\(--lp-o, 1\) \/ var\(--la\)\)/.test(lc.css)) bad(`비킬 자리가 없는 칸의 판(lit-flat)이 조명 구간 안을 흐린 쪽 밝기로 되돌리지 않음: ${lc.cls} ${lc.css}`);
      if (!/\.tl \.tl-band\.has-lit :is\(\.tl-cell, \.tl-dep, \.tl-dyn\)\.lit-flat \{ --bo: inherit; --la: inherit; -webkit-mask-image: var\(--lf\); mask-image: var\(--lf\); \}/.test(csrc)) bad('lit-flat 칸이 띠의 --bo · --la를 물려받아 판(--lf)을 쓰지 않음');
      if (!/litEdges: p \? this\._litEdges : null,/.test(tsrc) || !/const lit = o\.litEdges \? litShift\(row, \{ lines, shift \}, o\.litEdges\) : null;/.test(tsrc) || !/this\._litEdges = edgeXs\.length/.test(tsrc) || (tsrc.match(/this\._litCls\(l, w, plan\.litDim && plan\.litDim\.has\(/g) || []).length < 3) bad('칸 줄의 계획(_altPlan)이 조명 경계를 보지 않거나 칸 그리기가 litDim을 쓰지 않음');
    }
    /* ④ 상세 창 날짜 칸 */
    {
      const vsrc = src('js/viewer.js');
      const vcss = src('css/viewer.css');
      if (!/const alignYearCols = \(\) => \{/.test(vsrc) || !/new MutationObserver\(alignYearCols\)\.observe\(detailEl, \{ childList: true, subtree: true/.test(vsrc) || !/set\('--yw', widest\('\.year-events \.y'\)\)/.test(vsrc)) bad('상세 창 사건 목록의 날짜 칸을 창 전체에서 한 너비로 맞추지 않음 (alignYearCols)');
      if (!/set\('--sw', widest\('\.succ-list button > small'\)\)/.test(vsrc) || !/set\('--bw', widest\('\.succ-list button > b:first-child'\)\)/.test(vsrc) || !/\.succ-list button > small \{[^}]*min-width: min\(var\(--sw, 0px\), 45%\);/.test(vcss)) bad('승계 · 소속 목록의 기간 칸 · 배지 폭을 창 전체에서 맞추지 않음 (감독 건의 2026-10-14 6번 — --sw · --bw)');
      if (!/\.year-events \.y \{[^}]*min-width: min\(var\(--yw, 74px\), 45%\);/.test(vcss)) bad('날짜 칸의 너비가 --yw(창에서 가장 넓은 날짜)를 따르지 않음');
    }
    /* ⑤ 부정된 나라의 문 */
    {
      const d = TL.prototype._doorHTML.call({}, { x: 0, y: 0, w: 2, h: 4, from: 'a', to: 'b', ref: ' is-refuted' });
      if (!/class="tl-door is-refuted"/.test(d)) bad(`부정된 나라에 닿는 선의 문에 is-refuted가 없음: ${d}`);
      if (!/^\.tl-door\.is-refuted:not\(\.is-hot, \.is-selected\) \{ opacity: \.2; \}/m.test(csrc)) bad('부정된 나라에 닿는 선의 문이 선과 함께 옅어지지 않음 (.2)');
      if (!/ref: meta\.ref \}, piece\.door\)/.test(tsrc) || !/from: meta\.from, to: meta\.to, ref: meta\.ref \}, d\)/.test(tsrc)) bad('관문 · 다리의 문이 선의 부정 표시(ref)를 받지 않음');
      if (!/t\.door\.ref \? ' opacity="0\.2"' : ''/.test(tsrc)) bad('그림 내보내기에서 부정된 나라의 문이 옅어지지 않음');
      if (!/:is\(\.tl-link, \.tl-door\)\[data-from=/.test(tsrc)) bad('정권에 올릴 때 그 선의 문도 짙어지지 않음 (is-hot)');
    }
  } catch (e) {
    bad(`검사 도중 오류: ${e.stack ? e.stack.split('\n').slice(0, 2).join(' | ') : e}`);
  }
}
/* ㊸ 부분 승계 · 합류(2026-09-20 감독 결정 — 건의 5의 답 '2, 모두': 합류(흡수) 선은 모든 승계 종류에. 선 모양은 처음에 안 2(늘 세 가닥 · 정도만큼 진하게)였다가
   2026-10-13 감독 결정 'A 한 줄 · 짙기 80%'로(처음 35%는 너무 안 보였음) — 가는 실선 하나, 정도는 선에 그리지 않고 풍선 · 상세 창의 글로만):
   ① 자료 형식: type 'partial'(한국어 '부분' · '부분 승계' · 옛 '부분 계승') · degree 1~3(한국어 약 · 중 · 강 · 없으면 중) · parts 다섯(한국어 · 겹침 제거 · 늘 같은 차례) ·
      다른 종류에 적은 정도 · 이어진 것은 버림 · 한 쌍에는 선 하나(같은 선대를 두 번 적으면 첫 줄만 + 알림) · 왕복(읽기 → 내보내기 → 읽기) · 형식 버전 2 · 모델의 선(edge)에 정도 · 이어진 것이 실림
   ② 줄 차지 순서(chainRows): 한 선대의 줄을 다투면 직접 > 부흥 · 간접 > 부분
   ③ 선의 기하(SUCC_KINDS.partial · thinOf · joinPiece): 가는 실선 하나 — 굵기는 밀도의 가는 선 값(보통 1px · 픽셀 칸 가운데, 조감 .8 · .6) · 짙기 .8 ·
      문은 다른 승계와 같은 높이 · 다리 · 관문은 한 획 · 세로 통로도 다른 승계와 같은 한 칸 · 합류 조각은 종류와 상관없이 같은 크기로 테두리 밖으로 나가지 않음
   ④ 합류(흡수 — 모든 승계 종류): HT.succAbsorbs · _linkPlan이 선을 후대의 건국 네모로 보내지 않고 그해의 테두리에 닿게 하고 합류 조각을 둠 · 후대의 책갈피 탭 밖으로 비킴 ·
      흡수가 아닌 쌍은 예전처럼 건국 네모로
   ⑤ 글: 상세 창의 배지 · 이어진 것 · 'n년 합류' · 범례 · 메이커 줄(정도 · 이어진 것 단추) · 패치 표시 · 문서(DLC-형식 · README · 용어집) */
{
  const bad = msg => out.problems.push(`부분 승계: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const near = (a, b, e = 1e-6) => Math.abs(a - b) <= e;
  const step = (tag, fn) => {
    try {
      fn();
    } catch (e) {
      bad(`${tag} 검사 도중 오류: ${e.message}`);
    }
  };
  step('자료 형식', () => {
    /* ① 자료 형식 */
    const one = (x, warns) => HT.normalizeSucc(x, m => warns && warns.push(m));
    if (JSON.stringify(one({ from: '가', type: '부분 승계' })) !== JSON.stringify({ from: '가', type: 'partial', degree: 2 })) bad(`한국어 '부분 승계'와 정도의 기본값(중)을 읽지 못함: ${JSON.stringify(one({ from: '가', type: '부분 승계' }))}`);
    if (one({ from: '가', type: '부분', degree: '강' }).degree !== 3 || one({ from: '가', type: '부분 계승', degree: 1 }).degree !== 1) bad('정도의 한국어(강) · 숫자를 읽지 못함');
    const parts = one({ from: '가', type: 'partial', parts: ['문화', 'people', '지배층', '백성'] }).parts;
    if (JSON.stringify(parts) !== JSON.stringify(['elite', 'people', 'culture'])) bad(`이어진 것의 한국어 · 겹침 · 차례 정리가 어긋남: ${JSON.stringify(parts)}`);
    if ('degree' in one({ from: '가', type: 'direct', degree: 3, parts: ['elite'] })) bad('부분 승계가 아닌 줄에 정도 · 이어진 것이 남음');
    const w1 = [];
    one({ from: '가', type: 'partial', degree: '아주 강함', parts: ['군대'] }, w1);
    if (w1.length !== 2) bad(`읽지 못한 정도 · 이어진 것에 알림이 없음 (${w1.length}건)`);
    const pack = {
      format: 'history-timeline-dlc',
      formatVersion: 1,
      id: 'smoke-partial',
      name: 'x',
      tracks: [{ id: 't', name: 't' }],
      periods: [
        { track: 't', name: '가', start: 1, end: 5 },
        { track: 't', name: '나', start: 5, end: 9, succeeds: [{ from: '가', type: '부분', degree: '약', parts: ['제도'] }, { from: '가', type: 'direct' }] },
      ],
    };
    const r = HT.normalizePack(JSON.parse(JSON.stringify(pack)));
    const succ = r.pack && r.pack.periods[1].succeeds;
    if (!succ || succ.length !== 1 || succ[0].type !== 'partial' || succ[0].degree !== 1 || !r.warnings.some(w => /두 번 적혀/.test(w.msg))) bad(`한 쌍에 선 하나(같은 선대를 두 번 적으면 첫 줄 + 알림)가 아님: ${JSON.stringify(succ)}`);
    const json = HT.packToJSON(r.pack);
    const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (json.formatVersion !== 2) bad('부분 승계를 쓴 파일이 형식 버전 2로 나가지 않음');
    if (!back.pack || JSON.stringify(HT.packToJSON(back.pack)) !== JSON.stringify(json)) bad('부분 승계의 왕복(읽기 → 내보내기 → 읽기)에서 자료가 달라짐');
    const m2 = r.pack && HT.buildModel([r.pack], null);
    const e2 = m2 && (m2.periods.find(p => p.name === '나').predecessors || [])[0];
    if (!e2 || e2.type !== 'partial' || e2.degree !== 1 || JSON.stringify(e2.parts) !== JSON.stringify(['institutions'])) bad(`모델의 승계선에 정도 · 이어진 것이 실리지 않음: ${JSON.stringify(e2 && { t: e2.type, d: e2.degree, p: e2.parts })}`);
    if (HT.successionLabel({ type: 'partial', degree: 2, parts: ['elite', 'people'] }) !== '부분 승계 · 정도 중 · 지배층 · 백성' || HT.successionLabel({ type: 'direct' }) !== '직접 승계') bad('승계 한 건의 글(HT.successionLabel)이 어긋남');
    /* 옛 견본(부분 승계를 쓰지 않은 파일)은 이 단계로 한 글자도 바뀌지 않아야 — 위의 견본 해시가 그 몫 */
    const plain = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 1, id: 'smoke-plain', name: 'x', tracks: [{ id: 't', name: 't' }], periods: [{ track: 't', name: '가', start: 1, end: 5 }, { track: 't', name: '나', start: 5, end: 9, succeeds: ['가'] }] });
    if (!plain.pack || JSON.stringify(plain.pack.periods[1].succeeds) !== JSON.stringify([{ from: '가', type: 'indirect' }]) || HT.packToJSON(plain.pack).formatVersion !== 1) bad('부분 승계를 쓰지 않은 파일의 승계 줄 · 형식 버전이 달라짐');
  });
  step('줄 · 그림', () => {
    /* ② 줄 차지 순서 */
    const TL2 = HT.Timeline || {};
    if (!TL2.chainRows || !TL2.thinOf || !TL2.joinPiece) bad('Timeline에 부분 승계 도우미(chainRows · thinOf · joinPiece)가 없음');
    else {
      const P = (name, start, endY, pre = [], extra = {}) => Object.assign({ name, uid: name, start, endY, predecessors: pre }, extra);
      const names = rows => rows.map(r => r.map(x => x.name).join('→')).join(' | ');
      for (const [other, tag] of [['direct', '직접'], ['revival', '부흥'], ['indirect', '간접']]) {
        const q = P('앞', 0, 100);
        const a = P('긴 부분', 100, 400, [{ from: q, type: 'partial', degree: 3 }]);
        const b = P('짧은 그것', 100, 150, [{ from: q, type: other }]);
        const got = names(TL2.chainRows([q, a, b]));
        if (got !== '앞→짧은 그것 | 긴 부분') bad(`한 선대의 줄을 다툴 때 ${tag} 승계가 부분 승계보다 먼저가 아님: ${got}`);
      }
      /* 부분끼리는 예전처럼 byStart 차례(긴 나라가 먼저) */
      const q2 = P('앞2', 0, 100);
      const a2 = P('긴 부분2', 100, 400, [{ from: q2, type: 'partial' }]);
      const b2 = P('짧은 부분2', 100, 150, [{ from: q2, type: 'partial' }]);
      if (!names(TL2.chainRows([q2, a2, b2])).startsWith('앞2→긴 부분2')) bad('부분끼리는 byStart 차례(긴 나라)가 아님');
      /* ③ 선의 기하 */
      const { thinOf, SUCC_KINDS, G, BIRD, joinPiece } = TL2; // joinPiece는 종류를 받지 않음(늘 같은 크기)
      const thin = thinOf(SUCC_KINDS.partial, G.thin);
      if (!thin || thin.w !== 1 || !thin.crisp || thinOf(SUCC_KINDS.direct, G.thin) || thinOf(SUCC_KINDS.indirect, G.thin) || thinOf(SUCC_KINDS.revival, G.thin)) bad(`부분 승계만 가는 선(보통 밀도 1px · 픽셀 칸 맞춤)이 아님: ${JSON.stringify(thin)}`);
      if (TL2.PARTIAL !== 0.8) bad(`부분 승계의 짙기가 .8이 아님: ${TL2.PARTIAL}`);
      for (const [k, b] of Object.entries(BIRD)) if (!b.thin || !(b.thin.w >= 0.5 && b.thin.w < 1) || b.thin.crisp) bad(`조감 ${k}: 가는 선 값(thin)이 없거나 1px 아래의 가는 선이 아님`);
      /* 다리 · 관문: 한 획 · 제 굵기 · 픽셀 칸 가운데 · 문은 다른 승계와 같은 높이 — 정도가 달라도 같은 그림 */
      const br = TL2.seamBridge({ qe: 100, pf: 100, xa: 94, xb: 106, y: 20, kind: SUCC_KINDS.partial, sg: G.thin });
      const ys = [...new Set(br.segs.map(s => s.y1))];
      // 1px 선은 픽셀 칸 가운데(.5)에 — y 20이면 20.5 (두 칸에 번지지 않게)
      if (ys.length !== 1 || !near(ys[0], 20.5) || br.segs.length !== 2 || br.segs.some(s => s.w !== 1) || !near(br.doors[0].h, G.door)) bad(`부분 승계의 다리가 가는 한 획 · 문 ${G.door}px가 아님: ${JSON.stringify({ ys, n: br.segs.length, h: br.doors[0].h })}`);
      const gp = TL2.gatePiece({ a: 90.5, b: 100.5, at: 20, vertical: false, border: [99, 100], kind: SUCC_KINDS.partial, sg: G.thin });
      if (gp.segs.length !== 1 || gp.segs[0].w !== 1 || !near(gp.segs[0].y1, 20.5) || !near(gp.door.h, G.door)) bad(`부분 승계의 관문이 가는 한 획이 아님: ${JSON.stringify(gp.segs)}`);
      const gb = TL2.gatePiece({ a: 90.5, b: 100.5, at: 20, vertical: true, border: [99, 100], kind: SUCC_KINDS.partial, dh: BIRD.c.door, sg: BIRD.c.thin });
      if (gb.segs.length !== 1 || gb.segs[0].w !== BIRD.c.thin.w || !near(gb.segs[0].x1, 20) || !near(gb.door.w, BIRD.c.door)) bad(`조감의 부분 승계 관문이 그 밀도의 가는 선 · 문이 아님: ${JSON.stringify(gb)}`);
      /* 합류 조각: 테두리 위 — 바깥 변에서 안쪽으로만 (밖으로 나가지 않음), 폭은 승계선 굵기 1.6 + 양쪽 1.5px(종류와 상관없이 같은 크기) */
      const jd = joinPiece({ x: 50, edgeY: 200, dir: 1 });
      const ju = joinPiece({ x: 50, edgeY: 200, dir: -1 });
      if (!near(jd.y, 200) || jd.h > G.bw + 1 || !near(jd.x + jd.w / 2, 50) || !near(jd.w, 1.6 + 3)) bad(`합류 조각(아래로)이 테두리 위 · 선 굵기 + 여백이 아님: ${JSON.stringify(jd)}`);
      if (!near(ju.y + ju.h, 200) || !near(ju.w, jd.w)) bad(`합류 조각(위로)이 테두리 안쪽으로 붙지 않음: ${JSON.stringify(ju)}`);
      /* ④ 합류(흡수) — 가짜 트랙에서 _linkPlan */
      const TLp = HT.Timeline.prototype;
      const X = y => y * 2;
      const plan = (list, rowOf, W = 3000, tweak = null) => {
        for (const p of list) p._seamL = p._seamR = null;
        TL2.chainRows(list.slice());
        const n = Math.max(...list.map(rowOf)) + 1;
        const rowPeriods = Array.from({ length: n }, () => []);
        for (const p of list) rowPeriods[(p._row = rowOf(p))].push(p);
        const tr = { id: 't', periods: list, rows: n, rowTop: Array.from({ length: n }, (_, i) => 12 + i * 40), rowHs: Array(n).fill(29), rowGap: Array(n).fill(11), geo: { lines: 1, textTop: 4, lineH: 21 }, geos: null, hiddenRows: new Set(), foldedRows: new Set(), commonRow: -1, scopeBranches: [], rowPeriods, eventsByRow: [] };
        if (tweak) tweak(tr);
        return { tr, pl: TLp._linkPlan.call(Object.assign(Object.create(TLp), { show: { succession: 'all', partOf: false }, W }), tr, X, W) };
      };
      const T = (name, start, endY, pre = [], extra = {}) => P(name, start, endY, pre, Object.assign({ track: 't', color: '#bba395' }, extra));
      if (!HT.succAbsorbs(T('q', 0, 100), T('p', 50, 200)) || HT.succAbsorbs(T('q', 0, 100), T('p', 100, 200)) || HT.succAbsorbs(T('q', 0, 100), T('p', 50, 90))) bad('흡수(합류)의 조건(후대가 선대의 끝보다 먼저 있었고 끝난 뒤에도 이어짐)이 어긋남');
      for (const type of ['direct', 'indirect', 'revival', 'partial']) {
        const q = T('앞', 0, 100);
        const p = T('이미 있던 나라', 50, 200, [{ from: q, type, degree: 2 }]);
        const { tr, pl } = plan([q, p], x => (x === q ? 0 : 1));
        const link = pl.back.find(b => b.k === 'link');
        const join = pl.top.find(t => t.line && t.line.join);
        const sq = TLp._squares.call({ W: Infinity }, q, X, 1);
        const sp = TLp._squares.call({ W: Infinity }, p, X, 1);
        const yJ = tr.rowTop[1];
        if (!link || link.pts.length !== 2 || !near(link.pts[0][0], sq.ec) || !near(link.pts[1][0], sq.ec) || !near(link.pts[1][1], yJ)) bad(`${type}: 합류 선이 멸망 네모 밑에서 곧게 그해의 후대 띠 테두리로 가지 않음: ${link ? JSON.stringify(link.pts) : '선 없음'}`);
        if (link && link.pts.some(pt => near(pt[0], sp.fc - G.sq / 2 - 1))) bad(`${type}: 합류 선이 후대의 건국 네모로 거꾸로 감`);
        if (!join || join.row !== 1 || join.uid !== p.uid || !near(join.line.join.y, yJ) || join.line.join.h > G.bw + 1) bad(`${type}: 합류 조각이 후대 띠 테두리 위에 없음: ${join ? JSON.stringify(join.line.join) : '조각 없음'}`);
        if (!pl.top.some(t => t.door && t.uid === q.uid)) bad(`${type}: 합류 선이 선대 띠를 지나는 자리에 문이 없음`);
        if (!pl.zones.some(z => z.row === 0)) bad(`${type}: 합류 내림줄 자리를 사건 글자가 비켜 가지 않음(zones)`);
      }
      /* 선대 줄에 기관 칸 단이 있어도 그 칸이 멸망 네모 자리(± 10px)에 없으면 내림줄로 합류하고, 있으면 내림줄 없이 띠 밖 통로로 — _lowerBusy
         (예전에는 그 줄에 단이 있기만 하면 막아 이미 있던 나라로 합류하지 못하고 시작점으로 되돌아갔음 · 2026-09-22 감독 '부분 승계도 간접 승계처럼 중간 합류') */
      for (const [organEnd, drop] of [[40, true], [100, false]]) {
        const q = T('앞', 0, 100);
        const p = T('이미 있던 나라', 50, 200, [{ from: q, type: 'partial', degree: 2 }]);
        const organ = T('기관', 0, organEnd, [], { hosts: [{ host: q, start: 0, end: organEnd }] });
        const { pl } = plan([q, p], x => (x === q ? 0 : 1), 3000, tr => {
          tr.geos = [Object.assign({}, tr.geo, { organTop: 20, organH: 15 }), tr.geo];
          tr.overlays = [organ];
        });
        const link = pl.back.find(b => b.k === 'link');
        const sq = TLp._squares.call({ W: Infinity }, q, X, 1);
        const straight = !!link && link.pts.length === 2 && near(link.pts[0][0], sq.ec);
        if (straight !== drop) bad(`기관 칸이 ${organEnd}년까지인 선대(멸망 100년)의 합류 선이 ${drop ? '멸망 네모 밑에서 곧게 내려가지 않음' : '칸을 가로질러 내려감'}: ${link ? JSON.stringify(link.pts) : '선 없음'}`);
        if (!pl.top.some(t => t.line && t.line.join)) bad(`기관 칸이 ${organEnd}년까지인 선대에서 합류 조각이 없음`);
      }
      /* 후대의 책갈피 탭 위에는 닿지 않고 탭 너머 띠 밖 통로로 */
      {
        const q = T('앞', 0, 100);
        const p = T('탭이 긴 나라', 50, 200, [{ from: q, type: 'partial', degree: 2 }], { _tabR: 199 });
        const { pl } = plan([q, p], x => (x === q ? 0 : 1));
        const join = pl.top.find(t => t.line && t.line.join);
        if (!join || join.line.join.x < 199 + 3) bad(`합류 조각이 후대의 책갈피 탭(${199}px) 위에 놓임: ${join ? join.line.join.x : '조각 없음'}`);
      }
      /* 흡수가 아닌 쌍(후대가 선대 뒤에 섬)은 예전처럼 건국 네모로 */
      {
        const q = T('앞', 0, 100);
        const p = T('뒤', 140, 200, [{ from: q, type: 'partial', degree: 2 }]);
        const { pl } = plan([q, p], x => (x === q ? 0 : 1));
        const link = pl.back.find(b => b.k === 'link');
        const sp = TLp._squares.call({ W: Infinity }, p, X, 1);
        if (!link || !near(link.pts[link.pts.length - 1][0], sp.fc - G.sq / 2 - 1)) bad('흡수가 아닌 쌍의 승계선이 건국 네모에 닿지 않음');
        if (pl.top.some(t => t.line && t.line.join)) bad('흡수가 아닌 쌍에 합류 조각이 생김');
      }
      /* 세로 통로의 간격: 부분 승계도 다른 승계와 같은 자리 · 한 칸(5px) — 예전의 세 가닥은 폭이 넓어 1.6칸을 썼음 */
      {
        const chan = type => {
          const q = T('앞', 0, 100);
          const a = T('뒤 하나', 160, 300, [{ from: q, type }]);
          const b = T('뒤 둘', 160, 300, [{ from: q, type }]);
          const { pl } = plan([q, a, b], x => (x === q ? 0 : x === a ? 1 : 2));
          return pl.back.filter(l => l.k === 'link' && l.pts.length === 4).map(l => l.pts[1][0]).sort((u, v) => u - v);
        };
        const cp = chan('partial');
        const cd = chan('direct');
        if (cp.length !== 2 || !near(cp[1] - cp[0], 5) || JSON.stringify(cp) !== JSON.stringify(cd)) bad(`부분 승계의 세로 통로가 다른 승계와 같은 자리(한 칸 5px)가 아님: ${JSON.stringify({ cp, cd })}`);
      }
    }
  });
  step('글', () => {
    /* ⑤ 글 */
    const vsrc = src('js/viewer.js');
    const csrc2 = src('css/viewer.css');
    const core = src('js/core.js');
    if (!/class="succ-partial"[^>]*>부분<\/b>/.test(vsrc) || !/`정도 \$\{HT\.succDegreeName\(edge\.degree\)\}`/.test(vsrc) || /succ-deg/.test(vsrc) || !/succ-parts/.test(vsrc) || !/HT\.succAbsorbs\(edge\.from, edge\.to\)/.test(vsrc) || !/합류/.test(vsrc)) bad('상세 창의 승계 목록에 부분 배지 · 정도 글 · 이어진 것 · n년 합류가 없음(또는 옛 세 줄 기호가 남음)');
    if (/succ-deg/.test(csrc2) || !/\.succ-list \.succ-parts \{[^}]*word-break: keep-all/.test(csrc2)) bad('상세 창 배지에 옛 세 줄 기호가 남았거나 이어진 것의 글 꺾임 규칙이 없음');
    const ccss = src('css/common.css');
    if (!/\.tl-links \.tl-link\.is-partial:not\([^)]*\) \{ opacity: \.8; \}/.test(ccss) || !/\.tl-marks \.tl-link\.is-partial:not\([^)]*\) \.tl-seg:not\(\.is-join\) \{ opacity: \.8889; \}/.test(ccss) || /tl-strand|is-ghost/.test(ccss)) bad('화면의 부분 승계 짙기(띠 뒤 .8 · 띠 위 .9 × .8889)가 아니거나 옛 가닥 규칙이 남음');
    if (!/HT\.Timeline\.thinSample\(\)/.test(vsrc) || !/HT\.Timeline\.joinSample\(\)/.test(vsrc) || !/seam\('partial'/.test(vsrc)) bad('범례에 부분 승계 · 합류 · 부분 승계 다리 견본이 없음');
    const succRow = HT.succRowHTML ? HT.succRowHTML({ type: 'partial', degree: 3, parts: ['elite'] }) : '';
    if (!/data-sp-deg="1"[^>]*aria-pressed="false"/.test(succRow) || !/data-sp-deg="3"[^>]*aria-pressed="true"/.test(succRow) || !/data-sp-part="elite"[^>]*aria-pressed="true"/.test(succRow) || (succRow.match(/data-sp-part=/g) || []).length !== 5) bad('메이커 승계 줄에 정도 단추 셋 · 이어진 것 단추 다섯이 없음(또는 지금 값이 눌려 있지 않음)');
    if (!/class="s-partial" hidden/.test(HT.succRowHTML({ type: 'direct' }))) bad('부분 승계가 아닌 줄에서 정도 · 이어진 것 단추가 숨지 않음');
    if (!/나라는 끊겼으나 지배층·백성·영역·제도·문화의 일부가 넘어감/.test(core)) bad("승계 종류 설명 '나라는 끊겼으나 …'이 없음");
    if (!/if \(k === 'succeeds' && Array\.isArray\(v\)\)/.test(vsrc)) bad('패치 표시(수정 내역)의 승계 목록이 종류 · 정도를 보여 주지 않음');
    const dlcDoc2 = src('DLC-형식.md');
    if (!/### 부분 승계/.test(dlcDoc2) || !/`degree`/.test(dlcDoc2) || !/`parts`/.test(dlcDoc2) || !/합류\(흡수\) — 모든 승계 종류/.test(dlcDoc2)) bad('DLC-형식.md에 부분 승계(정도 · 이어진 것) · 합류 절이 없음');
    if (!/부분 승계/.test(src('README.md')) || !/합류/.test(src('README.md'))) bad('README에 부분 승계 · 합류 설명이 없음');
    const gloss = src('docs/용어집.md');
    if (!/부분 승계/.test(gloss) || !/합류 조각/.test(gloss)) bad('용어집에 부분 승계 · 합류 조각이 없음');
    /* 견본(sample-lantern)에 부분 승계(정도 약 · 중 · 강, 이어진 것)와 합류(흡수 — 다른 종류의 선)가 있음 */
    const lan = packs.find(p => p.id === 'lantern-chronicle');
    if (!lan) bad('부분 승계 · 합류를 담은 견본(samples/sample-lantern.json)이 없음');
    else {
      const lm = HT.buildModel([lan], null);
      const edges = lm.periods.flatMap(p => (p.predecessors || []).map(e => ({ e, to: p })));
      const part = edges.filter(x => x.e.type === 'partial');
      // 견본 2.0.0: 부분 승계 넷(정도 약 1 · 중 2 · 중 2 — 청림 신관국 → 은가지 자치령 · 강 3), 합류 여섯(둘이 더해짐 — 야광 조개무지 문화 → 산호 섬나라 · 은가지 자치령 → 청림 대공국)
      if (part.map(x => x.e.degree).sort().join() !== '1,2,2,3' || !part.every(x => (x.e.parts || []).length)) bad(`견본의 부분 승계가 정도 셋(1 · 2 · 3)과 이어진 것을 담지 않음: ${part.map(x => `${x.e.from.name}→${x.to.name}:${x.e.degree}`).join(', ')}`);
      if (edges.filter(x => HT.succAbsorbs(x.e.from, x.to)).length !== 6) bad('견본의 합류(흡수) 여섯(빛돌 무덤 문화 → 연맹 · 윗물국 · 갈대 공국 → 아랫물국 · 북설 칸국 → 부흥국 · 야광 조개무지 문화 → 산호 섬나라 · 은가지 자치령 → 청림 대공국)이 잡히지 않음');
    }
  });
}

/* [44] 이전 팩 ZIP의 보관 검사 (scripts/fixtures/packfile-v1.js — docs/구상-메이커-팩.md 2-1): CRC32 · 쓰기/읽기 왕복(deflate · store) · 노드 zlib와 같은 압축 · 깨진 파일 · 한도 · 윈도우 '압축 폴더'로 만든 zip */
{
  const bad = msg => out.problems.push(`팩 zip: ${msg}`);
  const zlib = await import('node:zlib');
  try {
    load('scripts/fixtures/packfile-v1.js'); // 이전 ZIP 규격의 보관용 검사 — 제품에서는 읽지 않음
  } catch (e) {
    bad(`js/packfile.js를 읽지 못함: ${e.message}`);
  }
  const PF = HT.packFile;
  if (!PF || typeof PF.writeZip !== 'function') bad('HT.packFile.writeZip이 없음');
  else {
    const te = new TextEncoder();
    const td = new TextDecoder();
    if (PF.crc32(te.encode('123456789')) !== 0xcbf43926) bad('CRC32 값이 표준(cbf43926)과 다름');
    const entries = [
      { name: 'pack.json', data: '{"a":1}' },
      { name: 'content/events.json', data: JSON.stringify({ events: Array.from({ length: 200 }, (_, i) => ({ id: `e${i}`, title: '같은 글 '.repeat(5) })) }) },
    ];
    for (const compress of [true, false]) {
      const z = await PF.writeZip(entries, { compress });
      if (!PF.isZip(z)) bad('쓴 파일이 zip(PK)으로 시작하지 않음');
      const m = await PF.readZip(z);
      for (const e of entries) if (!m.has(e.name) || td.decode(m.get(e.name)) !== e.data) bad(`zip 왕복(${compress ? 'deflate' : 'store'})에서 «${e.name}»이 달라짐`);
      if (compress) {
        const dv = new DataView(z.buffer, z.byteOffset, z.byteLength);
        let p = 0;
        let deflated = 0;
        while (dv.getUint32(p, true) === 0x04034b50) {
          const method = dv.getUint16(p + 8, true);
          const csize = dv.getUint32(p + 18, true);
          const nlen = dv.getUint16(p + 26, true);
          const xlen = dv.getUint16(p + 28, true);
          const name = td.decode(z.subarray(p + 30, p + 30 + nlen));
          const body = z.subarray(p + 30 + nlen + xlen, p + 30 + nlen + xlen + csize);
          if (method === 8) {
            deflated++;
            if (zlib.inflateRawSync(body).toString('utf8') !== entries.find(x => x.name === name).data) bad(`노드 zlib로 푼 «${name}»이 다름`);
          }
          p += 30 + nlen + xlen + csize;
        }
        if (!deflated) bad('긴 부분 파일이 deflate로 압축되지 않음');
      }
    }
    const z = await PF.writeZip(entries);
    const expectFail = async (bytes, word, what) => {
      try {
        await PF.readZip(bytes);
        bad(`${what}을(를) 받아들임`);
      } catch (e) {
        if (!e.packError || !String(e.message).includes(word)) bad(`${what}: 알림이 다름 — ${e.message}`);
      }
    };
    await expectFail(z.subarray(0, z.length - 10), '잘렸', '끝이 잘린 zip');
    const flip = z.slice();
    flip[40] ^= 0xff; // pack.json 본문(짧아 압축 없이 들어감)의 한 글자
    await expectFail(flip, '깨졌', '본문이 틀린 zip');
    const locked = z.slice();
    {
      const dv = new DataView(locked.buffer);
      const cd = dv.getUint32(locked.length - 6, true);
      dv.setUint16(cd + 8, dv.getUint16(cd + 8, true) | 1, true);
    }
    await expectFail(locked, '암호', '암호 걸린 zip');
    await expectFail(te.encode('{"format":"x"}'), '압축(zip) 파일이 아닙니다', 'zip이 아닌 글');
    await expectFail(await PF.writeZip([{ name: 'content/events.json', data: new Uint8Array(33 * 1024 * 1024) }]), '너무 큽니다', '32MB를 넘는 부분 파일');
    const win = await PF.readZip(readFileSync(join(root, 'scripts/fixtures/windows-zip.htpack')));
    if (!win.has('pack.json') || !win.has('content/events.json')) bad(`윈도우에서 만든 zip의 파일 이름을 읽지 못함: ${[...win.keys()].join(', ')}`);
  }
}

/* [45] 팩 정보의 새 칸 (docs/구상-메이커-팩.md 2-2): 분류 · 태그 · 짧은 소개 · 볼거리 · 표지 · 관계 · 판 기록 · 만든 날 · 반영한 날 —
   읽기 · 검사 · 쓰기 왕복, requires 바로 뒤, 적은 것만 나감(새 칸이 없는 DLC는 열쇠도 없음 · 형식 1), 새 칸을 쓴 파일은 형식 2, 고친 것 목록 */
{
  const bad = msg => out.problems.push(`팩 정보: ${msg}`);
  const NEW = ['category', 'tags', 'summary', 'highlights', 'cover', 'relations', 'changelog', 'created', 'updated'];
  const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
  const base = { format: HT.FORMAT, id: 'info-test', name: '정보 견본', version: '1.2.0', tracks: [{ id: 'it', name: '견본 땅' }], periods: [{ id: 'p1', track: 'it', name: '가 나라', start: 100, end: 200 }] };
  const full = Object.assign({}, base, {
    category: 'region', tags: ['가', '나'], summary: '짧게', highlights: ['하나', '둘'], cover: PNG,
    relations: [{ type: 'needs', id: 'east-asia-base', name: '동아시아사 기본팩' }, { type: 'after', id: 'other' }],
    changelog: [{ version: '1.2.0', date: '2026-09-20', note: '시대 1 더함' }], created: '2026-09-19', updated: '2026-09-20',
  });
  if (!Array.isArray(HT.PACK_CATEGORIES) || HT.PACK_CATEGORIES.map(c => c.id).join() !== 'expansion,region,nation,theory,world,docs,map') bad('분류 표(HT.PACK_CATEGORIES)가 다름'); // map(지도팩)은 형식 3
  const baseWarn = HT.normalizePack(base).warnings.length; // 새 칸과 상관없는 경고(있다면)는 빼고 셈
  const r = HT.normalizePack(full);
  if (!r.pack || r.warnings.length !== baseWarn) bad(`올바른 새 칸에 경고: ${r.warnings.map(w => w.msg).join(' / ')}`);
  const json = r.pack && HT.packToJSON(r.pack);
  if (json) {
    for (const k of NEW) if (canon(json[k]) !== canon(full[k])) bad(`«${k}»가 왕복에서 달라짐: ${JSON.stringify(json[k])}`);
    if (json.formatVersion !== 2) bad(`새 칸을 쓴 파일이 형식 ${json.formatVersion}로 나감`);
    const keys = Object.keys(json);
    if (keys.indexOf('category') !== keys.indexOf('requires') + 1) bad(`새 칸이 requires 바로 뒤에 오지 않음: ${keys.slice(0, 12).join(',')}`);
  }
  const plain = HT.packToJSON(HT.normalizePack(base).pack);
  for (const k of NEW) if (k in plain) bad(`새 칸을 쓰지 않은 DLC에 «${k}» 열쇠가 생김`);
  if (plain.formatVersion !== 1) bad(`새 칸이 없는 DLC가 형식 ${plain.formatVersion}로 나감`);
  const messy = Object.assign({}, base, {
    category: 'nope', tags: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'x'.repeat(25)], summary: 's'.repeat(130), highlights: Array.from({ length: 12 }, (_, i) => `줄 ${i}`),
    cover: 'data:text/plain;base64,AAAA',
    relations: [{ type: 'recommends', id: 'x' }, { type: 'needs', id: 'info-test' }, { type: 'needs', id: 'bad id!' }, { type: 'needs', id: 'ok' }, { type: 'needs', id: 'ok' }],
    changelog: [{ note: '판 없음' }, { version: '1.0.0', date: '어제' }], created: '2026/09/19',
  });
  const m = HT.normalizePack(messy);
  const mp = m.pack || {};
  if ('category' in mp) bad('모르는 분류를 남김');
  if (!mp.tags || mp.tags.length !== 5 || mp.tags.some(t => t.length > 20)) bad(`태그를 5개 · 20자로 줄이지 않음: ${JSON.stringify(mp.tags)}`);
  if (!mp.summary || mp.summary.length !== 120) bad('짧은 소개를 120자로 자르지 않음');
  if (!mp.highlights || mp.highlights.length !== 10) bad('볼거리를 10줄로 줄이지 않음');
  if ('cover' in mp) bad('그림이 아닌 표지를 남김');
  if (canon(mp.relations) !== canon([{ type: 'needs', id: 'ok' }])) bad(`관계 검사가 다름: ${JSON.stringify(mp.relations)}`);
  if (canon(mp.changelog) !== canon([{ version: '1.0.0' }])) bad(`판 기록 검사가 다름: ${JSON.stringify(mp.changelog)}`);
  if ('created' in mp) bad('읽지 못한 날짜를 남김');
  if (m.warnings.length - baseWarn < 8) bad(`고친 것을 알리지 않음(경고 ${m.warnings.length - baseWarn}개)`);
  const huge = HT.normalizePack(Object.assign({}, base, { cover: `data:image/png;base64,${'A'.repeat(2000004)}` }));
  if ('cover' in huge.pack || !huge.warnings.some(w => /너무 커/.test(w.msg))) bad('너무 큰 표지를 알리지 않거나 남김');
  const edited = HT.normalizePack(Object.assign({}, full, { tags: ['가'], cover: undefined })).pack;
  const ch = HT.draft.changes(edited, r.pack).filter(c => c.list === 'info').map(c => c.key).sort();
  if (canon(ch) !== canon(['cover', 'tags'])) bad(`새 칸의 고침을 세지 않음: ${ch.join(',')}`);
}

/* [46] 이전 ZIP 규격의 .htpack ↔ DLC JSON 보관 검사 (docs/구상-메이커-팩.md 2-1): 기본팩 · 견본 모두 묶었다 풀면 한 글자도 다르지 않음(deflate · store) · 부분 파일 이름 · 표지 그림 파일 ·
   여러 부분 파일을 이름 차례로 합침 · BOM · 맥의 __MACOSX · 가리키는 그림이 없는 표지 · 파일 읽기(내용으로 가림) · 파일 이름 */
{
  const bad = msg => out.problems.push(`.htpack: ${msg}`);
  const PF = HT.packFile;
  const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
  if (!PF || typeof PF.build !== 'function') bad('HT.packFile.build가 없음');
  else {
    const all = packs.map(p => HT.packToJSON(p));
    for (const json of all) {
      for (const compress of [true, false]) {
        const { raw } = await PF.parse(await PF.build(json, { compress }));
        const again = HT.normalizePack(raw);
        if (!again.pack || canon(HT.packToJSON(again.pack)) !== canon(json)) bad(`«${json.id}»을(를) 묶었다 풀면 달라짐 (${compress ? 'deflate' : 'store'})`);
      }
    }
    const kinds = all.find(j => j.id === 'lantern-chronicle'); // 견본 sample-lantern(문서 · 인물 · 시대 구분까지 든 팩)
    const withCover = Object.assign({}, kinds, { cover: PNG, category: 'world' });
    const zb = await PF.build(withCover);
    const files = await PF.readZip(zb);
    const names = [...files.keys()];
    if (canon(names) !== canon(['pack.json', 'content/base.json', 'content/history.json', 'content/events.json', 'content/figures.json', 'content/divisions.json', 'content/documents.json', 'images/cover.png'])) bad(`부분 파일이 다름: ${names.join(', ')}`);
    const head = JSON.parse(new TextDecoder().decode(files.get('pack.json')));
    if (head.cover !== 'images/cover.png' || 'periods' in head || 'documents' in head || head.category !== 'world') bad(`pack.json이 맞지 않음: ${Object.keys(head).join(',')}`);
    if ((await PF.parse(zb)).raw.cover !== PNG) bad('표지 그림이 data URL로 돌아오지 않음');
    const hand = await PF.writeZip([
      { name: 'pack.json', data: JSON.stringify({ format: HT.FORMAT, id: 'hand', name: '손으로 묶음', version: '1.0.0', tracks: [{ id: 'h', name: '에이치' }] }) },
      { name: 'content/events-2.json', data: JSON.stringify({ events: [{ id: 'b', track: 'h', title: '둘', start: 2 }] }) },
      { name: 'content/events-1.json', data: '﻿' + JSON.stringify({ events: [{ id: 'a', track: 'h', title: '하나', start: 1 }] }) },
      { name: 'content/documents.json', data: JSON.stringify({ documents: { a: '문서 하나' } }) },
      { name: '__MACOSX/content/._events-1.json', data: new Uint8Array([0, 5, 22, 7, 0, 2]) },
      { name: 'content/._events-2.json', data: new Uint8Array([0, 5, 22, 7]) },
    ]);
    const h = (await PF.parse(hand)).raw;
    if (canon((h.events || []).map(e => e.id)) !== canon(['a', 'b'])) bad(`부분 파일을 이름 차례로 합치지 않거나 맥의 덧파일을 읽음: ${JSON.stringify((h.events || []).map(e => e.id))}`);
    if (!h.documents || h.documents.a !== '문서 하나') bad('문서 부분 파일을 합치지 않음');
    const lost = await PF.parse(await PF.writeZip([{ name: 'pack.json', data: JSON.stringify({ format: HT.FORMAT, id: 'lost', name: '잃은 표지', cover: 'images/cover.webp' }) }]));
    if ('cover' in lost.raw || !lost.notes.length) bad('가리키는 그림이 없는 표지를 알리지 않거나 남김');
    const noHead = PF.writeZip([{ name: 'content/events.json', data: '{"events":[]}' }]).then(PF.parse);
    await noHead.then(() => bad('pack.json 없는 팩을 받아들임'), e => !e.packError && bad(`pack.json 없는 팩 알림이 다름: ${e.message}`));
    const f1 = await PF.read(new File([zb], '이름만.json'));
    if (f1.kind !== 'htpack' || f1.raw.id !== 'lantern-chronicle') bad('이름이 .json인 팩 파일을 내용으로 가리지 못함');
    const f2 = await PF.read(new File([JSON.stringify(withCover)], '이름만.htpack'));
    if (f2.kind !== 'json' || f2.raw.cover !== PNG) bad('이름이 .htpack인 JSON 파일을 내용으로 가리지 못함');
    try {
      await PF.read(new File(['{나쁜'], 'bad.json'));
      bad('깨진 JSON을 받아들임');
    } catch (e) {
      if (!e.packError || !/JSON/.test(e.message)) bad(`깨진 JSON 알림이 다름: ${e.message}`);
    }
    const w = await PF.parse(readFileSync(join(root, 'scripts/fixtures/windows-zip.htpack')));
    const wp = HT.normalizePack(w.raw);
    if (!wp.pack || wp.pack.events.length !== 1) bad(`윈도우에서 만든 팩(BOM)을 읽지 못함: ${wp.errors.map(e => e.msg).join(' / ')}`);
    if (PF.fileName({ id: 'a-b', version: '1.2.3' }) !== 'a-b-v1.2.3.htpack') bad('팩 파일 이름 꼴이 다름');
    if ((await PF.fitCover(PNG, 960, 540)) !== PNG) bad('캔버스가 없는 곳(노드)에서 표지 줄이기가 그림을 바꿈');
  }
}

/* [47] 불러오는 차례와 관계 상태 (docs/구상-메이커-팩.md 2-4) */
{
  const bad = msg => out.problems.push(`불러오는 차례: ${msg}`);
  const P = (id, rel = [], extra = {}) => Object.assign({ id, name: id.toUpperCase(), relations: rel.map(([type, to]) => ({ type, id: to })) }, extra);
  const ids = l => l.map(p => p.id).join(' ');
  if (typeof HT.orderPacks !== 'function' || typeof HT.packRelationState !== 'function') bad('HT.orderPacks · HT.packRelationState가 없음');
  else {
    const base = P('east-asia-base', [], { builtin: true });
    let o = HT.orderPacks([base, P('a', [['needs', 'c']]), P('b'), P('c')]);
    if (ids(o) !== 'east-asia-base b c a') bad(`needs를 지키지 않음: ${ids(o)}`);
    o = HT.orderPacks([base, P('a', [['after', 'b']]), P('b')]);
    if (ids(o) !== 'east-asia-base b a') bad(`after를 지키지 않음: ${ids(o)}`);
    o = HT.orderPacks([base, P('a'), P('b', [['needs', 'east-asia-base'], ['needs', 'zz']])]);
    if (ids(o) !== 'east-asia-base a b') bad(`기본팩 · 없는 팩을 가리키는 줄에 차례가 흔들림: ${ids(o)}`);
    o = HT.orderPacks([base, P('a', [['after', 'b']]), P('b', [['after', 'a']])]);
    if (ids(o) !== 'east-asia-base a b' || canon(o[1].orderIgnored) !== canon(['b']) || o[2].orderIgnored) bad(`고리를 설치한 차례대로 두지 않음: ${ids(o)} · ${JSON.stringify(o.map(p => p.orderIgnored))}`);
    o = HT.orderPacks([P('east-asia-base', [], { overridesBuiltin: true }), P('a')]);
    if (ids(o) !== 'east-asia-base a') bad('기본팩을 대신한 설치본이 앞에 남지 않음');
    const now = [base, P('t', [['needs', 'east-asia-base'], ['needs', 'gone'], ['conflicts', 'u']], { requires: ['u'] }), P('u'), P('v', [['conflicts', 't']])];
    const on = id => id !== 'east-asia-base';
    const st = HT.packRelationState(now[1], now, on);
    if (canon(st.needs.map(n => n.state)) !== canon(['off', 'missing'])) bad(`필요한 팩 상태가 다름: ${JSON.stringify(st.needs)}`);
    if (canon(st.conflicts.map(c => c.id).sort()) !== canon(['u', 'v'])) bad(`함께 못 씀을 두 쪽 모두에서 보지 않음: ${JSON.stringify(st.conflicts)}`);
    if (canon(st.recommends.map(r => r.state)) !== canon(['on'])) bad('함께 쓰면 좋은 팩(requires) 상태가 다름');
    if (HT.packRelationState(now[2], now, id => id !== 't').conflicts.length) bad('한쪽이 꺼져 있는데 함께 못 씀을 알림');
    const lp = HT.loadPacks();
    if (!lp.length || !lp[0].builtin) bad('HT.loadPacks가 기본팩을 앞에 두지 않음');
  }
}

/* [48] 자동 표지 (docs/구상-메이커-팩.md 2-6): 표지가 없는 팩의 카드 그림 — 시대 막대(겹치지 않게 7줄까지) · 시대가 없으면 줄무늬 · 늘 같은 그림 · 이름 글 이스케이프 */
{
  const bad = msg => out.problems.push(`자동 표지: ${msg}`);
  if (typeof HT.autoCover !== 'function') bad('HT.autoCover가 없음');
  else {
    const kinds = packs.find(p => p.id === 'lantern-chronicle'); // 견본 sample-lantern(시대 21)
    const a = HT.autoCover(kinds);
    if (!/^<svg class="pk-auto"[^>]*viewBox="0 0 320 180"/.test(a)) bad('SVG(pk-auto · 320×180)가 아님');
    const bars = (a.match(/<rect /g) || []).length - 1;
    if (bars < 5 || bars > kinds.periods.length) bad(`시대 막대 수가 이상함: ${bars}`);
    if (a !== HT.autoCover(kinds)) bad('같은 팩인데 그림이 다름');
    const empty = HT.autoCover({ id: 'x', name: '<이름>', periods: [] });
    if ((empty.match(/<rect /g) || []).length !== 6 || !empty.includes('&lt;이름&gt;')) bad('시대가 없는 팩의 줄무늬 · 이름 글 이스케이프가 다름');
    if (/NaN|Infinity|undefined/.test(a + empty)) bad('수가 아닌 값이 그림에 들어감');
  }
}

/* [49] 파일을 바이트로 받기 (팩 파일은 압축이라 글로 읽으면 깨짐): PC 앱의 열기 대화상자는 바이트로 읽고(권한 fs:allow-read-file),
   안드로이드 앱이 넘긴 b64 줄은 바이트 파일로 · text 줄은 지금처럼 */
{
  const bad = msg => out.problems.push(`파일 받기: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  if (!JSON.parse(src('src-tauri/capabilities/default.json')).permissions.includes('fs:allow-read-file')) bad('PC 앱에 파일을 바이트로 읽는 권한(fs:allow-read-file)이 없음');
  const run = ({ mobile, taken = null }) => {
    const calls = [];
    const on = {};
    const w = {
      HT: { toast() {} },
      __TAURI__: {
        dialog: { open: async () => ['C:/팩/가.htpack'] },
        fs: { readFile: async p => (calls.push(`readFile ${p}`), new Uint8Array([0x50, 0x4b, 3, 4, 9])), readTextFile: async () => (calls.push('readTextFile'), '') },
        path: { appDataDir: async () => '/d' },
      },
      matchMedia: () => ({ matches: false }),
      navigator: { userAgent: mobile ? 'Mozilla/5.0 (Linux; Android 15; Pixel 7) Mobile' : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', maxTouchPoints: mobile ? 5 : 0 },
      location: { protocol: 'http:', assign() {} },
      history: { state: null, pushState() {}, back() {} },
      document: { addEventListener() {}, dispatchEvent: e => calls.push({ type: e.type, files: e.detail }), documentElement: { dataset: {} }, body: { appendChild() {} }, createElement: () => ({}) },
      addEventListener: (t, fn) => (on[t] = fn),
      setTimeout: fn => fn(),
      CustomEvent: class {
        constructor(type, o) {
          this.type = type;
          this.detail = o && o.detail;
        }
      },
      File,
      atob,
      Uint8Array,
    };
    if (taken) w.HTAndroid = { takeFiles: () => taken };
    w.window = w;
    vm.createContext(w);
    vm.runInContext(src('js/platform.js'), w, { filename: 'js/platform.js' });
    return { P: w.HT.platform, calls, on };
  };
  try {
    const pc = run({ mobile: false });
    const [f] = await pc.P.openFiles('.htpack', true);
    const bytes = f && new Uint8Array(await f.arrayBuffer());
    if (!f || f.name !== '가.htpack' || bytes.length !== 5 || bytes[0] !== 0x50 || f.type !== 'application/x-htpack') bad(`PC 앱의 열기가 바이트를 그대로 넘기지 않음: ${f && f.name} · ${bytes && bytes.length} · ${f && f.type}`);
    if (pc.calls.includes('readTextFile')) bad('PC 앱의 열기가 아직 글로 읽음');
  } catch (e) {
    bad(`js/platform.js를 앱처럼 읽지 못함: ${e && e.message}`);
  }
}

/* [50] 팩 파일의 배선 (docs/구상-메이커-팩.md 2-5): 두 화면이 js/packfile.js를 platform.js 뒤 · 팩 앞에 읽음 · 서비스 워커 캐시 · PWA 파일 연결(.htpack) ·
   연표의 설치가 팩 파일 읽기를 쓰고 표지를 정규화 전에 줄임 · 설치 칸 · 끌어다 놓기가 .htpack을 받음 · 내보내기가 팩 파일 · 메이커 전용이 아님 */
{
  const bad = msg => out.problems.push(`팩 파일 배선: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const scripts = html => [...html.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<script src="([^"]+)"/g)].map(m => m[1]);
  for (const page of ['index.html', 'dlc-maker.html']) {
    const s = scripts(src(page));
    const at = s.indexOf('js/packfile.js');
    if (at < 0) bad(`${page}이(가) js/packfile.js를 읽지 않음`);
    else if (!(at > s.indexOf('js/platform.js') && at < s.findIndex(x => x.startsWith('packs/')))) bad(`${page}에서 js/packfile.js의 자리가 platform.js 뒤 · 팩 앞이 아님`);
  }
  if (!/'js\/packfile\.js'/.test(src('sw.js'))) bad('서비스 워커 캐시 목록에 js/packfile.js가 없음');
  const fh = (JSON.parse(src('manifest.webmanifest')).file_handlers || []).flatMap(h => Object.values(h.accept || {}).flat());
  if (!fh.includes('.htpack') || fh.includes('.json')) bad(`PWA 파일 연결이 .htpack 전용이 아님: ${fh.join(',')}`);
  if (/MAKER_ONLY = \[[^\]]*packfile/.test(src('scripts/build-web.mjs'))) bad('js/packfile.js가 메이커 전용으로 빠짐 (연표도 씀)');
  const v = src('js/viewer.js');
  const inst = v.slice(v.indexOf('async function installFiles'), v.indexOf('function restoreBackup'));
  if (!/HT\.packFile\.read\(/.test(inst)) bad('연표의 설치가 팩 파일 읽기(HT.packFile.read)를 쓰지 않음');
  if (!(inst.indexOf('fitCover') > 0 && inst.indexOf('fitCover') < inst.indexOf('HT.normalizePack('))) bad('설치할 때 표지를 정규화보다 먼저 줄이지 않음 (큰 표지를 검사가 먼저 버림)');
  if (!/pickFiles\('\.htpack', true\)/.test(v)) bad('설치 칸이 .htpack을 고르지 못함');
  if (!/\\\.htpack\$\/i/.test(v)) bad('끌어다 놓기가 .htpack을 받지 않음');
  if (!/HT\.packFile\.build\(HT\.packToJSON\(/.test(v)) bad('DLC 관리의 내보내기가 팩 파일을 만들지 않음');
  const dlc = v.slice(v.indexOf('/* DLC 관리 (docs/구상-메이커-팩.md 2-5)'), v.indexOf('async function installFiles')); // 카드 · 자세히 · 창 조작까지
  const card = src('js/packfile.js').slice(src('js/packfile.js').indexOf('/* ---------- DLC 카드')); // 카드 틀은 두 화면 공용(HT.packCard — 2단계 과제 5)
  if (!/HT\.autoCover\(/.test(card) || !/HT\.packCard\.html\(/.test(dlc) || !/HT\.packRelationState\(/.test(dlc)) bad('DLC 관리 카드가 자동 표지 · 관계 상태를 쓰지 않음');
  for (const k of ['data-cat', 'data-find', 'data-pick-pack', 'data-toggle', 'data-enable', 'data-export', 'data-remove', 'data-install', 'data-backup']) if (!(dlc + card).includes(k)) bad(`DLC 관리에 ${k}가 없음`);
  if (/placeholder=/.test(dlc)) bad('DLC 관리에 회색 예시 글(placeholder)이 있음');
}

/* [51] 메이커의 열기 · 파일로가 팩 파일 (docs/구상-메이커-팩.md 3-7): 열기와 파일로는 전용 .htpack만, JSON 명령은 없음 ·
   DLC id를 바꾸면 자기를 가리키게 된 관계 줄은 지움 */
{
  const bad = msg => out.problems.push(`메이커 파일: ${msg}`);
  const m = readFileSync(join(root, 'js/maker.js'), 'utf8');
  const open = m.slice(m.indexOf('async function openFile'), m.indexOf('/* ---------- 고르는 창'));
  if (!/HT\.packFile\.read\(/.test(open) || !/pickFiles\('\.htpack'\)/.test(open)) bad('메이커의 열기가 팩 파일을 받지 않음');
  const exp = m.slice(m.indexOf('async function exportFile'), m.indexOf('/* ---------- 셋 가운데 고르기'));
  if (!/HT\.packFile\.build\(HT\.F4\.toFile\(HT\.packToJSON\(/.test(exp) || !/HT\.packFile\.build\(HT\.F4\.legacyFile\(HT\.packToJSON\(/.test(exp) || /function exportJSON/.test(exp)) bad('메이커의 파일로가 전용 팩만 만들지 않음'); // 형식 4 저장(5단계 과제 2) · 옛 형식 내보내기는 옛 열쇠 yearCycle을 채움(과제 6)
  if (/exportJSON|JSON 한 파일로/.test(m)) bad('메이커에 JSON 내보내기 길이 남음');
  if (!/DLC 파일 열기 \(\.htpack\)/.test(readFileSync(join(root, 'js/maker-shell.js'), 'utf8'))) bad('처음 화면의 열기 단추 글이 팩 파일을 말하지 않음'); // 고르는 창 → 처음 화면(2단계 과제 5)
  const d = HT.draft.clean({ format: HT.FORMAT, id: 'old-id', name: '옛', relations: [{ type: 'needs', id: 'new-id' }, { type: 'after', id: 'keep' }] });
  HT.makerKit.renameDlc(d, 'new-id');
  if (canon(d.relations) !== canon([{ type: 'after', id: 'keep' }])) bad(`DLC id를 바꾼 뒤 자기를 가리키는 관계가 남음: ${JSON.stringify(d.relations)}`);
}

/* [52] 모바일 팩 열기는 codex/mobile-port에 따로 보관합니다. PC·웹은 브라우저의 파일 열기로 검사합니다. */

/* [53] 1단계 독립 검토에서 나온 것 (2026-09-19): 겹치는 항목 · 부풀린 크기의 압축 폭탄 · 폴더째 압축한 팩 · 한글 조합 중 찾기(찾기 칸을 다시 그리지 않음) ·
   휴대폰 파일 고르기의 .htpack · 메이커로 연 팩의 큰 표지 · 안드로이드의 아주 큰 파일 · 어두운 모드의 분류 딱지 */
{
  const bad = msg => out.problems.push(`검토 고침: ${msg}`);
  const src = f => readFileSync(join(root, f), 'utf8');
  const PF = HT.packFile;
  const cat = list => {
    const o = new Uint8Array(list.reduce((n, b) => n + b.length, 0));
    let k = 0;
    for (const b of list) {
      o.set(b, k);
      k += b.length;
    }
    return o;
  };
  const expectFail = async (bytes, word, what) => {
    try {
      await PF.readZip(bytes);
      bad(`${what}을(를) 받아들임`);
    } catch (e) {
      if (!e.packError || !String(e.message).includes(word)) bad(`${what}: 알림이 다름 — ${e.message}`);
    }
  };
  // 1) 같은 자리를 두 번 가리키는 목차
  const one = await PF.writeZip([{ name: 'content/events.json', data: new Uint8Array(1024) }], { compress: false });
  {
    const dv = new DataView(one.buffer, one.byteOffset, one.byteLength);
    const eo = one.length - 22;
    const cdSize = dv.getUint32(eo + 12, true);
    const cdOff = dv.getUint32(eo + 16, true);
    const cen = one.subarray(cdOff, cdOff + cdSize);
    const end = new Uint8Array(22);
    const ev = new DataView(end.buffer);
    ev.setUint32(0, 0x06054b50, true);
    ev.setUint16(8, 2, true);
    ev.setUint16(10, 2, true);
    ev.setUint32(12, cdSize * 2, true);
    ev.setUint32(16, cdOff, true);
    await expectFail(cat([one.subarray(0, cdOff), cen, cen, end]), '겹', '같은 자리를 두 번 가리키는 zip');
  }
  // 2) 목차가 적은 풀린 크기의 합이 한도를 넘음 (항목마다는 32MB 안)
  {
    const many = await PF.writeZip(Array.from({ length: 5 }, (_, i) => ({ name: `content/p${i}.json`, data: new Uint8Array(8) })), { compress: false });
    const dv = new DataView(many.buffer, many.byteOffset, many.byteLength);
    const eo = many.length - 22;
    let p = dv.getUint32(eo + 16, true);
    for (let i = 0; i < 5; i++) {
      dv.setUint32(p + 24, 30 * 1024 * 1024, true);
      p += 46 + dv.getUint16(p + 28, true) + dv.getUint16(p + 30, true) + dv.getUint16(p + 32, true);
    }
    await expectFail(many, '너무 큽니다', '풀린 크기의 합이 한도를 넘는 zip');
  }
  // 3) 폴더째 압축한 팩 (윈도우 '압축(ZIP) 폴더' · 맥 Finder)
  {
    const z = await PF.writeZip([
      { name: 'mypack/', data: new Uint8Array(0) },
      { name: 'mypack/pack.json', data: JSON.stringify({ format: HT.FORMAT, id: 'folder-pack', name: '폴더째', version: '1.0.0', tracks: [{ id: 'f', name: '에프' }] }) },
      { name: 'mypack/content/events.json', data: JSON.stringify({ events: [{ id: 'e', track: 'f', title: '하나', start: 3 }] }) },
      { name: '__MACOSX/mypack/._pack.json', data: new Uint8Array([0, 5, 22, 7]) },
    ]);
    try {
      const r = (await PF.parse(z)).raw;
      if (r.id !== 'folder-pack' || !r.events || r.events.length !== 1) bad(`폴더째 압축한 팩을 제대로 읽지 못함: ${JSON.stringify(r).slice(0, 80)}`);
    } catch (e) {
      bad(`폴더째 압축한 팩을 읽지 못함: ${e.message}`);
    }
  }
  // 4) 한글 조합: 찾기 칸에 칠 때 찾기 칸(과 위 칸)은 다시 그리지 않음 — 카드 · 자세히 · 아래 줄만
  {
    const v = src('js/viewer.js');
    const at = v.indexOf("dlcDialog.addEventListener('input'");
    const body = at >= 0 ? v.slice(at, v.indexOf('});', at)) : '';
    if (!body || /renderDlc\(\)/.test(body) || !/renderDlcMain\(\)/.test(body)) bad('찾기 칸에 칠 때 창 전체(찾기 칸까지)를 다시 그림 — 한글 조합이 끊김');
    const main = v.slice(v.indexOf('function renderDlcMain'), v.indexOf('function renderDlc()'));
    if (!main || /pk-find|data-find/.test(main)) bad('카드만 다시 그리는 함수(renderDlcMain)가 없거나 찾기 칸을 다시 씀');
  }
  // 5) 휴대폰의 파일 고르기: .htpack을 고를 수 있게 zip · octet-stream도 받음
  {
    let made = null;
    const w = {
      HT: { toast() {} },
      matchMedia: () => ({ matches: false }),
      navigator: { userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 7) Mobile', maxTouchPoints: 5 },
      location: { protocol: 'http:', assign() {} },
      history: { state: null, pushState() {}, back() {} },
      document: {
        addEventListener() {},
        dispatchEvent() {},
        documentElement: { dataset: {} },
        body: { appendChild() {} },
        createElement: () => (made = { addEventListener(t, fn) { if (t === 'change') this.change = fn; }, click() { this.files = []; this.change(); } }),
      },
      addEventListener() {},
      setTimeout: fn => fn(),
      CustomEvent: class {},
      File,
    };
    w.window = w;
    vm.createContext(w);
    vm.runInContext(src('js/platform.js'), w, { filename: 'js/platform.js' });
    await w.HT.platform.openFiles('.htpack', true);
    const acc = String((made && made.accept) || '');
    if (!/application\/octet-stream/.test(acc) || !/application\/x-htpack/.test(acc) || /application\/zip|application\/json/.test(acc)) bad(`휴대폰 파일 고르기가 전용 팩을 받지 않음: accept=${acc}`);
  }
  // 6) 메이커로 연 팩의 큰 표지는 작업본에 넣기 전에 줄임
  {
    const m = src('js/maker.js');
    const open = m.slice(m.indexOf('async function openFile'), m.indexOf('/* ---------- 고르는 창'));
    const fit = open.indexOf('fitCover');
    if (fit < 0 || fit > open.indexOf('switchDraft(')) bad('메이커로 연 팩의 큰 표지를 작업본에 넣기 전에 줄이지 않음 (저장소가 넘침)');
  }
  // 7) 네이티브 모바일 파일 크기 검사는 별도 모바일 가지에서 합니다.
  // 8) 어두운 모드: 분류 딱지는 토큰 색 (고정된 밝은 바탕 위의 --text 글자는 안 보임)
  {
    const css = src('css/viewer.css');
    const rule = (css.match(/\.pk-cat \{[^}]*\}/) || [''])[0];
    if (!rule || /rgba\(255, 252, 246/.test(rule) || !/var\(--surface\)/.test(rule)) bad('분류 딱지 바탕이 고정된 밝은 색이라 어두운 모드에서 글자가 안 보임');
  }
}

/* [54] 2단계 작업실 틀 (docs/계획-메이커-팩-2-작업실.md 과제 1~6): 명령 표 · 키 이름 · 배치 기억 · 구조 나무 · 파일 배선 · 뼈대 */
/* [54]-1 순수 부품 · 파일 배선 */
{
  const bad = msg => out.problems.push(`작업실 틀: ${msg}`);
  try {
    load('js/maker-shell.js');
  } catch (e) {
    bad(`js/maker-shell.js를 읽지 못함 — ${e.message}`);
  }
  const S = HT.makerShell;
  if (!S) bad('js/maker-shell.js가 HT.makerShell을 만들지 않음');
  else {
    const cmds = S.COMMANDS.filter(c => !c.sep);
    const ids = cmds.map(c => c.id);
    if (new Set(ids).size !== ids.length) bad('명령 id가 겹침');
    for (const c of S.COMMANDS) if (!S.MENUS.some(([m]) => m === c.menu)) bad(`명령 ${c.id || '구분선'}의 메뉴 «${c.menu}»가 MENUS에 없음`);
    const keys = cmds.filter(c => c.key).map(c => c.key);
    if (new Set(keys).size !== keys.length) bad('단축키가 두 명령에 겹침');
    for (const c of cmds.filter(c => c.id.startsWith('base:'))) if (!HT.makerKit.BASE_TABLES[c.id.slice(5)]) bad(`넣기 메뉴 ${c.id}가 바탕 자료 표에 없음`);
    for (const id of ['start', 'open', 'reflect', 'export', 'tab-timeline', 'tab-table', 'tab-wiki', 'toggle-left', 'toggle-right', 'toggle-bottom', 'check', 'changes', 'keys', 'guide', 'delete', 'rename', 'find'])
      if (!ids.includes(id)) bad(`명령 표에 ${id}가 없음`);
    const K = (key, code, mods = {}) => S.keyName(Object.assign({ key, code }, mods));
    [
      [K('e', 'KeyE', { ctrlKey: true, shiftKey: true }), 'Ctrl+Shift+E'],
      [K('ㅠ', 'KeyB', { ctrlKey: true }), 'Ctrl+B'], // 한글 자판
      [K('b', 'KeyB', { ctrlKey: true, altKey: true }), 'Ctrl+Alt+B'],
      [K('1', 'Digit1', { metaKey: true }), 'Ctrl+1'],
      [K('?', 'Slash', { shiftKey: true }), '?'],
      [K('Delete', 'Delete'), 'Delete'],
      [K('F2', 'F2'), 'F2'],
      [K('Shift', 'ShiftLeft', { shiftKey: true }), ''],
      [K('Process', 'KeyK', { ctrlKey: true }), 'Ctrl+K'], // 조합 중에 온 키
    ].forEach(([got, want], i) => got !== want && bad(`키 이름 ${i}: «${got}» ≠ «${want}»`));
    const d = S.readUi(null);
    const def = { left: { open: true, w: 280, tab: 'tree' }, right: { open: true, w: 380, wide: false }, bottom: { open: false, h: 220, tab: 'problems' }, center: 'timeline', grid: {}, findHidden: [], dim: 'mid', tree: {} };
    if (JSON.stringify(d) !== JSON.stringify(def)) bad(`배치 기본값: ${JSON.stringify(d)}`);
    const u = S.readUi({ left: { w: 50, tab: 'x', open: false }, right: { w: 100, wide: 1 }, bottom: { h: 9, open: true, tab: 'changes' }, center: 'wiki', dim: 'strong', tree: { history: false, x: 'y' } });
    if (u.left.w !== 200 || u.left.open || u.left.tab !== 'tree' || u.right.w !== 320 || u.right.wide || u.bottom.h !== 120 || !u.bottom.open || u.bottom.tab !== 'changes' || u.center !== 'timeline' || u.dim !== 'strong' || JSON.stringify(u.tree) !== '{"history":false}')
      bad(`배치 읽기가 한도 · 모르는 값을 거르지 않음: ${JSON.stringify(u)}`);
    if (S.readUi({ left: { w: 9999 } }).left.w !== 480) bad('왼쪽 폭이 480을 넘음');
    const kinds = HT.draft.clean(JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8')));
    const tree = S.treeOf(kinds);
    const g = k => tree.find(x => x.key === k);
    if (tree.map(x => x.key).join() !== 'base,history,events,figures,split,lens,patches,docs,images') bad(`구조 묶음 차례: ${tree.map(x => x.key)}`); // lens = 단체 · 제도 (형식 3 — 통합에서 더함)
    const per = g('history').kids.filter(k => k.key.startsWith('periods:'));
    if (per.reduce((a, k) => a + k.n, 0) !== kinds.periods.length) bad('구조의 시대 수가 작업본과 다름');
    if (g('events').n !== kinds.events.length) bad('구조의 사건 수가 작업본과 다름');
    if (g('base').kids.map(k => k.base).join() !== 'tracks,spheres,yearCycles,categories,peoples,rankDefs,houses,surnames,places,themes') bad('바탕 줄이 바탕 자료 표와 맞지 않음'); // 성씨 · 지명 · 주제 (형식 3) · 문화권(2026-10-23) · 주기(5단계 과제 6)
    for (const k of g('base').kids) if (!HT.makerKit.BASE_TABLES[k.base]) bad(`구조 나무의 바탕 줄 «${k.base}»에 바탕 자료 표가 없음`);
    const rows = per[0].rows;
    if (rows.some((r, i) => i && r.t < rows[i - 1].t)) bad('시대 줄이 시작 해 차례가 아님');
    if (!rows.every(r => kinds.periods.some(p => `${kinds.id}/${p.id}` === r.uid))) bad('시대 줄의 uid가 "<DLC id>/<항목 id>"가 아님');
    for (const grp of tree) for (const r of (grp.rows || []).concat(...(grp.kids || []).map(k => k.rows || []))) if (r.uid && !['patch'].includes(r.kind) && !HT.FORMS[r.kind]) bad(`구조 줄의 종류 «${r.kind}»가 폼 표에 없음`);
    const dating = HT.draft.clean(JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8'))); // 견본에는 패치가 없어 덮어쓰기 둘(고침 · 숨김)을 더해 봄
    dating.patches.push({ target: 'east-asia-base/x', set: { name: '가' } }, { target: 'east-asia-base/y', hide: true });
    if (S.treeOf(dating).find(x => x.key === 'patches').n !== dating.patches.filter(p => p && p.target).length) bad('구조의 덮어쓰기 수가 패치 수와 다름');
    const name = rows[0].name;
    const f = S.filterTree(tree, name);
    const flat = f.flatMap(x => (x.rows || []).concat(...(x.kids || []).map(k => k.rows || [])));
    if (!f.length || !f.every(x => x.open) || !flat.length || flat.some(r => !r.name.includes(name))) bad('찾기가 맞는 줄만 남기지 않음');
    if (S.filterTree(tree, '').length !== tree.length) bad('빈 찾기가 나무를 줄임');
    if (S.treeOf(null).length) bad('작업본이 없는데 나무가 있음');
  }
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  const at = s => make.indexOf(`src="${s}"`);
  if (!(at('js/maker.js') > 0 && at('js/maker.js') < at('js/maker-shell.js') && at('js/maker-shell.js') < at('js/viewer.js'))) bad('dlc-maker.html에서 js/maker-shell.js가 maker.js 다음 · viewer.js 앞이 아님');
  if (readFileSync(join(root, 'index.html'), 'utf8').includes('maker-shell.js')) bad('index.html(보기 전용)이 작업실 틀을 읽음');
  if (!readFileSync(join(root, 'sw.js'), 'utf8').includes("'js/maker-shell.js'")) bad('sw.js PRECACHE에 js/maker-shell.js가 없음');
  if (!/MAKER_ONLY = \[[^\]]*'js\/maker-shell\.js'/.test(readFileSync(join(root, 'scripts/build-web.mjs'), 'utf8'))) bad('build-web의 MAKER_ONLY에 js/maker-shell.js가 없음');
}
/* [54]-2 뼈대: 새 자리 · 없앤 자리 · viewer가 묶는 요소 · 도구 줄의 명령 · 편집 창 · 상세가 오른쪽 창 안 · 틀을 붙이는 곳 */
{
  const bad = msg => out.problems.push(`작업실 뼈대: ${msg}`);
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  const has = id => make.includes(`id="${id}"`);
  for (const id of ['mkMenubar', 'mkMenus', 'mkDoc', 'mkName', 'mkVer', 'mkSaved', 'mkTools', 'mkLeft', 'mkTree', 'mkTreeFind', 'mkPacks', 'mkCTabs', 'mkCenter', 'mkRight', 'mkProps', 'mkBottom', 'mkBottomBody', 'mkStatus', 'mkStart', 'mkCheckBtn', 'mkChanges', 'mkReflect', 'mkFile', 'mkAlert', 'mkDrift'])
    if (!has(id)) bad(`dlc-maker.html에 #${id}가 없음`);
  for (const id of ['mkBar', 'dock', 'mkPick', 'mkInfoBtn', 'mkBaseBtn', 'mkPasteBtn']) if (has(id)) bad(`옛 자리 #${id}가 남아 있음`);
  /* viewer.js가 조건 없이 묶는 요소 — 메이커에도 있어야 함 (숨긴 자리라도) */
  for (const id of ['filterToggle', 'menuBtn', 'addPeriodBtn', 'searchInput', 'searchResults', 'viewRange', 'dlcBtn', 'addEventBtn', 'ctxMenu', 'filterbar', 'zenExit', 'statusPill', 'packSummary', 'legend', 'detail', 'editPane', 'editorForm', 'wikiPane', 'timeline', 'stage', 'yearBtn', 'measureBtn', 'tableBtn', 'imageBtn', 'legendBtn'])
    if (!has(id)) bad(`viewer.js가 묶는 #${id}가 dlc-maker.html에 없음`);
  const stageEnd = make.indexOf('</main>');
  if (!(make.indexOf('id="mkRight"') > stageEnd && make.indexOf('id="detail"') > make.indexOf('id="mkRight"') && make.indexOf('id="editPane"') > make.indexOf('id="mkRight"'))) bad('#detail · #editPane이 #stage 밖 #mkRight 안에 있지 않음');
  if (!make.includes('class="mk-shell"')) bad('<body>에 mk-shell이 없음 (첫 그림부터 작업실 배치)');
  const ids = HT.makerShell ? HT.makerShell.COMMANDS.filter(c => !c.sep).map(c => c.id) : [];
  for (const m of make.matchAll(/data-cmd="([^"]+)"/g)) if (!ids.includes(m[1])) bad(`도구 줄 data-cmd="${m[1]}"가 명령 표에 없음`);
  for (const m of make.matchAll(/data-add="([^"]+)"/g)) if (!HT.FORMS[m[1]]) bad(`data-add="${m[1]}"가 폼 표에 없음`);
  const shellSrc = readFileSync(join(root, 'js/maker-shell.js'), 'utf8');
  if (!/function mount\(ctx, api\)/.test(shellSrc)) bad('HT.makerShell.mount가 없음');
  if (!/isTyping\(a\)/.test(shellSrc) || !/if \(!ctrl && /.test(shellSrc)) bad('틀의 단축키가 글 칸에서 Delete · F2 · ?를 쉬지 않음 (Ctrl 조합만 어디서나)');
  const makerSrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (!makerSrc.includes('HT.makerShell.mount(ctx, api)')) bad('maker.js의 start가 틀을 붙이지 않음');
  if (/\$\('#mk(Pick|InfoBtn|BaseBtn|PasteBtn)'\)/.test(makerSrc)) bad('maker.js가 없앤 메이커 줄 단추를 찾음');
  if (makerSrc.includes('--pane-w')) bad('편집 창이 옛 붙박이 폭(--pane-w)을 씀 — 오른쪽 창 폭은 틀이 맡음');
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  if (!/detailEl\.closest\('\.mk-right'\)/.test(vsrc)) bad('syncInset이 오른쪽 창 안의 상세를 연표를 가린 것으로 셈');
  if (!/closest\('#editPane, \.mk-win, \.fp-win, #mkProps, #mkStart'\)/.test(vsrc)) bad('inMakerWin이 팩 정보 · 처음 화면을 모름 (그 안에서 누른 글자가 단축키로 샘)');
  if (!/cmd: \{/.test(vsrc)) bad('viewer가 메이커에 명령(ctx.cmd)을 넘기지 않음');
}
/* [54]-3 구조 탭: 찾기 칸은 나무 밖(다시 그려도 조합이 끊기지 않게) · 보이는 기간 밖일 때만 연표를 옮김 · 줄 수 한도 · 붉은 점 */
{
  const bad = msg => out.problems.push(`구조 탭: ${msg}`);
  const src = readFileSync(join(root, 'js/maker-shell.js'), 'utf8');
  if (!/findEl\.addEventListener\('input', renderTree\)/.test(src)) bad('찾기 칸의 글이 나무를 다시 그리지 않음');
  if (/findEl\.(outerHTML|parentNode\.innerHTML)|treeEl\.parentNode\.innerHTML/.test(src)) bad('찾기 칸까지 다시 그림 (한글 조합이 끊김)');
  if (!/e < v\.start \|\| s > v\.end/.test(src)) bad('구조에서 누른 항목이 이미 보이는데도 연표를 옮김 (움직임 원칙: 필요할 때만)');
  if (!/const CAP = 300/.test(src)) bad('한 묶음에 그리는 줄 수 한도(300)가 없음');
  if (!/badIds\(\)/.test(src)) bad('검사 오류가 있는 항목에 붉은 점을 달지 않음');
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  if (make.indexOf('id="mkTreeFind"') > make.indexOf('id="mkTree"')) bad('찾기 칸이 나무(#mkTree) 안이나 뒤에 있음');
}
/* [54]-4 아래 창: 검사 창 · 고친 것 창은 없고, 반영이 걸린 항목을 문제 창으로 알림 */
{
  const bad = msg => out.problems.push(`아래 창: ${msg}`);
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  for (const id of ['mkCheckWin', 'mkChangesDialog']) if (make.includes(`id="${id}"`)) bad(`옛 창 #${id}가 남아 있음`);
  const src = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (/checkWin|changesDialog/.test(src)) bad('maker.js가 옛 검사 창 · 고친 것 창을 씀');
  if (!/function renderBottom\(\)/.test(src)) bad('아래 창을 그리는 renderBottom이 없음');
  if (!/shell\.openBottom\('problems'\)/.test(src.slice(src.indexOf('function reflectNow'), src.indexOf('function exportFile')))) bad('반영이 오류 · 빠진 항목을 문제 창으로 알리지 않음');
  const shellSrc = readFileSync(join(root, 'js/maker-shell.js'), 'utf8');
  if (/api\.openCheck|api\.openChanges/.test(shellSrc)) bad('틀이 아직 옛 검사 창 · 고친 것 창을 부름');
}
/* [54]-5 처음 화면 · 카드 공용 함수: 옛 DLC 관리 카드와 글자까지 같음 · 작업본에만 두는 칸(_)은 파일로 나가지 않음 · 날짜 · 옛 고르는 창 없음 */
{
  const bad = msg => out.problems.push(`처음 화면: ${msg}`);
  const esc = HT.escapeHtml;
  /* 옛 viewer.js의 카드(1단계 532da4b) — 같은 입력에 같은 글이 나와야 함 */
  const oldIsBase = p => !!(p.builtin || p.overridesBuiltin);
  const oldCat = p => (oldIsBase(p) ? '기본팩' : (HT.PACK_CATEGORIES.find(c => c.id === p.category) || {}).name || '');
  const oldCover = p => `${p.cover ? `<img src="${esc(p.cover)}" alt="" loading="lazy">` : HT.autoCover(p)}${oldCat(p) ? `<span class="pk-cat${oldIsBase(p) ? ' is-base' : ''}">${esc(oldCat(p))}</span>` : ''}`;
  const oldCounts = (src, keep) => HT.USER_LISTS.map(({ list, kind }) => ({ list, word: HT.FORMS[kind].word, n: (src[list] || []).length })).filter(x => !keep || x.n || keep.includes(x.list)).map(x => `${x.word} ${x.n}개`).join(' · ');
  const oldContents = p => [oldCounts(p, ['periods', 'events']), (p.patches || []).length ? `덮어쓰기 ${p.patches.length}개` : '', Object.keys(p.documents || {}).length ? `문서 ${Object.keys(p.documents).length}개` : ''].filter(Boolean).join(' · ');
  const oldCard = (p, on, sel, editing, rel) => `<div class="pk-card${on ? '' : ' is-off'}${sel ? ' is-sel' : ''}" data-pick-pack="${esc(p.id)}" tabindex="0" role="button" aria-pressed="${sel}" aria-label="${esc(p.name)} — 누르면 자세히">
      <div class="pk-cover">${oldCover(p)}</div>
      <div class="pk-body">
        <div class="pk-name"><b>${esc(p.name)}</b><span class="ver">v${esc(p.version)}</span>${editing ? '<span class="pack-tag">고치는 중</span>' : ''}<label class="switch" title="${on ? '끄기' : '켜기'}"><input type="checkbox" data-toggle="${esc(p.id)}"${on ? ' checked' : ''} aria-label="${esc(p.name)} ${on ? '끄기' : '켜기'}"><i></i></label></div>
        ${p.summary || p.description ? `<p class="pk-sum">${esc(p.summary || p.description)}</p>` : ''}
        ${(p.tags || []).length ? `<div class="pk-tags">${p.tags.map(t => `<span>${esc(t)}</span>`).join('')}</div>` : ''}
        <div class="pk-meta">${esc(oldContents(p))}</div>
        ${rel}
      </div>
    </div>`;
  const C = HT.packCard;
  if (!C || typeof C.html !== 'function') bad('HT.packCard가 없음 (js/packfile.js)');
  else {
    const rel = '<div class="pk-rel is-ok">✓ 필요한 팩 켜짐</div>';
    for (const p of packs) {
      for (const [on, sel, editing] of [[true, false, false], [false, true, true]]) {
        const want = oldCard(p, on, sel, editing, sel ? rel : '');
        const got = C.html(p, { sel, toggle: on, off: !on, tag: editing ? '고치는 중' : '', rel: sel ? rel : '' });
        if (got !== want) bad(`«${p.id}» 카드가 옛 DLC 관리 카드와 다름 (켜짐 ${on})`);
      }
    }
    const plain = C.html(packs[0], { hint: '누르면 이 DLC를 고칩니다' });
    if (plain.includes('class="switch"') || !plain.includes('누르면 이 DLC를 고칩니다')) bad('스위치 없는 카드(처음 화면)가 스위치를 그리거나 안내 글을 바꾸지 않음');
  }
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  if (/const coverHTML = p =>|const listCountsText = /.test(vsrc)) bad('viewer.js에 옛 카드 부품이 남음 (HT.packCard로 옮김)');
  if (!/HT\.packCard\.html\(/.test(vsrc)) bad('DLC 관리가 HT.packCard.html을 부르지 않음');
  const kinds = JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8'));
  const withUnder = Object.assign(HT.draft.clean(kinds), { _edited: 1, _nextNote: '적어 둔 말' });
  const r = HT.normalizePack(withUnder);
  if (!r.pack) bad('작업본에만 두는 칸(_)이 있으면 검사를 통과하지 못함');
  else {
    const json = HT.packToJSON(r.pack);
    if ('_edited' in json || '_nextNote' in json) bad('작업본에만 두는 칸(_)이 파일로 나감');
    if (r.warnings.some(w => /_edited|_nextNote/.test(w.msg))) bad('작업본에만 두는 칸(_)을 검사가 경고함');
  }
  const kit = HT.makerKit;
  if (typeof kit.today !== 'function' || kit.today(new Date(2026, 0, 5)) !== '2026-01-05') bad('kit.today가 YYYY-MM-DD(그 컴퓨터의 날짜)가 아님');
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  if (make.includes('id="mkPickDialog"')) bad('옛 고르는 창(#mkPickDialog)이 남음');
  const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (/pickDialog|renderPick|openPick/.test(msrc)) bad('maker.js가 옛 고르는 창을 씀');
  if (!/async function createNew\(\{ name, id, category, how \}\)/.test(msrc)) bad('새로 만들기(createNew)가 시작 방법을 받지 않음');
  if (!/if \(maker\) return maker\.openDropped\(/.test(vsrc)) bad('메이커에서 끌어다 놓은 파일이 설치로 감 (메이커에서는 열기)');
}
/* [55] 2단계 불러온 팩 · 자물쇠 (docs/계획-메이커-팩-2-작업실.md 과제 7~9) */
/* [55]-1 순수: 기록 읽기 · 줄 짜기(저절로 드는 팩 · 없는 팩) · 흐리기 CSS · 필요한 팩 맞추기 · id 옮기기 */
{
  const bad = msg => out.problems.push(`불러온 팩: ${msg}`);
  const kit = HT.makerKit;
  if (!['readRefs', 'patchTargets', 'refPlan', 'refDimCSS', 'syncNeeds', 'moveRefs'].every(f => typeof kit[f] === 'function')) bad('HT.makerKit에 불러온 팩 도구가 없음');
  else {
    const all = kit.readRefs({ mine: [{ id: 'east-asia', show: false }, { id: 'east-asia' }, { id: 'bad id!' }, { id: 'mine' }, null], 'x y': [{ id: 'a' }], empty: [] });
    if (JSON.stringify(all) !== JSON.stringify({ mine: [{ id: 'east-asia', show: false, locked: true }] })) bad(`기록 읽기가 겹침 · 잘못된 id · 자기 자신을 거르지 않음: ${JSON.stringify(all)}`);
    const base = packs[0]; // 기본팩 — dev-smoke가 맨 먼저 정규화한 것 (builtin 표시는 HT.loadPacks가 붙이므로 여기엔 없음)
    const d = HT.draft.blank({ id: 'mine', name: '내 팩' });
    if (kit.refPlan(d, [], packs).length) bad('아무것도 적지 않은 새 DLC에 불러온 팩이 있음 (처음에는 이 DLC만)');
    d.patches.push({ target: `${base.id}/x`, hide: true }, { target: 'mine/y', hide: true });
    d.relations = [{ type: 'needs', id: 'gone-pack' }];
    if (JSON.stringify(kit.patchTargets(d)) !== JSON.stringify([base.id])) bad('덮어쓰기 대상 팩 id가 틀림 (자기 자신은 빼야 함)');
    const lastId = packs[packs.length - 1].id;
    const rows = kit.refPlan(d, [{ id: 'mine' }, { id: lastId, show: false, locked: false }], packs);
    const by = id => rows.find(r => r.id === id);
    if (by('mine')) bad('작업본 자신이 불러온 팩에 들어감');
    if (!by(base.id) || by(base.id).auto !== 'patch' || !by(base.id).locked || !by(base.id).show) bad('덮어쓰기 대상 팩이 잠긴 채 저절로 들어오지 않음');
    if (!by('gone-pack') || by('gone-pack').auto !== 'needs' || !by('gone-pack').missing) bad('설치되지 않은 필요한 팩이 missing 줄로 남지 않음');
    const last = by(lastId);
    if (!last || last.show || last.locked || last.auto) bad('적어 둔 줄의 보이기 · 자물쇠가 지켜지지 않음');
    if (rows[0].id !== lastId) bad('적어 둔 줄이 저절로 든 줄보다 앞에 오지 않음');
    const flat = s => s.replace(/\s+/g, ' ');
    const css = flat(kit.refDimCSS([{ id: 'aa', show: true, locked: true }, { id: 'bb', show: true, locked: false }, { id: 'cc', show: false, locked: true }, { id: 'dd', show: true, locked: true, missing: true }], 'mid'));
    if (!/\[data-uid\^="aa\/"\][^{]*\{ opacity: 0\.45;/.test(css) || !/\[data-uid\^="bb\/"\][^{]*\{ opacity: 0\.6;/.test(css) || css.includes('cc/') || css.includes('dd/') || !css.includes(':not(.is-selected)')) bad(`흐리기 CSS가 틀림: ${css}`);
    if (!kit.refDimCSS([{ id: 'aa', show: true, locked: true }], 'light').includes('opacity: 0.3;') || !kit.refDimCSS([{ id: 'aa', show: true, locked: false }], 'strong').includes('opacity: 0.8;')) bad('옅게 0.3 · 진하게(풀림) 0.8이 아님');
    if (kit.refDimCSS([], 'mid') !== '') bad('불러온 팩이 없는데 흐리기 CSS가 있음');
    const dd = HT.draft.clean(JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8'))); // 견본에는 패치가 없어 기본팩을 고치는 덮어쓰기 하나를 더함
    dd.patches.push({ target: `${base.id}/x`, set: { name: '가' } });
    const n1 = kit.syncNeeds(dd, packs);
    const n2 = kit.syncNeeds(dd, packs);
    if (!n1 || n2 || !dd.relations.some(r => r.type === 'needs' && r.name)) bad(`덮어쓰기 대상을 필요한 팩으로 한 번만 더하지 않음 (${JSON.stringify(dd.relations)})`);
    const plain = HT.draft.blank({ id: 'p' });
    if (kit.syncNeeds(plain, packs) || 'relations' in plain) bad('덮어쓰기가 없는 작업본에 relations 칸이 생김 (한 글자도 바뀌면 안 됨)');
    const moved = kit.moveRefs({ a: [{ id: 'x', show: true, locked: true }], b: [] }, 'a', 'c');
    if (moved.a || !moved.c || moved.c[0].id !== 'x') bad('id를 바꿀 때 불러온 팩 기록이 새 id로 옮겨 가지 않음');
  }
}
/* [55]-2 배선: 메이커의 모델은 불러온 팩으로(켜고 끔은 보지 않음) · 눈을 끈 팩은 연표에서 거름 · 흐리기 CSS를 씀 */
{
  const bad = msg => out.problems.push(`불러온 팩 배선: ${msg}`);
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  if (!/maker \? maker\.buildModel\(state\.packs\)/.test(vsrc)) bad('refresh가 메이커에 켜진 팩만 넘김 (불러온 팩이 켜고 끔을 대신)');
  if (!/maker\.hiddenPacks\(\)/.test(vsrc)) bad('applyFilters가 눈을 끈 팩을 거르지 않음');
  const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (!/refRows = kit\.refPlan\(/.test(msrc)) bad('buildModel이 불러온 팩 줄로 모델을 짓지 않음');
  if (!/'ht\.maker\.refs'/.test(msrc)) bad('불러온 팩 기록 열쇠(ht.maker.refs)가 없음');
  const ssrc = readFileSync(join(root, 'js/maker-shell.js'), 'utf8');
  if (!/mkRefDim/.test(ssrc) || !/refDimCSS\(api\.refRows\(\), ui\.dim\)/.test(ssrc)) bad('틀이 흐리기 CSS를 쓰지 않음');
}
/* [55]-3 불러온 팩 탭: 저절로 든 줄은 뺄 수 없음 · 없는 팩 줄 · 조용한 설치 · D 키 · 기본팩에 덧붙이기 · id 바꾸면 기록이 따라감 */
{
  const bad = msg => out.problems.push(`불러온 팩 탭: ${msg}`);
  const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (!/function renderPacks\(\)/.test(msrc)) bad('불러온 팩 탭을 그리는 renderPacks가 없음');
  if (!/r\.auto \? '' : '<button type="button" class="ic" data-ref-remove/.test(msrc)) bad('저절로 든 줄(덮어쓰기 대상 · 필요한 팩)에도 빼기 단추가 있음');
  if (!/설치되어 있지 않음/.test(msrc)) bad('설치되지 않은 팩 줄을 알리지 않음');
  if (!/how === 'base'/.test(msrc)) bad('기본팩에 덧붙이기가 기본팩을 불러오지 않음');
  if ((msrc.match(/kit\.moveRefs\(/g) || []).length < 1) bad('id를 바꿀 때 불러온 팩 기록을 옮기지 않음');
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  if (!/async function installFiles\(files, \{ quiet = false \} = \{\}\)/.test(vsrc) || !/if \(!quiet\) openDlc\(\)/.test(vsrc) || !/return ids;/.test(vsrc)) bad('installFiles가 조용한 설치(quiet) · 설치한 id 돌려주기를 하지 않음');
  if (!/if \(maker\) return maker\.openPacks\(\)/.test(vsrc)) bad('메이커의 DLC 관리(D)가 불러온 팩 탭으로 가지 않음');
}
/* [55]-4 자물쇠: 잠긴 팩의 항목은 편집 창 · 지우기 · 저장이 막히고, 상세에 자물쇠 줄 · [🔓 자물쇠 풀기] · [내 DLC로 복사](3단계 자리) */
{
  const bad = msg => out.problems.push(`자물쇠: ${msg}`);
  const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const pe = vsrc.slice(vsrc.indexOf('function paneEditable'), vsrc.indexOf('function paneEditable') + 400);
  if (!/maker\.isLocked\(x\)/.test(pe)) bad('paneEditable이 잠긴 항목을 편집 창으로 엶');
  const del = vsrc.slice(vsrc.indexOf('function deleteItem'), vsrc.indexOf('function deleteItem') + 600);
  if (!/maker\.isLocked\(x\)/.test(del)) bad('deleteItem이 잠긴 항목을 지우거나 숨김');
  if (!/mk-lockbar/.test(vsrc) || !/data-unlock/.test(vsrc)) bad('상세에 자물쇠 줄 · [자물쇠 풀기]가 없음');
  if (!/data-copy-own/.test(vsrc) || !/maker\.duplicateSelection/.test(vsrc)) bad('[내 DLC로 복사] 명령이 실제 복제에 연결되지 않음');
  const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  for (const fn of ['function saveItem', 'function removeItem']) {
    const body = msrc.slice(msrc.indexOf(fn), msrc.indexOf(fn) + 900);
    if (!/isLocked\(x\)/.test(body)) bad(`${fn.slice(9)}가 잠긴 팩의 항목을 고침 (마지막 가드)`);
  }
}
/* [56] 2단계 판 기록 · 팩 정보 (과제 10~11) */
/* [56]-1 판 기록 · 태그 · 관계 도구 · 반영 차례 */
{
  const bad = msg => out.problems.push(`판 기록: ${msg}`);
  const kit = HT.makerKit;
  if (!['changelogNote', 'nextChangelog', 'addTag', 'addRelation'].every(f => typeof kit[f] === 'function')) bad('HT.makerKit에 판 기록 · 태그 · 관계 도구가 없음');
  else {
    const ch = [{ type: 'add', list: 'periods' }, { type: 'add', list: 'periods' }, { type: 'edit', list: 'events' }, { type: 'add', list: 'patches' }, { type: 'edit', list: 'info' }, { type: 'edit', list: 'info' }, { type: 'remove', list: 'documents' }];
    const note = kit.changelogNote(ch);
    if (note !== '시대 2 더함 · 사건 1 고침 · 덮어쓰기 1 더함 · DLC 정보 고침 · 문서 1 뺌') bad(`고친 것 요약: «${note}»`);
    if (kit.changelogNote([]) !== '') bad('고친 것이 없는데 요약이 있음');
    const list = kit.nextChangelog([{ version: '1.0.1', date: '2026-01-01', note: '앞' }], { version: '1.0.2', date: '2026-02-02', note: '뒤' });
    if (list.length !== 2 || list[0].version !== '1.0.2' || list[1].note !== '앞') bad('새 줄이 맨 앞에 오지 않음');
    const long = kit.nextChangelog(Array.from({ length: 200 }, (_, i) => ({ version: `0.0.${i}`, date: '', note: '' })), { version: '9.9.9', date: '', note: '' });
    if (long.length !== HT.PACK_LIMITS.changelog || long[0].version !== '9.9.9') bad('판 기록이 200줄을 넘거나 새 줄을 버림');
    if (kit.nextChangelog(undefined, { version: '1.0.0', date: 'd', note: 'x'.repeat(900) })[0].note.length !== HT.PACK_LIMITS.noteLen) bad('고친 것 글이 500자에서 잘리지 않음');
    const t1 = kit.addTag(['가'], '  나 ');
    if (t1.problem || t1.tags.join() !== '가,나') bad('태그 더하기가 앞뒤 빈칸을 떼고 더하지 않음');
    if (!kit.addTag(['a', 'b', 'c', 'd', 'e'], 'f').problem) bad('태그 5개를 넘어도 막지 않음');
    if (!kit.addTag([], 'x'.repeat(21)).problem) bad('20자 넘는 태그를 막지 않음');
    const t2 = kit.addTag(['가'], '가');
    if (t2.problem || t2.tags.length !== 1) bad('같은 태그를 두 번 넣음');
    const d = HT.draft.blank({ id: 'me', name: '나' });
    if (!kit.addRelation(d, 'needs', 'bad id!', packs)) bad('잘못된 id를 관계로 받음');
    if (!kit.addRelation(d, 'needs', 'me', packs)) bad('자기 자신을 관계로 받음');
    if (kit.addRelation(d, 'requires', 'x1', packs) || !d.requires.includes('x1')) bad('함께 쓰면 좋음이 requires에 들어가지 않음');
    if (kit.addRelation(d, 'conflicts', packs[0].id, packs) || !d.relations.some(r => r.type === 'conflicts' && r.id === packs[0].id && r.name === packs[0].name)) bad('함께 못 씀이 relations에 이름과 함께 들어가지 않음');
    kit.addRelation(d, 'conflicts', packs[0].id, packs);
    if (d.relations.filter(r => r.type === 'conflicts').length !== 1) bad('같은 관계를 두 번 넣음');
  }
  const src = readFileSync(join(root, 'js/maker.js'), 'utf8');
  const body = src.slice(src.indexOf('function reflectNow'), src.indexOf('async function exportFile'));
  const at = s => body.indexOf(s);
  if (!(at('kit.syncNeeds(') > 0 && at('kit.nextChangelog(') > 0 && at('kit.nextChangelog(') < at('HT.store.set(K.installed'))) bad('반영이 판 기록 · 필요한 팩을 설치본을 쓰기 전에 적지 않음');
  if (!/_nextNote/.test(body) || !/updated/.test(body)) bad('반영이 다음 반영 말(_nextNote) · 마지막 반영한 날(updated)을 쓰지 않음');
}
/* [56]-2 팩 정보: 옛 대화상자 없음 · 치는 동안 칸을 다시 그리지 않음(한글 조합) · id 바꾸면 불러온 팩 기록도 · 표지(위에서부터 자르기) · 한도 */
{
  const bad = msg => out.problems.push(`팩 정보: ${msg}`);
  const make = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
  if (make.includes('id="mkInfoDialog"')) bad('옛 DLC 정보 창(#mkInfoDialog)이 남음');
  const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
  if (/infoDialog|infoForm|function saveInfo/.test(msrc)) bad('maker.js가 옛 DLC 정보 창을 씀');
  for (const f of ['function renderInfo()', 'function paintInfoCard()', 'async function renameTo(', 'async function setCover(']) if (!msrc.includes(f)) bad(`${f}가 없음`);
  const live = msrc.slice(msrc.indexOf('function renderLive'), msrc.indexOf('function renderLive') + 500);
  if (/renderInfo\(\)/.test(live) || !/paintInfoCard\(\)/.test(live)) bad('모델을 새로 지을 때 팩 정보 칸을 다시 그림 (치던 글 · 한글 조합이 끊김) — 카드 · 표지 · 담긴 것만');
  const ren = msrc.slice(msrc.indexOf('async function renameTo('), msrc.indexOf('async function renameTo(') + 1200);
  if (!/kit\.moveRefs\(refsAll/.test(ren) || !/ctx\.leaveEditor\(/.test(ren)) bad('id를 바꿀 때 불러온 팩 기록을 옮기지 않거나 편집 창을 먼저 닫지 않음');
  if (!/data-info-next/.test(msrc) || !/_nextNote/.test(msrc)) bad('다음 반영 말(_nextNote) 칸이 없음');
  if (!/HT\.PACK_LIMITS\.cover/.test(msrc)) bad('표지 크기 한도(HT.PACK_LIMITS.cover)를 보지 않음');
  const psrc = readFileSync(join(root, 'js/packfile.js'), 'utf8');
  if (!/async function fitCover\(src, maxW = 1600, maxH = 900, \{ top = false \} = \{\}\)/.test(psrc)) bad('fitCover가 위에서부터 자르기(top)를 받지 않음 — 📷 표지가 연표 가운데를 자름');
}
/* [57] 2단계 독립 검토 고침 (2026-09-20): Ctrl+Shift+E가 반영으로 새지 않음 · 처음 화면에서 연표 단축키 쉼 · 찾기 결과가 도구 줄에 잘리지 않음 ·
   떼어 낸 편집 창이 오른쪽 창을 접어도 보이고 앞으로 나옴 · 판 기록만 고쳐도 고친 것에 잡힘 · 지우기는 구조에서 고른 줄 · 빈 트랙 빼기가 구분도 셈 · 바꾸기 전에 치던 글 저장 */
{
  const bad = msg => out.problems.push(`검토 고침: ${msg}`);
  const v = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const s = readFileSync(join(root, 'js/maker-shell.js'), 'utf8');
  const m = readFileSync(join(root, 'js/maker.js'), 'utf8');
  const c = readFileSync(join(root, 'css/maker.css'), 'utf8');
  if (!/if \(ctrl && !e\.shiftKey && k\.toLowerCase\(\) === 'e'\)/.test(v)) bad('연표의 Ctrl+E가 Shift까지 받아 Ctrl+Shift+E(팩 파일로)가 반영으로 샘');
  if (!/maker\.isStart\(\)/.test(v) || !/isStart:/.test(m)) bad('처음 화면이 떠 있어도 연표 단축키(n · z · d …)가 돎');
  if (!/\.mk-find \.search-results \{[^}]*position: fixed/.test(c)) bad('찾기 결과가 도구 줄(overflow) 안에 있어 잘림');
  if (/\.mk-right \{[^}]*z-index: 45/.test(c)) bad('오른쪽 창이 층(z-index)을 만들어 떼어 낸 편집 창이 앞으로 나오지 못함');
  if (!/\nbody\.mk-shell > \.edit-pane\.is-floating \{[^}]*visibility: visible/.test(c)) bad('오른쪽 창을 접으면 떼어 낸 편집 창까지 보이지 않음');
  if (/#mkInfoIdNote/.test(c)) bad('없어진 DLC 정보 창의 CSS 규칙이 남음');
  if (!/mkTree \[data-tuid\]/.test(s.slice(s.indexOf('const current = '), s.indexOf('const current = ') + 400))) bad('Delete · F2가 구조에서 고른 줄이 아니라 오른쪽 창의 항목만 봄');
  if (!/flushSoon\(\);/.test(m.slice(m.indexOf('async function switchDraft'), m.indexOf('async function switchDraft') + 300))) bad('DLC를 바꾸기 전에 치던 글(잠깐 쉬었다 저장)을 저장하지 않음');
  const filt = v.slice(v.indexOf('function applyFilters'), v.indexOf('function applyFilters') + 2200);
  if (!/const epochs = /.test(filt) || !/concat\(events, figures, epochs, scopes\)/.test(filt)) bad('빈 트랙 빼기가 시대 구분 · 대범위만 있는 트랙을 지움');
  /* 판 기록 · 만든 날 · 반영한 날만 고쳐도 '고친 것'에 잡혀야 반영이 됩니다 */
  const raw = JSON.parse(readFileSync(join(root, 'samples/sample-lantern.json'), 'utf8')); // 견본의 판 기록 · 날짜(2026-10-14)와 다른 값으로 고쳐 봄
  const base = HT.normalizePack(HT.draft.clean(raw)).pack;
  for (const [k, val] of [['changelog', [{ version: '1.0.0', date: '2026-01-01', note: '첫 판' }]], ['updated', '2026-01-02'], ['created', '2026-01-01']]) {
    const next = HT.normalizePack(Object.assign(HT.draft.clean(raw), { [k]: val })).pack;
    if (!next) bad(`${k}를 넣은 작업본이 검사를 통과하지 못함`);
    else if (!HT.draft.changes(next, base).some(ch => ch.list === 'info' && ch.key === k)) bad(`${k}만 고치면 '고친 것'에 잡히지 않아 반영할 수 없음`);
  }
}
/* [58] 편집 기본기: 실제 값의 왕복 · 기록 한도 · 복사 자료와 참조 보존 */
{
  const bad = msg => out.problems.push(`편집 기본기: ${msg}`);
  load('js/maker-history.js');
  const { History } = HT.makerHistory, E = HT.makerEdit;
  const first = HT.draft.clean({ id: 'wind', name: '바람 세계', periods: [{ id: 'p', name: '바람국', start: 100, end: 200, track: 't', people: 'folk', leaders: [{ name: '첫 사람', start: 100, end: 200, house: 'clan', rank: '큰 지위' }] }], tracks: [{ id: 't', name: '들녘' }], peoples: [{ id: 'folk', name: '바람 민족', parent: 'elder' }, { id: 'elder', name: '옛 민족' }], rankDefs: [{ id: 'r', name: '큰 지위' }], houses: [{ id: 'clan', name: '바람 가문' }], documents: { p: '본문', 'p//별책': '하위 문서', 'cell:wind/p:leader:첫 사람': '칸 문서' } });
  const history = new History(first), raw = JSON.parse(JSON.stringify(first));
  let seed = 41;
  for (let i = 0; i < 120; i++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    raw.periods[0].end = 201 + seed % 900;
    raw.description = `고침 ${i}`;
    history.push(raw, `고침 ${i}`);
  }
  const last = JSON.stringify(raw);
  let got;
  while (history.canUndo) got = history.undo();
  if (JSON.stringify(got) !== JSON.stringify(first)) bad('모두 되돌린 자료가 처음과 다름');
  while (history.canRedo) got = history.redo();
  if (JSON.stringify(got) !== last) bad('모두 다시 한 자료가 마지막과 다름');
  history.go(17); history.push(first, '새 갈래');
  if (history.canRedo || history.rows.length !== 19) bad('중간에서 새로 고쳤는데 이전 다시 하기 갈래가 남음');
  const limit = new History({ n: 0 }, { steps: 3 });
  for (let n = 1; n < 20; n++) limit.push({ n });
  if (limit.rows.length !== 4 || limit.go(0).n !== 16) bad('걸음 수 한도가 틀림');
  const bytes = new History({ n: 0 }, { bytes: 150 });
  for (let n = 1; n < 10; n++) bytes.push({ n, text: '가나다라' });
  if (bytes.bytes > 150 || !bytes.rows.length) bad('기록 용량 한도가 틀림');
  const copy = E.bundle([first], ['wind/p']);
  if (copy.entries.length !== 1 || copy.definitions.tracks.length !== 1 || copy.definitions.houses.length !== 1 || copy.definitions.rankDefs.length !== 1 || copy.definitions.peoples.length !== 2) bad('복사한 항목에 필요한 정의와 상위 정의가 따라오지 않음');
  const dup = E.insert(first, copy, { duplicate: true });
  const item = dup.draft.periods[1];
  if (item.id === 'p' || item.name !== '바람국 (사본)' || first.periods.length !== 1) bad('복제가 새 id·이름을 만들지 않거나 원본을 바꿈');
  if (dup.draft.documents[item.id] !== '본문' || dup.draft.documents[item.id + '//별책'] !== '하위 문서' || !Object.values(dup.draft.documents).includes('칸 문서')) bad('복제한 문서·하위 문서가 없음');
  const target = HT.draft.clean({ id: 'new', name: '새 세계', tracks: [{ id: 't', name: '내 들녘' }], periods: [{ id: 'p', name: '원래 나라', track: 't', start: 1, end: 2 }] });
  const pasted = E.insert(target, copy);
  if (pasted.draft.tracks.length !== 1 || pasted.draft.tracks[0].name !== '내 들녘' || pasted.draft.periods[1].name !== '바람국' || pasted.draft.periods[1].id === 'p') bad('다른 DLC 붙여넣기에서 기존 정의 우선·이름·id 충돌 처리가 틀림');
  const html = E.clipboardHTML(copy);
  const parsed = E.fromClipboard({ getData: type => type === 'text/html' ? html : '' });
  if (canon(parsed) !== canon(copy) || !E.tsv(copy).startsWith('종류\t이름\t')) bad('시스템 복사 묶음과 표 글이 왕복하지 않음');
  if (E.validBundle({ format: 'history-timeline-items', version: 1, entries: [{ list: 'unknown', item: {} }] })) bad('잘못된 항목 묶음을 허용함');
}

/* [61] 전용 팩 2: 실제 제품 저장기 · 손상/위장/크기 거절 · 백업 · 파일 연결 */
try { out.htpack = await (await import('./check-htpack.mjs')).checkHTPack(); }
catch (e) { out.problems.push(`전용 팩 검사: ${e.stack || e}`); }

/* [62] 연표 성능: 범위 검색은 전체 검사와 같아야 하고, 보이는 줄만 골라도 모델의 높이는 보존합니다. */
{
  const bad = msg => out.problems.push(`연표 성능: ${msg}`);
  const TL = HT.Timeline || {};
  if (!TL.intervalIndex || !TL.intervalQuery || !TL.intervalHas || !TL.visibleRows) bad('범위·줄 검색 도우미가 없음');
  else {
    const data = Array.from({ length: 2000 }, (_, i) => {
      const lo = (i * 137) % 1900 - 1000;
      return { id: i, lo, hi: lo + (i % 31 === 0 ? 2200 : i % 13) };
    });
    data.push({ id: 2000, lo: -Infinity, hi: Infinity }, { id: 2001, lo: 20, hi: 20 });
    const original = JSON.stringify(data), index = TL.intervalIndex(data, e => [e.lo, e.hi]);
    for (let start = -1100; start < 1100; start += 17) {
      const end = start + (start % 3 === 0 ? 0 : 32);
      const expected = data.filter(e => e.hi >= start && e.lo <= end).map(e => e.id).join(',');
      const got = TL.intervalQuery(index, start, end).map(e => e.id).join(',');
      if (got !== expected || TL.intervalHas(index, start, end) !== !!expected) { bad(`범위 ${start}~${end}의 항목 또는 순서가 전체 검사와 다름`); break; }
    }
    if (TL.intervalQuery(TL.intervalIndex([], e => [e.lo, e.hi]), 0, 1).length || TL.intervalHas(null, 0, 1)) bad('빈 범위 검색에 결과가 있음');
    const point = TL.intervalIndex([{ lo: 20, hi: 20 }], e => [e.lo, e.hi]);
    if (!TL.intervalHas(point, 20, 20) || TL.intervalHas(point, 20.1, 21) || TL.intervalHas(point, 18, 19.9)) bad('점과 빈 구간의 경계 포함 판단이 틀림');
    if (JSON.stringify(data) !== original) bad('범위 검색이 원본 자료를 바꿈');
    const tr = { rows: 8, rowTop: [0, 80, 160, 240, 320, 400, 480, 560], rowHs: [60, 60, 0, 60, 60, 60, 60, 60] };
    const before = JSON.stringify(tr);
    if ([...TL.visibleRows(tr, 230, 390, 10)].join(',') !== '3,4,5') bad('보이는 줄·여유 범위·높이가 0인 줄의 판단이 틀림');
    if (JSON.stringify(tr) !== before) bad('보이는 줄 검색이 모델 높이를 바꿈');
    const tl = Object.create(TL.prototype);
    tl.view = { start: 1, end: 2 };
    const broad = { start: 100, endY: 100, spanMin: 50, spanMax: 160 };
    const year = { start: 100, endY: 100 };
    const precise = TL.intervalIndex([broad, year], e => tl._extent(e));
    if (!TL.intervalQuery(precise, 120, 121).includes(broad)) bad('통설 점이 밖에 있는 연대 폭을 놓침');
    // 연도만 있는 점은 그해 가운데 하나에 선다(2026-10-14 감독 결정 '일 기준까지 확대해도 범위로 진행 x · 중간으로') — 놓인 자리까지만 넓히고 그해 뒤쪽은 넣지 않음.
    // 사건의 자리(spot)를 적으면 그 구간 안의 그 자리로(같은 해 사건이 겹칠 때)
    if (!TL.intervalQuery(precise, 100.49, 100.51).includes(year) || TL.intervalQuery(precise, 100.7, 100.8).includes(year)) bad('연도만 있는 점이 그해 가운데 하나로 잡히지 않음');
    if (Math.abs(tl._placeAt(year) - 100.5) > 1e-9 || Math.abs(tl._placeAt({ start: 100, endY: 100, spot: 0.25 }) - 100.25) > 1e-9 || tl._placeAt({ start: 100, endY: 110 }) !== 100)
      bad('날짜를 모르는 점의 자리(가운데 · spot · 기간 사건은 시작)가 틀림');
  }
}

/* [63] 메이커 4~6단계: 실제 표·날짜·참조·되돌리기 계산 */
try {
  ['js/maker-grid.js', 'js/maker-drag.js', 'js/maker-find.js'].forEach(load);
  out.makerNext = (await import('./check-maker-next.mjs')).checkMakerNext(HT);
} catch (error) { out.problems.push(`메이커 후속 검사: ${error.stack || error}`); }

/* 형식 3 견본 — 형식 버전 3으로 나가는 견본은 sample-lantern(id lantern-chronicle) 하나(2026-10-14 옛 견본 27개를 이것 하나로 바꿈 — 판 · 단체 · 렌즈 · 이름 · 계보 · 승계표 · 문서 그림 · 집권 · 실권을 모두 담음). 기본팩은 1 · 2 그대로여야 함 ([64] · [65] · [66]이 봄) */
const FORMAT3_SAMPLES = ['lantern-chronicle'];

/* [64] 형식 3 — 모아 보기 판(views) · 지도 1단계(maps — 그림 바탕 + 장면) · 글꼴(fonts) (docs/구상-연표-확장-10건.md 3-6 · 3-10 · 3-9):
   정규화(필수 칸 · 모르는 보기 설정 · 잘못된 꼭짓점 · 장면의 해 · 라이선스 없는 글꼴) · 왕복(날짜 글 · 장면의 주인) · 형식 버전 3(쓴 파일만 · 기본팩은 그대로) ·
   문서 키 view: · map: · 모델(구성 나라 · 장면의 주인을 나라로 · 못 찾음 경고) · HT.mapFrameAt(사이의 해는 앞 열쇠 해 · 구역의 기간) · HT.fontFaces · 패치 대상 아님 · 반영하지 않은 고침 */
try {
  const bad = msg => out.problems.push(`형식 3(판 · 지도 · 글꼴): ${msg}`);
  const NEW3 = ['lantern-chronicle']; // 판(views)을 담은 견본 — 지도(maps) · 글꼴(fonts)을 담은 견본은 없음
  const mk = extra => Object.assign({ format: HT.FORMAT, id: 'smoke-f3', name: '검사', tracks: [{ id: 'f3-a', name: '검사 들' }, { id: 'f3-b', name: '검사 바다' }], periods: [{ id: 'pa', track: 'f3-a', name: '갑 왕국', start: 100, end: 400 }, { id: 'pb', track: 'f3-b', name: '을 연맹', start: 150, end: 300 }, { id: 'pc', track: 'f3-b', name: '갑 왕국', start: 120, end: 200 }] }, extra);
  const norm = extra => HT.normalizePack(mk(extra));
  const msgs = r => r.errors.concat(r.warnings).map(w => w.msg).join(' / ');
  const has = (r, re, which = 'warnings') => r[which].some(w => re.test(w.msg));
  const fontSrc = (head, type = 'woff2') => `data:font/${type};base64,${Buffer.concat([Buffer.from(head, 'latin1'), Buffer.alloc(20, 7)]).toString('base64')}`;
  const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  /* 형식 버전: 읽는 버전 3 · 새 열쇠를 쓴 파일만 3 · 기본팩은 그대로 1 · 2 */
  if (HT.FORMAT_VERSION !== 3 || HT.FORMAT_VERSION_V3 !== 3 || !(HT.NEW_FORMAT_KEYS_V3 || []).length) bad('읽는 형식 버전이 3이 아니거나 버전 3의 열쇠 목록이 비어 있음');
  const fv = extra => HT.packToJSON(norm(extra).pack).formatVersion;
  if (fv({}) !== 1) bad('새 열쇠를 쓰지 않은 파일이 1로 나가지 않음');
  if (fv({ houses: [{ name: '병 가문' }] }) !== 2) bad('버전 2의 열쇠만 쓴 파일이 2로 나가지 않음');
  if (fv({ views: [{ name: '판', members: ['갑 왕국'] }] }) !== 3) bad('views를 쓴 파일이 3으로 나가지 않음');
  if (fv({ maps: [{ name: '지도', size: [10, 10] }] }) !== 3) bad('maps를 쓴 파일이 3으로 나가지 않음');
  if (fv({ fonts: [{ id: 'f', family: '검사체', src: fontSrc('wOF2'), license: '검사용' }] }) !== 3) bad('fonts를 쓴 파일이 3으로 나가지 않음');
  if (fv({ category: 'map' }) !== 3) bad('분류 지도팩(map)을 쓴 파일이 3으로 나가지 않음');
  if (fv({ category: 'region' }) !== 2) bad('형식 2의 분류가 3으로 나감');
  if (fv({ documents: { 'view:v-x': '본문' } }) !== 3 || fv({ documents: { 'map:m-x//하위': '본문' } }) !== 3) bad('판 · 지도의 문서(view: · map:)만 쓴 파일이 3으로 나가지 않음');
  if (fv({ views: [] , maps: [], fonts: [] }) !== 1) bad('빈 목록만 적은 파일이 1로 나가지 않음');
  for (const p of packs) {
    const v = HT.packToJSON(p).formatVersion;
    if (FORMAT3_SAMPLES.includes(p.id) || p.id === 'east-asia-base' ? v !== 3 : v > 2) bad(`${p.id}: formatVersion ${v}로 나감 (형식 3 견본 · 문화권을 든 기본팩만 3)`); // 기본팩은 제 문화권(spheres)으로 형식 3 (2026-10-23)
    if (!NEW3.includes(p.id) && (p.views || p.maps || p.fonts)) bad(`${p.id}: 옛 팩에 형식 3의 목록이 생김`);
  }
  if (HT.normalizePack(Object.assign(mk({}), { formatVersion: 3 })).warnings.some(w => /새로운 형식/.test(w.msg))) bad('formatVersion 3인 파일에 "더 새로운 형식" 경고가 뜸');
  if (!HT.normalizePack(Object.assign(mk({}), { formatVersion: HT.F4.VERSION + 1 })).warnings.some(w => /새로운 형식/.test(w.msg))) bad(`formatVersion ${HT.F4.VERSION + 1}인 파일에 경고가 없음`); // 4는 형식 4로 내려 읽음(리메이크 1a)
  if (!HT.PACK_CATEGORIES.some(c => c.id === 'map' && c.name === '지도팩')) bad('분류에 지도팩(map)이 없음');

  /* 모아 보기 판: 필수 칸 · 나라 참조 꼴 · 기간 · 보기 설정(아는 열쇠만) · id */
  if (!has(norm({ views: [{ members: ['갑 왕국'] }] }), /이름이 비어/, 'errors')) bad('이름 없는 판이 오류가 아님');
  if (!has(norm({ views: [{ name: '판', members: [] }] }), /구성 나라/, 'errors')) bad('구성 나라가 없는 판이 오류가 아님');
  const rv = norm({ views: [
    { name: '판', members: ['f3-a:갑 왕국', { track: 'f3-b', polity: '을 연맹' }, '을 연맹', 'f3-a:갑 왕국'], start: '120-03', end: 300, settings: { density: '조감', lens: '조세제도', show: { leaders: false, 없는표시: true, figures: '네' }, 모르는열쇠: 1 } },
    { name: '판', members: ['갑 왕국'], end: 300, settings: { density: 9 } },
    { id: 'v-x', name: '둘째', members: ['갑 왕국'], settings: 'x' },
    { id: 'v-x', name: '셋째', members: ['갑 왕국'] },
  ] });
  const vs = rv.pack.views || [];
  if (vs.length !== 4 || rv.errors.length) bad(`판 넷이 읽히지 않음: ${msgs(rv)}`);
  else {
    if (canon(vs[0].members) !== canon([{ track: 'f3-a', polity: '갑 왕국' }, { track: 'f3-b', polity: '을 연맹' }, '을 연맹'])) bad(`구성 나라의 꼴 · 겹침 정리가 다름: ${JSON.stringify(vs[0].members)}`);
    if (canon(vs[0].settings) !== canon({ density: 2, lens: '조세제도', show: { leaders: false } })) bad(`보기 설정이 아는 열쇠만 남지 않음: ${JSON.stringify(vs[0].settings)}`);
    for (const re of [/표시 «없는표시»/, /표시 «figures»는 참/, /열쇠 «모르는열쇠»/, /밀도 «9»/, /시작 없이 끝만/, /보기 설정\(settings\)이/, /id "v-x"가 겹쳐 "v-x-2"/]) if (!rv.warnings.some(w => re.test(w.msg))) bad(`판의 경고가 없음: ${re}`);
    if (vs[1].start != null || vs[1].settings || vs[0].id === vs[1].id || vs[1].id !== `${vs[0].id}-2`) bad('끝만 적은 판의 기간 · 모르는 밀도 · 같은 이름의 자동 id가 틀림');
    if (vs[3].id !== 'v-x-2') bad('겹친 판 id에 -2가 붙지 않음');
    const j = HT.packToJSON(rv.pack);
    if (j.views[0].start !== '120-03' || 'startAt' in j.views[0]) bad('판의 날짜 글이 제자리로 접히지 않음');
  }

  /* 지도: 꼴 오류 · 그림 · 층위 · 구역(잘못된 꼭짓점 경고) · 장면(해 순 · 같은 해 · 없는 구역) · 지명 */
  if (!has(norm({ maps: [{ name: '지도', crs: 'polar', size: [1, 1] }] }), /좌표 방식/, 'errors')) bad('모르는 좌표 방식이 오류가 아님');
  if (!has(norm({ maps: [{ name: '지도' }] }), /크기\(size/, 'errors')) bad('그림 좌표인데 크기가 없는 지도가 오류가 아님');
  if (!has(norm({ maps: [{ size: [1, 1] }] }), /이름이 비어/, 'errors')) bad('이름 없는 지도가 오류가 아님');
  const sq = (x, y, s = 2) => [[x, y], [x + s, y], [x + s, y + s], [x, y + s]];
  const rm = norm({ maps: [{
    name: '검사 지도', size: [20, 10], image: 'data:text/plain;base64,QUJD',
    levels: ['도', { id: '군', name: '고을' }, { name: '현' }, '도', {}],
    regions: [
      { id: 'a', name: '가', level: '도', shape: sq(0, 0, 8) },
      { id: 'b', level: '군', parent: 'a', start: 150, end: 250, shape: sq(1, 1) },
      { id: 'c', level: '모름', parent: 'zz', shape: [sq(3, 3), [[1, 1], [2, '둘'], [3, 3]], [[0, 0], [1, 1], [0, 0]]] },
      { id: 'd', shape: [[0, 0], [5, 5]] },
      { id: 'e', shape: [[0, 0], [1, 0], [1, NaN], [0, 1]] },
      { id: 'f', parent: 'g', shape: sq(10, 2) },
      { id: 'g', parent: 'f', shape: sq(12, 2) },
      { id: 'h', level: '도', parent: 'b', shape: sq(30, 2) },
      { id: 'a', shape: sq(0, 0) },
      { shape: sq(0, 0) },
    ],
    frames: [
      { year: 300, owners: { a: '갑 왕국' } },
      { year: '150-06-01', owners: { a: 'f3-a:갑 왕국', b: { track: 'f3-b', polity: '을 연맹' }, zz: '갑 왕국' }, image: PNG },
      { year: 300, note: '같은 해' },
      { owners: { a: '갑 왕국' } },
      { year: 200, owners: { b: null, c: 'none', d: '' } },
    ],
    places: ['나루', { id: 'pl-1' }, '나루', ''],
  }] });
  const M = (rm.pack.maps || [])[0];
  if (!M || rm.errors.length) bad(`검사 지도가 읽히지 않음: ${msgs(rm)}`);
  else {
    if (M.image) bad('그림이 아닌 바탕 그림(data:text)을 버리지 않음');
    if (canon(M.levels) !== canon([{ id: '도', name: '도' }, { id: '군', name: '고을' }, { id: '현', name: '현' }])) bad(`행정 층위가 다름: ${JSON.stringify(M.levels)}`);
    const ids = M.regions.map(r => r.id).join();
    if (ids !== 'a,b,c,f,g,h') bad(`남은 구역이 다름: ${ids} (꼭짓점이 둘뿐인 d · 수가 아닌 꼭짓점의 e · 겹친 a · id 없는 구역은 빠져야 함)`);
    const c = M.regions.find(r => r.id === 'c');
    if (!c || c.level || c.parent || !Array.isArray(c.shape[0][0]) || c.shape.length !== 1) bad('여러 고리 구역에서 잘못된 고리만 빠지고 모르는 층위 · 위 구역이 빠지지 않음');
    const loopKept = ['f', 'g'].filter(id => M.regions.find(r => r.id === id).parent).length;
    if (loopKept !== 1) bad('돌고 도는 위 구역이 끊기지 않음');
    for (const re of [/2번째 꼭짓점이 \[x, y\] 두 수가 아니어서 그 고리를/, /꼭짓점이 2개뿐/, /3번째 꼭짓점이 \[x, y\]/, /그림\(20×10\) 밖으로/, /층위 «모름»/, /위 구역\(parent\) «zz»/, /제자리로 돌아와/, /층위\(군\)가 이 구역의 층위\(도\)보다 위가 아닙니다/, /그림\(png · jpeg · webp/, /행정 층위 "도"가 겹쳐/, /장면 #4: 해\(year\)가 없거나/, /같은 해\(300\)의 장면이 둘/, /구역 «zz»가 이 지도에 없어/])
      if (!rm.warnings.some(w => re.test(w.msg))) bad(`지도의 경고가 없음: ${re}`);
    if (rm.warnings.some(w => /꼭짓점/.test(w.msg) && w.kind !== 'maps')) bad('꼭짓점 경고의 종류(kind)가 maps가 아님');
    if (M.frames.map(f => f.year).join() !== `${HT.readDate('150-06-01').t},200,300` || M.frames[2].note) bad(`장면이 해 순으로 정리되지 않거나 같은 해의 뒤 장면이 남음: ${M.frames.map(f => f.year)}`);
    if (canon(M.frames[1].owners) !== canon({ b: null, c: null })) bad(`장면의 주인 지우기(null · none) · 없는 구역 정리가 다름: ${JSON.stringify(M.frames[1].owners)}`);
    if (canon(M.places) !== canon(['나루', 'pl-1'])) bad(`지명 글 목록이 다름: ${JSON.stringify(M.places)}`);
    const j = HT.packToJSON(rm.pack).maps[0];
    if (j.frames[0].year !== '150-06-01' || 'yearAt' in j.frames[0]) bad('장면의 해 날짜 글이 제자리로 접히지 않음');
    const back = HT.normalizePack(JSON.parse(JSON.stringify(HT.packToJSON(rm.pack))));
    if (!back.pack || canon(HT.packToJSON(back.pack)) !== canon(HT.packToJSON(rm.pack))) bad('검사 지도가 왕복하지 않음');
    /* 장면의 주인 열쇠가 "…At"이어도 날짜 짝으로 접히지 않음 */
    const at = norm({ maps: [{ name: '열쇠', size: [9, 9], regions: [{ id: 'x', shape: sq(0, 0) }, { id: 'xAt', shape: sq(3, 3) }], frames: [{ year: 100, owners: { x: '갑 왕국', xAt: null } }] }] });
    if (canon(HT.packToJSON(at.pack).maps[0].frames[0].owners) !== canon({ x: '갑 왕국', xAt: null })) bad('구역 id가 "…At"인 장면의 주인이 날짜 짝으로 접힘');
  }
  const ll = norm({ maps: [{ name: '경위도', crs: 'lonlat', size: [3, 3], image: PNG, regions: [{ id: 'k', shape: [[120, 30], [130, 30], [130, 40]] }, { id: 'o', shape: [[170, 10], [190, 10], [180, 20]] }], frames: [{ year: 100, image: PNG }] }] });
  const L = (ll.pack.maps || [])[0];
  if (!L || L.size || L.image || L.frames[0].image || L.regions.map(r => r.id).join() !== 'k') bad('경위도 지도에서 크기 · 그림 · 범위 밖 꼭짓점의 구역이 빠지지 않음');
  if (!has(ll, /경위도 범위/)) bad('경위도 범위 밖 꼭짓점에 경고가 없음');

  /* HT.mapFrameAt — 위의 검사 지도(지도 견본이 없어졌으므로): 사이의 해는 앞 열쇠 해 · 첫 장면 앞은 null · 구역의 기간 [시작, 끝) · 주인 이어받기와 지우기(null) · 날짜 글로 묻기 */
  if (M) {
    const at = y => HT.mapFrameAt(M, y);
    if (at(150) !== null) bad('첫 장면(150-06-01)보다 앞의 해에 장면이 나옴');
    if (!at(150.5) || at(150.5).year !== M.frames[0].year || at(199.5).year !== M.frames[0].year) bad('사이의 해(199.5)가 앞 열쇠 해(150-06-01)를 따르지 않음');
    if (!at(249).regions.includes('b') || at(250).regions.includes('b') || !at(250).regions.includes('a')) bad('구역의 기간이 [시작, 끝)이 아님');
    const s200 = at(200);
    if ('b' in s200.owners || canon(s200.owners.a) !== canon({ track: 'f3-a', polity: '갑 왕국' })) bad('장면의 주인이 앞 장면에서 이어받아지지 않거나 지운 주인(null)이 남음');
    if (at('200-03-01').index !== 1 || at(5000).index !== 2) bad('날짜 글로 물은 해 · 마지막 장면 뒤의 해가 틀림');
    if (HT.mapFrameAt(M, '아무 글') !== null || HT.mapFrameAt({ name: '빈 지도' }, 500) !== null) bad('읽을 수 없는 해 · 장면이 없는 지도에 null이 아님');
    /* 모델: 장면의 주인을 나라로 */
    const mm = HT.buildModel([rm.pack], null).mapMap.get(M.id);
    if (!mm || mm.uid !== `map:${M.id}` || mm.warnings.length) bad(`모델의 지도가 없거나 경고가 있음: ${mm && mm.warnings.join(' / ')}`);
    else {
      const it = HT.mapFrameAt(mm, 160).items;
      if (!it.a || it.a.uid !== 'smoke-f3/pa' || !it.b || it.b.uid !== 'smoke-f3/pb') bad('모델의 장면이 주인을 나라로 풀지 않음');
    }
  }
  if (HT.docKey.parse('map:m-x').type !== 'map' || HT.docKey.relative('map:m-x', 'lantern-chronicle') !== 'map:m-x') bad('지도 문서 키가 풀리지 않음');

  /* 모아 보기 판 — 견본 sample-lantern의 '아홉 불씨'(네 트랙에 걸친 판) */
  const sv = packs.find(p => p.id === 'lantern-chronicle');
  if (!sv) {
    if (!skipSamples.some(s => 'sample-lantern.json'.includes(s))) bad('견본 sample-lantern이 없음'); // --skip으로 뺐으면 견본 검사만 건너뜀
  } else {
    const m3 = HT.buildModel([sv], null);
    const vw = m3.viewMap.get('v-nine-embers');
    if (!vw || vw.members.map(p => p.name).join() !== '등불 왕국,윗물국,아랫물국,갈대 공국,적석 왕국,산호 섬나라,설족 칸국' || vw.tracks.join() !== 'hayeon,jeokseok,sanho,seolryeong' || vw.warnings.length || vw.endY !== 788) bad('네 트랙에 걸친 판의 구성 나라 · 트랙 · 기간이 다름');
    if (!vw || !/불씨/.test(vw.wiki || '') || !m3.docs.has('view:v-nine-embers') || HT.docKey.parse('view:v-nine-embers//하위').type !== 'view' || HT.docKey.absolute('view:v-nine-embers', 'lantern-chronicle') !== 'view:v-nine-embers') bad('판 문서(view:id)가 이어지지 않거나 문서 키에 DLC id가 붙음');
    /* 패치 대상이 아님: 판을 가리킨 패치는 대상이 없어 쉬고, 판은 그대로 */
    const patcher = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-f3-patch', name: '검사', patches: [{ target: 'lantern-chronicle/v-nine-embers', set: { name: '바뀐 이름' } }, { target: 'view:v-nine-embers', hide: true }] }).pack;
    const mp = HT.buildModel([sv, patcher], null);
    if (!mp.viewMap.get('v-nine-embers') || mp.viewMap.get('v-nine-embers').name !== '아홉 불씨') bad('판이 패치로 바뀌거나 숨겨짐');
    /* 모델 경고: 못 찾은 나라 · 이름이 여러 트랙에 · 같은 id의 판(다른 DLC) · 그해에 없던 주인 */
    const other = HT.normalizePack(mk({ views: [{ id: 'v-nine-embers', name: '같은 id', members: ['갑 왕국', '없는 나라'] }, { name: '모호', members: ['갑 왕국'] }], maps: [{ name: '때 지난', size: [9, 9], regions: [{ id: 'x', shape: sq(0, 0) }], frames: [{ year: 50, owners: { x: '을 연맹' } }] }] })).pack;
    const mo = HT.buildModel([sv, other], null);
    // 견본 2.0.0의 판 셋 + 검사 팩의 판 둘 가운데 같은 id 하나는 빠져 넷
    if (!mo.viewMap.get('v-nine-embers').warnings.some(w => /같은 id\(v-nine-embers\)/.test(w)) || mo.views.length !== (sv.views || []).length + 1) bad('다른 DLC의 같은 id 판이 앞의 것에 알림으로 남지 않음');
    const amb = mo.views.find(v => v.name === '모호');
    if (!amb || !amb.warnings.some(w => /여러 트랙/.test(w)) || amb.members[0].uid !== 'smoke-f3/pa') bad('이름이 같은 나라가 여러 트랙에 있을 때 경고 · 고른 나라가 다름');
    const lost = HT.buildModel([other], null).views.find(v => v.id === 'v-nine-embers');
    if (!lost || !lost.warnings.some(w => /"없는 나라"을\(를\) 연표에서 찾지 못했습니다/.test(w)) || lost.members.length !== 1) bad('못 찾은 구성 나라에 경고가 없음');
    const late = mo.maps.find(x => x.name === '때 지난'); // 견본 2.0.0에 지도가 하나 생겨 맨 앞이 견본의 지도 — 검사 팩의 지도를 이름으로 찾음
    if (!late || !late.warnings.some(w => /그해에 연표에 없던 나라/.test(w))) bad('그해에 없던 장면의 주인에 경고가 없음');
    /* 옛 자료(기본팩)의 모델: 형식 3의 목록이 비어 있음 */
    const plain = HT.buildModel(packs.filter(p => !NEW3.includes(p.id)), null);
    if (plain.views.length || plain.maps.length || plain.fonts.length) bad('옛 자료의 모델에 판 · 지도 · 글꼴이 생김');
  }

  /* 글꼴: 라이선스 없는 글꼴은 오류(그 글꼴만 빠짐) · 꼴 · 내용 · 한도 · 문자 꼬리표 · HT.fontFaces */
  const rf = norm({ fonts: [
    { id: 'ok', family: '검사체', src: fontSrc('wOF2'), license: '검사용 자유 이용', scripts: ['hang', 'Latn', 'Hangul', 'Hang'], note: '메모' },
    { id: 'nolic', family: '라이선스 없음', src: fontSrc('wOF2') },
    { id: 'png', family: '그림', src: PNG, license: '검사' },
    { id: 'lie', family: '거짓', src: fontSrc('OTTO', 'woff2'), license: '검사' },
    { id: 'otf', family: '오픈', src: fontSrc('OTTO', 'otf'), license: '검사', scripts: 'Hani, Arab' },
    { id: 'ok', family: '겹침', src: fontSrc('wOF2'), license: '검사' },
    { family: 'id 없음', src: fontSrc('wOF2'), license: '검사' },
  ] });
  const fs = rf.pack.fonts || [];
  if (fs.map(f => f.id).join() !== 'ok,otf') bad(`남은 글꼴이 다름: ${fs.map(f => f.id)}`);
  if (!has(rf, /"라이선스 없음": 라이선스\(license\)가 비어/, 'errors') || rf.errors.find(e => /라이선스/.test(e.msg)).kind !== 'fonts') bad('라이선스 없는 글꼴이 오류(종류 fonts)가 아님');
  for (const re of [/"그림": 글꼴 파일\(src\)이 data:font/, /"거짓": 글꼴 파일의 내용이 woff2/, /id가 비었거나/]) if (!has(rf, re, 'errors')) bad(`글꼴 오류가 없음: ${re}`);
  if (!has(rf, /id "ok"가 겹쳐/) || !has(rf, /«Hangul»는 네 글자/)) bad('글꼴의 겹친 id · 잘못된 문자 꼬리표에 경고가 없음');
  if (fs[0] && canon(fs[0].scripts) !== canon(['Hang', 'Latn'])) bad(`문자 꼬리표 정리가 다름: ${fs[0].scripts}`);
  if (fs[1] && canon(fs[1].scripts) !== canon(['Hani', 'Arab'])) bad('쉼표로 이은 문자 꼬리표를 읽지 못함');
  const keepL = HT.PACK_LIMITS.font;
  HT.PACK_LIMITS.font = 40;
  if (!has(norm({ fonts: [{ id: 'big', family: '큼', src: fontSrc('wOF2'), license: '검사' }] }), /너무 커서/, 'errors')) bad('한도를 넘는 글꼴이 오류가 아님');
  HT.PACK_LIMITS.font = keepL;
  const keepN = HT.PACK_LIMITS.fonts;
  HT.PACK_LIMITS.fonts = 1;
  const two = norm({ fonts: [{ id: 'a1', family: '하나', src: fontSrc('wOF2'), license: '검사' }, { id: 'a2', family: '둘', src: fontSrc('wOF2'), license: '검사' }] });
  HT.PACK_LIMITS.fonts = keepN;
  if ((two.pack.fonts || []).length !== 1 || !has(two, /1개까지/)) bad('글꼴 개수 한도가 지켜지지 않음');
  const onlyFonts = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-fonts', name: '글꼴 팩', fonts: [{ id: 'ok', family: '검사체', src: fontSrc('wOF2'), license: '검사' }] });
  if (!onlyFonts.pack || onlyFonts.warnings.some(w => /하나도 없습니다/.test(w.msg))) bad('글꼴만 담은 DLC에 "하나도 없습니다" 경고가 뜸');
  const faces = HT.fontFaces(HT.buildModel([rf.pack, onlyFonts.pack], null));
  if (faces.length !== 2 || faces[0].family !== '검사체' || !/^url\("data:font\/woff2;base64,[^"]+"\) format\("woff2"\)$/.test(faces[0].source) || faces[1].source.indexOf('format("opentype")') < 0 || faces[0].descriptors.display !== 'swap' || faces[0].license !== '검사용 자유 이용') bad(`HT.fontFaces의 목록이 다름: ${JSON.stringify(faces.map(f => [f.id, f.family, f.source.slice(-20)]))}`);
  if (HT.fontFaces(HT.buildModel([rf.pack, onlyFonts.pack], null)).filter(f => f.id === 'ok').length !== 1) bad('같은 id의 글꼴이 두 번 나옴');
  const back = HT.normalizePack(JSON.parse(JSON.stringify(HT.packToJSON(rf.pack))));
  if (canon(HT.packToJSON(back.pack)) !== canon(HT.packToJSON(rf.pack))) bad('글꼴이 왕복하지 않음');

  /* 메이커 작업본: 그대로 들고 다니고(D.clean), 고치면 반영하지 않은 고침으로 잡힘 */
  if (sv) {
    const D = HT.draft;
    const json = HT.packToJSON(sv);
    const d = D.clean(JSON.parse(JSON.stringify(json)));
    if (canon(HT.packToJSON(HT.normalizePack(d).pack)) !== canon(json)) bad('작업본으로 가져와 내보내면 판이 달라짐');
    const d2 = JSON.parse(JSON.stringify(d));
    d2.views[0].name = '고친 판';
    d2.views.pop();
    d2.maps = (d2.maps || []).concat([{ name: '새 지도', size: [5, 5] }]); // 견본 2.0.0의 지도는 그대로 두고 더함 (갈아 끼우면 remove:maps도 잡힘)
    const ch = D.changes(HT.normalizePack(d2).pack, sv).map(c => `${c.type}:${c.list}`).sort().join();
    if (ch !== 'add:maps,edit:views,remove:views') bad(`판 · 지도의 고침이 반영하지 않은 고침으로 잡히지 않음: ${ch}`);
    const fdoc = readFileSync(join(root, 'DLC-형식.md'), 'utf8');
    for (const re of [/## views \(모아 보기 판\) — 형식 버전 3/, /## maps \(지도 — 1단계/, /## fonts \(글꼴\) — 형식 버전 3/, /`formatVersion` \| \| `1` · `2` · `3`/, /`map`\(지도팩/, /`view:v-three-lands` · `map:m-mist-isle`/]) if (!re.test(fdoc)) bad(`DLC-형식.md에 형식 3의 절 · 줄이 없음: ${re}`);
    if (D.WORDS.views !== '모아 보기 판' || D.WORDS.maps !== '지도' || D.WORDS.fonts !== '글꼴') bad('판 기록 요약의 낱말이 없음');
    const d3 = JSON.parse(JSON.stringify(d));
    d3.views[0].wiki = '옛 본문';
    D.setDoc(d3, `view:${d3.views[0].id}`, '새 본문');
    if ('wiki' in d3.views[0] || d3.documents[`view:${d3.views[0].id}`] !== '새 본문') bad('판 문서를 고칠 때 판의 옛 본문(wiki)이 지워지지 않음');
  }
} catch (e) {
  out.problems.push(`형식 3(판 · 지도 · 글꼴) 검사: ${e.stack || e}`);
}

/* [65] 형식 버전 3 — 단체 · 렌즈의 재료 (docs/구상-연표-확장-10건.md 3-7 · 3-8 · 작업판 F2): 형식 버전(3은 새 열쇠를 쓴 파일만) · 읽기(한국어 낱말 · 자유 글 · 칸 · 경고) ·
   왕복 · 모델(단체 · 제도 · 주제 사전 · 사건의 주제 색인 · 나라 쪽 역참조 · 경고) · 패치(사건의 theme · law · election, 단체 · 제도) · 작업본(자동 id · 폼 꼴 · 남의 단체의 패치) · 메이커 표 */
{
  const bad = msg => out.problems.push(`형식 3 단체 · 렌즈: ${msg}`);
  try {
    const head = { format: HT.FORMAT, version: '1.0.0' };
    const read = raw => HT.normalizePack(Object.assign({}, head, raw));
    const ver = raw => {
      const r = read(raw);
      return r.pack ? HT.packToJSON(r.pack).formatVersion : `오류 ${r.errors.map(e => e.msg).join(' / ')}`;
    };
    const T = [{ id: 'ta', name: '가 땅' }, { id: 'tb', name: '나 땅' }];
    const P = [{ id: 'pa', track: 'ta', name: '솔나라', start: 600, end: 1000 }, { id: 'pb', track: 'tb', name: '물나라', start: 650, end: 990 }];
    /* ① 형식 버전 */
    if (HT.FORMAT_VERSION !== 3 || HT.FORMAT_VERSION_V3 !== 3) bad(`읽는 형식 버전이 3이 아님 (${HT.FORMAT_VERSION})`);
    const v = {
      plain: ver({ id: 'f2-v1', name: '검사', tracks: T, periods: P }),
      v2: ver({ id: 'f2-v2', name: '검사', tracks: T, periods: P, houses: [{ id: 'h', name: '가 가문' }] }),
      group: ver({ id: 'f2-v3a', name: '검사', tracks: T, periods: P, groups: [{ name: '들 무리', track: 'ta', start: 700 }] }),
      inst: ver({ id: 'f2-v3b', name: '검사', tracks: T, periods: P, institutions: [{ theme: 'tax', polity: '솔나라', spans: [['밭 나눔', null, 800]] }] }),
      themes: ver({ id: 'f2-v3c', name: '검사', themes: [{ id: 'guild', name: '길드 제도' }] }),
      theme: ver({ id: 'f2-v3d', name: '검사', tracks: T, events: [{ track: 'ta', title: '가', start: 700, theme: '법률' }] }),
      law: ver({ id: 'f2-v3e', name: '검사', tracks: T, events: [{ track: 'ta', title: '가', start: 700, law: { act: '제정' } }] }),
      election: ver({ id: 'f2-v3f', name: '검사', tracks: T, events: [{ track: 'ta', title: '가', start: 700, election: { office: '의회' } }] }),
      unlaw: ver({ id: 'f2-v3g', name: '검사', patches: [{ target: 'other/e', set: { law: null } }] }),
      peopleList: ver({ id: 'f2-v3h', name: '검사', patches: [{ target: 'other/g', set: { people: ['가람'] } }] }),
      peopleText: ver({ id: 'f2-v1b', name: '검사', patches: [{ target: 'other/p', set: { people: '들 민족' } }] }),
      both: ver({ id: 'f2-v3i', name: '검사', tracks: T, periods: P, houses: [{ id: 'h', name: '가 가문' }], groups: [{ name: '들 무리', track: 'ta', start: 700 }] }),
    };
    const want = { plain: 1, v2: 2, group: 3, inst: 3, themes: 3, theme: 3, law: 3, election: 3, unlaw: 3, peopleList: 3, peopleText: 1, both: 3 };
    if (JSON.stringify(v) !== JSON.stringify(want)) bad(`형식 버전이 어긋남: ${JSON.stringify(v)}`);
    for (const p of packs) {
      const fv = HT.packToJSON(p).formatVersion;
      if (p.id === 'lantern-chronicle' && fv !== 3) bad(`견본 ${p.id}(단체 · 제도 · 주제를 씀)이 형식 3으로 나가지 않음 (${fv})`);
    }
    if (read(Object.assign({ id: 'f2-new', name: '검사', tracks: T }, { formatVersion: 3 })).warnings.some(w => /새로운 형식/.test(w.msg))) bad('formatVersion 3 파일에 "더 새로운 형식" 경고가 뜸');
    if (!read({ id: 'f2-newer', name: '검사', tracks: T, formatVersion: HT.F4.VERSION + 1 }).warnings.some(w => /새로운 형식/.test(w.msg))) bad(`formatVersion ${HT.F4.VERSION + 1} 파일에 경고가 없음`); // 4는 형식 4로 내려 읽음(리메이크 1a)
    /* ② 읽기 */
    const full = read({
      id: 'f2-full', name: '검사', tracks: T, periods: P,
      themes: [{ name: '길드 제도', color: '#c8b193' }, { id: 'tax', name: '세금 제도' }, { id: 'tax', name: '겹친 것' }],
      groups: [
        { id: 'g1', name: '옛 무리', type: '붕당', track: 'ta', within: 'ta:솔나라', start: 700, end: '미정', endHint: 760, power: [['집권', 710, 730, '메모'], ['실권', '미정', 750]] },
        { id: 'g2', name: '새 무리', type: '길드', track: 'ta', within: [{ polity: '솔나라', start: 760, end: 800 }], start: 760, from: [{ group: '옛 무리', how: '갈라짐' }, '옛 무리', { group: '새 무리' }, { group: '없는 무리', how: '모르는 말' }], people: '가람, 나래, 가람' },
        { id: 'g3', name: '두 나라 맹약', type: '동맹', track: 'ta', start: 800, end: 850, members: [{ polity: '솔나라', role: '맹주' }] },
        { name: '', track: 'ta', start: 1 },
      ],
      institutions: [
        { id: 'i1', theme: '조세제도', polity: { track: 'ta', polity: '솔나라' }, family: '고르게 나눔', spans: [['밭 나눔', null, 800], ['돈 거둠', 790], ['', 900]] },
        { id: 'i2', theme: 'tax', polity: 'tb:물나라', family: '고르게 나눔', spans: [{ name: '밭 나눔', start: 700, from: 'ta:솔나라' }] },
        { theme: 'law', polity: '솔나라', spans: [] },
      ],
      events: [
        { id: 'e1', track: 'ta', title: '법 반포', start: 760, theme: '법률, tax, 법률', law: { name: '새 법', act: '반포', articles: '제1조 가\n\n제2조 나' } },
        { id: 'e2', track: 'ta', title: '첫 선거', start: 900, theme: ['election', 'guild-x'], election: { office: '의회', results: [{ who: '푸른 모임', votes: '12,034', seats: 41, won: '당선' }, ['붉은 모임', 9870, 33], { votes: 5 }, { who: '그 밖', seats: '여섯' }] } },
        { id: 'e3', track: 'ta', title: '빈 규격', start: 901, law: {}, election: { results: [] } },
      ],
    });
    const fp = full.pack;
    if (!fp) bad(`읽기 검사 팩이 정규화되지 않음: ${full.errors.map(e => e.msg).join(' / ')}`);
    else {
      const w = full.warnings.map(x => x.msg).join(' | ');
      const g = id => fp.groups.find(x => x.id === id);
      if (fp.groups.length !== 3 || !full.errors.some(e => e.kind === 'groups' && /이름이 비어/.test(e.msg))) bad('이름 없는 단체가 오류로 빠지지 않음');
      if (g('g1').type !== 'faction' || g('g2').type !== '길드' || g('g3').type !== 'coalition') bad(`단체 종류(한국어 → id · 자유 글)가 어긋남: ${fp.groups.map(x => x.type)}`);
      if (JSON.stringify(g('g1').within) !== JSON.stringify([{ track: 'ta', polity: '솔나라' }]) || g('g2').within[0].start !== 760) bad(`있던 나라("트랙:이름" · 기간 줄)가 어긋남: ${JSON.stringify([g('g1').within, g('g2').within])}`);
      if (!g('g1').endUnknown || g('g1').end !== 760 || g('g1').power.length !== 2 || !g('g1').power[1].startUnknown) bad(`단체의 미정 · 집권 칸이 어긋남: ${JSON.stringify(g('g1'))}`);
      if (JSON.stringify(g('g2').from) !== JSON.stringify([{ group: '옛 무리', how: 'split' }, { group: '없는 무리' }]) || !/두 번 적혀/.test(w) || !/자기 자신/.test(w) || !/모르는 말/.test(w)) bad(`앞선 단체(한국어 · 겹침 · 자기 자신 · 모르는 방식)가 어긋남: ${JSON.stringify(g('g2').from)}`);
      if (g('g2').people.join() !== '가람,나래') bad('구성원(쉼표 글 · 겹침)이 어긋남');
      if (!/연합인데 구성 나라가 하나뿐/.test(w)) bad('구성 나라가 하나뿐인 연합에 경고가 없음');
      if (fp.themes.length !== 2 || fp.themes[0].id !== `theme-${HT.hash('길드 제도')}` || !/중복/.test(w)) bad(`주제 사전(이름으로 만든 id · 겹친 id)이 어긋남: ${JSON.stringify(fp.themes)}`);
      const i1 = fp.institutions.find(x => x.id === 'i1');
      const i2 = fp.institutions.find(x => x.id === 'i2');
      if (fp.institutions.length !== 2 || !full.errors.some(e => e.kind === 'institutions' && /칸\(spans\)이 하나도/.test(e.msg))) bad('칸 없는 제도가 오류로 빠지지 않음');
      if (i1.track !== 'ta' || i1.polity !== '솔나라' || i1.spans.length !== 2 || i1.spans[0].start != null || !/이름이 없어/.test(w) || !/겹칩니다/.test(w)) bad(`제도(나라 객체 · 첫 칸 시작 비움 · 이름 없는 칸 · 겹침)가 어긋남: ${JSON.stringify(i1)}`);
      if (i2.track !== 'tb' || JSON.stringify(i2.spans[0].from) !== JSON.stringify({ track: 'ta', polity: '솔나라' })) bad(`제도의 "트랙:이름" 나라 · 온 곳이 어긋남: ${JSON.stringify(i2)}`);
      const e = id => fp.events.find(x => x.id === id);
      if (e('e1').theme.join() !== '법률,tax' || e('e1').law.act !== 'enact' || e('e1').law.articles.length !== 2) bad(`사건의 주제 꼬리표 · 법 규격이 어긋남: ${JSON.stringify(e('e1'))}`);
      const res = e('e2').election.results;
      if (res.length !== 3 || res[0].votes !== 12034 || res[0].won !== true || res[1].seats !== 33 || res[2].seats != null || !/누구\(who\)가 없어/.test(w) || !/의석 "여섯"/.test(w)) bad(`선거 결과(쉼표 수 · 목록 꼴 · 빈 사람 · 읽을 수 없는 의석)가 어긋남: ${JSON.stringify(res)}`);
      if ('law' in e('e3') || 'election' in e('e3')) bad('빈 법 · 선거 규격이 칸으로 남음');
      /* ③ 왕복 */
      const json = HT.packToJSON(fp);
      const again = HT.normalizePack(JSON.parse(JSON.stringify(json)));
      if (!again.pack || canon(HT.packToJSON(again.pack)) !== canon(json)) bad('단체 · 제도 · 주제 · 법 · 선거의 왕복(정규화 → 내보내기 → 정규화)에서 자료가 달라짐');
      /* ④ 모델: 찾지 못한 나라 · 주제 · 단체, 같은 나라 · 같은 주제의 겹치는 제도 */
      const mm = HT.buildModel([fp, read({ id: 'f2-more', name: '검사 2', tracks: T, institutions: [{ id: 'j1', theme: '세금 제도', track: 'ta', polity: '솔나라', spans: [['겹치는 법', 795, 820]] }, { id: 'j2', theme: '없는 주제', polity: '없는 나라', spans: [['어딘가', 700, 750]] }, { id: 'j3', theme: 'law', polity: '없는 나라', spans: [['자리 없음']] }] }).pack], null);
      const gx = mm.groups.find(x => x.id === 'g2');
      if (!gx || gx.fromList[0].group !== mm.groups.find(x => x.id === 'g1') || !(mm.groups.find(x => x.id === 'g1').intoList || []).some(t => t.group === gx && t.how === 'split') || !gx.warnings.some(x => /없는 무리/.test(x))) bad('앞선 단체 · 뒤를 이은 단체 · 찾지 못한 단체 경고가 어긋남');
      const sol = mm.periods.find(p => p.uid === 'f2-full/pa');
      if (!sol || (sol.groupLinks || []).map(l => `${l.group.id}:${l.role}`).join() !== 'g1:within,g2:within,g3:member') bad(`나라 쪽 단체 역참조가 어긋남: ${sol && JSON.stringify((sol.groupLinks || []).map(l => [l.group.id, l.role]))}`);
      const jx = mm.institutions.find(x => x.id === 'j1');
      const ix = mm.institutions.find(x => x.id === 'i1');
      if (!ix || ix.themeId !== 'tax' || ix.themeName !== '세금 제도' || ix.spanList[0].start !== 600 || ix.spanList[1].end !== 1000) bad(`제도의 주제(DLC가 덮은 내장 주제) · 빈 경계(나라 시작 · 끝)가 어긋남: ${ix && JSON.stringify([ix.themeId, ix.themeName, ix.spanList.map(s => [s.start, s.end])])}`);
      if (!jx || !jx.warnings.some(x => /겹칩니다/.test(x))) bad('같은 나라 · 같은 주제의 제도끼리 겹치는 칸에 경고가 없음');
      const j2 = mm.institutions.find(x => x.id === 'j2');
      if (!j2 || !j2.warnings.some(x => /없는 나라/.test(x)) || !j2.warnings.some(x => /없는 주제/.test(x)) || !mm.themes.some(t => t.auto && t.name === '없는 주제')) bad('찾지 못한 나라 · 사전에 없는 주제의 경고 · auto 주제가 어긋남');
      if (mm.institutions.some(x => x.id === 'j3')) bad('자리를 정할 수 없는 제도가 모델에 들어감');
      if ((mm.institutionIndex.byFamily.get('tax|고르게 나눔') || []).length !== 2 || ix.sameFamily.length !== 1 || !(mm.institutionIndex.byPolity.get('f2-full/pa') || []).includes(ix)) bad('제도 색인(갈래 · 나라) · 같은 갈래가 어긋남');
      const e2 = mm.byUid.get('f2-full/e2');
      if (!e2 || e2.themeRefs.map(t => `${t.id}${t.auto ? '*' : ''}`).join() !== `election,theme-${HT.hash('guild-x')}*` || !(mm.themeEvents.get('election') || []).includes(e2)) bad(`사건의 주제 색인이 어긋남: ${e2 && JSON.stringify(e2.themeRefs)}`);
      if (mm.themes.slice(0, 8).map(t => t.id).join() !== 'system,faction,law,election,ideology,military,tax,selection') bad('주제 사전의 차례가 내장 뼈대 여덟부터가 아님');
      if (mm.byUid.get('f2-full/g1').kind !== 'group' || HT.itemWord(mm.byUid.get('f2-full/i1')) !== '제도') bad('단체 · 제도가 byUid · 부르는 말(ITEM_WORDS)에 없음');
      /* ⑤ 패치: 사건의 theme · law · election (사건에만), 단체 · 제도 고치기 · 숨기기 */
      const patch = read({
        id: 'f2-patch', name: '학설팩',
        patches: [
          { target: 'f2-full/e1', set: { law: null, theme: ['조세제도'], election: { office: '대표' } } },
          { target: 'f2-full/pa', set: { law: { act: '폐지' }, description: '시대 설명' } },
          { target: 'f2-full/g1', set: { power: [['집권', 715, 735]], type: '정당' } },
          { target: 'f2-full/i1', set: { spans: [['한 칸', null, null]], theme: ['law', 'tax'] } },
          { target: 'f2-full/g3', hide: true },
        ],
      });
      if (!patch.pack) bad(`패치 팩이 정규화되지 않음: ${patch.errors.map(e => e.msg).join(' / ')}`);
      else {
        const pm = HT.buildModel([fp, patch.pack], null);
        const pe = pm.byUid.get('f2-full/e1');
        if (!pe || pe.law || pe.election.office !== '대표' || pe.themeRefs.map(t => t.id).join() !== 'tax') bad(`사건 패치(법 떼기 · 선거 얹기 · 주제)가 어긋남: ${pe && JSON.stringify([pe.law, pe.election, pe.themeRefs])}`);
        const pp = pm.byUid.get('f2-full/pa');
        if (!pp || pp.law || pp.description !== '시대 설명') bad('시대를 가리킨 패치의 law가 버려지지 않거나 다른 칸이 빠짐');
        const pg = pm.byUid.get('f2-full/g1');
        if (!pg || pg.type !== 'party' || pg.powerSpans.length !== 1 || pg.powerSpans[0].start !== 715 || !pg.patchedBy) bad(`단체 패치가 어긋남: ${pg && JSON.stringify([pg.type, pg.powerSpans])}`);
        const pi = pm.byUid.get('f2-full/i1');
        if (!pi || pi.theme !== 'law' || pi.spanList.length !== 1 || pi.spanList[0].start !== 600 || pi.spanList[0].end !== 1000) bad(`제도 패치(주제 목록 → 첫 것 · 칸)가 어긋남: ${pi && JSON.stringify([pi.theme, pi.spanList])}`);
        if (pm.byUid.has('f2-full/g3') || (pm.byUid.get('f2-full/pa').groupLinks || []).some(l => l.group.id === 'g3')) bad('숨긴 단체가 모델 · 나라 역참조에 남음');
      }
    }
    /* ⑥ 견본(sample-lantern)의 모델 (--skip으로 견본을 뺐으면 건너뜀 — [64] · [66]과 같게: 옛 모델 해시를 볼 때) */
    if (model && !skipSamples.some(k => 'sample-lantern.json'.includes(k))) {
      const gs = (model.groups || []).filter(x => x.packId === 'lantern-chronicle');
      const is = (model.institutions || []).filter(x => x.packId === 'lantern-chronicle');
      // 견본 2.0.0: 단체 열하나(붕당 셋 · 정당 다섯 · 정권 하나 · 연합 하나 · 자유 글 종류 '길드' 하나 — 모르는 종류는 글 그대로) · 제도 일곱(불씨 둘 · 의회 셋 · 광학·연금 둘)
      if (gs.length !== 11 || is.length !== 7) bad(`견본의 단체 · 제도 수가 어긋남: ${gs.length} · ${is.length}`);
      if (gs.some(x => x.warnings.length) || is.some(x => x.warnings.length)) bad(`견본에 확인할 것이 있음: ${gs.concat(is).flatMap(x => x.warnings).join(' | ')}`);
      if (gs.map(x => x.type).sort().join() !== 'coalition,faction,faction,faction,party,party,party,party,party,regime,길드') bad(`견본의 단체 종류(붕당 셋 · 정당 다섯 · 정권 · 연합 · 자유 글 '길드')가 어긋남: ${gs.map(x => x.type)}`);
      if (is.map(x => x.themeId).sort().join() !== 'alchemy-optics,alchemy-optics,ember,ember,parliament,parliament,parliament' || is.some(x => (model.themes.find(t => t.id === x.themeId) || { auto: true }).auto)) bad(`견본의 제도가 DLC가 정의한 주제(불씨 · 의회 · 광학·연금)로 풀리지 않음: ${is.map(x => x.themeId)}`);
    }
    /* ⑦ 작업본: 비운 id는 읽기와 같은 값 · 견본을 열어 그대로 내보내도 같음 · 새 단체 · 남의 단체의 패치 */
    const D = HT.draft;
    for (const name of ['sample-lantern']) {
      const raw = JSON.parse(readFileSync(join(root, 'samples', `${name}.json`), 'utf8'));
      if (canon(HT.packToJSON(HT.normalizePack(raw).pack)) !== canon(HT.packToJSON(HT.normalizePack(D.clean(raw)).pack))) bad(`${name}: 작업본으로 열어 그대로 내보낸 파일이 원본과 다름`);
      const stripped = JSON.parse(JSON.stringify(raw));
      for (const k of ['groups', 'institutions', 'themes']) for (const x of stripped[k] || []) if (k !== 'themes' || x.name) delete x.id; // 이름 없이 id만 적은 줄(내장 주제 숨기기)은 그대로
      const want = HT.normalizePack(stripped).pack;
      const got = HT.normalizePack(D.clean(stripped)).pack;
      for (const k of ['groups', 'institutions', 'themes']) if ((want[k] || []).map(x => x.id).join() !== (got[k] || []).map(x => x.id).join()) bad(`${name}: id를 비운 ${k}의 작업본 id가 읽기와 다름`);
    }
    if (!D.LISTS.includes('groups') || !D.LISTS.includes('institutions') || !D.LISTS.includes('themes') || D.WORDS.groups !== '단체') bad('작업본의 목록에 단체 · 제도 · 주제가 없음');
    const dr = D.blank({ id: 'f2-draft', name: '검사' });
    dr.tracks.push({ id: 'ta', name: '가 땅' });
    const gid = D.addItem(dr, 'group', { name: '들 무리', type: 'faction', track: 'ta', start: 700, end: undefined, within: '솔나라', power: [{ name: '집권', start: 710 }], people: undefined, description: '' });
    const iid = D.addItem(dr, 'institution', { theme: 'tax', polity: '솔나라', spans: [{ name: '밭 나눔' }], description: '' });
    if (!/^gr-/.test(gid) || !/^in-/.test(iid) || dr.groups.length !== 1 || dr.institutions.length !== 1 || 'description' in dr.groups[0] || 'people' in dr.groups[0]) bad(`작업본에 단체 · 제도 넣기가 어긋남: ${JSON.stringify([gid, iid, dr.groups, dr.institutions])}`);
    const dn = HT.normalizePack(dr);
    if (!dn.pack || dn.errors.length || HT.packToJSON(dn.pack).formatVersion !== 3) bad(`넣은 단체 · 제도가 검사를 통과하지 못하거나 형식 3이 아님: ${dn.errors.map(e => e.msg).join(' / ')}`);
    if (fp) {
      const baseM = HT.buildModel([fp], null);
      const orig = baseM.byUid.get('f2-full/g1');
      const obj = { name: orig.name, type: orig.type, track: orig.track, start: orig.start, end: orig.end, endUnknown: orig.endUnknown, within: orig.within, power: [{ name: '집권', start: 712, end: 730, note: '메모' }].concat(orig.power.slice(1)), from: undefined, people: undefined, members: undefined, event: undefined, color: undefined, description: '', note: '' };
      const pd = D.blank({ id: 'f2-patcher', name: '고치는 팩' });
      const made = D.patchForeign(pd, orig, obj);
      if (!made || JSON.stringify(Object.keys(made.set)) !== JSON.stringify(['power'])) bad(`남의 단체를 고친 패치가 바뀐 칸(power)만 담지 않음: ${made && JSON.stringify(made.set)}`);
      const same = D.patchForeign(D.blank({ id: 'f2-p2', name: '고치는 팩' }), orig, Object.assign({}, obj, { power: orig.power }));
      if (same) bad(`고치지 않은 남의 단체에 패치가 생김: ${JSON.stringify(same.set)}`);
      const oi = baseM.byUid.get('f2-full/i1');
      const sameInst = D.patchForeign(D.blank({ id: 'f2-p3', name: '고치는 팩' }), oi, { theme: oi.theme, track: oi.track, polity: oi.polity, family: oi.family, spans: oi.spans, description: '' });
      if (sameInst) bad(`고치지 않은 남의 제도에 패치가 생김(모델이 채운 트랙 · 기간이 자료로 굳음): ${JSON.stringify(sameInst.set)}`);
    }
    /* ⑧ 폼 · 메이커 표 */
    for (const k of ['group', 'institution']) {
      const F = HT.FORMS[k];
      if (!F || !F.nameKey || typeof F.fresh !== 'function' || typeof F.filterKeys !== 'function' || F.add === false || F.key) bad(`폼 HT.FORMS.${k}의 설정이 어긋남 (추가 메뉴에 단축키 없이 나와야 함)`);
    }
    if (HT.FORMS.group && HT.FORMS.group.word !== '단체') bad("단체 폼의 부르는 말이 '단체'가 아님 (추가 메뉴 '＋ 단체 추가')");
    if (HT.FORMS.institution && HT.FORMS.institution.word !== '제도') bad("제도 폼의 부르는 말이 '제도'가 아님 (추가 메뉴 '＋ 제도 추가')");
    const evHtml = HT.FORMS.event.html({ tracks: [], categories: [] });
    if (!/data-adv="lens"/.test(evHtml) || !/name="lawAct"/.test(evHtml) || !/data-el-results/.test(evHtml) || !/name="themes"/.test(evHtml)) bad('사건 폼에 주제 · 법 · 선거 구역이 없음');
    const gHtml = HT.FORMS.group.html({ tracks: [{ id: 'ta', name: '가 땅' }] });
    for (const sel of ['name="type"', 'data-gp-within', 'data-gp-from', 'data-gp-power', 'name="people"', 'data-gp-members', 'name="event"', 'name="useColor"', 'name="description"', 'name="note"', 'name="certainty"', 'name="wiki"']) if (!gHtml.includes(sel)) bad(`단체 폼에 칸 ${sel}이 없음 (형식에 있는 칸 = 폼에 있는 칸)`);
    const iHtml = HT.FORMS.institution.html({ tracks: [{ id: 'ta', name: '가 땅' }] });
    for (const sel of ['name="theme"', 'name="polity"', 'name="track"', 'name="family"', 'data-inst-spans', 'name="description"', 'name="wiki"']) if (!iHtml.includes(sel)) bad(`제도 폼에 칸 ${sel}이 없음`);
    if (/placeholder="[^"]*(예:|예시)/.test(gHtml + iHtml + evHtml)) bad('입력 칸에 예시 글(placeholder)이 있음');
    const kit = HT.makerKit;
    if (!kit) bad('메이커 도구(HT.makerKit)가 없음');
    else {
      if (!kit.itemLists().includes('groups') || !kit.itemLists().includes('institutions') || kit.kindOfList('groups') !== 'group' || kit.kindOfList('institutions') !== 'institution' || kit.listWord('groups') !== '단체') bad('메이커의 항목 목록(itemLists · kindOfList)에 단체 · 제도가 없음');
      const BT = kit.BASE_TABLES;
      if (!BT.themes || BT.themes.builtin().length !== 8 || !BT.groups || BT.groups.form !== 'group' || !BT.institutions || BT.institutions.form !== 'institution') bad('바탕 자료에 주제 표 · 단체 · 제도 목록이 없음');
      else {
        const dt = { themes: [{ id: 'guild', name: '길드' }], events: [{ id: 'e', theme: ['길드', 'tax'] }, { id: 'f', theme: '길드, law' }], institutions: [{ id: 'i', theme: '길드' }], patches: [{ target: 'x/y', set: { theme: ['길드'] } }] };
        const users = kit.findUsers(dt, BT.themes, dt.themes[0]);
        const n = kit.renameRefs(dt, BT.themes, 'name', '길드', '모임 제도');
        if (users.length !== 4 || n !== 4 || dt.events[0].theme.join() !== '모임 제도,tax' || dt.events[1].theme !== '모임 제도, law' || dt.institutions[0].theme !== '모임 제도' || dt.patches[0].set.theme[0] !== '모임 제도') bad(`주제 이름 바꾸기의 쓰는 곳 · 따라 바꾸기가 어긋남: ${users.length} · ${n} · ${JSON.stringify(dt)}`);
        const tr = { tracks: [{ id: 'ta' }], groups: [{ id: 'g', track: 'ta', within: 'ta:솔나라', members: [{ track: 'ta', polity: '가' }, 'ta:나'] }], institutions: [{ id: 'i', polity: 'ta:솔나라', spans: [{ from: { track: 'ta', polity: '가' } }, { from: 'ta:나' }] }] };
        const m2 = kit.renameRefs(tr, BT.tracks, 'id', 'ta', 'tz');
        if (tr.groups[0].track !== 'tz' || tr.groups[0].within !== 'tz:솔나라' || tr.groups[0].members[0].track !== 'tz' || tr.groups[0].members[1] !== 'tz:나' || tr.institutions[0].polity !== 'tz:솔나라' || tr.institutions[0].spans[0].from.track !== 'tz' || tr.institutions[0].spans[1].from !== 'tz:나') bad(`트랙 id를 바꿨는데 단체 · 제도의 트랙 참조가 따라가지 않음: ${m2} · ${JSON.stringify(tr)}`);
      }
      if (typeof kit.lensChecks !== 'function') bad('메이커 검사(HT.makerKit.lensChecks)가 없음');
      else if (fp) {
        const lp = read({ id: 'f2-lc', name: '검사', tracks: T, groups: [{ id: 'lg', name: '떠돈 무리', track: 'ta', start: 700, within: '없는 나라' }], institutions: [{ id: 'li', theme: '없는 주제', polity: '없는 나라', spans: [['자리 없음']] }], events: [{ id: 'le', track: 'ta', title: '주제 모름', start: 700, theme: '아무 주제' }] }).pack;
        const lm = HT.buildModel([lp], null);
        const ws = kit.lensChecks(lp, lm, { groups: [{ id: 'lg' }], institutions: [{ id: 'li' }], events: [{ id: 'le' }] }).map(x => `${x.kind}#${x.index}`);
        if (ws.join() !== 'groups#0,institutions#0,events#0') bad(`메이커 검사(단체 · 제도 · 사건의 주제)가 어긋남: ${ws.join()}`);
      }
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [66] 형식 버전 3 — 이름 목록 · 성씨 · 지명 · 사람 잇기 · 자리 이음 · 혈연 (2026-10-12 연표 확장 10건 F1 — DLC-형식.md의 '이름 목록' ~ '혈연' 절):
   ① 견본(sample-lantern)은 오류 0 · 경고 0 · 왕복 같음 · 형식 3, 기본팩은 3이 아님 · 읽는 버전 3 · 더 새로운 버전(4)에는 경고
   ② 새 열쇠 · 칸을 하나씩만 쓴 파일이 3으로 나감(패치가 그 칸을 비우는 null · []도) · 옛 칸만 쓴 파일은 그대로
   ③ "미상"과 비움의 구별이 파일 꼴(kinUnknown · howUnknown · fromUnknown · whoUnknown)로 남고 왕복에서도 같음 · 낱말 → id · 자유 글 · 언어 꼬리표의 가벼운 꼴 검사
   ④ 모델: 도읍 city의 지명 id → 지명 이름(같은 도시는 같은 이름) · 지명 · 성씨를 저절로 모음 · 사람 잇기(두 나라 · 다시 오름 · 미상) · lineageOf · familyOf ·
      관계와 혈연이 어긋나면 · 못 찾은 사람 · 고리는 경고(model.peopleWarnings)
   ⑤ 패치로 이름 · 장소 · 부모를 고치거나 비움 · 메이커: 남의 나라를 열어 그대로 저장하면 패치 없음 · 지명 id를 바꾸면 도읍 · 사건 장소가 따라감 */
{
  const bad = msg => out.problems.push(`형식 3 이름 · 계보: ${msg}`);
  try {
    const ver = raw => {
      const r = HT.normalizePack(Object.assign({ format: HT.FORMAT, formatVersion: 3, id: 'smoke-f1', name: '검사', tracks: [{ id: 't', name: '가 땅' }] }, raw));
      return r.pack ? HT.packToJSON(r.pack).formatVersion : `오류: ${r.errors.map(e => e.msg).join(' / ')}`;
    };
    /* ① 견본 · 읽는 버전 */
    if (HT.FORMAT_VERSION !== 3 || HT.FORMAT_VERSION_V3 !== 3 || !(HT.NEW_FORMAT_KEYS_V3 || []).length) bad('읽는 형식 버전이 3이 아니거나 버전 3의 열쇠 목록이 비어 있음');
    const mine = ['lantern-chronicle'].filter(() => !skipSamples.some(k => 'sample-lantern.json'.includes(k))); // 견본 sample-lantern — --skip으로 뺀 견본은 보지 않음 (옛 모델 해시를 볼 때)
    for (const id of mine) {
      const row = out.packs.find(p => p.id === id);
      if (!row) bad(`견본 ${id}이(가) 읽히지 않음`);
      else if (row.errors || row.warnings || !row.roundtrip) bad(`견본 ${id}: 오류 ${row.errors} · 경고 ${row.warnings} · 왕복 ${row.roundtrip ? '같음' : '다름'}`);
      const p = packs.find(q => q.id === id);
      if (p && HT.packToJSON(p).formatVersion !== 3) bad(`견본 ${id}이(가) 형식 3으로 나가지 않음`);
    }
    for (const p of packs) if (!FORMAT3_SAMPLES.includes(p.id) && p.id !== 'east-asia-base' && HT.usesFormatV3(HT.packToJSON(p))) bad(`옛 견본 ${p.id}이(가) 형식 3의 칸을 쓴다고 나옴`);
    { // 기본팩은 제 문화권(spheres · 트랙의 sphere — 2026-10-23)만으로 형식 3 — 그것을 빼면 형식 3의 칸을 쓰지 않아야 함
      const b = packs.find(p => p.id === 'east-asia-base');
      const j = b && HT.packToJSON(b);
      if (!j || !HT.usesFormatV3(j)) bad('기본팩이 형식 3(문화권)이 아님');
      else { delete j.spheres; for (const t of j.tracks) delete t.sphere; if (HT.usesFormatV3(j)) bad('기본팩이 문화권 말고도 형식 3의 칸을 씀'); }
    }
    const sample = packs.find(p => p.id === 'lantern-chronicle');
    if (sample) {
      const again = HT.normalizePack(HT.packToJSON(sample));
      if (again.warnings.some(w => /새로운 형식/.test(w.msg))) bad('형식 3인 파일을 읽을 때 "더 새로운 형식" 경고가 뜸');
      if (!HT.normalizePack(Object.assign(HT.packToJSON(sample), { formatVersion: HT.F4.VERSION + 1 })).warnings.some(w => /새로운 형식/.test(w.msg))) bad(`형식 ${HT.F4.VERSION + 1}인 파일에 "더 새로운 형식" 경고가 없음`); // 4는 형식 4로 내려 읽음(리메이크 1a)
    }
    /* ② 새 열쇠 · 칸 하나씩 */
    const P = extra => Object.assign({ id: 'p', track: 't', name: '가 나라', start: 500, end: 600 }, extra);
    const cases = [
      ['시대의 이름 목록', { periods: [P({ names: [{ text: 'Ga', kind: '로마자' }] })] }],
      ['지도자의 이름 목록', { periods: [P({ leaders: [{ name: '첫', start: 500, names: ['원래 이름'] }] })] }],
      ['연호의 이름 목록', { periods: [P({ eras: [{ name: '해', start: 500, names: [{ text: 'Hae' }] }] })] }],
      ['지도자의 사람', { periods: [P({ leaders: [{ name: '첫', start: 500, person: '어느 사람' }] })] }],
      ['내각의 사람', { periods: [P({ cabinets: [{ name: '회의', start: 500, person: '어느 사람' }] })] }],
      ['자리 이음', { periods: [P({ leaders: [{ name: '첫', start: 500 }, { name: '둘', start: 550, accession: { how: '추대' } }] })] }],
      ['지도자의 부모', { periods: [P({ leaders: [{ name: '첫', start: 500, parents: [{ who: '미상', as: '부' }] }] })] }],
      ['지도자의 배우자', { periods: [P({ leaders: [{ name: '첫', start: 500, spouses: ['어느 사람'] }] })] }],
      ['인물의 부모', { figures: [{ track: 't', name: '갑', birth: 500, parents: [{ who: '을', as: '모' }] }] }],
      ['인물의 이름 목록', { figures: [{ track: 't', name: '갑', birth: 500, names: [{ text: 'Gap' }] }] }],
      ['사건의 장소', { events: [{ track: 't', title: '일', start: 500, place: '어느 나루' }] }],
      ['사건의 이름 목록', { events: [{ track: 't', title: '일', start: 500, names: [{ text: 'Il' }] }] }],
      ['가문의 이름 목록', { houses: [{ name: '가 가문', names: [{ text: 'Ga-ga' }] }] }],
      ['왕조의 이름 목록', { periods: [P()], dynasties: [{ track: 't', name: '가 왕조', start: 500, end: 600, polities: '가 나라', names: [{ text: 'Ga-wangjo' }] }] }],
      ['성씨 사전', { surnames: [{ name: '가' }] }],
      ['지명 사전', { places: [{ name: '어느 나루' }] }],
      ['지명 문서', { periods: [P()], documents: { 'place:pl-x': '== 글 ==' } }],
      ['패치의 이름 목록', { patches: [{ target: '딴팩/딴것', set: { names: [{ text: 'X' }] } }] }],
      ['패치로 이름 목록을 비움(null)', { patches: [{ target: '딴팩/딴것', set: { names: null } }] }],
      ['패치로 장소를 비움(null)', { patches: [{ target: '딴팩/딴것', set: { place: null } }] }],
      ['패치로 부모를 비움([])', { patches: [{ target: '딴팩/딴것', set: { parents: [] } }] }],
      ['패치의 지도자 사람', { patches: [{ target: '딴팩/딴것', set: { leaders: [{ name: '첫', start: 500, person: '갑' }] } }] }],
    ];
    for (const [what, raw] of cases) if (ver(raw) !== 3) bad(`${what}만 쓴 파일이 형식 3으로 나가지 않음 (${ver(raw)})`);
    if (ver({ periods: [P({ leaders: [{ name: '첫', start: 500 }] })] }) !== 1) bad('옛 칸만 쓴 파일이 형식 1로 나가지 않음');
    if (ver({ periods: [P({ house: '가 가문' })] }) !== 2) bad('형식 2의 칸만 쓴 파일이 형식 2로 나가지 않음');
    /* ③ 미상과 비움 · 낱말 · 자유 글 · 언어 꼬리표 */
    {
      const r = HT.normalizePack({ format: HT.FORMAT, formatVersion: 3, id: 'smoke-unk', name: '검사', tracks: [{ id: 't', name: 'T' }], periods: [P({ leaders: [
        { name: '첫', start: 500 },
        { name: '둘', start: 520, accession: { kin: '미상', how: '' } },
        { name: '셋', start: 540, accession: '미상' },
        { name: '넷', start: 560, accession: { kin: '아우', how: '빛의 의식', from: '?' }, parents: [{ who: '모름', as: '부' }, { who: '첫', as: '양부' }, { who: '가 나라:첫@500', as: '후손', gen: 2 }] },
        { name: '다섯', start: 580, accession: { kin: '', how: '' } },
      ] })] });
      const L = r.pack ? r.pack.periods[0].leaders : [];
      const json = r.pack ? HT.packToJSON(r.pack) : null;
      if (!r.pack || r.warnings.length) bad(`미상 검사용 팩: ${r.errors.concat(r.warnings).map(e => e.msg).join(' / ')}`);
      else {
        if (JSON.stringify(L[1].accession) !== '{"kinUnknown":true}') bad(`관계만 미상(방식은 비움)이 { kinUnknown: true }가 아님: ${JSON.stringify(L[1].accession)}`);
        if (JSON.stringify(L[2].accession) !== '{"kinUnknown":true,"howUnknown":true}') bad('자리 이음 "미상" 한 글이 관계 · 방식 모두 미상이 아님');
        if (L[3].accession.kin !== 'younger-brother' || L[3].accession.how !== '빛의 의식' || L[3].accession.fromUnknown !== true || 'from' in L[3].accession) bad(`낱말 → id · 자유 글 · 앞 지도자 미상이 맞지 않음: ${JSON.stringify(L[3].accession)}`);
        if (!L[3].parents[0].whoUnknown || 'who' in L[3].parents[0] || L[3].parents[1].as !== 'adoptive-father' || JSON.stringify(L[3].parents[2].who) !== '{"polity":"가 나라","leader":"첫","start":500}' || L[3].parents[2].gen !== 2) bad(`부모의 미상 · 관계 낱말 · 지도자 칸 참조 · 몇 대손이 맞지 않음: ${JSON.stringify(L[3].parents)}`);
        if ('accession' in L[4]) bad('비운 자리 이음(관계 · 방식 모두 빈 글)이 칸에 남음 — 비움은 적지 않은 것');
        const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
        if (!back.pack || canon(HT.packToJSON(back.pack)) !== canon(json)) bad('미상 · 비움을 적은 파일의 왕복이 다름');
        if (json.formatVersion !== 3) bad('미상을 적은 자리 이음 파일이 형식 3이 아님');
      }
      const w = [];
      HT.readNames([{ text: '가', lang: '한국어' }, { text: '나', lang: 'x-moon-Latn' }, { text: '' }, { text: '다', start: 600, end: 500 }], m => w.push(m));
      if (!w.some(m => /한국어/.test(m)) || w.some(m => /x-moon-Latn/.test(m)) || !w.some(m => /비어 있어/.test(m)) || !w.some(m => /앞서/.test(m))) bad(`이름 목록의 가벼운 검사(언어 꼬리표 꼴 · 빈 글 · 거꾸로 된 기간)가 맞지 않음: ${w.join(' / ')}`);
      if (HT.readNames([{ text: '가', lang: '한국어' }])[0].lang !== '한국어') bad('꼴에 맞지 않는 언어 꼬리표를 버림 (적은 그대로 두어야 함)');
      if (HT.readNames([{ text: '가', kind: '옛이름' }])[0].kind !== 'former' || HT.readNames([{ text: '가', kind: '높여 부른 이름' }])[0].kind !== '높여 부른 이름') bad('이름의 종류: 낱말 → id · 자유 글이 맞지 않음');
      const nm = HT.readNames([{ text: '가', start: '미정', startHint: 480, end: '음력 0520-03-01' }])[0];
      if (!nm.startUnknown || nm.start !== 480 || !nm.endAt) bad(`이름의 기간: 미정 · 배치용 연도 · 날짜 글이 남지 않음 ${JSON.stringify(nm)}`);
    }
    /* ④ 모델 */
    if (model && mine.length === 1) {
      /* 견본 sample-lantern(도읍 · 사건 장소는 모두 지명 이름으로 적음 — 지명 id로 적은 도읍 · 저절로 생기는 지명 · 성씨는 견본에 없음) */
      const hoban = HT.placeOf(model, 'pl-hoban');
      if (!hoban || hoban !== HT.placeOf(model, '호반성') || hoban.uses.filter(u => u.role === 'capital').length !== 6 || hoban.parentId !== 'pl-hayeon') bad('지명: id · 이름으로 같은 지명 · 도읍 여섯 곳(이름으로 적음) · 위 구역이 맞지 않음');
      if ((model.places || []).some(p => p.auto && !p.uses.length && !(model.places || []).some(q => q.parentId === p.id))) bad('쓰인 곳 없는 지명이 저절로 생김');
      const on = (model.surnames || []).find(s => s.id === 'sn-on');
      if (!on || !on.houses.includes('h-ondam') || (model.surnames || []).some(s => s.auto)) bad('성씨: 사전의 성(이름으로 적은 가문의 성)이 한 성씨로 모이지 않거나 사전에 있는 성이 저절로 생김');
      const lin = HT.lineageOf(model, 'lantern-chronicle/p-empire');
      const R = lin ? lin.rulers : [];
      if (R.length !== 10) bad('lineageOf: 설원 제국 지도자 열이 아님');
      else {
        if (R[1].accession.kin !== 'son' || R[1].accession.from !== R[0].person || !R[1].accession.fromAuto || R[1].accession.fromRuler !== 0) bad('lineageOf: 비운 앞 지도자가 바로 앞 칸이 아님');
        if (R[8].person !== R[6].person || !R[8].restored || R[8].accession.how !== 'restoration') bad('lineageOf: 다시 오른 지도자(두갈래 황제 — 같은 사람의 두 칸)가 맞지 않음');
        if (R[0].elsewhere.length !== 1 || R[0].elsewhere[0].name !== '설족 칸국' || R[9].elsewhere.length !== 1 || R[9].elsewhere[0].name !== '북설 칸국') bad('lineageOf: 두 나라를 다스린 같은 사람(솔가 · 끝눈)이 맞지 않음');
      }
      const coral = HT.lineageOf(model, 'lantern-chronicle/p-coral');
      if (!coral || !coral.rulers[2].accession.kinUnknown || !coral.rulers[2].accession.howUnknown || coral.rulers[2].accession.kin) bad('lineageOf: 자리 이음 미상(진주왕)이 맞지 않음');
      const league = HT.lineageOf(model, 'lantern-chronicle/p-league');
      if (!league || league.rulers[6].person.figure?.id !== 'f-baul-mir' || league.rulers[8].person !== league.rulers[6].person || !league.rulers[8].restored || !league.rulers[10].restored) bad('lineageOf: 인물로 이어진 칸 · 세 번 오른 도선장(바울 미르)이 맞지 않음');
      const uni = HT.lineageOf(model, 'lantern-chronicle/p-union');
      const rev = HT.lineageOf(model, 'lantern-chronicle/p-revival');
      if (!uni || !rev || uni.rulers[0].accession.from !== rev.rulers[11].person || uni.rulers[0].accession.fromAuto || uni.rulers[0].person !== rev.rulers[11].person) bad('lineageOf: "나라:지도자@해"로 적은 앞 지도자(합등왕 — 본인)가 그 칸의 사람으로 풀리지 않음');
      /* 견본 2.0.0: 부흥왕 칸이 인물 휘 도윤(가문 휘씨 — 적은 가문)에 이어지고 남등왕 휘 시온이 청림지파의 파조라, 부흥왕 ~ 명휘왕이 남파 밖(휘씨 · 청림지파)으로 감 —
         예전과 같은 그림(남강군 → 24대 뒤 부흥왕 · 명휘왕 ↔ 단목 해랑)을 보려고 남파의 아래 파(청림지파)까지 넣어 봄 */
      const fam = HT.familyOf(model, 'h-hwi-nam', { branches: true });
      const N = fam ? Object.fromEntries(fam.nodes.map(n => [n.name, n])) : {};
      if (!fam || !N['명휘왕'] || !N['명휘왕'].member || !N['단목 해랑'] || N['단목 해랑'].member || N['단목 해랑'].generation !== N['명휘왕'].generation || !N['휘 은하'] || N['휘 은하'].member || !N['휘 남강군'] || !N['휘 도윤'] || N['휘 도윤'].generation - N['휘 남강군'].generation !== 24 || !fam.nodes.some(n => n.unknown)) bad(`familyOf: 사람 · 가문 안팎 · 세대(몇 대 건너뜀 · 배우자 같은 세대) · 미상 자리가 맞지 않음 ${JSON.stringify(fam && fam.nodes.map(n => [n.name, n.member, n.generation]))}`);
      if (!fam || fam.edges.filter(e => e.type === 'parent').length !== 18 || !fam.edges.some(e => e.type === 'parent' && e.as === 'ancestor' && e.gen === 24) || fam.edges.filter(e => e.type === 'spouse').length !== 2) bad('familyOf: 선(부모 → 자식 열여덟 · 24대 조상 · 배우자 둘)이 맞지 않음');
      if ((model.peopleWarnings || []).some(w => w.packId === 'lantern-chronicle')) bad(`견본에 사람 · 계보 경고가 남음: ${model.peopleWarnings.map(w => w.msg).join(' / ')}`);
    }
    {
      /* 견본에 없는 꼴 — 도읍 city에 적은 지명 id · 사전에 없는 도읍의 지명 · id로 적은 성 · 사전에 없는 성 (작은 검사 팩) */
      const pr = HT.normalizePack({ format: HT.FORMAT, formatVersion: 3, id: 'smoke-pl', name: '검사', tracks: [{ id: 't', name: 'T' }], places: [{ id: 'pl-a', name: '가 나루' }], surnames: [{ id: 'sn-ga', name: '가' }], houses: [{ id: 'h1', name: '가씨', surname: 'sn-ga' }, { id: 'h2', name: '하씨', surname: '하' }], periods: [P({ capitals: [['pl-a', 500, 550], ['나 성', 550]] })], events: [{ id: 'e', track: 't', title: '일', start: 520, place: '가 나루' }] });
      const pm = pr.pack && HT.buildModel([pr.pack], null);
      const pp = pm && pm.byUid.get('smoke-pl/p');
      if (!pp || pp.capitals[0].city !== '가 나루') bad('도읍 city에 적은 지명 id가 모델에서 지명 이름으로 풀리지 않음');
      const pa = pm && HT.placeOf(pm, 'pl-a');
      if (!pa || pa !== HT.placeOf(pm, '가 나루') || pa.uses.length !== 2 || pa.uses.filter(u => u.role === 'capital').length !== 1) bad('지명: id로 적은 도읍과 이름으로 적은 사건 장소가 한 지명으로 모이지 않음');
      if (!pm || !pm.places.some(x => x.auto && x.name === '나 성' && x.uses.length === 1)) bad('사전에 없는 도읍의 지명이 저절로 생기지 않음');
      const sg = pm && pm.surnames.find(s => s.id === 'sn-ga');
      if (!sg || !sg.houses.includes('h1') || !pm.surnames.some(s => s.auto && s.name === '하' && s.houses.includes('h2'))) bad('성씨: id로 적은 성이 사전의 성으로 · 사전에 없는 성이 저절로 모이지 않음');
    }
    {
      /* 어긋남 · 못 찾음 · 고리 */
      const r = HT.normalizePack({ format: HT.FORMAT, formatVersion: 3, id: 'smoke-kin', name: '검사', tracks: [{ id: 't', name: 'T' }], periods: [P({ leaders: [
        { name: '첫', start: 500 },
        { name: '둘', start: 520, accession: { kin: '아들' }, parents: [{ who: '남', as: '부' }] },
        { name: '셋', start: 530, accession: { kin: '본인' } },
        { name: '넷', start: 540, parents: [{ who: '다섯', as: '부' }] },
        { name: '다섯', start: 550, parents: [{ who: '넷', as: '부' }] },
        { name: '남', start: 560, parents: [{ who: '딴 사람', as: '부' }] },
      ] })] });
      const km = HT.buildModel([r.pack], null);
      const msgs = km.peopleWarnings.map(w => w.msg).join(' / ');
      if (!/"둘".*'아들'.*어긋납니다/.test(msgs)) bad(`관계(아들)와 부모가 어긋나는데 경고가 없음: ${msgs}`);
      if (!/'본인'.*다른 사람/.test(msgs)) bad('관계가 본인인데 다른 사람이면 경고가 없음');
      if (!/"딴 사람".*찾지 못했습니다/.test(msgs)) bad('못 찾은 부모에 경고가 없음');
      if (!/고리/.test(msgs)) bad('혈연의 고리에 경고가 없음');
      if (km.peopleWarnings.some(w => w.packId !== 'smoke-kin' || w.list !== 'periods' || w.id !== 'p')) bad('사람 · 계보 경고가 그 항목(검사 창의 줄)을 가리키지 않음');
    }
    /* ⑤ 패치 · 메이커 */
    {
      const baseRaw = { format: HT.FORMAT, formatVersion: 3, id: 'smoke-f1base', name: '바탕', tracks: [{ id: 't', name: 'T' }],
        periods: [P({ names: [{ text: 'Ga' }], leaders: [{ name: '첫', start: 500, person: '갑', names: [{ text: 'Cheot' }], parents: [{ who: '미상' }] }] })],
        figures: [{ id: 'f', track: 't', name: '갑', birth: 480, parents: [{ who: '을', as: '부' }] }, { id: 'g', track: 't', name: '을', birth: 450 }],
        events: [{ id: 'e', track: 't', title: '일', start: 520, place: '나루', names: [{ text: 'Il' }] }] };
      const bp = HT.normalizePack(baseRaw).pack;
      const patch = HT.normalizePack({ format: HT.FORMAT, formatVersion: 3, id: 'smoke-f1patch', name: '고침', patches: [
        { target: 'smoke-f1base/p', set: { names: null } },
        { target: 'smoke-f1base/e', set: { place: null, names: [{ text: 'Il-2', kind: '약칭' }] } },
        { target: 'smoke-f1base/f', set: { parents: [] } },
      ] });
      if (!patch.pack || patch.warnings.length || HT.packToJSON(patch.pack).formatVersion !== 3) bad(`형식 3의 칸을 고치는 패치가 읽히지 않거나 형식 3이 아님: ${patch.errors.concat(patch.warnings).map(e => e.msg).join(' / ')}`);
      else {
        const pm = HT.buildModel([bp, patch.pack], null);
        const p = pm.byUid.get('smoke-f1base/p');
        const e = pm.byUid.get('smoke-f1base/e');
        const f = pm.byUid.get('smoke-f1base/f');
        if (HT.namesSplit(p.names).main.length || e.place || e.names[0].kind !== 'short' || (f.parents || []).length) bad('패치로 이름 · 장소를 비우거나 바꾸고 부모를 비운 것이 모델에 반영되지 않음');
        if (HT.personOf(pm, f).parents.some(q => !q.node.unknown)) bad('패치로 비운 부모(을)가 사람 잇기에 남음'); // 같은 사람의 지도자 칸에 적힌 "미상" 부모는 남음
      }
      /* 메이커: 남의 나라를 열어 그대로 저장하면 패치 없음(폼이 내놓는 꼴 흉내 — 칸 목록은 모델의 것 그대로) · 지도자의 사람만 고치면 지도자 목록 패치 */
      const bm = HT.buildModel([bp], null);
      const item = bm.byUid.get('smoke-f1base/p');
      const d = HT.draft.blank({ id: 'smoke-f1draft', name: '고침' });
      const form = { name: item.name, names: item.names, leaders: HT.cellsFileForm(item.leaders).map(c => { const { houseId, houseName, houseColor, houseAuto, dynastyAuto, rankAuto, ...o } = c; return o; }) };
      if (HT.draft.patchForeign(d, item, form)) bad('남의 나라를 열어 그대로 저장했는데 패치가 생김 (이름 목록 · 지도자의 사람 칸)');
      form.leaders[0] = Object.assign({}, form.leaders[0], { person: '을' });
      const made = HT.draft.patchForeign(d, item, form);
      if (!made || !made.set.leaders || made.set.leaders[0].person !== '을' || HT.packToJSON(HT.normalizePack(Object.assign({}, d, { tracks: [] })).pack).formatVersion !== 3) bad('지도자의 사람만 고쳤는데 지도자 목록 패치가 생기지 않거나 형식 3이 아님');
      /* 바탕 자료: 지명 · 성씨의 쓰는 곳과 id 바꾸기 */
      const kit = HT.makerKit;
      if (kit && kit.BASE_TABLES.places && kit.BASE_TABLES.surnames) {
        /* 견본 sample-lantern의 호반성(2.0.0: 도읍 여섯 · 사건 열(장소 · 조약의 맺은 곳) · 지도 하나의 지명 글 — 모두 이름으로 적음 · 지명 문서 place:pl-hoban)에, id로 적은 도읍 하나를 더해 봄.
           쓰는 곳은 줄 수로 17(시대 6 · 사건 10 · 지도 1 — 더한 도읍은 이미 이름으로 쓰는 연합 왕국 줄), 이름을 바꾸면 칸 수로 20(도읍 6 · 사건 장소 10 · 조약의 맺은 곳 3 · 지도 1) */
        const dr = HT.draft.clean(JSON.parse(readFileSync(join(root, 'samples', 'sample-lantern.json'), 'utf8')));
        dr.periods.find(p => p.id === 'p-union').capitals.push({ city: 'pl-hoban', start: 1500, role: 'secondary' });
        const pl = dr.places.find(x => x.id === 'pl-hoban');
        const users = kit.findUsers(dr, kit.BASE_TABLES.places, pl);
        if (users.length !== 17) bad(`지명의 쓰는 곳(도읍 id로 · 이름으로 · 사건 장소 · 지도)이 17이 아님: ${users.length}`);
        const n = kit.renameRefs(dr, kit.BASE_TABLES.places, 'id', 'pl-hoban', 'pl-hb');
        const un = dr.periods.find(p => p.id === 'p-union');
        if (n !== 2 || un.capitals[un.capitals.length - 1].city !== 'pl-hb' || un.capitals[0].city !== '호반성' || !('place:pl-hb' in dr.documents) || 'place:pl-hoban' in dr.documents) bad(`지명 id를 바꿨는데 id로 적은 도읍 · 문서만 따라가지 않음 (${n})`);
        pl.id = 'pl-hb';
        const nn = kit.renameRefs(dr, kit.BASE_TABLES.places, 'name', '호반성', '호반 성');
        if (nn !== 20 || un.capitals[0].city !== '호반 성' || dr.events.find(x => x.id === 'e-hoban-move').place !== '호반 성') bad(`지명 이름을 바꿨는데 이름으로 적은 도읍 · 사건 장소가 따라가지 않음 (${nn})`);
        const sn = dr.surnames.find(x => x.id === 'sn-on');
        if (kit.renameRefs(dr, kit.BASE_TABLES.surnames, 'name', '온', '오온') !== 1 || dr.houses.find(h => h.id === 'h-ondam').surname !== '오온' || dr.houses.find(h => h.id === 'h-hwi').surname !== '휘') bad('성씨 이름을 바꿨는데 그 이름으로 적은 가문의 성만 따라가지 않음');
        if (!sn) bad('성씨 사전 줄이 작업본에 없음');
        if (!HT.draft.LISTS.includes('surnames') || !HT.draft.LISTS.includes('places')) bad('작업본 목록에 성씨 · 지명이 없음');
      } else bad('메이커 바탕 자료에 성씨 · 지명 표가 없음');
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [67] 형식 3 세 갈래 잇기 (통합 — F1 이름 · 사람 · F2 단체 · 렌즈 · F3 판 · 지도):
   ① 단체의 구성원(people)이 사람 참조(HT.readPersonRef — 인물 이름 · id · 지도자 칸 "나라:지도자@해")로 읽히고, 모델의 사람 풀이(linkPeople)로 인물 · 지도자 칸의 사람 자리에 —
      사람 자리 쪽에는 속한 단체(groups) · 못 찾은 지도자 칸은 단체의 '확인할 것' · 글로 적은 이름은 경고 없이 글로만 · 패치 · 왕복 · 메이커의 트랙 id 바꾸기
   ② 이름 목록(names)이 단체 · 제도 · 주제 · 모아 보기 판 · 지도의 구역에도 같은 읽기(HT.readNames)로 — 낱말 → id · 왕복(날짜 글 제자리) · 폼의 이름 줄
   ③ 지도의 지명 글 목록(maps[].places)이 지명 사전과 이어짐(모델 placeItems — 사전의 id · 이름 · 없으면 저절로) · 메이커의 지명 id 바꾸기가 지도의 지명 글도 따라감
   ④ 구조 나무 '종류별'에 단체 · 제도 묶음과 성씨 · 지명 · 주제 바탕 줄 */
{
  const bad = msg => out.problems.push(`형식 3 잇기: ${msg}`);
  try {
    const head = { format: HT.FORMAT, version: '1.0.0', id: 'smoke-link', name: '잇기 검사' };
    const read = raw => HT.normalizePack(Object.assign({}, head, raw));
    const T = [{ id: 'lk', name: '잇는 들' }];
    const base = {
      tracks: T,
      periods: [{ id: 'sol', track: 'lk', name: '솔나라', start: 500, end: 700, leaders: [{ name: '첫 왕', start: 500, end: 530 }, { name: '둘째 왕', start: 530, end: 600 }, { name: '셋째 왕', start: 600, end: 700 }] }],
      figures: [{ id: 'garam', track: 'lk', name: '가람', birth: 480, death: 560 }],
    };
    /* ① 구성원 = 사람 참조 */
    if (canon(HT.readGroupPeople('가람, 솔나라:첫 왕@500, 가람, ')) !== canon(['가람', { polity: '솔나라', leader: '첫 왕', start: 500 }])) bad(`구성원 글 읽기가 다름: ${JSON.stringify(HT.readGroupPeople('가람, 솔나라:첫 왕@500, 가람, '))}`);
    const people = ['가람', '솔나라:첫 왕@500', '둘째 왕', { track: 'lk', polity: '솔나라', leader: '없는 왕' }, '그냥 이름', { polity: '솔나라' }];
    const r1 = read(Object.assign({}, base, { groups: [{ id: 'band', name: '들바람 모임', type: '붕당', track: 'lk', start: 510, end: 650, within: '솔나라', people }] }));
    const g0 = r1.pack && r1.pack.groups && r1.pack.groups[0];
    if (!g0) bad(`구성원 검사 단체가 읽히지 않음: ${r1.errors.map(e => e.msg).join(' / ')}`);
    else {
      if (canon(g0.people) !== canon(['가람', { polity: '솔나라', leader: '첫 왕', start: 500 }, '둘째 왕', { track: 'lk', polity: '솔나라', leader: '없는 왕' }, '그냥 이름'])) bad(`구성원의 파일 꼴이 다름: ${JSON.stringify(g0.people)}`);
      if (!r1.warnings.some(w => /구성원 .*읽을 수 없어/.test(w.msg))) bad('지도자 없는 사람 참조 객체에 경고가 없음');
      const j = HT.packToJSON(r1.pack);
      if (canon(HT.packToJSON(read(JSON.parse(JSON.stringify(j))).pack)) !== canon(j)) bad('구성원(사람 참조)이 왕복하지 않음');
      const m = HT.buildModel([r1.pack], null);
      const g = m.groups[0];
      const rows = g.peopleList;
      const fig = m.figures.find(f => f.name === '가람');
      const cellName = r => (r && r.person && r.person.cells[0] ? r.person.cells[0].c.name : '');
      if (!rows[0].figure || rows[0].figure !== fig || rows[0].person !== HT.personOf(m, fig)) bad('구성원 "가람"이 인물 · 그 사람 자리로 이어지지 않음');
      if (rows[1].figure || cellName(rows[1]) !== '첫 왕' || rows[1].name !== '솔나라:첫 왕@500') bad(`구성원 "솔나라:첫 왕@500"이 지도자 칸의 사람 자리로 이어지지 않음: ${cellName(rows[1])}`);
      if (cellName(rows[2]) !== '둘째 왕') bad('구성원 "둘째 왕"(지도자 칸의 이름)이 그 칸의 사람 자리로 이어지지 않음');
      if (rows[3].person || !g.warnings.some(w => /구성원 "솔나라:없는 왕"/.test(w))) bad('찾지 못한 지도자 칸 구성원이 단체의 확인할 것에 없음');
      if (rows[4].person || rows[4].figure || g.warnings.some(w => /그냥 이름/.test(w))) bad('글로만 적은 구성원 이름에 사람 자리 · 경고가 생김');
      if (!HT.personOf(m, fig).groups.includes(g) || !rows[1].person.groups.includes(g)) bad('사람 자리 쪽에 속한 단체(groups)가 없음');
      if (m.peopleWarnings.some(w => /구성원/.test(w.msg))) bad('구성원 풀이가 사람 · 계보 경고(peopleWarnings)에 섞임');
    }
    const pr = read({ patches: [{ target: 'other/g', set: { people: ['솔나라:첫 왕', '가람'] } }] });
    const ps = pr.pack && pr.pack.patches[0] && pr.pack.patches[0].set.people;
    if (canon(ps) !== canon([{ polity: '솔나라', leader: '첫 왕' }, '가람']) || HT.packToJSON(pr.pack).formatVersion !== 3) bad(`패치의 구성원이 사람 참조로 읽히지 않거나 형식 3이 아님: ${JSON.stringify(ps)}`);
    const kit = HT.makerKit;
    if (kit) {
      const d = HT.draft.clean({ format: HT.FORMAT, id: 'smoke-link-d', name: '검사', tracks: T, groups: [{ id: 'band', name: '모임', track: 'lk', start: 510, people: [{ track: 'lk', polity: '솔나라', leader: '첫 왕' }, '가람'] }] });
      kit.renameRefs(d, kit.BASE_TABLES.tracks, 'id', 'lk', 'lk2');
      if (d.groups[0].track !== 'lk2' || d.groups[0].people[0].track !== 'lk2' || d.groups[0].people[1] !== '가람') bad(`트랙 id를 바꿨는데 구성원(지도자 칸)의 트랙이 따라가지 않음: ${JSON.stringify(d.groups[0])}`);
    }

    /* ② 이름 목록 — 단체 · 제도 · 주제 · 판 · 지도 구역 */
    const NM = [{ text: 'Wind Band', kind: '로마자', lang: 'x-wind' }, { text: '옛 바람', kind: '옛 이름', start: '520-03', end: 560 }];
    const r2 = read(Object.assign({}, base, {
      themes: [{ id: 'tax2', name: '거둠 제도', names: NM }],
      groups: [{ id: 'band', name: '들바람 모임', track: 'lk', start: 510, names: NM }],
      institutions: [{ id: 'in1', theme: 'tax2', polity: '솔나라', track: 'lk', spans: [['밭 나눔', 500]], names: NM }],
      views: [{ id: 'v1', name: '판', members: ['솔나라'], names: NM }],
      maps: [{ id: 'm1', name: '지도', size: [10, 10], regions: [{ id: 'r1', name: '가 고을', shape: [[0, 0], [5, 0], [5, 5]], names: NM }] }],
    }));
    const P2 = r2.pack;
    if (!P2) bad(`이름 목록 검사 팩이 읽히지 않음: ${r2.errors.map(e => e.msg).join(' / ')}`);
    else {
      const lists = { 주제: P2.themes[0], 단체: P2.groups[0], 제도: P2.institutions[0], 판: P2.views[0], 구역: P2.maps[0].regions[0] };
      for (const [w, x] of Object.entries(lists)) if (!x || !Array.isArray(x.names) || x.names.length !== 2 || x.names[0].kind !== 'roman' || x.names[1].kind !== 'former') bad(`${w}의 이름 목록이 같은 읽기(HT.readNames — 낱말 → id)로 읽히지 않음: ${JSON.stringify(x && x.names)}`);
      const j = HT.packToJSON(P2);
      if (j.themes[0].names[1].start !== '520-03' || j.groups[0].names[1].start !== '520-03' || j.maps[0].regions[0].names[1].start !== '520-03' || j.views[0].names[1].start !== '520-03') bad('이름 목록의 날짜 글이 파일에서 제자리로 접히지 않음 (주제 · 단체 · 판 · 구역)');
      if (canon(HT.packToJSON(read(JSON.parse(JSON.stringify(j))).pack)) !== canon(j)) bad('이름 목록을 단 단체 · 제도 · 주제 · 판 · 구역이 왕복하지 않음');
      const m = HT.buildModel([P2], null);
      if (!m.groups[0].names || !m.institutions[0].names || !(m.themeMap.get('tax2') || {}).names || !m.views[0].names) bad('모델의 단체 · 제도 · 주제 · 판에 이름 목록이 없음');
    }
    if (HT.FORMS.group && !HT.FORMS.group.html({ tracks: T }).includes('data-names-field')) bad('단체 폼에 이름(원어 등) 칸이 없음 (형식에 있는 칸 = 폼에 있는 칸)');
    if (HT.FORMS.institution && !HT.FORMS.institution.html({ tracks: T }).includes('data-names-field')) bad('제도 폼에 이름(원어 등) 칸이 없음');
    if (kit && !kit.BASE_TABLES.themes.names) bad('바탕 자료 주제 표에 이름 목록(文) 단추가 없음');

    /* ③ 지도의 지명 글 ↔ 지명 사전 */
    const r3 = read({ tracks: T, places: [{ id: 'pl-ferry', name: '나루', names: [{ text: 'Ferry' }] }], maps: [{ id: 'm1', name: '지도', size: [10, 10], places: ['나루', 'pl-ferry', '새 언덕'] }] });
    if (!r3.pack) bad(`지명 잇기 검사 팩이 읽히지 않음: ${r3.errors.map(e => e.msg).join(' / ')}`);
    else {
      const m = HT.buildModel([r3.pack], null);
      const mp = m.maps[0];
      const [a, b, c] = mp.placeItems || [];
      if (!a || a !== b || a.id !== 'pl-ferry' || !c || !c.auto || c.name !== '새 언덕') bad(`지도의 지명 글이 지명 사전으로 풀리지 않음: ${JSON.stringify((mp.placeItems || []).map(p => p && p.id))}`);
      if (!a || !a.uses.some(u => u.role === 'map' && u.mapId === 'm1') || a.uses.filter(u => u.role === 'map').length !== 1) bad('지명의 쓰인 곳에 지도가 (한 번) 없음');
      if (canon(r3.pack.maps[0].places) !== canon(['나루', 'pl-ferry', '새 언덕'])) bad('지도의 원문 지명 글이 바뀜');
    }
    if (kit) {
      const d = HT.draft.clean({ format: HT.FORMAT, id: 'smoke-link-p', name: '검사', tracks: T, places: [{ id: 'pl-ferry', name: '나루' }], maps: [{ id: 'm1', name: '지도', size: [10, 10], places: ['나루', 'pl-ferry'] }] });
      kit.renameRefs(d, kit.BASE_TABLES.places, 'id', 'pl-ferry', 'pl-boat');
      kit.renameRefs(d, kit.BASE_TABLES.places, 'name', '나루', '큰 나루');
      if (canon(d.maps[0].places) !== canon(['큰 나루', 'pl-boat'])) bad(`지명 id · 이름을 바꿨는데 지도의 지명 글이 따라가지 않음: ${JSON.stringify(d.maps[0].places)}`);
    }

    /* ④ 구조 나무 '종류별' — 단체 · 제도 묶음 · 성씨 · 지명 · 주제 바탕 줄 */
    const S = HT.makerShell;
    if (S && S.treeOf) {
      const d = HT.draft.clean(Object.assign({}, head, { id: 'smoke-link-t', tracks: T, periods: base.periods, groups: [{ id: 'band', name: '들바람 모임', track: 'lk', start: 510 }], institutions: [{ id: 'in1', theme: 'tax', polity: '솔나라', track: 'lk', spans: [['밭 나눔', 500]] }], surnames: [{ id: 'sn-a', name: '솔' }], places: [{ id: 'pl-a', name: '나루' }] }));
      const model = HT.buildModel([HT.normalizePack(d).pack], null);
      const tree = S.treeOf(d, { model });
      const lens = tree.find(x => x.key === 'lens');
      const rowsOf = k => ((lens && lens.kids.find(x => x.key === k)) || {}).rows || [];
      if (!lens || lens.n !== 2 || rowsOf('lens:groups')[0].name !== '들바람 모임' || rowsOf('lens:institutions')[0].name !== '솔나라 · 조세제도' || rowsOf('lens:institutions')[0].uid !== 'smoke-link-t/in1') bad(`구조 나무에 단체 · 제도 묶음이 없거나 줄이 다름: ${JSON.stringify(lens && lens.kids.map(k => k.rows.map(r => r.name)))}`);
      const baseKids = tree.find(x => x.key === 'base').kids;
      if (['surnames', 'places', 'themes'].some(k => !baseKids.some(x => x.base === k)) || baseKids.find(x => x.base === 'surnames').n !== 1 || baseKids.find(x => x.base === 'places').n !== 1) bad('구조 나무의 바탕에 성씨 · 지명 · 주제 줄이 없거나 수가 다름');
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [68] 형식 3 통합 검토에서 확인된 지적(2026-10-12 — 메이커 · 형식 · 규칙 · 바름 네 갈래 검토):
   ① 성씨 · 지명 문서를 지우면 사전 줄의 옛 본문(wiki)도 지워 되살아나지 않음(가문과 같게) ② 단체의 집권 칸(power)에는 이름 목록을 읽지 않음(폼에 상자가 없어 그대로 저장해도 사라지던 것)
   ③ 지도자 · 내각 칸의 사람 "미상"은 적지 않은 것과 같음(서로 다른 칸이 한 사람으로 묶이지 않게) · 단체 구성원의 "미상"은 뺌 · 사람 칸의 자동 완성에 "미상" 없음
   ④ 같은 이름 · 같은 점수의 인물은 고르지 않고 알림(부모 · 단체 구성원) · 찾지 못한 부모는 혈연 견주기에 세지 않음 · 긴 계보의 부모 고리 검사가 호출 더미를 넘기지 않음
   ⑤ 지명 사전 id로 적은 도읍은 그 지명에(같은 이름의 지명이 둘이어도) · 문서 열쇠는 적은 id · 사전의 같은 이름은 알림 ⑥ 시대 이름 바꾸기가 형식 3의 나라 참조(있던 나라 · 사람 참조 · 온 곳 · 판 · 지도 장면)도 따라감
   ⑦ 트랙 id 바꾸기가 판 · 지도 장면 · 사람 참조의 track도 따라감(쓰는 곳에도 셈) ⑧ 날짜 옮기기: 사람 참조의 start는 열쇠라 옮기지 않음(제 나라 칸을 가리키는 것만 함께) · 목록 꼴 집권 칸도 옮김
   ⑨ 한꺼번에 고치기의 소속이 돌고 도는 소속을 만들지 않음 ⑩ 지명 이름 · id 바꾸기가 도읍 칸 문서 · 조약의 맺은 곳도 옮김 ⑪ 단체 이름 바꾸기가 뒤 단체의 앞선 단체를 따라감
   ⑫ 낱말 표 찾기가 물려받은 이름('constructor' …)을 낱말로 읽지 않음 ⑬ 제도 칸의 끝을 비운 뒤 세기 글 끝이 되살아나지 않음(왕복이 한 번에 고정) */
{
  const bad = msg => out.problems.push(`형식 3 검토: ${msg}`);
  try {
    const kit = HT.makerKit;
    const head = { format: HT.FORMAT, version: '1.0.0', id: 'smoke-rv', name: '검토 반영' };
    const T = [{ id: 'rv-a', name: '가 들' }, { id: 'rv-b', name: '나 들' }];
    const read = raw => HT.normalizePack(Object.assign({}, head, { tracks: T }, raw));
    const model = raw => HT.buildModel([read(raw).pack], null);
    const clean = raw => HT.draft.clean(Object.assign({}, head, { tracks: T }, raw));
    /* ① 성씨 · 지명 문서 */
    {
      const d = clean({ surnames: [{ id: 'sn-e', name: '솔', wiki: '옛 성씨 글' }], places: [{ id: 'pl-e', name: '나루', wiki: '옛 지명 글' }], houses: [{ id: 'h', name: '솔 가문', wiki: '옛 가문 글' }] });
      for (const k of ['surname:sn-e', 'place:pl-e', 'house:h']) HT.draft.setDoc(d, k, '새 글');
      if (d.surnames[0].wiki != null || d.places[0].wiki != null || d.houses[0].wiki != null) bad(`문서를 적었는데 사전 줄의 옛 본문(wiki)이 남음: ${JSON.stringify([d.surnames[0], d.places[0]])}`);
      for (const k of ['surname:sn-e', 'place:pl-e', 'house:h']) HT.draft.setDoc(d, k, '');
      const m = HT.buildModel([HT.normalizePack(d).pack], null);
      if (Object.keys(d.documents).length || m.docs.has('surname:sn-e') || m.docs.has('place:pl-e') || m.docs.has('house:h')) bad('성씨 · 지명 문서를 지웠는데 옛 본문이 문서로 되살아남');
    }
    /* ② 집권 칸의 이름 목록 */
    {
      const r = read({ periods: [{ id: 'k', track: 'rv-a', name: '갑', start: 400, end: 500 }], groups: [{ id: 'g1', name: '무리', track: 'rv-a', start: 420, end: 470, within: '갑', power: [{ name: '집권', start: 430, end: 460, names: [{ text: 'Jipgwon', kind: '로마자' }] }] }] });
      if (!r.pack || r.pack.groups[0].power[0].names) bad(`단체의 집권 칸이 이름 목록을 읽음(폼에 상자가 없어 그대로 저장해도 사라짐): ${JSON.stringify(r.pack && r.pack.groups[0].power)}`);
      if (HT.FORMS.group) {
        const html = HT.powerRowHTML ? HT.powerRowHTML({ name: '집권', start: 430 }) : '';
        if (/data-names-rows/.test(html)) bad('집권 줄에 이름 상자가 생겼는데 읽기는 이름 목록을 버림 — 둘 중 하나로');
      }
    }
    /* ③ 사람 "미상" */
    {
      const r = read({ periods: [{ id: 'ga', track: 'rv-a', name: '가', start: 500, end: 560, leaders: [{ name: '갑', start: 500, end: 550, person: '미상' }] }, { id: 'na', track: 'rv-b', name: '나', start: 500, end: 600, leaders: [{ name: '을', start: 520, end: 560, person: '미상' }], cabinets: [{ name: '회의', start: 520, end: 530, person: '모름' }] }], groups: [{ id: 'g', name: '무리', track: 'rv-a', start: 510, end: 540, people: ['미상', '갑'] }] });
      const P = r.pack;
      if (!P || P.periods.some(p => (p.leaders || []).concat(p.cabinets || []).some(c => c.person != null))) bad('지도자 · 내각 칸의 사람 "미상"이 사람 참조로 남음');
      if (!P || JSON.stringify(P.groups[0].people) !== JSON.stringify(['갑'])) bad(`단체 구성원의 "미상"을 빼지 않음: ${JSON.stringify(P && P.groups[0].people)}`);
      if (r.warnings.filter(w => /미상|모름/.test(w.msg)).length !== 4) bad(`사람 "미상"을 뺀 경고가 넷이 아님: ${JSON.stringify(r.warnings.map(w => w.msg))}`);
      const m = HT.buildModel([P], null);
      if (HT.personOf(m, m.byUid.get('smoke-rv/ga'), 'leader:0') === HT.personOf(m, m.byUid.get('smoke-rv/na'), 'leader:0')) bad('사람 "미상"을 적은 서로 다른 나라의 지도자 칸이 한 사람으로 묶임');
      const lists = HT.lineageListsHTML({ figureNames: ['가람'] });
      const person = (lists.match(/<datalist id="mkPersonList">[\s\S]*?<\/datalist>/) || [''])[0], who = (lists.match(/<datalist id="mkWhoList">[\s\S]*?<\/datalist>/) || [''])[0];
      if (/미상/.test(person) || !/미상/.test(who)) bad('사람 칸의 자동 완성(mkPersonList)에 "미상"이 있거나 부모 · 배우자 · 앞 지도자 칸(mkWhoList)에 없음');
      const box = HT.cxBoxHTML('leaders', {});
      if (!/class="x-person" list="mkPersonList"/.test(box) || !/class="x-from" list="mkWhoList"/.test(box) || !/class="x-who" list="mkWhoList"/.test(HT.parentRowHTML({}))) bad('사람 상자의 칸이 고친 자동 완성 목록을 쓰지 않음');
    }
    /* ④ 같은 이름의 인물 · 찾지 못한 부모 · 긴 계보 */
    {
      const m = model({ periods: [{ id: 'k', track: 'rv-a', name: '나라', start: 100, end: 200 }], figures: [{ id: 'f1', track: 'rv-a', name: '달님', birth: 100, death: 160 }, { id: 'f2', track: 'rv-a', name: '달님', birth: 120, death: 180 }, { id: 'kid', track: 'rv-a', name: '아이', birth: 140, death: 190, parents: [{ who: '달님' }] }, { id: 'kid2', track: 'rv-a', name: '둘째 아이', birth: 140, death: 190, parents: [{ who: 'f2' }] }], groups: [{ id: 'g', name: '무리', track: 'rv-a', start: 130, end: 170, within: '나라', people: ['달님', 'f1'] }] });
      const kid = HT.personOf(m, m.byUid.get('smoke-rv/kid')), kid2 = HT.personOf(m, m.byUid.get('smoke-rv/kid2'));
      if (!kid || kid.parents.length !== 1 || kid.parents[0].node.figure || !kid.parents[0].node.missing) bad(`같은 이름의 인물 둘 가운데 하나를 부모로 조용히 고름: ${JSON.stringify(kid && kid.parents.map(e => e.node.key))}`);
      if (!m.peopleWarnings.some(w => /달님.*같은 이름의 인물이 여럿/.test(w.msg))) bad('같은 이름의 인물을 고를 수 없다는 경고가 없음');
      if (!kid2 || kid2.parents[0].node.figure !== m.byUid.get('smoke-rv/f2')) bad('id로 적은 부모가 그 인물에 이어지지 않음');
      const g = m.groups[0];
      if (g.peopleList[0].figure || !g.peopleList[0].ambiguous || g.peopleList[1].figure !== m.byUid.get('smoke-rv/f1') || !g.warnings.some(w => /같은 이름의 인물이 여럿/.test(w))) bad(`단체 구성원의 같은 이름 인물을 조용히 고르거나 알리지 않음: ${JSON.stringify(g.peopleList.map(r => [r.name, r.figure && r.figure.id]))}`);
      const m2 = model({ periods: [{ id: 'k', track: 'rv-a', name: '갑 왕국', start: 500, end: 600, leaders: [{ name: '첫 임금', start: 500, end: 520 }, { name: '첫 임금', start: 520, end: 530 }, { name: '둘째 임금', start: 530, end: 560, accession: { kin: '아들' }, parents: [{ who: '첫 임금' }] }, { name: '셋째 임금', start: 560, end: 590, accession: { kin: '아들' }, parents: [{ who: '없는 사람' }] }] }] });
      if (m2.peopleWarnings.some(w => /혈연과 어긋납니다/.test(w.msg))) bad(`찾지 못한 부모를 혈연으로 세어 자리 이음 관계에 엉뚱한 경고: ${JSON.stringify(m2.peopleWarnings.map(w => w.msg))}`);
      const figs = Array.from({ length: 8000 }, (_, k) => ({ id: `c${k}`, track: 'rv-a', name: `사람${k}`, birth: 1000 + k, death: 1050 + k, parents: k < 7999 ? [{ who: `c${k + 1}` }] : [] })); // 후손이 앞에 놓이는 차례 — 되부름이면 8,000대 깊이
      try {
        model({ figures: figs });
      } catch (e) {
        bad(`긴 계보(8,000대)에서 모델이 멈춤: ${e && e.message}`);
      }
    }
    /* ⑤ 지명 사전 id로 적은 도읍 */
    {
      const m = model({ places: [{ id: 'pl-a', name: '같은곳', names: [{ text: 'Ay', kind: '로마자' }] }, { id: 'pl-b', name: '같은곳', names: [{ text: 'Bee', kind: '로마자' }] }], periods: [{ id: 'k1', track: 'rv-a', name: '갑', start: 100, end: 200, capitals: [{ city: 'pl-b', start: 100 }] }, { id: 'k2', track: 'rv-b', name: '을', start: 100, end: 200, capitals: [{ city: 'pl-a', start: 100 }] }] });
      const c = m.byUid.get('smoke-rv/k1').capitals[0];
      if (c.city !== '같은곳' || c.placeId !== 'pl-b' || HT.placeOf(m, c.placeId || c.city).id !== 'pl-b') bad(`id로 적은 도읍이 그 지명에 붙지 않음: ${JSON.stringify(c)}`);
      if (JSON.stringify(m.places.map(p => [p.id, p.uses.map(u => u.item.name)])) !== JSON.stringify([['pl-a', ['을']], ['pl-b', ['갑']]])) bad(`같은 이름의 지명의 쓰인 곳이 섞임: ${JSON.stringify(m.places.map(p => [p.id, p.uses.length]))}`);
      if (HT.docKey.cell('smoke-rv/k1', 'capitals', c) !== 'cell:smoke-rv/k1:capitals:pl-b@100') bad(`id로 적은 도읍 칸의 문서 열쇠가 적은 id가 아님: ${HT.docKey.cell('smoke-rv/k1', 'capitals', c)}`);
      if (!m.peopleWarnings.some(w => w.list === 'places' && /같은곳.*둘/.test(w.msg))) bad('지명 사전의 같은 이름을 알리지 않음');
    }
    if (kit && HT.makerFind && HT.makerDrag && HT.makerGrid) {
      /* ⑥ 시대 이름 바꾸기 */
      {
        const d = clean({
          periods: [
            { id: 'gap', track: 'rv-a', name: '갑', start: 500, end: 600, leaders: [{ name: '첫', start: 500, end: 530 }, { name: '둘', start: 530, end: 560, accession: { from: { polity: '갑', leader: '첫', start: 500 } }, parents: [{ who: { polity: '갑', leader: '첫', start: 500 } }] }] },
            { id: 'eul', track: 'rv-b', name: '을', start: 500, end: 600, leaders: [{ name: '셋', start: 520, end: 560, person: '갑:둘@530' }] },
          ],
          figures: [{ id: 'f', track: 'rv-a', name: '사람', birth: 490, death: 570, spouses: [{ who: '갑:첫' }] }],
          groups: [{ id: 'g0', name: '무리', track: 'rv-a', start: 510, end: 550, within: [{ polity: '갑' }], people: ['갑:첫@500'] }],
          institutions: [{ id: 'in', theme: 'tax', polity: '을', track: 'rv-b', spans: [{ name: '첫째 칸', start: 500, end: 520 }, { name: '둘째 칸', start: 520, from: 'rv-a:갑' }, { name: '셋째 칸', start: 540, from: { polity: '갑', name: '첫째' } }] }],
          views: [{ id: 'v', name: '판', members: ['rv-a:갑', '을'] }],
          maps: [{ id: 'm', name: '지도', size: [10, 10], regions: [{ id: 'r1', name: '고을', shape: [[0, 0], [5, 0], [5, 5]] }], frames: [{ year: 520, owners: { r1: '갑' } }] }],
        });
        const gap = d.periods[0];
        const n = HT.makerFind.renameReferences(d, 'periods', Object.assign({}, gap), Object.assign({}, gap, { name: '갑2' }));
        gap.name = '갑2';
        const m = HT.buildModel([HT.normalizePack(d).pack], null);
        const left = JSON.stringify(d).match(/"갑"|"갑:|"rv-a:갑"/g);
        if (n !== 10 || left || d.institutions[0].spans[2].from.name !== '첫째') bad(`시대 이름을 바꿨는데 형식 3의 나라 참조가 남음(${n}곳 고침): ${JSON.stringify(left)}`);
        if (m.peopleWarnings.length || m.views[0].warnings.length || m.maps[0].warnings.length || m.groups[0].warnings.length || m.institutions[0].warnings.length) bad(`시대 이름을 바꾼 뒤 못 찾음 경고: ${JSON.stringify([m.peopleWarnings.map(w => w.msg), m.views[0].warnings, m.maps[0].warnings])}`);
      }
      /* ⑦ 트랙 id 바꾸기 */
      {
        const d = clean({
          periods: [{ id: 'gap', track: 'rv-a', name: '갑', start: 500, end: 600, leaders: [{ name: '첫', start: 500, end: 530 }] }, { id: 'eul', track: 'rv-b', name: '을', start: 500, end: 600, leaders: [{ name: '셋', start: 520, end: 560, person: { track: 'rv-a', polity: '갑', leader: '첫', start: 500 } }] }],
          figures: [{ id: 'f', track: 'rv-b', name: '사람', birth: 490, death: 570, parents: [{ who: { track: 'rv-a', polity: '갑', leader: '첫' } }] }],
          views: [{ id: 'v', name: '판', members: ['rv-a:갑', { track: 'rv-a', polity: '갑' }] }],
          maps: [{ id: 'm', name: '지도', size: [10, 10], regions: [{ id: 'r1', name: '고을', shape: [[0, 0], [5, 0], [5, 5]] }], frames: [{ year: 520, owners: { r1: 'rv-a:갑' } }, { year: 540, owners: { r1: { track: 'rv-a', polity: '갑' } } }] }],
        });
        const users = kit.findUsers(d, kit.BASE_TABLES.tracks, d.tracks[0]).map(u => u.list);
        if (!users.includes('views') || !users.includes('maps') || !users.includes('figures')) bad(`트랙의 쓰는 곳에 판 · 지도 · 사람 참조가 없음: ${JSON.stringify(users)}`);
        kit.renameRefs(d, kit.BASE_TABLES.tracks, 'id', 'rv-a', 'rv-a2');
        d.tracks[0].id = 'rv-a2';
        if (/"rv-a"|"rv-a:/.test(JSON.stringify(d))) bad(`트랙 id를 바꿨는데 판 · 지도 장면 · 사람 참조에 옛 id가 남음: ${JSON.stringify([d.views[0].members, d.maps[0].frames.map(f => f.owners), d.periods[1].leaders[0].person, d.figures[0].parents])}`);
        const m = HT.buildModel([HT.normalizePack(d).pack], null);
        if (m.views[0].warnings.length || m.maps[0].warnings.length || m.peopleWarnings.length) bad('트랙 id를 바꾼 뒤 판 · 지도 · 사람 잇기에 못 찾음 경고');
      }
      /* ⑧ 날짜 옮기기 */
      {
        const sh = HT.makerDrag.shiftItem;
        const fa = sh({ id: 'fa', track: 'rv-a', name: '아이', birth: 160, death: 200, parents: [{ who: { polity: '가 나라', leader: '둘째 임금', start: 150 }, as: '부' }], spouses: [{ who: '가 나라:첫 임금@100', start: 180, end: 190 }] }, -15);
        if (fa.parents[0].who.start !== 150 || fa.spouses[0].who !== '가 나라:첫 임금@100' || fa.birth !== 145 || fa.spouses[0].start !== 165) bad(`인물을 옮기니 다른 나라를 가리키는 사람 참조의 시작 해까지 옮김: ${JSON.stringify(fa)}`);
        const g = sh({ id: 'gap', track: 'rv-a', name: '갑 왕국', start: 500, end: 600, leaders: [{ name: '둘째 임금', start: 530, end: 545 }, { name: '셋째 임금', start: 545, end: 552 }, { name: '둘째 임금', start: 552, end: 560, person: { polity: '갑 왕국', leader: '둘째 임금', start: 530 }, accession: { from: { polity: '갑 왕국', leader: '셋째 임금', start: 545 } } }, { name: '넷째', start: 560, end: 570, person: '갑 왕국:둘째 임금@530', parents: [{ who: { polity: '을 나라', leader: '먼 임금', start: 500 } }] }] }, 10);
        const L = g.leaders;
        if (L[2].person.start !== 540 || L[2].accession.from.start !== 555 || L[3].person !== '갑 왕국:둘째 임금@540' || L[3].parents[0].who.start !== 500) bad(`나라를 옮길 때 제 칸을 가리키는 사람 참조 · 앞 지도자가 칸과 함께 옮겨지지 않음(다른 나라 것은 그대로여야 함): ${JSON.stringify(L.slice(2))}`);
        const grp = sh({ id: 'g', name: '무리', track: 'rv-a', start: 100, end: 150, people: [{ polity: '가', leader: '첫', start: 100 }], power: [['집권', 110, 120], { name: '연정', start: 130, end: 140 }], from: ['옛 무리'] }, 10);
        if (grp.people[0].start !== 100 || JSON.stringify(grp.power) !== JSON.stringify([{ name: '집권', start: 120, end: 130 }, { name: '연정', start: 140, end: 150 }]) || JSON.stringify(grp.from) !== '["옛 무리"]') bad(`단체를 옮길 때 구성원 참조가 옮겨지거나 목록 꼴 집권 칸이 그대로임: ${JSON.stringify(grp)}`);
      }
      /* ⑨ 한꺼번에 고치기의 소속 고리 */
      {
        const d = clean({ periods: [{ id: 'ga', track: 'rv-a', name: '가', start: 100, end: 300 }, { id: 'na', track: 'rv-a', name: '나', start: 100, end: 300, partOf: '가' }, { id: 'da', track: 'rv-a', name: '다', start: 100, end: 300, partOf: '나' }, { id: 'ra', track: 'rv-a', name: '라', start: 100, end: 300 }] });
        const m = HT.buildModel([HT.normalizePack(d).pack], null);
        const r = HT.makerGrid.bulkPlan(d, ['smoke-rv/ga', 'smoke-rv/ra'], { key: 'partOf', text: '다' }, { model: m, isLocked: () => false, rawOf: x => x, baseModel: () => m });
        if (r.changed !== 1 || r.skipped !== 1 || !r.reasons.includes('제 아래 나라에는 놓을 수 없음') || d.periods[0].partOf != null || d.periods[3].partOf !== '다') bad(`한꺼번에 고치기가 돌고 도는 소속을 만듦: ${JSON.stringify([r.changed, r.skipped, r.reasons, d.periods.map(p => p.partOf || null)])}`);
      }
      /* ⑩ 지명 이름 · id 바꾸기와 도읍 칸 문서 · 조약의 맺은 곳 */
      {
        const mk = city => clean({ places: [{ id: 'pl-x', name: '옛 이름' }], periods: [{ id: 'p1', track: 'rv-a', name: '갑', start: 100, end: 200, capitals: [{ city, start: 100 }] }], events: [{ id: 'e1', track: 'rv-a', title: '맹세', start: 150, treaty: { place: '옛 이름', parties: ['갑'] } }], documents: { [`cell:p1:capitals:${city}@100`]: '도읍 글' } });
        const has = d => {
          const m = HT.buildModel([HT.normalizePack(d).pack], null);
          return m.docs.has(HT.docKey.cell('smoke-rv/p1', 'capitals', m.byUid.get('smoke-rv/p1').capitals[0]));
        };
        const a = mk('옛 이름');
        kit.renameRefs(a, kit.BASE_TABLES.places, 'name', '옛 이름', '새 이름');
        a.places[0].name = '새 이름';
        if (!has(a) || a.events[0].treaty.place !== '새 이름') bad(`지명 이름을 바꾸니 이름으로 적은 도읍 칸 문서가 떨어지거나 조약의 맺은 곳이 남음: ${JSON.stringify([a.documents, a.events[0].treaty.place])}`);
        const b = mk('pl-x');
        if (!has(b)) bad('id로 적은 도읍 칸의 문서(cell:…:capitals:지명 id@해)가 이어지지 않음');
        kit.renameRefs(b, kit.BASE_TABLES.places, 'name', '옛 이름', '새 이름');
        b.places[0].name = '새 이름';
        if (!has(b)) bad('지명 이름을 바꾸니 id로 적은 도읍 칸 문서가 떨어짐');
        kit.renameRefs(b, kit.BASE_TABLES.places, 'id', 'pl-x', 'pl-y');
        b.places[0].id = 'pl-y';
        if (!has(b) || b.periods[0].capitals[0].city !== 'pl-y') bad(`지명 id를 바꾸니 도읍 칸 문서가 떨어짐: ${JSON.stringify(b.documents)}`);
        b.places = [];
        if (!has(b)) bad('지명 사전이 없을 때(사전 DLC를 끔) id로 적은 도읍 칸 문서가 떨어짐');
        if (!(kit.BASE_TABLES.themes.refs.id || []).some(s => s.list === 'views' && s.path === 'settings.lens') || (kit.BASE_TABLES.themes.refs.name || []).some(s => s.list === 'views')) bad('주제 id 바꾸기가 판의 렌즈(settings.lens — 주제 id 글)를 따라가지 않거나 이름 바꾸기에도 따라감');
      }
      /* ⑪ 단체 이름 바꾸기 */
      {
        const d = clean({ periods: [{ id: 'k', track: 'rv-a', name: '나라', start: 700, end: 900 }], groups: [{ id: 'gr-old', name: '옛 무리', track: 'rv-a', start: 760, end: 842, within: '나라' }, { id: 'gr-e', name: '동쪽 무리', track: 'rv-a', start: 842, end: 900, within: '나라', from: [{ group: '옛 무리', how: 'split' }] }, { id: 'gr-s', name: '남쪽 무리', track: 'rv-a', start: 842, end: 900, within: '나라', from: ['옛 무리'] }, { id: 'gr-w', name: '서쪽 무리', track: 'rv-a', start: 842, end: 900, within: '나라', from: ['gr-old'] }] });
        const before = Object.assign({}, d.groups[0]);
        d.groups[0].name = '옛 큰 무리';
        const n = kit.renameGroupRefs(d, before, '옛 무리', '옛 큰 무리');
        const m = HT.buildModel([HT.normalizePack(d).pack], null);
        if (n !== 2 || m.groups.some(g => g.warnings.length) || (m.byUid.get('smoke-rv/gr-old').intoList || []).length !== 3 || d.groups[3].from[0] !== 'gr-old') bad(`단체 이름을 바꾸니 뒤 단체의 앞선 단체가 끊어짐: ${JSON.stringify(d.groups.map(g => g.from))}`);
      }
    }
    /* ⑫ 낱말 표 · ⑬ 제도 칸의 끝 */
    {
      const r = read({ periods: [{ id: 'k', track: 'rv-a', name: '갑', start: 400, end: 500, leaders: [{ name: '첫', start: 400, end: 420 }, { name: '둘', start: 420, end: 450, accession: { kin: 'constructor', how: 'toString' } }] }], groups: [{ id: 'g', name: '무리', track: 'rv-a', start: 410, end: 440, within: '갑', type: '__proto__', names: [{ text: '무리', kind: 'valueOf' }] }] });
      const j = r.pack ? HT.packToJSON(r.pack) : null;
      const ok = j && j.groups[0].type === '__proto__' && JSON.stringify(j.periods[0].leaders[1].accession) === JSON.stringify({ kin: 'constructor', how: 'toString' }) && j.groups[0].names[0].kind === 'valueOf';
      if (!ok || canon(HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(j))).pack)) !== canon(j)) bad(`낱말 표가 물려받은 이름을 낱말로 읽음: ${JSON.stringify(j && [j.groups[0].type, j.periods[0].leaders[1].accession, j.groups[0].names])}`);
      const sp = HT.readInstSpans([{ name: 's', start: 790, end: '3세기 말' }]);
      if (JSON.stringify(sp.list) !== JSON.stringify([{ name: 's', start: 790 }]) || !sp.warnings.some(w => /끝을 비웠습니다/.test(w))) bad(`제도 칸의 끝을 비웠다고 알리고는 세기 글 끝을 되살림: ${JSON.stringify(sp.list)}`);
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [69] D1 — 승계표 · 세계표 · 계보 전용 인물 · 파 · 머리 칩 · 가문 조명 (docs/설계-10건/1-2-…-확정.md 2절 · 3-3 · 3-4 · 4-2 · 4-4 · 5-3 · 6-3 — D1-W1):
   ① 형식 버전: 새 칸(계보 전용 · 형제 순서 · 가문의 구분 · 민족 · 꼬리표 · 정권의 꼬리표 · 패치의 lineageOnly · order — null도)을 하나씩만 쓴 파일은 3 · 견본 sample-lantern(오류 · 경고 0 · 왕복 같음 · 3)
   ② 읽기: 날짜 없는 계보 전용은 받음 · 보통 인물은 여전히 오류 · 계보 전용의 중요도는 버리고 경고 · 활동 기록은 두고 경고 · 형제 순서가 정수가 아니면 경고 · 자동 id 씨앗에 첫 부모 · 왕복
   ③ 모델: 계보 전용은 lineageFigures에만(figures · servedBy · 가문 구성원 members에 없음) · byUid에 있음 · 저절로 잇기 안 함 · 날짜 없는 사람의 겹침 오탐 없음 · 이름 미상의 공유 자리
   ④ 사람 자리의 가문: 적음 > 파조 > 물려받기(양부 > 부 > 생부 — 모 쪽 안 받음) > 칸 짐작 · 혈연 없는 사람은 예전 규칙 그대로 · 칸의 houseId 그대로
   ⑤ HT.familyOf: 고리 없는 견본에서 옛 구현(이 검사 안의 사본)과 같음 · branches · 고리 1건 끊김 + 경고
   ⑥ 계보 뼈대: 8-1 예시와 같은 열 · size 합 · 한 사람 한 번 · 나무 부모가 앞 · 덧선(양부 → 옆구리 비트) · 안정 열쇠(두 번 지어도 같음 · 빈 고리 '<자식>^<줄>') · 나눠 짓기 = 동기
   ⑦ HT.kinLayout: 정수 · 같은 세대 카드 겹침 0 · 같은 입력 같은 결과 · 모두 펼침 폭 = 잎(4 + 옆구리) · 펼친 마디(옆구리)의 합 · 보이지 않는 마디 x −1
   ⑧ HT.successionRows: 줄 수 ≤ 사람 + 지도자 · 다음 지도자는 건너뛰기 줄 · 다시 오른 사람은 처음 카드에서만 · 모두 펼침에서 한 사람 한 번
   ⑨ 머리 칩: 정권 셋 + 꼬리표 · 가문 짐작 표시 · 본관 성씨 · 이름이 본관 성씨와 같으면 뺌 ⑩ HT.houseSpans: 맞닿은 칸 잇기 · 파 포함 · 칸 없는 나라 = 국성 기간 · 성씨(가문 여럿)
   ⑪ HT.accessionLine 여섯 갈래의 차례 ⑬ 2천 명 — 부모를 이름으로 적어도 id로 적은 것과 같은 사람 잇기 */
{
  const bad = msg => out.problems.push(`D1 계보: ${msg}`);
  try {
    const J = x => JSON.stringify(Array.from(x));
    const head = { format: HT.FORMAT, formatVersion: 3, version: '1.0.0', id: 'smoke-kin1', name: '계보 검사' };
    const T = [{ id: 'k', name: '가람' }];
    const read = raw => HT.normalizePack(Object.assign({}, head, { tracks: T }, raw));
    const ver = raw => {
      const r = read(raw);
      return r.pack ? HT.packToJSON(r.pack).formatVersion : `오류: ${r.errors.map(e => e.msg).join(' / ')}`;
    };
    /* ① 형식 버전 · 견본 */
    const P = extra => Object.assign({ id: 'p', track: 'k', name: '가람 나라', start: 1400, end: 1500 }, extra);
    const cases = [
      ['계보 전용 인물', { figures: [{ id: 'f', track: 'k', name: '갑', lineageOnly: true }] }],
      ['형제 순서', { figures: [{ id: 'f', track: 'k', name: '갑', birth: 1410, order: 2 }] }],
      ['가문의 구분', { houses: [{ id: 'h', name: '온씨', track: 'k' }] }],
      ['가문의 민족', { houses: [{ id: 'h', name: '온씨', people: '누리' }] }],
      ['가문의 꼬리표', { houses: [{ id: 'h', name: '온씨', tags: '왕실, 무가' }] }],
      ['정권의 꼬리표', { periods: [P({ tags: ['통일 왕조'] })] }],
      ['패치의 계보 전용', { patches: [{ target: '딴팩/f', set: { lineageOnly: true } }] }],
      ['패치로 계보 전용을 지움(null)', { patches: [{ target: '딴팩/f', set: { lineageOnly: null } }] }],
      ['패치의 형제 순서', { patches: [{ target: '딴팩/f', set: { order: 3 } }] }],
    ];
    for (const [what, raw] of cases) if (ver(raw) !== 3) bad(`${what}만 쓴 파일이 형식 3으로 나가지 않음 (${ver(raw)})`);
    if (ver({ houses: [{ id: 'h', name: '온씨', surname: '온' }] }) !== 2 || ver({ figures: [{ id: 'f', track: 'k', name: '갑', birth: 1410, lineageOnly: false }] }) !== 2) bad('옛 칸만 쓴 파일(가문 · lineageOnly: false)이 형식 3으로 나감');
    if (!skipSamples.some(k => 'sample-lantern.json'.includes(k))) {
      const row = out.packs.find(p => p.id === 'lantern-chronicle');
      const sp = packs.find(p => p.id === 'lantern-chronicle');
      if (!row || !sp) bad('견본 sample-lantern이 읽히지 않음');
      else {
        if (row.errors || row.warnings || !row.roundtrip) bad(`견본 sample-lantern: 오류 ${row.errors} · 경고 ${row.warnings} · 왕복 ${row.roundtrip ? '같음' : '다름'}`);
        if (HT.packToJSON(sp).formatVersion !== 3) bad('견본 sample-lantern이 형식 3으로 나가지 않음');
        if ((sp.figures || []).filter(f => f.lineageOnly).length !== 4) bad('견본 sample-lantern의 계보 전용 인물이 넷이 아님');
      }
    }
    /* ② 읽기 */
    {
      const r = read({ figures: [
        { id: 'a', track: 'k', name: '갑', lineageOnly: true },
        { id: 'b', track: 'k', name: '을' },
        { id: 'c', track: 'k', name: '병', lineageOnly: true, importance: 3, service: [{ polity: '가람 나라', start: 1410, end: 1420 }] },
        { id: 'd', track: 'k', name: '정', lineageOnly: true, order: 1.5 },
        { id: 'e', track: 'k', name: '무', birth: 1410, order: '2' },
      ] });
      const F = Object.fromEntries((r.pack ? r.pack.figures : []).map(f => [f.id, f]));
      const msgs = r.warnings.map(w => w.msg).join(' / ');
      if (!F.a || F.a.lineageOnly !== true || 'importance' in F.a) bad(`날짜 없는 계보 전용 인물을 받지 않거나 중요도를 채움: ${JSON.stringify(F.a)}`);
      if (F.b || !r.errors.some(e => /"을".*날짜가 하나도 없습니다/.test(e.msg))) bad('날짜 없는 보통 인물이 오류가 아님');
      if (!F.c || 'importance' in F.c || !/"병".*중요도를 쓰지 않아/.test(msgs) || !(F.c.service || []).length || !/"병".*활동 기록은 연표에 그리지 않습니다/.test(msgs)) bad(`계보 전용의 중요도 버림 · 활동 기록 경고가 맞지 않음: ${msgs}`);
      if (!F.d || 'order' in F.d || !/"정".*형제 순서/.test(msgs)) bad('정수가 아닌 형제 순서를 빼고 알리지 않음');
      if (!F.e || F.e.order !== 2) bad('형제 순서(글 "2")를 정수로 읽지 않음');
      const json = HT.packToJSON(r.pack);
      if (canon(HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(json))).pack)) !== canon(json)) bad('계보 전용 · 형제 순서를 쓴 파일의 왕복이 다름');
      /* 자동 id: 생년 없는 같은 이름의 형제 · 사촌이 줄 차례가 바뀌어도 부모가 다르면 id가 그대로 */
      const ids = list => read({ figures: list }).pack.figures.map(f => `${f.name}<${f.parents[0].who}>=${f.id}`).sort().join(' ');
      const twins = [{ track: 'k', name: '같은 이름', lineageOnly: true, parents: [{ who: 'x1', as: '부' }] }, { track: 'k', name: '같은 이름', lineageOnly: true, parents: [{ who: 'x2', as: '부' }] }];
      if (ids(twins) !== ids(twins.slice().reverse())) bad('생년 없는 같은 이름의 계보 전용 인물 자동 id가 줄 차례에 따라 바뀜');
      const plain = read({ figures: [{ track: 'k', name: '보통', birth: 1410, parents: [{ who: 'x1', as: '부' }] }] }).pack.figures[0].id;
      if (plain !== `f-${HT.hash('k|보통|1410')}`) bad('보통 인물의 자동 id 씨앗이 바뀜(옛 파일의 id가 달라짐)');
      const pr = HT.normalizePack(Object.assign({}, head, { id: 'smoke-kin1p', patches: [{ target: '딴팩/f', set: { lineageOnly: '예', order: 'x' } }, { target: '딴팩/g', set: { lineageOnly: false, order: '4' } }] }));
      if (!pr.pack || pr.pack.patches.length !== 1 || pr.pack.patches[0].set.order !== 4 || pr.pack.patches[0].set.lineageOnly !== false || pr.warnings.filter(w => /계보 전용|형제 순서/.test(w.msg)).length !== 2) bad(`패치의 lineageOnly · order 읽기가 맞지 않음: ${JSON.stringify(pr.pack && pr.pack.patches)} / ${pr.warnings.map(w => w.msg).join(' / ')}`);
    }
    /* ③ 모델 */
    {
      const r = read({
        houses: [{ id: 'h', name: '온씨' }],
        periods: [P({ house: 'h', leaders: [{ name: '첫 임금', start: 1400, end: 1420 }, { name: '둘째 임금', start: 1420, end: 1450, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] }] })],
        figures: [
          { id: 'lo', track: 'k', name: '첫 임금', lineageOnly: true, birth: 1380, death: 1430, house: 'h' }, // 지도자와 같은 이름 · 겹친 시기 — 저절로 잇지 않음
          { id: 'x', track: 'k', name: '미상', lineageOnly: true, parents: [{ who: 'lo', as: '부' }] },
          { id: 'y1', track: 'k', name: '형', lineageOnly: true, parents: [{ who: 'x', as: '부' }] },
          { id: 'y2', track: 'k', name: '아우', lineageOnly: true, parents: [{ who: 'x', as: '부' }] },
          { id: 'z1', track: 'k', name: '같은이', birth: 1405, death: 1460 },
          { id: 'z2', track: 'k', name: '같은이', lineageOnly: true },
          { id: 'w', track: 'k', name: '딴이', birth: 1440, parents: [{ who: '같은이', as: '부' }] },
        ],
      });
      const m = HT.buildModel([r.pack], null);
      const lo = m.byUid.get('smoke-kin1/lo');
      if (!lo || m.figures.includes(lo) || !m.lineageFigures.includes(lo)) bad('계보 전용 인물이 lineageFigures가 아닌 figures에 있음');
      if (m.periods.some(p => (p.servedBy || []).some(s => s.figure.lineageOnly))) bad('계보 전용 인물이 정권의 servedBy에 듦');
      if (m.houses.some(h => h.members.some(x => x.item && x.item.lineageOnly))) bad('계보 전용 인물이 가문 구성원 목록(members)에 듦');
      const cell0 = HT.personOf(m, m.byUid.get('smoke-kin1/p'), 'leader:0');
      if (!cell0 || cell0.figure) bad('계보 전용 인물이 같은 이름 · 겹친 시기의 지도자 칸과 저절로 이어짐');
      const xp = HT.personOf(m, m.byUid.get('smoke-kin1/x'));
      if (!xp || !xp.unknown || xp.children.length !== 2 || xp.name !== '미상') bad('이름이 미상인 계보 전용 인물이 형제 둘을 둔 이름 미상의 공유 자리가 아님');
      const wp = HT.personOf(m, m.byUid.get('smoke-kin1/w'));
      if (!wp || !wp.parents[0] || wp.parents[0].node.figure !== m.byUid.get('smoke-kin1/z1') || m.peopleWarnings.some(q => /같은 이름의 인물이 여럿/.test(q.msg))) bad('날짜 없는 같은 이름(계보 전용)이 그 시기와 겹친다고 나와 고를 수 없게 됨');
      if (m.figures.length !== 2 || m.lineageFigures.length !== 5) bad(`인물 나눔이 맞지 않음: 띠 ${m.figures.length} · 계보 전용 ${m.lineageFigures.length}`);
    }
    /* ④ 사람 자리의 가문 */
    {
      const r = read({
        houses: [{ id: 'h', name: '온씨', founder: '가람 나라:첫 임금@1400' }, { id: 'hb', name: '바람파', parent: 'h', founder: 'fb' }, { id: 'hx', name: '딴 가문' }, { id: 'hm', name: '외가' }],
        periods: [P({ house: 'h', leaders: [{ name: '첫 임금', start: 1400, end: 1420 }, { name: '둘째 임금', start: 1420, end: 1450, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] }, { name: '셋째 임금', start: 1450, end: 1460, house: 'hx', parents: [{ who: 'fb', as: '부' }] }] })],
        figures: [
          { id: 'fb', track: 'k', name: '바람', lineageOnly: true, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] },
          { id: 'c1', track: 'k', name: '자식1', lineageOnly: true, parents: [{ who: 'fb', as: '부' }] },
          { id: 'mom', track: 'k', name: '어미', lineageOnly: true, house: 'hm' },
          { id: 'c2', track: 'k', name: '자식2', lineageOnly: true, parents: [{ who: 'mom', as: '모' }] },
          { id: 'c3', track: 'k', name: '자식3', lineageOnly: true, parents: [{ who: 'mom', as: '생부' }, { who: 'fb', as: '양부' }] },
          { id: 'c4', track: 'k', name: '자식4', lineageOnly: true, parents: [{ who: 'mom', as: '생부' }, { who: '가람 나라:첫 임금@1400', as: '부' }] },
          { id: 'c5', track: 'k', name: '자식5', lineageOnly: true, house: 'hx', parents: [{ who: 'fb', as: '부' }] },
        ],
      });
      const m = HT.buildModel([r.pack], null);
      const per = id => HT.personOf(m, m.byUid.get(`smoke-kin1/${id}`));
      const cellP = i => HT.personOf(m, m.byUid.get('smoke-kin1/p'), `leader:${i}`);
      const want = [[cellP(0), 'h', 'founder'], [cellP(1), 'h', 'inherit'], [cellP(2), 'hx', 'written'], [per('fb'), 'hb', 'founder'], [per('c1'), 'hb', 'inherit'], [per('c2'), null, null], [per('c3'), 'hb', 'inherit'], [per('c4'), 'h', 'inherit'], [per('c5'), 'hx', 'written'], [per('mom'), 'hm', 'written']];
      for (const [n, id, how] of want) if (!n || n.houseId !== id || n.houseHow !== how) bad(`사람 자리의 가문이 맞지 않음: ${n ? n.name : '?'} → ${n && n.houseId}(${n && n.houseHow}), 기대 ${id}(${how})`);
      if (m.byUid.get('smoke-kin1/p').leaders[2].houseId !== 'hx' || m.byUid.get('smoke-kin1/p').leaders[1].houseId !== 'h') bad('칸의 houseId(띠의 가문 줄)가 바뀜');
      /* 혈연 없는 옛 견본: 사람 자리의 가문 = 예전 규칙(인물의 가문 → 적은 칸 → 짐작 칸) */
      if (model) for (const n of model.persons) {
        if (n.parents.length || n.children.length) continue;
        const hc = n.cells.find(x => x.c.houseId && !x.c.houseAuto) || n.cells.find(x => x.c.houseId);
        const old = (n.figure && n.figure.houseId) || (hc ? hc.c.houseId : null);
        if (n.houseId !== old && !(model.houses || []).some(h => h.founderNode === n)) {
          bad(`혈연 없는 사람의 가문이 예전과 다름: ${n.name} ${n.houseId} ≠ ${old}`);
          break;
        }
      }
    }
    /* ⑤ HT.familyOf — 옛 구현 사본(고리 없는 자료에서 같은 값이어야 함) */
    {
      const personRuledOld = n => (n ? n.cells.filter(x => x.kind === 'leader').map(x => ({ uid: x.p.uid, name: x.p.name, ref: x.ref, i: x.i, ordinal: x.c.ordinal ?? null, color: x.p.color, start: x.c.start })) : []);
      const familyOld = (model, houseId) => {
        const h = model.houseMap.get(houseId) || (model.houses || []).find(x => x.name === houseId) || null;
        if (!h) return null;
        const members = model.persons.filter(n => n.houseId === h.id);
        const inSet = new Set(members);
        for (const n of members) for (const e of n.parents.concat(n.children, n.spouses)) inSet.add(e.node);
        const list = [...inSet];
        const edges = [];
        const seenSp = new Set();
        for (const n of list) {
          for (const e of n.parents) if (inSet.has(e.node)) edges.push({ type: 'parent', from: e.node.key, to: n.key, as: e.as, gen: e.gen || 1, certainty: e.certainty || '' });
          for (const e of n.spouses) {
            if (!inSet.has(e.node)) continue;
            const k = [n.key, e.node.key].sort().join('|');
            if (seenSp.has(k)) continue;
            seenSp.add(k);
            edges.push({ type: 'spouse', a: n.key, b: e.node.key, start: e.start, end: e.end, startUnknown: e.startUnknown, endUnknown: e.endUnknown });
          }
        }
        const gen = new Map(list.map(n => [n.key, 0]));
        for (let round = 0; round < list.length; round++) {
          let moved = false;
          for (const e of edges) {
            if (e.type !== 'parent') continue;
            const want = gen.get(e.from) + e.gen;
            if (want > gen.get(e.to)) {
              gen.set(e.to, want);
              moved = true;
            }
          }
          if (!moved) break;
        }
        for (const e of edges)
          if (e.type === 'spouse') {
            const ga = gen.get(e.a);
            const gb = gen.get(e.b);
            const noA = !list.find(n => n.key === e.a).parents.some(q => inSet.has(q.node));
            const noB = !list.find(n => n.key === e.b).parents.some(q => inSet.has(q.node));
            if (noA && !noB) gen.set(e.a, gb);
            else if (noB && !noA) gen.set(e.b, ga);
          }
        const nodes = list.map(n => ({ key: n.key, name: n.name, member: members.includes(n), unknown: n.unknown, missing: n.missing, generation: gen.get(n.key), figureUid: n.figure ? n.figure.uid : null, houseId: n.houseId, ruled: personRuledOld(n).map(({ polity, ...r }) => r) }));
        nodes.sort((a, b) => a.generation - b.generation || (b.member ? 1 : 0) - (a.member ? 1 : 0));
        return { house: h, nodes, edges };
      };
      let compared = 0;
      if (model)
        for (const h of model.houses) {
          if (h.packId !== 'lantern-chronicle') continue;
          const a = HT.familyOf(model, h.id);
          const b = familyOld(model, h.id);
          compared++;
          if (canon({ nodes: a.nodes, edges: a.edges }) !== canon({ nodes: b.nodes, edges: b.edges }) || a.warnings.length) bad(`familyOf("${h.id}")가 옛 구현과 다름`);
        }
      if (model && !compared && !skipSamples.length) bad('familyOf를 견줄 견본 가문이 없음');
      if (model && model.houseMap.get('h-hwi')) {
        const fb = HT.familyOf(model, 'h-hwi', { branches: true });
        const f0 = HT.familyOf(model, 'h-hwi');
        const nam = fb && fb.nodes.find(n => n.name === '휘 남강군');
        if (!fb || fb.nodes.filter(n => n.member).length <= f0.nodes.filter(n => n.member).length || !nam || nam.branchId !== 'h-hwi-nam' || nam.founderOf !== 'h-hwi-nam') bad('familyOf branches: 파의 사람 · 파 경계(branchId · founderOf)가 맞지 않음');
      }
      /* 고리 1건 */
      const r = read({ houses: [{ id: 'h', name: '온씨' }], figures: [{ id: 'a', track: 'k', name: '갑', lineageOnly: true, house: 'h', parents: [{ who: 'b', as: '부' }] }, { id: 'b', track: 'k', name: '을', lineageOnly: true, house: 'h', parents: [{ who: 'a', as: '부' }] }, { id: 'c', track: 'k', name: '병', lineageOnly: true, parents: [{ who: 'b', as: '부' }] }] });
      const cm = HT.buildModel([r.pack], null);
      const cf = HT.familyOf(cm, 'h');
      if (!cf || !cf.warnings.some(w => /고리/.test(w)) || cf.nodes.some(n => n.generation > 3)) bad(`familyOf: 고리를 끊고 알리지 않거나 세대가 불어남 ${JSON.stringify(cf && cf.nodes.map(n => [n.name, n.generation]))}`);
      const cs = HT.kinSkeleton(cm, 'kin:h');
      if (!cs || cs.n !== 3 || !cs.warnings.some(w => /고리/.test(w)) || [...cs.par].filter(x => x < 0).length !== 1) bad('계보 뼈대가 고리를 한 선만 끊어 나무로 만들지 않음');
    }
    /* ⑥ 계보 뼈대 — 8-1 예시(2-6 견본)와 같은 열 */
    const ex = {
      format: HT.FORMAT, formatVersion: 3, id: 'kin-example', name: '계보 예시 (확인용)', tracks: [{ id: 'garam', name: '가람' }], peoples: [{ id: 'nuri', name: '누리족' }],
      houses: [
        { id: 'h-on', name: '물빛 온씨', surname: '온', seat: '물빛', founder: '가람 나라:첫 임금@1400', track: 'garam', people: '누리족', tags: ['왕실'] },
        { id: 'h-on-baram', name: '바람대군파', parent: 'h-on', founder: 'f-baram' },
        { id: 'h-on-sol', name: '솔군파', parent: 'h-on-baram', founder: 'f-sol' },
      ],
      periods: [{ id: 'garam', track: 'garam', name: '가람 나라', people: '누리족', house: 'h-on', start: 1400, end: 1650, tags: ['통일 왕조'], leaders: [{ name: '첫 임금', start: 1400, end: 1418 }, { name: '둘째 임금', start: 1418, end: 1450, accession: { kin: '아들', how: '선양' }, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] }] }],
      figures: [
        { id: 'f-baram', track: 'garam', name: '바람대군', lineageOnly: true, role: '왕자', birth: 1402, parents: [{ who: '가람 나라:첫 임금@1400', as: '부' }] },
        { id: 'f-sol', track: 'garam', name: '솔군', lineageOnly: true, parents: [{ who: 'f-baram', as: '부' }] },
        { id: 'f-sol-x', track: 'garam', name: '미상', lineageOnly: true, parents: [{ who: 'f-sol', as: '부' }] },
        { id: 'f-ga', track: 'garam', name: '온 가람', lineageOnly: true, parents: [{ who: 'f-sol-x', as: '부' }] },
        { id: 'f-na', track: 'garam', name: '온 나래', lineageOnly: true, parents: [{ who: 'f-sol-x', as: '부' }] },
      ],
    };
    const exr = HT.normalizePack(ex);
    const em = HT.buildModel([exr.pack], null);
    const es = HT.kinSkeleton(em, 'kin:h-on');
    if (exr.warnings.length || em.peopleWarnings.length || !es) bad(`2-6 예시: 경고가 남거나 뼈대가 없음 ${exr.warnings.concat(em.peopleWarnings).map(w => w.msg).join(' / ')}`);
    else {
      const want = { n: 7, gens: 5, par: [-1, 0, 1, 2, 3, 3, 0], size: [7, 5, 4, 3, 1, 1, 1], gen: [0, 1, 2, 3, 4, 4, 1], bits: [33, 81, 81, 67, 65, 65, 33], edge: [0, 0, 0, 0, 0, 0, 0], branch: [0, 1, 2, 2, 2, 2, 0], color: [1, 0, 0, 0, 0, 0, 1], color2: [], extra: [],
        name: ['첫 임금', '바람대군', '솔군', '미상', '온 가람', '온 나래', '둘째 임금'], sub: ['1대 · 1400~1418', '1402~', '', '', '', '', '2대 · 1418~1450'],
        key: ['c:kin-example/garam|leader:0', 'f:kin-example/f-baram', 'f:kin-example/f-sol', 'f:kin-example/f-sol-x', 'f:kin-example/f-ga', 'f:kin-example/f-na', 'c:kin-example/garam|leader:1'],
        cells: { 'kin-example/garam|leader:0': 0, 'kin-example/garam|leader:1': 6 } };
      for (const [k, v] of Object.entries(want)) {
        const got = ArrayBuffer.isView(es[k]) ? Array.from(es[k]) : es[k];
        if (canon(got) !== canon(v)) bad(`2-6 예시의 뼈대 열 ${k}가 8-1과 다름: ${canon(got)}`);
      }
      if (es.uid !== 'kin:h-on' || es.v !== 1 || es.branches.map(b => `${b.uid}@${b.at}^${b.up}`).join(' ') !== 'house:h-on@0^-1 house:h-on-baram@1^0 house:h-on-sol@2^1' || es.colors.length !== 2) bad(`2-6 예시의 머리 · 파 표가 맞지 않음: ${canon(es.branches)}`);
      if (canon(HT.kinOf(em, 'kin-example/garam', 1)) !== canon({ key: 'kin:h-on', at: 6 })) bad('HT.kinOf가 지도자 칸의 뼈대 자리를 내지 않음');
      const P0 = em.byUid.get('kin-example/garam');
      if (J(HT.successionRows(em, P0, HT.successionOpen(em, P0, 'children'))) !== '[0,0,0,1,1,1,2,1,1,0,1,0]' || HT.successionReach(em, P0, 0) !== 5 || HT.successionReach(em, P0, 1) !== 0) bad(`2-6 예시의 승계표 줄(자녀까지)이 '바람대군 · → 2대 둘째 임금'이 아님: ${J(HT.successionRows(em, P0, HT.successionOpen(em, P0, 'children')))}`);
      if (HT.houseHead(em, 'h-on-baram').map(c => c.text).join(' › ') !== '가람 › 누리족 › 물빛 온씨 › 바람대군파' || HT.houseHead(em, 'h-on').map(c => c.text).join(' › ') !== '가람 › 누리족 › 물빛 온씨 › 왕실') bad(`세계표 머리가 2-6 예시와 다름: ${HT.houseHead(em, 'h-on-baram').map(c => c.text).join(' › ')}`);
    }
    if (model && model.houseMap.get('h-hwi')) {
      /* 견본 sample-lantern의 휘씨(본파 · 남파 · 청림지파 포함 — 2.0.0에서 47명) */
      const s = HT.kinSkeleton(model, 'kin:h-hwi');
      if (HT.kinSkeleton(model, 'kin:h-hwi') !== s) bad('계보 뼈대를 모델마다 캐시하지 않음');
      let rootSum = 0;
      for (let i = 0; i < s.n; i++) {
        if (s.par[i] < 0) rootSum += s.size[i];
        else if (s.par[i] >= i) bad(`뼈대의 나무 부모가 앞 차례가 아님: ${i}`);
      }
      if (rootSum !== s.n || new Set(s.key).size !== s.n) bad('뼈대의 size 합 · 한 사람 한 번이 맞지 않음');
      /* 두 부모를 다 적은 사람(휘 남강군 — 아버지 미상의 빈 고리가 나무 부모, 어머니 휘 은하는 덧선 — 옆구리 비트) · 견본 2.0.0의 양자는 휘 시온(양모 유리아)뿐 — 여기서는 보지 않음 */
      const side = s.key.indexOf('f:lantern-chronicle/f-namgang');
      if (side < 0 || !(s.bits[side] & 8) || ![...Array(s.extra.length / 4).keys()].some(j => s.extra[j * 4 + 1] === side) || s.edge[side] !== 0) bad('두 부모 가운데 덧선(옆구리 비트)이 맞지 않음');
      // 견본 2.0.0: 부흥왕 · 합등왕 칸이 인물(휘 도윤 · 휘 다온 — 칸의 given 이름)에 이어져 뼈대 열쇠가 칸(c:)이 아니라 인물(f:)
      const far = s.key.indexOf('f:lantern-chronicle/f-hwi-doyun');
      if (far < 0 || s.edge[far] !== 6 || s.gen[far] - s.gen[s.par[far]] !== 24) bad('몇 대 건너뛴 후손(부흥왕 휘 도윤 — 긴 파선 · 전승 옅게 · 24대)이 맞지 않음');
      const two = s.key.indexOf('f:lantern-chronicle/f-hwi-daon');
      if (two < 0 || !(s.bits[two] & 256) || !s.color2[two]) bad('두 나라를 다스린 지도자(합등왕 휘 다온) 비트 · 둘째 색이 없음');
      const u = s.key.findIndex(k => /\^\d+$/.test(k));
      if (u < 0 || !(s.bits[u] & 2) || s.key[u] !== 'f:lantern-chronicle/f-namgang^1') bad(`이름 미상(빈 고리)의 안정 열쇠가 '<자식 열쇠>^<줄>'이 아님: ${s.key[u]}`);
      const again = HT.kinSkeleton(HT.buildModel(packs, null), 'kin:h-hwi');
      if (canon(again.key) !== canon(s.key) || J(again.par) !== J(s.par)) bad('같은 자료로 두 번 지은 뼈대의 안정 열쇠 · 차례가 다름');
      /* 나눠 짓기(HT.kinSkeletonAsync — 몇 ms마다 양보): 동기와 같은 뼈대 · 같은 캐시 */
      const am = HT.buildModel(packs, null);
      const as = await HT.kinSkeletonAsync(am, 'kin:h-hwi', { slice: 1 });
      if (!as || ['par', 'size', 'gen', 'bits', 'edge', 'branch', 'color', 'extra'].some(k => J(as[k]) !== J(s[k])) || canon(as.key) !== canon(s.key) || canon(as.cells) !== canon(s.cells) || HT.kinSkeleton(am, 'kin:h-hwi') !== as) bad('나눠 지은 뼈대가 동기로 지은 것과 다르거나 캐시에 없음');
      /* ⑦ HT.kinLayout */
      const check = (open, label) => {
        const L = HT.kinLayout(s, open);
        const L2 = HT.kinLayout(s, open);
        if (J(L.x) !== J(L2.x) || J(L.w) !== J(L2.w) || L.width !== L2.width) bad(`kinLayout(${label}): 같은 입력인데 결과가 다름`);
        for (const row of L.rows) for (let k = 1; k < row.length; k++) if (L.x[row[k]] - L.x[row[k - 1]] < 4) bad(`kinLayout(${label}): 같은 세대 카드가 겹침(${row[k - 1]} · ${row[k]})`);
        if ([...L.x, ...L.w].some(v => !Number.isInteger(v))) bad(`kinLayout(${label}): 정수가 아님`);
        let vis = 0;
        for (const row of L.rows) vis += row.length;
        if ([...L.x].filter(v => v >= 0).length !== vis) bad(`kinLayout(${label}): 보이지 않는 마디의 x가 −1이 아님`);
        return L;
      };
      const all = check(new Uint8Array(s.n).fill(1), '모두');
      let want = 0;
      for (let i = 0; i < s.n; i++) want += (s.size[i] > 1 ? 0 : 4) + (s.bits[i] & 8 ? 1 : 0);
      if (all.width !== want) bad(`kinLayout: 모두 펼침 폭(${all.width})이 잎 4칸 · 옆구리 1칸의 합(${want})이 아님`);
      check(HT.kinDefaultOpen(s), '기본');
      check(new Uint8Array(s.n), '모두 접음');
      const half = new Uint8Array(s.n);
      for (let i = 0; i < s.n; i += 2) half[i] = 1;
      check(half, '반');
      if (HT.kinDefaultOpen(s).some(v => !v) && s.n <= 200) bad('200명 이하 뼈대의 기본 펼침이 모두 펼침이 아님');
      /* ⑧ HT.successionRows */
      const G = model.byUid.get('lantern-chronicle/p-lantern'); // 휘씨가 국성인 등불 왕국
      const rowsAll = HT.successionRows(model, G, HT.successionOpen(model, G, 'all'));
      const persons = new Set();
      let leadersN = 0;
      for (let k = 0; k < rowsAll.length; k += 3) {
        if (rowsAll[k] === 0) leadersN++;
        if (rowsAll[k] === 1) {
          if (persons.has(rowsAll[k + 1])) bad(`승계표 모두 펼침에 같은 사람이 두 번: ${s.name[rowsAll[k + 1]]}`);
          persons.add(rowsAll[k + 1]);
        }
      }
      if (rowsAll.length / 3 > s.n + G.leaders.length) bad('승계표 모두 펼침 줄 수가 사람 + 지도자를 넘음');
      if (leadersN !== G.leaders.length) bad('승계표에 지도자 줄이 칸마다 하나가 아님');
      const lead = J(HT.successionRows(model, G, HT.successionOpen(model, G, 'leaders')));
      if (lead !== J(G.leaders.flatMap((c, m) => [0, m, 0])) || HT.successionReach(model, G, 7) !== 2 || HT.successionReach(model, G, 12) !== 1) bad(`승계표 지도자만 · 칸(적관왕 · 은등왕)의 후손 수가 맞지 않음 ${lead}`);
      /* 다시 오른 사람(설원 제국의 두갈래 황제 — 6 · 8 칸, 같은 마디): 펴면 처음 카드(6) 아래에만 줄이 생김 */
      const GE = model.byUid.get('lantern-chronicle/p-empire');
      const k2 = HT.kinOf(model, GE, 6);
      const opened = HT.successionOpen(model, GE, 'leaders');
      opened[k2.key][k2.at] = 1;
      const or = HT.successionRows(model, GE, opened);
      const at4 = [...Array(or.length / 3).keys()].find(r => or[r * 3] === 0 && or[r * 3 + 1] === 8);
      const at2 = [...Array(or.length / 3).keys()].find(r => or[r * 3] === 0 && or[r * 3 + 1] === 6);
      if (canon(HT.kinOf(model, GE, 8)) !== canon(k2) || HT.successionReach(model, GE, 8) !== 0 || !(at2 >= 0 && or[(at2 + 1) * 3] !== 0) || (or.length / 3 > at4 + 1 && or[(at4 + 1) * 3] !== 0)) bad(`다시 오른 사람의 카드가 처음 카드에서만 펼쳐지지 않음 ${J(or)}`);
      const ch = HT.successionRows(model, G, HT.successionOpen(model, G, 'children'));
      let skip = false;
      for (let k = 0; k < ch.length; k += 3) if (ch[k] === 2 && ch[k + 1] === 1) skip = true;
      if (!skip) bad('다음 지도자(2대)가 첫 카드 아래 건너뛰기 줄이 아님');
    }
    /* ⑨ 머리 칩 */
    if (model && model.houseMap.get('h-hwi-nam')) {
      /* 견본 sample-lantern — 본관 성씨와 같은 이름 · 본관 없는 가문 · 민족을 적지 않은 정권은 견본에 없음(본관 성씨와 같은 이름 칩 빼기는 위 2-6 예시의 '물빛 온씨'가 봄) */
      const ph = HT.polityHead(model, 'lantern-chronicle/p-lantern');
      if (ph.map(c => `${c.role}:${c.text}`).join(' ') !== 'track:하연 people:하연인 name:등불 왕국 tag:첫 통일 왕국' || ph.some(c => !c.field)) bad(`승계표 머리 칩이 구분 › 민족 › 국가 이름 · 꼬리표가 아님: ${canon(ph)}`);
      const hh = HT.houseHead(model, 'h-hwi-nam');
      if (!hh[0].auto || !/^짐작 — /.test(hh[0].title || '') || hh[2].text !== '휘성 휘씨' || hh[2].field !== 'seat' || hh[3].text !== '휘씨 남파') bad(`세계표 머리(파): 짐작 표시 · 본관 성씨 · 이름이 맞지 않음 ${canon(hh)}`);
      if (HT.houseHead(model, 'h-hwi').map(c => `${c.role}:${c.text}`).slice(2, 4).join(' ') !== 'surname:휘성 휘씨 name:휘씨') bad('본관 성씨와 다른 이름 칩이 본관 성씨 칩 뒤에 남지 않음');
    }
    /* ⑩ HT.houseSpans · houseUnder · houseEras */
    {
      const r = read({
        houses: [{ id: 'a', name: '갑씨', surname: '갑' }, { id: 'a2', name: '갑씨 파', parent: 'a' }, { id: 'b', name: '을씨', surname: '갑' }],
        periods: [
          P({ id: 'p1', leaders: [{ name: '하나', start: 1400, end: 1410, house: 'a' }, { name: '둘', start: 1410, end: 1420, house: 'a' }, { name: '셋', start: 1420, end: 1430, house: 'b' }, { name: '넷', start: 1430, end: 1440, house: 'a2' }] }),
          { id: 'p2', track: 'k', name: '다른 나라', start: 1300, end: 1350, house: 'a' },
        ],
      });
      const m = HT.buildModel([r.pack], null);
      const sp = HT.houseSpans(m, 'a');
      if (canon(sp) !== canon([{ uid: 'smoke-kin1/p2', start: 1300, end: 1350 }, { uid: 'smoke-kin1/p1', start: 1400, end: 1420 }])) bad(`houseSpans: 맞닿은 칸 잇기 · 칸 없는 나라의 국성 기간이 맞지 않음 ${canon(sp)}`);
      const spb = HT.houseSpans(m, 'a', { branches: true });
      if (spb.length !== 3 || spb[2].start !== 1430) bad(`houseSpans: 파를 포함하지 않음 ${canon(spb)}`);
      const sur = HT.houseSpans(m, m.surnames.find(x => x.name === '갑').houses);
      if (sur.length !== 2 || sur[1].end !== 1430) bad(`houseSpans: 성씨(가문 여럿)가 한 구간으로 잇지 않음 ${canon(sur)}`);
      if (canon(HT.houseUnder(m, 'house:a')) !== canon(['a', 'a2'])) bad('houseUnder가 자기와 아래 파를 내지 않음');
      const er = HT.houseEras(m, 'a');
      if (er.length !== 2 || canon(er[1].cells) !== canon([[1400, 1420], [1430, 1440]]) || canon(er[0].span) !== canon([1300, 1350])) bad(`houseEras가 맞지 않음 ${canon(er)}`);
      /* 실권(내각) 가문(감독 건의 2026-10-14 5번): 지도자 자리가 없어도 내각 칸의 기간이 '다스린 기간'의 실권 구간으로 — 지도자 구간과 따로 */
      const rc = read({
        houses: [{ id: 'k', name: '병씨' }, { id: 'q', name: '정씨' }],
        periods: [
          P({ id: 'p9', house: 'k', leaders: [{ name: '하나', start: 1400, end: 1440 }], cabinets: [{ name: '재상', start: 1410, end: 1420, house: 'q' }, { name: '재상 둘', start: 1420, end: 1425, house: 'q' }, { name: '왕족 재상', start: 1430, end: 1435, house: 'k' }] }),
          { id: 'p10', track: 'k', name: '뒤 나라', start: 1450, end: 1500, cabinets: [{ name: '섭정', start: 1460, endUnknown: true, house: 'q' }] },
        ],
      });
      const mc = HT.buildModel([rc.pack], null);
      const eq = HT.houseEras(mc, 'q');
      if (eq.length !== 2 || canon(eq[0].cells) !== canon([]) || canon(eq[0].real) !== canon([[1410, 1425]]) || eq[0].openReal) bad(`houseEras: 실권 가문의 내각 구간이 실권(real)으로 잇지 않음 ${canon(eq)}`);
      if (canon(eq[1].real) !== canon([[1460, 1500]]) || canon(eq[1].openReal) !== canon([0])) bad(`houseEras: 끝이 미정인 실권 구간에 열린 끝(openReal) 표시가 없음 — 글이 나라의 끝을 그 가문의 끝처럼 적게 됨 ${canon(eq[1])}`);
      const ek = HT.houseEras(mc, 'k');
      if (ek.length !== 1 || canon(ek[0].cells) !== canon([[1400, 1440]]) || canon(ek[0].real) !== canon([[1430, 1435]])) bad(`houseEras: 국성 가문의 지도자 · 실권 구간이 따로 나오지 않음 ${canon(ek)}`);
      if (!HT.houseSpans(mc, 'q').every(s => s.real === true)) bad('houseSpans: 실권 구간에 real 표시가 없음(가문 조명)');
    }
    /* ⑪ HT.accessionLine */
    {
      const want = [[{ how: 'usurpation', kinUnknown: true }, 1], [{ how: 'coup' }, 1], [{ how: 'conquest' }, 1], [{ kin: 'son', howUnknown: true }, 2], [{ kinUnknown: true, how: 'abdication' }, 2], [{ how: 'abdication' }, 3], [{ how: 'restoration' }, 4], [{ kin: 'son', how: 'hereditary' }, 5], [{ how: '빛의 의식' }, 5], [{ kin: 'son' }, 5], [{}, 0], [null, 0]];
      for (const [a, v] of want) if (HT.accessionLine(a) !== v) bad(`accessionLine(${canon(a)}) = ${HT.accessionLine(a)}, 기대 ${v}`);
      if (model && model.byUid.get('lantern-chronicle/p-coral')) {
        /* 견본 sample-lantern (앞 지도자 미상은 견본에 없음) */
        const seam = (pid, i) => HT.accessionSeam(model, HT.lineageOf(model, `lantern-chronicle/${pid}`).rulers[i]);
        const seams = [seam('p-lower', 3), seam('p-coral', 2), seam('p-coral', 10), seam('p-empire', 8), seam('p-lantern', 0)];
        if (canon(seams) !== canon(['숙부 · 찬탈', '관계 미상 · 방식 미상', '', '사촌 · 복위', '전임자 휘내 돌지기의 딸 · 돌 넘김'])) bad(`이음매 글이 맞지 않음: ${seams.join(' | ')}`);
      }
    }
    /* 폼(D1 7-2 ① · ③ — core.js): 인물 폼의 계보 전용 체크 · 형제 순서 칸(회색 예시 글 없음) · 계보 전용이면 접을 줄 넷 · 정권 폼의 꼬리표 칸 */
    {
      const ff = HT.figureFieldsHTML({ tracks: [{ id: 'k', name: '가람' }] });
      const tagOf = n => (ff.match(new RegExp(`<input[^>]*name="${n}"[^>]*>`)) || [''])[0];
      if (!/type="checkbox" name="lineageOnly"/.test(ff) || !tagOf('order') || /placeholder/.test(tagOf('order'))) bad('인물 폼에 계보 전용 체크 · 형제 순서 칸이 없거나 형제 순서 칸에 회색 예시 글이 있음');
      if ((ff.match(/ data-life[ >]/g) || []).length !== 4 || !/data-life-more style="display:none"/.test(ff)) bad('인물 폼의 계보 전용 접기 줄(중요도 · 활동 시작 · 활동 끝 · 활동 기록)과 더 보기 단추가 맞지 않음');
      if (!/<input name="tags"/.test(HT.periodFieldsHTML({ tracks: [{ id: 'k', name: '가람' }] }))) bad('정권 폼에 꼬리표 칸이 없음');
      if (canon(HT.FORMS.figure.filterKeys({ lineageOnly: true, importance: undefined })) !== '{}' || HT.FORMS.figure.filterKeys({ importance: 3 }).importance !== 3) bad('계보 전용 인물을 저장한 뒤 중요도 필터를 풀려 함');
    }
    /* ⑬ 2천 명 — 이름 참조 = id 참조 */
    {
      const mk = byName => {
        const figs = [];
        for (let i = 0; i < 2000; i++) {
          const p = i ? Math.floor((i - 1) / 3) : -1;
          figs.push({ id: `n${i}`, track: 'k', name: `사람${i}`, lineageOnly: true, house: i ? undefined : 'h', parents: p < 0 ? undefined : [{ who: byName ? `사람${p}` : `n${p}`, as: '부' }] });
        }
        return HT.buildModel([read({ houses: [{ id: 'h', name: '큰집' }], figures: figs }).pack], null);
      };
      const a = mk(true);
      const b = mk(false);
      const sig = m => m.persons.map(n => `${n.key}<${n.parents.map(e => e.node.key).join(',')}>${n.houseId}`).join(' ');
      if (sig(a) !== sig(b) || a.peopleWarnings.length) bad('2천 명: 부모를 이름으로 적은 사람 잇기가 id로 적은 것과 다름');
      const s = HT.kinSkeleton(b, 'kin:h');
      if (!s || s.n !== 2000 || s.size[0] !== 2000) bad('2천 명 계보 뼈대가 한 나무가 아님');
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [70] 띠 배치의 기준점(배열 기준) · 시대 접기 · 간지 설정 (형식 3 — docs/설계-10건/6-모아-보기와-배치.md 결정 6 · 7 · 8, 감독 선택 D4 6 C · 7 A · 8 B):
   ① 읽기 — 민족의 배열 기준(rowOrder · 한국어 · 모르는 값) · 나라의 남북 위치(northSouth · 글로 적은 수) · 최상위 간지 설정(yearCycle — false · 이름 목록 · 첫 해 · 모르는 칸) · 패치의 northSouth
   ② 형식 버전 — 새 칸을 하나라도 쓴 파일만 3 · 왕복 ③ 모델 — 먼저 켠 DLC의 순환 · 같은 id 민족의 기준 이어받기 · 남북 값(적은 값 → 첫 정도의 지명 좌표 · 지도의 crs 셋) · 알림
   ④ 배열 — 작은 검사 팩의 트랙이 북 → 남 · 'start'로 끊은 갈래는 시작 해 · 값 없는 줄은 뒤 · 민족 칸이 조각나지 않음 · 기준을 지우면 지금 규칙 그대로 · 대범위를 켜도 묶음 차례 그대로
   ⑤ 간지 셈(0년 없음 · 넓게 볼 때의 첫 해) · 보는 사람의 간지 줄(HT.yearCycleUi — 처음 한 번만 끔 · 다시 켜면 그대로 · DLC를 끄면 저절로 끈 것만 되켬)
   ⑥ 날짜 칸(가짜 this로 _buildAxis) — 접으면 '시대 구분 n개 나라 ▸' 한 줄 · 펴면 지금과 같은 줄(왼쪽 이름이 같은 모양의 단추) · 줄 이름 '간지' ↔ 순환의 이름
   ⑦ 메이커 — 민족 표의 배열 기준 칸 · 시대 폼의 남북 위치 칸(회색 예시 글 없음) · 팩 정보의 간지 설정 · 반영할 고침에 해 이름(false도) */
{
  const bad = msg => out.problems.push(`배열 기준 · 시대 접기 · 간지 설정: ${msg}`);
  try {
    const TL = HT.Timeline;
    const head = { format: HT.FORMAT, version: '1.0.0', id: 'smoke-ord', name: '배열 기준 검사' };
    const T = [{ id: 'od-a', name: '가 들' }];
    const read = (raw, h = head) => HT.normalizePack(Object.assign({}, h, { tracks: T }, raw));
    /* ① 읽기 */
    {
      const r = read({ peoples: [{ id: 'p1', name: '갑 겨레', rowOrder: '남북' }, { id: 'p2', name: '을 겨레', rowOrder: '시작 해' }, { id: 'p3', name: '병 겨레', rowOrder: 'constructor' }, { id: 'p4', name: '정 겨레', rowOrder: 'NorthSouth' }], periods: [{ id: 'a', track: 'od-a', name: '가', start: 1, end: 9, northSouth: '38.5' }, { id: 'b', track: 'od-a', name: '나', start: 1, end: 9, northSouth: '북쪽' }, { id: 'c', track: 'od-a', name: '다', start: 1, end: 9, northSouth: -2 }], patches: [{ target: 'x/y', set: { northSouth: '' } }, { target: 'x/z', set: { northSouth: '41' } }, { target: 'x/w', set: { northSouth: '높이', note: '' } }] });
      const P = Object.fromEntries(r.pack.peoples.map(p => [p.id, p.rowOrder]));
      if (P.p1 !== 'northSouth' || P.p2 !== 'start' || P.p3 !== undefined || P.p4 !== 'northSouth') bad(`민족의 배열 기준을 읽지 못함: ${JSON.stringify(P)}`);
      if (!r.warnings.some(w => /constructor/.test(w.msg))) bad('모르는 배열 기준(물려받은 이름 constructor)을 알리지 않음');
      const ns = r.pack.periods.map(p => p.northSouth);
      if (!(ns[0] === 38.5 && ns[1] === undefined && ns[2] === -2)) bad(`남북 위치를 읽지 못함: ${JSON.stringify(ns)}`);
      if (!r.warnings.some(w => /남북 위치/.test(w.msg) && /"나"/.test(w.msg))) bad('수가 아닌 남북 위치를 알리지 않음');
      const sets = r.pack.patches.map(p => p.set);
      if (sets[0].northSouth !== null || sets[1].northSouth !== 41 || 'northSouth' in sets[2]) bad(`패치의 남북 위치(비움 null · 글 수 · 못 읽음 뺌)가 맞지 않음: ${JSON.stringify(sets)}`);
      const yc = v => {
        const w = [];
        return { v: HT.readYearCycle(v, m => w.push(m)), w };
      };
      if (yc(false).v !== false || yc('끔').v !== false || yc(undefined).v !== undefined || yc(null).v !== undefined) bad('간지 설정의 false · "끔" · 비움을 읽지 못함');
      const a = yc({ names: '샘물, 숲길 ,볕뉘', start: '기원전 3', label: '해 이름', extra: 1 });
      if (JSON.stringify(a.v) !== JSON.stringify({ names: ['샘물', '숲길', '볕뉘'], start: -3, label: '해 이름' }) || !a.w.some(m => /extra/.test(m))) bad(`간지 설정(글 목록 · 기원전 첫 해 · 모르는 칸)을 읽지 못함: ${JSON.stringify(a)}`);
      const b = yc({ names: ['하나'] });
      if (b.v !== undefined || !b.w.length) bad('이름이 하나뿐인 순환을 버리지 않거나 알리지 않음');
      const c = yc({ names: ['가', '나'] });
      if (!c.v || c.v.start !== 1 || !c.w.some(m => /1년/.test(m))) bad(`첫 해가 없는 순환을 1년으로 보고 알리지 않음: ${JSON.stringify(c)}`);
      if (yc(true).v !== undefined || !yc(true).w.length || yc([1, 2]).v !== undefined) bad('간지 설정의 true · 목록을 버리고 알리지 않음');
      const long = yc({ names: ['아주'.repeat(11) + '긴 이름', '둘'], start: 1, label: '아주'.repeat(11) + '긴 줄 이름' });
      if (long.v.names[0].length !== HT.YEAR_CYCLE_LIMITS.nameLen || long.v.label.length !== HT.YEAR_CYCLE_LIMITS.label || long.w.length < 2) bad('긴 이름 · 줄 이름을 자르고 알리지 않음');
    }
    /* ② 형식 버전 · 왕복 */
    {
      const v = raw => HT.packToJSON(read(raw).pack).formatVersion;
      const base = { periods: [{ id: 'a', track: 'od-a', name: '가', start: 1, end: 9 }] };
      if (v(base) !== 1) bad('새 칸 없는 파일이 1로 나가지 않음');
      if (v(Object.assign({ peoples: [{ id: 'p', name: '갑', rowOrder: 'start' }] }, base)) !== 3) bad('rowOrder만 쓴 파일이 3으로 나가지 않음');
      if (v({ periods: [{ id: 'a', track: 'od-a', name: '가', start: 1, end: 9, northSouth: 0 }] }) !== 3) bad('northSouth(0)만 쓴 파일이 3으로 나가지 않음');
      if (v(Object.assign({ yearCycle: false }, base)) !== 3) bad('yearCycle: false만 쓴 파일이 3으로 나가지 않음');
      if (v(Object.assign({ patches: [{ target: 'x/y', set: { northSouth: null } }] }, base)) !== 3) bad('남북 위치를 비우는 패치만 쓴 파일이 3으로 나가지 않음');
      for (const raw of [Object.assign({ yearCycle: false }, base), Object.assign({ yearCycle: { names: ['가', '나', '다'], start: -10, label: '해' } }, base)]) {
        const j = HT.packToJSON(read(raw).pack);
        const k = HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(j))).pack);
        if (canon(j) !== canon(k) || JSON.stringify(j.yearCycle) !== JSON.stringify(raw.yearCycle)) bad(`간지 설정이 왕복에서 달라짐: ${JSON.stringify([j.yearCycle, k.yearCycle])}`);
      }
      const d1 = HT.draft.clean(Object.assign({}, head, { tracks: T }, base));
      const d2 = Object.assign(JSON.parse(JSON.stringify(d1)), { yearCycle: false });
      if (!HT.draft.changes(HT.normalizePack(d2).pack, HT.normalizePack(d1).pack).some(c => c.key === 'yearCycle')) bad('간지 설정을 끈 것(false)이 반영할 고침에 없음');
      if (HT.draft.changes(HT.normalizePack(d1).pack, HT.normalizePack(d1).pack).some(c => c.key === 'yearCycle')) bad('간지 설정을 고치지 않았는데 고침으로 셈');
    }
    /* ③ 모델 */
    {
      const pk = (id, raw) => read(raw, Object.assign({}, head, { id, name: id })).pack;
      const m1 = HT.buildModel([pk('o1', { periods: [{ id: 'a', track: 'od-a', name: '가', start: 1, end: 9 }] }), pk('o2', { yearCycle: false }), pk('o3', { yearCycle: { names: ['가', '나'], start: 1 } })], null);
      if (!m1.yearCycle || !m1.yearCycle.off || m1.yearCycle.packId !== 'o2') bad(`먼저 켠 DLC의 간지 설정이 쓰이지 않음: ${JSON.stringify(m1.yearCycle)}`);
      if (HT.buildModel([pk('o1', { periods: [{ id: 'a', track: 'od-a', name: '가', start: 1, end: 9 }] })], null).yearCycle !== null) bad('순환을 적은 DLC가 없는데 모델의 순환이 null이 아님');
      const m2 = HT.buildModel([pk('o1', { peoples: [{ id: 'pp', name: '갑 겨레' }], periods: [{ id: 'a', track: 'od-a', name: '가', start: 1, end: 9, people: '갑 겨레' }] }), pk('o2', { peoples: [{ id: 'pp', name: '다른 이름', rowOrder: 'northSouth' }] }), pk('o3', { peoples: [{ id: 'pp', name: '셋째', rowOrder: 'start' }] })], null);
      const pp = m2.peopleMap.get('pp');
      if (pp.name !== '갑 겨레' || pp.rowOrder !== 'northSouth') bad(`같은 id 민족: 이름은 먼저 켠 DLC · 배열 기준은 그것이 없을 때 뒤 DLC의 첫 것이어야 함: ${JSON.stringify([pp.name, pp.rowOrder])}`);
      /* 남북 값: 적은 값 → 첫 정도(임시 · 배도 · 뒤 도읍은 보지 않음)의 지명 좌표 · 지도의 crs */
      const caps = [{ city: '임시 땅', start: 50, role: '임시' }, { city: '남쪽 마을', start: 120 }, { city: '북쪽 마을', start: 100 }, { city: '배도 터', start: 90, role: '배도' }];
      const places = [{ id: 'pl-n', name: '북쪽 마을', at: [10, 45] }, { id: 'pl-s', name: '남쪽 마을', at: [10, 20] }, { id: 'pl-t', name: '임시 땅', at: [10, 80] }, { id: 'pl-b', name: '배도 터', at: [10, 70] }];
      const north = (extra, own) => {
        const m = HT.buildModel([pk('o1', Object.assign({ places, periods: [Object.assign({ id: 'a', track: 'od-a', name: '가', start: 50, end: 300, capitals: caps }, own)] }, extra))], null);
        return [HT.northOf(m.byUid.get('o1/a')), m.orderWarnings];
      };
      if (north({}, { northSouth: 7 })[0] !== 7) bad('적은 남북 위치가 이기지 않음');
      if (north({}, {})[0] !== 45) bad(`첫 정도(시작이 가장 이른 정식 도읍)의 위도가 아님: ${north({}, {})[0]}`);
      const imgMap = (crs, names) => ({ id: `m-${crs}-${names.length}`, name: '지도', crs, ...(crs === 'image' ? { size: [100, 100] } : {}), places: names });
      if (north({ maps: [imgMap('image', ['북쪽 마을'])] }, {})[0] !== -45) bad('그 지명을 실은 그림 지도(crs image)의 y를 뒤집지 않음');
      if (north({ maps: [imgMap('image', ['남쪽 마을']), imgMap('lonlat', ['북쪽 마을'])] }, {})[0] !== 45) bad('그 지명을 실은 경위도 지도의 위도를 그대로 쓰지 않음');
      if (north({ maps: [imgMap('image', ['남쪽 마을'])] }, {})[0] !== -45) bad('지명을 실은 지도가 없을 때 그 DLC 지도들의 crs(모두 같음)를 따르지 않음');
      const mixed = north({ maps: [imgMap('image', ['남쪽 마을']), imgMap('lonlat', ['임시 땅'])], peoples: [{ id: 'pp', name: '갑 겨레', rowOrder: 'northSouth' }] }, { people: '갑 겨레' });
      if (mixed[0] !== 45 || !mixed[1].some(w => /경위도/.test(w.msg))) bad(`crs가 섞였을 때 경위도로 보고 알리지 않음: ${JSON.stringify(mixed)}`);
      const none = HT.buildModel([pk('o1', { peoples: [{ id: 'pp', name: '갑 겨레', rowOrder: 'northSouth' }, { id: 'qq', name: '을 겨레' }], periods: [{ id: 'a', track: 'od-a', name: '값 없음', start: 1, end: 9, people: '갑 겨레' }, { id: 'b', track: 'od-a', name: '뒤 나라', start: 9, end: 20, people: '갑 겨레', succeeds: ['값 없음'] }, { id: 'c', track: 'od-a', name: '기준 없음', start: 1, end: 9, people: '을 겨레' }] })], null);
      const msgs = none.orderWarnings.map(w => w.msg).join(' / ');
      if (!/값 없음: 남북 위치 없음/.test(msgs) || /뒤 나라/.test(msgs) || /기준 없음/.test(msgs)) bad(`'남북 위치 없음' 알림은 '북 → 남' 민족의 줄 머리에만: ${msgs}`);
    }
    /* ④ 배열 — 작은 검사 팩(가짜 this로 _layoutTrack · dev-smoke의 lay와 같은 꼴). 견본 sample-lantern은 트랙마다 줄이 적거나 하연이 'start'라 북 → 남 차례가 드러나지 않음 */
    {
      const raw = { format: HT.FORMAT, version: '1.0.0', id: 'smoke-ord4', name: '배열 검사', tracks: [{ id: 'od-a', name: '가 들' }],
        peoples: [{ id: 'up', name: '윗 겨레', rowOrder: 'northSouth' }, { id: 'sub', name: '아랫 갈래', parent: '윗 겨레', rowOrder: 'start' }],
        periods: [
          { id: 'a', track: 'od-a', name: '가운데 나라', start: 10, end: 90, people: '윗 겨레', northSouth: 40 },
          { id: 'b', track: 'od-a', name: '북쪽 나라', start: 30, end: 90, people: '윗 겨레', northSouth: 50 },
          { id: 'c', track: 'od-a', name: '남쪽 나라', start: 0, end: 90, people: '윗 겨레', northSouth: 30 },
          { id: 'd', track: 'od-a', name: '값 없는 나라', start: 5, end: 90, people: '윗 겨레' },
          { id: 'e', track: 'od-a', name: '갈래 뒤', start: 25, end: 90, people: '아랫 갈래', northSouth: 60 },
          { id: 'f', track: 'od-a', name: '갈래 앞', start: 15, end: 90, people: '아랫 갈래', northSouth: 20 },
        ] };
      const rowsOf = (rawPack, opts = {}) => {
        const m = HT.buildModel([HT.normalizePack(rawPack).pack], null);
        const t = Object.assign(Object.create(TL.prototype), { folded: new Set(), foldedPeoples: new Set(), foldedEras: new Set(), expandedHosts: new Set(), scopesOn: opts.scopesOn || {}, show: Object.assign({}, HT.SHOW_DEFAULTS), density: 0, view: { start: -2500, end: 2100 }, _lod: new Map(), leaderMode: 'auto', birdShape: 'a', birdAuto: false, _bird: null });
        t._proxies = TL.depProxies(m.periods);
        t._setScopes(m.scopes || []);
        t._cats = new Map(HT.DEFAULT_CATEGORIES.map((c, i) => [c.id, { name: c.name, color: c.color, i }]));
        t._dynUids = new Set();
        const tr = Object.assign({}, m.trackMap.get('od-a'), { periods: m.periods.filter(p => p.track === 'od-a'), events: [], figures: [] });
        t._layoutTrack(tr);
        return { rows: tr.rowPeriods.map(r => r.map(p => p.name).join('→')), groups: tr.groups, tr };
      };
      const want = ['갈래 앞', '갈래 뒤', '북쪽 나라', '가운데 나라', '남쪽 나라', '값 없는 나라'];
      const got = rowsOf(raw);
      if (JSON.stringify(got.rows) !== JSON.stringify(want)) bad(`배열이 북 → 남(묶음 사이는 가장 북쪽 값 · 'start'로 끊은 갈래 안은 시작 해 · 값 없는 줄은 뒤)이 아님: ${got.rows.join(' | ')}`);
      /* 민족 칸이 조각나지 않음: 같은 이름의 묶음은 하나 · 그 줄 범위가 이어짐 */
      const names = got.groups.map(g => g.name);
      if (new Set(names).size !== names.length) bad(`민족 칸이 조각남: ${names.join(' · ')}`);
      const g = Object.fromEntries(got.groups.map(x => [x.name, x]));
      if (!g['윗 겨레'] || g['윗 겨레'].first !== 0 || g['윗 겨레'].count !== 6 || !g['아랫 갈래'] || g['아랫 갈래'].first !== 0 || g['아랫 갈래'].count !== 2) bad(`민족 칸의 자리가 기대와 다름: ${got.groups.map(x => `${x.name}@${x.first}+${x.count}`).join(' · ')}`);
      /* 기준을 지우면 지금 규칙(시작 해) 그대로 */
      const plain = JSON.parse(JSON.stringify(raw));
      for (const p of plain.peoples) delete p.rowOrder;
      const was = rowsOf(plain).rows;
      if (JSON.stringify(was) !== JSON.stringify(['남쪽 나라', '값 없는 나라', '가운데 나라', '갈래 앞', '갈래 뒤', '북쪽 나라'])) bad(`기준을 지운 팩이 지금 규칙(시작 해)의 차례가 아님: ${was.join(' | ')}`);
      /* 이음매(_seamL · _seamR)가 값을 재는 셈으로 바뀌지 않음 · 대범위를 켜도 다른 묶음의 차례 그대로 */
      const withScope = JSON.parse(JSON.stringify(raw));
      withScope.scopes = [{ id: 'ord-sc', track: 'od-a', name: '가운데 무리', members: ['가운데 나라'] }];
      const sc = rowsOf(withScope, { scopesOn: { 'smoke-ord4/ord-sc': true } });
      const rest = sc.rows.filter(r => !/가운데 나라/.test(r));
      if (JSON.stringify(rest) !== JSON.stringify(want.filter(n => n !== '가운데 나라'))) bad(`대범위를 켜니 다른 줄의 차례가 바뀜: ${sc.rows.join(' | ')}`);
      if (got.tr.periods.some(p => p._seamL || p._seamR)) bad('승계가 없는 트랙에 이음매가 남음 (값을 재려고 지은 줄의 흔적)');
    }
    /* ⑤ 간지 셈 · 보는 사람의 간지 줄 */
    {
      const cy = { names: ['갑', '을', '병'], start: 4 };
      const seq = [-2, -1, 1, 2, 3, 4, 5].map(y => HT.cycleName(cy, y)).join('');
      if (seq !== '을병갑을병갑을') bad(`간지 명칭이 0년 없이 이어지지 않음(4년 = 첫 이름): ${seq}`);
      if (HT.cycleName(null, 1984) !== HT.ganji(1984) || HT.cycleName({ off: true }, 1984) !== '갑자' || HT.cycleLabel(null) !== '간지' || HT.cycleLabel({ names: ['가', '나'], start: 1 }) !== '간지' || HT.cycleLength(null) !== 60) bad('순환이 없거나 끈 때 육십갑자 · 줄 이름 간지가 아님');
      if (JSON.stringify(HT.cycleFirstYears(null, 1900, 2030)) !== '[1924,1984]' || JSON.stringify(HT.cycleFirstYears(cy, -8, 8)) !== '[-6,-3,1,4,7]') bad(`한 바퀴의 첫 해가 맞지 않음: ${JSON.stringify([HT.cycleFirstYears(null, 1900, 2030), HT.cycleFirstYears(cy, -8, 8)])}`);
      const ui = { show: { ganji: true } };
      const off = { yearCycle: { off: true, packId: 'dlc-a' } };
      if (!HT.yearCycleUi(ui, off) || ui.show.ganji !== false || !ui.cycleAutoOff) bad('DLC가 끈 순환을 처음 볼 때 간지 줄을 끄지 않음');
      ui.show = Object.assign({}, ui.show, { ganji: true }); // 보는 사람이 필터에서 다시 켬
      if (HT.yearCycleUi(ui, off) || ui.show.ganji !== true) bad('보는 사람이 다시 켠 간지 줄을 또 끔');
      if (HT.yearCycleUi(ui, { yearCycle: null }) || ui.show.ganji !== true || ui.cycleAutoOff) bad('DLC를 끈 뒤 보는 사람이 켠 간지 줄이 바뀌거나 저절로 끈 표시가 남음');
      const ui2 = { show: { ganji: true } };
      HT.yearCycleUi(ui2, off);
      if (!HT.yearCycleUi(ui2, { yearCycle: null }) || ui2.show.ganji !== true) bad('저절로 끈 간지 줄이 그 DLC를 끈 뒤 되켜지지 않음');
      const ui3 = { show: { ganji: false } };
      if (HT.yearCycleUi(ui3, off) || ui3.cycleAutoOff || HT.yearCycleUi(ui3, { yearCycle: null }) || ui3.show.ganji !== false) bad('보는 사람이 끈 간지 줄을 DLC를 끈 뒤에 켬');
    }
    /* ⑥ 날짜 칸 (가짜 this로 _buildAxis — 화면 없이 글만) */
    {
      const tracks = [{ id: 'k1', name: '갑 땅', color: '#9dbea8' }, { id: 'k2', name: '을 땅', color: '#a0bcc5' }];
      const ep = (id, track, s, e) => ({ uid: `x/${id}`, name: `${id} 시대`, track, start: s, endY: e, color: '#c8b193' });
      const axis = (axisOpen, cycle, ganji = true) => {
        const t = Object.assign(Object.create(TL.prototype), { tracks, epochs: [ep('공', null, 0, 500), ep('가', 'k1', 0, 200), ep('나', 'k1', 100, 300), ep('다', 'k2', 50, 400)], show: Object.assign({}, HT.SHOW_DEFAULTS, { ganji, eras: false, capitals: false }), axisOpen: new Set(axisOpen), foldedEras: new Set(), openCapSec: new Set(), altCal: '', gutter: 240, axisEl: { innerHTML: '', style: { setProperty() {} } } });
        t.setYearCycle(cycle);
        t._buildAxis();
        return t;
      };
      const open = axis([], null);
      const h = open.axisEl.innerHTML;
      if (open.epochRows.length !== 3 || (h.match(/is-epoch/g) || []).length !== 3 || /data-group="epochs"/.test(h) || (h.match(new RegExp(`data-axis-group="${TL.EPOCH_FOLD}" aria-expanded="true"`, 'g')) || []).length !== 3) bad('펼친 날짜 칸이 공통 줄 하나 + 나라 줄 둘(셋 다 왼쪽 이름이 접기 단추)이 아님');
      if ((h.match(/class="tl-fold-mark">▾</g) || []).length !== 1 || !/>시대 구분<i class="tl-fold-mark">▾<\/i><\/button>/.test(h)) bad('펼친 시대 구분의 맨 처음 줄(공통 줄) 이름 끝에만 ▾가 있지 않음');
      if (!/border-width:0 1px 0 0;border-style:solid;border-color:var\(--paper-line\)/.test(h)) bad('나라 줄 왼쪽 이름 단추가 글 칸의 오른쪽 선을 그대로 두지 않음');
      if (!/<div class="tl-corner">간지<\/div>/.test(h)) bad('순환이 없을 때 간지 줄 제목이 "간지"가 아님');
      const shut = axis([TL.EPOCH_FOLD], { names: ['샘', '숲'], start: 1, label: '세차' });
      const s = shut.axisEl.innerHTML;
      if ((s.match(/is-epoch/g) || []).length !== 0 || (s.match(/data-group="epochs"/g) || []).length !== 1 || !/<b>시대 구분<\/b><i>3줄 ▸<\/i>/.test(s) || !shut.groupRows.some(g => g.epochs && g.list.length === 3 && !g.list[0].track)) bad('접은 날짜 칸이 공통 줄까지 "시대 구분 3줄 ▸" 한 줄이 아님(감독 건의 2026-10-14 2번)');
      if (s.indexOf('data-group="epochs"') > s.indexOf('is-ganji')) bad('공통 줄이 있으면 접힌 시대 구분 줄이 연도 바로 아래(간지 위)에 있지 않음');
      const onlyTracks = (() => {
        const t = Object.assign(Object.create(TL.prototype), { tracks, epochs: [ep('가', 'k1', 0, 200), ep('다', 'k2', 50, 400)], show: Object.assign({}, HT.SHOW_DEFAULTS, { ganji: true, eras: false, capitals: false }), axisOpen: new Set([TL.EPOCH_FOLD]), foldedEras: new Set(), openCapSec: new Set(), altCal: '', gutter: 240, axisEl: { innerHTML: '', style: { setProperty() {} } } });
        t.setYearCycle(null);
        t._buildAxis();
        return t.axisEl.innerHTML;
      })();
      if (!/<i>2줄 ▸<\/i>/.test(onlyTracks) || onlyTracks.indexOf('data-group="epochs"') < onlyTracks.indexOf('is-ganji')) bad('공통 줄이 없으면 접힌 시대 구분 줄이 나라 줄 자리(간지 아래)에 "2줄 ▸"로 있지 않음');
      if (!/<div class="tl-corner">세차<\/div>/.test(s)) bad('순환이 있을 때 줄 제목이 순환의 줄 제목이 아님');
      if (/class="tl-axis-row is-ganji"/.test(axis([], null, false).axisEl.innerHTML)) bad('간지를 끈 날짜 칸에 간지 줄이 남음');
      if (!/this\.groupRows = epochGroup \? \[epochGroup\] : \[\]/.test(readFileSync(join(root, 'js/timeline.js'), 'utf8'))) bad('접은 시대 구분 줄이 묶음 막대(groupRows)로 그려지지 않음');
    }
    /* ⑦ 메이커 · 폼 */
    {
      const kit = HT.makerKit;
      const col = kit && kit.BASE_TABLES.peoples.cols.find(c => c.key === 'rowOrder');
      if (!col || col.type !== 'select' || col.options.map(o => o.id).join(',') !== ',start,northSouth') bad('바탕 자료 민족 표에 배열 기준 칸(상위 민족 따름 · 시작 연도 · 북 → 남)이 없음');
      const form = HT.periodFieldsHTML({ tracks: T });
      if (!/name="northSouth" type="number"/.test(form) || /placeholder/.test(form)) bad('시대 폼에 남북 위치 칸이 없거나 회색 예시 글이 있음');
      const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
      if (!/name="yearCycleMode"/.test(msrc) || !/model\.orderWarnings/.test(msrc) || /yearCycle[^\n]*placeholder/.test(msrc)) bad('메이커의 팩 정보에 간지 설정 칸이 없거나 검사 창에 배열 기준 알림이 없음');
      const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
      if (!/HT\.yearCycleUi\(state\.ui, state\.model\)/.test(vsrc) || !/timeline\.setYearCycle\(state\.model\.yearCycle/.test(vsrc)) bad('보는 앱이 모델의 간지 설정을 연표에 넘기지 않음');
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [71] 렌즈 — 웹(감독 선택 D5 결정 5 A · 6 B, 덧붙임 "렌즈 종류도 dlc 조정 가능하게" · 설계 docs/설계-10건/7-8-단체와-렌즈.md):
   ① 주제 사전의 렌즈에서 숨김(themes[].hidden — 이름 없이 숨김만 적은 줄 · 왕복 · 형식 3) ② 합치기(숨김은 켠 DLC 가운데 하나라도 · 이름 · 색은 먼저 정의) · 렌즈 차림표의 주제(HT.lensThemes)
   ③ 갈래 색 — 같은 주제 안의 다른 갈래는 다른 색(겹치면 다음 자리 · 겹침이 없으면 예전 해시 색 그대로) ④ 렌즈 칸의 출처(HT.lensCellsOf — 제도 · 붕당의 집권 칸과 연정 · 체제를 지위로 대신 · 자료 없음)
   ⑤ 사건의 렌즈 주제(법률 = law · 선거 = election) ⑥ 연표 · 화면 뼈대(렌즈 켬 줄 배치 · 바꿔 끼움 · 옅게 · 그림 내보내기 · index.html · sw.js · 움직임 토큰) ⑦ 메이커 주제 표의 '렌즈에서 숨김' 칸 */
{
  const bad = msg => out.problems.push(`렌즈(웹): ${msg}`);
  try {
    const head = { format: HT.FORMAT, version: '1.0.0' };
    const read = raw => HT.normalizePack(Object.assign({}, head, raw));
    /* ① 숨김 칸 읽기 · 왕복 */
    {
      const r = read({ id: 'ln-hide', name: '숨김', themes: [{ id: 'military', hidden: true }, { id: 'magic', name: '마법 체계', hidden: true, kind: '마법' }, { hidden: true }, { id: 'tax', name: '세금 제도', hidden: false }] });
      const list = r.pack ? r.pack.themes : [];
      if (JSON.stringify(list) !== JSON.stringify([{ id: 'military', hidden: true }, { id: 'magic', name: '마법 체계', hidden: true, kind: '마법' }, { id: 'tax', name: '세금 제도' }])) bad(`숨김 칸 읽기가 어긋남(이름 없는 숨김 줄 · hidden: false는 칸 없음): ${JSON.stringify(list)}`);
      if (!r.warnings.some(w => /이름이 없어 뺐습니다/.test(w.msg))) bad('id도 이름도 없는 숨김 줄을 알리지 않음');
      const j = r.pack ? HT.packToJSON(r.pack) : null;
      const back = j ? read(JSON.parse(JSON.stringify(j))) : null;
      if (!j || j.formatVersion !== 3 || canon(HT.packToJSON(back.pack)) !== canon(j)) bad(`숨김 칸이 왕복에서 달라지거나 형식 3이 아님: ${j && j.formatVersion}`);
      const r2 = read({ id: 'ln-hide2', name: '숨김', themes: [{ id: 'bad id!', hidden: true }] });
      if ((r2.pack && (r2.pack.themes || []).length) || !r2.warnings.some(w => /올바르지 않아 뺐습니다/.test(w.msg))) bad('올바르지 않은 id에 이름 없이 숨김만 적은 줄을 빼지 않음');
    }
    /* ② 합치기 · 렌즈 차림표의 주제 */
    {
      const A = { id: 'pa', name: '이름 DLC', themes: [{ id: 'tax', name: '세금 제도', color: '#d4a39b' }] };
      const B = { id: 'pb', name: '숨김 DLC', themes: [{ id: 'tax', hidden: true }, { id: 'election', hidden: true }] };
      const ab = HT.mergeThemes([A, B]);
      const ba = HT.mergeThemes([B, A]);
      const t1 = ab.find(t => t.id === 'tax');
      const t2 = ba.find(t => t.id === 'tax');
      if (!t1 || t1.name !== '세금 제도' || !t1.hidden || t1.hiddenBy !== '숨김 DLC' || !t2 || t2.name !== '세금 제도' || !t2.hidden) bad(`숨김이 이름 · 색과 따로 합쳐지지 않음(하나라도 숨기면 숨김 · 이름은 이름 있는 정의): ${JSON.stringify([t1, t2])}`);
      if (ab.length !== 8 || ab.map(t => t.id).join() !== HT.THEMES.map(t => t.id).join()) bad('숨김만 적은 줄이 사전의 차례 · 개수를 바꿈');
      if (HT.mergeThemes([A]).find(t => t.id === 'tax').hidden || HT.THEMES.some(t => 'hidden' in t)) bad('숨기지 않은 주제가 숨거나 내장 뼈대(HT.THEMES)가 바뀜');
      if (Object.keys(HT.THEME_HINTS).join() !== HT.THEMES.map(t => t.id).join() || HT.themeHint({ id: 'tax' }) !== HT.THEME_HINTS.tax || HT.themeHint({ id: 'x', kind: '경제' }) !== '경제') bad('렌즈 차림표의 한마디(HT.THEME_HINTS · HT.themeHint)가 내장 여덟과 맞지 않음');
      const T = [{ id: 'la', name: '가 땅' }];
      const m = HT.buildModel([read({ id: 'ln-m', name: '렌즈', tracks: T, periods: [{ id: 'p', track: 'la', name: '솔나라', start: 600, end: 900 }], themes: [{ id: 'military', hidden: true }, { id: 'magic', name: '마법 체계' }], institutions: [{ theme: 'military', polity: '솔나라', spans: [['마을 군', null, 700]] }, { theme: '마법 체계', polity: '솔나라', spans: [['별 부름', 650]] }, { theme: '새 주제', polity: '솔나라', spans: [['처음', 610]] }] }).pack], null);
      const ids = HT.lensThemes(m).map(t => t.id);
      const mil = m.institutions.find(o => o.themeId === 'military');
      if (ids.includes('military') || !ids.includes('magic') || ids.length !== 9 || ids.indexOf('magic') !== 7 || !ids.some(id => /^theme-/.test(id))) bad(`렌즈 차림표의 주제가 어긋남(숨긴 군사제도 빠짐 · 마법 체계 · 자료 있는 사전 밖 주제 더함): ${ids.join()}`);
      if (!mil || (mil.warnings || []).length || !m.themes.find(t => t.id === 'military').hidden) bad('숨긴 주제의 제도가 그 주제를 찾지 못하거나 사전에서 빠짐(숨김은 렌즈 고르기에서만)');
    }
    /* ③ 갈래 색 */
    {
      let pair = null;
      const seen = new Map();
      for (let i = 0; i < 400 && !pair; i++) {
        const name = `갈래${i}`;
        const c = HT.autoColor(`family:system|${name}`);
        if (seen.has(c)) pair = [seen.get(c), name];
        else seen.set(c, name);
      }
      const T = [{ id: 'la', name: '가 땅' }, { id: 'lb', name: '나 땅' }];
      const P = [{ id: 'pa', track: 'la', name: '솔나라', start: 600, end: 900 }, { id: 'pb', track: 'lb', name: '물나라', start: 600, end: 900 }];
      const m = HT.buildModel([read({ id: 'ln-c', name: '색', tracks: T, periods: P, institutions: [
        { id: 'a', theme: 'system', polity: '솔나라', family: pair[0], spans: [['가', null, 700]] },
        { id: 'b', theme: 'system', polity: '솔나라', family: pair[1], spans: [['나', 700]] },
        { id: 'c', theme: 'system', polity: '물나라', family: pair[1], spans: [['나', 600]] },
        { id: 'd', theme: 'tax', polity: '물나라', family: '혼자', spans: [['밭', 600]] },
      ] }).pack], null);
      const col = id => m.institutions.find(o => o.id === id).color;
      if (col('a') === col('b') || col('b') !== col('c')) bad(`같은 주제의 다른 갈래가 같은 색이거나 같은 갈래가 나라마다 다른 색: ${[col('a'), col('b'), col('c')].join()}`);
      if (col('d') !== HT.pastel(HT.autoColor('family:tax|혼자')) || col(pair[0] < pair[1] ? 'a' : 'b') !== HT.pastel(HT.autoColor(`family:system|${pair[0] < pair[1] ? pair[0] : pair[1]}`))) bad('겹침이 없는 갈래(와 이름 차례가 앞선 갈래)의 색이 예전 해시 색과 다름');
    }
    /* ④ 렌즈 칸의 출처 · ⑤ 사건 */
    {
      /* 견본 sample-lantern — 불씨(ember) · 의회(parliament) 제도, 붕당 둘(진주파 · 닻파 — 집권 · 연정 · 실권), 지위 변천. 붕당 · 체제 주제의 제도 칸 · 연합 단체는 견본에 없음 */
      const pk = id => packs.find(p => p.id === id);
      if (!pk('lantern-chronicle')) bad('견본 sample-lantern을 찾지 못함');
      else {
        const m = HT.buildModel([pk('lantern-chronicle')], null);
        const P = name => m.periods.find(p => p.name === name);
        const emb = HT.lensCellsOf(P('등불 왕국'), 'ember');
        if (emb.src !== 'inst' || emb.cells.map(c => c.name).join() !== '아홉 가문 회의,빈 등좌 회의' || emb.cells.some(c => !c.uid || c.famKey !== 'ember|가문 회의')) bad(`제도 렌즈의 칸이 어긋남: ${JSON.stringify(emb.cells.map(c => [c.name, c.famKey]))}`);
        const sea = HT.lensCellsOf(P('산호 해상 동맹'), 'parliament');
        const uni = HT.lensCellsOf(P('하연 연합 왕국'), 'parliament');
        if (!sea.cells.length || !uni.cells.length || uni.cells[0].color !== sea.cells[1].color || uni.cells[0].famKey !== sea.cells[1].famKey) bad('같은 갈래의 다른 나라 렌즈 칸이 같은 색 · 같은 갈래가 아님 (메아리의 열쇠)');
        const fac = HT.lensCellsOf(P('산호 해상 동맹'), 'faction');
        const names = fac.cells.map(c => c.name);
        const coal = fac.cells.find(c => c.n === 2);
        if (fac.src !== 'group' || names.join(' / ') !== '진주파 / 닻파 / 진주파 · 닻파 / 진주파 / 닻파 / 진주파' || !coal || coal.start !== 1160 || coal.end !== 1200 || coal.short !== '진·닻' || !coal.color2 || coal.color2 === coal.color) bad(`붕당 렌즈의 칸(집권 · 연정 두 색 · 실권은 뺌)이 어긋남: ${names.join(' / ')} ${JSON.stringify(coal && [coal.start, coal.end, coal.short, coal.color, coal.color2])}`);
        if (HT.lensCellsOf(P('등불 왕국'), 'tax').src !== '') bad('자료 없는 나라의 렌즈 칸 출처가 빈 값이 아님');
        if (HT.lensCellsOf(P('등불 왕국'), 'system').src !== 'rank') bad('체제 렌즈가 제도 칸이 없을 때 지위 변천으로 가지 않음');
        if (!HT.lensAny(P('등불 왕국')) || HT.lensAny(P('빛나루 자유시')) || !HT.lensAny(P('산호 해상 동맹')) || HT.lensAny(P('새물섬'))) bad('렌즈 켬 줄 배치의 자료 판정(HT.lensAny)이 어긋남');
        if (HT.lensCellsOf(P('등불 왕국'), 'ember') !== emb) bad('렌즈 칸을 정권마다 기억하지 않음(그릴 때마다 다시 셈)');
        const at = HT.lensCellAt(P('등불 왕국'), 'ember', 412);
        if (!at || at.name !== '빈 등좌 회의' || HT.lensCellAt(P('등불 왕국'), 'ember', 411).name !== '아홉 가문 회의') bad('그 해의 렌즈 칸(이름 칸 부제)이 어긋남 — 경계 해는 뒤 칸');
        const E = t => m.events.find(e => e.title === t);
        const hit = (t, id) => HT.lensEventHit(E(t), id);
        if (!hit('공화국 헌법 반포', 'law') || !hit('첫 보통선거', 'election') || !hit('불꺼짐', 'ember') || hit('불꺼짐', 'law') || !hit('빛돌 전매법 반포', 'lightstone') || hit('빛돌 전매법 반포', 'tax')) bad('사건의 렌즈 주제(꼬리표 · 법 · 선거)가 어긋남');
        if (!HT.lensHasData(m, 'ember') || HT.lensHasData(m, 'tax') || HT.lensHasData(HT.buildModel([], null), 'tax')) bad('렌즈 자료 있음 판정(차림표의 자료 없음)이 어긋남');
      }
    }
    /* ⑥ 연표 · 화면 뼈대 (렌즈를 끄면 예전과 같은 길 — 그림은 scripts/lens-check.mjs가 브라우저에서) */
    {
      const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
      if (!/const leader = \(this\.show\.leaders && tr\.periods\.some\(p => p\.leaders && p\.leaders\.length\)\) \|\| \(this\.themeLens && tr\.periods\.some\(p => HT\.lensAny\(p\)\)\) \? G\.leader : 0;/.test(tsrc)) bad('렌즈 켬 줄 배치(지도자 칸 자리)가 렌즈 종류와 상관없는 하나가 아님');
      if (!/inner \+= lensL \? this\._lensRow\(p, lensL, X, ox, iw, gr\.leaderTop - BW, g\.leaderH, cut\) : this\._cells\(p\.leaders, 'leader', p, X, ox, iw, gr\.leaderTop - BW, g\.leaderH, cut\);/.test(tsrc)) bad('렌즈가 지도자 칸 자리에 바꿔 끼우지 않음(렌즈를 끄면 예전 길 그대로)');
      if (!/' is-nolens'/.test(tsrc) || !/lens: true, h/.test(tsrc) || !/mini: true/.test(tsrc)) bad('자료 없는 나라 옅게 · 지위 맞바꿈이 없음');
      if (!/lensSVG\(lensS, y \+ gp\.leaderTop, g\.leaderH, left, w, x1, x2\)/.test(tsrc) || !/<g opacity="0\.26">/.test(tsrc)) bad('그림 내보내기에 렌즈 칸 · 옅은 사건이 없음');
      if (!/new CustomEvent\('tl-data'\)/.test(tsrc)) bad("연표가 자료를 다시 넣은 뒤 'tl-data'를 알리지 않음 (렌즈 고르기가 주제가 사라졌는지 봄)");
      const view = readFileSync(join(root, 'index.html'), 'utf8');
      const sw = readFileSync(join(root, 'sw.js'), 'utf8');
      if (!(view.indexOf('src="js/lens-ui.js"') > view.indexOf('src="js/viewer.js"') && view.indexOf('src="js/viewer.js"') > 0) || !/id="themeLensBtn"/.test(view)) bad('index.html이 렌즈 단추 · js/lens-ui.js(viewer.js 다음)를 갖지 않음');
      if (!/'js\/lens-ui\.js'/.test(sw)) bad('sw.js 미리 담기에 js/lens-ui.js가 없음');
      const lsrc = readFileSync(join(root, 'js/lens-ui.js'), 'utf8');
      if (/localStorage/.test(lsrc) || !/HT\.store\.set\(K\.ui, state\.ui\)/.test(lsrc) || /viewer\.js/.test(lsrc.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, ''))) bad('렌즈 설정을 보는 사람 설정(ui.themeLens — HT.store)으로 기억하지 않거나 viewer.js를 건드림');
      if (/재위|즉위|퇴위|재임|임기|계승/.test(lsrc)) bad('렌즈 고르기에 쓰지 않기로 한 낱말이 있음');
      const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
      const blk = csrc.slice(csrc.indexOf('/* ── 렌즈 (주제 보기'));
      if (!blk || !/\.tl\.has-themelens :is\(\.tl-ev, \.tl-rail, \.tl-clu\)\.no-lens \{ opacity: \.26; \}/.test(blk) || !/\.tl-band \.tl-cell\.is-nolens \{ opacity: \.4; \}/.test(blk)) bad('렌즈 CSS(사건 .26 · 자료 없는 지도자 칸 .4)가 없음');
      if (/\d+(\.\d+)?m?s\b/.test(blk.replace(/var\(--t-[a-z]+\)/g, ''))) bad('렌즈 CSS의 움직임이 토큰(--t-micro …)이 아닌 시간을 씀');
    }
    /* ⑦ 메이커 주제 표 */
    {
      const t = HT.makerKit && HT.makerKit.BASE_TABLES.themes;
      const col = t && t.cols.find(c => c.key === 'hidden');
      if (!col || col.type !== 'check' || t.dropped({ id: 'military', hidden: true }) !== '' || !t.dropped({ id: 'military' }) || t.dropped({ name: '가' }) !== '') bad('메이커 주제 표에 렌즈에서 숨김(check) 칸이 없거나 숨김만 켠 줄을 빠지는 줄로 알림');
      const msrc = readFileSync(join(root, 'js/maker.js'), 'utf8');
      if (!/if \(col\.type === 'check'\) \{\s*if \(text === true\) x\[col\.key\] = true;\s*else delete x\[col\.key\];/.test(msrc) || !/writeCol\(col, r\.x, col\.type === 'check' \? e\.target\.checked : e\.target\.value\)/.test(msrc)) bad("메이커 표의 check 칸이 켜면 true · 끄면 칸을 지우지 않음");
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [72] 집권 단 · 실권 단 · 연합 표시 — 웹(감독 선택 D5 결정 1 A · 2 · 3 C + 덧판 x1 A 짙은 칠 · x2 A 겹 탭 · x3 C 두 색 + 색 점, 원칙 "단어로 구분하지 말 것" · 설계 docs/설계-10건/7-8-단체와-렌즈.md 11절):
   ① 집권 기간 칸 이름의 낱말(실권 · 연정 · 집권) ② 나라의 단체 칸(HT.groupStrip — 견본 sample-lantern의 집권 · 연정 2 · 실권 · 명목) · 붕당 렌즈가 같은 칸
   ③ 단체 자동 색의 겹침 막기(같은 나라 — 겹치면 다음 자리 · 적은 색이 이김 · 함께 집권한 같은 색이면 경고) ④ 줄 배치(덧단 = 줄 단위 · 집권 + 실권 두 줄 = +46 · 집권만 = +23 · 자료 없는 줄 · 표시를 끄거나
   내보내기의 연표(show에 groups가 없음)는 1px도 그대로) ⑤ 단체 칸의 HTML(딱지 글 없음 · 점 수 = 단체 수 · 실권 · 두 색 · 줄임) ⑥ 연합의 겹 탭 값 묶음 · 끈 때 없음(견본에 연합 단체가 없어 가담 기간 · 탭 자리 셈은 빠짐)
   ⑦ CSS · 그림 내보내기 · 끄는 동안의 자리 · 움직임 토큰 — 브라우저 그림은 scripts/power-check.mjs */
{
  const bad = msg => out.problems.push(`집권 · 실권 · 연합(웹): ${msg}`);
  try {
    const TL = HT.Timeline;
    if (!TL || typeof TL.prototype._groupCells !== 'function' || typeof TL.prototype._coalTabPlan !== 'function' || typeof HT.groupStrip !== 'function' || typeof HT.coalitionsOf !== 'function') throw new Error('HT.groupStrip · HT.coalitionsOf · Timeline의 _groupCells · _coalTabPlan이 없음');
    /* ① 낱말 */
    const kinds = [['실권', 'real'], ['섭정', 'real'], ['수렴 청정', 'real'], ['연정', 'coal'], ['공동 집권', 'coal'], ['연립', 'coal'], ['집권', 'power'], ['모르는 말', 'power'], ['', 'power']].filter(([w, k]) => HT.powerSpanKind(w) !== k);
    if (kinds.length) bad(`집권 기간 칸 이름의 낱말을 잘못 가름: ${JSON.stringify(kinds)}`);
    /* ② 견본 sample-lantern의 칸 — 산호 해상 동맹의 붕당 둘(진주파 · 닻파: 집권 · 연정 · 실권), 하연의 정당 둘 (--skip으로 견본을 뺐으면 건너뜀).
       세 단체 연정 · 짝을 모르는 연정 · 연합 단체(가담 기간 · 겹 탭 ⑥)는 견본에 없음 */
    const sp = packs.find(p => p.id === 'lantern-chronicle');
    if (sp) {
      const m = HT.buildModel([sp], null);
      const P = name => m.periods.find(p => p.name === name);
      const garam = P('산호 해상 동맹');
      const S = HT.groupStrip(garam);
      const cellText = c => `${c.name}${c.n > 1 ? `×${c.n}` : ''}${c.solo ? '?' : ''}@${c.start}-${c.end}`;
      const want = '진주파@1031-1120 | 닻파@1120-1160 | 진주파 · 닻파×2@1160-1200 | 진주파@1200-1250 | 닻파@1250-1340 | 진주파@1352-1402';
      if (S.power.map(cellText).join(' | ') !== want) bad(`집권 칸(연정 2)이 어긋남: ${S.power.map(cellText).join(' | ')}`);
      const two = S.power.find(c => c.n === 2);
      if (!two || two.colors.length !== 2 || two.uids.length !== 2 || two.color !== two.colors[0] || two.color2 !== two.colors[1] || new Set(two.colors).size !== 2 || two.short !== '진·닻') bad('두 단체 연정 칸의 색 목록(점) · 위아래 두 색 · 첫 글자가 어긋남');
      if (S.real.map(cellText).join(' | ') !== '진주파@1340-1352' || !S.real.every(c => c.real)) bad(`실권 칸(실권 집단)이 어긋남: ${S.real.map(cellText).join(' | ')}`);
      const nom = [...S.nominal].map(i => garam.leaders[i].name).join();
      if (nom !== '물새 아라') bad(`명목 지도자(제 기간의 절반 이상이 실권과 겹침)가 어긋남: ${nom}`);
      if (HT.groupStrip(P('산호 섬나라')).power.length || HT.groupStrip(P('하연 연합 왕국')).real.length || HT.groupStrip(garam) !== S) bad('단체 자료 없는 나라에 칸이 생기거나 정권마다 기억하지 않음');
      const lens = HT.lensCellsOf(garam, 'faction');
      if (lens.src !== 'group' || lens.cells.map(cellText).join(' | ') !== want) bad('붕당 렌즈의 칸이 집권 단과 같은 셈이 아님(맞바꿈의 바탕)');
      if (m.groups.some(g => g.warnings.length)) bad(`견본의 단체에 경고: ${m.groups.filter(g => g.warnings.length).map(g => `${g.name} — ${g.warnings.join(' / ')}`).join(' · ')}`);
      /* ④ 줄 배치 — 가짜 this로 _layoutTrack (dev-smoke 조감 블록의 lay와 같은 길) */
      const lay = (track, show) => {
        const t = Object.assign(Object.create(TL.prototype), { folded: new Set(), foldedPeoples: new Set(), foldedEras: new Set(), expandedHosts: new Set(), scopesOn: {}, show, density: 0, view: { start: -700, end: 1950 }, _lod: new Map(), leaderMode: 'auto', birdShape: 'a', birdAuto: false, _bird: null });
        t._proxies = TL.depProxies(m.periods);
        t._setScopes(m.scopes || []);
        t._cats = new Map(HT.DEFAULT_CATEGORIES.map((c, i) => [c.id, { name: c.name, color: c.color, i }]));
        t._dynUids = new Set();
        const tr = Object.assign({}, m.tracks.find(x => x.id === track), { periods: m.periods.filter(p => p.track === track), events: m.events.filter(e => e.track === track).map(e => Object.assign({}, e, { _place: { track: e.track, polityUid: e.polityUid }, _sec: false, _pi: 0 })), figures: [] });
        t._layoutTrack(tr);
        return tr;
      };
      const EXP = { leaders: true, cabinets: true, eras: true, capitals: true, ganji: true, succession: true, partOf: true, epochs: true }; // 내보내기의 연표(prototype/scripts/export/base.mjs)와 같은 show
      const on = lay('sanho', Object.assign({}, HT.SHOW_DEFAULTS));
      const off = lay('sanho', Object.assign({}, HT.SHOW_DEFAULTS, { groups: false }));
      const exp = lay('sanho', EXP);
      const rG = garam._row;
      const g1 = on.geos[rG];
      const g0 = off.geos[rG];
      if (HT.SHOW_DEFAULTS.groups !== true) bad('표시 체크 groups의 기본값이 켬(true)이 아님');
      if (on.rowHs[rG] - off.rowHs[rG] !== 2 * (TL.G.power + TL.G.powerGap) || TL.G.power !== 20 || TL.G.powerGap !== 3) bad(`집권 + 실권 두 줄의 덧단이 +46((20 + 틈 3) × 2)이 아님: ${on.rowHs[rG]} − ${off.rowHs[rG]}`);
      if (g1.powerH !== 20 || g1.realH !== 20 || g1.powerTop !== g0.leaderTop || g1.realTop !== g1.powerTop + 23 || g1.leaderTop !== g1.realTop + 23 || g1.textTop !== g0.textTop + 46) bad(`덧단의 자리(위 집권 · 아래 실권 · 지도자 칸 바로 위)가 어긋남: ${JSON.stringify([g1.powerTop, g1.realTop, g1.leaderTop, g0.leaderTop])}`);
      /* 하연: 집권만 있는 줄(부흥국 → 연합 왕국 → 공화국)은 한 줄(+23) · 단체 자료가 없는 줄(아랫물국)은 그대로 */
      const hOn = lay('hayeon', Object.assign({}, HT.SHOW_DEFAULTS));
      const hOff = lay('hayeon', Object.assign({}, HT.SHOW_DEFAULTS, { groups: false }));
      const hExp = lay('hayeon', EXP);
      const rU = P('하연 연합 왕국')._row;
      const rN = P('아랫물국')._row;
      if (hOn.rowHs[rU] - hOff.rowHs[rU] !== TL.G.power + TL.G.powerGap || hOn.geos[rU].realH) bad(`집권만 있는 줄의 덧단이 한 줄(+23)이 아님: ${hOn.rowHs[rU]} − ${hOff.rowHs[rU]}`);
      if (hOn.rowHs[rN] !== hOff.rowHs[rN] || hOn.geos[rN].powerH || hOn.geos[rN].realH) bad('단체 자료가 없는 줄(아랫물국)이 높아짐 — 덧단은 줄 단위');
      for (const [e, o] of [[exp, off], [hExp, hOff]]) if (JSON.stringify(e.rowHs) !== JSON.stringify(o.rowHs) || JSON.stringify(e.geos.map(g => g.leaderTop)) !== JSON.stringify(o.geos.map(g => g.leaderTop))) bad('내보내기의 연표(show에 groups가 없음)가 덧단을 넣음 — 새 앱이 단체 단을 그리기 전까지 예전 배치 그대로여야 함(계약 3절의 자체 점검)');
      /* ⑤ 단체 칸 HTML (가짜 this — 글자 폭은 이 검사의 가짜 캔버스: 한 글자 7px) */
      const t = Object.assign(Object.create(TL.prototype), { show: Object.assign({}, HT.SHOW_DEFAULTS), density: 0, _bird: null, showAlt: false, spots: [], _litCols: null, _litEdges: null, _groupFocus: null });
      const X = y => (y - 1020) * 4; // 1년 = 4px
      const html = TL.prototype._groupCells.call(t, garam, S.power, X, 0, 1600, 0, 13, {});
      const cells = [...html.matchAll(/<i class="tl-cell k-group([^"]*)"[^>]*data-groups="([^"]*)"[^>]*>(.*?)<\/i>(?=<i class="tl-cell|$)/g)].map(x => ({ cls: x[1], groups: x[2].split(' '), dots: (x[3].match(/class="gd"/g) || []).length, text: (x[3].match(/<b[^>]*>([^<]*)<\/b>/) || [])[1] || '' }));
      if (cells.length !== S.power.length) bad(`단체 칸 수가 어긋남(${cells.length} ≠ ${S.power.length})`);
      else {
        const bad5 = cells.map((c, i) => [c, S.power[i]]).filter(([c, s]) => c.dots !== (s.solo ? 1 : s.n > 1 ? s.n : 0) && !(c.dots === 0 && !c.text) || /is-two/.test(c.cls) !== s.n > 1 || /is-solo/.test(c.cls) !== !!s.solo || c.groups.join() !== s.uids.join());
        if (bad5.length) bad(`단체 칸의 점 수(= 함께 집권한 단체 수) · 두 색 · 짝 모름 · data-groups가 어긋남: ${JSON.stringify(bad5.map(([c]) => c))}`);
      }
      if (/>(집권|실권|연정|연합)(\s|\d|<)/.test(html) || /class="(sch|mk-tag|tag)"/.test(html)) bad('단체 칸에 딱지 글(집권 · 실권 · 연정)이 있음 — 감독 원칙: 모양 · 색으로만');
      const realHtml = TL.prototype._groupCells.call(t, garam, S.real, X, 0, 1600, 15, 13, {});
      if ((realHtml.match(/ is-real/g) || []).length !== S.real.length || /class="gd"/.test(realHtml)) bad('실권 칸이 is-real(짙은 칠)이 아니거나 점이 붙음');
      const narrow = TL.prototype._groupCells.call(t, garam, S.power, y => (y - 1020) * 0.6, 0, 300, 0, 13, {});
      if (/<b[^>]*>[^<]*…/.test(narrow) || /is-clip/.test(narrow)) bad('좁은 단체 칸이 글을 반쯤 자름(이름 → 첫 글자 → 없음이어야 함)');
      const lensHtml = TL.prototype._groupCells.call(t, garam, S.power, X, 0, 1600, 0, 20, { lens: true });
      if (!/k-group k-lens/.test(lensHtml) || !/height:20px/.test(lensHtml)) bad('붕당 렌즈의 칸이 지도자 자리(20px · k-lens)에 단체 칸 꼴로 그려지지 않음');
      /* ⑥ 연합의 겹 탭 자리 — 견본에 연합 단체가 없어 값 묶음 · 끈 때만 */
      const TAB = TL.TAB;
      if (TAB.backDx !== 4 || TAB.backDy !== 3 || TAB.coalPad !== 9) bad('겹 탭의 뒤 장 어긋남(4px 오른쪽 · 3px 위) · 안 여백(9px)이 덧판 x2 A와 다름');
      if (TL.prototype._coalTabPlan.call({ show: {} }, garam, X, 4000, 200, 260, 984, []).length) bad('표시를 끈 때(또는 내보내기)에도 연합 탭이 생김');
    }
    /* ③ 단체 자동 색의 겹침 막기 */
    {
      const pal = HT.PASTEL.map(c => c.id);
      const ids = Array.from({ length: 60 }, (_, i) => `g${i}`);
      const slot = id => pal.indexOf(HT.autoColor(`grc/${id}`.replace(/^/, 'group:')));
      let pair = null;
      for (let i = 0; i < ids.length && !pair; i++) for (let j = i + 1; j < ids.length && !pair; j++) if (slot(ids[i]) === slot(ids[j])) pair = [ids[i], ids[j]];
      const base = { format: HT.FORMAT, version: '1.0.0', id: 'grc', name: '색', tracks: [{ id: 'grc-t', name: '가' }], periods: [{ id: 'p', track: 'grc-t', name: '가 나라', start: 100, end: 300 }] };
      const mk = groups => HT.buildModel([HT.normalizePack(Object.assign({}, base, { groups })).pack], null);
      if (!pair) bad('겹치는 자동 색 둘을 찾지 못함(검사 자료)');
      else {
        const m1 = mk([{ id: pair[0], track: 'grc-t', name: '가 무리', within: '가 나라', start: 100, end: 200, power: [['집권', 110, 150]] }, { id: pair[1], track: 'grc-t', name: '나 무리', within: '가 나라', start: 120, end: 220, power: [['연정', 120, 150]] }]);
        const [a, b] = ['가 무리', '나 무리'].map(n => m1.groups.find(g => g.name === n));
        if (!a || !b || a.color === b.color || a.color !== HT.pastel(HT.autoColor(`group:grc/${pair[0]}`))) bad('같은 나라 단체의 자동 색이 겹침(이름 차례로 앞 단체는 해시 색 그대로 · 뒤 단체는 다음 자리)');
        const m2 = mk([{ id: pair[0], track: 'grc-t', name: '가 무리', within: '가 나라', start: 100, end: 200 }, { id: 'other', track: 'grc-t', name: '다 무리', start: 100, end: 200 }]);
        if (m2.groups.find(g => g.name === '가 무리').color !== HT.pastel(HT.autoColor(`group:grc/${pair[0]}`))) bad('겹침이 없는 단체의 자동 색이 바뀜(예전 색 그대로여야 함)');
        const m3 = mk([{ id: 'x1', track: 'grc-t', name: '가 무리', within: '가 나라', start: 100, end: 200, color: '#d4a39b', power: [['집권', 110, 150]] }, { id: 'x2', track: 'grc-t', name: '나 무리', within: '가 나라', start: 100, end: 200, color: '#d4a39b', power: [['연정', 140, 160]] }]);
        const w3 = m3.groups.find(g => g.name === '나 무리').warnings;
        if (m3.groups.find(g => g.name === '나 무리').color !== '#d4a39b' || !w3.some(w => /함께 집권한 단체 "가 무리"와\(과\) 색이 같아/.test(w))) bad('적은 색이 이기지 않거나 · 함께 집권한 같은 색 단체에 경고가 없음');
      }
    }
    /* ⑦ CSS · 연표 뼈대 · 그림 내보내기 */
    {
      const tsrc = readFileSync(join(root, 'js/timeline.js'), 'utf8');
      const csrc = readFileSync(join(root, 'css/common.css'), 'utf8');
      const blk = csrc.slice(csrc.indexOf('/* ── 단체 단 · 연합 표시'));
      if (!blk || blk.length < 100) bad("common.css에 '단체 단 · 연합 표시' 블록이 없음");
      else {
        if (!/\.k-group\.is-real \{[^}]*color-mix\(in oklab, var\(--c\) 64%, var\(--paper-ink\)\)[^}]*background: color-mix\(in srgb, var\(--c\) 78%, var\(--paper\)\)/.test(blk)) bad('실권 칸이 단체 색 78% · 그 색 64%의 짙은 테두리가 아님(덧판 x1 A)');
        if (!/\.k-group \{[^}]*background: color-mix\(in srgb, var\(--c\) 40%, var\(--paper\)\)/.test(blk) || !/\.k-group\.is-two \{ background: linear-gradient\(180deg, color-mix\(in srgb, var\(--c\) 42%, var\(--paper\)\) 0 50%, color-mix\(in srgb, var\(--c2\) 42%/.test(blk)) bad('집권 칸 40% · 연정 칸 위아래 두 색 42%가 아님(결정 1 A · 덧판 x3 C)');
        if (!/\.gd \{[^}]*width: 6px; height: 6px;/.test(blk)) bad('연정 칸의 색 점이 6px가 아님');
        if (!/\.tl-htab\.k-coal \{ --tm: 34%;/.test(blk) || !/\.k-coal > svg \.bf \{ fill: color-mix\(in srgb, var\(--c\) 18%, var\(--paper\)\)/.test(blk)) bad('연합의 겹 탭이 앞 장 34% · 뒤 장 18%가 아님(덧판 x2 A)');
        if (!/\.k-leader\.is-nominal b \{ opacity: \.5; \}/.test(blk)) bad('명목 지도자의 이름이 50%가 아님(결정 2 A)');
        if (/\d+(\.\d+)?m?s\b/.test(blk.replace(/var\(--t-[a-z]+\)/g, ''))) bad('단체 단 · 연합 CSS의 움직임이 토큰(--t-micro …)이 아닌 시간을 씀');
      }
      if (!/if \(gr\.powerH \|\| gr\.realH\) inner \+= this\._groupRows\(p, X, ox, iw, gr, BW, cut, lensL\);/.test(tsrc)) bad('띠 안에 단체 단(_groupRows)을 그리지 않음');
      if (!/if \(L\.src === 'group'\) return this\._groupCells\(/.test(tsrc)) bad('붕당 렌즈가 집권 단의 칸 꼴(_groupCells)로 지도자 자리에 그리지 않음');
      if (!/body \+= groupSVG\(gS\.real, y \+ gp\.realTop, G\.power, left, w, x1, x2\)/.test(tsrc) || !/this\._coalTabPlan\(p, X, W, x1, from, flatR, host\)\) \{\s*const col = c\.group\.color;/.test(tsrc)) bad('그림 내보내기에 단체 단 · 연합의 겹 탭이 없음');
      if (!/new Map\(this\._backTabPlan\(p, X, W, left, /.test(tsrc)) bad('끄는 동안(_drawTrackScene)의 뒤 장 탭 자리가 연합 탭까지 다시 잡지 않음');
      if (!/const groupsOn = !!this\.show\.groups && this\.density <= 0;/.test(tsrc)) bad('단체 단이 표시 체크(켜져 있어야)를 따르지 않음 — 내보내기의 연표는 groups 열쇠가 없음');
    }
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [D5-가] 단체 · 렌즈의 남은 이음 — 웹(10건 D5 이어하기 3절 라 · 2026-10-13):
   ① 앞선 단체의 방식 '미상'(HT.GROUP_HOWS의 unknown — 비움 = 적지 않음과 다름): 읽기 · 이름 · 왕복 · 계보 나무의 이음 종류
   ② 필터 시트의 '단체' 체크(연표 · 메이커 두 화면 · viewer.js SHOW_TOGGLES) ③ 범례의 단체 줄이 연표와 같은 견본 도우미를 부름 ④ 메이커 미리보기의 렌즈 고르기
   ⑤ 계보 창의 집권 덩이 종류가 띠 위 단체 단과 같은 낱말 표(HT.powerSpanKind) — 브라우저 그림은 scripts/power-check.mjs · lens-check.mjs */
{
  const bad = msg => out.problems.push(`단체 · 렌즈의 남은 이음(웹): ${msg}`);
  try {
    /* ① 미상 */
    const hows = [['미상', 'unknown'], ['모름', 'unknown'], ['방식 미상', 'unknown'], ['unknown', 'unknown'], ['갈라짐', 'split'], ['', ''], ['아무 말', '']].filter(([w, k]) => HT.groupHow(w) !== k);
    if (hows.length) bad(`앞선 단체의 방식을 잘못 읽음: ${JSON.stringify(hows)}`);
    if (HT.groupHowName('unknown') !== '미상') bad(`방식 unknown의 이름: ${HT.groupHowName('unknown')}`);
    const raw = {
      format: 'history-timeline-dlc', formatVersion: 3, id: 'd5-how-check', name: '가상 방식 미상', version: '1.0.0',
      tracks: [{ id: 'd5h-a', name: '가상 갈래' }],
      periods: [{ id: 'd5h-p', track: 'd5h-a', name: '달못 나라', start: 100, end: 300 }],
      groups: [
        { id: 'd5h-old', track: 'd5h-a', name: '옛 모임', type: 'faction', start: 100, end: 180, within: '달못 나라', power: [['집권', 110, 170]] },
        { id: 'd5h-new', track: 'd5h-a', name: '새 모임', type: 'faction', start: 180, end: 300, within: '달못 나라', from: [{ group: '옛 모임', how: '미상' }], power: [['섭정', 200, 240], ['집권', 240, 290]] },
        { id: 'd5h-etc', track: 'd5h-a', name: '곁 모임', type: 'faction', start: 190, end: 260, within: '달못 나라', from: [{ group: '옛 모임' }] },
      ],
    };
    const r = HT.normalizePack(raw);
    if (!r.pack || r.errors.length) bad(`방식 미상을 적은 DLC가 읽히지 않음: ${JSON.stringify(r.errors)}`);
    else {
      const json = HT.packToJSON(r.pack);
      const how = id => ((json.groups.find(g => g.id === id).from || [])[0] || {}).how;
      if (how('d5h-new') !== 'unknown' || how('d5h-etc') !== undefined) bad(`파일에 방식이 잘못 적힘: ${how('d5h-new')} · ${how('d5h-etc')}`);
      if (JSON.stringify(HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(json))).pack)) !== JSON.stringify(json)) bad('방식 미상의 왕복이 같지 않음');
      if (!HT.groupTreeLayout) load('js/group-tree.js');
      const m = HT.buildModel([r.pack], null);
      const polity = m.periods.find(p => p.name === '달못 나라');
      const tree = HT.groupTreeLayout(m, { polityUid: polity.uid });
      const kinds = (tree ? tree.edges : []).map(e => e.kind).sort().join();
      if (kinds !== 'blank,unknown') bad(`계보 나무의 이음 종류: ${kinds} (미상 = unknown · 적지 않음 = blank여야 함)`);
      /* ⑤ 계보 창의 집권 덩이: '섭정'은 실권(띠 위 단체 단과 같은 낱말 표) */
      const node = tree && tree.nodes.find(n => n.g.name === '새 모임');
      const segs = node ? node.segs.map(s => s.kind).join() : '';
      if (segs !== 'real,power') bad(`계보 창의 집권 덩이 종류: ${segs} (섭정 = real · 집권 = power여야 함)`);
    }
    const gsrc = readFileSync(join(root, 'js/group-tree.js'), 'utf8');
    if (!/const spanKind = c => HT\.powerSpanKind\(c\.name\);/.test(gsrc) || /const REAL = /.test(gsrc)) bad('계보 창이 집권 칸의 종류를 제 낱말 표로 따로 셈함(HT.powerSpanKind를 써야 함)');
    /* ② 필터의 '단체' 체크 */
    const vsrc = readFileSync(join(root, 'js/viewer.js'), 'utf8');
    if (!/SHOW_TOGGLES, \{ groupToggle: 'groups' \}/.test(vsrc)) bad("viewer.js의 표시 체크 목록에 '단체'(groupToggle → groups)가 없음");
    for (const page of ['index.html', 'dlc-maker.html']) {
      const html = readFileSync(join(root, page), 'utf8');
      if (!/<input id="groupToggle" type="checkbox" checked> 단체<\/label>/.test(html)) bad(`${page}의 필터 시트에 '단체' 체크가 없음(기본 켬)`);
      if (html.indexOf('id="rankToggle"') > html.indexOf('id="groupToggle"') || html.indexOf('id="groupToggle"') > html.indexOf('id="figureToggle"')) bad(`${page}: '단체' 체크의 자리가 지위 다음 · 인물 앞이 아님`);
    }
    if (HT.SHOW_DEFAULTS.groups !== true) bad('표시 체크 단체의 기본값이 켬이 아님');
    /* ③ 범례 */
    if (!/HT\.Timeline\.coalTabSample\(\)/.test(vsrc) || !/HT\.Timeline\.groupCellSample\(kind\)/.test(vsrc)) bad('범례가 연표의 견본 도우미(coalTabSample · groupCellSample)를 부르지 않음');
    const TL = HT.Timeline;
    for (const svg of [TL.coalTabSample(), TL.groupCellSample('power'), TL.groupCellSample('coal'), TL.groupCellSample('real')]) {
      if (!/^<svg class="lg-seam"/.test(svg) || /fbf7ef|2e2820/i.test(svg)) bad(`범례 견본의 꼴 · 바탕색(옛 종이빛이 남음): ${svg.slice(0, 80)}`);
    }
    if ((TL.coalTabSample().match(/<path /g) || []).length !== 4) bad('겹 탭 견본이 뒤 장 · 앞 장(칠 · 선 넷)이 아님');
    if ((TL.groupCellSample('coal').match(/<circle /g) || []).length !== 2) bad('함께 집권 견본의 색 점이 둘이 아님');
    /* ④ 메이커 미리보기의 렌즈 고르기 */
    const mk = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
    if (!(mk.indexOf('js/lens-ui.js') > mk.indexOf('js/viewer.js') && mk.indexOf('js/viewer.js') > 0)) bad('dlc-maker.html이 viewer.js 다음에 js/lens-ui.js를 읽지 않음');
    const lsrc = readFileSync(join(root, 'js/lens-ui.js'), 'utf8');
    if (!/document\.getElementById\('mkCTabs'\)/.test(lsrc)) bad('lens-ui.js가 메이커의 가운데 탭 줄에 단추를 만들지 않음');
    if (!/\.mk-ctabs \.lens-btn \{/.test(readFileSync(join(root, 'css/maker.css'), 'utf8'))) bad('메이커 탭 줄의 렌즈 단추 크기 규칙이 없음');
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [73] 형식 3 — 문서 그림 (10건 D3 결정 8 · 9 · 16건 15번 — DLC-형식.md '문서 그림' · docs/설계-10건/4-5-메이커-블록과-묶음.md 2절 6):
   형식 버전(images를 쓴 파일만 3) · 읽기(필수 칸 · 그림 꼴 · 한 장 · 합 한도 · 겹친 id · 이름 · 크기) · 왕복 · 패치 대상 아님 · 모델의 그림 사전(그 팩의 것만) ·
   렌더러([[파일:…]] → 오른쪽에 띄운 그림 · 가운데 · 그림 없음 · 줄 가운데 그림 · 그림을 모르는 곳은 예전처럼 지움 · 옛 문서는 1글자도 다르지 않음) · 반영하지 않은 고침 */
{
  const bad = msg => out.problems.push(`문서 그림: ${msg}`);
  try {
    if (!HT.namu) load('js/wiki.js');
    const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    const mk = extra => Object.assign({ format: HT.FORMAT, id: 'smoke-img', name: '그림 검사', tracks: [{ id: 'im-a', name: '검사 바다' }], periods: [{ id: 'pa', track: 'im-a', name: '갑 나라', start: 100, end: 300 }] }, extra);
    const norm = extra => HT.normalizePack(mk(extra));
    const has = (r, re, which = 'warnings') => r[which].some(w => re.test(w.msg));
    const L = HT.PACK_LIMITS;
    if (L.docImage !== 2000000 || L.docImageTotal !== 20000000) bad(`한도가 설계와 다름: ${L.docImage} · ${L.docImageTotal}`);
    /* 형식 버전 */
    const fv = extra => HT.packToJSON(norm(extra).pack).formatVersion;
    if (fv({ images: [{ id: 'g', name: '그림.png', src: PNG }] }) !== 3) bad('images를 쓴 파일이 3으로 나가지 않음');
    if (fv({ images: [] }) !== 1) bad('빈 images만 적은 파일이 1로 나가지 않음');
    if (!(HT.NEW_FORMAT_KEYS_V3 || []).includes('images[]') || (HT.NEW_FORMAT_KEYS || []).includes('images[]')) bad('images[]가 형식 3 목록에만 있지 않음');
    /* 읽기 */
    const r = norm({ images: [
      { id: 'g1', name: '바다.png', src: PNG, caption: '  바다 그림 ', alt: '바다', credit: '검사', width: 800, height: '450' },
      { name: '이름만.png', src: PNG },
      { id: 'g1', name: '겹친 id', src: PNG },
      { id: 'g3', name: '바다.png', src: PNG, width: -3 },
      { id: 'g4', name: '그림 아님', src: 'data:text/plain;base64,QQ==' },
      { id: 'g5', name: '빈 그림' },
      { id: 'g6', name: '큰 그림', src: 'data:image/png;base64,' + 'A'.repeat(L.docImage) },
      'x',
    ] });
    const g = r.pack.images || [];
    if (g.length !== 3) bad(`읽힌 그림 수가 3이 아님: ${g.map(x => x.id).join(',')}`);
    else {
      if (g[0].caption !== '바다 그림' || g[0].height !== 450 || g[0].width !== 800 || g[0].credit !== '검사') bad(`설명 · 크기가 읽히지 않음: ${JSON.stringify(Object.assign({}, g[0], { src: '…' }))}`);
      if (g[1].id !== `img-${HT.hash('이름만.png')}` || g[1].name !== '이름만.png') bad(`id 없는 그림의 id가 이름에서 나오지 않음: ${g[1].id}`);
      if ('width' in g[2]) bad('음수 폭이 남음');
    }
    for (const re of [/id "g1"가 겹쳐/, /이름이 앞 그림과 같아/, /폭\(width\)/]) if (!has(r, re)) bad(`경고가 없음: ${re}`);
    for (const re of [/png · jpeg · webp/, /그림\(src\)이 비어/, /너무 커서/, /형식이 올바르지 않습니다/]) if (!has(r, re, 'errors')) bad(`오류가 없음: ${re}`);
    const many = Array.from({ length: 12 }, (_, i) => ({ id: `t${i}`, name: `t${i}`, src: 'data:image/png;base64,' + 'A'.repeat(1900000) }));
    const rt = norm({ images: many });
    if ((rt.pack.images || []).length !== 10 || !has(rt, /합친 크기가 한도/, 'errors')) bad(`팩 그림 합 한도에서 뒤의 그림부터 빠지지 않음: ${(rt.pack.images || []).length}`);
    if (!has(norm({ images: { id: 'x' } }), /목록이어야/)) bad('목록이 아닌 images에 경고가 없음');
    /* 왕복 · 패치 대상 아님 */
    const j = HT.packToJSON(r.pack);
    if (canon(HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(j))).pack)) !== canon(j)) bad('그림 사전이 왕복에서 달라짐');
    if (HT.PATCHABLE.includes('images')) bad('images가 패치 대상 칸에 들어 있음');
    /* 모델: 그 문서 글을 적은 팩의 사전에서만 · id → 이름 → 대소문자 */
    const other = HT.normalizePack({ format: HT.FORMAT, id: 'smoke-img2', name: '다른 팩', tracks: [{ id: 'im-b', name: '다른 바다' }], periods: [{ id: 'pb', track: 'im-b', name: '을 나라', start: 100, end: 300 }], images: [{ id: 'o1', name: '다른.png', src: PNG }], documents: { 'pb': '[[파일:다른.png]] [[파일:바다.png]]' } }).pack;
    const m = HT.buildModel([r.pack, other], null);
    if (!m.imageMap || m.imageMap.size !== 2) bad('모델에 그림 사전(imageMap)이 팩마다 생기지 않음');
    const hit = HT.docImageOf(m, 'smoke-img', 'g1');
    if (!hit || hit.uid !== 'img:smoke-img/g1' || hit.packId !== 'smoke-img') bad(`id로 찾기 · uid가 틀림: ${hit && hit.uid}`);
    if (HT.docImageOf(m, 'smoke-img', '바다.png') !== hit || HT.docImageOf(m, 'smoke-img', '파일:바다.PNG') !== hit) bad('이름(대소문자 무시 · "파일:" 머리)으로 찾지 못함');
    if (HT.docImageOf(m, 'smoke-img2', '바다.png') || HT.docImageOf(m, 'smoke-img', '다른.png') || HT.docImageOf(m, '', 'g1')) bad('다른 팩의 그림 사전에서 찾음(그 문서 글을 적은 팩의 것만이어야 함)');
    const m0 = HT.buildModel([norm({}).pack], null);
    if (!m0.imageMap || m0.imageMap.size) bad('그림이 없는 모델에 빈 그림 사전이 없거나 차 있음');
    /* 렌더러 */
    const N = HT.namu;
    const spec = N.fileSpec('파일:바다.png|width=50%|align=center|기타=1');
    if (canon(spec) !== canon({ name: '바다.png', width: '50%', align: 'center' })) bad(`fileSpec이 틀림: ${JSON.stringify(spec)}`);
    if (N.fileSpec('이미지:x|width=300').width !== '300px' || N.fileSpec('file:x|width=0').width !== '' || N.fileSpec('파일:x|align=top').align !== '') bad('width · align 읽기가 틀림');
    if (canon(N.files('가 [[파일:a.png]] 나\n[[이미지:b|align=left]]').map(f => f.name)) !== canon(['a.png', 'b'])) bad('files()가 그림 고리를 다 찾지 못함');
    const img = name => HT.docImageOf(m, 'smoke-img', name);
    const doc = '== 바다 ==\n[[파일:바다.png]]\n첫 줄 글\n둘째 줄 글\n== 끝 ==\n앞 글 [[파일:g1|align=center|width=60%]] 뒤 글\n[[파일:없는 그림]]\n * 목록 [[파일:바다.png]] 안';
    const html = N.render(doc, { image: img }).html;
    const figs = html.match(/<figure class="wk-fig[^"]*"/g) || [];
    if (canon(figs) !== canon(['<figure class="wk-fig is-right"', '<figure class="wk-fig is-center"', '<figure class="wk-fig is-missing"'])) bad(`그림 셋(오른쪽 · 가운데 · 없음)이 그려지지 않음: ${JSON.stringify(figs)}`);
    if (!/<\/figure><p>첫 줄 글<br>둘째 줄 글<\/p>/.test(html)) bad('오른쪽 그림 뒤에 글이 한 문단으로 이어지지 않음');
    if (!/<\/h3><figure class="wk-fig is-center" style="--fig-w:60%;--fig-nat:800px"[^>]*>.*?<\/figure><p>앞 글  뒤 글<\/p>/.test(html)) bad('줄 가운데의 그림이 그 줄 앞으로 나와 놓이지 않음(글은 그림 고리만 빼고 한 문단)');
    if (!/alt="바다"/.test(html) || !/<figcaption>바다 그림<span class="wk-fig-credit"> · 검사<\/span><\/figcaption>/.test(html) || !/width="800" height="450"/.test(html)) bad('대체 글 · 설명 · 출처 · 크기가 그림에 붙지 않음');
    if (!/그림 없음 — 없는 그림/.test(html)) bad("사전에 없는 그림이 '그림 없음' 자리로 그려지지 않음");
    if (/<li>[^<]*<figure/.test(html) || !/<li>목록  안<\/li>/.test(html)) bad('목록 안의 그림 고리가 예전처럼 지워지지 않음');
    if (/wk-fig/.test(N.render(doc).html) || /wk-fig/.test(N.render(doc, { link: () => ({}) }).html)) bad('그림을 모르는 곳(opts.image 없음)에서 그림이 그려짐 — 예전처럼 지워야 함');
    /* 옛 문서는 1글자도 다르지 않음: 기본팩 · 견본의 문서 모두 — 그림 찾기를 주어도 그림 고리가 없으면 같은 HTML */
    let docs = 0;
    const big = HT.buildModel(packs, null);
    for (const [k, d] of big.docs) {
      if (!d.text || /\[\[(파일|이미지|file)\s*:/i.test(d.text)) continue;
      docs++;
      if (N.render(d.text).html !== N.render(d.text, { image: name => HT.docImageOf(big, d.packId, name) }).html) {
        bad(`그림 고리가 없는 문서 ${k}의 HTML이 달라짐`);
        break;
      }
    }
    if (docs < 10) bad(`견줄 옛 문서가 너무 적음: ${docs}`);
    /* 견본 sample-lantern: 그림 사전 여섯(2.0.1 — 왕관 · 오색 등불 · 청옥 인장 · 백유리 렌즈 · 백탑 문장 · 호반성 등좌, 하나도 빠지지 않고 읽힘) · 하위 문서(등불 왕국//아홉 불씨)가 이름으로 적은 가운데 그림 (오른쪽 · 없음 · id로 적은 그림은 위의 검사 문서가 봄) */
    const sample = packs.find(p => p.id === 'lantern-chronicle');
    if (!sample) bad('견본 sample-lantern이 읽히지 않음');
    else {
      if ((sample.images || []).length !== 6) bad(`견본의 그림 사전이 여섯이 아님: ${(sample.images || []).length}`);
      const ms = HT.buildModel([sample], null);
      const d = ms.docs.get('lantern-chronicle/p-lantern//아홉 불씨');
      const h = d && N.render(d.text, { image: name => HT.docImageOf(ms, d.packId, name) }).html;
      if (!h || (h.match(/<figure class="wk-fig/g) || []).length !== 1 || (h.match(/<figure class="wk-fig is-center"/g) || []).length !== 1 || !/data-wiki-img="img:lantern-chronicle\/img-crown"/.test(h)) bad('견본 하위 문서의 이름으로 적은 그림(가운데)이 그려지지 않음');
    }
    /* 반영하지 않은 고침 · 작업본 */
    const ch = HT.draft.changes(norm({ images: [{ id: 'g1', name: '바다.png', src: PNG }] }).pack, norm({}).pack);
    if (!ch.some(c => c.list === 'images' && c.type === 'add' && /문서 그림 추가 · 바다\.png/.test(c.label))) bad(`반영하지 않은 고침에 문서 그림이 잡히지 않음: ${JSON.stringify(ch)}`);
    const dr = HT.draft.clean(mk({ images: [{ id: 'g1', name: '바다.png', src: PNG }] }));
    if (!dr.images || dr.images.length !== 1) bad('작업본(HT.draft.clean)이 그림 사전을 버림');
    /* 화면 배선: 메이커에만 그림 넣기 부품 · 목록 셋 */
    const maker = readFileSync(join(root, 'dlc-maker.html'), 'utf8');
    const index = readFileSync(join(root, 'index.html'), 'utf8');
    if (!maker.includes('<script src="js/maker-images.js"></script>') || index.includes('maker-images.js')) bad('js/maker-images.js가 메이커에만 실리지 않음');
    if (!readFileSync(join(root, 'sw.js'), 'utf8').includes("'js/maker-images.js'") || !/MAKER_ONLY = \[[^\]]*'js\/maker-images\.js'/.test(readFileSync(join(root, 'scripts/build-web.mjs'), 'utf8'))) bad('js/maker-images.js가 서비스 워커 · 포장 목록에 없음');
    if (!N.toolbarHTML({ image: true }).includes('data-wiki-image') || N.toolbarHTML().includes('data-wiki-image')) bad("도구 줄의 '그림' 단추가 image 선택으로만 나오지 않음");
    const tb = N.toolbarHTML({ image: true });
    if (tb.indexOf('data-wiki-image') < tb.indexOf('data-wiki-insert="table"') || tb.indexOf('data-wiki-image') > tb.indexOf('data-wiki-insert="fold"')) bad("'그림' 단추가 '표' 바로 옆이 아님");
  } catch (e) {
    bad(`예외: ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
  }
}

/* [74] 형식 4 — 리메이크 1단계 1a(scripts/check-format4.mjs · docs/설계-리메이크-객체-그릇-서고.md 3절): 종류 · 소속 · 시대의 이음 규칙,
   기본팩 · 견본의 옛 → 4 → 옛 왕복과 모델(접힘 · 소속 · 대범위) 지킴, 형식 4 파일의 읽기 길(normalizePack · 전용 팩) */
try { out.format4 = await (await import('./check-format4.mjs')).checkFormat4(HT); }
catch (e) { out.problems.push(`형식 4 검사: ${e.stack || e}`); }

/* [75] 문화권(sphere) — 리메이크 조각 ②(DLC-형식.md 'tracks' · docs/설계-리메이크-객체-그릇-서고.md 3-7): 트랙의 sphere 읽기(틀린 id는 뺌 · 모르는 id는 둠) · 형식 버전 3 · 왕복 ·
   모델의 트랙 차례(문화권 → order · 문화권 없는 트랙은 맨 뒤) · 여러 DLC가 같은 트랙을 적을 때(먼저 놓인 쪽) · 프로그램에 든 문화권은 없음(2026-10-23) — 기본팩은 제 spheres의 동아시아, 등불 견본은 가상 일곱 */
{
  const bad = msg => out.problems.push(`문화권: ${msg}`);
  try {
    if (HT.SPHERES || HT.FANTASY_SPHERES || HT.SPHERE_DEFAULT || HT.isBuiltinSphere) bad('프로그램에 든 문화권 목록이 아직 있음');
    const mk = (tracks, id = 'smoke-sphere', spheres = [{ id: 'steppe', name: '초원', order: 2 }]) => ({ format: HT.FORMAT, id, name: '문화권 검사', spheres, tracks, periods: tracks.map((t, i) => ({ id: `p${i}`, track: t.id, name: `나라 ${i}`, start: 100, end: 300 })) });
    const r = HT.normalizePack(mk([{ id: 'sa', name: '갑 줄', order: 1, sphere: 'steppe' }, { id: 'sb', name: '을 줄', order: 2 }, { id: 'sc', name: '병 줄', order: 3, sphere: '없는-문화권' }, { id: 'sd', name: '정 줄', order: 0, sphere: 'islam' }]));
    if (r.errors.length) bad(`오류: ${r.errors.map(e => e.msg).join(' / ')}`);
    const t = id => r.pack.tracks.find(x => x.id === id);
    if (t('sa').sphere !== 'steppe' || 'sphere' in t('sb') || 'sphere' in t('sc') || t('sd').sphere !== 'islam') bad('트랙의 sphere 읽기(틀린 id는 뺌 · 모르는 id는 둠)가 틀림');
    if (!r.warnings.some(w => /문화권 "없는-문화권"/.test(w.msg)) || r.warnings.some(w => /"islam"/.test(w.msg))) bad('틀린 문화권 id에만 경고해야 함');
    const json = HT.packToJSON(r.pack);
    if (json.formatVersion !== 3) bad(`sphere를 쓴 파일이 3으로 나가지 않음(${json.formatVersion})`);
    const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if ((back.pack.tracks.find(x => x.id === 'sa') || {}).sphere !== 'steppe') bad('왕복에서 sphere가 빠짐');
    if (HT.packToJSON(HT.normalizePack(mk([{ id: 'sb', name: '을 줄' }], 'smoke-sphere-1', [])).pack).formatVersion !== 1) bad('sphere · spheres를 쓰지 않은 파일이 1로 나가지 않음');
    // 모델: 문화권 차례가 order보다 앞 · 문화권 없는 트랙(sb · sc · 만든 곳이 없는 islam의 sd)은 모든 문화권 뒤에 order 차례 · sd는 알림(sphereWarnings)
    const m = HT.buildModel([r.pack]);
    const order = m.tracks.map(x => x.id).join(',');
    if (order !== 'sa,sd,sb,sc') bad(`모델의 트랙 차례가 문화권 → order가 아님: ${order}`);
    if (m.tracks.find(x => x.id === 'sb').sphere !== '' || m.tracks.find(x => x.id === 'sd').sphere !== '' || m.tracks.find(x => x.id === 'sa').sphere !== 'steppe') bad('모델 트랙의 sphere(적지 않거나 못 찾으면 빈 글)가 틀림');
    if (!(m.sphereWarnings || []).some(w => w.packId === 'smoke-sphere' && w.list === 'tracks' && w.id === 'sd' && /islam/.test(w.msg)) || m.sphereWarnings.length !== 1) bad('만든 곳이 없는 문화권 알림(sphereWarnings)이 틀림');
    if (HT.sphereOf('islam') !== null || HT.sphereOrder('islam') !== Infinity || HT.sphereOf('') !== null || HT.sphereOrder('steppe') !== 2) bad('문화권 조회(없으면 null · 차례 Infinity)가 틀림');
    // 여러 DLC: 먼저 놓인 DLC가 비워 두었거나 못 찾은 트랙에 뒤 DLC의 값 · 뒤 DLC가 islam을 만들면 sd가 그 문화권에
    const r2 = HT.normalizePack(mk([{ id: 'sb', name: '을 줄', sphere: 'islam' }], 'smoke-sphere-2', [{ id: 'islam', name: '이슬람', order: 9 }]));
    const m2 = HT.buildModel([r.pack, r2.pack]);
    if (m2.tracks.find(x => x.id === 'sb').sphere !== 'islam' || m2.tracks.find(x => x.id === 'sd').sphere !== 'islam' || (m2.sphereWarnings || []).length) bad('먼저 놓인 DLC가 비운 트랙에 뒤 DLC의 문화권이 들지 않음');
    if (m2.tracks.map(x => x.id).join(',') !== 'sa,sd,sb,sc') bad(`두 DLC 모델의 트랙 차례: ${m2.tracks.map(x => x.id).join(',')}`);
    // 기본팩은 제 spheres의 동아시아(차례 1) · 등불 견본은 가상 일곱(101 ~ 107) — 프로그램에는 없음
    const builtinIds = new Set(HT.getBuiltinPacks().map(x => x.id));
    const base = HT.buildModel(packs.filter(p => builtinIds.has(p.id)));
    if (!base.tracks.length) bad('기본팩 트랙이 하나도 없음');
    if (base.tracks.some(x => x.sphere !== 'east-asia') || base.spheres.length !== 1 || base.spheres[0].order !== 1 || base.spheres[0].name !== '동아시아' || (base.sphereWarnings || []).length) bad('기본팩 트랙 · 문화권이 동아시아가 아님');
    const lantern = packs.find(p => p.id === 'lantern-chronicle');
    if (lantern) {
      const ml = HT.buildModel([lantern]);
      if (ml.spheres.length !== 7 || ml.spheres[0].id !== 'ember-basin' || ml.spheres[0].order !== 101 || ml.spheres[6].id !== 'white-spire' || ml.tracks.some(x => !x.sphere) || (ml.sphereWarnings || []).length) bad('등불 견본의 문화권 일곱이 제 spheres에 없음');
    } else bad('등불 견본(lantern-chronicle)이 없음');
  } catch (e) { bad(e.stack || String(e)); }
}

/* [76] DLC의 문화권 사전(spheres — 2026-10-23 · DLC-형식.md 'spheres'): 읽기(id · 이름 · 순서 · 설명 · 겹침 · 틀린 id) · 형식 버전 3 · 왕복 · 트랙이 제 DLC · 다른 DLC의 문화권을 가리킴 ·
   모델의 사전(DLC만 · 차례 — 비우면 1000부터) · 만든 곳이 없는 id는 문화권 없이 · 작업본 목록 · 메이커 바탕 표(트랙 다음 · 기본 가져오기 없음) · 트랙 고르기 칸의 선택지 */
{
  const bad = msg => out.problems.push(`문화권 사전: ${msg}`);
  try {
    const mk = (spheres, tracks, id) => ({ format: HT.FORMAT, id, name: '문화권 사전 검사', spheres, tracks, periods: tracks.map((t, i) => ({ id: `p${i}`, track: t.id, name: `나라 ${i}`, start: 100, end: 300 })) });
    const r = HT.normalizePack(
      mk(
        [{ id: 'mist-sea', name: '안개 바다권', description: '가상 세계' }, { id: 'ash-plain', name: '재 들판권', order: 150 }, { id: 'east-asia', name: '동쪽 바다' }, { id: 'mist-sea', name: '겹침' }, { id: '틀린 id', name: '틀림' }, { id: 'no-name' }],
        [{ id: 'ta', name: '갑', order: 1, sphere: 'mist-sea' }, { id: 'tb', name: '을', order: 1, sphere: 'ash-plain' }, { id: 'tc', name: '병', order: 1 }, { id: 'td', name: '정', order: 1, sphere: 'other-dlc' }],
        'smoke-spheres'
      )
    );
    if (!r.pack) throw Error('정규화 실패 ' + r.errors.map(e => e.msg).join(' / '));
    const sp = r.pack.spheres || [];
    if (sp.map(x => x.id).join(',') !== 'mist-sea,ash-plain,east-asia,no-name') bad(`문화권 사전 읽기가 틀림: ${sp.map(x => x.id).join(',')}`);
    if (sp[1].order !== 150 || sp[0].description !== '가상 세계' || sp[3].name !== 'no-name') bad('문화권의 순서 · 설명 · 빈 이름(id로) 읽기가 틀림');
    if (!r.warnings.some(w => /"mist-sea"가 중복/.test(w.msg)) || !r.warnings.some(w => /문화권 #5.*id가 비었거나/.test(w.msg))) bad('겹친 id · 틀린 id 경고가 없음');
    if (r.warnings.some(w => /트랙 "t[ad]"의 문화권/.test(w.msg))) bad('올바른 문화권 id에는 읽을 때 경고하지 않아야 함(만든 곳은 모델이 봄)');
    const t = id => r.pack.tracks.find(x => x.id === id);
    if (t('ta').sphere !== 'mist-sea' || t('td').sphere !== 'other-dlc') bad('트랙의 sphere(제 DLC의 것 · 다른 DLC의 것)를 남기지 않음');
    const json = HT.packToJSON(r.pack);
    if (json.formatVersion !== 3) bad(`spheres를 쓴 파일이 3으로 나가지 않음(${json.formatVersion})`);
    const back = HT.normalizePack(JSON.parse(JSON.stringify(json)));
    if (canon(HT.packToJSON(back.pack)) !== canon(json)) bad('왕복에서 문화권 사전이 달라짐');
    if (HT.packToJSON(HT.normalizePack(mk([], [{ id: 'tc', name: '병' }], 'smoke-spheres-0')).pack).spheres) bad('문화권이 없는 파일에 spheres 열쇠가 생김');
    // 모델: DLC의 넷뿐(ash-plain 150 · mist-sea 1000 · east-asia 1001 · no-name 1002) · 트랙 차례 tb(150) → ta(1000) → tc(없음) → td(만든 곳 없음 → 없음 · 알림)
    const m = HT.buildModel([r.pack]);
    if (m.spheres.length !== 4 || m.spheres.map(x => `${x.id}@${x.order}`).join() !== 'ash-plain@150,mist-sea@1000,east-asia@1001,no-name@1002') bad(`모델의 문화권 사전이 틀림: ${m.spheres.map(x => `${x.id}@${x.order}`).join()}`);
    if (m.spheres[0].packId !== 'smoke-spheres') bad('문화권의 packId가 없음');
    if (m.tracks.map(x => x.id).join(',') !== 'tb,ta,tc,td') bad(`모델의 트랙 차례가 문화권 차례가 아님: ${m.tracks.map(x => x.id).join(',')}`);
    if (m.tracks.find(x => x.id === 'td').sphere !== '' || HT.sphereOf('other-dlc') !== null || !HT.isSphere('mist-sea') || (m.sphereWarnings || []).length !== 1 || m.sphereWarnings[0].id !== 'td') bad('만든 곳이 없는 문화권이 빈 글 · 알림으로 풀리지 않거나 사전 조회가 틀림');
    // 다른 DLC가 만든 문화권: 뒤 DLC가 other-dlc를 만들면 td가 그 문화권에(차례 1003) · 같은 id는 먼저 놓인 DLC가 이김
    const r2 = HT.normalizePack(mk([{ id: 'other-dlc', name: '남의 문화권' }, { id: 'mist-sea', name: '뒤 DLC의 안개' }], [], 'smoke-spheres-2'));
    if (r2.warnings.some(w => /하나도 없습니다/.test(w.msg))) bad('문화권 사전만 담은 DLC를 빈 DLC로 봄');
    const m2 = HT.buildModel([r.pack, r2.pack]);
    if (m2.tracks.find(x => x.id === 'td').sphere !== 'other-dlc' || m2.spheres.find(x => x.id === 'other-dlc').order !== 1003 || m2.spheres.find(x => x.id === 'mist-sea').name !== '안개 바다권' || (m2.sphereWarnings || []).length) bad('다른 DLC의 문화권 정의 · 먼저 놓인 DLC 우선이 틀림');
    HT.buildModel(packs); // HT.sphereOf가 보는 사전을 원래(기본팩 + 견본)로
    // 작업본 · 메이커
    const d = HT.draft.clean(json);
    if (!Array.isArray(d.spheres) || d.spheres.length !== 4) bad('작업본 목록에 문화권 사전이 없음');
    if (!HT.draft.blank().spheres) bad('빈 작업본에 spheres 자리가 없음');
    const kit = HT.makerKit;
    if (kit) {
      const T = kit.BASE_TABLES.spheres;
      if (!T || T.word !== '문화권' || Object.keys(kit.BASE_TABLES)[1] !== 'spheres') bad('바탕 자료 표에 문화권 칸이 트랙 다음에 없음');
      if (T.builtin) bad('프로그램에 든 문화권 가져오기(builtin)가 아직 있음');
      if (kit.findUsers(d, T, d.spheres[0]).length !== 1) bad('문화권을 쓰는 트랙 세기가 틀림');
      if (kit.renameRefs(d, T, 'id', 'mist-sea', 'mist-sea-2') !== 1 || d.tracks.find(x => x.id === 'ta').sphere !== 'mist-sea-2') bad('문화권 id를 바꿔도 트랙이 따라가지 않음');
      d.spheres[0].id = 'mist-sea-2';
      const col = kit.BASE_TABLES.tracks.cols.find(c => c.key === 'sphere');
      const opts = typeof col.options === 'function' ? col.options(d, m2) : [];
      if (opts[0]?.id !== '' || !opts.some(o => o.id === 'other-dlc' && /smoke-spheres-2/.test(o.hint)) || !opts.some(o => o.id === 'mist-sea-2' && o.hint === '이 DLC의 문화권') || opts.length !== 1 + m2.spheres.length + 1) bad('트랙 고르기 칸의 문화권 선택지(없음 + 켠 DLC + 작업본)가 틀림');
    }
  } catch (e) {
    bad(e.stack || String(e));
  }
}

/* [77] 내장 팩 등록 함수(리메이크 6단계 걸음 1 — js/core.js HT.packRegistry · docs/기본팩-손질-목록-초안.md 3-1): 내장 등록(HT.definePack …)은 등록부 하나를 쓰고
   따로 만든 등록부는 내장 목록을 건드리지 않음 · 형식 4 선언은 objects로 내고 정규화 오류 0 · 승계 방식(how)이 정규화를 지남 ·
   기본팩의 등록 꼴은 선언대로 — 형식 3 선언이면 periods(objects 없음), 형식 4 선언이면 objects(띠는 객체 · periods · epochs 없음)이고 내림(HT.F4.down)
   알림은 옮겨 앉기 · 기간 있는 within('접지 않고 소속(제 줄)으로')뿐(새 기본팩이 어느 형식으로 들어와도 이 기대는 그대로). 자세한 단위는 check-format4 ④ · ⑰ */
{
  const bad = msg => out.problems.push(`등록 함수: ${msg}`);
  try {
    if (typeof HT.packRegistry !== 'function') throw Error('HT.packRegistry가 없음');
    const n0 = HT.getBuiltinPacks().length;
    const R = HT.packRegistry(new Map(), { warn: () => {} });
    R.definePack({ id: 'smoke-reg', name: '등록 검사', formatVersion: 4, tracks: [{ id: 'ta', name: '가 줄' }] });
    R.extendPack('smoke-reg', { track: 'ta', eras: [[1, 50, '앞 시대', '']], periods: [[1, 100, '가 나라', '', { within: [{ of: `ta-e${HT.hash(1 + '앞 시대')}`, end: 50 }] }], [100, 200, '나 나라', '']] });
    R.describePeriods('smoke-reg', 'ta', { '나 나라': { succeeds: [{ from: '가 나라', type: 'direct', how: '정복' }] } });
    if (HT.getBuiltinPacks().length !== n0) bad('따로 만든 등록부가 내장 목록을 바꿈');
    const r = HT.normalizePack(JSON.parse(JSON.stringify(R.get('smoke-reg'))));
    if (!r.pack || r.errors.length) bad(`형식 4 선언 팩의 정규화 오류: ${r.errors.map(e => e.msg).join(' / ')}`);
    else {
      const j = HT.packToJSON(r.pack);
      if ((j.periods.find(p => p.name === '나 나라').succeeds[0] || {}).how !== 'conquest') bad('승계 방식(how)이 정규화에서 빠짐');
      if (!(j.scopes || []).some(s => s.name === '앞 시대')) bad('기간 있는 within으로 가리킨 시대 객체가 그릇이 되지 않음');
    }
    for (const raw of HT.getBuiltinPacks()) {
      if (Number(raw.formatVersion) === HT.F4.VERSION) {
        if (!Array.isArray(raw.objects) || 'periods' in raw || 'epochs' in raw) bad(`기본팩 ${raw.id}: 형식 4 선언인데 등록 꼴이 objects가 아님`);
        const notes = [];
        HT.F4.down(JSON.parse(JSON.stringify(raw)), m => { if (!/지금 화면에서는 접지 않고 소속\(제 줄\)으로 그립니다/.test(m)) notes.push(m); });
        if (notes.length) bad(`기본팩 ${raw.id}을(를) 내릴 때 옮겨 앉기 밖의 알림 ${notes.length}건: ${notes.slice(0, 3).join(' / ')}`);
      } else if (raw.formatVersion !== 3 || !Array.isArray(raw.periods) || 'objects' in raw) bad(`기본팩 ${raw.id}: 형식 3 선언인데 등록 꼴이 periods가 아님(또는 형식 번호가 3 · 4 밖)`);
    }
  } catch (e) {
    bad(e.stack || String(e));
  }
}

/* [78] 달력 다섯(리메이크 6단계 걸음 4 · D10 — js/calendar.js): 히브리력(티슈리 = 1월 · 윤년 13달) · 에티오피아력 · 콥트력(13째 달 5 · 6일) · 사카력 · 불기(타이 — 해만 서력 + 543, 산수)의
   날짜 글이 아는 양력 날로 읽힘 · 없는 날(평년의 13월 · 6일짜리 13째 달의 6일 · 12달 달력의 13월) · 1년 앞 · 보조 달력 이름(formatIn) · 달 경계(monthsIn이 5일짜리 13째 달을 건너뛰지 않음) ·
   달 정밀도의 구간(precSpan — 짧은 달은 그 달만) · 날짜 칸의 13월 고르기(13달 달력에서만). 엔진 쪽은 읽기 벡터(read-vectors)가 같은 표본을 지킨다 */
{
  const bad = msg => out.problems.push(`달력 다섯: ${msg}`);
  try {
    const cal = HT.cal;
    const civ = s => { const r = cal.parse(s); return r && r.ok ? cal.formatT(r.t, 'd') : `(못 읽음: ${r ? r.error : '빈 값'})`; };
    for (const [text, want] of [
      ['히브리력 5784-01-01', '2023년 9월 16일'], ['히브리력 5784-07-14', '2024년 3월 24일'], ['유대력 5784-08-15', '2024년 4월 23일'], ['히브리력 5784-13-29', '2024년 10월 2일'],
      ['에티오피아력 2016-01-01', '2023년 9월 12일'], ['에티오피아력 2015-13-06', '2023년 9월 11일'], ['콥트력 1740-01-01', '2023년 9월 12일'], ['콥트력 1-01-01', '284년 8월 29일'],
      ['사카력 1945-01-01', '2023년 3월 22일'], ['인도 국정력 1946-01-01', '2024년 3월 21일'], ['불기 2567-02-29', '2024년 2월 29일'], ['1592-05-23 (불기)', '1049년 5월 23일'],
    ]) if (civ(text) !== want) bad(`${text} → ${civ(text)} (기대 ${want})`);
    for (const [text, err] of [['히브리력 5783-13-01', '히브리력에 그런 날짜가 없습니다.'], ['에티오피아력 2016-13-06', '에티오피아력에 그런 날짜가 없습니다.'], ['히브리력 5784-14-01', '달은 1~13 사이여야 합니다.'],
      ['사카력 1945-13-01', '달은 1~12 사이여야 합니다.'], ['1592-13-01', '달은 1~12 사이여야 합니다.'], ['불기 2566-02-29', '2566년 2월은 28일까지입니다.'], ['콥트력 기원전 3-01-01', '콥트력은(는) 1년부터 적을 수 있습니다.'],
      ['불기 기원전 3', '불기은(는) 1년부터 적을 수 있습니다.']]) {
      const r = cal.parse(text);
      if (!r || r.ok || r.error !== err) bad(`${text}: 오류 글 ${r ? r.error : '빈 값'} (기대 ${err})`);
    }
    const t = cal.parse('2024-09-08').t;
    const names = ['hebrew', 'ethiopic', 'coptic', 'indian', 'buddhist'].map(id => cal.formatIn(id, t)).join(' / ');
    if (names !== '히브리력 5784년 13월 5일 / 에티오피아력 2016년 13월 3일 / 콥트력 1740년 13월 3일 / 사카력 1946년 6월 17일 / 불기 2567년 9월 8일') bad(`보조 달력 이름: ${names}`);
    if (!['hebrew', 'ethiopic', 'coptic', 'indian', 'buddhist'].every(id => cal.supports(id))) bad('이 Node의 ICU가 달력 다섯을 모름');
    const marks = cal.monthsIn('ethiopic', cal.jdnCivil(2024, 8, 1), cal.jdnCivil(2024, 10, 31)).map(x => `${x.y}-${x.label}`).join(' ');
    if (!marks.includes('2016-13월 2017-1월 2017-2월')) bad(`에티오피아력 달 경계에서 13째 달 뒤가 빠짐: ${marks}`);
    const span = cal.precSpan(cal.parse('에티오피아력 2016-13'));
    if (!span || Math.round((span[1] - span[0]) * 366) !== 5) bad(`5일짜리 13째 달의 구간이 ${span ? ((span[1] - span[0]) * 366).toFixed(2) : '없음'}일`);
    if (typeof HT.yearFieldHTML === 'function') {
      const html = HT.yearFieldHTML('smokeY');
      if (!/<option value="13" hidden disabled>13월<\/option>/.test(html)) bad('날짜 칸의 달 고르기에 숨긴 13월이 없음(13달 달력의 날짜를 연 폼이 달을 잃음)');
      if (!/<option value="hebrew"/.test(html) || !/<option value="buddhist"/.test(html)) bad('날짜 칸의 달력 고르기에 새 달력이 없음');
    }
  } catch (e) {
    bad(e.stack || String(e));
  }
}

/* [79] 옮겨 앉기 토막과 섬김 · 실권의 상대(리메이크 6단계 — js/core.js splitMoves · 엔진 거울 lay/f4.rs split_moves): 새 앱 내보내기(HT.F4.split)에서
   토막 난 객체를 섬김(partOf[].of — 글 줄도) · 실권(power[].over)으로 가리킨 줄은 그 줄의 시작 해(비우면 가리킨 쪽 객체의 시작 해)가 든 토막으로 —
   0 ~ 100인 가 나라(x)가 50년에 그릇을 떠나 x · x.mv50(그릇 밖 토막)으로 나뉘면 60년에 시작한 섬김 · 실권은 x.mv50으로. 웹 · 메이커(나누지 않음)는 원 객체 그대로.
   토막 난 객체가 쥔 남의 실권(power[].over — 검토 고침)은 그 줄의 시작 해(비우면 객체의 시작 해)가 든 토막 하나에만 · 이름만인 줄(제 안의 실권자)은 토막마다 */
{
  const bad = msg => out.problems.push(`옮겨 앉기 상대: ${msg}`);
  const was = HT.F4.split;
  try {
    const J = { format: HT.FORMAT, formatVersion: 4, id: 'smoke-mv', name: '토막 상대', tracks: [{ id: 'ta', name: '가 줄' }], events: [], objects: [
      { id: 'e1', type: 'era', track: 'ta', name: '앞 시대', start: 0, end: 50 },
      { id: 'x', track: 'ta', name: '가 나라', start: 0, end: 100, within: [{ of: 'e1', end: 50 }], power: [{ over: 'z', start: 10, end: 90 }, { over: 'z', start: 60, end: 70 }, { over: 'z' }, { name: '권신', start: 10, end: 90 }] },
      { id: 'z', track: 'ta', name: '다 나라', start: 0, end: 100 },
      { id: 'r', type: 'regime', track: 'ta', name: '실권', start: 60, end: 80, partOf: [{ of: '가 나라', relation: 'nominal' }] },
      { id: 's', track: 'ta', name: '이웃', start: 10, end: 90, partOf: [{ of: 'x', relation: 'vassal', start: 70 }, { of: 'x', relation: 'vassal', end: 20 }], power: [{ over: '가 나라', start: 55, end: 60 }] },
      { id: 't', track: 'ta', name: '뒤 나라', start: 65, end: 95, partOf: '가 나라' },
    ] };
    const hosts = (split, id) => {
      HT.F4.split = split;
      const p = HT.F4.down(JSON.parse(JSON.stringify(J))).periods.find(q => q.id === id);
      return JSON.stringify([p.partOf, (p.power || []).map(w => w.over)]);
    };
    const on = ['r', 's', 't'].map(id => hosts(true, id)).join(' | ');
    if (on !== '[[{"polity":"x.mv50","relation":"nominal"}],[]] | [[{"polity":"x.mv50","relation":"vassal","start":70},{"polity":"x","relation":"vassal","end":20}],["x.mv50"]] | [[{"polity":"x.mv50","nest":false}],[]]') bad(`토막 난 상대를 가리킨 섬김 · 실권: ${on}`);
    const off = ['r', 't'].map(id => hosts(false, id)).join(' | ');
    if (off !== '[[{"polity":"가 나라","relation":"nominal"}],[]] | [[{"polity":"가 나라","nest":false}],[]]') bad(`나누지 않을 때(웹 · 메이커)의 섬김이 바뀜: ${off}`);
    const held = split => {
      HT.F4.split = split;
      return JSON.stringify(HT.F4.down(JSON.parse(JSON.stringify(J))).periods.filter(q => q.name === '가 나라').map(p => [p.id, (p.power || []).map(w => (w.over ? `${w.over}@${w.start ?? ''}` : w.name))]));
    };
    if (held(true) !== '[["x",["z@10","z@","권신"]],["x.mv50",["z@60","권신"]]]') bad(`토막 난 객체가 쥔 실권 줄이 토막마다 복제되거나 시작 해의 토막에 가지 않음: ${held(true)}`);
    if (held(false) !== '[["x",["z@10","z@60","z@","권신"]]]') bad(`나누지 않을 때(웹 · 메이커)의 실권 줄이 바뀜: ${held(false)}`);
  } catch (e) {
    bad(e.stack || String(e));
  } finally {
    HT.F4.split = was;
  }
}

if (process.argv.includes('--json')) console.log(JSON.stringify(out, null, 2));
else {
  for (const p of out.packs) console.log(`${p.file || '(기본팩)'}  ${p.id}  오류 ${p.errors} · 경고 ${p.warnings}${p.file ? ` · 왕복 ${p.roundtrip ? '같음' : '다름!'} · ${p.hash}` : ''}`);
  if (out.model) console.log(`모델: 트랙 ${out.model.tracks} · 시대 ${out.model.periods} · 사건 ${out.model.events} · 시대 구분 ${out.model.epochs} · 민족 ${out.model.peoples} ${JSON.stringify(out.model.extra)} · ${out.model.hash}`);
  if (out.model && out.model.hashV1) console.log(`모델(형식 1인 팩만 — 새 견본을 뺀 기준값): ${out.model.hashV1}`);
  console.log(out.problems.length ? `문제 ${out.problems.length}건:\n - ${out.problems.join('\n - ')}` : '문제 없음');
}
process.exit(out.problems.length ? 1 : 0);

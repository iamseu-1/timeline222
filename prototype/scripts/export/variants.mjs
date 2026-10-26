// 변형(variant) — 켤 수 있는 것 하나마다 '기본 상태와의 차이'를 자료로 싣는다.
//   host:<상위 띠 uid>   소속 펼치기(명세 04의 5-2절 · 지금 연표의 toggleMembers · expandedHosts)
//   scope:<대범위 uid>   대범위 모아 보기(명세 04의 6-1절 · 지금 연표의 toggleScope · _scopeClaims · _scopeNodes)
//   shelf:<그릇 uid>     선반(리메이크 4단계 · 감독 결정 2026-10-25 '선반 = 엔진 변형 길' — 지금 연표 서고의 그릇 상태 'shelf' · _shelfSplit):
//                        그 그릇 하나만 켜고 shelvedScopes = {uid}로 다시 배치 — 구성원 가운데 상위 shelfKeep(5)만 제 줄에 남고 나머지 띠는 숨는다.
//                        그 그릇이 차지한 구성원이 shelfKeep을 넘는 그릇에만 생기고, 이 모듈의 변형 뒤에 셈한다(이 모듈 목록의 맨 뒤 — 이 모듈의 앞 변형 번호는 그대로.
//                        렌즈 변형(kind 4 — 뒤의 lens 모듈이 out.variants에 붙임)은 그 뒤라 렌즈가 있는 자료에서는 선반 수만큼 번호가 밀린다).
//
// 내보내기는 변형마다 **그것 하나만 켠** 상태로 지금 연표의 배치기(_layoutTrack)를 다시 돌리고, 줄 · 띠 · 사건 · 그릴 것을
// 기본 상태와 견준다. 줄은 '내용'(그 줄에 놓인 띠의 uid를 이은 글)으로 맞춘다 — 켜고 끄면 줄 번호가 통째로 밀리지만
// 같은 띠를 실은 줄은 같은 줄이기 때문이다. 그래서 대부분의 차이는 '띠가 옮겨 간 것'이 아니라 **줄이 옮겨 쌓인 것**이고,
// 자료도 그렇게 싣는다(계약 3절 끝 · 2절 끝).
//
//  ① 새 줄      기본에 없던 줄(펼친 소속 줄 kind 1 · 대범위 가지가 새로 지은 줄) — 그 트랙의 줄 목록 뒤에 이어 붙인다.
//  ② 쌓는 차례  줄마다 `after`(어느 줄 바로 아래인가) · `ord`. 기본의 차례(r − 1)와 다른 줄만 싣는다.
//  ③ 이사       줄이 옮겨 쌓이는 것으로 설명되지 않는 것 — 띠 · 사건이 다른 줄로 간 것({kind, ref, row}).
//  ④ 새로 그릴 것  그 변형에서만 생기는 띠 · 칸 · 사건 · 일반 항목 · 줄 이름(variant 열쇠를 달아 함께 싣는다).
//  ⑤ 묶음       왼쪽 칸의 대범위 칸(새 묶음)과 그 줄 목록.
//  ⑥ 선반만     숨는 띠는 이사의 도착 줄 −1(③ — 지금 연표의 _hidden), 그 띠의 사건도 이사 −1(배치기가 줄 null로 둔 것 — 공통 줄을 새로 만들지 않음),
//               바탕 문화의 조각은 승계국을 따라 새 줄 또는 −1로 이사, 변형에 없는 기본 줄은 빠지는 줄(after −2 · ord −1 · new 0 — 엔진 계약 2-4절),
//               변형 다시 셈에 짝이 없는 기본 항목(느슨한 이름을 수로 셈)은 가림(kind 4). 다른 갈래의 출력은 바이트 그대로다.
//
// 자체 점검: 변형을 켠 채 돌린 tracks.mjs가 계약 3절의 식으로 줄을 다시 쌓아 지금 연표의 _layoutTrack과 1px도
// 다르지 않은지 확인하고(그 모듈의 assert), 여기에서 한 번 더 '기본 줄 + 변형의 차이'를 쌓아 같은 자리가 나오는지 본다.
import { assert, importModule, color } from './base.mjs'; // 노드 내장을 직접 부르지 않는다(브라우저 겸용 — base.mjs 머리말)

/** 변형 상태에서 다시 돌릴 모듈 — 줄 · 띠 · 그릴 것을 만드는 것만(날짜 칸과 항목 기록은 보기 상태와 무관하다).
    `minibars`가 든 까닭: 가는 막대의 '접힌 민족 줄용 단'(구역 45의 `b`)은 **묶음마다** 셈하는데(계약 6-11절),
    대범위를 켜면 흩어져 있던 정권이 한 가지로 모여 묶음이 달라진다 — 그 가지를 접었을 때 막대가 겹치지 않게 변형 판을 함께 싣는다. */
const REPLAY = ['tracks', 'bands', 'strips', 'events', 'hangs', 'figures', 'rails', 'links', 'scopes', 'minibars', 'labels', 'power'];
// 'power'(단체 단 · 명목 지도자 · 연합의 겹 탭 — D5 결정 1 ~ 3): 소속을 펼쳐야 그려지는 띠의 단체 칸 · 겹 탭도 변형 판으로 싣는다(단체 자료가 없으면 빈손).

/** 계약 3절의 상수(tracks.mjs의 G와 같은 값). boards.mjs(집합 보기)도 같은 값 · 같은 식으로 자체 점검한다. */
// 통합 2026-10-13: 글줄(크기 × 1.2)과 테두리 사이 최소 3px, 단 사이 최소 3px.
export const G = {
  pad: 9, inset: 4, slotGap: 3, line: 21, railPitch: 7,
  dynasty: 20, leader: 22, cabinet: 21, organ: 20, dep: 20,
  zoneTab: 20, zoneGap: 3, gap: 8, memberGap: 6, groupGap: 14,
  folded: 34, foldedGroup: 30, hem: 21, tab: 18,
  figure: 20, figGap: 3, phase: 20, phaseGap: 3, rank: 20, rankGap: 3,
  power: 20, powerGap: 3,
  hang: 13, // 매달린 속국 이름표 한 줄(tracks.mjs의 G.hang · timeline.js의 HANG.pitch)
};

/** 변형 번호: 1 소속 펼치기 · 2 대범위 모아 보기 · 5 단체 펼치기(리메이크 조각 ④ — 든 나라 밑에 그 나라 단체의 띠를 펼침 · 3 집합 보기 · 4 렌즈는 다른 모듈) ·
    6 선반(리메이크 4단계 — 그 그릇의 scope 변형을 대신함 · 엔진 variant.rs의 SHELF_KIND). */
export const VARIANT_KIND = { host: 1, scope: 2, groups: 5, shelf: 6 };

/** 줄 하나의 높이 — 계약 3절의 '띠 안'을 그대로 쌓는다(tracks.mjs의 stackBand와 같은 식 — 지금 연표와 대조하는 자체 점검용).
    2026-10-15부터 화면 쪽 layout.dart의 _bandOf는 꼬리표 갈래 E의 식(계약 3절 머리의 상자)으로 쌓아 이 식과 다르다 — 내보내는 재료는 같다.
    [on]은 그때 보이는 줄들로 다시 셈한 트랙 값 `{ railLevels, organ }`이다(계약 3절 끝). */
export function rowHeight(track, spec, on) {
  if (spec.kind === 3) return G.foldedGroup;
  let y = G.inset;
  if (track.dynasty) y += G.dynasty + G.slotGap;
  y += (spec.phase || 0) * (G.phase + G.phaseGap);
  if (spec.rank) y += G.rank + G.rankGap;
  // 단체 단(집권 · 실권 — tracks.mjs의 packRowValues 비트 7 · 8): 그 줄에 있으면 20 + 3씩
  if ((spec.figWide >> 7) & 1) y += G.power + G.powerGap;
  if ((spec.figWide >> 8) & 1) y += G.power + G.powerGap;
  if (track.leader) y += G.leader + G.slotGap;
  if (track.cabinet) y += G.cabinet + G.slotGap;
  y += (spec.lines || 0) * G.line;
  y += (on.railLevels || 2) * G.railPitch;
  const figTop = y + G.slotGap;
  const figH = spec.fig ? spec.fig * G.figure + (spec.fig - 1) * G.figGap : 0;
  const depTop = figH ? figTop + figH + G.slotGap : y + G.slotGap;
  // dep는 저장된 옛 높이(n*13-1)다. 옛 저장소와 같은 열을 유지하고 화면 높이만 환산한다.
  const dep = spec.dep ? Math.round((spec.dep + 1) / 13) * (G.dep + G.slotGap) - G.slotGap : 0;
  const organTop = depTop + (dep ? dep + G.slotGap : 0);
  const rowH = (on.organ ? organTop + G.organ : dep ? depTop + dep : figH ? figTop + figH : y) + G.inset;
  // 덧붙는 높이: 매달린 속국 이름표 줄(figWide 비트 9~13 — tracks.mjs의 packRowValues) × 13 + 나머지 구역 탭 줄 × 23 + 3
  const hl = ((spec.figWide || 0) >> 9) & 31;
  const zl = Math.max(0, (spec.zones || 0) - hl);
  const cut = (hl + zl ? hl * G.hang + zl * (G.zoneTab + G.zoneGap) + 3 : 0) + (spec.hem ? G.hem : 0);
  return rowH + cut;
}

/** 줄 단위 트랙 값(계약 3절 끝)을 보이는 줄들의 최댓값으로 — 화면 쪽 `layout.dart`의 `_syncTrackValues`와 같은 길. */
export function trackValuesOf(track, rows, live) {
  let railLevels = 2, organ = false, known = false;
  for (const r of live) {
    const packed = rows[r] && rows[r].figWide;
    const rail = ((packed >> 3) & 7) - 1;
    if (!(rail >= 0) || rows[r].kind === 3) continue;
    known = true;
    if (rail > railLevels) railLevels = rail;
    if ((packed & 64) !== 0) organ = true;
  }
  return known ? { railLevels, organ } : { railLevels: track.railLevels || 2, organ: !!track.organ };
}

/** 줄의 '내용' 열쇠 — 그 줄에 놓인 띠의 uid를 이은 글(빈 줄은 공통 줄뿐이다). */
const rowKeyOf = (tr, r) => (tr.rowPeriods[r] || []).map(p => p.uid).join('+') || (r === tr.commonRow ? '#공통' : `#빈${r}`);

/** 사건 하나의 이름 — rails.mjs의 eventUid와 같은 식(공동 사건의 다른 자리는 #n이 붙는다). */
const eventKeyOf = e => e.uid + (e._pi ? `#${e._pi}` : '');

/** 일반 항목 하나의 '느슨한 이름' — 무엇을 그리는 것인가만 본다(줄과 a~d는 뺀다).
 *  줄이 옮겨 쌓이면 승계선의 아래 방향 비트와 세로 통로 번호처럼 **같은 것의 값이 달라지는** 항목이 있어,
 *  그것을 새 항목으로 실으면 기본 판과 겹쳐 두 번 그려진다 — 느슨한 이름이 같으면 '변형 판'으로 보고 기본 판을 가린다. */
const itemKeyOf = it => [it.section, it.ref, it.name, it.start, it.end, it.text2].join('');
/** 값까지 모두 같은가(변형 판인지 그대로인지 가른다). */
const itemSameOf = it => [it.a, it.b, it.c, it.d].join('');

/** 칸 하나의 이름. */
const cellKeyOf = c => [c.period, c.kind, c.start, c.end, c.name].join('');
const cellSameOf = c => [c.lane, c.style, c.color].join('');

/** 빈 내보내기 그릇(export-layout.mjs의 out과 같은 모양). */
const emptyOut = name => ({ name, categories: [], tracks: [], epochs: [], axis: [], periods: [], cells: [], events: [], items: [], entities: [], rowLabels: [] });

/** 지금 연표의 배치 상태를 그대로 찍어 둔다(줄의 자리 · 묶음 · 띠와 사건의 줄). */
function snapshot(tl) {
  return tl.tracks.map(tr => ({
    id: tr.id,
    rows: tr.rows,
    height: tr.height,
    keys: Array.from({ length: tr.rows }, (_, r) => rowKeyOf(tr, r)),
    rowTop: tr.rowTop.slice(),
    rowGap: tr.rowGap.slice(),
    rowHs: tr.rowHs.slice(),
    scopePad: Array.from({ length: tr.rows }, (_, r) => Math.round(tl._scopePad(tr, r, r - 1))),
    groupStart: Array.from({ length: tr.rows }, (_, r) => (tr.groups.some(g => g.first === r) ? 1 : 0)),
    groups: tr.groups.map(g => ({ key: g.key, name: g.name || '', color: g.color, depth: g.depth, first: g.first, count: g.count, scope: g.scope || null, culture: !!g.culture })),
    bandRow: new Map(tr.periods.filter(p => !p._overlay && !p._under).map(p => [p.uid, p._hidden ? -1 : p._row])),
    // 사건의 줄 null = 선반 변형이 숨긴 띠의 사건(지금 연표 _layoutTrack 3) → −1(숨음)
    eventRow: new Map(tr.events.map(e => [eventKeyOf(e), e._row === null ? -1 : e._row == null || e._row < 0 ? tr.commonRow : e._row])),
    // 바탕 문화의 조각(bands.mjs와 같은 셈 — 첫 줄은 띠 uid · 둘째 줄부터 uid#u<줄>) → 줄. 선반 변형의 이사에만 쓴다(아래 '이사')
    underRow: new Map(tr.periods.filter(p => p._under && !p._overlay && !p._hidden).flatMap(p => (p._underRows || []).map((r, k) => [k === 0 ? p.uid : `${p.uid}#u${r}`, r]))),
  }));
}

/** 변형 하나를 켠 상태로 지금 연표의 배치기를 다시 돌린다. */
function relayout(tl, variant) {
  tl.expandedHosts = new Set(variant && variant.kind === 'host' ? [variant.uid] : []);
  tl.expandedGroups = new Set(variant && variant.kind === 'groups' ? [variant.uid] : []);
  // 그 그릇 하나만 켬 — 나머지는 자료의 default와 상관없이 풂(기본 배치와 같게 — base.mjs의 리메이크 2부 주석). 선반도 그 그릇을 켠 배치다.
  tl.scopesOn = Object.fromEntries((tl.scopes || []).map(s => [s.uid, !!(variant && (variant.kind === 'scope' || variant.kind === 'shelf') && variant.uid === s.uid)]));
  // 선반: 그 그릇만 선반 상태(_layoutTrack이 상위 shelfKeep 밖 구성원을 숨김) — 그 밖(끝의 기본 되돌림 포함)은 빈 집합
  tl.shelvedScopes = new Set(variant && variant.kind === 'shelf' ? [variant.uid] : []);
  for (const tr of tl.tracks) tl._layoutTrack(tr);
}

/** REPLAY 모듈을 새 그릇에 다시 돌린다(모듈끼리 나눠 쓰는 값도 새로 — 기본 상태의 것을 덮지 않는다).
    띠 번호(링크의 b · 매달린 이름표의 d — 순번 + 1)는 **결과의 번호**로 맞춘다: 가져오기가 띠를 넣는 차례는 결과(out.periods)의 차례이고,
    변형에서만 생기는 띠는 그 뒤에 이어 붙는다(contribute의 '그 변형에서만 생기는 것'). 다시 돌린 배치의 순번을 그대로 쓰면 새 띠가 목록
    가운데 끼어 그 뒤 띠의 번호가 하나씩 밀린다. boards.mjs의 replay와 같은 길 — strips · events는 다시 돌린 목록을 읽으므로 그 뒤에
    바꿔 끼우고, power는 다시 돌린 out.periods를 순번으로 읽으므로 되돌린다.
    [baseUids] 기본 결과에 있는 띠 · [baseBand] 기본 띠의 순번(bands.mjs — 첫 조각) · [nextAt] 이 변형의 새 띠가 붙기 시작할 자리. */
async function replay(ctx, mods, baseUids, baseBand, nextAt) {
  const out = emptyOut(ctx.raw.name);
  const sub = Object.assign({}, ctx, { shared: {}, notes: {} });
  let replayed = null;
  for (const name of REPLAY) {
    if (name === 'hangs') {
      replayed = sub.shared.bandOf;
      const final = new Map();
      let next = nextAt;
      for (const p of out.periods) {
        if (baseUids.has(p.uid)) {
          if (!final.has(p.uid)) final.set(p.uid, baseBand.get(p.uid));
          continue;
        }
        if (!final.has(p.uid)) final.set(p.uid, next); // 새 띠의 조각은 모두 차례대로 붙는다 — 번호는 첫 조각의 것
        next++;
      }
      sub.shared.bandOf = final;
    }
    if (name === 'power' && replayed) sub.shared.bandOf = replayed;
    const mod = mods.get(name);
    if (mod) await mod.contribute(sub, out);
  }
  return { out, notes: sub.notes };
}

export async function contribute(ctx, out) {
  const { tl, model } = ctx;
  const mods = new Map();
  for (const name of REPLAY) mods.set(name, await importModule(name));
  const trackIndex = ctx.trackIndex;

  /* 변형 목록. 소속 펼치기는 단추가 생기는 상위 정권마다(명세 5-2의 셈 그대로 — 지금 연표의 _drawTrack 6941줄),
     대범위는 자료에 적힌 것마다 하나씩. */
  const variants = [];
  tl.tracks.forEach((tr, at) => {
    for (const p of tr.periods) {
      if (p._hidden || p._overlay || p._under || p._row == null) continue;
      const n = (p.members || []).filter(m => m.track === tr.id && m.singleHost && !m.groupUid && m.polityKind !== 'overlay' && !(m._scope && m._host !== p)).length;
      if (n > 0) variants.push({ key: `host:${p.uid}`, kind: 'host', uid: p.uid, track: at, name: p.name || '', members: n });
    }
  });
  /* 단체 펼치기(리메이크 조각 ④ · 설계 4-6 #7 C '손잡이로 펼침'): 그 나라에 접혀 든 단체의 띠(core.js의 groupUid — 숨은 토막)가 있는 나라마다 하나.
     소속 펼치기와 같은 길(그 나라 밑에 새 줄)이고, 수(members)는 단체 수(토막이 아니라 단체)다. */
  tl.tracks.forEach((tr, at) => {
    for (const p of tr.periods) {
      if (p._hidden || p._overlay || p._under || p._row == null) continue;
      const n = new Set((p.members || []).filter(m => m.track === tr.id && m.singleHost && m.groupUid).map(m => m.groupUid)).size;
      if (n > 0) variants.push({ key: `groups:${p.uid}`, kind: 'groups', uid: p.uid, track: at, name: p.name || '', members: n });
    }
  });
  for (const s of model.scopes || []) {
    const at = trackIndex.has(s.track) ? trackIndex.get(s.track) : -1;
    if (at < 0) continue;
    variants.push({ key: `scope:${s.uid}`, kind: 'scope', uid: s.uid, track: at, name: s.name || '' });
  }

  const base = snapshot(tl);
  /** 기본 상태에 있던 묶음의 이름 — 그 변형에서만 생기는 묶음(대범위 가지)을 가린다. */
  const baseGroupKeys = base.map(t => new Set(t.groups.map(g => g.key)));
  const baseRows = out.tracks.map(t => t.rows.length);
  const baseBandUids = new Set(out.periods.map(p => p.uid));
  /** 기본 띠의 순번(bands.mjs가 채운 것 — 기본 항목의 띠 번호가 쓴 값) — 변형의 띠 번호를 이 번호 공간으로 맞춘다(replay). */
  const baseBand = ctx.shared.bandOf;
  assert.ok(baseBand, '변형: 띠 모듈(bands)이 먼저 돌아야 합니다');
  const baseEventUids = new Set(out.events.map(e => e.uid));
  /** 느슨한 이름 → 기본 항목의 자리(여럿이면 가리지 않고 새 항목으로 본다). */
  const baseItemAt = new Map();
  out.items.forEach((it, i) => {
    const k = itemKeyOf(it);
    if (!baseItemAt.has(k)) baseItemAt.set(k, []);
    baseItemAt.get(k).push(i);
  });
  const baseCellAt = new Map();
  out.cells.forEach((c, i) => {
    const k = cellKeyOf(c);
    if (!baseCellAt.has(k)) baseCellAt.set(k, []);
    baseCellAt.get(k).push(i);
  });
  const baseLabelRows = new Set((out.rowLabels || []).map(l => `${l.track}#${l.row}`));
  /** 기본 줄 이름의 자리(트랙 · 줄 · 띠) — 민족 딱지가 변형마다 달라지는 곳에 덧글을 얹으려고 찾아 둔다. */
  const baseLabelAt = new Map();
  for (const l of out.rowLabels || []) {
    if (l.kind === 0) baseLabelAt.set(`${l.track}#${l.row}#${l.period}`, l);
  }

  const list = (out.variants = []);
  const notes = { 변형: variants.length, 선반: 0, 새줄: 0, 쌓는차례: 0, 이사: 0, 새띠: 0, 새사건: 0, 새항목: 0, 변형판: 0, 새칸: 0, 새줄이름: 0, 새묶음: 0, 민족딱지: 0, 빠지는줄: 0, 가림: 0, 줄단위트랙값: [], 어긋남: [] };

  // 목록 끝에 선반 변형이 붙으므로(아래 scope 갈래) 순번으로 돈다 — 붙은 것도 돈다
  for (let vi = 0; vi < variants.length; vi++) {
    const v = variants[vi];
    const shelf = v.kind === 'shelf';
    relayout(tl, v);
    const got = snapshot(tl);
    /* 선반 변형의 후보: 이 그릇만 켠 배치에서 그 그릇이 차지한 구성원(_layoutTrack 선반 셈과 같은 거르기 — 숨은 · 밑깔림 · 기관이 아닌 것)이
       shelfKeep을 넘으면(지금 연표의 _shelfSplit) 그 그릇의 선반 변형을 목록 끝에 붙인다 */
    if (v.kind === 'scope') {
      const members = tl.tracks[v.track].periods.filter(p => p._scope && p._scope.uid === v.uid && !p._hidden && !p._under && !p._overlay);
      if (tl._shelfSplit(members).rest.length) {
        variants.push({ key: `shelf:${v.uid}`, kind: 'shelf', uid: v.uid, track: v.track, name: v.name });
        notes.선반++;
      }
    }
    const { out: vout } = await replay(ctx, mods, baseBandUids, baseBand, out.periods.length);
    const entry = { key: v.key, kind: VARIANT_KIND[v.kind], track: v.track, band: v.kind === 'host' || v.kind === 'groups' ? v.uid : '', uid: v.kind === 'scope' || shelf ? v.uid : '', name: v.name, rows: [], moves: [], groups: [], hides: [], notes: '' };
    const warn = [];

    /* ── 줄 맞추기: 변형의 줄 → 기본 줄(내용이 같은 줄). 못 찾으면 새 줄이다 ───────────── */
    const rowMap = tl.tracks.map(() => new Map()); // 변형 줄 번호 → 엔진 줄 번호(트랙 안)
    got.forEach((t, at) => {
      const b = base[at];
      const byKey = new Map();
      b.keys.forEach((k, r) => { if (!byKey.has(k)) byKey.set(k, r); });
      let next = out.tracks[at].rows.length; // 새 줄은 그 트랙의 줄 목록 뒤에 이어 붙인다(앞선 변형이 더한 줄 뒤에)
      const used = new Set();
      t.keys.forEach((k, r) => {
        const at2 = byKey.has(k) && !used.has(byKey.get(k)) ? byKey.get(k) : -1;
        if (at2 >= 0) {
          used.add(at2);
          rowMap[at].set(r, at2);
        } else {
          rowMap[at].set(r, next++);
        }
      });
    });

    /* ── 새 줄 · 쌓는 차례 ─────────────────────────────────────────────────────── */
    got.forEach((t, at) => {
      const b = base[at];
      const order = Array.from({ length: t.rows }, (_, r) => rowMap[at].get(r));
      for (let r = 0; r < t.rows; r++) {
        const row = order[r];
        const fresh = row >= baseRows[at];
        const after = r === 0 ? -1 : order[r - 1];
        const baseAfter = row >= baseRows[at] ? null : row === 0 ? -1 : row - 1;
        const padChanged = !fresh && b.scopePad[row] !== t.scopePad[r];
        const groupChanged = !fresh && b.groupStart[row] !== t.groupStart[r];
        if (fresh) {
          // 그 변형에서만 있는 줄: tracks.mjs가 변형 상태로 만든 줄 기록을 그대로 싣는다.
          const record = Object.assign({}, vout.tracks[at].rows[r], { variant: v.key });
          const slot = out.tracks[at].rows;
          assert.equal(slot.length, row, `새 줄의 자리가 어긋났습니다: ${v.key} 트랙 ${at} 줄 ${row}`);
          slot.push(record);
          notes.새줄++;
        } else if (!padChanged && !groupChanged) {
          // 값이 그대로인 기본 줄은 차례가 바뀌었을 때만 싣는다.
          const rec = vout.tracks[at].rows[r], old = out.tracks[at].rows[row];
          // `height`는 2판의 '줄의 몫'이라 차례가 바뀌면 맨 끝 줄의 아래 여백만큼 달라진다 — 다시 쌓기가 쓰지 않으므로 견주지 않는다.
          // `figWide`는 넉넉하게의 인물 단 수와 **줄 단위 트랙 값**(그 줄의 기간 막대 단 수 · 기관 칸)을 함께 담은 값이다(계약 6-5절) —
          // 소속을 펼치면 상위 줄의 사건이 소속 줄로 옮겨 가 기본 줄의 막대 단 수가 줄어들 수 있으므로 여기에서 함께 본다.
          for (const k of ['bandH', 'lines', 'kind', 'phase', 'rank', 'fig', 'dep', 'zones', 'hem', 'figWide']) {
            if (rec[k] !== old[k]) warn.push(`트랙 ${at} 줄 ${row}의 ${k}가 ${old[k]} → ${rec[k]}로 달라졌으나 싣지 않았습니다`);
          }
          if (rec.figWide !== old.figWide) {
            notes.줄단위트랙값.push(`${v.key}: 트랙 ${at} 줄 ${row} — 막대 ${((old.figWide >> 3) & 7) - 1} → ${((rec.figWide >> 3) & 7) - 1} · 기관 ${(old.figWide & 64) !== 0} → ${(rec.figWide & 64) !== 0}`);
          }
          if (JSON.stringify(rec.cats) !== JSON.stringify(old.cats)) warn.push(`트랙 ${at} 줄 ${row}의 분류별 글줄이 달라졌으나 싣지 않았습니다`);
        }
        if (after !== baseAfter || padChanged || groupChanged) {
          entry.rows.push({ track: at, row, after, ord: 0, new: fresh ? 1 : 0, scopePad: Math.round(t.scopePad[r]), groupStart: t.groupStart[r] });
          if (!fresh) notes.쌓는차례++;
        }
      }
      /* 선반: 변형에 없는 기본 줄(구성원이 다 숨었거나 다시 지은 줄로 떠난 줄)은 빠지는 줄 — after −2 · ord −1(옮겨 간 판 줄이 없음 — 엔진 legacy.rs) · new 0.
         그 밖의 갈래는 줄 채우기의 울타리(fence)로 줄 내용이 변형마다 같아 빠지는 기본 줄이 없다(있어도 예전처럼 싣지 않는다 — 출력 그대로) */
      if (shelf) {
        const kept = new Set(rowMap[at].values());
        for (let row = 0; row < b.rows; row++) {
          if (kept.has(row)) continue;
          entry.rows.push({ track: at, row, after: -2, ord: -1, new: 0, scopePad: 0, groupStart: 0 });
          notes.빠지는줄++;
        }
      }
      if (t.height !== b.height && !t.keys.length) warn.push(`트랙 ${at}의 높이만 달라졌습니다`);
    });
    // 같은 자리에 여럿이면 차례를 매긴다(빠지는 줄은 쌓지 않으므로 세지 않음).
    {
      const seen = new Map();
      for (const r of entry.rows) {
        if (r.after === -2) continue;
        const key = `${r.track}#${r.after}`;
        r.ord = seen.get(key) || 0;
        seen.set(key, r.ord + 1);
      }
    }

    /* ── 이사: 줄이 옮겨 쌓인 것으로 설명되지 않는 띠 · 사건 ──────────────────────── */
    got.forEach((t, at) => {
      const b = base[at];
      for (const [uid, r] of t.bandRow) {
        if (!baseBandUids.has(uid)) continue; // 새 띠는 아래에서 통째로 싣는다
        const was = b.bandRow.get(uid);
        const now = r < 0 ? -1 : rowMap[at].get(r);
        if (was === undefined || now === was) continue;
        entry.moves.push({ kind: 1, ref: uid, row: now, track: at });
        notes.이사++;
      }
      /* 선반: 바탕 문화는 승계국 줄을 따라 깔리는데 선반은 줄을 다시 지어, 조각이 빠지는 줄에 남는다 — 기본 조각마다 변형에 같은 조각이 있으면
         그 줄로, 없으면(승계국이 모두 숨음 · 줄 번호가 바뀌어 조각 이름이 달라짐) −1로 옮긴다. 변형에만 있는 조각은 새 띠(아래)로 붙는다.
         그 밖의 갈래는 예전처럼 싣지 않는다(출력 그대로) */
      if (shelf) {
        for (const [uid, was] of b.underRow) {
          if (!baseBandUids.has(uid)) continue;
          const r = t.underRow.get(uid);
          const now = r == null ? -1 : rowMap[at].get(r);
          if (now === was) continue;
          entry.moves.push({ kind: 1, ref: uid, row: now, track: at });
          notes.이사++;
        }
      }
      for (const [uid, r] of t.eventRow) {
        if (!baseEventUids.has(uid)) continue;
        const was = b.eventRow.get(uid);
        const now = r < 0 ? -1 : rowMap[at].get(r);
        if (was === undefined || now === was) continue;
        entry.moves.push({ kind: 2, ref: uid, row: now, track: at });
        notes.이사++;
      }
    });

    /* ── 그 변형에서만 생기는 것 ─────────────────────────────────────────────── */
    const rowOf = (at, r) => {
      const row = rowMap[at].get(r);
      if (row == null) throw new Error(`${v.key}: 트랙 ${at}의 줄 ${r}을 옮길 곳이 없습니다`);
      return row;
    };
    const freshBand = new Set();
    for (const p of vout.periods) {
      if (baseBandUids.has(p.uid)) continue;
      out.periods.push(Object.assign({}, p, { row: rowOf(p.track, p.row), variant: v.key }));
      freshBand.add(p.uid);
      notes.새띠++;
    }
    for (const c of vout.cells) {
      const at = baseCellAt.get(cellKeyOf(c));
      if (at && at.length === 1) {
        if (cellSameOf(out.cells[at[0]]) !== cellSameOf(c)) {
          out.cells.push(Object.assign({}, c, { variant: v.key }));
          entry.hides.push({ kind: 3, at: at[0] });
          notes.새칸++;
        }
        continue;
      }
      if (at) continue;
      if (!freshBand.has(c.period)) { warn.push(`기본에 없던 칸이 기본 띠(${c.period})에 붙었습니다: ${c.name}`); continue; }
      out.cells.push(Object.assign({}, c, { variant: v.key }));
      notes.새칸++;
    }
    for (const e of vout.events) {
      if (baseEventUids.has(e.uid)) continue;
      out.events.push(Object.assign({}, e, { row: rowOf(e.track, e.row), variant: v.key }));
      notes.새사건++;
    }
    for (const it of vout.items) {
      // 두 끝을 따로 옮기면 차례가 뒤집힐 수 있다(새 줄은 줄 목록 뒤에 붙고 기본 줄은 제자리 — 대범위 가지 · 펼친 소속 줄이
      // 기본 줄보다 위에 쌓일 때). 옮긴 뒤 위 · 아래를 다시 고른다(boards.mjs와 같은 규칙 — 계약: row ≤ row2).
      const r1 = rowOf(it.track, it.row), r2 = rowOf(it.track, it.row2);
      const row = Math.min(r1, r2), row2 = Math.max(r1, r2);
      const at = baseItemAt.get(itemKeyOf(it));
      if (at && at.length === 1) {
        const old = out.items[at[0]];
        if (itemSameOf(old) === itemSameOf(it) && old.row === row && old.row2 === row2) continue; // 그대로다
        out.items.push(Object.assign({}, it, { row, row2, variant: v.key }));
        entry.hides.push({ kind: 4, at: at[0] }); // 이 변형에서는 기본 판을 가린다
        notes.변형판++;
        continue;
      }
      if (at) continue; // 느슨한 이름이 여럿이라 어느 것을 가릴지 가릴 수 없다 — 그대로 둔다
      out.items.push(Object.assign({}, it, { row, row2, variant: v.key }));
      notes.새항목++;
    }
    /* 선반: 기본 항목 가운데 변형 다시 셈에 짝이 없는 것(숨은 띠의 이름 · 승계선 · 막대 …)은 가린다(kind 4). 느슨한 이름을 수로 세어
       다시 셈에 그 이름이 하나도 없으면 그 이름의 기본 항목을 모두 가린다 — 하나라도 있으면 어느 것이 짝인지 가릴 수 없어 그대로 둔다(위 갈래와 같은 말). */
    if (shelf) {
      const left = new Map();
      for (const it of vout.items) left.set(itemKeyOf(it), (left.get(itemKeyOf(it)) || 0) + 1);
      const gone = [];
      for (const [k, at] of baseItemAt) {
        if (left.get(k)) continue;
        gone.push(...at);
      }
      gone.sort((a, b) => a - b);
      for (const at of gone) {
        entry.hides.push({ kind: 4, at });
        notes.가림++;
      }
    }
    for (const l of vout.rowLabels || []) {
      const row = rowOf(l.track, l.row);
      if (row >= baseRows[l.track]) {
        (out.rowLabels = out.rowLabels || []).push(Object.assign({}, l, { row, variant: v.key }));
        notes.새줄이름++;
        continue;
      }
      /* 그 변형에서만 생기는 묶음(대범위 가지)의 **접힘용 후보**: 가지의 첫 줄이 기본 줄이면 위의 갈래로 들지 않는다.
         가지를 접었을 때 보일 이름이라 함께 싣고, 켜지 않았을 때 쓰이지 않게 변형 열쇠를 단다(화면 쪽 row_labels.dart의 `live`). */
      if (l.kind === 2 && l.group && !baseGroupKeys[l.track].has(l.group)) {
        (out.rowLabels = out.rowLabels || []).push(Object.assign({}, l, { row, variant: v.key }));
        notes.새줄이름++;
        continue;
      }
      /* 기본 줄의 이름 글은 그대로 두지만 **민족 딱지**는 보기 조건이 줄 구성을 바꾸면 달라진다(계약 6-8절) —
         대범위를 켜면 그 가지에 든 줄의 덮개가 대범위 칸이 되어 딱지가 새로 생긴다. 줄 이름 표에는 변형 열이 없어
         판을 따로 실을 수 없으므로, 달라진 딱지만 그 줄의 이름 글 안에 `chipOn`(변형 열쇠 → 딱지 · 없어지면 null)으로 얹는다.
         고르는 일은 켠 변형을 아는 화면 쪽(row_labels.dart)이 한다. */
      if (l.kind !== 0) continue;
      const old = baseLabelAt.get(`${l.track}#${row}#${l.period}`);
      if (!old) continue;
      const now = l.chip || null;
      if (JSON.stringify(now) === JSON.stringify(old.chip || null)) continue;
      (old.chipOn = old.chipOn || {})[v.key] = now;
      notes.민족딱지++;
    }

    /* ── 왼쪽 칸의 새 묶음(대범위 칸) ─────────────────────────────────────────── */
    got.forEach((t, at) => {
      const had = new Set(base[at].groups.map(g => g.key));
      for (const g of t.groups) {
        if (had.has(g.key)) continue;
        const rows = [];
        for (let r = g.first; r < g.first + g.count; r++) rows.push(rowOf(at, r));
        entry.groups.push({ track: at, key: g.key, depth: g.depth, name: g.name, color: color(g.color, 0xa4b1b7), kind: g.scope ? 2 : g.culture ? 1 : 0, rows });
        notes.새묶음++;
      }
    });

    /* ── 자체 점검: 기본 줄 + 이 변형의 차이로 다시 쌓으면 지금 연표와 같은 자리인가 ── */
    const stacked = restack(out, entry, base, baseRows);
    got.forEach((t, at) => {
      const want = stacked[at];
      if (!want) return;
      for (let r = 0; r < t.rows; r++) {
        const row = rowMap[at].get(r);
        if (Math.abs((want.top.get(row) ?? NaN) - t.rowTop[r]) > 0.001) {
          warn.push(`트랙 ${at} 줄 ${row}의 자리: 계약 ${want.top.get(row)} ≠ 연표 ${t.rowTop[r]}`);
        }
      }
      if (Math.abs(want.height - t.height) > 0.001) warn.push(`트랙 ${at}의 높이: 계약 ${want.height} ≠ 연표 ${t.height}`);
    });

    if (warn.length) {
      entry.notes = warn.slice(0, 6).join(' · ');
      notes.어긋남.push(`${v.key}: ${warn.length}곳 — ${warn[0]}`);
    }
    list.push(entry);
  }

  relayout(tl, null); // 기본 상태로 되돌린다
  ctx.notes.변형 = notes;
}

/** 기본 줄 + 한 변형의 차이로 줄을 다시 쌓아 본다(계약 3절의 식 · 화면 쪽 layout.dart와 같은 차례 — 높이 식은 2026-10-15부터 앱이 꼬리표 갈래 E로 다르다).
 *  돌려주는 값: 트랙마다 { top: Map(줄 → 위 자리), height }. */
function restack(out, entry, base, baseRows) {
  return out.tracks.map((track, at) => {
    const rows = track.rows;
    const own = entry.rows.filter(r => r.track === at);
    const gone = new Set(own.filter(r => r.after === -2).map(r => r.row)); // 빠지는 줄(선반)은 쌓지 않는다 — 트랙 값(trackValuesOf)도 산 줄로만
    const belongs = r => !gone.has(r) && (r < baseRows[at] || own.some(x => x.row === r && x.new));
    const afterOf = new Map(), padOf = new Map(), startOf = new Map();
    for (const r of own) { afterOf.set(r.row, r.after); padOf.set(r.row, r.scopePad); startOf.set(r.row, r.groupStart); }
    const live = [];
    for (let r = 0; r < rows.length; r++) if (belongs(r)) live.push(r);
    const anchor = r => (afterOf.has(r) ? afterOf.get(r) : r === 0 ? -1 : r - 1);
    const next = new Map();
    for (const r of live) {
      const a = anchor(r);
      if (!next.has(a)) next.set(a, []);
      next.get(a).push(r);
    }
    for (const [, kids] of next) {
      kids.sort((x, y) => {
        const ox = own.find(o => o.row === x), oy = own.find(o => o.row === y);
        return ((ox && ox.ord) || 0) - ((oy && oy.ord) || 0) || x - y;
      });
    }
    const order = [];
    const seen = new Set();
    const stack = [...(next.get(-1) || [])].reverse();
    while (stack.length) {
      const r = stack.pop();
      if (seen.has(r)) continue;
      seen.add(r);
      order.push(r);
      const kids = next.get(r) || [];
      for (let i = kids.length - 1; i >= 0; i--) stack.push(kids[i]);
    }
    for (const r of live) if (!seen.has(r)) order.push(r); // 닿지 못한 줄(고리)은 뒤에
    const top = new Map();
    const on = trackValuesOf(track, rows, live); // 그 변형에서 보이는 줄들로 다시 셈한 트랙 값
    let y = G.pad;
    let first = true;
    for (const r of order) {
      const spec = rows[r];
      const pad = padOf.has(r) ? padOf.get(r) : spec.scopePad || 0;
      const crosses = startOf.has(r) ? startOf.get(r) : spec.groupStart || 0;
      const tab = spec.kind === 3 || spec.kind === 2 ? 0 : G.tab;
      const gap = (first ? 0 : spec.kind === 1 && !crosses ? G.memberGap : G.gap + (crosses ? G.groupGap : 0)) + tab + pad;
      y += gap;
      top.set(r, y);
      y += rowHeight(track, spec, on);
      first = false;
    }
    return { top, height: Math.max(y + G.pad, G.folded) };
  });
}

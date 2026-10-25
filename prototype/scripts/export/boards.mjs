// 집합 보기(10건 6 · 감독 선택 D4 결정 1 A · 2 A · 5 A — 설계 docs/설계-10건/6-모아-보기와-배치.md 9절) — 새 앱(아카이브)은 스스로 다시 배치하지 못하므로
// **판마다 '판을 켠 배치'를 미리 셈해** 변형 kind 3(`view:<id>` — 계약 부록 가-9의 예약)으로 싣는다. 엔진은 변형을 나르기만 하고(variants_of),
// 앱은 켬끔에 맞춰 바꿔 그린다(scene/layout.dart · 판 트랙을 맨 위에 · 나머지 트랙은 판의 접힘).
//
// 판 둘:
//   ① DLC가 준 판(모델의 views — `view:<id>`)                         열쇠 `view:<id>`
//   ② 시대 구분의 '이 시대의 나라' 임시 판(결정 5 A · 저장하지 않음)   열쇠 `view:epoch:<시대 구분 uid>`
//      — 앱은 판을 셈하지 못하므로 시대 구분마다 **기본 후보 그대로의 판 하나**를 미리 싣는다(웹 views-ui.js의 candidates(x, false) · epochBoard).
//        칩으로 빼고 넣기 · '같은 기간의 다른 트랙 나라'는 조합마다 배치가 달라 미리 실을 수 없다 — 앱의 카드는 칩을 보여 주기만 한다(보고의 결정 기록).
//
// 판 하나를 켠 배치는 지금 연표의 길 그대로다: tl.board를 걸고 tl._boardPlan()(구성 나라의 줄을 통째로 맨 위 합성 트랙 __board로 · 원래 트랙에서는 그 줄을 뺌) →
// 판 트랙 · 원래 트랙을 다시 배치 → 줄 · 띠 · 그릴 것을 만드는 모듈(REPLAY)을 **판 트랙과 원래 트랙에만** 다시 돌려 기본 상태와 견준다.
// 판을 켠 동안 나머지 트랙은 접히지만(결정 1 A) 접힘은 보기 상태라 여기서는 모두 편 채로 셈한다(앱이 접는다).
//
// 싣는 곳: **새 겉 열쇠 `boards`** — 옛 열쇠(tracks · periods · cells · events · items · rowLabels · variants · entities)는 판이 있어도 1바이트도 달라지지 않는다
// (모르는 열쇠는 옛 엔진이 건너뛴다 · 판 자료는 변형 열쇠를 달아 켜지 않으면 없는 것과 같다).
//   boards.tracks    판마다 판 트랙 하나(열쇠 `__board:<변형 열쇠>` · 줄은 모두 그 변형의 줄) — 가져오기가 옛 트랙 · 줄 **뒤에** 붙인다(옛 줄 번호 그대로)
//   boards.variants  변형(kind 3): rows(판 줄의 쌓는 차례 · 원래 트랙의 사라진 줄 after −2 · 남은 줄의 새 차례) · moves(띠 · 사건이 판 줄로) ·
//                    hides(바뀐 칸 · 그릴 것의 기본 판을 가림) · groups(왼쪽 칸: 원래 트랙 칩 kind 3 · 제 민족 칩 kind 0/1)
//   boards.cells · items · rowLabels   그 변형에서만 있는 칸 · 그릴 것 · 줄 이름(variant 열쇠)
//   boards.entities  판 기록 `board:<변형 열쇠>`(kind board) — 앱의 목록 · 시대 구분 카드가 읽는다(이름 · 색 · 기간 · 구성 나라 · 수)
//
// 사라진 줄(after −2): 원래 트랙에서 판으로 통째로 옮겨 간 줄. 앱은 그 줄을 쌓지 않고(빈 줄이 남지 않음), `to`(그 줄이 옮겨 간 판 줄)로 '가려는 곳 펴기'를 잇는다.
//
// 자체 점검: 판 트랙 · 원래 트랙을 '기본 줄 + 변형의 차이'로 앱과 같은 식(계약 3-2절 · 사라진 줄 빼고)으로 다시 쌓아 지금 연표의 자리와 견준다 —
// 어긋나면 그 변형의 notes와 ctx.notes.집합보기.어긋남에 적는다. 다 돌린 뒤 연표가 기본 상태로 돌아왔는지(줄 차례 · 자리) 확인한다.
import { assert, importModule, color } from './base.mjs'; // 노드 내장을 직접 부르지 않는다(브라우저 겸용 — base.mjs 머리말)
import { G, rowHeight, trackValuesOf } from './variants.mjs';

/** 변형 번호(계약 부록 가-9의 예약): 3 집합 보기. */
export const BOARD_KIND = 3;

/** 판 트랙 · 원래 트랙에서 다시 돌릴 모듈 — variants.mjs의 REPLAY와 같은 차례. */
const REPLAY = ['tracks', 'bands', 'strips', 'events', 'hangs', 'figures', 'rails', 'links', 'scopes', 'minibars', 'labels', 'power'];

/** 지금 연표의 판 트랙 id(js/timeline.js의 BOARD_ID). */
const BOARD_ID = '__board';

/** 판의 기본 색 — 파스텔 열두 가지의 버터(js/views-ui.js의 BUTTER). */
const BUTTER = '#d7c18e';

/** 줄의 '내용' 열쇠 — variants.mjs와 같은 식(그 줄에 놓인 띠의 uid를 이은 글). */
const rowKeyOf = (tr, r) => (tr.rowPeriods[r] || []).map(p => p.uid).join('+') || (r === tr.commonRow ? '#공통' : `#빈${r}`);

/** 칸 · 그릴 것을 견주는 열쇠. 칸은 (띠 · 종류 · 기간 · 이름)이 같으면 같은 칸이고 단 · 모양 · 색이 달라지면 변형 판이다(variants.mjs와 같은 식). */
const cellKeyOf = c => [c.period, c.kind, c.start, c.end, c.name].join('');
const cellSameOf = c => [c.lane, c.style, c.color].join('');
/** 그릴 것은 **값까지 모두** 같아야 그대로다(줄은 엔진 번호 공간으로 옮겨 적은 뒤). */
const itemFullOf = (it, track, row, row2) =>
  [it.section, track, row, row2, it.start, it.end, it.lod, it.ref, it.name, it.color, it.a, it.b, it.c, it.d, it.text2].join('');

/** 판 목록: ① DLC가 준 판 ② 시대 구분마다 기본 후보 그대로의 임시 판. 웹(js/views-ui.js)의 boardOf · candidates · epochBoard와 같은 값. */
function boardsOf(ctx) {
  const { HT, model, tl } = ctx;
  const out = [];
  const keys = new Set();
  const trackName = id => {
    const t = (model.tracks || []).find(x => x.id === id);
    return t ? t.name || id : id;
  };
  const memberRows = list => list.map(p => ({ uid: p.uid, name: p.name || '', color: p.color || '', track: p.track || '', trackName: trackName(p.track) }));
  for (const v of model.views || []) {
    const members = (v.members || []).filter(Boolean);
    if (!members.length) continue; // 구성 나라를 하나도 찾지 못한 판은 켤 수 없다(웹도 켜지 않음 — 목록에서 알림)
    const key = v.uid; // `view:<id>`
    if (keys.has(key)) continue;
    keys.add(key);
    const missing = Math.max(0, HT.readScopeRefs(v.memberRefs).length - members.length);
    out.push({
      key, uid: v.uid, name: v.name || '', color: v.color || BUTTER, members: members.map(p => p.uid),
      start: v.start != null && Number.isFinite(v.start) ? v.start : undefined, end: v.start != null && Number.isFinite(v.endY) ? v.endY : undefined,
      temp: false, pack: ctx.packOf(v), packName: v.packName || '',
      record: { view: v.uid, packName: v.packName || '', members: memberRows(members), tracks: new Set(members.map(p => p.track)).size, missing },
    });
  }
  /* 시대 구분의 카드(결정 5 A): 같은 트랙(공통 시대 구분이면 모든 트랙) · 기간이 겹치는 나라(기관 · 문화 · 왕조 빼고) · 이어진 대범위의 구성 나라는 빼고.
     차례 = 연표의 줄 차례(echoBands의 order — 판을 켜기 전에 잰 것) → 시작 해. 내보내기는 거르기 없는 '모두 켠' 상태라 보이는 나라 = 모든 나라. */
  const ord = tl.echoBands();
  const tOrder = new Map((model.tracks || []).map((t, i) => [t.id, i]));
  const at = p => (ord.has(p.uid) ? ord.get(p.uid).order : (tOrder.get(p.track) ?? 1e6) + 0.999);
  for (const x of model.epochs || []) {
    const s = x.start;
    const e = x.endY != null ? x.endY : x.start;
    if (!Number.isFinite(s) || !Number.isFinite(e)) continue;
    const inScopes = new Set((x.scopes || []).flatMap(sc => (sc.members || []).map(p => p.uid)));
    const list = (model.periods || [])
      .filter(p => HT.itemKindOf(p) === 'period' && (!x.track || p.track === x.track) && p.start < e && (p.endY != null ? p.endY : p.start) > s && !inScopes.has(p.uid))
      .sort((a, b) => at(a) - at(b) || a.start - b.start);
    if (!list.length) continue; // 웹도 후보가 없으면 카드를 두지 않는다
    const key = `view:epoch:${x.uid}`;
    if (keys.has(key)) continue;
    keys.add(key);
    out.push({
      key, uid: x.uid, name: x.name || '', color: HT.pastel(HT.isColor(x.color) ? x.color : BUTTER), members: list.map(p => p.uid),
      start: s, end: e, temp: true, pack: ctx.packOf(x), packName: x.packName || '',
      record: {
        epoch: x.uid, epochTrack: x.track || '', scoped: (x.scopes || []).length > 0 ? 1 : 0, packName: x.packName || '',
        members: memberRows(list), tracks: new Set(list.map(p => p.track)).size, missing: 0,
      },
    });
  }
  return out;
}

/** 줄 자리 · 묶음 틈 · 대범위 여백 — 트랙 하나의 지금 배치를 찍어 둔다. */
function snapTrack(tl, tr) {
  return {
    id: tr.id,
    rows: tr.rows,
    height: tr.height,
    keys: Array.from({ length: tr.rows }, (_, r) => rowKeyOf(tr, r)),
    rowTop: tr.rowTop.slice(),
    scopePad: Array.from({ length: tr.rows }, (_, r) => Math.round(tl._scopePad(tr, r, r - 1))),
    groupStart: Array.from({ length: tr.rows }, (_, r) => (tr.groups.filter(gp => !tr.board || gp.from).some(gp => gp.first === r) ? 1 : 0)),
  };
}

/** 판을 켠 배치에서 REPLAY 모듈을 다시 돌린다(판 트랙 · 원래 트랙만). 띠 번호(링크의 b · 매달린 이름표의 d …)는 **기본 배치의 번호**로 맞춘다 —
    가져오기가 띠를 넣는 차례는 기본 배치의 것(out.periods)이라, 다시 돌린 배치의 순번을 그대로 쓰면 다른 띠를 가리킨다.
    strips · events는 다시 돌린 배치의 띠 목록을 읽어야 하므로 그 뒤에 바꿔 끼운다(bands.mjs가 채운 ctx.shared.bandOf). */
async function replay(ctx, mods, baseBand, trackIds) {
  const out = { name: ctx.raw.name, categories: [], tracks: [], epochs: [], axis: [], periods: [], cells: [], events: [], items: [], entities: [], rowLabels: [] };
  // 사건 모듈은 '내보낸 사건 수 = 모델의 사건 수'를 점검한다 — 다시 돌리는 트랙(원래 트랙)에 첫 자리가 있는 사건만 든 모델을 건넨다.
  const firstTrack = e => (e.placements && e.placements.length ? e.placements[0].track : e.track);
  const model = Object.assign({}, ctx.model, { events: (ctx.model.events || []).filter(e => trackIds.has(firstTrack(e))) });
  const sub = Object.assign({}, ctx, { model, shared: {}, notes: {} });
  for (const name of REPLAY) {
    if (name === 'hangs') sub.shared.bandOf = baseBand;
    // 단체 단은 다시 돌린 out.periods의 기간·줄을 읽는다. 관계선용 기본 띠 번호를 넘기면 판의 다른 나라를 읽는다.
    if (name === 'power') sub.shared.bandOf = new Map(out.periods.map((p, i) => [p.uid, i]));
    const mod = mods.get(name);
    if (mod) await mod.contribute(sub, out);
  }
  return out;
}

/** 판 하나: 지금 연표에 판을 걸고 다시 배치해 기본 상태와의 차이를 낸다. 판 트랙이 서지 않으면(구성 나라가 하나도 없음) null. */
async function boardOne(ctx, mods, b, env) {
  const { tl } = ctx;
  const order0 = tl.tracks.slice();
  const keep = order0.map(tr => [tr, tr.periods, tr.events, tr.figures]);
  let affected = [];
  tl.board = { id: b.key, name: b.name, color: b.color, members: b.members.slice(), start: b.start, end: b.end, temp: b.temp };
  tl._boardOpen = new Set(order0.map(t => t.id)); // 판을 켠 동안 나머지 트랙은 접히지만 — 접힘은 앱의 보기 상태라 여기서는 모두 편 채로 셈한다
  tl._boardFolded = false;
  try {
    tl._boardPlan();
    const btr = tl._boardTr;
    if (!btr) return null;
    affected = order0.filter(tr => tr.axisPeriods);
    tl._layoutTrack(btr);
    for (const tr of affected) tl._layoutTrack(tr);
    const live = [btr, ...affected];
    const all = tl.tracks;
    tl.tracks = live;
    let vout;
    try {
      vout = await replay(ctx, mods, env.baseBand, new Set(affected.map(tr => tr.id)));
    } finally {
      tl.tracks = all;
    }
    return diff(ctx, b, env, btr, affected, live.map(tr => snapTrack(tl, tr)), vout);
  } finally {
    tl.tracks = order0;
    for (const [tr, periods, events, figures] of keep) {
      tr.periods = periods;
      tr.events = events;
      tr.figures = figures;
      delete tr.axisPeriods;
    }
    tl.board = null;
    tl._boardTr = null;
    tl._boardUids = null;
    tl._boardOpen = new Set();
    tl._boardFolded = false;
    for (const tr of affected) tl._layoutTrack(tr); // 옮겨 갔던 정권의 배치 값(_row · _hidden · _seamL …)을 기본 상태로
  }
}

/** 판을 켠 배치(vout · 찍어 둔 자리 got)와 기본 상태(env)의 차이 → 판 트랙 하나 · 변형 하나 · 그 변형에서만 있는 것. */
function diff(ctx, b, env, btr, affected, got, vout) {
  const { out } = env;
  const warn = []; // 어긋남 — 앱이 웹과 다르게 그린다
  const note = []; // 알림 — 판을 켜면 접히는 원래 트랙을 펼 때만 보이는 차이(트랙 단위 단)
  const slotChanged = new Set();
  const boardIndex = env.nextTrack; // 판 트랙의 번호(옛 트랙 · 앞선 판 트랙 뒤)
  /** 다시 돌린 배치의 트랙 순번 → 엔진의 트랙 번호(판 트랙은 boardIndex). */
  const trackOf = j => (j === 0 ? boardIndex : env.trackAt.get(affected[j - 1].id));

  /* ── 줄 맞추기: 원래 트랙은 내용으로 기본 줄과 짝짓고, 판 트랙의 줄은 모두 새 줄이다 ─────────────── */
  const rowMap = got.map(() => new Map()); // 다시 돌린 배치의 줄 → 그 트랙의 엔진 줄(판 트랙은 판 트랙 안 차례)
  got[0].keys.forEach((_, r) => rowMap[0].set(r, r));
  const boardRowByKey = new Map();
  got[0].keys.forEach((k, r) => {
    if (!boardRowByKey.has(k)) boardRowByKey.set(k, r);
  });
  const gone = []; // [트랙 번호, 줄, 옮겨 간 판 줄(없으면 −1)]
  for (let j = 1; j < got.length; j++) {
    const a = trackOf(j);
    const base = env.base[a];
    const byKey = new Map();
    base.keys.forEach((k, r) => {
      if (!byKey.has(k)) byKey.set(k, r);
    });
    const used = new Set();
    got[j].keys.forEach((k, r) => {
      const at = byKey.has(k) && !used.has(byKey.get(k)) ? byKey.get(k) : -1;
      if (at < 0) throw new Error(`원래 트랙 ${base.id}에 기본 상태에 없던 줄이 생겼습니다(${k}) — 판의 차이로 실을 수 없습니다`);
      used.add(at);
      rowMap[j].set(r, at);
    });
    for (let r = 0; r < base.rows; r++) if (!used.has(r)) gone.push([a, r, boardRowByKey.has(base.keys[r]) ? boardRowByKey.get(base.keys[r]) : -1]);
  }
  const rowOf = (j, r) => {
    const row = rowMap[j].get(r);
    if (row == null) throw new Error(`${b.key}: 다시 돌린 배치의 줄 ${j}#${r}을 옮길 곳이 없습니다`);
    return row;
  };

  /* ── 판 트랙(새 트랙)과 그 줄 ─────────────────────────────────────────────── */
  const vt = vout.tracks[0];
  const track = {
    key: `${BOARD_ID}:${b.key}`, name: vt.name, color: vt.color,
    dynasty: vt.dynasty, leader: vt.leader, cabinet: vt.cabinet, organ: vt.organ, railLevels: vt.railLevels,
    rows: vt.rows.map(r => Object.assign({}, r, { variant: b.key })), groups: [], pack: b.pack,
  };
  const entry = { key: b.key, kind: BOARD_KIND, track: boardIndex, band: '', uid: b.uid, name: b.name, notes: '', rows: [], moves: [], hides: [], groups: [] };
  vt.rows.forEach((_, r) => {
    entry.rows.push({ track: boardIndex, row: r, after: r === 0 ? -1 : r - 1, ord: 0, new: 1, scopePad: Math.round(got[0].scopePad[r]), groupStart: got[0].groupStart[r] });
  });

  /* ── 원래 트랙: 사라진 줄(after −2 · to = 옮겨 간 판 줄)과 남은 줄의 새 차례 · 덮어쓰는 값 ─────────────── */
  for (const [a, row, to] of gone) {
    const o = { track: a, row, after: -2, ord: 0, new: 0, scopePad: 0, groupStart: 0 };
    if (to >= 0) Object.assign(o, { toTrack: boardIndex, to });
    entry.rows.push(o);
  }
  for (let j = 1; j < got.length; j++) {
    const a = trackOf(j);
    const base = env.base[a], t = got[j];
    const order = Array.from({ length: t.rows }, (_, r) => rowMap[j].get(r));
    for (let r = 0; r < t.rows; r++) {
      const row = order[r];
      const after = r === 0 ? -1 : order[r - 1];
      const baseAfter = row === 0 ? -1 : row - 1;
      const padChanged = base.scopePad[row] !== t.scopePad[r];
      const groupChanged = base.groupStart[row] !== t.groupStart[r];
      // 줄의 생김새(글줄 · 단 …)는 변형이 덮어쓸 수 없다 — 달라지면 알린다(앱은 보이는 줄들로 트랙 값 · 글줄 수를 다시 셈하므로 대개 같다).
      const rec = vout.tracks[j].rows[r], old = out.tracks[a].rows[row];
      // 글줄 수(lines)는 앱이 남은 줄 수로 다시 셈한다(scene/layout.dart의 _bandOf — 아래 자체 점검의 restack도 같은 식) — 견주지 않는다.
      for (const k of ['bandH', 'kind', 'phase', 'rank', 'fig', 'dep', 'zones', 'hem']) {
        if (rec[k] !== old[k]) (k === 'bandH' ? note : warn).push(`트랙 ${a} 줄 ${row}의 ${k}가 ${old[k]} → ${rec[k]}로 달라졌으나 싣지 않았습니다`);
      }
      if (after !== baseAfter || padChanged || groupChanged) {
        entry.rows.push({ track: a, row, after, ord: 0, new: 0, scopePad: Math.round(t.scopePad[r]), groupStart: t.groupStart[r] });
      }
    }
    // 트랙 단위 단(왕조 · 지도자 · 내각)은 트랙 하나의 값이라 변형이 바꿀 수 없다 — 원래 트랙을 판을 켠 채 펴면 기본 값으로 그린다(알림 — 판을 켜면 접혀 있다).
    const vt2 = vout.tracks[j], ot = out.tracks[a];
    for (const k of ['dynasty', 'leader', 'cabinet']) {
      if (vt2[k] === ot[k]) continue;
      note.push(`트랙 ${a}의 ${k} 단 ${ot[k]} → ${vt2[k]}(판을 켠 채 그 트랙을 펴면 기본 값)`);
      slotChanged.add(a);
    }
  }
  {
    const seen = new Map();
    for (const r of entry.rows) {
      if (r.after === -2) continue;
      const k = `${r.track}#${r.after}`;
      r.ord = seen.get(k) || 0;
      seen.set(k, r.ord + 1);
    }
  }

  /* ── 이사: 띠가 판 줄로 ─────────────────────────────────────────────────────
        엔진은 칸 · 사건 · 그릴 것을 **가리키는 띠를 따라** 옮긴다(variant.rs의 band_row · event_row · item_rows). 그래서 사건은 그 띠를 따라가는 자리와
        판을 켠 자리가 다를 때만 따로 옮기고, 그릴 것은 엔진이 옮긴 자리를 흉내 내어 판을 켠 자리와 같으면 그대로 둔다 — 같은 자료를 두 번 싣지 않는다. */
  const G_ = (t, r) => env.firstRow(t) + r; // 엔진의 전체 줄 번호(옛 트랙 · 줄 뒤에 판 트랙 · 줄이 붙는다)
  const bandDest = new Map(); // 옮긴 띠 → 전체 줄 번호
  const seenBands = new Set();
  for (const p of vout.periods) {
    seenBands.add(p.uid);
    const was = env.bandAt.get(p.uid);
    if (!was) {
      warn.push(`기본 상태에 없던 띠가 생겼습니다: ${p.name}`);
      continue;
    }
    const now = [trackOf(p.track), rowOf(p.track, p.row)];
    if (now[0] === was[0] && now[1] === was[1]) continue;
    entry.moves.push({ kind: 1, ref: p.uid, track: now[0], row: now[1] });
    bandDest.set(p.uid, G_(now[0], now[1]));
  }
  const eventDest = new Map(); // 사건 → 엔진이 그리는 전체 줄(제 이사 → 든 띠의 이사 → 제자리)
  let followed = 0;
  for (const e of vout.events) {
    const was = env.eventAt.get(e.uid);
    if (!was) {
      warn.push(`기본 상태에 없던 사건이 생겼습니다: ${e.title}`);
      continue;
    }
    const t = trackOf(e.track), r = rowOf(e.track, e.row);
    const now = G_(t, r);
    const band = env.eventBand.get(e.uid) || '';
    const engine = bandDest.has(band) ? bandDest.get(band) : G_(was[0], was[1]);
    if (engine === now) {
      if (now !== G_(was[0], was[1])) {
        eventDest.set(e.uid, now);
        followed++;
      }
      continue;
    }
    entry.moves.push({ kind: 2, ref: e.uid, track: t, row: r });
    eventDest.set(e.uid, now);
  }
  const touched = new Set([boardIndex, ...affected.map(tr => env.trackAt.get(tr.id))]);
  for (const p of out.periods) if (!p.variant && touched.has(p.track) && !seenBands.has(p.uid)) warn.push(`판을 켜면 사라지는 띠: ${p.name}`);

  /* ── 칸: 띠를 따라간다. 단 · 모양 · 색이 달라진 칸만 변형 판(기본 판을 가림) ─────────────────────── */
  const cells = [];
  for (const c of vout.cells) {
    const at = env.cellAt.get(cellKeyOf(c));
    if (at && at.length === 1) {
      if (cellSameOf(out.cells[at[0]]) !== cellSameOf(c)) {
        cells.push(Object.assign({}, c, { variant: b.key }));
        entry.hides.push({ kind: 3, at: at[0] });
      }
      continue;
    }
    if (at) continue; // 이름이 같은 칸이 여럿 — 가릴 수 없어 그대로 둔다(variants.mjs와 같은 규칙)
    cells.push(Object.assign({}, c, { variant: b.key }));
  }

  /* ── 그릴 것: 기본 항목을 엔진이 옮겨 그릴 자리(variant.rs의 item_rows — 가리키는 띠 · 사건이 옮겨 가면 그쪽 끝을 따라감)를 흉내 내어,
        판을 켠 배치의 항목과 **값까지 같으면** 그대로 둔다. 남는 기본 항목은 가리고, 판을 켠 배치에만 있는 항목은 그 변형의 판으로 싣는다
        (판의 항목은 엔진이 옮기지 않는다 — 이미 판을 켠 자리에 있다: variant.rs의 boards). ─────────────── */
  const dests = new Set([...bandDest.values(), ...eventDest.values()]);
  const engineRows = it => {
    const row = G_(it.track, it.row), row2 = G_(it.track, it.row2);
    const to = env.bandAt.has(it.ref) ? bandDest.get(it.ref) : eventDest.get(it.ref);
    if (to == null) return [row, row2];
    if (row === row2) return [to, to];
    const other = dests.has(row) || row2 === to ? row : row2;
    return [Math.min(to, other), Math.max(to, other)];
  };
  const sig = (it, row, row2) => [it.section, row, row2, it.start, it.end, it.lod, it.ref, it.name, it.color, it.a, it.b, it.c, it.d, it.text2].join('');
  const pool = new Map(); // 엔진이 그릴 모습 전체 → 기본 항목의 자리 목록
  for (const at of env.itemsOf(touched)) {
    const it = out.items[at];
    const [row, row2] = engineRows(it);
    const k = sig(it, row, row2);
    if (!pool.has(k)) pool.set(k, []);
    pool.get(k).push(at);
  }
  const items = [];
  for (const it of vout.items) {
    let row, row2;
    try {
      row = rowOf(it.track, it.row);
      row2 = rowOf(it.track, it.row2);
    } catch (e) {
      e.message += ` — 그릴 것 구역 ${it.section} · ${it.name || it.ref || ''}`; // 어느 모듈의 무엇이 줄을 벗어났는지
      throw e;
    }
    const t = trackOf(it.track);
    const lo = Math.min(row, row2), hi = Math.max(row, row2);
    const list = pool.get(sig(it, G_(t, lo), G_(t, hi)));
    if (list && list.length) {
      list.pop(); // 엔진이 그대로(또는 띠를 따라 옮겨) 그리는 기본 항목
      continue;
    }
    items.push(Object.assign({}, it, { track: t, row: lo, row2: hi, variant: b.key }));
  }
  for (const list of pool.values()) for (const at of list) entry.hides.push({ kind: 4, at });
  // 다시 돌리지 않은 트랙의 항목이 옮겨 간 띠 · 사건을 가리키면 엔진이 그 끝을 판으로 끌고 간다 — 가리고 제자리 그대로의 판으로 다시 싣는다.
  for (const at of env.itemsOutside(touched)) {
    const it = out.items[at];
    const [row, row2] = engineRows(it);
    if (row === G_(it.track, it.row) && row2 === G_(it.track, it.row2)) continue;
    entry.hides.push({ kind: 4, at });
    items.push(Object.assign({}, it, { variant: b.key }));
    note.push(`다른 트랙의 항목이 판으로 옮긴 것을 가리켜 제자리 판으로 다시 실었습니다: 구역 ${it.section}`);
  }
  env.followed = (env.followed || 0) + followed;

  /* ── 줄 이름: 판 줄의 것만(원래 트랙의 남은 줄은 기본 줄 이름 그대로 — 민족 딱지가 바뀌면 알림) ─────────── */
  const labels = [];
  for (const l of vout.rowLabels || []) {
    if (l.track !== 0) continue;
    labels.push(Object.assign({}, l, { track: boardIndex, variant: b.key }));
  }

  /* ── 왼쪽 칸: 원래 트랙 칩(kind 3 · 첫 단) · 제 민족 칩(kind 0 · 문화는 1 · 둘째 단) — 판 트랙의 묶음 그대로 ─────────── */
  for (const gp of btr.groups || []) {
    if (!gp.count) continue;
    const rows = [];
    for (let r = gp.first; r < gp.first + gp.count; r++) rows.push(r);
    entry.groups.push({
      track: boardIndex, key: gp.from ? `__from:${gp.track}#${gp.first}` : `__bp:${gp.key}#${gp.first}`, depth: gp.depth, name: gp.name || '',
      color: color(gp.color, 0xa4b1b7), kind: gp.from ? 3 : gp.culture ? 1 : 0, rows,
    });
  }

  /* ── 자체 점검: 기본 줄 + 이 변형의 차이로 앱과 같은 식으로 다시 쌓으면 지금 연표의 자리인가 ─────────────── */
  const checks = [[0, boardIndex, track]];
  for (let j = 1; j < got.length; j++) if (!slotChanged.has(trackOf(j))) checks.push([j, trackOf(j), out.tracks[trackOf(j)]]);
  for (const [j, a, rec] of checks) {
    const stacked = restack(a, rec, entry);
    const t = got[j];
    for (let r = 0; r < t.rows; r++) {
      const row = rowMap[j].get(r);
      const want = stacked.top.get(row);
      if (want == null || Math.abs(want - t.rowTop[r]) > 0.001) warn.push(`트랙 ${a} 줄 ${row}의 자리: 계약 ${want} ≠ 연표 ${t.rowTop[r]}`);
    }
    if (Math.abs(stacked.height - t.height) > 0.001) warn.push(`트랙 ${a}의 높이: 계약 ${stacked.height} ≠ 연표 ${t.height}`);
  }

  if (warn.length || note.length) entry.notes = [...warn, ...note].slice(0, 6).join(' · ');

  /* ── 판 기록(앱의 목록 · 시대 구분 카드) ─────────────────────────────────────────── */
  const present = b.members.filter(uid => env.ownerOf.has(uid));
  const record = Object.assign(
    {
      key: b.key, name: b.name, color: b.color, temp: b.temp ? 1 : 0, label: (btr.board && btr.board.label) || '',
      present: present.length, presentTracks: new Set(present.map(uid => env.ownerOf.get(uid))).size,
    },
    b.start != null ? { start: b.start, end: b.end != null ? b.end : b.start } : {},
    b.record,
  );
  const entity = { uid: `board:${b.key}`, kind: 'board', pack: b.pack, json: JSON.stringify(record) };
  return { track, entry, cells, items, labels, entity, warn, note, gone: gone.length };
}

/** 기본 줄 + 판 변형의 차이로 트랙 하나를 다시 쌓는다 — 앱(scene/layout.dart의 _build · _orderOf)과 같은 차례:
    사라진 줄(after −2)은 빼고, 숨은 줄을 건너서도 묶음 경계(+14)는 남는다(건넌 줄 가운데 groupStart가 있으면). */
function restack(trackIndex, record, entry) {
  const rows = record.rows;
  const own = entry.rows.filter(r => r.track === trackIndex);
  const over = new Map(own.map(r => [r.row, r]));
  const goneRows = new Set(own.filter(r => r.after === -2).map(r => r.row));
  const live = [];
  for (let r = 0; r < rows.length; r++) if (!goneRows.has(r) && (!rows[r].variant || rows[r].variant === entry.key)) live.push(r); // 다른 변형(소속 펼치기 · 대범위)의 줄은 켜지 않았다
  const anchor = r => (over.has(r) ? over.get(r).after : r === 0 ? -1 : r - 1);
  const next = new Map();
  for (const r of live) {
    const a = anchor(r);
    if (!next.has(a)) next.set(a, []);
    next.get(a).push(r);
  }
  for (const [, kids] of next) kids.sort((x, y) => ((over.get(x) || {}).ord || 0) - ((over.get(y) || {}).ord || 0) || x - y);
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
  for (const r of live) if (!seen.has(r)) order.push(r);
  const track = record; // 트랙 단위 단(왕조 · 지도자 · 내각)은 트랙 기록의 값 · 막대 단 수와 기관 칸은 보이는 줄들로(trackValuesOf)
  const on = trackValuesOf(track, rows, live);
  // 글줄 수: 앱(_bandOf)처럼 남은 줄 수로 — 분류별 글줄이 둘 이상이면 그 수, 아니면 자동 밀도의 문턱(6줄 이하면 2).
  const linesOf = spec => (spec.cats && spec.cats.length >= 2 ? spec.cats.length : live.length <= 6 ? 2 : 1);
  const top = new Map();
  let y = G.pad;
  let last = -1;
  for (const r of order) {
    const spec = rows[r];
    const o = over.get(r);
    const pad = o ? o.scopePad : spec.scopePad || 0;
    let crosses = o ? !!o.groupStart : false;
    for (let k = last < 0 ? 0 : last + 1; k <= r; k++) if (rows[k] && rows[k].groupStart && !goneRows.has(k)) crosses = true;
    const tab = spec.kind === 3 || spec.kind === 2 ? 0 : G.tab;
    const gap = (last < 0 ? 0 : spec.kind === 1 && !crosses ? G.memberGap : G.gap + (crosses ? G.groupGap : 0)) + tab + pad;
    y += gap;
    top.set(r, y);
    y += rowHeight(track, spec.kind === 3 ? spec : Object.assign({}, spec, { lines: linesOf(spec) }), on);
    last = r;
  }
  return { top, height: Math.max(y + G.pad, G.folded) };
}

export async function contribute(ctx, out) {
  const { tl } = ctx;
  const boards = boardsOf(ctx);
  const notes = { 판: 0, 임시판: 0, 새줄: 0, 사라진줄: 0, 이사: 0, 새칸: 0, 새항목: 0, 가림: 0, 새줄이름: 0, 묶음: 0, 뺀판: [], 어긋남: [], 알림: [] };
  ctx.notes.집합보기 = notes;
  if (!boards.length) return; // 판이 없으면 겉 열쇠도 없다 — 내보낸 글이 1바이트도 달라지지 않는다

  const mods = new Map();
  for (const name of REPLAY) mods.set(name, await importModule(name));
  const trackAt = new Map(tl.tracks.map((tr, i) => [tr.id, i]));
  const env = {
    out,
    trackAt,
    base: tl.tracks.map(tr => snapTrack(tl, tr)),
    nextTrack: out.tracks.length,
    // 기본 상태의 것만(소속 펼치기 · 대범위 변형이 더한 띠 · 사건 · 칸 · 그릴 것은 그 변형을 켰을 때만 있다 — variant 열쇠)
    baseBand: new Map(out.periods.map((p, i) => [p.uid, i])),
    bandAt: new Map(out.periods.filter(p => !p.variant).map(p => [p.uid, [p.track, p.row]])),
    eventAt: new Map(out.events.filter(e => !e.variant).map(e => [e.uid, [e.track, e.row]])),
    eventBand: new Map(out.events.filter(e => !e.variant).map(e => [e.uid, e.band || ''])),
    boardRows: [], // 받아들인 판 트랙마다의 줄 수(전체 줄 번호 셈)
    firstRow: null,
    cellAt: new Map(),
    ownerOf: new Map(tl.tracks.flatMap(tr => tr.periods.map(p => [p.uid, tr.id]))),
    itemsOf: null,
    itemsOutside: null,
  };
  out.cells.forEach((c, i) => {
    if (c.variant) return;
    const k = cellKeyOf(c);
    if (!env.cellAt.has(k)) env.cellAt.set(k, []);
    env.cellAt.get(k).push(i);
  });
  const byTrack = new Map();
  out.items.forEach((it, i) => {
    if (it.variant) return;
    if (!byTrack.has(it.track)) byTrack.set(it.track, []);
    byTrack.get(it.track).push(i);
  });
  env.itemsOf = touched => [...touched].flatMap(t => byTrack.get(t) || []);
  env.itemsOutside = touched => [...byTrack.keys()].filter(t => !touched.has(t)).flatMap(t => byTrack.get(t));
  const before = env.base.map(t => JSON.stringify([t.keys, t.rowTop, t.height]));
  /* 엔진의 전체 줄 번호: 가져오기는 옛 트랙의 줄(그 트랙의 변형 줄까지)을 트랙 차례로 넣고, 그 뒤에 판 트랙의 줄을 판 차례로 넣는다(legacy.rs) */
  const baseFirst = [];
  {
    let n = 0;
    for (const t of out.tracks) {
      baseFirst.push(n);
      n += t.rows.length;
    }
    env.baseTotal = n;
  }
  env.firstRow = t => (t < out.tracks.length ? baseFirst[t] : env.baseTotal + env.boardRows.slice(0, t - out.tracks.length).reduce((a, b) => a + b, 0));

  const result = { tracks: [], variants: [], cells: [], items: [], rowLabels: [], entities: [] };
  for (const b of boards) {
    let got;
    try {
      got = await boardOne(ctx, mods, b, env);
    } catch (err) {
      notes.뺀판.push(`${b.key}: ${err && err.message ? err.message.split('\n')[0] : err}`);
      continue;
    }
    if (!got) {
      notes.뺀판.push(`${b.key}: 구성 나라가 연표에 없음`);
      continue;
    }
    env.nextTrack++;
    env.boardRows.push(got.track.rows.length);
    result.tracks.push(got.track);
    result.variants.push(got.entry);
    result.cells.push(...got.cells);
    result.items.push(...got.items);
    result.rowLabels.push(...got.labels);
    result.entities.push(got.entity);
    if (b.temp) notes.임시판++;
    else notes.판++;
    notes.새줄 += got.track.rows.length;
    notes.사라진줄 += got.gone;
    notes.이사 += got.entry.moves.length;
    notes.새칸 += got.cells.length;
    notes.새항목 += got.items.length;
    notes.가림 += got.entry.hides.length;
    notes.새줄이름 += got.labels.length;
    notes.묶음 += got.entry.groups.length;
    if (got.warn.length) notes.어긋남.push(`${b.key}: ${got.warn.length}곳 — ${got.warn[0]}`);
    if (got.note.length) notes.알림.push(`${b.key}: ${got.note.length}곳 — ${got.note[0]}`);
  }
  // 다 돌린 뒤 연표가 기본 상태로 돌아왔는가(뒤 모듈 · 다음 내보내기가 같은 배치를 읽게).
  const after = tl.tracks.map(tr => snapTrack(tl, tr)).map(t => JSON.stringify([t.keys, t.rowTop, t.height]));
  assert.equal(after.join('\n'), before.join('\n'), '집합 보기를 다 돌린 뒤 연표가 기본 배치로 돌아오지 않았습니다');
  if (result.variants.length) out.boards = result;
}


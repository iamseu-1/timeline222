// 관계선 — 건국 · 멸망 네모(20) · 승계선(21) · 소속선(22) · 할거기 칠(25) · 소속 단추(26) · 할거 모아 보기 단추(27) · 동군연합 이음줄의 끝(49).
// 지금 연표의 _squares · chainRows · _linkPlan · _hollowHTML · _scopeBtnsHTML이 쓰는 값 가운데 **화면 px과 무관한 것만** 싣는다
// (명세 docs/명세-3단계/04-관계선.md 8-1절 · 값의 뜻은 계약 6-10절). px에 달린 것(네모 생략 문턱 · seamPush · 길 고르기 · 문의 자리)은 그리는 쪽이 셈한다.
// 대범위 테두리(23) · 기간 칠(24)은 '켠 상태'에서만 생기고(줄이 통째로 옮겨 간다) 견본의 대범위는 모두 꺼진 채라 이번에는 싣지 않는다.
import { minute, color } from './base.mjs';
import { lodOf } from './rails.mjs';

/** 내가 쓰는 구역 번호(계약 6-10절) */
export const SECTION = { square: 20, link: 21, part: 22, scope: 23, scopeSpan: 24, hollow: 25, memBtn: 26, scopeBtn: 27, union: 49, groupsBtn: 51, move: 52 };

/** 승계 종류 번호 — 모르는 종류는 간접으로 본다(지금 연표의 succKind) */
const SUCC_NO = { direct: 0, indirect: 1, revival: 2, partial: 3 };

/** 구역 20 · 네모의 a 비트 */
const SQ = { unkS: 1, unkE: 2, ongoing: 4, seamL: 8, seamR: 16, rangeS: 32, rangeE: 64, refuted: 128, wideL: 256, wideR: 512 };
/** 직접이 아닌 승계(간접 · 부흥 · 부분)의 이음매 — 네모가 더 비켜 앉아(6px) 점선 다리가 보인다(묶음 5 · 7번 · 지금 연표의 seamWide와 같은 판정). q = 앞 띠, p = 뒤 띠 */
const seamWide = (q, p) => !!(q && p && (((p.predecessors || []).find(e => e.from === q) || {}).type || 'indirect') !== 'direct');
/** 구역 21 · 승계선의 a 비트 */
const LK = { down: 1 << 4, qFirst: 1 << 5, seam: 1 << 6, absorb: 1 << 7, bundled: 1 << 8, unkQ: 1 << 9, unkP: 1 << 10, rangeQ: 1 << 11, rangeP: 1 << 12, refuted: 1 << 13 };

const U32 = 0xfffffff0;
const clampU32 = v => (!Number.isFinite(v) || v <= 0 ? 0 : Math.min(U32, Math.round(v)));

/** 띠의 바깥 끝(연대 폭을 품은 해) — 지금 연표의 bandStart · bandEnd */
const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const bandOf = ctx.shared.bandOf || new Map(); // 띠의 uid → out.periods의 순번 (bands.mjs) — 띠 번호는 그 순번 + 1(가져오기가 넣는 차례)
  const idOf = uid => (bandOf.has(uid) ? bandOf.get(uid) + 1 : 0);
  const counts = { 네모: 0, 승계선: 0, 소속선: 0, 할거기칠: 0, 소속단추: 0, 대범위단추: 0, 동군연합끝: 0 };
  const skipped = { 승계_트랙밖: 0, 승계_숨은띠: 0, 소속_상국없음: 0 };
  const item = o => out.items.push(Object.assign({ section: 0, track: 0, row: 0, row2: 0, start: 0, end: 0, lod: -1, ref: '', name: '', color: 0, a: 0, b: 0, c: 0, d: 0, text2: '' }, o));
  const refuted = p => HT.historicityOf(p) === 'refuted';

  tl.tracks.forEach((tr, track) => {
    const hidden = row => tr.hiddenRows && tr.hiddenRows.has(row);
    /** 지금 연표가 네모 · 선을 그리는 띠(= _drawLinks의 거름) */
    const drawn = p => !p._folded && !p._hidden && !p._under && !p._overlay && p._row != null && p._row >= 0 && p._row < tr.rows && !hidden(p._row);

    /* ── 구역 20 · 건국 · 멸망 네모 ─────────────────────────────────────────────
       띠마다 하나로 싣는다(제안은 끝마다 하나였으나, 한쪽 네모를 그릴지가 **띠의 반대쪽 끝**에 달려 있고
       — 생략 문턱 w = x2 − x1 · 네모 하나뿐인 띠의 ec − fc — 두 끝은 서로 다른 타일에 실려 만나지 못한다. 계약 6-10절에 그대로 적었다).
       start · end = 띠의 바깥 끝(연대 폭을 품은 해). 확정 해는 b · c의 '안쪽 여백'으로 되돌린다:
       한쪽 끝은 이음매이거나 연대 폭이거나 둘 중 하나뿐이므로(chainRows는 연대 폭이 있는 끝에 이음매를 적지 않는다) 한 칸을 나눠 쓴다. */
    for (const p of tr.periods) {
      if (!drawn(p)) continue;
      const s = minute(bandStart(p)), e = minute(bandEnd(p));
      if (s == null || e == null || e < s) continue;
      const seamL = p._seamL && p._seamL._row === p._row ? p._seamL : null;
      const seamR = p._seamR && p._seamR._row === p._row ? p._seamR : null;
      const a =
        (p.startUnknown ? SQ.unkS : 0) | (p.endUnknown ? SQ.unkE : 0) | (p.ongoing ? SQ.ongoing : 0) |
        (seamL ? SQ.seamL | (seamWide(seamL, p) ? SQ.wideL : 0) : 0) | (seamR ? SQ.seamR | (seamWide(p, seamR) ? SQ.wideR : 0) : 0) |
        (p.startRange ? SQ.rangeS : 0) | (p.endRange ? SQ.rangeE : 0) | (refuted(p) ? SQ.refuted : 0);
      // 왼쪽 칸 b: 이음매면 앞 띠와의 틈(분), 연대 폭이면 바깥 끝 ↔ 확정 해의 거리(분)
      const b = seamL ? clampU32(s - minute(bandEnd(seamL))) : p.startRange ? clampU32(minute(p.start) - s) : 0;
      const c = seamR ? clampU32(minute(bandStart(seamR)) - e) : p.endRange ? clampU32(e - minute(p.endY)) : 0;
      item({ section: SECTION.square, track, row: p._row, row2: p._row, start: s, end: e, lod: -1, ref: p.uid, name: p.name || '', color: color(p.color), a, b, c });
      counts.네모++;
    }

    /* ── 구역 26 · 소속 펼치기 단추 '▸ n' (띠 안 첫 글줄) ─────────────────────── */
    for (const p of tr.periods) {
      if (!drawn(p)) continue;
      // 켠 대범위로 떠난 정권은 세지 않는다 — _drawTrack의 nMem과 같은 셈
      const n = (p.members || []).filter(m => m.track === tr.id && m.singleHost && !m.groupUid && m.polityKind !== 'overlay' && !(m._scope && m._host !== p)).length;
      if (!n) continue;
      const s = minute(bandStart(p)), e = minute(bandEnd(p));
      if (s == null || e == null || e < s) continue;
      item({ section: SECTION.memBtn, track, row: p._row, row2: p._row, start: s, end: e, lod: -1, ref: p.uid, name: p.name || '', color: color(p.color), a: n });
      counts.소속단추++;
    }

    /* ── 구역 51 · 단체 펼치기(리메이크 조각 ④ · 설계 4-6 #7 C — 든 나라 띠의 플래그 창 '단체 n') ──────────────
       그 나라에 접혀 든 단체의 띠(core.js의 groupUid — 숨은 토막)가 있는 나라마다 하나. a = 단체 수(토막이 아니라 단체),
       text2 = 플래그 창의 목록 — 단체마다 'uid␟이름␟#색'(␟ = U+001F)을 ␞(U+001E)로 이어 붙임(단체의 처음 차례). 펼치면 변형 `groups:<나라 uid>`. */
    for (const p of tr.periods) {
      if (!drawn(p)) continue;
      const groups = new Map();
      for (const m of p.members || []) if (m.track === tr.id && m.singleHost && m.groupUid && !groups.has(m.groupUid)) groups.set(m.groupUid, m);
      if (!groups.size) continue;
      const s = minute(bandStart(p)), e = minute(bandEnd(p));
      if (s == null || e == null || e < s) continue;
      const list = [...groups.values()].sort((a, b) => a.start - b.start).map(m => [m.groupUid, m.name || '', m.color || ''].join('\u001f')).join('\u001e');
      item({ section: SECTION.groupsBtn, track, row: p._row, row2: p._row, start: s, end: e, lod: -1, ref: p.uid, name: p.name || '', color: color(p.color), a: groups.size, text2: list });
      counts.단체단추 = (counts.단체단추 || 0) + 1;
    }

    /* ── 구역 21 · 승계선 ────────────────────────────────────────────────────
       고를 쌍과 차례는 _linkPlan 그대로(선대 uid → |Δ줄|). 세로 통로 번호 k는 '모두 켠 상태'의 기준값이다
       (화면에서 걸러진 쌍이 있으면 그리는 쪽이 다시 센다 — 명세 8-1절). */
    const edges = [];
    // '같은 트랙'은 선대가 지금 이 트랙에 놓였는가로 본다(자료의 track이 아니라) — 판을 켜면 구성 나라는 판 트랙(__board)으로 옮겨 가고
    // track은 원래 트랙 그대로라, track으로 보면 원래 트랙에 판 줄 번호로 선이 그어졌다(js/timeline.js _linkPlan과 같은 규칙 · 소속선의 tr.periods 찾기와 같은 뜻).
    const placed = new Set(tr.periods);
    for (const p of tr.periods) {
      if (p._folded || p._hidden || p._overlay) continue;
      for (const edge of p.predecessors || []) {
        const q = edge.from;
        if (!q) continue;
        if (!placed.has(q)) { skipped.승계_트랙밖++; continue; }
        if (q._row == null || p._row == null || q._folded || q._hidden || q._under || q._overlay || hidden(q._row) || hidden(p._row)) { skipped.승계_숨은띠++; continue; }
        edges.push({ edge, q, p });
      }
    }
    edges.sort((x, y) => HT.cmp16(x.q.uid, y.q.uid) || Math.abs(x.p._row - x.q._row) - Math.abs(y.p._row - y.q._row));
    const bundled = bundledEdges(tl, tr);
    const outIdx = new Map();
    for (const { edge, q, p } of edges) {
      const type = SUCC_NO[edge.type] != null ? SUCC_NO[edge.type] : SUCC_NO.indirect;
      let k = 0;
      if (q._row !== p._row) {
        k = outIdx.get(q.uid) || 0;
        outIdx.set(q.uid, k + 1); // 부분 승계도 한 칸(가는 한 줄 — 예전의 세 가닥은 1.6칸을 썼음 · js/timeline.js _linkPlan과 같은 증분)
      }
      const qe = minute(bandEnd(q)), pf = minute(bandStart(p));
      if (qe == null || pf == null) continue;
      const degree = type === SUCC_NO.partial ? (edge.degree === 1 || edge.degree === 3 ? edge.degree : 2) : 0;
      const a =
        type | (degree << 2) |
        (p._row > q._row ? LK.down : 0) | (bandEnd(q) <= bandStart(p) ? LK.qFirst : 0) |
        (p._seamL === q && q._row === p._row ? LK.seam : 0) | (HT.succAbsorbs(q, p) ? LK.absorb : 0) |
        (bundled.has(edge) ? LK.bundled : 0) |
        (q.endUnknown ? LK.unkQ : 0) | (p.startUnknown ? LK.unkP : 0) |
        (q.endRange ? LK.rangeQ : 0) | (p.startRange ? LK.rangeP : 0) |
        (refuted(q) || refuted(p) ? LK.refuted : 0);
      const tip = `${q.name} → ${p.name} · ${HT.successionLabel ? HT.successionLabel(edge) : edge.type}${edge.note ? ` · ${edge.note}` : ''}`;
      // 실리는 단계는 두 띠 가운데 짧은 쪽이 보이는 단계(명세 8-1절) — 두 끝이 다 보이지 않는 배율에서는 선도 없다.
      const span = Math.min(minute(bandEnd(q)) - minute(bandStart(q)), minute(bandEnd(p)) - minute(bandStart(p)));
      item({
        section: SECTION.link, track, row: Math.min(q._row, p._row), row2: Math.max(q._row, p._row),
        start: Math.min(qe, pf), end: Math.max(qe, pf), lod: lodOf(span),
        ref: q.uid, name: tip, color: color(q.color), a, b: idOf(p.uid), c: Math.round(k * 10), d: 0, text2: p.uid,
      });
      counts.승계선++;
    }

    /* ── 구역 22 · 소속선 ────────────────────────────────────────────────────
       상위 띠 아래에 펼쳐진 소속(singleHost)만. 같은 상국 아래 관계만 바뀌어 이어지는 구간은 선 하나로 묶는다 —
       묶는 기준이 px(1.5px 안으로 맞닿음)이라, 넣을 때는 **시각이 꼭 같은 것만** 묶는다(명세 8-1절). */
    for (const p of tr.periods) {
      if (!p.hosts || !p.hosts.length || p._folded || p._hidden || p._overlay || p._row == null || !p.singleHost || p.groupUid) continue; // 단체의 띠(조각 ④)는 소속선 없음
      const anyRel = p.hosts.some(h => h.relation);
      const joined = (x, y) => anyRel && x.host.uid === y.host.uid && (x.end ?? p.endY) === (y.start ?? p.start);
      for (let j = 0; j < p.hosts.length; j++) {
        const h = p.hosts[j];
        if (j > 0 && joined(p.hosts[j - 1], h)) continue;
        let last = h;
        const rels = [relName(HT, h)];
        for (let t = j + 1; t < p.hosts.length && joined(p.hosts[t - 1], p.hosts[t]); t++) rels.push(relName(HT, (last = p.hosts[t])));
        const host = tr.periods.find(o => o.uid === h.host.uid);
        if (!host || host._folded || host._hidden || host._row == null || host._row === p._row || hidden(p._row) || hidden(host._row)) { skipped.소속_상국없음++; continue; }
        const s = minute(h.start ?? p.start), e = minute(last.end ?? p.endY);
        if (s == null || e == null || e < s) continue;
        const rel = rels.filter(Boolean).filter((x, t, arr) => x !== arr[t - 1]).join(' → ');
        const kindName = HT.kindName(p.polityKind);
        const tip = `${p.name} — ${host.name} 소속 (${kindName}${rel && rel !== kindName ? ` · 소속 관계: ${rel}` : ''})`;
        item({
          section: SECTION.part, track, row: Math.min(p._row, host._row), row2: Math.max(p._row, host._row), start: s, end: e, lod: -1,
          ref: p.uid, name: tip, color: color(host.color),
          a: (p._row > host._row ? 1 : 0) | (refuted(p) || refuted(host) ? 2 : 0),
          b: idOf(host.uid), c: (tr.hangRowLanes && tr.hangRowLanes.get(host._row)) || 0, d: 0, text2: rel,
        });
        counts.소속선++;
      }
    }

    /* ── 구역 25 · 할거기 칠 · 구역 27 · '▸ 〈성격〉 n' 단추 ───────────────────
       상징적 본국(대범위의 host이고 s.afterHost가 아닌 것)의 띠에 대범위를 꺼 두어도 보이는 둘. */
    for (const p of tr.periods) {
      if (!drawn(p)) continue;
      const list = (tl._hosted && tl._hosted.get(p.uid)) || null;
      if (!list) continue;
      for (const s of list) {
        const a0 = Math.max(s.start, bandStart(p)), b0 = Math.min(s.endY, bandEnd(p));
        if (!(b0 > a0)) continue;
        const start = minute(a0), end = minute(b0);
        if (start == null || end == null || end < start) continue;
        item({
          section: SECTION.hollow, track, row: p._row, row2: p._row, start, end, lod: -1,
          ref: p.uid, name: s.name || '', color: color(s.color), a: 0, b: 0, c: 0, d: 0, text2: s.label || '할거',
        });
        counts.할거기칠++;
        const n = (s.members || []).filter(m => tr.periods.includes(m)).length;
        if (!n) continue;
        item({
          section: SECTION.scopeBtn, track, row: p._row, row2: p._row, start, end, lod: -1,
          ref: p.uid, name: s.label || '대범위', color: color(s.color), a: n, b: 0, c: 0, d: 0, text2: s.uid,
        });
        counts.대범위단추++;
      }
    }
  });

  /* ── 구역 49 · 동군연합 이음줄의 끝(건의 8의 6-다 · 2026-10-14) ───────────────────
     같은 사람이 같은 때 두 나라의 지도자인 짝(HT.unionPairs)마다 **끝 둘** — 두 나라가 다른 트랙일 수 있어(견본은 모두 그렇다) 끝마다 제 트랙 · 줄에 싣고
     짝은 text2의 열쇠로 잇는다. start = 겹친 기간의 **가운데**(줄을 긋는 해) · end = 가운데 + 겹친 길이 — 길이를 두어야 단계 셈(길이로 정함)이 칸처럼 잡혀
     보통 배율의 타일에도 실린다(길이 0이면 가장 고운 단계에만). 그리는 쪽은 잘리지 않은 왼쪽 끝(= 가운데)에서 줄을 긋는다. 그리는 쪽이 두 끝을 다 받고 두 지도자 칸이 다 그려지면
     두 칸을 꿰는 줄 · 고리를, 아니면(한쪽이 화면 밖 · 칸이 없음) 보이는 칸의 이름 앞에 겹고리 표지를 단다.
     a = 이 끝의 지도자 칸 순번(leader:a) · b = 짝 띠의 번호 · c = 짝의 지도자 칸 순번 · name = 풍선 글. 엔진은 뜻을 모른 채 나른다(새 칸 없음). */
  // 트랙 번호는 지금 tl.tracks의 차례(승계선 · 소속선의 tl.tracks.forEach 순번과 같게) — 판을 다시 돌릴 때(boards.mjs replay)는 tl.tracks가
  // [판 트랙, 원래 트랙 …]으로 줄어 ctx.trackIndex(전체 차례)와 다르다. 평소 · 다른 변형에서는 둘이 같다.
  const trackIndex = new Map(tl.tracks.map((t, i) => [t.id, i]));
  // 끝의 트랙은 그 나라가 지금 놓인 트랙이다(자료의 track이 아니라 — 판을 켜면 판 트랙) · 웹 _planUnions의 trackOf(tr.periods에 드는가)와 같은 규칙.
  const placedIn = new Map();
  for (const t of tl.tracks) for (const p of t.periods) placedIn.set(p, t);
  const placedIndex = p => trackIndex.get(placedIn.get(p).id) ?? 0;
  const drawable = p => {
    const tr = p && placedIn.get(p);
    return !!tr && !p._folded && !p._hidden && !p._under && !p._overlay && p._row != null && p._row >= 0 && p._row < tr.rows && !(tr.hiddenRows && tr.hiddenRows.has(p._row)) && !tr.foldedRows.has(p._row);
  };
  /* ── 구역 52 · 옮겨 앉기의 끝(리메이크 2부 · 결정 #3 A) ───────────────────
     다리(core.js splitMoves — HT.F4.split)가 나눈 토막('<원 id>.mv<경계 해>')의 짝(앞 → 뒤)마다 끝 둘(구역 49와 같은 꼴): row = 그 토막의 줄 · ref = 그 토막 ·
     start = 옮긴 해 · end = 옮긴 해 + 두 토막 가운데 짧은 길이(단계 셈) · a = 0 앞 끝 / 1 뒤 끝 · b = 짝 토막의 번호 · name = 풍선 글 · text2 = 짝 열쇠(뒤 토막 uid).
     그리는 쪽(paint/links.dart _planMoves)이 앞 토막 아랫변(뒤가 위 줄이면 윗변)의 매듭에서 곧게 내려 뒤 토막 구멍으로 점선 실을 긋는다. 엔진은 뜻을 모른 채 나른다. */
  {
    const cutOf = p => {
      const m = /^(.*)\.mv(-?\d+(?:\.\d+)?)$/.exec(String(p.id ?? ''));
      return m ? { base: m[1], at: Number(m[2]) } : null;
    };
    for (const p of ctx.model.periods || []) {
      const cut = cutOf(p);
      if (!cut) continue;
      const q = (ctx.model.periods || []).find(x => x !== p && x.packId === p.packId && x.track === p.track && (x.id === cut.base || String(x.id ?? '').startsWith(cut.base + '.mv')) && x.endY != null && Math.abs(x.endY - cut.at) < 1e-9);
      if (!q || !drawable(q) || !drawable(p)) continue;
      const at = minute(cut.at), len = Math.min(q.endY - q.start, (p.endY ?? cut.at) - cut.at);
      const until = minute(cut.at + Math.max(len, 1e-3));
      if (at == null || until == null) continue;
      const tip = `${p.name || ''} — 옮겨 앉음 · ${HT.formatYear(cut.at)}`;
      for (const [me, other, a] of [[q, p, 0], [p, q, 1]]) {
        item({
          section: SECTION.move, track: placedIndex(me), row: me._row, row2: me._row, start: at, end: at + Math.max(1, until - at), lod: -1,
          ref: me.uid, name: tip, color: color(me.color), a, b: idOf(other.uid), c: 0, d: 0, text2: p.uid,
        });
      }
      counts.옮겨앉기끝 = (counts.옮겨앉기끝 || 0) + 2;
    }
  }
  for (const u of HT.unionPairs ? HT.unionPairs(ctx.model) : []) {
    if (!drawable(u.a.p) || !drawable(u.b.p)) continue;
    const at = minute(u.mid), s0 = minute(u.s), e0 = minute(u.e);
    if (at == null || s0 == null || e0 == null) continue;
    const tip = `동군연합 · ${u.name} — ${u.a.p.name} · ${u.b.p.name} · ${HT.formatYear(u.s)} ~ ${HT.formatYear(u.e)}`;
    for (const [me, other] of [[u.a, u.b], [u.b, u.a]]) {
      item({
        section: SECTION.union, track: placedIndex(me.p), row: me.p._row, row2: me.p._row, start: at, end: at + Math.max(1, e0 - s0), lod: -1,
        ref: me.p.uid, name: tip, color: 0, a: me.i, b: idOf(other.p.uid), c: other.i, d: 0, text2: u.key,
      });
      counts.동군연합끝++;
    }
  }

  ctx.notes.관계선 = counts;
  ctx.notes.관계선에서_뺀_것 = skipped;
}

/** 소속 한 구간의 관계 이름(지금 연표의 depRel) */
function relName(HT, h) {
  const info = h && h.relation && HT.relationInfo ? HT.relationInfo(h.relation) : null;
  return (info && info.name) || '';
}

/** 대범위 부흥선으로 묶이는 승계 한 건들(_scopeBranches의 tr._bundled) — 대범위를 켰을 때만 실제로 묶이지만,
    자료로는 '본국이 끝난 뒤 생긴 대범위(afterHost)의 구성 정권이 본국을 부흥으로 가리키는 것'으로 정해진다. */
function bundledEdges(tl, tr) {
  const set = new Set();
  for (const s of (tl._data && tl._data.scopes) || []) {
    if (!s.afterHost || !s.host) continue;
    for (const m of s.members || []) {
      if (!m || m.track !== tr.id) continue;
      for (const e of m.predecessors || []) if (e.type === 'revival' && e.from === s.host) set.add(e);
    }
  }
  return set;
}

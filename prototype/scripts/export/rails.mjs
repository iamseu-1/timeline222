// 기간 사건의 그림 — 기간 막대 · 연대 폭 · 이설 · 조약 발효 눈금(계약 4절의 items · 6절의 구역 33~36).
// 지금 연표는 이것들을 글줄 아래 '기간 레일'에 그린다(js/timeline.js의 _drawTrack 7065~7125줄 · 상수는 G.railPitch 7).
// 단(lvl)은 화면이 아니라 자료(해)로만 정한다 — 확대해도 같은 단이다. 규칙과 비트의 뜻은 계약 6절.
import { minute, color as rgb } from './base.mjs';

/** 내가 쓰는 일반 구역 번호(32~47 가운데). 32는 events.mjs(하위 사건)가 쓴다. */
export const SECTION = { rail: 33, fuzz: 34, alt: 35, effect: 36 };

/** 단계 · 통 산수. engine/src/levels.rs의 lod_of와 같은 식이다: 기간이 통 너비(4^L분)의 1/8 이상인 가장 성긴 단계. */
export function lodOf(duration) {
  const wide = Math.max(0, duration) * 8;
  for (let level = 14; level >= 0; level--) if (wide >= 4 ** level) return level;
  return 0;
}

/** 사건의 색 — 그려지는 자리(placements)의 정권 색이 먼저(_drawTrack과 같다). */
export const eventColor = e => (e._place && e._place.polityColor) || e.polityColor || e.color || '#a4b1b7';

/** 한 사건의 열쇠(공동 사건의 둘째 자리부터는 #1 · #2 … — events.mjs의 uid와 같다). */
export const eventUid = e => e.uid + (e._pi ? `#${e._pi}` : '');

/** 이 사건이 기간 막대 칸을 쓰는가. 화면은 폭(픽셀)으로 따지지만(ranged || fuzzy || alts) 자료로는 같은 것을 해로 따진다(_layoutTrack의 railLevels 셈과 같다). */
export const onRail = (HT, e) => e.endY > e.start || !!e.startRange || !!e.endRange || HT.datedAlts(e).length > 0;

/** 사건이 기간 막대 칸에서 차지하는 해 범위 [lo, hi] — 통설 · 연대 폭 · 이설을 모두 품는다(_layoutTrack의 segs와 같다). */
export function railSpan(HT, e) {
  const ys = [e.start, e.endY];
  if (e.startRange) ys.push(...e.startRange);
  if (e.endRange) ys.push(...e.endRange);
  for (const a of HT.datedAlts(e)) ys.push(a.start, a.end ?? a.start);
  return [Math.min(...ys), Math.max(...ys)];
}

/** 사건의 열쇠 → 기간 막대의 단. 줄마다 빈 단을 찾고(없으면 가장 적게 겹치는 단 — 화면의 pickLevel과 같은 규칙), 단 수는 그 트랙의 railLevels.
    함께 **그 줄에서 단을 고르는 차례**(`ctx.shared.railRank`)도 적어 둔다 — 화면은 배율마다 단을 다시 고르는데(js/timeline.js의 pickLevel),
    그때 이 차례대로 돌려야 지금 연표와 같은 단이 나온다(중요한 것 먼저 · 같으면 이른 것 먼저). 화면 쪽은 `d`의 8비트 위에서 이 차례를 읽는다. */
export function railLevels(ctx) {
  if (ctx.shared.railLevel) return ctx.shared.railLevel;
  const { tl, HT } = ctx;
  const map = new Map();
  const rank = new Map();
  for (const tr of tl.tracks) {
    const max = Math.max(1, Math.min(3, tr.geo.railLevels || 2));
    for (const list of tr.eventsByRow || []) {
      const levels = Array.from({ length: max }, () => []);
      const order = list
        .filter(e => onRail(HT, e))
        .map(e => ({ e, span: railSpan(HT, e) }))
        // 화면이 사건을 놓는 차례와 같게: 중요한 것 먼저 · 같으면 이른 것 먼저(_placeRow의 order — 고름 · 강조는 그때그때라 빼고).
        .sort((a, b) => (b.e.importance || 2) - (a.e.importance || 2) || a.e.start - b.e.start || (a.e.uid < b.e.uid ? -1 : 1));
      order.forEach(({ e }, i) => rank.set(eventUid(e), i));
      for (const { e, span } of order) {
        const [l, r] = span;
        let lvl = levels.findIndex(used => !used.some(([a, b]) => a < r && l < b));
        if (lvl < 0) {
          let best = Infinity;
          levels.forEach((used, i) => {
            const over = used.reduce((s, [a, b]) => s + Math.max(0, Math.min(b, r) - Math.max(a, l)), 0);
            if (over < best) { best = over; lvl = i; }
          });
        }
        levels[lvl].push([l, r]);
        map.set(eventUid(e), lvl);
      }
    }
  }
  ctx.shared.railLevel = map;
  ctx.shared.railRank = rank;
  return map;
}

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const levels = railLevels(ctx);
  const ranks = ctx.shared.railRank;
  const count = { 기간막대: 0, 연대폭: 0, 이설: 0, 발효: 0, 짧은막대: 0 };
  const DAY = 1440;
  tl.tracks.forEach((tr, track) => {
    for (const e of tr.events) {
      if (!onRail(HT, e) || e._row === null) continue; // 줄 null = 선반 변형이 숨긴 띠의 사건(events.mjs와 같음 — 싣지 않음)
      const row = e._row == null || e._row < 0 ? tr.commonRow : e._row;
      if (row == null || row < 0 || row >= tr.rows) continue;
      const uid = eventUid(e);
      const lvl = levels.get(uid) ?? 0;
      const color = rgb(eventColor(e));
      const alts = HT.datedAlts(e);
      // 이 사건의 그림이 통틀어 차지하는 폭 — 곁들임(빗금 · 이설 세로바 · 발효 눈금)은 막대와 같은 단계까지 실린다.
      const [lo, hi] = railSpan(HT, e);
      const whole = Math.max(0, minute(hi) - minute(lo));
      const near = lodOf(whole);
      // 화면이 단을 다시 고를 때 쓰는 값(계약 6-7): b의 5~6비트 = 중요도 · d의 8비트 위 = 그 줄에서의 차례 + 1.
      const impBits = Math.min(3, Math.max(1, e.importance || 2)) << 5;
      const rankBits = ((ranks.get(uid) ?? 0) + 1) << 8;
      const base = { section: 0, track, row, row2: row, start: 0, end: 0, lod: near, ref: uid, name: '', color, a: lvl, b: impBits, c: 0, d: rankBits, text2: '' };

      // 구역 33 · 기간 막대: 가는 선 + 양 끝 세로바. 기간이 아무리 짧아도 모두 싣는다(화면은 최소 3px으로 그린다).
      if (e.endY > e.start) {
        const start = minute(e.start), end = Math.max(start, minute(e.endY));
        if (end - start < 45.5 * DAY) count.짧은막대++;
        out.items.push(Object.assign({}, base, {
          section: SECTION.rail, start, end, lod: -1, name: e.title || '',
          b: impBits | (e._sec ? 1 : 0) | (e.treaty ? 2 : 0) | (e.startRange ? 4 : 0) | (e.endRange ? 8 : 0) | (alts.length ? 16 : 0),
          c: (e.startUnknown ? 1 : 0) | (e.endUnknown ? 2 : 0),
          d: rankBits | Math.min(255, alts.length),
        }));
        count.기간막대++;
      }

      // 구역 34 · 연대 폭: 기간 사건이면 빗금 구간, 끝 연도 없는 점 사건이면 점선 실의 양 끝 눈금.
      [e.startRange, e.endRange].forEach((range, j) => {
        if (!range) return;
        const start = minute(range[0]), end = Math.max(start, minute(range[1]));
        out.items.push(Object.assign({}, base, { section: SECTION.fuzz, start, end, b: impBits | j, c: e.endY > e.start ? 1 : 0 }));
        count.연대폭++;
      });

      // 구역 35 · 이설: 점선 세로바(시작) + 통설과 이어 주는 점선. 끝이 통설과 다른 이설은 끝에도 같은 세로바.
      alts.forEach((a, j) => {
        const endY = a.end != null && isFinite(a.end) ? a.end : a.start;
        const start = minute(a.start), end = Math.max(start, minute(endY));
        const differs = a.end != null && isFinite(a.end) && !a.ongoing && Math.abs(a.end - (e.end ?? e.endY)) > 1e-9;
        out.items.push(Object.assign({}, base, {
          section: SECTION.alt, start, end, name: a.label || '',
          b: impBits | (a.end != null && isFinite(a.end) ? 1 : 0) | (differs ? 2 : 0) | (a.ongoing ? 4 : 0) | (e.endY > e.start ? 8 : 0),
          c: j,
        }));
        count.이설++;
      });

      // 구역 36 · 조약의 발효 눈금: x0 = 눈금 자리 · x1 = 기간 막대의 끝(단계 셈에만 — 막대와 함께 실리게).
      const eff = e.treaty && e.treaty.effective;
      if (eff != null && isFinite(eff) && Math.abs(eff - e.start) > 1e-6) {
        const at = minute(eff);
        out.items.push(Object.assign({}, base, { section: SECTION.effect, start: Math.min(at, minute(e.endY)), end: Math.max(at, minute(e.endY)), b: impBits | (at <= minute(e.endY) ? 0 : 1), c: 0 }));
        count.발효++;
      }
    }
  });
  ctx.notes.기간막대 = count;
}

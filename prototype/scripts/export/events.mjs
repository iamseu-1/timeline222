// 사건. 2단계의 값에서 출발한다 — 분류 · 모양 · 확실성 · 글줄 · 이름 옆 날짜 글 · 기간 막대의 단(계약 4 · 6절의 look · label · rail)은 이 모듈이 더한다.
// 읽은 곳: js/timeline.js의 _drawTrack(사건 부분) · _placeRow(3409줄) · _labelDate(3735줄) · _pointAt · _extent · _precSpan, 모양은 css/common.css의 .tl-ev.
import { assert } from './base.mjs'; // 노드에서는 node:assert/strict 그대로(브라우저 겸용 — base.mjs 머리말)
import { minute, color as rgb } from './base.mjs';
import { railLevels, onRail, eventColor, eventUid } from './rails.mjs';

/** look의 비트 자리 (계약 6절의 표와 같다). */
const LOOK = { cat: 0, lane: 8, treaty: 16, shared: 17, pair: 18, child: 19, estimated: 20, legend: 21, unknown: 22, fuzzy: 23, kids: 24 };
/** rail의 비트 자리. */
const RAIL = { level: 0, ranged: 2, fuzzS: 3, fuzzE: 4, alt: 5, altEnd: 6, effect: 7, prec: 8 };
/** 날짜 정밀도 — 적은 만큼만(연도만 적은 사건에 없는 날짜를 지어내지 않는다). */
const PREC = { y: 0, m: 1, d: 2, x: 2, h: 3, min: 4, c: 5, c2: 6, c3: 7 }; // c · c2 · c3 = 세기 · 반세기 · 세기의 셋째(묶음 5 · 6번) — rail 8~10비트(3비트) 안
/** 하위 사건이 펼쳐지는 문턱(_drawTrack): 부모의 폭 90px 이상 · 한 번 펼쳐지면 8% 더 좁아져야 다시 접힌다. */
const WIDE = 90;
const WIDE_GAP = 80; // 0.08을 천분율로

/** 사건의 분류 번호 = out.categories의 순번. 앞선 모듈(tracks.mjs)이 채워 둔 ctx.shared.catNo를 그대로 쓰고, 없으면 지금 연표의 분류 차례로 채운다. */
function catIndex(ctx, out) {
  if (ctx.shared.catNo) return ctx.shared.catNo;
  if (!out.categories.length) for (const [id, c] of [...ctx.tl._cats.entries()].sort((a, b) => a[1].i - b[1].i)) out.categories.push({ key: id, name: c.name || id, color: rgb(c.color) });
  ctx.shared.catNo = new Map(out.categories.map((c, i) => [c.key, i]));
  return ctx.shared.catNo;
}

/** 이름 옆 날짜 글 — _labelDate를 화면 없이 그대로: 적은 정밀도만큼의 온 글(해 눈금 · 같은 해 보기에서 줄이는 것은 그리는 쪽이 한다. 계약 6절). */
function labelOf(HT, e) {
  const at = HT.atOf(e, 'start');
  const r = at && HT.cal ? HT.cal.parse(at) : null;
  if (!r || !r.ok || r.prec === 'y') return { text: HT.formatYear(e.start), prec: PREC.y };
  if (r.span) return { text: r.text, prec: PREC[r.prec] ?? PREC.c }; // 세기로 적은 연대는 적은 글 그대로
  const prec = r.prec === 'm' ? 'm' : r.prec === 'd' ? 'd' : r.prec;
  return { text: HT.cal.formatT(r.t, prec), prec: PREC[prec] ?? PREC.d };
}

export function contribute(ctx, out) {
  const periodByUid = new Map(ctx.model.periods.map(p => [p.uid, p]));
  const bandUidOf = e => {
    const uid = e._place ? e._place.polityUid : e.polityUid;
    let p = uid != null ? periodByUid.get(uid) : null;
    while (p && p._hidden) p = p._host;
    return p && ctx.shared.bandOf && ctx.shared.bandOf.has(p.uid) ? p.uid : '';
  };
  const { tl, model, HT } = ctx;
  const cats = catIndex(ctx, out);
  const levels = railLevels(ctx);
  const count = { 묶음사건: 0, 하위사건: 0, 자유배치: 0, 분류별글줄: 0 };
  tl.tracks.forEach((tr, trackIndex) => {
    for (const e of tr.events) {
      const row = e._row == null || e._row < 0 ? tr.commonRow : e._row;
      assert.ok(row >= 0 && row < tr.rows, `사건의 줄이 없습니다: ${e.title}`);
      // 날짜를 정확히 모르는 점 사건은 그 구간 가운데(또는 사건의 자리 spot)에 하나로 선다 — 연표의 _placeAt과 같은 해를 시작 분으로 싣는다
      // (2026-10-14 감독 결정 · 날짜 글과 정밀도는 label · rail이 따로 나르고, 놓인 자리는 늘 그 구간 안이라 같은 해 보기 · 칸의 목록은 그대로).
      const place = (e.endY ?? e.start) > e.start ? e.start : tl._placeAt(e);
      const start = minute(place), end = minute(e.endY ?? e.start);
      const uid = eventUid(e);
      const cert = e.certainty || 'accepted';
      const fuzzy = !!(e.startRange || e.endRange); // 연대 폭이 있으면 화면이 확실성 딱지를 끄고 빗금 구간으로 말한다
      const rowCats = (tr.rowCats && tr.rowCats[row]) || null;
      const lane = rowCats ? rowCats.indexOf(e.category || 'etc') : -1;
      if (rowCats) count[lane >= 0 ? '분류별글줄' : '자유배치']++;
      const kids = e.children && e.children.length ? e.children.length : 0;
      const label = labelOf(HT, e);
      const alts = HT.datedAlts(e);
      const altEnd = alts.some(a => a.end != null && isFinite(a.end) && !a.ongoing && Math.abs(a.end - (e.end ?? e.endY)) > 1e-9);
      const eff = e.treaty && e.treaty.effective;

      const look =
        ((cats.has(e.category || 'etc') ? cats.get(e.category || 'etc') : 255) << LOOK.cat) |
        ((lane >= 0 && lane < 255 ? lane : 255) << LOOK.lane) |
        ((e.treaty ? 1 : 0) << LOOK.treaty) |
        ((e.shared ? 1 : 0) << LOOK.shared) |
        ((e._sec ? 1 : 0) << LOOK.pair) |
        ((e.parentUid ? 1 : 0) << LOOK.child) |
        ((!fuzzy && cert === 'estimated' ? 1 : 0) << LOOK.estimated) |
        ((!fuzzy && cert === 'legend' ? 1 : 0) << LOOK.legend) |
        ((e.startUnknown || e.endUnknown ? 1 : 0) << LOOK.unknown) |
        ((fuzzy ? 1 : 0) << LOOK.fuzzy) |
        (Math.min(255, kids) << LOOK.kids);
      const rail =
        ((levels.get(uid) ?? 0) << RAIL.level) |
        ((onRail(HT, e) ? 1 : 0) << RAIL.ranged) |
        ((e.startRange ? 1 : 0) << RAIL.fuzzS) |
        ((e.endRange ? 1 : 0) << RAIL.fuzzE) |
        ((alts.length ? 1 : 0) << RAIL.alt) |
        ((altEnd ? 1 : 0) << RAIL.altEnd) |
        ((eff != null && isFinite(eff) && Math.abs(eff - e.start) > 1e-6 ? 1 : 0) << RAIL.effect) |
        (label.prec << RAIL.prec);

      out.events.push({
        uid, track: trackIndex, row, start, end: start == null ? null : Math.max(end ?? start, start),
        importance: Math.min(3, Math.max(1, e.importance || 1)), title: e.title ?? e.name ?? '', body: e.description ?? '',
        look: look >>> 0, label: label.text, rail: rail >>> 0,
        // 사건이 든 띠(정권)의 uid — 점의 색(정권 색) · 점과 이름을 띠 안에 가두기 · '묶음은 같은 띠 안에서만'에 쓴다. 띠가 없으면(그 밖 줄) ''.
        band: bandUidOf(e),
      });

      // 구역 32 · 하위 사건: 평소에는 숨고 부모가 화면에서 넓어지면 펼쳐진다. 자리(start · end)는 **부모의 기간**이라
      // 그리는 쪽이 x1 − x0 ≥ 90px인지만 보면 되고, 단계(lod −1)도 부모의 기간에서 셈해 부모가 가늘 때는 실리지 않는다.
      if (e.parentUid) {
        const parent = tr.eventByUid.get(e.parentUid) || (model.events || []).find(q => q.uid === e.parentUid);
        if (parent) {
          const ps = minute(parent.start), pe = Math.max(ps, minute(parent.endY ?? parent.start));
          out.items.push({
            section: 32, track: trackIndex, row, row2: row, start: ps, end: pe, lod: -1,
            ref: uid, name: parent.uid, color: rgb(eventColor(parent)),
            a: Math.min(255, (parent.children || []).length), b: WIDE, c: WIDE_GAP, d: 0, text2: parent.title || '',
          });
          count.하위사건++;
        }
      }
      if (kids) count.묶음사건++;
    }
  });
  assert.equal(out.events.filter(e => !e.uid.includes('#')).length, model.events.length, '사건 수가 모델과 다릅니다');
  ctx.notes.사건 = count;
}

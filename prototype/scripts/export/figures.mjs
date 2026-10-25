// 인물의 활동 막대(계약 4절의 items · 6절의 구역 37 · 38).
// 읽은 곳: js/timeline.js의 _layoutTrack 3-1)과 단 배정(2862~2898줄) · _figureGroups(6358줄) · _figureBars(6403줄) · _figSpan · _figUnk.
// 줄(row)과 단(lvl)은 이미 자료로 정해져 있다(_layoutTrack이 tr.figures에 적어 둔 것) — 화면은 그대로 쓰기만 한다.
import { minute, color as rgb } from './base.mjs';
import { lodOf } from './rails.mjs';

export const SECTION = { bar: 37, group: 38, alt: 39 };

/** 띠가 그려지는 해 범위 — 연대 폭이 있으면 그 바깥 끝까지(timeline.js의 bandStart · bandEnd). */
const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);

/** 활동 막대의 양 끝이 미정인지 — 막대의 그 끝이 섬긴 구간의 진짜 끝일 때만(띠의 기간에서 잘린 끝은 미정이 아니다. _figUnk와 같다). */
function unknownEnds(s, host) {
  return {
    start: !!s.fromUnknown && Math.abs(Math.max(s.start, bandStart(host)) - s.from) < 1e-9,
    end: !!s.toUnknown && Math.abs(Math.min(s.endY, bandEnd(host)) - s.to) < 1e-9,
  };
}

/** 인물의 생몰 · 활동 시기(js/timeline.js의 figBaseOf). 앞뒤가 뒤집힌 이설을 가리는 데 쓴다. */
const figBase = f => ({ birth: f.birth, birthAt: f.birthAt, death: f.death, deathAt: f.deathAt, start: f.start, startAt: f.startAt, end: f.endY, endAt: f.endYAt, ongoing: f.ongoing, startUnknown: f.startUnknown, endUnknown: f.endUnknown });
const FIG_KEYS = ['start', 'end', 'birth', 'death'];

/** 활동 막대 하나가 품는 이설(js/timeline.js의 figBarCell): 섬긴 기록 줄의 이설에, 이 막대의 끝이 곧 활동의 끝일 때만 인물의 활동 시작 · 끝 이설을 더한다. */
function barAlternatives(HT, f, s) {
  const list = ((s && s.alternatives) || []).slice();
  const atS = Math.abs(s.from - f.start) < 1e-9;
  const atE = Math.abs(s.to - f.endY) < 1e-9;
  for (const a of f.alternatives || []) {
    if (HT.altFlipped(a, figBase(f), FIG_KEYS)) continue;
    const o = {};
    if (atS && a.start != null) Object.assign(o, { start: a.start, startAt: a.startAt });
    if (atE && a.ongoing === true) o.ongoing = true;
    else if (atE && a.end != null) Object.assign(o, { end: a.end, endAt: a.endAt });
    if (Object.keys(o).length) list.push(Object.assign(o, { label: a.label }));
  }
  return list;
}

/** 이설이 말하는 경계 해 [{ y, side }] — js/timeline.js의 altEdges 그대로(통설과 같은 해 · 뒤집힌 이설은 뺀다). 칸 쪽(strips.mjs)과 같은 식이다. */
function altEdges(HT, list, base, now) {
  const out = [];
  const push = (y, side) => {
    if (y == null || !isFinite(y) || out.some(q => Math.abs(q.y - y) < 1e-9)) return;
    out.push({ y, side });
  };
  for (const a of list) {
    if (!HT.altDated(a) || HT.altFlipped(a, base)) continue;
    const f = HT.altSpan(a, base);
    if (f.own.start && f.start != null && base.start != null && Math.abs(f.start - base.start) > 1e-9) push(f.start, 's');
    const e = f.ongoing ? now : f.end;
    if (f.own.end && e != null && base.end != null && Math.abs(e - base.end) > 1e-9) push(e, 'e');
  }
  return out;
}

/** 인물의 생몰 이설이 말하는 해(수명선 위의 작은 빈 고리 `.lnalt`) — 앞뒤가 뒤집힌 이설과 실제 생몰과 같은 해는 뺀다. */
function lifeEdges(HT, f) {
  const out = [];
  for (const a of f.alternatives || []) {
    if (HT.altFlipped(a, figBase(f), FIG_KEYS)) continue;
    for (const y of [a.birth, a.death]) {
      if (y == null || !isFinite(y) || y === f.birth || y === f.death || out.includes(y)) continue;
      out.push(y);
    }
  }
  return out;
}

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const bandOf = ctx.shared.bandOf || new Map();
  const count = { 막대: 0, 묶음: 0, 넘친인물: 0, 생몰있음: 0, 이설경계: 0, 생몰이설: 0 };
  tl.tracks.forEach((tr, track) => {
    const groups = new Map(); // 띠 uid → 그 띠에 그려지는 막대들
    for (const x of tr.figures || []) {
      if (x.lvl < 0 || x.row == null || !x.band) { count.넘친인물++; continue; }
      if (tr.hiddenRows && tr.hiddenRows.has(x.row)) { count.넘친인물++; continue; }
      const { f, s, band } = x;
      const start = minute(s.start), end = Math.max(start, minute(s.endY));
      if (start == null) continue;
      // 1년이 안 되는 활동도 화면에서는 적어도 3px으로 그린다 — 그 1년의 폭으로 단계를 매겨 성긴 단계에서 사라지지 않게(_figSpan).
      const [s0, s1] = s.endY - s.start >= 1 ? [s.start, s.endY] : [(s.start + s.endY) / 2 - 0.5, (s.start + s.endY) / 2 + 0.5];
      const lod = lodOf(Math.max(0, minute(s1) - minute(s0)));
      const unk = unknownEnds(s, band);
      const alts = (f.alternatives || []).length + (s.alternatives || []).length;
      const life = f.birth != null || f.death != null ? `${f.birth != null ? minute(f.birth) : ''}|${f.death != null ? minute(f.death) : ''}` : '|';
      if (f.birth != null || f.death != null) count.생몰있음++;
      out.items.push({
        section: SECTION.bar, track, row: x.row, row2: x.row, start, end, lod,
        ref: band.uid, name: f.name || '', color: rgb(s.color || band.color),
        a: x.lvl,
        b: Math.min(3, Math.max(1, f.importance || 2)) | (unk.start ? 4 : 0) | (unk.end ? 8 : 0) | (alts ? 16 : 0) | (f.houseId ? 32 : 0),
        c: x.i || 0,
        d: 0,
        // 가문 강조(emphasis.look.house)가 견줄 값이라 가문의 id를 넷째 칸에 싣는다(계약 6-7 · 가문이 없으면 빈칸).
        text2: `${f.uid}|${life}|${f.houseId || ''}`,
      });
      count.막대++;

      // 구역 39 · 활동 기록의 이설: 유령 구분선(막대 안)과 생몰 이설의 빈 고리(수명선 위). start가 표식의 자리이고 end는 막대의 끝이다(단계 셈과 타일 고르기에만).
      const seed = { section: SECTION.alt, track, row: x.row, row2: x.row, start, end, lod, ref: band.uid, name: '', color: rgb(s.color || band.color), a: x.lvl, b: 0, c: x.i || 0, d: 0, text2: f.uid };
      const base = { start: s.from, startAt: s.fromAt, end: s.to, endAt: s.toAt, startUnknown: s.fromUnknown, endUnknown: s.toUnknown };
      for (const m of altEdges(HT, barAlternatives(HT, f, s), base, f.endY)) {
        const at = minute(m.y);
        if (at == null || !isFinite(at)) continue;
        out.items.push(Object.assign({}, seed, { start: at, end: Math.max(at, end), b: m.side === 'e' ? 1 : 0 }));
        count.이설경계++;
      }
      for (const y of lifeEdges(HT, f)) {
        const at = minute(y);
        if (at == null || !isFinite(at)) continue;
        out.items.push(Object.assign({}, seed, { start: at, end: Math.max(at, end), b: 4 }));
        count.생몰이설++;
      }
      if (!groups.has(band.uid)) groups.set(band.uid, { band, row: x.row, n: 0 });
      groups.get(band.uid).n++;
    }
    // 구역 38 · 인물 단 묶음: 막대가 빽빽하면(보이는 막대의 평균 폭 6px 미만) 단 전체를 '인물 n명' 한 칸으로 바꾼다.
    for (const { band, row, n } of groups.values()) {
      const start = minute(bandStart(band)), end = Math.max(start, minute(bandEnd(band)));
      out.items.push({
        section: SECTION.group, track, row, row2: row, start, end, lod: -1,
        ref: bandOf.has(band.uid) ? band.uid : '', name: band.name || '', color: rgb(band.color),
        a: n, b: 6, c: 80, d: 0, text2: band.uid,
      });
      count.묶음++;
    }
  });
  ctx.notes.인물 = count;
}

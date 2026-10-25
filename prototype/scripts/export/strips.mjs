// 띠 안의 모든 단의 칸: 왕조 · 지도자 · 내각 · 기관 · 시기 구분 · 지위 · 예속(안).
// 단의 종류 번호와 lane · style · color의 뜻은 계약 6절. 화면에 달린 값(잘림 · 조명 · 이름이 몇 글자나 드는가)은 싣지 않는다.
// 칸에 딸린 것(모호한 구간 · 이설 경계 · 가문)은 일반 항목 구역 40~42로 나간다(계약 6-2 끝).
// 칸의 정통성(지도자 · 내각 · 직위 줄 더의 칸 status)은 구역 57로 나간다(4단계 배치 갈래 · 계약 1-1 덧붙임 — 소속 구간의 것은 bands.mjs의 구역 58).
// 지도자 칸의 lane은 그 칸의 단이다(4단계 배치 갈래 둘째 · 계약 1-1 덧붙임 — 공동 · 주장 칸이 겹친 띠만 · js/timeline.js의 _leaderLanes · 그 밖은 0 그대로).
import { minute, color } from './base.mjs';
import { statusNoOf } from './bands.mjs';

/** 단의 종류(계약 5절의 '단의 종류' 그대로) — 6 인물은 figures.mjs의 몫 */
const STRIP = { dynasty: 0, leader: 1, cabinet: 2, organ: 3, phase: 4, rank: 5, dep: 7 };
/** 칸의 모습(계약 6절) */
const ST = { unkS: 1, unkE: 2, joinL: 4, estimated: 8, legend: 16, tagged: 32, range: 64, alt: 128 };
const ST_RANK = 8; // 0x700 — 지위 서열 단계 + 1
const ST_DEP = 11; // 0x3800 — 예속 이름표 모양 + 1
const DEP_LOOK = { held: 1, owned: 2, occupied: 3 };

/** 내가 쓰는 일반 항목 구역(40~43 · 계약 6-2 끝 · 54 · 55 — 리메이크 3단계 계약 1-1 초안 · 57 칸의 정통성 — 4단계 배치 갈래 · 계약 1-1 덧붙임) */
export const SECTION = { zone: 40, alt: 41, house: 42, item: 43, leaderName: 46, borrow: 54, officeName: 55, legit: 57 };
/** 리메이크 3단계(계약 1-1 초안): 직위 줄 더(셋째 직위 줄부터)의 칸 종류 9 · 빌린 직위 줄의 칸 style 27비트(종류 1 · 2 · 9에서만 — 종류 8의 27~29는 단 갈래) */
export const KIND_OFFICE = 9;
export const ST_BORROW = 1 << 27;

/** 빌림의 출처 "객체 id" · "객체 id/직위 이름"(형식 4 더하기 — offices[].from) → { src(모델 정권 · 못 찾으면 null), office, text("출처 이름/직위") }.
    같은 DLC의 id → 이름 → 온 uid 차례(HT.f4Preview의 fromText와 같은 뜻 — 첫 / 앞이 객체). */
const fromOf = (model, p, ref) => {
  const s = String(ref ?? '').trim();
  const whole = model.byUid && model.byUid.get(s);
  const cut = whole ? -1 : s.indexOf('/');
  const key = cut >= 0 ? s.slice(0, cut).trim() : s;
  const office = cut >= 0 ? s.slice(cut + 1).trim() : '';
  const src = whole || model.periods.find(q => q.packId === p.packId && q.id === key) || model.periods.find(q => q.packId === p.packId && q.name === key) || null;
  return { src, office, text: `${src ? src.name : key}${office ? `/${office}` : ''}` };
};
/** 출처의 직위 줄 칸 — 이름이 비거나 지도자면 지도자 칸, 내각이면 내각 칸, 그 밖은 출처의 직위 줄 더에서 같은 이름 */
const officeCells = (src, office) => {
  if (!src) return [];
  if (!office || office === '지도자') return src.leaders || [];
  if (office === '내각') return src.cabinets || [];
  const f = (src.offices || []).find(o => o && o.name === office);
  return (f && f.cells) || [];
};

/** style에 함께 싣는 값(계약 6-2): 비트 14 번갈아 짙기(is-alt) · 15~26 그 목록에서의 순번 + 1(0 없음 · 4095 넘침).
    lane은 타일의 정렬 열쇠(row, kind, lane, start, id)라 단 번호만 담는다 — 다른 값을 얹으면 같은 단의 칸이 흩어진다. */
const styleWith = (style, alt, seq) => style | (alt ? 1 << 14 : 0) | ((seq == null || seq < 0 ? 0 : Math.min(4095, seq + 1)) << 15);

/** 단계 · 통 산수(engine/src/levels.rs의 lod_of와 같은 식) — 칸에 딸린 항목은 그 칸과 같은 단계까지 실린다. */
const lodOf = duration => {
  const wide = Math.max(0, duration) * 8;
  for (let level = 14; level >= 0; level--) if (wide >= 4 ** level) return level;
  return 0;
};

/** 칸 하나의 style 가운데 칸 자료에서 곧바로 나오는 몫 */
const cellStyle = c => {
  const cert = c && c.certainty;
  return (c && c.startUnknown ? ST.unkS : 0) | (c && (c.endUnknown || c.endYAuto) ? ST.unkE : 0) |
    (cert === 'estimated' ? ST.estimated : cert === 'legend' ? ST.legend : 0) |
    (c && (c.startRange || c.endRange) ? ST.range : 0) |
    (c && c.alternatives && c.alternatives.length ? ST.alt : 0);
};

/** 칸의 통설 구간 — 유령 구분선이 견주는 값(js/timeline.js의 cellBaseOf와 같은 식) */
const cellBaseOf = (HT, c, p, ref) => {
  if (!(c && c.alternatives && c.alternatives.length)) return null;
  const sp = HT.cellSpan(c, p, ref);
  return { start: sp.start, startAt: c.startAt, end: sp.end, endAt: sp.endAt, startUnknown: c.startUnknown, endUnknown: !!(c.endUnknown || (c.end == null && c.endYAuto)), ongoing: HT.cellToNow(c, p) };
};

/** 왕조 칸의 이설 — 다스린 구간의 것에 왕조 항목 자신의 이설을 더한다(js/timeline.js의 dynCellOf와 같은 식) */
const dynCellOf = (HT, d, y) => {
  const alts = HT.datedAlts(y);
  if (!alts.length) return d;
  const atS = Math.abs(d.start - y.start) < 1e-9;
  const atE = !y.ongoing && Math.abs(d.end - y.endY) < 1e-9;
  if (!atS && !atE) return d;
  const list = ((d && d.alternatives) || []).slice();
  for (const a of alts) {
    const o = {};
    if (atS) Object.assign(o, { start: a.start, startAt: a.startAt });
    if (atE && a.end != null) Object.assign(o, { end: a.end, endAt: a.endAt });
    if (o.start != null || o.end != null) list.push(Object.assign(o, { label: a.label }));
  }
  return Object.assign({}, d, { alternatives: list });
};

/** 이설이 말하는 경계 해 [{ y, side }] — js/timeline.js의 altEdges 그대로(통설과 같은 해 · 뒤집힌 이설은 뺀다) */
const altEdges = (HT, c, base, now) => {
  const out = [];
  const push = (y, side) => {
    if (y == null || !isFinite(y) || out.some(q => Math.abs(q.y - y) < 1e-9)) return;
    out.push({ y, side });
  };
  for (const a of (c && c.alternatives) || []) {
    if (!HT.altDated(a) || HT.altFlipped(a, base)) continue;
    const f = HT.altSpan(a, base);
    if (f.own.start && f.start != null && base.start != null && Math.abs(f.start - base.start) > 1e-9) push(f.start, 's');
    const e = f.ongoing ? now : f.end;
    if (f.own.end && e != null && base.end != null && Math.abs(e - base.end) > 1e-9) push(e, 'e');
  }
  return out;
};

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const bandOf = ctx.shared.bandOf;
  const counts = { 왕조: 0, 지도자: 0, 내각: 0, 기관: 0, 시기: 0, 지위: 0, 예속안: 0 };
  const extra = { 모호한구간: 0, 이설경계: 0, 가문: 0, 가리키는항목: 0, 지도자표기: 0, 빌린줄: 0, 직위줄더: 0, 직위줄더칸: 0, 칸정통성: 0 };
  const skipped = { 기관_주인없음: 0, 기관_단없음: 0 };
  const tiers = { 띠: 0, 칸: 0, 넘침: 0 }; // 지도자 두 단(4단계 배치 갈래 둘째): 두 단 이상인 띠 · 단 1 이상에 실은 지도자 칸 · 4단을 넘어 마지막 단에 둔 칸

  tl.tracks.forEach((tr, trackIndex) => {
    const trackRows = out.tracks[trackIndex].rows;
    const geoOf = r => tr.geos[r] || tr.geo;

    /* 칸에 딸린 항목(구역 40~43) — 자리는 칸의 구간이 아니라 제 구간이고, 단계(lod)는 그 칸과 같다(칸이 보이는 배율에서 함께 나온다).
       a = 칸의 종류 · b = 칸의 단 · 나머지는 구역마다(계약 6-2 끝). ref는 그 칸이 든 띠의 uid다. */
    const marks = (p, kind, lane, start, end, seq, c, base, now, house, item) => {
      const row = p._row;
      const seed = { section: 0, track: trackIndex, row, row2: row, start, end, lod: lodOf(end - start), ref: p.uid, name: '', color: 0, a: kind, b: lane, c: 0, d: 0, text2: '' };
      const nth = seq == null || seq < 0 ? 0 : Math.min(4095, seq + 1);
      if (c) {
        // 구역 40 — 모호한 구간(연대 폭). 무늬는 전승이면 빗금, 그 밖(추정 · 통설 · 확실)이면 세로 줄(zoneKindOf).
        const look = c.certainty === 'legend' ? 1 : 0;
        [c.startRange, c.endRange].forEach((range, side) => {
          if (!range) return;
          const a = minute(range[0]), b = Math.max(a, minute(range[1]));
          out.items.push(Object.assign({}, seed, { section: SECTION.zone, start: a, end: b, c: look, d: side }));
          extra.모호한구간++;
        });
        // 구역 41 — 이설이 말하는 경계(유령 구분선). start가 선의 자리이고 end는 칸의 끝이다(단계 셈과 타일 고르기에만).
        if (base) {
          for (const m of altEdges(HT, c, base, now)) {
            const at = minute(m.y);
            if (at == null) continue;
            out.items.push(Object.assign({}, seed, { section: SECTION.alt, start: at, end: Math.max(at, end), c: m.side === 'e' ? 1 : 0, d: nth }));
            extra.이설경계++;
          }
        }
      }
      // 구역 42 — 이 칸의 가문(가문 강조 is-house). 칸의 style에는 가문의 이름을 담을 자리가 없어 일반 항목으로 싣는다.
      if (house && house.houseId) {
        out.items.push(Object.assign({}, seed, { section: SECTION.house, name: house.houseName || '', color: color(house.houseColor, 0), c: nth, text2: house.houseId }));
        extra.가문++;
      }
      // 구역 43 — 이 칸이 가리키는 항목의 uid(왕조 · 기관 · 예속 안 칸). 누르면 열 상세 창을 찾는 값이다.
      if (item && item.uid) {
        out.items.push(Object.assign({}, seed, { section: SECTION.item, name: item.name || '', color: color(item.color, 0), c: nth, text2: item.uid }));
        extra.가리키는항목++;
      }
      // 구역 46 — 지도자 칸의 다른 표기(묘호 · 시호 · 이름 · 대수). 필터 시트의 '지도자 표기'와 '대수'가 쓴다.
      // 칸의 이름은 기본 표기(HT.leaderLabel(c, 'auto', false)) 하나뿐이라, 표기를 바꿀 글을 따로 싣는다.
      // `name` = 묘호 · `text2` = "시호	이름"(항목의 글 밭이 둘뿐이라 탭으로 잇는다) · `c` = 그 칸의 순번 + 1 · `d` = 대수 + 1(0 = 대수 없음).
      if (kind === STRIP.leader && c && (c.temple || c.title || c.given || c.ordinal != null)) {
        out.items.push(Object.assign({}, seed, {
          section: SECTION.leaderName,
          name: c.temple || '',
          c: nth,
          d: c.ordinal == null ? 0 : c.ordinal + 1,
          text2: `${c.title || ''}	${c.given || ''}`,
        }));
        extra.지도자표기++;
      }
      // 구역 57 — 칸의 정통성(4단계 배치 갈래 · 계약 1-1 덧붙임 · 감독 결정 LEGIT 가): 지도자 · 내각 · 직위 줄 더의 칸만(예속 안 칸의 c는 소속 줄이라 뺀다 — 그것은 구역 58).
      // `c` = 그 칸의 순번 + 1 · `d` = 정통성 번호 + 1(띠의 form 10 ~ 12와 같은 차례). status를 적지 않은 칸은 싣지 않는다.
      const legit = (kind === STRIP.leader || kind === STRIP.cabinet || kind === KIND_OFFICE) && c ? statusNoOf(c.status) : 0;
      if (legit) {
        out.items.push(Object.assign({}, seed, { section: SECTION.legit, c: nth, d: legit }));
        extra.칸정통성++;
      }
    };

    const put = (p, kind, lane, s, e, name, style, col, opt) => {
      if (s == null || e == null || !name) return false;
      const band = out.periods[bandOf.get(p.uid)];
      const start = Math.max(s, band.start), end = Math.max(start, Math.min(e, band.end));
      if (s > band.end || e < band.start) return false;
      const o = opt || {};
      out.cells.push({ period: p.uid, kind, lane, start, end, name, style: styleWith(style, o.alt, o.seq), color: col || 0 });
      marks(p, kind, lane, start, end, o.seq, o.cell, o.base, o.now, o.house, o.item);
      return true;
    };

    for (const p of tr.periods) {
      if (p._overlay || !bandOf.has(p.uid)) continue;
      const geo = geoOf(p._row);

      /* 왕조: 이 띠를 다스린 왕조마다 긴 둥근 칸 하나(_dynCells — 이어 붙이지 않고 왕조가 바뀌면 끊김), 제 색으로 */
      if (tr.geo.dynastyH) {
        tl._dynOf(p).forEach((d, i) => {
          const y = d.dynasty;
          const cell = dynCellOf(HT, d, y);
          if (put(p, STRIP.dynasty, 0, minute(d.start), minute(d.end), y.name || '', cellStyle(d), color(y.color, 0),
            { seq: i, cell, base: { start: d.start, end: d.end }, now: p.endY, house: y, item: { uid: y.uid, name: y.name, color: y.color } })) counts.왕조++;
        });
      }
      /* 지도자 · 내각: 같은 왕조에서 이어지는 칸은 하나의 긴 둥근 칸(_cells의 layoutStrip 무리 열쇠 = 왕조).
         번갈아 짙기(is-alt)는 보이는 차례가 아니라 **원래 목록의 번호**로 정한다(명세 5-3의 6번) — lane 비트 18에 싣는다.
         지도자 칸의 lane = 그 칸의 단(4단계 배치 갈래 둘째 · 계약 1-1 덧붙임 — tl._leaderLanes: 공동 · 주장 칸이 겹친 띠만 0 위 · 1 아래 …, 그 밖은 0 그대로).
         내각은 0 그대로다. 이음(joinL)은 같은 단의 바로 앞 칸으로 센다(단마다 prevKey). 칸에 딸린 구역 40 ~ 42 · 46 · 57의 b(marks의 seed)도 이 단을 따른다 */
      for (const [kind, list, h, ref] of [[STRIP.leader, p.leaders, tr.geo.leaderH, 'leader'], [STRIP.cabinet, p.cabinets, tr.geo.cabinetH, 'cabinet']]) {
        if (!h || !list || !list.length) continue;
        const lanes = kind === STRIP.leader ? tl._leaderLanes(p) : null;
        if (lanes && lanes.n > 1) {
          tiers.띠++;
          tiers.넘침 += lanes.over;
        }
        const prevKey = []; // 단마다 바로 앞 칸의 무리 열쇠
        list.forEach((c, i) => {
          const lane = lanes ? lanes.lane[i] : 0;
          const key = c.dynasty || c.dynastyAuto || '';
          const name = kind === STRIP.leader ? HT.leaderLabel(c, 'auto', false) : c.name;
          const style = cellStyle(c) | (prevKey[lane] !== undefined && prevKey[lane] === key ? ST.joinL : 0) | ((kind === STRIP.leader ? p.leadersFrom : p.cabinetsFrom) ? ST_BORROW : 0);
          if (put(p, kind, lane, minute(c.start), minute(c.end ?? p.endY), name, style, 0,
            { alt: i % 2 === 1, seq: i, cell: c, base: cellBaseOf(HT, c, p, `${ref}:${i}`), now: p.endY, house: c })) {
            counts[kind === STRIP.leader ? '지도자' : '내각']++;
            if (lane > 0) tiers.칸++;
          }
          prevKey[lane] = key;
        });
      }
      /* 리메이크 3단계(계약 1-1 초안) — 빌린 직위 줄의 머리 글(구역 54)과 직위 줄 더(칸 종류 9 · 줄 이름 구역 55).
         칸 층 셈 · 줄 높이에는 넣지 않는다(4단계가 그릴 때 정함) — 있는 값은 그대로다. */
      {
        const band = out.periods[bandOf.get(p.uid)];
        const head = (section, a, b, name, text2) =>
          out.items.push({ section, track: trackIndex, row: band.row, row2: band.row, start: band.start, end: band.end, lod: -1, ref: p.uid, name, color: 0, a, b, c: 0, d: 0, text2 });
        for (const [kind, v] of [[STRIP.leader, p.leadersFrom], [STRIP.cabinet, p.cabinetsFrom]]) {
          if (!v || !v.from) continue;
          const f = fromOf(ctx.model, p, v.from);
          head(SECTION.borrow, kind, 0, f.text, f.src ? f.src.uid : '');
          extra.빌린줄++;
        }
        (p.offices || []).forEach((o, lane) => {
          if (!o || typeof o !== 'object') return;
          const f = o.from ? fromOf(ctx.model, p, o.from) : null;
          const cells = f ? officeCells(f.src, f.office) : o.cells || [];
          head(SECTION.officeName, KIND_OFFICE, lane, o.name || (f && f.office) || '', '');
          extra.직위줄더++;
          if (f) {
            head(SECTION.borrow, KIND_OFFICE, lane, f.text, f.src ? f.src.uid : '');
            extra.빌린줄++;
          }
          cells.forEach((c, i) => {
            const name = HT.leaderLabel(c, 'auto', false) || c.name || '';
            if (put(p, KIND_OFFICE, lane, minute(c.start), minute(c.end ?? p.endY), name, cellStyle(c) | (f ? ST_BORROW : 0), 0,
              { alt: i % 2 === 1, seq: i, cell: c, base: null, now: p.endY, house: c })) extra.직위줄더칸++;
          });
        });
      }
      /* 시기 구분(학계): 체계마다 얇은 한 줄(lane) — 체계가 둘 이상이면 이름 앞에 체계 이름을 탭 문자로 붙여 둔다(계약 6절) */
      if (geo.phaseH && p.phaseSchemes) {
        const multi = p.phaseSchemes.length > 1;
        p.phaseSchemes.slice(0, Math.round(geo.phaseH / 15) || 3).forEach((sc, lane) => {
          let first = true;
          for (const c of sc.spans) {
            const name = multi && sc.scheme ? `${sc.scheme}\t${c.name}` : c.name;
            const style = cellStyle(c) | (multi && sc.scheme ? ST.tagged : 0) | (first ? 0 : ST.joinL);
            if (put(p, STRIP.phase, lane, minute(c.start), minute(c.end), name, style, 0,
              { seq: c.ci, cell: c, base: cellBaseOf(HT, c, p, `phase:${c.ci}`), now: p.endY })) counts.시기++;
            first = false;
          }
        });
      }
      /* 지위: 서열이 높을수록 나라 색이 짙게 — 짙기는 그리는 쪽이 단계로 섞으므로 단계만 싣는다(계약 6절) */
      if (geo.rankH && p.rankSpans) {
        let first = true;
        for (const c of p.rankSpans) {
          const style = cellStyle(c) | (first ? 0 : ST.joinL) | (Math.min(7, (c.level || 0) + 1) << ST_RANK);
          if (put(p, STRIP.rank, 0, minute(c.start), minute(c.end), c.name || '', style, 0,
            { seq: c.i, cell: c, base: cellBaseOf(HT, c, p, `rank:${c.i}`), now: p.endY })) counts.지위++;
          first = false;
        }
      }
      /* 예속(안) 칸: 상국 띠 안 맨 아래 — 상국이 다스린 속국(괴뢰 · 위임 · 식민 · 점령)의 이름표. lane 0이 띠 아랫변에 가장 가깝다 */
      if (geo.depH && p._dep && p._dep.inLanes) {
        for (const it of p._dep.items) {
          if (!it.inn) continue;
          let first = true;
          for (const s of it.segs.filter(x => x.side === 'in')) {
            const style = cellStyle(s.h) | (first ? 0 : ST.joinL) | (Math.min(7, DEP_LOOK[s.look] || 0) << ST_DEP);
            if (put(p, STRIP.dep, it.inLane || 0, minute(s.a), minute(s.b), it.p.name || '', style, color(it.p.color),
              { seq: (it.p.hosts || []).indexOf(s.h), cell: s.h, base: { start: s.a, end: s.b, startUnknown: s.h.startUnknown, endUnknown: s.h.endUnknown }, now: it.p.endY,
                item: { uid: it.p.uid, name: it.p.name, color: it.p.color } })) counts.예속안++;
            first = false;
          }
        }
      }
    }

    /* 기관(얹히는 조직 — 구역 탭은 hangs.mjs의 몫): 제 줄 없이 주인 띠의 기관 단에. 겹치면 단(lane)을 나눈다 — 2단계처럼 빼지 않는다 */
    const organLanes = new Map(); // 주인 띠 uid → 단마다의 마지막 끝
    const organSeq = new Map(); // 주인 띠 uid → 그 띠에 실은 기관 칸의 수(칸 참조 'organ:n'의 번호 — 상세 창이 구역 43의 uid로 연다)
    for (const p of tr.periods.filter(q => q._overlay && q.scale !== 'zone').sort((a, b) => a.start - b.start || a.endY - b.endY)) {
      for (const h of p.hosts || []) {
        let host = tr.periods.find(q => q.uid === h.host.uid) || null;
        while (host && host._hidden) host = host._host;
        if (!host || !bandOf.has(host.uid)) { skipped.기관_주인없음++; continue; }
        const band = out.periods[bandOf.get(host.uid)];
        if (trackRows[band.row].organTop < 0) { skipped.기관_단없음++; continue; }
        const s = Math.max(minute(Math.max(p.start, h.start ?? -Infinity)), band.start);
        const e = Math.min(minute(Math.min(p.endY, h.end ?? Infinity)), band.end);
        if (e < s) continue;
        const ends = organLanes.get(host.uid) || [];
        let lane = ends.findIndex(end => end < s);
        if (lane < 0) lane = ends.push(-Infinity) - 1;
        ends[lane] = e;
        organLanes.set(host.uid, ends);
        const seq = organSeq.get(host.uid) || 0;
        organSeq.set(host.uid, seq + 1);
        out.cells.push({ period: host.uid, kind: STRIP.organ, lane, start: s, end: e, name: p.name || '', style: styleWith(cellStyle(p), false, seq), color: color(p.color) });
        // 기관 칸은 제 항목의 이설만 그린다(모호한 구간은 그리지 않는다 — 지금 연표의 oc가 alternatives만 담는다).
        const alts = HT.datedAlts(p);
        marks(host, STRIP.organ, lane, s, e, seq, alts.length ? { alternatives: alts } : null,
          { start: p.start, startAt: p.startAt, end: p.endY, endAt: p.endAt, startUnknown: p.startUnknown, endUnknown: p.endUnknown, ongoing: p.ongoing }, p.endY, null,
          { uid: p.uid, name: p.name, color: p.color });
        counts.기관++;
      }
    }
  });
  ctx.notes.칸 = counts;
  ctx.notes.칸에_딸린_것 = extra;
  ctx.notes.칸에서_뺀_것 = skipped;
  ctx.notes.지도자_두단 = tiers;
}

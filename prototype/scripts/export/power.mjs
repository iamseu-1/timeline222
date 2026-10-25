// 단체 단(집권 · 실권) · 명목 지도자 · 연합의 겹 탭 — 10건 7의 D5 결정 1 A · 2(자리 A) · 3 C와 덧판 x1 A · x2 A · x3 C의 새 앱(아카이브) 몫.
// 새 앱은 스스로 다시 배치하지 못하므로, 웹 연표가 그리는 것(js/timeline.js의 _layoutTrack 단체 덧단 · _groupRows · _groupCells · _cells의 is-nominal ·
// _coalTabPlan의 재료)을 여기서 자료로 풀고 엔진은 뜻을 모른 채 나르기만 한다(엔진 스키마 판 '3' 그대로 · Rust는 고치지 않는다).
// 셈은 js/core.js의 HT.groupStrip(집권 · 실권 칸 · 명목) · HT.coalitionsOf(연합 가담 기간)를 그대로 부른다 — 웹과 같은 답.
// 규칙 · 숫자의 근거는 설계 docs/설계-10건/7-8-단체와-렌즈.md 11-2 · 11-3(웹 구현 기록)과 13절(새 앱 구현 기록).
//
// 번호는 계약 부록 가-9의 예약(docs/설계-10건/A-아카이브-이음.md)을 쓴다 — 렌즈(export/lens.mjs)가 같은 칸 종류 8의 단 0 · 1과 단 갈래 1~4를 쓰므로 그 뒤를 잇는다.
// 뜻은 이 머리말과 설계 문서 13절에 적고, 계약 문서에 옮겨 적는 것은 총괄 몫이다.
//
//  ① 줄 값: 그 줄에 집권 단 · 실권 단이 있는가 — tracks.mjs가 `figWide`의 비트 7 · 8에 싣는다(이 모듈이 아니라 줄 쌓기 자체 점검과 함께).
//  ② 단체 칸 = **칸 종류 8(공용 칸 단)** 기본 판(변형 없음). `lane` 2 = 집권 단 · 3 = 실권 단.
//     `style` 27~29(`>> 27 & 7`) = 단 갈래: 5 한 단체의 집권 · 6 연정(함께 집권한 단체 둘 이상 · 짝을 모르는 연정 포함) · 7 실권(실권 칸끼리 겹치면 두 색 + 점 그대로).
//     `style` 32 = `name`에 줄임이 탭으로 붙음("줄임\t이름 · 이름" — 줄임 = 단체마다 첫 글자 '·' 이음, 한 단체면 그 첫 글자) — 렌즈의 단체 칸(갈래 2)과 같은 꼴.
//     나머지 비트(1 · 2 미정 끝 · 4 앞 칸과 이음 · 15~26 순번 + 1)는 계약 6-2 그대로. `color` = 첫째 단체의 색(모델의 g.color — 자동 색 겹침 막기를 거친 값).
//     칸마다 구역 43 항목 하나: `a` 8 · `b` 단 · `c` 순번 + 1 · `name` '' · `color` = 둘째 단체 색(연정 — 없으면 0) · `d` 1 = 짝을 모르는 연정 ·
//     `text2` = 누르면 열 단체(첫째)의 uid, 색 점이 있는 칸(연정 · 짝 모름)은 뒤에 `\t` + 점 색(6자리 16진 · ',' 이음 — 단체 차례). 렌즈의 단체 칸과 같은 꼴이다.
//  ③ 명목 지도자 = 지도자 칸(종류 1)의 `style` **비트 29**(가-9에서 kind 1의 27~28은 D1이 풀었고 29는 비어 있음) — 켜져 있으면 그리는 쪽이 이름 글만 .5.
//     붕당 렌즈가 집권 단 자리(단 2)로 내린 지도자 칸(종류 8 · 단 갈래 4 — export/lens.mjs)은 비트 27~29가 단 갈래라 **비트 30**에 같은 뜻을
//     늦은 차례(contributeLate — 렌즈 모듈이 칸을 실은 뒤)에 켠다(웹 _cells의 is-nominal은 작은 지도자 칸에도 붙는다).
//  ④ 연합의 겹 탭 = **구역 47(뒤 장의 탭)의 모습 `a` 7**: 구성 나라 띠마다 가담 한 건에 항목 하나 — `row` · `ref` = 구성 나라 띠 · 구간 = 가담 기간(HT.coalitionsOf) ·
//     `name` · `color` = 연합 이름 · 색 · `b` = 그 띠의 가담 차례(HT.coalitionsOf의 차례 = 시작 · 끝 · 이름 차례) · `c` 0 · `d` 0 · `text2` = 연합 단체의 uid.
//     자리(상국 탭 먼저 · 연합 탭은 밀지 않음)는 그리는 쪽이 장면마다 정한다(웹 _coalTabPlan).
//
// 표시 체크 '단체'(show.groups — base.mjs의 연표는 켬)가 꺼져 있으면 아무것도 싣지 않는다. 단체 자료가 없는 자료는 ②~④가 모두 빈손이고 ①의 비트도 0이라
// 옛 출력이 바이트까지 그대로다. 노드 내장을 부르지 않는다(메이커 일꾼 겸용 — base.mjs 머리말).
import { minute, color } from './base.mjs';

/** 칸 종류 8(공용 칸 단)과 단체 단의 단 · 단 갈래(style 27~29). 렌즈(lens.mjs)의 단 0 · 1 · 갈래 1~4 다음을 쓴다. */
export const KIND_COMMON = 8;
export const POWER_LANE = { power: 2, real: 3 };
export const POWER_BAND = { single: 5, coalition: 6, real: 7 };
const BAND_SHIFT = 27;
/** 지도자 칸(종류 1)의 명목 비트(style 29) · 렌즈가 단 2로 내린 지도자 칸(종류 8 · 단 갈래 4)의 명목 비트(style 30). */
export const NOMINAL_BIT = 1 << 29;
export const NOMINAL_BIT_LOWERED = 1 << 30;
const LENS_LOWERED_LEADER = 4;
/** 구역 47(뒤 장의 탭)의 모습 7 = 연합의 겹 탭(0~6은 상국 탭 — hangs.mjs). */
export const SECTION_HOST_TAB = 47;
export const COALITION_LOOK = 7;
const SECTION_ITEM = 43;
/** 실권 밑줄(리메이크 3단계 · 계약 1-1 초안) */
export const SECTION_POWER_LINE = 56;
const STRIP_LEADER = 1;
/** 계약 6-2의 칸 모습 비트(strips.mjs와 같은 값). */
const ST = { unkS: 1, unkE: 2, joinL: 4, tagged: 32 };

const styleWith = (style, seq) => style | ((seq == null || seq < 0 ? 0 : Math.min(4095, seq + 1)) << 15);
/** 단계 산수(engine/src/levels.rs의 lod_of — strips.mjs와 같은 식). 칸에 딸린 항목은 그 칸과 같은 단계까지 실린다. */
const lodOf = duration => {
  const wide = Math.max(0, duration) * 8;
  for (let level = 14; level >= 0; level--) if (wide >= 4 ** level) return level;
  return 0;
};
const hex6 = c => color(c, 0xa4b1b7).toString(16).padStart(6, '0');

export function contribute(ctx, out) {
  const { tl, HT } = ctx;
  const notes = { 집권칸: 0, 연정칸: 0, 실권칸: 0, 딸린항목: 0, 명목: 0, 연합탭: 0 };
  ctx.notes.단체단 = notes;
  /* 리메이크 3단계(계약 1-1 초안) — 실권 밑줄(구역 56): 객체의 power[].over(형식 4 더하기 — 쥔 쪽에만 적고 over가 빼앗긴 객체)마다
     빼앗긴 쪽 띠에 항목 하나 · 구간은 그 띠 안으로 자름 · 이름 · 색 = 쥔 쪽(5단계 과제 12 — 감독 결정 장면 3) · text2 = 쥔 쪽 uid.
     over 없이 이름만인 줄 = 제 안의 실권자(세도 가문 · 권신 — 정규화가 받음 · 가지 remake-5b)는 제 띠에 · a 1 · 이름 = 그 줄의 이름 · 색 0 · text2 ''.
     표시 체크 단체와 상관없이 싣는다(객체의 실권이지 단체의 칸이 아님). 상대를 못 찾거나 띠가 없으면 뺀다.
     리메이크 6단계(설계 3-4 · 같은 일을 두 쪽에 적지 않음): 실권 정권(종류 regime)이 섬김(partOf 명목상)으로 가리키는 상대에는 over를 따로 적지 않아도 실권 밑줄 —
     over 줄과 같은 꼴로 상대 띠에 항목 하나 · 구간은 섬김 기간(비우면 실권 정권의 기간)을 그 띠 안으로 자름. 같은 상대를 over로 적은 줄이 있으면 그 줄만(두 번 싣지 않음). */
  if (ctx.shared.bandOf) {
    const bandOf = ctx.shared.bandOf;
    let n = 0;
    for (const p of ctx.model.periods || []) {
      const overs = new Set(); // over로 적은 상대(아래 섬김 밑줄이 같은 상대에 겹치지 않게)
      for (const w of Array.isArray(p.power) ? p.power : []) {
        if (!w) continue;
        if (!w.over) {
          if (!w.name || !bandOf.has(p.uid)) continue;
          const band = out.periods[bandOf.get(p.uid)];
          const s = Math.max(band.start, minute(w.start ?? p.start) ?? band.start), e = Math.min(band.end, minute(w.end ?? p.endY) ?? band.end);
          if (!(e >= s)) continue;
          out.items.push({ section: SECTION_POWER_LINE, track: band.track, row: band.row, row2: band.row, start: s, end: e, lod: lodOf(e - s), ref: p.uid, name: w.name, color: 0, a: 1, b: 0, c: 0, d: 0, text2: '' });
          n++;
          continue;
        }
        const key = String(w.over).trim();
        const t = (ctx.model.byUid && ctx.model.byUid.get(key)) || ctx.model.periods.find(q => q.packId === p.packId && q.id === key) || ctx.model.periods.find(q => q.packId === p.packId && q.name === key);
        if (!t || t === p) continue;
        overs.add(t);
        if (!bandOf.has(t.uid)) continue;
        const band = out.periods[bandOf.get(t.uid)];
        const s = Math.max(band.start, minute(w.start ?? t.start) ?? band.start), e = Math.min(band.end, minute(w.end ?? t.endY) ?? band.end);
        if (!(e >= s)) continue;
        out.items.push({ section: SECTION_POWER_LINE, track: band.track, row: band.row, row2: band.row, start: s, end: e, lod: lodOf(e - s), ref: t.uid, name: p.name || '', color: color(p.color, 0), a: 0, b: 0, c: 0, d: 0, text2: p.uid });
        n++;
      }
      if (p.type !== 'regime') continue;
      for (const h of Array.isArray(p.hosts) ? p.hosts : []) {
        const t = h && h.host;
        if (!t || h.relation !== 'nominal' || t === p || overs.has(t) || !bandOf.has(t.uid)) continue;
        const band = out.periods[bandOf.get(t.uid)];
        const s = Math.max(band.start, minute(h.start ?? p.start) ?? band.start), e = Math.min(band.end, minute(h.end ?? p.endY) ?? band.end);
        if (!(e >= s)) continue;
        out.items.push({ section: SECTION_POWER_LINE, track: band.track, row: band.row, row2: band.row, start: s, end: e, lod: lodOf(e - s), ref: t.uid, name: p.name || '', color: color(p.color, 0), a: 0, b: 0, c: 0, d: 0, text2: p.uid });
        n++;
      }
    }
    notes.실권밑줄 = n;
  }
  if (!tl.show || !tl.show.groups || typeof HT.groupStrip !== 'function') return;
  const bandOf = ctx.shared.bandOf;
  if (!bandOf) return;

  /** 명목 지도자 칸의 순번 — 띠 uid → Set(늦은 차례가 렌즈의 내린 지도자 칸에 같은 표시를 켠다). 변형 판을 다시 돌릴 때(variants.mjs)는 새 shared라 덮지 않는다. */
  const nominalOf = (ctx.shared.powerNominal = new Map());

  /* 지도자 칸(종류 1)의 자리 — 띠 uid → 순번 → out.cells의 자리(명목 비트를 켤 칸을 찾는다). strips.mjs가 이미 실었다. */
  const leaderAt = new Map();
  out.cells.forEach((c, i) => {
    if (c.kind !== STRIP_LEADER || c.variant) return;
    const seq = ((c.style >> 15) & 0xfff) - 1;
    if (seq < 0) return;
    if (!leaderAt.has(c.period)) leaderAt.set(c.period, new Map());
    leaderAt.get(c.period).set(seq, i);
  });

  tl.tracks.forEach((tr, trackIndex) => {
    /* 연합의 겹 탭이 붙는 띠 — hangs.mjs의 뒤 장의 탭과 같은 조건(그려지는 띠 · 접힌 민족 줄 밖) */
    const drawn = p => !p._folded && !p._hidden && !p._under && !p._overlay && p._row != null && p._row >= 0 && p._row < tr.rows && !tr.foldedRows.has(p._row);
    for (const p of tr.periods) {
      if (p._overlay || !bandOf.has(p.uid)) continue;
      const band = out.periods[bandOf.get(p.uid)];
      const geo = tr.geos[p._row] || tr.geo;
      const S = HT.groupStrip(p);

      /* ② 단체 칸 — 그 줄에 그 단이 있을 때만(웹 _groupRows: gr.powerH · gr.realH) */
      for (const [lane, list, h] of [[POWER_LANE.power, S.power, geo.powerH], [POWER_LANE.real, S.real, geo.realH]]) {
        if (!h || !list.length) continue;
        list.forEach((c, j) => {
          if (!c.name) return;
          const s0 = minute(c.start == null || !isFinite(c.start) ? p.start : c.start);
          const e0 = minute(c.end == null || !isFinite(c.end) ? p.endY : c.end);
          if (s0 == null || e0 == null || s0 > band.end || e0 < band.start) return;
          const start = Math.max(s0, band.start), end = Math.max(start, Math.min(e0, band.end));
          const two = (c.n || 1) > 1;
          const kind = c.real ? POWER_BAND.real : two || c.solo ? POWER_BAND.coalition : POWER_BAND.single;
          const style = styleWith((c.startUnknown ? ST.unkS : 0) | (c.endUnknown ? ST.unkE : 0) | (j > 0 ? ST.joinL : 0) | ST.tagged, j) | (kind << BAND_SHIFT);
          const short = c.short || [...c.name][0] || '';
          out.cells.push({ period: p.uid, kind: KIND_COMMON, lane, start, end, name: `${short}\t${c.name}`, style, color: color(c.color, 0xa4b1b7) });
          if (c.real) notes.실권칸++;
          else if (kind === POWER_BAND.coalition) notes.연정칸++;
          else notes.집권칸++;
          // 색 점(웹의 `.gd`): 연정은 함께 집권한 단체 전부의 색, 짝을 모르는 연정은 제 색 하나, 한 단체는 없음.
          const dots = c.solo ? [c.color] : two ? c.colors || [] : [];
          out.items.push({
            section: SECTION_ITEM, track: trackIndex, row: band.row, row2: band.row, start, end, lod: lodOf(end - start),
            ref: p.uid, name: '', color: two && c.color2 ? color(c.color2, 0) : 0, a: KIND_COMMON, b: lane, c: Math.min(4095, j + 1),
            d: c.solo ? 1 : 0, text2: (c.uid || '') + (dots.length ? `\t${dots.map(hex6).join(',')}` : ''),
          });
          notes.딸린항목++;
        });
      }

      /* ③ 명목 지도자 — 웹 _cells의 is-nominal(실권 칸들과 제 기간의 절반 이상 겹침 · HT.groupStrip의 nominal) */
      if (S.nominal.size) nominalOf.set(p.uid, S.nominal);
      if (S.nominal.size && leaderAt.has(p.uid)) {
        const at = leaderAt.get(p.uid);
        for (const i of S.nominal) {
          if (!at.has(i)) continue;
          out.cells[at.get(i)].style |= NOMINAL_BIT;
          notes.명목++;
        }
      }

      /* ④ 연합의 겹 탭 — 구성 나라 띠마다 가담 한 건에 항목 하나(자리는 그리는 쪽) */
      if (!drawn(p)) continue;
      HT.coalitionsOf(p).forEach((c, k) => {
        if (!(c.end > c.start)) return;
        const start = minute(c.start), end = minute(c.end);
        if (start == null || end == null || end < start) return;
        out.items.push({
          section: SECTION_HOST_TAB, track: trackIndex, row: p._row, row2: p._row, start, end, lod: -1, ref: p.uid,
          name: c.group.name || '', color: color(c.group.color, 0xa4b1b7), a: COALITION_LOOK, b: k, c: 0, d: 0, text2: c.group.uid || '',
        });
        notes.연합탭++;
      });
    }
  });
}

/** 늦은 차례: 붕당 렌즈(export/lens.mjs — MODULES 맨 끝)가 집권 단 자리(단 2)로 내린 지도자 칸(종류 8 · 단 갈래 4)에도 명목 표시(비트 30)를 켠다.
    렌즈 칸의 순번(비트 15~26)은 지도자 칸의 순번 그대로라 ③과 같은 Set으로 찾는다. 렌즈 모듈을 건너뛰었거나 렌즈 칸이 없으면 아무것도 하지 않는다. */
export function contributeLate(ctx, out) {
  const nominalOf = ctx.shared.powerNominal;
  if (!nominalOf || !nominalOf.size) return;
  let n = 0;
  for (const c of out.cells) {
    if (c.kind !== KIND_COMMON || c.lane !== POWER_LANE.power || !/^theme:/.test(c.variant || '')) continue;
    if (((c.style >> BAND_SHIFT) & 7) !== LENS_LOWERED_LEADER) continue;
    const seq = ((c.style >> 15) & 0xfff) - 1;
    const set = nominalOf.get(c.period);
    if (seq < 0 || !set || !set.has(seq)) continue;
    c.style = (c.style | NOMINAL_BIT_LOWERED) >>> 0;
    n++;
  }
  if (ctx.notes.단체단) ctx.notes.단체단.렌즈명목 = n;
}

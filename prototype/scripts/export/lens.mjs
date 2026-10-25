// 렌즈(주제 보기 — 10건 8 · 감독 선택 D5 결정 5 A · 6 B)의 새 앱 몫: 렌즈 칸을 **미리 셈해** 변형으로 싣는다.
// 새 앱은 스스로 다시 배치하지 못하므로, 웹 연표가 렌즈를 켤 때 그리는 것(js/timeline.js의 _lensRow · _lensCells · _rankCells(lens) ·
// 이름 칸 부제 · 사건 옅게)을 여기서 자료로 풀고 엔진은 뜻을 모른 채 나르기만 한다(엔진 스키마 판 '3' 그대로 · Rust는 고치지 않는다).
// 규칙의 근거는 설계 docs/설계-10건/7-8-단체와-렌즈.md 10-2(자료에서 그림까지) · 10-3(새 앱이 따라 짓는 길), 셈은 js/core.js의
// HT.lensCellsOf · HT.lensAny · HT.lensEventHit · HT.lensHasData · HT.themeHint를 그대로 부른다(웹과 같은 답).
//
// 번호는 계약 부록 가-9의 예약(docs/설계-10건/A-아카이브-이음.md)을 쓴다 — 뜻은 이 머리말과 설계 문서의 '구현 기록(새 앱 — 렌즈)'에 적고,
// 계약 문서에 옮겨 적는 것은 총괄 몫이다.
//
//  ① 변형 kind 4 `theme:<주제 id>` — 렌즈 하나(그 주제로 그릴 칸이 있는 나라가 하나라도 있을 때만). `uid` = 주제 id · `name` = 주제 이름.
//     · 새 칸(그 변형에서만 있는 칸) = **칸 종류 8(공용 칸 단)**. `lane` 0 = 지도자 칸 자리 · 1 = 지위 단 자리.
//       `style` 27~29(`>> 27 & 7`) = 단 갈래: 1 렌즈 칸(제도 — 웹의 `.k-lens`) · 2 단체 칸(붕당 렌즈 = 집권 단의 칸 — 웹의 `_groupCells(lens)` ·
//       `.k-group.k-lens`: 모서리 4 · 연정은 위아래 두 색 + 색 점 · 짝을 모르는 연정은 위 반만 · `name`은 "줄임\t이름"(줄임 = 단체마다 첫 글자 '·' 이음), 비트 32)
//       · 3 지위로 대신한 체제(지위 칸 꼴 — 비트 8~10 서열은 지위 칸과 같다) · 4 지위 단 자리로 내린 지도자 칸(지도자 칸 꼴 · 작은 글).
//       나머지 비트(1 · 2 미정 끝 · 4 앞 칸과 이음 · 14 번갈아 짙기 · 15~26 순번 + 1)는 계약 6-2 그대로. `color` = 내보낼 때 셈한 갈래 · 단체 색(앱은 셈하지 않는다).
//       갈래 1 · 2 칸에는 구역 43 항목이 딸린다: `a` 8 · `b` 단 · `c` 순번 + 1 · `name` = 갈래 이름(메아리의 열쇠 — 단체 칸 · 갈래 없는 제도는 '') ·
//       `color` = 연정 칸의 둘째 단체 색(없으면 0) · `d` = 1 짝을 모르는 연정(단체 칸만 — 아니면 0) ·
//       `text2` = 누르면 열 항목(제도 · 첫 단체)의 uid, 색 점이 있는 단체 칸(연정 · 짝 모름)은 뒤에 `\t` + 점 색(6자리 16진 · ',' 이음 — 단체 차례).
//     · 가리는 것(`hides` kind 3) = 그 렌즈로 그릴 칸이 있는 나라의 지도자 칸(종류 1), 지위로 대신한 나라는 지위 칸(종류 5)도.
//       붕당 렌즈의 맞바꿈(웹의 _groupRows — 집권 단 자리에 지도자 칸을 작게)은 내보내기의 연표에 집권 단이 생긴 날(`geo.powerH` —
//       설계 11-3: base.mjs의 show.groups · 단체 단 칸 = 종류 8 `lane` 2)부터: 그 줄의 집권 단 칸(종류 8 · 단 2)도 가리고 지도자 칸을 단 2에 갈래 4로.
//       집권 단 작업(export/power.mjs · 48c5d1c)이 base.mjs의 show.groups를 켠 뒤로 이 갈래가 돈다 — 내린 지도자 칸의 명목 표시(비트 30)는
//       power.mjs의 늦은 차례가 켠다. 앱은 단 2의 자리(집권 단)를 그 작업의 RowGeo가 줄 때 그린다(그 전에는 그리지 않음).
//       → 렌즈를 켠 동안 타일에 남는 지도자 칸은 모두 '그 주제 자료가 없는 나라'의 것이다(앱은 그것을 .4로 옅게 그린다).
//  ② 줄 배치 `theme:*` — 렌즈 켬 배치는 렌즈 종류와 상관없이 하나이고 바뀌는 것은 트랙의 '지도자 자리가 있는가' 하나뿐이라
//     (변형 표의 `track`이 하나뿐이어서 싣지 못한다) 항목 기록 `themes`의 `x_lens.slot`(트랙 글자 id 목록)으로 싣는다:
//     앱의 지도자 자리 = (트랙의 지도자 칸 && 표시 '지도자') || (렌즈 켬 && slot). 자기 검사가 지금 연표의 _layoutTrack과 대조한다.
//  ③ 차림표 · 사건 — 항목 기록 `themes`의 `x_lens.themes[]`(사전 차례): `hint` 한마디(HT.themeHint) · `has` 자료 있음(HT.lensHasData) ·
//     `hidden` 렌즈에서 숨김 · `v` 변형 있음 · `sw` 갈래 견본({ t 제목, l [[이름, 색]] }) · `ev` 그 주제의 사건 uid(공동 사건의 다른 자리 `#n` 포함 —
//     앱이 `ids_of`로 타일의 사건 번호로 바꿔 사건을 옅게 · 고리를 단다).
//     렌즈로 말할 것이 하나도 없는 자료(동아시아 기본팩 — 제도 · 지위 · 단체 · 숨김 · DLC 한마디가 없음)는 `x_lens`를 싣지 않는다(기록 바이트 그대로).
//
// **옛 열쇠는 1바이트도 바꾸지 않는다**: 칸 · 일반 항목 · 변형은 모두 **뒤에 덧붙이고**(앞선 것의 자리 · `hides[].at`이 그대로),
// themes 기록은 끝에 `x_lens` 열쇠 하나만 더한다. 이 모듈을 건너뛴(HT_EXPORT_SKIP=lens) 출력이 곧 고치기 전의 출력이다 — prototype/scripts/lens-export-check.mjs가 견준다.
// 노드 내장을 부르지 않는다(메이커 일꾼 겸용 — base.mjs 머리말).
import { assert, minute, color } from './base.mjs';
import { G } from './variants.mjs';

/** 변형 번호(계약 부록 가-9의 예약): 4 렌즈. variants.mjs의 1 소속 펼치기 · 2 대범위와 같은 표에 든다. */
export const VARIANT_KIND_THEME = 4;
/** 칸 종류 8(공용 칸 단)과 그 단 갈래(style 27~29). */
export const KIND_COMMON = 8;
export const LENS_BAND = { inst: 1, group: 2, rank: 3, leader: 4 };
export const LENS_LANE = { leader: 0, rank: 1, power: 2 };
const BAND_SHIFT = 27;
/** 계약 6-2의 칸 모습 비트(strips.mjs와 같은 값 — 그 모듈의 것은 내보내지 않아 여기 옮겨 둔다). */
const ST = { unkS: 1, unkE: 2, joinL: 4, estimated: 8, legend: 16, tagged: 32, range: 64, alt: 128 };
const ST_RANK = 8;
const STRIP = { leader: 1, rank: 5 };
const SECTION_ITEM = 43;
/** 계약 3절의 지도자 칸 높이 + 틈(렌즈 켬 배치에서 지도자 자리가 새로 생긴 줄이 늘어나는 만큼). */
const LEADER_SLOT = G.leader + G.slotGap;

const styleWith = (style, alt, seq) => style | (alt ? 1 << 14 : 0) | ((seq == null || seq < 0 ? 0 : Math.min(4095, seq + 1)) << 15);
/** 칸 하나의 style 가운데 칸 자료에서 곧바로 나오는 몫(strips.mjs의 cellStyle 그대로). */
const cellStyle = c => {
  const cert = c && c.certainty;
  return (c && c.startUnknown ? ST.unkS : 0) | (c && (c.endUnknown || c.endYAuto) ? ST.unkE : 0) |
    (cert === 'estimated' ? ST.estimated : cert === 'legend' ? ST.legend : 0) |
    (c && (c.startRange || c.endRange) ? ST.range : 0) |
    (c && c.alternatives && c.alternatives.length ? ST.alt : 0);
};
/** 단계 산수(engine/src/levels.rs의 lod_of — strips.mjs와 같은 식). */
const lodOf = duration => {
  const wide = Math.max(0, duration) * 8;
  for (let level = 14; level >= 0; level--) if (wide >= 4 ** level) return level;
  return 0;
};

/** 렌즈 차림표의 갈래 견본(js/lens-ui.js의 swatches 그대로) — { t 제목, l [[이름, 0xRRGGBB]] } 또는 null. */
function swatchesOf(model, t) {
  const seen = new Map();
  for (const o of (model.institutionIndex && model.institutionIndex.byTheme.get(t.id)) || []) {
    if (o.family && !seen.has(o.familyKey)) seen.set(o.familyKey, { name: o.family, color: o.color, start: o.start });
  }
  if (seen.size) return { t: `${t.name}의 갈래 — 같은 색은 나라 너머 같은 갈래`, l: [...seen.values()].sort((a, b) => a.start - b.start).map(f => [f.name, color(f.color, 0xa4b1b7)]) };
  if (t.id !== 'faction') return null;
  const gs = (model.groups || []).filter(g => g.type !== 'coalition' && g.type !== 'regime' && (g.powerSpans || []).length && (g.withinList || []).some(w => w.polity));
  return gs.length ? { t: `${t.name} — 칸 색은 집권한 단체의 색 · 두 색은 연정`, l: gs.map(g => [g.name, color(g.color, 0xa4b1b7)]) } : null;
}

export function contribute(ctx, out) {
  const { tl, HT, model } = ctx;
  const bandOf = ctx.shared.bandOf;
  assert.ok(bandOf, '렌즈: 띠 모듈(bands)이 먼저 돌아야 합니다');
  const notes = { 렌즈: 0, 칸: { 제도: 0, 단체: 0, 연정: 0, 지위대신: 0, 내린지도자: 0 }, 가림: 0, 딸린항목: 0, 자리트랙: 0, 사건: 0 };
  const themes = model.themes || [];
  if (!themes.length) {
    ctx.notes.렌즈 = notes;
    return;
  }

  /* ── ② 렌즈 켬 줄 배치: 지도자 자리가 있는 트랙(HT.lensAny인 정권이 있는 트랙) — 지금 연표의 _layoutTrack을 렌즈 켬으로 한 번 더 돌려 대조한다 ── */
  const slot = [];
  const trackHas = tl.tracks.map(tr => tr.periods.some(p => HT.lensAny(p)));
  tl.tracks.forEach((tr, i) => {
    if (trackHas[i]) slot.push(tr.id);
  });
  notes.자리트랙 = slot.length;
  if (slot.length) {
    const before = tl.tracks.map(tr => ({ leader: tr.geo.leaderH > 0, rowHs: tr.rowHs.slice(), height: tr.height }));
    const was = tl.themeLens;
    tl.themeLens = { id: '*', name: '*', color: '#a4b1b7' }; // 렌즈 켬 배치는 themeLens가 있는지만 본다(설계 10-3)
    try {
      for (const tr of tl.tracks) tl._layoutTrack(tr);
      tl.tracks.forEach((tr, i) => {
        const want = before[i].leader || trackHas[i];
        assert.equal(tr.geo.leaderH > 0, want, `렌즈 켬 배치: 트랙 ${tr.id}의 지도자 자리가 ${tr.geo.leaderH > 0}(기대 ${want})`);
        // 지도자 자리가 새로 생긴 트랙만 줄마다 LEADER_SLOT(현재 22 + 3)만큼 늘고(접힌 줄 · 그 밖 줄은 0 그대로), 나머지 트랙은 1px도 그대로다.
        const grow = !before[i].leader && trackHas[i];
        tr.rowHs.forEach((h, r) => {
          const old = before[i].rowHs[r];
          const ok = grow ? h === old || h === old + LEADER_SLOT : h === old;
          assert.ok(ok, `렌즈 켬 배치: 트랙 ${tr.id} 줄 ${r}의 높이 ${old} → ${h}`);
        });
      });
    } finally {
      tl.themeLens = was || null;
      for (const tr of tl.tracks) tl._layoutTrack(tr);
    }
  }

  /* ── ① 렌즈마다 변형 하나: 칸 종류 8 + 구역 43 + 가림 ─────────────────────────────── */
  const cellsOfBand = new Map(); // 띠 uid → 그 띠의 칸 자리(앞선 모듈이 실은 것 — 변형 판까지)
  out.cells.forEach((c, i) => {
    if (!cellsOfBand.has(c.period)) cellsOfBand.set(c.period, []);
    cellsOfBand.get(c.period).push(i);
  });
  const variants = (out.variants = out.variants || []);
  const lensOf = new Map(); // 주제 id → x_lens.themes의 칸
  const evHit = new Map(); // 주제 id → 그 주제의 사건 uid(모델)
  for (const t of themes) evHit.set(t.id, new Set());
  for (const e of model.events || []) {
    for (const t of themes) if (HT.lensEventHit(e, t.id)) evHit.get(t.id).add(e.uid);
  }

  for (const t of themes) {
    const key = `theme:${t.id}`;
    const vCells = [], vItems = [], hides = [];
    const count = { 제도: 0, 단체: 0, 연정: 0, 지위대신: 0, 내린지도자: 0 };
    tl.tracks.forEach((tr, trackIndex) => {
      for (const p of tr.periods) {
        if (p._overlay || !bandOf.has(p.uid)) continue;
        const L = HT.lensCellsOf(p, t.id);
        if (!L.src) continue; // 자료 없는 나라: 지도자 칸이 그대로 남는다(앱이 .4로)
        const band = out.periods[bandOf.get(p.uid)];
        const geo = tr.geos[p._row] || tr.geo;
        /** 칸 하나를 띠 안으로 잘라 싣는다(strips.mjs의 put과 같은 자르기). 실었으면 그 칸. */
        const put = (lane, s, e, name, style, col) => {
          if (s == null || e == null || !name) return null;
          if (s > band.end || e < band.start) return null;
          const start = Math.max(s, band.start), end = Math.max(start, Math.min(e, band.end));
          const cell = { period: p.uid, kind: KIND_COMMON, lane, start, end, name, style, color: col || 0, variant: key };
          vCells.push(cell);
          return cell;
        };
        /* 가림: 이 나라의 지도자 칸(지위로 대신하면 지위 칸도 · 붕당의 맞바꿈이면 집권 단 칸도) — 앞선 모듈이 실은 것 전부(변형 판 포함) */
        const swapPower = L.src === 'group' && !!geo.powerH;
        for (const at of cellsOfBand.get(p.uid) || []) {
          const k = out.cells[at].kind;
          if (k === STRIP.leader || (L.src === 'rank' && k === STRIP.rank) || (swapPower && k === KIND_COMMON && out.cells[at].lane === LENS_LANE.power)) hides.push({ kind: 3, at });
        }
        /** 가린 지도자 칸을 덧단 자리(단 lane)에 작게(갈래 4 — 지도자 칸의 무리 · 번갈아 짙기 · 순번 그대로). */
        const downLeaders = lane => {
          let prevKey = null;
          p.leaders.forEach((c, i) => {
            const k = c.dynasty || c.dynastyAuto || '';
            const style = styleWith(cellStyle(c) | (prevKey !== null && prevKey === k ? ST.joinL : 0), i % 2 === 1, i) | (LENS_BAND.leader << BAND_SHIFT);
            if (put(lane, minute(c.start), minute(c.end ?? p.endY), HT.leaderLabel(c, 'auto', false), style, 0)) count.내린지도자++;
            prevKey = k;
          });
        };
        if (L.src === 'rank') {
          /* 체제를 지위 변천으로 대신: 지위 칸을 지도자 자리에(갈래 3 — 지위 칸의 서열 · 이음 · 미정 그대로, 순번은 지위 칸 참조 rank:i) */
          let first = true;
          for (const c of p.rankSpans) {
            const style = styleWith(cellStyle(c) | (first ? 0 : ST.joinL) | (Math.min(7, (c.level || 0) + 1) << ST_RANK), false, c.i) | (LENS_BAND.rank << BAND_SHIFT);
            if (put(LENS_LANE.leader, minute(c.start), minute(c.end), c.name || '', style, 0)) count.지위대신++;
            first = false;
          }
          /* 그 줄에 지위 단이 있으면 지도자 칸을 지위 단 자리로 */
          if (geo.rankH && p.leaders && p.leaders.length) downLeaders(LENS_LANE.rank);
          continue;
        }
        /* 붕당의 맞바꿈: 그 줄에 집권 단이 있으면 지도자 칸을 집권 단 자리로(웹은 표시 체크 '지도자'를 끈 동안 비우고, 앱은 그때 갈래 4를 그리지 않는다) */
        if (swapPower && p.leaders && p.leaders.length) downLeaders(LENS_LANE.power);
        /* 제도 칸 · 붕당의 단체 칸(= 집권 단의 칸 — 지도자 자리 · 날짜 차례 한 줄 · 이어지면 긴 둥근 칸) */
        const group = L.src === 'group';
        L.cells.forEach((c, j) => {
          if (!c.name) return;
          const two = group && (c.n || 1) > 1;
          const s = minute(c.start == null || !isFinite(c.start) ? p.start : c.start);
          const e = minute(c.end == null || !isFinite(c.end) ? p.endY : c.end);
          const style = styleWith((c.startUnknown ? ST.unkS : 0) | (c.endUnknown ? ST.unkE : 0) | (j > 0 ? ST.joinL : 0) | (group ? ST.tagged : 0), false, j) |
            ((group ? LENS_BAND.group : LENS_BAND.inst) << BAND_SHIFT);
          const name = group ? `${c.short || [...c.name][0] || ''}\t${c.name}` : c.name;
          const cell = put(LENS_LANE.leader, s, e, name, style, color(c.color, 0xa4b1b7));
          if (!cell) return;
          if (!group) count.제도++;
          else if (two || c.solo) count.연정++;
          else count.단체++;
          // 색 점(웹의 `.gd`): 연정은 함께 집권한 단체 전부의 색, 짝을 모르는 연정은 제 색 하나, 한 단체의 집권은 없음.
          const dots = !group ? [] : c.solo ? [c.color] : two ? c.colors || [] : [];
          const dotText = dots.length ? `\t${dots.map(x => color(x, 0xa4b1b7).toString(16).padStart(6, '0')).join(',')}` : '';
          vItems.push({
            section: SECTION_ITEM, track: trackIndex, row: band.row, row2: band.row, start: cell.start, end: cell.end, lod: lodOf(cell.end - cell.start),
            ref: p.uid, name: group ? '' : c.fam || '', color: two && c.color2 ? color(c.color2, 0) : 0, a: KIND_COMMON, b: LENS_LANE.leader, c: Math.min(4095, j + 1),
            d: group && c.solo ? 1 : 0, text2: (c.uid || '') + dotText, variant: key,
          });
        });
      }
    });
    const entry = { id: t.id, hint: HT.themeHint(t), has: HT.lensHasData(model, t.id) ? 1 : 0 };
    if (t.hidden) entry.hidden = 1;
    if (vCells.length) {
      out.cells.push(...vCells);
      out.items.push(...vItems);
      variants.push({ key, kind: VARIANT_KIND_THEME, track: 0, band: '', uid: t.id, name: t.name || t.id, rows: [], moves: [], groups: [], hides, notes: '' });
      entry.v = 1;
      notes.렌즈++;
      notes.가림 += hides.length;
      notes.딸린항목 += vItems.length;
      for (const k of Object.keys(count)) notes.칸[k] += count[k];
    }
    const sw = swatchesOf(model, t);
    if (sw) entry.sw = sw;
    const hit = evHit.get(t.id);
    if (hit.size) {
      // 타일의 사건은 자리마다 uid가 다르다(공동 사건의 다른 자리는 `#n` — rails.mjs의 eventUid). 그 자리들을 모두 싣는다.
      entry.ev = out.events.filter(e => hit.has(e.uid.split('#')[0])).map(e => e.uid);
      notes.사건 += entry.ev.length;
    }
    lensOf.set(t.id, entry);
  }

  /* ── ③ 항목 기록 themes에 x_lens — 렌즈로 말할 것이 있을 때만(없으면 기록 바이트 그대로) ── */
  const list = themes.map(t => lensOf.get(t.id));
  const worth = slot.length > 0 || list.some(x => x.has || x.hidden || x.v || x.sw || x.ev) || themes.some(t => t.kind);
  if (worth) {
    const rec = out.entities.find(e => e.uid === 'themes' && e.kind === 'themes');
    assert.ok(rec, '렌즈: 항목 기록 themes가 없습니다(entities 모듈이 먼저 돌아야 합니다)');
    const body = JSON.parse(rec.json);
    body.x_lens = { slot, themes: list };
    rec.json = JSON.stringify(body);
  }
  ctx.notes.렌즈 = notes;
}

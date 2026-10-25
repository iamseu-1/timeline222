// 트랙 · 줄 · 민족 묶음 · 분류 · 공통 시대 구분. 2단계의 값(모두 켠 · 자동 밀도의 굳은 자리)에서 출발해 3단계의 새 값(계약 1 · 3 · 4절)을 더한다.
// 자체 점검: 계약 3절의 식으로 줄을 다시 쌓은 결과가 지금 연표의 _layoutTrack이 낸 값과 1px도 다르지 않아야 한다.
import { assert } from './base.mjs'; // 노드에서는 node:assert/strict 그대로(브라우저 겸용 — base.mjs 머리말)
import { minute, color } from './base.mjs';

/** 계약 3절의 상수 — js/timeline.js의 G와 같은 값(웹 코드는 읽기만 하므로 여기에 옮겨 적고, 다르면 자체 점검이 알려 준다). */
// 통합 2026-10-13: 글줄(크기 × 1.2)과 테두리 사이 최소 3px, 단 사이 최소 3px.
const G = {
  pad: 9, inset: 4, slotGap: 3, line: 21, railPitch: 7,
  dynasty: 20, leader: 22, cabinet: 21, organ: 20, dep: 20,
  zoneTab: 20, zoneGap: 3, gap: 8, memberGap: 6, groupGap: 14,
  folded: 34, foldedGroup: 30, hem: 21, tab: 18,
  figure: 20, figGap: 3, phase: 20, phaseGap: 3, rank: 20, rankGap: 3,
  power: 20, powerGap: 3,
  hang: 13, // 매달린 속국 이름표 한 줄(timeline.js의 HANG.pitch — 건의 8의 나 · 2026-10-14 "크기만 줄이자" · 글 틈 때문에 12 → 13 · 구역 탭은 zoneTab + zoneGap 그대로)
};

/** 계약 3절의 '띠 안' 그대로 위에서부터 쌓는다.
    on = 트랙 단위로 있고 없는 단 { dynasty, leader, cabinet, organ }, n = 줄 단위 수 { lines, phase, rank, power, real, fig, dep, railLevels }.
    power · real = 단체 단(설계 7-8 결정 1 A 집권 · 2 A 실권 — 지위 단 아래 · 지도자 칸 위의 줄 단위 덧단 13 + 틈 2, 위 = 집권 · 아래 = 실권) — 없으면 예전 식 그대로 */
function stackBand(on, n) {
  let y = G.inset;
  const dynastyTop = y;
  if (on.dynasty) y += G.dynasty + G.slotGap;
  const phaseTop = y;
  y += n.phase * (G.phase + G.phaseGap);
  const rankTop = y;
  if (n.rank) y += G.rank + G.rankGap;
  const powerTop = y;
  if (n.power) y += G.power + G.powerGap;
  const realTop = y;
  if (n.real) y += G.power + G.powerGap;
  const leaderTop = y;
  if (on.leader) y += G.leader + G.slotGap;
  const cabinetTop = y;
  if (on.cabinet) y += G.cabinet + G.slotGap;
  const textTop = y;
  y += n.lines * G.line;
  const railTop = y;
  const railH = n.railLevels * G.railPitch;
  y += railH;
  const figTop = y + G.slotGap;
  const figH = n.fig ? n.fig * G.figure + (n.fig - 1) * G.figGap : 0;
  const depTop = figH ? figTop + figH + G.slotGap : y + G.slotGap;
  const organTop = depTop + (n.dep ? n.dep + G.slotGap : 0);
  const rowH = (on.organ ? organTop + G.organ : n.dep ? depTop + n.dep : figH ? figTop + figH : railTop + railH) + G.inset;
  return { dynastyTop, phaseTop, rankTop, powerTop, realTop, leaderTop, cabinetTop, textTop, railTop, figTop, figH, depTop, organTop, rowH };
}

/** 줄 단위 트랙 값(계약 3절 끝 · 6-5절)을 `figWide` 한 정수에 담는 꼴.
    비트 0~2 넉넉하게의 인물 단 수(0~3) · 비트 3~5 **그 줄의 기간 막대 단 수 + 1**(0이면 실리지 않음) · 비트 6 **그 줄의 기관 칸** ·
    비트 9~13 **그 줄에 매달린 속국 이름표 줄 수**(0~31 — 아래 주석).
    엔진은 이 열을 정수로 나르기만 하고 뜻을 모른다 — 푸는 곳은 여기와 화면 쪽 `layout.dart`뿐이다. */
export const packRowValues = (figWide, rail, organ, power = false, real = false, hang = 0) =>
  (figWide & 7) | (((rail + 1) & 7) << 3) | ((organ ? 1 : 0) << 6) | ((power ? 1 : 0) << 7) | ((real ? 1 : 0) << 8) | ((Math.min(hang, 31) & 31) << 9);
/* 비트 7 · 8(2026-10-12 · D5 결정 1 A · 2 A의 새 앱 몫): **그 줄에 집권 단 · 실권 단이 있는가**(단체 단 — 줄 단위 덧단 20 + 3, 위 = 집권 · 아래 = 실권).
   엔진은 이 열을 정수로 나르기만 하므로 엔진 · 스키마를 고치지 않고 화면 쪽 `layout.dart`(`RowSpec.power` · `real`)가 푼다.
   단체 자료가 없는 줄은 0이라 옛 저장소 · 옛 자료의 값이 바이트까지 그대로다(비트 3~5가 0인 옛 저장소에서는 읽지 않는다).
   비트 9~13(2026-10-14 · 건의 8의 나 — 감독 "크기만 줄이자"): **그 줄에 매달린 속국 이름표 줄 수**(지금 연표의 tr.hangRowLanes — 그 줄 상국들의 outLanes 가운데 큰 값).
   매달린 줄은 한 줄 13px(G.hang)로 구역 탭(23)과 높이가 달라, 줄의 `zones`(구역 탭 줄 + 매달린 줄)만으로는 덧붙는 높이를 셀 수 없다 —
   덧붙는 높이 = 매달린 줄 × 13 + (zones − 매달린 줄) × 23 + 3. 매달린 탭이 없는 줄은 0이라 값이 바이트까지 그대로다. 화면 쪽 `layout.dart`가 푼다(접기 단추로 접으면 그 상국 몫을 뺀다).
   비트 14(2026-10-15 · 꼬리표 갈래 E — 설계 4-1 '실제 띠에 입힘'): **그 줄에 위로 솟는 것이 있는가** — 구역 47(섬기는 띠의 받침 카드 + 상국 탭 ·
   연합의 겹 탭)을 실은 줄. 새 앱은 띠 위 탭 줄이 없어 이런 줄만 위 틈을 15 더 둔다(`layout.dart`의 `RowSpec.raised` · `G.raise`).
   구역 47은 다른 모듈(hangs.mjs · power.mjs)이 싣으므로 모든 모듈이 끝난 뒤 [contributeLate]가 켠다. 지금 연표의 줄 쌓기와는 상관없는 값이라
   자체 점검(계약 3절의 식 대조)에는 들지 않는다. 소속 펼치기 · 대범위 변형이 새로 만든 줄에는 아직 싣지 않는다.
   비트 15(2026-10-15 · 리메이크 조각 ③ — 설계 4-1 '줄 위 틈 — 그릇 안 15'): **그 줄이 그릇의 줄인가** — 구역 50(풀린 그릇의 열쇠표)을 실은 줄.
   풀렸을 때는 띠 위에 열쇠표가, 펼쳤을 때는 매다는 실이 들 자리라 위 틈을 15로 둔다(`layout.dart`의 `RowSpec.contained` · `G.contain`).
   비트 14와 같이 [contributeLate]가 켜고, 자체 점검에는 들지 않는다.
   비트 16 · 17 · 18 · 19(2026-10-15 · 리메이크 2부 — 목업 서고 "칸은 그 줄에 있을 때만"): **그 줄에 왕조 · 지도자 · 내각 칸이 있는가**(strips.mjs가 실은
   칸 종류 0 · 1 · 2)와 **세 비트를 실었다는 표시**(19). 19가 선 줄은 화면이 트랙 값(트랙에 하나라도 있으면 모든 줄에 층) 대신 줄 값으로 흰 층을 둔다
   (`layout.dart`의 `RowSpec.cellRows`) — 지금 연표의 줄 쌓기와는 다른 값이라 자체 점검에는 들지 않는다. 옛 저장소는 19가 없어 트랙 값 그대로다.
   비트 20(2026-10-15 · 리메이크 2부 · 감독 결정 '두 장 ㄴ'): **그 줄에 사건이 있는가** — 있으면 몸통 띠 아래에 흰 사건 칸(18)을 둔다(`RowSpec.events`).
   19가 없는 옛 저장소는 늘 둔다. 띠의 look 비트 19 · 20(그 띠에 사건 · 칸이 있는가 — 몸통 띠를 어디까지 그릴지)과 21~29(그 띠가 가진 칸 층 —
   왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관: 몸통을 제 마지막 칸 층까지만)도 같은 차례에 켠다. */

/** 그 줄에 기관 칸이 있는가 — 기관(구역이 아닌 얹힌 정권)이 얹히는 **모든** 상위 줄(지금 연표 _layoutTrack 2-2와 같은 길).
    지금 연표의 트랙 값 `organ`은 "보이는 상위 줄을 하나라도 가진 기관이 있는가"라, 줄마다의 값을 보이는 줄에서 OR 하면 같은 답이 된다. */
function organRowsOf(tr) {
  const inTrack = new Map(tr.periods.map(p => [p.uid, p]));
  const rows = new Set();
  for (const p of tr.periods) {
    if (!p._overlay || p.scale === 'zone') continue;
    for (const h of p.hosts || []) {
      let host = inTrack.get(h.host.uid);
      while (host && host._hidden) host = host._host;
      if (host && host._row != null && !tr.foldedRows.has(host._row)) rows.add(host._row);
    }
  }
  return rows;
}

/** 줄마다의 기간 막대 단 수(0~3) — 지금 연표 _layoutTrack 4)의 railLevels 셈을 줄 하나씩 따로 한 것.
    트랙 값은 `max(2, 보이는 줄들의 최댓값)`이다(접힌 민족 줄에 합쳐진 줄은 사건이 빠져 0이 된다). */
function railRowsOf(HT, tr) {
  return (tr.eventsByRow || []).map(list => {
    const segs = (list || [])
      .filter(e => !e.parentUid && (e.endY - e.start > 0 || e.startRange || e.endRange || HT.datedAlts(e).length))
      .map(e => {
        const ys = [e.start, e.endY];
        if (e.startRange) ys.push(...e.startRange);
        if (e.endRange) ys.push(...e.endRange);
        HT.datedAlts(e).forEach(a => ys.push(a.start, a.end ?? a.start));
        return [Math.min(...ys), Math.max(...ys)];
      })
      .sort((a, b) => a[0] - b[0]);
    const ends = [];
    for (const [s, e] of segs) {
      const i = ends.findIndex(end => end < s);
      if (i < 0) ends.push(e);
      else ends[i] = e;
    }
    return Math.min(3, ends.length);
  });
}

/** 인물 단의 단 수를 줄마다 — 지금 연표의 _layoutTrack 4)와 같은 규칙(중요도 높은 순 → 시작 순, 최대 figMax단).
    tr.figures의 lvl은 건드리지 않는다(자동 밀도의 값은 _layoutTrack이 이미 적어 두었다). */
function figLevelsOf(tl, tr, figMax) {
  const rows = tr.rowPeriods.map(() => 0);
  if (!figMax) return rows;
  const byRow = new Map();
  for (const x of tr.figures || []) if (x.row != null) byRow.set(x.row, (byRow.get(x.row) || []).concat([x]));
  for (const [r, list] of byRow) {
    const levels = Array.from({ length: figMax }, () => []);
    const lvlOf = new Map();
    const sorted = list.slice().sort((a, b) => (b.f.importance || 2) - (a.f.importance || 2) || a.s.start - b.s.start || a.s.endY - b.s.endY);
    for (const x of sorted) {
      const [lo, hi] = tl._figSpan(x.s);
      const free = l => !levels[l].some(([a, b]) => a < hi && lo < b);
      const want = lvlOf.get(x.f.uid);
      const l = want != null && free(want) ? want : levels.findIndex((_, i) => free(i));
      if (l < 0) continue;
      levels[l].push([lo, hi]);
      lvlOf.set(x.f.uid, l);
      rows[r] = Math.max(rows[r], l + 1);
    }
  }
  return rows;
}

export function contribute(ctx, out) {
  const { tl, model, HT } = ctx;

  /* 분류: tl._cats의 순번(i) 차례대로 — 이 배열에서의 자리가 곧 '분류 번호'다(계약 4절). */
  const cats = [...tl._cats.entries()].sort((a, b) => a[1].i - b[1].i);
  const catNo = (ctx.shared.catNo = new Map());
  cats.forEach(([id, c], n) => {
    catNo.set(id, n);
    out.categories.push({ key: id, name: c.name || id, color: color(c.color, 0xa4b1b7) });
  });
  ctx.notes.분류_번호가_순번과_다름 = cats.filter(([, c], n) => c.i !== n).length;

  for (const e of model.epochs || []) {
    const start = minute(e.start), end = minute(e.endY ?? e.end ?? e.start);
    if (!e.track && start != null && end != null && end >= start) out.epochs.push({ start, end, color: color(e.color, 0xc8b193), name: e.name || '' });
  }

  const diffs = []; // 계약 3절의 식과 지금 연표가 다른 곳
  const note = (where, want, got) => { if (Math.abs(want - got) > 0.001) diffs.push(`${where}: 계약 ${want} ≠ 연표 ${got}`); };

  for (const tr of tl.tracks) {
    const on = {
      dynasty: tr.geo.dynastyH > 0 ? 1 : 0, leader: tr.geo.leaderH > 0 ? 1 : 0,
      cabinet: tr.geo.cabinetH > 0 ? 1 : 0, organ: tr.geo.organH > 0 ? 1 : 0,
    };
    const railLevels = tr.geo.railLevels;
    // 집합 보기의 판 트랙(tr.board)은 원래 트랙이 바뀌는 곳(원래 트랙 칩 — gp.from)만 묶음 틈 — 지금 연표의 _layoutTrack 4) · 5)와 같다(js/timeline.js 'groupStart').
    // 판 트랙이 아니면 지금과 같다(기본 상태의 내보내기에는 판 트랙이 없다 — 1바이트도 달라지지 않는다).
    const groupStart = new Set(tr.groups.filter(gp => !tr.board || gp.from).map(gp => gp.first));
    const figWideRows = figLevelsOf(tl, tr, 3); // 넉넉하게(3단)에서의 인물 단 수
    /* 줄 단위 트랙 값(계약 3절 끝): 민족을 접거나 소속을 펼치면 지금 연표는 트랙 값(기관 칸 · 기간 막대 단 수)을 다시 셈한다.
       저장소에 '모두 편' 값 하나만 두면 접힌 민족 줄에서 띠가 23px 높아진다(실측 9.3) — 줄마다의 값을 함께 실어,
       화면이 '보이는 줄들의 최댓값'으로 다시 셈하게 한다. */
    const organRows = organRowsOf(tr);
    const railRows = railRowsOf(HT, tr);
    {
      const live = [...Array(tr.rows).keys()].filter(r => !tr.foldedRows.has(r));
      note(`${tr.id} 기간 막대 단 수`, Math.max(2, ...live.map(r => railRows[r] || 0)), railLevels);
      note(`${tr.id} 기관 칸`, live.some(r => organRows.has(r)) ? 1 : 0, on.organ);
    }

    const rows = [];
    let y = G.pad; // 계약 3절로 다시 쌓아 보는 세로 자리
    for (let r = 0; r < tr.rows; r++) {
      const geo = tr.geos[r] || tr.geo;
      const slotTop = r === 0 ? 0 : tr.rowTop[r] - tr.rowGap[r];
      const slotEnd = r === tr.rows - 1 ? tr.height : tr.rowTop[r + 1] - tr.rowGap[r + 1];
      const bandTop = Math.round(tr.rowTop[r] - slotTop);
      const at = (top, h) => (h > 0 ? Math.round(bandTop + top) : -1);
      const folded = tr.foldedRows.has(r);
      const member = tr.memberRows.has(r);
      const common = r === tr.commonRow;
      const rowCats = (tr.rowCats && tr.rowCats[r]) || null;
      const n = {
        lines: geo.lines,
        phase: Math.round((geo.phaseH || 0) / (G.phase + G.phaseGap)),
        rank: geo.rankH ? 1 : 0,
        power: geo.powerH ? 1 : 0,
        real: geo.realH ? 1 : 0,
        fig: geo.figLevels || 0,
        dep: geo.depH || 0,
        railLevels,
      };
      const hl = folded ? 0 : tr.hangRowLanes.get(r) || 0; // 매달린 속국 이름표 줄(한 줄 13)
      const zl = tr.zoneRowLanes.get(r) || 0; // 구역 탭 줄(한 줄 20 + 3)
      const zones = zl + (tr.hangRowLanes.get(r) || 0);
      const hem = tr.underRowSet.has(r) ? 1 : 0;
      const scopePad = tl._scopePad(tr, r, r - 1);

      /* --- 자체 점검: 계약 3절의 식으로 다시 쌓기 --- */
      const s = stackBand(on, n);
      const where = `${tr.id}#${r}`;
      if (!folded) {
        note(`${where} 왕조 단 위`, s.dynastyTop, geo.dynastyTop);
        note(`${where} 시기 단 위`, s.phaseTop, geo.phaseTop);
        note(`${where} 지위 단 위`, s.rankTop, geo.rankTop);
        if (n.power) note(`${where} 집권 단 위`, s.powerTop, geo.powerTop);
        if (n.real) note(`${where} 실권 단 위`, s.realTop, geo.realTop);
        note(`${where} 지도자 단 위`, s.leaderTop, geo.leaderTop);
        note(`${where} 내각 단 위`, s.cabinetTop, geo.cabinetTop);
        note(`${where} 글줄 위`, s.textTop, geo.textTop);
        note(`${where} 기간 막대 위`, s.railTop, geo.railTop);
        note(`${where} 인물 단 위`, s.figTop, geo.figTop);
        note(`${where} 예속 칸 위`, s.depTop, geo.depTop);
        note(`${where} 기관 단 위`, s.organTop, geo.organTop);
        note(`${where} 띠 높이`, s.rowH, geo.rowH);
      }
      const cut = folded ? 0 : (hl + zl ? hl * G.hang + zl * (G.zoneTab + G.zoneGap) + 3 : 0) + (hem ? G.hem : 0);
      note(`${where} 줄 밑에 덧붙은 높이`, cut, tr.rowCut[r]);
      const h = folded ? G.foldedGroup : s.rowH + cut;
      note(`${where} 줄 높이`, h, tr.rowHs[r]);
      const tab = folded || common ? 0 : G.tab;
      const crosses = groupStart.has(r);
      const gap = (r === 0 ? 0 : member && !crosses ? G.memberGap : G.gap + (crosses ? G.groupGap : 0)) + tab + scopePad;
      note(`${where} 줄 위의 틈`, gap, tr.rowGap[r]);
      y += gap;
      note(`${where} 줄의 위 자리`, y, tr.rowTop[r]);
      y += h;

      rows.push({
        height: Math.round(slotEnd - slotTop), bandTop, bandH: Math.round(geo.rowH),
        dynTop: at(geo.dynastyTop, geo.dynastyH), leadTop: at(geo.leaderTop, geo.leaderH), cabTop: at(geo.cabinetTop, geo.cabinetH),
        textTop: Math.round(bandTop + geo.textTop), lines: geo.lines, railTop: Math.round(bandTop + geo.railTop), organTop: at(geo.organTop, geo.organH),
        kind: folded ? 3 : common ? 2 : member ? 1 : 0,
        groupStart: crosses ? 1 : 0, scopePad: Math.round(scopePad), phase: n.phase, rank: n.rank,
        cats: rowCats ? rowCats.map(id => (catNo.has(id) ? catNo.get(id) : 0)) : [],
        fig: n.fig, dep: n.dep ? Math.round((n.dep + G.slotGap) / (G.dep + G.slotGap)) * 13 - 1 : 0, zones, hem, // dep 저장 형식은 옛 12px + 틈 1 그대로; 화면만 새 기하로 환산
        // 넉넉하게의 인물 단 수와 줄 단위 트랙 값을 한 정수에 담는다(packRowValues의 주석 · 계약 6-5절).
        figWide: packRowValues(Math.max(folded ? 0 : figWideRows[r] || 0, n.fig), folded ? 0 : railRows[r] || 0, !folded && organRows.has(r), !folded && !!n.power, !folded && !!n.real, hl),
      });
    }
    note(`${tr.id} 트랙 높이`, Math.max(y + G.pad, G.folded), tr.height);

    const groups = tr.groups.map(gp => ({
      depth: gp.depth, first: gp.first, count: gp.count, name: gp.name || '',
      color: color(gp.color, 0xa4b1b7), kind: gp.scope ? 2 : gp.culture ? 1 : 0,
    }));
    out.tracks.push({
      // key = 트랙의 글자 id(`mw-coast`). 항목 기록(entities)의 `track`이 이 글자라, 대범위 칩이 제 트랙을 찾는다(계약 4절).
      key: tr.id, name: tr.name || tr.id, color: color(tr.color, 0xc27a45),
      dynasty: on.dynasty, leader: on.leader, cabinet: on.cabinet, organ: on.organ, railLevels,
      rows, groups,
      // 이 트랙을 처음 말한 DLC의 순번(여러 DLC가 같은 트랙에 얹을 수 있다 — 지금 연표의 addTrack).
      pack: ctx.trackPack.get(tr.id) ?? 0,
      // 문화권(리메이크 조각 ② — 켠 DLC의 spheres에 만든 id · 적지 않은 트랙은 빈 글 = 문화권 없음 · 2026-10-23부터 프로그램에 든 문화권은 없음). 모델이 트랙을 문화권 차례로 이미 세워 두었다.
      sphere: tr.sphere || '',
    });
  }
  assert.equal(diffs.length, 0, `계약 3절의 줄 쌓기와 지금 연표가 다릅니다(${diffs.length}곳):\n  ${diffs.slice(0, 12).join('\n  ')}`);
  ctx.notes.줄_쌓기_대조 = { 맞음: out.tracks.reduce((a, t) => a + t.rows.length, 0), 다름: diffs.length };
}

/** 늦은 차례(모든 모듈이 항목을 실은 뒤): 구역 47(받침 카드 + 상국 탭 · 연합의 겹 탭)을 실은 줄에 `figWide` 비트 14(위로 솟는 것)를,
    구역 50(풀린 그릇의 열쇠표)을 실은 줄에 비트 15(그릇의 줄)를 켠다.
    비트 3~5(기간 막대 + 1)가 0인 줄은 옛 저장소로 읽히므로(layout.dart) 켜지 않는다. */
export function contributeLate(ctx, out) {
  spheresLate(ctx, out);
  let n = 0;
  for (const it of out.items) {
    if (it.section !== 47) continue;
    const rec = out.tracks[it.track] && out.tracks[it.track].rows[it.row];
    if (!rec || !((rec.figWide >> 3) & 7) || rec.figWide & (1 << 14)) continue;
    rec.figWide |= 1 << 14;
    n++;
  }
  ctx.notes.솟는_줄 = n;
  let m = 0;
  for (const it of out.items) {
    if (it.section !== 50) continue;
    const rec = out.tracks[it.track] && out.tracks[it.track].rows[it.row];
    if (!rec || !((rec.figWide >> 3) & 7) || rec.figWide & (1 << 15)) continue;
    rec.figWide |= 1 << 15;
    m++;
  }
  ctx.notes.그릇_줄 = m;
  // 비트 16~19: 줄마다 왕조 · 지도자 · 내각 칸이 있는가(위 주석) — 칸이 매인 띠의 줄로 센다.
  const at = new Map(out.periods.map(p => [p.uid, p]));
  const bits = new Map();
  for (const cell of out.cells || []) {
    if (!(cell.kind >= 0 && cell.kind <= 2)) continue;
    const p = at.get(cell.period);
    if (!p) continue;
    const key = `${p.track}|${p.row}`;
    bits.set(key, (bits.get(key) || 0) | (1 << (16 + cell.kind)));
  }
  /* 비트 20 · 띠 look 비트 19 · 20(리메이크 2부 · 감독 결정 '두 장 ㄴ' — 얇은 이름 색줄 + 몸통 띠(칸 뭉치 + 흰 사건 칸)):
     줄에 사건이 있는가(사건 칸을 둘지 — 변형이 옮긴 사건 · 변형에만 있는 사건도) · 띠에 사건 · 칸이 있는가(몸통 띠를 어디까지 그릴지).
     띠를 적지 않은 사건은 같은 줄에서 그 해를 덮는 띠의 것으로 센다. */
  const evRows = new Set(), evBands = new Set(), cellBands = new Set();
  const byRow = new Map();
  for (const p of out.periods) {
    const key = `${p.track}|${p.row}`;
    (byRow.get(key) || byRow.set(key, []).get(key)).push(p);
  }
  for (const e of out.events || []) {
    const key = `${e.track}|${e.row}`;
    evRows.add(key);
    if (e.band && at.has(e.band)) evBands.add(e.band);
    else {
      const p = (byRow.get(key) || []).find(q => q.start <= e.start && e.start <= q.end);
      if (p) evBands.add(p.uid);
    }
  }
  for (const v of out.variants || []) for (const m of v.moves || []) if (m.kind === 2) evRows.add(`${m.track}|${m.row}`);
  /* 띠 look 비트 21~29: 그 띠가 가진 칸 층(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관) — 몸통 띠를 제 마지막 칸 층까지만 두고
     사건 칸을 그 바로 밑에 붙인다(한 줄에 이은 띠들이 칸 층을 나눠 써도 제 몸통은 제 것만 — 고려 = 색줄 + 무신 정권 단 + 사건 칸). 렌즈 칸(종류 8의 단 0 · 1)은 지도자 · 지위 자리 */
  const FLOOR = { 0: 21, 4: 22, 5: 23, 1: 26, 2: 27, 7: 28, 3: 29 };
  const floors = new Map();
  for (const cell of out.cells || []) {
    cellBands.add(cell.period);
    const bit = cell.kind === 8 ? ({ 2: 24, 3: 25, 0: 26, 1: 23 })[cell.lane] : FLOOR[cell.kind];
    if (bit != null) floors.set(cell.period, (floors.get(cell.period) || 0) | (1 << bit));
  }
  for (const p of out.periods) p.look = (p.look || 0) | (evBands.has(p.uid) ? 1 << 19 : 0) | (cellBands.has(p.uid) ? 1 << 20 : 0) | (floors.get(p.uid) || 0);
  let k = 0;
  out.tracks.forEach((t, ti) => (t.rows || []).forEach((rec, ri) => {
    if (!rec || !((rec.figWide >> 3) & 7)) return;
    rec.figWide |= (bits.get(`${ti}|${ri}`) || 0) | (1 << 19) | (evRows.has(`${ti}|${ri}`) ? 1 << 20 : 0);
    k++;
  }));
  ctx.notes.칸_줄값 = k;
  ctx.notes.두장_몸통 = { 사건줄: evRows.size, 사건띠: evBands.size, 칸띠: cellBands.size };
}

/** 최상위 `spheres`(리메이크 조각 ②): 쓰인 문화권만 차례대로 `{ id, name, order, count, default }` — count = 그 문화권 트랙에 실린 띠 수(머리 단의 수),
    default = 처음 펼칠 문화권(첫 DLC — 기본팩이 처음 말한 트랙의 문화권 · 없으면 첫 문화권 — 설계 4-6 #1 A). 문화권이 없는 트랙(판 트랙)은 세지 않는다. */
function spheresLate(ctx, out) {
  const { HT } = ctx;
  const count = new Map();
  for (const t of out.tracks) if (t.sphere) count.set(t.sphere, 0);
  if (!count.size) return;
  for (const p of out.periods) {
    const t = out.tracks[p.track];
    if (t && t.sphere) count.set(t.sphere, count.get(t.sphere) + 1);
  }
  const first = out.tracks.find(t => t.sphere && t.pack === 0) || out.tracks.find(t => t.sphere);
  out.spheres = [...count.keys()]
    .map(id => HT.sphereOf(id))
    .sort((a, b) => a.order - b.order)
    .map(x => ({ id: x.id, name: x.name, order: x.order, count: count.get(x.id), default: x.id === first.sphere }));
  ctx.notes.문화권 = out.spheres.map(x => `${x.name} ${x.count}${x.default ? ' (처음 펼침)' : ''}`).join(' · ');
}

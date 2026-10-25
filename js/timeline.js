/* 역사 연표 — 타임라인 렌더러
   구조: 트랙(나라) → 민족 → 정권 띠 → [지도자 칸 / 내각 칸 / 사건 줄 / 기간 레일 칸].
   승계를 선언한 정권끼리 같은 줄을 쓰고, 건국·멸망 네모를 승계선으로 잇습니다.
   맨 위 날짜 칸에는 연도 · 간지 · 나라별 연호가 함께 놓입니다. */
(function () {
  'use strict';
  const HT = window.HT;

  /* 사건의 연대 범위는 자료를 배치할 때 한 번 정리합니다. 긴 기간·이설·정밀도 구간도 함께 찾고,
     결과는 원래 자료 순서로 돌려주어 중요도가 같은 사건의 이름 자리와 묶음 순서를 보존합니다. */
  function intervalIndex(items, extent) {
    const entries = items.map((item, order) => {
      const [lo, hi] = extent(item);
      return { item, order, lo, hi };
    }).sort((a, b) => a.lo - b.lo || a.order - b.order);
    const build = (lo, hi) => {
      if (lo >= hi) return null;
      const mid = (lo + hi) >>> 1, entry = entries[mid];
      const left = build(lo, mid), right = build(mid + 1, hi);
      return { entry, left, right, min: entries[lo].lo, max: Math.max(entry.hi, left ? left.max : -Infinity, right ? right.max : -Infinity) };
    };
    return build(0, entries.length);
  }
  function intervalVisit(node, lo, hi, take) {
    if (!node || node.max < lo || node.min > hi) return false;
    const e = node.entry;
    if (e.lo <= hi && e.hi >= lo && take(e)) return true;
    return intervalVisit(node.left, lo, hi, take) || intervalVisit(node.right, lo, hi, take);
  }
  function intervalQuery(index, lo, hi) {
    const found = [];
    intervalVisit(index, lo, hi, e => { found.push(e); return false; });
    return found.sort((a, b) => a.order - b.order).map(e => e.item);
  }
  const intervalHas = (index, lo, hi) => intervalVisit(index, lo, hi, () => true);
  /* 세로 자리·높이는 건드리지 않습니다. 화면과 그 주변만 채우며, 접혀 높이가 없는 줄은 비웁니다. */
  function visibleRows(tr, top, bottom, margin) {
    const rows = new Set();
    for (let r = 0; r < tr.rows; r++) if (tr.rowHs[r] > 0 && tr.rowTop[r] <= bottom + margin && tr.rowTop[r] + tr.rowHs[r] >= top - margin) rows.add(r);
    return rows;
  }

  const MIN_SPAN = 1.2 / 365.25; // 확대 한계: 하루 남짓 — 날·시각까지 (해보다 작은 눈금·달력은 js/calendar.js)
  const AXIS_STEPS = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000];
  const GUTTER = 196;
  const COL = { track: 24, people: 22 };
  const BOARD_ID = '__board'; // 집합 보기(10건 6)의 합성 트랙 id — 맨 위에 하나 (setBoard · _boardPlan)
  /* 줄 안의 자리(px): 위아래 여백 inset, 칸 사이 틈 slotGap. 띠 안의 도형은 띠 바깥 가장자리에서 bw+pad2 = 4px 안쪽에 둡니다 */
  // 통합 2026-10-13: 글줄(크기 × 1.2)과 테두리 사이 최소 3px, 단 사이 최소 3px.
const G = { pad: 9, inset: 4, slotGap: 3, line: 21, rail: 14, railPitch: 7, dynasty: 20, leader: 22, cabinet: 21, organ: 20, dep: 20, zoneTab: 20, zoneGap: 3, zoneLanes: 3, gap: 8, memberGap: 6, groupGap: 14, folded: 34, foldedGroup: 30, hem: 21, bw: 1, pad2: 3, sq: 7, tab: 18 };
  Object.assign(G, { figure: 20, figGap: 3 }); // 인물 단: 한 단의 높이 · 단 사이 틈 (기간 막대 아래 · 예속 띠 위, 줄마다 단 수가 다름)
  Object.assign(G, { phase: 20, phaseGap: 3, phaseMax: 3 });
  const G_BASE = G; // 서고 값과 고를 때의 옛 값 묶음(함수 안 const G가 가리므로 — _phaseCells · _rankCells) // 시기 구분(학계) 단: 체계마다 얇은 한 줄(높이 20 · 아래 틈 3), 한 줄(띠)에 그리는 체계는 최대 3 — 줄 단위 위쪽 덧단
  Object.assign(G, { rank: 20, rankGap: 3 }); // 지위 단: 시기 단 아래 · 지도자 칸 위의 얇은 한 줄(높이 20 · 아래 틈 3) — 같은 줄 단위 위쪽 덧단
  Object.assign(G, { power: 20, powerGap: 3 }); // 단체 단(설계 7-8 결정 1 A 집권 · 2 A 실권): 지위 단 아래 · 지도자 칸 위의 얇은 줄(높이 20 · 아래 틈 3) — 같은 줄 단위 위쪽 덧단, 최대 두 줄(위 집권 · 아래 실권)
  Object.assign(G, { scopeHead: 16, scopeFoot: 6, scopePadX: 8 }); // 대범위 테두리(7-2): 머리(이름표 자리 — 책갈피 탭 자리 위) · 아래 여백 · 띠 바깥 가로 여백 (_scopePad · _drawScopes)
  Object.assign(G, { mini: 6, miniTop: 5, miniPitch: 8, door: 4.4, radius: 10 }); // 접힌 줄 · 접힌 트랙의 가는 막대(높이 · 첫 단의 위 · 단 간격) · 승계선의 문 높이 · 띠 모서리 반지름
  /* 뒤 장(건의 8의 2번 C — 감독 선택 2026-10-13 '어긋난 겹장 + 끝 쪽 탭'): 속국 띠 뒤 상국 빛깔의 종이(관계의 시작 ~ 끝) · 상국 이름 탭은 관계가 끝나는 쪽.
     rise = 뒤 장을 위로 어긋나게 하는 몫 · shift = 관계가 띠 첫머리부터일 때 오른쪽으로 어긋나게 하는 몫 · tabRise = 상국 탭을 올리는 몫 — 감독 확정 2026-10-14
     '옆은 맞추고 위로만 5px'(목업 C의 5 · 5 · 5에서 shift만 0 — 뒤 장은 관계 구간 그대로 · 띠 끝 밖으로 나오지 않음, 상국 탭은 뒤 장의 평평한 윗변에 · 뒤 장과 같은 칠 · 테).
     gap = 띠 둘레의 종이빛 틈(css 변수 --tl-plate-gap이 있으면 그 값 — 그림 두 꼴을 같은 코드로). 칠 = 상국 색의 몫(oklab · 나머지는 종이) — 깊이(depLook)마다,
     명목상 · 관계 없는 소속은 칠 없이 점선 · 파선 테 · 테 = 상국 색 78% + 먹. 새 앱 bands.dart의 sheetRise · sheetShift · sheetGap · sheetMix와 같은 값 */
  const PLATE = { rise: 5, shift: 0, tabRise: 5, radius: 10, gap: 1.5, mix: { loose: 0.46, firm: 0.62, held: 0.74, owned: 0.86, occupied: 0.86, nominal: 0, plain: 0 }, edge: 0.78 };
  /* 매달린 속국 이름표(건의 8의 나 — 감독 결정 2026-10-14 "원래대로 두고 크기만 줄이자"): 줄 배정(depProxies)은 그대로, 크기만 반 — 한 줄 pitch 13(예전 구역 탭과 같은 23) ·
     탭 높이도 13(띠 밑에 2px 끼워 0번 줄은 11px 드러남) · 글 8px(650 그대로 — 띠 안 품은 칸은 9.5 그대로) · linkOut = 세로 끈이 매달린 탭에 닿는 자리(탭 윗변에서).
     한 줄 13은 감독 원칙(글 위아래 틈 — 1배 실측 첫 줄 1/1 · 둘째 줄부터 1/2)으로 12에서 고친 값(안 B — 2026-10-14). 글 상자는 common.css .tl-hang(첫 줄 y 3~12 · 둘째 줄부터 2~12).
     구역 탭(G.zoneTab · zoneGap)은 그대로 — 그 줄의 덧붙는 높이 = 매달린 줄 × 13 + 구역 줄 × 23 + 3. 상국 띠의 '▸ 속국 n' 단추로 접으면 그 상국의 줄만큼 줄이 낮아짐(foldedHangs).
     새 앱 hangs.dart · layout.dart가 같은 값을 씁니다 */
  const HANG = { pitch: 13, font: 8, linkOut: 7 };
  /* 가는 승계선(부분 승계 — SUCC_KINDS의 thin)의 굵기. crisp: 선을 픽셀 칸 가운데(.5)에 맞춰 긋기(crispAt) — 1px 선이 두 칸에 번지지 않게.
     예전에는 늘 세 가닥(정도만큼 진하게)이었으나 선이 셋이라 난잡해 가는 한 줄로 바꿈 (2026-10-13 감독: "부분승계를 좀 단순하게 · 선이 3개니까 너무 난잡해진다") */
  G.thin = { w: 1, crisp: true };
  /* 조감 (건의 1 — 밀도 넷째 단계 '조감', density 2): 줄은 띠 하나뿐 — 글줄 · 칸 · 막대 · 인물 · 덧단 · 책갈피 탭 · 구역 탭 · 바탕 문화 단이 모두 0.
     모양(shape) 셋: a 띠 21px · 띠 안 이름 + 사건 점 · 개수 알약(기본) / b 21px · 이름만 / c 8px · 글자 없이 띠 · 선만(이름은 올려야 · 왼쪽 줄 이름은 색 점만).
     줄 사이는 모두 6px(소속선이 지나갈 틈 — 5.5px보다 좁으면 이웃 줄 사이의 소속선이 사라짐) · 민족 경계 +6 · 트랙 위아래 4 · 대범위 머리 12 · 발 4.
     띠 모서리는 문(4.4 · 8px 띠는 3)이 곧은 테두리 안에 들도록 4.5 · 2.5 — 지금 쓰는 값 묶음은 this._G()가 돌려줍니다 */
  const G_BIRD = { pad: 4, gap: 6, memberGap: 6, groupGap: 6, tab: 0, hem: 0, folded: 22, foldedGroup: 14, scopeHead: 12, scopeFoot: 4, mini: 3, miniTop: 1.5, miniPitch: 4 };
  /* 서고 배치 3단(2026-10-23 · 인수인계 5-15 — 새 앱 layout.dart G · 계약 3절 '두 장 꼬리표'): 메이커 미리보기(opts.seogo)만 켜는 값 묶음. 내보내기(prototype/scripts/export)는 켜지 않아 배치가 바이트까지 그대로.
     띠 = 이름 색줄 head 14(구멍 · 이름 · 꼬리 마름모 — 세로 가운데 7) → 칸 층 floor 14씩 맞붙음(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관 — 틈 0) → 흰 사건 칸 line 18 × 글줄 → 기간 막대 · 인물 단(감독 "날짜 칸 · 인물 막대는 그대로").
     줄 위 틈: 솟는 줄(받침 카드 6 + 상국 · 연합 탭 12)은 raise 15, 그릇의 줄(열쇠표 · 매다는 실)은 contain 10을 줄 위 틈(tab 5)에 더함 — 줄 사이 3 · 소속 줄 1 · 트랙 위아래 4(새 앱 ViewMetrics.normal). 폴더 머리 21 · 발 7 · 접힌 폴더 줄 24 · 문화권 머리 단 20 · 그 아래 틈 4 · 문화권 사이 6 */
  const G_SEOGO = { pad: 4, gap: 3, memberGap: 1, tab: 5, inset: 0, slotGap: 0, line: 18, head: 14, dynasty: 14, leader: 14, cabinet: 14, organ: 14, dep: 14, phase: 14, phaseGap: 0, rank: 14, rankGap: 0, power: 14, powerGap: 0, scopeHead: 21, scopeFoot: 7, foldedGroup: 24, raise: 15, contain: 10, sphereHead: 20, sphereGap: 4, sphereBetween: 6, keyH: 12, keyRise: 2, stag: 13, f4Epoch: 14, f4Cycle: 13, f4Person: 16, f4Horn: 4.5, shelfKeep: 5, shelfH: 19, figure: 14, figGap: 2 }; // figure · figGap: 서고의 인물 단(알약) — 칸 층과 같은 14 // shelf*: 과제 9 선반 — 제 줄에 두는 상위 수 · 폴더 발의 작은 꼬리표 줄(13 + 틈) // f4*: 과제 9 — 문화권 머리 단 밑 시대 줄 · 주기 줄 · 사람 띠 · 뿔 매듭 높이
  const BIRD = {
    a: { shape: 'a', h: 21, name: true, dots: true, door: 4.4, radius: 4.5 },
    b: { shape: 'b', h: 21, name: true, dots: false, door: 4.4, radius: 4.5 },
    c: { shape: 'c', h: 8, name: false, dots: false, door: 3, radius: 2.5 },
  };
  /* 조감의 가는 승계선(부분 승계): 띠가 낮아 선도 더 가늘게 — a · b 0.8 · c 0.6 (1px 아래라 픽셀 칸 맞춤 없음) */
  BIRD.a.thin = BIRD.b.thin = { w: 0.8 };
  BIRD.c.thin = { w: 0.6 };
  const BIRD_AUTO = 2600; // 자동 조감의 문턱(보기 폭, 년) — 사건 이름이 모두 꺼지는 넓이(_draw의 imp3)와 같음: 이보다 넓게 보면 줄 안이 빈 칸뿐이라 세로로 줄여 한눈에. 나가는 문턱은 8% 아래(LOD_GAP)
  const BIRD_NAME = { size: 10, wt: 700, inset: 6, clear: 3 }; // 띠 안 이름: 10px 굵게 · 띠 시작에서 6px · 둘레 3px에는 점 · 알약 · 단추를 두지 않음
  const STUB = 3; // 조감의 승계선이 띠 끝에 닿는 짧은 끝: 테두리 안쪽 3px까지 (문을 지나 — 네모가 없으니 띠 끝이 곧 역)
  const AXIS = { years: 30, ganji: 20, cal: 20, era: 22, epoch: 24, group: 22, cap: 22, capSec: 16 };
  const EPOCH_FOLD = 'epochFold'; // 날짜 칸 묶음 기억(axisOpen)의 열쇠: 있으면 나라별 시대 구분 줄을 한 줄로 접음 (시대 접기 — 설계 6 결정 7 A)
  const FADE = HT.UNKNOWN_FADE || 44;
  const SAFE_Y = 56; // 고른 줄이 "잘 보인다"고 치는 위아래 여유(px) — 이 안쪽에 온전히 있으면 화면을 옮기지 않습니다 (setAnchor)
  const CHASE = { notch: 70, fine: 25 }; // 확대 엔진 하나(_glideTo): 목표를 쫓아가는 시간 상수(ms) — 노치 휠 · 단추 · 키는 70, 트랙패드·고해상도 휠은 25(손에 더 바짝)
  /* 관성(_coastFrom): 끌다 놓으면 손의 속도를 이어받아 지수 감속으로 미끄러집니다 — 시간 상수 tau(ms)는 가로·세로 같은 값(초당 1000px로 놓으면 약 250px — "보통").
     min: 이보다 느리게 놓으면 관성 없음 · rest: 이보다 느려지면 멎음 · grab: 이보다 빠를 때 누른 것은 멈추려는 누름(고르지 않음) — 모두 px/초 · max: 길어도 화면 폭의 몇 배까지
     · travel: 손이 이만큼(px)은 끌고 나서 놓아야 관성 — 누르다 살짝 미끄러진 손(짧고 빠른 몇 px)이 화면을 던지지 않게 */
  const COAST = { tau: 250, min: 50, rest: 15, grab: 80, max: 1.5, travel: 20 };
  const LOD_GAP = 0.08; // 문턱은 두 개: 확대 수준에 따라 바뀌는 것은 들어오는 문턱과 나가는 문턱을 8% 벌립니다 — 경계에서 멈춰도 깜빡이지 않게 (_past · _stepAt)
  const FX_BUDGET = 160; // 움직이는 중 한 프레임에 새로 거는 효과의 상한 — 넘치면 그 프레임의 나머지는 효과 없이 (멀리 빠르게 날 때 프레임이 밀리지 않게)
  /* 글자 너비는 화면에 실제로 쓰이는 글꼴로 잽니다 (다르면 칸 이름이 잘리거나 어긋남) */
  let fontStack = '';
  const FONT = (px, wt = 500) => {
    if (!fontStack) fontStack = getComputedStyle(document.body || document.documentElement).fontFamily || '"Malgun Gothic", sans-serif';
    return `${wt} ${px}px ${fontStack}`;
  };
  /** 곡선 css(cubic-bezier(x1, y1, x2, y2))가 진행값 y에 닿는 시간 비율(0~1) — 흐름 도중 어떤 높이에 닿는 순간을 셀 때 (이분법 · 곡선이 아니면 y 그대로) */
  const bezierTimeAt = (css, y) => {
    const m = /cubic-bezier\(([^)]+)\)/.exec(css || '');
    if (!m) return y;
    const [x1, y1, x2, y2] = m[1].split(',').map(Number);
    const B = (a, b, s) => 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s;
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 32; i++) {
      const s = (lo + hi) / 2;
      if (B(y1, y2, s) < y) lo = s;
      else hi = s;
    }
    return B(x1, x2, hi);
  };
  /* 글자 사이: body의 −0.01em이 px로 계산되어 그대로 물려받아짐(글자 크기와 무관) — 글자 수만큼 더하면 화면 폭 그대로 (줄 이름의 연도 빼기 · 줄이기) */
  let bodyLs = null;
  const bodyLS = () => (bodyLs != null ? bodyLs : (bodyLs = parseFloat(getComputedStyle(document.body || document.documentElement).letterSpacing) || 0));

  const esc = HT.escapeHtml;
  const cx = t => t.toFixed(1);
  const measureCtx = document.createElement('canvas').getContext('2d');
  const widths = new Map();
  /* 실어 둔 글꼴(css/common.css의 @font-face — 프리텐다드)이 뒤늦게 열리면 그 전에 잰 폭은 버립니다 — 다음 배치가 새 글꼴로 다시 잽니다
     (첫 화면은 js/viewer.js가 글꼴이 열린 뒤에 그리므로 보통은 버릴 것이 없음) */
  if (document.fonts && document.fonts.addEventListener) document.fonts.addEventListener('loadingdone', () => widths.clear());
  function textWidth(text, size, wt = 500) {
    const key = `${wt}|${size}|${text}`;
    let w = widths.get(key);
    if (w == null) {
      measureCtx.font = FONT(size, wt);
      w = measureCtx.measureText(text).width;
      widths.set(key, w);
    }
    return w;
  }
  const shortYears = p => {
    const s = HT.yearOf(p.start);
    const e = p.ongoing ? null : HT.yearOf(p.endY);
    if (e == null) return s < 0 ? `BC ${-s}–` : `${s}–`;
    if (s < 0 && e < 0) return `BC ${-s}–${-e}`;
    if (s < 0) return `BC ${-s}–${e}`;
    return `${s}–${e}`;
  };
  const bcYear = y => (y < 0 ? `BC ${-HT.yearOf(y)}` : `${HT.yearOf(y)}`);
  /* 점 사건(끝 연도 없음)의 불확실한 연대는 기간처럼 보이지 않게 "점선 실에 꿴 구슬"로:
     통설 = 채운 구슬(점 바로 아래), 다른 견해 = 빈 고리, 연대 폭의 양 끝 = 작은 눈금. 6px 안으로 붙는 구슬은 하나로 합칩니다 */
  /* ranges: 연대 폭의 눈금을 넣을지 — 점 사건은 넣지 않습니다(감독 결정 2026-10-13 "정확한 일자를 모르면 한 곳을 찍어 단일로 · 범위 표현 x").
     통설 구슬 하나뿐이면 실을 긋지 않으므로(hi − lo < 3) 연대 폭만 적은 점 사건은 점 하나로 남습니다 — 다른 견해의 구슬과 실은 그대로 */
  const beadsOf = (e, alts, x0, C, X, ranges = true) => {
    const beads = [{ x: x0, y: e.start, kind: 'main' }];
    /* 이설의 시작과 끝(이설이 기간이면 — 디테일 건의 4: 끝에도 구슬)마다 빈 고리 하나 — 이미 있는 구슬과 6px 안이면 하나로 */
    for (const a of alts)
      for (const y of [a.start, a.end]) {
        if (y == null || !isFinite(y)) continue;
        const x = C(X(y));
        if (!beads.some(b => Math.abs(b.x - x) < 6)) beads.push({ x, y, kind: 'alt', a });
      }
    const edges = [];
    for (const r of ranges ? [e.startRange, e.endRange] : []) {
      if (!r) continue;
      for (const y of r) {
        const x = C(X(y));
        if (!beads.some(b => Math.abs(b.x - x) < 4) && !edges.some(d => Math.abs(d.x - x) < 2)) edges.push({ x, y, r });
      }
    }
    const xs = beads.map(b => b.x).concat(edges.map(d => d.x));
    return { beads, edges, lo: Math.min(...xs), hi: Math.max(...xs) };
  };
  /* 기간 사건의 이설의 끝 [{ x, j, a }] — 끝이 통설의 끝과 다른 이설만(현재까지인 이설은 끝이 없음), 원래 끝 x1과 4px 안이면 바깥으로 비킴 (화면 · 그림 내보내기 공용) */
  const altEnds = (e, alts, x1, C, X) =>
    alts
      .map((a, j) => ({ a, j }))
      .filter(({ a }) => a.end != null && isFinite(a.end) && !a.ongoing && Math.abs(a.end - (e.end ?? e.endY)) > 1e-9)
      .map(q => {
        const x = C(X(q.a.end));
        return Object.assign(q, { x: Math.abs(x - x1) < 4 ? x1 + (x < x1 ? -4 : 4) : x });
      });
  /* 열린 도읍 노선도 카드들 — Esc로 닫기. 문서 리스너는 여기 하나뿐이라 연표를 여러 번 만들어도(메이커 미리보기) 쌓이지 않습니다.
     입력 칸·열린 대화상자·메뉴가 있으면 그쪽 Esc를 먼저 두고 가로채지 않습니다 */
  const openMetros = new Set();
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape' || !openMetros.size || e.defaultPrevented) return;
    const t = e.target && e.target.closest ? e.target : null;
    const inCard = !!(t && t.closest('.tl-metro'));
    if (!inCard && t && t.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]')) return;
    if (document.querySelector('dialog[open], [role="menu"]:not([hidden])')) return;
    let closed = false;
    for (const tl of [...openMetros]) {
      if (!tl.metroEl || !tl.metroEl.isConnected || tl.metroEl.hidden) {
        openMetros.delete(tl);
        continue;
      }
      const back = tl.metroEl.contains(document.activeElement) && tl.metro.anchor && tl.metro.anchor.isConnected ? tl.metro.anchor : null;
      tl.hideMetro();
      if (back) back.focus({ preventScroll: true });
      closed = true;
    }
    if (closed) {
      e.preventDefault();
      e.stopImmediatePropagation(); // 같은 Esc로 상세 패널까지 닫히지 않게 (카드만)
    }
  });
  /* 고정해 둔 묶음 카드도 Esc로 닫습니다 (입력 칸·대화상자가 있으면 그쪽이 먼저) */
  const openCards = new Set();
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape' || !openCards.size || e.defaultPrevented) return;
    const t = e.target && e.target.closest ? e.target : null;
    if (t && !t.closest('.tl-card') && t.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]')) return;
    if (document.querySelector('dialog[open], [role="menu"]:not([hidden])')) return;
    let closed = false;
    for (const tl of [...openCards]) {
      openCards.delete(tl);
      if (tl.cardEl && !tl.cardEl.hidden) {
        tl.hideCard(true);
        closed = true;
      }
    }
    if (closed) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  });
  const overlaps = (list, l, r) => list.some(([a, b]) => a < r && l < b);
  /* 기간 막대 단 고르기: 빈 단이 없으면 가장 적게 겹치는 단에 (마지막 단에 몰아 쌓지 않음) */
  const pickLevel = (levels, l, r) => {
    let lvl = levels.findIndex(list => !overlaps(list, l, r));
    if (lvl < 0) {
      let best = Infinity;
      levels.forEach((list, i) => {
        const ov = list.reduce((s, [a, b]) => s + Math.max(0, Math.min(b, r) - Math.max(a, l)), 0);
        if (ov < best) {
          best = ov;
          lvl = i;
        }
      });
    }
    levels[lvl].push([l, r]);
    return lvl;
  };
  /* 이어 붙는 칸(같은 무리에서 앞 칸의 끝 = 뒤 칸의 시작)은 틈 없이 하나의 긴 둥근 칸으로 — 안쪽은 가는 구분선만 */
  const joins = (cells, keyOf, a, b) =>
    cells.map((c, i) => {
      const prev = cells[i - 1];
      const next = cells[i + 1];
      return {
        l: !!prev && keyOf(prev) === keyOf(c) && Math.abs(b(prev) - a(c)) < 1.5,
        r: !!next && keyOf(next) === keyOf(c) && Math.abs(b(c) - a(next)) < 1.5,
      };
    });
  /* 이어지는 칸 무리 배치 → [{ it, l, r, jl, jr, atL, atR }]. lo·hi 밖은 자르고, 잇지 않는 쪽은 0.5px 틈.
     너무 좁아 그리지 않는 칸(minW 미만)이 있어도 무리가 끊기거나 끝이 열리지 않게, 이음은 실제로 그리는 칸끼리만 잇고
     그 사이 빈틈은 앞 칸을 늘려 메웁니다 */
  const layoutStrip = (items, keyOf, a, b, lo, hi, minW = 1) => {
    const vis = items.map(it => ({ it, a: a(it), b: b(it) })).filter(v => v.b > lo && v.a < hi);
    const jn = joins(vis, v => keyOf(v.it), v => v.a, v => v.b);
    const cells = vis.map((v, n) => ({
      it: v.it,
      n,
      atL: v.a <= lo,
      atR: v.b >= hi,
      l: v.a > lo ? v.a + (jn[n].l ? 0 : 0.5) : lo,
      r: v.b < hi ? v.b - (jn[n].r ? 0 : 0.5) : hi,
      jl: false,
      jr: false,
    }));
    const drawn = cells.filter(c => c.r - c.l >= minW);
    const linked = (p, c) => {
      for (let i = p.n; i < c.n; i++) if (!jn[i].r) return false;
      return true;
    };
    drawn.forEach((c, k) => {
      const p = drawn[k - 1];
      if (!p || !linked(p, c)) return;
      c.jl = p.jr = true;
      if (p.r < c.l) p.r = c.l;
    });
    return drawn;
  };
  /* 가문 줄의 구간: layoutStrip이 놓은 지도자 칸들 가운데, 이어 붙은(jl) 칸에서 같은 가문(houseId)이 이어지는 동안 하나 — [{ id, color, l, r, first, last }].
     가문이 없는 칸은 건너뜁니다. 끝의 들임: 앞뒤가 다른 가문의 칸에 붙어 있으면 1px(구분), 칸의 둥근 끝이면 3px(모서리 밖으로 나가지 않게), 화면에서 잘린 열린 끝이면 0 */
  const houseRuns = (strip, clip = {}) => {
    const out = [];
    let cur = null;
    for (const e of strip) {
      const c = e.it.c;
      if (cur && e.jl && c.houseId && c.houseId === cur.id) {
        cur.r = e.r;
        cur.last = e;
        continue;
      }
      cur = c.houseId ? { id: c.houseId, color: c.houseColor, l: e.l, r: e.r, first: e, last: e } : null;
      if (cur) out.push(cur);
    }
    for (const u of out) {
      u.l += u.first.jl ? 1 : u.first.atL && clip.l ? 0 : 3;
      u.r -= u.last.jr ? 1 : u.last.atR && clip.r ? 0 : 3;
    }
    return out.filter(u => u.r - u.l >= 4);
  };
  /* 가로·세로 꺾은선을 둥근 모서리로 */
  const roundHV = (pts, rad) =>
    pts.reduce((d, pt, i) => {
      if (i === 0) return `M${cx(pt[0])} ${cx(pt[1])}`;
      const nx = pts[i + 1];
      if (!nx) return `${d} L${cx(pt[0])} ${cx(pt[1])}`;
      const pv = pts[i - 1];
      const r = Math.min(rad, Math.abs(pt[0] - pv[0] || pt[1] - pv[1]) / 2, Math.abs(nx[0] - pt[0] || nx[1] - pt[1]) / 2);
      const ix = pt[0] - Math.sign(pt[0] - pv[0]) * r;
      const iy = pt[1] - Math.sign(pt[1] - pv[1]) * r;
      const ox = pt[0] + Math.sign(nx[0] - pt[0]) * r;
      const oy = pt[1] + Math.sign(nx[1] - pt[1]) * r;
      return `${d} L${cx(ix)} ${cx(iy)} Q${cx(pt[0])} ${cx(pt[1])} ${cx(ox)} ${cx(oy)}`;
    }, '');
  /* 그림 내보내기용: 두 색을 k:1-k로 섞은 #hex */
  const mixHex = (a, b, k) => {
    const pa = [1, 3, 5].map(i => parseInt(HT.hex6(a).slice(i, i + 2), 16));
    const pb = [1, 3, 5].map(i => parseInt(HT.hex6(b).slice(i, i + 2), 16));
    return `#${pa.map((v, i) => Math.round(v * k + pb[i] * (1 - k)).toString(16).padStart(2, '0')).join('')}`;
  };
  /* 그림 내보내기용: 두 색을 oklab에서 k:1-k로 섞은 #hex — 화면의 color-mix(in oklab …)와 같은 섞임 (뒤 장의 칠 · 테 — _hostPlatesSVG · 범례 hostTabSample) */
  const mixOk = (a, b, k) => {
    const lin = v => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
    const gam = v => (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055);
    const lab = hex => {
      const [r, g, b2] = [1, 3, 5].map(i => lin(parseInt(HT.hex6(hex).slice(i, i + 2), 16) / 255));
      const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b2);
      const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b2);
      const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b2);
      return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
    };
    const A = lab(a);
    const B = lab(b);
    const [L, aa, bb] = A.map((v, i) => v * k + B[i] * (1 - k));
    const l = (L + 0.3963377774 * aa + 0.2158037573 * bb) ** 3;
    const m = (L - 0.1055613458 * aa - 0.0638541728 * bb) ** 3;
    const s = (L - 0.0894841775 * aa - 1.291485548 * bb) ** 3;
    const rgb = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
    return `#${rgb.map(v => Math.round(Math.min(1, Math.max(0, gam(v))) * 255).toString(16).padStart(2, '0')).join('')}`;
  };
  const bandStart = p => (p.startRange ? p.startRange[0] : p.start);
  const bandEnd = p => (p.endRange ? p.endRange[1] : p.endY);
  /* 흐린 띠 안의 조명 구간(같은 시기를 타국에도 — has-lit): 띠 안쪽 좌표의 구간들을 겹치거나 맞닿으면 하나로 (제 조명과 메아리가 맞닿은 자리에 이음매가 없게) */
  const mergeCols = cols => {
    const out = [];
    for (const [a, b] of cols.filter(([a, b]) => b - a > 0.5).sort((u, v) => u[0] - v[0])) {
      const last = out[out.length - 1];
      if (last && a <= last[1] + 0.5) last[1] = Math.max(last[1], b);
      else out.push([a, b]);
    }
    return out;
  };
  /* 흐리지 않을 해 구간 두 벌이 같은가 (_litState — 다시 그릴 때마다 새로 만든 목록이므로 값으로) */
  const litSame = (u, v) => u.length === v.length && u.every((s, i) => Math.abs(s[0] - v[i][0]) < 1e-9 && Math.abs(s[1] - v[i][1]) < 1e-9);
  /* 흐리지 않을 구간을 옮기는 동안(다른 칸으로 — _litState의 lit-sw): 새 구간 cols(to)와 옛 구간 prev(from)를 [a, b, 변수]로 나눔 —
     둘 다 든 곳은 la(그대로 1), 새 구간에만 든 곳은 ln(지금 밝기에서 1로 --t-in), 옛 구간에만 든 곳은 lo(1에서 그 띠의 흐림으로 --t-out) */
  const litSegs = (cols, prev) => {
    if (!prev) return cols.map(([a, b]) => [a, b, 'la']);
    const xs = [...new Set(cols.concat(prev).flat())].sort((u, v) => u - v);
    const inside = (list, t) => list.some(([a, b]) => a <= t && t < b);
    const out = [];
    for (let k = 0; k + 1 < xs.length; k++) {
      const a = xs[k];
      const b = xs[k + 1];
      const t = (a + b) / 2;
      const n = inside(cols, t);
      const o = inside(prev, t);
      if (!n && !o) continue;
      const v = n && o ? 'la' : n ? 'ln' : 'lo';
      const last = out[out.length - 1];
      if (last && last[2] === v && Math.abs(last[1] - a) < 1e-6) last[1] = b;
      else out.push([a, b, v]);
    }
    return out;
  };
  /* 띠의 가림(mask) 판: 띠의 테두리 상자에서 사방 LIT_PAD만큼 넓혀(그림자까지 흐린 띠와 같게), 조명 구간은 var(--la)(옮기는 동안은 구간마다 --la · --ln · --lo — litSegs) ·
     그 밖은 var(--bo)(그 띠가 흐려진 만큼). 구간이 띠 안쪽 끝에 닿으면 테두리와 그 바깥(그림자)까지 — 띠 끝의 모서리 모양은 띠 그대로, 띠 중간에서 끊긴 끝은 곧은 세로 끝(네모) */
  const LIT_PAD = 48;
  const litMask = (segs, bw, iw, w) => {
    const o = 'rgba(0,0,0,var(--bo))';
    const end = w + 2 * LIT_PAD;
    const stops = [];
    let x = 0;
    for (const [a, b, v] of segs) {
      const A = a <= 0.5 ? 0 : a + bw + LIT_PAD;
      const B = b >= iw - 0.5 ? end : b + bw + LIT_PAD;
      if (A > x) stops.push(`${o} ${cx(x)}px ${cx(A)}px`);
      stops.push(`rgba(0,0,0,var(--${v})) ${cx(Math.max(A, x))}px ${cx(B)}px`);
      x = B;
    }
    if (x < end) stops.push(`${o} ${cx(x)}px`);
    return `linear-gradient(to right, ${stops.join(', ')})`;
  };
  const peopleKey = (tr, gp) => `${tr.id}|${gp.key}`;
  /* 세로 이름 줄이기 (민족 칸 · 민족 딱지 · 트랙 이름 — 칸에 다 들지 않을 때): 뜻이 남는 차례로 — 괄호를 뗀 이름('한(삼한)' → '한'), 한 낱말이면 끝의 '민족 · 족'을 뗀 이름('참족' → '참' · '흉노족' → '흉노')
     그다음 그 첫 글자('흉' — 한 낱말 고유 이름의 첫 글자는 책갈피 탭의 첫 글자와 같은 말투), 여러 낱말이면 첫 낱말(빈칸 · 붙임표 · 가운뎃점 · 빗금 앞 — '초기 유력 이민족' → '초기' · '여진-만주족' → '여진')까지만 —
     여러 낱말 이름의 첫 낱말을 잘라 한 글자만 남기지는 않습니다('초' · '후'는 뜻을 알 수 없음). 모두 들지 않으면 글 없이(칸의 색과 풍선의 이름으로). fits(글) → 들면 true */
  const shortNames = name => {
    const out = [];
    const add = t => (t = (t || '').trim()) && !out.includes(t) && out.push(t);
    add(name);
    const bare = name.replace(/\s*[(（][^)）]*[)）]\s*/g, ' ').trim();
    add(bare);
    const words = bare.split(/[\s\-‐–·・/]+/).filter(Boolean);
    const stem = w => w.replace(/(민족|족)$/, '');
    if (words.length === 1) {
      const st = stem(words[0]);
      add(st);
      if ([...st].length > 1) add([...st][0]);
    } else if (words.length > 1) {
      add(words[0]);
      add(stem(words[0]));
    }
    return out;
  };
  const shortName = (name, fits) => shortNames(name || '').find(fits) || '';

  /* ── 승계선의 모양과 이음매 (건의 5 — 관문 + 환승 다리) ──
     승계 종류마다 한 줄: 선을 그리는 곳(띠 뒤 선 · 같은 줄의 다리 · 관문 · 범례 · 그림 내보내기)은 모두 이 표만 봅니다.
     dash: 띠 뒤 선의 점선 박자('' = 실선) · beat: 띠 위 조각(다리 · 관문)의 점선 박자 [칠, 빔] — 조각 길이에 맞춰 칠을 늘여 양 끝이 늘 칠로 끝나고, 다리는 이음매 한가운데가 빔 ·
     ring: 작은 고리(부흥 — 다리에서는 이음매 위, 그 밖에는 후대 띠 바로 앞) · thin: 가는 선(밀도의 가는 선 값 G.thin — 굵기 w · 픽셀 칸 맞춤 crisp, 없으면 1.6px).
     rank: 줄 차지 차례(chainRows — 한 선대의 줄을 여럿이 다투면 작은 쪽이 먼저: 직접 > 부흥 · 간접 > 부분).
     부분 승계(2026-10-13 감독 결정 — 'A 한 줄 · 짙기 80%'): 가는 실선 하나 — 굵은 실선 = 직접 · 가는 실선 = 부분 · 점선 = 간접 · 점선 + 고리 = 부흥.
     정도(약 · 중 · 강)는 선에 그리지 않고 풍선 · 상세 창의 글로만(HT.successionLabel). 예전(2026-09-20)의 '늘 세 가닥 · 정도만큼 진하게'는 선이 셋이라 난잡해 버림 */
  const SUCC_KINDS = {
    direct: { dash: '', beat: null, ring: false, rank: 0 },
    indirect: { dash: '5 4', beat: [5, 4], ring: false, rank: 1 },
    revival: { dash: '5 4', beat: [5, 4], ring: true, rank: 1 },
    partial: { dash: '', beat: null, ring: false, rank: 2, thin: true },
  };
  const succKind = type => SUCC_KINDS[type] || SUCC_KINDS.indirect;
  /* 가는 선 값(밀도마다): 보통 밀도 1px · 픽셀 칸 맞춤, 조감은 BIRD의 thin(a · b 0.8 · c 0.6) */
  const THIN = G.thin;
  /** 가는 선의 종류면 그 밀도의 가는 선 값 { w, crisp }, 아니면 null(1.6px 선) */
  const thinOf = (kind, sg = THIN) => (kind.thin ? sg : null);
  /** 가는 선의 자리를 픽셀 칸 가운데(.5)로 (가는 선 값에 crisp가 있을 때 — 보통 밀도의 1px 선. 조감의 더 가는 선은 그대로) */
  const crispAt = (v, s) => (s && s.crisp ? Math.floor(v) + 0.5 : v);
  /** 가로 · 세로 꺾은선의 꼭짓점을 모두 픽셀 칸 가운데로 — 가로 변은 y, 세로 변은 x가 칸 가운데에 들어 1px 선이 또렷함 */
  const crispHV = (pts, s) => (s && s.crisp ? pts.map(([x, y]) => [crispAt(x, s), crispAt(y, s)]) : pts);
  /* 부분 승계의 짙기(화면의 common.css · 그림 내보내기 공용): 띠 뒤 선도 띠 위 조각(다리 · 관문)도 .8 — 가는 선(1px)이라 다른 승계선의 띠 뒤 짙기 .5로는 잘 보이지 않음
     (2026-10-13 감독: 처음 35%로 골랐다가 "너무 안보이네" → 80%). 직접 승계(1.6px)와는 굵기로 구별. 합류 조각(흡수)은 다른 승계와 같은 .9 */
  const PARTIAL = 0.8;
  /** 점선 박자 [칠, 빔]으로 from → to를 채운 칠 구간들 [[작은 값, 큰 값] …] — 칠을 늘이거나 줄여 양 끝이 늘 칠로 끝납니다 (0.5px보다 짧으면 없음 · 박자가 없으면 한 획) */
  const beatRuns = (from, to, beat) => {
    const len = Math.abs(to - from);
    if (len < 0.5) return [];
    if (!beat) return [[Math.min(from, to), Math.max(from, to)]];
    const [on, off] = beat;
    const n = Math.max(1, Math.round((len + off) / (on + off)));
    const d = (len - off * (n - 1)) / n;
    const dir = Math.sign(to - from);
    return Array.from({ length: n }, (_, i) => {
      const a = from + dir * i * (d + off);
      return [Math.min(a, a + dir * d), Math.max(a, a + dir * d)];
    });
  };
  /** 같은 줄에서 곧바로 이어지는 두 띠 사이(틈 g px)에서 이음매 쪽 네모가 더 안으로 비켜 앉는 거리: 맞닿으면 3px, 틈이 12px로 벌어지면 0 — 그사이는 이어지게(문턱 없음) */
  /** 이음매 쪽 네모가 더 안으로 비켜 앉는 거리(px): 맞닿으면 3px, 틈이 12px로 벌어지면 0. 직접이 아닌 승계(wide — 간접 · 부흥 · 부분)는 6px —
      다리가 6 + 2 × 6 = 18px이라 점선이 두 토막 + 빔으로 보여 "네모 둘이 그냥 붙은" 모양이 되지 않게 (묶음 5 · 7번 · 감독 결정 A 틈 넓힘).
      8px(목업)은 건국 해에 놓인 사건의 이름이 같은 해 보기에서 네모에 밀려 숨는 일이 있어 6px로 줄임(dev-smoke의 '그 해 보기' 검사) */
  const seamPush = (g, wide = false) => (wide ? 6 : 3) * HT.clamp(1 - g / 12, 0, 1);
  /** q → p 이음매가 직접 승계가 아닌지 (내보내기 links.mjs의 seamWide와 같은 판정) */
  const seamWide = (q, p) => !!(q && p && (((p.predecessors || []).find(e => e.from === q) || {}).type || 'indirect') !== 'direct');
  const SQ_CLEAR = 1.5; // 건국 · 멸망 네모(와 내림줄) 둘레에서 사건 글자가 비켜 가는 여유(px) — 네모 + 1.5px (_sqZones · _linkPlan의 zones)
  /* 관문의 가장 긴 길이: 네모가 띠 끝 자리(테두리 + 2px 안 · 이음매면 seamPush만큼 더)에 있을 때 네모 쪽 끝(네모 + 1px) ↔ 테두리 = G.bw + 1 + 비키기(≤ 3) — 0.5px 여유.
     이보다 멀면(연대 폭이 있는 끝: 네모는 끝 해 X(endY)에 서서 연대 폭만큼 테두리에서 떨어짐) 관문 · 다리 없이 띠 뒤 선만 — 띠 위 획이 연대 폭 구간의 사건 점 · 글자를 가로지르지 않게 */
  const GATE_MAX = G.bw + 1 + seamPush(0, true) + 0.5;
  const DOOR_H = 4.4; // 문의 높이(선을 따라 잰 길이의 수직): 선 굵기 1.6 위아래로 종이색 1.4px — 가는 선도 같은 문
  /** 다리 (같은 줄 · 곧바로 이음 — 띠 위 층): qe = 선대 띠의 바깥 오른쪽 끝, pf = 후대 띠의 바깥 왼쪽 끝, xa = 멸망 네모 오른쪽 + 1, xb = 건국 네모 왼쪽 − 1, y = 네모 높이,
      dh = 문 높이(조감의 8px 띠는 3 — BIRD.c.door), sg = 그 밀도의 가는 선 값.
      → { doors: [{ x, y, w, h, seam }], segs: [{ x1, y1, x2, y2, side: 'q' | 'p', w(가는 선) }], ring: { x, y } | null }.
      문 = 선이 테두리를 지나는 곳의 종이색 둥근 네모(테두리 + 양쪽 0.5px) — 맞닿으면 두 테두리를 한 문으로(seam). 선은 이음매(두 끝의 가운데)에서 왼쪽은 선대 · 오른쪽은 후대의 테두리색,
      점선이면 이음매 한가운데가 박자의 빔 · 고리는 이음매 위 */
  const seamBridge = ({ qe, pf, xa, xb, y, kind, dh = DOOR_H, sg = THIN }) => {
    const door = (a, b, seam) => ({ x: a - 0.5, y: y - dh / 2, w: b - a + 1, h: dh, seam });
    const doors = pf - qe < 0.5 ? [door(qe - 1, pf + 1, true)] : [door(qe - 1, qe, false), door(pf, pf + 1, false)];
    const mid = (qe + pf) / 2;
    const runs = kind.beat ? beatRuns(mid - kind.beat[1] / 2, xa, kind.beat).concat(beatRuns(mid + kind.beat[1] / 2, xb, kind.beat)) : [[xa, mid], [mid, xb]];
    const thin = thinOf(kind, sg);
    const yy = crispAt(y, thin);
    const segs = [];
    for (const [a, b] of runs) if (b - a > 0.05) segs.push(Object.assign({ x1: a, y1: yy, x2: b, y2: yy, side: b <= mid + 1e-6 ? 'q' : 'p' }, thin ? { w: thin.w } : {}));
    return { doors, segs, ring: kind.ring ? { x: mid, y } : null };
  };
  /** 관문 (띠 위 층): 선이 제 띠의 네모에서 테두리 밖 0.5px까지 가는 한 획 — a = 네모 쪽 끝, b = 테두리 바깥 0.5px, at = 획의 높이(가로) · x(세로),
      border = [테두리의 두 변] (가로 획이면 x, 세로 획이면 y) → { door, segs: [{ x1, y1, x2, y2, w(가는 선) }] }. 점선이면 박자를 네모 쪽에서 맞춤 */
  const gatePiece = ({ a, b, at, vertical, border, kind, dh = DOOR_H, sg = THIN }) => {
    const lo = Math.min(border[0], border[1]) - 0.5;
    const hi = Math.max(border[0], border[1]) + 0.5;
    const door = vertical ? { x: at - dh / 2, y: lo, w: dh, h: hi - lo, seam: false } : { x: lo, y: at - dh / 2, w: hi - lo, h: dh, seam: false };
    const thin = thinOf(kind, sg);
    const o = crispAt(at, thin);
    const segs = beatRuns(a, b, kind.beat).map(([u, v]) => Object.assign(vertical ? { x1: o, y1: u, x2: o, y2: v } : { x1: u, y1: o, x2: v, y2: o }, thin ? { w: thin.w } : {}));
    return { door, segs };
  };
  /** 합류 조각 (흡수 — 후대가 선대보다 먼저 있던 나라, 2026-09-20 감독 결정 '모든 승계 종류'): 선이 후대 띠의 테두리에 닿는 자리에 선대 색의 짧은 조각.
      x = 닿는 자리, edgeY = 후대 띠의 선대 쪽 바깥 변, dir = 선이 가는 쪽(1 = 아래로 — 위 테두리에 닿음) — 테두리 밖으로 나가지 않게 바깥 변에서 안쪽으로 h(테두리 1px + 0.6),
      폭은 승계선의 굵기 1.6 + 양쪽 1.5px — 가는 선(부분 승계)도 같은 크기(합류한 자리의 표지라 종류와 상관없이 같게) → { x, y, w, h } */
  const joinPiece = ({ x, edgeY, dir }) => {
    const w = 1.6 + 3;
    const h = G.bw + 0.6;
    return { x: x - w / 2, y: dir > 0 ? edgeY : edgeY - h, w, h };
  };
  /** 줄 만들기: 승계(직접 · 간접 · 부흥 · 부분)로 이어지는 정권만 같은 줄을 씁니다 — 관계가 없으면 같은 민족이라도 새 줄. list는 시작 차례(byStart).
      같은 해에 시작하는 정권들(무리)은 이을 줄을 무리 전체로 고릅니다: 직접 승계로 이은 수 → 부분 승계가 아닌 것으로 이은 수 → 이은 수가 가장 많은 배치 —
      그런 배치가 여럿이면 예전 규칙(차례대로 각자 이을 수 있는 첫 줄)에 가장 가까운 것. 그래서 한 선대의 줄을 여러 후대가 다투면 직접 승계가 먼저(그다음 부흥 · 간접, 부분 승계가 마지막),
      직접 선대와 간접 선대를 함께 가진 후대는 직접 선대의 줄로 가고, 같은 급끼리는 예전처럼 byStart 차례(긴 나라가 먼저).
      줄이 정해지면 줄 안에서 곧바로 이어지는 승계 쌍(선대의 끝 · 후대의 시작이 모두 확정 — 미정도 연대 폭도 아닌 끝)을 선대의 _seamR · 후대의 _seamL로 적어 둡니다 —
      이음매 쪽 네모가 비켜 앉고(_squares) 두 네모 사이에 다리가 놓입니다(_linkPlan). 표시 체크(승계선 끄기 · 직접만)와 무관하게 자료로 정함 */
  const succRank = (p, q) => {
    const e = (p.predecessors || []).find(x => x.from === q);
    return !e ? Infinity : succKind(e.type).rank;
  };
  /* fence(q, p) — 리메이크 2부 포개짐: 내보내기 때만 쓰는 줄 울타리(같은 직접 그릇끼리만 한 줄 — _layoutTrack의 rowsOf). 없으면 예전 그대로 */
  const chainRows = (list, fence) => {
    const rows = [];
    for (let i = 0; i < list.length; ) {
      let j = i + 1;
      while (j < list.length && bandStart(list[j]) === bandStart(list[i])) j++;
      const grp = list.slice(i, j);
      /* 무리의 배치 훑기: 차례대로 각자 이을 수 있는 줄(끝 정권이 선대이고 그 앞에서 끝남)을 먼저 생긴 줄부터, 마지막에 새 줄 — 처음 닿는 배치가 예전 규칙.
         더 나은 배치(직접 수 → 이은 수)를 만날 때만 바꿔 적으므로 같은 점수면 예전 규칙에 가까운 것이 남습니다. 무리가 크면(9개 이상) 예전 규칙 그대로(첫 줄만) */
      const greedy = grp.length > 8;
      const pick = [];
      let best = null;
      /* 점수: 직접으로 이은 수 → 직접 · 부흥 · 간접으로 이은 수(부분 승계가 아닌 것) → 이은 수 — 한 선대의 줄을 다투면 직접 > 부흥 · 간접 > 부분 */
      const walk = (k, direct, strong, total) => {
        if (k === grp.length) {
          if (!best || direct > best.direct || (direct === best.direct && (strong > best.strong || (strong === best.strong && total > best.total)))) best = { direct, strong, total, pick: pick.slice() };
          return;
        }
        const p = grp[k];
        for (let t = 0; t < rows.length; t++) {
          const r = rows[t];
          const last = r[r.length - 1];
          const rank = bandEnd(last) <= bandStart(p) && (!fence || fence(last, p)) ? succRank(p, last) : Infinity;
          if (rank === Infinity) continue;
          r.push(p);
          pick.push(t);
          walk(k + 1, direct + (rank === 0 ? 1 : 0), strong + (rank <= 1 ? 1 : 0), total + 1);
          pick.pop();
          r.pop();
          if (greedy) return;
        }
        rows.push([p]);
        pick.push(-1);
        walk(k + 1, direct, strong, total);
        pick.pop();
        rows.pop();
      };
      walk(0, 0, 0, 0);
      best.pick.forEach((t, k) => (t < 0 ? rows.push([grp[k]]) : rows[t].push(grp[k])));
      i = j;
    }
    for (const r of rows)
      for (let k = 1; k < r.length; k++) {
        const q = r[k - 1];
        const p = r[k];
        if (!q.endUnknown && !p.startUnknown && !q.endRange && !p.startRange && (p.predecessors || []).some(e => e.from === q)) {
          q._seamR = p;
          p._seamL = q;
        }
      }
    return rows;
  };
  /* 줄 채우기(리메이크 2부 — 목업 서고 '이어지지 않아도 겹치지 않으면 한 줄에' · 감독 2026-10-15 "최대한 목업 반영"): 승계로 이은 사슬(chainRows의 줄)을
     시작 차례로, 앞 줄의 마지막 띠가 그 사슬의 첫 띠보다 먼저 끝나는 첫 줄에 이어 붙입니다(끝과 시작이 같은 해면 붙이지 않음 — 이음매로 보이지 않게).
     내보내기(새 앱)만 켭니다(tl.packRows — export/base.mjs). 웹 · 메이커 미리보기는 예전처럼 사슬마다 한 줄 */
  const packChains = (rows, fence) => {
    const out = [];
    for (const r of rows.slice().sort((a, b) => bandStart(a[0]) - bandStart(b[0]))) {
      const into = out.find(o => bandEnd(o[o.length - 1]) < bandStart(r[0]) && (!fence || fence(o[0], r[0])));
      if (into) into.push(...r);
      else out.push(r.slice());
    }
    return out;
  };
  /** 띠의 바탕 짙기(어두운 화면의 이음매 문 색 — 두 띠 바탕의 중간): common.css의 띠 바탕 규칙과 같은 표 → [색, %] */
  const bandTint = p => {
    const hs = HT.historicityOf(p);
    const kind = p.polityKind || 'state';
    const light = kind === 'vassal' || isDepKind(kind) || kind === 'exile' || kind === 'movement';
    const fog = light ? 10 : p.startUnknown || p.endUnknown || kind === 'federation' ? 7 : 24; // 전설 · 반전설 · 부정됨의 안개(::before --fog)
    if (hs === 'refuted') return ['var(--paper-muted)', Math.round(fog * 0.45)]; // 부정됨 = 전설과 같은 안개를 색 없이 (묶음 5 · 5번)
    if (hs === 'legendary') return [p.color, Math.round(fog * 0.45)]; // 위에서 아래로 옅어지는 안개의 가운데쯤
    if (hs === 'semi') return [p.color, fog];
    if (kind === 'federation') return [p.color, 6];
    if (light) return [p.color, 9];
    if (kind === 'org' || kind === 'era') return [p.color, 10];
    if (p.startUnknown || p.endUnknown) return [p.color, 6];
    if (p.certainty === 'legend' && !p.startRange && !p.endRange) return [p.color, 10]; // 전승 연대 빗금(14 · 5)의 가운데
    return [p.color, 24];
  };
  const KIND_SHORT = { vassal: '종속', federation: '연맹', org: '조직', era: '시대', culture: '문화', overlay: '기관' };
  for (const k of HT.POLITY_KINDS || []) if (k.short && !KIND_SHORT[k.id]) KIND_SHORT[k.id] = k.short; // 새 종류(조공 · 보호 · 괴뢰 …)의 딱지는 종류 표(core.js)에서
  const isDepKind = kind => !!HT.kindFamily && HT.kindFamily(kind) === 'dependent'; // 종속 갈래: 제 띠는 옅은 띠 하나 — 누구를 어떻게 섬겼는지는 상국 띠의 속국 이름표로 (depProxies)
  /* 소속 한 구간의 관계: 적힌 관계(rel) — 없으면 null (띠 · 소속선의 설명글) */
  const depRel = h => (h && h.relation && HT.relationInfo ? HT.relationInfo(h.relation) : null);
  /* 속국 이름표 (2026-09-20 감독 결정 '뒤집기' — 속국 띠 안에 상국을 그리지 않고, 상국 띠가 제 아래 나라들을 품습니다).
     소속(partOf)을 적은 정권의 소속 구간 하나가 상국 띠의 이름표 하나이고, 자리는 관계의 자율성이 정합니다:
     스스로 다스린 관계는 상국 띠 아래에 매달리고(out) — loose 빈 탭(조공 · 봉국 · 자치령) · firm 칠한 탭(종속 · 보호 · 위성) · nominal 점선 탭(명목상) ·
     plain 파선 탭(관계를 적지 않은 소속 · 구성국 · 동군연합 — 예속이 아닌 소속), 상국이 다스린 관계는 상국 띠 안 맨 아래 칸에 들어옵니다(in) —
     held 옅은 칸(괴뢰 · 위임) · owned 짙은 칸(식민) · occupied 빗금 칸(점령). 관계를 적지 않은 소속은 종속 갈래 종류에서 빌립니다(HT.relationOfKind).
     상위 띠 아래에 접히는 소속(singleHost)은 이미 상국 띠 밑에 들어 있으므로, 기관 · 왕조의 소속은 예속이 아니므로 뺍니다. 상국과 속국이 모두 그려질 때만(periods 안 — 트랙이 달라도).
     줄은 상국마다 밖 · 안을 따로, 속국의 그쪽 구간 전체(처음 ~ 끝)가 겹치지 않게 나눕니다 — 화면 범위가 아니라 자료로(높이는 자료가 정함).
     0번 줄이 상국 띠 아랫변에 가장 가깝습니다(매달린 탭은 띠 바로 밑, 품은 칸은 띠 안 맨 아래). 밖 ↔ 안을 옮긴 속국이 먼저 그 줄을 받고(세로 끈이 짧게), 나머지는 시작 순 ·
     같이 시작하면 오래 매인 쪽이 먼저.
     → Map(상국 uid → { items: [{ p, segs: [{ h, a, b, rel, look, side }], out, inn, outLane, inLane }], outLanes, inLanes }) */
  const depLook = (p, h) => {
    const rel = h.relation || (HT.relationOfKind ? HT.relationOfKind(p.polityKind) : '') || '';
    const r = rel && HT.relationInfo ? HT.relationInfo(rel) : null;
    if (!r || r.hollow || r.autonomy == null) return { rel, look: 'plain', side: 'out' };
    if (rel === 'nominal') return { rel, look: 'nominal', side: 'out' };
    if (rel === 'occupied') return { rel, look: 'occupied', side: 'in' };
    return r.autonomy >= 3 ? { rel, look: 'loose', side: 'out' } : r.autonomy === 2 ? { rel, look: 'firm', side: 'out' } : r.autonomy === 1 ? { rel, look: 'held', side: 'in' } : { rel, look: 'owned', side: 'in' };
  };
  /** 뒤 장의 구간(상국 표기 C — 뒤 장 _hostPlates · 상국 탭 _hostTabPlan 공용): 그 나라가 섬긴 상국마다 관계의 시작 ~ 끝 — 상국은 띠로 그려지는 정권일 때만
      (왕조 · 기관 · 문화는 뺌 — depProxies와 같은 조건 · 다른 트랙이어도 · 상국 띠가 화면에 없어도), 상위 띠 아래에 접힌 소속(singleHost)은 이미 상국 밑에 있으므로 없습니다.
      atL · atR = 관계가 띠의 첫머리 · 끝까지인가 · jl · jr = 같은 상국의 앞 · 뒤 구간과 맞닿음(관계만 바뀐 자리 — 뒤 장이 이어지고 짙기만 바뀜).
      칠의 짙기 · 선(look)은 상국 띠의 속국 이름표와 같은 자(depLook) → [{ h, k, a, b, l, r, look, rel, atL, atR, jl, jr }] (시작 차례) */
  const hostSegs = (p, X) => {
    if (!p.hosts || !p.hosts.length || p.singleHost) return [];
    const drawn = q => q && q.polityKind !== 'overlay' && q.polityKind !== 'dynasty' && q.polityKind !== 'culture';
    const segs = [];
    p.hosts.forEach((h, k) => {
      if (!h.host || !drawn(h.host)) return;
      const a = h.start ?? p.start;
      const b = h.end ?? p.endY;
      if (!(b > a)) return;
      const d = depLook(p, h);
      segs.push({ h, k, a, b, l: X(a), r: X(b), look: d.look, rel: d.rel, atL: a <= p.start, atR: b >= p.endY, jl: false, jr: false });
    });
    segs.sort((u, v) => u.l - v.l || u.r - v.r);
    for (const u of segs)
      for (const v of segs)
        if (u !== v && u.h.host === v.h.host && u.b === v.a) {
          u.jr = true;
          v.jl = true;
        }
    return segs;
  };
  const depProxies = periods => {
    const present = new Set(periods.map(p => p.uid));
    const byHost = new Map();
    const drawn = q => q && q.polityKind !== 'overlay' && q.polityKind !== 'dynasty' && q.polityKind !== 'culture';
    for (const p of periods) {
      if (!p.hosts || !p.hosts.length || !drawn(p)) continue;
      if (p.groupUid) continue; // 단체의 띠(리메이크 조각 ④ — 내보내기만)는 든 나라 띠 안의 집권 · 실권으로 보이므로 속국 이름표를 달지 않음
      for (const h of p.hosts) {
        if (!h.host || !present.has(h.host.uid) || !drawn(h.host)) continue; // 상국이 띠로 그려지는 정권일 때만 (왕조 · 기관 · 문화는 이름표를 달 띠가 없음)
        const a = h.start ?? p.start;
        const b = h.end ?? p.endY;
        if (!(b > a)) continue;
        const look = depLook(p, h);
        /* 상위 띠 아래에 접어 둔 소속(singleHost)은 이미 상국 띠 밑에 있으므로 예속이 아닌 소속(구성국 · 동군연합 · 관계 없음)이면 이름표를 달지 않습니다.
           접어 두었어도 예속 관계(조공 · 보호 · 식민 …)를 적었으면 깊이가 어디에도 보이지 않게 되므로 이름표를 답니다 */
        if (p.singleHost && look.look === 'plain') continue;
        if (!byHost.has(h.host.uid)) byHost.set(h.host.uid, new Map());
        const m = byHost.get(h.host.uid);
        if (!m.has(p.uid)) m.set(p.uid, { p, segs: [] });
        m.get(p.uid).segs.push(Object.assign({ h, a, b }, look));
      }
    }
    const out = new Map();
    for (const [uid, m] of byHost) {
      const items = [...m.values()];
      for (const it of items) {
        it.segs.sort((x, y) => x.a - y.a);
        for (const [key, side] of [['out', 'out'], ['inn', 'in']]) {
          const ss = it.segs.filter(s => s.side === side);
          it[key] = ss.length ? [Math.min(...ss.map(s => s.a)), Math.max(...ss.map(s => s.b))] : null;
        }
      }
      const lanes = (key, laneKey) => {
        const ends = [];
        const moved = x => (x.out && x.inn ? 0 : 1);
        for (const it of items.filter(x => x[key]).sort((x, y) => moved(x) - moved(y) || x[key][0] - y[key][0] || y[key][1] - x[key][1])) {
          let k = ends.findIndex(e => e <= it[key][0]);
          if (k < 0) k = ends.push(0) - 1;
          ends[k] = it[key][1];
          it[laneKey] = k;
        }
        return ends.length;
      };
      out.set(uid, { items, outLanes: lanes('out', 'outLane'), inLanes: lanes('inn', 'inLane') });
    }
    return out;
  };
  /** 그 줄에 잡힌 품은 칸 자리의 줄 수 (줄 단위 — 한 줄에 상국이 여럿이면 가장 많은 쪽으로 잡힙니다) */
  const depRowLanes = gr => Math.max(0, Math.round((gr.depH + G.slotGap) / (G.dep + G.slotGap)));
  /** 품은 칸 줄의 윗변 (예속 칸 자리 안에서): 0번 줄이 맨 아래 — 상국 띠 아랫변 · 매달린 탭에 가장 가까움.
      자리의 줄 수(그 줄 전체)로 재야 줄 수가 적은 상국의 칸도 띠 아랫변에 붙습니다 */
  const depInTop = (rowLanes, lane) => Math.max(0, rowLanes - 1 - lane) * (G.dep + G.slotGap);
  /** 세로 끈(밖 ↔ 안을 옮긴 때)이 x에서 다른 속국의 이름표를 지나는지: 이 속국의 품은 칸 줄보다 띠 아랫변에 가까운 품은 칸 · 매달린 탭 줄보다 띠에 가까운 탭 */
  const depLinkBlocked = (dep, it, X, x) =>
    dep.items.some(
      o =>
        o !== it &&
        o.segs.some(s => X(s.a) - 1 < x && x < X(s.b) + 1 && ((s.side === 'in' && o.inLane < it.inLane) || (s.side === 'out' && o.outLane < it.outLane)))
    );
  /* 책갈피 탭의 글 — 화면(_drawTrack)과 그림 내보내기(toSVG)가 이 하나로 정해 딱지의 차례 · 수 · 줄임이 늘 같습니다:
     이름 → 종류 딱지 → 실재성 딱지 → 지위 딱지(함께 들어갈 때만). 종속 갈래 · 소속 관계는 글자 딱지가 없습니다 — 상국 띠의 속국 이름표(depProxies)가 말합니다.
     room = 탭이 들 폭, rk = 지위 딱지로 붙일 지위 구간(tabRank) 또는 null.
     모두 들어가면 'full', 이름의 첫 글자만 들어가면 'short'(딱지 없이), 그것도 안 되면 '' → { mode, width(차지한 폭), kds: [{ t, rel }], hs, hsTag, rk } */
  const tabParts = (p, room, rk = null, ext = 0) => {
    const kind = p.polityKind || 'state';
    const hs = HT.historicityOf(p);
    const kds = !isDepKind(kind) && KIND_SHORT[kind] ? [{ t: KIND_SHORT[kind], rel: false }] : [];
    const hsTag = hs ? HT.historicityTag(hs) : '';
    const baseW = textWidth(p.name, 9.5, 700) + 14 + kds.reduce((s, k) => s + textWidth(k.t, 8.5) + 12, 0) + (hs ? textWidth(hsTag, 8.5) + 12 : 0) + (hs === 'legendary' ? 2 : 0);
    const rkNeed = rk ? textWidth(rk.name, 8.5) + 12 : 0;
    const rkOn = !!rk && room >= baseW + rkNeed + ext;
    const fullW = baseW + (rkOn ? rkNeed : 0) + ext; // ext = 간지 탭의 어깨 몫(TAB.ext × 2) — 온 이름 탭에만 더하고 첫 글자 탭은 예전 폭 그대로
    const shortW = textWidth(p.name.slice(0, 1), 9.5, 700) + 14; // 탭 글은 9px(감독 선택 2026-10-13 "글자 한 단계 작게" — 예전 10px) · 폭은 반 포인트 크게 9.5px로 잼(예전 10.5 / 10과 같은 어긋남)
    const mode = room >= fullW ? 'full' : room >= shortW ? 'short' : '';
    return { mode, width: mode === 'full' ? fullW : mode === 'short' ? shortW : 0, kds, hs, hsTag, rk: rkOn ? rk : null };
  };
  /* 탭의 지위 딱지로 붙일 지위: 지위 단이 없는 줄(rankH = 0)에서 지위가 하나뿐인 정권 (표시 체크 '지위'가 켜져 있을 때) */
  const tabRank = (p, show, rankH) => (show.ranks !== false && !rankH && p.rankSpans && p.rankSpans.length === 1 ? p.rankSpans[0] : null);
  /* 간지(디바이더)의 탭 — 감독 결정 2026-09-22(묶음 3 · 1번 'L'): 책갈피 탭은 띠(종이)의 윗변이 완만한 어깨로 솟은 것이고, 그 옆에 뒤 장(그 나라가 섬긴 상국)의 탭이 빼꼼 나옵니다.
     TAB.sh = 어깨 폭 7px(첫 글자만 적는 짧은 탭은 TAB.shShort 4px) · TAB.ext = 온 이름 탭이 예전 필름 탭보다 넓어지는 몫(한쪽 6px — 어깨 7 + 안 여백 6 = 13, 예전 안 여백 7 · 짧은 탭은 어깨 4 + 안 여백 3 = 7로 예전 폭 그대로) ·
     TAB.gap = 탭 사이 틈 · TAB.hostSize · hostWt = 뒤 장의 탭 글자. 탭의 발은 띠의 둥근 모서리(G.radius) 위에 두지 않고 모서리가 끝나 윗변이 평평해지는 곳부터, 오른쪽 평지 끝을 넘지 않습니다.
     화면(_drawTrack · _hostTabs) · 그림 내보내기(toSVG) · 새 앱(prototype/app/lib/scene/paint/bands.dart · hangs.dart)이 같은 값을 씁니다 */
  const TAB = { sh: 7, shShort: 4, ext: 6, gap: 4, hostSize: 8.5, hostWt: 600 };
  /* 서고 모양 2단 나-1(한 장 꼬리표 — 새 앱 bands.dart TagLook): 이름 색줄 키 14 · 구멍 가운데는 왼쪽 끝에서 7 · 이름은 구멍에서 7 뒤(14) · 이름은 오른쪽 끝 15 앞까지 · 탭 글의 안 여백 13.
     귀: 모따기 = 키 × 0.1(5 ~ 12) · 둥근 끝 = 키 × 0.22(12 ~ 24) — 이름 색줄은 탭 자리(G.tab 18) 안의 아래 14px라 줄 몫은 그대로 */
  const TAG = { head: 14, holeX: 7, holeY: 7, holeR: 2.5, diamondX: 7, diamondHalf: 3, name: 14, nameRight: 15, pad: 13 }; // holeY · holeR · diamondX · diamondHalf: 서고 3단의 구멍(세로 가운데 7 · 반지름 2.5) · 꼬리 마름모(오른쪽 끝에서 7 · 반 대각선 3 — 새 앱 TagLook)
  const tagCorner = (kind, h) => (kind === 'client' ? 0 : kind === 'movement' ? Math.round(HT.clamp(h * 0.22, 12, 24)) : Math.round(HT.clamp(h * 0.1, 5, 12)));
  const tagNameAt = (p, X, x1) => Math.max((p.startUnknown ? X(p.start) : x1) + TAG.name, 6); // 이름 글의 첫머리(화면 왼쪽 밖이면 가장자리 6px에 붙어 따라옴) // hostSize: 감독 선택 2026-10-13 "글자 한 단계 작게"(9.5 → 8.5 — 상국 탭 · 연합의 겹 탭)
  /** 탭 한 장의 윤곽(SVG path — 밑변 없음): 왼쪽 아래에서 어깨의 S자로 올라 윗변을 지나 오른쪽 아래로. (x, y)는 왼쪽 위 · w 폭 · h 높이(띠 밑에 든 1px까지) · s 어깨 폭 */
  const tabBump = (x, y, w, h, s) => {
    const f = v => Number(v).toFixed(2).replace(/\.?0+$/, '');
    return `M${f(x)},${f(y + h)} C${f(x + s * 0.6)},${f(y + h)} ${f(x + s * 0.4)},${f(y)} ${f(x + s)},${f(y)} L${f(x + w - s)},${f(y)} C${f(x + w - s * 0.4)},${f(y)} ${f(x + w - s * 0.6)},${f(y + h)} ${f(x + w)},${f(y + h)}`;
  };
  /** 화면의 탭 안에 넣는 <svg>: 칠(.f)과 선(.s)의 빛깔은 CSS(.tl-lane .tl-tab · .tl-htab)가 정합니다 */
  const tabSvg = (w, h, s) => `<svg width="${cx(w)}" height="${h}" viewBox="0 0 ${cx(w)} ${h}" aria-hidden="true"><path class="f" d="${tabBump(0, 0, w, h, s)} Z"/><path class="s" d="${tabBump(0, 0.5, w, h - 0.5, s)}"/></svg>`;
  /* 연합의 겹 탭(설계 7-8 결정 3 C + 덧판 x2 A — 감독 선택 2026-10-12 · '연합' 딱지 없이 모양으로): 상국 탭(뒤 장의 탭)과 같은 줄 · 같은 윤곽(tabBump · 어깨 TAB.sh)의 앞 장에,
     같은 윤곽의 둘째 장이 TAB.backDx(4px) 오른쪽 · TAB.backDy(3px) 위에 겹침 — 여러 장이 한 묶음으로 겹친 머리. 앞 장의 안 여백은 TAB.coalPad(9px) — 폭 = 글 + 18,
     요소 폭은 뒷장까지(+4 — 누르기 자리). 화면(_hostTabs) · 그림 내보내기(_hostTabsSVG) · 범례(Timeline.coalTabSample)가 같은 값 */
  Object.assign(TAB, { coalPad: 9, backDx: 4, backDy: 3 });
  /** 겹 탭의 <svg>: 뒤 장(칠 .bf · 선 .bs — 띠 윗변까지 내려와 띠가 덮음) 다음에 앞 장(.f · .s). 빛깔은 CSS(.tl-lane .tl-htab.k-coal) */
  const coalTabSvg = (w, h, s = TAB.sh) => {
    const dx = TAB.backDx;
    const dy = TAB.backDy;
    return `<svg width="${cx(w + dx + 1)}" height="${h}" viewBox="0 0 ${cx(w + dx + 1)} ${h}" aria-hidden="true"><path class="bf" d="${tabBump(dx, -dy, w, h + dy, s)} Z"/><path class="bs" d="${tabBump(dx, 0.5 - dy, w, h + dy - 0.5, s)}"/><path class="f" d="${tabBump(0, 0, w, h, s)} Z"/><path class="s" d="${tabBump(0, 0.5, w, h - 0.5, s)}"/></svg>`;
  };

  /* 실재성의 안개(toSVG — 화면은 common.css 끝의 '실재성'): 띠를 위에서 아래로 옅어지게 가리는 가림막. 전설은 띠 전체가, 반전설은 아래 1/3만 사라집니다.
     hs-h-*: 띠 뒤 선의 가림막(holes)에 쓰는 같은 모양의 검은 칠 — 화면에서 전설 · 반전설 띠는 바탕이 투명하고 안개만 아래로 옅어져 띠 뒤 선이 아래쪽으로 비쳐 보이므로, 그림도 안개만큼만 가림 */
  const HS_SVG_DEFS =
    '<linearGradient id="hs-h-legendary" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000"/><stop offset=".45" stop-color="#000" stop-opacity=".5"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>' +
    '<linearGradient id="hs-h-semi" x1="0" y1="0" x2="0" y2="1"><stop offset=".66" stop-color="#000"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>' +
    '<linearGradient id="hs-g-legendary" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".45" stop-color="#fff" stop-opacity=".5"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
    '<linearGradient id="hs-g-semi" x1="0" y1="0" x2="0" y2="1"><stop offset=".66" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
    '<mask id="hs-legendary" maskContentUnits="objectBoundingBox"><rect x="-.05" y="-.05" width="1.1" height="1.1" fill="url(#hs-g-legendary)"/></mask>' +
    '<mask id="hs-semi" maskContentUnits="objectBoundingBox"><rect x="-.05" y="-.05" width="1.1" height="1.1" fill="url(#hs-g-semi)"/></mask>';
  /* 그림 내보내기의 점령지 빗금 칸(화면의 .tl-dep.is-occupied — 가는 빗금 ＼, 전승 연대의 넓은 빗금 ／과 기울기 · 굵기가 다름) */
  const DEP_HATCH_SVG = '<pattern id="tl-dep-hatch" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(-45)"><rect width="1" height="4" fill="#000000" fill-opacity="0.32"/></pattern>';
  const reduceMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  /** 칸 하나의 날짜 구간 글 (지도자·연호·도읍 칸의 툴팁) — 날짜까지 적었으면 날짜로. 칸의 미정이면 그쪽은 "미정"
      (끝을 비운 도읍의 끝이 시작 미정인 다음 정도에서 짐작한 자리 — endYAuto — 여도 "미정").
      p(그 칸의 정권)를 주면 진행 중인 정권의 끝까지 가는 칸은 끝이 "현재" (HT.cellToNow — 연호 띠의 사본은 만들 때 toNow를 달아 둠) */
  const cellRange = (c, endKey = 'end', fallbackEnd = null, p = null) => {
    const s = c.startUnknown ? '미정' : HT.formatWhen(c, 'start');
    if (c.endUnknown || (endKey === 'endY' && c.endYAuto)) return `${s} ~ 미정`;
    if (c.toNow || HT.cellToNow(c, p)) return `${s} ~ 현재`;
    const ev = c[endKey] ?? fallbackEnd;
    if (ev == null) return `${s} ~`;
    const at = endKey === 'endY' ? c.endYAt || c.endAt : c[`${endKey}At`];
    return `${s} ~ ${HT.formatDate(ev, at)}`;
  };
  /** 칸의 다른 견해를 설명글 줄로 (도읍 노선도의 역 설명글 — 상세 창과 같은 글 HT.altText, 비운 쪽은 그 칸의 연대 · 디테일 건의 4) */
  const cellAltTip = c => ((c && c.alternatives) || []).map(a => `\n  다른 견해 — ${HT.altText(a, { start: c.start, startAt: c.startAt, end: c.endY ?? c.end, endAt: c.endYAt || c.endAt, startUnknown: c.startUnknown, endUnknown: c.endUnknown })}`).join('');
  /* 칸의 미정 — 띠의 미정 끝과 같은 말투: 미정인 쪽 끝이 칸 안에서 옅어지며 사라지고(이웃 칸은 덮지 않음) 그쪽 테두리 · 구분선이 점선.
     이어 붙은 쪽(j-l · j-r)은 끝까지 사라지지 않고 옅어지기만 해서 하나의 긴 둥근 칸이 끊겨 보이지 않습니다 (CSS '칸의 미정').
     c = 칸(startUnknown · endUnknown), prev = 바로 앞에 이어 붙은 칸(그 끝이 미정이면 사이 구분선 — 이 칸의 왼쪽 테두리 — 도 점선: u-l),
     w = 칸 너비, tw = 가운데 놓인 이름표의 글자 너비(없으면 null) — 꼬리가 글자까지 먹어 들어가지 않게,
     cutL · cutR = 그쪽 끝이 화면 밖에서 잘렸음(진짜 끝이 보이지 않으니 사라지는 꼬리도 없음) → { cls, css, s, e, f(꼬리 길이) } */
  const unkCell = (c, prev, jl, w, tw = null, cutL = false, cutR = false) => {
    const s = !!c.startUnknown && !cutL;
    const e = !!c.endUnknown && !cutR;
    const ul = jl && !!prev && !!prev.endUnknown;
    if (!s && !e && !ul) return { cls: '', css: '' };
    const f = Math.max(3, Math.min(FADE, w * 0.4, tw != null ? (w - tw) / 2 : w * 0.3));
    return { cls: `${s ? ' unk-s' : ''}${e ? ' unk-e' : ''}${ul ? ' u-l' : ''}`, css: `${s ? `;--fl:${cx(f)}px` : ''}${e ? `;--fr:${cx(f)}px` : ''}`, s, e, f };
  };
  /** 소속(예속) 기간의 글: 비운 쪽은 그 정권의 시작 · 끝, 미정인 쪽은 "미정" (예속 띠 · 소속선의 설명) */
  const hostRange = (h, p) =>
    `${h.startUnknown ? '미정' : h.start != null ? HT.formatDate(h.start, h.startAt) : HT.formatWhen(p, 'start')} ~ ${h.endUnknown ? '미정' : h.end != null ? HT.formatDate(h.end, h.endAt) : HT.formatDate(p.endY, p.endAt)}`;

  /* ---------- 칸의 이설 · 모호한 칸 (디테일 건의 4 뒷부분 — 감독 답 '기본적으로 유령 구분선을 쓰고, 이설이 아니라 자체가 모호하면 띠 같이 흐려지게, 점선 등') ----------
   * 유령 구분선: 이설이 말하는 경계 해마다 칸 높이만 한 옅은 점선(1px 점 · 1 켜고 2 끔, 위아래 2px 들임) — 진짜 구분선(실선)은 그대로 둡니다.
   *   진짜 구분선 · 칸 끝에서 3px 안이면(또는 띠 밖 · 칸의 미정 꼬리 안 · 이름표를 비킬 자리가 없으면) 선 대신 그 칸 이름 밑에 옅은 점선 하나('이설 있음').
   *   선이 이름표 글자에 닿으면 이름표를 적게 움직이는 쪽으로 선에서 3px까지 비킵니다(칸 끝과도 3px). 빽빽하게 뭉친 칸 · '인물 n명' 칸 · 8px보다 좁은 칸 · 조감에는 없음.
   * 모호한 칸(확실성 · 연대 폭 — 이설이 아니라 연대 자체가 흐림): 띠의 연대 폭처럼 그 구간의 칸 바탕에 무늬(추정 = 세로 줄 · 전승 = 빗금 — 이름표 글자는 비켜서),
   *   그 구간 안의 구분선(이웃 칸과 나눠 쓰는 경계)과 칸 끝은 점선. 미정(진짜 경계가 대시 + 칸이 옅어지며 사라짐)과 달리 칸은 옅어지지 않고 무늬만 · 경계는 점.
   * 자리는 모두 한 순수 함수(altRowPlan)가 정합니다 — 화면(_drawTrack · 날짜 칸)과 그림 내보내기(toSVG)가 같은 답 */
  const ALT_GAP = 3; // 유령선이 진짜 구분선 · 칸 끝 · 이름표 글자와 떨어질 거리(px)
  const ALT_MIN_W = 8; // 이보다 좁은 칸에는 표식을 달지 않음
  /** 칸 c의 이설이 말하는 경계 [{ y, side: 's' | 'e' }] — base = 칸의 통설 구간(HT.altSpan이 비운 쪽을 채우는 값 · 상세 창의 '다른 견해'와 같은 값).
      이설이 적은 쪽만, 통설과 같은 해는 뺍니다. 현재까지인 이설의 끝은 now(그 정권의 끝). 같은 해는 한 번만.
      빈 쪽을 통설 값으로 채우면 앞뒤가 뒤집히는 이설(HT.altFlipped — 적지 않은 끝을 풀어 둔 값과 견줌)은 긋지 않습니다(상세 창의 '다른 견해'에 까닭과 함께) */
  const altEdges = (c, base, now = null) => {
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
  /**
   * 칸 한 줄의 유령 구분선 자리 (순수 함수 — 화면 · 그림 내보내기 · dev-smoke가 함께 씀).
   * cells: 그 줄에 그려진 칸 [{ l, r, ink: { c: 글자 가운데, w: 글자 폭 } | null, fixed: 이름표를 옮길 수 없음, fade: [[a, b]] 칸의 미정 꼬리 }] (줄 좌표)
   * marks: 이설의 경계 [{ x, owner: 칸 번호, key }] — 제 칸 안 · 이웃 칸 안 · 칸 사이 빈자리 어디든(같은 줄 안)
   * lo · hi: 선을 그을 수 있는 범위(띠 안쪽), far(key, 거리): 진짜 경계에서 충분히 먼가(화면은 문턱 둘 — _past, 그림은 거리 ≥ 3)
   * → { lines: [{ x, owner, key }], has: Set(선을 하나도 긋지 못한 칸 번호 — 이름 밑 '이설 있음'), shift: Map(칸 번호 → 이름표를 옮길 px) }
   */
  const altMarks = (cells, marks, { lo = -Infinity, hi = Infinity, far = (k, d) => d >= ALT_GAP } = {}) => {
    const miss = new Set();
    const edges = cells.flatMap(c => [c.l, c.r]);
    let lines = [];
    for (const m of marks) {
      if (!cells[m.owner]) continue;
      const d = edges.length ? Math.min(...edges.map(e => Math.abs(e - m.x))) : Infinity;
      const ok = far(m.key, d); // 문턱의 기억은 그리기마다 (띠 밖이어도)
      if (m.x < lo || m.x > hi - 1 || !ok || cells.some(c => c.fade && c.fade.some(([a, b]) => m.x >= a - 1 && m.x <= b + 1))) {
        miss.add(m.owner);
        continue;
      }
      if (lines.some(q => Math.abs(q.x - m.x) < ALT_GAP)) continue; // 같은 자리의 이설(앞 칸의 끝 = 뒤 칸의 시작 …) — 선 하나
      lines.push(m);
    }
    const shift = new Map();
    cells.forEach((c, i) => {
      if (!c.ink) return;
      const inside = lines.filter(m => m.x >= c.l && m.x < c.r);
      const L = c.ink.c - c.ink.w / 2;
      const R = c.ink.c + c.ink.w / 2;
      const hits = inside.filter(m => m.x + 1 > L - ALT_GAP && m.x < R + ALT_GAP);
      if (!hits.length) return;
      /* 이름표 가운데가 설 수 있는 구간(칸 테두리 안 3px) − 선마다 글자가 3px보다 가까워지는 구간 → 가장 적게 옮기는 자리 */
      let to = null;
      if (!c.fixed) {
        const w = c.ink.w;
        let segs = [[c.l + 1 + ALT_GAP + w / 2, c.r - 1 - ALT_GAP - w / 2]];
        for (const m of inside) {
          const a = m.x - ALT_GAP - w / 2;
          const b = m.x + 1 + ALT_GAP + w / 2;
          segs = segs.flatMap(([s, e]) => [[s, Math.min(e, a)], [Math.max(s, b), e]]).filter(([s, e]) => e >= s);
        }
        for (const [s, e] of segs) {
          const v = HT.clamp(c.ink.c, s, e);
          if (to == null || Math.abs(v - c.ink.c) < Math.abs(to - c.ink.c) - 1e-9) to = v;
        }
      }
      if (to != null) shift.set(i, to - c.ink.c);
      else {
        lines = lines.filter(m => !hits.includes(m));
        for (const m of hits) miss.add(m.owner);
      }
    });
    const drawn = new Set(lines.map(m => m.owner));
    return { lines, has: new Set([...miss].filter(i => !drawn.has(i))), shift };
  };
  /* 이름표 글자 잉크의 아래 끝(칸 위에서, px) — 칸 가운데에 선 글줄(줄 높이 lh)의 기준선 + 글자의 아래 잉크.
     기준선은 화면에서 한 번 재어 둔 값(글꼴 · 굵기 · 크기 · 줄 높이마다 — 글꼴의 소수 값이 캔버스보다 정확), 잴 수 없으면(노드) 캔버스 값으로 셈 */
  const inkMetrics = new Map();
  const baseMemo = new Map();
  const inkBottom = (text, size, wt, h, lh = size * 1.2) => {
    const key = `${wt}|${size}|${text}`;
    let m = inkMetrics.get(key);
    if (!m) {
      measureCtx.font = FONT(size, wt);
      const t = measureCtx.measureText(text);
      m = { A: t.fontBoundingBoxAscent || size * 0.88, D: t.fontBoundingBoxDescent || size * 0.22, d: t.actualBoundingBoxDescent ?? size * 0.1 };
      inkMetrics.set(key, m);
    }
    const bk = `${wt}|${size}|${lh}`;
    let off = baseMemo.get(bk);
    if (off == null) {
      off = (lh - (m.A + m.D)) / 2 + m.A;
      try {
        const box = document.createElement('div');
        box.style.cssText = `position:absolute;left:-9999px;top:0;visibility:hidden;white-space:nowrap;font:${FONT(size, wt).replace(/(\d+(\.\d+)?px)/, `$1/${lh}px`)}`;
        box.innerHTML = '가<i style="display:inline-block;width:0;height:0;vertical-align:baseline"></i>';
        document.body.appendChild(box);
        const v = box.lastChild.getBoundingClientRect().bottom - box.getBoundingClientRect().top;
        box.remove();
        if (isFinite(v) && v > 0) off = v;
      } catch (e) {
        /* 노드(검사)에서는 캔버스 값 그대로 */
      }
      baseMemo.set(bk, off);
    }
    return (h - lh) / 2 + off + m.d;
  };
  /* 모호한 칸의 무늬: 띠의 연대 폭(.tl-zone)과 같은 말 — 추정 = 세로 줄, 그 밖(전승 · 확실) = 빗금. 칸 바탕 위 · 이름표 글자 밑에 (화면은 CSS 줄무늬, 그림은 같은 간격의 선) */
  const zoneKindOf = c => ((c && c.certainty) === 'legend' ? 'legend' : 'estimated'); // 확실 · 통설인데 연대 폭만 적은 칸도 추정의 무늬 (확실은 흐림이 아님)
  /**
   * 칸 한 줄의 이설 · 모호한 칸 계획 (순수 — 화면 · 그림 내보내기 공용).
   * row: 그 줄에 그려진 칸 [{ l, r, jl, jr, c: 칸 자료(이설 · 확실성 · 연대 폭), base: 통설 구간(altEdges), key, ink: { text, size, wt } | null, fixed, bl · br(좌우 테두리 두께), fade, hasMax(이름 밑 점선의 가장 낮은 y — 가문 줄 위) }]
   * o: { X(해 → 줄 좌표), now, lo, hi, h(칸 높이), far, minW(표식을 달 칸 폭 — 문턱 둘이면 함수 wide(u, w)) }
   * → { lines, has: [{ i, x0, x1, y }](y = 칸 위에서), shift: Map, zones: Map(i → { layers: [{ a, b, kind }](칸 왼쪽 끝에서), zl, zr }) }
   */
  const altRowPlan = (row, o) => {
    if (!row.some(u => u.c && HT.drawsUncertainty(u.c))) { // 줄에 그릴 이설 · 모호함이 없으면 계산하지 않음 (프레임마다 부르므로) — 조명 경계 비킴(o.litEdges)만
      const plan = { lines: [], has: [], shift: new Map(), zones: new Map() };
      return o.litEdges ? litShift(row, plan, o.litEdges) : plan;
    }
    const cells = row.map(u => {
      let ink = null;
      if (u.ink && u.ink.text) {
        const w = u.fixed ? Math.max(0, u.r - u.l - 2) : textWidth(u.ink.text, u.ink.size, u.ink.wt);
        ink = { c: u.ink.c ?? (u.l + (u.bl ?? 1) + u.r - (u.br ?? 1)) / 2, w }; // ink.c = 이름표 글자의 가운데(왼쪽 맞춤 이름표 — 구역 탭), 없으면 칸 가운데
      }
      return { l: u.l, r: u.r, ink, fixed: !!u.fixed, fade: u.fade || null };
    });
    const marks = [];
    if (o.alt !== false)
      row.forEach((u, i) => {
        if (!u.c || !u.base || !(u.c.alternatives && u.c.alternatives.length)) return;
        if (!(o.wide ? o.wide(u, u.r - u.l) : u.r - u.l >= (o.minW ?? ALT_MIN_W))) return;
        for (const e of altEdges(u.c, u.base, u.now ?? o.now)) marks.push({ x: o.X(e.y), owner: i, key: `${u.key}|${e.y}` });
      });
    const { lines, has, shift } = altMarks(cells, marks, o);
    /* 칸 이름표가 조명 경계를 비킴(litShift — 띠 안의 칸 줄): 유령선을 비킨 자리에서 한 번 더 — '이설 있음' 점선 · 무늬의 글자 자리가 옮긴 이름을 따라가게 이 다음에 셈 */
    const lit = o.litEdges ? litShift(row, { lines, shift }, o.litEdges) : null;
    const hasOut = [];
    for (const i of has) {
      const u = row[i];
      const c = cells[i];
      if (!c.ink || c.fixed || c.ink.w < 4) continue;
      const ib = inkBottom(u.ink.text, u.ink.size, u.ink.wt, o.h, u.ink.lh);
      const y = Math.min(u.hasMax ?? o.h - 3, Math.round((ib + 1) * 2) / 2); // 글자 1px 밑 — 아래 테두리(가문 줄이 있으면 그 줄)와는 적어도 1px (칸 안쪽 · hasMax = 칸마다의 아래 한계)
      if (y < ib + 0.25) continue; // 얇은 칸: 글자와 아래 테두리 사이에 1px 점선이 들 자리가 없음 — 표시 없이(상세 창의 '다른 견해'에)
      const cc = c.ink.c + (shift.get(i) || 0);
      hasOut.push({ i, x0: cc - c.ink.w / 2, x1: cc + c.ink.w / 2, y });
    }
    /* 모호한 칸: 연대 폭([이른, 늦은]) · 폭 없이 확실성만 적은 칸은 칸 전체(양옆 경계도 모호) — 같은 줄의 칸들에 걸쳐 */
    const zones = new Map();
    if (o.zone !== false) {
      const spans = [];
      row.forEach(u => {
        const c = u.c;
        if (!c) return;
        const kind = zoneKindOf(c);
        const rs = [c.startRange, c.endRange].filter(Boolean);
        for (const [a, b] of rs) spans.push({ a: o.X(a), b: o.X(b), kind });
        if (!rs.length && (c.certainty === 'estimated' || c.certainty === 'legend')) spans.push({ a: u.l - 0.5, b: u.r + 0.5, kind });
      });
      if (spans.length)
        row.forEach((u, i) => {
          const c = cells[i];
          const inL = u.l + (u.bl ?? 1);
          const inR = u.r - (u.br ?? 1);
          const ink = c.ink && !c.fixed ? [c.ink.c + (shift.get(i) || 0) - c.ink.w / 2 - ALT_GAP - 0.5, c.ink.c + (shift.get(i) || 0) + c.ink.w / 2 + ALT_GAP + 0.5] : c.ink ? [inL, inR] : null; // 글자에서 3px + 반 픽셀(자간 · 반올림 여유)
          const layers = [];
          let zl = false;
          let zr = false;
          for (const z of spans) {
            const a = Math.max(z.a, inL);
            const b = Math.min(z.b, inR);
            if (u.l > z.a + 0.25 && u.l < z.b - 0.25) zl = true; // 이 칸의 왼쪽 경계(이어 붙은 칸이면 사이 구분선)가 연대 폭 안
            if (!u.jr && u.r > z.a + 0.25 && u.r < z.b - 0.25) zr = true; // 이어 붙지 않은 오른쪽 끝이 연대 폭 안
            if (b - a < 1) continue;
            const parts = ink ? [[a, Math.min(b, ink[0])], [Math.max(a, ink[1]), b]] : [[a, b]];
            for (const [p, q] of parts) if (q - p >= 1) layers.push({ a: p - u.l, b: q - u.l, kind: z.kind });
          }
          if (layers.length || zl || zr) zones.set(i, { layers, zl, zr });
        });
    }
    return { lines, has: hasOut, shift, zones, litDim: lit && lit.litDim };
  };
  /**
   * 칸 이름표가 조명 경계(같은 시기를 타국에도 — 흐린 띠의 흐리지 않는 구간 · 조명 칠의 끝선)에 걸치지 않게 (순수 — 화면 · dev-smoke).
   * 경계는 이름을 반으로 갈라 한쪽만 밝게 하고(띠의 가림 판 --lm · 칸 안의 판 --lp) 칠의 끝선이 글자를 지나므로, 이름 가운데가 든 쪽(조명 안 · 밖)으로
   * 경계에서 ALT_GAP + 1px(끝선 굵기) 떨어질 만큼 옮깁니다 — 이름 전체가 그쪽 밝기(조감 띠 안 이름의 is-lit과 같은 규칙: 가운데가 구간 안이면 밝게, 밖이면 흐리게).
   * 그쪽에 자리가 없으면 반대쪽, 둘 다 없으면 옮기지 않고 plan.litDim에 적음(칸 전체를 흐린 쪽 밝기로 고르게 — _litCls(…, true)의 lit-flat). 칸 바탕 · 테두리는 경계를 그대로 따름.
   * row: altRowPlan과 같은 칸 목록(ink · fixed · l · r · bl · br) · plan: altRowPlan의 결과(shift · lines — 유령선도 비킴) · edges: 경계 x들(띠 안쪽 좌표)
   */
  const litShift = (row, plan, edges) => {
    row.forEach((u, i) => {
      if (!u.ink || !u.ink.text) return;
      const move = !u.fixed || !!u.litL; // 칸을 채운 이름(앞글자 …)은 옮기지 않음 — 딱지가 붙은 시기 이름(litL = 딱지 오른쪽 끝)은 딱지 뒤의 자리 안에서
      const inL = u.litL ?? u.l + (u.bl ?? 1);
      const inR = u.r - (u.br ?? 1);
      const base = u.litL != null ? (inL + inR) / 2 : u.ink.c ?? (inL + inR) / 2;
      const w = move ? textWidth(u.ink.text, u.ink.size, u.ink.wt) : Math.max(0, u.r - u.l - 2);
      const c0 = base + (plan.shift.get(i) || 0);
      const pad = ALT_GAP + 1;
      const es = edges.filter(e => e > inL + 0.5 && e < inR - 0.5).sort((a, b) => a - b);
      if (!es.some(e => e > c0 - w / 2 - pad && e < c0 + w / 2 + pad)) return;
      if (!move) return void (plan.litDim || (plan.litDim = new Set())).add(i);
      const cuts = [inL - 1].concat(es, [inR + 1]); // 칸 끝은 유령선과 같은 자리 셈(테두리 1 + ALT_GAP) — 경계와 같은 pad가 되게 1px 밖에서
      const ghosts = plan.lines.filter(m => m.x >= u.l && m.x < u.r);
      const room = k => {
        let segs = [[cuts[k] + pad + w / 2, cuts[k + 1] - pad - w / 2]].filter(([s, e]) => e >= s);
        for (const m of ghosts) {
          const a = m.x - ALT_GAP - w / 2;
          const b = m.x + 1 + ALT_GAP + w / 2;
          segs = segs.flatMap(([s, e]) => [[s, Math.min(e, a)], [Math.max(s, b), e]]).filter(([s, e]) => e >= s);
        }
        let to = null;
        for (const [s, e] of segs) {
          const v = HT.clamp(c0, s, e);
          if (to == null || Math.abs(v - c0) < Math.abs(to - c0) - 1e-9) to = v;
        }
        return to;
      };
      const own = cuts.findIndex((x, k) => k + 1 < cuts.length && c0 >= x && c0 < cuts[k + 1]);
      let to = own >= 0 ? room(own) : null;
      if (to == null)
        for (let k = 0; k + 1 < cuts.length; k++) {
          if (k === own) continue;
          const v = room(k);
          if (v != null && (to == null || Math.abs(v - c0) < Math.abs(to - c0))) to = v;
        }
      if (to != null) plan.shift.set(i, to - base);
      else (plan.litDim || (plan.litDim = new Set())).add(i);
    });
    return plan;
  };
  /**
   * 조감의 띠 안 이름 자리 box = [왼, 오른](글자 + 둘레 — 띠 안쪽 좌표)에서 조명 칠 · 가림 판의 경계가 글자를 가로지르지 않게 (순수 — 화면 · dev-smoke):
   * 이름 가운데가 든 토막이 이름 자리를 다 덮도록 늘리고, 다른 토막은 이름 자리 밖에서 끝나게 — 가운데가 어느 토막에도 없으면 모든 토막이 이름 자리 밖에서 끝남
   * (이름의 밝기 is-lit — 가운데가 흐리지 않는 구간 안이면 밝게 — 과 같은 규칙. 띠 안 이름은 띠 시작에 고정이라 옮기지 않고 경계를 옮김). segs: [[왼, 오른, …]]
   */
  const nameSnap = (segs, box) => {
    if (!box || !segs.length) return segs;
    const [nl, nr] = box;
    const c = (nl + nr) / 2;
    const host = segs.findIndex(([a, b]) => a <= c && c <= b);
    const out = [];
    segs.forEach((s, i) => {
      let [a, b] = s;
      if (i === host) {
        a = Math.min(a, nl);
        b = Math.max(b, nr);
      } else {
        if (a > nl && a < nr) a = nr;
        if (b > nl && b < nr) b = nl;
      }
      if (b - a > 0.5) out.push([a, b].concat(s.slice(2)));
    });
    return out;
  };
  /** 칸의 통설 구간 — 유령선이 견주는 값 = 상세 창 '다른 견해'의 첫 줄(viewer.js cellBase와 같은 식): 적힌 시작 · 연표에 놓인 끝(비운 끝은 풀어 둔 끝) · 미정 · 현재까지 */
  const cellBaseOf = (c, p, ref) => {
    if (!(c && c.alternatives && c.alternatives.length)) return null; // 이설이 없는 칸은 셈하지 않음 (쓰는 곳은 이설의 경계 · 설명글뿐 — 프레임마다 모든 칸이 부르므로)
    const sp = HT.cellSpan(c, p, ref);
    return { start: sp.start, startAt: c.startAt, end: sp.end, endAt: sp.endAt, startUnknown: c.startUnknown, endUnknown: !!(c.endUnknown || (c.end == null && c.endYAuto)), ongoing: HT.cellToNow(c, p) };
  };
  /** 칸의 미정 꼬리(unkCell)의 구간 — 그 안에는 유령선을 긋지 않음 (꼬리는 칸과 함께 옅어지지만 선은 칸의 가림막을 받지 않으므로) */
  const unkFade = (unk, l, r) => {
    const out = [];
    if (unk && unk.s) out.push([l, l + unk.f]);
    if (unk && unk.e) out.push([r - unk.f, r]);
    return out.length ? out : null;
  };
  /** 설명글 끝의 다른 견해 줄 (칸 · 막대에 올렸을 때 — 상세 창과 같은 글 HT.altText, 비운 쪽은 통설 값) */
  const altTip = (c, base) => ((c && c.alternatives) || []).map(a => `\n  다른 견해 — ${HT.altText(a, base || {})}`).join('');
  /** 인물의 통설 연대 (이설의 빈 칸을 채우는 값 — viewer.js figureBase와 같은 식: 끝은 풀어 둔 활동 끝) */
  const FIG_KEYS = ['start', 'end', 'birth', 'death'];
  const figBaseOf = f => ({ birth: f.birth, birthAt: f.birthAt, death: f.death, deathAt: f.deathAt, start: f.start, startAt: f.startAt, end: f.endY, endAt: f.endYAt, ongoing: f.ongoing, startUnknown: f.startUnknown, endUnknown: f.endUnknown });
  /** 인물 활동 막대 하나의 이설 · 모호한 연대 — 섬긴 기록 줄의 것에, 인물의 활동 시작 · 끝 이설을 이 막대의 끝이 곧 활동의 끝일 때만 더함 (생몰의 이설은 수명선의 고리로) */
  const figBarCell = (f, s) => {
    const list = ((s && s.alternatives) || []).slice();
    const atS = Math.abs(s.from - f.start) < 1e-9;
    const atE = Math.abs(s.to - f.endY) < 1e-9;
    for (const a of f.alternatives || []) {
      if (HT.altFlipped(a, figBaseOf(f), FIG_KEYS)) continue; // 생몰 · 활동 시기와 앞뒤가 뒤집힌 이설은 그리지 않음 (상세 창에 까닭과 함께)
      const o = {};
      if (atS && a.start != null) Object.assign(o, { start: a.start, startAt: a.startAt });
      if (atE && a.ongoing === true) o.ongoing = true;
      else if (atE && a.end != null) Object.assign(o, { end: a.end, endAt: a.endAt });
      if (Object.keys(o).length) list.push(Object.assign(o, { label: a.label }));
    }
    return { alternatives: list, certainty: s.certainty, startRange: s.startRange, endRange: s.endRange };
  };
  /** 왕조 칸 하나의 이설 — 다스린 정권 줄(polities)의 것에, 왕조 항목 자신의 이설(시작 · 끝)을 이 칸의 끝이 곧 왕조의 시작 · 끝일 때만 더함
      (인물 막대의 figBarCell과 같은 규칙 — 왕조가 여러 나라를 다스렸으면 그 끝에 닿은 칸에만). 더할 것이 없으면 줄 그대로 */
  const dynCellOf = (d, y) => {
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
  /** 기관 · 구역 항목의 통설 구간 (항목 자신의 이설이 견주는 값 — 칸 하나짜리 줄) */
  const itemBaseOf = p => ({ start: p.start, startAt: p.startAt, end: p.endY, endAt: p.endAt, startUnknown: p.startUnknown, endUnknown: p.endUnknown, ongoing: p.ongoing });
  const zoneCls = z => (z ? `${z.layers.length ? ' has-zone' : ''}${z.zl ? ' z-l' : ''}${z.zr ? ' z-r' : ''}` : '');
  /* 모호한 칸 무늬의 CSS (칸 안쪽 — 칸의 테두리 안 왼쪽 끝이 0): 무늬 층마다 제 자리 · 폭 */
  const ZONE_GRAD = { estimated: 'repeating-linear-gradient(90deg,var(--zc) 0 1.5px,transparent 1.5px 4px)', other: 'repeating-linear-gradient(135deg,var(--zc) 0 1.5px,transparent 1.5px 4.5px)' };
  const zoneCss = (z, bl = 1) =>
    z.layers.length
      ? `;background-image:${z.layers.map(q => ZONE_GRAD[q.kind === 'estimated' ? 'estimated' : 'other']).join(',')};background-size:${z.layers.map(q => `${cx(q.b - q.a)}px 100%`).join(',')};background-position:${z.layers.map(q => `${cx(q.a - bl)}px 0`).join(',')};background-repeat:no-repeat`
      : '';

  /* ---------- 요소 다시 쓰기 (morph) ----------
     그릴 때마다 innerHTML을 통째로 바꾸면 요소가 매번 새로 태어나 CSS 전환이 이어지지 않고, 나타나고 사라지는 것을 다듬을 수 없습니다.
     data-k(고유 키)가 붙은 요소는 같은 키의 기존 요소를 그대로 두고 속성·내용만 맞춥니다. 새로 생긴 요소(born)와 이름이 새로 붙은 사건(relabeled)을
     돌려주어 살짝 떠오르게 합니다. 흩어지며 사라지는 잔상(_ghost)은 건드리지 않습니다 */
  const tpl = document.createElement('template');
  const SQZ_NEAR = 120; // 밀도가 바뀌는 흐름에서 화면 위아래로 이만큼 안에 드는 트랙까지 줄 안의 움직임을 겁니다 (_squashAway — 탭 · 잔상의 위쪽 여유)
  const SQZ_NONE = new Set(); // 밀도가 바뀐 뒤의 첫 그리기: 앞선 화면에 있던 키가 없다고 치면 새 줄 안의 것이 모두 새로 생긴 것 (morph의 known — _squash)
  const KEEP_CLASS = ['mk-selected', 'is-hot', 'is-selected', 'is-match', 'is-dim', 'is-onrow', 'is-city', 'is-carded', 'is-arrived', 'is-echo-hit', 'echo-out', 'is-hit'];
  const syncAttrs = (o, n) => {
    for (const a of n.attributes) {
      if (a.name === 'class') {
        const keep = KEEP_CLASS.filter(c => o.classList.contains(c));
        const v = keep.length ? `${a.value} ${keep.join(' ')}` : a.value;
        if (o.getAttribute('class') !== v) o.setAttribute('class', v);
      } else if (o.getAttribute(a.name) !== a.value) o.setAttribute(a.name, a.value);
    }
    for (const a of [...o.attributes]) if (!n.hasAttribute(a.name)) o.removeAttribute(a.name);
  };
  /* 사라짐 다듬기: 화면 안에 있던 요소만 옅어지며 물러납니다 (화면 밖으로 밀려나 없어지는 것은 그대로 — 움직일 이유가 없음).
     시작 밝기는 적지 않습니다 — 지금 밝기에서(고른 것이 있어 어두워진 장면이면 그 밝기에서) 옅어지므로 번쩍이지 않습니다.
     멈춰 있을 때는 제자리에서 160ms(--t-out), 움직이는 중에는 세계 좌표를 따라가며 120ms (Timeline._linger — fx.out이 고릅니다) */
  const inViewX = (el, W) => {
    const l = parseFloat(el.style.left);
    if (isNaN(l)) return true;
    const w = parseFloat(el.style.width) || 0;
    return l + w > -24 && l < W + 24;
  };
  const fadeOut = (el, dur = HT.motion.T.out, easing = 'ease-in', done = null) => {
    el._ghost = true;
    el.classList.add('is-leaving');
    el.style.pointerEvents = 'none';
    el.removeAttribute('data-uid'); // 물러나는 잔상은 찾기·고르기의 대상이 아닙니다
    const a = el.animate([{ opacity: 0 }], { duration: dur, easing, fill: 'forwards' });
    a.onfinish = a.oncancel = () => {
      el.remove();
      if (done) done();
    };
  };
  /* 이름이 떨어져 점만 남는 사건: 글자만 잔상으로 남겨 옅어지게 (점은 제자리에 그대로) */
  const ghostLabel = (o, fx) => {
    const g = o.cloneNode(true);
    g._ghost = true;
    const d = g.querySelector('.d');
    if (d) d.remove();
    g.removeAttribute('data-k');
    g.removeAttribute('data-uid');
    g.removeAttribute('title');
    o.parentNode.insertBefore(g, o.nextSibling);
    fx.out(g);
  };
  /* 속까지 다시 쓰는 요소: 정권 띠(.tl-band) · 인물 막대(.tl-fig) · 기관 칸(.tl-org)의 속은 통째로 갈지 않고 한 겹 더 morph — 키(data-k)가 붙은 속 요소(칸 이설의 유령 구분선 ·
     이설 조명)만 제자리에 남아 떠오르고 옅어집니다(움직임 원칙 ②). 키 없는 속 요소(칸 · 무늬 …)는 예전처럼 새로 태어나고 조용히 치워집니다 (fx.deep) */
  const DEEP = el => el.classList.contains('tl-band') || el.classList.contains('tl-fig') || el.classList.contains('tl-org');
  const tpls = [tpl]; // 겹마다 제 틀 (바깥 morph가 틀의 자식을 도는 동안 속 morph가 그 틀을 갈아 쓰지 않게)
  /* fx = { W, quiet, out(el), deep } (Timeline._fx) — 없으면 효과 없이 그냥 바꿉니다 */
  function morph(host, html, fx = null, known = null, depth = 0, retainEvents = false) {
    /* 같은 배율로 옮길 때 사건은 이미 지은 요소를 그대로 씁니다. 띠·이름표만 고치며,
       사건의 글과 도형을 다시 해석하거나 떼어 붙이지 않습니다. 다음 배치에서는 일반 경로로 돌아옵니다. */
    const retained = el => retainEvents && el.nodeType === 1 && el.hasAttribute('data-pan');
    if (host._html === html) return null;
    /* 처음 채우는 줄은 통째로 그냥 나타납니다. 다만 다시 지은 줄(known = 앞선 화면에 있던 키들)이면 그때 없던 것만 새로 생긴 것으로 칩니다 */
    const first = host._html == null;
    host._html = html;
    const tpl = tpls[depth] || (tpls[depth] = document.createElement('template'));
    tpl.innerHTML = html;
    /* 속 겹: 키 없는 옛 요소(칸 · 무늬 …)는 어차피 새로 태어나므로 먼저 치웁니다 — 남겨 두면 키가 붙은 요소가 그 앞뒤로 옮겨 끼워지며(떼었다 붙임)
       CSS 전환(조명된 칸의 유령선이 짙어지는 --gc)이 끊깁니다 */
    /* 키가 붙었지만 이번에 없어지는 요소(다른 칸으로 옮긴 이설 조명 …)도 먼저 물러나게(잔상) — 그래야 남는 요소가 그것을 건너 옮겨지지 않습니다 */
    if (depth) {
      const keep = new Set([...tpl.content.children].map(n => n.dataset.k).filter(Boolean));
      for (const c of [...host.children]) {
        if (c._ghost) continue;
        if (!c.dataset.k) c.remove();
        else if (!keep.has(c.dataset.k)) {
          if (fx) fx.out(c);
          else c.remove();
        }
      }
    }
    const old = new Map();
    let ghosts = null; // 아직 물러나는 중인 잔상 (같은 것이 곧바로 다시 생기면 잔상은 치우고 그 밝기에서 이어 떠오릅니다 — 같은 글자가 두 겹으로 보이지 않게)
    for (const c of host.children) {
      if (!c.dataset.k || retained(c)) continue;
      if (!c._ghost) old.set(c.dataset.k, c);
      else (ghosts || (ghosts = new Map())).set(c.dataset.k, c);
    }
    const born = [];
    const relabeled = [];
    let cur = host.firstChild;
    for (const n of [...tpl.content.children]) {
      const k = n.dataset.k;
      const o = k ? old.get(k) : null;
      let node = n;
      if (o && o.tagName === n.tagName) {
        old.delete(k);
        const wasBare = o.classList.contains('is-bare');
        const inner = n.innerHTML;
        if (fx && !wasBare && n.classList.contains('is-bare') && o.classList.contains('tl-ev') && inViewX(o, fx.W)) ghostLabel(o, fx);
        syncAttrs(o, n);
        if (o._inner !== inner) {
          if (depth === 0 && DEEP(o)) {
            if (o._html == null) o._html = o._inner || ''; // 처음 속을 고쳐 쓸 때도 '처음 채움'이 아니게 — 새 키만 새로 생긴 것
            const d = fx ? fx.deep : null;
            const res = morph(o, inner, d, null, 1);
            if (res && d && res.born.length) d.born(res.born, o);
          } else o.innerHTML = inner;
          o._inner = inner;
        }
        if (wasBare && !o.classList.contains('is-bare')) relabeled.push(o);
        node = o;
      } else {
        n._inner = n.innerHTML;
        if (k && (first ? known && !known.has(k) : true)) born.push(n);
        const g = k && ghosts ? ghosts.get(k) : null;
        if (g) {
          n._from = parseFloat(getComputedStyle(g).opacity) || 0;
          if (cur === g) cur = cur.nextSibling;
          g.remove();
        }
      }
      while (cur && (cur._ghost || retained(cur))) cur = cur.nextSibling;
      if (node === cur) cur = cur.nextSibling;
      else host.insertBefore(node, cur);
    }
    while (cur) {
      const nx = cur.nextSibling;
      if (!cur._ghost && !retained(cur)) {
        if (fx && (depth || inViewX(cur, fx.W))) fx.out(cur);
        else cur.remove();
      }
      cur = nx;
    }
    return { born, relabeled };
  }

  /* ---------- 멀리 건너뛰기: "물러났다가 옮겨 가서 다시 다가가는" 길 ----------
     van Wijk & Nuij(2003)의 매끄러운 확대·이동 — 지도에서 먼 곳으로 갈 때처럼, 두 시점을 함께 볼 만큼 물러났다가 다가갑니다.
     u = 보기 가운데 해, w = 보기 폭(년). at(0..1) → [u, w], S = 길의 길이(시간을 정할 때 씀) */
  const RHO = Math.SQRT2;
  const zoomPath = (u0, w0, u1, w1) => {
    const d = u1 - u0;
    const ad = Math.abs(d);
    if (ad < 1e-9 * Math.max(w0, w1)) {
      const S = Math.log(w1 / w0) / RHO;
      return { S: Math.abs(S), at: t => [u0 + t * d, w0 * Math.exp(RHO * t * S)] };
    }
    const r2 = RHO * RHO;
    const b0 = (w1 * w1 - w0 * w0 + r2 * r2 * ad * ad) / (2 * w0 * r2 * ad);
    const b1 = (w1 * w1 - w0 * w0 - r2 * r2 * ad * ad) / (2 * w1 * r2 * ad);
    const r0 = -Math.asinh(b0);
    const r1 = -Math.asinh(b1);
    const S = (r1 - r0) / RHO;
    const ch0 = Math.cosh(r0);
    const sh0 = Math.sinh(r0);
    return {
      S,
      at: t => {
        const s = t * S;
        const u = (w0 / (r2 * ad)) * (ch0 * Math.tanh(RHO * s + r0) - sh0);
        return [u0 + u * d, (w0 * ch0) / Math.cosh(RHO * s + r0)];
      },
    };
  };
  const easeInOut = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const easeOut = t => 1 - Math.pow(1 - t, 3);

  /* ---------- 놓는 순간의 손 속도 ----------
     samples = 끄는 동안의 표본 [{ t(ms), x, y }], now = 놓은 시각 → [vx, vy] (px/ms).
     마지막 80ms의 표본에 곡선을 맞춰(최소제곱) 마지막 순간의 기울기를 읽습니다 — 표본 하나의 잡음에 휘둘리지 않고, 멈추려고 늦추던 손이면 늦춘 그 속도가 나옵니다(평균이 아니라).
     표본이 적으면(넷 미만 · 40ms 미만) 직선 기울기로. 곡선 값은 직선 기울기의 두 배까지만 믿고, 둘의 방향이 엇갈리면(끝에서 되돌아선 손) 0. 놓기 전에 손이 멈춰 있었으면(마지막 표본이 50ms보다 오래됨)도 0 */
  const releaseVelocity = (samples, now) => {
    const s = samples.filter(p => now - p.t <= 80);
    const n = s.length;
    if (n < 2 || now - s[n - 1].t > 50 || s[n - 1].t - s[0].t < 8) return [0, 0];
    const last = s[n - 1];
    let S1 = 0;
    let S2 = 0;
    let S3 = 0;
    let S4 = 0;
    for (const p of s) {
      const u = p.t - last.t;
      S1 += u;
      S2 += u * u;
      S3 += u * u * u;
      S4 += u * u * u * u;
    }
    const det = n * (S2 * S4 - S3 * S3) - S1 * (S1 * S4 - S3 * S2) + S2 * (S1 * S3 - S2 * S2);
    const curved = n >= 4 && last.t - s[0].t >= 40 && det > 1e-4 * n * S2 * S4; // 표본의 시각이 두어 덩이로 뭉쳐 있으면 곡선을 맞출 수 없습니다
    const fit = key => {
      let Y0 = 0;
      let Y1 = 0;
      let Y2 = 0;
      for (const p of s) {
        const u = p.t - last.t;
        const y = p[key] - last[key];
        Y0 += y;
        Y1 += u * y;
        Y2 += u * u * y;
      }
      const line = (n * Y1 - S1 * Y0) / (n * S2 - S1 * S1);
      if (!curved) return line;
      const b = (n * (Y1 * S4 - S3 * Y2) - Y0 * (S1 * S4 - S3 * S2) + S2 * (S1 * Y2 - Y1 * S2)) / det; // 2차 곡선의 마지막 순간 기울기
      return b * line <= 0 ? 0 : Math.sign(line) * Math.min(Math.abs(b), Math.abs(line) * 2);
    };
    return [fit('x'), fit('y')];
  };

  class Timeline {
    constructor(root, opts = {}) {
      this.root = root;
      this.opts = Object.assign({ onSelect: null, onViewChange: null, onMeasure: null, onFold: null, onFoldPeople: null, onFoldEra: null, onExpand: null, onAltCal: null, emptyText: '표시할 트랙이 없습니다.' }, opts);
      this.tracks = [];
      this.view = { start: -2500, end: HT.CURRENT_YEAR + 50 };
      this.extent = { min: -2500, max: HT.CURRENT_YEAR };
      this.selected = null;
      this.highlight = null;
      this.hiLayout = null; // 사건 배치에 쓰는 강조(setHighlight의 layout — 왕조 · 인물 창의 강조는 흐림 · 밝기에만)
      this.showAlt = opts.showAlt !== false;
      this.show = Object.assign({ leaders: true, cabinets: true, eras: true, capitals: true, ganji: true, succession: true, partOf: true, epochs: true }, opts.show || {});
      this.yearCycle = null; // 간지 설정 (형식 3 — setYearCycle · 모델의 yearCycle) — 없으면 육십갑자
      this.epochs = [];
      this.folded = new Set(opts.folded || []);
      this.foldedPeoples = new Set(opts.foldedPeoples || []); // "트랙id|민족id"
      this.foldedEras = new Set(opts.foldedEras || []); // 트랙id
      this.axisOpen = new Set(opts.axisOpen || []); // 맨 위 날짜 칸에서 펼친 묶음: 'eras'(연호) · 'capitals'(도읍) — 'epochFold'(EPOCH_FOLD)만 뜻이 반대: 있으면 나라별 시대 구분 줄을 접음
      this.openCapSec = new Set(opts.openCapSec || []); // 도읍 줄에서 배도 갈래를 펼친 트랙id
      this.metro = { uid: null, pinned: false, timer: 0, anchor: null }; // 도읍 노선도 카드
      this.altCal = opts.altCal !== undefined ? opts.altCal : 'dangi'; // 확대했을 때 날짜 칸 아래에 보이는 보조 달력 (''이면 끔)
      this._clusters = new Map(); // 겹친 사건 묶음 id → { uids, t0, t1, … }
      this.spot = null; // 칸 기간 조명: { uid(정권), cell('leader:3'), start, end } — 그 칸을 진하게, 띠 안 그 기간을 옅게 칠함
      this.spots = []; // 조명 목록 (setSpotlight가 하나든 여럿이든 여기에 — this.spot은 그 첫째. 띠마다 제 uid의 것만 칠합니다)
      this.house = null; // 가문 창이 열린 가문 id (setHouse) — 그 가문의 칸이 is-house로 진해짐 (여럿이면 첫째 — 모두는 houses)
      this.houses = null; // 진하게 할 가문 id들 Set (setHouse — 본가를 누르면 아래 파까지 · 성씨를 누르면 그 성의 가문 모두)
      this.houseSpans = null; // 가문 조명 구간 [{ uid(정권), start, end }] (setHouse의 spans — HT.houseSpans) — 칸 조명과 같은 칠 · 맨 위 날짜 칸 괄호
      this.houseDim = false; // 가문 조명이 걸린 띠 안에서 다른 가문의 지도자 칸을 .55로 (setHouse의 dim)
      this._tip = { key: null, timer: 0, el: null }; // 성씨 풍선(지도자 칸 · 왕조 칸에 올림 — D1 결정 6 A)
      /* 세로 닻: 줄이 접히고 펴져 위쪽 내용의 높이가 바뀌어도 보던 줄이 화면에서 제자리에 머물게 스크롤을 우리가 맞춥니다
         (브라우저의 자동 닻은 끔 — css overflow-anchor). 창이 열려 있으면 고른 항목의 줄이 닻(누른 그 자리 그대로 — 가려졌을 때만 최소한으로 옮김),
         아니면 화면 가운데의 줄이 닻 */
      this.anchorUid = null;
      this._anchorOff = null; // 닻 줄의 위쪽이 화면 위에서 떨어진 거리
      this._anchorSpring = null; // 닻을 옮기는 스프링 (가려진 줄을 데려올 때 · 멀리 갈 때의 가운데 맞춤) — 값 = _anchorOff
      this._anchorTo = null; // 아직 출발하지 않은 목표 — 첫 프레임에 스프링에 넘깁니다 (_anchorLoop)
      this._carry = null; // 멀리 가기에 실린 세로 이동 { from, to, set } — 가로 비행과 같은 진행값으로 나아갑니다 (_flyRow · _animateTo)
      this._arrive = null; // 도착했을 때 한 번 부를 것 (도착 표시)
      this._insetR = 0; // 상세 창이 연표의 오른쪽을 가린 폭 (setInset)
      this._selfScroll = 0; // 우리가 스크롤을 옮긴 시각 (사용자 스크롤과 구별)
      /* 움직이는 동안은 고요: 끌기·휠·미끄러짐·멀리 가기 중에는(_moving) 세부 효과가 제자리 120ms 투명도뿐입니다 (_fxMode) */
      this._moving = false; // 이번 그리기가 움직이는 중의 것인가 (_draw가 적고 .tl에 is-moving을 붙입니다)
      this._drawn = null; // 직전 그리기의 보기 { start, k } — 날짜 칸에서 사라지는 것의 자리(해)를 되읽습니다 (트랙은 tr._view — _linger)
      this._lingers = new Set(); // 움직이는 중에 옅어지며 물러나는 요소들 — 그리기마다 세계 좌표로 옮깁니다 (_lingerMove)
      this._fxN = 0; // 이번 그리기에서 건 효과 수 (FX_BUDGET)
      this._lod = new Map(); // 문턱의 기억: 확대 수준에 따라 바뀌는 것이 지금 어느 쪽인지 (_past · _stepAt)
      this._wheelG = null; // 휠 제스처 하나 { notch, t } — 장치(노치 휠 · 트랙패드)는 제스처의 첫 입력에서 한 번만 가립니다 (_bind)
      this._card = { id: null, pinned: false, timer: 0 }; // 묶음 카드
      this.expandedHosts = new Set(opts.expandedHosts || []); // 소속 정권을 펼쳐 둔 상위 정권 uid
      this.foldedHangs = new Set(opts.foldedHangs || []); // 매달린 속국 이름표를 접어 둔 상국 uid (toggleHangs — 이번 보기에서만)
      this.scopesOn = Object.assign({}, opts.scopesOn || {}); // 대범위 모아 보기: { uid: true | false } — 기록이 없으면 대범위의 default (scopeOn · toggleScope)
      this.board = null; // 켠 집합 보기 { id, name, color, members(uid 차례), start?, end?, temp? } — 맨 위 합성 트랙(BOARD_ID)으로 구성 나라의 줄을 통째로 모읍니다 (setBoard)
      this._boardOpen = new Set(); // 집합 보기를 켠 동안 보는 사람이 다시 편 트랙 (나머지는 접힘 — 접힘 기억 this.folded는 건드리지 않음)
      this._boardFolded = false; // 집합 보기 트랙 자신을 접었는가
      this.leaderMode = opts.leaderMode || 'auto'; // 지도자 표기: auto · temple · title · given · temple-title · all
      this.leaderOrdinal = !!opts.leaderOrdinal; // 대수 표시
      this.origOf = typeof opts.origOf === 'function' ? opts.origOf : null; // 왼쪽 줄 이름 칸에 함께 적을 원어: 정권 → { text } | null (10건 3 · 감독 결정 D2-2 — 뷰어가 표기 설정 · 글자 범위 표로 정해 넘김 · 없으면 지금 그대로)
      this.depth = 1; // 민족 계층의 최대 단계 수 (왼쪽 민족 칸 개수)
      this.lens = opts.lens || '';
      this.themeLens = null; // 렌즈(주제 보기 — 설계 7-8 결정 5 A): { id, name, color } — 지도자 칸 자리에 그 주제의 칸 (setThemeLens). '관점'(this.lens)과 다른 것
      this._echoFam = null; // 렌즈 칸의 같은 갈래 메아리: 올린 칸의 갈래('주제 id|갈래') — 모든 나라의 같은 갈래 칸이 진해짐
      this.density = 0; // -1 넉넉 / 0 자동 / 1 빽빽 / 2 조감
      this.birdShape = BIRD[opts.birdShape] ? opts.birdShape : 'a'; // 조감 모양: a 이름 + 점 · b 이름만 · c 8px 띠 · 선만
      this.birdAuto = !!opts.birdAuto; // 가로로 많이 축소하면(보기 폭 BIRD_AUTO년 이상) 저절로 조감 — 기본 끔
      this._bird = null; // 이번 배치의 조감 값 묶음(BIRD[모양]) — 조감이 아니면 null. 다시 지을 때(setData)만 바뀝니다 (_birdNow)
      this._autoOn = null; // 자동 조감의 문턱을 넘어 있는가 — 정착 때만 다시 잽니다(손에 잡힌 동안 모양이 바뀌지 않게 · _birdSettle)
      this._birdHold = false; // 자동 조감을 손으로 푼 동안(↕ · V · 밀도 목록): 보기가 나가는 문턱 아래로 좁아질 때까지 자동으로 다시 들어가지 않음
      this.marker = null;
      this.measureMode = false;
      this.measure = null;
      this.gutter = GUTTER;
      this.W = 600;
      this._raf = 0;
      this._anim = 0;
      this._enterTimer = 0;
      /* 서고 배치 3단(메이커 미리보기만 — G_SEOGO): 두 장 꼬리표 줄 쌓기 · 문화권 머리 단 · 서고 왼쪽 칸 · 그릇 세 상태 · 승계선은 꼬리 마름모 → 구멍. 내보내기는 켜지 않음 */
      this.seogo = !!opts.seogo;
      this.spheres = []; // 문화권 목록(setData의 spheres 가운데 트랙이 쓰는 것 — 차례대로) · 트랙의 sphere가 가리킴
      this.foldedSpheres = Array.isArray(opts.foldedSpheres) ? new Set(opts.foldedSpheres) : null;
      this.shelvedScopes = new Set(Array.isArray(opts.shelvedScopes) ? opts.shelvedScopes : []); // 선반 상태의 그릇 uid(서고 과제 9 — 기억은 opts.onShelf) // 접힌 문화권 id — null이면 기억이 없어 처음 접힘 규칙(기본 문화권 하나만 폄 — _sphereSetup)
      this._gs = null; // 서고 값 묶음(G + G_SEOGO)의 기억 (_G)
      this.root.classList.toggle('is-seogo', this.seogo);
      this._build();
      this._bind();
      this._bindMetro();
    }

    /* ---------- 공개 API ---------- */
    setData({ tracks, periods, events, epochs, categories, scopes }, { enter = true } = {}) {
      if (this.tracks && this.tracks.some(tr => tr._panScene)) {
        this._sceneDisabled = true;
        try { this._draw(); } finally { this._sceneDisabled = false; }
      }
      this._finishEventPan(); // 움직이던 사건 층을 실제 좌표로 풀어, 밀도 변경·접기의 이전 화면도 같은 구조로 기억합니다.
      this._stopCoast(); // 미끄러지던 중에 다시 지으면 관성은 거기까지 (붙잡을 줄은 멈춘 화면에서 잡습니다)
      /* 밀도(와 조감 모양)가 정하는 자리 값 — 바뀌었으면(조감 ↔ 다른 밀도 · 넉넉 ↔ 빽빽 …) 줄의 높이 · 자리가 한 시계로 흐르고 줄 안의 것은 옅어지고 떠오릅니다 (_squash) */
      const bird = this._birdNow();
      const geoSig = bird ? `bird-${bird.shape}` : `d${this.density}`;
      const squash = this._geoSig != null && geoSig !== this._geoSig && !!this._entered;
      const birdWay = this._geoSig != null && !!bird !== !!this._bird ? (bird ? 'in' : 'out') : null; // 조감에 들거나 나옴 — 나올 때는 들기 전에 보던 줄로 (_birdBack)
      const before = this._snapshot(squash, birdWay); // 다시 짓기 전의 화면: 트랙의 지금 높이 · 빈 줄 접힘의 기억 · 붙잡고 있을 줄 (_foldAhead · _applyFlip) — 밀도가 바뀌면 옛 줄 · 이름 칸의 크기와 요소도 (_squash)
      const birdChanged = !!bird !== !!this._bird;
      this._bird = bird;
      this._geoSig = geoSig;
      this.root.classList.toggle('is-bird', !!bird);
      for (const k of Object.keys(BIRD)) this.root.classList.toggle(`is-bird-${k}`, !!bird && bird.shape === k);
      this._data = { tracks, periods, events, epochs, categories, scopes }; // 다시 배치(relayout · toggleScope)는 이것을 그대로 다시 넣습니다 — 대범위도 함께 실어야 켜는 순간 사라지지 않음
      /* 인물: 부르는 쪽(뷰어)이 보이는 트랙 · 중요도 필터로 걸러 준 목록. relayout()이 _data로 다시 짓기 때문에 _data에도 싣습니다(빠뜨리면 첫 접기에서 인물이 통째로 사라짐) */
      this._data.figures = (arguments[0] && arguments[0].figures) || [];
      this._data.spheres = (arguments[0] && arguments[0].spheres) || []; // 문화권 목록(서고 3단의 머리 단 — _sphereSetup) · defaultSphere = 처음 펴 둘 문화권 id(고치는 DLC의 첫 트랙의 것)
      this._data.defaultSphere = (arguments[0] && arguments[0].defaultSphere) || null;
      this._data.unions = (arguments[0] && arguments[0].unions) || []; // 동군연합 짝(HT.unionPairs — 뷰어가 모델에서 셈해 줌 · 건의 8의 6-다)
      this._data.houseMap = (arguments[0] && arguments[0].houseMap) || null;
      this._data.f4 = (arguments[0] && arguments[0].f4) || null; // 서고 미리보기의 형식 4 모델(5단계 과제 9 · 정한 것 #3 — HT.f4Preview) · 서고가 아니면 쓰지 않음 // 가문 표(모델의 houseMap — 성씨 풍선의 성씨 · 본관 · 본가 길). 없으면 _houseMapNow가 뷰어의 모델에서
      this._setScopes(scopes); // 대범위 목록 · 본국별 할거 구간 (_layoutTrack · _drawTrack)
      /* 사건 분류: 띠 안 분류별 글줄의 순서·이름·색 (목록 순서 = 줄 순서, 없으면 기본 분류) */
      this._cats = new Map();
      (categories && categories.length ? categories : HT.DEFAULT_CATEGORIES).forEach((c, i) => this._cats.set(c.id, { name: c.name, color: c.color, i }));
      for (const e of events) {
        const id = e.category || 'etc';
        if (!this._cats.has(id)) this._cats.set(id, { name: id === 'etc' ? '기타' : id, color: e.color || '#a4b1b7', i: 1000 + this._cats.size });
      }
      this.epochs = epochs || [];
      const map = new Map();
      this.tracks = tracks.map(t => {
        const tr = Object.assign({}, t, { periods: [], events: [] });
        map.set(t.id, tr);
        return tr;
      });
      /* 같은 도시를 도읍으로 쓴 정권들 (도읍 칸에 올리면 함께 진하게 · 노선도의 환승역) */
      this._cityUses = new Map();
      for (const p of periods) {
        for (const c of p.capitals || []) {
          if (!this._cityUses.has(c.city)) this._cityUses.set(c.city, []);
          this._cityUses.get(c.city).push({ p, c });
        }
      }
      /* 왕조는 제 줄을 갖지 않고 다스린 정권 띠의 왕조 칸에만 그립니다 (다른 트랙의 정권을 다스려도 그 띠에) */
      this._dynUids = new Set();
      periods.forEach(p => {
        if (p.polityKind === 'dynasty') return this._dynUids.add(p.uid);
        if (map.has(p.track)) map.get(p.track).periods.push(p);
      });
      this._proxies = depProxies(periods); // 상국 띠마다 품을 속국 이름표 (트랙이 달라도 — _layoutTrack · _drawTrack · toSVG)
      events.forEach(e => {
        const places = e.placements && e.placements.length ? e.placements : [{ track: e.track, polityUid: e.polityUid }];
        places.forEach((place, i) => {
          const tr = map.get(place.track);
          if (tr) tr.events.push(Object.assign({}, e, { _place: place, _sec: i > 0, _pi: i }));
        });
      });
      /* 인물의 활동 막대: 섬긴 정권마다 하나, 그 정권의 트랙에 (두 트랙의 나라를 섬긴 사람은 두 트랙에 하나씩). 줄 · 단은 _layoutTrack이 정합니다 */
      for (const tr of this.tracks) tr.figures = [];
      for (const f of this._data.figures) {
        (f.services || []).forEach((s, i) => {
          const tr = s.shown && s.polity ? map.get(s.polity.track) : null;
          if (tr) tr.figures.push({ f, s, i, row: null, lvl: -1, band: null }); // i = 섬긴 기록의 순번 (같은 정권을 두 번 섬긴 사람의 막대를 가름)
        });
      }
      this._boardPlan(); // 집합 보기를 켰으면: 구성 나라가 놓인 줄을 통째로(그 줄의 나라 · 사건 · 인물과 함께) 맨 위 합성 트랙으로 — 끄면 아무것도 하지 않음

      this._sphereSetup(this._data.spheres, this._data.defaultSphere); // 서고: 문화권 머리 단 · 접힌 문화권의 트랙은 숨김 (_layoutTrack 전에 — 트랙의 접힘 · 높이를 정함)
      let min = Infinity;
      let max = -Infinity;
      this.depth = 1;
      for (const tr of this.tracks) {
        this._layoutTrack(tr);
        this.depth = Math.max(this.depth, tr.depth || 1);
        for (const x of tr.periods.concat(tr.events)) {
          min = Math.min(min, x.spanMin ?? x.start);
          max = Math.max(max, x.spanMax ?? x.endY);
        }
      }
      // 민족 단계가 깊어지면 왼쪽 칸이 그만큼 넓어집니다
      this.gutter = GUTTER + (this.depth - 1) * COL.people;
      if (isFinite(min)) this.extent = { min, max: Math.max(max, min + 10) };
      this.emptyEl.hidden = this.tracks.length > 0;
      this.emptyEl.textContent = this.opts.emptyText;
      this._buildAxis();
      this._foldAhead(before); // 빈 줄 접힘을 먼저 계산해 두어, 새 DOM이 처음부터 접힌 크기로 태어나게
      this._buildTracks();
      this.hideCard(true);
      this.hideTip(true);
      const clock = before.squash ? this._squashClock() : null; // 밀도가 바뀐 한 번에만: 트랙 높이까지 모든 움직임을 한 시각에 못 박음 (_squashRun)
      this._applyFlip(before, clock);
      this._squash(before, clock); // 밀도가 바뀐 한 번에만: 줄 높이 · 자리 · 이름 칸이 옛 크기에서 흐르고 옛 줄 안은 잔상으로 옅어짐 — 높이 전환과 같은 호출 · 같은 시계
      this._gather(before); // 대범위를 켜고 끈 한 번에만: 줄이 옛 자리에서 새 자리로 모여듦 — 높이 전환과 같은 호출 · 같은 시계 (7-3)
      if (enter && !this._entered && this.tracks.length) this._enter(); // 등장 연출은 맨 처음 자료를 받았을 때 한 번만 (필터·저장·미리보기 갱신·접기·펼치기에서는 하지 않음)
      this.setView(this.view.start, this.view.end);
      // 열려 있던 노선도는 새 자료로 다시 (정권이 사라졌으면 닫기)
      if (this.metro.uid && this.metroEl && !this.metroEl.hidden) {
        if (!this.showMetro(this.metro.uid, null, undefined, true)) this.hideMetro();
      }
      if (birdChanged && this.opts.onBird) this.opts.onBird(!!bird); // 조감에 들어가거나 나옴 (↕ 단추의 눌림 · 자동 조감)
      this._rebuiltAt = performance.now(); // 다시 지은 끝 — 그 사이 브라우저가 깎은 스크롤(새 DOM이 짧아짐)은 손으로 옮긴 것이 아님 (스크롤 듣개의 _birdBack)
      if (this.opts.onLayout) this.opts.onLayout(); // 띠가 바뀌었을 수 있음(접기 · 펼치기 · 소속 펼침) — 뷰어가 조명의 사건 · 같은 시기 타국을 다시 셈 (echoBands)
      this.root.dispatchEvent(new CustomEvent('tl-data')); // 자료를 다시 넣음 — 스스로 붙는 부품(js/lens-ui.js — 켠 렌즈의 주제가 사라지거나 숨었는지)이 듣습니다
    }

    /** 데이터는 그대로 두고 배치만 다시 (토글·접기 후) */
    relayout() {
      if (!this._data) return (this._pressHold = null);
      this._beginJump();
      this.setData(this._data, { enter: false }); // 지금 높이에서 새 높이로 한 번에 흐릅니다 (_snapshot → _applyFlip)
      this._settleSoon(0); // 밀려난 것은 높이가 흐르기 시작하는 지금 함께 알립니다 — 다 흐른 뒤의 배치는 모델로 알 수 있으므로 기다리지 않습니다 (_settle · _finalGeom)
    }

    /** 다시 짓기 직전의 화면을 기억합니다 — 트랙마다 지금 보이는 높이(흐르는 도중이면 그 순간의 높이) · 접힘 상태 · 빈 줄 접힘의 기억,
        그리고 다시 짓는 동안 제자리에 붙잡을 줄(hold): 방금 누른 단추의 줄, 없으면 화면 가운데 줄. 새 DOM이 아니라 "누르기 직전 화면"에서 잡아야 보던 자리가 지켜집니다 */
    _snapshot(squash = false, birdWay = null) {
      const b = this.bodyEl;
      const snap = { tracks: new Map(), hold: null, squash: squash && !reduceMotion() ? this._squashFirst() : null, scroll: b.scrollTop, bw: b.clientWidth }; // scroll: 다시 짓기 전의 스크롤 (새 DOM이 짧아지면 브라우저가 곧바로 깎아 버림 — _squashHold)
      for (const tr of this.tracks) {
        const live = !!(tr.el && tr.el.isConnected);
        snap.tracks.set(tr.id, {
          h: live ? tr.el.getBoundingClientRect().height : null,
          folded: !!tr.folded,
          rows: tr.rows,
          hidden: !tr.folded && tr._rowMemo ? tr.hiddenRows : null,
          opened: live && tr.el._openedAt != null ? tr.el._openedAt : null, // 펼친 내용이 떠오르기 시작한 시각 (도중에 다시 지으면 이어서 떠오르게)
          memo: { lab: tr._lab, clu: tr._clu, wide: tr._wide, bnm: tr._bnm }, // 이름 자리·묶음의 기억 (문턱은 두 개 — 다시 지어도 누르지 않은 트랙의 이름과 묶음이 그대로이게)
          el: live ? tr.el : null, // 필터로 꺼지는 트랙은 이 요소가 옅어지며 접힙니다 (_applyFlip)
          lanes: live && !tr.folded && tr.laneEls ? tr.laneEls : null, // 앞선 화면의 줄 — 다시 지은 뒤 첫 그리기에서 새로 생긴 것·없어진 것을 가려냅니다 (_drawTrack)
        });
      }
      const press = this._pressHold;
      this._pressHold = null;
      if (this.tracks.length && !this._anchorLane()) {
        let a = null;
        const tr = press ? this.tracks.find(t => t.id === press.trackId) : null;
        if (tr && tr.el && tr.el.isConnected) {
          const row = !tr.folded && tr.laneEls && tr.laneEls[press.row] ? press.row : -1;
          const abs = tr.el.offsetTop + (row >= 0 ? tr.laneEls[row].offsetTop : 0);
          a = { tr, row, off: abs - b.scrollTop };
          /* 위쪽이 화면 밖으로 나간 긴 트랙을 접을 때는 그 아래 트랙을 붙잡습니다 — 접힌 띠가 보이던 아래 끝에 남고, 화면의 다른 것은 움직이지 않습니다 */
          const next = this.tracks[this.tracks.indexOf(tr) + 1];
          const nextOff = next && next.el && next.el.isConnected ? next.el.offsetTop - b.scrollTop : -1;
          if (row < 0 && a.off < 0 && !tr.folded && this._foldedNow(tr.id) && nextOff >= 0 && nextOff <= b.clientHeight) a = { tr: next, row: -1, off: nextOff };
        }
        if (!a && birdWay === 'out') a = this._birdReturn(); // 조감에서 나옴: 조감 가운데 줄이 아니라 들기 전에 보던 줄을 그때의 화면 자리에 (켰다 끈 한 번의 왕복에 보던 곳을 잃지 않게)
        if (!a) a = this._autoAnchor();
        if (a && a.tr.el && a.tr.el.isConnected) snap.hold = { id: a.tr.id, row: a.row, off: a.off, top: a.back ? a.back.top : a.tr.el.offsetTop - b.scrollTop, pressed: !!(tr && a.tr === tr), gkey: (tr && a.tr === tr && press.gkey) || null, uid: (tr && a.tr === tr && press.uid) || null };
      }
      /* 조감에 들 때 붙잡은 줄(보던 줄)과 그 화면 자리를 기억합니다 — 나올 때(밀도 · ↕ · V · 자동 조감) 그 줄로. 그 사이 손으로 위아래로 옮기거나(스크롤 듣개) 항목을 고르면(setSelected) 잊음 */
      if (birdWay) this._birdBack = birdWay === 'in' && snap.hold && !snap.hold.pressed ? { id: snap.hold.id, row: snap.hold.row, off: snap.hold.off, top: snap.hold.top } : null;
      return snap;
    }

    /** 조감에 들기 전에 보던 줄 { tr, row, off, back } — 그 트랙이 없어졌거나 접혔거나 그 줄이 없으면 null (화면 가운데 줄로) */
    _birdReturn() {
      const k = this._birdBack;
      const tr = k ? this.tracks.find(t => t.id === k.id) : null;
      if (!tr || !tr.el || !tr.el.isConnected) return null;
      if (k.row < 0) return { tr, row: -1, off: k.top, back: k };
      if (tr.folded || !tr.laneEls || !tr.laneEls[k.row]) return null;
      return { tr, row: k.row, off: k.off, back: k };
    }

    /** 빈 줄 접힘을 DOM을 짓기 전에 모델만으로 계산합니다 — 새 줄이 처음부터 접힌 크기로 태어나므로, 다시 지을 때마다 모든 트랙이 최대 높이로 부풀었다 꺼지는 일이 없습니다.
        접힘의 기억(히스테리시스)은 같은 트랙끼리(줄 수가 같을 때) 이어받아, 누르지 않은 트랙의 높이는 1px도 바뀌지 않습니다 */
    _foldAhead(before) {
      const view = this._clampView(this.view.start, this.view.end); // 곧 setView가 맞출 범위 (자료가 바뀌면 범위 끝도 달라짐)
      const W = Math.max(60, (before.bw != null ? before.bw : this.bodyEl.clientWidth) - this.gutter); // 폭은 다시 짓기 전에 잰 것 — 여기서 재면 조감 표시(루트 클래스)를 막 바꾼 옛 DOM 전체를 헛되이 다시 계산함(15ms 남짓)
      const X = y => ((y - view.start) * W) / (view.end - view.start);
      const moving = this._inMotion();
      const back = this._boardRestore; // 집합 보기를 끈 한 번: 판을 켜기 전 트랙마다의 기억(빈 줄 접힘 · 이름 자리)으로 — 켜기 전과 1px도 다르지 않게 (setBoard)
      this._boardRestore = null;
      for (const tr of this.tracks) {
        const old = (back && back.get(tr.id)) || before.tracks.get(tr.id);
        if (old && old.memo) [tr._lab, tr._clu, tr._wide, tr._bnm] = [old.memo.lab, old.memo.clu, old.memo.wide, old.memo.bnm];
        if (tr.folded) continue;
        const carried = !!(old && old.hidden && old.rows === tr.rows);
        if (carried) {
          tr.hiddenRows = new Set(old.hidden);
          tr._rowMemo = true;
        }
        tr._hiddenSig = this._foldRows(tr, X, W, moving); // _buildTracks가 이 크기 그대로 짓습니다
        if (!carried) tr._rowMemo = false; // 이어받은 기억이 없으면, 기억은 실제로 그린 화면부터 (맨 처음에는 곧이어 저장된 보기 범위로 바뀌므로)
      }
    }

    /** 누른 단추(트랙 이름 · 민족 칸 · 소속 정권 단추)가 놓인 줄 → { trackId, row } (row −1 = 트랙 위쪽).
        다시 배치하는 동안 그 줄을 붙잡아, 누른 것이 손 밑에서 달아나지 않습니다 */
    _holdOf(el) {
      const trEl = el && el.closest ? el.closest('.tl-track') : null;
      const tr = trEl ? this.tracks.find(t => t.id === trEl.dataset.track) : null;
      if (!tr) return null;
      if (el.dataset.fold) return { trackId: tr.id, row: -1 };
      const gkey = el.dataset.foldPeople || null; // 민족 칸: 그 묶음에서 펴져 있는 첫 줄 (다시 지은 뒤에도 같은 묶음의 첫 줄을 찾습니다)
      const rowEl = el.closest('[data-row]');
      return { trackId: tr.id, row: gkey ? this._groupRow(tr, gkey) : rowEl ? Number(rowEl.dataset.row) : -1, gkey };
    }

    /** 민족 묶음(key = "트랙id|민족id")에서 지금 펴져 있는 첫 줄 (없으면 −1) */
    _groupRow(tr, gkey) {
      const gp = (tr.groups || []).find(g => peopleKey(tr, g) === gkey);
      if (!gp || tr.folded) return -1;
      for (let r = gp.first; r < gp.first + gp.count; r++) if (!tr.hiddenRows.has(r)) return r;
      return -1;
    }

    /** 다시 지은 뒤에 붙잡을 줄을 새 DOM에서 다시 찾습니다 (줄 구성이 달라졌거나 그 트랙이 접혔으면 트랙 위쪽을 붙잡음) */
    _resolveHold(h, before) {
      const tr = h ? this.tracks.find(t => t.id === h.id) : null;
      if (!tr || !tr.el) return null;
      const old = before.tracks.get(h.id);
      const row = h.gkey ? this._groupRow(tr, h.gkey) : h.uid ? this._uidRow(tr, h.uid) : h.row; // uid: 그 정권의 줄을 다시 찾음 (대범위를 켜고 끌 때의 본국 줄 — 위쪽 줄이 빠져 번호가 바뀌어도)
      const rowOK = h.row >= 0 && row >= 0 && !tr.folded && tr.laneEls && tr.laneEls[row] && (h.pressed || (old && old.rows === tr.rows));
      return { tr, row: rowOK ? row : -1, off: rowOK ? h.off : h.top };
    }

    setSelected(uid) {
      this.selected = uid || null;
      if (uid) this._birdBack = null; // 조감에서 무엇을 골랐으면 나올 때 그 자리에서 (들기 전에 보던 줄로 돌아가지 않음 — _snapshot)
      this._applyStates();
      this.render();
    }

    /** 강조(검색 결과 · 창이 고른 것) — 강조 밖은 흐립니다. opts(창의 조명 강조일 때만 — 검색은 주지 않음):
        spot 조명 강조임(묶음 알약에 그 시기의 사건 표시) · echo 같은 시기 타국의 사건(HT.echoEvents의 echoKeys 'uid:자리' — 흐리지 않고 제 사건과 같은 밝기, 이름 우선순위 · 부모 펼침에는 넣지 않음) ·
        lit 흐린 띠 안의 조명 구간을 흐리지 않음(설정 '같은 시기를 타국에도' — _drawTrack의 has-lit) ·
        layout false면 이 강조를 사건 배치(이름 우선순위 · 하위 사건을 품은 부모의 저절로 펼침 — hiLayout)에 쓰지 않음(흐림 · 밝기만):
        '같은 시기를 타국에도'를 켤 때만 강조를 거는 왕조 · 인물 창 — 스위치 하나로 이름표가 바뀌거나 부모 사건이 펼쳐졌다 접히며 줄이 다시 놓이지 않게 */
    setHighlight(set, opts = {}) {
      this.highlight = set;
      this.hiLayout = set && opts.layout !== false ? set : null;
      this.echo = set && opts.echo && opts.echo.size ? opts.echo : null;
      this.litOn = !!(set && opts.lit);
      this.spotHi = !!(set && opts.spot);
      this._applyStates();
      this.render();
    }

    setShowAlt(on) {
      this.showAlt = !!on;
      this.render();
    }

    /** 간지 설정 (형식 3 — 설계 6 결정 8 B · 모델의 yearCycle): null = 육십갑자 · { off: true } = DLC가 간지 줄을 기본으로 끔 · { names, start, label } = 다른 순환.
        ganji(참 · 거짓)를 주면 간지 줄의 표시도 함께 정합니다(보는 사람의 필터 '간지' — HT.yearCycleUi가 맞춘 값). 다시 짓지 않습니다 — 부르는 쪽의 setData가 날짜 칸을 다시 지음 */
    setYearCycle(cycle, ganji) {
      this.yearCycle = cycle && typeof cycle === 'object' ? cycle : null;
      if (typeof ganji === 'boolean') this.show.ganji = ganji;
    }

    /** 날짜 칸에 그릴 순환 — DLC가 이름 목록을 준 순환만 (없거나 끈 순환이면 null — 육십갑자) */
    _cycle() {
      const c = this.yearCycle;
      return c && Array.isArray(c.names) && c.names.length >= 2 ? c : null;
    }

    /** 지도자·내각 칸, 상단 연호·간지 줄, 승계선 켜고 끄기 */
    setShow(patch) {
      Object.assign(this.show, patch);
      if (Object.keys(patch).every(k => k === 'spotEcho' || k === 'houses')) return this.render(); // 조명 메아리 · 가문 줄은 칠일 뿐 — 줄 배치는 그대로
      this.relayout();
    }

    setLens(lens) {
      this.lens = lens || '';
      this.render();
    }

    /** 렌즈(설계 docs/설계-10건/7-8-단체와-렌즈.md 결정 5 A — 감독 선택): 주제 { id, name, color } 하나(null이면 끔).
        켜면 나라 띠의 지도자 칸 자리에 그 주제의 칸을 바꿔 끼웁니다(HT.lensCellsOf — 줄 높이 그대로). 렌즈를 켠 동안의 줄 배치는 렌즈 종류와 상관없이 하나라
        (지도자 칸이 없는 트랙도 렌즈 자료가 있으면 그 자리가 생김 — _layoutTrack) 켜고 끌 때 그 자리가 바뀌는 트랙이 있을 때만 다시 배치하고, 렌즈끼리 바꿀 때는 다시 그리기만.
        렌즈를 고르는 차림표 · 단축키는 js/lens-ui.js(연표 화면) */
    setThemeLens(theme) {
      const next = theme && theme.id ? { id: String(theme.id), name: String(theme.name || theme.id), color: theme.color || '#a4b1b7' } : null;
      const was = this.themeLens;
      if ((was && was.id) === (next && next.id) && (was && was.color) === (next && next.color) && (was && was.name) === (next && next.name)) return;
      this.themeLens = next;
      this._echoFam = null;
      this.root.classList.remove('lens-echo');
      this.root.classList.toggle('has-themelens', !!next);
      if (next) this.root.style.setProperty('--lens-c', next.color);
      else this.root.style.removeProperty('--lens-c');
      const slot = tr => this.show.leaders && tr.periods.some(p => p.leaders && p.leaders.length);
      if (!!was !== !!next && (this.tracks || []).some(tr => !slot(tr) && tr.periods.some(p => HT.lensAny(p)))) return this.relayout();
      this.render();
    }

    /** 렌즈 칸의 같은 갈래 메아리(설계 결정 5 — 같은 갈래에 올리면 모든 나라의 같은 갈래 칸이 진해지고 나머지 렌즈 칸은 옅어짐). fam = '주제 id|갈래' 또는 null */
    _lensEcho(fam) {
      fam = fam || null;
      if (fam === this._echoFam) return;
      this._echoFam = fam;
      this.root.classList.toggle('lens-echo', !!fam);
      this.root.querySelectorAll('.tl-cell.k-lens.is-fam').forEach(el => el.classList.remove('is-fam'));
      if (fam) this.root.querySelectorAll(`.tl-cell.k-lens[data-fam="${CSS.escape(fam)}"]`).forEach(el => el.classList.add('is-fam'));
    }

    /** 밀도: -1 넉넉 · 0 자동 · 1 빽빽 · 2 조감. 자동 조감이 켜진 채 조감을 손으로 떠나면(다른 밀도를 고름) 문턱 아래로 좁아질 때까지 자동 조감을 쉽니다 — 고른 밀도가 곧바로 되돌려지지 않게.
        다시 짓기는 부르는 쪽이 (뷰어의 applyFilters — 밀도가 바뀐 줄은 한 시계로 흐름: _squash) */
    setDensity(bias) {
      const d = [-1, 0, 1, 2].includes(Number(bias)) ? Number(bias) : 0;
      if (d === 2) this._birdHold = false;
      else if (this._bird && this.birdAuto && this._autoOn) this._birdHold = true;
      this.density = d;
    }

    /** 조감 모양(a · b · c)과 자동 조감(켜고 끔) — 다시 짓기는 부르는 쪽이 */
    setBird({ shape, auto } = {}) {
      if (shape != null) this.birdShape = BIRD[shape] ? shape : 'a';
      if (auto != null) {
        this.birdAuto = !!auto;
        this._birdHold = false;
        if (this.birdAuto) this._autoOn = this._past('bird', this.span() / BIRD_AUTO, 1); // 켜는 순간은 지금 보기로 (문턱 판정은 정착 때만 새로 하므로 — 정착 없이 옮긴 보기에서 묵은 판정이 남지 않게)
      }
    }

    /** 지금 조감으로 그리고 있는가 (밀도 조감이거나 자동 조감) */
    isBird() {
      return !!this._bird;
    }

    /** 자동 조감을 손으로 풂(↕ · V): 문턱 아래로 좁아질 때까지 쉬고, 고른 밀도로 흘러 돌아갑니다 */
    leaveAutoBird() {
      if (!this._bird || this.density === 2) return;
      this._birdHold = true;
      this._rebuildBird();
    }

    /** 조감 여부만 바뀐 다시 짓기 — 목록에서 밀도를 고른 것(뷰어의 applyFilters)과 같게 곧바로 setData: 줄이 한 시계로 흐르고(_squash), 가장자리 안내(밀려난 것 알림)는 띄우지 않음 */
    _rebuildBird() {
      if (!this._data) return;
      this._jump = null;
      this.setData(this._data, { enter: false });
    }

    /** 이번에 지을 조감 값 묶음 (조감이 아니면 null): 밀도 조감, 또는 자동 조감이 켜져 있고 문턱을 넘었으며 손으로 풀지 않았을 때 */
    _birdNow() {
      if (this._autoOn == null) this._autoOn = this._past('bird', this.span() / BIRD_AUTO, 1); // 맨 처음은 지금 보기로 (그 뒤로는 정착 때만)
      const on = this.density === 2 || (this.birdAuto && !this._birdHold && this._autoOn);
      return on ? BIRD[this.birdShape] || BIRD.a : null;
    }

    /** 자동 조감의 정착(_settle에서 — 움직임이 멎은 뒤 한 번): 문턱은 두 개(들어가기 BIRD_AUTO년 · 나가기 8% 아래). 조감 여부가 바뀌면 다시 배치(한 시계로 흐름)하고 true */
    _birdSettle() {
      const past = this._past('bird', this.span() / BIRD_AUTO, 1);
      if (!past) this._birdHold = false;
      this._autoOn = past;
      if (!this.birdAuto || this.density === 2 || !!this._birdNow() === !!this._bird) return false;
      this._rebuildBird();
      return true;
    }

    /** 지금 쓰는 자리 값 묶음(G) — 조감이면 줄 사이 · 여백 · 접힌 줄 · 막대 · 문 · 모서리를 조감 값으로 */
    _G() {
      const b = this._bird;
      if (!b) {
        if (!this.seogo) return G;
        if (!this._gs) this._gs = Object.assign({}, G, G_SEOGO); // 서고 배치 3단: 조감이 아닐 때의 값 묶음 (조감은 서고에서도 예전 조감 그대로)
        return this._gs;
      }
      if (!this._gb || this._gb.shape !== b.shape) this._gb = Object.assign({}, G, G_BIRD, { shape: b.shape, door: b.door, radius: b.radius, thin: b.thin });
      return this._gb;
    }

    /** 서고 배치(메이커)이고 조감이 아닌가 — 두 장 꼬리표 줄 쌓기 · 구멍 · 꼬리 마름모를 쓰는 그리기 */
    _seogoOn() {
      return this.seogo && !this._bird;
    }

    /** 줄 r 위의 탭 자리(책갈피 탭 18 — 서고에서는 이름 색줄이 띠 안에 있어 받침 카드 · 상국 탭 · 열쇠표 · 매다는 실의 자리) + 서고의 올림 몫(tr.rowLift — 솟는 줄 15 · 그릇의 줄 10).
        접힌 민족 줄 · 트랙 공통 줄은 0. _layoutTrack · _foldRows · _scopeHead · _scopeBox · _linkPlan이 같은 값을 씁니다 */
    _tabOf(tr, r) {
      if (tr.foldedRows.has(r) || r === tr.commonRow) return 0;
      return this._G().tab + ((tr.rowLift && tr.rowLift[r]) || 0);
    }

    /** 서고 배치의 띠마다 몸통(새 앱 bands.dart TagLook.compactOf · eventLift): 줄의 칸 뭉치(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관)에서
        이 띠가 갖지 않은 층을 빼고 맞붙인 자리(gb — 줄 자리 geo와 같은 꼴)와, 흰 사건 칸 · 몸통 아랫변을 그만큼 올리는 몫(lift — '넉넉하게'는 0).
        가졌는가는 화면이 아니라 자료로(내보내기 tracks.mjs의 띠 look 비트 21~29와 같은 뜻) — 칸이 없는 띠는 색줄 바로 밑이 사건 칸. 서고가 아니면 줄의 자리 그대로 */
    _bandGeo(tr, p) {
      const gr = (tr.geos && tr.geos[p._row]) || tr.geo;
      if (!this._seogoOn() || gr.bird) return { gb: gr, lift: 0 };
      const g = tr.geo;
      const S = gr.powerH || gr.realH ? HT.groupStrip(p) : null;
      const organHost = q => (tr.overlays || []).some(o => o.scale !== 'zone' && (o.hosts || []).some(h => h.host && h.host.uid === q.uid));
      const floors = [
        ['dynastyTop', gr.dynastyH, () => this._dynOf(p).length > 0],
        ['phaseTop', gr.phaseH, () => (p.phaseSchemes || []).length > 0],
        ['rankTop', gr.rankH, () => (p.rankSpans || []).length > 0],
        ['powerTop', gr.powerH, () => S.power.length > 0],
        ['realTop', gr.realH, () => S.real.length > 0],
        ['leaderTop', gr.leaderH, () => (p.leaders || []).length > 0 || !!(this.themeLens && HT.lensAny(p))],
        ['cabinetTop', gr.cabinetH, () => (p.cabinets || []).length > 0],
        ['depTop', gr.depH, () => !!(p._dep && p._dep.inLanes)],
        ['organTop', g.organH, () => organHost(p)],
      ];
      const gb = Object.assign({}, gr);
      gb.floorTops = []; // 제 칸 층의 윗변들(층 사이 금 — 새 앱 RowGeo.floorTops를 compactOf로 옮긴 자리 · 시기는 단마다)
      let up = 0;
      for (const [k, h, own] of floors) {
        if (!h || gr[k] == null) continue;
        gb[k] = gr[k] - up;
        if (!own()) up += h;
        else for (let y = gb[k]; y < gb[k] + h - 0.5; y += k === 'phaseTop' ? G_SEOGO.phase : k === 'depTop' ? G_SEOGO.dep : h) gb.floorTops.push(y);
      }
      gb.floorEnd = gr.textTop - up; // 제 칸 뭉치의 아랫변 (칸 칠 --fe · 사건 칸의 윗변)
      const lift = this.density < 0 ? 0 : up;
      gb.textTop = gr.textTop - lift;
      return { gb, lift };
    }

    toggleFold(trackId, force) {
      if (this._boardTr) return this._boardFold(trackId, force); // 집합 보기를 켠 동안은 그 판의 접힘만 (접힘 기억은 판을 끄면 그대로 돌아옴)
      const on = force == null ? !this.folded.has(trackId) : !!force;
      if (on) this.folded.add(trackId);
      else this.folded.delete(trackId);
      if (this.opts.onFold) this.opts.onFold([...this.folded]);
      if (!this._pressHold) this._pressHold = { trackId, row: -1 }; // 접고 펴는 트랙의 위쪽이 제자리 — 아래쪽이 밀리고 당겨집니다
      this.relayout();
    }

    /** 모든 트랙 접기/펴기 */
    foldAll(on) {
      if (this._boardTr) {
        this._boardOpen = new Set(on ? [] : this.tracks.map(t => t.id));
        this._boardFolded = !!on;
        return this.relayout();
      }
      this.folded = new Set(on ? this.tracks.map(t => t.id) : []);
      if (this.opts.onFold) this.opts.onFold([...this.folded]);
      this.relayout();
    }
    allFolded() {
      return this.tracks.length > 0 && this.tracks.every(t => this._foldedNow(t.id));
    }

    /** 민족 묶음 접기/펴기 (key = "트랙id|민족id") */
    toggleFoldPeople(key, force) {
      const on = force == null ? !this.foldedPeoples.has(key) : !!force;
      if (on) this.foldedPeoples.add(key);
      else this.foldedPeoples.delete(key);
      if (this.opts.onFoldPeople) this.opts.onFoldPeople([...this.foldedPeoples]);
      this.relayout();
    }

    /** 소속 정권(연맹 구성국·종속국·조직체) 펼치기/접기 — 상위 정권 uid */
    toggleMembers(uid, force) {
      const on = force == null ? !this.expandedHosts.has(uid) : !!force;
      if (on) this.expandedHosts.add(uid);
      else this.expandedHosts.delete(uid);
      if (this.opts.onExpand) this.opts.onExpand([...this.expandedHosts]);
      this.relayout();
    }

    /** 그 상국의 매달린 속국 이름표를 접어 두었는가 (생성자를 건너뛴 배치기 — 내보내기 · 검사의 가짜 연표에는 기록이 없으면 모두 펼침) */
    _hangsFolded(uid) {
      if (this.seogo) return !(this.openHangs && this.openHangs.has(uid)); // 서고: 처음에는 모두 접힘 — 펼친 상국만 기억(새 앱 ViewState.openHangs · 이번 보기에서만)
      return !!(this.foldedHangs && this.foldedHangs.has(uid));
    }

    /** 상국 띠 아래에 매달린 속국 이름표 접기/펼치기 — 상국 uid (접으면 그 줄이 매달린 줄만큼 낮아짐) */
    toggleHangs(uid, force) {
      if (this.seogo) {
        if (!this.openHangs) this.openHangs = new Set();
        const fold = force == null ? this.openHangs.has(uid) : !!force;
        if (fold) this.openHangs.delete(uid);
        else this.openHangs.add(uid);
        this.relayout();
        return;
      }
      if (!this.foldedHangs) this.foldedHangs = new Set();
      const on = force == null ? !this.foldedHangs.has(uid) : !!force;
      if (on) this.foldedHangs.add(uid);
      else this.foldedHangs.delete(uid);
      if (this.opts.onFoldHangs) this.opts.onFoldHangs([...this.foldedHangs]);
      this.relayout();
    }

    /** 지도자 칸 표기 방식과 대수 표시 */
    setLeaderLabel(mode, ordinal) {
      if (mode != null) this.leaderMode = mode;
      if (ordinal != null) this.leaderOrdinal = !!ordinal;
      this.tracks.forEach(tr => (tr._labelSig = null));
      this.render();
    }

    /** 왼쪽 줄 이름 칸의 원어 병기(10건 3 · 감독 결정 D2-2 '맨 왼쪽 구분표에서만'): fn(정권) → { text } | null. null이면 병기 없음(지금 그대로).
        줄 높이 · 배치는 그대로라 줄 이름만 다시 씁니다. redraw = false면 다음 그리기에(자료를 새로 넣기 직전 — setData가 다시 그림) */
    setOrig(fn, redraw = true) {
      this.origOf = typeof fn === 'function' ? fn : null;
      this.tracks.forEach(tr => (tr._labelSig = null));
      if (redraw) this.render();
    }

    /** 화면 글꼴이 바뀜(글꼴 팩을 싣거나 화면 글꼴을 고름 — 10건 9): 글 폭을 재는 글꼴 목록 · 잰 폭 · 기준선을 비우고 다시 배치합니다(겹침 금지가 기대는 폭을 새 글꼴로) */
    refont() {
      fontStack = '';
      bodyLs = null;
      widths.clear();
      inkMetrics.clear();
      baseMemo.clear();
      this.tracks.forEach(tr => (tr._labelSig = null));
      this.relayout();
    }

    /** 연호 줄 접기/펴기 (여러 갈래 → 한 줄) */
    toggleFoldEra(trackId, force) {
      const on = force == null ? !this.foldedEras.has(trackId) : !!force;
      if (on) this.foldedEras.add(trackId);
      else this.foldedEras.delete(trackId);
      if (this.opts.onFoldEra) this.opts.onFoldEra([...this.foldedEras]);
      this.relayout();
    }

    /** 맨 위 날짜 칸의 큰 묶음(연호 · 도읍) 펼치기/접기 — 펼치면 나라별 줄이 나옵니다 */
    toggleAxisGroup(key, force) {
      const on = force == null ? !this.axisOpen.has(key) : !!force;
      if (on) this.axisOpen.add(key);
      else this.axisOpen.delete(key);
      if (this.opts.onAxisGroup) this.opts.onAxisGroup([...this.axisOpen]);
      this.relayout();
    }

    /** 나라별 도읍 줄의 배도(별도·5경·소경) 갈래 펼치기/접기 */
    toggleCapSec(trackId, force) {
      const on = force == null ? !this.openCapSec.has(trackId) : !!force;
      if (on) this.openCapSec.add(trackId);
      else this.openCapSec.delete(trackId);
      if (this.opts.onCapSec) this.opts.onCapSec([...this.openCapSec]);
      this.relayout();
    }

    /** 보조 달력(음력·이슬람력 …) 줄 — 해보다 작게 확대했을 때 날짜 칸 아래에 나옵니다. ''이면 끔 */
    setAltCal(id) {
      this.altCal = id || '';
      if (this.opts.onAltCal) this.opts.onAltCal(this.altCal);
      this._buildAxis();
      this.render();
    }

    /** 창이 열려 있는 동안 고른 항목의 줄을 세로 닻으로: 옮기고 확대하고 위쪽 줄이 접히고 펴져도 그 줄이 화면에서 제자리에 머뭅니다.
        누른 것은 달아나지 않습니다 — reveal(새로 골랐을 때): 그 줄이 이미 잘 보이면(위아래 여유 SAFE_Y 안쪽에 온전히) 화면은 1px도 움직이지 않고,
        가장자리에 걸렸거나 가려졌을 때만 여유 안으로 들어오는 최소 거리를 스프링으로 옮깁니다. center(가운데 맞춤)는 멀리 갈 때만 — focusOn(검색·여기로 가기).
        사용자가 스크롤 막대나 세로 끌기로 직접 옮기면 그 자리가 새 기준이 됩니다 */
    setAnchor(uid, { reveal = false, center = false } = {}) {
      if (reveal || center) this._stopCoast(); // 미끄러지던 중에 골라 데려와야 하면 관성은 거기까지 — 세로는 이제 닻이 씁니다
      const changed = (uid || null) !== this.anchorUid;
      this.anchorUid = uid || null;
      const a = this._anchorLane();
      if (!a) {
        this._anchorOff = this._anchorSpring = this._anchorTo = null; // 그릴 줄이 없는 항목(시대 구분·왕조·접힌 트랙 속): 화면 가운데 줄을 붙잡습니다
        return;
      }
      if (changed || this._anchorOff == null) {
        /* 다른 줄로 닻을 옮김: 지금 그 줄이 있는 자리가 기준. 화면이 아직 움직이던 중이면(앞선 데려오기) 그 속도는 이어받습니다 */
        const t = this._anchorClock();
        const sp = this._anchorSpring;
        const v = sp && !sp.done(t) ? sp.velocity(t) : 0;
        this._anchorOff = this._laneAbs(a) - this.bodyEl.scrollTop;
        this._anchorTo = null;
        this._anchorSpring = Math.abs(v) > 1 ? this._newAnchorSpring(this._anchorOff).set(this._anchorOff, v, t) : null;
        if (this._anchorSpring) this._anchorLoop();
      }
      if (center || reveal) this._revealAnchor(center);
    }

    _newAnchorSpring(value) {
      return new HT.motion.Spring(value, { response: 0.36, restDelta: 0.25, restSpeed: 2 }); // 되튐 0(임계 감쇠) — docs/움직임-개선안.md 4절의 move
    }

    /** 닻 줄을 데려옵니다: center면 화면 가운데로(멀리 갈 때만), 아니면 위아래 여유(SAFE_Y) 안으로 들어오는 최소 거리만 — 이미 잘 보이면 아무것도 하지 않습니다.
        목표만 정해 두고, 출발은 다음 프레임에 합니다(_anchorLoop) — 고른 직후의 무거운 그리기가 끝난 뒤에 시계가 돌기 시작해 첫 프레임에 덜컥 뛰지 않습니다.
        이미 움직이던 중이면 지금 값·지금 속도에서 새 목표로 이어 갑니다 */
    _revealAnchor(center = false) {
      const a = this._anchorLane();
      if (!a) return;
      const cur = this._laneAbs(a) - this.bodyEl.scrollTop;
      if (this._anchorOff == null) this._anchorOff = cur;
      if (!center && a.tr.hiddenRows.has(a.row)) return; // 이 시기에 그릴 것이 없어 접힌 줄 — 옮겨서 보여 줄 것이 없습니다
      const to = this._revealTo(a, cur, center);
      const from = this._anchorSpring ? this._anchorSpring.target : this._anchorOff;
      if (Math.abs(to - from) < 0.5 && this._anchorTo == null) return;
      if (reduceMotion()) {
        this._anchorSpring = this._anchorTo = null;
        this._anchorOff = to;
        return this._keepAnchor();
      }
      this._anchorTo = to;
      this._anchorLoop();
    }

    /** 줄 a를 데려다 놓을 자리(화면 위에서 떨어진 거리): center면 화면 가운데, 아니면 지금 자리(cur)에서 위아래 여유(SAFE_Y) 안으로 들어오는 가장 가까운 곳 — 스크롤이 닿는 데까지만 */
    _revealTo(a, cur, center = false) {
      const H = this.bodyEl.clientHeight;
      const h = a.tr.baseRowHs[a.row] || 0; // 접혀 있던 줄이라도 펴졌을 때의 높이로
      const lo = SAFE_Y + this._G().tab; // 띠 위 책갈피 탭까지 보이게 (조감은 탭 없음)
      const hi = H - SAFE_Y - h;
      let to;
      if (center) to = Math.max(lo, (H - h) / 2);
      else if (hi >= lo) to = HT.clamp(cur, lo, hi);
      else to = cur > lo ? lo : Math.max(cur, hi); // 화면보다 높은 줄: 위쪽이 보이게, 이미 화면을 다 덮고 있으면 그대로
      return this._reachable(a.tr, a.tr.rowTop[a.row], to);
    }

    /** 스크롤이 닿을 수 있는 데까지만: 트랙 tr 안의 세로 자리 y를 화면 위에서 to만큼 떨어진 곳에 두려 할 때 실제로 가능한 값.
        맨 위·맨 아래 줄은 가운데까지 올 수 없으므로, 끝에 부딪혀 뚝 멈추지 않게 처음부터 닿을 수 있는 자리를 목표로 삼습니다.
        높이가 흐르는 도중일 수 있어 화면이 아니라 모델의 최종 높이로 셉니다 */
    _reachable(tr, y, to) {
      const { tops, total } = this._modelTops();
      const abs = (tops.get(tr) || 0) + y;
      return abs - HT.clamp(abs - to, 0, Math.max(0, total - this.bodyEl.clientHeight));
    }

    /** 세로 배치를 모델로 셉니다: 트랙마다의 위쪽 자리(tops)와 전체 높이(total). 높이가 흐르는 도중에는 화면을 재 볼 수 없으므로, 다 흐른 뒤의 자리는 여기서 셉니다.
        트랙의 높이는 아래 테두리까지 든 값입니다(border-box) */
    _modelTops() {
      const tops = new Map();
      let total = 0;
      for (const tr of this.tracks) {
        total += this._sphereLead(tr); // 서고: 문화권 머리 단 · 틈
        tops.set(tr, total);
        total += tr.height;
      }
      return { tops, total };
    }

    /* ---------- 서고 3단 · 문화권 머리 단 (새 앱 layout.dart 리메이크 조각 ② · 설계 4-6 #1 A · #5 B) ----------
       트랙은 문화권 차례로 서 있고(core.js buildModel), 문화권이 바뀌는 트랙 앞에 머리 단 20(왼쪽 칸 왼쪽 3 ~ 그림판 끝 · 구멍 · 이름 11 · 띠 수 · 오른쪽 끝 ▾/▸)을 두고 펼친 문화권은 그 아래 4 뒤에 트랙 ·
       문화권 사이 6. 접힌 문화권은 머리 단 하나뿐(그 트랙은 높이 0으로 숨고 머리 단 안에 보는 범위의 띠를 작은 꼬리표 13으로 · 막히면 +n). 처음 접힘 = 기본 문화권(고치는 DLC의 첫 트랙의 것) 하나만 폄 →
       기억(opts.foldedSpheres · onFoldSphere) · 문화권이 하나면 접지 않음. 문화권 밖 트랙(판 트랙 · 모르는 id)은 머리 단 없이 그대로. 서고가 아니면 아무것도 하지 않음 */
    _sphereSetup(list, defaultSphere) {
      this.spheres = [];
      for (const tr of this.tracks) {
        tr._sphere = null;
        tr._sphereHidden = false;
      }
      if (!this.seogo) return;
      const byId = new Map((list || []).map(s => [s.id, s]));
      for (const tr of this.tracks) {
        const id = tr.board ? '' : tr.sphere || '';
        if (!id || !byId.has(id)) continue;
        let s = this.spheres.find(x => x.id === id);
        if (!s) {
          s = { id, name: byId.get(id).name || id, tracks: [], count: 0, folded: false, el: null };
          this.spheres.push(s);
        }
        s.tracks.push(tr);
        tr._sphere = s;
        s.count += tr.periods.filter(p => p.polityKind !== 'dynasty').length;
      }
      if (this.foldedSpheres === null) {
        const open = (defaultSphere && this.spheres.find(s => s.id === defaultSphere)) || this.spheres[0];
        this.foldedSpheres = new Set(this.spheres.length >= 2 ? this.spheres.filter(s => s !== open).map(s => s.id) : []);
        if (this.opts.onFoldSphere) this.opts.onFoldSphere([...this.foldedSpheres]);
      }
      for (const s of this.spheres) {
        s.folded = this.spheres.length >= 2 && this.foldedSpheres.has(s.id);
        for (const tr of s.tracks) tr._sphereHidden = s.folded;
      }
      for (const s of this.spheres) this._sphereF4(s); // 과제 9: 머리 단 밑 줄(시대 구분 · 주기 · 사람 띠)의 높이
    }

    /** 이 트랙 앞에 오는 문화권 머리 단 · 틈의 높이(문화권의 첫 트랙에만) — 트랙을 차례로 쌓는 곳(_modelTops · _draw · _planUnions · _buildTracks)이 같은 값을 더합니다 */
    _sphereLead(tr) {
      const s = tr._sphere;
      if (!s || s.tracks[0] !== tr) return 0;
      return (this.spheres[0] === s ? 0 : G_SEOGO.sphereBetween) + G_SEOGO.sphereHead + (s.folded ? 0 : (s.extraH || 0) + G_SEOGO.sphereGap);
    }

    /** 문화권 머리 단의 요소(HTML) — _buildTracks가 문화권의 첫 트랙 앞에 끼움. 접힌 문화권의 작은 꼬리표는 그리기마다 _drawSphereTags가 채움 */
    _sphereHTML(s) {
      const lead = this._sphereLead(s.tracks[0]);
      const mt = lead - G_SEOGO.sphereHead - (s.folded ? 0 : (s.extraH || 0) + G_SEOGO.sphereGap);
      return `<div class="tl-sphere${s.folded ? ' is-folded' : ''}" data-sphere="${esc(s.id)}" role="button" tabindex="0" aria-expanded="${!s.folded}" title="${esc(`${s.name} · ${s.folded ? '펼치기' : '접기'}`)}" style="height:${G_SEOGO.sphereHead + (s.folded ? 0 : s.extraH || 0)}px;margin-top:${mt}px;margin-bottom:${s.folded ? 0 : G_SEOGO.sphereGap}px"><i class="tl-hole"></i><b>${esc(s.name)}</b><small>${s.count}</small><span class="tl-sphere-tags"></span><span class="tl-sphere-rows"></span><em>${s.folded ? '▸' : '▾'}</em></div>`;
    }

    /** 접힌 문화권의 머리 단 안 작은 꼬리표(높이 13 · 구멍 · 이름 8.5 굵게 — 새 앱 minibars.dart): 보는 범위에 든 그 문화권의 띠를 시작 차례로, 자리가 막히면 '+n' */
    _drawSphereTags(s, X, W) {
      if (!s.el) return;
      const box = s.el.querySelector('.tl-sphere-tags');
      if (!box) return;
      if (!s.folded) {
        if (box.innerHTML) box.innerHTML = '';
        this._drawSphereRows(s, X, W); // 과제 9: 머리 단 밑 줄
        return;
      }
      const list = [];
      for (const tr of s.tracks) for (const p of tr.periods) if (p.polityKind !== 'dynasty' && p.polityKind !== 'overlay' && !p._under) list.push(p);
      const html = this._stagsHTML(list, X, W, 3);
      if (box._html !== html) {
        box.innerHTML = html;
        box._html = html;
      }
    }

    /* ---------- 서고 과제 9 · 형식 4 모델의 새 장치(계획 정한 것 #3 — opts/setData의 f4 = HT.f4Preview(모델, 작업본) · 메이커만) ----------
       사람 띠: 왕관(지도자 칸의 person 이음)이 둘 이상인 사람을 첫 왕관 트랙의 문화권 머리 단 밑에 흰 종이 띠 16(구멍 · 이름 · 때 · 왕관 n)으로, 종이 아랫변에서 칸마다 점선 실이
       띠 뒤 통로(.tl-f4-threads — 줄 층 아래)로 내려가 그 띠 윗변에 작은 뿔 매듭(밑변 5 · 높이 4.5 · 테 1)으로 닿는다(목업 w-1-crowns personBar · 감독 10-23 "글자가 가려지면 안 됨").
       문화권 머리 단 밑: 그 문화권의 시대 구분 줄 14 · 주기 줄 13(이름 돌림은 해마다 칸 · 연호 눈금은 step마다). 접힌 문화권은 머리 단뿐.
       빌린 층: 빌린 자리(leadersFrom · cabinetsFrom)의 칸은 윗선 점선 · 옅게, 이름 옆에 '· 직위 ← 출처'. 밑줄 실권: 빼앗긴 쪽 띠 머리 아랫변의 2px(쥔 쪽 색) + 오른쪽 끝에 쥔 쪽 이름 8.5 ·
       그 동안의 지도자 칸은 옅게. 서고가 아니거나 f4가 없으면(내보내기 · 조감) 아무것도 더하지 않는다 — 배치 바이트 그대로 */
    _sphereF4(s) {
      const f4 = this.seogo && this._data && this._data.f4;
      s.f4 = null;
      s.extraH = 0;
      if (!f4) return;
      const rows = (f4.sphereRows || {})[s.id] || null;
      const trackOf = uid => this.tracks.find(tr => tr.periods.some(p => p.uid === uid));
      /* 사람 띠는 왕관들의 문화권 가운데 가장 위(머리 단 차례가 앞선) 문화권 밑에 — 실이 아래로만 내려가게 */
      const topSphere = ps => { let best = null; for (const cr of ps.crowns || []) { const tr = trackOf(cr.uid); const sp = tr && tr._sphere; if (sp && (!best || this.spheres.indexOf(sp) < this.spheres.indexOf(best))) best = sp; } return best; };
      const persons = (f4.persons || []).filter(ps => topSphere(ps) === s);
      const epochs = rows ? rows.epochs.filter(e => e.start != null || e.end != null) : [];
      const cycle = rows ? rows.cycle : null;
      if (!epochs.length && !cycle && !persons.length) return;
      /* 사람 띠 줄 나눔: 때가 겹치지 않는(앞뒤 틈 2해) 사람은 한 줄에 — 사람마다 한 줄씩 두면 넓게 볼 때 빈 줄만 쌓임 */
      const lanes = [];
      for (const ps of persons.slice().sort((a, b) => a.start - b.start)) {
        let k = lanes.findIndex(end => end + 2 <= ps.start);
        if (k < 0) k = lanes.push(-Infinity) - 1;
        lanes[k] = ps.end;
        ps._lane = k;
      }
      s.f4 = { epochs, cycle, persons, lanes: lanes.length };
      s.extraH = (epochs.length ? G_SEOGO.f4Epoch : 0) + (cycle ? G_SEOGO.f4Cycle : 0) + lanes.length * G_SEOGO.f4Person + 2;
    }
    /** 펼친 문화권의 머리 단 밑 줄(시대 구분 · 주기 · 사람 띠) — 그리기마다 (_drawSphereTags가 부름) */
    _drawSphereRows(s, X, W) {
      const box = s.el && s.el.querySelector('.tl-sphere-rows');
      if (!box) return;
      const f = s.f4;
      if (!f || s.folded) {
        if (box.innerHTML) box.innerHTML = '';
        return;
      }
      let html = '';
      let y = 0;
      if (f.epochs.length) {
        html += `<em class="tl-srow-lab" style="top:${y}px">시대</em>`; // 줄 이름(왼쪽 칸)
        for (const e of f.epochs) {
          const a = Math.max(e.start == null ? -1e9 : X(e.start), 0), b = Math.min(e.end == null ? 1e9 : X(e.end), W);
          if (b - a < 2) continue;
          html += `<i class="tl-srow tl-srow-ep" style="left:${cx(a)}px;width:${cx(b - a)}px;top:${y}px" title="${esc(e.name)}">${esc(e.name)}</i>`;
        }
        y += G_SEOGO.f4Epoch;
      }
      if (f.cycle) {
        const cyc = f.cycle;
        let cells = '';
        const y0 = Math.floor(this.view.start), y1 = Math.ceil(this.view.end);
        const yw = X(y0 + 1) - X(y0);
        if (cyc.names && yw >= 9 && y1 - y0 <= 400) {
          const n = cyc.names.length;
          for (let yr = y0; yr <= y1; yr++) {
            const x0 = X(yr), x1 = X(yr + 1);
            if (x1 < 0 || x0 > W) continue;
            const i = (((yr - cyc.start) % n) + n) % n;
            const first = i === 0;
            cells += `<b${first ? ' class="is-first"' : ''} style="left:${cx(x0)}px;width:${cx(x1 - x0)}px">${yw >= 16 ? esc(cyc.names[i]) : ''}</b>`;
          }
        } else if (cyc.names && cyc.names.length) {
          /* 해 한 칸이 좁으면 한 바퀴(이름 n개)를 한 칸으로 — 눈금 줄의 간지처럼 첫 이름(+ 해)만. 바퀴 칸도 좁으면 빈 칸(경계만) */
          const n = cyc.names.length, rw = yw * n;
          if (rw >= 4 && (y1 - y0) / n <= 400) for (let yr = y0 - ((((y0 - cyc.start) % n) + n) % n); yr <= y1; yr += n) {
            const x0 = Math.max(X(yr), 0), x1 = Math.min(X(yr + n), W, box.clientWidth || W); // 보이는 몫만(줄 상자 오른쪽 끝 · 화면 가장자리에서 글이 반쯤 잘리지 않게)
            if (x1 - x0 < 1) continue;
            const full = `${cyc.names[0]} ${HT.formatAxisYear(yr)}`;
            const text = x1 - x0 >= textWidth(full, 8, 700) + 8 ? full : x1 - x0 >= textWidth(cyc.names[0], 8, 700) + 6 ? cyc.names[0] : '';
            cells += `<b class="is-first" style="left:${cx(x0)}px;width:${cx(x1 - x0)}px">${esc(text)}</b>`;
          }
        } else if (cyc.era) {
          const step = Math.max(1, cyc.step || 1);
          const from = Math.ceil(this.view.start / step) * step;
          if ((this.view.end - from) / step <= 400) for (let yr = from; yr <= y1; yr += step) {
            const x0 = X(yr), x1 = X(yr + step);
            if (x1 < 0 || x0 > W) continue;
            cells += `<b class="is-first" style="left:${cx(x0)}px;width:${cx(Math.max(x1 - x0, 1))}px">${x1 - x0 >= 40 ? esc(`${cyc.era} ${yr - cyc.from}년`) : ''}</b>`;
          }
        }
        html += `<i class="tl-srow tl-srow-cy" style="left:0;width:${cx(W)}px;top:${y}px" title="${esc(cyc.label || cyc.era || '')}">${cells}</i><em class="tl-srow-lab" style="top:${y}px">${esc(cyc.label || cyc.era || '')}</em>`; // 줄 이름은 왼쪽 칸(눈금 이름 자리 — 마지막 칸 글과 겹치지 않게)
        y += G_SEOGO.f4Cycle;
      }
      f.persons.forEach((ps, k) => {
        const a0 = X(ps.start), b0 = X(ps.end);
        if (b0 < 0 || a0 > W) return;
        const a = Math.max(a0, 0), b = Math.min(Math.max(b0, a0 + 14), W); // 좁아도 구멍 하나는 보이게(14) — 이름 · 때는 들어가는 만큼(줄임표)
        const tip = `${ps.name} · ${HT.formatYear(ps.start)} ~ ${HT.formatYear(ps.end)} · 왕관 ${ps.crowns.length}`;
        html += `<i class="tl-person${b - a < 40 ? ' is-tiny' : b - a < 60 ? ' is-narrow' : ''}" data-person="${k}" style="left:${cx(a)}px;width:${cx(b - a)}px;top:${y + (ps._lane || 0) * G_SEOGO.f4Person}px" title="${esc(tip)}"><i class="tl-hole"></i><b>${esc(ps.name)}</b><small>${esc(`${ps.start} ~ ${ps.end}  ·  왕관 ${ps.crowns.length}`)}</small></i>`;
      });
      y += (f.lanes || 0) * G_SEOGO.f4Person;
      if (box._html !== html) {
        box.innerHTML = html;
        box._html = html;
      }
    }
    /** 사람 띠의 실 · 뿔 매듭 — 줄 층 아래의 그림판 한 장(.tl-f4-threads · tracksEl 좌표)에 자리를 DOM에서 재어 그린다(띠가 실을 가림 = 띠 뒤 통로) */
    _drawF4Threads() {
      const f4 = this.seogo && this._data && this._data.f4;
      let svg = this.f4El;
      if (!f4 && !svg) return;
      if (!svg) {
        svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('class', 'tl-f4-threads');
        svg.setAttribute('aria-hidden', 'true');
        this.tracksEl.appendChild(svg);
        this.f4El = svg;
      } else if (!svg.isConnected) this.tracksEl.appendChild(svg); // 트랙을 다시 지으면(_buildTracks의 innerHTML) 떨어져 나가므로 다시 붙임
      let d = '', knots = '';
      if (f4 && !this._bird) {
        const r0 = this.tracksEl.getBoundingClientRect();
        for (const s of this.spheres) {
          if (s.folded || !s.f4 || !s.el) continue;
          const rows = s.el.querySelector('.tl-sphere-rows');
          if (!rows) continue;
          s.f4.persons.forEach((ps, k) => {
            const el = rows.querySelector(`.tl-person[data-person="${k}"]`);
            if (!el) return;
            const pr = el.getBoundingClientRect();
            const by = Math.round(pr.bottom - r0.top) + 0.5;
            for (const cr of ps.crowns) {
              const tr = this.tracks.find(t => t.periods.some(p => p.uid === cr.uid));
              if (!tr || !tr.el || !tr.lanesEl || tr._sphereHidden || tr.folded) continue;
              const cell = tr.lanesEl.querySelector(`.tl-band[data-uid="${CSS.escape(cr.uid)}"] .tl-cell.k-leader[data-cell="leader:${cr.i}"]`);
              const band = cell && cell.closest('.tl-band');
              if (!cell || !band) continue;
              const cb = cell.getBoundingClientRect(), bb = band.getBoundingClientRect();
              if (cb.width < 4) continue;
              const x = Math.round(Math.max(cb.left, bb.left) - r0.left) + 8.5, top = Math.round(bb.top - r0.top) + 0.5;
              if (top <= by + G_SEOGO.f4Horn + 2) continue;
              d += `M${x},${by + 1.5} V${top - G_SEOGO.f4Horn}`;
              knots += `<path class="tl-knot" d="M${x - 2.5},${top} L${x},${top - G_SEOGO.f4Horn} L${x + 2.5},${top} Z"/><circle class="tl-knot-dot" cx="${x}" cy="${by}" r="1.5"/>`;
            }
          });
        }
      }
      const html = d || knots ? `<path class="tl-thread-p" d="${d}"/>${knots}` : '';
      if (svg._html !== html) {
        svg.innerHTML = html;
        svg._html = html;
      }
      /* 줄 높이 · 머리 단이 흐르는 동안(CSS 전환) 잰 자리는 흐름이 끝나면 낡으므로, 흐름이 남아 있으면 조금 뒤 다시 잼 — 끝난 뒤의 한 번이 마지막 */
      clearTimeout(this._f4Late);
      const flowing = f4 && this.tracksEl.getAnimations && this.tracksEl.getAnimations({ subtree: true }).some(a => a.playState === 'running' && typeof CSSTransition !== 'undefined' && a instanceof CSSTransition);
      if (flowing) this._f4Late = setTimeout(() => this._drawF4Threads(), 120);
      const w = this.tracksEl.scrollWidth, h = this.tracksEl.scrollHeight;
      if (svg._w !== w || svg._h !== h) {
        svg.setAttribute('width', w);
        svg.setAttribute('height', h);
        svg._w = w;
        svg._h = h;
      }
    }
    /** 빌린 자리(leadersFrom · cabinetsFrom — HT.f4Preview의 borrows) */
    _f4Borrow(uid, kind) {
      const f4 = this.seogo && this._data && this._data.f4;
      const b = f4 && f4.borrows && f4.borrows[uid];
      return b ? b[kind] || null : null;
    }
    _f4BorrowText(uid) {
      const f4 = this.seogo && this._data && this._data.f4;
      const b = f4 && f4.borrows && f4.borrows[uid];
      if (!b) return '';
      return [b.leader && `· ${b.leader.name} ← ${b.leader.from}`, b.cabinet && `· ${b.cabinet.name} ← ${b.cabinet.from}`].filter(Boolean).join('  ');
    }
    /** 이 객체가 빼앗긴 실권(쥔 쪽의 power[].over가 이 객체 — HT.f4Preview의 powers) */
    _f4Powers(uid) {
      const f4 = this.seogo && this._data && this._data.f4;
      return (f4 && f4.powers && f4.powers[uid]) || [];
    }
    /** 문화권 접기 · 펴기(머리 단 어디를 눌러도) — 기억은 opts.onFoldSphere로 */
    toggleFoldSphere(id, force) {
      if (!this.foldedSpheres) this.foldedSpheres = new Set();
      const on = force == null ? !this.foldedSpheres.has(id) : !!force;
      if (on) this.foldedSpheres.add(id);
      else this.foldedSpheres.delete(id);
      if (this.opts.onFoldSphere) this.opts.onFoldSphere([...this.foldedSpheres]);
      this.relayout();
    }

    /** 지금 세로로 붙잡혀 있는 줄 { tr, row, off } — 닻(고른 줄)이 있으면 그 줄, 없으면 잠시 붙잡은 줄이나 화면 가운데 줄. 데려오는 중이면 off는 도착할 자리 */
    _holdNow() {
      const a = this.anchorUid ? this._anchorLane() : null;
      if (a) {
        const off = this._anchorTo != null ? this._anchorTo : this._anchorSpring ? this._anchorSpring.target : this._anchorOff;
        return { tr: a.tr, row: a.row, off: off != null ? off : this._laneAbs(a) - this.bodyEl.scrollTop };
      }
      const h = this._heldAuto();
      return h ? { tr: h.tr, row: h.row, off: h.to != null ? h.to : h.spring ? h.spring.target : h.off } : null;
    }

    /** 줄 높이가 다 흐른 뒤의 세로 배치(모델): 트랙의 위쪽 자리(tops) · 전체 높이(total) · 그때의 스크롤 위치(top — 붙잡힌 줄 hold가 제자리에 머문다고 보고, 스크롤이 닿는 데까지) */
    _finalGeom(hold) {
      const g = this._modelTops();
      const max = Math.max(0, g.total - this.bodyEl.clientHeight);
      const live = hold && g.tops.has(hold.tr);
      g.top = HT.clamp(live ? g.tops.get(hold.tr) + (hold.row >= 0 && !hold.tr.folded ? hold.tr.rowTop[hold.row] : 0) - hold.off : this.bodyEl.scrollTop, 0, max);
      return g;
    }

    /** 닻 줄: 고른 항목이 놓인 줄 { tr, row, lane } (그 시기에 그려지지 않으면 null) */
    _anchorLane() {
      return this._laneOf(this.anchorUid);
    }

    /** 항목(uid)이 놓인 줄 { tr, row, lane } — 제 줄이 없거나(시대 구분·왕조) 접힌 트랙 속이면 null */
    _laneOf(uid) {
      if (!uid) return null;
      for (const tr of this.tracks) {
        if (tr.folded || !tr.el || !tr.laneEls) continue;
        const p = tr.periods.find(x => x.uid === uid);
        const e = !p && tr.events.find(x => x.uid === uid);
        const fg = !p && !e && (tr.figures || []).find(x => x.f.uid === uid && x.row != null); // 인물: 섬긴 정권의 줄 (단에서 넘쳐 그려지지 않았어도 그 줄)
        const row = p ? p._row : e ? e._row : fg ? fg.row : null;
        if (row == null || !tr.laneEls[row]) continue;
        return { tr, row, lane: tr.laneEls[row] };
      }
      return null;
    }

    _laneAbs(a) {
      return a.tr.el.offsetTop + a.lane.offsetTop;
    }

    /** 닻이 없을 때: 화면 가운데에 걸린 줄을 이번 그리기의 임시 닻으로 */
    _autoAnchor() {
      const b = this.bodyEl;
      const mid = b.scrollTop + b.clientHeight / 2;
      let best = null;
      for (const tr of this.tracks) {
        if (!tr.el) continue;
        const t0 = tr.el.offsetTop;
        if (t0 > mid) break;
        if (tr.folded || !tr.laneEls) {
          best = { tr, row: -1, abs: t0 };
          continue;
        }
        for (let r = 0; r < tr.laneEls.length; r++) {
          if (tr.hiddenRows && tr.hiddenRows.has(r)) continue;
          const abs = t0 + tr.laneEls[r].offsetTop;
          if (abs > mid) break;
          best = { tr, row: r, abs };
        }
      }
      return best ? Object.assign(best, { off: best.abs - b.scrollTop }) : null;
    }

    /** 닻이 없을 때 붙잡을 줄: 접기·펼치기의 흐름이 도는 동안은 누르기 직전에 잡아 둔 줄(_applyFlip), 그 밖에는 지금 화면 가운데 줄 */
    _heldAuto() {
      const h = this._held;
      if (h && HT.motion.now() < h.until + (h.spring || h.to != null ? 1200 : 0) && h.tr.el && h.tr.el.isConnected) return h; // 데려오는 중이면 조금 더 (길어도 1.2초)
      this._held = null;
      return this._autoAnchor();
    }

    _scrollSelf(top) {
      const b = this.bodyEl;
      const t = HT.clamp(top, 0, Math.max(0, b.scrollHeight - b.clientHeight));
      if (Math.abs(t - b.scrollTop) < 0.5) return void (this._selfTop = b.scrollTop);
      this._selfScroll = performance.now();
      b.scrollTop = t;
      this._selfTop = b.scrollTop; // 우리가 둔 스크롤 (스크롤 듣개가 손으로 옮긴 것과 가름 — 값으로: 시간 창과 달리 흐름 직후의 손 스크롤도 놓치지 않음)
    }

    /** 세로를 손이 쥐고 있는가 — 끄는 동안과, 놓은 뒤 그 속도로 미끄러지는 동안(관성). 그동안 세로 스크롤은 손(과 관성)이 쓰고 닻은 쉽니다 — 서로 다투지 않게 */
    _handHeld() {
      return this.bodyEl.classList.contains('is-dragging') || !!this._coast;
    }

    /** 닻 줄을 제자리에 (그리기 뒤 · 줄 높이가 흐르는 동안 매 프레임) */
    _keepAnchor(auto = null) {
      if (this._handHeld()) return;
      const a = this.anchorUid ? this._anchorLane() : null;
      if (!a) this._anchorOff = this._anchorSpring = this._anchorTo = null; // 닻 줄이 없거나 사라졌으면(그 트랙을 접음) 데려오기도 그만두고, 화면 가운데 줄을 붙잡습니다
      if (a) {
        const b = this.bodyEl;
        if (this._anchorOff == null) this._anchorOff = this._laneAbs(a) - b.scrollTop; // 그 줄이 이제 막 그려졌으면(접힌 트랙을 폈을 때) 지금 자리가 기준
        const sp = this._anchorSpring;
        let arrived = false;
        let near = false; // 눈에는 다 온 것(남은 거리 1px 미만) — 도착 표시는 이때. 스프링이 완전히 쉴 때(arrived)까지는 조금 더 걸립니다
        if (sp) {
          const t = this._anchorClock();
          this._anchorOff = sp.value(t);
          arrived = this._anchorTo == null && sp.done(t);
          near = this._anchorTo == null && Math.abs(sp.target - this._anchorOff) < 1;
        }
        this._scrollSelf(this._laneAbs(a) - this._anchorOff);
        if (arrived) {
          this._anchorSpring = null;
          this._anchorOff = this._laneAbs(a) - b.scrollTop; // 스크롤 끝에 걸려 다 가지 못했으면 실제로 닿은 자리가 기준
        }
        if (near || arrived) this._arrived();
        return;
      }
      if (!auto || !auto.tr.el) return;
      let near = false;
      if (auto.spring) {
        /* 붙잡은 줄을 데려오는 중 (위쪽이 가려진 긴 트랙을 접었을 때 — _applyFlip · 가장자리 안내의 "여기로" — _bringRow) */
        const t = this._anchorClock();
        auto.off = auto.spring.value(t);
        near = auto.to == null && Math.abs(auto.spring.target - auto.off) < 1;
        if (auto.to == null && auto.spring.done(t)) auto.spring = null;
      }
      const abs = auto.row < 0 ? auto.tr.el.offsetTop : auto.tr.el.offsetTop + (auto.tr.laneEls && auto.tr.laneEls[auto.row] ? auto.tr.laneEls[auto.row].offsetTop : 0);
      this._scrollSelf(abs - auto.off);
      if (near) this._arrived();
    }

    /** 데려오기·멀리 가기가 도착했을 때 한 번 부를 것(도착 표시)을 맡겨 둡니다 — 도중에 누르거나 직접 옮기면 버립니다 */
    _arrived() {
      const fn = this._arrive;
      this._arrive = null;
      if (fn) fn();
    }

    /** 멀리 가기의 세로 — 가로 비행과 같은 진행값으로 그 항목의 줄을 화면 가운데로 옮겨, 가로·세로가 대각선 한 번에 같은 프레임에 도착합니다(_animateTo가 매 프레임 _carry를 나아가게 함).
        옮기는 것은 스크롤이 아니라 "붙잡은 줄이 화면 위에서 떨어진 거리"입니다: 닻(창이 열린 항목의 줄)이 있으면 닻의 자리(_anchorOff)를, 없으면 그 줄을 비행 동안 붙잡아(_held) 그 자리를.
        scrollTop은 여전히 _keepAnchor 하나만 쓰므로, 도중에 위쪽 줄이 펴져도 어긋나지 않습니다. 목표는 다시 배치한 뒤의 줄에서 셉니다(접힌 트랙 속에 있던 항목도 이제 줄이 있음) */
    _flyRow(uid, trackId, dur) {
      const b = this.bodyEl;
      let a = this._laneOf(uid);
      let cur;
      let to;
      if (a) {
        cur = this._laneAbs(a) - b.scrollTop;
        to = this._revealTo(a, cur, true);
      } else {
        /* 제 줄이 없는 항목: 그 트랙이 화면에 없을 때만 트랙 위쪽이 보이게 */
        const tr = this.tracks.find(t => t.id === trackId);
        if (!tr || !tr.el) return;
        cur = tr.el.offsetTop - b.scrollTop;
        const mid = b.clientHeight / 2;
        if ((cur >= 0 && cur <= b.clientHeight - Math.min(tr.height, 80)) || (cur < mid && cur + tr.height > mid)) return;
        a = { tr, row: -1 };
        to = this._reachable(tr, 0, 8);
      }
      if (Math.abs(to - cur) < 0.5) return;
      const anchored = this.anchorUid ? this._anchorLane() : null;
      if (anchored) {
        /* 닻이 있으면 닻의 자리를 같은 만큼 (같은 줄이면 곧 그 줄의 목표) — 앞서 하던 데려오기(스프링)는 비행이 이어받습니다 */
        const from = this._laneAbs(anchored) - b.scrollTop;
        this._anchorSpring = this._anchorTo = null;
        this._anchorOff = from;
        this._carry = { from, to: from + (to - cur), set: v => (this._anchorOff = v) };
        return;
      }
      const T = HT.motion.T;
      const held = (this._held = { tr: a.tr, row: a.row, off: cur, until: HT.motion.now() + dur + T.move + 120 });
      this._carry = { from: cur, to, set: v => (held.off = v) };
      this._anchorLoop(T.move + 80, held); // 앞선 재배치가 붙잡던 줄 대신 이 줄을 (높이가 흐르는 동안 매 프레임)
    }

    /** 비행 없이 세로로만 데려오기(가장자리 안내의 "여기로"): 트랙 tr의 줄 row(−1이면 트랙 위쪽)를 화면 위 to 자리로 — 되튐 없는 스프링 하나, 도착하면 done.
        여기서도 scrollTop은 _keepAnchor만 씁니다: 닻이 있으면 닻의 자리를 같은 만큼 옮기고, 없으면 그 줄을 붙잡아 데려옵니다 */
    _bringRow(tr, row, to, done = null) {
      this._stopCoast();
      const b = this.bodyEl;
      const lane = row >= 0 && tr.laneEls ? tr.laneEls[row] : null;
      const cur = tr.el.offsetTop + (lane ? lane.offsetTop : 0) - b.scrollTop;
      to = this._reachable(tr, lane ? tr.rowTop[row] : 0, to);
      this._carry = null;
      this._arrive = done;
      const anchored = this.anchorUid ? this._anchorLane() : null;
      if (anchored && this._anchorOff == null) this._anchorOff = this._laneAbs(anchored) - b.scrollTop;
      if (Math.abs(to - cur) < 0.5 || reduceMotion()) {
        if (anchored) {
          this._anchorSpring = this._anchorTo = null;
          this._anchorOff += to - cur;
        } else this._held = { tr, row: lane ? row : -1, off: to, until: HT.motion.now() + 80 };
        this._keepAnchor(anchored ? null : this._held);
        return this._arrived();
      }
      if (anchored) {
        this._anchorTo = this._anchorOff + (to - cur); // 움직이던 중이면 지금 값·지금 속도에서 새 목표로 이어 갑니다 (_anchorLoop)
        return this._anchorLoop();
      }
      const T = HT.motion.T;
      const held = (this._held = { tr, row: lane ? row : -1, off: cur, to, until: HT.motion.now() + T.move + 80 });
      this._anchorLoop(T.move + 80, held);
    }

    /** 줄 높이가 흐르는 동안(접힘·펼침 전환 — 길이는 --t-move) 닻을 매 프레임 붙잡습니다 */
    _anchorLoop(ms = HT.motion.T.move + 60, auto = null) {
      cancelAnimationFrame(this._anchorRaf);
      this._loopOn = true; // 붙잡는 동안 (스크롤 듣개: 이 사이 흐르는 높이에 브라우저가 깎은 스크롤은 손으로 옮긴 것이 아님)
      const t0 = HT.motion.now();
      const step = () => {
        if (this._anchorTo != null && this._anchorOff != null) {
          /* 데려오기의 출발은 여기(첫 프레임)에서 — 지금 값·지금 속도에서 새 목표로 */
          const sp = this._anchorSpring || (this._anchorSpring = this._newAnchorSpring(this._anchorOff));
          sp.set(this._anchorTo, null, this._anchorClock());
          this._anchorTo = null;
        }
        if (auto && auto.to != null) {
          (auto.spring || (auto.spring = this._newAnchorSpring(auto.off))).set(auto.to, null, this._anchorClock());
          auto.to = null;
        }
        this._keepAnchor(auto);
        if (HT.motion.now() - t0 < ms || this._anchorSpring || (auto && auto.spring)) return (this._anchorRaf = requestAnimationFrame(step)); // 스프링이 멈출 때까지
        this._loopOn = false;
        /* 다 흘렀을 때 닻 줄이 스크롤 끝에 걸려 제자리를 못 지켰으면(접혀서 문서가 짧아짐) 실제로 닿은 자리가 새 기준 — 나중에 위쪽이 펴질 때 묵은 자리로 슬금슬금 되돌아가지 않게 */
        const a = this.anchorUid && !this._carry && this._anchorOff != null && !this._handHeld() ? this._anchorLane() : null;
        if (a) this._anchorOff = this._laneAbs(a) - this.bodyEl.scrollTop;
      };
      this._anchorRaf = requestAnimationFrame(step);
    }

    /** 닻 스프링의 시계: HT.motion.now()를 따라가되 한 프레임에 34ms까지만 나아갑니다 — 그리기가 밀려 프레임이 길어져도 덜컥 뛰지 않고 이어서 움직입니다 */
    _anchorClock() {
      const now = HT.motion.now();
      this._anchorT = (this._anchorT || 0) + HT.clamp(now - (this._anchorAt == null ? now : this._anchorAt), 0, 34);
      this._anchorAt = now;
      return this._anchorT;
    }

    /** 닻의 기준을 지금 화면의 그 자리로 (데려오던 중이면 멈춤) — 누르는 순간 · 끌어 옮긴 뒤 · 사용자가 직접 스크롤했을 때 */
    _anchorRebase() {
      const a = this.anchorUid ? this._anchorLane() : null;
      this._anchorSpring = this._anchorTo = this._arrive = null;
      this._anchorOff = a ? this._laneAbs(a) - this.bodyEl.scrollTop : null;
    }

    /** 칸 기간 조명 — 칸(지도자 · 내각 · 연호 · 도읍 …) 하나와 그 기간을 띠 안에서 밝힙니다 (null이면 끔).
        spot = { uid(정권), cell('leader:3' — 진하게 할 칸, 없어도 됨), start, end } 하나 또는 그 배열(여러 띠 · 여러 기간 — 왕조가 다스린 나라들,
        두 정권을 섬긴 인물처럼). 그릴 때는 띠마다 제 것만 고릅니다(_spotsOf) */
    setSpotlight(spot) {
      this.spots = (Array.isArray(spot) ? spot : [spot]).filter(s => s && s.uid);
      this.spot = this.spots[0] || null;
      this._sameSync(); // 고른 칸의 같은 사람 테 (건의 8의 6-나)
      this.render();
    }

    /* ---------- 같은 사람의 칸 (건의 8의 6-나 — 감독 선택 2026-10-13) ----------
       지도자(사람을 적은 내각) 칸에 올리거나 고르면(조명된 칸) 같은 사람의 모든 칸 — 다른 나라 · 같은 나라 복위 칸 — 에 먹 1.5px 테(.is-same · 바탕은 그대로).
       올린 · 고른 그 칸 자신도 같은 테. 같은 사람의 자리가 없는 칸은 그대로. 사람 자리는 뷰어가 셈(opts.samePerson(uid, ref) → [{ uid, ref }]).
       고른 칸(조명)에서 온 짝 칸에는 .is-same-sel도 — 그 칸이 든 띠는 고른 띠처럼 흐리지 않음(강조 밖 .2 · 고름 .58에서 빼서 1 · 띠 안의 다른 칸은 .45 · 짝 칸은 1 — css/common.css).
       올리기만 할 때는 원래 흐림이 없으니 테만. 화면 상태라 그림 내보내기(toSVG)에는 넣지 않음 */
    _sameOf(uid, ref) {
      const f = this.opts.samePerson;
      const list = f && uid && /^(leader|cabinet):\d+$/.test(ref || '') ? f(uid, ref) || [] : [];
      return list.length >= 2 ? list.map(q => `${q.uid}|${q.ref}`) : [];
    }
    _sameSync() {
      const sel = new Set();
      for (const s of this.spots || []) for (const k of this._sameOf(s.uid, s.cell)) sel.add(k);
      const keys = new Set([...(this._sameHot || []), ...sel]);
      this._sameKeys = keys.size ? keys : null;
      this._sameSelKeys = sel.size ? sel : null;
      this._sameSelUids = sel.size ? new Set([...sel].map(k => k.slice(0, k.lastIndexOf('|')))) : null; // 짝 칸이 든 나라 — 책갈피 탭도 흐리지 않음
    }
    _isSame(uid, ref) {
      return !!this._sameKeys && this._sameKeys.has(`${uid}|${ref}`);
    }
    _isSameSel(uid, ref) {
      return !!this._sameSelKeys && this._sameSelKeys.has(`${uid}|${ref}`);
    }
    /** 올림: hit = [띠의 정권 uid, 칸 'leader:3'] | null — 그리기를 다시 하지 않고 테만 옮김 (다음 그리기도 같은 답 — _cells가 _isSame을 봄) */
    _sameHover(hit) {
      const key = hit ? hit.join('|') : '';
      if (key === (this._sameHotKey || '')) return;
      this._sameHotKey = key;
      this._sameHot = hit ? this._sameOf(hit[0], hit[1]) : null;
      this._sameSync();
      this.root.querySelectorAll('.tl-band .tl-cell.is-same').forEach(el => {
        const b = el.closest('.tl-band');
        if (!this._isSame(b && b.dataset.uid, el.dataset.cell)) el.classList.remove('is-same');
      });
      for (const k of this._sameKeys || []) {
        const at = k.lastIndexOf('|');
        this.root.querySelectorAll(`.tl-band[data-uid="${CSS.escape(k.slice(0, at))}"] .tl-cell[data-cell="${CSS.escape(k.slice(at + 1))}"]`).forEach(el => el.classList.add('is-same'));
      }
    }

    /** 가문 강조 · 가문 조명 (D1 결정 7 A — 확정 설계 5-3). setHouse(ids | id | null, { spans, dim } = {})
        ids — 가문 id 하나 또는 목록(본가를 누르면 아래 파까지 — HT.houseUnder · 성씨를 누르면 그 성의 가문 모두): 그 가문들의 지도자 · 내각 · 왕조 칸
          (과 인물 막대 · 가문 줄)을 진하게(is-house).
        spans — 조명 구간 [{ uid(정권), start, end }](HT.houseSpans): 그 띠(숨은 소속이면 보이는 상위 띠)마다 칸 조명과 같은 칠(.tl-spot 22% · 추정 빗금 위)과
          맨 위 날짜 칸 아래 괄호(메아리 괄호와 같은 요소 — 겹치거나 맞닿으면 하나로). 없으면 칠 · 괄호 없이 진하게만(옛 꼴 setHouse(id) 그대로).
        dim — 참이면 조명이 걸린 띠 안에서 다른 가문의 지도자 칸을 .55로 (다른 나라 띠는 흐리지 않음).
        null(또는 빈 목록)이면 모두 끔 — 끈 뒤 화면은 켜기 전 화면과 같습니다. 같은 값으로 다시 부르면 아무것도 하지 않음 */
    setHouse(ids, { spans = null, dim = false } = {}) {
      const list = [...new Set((Array.isArray(ids) ? ids : [ids]).filter(v => v != null && v !== '').map(String))];
      const hs = list.length && Array.isArray(spans) ? spans.filter(s => s && s.uid && isFinite(s.start) && isFinite(s.end) && s.end >= s.start).map(s => ({ uid: s.uid, start: Number(s.start), end: Number(s.end) })) : [];
      const key = list.length ? JSON.stringify([list, hs.map(s => [s.uid, s.start, s.end]), !!dim]) : '';
      if (key === (this._houseKey || '')) return;
      this._houseKey = key;
      this.house = list[0] || null;
      this.houses = list.length ? new Set(list) : null;
      this.houseSpans = hs.length ? hs : null;
      this.houseDim = !!(dim && hs.length);
      this.render();
    }

    /** 그 가문(id)이 지금 진하게 할 가문인가 (setHouse의 ids) */
    _isHouse(id) {
      return !!id && !!this.houses && this.houses.has(id);
    }

    /** 맨 위 날짜 칸의 괄호 구간 [[시작, 끝]] — 조명 메아리 기간(_echoSpans)과 가문 조명 구간(setHouse의 spans)을 겹치거나 맞닿으면 하나로 (HT.echoSpans) */
    _brkSpans() {
      const echo = this._echoSpans();
      if (!this.houseSpans) return echo;
      return HT.echoSpans(echo.map(([start, end]) => ({ start, end })).concat(this.houseSpans));
    }

    /** 이 띠(정권)에 걸린 조명들. band(조명 → 그것이 켜질 띠의 uid)를 주면 그것으로 고릅니다 — 상위 띠 아래 숨은 소속의 조명은 보이는 상위 띠의 것 */
    _spotsOf(uid, band) {
      if (!this.spots.length) return this.spots; // 조명이 없을 때(거의 늘)는 빈 목록 그대로
      return this.spots.filter(s => (band ? band.get(s) : s.uid) === uid);
    }

    /** 흐린 띠 안의 조명 구간(has-lit) — 띠마다 나타남 · 옮김 · 물러남을 기억합니다. cols = 이번에 흐리지 않을 해 구간(없으면 null).
        돌려주는 것 { cols(흐리지 않을 구간 — 칸의 밝기도 이것), from · to(옮기는 동안의 옛 구간 · 새 구간 — 가림 판을 이 둘로 나눔, 옮기지 않으면 null), cls }.
        나타날 때: 불투명도는 그 자리에서 1로 바꾸고 같은 밝기의 가림(바깥 --bo · 조명 구간 --la = --bo)에서 시작해 조명 구간만 --t-in에 걸쳐 1로.
        옮길 때(메아리를 켠 채 다른 칸으로 — 구간이 바뀜, lit-sw): 두 구간에 다 드는 곳은 1 그대로, 새 구간에만 드는 곳(--ln)은 지금 밝기에서 --t-in에 1로,
        옛 구간에만 드는 곳(--lo)은 1에서 그 띠의 흐림으로 --t-out — 다 가라앉은 뒤에 새 구간 하나로. 옮기는 도중에 옛 구간으로 돌아가면(▶ 뒤 곧바로 ◀) 가림 판은 그대로 두고
        두 변수의 목표만 뒤집어(lit-back) 지금 밝기에서 되돌아가고, 다른 구간으로 또 옮기면 이번 옮김이 가라앉은 뒤에 그때의 구간으로 이어서 옮깁니다
        (한 번에 한 옮김 — 가림 판의 변수가 넷뿐이라 셋째 구간을 겹치면 튐).
        물러날 때(메아리를 끔 · 창을 닫음): 조명 구간을 한동안 남겨(lit-out) 그 띠가 될 밝기(--bt)로 --t-out에 옅어지고(옮기는 도중이면 옛 구간 · 새 구간 모두),
        흐림이 바뀌면 바깥도 띠의 불투명도와 같은 .3초로 따라간 뒤(--bo), 다 가라앉은 한 번(lit-done — 불투명도 전환 없이)에 보통 띠로 — 밝기가 튀는 프레임이 없습니다 */
    _litState(uid, track, cols) {
      const m = this._lit || (this._lit = new Map());
      (this._litSeen || (this._litSeen = new Set())).add(uid);
      const st = m.get(uid);
      const now = HT.motion.now();
      const settle = Math.max(HT.motion.T.in, HT.motion.T.out, 300) + 40; // 조명 구간의 나타남(--t-in) · 물러남(--t-out)과 띠의 불투명도 전환(.3초 — css .tl-band) 가운데 긴 쪽
      const sw = s => ((s.shownSw = true), { cols: s.cols, from: s.from, to: s.to, cls: ` has-lit lit-sw${s.back ? ' lit-back' : ''}${s.out ? ' lit-out' : ''}` });
      const plain = (s, cls) => ((s.shownSw = false), { cols: s.cols, from: null, to: null, cls });
      const start = s => {
        s.sw = now + settle;
        this._litWake(s.sw, now);
      };
      if (st && st.sw && now >= st.sw && !st.out) Object.assign(st, { sw: 0, from: null, to: null, back: false }); // 옮김이 가라앉음 — 목표 구간 하나로 (옅어지던 곳은 이미 바깥과 같은 밝기, 밝아지던 곳은 이미 1)
      if (cols) {
        if (!st) {
          const s = { cols, out: 0, sw: 0, from: null, to: null, back: false, track, shownSw: false };
          m.set(uid, s);
          return plain(s, ' has-lit');
        }
        if (st.sw) {
          /* 옮기는 중(물러나던 참이면 다시 나타남 — 목표 쪽은 지금 밝기에서 1로, 다른 쪽은 그대로 옅어짐):
             옛 구간 · 새 구간으로 돌아가면 목표만 뒤집고, 셋째 구간이면 이 옮김이 가라앉은 뒤에 */
          const back = litSame(cols, st.from) ? true : litSame(cols, st.to) ? false : st.back;
          if (st.out || back !== st.back) {
            Object.assign(st, { out: 0, back, cols: back ? st.from : st.to });
            start(st);
          }
          return sw(st);
        }
        if (litSame(st.cols, cols)) {
          st.out = 0;
          st.cols = cols;
          return plain(st, ' has-lit');
        }
        /* 막 가라앉은 옮김의 lit-sw가 아직 붙어 있으면 한 프레임은 보통 has-lit로(보이는 밝기는 같음) — --lo · --ln이 제자리로 돌아간 뒤에 다음 옮김을 시작해야 전환이 걸림 */
        if (st.shownSw) {
          this._litFrame();
          return plain(st, ' has-lit');
        }
        /* 구간이 바뀜(다른 칸으로 · 물러나던 참에 다른 구간으로 다시): 옛 구간은 지금 밝기에서 옅어지고 새 구간은 지금 밝기에서 밝아짐 */
        Object.assign(st, { from: st.cols, to: cols, cols, back: false, out: 0 });
        start(st);
        return sw(st);
      }
      if (!st) return { cols: null, from: null, to: null, cls: '' };
      if (!st.out) {
        st.out = now + settle;
        this._litWake(st.out, now);
      }
      if (now < st.out) return st.to ? sw(st) : plain(st, ' has-lit lit-out');
      m.delete(uid);
      this._litFrame(); // lit-done은 한 번 그려진 뒤 떼어 냄
      return { cols: null, from: null, to: null, cls: ' lit-done' };
    }

    /** 한 프레임이 그려진 뒤 다시 그리기 (lit-done 떼기 · 가라앉은 옮김 뒤의 다음 옮김) */
    _litFrame() {
      if (!this._litDoneRaf) this._litDoneRaf = requestAnimationFrame(() => requestAnimationFrame(() => ((this._litDoneRaf = 0), this.render())));
    }

    /** 흐리지 않는 구간의 나타남 · 옮김 · 물러남이 가라앉을 때(at — 가상 시각) 한 번 다시 그리기 (가장 늦은 것 하나만 걸어 둠) */
    _litWake(at, now) {
      if (this._litT && this._litAt >= at) return;
      clearTimeout(this._litT);
      this._litAt = at;
      this._litT = HT.motion.later(at - now + 16, () => {
        this._litT = 0;
        this.render();
      });
    }

    _litPrune(track) {
      if (!this._lit) return;
      for (const [uid, st] of this._lit) if (st.track === track && !(this._litSeen && this._litSeen.has(uid))) this._lit.delete(uid);
      if (this._litSeen) this._litSeen.clear();
    }

    /** 칸 하나(띠 안쪽 좌표 l · 너비 w)가 흐리지 않는 조명 구간(_litCols)에 드는 모습 — 온전히 들면 lit-in, 걸치면 lit-part + 칸 안의 가림 판(--lp).
        그 구간의 칸은 제 조명의 띠(강조된 띠)의 칸과 같은 밝기(.55), 밖은 흐린 띠의 칸 그대로(.45 — 걸친 칸은 그 비율만큼 가림) */
    _litCls(l, w, flat = false) {
      const cols = this._litCols;
      if (!cols) return { cls: '', css: '' };
      const r = l + w;
      const ov = cols.filter(([a, b]) => b > l + 0.01 && a < r - 0.01);
      if (!ov.length) return { cls: '', css: '' };
      if (ov[0][0] <= l + 0.5 && ov[0][1] >= r - 0.5) return { cls: ' lit-in', css: '' };
      /* 이름이 조명 경계를 비킬 자리가 없는 칸(litShift의 litDim — 칸을 채운 앞글자 이름 …): 칸 전체(바탕 · 글자)를 흐린 쪽 밝기로 고르게 — 글자가 반만 밝게 갈리지 않게.
         조명 구간 안에서는 띠의 가림 판(--la)을 되돌려 흐린 쪽(--bo)이 되게 칸의 판(--lf)으로 줄임 (common.css lit-flat) */
      if (flat) {
        const dim = 'rgba(0,0,0,calc(var(--bo) * var(--lp-o, 1) / var(--la)))';
        const out = 'rgba(0,0,0,var(--lp-o, 1))';
        const fs = [];
        let fx = 0;
        for (const [a, b] of ov) {
          const A = Math.max(0, a - l);
          const B = Math.min(w, b - l);
          if (A > fx) fs.push(`${out} ${cx(fx)}px ${cx(A)}px`);
          fs.push(`${dim} ${cx(A)}px ${cx(B)}px`);
          fx = B;
        }
        if (fx < w) fs.push(`${out} ${cx(fx)}px`);
        return { cls: ' lit-flat', css: `;--lf:linear-gradient(to right, ${fs.join(', ')})` };
      }
      const o = 'rgba(0,0,0,var(--lp-o))';
      const stops = [];
      let x = 0;
      for (const [a, b] of ov) {
        const A = Math.max(0, a - l);
        const B = Math.min(w, b - l);
        if (A > x) stops.push(`${o} ${cx(x)}px ${cx(A)}px`);
        stops.push(`#000 ${cx(A)}px ${cx(B)}px`);
        x = B;
      }
      if (x < w) stops.push(`${o} ${cx(x)}px`);
      return { cls: ' lit-part', css: `;--lp:linear-gradient(to right, ${stops.join(', ')})` };
    }

    /** 그 칸('era:2')이 조명된 칸인가 — 띠 안의 칸과 맨 위 날짜 칸의 칸이 함께 씁니다 */
    _isSpot(uid, ref) {
      return this.spots.some(s => s.uid === uid && s.cell === ref);
    }

    /** 조명 메아리(설정 '같은 시기를 타국에도')의 기간들 — 겹치는 조명은 하나로 합쳐, 다른 띠와 맨 위 연도 줄이 같은 구간을 봅니다 (HT.echoSpans — 창의 '같은 시기 타국'과 같은 계산) */
    _echoSpans() {
      if (!this.show.spotEcho || !this.spots.length) return [];
      return HT.echoSpans(this.spots);
    }

    /** (공개) 정권마다 그 정권이 연표에 그려지는 띠 — HT.echoEvents의 bandOf가 읽는 표: Map(정권 uid → { band, start, end, order, drawn, hidden, name, color, track }).
        상위 띠 아래 숨은 소속은 그 상위 띠(hidden), 접힌 트랙 · 접힌 민족 줄은 folded(사건도 그려지지 않음), 띠가 없는 것(바탕 문화 · 기관)은 drawn이 거짓(칠이 없음).
        start · end = 그 띠가 있던 구간(칠이 잘리는 자리 — _drawTrack의 메아리와 같은 값), order = 연표 위에서 아래로의 차례(트랙 번호 + 줄) */
    echoBands() {
      const out = new Map();
      (this.tracks || []).forEach((tr, ti) => {
        const rows = (tr.rows || 0) + 2;
        for (const p of tr.periods) {
          let q = p;
          while (q && q._hidden) q = q._host;
          if (!q) q = p;
          const folded = !!tr.folded || !!q._folded || (q._row != null && !!tr.foldedRows && tr.foldedRows.has(q._row));
          const drawn = !folded && q._row != null && !q._under && !q._overlay;
          out.set(p.uid, { band: q.uid, start: bandStart(q), end: bandEnd(q), order: ti + ((q._row ?? rows - 2) + 1) / rows, drawn, folded, hidden: q !== p, name: q.name, color: q.color, track: tr.id });
        }
      });
      return out;
    }

    /** (공개) 트랙의 차례 (echoBands의 order와 같은 자 — 정권이 없는 사건의 묶음이 그 트랙의 맨 아래에) */
    trackOrder(id) {
      const i = (this.tracks || []).findIndex(t => t.id === id);
      return i < 0 ? (this.tracks || []).length : i;
    }

    setMarker(year) {
      this.marker = year == null ? null : Number(year);
      this.render();
    }

    setMeasureMode(on) {
      this.measureMode = !!on;
      if (!on) this.measure = null;
      this.bodyEl.classList.toggle('is-measuring', this.measureMode);
      this.render();
    }

    yearAtClientX(clientX) {
      const x = clientX - this.bodyEl.getBoundingClientRect().left - this.gutter;
      return this.view.start + (HT.clamp(x, 0, this.W) / this.W) * this.span();
    }

    span() {
      return this.view.end - this.view.start;
    }

    /** 보기 범위를 자료의 범위 안으로 (폭은 최소~최대, 가운데는 자료가 있는 곳) */
    _clampView(start, end) {
      const span = HT.clamp(end - start, MIN_SPAN, this._maxSpan());
      const center = HT.clamp((start + end) / 2, this.extent.min, this.extent.max);
      return { start: center - span / 2, end: center - span / 2 + span };
    }

    /** inset(멀리 갈 때 — setInset): true면 [start, end]를 창에 가려지지 않은 부분에 꼭 담고, 'center'면 폭은 그대로 둔 채 그 가운데만 가려지지 않은 부분의 가운데로.
        animate면 비행의 길이(ms)를 돌려줍니다 */
    setView(start, end, { animate = false, anchor = null, inset = false } = {}) {
      if (inset) [start, end] = this._insetView(start, end, inset === 'center');
      const to = this._clampView(start, end);
      if (animate) return this._animateTo(to.start, to.end, anchor);
      this._stopGlide();
      this.view = to;
      this.render(true);
    }

    /** 연표의 오른쪽을 가리는 창(상세 창)의 폭(px — 연표 오른쪽 끝에서 잰 것). 멀리 가기(focusOn · setView의 inset)가 가려지지 않은 부분의 가운데에 도착합니다. 가리는 것이 없으면 0 */
    setInset({ right = 0 } = {}) {
      this._insetR = Math.max(0, Number(right) || 0);
    }

    /** [s, e]가 가려지지 않은 부분에 꼭 담기는 보기 범위: 가린 폭만큼 오른쪽으로 더 넓게 잡습니다. keepSpan이면 폭은 그대로 두고 가운데만 옮깁니다.
        가린 폭이 연표의 절반을 넘으면(좁은 화면에서 창이 화면을 다 덮을 때) 평소대로 */
    _insetView(s, e, keepSpan = false) {
      const W = Math.max(60, this.bodyEl.clientWidth - this.gutter);
      const edge = this.root.getBoundingClientRect().right - this.bodyEl.getBoundingClientRect().left - this.bodyEl.clientWidth; // 연표 오른쪽 끝과 그림 영역 사이(세로 스크롤 막대)
      const r = (this._insetR || 0) - Math.max(0, edge);
      if (!(r > 0) || r > W / 2) return [s, e];
      if (!keepSpan) return [s, s + ((e - s) * W) / (W - r)];
      const d = ((e - s) * r) / (2 * W);
      return [s + d, e + d];
    }

    /** 확대 엔진 하나 — 휠 · 트랙패드 · 단추 · 키(확대와 화살표 이동)가 모두 이 길로: 목표 보기만 정하고 매 프레임 조금씩 따라갑니다(지수 감쇠, 시간 상수 tau ms — CHASE).
        연달아 굴리거나 눌러도 목표가 쌓일 뿐 끊기지 않고(도중에 엔진이 바뀌지 않음), 시작·끝을 함께 같은 비율로 쫓으므로 커서 아래 해는 제자리에 있습니다 */
    _glideTo(s, e, tau = CHASE.notch) {
      this._stopAnim();
      this._stopCoast(); // 관성으로 미끄러지던 중이면 그 자리에서 멈추고 거기서부터
      const span = HT.clamp(e - s, MIN_SPAN, this._maxSpan());
      const c = HT.clamp((s + e) / 2, this.extent.min, this.extent.max);
      const to = { start: c - span / 2, end: c + span / 2 };
      if (this._glide) {
        this._glide.to = to;
        this._glide.tau = tau;
        return;
      }
      this._beginJump();
      const g = (this._glide = { to, tau, t: HT.motion.now(), raf: 0 });
      const step = ts => {
        if (this._glide !== g) return;
        const now = HT.motion.now(ts); // 한 시계(HT.motion) — 느리게 보기에서는 시간도 같이 느려집니다
        /* 첫 프레임: 프레임의 시각(ts)은 그 프레임 안에서 먼저 처리된 입력의 시각(g.t)보다 이를 수 있습니다 — 흐른 시간이 음수면 목표에서 멀어지는 쪽으로 튀므로(시간 상수가 짧을수록 크게),
           첫 걸음은 적어도 반 프레임(8ms)만큼, 그 뒤로는 0 이상으로 */
        const dt = HT.clamp(now - g.t, g.moved ? 0 : 8, 64);
        g.moved = true;
        g.t = now;
        const a = 1 - Math.exp(-dt / g.tau);
        const v = this.view;
        let s2 = v.start + (g.to.start - v.start) * a;
        let e2 = v.end + (g.to.end - v.end) * a;
        const done = Math.abs(g.to.start - s2) + Math.abs(g.to.end - e2) < (g.to.end - g.to.start) * 3e-4;
        if (done) [s2, e2] = [g.to.start, g.to.end];
        this.view = { start: s2, end: e2 };
        this._draw();
        if (done) {
          this._glide = null;
          this._settleSoon();
          this._motionEnd();
        } else g.raf = requestAnimationFrame(step);
      };
      g.raf = requestAnimationFrame(step);
    }

    _stopGlide() {
      this._stopCoast();
      if (!this._glide) return;
      cancelAnimationFrame(this._glide.raf);
      this._glide = null;
    }

    /** 관성 — 끌다 놓으면 손의 속도(vx, vy — px/ms · releaseVelocity)를 이어받아 미끄러지다 멎습니다. 속도가 시간 상수 COAST.tau로 지수 감속하므로, 첫 프레임의 빠르기가 손의 빠르기 그대로이고
        거기서 줄어들기만 합니다(놓은 직후에 더 빨라지는 일이 없음). 가로(보기 범위)와 세로(스크롤)가 같은 시계·같은 상수로 함께 가서 함께 멎습니다.
        자리는 놓은 자리에서 닫힌 식으로 셉니다: 놓은 자리 + 갈 거리 × (1 − e^(−t/tau)) — 프레임이 밀려도 어긋남이 쌓이지 않습니다. 갈 거리는 속도 × tau, 길어도 화면 폭의 COAST.max배,
        자료의 끝·스크롤의 끝을 넘으면 거기까지만(끝에 부딪혀 뚝 멈추지 않고 끝을 향해 잦아듦). 멎는 것은 자리가 아니라 빠르기로 정합니다(COAST.rest) — 꼬리가 길게 기어가지 않게 — 그리고 멎은 그 프레임에 바로 정착(_settle).
        미끄러지는 동안도 "손에 잡힌 동안"입니다(_inMotion): 줄이 접히지 않고, 세부 효과는 조용하고, 세로 닻은 쉽니다(_handHeld). 누름·휠·키·다른 이동이 오면 그 자리에서 멈춥니다(_stopCoast).
        관성을 시작했으면 true (너무 느리게 놓았거나 · 갈 데가 없거나 · 동작 줄이기면 false — 부른 쪽이 관성 없는 놓기로 마무리) */
    _coastFrom(vx, vy) {
      const tau = COAST.tau;
      const v = Math.hypot(vx, vy) * 1000;
      if (!(v > COAST.min) || reduceMotion()) return false;
      const b = this.bodyEl;
      const far = Math.min(1, (this.W * COAST.max) / ((v / 1000) * tau));
      const from = Object.assign({}, this.view);
      const perPx = (from.end - from.start) / this.W;
      const to = this._clampView(from.start - vx * far * tau * perPx, from.end - vx * far * tau * perPx);
      const dYears = to.start - from.start;
      const top = b.scrollTop;
      const dTop = HT.clamp(top - vy * far * tau, 0, Math.max(0, b.scrollHeight - b.clientHeight)) - top;
      const v0 = (Math.hypot(dYears / perPx, dTop) / tau) * 1000; // 실제로 갈 거리로 다시 센 첫 빠르기(px/초) — 끝에 막혀 갈 데가 없으면 관성도 없습니다
      if (!(v0 > COAST.min)) return false;
      if (this._raf) {
        cancelAnimationFrame(this._raf); // 놓기 직전 손의 마지막 자리는 관성의 첫 프레임이 함께 그립니다 (한 프레임에 두 번 그리지 않게)
        this._raf = 0;
      }
      const c = (this._coast = { t: HT.motion.now(), T: 0, raf: 0, speed: () => v0 * Math.exp(-c.T / tau) });
      const step = ts => {
        if (this._coast !== c) return;
        const now = HT.motion.now(ts); // 한 시계(HT.motion) — 느리게 보기에서는 관성도 같이 느려집니다
        c.T += HT.clamp(now - c.t, 0, 64); // 프레임이 길게 밀려도 덜컥 뛰지 않게 (한 걸음은 64ms까지)
        c.t = now;
        const p = 1 - Math.exp(-c.T / tau);
        this.view = { start: from.start + dYears * p, end: from.end + dYears * p };
        if (dTop) b.scrollTop = top + dTop * p;
        if (this._raf) {
          cancelAnimationFrame(this._raf); // 세로로 옮겨 들어온 트랙이 부른 그리기(scroll → render)는 이 프레임의 그리기로 갈음합니다
          this._raf = 0;
        }
        if (c.speed() < COAST.rest) return this._coastEnd();
        this._draw();
        c.raf = requestAnimationFrame(step);
      };
      c.raf = requestAnimationFrame(step);
      return true;
    }

    /** 관성이 멎은 프레임: 기다림 없이 바로 정착 — 미뤄 둔 줄 접힘과 안내가 멎는 흐름 안에서 함께 시작합니다 (멀리 가기의 도착과 같음) */
    _coastEnd() {
      this._coast = null;
      this._rehold();
      if (!this._settle()) this._draw();
      this._motionEnd();
    }

    /** 관성을 그 자리에서 멈춥니다(누름 · 휠 · 키 · 다른 이동 · 다시 짓기). 멈춘 자리가 세로의 새 기준이고, 미뤄 둔 정착은 잠깐 뒤에(손이 또 올 수 있으니 — 누르고 있으면 뗄 때부터 셈).
        멈추던 순간의 빠르기(px/초)를 돌려줍니다 — 관성이 없었으면 0. 아직 빠를 때(COAST.grab) 누른 것은 고르려는 것이 아니라 멈추려는 누름입니다 (_bind의 finish) */
    _stopCoast() {
      const c = this._coast;
      if (!c) return 0;
      cancelAnimationFrame(c.raf);
      this._coast = null;
      this._rehold();
      this._settleSoon();
      return c.speed();
    }

    /** 손(과 관성)이 놓은 자리가 세로의 새 기준: 닻(고른 줄)은 지금 자리로 다시 잡고, 잠시 붙잡아 두던 줄(접기·펼치기 · 멀리 가기)은 놓고,
        끄는 동안 펴진 줄의 높이가 아직 흐르는 중일 수 있으니 놓은 자리의 줄을 새로 붙잡습니다 — 끌기 전의 자리로 되돌아가지 않게 */
    _rehold() {
      if (this.anchorUid) this._anchorRebase();
      this._held = null;
      this._anchorLoop(HT.motion.T.move + 60, this.anchorUid && this._anchorLane() ? null : this._autoAnchor());
    }

    /** 비행을 그 자리에서 멈춥니다(누름 · 휠 · 새 이동). 실려 가던 세로 이동도 함께 멈추고(붙잡은 줄은 지금 자리가 기준), 도착 표시는 버리고,
        비행이 시작하며 적어 둔 "이동 전 화면"(_jump)은 정착 때 정리되게 합니다 — 멈춘 채 남아 다음 안내를 묵은 화면과 견주지 않게 */
    _stopAnim() {
      cancelAnimationFrame(this._anim);
      this._carry = null;
      if (!this._animating) return;
      this._animating = false;
      this._arrive = null;
      this._settleSoon();
    }

    _maxSpan() {
      return Math.max(200, (this.extent.max - this.extent.min) * 1.6);
    }

    /** px(연표 안쪽 x)에 있는 해를 그 자리에 둔 채 확대·축소합니다. smooth면 확대 엔진(_glideTo · tau)으로 — 쫓아가던 목표에서 이어서 셈하므로, 연달아 굴리거나 눌러도 그만큼이 정확히 쌓입니다.
        focus = 커서 아래 정권 띠: 띠를 가운데로 끌어당기지 않습니다(커서 아래 해가 제자리). 다만 지금 온전히 보이는 띠가 이 확대 때문에 화면 가장자리에서 잘리게 되면,
        잘리지 않을 만큼만 붙잡습니다 — 가장자리 여유는 지금 여유 · 화면 폭의 4% · 남는 자리의 절반 가운데 가장 작은 쪽(안쪽으로 더 데려오지는 않고, 띠가 화면을 꽉 채울 때까지 붙잡다가 놓습니다).
        띠가 새 화면보다 길거나 이미 잘려 있으면 커서 자리 기준 그대로 (긴 왕조 안에서 한 시기로 파고들 때) */
    zoomAt(factor, px = this.W / 2, { animate = false, focus = null, smooth = false, tau = CHASE.notch } = {}) {
      const base = smooth && this._glide ? this._glide.to : this.view; // 쫓아가는 목표에서 이어서
      const span = base.end - base.start;
      const x = HT.clamp(px, 0, this.W);
      const year = base.start + (x / this.W) * span;
      const next = HT.clamp(span * factor, MIN_SPAN, this._maxSpan());
      let s = year - (x / this.W) * next;
      const s0 = s;
      if (focus && next < span) {
        const a = bandStart(focus);
        const b = bandEnd(focus);
        const room = next - (b - a); // 새 화면에서 띠 양옆에 남는 자리
        if (room >= 0 && a >= base.start && b <= base.end) {
          const padL = Math.min(next * 0.04, ((a - base.start) * next) / span, room / 2);
          const padR = Math.min(next * 0.04, ((base.end - b) * next) / span, room / 2);
          s = HT.clamp(s, b + padR - next, a - padL);
        }
      }
      if (smooth && !reduceMotion()) return this._glideTo(s, s + next, tau);
      if (smooth) this._beginJump(); // 움직임 줄이기의 휠 · 키 · 단추: 곧바로 옮기되, 미끄러짐이 멎은 것처럼 정착을 예약 (자동 조감 · 미뤄 둔 줄 접힘 · 밀려난 것 알림 — _settle)
      this.setView(s, s + next, { animate, anchor: s === s0 ? { year, f: x / this.W } : null });
      if (smooth) this._settleSoon();
    }

    /** 휠 확대의 기준 띠: 커서가 있는 줄에서 커서 해를 품은 정권 띠(겹치면 가장 짧은 것) */
    _bandAt(target, year) {
      const trEl = target && target.closest ? target.closest('.tl-track') : null;
      const rowEl = target && target.closest ? target.closest('[data-row]') : null;
      if (!trEl || !rowEl || trEl.classList.contains('is-folded')) return null;
      const tr = this.tracks.find(t => t.id === trEl.dataset.track);
      const row = Number(rowEl.dataset.row);
      if (!tr || !tr.rowPeriods || !tr.rowPeriods[row] || (tr.foldedRows && tr.foldedRows.has(row))) return null;
      let best = null;
      for (const p of tr.rowPeriods[row]) {
        if (p._hidden || p._overlay || !(bandStart(p) <= year && year <= bandEnd(p))) continue;
        if (!best || bandEnd(p) - bandStart(p) < bandEnd(best) - bandStart(best)) best = p;
      }
      return best;
    }

    /** 단추·키보드 확대: 커서가 연표 위에 있으면 커서 자리를, 아니면 화면 가운데를 기준으로. 휠과 같은 엔진 — 연달아 누르면 목표가 쌓여, 두 번 누르면 정확히 두 번만큼 */
    zoom(factor) {
      return this.zoomAt(factor, this._hoverX != null ? this._hoverX : this.W / 2, { smooth: true });
    }

    _zoomCenter(factor) {
      const span = this.span() * factor;
      const c = (this.view.start + this.view.end) / 2;
      this.setView(c - span / 2, c + span / 2, { animate: true, anchor: { year: c, f: 0.5 } });
    }

    /** 옆으로 years만큼. smooth면 확대 엔진으로 미끄러져 갑니다(화살표 키 · 휠의 가로 이동) — 쫓아가던 목표에서 이어서 셈하므로 도중의 확대를 끊지 않고, 연달아 누르면 그만큼 쌓입니다 */
    panBy(years, { smooth = false, tau = CHASE.notch } = {}) {
      if (smooth && !reduceMotion()) {
        const base = this._glide ? this._glide.to : this.view;
        return this._glideTo(base.start + years, base.end + years, tau);
      }
      if (smooth) this._beginJump(); // 움직임 줄이기의 화살표 키 · 휠의 가로 이동: 곧바로 옮기고 정착을 예약 (확대와 같게)
      this.setView(this.view.start + years, this.view.end + years);
      if (smooth) this._settleSoon();
    }

    fitAll(animate = true) {
      const pad = (this.extent.max - this.extent.min) * 0.03 + 5;
      this.setView(this.extent.min - pad, this.extent.max + pad, { animate });
    }

    focusOn(item) {
      const len = item.endY - item.start;
      /* 날짜까지 적은 항목은 그 정밀도에 맞춰 더 가까이 (해 → 30~160년, 달 → 2~5년, 날 → 두 달~반년, 시각 → 사흘) */
      const at = HT.atOf(item, 'start');
      const prec = at ? (HT.cal.parse(at) || {}).prec : 'y';
      const [lo, hi] = prec === 'm' ? [2, 5] : prec === 'd' ? [60 / 365.25, 0.5] : prec === 'h' || prec === 'min' ? [3 / 365.25, 10 / 365.25] : [30, 160];
      const span = len > 0 ? Math.max(len * 2.2, Math.min(lo, 30)) : Math.min(Math.max(this.span(), lo), hi);
      const c = len > 0 ? item.start + len / 2 : item.itemKind === 'event' ? this._placeAt(item) : item.start; // 날짜를 모르는 점 사건은 놓인 자리(그 구간 가운데)로
      // 왕조는 제 줄이 없으니, 다스린 나라(첫 번째) 띠를 기준으로 펼치고 그 트랙으로 갑니다
      const ruled = item.polityKind === 'dynasty' ? ((item.hosts || [])[0] || {}).host || null : null;
      // 인물도 제 줄이 없습니다 — 섬긴 정권(첫 번째)을 기준으로 접힌 민족 · 숨은 소속을 펴고, 그 정권의 트랙(다른 트랙일 수 있음)으로 갑니다
      const served = item.kind === 'figure' && item.polityUid ? this._data.periods.find(p => p.uid === item.polityUid) || null : null;
      const own = ruled || served || (item.kind === 'period' ? item : null);
      const trackId = this._boardHas(own ? own.uid : item.polityUid) ? BOARD_ID : ruled ? ruled.track : served ? served.track : item.track; // 집합 보기로 옮겨 간 나라(와 그 사건)는 판 트랙에서
      /* 접힌 트랙 · 접힌 민족(어느 단계든) · 숨은 소속 정권 안에 있으면 펼쳐서 보이게 — 바꿀 것을 모아 다시 배치는 한 번만 합니다 */
      let relaid = false;
      if (this._boardTr && this._foldedNow(trackId)) {
        if (trackId === BOARD_ID) this._boardFolded = false; // 집합 보기를 켠 동안은 판의 접힘만 풂 (접힘 기억은 그대로)
        else this._boardOpen.add(trackId);
        this._pressHold = { trackId, row: -1 };
        relaid = true;
      } else if (!this._boardTr && this.folded.has(trackId)) {
        this.folded.delete(trackId);
        if (this.opts.onFold) this.opts.onFold([...this.folded]);
        this._pressHold = { trackId, row: -1 }; // 펴는 트랙의 위쪽이 제자리 (toggleFold와 같게)
        relaid = true;
      }
      const period = ruled || (item.kind === 'period' ? item : item.polityUid ? this._data.periods.find(p => p.uid === item.polityUid) : null);
      if (period) {
        let changed = false;
        /* 켠 대범위로 모인 정권(_layoutTrack이 적어 둔 _scope)은 옛 상위 아래 · 제 민족 묶음이 아니라 대범위 가지에 있습니다 —
           옛 상위를 펼치면 같은 정권이 두 번 놓이므로(빈 줄 하나 + 가지), 상위 사슬은 가지를 떠난 곳에서 멈추고 민족 접힘 대신 그 가지의 접힘만 풉니다 */
        const gathered = q => !!(q._scope && this.scopeOn(q._scope));
        const ups = [];
        let cur = period;
        let host = cur.singleHost && cur.partOfUid ? this._data.periods.find(p => p.uid === cur.partOfUid) : null;
        while (host && !(gathered(cur) && host._scope !== cur._scope) && ups.length < 50) {
          ups.push(host);
          cur = host;
          host = cur.singleHost && cur.partOfUid ? this._data.periods.find(p => p.uid === cur.partOfUid) : null;
        }
        if (gathered(cur)) {
          if (this.foldedPeoples.delete(`${trackId}|__scope:${cur._scope.uid}`)) changed = true;
        } else
          for (const pe of period.peoplePath || []) {
            const key = `${trackId}|${pe.id}`;
            if (this.foldedPeoples.has(key)) {
              this.foldedPeoples.delete(key);
              changed = true;
            }
          }
        for (const s of period.scopes || []) if (this.foldedPeoples.delete(`${trackId}|__scope:${s.uid}`)) changed = true; // 모인 대범위 가지를 접어 두었으면 그것도 펴서 (7-2)
        for (const h of ups)
          if (!this.expandedHosts.has(h.uid)) {
            this.expandedHosts.add(h.uid);
            changed = true;
          }
        if (changed) {
          if (this.opts.onFoldPeople) this.opts.onFoldPeople([...this.foldedPeoples]);
          if (this.opts.onExpand) this.opts.onExpand([...this.expandedHosts]);
          relaid = true;
        }
      }
      if (item.kind === 'scope' && this.foldedPeoples.delete(`${trackId}|__scope:${item.uid}`)) {
        if (this.opts.onFoldPeople) this.opts.onFoldPeople([...this.foldedPeoples]); // 대범위 자신으로 갈 때도 접어 둔 가지는 펴서
        relaid = true;
      }
      if (relaid) this.relayout();
      /* 가로: 창이 가리지 않은 부분의 가운데로 날아갑니다(setInset). 세로: 그 줄을 화면 가운데로 — 가운데 맞춤은 이렇게 멀리 갈 때만 하고,
         가로 비행과 같은 박자에 실어 대각선 한 번에 도착합니다(_flyRow). 브라우저의 부드러운 자동 스크롤은 쓰지 않습니다 — 우리 시계로 늦출 수도, 도중에 이어받을 수도 없습니다 */
      const dur = this.setView(c - span / 2, c + span / 2, { animate: true, inset: len > 0 ? true : 'center' }); // 기간이 있으면 가려지지 않은 부분에 꼭 담고, 한 시점이면 지금 폭 그대로 가운데만 (누를 때마다 넓어지지 않게)
      this._flyRow(ruled ? ruled.uid : item.uid, trackId, dur);
      this._arrive = () => this._ringAt(ruled ? ruled.uid : item.uid); // 도착한 뒤에 고리 한 번 (도중에 눌러 멈추면 하지 않음)
    }

    render(viewOnly = false) {
      if (!this.axisEl.firstChild) return; // 자료를 아직 받지 못한 처음(js/viewer.js가 실어 둔 글꼴이 열리기를 기다리는 동안)에는 그릴 틀이 없습니다 — 첫 setData가 날짜 칸을 짓고 그립니다
      if (!viewOnly) this._paintRevision = (this._paintRevision || 0) + 1;
      if (!this._raf)
        this._raf = requestAnimationFrame(() => {
          this._raf = 0;
          this._draw();
        });
    }

    titleFor(e, trackId) {
      const views = e.perspectives || [];
      if (this.lens && this.lens !== 'local') {
        const v = views.find(x => x.track === this.lens && x.title);
        if (v) return v.title;
      } else if (this.lens === 'local') {
        const v = views.find(x => x.track === trackId && x.title);
        if (v) return v.title;
      }
      return e.title;
    }

    /* ---------- 배치 ---------- */
    _layoutTrack(tr) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      tr.folded = this._foldedNow(tr.id) || !!tr._sphereHidden; // 집합 보기를 켠 동안은 판의 접힘 (_foldedNow) · 접힌 문화권의 트랙은 접힌 셈(서고 3단 — 높이는 0)
      const byStart = (a, b) => bandStart(a) - bandStart(b) || bandEnd(b) - bandEnd(a);
      const inTrack = new Map(tr.periods.map(p => [p.uid, p]));

      /* 0) 소속(연맹 구성국·종속국·조직체): 상위 정권이 펼쳐져 있을 때만 보입니다 */
      for (const p of tr.periods) {
        // 상위 정권이 하나뿐(기간 없음)일 때만 그 띠 아래 접힙니다. 차례로 예속된 정권(여러 개·기간 있음)은 제 줄에 예속 띠로 보입니다.
        // 기관(통감부·조계지 등)은 접히지 않고 얹히는 정권 띠의 아래쪽에 그려집니다
        p._overlay = p.polityKind === 'overlay' && p.hosts && p.hosts.some(h => inTrack.has(h.host.uid));
        p._host = !p._overlay && p.singleHost && p.partOfUid ? inTrack.get(p.partOfUid) || null : null;
        p._member = !!p._host;
        p._row = null;
        p._folded = false;
        p._seamL = p._seamR = null; // 같은 줄에서 곧바로 이어지는 승계 쌍 (chainRows가 다시 적음)
      }
      /* 대범위 (7-2): 켠 대범위의 구성 정권은 다른 정권 띠 아래에 접혀 있던 자리를 떠나 대범위 가지로 갑니다 (같은 대범위에 든 상위를 따라가는 것은 그대로) */
      const scopeOf = this._scopeClaims(tr, inTrack);
      for (const p of tr.periods) {
        p._scope = scopeOf.get(p.uid) || null;
        if (p._scope && p._host && scopeOf.get(p._host.uid) !== p._scope) {
          p._host = null;
          p._member = false;
        }
      }
      /* 소속이 돌고 도는 자료(가 → 다 → 나 → 가 — 모델은 두 나라가 서로를 가리키는 고리만 끊음)도 그릴 수 있게: _host를 따라가다 제 길로 돌아오면
         고리의 마지막 고리를 끊습니다 (아래의 'while (h && h._hidden) h = h._host'들이 끝없이 돌지 않게) */
      {
        const done = new Set();
        for (const p of tr.periods) {
          const path = [];
          let q = p;
          while (q && !done.has(q) && !path.includes(q)) {
            path.push(q);
            q = q._host;
          }
          if (q && path.includes(q)) {
            const last = path[path.length - 1];
            last._host = null;
            last._member = false;
          }
          for (const x of path) done.add(x);
        }
      }
      const hiddenMemo = new Map();
      const isHidden = p => {
        if (!p._host) return false;
        if (hiddenMemo.has(p.uid)) return hiddenMemo.get(p.uid);
        hiddenMemo.set(p.uid, true); // 순환 방지
        // 단체의 띠(리메이크 조각 ④ — core.js buildModel opts.groupBands)는 소속 펼치기가 아니라 단체 펼치기(expandedGroups)로 섭니다
        const open = p.groupUid ? !!(this.expandedGroups && this.expandedGroups.has(p._host.uid)) : this.expandedHosts.has(p._host.uid);
        const h = !open || isHidden(p._host);
        hiddenMemo.set(p.uid, h);
        return h;
      };
      for (const p of tr.periods) p._hidden = isHidden(p);

      /* 0-1) 바탕 문화: 승계국(국가)이 있는 문화는 제 줄을 갖지 않고 승계국 줄 밑에 깔립니다.
         문화 → 문화 → 국가처럼 이어진 경우도 끝에 국가가 있으면 모두 바탕이 됩니다 */
      for (const p of tr.periods) {
        p._under = false;
        p._underRows = [];
      }
      const succIn = p => (p.successors || []).map(e => inTrack.get(e.to.uid)).filter(s => s && !s._hidden);
      let changed = true;
      while (changed) {
        changed = false;
        for (const p of tr.periods) {
          if (p._under || p.polityKind !== 'culture' || p._hidden) continue;
          if (succIn(p).some(s => s.polityKind !== 'culture' || s._under)) {
            p._under = true;
            changed = true;
          }
        }
      }

      /* 1) 민족 트리 (대명제 → … → 민족). 정권은 어느 단계에든 붙을 수 있습니다 */
      const mkNode = (pe, depth) => ({ id: pe.id, name: pe.name, color: pe.color || tr.color, order: pe.order ?? 1e9, depth, children: [], childMap: new Map(), periods: [], first: 0, count: 0 });
      const root = mkNode({ id: '', name: '' }, -1);
      const nodeOf = new Map(); // 정권 → 나무에서 붙은 묶음 (대범위가 구성 정권을 옮겨 갈 때)
      for (const p of tr.periods) {
        if (p._under || p._overlay) continue;
        let node = root;
        for (const pe of p.peoplePath || []) {
          let child = node.childMap.get(pe.id);
          if (!child) {
            child = mkNode(pe, node.depth + 1);
            child.rule = pe.rowOrder || node.rule || ''; // 배열 기준 (형식 3 — 민족의 rowOrder · 적지 않으면 상위 민족의 것을 물려받음 · 'start'는 끊음)
            node.childMap.set(pe.id, child);
            node.children.push(child);
          }
          node = child;
        }
        node.periods.push(p);
        nodeOf.set(p, node);
      }
      // 민족 없는 문화(고고학 문화)는 트랙 맨 위 "문화" 묶음으로
      const cultures = root.periods.filter(p => p.polityKind === 'culture');
      if (cultures.length) {
        root.periods = root.periods.filter(p => p.polityKind !== 'culture');
        const cn = mkNode({ id: '__culture', name: '문화', color: tr.color, order: -1 }, 0);
        cn.culture = true;
        cn.periods = cultures;
        root.childMap.set(cn.id, cn);
        root.children.unshift(cn);
      }
      const startOf = n => Math.min(...n.periods.map(bandStart), ...n.children.map(startOf));
      const sortNode = n => {
        n.periods.sort(byStart);
        n.children.sort((a, b) => a.order - b.order || startOf(a) - startOf(b));
        n.children.forEach(sortNode);
      };
      sortNode(root);
      tr.depth = 1;
      const measure = n => {
        if (n.depth >= 0) tr.depth = Math.max(tr.depth, n.depth + 1);
        n.children.forEach(measure);
      };
      measure(root);
      if (tr.board) tr.depth = tr.board.rows.some(r => r.people) ? 2 : 1; // 집합 보기: 왼쪽 칸은 원래 트랙 칩(첫 단) · 제 민족 칩(둘째 단)뿐 (_boardGroups)
      /* 대범위 가지 (7-2): 전원으로 지은 나무에서 묶음마다 시작 해(start0)와 깊이(tr.depth)를 먼저 정해 둔 뒤에, 켠 대범위의 구성 정권만 합성 가지(__scope:<uid>)로 옮깁니다 —
         묶음의 차례는 start0으로 정하므로 켜고 꺼도 다른 민족 묶음의 차례와 왼쪽 칸 폭(this.gutter)이 그대로입니다 */
      const mark0 = n => {
        n.start0 = startOf(n);
        n.children.forEach(mark0);
      };
      mark0(root);
      /* 배열 기준 '북 → 남' (형식 3 — 설계 6 결정 6 C · 감독 선택 D4): 그 민족 묶음 안(제 줄과 하위 민족)은 남북 값(HT.northOf)이 큰 줄 · 묶음이 위.
         묶음 하나의 값 = 그 안 줄 값 가운데 가장 북쪽(한 줄의 값 = 그 줄 첫 나라의 값 — 묶음은 통째로 움직여 민족 칸이 조각나지 않음).
         start0처럼 전원으로 지은 나무에서 미리 정해 두어 대범위를 켜고 꺼도 묶음 차례가 그대로입니다. 기준을 적은 민족이 없는 트랙은 아무것도 하지 않음(옛 파일 그대로) */
      const nsOn = (function any(n) {
        return n.rule === 'northSouth' || n.children.some(any);
      })(root);
      if (nsOn) {
        const seams = tr.periods.map(p => [p, p._seamL, p._seamR]); // 값을 재려고 지은 줄이 이음매(_seamL · _seamR)를 남기지 않게 (줄은 아래 visit가 다시 지음)
        const mark1 = n => {
          let v = null;
          for (const r of chainRows(n.periods.filter(p => !p._member))) {
            const x = HT.northOf(r[0]);
            if (x != null && (v == null || x > v)) v = x;
          }
          for (const c of n.children) {
            mark1(c);
            if (c.ns0 != null && (v == null || c.ns0 > v)) v = c.ns0;
          }
          n.ns0 = v;
        };
        mark1(root);
        for (const [p, l, r] of seams) {
          p._seamL = l;
          p._seamR = r;
        }
      }
      const byNorth = (a, b) => (a.ns == null) - (b.ns == null) || (a.ns != null && b.ns != null ? b.ns - a.ns : 0); // 값이 없는 것은 뒤에 · 같으면 앞의 차례(시작 해) 그대로
      /* 선반(서고 과제 9 — 그릇 상태 'shelf'): 켠 그릇의 구성원 가운데 중요도(없으면 기간 길이) 상위 shelfKeep만 제 줄에 두고 나머지는 숨겨 폴더 발의 작은 꼬리표 줄로(_scopeBranches의 b.shelf) */
      if (this.seogo) tr._shelf = new Map(); // 서고만 — 옛 화면 · 내보내기의 트랙에는 새 칸을 만들지 않음(엔진 정답지 rows가 그대로)
      if (this.seogo && this.shelvedScopes.size) {
        const bySc = new Map();
        for (const p of tr.periods) {
          const s = scopeOf.get(p.uid);
          if (s && this.shelvedScopes.has(s.uid) && !p._hidden && !p._under && !p._overlay) bySc.set(s, (bySc.get(s) || []).concat([p]));
        }
        const rank = p => [typeof p.importance === 'number' ? p.importance : -1, bandEnd(p) - bandStart(p)];
        for (const [s, list] of bySc) {
          if (list.length <= G_SEOGO.shelfKeep) continue;
          const sorted = list.slice().sort((a, b) => { const x = rank(a), y = rank(b); return y[0] - x[0] || y[1] - x[1] || bandStart(a) - bandStart(b); });
          const rest = sorted.slice(G_SEOGO.shelfKeep);
          for (const p of rest) p._hidden = true;
          tr._shelf.set(s.uid, rest);
        }
      }
      const scopeNodes = this._scopeNodes(tr, scopeOf, nodeOf, inTrack, byStart);
      const hostedAfter = new Map(); // 본국 uid → 그 줄 바로 아래에 모일 가지들
      for (const sn of scopeNodes) if (sn.host) hostedAfter.set(sn.host.uid, (hostedAfter.get(sn.host.uid) || []).concat([sn]));
      const emitted = new Set();

      /* 2) 줄 만들기(chainRows — 맨 위 도우미). 승계(직접 · 간접 · 부흥)로 이어지는 정권만 같은 줄을 씁니다 — 관계가 없으면 같은 민족이라도 새 줄 */
      const rowList = []; // { periods, node, folded?, member? }
      const collect = (n, out) => {
        n.periods.forEach(p => !p._hidden && out.push(p));
        n.children.forEach(c => collect(c, out));
        return out;
      };
      /* 상징적 본국이 있는 대범위 가지는 본국 줄(과 그 소속 줄) 바로 아래에 — 본국 줄은 1px도 움직이지 않습니다 (8-4 바) */
      const emitHosted = list => {
        for (const p of list)
          for (const sn of hostedAfter.get(p.uid) || []) {
            if (emitted.has(sn)) continue;
            emitted.add(sn);
            visit(sn, false);
          }
      };
      // 소속 펼치기 · 단체 펼치기(리메이크 조각 ④) 가운데 하나라도 켠 상위 — 어느 쪽 소속이 섰는지는 아래 m._hidden이 가린다
      const opened = uid => this.expandedHosts.has(uid) || !!(this.expandedGroups && this.expandedGroups.has(uid));
      /* 줄 채우기는 내보내기만(위 packChains). 내보내기 때는 울타리도 — 두 띠는 같은 직접 그릇(가장 안쪽 · 켜고 끔과 무관)일 때만 한 줄:
         그래야 그릇 변형마다 줄 내용이 같아 새 앱이 변형을 겹쳐 켜도 어긋나지 않는다(리메이크 2부 포개짐 — remake/nest/지도.md 1-3 · 3-1) */
      const directScope = p => (p.scopes || []).filter(x => x.track === tr.id).sort((a, b) => (b.depth || 0) - (a.depth || 0) || a.start - b.start)[0] || null;
      const fence = (q, p) => directScope(q) === directScope(p);
      const rowsOf = list => (this.packRows ? packChains(chainRows(list, fence), fence) : chainRows(list));
      const pushMembers = host => {
        if (!opened(host.uid)) return;
        const mem = (host.members || []).filter(m => inTrack.has(m.uid) && m._host === host && !m._hidden && !(m._scope && m._host !== host)).sort(byStart); // 정말 이 띠 아래에 접히는 정권만 — 제 줄에 선 소속(예속 띠)이 소속 줄에 또 들어가 빈 줄이 생기지 않게 · 켠 대범위로 떠난 정권(위에서 _host를 비움)도 옛 상위 아래에 두지 않습니다 (가지에 한 번만)
        for (const r of rowsOf(mem)) {
          rowList.push({ periods: r, member: host });
          r.forEach(pushMembers);
          emitHosted(r);
        }
      };
      const visit = (node, isRoot) => {
        node.first = rowList.length;
        const folded = !isRoot && this.foldedPeoples.has(`${tr.id}|${node.id}`);
        let foldedAll = null;
        if (folded) {
          const all = collect(node, []).sort(byStart);
          if (all.length) rowList.push({ periods: all, node, folded: true });
          foldedAll = all;
        } else {
          // 이 단계에 직접 붙은 정권의 사슬(줄)과 하위 민족 묶음을 시작 연도순으로 섞어 놓습니다
          const byS = (a, b) => a.start - b.start;
          const ownBlocks = rowsOf(node.periods.filter(p => !p._member && !p._hidden)).map(r => ({
            start: bandStart(r[0]),
            ns: HT.northOf(r[0]), // 남북 값 (배열 기준 '북 → 남'인 묶음에서만 씀)
            run: () => {
              rowList.push({ periods: r, node });
              r.forEach(pushMembers);
              emitHosted(r);
            },
          }));
          const childBlocks = node.children.map(c => ({ start: c.start0, ns: c.ns0 ?? null, run: () => visit(c, false) }));
          if (isRoot) for (const sn of scopeNodes) if (!sn.host) childBlocks.push({ start: sn.start0, run: () => visit(sn, false) }); // 본국이 없는 대범위는 뿌리 바로 아래에 (시작 해 차례)
          // 뿌리(민족 없음)의 정권은 맨 아래, 그 밖에는 시작 연도순으로 섞습니다
          const blocks = isRoot ? childBlocks.sort(byS).concat(ownBlocks.sort(byS)) : childBlocks.concat(ownBlocks).sort(byS);
          if (!isRoot && node.rule === 'northSouth') blocks.sort(byNorth); // 배열 기준 '북 → 남' (위 mark1) — 안정 정렬이라 값이 같거나 없는 것끼리는 시작 해 차례 그대로
          blocks.forEach(b => b.run());
        }
        node.count = rowList.length - node.first;
        if (foldedAll) emitHosted(foldedAll); // 접힌 민족 줄 속의 본국: 대범위 가지는 그 접힌 줄 아래에 (접힌 묶음의 칸이 가지까지 덮지 않게 묶음을 닫은 뒤에)
      };
      if (tr.board) this._boardVisit(tr, rowList, pushMembers); // 집합 보기: 민족 나무가 아니라 구성 나라의 차례대로 옮겨 온 줄 그대로 (줄 통째 — _boardPlan)
      else {
        visit(root, true);
        for (const sn of scopeNodes) if (sn.host && !emitted.has(sn)) visit(sn, false); // 본국 줄을 찾지 못한 가지는 맨 아래에
      }

      tr.rowPeriods = [];
      tr.foldedRows = new Set();
      tr.memberRows = new Set();
      rowList.forEach((r, i) => {
        tr.rowPeriods[i] = r.periods;
        r.periods.forEach(p => {
          p._row = i;
          p._folded = !!r.folded;
        });
        if (r.folded) tr.foldedRows.add(i);
        if (r.member) tr.memberRows.add(i);
      });
      tr.groups = [];
      const groupsOf = n => {
        for (const c of n.children) {
          const folded = this.foldedPeoples.has(`${tr.id}|${c.id}`);
          if (c.count) tr.groups.push({ key: c.id, name: c.name, color: c.color, depth: c.depth, first: c.first, count: c.count, folded, culture: !!c.culture });
          if (!folded) groupsOf(c);
        }
      };
      if (tr.board) tr.groups = this._boardGroups(tr); // 집합 보기: 원래 트랙 칩 · 제 민족 칩 (접지 않음)
      else groupsOf(root);
      /* 대범위 가지도 민족 묶음처럼 왼쪽 칸 하나(민족 칸 전체 폭 — .tl-people.is-scope)를 갖고, 누르면 접힙니다. 테두리의 자리는 가지의 줄 범위(tr.scopeBranches)로 */
      for (const sn of scopeNodes) if (sn.count) tr.groups.push({ key: sn.id, name: sn.name, color: sn.color, depth: 0, first: sn.first, count: sn.count, folded: this.foldedPeoples.has(`${tr.id}|${sn.id}`), culture: false, scope: sn.scope.uid });
      tr.scopeBranches = tr.board ? this._boardBranch(tr) : this._scopeBranches(tr, scopeNodes); // 집합 보기: 판 전체를 두르는 테두리 하나 (대범위 테두리와 같은 말씨 · 가로 전체)
      /* 접힌 트랙·접힌 민족 줄의 가는 막대 단(위·아래 줄): 화면이 아니라 자료 전체로 미리 정해 두어, 옆으로 옮겨도 막대가 단을 바꾸지 않습니다 */
      const assignLanes = (list, key) => {
        const ends = [];
        for (const p of list.slice().sort((a, b) => bandStart(a) - bandStart(b) || bandEnd(b) - bandEnd(a))) {
          let lane = ends.findIndex(end => end <= bandStart(p));
          if (lane < 0) lane = ends.length >= 3 ? ends.indexOf(Math.min(...ends)) : ends.push(-Infinity) - 1; // 3단이 다 차면 가장 먼저 끝나는 단에 겹쳐
          ends[lane] = Math.max(ends[lane], bandEnd(p));
          p[key] = lane;
        }
      };
      assignLanes(tr.periods.filter(p => !p._hidden && !p._overlay && !p._under), '_laneAll');
      for (const r of tr.foldedRows) assignLanes(tr.rowPeriods[r] || [], '_laneRow');

      /* 2-1) 바탕 문화의 줄: 승계국(들)의 줄. 승계국이 또 바탕 문화면 그 문화의 줄을 따릅니다. 사건은 첫 줄에 */
      tr.underlays = [];
      const underRowsMemo = new Map();
      const underRows = (p, depth = 0) => {
        if (underRowsMemo.has(p.uid)) return underRowsMemo.get(p.uid);
        underRowsMemo.set(p.uid, []); // 순환 방지
        const rows = [];
        if (depth < 20) {
          for (const s of succIn(p)) {
            if (s._under) {
              underRows(s, depth + 1).forEach(r => !rows.includes(r) && rows.push(r));
              continue;
            }
            let host = s;
            while (host && host._hidden) host = host._host;
            if (host && host._row != null && !tr.foldedRows.has(host._row) && !rows.includes(host._row)) rows.push(host._row);
          }
        }
        rows.sort((a, b) => a - b);
        underRowsMemo.set(p.uid, rows);
        return rows;
      };
      for (const p of tr.periods) {
        if (!p._under) continue;
        const rows = underRows(p);
        p._underRows = rows;
        p._row = rows.length ? rows[0] : null; // 승계국이 모두 접혀 있으면 그리지 않음
        if (rows.length) tr.underlays.push(p);
      }
      tr.underRowSet = new Set(tr.underlays.flatMap(p => p._underRows));

      /* 2-2) 기관: 얹히는 시대 띠의 줄을 씁니다. 기관(agency)은 띠 안 맨 아래의 기관 칸에,
         구역(zone — 조계지·조차지)은 시대 띠 아래로 살짝 내려오는 탭으로. 탭은 연도가 겹치면 단을 나눕니다(최대 3단) */
      tr.overlays = [];
      const zoneLanes = new Map(); // 줄 → [[[시작, 끝], …] 단별]
      for (const p of tr.periods) {
        if (!p._overlay) continue;
        const rows = [];
        p._zoneLane = {};
        for (const h of p.hosts) {
          let host = inTrack.get(h.host.uid);
          while (host && host._hidden) host = host._host;
          if (!host || host._row == null || tr.foldedRows.has(host._row)) continue;
          if (!rows.includes(host._row)) rows.push(host._row);
          if (p.scale !== 'zone') continue;
          const s = Math.max(bandStart(p), h.start ?? -Infinity, bandStart(host));
          const e = Math.min(bandEnd(p), h.end ?? Infinity, bandEnd(host));
          if (e <= s) continue;
          const lanes = zoneLanes.get(host._row) || [];
          let lane = lanes.findIndex(list => !overlaps(list, s, e));
          if (lane < 0 && lanes.length < G.zoneLanes) lane = lanes.push([]) - 1;
          if (lane < 0) lane = lanes.length - 1;
          lanes[lane].push([s, e]);
          zoneLanes.set(host._row, lanes);
          p._zoneLane[h.host.uid] = lane;
        }
        p._row = rows.length ? rows[0] : null;
        if (rows.length) tr.overlays.push(p);
      }
      tr.zoneRowLanes = new Map([...zoneLanes].map(([r, lanes]) => [r, lanes.length]));
      /* 속국 이름표(depProxies): 이 트랙의 상국 띠마다 — 매달린 탭의 줄 수는 구역 탭처럼 띠 아래에 덧붙는 높이(rowCut)로, 품은 칸의 줄 수는 예속 칸 자리(depRows)로.
         매달린 탭을 접어 둔 상국(foldedHangs)은 세지 않음 — 그 줄이 낮아지고 구역 탭 · 소속선도 따라 올라옴 */
      tr.hangRowLanes = new Map();
      for (const p of tr.periods) {
        p._dep = (this._proxies && this._proxies.get(p.uid)) || null;
        if (!p._dep || p._hidden || p._overlay || p._under || p._row == null || tr.foldedRows.has(p._row) || this._hangsFolded(p.uid)) continue;
        if (p._dep.outLanes) tr.hangRowLanes.set(p._row, Math.max(tr.hangRowLanes.get(p._row) || 0, p._dep.outLanes));
      }

      /* 3) 사건 줄 배정 (접힌 민족·숨은 소속 정권의 사건은 보이는 상위 줄로) */
      const rowFor = uid => {
        let p = inTrack.get(uid);
        while (p && p._hidden) p = p._host;
        return p ? p._row : undefined;
      };
      let hasCommon = false;
      for (const e of tr.events) {
        const pol = e._place ? e._place.polityUid : e.polityUid;
        const row = pol != null ? rowFor(pol) : undefined;
        if (row == null) {
          e._row = -1;
          hasCommon = true;
        } else e._row = row;
      }
      const periodRows = tr.rowPeriods.length;
      tr.rows = periodRows + (hasCommon ? 1 : 0);
      tr.commonRow = hasCommon ? periodRows : -1;
      tr.events.forEach(e => {
        if (e._row === -1) e._row = tr.commonRow;
      });
      tr.events.sort((a, b) => a.start - b.start);
      tr.eventsByRow = Array.from({ length: tr.rows }, () => []);
      tr.events.forEach(e => tr.eventsByRow[e._row] && !tr.foldedRows.has(e._row) && tr.eventsByRow[e._row].push(e));
      tr.eventIndexByRow = tr.eventsByRow.map(list => intervalIndex(list, e => this._extent(e)));
      tr.eventParents = tr.events.filter(e => e.children && e.children.length);
      tr.eventByUid = new Map(tr.events.map(e => [e.uid, e]));

      /* 3-1) 인물의 줄: 섬긴 정권의 줄. 상위 띠 아래 숨은 소속 정권의 인물은 사건처럼 보이는 상위 줄로(band = 그 줄에서 실제로 그려지는 띠 — 막대는 그 띠 안쪽에 가둡니다).
         접힌 민족 줄 · 바탕 문화 · 기관을 섬긴 인물은 그리지 않습니다(상세에서만) */
      for (const x of tr.figures || []) {
        let p = inTrack.get(x.s.polity.uid);
        while (p && p._hidden) p = p._host;
        const ok = p && !p._overlay && !p._under && p._row != null && !tr.foldedRows.has(p._row);
        x.band = ok ? p : null;
        x.row = ok ? p._row : null;
        x.lvl = -1;
      }

      /* 4) 줄 구조: [지도자][내각][사건 줄 ×n][기간 레일][인물 단][예속 띠][기관] */
      /* 서고 배치(메이커 미리보기 — 새 앱 layout.dart _bandOf): 흰 사건 칸은 글줄 하나, '넉넉하게'만 둘(분류별 글줄이면 그 수) */
      const loose = this.density < 0;
      const seogoRow = this._seogoOn();
      const lines = seogoRow ? (loose ? 2 : 1) : this.density < 0 ? 2 : this.density > 0 ? 1 : tr.rows <= 6 ? 2 : 1;
      /* 인물 단의 단 배정 — 줄 단위로(승계로 한 줄을 같이 쓰는 앞뒤 띠에서 같은 사람이 다른 단으로 튀지 않게), 활동 막대의 해로만(화면이 아니라 자료로),
         중요도 높은 순 → 시작 순으로 위 단부터. 최대 단 수: 보통 2 · `넉넉하게` 3 · `빽빽하게`와 글줄 1개 모드 1. 넘치는 인물은 그리지 않습니다(lvl −1 — 정권 상세의 인물 목록에는 모두 나옴) */
      const figMax = this._bird || this.show.figures === false ? 0 : seogoRow ? (loose ? 3 : 0) : this.density < 0 ? 3 : this.density > 0 || lines === 1 ? 1 : 2; // 서고: 인물 단은 '넉넉하게'에서만 3단(새 앱 figMax)
      const figRows = tr.rowPeriods.map(() => 0);
      if (figMax) {
        const byRow = new Map();
        for (const x of tr.figures || []) if (x.row != null) byRow.set(x.row, (byRow.get(x.row) || []).concat([x]));
        for (const [r, list] of byRow) {
          const levels = Array.from({ length: figMax }, () => []);
          const lvlOf = new Map(); // 인물 → 이 줄에서 먼저 잡은 단
          list.sort((a, b) => (b.f.importance || 2) - (a.f.importance || 2) || a.s.start - b.s.start || a.s.endY - b.s.endY);
          for (const x of list) {
            const [lo, hi] = this._figSpan(x.s); // 1년이 안 되는 활동은 그 가운데 1년으로 (같은 해의 두 사람 · 끝이 맞닿은 막대가 한 단에 포개지지 않게)
            const free = l => !levels[l].some(([a, b]) => a < hi && lo < b);
            const want = lvlOf.get(x.f.uid);
            const l = want != null && free(want) ? want : levels.findIndex((_, i) => free(i));
            if (l < 0) continue;
            levels[l].push([lo, hi]);
            lvlOf.set(x.f.uid, l);
            x.lvl = l;
            figRows[r] = Math.max(figRows[r], l + 1);
          }
        }
      }
      /* 왕조 칸: 다스린 왕조가 적힌 정권이 있는 트랙만, 띠 맨 위에 (지도자 칸 위) */
      const dynasty = this.show.dynasties !== false && tr.periods.some(p => this._dynOf(p).length) ? G.dynasty : 0;
      /* 렌즈를 켠 동안(설계 7-8 결정 5 A): 렌즈 칸은 지도자 칸 자리에 들어가므로, 지도자 칸이 없는 트랙도 어느 렌즈로든 그릴 자료(HT.lensAny)가 있으면 그 자리를 둡니다 —
         렌즈 종류와 상관없이 같은 배치라 렌즈를 바꿔도 줄 높이가 그대로 (렌즈를 끄면 예전과 1px도 같음) */
      const leader = (this.show.leaders && tr.periods.some(p => p.leaders && p.leaders.length)) || (this.themeLens && tr.periods.some(p => HT.lensAny(p))) ? G.leader : 0;
      const cabinet = this.show.cabinets && tr.periods.some(p => p.cabinets && p.cabinets.length) ? G.cabinet : 0;
      /* 기관 칸: 통감부 같은 기관이 있는 트랙만, 띠 안 맨 아래(기간 막대·예속 띠 아래)에 — 다른 칸을 가리지 않습니다 */
      const organ = (tr.overlays || []).some(p => p.scale !== 'zone') ? G.organ : 0;
      /* 예속 칸: 상국 띠 안 맨 아래(기간 막대 아래)에 상국이 다스린 속국(자율성 1 · 0)의 이름표 — 줄 수만큼(한 줄 G.dep + 틈 1) 띠가 높아져 사건 글줄 · 막대와 겹치지 않습니다.
         자리는 줄 단위입니다 — 그 줄에 이름표를 품은 상국이 있을 때만(depRows). 트랙 공통 값(dep)은 tr.geo · tr.rowH의 기준으로만 남깁니다 */
      const depLanes = p => (p._dep && !p._overlay && !p._hidden && !p._under ? p._dep.inLanes : 0);
      const dep = tr.periods.some(depLanes) ? G.dep : 0;
      const depRows = tr.rowPeriods.map((list, r) => {
        const n = tr.foldedRows.has(r) ? 0 : Math.max(0, ...list.map(depLanes));
        return n ? n * (G.dep + G.slotGap) - G.slotGap : 0;
      });
      /* 기간 막대 단 수: 한 줄에서 시기가 겹치는 기간 사건 수만큼(2~3단) — 막대끼리 겹쳐 쌓이지 않게 */
      let railLevels = 2;
      for (const list of tr.eventsByRow) {
        const segs = list
          .filter(e => !e.parentUid && (e.endY - e.start > 0 || e.startRange || e.endRange || HT.datedAlts(e).length)) // 이설은 시작이 있는 것만 그립니다 (글만 있는 견해는 상세 창에만 — HT.datedAlts)
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
        railLevels = Math.max(railLevels, Math.min(3, ends.length));
      }
      if (seogoRow && !loose) railLevels = 0; // 서고: 기간 막대는 '넉넉하게'에서만(새 앱 — 막대를 그리지 않는 보기에서는 자리도 없음)
      const railH = railLevels * G.railPitch;
      /* 세로 자리: [여백][왕조][틈][지도자][틈][내각][틈][사건 글줄 ×n][기간 막대 2~3단][예속 띠][틈][기관][여백] — 모두 줄(lane) 좌표.
         서고 배치(_seogoOn — G.head 14): [이름 색줄 14][왕조][지도자][내각][예속][기관][사건 글줄 ×n][기간 막대][인물] — 칸 층은 틈 없이 맞붙고(slotGap 0) 예속 · 기관 칸도 사건 칸 위의 층(새 앱 layout.dart _bandOf) */
      const seogo = this._seogoOn();
      const dynastyTop = G.inset + (seogo ? G.head : 0);
      const leaderTop = dynastyTop + (dynasty ? dynasty + G.slotGap : 0);
      const cabinetTop = leaderTop + (leader ? leader + G.slotGap : 0);
      const textTop = seogo ? cabinetTop + (cabinet ? cabinet : 0) + (dep ? dep : 0) + organ : cabinetTop + (cabinet ? cabinet + G.slotGap : 0);
      const railTop = textTop + lines * G.line;
      const depTop = seogo ? cabinetTop + (cabinet ? cabinet : 0) : railTop + railH + G.slotGap;
      const organTop = seogo ? depTop + (dep ? dep : 0) : depTop + (dep ? dep + G.slotGap : 0);
      tr.geo = {
        lines,
        font: lines > 1 ? 12 : 11.5,
        name: lines > 1 ? 13.5 : 12.5,
        dynastyTop,
        dynastyH: dynasty,
        leaderTop,
        leaderH: leader,
        cabinetTop,
        cabinetH: cabinet,
        organTop,
        organH: organ,
        textTop,
        lineH: G.line,
        railTop,
        railH,
        railLevels,
        depTop,
        depH: dep,
      };
      tr.rowH = seogo ? railTop + railH + (railH ? G.pad2 : 0) : (organ ? organTop + organ : dep ? depTop + dep : railTop + railH) + G.inset; // 서고: 막대가 몸통 아랫변에 닿지 않게 틈 3(G.pad2)
      tr.geo.rowH = tr.rowH;
      /* 사건 분류별 내부 글줄: 한 줄(띠)의 사건 분류가 둘 이상이면 분류마다 글줄 하나 — 그만큼 띠가 높아집니다.
         줄 순서는 분류 목록 순서로 고정(정치 → 전쟁 → 외교 …, 없는 분류는 건너뜀). 분류가 하나뿐인 줄은 예전처럼 글줄 1~2개에 자유롭게,
         빽빽하게에서는 모두 한 글줄. 높이가 화면 이동마다 바뀌지 않도록 줄에 속한 사건 전체(큰 사건만)로 정합니다 */
      const catIndex = id => (this._cats && this._cats.has(id) ? this._cats.get(id).i : 9999);
      tr.rowCats = tr.eventsByRow.map(list => {
        if (this.density > 0 || (seogoRow && !loose)) return null; // 서고: 분류별 글줄은 '넉넉하게'에서만
        const ids = [...new Set(list.filter(e => !e.parentUid).map(e => e.category || 'etc'))];
        return ids.length >= 2 ? ids.sort((a, b) => catIndex(a) - catIndex(b)) : null;
      });
      /* 시기 구분(학계) 단 — 줄 단위 위쪽 덧단: 왕조 칸 아래 · 지도자 칸 위에 체계마다 얇은 한 줄. 그 줄에 그리는 정권들이 가진 체계 수(최대 3)만큼
         그 줄만 높아지고, 지도자 · 내각 · 사건 글줄 · 그 아래가 함께 내려갑니다 (시기가 없는 줄은 1px도 그대로). 빽빽하게 · 표시 체크를 끄면 없음 */
      const phaseLanes = p => (this.show.phases !== false && this.density <= 0 && p.phaseSchemes ? Math.min(G.phaseMax, p.phaseSchemes.length) : 0);
      const upRows = tr.rowPeriods.map((list, r) => (tr.foldedRows.has(r) ? 0 : Math.max(0, ...list.map(phaseLanes)) * (G.phase + G.phaseGap)));
      /* 지위 단 — 같은 줄 단위 위쪽 덧단(시기 단 아래 · 지도자 칸 위): 그 줄에 지위가 둘 이상인 정권(지위가 실제로 바뀐 정권)이 있을 때만.
         지위가 하나뿐인 정권만 있는 줄은 단 없이 책갈피 탭의 작은 딱지로. 빽빽하게 · 표시 체크를 끄면 없음 */
      const rankRows = tr.rowPeriods.map((list, r) => (!tr.foldedRows.has(r) && this.show.ranks !== false && this.density <= 0 && list.some(p => p.rankSpans && p.rankSpans.length > 1) ? G.rank + G.rankGap : 0));
      /* 단체 단(설계 7-8 결정 1 A · 2 A — 감독 선택 2026-10-12) — 같은 줄 단위 위쪽 덧단(지위 단 아래 · 지도자 칸 위): 그 줄에 집권 칸이 있는 정권이 있으면 집권 줄,
         실권 칸이 있는 정권이 있으면 실권 줄(둘 다면 위 = 집권 · 아래 = 실권 — 실권이 명목 지도자와 맞닿게). 자료(HT.groupStrip)가 있는 줄만 높아지고, 빽빽하게 · 표시 체크 '단체'를 끄면 없음.
         표시 체크는 켜져 있어야(show.groups가 참) 그림 — 뷰어 · 메이커는 HT.SHOW_DEFAULTS(기본 켬)로 받고, 새 앱 내보내기의 연표(prototype/scripts/export/base.mjs — show에 이 열쇠가 없음)는
         새 앱이 단체 단을 그릴 수 있게 될 때까지 덧단 없이 예전 배치 그대로(계약 3절의 줄 쌓기 자체 점검이 맞음 — 설계 7-8 11절) */
      const groupsOn = !!this.show.groups && this.density <= 0;
      const powerRows = tr.rowPeriods.map((list, r) => (groupsOn && !tr.foldedRows.has(r) && list.some(p => HT.groupStrip(p).power.length) ? G.power + G.powerGap : 0));
      const realRows = tr.rowPeriods.map((list, r) => (groupsOn && !tr.foldedRows.has(r) && list.some(p => HT.groupStrip(p).real.length) ? G.power + G.powerGap : 0));
      /* 줄마다의 세로 자리: 글줄 수(L) · 예속 띠 자리(dp — 그 줄에 예속 띠가 있을 때만) · 위쪽 덧단(up — 시기 단, rk — 지위 단 — 글줄 위) ·
         인물 단 수(fg — 그 줄에 그릴 인물이 있을 때만, 글줄 아래)로. 모든 줄이 제 geo를 가집니다.
         위쪽 덧단은 지도자 · 내각 · 사건 글줄과 그 아래(기간 막대 · 인물 단 · 예속 띠 · 기관)를 모두 up + rk만큼 내립니다.
         인물 단은 기간 막대 아래 · 예속 띠 위: [틈 3][단 15 (+ 단 사이 2) × fg]. 덧단도 인물도 없는 줄은 예전과 1px도 같습니다 */
      const geoFor = (L, dp, up = 0, rk = 0, fg = 0, pw = 0, rl = 0, r = null) => {
        if (seogo) {
          /* 서고 두 장 꼬리표(새 앱 layout.dart _bandOf · 계약 3절): 색줄 14 → 칸 층(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관 — 14씩 맞붙음) → 흰 사건 칸 18 × L →
             기간 막대 → 인물 단(막대 아래 틈 3 · 단 아래 틈 3). 막대만 있으면 몸통 아랫변까지 3.
             왕조 · 지도자 · 내각 층은 그 줄에 칸이 있을 때만(새 앱 RowSpec.cellRows — 내보내기 tracks.mjs 비트 16~18 '칸이 매인 띠의 줄로 센다') — 트랙 값이 아니라 줄 값 */
          const here = f => r == null || (tr.rowPeriods[r] || []).some(f);
          const dynasty = trackDynasty && here(p => this._dynOf(p).length) ? trackDynasty : 0;
          const leader = trackLeader && here(p => (this.show.leaders && p.leaders && p.leaders.length) || (this.themeLens && HT.lensAny(p))) ? trackLeader : 0;
          const cabinet = trackCabinet && here(p => p.cabinets && p.cabinets.length) ? trackCabinet : 0;
          let y = G.head;
          const dTop = y;
          y += dynasty;
          const pTop = y;
          y += up;
          const rTop = y;
          y += rk ? G.rank : 0;
          const pwTop = y;
          y += pw ? G.power : 0;
          const rlTop = y;
          y += rl ? G.power : 0;
          const lTop = y;
          y += leader;
          const cTop = y;
          y += cabinet;
          const dpTop = y;
          y += dp;
          const oTop = y;
          y += organ;
          const tt = y;
          y += L * G.line;
          const rt = y;
          y += railH;
          const fh = fg ? fg * G.figure + (fg - 1) * G.figGap : 0;
          const ft = rt + railH + G.pad2;
          y = fh ? ft + fh + G.pad2 : railH ? y + G.pad2 : y; // 막대도 인물도 없으면 사건 칸이 몸통 아랫변
          return Object.assign({}, tr.geo, { lines: L, dynastyTop: dTop, dynastyH: dynasty, leaderH: leader, cabinetH: cabinet, phaseTop: pTop, phaseH: up, rankTop: rTop, rankH: rk ? G.rank : 0, powerTop: pwTop, powerH: pw ? G.power : 0, realTop: rlTop, realH: rl ? G.power : 0, leaderTop: lTop, cabinetTop: cTop, textTop: tt, railTop: rt, figTop: ft, figH: fh, figLevels: fg, depTop: dpTop, depH: dp, organTop: oTop, rowH: y });
        }
        const sh = up + rk + pw + rl; // 위쪽 덧단(시기 · 지위 · 집권 · 실권)이 지도자 칸부터 아래를 내리는 만큼 — 단체 단이 없으면 예전과 같은 수
        const tt = textTop + sh;
        const rt = tt + L * G.line;
        const ft = rt + railH + G.slotGap;
        const fh = fg ? fg * G.figure + (fg - 1) * G.figGap : 0;
        const dt = fh ? ft + fh + G.slotGap : rt + railH + G.slotGap; // 인물 단 아래에 오는 것(예속 띠 · 기관)은 막대와 붙어 보이지 않게 틈 3
        const ot = dt + (dp ? dp + G.slotGap : 0);
        return Object.assign({}, tr.geo, { lines: L, phaseTop: leaderTop, phaseH: up, rankTop: leaderTop + up, rankH: rk ? G.rank : 0, powerTop: leaderTop + up + rk, powerH: pw ? G.power : 0, realTop: leaderTop + up + rk + pw, realH: rl ? G.power : 0, leaderTop: leaderTop + sh, cabinetTop: cabinetTop + sh, textTop: tt, railTop: rt, figTop: ft, figH: fh, figLevels: fg, depTop: dt, depH: dp, organTop: ot, rowH: (organ ? ot + organ : dp ? dt + dp : fh ? ft + fh : rt + railH) + G.inset });
      };
      const trackDynasty = dynasty, trackLeader = leader, trackCabinet = cabinet; // 서고 geoFor가 줄 값으로 가르는 트랙 값
      tr.geos = tr.rowCats.map((cats, r) => geoFor(cats ? cats.length : lines, depRows[r] || 0, upRows[r] || 0, rankRows[r] || 0, figRows[r] || 0, powerRows[r] || 0, realRows[r] || 0, r));
      /* 조감: 줄은 띠 하나뿐 — 모든 칸 · 글줄 · 막대 · 인물 · 덧단의 높이가 0이고, 글줄 하나가 띠 전체(네모 · 승계선이 닿는 높이 = 띠 가운데 — _anchorY) */
      if (this._bird) {
        const H = this._bird.h;
        tr.geo = { lines: 1, font: 10, name: 10.5, dynastyTop: 0, dynastyH: 0, leaderTop: 0, leaderH: 0, cabinetTop: 0, cabinetH: 0, organTop: H, organH: 0, textTop: 0, lineH: H, railTop: H, railH: 0, railLevels: 0, depTop: H, depH: 0, rowH: H, bird: true };
        tr.rowH = H;
        tr.rowCats = tr.rowCats.map(() => null);
        tr.geos = tr.geos.map(() => Object.assign({}, tr.geo, { phaseTop: 0, phaseH: 0, rankTop: 0, rankH: 0, powerTop: 0, powerH: 0, realTop: 0, realH: 0, figTop: H, figH: 0, figLevels: 0 }));
      }

      /* 5) 줄마다의 높이와 위쪽 위치 (접힌 민족 줄은 낮고, 민족이 바뀌는 곳은 조금 더 띄웁니다) */
      tr.rowTop = [];
      tr.rowGap = [];
      tr.rowHs = [];
      tr.rowCut = []; // 줄 높이 가운데 정권 띠 아래에 덧붙은 부분(구역 탭 + 바탕 문화 이름 단)
      let y = G.pad;
      const groupStart = new Set(tr.groups.filter(gp => !tr.board || gp.from).map(gp => gp.first)); // 집합 보기는 원래 트랙이 바뀌는 곳만 묶음 틈
      /* 서고의 줄 올림(새 앱 RowSpec.raised · contained — G_SEOGO.raise · contain): 솟는 줄(받침 카드 + 상국 탭 · 연합 탭이 있는 띠의 줄) 15 ·
         그릇의 줄(켠 대범위 가지의 줄 — 매다는 실 · 끈 대범위에 든 띠의 줄 — 열쇠표) 10 — 탭 자리에 더함(_tabOf). 서고가 아니면 모두 0(예전 그대로) */
      tr.rowLift = tr.rowPeriods.map(() => 0);
      if (seogo) {
        const inBranch = new Set();
        for (const b of tr.scopeBranches || []) for (let r = b.first; r < b.first + b.count; r++) inBranch.add(r);
        const keyed = p => (p.scopes || []).some(x => x.track === tr.id && !this.scopeOn(x)); // 끈 대범위에 든 띠 — 열쇠표가 달림 (_keyTagsHTML)
        tr.rowLift = tr.rowPeriods.map((list, r) => {
          if (tr.foldedRows.has(r)) return 0;
          const shown = list.filter(p => !p._hidden && !p._overlay && !p._under);
          if (shown.some(p => hostSegs(p, v => v).length || (p.groupLinks && p.groupLinks.length))) return G.raise;
          return inBranch.has(r) || shown.some(keyed) ? G.contain : 0;
        });
      }
      for (let r = 0; r < tr.rows; r++) {
        const tab = this._tabOf(tr, r); // 띠 위 책갈피 탭 자리 (+ 서고의 올림 몫)
        const gap = (r === 0 ? 0 : tr.memberRows.has(r) ? G.memberGap : G.gap + (groupStart.has(r) ? G.groupGap : 0)) + tab + this._scopePad(tr, r, r - 1); // 대범위 테두리의 머리 · 아래 여백 (_foldRows와 같은 도우미)
        // 구역 탭이 내려오는 줄과 바탕 문화가 깔린 줄은 그만큼 더 높습니다
        /* 띠 아래에 덧붙는 줄: 속국 이름표가 매달린 줄(띠에 바로 붙음 — 한 줄 HANG.pitch) → 구역 탭(한 줄 G.zoneTab + G.zoneGap) */
        const hl = tr.hangRowLanes.get(r) || 0;
        const zl = tr.zoneRowLanes.get(r) || 0;
        const cut = this._bird || tr.foldedRows.has(r) ? 0 : (hl + zl ? hl * HANG.pitch + zl * (G.zoneTab + G.zoneGap) + 3 : 0) + (tr.underRowSet.has(r) ? G.hem : 0);
        tr.rowCut.push(cut);
        const h = tr.foldedRows.has(r) ? G.foldedGroup : ((tr.geos[r] && tr.geos[r].rowH) || tr.rowH) + cut;
        y += gap;
        tr.rowGap.push(gap);
        tr.rowTop.push(y);
        tr.rowHs.push(h);
        y += h;
      }
      const tailShelf = (tr.scopeBranches || []).reduce((m, b) => ((b.ee ?? b.first + b.count) >= tr.rowPeriods.length ? Math.max(m, this._shelfH(b) + (b.kids || []).filter(c => (c.ee ?? c.first + c.count) >= tr.rowPeriods.length).length * G.scopeFoot) : m), 0); // 마지막 가지의 선반 · 포개진 발은 트랙 밑에 자리를 더함(서고 과제 9)
      tr.height = tr._sphereHidden ? 0 : tr.folded ? G.folded : Math.max(y + tailShelf + G.pad, G.folded); // 접힌 문화권의 트랙은 0 (머리 단이 대신함 — 서고 3단)
      // 화면 범위에 따라 빈 줄을 접을 때의 기준값
      tr.baseRowTop = tr.rowTop.slice();
      tr.baseRowGap = tr.rowGap.slice();
      tr.baseRowHs = tr.rowHs.slice();
      tr.baseHeight = tr.height;
      tr.hiddenRows = new Set();
      tr._rowMemo = false; // 접힘의 기억(히스테리시스)이 아직 없음 — 같은 트랙의 앞선 배치가 있으면 setData가 이어 줍니다(_foldAhead)
      tr._hiddenSig = null; // DOM에 적어 둔 접힘 (짓기 전에 _foldAhead가 채우고, 그 크기 그대로 짓습니다)
    }

    /** 지금 화면 범위에 아무것도 없는 줄은 높이까지 접어, 아래 줄이 위로 올라옵니다.
        계산(_foldRows — 모델만)과 쓰기(_collapseRows — 바뀐 것만 DOM에)를 나눠 두어, DOM을 짓기 전에도 접힌 크기를 알 수 있습니다 */
    _foldRows(tr, X, W, keepOpen = false) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      /* 접힘 판단에 여유를 둡니다: 화면 폭의 1/4 안으로 다가오면 펴지고, 3/4 밖으로 멀어져야 접힙니다(히스테리시스).
         끌기·미끄러짐·이동 중(keepOpen)에는 펴지기만 하고 접히지는 않아, 손에 잡힌 동안 줄이 부들거리지 않습니다 */
      const m1 = W * 0.25;
      const m2 = W * 0.75;
      const first = !tr._rowMemo;
      const x0 = X(0), scale = X(1) - x0;
      const year = x => (x - x0) / scale;
      const near = Array.from({ length: tr.rows }, () => false);
      const far = Array.from({ length: tr.rows }, () => true);
      const mark = (r, a, b) => {
        const l = X(a);
        const rr = X(b);
        if (rr >= -m1 && l <= W + m1) near[r] = true;
        if (!(rr < -m2 || l > W + m2)) far[r] = false;
      };
      for (let r = 0; r < tr.rows; r++) {
        for (const p of tr.rowPeriods[r] || []) {
          if (p._hidden) continue;
          mark(r, bandStart(p) - (p.startUnknown ? (FADE * this.span()) / W : 0), bandEnd(p) + (p.endUnknown ? (FADE * this.span()) / W : 0));
        }
        if (tr.eventIndexByRow) {
          if (!near[r]) near[r] = intervalHas(tr.eventIndexByRow[r], year(-m1), year(W + m1));
          if (far[r]) far[r] = !intervalHas(tr.eventIndexByRow[r], year(-m2), year(W + m2));
        } else for (const e of tr.eventsByRow[r] || []) mark(r, ...this._extent(e));
      }
      for (const p of tr.underlays || []) for (const r of p._underRows) mark(r, bandStart(p), bandEnd(p));
      const seen = near.map((n, r) => n || (!first && !tr.hiddenRows.has(r) && (keepOpen || !far[r])));
      const hidden = new Set();
      let y = G.pad;
      let lastVisible = -1;
      const groupStart = new Set(tr.groups.filter(gp => !tr.board || gp.from).map(gp => gp.first)); // 집합 보기는 원래 트랙이 바뀌는 곳만 묶음 틈
      for (let r = 0; r < tr.rows; r++) {
        if (!seen[r]) {
          hidden.add(r);
          tr.rowGap[r] = 0;
          tr.rowHs[r] = 0;
          tr.rowTop[r] = y;
          continue;
        }
        // 숨은 줄 사이를 건너뛰어도 민족이 바뀌는 곳은 띄웁니다
        let crossesGroup = false;
        for (let k = lastVisible + 1; k <= r; k++) if (groupStart.has(k)) crossesGroup = true;
        const tab = this._tabOf(tr, r); // 띠 위 책갈피 탭 자리 (+ 서고의 올림 몫)
        const gap = (lastVisible < 0 ? 0 : tr.memberRows.has(r) && !crossesGroup ? G.memberGap : G.gap + (crossesGroup ? G.groupGap : 0)) + tab + this._scopePad(tr, r, lastVisible); // 대범위 테두리의 머리 · 아래 여백 (_layoutTrack과 같은 도우미)
        y += gap;
        tr.rowGap[r] = gap;
        tr.rowTop[r] = y;
        tr.rowHs[r] = tr.baseRowHs[r];
        y += tr.rowHs[r];
        lastVisible = r;
      }
      tr.height = Math.max(y + G.pad, G.folded);
      tr.hiddenRows = hidden;
      tr._rowMemo = true;
      return [...hidden].join(','); // 접힘 서명 — DOM에 적어 둔 것(_hiddenSig)과 다르면 _collapseRows가 씁니다
    }

    _collapseRows(tr, X, W, keepOpen = false) {
      const sig = this._foldRows(tr, X, W, keepOpen);
      if (sig === tr._hiddenSig) return;
      // 바뀐 것만 DOM에 반영
      tr._hiddenSig = sig;
      const hidden = tr.hiddenRows;
      tr.laneEls.forEach((el, r) => {
        el.style.marginTop = `${tr.rowGap[r]}px`;
        el.style.height = `${tr.rowHs[r]}px`;
        el.classList.toggle('is-collapsed', hidden.has(r));
      });
      tr.el.style.height = `${tr.height}px`;
      tr._heightChanged = true; // 이번 그리기에서 높이가 흐르기 시작함 → 닻 붙잡기(_draw)
      tr._labelSig = null; // 왼쪽 라벨도 새 높이로
      const boxes = tr.el.querySelectorAll('.tl-people');
      tr.groups
        .filter(gp => gp.name)
        .forEach((gp, i) => {
          const el = boxes[i];
          if (!el) return;
          const at = this._peopleSpan(tr, gp);
          if (!at) {
            el.classList.add('is-collapsed');
            el.style.height = '0px';
            return;
          }
          el.classList.remove('is-collapsed');
          el.style.top = `${at.top}px`;
          el.style.height = `${at.height}px`;
        });
      this._placePchips(tr); // 민족 딱지도 제 줄과 함께 (줄이 접혀 높이가 0이면 함께 사라짐)
      this._placeScopes(tr); // 대범위 테두리의 세로 자리도 (가로는 매 그리기의 _drawScopes)
      this._fitTrackName(tr);
    }

    /** 트랙 이름(왼쪽 세로 글): 트랙 높이에 다 들지 않으면 뜻이 남는 차례로 줄이고(shortNames) 그래도 안 되면 글 없이 — 세로 글이 칸 밖으로 넘치지 않게
        (한 자 ≈ 15.5px: 12.5px 글자 + 자간 .24em · 위아래 여유 4). 줄였으면 풍선에 온 이름 */
    _fitTrackName(tr) {
      const b = tr.el && !tr.folded ? tr.el.querySelector('.tl-tname') : null;
      const span = b && b.querySelector('span');
      if (!span) return;
      const text = shortName(tr.name, t => [...t].length * 15.5 + 4 <= tr.height);
      if (span.textContent !== text) span.textContent = text;
      b.title = text === tr.name ? '접기' : `${tr.name} · 접기`;
    }

    /** 민족 칸의 세로 자리: 그 묶음에서 지금 펴져 있는 첫 줄부터 마지막 줄까지 (모두 접혔으면 null) */
    _peopleSpan(tr, gp) {
      let first = -1;
      let last = -1;
      for (let r = gp.first; r < gp.first + gp.count; r++) {
        if (tr.hiddenRows.has(r)) continue;
        if (first < 0) first = r;
        last = r;
      }
      return first < 0 ? null : { top: tr.rowTop[first], height: tr.rowTop[last] + tr.rowHs[last] - tr.rowTop[first] };
    }

    /** 줄 r의 정권들의 민족이 그 줄을 덮은 민족 묶음(왼쪽 민족 칸)과 다른가 (docs/구상-체제-확장.md 8-4 사) — 다르면 { id, name, color, under, cover, all }, 같거나 민족이 없으면 null.
        자리는 소속이 정하므로(상위 띠 아래에 접혀 들어간 소속 정권 · 뒤에 올 대범위로 모인 정권) 그 줄의 민족 칸은 상위의 민족으로 덮여 제 민족이 가려집니다 — 그때 민족 딱지로 알립니다.
        묶음과 다른 민족이 여럿이면 가장 오래 이어진 민족을 딱지에, 모두는 설명글에. 접힌 줄 · 트랙 공통 줄은 묻지 않습니다 */
    _rowPeopleChip(tr, r) {
      if (!tr.rowPeriods || tr.foldedRows.has(r) || r === tr.commonRow) return null;
      const list = (tr.rowPeriods[r] || []).filter(p => p.peopleId && !p._hidden);
      if (!list.length) return null;
      let cover = null;
      for (const gp of tr.groups || []) if (gp.name && !gp.culture && gp.first <= r && r < gp.first + gp.count && (!cover || gp.scope || (!cover.scope && gp.depth > cover.depth))) cover = gp; // 대범위 가지(민족 칸 전체 폭)가 덮은 줄은 그 가지가 덮개
      const own = new Map(); // 묶음과 다른 민족 → 그 민족 정권들의 기간 합
      for (const p of list) if (!cover || p.peopleId !== cover.key) own.set(p.peopleId, (own.get(p.peopleId) || 0) + bandEnd(p) - bandStart(p));
      if (!own.size) return null;
      const id = [...own.entries()].sort((a, b) => b[1] - a[1])[0][0];
      const p = list.find(q => q.peopleId === id);
      const host = p._host || null;
      return { id, name: p.peopleName || id, color: p.peopleColor || tr.color, under: host ? host.name : cover ? cover.name : '', cover: cover ? cover.name : '', all: [...own.keys()].map(k => list.find(q => q.peopleId === k).peopleName || k), scope: cover && cover.scope ? cover.name : '' };
    }

    /** 민족 딱지 (8-4 사): 줄마다 _rowPeopleChip이 다르다고 하면, 민족 칸 자리의 오른쪽 끝 단에 그 줄 높이만큼의 딱지를 끼워 넣습니다
        (제 민족 색 · 세로 글 · 종이빛 1px 테 · 폭 = 단 폭 − 8 · 글이 안 들어가면 첫 글자, 그것도 안 되면 글 없이). 누르면 그 민족의 문서 — 접기 단추가 아닙니다.
        세로 자리는 _placePchips가 (지을 때와 빈 줄이 접힐 때) 씁니다. 민족 칸(.tl-people)을 순번으로 짝짓는 코드가 있어 클래스는 따로(.tl-pchip) */
    _pchipsHTML(tr) {
      tr.pchips = [];
      if (tr.folded) return '';
      for (let r = 0; r < tr.rows; r++) {
        const c = this._rowPeopleChip(tr, r);
        if (c) tr.pchips.push(Object.assign({ r }, c));
      }
      const left = (this.depth - 1) * COL.people + 4;
      const width = COL.people - 8;
      const fits = (s, h) => s.length * 10.1 + 4 <= h; // 세로 글 한 자 ≈ 10.1px (9.5px 글자 + 자간 .06em — 빈칸도 한 자) · 위아래 테 1px씩과 여유
      /* 민족 칸이 한 단뿐이면(this.depth === 1) 오른쪽 끝 단이 곧 대범위 칸(전체 폭)이라, 가지 안의 딱지가 칸 전체를 덮으면 대범위 이름과 누를 자리가 사라집니다 —
         그때 가지 안의 딱지는 칸 오른쪽 가장자리의 가는 띠(글 없이 제 민족 색 · 누르면 문서는 그대로)로 끼우고, 이름은 그 왼쪽에 (_placePchips의 is-thin) */
      const thinL = COL.people - 2 - 6; // 대범위 칸(왼쪽 2 · 폭 COL.people − 4)의 안쪽 오른쪽 끝에 붙는 폭 5
      return tr.pchips
        .map(c => {
          const h = tr.baseRowHs[c.r] || tr.rowHs[c.r] || 0;
          const thin = this.depth === 1 && !!c.scope;
          const text = thin ? '' : shortName(c.name, t => fits(t, h)); // 들지 않으면 뜻이 남는 차례로 줄이고, 그래도 안 되면 글 없이 (shortNames)
          const tip = c.scope ? `${c.all.join(' · ')} — 대범위 ${c.scope}에 모인 나라의 제 민족 · 누르면 ${c.name} 문서` : `${c.all.join(' · ')} — ${c.under ? `${c.under} 아래에 놓인 ` : ''}다른 민족${c.cover && c.cover !== c.under ? ` (이 자리의 민족 칸: ${c.cover})` : ''} · 누르면 ${c.name} 문서`;
          return `<button type="button" class="tl-pchip${thin ? ' is-thin' : ''}" data-people-doc="${esc(`people:${c.id}`)}" data-pchip="${c.r}" style="left:${thin ? thinL : left}px;width:${thin ? 5 : width}px;top:${tr.rowTop[c.r]}px;height:${tr.hiddenRows.has(c.r) ? 0 : tr.rowHs[c.r]}px;--pc:${c.color}" title="${esc(tip)}"><span>${esc(text)}</span></button>`;
        })
        .join('');
    }

    /** 민족 딱지의 세로 자리(줄이 접혀 높이가 0이면 함께 사라짐)와, 딱지가 끼워진 민족 칸의 이름 자리: 이름은 딱지가 없는 가장 긴 구간의 가운데로 옮겨 딱지에 덮이지 않게 */
    _placePchips(tr) {
      if (!tr.el || tr.folded) return;
      const chips = tr.pchips || [];
      const els = tr.el.querySelectorAll('.tl-pchip');
      chips.forEach((c, i) => {
        const el = els[i];
        if (!el) return;
        const gone = tr.hiddenRows.has(c.r) || !tr.rowHs[c.r];
        el.classList.toggle('is-collapsed', gone);
        el.style.top = `${tr.rowTop[c.r]}px`;
        el.style.height = `${gone ? 0 : tr.rowHs[c.r]}px`;
      });
      const chipRows = new Set(chips.map(c => c.r));
      /* 대범위 가지가 민족 묶음 가운데에 끼워졌으면(본국 줄 아래) 가지의 왼쪽 칸(전체 폭)이 그 줄들의 민족 칸을 덮으므로, 민족 칸 이름도 가지 밖의 구간으로 비켜 갑니다 */
      const scopeRows = new Set();
      for (const b of tr.scopeBranches || []) if (!b.board) for (let r = b.first; r < b.first + b.count; r++) scopeRows.add(r); // 집합 보기의 테두리는 왼쪽 칸이 없음 — 칩 이름을 비키게 하지 않음
      const boxes = tr.el.querySelectorAll('.tl-people');
      /* 세로 글 한 자의 높이 · 위아래 여유: 민족 칸은 11.8 · 2, 집합 보기의 칩(굵은 원래 트랙 칩 · 줄이 짧은 판)은 넉넉히 12.5 · 8 — 반쯤 잘린 글자가 없게 (설계 결정 2의 규칙) */
      const [perCh, padCh] = tr.board ? [12.5, 8] : [11.8, 2];
      tr.groups
        .filter(gp => gp.name)
        .forEach((gp, i) => {
          const el = boxes[i];
          if (!el) return;
          const blocked = r => (!gp.scope && gp.depth === this.depth - 1 && chipRows.has(r)) || (!gp.scope && scopeRows.has(r)); // 대범위 칸은 딱지에 막히지 않음 (한 단이면 딱지가 가는 띠 — _pchipsHTML)
          let has = false;
          let side = false;
          if (!gp.folded) for (let r = gp.first; r < gp.first + gp.count; r++) if (!tr.hiddenRows.has(r)) {
            if (blocked(r)) has = true;
            if (gp.scope && chipRows.has(r)) side = true;
          }
          el.classList.toggle('is-side', side && this.depth > 1); // 넓은 대범위 칸: 딱지가 오른쪽 끝 단에 끼워지면 이름은 그 왼쪽으로
          el.classList.toggle('is-thin', side && this.depth === 1); // 한 단뿐인 대범위 칸: 오른쪽 가장자리의 가는 딱지 왼쪽으로
          const at = has && this._peopleSpan(tr, gp);
          el.classList.toggle('has-pchip', !!at);
          const span = el.querySelector('span');
          if (!at) {
            /* 딱지가 없어도 이름이 칸에 다 들지 않으면(낮은 줄 · 조감) 같은 규칙으로 줄임 — 세로 글이 칸 밖으로 넘치지 않게 (접힌 묶음은 가로 글 · 말줄임) */
            const all = !gp.folded && this._peopleSpan(tr, gp);
            const text = !all ? gp.name : shortName(gp.name, s => [...s].length * perCh + padCh <= all.height);
            if (span && span.textContent !== text) span.textContent = text;
            if (text === gp.name) delete el.dataset.cut;
            else el.dataset.cut = '1';
            return;
          }
          /* 이름의 자리: 막히지 않은 줄들의 구간을 줄 사이 틈까지 넓혀(앞의 막힌 줄 아랫변 ~ 다음 막힌 줄 윗변, 없으면 칸의 끝) 가장 긴 것 */
          let best = null;
          let run = null;
          let edge = at.top; // 앞의 막힌 줄의 아랫변 (없으면 칸의 위)
          const close = bottom => {
            if (!run) return;
            run.bottom = bottom;
            if (!best || run.bottom - run.top > best.bottom - best.top) best = run;
            run = null;
          };
          for (let r = gp.first; r < gp.first + gp.count; r++) {
            if (tr.hiddenRows.has(r)) continue;
            if (blocked(r)) {
              close(tr.rowTop[r]);
              edge = tr.rowTop[r] + tr.rowHs[r];
            } else if (!run) run = { top: edge };
          }
          close(at.top + at.height);
          /* 그래도 이름(세로 글 한 자 ≈ 11.8px: 10.5px 글자 + 자간 .12em)이 들어가지 않으면 첫 글자만, 그것도 안 되면 비움 — 칸 밖으로 잘리지 않게 (딱지의 fits와 같은 규칙) */
          const h = best ? best.bottom - best.top : 0;
          const fits = s => [...s].length * perCh + padCh <= h;
          const text = shortName(gp.name, fits); // 들지 않으면 뜻이 남는 차례로 줄이고, 그래도 안 되면 글 없이 (shortNames — 한 글자로 자르지 않음)
          if (span && span.textContent !== text) span.textContent = text;
          if (text === gp.name) delete el.dataset.cut;
          else el.dataset.cut = '1';
          el.style.setProperty('--lt', `${best ? best.top - at.top : 0}px`);
          el.style.setProperty('--lh', `${h}px`);
        });
    }

    /** 줄의 세로 중심 (줄마다 높이가 다를 수 있습니다) */
    /** 건국·멸망 네모와 승계선이 닿는 높이: 글줄이 둘 이상이면 두 글줄 사이, 하나면 글줄 가운데 */
    _anchorY(tr, row) {
      const g = (tr.geos && tr.geos[row]) || tr.geo;
      if (this._seogoOn()) return tr.rowTop[row] + TAG.holeY; // 서고: 구멍 · 꼬리 마름모의 높이 — 이름 색줄(14)의 세로 가운데 7 (새 앱 links.dart anchorY)
      return tr.rowTop[row] + (g.lines > 1 ? g.textTop + g.lineH : g.textTop + g.lineH / 2);
    }

    /** 띠의 건국·멸망 표시 위치 — 띠 안쪽에 둡니다. fc/ec = 가운데 x, showF/showE = 그릴지.
        띠가 좁아 두 네모가 겹치면 건국 네모 하나만 가운데에, 네모가 들어갈 폭도 없으면 그리지 않습니다.
        이음매: 같은 줄에서 곧바로 이어지는 승계 쌍(chainRows의 _seamL · _seamR)의 이음매 쪽 네모는 틈에 따라 더 안으로 비켜 앉아(맞닿으면 3px · 직접이 아닌 승계면 6px — seamPush · seamWide)
        두 네모 사이에 다리가 놓일 자리를 냅니다. W = 네모를 그릴 폭(화면 · 그림 내보내기) */
    _squares(p, X, lines = 2, W = this.W || Infinity) {
      const x1 = X(bandStart(p)) - (p.startUnknown ? FADE : 0);
      const x2 = X(bandEnd(p)) + (p.endUnknown ? FADE : 0);
      if (this._bird) return { x1, x2, fc: x1, ec: x2, showF: false, showE: false }; // 조감에는 네모가 없음 — 승계선은 띠 끝 가운데에 닿음 (_linkPlan)
      if (this.seogo) {
        /* 서고(새 앱 links.dart · 설계 4-1 '구멍과 꼬리 마름모'): 건국 · 멸망 네모 대신 구멍(왼쪽 끝에서 7 — 이름 색줄 안 · 띠가 16px 이상일 때)과 꼬리 마름모(오른쪽 끝에서 7 — 구멍과 떨어져 설 30px 이상일 때).
           미정인 끝은 사라지는 꼬리라 제 끝 해에. 이음매에서도 비켜 앉지 않음 */
        const w = x2 - x1;
        const fc = p.startUnknown ? X(p.start) : x1 + TAG.holeX;
        const ec = p.endUnknown ? X(p.endY) : x2 - TAG.diamondX;
        const showF = w >= 16 && (p.startUnknown || (x1 >= -1 && fc + TAG.holeR <= W + 0.5));
        const showE = w >= 30 && !p.ongoing && (p.endUnknown || (x2 <= W + 1 && ec - TAG.diamondHalf >= -0.5));
        return { x1, x2, fc, ec, showF, showE };
      }
      const half = G.sq / 2;
      const m = G.bw + 2 + half;
      const mL = m + (p._seamL ? seamPush(x1 - X(bandEnd(p._seamL)), seamWide(p._seamL, p)) : 0);
      const mR = m + (p._seamR ? seamPush(X(bandStart(p._seamR)) - x2, seamWide(p, p._seamR)) : 0);
      let fc = p.startUnknown ? X(p.start) : Math.max(X(p.start), x1 + mL);
      let ec = p.endUnknown ? X(p.endY) : Math.min(X(p.endY), x2 - mR);
      let showF = true;
      let showE = !p.ongoing;
      /* 글줄이 하나면 네모가 사건 점과 같은 글줄에 있으므로, 네모 사이에 점 하나 놓을 자리(약 42px)가 없으면 멸망 네모를,
         건국 네모 옆에도 자리(약 29px)가 없으면 둘 다 생략합니다 — 멀리서 볼 때 점과 네모가 포개지지 않게
         (점은 건국 네모 오른쪽 8px·멸망 네모 왼쪽 10px 밖에, 띠 끝에서 9px 안에 놓입니다: _placeRow의 avoid) */
      const w = x2 - x1;
      if (lines === 1 && w < 42) showE = false;
      if ((lines === 1 && w < 29) || w < G.sq + 2 * (G.bw + 1)) {
        showF = showE = false;
        fc = ec = (x1 + x2) / 2;
      } else if (showE && ec - fc < G.sq + 1) {
        fc = ec = Math.min(Math.max((fc + ec) / 2, x1 + m), x2 - m); // 네모 하나뿐인 좁은 띠: 이음매 비키기 없이 띠 안쪽 여백만 (비키면 반대쪽 테두리에 걸림)
        showE = false;
      }
      /* 화면 안에 온전히 들어오는 것만 (반쯤 잘린 네모는 그리지 않음) */
      showF = showF && X(p.start) >= -1 && fc - half >= -0.5 && fc + half <= W + 0.5;
      showE = showE && X(p.endY) <= W + 1 && ec - half >= -0.5 && ec + half <= W + 0.5;
      return { x1, x2, fc, ec, showF, showE };
    }

    /** 조감의 띠 안 단추 (소속 펼치기 ▸n · 할거 모아 보기 ▸ 〈성격〉 n): 이름 뒤에 높이 10 · 8.5px 글자로 — 자리는 띠 시작에 고정(이름처럼 — 화면 가장자리를 따라오지 않음), 들어가지 않으면 없음.
        조감에서도 소속을 펼치고 대범위를 켤 수 있게. 모양 c(8px)는 자리가 없어 없음(필터의 대범위 칩 · 상세 · 다른 밀도에서). 차지한 구간(둘레 포함)은 zones에 — 점 · 알약을 두지 않음.
        그림 내보내기는 단추를 그리지 않되 같은 구간을 비워 점 자리가 화면과 같게 (bnR = 띠 안 이름의 오른쪽 끝 — 이름이 없으면 없음) */
    _birdBtns(tr, p, X, W, x2, zones, bnR) {
      if (!this._bird || !this._bird.name || bnR == null) return '';
      const g = (tr.geos && tr.geos[p._row]) || tr.geo;
      const end = p.endUnknown ? X(p.endY) : x2;
      let out = '';
      const nMem = (p.members || []).filter(m => m.track === tr.id && m.singleHost && !m.groupUid && m.polityKind !== 'overlay' && !(m._scope && m._host !== p)).length; // _drawTrack의 소속 단추와 같은 셈
      if (nMem) {
        const open = this.expandedHosts.has(p.uid);
        const memTxt = `${open ? '▾' : '▸'}${nMem}`;
        const memW = textWidth(memTxt, 8.5, 600) + 8;
        const bx = bnR + 4;
        if (bx + memW <= end - BIRD_NAME.inset) {
          out += `<button type="button" class="tl-mem is-bird${open ? ' is-open' : ''}" data-k="m:${esc(p.uid)}" data-fold-members="${esc(p.uid)}" data-row="${p._row}" style="left:${cx(bx)}px;top:${cx((g.lineH - 10) / 2)}px;--c:${p.color}" title="${esc(`${p.name}에 딸린 정권·조직 ${nMem}개 — ${open ? '접기' : '펼치기'}`)}">${esc(memTxt)}</button>`;
          zones.push([bx - BIRD_NAME.clear, bx + memW + BIRD_NAME.clear]);
        }
      }
      return out + this._scopeBtnsHTML(tr, p, X, W, end, g, zones, null);
    }

    /** 조감의 띠 안 이름: 띠 시작(미정이면 사라지는 꼬리 안쪽의 제 시작)에서 BIRD_NAME.inset 안쪽에 고정 — 들 폭은 띠 전체(화면에 잘린 폭이 아님 — 옆으로 옮겨도 같음).
        들어가는 대로 이름 → 첫 글자 → 없음. 문턱은 두 개(원칙 ⑨): 더 긴 모양으로 바뀌려면 8px(양옆 4px)의 여유가 더 있어야 하고, 지금 모양은 딱 들어가는 동안 그대로 —
        prev = 지난 그리기의 기억(없으면 문턱 하나 — 맨 처음 · 그림 내보내기), memo = 이번 기억을 적을 곳 → { l, w, mode, text } */
    _birdName(p, X, prev = null, memo = null) {
      const l = (p.startUnknown ? X(p.start) : X(bandStart(p))) + BIRD_NAME.inset;
      const room = (p.endUnknown ? X(p.endY) : X(bandEnd(p))) - BIRD_NAME.inset - l;
      const was = prev ? prev.get(p.uid) : undefined;
      const RANK = { '': 0, short: 1, full: 2 };
      const fit = (t, mode) => {
        const w = textWidth(t, BIRD_NAME.size, BIRD_NAME.wt);
        return room >= w + (was !== undefined && RANK[mode] > RANK[was] ? 8 : 0) ? w : -1;
      };
      let mode = '';
      let w = fit(p.name, 'full');
      if (w >= 0) mode = 'full';
      else if ((w = fit(p.name.slice(0, 1), 'short')) >= 0) mode = 'short';
      if (memo) memo.set(p.uid, mode);
      return { l, w: Math.max(0, w), mode, text: mode === 'full' ? p.name : mode === 'short' ? p.name.slice(0, 1) : '' };
    }

    /** 건국 · 멸망 네모의 자리(네모 + SQ_CLEAR)를 사건 글자가 비켜 가게: 줄 row의 네모가 닿는 글줄들 — 글줄이 하나면 그 글줄(네모가 글줄 가운데에 있어 점도 밖으로 밀림 — noDot),
        둘 이상이면 네모가 걸친 첫째 · 둘째 글줄(두 글줄 사이에 있어 위아래 글자의 칸에 1px씩 걸침 — 점은 글줄 가운데라 닿지 않음). 화면(_drawTrack)과 그림 내보내기(toSVG)가 같이 씀 */
    _sqZones(sq, lanes, noDot) {
      const half = G.sq / 2 + SQ_CLEAR;
      for (const [c, on, dir] of [[sq.fc, sq.showF, 1], [sq.ec, sq.showE, -1]]) {
        if (!on) continue;
        for (const res of lanes) res.push([c - half, c + half, noDot ? 2 : 1]); // 셋째 값: 1 = 글줄 둘 이상 — 글자만 비킴(네모는 두 글줄 사이라 점(글줄 가운데)과는 3.5px 떨어져 있으므로 점이 네모 바로 위아래에 있어도 글자가 네모를 비키면 이름을 붙임), 2 = 글줄 하나 — 점과 글자의 실제 가장자리가 비킴 (_placeRow의 blocks)
        if (noDot) noDot.push([c - half, c + half, dir]);
      }
    }

    /** 사건 시작의 정밀도가 덮는 구간 [t0, t1] (연도만 → 그해, 달까지 → 그달 …). 그리지는 않고, 점의 풍선 글에 모른다는 말을 붙일 문턱(_pointAt의 f)에만 씁니다 */
    _precSpan(e) {
      if (e._ps !== undefined) return e._ps;
      let sp = null;
      if (!e.startUnknown && HT.cal) {
        const at = HT.atOf(e, 'start');
        const r = at ? HT.cal.parse(at) : null;
        e._psCent = !!(r && r.span); // 세기 · 반세기 · 세기의 셋째 — 괄호의 '달 눈금' 문턱을 받지 않음
        if (at) sp = HT.cal.precSpan(r);
        else if (Number.isInteger(e.start)) sp = [e.start, e.start === -1 ? 0 : e.start + 1]; // 기원전 1년은 빈 0년 자리 앞에서
      }
      e._ps = sp;
      return sp;
    }

    /** 날짜를 정확히 모르는 점 사건이 놓이는 해 — 정밀도 구간(연도만 → 그해 · 달까지 → 그달 · 날까지 → 그날 · 세기로 적음 → 그 구간)의 가운데,
        또는 사건에 적은 자리(spot — 0 처음 ~ 1 끝 · 같은 해 사건이 쌓여 겹칠 때 옮김)에 하나로 섭니다. 확대해도 옮겨 가지 않습니다
        (감독 결정 2026-10-14 "일 기준까지 확대해도 범위로 진행하지 말 것" → "중간으로 해 주고 사건에서 위치를 조정할 수 있게").
        구간이 없으면(끝이 있는 사건 · 미정 · 날짜를 다 적음) 시작 그대로. 내보내기(prototype/scripts/export/events.mjs)가 이 해를 사건의 시작 분으로 싣습니다 */
    _placeAt(e) {
      const sp = e.endY > e.start ? null : this._precSpan(e);
      if (!sp) return e.start;
      const s = Number.isFinite(e.spot) ? HT.clamp(e.spot, 0, 0.99) : 0.5; // 1(끝)은 다음 구간의 첫머리가 되지 않게 조금 앞
      return sp[0] + (sp[1] - sp[0]) * s;
    }

    /** 점 사건이 놓일 해(_placeAt)와 '모름' 글의 문턱 f(0~1): f는 정밀도 구간이 화면에서 넉넉해진 정도(14px → 50px)로, 점의 풍선 글 뒤에 모른다는 말을 붙일지에만 씁니다 */
    _pointAt(e, X) {
      const sp = e.endY > e.start ? null : this._precSpan(e);
      if (!sp) return { t: e.start, f: 0, sp: null };
      const w = X(sp[1]) - X(sp[0]);
      const u = HT.clamp((w - 14) / 36, 0, 1);
      return { t: this._placeAt(e), f: u * u * (3 - 2 * u), sp };
    }

    /** 사건이 차지하는 해 범위 [lo, hi] — 연대 폭 · 이설까지. 날짜를 모르는 점 사건은 놓인 해(_placeAt) 하나이고(그해 전체로도, 적은 첫머리까지도 넓히지 않음),
        연대 폭 · 이설이 그 밖으로 뻗으면 그만큼만 */
    _extent(e) {
      const t = this._placeAt(e);
      if (t === e.start) return [e.spanMin ?? e.start, e.spanMax ?? e.endY];
      const lo = e.spanMin != null && e.spanMin < e.start ? Math.min(e.spanMin, t) : t;
      const hi = e.spanMax != null && e.spanMax > e.endY ? Math.max(e.spanMax, t) : t;
      return [lo, hi];
    }

    _rowMid(tr, row) {
      const cut = tr.hiddenRows && tr.hiddenRows.has(row) ? 0 : (tr.rowCut && tr.rowCut[row]) || 0;
      return tr.rowTop[row] + ((tr.rowHs[row] ?? tr.rowH) - cut) / 2;
    }

    /** 한 줄의 사건 배치. 규칙: ① 글자는 다른 글자·이름표와 겹치지 않는다 ② 글자는 다른 사건의 점을 덮지 않는다
        ③ 이름이 붙지 않은 점은 글자가 없는 글줄에 놓는다. 자리가 없으면 이름을 숨기고 점만 남깁니다(마우스를 올리면 이름) */
    _placeRow(list, X, W, tr, ctx, row) {
      const g = (tr.geos && tr.geos[row]) || tr.geo;
      const L = g.lines;
      /* 분류별 글줄이면 사건은 제 분류의 글줄에만 (이름이 들어갈 자리가 없으면 점만) */
      const cats = tr.rowCats && tr.rowCats[row];
      const laneOf = e => (cats ? cats.indexOf(e.category || 'etc') : -1);
      const prio = e => (e.uid === this.selected ? 100 : 0) + (this.hiLayout && this.hiLayout.has(e.uid) ? 10 : 0) + (e.importance || 2);
      const res = (ctx.reserved && ctx.reserved[row]) || [];
      const subs = Array.from({ length: L }, (_, i) => (res[i] || []).slice());
      const out = [];
      const span = this.span();
      const minImp = ctx.minImp || (span > 2600 ? 99 : span > 1300 ? 3 : span > 500 ? 2 : 1); // 화면 그리기는 두 문턱으로 고른 값을 넘깁니다 (_draw · _past)
      if (tr.eventIndexByRow && list === tr.eventsByRow[row]) {
        const x0 = X(0), scale = X(1) - x0;
        const lo = (-10 - x0) / scale, hi = (W + 10 - x0) / scale;
        const epsilon = Math.max(1, Math.abs(lo), Math.abs(hi)) * Number.EPSILON * 8;
        list = intervalQuery(tr.eventIndexByRow[row], lo - epsilon, hi + epsilon);
      }
      const order = list
        .filter(e => {
          if (e.parentUid && !ctx.expanded.has(e.parentUid)) return false;
          const [lo, hi] = this._extent(e);
          return !(X(hi) < -10 || X(lo) > W + 10);
        })
        .sort((a, b) => prio(b) - prio(a) || a.start - b.start);
      /* 그리는 점은 제 정권 띠 안쪽에: 가장자리와 겹치지 않도록 (정확한 연도는 마우스를 올리면 나옵니다) */
      const inside = (e, x, m) => {
        const bb = ctx.bandBounds && ctx.bandBounds.get(e._place && e._place.polityUid);
        if (!bb) return x;
        const lo = bb[0] + m;
        const hi = bb[1] - m;
        return hi <= lo ? (bb[0] + bb[1]) / 2 : Math.min(hi, Math.max(lo, x));
      };
      /* 글줄이 하나뿐이면 건국·멸망 네모와 소속 단추가 같은 글줄에 있으므로, 점을 그 자리 밖으로 밀어냅니다.
         dir > 0 이면 오른쪽으로(글자가 오른쪽에 붙을 자리까지), dir < 0 이면 왼쪽으로(뒤집은 글자 자리까지) */
      const zones = ((ctx.noDot && ctx.noDot[row]) || []).slice().sort((a, b) => a[0] - b[0]);
      const avoid = (e, x) => {
        const at = inside(e, x, dotM);
        if (!zones.length) return at;
        const bb = ctx.bandBounds && ctx.bandBounds.get(e._place && e._place.polityUid);
        let free = [[bb ? bb[0] + dotM : -1e9, bb ? bb[1] - dotM : 1e9]].filter(([l, r]) => r >= l);
        for (const [a, b, dir, ln] of zones) {
          if (ln != null && laneOf(e) !== ln) continue; // 그 글줄의 점만 (분류별 글줄의 단추)
          const fa = dir > 0 ? a - 4.5 : a - 10; // 뒤집은 글자 자리까지
          const fb = dir > 0 ? b + 8 : b + 4.5; // 오른쪽 글자 자리까지
          free = free.flatMap(([l, r]) => (fb <= l || fa >= r ? [[l, r]] : [[l, fa], [fb, r]].filter(([u, v]) => v >= u)));
        }
        let best = at;
        let dist = Infinity;
        for (const [l, r] of free) {
          const c = Math.min(r, Math.max(l, at));
          if (Math.abs(c - at) < dist) {
            dist = Math.abs(c - at);
            best = c;
          }
        }
        return best;
      };
      /* 점의 반지름 3.5 + 둘레 3 + 테두리 1 — 띠 테두리 위에 점의 둘레가 얹히지 않게 */
      const dotM = 9;
      const pts = order.map(e => this._pointAt(e, X));
      const xs = order.map((e, i) => avoid(e, inside(e, X(pts[i].t), dotM)));
      const dotLine = order.map(e => laneOf(e)); // -1: 아직 정해지지 않음 → 모든 글줄에서 장애물 (분류별 글줄이면 처음부터 제 글줄)
      const DOT = 6; // 점의 반지름 + 여유
      const coversDot = (k, a, b, self) => {
        for (let j = 0; j < order.length; j++) {
          if (j === self) continue;
          const d = xs[j];
          if (Math.abs(d - xs[self]) < 1.5) continue; // 같은 해의 점은 원래 한자리
          if (d + DOT <= a || d - DOT >= b) continue;
          if (dotLine[j] === -1 || dotLine[j] === k) return true;
        }
        return false;
      };
      /* 이름 자리 t가 글줄의 차지한 구간(list)에 걸리는지: 보통 구간(다른 이름 · 단추 · 내림줄)은 이름 전체(l ~ r — 이름 사이 여백까지, 문턱 m)가 비키고,
         건국 · 멸망 네모 + 1.5px(_sqZones — 셋째 값)는 실제로 그려지는 것만 비키면 됨: 1 = 글줄 둘 이상인 줄 — 글자의 실제 가장자리(gl ~ gr)만(점은 글줄 가운데라 두 글줄 사이의 네모와 3.5px 떨어짐),
         2 = 글줄 하나인 줄 — 점 쪽 끝(l · r)부터 글자의 먼 가장자리까지(sl ~ sr — 문턱 m은 글자 쪽에만: 점은 네모 둘레 밖으로 밀려 네모와 늘 같은 거리라 문턱이 있으면 새로 붙는 이름이 영영 못 붙음). 예전에는 둘 다 이름 전체(이름 사이 여백까지)로 막아, 제 띠 시작 9px 안에 붙은 점 —
         6·25 전쟁 · 메이지 유신 · 중화인민공화국 수립처럼 건국 해의 사건 — 이 네모 바로 밑이라는 까닭만으로, 또 이음매에서 3px 비켜 앉은 네모 때문에 이름을 잃었음 (62ff5c7 ~) */
      const blocks = (list, t, m, tight = 0, shed = null) =>
        list.some(z => {
          const [a, b, sq, sa, sb, pill] = z;
          if (sq === 1) return a < t.gr && t.gl < b;
          if (sq === 2) return a < t.sr + (t.flip ? 0 : m) && t.sl - (t.flip ? m : 0) < b;
          const hit = (A, B, sA, sB) => (tight && sA != null ? sA < t.sr + tight + m && t.sl - tight - m < sB : A < t.r + m && t.l - m < B);
          if (!hit(a, b, sa, sb)) return false;
          if (!shed || !pill) return true;
          /* 막는 것이 이웃 이름의 알약뿐이면 그 이웃의 알약을 떼어 자리를 냅니다 (마지막 차례 — 이름을 잃는 것보다 이웃의 곁들임을 떼는 것이 나음).
             알약은 점 반대쪽 끝에 붙으므로 떼면 자리가 점 쪽으로만 줄어듦 — 이미 놓인 글자 · 점은 움직이지 않습니다. 걸린 이웃은 모아 두었다가 자리를 잡을 때에만 실제로 뗍니다 */
          const d = pill[1];
          if (pill[0] ? hit(a + d, b, sa + d, sb) : hit(a, b - d, sa, sb - d)) return true;
          shed.push(z);
          return false;
        });
      /* 둘째 차례의 좁힌 여백(tight): 첫째 차례에 자리를 못 찾은 이름은 다른 이름과의 사이를 이름 사이 여백(글자 ↔ 글자 13px) 대신 점 · 글자의 실제 가장자리(sa ~ sb)끼리 LAB_TIGHT px로 —
         이미 놓인 이름 · 점은 그대로 두고 비어 있는 틈에만 (겹침 없음). 예전에 접힌 하위 사건 수 알약을 이름 폭에 빼고 재던 동안 붙어 있던 이름이 알약을 제대로 재면서 빠지지 않게 */
      const LAB_TIGHT = 5;
      /* 이웃의 알약을 실제로 뗌: 차지한 구간(점 반대쪽 끝) · 그 이름의 자리 값(span · ink · solid)을 알약 폭만큼 줄이고 noCnt로 그리지 않게 (알약은 누르면 그대로 펼쳐지므로 이름을 잃는 것보다 나음) */
      const shedPill = z => {
        const [flip, d, own] = z[5];
        if (flip) { z[0] += d; z[3] += d; } else { z[1] -= d; z[4] -= d; }
        Object.assign(own, { noCnt: true, span: [z[0], z[1]], solid: [z[3], z[4]], ink: flip ? [own.ink[0] + d, own.ink[1]] : [own.ink[0], own.ink[1] - d] });
        z[5] = null;
      };
      const late = []; // 연도를 떼면 들 수 있는 이름 (둘째 차례)
      order.forEach((e, i) => {
        const pk = `${e.uid}:${e._pi || 0}`;
        const x = xs[i];
        if (ctx.seen && x >= -4 && x <= W + 4) ctx.seen.add(pk); // 이번 그리기에서 이름 자리를 따져 본 사건 (화면 밖의 것은 기억을 그대로 둡니다 — _drawTrack)
        const x2 = X(e.endY);
        const child = !!e.parentUid;
        const ranged = x2 - X(e.start) > 2;
        const text = this.titleFor(e, tr.id);
        const localName = e._sec && this.lens === 'local' && text !== e.title;
        const item = { e, x, x2, label: false, flip: false, sub: 0, child, sec: !!e._sec, text, ranged, rx: inside(e, X(e.start), 5), rx2: inside(e, x2, 5), clamp: v => inside(e, v, 5), pt: pts[i] };
        const need = child ? Math.min(minImp, 2) : minImp;
        if ((!item.sec || localName) && (e.importance || 2) >= need && x >= -4 && x <= W + 4 && minImp < 99) {
          const size = child ? g.font - 0.5 : g.font;
          const yr = L > 1 && !child ? this._labelDate(e) : '';
          const kids = e.children && e.children.length && !ctx.expanded.has(e.uid) ? e.children.length : 0; // 접힌 하위 사건 수 알약(.cnt — 사이 6 + 앞 여백 4 + 안 여백 8)도 이름 폭에 — 빼고 재면 알약만큼 뒤의 연도가 네모 · 이웃 글자에 걸침
          const wOf = (y, kn = kids) => textWidth(text, size) + (y ? textWidth(y, size - 1) + 6 : 0) + (kn ? textWidth(String(kn), size * 0.82) + 18 : 0) + (child ? 14 : 17);
          const bounds = ctx.bandBounds.get(e._place && e._place.polityUid) || [-2, W + 2];
          /* 제 띠 안(lo ~ hi)은 이름 전체(l ~ r — 이름 뒤의 빈 여백까지)로 재지만, 화면(그림) 양 끝은 점 · 글자(sl ~ sr — 이름 뒤의 여백은 뺀 것)만 들면 됩니다:
             띠가 화면 밖으로 이어지는데도 끝의 이름이 보이지 않는 여백 몇 px 때문에 통째로 사라지던 것 (한양 천도 — 이음매로 점이 3px 안으로 들어가 이름 끝이 W + 2를 0.5px 넘김) */
          const lo = bounds[0] - 3;
          const hi = bounds[1] + 3;
          /* 오른쪽에 먼저, 안 되면 왼쪽(뒤집기)에 — 지난 프레임의 방향·글줄이 아직 되면 그대로 (끌 때 이름이 뒤집히며 부들거리지 않게) */
          const prev = ctx.prevLab ? ctx.prevLab.get(pk) : null;
          const first = child && L > 1 ? 1 : 0;
          const lane = laneOf(e);
          let ks = lane >= 0 ? [lane] : Array.from({ length: L }, (_, n) => (first + n) % L);
          if (prev && lane < 0 && ks.includes(prev.sub)) ks = [prev.sub].concat(ks.filter(k => k !== prev.sub));
          /* 이름 자리의 문턱도 두 개: 새로 붙는 이름은 양옆으로 4px의 여유가 더 있어야 하고, 이미 붙어 있던 이름은 딱 들어가는 동안 그대로 — 자리가 빠듯한 경계에서 이름이 붙었다 떨어졌다 하지 않습니다 (겹침은 어느 쪽에서도 없음) */
          const m = ctx.prevLab && !prev && e.uid !== this.selected ? 4 : 0; // 고른 사건의 이름은 기다리지 않습니다
          /* 연도까지 붙인 이름(글줄 둘 이상인 줄)이 어느 자리에도 들지 않으면, 모든 사건이 자리를 잡은 뒤(둘째 차례 — late) 연도를 떼고 한 번 더 — 이름을 잃는 것보다 연도를 떼는 것이 나음(연도는 올리면 나옴):
             네모 · 이웃 점 사이에 끼여 연도 몇 글자 때문에 이름이 통째로 숨던 것. 연도를 뗀 이름이 다시 연도를 붙이려면 4px 여유가 더 있어야(문턱 둘 — 붙였다 뗐다 하지 않게).
             자리(tries): l ~ r = 점까지 포함한 이름 전체(이름 사이 여백까지) · tl ~ tr = 글자 쪽(점과 그 둘레를 뺀 것 — 다른 점을 덮는지) ·
             gl ~ gr = 글자의 실제 가장자리(.tl-ev: 점(dotW)은 x − 3.5부터(뒤집으면 뒤 여백 2px 안쪽에서 끝남) · 점 ↔ 글자 6px — 0.5px 넉넉히) · sl ~ sr = 점 쪽 끝 ~ 글자의 먼 가장자리 (네모 자리 · 좁힌 여백 — blocks) */
          const dotW = e.startUnknown || e.endUnknown ? 10 : e.shared ? 9 : child ? 5 : 7; // .tl-ev .d의 폭 (is-unk · is-shared · is-child — common.css)
          const place = (y, mm, tight = 0, kn = kids, shed = 0) => {
            const w = wOf(y, kn);
            const pw = kn ? textWidth(String(kn), size * 0.82) + 18 : 0; // 알약 한 칸 — 이 이름이 나중에 자리를 내줄 때 떼는 폭 (shedPill)
            const ink = textWidth(text, size) + pw + (y ? textWidth(y, size - 1) + 6 : 0); // 글자 줄의 실제 폭 (이름 · 알약 · 연도 — 사이 6px)
            const tries = [
              { flip: false, l: x - 7, r: x + w, tl: x + 6, tr: x + w, gl: x + dotW + 2, gr: x + dotW + 3 + ink, sl: x - 7, sr: x + dotW + 3 + ink },
              { flip: true, l: x - w, r: x + 9, tl: x - w, tr: x - 6, gl: x - dotW - 5 - ink, gr: x - dotW - 4, sl: x - dotW - 5 - ink, sr: x + 9 },
            ];
            if (prev && prev.flip) tries.reverse();
            for (const t of tries) {
              if (t.l - mm < lo || t.r + mm > hi || t.sl - mm < 0 || t.sr + mm > W) continue;
              for (const k of ks) {
                const sh = shed ? [] : null;
                if (blocks(subs[k], t, mm, tight, sh) || (tight ? coversDot(k, t.gl - 2, t.gr + 2, i) : coversDot(k, t.tl, t.tr, i))) continue; // 좁힌 여백에서는 다른 점도 글자의 실제 가장자리에서 2px(점의 둘레 밖 1.5px)까지
                if (sh) for (const z of sh) shedPill(z);
                subs[k].push([t.l, t.r, 0, t.sl, t.sr, pw ? [t.flip, pw, item] : null]); // 셋째 값 0 = 이름(보통 구간) · 넷째 · 다섯째 = 점 · 글자의 실제 가장자리(둘째 차례의 좁힌 여백) · 여섯째 = 떼어 줄 수 있는 알약 (뒤집힘 · 폭 · 그 이름)
                Object.assign(item, { label: true, flip: t.flip, sub: k, span: [t.l, t.r], ink: [t.gl, t.gr], solid: [t.sl, t.sr], yr: y, noCnt: !!kids && !kn }); // ink · solid: 글자의 실제 가장자리 · 점 쪽 끝 ~ 글자 끝 (검사 — dev-smoke ㊶)
                if (ctx.newLab) ctx.newLab.set(pk, { flip: t.flip, sub: k, noYr: !!yr && !y });
                dotLine[i] = k;
                return true;
              }
            }
            return false;
          };
          if (!place(yr, yr && prev && prev.noYr ? Math.max(m, 4) : m)) late.push(() => (yr && place('', m)) || place(yr, m, LAB_TIGHT) || (yr && place('', m, LAB_TIGHT)) || (kids && place('', m, LAB_TIGHT, 0)) || place('', m, LAB_TIGHT, 0, 1)); // 연도를 뗀 이름 · 좁힌 여백은 모든 사건이 제 모양으로 자리를 잡은 뒤에(둘째 차례 — 첫째 차례의 이름이 들던 자리를 빼앗지 않게), 마지막으로 하위 사건 수 알약도 떼고(누르면 펼쳐짐 — 알약만 없음), 그래도 안 되면 자리를 막는 이웃 이름의 알약까지 (shed — 이웃도 이름은 그대로)
        }
        if (!item.label) {
          // 이름 없는 점: 제 분류의 글줄, 아니면 그 자리에 글자가 없는 글줄로
          let k = laneOf(e);
          if (k < 0) {
            k = -1;
            for (let n = 0; n < L; n++) if (!overlaps(subs[n], x - DOT, x + DOT)) { k = n; break; }
            /* 빈 글줄이 없으면 적어도 단추 · 네모 자리(reserved — 점을 덮는 것)가 아닌 글줄로 (글자 밑의 점은 글자의 종이빛 사이로 보이지만 단추 밑의 점은 가려짐) */
            if (k < 0) for (let n = 0; n < L && k < 0; n++) if (!overlaps(res[n] || [], x - DOT, x + DOT)) k = n;
            if (k < 0) k = 0;
          }
          item.sub = k;
          dotLine[i] = k;
        }
        out.push(item);
      });
      for (const f of late) f(); // 둘째 차례: 연도를 뗀 이름 — 자리 · 이름 사이 여백 · 점 덮기를 첫째 차례와 같게 따지므로, 이미 놓인 이름 · 점을 건드리지 않고 이름만 늘어남
      /* 점이 제 띠 안쪽(테두리 1px 안)에 다 들지 않는 좁은 띠의 점 — 띠 밖으로 나가지 않게 (dotR = 점의 반지름 + 둘레: 화면의 .d 크기 표와 같게):
         보통 밀도는 조감 크기의 작은 점(it.sm → .is-sm — 5px + 둘레 2px)으로 그리고, 그것도 안 들 때만 숨깁니다. 조감은 처음부터 작은 점이라 안 들면 숨김.
         조감은 띠 안 이름 · 단추 자리(ctx.bird.zones — 둘레 포함)에 걸린 점도 옮기지 않고 숨기고(자리는 자료가 정함 — 원칙 ①), 띠가 그려지지 않는 정권(바탕 문화)의 점도 (그 밖 줄은 그대로) */
      const bird = ctx.bird || null;
      const zonesB = (bird && bird.zones && bird.zones[row]) || [];
      const bandOf = it => ctx.bandBounds && ctx.bandBounds.get(it.e._place && it.e._place.polityUid);
      const dotR = (it, sm = !!bird) => {
        const e = it.e;
        if (sm) return e.shared || e.startUnknown || e.endUnknown || it.child ? 3.5 : 4.5;
        return e.shared ? 7.5 : e.startUnknown || e.endUnknown ? 5 : it.child ? 4.5 : 6.5;
      };
      const edge = bird ? 1 + STUB + 0.5 : 1; // 띠 바깥 끝에서 점(둘레)까지 적어도: 테두리 1 — 조감은 승계선의 짧은 끝(STUB)과 0.5px 더 (좁은 띠 가운데의 점이 짧은 끝 · 문에 걸리지 않게)
      for (const it of out) {
        if (it.label) continue;
        const bb = bandOf(it);
        const room = bb ? bb[1] - bb[0] - 2 * edge : Infinity;
        if (bb ? room < 2 * dotR(it) : bird && row !== bird.common) {
          if (!bird && room >= 2 * dotR(it, true)) it.sm = true; // 좁은 띠(점은 띠 가운데 — inside): 작은 점으로
          else it.hidden = it.off = true;
        } else if (zonesB.length && overlaps(zonesB, it.x - dotR(it), it.x + dotR(it))) it.hidden = it.off = true;
      }
      /* 겹친 점 정리 — 멀리서 볼 때 점이 포개져 지저분해지지 않게:
         ① 이름 붙은 사건의 점과 거의 같은 자리(CL px 안)에 떨어진 점은 그 사건에 겹쳐 쌓습니다 (점이 포갠 동전처럼 보이고, 올리면 목록)
         ② 이름 없는 점끼리 가까우면 개수 알약 하나로 묶습니다. 알약이 차지할 폭까지 따져 옆 점·알약과도 닿지 않게 이어 묶고,
            묶인 점들의 실제 자리는 알약 아래 가는 선과 눈금으로 남깁니다 (정확한 시점을 잃지 않게) */
      /* 묶음의 문턱도 두 개: 11px 안으로 붙으면 묶이고, 한 번 묶인 것끼리는 14px(알약 곁은 5px)까지 벌어져야 풀립니다 — 경계에서 멈춰도 묶였다 풀렸다 하지 않게.
         떨어져 있는 점은 늘 11px 넘게 떨어져 있으므로 겹침은 어느 쪽에서도 없습니다. 기억(prevClu)은 화면 그리기에만 있습니다 */
      const CL = 11;
      const CL_OUT = 14;
      const pkOf = it => `${it.e.uid}:${it.e._pi || 0}`;
      const was = ctx.prevClu && ctx.prevClu.size ? ctx.prevClu : null;
      const together = (a, b) => {
        if (!was) return false;
        const id = was.get(pkOf(a));
        return id != null && id === was.get(pkOf(b));
      };
      const mark = (it, id) => ctx.newClu && ctx.newClu.set(pkOf(it), id);
      const pillS = n => 9 + 5 * String(n).length; // 작은 알약: 높이 10 · 8px 글자 · 둘레 없이 안쪽 1px 테 (조감, 그리고 보통 밀도의 좁은 띠 — .is-sm)
      const pillW = n => (bird ? pillS(n) : 13 + 6.2 * String(n).length);
      /* 묶음은 한 띠 안에서만 (같은 줄의 이웃한 띠 — 조선과 대한제국 — 의 점이 한 알약으로 묶이면 알약 아래 자리 선이 띠 경계를 넘어 이웃 띠로 감) */
      const sameBand = (a, b) => bandOf(a) === bandOf(b);
      for (const it of out) {
        if (it.label || it.off) continue;
        const host = out.find(h => h.label && h.sub === it.sub && sameBand(h, it) && Math.abs(h.x - it.x) < (together(h, it) ? CL_OUT : CL));
        if (!host) continue;
        (host.more = host.more || []).push(it);
        it.hidden = host;
        mark(host, `a:${pkOf(host)}`);
        mark(it, `a:${pkOf(host)}`);
      }
      out.clusters = [];
      const byLine = new Map();
      for (const it of out) if (!it.label && !it.hidden) (byLine.get(it.sub) || byLine.set(it.sub, []).get(it.sub)).push(it);
      for (const [sub, list] of byLine) {
        list.sort((a, b) => a.x - b.x);
        const extent = run => {
          if (run.length === 1) return [run[0].x - 5, run[0].x + 5];
          const l = run[0].x;
          const r = run[run.length - 1].x;
          const w = Math.max(r - l + 12, pillW(run.length));
          return [(l + r) / 2 - w / 2, (l + r) / 2 + w / 2];
        };
        const runs = [];
        let run = [list[0]];
        for (let i = 1; i < list.length; i++) {
          const it = list[i];
          const last = run[run.length - 1];
          const tg = together(it, last);
          if (sameBand(it, last) && (it.x - last.x < (tg ? CL_OUT : CL) || it.x - 5 < extent(run)[1] + (tg ? 5 : 2))) run.push(it);
          else {
            runs.push(run);
            run = [it];
          }
        }
        runs.push(run);
        /* 알약끼리 너무 붙으면 한 번 더 합칩니다 */
        for (let i = 1; i < runs.length; i++) {
          const a = runs[i - 1];
          if (sameBand(runs[i][0], a[a.length - 1]) && extent(runs[i])[0] < extent(a)[1] + (together(runs[i][0], a[a.length - 1]) ? 5 : 2)) {
            runs[i - 1] = a.concat(runs[i]);
            runs.splice(i--, 1);
          }
        }
        for (const r of runs) {
          if (r.length < 2) continue;
          const lead = r.slice().sort((a, b) => prio(b.e) - prio(a.e) || a.e.start - b.e.start)[0];
          const l = r[0].x;
          const rr = r[r.length - 1].x;
          let w = pillW(r.length);
          let sm = false;
          /* 알약 자리: 가운데가 글자와 겹치면 묶음 범위 안에서 비켜 둡니다 */
          let cx0 = (l + rr) / 2;
          for (const c of [cx0, l + w / 2 - 5, rr - w / 2 + 5]) {
            if (!overlaps(subs[sub] || [], c - w / 2, c + w / 2)) {
              cx0 = c;
              break;
            }
          }
          /* 알약(과 둘레)은 대표 사건의 띠 안쪽에 — 보통 밀도는 제 크기가 안 들면 작은 알약(sm → .is-sm)으로, 그것도 안 들면 그리지 않음(묶인 점도 — 띠 밖으로 나가지 않게),
             조감은 띠 안 이름 · 단추 자리에 걸리면 숨김 */
          const bb = bandOf(lead);
          let pm = bird ? 5 : 4; // 띠 바깥 끝에서 알약 끝까지: 테두리 1 + 둘레(화면은 3px 종이빛 · 조감은 둘레 없이 승계선의 짧은 끝 3px을 비켜 · 보통 밀도의 작은 알약은 둘레 없이 1px 틈)
          if (bb) {
            if (!bird && bb[1] - bb[0] - 2 * pm < w && bb[1] - bb[0] - 4 >= pillS(r.length)) {
              w = pillS(r.length);
              pm = 2;
              sm = true;
            }
            const lo = bb[0] + pm + w / 2;
            const hi = bb[1] - pm - w / 2;
            if (hi < lo || (zonesB.length && overlaps(zonesB, Math.min(hi, Math.max(lo, cx0)) - w / 2, Math.min(hi, Math.max(lo, cx0)) + w / 2))) {
              r.forEach(it => (it.hidden = it.off = true));
              continue;
            }
            cx0 = Math.min(hi, Math.max(lo, cx0));
          } else cx0 = lead.clamp(cx0);
          /* 글자를 비켜 가운데에서 옮긴 알약(네모 · 관문 자리의 글줄 등)이 같은 글줄의 이웃 점 · 글자에 닿으면(둘레 포함) — 다른 비킴 자리, 없으면 가운데로 돌아감
             (가운데는 묶을 때 이웃과 떨어지게 정한 자리 — 옮기기 전과 같음) */
          const mid = (l + rr) / 2;
          if (Math.abs(cx0 - mid) > 0.5) {
            const ring = sm || bird ? 1 : 3;
            const fit = c => (bb ? Math.min(bb[1] - pm - w / 2, Math.max(bb[0] + pm + w / 2, c)) : lead.clamp(c));
            const near = (c, text) => {
              const half = w / 2 + ring;
              if (text && overlaps(subs[sub] || [], c - half, c + half)) return true;
              if (zonesB.length && overlaps(zonesB, c - w / 2, c + w / 2)) return true; // 조감: 띠 안 이름 · 단추 자리
              return list.some(it => !r.includes(it) && Math.abs(it.x - c) < half + dotR(it, bird || !!it.sm) - 0.25);
            };
            if (near(cx0, true)) {
              const alt = [l + w / 2 - 5, rr - w / 2 + 5].map(fit).find(c => Math.abs(c - cx0) > 0.5 && !near(c, true));
              const back = fit(mid);
              if (alt != null) cx0 = alt;
              else if (!(zonesB.length && overlaps(zonesB, back - w / 2, back + w / 2))) cx0 = back;
            }
          }
          r.forEach(it => (it.hidden = true));
          r.forEach(it => mark(it, `c:${sub}:${pkOf(r[0])}`));
          out.clusters.push({ sub, members: r, lead, l, r: rr, x: cx0, w, sm });
        }
      }
      out.subs = subs; // 글줄별로 차지한 구간 (정권 이름표가 뒤에 빈자리를 찾을 때 씀)
      out.dots = xs.map((x, i) => [x, dotLine[i]]);
      return out;
    }

    /** 사건 이름 옆 날짜: 해 눈금이면 연도, 달·날 눈금이면 적은 정밀도만큼 (연도만 적은 사건에 없는 날짜를 지어내지 않음) */
    _labelDate(e) {
      const at = HT.atOf(e, 'start');
      const r = at ? HT.cal.parse(at) : null;
      if (r && r.ok && r.span) return r.text; // 세기로 적은 연대는 배율과 상관없이 적은 대로 ("3세기 중반" — 234년이라 적으면 모르는 것이 사라짐)
      if (!this._sub || !r || !r.ok || r.prec === 'y') return HT.formatYear(e.start);
      const one = HT.yearOf(this.view.start) === HT.yearOf(this.view.end);
      const s = HT.cal.formatT(r.t, r.prec === 'm' ? 'm' : r.prec === 'd' ? 'd' : r.prec);
      return one ? s.replace(/^(기원전 )?\d+년 /, '') : s;
    }

    /* ---------- DOM ---------- */
    _build() {
      this.root.classList.add('tl');
      this.root.innerHTML = `
        <div class="tl-axis"></div>
        <div class="tl-body" tabindex="0" aria-label="연표. 휠로 확대·축소, 드래그로 이동">
          <div class="tl-inner"><div class="tl-grid"></div><div class="tl-tracks"></div></div>
          <div class="tl-empty" hidden></div>
        </div>`;
      this.axisEl = this.root.querySelector('.tl-axis');
      this.bodyEl = this.root.querySelector('.tl-body');
      this.innerEl = this.root.querySelector('.tl-inner');
      this.gridEl = this.root.querySelector('.tl-grid');
      this.tracksEl = this.root.querySelector('.tl-tracks');
      this.emptyEl = this.root.querySelector('.tl-empty');
      new ResizeObserver(() => this.render()).observe(this.root);
      this.axisEl.addEventListener('pointermove', e => this._axisHover(e));
      this.axisEl.addEventListener('change', e => {
        if (e.target.matches('[data-cal-pick]')) this.setAltCal(e.target.value);
      });
      this.axisEl.addEventListener('pointerleave', () => this._axisHover(null));
      this.axisEl.addEventListener('click', e => {
        const b = e.target.closest('[data-fold-era]');
        if (b) return this.toggleFoldEra(b.dataset.foldEra);
        const g = e.target.closest('[data-axis-group]');
        if (g) return this.toggleAxisGroup(g.dataset.axisGroup);
        const sec = e.target.closest('[data-cap-sec]');
        if (sec) return this.toggleCapSec(sec.dataset.capSec);
        /* 시대 구분 칸을 누르면 그 항목(제 문서·상세)을, 연호·도읍 칸을 누르면 그 정권의 그 칸('era:2' · 'capital:0' — 칸 상세와 기간 조명)을 엽니다 */
        const hit = e.target.closest('[data-uid]');
        const cell = hit && e.target.closest('[data-cell]');
        if (hit && this.opts.onSelect) this.opts.onSelect(hit.dataset.uid, Math.round(this.yearAtClientX(e.clientX)), { cell: cell ? cell.dataset.cell : undefined, multi: e.ctrlKey || e.metaKey });
      });
    }

    /** 맨 위 날짜 칸: 연도 · 시대 구분 · 간지 · 연호 묶음 · 도읍 묶음 (묶음은 누르면 나라별 줄) */
    _buildAxis() {
      const rows = [`<div class="tl-axis-row is-years" style="height:${AXIS.years}px"><div class="tl-corner" data-corner="years"></div><div class="tl-axis-cells" data-kind="years"></div></div>`];
      /* 시대 구분 띠: 공통(트랙 없음) 줄은 연도 바로 아래, 나라별 줄은 그 나라 연호 줄 옆에 */
      this.epochRows = [];
      const packLanes = list => {
        const ends = [];
        for (const e of list) {
          let lane = ends.findIndex(end => end <= e.start);
          if (lane < 0) lane = ends.length;
          ends[lane] = e.endY;
          e._lane = lane;
        }
        return Math.max(1, ends.length);
      };
      /* 시대 접기 (설계 6 결정 7 A → 감독 건의 2026-10-14 2번 "시대 구분 접기"): 공통 줄까지 모든 시대 구분 줄을 연호 · 도읍 묶음과 같은 꼴의 한 줄
         '시대 구분 n줄 ▸'로 접습니다 — 접힌 줄은 맨 처음 시대 구분 줄의 자리에(공통 줄이 있으면 연도 바로 아래), 줄마다 시대 색의 가는 막대 한 가닥.
         펼친 모습은 그대로이고, 어느 시대 구분 줄이든 왼쪽 이름(같은 모양의 단추)을 누르면 접힙니다 — 맨 처음 줄의 이름 끝에 ▾.
         접힘 기억은 날짜 칸 묶음의 기억(axisOpen)에 'epochFold' 한 열쇠 — 기본이 펼침이라 열쇠의 뜻이 연호 · 도읍과 반대(있으면 접힘) */
      const epochAll = [];
      if (this.show.epochs) {
        const common = this.epochs.filter(e => !e.track).slice().sort((a, b) => a.start - b.start);
        if (common.length) epochAll.push({ track: null, epochs: common });
        for (const tr of this.tracks) {
          const list = this.epochs.filter(e => e.track === tr.id).slice().sort((a, b) => a.start - b.start);
          if (list.length) epochAll.push({ track: tr, epochs: list });
        }
      }
      const epochFolded = epochAll.length > 0 && this.axisOpen.has(EPOCH_FOLD);
      let epochGroup = null; // 접힌 시대 구분 줄 — 막대는 _draw의 '접힌 연호·도읍 묶음'이 그림 (아래 groupRows)
      const epochFoldRow = () => {
        epochGroup = { key: 'epochs', list: epochAll, open: false, epochs: true };
        const tip = `시대 구분 — ${epochAll.map(d => (d.track ? d.track.name : '공통')).join(' · ')} · 눌러서 펼치기`;
        rows.push(
          `<div class="tl-axis-row is-group" style="height:${AXIS.group}px"><button type="button" class="tl-corner tl-group-btn" data-axis-group="${EPOCH_FOLD}" aria-expanded="false" title="${esc(tip)}"><b>시대 구분</b><i>${epochAll.length}줄 ▸</i></button><div class="tl-axis-cells" data-kind="group" data-group="epochs" data-axis-group="${EPOCH_FOLD}" title="${esc(tip)}"></div></div>`
        );
      };
      /* 펼친 줄: 왼쪽 이름이 시대 접기 단추 — 보이는 모양은 글 칸(div)과 같게(단추의 기본 테두리만 지우고 칸의 오른쪽 선을 그대로 둠) · 맨 처음 줄만 끝에 ▾ */
      const epochRow = (d, first) => {
        const { track, epochs: list } = d;
        const lanes = packLanes(list);
        this.epochRows.push({ track, epochs: list, lanes });
        const label = track ? `${esc(track.name)} 시대` : '시대 구분';
        const corner = `<button type="button" class="tl-corner" data-axis-group="${EPOCH_FOLD}" aria-expanded="true" style="border-width:0 1px 0 0;border-style:solid;border-color:var(--paper-line);cursor:pointer" title="${esc(`${track ? `${track.name} 시대` : '시대 구분'} — 눌러서 시대 구분 줄을 모두 한 줄로 접기`)}">${label}${first ? '<i class="tl-fold-mark">▾</i>' : ''}</button>`;
        rows.push(`<div class="tl-axis-row is-epoch" style="height:${AXIS.epoch * lanes}px;--track:${track ? track.color : 'var(--accent)'}">${corner}<div class="tl-axis-cells" data-kind="epoch" data-track="${track ? esc(track.id) : ''}"></div></div>`);
      };
      const epochCommon = epochAll.find(d => !d.track);
      if (epochCommon) {
        if (epochFolded) epochFoldRow();
        else epochRow(epochCommon, true);
      }
      if (this.show.ganji) rows.push(`<div class="tl-axis-row is-ganji" style="height:${AXIS.ganji}px"><div class="tl-corner">${esc(HT.cycleLabel(this._cycle()))}</div><div class="tl-axis-cells" data-kind="ganji"></div></div>`); // 줄 이름: 육십갑자면 '간지', DLC의 간지 설정이면 그 줄 이름 (형식 3 — 결정 8 B)
      /* 보조 달력: 해보다 작게 확대했을 때만 스르르 열립니다 (접혀 있을 땐 높이 0) */
      if (HT.cal && this.altCal && HT.cal.supports(this.altCal)) {
        const opts = HT.cal.CALENDARS.filter(c => !['civil', 'gregorian', 'julian'].includes(c.id) && HT.cal.supports(c.id));
        rows.push(
          `<div class="tl-axis-row is-cal${this._calOpen ? ' is-open' : ''}" data-cal-row style="--h:${AXIS.cal}px"><label class="tl-corner tl-cal-corner" title="보조 달력 — 바꾸거나 끌 수 있습니다"><select class="tl-cal-pick" data-cal-pick aria-label="보조 달력">${opts
            .map(c => `<option value="${c.id}"${c.id === this.altCal ? ' selected' : ''}>${esc(c.name)}</option>`)
            .join('')}<option value="">끄기</option></select></label><div class="tl-axis-cells" data-kind="cal"></div></div>`
        );
      }
      /* 나라별 시대 구분 줄(간지 · 보조 달력 아래) — 접혀 있으면 공통 줄이 없을 때만 여기에 접힌 줄 하나 */
      const epochByTrack = epochAll.filter(d => d.track);
      if (!epochFolded) epochByTrack.forEach((d, i) => epochRow(d, !epochCommon && i === 0));
      else if (!epochCommon) epochFoldRow();
      /* 연호 · 도읍: 큰 묶음 줄 하나(누르면 펼침) 아래에 나라별 줄 */
      this.eraRows = [];
      this.capRows = [];
      this.groupRows = epochGroup ? [epochGroup] : []; // 접은 시대 구분 줄도 같은 묶음 막대로 그립니다 (시대 접기)
      // 정권별 묶음을 겹치지 않게 갈래(레인)에 배정 — 명·청처럼 같은 시기에 두 정권이 있으면 두 갈래
      const packSpans = list => {
        list.sort((a, b) => a.s - b.s || a.e - b.e);
        const ends = [];
        for (const po of list) {
          let lane = ends.findIndex(end => end <= po.s);
          if (lane < 0) lane = ends.length;
          ends[lane] = po.e;
          po.lane = lane;
        }
        return ends.length;
      };
      const eraData = [];
      if (this.show.eras) {
        for (const tr of this._axisTracks()) {
          const polities = [];
          for (const p of tr.axisPeriods || tr.periods) {
            if (!p.eras || !p.eras.length) continue;
            const eras = p.eras.map((c, ci) => Object.assign({}, c, { end: c.end ?? p.endY, endAt: c.end != null ? HT.atOf(c, 'end') : HT.atOf(p, 'end'), toNow: HT.cellToNow(c, p), polity: p.name, color: p.color, uid: p.uid, ci, pol: p })); // ci = 그 정권의 연호 목록에서의 순번 (칸 참조 'era:ci')
            polities.push({ eras, s: Math.min(...eras.map(c => c.start)), e: Math.max(...eras.map(c => c.end)) });
          }
          if (!polities.length) continue;
          const lanes = packSpans(polities);
          polities.forEach(po => po.eras.forEach(c => (c.lane = po.lane)));
          const eras = polities.flatMap(po => po.eras).sort((a, b) => a.start - b.start);
          eraData.push({ track: tr, eras, lanes, spans: polities.map(po => [po.s, po.e]) });
        }
      }
      const capData = [];
      if (this.show.capitals !== false) {
        for (const tr of this._axisTracks()) {
          const entries = [];
          const sec = [];
          for (const p of tr.axisPeriods || tr.periods) {
            const caps = p.capitals || [];
            if (!caps.length) continue;
            /* 정도·공동·망명·임시: 임시 도읍 기간은 그때의 정도 칸을 비우고 그 자리에(개경 | 강화 | 개경).
               그래도 겹치는 칸(공동 정도)은 같은 정권의 다음 갈래로 */
            const temps = caps.filter(c => c.role === 'temporary');
            let segs = caps.filter(c => c.role !== 'secondary' && c.role !== 'temporary').map(c => ({ c, s: c.start, e: c.endY }));
            for (const t of temps) {
              const next = [];
              for (const g of segs) {
                if (g.e <= t.start || g.s >= t.endY) {
                  next.push(g);
                  continue;
                }
                if (g.s < t.start) next.push({ c: g.c, s: g.s, e: t.start });
                if (g.e > t.endY) next.push({ c: g.c, s: t.endY, e: g.e });
              }
              segs = next;
            }
            segs = segs.concat(temps.map(c => ({ c, s: c.start, e: c.endY }))).sort((a, b) => a.s - b.s || a.e - b.e);
            const subs = [];
            for (const g of segs) {
              let k = subs.findIndex(list => list[list.length - 1].e <= g.s + 1e-6);
              if (k < 0) k = subs.push([]) - 1;
              subs[k].push(g);
            }
            subs.forEach((list, k) => entries.push({ p, key: `${p.uid}|${k}`, segs: list, s: list[0].s, e: Math.max(...list.map(g => g.e)) }));
            // 배도: 같은 묶음(group — 5경·5소경)은 한 칸으로
            const groups = new Map();
            for (const c of caps.filter(c => c.role === 'secondary')) {
              const key = c.group || `${c.city}@${c.start}`;
              const gr = groups.get(key);
              if (gr) {
                gr.start = Math.min(gr.start, c.start);
                gr.endY = Math.max(gr.endY, c.endY);
                gr.members.push(c);
              } else groups.set(key, { p, name: c.group || c.name, city: c.group ? '' : c.city, start: c.start, endY: c.endY, members: [c] });
            }
            sec.push(...groups.values());
          }
          if (!entries.length && !sec.length) continue;
          const lanes = Math.max(1, packSpans(entries));
          sec.sort((a, b) => a.start - b.start || a.endY - b.endY);
          const secEnds = [];
          for (const gr of sec) {
            let lane = secEnds.findIndex(end => end <= gr.start);
            if (lane < 0) lane = secEnds.length;
            secEnds[lane] = gr.endY;
            gr.lane = lane;
          }
          capData.push({ track: tr, entries, lanes, sec, secLanes: secEnds.length, spans: entries.map(en => [en.s, en.e]).concat(sec.map(gr => [gr.start, gr.endY])) });
        }
      }
      const group = (key, name, list) => {
        if (!list.length) return false;
        const open = this.axisOpen.has(key);
        this.groupRows.push({ key, list, open });
        const names = list.map(d => d.track.name).join(' · ');
        const tip = open ? `${name} 접기` : `${name} — ${names} · 눌러서 나라별로 펼치기`;
        rows.push(
          `<div class="tl-axis-row is-group${open ? ' is-open' : ''}" style="height:${AXIS.group}px"><button type="button" class="tl-corner tl-group-btn" data-axis-group="${key}" aria-expanded="${open}" title="${esc(tip)}"><b>${name}</b><i>${open ? '▾' : `${list.length}개 나라 ▸`}</i></button><div class="tl-axis-cells" data-kind="group" data-group="${key}"${open ? '' : ` data-axis-group="${key}" title="${esc(tip)}"`}></div></div>`
        );
        return open;
      };
      if (group('eras', '연호', eraData)) {
        for (const d of eraData) {
          const { track: tr, eras, lanes } = d;
          const folded = lanes > 1 && this.foldedEras.has(tr.id);
          this.eraRows.push({ track: tr, eras, lanes, folded });
          const corner =
            lanes > 1
              ? `<button type="button" class="tl-corner tl-era-fold" data-fold-era="${esc(tr.id)}" aria-expanded="${!folded}" title="${esc(`${tr.name} 연호 · ${folded ? `${lanes}갈래로 펼치기` : '한 줄로 접기'}`)}">${esc(tr.name)} <i>${folded ? `${lanes}갈래 ▸` : '▾'}</i></button>`
              : `<div class="tl-corner" title="${esc(`${tr.name} 연호`)}">${esc(tr.name)}</div>`;
          rows.push(`<div class="tl-axis-row is-era is-sub${folded ? ' is-folded' : ''}" style="height:${AXIS.era * (folded ? 1 : lanes)}px;--track:${tr.color}">${corner}<div class="tl-axis-cells" data-kind="era" data-track="${esc(tr.id)}"></div></div>`);
        }
      }
      if (group('capitals', '도읍', capData)) {
        for (const d of capData) {
          d.secOpen = d.secLanes > 0 && this.openCapSec.has(d.track.id);
          this.capRows.push(d);
          const h = AXIS.cap * d.lanes + (d.secOpen ? d.secLanes * AXIS.capSec + 2 : 0);
          const corner = d.secLanes
            ? `<button type="button" class="tl-corner tl-era-fold" data-cap-sec="${esc(d.track.id)}" aria-expanded="${d.secOpen}" title="${esc(`${d.track.name} 도읍 · ${d.secOpen ? '배도 갈래 접기' : '배도(별도·5경·소경) 갈래 펼치기'}`)}">${esc(d.track.name)} <i>${d.secOpen ? '배도 ▾' : `배도 ${d.sec.length} ▸`}</i></button>`
            : `<div class="tl-corner" title="${esc(`${d.track.name} 도읍`)}">${esc(d.track.name)}</div>`;
          rows.push(`<div class="tl-axis-row is-era is-cap is-sub" style="height:${h}px;--track:${d.track.color}">${corner}<div class="tl-axis-cells" data-kind="cap" data-track="${esc(d.track.id)}"></div></div>`);
        }
      }
      this.axisEl.innerHTML = rows.join('');
      this.axisEl.style.setProperty('--gutter', `${this.gutter}px`);
    }

    _buildTracks() {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      this.tracksEl.style.setProperty('--gutter', `${this.gutter}px`);
      this.bodyEl.style.setProperty('--gutter', `${this.gutter}px`); // 그림판 바탕(common.css 서고 모양 1단 가)이 트랙 아래쪽의 줄 이름 칸 몫도 종이로
      this.tracksEl.innerHTML = this.tracks
        .map(tr => {
          const g = tr.geo;
          const style = `height:${tr.height}px;--rowH:${tr.rowH}px;--nameSize:${g.name}px;--evSize:${g.font}px;--track:${tr.color}`;
          const lead = tr._sphere && tr._sphere.tracks[0] === tr ? this._sphereHTML(tr._sphere) : ''; // 서고: 문화권의 첫 트랙 앞에 머리 단
          if (tr._sphereHidden) return `${lead}<section class="tl-track is-folded is-sphere-hidden" data-track="${esc(tr.id)}" style="${style};display:none"><div class="tl-lanes"><div class="tl-mini"></div></div></section>`; // 접힌 문화권의 트랙: 자리 없음
          if (tr.folded) {
            return `${lead}<section class="tl-track is-folded${tr.board ? ' is-board' : ''}" data-track="${esc(tr.id)}" style="${style}">
              <button type="button" class="tl-fold" data-fold="${esc(tr.id)}" aria-expanded="false" title="펼치기"><span>${esc(tr.name)}</span><i>펼치기 ▸</i></button>
              <div class="tl-lanes"><div class="tl-mini"></div></div>
            </section>`;
          }
          /* 줄과 민족 칸은 처음부터 접힌 크기로 태어납니다 (_foldAhead가 먼저 계산해 둔 값 — 큰 크기로 태어났다가 줄어드는 "풍선"이 없게) */
          const lanes = Array.from({ length: tr.rows }, (_, r) => `<div class="tl-lane${tr.foldedRows.has(r) ? ' is-folded' : ''}${tr.memberRows.has(r) ? ' is-member' : ''}${tr.underRowSet.has(r) ? ' has-under' : ''}${tr.hiddenRows.has(r) ? ' is-collapsed' : ''}" data-row="${r}" style="margin-top:${tr.rowGap[r]}px;height:${tr.rowHs[r]}px;--hem:${G.hem}px;--cut:${tr.rowCut[r] || 0}px"></div>`).join('');
          // 민족 칸: 대명제가 왼쪽, 세부 민족이 오른쪽. 접힌 단계 아래는 그 단계 칸이 나머지 폭을 차지합니다
          const people = tr.groups
            .filter(gp => gp.name)
            .map(gp => {
              const at = this._peopleSpan(tr, gp);
              const left = gp.depth * COL.people + 2;
              const width = gp.folded || gp.scope ? this.depth * COL.people - left - 2 : COL.people - 4; // 대범위 가지의 칸은 민족 칸 전체 폭 (7-2)
              const sc = gp.scope ? ` is-scope${this._scopeBorn === gp.scope ? ' is-born' : ''}` : '';
              /* 집합 보기의 칩(원래 트랙 · 제 민족)은 접기 단추가 아님 — 순번으로 짝짓는 코드(_collapseRows · _placePchips)가 같은 .tl-people로 찾으므로 클래스는 그대로 */
              if (tr.board) return `<button type="button" class="tl-people${gp.from ? ' is-from' : ''}${gp.culture ? ' is-culture' : ''}${at ? '' : ' is-collapsed'}" data-board-chip style="top:${at ? at.top : tr.rowTop[gp.first]}px;height:${at ? at.height : 0}px;left:${left}px;width:${width}px;--pc:${gp.color}" title="${esc(gp.from ? `${gp.name} 트랙에서 온 줄` : gp.name)}"><span>${esc(gp.name)}</span></button>`;
              return `<button type="button" class="tl-people${gp.folded ? ' is-folded' : ''}${gp.culture ? ' is-culture' : ''}${sc}${at ? '' : ' is-collapsed'}" data-fold-people="${esc(peopleKey(tr, gp))}" aria-expanded="${!gp.folded}" style="top:${at ? at.top : tr.rowTop[gp.first]}px;height:${at ? at.height : 0}px;left:${left}px;width:${width}px;--pc:${gp.color}" title="${esc(gp.name)} · ${gp.folded ? '펼치기' : '접기'}"><span>${gp.folded ? `${esc(gp.name)} ▸` : esc(gp.name)}</span></button>`;
            })
            .join('');
          const sameSphere = this.seogo && tr._sphere && tr._sphere.name === tr.name; // 서고 왼쪽 칸: 트랙 세로 이름은 그 문화권과 이름이 다를 때만(새 앱 gutter.dart)
          return `${lead}<section class="tl-track${tr.board ? ' is-board' : ''}" data-track="${esc(tr.id)}" style="${style}">
            <div class="tl-tbox">
              <button type="button" class="tl-tname${sameSphere ? ' is-same-sphere' : ''}" data-fold="${esc(tr.id)}" aria-expanded="true" title="접기"><span>${esc(tr.name)}</span></button>
              <div class="tl-peoples" style="width:${this.depth * COL.people}px">${people}${this._pchipsHTML(tr)}</div>
              <div class="tl-rows" style="margin-left:${this.seogo ? COL.track : COL.track + this.depth * COL.people}px;padding-top:${G.pad}px"></div>
            </div>
            <div class="tl-lanes" style="padding-top:${G.pad}px">${this._scopesHTML(tr)}${lanes}<svg class="tl-links" aria-hidden="true"></svg><svg class="tl-marks" aria-hidden="true"></svg></div>
          </section>`;
        })
        .join('');
      this._scopeBorn = null; // 방금 켠 대범위의 떠오름은 이번 짓기 한 번만
      for (const s of this.spheres) s.el = this.tracksEl.querySelector(`.tl-sphere[data-sphere="${CSS.escape(s.id)}"]`); // 서고: 문화권 머리 단 요소 (_drawSphereTags)
      this.tracks.forEach(tr => {
        const el = this.tracksEl.querySelector(`[data-track="${CSS.escape(tr.id)}"]`);
        tr.el = el;
        tr.rowsEl = el.querySelector('.tl-rows');
        tr.lanesEl = el.querySelector('.tl-lanes');
        tr.laneEls = [...el.querySelectorAll('.tl-lane')];
        tr.linksEl = el.querySelector('.tl-links');
        tr.marksEl = el.querySelector('.tl-marks');
        tr.miniEl = el.querySelector('.tl-mini');
        tr._labelSig = null;
        this._fitTrackName(tr); // 트랙 이름이 낮은 트랙(조감 · 줄이 적은 트랙)에 다 들지 않으면 줄임
        this._placePchips(tr); // 민족 딱지가 끼워진 민족 칸의 이름 자리
        this._placeScopes(tr); // 대범위 테두리의 세로 자리
      });
    }

    /** 다시 지은 뒤: 높이가 달라진 트랙만 이전 높이에서 새 높이로 한 번에 흐르게 (FLIP). 새 DOM은 이미 접힌 크기로 태어났으므로(_foldAhead)
        "팍 열리고 다시 줄어드는" 두 단계가 없고, 높이가 그대로인 트랙은 1px도 움직이지 않습니다. 곡선·길이는 줄 접힘과 같은 하나(--t-move · --spring).
        is-opening(내용이 떠오름) · is-closing은 실제로 펼치거나 접은 트랙(과 줄 구성이 달라진 트랙)에만 붙습니다.
        누르기 직전에 잡아 둔 줄(before.hold)은 흐르는 동안 화면에서 제자리에 붙잡습니다 */
    _applyFlip(before, clock = null) {
      const T = HT.motion.T;
      const now = HT.motion.now();
      const flowing = []; // [요소, 이전 높이, 새 높이]
      for (const tr of this.tracks) {
        const el = tr.el;
        if (!el || reduceMotion()) continue;
        const old = before.tracks.get(tr.id);
        /* 앞선 화면의 줄을 기억해 두었다가, 다시 지은 뒤 첫 그리기에서 새로 생긴 것만 떠오르고 없어진 것은 옅어지며 물러나게 (_drawTrack) */
        tr._was = old && old.lanes && !tr.folded ? { lanes: old.lanes, sameRows: old.rows === tr.rows, until: now + T.move + 80 } : null;
        const h0 = old ? old.h : before.tracks.size ? 0 : null; // 새로 켠 트랙은 0에서 자라납니다 (맨 처음 자료는 그대로)
        const h1 = tr.height;
        const flow = h0 != null && Math.abs(h1 - h0) >= 0.5;
        const opened = flow && !tr.folded && (!old || old.folded || tr.rows > old.rows);
        const closed = flow && !!old && !old.folded && (tr.folded || tr.rows < old.rows);
        /* 펼친 내용이 떠오르는 도중에 (다른 것을 눌러) 다시 지어졌으면, 처음부터가 아니라 하던 데서 이어 떠오릅니다 */
        const since = !opened && old && old.opened != null && !tr.folded ? now - old.opened : -1;
        if (opened) el._openedAt = now;
        else if (since >= 0 && since < T.in) {
          el._openedAt = old.opened;
          el.style.setProperty('--since', `${-Math.round(since)}ms`);
        }
        if (el._openedAt != null) el.classList.add('is-opening');
        else if (closed) el.classList.add('is-closing');
        if (el._openedAt != null || closed) HT.motion.later(T.move + 40, () => el.classList.remove('is-opening', 'is-closing'));
        if (flow) flowing.push([el, h0, h1]);
      }
      /* 필터로 끈 트랙: 있던 자리에서 옅어지며 높이 0으로 접힙니다(같은 시계) — 아래 트랙들이 툭 올라붙지 않게. 다 접히면 치웁니다 */
      if (!reduceMotion()) {
        const ids = [...before.tracks.keys()];
        ids.forEach((id, i) => {
          const old = before.tracks.get(id);
          if (!old.el || !(old.h > 0) || this.tracks.some(t => t.id === id)) return;
          const next = ids.slice(i + 1).map(x => this.tracks.find(t => t.id === x)).find(t => t && t.el);
          const g = old.el;
          g.removeAttribute('data-track');
          g.classList.remove('is-opening', 'is-closing');
          g.classList.add('is-gone');
          this.tracksEl.insertBefore(g, next ? next.el : null);
          flowing.push([g, old.h + 1, 0]); // 아래 테두리 1px까지 (is-gone은 border-box)
          HT.motion.later(T.move + 40, () => g.remove());
        });
      }
      if (clock) {
        /* 밀도가 바뀐 흐름: 트랙 높이도 줄 · 이름 칸과 같은 시각에 못 박은 움직임으로 (CSS 전환은 한 프레임 늦게 시작해, 스크롤 끝에 걸린 줄이 그 어긋남만큼 출렁임) */
        for (const [el, h0, h1] of flowing) {
          el.style.height = `${h1}px`;
          if (el.classList.contains('is-gone')) el.style.opacity = '0';
          this._squashRun(clock, el, [{ height: `${h0}px`, offset: 0 }], T.move, HT.motion.C.spring);
        }
      } else {
        for (const [el, h0] of flowing) {
          el.style.transition = 'none';
          el.style.height = `${h0}px`;
        }
        if (flowing.length) this.tracksEl.getBoundingClientRect(); // 이전 높이를 한 번 그리게 한 뒤
        for (const [el, , h1] of flowing) {
          el.style.transition = '';
          el.style.height = `${h1}px`;
          if (el.classList.contains('is-gone')) el.style.opacity = '0';
        }
      }
      const flows = flowing.length > 0;
      const held = this._resolveHold(before.hold, before);
      this._held = held && flows ? Object.assign(held, { until: now + T.move + 80 }) : null;
      /* 위쪽이 화면 밖에 있던 긴 트랙을 접었으면 접힌 띠가 화면 위로 사라져 버립니다 — 보이는 데(위쪽 여유 SAFE_Y)까지만 스프링으로 데려옵니다. 누른 것이 사라지지 않게 */
      if (this._held && held.row < 0 && held.tr.folded && held.off < 0 && !reduceMotion()) held.to = this._reachable(held.tr, 0, SAFE_Y);
      this._keepAnchor(held); // 없어진 트랙처럼 흐르지 않고 바뀐 것은 지금 바로 맞추고
      if (flows) this._anchorLoop(T.move + 80, held); // 흐르는 동안은 매 프레임 (창이 열려 있으면 고른 줄이 먼저 — _keepAnchor)
    }

    /* ---------- 밀도가 바뀔 때의 흐름 (조감 ↔ 다른 밀도 · 넉넉 ↔ 자동 ↔ 빽빽) ----------
       한 시계(T.move · C.spring — 트랙 높이의 _applyFlip과 같은 호출 · 같은 출발 프레임): 줄의 높이 · 위 틈, 줄 칸 · 이름 칸의 위 여백, 왼쪽 줄 이름, 민족 칸 · 딱지, 대범위 테두리가
       옛 크기 · 자리에서 새 것으로 흐릅니다(요소마다 따로 옮기지 않고 줄째). 옛 줄 안의 것(칸 · 탭 · 사건 · 띠 안 이름 …)은 새 줄 안에 통째로 잘린 잔상(.tl-sqz)으로 남아
       T.out에 옅어지고 — 줄이 낮아지면 아래쪽부터 잘림 — 새 것은 T.in에 떠오릅니다. 띠는 그대로(제 높이가 줄과 함께 흐를 뿐 — 잔상의 띠 껍데기는 비움), 선 그림은 기다렸다가 도착하는 순간 떠오르고
       옛 선은 T.out에 옅어집니다. 보던 줄은 제자리(_applyFlip의 붙잡기 — 매 프레임 _keepAnchor). 움직임 줄이기면 없음(_snapshot이 재지 않음) */
    _squashFirst() {
      const m = new Map();
      m.bird = this._bird ? this._bird.shape : null; // 옛 밀도가 조감이었나 — 잔상(.was-bird)이 옛 모습 그대로 옅어지게 (조감 전용 모양은 살아 있는 줄과 이 잔상에만: common.css)
      const px = (el, k) => parseFloat(getComputedStyle(el)[k]) || 0;
      const tab = this._G().tab; // 옛 줄 안의 것이 줄 위로 삐져나온 만큼 (책갈피 탭) — 잔상이 그만큼 위까지 보이게
      for (const tr of this.tracks) {
        if (!tr.el || !tr.el.isConnected) continue;
        const top = tr.el.offsetTop; // 옛 자리 · 높이 — 흐르는 내내 화면 밖인 트랙을 가림 (_squashAway)
        const h = tr.el.getBoundingClientRect().height;
        if (tr.folded) {
          if (tr.miniEl) m.set(tr.id, { folded: true, mini: tr.miniEl, top, h });
          continue;
        }
        if (!tr.laneEls || !tr.rowsEl) continue;
        const box = (sel, key) => {
          const out = new Map();
          tr.el.querySelectorAll(sel).forEach(el => {
            const k = el.getAttribute(key);
            if (!el._ghost && k != null && !el.classList.contains('is-collapsed')) out.set(k, { top: px(el, 'top'), height: px(el, 'height'), text: el.textContent });
          });
          return out;
        };
        m.set(tr.id, {
          folded: false,
          top,
          h,
          n: tr.rows,
          tab,
          vars: ['--nameSize', '--evSize', '--rowH'].map(k => [k, tr.el.style.getPropertyValue(k)]).filter(([, v]) => v), // 옛 글자 크기 · 줄 높이 — 잔상은 새 트랙 안에 들어가므로 옛 값을 지니고 감 (새 값을 물려받으면 옛 이름이 커지며 칸을 넘침)
          pad: px(tr.lanesEl, 'paddingTop'),
          rpad: px(tr.rowsEl, 'paddingTop'),
          lanes: tr.laneEls.map(el => ({ el, h: el.getBoundingClientRect().height, mt: px(el, 'marginTop') })),
          rowsEl: tr.rowsEl,
          rows: [...tr.rowsEl.children].map(el => ({ h: el.getBoundingClientRect().height, mt: px(el, 'marginTop') })),
          peoples: box('.tl-people', 'data-fold-people'),
          pchips: box('.tl-pchip', 'data-pchip'),
          scopes: box('.tl-lanes > .tl-scope', 'data-uid'),
          svgs: [tr.linksEl, tr.marksEl].filter(Boolean),
        });
      }
      return m;
    }

    /** 흐름의 출발 (setData에서 _applyFlip 바로 다음): 줄 · 여백 · 민족 칸 · 딱지 · 테두리를 옛 값에서 흐르게 걸고, 옛 줄 · 옛 선 그림을 잔상으로 남깁니다.
        새 줄 안의 것 · 왼쪽 줄 이름은 첫 그리기(_drawTrack · _drawFolded)가 같은 시계에 붙입니다 (_squashIn · _squashLabels) */
    /** 흐름의 시계 하나: 모든 움직임(트랙 높이 · 줄 · 이름 칸 · 잔상 · 떠오름)의 시작 시각을 이 문서 시각(tl)에 못 박습니다 — 한 프레임 늦게 붙는 것(첫 그리기)도 같은 자리에서 이어짐 */
    _squashClock() {
      const now = HT.motion.now();
      return { t0: now, tl: document.timeline ? document.timeline.currentTime : null, until: now + HT.motion.T.move + 80 };
    }

    _squash(before, g) {
      const S = before.squash;
      if (!S || !g) return;
      const G = this._G();
      const M = HT.motion;
      const T = M.T;
      const flow = (el, kf) => this._squashRun(g, el, [Object.assign({ offset: 0 }, kf)], T.move, M.C.spring);
      const moved = (a, b) => Math.abs(a - b) >= 0.5;
      const fadeGhost = el => {
        el._ghost = true;
        const a = this._squashRun(g, el, [{ opacity: 1 }, { opacity: 0 }], T.out, 'ease-in', 'forwards');
        a.onfinish = a.oncancel = () => el.remove();
      };
      const plan = this._squashPlan(before); // 붙잡을 줄 · 다 흐른 뒤의 스크롤 (_squashHold) — 흐르는 내내 화면 밖인 트랙을 가리는 데도 씀 (_squashAway)
      for (const tr of this.tracks) {
        const o = S.get(tr.id);
        if (!o || !tr.el) continue;
        if (this._squashAway(o, tr, plan)) {
          tr._was = null; // 화면 밖: 줄 안은 곧바로 새 것 (옅어지고 떠오를 것이 보이지 않음)
          continue;
        }
        if (o.folded || tr.folded) {
          /* 접힌 채인 트랙: 높이만 흐르고(_applyFlip) 가는 막대는 옛 것이 옅어지며 새 것이 떠오름 */
          if (o.folded && tr.folded && o.mini && tr.miniEl) {
            o.mini.classList.add('tl-sqz-mini');
            tr.miniEl.parentNode.insertBefore(o.mini, tr.miniEl);
            fadeGhost(o.mini);
            tr._squash = { g, drawn: false };
          }
          continue;
        }
        if (o.n !== tr.rows || !tr.laneEls) continue; // 줄 구성이 달라진 트랙은 예전처럼 (밀도만 바뀌면 줄 구성은 그대로)
        tr._was = null; // 옛 줄 안의 것은 잔상이 맡고, 새 것은 모두 떠오름
        tr._squash = { g, o, bird: S.bird, drawn: false, labels: false };
        tr.el.classList.add('is-sqz'); // 흐르는 동안 줄 아래로 삐져나오지 않게 (common.css)
        HT.motion.later(T.move + 40, () => tr.el.classList.remove('is-sqz'));
        if (moved(o.pad, G.pad)) flow(tr.lanesEl, { paddingTop: `${o.pad}px` });
        if (moved(o.rpad, G.pad)) flow(tr.rowsEl, { paddingTop: `${o.rpad}px` });
        tr.laneEls.forEach((lane, r) => {
          const ol = o.lanes[r];
          if (!ol) return;
          if (moved(ol.h, tr.rowHs[r]) || moved(ol.mt, tr.rowGap[r])) flow(lane, { height: `${ol.h}px`, marginTop: `${ol.mt}px` });
          if (ol.h < 0.5) return;
          /* 옛 줄 안의 것: 새 줄의 맨 뒤에 잘린 잔상으로 — 위로는 옛 탭 자리까지, 아래는 새 줄의 (흐르는) 아랫변에서 잘림 */
          const wrap = document.createElement('div');
          wrap.className = `${S.bird ? `tl-sqz was-bird was-bird-${S.bird}` : 'tl-sqz'}${this._bird ? ' to-bird' : ''}`; // 조감에서 남은 잔상은 조감 모양 그대로 (common.css — 조감 전용 모양은 살아 있는 줄과 이 잔상에만) · 조감으로 가는 잔상(to-bird)은 이설 조명도 칸과 함께 옅어짐
          wrap.style.top = `${-o.tab}px`;
          for (const [k, v] of o.vars) wrap.style.setProperty(k, v);
          wrap.inert = true;
          wrap.setAttribute('aria-hidden', 'true');
          const old = ol.el;
          const KEYS = ['data-uid', 'data-cluster', 'data-cell', 'data-fold-members', 'data-fold-hangs', 'data-scope'];
          for (const el of old.querySelectorAll(KEYS.map(k => `[${k}]`).join(', '))) for (const k of KEYS) el.removeAttribute(k);
          const cut = old.style.getPropertyValue('--cut');
          old.removeAttribute('data-row');
          old.className = 'tl-sqz-in';
          old.style.cssText = `top:${o.tab}px;height:${ol.h}px;--cut:${cut || '0px'}`;
          wrap.appendChild(old);
          lane.insertBefore(wrap, lane.firstChild);
          fadeGhost(wrap);
        });
        /* 민족 칸 · 민족 딱지 · 대범위 테두리: 옛 자리 · 옛 높이에서 */
        const flip = (sel, key, map, text = false) =>
          tr.el.querySelectorAll(sel).forEach(el => {
            const old = map.get(el.getAttribute(key));
            if (!old || el.classList.contains('is-collapsed')) return;
            const top = parseFloat(el.style.top) || 0;
            const h = parseFloat(el.style.height) || 0;
            if (moved(old.top, top) || moved(old.height, h)) flow(el, { top: `${old.top}px`, height: `${old.height}px` });
            if (text) this._squashText(el, old, h, g);
          });
        flip('.tl-people', 'data-fold-people', o.peoples, true);
        flip('.tl-pchip', 'data-pchip', o.pchips, true);
        flip('.tl-lanes > .tl-scope', 'data-uid', o.scopes);
        /* 선 그림: 옛 것은 제자리에서 움직이는 중의 짧은 옅어짐(T.micro — 줄이 떠나는 동안 옛 자리에 남은 선이 오래 떠 있지 않게), 새 것은 기다렸다가 줄이 도착하는 순간 떠오름 (움직이는 줄을 가로지르지 않게) */
        for (const svg of o.svgs) {
          for (const el of svg.querySelectorAll('[data-from], [data-to]')) {
            el.removeAttribute('data-from');
            el.removeAttribute('data-to');
          }
          tr.lanesEl.insertBefore(svg, tr.linksEl);
          svg._ghost = true;
          const a = this._squashRun(g, svg, [{ opacity: 1 }, { opacity: 0 }], T.micro, 'linear', 'forwards');
          a.onfinish = a.oncancel = () => svg.remove();
        }
        for (const svg of [tr.linksEl, tr.marksEl]) if (svg) this._squashRun(g, svg, [{ opacity: 0, offset: 0 }], T.in, M.C.ease, 'backwards', T.move - T.in);
      }
      this._squashHold(g, plan);
    }

    /** 흐름 동안 붙잡을 줄 (원칙 ⑧ — 보던 줄은 제자리): 창이 열린 항목의 줄(닻), 아니면 _applyFlip이 붙잡은 화면 가운데 줄. 다 흐른 뒤의 스크롤(모델로 — 그 줄을 지금 화면 자리에 두되
        스크롤이 닿는 데까지)로, 스크롤이 줄 높이와 같은 곡선 · 같은 진행값으로 곧게 옮겨 갑니다 — 조감으로 줄어 내용이 화면보다 짧아지는 동안에도 스크롤 끝에 걸렸다 풀리며 그 줄이
        내려갔다 올라가는 출렁임이 없게(높이는 모두 한 시계라 스크롤도 늘 제 범위 안). 스크롤이 닿으면 그 줄은 1px도 움직이지 않습니다.
        _squashPlan이 붙잡을 줄과 다 흐른 뒤의 스크롤을 셈(움직임 없이), _squashHold가 그대로 겁니다 */
    _squashPlan(before) {
      const b = this.bodyEl;
      const a = this.anchorUid ? this._anchorLane() : null;
      const h = a || this._held;
      if (!h || !h.tr || !h.tr.el) return null;
      const { tops, total } = this._modelTops();
      /* 출발점은 다시 짓기 전의 화면: 스크롤(새 DOM이 처음 잴 때 짧아진 높이로 이미 깎였을 수 있음)과 그 줄의 화면 자리 */
      const s0 = before.scroll;
      const off0 = a ? (this._anchorOff != null ? this._anchorOff : this._laneAbs(a) - s0) : h.off;
      const absF = tops.get(h.tr) + (h.row >= 0 ? h.tr.rowTop[h.row] : 0);
      const H = b.clientHeight;
      const sF = HT.clamp(absF - off0, 0, Math.max(0, total - H));
      /* 높이는 모두 한 곡선이라 내용의 높이 c(p)도 진행값 p에 곧게 따라갑니다. 다 줄어든 내용이 화면보다 짧으면 스크롤 끝(c − H)이 p*에서 0에 닿으므로,
         스크롤도 p*까지 곧게 0으로 — 끝에 걸렸다 풀리며 그 줄이 내려갔다 올라가는 출렁임 없이 한 방향으로 (그 뒤는 위쪽 줄이 줄어드는 만큼 함께 올라감) */
      let c0 = 0;
      for (const tr of this.tracks) c0 += before.tracks.has(tr.id) && before.tracks.get(tr.id).h != null ? before.tracks.get(tr.id).h : tr.height;
      const pe = total >= H || c0 <= total ? 1 : HT.clamp((c0 - H) / (c0 - total), 0.05, 1);
      return { a, h, tops, s0, off0, absF, H, sF, pe };
    }

    /** 흐르는 내내 화면(과 위아래 SQZ_NEAR) 밖에 있는 트랙인가 — 트랙의 위 · 높이 · 스크롤이 모두 진행값에 곧게(스크롤은 p*에서 꺾여) 따라가므로 출발 · 꺾임 · 도착 세 자리의 테두리로 셈.
        그런 트랙은 줄 안의 잔상 · 떠오름 · 줄 흐름을 걸지 않습니다(트랙 높이만 흐름 — 비용: 화면 밖 트랙까지 모든 줄의 움직임을 걸면 밀도를 바꾼 첫 그림이 두세 배 늦어짐) */
    _squashAway(o, tr, plan) {
      if (!plan || !o || o.top == null) return false;
      const { tops, s0, sF, pe, H } = plan;
      const nt = tops.get(tr);
      if (nt == null) return false;
      let lo = Infinity;
      let hi = -Infinity;
      for (const y of [0, pe, 1]) {
        const top = o.top + (nt - o.top) * y - (s0 + (sF - s0) * Math.min(1, y / pe));
        lo = Math.min(lo, top);
        hi = Math.max(hi, top + o.h + (tr.height - o.h) * y);
      }
      return hi < -SQZ_NEAR || lo > H + SQZ_NEAR;
    }

    _squashHold(g, plan) {
      if (!plan) return;
      const M = HT.motion;
      const { a, h, s0, off0, absF, sF, pe } = plan;
      const clock = this._squashRun(g, this.tracksEl, [], M.T.move, M.C.spring);
      const prog = () => {
        if (clock.playState === 'finished' || clock.playState === 'idle') return 1;
        const pr = clock.effect.getComputedTiming().progress;
        return pr == null ? 1 : pr;
      };
      const scrollAt = () => s0 + (sF - s0) * Math.min(1, prog() / pe);
      if (a) {
        /* 창이 열려 있으면 스크롤은 닻(_keepAnchor)이 씁니다: 닻 자리(_anchorOff)가 스크롤을 scrollAt()으로 옮기도록 스프링 자리에 같은 모양의 따라가기 (모여듦의 _gatherHold와 같은 방식) */
        const self = this;
        const abs = () => {
          const c = self._anchorLane();
          return c ? self._laneAbs(c) : absF;
        };
        this._anchorTo = null;
        this._anchorOff = off0;
        this._anchorSpring = {
          target: absF - sF,
          value: () => abs() - scrollAt(),
          velocity: () => 0,
          done: () => prog() >= 1,
          set(to, v, t) {
            return (self._anchorSpring = self._newAnchorSpring(this.value()).set(to, null, t));
          },
        };
        this._keepAnchor();
        this._anchorLoop(M.T.move + 80);
      } else {
        const held = { tr: h.tr, row: h.row, until: M.now() + M.T.move + 80 };
        Object.defineProperty(held, 'off', { enumerable: true, get: () => h.tr.el.offsetTop + (h.row >= 0 && h.tr.laneEls[h.row] ? h.tr.laneEls[h.row].offsetTop : 0) - scrollAt(), set: () => {} });
        this._held = held;
        this._keepAnchor(held); // 이 자리에서 곧바로 (깎인 스크롤을 첫 그림 전에 되돌림)
        this._anchorLoop(M.T.move + 80, held);
      }
    }

    /** 흐름의 움직임 하나: 시작 시각을 흐름의 문서 시각(g.tl)에 못 박아 — 같은 호출의 트랙 높이 전환 · 한 프레임 늦게 붙는 새 요소와 한 시계 (느리게 보기면 그 빠르기로) */
    _squashRun(g, el, kf, duration, easing, fill = 'backwards', delay = 0) {
      const M = HT.motion;
      const a = el.animate(kf, { duration, easing, fill, delay });
      if (g.tl != null) a.startTime = g.tl;
      if (M.rate !== 1) a.playbackRate = M.rate;
      return a;
    }

    /** 민족 칸 · 민족 딱지의 세로 글 (흐름의 출발): 글은 다 흐른 뒤의 높이로 고른 것이라, 글이 바뀐 칸('흉' → '흉노족' — 조감에서 다른 밀도로)은 옛 높이에서 자라기 시작하는
        첫 프레임들에 아직 들지 않아 칸 테두리에 잘린 글자가 보입니다 — 글이 바뀐 칸은 글을 비워 두었다가 칸이 그 글이 들 높이에 닿는 순간(흐름 곡선 C.spring으로 셈)부터 T.in에 떠오릅니다.
        글이 그대로인 칸은 옛 높이 · 새 높이 모두에 들므로 그 사이에도 듦 (손대지 않음). 접힌 묶음의 가로 글은 말줄임이라 제외 */
    _squashText(el, old, h1, g) {
      const span = el.querySelector('span');
      if (!span || !span.textContent || span.textContent === old.text || el.classList.contains('is-folded')) return;
      const M = HT.motion;
      const pchip = el.classList.contains('tl-pchip');
      const n = [...span.textContent].length;
      const need = pchip ? n * 10.1 + 4 : n * 11.8 + 2; // 글을 고를 때의 fits와 같은 셈 (_pchipsHTML · _placePchips)
      const lt = parseFloat(el.style.getPropertyValue('--lt'));
      const lh = parseFloat(el.style.getPropertyValue('--lh'));
      const req = !pchip && el.classList.contains('has-pchip') && isFinite(lt) && isFinite(lh) ? lt + lh / 2 + need / 2 : need; // 딱지를 비켜 앉은 이름은 그 구간 가운데 — 칸이 그 아래 끝까지 자라야 듦
      const f = h1 > old.height + 0.5 ? HT.clamp((req - old.height) / (h1 - old.height), 0, 1) : 0;
      this._squashRun(g, span, [{ opacity: 0, offset: 0 }], M.T.in, M.C.ease, 'backwards', f > 0 ? M.T.move * bezierTimeAt(M.C.spring, f) : 0);
    }

    /** 새 줄 안의 것을 떠오르게 (흐름 뒤의 첫 그리기 — morph가 모두 새로 생긴 것으로 돌려줌): 띠는 그대로 두고(줄과 함께 제 높이가 흐름) 띠 안의 칸 · 글줄 구분선만,
        그 밖(탭 · 사건 · 알약 · 띠 안 이름 · 단추 · 가는 막대 …)은 통째로. 연대 폭 빗금 · 할거기 칠 · 조명 틀(.tl-spots)은 옛 띠에도 있던 것이라 그대로 (잔상의 띠에서는 숨김),
        이설 조명(.tl-altspot)도 옛 띠에 있었으면 그대로 — 조감에서 나올 때(wasBird — 조감에는 이설 조명이 없음)만 칸과 함께 떠오름 */
    _squashIn(born, g, wasBird = false) {
      const M = HT.motion;
      const keep = wasBird ? '.tl-zone, .tl-spot, .tl-spots' : '.tl-zone, .tl-spot, .tl-spots, .tl-altspot';
      for (const el of born) {
        const list = el.classList.contains('tl-band') ? [...el.children].filter(c => !c.matches(keep)) : [el];
        for (const c of list) this._squashRun(g, c, [{ opacity: 0, offset: 0 }], M.T.in, M.C.ease);
      }
    }

    /** 왼쪽 줄 이름 (흐름 뒤 처음 다시 쓸 때): 새 줄 이름은 옛 높이 · 위 틈에서 흐르며 떠오르고, 옛 줄 이름 칸은 같은 자리에서 새 높이로 함께 흐르며 옅어집니다 — 같은 시계 */
    _squashLabels(tr) {
      const sq = tr._squash;
      sq.labels = true;
      const { o, g } = sq;
      const M = HT.motion;
      const T = M.T;
      const run = (el, kf, dur, easing, fill = 'backwards') => this._squashRun(g, el, kf, dur, easing, fill);
      [...tr.rowsEl.children].forEach((el, i) => {
        const r = o.rows[i];
        if (r && (Math.abs(r.h - tr.rowHs[i]) >= 0.5 || Math.abs(r.mt - tr.rowGap[i]) >= 0.5)) run(el, [{ offset: 0, height: `${r.h}px`, marginTop: `${r.mt}px` }], T.move, M.C.spring);
        run(el, [{ offset: 0, opacity: 0 }], T.in, M.C.ease);
      });
      const old = o.rowsEl;
      if (!old || old.isConnected) return;
      old.classList.add('tl-sqz-rows');
      if (sq.bird) old.classList.add('was-bird', `was-bird-${sq.bird}`); // 조감에서 남은 줄 이름은 조감 모양 그대로 (common.css)
      for (const [k, v] of o.vars) old.style.setProperty(k, v); // 옛 글자 크기 그대로 (새 트랙의 --nameSize를 물려받으면 옛 이름이 커지며 칸을 넘침)
      old.inert = true;
      for (const el of old.querySelectorAll('[data-uid], [data-fold-people]')) {
        el.removeAttribute('data-uid');
        el.removeAttribute('data-fold-people');
      }
      tr.rowsEl.after(old);
      run(old, [{ paddingTop: `${o.rpad}px` }, { paddingTop: `${this._G().pad}px` }], T.move, M.C.spring, 'forwards');
      [...old.children].forEach((el, i) => {
        if (i >= tr.rows) return;
        run(el, [{ height: `${o.rows[i] ? o.rows[i].h : 0}px`, marginTop: `${o.rows[i] ? o.rows[i].mt : 0}px` }, { height: `${tr.rowHs[i]}px`, marginTop: `${tr.rowGap[i]}px` }], T.move, M.C.spring, 'forwards');
      });
      old._ghost = true;
      const a = run(old, [{ opacity: 1 }, { opacity: 0 }], T.out, 'ease-in', 'forwards');
      a.onfinish = a.oncancel = () => old.remove();
    }

    /** 첫 등장 — 맨 처음 자료를 받았을 때 딱 한 번, 연표 전체가 한 몸으로 떠오릅니다(css .tl-inner.is-entering). 필터·저장·미리보기 갱신 때는 다시 재생하지 않습니다.
        떠오르는 동안에는 높이 전환과 세부 효과(_fxOK)를 쉬고, 다 떠오르면(animationend) 표시를 뗍니다 */
    _enter() {
      this._entered = true;
      if (reduceMotion()) return;
      const el = this.innerEl;
      const T = HT.motion.T;
      const done = e => {
        if (e && e.target !== el) return; // 안쪽 요소의 애니메이션 끝 신호는 지나칩니다
        clearTimeout(this._enterTimer);
        this._enterArm = null;
        el.removeEventListener('animationend', done);
        el.classList.remove('is-entering');
      };
      el.classList.add('is-entering');
      el.addEventListener('animationend', done);
      /* 끝 신호가 오지 않을 때(창이 숨어 있음)를 위한 시한 — 첫 그리기가 끝난 뒤부터 잽니다(_draw). 첫 그리기가 늦어져도 그 전에 표시가 떨어져 줄 높이가 흐르는 일이 없게 */
      this._enterArm = () => (this._enterTimer = HT.motion.later((T.move + T.micro) * 2 + 200, () => done()));
    }

    /** 보기 범위를 [s, e]로 옮기는 비행 — 길이(ms)를 돌려줍니다. 세로 이동이 실려 있으면(_carry) 같은 진행값으로 함께 나아가 같은 프레임에 도착합니다 */
    _animateTo(s, e, anchor = null) {
      this._stopAnim();
      this._stopGlide();
      this._arrive = null;
      this._animating = true; // 움직이는 동안 줄 접힘을 미룹니다 (_draw)
      const from = Object.assign({}, this.view);
      const w0 = from.end - from.start;
      const w1 = e - s;
      let at;
      let dur;
      let ease;
      if (reduceMotion()) {
        at = () => [(s + e) / 2, w1];
        dur = 1;
        ease = easeOut;
      } else if (anchor) {
        /* 제자리 확대: 기준 해를 같은 자리에 둔 채 폭만 로그 눈금으로 고르게.
           목표가 범위 끝에서 잘려 기준 해가 조금 옮겨졌으면 그만큼을 고르게 나눠 보정합니다 */
        const lr = Math.log(w1 / w0);
        const miss = s - (anchor.year - anchor.f * w1);
        at = t => {
          const w = w0 * Math.exp(lr * t);
          return [anchor.year - anchor.f * w + miss * t + w / 2, w];
        };
        dur = 300;
        ease = easeOut;
      } else {
        const path = zoomPath((from.start + from.end) / 2, w0, (s + e) / 2, w1);
        at = path.at;
        dur = HT.clamp(260 + path.S * 170, 320, 1100);
        ease = easeInOut;
      }
      /* 방금 고른 줄을 여유 안으로 데려오려던 참이면(아직 출발 전 — setAnchor의 reveal) 그 세로 이동도 이 비행에 싣습니다: 끝나는 시각이 하나 */
      if (!anchor && this._anchorTo != null && this._anchorOff != null && !this._anchorSpring) {
        this._carry = { from: this._anchorOff, to: this._anchorTo, set: v => (this._anchorOff = v) };
        this._anchorTo = null;
      }
      this._beginJump();
      const called = HT.motion.now();
      let t0 = null;
      const step = ts => {
        const now = HT.motion.now(ts);
        if (t0 == null) t0 = Math.max(called, now - 16.7); // 출발은 첫 프레임에서 — 직전의 다시 배치·그리기에 걸린 시간만큼을 첫 프레임에 건너뛰지 않습니다
        const t = HT.clamp((now - t0) / dur, 0, 1);
        const p = t >= 1 ? 1 : ease(t);
        const [u, w] = t >= 1 ? [(s + e) / 2, w1] : at(p);
        this.view = { start: u - w / 2, end: u + w / 2 };
        const cy = this._carry;
        if (cy) cy.set(cy.from + (cy.to - cy.from) * p); // 세로도 같은 진행값으로(_flyRow) — scrollTop은 그리기 끝의 _keepAnchor가 씁니다
        if (t < 1) {
          this._draw();
          this._anim = requestAnimationFrame(step);
          return;
        }
        this._carry = null;
        if (anchor) {
          /* 제자리 확대(setView의 anchor — 단추·키보드 확대는 이제 확대 엔진 _glideTo로 갑니다): 연달아 부르는 사이에 줄이 접혔다 펴지지 않게, 휠처럼 잠깐 기다렸다가 정착 */
          this._draw();
          this._animating = false;
          this._settleSoon();
        } else {
          /* 멀리 가기의 도착: 기다림 없이 이 도착 프레임에서 바로 정착 — 미뤄 둔 줄 접힘이 도착과 함께 흐르기 시작하고, 안내도 같은 순간에 */
          this._animating = false;
          if (!this._settle()) this._draw();
        }
        this._motionEnd();
        this._arrived();
      };
      this._anim = requestAnimationFrame(step);
      return dur;
    }

    _bind() {
      const body = this.bodyEl;
      const pointers = new Map();
      let drag = null;
      let pinch = null;
      let measuring = false;
      const localX = clientX => clientX - body.getBoundingClientRect().left - this.gutter;

      /* 휠·트랙패드: 세로는 커서 자리 기준 확대·축소, 가로(또는 Shift)는 이동. 맨 위 날짜 칸에서도 똑같이.
         확대도 이동도 엔진 하나(_glideTo)로 갑니다 — 작은 입력이 큰 입력의 미끄러짐을 끊던 일이 없습니다. 장치는 제스처의 첫 입력에서 한 번만 가리고(0.16초 넘게 쉬면 새 제스처)
         끝까지 그대로: 한 번에 크게 오는 노치 휠은 70ms로 부드럽게, 잘게 오는 트랙패드·고해상도 휠은 25ms로 손에 바짝 */
      const onWheel = e => {
        e.preventDefault();
        this._stopAnim();
        let dx = e.deltaX;
        let dy = e.deltaY;
        if (e.deltaMode === 1) { dx *= 16; dy *= 16; }
        if (e.deltaMode === 2) { dx *= 400; dy *= 400; }
        if (e.shiftKey) { dx = dx || dy; dy = 0; }
        const now = performance.now(); // 손의 뜻을 읽는 시간이라 실제 시각으로 (느리게 보기와 무관)
        let wg = this._wheelG;
        if (!wg || now - wg.t > 160) wg = this._wheelG = { notch: Math.max(Math.abs(dx), Math.abs(dy)) >= 40, t: now };
        wg.t = now;
        const tau = wg.notch ? CHASE.notch : CHASE.fine;
        if (Math.abs(dx) > Math.abs(dy)) this.panBy((dx * this.span()) / this.W, { smooth: true, tau });
        else {
          const f = Math.exp(dy * 0.0018);
          /* 기준 띠(잘리지 않게 붙잡을 띠 — zoomAt)는 연달아 굴리는 동안(0.45초 안, 커서가 거의 그대로) 처음 고른 것을 유지 — 붙잡느라 옮겨진 뒤 커서 아래에 온 옆 띠로 바뀌지 않게 */
          let focus = null;
          if (f < 1 && localX(e.clientX) >= 0 && body.contains(e.target)) {
            const wf = this._wheelFocus;
            const keep = wf && now - wf.t < 450 && Math.abs(wf.x - e.clientX) < 24 && Math.abs(wf.y - e.clientY) < 24 ? wf.p : null;
            focus = keep || this._bandAt(e.target, this.yearAtClientX(e.clientX));
            this._wheelFocus = focus ? { p: focus, t: now, x: keep ? wf.x : e.clientX, y: keep ? wf.y : e.clientY } : null;
          } else this._wheelFocus = null;
          this.zoomAt(f, localX(e.clientX), { focus, smooth: true, tau });
        }
        this._touchJump();
      };
      body.addEventListener('wheel', onWheel, { passive: false });
      this.axisEl.addEventListener('wheel', onWheel, { passive: false });
      /* 마지막 커서 위치(연표 안쪽 x) — 단추·키보드 확대의 기준점 */
      const trackHover = e => {
        const x = localX(e.clientX);
        this._hoverX = x >= 0 && x <= this.W ? x : null;
      };
      this.axisEl.addEventListener('pointermove', trackHover);
      this.axisEl.addEventListener('pointerleave', () => (this._hoverX = null));

      /* 마우스로 줄 이름·민족 칸 같은 단추를 누를 때 브라우저가 그 단추를 초점에 두며 화면을 스크롤하는 일이 없게:
         기본 동작을 막고 초점은 연표 몸통에 (스크롤 없이). 키보드로는 여전히 Tab으로 갈 수 있습니다 */
      body.addEventListener('mousedown', e => {
        if (e.button !== 0 || e.target.closest('input, select, textarea, [contenteditable=""], [contenteditable="true"]')) return;
        e.preventDefault();
        if (document.activeElement !== body) body.focus({ preventScroll: true });
      });
      /* 손의 표본을 찍는 시각: 진짜 입력은 기기가 적은 시각(그리기가 밀려 늦게 전달돼도 정확), 시험용 합성 입력은 지금 시각. 손을 읽는 시간이라 느리게 보기와 무관합니다 */
      const stamp = e => (e.isTrusted && e.timeStamp > 0 ? e.timeStamp : performance.now());
      body.addEventListener('pointerdown', e => {
        const coasting = this._stopCoast(); // 어떤 누름이든(스크롤 막대 · 오른쪽 단추도) 관성은 그 자리에서 멈춥니다
        if (coasting) this._motionEnd();
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        if (e.clientX - body.getBoundingClientRect().left > body.clientWidth) return;
        this._stopAnim();
        if (this._anchorSpring || this._anchorTo != null) this._anchorRebase(); // 세로로 데려오던 중이면 누르는 순간 그 자리에 멈춥니다
        if (this._held) this._held.spring = this._held.to = null;
        this._arrive = null; // 도중에 눌러 멈췄으면 도착 표시도 하지 않습니다
        if (this._settleDue) {
          /* 정착을 기다리던 중에 다시 눌렀으면 그 예약을 거둡니다 — 손에 잡힌 동안 줄이 접히지 않게 (끊어 끌기). 손을 떼면 다시 겁니다(finish) */
          clearTimeout(this._settleTimer);
          this._settleHeld = true;
        }
        try {
          body.setPointerCapture(e.pointerId);
        } catch (err) {
          /* 시험용 합성 포인터(활성 포인터가 아님)는 붙잡을 수 없습니다 — 끌기·누르기 처리는 그대로 이어 갑니다 */
        }
        pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (this.measureMode && pointers.size === 1) {
          const y = this.yearAtClientX(e.clientX);
          this.measure = { a: y, b: y };
          measuring = true;
          drag = null;
          this.render();
          return;
        }
        if (pointers.size === 1) {
          this._stopGlide();
          /* grabbed: 아직 빠르게 미끄러지던 관성을 잡아 세운 누름 — 멈추려던 것이지 고르려던 것이 아니므로, 그대로 떼어도 고르기·접기로 치지 않습니다(finish). 거의 멎은 뒤(COAST.grab 아래)의 누름은 평소대로 */
          drag = { x: e.clientX, y: e.clientY, view: Object.assign({}, this.view), scroll: body.scrollTop, moved: false, target: e.target, grabbed: coasting >= COAST.grab, path: 0, samples: [{ t: stamp(e), x: e.clientX, y: e.clientY }] };
        } else if (pointers.size === 2) {
          const [a, b] = [...pointers.values()];
          const cx = localX((a.x + b.x) / 2);
          pinch = { dist: Math.hypot(a.x - b.x, a.y - b.y) || 1, span: this.span(), year: this.view.start + (cx / this.W) * this.span() };
          drag = null;
          this._pinching = true; // 두 손가락 확대도 "손에 잡힌 동안" — 줄이 접히지 않고 세부 효과는 조용히 (_inMotion)
        }
        this._motionEnd(); // 눌러서 미끄러짐·비행을 멈췄으면 고요 표시도 여기서 뗍니다
      });

      body.addEventListener('pointermove', e => {
        trackHover(e);
        if (!pointers.has(e.pointerId)) {
          this._hover(e.target);
          return;
        }
        pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (measuring) {
          this.measure.b = this.yearAtClientX(e.clientX);
          this.render();
          return;
        }
        if (pinch && pointers.size >= 2) {
          const [a, b] = [...pointers.values()];
          const dist = Math.hypot(a.x - b.x, a.y - b.y) || 1;
          const span = HT.clamp((pinch.span * pinch.dist) / dist, MIN_SPAN, this._maxSpan());
          const s = pinch.year - (localX((a.x + b.x) / 2) / this.W) * span;
          this.setView(s, s + span);
          return;
        }
        if (!drag) return;
        /* 손의 표본(마지막 80ms 남짓만 남김)과 끌어 온 길이 — 놓는 순간의 속도를 여기서 읽어 관성으로 잇습니다 (releaseVelocity) */
        const at = stamp(e);
        const prev = drag.samples[drag.samples.length - 1];
        if (prev) drag.path += Math.hypot(e.clientX - prev.x, e.clientY - prev.y);
        drag.samples.push({ t: at, x: e.clientX, y: e.clientY });
        while (drag.samples.length > 2 && at - drag.samples[0].t > 100) drag.samples.shift();
        if (!drag.moved) {
          if (Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 5) return;
          /* 끌기의 문턱(5px)을 넘는 순간: 기준점을 지금 자리로 다시 잡습니다 — 문턱만큼의 거리가 첫 프레임에 한꺼번에 튀어나오지 않고, 화면은 여기서부터 손을 따라갑니다 */
          Object.assign(drag, { x: e.clientX, y: e.clientY, view: Object.assign({}, this.view), scroll: body.scrollTop, moved: true });
          this._beginJump();
          this.hideCard();
          body.classList.add('is-dragging');
        }
        const dx = e.clientX - drag.x;
        const dy = e.clientY - drag.y;
        const years = (-dx * (drag.view.end - drag.view.start)) / this.W;
        this.setView(drag.view.start + years, drag.view.end + years);
        body.scrollTop = drag.scroll - dy;
      });

      body.addEventListener('pointerover', e => {
        this._hover(e.target);
        this._cardHover(e.target);
      });
      body.addEventListener('pointerleave', () => {
        this._hover(null);
        this._cardHover(null);
        this._hoverX = null;
      });
      /* 성씨 풍선(D1 결정 6 A): 지도자 칸 · 왕조 칸에 올리면 — 누르거나 스크롤하면 걷힘 (옮기기 · 확대는 _draw가 걷음) */
      body.addEventListener('pointerover', e => this._tipHover(e));
      body.addEventListener('pointerleave', () => this._tipHover(null));
      body.addEventListener('pointerdown', () => this.hideTip(true), true);
      body.addEventListener('scroll', () => this._tip.key && this.hideTip(true), { passive: true });
      /* 사용자가 직접 위아래로 옮기면 가장자리 안내는 물러납니다 */
      body.addEventListener('scroll', () => {
        if (this.anchorUid && performance.now() - this._selfScroll > 700) this._anchorRebase(); // 사용자가 직접 옮겼으면 그 자리가 새 기준
        /* 조감에서 손으로 위아래로 옮겼으면(우리가 둔 값에서 8px 넘게 — 가로로 끄는 동안의 떨림은 빼고) 나올 때 그 자리에서 (들기 전에 보던 줄로 돌아가지 않음 — _birdBack).
           줄을 붙잡는 동안(_loopOn — 흐르는 높이에 브라우저가 깎은 스크롤)과 다시 지은 직후의 깎임은 손으로 옮긴 것이 아님 */
        if (this._birdBack && !this._loopOn && Math.abs(body.scrollTop - (this._selfTop ?? body.scrollTop)) >= 8 && performance.now() - (this._rebuiltAt || 0) > 150) this._birdBack = null;
        if (!this._jump && this.hintEl && !this.hintEl.hidden && performance.now() - (this._hintAt || 0) > 700) this._hideEdgeHint();
        if (this._card.id && !this._card.pinned) this.hideCard();
        if (this.tracks.some(tr => tr._stale || tr._rowsVirtual)) this.render(true); // 아직 안 그린 트랙·줄이 화면에 들어오면
      }, { passive: true });

      /* 연표 몸통의 단추: 누름(아래 finish의 pointerup)과 키보드(초점 → Enter · Space — 아래 click)가 같은 길로. t = 누른 자리의 요소, before = 맡기로 했을 때 먼저 할 정리.
         맡았으면 true — 민족 딱지 · 할거 단추 · 소속 단추 · 민족 칸 · 접힌 줄 이름 · 트랙 이름(접기) */
      const pressButton = (t, before) => {
        /* 민족 딱지(8-4 사): 접기 단추가 아니라 그 민족의 문서를 엽니다 (opts.onPeople) */
        const pdoc = t && t.closest('[data-people-doc]');
        if (pdoc) {
          before();
          if (this.opts.onPeople) this.opts.onPeople(pdoc.dataset.peopleDoc);
          return true;
        }
        /* 본국 띠의 '▸ 〈성격〉 n' 단추(8-4 바): 그 대범위의 모아 보기를 켜고 끕니다 — 누른 줄(본국 줄)은 제자리 (위쪽 줄이 빠지면 스크롤이 모여듦과 같은 곡선으로 따라감 — _gatherHold) */
        const scopeBtn = t && t.closest('[data-scope]');
        if (scopeBtn) {
          before();
          this._pressHold = this._holdOf(scopeBtn);
          this.toggleScope(scopeBtn.dataset.scope);
          return true;
        }
        /* 집합 보기 테두리의 이름표: 판 목록을 엽니다 (켜고 끄기는 목록의 스위치 — opts.onBoardName) */
        const boardName = t && t.closest('[data-board-name]');
        if (boardName) {
          before();
          if (this.opts.onBoardName) this.opts.onBoardName(boardName);
          return true;
        }
        const sphere = t && t.closest('[data-sphere]'); // 서고 3단: 문화권 머리 단 어디를 눌러도 접고 폄
        if (sphere) {
          before();
          this.toggleFoldSphere(sphere.dataset.sphere);
          return true;
        }
        const members = t && t.closest('[data-fold-members]');
        const hangs = t && t.closest('[data-fold-hangs]');
        const foldPeople = t && t.closest('[data-fold-people]');
        const fold = t && t.closest('[data-fold]');
        if (members || hangs || foldPeople || fold) {
          before();
          this._pressHold = this._holdOf(members || hangs || foldPeople || fold); // 누른 단추의 줄을 다시 배치하는 동안 제자리에 (_snapshot)
          if (members) this.toggleMembers(members.dataset.foldMembers);
          else if (hangs) this.toggleHangs(hangs.dataset.foldHangs);
          else if (foldPeople) this.toggleFoldPeople(foldPeople.dataset.foldPeople);
          else this.toggleFold(fold.dataset.fold);
          return true;
        }
        return false;
      };
      /* 키보드로 누른 단추: 초점이 간 단추에서 Enter · Space를 누르면 브라우저가 click(detail 0)을 보냅니다 — 마우스 · 손가락의 누름은 pointerup이 이미 맡았으므로(그 click은 detail ≥ 1) 이것만.
         초점 모양은 단추마다(:focus-visible — .tl-pchip · .tl-people · .tl-tname …) */
      body.addEventListener('click', e => {
        if (e.detail !== 0 || !e.target.closest) return;
        const b = e.target.closest('button');
        if (b && body.contains(b) && pressButton(b, () => {})) e.preventDefault();
      });

      const finish = e => {
        if (!pointers.has(e.pointerId)) return;
        pointers.delete(e.pointerId);
        if (pointers.size === 0 && this._settleHeld) {
          this._settleHeld = false;
          if (this._settleDue) this._settleSoon(); // 누르는 동안 거둬 둔 정착을 손을 뗀 지금부터 다시 기다립니다
        }
        if (measuring) {
          measuring = false;
          const a = Math.min(this.measure.a, this.measure.b);
          const b = Math.max(this.measure.a, this.measure.b);
          if (b - a < this.span() * 0.005) this.measure = null;
          this.render();
          if (this.opts.onMeasure) this.opts.onMeasure(this.measure ? { from: a, to: b } : null);
          return;
        }
        if (drag && drag.moved && pointers.size === 0) {
          /* 놓기: 손에 속도가 있으면 그 속도로 미끄러지다 멎고(관성 — 멎은 프레임에 바로 정착), 없으면 그 자리가 새 기준이고 잠깐 뒤에 정착(끊어 끌 때 줄이 숨 쉬지 않게) */
          const [vx, vy] = e.type === 'pointerup' && drag.path >= COAST.travel ? releaseVelocity(drag.samples, stamp(e)) : [0, 0];
          if (!this._coastFrom(vx, vy)) {
            this._rehold();
            this._settleSoon();
          }
        }
        const tap = drag && !drag.moved && !drag.grabbed && e.type === 'pointerup' && pointers.size === 0; // 관성을 잡아 세운 누름(grabbed)은 고르기도 접기도 아닙니다
        if (tap) {
          const t = drag.target && drag.target.closest ? drag.target : null;
          /* 묶음 알약: 누르면 그 구간으로 확대(묶인 점들이 제자리로 풀려 나옴). 모두 같은 때라 더 확대할 수 없으면 목록을 고정 */
          const clu = t && t.closest('.tl-clu[data-cluster]');
          if (clu) {
            drag = pinch = null;
            body.classList.remove('is-dragging');
            this._clusterClick(clu);
            return;
          }
          if (
            pressButton(t, () => {
              drag = pinch = null;
              body.classList.remove('is-dragging');
            })
          )
            return;
        }
        if (tap && this.opts.onSelect) {
          const hit = drag.target && drag.target.closest && drag.target.closest('[data-uid]');
          const cell = hit && drag.target.closest('[data-cell]'); // 지도자·내각 칸을 눌렀으면 그 칸도
          this.opts.onSelect(hit ? hit.dataset.uid : null, Math.round(this.yearAtClientX(e.clientX)), { cell: cell ? cell.dataset.cell : undefined, multi: e.ctrlKey || e.metaKey });
        }
        if (pointers.size === 0) {
          drag = pinch = null;
          this._pinching = false;
          body.classList.remove('is-dragging');
          this._motionEnd();
        } else if (pointers.size === 1) {
          const [p] = [...pointers.values()];
          pinch = null;
          this._pinching = false;
          body.classList.add('is-dragging'); // 남은 손가락의 끌기로 이어집니다 — 그 사이에도 손에 잡힌 채
          drag = { x: p.x, y: p.y, view: Object.assign({}, this.view), scroll: body.scrollTop, moved: true, target: null, path: 0, samples: [] };
        }
      };
      body.addEventListener('pointerup', finish);
      body.addEventListener('pointercancel', finish);

      /* 연표에 초점이 있을 때의 키: 화살표 = 옆으로(화면의 15%씩, 미끄러져 감 — 누르고 있으면 목표가 쌓임) · + − = 확대·축소(단추와 같은 폭) · 0 = 전체 보기.
         처리한 키는 preventDefault로 표시합니다 — 페이지의 단축키 처리기(viewer.js)가 같은 키를 한 번 더 실행하지 않게. Ctrl·Alt·⌘과 함께면 브라우저의 것(화면 확대 등) */
      const onKey = e => {
        if (e.ctrlKey || e.metaKey || e.altKey || e.defaultPrevented) return;
        const base = this._glide ? this._glide.to : this.view;
        const span = base.end - base.start;
        const keys = {
          ArrowLeft: () => this.panBy(-span * 0.15, { smooth: true }),
          ArrowRight: () => this.panBy(span * 0.15, { smooth: true }),
          '+': () => this.zoom(0.6),
          '=': () => this.zoom(0.6),
          '-': () => this.zoom(1.6),
          '0': () => this.fitAll(),
        };
        if (keys[e.key]) {
          e.preventDefault();
          keys[e.key]();
        }
      };
      body.addEventListener('keydown', e => {
        const coasting = this._stopCoast(); // 어떤 키든 관성은 그 자리에서 멈춥니다 (키보드로 세로로 옮기는 것과 다투지 않게)
        onKey(e);
        if (coasting) this._motionEnd(); // 키가 미끄러짐으로 잇지 않았으면 고요 표시도 여기서 뗍니다
      });
    }

    /* ---------- 나타남·묶임의 움직임 ---------- */
    /** 지금 손에 잡혀 있는가 — 끌기 · 놓은 뒤의 관성(_coast) · 두 손가락 확대 · 휠과 단추·키의 미끄러짐(_glide) · 멀리 가기(_animating) */
    _inMotion() {
      return this.bodyEl.classList.contains('is-dragging') || !!this._coast || !!this._pinching || !!this._glide || !!this._animating;
    }

    /** 움직임이 멎은 순간: 고요 표시(.tl.is-moving)를 떼고, 움직이는 동안 지나친 호버가 아직 손 밑에 있으면 이제 비춥니다. 세부 효과의 단계(_moving)는 다음 그리기가 다시 정합니다 */
    _motionEnd() {
      if (this._inMotion()) return;
      this.root.classList.remove('is-moving');
      const t = this._hoverMissed;
      this._hoverMissed = null;
      if (!t || !t.isConnected || !t.matches(':hover')) return;
      this._hover(t);
      this._cardHover(t);
      this._tipHover({ target: t });
    }

    /** 세부 효과의 세 단계: 'full' 멈춰 있을 때 · 'quiet' 움직이는 중(제자리 120ms 투명도만 — 미끄러짐·부풂·잔상 없음. 막지 않고 조용히: 갑자기 생기거나 사라지지 않습니다)
        · 'off' 동작 줄이기 · 첫 등장 중 · 창이 숨어 있을 때 */
    _fxMode() {
      if (reduceMotion() || this.innerEl.classList.contains('is-entering') || (typeof document !== 'undefined' && document.visibilityState === 'hidden')) return 'off';
      return this._moving ? 'quiet' : 'full';
    }

    _fxOK() {
      return this._fxMode() !== 'off';
    }

    /** 문턱은 두 개 — 확대 수준에 따라 바뀌는 것(이름이 붙는 단계 · 간지·보조 달력 줄의 단계)이 경계 근처에서 멈췄을 때 깜빡이지 않게:
        v가 th 이상이면 켜지고, 한 번 켜지면 th보다 8%(LOD_GAP) 아래로 내려가야 꺼집니다. 확대 정도에만 씁니다 — 옆으로 옮기는 것과 무관해서 "자리는 자료가 정한다"를 건드리지 않습니다 */
    _past(key, v, th) {
      const on = this._lod.get(key) ? v >= th * (1 - LOD_GAP) : v >= th;
      this._lod.set(key, on);
      return on;
    }

    /** 눈금 간격 고르기(가장 촘촘하면서 간격이 min px 이상인 것)의 두 문턱: 지금 쓰는 간격은 8% 더 좁아질 때까지 그대로 두고, 더 촘촘한 간격으로는 제 문턱(min)에서 바로 넘어갑니다 */
    _stepAt(key, steps, k, min) {
      const plain = steps.find(s => s * k >= min);
      const cur = this._lod.get(key);
      const step = cur != null && (plain == null || cur < plain) && cur * k >= min * (1 - LOD_GAP) ? cur : plain;
      this._lod.set(key, step);
      return step;
    }

    /** morph에 넘기는 효과 설정 { W, quiet, out(사라지는 요소) } — 효과를 쉴 때는 null. tr = 그 줄들의 트랙(날짜 칸이면 없음): 요소들이 마지막으로 그려진 보기를 거기서 읽습니다 */
    _fx(W, tr = null) {
      if (this._sceneRendering) return null;
      const mode = this._fxMode();
      if (mode === 'off') return null;
      const quiet = mode === 'quiet';
      const from = tr ? tr._view : this._drawn;
      /* 띠 · 인물 막대의 속(morph의 한 겹 더): 키가 붙은 속 요소만 제자리에서 옅어지고(띠가 움직이면 띠와 함께) · 떠오릅니다 — 화면 가장자리에서 밀려 들고 나는 것은 그대로 */
      const onScreen = (el, host) => {
        const x = (parseFloat(host.style.left) || 0) + (parseFloat(el.style.left) || 0);
        return x > 24 && x < W - 24;
      };
      const deep = {
        W,
        quiet,
        out: el => {
          if (!el.dataset.k || !onScreen(el, el.parentNode) || (quiet && this._fxN >= FX_BUDGET)) return el.remove();
          this._fxN++;
          fadeOut(el, quiet ? HT.motion.T.micro : HT.motion.T.out, quiet ? 'linear' : 'ease-in');
        },
        born: (els, host) => {
          if (els.length > 80) return;
          for (const el of els) if (onScreen(el, host)) this._fadeIn(el, quiet);
        },
      };
      return { W, quiet, out: el => this._linger(el, from, quiet), deep };
    }

    /** 화면 안에서 사라지는 요소: 화면에 얼어붙지 않게 제가 있던 해(세계 좌표)를 따라가며 옅어집니다 — 멈춰 있을 때는 (보기가 그대로이니) 제자리에서 160ms, 움직이는 중에는 120ms.
        from = 그 요소가 마지막으로 그려진 보기 { start, k } — 거기서 자리(해)를 되읽고, 그리기마다 _lingerMove가 옮깁니다 */
    _linger(el, from, quiet) {
      const l = parseFloat(el.style.left);
      if (!from || isNaN(l)) return quiet ? el.remove() : fadeOut(el);
      if (quiet && this._fxN >= FX_BUDGET) return el.remove();
      const w = parseFloat(el.style.width);
      el._wt = from.start + l / from.k;
      el._wt2 = w > 0 ? from.start + (l + w) / from.k : null;
      const k = this.W / this.span();
      if (from.start !== this.view.start || from.k !== k) {
        this._lingerPlace(el, this.view.start, k);
        if (!inViewX(el, this.W)) return el.remove(); // 옮기고 보니 화면 밖 — 옅어질 것도 없습니다
      }
      this._lingers.add(el);
      this._fxN++;
      fadeOut(el, quiet ? HT.motion.T.micro : HT.motion.T.out, quiet ? 'linear' : 'ease-in', () => this._lingers.delete(el));
    }

    _lingerPlace(el, start, k) {
      const l = (el._wt - start) * k;
      el.style.left = `${cx(l)}px`;
      if (el._wt2 != null) el.style.width = `${cx(Math.max(0, (el._wt2 - start) * k - l))}px`;
    }

    _lingerMove(start, k) {
      for (const el of this._lingers) {
        if (!el.isConnected) this._lingers.delete(el);
        else this._lingerPlace(el, start, k);
      }
    }

    /** 새로 생긴 것 하나를 떠오르게: 끝 밝기는 적지 않습니다 — 제 밝기(고른 것이 있어 어두워진 장면이면 그 밝기)로 떠올라, 밝게 태어났다가 툭 어두워지지 않습니다.
        멈춰 있을 때 200ms(--t-in), 움직이는 중 120ms(--t-micro) */
    _fadeIn(el, quiet = this._moving) {
      if (quiet && this._fxN >= FX_BUDGET) return;
      this._fxN++;
      const M = HT.motion;
      el.animate([{ opacity: el._from || 0, offset: 0 }], { duration: quiet ? M.T.micro : M.T.in, easing: quiet ? 'linear' : M.C.ease });
    }

    /** 한 줄에서 새로 생긴 요소를 다듬습니다 — 제자리에서 투명도로만: 새 점·띠·묶음 알약은 떠오르고(_fadeIn), 점에 새로 붙은 이름은 글자만 떠오릅니다.
        멈춰 있을 때 200ms(--t-in), 움직이는 중(quiet) 120ms(--t-micro). 튀는 알약·모여드는 잔상·풀려나는 미끄러짐·이름 미끄러짐은 없습니다 — 확대 자체가 점을 모으고 흩으므로 덧붙일 것이 없습니다.
        화면 가장자리에서 밀려 들어온 것(옆으로 옮길 때)은 그대로 둡니다 */
    _laneFx({ born, relabeled }, W, quiet = false) {
      if (born.length > 80) return;
      const M = HT.motion;
      for (const el of born) {
        const x = parseFloat(el.style.left);
        if (x > 24 && x < W - 24) this._fadeIn(el, quiet);
      }
      for (const el of relabeled) {
        if (quiet && this._fxN >= FX_BUDGET) break;
        el.querySelectorAll('.t, .y, .cnt').forEach(c => c.animate([{ opacity: 0, offset: 0 }], { duration: quiet ? M.T.micro : M.T.in, easing: quiet ? 'linear' : M.C.ease }));
        this._fxN++;
      }
    }

    /** 다시 지은 줄의 첫 그리기에서: 앞선 화면의 같은 줄에 있다가 이번에 없어진 것(필터로 끈 분류·종류)을 제자리에서 옅어지며 물러나게 합니다.
        줄이 낮아져 새 띠 밖으로 삐져나올 것과 화면 밖의 것은 그냥 둡니다 */
    _fadeGone(tr, row, oldLane, W) {
      const lane = tr.laneEls[row];
      if (!oldLane || !lane) return;
      const now = new Set();
      for (const c of lane.children) if (c.dataset.k) now.add(c.dataset.k);
      const room = (tr.rowHs[row] || 0) - ((tr.rowCut && tr.rowCut[row]) || 0);
      let n = 0;
      for (const o of [...oldLane.children]) {
        const k = o.dataset.k;
        if (!k || o._ghost || now.has(k) || !inViewX(o, W)) continue;
        if ((parseFloat(o.style.top) || 0) + 12 > room || ++n > 60) continue;
        lane.appendChild(o);
        fadeOut(o);
      }
    }

    /* ---------- 겹친 사건 묶음 카드 ---------- */
    _clusterClick(el) {
      const c = this._clusters.get(el.dataset.cluster);
      if (!c) return;
      const span = c.t1 - c.t0;
      if (span > MIN_SPAN * 2) {
        /* 묶음이 풀릴 만큼 확대: 묶인 점들 사이가 화면의 절반쯤 되게 */
        this.hideCard(true);
        const w = Math.max(span / 0.5, MIN_SPAN * 3);
        const mid = (c.t0 + c.t1) / 2;
        this.setView(mid - w / 2, mid + w / 2, { animate: true });
      } else this.showCard(el.dataset.cluster, el, true);
    }

    _cardHover(target) {
      let el = target && target.closest ? target.closest('[data-cluster]') : null;
      const card = this._card;
      if (target && target.closest && target.closest('.tl-card')) return;
      clearTimeout(card.timer);
      if (card.pinned) return;
      /* 움직이는 동안(과 우리가 세로로 옮긴 직후 0.2초)은 고요: 손 밑을 지나가는 알약마다 목록이 열리지 않습니다 — 멎은 뒤에도 그 위에 있으면 그때 (_motionEnd) */
      if (el && (this._inMotion() || performance.now() - this._selfScroll < 200)) {
        this._hoverMissed = target;
        el = null;
      }
      if (el) {
        if (card.id === el.dataset.cluster && this.cardEl && !this.cardEl.hidden) return;
        card.timer = setTimeout(() => this.showCard(el.dataset.cluster, el, false), card.id ? 60 : 160);
      } else if (card.id) card.timer = setTimeout(() => this.hideCard(), 220);
    }

    /** 묶음의 사건 목록 카드. 줄을 누르면 그 사건을 고르고(고른 사건은 묶음에서 빠져 이름이 붙음), "이 구간 확대"로 펼칩니다 */
    showCard(id, anchor, pin) {
      const c = this._clusters.get(id);
      if (!c) return this.hideCard(true);
      if (!this.cardEl) {
        const el = (this.cardEl = document.createElement('div'));
        el.className = 'tl-card';
        el.hidden = true;
        el.setAttribute('role', 'dialog');
        this.root.appendChild(el);
        el.addEventListener('pointerleave', () => {
          if (!this._card.pinned) this._card.timer = setTimeout(() => this.hideCard(), 220);
        });
        el.addEventListener('pointerenter', () => clearTimeout(this._card.timer));
        el.addEventListener('click', ev => {
          const row = ev.target.closest('[data-card-uid]');
          const zoom = ev.target.closest('[data-card-zoom]');
          const close = ev.target.closest('[data-card-close]');
          if (close) return this.hideCard(true);
          if (zoom) {
            const cur = this._clusters.get(this._card.id);
            if (cur) {
              const w = Math.max((cur.t1 - cur.t0) / 0.5, MIN_SPAN * 3);
              const mid = (cur.t0 + cur.t1) / 2;
              this.hideCard(true);
              this.setView(mid - w / 2, mid + w / 2, { animate: true });
            }
            return;
          }
          if (row && this.opts.onSelect) {
            this.hideCard(true);
            this.opts.onSelect(row.dataset.cardUid, HT.yearOf(Number(row.dataset.cardT)));
          }
        });
      }
      const when = x => {
        if (x.startUnknown) return '미정';
        const at = HT.atOf(x, 'start');
        const r = at && HT.cal.parse(at);
        return r && r.ok && r.prec !== 'y' ? HT.cal.formatT(x.start, r.prec === 'm' ? 'm' : 'd') : HT.formatYear(x.start);
      };
      const items = c.items.slice().sort((a, b) => a.start - b.start || (b.importance || 2) - (a.importance || 2));
      const MAX = 9;
      /* 머리글의 범위는 지금 눈금 단위만큼 자세히 (해 눈금이면 해, 달·날 눈금이면 그만큼) — 같으면 하나만 */
      const prec = !this._sub ? 'y' : this._sub.unit === 'mo' ? 'm' : this._sub.unit === 'd' ? 'd' : 'h';
      const fmt = v => (prec === 'y' ? HT.formatYear(v) : HT.cal.formatT(v, prec));
      const r0 = fmt(c.t0);
      const r1 = fmt(c.t1);
      const range = r0 === r1 ? r0 : `${r0} ~ ${r1}`;
      const canZoom = c.t1 - c.t0 > MIN_SPAN * 2;
      this.cardEl.innerHTML = `<div class="tc-head"><i class="tc-mark" style="--c:${c.color}"></i><b>사건 ${items.length}개</b><span>${esc(range)}</span>${pin ? '<button type="button" class="tc-x" data-card-close aria-label="닫기">✕</button>' : ''}</div>
        <div class="tc-list">${items
          .slice(0, MAX)
          .map(x => `<button type="button" class="tc-row${x.uid === this.selected ? ' is-selected' : ''}" data-card-uid="${esc(x.uid)}" data-card-t="${x.start}"><i class="tc-dot${x.treaty ? ' is-treaty' : ''}" style="--c:${x.color}"></i><span class="tc-when">${esc(when(x))}</span><span class="tc-title">${esc(this.titleFor(x, x.track))}</span>${(x.importance || 2) >= 3 ? '<i class="tc-star">★</i>' : ''}</button>`)
          .join('')}</div>
        <div class="tc-foot">${items.length > MAX ? `<span>외 ${items.length - MAX}개</span>` : '<span></span>'}${canZoom ? '<button type="button" class="tc-zoom" data-card-zoom>⤢ 이 구간 확대</button>' : ''}</div>`;
      this._card.id = id;
      this._card.pinned = !!pin;
      if (pin) openCards.add(this);
      this.root.querySelectorAll('.is-carded').forEach(x => x.classList.remove('is-carded'));
      if (anchor) anchor.classList.add('is-carded');
      /* 자리: 알약 바로 아래(모자라면 위), 가로는 연표 안에 */
      const el = this.cardEl;
      el.getAnimations().forEach(a => a.cancel());
      el.classList.remove('is-leaving');
      el.hidden = false;
      const rr = this.root.getBoundingClientRect();
      const ar = anchor.getBoundingClientRect();
      const b = anchor.querySelector('b') || anchor.querySelector('.d') || anchor;
      const br = b.getBoundingClientRect();
      const w = el.offsetWidth;
      const h = el.offsetHeight;
      let left = br.left + br.width / 2 - rr.left - w / 2;
      left = HT.clamp(left, this.gutter + 6, rr.width - w - 10);
      let top = ar.bottom - rr.top + 4;
      let below = true;
      if (top + h > rr.height - 8) {
        top = ar.top - rr.top - h - 4;
        below = false;
      }
      el.style.left = `${left.toFixed(1)}px`;
      el.style.top = `${Math.max(4, top).toFixed(1)}px`;
      el.style.setProperty('--nub', `${(br.left + br.width / 2 - rr.left - left).toFixed(1)}px`);
      el.classList.toggle('is-above', !below);
      el.classList.toggle('is-pinned', !!pin);
    }

    hideCard(force = false) {
      if (!this.cardEl || (this._card.pinned && !force)) return;
      clearTimeout(this._card.timer);
      const el = this.cardEl;
      if (!el.hidden && !reduceMotion()) {
        /* 스르륵 닫기 — 그 사이 다시 열리면 취소됩니다 (showCard) */
        el.classList.add('is-leaving');
        const a = el.animate([{ opacity: 1 }, { opacity: 0, transform: 'translateY(2px)' }], { duration: 150, easing: 'ease-in' });
        a.onfinish = () => {
          if (el.classList.contains('is-leaving')) {
            el.hidden = true;
            el.classList.remove('is-leaving');
          }
        };
      } else el.hidden = true;
      this._card.id = null;
      this._card.pinned = false;
      openCards.delete(this);
      this.root.querySelectorAll('.is-carded').forEach(x => x.classList.remove('is-carded'));
    }

    /* ---------- 성씨 풍선 (D1 결정 6 A — 확정 설계 5-2) ----------
       지도자 칸 · 왕조 칸에 마우스를 올리면 칸 아래 8px에 묶음 카드(.tl-card)와 같은 유리 카드: 머리 = 이름 · 기간, 줄 = 성씨 · 본관 · 가문(가문 색 점 · 파면 본가 길) · 왕조,
       원어 한 줄, 칸의 메모 · 다른 견해, 바닥 = 누르는 길 한 줄. 없는 줄은 뺍니다. 띠 높이는 그대로이고, 화면 끝에서는 화면 안으로 비킵니다(아래 자리가 없으면 칸 위).
       풍선이 뜨는 칸은 브라우저 설명글(title)을 걷고 aria-label로 옮겨(title="" — 띠의 설명글도 물려받지 않음) 두 겹으로 뜨지 않습니다.
       가문 줄을 누르면 가문 창(가문 조명 — opts.onSelect('house:<id>')), 성씨 줄을 누르면 성씨 창(onSelect('surname:<id>')). 올림이 없는 손가락 · 펜에는 띄우지 않음(휴대폰은 창의 배지) */
    _tipHover(e) {
      const tip = this._tip;
      const t = e && e.target;
      clearTimeout(tip.timer);
      if (e && e.pointerType) tip.mouse = e.pointerType === 'mouse'; // 마지막 손이 마우스인가 (움직임이 멎은 뒤 _motionEnd가 부를 때는 이것으로)
      let el = t && t.closest ? t.closest('.tl-band .tl-cell.k-leader[data-cell], .tl-band .tl-dyn[data-uid]') : null;
      if (el && !tip.mouse) el = null;
      if (el && (this._inMotion() || performance.now() - this._selfScroll < 200)) el = null; // 움직이는 동안은 고요 (멎은 뒤 _motionEnd가 다시)
      if (el) {
        if (this._tipKey(el) === tip.key && tip.el && !tip.el.hidden) return;
        tip.timer = setTimeout(() => this._showTip(el), tip.key ? 60 : 160);
      } else if (tip.key) tip.timer = setTimeout(() => this.hideTip(), 220);
    }

    /** 풍선의 열쇠 — 띠(정권) + 칸 ('uid|leader:3' · 'uid|dyn:왕조 uid') */
    _tipKey(el) {
      const band = el.closest('.tl-band');
      return band ? `${band.dataset.uid}|${el.dataset.cell || `dyn:${el.dataset.uid}`}` : null;
    }

    /** 가문 표(id → 가문): setData의 houseMap, 없으면 이 연표를 쓰는 뷰어의 모델 것 (뷰어가 넘기기 전의 대역 길) */
    _houseMapNow() {
      if (this._data && this._data.houseMap) return this._data.houseMap;
      const v = HT.viewer;
      return v && v.timeline === this && v.state && v.state.model && v.state.model.houseMap ? v.state.model.houseMap : null;
    }

    /** 풍선의 글(HTML) — 칸 요소 el. 못 풀면 null */
    _tipHTML(el) {
      const band = el.closest('.tl-band');
      const trEl = el.closest('.tl-track');
      const tr = band && trEl && (this.tracks || []).find(t => t.id === trEl.dataset.track);
      const p = tr && tr.periods.find(q => q.uid === band.dataset.uid);
      if (!p) return null;
      let head;
      let when;
      let houseId = null;
      let dynName = '';
      let names = null;
      let notes = [];
      let facts = [];
      let foot;
      if (el.dataset.cell) {
        const ref = el.dataset.cell;
        const c = (p.leaders || [])[Number(ref.split(':')[1])];
        if (!c) return null;
        head = c.name; // 머리는 이름 · 기간(목업 결정 6 A) — 묘호 · 시호 · 이름 · 지위는 그 아래 옅은 한 줄 (HT.leaderFull과 같은 말)
        facts = [c.temple && `묘호 ${c.temple}`, c.title && `시호 ${c.title}`, c.given && `이름 ${c.given}`, (c.rank || c.rankAuto) && `지위 ${c.rank || c.rankAuto}`].filter(Boolean);
        when = cellRange(c, 'end', null, p);
        houseId = c.houseId || null;
        dynName = c.dynasty || c.dynastyAuto || '';
        names = c.names;
        if (c.note) notes.push(c.note);
        notes = notes.concat(altTip(c, cellBaseOf(c, p, ref)).split('\n').map(v => v.trim()).filter(Boolean));
        foot = '누르면 그 칸';
      } else {
        const ds = this._dynOf(p).filter(d => d.dynasty && d.dynasty.uid === el.dataset.uid);
        if (!ds.length) return null;
        const r = el.getBoundingClientRect();
        const t = this.yearAtClientX ? this.yearAtClientX(r.left + r.width / 2) : null;
        const d = (t != null && ds.find(q => q.start <= t && t <= q.end)) || ds[0];
        const y = d.dynasty;
        head = y.name;
        when = `${HT.formatYear(d.start)} ~ ${HT.formatYear(d.end)}`;
        houseId = y.houseId || null;
        names = y.names;
        if (!houseId && y.house) notes.push(`본가 왕조 ${y.house}`);
        if (d.note) notes.push(d.note);
        const c = dynCellOf(d, d.dynasty); // 칸이 쓰는 것과 같은 이설(그 띠의 다스림 줄 + 왕조 자신)
        notes = notes.concat(altTip(c, { start: d.start, end: d.end }).split('\n').map(v => v.trim()).filter(Boolean));
        foot = '누르면 그 왕조';
      }
      const rows = [];
      const hm = houseId ? this._houseMapNow() : null;
      const h = hm && hm.get(houseId);
      if (h) {
        const path = (h.path && h.path.length ? h.path : [h.id]).map(id => hm.get(id)).filter(Boolean);
        const up = path.slice().reverse(); // 저부터 본가 쪽으로 — 성씨 · 본관은 처음 만나는 것 (파는 본가의 것을 물려받음)
        const sur = up.find(x => x.surname);
        const seat = up.find(x => x.seat);
        if (sur) rows.push(['성씨', sur.surnameId ? `<button type="button" class="ht-link" data-tip-surname="${esc(sur.surnameId)}">${esc(sur.surname)}</button>` : esc(sur.surname)]);
        if (seat) rows.push(['본관', esc(seat.seat)]);
        const chain = path.length > 3 ? [path[0], null, path[path.length - 2], path[path.length - 1]] : path; // 본가 길을 짧게 — 넷 이상이면 뿌리 › … › 위 › 저
        const text = chain.map(x => (x ? esc(x.name) : '…')).join(' <small>›</small> ');
        rows.push(['가문', `<button type="button" class="ht-link" data-tip-house="${esc(h.id)}"><i class="ht-dot" style="--hc:${esc(h.color)}"></i>${text}</button>`]);
      } else if (houseId && el.dataset.cell) {
        const c = (p.leaders || [])[Number(el.dataset.cell.split(':')[1])];
        if (c && c.houseName) rows.push(['가문', `<button type="button" class="ht-link" data-tip-house="${esc(houseId)}"><i class="ht-dot" style="--hc:${esc(c.houseColor || '')}"></i>${esc(c.houseName)}</button>`]);
      }
      if (dynName) rows.push(['왕조', esc(dynName)]);
      const main = HT.namesSplit ? HT.namesSplit(names).main : [];
      const native = main.length ? `<p class="ht-names">${main.map(n => `<bdi${n.lang ? ` lang="${esc(n.lang)}"` : ''}>${esc(n.text)}</bdi>`).join(' · ')}</p>` : '';
      const lit = rows.some(r => r[0] === '가문');
      const sub = facts.length ? `<p class="ht-sub">${esc(facts.join(' · '))}</p>` : '';
      return `<div class="ht-head"><b>${esc(head)}</b><span>${esc(when)}</span></div>${sub}${native}${rows.length ? `<dl>${rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('')}</dl>` : ''}${notes.length ? `<p class="ht-note">${notes.map(esc).join('<br>')}</p>` : ''}<p class="ht-foot">${foot}${lit ? ' · 가문을 누르면 가문 조명' : ''}</p>`;
    }

    /** 풍선을 띄움 — 칸 아래 8px(모자라면 칸 위), 가로는 칸 왼쪽에서 8px 앞 · 연표 안(상세 창이 가린 오른쪽은 빼고) */
    _showTip(anchor) {
      if (!anchor || !anchor.isConnected) return;
      const html = this._tipHTML(anchor);
      if (!html) return this.hideTip(true);
      const tip = this._tip;
      if (!tip.el) {
        const el = (tip.el = document.createElement('div'));
        el.className = 'tl-htip';
        el.hidden = true;
        el.setAttribute('role', 'tooltip');
        this.root.appendChild(el);
        el.addEventListener('pointerleave', () => {
          clearTimeout(tip.timer);
          tip.timer = setTimeout(() => this.hideTip(), 220);
        });
        el.addEventListener('pointerenter', () => clearTimeout(tip.timer));
        el.addEventListener('click', ev => {
          const hb = ev.target.closest('[data-tip-house]');
          const sb = ev.target.closest('[data-tip-surname]');
          if (!hb && !sb) return;
          this.hideTip(true);
          if (this.opts.onSelect) this.opts.onSelect(hb ? `house:${hb.dataset.tipHouse}` : `surname:${sb.dataset.tipSurname}`);
        });
      }
      const el = tip.el;
      el.getAnimations().forEach(a => a.cancel());
      el.classList.remove('is-leaving');
      if (el._html !== html) {
        el._html = html;
        el.innerHTML = html;
      }
      el.hidden = false;
      tip.key = this._tipKey(anchor);
      tip.at = `${this.view.start}|${this.view.end}|${this.bodyEl.scrollTop}`;
      const rr = this.root.getBoundingClientRect();
      const br = this.bodyEl.getBoundingClientRect();
      const ar = anchor.getBoundingClientRect();
      const w = el.offsetWidth;
      const h = el.offsetHeight;
      const lo = br.left - rr.left + this.gutter + 6;
      const hi = Math.max(lo, br.right - rr.left - (this._insetR || 0) - w - 10);
      const left = HT.clamp(ar.left - rr.left - 8, lo, hi);
      let top = ar.bottom - rr.top + 8;
      let below = true;
      if (top + h > br.bottom - rr.top - 8 && ar.top - rr.top - 8 - h >= br.top - rr.top + 4) {
        top = ar.top - rr.top - 8 - h;
        below = false;
      }
      el.style.left = `${left.toFixed(1)}px`;
      el.style.top = `${Math.max(br.top - rr.top + 4, top).toFixed(1)}px`;
      el.classList.toggle('is-above', !below);
    }

    /** 풍선을 걷음 (now면 그 자리에서 — 누름 · 옮김 · 다시 그리기) */
    hideTip(now = false) {
      const tip = this._tip;
      clearTimeout(tip.timer);
      tip.key = null;
      const el = tip.el;
      if (!el || el.hidden) return;
      if (!now && !reduceMotion()) {
        el.classList.add('is-leaving');
        const a = el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: HT.motion.T.out, easing: HT.motion.C.ease });
        a.onfinish = () => {
          if (el.classList.contains('is-leaving')) {
            el.hidden = true;
            el.classList.remove('is-leaving');
          }
        };
      } else {
        el.getAnimations().forEach(a => a.cancel());
        el.classList.remove('is-leaving');
        el.hidden = true;
      }
    }

    /* ---------- 가장자리 안내 ----------
       확대·이동·접기처럼 화면이 갑자기 넘어가서, 방금까지 보던 나라가 화면 위·아래로 밀려나면
       그쪽 가장자리에 작은 알약이 떠서 무엇이 밀려났는지 알려 줍니다. 이름을 누르면 그 나라로 스르르 넘어가 잠깐 반짝입니다 */
    /** 지금 화면(세로)에 보이는 것들 — 트랙 · 민족 묶음 · 줄의 대표 정권(국가). key → { kind, name, color, sub, trackId, … }.
        final(_finalGeom)을 주면 화면을 재는 대신, 줄 접힘이 다 흐른 뒤의 배치(모델)에서 보일 것들을 셉니다 */
    _visibleUnits(final = null) {
      const b = this.bodyEl;
      const top = final ? final.top : b.scrollTop;
      const bot = top + b.clientHeight;
      const out = new Map();
      const add = (key, u, y, h) => {
        const vis = Math.min(bot, y + h) - Math.max(top, y);
        if (vis > Math.min(24, h * 0.5)) out.set(key, u);
      };
      for (const tr of this.tracks) {
        if (!tr.el || !tr.el.isConnected) continue;
        const t0 = final ? final.tops.get(tr) : tr.el.offsetTop;
        add(`t:${tr.id}`, { kind: 'track', name: tr.name, color: tr.color, sub: '트랙', trackId: tr.id }, t0, tr.height || tr.el.offsetHeight);
        const groupWord = gp => (gp.scope ? '대범위' : '민족'); // 밀려남 알림의 칩 글 — 대범위 가지는 민족이 아니라 대범위
        if (tr.folded) continue;
        const rowY = r => t0 + (!final && tr.laneEls[r] ? tr.laneEls[r].offsetTop : tr.rowTop[r]);
        for (let r = 0; r < tr.rows; r++) {
          if (tr.hiddenRows.has(r) || tr.foldedRows.has(r) || r === tr.commonRow) continue;
          const p = tr._picks && tr._picks[r];
          if (!p) continue;
          add(`p:${p.uid}`, { kind: 'polity', uid: p.uid, name: p.name, color: p.color, sub: `${tr.name}${p.peopleName ? ` · ${p.peopleName}` : ''}`, trackId: tr.id, trackName: tr.name }, rowY(r), tr.rowHs[r] || 0);
        }
        for (const gp of tr.groups || []) {
          if (!gp.name) continue;
          let first = -1;
          let last = -1;
          for (let r = gp.first; r < gp.first + gp.count; r++) {
            if (tr.hiddenRows.has(r)) continue;
            if (first < 0) first = r;
            last = r;
          }
          if (first < 0) continue;
          const y0 = rowY(first);
          add(`g:${tr.id}|${gp.key}`, { kind: 'people', gkey: `${tr.id}|${gp.key}`, name: gp.name, color: gp.color, sub: `${tr.name} · ${groupWord(gp)}`, trackId: tr.id, trackName: tr.name }, y0, rowY(last) + (tr.rowHs[last] || 0) - y0);
        }
      }
      return out;
    }

    /** 그것이 지금 어디 있나 → { top, el, tr, row } (이 시기에 그릴 것이 없으면 null). final을 주면 다 흐른 뒤의 자리(모델) */
    _locate(u, final = null) {
      const tr = this.tracks.find(x => x.id === u.trackId);
      if (!tr || !tr.el || !tr.el.isConnected) return null;
      const t0 = final ? final.tops.get(tr) : tr.el.offsetTop;
      if (u.kind === 'track' || tr.folded) return { top: t0, el: tr.el, tr };
      const rowY = r => t0 + (!final && tr.laneEls[r] ? tr.laneEls[r].offsetTop : tr.rowTop[r]);
      if (u.kind === 'polity') {
        const r = (tr._picks || []).findIndex(p => p && p.uid === u.uid);
        if (r < 0 || tr.hiddenRows.has(r)) return null;
        return { top: rowY(r), el: tr.laneEls[r], tr, row: r };
      }
      const gp = (tr.groups || []).find(g => `${tr.id}|${g.key}` === u.gkey);
      if (!gp) return null;
      for (let r = gp.first; r < gp.first + gp.count; r++) if (!tr.hiddenRows.has(r)) return { top: rowY(r), el: tr.laneEls[r], tr, row: r };
      return null;
    }

    _beginJump() {
      if (this._jump || !this.tracks.length || !this.bodyEl.clientHeight) return;
      this._jump = { before: this._visibleUnits() };
    }

    _touchJump() {
      this._beginJump();
      this._settleSoon();
    }

    /** 정착을 예약합니다. 기다림은 "손이 또 올지"를 보는 시간입니다 — 끊어 끌거나 휠을 연달아 굴리는 사이에 줄이 접혔다 펴지며 숨 쉬지 않게:
        휠·미끄러짐이 멎은 뒤와 관성 없이 놓은 뒤는 0.3초(기본), 다시 배치한 뒤는 0(그 자리에서 곧바로). 멀리 가기의 도착은 예약 없이 도착 프레임에 바로 정착합니다(_animateTo).
        기다리는 동안 다시 누르면 예약을 거두고(pointerdown), 손을 뗄 때 다시 겁니다 — 휠은 굴릴 때마다 새로 겁니다 */
    _settleSoon(delay = 300) {
      clearTimeout(this._settleTimer);
      this._settleDue = true;
      this._settleTimer = HT.motion.later(delay, () => this._settle());
    }

    /** 정착 — 움직임이 멎은 뒤 딱 한 번: 미뤄 둔 줄 접힘을 시작하고(흐르게), 같은 순간에 밀려난 것을 알립니다. 접힘과 안내가 한 박자 — 한참 뒤의 두 번째 막이 없습니다.
        아직 움직이는 중이면 미루고 false를 돌려줍니다 */
    _settle() {
      if (this._inMotion()) {
        this._settleSoon(200);
        return false;
      }
      clearTimeout(this._settleTimer);
      this._settleDue = false;
      if (this._birdSettle()) return true; // 자동 조감이 켜지거나 꺼짐 — 다시 짓기(한 시계로 흐름 · 빈 줄 접힘도 지금 보기로)가 이 정착을 대신합니다
      const hold = this._holdNow(); // 접히는 동안 제자리에 붙잡힐 줄 — 접기 전의 화면에서
      if (this._raf) {
        cancelAnimationFrame(this._raf);
        this._raf = 0;
      }
      this._draw(); // 움직이는 동안 미뤄 둔 줄 접힘을 이제 한 번에 (기다리지 않고 지금 — 모델은 이 순간 접힌 뒤의 값이 됩니다)
      this._announce(hold);
      return true;
    }

    /** 밀려난 것 알리기: 이동 전에 보이던 것(_jump) 가운데 이제 화면 밖에 있는 것을 가장자리 안내로.
        접히기 전의 화면이 아니라 다 접힌 뒤의 배치로 가립니다 — 화면은 이제 막 흐르기 시작했으므로 재지 않고 모델로 셉니다(_finalGeom) */
    _announce(hold) {
      const j = this._jump;
      this._jump = null;
      if (!j) return;
      const final = this._finalGeom(hold);
      const now = this._visibleUnits(final);
      const bot = final.top + this.bodyEl.clientHeight;
      const lost = [];
      for (const [key, u] of j.before) {
        if (now.has(key)) continue;
        const at = this._locate(u, final);
        if (!at) continue; // 이 시기에 그릴 것이 없어 사라진 줄은 "밀려난" 게 아닙니다
        if (u.kind === 'track' && !at.tr.folded && at.tr.hiddenRows && at.tr.hiddenRows.size >= at.tr.rows) continue;
        lost.push(Object.assign({ key, at: at.top, row: at.row }, u));
      }
      if (!lost.length) return;
      /* 묶기: 트랙이 통째로 밀렸으면 트랙 하나로. 민족 묶음이 통째로 밀렸는데 그 안의 정권이 셋 이상이면 민족 하나로("한족 · 4"),
         둘 이하면 정권 이름을 그대로. 민족 안의 민족(대명제 → 민족)이 함께 밀렸으면 큰 쪽만 */
      const trackLost = new Set(lost.filter(u => u.kind === 'track').map(u => u.trackId));
      const groupOf = (u, g) => {
        const tr = this.tracks.find(x => x.id === u.trackId);
        const gp = tr && (tr.groups || []).find(x => `${tr.id}|${x.key}` === g.gkey);
        return gp && u.row != null && u.row >= gp.first && u.row < gp.first + gp.count;
      };
      const peoples = lost.filter(u => u.kind === 'people' && !trackLost.has(u.trackId));
      const polities = lost.filter(u => u.kind === 'polity' && !trackLost.has(u.trackId));
      const bigPeoples = peoples.filter(g => {
        const inside = polities.filter(u => u.trackId === g.trackId && groupOf(u, g));
        if (inside.length < 3) return false;
        // 더 큰 묶음(대명제)이 같이 밀렸으면 그쪽만
        return !peoples.some(h => h !== g && h.trackId === g.trackId && polities.filter(u => u.trackId === h.trackId && groupOf(u, h)).length >= 3 && inside.every(u => groupOf(u, h)) && polities.filter(u => u.trackId === h.trackId && groupOf(u, h)).length > inside.length);
      });
      for (const g of bigPeoples) g.count = polities.filter(u => u.trackId === g.trackId && groupOf(u, g)).length;
      const show = lost.filter(u => u.kind === 'track' || bigPeoples.includes(u) || (u.kind === 'polity' && !trackLost.has(u.trackId) && !bigPeoples.some(g => g.trackId === u.trackId && groupOf(u, g))));
      const down = show.filter(u => u.at >= bot - 24).sort((a, b) => a.at - b.at);
      const up = show.filter(u => u.at < bot - 24).sort((a, b) => b.at - a.at);
      if (down.length || up.length) this._showEdgeHint(down, up);
    }

    _showEdgeHint(down, up) {
      if (!this.hintEl) {
        const el = (this.hintEl = document.createElement('div'));
        el.className = 'tl-hints';
        el.hidden = true;
        this.root.appendChild(el);
        el.addEventListener('click', ev => {
          const b = ev.target.closest('[data-hint-go]');
          if (ev.target.closest('[data-hint-close]')) return this._hideEdgeHint();
          if (b) this._goUnit(b.dataset.hintGo);
        });
        el.addEventListener('pointerenter', () => clearTimeout(this._hintTimer));
        el.addEventListener('pointerleave', () => this._armHint(3200));
      }
      this._hintUnits = new Map(down.concat(up).map(u => [u.key, u]));
      /* 알약 하나: 정권(국가)은 이름 + 작은 나라 이름, 민족은 이름 + "민족", 트랙은 이름 + "트랙" */
      const chip = u =>
        `<button type="button" class="th-chip is-${u.kind}" data-hint-go="${esc(u.key)}" style="--c:${u.color}" title="${esc(`${u.name} · ${u.sub}${u.count ? ` · 정권 ${u.count}개` : ''} — 여기로 가기`)}"><i></i>${esc(u.name)}<small>${esc(u.kind === 'polity' ? u.trackName : u.kind === 'people' ? `민족 · ${u.count}` : '트랙')}</small></button>`;
      const pill = (list, dir) => {
        if (!list.length) return '';
        const shown = list.slice(0, 4);
        return `<div class="tl-hint is-${dir}" role="status"><button type="button" class="th-go" data-hint-go="${esc(shown[0].key)}" title="${dir === 'down' ? '아래' : '위'}로 가기">${dir === 'down' ? '↓' : '↑'}</button><span class="th-lead">${dir === 'down' ? '아래로 밀려남' : '위로 밀려남'}</span>${shown.map(chip).join('')}${
          list.length > shown.length ? `<span class="th-more">외 ${list.length - shown.length}</span>` : ''
        }<button type="button" class="th-x" data-hint-close aria-label="닫기">✕</button></div>`;
      };
      const el = this.hintEl;
      el.style.setProperty('--axisH', `${this.axisEl.offsetHeight}px`);
      el.style.setProperty('--gutter', `${this.gutter}px`);
      /* 조용히 한 번(css .tl-hint — is-in이 붙으면 떠오르며 짙어짐): 내용이 그대로면 다시 쓰지도 다시 등장하지도 않고, 내용이 바뀌어도 이미 떠 있던 쪽(위·아래)은 제자리에서 내용만 바뀝니다.
         물러나던 중에 다시 불리면 늦게 온 숨김이 새 안내를 지우지 않게 그 시한부터 거두고, 지금 밝기에서 되돌아옵니다 */
      clearTimeout(this._hintOut);
      const html = pill(up, 'up') + pill(down, 'down');
      const wasHidden = el.hidden;
      el.hidden = false;
      if (el._html !== html) {
        const had = new Set(wasHidden ? [] : [...el.querySelectorAll('.tl-hint.is-in')].map(p => (p.classList.contains('is-up') ? 'up' : 'down')));
        el.innerHTML = el._html = html;
        for (const p of el.querySelectorAll('.tl-hint')) if (had.has(p.classList.contains('is-up') ? 'up' : 'down')) p.classList.add('is-in');
      }
      void el.offsetWidth; // 새로 생긴 알약의 처음 모습(옅고 5px 비켜난)을 한 번 그린 뒤에
      for (const p of el.querySelectorAll('.tl-hint')) p.classList.add('is-in');
      this._hintAt = performance.now();
      this._armHint(6000);
    }

    _armHint(ms) {
      clearTimeout(this._hintTimer);
      this._hintTimer = HT.motion.later(ms, () => this._hideEdgeHint());
    }

    /** 안내가 물러납니다: 지금 밝기에서 옅어지고(css --t-out), 다 옅어지면 치웁니다. 치우는 시한(_hintOut)은 하나만 — 그 사이 다시 불리면 거둡니다(_showEdgeHint) */
    _hideEdgeHint() {
      const el = this.hintEl;
      if (!el || el.hidden) return;
      clearTimeout(this._hintTimer);
      clearTimeout(this._hintOut);
      for (const p of el.querySelectorAll('.tl-hint')) p.classList.remove('is-in');
      this._hintOut = HT.motion.later(HT.motion.T.out + 20, () => (el.hidden = true));
    }

    /** 그 줄(정권·민족·트랙)로 넘어가고, 도착하면 고리로 한 번 알립니다 */
    _goUnit(key) {
      const u = this._hintUnits && this._hintUnits.get(key);
      this._hideEdgeHint();
      const at = u && this._locate(u);
      if (!at) return;
      /* 세로로만 가는 길: 브라우저의 자동 스크롤 대신 닻과 같은 스프링 하나로 데려오고(_bringRow), 도착 표시는 도착한 뒤에 */
      this._bringRow(at.tr, at.row != null ? at.row : -1, at.row != null ? this._G().tab + 8 : 8, () => this._ringAt(at.el));
    }

    /** 도착 표시 — 고리가 한 번 옅어집니다(css .is-arrived · --t-ring 600ms). target = 항목 uid(그 띠나 점) 또는 요소(줄 · 트랙).
        요소의 그림자는 건드리지 않고(::after), 다시 불리면 앞선 고리를 걷고 새로 시작합니다 — 걷는 시한은 하나뿐이라 서로 엇갈리지 않습니다 */
    _ringAt(target) {
      const again = !!this._ring;
      this._ringOff();
      const els = typeof target === 'string' ? [...this.root.querySelectorAll(`.tl-band[data-uid="${CSS.escape(target)}"], .tl-ev[data-uid="${CSS.escape(target)}"], .tl-fig[data-uid="${CSS.escape(target)}"]`)] : target && target.isConnected ? [target] : [];
      if (!els.length) return;
      if (again) void this.root.offsetWidth; // 같은 요소에 다시 걸 때도 처음부터
      els.forEach(el => el.classList.add('is-arrived'));
      const ms = parseFloat(getComputedStyle(this.root).getPropertyValue('--t-ring')) || 600;
      this._ring = HT.motion.later(ms + 80, () => this._ringOff());
    }

    _ringOff() {
      if (!this._ring) return;
      clearTimeout(this._ring);
      this._ring = null;
      this.root.querySelectorAll('.is-arrived').forEach(el => el.classList.remove('is-arrived'));
    }

    /** 라벨과 띠를 서로 비추는 호버 — 같은 정권(같은 uid)만 */
    _hover(target) {
      if (target && this._inMotion()) {
        /* 움직이는 동안은 고요: 손 밑을 지나가는 띠마다 비추지 않습니다 — 멎은 뒤에도 그 위에 있으면 그때 (_motionEnd) */
        this._hoverMissed = target;
        target = null;
      }
      if (this.themeLens || this._echoFam) {
        const lc = target && target.closest ? target.closest('.tl-cell.k-lens[data-fam]') : null; // 렌즈 칸의 같은 갈래 메아리 (갈래가 있는 칸만)
        this._lensEcho(lc ? lc.dataset.fam : null);
      }
      const ct = target && target.closest ? target.closest('.tl-htab.k-coal[data-coal]') : null; // 연합의 겹 탭에 올리면 구성 나라 모두 진하게 (트랙이 달라도 — _coalHover)
      this._coalHover(ct ? ct.dataset.coal : null);
      const pc = target && target.closest ? target.closest('.tl-band .tl-cell:is(.k-leader, .k-cabinet)[data-cell]') : null; // 같은 사람의 칸 모두에 테 (건의 8의 6-나 — _sameHover)
      const pb = pc && pc.closest('.tl-band');
      this._sameHover(pb && pb.dataset.uid ? [pb.dataset.uid, pc.dataset.cell] : null);
      const host = target && target.closest ? target.closest('[data-row]') : null;
      const uid = host && host.dataset.uid;
      const key = host ? `${host.closest('.tl-track').dataset.track}|${uid || host.dataset.row}` : null;
      if (key === this._hotKey) return;
      this._hotKey = key;
      this.root.querySelectorAll('.is-hot').forEach(el => el.classList.remove('is-hot'));
      if (!host || !uid) return;
      const track = host.closest('.tl-track');
      track.querySelectorAll(`[data-uid="${CSS.escape(uid)}"]`).forEach(el => el.classList.add('is-hot'));
      // 그 정권에 닿는 승계선만 진하게 (문도 — 부정된 나라에 닿는 선의 문은 선과 함께 옅다가 올리면 함께 평소대로)
      track.querySelectorAll(`:is(.tl-link, .tl-door)[data-from="${CSS.escape(uid)}"], :is(.tl-link, .tl-door)[data-to="${CSS.escape(uid)}"]`).forEach(el => el.classList.add('is-hot'));
    }

    /** 연합의 겹 탭에 올렸을 때(설계 7-8 결정 3 C — 감독 선택 2026-10-12): 그 연합의 구성 나라 띠만 또렷 · 각자의 가담 기간 조명(띠 안에 미리 그려 둔 .tl-coal-lit을 켬) ·
        나머지 줄과 이름 칸은 옅게 · 같은 연합의 겹 탭 모두 진하게 — 트랙이 달라도(연표 전체). uid = 연합 단체(null이면 풂). 그리는 동안에도 _coalHot을 보고 같은 표시를 붙임 */
    _coalHover(uid) {
      uid = uid || null;
      if (uid === (this._coalHot || null)) return;
      this._coalHot = uid;
      this.root.classList.toggle('coal-hot', !!uid);
      this.root.querySelectorAll('.is-coal-on').forEach(el => el.classList.remove('is-coal-on'));
      if (!uid) return;
      const q = CSS.escape(uid);
      for (const lit of this.root.querySelectorAll(`.tl-coal-lit[data-coal="${q}"]`)) {
        lit.classList.add('is-coal-on');
        const band = lit.closest('.tl-band');
        if (!band) continue;
        band.classList.add('is-coal-on');
        const lane = band.closest('.tl-lane');
        if (lane) lane.classList.add('is-coal-on');
        const track = band.closest('.tl-track');
        const row = track && track.querySelector(`.tl-row[data-uid="${CSS.escape(band.dataset.uid)}"]`);
        if (row) row.classList.add('is-coal-on');
      }
      this.root.querySelectorAll(`.tl-htab.k-coal[data-coal="${q}"]`).forEach(el => el.classList.add('is-coal-on'));
    }

    /** (공개) 단체 계보 창(js/group-tree.js)이 막대를 누를 때: 집권 단 · 실권 단에서 그 단체의 칸만 진하게(안쪽 1.5px 진한 테두리 — 조명과 같은 말) · 나머지 단체 칸은 옅게(.4). null이면 풂 */
    setGroupFocus(uid) {
      uid = uid || null;
      if (uid === (this._groupFocus || null)) return;
      this._groupFocus = uid;
      this.root.classList.toggle('group-focus', !!uid);
      this.root.querySelectorAll('.tl-cell.k-group.is-gf').forEach(el => el.classList.remove('is-gf'));
      if (uid) this.root.querySelectorAll('.tl-cell.k-group[data-groups]').forEach(el => el.classList.toggle('is-gf', el.dataset.groups.split(' ').includes(uid)));
    }

    /** 도읍 칸에 올리면 같은 도시를 도읍으로 쓴 칸만 진하게 (평양 = 고구려 평양성 · 고려 서경) */
    _axisHover(e) {
      const cell = e && e.target && e.target.closest ? e.target.closest('.tl-ccell[data-city]') : null;
      const city = cell ? cell.dataset.city : null;
      if (city === (this._hotCity || null)) return;
      this._hotCity = city;
      this._markCity(city);
    }

    _markCity(city) {
      this.axisEl.querySelectorAll('.tl-ccell.is-city').forEach(el => el.classList.remove('is-city'));
      const hits = city ? this.axisEl.querySelectorAll(`.tl-ccell[data-city="${CSS.escape(city)}"]`) : [];
      hits.forEach(el => el.classList.add('is-city'));
      // 다른 칸을 흐리는 건 같은 도시가 둘 이상 보일 때만
      this.axisEl.classList.toggle('has-city', hits.length > 1);
    }

    /** 도읍 칸의 설명: 그때 이름(도시) · 기간 · 역할 · 같은 도시를 쓴 다른 나라 */
    _capTip(p, c) {
      const nm = c.as && c.as !== c.city ? `${c.as} (${c.city})` : c.city;
      const role = c.role && c.role !== 'main' ? ` · ${HT.capitalRoleName(c.role)}` : '';
      const others = (this._cityUses.get(c.city) || []).filter(u => u.p !== p).map(u => `${u.p.name} ${u.c.name} ${u.c.startUnknown ? '미정' : HT.formatWhen(u.c, 'start')}~`);
      const lines = [`${p.name} 도읍 · ${nm}${c.label ? ` · ${c.label}` : ''}${role}`, `${cellRange(c, 'endY', null, p)}${c.note ? ` · ${c.note}` : ''}`];
      if (others.length) lines.push(`같은 도시: ${others.slice(0, 4).join(' · ')}${others.length > 4 ? ` 외 ${others.length - 4}` : ''}`);
      return lines.join('\n');
    }

    /* ---------- 도읍 노선도 카드 ----------
       왼쪽 줄 이름에 잠깐 머물면(키보드는 Enter) 그 정권의 도읍 내력을 지하철 노선도처럼 보여 줍니다.
       본선 = 정도, 위로 갈라지는 지선 = 배도, 아래 점선 우회 = 임시 도읍, 겹고리 = 다른 나라와 같은 도시(환승역).
       시간 길이가 아니라 순서만 나타냅니다. 역을 누르면 그 시기로, 📌로 고정, Esc로 닫기 */
    _metroHTML(p) {
      const caps = (p.capitals || []).slice().sort((a, b) => a.start - b.start || a.endY - b.endY);
      const others = city => (city ? (this._cityUses.get(city) || []).filter(u => u.p !== p) : []);
      /* 본선의 역: 같은 도시로 돌아오면(개경 → 강화 → 개경) 한 역에 합칩니다 */
      const nodes = [];
      for (const c of caps) {
        if (c.role === 'secondary') continue;
        const prev = nodes[nodes.length - 1];
        if (c.role === 'temporary') {
          nodes.push({ type: 'detour', c, periods: [c], names: [c.name] });
          continue;
        }
        const back = prev && prev.type === 'detour' ? nodes[nodes.length - 2] : prev;
        if (back && back.type === 'station' && back.c.city === c.city) {
          back.periods.push(c);
          if (!back.names.includes(c.name)) back.names.push(c.name);
          continue;
        }
        nodes.push({ type: 'station', c, periods: [c], names: [c.name] });
      }
      /* 배도 지선: 같은 도시·같은 묶음은 하나로 */
      const branches = [];
      const byKey = new Map();
      for (const c of caps.filter(c => c.role === 'secondary')) {
        const key = c.group || c.city;
        const b = byKey.get(key);
        if (b) {
          if (c.start < b.start) b.startUnknown = !!c.startUnknown; // 칸의 미정: 지선의 첫 시작이 미정인 도시의 것인지 (이름표 · 단추의 설명이 함께 봄)
          if (c.endY > b.endY) b.endUnknown = !!c.endUnknown; // 지선의 마지막 끝이 미정인 도시의 것인지 (단추의 설명 — cellRange)
          b.start = Math.min(b.start, c.start);
          b.endY = Math.max(b.endY, c.endY);
          continue;
        }
        const nb = { name: c.group || c.name, city: c.group ? '' : c.city, start: c.start, endY: c.endY, startUnknown: !!c.startUnknown, endUnknown: !!c.endUnknown };
        byKey.set(key, nb);
        branches.push(nb);
      }
      const shown = branches.slice(0, 4);
      const seatCities = new Set(caps.filter(c => c.role !== 'secondary').map(c => c.city));
      const secCities = new Set(caps.filter(c => c.role === 'secondary' && !seatCities.has(c.city)).map(c => c.city));
      let moves = 0;
      caps.filter(c => c.role !== 'secondary').forEach((c, i, arr) => i && arr[i - 1].city !== c.city && moves++);

      /* 이름표 (크기를 먼저 재서 역 사이를 넉넉히) */
      const chip = ex => (ex.length ? { uid: ex[0].p.uid, color: ex[0].p.color, text: `⇄ ${ex[0].p.name}${ex.length > 1 ? ` 외 ${ex.length - 1}` : ''}`, tip: `같은 도시 · ${ex.map(u => `${u.p.name} ${u.c.name} ${u.c.startUnknown ? '미정' : bcYear(u.c.start)}–`).join(' · ')}` } : null);
      const chipW = ch => (ch ? textWidth(ch.text, 9.5, 600) + 14 : 0);
      const label = (n, sub) => {
        const ch = chip(others(n.c.city));
        const name = n.names.join('·') + (n.c.label && !n.names.includes(n.c.label) ? ` (${n.c.label})` : '');
        return { name, sub, ch, w: Math.max(textWidth(name, 12, 700), textWidth(sub, 10)) + (ch ? chipW(ch) + 4 : 0) + 2 };
      };
      const sY = c => (c.startUnknown ? '미정' : bcYear(c.start)); // 칸의 미정: 역 이름 아래의 해도 "미정"
      nodes.forEach(n => {
        const years = n.periods.map(sY).join(' · ');
        const tag = n.type === 'detour' ? `${sY(n.c)}–${n.c.endUnknown || n.c.endYAuto ? '미정' : bcYear(n.c.endY)} · 임시` : `${years}${n.c.role === 'exile' ? ' · 망명' : n.c.role === 'co' ? ' · 공동' : ''}`;
        n.lab = label(n, tag);
      });
      const L = 28; // 우회선 반폭
      const MIN = 60;
      const xs = [];
      let x = 28;
      let lowRight = -Infinity; // 아래 줄(임시 도읍 이름표)의 오른쪽 끝
      nodes.forEach((n, i) => {
        const prev = nodes[i - 1];
        if (i === 0) x = n.type === 'detour' ? Math.max(28 + L, n.lab.w / 2 + 10) : 28;
        else if (prev.type === 'station') x += Math.max(MIN, prev.lab.w + (n.type === 'detour' ? L + 4 : 14));
        else x += Math.max(MIN, L + 16, n.type === 'detour' ? 2 * L + 16 : 0);
        if (n.type === 'detour') {
          x = Math.max(x, lowRight + 14 + n.lab.w / 2);
          lowRight = x + n.lab.w / 2;
        }
        xs.push(x);
      });
      const last = nodes[nodes.length - 1];
      const endLab = { name: p.ongoing ? '지금' : '끝', sub: p.ongoing ? '' : bcYear(p.endY) };
      const endW = Math.max(textWidth(endLab.name, 12, 700), textWidth(endLab.sub, 10)) + 4;
      const xEnd = !last ? 28 + MIN : x + Math.max(MIN - 8, last.type === 'station' ? last.lab.w + 14 : L + 16);
      /* 지선은 그 해에 있던 본선 역에서 위로. 왼쪽 지선일수록 높이 올려 이름표와 세로선이 엇갈리지 않게 */
      const anchorOf = y => {
        let k = nodes.findIndex(n => n.type === 'station' && n.periods.some(c => c.start <= y && y < c.endY));
        if (k < 0) nodes.forEach((n, i) => n.type === 'station' && n.c.start <= y && (k = i));
        if (k < 0) k = Math.max(0, nodes.findIndex(n => n.type === 'station'));
        return nodes.length ? xs[k] : 28;
      };
      const perAnchor = new Map();
      const brs = shown
        .map(b => {
          const ax = anchorOf(b.start);
          const j = perAnchor.get(ax) || 0;
          perAnchor.set(ax, j + 1);
          const ch = chip(others(b.city));
          const text = `${b.startUnknown ? '미정' : bcYear(b.start)}–`;
          return { b, ox: ax + 13 + j * 11, ch, text, w: textWidth(b.name, 11.5, 700) + 4 + textWidth(text, 10) + (ch ? chipW(ch) + 6 : 0) + 4 };
        })
        .sort((u, v) => u.ox - v.ox);
      const levels = brs.length;
      const mainY = levels ? 45 + (levels - 1) * 26 : 20;
      brs.forEach((br, i) => (br.y = mainY - 28 - (levels - 1 - i) * 26));
      const hasDetour = nodes.some(n => n.type === 'detour');
      const mapH = mainY + (hasDetour ? 76 : 46);
      const mapW = Math.ceil(Math.max(xEnd - 8 + endW + 10, lowRight + 10, ...brs.map(br => br.ox + 30 + br.w + 8), 260));

      const svg = [];
      const html = [];
      const mainFrom = nodes.length ? (nodes[0].type === 'detour' ? xs[0] - L : xs[0]) : 28;
      svg.push(`<line class="m-main" x1="${cx(mainFrom)}" y1="${mainY}" x2="${cx(xEnd)}" y2="${mainY}"></line>`);
      /* 칸의 미정: 두 역 사이의 경계(뒤 역의 시작이나 앞 역의 끝)가 미정이면 그 사이 본선이 점선 — 역 동그라미 · 우회선 자리는 피해서 */
      const unkBefore = n => n.type === 'station' && !!n.periods[0].startUnknown;
      const unkAfter = n => n.type === 'station' && !!(n.periods[n.periods.length - 1].endUnknown || n.periods[n.periods.length - 1].endYAuto);
      const dashSeg = (a, b) => {
        if (b - a >= 8) svg.push(`<line class="m-gap" x1="${cx(a)}" y1="${mainY}" x2="${cx(b)}" y2="${mainY}"></line><line class="m-unk" x1="${cx(a)}" y1="${mainY}" x2="${cx(b)}" y2="${mainY}"></line>`);
      };
      const offR = i => xs[i] + (nodes[i].type === 'detour' ? L : 12);
      nodes.forEach((n, i) => {
        if (i && (unkBefore(n) || unkAfter(nodes[i - 1]))) dashSeg(offR(i - 1), xs[i] - (n.type === 'detour' ? L : 12));
      });
      if (last && unkAfter(last)) dashSeg(offR(nodes.length - 1), xEnd - 7);
      const xferRing = (ex, x0, y0, r) => (ex.length ? `<circle class="m-xfer" cx="${cx(x0)}" cy="${cx(y0)}" r="${r}" style="--oc:${ex[0].p.color}"></circle>` : '');
      const chipHTML = ch => (ch ? `<button type="button" class="m-x" data-metro-uid="${esc(ch.uid)}" style="--oc:${ch.color}" title="${esc(`${ch.tip} — 누르면 그 나라 노선도`)}">${esc(ch.text)}</button>` : '');
      const go = (a, b, inner, tip) => `<button type="button" class="m-go" data-metro-year="${a}" data-metro-end="${b}" title="${esc(tip)}">${inner}</button>`;
      // 가장 오래 머문 역은 조금 크게
      const stay = n => n.periods.reduce((sum, c) => sum + (c.endY - c.start), 0);
      const longest = nodes.filter(n => n.type === 'station').reduce((best, n) => (!best || stay(n) > stay(best) ? n : best), null);
      nodes.forEach((n, i) => {
        const x0 = xs[i];
        const ex = others(n.c.city);
        const a = n.periods[0].start;
        const b = n.periods[n.periods.length - 1].endY;
        const tip = `${n.periods.map(c => `${c.name} ${cellRange(c, 'endY', null, p)}${c.note ? ` · ${c.note}` : ''}${cellAltTip(c)}`).join('\n')}\n누르면 이 시기로`;
        const inner = `<b>${esc(n.lab.name)}</b><small>${esc(n.lab.sub)}</small>`;
        if (n.type === 'detour') {
          const l = x0 - L;
          const r = x0 + L;
          svg.push(`<line class="m-vacant" x1="${cx(l + 6)}" y1="${mainY}" x2="${cx(r - 6)}" y2="${mainY}"></line>`);
          svg.push(`<path class="m-detour" d="M${cx(l)} ${mainY} C ${cx(l + 5)} ${mainY + 40}, ${cx(r - 5)} ${mainY + 40}, ${cx(r)} ${mainY}"></path>`);
          svg.push(xferRing(ex, x0, mainY + 30, 10));
          svg.push(`<circle class="m-stop is-temp" cx="${cx(x0)}" cy="${mainY + 30}" r="6"></circle>`);
          html.push(`<span class="m-lab is-temp" style="left:${cx(x0 - n.lab.w / 2)}px;top:${mainY + 44}px">${go(a, b, inner, tip)}${chipHTML(n.lab.ch)}</span>`);
          return;
        }
        svg.push(xferRing(ex, x0, mainY, 11));
        svg.push(`<circle class="m-stop${n === longest ? ' is-main' : ''}" cx="${cx(x0)}" cy="${mainY}" r="${n === longest ? 7.5 : 6}"></circle>`);
        html.push(`<span class="m-lab" style="left:${cx(x0 - 8)}px;top:${mainY + 14}px">${go(a, b, inner, tip)}${chipHTML(n.lab.ch)}</span>`);
      });
      svg.push(`<circle class="m-end" cx="${cx(xEnd)}" cy="${mainY}" r="4.5"></circle>`);
      html.push(`<span class="m-lab is-end" style="left:${cx(xEnd - 8)}px;top:${mainY + 14}px"><b>${endLab.name}</b><small>${esc(endLab.sub)}</small></span>`);
      brs.forEach(br => {
        const { b, ox, y } = br;
        const ex = others(b.city);
        svg.push(`<path class="m-branch" d="M${cx(ox)} ${mainY - 3} L ${cx(ox)} ${cx(y + 9)} Q ${cx(ox)} ${cx(y)} ${cx(ox + 9)} ${cx(y)} L ${cx(ox + 12)} ${cx(y)}"></path>`);
        svg.push(xferRing(ex, ox + 16, y, 8.5));
        svg.push(`<circle class="m-stop is-sec" cx="${cx(ox + 16)}" cy="${cx(y)}" r="4.5"></circle>`);
        const tip = `${b.name} 배도 · ${cellRange(b, 'endY', null, p)}${cellAltTip(b)}\n누르면 이 시기로`;
        html.push(`<span class="m-lab is-sec" style="left:${cx(ox + 30)}px;top:${cx(y - 9)}px">${go(b.start, b.endY, `<b>${esc(b.name)}</b><small>${esc(br.text)}</small>`, tip)}${chipHTML(br.ch)}</span>`);
      });

      const legend = [`<span><i class="lg-main"></i>정도</span>`];
      if (brs.length) legend.push(`<span><i class="lg-branch"></i>배도(지선)</span>`);
      if (hasDetour) legend.push(`<span><i class="lg-detour"></i>임시(우회)</span>`);
      if (caps.some(c => others(c.city).length)) legend.push(`<span><i class="lg-xfer"></i>같은 도시(환승)</span>`);
      if (branches.length > shown.length) legend.push(`<span class="m-more">배도 외 ${branches.length - shown.length}곳</span>`);
      const tr = this.tracks.find(t => t.id === p.track);
      const peers = tr ? tr.periods.filter(q => q.capitals && q.capitals.length) : [];
      const pin = this.metro.pinned;
      return `
        <div class="m-head"><i class="m-dot"></i><b>${esc(p.name)}</b><span class="m-sum">도읍 ${seatCities.size}곳${secCities.size ? ` · 배도 ${secCities.size}곳` : ''} · 천도 ${moves}번 · ${esc(HT.formatRange(p))}</span>
          <button type="button" class="m-btn" data-metro-pin aria-pressed="${pin}" title="${pin ? '고정 풀기' : '카드 고정'}">📌</button><button type="button" class="m-btn" data-metro-close aria-label="닫기" title="닫기 (Esc)">✕</button></div>
        <div class="m-body"><div class="m-map" style="width:${mapW}px;height:${mapH}px"><svg class="m-svg" width="${mapW}" height="${mapH}" viewBox="0 0 ${mapW} ${mapH}" aria-hidden="true">${svg.join('')}</svg>${html.join('')}</div></div>
        <div class="m-legend">${legend.join('')}</div>
        <div class="m-foot">${peers.length > 1 ? peers.map(q => `<button type="button" class="m-peer${q === p ? ' is-on' : ''}" data-metro-uid="${esc(q.uid)}" style="--pc:${q.color}"${q === p ? ' aria-current="true"' : ''}>${esc(q.name)}</button>`).join('') : ''}<span class="m-hint">역을 누르면 그 시기로${peers.length > 1 ? ' · ← → 다른 정권' : ''}</span></div>`;
    }

    /** 도읍 노선도 카드를 엽니다. anchor = 기준 요소(왼쪽 줄 이름, 없으면 제자리), pin = 고정 여부(생략하면 그대로).
        keepTimer = 걸려 있던 열기·닫기 예약을 그대로 둠 (자료가 바뀌어 다시 그릴 때) */
    showMetro(uid, anchor, pin, keepTimer = false) {
      const el = this.metroEl;
      const p = el && this._data && this._data.periods.find(q => q.uid === uid);
      if (!p || !(p.capitals && p.capitals.length)) return false;
      const M = this.metro;
      if (!keepTimer) clearTimeout(M.timer);
      openMetros.add(this);
      if (pin != null) M.pinned = !!pin;
      const was = !el.hidden;
      const keep = was ? { left: el.offsetLeft, top: el.offsetTop } : null;
      M.uid = uid;
      if (anchor) M.anchor = anchor;
      el.style.setProperty('--c', p.color);
      el.innerHTML = this._metroHTML(p);
      el.classList.toggle('is-pinned', M.pinned);
      const rr = this.root.getBoundingClientRect();
      el.style.maxWidth = `${Math.max(260, Math.round(rr.width - 16))}px`;
      el.hidden = false;
      const w = el.offsetWidth;
      const h = el.offsetHeight;
      const a = anchor && anchor.isConnected ? anchor.getBoundingClientRect() : null;
      let left;
      let top;
      if (a) {
        left = a.right - rr.left + 12;
        top = a.top - rr.top + a.height / 2 - 34;
      } else if (keep) ({ left, top } = keep);
      else {
        left = this.gutter + 16;
        top = this.axisEl.offsetHeight + 12;
      }
      left = Math.max(8, Math.min(left, rr.width - w - 8));
      top = Math.max(8, Math.min(top, rr.height - h - 8));
      el.style.left = `${Math.round(left)}px`;
      el.style.top = `${Math.round(top)}px`;
      // 줄 이름을 가리키는 꼭지 (카드가 줄 이름 오른쪽에 있을 때만)
      const tipOn = !!a && left >= a.right - rr.left + 4;
      el.classList.toggle('has-tip', tipOn);
      if (tipOn) el.style.setProperty('--ay', `${Math.round(HT.clamp(a.top - rr.top + a.height / 2 - top, 18, h - 18))}px`);
      return true;
    }

    hideMetro() {
      const M = this.metro;
      clearTimeout(M.timer);
      M.uid = null;
      M.pinned = false;
      M.anchor = null;
      if (this.metroEl) this.metroEl.hidden = true;
      openMetros.delete(this);
    }

    _bindMetro() {
      const el = document.createElement('div');
      el.className = 'tl-metro';
      el.hidden = true;
      el.setAttribute('role', 'dialog');
      el.setAttribute('aria-label', '도읍 노선도');
      this.root.appendChild(el);
      this.metroEl = el;
      const M = this.metro;
      const later = (fn, ms) => {
        clearTimeout(M.timer);
        M.timer = setTimeout(fn, ms);
      };
      const rowOf = t => (t && t.closest ? t.closest('.tl-row.has-cap[data-uid]') : null);
      /* 동군연합 이음줄: 조각(트랙마다 띠 뒤 · 띠 위)에 올리면 같은 짝의 조각이 모두 짙어짐 */
      const unionOf = t => (t && t.closest ? t.closest('[data-union]') : null);
      this.tracksEl.addEventListener('pointerover', e => {
        const u = unionOf(e.target);
        if (u) for (const el of this.tracksEl.querySelectorAll(`[data-union="${CSS.escape(u.dataset.union)}"]`)) el.classList.add('is-over');
      });
      this.tracksEl.addEventListener('pointerout', e => {
        const u = unionOf(e.target);
        if (u) for (const el of this.tracksEl.querySelectorAll(`[data-union="${CSS.escape(u.dataset.union)}"]`)) el.classList.remove('is-over');
      });
      this.tracksEl.addEventListener('pointerover', e => {
        if (e.pointerType === 'touch' || e.buttons) return;
        const row = rowOf(e.target);
        if (!row || M.pinned) return;
        if (!el.hidden && M.uid === row.dataset.uid) return clearTimeout(M.timer);
        later(() => this.showMetro(row.dataset.uid, row), el.hidden ? 450 : 180);
      });
      this.tracksEl.addEventListener('pointerout', e => {
        const row = rowOf(e.target);
        if (!row || M.pinned || row.contains(e.relatedTarget) || el.contains(e.relatedTarget)) return;
        later(() => this.hideMetro(), el.hidden ? 0 : 260);
      });
      this.tracksEl.addEventListener('keydown', e => {
        const row = rowOf(e.target);
        if (!row || e.key !== 'Enter') return;
        e.preventDefault();
        this.showMetro(row.dataset.uid, row, true);
        const first = el.querySelector('.m-go');
        if (first) first.focus({ preventScroll: true });
      });
      el.addEventListener('pointerenter', () => clearTimeout(M.timer));
      el.addEventListener('pointerleave', e => {
        if (M.pinned || e.pointerType === 'touch') return;
        const row = rowOf(e.relatedTarget);
        if (row && row.dataset.uid === M.uid) return;
        later(() => this.hideMetro(), 260);
      });
      el.addEventListener('click', e => {
        if (e.target.closest('[data-metro-close]')) return this.hideMetro();
        if (e.target.closest('[data-metro-pin]')) return this.showMetro(M.uid, null, !M.pinned);
        const peer = e.target.closest('[data-metro-uid]');
        if (peer) return this.showMetro(peer.dataset.metroUid, null, true);
        const st = e.target.closest('[data-metro-year]');
        if (st) {
          const a = Number(st.dataset.metroYear);
          const b = Math.max(Number(st.dataset.metroEnd), a + 1);
          const pad = Math.max(6, (b - a) * 0.2);
          this.setView(a - pad, b + pad, { animate: true });
        }
      });
      el.addEventListener('keydown', e => {
        if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
        const peers = [...el.querySelectorAll('.m-peer')];
        const at = peers.findIndex(b => b.classList.contains('is-on'));
        if (peers.length < 2 || at < 0) return;
        e.preventDefault();
        e.stopPropagation();
        const next = peers[(at + (e.key === 'ArrowRight' ? 1 : peers.length - 1)) % peers.length];
        this.showMetro(next.dataset.metroUid, null, true);
        const on = el.querySelector('.m-peer.is-on');
        if (on) on.focus({ preventScroll: true });
      });
    }

    _applyStates() {
      const sel = this.selected;
      const hi = this.highlight;
      const echo = this.echo; // 같은 시기 타국의 사건 — 점 하나하나('uid:자리')
      if (!sel && !hi && !this._hadStates) return; // 고른 것도 강조도 없으면 훑을 필요 없음 (메아리는 강조가 있을 때만)
      this._hadStates = !!(sel || hi);
      this.root.classList.toggle('is-picked', !!sel);
      this.root.classList.toggle('is-filtered', !!hi);
      this.root.querySelectorAll('.is-onrow').forEach(el => el.classList.remove('is-onrow'));
      const dimmed = []; // 메아리였다가 흐려지는 사건 — 지금 밝기에서 --t-out으로 옅어지게(echo-out)
      this.root.querySelectorAll('[data-uid]').forEach(el => {
        const uid = el.dataset.uid;
        const m = !!hi && hi.has(uid);
        const ev = el.classList.contains('tl-ev');
        const lit = !!echo && !m && ev && echo.has((el.dataset.k || '').slice(2)); // data-k = 'e:uid:자리'
        el.classList.toggle('is-selected', uid === sel || (!!sel && el.dataset.band === sel && (el.classList.contains('tl-htab') || el.classList.contains('tl-plate')))); // 뒤 장의 탭은 제 속국 띠를 따라 (묶음 3 · 1번 — 새 앱과 같게)
        el.classList.toggle('is-match', m);
        el.classList.toggle('is-dim', !!hi && !m && !lit);
        if (ev) {
          if (el.classList.contains('is-echo-hit') && !lit && !!hi && !m) dimmed.push(el);
          el.classList.toggle('is-echo-hit', lit);
        }
      });
      if (dimmed.length) {
        for (const el of dimmed) el.classList.add('echo-out');
        clearTimeout(this._echoOutT);
        this._echoOutT = HT.motion.later(HT.motion.T.out + 40, () => this.root.querySelectorAll('.tl-ev.echo-out').forEach(el => el.classList.remove('echo-out')));
      }
      /* 묶음: 조명 강조일 때 그 시기의 사건(제 것 · 타국)을 품은 묶음에 표시 — 알약(.tl-clu — data-uid가 없어 흐림 · 강조를 받지 않음)과
         같은 자리 사건 더미(.tl-ev.has-more — 대표 사건이 그 시기 밖이라 흐려도 뒤에 겹친 사건이 그 시기면 점과 겹 고리는 흐리지 않음, css) */
      this.root.querySelectorAll('[data-cluster]').forEach(el => {
        const c = this.spotHi && hi ? this._clusters.get(el.dataset.cluster) : null;
        el.classList.toggle('is-hit', !!c && c.keys.some(k => hi.has(k.slice(0, k.lastIndexOf(':'))) || (!!echo && echo.has(k))));
      });
      /* 묶음이 풀려 data-cluster를 잃은 요소(같은 자리 사건 더미가 확대로 풀림)에 morph가 지켜 준 is-hit이 남지 않게 — 매번 새로 셈 */
      this.root.querySelectorAll('.is-hit:not([data-cluster])').forEach(el => el.classList.remove('is-hit'));
      this.root.querySelectorAll('.tl-link, .tl-door[data-from]').forEach(el => el.classList.toggle('is-selected', !!sel && (el.dataset.from === sel || el.dataset.to === sel)));
      if (sel) {
        this.root.querySelectorAll(`.tl-ev[data-uid="${CSS.escape(sel)}"]`).forEach(el => {
          const lane = el.closest('.tl-lane');
          if (lane) lane.querySelectorAll('.tl-band').forEach(b => b.classList.add('is-onrow'));
        });
        /* 고른 인물: 그 막대가 놓인(섬긴) 띠만 제 밝기로 */
        this.root.querySelectorAll(`.tl-fig[data-uid="${CSS.escape(sel)}"]`).forEach(el => {
          const lane = el.closest('.tl-lane');
          if (lane && el.dataset.band) lane.querySelectorAll(`.tl-band[data-uid="${CSS.escape(el.dataset.band)}"]`).forEach(b => b.classList.add('is-onrow'));
        });
      }
    }

    /* ---------- 그리기 ---------- */
    _draw() {
      /* 화면 크기는 쓰기 전에 한 번 읽습니다. 트랙마다 다시 읽으면
         바로 앞에서 바꾼 띠·칸의 배치를 브라우저가 매번 강제로 계산합니다. */
      const W = Math.max(60, this.bodyEl.clientWidth - this.gutter);
      const H = this.bodyEl.clientHeight;
      const sTop = this.bodyEl.scrollTop;
      const auto = this._handHeld() || (this.anchorUid && this._anchorLane()) ? null : this._heldAuto();
      this.W = W;
      const { start, end } = this.view;
      const span = end - start;
      const k = W / span;
      const X = y => (y - start) * k;
      if (this._tip.key && this._tip.at !== `${start}|${end}|${sTop}`) this.hideTip(true); // 성씨 풍선: 보기가 옮겨지면 걷음 (칸이 풍선 밑에서 달아나지 않게)
      /* 움직이는 동안은 고요: 이번 그리기가 손에 잡힌 동안의 것인지 먼저 적어 둡니다 — 세부 효과가 제자리 120ms 투명도로 조용해지고(_fxMode), 호버로 부푸는 것도 쉽니다(css .tl.is-moving) */
      const motion = this._inMotion();
      const last = this._drawn;
      this._moving = motion || (this._moving && !!last && (last.start !== start || last.k !== k)); // 멀리 가기의 도착 프레임도 아직 움직이는 그림입니다 — 보기가 직전과 다르면 조용히
      this.root.classList.toggle('is-moving', motion);
      const drawn = { start, k }; // 이번 그리기의 보기 — 그린 트랙마다 적어 둡니다 (사라지는 것이 제 해를 되읽게 — _linger)
      this._fxN = 0;
      if (this._lingers.size) this._lingerMove(start, k); // 옅어지며 물러나는 것들은 제가 있던 해를 따라갑니다
      /* 이름이 붙는 중요도 단계 (멀리서는 큰 사건만) — 문턱은 두 개(_past) */
      const imp = [this._past('imp3', 2600 / span, 1), this._past('imp2', 1300 / span, 1), this._past('imp1', 500 / span, 1)];
      this._minImp = !imp[0] ? 99 : !imp[1] ? 3 : !imp[2] ? 2 : 1;

      /* 연도 눈금. 세로선은 승계선·소속선과 헷갈리지 않도록 아주 옅은 파스텔 점선으로만 긋고,
         대신 한 칸 걸러 아주 옅은 바탕 띠를 깔아 세기(눈금 간격)를 구별합니다.
         한 해가 넉넉히 넓어지면 해보다 작은 눈금으로: 6개월 → 3개월 → 1개월 → 10일 → 5일 → 이틀 → 하루 → 12·6·3·1시간.
         윗단위가 바뀌는 눈금(1월 · 1일 · 0시)은 조금 진하게 그 단위 이름을 적습니다 */
      let sub = HT.cal ? HT.cal.subStep(k) : null;
      /* 눈금 단위의 문턱도 두 개: 지금 쓰는 단위는 글자 사이가 8% 더 좁아질 때까지 그대로 (더 촘촘한 단위로는 제 문턱에서 바로) */
      if (this._sub && sub !== this._sub && HT.cal.subStep(k / (1 - LOD_GAP)) === this._sub) sub = this._sub;
      this._sub = sub;
      let ticks = '';
      let grid = '';
      const gridX = (this._gridX = []); // 해 눈금선의 자리 — 유령 구분선이 눈금선과 겹치면 조금 짙게(묻히지 않게 · _altMarksHTML)
      if (sub) {
        const list = HT.cal.subTicks(start, end, sub);
        list.forEach((tk, i) => {
          const x = X(tk.t);
          const nx = i + 1 < list.length ? X(list[i + 1].t) : W + 1;
          const shown = tk.t >= start - 1e-12;
          if (shown) ticks += `<span class="tl-tick${tk.major ? ' is-major' : ''}" data-k="${tk.key}" style="left:${cx(x)}px">${esc(tk.label)}</span>`;
          if (tk.idx % 2 === 0) {
            const l = Math.max(0, x);
            const w = Math.min(W, nx) - l;
            if (w > 0) grid += `<i class="tl-gband" style="left:${cx(this.gutter + l)}px;width:${cx(w)}px"></i>`;
          }
          if (shown) grid += `<i class="tl-gl${tk.major ? ' is-major' : ''}" style="left:${cx(this.gutter + x)}px"></i>`;
          if (shown) gridX.push(x);
        });
      } else {
        const step = this._stepAt('axis', AXIS_STEPS, k, 96) || AXIS_STEPS[AXIS_STEPS.length - 1]; // 눈금 간격(과 바탕 줄무늬)의 문턱도 두 개: 96px에서 촘촘해지고, 88px까지 좁아져야 성겨집니다
        const first = Math.ceil(start / step) * step;
        for (let i = 0, t = first - step; t <= end; i++, t = first + (i - 1) * step) {
          const x = X(t);
          const half = this.seogo ? textWidth(HT.formatAxisYear(t), 11, 700) / 2 + 2 : 0; // 서고: 가장자리에서 반쯤 잘릴 눈금 글은 그리지 않음(왼쪽 'n년 보기' 글과 겹치지 않게 — 감독 2026-10-24 전수 점검)
          if (t >= first && (!this.seogo || (x >= half && x <= W - half))) ticks += `<span class="tl-tick" data-k="y${t}" style="left:${cx(x)}px">${HT.formatAxisYear(t)}</span>`;
          const shade = Math.round(t / step) % 2 === 0;
          if (shade) {
            const l = Math.max(0, x);
            const w = Math.min(W, X(t + step)) - l;
            if (w > 0) grid += `<i class="tl-gband" style="left:${cx(this.gutter + l)}px;width:${cx(w)}px"></i>`;
          }
          if (t >= first) grid += `<i class="tl-gl${Math.abs(t) < 1e-9 ? ' is-zero' : ''}" style="left:${cx(this.gutter + x)}px"></i>`;
          if (t >= first) gridX.push(x);
        }
      }
      /* 조명 메아리 · 가문 조명: 맨 위 연도 줄의 아래쪽에 조명된 기간의 가는 괄호 (눈금 글자 아래 — 겹치지 않습니다) */
      this._brkSpans().forEach(([a, b], i) => {
        const l = HT.clamp(X(a), 0, W);
        const r = HT.clamp(X(b), 0, W);
        if (r - l > 0.5) ticks += `<i class="tl-spot-brk${X(a) < 0 ? ' clip-l' : ''}${X(b) > W ? ' clip-r' : ''}" data-k="brk${i}" style="left:${cx(l)}px;width:${cx(r - l)}px"></i>`;
      });
      const cells = kind => this.axisEl.querySelector(`.tl-axis-cells[data-kind="${kind}"]`);
      const fx = this._fx(W); // 날짜 칸은 그리기마다 그리므로 직전 자리를 늘 되읽을 수 있습니다
      const tickFx = morph(cells('years'), ticks, fx);
      if (fx && tickFx && tickFx.born.length && tickFx.born.length < 40) for (const el of tickFx.born) this._fadeIn(el); // 눈금 간격이 바뀌면 새 눈금은 떠오르고, 빠지는 눈금은 제 해를 따라가며 옅어집니다
      /* 모서리: 보기 폭 (해보다 작으면 화면 왼쪽 끝이 속한 해·달을 크게) */
      const corner = this.axisEl.querySelector('[data-corner="years"]');
      const spanText = HT.cal ? HT.cal.spanText(span) : `${Math.round(span)}년`;
      const cornerHtml = sub ? `<b>${esc(HT.cal.context(start, sub))}</b><small>· ${esc(spanText)} 보기</small>` : esc(`${spanText} 보기`);
      if (corner._html !== cornerHtml) {
        corner._html = cornerHtml;
        corner.innerHTML = cornerHtml;
      }

      /* 간지 */
      const ganjiEl = cells('ganji');
      const cyc = this._cycle(); // DLC의 간지 설정 (형식 3 — 설계 6 결정 8 B) · 없으면 육십갑자(아래 예전 그대로)
      if (ganjiEl && cyc) {
        /* 간지 설정: 육십갑자 줄과 같은 꼴(해마다 이어진 칸 · 몇 해마다 눈금 · 넓게 보면 한 바퀴의 첫 해만) — 첫 이름의 해는 갑자년처럼 강조.
           이름이 길면 칸이 넉넉해질 때까지 눈금으로. 날마다의 이름(일진)은 육십갑자일 때만 */
        const n = cyc.names.length;
        const need = Math.max(26, Math.ceil(Math.max(...cyc.names.map(s => textWidth(s, 10.5))) + 6));
        const cStep = this._stepAt('cycle', [1, 2, 5, 10, 20, 30], k, need);
        const tipOf = y => `${HT.formatYear(y)} ${HT.cycleName(cyc, y)} (${HT.cycleLabel(cyc)})`;
        let html = '';
        if (cStep === 1) {
          const ys = [];
          for (let y = Math.floor(start); y <= Math.ceil(end); y++) {
            if (y === 0) continue;
            if (X(y + 1) < 0 || X(y) > W) continue;
            ys.push(y);
          }
          const jn = joins(ys, () => '', y => X(y), y => X(y + 1));
          ys.forEach((y, j) => {
            const x1 = X(y);
            const x2 = X(y + 1);
            const gl = jn[j].l ? 0 : 0.5;
            const gr = jn[j].r ? 0 : 0.5;
            const idx = HT.cycleIndex(cyc, y);
            html += `<i class="tl-acell${idx === 0 ? ' is-gapja' : ''}${idx % 2 ? ' is-alt' : ''}${jn[j].l ? ' j-l' : ''}${jn[j].r ? ' j-r' : ''}" style="left:${cx(x1 + gl)}px;width:${cx(Math.max(0, x2 - x1 - gl - gr))}px" title="${esc(tipOf(y))}">${esc(HT.cycleName(cyc, y))}</i>`;
          });
        } else if (cStep) {
          const withYear = this._past(`cycleYear${cStep}`, cStep * k, need + 38);
          for (let y = Math.floor(start / cStep) * cStep; y <= end; y += cStep) {
            if (y === 0) continue;
            const x = X(y);
            if (x < -30 || x > W) continue;
            html += `<i class="tl-atick${HT.cycleIndex(cyc, y) === 0 ? ' is-gapja' : ''}" style="left:${cx(x)}px" title="${esc(tipOf(y))}">${esc(HT.cycleName(cyc, y))}${withYear ? `<small>${esc(HT.formatAxisYear(y))}</small>` : ''}</i>`;
          }
        } else if (this._past('cycleRound', k * n, Math.max(56, need + 30))) {
          for (const y of HT.cycleFirstYears(cyc, start, end)) html += `<i class="tl-atick" style="left:${cx(X(y))}px" title="${esc(tipOf(y))}">${esc(cyc.names[0])} ${esc(HT.formatAxisYear(y))}</i>`;
        } else {
          html = `<span class="tl-ahint">확대하면 ${esc(HT.cycleLabel(cyc))} 줄이 보입니다</span>`;
        }
        ganjiEl.innerHTML = html;
      } else if (ganjiEl) {
        let html = '';
        const gStep = this._stepAt('ganji', [1, 2, 5, 10, 20, 30], k, 26);
        const dayW = k / 365.25;
        if (HT.cal && this._past('ganjiDay', dayW, 26)) {
          /* 날이 넉넉히 보이면 날마다의 간지(일진) — 60일마다 돌아오는 갑자일은 강조 */
          const J0 = HT.cal.at(start).J;
          const J1 = HT.cal.at(end).J;
          const js = [];
          for (let J = J0; J <= J1 && js.length < 500; J++) js.push(J);
          const jn = joins(js, () => '', J => X(HT.cal.tOf(J)), J => X(HT.cal.dayEnd(J)));
          js.forEach((J, n) => {
            const x1 = X(HT.cal.tOf(J));
            const x2 = X(HT.cal.dayEnd(J));
            const gl = jn[n].l ? 0 : 0.5;
            const gr = jn[n].r ? 0 : 0.5;
            const idx = HT.cal.dayGanjiIndex(J);
            const name = HT.cal.dayGanji(J);
            html += `<i class="tl-acell${idx === 0 ? ' is-gapja' : ''}${J % 2 ? ' is-alt' : ''}${jn[n].l ? ' j-l' : ''}${jn[n].r ? ' j-r' : ''}" style="left:${cx(x1 + gl)}px;width:${cx(Math.max(0, x2 - x1 - gl - gr))}px" title="${esc(`${HT.cal.formatT(HT.cal.tOf(J), 'd')} · ${name}일 (일진)`)}">${name}</i>`;
          });
        } else if (gStep === 1) {
          /* 해마다 이어지므로 틈 없는 하나의 긴 둥근 칸 — 안쪽은 가는 구분선 */
          const ys = [];
          for (let y = Math.floor(start); y <= Math.ceil(end); y++) {
            if (y === 0) continue;
            if (X(y + 1) < 0 || X(y) > W) continue;
            ys.push(y);
          }
          const jn = joins(ys, () => '', y => X(y), y => X(y + 1));
          ys.forEach((y, n) => {
            const x1 = X(y);
            const x2 = X(y + 1);
            const gl = jn[n].l ? 0 : 0.5;
            const gr = jn[n].r ? 0 : 0.5;
            const idx = HT.ganjiIndex(y);
            html += `<i class="tl-acell${idx === 0 ? ' is-gapja' : ''}${idx % 2 ? ' is-alt' : ''}${jn[n].l ? ' j-l' : ''}${jn[n].r ? ' j-r' : ''}" style="left:${cx(x1 + gl)}px;width:${cx(Math.max(0, x2 - x1 - gl - gr))}px" title="${esc(`${HT.formatYear(y)} ${HT.ganji(y)}년`)}">${HT.ganji(y)}</i>`;
          });
        } else if (gStep) {
          // 중간 단계: 몇 해마다 그 해의 간지를 눈금으로 (갑자년은 강조)
          const withYear = this._past(`ganjiYear${gStep}`, gStep * k, 64);
          for (let y = Math.floor(start / gStep) * gStep; y <= end; y += gStep) {
            if (y === 0) continue;
            const x = X(y);
            if (x < -30 || x > W) continue;
            const idx = HT.ganjiIndex(y);
            html += `<i class="tl-atick${idx === 0 ? ' is-gapja' : ''}" style="left:${cx(x)}px" title="${esc(`${HT.formatYear(y)} ${HT.ganji(y)}년`)}">${HT.ganji(y)}${withYear ? `<small>${esc(HT.formatAxisYear(y))}</small>` : ''}</i>`;
          }
        } else if (this._past('ganji60', k * 60, 56)) {
          // 넓게 볼 때는 60년마다 돌아오는 갑자년만 표시
          const first = Math.ceil((start - 4) / 60) * 60 + 4;
          for (let y = first; y <= end; y += 60) {
            const yy = y <= 0 ? y - 1 : y;
            html += `<i class="tl-atick" style="left:${cx(X(yy))}px" title="${esc(`${HT.formatYear(yy)} 갑자년`)}">갑자 ${esc(HT.formatAxisYear(yy))}</i>`;
          }
        } else {
          html = '<span class="tl-ahint">확대하면 간지가 보입니다</span>';
        }
        ganjiEl.innerHTML = html;
      }

      /* 보조 달력 (음력 · 이슬람력 …): 달이 18px 넘게 보이면 열립니다. 날이 넉넉하면 그 달력의 날까지 */
      const calRow = this.axisEl.querySelector('[data-cal-row]');
      if (calRow) {
        const open = this._past('calOpen', sub ? k / 12 : 0, 18);
        if (open !== !!this._calOpen) {
          this._calOpen = open;
          calRow.classList.toggle('is-open', open);
        }
        const el = calRow.querySelector('[data-kind="cal"]');
        let html = '';
        if (open) {
          const id = this.altCal;
          const c = HT.cal.get(id);
          const J0 = HT.cal.at(start).J;
          const J1 = HT.cal.at(end).J;
          const dayW = k / 365.25;
          const monthName = m => `${m.leap ? '윤' : ''}${m.m}월`;
          const yearName = y => (c.lunar ? `${HT.ganji(y)}년` : `${y < 0 ? `기원전 ${-y}` : y}년`);
          if (this._past('calDay', dayW, 20)) {
            /* 날마다: 그 달력의 날짜 (초하루는 달 이름, 보름은 조금 진하게) */
            for (let J = J0; J <= J1 + 1 && J - J0 < 500; J++) {
              const p = HT.cal.partsIn(id, J);
              if (!p) break;
              const x1 = X(HT.cal.tOf(J));
              const x2 = X(HT.cal.dayEnd(J));
              const first = p.d === 1;
              const label = first ? (p.m === 1 && !p.leap ? `${yearName(p.y)} ${monthName(p)}` : monthName(p)) : String(p.d);
              const fits = x2 - x1 >= textWidth(label, 10.5) + 6;
              html += `<i class="tl-acell tl-calday${first ? ' is-first' : ''}${c.lunar && p.d === 15 ? ' is-full' : ''}${(p.m + (p.leap ? 1 : 0)) % 2 ? ' is-alt' : ''}" data-k="cd${J}" style="left:${cx(x1 + 0.5)}px;width:${cx(Math.max(0, x2 - x1 - 1))}px" title="${esc(`${HT.cal.formatIn(id, HT.cal.tOf(J))} = ${HT.cal.formatT(HT.cal.tOf(J), 'd')}`)}">${fits ? esc(label) : first ? esc(String(p.m)) : ''}</i>`;
            }
          } else {
            const months = HT.cal.monthsIn(id, J0 - 1, J1 + 1);
            months.forEach((m, i) => {
              const nx = months[i + 1] ? months[i + 1].t : HT.cal.tOf(m.J + 30);
              const x1 = X(m.t);
              const x2 = X(nx);
              if (x2 < 0 || x1 > W) return;
              const l = Math.max(x1, 0);
              const r = Math.min(x2, W);
              const w = r - l;
              if (w < 1) return;
              const label = m.major ? `${yearName(m.y)} ${monthName(m)}` : monthName(m);
              const text = w >= textWidth(label, 10.5) + 8 ? label : w >= textWidth(monthName(m), 10.5) + 6 ? monthName(m) : '';
              html += `<i class="tl-acell tl-calmon${m.major ? ' is-first' : ''}${m.leap ? ' is-leap' : ''}${i % 2 ? ' is-alt' : ''}${x1 < 0 ? ' clip-l' : ''}${x2 > W ? ' clip-r' : ''}" data-k="cm${m.J}" style="left:${cx(l + (x1 < 0 ? 0 : 0.5))}px;width:${cx(Math.max(0, w - (x1 < 0 ? 0 : 0.5) - (x2 > W ? 0 : 0.5)))}px" title="${esc(`${c.name} ${yearName(m.y)} ${monthName(m)} — ${HT.cal.formatT(m.t, 'd')}부터`)}">${esc(text)}</i>`;
            });
          }
        }
        morph(el, html, fx);
      }

      /* 시대 구분 */
      for (const row of this.epochRows || []) {
        const el = this.axisEl.querySelector(`.tl-axis-cells[data-kind="epoch"][data-track="${CSS.escape(row.track ? row.track.id : '')}"]`);
        if (!el) continue;
        let html = '';
        for (const e of row.epochs) {
          const a = X(e.start);
          const b = X(e.endY);
          if (b < 0 || a > W) continue;
          const l = Math.max(a, 0);
          const w = Math.min(b, W) - l;
          if (w < 1) continue;
          const label = w >= textWidth(e.name, 11, 650) + 20 ? esc(e.name) : w >= 34 ? esc(e.name.replace(/\s*시대$/, '').slice(0, 2)) : '';
          const tip = `${e.name} · ${HT.formatRange(e)}${e.note ? ` · ${e.note}` : ''} — 누르면 상세·문서`;
          const gl = a < 0 ? 0 : 0.5;
          const gr = b > W ? 0 : 0.5;
          html += `<i class="tl-epoch${a < 0 ? ' clip-l' : ''}${b > W ? ' clip-r' : ''}" data-uid="${esc(e.uid)}" style="left:${cx(l + gl)}px;width:${cx(Math.max(0, w - gl - gr))}px;top:${(e._lane || 0) * AXIS.epoch + 3}px;height:${AXIS.epoch - 6}px;--c:${e.color}" title="${esc(tip)}"><b>${label}</b></i>`;
        }
        el.innerHTML = html;
      }

      /* 나라별 연호 */
      for (const row of this.eraRows || []) {
        const el = this.axisEl.querySelector(`.tl-axis-cells[data-kind="era"][data-track="${CSS.escape(row.track.id)}"]`);
        if (!el) continue;
        const seen = row.eras.filter(c => X(c.end) >= 0 && X(c.start) <= W);
        let html = '';
        const avg = seen.length ? seen.reduce((s, c) => s + Math.min(X(c.end), W) - Math.max(X(c.start), 0), 0) / seen.length : 0;
        /* 한 왕조(같은 정권)에서 이어지는 연호는 틈 없이 하나의 긴 둥근 칸으로 — 왕조가 바뀌는 곳에서만 끊깁니다 */
        const laneOf = c => (row.folded ? 0 : c.lane || 0);
        const byLane = new Map();
        seen.forEach(c => byLane.set(laneOf(c), (byLane.get(laneOf(c)) || []).concat([c])));
        const order = new Map(seen.map((c, i) => [c, i]));
        let marks = '';
        for (const list of byLane.values()) {
          const sorted = list.slice().sort((a, b) => a.start - b.start);
          const strip = layoutStrip(sorted, c => c.polity || '', c => X(c.start), c => X(c.end), 0, W, 0.5);
          const top = laneOf(sorted[0]) * AXIS.era + 3;
          const h = AXIS.era - 6;
          /* 칸의 이설 · 모호한 칸 (디테일 건의 4): 띠 안의 칸과 같은 계획(altRowPlan) — 이름표 글은 칸 자체에 있으므로 비킴은 좌우 안쪽 여백으로 */
          const erow = strip.map(({ it: c, l, r, jl, jr, atL, atR }, k) => {
            const w = r - l;
            const label = avg >= 4 && w >= textWidth(c.name, 10.5) + 8 ? c.name : '';
            const unk = unkCell(c, k && strip[k - 1].it, jl, w, label ? textWidth(c.name, 10.5) : null, atL, atR); // 칸의 미정
            const q = c.pol || null; // 그 연호의 정권 (날짜 칸의 사본이 달고 옴)
            return { c, l, r, jl, jr, atL, atR, w, label, unk, key: `era:${c.uid}:${c.ci}`, ref: `era:${c.ci}`, base: q ? cellBaseOf(c, q, `era:${c.ci}`) : { start: c.start, end: c.end }, ink: label ? { text: label, size: 10.5, wt: 500, lh: 12.6 } : null, bl: w < 10 ? 0 : 1, br: w < 10 || jr ? 0 : 1, fade: unkFade(unk, l, r), now: q ? q.endY : null };
          });
          const plan = this._altPlan(null, erow, { X, lo: -Infinity, hi: Infinity, h, now: null, alt: this.showAlt }); // 맨 위 날짜 칸은 조감에서도 크기가 그대로 — 유령선도 그대로
          erow.forEach((u, k) => {
            const { c, l, jl, jr, atL, atR, w, label, unk } = u;
            const tip = `${c.polity} 연호 ${c.name} · ${cellRange(c)}${c.note ? ` · ${c.note}` : ''}${altTip(c, u.base)}`;
            const z = plan.zones.get(k);
            const dx = plan.shift.get(k) || 0;
            const pad = dx ? `;padding-left:${cx(3 + Math.max(0, 2 * dx))}px;padding-right:${cx(3 + Math.max(0, -2 * dx))}px` : ''; // 글이 칸 자체에 있어 좌우 여백의 차로 가운데를 옮김
            html += `<i class="tl-acell${order.get(c) % 2 ? ' is-alt' : ''}${w < 10 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL ? ' clip-l' : ''}${atR ? ' clip-r' : ''}${this._isSpot(c.uid, u.ref) ? ' is-spot' : ''}${unk.cls}${zoneCls(z)}" data-k="${esc(u.key)}" data-uid="${esc(c.uid)}" data-cell="era:${c.ci}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${h}px;--c:${c.color}${unk.css}${pad}${z ? zoneCss(z, u.bl) : ''}" title="${esc(tip)}">${esc(label)}</i>`;
          });
          marks += this._altMarksHTML(null, erow, plan, { top, h, vw: W - 1, color: u => u.c.color, spot: u => this._isSpot(u.c.uid, u.ref) });
        }
        const res = morph(el, html + marks, fx); // 날짜 칸도 키로 이어 씀 — 유령선이 '이설' 체크 · 조명을 바꿀 때 떠오르고 옅어지게 (움직임 원칙 ②)
        if (res && fx) this._laneFx(res, W, fx.quiet);
      }

      /* 접힌 연호·도읍 묶음: 나라마다 가는 막대 한 줄씩 — 어느 시기에 무엇이 들어 있는지만 */
      for (const gr of this.groupRows || []) {
        const el = this.axisEl.querySelector(`.tl-axis-cells[data-kind="group"][data-group="${gr.key}"]`);
        if (!el) continue;
        if (gr.open) {
          el.innerHTML = '';
          continue;
        }
        const n = Math.min(gr.list.length, 4);
        const bh = Math.min(5, Math.floor((AXIS.group - 6) / n) - 1);
        const top0 = (AXIS.group - (n * (bh + 1) - 1)) / 2;
        let html = '';
        gr.list.slice(0, n).forEach((d, i) => {
          if (gr.epochs) {
            /* 접은 시대 구분 줄 (시대 접기): 나라마다 한 가닥 — 시대 구분마다 제 색의 막대 (겹친 시대는 늦게 시작한 것이 위) */
            for (const e of d.epochs) {
              const l = Math.max(X(e.start), 0);
              const r = Math.min(X(e.endY), W);
              if (r - l < 0.5) continue;
              html += `<i class="tl-gbar" style="left:${cx(l)}px;width:${cx(Math.max(2, r - l))}px;top:${cx(top0 + i * (bh + 1))}px;height:${bh}px;--c:${e.color}"></i>`;
            }
            return;
          }
          // 한 나라의 구간을 합쳐서 (막대끼리 겹치지 않게)
          const merged = [];
          for (const [a, b] of d.spans.slice().sort((u, v) => u[0] - v[0])) {
            const last = merged[merged.length - 1];
            if (last && a <= last[1]) last[1] = Math.max(last[1], b);
            else merged.push([a, b]);
          }
          for (const [a, b] of merged) {
            const l = Math.max(X(a), 0);
            const r = Math.min(X(b), W);
            if (r - l < 0.5) continue;
            html += `<i class="tl-gbar" style="left:${cx(l)}px;width:${cx(Math.max(2, r - l))}px;top:${cx(top0 + i * (bh + 1))}px;height:${bh}px;--c:${d.track.color}"></i>`;
          }
        });
        el.innerHTML = html;
      }

      /* 나라별 도읍: 정권마다 하나의 긴 둥근 칸(천도 = 가는 구분선 · 임시 = 점선 칸). 배도는 아래 옅은 갈래 */
      for (const row of this.capRows || []) {
        const el = this.axisEl.querySelector(`.tl-axis-cells[data-kind="cap"][data-track="${CSS.escape(row.track.id)}"]`);
        if (!el) continue;
        let html = '';
        let marks = '';
        for (const en of row.entries) {
          const top = en.lane * AXIS.cap + 3;
          /* 보이지 않을 만큼 좁은 임시 도읍(1년 피난 등)은 이 배율에서 빼고, 그 때문에 갈린 정도 칸을 다시 하나로 */
          const segs = [];
          for (const g of en.segs) {
            if (g.c.role === 'temporary' && X(g.e) - X(g.s) < 4) continue;
            const last = segs[segs.length - 1];
            if (last && last.c === g.c) segs[segs.length - 1] = { c: g.c, s: last.s, e: Math.max(last.e, g.e) };
            else segs.push(g);
          }
          /* 칸의 미정: 조각의 끝이 그 도읍의 진짜 시작 · 끝일 때만 (임시 도읍에 갈린 조각의 끝은 미정이 아님) */
          const segUnk = g => ({ startUnknown: !!g.c.startUnknown && Math.abs(g.s - g.c.start) < 1e-9, endUnknown: !!(g.c.endUnknown || g.c.endYAuto) && Math.abs(g.e - g.c.endY) < 1e-9 });
          const strip = layoutStrip(segs, () => en.key, g => X(g.s), g => X(g.e), 0, W, 0.5);
          const h = AXIS.cap - 6;
          /* 칸의 이설 · 모호한 칸 (디테일 건의 4): 도읍 하나가 임시 도읍에 갈려 조각이 여럿이어도 이설의 경계는 그 도읍의 진짜 시작 · 끝과 견줌(통설 구간 = 그 도읍의 칸) */
          const crow = strip.map(({ it: g, l, r, jl, jr, atL, atR }, k) => {
            const c = g.c;
            const w = r - l;
            const text = c.label || c.name;
            const full = w >= textWidth(text, 10.5, 600) + 10;
            const label = full ? text : w >= textWidth(text.slice(0, 1), 10.5, 600) + 8 ? text.slice(0, 1) : '';
            const ref = `capital:${en.p.capitals.indexOf(c)}`; // 칸 참조: 그 정권의 도읍 목록(HT.resolveCapitals의 결과)에서의 순번
            const unk = unkCell(segUnk(g), k && segUnk(strip[k - 1].it), jl, w, full ? textWidth(text, 10.5, 600) : label ? textWidth(text.slice(0, 1), 10.5, 600) : null, atL, atR);
            /* 같은 도읍의 조각이 여럿이면 이설 표식은 그 도읍의 진짜 시작 · 끝이 든 조각에만 (한 경계에 선 하나) */
            const own = Math.abs(g.s - c.start) < 1e-9 || Math.abs(g.e - c.endY) < 1e-9;
            return { c: own ? c : null, g, l, r, jl, jr, atL, atR, w, label, unk, ref, key: `cap:${en.key}:${ref}:${g.s}`, base: own ? cellBaseOf(c, en.p, ref) : null, ink: label ? { text: label, size: 10.5, wt: 600, lh: 12.6 } : null, bl: w < 10 ? 0 : 1, br: w < 10 || jr ? 0 : 1, fade: unkFade(unk, l, r), now: en.p.endY };
          });
          const plan = this._altPlan(null, crow, { X, lo: -Infinity, hi: Infinity, h, now: null, alt: this.showAlt }); // 맨 위 날짜 칸은 조감에서도 크기가 그대로 — 유령선도 그대로
          crow.forEach((u, k) => {
            const { g, l, jl, jr, atL, atR, w, label, unk, ref } = u;
            const c = g.c;
            const z = plan.zones.get(k);
            const dx = plan.shift.get(k) || 0;
            const pad = dx ? `;padding-left:${cx(3 + Math.max(0, 2 * dx))}px;padding-right:${cx(3 + Math.max(0, -2 * dx))}px` : '';
            const cls = `${c.role === 'temporary' ? ' is-temp' : ''}${c.role === 'exile' ? ' is-exile' : ''}${w < 10 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL ? ' clip-l' : ''}${atR ? ' clip-r' : ''}${this._isSpot(en.p.uid, ref) ? ' is-spot' : ''}${unk.cls}${zoneCls(z)}`;
            html += `<i class="tl-acell tl-ccell${cls}" data-k="${esc(u.key)}" data-uid="${esc(en.p.uid)}" data-cell="${ref}" data-city="${esc(c.city)}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${h}px;--c:${en.p.color}${unk.css}${pad}${z ? zoneCss(z, u.bl) : ''}" title="${esc(this._capTip(en.p, c))}">${esc(label)}</i>`;
          });
          marks += this._altMarksHTML(null, crow, plan, { top, h, vw: W - 1, color: () => en.p.color, spot: u => this._isSpot(en.p.uid, u.ref) });
        }
        if (row.secOpen) {
          const base = row.lanes * AXIS.cap + 1;
          for (const gr of row.sec) {
            const a = X(gr.start);
            const b = X(gr.endY);
            if (b <= 0 || a >= W) continue;
            const l = a <= 0 ? 0 : a + 0.5;
            const r = b >= W ? W : b - 0.5;
            const w = r - l;
            if (w < 1) continue;
            /* 칸의 미정: 묶음의 첫 시작 · 마지막 끝이 미정인 도시의 것이면 그쪽 끝이 옅어지고, 이름 뒤의 해도 "미정" */
            const gu = { startUnknown: gr.members.some(c => c.startUnknown && c.start === gr.start), endUnknown: gr.members.some(c => c.endUnknown && c.endY === gr.endY) };
            const full = `${gr.name} ${gu.startUnknown ? '미정' : bcYear(gr.start)}–`;
            const fits = w >= textWidth(full, 9.5, 600) + 12;
            const label = fits ? esc(full) : w >= textWidth(gr.name, 9.5, 600) + 10 ? esc(gr.name) : '';
            const tip = `${gr.p.name} 배도 · ${gr.members.map(c => `${c.as && c.as !== c.city ? `${c.as}(${c.city})` : c.city} ${c.startUnknown ? '미정' : HT.formatWhen(c, 'start')}~`).join(' · ')}`;
            const refs = gr.members.map(c => `capital:${gr.p.capitals.indexOf(c)}`); // 묶음(5경 …)은 첫 도시의 칸으로 엽니다 — 묶인 도시 가운데 하나라도 조명되어 있으면 진하게
            const unk = unkCell(gu, null, false, w, label ? textWidth(fits ? full : gr.name, 9.5, 600) : null, a <= 0, b >= W);
            html += `<i class="tl-acell tl-ccell is-sec${w < 10 ? ' is-thin' : ''}${a <= 0 ? ' clip-l' : ''}${b >= W ? ' clip-r' : ''}${refs.some(r => this._isSpot(gr.p.uid, r)) ? ' is-spot' : ''}${unk.cls}" data-k="${esc(`sec:${gr.p.uid}:${refs[0]}`)}" data-uid="${esc(gr.p.uid)}" data-cell="${refs[0]}"${gr.city ? ` data-city="${esc(gr.city)}"` : ''} style="left:${cx(l)}px;width:${cx(w)}px;top:${base + gr.lane * AXIS.capSec}px;height:${AXIS.capSec - 3}px;--c:${gr.p.color}${unk.css}" title="${esc(tip)}">${label}</i>`;
          }
        }
        const res = morph(el, html + marks, fx); // 날짜 칸도 키로 이어 씀 (연호 줄과 같게)
        if (res && fx) this._laneFx(res, W, fx.quiet);
      }
      if (this._hotCity) this._markCity(this._hotCity);

      /* 격자·현재·기준선·기간 재기 */
      const nowX = X(HT.NOW_T ?? HT.CURRENT_YEAR);
      if (nowX >= 0 && nowX <= W) grid += `<i class="tl-now${this.seogo && nowX > W - 40 ? ' is-left' : ''}" style="left:${cx(this.gutter + nowX)}px"><span>현재</span></i>`; // 서고: 오른쪽 끝에 가까우면 글을 선 왼쪽에(잘리거나 접기 표와 겹치지 않게)
      /* 기준선·기간 재기의 날짜는 지금 눈금 단위만큼 자세히 (해 → 1592년, 달 → 1592년 5월, 날 → 5월 23일, 시 → 14시) */
      const prec = !sub ? 'y' : sub.unit === 'mo' ? 'm' : sub.unit === 'd' ? 'd' : 'h';
      const at = t => (prec === 'y' ? HT.formatYear(t) : HT.cal.formatT(t, prec));
      if (this.marker != null) {
        const mx = X(this.marker);
        const cy = this._cycle(); // 간지 설정(형식 3)이면 그 이름 · 간지 줄을 DLC가 끈 채면(보는 사람이 켜지 않음) 적지 않음
        const gj = cy ? HT.cycleName(cy, this.marker) : this.yearCycle && this.yearCycle.off && !this.show.ganji ? '' : prec === 'd' || prec === 'h' ? `${HT.cal.dayGanji(HT.cal.at(this.marker).J)}일` : HT.ganji(this.marker);
        if (mx >= -1 && mx <= W + 1) grid += `<i class="tl-marker" style="left:${cx(this.gutter + mx)}px"><span>${esc(at(this.marker))} ${esc(gj)}</span></i>`;
      }
      if (this.measure) {
        const a = Math.min(this.measure.a, this.measure.b);
        const b = Math.max(this.measure.a, this.measure.b);
        const ml = HT.clamp(X(a), 0, W);
        const mr = HT.clamp(X(b), 0, W);
        const len = HT.cal ? HT.cal.durText(b - a) : `${Math.round(b - a).toLocaleString()}년`;
        grid += `<i class="tl-band-measure" style="left:${cx(this.gutter + ml)}px;width:${cx(mr - ml)}px"><span>${esc(`${at(a)} ~ ${at(b)} · ${len}`)}</span></i>`;
      }
      this.gridEl.innerHTML = grid;

      const keepOpen = motion || !!this._settleDue; // 손에 잡힌 동안과 정착을 기다리는 동안에는 줄이 펴지기만 하고 접히지 않습니다 — 접힘은 정착 한 번에(_settle)
      this.tracks.forEach(tr => (tr._heightChanged = false));
      /* 세로로 화면 밖에 있는 트랙(위아래 한 화면 여유 밖)은 그리지 않습니다 — 스크롤해 들어오면 그때 그립니다(_stale) */
      const sBot = sTop + H;
      const slack = Math.max(300, H);
      this._planUnions(X, W, sTop, sBot); // 동군연합 이음줄 · 겹고리 표지(트랙마다 제 몫 — _drawLinks · _cells)
      let y = 0;
      for (const s of this.spheres) this._drawSphereTags(s, X, W); // 서고: 접힌 문화권의 머리 단 안 작은 꼬리표
      for (const tr of this.tracks) {
        y += this._sphereLead(tr); // 서고: 문화권 머리 단 · 틈
        if (tr._sphereHidden) continue; // 접힌 문화권의 트랙: 높이 0 · 안 그림
        const h = tr.height;
        /* 밀도가 바뀌며 흐르는 동안 화면에 드는 트랙(_squash — 흐르는 내내 화면 밖인 트랙은 _squashAway가 뺌)은 흐르는 동안 늘 그립니다: 여기의 자리(y)는 다 흐른 뒤의 모델이고 스크롤은 흐르는 중이라,
           줄어드는 내용의 아래쪽에서 조감으로 가면 화면에 있는 트랙을 밖으로 잘못 보고 새 줄 안의 것 없이 잔상만 옅어지던 것(스크롤이 따라 내려올 때까지) */
        const flowing = !!tr._squash && HT.motion.now() < tr._squash.g.until;
        const off = tr.el && !flowing && (y > sBot + slack || y + h < sTop - slack);
        if (off) this._releaseTrackScene(tr);
        if (tr._was && HT.motion.now() > tr._was.until) tr._was = null; // 앞선 화면의 줄은 다시 지은 직후의 첫 그리기에만 씁니다
        if (tr.folded) {
          if (off) tr._stale = true;
          else {
            tr._stale = false;
            this._drawFolded(tr, X, W);
            tr._view = drawn;
          }
        } else {
          this._collapseRows(tr, X, W, keepOpen);
          if (off) tr._stale = true;
          else {
            tr._stale = false;
            /* 줄 높이가 흐르는 동안은 중간 자리가 모델과 다르므로 기존처럼 모두 채웁니다.
               정착하면 한 화면보다 작은 여유를 두고 줄 단위로 거릅니다. 조감의 이름·연결선 계획은 그대로 둡니다. */
            tr._drawRows = this._bird || flowing || tr._was || tr._gather || this._loopOn ? null : visibleRows(tr, sTop - y, sBot - y, Math.max(180, H * 0.4));
            tr._rowsVirtual = !!tr._drawRows && tr._drawRows.size < tr.rows;
            tr._neededRows = tr._drawRows ? visibleRows(tr, sTop - y, sBot - y, 48) : null;
            tr._paintClip = { top: Math.max(0, sTop - y - 96), height: H + 192 };
            this._drawTrackScene(tr, X, W);
            tr._view = drawn;
          }
        }
        y += tr.height + 1;
      }
      this._drawn = drawn;
      if (this.seogo) this._drawF4Threads(); // 과제 9: 사람 띠의 실 · 뿔 매듭(띠 뒤 통로)
      this._applyStates();
      this._keepAnchor(auto); // 세로 스크롤을 쓰는 곳은 여기 하나 (멀리 갈 때의 세로 이동도 이 프레임의 값으로)
      if (this.tracks.some(tr => tr._heightChanged)) this._anchorLoop(HT.motion.T.move + 60, auto); // 줄 높이가 흐르기 시작했으면 흐르는 동안 매 프레임
      if (this._enterArm) {
        this._enterArm(); // 첫 등장의 시한은 첫 그리기 뒤부터 (_enter)
        this._enterArm = null;
      }
      if (this.opts.onViewChange) this.opts.onViewChange(this.view);
    }

    /** 접힌 줄의 가는 막대 — 시간이 겹치면 단을 나눠(최대 3단) 서로 겹치지 않게 */
    _miniBars(list, X, W, attrs = '', laneKey = '_laneAll', boxH = 0) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      const top0 = this._bird ? (boxH - (2 * G.miniPitch + G.mini)) / 2 : G.miniTop; // 조감: 세 단(높이 3 · 간격 4)이 낮은 칸(접힌 줄 14 · 접힌 트랙 22)의 가운데에
      let html = '';
      for (const p of list) {
        const x1 = X(bandStart(p));
        const x2 = X(bandEnd(p));
        if (x2 < 0 || x1 > W) continue;
        const lane = p[laneKey] || 0; // 단은 _layoutTrack에서 자료로 정해 둔 것 — 화면을 옮겨도 그대로
        const l = Math.max(x1, 0);
        html += `<i class="tl-mini-bar" data-k="mb:${esc(p.uid)}" data-uid="${esc(p.uid)}"${attrs} style="left:${cx(l)}px;width:${cx(Math.max(3, Math.min(x2, W) - l))}px;top:${cx(top0 + lane * G.miniPitch)}px;${this._bird ? `height:${G.mini}px;` : ''}--c:${p.color}" title="${esc(`${p.name} (${HT.formatRange(p)})`)}"></i>`;
      }
      return html;
    }

    /** 접힌 트랙: 정권 띠만 가늘게 */
    _drawFolded(tr, X, W) {
      const sq = tr._squash && HT.motion.now() < tr._squash.g.until && !tr._squash.drawn ? tr._squash : null; // 밀도가 바뀐 뒤의 첫 그리기: 새 막대는 모두 떠오름 (옛 막대는 잔상 — _squash)
      const fx = this._fx(W, tr);
      const res = morph(tr.miniEl, this._miniBars(tr.periods.filter(p => !p._hidden && !p._overlay && !p._under), X, W, '', '_laneAll', this._G().folded), fx, sq && fx ? SQZ_NONE : null);
      if (sq) {
        sq.drawn = true;
        if (res && fx) this._squashIn(res.born, sq.g);
      }
    }

    /** 이 띠를 다스린 왕조 구간 가운데 지금 보이는(필터에서 끄지 않은) 것 */
    _dynOf(p) {
      return (p.dynasties || []).filter(d => this._dynUids && this._dynUids.has(d.dynasty.uid));
    }

    /** 왕조 칸: 이 띠를 다스린 왕조마다 긴 둥근 칸 하나 (왕조가 바뀌면 끊김). 누르면 그 왕조의 상세·문서 */
    _dynCells(p, X, ox, iw, top, h, clip = {}) {
      const P = G.pad2;
      let html = '';
      const row = [];
      for (const d of this._dynOf(p)) {
        const a = X(d.start) - ox;
        const b = X(d.end) - ox;
        if (b <= P || a >= iw - P) continue;
        const l = a > P ? a + 0.5 : P;
        const r = b < iw - P ? b - 0.5 : iw - P;
        const w = r - l;
        if (w < 1) continue;
        const y = d.dynasty;
        const short = y.name.replace(/\s*(왕조|왕가|가문|家|朝)$/, '');
        const text = w >= textWidth(y.name, 10, 650) + 14 ? y.name : short && w >= textWidth(short, 10, 650) + 12 ? short : '';
        /* 왕조 칸의 이설 · 모호한 연대는 그 다스린 정권 줄(polities)의 것 + 왕조 항목 자신의 이설(칸의 끝이 곧 왕조의 끝일 때) — 칸은 적힌 값 그대로 그려지므로 통설 구간도 적힌 값 */
        row.push({ d, y, a, b, l, r, w, text, c: dynCellOf(d, y), key: `dyn:${y.uid}:${d.start}`, base: { start: d.start, end: d.end }, ink: text ? { text, size: 10, wt: 650, lh: 12 } : null, bl: w < 8 ? 0 : 1, br: w < 8 ? 0 : 1 }); // 왕조 항목 자신의 이설도 (그 끝에 닿은 칸 — dynCellOf)
      }
      const plan = this._altPlan(p, row, { X: t => X(t) - ox, lo: X(bandStart(p)) - ox + P, hi: X(bandEnd(p)) - ox - P, h });
      row.forEach((u, k) => {
        const { d, y, a, b, l, w, text } = u;
        const tip = `${y.name} · 왕조 (${HT.formatYear(d.start)} ~ ${HT.formatYear(d.end)})${y.houseName ? ` · 가문 ${y.houseName}` : y.house ? ` · ${y.house}` : ''}${d.note ? ` · ${d.note}` : ''}${altTip(u.c, u.base)} — 누르면 상세·문서`;
        const hs = y.houseId ? ` data-house="${esc(y.houseId)}"` : '';
        const z = plan.zones.get(k);
        const dx = plan.shift.get(k);
        const lf = plan.litDim && plan.litDim.has(k) ? this._litCls(l, w, true) : null; // 이름이 조명 경계를 비킬 자리가 없으면 흐린 쪽 밝기로 고르게 (lit-flat)
        const flat = lf && lf.cls === ' lit-flat' ? lf : { cls: '', css: '' };
        html += `<i class="tl-dyn${w < 8 ? ' is-thin' : ''}${a <= P && clip.l ? ' c-l' : ''}${b >= iw - P && clip.r ? ' c-r' : ''}${this._isHouse(y.houseId) ? ' is-house' : ''}${zoneCls(z)}${flat.cls}" data-uid="${esc(y.uid)}"${hs} data-row="${p._row}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${h}px;--c:${y.color}${z ? zoneCss(z, u.bl) : ''}${flat.css}" title="" aria-label="${esc(tip)}">${text ? `<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(text)}</b>` : ''}</i>`; // 성씨 풍선이 설명글을 맡음
      });
      /* 왕조 칸의 조명은 칸 참조가 아니라 그 왕조 창(왕조 uid · 그 띠의 기간)이라 색을 짙게 하는 조명 칸은 없음 — 왕조를 고른 동안(is-selected)만 */
      html += this._altMarksHTML(p, row, plan, { top, h, vw: iw - 1, gx: ox, color: u => u.y.color, spot: u => this.selected === u.y.uid });
      return html;
    }

    /** 칸 한 줄의 이설 · 모호한 칸 계획 (altRowPlan — 화면용: 진짜 경계에서 3px · 8px 칸의 문턱은 둘(_past), '이설' 체크가 꺼져 있거나 조감이면 유령선 없음 · 무늬는 그대로).
        조감에서도 크기가 그대로인 맨 위 날짜 칸(연호 · 도읍)은 o.alt로 '이설' 체크만 봄 */
    _altPlan(p, row, o) {
      const id = p ? p.uid : '';
      const plan = altRowPlan(
        row,
        Object.assign(
          {
            now: p ? p.endY : null,
            alt: this.showAlt && !this._bird,
            far: (k, d) => this._past(`calt:${id}:${k}`, d, ALT_GAP),
            wide: (u, w) => this._past(`caltw:${id}:${u.key}`, w, ALT_MIN_W),
            litEdges: p ? this._litEdges : null, // 띠 안의 칸 줄(띠 안쪽 좌표)이면 이름표가 조명 경계를 비켜 감 (litShift — 띠를 그리는 동안 _litEdges)
          },
          o
        )
      );
      return plan;
    }

    /** 유령 구분선 · '이설 있음' 점선의 HTML — 키(data-k)가 붙은 속 요소라 '이설' 체크 · 조명을 바꿀 때 떠오르고 옅어짐(morph의 한 겹 더), 조명된 칸의 것은 색만 짙게(is-spot).
        누름은 받지 않습니다(칸의 올림 · 누름을 가로채지 않게). top · h = 칸 줄의 자리 · 높이, bottom = 선 아래 들임(가문 줄이 있으면 4), x0 = 좌표를 옮길 만큼(인물 막대 안),
        vlo · vw = 그릴 수 있는 왼 · 오른쪽 끝(m.x의 좌표 — 화면에 잘린 띠 밖의 선은 그리지 않음), color(u) = 칸마다 제 색(왕조 · 예속 띠 · 날짜 칸) */
    _altMarksHTML(p, row, plan, { top, h, bottom = 2, cls = '', color = null, x0 = 0, vlo = 0, vw = Infinity, spot = null, gx = 0 } = {}) {
      let html = '';
      const grid = this._gridX || [];
      const spotted = u => (spot ? spot(u) : !!p && this._isSpot(p.uid, u.key));
      const col = u => (color ? `;--c:${color(u)}` : '');
      for (const m of plan.lines) {
        const u = row[m.owner];
        if (m.x < vlo || m.x > vw) continue;
        const onGrid = grid.some(x => Math.abs(x - (m.x + gx)) < 1.5); // 해 눈금선(옅은 점선)과 겹침 — 눈금선에 묻히지 않게 조금 짙게 (목업 보고 (가))
        if (this._caltAt && u.key) (this._caltAt.get(u.key) || this._caltAt.set(u.key, []).get(u.key)).push(m.x); // 띠 하나를 그리는 동안: 칸마다 실제로 그은 유령선 자리 (이설 조명의 점선이 같은 자리 · 같은 때만 — _altSpotsHTML)
        html += `<i class="tl-calt${cls}${spotted(u) ? ' is-spot' : ''}${onGrid ? ' on-grid' : ''}" data-k="ca:${esc(m.key)}" style="left:${cx(m.x - x0)}px;top:${cx(top + 2)}px;height:${cx(h - 2 - bottom)}px${col(u)}"></i>`;
      }
      for (const q of plan.has) {
        const u = row[q.i];
        html += `<i class="tl-calt is-has${cls}${spotted(u) ? ' is-spot' : ''}" data-k="ch:${esc(u.key)}" style="left:${cx(q.x0 - x0)}px;width:${cx(q.x1 - q.x0)}px;top:${cx(top + q.y)}px${col(u)}"></i>`;
      }
      return html;
    }

    /** 이설 조명 — 고른 칸(조명 s.cell)의 이설마다 그 기간을 띠 바탕에: 이설이 통설과 다른 쪽은 유령 구분선과 같은 자리(선의 바깥 끝까지 — 1px도 어긋나지 않게)의
        점선(d-l · d-r), 같은 쪽은 칸 조명의 경계(HT.cellSpan — 건의 7의 상호배타 경계) 그대로. 점선의 점은 그 칸 줄의 유령선과 같은 자리(--ph).
        '이설' 체크가 꺼져 있거나 조감이면 없음. 키가 붙은 속 요소라 조명을 바꿀 때 떠오르고 옅어짐.
        점선은 그 칸 줄에 유령선을 실제로 그었을 때만(drawn — 띠의 칸을 그리며 적어 둔 this._caltAt: 진짜 경계 · 칸 끝에서 3px 안이라 유령선을 긋지 않는 폭에서는 칠만),
        건국 · 멸망 네모와 그 옆 관문 · 다리 · 문 자리(띠 끝의 역)를 지나면 긋지 않습니다 — 점선은 띠 높이 전체라 네모 · 관문 획을 가로지름 (칠은 그대로, 네모가 위 층) */
    _altSpotsHTML(p, tr, own, X, ox, iw, gr, BW, drawn = null) {
      if (!this.showAlt || this._bird || !own.length) return '';
      const G = this._G(); // 시기 단의 단 간격 — 서고 배치면 14(G_SEOGO)
      let html = '';
      const hs = G.sq / 2;
      const sq = this._squares(p, X, gr.lines);
      const bx1 = sq.x1 - ox;
      const bx2 = sq.x2 - ox;
      const stations = [];
      if (sq.showF) {
        const a = sq.fc - ox - hs;
        const b = sq.fc - ox + hs;
        stations.push(a - bx1 <= GATE_MAX + 1 ? [bx1 - 1, b + SQ_CLEAR] : [a - SQ_CLEAR, b + SQ_CLEAR]); // 띠 끝 자리의 네모면 테두리까지(관문 · 다리 · 문)
      }
      if (sq.showE) {
        const a = sq.ec - ox - hs;
        const b = sq.ec - ox + hs;
        stations.push(bx2 - b <= GATE_MAX + 1 ? [a - SQ_CLEAR, bx2 + 1] : [a - SQ_CLEAR, b + SQ_CLEAR]);
      }
      const clear = x => !stations.some(([a, b]) => x > a - 0.5 && x < b + 0.5);
      const ghost = (cell, x) => (drawn.get(cell) || []).some(v => Math.abs(v - x) < 0.5);
      const rowTop = (kind, c) =>
        kind === 'leader' ? gr.leaderTop - BW : kind === 'cabinet' ? gr.cabinetTop - BW : kind === 'rank' ? gr.rankTop - BW : kind === 'phase' ? gr.phaseTop - BW + Math.max(0, (p.phaseSchemes || []).findIndex(sc => sc.spans.includes(c))) * (G.phase + G.phaseGap) : 0;
      for (const s of own) {
        if (!s.cell) continue;
        const q = s.uid === p.uid ? p : tr.periods.find(x => x.uid === s.uid);
        const [kind, n] = String(s.cell).split(':');
        const c = q ? HT.cellsOf(q, kind)[Number(n)] : null;
        if (!c || !(c.alternatives && c.alternatives.length)) continue;
        const base = cellBaseOf(c, q, s.cell);
        const ph = (((rowTop(kind, c) + 2) % 3) + 3) % 3;
        c.alternatives.forEach((a, j) => {
          if (!HT.altDated(a) || HT.altFlipped(a, base)) return;
          const f = HT.altSpan(a, base);
          const e = f.ongoing ? q.endY : f.end;
          const dl = f.own.start && f.start != null && Math.abs(f.start - base.start) > 1e-9;
          const dr = f.own.end && e != null && Math.abs(e - base.end) > 1e-9;
          if (!dl && !dr) return;
          const a0 = X(dl ? f.start : s.start) - ox;
          const b0 = dr ? X(e) - ox + 1 : X(s.end) - ox;
          const sl = HT.clamp(a0, 0, iw);
          const sr = HT.clamp(b0, 0, iw);
          if (sr - sl <= 0.5) return;
          const own = q === p && drawn; // 칸이 이 띠의 칸 줄에 있음 (숨은 소속의 칸은 상위 띠에 칸 줄이 없어 유령선도 없음 — 점선만)
          const lineL = dl && a0 >= 0 && clear(a0) && (!own || ghost(s.cell, a0));
          const lineR = dr && b0 <= iw && clear(b0 - 1) && (!own || ghost(s.cell, b0 - 1));
          html += `<i class="tl-altspot${sl <= 0 ? ' at-s' : ''}${sr >= iw ? ' at-e' : ''}${lineL ? ' d-l' : ''}${lineR ? ' d-r' : ''}" data-k="as:${esc(s.cell)}:${j}" style="left:${cx(sl)}px;width:${cx(sr - sl)}px;--ph:${ph}px"></i>`;
        });
      }
      return html;
    }

    /** 지도자·내각 칸. 좌표는 띠 안쪽(ox = 띠 안쪽 왼쪽 x, iw = 안쪽 너비) — 띠 가장자리에서 4px 안쪽, 칸끼리는 1px 틈 */
    _cells(list, kind, p, X, ox, iw, top, h, clip = {}) {
      if (!list || !list.length) return '';
      /* 렌즈(설계 7-8 결정 5 A)일 때만 clip에 실려 옴: mini 지위 단과 자리를 맞바꾼 지도자 칸(13px 덧단 · 9.5px 글) · cls 덧붙일 모습(' is-nolens' — 그 주제 자료가 없는 나라의 지도자 칸을 옅게) */
      const lo = clip;
      const mo = `${lo.mini ? ' is-mini' : ''}${lo.cls || ''}`;
      /* 명목(설계 7-8 결정 2 A — 실권 단이 보이는 동안): 실권 칸들과 제 기간의 절반 이상 겹친 지도자 칸은 이름 글만 50%(is-nominal — 칸 · 가문 줄은 그대로). 자료만의 셈(HT.groupStrip의 nominal) */
      const nom = kind === 'leader' && this._groupsOn() ? HT.groupStrip(p).nominal : null;
      /* 가문 줄(칸 위에서 h-3 ~ h-1)이 있는 지도자 칸: 이름 밑 '이설 있음'은 그 줄보다 1px 위까지 (자리가 없으면 상세 창에만) */
      const houseMax = (k, c, hh) => (k === 'leader' && this.show.houses && c.houseId ? hh - 5 : undefined);
      const size = lo.mini ? 9.5 : kind === 'leader' ? 11.5 : 10.5;
      const wt = kind === 'leader' ? 600 : 500;
      const P = G.pad2;
      const seen = list.filter(c => X(c.end ?? p.endY) - ox > P && X(c.start) - ox < iw - P);
      if (seen.length > 1 && (iw - 2 * P) / seen.length < 6) {
        const what = kind === 'leader' ? `지도자 ${seen.length}명` : `내각 ${seen.length}개`;
        const lc = this._litCls(P, Math.max(0, iw - 2 * P)); // 흐리지 않는 조명 구간에 드는 모습 (같은 시기를 타국에도)
        return `<i class="tl-cell k-${kind} is-dense${mo}${lc.cls}" style="left:${P}px;width:${cx(Math.max(0, iw - 2 * P))}px;top:${top}px;height:${h}px${lc.css}" title="${esc(`${what} — 확대하면 칸이 나뉩니다`)}"></i>`;
      }
      let html = '';
      const unks = new Map(); // 칸(strip의 한 칸) → 그 칸의 미정 모습 — 가문 줄이 칸과 함께 옅어지게
      /* 이어지는 칸(같은 왕조에서 앞 칸의 끝 = 다음 칸의 시작)은 틈 없이 하나의 긴 둥근 칸으로 */
      const strip = layoutStrip(list.map((c, i) => ({ c, i })), v => v.c.dynasty || v.c.dynastyAuto || '', v => X(v.c.start) - ox, v => X(v.c.end ?? p.endY) - ox, P, iw - P);
      /* 칸의 이설 · 모호한 칸 (디테일 건의 4): 칸마다 이름표 · 미정 꼬리를 먼저 정하고, 유령 구분선 · 이름표 비킴 · 무늬를 한 번에 (altRowPlan) */
      const cellsOf = strip.map(({ it: { c, i }, l, r, jl, jr, atL, atR }, k) => {
        const w = r - l;
        const text = kind === 'leader' ? HT.leaderLabel(c, this.leaderMode, this.leaderOrdinal) : c.name;
        const full = w >= textWidth(text, size, wt) + 12;
        const narrow = !full && w >= textWidth(text.slice(0, 1), size, wt) + 8; // 좁으면 앞글자만 보이고 …로 줄입니다
        const unk = unkCell(c, k && strip[k - 1].it.c, jl, w, full ? textWidth(text, size, wt) : narrow ? w : null, atL && clip.l, atR && clip.r); // 칸의 미정 (앞글자만 보이는 칸은 꼬리를 아주 짧게)
        return { c, i, l, r, jl, jr, atL, atR, w, text, full, narrow, unk, key: `${kind}:${i}`, base: cellBaseOf(c, p, `${kind}:${i}`), ink: full || narrow ? { text, size, wt, lh: size * 1.2 } : null, fixed: narrow, bl: w < 8 ? 0 : 1, br: w < 8 || jr ? 0 : 1, fade: unkFade(unk, l, r), hasMax: houseMax(kind, c, h) };
      });
      const plan = this._altPlan(p, cellsOf, { X: y => X(y) - ox, lo: X(bandStart(p)) - ox + P, hi: X(bandEnd(p)) - ox - P, h });
      const bor = this.seogo && this._f4Borrow(p.uid, kind); // 과제 9: 빌린 자리의 칸(윗선 점선 · 옅게)
      const pws = this.seogo && kind === 'leader' ? this._f4Powers(p.uid) : [];
      const ousted = c => pws.some(w => (w.start == null || (c.end ?? p.endY) > w.start) && (w.end == null || c.start < w.end));
      cellsOf.forEach((u, k) => {
        const { c, i, l, r, jl, jr, atL, atR, w, text, full, narrow, unk } = u;
        const dx = plan.shift.get(k);
        // 동군연합 이음줄을 그을 수 없는 끝(_planUnions)의 겹고리 표지: 온 이름이 든 칸에서 고리 둘(폭 12) + 2px이 더 들어갈 때만 이름 앞에
        const umark = kind === 'leader' && full && this._uMarks && this._uMarks.has(`${p.uid}|leader:${i}`) && w >= textWidth(text, size, wt) + 12 + 14 ? '<i class="tl-umark" aria-hidden="true"></i>' : '';
        const label = full || narrow ? `${umark}<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(text)}</b>` : '';
        const nominal = !!nom && nom.has(i);
        const tip = `${kind === 'cabinet' ? '내각 ' : ''}${kind === 'leader' ? HT.leaderFull(c) : c.name} · ${cellRange(c, 'end', null, p)}${c.dynasty || c.dynastyAuto ? ` · ${c.dynasty || c.dynastyAuto}` : ''}${c.houseName ? ` · 가문 ${c.houseName}` : ''}${c.note ? ` · ${c.note}` : ''}${nominal ? ' · 명목 — 이 기간의 절반 이상은 실권이 따로(위 실권 단)' : ''}${altTip(c, u.base)}`;
        const spot = this._isSpot(p.uid, `${kind}:${i}`);
        const house = c.houseId ? ` data-house="${esc(c.houseId)}"` : '';
        unks.set(strip[k], unk);
        const lc = this._litCls(l, w, plan.litDim && plan.litDim.has(k));
        const z = plan.zones.get(k);
        html += `<i class="tl-cell k-${kind}${mo}${bor ? ' is-borrowed' : ''}${pws.length && ousted(c) ? ' is-ousted' : ''}${nominal ? ' is-nominal' : ''}${i % 2 ? ' is-alt' : ''}${narrow ? ' is-clip' : ''}${w < 8 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL && clip.l ? ' c-l' : ''}${atR && clip.r ? ' c-r' : ''}${spot ? ' is-spot' : ''}${this._isSame(p.uid, `${kind}:${i}`) ? ' is-same' : ''}${this._isSameSel(p.uid, `${kind}:${i}`) ? ' is-same-sel' : ''}${this._isHouse(c.houseId) ? ' is-house' : kind === 'leader' && this._hDim ? ' is-other-house' : ''}${unk.cls}${lc.cls}${zoneCls(z)}" data-cell="${kind}:${i}"${house} style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${h}px${unk.css}${lc.css}${z ? zoneCss(z, u.bl) : ''}" ${kind === 'leader' ? `title="" aria-label` : 'title'}="${esc(tip)}">${label}</i>`; // 지도자 칸은 성씨 풍선이 설명글을 맡음 (title="" — 띠의 설명글도 겹쳐 뜨지 않게)
      });
      html += this._altMarksHTML(p, cellsOf, plan, { top, h, bottom: kind === 'leader' && this.show.houses ? 4 : 2, vw: iw - 1, gx: ox });
      /* 가문 줄(표시 체크 '가문', 기본 끔): 지도자 칸 아래 테두리 바로 안쪽에 가문 색의 가는 줄 — 같은 가문이 이어지는 동안 하나.
         칸과 별개의 요소라 칸의 올림 · 조명 모습과 부딪히지 않고, 누름은 칸이 받습니다 (빽빽한 칸일 때는 위에서 이미 돌아감) */
      if (kind === 'leader' && this.show.houses)
        for (const u of houseRuns(strip, clip)) {
          /* 칸의 미정: 줄의 바깥 끝(이어 붙지 않은 끝)의 칸이 그쪽이 미정이면 줄도 그 칸과 함께 옅어지며 사라집니다 — 줄은 칸 끝에서 3px 안쪽에서 시작하므로 꼬리도 3px 짧게 (CSS '통합 마무리') */
          const a = !u.first.jl && unks.get(u.first);
          const z = !u.last.jr && unks.get(u.last);
          const fl = a && a.s ? a.f - 3 : 0;
          const fr = z && z.e ? z.f - 3 : 0;
          html += `<i class="tl-houseline${this._isHouse(u.id) ? ' is-house' : ''}${fl > 0 ? ' unk-s' : ''}${fr > 0 ? ' unk-e' : ''}" style="left:${cx(u.l)}px;width:${cx(u.r - u.l)}px;top:${cx(top + h - 3)}px;--hc:${u.color}${fl > 0 ? `;--fl:${cx(fl)}px` : ''}${fr > 0 ? `;--fr:${cx(fr)}px` : ''}"></i>`;
        }
      return html;
    }

    /** (공개) 정권이 지금 그려지는 띠의 uid — 상위 띠 아래 숨은 소속이면 그것이 접혀 든 보이는 상위 띠, 연표에 없으면 null.
        그 소속을 섬긴 인물은 그 상위 띠의 인물 단에 그려지므로, 뷰어가 그 띠 상세의 인물 목록에 함께 모을 때 씁니다 */
    shownBandOf(uid) {
      for (const tr of this.tracks || []) {
        let p = tr.periods.find(q => q.uid === uid);
        if (!p) continue;
        while (p && p._hidden) p = p._host;
        return p ? p.uid : null;
      }
      return null;
    }

    /** 활동 막대가 차지하는 해 [시작, 끝] — 단 배정과 빽빽함이 함께 씁니다. 1년이 안 되는 활동(생년이나 몰년 하나만 적어 그 해 하나로 짐작한 사람,
        한 해 안에 끝난 섬김)은 막대를 그리는 자리(구간의 가운데)를 한가운데로 한 1년으로 칩니다 — 길이가 0인 구간은 무엇과도 겹치지 않는 것으로 셈해져
        같은 해의 두 사람이 한 단에 포개지고, 3px 막대만 있는 띠는 아무리 확대해도 `인물 n명` 한 칸으로 남았습니다 */
    _figSpan(s) {
      if (s.endY - s.start >= 1) return [s.start, s.endY];
      const c = (s.start + s.endY) / 2;
      return [c - 0.5, c + 0.5];
    }

    /** 활동 막대의 양 끝이 미정인지 (칸의 미정 — 모델의 fromUnknown · toUnknown): 막대의 그 끝이 섬긴 구간의 진짜 끝일 때만
        (정권 · 그려지는 띠의 기간에서 잘린 끝은 미정이 아님) → unkCell이 받는 { startUnknown, endUnknown } */
    _figUnk(s, host) {
      return {
        startUnknown: !!s.fromUnknown && Math.abs(Math.max(s.start, bandStart(host)) - s.from) < 1e-9,
        endUnknown: !!s.toUnknown && Math.abs(Math.min(s.endY, bandEnd(host)) - s.to) < 1e-9,
      };
    }

    /** 인물 단의 배치(화면 · 그림 내보내기 공용): 그려지는 띠마다 { host(띠), row, g(그 줄의 geo), vlo · vhi(띠 안쪽의 보이는 범위), bars: [{ x, la, rb, span }], avg(막대 평균 폭 — span의 평균) }.
        막대는 섬긴 구간을 띠의 기간 안으로 자르고 띠 안쪽 4px에 가둡니다 — 아주 짧은 활동도 3px은 보이게. 단에서 넘친 인물(lvl −1) · 접힌 줄 · 화면 밖은 뺍니다.
        평균 폭은 1년이 안 되는 막대를 그 1년의 폭(_figSpan)으로 셉니다 — 억지로 넓힌 3px만 세면 확대해도 늘 6px 아래라서 */
    _figureGroups(tr, X, W) {
      const groups = [];
      if (this.show.figures === false || !(tr.figures || []).length) return groups;
      const byBand = new Map();
      for (const x of tr.figures) {
        if (x.lvl < 0 || x.row == null || !x.band || (tr.hiddenRows && tr.hiddenRows.has(x.row))) continue;
        if (!byBand.has(x.band.uid)) byBand.set(x.band.uid, []);
        byBand.get(x.band.uid).push(x);
      }
      const edge = G.bw + G.pad2;
      for (const list of byBand.values()) {
        const host = list[0].band;
        const row = list[0].row;
        const g = (tr.geos && tr.geos[row]) || tr.geo;
        if (!g.figH) continue;
        const lo = X(bandStart(host)) - (host.startUnknown ? FADE : 0) + edge;
        const hi = X(bandEnd(host)) + (host.endUnknown ? FADE : 0) - edge;
        const vlo = Math.max(lo, 0);
        const vhi = Math.min(hi, W);
        if (vhi - vlo < 3) continue;
        const bars = [];
        for (const x of list) {
          const a = X(Math.max(x.s.start, bandStart(host)));
          const b = X(Math.min(x.s.endY, bandEnd(host)));
          let la = a > lo ? a + 0.5 : lo;
          let rb = b < hi ? b - 0.5 : hi;
          if (rb - la < 3) {
            la = HT.clamp((a + b) / 2 - 1.5, lo, Math.max(lo, hi - 3));
            rb = la + 3;
          }
          if (rb <= vlo || la >= vhi) continue;
          const [s0, s1] = this._figSpan(x.s);
          const short = x.s.endY - x.s.start < 1;
          bars.push({ x, la, rb, span: short ? Math.max(rb - la, X(s1) - X(s0)) : rb - la }); // span = 빽빽함을 잴 폭
        }
        if (bars.length) groups.push({ host, row, g, vlo, vhi, bars, avg: bars.reduce((s, q) => s + q.span, 0) / bars.length });
      }
      return groups;
    }

    /** 인물 단 — 줄마다의 HTML. 기간 막대 아래 · 예속 띠 위에, 기관 칸처럼 **줄 직속 요소**로 그립니다(data-k · data-uid · data-row):
        떠오름(_laneFx) · 상태 유지(KEEP_CLASS) · 올림 강조 · 고름이 저절로 붙고, 고른 것이 있어 흐려진 부모 띠의 흐림을 물려받지 않습니다.
        활동 막대 = 둥근 칸(이름은 들어갈 때만: 전체 → 첫 글자 → 없음 · 중요도 3은 굵게), 그려지는 띠의 안쪽 4px에 가둡니다.
        수명선(생 ~ 몰)은 막대 양옆으로 뻗는 가는 선으로 두고 올리거나 골랐을 때만 보입니다(css) — 기간 막대와 닮은 가는 선이 늘 겹겹이 놓이지 않게.
        빽빽하면(그 띠에서 보이는 막대의 평균 폭 6px 미만 — 문턱은 두 개) 단 전체를 `인물 n명` 한 칸으로. 단(lvl)과 줄(row)은 자료로 정해 둔 것(_layoutTrack) */
    _figureBars(tr, X, W) {
      const G = this._seogoOn() ? this._G() : G_BASE; // 서고: 알약 높이 14 · 틈 2(배치 geoFor의 figure와 같은 값 — 다르면 알약이 띠 아랫변까지 내려옴)
      const out = Array.from({ length: tr.rows }, () => '');
      for (const { host, row, g, vlo, vhi, bars, avg } of this._figureGroups(tr, X, W)) {
        if (tr._drawRows && !tr._drawRows.has(row)) continue;
        const split = bars.length < 2 || this._past(`fig:${tr.id}:${host.uid}`, avg, 6);
        if (!split) {
          /* 한 칸: 누르면 그 띠(정권)의 상세가 열리고 인물 목록으로 갑니다(data-cell="figures") — 글은 들어갈 때만 */
          const label = `인물 ${bars.length}명`;
          const fits = vhi - vlo >= textWidth(label, 10, 500) + 12;
          out[row] += `<i class="tl-fig is-dense" data-k="fd:${esc(host.uid)}" data-uid="${esc(host.uid)}" data-row="${row}" data-cell="figures" style="left:${cx(vlo)}px;width:${cx(vhi - vlo)}px;top:${g.figTop}px;height:${G.figure}px;--c:${host.color}" title="${esc(`${host.name}의 인물 ${bars.length}명 — 확대하면 나뉩니다 (누르면 ${host.name} 상세의 인물 목록)`)}">${fits ? `<b>${esc(label)}</b>` : ''}</i>`;
          continue;
        }
        const byLvl = new Map(); // 단 → 그 단의 막대 (이설의 유령선이 같은 단의 다른 사람 막대를 지나가지 않게)
        for (const q of bars) (byLvl.get(q.x.lvl) || byLvl.set(q.x.lvl, []).get(q.x.lvl)).push(q);
        const edge = G.bw + G.pad2;
        for (const { x, la, rb } of bars) {
          const { f, s } = x;
          const l = Math.max(la, 0);
          const w = Math.min(rb, W) - l;
          if (w < 1) continue;
          const wt = (f.importance || 2) >= 3 ? 700 : 500;
          const fs = this._seogoOn() ? 8.5 : 10, pad = this._seogoOn() ? 8 : 12; // 서고: 알약 글 8.5 · 안 여백 3씩 — 재는 값도 그린 글 크기로
          const whole = w >= textWidth(f.name, fs, wt) + pad;
          const plain = whole ? f.name : !this._seogoOn() && w >= textWidth(f.name.slice(0, 1), fs, wt) + 8 ? f.name.slice(0, 1) : ''; // 서고는 다 들어갈 때만 이름(첫 글자만 남기지 않음 — 설계 4-1)
          const text = esc(plain);
          /* 수명선: 생 ~ 몰 가운데 아는 쪽까지, 그려지는 띠 안쪽 · 화면 안으로 잘라서 (막대 밖으로 2px 넘게 나갈 때만) */
          const ls = HT.clamp(f.birth != null ? X(f.birth) : la, vlo, vhi);
          const le = HT.clamp(f.death != null ? X(f.death) : rb, vlo, vhi);
          /* 막대의 왼쪽(출생 쪽) · 오른쪽(사망 쪽) 두 토막 — 막대 위를 지나가지 않습니다. 좌표는 막대의 테두리 안쪽 기준. 끝이 잘리지 않았을 때만 끝 점(at-b · at-d) */
          const line =
            (ls < l - 2 ? `<i class="ln${ls > vlo ? ' at-b' : ''}" style="left:${cx(ls - l - G.bw)}px;width:${cx(l - ls)}px"></i>` : '') +
            (le > l + w + 2 ? `<i class="ln${le < vhi ? ' at-d' : ''}" style="left:${cx(w - G.bw)}px;width:${cx(le - l - w)}px"></i>` : '');
          const life = HT.figureLife(f);
          const where = s.polity && s.polity !== host ? `${host.name} · ${s.polity.name}` : host.name;
          const tip = `${f.name}${f.role ? ` · ${f.role}` : ''}${s.office ? ` · ${s.office}` : ''} — ${where} (${s.fromUnknown ? '미정' : HT.formatDate(s.from, s.fromAt)} ~ ${f.ongoing && s.to === f.endY ? '현재' : s.toUnknown ? '미정' : HT.formatDate(s.to, s.toAt)})${life ? ` · 생몰 ${life}` : ''}${f.houseName ? ` · 가문 ${f.houseName}` : ''}${s.note ? ` · ${s.note}` : ''}`;
          /* 칸의 미정: 섬긴 기간(또는 물려받은 활동 시기)의 미정인 끝이 막대 안에서 옅어지고 그쪽 테두리가 점선 — 아주 좁은 막대는 그대로 (CSS '지위 변천 · 섬긴 기록의 미정') */
          const tw = !text ? null : textWidth(plain, fs, wt); // 가운데 이름표의 글자 너비 — 꼬리가 글자까지 먹어 들어가지 않게
          const unk = w >= 8 ? unkCell(this._figUnk(s, host), null, false, w, tw, la < 0, rb > W) : { cls: '', css: '' };
          /* 활동 막대의 이설 · 모호한 연대 (디테일 건의 4): 섬긴 기록 줄의 것 + 인물의 활동 시작 · 끝 이설(이 막대의 끝이 곧 활동의 끝일 때 — 비운 쪽은 활동 시기를 물려받음).
             통설 구간은 섬긴 기간(모델의 from · to). 같은 단의 다른 사람 막대는 선이 지나가지 않게 막음(글자처럼 — 그 안이면 이 막대 이름 밑 '이설 있음') */
          const own = { c: figBarCell(f, s), l, r: l + w, key: `fig:${f.uid}:${s.polityUid}:${x.i || 0}`, base: { start: s.from, startAt: s.fromAt, end: s.to, endAt: s.toAt, startUnknown: s.fromUnknown, endUnknown: s.toUnknown }, ink: plain ? { text: plain, size: fs, wt, lh: 10 } : null, bl: w < 8 ? 0 : 1, br: w < 8 ? 0 : 1, fade: unkFade(unk, l, l + w) };
          const others = HT.drawsUncertainty(own.c) ? byLvl.get(x.lvl).filter(q => q.x !== x).map(q => ({ l: q.la, r: q.rb, ink: { text: '·', size: 10, wt: 500 }, fixed: true, c: null })) : []; // 그릴 것이 없는 막대는 같은 단을 훑지 않음
          const frow = [own, ...others];
          const plan = this._altPlan(null, frow, { X, lo: X(bandStart(host)) + edge, hi: X(bandEnd(host)) - edge, h: G.figure, now: f.endY });
          const dx = plan.shift.get(0);
          const z = plan.zones.get(0);
          const marks = this._altMarksHTML(null, frow, plan, { top: -G.bw, h: G.figure, x0: l + G.bw, vw: W, spot: () => this.selected === f.uid });
          /* 생몰의 이설: 수명선 위의 작은 빈 고리(올리거나 골랐을 때만 — 수명선과 함께). 다른 이설 표식처럼 '이설' 체크 · 조감을 따르고, 앞뒤가 뒤집힌 이설은 없음 */
          const lifeAlt = (this.showAlt && !this._bird ? f.alternatives || [] : [])
            .filter(a => !HT.altFlipped(a, figBaseOf(f), FIG_KEYS))
            .flatMap(a => [a.birth, a.death].filter(y => y != null && isFinite(y) && ![f.birth, f.death].includes(y)))
            .map(y => X(y))
            .filter(v => v >= vlo && v <= vhi && (v < l - 3 || v > l + w + 3))
            .map(v => `<i class="lnalt" style="left:${cx(v - l - G.bw)}px"></i>`)
            .join('');
          /* 가문: 모델이 이어 둔 가문 id(linkHouses — 칸과 같은 data-house) · 가문 창이 열린 가문이면 is-house */
          out[row] += `<i class="tl-fig imp-${f.importance || 2}${la < 0 ? ' clip-l' : ''}${rb > W ? ' clip-r' : ''}${w < 8 ? ' is-thin' : ''}${unk.cls}${this._isHouse(f.houseId) ? ' is-house' : ''}${zoneCls(z)}" data-k="f:${esc(f.uid)}:${esc(s.polityUid)}${x.i ? `:${x.i}` : ''}" data-uid="${esc(f.uid)}" data-row="${row}" data-band="${esc(host.uid)}"${f.houseId ? ` data-house="${esc(f.houseId)}"` : ''} style="left:${cx(l)}px;width:${cx(w)}px;top:${g.figTop + x.lvl * (G.figure + G.figGap)}px;height:${G.figure}px;--c:${s.color || host.color}${unk.css}${z ? zoneCss(z, own.bl) : ''}" title="${esc(tip + altTip(own.c, own.base))}">${line}${lifeAlt}${text ? `<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${text}</b>` : ''}${marks}</i>`;
        }
      }
      return out;
    }

    /** 시기 구분(학계) 단: 체계마다 얇은 한 줄(파일에 적은 차례로 위에서 아래 · 최대 G.phaseMax). 좌표는 _cells와 같이 띠 안쪽 기준.
        이어지는 시기는 하나의 긴 둥근 칸 + 가는 구분선, 글은 이름 → 첫 글자 → 없음. 체계가 둘 이상이면 각 줄의 보이는 왼쪽 끝 칸에
        작은 체계 이름표 — 그 칸의 글과 함께 들어갈 때만(아니면 설명글에만). 칸 참조는 펼친 순번(phase:ci — 뷰어의 칸 상세 · 조명 · 검색이 같은 배열) */
    _phaseCells(p, X, ox, iw, top, clip = {}) {
      const G = this._G(); // 서고 배치면 시기 단 14씩 맞붙음(G_SEOGO) — 아니면 예전 값
      const fs = this._seogoOn() ? 8.5 : 9.5; // 칸 글 크기(서고 CSS 8.5)
      const schemes = (p.phaseSchemes || []).slice(0, G.phaseMax);
      const multi = (p.phaseSchemes || []).length > 1;
      const P = G.pad2;
      let html = '';
      schemes.forEach((sc, k) => {
        const y = top + k * (G.phase + G.phaseGap);
        const strip = layoutStrip(sc.spans, () => '', c => X(c.start) - ox, c => X(c.end) - ox, P, iw - P);
        const row = strip.map(({ it: c, l, r, jl, jr, atL, atR }, j) => {
          const w = r - l;
          const tag = multi && j === 0 ? sc.scheme : '';
          const nameW = textWidth(c.name, fs, 500) + 10;
          const withTag = !!tag && w >= textWidth(tag, 8, 600) + 12 + nameW;
          const full = w >= nameW;
          const narrow = !full && w >= textWidth(c.name.slice(0, 1), fs, 500) + 8;
          /* 미정인 경계: 칸의 미정과 같은 모습(unkCell — 그쪽 끝이 옅어지고 점선, 앞 시기의 끝이 미정이면 사이 구분선도 점선) */
          const unk = unkCell(c, j && strip[j - 1].it, jl, w, full ? (withTag ? textWidth(tag, 8, 600) + 12 : 0) + textWidth(c.name, fs, 500) : narrow ? w : null, atL && clip.l, atR && clip.r);
          return { c, l, r, jl, jr, atL, atR, w, tag, withTag, full, narrow, unk, key: `phase:${c.ci}`, base: cellBaseOf(c, p, `phase:${c.ci}`), ink: full || narrow ? { text: c.name, size: fs, wt: 500, lh: 9.5 * 1.2 } : null, fixed: narrow || withTag, litL: withTag ? l + (w < 8 ? 0 : 1) + textWidth(tag, 8, 600) + 12 : null, bl: w < 8 ? 0 : 1, br: w < 8 || jr ? 0 : 1, fade: unkFade(unk, l, r) }; // litL: 딱지(.sch — 글 + 안 여백 6 + 바깥 3) 뒤에서 이름이 가운데 — 조명 경계를 비킬 때 그 자리 안에서 (litShift)
        });
        const plan = this._altPlan(p, row, { X: t => X(t) - ox, lo: X(bandStart(p)) - ox + P, hi: X(bandEnd(p)) - ox - P, h: G.phase });
        row.forEach((u, j) => {
          const { c, l, jl, jr, atL, atR, w, tag, withTag, full, narrow, unk } = u;
          const dx = plan.shift.get(j);
          const label = `${withTag ? `<small class="sch">${esc(tag)}</small>` : ''}${full || narrow ? `<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(c.name)}</b>` : ''}`;
          const tip = `시기 구분(학계)${c.scheme ? ` · ${c.scheme}` : ''} — ${c.name} · ${HT.phaseRangeText(c, p)}${c.guess ? ' (경계 짐작)' : ''}${c.note ? ` · ${c.note}` : ''}${altTip(c, u.base)}`;
          const spot = this._isSpot(p.uid, `phase:${c.ci}`);
          const lc = this._litCls(l, w, plan.litDim && plan.litDim.has(j));
          const z = plan.zones.get(j);
          html += `<i class="tl-cell k-phase${narrow ? ' is-clip' : ''}${withTag ? ' has-sch' : ''}${w < 8 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL && clip.l ? ' c-l' : ''}${atR && clip.r ? ' c-r' : ''}${unk.cls}${spot ? ' is-spot' : ''}${lc.cls}${zoneCls(z)}" data-cell="phase:${c.ci}" style="left:${cx(l)}px;width:${cx(w)}px;top:${y}px;height:${G.phase}px${unk.css}${lc.css}${z ? zoneCss(z, u.bl) : ''}" title="${esc(tip)}">${label}</i>`;
        });
        html += this._altMarksHTML(p, row, plan, { top: y, h: G.phase, cls: ' k-phase', vw: iw - 1, gx: ox });
      });
      return html;
    }

    /** 지위 단: 정권의 지위 구간(p.rankSpans — 끝을 채운 것 · 지도자에게서 끌어낸 것)을 하나의 긴 둥근 칸 + 가는 구분선으로(무리는 늘 하나 — 비는 해가 있을 때만 끊김).
        글은 이름 → 첫 글자 → 없음. 서열이 높을수록 나라 색이 짙게(--mix ← HT.RANK_MIX: 사전 전체의 서열을 네 묶음으로, 서열 밖은 중립) — 같은 지위는 어느 나라에서나 같은 짙기.
        번갈아 짙기(is-alt)는 쓰지 않고, 승격▲ · 격하▼는 연표에 두지 않습니다(상세의 목록에서만). 칸 참조는 순번(rank:i — 뷰어의 칸 상세 · 조명 · 검색이 같은 배열) */
    _rankCells(p, X, ox, iw, top, clip = {}) {
      const G = this._G(); // 서고 배치면 지위 단 14(G_SEOGO)
      const P = G.pad2;
      /* clip.lens — 체제 렌즈를 지위 변천으로 대신할 때(설계 7-8 결정 5 A): 지도자 칸 자리(높이 clip.h · 글 11.5px)에 그림 — 칸 · 이음 · 짙기 규칙은 그대로 */
      const lo = clip;
      const H = lo.lens ? lo.h : G.rank;
      const fs = lo.lens ? 11.5 : this._seogoOn() ? 8.5 : 9.5;
      let html = '';
      const strip = layoutStrip(p.rankSpans || [], () => 0, c => X(c.start) - ox, c => X(c.end) - ox, P, iw - P);
      const row = strip.map(({ it: c, l, r, jl, jr, atL, atR }, j) => {
        const w = r - l;
        const first = c.name.slice(0, 1);
        /* 글이 들 자리 = 글자 + 글의 안쪽 여백 3px × 2 + 칸 테두리 1px × 2 — 첫 글자도 이만큼 있어야 '…'이나 반쯤 잘린 글자가 되지 않습니다 */
        const text = w >= textWidth(c.name, fs, 600) + 10 ? c.name : w >= textWidth(first, fs, 600) + 8 ? first : '';
        /* 칸의 미정: 다른 미정 칸과 같은 모습(unkCell — 그쪽 끝이 칸 안에서 옅어지고 점선, 앞 지위의 끝이 미정이면 사이 구분선도 점선) */
        const unk = unkCell(c, j && strip[j - 1].it, jl, w, text ? textWidth(text, fs, 600) : null, atL && clip.l, atR && clip.r);
        return { c, l, r, jl, jr, atL, atR, w, text, unk, key: `rank:${c.i}`, base: cellBaseOf(c, p, `rank:${c.i}`), ink: text ? { text, size: fs, wt: 600, lh: fs * 1.2 } : null, bl: w < 8 ? 0 : 1, br: w < 8 || jr ? 0 : 1, fade: unkFade(unk, l, r) };
      });
      const plan = this._altPlan(p, row, { X: t => X(t) - ox, lo: X(bandStart(p)) - ox + P, hi: X(bandEnd(p)) - ox - P, h: H });
      row.forEach((u, j) => {
        const { c, l, jl, jr, atL, atR, w, text, unk } = u;
        const tip = `지위 — ${HT.rankFull(c)} · ${HT.rankTierText(c)} · ${cellRange(c, 'end', null, p)}${c.derived ? ' (지도자에게 적힌 지위에서 끌어냄)' : ''}${c.note ? ` · ${c.note}` : ''}${altTip(c, u.base)}`;
        const spot = this._isSpot(p.uid, `rank:${c.i}`);
        const lv = c.level || 0;
        const lc = this._litCls(l, w, plan.litDim && plan.litDim.has(j));
        const z = plan.zones.get(j);
        const dx = plan.shift.get(j);
        html += `<i class="tl-cell k-rank rk-${lv}${lo.lens ? ' in-lens' : ''}${w < 8 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL && clip.l ? ' c-l' : ''}${atR && clip.r ? ' c-r' : ''}${unk.cls}${spot ? ' is-spot' : ''}${lc.cls}${zoneCls(z)}" data-cell="rank:${c.i}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${H}px;--mix:${HT.RANK_MIX[lv]}%${unk.css}${lc.css}${z ? zoneCss(z, u.bl) : ''}" title="${esc(tip)}">${text ? `<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(text)}</b>` : ''}</i>`;
      });
      html += this._altMarksHTML(p, row, plan, { top, h: H, vw: iw - 1, gx: ox });
      return html;
    }

    /** 렌즈 한 줄(설계 7-8 결정 5 A — 지도자 칸 자리 · 줄 높이 그대로): L = HT.lensCellsOf(p, 주제). 제도 · 붕당 칸은 _lensCells, 체제를 대신한 지위 변천은 지위 칸을 이 자리에,
        그 주제 자료가 없는 나라는 지도자 칸을 옅게 남김(비우지 않음 — 표시 체크 '지도자'를 끈 동안은 빈 채) */
    _lensRow(p, L, X, ox, iw, top, h, clip) {
      if (L.src === 'rank') return this._rankCells(p, X, ox, iw, top, Object.assign({}, clip, { lens: true, h }));
      if (L.src === 'group') return this._groupCells(p, L.cells, X, ox, iw, top, h, Object.assign({}, clip, { lens: true })); // 붕당 = 집권 단의 칸을 지도자 자리에(집권 단 자리에는 지도자 칸이 작게 — _groupRows의 맞바꿈)
      if (!L.src) return this.show.leaders ? this._cells(p.leaders, 'leader', p, X, ox, iw, top, h, Object.assign({}, clip, { cls: ' is-nolens' })) : '';
      return this._lensCells(p, L, X, ox, iw, top, h, clip);
    }

    /** 렌즈 칸: 지도자 칸과 같은 자리 · 크기 · 글(11.5px) — 갈래 색 칠 + 그 색의 테두리 · 짙은 글(감독 원칙: 띠 위에서는 글 딱지 대신 테두리 · 모양 · 색).
        이어지는 칸은 하나의 긴 둥근 칸 + 구분선(시기 · 지위 칸과 같은 이음), 빈 구간은 빈 채. 이름은 온 이름 → 앞글자만 보이게 자름(지도자 칸 규칙) → 없음.
        붕당의 연정 칸(같은 때 단체 둘 이상)은 위아래 두 색(첫째 · 둘째 단체) · 이름은 '이름 · 이름' → 첫 글자 '새·노' → 없음(한 단체의 집권으로 읽히지 않게 자르지 않음).
        누르면 그 제도 · 단체의 창(data-uid), 같은 갈래에 올리면 메아리(_lensEcho — data-fam) */
    _lensCells(p, L, X, ox, iw, top, h, clip = {}) {
      const P = G.pad2;
      const size = 11.5;
      const wt = 600;
      const lens = this.themeLens;
      let html = '';
      const strip = layoutStrip(L.cells, () => 0, c => X(c.start) - ox, c => X(c.end) - ox, P, iw - P);
      const row = strip.map(({ it: c, l, r, jl, jr, atL, atR }, j) => {
        const w = r - l;
        const many = (c.n || 1) > 1;
        const fits = t => !!t && w >= textWidth(t, size, wt) + 12;
        const text = fits(c.name) ? c.name : many && fits(c.short) ? c.short : '';
        const narrow = !text && !many && w >= textWidth(c.name.slice(0, 1), size, wt) + 8; // 좁으면 앞글자만 보이게 자름 (지도자 칸과 같은 is-clip)
        const shown = text || (narrow ? c.name : '');
        const unk = unkCell(c, j && strip[j - 1].it, jl, w, text ? textWidth(text, size, wt) : narrow ? w : null, atL && clip.l, atR && clip.r);
        return { c, l, r, jl, jr, atL, atR, w, text: shown, narrow, unk, key: `lens:${j}`, base: null, ink: shown ? { text: shown, size, wt, lh: size * 1.2 } : null, fixed: narrow, bl: w < 8 ? 0 : 1, br: w < 8 || jr ? 0 : 1, fade: unkFade(unk, l, r) };
      });
      const plan = this._altPlan(p, row, { X: t => X(t) - ox, lo: X(bandStart(p)) - ox + P, hi: X(bandEnd(p)) - ox - P, h });
      row.forEach((u, j) => {
        const { c, l, jl, jr, atL, atR, w, text, narrow, unk } = u;
        const dx = plan.shift.get(j);
        const what = L.src === 'group' ? (c.n > 1 ? `${lens.name} — 연정 ${c.n}` : lens.name) : `${lens.name}${c.fam ? ` · 갈래 ${c.fam}` : ''}`;
        const tip = `${what} — ${c.name} · ${HT.formatYear(c.start)} ~ ${HT.formatYear(c.end)}${c.note ? ` · ${c.note}` : ''} — 누르면 ${L.src === 'group' ? '단체' : '제도'} 창`;
        const lc = this._litCls(l, w, plan.litDim && plan.litDim.has(j));
        const z = plan.zones.get(j);
        const two = c.color2 ? `;--c2:${c.color2}` : '';
        html += `<i class="tl-cell k-lens${two ? ' is-two' : ''}${narrow ? ' is-clip' : ''}${w < 8 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL && clip.l ? ' c-l' : ''}${atR && clip.r ? ' c-r' : ''}${c.famKey && c.famKey === this._echoFam ? ' is-fam' : ''}${unk.cls}${lc.cls}${zoneCls(z)}" data-uid="${esc(c.uid)}" data-row="${p._row}"${c.famKey ? ` data-fam="${esc(c.famKey)}"` : ''} style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${h}px;--c:${c.color}${two}${unk.css}${lc.css}${z ? zoneCss(z, u.bl) : ''}" title="${esc(tip)}">${text ? `<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(text)}</b>` : ''}</i>`;
      });
      html += this._altMarksHTML(p, row, plan, { top, h, vw: iw - 1, gx: ox, color: u => u.c.color });
      return html;
    }

    /** 단체 단 · 명목 · 연합 표시가 보이는 때: 표시 체크 '단체'가 켜져 있고(show.groups — 내보내기의 연표처럼 그 열쇠가 없으면 끔) 띠 안 덧단을 그리는 밀도(넉넉 · 자동 — 빽빽 · 조감은 숨음) */
    _groupsOn() {
      return !!(this.show && this.show.groups) && this.density <= 0 && !this._bird;
    }

    /** 단체 단 두 줄(설계 7-8 결정 1 A · 2 A + 덧판): 위 = 집권(gr.powerTop) · 아래 = 실권(gr.realTop — 명목 지도자 칸과 맞닿음). 그 줄에 단이 있어도 이 정권에 칸이 없으면 빈 채.
        붕당 렌즈(lensL.src 'group')는 맞바꿈 — 집권 칸은 지도자 자리(_lensRow → _groupCells 20px)로, 이 집권 줄 자리에는 지도자 칸을 작게(지위 맞바꿈과 같은 꼴 · 13px · 9.5px 글) */
    _groupRows(p, X, ox, iw, gr, BW, clip, lensL) {
      const G = this._G(); // 서고 배치면 단체 단 14(G_SEOGO)
      const S = HT.groupStrip(p);
      let html = '';
      if (gr.powerH) {
        if (lensL && lensL.src === 'group') {
          if (this.show.leaders) html += this._cells(p.leaders, 'leader', p, X, ox, iw, gr.powerTop - BW, gr.powerH, Object.assign({}, clip, { mini: true })); // 층 높이(서고 14 · 옛 화면은 G.power 그대로)
        } else if (S.power.length) html += this._groupCells(p, S.power, X, ox, iw, gr.powerTop - BW, gr.powerH, clip);
      }
      if (gr.realH && S.real.length) html += this._groupCells(p, S.real, X, ox, iw, gr.realTop - BW, gr.realH, clip);
      return html;
    }

    /** 단체 칸 한 줄(집권 · 실권 · 붕당 렌즈 — 덧판 x1 A · x3 C, 감독 원칙 "단어로 구분하지 말 것": '집권' · '연정' · '실권' 딱지 글 없이 칠 · 테두리 · 점으로).
        cells = HT.groupStrip의 칸(또는 붕당 렌즈 칸 — 같은 셈). 이어지는 칸은 하나의 긴 둥근 칸 + 구분선(시기 · 지위 칸과 같은 이음), 빈 구간은 빈 채.
        · 집권 칸 = 단체 색 40% + 그 색의 테두리 · 글은 그 색 30% 섞은 먹 — 이름 → 첫 글자 → 없음(잘린 글자 없음)
        · 실권 칸(is-real) = 단체 색 78% · 테두리는 그 색 64% + 먹(짙은 선) · 글은 먹빛(그 색 10%)
        · 연정 칸(is-two — 같은 때 단체 둘 이상) = 위아래 두 색(첫째 · 둘째 단체 42%) + 단체 수만큼 색 점(6px · 단체 전부의 색) — 줄임 ① 점 + 이름들 → ② 점 + 첫 글자들 → ③ 점만 → ④ 두 색 칠만
        · 짝을 모르는 연정(is-solo — 칸 이름만 연정) = 위 반 제 색 · 아래 반 종이빛 + 점 하나
        clip.lens(붕당 렌즈 — 지도자 자리 20px · 11.5px 글)면 k-lens도 붙음(렌즈 칸과 같은 누름 · 메아리 · 그림 내보내기). 누르면 단체 창(data-uid = 첫 단체), data-groups = 단체 전부(계보 창의 setGroupFocus) */
    _groupCells(p, cells, X, ox, iw, top, h, clip = {}) {
      const P = G.pad2;
      const lens = !!clip.lens;
      const size = lens ? 11.5 : 8.5; // 단체 단의 글은 8.5px(감독 선택 2026-10-13 "글자 한 단계 작게" — 통합에서 칸 높이는 20px로 넓힘)
      const wt = 600;
      const pad = lens ? 12 : 10; // 글이 들 자리 = 글자 + 안 여백 + 테두리 (지도자 칸 12 · 지위 칸 10과 같은 셈)
      const DOT = 9; // 점 6px + 점 사이 3px
      const gf = this._groupFocus || null;
      let html = '';
      const strip = layoutStrip(cells, () => 0, c => X(c.start) - ox, c => X(c.end) - ox, P, iw - P);
      const row = strip.map(({ it: c, l, r, jl, jr, atL, atR }, j) => {
        const w = r - l;
        const nd = c.solo ? 1 : c.n > 1 ? c.n : 0; // 점 수 = 함께 집권한 단체 수
        const dw = nd ? nd * DOT + 3 : 0;
        const fits = t => !!t && w >= dw + textWidth(t, size, wt) + pad;
        const first = [...c.name][0] || '';
        const text = nd ? (fits(c.name) ? c.name : c.n > 1 && fits(c.short) ? c.short : c.solo && fits(first) ? first : '') : fits(c.name) ? c.name : w >= textWidth(first, size, wt) + 8 ? first : '';
        const dots = nd > 0 && (!!text || w >= dw + 6); // 점이 칸에 다 들어갈 때만(일부만 보이면 단체 수를 잘못 읽음) — 아니면 칠만
        const unk = unkCell(c, j && strip[j - 1].it, jl, w, text ? textWidth(text, size, wt) + (dots ? dw : 0) : dots ? dw : null, atL && clip.l, atR && clip.r);
        return { c, l, r, jl, jr, atL, atR, w, text, dots, unk, key: `grp:${j}`, base: null, ink: text ? { text, size, wt, lh: size * 1.2, c: dots ? l + (w + dw) / 2 : undefined } : null, fixed: !!text && text !== c.name, bl: w < 8 ? 0 : 1, br: w < 8 || jr ? 0 : 1, fade: unkFade(unk, l, r) };
      });
      const plan = this._altPlan(p, row, { X: t => X(t) - ox, lo: X(bandStart(p)) - ox + P, hi: X(bandEnd(p)) - ox - P, h });
      row.forEach((u, j) => {
        const { c, l, jl, jr, atL, atR, w, text, dots, unk } = u;
        const dx = plan.shift.get(j);
        const what = c.real ? '실권' : c.n > 1 ? `연정 ${c.n}` : c.solo ? '연정(함께한 단체는 자료에 없음)' : '집권';
        const tip = `${what} — ${c.name} · ${HT.formatYear(c.start)} ~ ${HT.formatYear(c.end)}${c.note ? ` · ${c.note}` : ''}${c.real ? ' — 이 기간의 지도자는 명목(이름 옅게 — 제 기간의 절반 이상)' : ''} — 누르면 단체 창`;
        const lc = this._litCls(l, w, plan.litDim && plan.litDim.has(j));
        const z = plan.zones.get(j);
        const dotHtml = dots ? (c.solo ? [c.color] : c.colors).map(cc => `<i class="gd" style="--dc:${cc}"></i>`).join('') : '';
        html += `<i class="tl-cell k-group${lens ? ' k-lens' : ''}${c.real ? ' is-real' : ''}${c.n > 1 ? ' is-two' : ''}${c.solo ? ' is-solo' : ''}${w < 8 ? ' is-thin' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${atL && clip.l ? ' c-l' : ''}${atR && clip.r ? ' c-r' : ''}${gf && c.uids.includes(gf) ? ' is-gf' : ''}${unk.cls}${lc.cls}${zoneCls(z)}" data-uid="${esc(c.uid)}" data-row="${p._row}" data-groups="${esc(c.uids.join(' '))}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${h}px;--c:${c.color}${c.color2 ? `;--c2:${c.color2}` : ''}${unk.css}${lc.css}${z ? zoneCss(z, u.bl) : ''}" title="${esc(tip)}">${dotHtml}${text ? `<b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(text)}</b>` : ''}</i>`;
      });
      html += this._altMarksHTML(p, row, plan, { top, h, vw: iw - 1, gx: ox, color: u => u.c.color });
      return html;
    }

    /** 연합 표시의 올림 조명 자리(설계 7-8 결정 3 C): 이 띠가 연합의 구성 나라면 가담 기간마다 띠 안 칠 하나(평소 숨음 — 겹 탭에 올리면 _coalHover가 켬) */
    _coalLitHTML(p, X, ox, iw) {
      if (!this.show.groups || this._bird) return '';
      let html = '';
      for (const c of HT.coalitionsOf(p)) {
        const a = HT.clamp(X(c.start) - ox, 0, iw);
        const b = HT.clamp(X(c.end) - ox, 0, iw);
        if (b - a < 0.5) continue;
        html += `<i class="tl-coal-lit${this._coalHot === c.group.uid ? ' is-coal-on' : ''}${a <= 0 ? ' at-s' : ''}${b >= iw ? ' at-e' : ''}" data-coal="${esc(c.group.uid)}" style="left:${cx(a)}px;width:${cx(b - a)}px;--kc:${c.group.color}"></i>`;
      }
      return html;
    }

    _finishEventPan() {
      for (const tr of this.tracks) {
        if (!tr._eventScene) continue;
        for (const lane of tr.laneEls || []) {
          const layer = lane.querySelector(':scope > .tl-pan-events');
          if (!layer) continue;
          const dx = layer._panX || 0;
          for (const el of [...layer.children]) {
            el.style.left = `${cx((parseFloat(el.style.left) || 0) + dx)}px`;
            el.removeAttribute('data-ink');
            lane.insertBefore(el, layer); // 이전 화면에 쓰일 가장자리 가림은 유지하고, 다음 그리기에서 새 글 모양으로 바꿉니다.
          }
          layer.remove();
          lane._html = null;
        }
        tr._eventScene = null;
        tr._eventReuse = false;
      }
    }

    /* 드래그 그림은 보이는 폭보다 좌우로 넓게 준비합니다. 같은 배율에서는 그 그림의 위치만
       바꾸고, 새 구간·줄·선택이 들어오면 다시 채웁니다. 정착·확대·밀도 전환은 원래 배치로
       돌아가므로 파일 내보내기와 메이커도 같은 상세 연표를 사용합니다. */
    _releaseTrackScene(tr) {
      const scene = tr._panScene;
      if (!scene) return;
      for (const el of scene.layers) {
        el.style.removeProperty('transform'); el.classList.remove('tl-pan-scene');
        if (el.classList.contains('tl-lane')) el.style.removeProperty('width');
        if (el instanceof SVGElement) { el.removeAttribute('viewBox'); el.style.removeProperty('top'); el.style.removeProperty('height'); el.style.removeProperty('overflow'); }
      }
      for (const ink of scene.ink) ink.el.classList.remove('is-pan-cut');
      for (const lane of tr.laneEls) lane._html = null;
      tr._lab = scene.memory.lab; tr._clu = scene.memory.clu; tr._bnm = scene.memory.bnm;
      tr._eventScene = null; tr._panScene = null; tr._sceneReleased = true;
    }

    _drawTrackScene(tr, X, W) {
      const scale = W / this.span(), start = this.view.start;
      const key = `${this._paintRevision || 0}|${W}|${tr._hiddenSig}|${tr.rowTop.join(',')}`;
      const covers = rows => !tr._neededRows || rows && [...tr._neededRows].every(r => rows.has(r));
      const still = tr._stillScene;
      if (this._handHeld() && !this._sceneDisabled && !this._loopOn && !tr._panScene && still && still.key === key && still.start === start && Math.abs(still.scale / scale - 1) < 1e-10 && covers(still.rows)) return;
      const allowed = !this._sceneDisabled && !this._bird && this._handHeld() && (tr._panScene || this._drawn && Math.abs(this._drawn.start - start) > 1e-10) && !this._loopOn && !tr._squash && !tr._gather && !tr._was && this._drawn && Math.abs(this._drawn.k / scale - 1) < 1e-10;
      if (!allowed) {
        this._releaseTrackScene(tr); this._drawTrack(tr, X, W);
        tr._stillScene = { key, start, scale, rows: tr._drawRows ? new Set(tr._drawRows) : null };
        return;
      }
      let scene = tr._panScene;
      let shift = scene ? (scene.start - start) * scale : 0;
      if (!scene || scene.key !== key || !covers(scene.rows) || Math.abs(scene.scale / scale - 1) > 1e-10 || Math.abs(shift) > scene.pad * .6) {
        this._releaseTrackScene(tr);
        this._finishEventPan();
        const pad = Math.min(320, W * .25), width = W + pad * 2;
        const saved = { view: this.view, W: this.W, drawn: this._drawn, grid: this._gridX };
        const memory = { lab: tr._lab, clu: tr._clu, bnm: tr._bnm };
        const left = start - pad / scale;
        this._sceneRendering = true;
        try {
          this.view = { start: left, end: left + width / scale };
          this.W = width; this._drawn = null; this._gridX = saved.grid.map(x => x + pad);
          this._drawTrack(tr, year => (year - left) * scale, width);
        } finally {
          this.view = saved.view; this.W = saved.W; this._drawn = saved.drawn; this._gridX = saved.grid;
          this._sceneRendering = false;
        }
        scene = tr._panScene = { key, start, scale, pad, memory, rows: tr._drawRows ? new Set(tr._drawRows) : null, layers: [...tr.lanesEl.children], ink: [], tabs: [], htabs: new Map() };
        for (const el of scene.layers) {
          if (el.classList.contains('tl-lane')) el.style.width = `${width}px`;
          el.classList.add('tl-pan-scene'); el.style.transform = `translate3d(${-pad}px,0,0)`;
        }
        /* 글자를 반쯤 자르지 않도록 실제 글 범위를 한 번만 읽습니다. 이동 중에는 저장한
           좌표로만 판단하며 브라우저에 너비·자리를 다시 묻지 않습니다. */
        const origin = tr.lanesEl.getBoundingClientRect().left;
        const targets = new Set();
        const walk = document.createTreeWalker(tr.lanesEl, NodeFilter.SHOW_TEXT);
        while (walk.nextNode()) {
          const text = walk.currentNode, el = text.parentElement;
          if (!text.textContent.trim() || !el || el instanceof SVGElement || el.closest('.tl-tab, .tl-htab')) continue;
          targets.add(el);
        }
        for (const el of targets) {
          const range = document.createRange(); range.selectNodeContents(el);
          const box = range.getBoundingClientRect();
          if (box.width) scene.ink.push({ el, lo: box.left - origin + pad, hi: box.right - origin + pad });
        }
        for (const el of tr.lanesEl.querySelectorAll('.tl-tab')) {
          const p = tr.periods.find(p => p.uid === el.dataset.uid);
          if (p) scene.tabs.push({ el, p, width: el.getBoundingClientRect().width });
        }
        /* 뒤 장의 탭(묶음 3 · 1번 — 상국 탭과 연합의 겹 탭): 띠마다 모아 두고 끄는 동안 _backTabPlan으로 다시 자리를 잡음 — 화면 가장자리에 붙는 제 이름 탭을 따라 비키고, 자리가 없으면 숨김.
           탭은 data-k(상국 'ht:띠:순번' · 연합 'ct:띠:단체')로 찾음 */
        for (const el of tr.lanesEl.querySelectorAll('.tl-htab')) {
          const p = tr.periods.find(p => p.uid === el.dataset.band);
          if (!p) continue;
          if (!scene.htabs.has(p)) scene.htabs.set(p, []);
          scene.htabs.get(p).push({ el, k: el.dataset.k });
        }
        shift = 0;
      }
      const offset = shift - scene.pad;
      for (const el of scene.layers) {
        el.style.transform = `translate3d(${cx(offset)}px,0,0)`;
        if (el instanceof SVGElement && tr._paintClip) {
          const { top, height } = tr._paintClip;
          const box = `0 ${top} ${W + scene.pad * 2} ${height}`;
          if (el.getAttribute('viewBox') !== box) {
            el.setAttribute('viewBox', box); el.style.top = `${top}px`; el.style.height = `${height}px`; el.style.overflow = 'hidden';
          }
        }
      }
      for (const { el, lo, hi } of scene.ink) el.classList.toggle('is-pan-cut', lo + offset < 0 || hi + offset > W);
      const tabEnds = new Map();
      for (const { el, p, width } of scene.tabs) {
        const left = X(bandStart(p)) - (p.startUnknown ? FADE : 0);
        const right = X(bandEnd(p)) + (p.endUnknown ? FADE : 0);
        const at = tagNameAt(p, X, left) - TAG.pad; // 한 장 꼬리표의 이름 글: 구멍 뒤 · 화면 왼쪽 밖이면 가장자리 6px(_drawTrack과 같게 — 서고 모양 2단 나-1)
        el.style.left = `${cx(at - offset)}px`;
        el.classList.toggle('is-stuck', left < -1);
        el.classList.toggle('is-pan-cut', at + width - TAG.pad > Math.min(W, (p.endUnknown ? X(p.endY) : right) - TAG.nameRight) - 2 || at + TAG.pad < 0);
        tabEnds.set(p.uid, at + width + TAB.gap);
      }
      for (const [p, list] of scene.htabs) {
        const left = X(bandStart(p)) - (p.startUnknown ? FADE : 0);
        const right = X(bandEnd(p)) + (p.endUnknown ? FADE : 0);
        const tabR = p.endUnknown ? Math.min(X(p.endY), W) - 6 : Math.min(right - G.radius, W - 6);
        const byK = new Map(this._backTabPlan(p, X, W, left, tabEnds.get(p.uid) ?? Math.max(left + G.radius, 6), tabR).map(q => [q.key, q]));
        for (const { el, k } of list) {
          const q = byK.get(k);
          el.style.visibility = q ? '' : 'hidden';
          if (q) el.style.left = `${cx(q.x - offset)}px`;
        }
      }
      this._drawTrackLabels(tr, X, W);
    }

    _drawTrack(tr, X, W) {
      const drawRow = r => !tr._drawRows || tr._drawRows.has(r);
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      const g = tr.geo;
      const geoOf = r => (tr.geos && tr.geos[r]) || g; // 줄마다 글줄 수가 다를 수 있음 (분류별 글줄)
      const inTrackDraw = (t, uid) => t.periods.find(q => q.uid === uid) || null;
      const rows = Array.from({ length: tr.rows }, () => '');
      const reserved = Array.from({ length: tr.rows }, (_, r) => Array.from({ length: geoOf(r).lines }, () => [])); // 줄 → 글줄별 차지한 구간
      const noDot = Array.from({ length: tr.rows }, () => []); // 줄 → 점을 둘 수 없는 구간 [시작, 끝, 밀어낼 쪽] (글줄이 하나일 때)
      const bandBounds = new Map();
      tr._litX = new Map(); // 띠마다 흐리지 않는 조명 구간(같은 시기를 타국에도 — has-lit)의 줄 좌표 — 그 안의 승계 이음매(다리 · 문)는 띠와 같이 흐리지 않음 (_drawLinks)
      const bird = this._bird; // 조감이면 그 값 묶음 (띠 하나뿐인 줄 — 띠 안 이름 · 점 · 알약)
      const bnm = Array.from({ length: tr.rows }, () => []); // 조감: 줄 → 띠 안 이름 · 단추가 차지한 구간(둘레 BIRD_NAME.clear 포함) — 점 · 알약을 두지 않음 (옮기지 않고 숨김 — 자리는 자료가 정함)
      const bnMemo = new Map(); // 조감: 띠 안 이름의 모양(온 이름 · 첫 글자 · 없음)의 기억 — 문턱은 두 개 (_birdName)

      const expanded = new Set();
      const newWide = new Set(); // 넓어서 펼쳐진 묶음 사건 — 한 번 펼쳐지면 8% 더 좁아져야 다시 접힙니다 (문턱은 두 개)
      const selParent = this.selected ? (tr.eventByUid.get(this.selected) || {}).parentUid : null;
      for (const e of tr.eventParents) {
        if (!e.children || !e.children.length) continue;
        const wide = X(e.endY) - X(e.start) >= (tr._wide && tr._wide.has(e.uid) ? 90 * (1 - LOD_GAP) : 90);
        if (wide) newWide.add(e.uid);
        const hit = this.hiLayout && e.children.some(c => this.hiLayout.has(c.uid));
        if (wide || hit || e.uid === this.selected || e.uid === selParent) expanded.add(e.uid);
      }

      /* 접힌 민족 줄: 가는 막대만 */
      /* 접힌 민족 줄: 가는 막대만 · 서고의 닫힌 폴더(접힌 대범위 가지)는 몸통 윗변에 실로 매단 작은 꼬리표(새 앱 scopes.dart _closedTags) */
      for (const r of tr.foldedRows) if (drawRow(r)) rows[r] += this._seogoOn() && tr.groups.some(gp => gp.first === r && gp.folded && gp.scope) ? this._stagsHTML((tr.rowPeriods[r] || []).filter(p => !p._overlay && !p._under), X, W, 4, 20, ` data-row="${r}"`) : this._miniBars(tr.rowPeriods[r] || [], X, W, ` data-row="${r}"`, '_laneRow', G.foldedGroup);

      /* 바탕 문화: 승계국 줄 밑에 깔리는 옅은 무늬 띠 (띠보다 먼저 그려 뒤에 놓입니다). 조감에는 없음 — 바탕 문화 단이 0이고, 그 사건 점도 그리지 않음 (_placeRow) */
      for (const p of bird ? [] : tr.underlays || []) {
        const x1 = X(bandStart(p));
        const x2 = X(bandEnd(p));
        bandBounds.set(p.uid, [x1, x2]);
        if (x2 < -2 || x1 > W + 2) continue;
        const left = Math.max(x1, -1);
        const width = Math.max(3, Math.min(x2, W + 1) - left);
        const clip = `${x1 < -1 ? ' clip-l' : ''}${x2 > W + 1 ? ' clip-r' : ''}`;
        const tip = `${p.name} · 문화 (${HT.formatRange(p)}) — ${(p.successors || []).map(e => e.to.name).join(', ')}의 바탕`;
        const fits = width >= textWidth(p.name, 11) + 24;
        for (const r of p._underRows) {
          if (!drawRow(r) || (tr.hiddenRows && tr.hiddenRows.has(r))) continue;
          rows[r] += `<div class="tl-under${clip}" data-k="u:${esc(p.uid)}" data-uid="${esc(p.uid)}" data-row="${r}" title="${esc(tip)}" style="left:${cx(left)}px;width:${cx(width)}px;--c:${p.color}">${
            fits && r === p._underRows[0] ? `<span class="tl-under-name">${esc(p.name)}<small>문화</small></span>` : ''
          }</div>`;
        }
      }

      /* 기관: 얹히는 시대 띠의 기간 안에서만.
         · 기관(통감부·총독부 — 내정을 직접 간섭한 기관): 띠 안 맨 아래의 기관 칸에(기간 막대·예속 띠 아래), 띠 안쪽 4px에 가둬서
         · 구역(조계지·조차지): 시대 띠 아래로 살짝 내려오는 작은 탭으로 (연맹의 구성국처럼) */
      const overlayHtml = Array.from({ length: tr.rows }, () => '');
      for (const p of tr.overlays || []) {
        const zone = p.scale === 'zone';
        for (const h of bird ? [] : p.hosts) { // 조감에는 기관 칸 · 구역 탭이 없음 (띠의 자리만 — 그 사건 점은 띠 안에)
          let host = inTrackDraw(tr, h.host.uid);
          while (host && host._hidden) host = host._host;
          if (!host || host._row == null || !drawRow(host._row) || tr.foldedRows.has(host._row) || tr.hiddenRows.has(host._row)) continue;
          const a = X(Math.max(bandStart(p), h.start ?? -Infinity, bandStart(host)));
          const b = X(Math.min(bandEnd(p), h.end ?? Infinity, bandEnd(host)));
          if (b - a < 1 || b < -2 || a > W + 2) continue;
          /* 얹히는 띠의 가장자리 안쪽으로: 기관은 4px, 구역 탭은 둥근 모서리 아래를 피해 10px */
          const hb0 = X(bandStart(host)) - (host.startUnknown ? FADE : 0);
          const hb1 = X(bandEnd(host)) + (host.endUnknown ? FADE : 0);
          const edge = zone ? 10 : G.bw + G.pad2;
          const la = a > hb0 + edge ? a + 0.5 : hb0 + edge;
          const rb = b < hb1 - edge ? b - 0.5 : hb1 - edge;
          const l = Math.max(la, 0);
          const w = Math.min(rb, W) - l;
          if (w < 2) continue;
          const row = host._row;
          let top;
          let height;
          if (zone) {
            const bandH = (tr.rowHs[row] ?? tr.rowH) - ((tr.rowCut && tr.rowCut[row]) || 0);
            const lane = p._zoneLane[h.host.uid] ?? 0;
            top = bandH + G.zoneGap + (tr.hangRowLanes.get(row) || 0) * HANG.pitch + lane * (G.zoneTab + G.zoneGap); // 띠에 바로 붙어 매달린 속국 이름표 줄 아래에
            height = G.zoneTab;
          } else {
            top = geoOf(row).organTop;
            height = g.organH;
          }
          const size = zone ? 9.5 : 10.5;
          const plain = w >= textWidth(p.name, size, 600) + 14 ? p.name : w >= textWidth(p.name.slice(0, 1), size, 600) + 10 ? p.name.slice(0, 1) : '';
          const text = esc(plain);
          /* 기관 · 구역 항목 자신의 이설 (디테일 건의 4 — 칸 하나짜리 줄): 다른 칸과 같은 계획(altRowPlan) — 유령 구분선은 이 칸 안에만, 이름표 비킴 · '이설 있음'.
             이름표는 기관 칸은 가운데, 구역 탭은 왼쪽 맞춤(테두리 1 + 안쪽 여백 6). 앞글자만 보이면 옮기지 않음 */
          const oc = HT.datedAlts(p).length ? { alternatives: HT.datedAlts(p) } : null;
          let omarks = '';
          let odx = 0;
          if (oc) {
            const tw = plain ? textWidth(plain, size, 600) : 0;
            const orow = [{ c: oc, l, r: l + w, key: `org:${p.uid}:${h.host.uid}`, base: itemBaseOf(p), ink: plain ? { text: plain, size, wt: 600, lh: size * 1.2, c: zone ? l + 7 + tw / 2 : undefined } : null, fixed: plain !== p.name, bl: 1, br: 1 }];
            const oplan = this._altPlan(null, orow, { X, lo: l, hi: l + w, h: height, now: p.endY });
            odx = oplan.shift.get(0) || 0;
            omarks = this._altMarksHTML(null, orow, oplan, { top: zone ? 0 : -1, h: height, x0: l + 1, vw: W, spot: () => this.selected === p.uid });
          }
          const tip = `${p.name} · ${zone ? '구역' : '기관'} — ${host.name} (${HT.formatRange(p)})${p.note ? ` · ${p.note}` : ''}${h.note ? ` · ${h.note}` : ''}${oc ? altTip(oc, itemBaseOf(p)) : ''}`;
          const clip = `${la < 0 ? ' clip-l' : ''}${rb > W ? ' clip-r' : ''}`;
          overlayHtml[row] += `<i class="tl-org ${zone ? 'is-zone' : 'is-agency'}${clip}${w < 16 ? ' is-thin' : ''}" data-k="o:${esc(p.uid)}:${esc(h.host.uid)}" data-uid="${esc(p.uid)}" data-row="${row}" data-band="${esc(host.uid)}" title="${esc(tip)}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;height:${height}px;--c:${p.color}"><b${odx ? ` style="translate:${cx(odx)}px"` : ''}>${text}</b>${omarks}</i>`;
        }
        bandBounds.set(p.uid, [X(bandStart(p)), X(bandEnd(p))]);
      }

      /* 조명이 켜질 띠: 상위 띠 아래 숨은 소속 정권의 조명(그 정권을 섬긴 인물의 창 등)은 그것이 접혀 든 보이는 상위 띠에 — 인물 막대도 그 띠에 그려집니다 */
      const spotBand = new Map();
      for (const s of (this.spots || []).concat(this.houseSpans || [])) { // 가문 조명 구간(setHouse의 spans)도 같은 규칙
        let q = inTrackDraw(tr, s.uid);
        while (q && q._hidden) q = q._host;
        if (q) spotBand.set(s, q.uid);
      }

      /* 미정 꼬리의 자리(감독 건의 2026-10-14 7번): 줄을 나눌 때는 꼬리(FADE)를 셈하지 않아(chainRows — 앞 띠의 끝 ≤ 뒤 띠의 시작이면 같은 줄)
         꼬리가 옆 띠 위에 반투명하게 겹쳐 두 테두리가 함께 보였습니다(단군조선의 끝이 위만조선의 앞을 덮음). 꼬리는 같은 줄 이웃 띠의 진짜 끝까지만 —
         옅어지는 폭은 그대로라 모자란 만큼 제 띠 안에서 옅어집니다. 둘 다 미정이면 사이의 가운데에서 만납니다(새 앱 bands.dart `_tailRoom`과 같은 규칙) */
      const rowBands = new Map();
      const liftBy = new Map(); // 서고: 띠 uid → 흰 사건 칸을 올리는 몫 (_bandGeo — 칸 층이 줄의 칸 뭉치보다 적은 띠)
      for (const q of tr.periods) {
        if (q._folded || q._hidden || q._under || q._overlay || q._row == null) continue;
        if (!rowBands.has(q._row)) rowBands.set(q._row, []);
        rowBands.get(q._row).push(q);
      }
      const tailRoom = (p, l, r) => {
        let lo = -Infinity, hi = Infinity;
        for (const q of rowBands.get(p._row) || []) {
          if (q === p) continue;
          const ql = X(bandStart(q)), qr = X(bandEnd(q));
          if (qr <= l + 0.5 && qr > lo) lo = q.endUnknown && p.startUnknown ? (qr + l) / 2 : qr;
          if (ql >= r - 0.5 && ql < hi) hi = q.startUnknown && p.endUnknown ? (r + ql) / 2 : ql;
        }
        return [Math.min(lo, l), Math.max(hi, r)];
      };

      /* 정권 띠 */
      for (const p of tr.periods) {
        if (p._folded || p._hidden || p._under || p._overlay || p._row == null) continue;
        let x1 = X(bandStart(p));
        let x2 = X(bandEnd(p));
        if (p.startUnknown || p.endUnknown) {
          const [roomL, roomR] = tailRoom(p, x1, x2);
          if (p.startUnknown) x1 = Math.max(x1 - FADE, roomL); // 미정 쪽으로 사라지는 꼬리
          if (p.endUnknown) x2 = Math.min(x2 + FADE, roomR);
        }
        bandBounds.set(p.uid, [x1, x2]);
        p._tabR = null;
        if (x2 < -2 || x1 > W + 2) continue;
        if (!drawRow(p._row)) {
          /* 다른 줄에서 들어오는 승계선도 이 탭을 비켜 가므로, 화면 밖에서는 자리만 남깁니다. */
          const tabL = bird ? (p.startUnknown ? Math.max(X(p.start), 0) + 6 : Math.max(x1 + G.radius, 6)) : tagNameAt(p, X, x1) - TAG.pad;
          const tabR = bird ? (p.endUnknown ? Math.min(X(p.endY), W) - 6 : Math.min(x2 - G.radius, W - 6)) : Math.min((p.endUnknown ? X(p.endY) : x2) - TAG.nameRight, W - 6) + TAG.pad;
          const tp = tabParts(p, tabR - tabL, tabRank(p, this.show, geoOf(p._row).rankH), TAB.ext * 2);
          if (!bird && (tp.mode === 'full' || tp.mode === 'short')) p._tabR = tabL + tp.width;
          continue;
        }
        const left = Math.max(x1, -1);
        const width = Math.max(3, Math.min(x2, W + 1) - left);
        const clip = `${x1 < -1 && !p.startUnknown ? ' clip-l' : ''}${x2 > W + 1 && !p.endUnknown ? ' clip-r' : ''}`;
        const kind = p.polityKind || 'state';
        const unk = `${p.startUnknown ? ' unk-s' : ''}${p.endUnknown ? ' unk-e' : ''}`;
        /* 미정인 시작이 화면 왼쪽 밖에서 잘렸으면(사라지는 꼬리가 화면 가장자리에 걸림) 왼쪽 모서리를 폅니다 — 가장자리의 큰 둥근 모서리(22px)가 화면에 붙은 탭 아래로 틈을 내지 않게 (CSS '통합 마무리').
           탭이 없는 오른쪽(끝이 미정인 띠가 오른쪽 밖으로 나감)은 옛 화면 그대로 둡니다 — 그쪽도 펴는 것은 감독이 고른 뒤에(설계 문서 9절) */
        const cutUnk = x1 < -1 && p.startUnknown ? ' cut-l' : '';
        const fadeL = p.startUnknown ? Math.max(0, FADE - Math.max(0, -1 - x1)) : 0;
        const fadeR = p.endUnknown ? Math.max(0, FADE - Math.max(0, x2 - (W + 1))) : 0;
        const cert = p.certainty || 'accepted';
        const zones = [p.startRange, p.endRange].filter(Boolean);
        const whole = cert !== 'accepted' && !zones.length;
        const zoneKind = cert === 'accepted' ? 'estimated' : cert;
        /* 실재성 (8-4 마): 선 모양 · 빗금은 연대 불확실의 몫이라, 바탕의 질감(안개 · 지운 자국)과 탭 이름의 글꼴 · 딱지로 말합니다 (모양은 common.css 끝의 '실재성') */
        const hs = HT.historicityOf(p);
        const hsc = hs ? ` hs-${hs}` : '';
        let inner = '';
        /* 띠의 자식은 테두리 안쪽(padding box)에서 잽니다: ox = 안쪽 왼쪽 x, iw = 안쪽 너비 */
        const BW = G.bw;
        const ox = left + BW;
        const iw = Math.max(0, width - 2 * BW);
        for (const [a, b] of zones) {
          const za = X(a) - ox;
          const zb = X(b) - ox;
          if (zb < 0 || za > iw) continue;
          const zl = Math.max(za, 0);
          const zw = Math.min(zb, iw) - zl;
          const zat = (a === (p.startRange || [])[0] ? p.startRangeAt : p.endRangeAt) || [];
          if (zw > 0.5) inner += `<i class="tl-zone z-${zoneKind}${zl <= 0.5 ? ' at-s' : ''}${zl + zw >= iw - 0.5 ? ' at-e' : ''}" style="left:${cx(zl)}px;width:${cx(zw)}px" title="${esc(`불확실한 구간: ${HT.formatDate(a, zat[0])} ~ ${HT.formatDate(b, zat[1])}`)}"></i>`;
        }
        inner += this._hollowHTML(p, X, ox, iw); // 상징적 본국의 할거기 칠 (8-4 바 — 대범위를 꺼 두어도 보임)
        const zoneCut = inner.length; // 조명 틀(.tl-spots)이 들 자리 — 빗금 · 할거기 칠(.tl-zone) 위, 칸 · 사건 아래 (D1 확정 설계 10절 14번 '함께' — 같은 칠은 같은 차례)
        if (this.showAlt && !bird) { // 조감에서는 다른 견해 고리 없음 (8px 고리가 띠 사이 틈을 채우고 띠 안 이름에 걸림 — 상세에서)
          for (const a of HT.datedAlts(p)) {
            for (const y of [a.start, a.end]) {
              if (y == null) continue;
              const ax = X(y) - left;
              if (ax < -4 || ax > width + 4) continue;
              inner += `<i class="tl-palt" style="left:${cx(ax)}px" title="${esc(`다른 견해 · ${a.label}: ${HT.formatDate(y, y === a.start ? a.startAt : a.endAt)}`)}"></i>`;
            }
          }
        }
        /* 칸 기간 조명: 고른 칸(지도자 · 내각 · 연호 · 도읍 …)의 기간을 띠 안에 옅은 색으로 (칸·사건보다 뒤). 이 띠에 걸린 조명마다 하나씩
           (조명은 여럿일 수 있습니다 — 두 정권을 섬긴 인물 · 왕조가 다스린 나라들. 숨은 소속의 것은 보이는 상위 띠에서 — spotBand).
           조명 메아리가 켜져 있으면 조명의 주인이 아닌 띠에도 그 기간을 제 조명과 같은 짙기로(is-echo) — 띠가 실제로 있던 구간과 겹친 만큼만(HT.echoBandSpans — 창의 '같은 시기 타국'과 같은 계산).
           끝 모양: 칠은 모두 네모이고, 띠 모양으로 잘라 주는 틀(.tl-spots) 안에 둡니다 — 띠 끝에 닿은 끝은 그 띠의 실제 모서리(반지름 · 미정 끝의 긴 모서리 · 화면 끝에서 잘린 곧은 끝), 띠 중간에서 끊긴 끝은 네모 */
        const litYears = []; // 이 띠에 칠한 조명 · 메아리가 덮는 해 — 흐린 띠에서 그 시기만큼은 흐리지 않을 자리(has-lit)
        let altOwn = null; // 이 띠에 걸린 조명 — 이설 조명은 칸을 다 그린 뒤(그은 유령선을 보고) 조명 틀 바로 뒤에 끼움
        let altCut = 0;
        const innerLen = inner.length;
        /* 조감의 띠 안 이름(아래 .tl-bnm — 자리는 여기서 먼저 정함): 그 자리(글자 + 둘레 2.5px — 칠의 끝선 1px 안쪽까지 글자에서 1.5px)에서는 조명 칠 · 가림 판의 경계가 글자를 가로지르지 않게 (nameSnap) */
        const bnm0 = bird && bird.name ? this._birdName(p, X, tr._bnm, bnMemo) : null;
        const bnBox = bnm0 && bnm0.text && bnm0.l >= -0.5 && bnm0.l + bnm0.w <= W + 0.5 ? [bnm0.l - ox - 2.5, bnm0.l + bnm0.w - ox + 2.5] : null;
        let spotSegs = []; // 칠한 토막 [왼, 오른, 메아리, 가문] (띠 안쪽 좌표) — 칸 이름표가 그 끝선을 비켜 감(_litEdges)
        const hown = this.houseSpans ? this.houseSpans.filter(s => spotBand.get(s) === p.uid) : null; // 가문 조명(setHouse의 spans) 가운데 이 띠의 것 — 구간이 화면 밖이어도 '조명된 띠'
        this._hDim = !!(this.houseDim && hown && hown.length); // 조명된 띠 안의 다른 가문 지도자 칸 .55 (_cells — 아래 칸을 다 그린 뒤 끔)
        if (this.spots.length || (hown && hown.length)) {
          const own = this._spotsOf(p.uid, spotBand);
          const paint = (a, b, echo) => {
            const sl = HT.clamp(X(a) - ox, 0, iw);
            const sr = HT.clamp(X(b) - ox, 0, iw);
            if (sr - sl <= 0.5) return;
            spotSegs.push([sl, sr, echo]);
            litYears.push([a, b]);
          };
          for (const s of own) paint(s.start, s.end, false);
          /* 메아리: 이 띠의 제 조명과 겹치는 부분은 빼고(두 번 칠하지 않게), 띠가 있던 구간으로 */
          for (const [a, b] of HT.echoBandSpans(this._echoSpans(), own.map(s => [s.start, s.end]), bandStart(p), bandEnd(p))) paint(a, b, true);
          /* 가문 조명(D1 결정 7 A): 칸 조명과 같은 칠 — 이 띠의 조명 · 메아리가 이미 칠한 해는 빼고(두 번 칠하지 않게), 띠가 있던 구간으로.
             흐린 띠의 '흐리지 않는 구간'(litYears)에는 넣지 않음 — 가문 창은 고르지 않는 창이라 연표를 흐리지 않음 */
          if (hown && hown.length)
            for (const [a, b] of HT.echoBandSpans(HT.echoSpans(hown), litYears.slice(), bandStart(p), bandEnd(p))) {
              const sl = HT.clamp(X(a) - ox, 0, iw);
              const sr = HT.clamp(X(b) - ox, 0, iw);
              if (sr - sl > 0.5) spotSegs.push([sl, sr, false, true]);
            }
          spotSegs = nameSnap(spotSegs, bnBox);
          const spotHtml = spotSegs.map(([sl, sr, echo, hz]) => `<i class="tl-spot${echo ? ' is-echo' : ''}${hz ? ' of-house' : ''}${sl <= 0 ? ' at-s' : ''}${sr >= iw ? ' at-e' : ''}" style="left:${cx(sl)}px;width:${cx(sr - sl)}px"></i>`).join('');
          if (spotHtml) inner = inner.slice(0, zoneCut) + `<i class="tl-spots">${spotHtml}</i>` + inner.slice(zoneCut);
          altCut = zoneCut + (spotHtml ? inner.length - innerLen : 0);
          altOwn = own.length ? own : null;
        }
        /* 같은 시기를 타국에도(8번 C안): 강조 밖이라 흐려진 띠라도 조명 · 메아리가 칠해진 그 시기만큼은 흐리지 않습니다 — 칠 · 테두리선 · 칸이 제 조명과 같은 밝기.
           띠 전체의 불투명도 대신 가림(mask)으로: 그 시기 밖은 흐린 띠와 똑같이(--bo = 그 띠의 불투명도), 그 시기는 --la(1). 나타남 · 물러남은 _litState */
        const lit = this._litState(p.uid, tr.id, this.litOn && !!this.highlight && !this.highlight.has(p.uid) && litYears.length ? litYears : null); // { cols, from · to(다른 칸으로 옮기는 동안의 옛 구간 · 새 구간), cls }
        const litPx = cols => nameSnap(mergeCols(cols.map(([a, b]) => [HT.clamp(X(a) - ox, 0, iw), HT.clamp(X(b) - ox, 0, iw)])), bnBox); // 조감의 띠 안 이름 자리에서는 경계가 이름 밖으로 (칠과 같게)
        this._litCols = lit.cols ? litPx(lit.to ? lit.from.concat(lit.to) : lit.cols) : null; // 칸의 밝기(lit-in): 옮기는 동안은 두 구간을 합쳐 — 옅어지는 쪽 칸은 가림이 가라앉은 뒤에 .45로(가림이 흐린 동안이라 거의 같은 밝기)
        const maskSegs = this._litCols ? (lit.to ? litSegs(litPx(lit.to), litPx(lit.from)) : litSegs(this._litCols, null)) : null;
        const litCss = maskSegs ? `;--lm:${litMask(maskSegs, BW, iw, width)}` : '';
        /* 칸 이름표가 비켜 갈 조명 경계(_altPlan → litShift): 칠한 토막의 끝선 · 가림 판의 밝기가 바뀌는 자리 (띠 끝에 닿은 끝은 빼고) */
        const edgeXs = [];
        for (const [a, b] of spotSegs.concat(maskSegs || [])) {
          if (a > 0.5) edgeXs.push(a);
          if (b < iw - 0.5) edgeXs.push(b);
        }
        this._litEdges = edgeXs.length ? [...new Set(edgeXs.map(v => Math.round(v * 100) / 100))] : null;
        /* 띠가 화면 끝에서 잘렸으면 그쪽 칸도 잘린 것처럼(열린 끝) */
        const cut = { l: x1 < -1 && !p.startUnknown, r: x2 > W + 1 && !p.endUnknown };
        this._caltAt = altOwn ? new Map() : null; // 칸마다 실제로 그은 유령선 자리 (_altMarksHTML이 적음 — 이설 조명의 점선)
        if (g.dynastyH) inner += this._dynCells(p, X, ox, iw, g.dynastyTop - BW, g.dynastyH, cut);
        const { gb: gr, lift: bandLift } = this._bandGeo(tr, p); // 지도자 칸부터 아래는 줄 단위 자리 (시기 단 덧단만큼 내려감) · 서고: 이 띠가 갖지 않은 층을 빼고 맞붙인 자리
        if (bandLift) liftBy.set(p.uid, bandLift); // 서고: 이 띠의 흰 사건 칸을 올리는 몫 (사건 · 묶음 · 단추가 함께 — 새 앱 BandLayer.eventLiftOf)
        for (const y of gr.floorTops || []) if (y > TAG.head + 0.5) inner += `<i class="tl-fl" style="top:${y - BW}px"></i>`; // 서고: 층 사이 금(테보다 옅게 — 새 앱 _paintTwoPiece의 층 사이 금) · 첫 층 윗변은 색줄 밑 금
        if (gr.phaseH) inner += this._phaseCells(p, X, ox, iw, gr.phaseTop - BW, cut);
        /* 렌즈(설계 7-8 결정 5 A): 지도자 칸 자리에 그 주제의 칸 — 체제 렌즈를 지위로 대신하면 지위 단과 지도자 칸이 자리를 맞바꿈 (_lensRow) */
        const lensL = this.themeLens && g.leaderH ? HT.lensCellsOf(p, this.themeLens.id) : null;
        if (gr.rankH && p.rankSpans) inner += lensL && lensL.src === 'rank' ? (this.show.leaders ? this._cells(p.leaders, 'leader', p, X, ox, iw, gr.rankTop - BW, G.rank, Object.assign({}, cut, { mini: true })) : '') : this._rankCells(p, X, ox, iw, gr.rankTop - BW, cut); // 지위 단 (그 줄에 지위가 바뀐 정권이 있을 때만 — 이 정권의 지위가 하나뿐이어도 단에)
        /* 단체 단(설계 7-8 결정 1 A · 2 A + 덧판 x1 A · x3 C): 지위 단 아래 · 지도자 칸 위 — 위 = 집권 · 아래 = 실권. 붕당 렌즈면 집권 줄 자리에 지도자 칸(작게) · 지도자 자리에 집권 칸(맞바꿈 — _groupRows · _lensRow) */
        if (gr.powerH || gr.realH) inner += this._groupRows(p, X, ox, iw, gr, BW, cut, lensL);
        if (g.leaderH) inner += lensL ? this._lensRow(p, lensL, X, ox, iw, gr.leaderTop - BW, g.leaderH, cut) : this._cells(p.leaders, 'leader', p, X, ox, iw, gr.leaderTop - BW, g.leaderH, cut);
        if (g.cabinetH) inner += this._cells(p.cabinets, 'cabinet', p, X, ox, iw, gr.cabinetTop - BW, g.cabinetH, cut);
        this._hDim = false;
        /* 이설 조명(디테일 건의 4 D안): 고른 칸의 이설 기간 — 조명(spots)과 다른 층이라 메아리 · 맨 위 괄호 · 흐리지 않는 구간(litYears)에 들지 않음. 조명 틀 바로 뒤(칸보다 앞)에 */
        if (altOwn) {
          const altSpot = this._altSpotsHTML(p, tr, altOwn, X, ox, iw, gr, BW, this._caltAt);
          if (altSpot) inner = inner.slice(0, altCut) + altSpot + inner.slice(altCut);
        }
        this._caltAt = null;
        /* 분류별 글줄 사이의 아주 옅은 구분선 */
        const rowCats = tr.rowCats && tr.rowCats[p._row];
        if (rowCats) for (let k = 1; k < rowCats.length; k++) inner += `<i class="tl-lanesep" style="top:${gr.textTop + k * g.lineH - BW}px"></i>`;
        /* 예속 칸: 이 띠가 상국이면, 상국이 다스린 속국(자율성 1 · 0 — 괴뢰 · 위임 · 식민 · 점령)의 이름표를 기간 막대 아래 제 칸에 (depProxies).
           속국 띠 안에는 상국을 그리지 않습니다 — 스스로 다스린 속국의 이름표는 띠 아래에 매달림(_depHangs) */
        if (gr.depH && p._dep && p._dep.inLanes) inner += this._depCells(p, X, ox, iw, gr.depTop - BW, cut, depRowLanes(gr));
        const tip = `${p.name} (${HT.formatRange(p)})${kind !== 'state' ? ` · ${HT.kindName(kind)}` : ''}${p.partOfName ? ` · ${p.partOfName} 소속${p.hosts && p.hosts.length === 1 && depRel(p.hosts[0]) ? ` (${depRel(p.hosts[0]).name})` : ''}` : ''}${p.peopleName ? ` · ${p.peopleName}` : ''}${cert === 'accepted' ? '' : ` · ${HT.certaintyName(cert)} 연대`}${hs ? ` · ${HT.historicityName(hs)}` : ''}`;
        const fam = isDepKind(kind) ? ' fam-dep' : ''; // 종속 갈래(종속국 · 조공 · 보호 · 괴뢰 …)의 띠는 옅은 띠 하나 — 누구를 어떻게 섬겼는지는 상국 띠의 속국 이름표로
        /* 연합 표시(설계 7-8 결정 3 C): 이 띠가 연합의 구성 나라면 가담 기간의 올림 조명 자리(평소 숨음 · 맨 앞 — 칸 밑에). 연합이 없는 띠는 빈 글 — 예전과 같은 띠 */
        const coalLit = p.groupLinks ? this._coalLitHTML(p, X, ox, iw) : '';
        /* 한 장 꼬리표(서고 모양 2단 나-1 — 새 앱 bands.dart _paintTwoPiece): 몸통 = 칸 뭉치(이 띠에 칸이 있으면 그 줄의 마지막 칸 층 아랫변 --fe까지 · 색줄 칠의 50%) + 흰 사건 칸.
           왼쪽 아래 귀는 몸통 키에 맞춤(--ck) · 이름 색줄은 띠 위 탭 자리에(.tl-head — 아래) · 조감에는 없음 */
        let tagCss = '';
        let holeIn = ''; // 서고 3단: 구멍은 띠 안 이름 색줄의 왼쪽 위(띠가 테 하나 — 새 앱 bands.dart)
        const seogo = this._seogoOn();
        if (!bird) {
          const floors = [[g.dynastyTop, g.dynastyH], [gr.phaseTop, gr.phaseH], [gr.rankTop, gr.rankH], [gr.powerTop, gr.powerH], [gr.realTop, gr.realH], [gr.leaderTop, g.leaderH], [gr.cabinetTop, g.cabinetH]];
          if (seogo) floors.push([gr.depTop, gr.depH], [gr.organTop, g.organH]); // 서고: 예속 · 기관 칸도 사건 칸 위의 층
          let fe = /class="tl-(cell|dyn)[\s"]/.test(inner) ? Math.max(0, ...floors.filter(([t, h]) => h > 0 && t != null).map(([t, h]) => t + h - BW)) : 0;
          if (seogo) fe = gr.floorEnd - BW; // 서고: 제 칸 층의 아랫변(칸이 없으면 색줄 바로 밑이 사건 칸 — 화면이 아니라 자료로 · _bandGeo)
          tagCss = `;--fe:${cx(fe)}px;--ck:${tagCorner(kind, (tr.rowHs[p._row] || 0) - (tr.rowCut[p._row] || 0) - bandLift)}px${seogo ? `;--hk:${tagCorner(kind, TAG.head)}px${bandLift ? `;--lift:${bandLift}px` : ''}` : ''}`; // --lift: 서고의 몸통 아랫변을 올린 몫(common.css)
          if (seogo) {
            /* 구멍(새 앱 links.dart _paintSquare): 왼쪽 끝에서 7(영토 밖 둥근 끝은 9 — TagLook.holeAt) · 시작이 미정이면 구멍 대신 확정 해 자리의 점선 동그라미(반지름 4 · 띠 테 빛깔) */
            const hx = kind === 'movement' ? 9 : TAG.holeX;
            if (p.startUnknown) {
              const fc = X(p.start);
              if (fc >= -1 && fc + 5 <= Math.min(x2, W + 1)) holeIn = `<i class="tl-hole is-unk" style="left:${cx(fc - left - 5.7)}px"></i>`;
            } else if (x1 >= -1 && x1 + hx + 4 <= Math.min(x2, W + 1)) holeIn = `<i class="tl-hole" style="left:${cx(x1 + hx - left - 5.5)}px"></i>`;
          }
        }
        rows[p._row] += `<div class="tl-band${whole ? ` cert-${cert}` : ''}${clip}${unk}${cutUnk}${kind !== 'state' ? ` kind-${kind}` : ''}${fam}${hsc}${lit.cls}${coalLit && this._coalHot && coalLit.includes(`data-coal="${esc(this._coalHot)}"`) ? ' is-coal-on' : ''}${bird ? '' : ' is-tag'}" data-k="b:${esc(p.uid)}" data-uid="${esc(p.uid)}" data-row="${p._row}" title="${esc(tip)}"
          style="left:${cx(left)}px;width:${cx(width)}px;--c:${p.color};--fadeL:${fadeL}px;--fadeR:${fadeR}px${litCss}${tagCss}">${holeIn}${coalLit}${inner}</div>`;
        if (!bird && !seogo) {
          /* 이름 색줄(서고 모양 2단 나-1): 띠 위 탭 자리의 아래 14px — 띠와 같은 폭 · 띠 칠 · 띠 테(밑변은 띠의 윗 테두리가 덮어 켜 사이 금이 됨) · 왼쪽 위 귀는 키 14의 꼴 · 구멍.
             이름 글은 아래 탭(.tl-tab.on-head)이 맡음 — 화면 가장자리에 붙어 따라오는 처리(끄는 동안 _drawTrackScene)가 탭에 있으므로 */
          const at0 = p.startUnknown ? X(p.start) : x1;
          const hole = at0 >= -1 && at0 + TAG.holeX + 4 <= Math.min(x2, W + 1) ? `<i class="tl-hole" style="left:${cx(at0 + TAG.holeX - left - 5.5)}px"></i>` : '';
          rows[p._row] += `<i class="tl-head${whole ? ` cert-${cert}` : ''}${clip}${unk}${cutUnk}${kind !== 'state' ? ` kind-${kind}` : ''}${fam}${hsc}" data-k="hd:${esc(p.uid)}" data-uid="${esc(p.uid)}" data-row="${p._row}" title="${esc(tip)}" style="left:${cx(left)}px;width:${cx(width)}px;--c:${p.color};--fadeL:${fadeL}px;--fadeR:${fadeR}px;--hk:${tagCorner(kind, TAG.head)}px">${hole}</i>`;
        }
        if (seogo) rows[p._row] += this._seogoExtras(tr, p, X, W, x1, x2); // 서고 3단: 매다는 실(펼친 폴더 안) · 열쇠표(풀린 그릇)
        if (!bird) rows[p._row] += this._hostPlates(p, X, W, left, width, `${clip}${unk}${cutUnk}`, bandLift); // 뒤 장(상국 표기 C): 속국 띠 뒤 상국 빛깔의 종이 — 띠 둘레의 종이빛 틈과 함께 (조감에는 없음)
        if (!this._bird && p._dep && p._dep.outLanes && !this._hangsFolded(p.uid)) rows[p._row] += this._depHangs(tr, p, X, W, geoOf(p._row), lit, ox); // 스스로 다스린 속국의 이름표: 띠 아래에 매달림 (띠 밑에 끼워져 — 책갈피 탭처럼 아래 층)
        const litCols = this._litCols; // 조감의 띠 안 이름이 흐리지 않는 구간에 드는지 (아래 .tl-bnm)
        if (litCols) tr._litX.set(p.uid, litCols.map(([a, b]) => [a + ox, b + ox]));
        this._litCols = null;
        this._litEdges = null;

        /* 정권 이름은 띠 위 왼쪽의 책갈피 탭에: 띠가 화면 왼쪽 밖으로 나가면 탭이 화면 가장자리에 붙어 따라옵니다.
           사건 글줄을 밀어내지 않고 자리가 늘 같아 눈이 헤매지 않습니다. 탭이 들어갈 폭이 없으면 첫 글자만, 그것도 안 되면 생략(왼쪽 칸에 이름이 있음) */
        /* 딱지: 종류(종속 · 괴뢰 …) + 상위 띠 아래에 접혀 있다가 펼쳐진 소속이면 소속 관계도(제 줄의 예속 띠가 없으므로 여기에) — 종류 딱지와 같은 말이면 한 번만.
           실재성 딱지는 종류 딱지와 같은 꼴로 그 뒤에 나란히 · 부정된 나라는 이름에 취소선(딱지에는 긋지 않게 이름만 감쌈) · 전설은 이름이 기울어 조금 넓어짐.
           지위 딱지: 지위 단이 없는 줄에서 지위가 하나뿐인 정권 — 이름 · 종류 · 실재성 딱지 뒤에 작은 딱지(서열 짙기). 함께 들어갈 때만, 아니면 생략.
           무엇을 얼마나 적는가는 tabParts 하나가 정합니다 — 그림 내보내기(toSVG)도 같은 것을 불러 딱지의 차례 · 수 · 첫 글자 줄임이 화면과 같음 */
        const tabName = s => (hs === 'refuted' ? `<s>${esc(s)}</s>` : esc(s));
        /* 간지 탭의 자리(묶음 3 · 1번 L — 감독 결정 2026-09-22): 탭의 발을 띠의 둥근 모서리(G.radius) 위에 두지 않고 모서리가 끝나 윗변이 평평해지는 곳(flatL)부터 —
           모서리가 화면 밖이면(띠가 왼쪽 밖으로 나감) 화면 가장자리 6px에 붙어 따라오고, 시작 미정의 사라지는 꼬리는 예전처럼 진짜 시작에서 6px 안쪽.
           오른쪽도 평평한 윗변이 끝나는 곳(x2 − G.radius)을 넘지 않습니다(안 들어가면 첫 글자만 · 그것도 안 되면 탭 없이 — 첫 글자가 사라지는 문턱이 예전 30px에서 36px로).
           예전의 모서리 밑 조각(at-corner)은 없습니다 — 탭이 모서리 뒤의 평지에서 솟아 어긋남이 없습니다 */
        const flatL = Math.max(x1 + G.radius, 6);
        const tabL = bird ? (p.startUnknown ? Math.max(X(p.start), 0) + 6 : flatL) : tagNameAt(p, X, x1) - TAG.pad; // 한 장 꼬리표: 글이 구멍 뒤(안 여백 13만큼 앞에서 시작)
        const tabR = bird ? (p.endUnknown ? Math.min(X(p.endY), W) - 6 : Math.min(x2 - G.radius, W - 6)) : Math.min((p.endUnknown ? X(p.endY) : x2) - TAG.nameRight, W - 6) + TAG.pad;
        const tp = tabParts(p, tabR - tabL, tabRank(p, this.show, geoOf(p._row).rankH), TAB.ext * 2);
        const kd = tp.kds.map(k => `<small class="kd${k.rel ? ' is-rel' : ''}">${k.t}</small>`).join('');
        const hsd = hs ? `<small class="kd is-hs">${tp.hsTag}</small>` : '';
        const rkTag = tp.rk ? `<small class="rk rk-${tp.rk.level || 0}" style="--mix:${HT.RANK_MIX[tp.rk.level || 0]}%">${esc(tp.rk.name)}</small>` : '';
        const tabText = tp.mode === 'full' ? (seogo ? tabName(p.name) : `${tabName(p.name)}${kd}${hsd}${rkTag}`) : tp.mode === 'short' ? tabName(p.name.slice(0, 1)) : ''; // 서고: 머리에는 이름만 — 종류 · 실재성 · 지위 딱지는 상세 창에서(새 앱 bands.dart _measureHead)
        p._tabR = null;
        let tabEnd = flatL; // 뒤 장의 탭이 서는 자리 — 제 이름 탭 오른쪽 + 틈(탭이 없으면 평지 첫머리)
        if (tabText && !bird) {
          p._tabR = tabL + tp.width;
          tabEnd = p._tabR + TAB.gap;
          /* 간지 탭은 띠보다 아래 층입니다. 다만 띠 윗변에 걸친 '다른 견해' 고리(.tl-palt)가 탭 자리에 걸리면 고리가 이름을 덮으므로, 그때만 탭이 고리의 윗반을 가립니다(has-pin) */
          const pin = this.showAlt && HT.datedAlts(p).some(a => [a.start, a.end].some(y => y != null && X(y) > tabL - 5 && X(y) < p._tabR + 5));
          rows[p._row] += `<span class="tl-tab${whole ? ` cert-${cert}` : ''}${unk}${kind !== 'state' ? ` kind-${kind}` : ''}${fam}${hsc}${tp.mode === 'short' ? ' is-short' : ''}${x1 < -1 ? ' is-stuck' : ''}${pin ? ' has-pin' : ''}${this._sameSelUids && this._sameSelUids.has(p.uid) ? ' is-same-host' : ''}" data-k="tab:${esc(p.uid)}" data-uid="${esc(p.uid)}" data-row="${p._row}" style="left:${cx(tabL)}px;top:${seogo ? 0 : -TAG.head}px;width:${cx(tp.width)}px;height:${TAG.head}px;--c:${p.color}" title="${esc(tip)}">${tabText}</span>`; // 간지 탭(서고: 띠 안 이름 색줄의 글 — top 0): 띠 윗 테두리 두께(G.bw)만큼만 띠 밑으로 들어가 띠의 테두리가 덮습니다 — 모양(어깨 · 칠 · 선)은 common.css '간지 탭'
        }
        if (!bird && this.seogo) { // 과제 9: 빌린 자리의 표지('· 직위 ← 출처' — 이름 탭 옆 · 글자를 덮지 않음) · 밑줄 실권(머리 아랫변 2px · 오른쪽 끝에 쥔 쪽 이름)
          const bl = this._f4BorrowText(p.uid);
          if (bl) {
            const bw = textWidth(bl, 8.5, 400) + 6;
            if (tabEnd + bw < tabR) {
              rows[p._row] += `<small class="tl-borrow" style="left:${cx(tabEnd)}px" title="${esc(bl)}">${esc(bl)}</small>`;
              tabEnd += bw + TAB.gap;
            }
          }
          for (const w of this._f4Powers(p.uid)) {
            const a = Math.max(w.start == null ? x1 : X(w.start), x1 + 3), b = Math.min(w.end == null ? x2 : X(w.end), x2 - 3);
            if (b - a < 4) continue;
            const nm = w.holder.name; // 밑줄 끝 이름은 쥔 쪽(감독 결정 장면 3 '빼앗긴 쪽 띠 머리에 쥔 쪽 색 밑줄과 이름') — 실권 이름은 풍선 글로
            const col = w.holder.color ? `--c:${esc(w.holder.color)}` : '';
            rows[p._row] += `<i class="tl-power-ul" style="left:${cx(a)}px;width:${cx(b - a)}px;${col}" title="${esc(`${w.name ? `${w.name} — ` : ''}${w.holder.name}의 실권`)}"></i>${b - a >= textWidth(nm, 8.5, 700) + 8 ? `<small class="tl-power-name" style="left:${cx(b - 3)}px;${col}">${esc(nm)}</small>` : ''}`;
          }
        }
        /* 뒤 장의 탭(묶음 3 · 1번): 그 나라가 섬긴 상국의 탭이 제 이름 탭 옆에 — 조감에는 없음 */
        if (!bird) rows[p._row] += this._hostTabs(p, X, W, x1, tabEnd, tabR);
        /* 조감: 이름은 책갈피 탭 대신 띠 안 왼쪽에 — 띠 시작에 고정(화면 가장자리를 따라오지 않음: 옆으로 옮겨도 점 · 알약이 숨거나 드러나지 않게 — 원칙 ①),
           들어가는 대로 이름 → 첫 글자 → 없음(딱지 없이 · 문턱은 두 개 — _birdName). 이름 둘레(BIRD_NAME.clear)의 점 · 알약은 옮기지 않고 숨깁니다(bnm → _placeRow).
           화면 안에 다 드는 이름만 그립니다 — 띠 시작이 화면 왼쪽 밖이거나 이름 끝이 오른쪽 밖이면 이름 없이(가장자리에 반쯤 잘린 이름이 없게 — 목업 ④). 자리(bnm)는 그대로 비워 점이 숨고 드러나지 않음.
           모양 c(8px)는 글자 없이 — 이름은 띠에 올리면 풍선으로, 왼쪽 줄 이름 칸은 색 점만 */
        let bnR = null; // 조감: 띠 안 이름(과 단추)의 오른쪽 끝 — 소속 단추가 그 뒤에
        if (bird && bird.name) {
          const nm = bnm0; // 위에서 정한 자리 (조명 경계를 이름 밖으로 옮길 때 쓴 것과 같은 것)
          if (nm.text) {
            /* 이름은 띠의 형제 요소라 띠의 흐림(불투명도 · 가림 판)을 받지 않습니다 — 책갈피 탭처럼 data-uid로 흐림(is-dim)을 받고, 이름 가운데가 흐리지 않는 조명 구간(같은 시기를 타국에도)에 들면 is-lit */
            const nc = nm.l + nm.w / 2 - ox;
            const nLit = !!litCols && litCols.some(([a, b]) => nc >= a && nc <= b);
            if (nm.l >= -0.5 && nm.l + nm.w <= W + 0.5) rows[p._row] += `<span class="tl-bnm${hsc}${nLit ? ' is-lit' : ''}" data-k="bn:${esc(p.uid)}" data-uid="${esc(p.uid)}" data-row="${p._row}" style="left:${cx(nm.l)}px;--c:${p.color}">${tabName(nm.text)}</span>`;
            bnm[p._row].push([nm.l - BIRD_NAME.clear, nm.l + nm.w + BIRD_NAME.clear]);
          }
          bnR = nm.text ? nm.l + nm.w : nm.l - 4;
        }
        /* 건국 · 멸망 네모 둘레는 사건 글자가 피해 갑니다: 글줄이 하나뿐이면 네모가 글줄 가운데에 오므로 점도 그 자리 밖으로 밀어내고, 둘 이상이면 네모가 걸친 두 글줄의 글자만 (_sqZones) */
        const nL = geoOf(p._row).lines;
        const sq1 = nL === 1 ? this._squares(p, X, 1) : null;
        this._sqZones(sq1 || this._squares(p, X, nL), reserved[p._row].slice(0, nL === 1 ? 1 : 2), nL === 1 ? noDot[p._row] : null);
        /* 소속 정권이 있으면 작은 단추: 접힘(▸ n) / 펼침(▾) — 첫 글줄에 두고 사건 글자가 피해 갑니다 */
        const nMem = (p.members || []).filter(m => m.track === tr.id && m.singleHost && !m.groupUid && m.polityKind !== 'overlay' && !(m._scope && m._host !== p)).length; // 켠 대범위로 떠난 정권은 세지 않음 (펼쳐도 여기에 오지 않음)
        if (bird) rows[p._row] += this._birdBtns(tr, p, X, W, x2, bnm[p._row], bnR); // 조감: 이름 뒤의 작은 소속 · 할거 단추 (_birdBtns)
        else if (nMem) {
          const open = this.expandedHosts.has(p.uid);
          const memTxt = `${open ? '▾' : '▸'} ${nMem}`;
          const memW = textWidth(memTxt, 10) + 14;
          let bx = Math.max(p.startUnknown ? X(p.start) : x1, 0) + 14;
          let room = Math.min(x2, W) - 6;
          if (sq1) {
            // 네모와 같은 글줄: 건국 네모 뒤에서 시작하고, 멸망 네모 앞에 점 하나(약 20px) 놓을 자리를 남깁니다
            if (sq1.showF) bx = Math.max(bx, sq1.fc + G.sq / 2 + 4);
            room = Math.min(room, (sq1.showE ? sq1.ec - G.sq / 2 - 1.5 : room) - 20);
          }
          if (bx + memW < room) {
            const by = gr.textTop + Math.round((g.lineH - 16) / 2);
            rows[p._row] += `<button type="button" class="tl-mem${open ? ' is-open' : ''}" data-k="m:${esc(p.uid)}" data-fold-members="${esc(p.uid)}" data-row="${p._row}" style="left:${cx(bx)}px;top:${by}px;--c:${p.color}" title="${esc(`${p.name}에 딸린 정권·조직 ${nMem}개 — ${open ? '접기' : '펼치기'}`)}">${esc(memTxt)}</button>`;
            reserved[p._row][0].push([bx - 3, bx + memW + 3]);
            if (geoOf(p._row).lines === 1) noDot[p._row].push([bx - 3, bx + memW + 3, 1]); // 글줄이 하나면 점을 단추 오른쪽으로
            else if (rowCats) noDot[p._row].push([bx - 3, bx + memW + 3, 1, 0]); // 분류별 글줄: 첫 글줄의 분류 점은 다른 글줄로 갈 수 없으므로 그 글줄의 점만 단추 오른쪽으로 (단추 밑에 가려지지 않게)
          }
        }
        /* 매달린 속국 이름표가 있는 상국이면 작은 접기 단추 '▾ 속국 n' / '▸ 속국 n'(건의 8의 나 — 감독 2026-10-14 "종주국 띠에 접기 하나"): 소속 단추와 같은 꼴 · 같은 첫 글줄,
           소속 단추 뒤 · 할거 단추 앞에서 이미 잡힌 자리(소속 단추 · 네모)를 비켜 오른쪽으로. 접으면 그 상국의 매달린 줄만큼 줄이 낮아짐(toggleHangs) */
        if (!bird && p._dep && p._dep.outLanes) {
          const nHang = p._dep.items.filter(it => it.out).length;
          const open = !this._hangsFolded(p.uid);
          const hbTxt = `${open ? '▾' : '▸'} 속국 ${nHang}`;
          const hbW = textWidth(hbTxt, 10) + 14;
          let bx = Math.max(p.startUnknown ? X(p.start) : x1, 0) + 14;
          let room = Math.min(x2, W) - 6;
          if (sq1) {
            if (sq1.showF) bx = Math.max(bx, sq1.fc + G.sq / 2 + 4);
            room = Math.min(room, (sq1.showE ? sq1.ec - G.sq / 2 - 1.5 : room) - 20);
          }
          for (let k = 0; k < 6; k++) {
            const hit = reserved[p._row][0].find(([l, r]) => bx < r && bx + hbW > l); // 소속 단추 · 건국 네모를 비켜
            if (!hit) break;
            bx = hit[1] + 3;
          }
          if (bx + hbW < room) {
            const by = gr.textTop + Math.round((g.lineH - 16) / 2);
            rows[p._row] += `<button type="button" class="tl-mem tl-hangbtn${open ? ' is-open' : ''}" data-k="hb:${esc(p.uid)}" data-fold-hangs="${esc(p.uid)}" data-row="${p._row}" style="left:${cx(bx)}px;top:${by}px;--c:${p.color}" title="${esc(`${p.name}의 속국 ${nHang} — ${open ? '접기' : '펼치기'}`)}">${esc(hbTxt)}</button>`;
            reserved[p._row][0].push([bx - 3, bx + hbW + 3]);
            if (geoOf(p._row).lines === 1) noDot[p._row].push([bx - 3, bx + hbW + 3, 1]);
            else if (rowCats) noDot[p._row].push([bx - 3, bx + hbW + 3, 1, 0]);
          }
        }
        if (!bird) {
          const nd = geoOf(p._row).lines === 1 ? noDot[p._row] : rowCats ? [] : null; // 분류별 글줄이면 첫 글줄의 점만 (위 소속 단추와 같게)
          rows[p._row] += this._scopeBtnsHTML(tr, p, X, W, x2, gr, reserved[p._row][0], nd);
          if (nd && nd !== noDot[p._row]) for (const z of nd) noDot[p._row].push(z.concat(0));
        } // 할거기 왼쪽 위의 '▸ 〈성격〉 n' — 띠에서 바로 모아 보기 (세로 자리는 소속 단추처럼 그 줄의 첫 글줄 — 시기 · 지위 단이 있으면 그만큼 내려감)
      }
      this._litPrune(tr.id); // 이 트랙에서 이번에 그리지 않은 띠(화면 밖으로 나가 새로 태어날 띠)의 조명 구간 기억은 버림
      /* 접혀 숨은 소속 정권의 사건은 보이는 상위 정권 띠 안에 가둡니다 */
      for (const p of tr.periods) {
        if (!p._hidden || bandBounds.has(p.uid)) continue;
        let h = p._host;
        while (h && h._hidden) h = h._host;
        if (h && bandBounds.has(h.uid)) bandBounds.set(p.uid, bandBounds.get(h.uid));
        if (h && liftBy.has(h.uid)) liftBy.set(p.uid, liftBy.get(h.uid));
      }
      /* 서고: 사건이 앉는 띠의 올림 몫 — 띠를 적지 않은 사건은 같은 줄에서 그 해를 덮는 띠의 것(내보내기 tracks.mjs의 evBands와 같은 셈) */
      const evLift = (e, row) => {
        if (!liftBy.size) return 0;
        const u = e._place && e._place.polityUid;
        if (u && liftBy.has(u)) return liftBy.get(u);
        if (u && bandBounds.has(u)) return 0;
        const q = (rowBands.get(row) || []).find(q => bandStart(q) <= e.start && e.start <= bandEnd(q));
        return (q && liftBy.get(q.uid)) || 0;
      };
      /* 조감: 기관 · 구역은 칸 없이 — 그 사건 점은 얹히는 띠(그 줄의 보이는 상위) 안쪽에 가둡니다 (칸이 없으니 상위 띠 밖의 빈 곳에 점이 뜨지 않게) */
      if (bird)
        for (const p of tr.overlays || []) {
          let host = null;
          for (const h of p.hosts) {
            let q = inTrackDraw(tr, h.host.uid);
            while (q && q._hidden) q = q._host;
            if (q && q._row === p._row && bandBounds.has(q.uid)) {
              host = q;
              break;
            }
          }
          const hb = host && bandBounds.get(host.uid);
          const ob = bandBounds.get(p.uid);
          if (!hb || !ob) bandBounds.delete(p.uid);
          else bandBounds.set(p.uid, Math.min(ob[1], hb[1]) > Math.max(ob[0], hb[0]) ? [Math.max(ob[0], hb[0]), Math.min(ob[1], hb[1])] : hb);
        }

      overlayHtml.forEach((h, r) => (rows[r] += h)); // 띠 뒤에 붙여 띠 위에 그려지게
      this._figureBars(tr, X, W).forEach((h, r) => (rows[r] += h)); // 인물 단도 띠 위에 (줄 직속 요소)
      if (tr.commonRow >= 0 && drawRow(tr.commonRow)) rows[tr.commonRow] += `<i class="tl-rule" data-k="rule" style="top:${geoOf(tr.commonRow).textTop + (geoOf(tr.commonRow).lines * g.lineH) / 2}px"></i>`;

      /* 승계선 · 소속선의 자리를 사건보다 먼저 정합니다 — 내림줄 └이 띠 안을 지나는 자리는 사건 글자가 비켜 갑니다 (_linkPlan의 zones · 그리기는 _drawLinks) */
      tr._bnmZ = bird ? bnm : null; // 조감: 내림줄 · 오름줄이 띠 안 이름 · 단추를 비켜 가게 (_linkPlan)
      const plan = (tr._plan = this._linkPlan(tr, X, W));
      for (const z of plan.zones) for (const k of z.lines) if (reserved[z.row] && reserved[z.row][k]) reserved[z.row][k].push([z.l, z.r]);

      /* 사건 · 기간 레일 */
      const ctx = { bandBounds, expanded, reserved, noDot, prevLab: tr._lab || null, newLab: new Map(), prevClu: tr._clu || null, newClu: new Map(), seen: new Set(), minImp: bird ? 99 : this._minImp, bird: bird ? { zones: bnm, common: tr.commonRow } : null }; // 조감은 사건 이름 없이 점 · 알약만 // 기억(prevLab · prevClu)이 아직 없는 첫 그리기는 문턱 하나로 (맨 처음 화면은 전과 같게)
      /* 옆으로 옮기는 동안만 사건 그림을 좌우 여유까지 지어 이어 씁니다. 배율·선택·검색·줄·장애물이
         달라지면 즉시 새로 배치하고, 손을 놓으면 실제 화면 폭으로 세부 이름을 다시 맞춥니다.
         화면 가장자리를 따라오는 소속 단추·승계선 자리는 세계 좌표로 비교해 재사용 여부를 정합니다. */
      const scale = W / this.span(), start = this.view.start;
      const priorScene = tr._eventScene;
      const pan = !this._sceneRendering && !bird && this._inMotion() && this._drawn && Math.abs(this._drawn.k / scale - 1) < 1e-10 && !tr._squash && !tr._gather && !tr._was && !this._loopOn;
      const pad = pan ? Math.min(240, W * 0.2) : 0;
      const world = x => Math.round((x + start * scale) * 1000) / 1000;
      const zones = list => list.map(z => [world(z[0]), world(z[1]), ...z.slice(2)]);
      const sceneKey = pan ? JSON.stringify([
        this.selected, [...(this.hiLayout || [])], this.lens, this.showAlt, ctx.minImp, !!this._sub, HT.yearOf(start) === HT.yearOf(this.view.end), [...expanded],
        [...bandBounds].map(([uid, bounds]) => [uid, ...bounds.map(world)]),
        reserved.map(lines => lines.map(zones)), noDot.map(zones),
        tr.rowTop.map((top, r) => [drawRow(r), top, tr.rowHs[r]])
      ]) : null;
      const delta = priorScene ? (priorScene.start - start) * scale : 0;
      const reuse = !!(pan && priorScene && priorScene.key === sceneKey && priorScene.W === W && Math.abs(priorScene.scale / scale - 1) < 1e-10 && Math.abs(delta) < pad * 0.55);
      tr._eventReuse = reuse;
      const frameRows = rows, eventW = W + 2 * pad;
      let eventOffset = 0;
      if (reuse) eventOffset = delta - priorScene.pad;
      else {
        const trackRows = frameRows;
        const rows = Array.from({ length: tr.rows }, () => '');
        const viewX = y => (y - start) * scale + pad;
        const viewW = eventW;
        if (pad) {
          const shift = list => list.map(z => [z[0] + pad, z[1] + pad, ...z.slice(2)]);
          ctx.bandBounds = new Map([...ctx.bandBounds].map(([uid, b]) => [uid, b.map(x => x + pad)]));
          ctx.reserved = ctx.reserved.map(lines => lines.map(shift));
          ctx.noDot = ctx.noDot.map(shift);
        }
        const X = viewX, W = viewW, bandBounds = ctx.bandBounds;
      /* 날짜를 정확히 모르는 점 사건(감독 결정 2026-10-13 "적당하게 한 곳을 찍어서 단일로 · 범위 표현 x" — 2026-09-22의 정밀도 괄호를 없앰):
         점은 그 구간 가운데(또는 사건에 적은 자리 spot) 하나에만 찍고(_placeAt — 확대해도 옮겨 가지 않음 · 2026-10-14), 모른다는 사실은 점의 풍선 글 뒤에만 적습니다.
         그 글은 예전에 괄호가 보이던 때(연도 · 달 · 날까지만 적은 것은 한 달이 58 → 72px로 넓어질 때부터, 세기로 적은 것은 구간이 화면에서 넉넉해질 때)만 붙입니다 */
      const monthU = HT.clamp((scale / 12 - 58) / 14, 0, 1), monthGate = monthU * monthU * (3 - 2 * monthU);
      const precGate = e => (e._psCent ? 1 : monthGate);
      const precNote = e => {
        const at = HT.atOf(e, 'start');
        const r = at ? HT.cal.parse(at) : null;
        const cent = r && r.span ? (r.prec === 'c' ? '그 세기 안 어느 해인지 모름' : r.prec === 'c2' ? '그 반세기 안 어느 해인지 모름' : '그 33년 안 어느 해인지 모름') : null;
        return cent || (!r || r.prec === 'y' ? '그해 안 어느 날인지 모름' : r.prec === 'm' ? '그달 안 어느 날인지 모름' : r.prec === 'd' ? '그날 몇 시인지 모름' : '그 시각 안');
      };
      for (const id of [...this._clusters.keys()]) if (id.startsWith(`${tr.id}|`)) this._clusters.delete(id);
      for (let row = 0; row < tr.rows; row++) {
        if (!drawRow(row)) continue;
        const levels = Array.from({ length: g.railLevels || 2 }, () => []);
        const placed = bird && !bird.dots ? [] : this._placeRow(tr.eventsByRow[row] || [], X, W, tr, ctx, row); // 조감 b · c는 사건 점 · 알약 없음
        const ekey = e => `${e.uid}:${e._pi || 0}`;
        const lensId = this.themeLens ? this.themeLens.id : null; // 렌즈: 그 주제의 사건만 또렷 + 주제 색 고리, 나머지는 옅게 (거르지 않음 — 설계 7-8 결정 5)
        const lensCls = e => (lensId ? (HT.lensEventHit(e, lensId) ? ' is-lens' : ' no-lens') : '');
        for (const it of placed) {
          const e = it.e;
          const ek = ekey(e);
          const lz = lensCls(e);
          const color = (e._place && e._place.polityColor) || e.polityColor || e.color;
          const cert = e.certainty || 'accepted';
          const fuzzy = e.startRange || e.endRange;
          const tipName = it.text !== e.title ? `${it.text} (${e.title})` : e.title;
          const vague = !bird && it.pt && it.pt.sp && it.pt.f > 0.02 && precGate(e) > 0.02; // 모르는 구간이 화면에서 넉넉해진 때(점 자리는 그대로)
          const tip = `${e.parentTitle ? `${e.parentTitle} › ` : ''}${tipName} · ${HT.formatRange(e)}${
            e.sharedWith ? ` · ${[e.polityName].concat(e.sharedWith).filter(Boolean).join(' · ')}` : e.polityName ? ` · ${e.polityName}` : ''
          }${vague ? ` — ${precNote(e)}` : ''}`;

          const ranged = it.ranged;
          const alts = this.showAlt && !it.sec ? HT.datedAlts(e) : [];
          const lineTop = geoOf(row).textTop + it.sub * g.lineH - evLift(e, row);
          if (!bird && (ranged || fuzzy || alts.length) && !(this._seogoOn() && !geoOf(row).railH)) { // 서고: 막대 칸이 없는 보기('넉넉하게' 밖)에서는 점과 이름만
            /* 기간 막대·오차 막대·이설 표시는 모두 기간 막대 칸에, 제 정권 띠 안쪽으로 가둬서 (조감에는 기간 막대 칸이 없음 — 점만) */
            const C = it.clamp;
            const xs = ranged ? [it.rx, it.rx2] : [C(it.x)];
            if (e.startRange) xs.push(C(X(e.startRange[0])), C(X(e.startRange[1])));
            if (e.endRange) xs.push(C(X(e.endRange[0])), C(X(e.endRange[1])));
            alts.forEach(a => xs.push(C(X(a.start)), C(X(a.end ?? a.start))));
            const lvl = pickLevel(levels, Math.min(...xs) - 4, Math.max(...xs) + 4);
            const top = geoOf(row).railTop + 3.5 + lvl * G.railPitch;
            if (ranged) {
              rows[row] += `<div class="tl-rail${it.sec ? ' is-pair' : ''}${e.treaty ? ' is-treaty' : ''}${lz}" data-k="r:${esc(ek)}" data-uid="${esc(e.uid)}" data-row="${row}" title="${esc(tip)}"
                style="left:${cx(it.rx)}px;width:${cx(Math.max(3, Math.min(it.rx2, W + 4) - it.rx))}px;top:${top}px;--c:${color}"></div>`;
              /* 조약: 발효가 체결과 다르면 겹줄 기간 막대 위에 작은 발효 눈금 (기간 막대가 있을 때만 — 실효일이 없는 조약에는 놓을 선이 없음) */
              const eff = e.treaty && e.treaty.effective;
              if (eff != null && Math.abs(eff - e.start) > 1e-6) {
                const fx0 = X(eff);
                if (fx0 > it.rx + 3 && fx0 < Math.min(it.rx2, W + 4) - 3)
                  rows[row] += `<i class="tl-eff" data-k="ef:${esc(ek)}" data-uid="${esc(e.uid)}" data-row="${row}" style="left:${cx(fx0)}px;top:${top}px;--c:${color}" title="${esc(`${e.title} · 발효 ${HT.formatDate(eff, e.treaty.effectiveAt)}`)}"></i>`;
              }
            } else {
              /* 점 사건: 점선 실에 꿴 구슬 (연도는 사건에 올리거나 고르면 구슬 위에) — 연대 폭의 눈금은 긋지 않음(한 점으로만) */
              const { beads, edges, lo, hi } = beadsOf(e, alts, C(it.x), C, X, false);
              if (hi - lo >= 3) {
                const range = r => `연대 폭 ${HT.formatYear(r[0])} ~ ${HT.formatYear(r[1])}`;
                rows[row] += `<i class="tl-thread" data-k="th:${esc(ek)}" style="left:${cx(lo)}px;width:${cx(hi - lo)}px;top:${top}px;--c:${color}"></i>`;
                edges.forEach((d, j) => (rows[row] += `<i class="tl-edge" data-k="ed:${esc(ek)}:${j}" data-uid="${esc(e.uid)}" data-row="${row}" style="left:${cx(d.x)}px;top:${top}px;--c:${color}" title="${esc(`${e.title} · ${range(d.r)}`)}"></i>`));
                for (const [j, b] of beads.entries()) {
                  const t = b.kind === 'alt' ? `다른 견해 · ${b.a.label || ''}: ${HT.formatRange(b.a)}` : `통설 · ${HT.formatWhen(e, 'start')}${e.startRange ? ` (${range(e.startRange)})` : ''}`;
                  rows[row] += `<i class="tl-bead${b.kind === 'alt' ? ' is-alt' : ''}" data-k="bd:${esc(ek)}:${j}" data-uid="${esc(e.uid)}" data-row="${row}" data-y="${esc(HT.formatAxisYear(b.y))}" style="left:${cx(b.x)}px;top:${top}px;--c:${color}" title="${esc(`${e.title} · ${t}`)}"></i>`;
                }
              }
            }
            if (ranged) for (const [j, r] of [e.startRange, e.endRange].entries()) {
              if (!r) continue;
              const l = C(X(r[0]));
              const w = C(X(r[1])) - l;
              const title = esc(`불확실한 구간: ${HT.formatYear(r[0])} ~ ${HT.formatYear(r[1])}`);
              /* 끝 연도 없이 연대 폭만 있는 사건은 양 끝 세로바가 있는 오차 막대, 기간 사건의 끝은 빗금 구간 */
              rows[row] += `<i class="tl-fuzz" data-k="fz:${esc(ek)}:${j}" style="left:${cx(l)}px;width:${cx(Math.max(2, w))}px;top:${top}px;--c:${color}" title="${title}"></i>`;
            }
            if (ranged && alts.length) {
              /* 이설의 시점은 점선 세로바. 원래 시작의 실선 세로바와 너무 가까우면 4px 비켜 둡니다 */
              const base = ranged ? it.rx : C(it.x);
              const axs = alts.map(a => {
                const x = C(X(a.start));
                return Math.abs(x - base) < 4 ? base + (x < base ? -4 : x > base ? 4 : -4) : x;
              });
              const lo = Math.min(...axs, base);
              rows[row] += `<i class="tl-altline" data-k="al:${esc(ek)}" style="left:${cx(lo)}px;width:${cx(Math.max(...axs, base) - lo)}px;top:${top}px;--c:${color}"></i>`;
              rows[row] += alts
                .map((a, j) => `<i class="tl-alt" data-k="a:${esc(ek)}:${j}" data-uid="${esc(e.uid)}" data-row="${row}" style="left:${cx(axs[j])}px;top:${top}px;--c:${color}" title="${esc(`다른 견해 · ${a.label}: ${HT.formatRange(a)}`)}"></i>`)
                .join('');
              /* 이설의 끝(디테일 건의 4 — 끝이 통설과 다른 이설만): 끝에도 같은 점선 세로바, 원래 끝과 점선으로 (너무 가까우면 4px 바깥으로) */
              const ends = altEnds(e, alts, it.rx2, C, X);
              if (ends.length) {
                const lo2 = Math.min(...ends.map(q => q.x), it.rx2);
                rows[row] += `<i class="tl-altline" data-k="al2:${esc(ek)}" style="left:${cx(lo2)}px;width:${cx(Math.max(...ends.map(q => q.x), it.rx2) - lo2)}px;top:${top}px;--c:${color}"></i>`;
                rows[row] += ends.map(q => `<i class="tl-alt" data-k="ae:${esc(ek)}:${q.j}" data-uid="${esc(e.uid)}" data-row="${row}" style="left:${cx(q.x)}px;top:${top}px;--c:${color}" title="${esc(`다른 견해 · ${q.a.label}: ${HT.formatRange(q.a)}`)}"></i>`).join('');
              }
            }
          }

          if (it.hidden) continue; // 묶음 알약 · 이름 붙은 사건에 겹쳐 쌓임
          const kids = e.children && e.children.length && !expanded.has(e.uid) && !it.noCnt ? `<i class="cnt">${e.children.length}</i>` : ''; // noCnt: 알약을 떼야 이름이 드는 자리 (_placeRow의 둘째 차례)
          const label = it.label ? `<span class="t">${esc(it.text)}</span>${kids}${it.yr ? `<span class="y">${esc(it.yr)}</span>` : ''}` : '';
          const more = it.more ? it.more.length : 0;
          if (more) {
            const id = `${tr.id}|${row}|e:${ek}`;
            const members = [it].concat(it.more);
            this._clusters.set(id, { lead: e.uid, uids: members.map(m => m.e.uid), keys: members.map(m => `${m.e.uid}:${m.e._pi || 0}`), items: members.map(m => m.e), color, t0: Math.min(...members.map(m => m.e.start)), t1: Math.max(...members.map(m => m.e.endY)) });
          }
          const ink = pad && it.label && it.solid ? ` data-ink="${cx(it.solid[0])},${cx(it.solid[1])}"` : '';
          const cls = `tl-ev imp-${e.importance || 2}${fuzzy ? '' : ` cert-${cert}`}${it.flip ? ' is-flip' : ''}${it.label ? '' : ' is-bare'}${it.child ? ' is-child' : ''}${e.shared ? ' is-shared' : ''}${it.sec ? ' is-pair' : ''}${e.startUnknown || e.endUnknown ? ' is-unk' : ''}${more ? ' has-more' : ''}${e.treaty ? ' is-treaty' : ''}${it.sm ? ' is-sm' : ''}${lz}`;
          rows[row] += `<div class="${cls}"${ink} data-k="e:${esc(ek)}" data-uid="${esc(e.uid)}" data-row="${row}"${more ? ` data-cluster="${esc(`${tr.id}|${row}|e:${ek}`)}" data-more="${more}"` : ''} title="${esc(more ? `${tip}\n+ 같은 자리에 사건 ${more}개 더 — 올리면 목록` : tip)}"
            style="left:${cx(it.x)}px;top:${lineTop}px;height:${g.lineH}px;--c:${color}"><i class="d"></i>${label}</div>`;
        }
        /* 묶음 알약: 개수 · 아래에 묶인 점들의 실제 자리(가는 선 + 눈금) · 안쪽 아랫단에 분류 색 비율 */
        for (const cl of placed.clusters || []) {
          const lead = cl.lead.e;
          const color = (lead._place && lead._place.polityColor) || lead.polityColor || lead.color;
          const lineTop = geoOf(row).textTop + cl.sub * g.lineH - evLift(lead, row);
          const key = `c:${ekey(lead)}`;
          const id = `${tr.id}|${row}|${key}`;
          const items = cl.members.map(m => m.e);
          this._clusters.set(id, { lead: lead.uid, uids: items.map(x => x.uid), keys: items.map(x => `${x.uid}:${x._pi || 0}`), items, color, t0: Math.min(...items.map(x => x.start)), t1: Math.max(...items.map(x => x.endY)) });
          const cats = new Map();
          for (const x of items) cats.set(x.color, (cats.get(x.color) || 0) + 1);
          let acc = 0;
          const seg = [...cats].map(([c, n]) => `${c} ${((acc / items.length) * 100).toFixed(1)}% ${(((acc += n) / items.length) * 100).toFixed(1)}%`).join(', ');
          const spread = !bird && !cl.sm && cl.r - cl.l > cl.w - 8; // 조감 · 작은 알약은 알약 아래 자리 선 · 눈금 없음 (좁은 띠 안에 알약만 — 그림 내보내기와 같게)
          /* 자리 선 · 눈금은 대표 사건의 띠 안쪽(테두리 1px 안)으로 잘라서 — 기관이 얹힌 띠처럼 사건의 범위가 그려진 띠보다 넓을 때도 띠 밖으로 나가지 않게 */
          const wb = bandBounds.get(lead._place && lead._place.polityUid);
          const wl = wb ? Math.max(cl.l, wb[0] + 1.5) : cl.l;
          const wr = wb ? Math.min(cl.r, wb[1] - 1.5) : cl.r;
          const ticks = spread ? cl.members.slice(0, 40).filter(m => m.x >= wl - 0.5 && m.x <= wr + 0.5).map(m => `<i class="tk" style="left:${cx(m.x - cl.x)}px"></i>`).join('') : '';
          const ink = pad ? ` data-ink="${cx(cl.x - cl.w / 2 - 3)},${cx(cl.x + cl.w / 2 + 3)}"` : '';
          rows[row] += `<div class="tl-clu${cl.sm ? ' is-sm' : ''}${lensId ? (items.some(x => HT.lensEventHit(x, lensId)) ? ' is-lens' : ' no-lens') : ''}"${ink} data-k="${key}" data-cluster="${esc(id)}" data-row="${row}" aria-label="${esc(`사건 ${items.length}개`)}" style="left:${cx(cl.x)}px;top:${lineTop}px;height:${g.lineH}px;--c:${color};--pw:${cx(cl.w)}px">${
            spread && wr > wl ? `<i class="wh" style="left:${cx(wl - cl.x)}px;width:${cx(wr - wl)}px"></i>${ticks}` : ''
          }<b><span>${items.length}</span><i class="seg" style="background:linear-gradient(90deg, ${seg})"></i></b></div>`;
        }
      }
        rows.forEach((html, row) => {
          trackRows[row] += pad && html ? `<div class="tl-pan-events" data-k="event-scene" data-pan="1">${html}</div>` : html;
        });
        tr._eventScene = pan ? { key: sceneKey, start, scale, W: viewW - 2 * pad, pad, masks: [] } : null;
        eventOffset = -pad;
      }
      /* 이름 자리·묶음의 기억은 확대의 기억입니다: 옆으로 옮겨 화면 밖에 나가 있는 동안에는 그대로 두었다가 돌아오면 이어 씁니다 — 같은 배율에서 옮겼다 돌아와도 이름과 묶음이 그대로 (자리는 옮긴 길과 무관) */
      for (const [memo, prev] of [[ctx.newLab, ctx.prevLab], [ctx.newClu, ctx.prevClu]]) if (prev) for (const [pk, v] of prev) if (!ctx.seen.has(pk) && !memo.has(pk)) memo.set(pk, v);
      tr._lab = ctx.newLab; // 다음 프레임의 이름 자리·방향 기준
      if (tr._bnm) for (const [k, v] of tr._bnm) if (!bnMemo.has(k)) bnMemo.set(k, v); // 조감 띠 안 이름의 기억도 화면 밖의 것은 그대로
      tr._bnm = bnMemo;
      tr._clu = ctx.newClu; // 다음 프레임의 묶음 기준 (같이 묶여 있던 점은 더 벌어져야 풀립니다 — _placeRow)
      tr._wide = newWide;
      /* 나타남과 사라짐은 같은 모습으로: 새로 생긴 것은 떠오르고, 화면 안에서 없어지는 것은 옅어지며 물러납니다 (멈춰 있을 때 제자리 · 움직이는 중에는 제 해를 따라가며 120ms — _fx) */
      const fx = pan || priorScene || tr._sceneReleased ? null : this._fx(W, tr);
      tr._sceneReleased = false; // 여유 그림을 바꿀 때는 잔상을 만들지 않아 좌표가 다른 옛 그림이 남지 않음
      /* 다시 지은 뒤의 첫 그리기(필터·접기·펼치기): 앞선 화면에 있던 것은 그대로 나타나고, 없던 것만 떠오르며, 있다가 없어진 것은 옅어지며 물러납니다 */
      const was = fx && tr._was && HT.motion.now() < tr._was.until ? tr._was : null;
      tr._was = null;
      if (was) {
        was.known = new Set();
        for (const o of was.lanes) for (const c of o.children) if (c.dataset.k && !c._ghost) was.known.add(c.dataset.k);
      }
      /* 밀도가 바뀐 뒤의 첫 그리기(_squash): 새 줄 안의 것은 모두 떠오름 — 옛 것은 잔상이 옅어지며 맡음 */
      const sq = tr._squash && HT.motion.now() < tr._squash.g.until ? tr._squash : (tr._squash = null);
      const fresh = !!(sq && !sq.drawn && fx);
      rows.forEach((html, row) => {
        const lane = tr.laneEls[row];
        if (!lane) return;
        if (!drawRow(row)) {
          if (lane.childNodes.length) lane.replaceChildren();
          lane._html = '';
          return;
        }
        const res = morph(lane, html, fx, was ? was.known : fresh ? SQZ_NONE : null, 0, reuse);
        if (pan) {
          const layer = lane.querySelector(':scope > .tl-pan-events');
          if (layer) {
            layer.style.transform = `translate3d(${cx(eventOffset)}px,0,0)`;
            layer._panX = eventOffset;
          }
        }
        if (pan && !reuse) for (const el of lane.querySelectorAll('[data-ink]')) {
          const [lo, hi] = el.dataset.ink.split(',').map(Number);
          tr._eventScene.masks.push({ el, lo, hi });
        }
        if (res && fresh) this._squashIn(res.born, sq.g, !!sq.bird);
        else if (res && fx) this._laneFx(res, W, fx.quiet);
        if (res && was && was.sameRows) this._fadeGone(tr, row, was.lanes[row], W);
      });
      if (sq) sq.drawn = true;
      /* 움직이는 그림도 가장자리에서 이름·개수 알약을 반쯤 자르지 않습니다. 폭을 재지 않고 배치 때
         얻은 실제 가장자리로 가리므로, 매 프레임 브라우저에 글자 크기를 다시 물어보지 않습니다. */
      if (pan) for (const { el, lo, hi } of tr._eventScene.masks) el.classList.toggle('is-edge-cut', lo + eventOffset < 0 || hi + eventOffset > W);

      this._drawLinks(tr, X, W);
      this._drawScopes(tr, X, W); // 대범위 테두리의 가로 자리 · 이름표 · 부흥선 (7-2)

      this._drawTrackLabels(tr, X, W, sq);
    }

    /** 작은 꼬리표 줄(서고 3단 — 접힌 문화권의 머리 단 · 닫힌 폴더): 띠를 시작 차례로 높이 13 · 구멍 · 이름 8.5 굵게, 앞 꼬리표와 4 띄우고 자리가 막히면 '+n'.
        top = 줄 안 세로 자리 · thread = 꼬리표 위로 올리는 실의 길이(0이면 없음 — 머리 단) · room = 오른쪽 한계(기본 W − 30) */
    _stagsHTML(list, X, W, top, thread = 0, attrs = '', room = W - 30) {
      const sorted = list.filter(p => X(bandEnd(p)) >= 0 && X(bandStart(p)) <= W).sort((a, b) => bandStart(a) - bandStart(b) || bandEnd(b) - bandEnd(a));
      let html = '';
      let right = 0;
      let more = 0;
      for (const p of sorted) {
        if (more) {
          more++;
          continue;
        }
        const w = Math.ceil(textWidth(p.name, 8.5, 700)) + 19;
        let x = Math.max(X(bandStart(p)), 0);
        if (x < right + 4) x = right + 4;
        if (x + w > room) {
          more = 1;
          continue;
        }
        html += `<i class="tl-stag" data-k="st:${esc(p.uid)}" data-uid="${esc(p.uid)}"${attrs} style="left:${cx(x)}px;top:${top}px;width:${w}px;--c:${p.color}" title="${esc(`${p.name} (${HT.formatRange(p)})`)}">${thread ? `<i class="tl-thread" style="top:${-thread}px;height:${thread - 1}px"></i>` : ''}<b>${esc(p.name)}</b></i>`;
        right = x + w;
      }
      if (more) html += `<i class="tl-stag is-more"${attrs} style="left:${cx(right + 4)}px;top:${top}px">+${more}</i>`;
      return html;
    }

    /** 서고 3단 — 띠에 딸린 것(새 앱 links.dart 매다는 실 · scopes.dart 열쇠표): 펼친 폴더 안 꼬리표는 구멍에서 곧게 올라가는 실(첫 줄 = 몸통 윗변 16 · 둘째 줄부터 줄 사이의 매듭),
        풀린(끈) 대범위에 든 띠는 띠 위 열쇠표(높이 12 · 둥근 끝 · 띠 시작에서 16 · 45° 실 — 누르면 그 그릇을 펼침 data-scope → toggleScope) */
    _seogoExtras(tr, p, X, W, x1, x2) {
      let out = '';
      const r = p._row;
      const holeX = (p.startUnknown ? X(p.start) : x1) + TAG.holeX;
      const branch = (tr.scopeBranches || []).find(b => !b.board && b.box && r >= b.first && r < b.first + b.count);
      if (branch && holeX >= -1 && holeX <= W + 1) {
        let fv = -1;
        for (let k = branch.first; k < branch.first + branch.count; k++)
          if (!tr.hiddenRows.has(k)) {
            fv = k;
            break;
          }
        const first = r === fv;
        const up = first ? (branch.box.hung ? Math.max(6, tr.rowGap[r] - 4) : 16) : Math.max(4, Math.round((tr.rowGap[r] || 0) / 2));
        out += `<i class="tl-thread${first ? '' : ' has-knot'}" data-row="${r}" style="left:${cx(holeX - 0.5)}px;top:${-up}px;height:${Math.max(0, up - TAG.holeR - 1)}px"></i>`;
      }
      let kx = Math.max(p.startUnknown ? X(p.start) : x1, 0) + 16;
      for (const s of (p.scopes || []).filter(x => x.track === tr.id && !this.scopeOn(x))) {
        const w = Math.ceil(textWidth(s.name, 8.5, 700)) + 22;
        if (kx + w > Math.min(x2, W) - 4) break;
        out += `<button type="button" class="tl-key" data-k="key:${esc(s.uid)}:${esc(p.uid)}" data-scope="${esc(s.uid)}" data-row="${r}" data-band="${esc(p.uid)}" style="left:${cx(kx)}px;width:${w}px;--c:${s.color}" title="${esc(`${s.name} — ${s.label || '대범위'} · 풀린 그릇 · 누르면 펼침`)}"><b>${esc(s.name)}</b></button>`;
        kx += w + 4;
      }
      return out;
    }

    /** 서고 3단의 왼쪽 칸(새 앱 gutter.dart · 목업 서고 gutter): 줄 = 작은 꼬리표 그림(12 × 8 · 그 띠의 칠 24% · 테 84%) + 보는 범위에 든 그 줄의 띠 이름을 시작 차례로 ' · '(넘치면 끝을 '…') ·
        글 11 굵게 먹 80 · 이름 색줄(14)의 세로 가운데에 맞춤 · 그릇 안 줄은 깊이마다 10 들여 씀. 폴더(켠 대범위) = 폴더 그림 + 이름(접힌 폴더는 띠 수)을 어깨 탭 높이에 — 누르면 펼침 ↔ 접음.
        민족 칸 · 딱지 · 연도 · 부제 · 노선 · 분류 점은 없음(목업에 없어 뺌 — 감독 2026-10-15 "최대한 목업 반영"). 접힌 민족 묶음은 이름 ▸ · 트랙 공통 줄은 '그 밖' */
    _drawSeogoLabels(tr, X, W, sq = null) {
      const center = (this.view.start + this.view.end) / 2;
      const depthOf = r => (tr.scopeBranches || []).filter(b => !b.board && r >= b.first && r < b.first + b.count).length;
      const picks = [];
      const rows = [];
      for (let row = 0; row < tr.rows; row++) {
        if (row === tr.commonRow) {
          rows.push({ common: true });
          continue;
        }
        if (tr.foldedRows.has(row)) {
          const gp = tr.groups.find(x => x.first === row && x.folded);
          rows.push({ folded: true, name: gp ? gp.name : '', color: gp ? gp.color : tr.color, key: gp ? peopleKey(tr, gp) : '', scope: !!(gp && gp.scope), n: (tr.rowPeriods[row] || []).length });
          continue;
        }
        const list = (tr.rowPeriods[row] || []).filter(p => !p._hidden);
        let best = null;
        let bestW = 0;
        let atCenter = null;
        const seen = [];
        for (const p of list) {
          if (p.start <= center && center <= p.endY) atCenter = p;
          const w = Math.min(X(bandEnd(p)), W) - Math.max(X(bandStart(p)), 0);
          if (w > 0) seen.push(p);
          if (w > bestW) {
            bestW = w;
            best = p;
          }
        }
        const pick = atCenter || best;
        picks[row] = pick || null;
        if (!pick) {
          rows.push(null);
          continue;
        }
        seen.sort((a, b) => bandStart(a) - bandStart(b));
        rows.push({ names: (seen.length ? seen : [pick]).map(p => p.name), color: pick.color, uid: pick.uid, member: tr.memberRows.has(row), depth: depthOf(row) });
      }
      tr._picks = picks;
      const folders = (tr.scopeBranches || []).filter(b => !b.board && b.box).map(b => ({ uid: b.uid, name: b.s.name, top: b.box.top + (b.box.hung ? 4 : b.box.tab - 10), depth: Math.max(0, depthOf(b.first) - 1), closed: this.foldedPeoples.has(`${tr.id}|__scope:${b.uid}`), n: (b.list || []).length }));
      const sig = `S|${rows.map((l, i) => (l ? `${l.uid || l.name || ''}/${(l.names || []).join('·')}/${l.depth || 0}/${l.folded ? 'f' : ''}/${tr.rowHs[i]}` : `/${tr.rowHs[i]}`)).join('|')}#${folders.map(f => `${f.uid}/${f.top}/${f.closed ? 1 : 0}`).join('|')}`;
      if (sig === tr._labelSig) return;
      tr._labelSig = sig;
      const roomBase = this.gutter - COL.track - 23 - 16 - 10; // 꼬리표 그림(왼쪽 47 = 트랙 칸 24 + 23) · 그림 뒤 16 · 오른쪽 10
      const fit = (names, depth) => {
        const room = roomBase - depth * 10;
        let text = names.join(' · ');
        if (textWidth(text, 11, 700) <= room) return text;
        for (let k = names.length - 1; k >= 1; k--) {
          text = `${names.slice(0, k).join(' · ')} …`;
          if (textWidth(text, 11, 700) <= room) return text;
        }
        return names[0];
      };
      tr.rowsEl.innerHTML =
        rows
          .map((l, i) => {
            const style = `margin-top:${tr.rowGap[i]}px;height:${tr.rowHs[i]}px`;
            if (!l) return `<div class="tl-row is-empty" data-row="${i}" style="${style}"></div>`;
            if (l.common) return tr.rowHs[i] ? `<div class="tl-row is-common is-seogo" data-row="${i}" style="${style}"><span class="nm">그 밖</span></div>` : `<div class="tl-row is-empty" data-row="${i}" style="${style}"></div>`; // 높이 0인 공통 줄은 이름 없이(이름표가 다음 문화권 머리 단 밑으로 비어져 나가지 않게)
            if (l.folded)
              return l.scope
                ? `<div class="tl-row is-empty" data-row="${i}" style="${style}"></div>` // 닫힌 폴더의 이름은 폴더 그림이 말함
                : `<button type="button" class="tl-row is-folded is-seogo" data-row="${i}" data-fold-people="${esc(l.key)}" title="${esc(l.name)} 펼치기" style="${style};--c:${l.color}"><span class="nm">${esc(l.name)} ▸</span><small>${l.n}</small></button>`;
            return `<div class="tl-row is-seogo${l.member ? ' is-member' : ''}${tr.hiddenRows.has(i) ? ' is-collapsed' : ''}" data-row="${i}" data-uid="${esc(l.uid)}" title="${esc(l.names.join(' · '))}" style="${style};--c:${l.color};--d:${l.depth}"><i class="tl-rtag"></i><span class="nm">${esc(fit(l.names, l.depth))}</span></div>`;
          })
          .join('') +
        folders
          .map(f => `<button type="button" class="tl-folder${f.closed ? ' is-closed' : ''}" data-fold-people="${esc(`${tr.id}|__scope:${f.uid}`)}" style="top:${cx(f.top)}px;--d:${f.depth}" title="${esc(`${f.name} · ${f.closed ? '펼침' : '접음'}`)}"><i class="tl-fico"></i><b>${esc(f.name)}</b>${f.closed ? `<small>${f.n}</small>` : ''}</button>`)
          .join('');
      if (sq && sq.o && !sq.labels) this._squashLabels(tr);
    }

    _drawTrackLabels(tr, X, W, sq = null) {
      if (this._seogoOn()) return this._drawSeogoLabels(tr, X, W, sq); // 서고 3단의 왼쪽 칸
      const bird = this._bird;
      /* 왼쪽 라벨 — 지금 보고 있는 시기의 정권 (+ 그때의 지도자) */
      const center = (this.view.start + this.view.end) / 2;
      const labels = [];
      const picks = []; // 줄의 대표 정권 (가장자리 안내 · 밀려난 줄로 가기)
      for (let row = 0; row < tr.rows; row++) {
        if (row === tr.commonRow) {
          labels.push({ name: '그 밖', color: '#9c978d', years: '', common: true });
          continue;
        }
        if (tr.foldedRows.has(row)) {
          const gp = tr.groups.find(x => x.first === row && x.folded);
          const n = (tr.rowPeriods[row] || []).length;
          labels.push({ name: gp ? gp.name : '', color: gp ? gp.color : tr.color, years: '', sub: bird ? '' : `정권 ${n}개 · 펼치기 ▸`, folded: true, key: gp ? peopleKey(tr, gp) : '' }); // 조감(14px 줄)은 부제 없이 — 펼치기는 이름 뒤 ▸ · 풍선
          continue;
        }
        let best = null;
        let bestW = 0;
        let atCenter = null;
        for (const p of tr.rowPeriods[row] || []) {
          if (p.start <= center && center <= p.endY) atCenter = p;
          const w = Math.min(X(p.endY), W) - Math.max(X(p.start), 0);
          if (w > bestW) {
            bestW = w;
            best = p;
          }
        }
        const pick = atCenter || best;
        picks[row] = pick || null;
        if (!pick) {
          labels.push(null);
          continue;
        }
        /* 그때의 지도자 · 지위: 칸이 품는 구간 [lo, hi)로(칸의 경계 — 경계 해는 뒤 칸의 것이라 바뀐 해의 1월 1일에 두 사람이 함께 잡히지 않음).
           잡히는 칸이 없으면(정권 끝 바로 그 순간 · 경계를 모르는 칸) 예전처럼 적힌 값의 양 끝을 포함해서. 왕조는 경계를 두지 않으니 뒤 왕조가 이기게 끝만 뺌 */
        const atCenter2 = (list, kind, endOf) => {
          const hit = list.find((c, i) => {
            const { lo, hi } = HT.cellSpan(c, pick, `${kind}:${i}`); // 순번 = 칸 참조의 번호 (지위는 p.rankSpans의 차례)
            return lo <= center && center < hi;
          });
          return hit || list.find(c => c.start <= center && center <= endOf(c));
        };
        const ruler = atCenter2(pick.leaders || [], 'leader', c => c.end ?? pick.endY);
        const dyns = this._dynOf(pick);
        const house = dyns.find(d => d.start <= center && center < d.end) || dyns.find(d => d.start <= center && center <= d.end);
        const rkNow = atCenter2(pick.rankSpans || [], 'rank', c => c.end); // 그때의 지위 — 부제에는 첫 글자만 (끝의 왕조가 잘리지 않게)
        /* 렌즈를 켠 동안(설계 7-8 결정 5 A): 부제의 '지금 지도자'가 '지금 제도'로 — 그 주제 자료가 없는 나라는 지도자 그대로(띠의 옅은 지도자 칸과 같게) */
        const lensOf = this.themeLens ? HT.lensCellsOf(pick, this.themeLens.id) : null;
        const lensNow = lensOf && lensOf.src ? HT.lensCellAt(pick, this.themeLens.id, center) : null;
        const head = lensOf && lensOf.src ? (lensNow ? lensNow.name : '') : ruler ? HT.leaderLabel(ruler, this.leaderMode, this.leaderOrdinal) : '';
        const sub = [head, rkNow && !(lensOf && lensOf.src === 'rank') ? rkNow.name.slice(0, 1) : '', house ? house.dynasty.name : ''].filter(Boolean).join(' · ');
        labels.push({ name: pick.name, color: pick.color, years: bird ? '' : shortYears(pick), uid: pick.uid, sub: bird ? '' : sub, member: tr.memberRows.has(row), cap: !!(pick.capitals && pick.capitals.length), cats: (tr.rowCats && tr.rowCats[row]) || null, orig: bird || !this.origOf ? null : this.origOf(pick) || null }); // 조감은 이름만 (연도 · 부제 · 원어 없이 — 줄이 띠 하나 높이)
      }
      tr._picks = picks;
      const sig = labels.map((l, i) => (l ? `${l.uid || l.name}/${l.sub || ''}/${l.cap ? 1 : 0}/${l.cats ? l.cats.join(',') : ''}/${tr.rowHs[i]}${l.orig ? `/${l.orig.text}` : ''}` : `/${tr.rowHs[i]}`)).join('|');
      if (sig !== tr._labelSig) {
        tr._labelSig = sig;
        /* 긴 줄 이름: 말줄임으로 잘리지 않게 — 들 폭(왼쪽 칸 − 민족 칸 · 점 · 여백)에 이름과 연도가 다 들지 않으면 연도를 빼고, 그래도 넘치면 이름 글자를 10px까지 줄임 (그래도 넘치면 말줄임) */
        const ls = bodyLS(); // 글자 사이(body의 −0.01em을 px로 물려받음 — 줄 이름 .nm도 같음, 연도 em은 0)
        const fitName = l => {
          const size = tr.geo.name - (l.member ? 1 : 0);
          const wt = l.member ? 500 : 600;
          const room = this.gutter - (COL.track + this.depth * COL.people) - 29 - (l.member ? 8 : 0) - (l.cats ? 8 : 0) - (l.cap ? 19 : 0) - 1 - 0.5; // 도읍 표시(.nm::after) 14+5px · 0.5: 잰 폭과 화면 폭의 반올림 차이
          const nameW = (t, s) => textWidth(t, s, wt) + ls * [...t].length; // 화면의 폭 그대로 (글자 사이까지 — 빠뜨리면 들어가는 연도도 뺌)
          const w = nameW(l.name, size);
          /* 원어 병기(10건 3 · 감독 결정 D2-2): 이름 + 원어 + 연도 → 이름 + 원어 → (안 들면 원어를 빼고) 아래의 지금 규칙. 원어는 보통 굵기 · 글자 사이 0 · 앞 4px(.nm-o) */
          if (l.orig) {
            const ow = textWidth(l.orig.text, size, 400) + 4;
            if (w + ow + (l.years ? textWidth(l.years, size * 0.6, 400) + 4 : 0) <= room) return { years: l.years, size: null, orig: true };
            if (w + ow <= room) return { years: '', size: null, orig: true };
          }
          if (w + (l.years ? textWidth(l.years, size * 0.6, 400) + 4 : 0) <= room) return { years: l.years, size: null };
          if (w <= room) return { years: '', size: null };
          const shrink = t => {
            let s2 = Math.floor(size * (room / nameW(t, size)) * 10) / 10;
            while (s2 >= 10 && nameW(t, s2) > room) s2 = Math.round((s2 - 0.1) * 10) / 10;
            return s2 >= 10 ? s2 : null;
          };
          const s2 = shrink(l.name);
          if (s2) return { years: '', size: s2 };
          /* 10px로도 넘치면 괄호 속 딴이름을 뗀 이름으로 ('베트남 민주 공화국(북베트남)' → '베트남 민주 공화국' — 온 이름은 풍선에) */
          const bare = l.name.replace(/\s*[(（][^)）]*[)）]\s*/g, ' ').trim();
          if (bare && bare !== l.name) {
            if (nameW(bare, size) <= room) return { years: '', size: null, text: bare };
            const s3 = shrink(bare);
            if (s3) return { years: '', size: s3, text: bare };
          }
          return { years: '', size: null };
        };
        tr.rowsEl.innerHTML = labels
          .map((l, i) => {
            const style = `margin-top:${tr.rowGap[i]}px;height:${tr.rowHs[i]}px`;
            if (!l) return `<div class="tl-row is-empty" data-row="${i}" style="${style}"></div>`;
            if (l.folded)
              return `<button type="button" class="tl-row is-folded" data-row="${i}" data-fold-people="${esc(l.key)}" title="${esc(l.name)} 펼치기" style="${style};--c:${l.color}">
              <span class="lbl"><span class="nm">${esc(l.name)}</span><span class="sub">${esc(l.sub)}</span></span></button>`;
            const full = l.orig ? `${l.name} ${l.orig.text}` : l.name; // 풍선 · 읽어 주는 글에는 원어까지 (칸에 들지 않아 뺀 때에도)
            const tip = l.cap ? ` tabindex="0" aria-haspopup="dialog" aria-label="${esc(`${full} — 도읍 노선도`)}"` : ` title="${esc(full)}"`;
            const fit = l.common ? { years: '', size: null } : fitName(l);
            /* 이름 · 원어는 <bdi>로 글 방향을 가둡니다(결정 4 — 오른쪽에서 왼쪽 글자의 이름 뒤 연도가 앞으로 뒤집히지 않게 · 연도 em도 CSS로 가둠) */
            return `<div class="tl-row${l.common ? ' is-common' : ''}${l.member ? ' is-member' : ''}${l.cap ? ' has-cap' : ''}${tr.hiddenRows.has(i) ? ' is-collapsed' : ''}" data-row="${i}"${l.uid ? ` data-uid="${esc(l.uid)}"` : ''}${tip} style="${style};--c:${l.color}">
              <span class="lbl"><span class="nm"${fit.size ? ` style="font-size:${fit.size}px"` : ''}><bdi>${esc(fit.text || l.name)}</bdi>${fit.orig ? `<bdi class="nm-o">${esc(l.orig.text)}</bdi>` : ''}${fit.years ? `<em>${esc(fit.years)}</em>` : ''}</span>${l.sub ? `<span class="sub">${esc(l.sub)}</span>` : ''}</span>${l.cats ? this._laneKey(tr, l.cats, i) : ''}</div>`;
          })
          .join('');
        if (sq && sq.o && !sq.labels) this._squashLabels(tr); // 밀도가 바뀐 뒤 처음 다시 쓴 줄 이름: 옛 높이에서 흐르며 떠오르고 옛 칸은 옅어짐
      }
      if (tr._gather) this._gatherDraw(tr); // 모여드는 중(7-3): 이번 그리기에 새로 지어진 줄 이름 · 네모 · 줄 안의 것을 같은 시계에 다시 붙임
    }

    /** 분류별 글줄 표시: 줄 이름 칸 오른쪽 끝에, 글줄 높이마다 그 분류 색의 작은 점 (올리면 분류 이름) */
    _laneKey(tr, cats, row) {
      const g = (tr.geos && tr.geos[row]) || tr.geo; // 줄 단위 자리 (시기 단 덧단만큼 글줄이 내려간 줄도 있음)
      return `<span class="tl-lanekey" aria-hidden="true">${cats
        .map((id, k) => {
          const c = (this._cats && this._cats.get(id)) || { name: id, color: '#a4b1b7' };
          return `<i style="top:${cx(g.textTop + k * g.lineH + g.lineH / 2)}px;--cc:${c.color}" title="${esc(`${c.name} 사건 줄`)}"></i>`;
        })
        .join('')}</span>`;
    }

    /** 동군연합 이음줄(건의 8의 6-다 · 2026-10-14 감독 "이음줄 진행" · 고른 안 A · 늘 옅게): 같은 사람이 같은 때 두 나라의 지도자이면(HT.unionPairs)
        겹친 기간의 가운데 해에서 두 지도자 칸을 세로로 꿰는 줄(먹 60% · 1.5px)과 두 끝의 고리(지름 7 · 종이빛 · 먹 1.5px 테) — 평소 .5 · 올리거나 고르면 1.
        두 나라는 다른 트랙일 수 있어 줄을 트랙마다 나눠 그립니다: 두 나라 띠 안의 몫과 고리는 띠 위(.tl-marks), 그 사이(다른 줄 · 다른 트랙)는 띠 뒤(.tl-links) — 승계선처럼.
        두 칸이 다 그려지고(접히지 · 숨지 않은 줄 · 지도자 단) 화면 세로 안에 있으며 가운데 해가 화면 가로 안이면 줄, 아니면 보이는 끝의 칸 이름 앞에 겹고리 표지(_cells — 칸이 좁으면 없음).
        → this._uMarks(표지를 달 칸 'uid|leader:i') · this._uDraw(트랙 → { back, front, rings }) — 새 앱 scene/paint/unions.dart와 같은 규칙 */
    _planUnions(X, W, sTop, sBot) {
      this._uMarks = new Set();
      this._uDraw = new Map();
      const allPairs = (this._data && this._data.unions) || [];
      /* 서고 미리보기에서 사람 띠로 그린 사람(왕관 둘 이상 — HT.f4Preview의 persons)은 사람 띠의 실 · 뿔 매듭이 칸을 이으므로 이음줄을 긋지 않음(세계사 장면 1 '라' 결정 — 두 벌이 엇갈리지 않게) */
      const f4 = this.seogo && this._data && this._data.f4;
      const crown = f4 && f4.persons && f4.persons.length ? new Set(f4.persons.flatMap(ps => ps.crowns.map(c => `${c.uid}|leader:${c.i}`))) : null;
      const pairs = crown ? allPairs.filter(q => !(crown.has(`${q.a.p.uid}|${q.a.ref}`) && crown.has(`${q.b.p.uid}|${q.b.ref}`))) : allPairs;
      if (!pairs.length || this._bird || !this.show.leaders || this.themeLens) return;
      const tops = new Map();
      let y = 0;
      for (const tr of this.tracks) {
        y += this._sphereLead(tr); // 서고: 문화권 머리 단 · 틈
        tops.set(tr, y);
        y += tr._sphereHidden ? 0 : tr.height + 1;
      }
      this._uSets = this._uSets || new WeakMap();
      const trackOf = q => this.tracks.find(tr => {
        let set = this._uSets.get(tr.periods);
        if (!set) this._uSets.set(tr.periods, (set = new Set(tr.periods)));
        return set.has(q);
      });
      const geoOf = (tr, row) => (tr.geos && tr.geos[row]) || tr.geo;
      /* 끝 하나: 그 지도자 칸이 그려지는가 · 칸의 세로 자리(트랙 안 · 화면 절대) */
      const endOf = e => {
        const q = e.p, tr = trackOf(q);
        if (!tr || tr.folded || q._folded || q._hidden || q._under || q._overlay || q._row == null || q._row < 0 || q._row >= tr.rows) return null;
        if ((tr.hiddenRows && tr.hiddenRows.has(q._row)) || (tr.foldedRows && tr.foldedRows.has(q._row))) return null;
        const g = geoOf(tr, q._row);
        if (!g || !g.leaderH) return null;
        const cellTop = tr.rowTop[q._row] + g.leaderTop;
        return { e, tr, row: q._row, uid: q.uid, ref: e.ref, cellTop, cellBottom: cellTop + g.leaderH, bandTop: tr.rowTop[q._row], bandBottom: tr.rowTop[q._row] + ((tr.rowHs[q._row] ?? tr.rowH) - ((tr.rowCut && tr.rowCut[q._row]) || 0)), abs: tops.get(tr) + cellTop };
      };
      const order = new Map(this.tracks.map((tr, i) => [tr, i]));
      for (const u of pairs) {
        const x = X(u.mid);
        if (!(x >= 0 && x <= W)) continue;
        const ends = [endOf(u.a), endOf(u.b)].filter(Boolean);
        if (!ends.length) continue;
        const inView = d => d.abs + (d.cellBottom - d.cellTop) > sTop && d.abs < sBot;
        const hot = this.selected === u.a.p.uid || this.selected === u.b.p.uid;
        if (ends.length === 2 && ends.every(inView)) {
          const [up, down] = ends[0].abs <= ends[1].abs ? ends : [ends[1], ends[0]];
          const tip = `동군연합 · ${u.name} — ${u.a.p.name} · ${u.b.p.name} · ${HT.formatYear(u.s)} ~ ${HT.formatYear(u.e)}`;
          const slot = tr => {
            if (!this._uDraw.has(tr)) this._uDraw.set(tr, []);
            const o = { key: u.key, tip, hot, mid: u.mid, back: [], front: [], rings: [] }; // 가로 자리는 그릴 때의 X로(끌기용 넓은 그림은 X가 어긋나 있음)
            this._uDraw.get(tr).push(o);
            return o;
          };
          const i0 = order.get(up.tr), i1 = order.get(down.tr);
          for (let i = i0; i <= i1; i++) {
            const tr = this.tracks[i], o = slot(tr);
            if (tr === up.tr) {
              o.front.push([up.cellBottom, up.bandBottom]);
              o.rings.push(up.cellBottom);
            }
            if (tr === up.tr && tr === down.tr) o.back.push([up.bandBottom, down.bandTop]);
            else if (tr === up.tr) o.back.push([up.bandBottom, tr.height]);
            else if (tr === down.tr) o.back.push([0, down.bandTop]);
            else o.back.push([0, tr.height]);
            if (tr === down.tr) {
              o.front.push([down.bandTop, down.cellTop]);
              o.rings.push(down.cellTop);
            }
          }
          continue;
        }
        for (const d of ends) if (inView(d)) this._uMarks.add(`${d.uid}|${d.ref}`);
      }
    }

    /** 한 트랙의 이음줄 몫(_planUnions) — 'back'은 띠 뒤 층(.tl-links)의 선, 'front'는 띠 위 층(.tl-marks)의 선과 고리. 같은 짝의 조각은 data-union으로 묶여 함께 짙어짐 */
    _unionHTML(tr, layer, X) {
      const list = this._uDraw && this._uDraw.get(tr);
      if (!list) return '';
      let html = '';
      for (const o of list) {
        const x = X(o.mid);
        const cls = `tl-union${o.hot ? ' is-hot' : ''}`;
        const data = ` data-union="${esc(o.key)}"`;
        const seg = ([a, b]) => (b - a > 0.5 ? `<path class="${cls}"${data} d="M${cx(x)} ${cx(a)} V${cx(b)}"><title>${esc(o.tip)}</title></path>` : '');
        if (layer === 'back') html += o.back.map(seg).join('');
        else html += o.front.map(seg).join('') + o.rings.map(y => `<circle class="tl-union-ring${o.hot ? ' is-hot' : ''}"${data} cx="${cx(x)}" cy="${cx(y)}" r="2.75"><title>${esc(o.tip)}</title></circle>`).join('');
      }
      return html;
    }

    /** 건국·멸망 네모와 승계선 · 소속선 — 자리는 _linkPlan이 정하고(이번 그리기에서 _drawTrack이 사건을 놓기 전에 정해 tr._plan에 둠), 여기서는 두 층에 그립니다:
        선(띠 뒤 · .tl-links — 띠를 가로지르는 부분은 띠에 가려짐)과 띠 위 층(.tl-marks — 줄별 <g data-row> · 정권별 <g data-p>, 그 안의 차례는 문 → 관문 · 다리 · 고리 → 네모).
        대범위를 켜고 끌 때 띠 위 층은 줄 · 띠와 같은 거리 · 같은 시계로 옮깁니다 (7-3 _gatherDraw) */
    _drawLinks(tr, X, W) {
      const svg = tr.linksEl;
      if (!svg) return;
      const plan = tr._plan || this._linkPlan(tr, X, W);
      svg.setAttribute('width', String(W));
      svg.setAttribute('height', String(tr.height));
      /* 선은 띠 뒤에(띠를 가로지르는 부분은 띠에 가려짐), 건국·멸망 표시와 관문 · 다리는 띠 위의 따로 된 층에.
         두 층 모두 글이 지난번과 같으면 다시 쓰지 않음(svg._html — 옮기는 동안 대부분의 프레임은 선이 그대로: 요소를 새로 낳지 않아 올림 · 고름 표시도 이어짐) */
      const back = plan.back.map(b => this._backHTML(b)).join('') + this._unionHTML(tr, 'back', X);
      if (svg._html !== back) {
        svg.innerHTML = back;
        svg._html = back;
      }
      // 건국(채운 둥근 네모)·멸망(빈 둥근 네모) — 띠 안쪽에. 연도가 미정이면 점선 동그라미
      const hs = G.sq / 2;
      const byRow = new Map(); // 줄 → 정권 → { pre: 문 · 관문 · 다리, sq: 네모 } — 줄별 <g data-row> · 정권별 <g data-p>: 대범위를 켜고 끌 때 줄 · 띠와 같은 거리 · 같은 시계로 옮깁니다 (7-3 _gatherDraw)
      const slot = (row, uid) => {
        if (!byRow.has(row)) byRow.set(row, new Map());
        const m = byRow.get(row);
        if (!m.has(uid)) m.set(uid, { pre: '', sq: '' });
        return m.get(uid);
      };
      /* 서고(설계 4-1 '구멍과 꼬리 마름모'): 건국 · 멸망 네모 대신 — 구멍은 띠 안(_drawTrack의 .tl-hole), 꼬리 마름모는 승계선이 떠나는 띠의 오른쪽 끝에만(반 대각선 3 · 테 없음 · 나라 색 60% + 먹 — common.css .tl-diamond) */
      const seogo = this._seogoOn();
      const departs = seogo ? new Set(plan.back.filter(b => b.from && b.k !== 'part').map(b => b.from).concat(plan.top.filter(t => t.line && t.line.from).map(t => t.line.from))) : null;
      for (const p of tr.periods) {
        if (p._folded || p._hidden || p._under || p._overlay || p._row == null || (tr.hiddenRows && tr.hiddenRows.has(p._row)) || (tr._drawRows && !tr._drawRows.has(p._row))) continue;
        const y = this._anchorY(tr, p._row);
        const { fc, ec, showF, showE } = this._squares(p, X, ((tr.geos && tr.geos[p._row]) || tr.geo).lines);
        let html = '';
        if (seogo) {
          if (showE && departs.has(p.uid)) html += `<polygon class="tl-diamond" points="${cx(ec)},${cx(y - TAG.diamondHalf)} ${cx(ec + TAG.diamondHalf)},${cx(y)} ${cx(ec)},${cx(y + TAG.diamondHalf)} ${cx(ec - TAG.diamondHalf)},${cx(y)}" style="--c:${p.color}"><title>${esc(`${p.name} — 뒤로 이어짐 · ${HT.formatDate(p.endY, p.endAt)}`)}</title></polygon>`;
          if (html) slot(p._row, p.uid).sq += html;
          continue;
        }
        if (showF) {
          html += p.startUnknown
            ? `<circle class="tl-sq is-unknown" cx="${cx(fc)}" cy="${cx(y)}" r="4" style="--c:${p.color}"><title>${esc(`${p.name} 건국 · 연도 미정 (${HT.formatYear(p.start)} 무렵에 배치)`)}</title></circle>`
            : `<rect class="tl-sq is-found" x="${cx(fc - hs)}" y="${cx(y - hs)}" width="${G.sq}" height="${G.sq}" rx="2" style="--c:${p.color}"><title>${esc(`${p.name} 건국 · ${HT.formatWhen(p, 'start')}`)}</title></rect>`;
        }
        if (showE) {
          html += p.endUnknown
            ? `<circle class="tl-sq is-unknown" cx="${cx(ec)}" cy="${cx(y)}" r="4" style="--c:${p.color}"><title>${esc(`${p.name} 멸망·종료 · 연도 미정 (${HT.formatYear(p.endY)} 무렵에 배치)`)}</title></circle>`
            : `<rect class="tl-sq is-fall" x="${cx(ec - hs)}" y="${cx(y - hs)}" width="${G.sq}" height="${G.sq}" rx="2" style="--c:${p.color}"><title>${esc(`${p.name} 멸망·종료 · ${HT.formatDate(p.endY, p.endAt)}`)}</title></rect>`;
        }
        if (html) slot(p._row, p.uid).sq += html;
      }
      /* 같은 줄의 승계 이음매(다리 · 그 문)가 두 띠의 흐리지 않는 조명 구간(같은 시기를 타국에도)에 들면 is-lit — 그 시기의 띠는 제 조명의 띠와 같은 밝기이므로
         다리 · 문도 고르지 않았을 때의 밝기 그대로(다른 것을 고른 동안 .14로 옅어지는 규칙에서 뺌 — common.css). 두 띠의 경계에 걸치므로 3px 여유 */
      const litX = tr._litX;
      const lit = t => {
        if (!t.seam || !litX || !litX.size) return false;
        const f = t.door || t.line;
        const xs = t.door ? [t.door.x + t.door.w / 2] : t.line.segs.map(s => (s.x1 + s.x2) / 2);
        const c = xs.reduce((a, b) => a + b, 0) / xs.length;
        return [f.from, f.to].every(u => (litX.get(u) || []).some(([a, b]) => c >= a - 3 && c <= b + 3)); // 두 띠 모두 (조명 구간의 끝이 이음매이면 한쪽만 흐리지 않으므로 아님)
      };
      for (const t of plan.top) if (!tr._drawRows || tr._drawRows.has(t.row)) slot(t.row, t.uid).pre += t.door ? this._doorHTML(t.door, lit(t)) : this._topLineHTML(t.line, lit(t));
      const html = [...byRow].map(([r, m]) => `<g data-row="${r}">${[...m].map(([uid, s]) => `<g data-p="${esc(uid)}">${s.pre}${s.sq}</g>`).join('')}</g>`).join('') + this._unionHTML(tr, 'front', X);
      if (tr.marksEl) {
        tr.marksEl.setAttribute('width', String(W));
        tr.marksEl.setAttribute('height', String(tr.height));
        if (tr.marksEl._html !== html) {
          tr.marksEl.innerHTML = html;
          tr.marksEl._html = html;
        }
      }
    }

    /** 띠 뒤 층의 선 하나 (화면) — 소속선 · 승계선(가닥이 여럿이면 한 묶음) · 부흥 고리 · 대범위 부흥선 */
    _backHTML(b) {
      if (b.k === 'part') return `<path class="tl-part${b.ref}" d="M${cx(b.x)} ${cx(b.y1)} V${cx(b.y2)}" stroke="${b.color}" style="--c:${b.color}"><title>${esc(b.tip)}</title></path><circle class="tl-part-dot${b.ref}" cx="${cx(b.x)}" cy="${cx(b.y2)}" r="2" fill="${b.color}" style="--c:${b.color}"/>`;
      const ends = ` data-from="${esc(b.from)}" data-to="${esc(b.to)}"><title>${esc(b.tip)}</title>`;
      if (b.k === 'ring') return `<path class="tl-link is-ring${b.ref}" d="M${cx(b.x + 2.75)} ${cx(b.y)} a2.75 2.75 0 1 0 -5.5 0 a2.75 2.75 0 1 0 5.5 0" stroke="${b.color}" style="--c:${b.color}"${ends}</path>`;
      if (b.k === 'bundle') return `<path class="tl-link is-revival is-bundle" d="${b.d}" stroke="${b.color}" style="--c:${b.color}" stroke-dasharray="${b.kind.dash}"${ends}</path><circle class="tl-link-ring" cx="${cx(b.end[0])}" cy="${cx(b.end[1])}" r="2.5" stroke="${b.color}" style="--c:${b.color}"/>`;
      const thin = thinOf(b.kind, b.sg);
      if (!thin) return `<path class="tl-link is-${b.type}${b.ref}" d="${roundHV(b.pts, b.r)}" stroke="${b.color}" style="--c:${b.color}"${b.kind.dash ? ` stroke-dasharray="${b.kind.dash}"` : ''}${ends}</path>`;
      /* 가는 선(부분 승계): 제 굵기(밀도의 가는 선 값)로, 1px 선은 픽셀 칸 가운데에 */
      return `<path class="tl-link is-${b.type}${b.ref}" d="${roundHV(crispHV(b.pts, thin), b.r)}" stroke="${b.color}" style="--c:${b.color};stroke-width:${thin.w}px"${ends}</path>`;
    }

    /** 띠 위 층의 문 (화면): 종이색 둥근 네모 — 맞닿은 이음매의 문은 어두운 화면에서 두 띠 바탕의 중간색 (common.css '승계 이음매').
        문은 제 승계선과 같은 data-from/to — 다른 것을 고른 동안 선과 함께 옅어짐(_applyStates · common.css: 선만 옅어지고 문이 테두리를 연 채 남지 않게) */
    _doorHTML(d, lit = false) {
      const tint = d.tint ? ` style="--da:${d.tint[0][0]};--ka:${d.tint[0][1]}%;--db:${d.tint[1][0]};--kb:${d.tint[1][1]}%"` : '';
      const ends = d.from ? ` data-from="${esc(d.from)}" data-to="${esc(d.to)}"` : '';
      return `<rect class="tl-door${d.tint ? ' is-seam' : ''}${lit ? ' is-lit' : ''}${d.ref || ''}"${ends} x="${cx(d.x)}" y="${cx(d.y)}" width="${cx(d.w)}" height="${cx(d.h)}" rx="1"${tint}/>`;
    }

    /** 띠 위 층의 선 조각 한 묶음 (화면): 관문 · 다리 — 조각마다 제 띠의 테두리색(--c → --edge), 묶음은 승계선과 같은 data-from/to라 올리고 고를 때 함께 짙어짐 */
    _topLineHTML(l, lit = false) {
      const segs = l.segs.map(s => `<path class="tl-seg" d="M${cx(s.x1)} ${cx(s.y1)} L${cx(s.x2)} ${cx(s.y2)}" style="--c:${s.c}${s.w ? `;stroke-width:${s.w}px` : ''}"/>`).join('');
      const ring = l.ring ? `<circle class="tl-seg is-ring" cx="${cx(l.ring.x)}" cy="${cx(l.ring.y)}" r="2.75" style="--c:${l.ring.c}"/>` : '';
      const join = l.join ? `<rect class="tl-seg is-join" x="${cx(l.join.x)}" y="${cx(l.join.y)}" width="${cx(l.join.w)}" height="${cx(l.join.h)}" rx="${cx(l.join.h / 2)}" style="--c:${l.join.c}"/>` : ''; // 합류 조각 (흡수 — 후대 띠 테두리 위)
      return `<g class="tl-link is-top is-${l.type}${l.ref}${lit ? ' is-lit' : ''}" data-from="${esc(l.from)}" data-to="${esc(l.to)}"><title>${esc(l.tip)}</title>${segs}${ring}${join}</g>`;
    }

    /** 승계선 · 소속선의 자리 — 화면(_drawLinks)과 그림 내보내기(toSVG)가 같은 것을 그립니다.
        back: 띠 뒤 층 [{ k: 'part' | 'link' | 'ring' | 'bundle', … }] · top: 띠 위 층 [{ row, uid, door | line }] — 관문(네모 ↔ 제 띠의 테두리) · 다리(같은 줄에서 곧바로 이음) · 문 · 고리 ·
        zones: 띠 안을 세로로 지나는 내림줄의 자리 [{ row, lines: [글줄 번호 …], l, r }] — 사건 글자가 비켜 갑니다(_drawTrack · toSVG).
        opt.tabR(p): 책갈피 탭의 오른쪽 끝 (그림 내보내기는 제 폭으로 잰 값 — 기본은 화면의 p._tabR) */
    _linkPlan(tr, X, W, opt = {}) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      const plan = { back: [], top: [], zones: [] };
      const tabR = opt.tabR || (p => p._tabR);
      const bird = !!this._bird;
      const birdZ = (bird && tr._bnmZ) || []; // 조감: 줄 → 띠 안 이름 · 단추 자리 (_drawTrack · toSVG가 이 계획을 짓기 전에 적어 둠)
      const birdEnd = (o, x) => x >= -1 && x <= W + 1 && X(bandEnd(o)) - X(bandStart(o)) >= 2 * (STUB + 3); // 조감의 관문을 둘 끝: 화면 안 · 짧은 끝 둘이 들 폭
      const stationX = G.bw + 2 + G.sq / 2 + 0.5; // 조감: 네모가 있었을 자리(띠 끝에서 7px) — 내림줄 · 오름줄의 세로 획 (문 4.4px이 모서리 4.5px 밖 곧은 변에 들게 0.5px 더)
      const birdClear = (row, x) => !(birdZ[row] || []).some(([l, r]) => l < x + 4 && r > x - 4);
      const anc = row => this._anchorY(tr, row);
      const geoOf = row => (tr.geos && tr.geos[row]) || tr.geo;
      const bandBottom = row => tr.rowTop[row] + tr.rowHs[row] - ((tr.rowCut && tr.rowCut[row]) || 0);
      /* 대범위 이름표의 자리 — 선 그림은 테두리보다 위 층이라, 소속선 · 되돌아가는 승계선이 이름표를 지나면 이름 글자를 덮습니다. 비켜 갈 때 씁니다(선 굵기 + 1px 여유) */
      const labs = (tr.scopeBranches || []).map(b => this._scopeLabelRect(b, X, W)).filter(Boolean);
      const labAt = (a, b) => labs.find(r => Math.max(a[0], b[0]) > r.l - 2 && Math.min(a[0], b[0]) < r.r + 2 && Math.max(a[1], b[1]) > r.t - 2 && Math.min(a[1], b[1]) < r.b + 2);
      const crossesLab = pts => labs.length > 0 && pts.some((pt, i) => i > 0 && !!labAt(pts[i - 1], pt));
      /* 소속선: 연맹의 구성국·종속국·조직체를 상위 정권과 세로 점선으로 잇습니다 */
      if (this.show.partOf !== false) {
        for (const p of tr.periods) {
          if (!p.hosts || !p.hosts.length || p._folded || p._hidden || p._overlay || p._row == null) continue;
          if (p.groupUid) continue; // 단체의 띠는 소속선 없이(리메이크 조각 ④ — 구멍만)
          if (!p.singleHost) continue; // 상위 띠 아래에 접히지 않는 소속은 상국 띠의 속국 이름표(depProxies)가 잇습니다 — 선은 접혀 들어갔다 펼친 소속에만
          /* 같은 상국 아래 관계만 바뀌어 예속 띠가 하나의 칸으로 이어지는 구간(예속 띠와 같은 기준: 관계를 적은 띠 · 같은 상국 · 1.5px 안으로 맞닿음)은
             선 하나 — 이어진 구간의 첫머리에서 내려오고, 설명글에 관계를 차례로(조공 → 보호 → 식민) 적습니다 */
          const anyRel = p.hosts.some(h => h.relation);
          const linked = (a, b) => anyRel && a.host.uid === b.host.uid && Math.abs(X(a.end ?? p.endY) - X(b.start ?? p.start)) < 1.5;
          for (let j = 0; j < p.hosts.length; j++) {
            const h = p.hosts[j];
            if (j > 0 && linked(p.hosts[j - 1], h)) continue;
            let last = h;
            const rels = [depRel(h)];
            for (let t = j + 1; t < p.hosts.length && linked(p.hosts[t - 1], p.hosts[t]); t++) rels.push(depRel((last = p.hosts[t])));
            const host = tr.periods.find(q => q.uid === h.host.uid);
            if (!host || host._folded || host._hidden || host._row === p._row || tr.hiddenRows.has(p._row) || tr.hiddenRows.has(host._row)) continue;
            let x = X(h.start ?? p.start) + 12; // 둥근 모서리를 피해 띠 안쪽 12px에서 내려옵니다
            const tabEnd = tabR(p);
            if (tabEnd != null && x < tabEnd + 6 && tabEnd + 8 < X(bandEnd(p)) - 6) x = tabEnd + 8; // 책갈피 탭을 피해
            if (x < -4 || x > W + 4) continue;
            const down = p._row > host._row;
            /* 두 띠 사이의 빈 곳만 잇습니다 — 띠 테두리 안으로 들어가지 않게 */
            const hang = (tr.hangRowLanes.get(host._row) || 0) * HANG.pitch; // 상국 띠 아래에 매달린 속국 이름표 줄 — 그 아래에서 내려옵니다
            const y1 = down ? bandBottom(host._row) + 1 + hang : tr.rowTop[host._row] - 1;
            const y2 = down ? tr.rowTop[p._row] - 2.5 : bandBottom(p._row) + 2.5;
            if (down ? y2 - y1 < 2 : y1 - y2 < 2) continue;
            const lab = labs.length ? labAt([x, y1], [x, y2]) : null;
            if (lab) {
              /* 대범위 이름표를 지나면(본국 줄에 매달린 가지의 머리) 이름표 오른쪽으로 비켜 내려오고, 두 띠 안에 그럴 자리가 없으면 긋지 않습니다 — 본국 아래에 매달린 모양이 이미 소속을 말함 */
              const nx = lab.r + 6;
              if (nx > X(bandEnd(p)) - 6 || nx > X(bandEnd(host)) - 6 || nx > W + 4 || labAt([nx, y1], [nx, y2])) continue;
              x = nx;
            }
            const relName = rels.filter(Boolean).map(r => r.name).filter((s, t, a) => s !== a[t - 1]).join(' → ');
            /* 이어진 구간 전체의 기간: 첫 소속의 시작 ~ 마지막 소속의 끝 (칸의 미정: 미정인 쪽은 "미정") */
            const span = { start: h.start, startAt: h.startAt, startUnknown: h.startUnknown, end: last.end, endAt: last.endAt, endUnknown: last.endUnknown };
            const tip = `${p.name} — ${host.name} 소속 (${HT.kindName(p.polityKind)}${relName && relName !== HT.kindName(p.polityKind) ? ` · 소속 관계: ${relName}` : ''})${span.start != null || span.end != null || span.startUnknown || span.endUnknown ? ` · ${hostRange(span, p)}` : ''}`;
            const ref = HT.historicityOf(p) === 'refuted' || HT.historicityOf(host) === 'refuted' ? ' is-refuted' : ''; // 부정된 나라에 닿는 선은 그리되 옅게 (8-4 마)
            plan.back.push({ k: 'part', x, y1, y2, color: host.color, tip, ref });
          }
        }
      }
      /* 관문 · 다리 · 문은 띠 위 층의 그 줄 · 그 정권 묶음에 (네모보다 먼저 — 네모가 위) */
      const put = (row, who, piece) => plan.top.push(Object.assign({ row, uid: who.uid }, piece));
      /* 관문: 선이 네모에서 제 띠의 테두리를 지나 나가는(들어오는) 짧은 한 획 + 테두리의 문. 띠 뒤 선은 이 자리에서 띠에 가려지므로 선이 네모에 닿는 모습을 띠 위에서 보여 줍니다 */
      const seogo = this._seogoOn(); // 서고: 선은 꼬리 마름모의 가운데에서 나와 뒤 꼬리표 구멍의 왼쪽 테에서 멎음 — 띠 위 층의 획(관문)만 있고 문은 없음(마름모 · 구멍이 테두리 안에 있어 테를 지나는 자리가 색줄 안)
      const gate = (who, row, meta, g) => {
        const piece = gatePiece(Object.assign({ kind: meta.kind, dh: G.door, sg: G.thin }, g));
        if (!seogo) put(row, who, { door: Object.assign({ tint: null, from: meta.from, to: meta.to, ref: meta.ref }, piece.door) }); // ref: 부정된 나라에 닿는 선의 문은 선과 함께 옅게
        put(row, who, { line: Object.assign({}, meta, { segs: piece.segs.map(s => Object.assign({ c: who.color }, s)), ring: null }) });
      };
      if (this.show.succession) {
        /* 승계선은 곡선 대신 꺾은선으로: 선대 띠 끝에서 잠깐 나갔다가 세로로 내려와 후대 띠 앞으로 들어갑니다.
           한 정권에서 여러 선이 나가면 세로 통로를 조금씩 비껴 겹치지 않게 합니다 */
        const outIdx = new Map();
        const edges = [];
        /* 선대가 '같은 트랙'인지는 지금 이 트랙에 놓였는가로 봅니다(자료의 track이 아니라) — 판을 켜면 구성 나라가 판 트랙으로 옮겨 가도 track은
           원래 트랙 그대로라, track으로 보면 원래 트랙에 판의 줄 번호로 선이 그어졌습니다. 판 안의 선은 두 나라가 모두 판에 있을 때만(소속선과 같은 규칙) */
        const placed = new Set(tr.periods);
        for (const p of tr.periods) {
          if (p._folded || p._hidden || p._overlay) continue;
          for (const edge of p.predecessors || []) {
            const q = edge.from;
            if (!placed.has(q) || q._row == null || p._row == null || q._folded || q._hidden || q._under || q._overlay || tr.hiddenRows.has(q._row) || tr.hiddenRows.has(p._row)) continue;
            if (this.show.succession === 'direct' && edge.type !== 'direct') continue;
            if (tr._bundled && tr._bundled.has(edge)) continue; // 모인 부흥 세력이 본국을 가리키는 부흥선은 테두리로 가는 한 줄로 묶어 그립니다 (_bundleLine)
            edges.push({ edge, q, p });
          }
        }
        edges.sort((a, b) => HT.cmp16(a.q.uid, b.q.uid) || Math.abs(a.p._row - a.q._row) - Math.abs(b.p._row - b.q._row));
        const half = G.sq / 2 + 1;
        /* 조감(네모 없음): 띠 끝이 곧 역 — 선은 띠 끝 가운데에 닿고, 테두리 안쪽 STUB(3px)까지의 짧은 끝이 관문(문 + 띠 위 획)입니다. 곧바로 이어지면 두 짧은 끝 사이가 다리(맞닿으면 한 문).
           미정인 끝은 사라지는 꼬리라 관문 없이 제 끝 해에서, 띠가 짧은 끝 둘이 들 만큼 넓지 않거나 끝이 화면 밖이면 관문 없이 띠 뒤 선만.
           내림줄 └은 멸망 네모가 있을 자리(띠 끝에서 7px — 네모 가운데 6.5px보다 0.5px 안쪽: 문이 모서리 밖 곧은 변에 들게 · stationX)에서 띠의 아래(위) 변을 지나 곧게, 오름줄 ┐은 건국 네모 자리로 — 띠 안 이름 · 단추 · 사건 점을 비킬 때만 */
        for (const { edge, q, p } of edges) {
          const kind = succKind(edge.type);
          const sq = this._squares(q, X, geoOf(q._row).lines, W);
          const sp = this._squares(p, X, geoOf(p._row).lines, W);
          const x1 = bird ? (q.endUnknown ? X(q.endY) : X(bandEnd(q)) - STUB) : seogo ? sq.ec : sq.ec + half; // 선대의 멸망 네모 오른쪽 (조감: 띠 끝의 짧은 끝 · 서고: 꼬리 마름모의 가운데)
          const y1 = anc(q._row);
          const x2 = bird ? (p.startUnknown ? X(p.start) : X(bandStart(p)) + STUB) : seogo ? sp.fc - TAG.holeR - 0.5 : sp.fc - half; // 후대의 건국 네모 왼쪽 (조감: 띠 시작의 짧은 끝 · 서고: 구멍의 왼쪽 테)
          const y2 = anc(p._row);
          if (Math.max(x1, x2) < -20 || Math.min(x1, x2) > W + 20) continue;
          const tip = `${q.name} → ${p.name} · ${HT.successionLabel ? HT.successionLabel(edge) : edge.type === 'direct' ? '직접 승계' : '간접 승계'}${edge.note ? ` · ${edge.note}` : ''}`; // 부분 승계는 '· 부분 승계 · 정도 중 · 지배층 · 백성'
          const ref = HT.historicityOf(p) === 'refuted' || HT.historicityOf(q) === 'refuted' ? ' is-refuted' : ''; // 부정된 나라에 닿는 승계선은 그리되 옅게 (8-4 마)
          const meta = { type: edge.type, kind, edge, from: q.uid, to: p.uid, tip, ref };
          const qe = X(bandEnd(q));
          const pf = X(bandStart(p));
          const qEnd = qe + (q.endUnknown ? FADE : 0);
          const pl = pf - (p.startUnknown ? FADE : 0);
          /* 네모가 그려지고 그 끝이 확정이며(미정인 끝은 사라지는 꼬리라 지날 테두리가 없음) 네모 쪽 끝이 문(테두리 ± 0.5)보다 안쪽인 끝(okQ · okP — 내림줄 · 오름줄을 고를 때) —
             네모 하나뿐인 좁은 띠에서 네모가 테두리에 바짝 붙으면 아님.
             관문 · 다리를 둘 수 있는 끝(gq · gp)은 여기에 더해 네모가 띠 끝 자리에 있을 때(테두리에서 GATE_MAX 안) — 연대 폭이 있는 끝은 네모가 띠 끝에서 멀어 관문 없이 띠 뒤 선만 */
          const okQ = bird ? !q.endUnknown && birdEnd(q, qe) : sq.showE && !q.endUnknown && x1 <= qe - 1.5;
          const okP = bird ? !p.startUnknown && birdEnd(p, pf) : sp.showF && !p.startUnknown && x2 >= pf + 1.5;
          const gq = okQ && (seogo || x1 >= qe - GATE_MAX); // 서고: 마름모는 늘 띠 끝에서 7 — 관문(띠 위 획)은 그려지는 마름모 · 구멍마다
          const gp = okP && (seogo || x2 <= pf + GATE_MAX);
          const gateOut = () => gq && gate(q, q._row, meta, { a: x1, b: qe + 0.5, at: y1, vertical: false, border: [qe - 1, qe] }); // 선대: 멸망 네모에서 오른쪽 테두리 밖으로
          const gateIn = () => gp && gate(p, p._row, meta, { a: x2, b: pf - 0.5, at: y2, vertical: false, border: [pf, pf + 1] }); // 후대: 건국 네모에서 왼쪽 테두리 밖으로 (박자는 네모 쪽에서)
          /* 부흥 승계: 간접 승계와 같은 점선 + 작은 고리(되돌아옴). 선은 띠 뒤에 있으므로 고리는 후대 띠 바로 앞(보이는 선의 끝 — 관문이 있으면 문 바깥)에, 자리가 있을 때만 */
          const rx = pl - (gp ? 4.75 : 3.75);
          let ring = kind.ring && pl > -10 && pl < W + 10;
          let pts;
          let rad = 6;
          if (q._row === p._row) {
            /* 같은 줄에서 곧바로 이음(chainRows의 _seamL): 두 네모 사이의 다리 — 선 전체가 띠 위 층이라 맞닿아도 · 틈이 벌어져도 같은 모양이 이어집니다(띠 뒤 선은 없음).
               네모가 그려지지 않는 먼 보기에서는 다리 · 문도 없이 예전처럼 띠 뒤 선만 */
            if (p._seamL === q && gq && gp) {
              const br = seamBridge({ qe, pf, xa: x1, xb: x2, y: y1, kind, dh: G.door, sg: G.thin });
              if (!seogo) for (const d of br.doors) put(p._row, p, { seam: true, door: Object.assign({ tint: d.seam ? [bandTint(q), bandTint(p)] : null, from: meta.from, to: meta.to, ref: meta.ref }, d) });
              put(p._row, p, { seam: true, line: Object.assign({}, meta, { segs: br.segs.map(s => Object.assign({ c: s.side === 'q' ? q.color : p.color }, s)), ring: br.ring && Object.assign({ c: q.color }, br.ring) }) });
              continue;
            }
            if (x2 - x1 < 2) continue;
            pts = [[x1, y1], [x2, y1]];
            if (ring) ring = rx - 2.75 >= qEnd + 3; // 두 띠 사이에 고리가 들어갈 틈이 있을 때만
            /* 곧바로 이음인데 네모 하나가 생략된 먼 보기에서는 관문도 없이 (반쪽 다리가 되지 않게) — 이음매 표시가 없는 쌍도 두 띠가 맞닿거나 겹치면(연대 폭 · 미정인 끝)
               관문은 둘 다이거나 둘 다 없이: 한쪽만이면 맞닿은 겹테두리의 한 줄만 열린 반쪽 다리가 됨 */
            if (p._seamL !== q && (gq === gp || pl - qEnd >= 1)) {
              gateOut();
              gateIn();
            }
          } else {
            const k = outIdx.get(q.uid) || 0;
            outIdx.set(q.uid, k + 1);
            let xm = qEnd + 9 + k * 5; // 세로 통로는 선대 띠(사라지는 꼬리·연대 폭 포함) 바깥에
            const dir = y2 > y1 ? 1 : -1;
            /* 흡수(합류 — 2026-09-20 감독 결정 '모든 승계 종류'): 후대가 선대의 끝보다 먼저 있었고 선대가 끝난 뒤에도 이어지면(이미 있던 나라로 들어감) 선을 후대의 건국 네모로
               거꾸로 보내지 않고 그해의 후대 띠 테두리에 곧게 닿게 — 닿는 자리에는 선대 색의 합류 조각(joinPiece — 테두리 위, 밖으로 나가지 않음). 길은 차례로
               ① 합류 내림줄: 멸망 네모 밑(위)에서 곧게(내림줄 └과 같은 조건 — 선대 띠 안의 그쪽이 비었을 때, 조감은 네모 자리 stationX)
               ② 합류 통로: 선대 띠 오른쪽 관문으로 나와 띠 밖 세로 통로에서 곧게 — 통로가 선대 줄의 다른 띠에 걸리면 안 됨, 후대의 책갈피 탭 위면 탭 너머로.
               닿는 자리는 후대 띠의 곧은 테두리(둥근 모서리 밖 · 합류 조각이 다 듦)이고 위 테두리면 책갈피 탭 밖 · 대범위 이름표는 가로지르지 않음 · 사이 줄의 띠 · 탭 뒤는
               지금의 승계선처럼 지나감(띠에 가려짐). 둘 다 안 되면 예전처럼 되돌아가는 길. 선대의 끝이 화면 밖이면 합류 선도 화면 밖이라 긋지 않음 */
            if (HT.succAbsorbs(q, p)) {
              if (qEnd < -50 || x1 > W + 20) continue; // 합류 선은 선대의 끝 언저리에만 있음
              const jw = joinPiece({ x: 0, edgeY: 0, dir }).w;
              const yJ = dir > 0 ? tr.rowTop[p._row] : bandBottom(p._row); // 후대 띠의 선대 쪽 바깥 변
              const pe = X(bandEnd(p));
              const tabEnd = dir > 0 && !bird ? tabR(p) : null;
              const landOK = x => x - jw / 2 >= pf + G.radius && x + jw / 2 <= pe - G.radius && (tabEnd == null || x - jw / 2 >= tabEnd + 3) && x > -10 && x < W + 10;
              let merge = null;
              const xd = bird ? qe - stationX : sq.ec;
              if (gq && landOK(xd) && this._dropOK(tr, q, dir, xd, X, tabR) && (!bird || birdClear(q._row, xd)) && !crossesLab([[xd, y1], [xd, yJ]])) merge = { x: xd, drop: true }; // 관문을 둘 수 있는 끝에서만(연대 폭이 있는 끝은 네모가 띠 끝에서 멀어 ②로)
              else
                for (const xv of [xm, tabEnd != null ? Math.max(xm, tabEnd + 3 + jw / 2) : xm]) {
                  if (landOK(xv) && this._clearAt(tr, q._row, (qe + xv) / 2, q, X, (xv - qe) / 2) && !crossesLab([[x1, y1], [xv, y1], [xv, yJ]])) {
                    merge = { x: xv, drop: false };
                    break;
                  }
                }
              if (merge) {
                const xj = merge.x;
                if (merge.drop) {
                  const yS = bird ? (dir > 0 ? bandBottom(q._row) - G.bw - STUB : tr.rowTop[q._row] + G.bw + STUB) : y1 + dir * half; // 멸망 네모의 아래(위) 변 1px 밖 (조감: 띠의 아래(위) 변 안쪽 짧은 끝)
                  const edgeY = dir > 0 ? bandBottom(q._row) : tr.rowTop[q._row];
                  pts = [[xj, yS], [xj, yJ]];
                  gate(q, q._row, meta, { a: yS, b: edgeY + dir * 0.5, at: xj, vertical: true, border: [edgeY - dir, edgeY] });
                  const L = geoOf(q._row).lines;
                  plan.zones.push({ row: q._row, lines: seogo ? Array.from({ length: L }, (_, i) => i) : L === 1 || dir < 0 ? [0] : Array.from({ length: L - 1 }, (_, i) => i + 1), l: xj - (G.sq / 2 + SQ_CLEAR), r: xj + G.sq / 2 + SQ_CLEAR });
                } else {
                  pts = [[x1, y1], [xj, y1], [xj, yJ]];
                  gateOut();
                }
                put(p._row, p, { line: Object.assign({}, meta, { segs: [], ring: null, join: Object.assign({ c: q.color }, joinPiece({ x: xj, edgeY: yJ, dir })) }) });
                plan.back.push({ k: 'link', pts, r: 6, type: edge.type, kind, sg: G.thin, color: q.color, from: q.uid, to: p.uid, tip, ref, join: true });
                /* 부흥의 고리: 합류 선 위, 후대 띠 테두리 바로 밖 — 선대 띠와의 사이에 들 때만 */
                const gy = yJ - dir * (0.5 + 3.6);
                if (kind.ring && (dir > 0 ? gy - 3.6 >= bandBottom(q._row) + 1 : gy + 3.6 <= tr.rowTop[q._row] - 1)) plan.back.push({ k: 'ring', x: xj, y: gy, color: q.color, from: q.uid, to: p.uid, tip, ref });
                continue;
              }
            }
            /* 세로 통로가 같은 트랙의 대범위 이름표(어느 가지의 머리든)를 곧게 지나면 이름표 오른쪽으로 비켜 내려옵니다 — 소속선과 같은 규칙.
               후대 띠 앞에 그만큼의 자리가 있을 때만(없으면 그대로 — 되돌아가는 길은 아래에서 따로 이름표를 피함) */
            if (labs.length && x2 >= xm + 6) {
              let xv = xm;
              for (let t = 0; t < 4; t++) {
                const lab = labAt([xv, y1], [xv, y2]);
                if (!lab) break;
                xv = lab.r + 6 + k * 5;
              }
              if (xv !== xm && x2 >= xv + 6 && !crossesLab([[x1, y1], [xv, y1], [xv, y2], [x2, y2]])) xm = xv;
            }
            /* 틈이 좁아 통로가 후대 앞에 서지 못하면: ① 통로를 후대 앞 6px까지 당기고(선대 띠 밖 4px 넘게 · 두 줄의 다른 띠 뒤로 숨지 않을 때),
               ② 그것도 안 되면 멸망 네모 밑(위)에서 곧게 나오는 내림줄 └ — 선대 띠 안을 지나는 부분은 띠 위 층의 관문, 그 자리의 사건 글자는 비켜 감(zones),
               ③ 선대 띠의 그쪽이 막혔으면(칸 · 예속 띠 …) 거꾸로 후대의 건국 네모로 곧게 드는 오름줄 ┐ — 선대 줄에서 후대 네모 자리까지 가로로 나와 후대 띠의 선대 쪽 변으로 들어감.
               셋 다 안 되면(해가 실제로 겹치거나 띠 안의 것에 걸림) 예전처럼 줄 사이 빈 곳으로 돌아갑니다 */
            let mode = x2 >= xm + 6 ? 'hv' : null;
            if (!mode) {
              const slid = Math.min(xm, pf - 6);
              const drop = bird ? qe - stationX : sq.ec;
              const rise = bird ? pf + stationX : sp.fc;
              if (slid >= qEnd + 4 && this._clearAt(tr, q._row, slid, q, X) && this._clearAt(tr, p._row, slid, p, X) && !crossesLab([[x1, y1], [slid, y1], [slid, y2], [x2, y2]])) {
                xm = slid;
                mode = 'hv';
              } else if (okQ && okP && pf - 6 >= drop && this._dropOK(tr, q, dir, drop, X, tabR) && (!bird || birdClear(q._row, drop)) && this._clearAt(tr, p._row, drop, p, X) && !crossesLab([[drop, y1], [drop, y2], [x2, y2]])) {
                xm = drop;
                mode = 'drop';
              } else if (okQ && (bird ? okP && birdClear(p._row, rise) : sp.showF) && !p.startUnknown && rise >= qe + 6 && rise >= x1 + 8 && this._dropOK(tr, p, -dir, rise, X, tabR) && this._clearAt(tr, q._row, (qe + rise) / 2, q, X, (rise - qe) / 2) && !crossesLab([[x1, y1], [rise, y1], [rise, y2]])) {
                xm = rise;
                mode = 'rise';
              }
            }
            if (mode === 'hv') {
              pts = [[x1, y1], [xm, y1], [xm, y2], [x2, y2]];
              if (ring) ring = rx - 2.75 >= xm + 3; // 세로 통로와 겹치지 않을 때만
              gateOut();
            } else if (mode === 'rise') {
              const yE = bird ? (dir > 0 ? tr.rowTop[p._row] + G.bw + STUB : bandBottom(p._row) - G.bw - STUB) : y2 - dir * half; // 건국 네모의 선대 쪽 변 1px 밖 (조감: 띠의 선대 쪽 변 안쪽 짧은 끝)
              const edgeY = dir > 0 ? tr.rowTop[p._row] : bandBottom(p._row); // 후대 띠의 선대 쪽 바깥 변
              pts = [[x1, y1], [xm, y1], [xm, yE]];
              gateOut();
              gate(p, p._row, meta, { a: yE, b: edgeY - dir * 0.5, at: xm, vertical: true, border: [edgeY + dir, edgeY] });
              const L = geoOf(p._row).lines;
              plan.zones.push({ row: p._row, lines: seogo ? Array.from({ length: L }, (_, i) => i) : L === 1 || dir > 0 ? [0] : Array.from({ length: L - 1 }, (_, i) => i + 1), l: xm - (G.sq / 2 + SQ_CLEAR), r: xm + G.sq / 2 + SQ_CLEAR });
              if (ring) {
                ring = false; // 부흥의 고리는 후대 띠의 선대 쪽 변 바로 밖(문 너머), 오름줄 위에 — 선대 줄까지 고리가 들어갈 틈이 있을 때만
                const gy = edgeY - dir * (0.5 + 3.6);
                if (dir > 0 ? gy - 3.6 >= bandBottom(q._row) + 1 : gy + 3.6 <= tr.rowTop[q._row] - 1) plan.back.push({ k: 'ring', x: xm, y: gy, color: q.color, from: q.uid, to: p.uid, tip, ref });
              }
            } else if (mode === 'drop') {
              const yS = bird ? (dir > 0 ? bandBottom(q._row) - G.bw - STUB : tr.rowTop[q._row] + G.bw + STUB) : y1 + dir * half; // 멸망 네모의 아래(위) 변 1px 밖에서 (조감: 띠의 아래(위) 변 안쪽 짧은 끝)
              const edgeY = dir > 0 ? bandBottom(q._row) : tr.rowTop[q._row]; // 선대 띠의 아래(위) 바깥 변
              pts = [[xm, yS], [xm, y2], [x2, y2]];
              if (ring) ring = rx - 2.75 >= xm + 3;
              gate(q, q._row, meta, { a: yS, b: edgeY + dir * 0.5, at: xm, vertical: true, border: [edgeY - dir, edgeY] });
              const L = geoOf(q._row).lines;
              plan.zones.push({ row: q._row, lines: seogo ? Array.from({ length: L }, (_, i) => i) : L === 1 || dir < 0 ? [0] : Array.from({ length: L - 1 }, (_, i) => i + 1), l: xm - (G.sq / 2 + SQ_CLEAR), r: xm + G.sq / 2 + SQ_CLEAR });
            } else {
              // 후대가 선대 끝보다 앞서 시작하면(겹침·되돌아감) 줄 사이 빈 곳으로 돌아갑니다 — 구역 탭·바탕 문화 단 아래, 책갈피 탭 위의 틈으로(돌아오는 가로선이 탭 밑에 숨지 않게)
              const tabOf = r => this._tabOf(tr, r);
              let nextGap = G.gap;
              for (let j = p._row + 1; j < tr.rows; j++) {
                if (tr.hiddenRows.has(j)) continue;
                const hj = this._scopeHead(tr, j);
                nextGap = tr.rowGap[j] - hj - (hj ? 0 : tabOf(j)); // 대범위 테두리의 머리(이름표 자리) · 다음 줄의 책갈피 탭 자리는 빼고 그 위의 빈 곳으로 (머리에는 탭 자리가 들어 있음 — _scopeHead)
                break;
              }
              const hd = this._scopeHead(tr, p._row);
              const upGap = tr.rowGap[p._row] - hd - (hd ? 0 : tabOf(p._row)); // 후대 줄 위의 빈 곳 (대범위 머리 · 책갈피 탭 자리는 뺌)
              const up = tr.rowTop[p._row] - (tr.rowGap[p._row] - upGap) - Math.max(2, upGap / 2);
              const down = tr.rowTop[p._row] + tr.rowHs[p._row] + Math.max(2, nextGap / 2);
              const xl = pl - 9 - k * 5 - (ring ? 5 : 0); // 부흥의 고리가 있으면 통로를 고리만큼 더 왼쪽에 — 모서리 굽이가 고리에 닿지 않게
              const via = gy => [[x1, y1], [xm, y1], [xm, gy], [xl, gy], [xl, y2], [x2, y2]];
              /* 내려가는 선은 후대 줄 위, 올라가는 선은 후대 줄 아래의 빈 곳으로 — 그쪽에 빈 곳이 없거나(본국 줄에 매달린 대범위의 머리가 간격을 다 차지함)
                 대범위 이름표를 가로지르면 반대쪽 빈 곳으로 돕니다 (반대쪽도 막히면 그대로) */
              pts = via(dir > 0 ? up : down);
              if ((dir > 0 ? upGap : nextGap) < 3 || crossesLab(pts)) {
                const alt = via(dir > 0 ? down : up);
                if ((dir > 0 ? nextGap : upGap) >= 3 && !crossesLab(alt)) pts = alt;
              }
              rad = 5;
              gateOut();
            }
            if (mode !== 'rise') gateIn();
          }
          plan.back.push({ k: 'link', pts, r: rad, type: edge.type, kind, sg: G.thin, color: q.color, from: q.uid, to: p.uid, tip, ref });
          if (ring) plan.back.push({ k: 'ring', x: rx, y: y2, color: q.color, from: q.uid, to: p.uid, tip, ref });
        }
      }
      /* 대범위 부흥선(모인 부흥 세력 → 본국, 한 줄로 묶음 — _bundleLine): 선은 띠 뒤, 본국의 멸망 네모에서 오른쪽 테두리까지는 관문 */
      for (const b of tr.scopeBranches || []) {
        const bl = this._bundleLine(tr, b, X, W);
        if (!bl) continue;
        plan.back.push(Object.assign({ k: 'bundle' }, bl));
        const host = bl.host;
        const sq = this._squares(host, X, geoOf(host._row).lines, W);
        const he = X(bandEnd(host));
        if ((bird ? birdEnd(host, he) : sq.showE) && !host.endUnknown && bl.x1 < he && bl.x1 >= he - GATE_MAX) gate(host, host._row, { type: 'revival', kind: bl.kind, edge: null, from: bl.from, to: bl.to, tip: bl.tip, ref: '' }, { a: bl.x1, b: he + 0.5, at: bl.y1, vertical: false, border: [he - 1, he] });
      }
      return plan;
    }

    /** 줄 row의 아래쪽 단과 띠 밑에 덧붙은 것이 xc ± 10px 안에 실제로 있는가 — 인물 막대(인물 단) · 속국(품은 예속 칸 · 매달린 이름표) · 기관 칸 · 구역 탭을 제 해의 폭으로 봅니다.
        예전에는 그 줄에 이런 것이 하나라도 있으면 어디서든 내림줄을 막아, 예속 띠가 일찍 끝난 선대에서도 이미 있던 나라로 합류하지 못하고 후대의 시작점까지 되돌아갔음
        (2026-09-22 감독 '부분 승계도 간접 승계처럼 중간 합류가 되게' — 월흔해 은륜 제국 → 새빛 공동국). 바탕 문화의 띠 · 이름 단은 선이 지나가는 바탕이라 보지 않음 */
    _lowerBusy(tr, row, xc, X) {
      const lo = xc - 10;
      const hi = xc + 10;
      const hit = (a, b) => X(a) < hi && X(b) > lo;
      for (const f of tr.figures || []) {
        if (f.row !== row || f.lvl < 0 || !f.band) continue;
        const [a, b] = this._figSpan(f.s);
        if (hit(Math.max(a, bandStart(f.band)), Math.min(b, bandEnd(f.band)))) return true;
      }
      for (const p of tr.rowPeriods[row] || []) {
        if (p._dep) for (const it of p._dep.items) for (const s of it.segs) if (hit(s.a, s.b)) return true;
      }
      for (const p of tr.overlays || []) {
        for (const h of p.hosts || []) {
          let host = tr.periods.find(x => x.uid === h.host.uid) || null;
          while (host && host._hidden) host = host._host;
          if (host && host._row === row && hit(Math.max(bandStart(p), h.start ?? -Infinity, bandStart(host)), Math.min(bandEnd(p), h.end ?? Infinity, bandEnd(host)))) return true;
        }
      }
      return false;
    }

    /** 줄 row에서 self 말고 다른 띠(사라지는 꼬리 포함)가 x ± (4 + half)를 덮지 않는가 — 당긴 세로 통로 · 내림줄 · 오름줄의 가로 획이 다른 띠 뒤로 숨어, 어디서 이어진 선인지 헷갈리지 않게 */
    _clearAt(tr, row, x, self, X, half = 0) {
      return !(tr.rowPeriods[row] || []).some(o => o !== self && !o._hidden && X(bandStart(o)) - (o.startUnknown ? FADE : 0) < x + 4 + half && X(bandEnd(o)) + (o.endUnknown ? FADE : 0) > x - 4 - half);
    }

    /** 내림줄 └을 선대 q의 띠 안(멸망 네모 xc의 아래 · 위)에 그어도 되는가: 그쪽에 띠 안의 칸 · 인물 단 · 예속 띠 · 기관 칸 · 구역 탭이 없고(위로 가면 좁은 띠의 책갈피 탭도),
        근처(± 10px — 띠 안으로 당겨진 점 · 기간 막대 자리)에 사건이 없을 때만 — 띠 위 층의 획이 띠 안의 것과 겹치지 않게.
        아래로 갈 때의 인물 단 · 예속 띠 · 기관 칸 · 덧붙은 탭은 그 줄에 있기만 하면 막던 것을 그 자리(xc ± 10px)에 실제로 있을 때만 막음(_lowerBusy) —
        위로 가는 쪽의 왕조 · 시기 · 지위 · 지도자 · 내각 단은 띠의 기간 내내 이어지므로 예전처럼 있기만 하면 막음 */
    _dropOK(tr, q, dir, xc, X, tabR) {
      const g = (tr.geos && tr.geos[q._row]) || tr.geo;
      if (this._seogoOn()) {
        /* 서고: 마름모 · 구멍이 맨 위 이름 색줄에 있어 위로는 색줄 7px뿐이고(늘 됨), 아래로는 칸 층(왕조 … 기관) 모두와 사건 칸 · 막대 · 인물 · 덧붙은 단을 지나야 함 — 칸 층이 하나라도 있으면 막힘 */
        if (dir > 0 && (g.dynastyH || g.phaseH || g.rankH || g.powerH || g.realH || g.leaderH || g.cabinetH || g.depH || g.organH || ((g.figH || (tr.rowCut && tr.rowCut[q._row])) && this._lowerBusy(tr, q._row, xc, X)))) return false;
      } else if (dir > 0 ? (g.figH || g.depH || g.organH || (tr.rowCut && tr.rowCut[q._row])) && this._lowerBusy(tr, q._row, xc, X) : g.dynastyH || g.phaseH || g.rankH || g.powerH || g.realH || g.leaderH || g.cabinetH) return false;
      const tabEnd = tabR(q);
      if (dir < 0 && tabEnd != null && tabEnd > xc - 6) return false;
      const qs = X(bandStart(q));
      const qe = X(bandEnd(q));
      const owner = uid => {
        let o = tr.periods.find(x => x.uid === uid) || null;
        while (o && o._hidden) o = o._host;
        return o;
      };
      for (const e of tr.eventsByRow[q._row] || []) {
        const uid = e._place ? e._place.polityUid : e.polityUid;
        const o = uid ? owner(uid) : null;
        if (o && o !== q) continue;
        const [lo, hi] = this._extent(e);
        const a = o ? HT.clamp(X(lo), qs + 9, qe - 9) : X(lo); // 제 띠의 사건은 띠 끝 9px 안으로 당겨짐 (_placeRow)
        const b = o ? HT.clamp(X(hi), qs + 9, qe - 9) : X(hi);
        if (a < xc + 10 && b > xc - 10) return false;
      }
      return true;
    }

    /* ---------- 집합 보기 (10건 6 — 설계 docs/설계-10건/6-모아-보기와-배치.md · 감독 선택 D4: 1 A · 2 A) ----------
       판 하나를 켜면 구성 나라가 놓인 줄을 **통째로** — 그 줄의 모든 나라(화면 밖까지) · 사건 · 인물 막대 · 같은 줄 안의 승계 이음, 그 줄 아래에 숨은 · 펼친 소속,
       그 줄에 깔린 바탕 문화 · 얹힌 기관까지 — 맨 위 합성 트랙(BOARD_ID) 하나로 옮겨 쌓습니다(구성 나라를 적은 차례 · 같은 줄의 둘째 나라는 첫째의 줄에 함께).
       원래 트랙에는 그 줄이 없어진 채로 다시 배치되고(빈 줄이 남지 않음), 나머지 트랙은 접힙니다(트랙 접기 그대로 — 34px · 가는 막대 · '펼치기 ▸', 트랙 이름을 누르면 그 트랙만 폄).
       판의 왼쪽 칸 = 세로 판 이름(.tl-tname — 판 색) · 원래 트랙 칩(첫 단 · 점선 — 대범위 칸의 말씨) · 제 민족 칩(둘째 단) · 줄 이름. 같은 트랙(같은 민족)이 이어진 줄은 칩 하나,
       칩이 글보다 짧으면 뜻이 남는 앞 글자만(shortName — 말줄임표 없음). 판 둘레는 대범위 테두리와 같은 말씨(.tl-scope.is-board)로 가로 전체 · 이름표 '판 이름 · 집합 보기 · 트랙 n · 나라 m'
       (대범위 머리 16px 자리 — 이름표를 누르면 판 목록 opts.onBoardName) · 판의 기간(start ~ end)은 대범위 기간과 같은 짙은 세로 구간.
       줄 사이는 대범위 가지와 같은 규칙(첫 줄 위 = 책갈피 탭 + 머리 16, 줄 사이 = 8 + 탭 11, 원래 트랙이 바뀌는 곳만 묶음 틈 14 · 판 아래 여백 6).
       판 안의 승계선 · 소속선은 두 나라가 모두 판에 있을 때만(다른 트랙의 선이므로 판 밖으로 나가는 선과 그 선만 닿던 네모는 저절로 없음).
       판의 구성 나라가 켠 대범위에 들어 있으면 판이 이김(판 트랙에는 대범위가 없음 — 판을 끄면 대범위 모습으로). 날짜 칸(연호 · 도읍 묶음)은 원래 트랙의 묶음 그대로(axisPeriods — 자료를 빼는 것이 아님).
       판을 끄면 this.folded(접힘 기억)를 건드린 적이 없으므로 켜기 전 모습 그대로(1px도 다르지 않음) — 판을 켜기 전에 보던 줄로 데려옵니다.
       움직임: 판 트랙은 새 트랙처럼 0에서 자라며 떠오르고(is-opening — --t-move · --t-in), 나머지 트랙은 같은 시계로 접힘(_applyFlip). 줄이 트랙을 넘어 날아가는 움직임은 없음
       (.tl-track이 그리기를 제 상자에 가두므로 — contain: paint). 동작 줄이기면 즉시. 새 앱(아카이브)은 이 규칙으로 내보낼 때 미리 셈한 변형 view:<id>를 받습니다 (설계 '구현 기록(웹)') */

    /** 집합 보기 켜기 · 끄기 — board = { id, name, color, members: [정권 uid — 판 안의 차례], start?, end?, temp?(저장하지 않은 판) } 또는 null.
        켜면: 판 트랙만 펴고 나머지는 접음(판을 바꿔 켜도 새로) · 판에 기간이 있으면 그 시기로(멀리 가기 — fly: false면 보던 범위 그대로) · 판의 머리를 화면 위로. 끄면: 켜기 전에 보던 줄로.
        같은 판(id)을 다시 넘기면(구성 나라를 고침) 접힘 · 보던 자리는 그대로 다시 모읍니다. 한 번에 판 하나 — 다른 판을 넘기면 앞 판이 꺼집니다. 돌려주는 값: 켠 판(없으면 null) */
    setBoard(board, { fly = true } = {}) {
      const prev = this.board;
      const next = board && Array.isArray(board.members) && board.members.length ? Object.assign({}, board, { members: board.members.slice() }) : null;
      if (!prev && !next) return null;
      if (!prev && next && this.bodyEl) {
        const a = this._autoAnchor(); // 판을 켜기 전에 보던 줄 — 끌 때 그 줄로 (스크롤 닻)
        this._boardBack = a && a.tr && !a.tr.board ? { id: a.tr.id, row: a.row, off: a.off } : null;
        /* 트랙마다의 기억(빈 줄 접힘 · 이름 자리의 문턱) — 판을 켜면 접혀 잊히므로 적어 두었다가 끌 때 되돌림 (_foldAhead) */
        this._boardStash = new Map(this.tracks.map(tr => [tr.id, { rows: tr.rows, hidden: !tr.folded && tr._rowMemo ? new Set(tr.hiddenRows) : null, memo: { lab: tr._lab, clu: tr._clu, wide: tr._wide, bnm: tr._bnm } }]));
      }
      if (prev && !next) {
        this._boardRestore = this._boardStash || null;
        this._boardStash = null;
      }
      this.board = next;
      if (!prev || !next || prev.id !== next.id) {
        this._boardOpen = new Set();
        this._boardFolded = false;
      }
      if (this._data) {
        cancelAnimationFrame(this._anchorRaf); // 앞선 데려오기 · 붙잡기는 여기까지 — 판의 머리(켤 때) · 보던 줄(끌 때)로 새로 겁니다
        this._held = null;
        this._pressHold = null;
        this._jump = null;
        this.setData(this._data, { enter: false });
        this._settleSoon(0);
        if (next && !(prev && prev.id === next.id)) this._boardReveal();
        else if (!next) this._boardReturn();
      }
      if (fly && next && next.start != null && isFinite(next.start)) {
        const e = next.end != null && isFinite(next.end) ? Math.max(next.end, next.start) : next.start;
        const pad = Math.max((e - next.start) * 0.12, 2); // 판의 기간이 화면 안쪽에 넉넉히 (양쪽 12% · 적어도 2년)
        this.setView(next.start - pad, e + pad, { animate: true, inset: true });
      }
      if (this.opts.onBoard) this.opts.onBoard(this.board);
      return this.board;
    }

    /** (공개) 켠 집합 보기 (없으면 null) */
    boardOn() {
      return this.board;
    }

    /** (공개) 정권 uid가 지금 판 트랙에 옮겨져 있는가 */
    _boardHas(uid) {
      return !!(uid && this._boardUids && this._boardUids.has(uid));
    }

    /** 지금 접힌 트랙인가 — 판이 서 있으면 판의 접힘(판 트랙은 _boardFolded, 나머지는 보는 사람이 다시 편 것만 펴짐), 아니면 접힘 기억(this.folded) */
    _foldedNow(id) {
      if (!this._boardTr) return this.folded.has(id);
      return id === BOARD_ID ? this._boardFolded : !this._boardOpen.has(id);
    }

    /** 판이 서 있는 동안의 트랙 접기 · 펴기 (toggleFold) — 접힘 기억(this.folded · opts.onFold)은 건드리지 않습니다 */
    _boardFold(trackId, force) {
      const on = force == null ? !this._foldedNow(trackId) : !!force;
      if (trackId === BOARD_ID) this._boardFolded = on;
      else if (on) this._boardOpen.delete(trackId);
      else this._boardOpen.add(trackId);
      if (!this._pressHold) this._pressHold = { trackId, row: -1 };
      this.relayout();
    }

    /** 날짜 칸(연호 · 도읍 묶음)이 도는 트랙 — 판 트랙은 빼고, 원래 트랙은 옮기기 전의 나라 목록(axisPeriods)으로 */
    _axisTracks() {
      return this.tracks.filter(tr => !tr.board);
    }

    /** setData 안(트랙마다 나라 · 사건 · 인물을 나눈 뒤 · 배치 전): 판을 켰으면 판 트랙을 지어 맨 앞에 넣습니다.
        줄은 지금 규칙의 배치(민족 묶음 접힘만 풀고 — 접힌 묶음 줄이 아니라 제 사슬 줄)로 한 번 먼저 짓고, 구성 나라의 줄을 떠 옵니다 */
    _boardPlan() {
      this._boardTr = null;
      this._boardUids = null;
      const v = this.board;
      if (!v) return;
      const owner = new Map(); // 정권 uid → 지금 그 정권을 든 트랙
      for (const tr of this.tracks) for (const p of tr.periods) owner.set(p.uid, tr);
      const keep = this.foldedPeoples;
      const laid = new Set();
      const plan = [];
      const taken = new Set(); // '트랙#줄' — 같은 줄에 든 둘째 나라는 첫째의 줄에 함께
      this.foldedPeoples = new Set();
      try {
        for (const uid of v.members) {
          const tr = owner.get(uid);
          if (!tr) continue; // 거르기로 숨었거나 켜지 않은 DLC의 나라 — 판에서는 빠짐
          if (!laid.has(tr)) {
            this._layoutTrack(tr);
            laid.add(tr);
          }
          let q = tr.periods.find(p => p.uid === uid);
          while (q && q._hidden) q = q._host; // 상위 띠 아래 숨은 소속은 그 상위의 줄째로
          if (!q || q._row == null) continue;
          const key = `${tr.id}#${q._row}`;
          if (taken.has(key)) continue;
          taken.add(key);
          const list = (tr.rowPeriods[q._row] || []).filter(p => !p._hidden);
          if (list.length) plan.push({ tr, row: q._row, periods: list });
        }
      } finally {
        this.foldedPeoples = keep;
      }
      if (!plan.length) return; // 구성 나라가 하나도 보이지 않으면 판 트랙 없이 지금 모습 그대로 (켜진 판은 남음 — 거르기를 풀면 다시 섬)
      /* 줄에 딸린 것: 그 줄 정권 아래의 소속(숨었든 펼쳤든 — 판 트랙에서 다시 상위 아래로), 그 줄에 깔린 바탕 문화 · 얹힌 기관 */
      const moved = new Set();
      const rowsOf = new Map();
      for (const r of plan) {
        r.periods.forEach(p => moved.add(p));
        if (!rowsOf.has(r.tr)) rowsOf.set(r.tr, new Set());
        rowsOf.get(r.tr).add(r.row);
      }
      for (const [tr, rows] of rowsOf)
        for (let grew = true; grew; ) {
          grew = false;
          for (const p of tr.periods) {
            if (moved.has(p)) continue;
            if ((p._host && moved.has(p._host)) || ((p._under || p._overlay) && p._row != null && rows.has(p._row))) {
              moved.add(p);
              grew = true;
            }
          }
        }
      const uids = new Set([...moved].map(p => p.uid));
      const peopleOf = p => {
        const pe = (p.peoplePath || [])[(p.peoplePath || []).length - 1];
        if (pe) return { id: pe.id, name: pe.name, color: pe.color || p.peopleColor || null };
        return p.polityKind === 'culture' ? { id: '__culture', name: '문화', color: null, culture: true } : null;
      };
      const present = v.members.filter(uid => owner.has(uid));
      const label = `집합 보기 · 트랙 ${new Set(present.map(uid => owner.get(uid).id)).size} · 나라 ${present.length}`;
      const btr = { id: BOARD_ID, name: '집합 보기', color: v.color || '#d7c18e', order: -1e9, periods: [], events: [], figures: [], board: { view: v, label, rows: [] } };
      for (const r of plan) {
        const pe = peopleOf(r.periods[0]);
        btr.board.rows.push({ periods: r.periods, track: r.tr.id, trackName: r.tr.name, trackColor: r.tr.color, people: pe && Object.assign(pe, { color: pe.color || r.tr.color }), first: 0, count: 0 });
      }
      for (const tr of rowsOf.keys()) {
        tr.axisPeriods = tr.periods; // 날짜 칸은 원래 트랙의 묶음 그대로 (_buildAxis)
        tr.periods = tr.axisPeriods.filter(p => !moved.has(p));
        btr.periods.push(...tr.axisPeriods.filter(p => moved.has(p)));
        const stay = [];
        for (const e of tr.events) (uids.has(e._place ? e._place.polityUid : e.polityUid) ? btr.events : stay).push(e);
        tr.events = stay;
        const fstay = [];
        for (const x of tr.figures || []) (x.s && x.s.polity && uids.has(x.s.polity.uid) ? btr.figures : fstay).push(x);
        tr.figures = fstay;
      }
      this.tracks.unshift(btr);
      this._boardTr = btr;
      this._boardUids = uids;
    }

    /** 판 트랙의 줄 만들기 (_layoutTrack 2단계 — 민족 나무의 visit 대신): 떠 온 줄을 차례대로, 줄마다 그 아래 펼친 소속 줄(pushMembers)과 함께.
        상위가 판에 있는 소속은 상위 아래에서 한 번만(그 소속을 따로 고른 줄에서는 뺌). 같은 줄의 곧바로 이어지는 승계 쌍(이음매)은 chainRows와 같은 규칙으로 다시 적음 */
    _boardVisit(tr, rowList, pushMembers) {
      for (const r of tr.board.rows) {
        r.first = rowList.length;
        const list = r.periods.filter(p => !p._member && !p._hidden && !p._under && !p._overlay);
        for (let k = 1; k < list.length; k++) {
          const q = list[k - 1];
          const p = list[k];
          if (!q.endUnknown && !p.startUnknown && !q.endRange && !p.startRange && (p.predecessors || []).some(e => e.from === q)) {
            q._seamR = p;
            p._seamL = q;
          }
        }
        if (list.length) {
          rowList.push({ periods: list, node: null });
          list.forEach(pushMembers);
        }
        r.count = rowList.length - r.first;
      }
    }

    /** 판 트랙의 왼쪽 칸 묶음: 원래 트랙 칩(첫 단 — from) · 제 민족 칩(둘째 단). 같은 트랙(같은 민족)이 이어진 줄은 하나로 — 접지 않음 */
    _boardGroups(tr) {
      const out = [];
      const rows = tr.board.rows.filter(r => r.count);
      let run = null;
      for (const r of rows) {
        if (run && run.track === r.track) run.count = r.first + r.count - run.first;
        else out.push((run = { key: `__from:${r.track}`, name: r.trackName, color: r.trackColor, depth: 0, first: r.first, count: r.count, folded: false, culture: false, from: true, track: r.track }));
      }
      let pr = null;
      for (const r of rows) {
        const k = r.people ? `${r.track}|${r.people.id}` : null;
        if (!k) {
          pr = null;
          continue;
        }
        if (pr && pr.k === k) pr.count = r.first + r.count - pr.first;
        else out.push((pr = { k, key: r.people.id, name: r.people.name, color: r.people.color, depth: 1, first: r.first, count: r.count, folded: false, culture: !!r.people.culture }));
      }
      return out;
    }

    /** 판 트랙의 테두리 하나 (대범위 가지와 같은 꼴 — _scopePad · _scopeBox · _placeScopes · _drawScopes가 그대로 씀, 가로는 _scopeX가 화면 전체로) */
    _boardBranch(tr) {
      tr._bundled = new Set();
      const n = tr.rowPeriods.length;
      if (!n) return [];
      const v = tr.board.view;
      const has = v.start != null && isFinite(v.start);
      const s = { uid: BOARD_ID, name: v.name || '집합 보기', label: tr.board.label, color: tr.color, start: has ? v.start : 0, endY: has ? (v.end != null && isFinite(v.end) ? v.end : v.start) : 0, rangeFrom: has ? undefined : 'members', temp: !!v.temp };
      return [{ s, uid: BOARD_ID, first: 0, count: n, host: null, hostRow: -1, hung: false, list: tr.rowPeriods.flat(), box: null, board: true }];
    }

    /** 판을 켠 뒤: 판의 머리가 화면 위에 오게 (보던 고른 줄이 판 안에 있으면 그 줄이 먼저 — 닻) */
    _boardReveal() {
      const btr = this._boardTr;
      if (!btr || !btr.el) return;
      const a = this.anchorUid ? this._anchorLane() : null;
      if (a && a.tr === btr) return;
      if (this.bodyEl.scrollTop > 0.5) this._bringRow(btr, -1, 0);
    }

    /** 판을 끈 뒤: 켜기 전에 보던 줄을 그때의 화면 자리로 (그 트랙이 없어졌거나 접혔으면 트랙 위쪽) */
    _boardReturn() {
      const k = this._boardBack;
      this._boardBack = null;
      const tr = k ? this.tracks.find(t => t.id === k.id) : null;
      if (!tr || !tr.el) return;
      const a = this.anchorUid ? this._anchorLane() : null;
      if (a) return;
      const row = k.row >= 0 && !tr.folded && tr.laneEls && tr.laneEls[k.row] ? k.row : -1;
      this._bringRow(tr, row, k.off);
    }

    /* ---------- 대범위 (docs/구상-체제-확장.md 7-1 · 7-2 · 7-4 · 8-4 바 · 사) ----------
       흩어진 정권들을 한 집합으로 묶어 켜고 끕니다. 켜면 구성 정권이 제 민족 묶음을 떠나 합성 가지(__scope:<uid>)로 모이고(뿌리 바로 아래 —
       상징적 본국이 있으면 본국 줄 바로 아래), 가지 둘레에 집합 테두리(.tl-scope — 띠 뒤 · 몸통은 누를 수 없고 이름표만 누름)가 생깁니다.
       세로 자리는 짓기와 빈 줄 접힘(_placeScopes — _buildTracks · _collapseRows), 가로 자리는 매 그리기(_drawScopes — 화면 안으로 잘라 clip-l/r).
       본국 띠의 할거기 칠(z-hollow)과 '▸ 〈성격〉 n' 단추는 대범위를 꺼 두어도 보입니다. 켜고 끌 때 줄이 모여들고 흩어지는 움직임(7-3)은 아래 '모여드는 움직임' 덩어리 */

    /** 대범위가 켜져 있는가 — 기록(scopesOn)이 없으면 대범위의 default */
    scopeOn(s) {
      const v = s ? this.scopesOn[s.uid] : null;
      return v == null ? !!(s && s.default) : !!v;
    }

    /** 대범위 모아 보기 켜기/끄기 (force: true · false · 없으면 뒤집기). 켤 때는 그 가지의 접힘 기억을 지워 늘 펼친 채 모입니다.
        모여드는 움직임(7-3): 다시 지을 때 스크롤은 0px — 트랙 위쪽을 붙잡고, 창이 열린 항목의 닻은 비워 새 자리를 기준으로 삼습니다(줄들은 옛 자리에서 흘러감).
        누른 본국 줄 · 구성 정권이 아닌 고른 줄은 그다음 _gatherHold가 제자리에 붙잡습니다(스크롤이 한 번에 뛰지 않고 모여듦과 같은 곡선으로 따라감).
        옛 자리는 여기서 다시 짓기 직전에 화면 좌표로(진행 중인 이동까지), 새 자리는 _applyFlip 뒤에 잽니다(_gather). 줄 번호로 이어받는 빈 줄 접힘의 기억은 끊고(줄 번호가 바뀜),
        정권마다 '밀려남 알림'은 띄우지 않습니다(relayout을 거치지 않고 _jump를 비움 — 켠 테두리가 화면 밖이면 데려오기로 대신). 동작 줄이기면 누른 본국 줄 · 닻을 그 자리에 두고 즉시 */
    toggleScope(uid, force) {
      const s = (this.scopes || []).find(x => x.uid === uid);
      if (!s) return false;
      const on = force == null ? !this.scopeOn(s) : !!force;
      const was = this.scopeOn(s);
      this.scopesOn[uid] = on;
      if (on && this.foldedPeoples.delete(`${s.track}|__scope:${uid}`) && this.opts.onFoldPeople) this.opts.onFoldPeople([...this.foldedPeoples]);
      if (on !== was && this._data) {
        if (on) this._scopeBorn = uid; // 테두리 · 왼쪽 칸은 이번 짓기 한 번만 --t-in으로 떠오름
        const tr = this.tracks.find(t => t.id === s.track);
        const press = this._pressHold; // 본국 띠의 단추를 눌렀으면 그 줄 (_bind)
        const pressed = !!(s.host && press && press.trackId === s.track && press.row >= 0);
        const still = reduceMotion();
        this._pressHold = still && pressed ? { trackId: s.track, row: press.row, uid: s.host.uid } : { trackId: s.track, row: -1 };
        cancelAnimationFrame(this._anchorRaf); // 앞선 데려오기 · 모여듦의 붙잡기는 여기까지 — 이번 손짓이 새로 겁니다
        this._held = null;
        if (!still) this._anchorOff = this._anchorSpring = this._anchorTo = null;
        this._jump = null;
        this._gatherReq = Object.assign(this._gatherFirst(tr, s, on), { pressUid: pressed ? s.host.uid : null, pressOff: null });
        /* 동작 줄이기에서 창이 열려 있으면 다시 짓기는 닻을 붙잡으므로, 누른 본국 줄의 지금 자리를 적어 두었다가 그 자리로 (_pressStill) */
        const lane = still && pressed && this._anchorLane() && tr && tr.laneEls ? tr.laneEls[press.row] : null;
        if (lane) this._gatherReq.pressOff = lane.getBoundingClientRect().top - this.bodyEl.getBoundingClientRect().top;
        if (tr) tr._rowMemo = false;
        this.setData(this._data, { enter: false });
        this._settleSoon(0);
      }
      if (this.opts.onScope) this.opts.onScope(this.scopes.filter(x => this.scopeOn(x)).map(x => x.uid), { uid, on });
      return on;
    }

    /* ---------- 서고 3단 · 그릇 세 상태 (설계 4-6 #2 B · 새 앱 scopes.dart ScopeState — 계약 '세 상태는 보기 상태에 따로 적지 않는다'):
       펼침 = 켠 대범위 · 가지 펴짐 / 접음 = 켠 대범위 · 가지(`<트랙>|__scope:<uid>`) 접힘 / 풂 = 끈 대범위(구성 띠가 제 줄로 · 띠 위에 열쇠표). 메이커의 오른쪽 클릭 차림표(viewer.js menuItems)가 씀 ---------- */
    scopeStateOf(uid) {
      const s = (this.scopes || []).find(x => x.uid === uid);
      if (!s) return null;
      if (!this.scopeOn(s)) return 'loose';
      if (this.foldedPeoples.has(`${s.track}|__scope:${uid}`)) return 'closed';
      return this.seogo && this.shelvedScopes.has(uid) ? 'shelf' : 'open'; // 선반(서고 과제 9): 펼친 채 상위 몇만 제 줄 · 나머지는 폴더 발의 작은 꼬리표
    }

    setScopeState(uid, state) {
      const s = (this.scopes || []).find(x => x.uid === uid);
      if (!s || this.scopeStateOf(uid) === state) return false;
      const shelf = state === 'shelf' && this.seogo;
      const had = this.shelvedScopes.has(uid);
      if (shelf !== had) { // 선반(서고 과제 9) — 기억은 opts.onShelf
        if (shelf) this.shelvedScopes.add(uid);
        else this.shelvedScopes.delete(uid);
        if (this.opts.onShelf) this.opts.onShelf([...this.shelvedScopes]);
      }
      if (state === 'loose') return this.toggleScope(uid, false), true;
      const key = `${s.track}|__scope:${uid}`;
      if (!this.scopeOn(s)) {
        this.toggleScope(uid, true); // 켜면서 가지는 펴짐(toggleScope가 접힘을 지움)
        if (state === 'closed') this.toggleFoldPeople(key, true);
        return true;
      }
      if (this.foldedPeoples.has(key) !== (state === 'closed')) this.toggleFoldPeople(key, state === 'closed');
      else if (shelf !== had) this._shelfRelayout(); // 펼침 ↔ 선반은 접힘이 같아 여기서 다시 배치
      return true;
    }
    /** 가지의 선반 높이(선반에 둔 구성원이 있을 때만 · 서고) */
    _shelfH(b) {
      return this.seogo && b && b.shelf && b.shelf.length ? G_SEOGO.shelfH : 0;
    }

    /** 화면 자리(clientX · clientY)를 품은 가장 안쪽의 켠 그릇(폴더 · 상자) — { uid, name, state } · 없으면 null. 오른쪽 클릭 차림표의 세 줄이 이 그릇을 바꿉니다 */
    scopeAtPoint(clientX, clientY) {
      let hit = null;
      for (const tr of this.tracks) {
        if (!tr.lanesEl || tr.folded) continue;
        for (const b of tr.scopeBranches || []) {
          if (b.board || !b.box) continue;
          const el = tr.lanesEl.querySelector(`:scope > .tl-scope[data-uid="${CSS.escape(b.uid)}"]`);
          if (!el || el.classList.contains('is-collapsed') || el.classList.contains('is-out')) continue;
          const r = el.getBoundingClientRect();
          if (clientX < r.left || clientX > r.right || clientY < r.top || clientY > r.bottom) continue;
          if (!hit || r.height < hit.h) hit = { uid: b.uid, name: b.s.name, h: r.height, state: this.scopeStateOf(b.uid) };
        }
      }
      return hit && { uid: hit.uid, name: hit.name, state: hit.state };
    }

    /** 정권(uid)이 지금 펴져 보이는 줄 (없거나 접혀 숨었으면 −1) — 다시 지을 때 그 정권의 줄을 붙잡습니다 (_resolveHold) */
    _uidRow(tr, uid) {
      const p = tr.folded ? null : tr.periods.find(q => q.uid === uid);
      if (!p || p._row == null || p._hidden) return -1;
      return tr.hiddenRows && tr.hiddenRows.has(p._row) ? -1 : p._row;
    }

    /** 자료의 대범위 목록과, 본국별 할거 구간(본국이 끝나기 전의 대범위 — 할거기 칠 · 단추) */
    /** 선반 상태만 바뀌었을 때의 다시 배치(toggleFoldPeople과 같은 길 — toggleScope 갈래의 규칙(dev-smoke: 밀려남 알림)은 선반에는 들지 않음) */
    _shelfRelayout() {
      this.relayout();
    }

    _setScopes(list) {
      this.scopes = list || [];
      this._hosted = new Map();
      for (const s of this.scopes) if (s.host && !s.afterHost) this._hosted.set(s.host.uid, (this._hosted.get(s.host.uid) || []).concat([s]));
    }

    /** 이 트랙에서 켠 대범위의 구성 정권 → 그 대범위. 한 정권이 켠 대범위 둘에 들면 먼저 시작한 쪽. 본국 · 기관 · 문화 · 왕조는 모이지 않습니다 */
    _scopeClaims(tr, inTrack) {
      const out = new Map();
      const skip = new Set(['overlay', 'culture', 'dynasty']);
      const on = (this.scopes || []).filter(s => s.track === tr.id && this.scopeOn(s)).sort((a, b) => a.start - b.start);
      /* 포개짐(리메이크 2부 · 설계 3-3): 정권마다 직접 그릇(깊은 것 → 시작 해 차례)에서 부모를 따라 올라가 **켠 첫 그릇**이 그 정권의 가지 —
         안쪽을 켜면 안쪽, 안쪽을 끄고 바깥을 켜면 바깥. 직접 그릇 여럿이면 앞의 것부터 보아 켠 조상이 있는 첫 것(예전: 켠 대범위 가운데 먼저 시작한 쪽) */
      const claim = (p, s) => {
        if (!p || skip.has(p.polityKind) || out.has(p.uid) || (s.host && s.host.uid === p.uid)) return;
        out.set(p.uid, s);
      };
      const firstOn = s => {
        for (let x = s; x; x = x.parent) if (x.track === tr.id && this.scopeOn(x)) return x;
        return null;
      };
      for (const p of inTrack.values()) {
        const direct = (p.scopes || []).filter(x => x.track === tr.id).sort((a, b) => (b.depth || 0) - (a.depth || 0) || a.start - b.start);
        for (const d of direct) {
          const s = firstOn(d);
          if (s) {
            claim(p, s);
            break;
          }
        }
      }
      for (const s of on) for (const m of s.members || []) claim(inTrack.get(m.uid), s); // 직접 구성원이 아닌 길로 든 것(옛 자료)
      return out;
    }

    /** 합성 가지 만들기: 구성 정권을 제 민족 묶음에서 빼어 대범위마다 한 가지로 (나무의 차례 · 깊이는 옮기기 전에 이미 정해 둠 — _layoutTrack 1단계).
        본국 줄에 매달 수 있으면(보이는 제 줄이 있는 본국) host를 달아 두고, 없으면 뿌리 바로 아래 */
    _scopeNodes(tr, scopeOf, nodeOf, inTrack, byStart) {
      const bySc = new Map();
      for (const p of tr.periods) {
        const s = scopeOf.get(p.uid);
        if (s) bySc.set(s, (bySc.get(s) || []).concat([p]));
      }
      const out = [];
      for (const [s, list] of bySc) {
        for (const p of list) {
          const n = nodeOf.get(p);
          const i = n ? n.periods.indexOf(p) : -1;
          if (i >= 0) n.periods.splice(i, 1);
        }
        list.sort(byStart);
        const h = s.host ? inTrack.get(s.host.uid) : null;
        const host = h && !h._hidden && !h._under && !h._overlay && !scopeOf.has(h.uid) ? h : null;
        out.push({ id: `__scope:${s.uid}`, name: s.name, color: s.color, order: -1, depth: 0, children: [], childMap: new Map(), periods: list, first: 0, count: 0, start0: Math.min(...list.map(bandStart)), scope: s, host });
      }
      return out.sort((a, b) => a.start0 - b.start0);
    }

    /** 가지의 줄 범위(테두리 · 간격 · 왼쪽 칸 이름 비키기)와, 테두리로 한 줄로 묶어 그릴 부흥선(tr._bundled — 본국이 끝난 뒤의 대범위에서 구성 정권이 revival로 본국을 가리킬 때) */
    _scopeBranches(tr, nodes) {
      tr._bundled = new Set();
      const out = nodes
        .filter(sn => sn.count)
        .map(sn => {
          const s = sn.scope;
          const list = [];
          for (let r = sn.first; r < sn.first + sn.count; r++) for (const p of tr.rowPeriods[r] || []) list.push(p);
          const host = sn.host;
          if (host && s.afterHost) for (const p of list) for (const e of p.predecessors || []) if (e.from === host && e.type === 'revival') tr._bundled.add(e); // 부흥 승계 종류는 소속 관계 쪽 가지에서 들어옵니다 — 없으면 묶을 것도 없음
          return { s, uid: s.uid, first: sn.first, count: sn.count, host, hostRow: host ? host._row : -1, hung: !!host && !s.afterHost, list, box: null, shelf: (tr._shelf && tr._shelf.get(s.uid)) || null }; // shelf: 선반에 둔 구성원(서고 과제 9)
        });
      /* 포개짐(서고만 — 감독 2026-10-24): 바깥 그릇은 제 줄과 안쪽 그릇(같은 트랙 · parent 사슬)의 줄을 모두 두름 — ef ~ ee는 넓힌 줄 범위, kids는 안쪽 가지들.
         서고가 아니면(내보내기 · 옛 화면) 넓히지 않아 배치가 그대로 */
      for (const b of out) {
        b.kids = this.seogo ? out.filter(c => c !== b && (() => { for (let x = c.s.parent; x; x = x.parent) if (x === b.s) return true; return false; })()) : [];
        b.ef = Math.min(b.first, ...b.kids.map(c => c.first));
        b.ee = Math.max(b.first + b.count, ...b.kids.map(c => c.first + c.count));
        b.depthBelow = b.kids.reduce((m, c) => { let d = 0; for (let x = c.s; x && x !== b.s; x = x.parent) d++; return Math.max(m, d); }, 0);
      }
      return out;
    }

    /** 줄 간격에 더할 대범위 몫 — _layoutTrack과 _foldRows의 두 간격 공식 끝에 똑같이 더합니다(r = 이 줄, prev = 바로 위의 펴진 줄 · 없으면 −1).
        가지의 펴진 첫 줄이면 머리(이름표 자리 — 책갈피 탭 자리 위), 본국 줄에 매달린 가지면 머리만 남기고 묶음 사이 틈은 뺌(테두리 위쪽이 본국 띠 아랫변에 붙음),
        가지가 끝난 뒤 처음 펴진 줄이면 아래 여백 */
    _scopePad(tr, r, prev) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      let pad = 0;
      for (const b of tr.scopeBranches || []) {
        const f = b.ef ?? b.first, end = b.ee ?? b.first + b.count; // 넓힌 줄 범위(포개짐 — 바깥 그릇의 머리 · 발은 안쪽 그릇의 것 바깥에 한 번 더)
        if (r >= f && r < end && prev < f) pad += b.hung && f === b.first && prev >= 0 && prev === b.hostRow ? G.scopeHead + 2 - G.gap - G.groupGap : G.scopeHead;
        else if (prev >= f && prev < end && r >= end) pad += G.scopeFoot + this._shelfH(b);
      }
      return pad;
    }

    /** 줄 r 위의 간격 가운데 대범위 테두리 머리가 차지한 몫(머리 + 책갈피 탭 자리) — 되돌아가는 승계선이 이름표를 가로지르지 않게 그 위의 빈 곳으로 (_drawLinks).
        본국 줄에 매달린 가지는 간격 전체가 머리(위 2 · 이름표 14 · 아래 2 · 탭 — _scopePad)라 남는 빈 곳이 없습니다 — 그때 _drawLinks는 반대쪽 빈 곳으로 돕니다 */
    _scopeHead(tr, r) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      let prev = -1;
      for (let k = r - 1; k >= 0; k--)
        if (!tr.hiddenRows.has(k)) {
          prev = k;
          break;
        }
      let n = 0;
      let hung = false;
      for (const b of tr.scopeBranches || []) {
        const f = b.ef ?? b.first, end = b.ee ?? b.first + b.count;
        if (r < f || r >= end || prev >= f) continue;
        n++; // 이 줄 위에 머리가 쌓이는 그릇(포개짐이면 바깥 · 안쪽 둘 이상)
        if (b.hung && prev >= 0 && prev === b.hostRow) hung = true;
      }
      if (!n) return 0;
      const tab = this._tabOf(tr, r);
      return hung && n === 1 ? G.scopeHead + 2 + tab : G.scopeHead * n + tab;
    }

    /** 테두리의 세로 자리 (펴진 줄이 없으면 null): 머리는 가지의 펴진 첫 줄의 책갈피 탭 자리 위, 본국 줄 바로 아래에 매달리면 본국 줄 아랫변부터 */
    _scopeBox(tr, b) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      const vis = (from, to) => { // 펴진 첫 · 끝 줄
        let a = -1, z = -1;
        for (let r = from; r < to; r++) {
          if (tr.hiddenRows.has(r)) continue;
          if (a < 0) a = r;
          z = r;
        }
        return [a, z];
      };
      const [fv, lv] = vis(b.ef ?? b.first, b.ee ?? b.first + b.count);
      if (fv < 0) return null;
      /* 포개짐: 같은 줄에서 시작하는 안쪽 그릇의 머리는 이 그릇의 머리 밑에, 같은 줄에서 끝나는 안쪽 그릇의 발 · 선반은 이 그릇의 발 위에 쌓임 */
      const kids = b.kids || [];
      const ranges = kids.map(c => vis(c.ef ?? c.first, c.ee ?? c.first + c.count));
      const headsIn = ranges.filter(([a]) => a === fv).length;
      const feetIn = kids.reduce((n, c, i) => (ranges[i][1] === lv ? n + G.scopeFoot + this._shelfH(c) : n), 0);
      let prev = -1;
      for (let r = fv - 1; r >= 0; r--)
        if (!tr.hiddenRows.has(r)) {
          prev = r;
          break;
        }
      const hung = b.hung && prev >= 0 && prev === b.hostRow;
      const tab = this._tabOf(tr, fv);
      const top = hung && !headsIn ? tr.rowTop[fv] - tr.rowGap[fv] : tr.rowTop[fv] - tab - G.scopeHead * (1 + headsIn);
      return { top, height: tr.rowTop[lv] + tr.rowHs[lv] + feetIn + G.scopeFoot + this._shelfH(b) - top, hung: hung && !headsIn, tab }; // tab = 첫 줄의 탭 자리 그대로(몸통 윗변 --bodyTop = tab + 5 — 포개진 바깥 그릇은 top이 머리 하나만큼 위라 몸통도 그만큼 위)
    }

    /** 테두리 요소 (띠 뒤 · .tl-lanes 바로 아래) — 자리는 _placeScopes · _drawScopes가 씁니다 */
    _scopesHTML(tr) {
      return (tr.scopeBranches || [])
        .map(b => {
          const s = b.s;
          if (b.board) return `<div class="tl-scope is-board" style="--sc:${s.color}"><i class="tl-scope-span" hidden></i><button type="button" class="tl-scope-name" data-board-name title="${esc(`${s.name} — 집합 보기${s.temp ? ' (저장하지 않은 판)' : ''} · 누르면 집합 보기 목록`)}"><b>${esc(s.name)}</b><small>${esc(s.label)}</small></button></div>`; // 집합 보기: 이름표를 누르면 판 목록 (opts.onBoardName)
          const tip = `${s.name}${s.label ? ` · ${s.label}` : ''} (${HT.formatRange(s)}) — 대범위 · 누르면 상세`;
          const box = this.seogo && s.parent && s.parent.track === s.track && this.scopeOn(s.parent); // 안쪽 그릇 = 상자(서고 과제 9 — 모따기 · 뚜껑 밑선 · 흰 라벨)
          return `<div class="tl-scope${this._scopeBorn === b.uid ? ' is-born' : ''}${box ? ' is-box' : ''}" data-uid="${esc(b.uid)}" style="--sc:${s.color}"><i class="tl-scope-span" hidden></i><button type="button" class="tl-scope-name" title="${esc(tip)}"><b>${esc(s.name)}</b>${s.label ? `<small>${esc(s.label)}</small>` : ''}</button></div>`;
        })
        .join('');
    }

    /** 테두리의 세로 자리 (짓기 · 빈 줄 접힘 — 줄과 같은 곡선 · 길이로 흐름) */
    _placeScopes(tr) {
      if (!tr.el || tr.folded || !tr.lanesEl) return;
      const els = tr.lanesEl.querySelectorAll(':scope > .tl-scope');
      (tr.scopeBranches || []).forEach((b, i) => {
        const el = els[i];
        if (!el) return;
        const box = (b.box = this._scopeBox(tr, b));
        el.classList.toggle('is-collapsed', !box);
        el.classList.toggle('is-hung', !!box && box.hung);
        if (!box) return;
        el.style.top = `${cx(box.top)}px`;
        el.style.height = `${cx(box.height)}px`;
        if (this.seogo) el.style.setProperty('--bodyTop', `${box.hung ? 0 : box.tab + 5}px`); // 서고 3단: 폴더 몸통 윗변 = 첫 띠 윗변 위 16(머리 21 + 탭 자리 − 16) · 어깨 탭은 그 위 20 (common.css 서고 3단)
      });
    }

    /** 테두리의 가로 범위(xl ~ xr — 구성 정권 띠 전체 + 여백) · 화면에 쓸 자리(−1 ~ W+1로 자름) · 이름표 모양(full · short · off).
        _drawScopes가 그리고, _drawLinks가 이름표를 비켜 가는 데(_scopeLabelRect) 같은 값을 씁니다 */
    _scopeX(b, X, W) {
      if (b.board) return { xl: -2, xr: W + 2, out: false, left: -1, width: W + 2, mode: 'full', nameW: this._bird ? textWidth(b.s.name, 9, 700) + 10 : textWidth(b.s.name, 10, 700) + 12 }; // 집합 보기: 가로 전체(기간이 아니라 보는 방법 — 이름표가 물러나지 않음) · 양쪽 모서리를 폄
      let xl = Infinity;
      let xr = -Infinity;
      for (const p of b.list.concat(...(b.kids || []).map(c => c.list))) { // 포개짐: 바깥 그릇은 안쪽 그릇의 띠까지
        xl = Math.min(xl, X(bandStart(p)) - (p.startUnknown ? FADE : 0));
        xr = Math.max(xr, X(bandEnd(p)) + (p.endUnknown ? FADE : 0));
      }
      xl -= G.scopePadX * (1 + (b.depthBelow || 0));
      xr += G.scopePadX * (1 + (b.depthBelow || 0));
      const left = Math.max(xl, -1);
      const width = Math.max(4, Math.min(xr, W + 1) - left);
      const room = width - 16;
      const nameW = this._bird ? textWidth(b.s.name, 9, 700) + 10 : textWidth(b.s.name, 10, 700) + 12; // 조감의 이름표는 9px · 높이 11 (대범위 머리 12px 안)
      const mode = xl < -1 || room < nameW ? 'off' : b.s.label && room < nameW + textWidth(b.s.label, this._bird ? 8 : 9) + 4 ? 'short' : 'full';
      return { xl, xr, out: xr < -2 || xl > W + 2, left, width, mode, nameW };
    }

    /** 이름표(.tl-scope-name — 테두리 안쪽 왼쪽 8px · 위 2px · 높이 14)의 화면 자리 { l, r, t, b } — 물러났거나 테두리가 없으면 null.
        승계선 · 소속선 그림은 테두리보다 위 층이라, 선이 이 자리를 지나면 이름 글자를 덮습니다 (_drawLinks가 비켜 감) */
    _scopeLabelRect(b, X, W) {
      if (!b.box) return null;
      const g = this._scopeX(b, X, W);
      if (g.out || g.mode === 'off') return null;
      const l = g.left + 1 + 8;
      const w = Math.min(g.mode === 'full' && b.s.label ? g.nameW + 4 + textWidth(b.s.label, this._bird ? 8 : 9) : g.nameW, g.width - 18);
      return this._bird ? { l, r: l + w, t: b.box.top + 0.5, b: b.box.top + 11.5 } : { l, r: l + w, t: b.box.top + 2, b: b.box.top + 16 };
    }

    /** 테두리의 가로 자리 (매 그리기): 가로 = 구성 정권 띠 전체의 범위(+ 여백) — 오래 간 나라도 띠가 테두리를 뚫고 나가지 않습니다.
        화면 밖은 −1 ~ W+1로 잘라 그쪽 모서리를 펴고(clip-l/r · 전환 없음), 대범위의 기간은 조금 더 짙은 세로 구간.
        이름표는 테두리 왼쪽 끝이 화면 안일 때만 — 밖으로 나가면 옅어지며 물러나고, 그때는 왼쪽 세로 칸이 이름을 말합니다.
        부흥선(본국의 멸망 네모에서 테두리로 한 줄)은 승계선과 함께 _linkPlan이 그립니다 (_bundleLine) */
    _drawScopes(tr, X, W) {
      if (!tr.lanesEl || !(tr.scopeBranches || []).length) return;
      const els = tr.lanesEl.querySelectorAll(':scope > .tl-scope');
      tr.scopeBranches.forEach((b, i) => {
        const el = els[i];
        if (!el || !b.box) return;
        const { xl, xr, out, left, width, mode } = this._scopeX(b, X, W);
        el.classList.toggle('is-out', out);
        if (out) return;
        el.style.left = `${cx(left)}px`;
        el.style.width = `${cx(width)}px`;
        el.classList.toggle('clip-l', xl < -1);
        el.classList.toggle('clip-r', xr > W + 1);
        const span = el.querySelector('.tl-scope-span');
        if (span) {
          const bw = xl < -1 ? 0 : 1; // 안쪽 칸은 테두리 안쪽(padding box)에서 잽니다
          const inner = width - bw - (xr > W + 1 ? 0 : 1);
          const a = HT.clamp(X(b.s.start) - left - bw, 0, inner);
          const c = HT.clamp(X(b.s.endY) - left - bw, 0, inner);
          const show = b.s.rangeFrom !== 'members' && c - a >= 1 && (a > 0.5 || c < inner - 0.5); // 짐작한 기간(구성 정권의 범위)이나 테두리 전체와 같은 기간이면 따로 칠하지 않음
          span.hidden = !show;
          if (show) {
            span.style.left = `${cx(a)}px`;
            span.style.width = `${cx(c - a)}px`;
          }
        }
        /* 선반(서고 과제 9): 폴더 발의 작은 꼬리표 줄 — 테두리 안쪽 6 ~ 6 · 자리가 막히면 '+n' */
        let shelf = el.querySelector('.tl-shelf');
        if (b.shelf && b.shelf.length) {
          if (!shelf) {
            shelf = document.createElement('span');
            shelf.className = 'tl-shelf';
            el.appendChild(shelf);
          }
          const html = this._stagsHTML(b.shelf, y => X(y) - left - 6, width - 12, 0, 0, ' data-shelf="1"', width - 12);
          if (shelf._html !== html) {
            shelf.innerHTML = html;
            shelf._html = html;
          }
        } else if (shelf) shelf.remove();
        const name = el.querySelector('.tl-scope-name');
        if (name) {
          /* 이름표가 테두리 안에 들어가지 않으면(좁은 테두리) 성격 → 이름 순으로 줄이고, 그래도 안 되면 물러남 — 테두리 밖으로 나가지 않게 (왼쪽 세로 칸이 이름을 말함 · 모양은 _scopeX) */
          const fresh = !name._drawn; // 새로 지어진 테두리의 첫 그리기: 물러나 있을 이름표는 전환 없이 처음부터 (떠오르는 테두리 안에서 보였다가 옅어지는 둘째 움직임이 없게)
          if (fresh) name.style.transition = 'none';
          name.classList.toggle('is-off', mode === 'off');
          name.classList.toggle('is-short', mode === 'short');
          if (fresh) {
            void getComputedStyle(name).opacity; // 전환 없이 한 번 확정한 뒤 전환을 되돌림
            name.style.transition = '';
            name._drawn = true;
          }
        }
        /* 부흥선 한 줄은 승계선과 함께 그립니다 (_bundleLine → _linkPlan — 그림 내보내기도 같은 자리) */
      });
    }

    /** 대범위 부흥선: 본국의 멸망 네모에서 테두리로 한 줄 (구성 정권마다가 아니라 — tr._bundled). 그리지 않으면 null,
        아니면 { d, end(고리 자리), x1, y1(선이 나가는 곳), host, kind, color, from, to, tip } — 화면(_drawLinks)과 그림 내보내기(toSVG)가 같은 것을 씁니다 */
    _bundleLine(tr, b, X, W) {
      const host = b.host;
      if (!b.box || !this.show.succession || this.show.succession === 'direct' || !host || !b.s.afterHost || host._row == null || host._folded || tr.hiddenRows.has(host._row)) return null; // '직접 승계만'이면 부흥선(직접이 아님)도 숨김 (_linkPlan과 같게)
      if (!b.list.some(p => (p.predecessors || []).some(e => tr._bundled.has(e)))) return null;
      const { xl, xr, out } = this._scopeX(b, X, W);
      if (out) return null;
      const half = G.sq / 2 + 1;
      const x1 = this._bird ? (host.endUnknown ? X(host.endY) : X(bandEnd(host)) - STUB) : this._squares(host, X, ((tr.geos && tr.geos[host._row]) || tr.geo).lines, W).ec + half; // 조감: 띠 끝의 짧은 끝에서 (_linkPlan의 관문)
      const y1 = this._anchorY(tr, host._row);
      const y2 = b.box.top + this._G().scopeHead / 2;
      const x2 = Math.max(xl, -20);
      let xm = X(bandEnd(host)) + (host.endUnknown ? FADE : 0) + 9;
      /* 세로로 내려오는 길이 같은 트랙의 다른 가지의 이름표를 곧게 지나면 그 이름표 오른쪽으로 비켜 내려옵니다 (승계선 · 소속선과 같은 규칙 — 테두리 안에 닿을 자리가 있을 때만) */
      const labs = tr.scopeBranches.filter(o => o !== b).map(o => this._scopeLabelRect(o, X, W)).filter(Boolean);
      const labAt = (xa, ya, yb) => labs.find(r => xa > r.l - 2 && xa < r.r + 2 && Math.max(ya, yb) > r.t - 2 && Math.min(ya, yb) < r.b + 2);
      for (let t = 0, lab; t < 4 && (lab = labAt(xm, y1, x2 >= xm + 6 ? y2 : b.box.top)); t++) {
        const nx = lab.r + 6;
        if (!(x2 >= nx + 6 || nx < xr - 16)) break;
        xm = nx;
      }
      if (Math.max(x1, x2) < -20 || Math.min(x1, xm) > W + 20) return null;
      /* 테두리가 본국 끝보다 넉넉히 오른쪽이면 테두리 왼쪽 변(머리 높이)으로, 아니면 테두리 위 변으로 내려와 닿습니다 — 이름표를 가로지르지 않게 */
      const side = x2 >= xm + 6;
      const end = side ? [x2, y2] : [xm, b.box.top];
      const d = side ? roundHV([[x1, y1], [xm, y1], [xm, y2], [x2, y2]], 6) : `M${cx(x1)} ${cx(y1)} H${cx(xm)} V${cx(end[1])}`;
      const n = b.list.filter(p => (p.predecessors || []).some(e => tr._bundled.has(e))).length;
      return { d, end, x1, y1, host, kind: succKind('revival'), color: host.color, from: host.uid, to: b.uid, tip: `${host.name} → ${b.s.name} · 부흥 (${n}개 세력)` };
    }

    /** 상징적 본국 띠의 할거기 칠 (.tl-zone 자리에 z-hollow): 그 구간만 띠 바탕의 가운데가 옅고 테두리 쪽만 남는 세로 구간 — "이름은 남았으나 실제 다스림은 흩어짐".
        본국이 이미 끝난 뒤의 대범위(부흥 운동)에는 없습니다 */
    /** 속국 이름표의 글과 설명 (화면 · 그림 공용): 이름이 다 들어가면 이름, 첫 글자만 들어가면 첫 글자, 아니면 없음.
        size = 글 크기(띠 안 품은 칸 9.5 · 매달린 탭 HANG.font 8) */
    _depLabel(it, w, size = 9.5) {
      const name = it.p.name;
      return w >= textWidth(name, size, 650) + 12 ? name : w >= textWidth(name.slice(0, 1), size, 650) + 9 ? name.slice(0, 1) : '';
    }
    _depTip(host, it, s) {
      const r = s.rel ? HT.relationInfo(s.rel) : null;
      const how = s.look === 'plain' ? ' 소속' : '에 예속';
      return `${it.p.name} — ${host.name}${how}${r ? ` (${r.name})` : ''} · ${hostRange(s.h, it.p)}${s.h.note ? ` · ${s.h.note}` : ''}`;
    }

    /** 품은 칸 (상국 띠 안 맨 아래 — 상국이 다스린 속국: 옅은 칸 괴뢰 · 위임 · 짙은 칸 식민 · 빗금 칸 점령). 줄마다 속국 하나, 같은 속국의 이어지는 구간은
        하나의 긴 둥근 칸 + 가는 구분선(layoutStrip). 속국의 빛깔 · 이름 — 누르면 그 속국(data-uid). 칸의 미정: 소속 기간의 미정인 끝이 옅어짐(unkCell) */
    _depAltRow(it, strip, outside = false, clip = {}) {
      const size = outside ? HANG.font : 9.5; // 매달린 탭(outside)은 8px · 품은 칸은 9.5px
      return strip.map(({ it: seg, l, r, jl, jr, atL, atR }, k) => {
        const w = r - l;
        const label = jl ? '' : this._depLabel(it, w - (outside ? 4 : 0), size);
        const tw = label ? textWidth(label, size, 650) : 0;
        const unk = unkCell(seg.h, k ? strip[k - 1].it.h : null, jl, w, label ? tw : null, atL && clip.l, atR && clip.r);
        const ref = `dep:${it.p.hosts.indexOf(seg.h)}`;
        return { seg, c: seg.h, l, r, w, jl, jr, atL, atR, label, unk, ref, key: `${it.p.uid}:${ref}`,
          base: { start: seg.a, end: seg.b, startUnknown: seg.h.startUnknown, endUnknown: seg.h.endUnknown },
          ink: label ? { text: label, size, wt: 650, lh: size * 1.2, c: l + (outside ? 7 : 6) + tw / 2 } : null,
          bl: 1, br: jr ? 0 : 1, fade: unkFade(unk, l, r) };
      });
    }

    /** 상국 이름 탭의 자리(건의 8의 2번 C — 화면 _hostTabs · 그림 _hostTabsSVG · 끄는 동안의 자리 _backTabPlan 공용): 모양은 예전 상국 탭 그대로, 자리는 **관계가 끝나는 쪽** —
        제 이름 탭이 띠의 평평한 윗변에 서듯 상국 탭은 뒤 장의 평평한 윗변 안에 섭니다(감독 확정 2026-10-14): 탭의 오른쪽 끝 = min(뒤 장 오른쪽 끝 − 둥근 값, 화면 오른쪽 끝 − 6) —
        뒤 장의 끝이 화면 오른쪽 밖이면 화면 안 끝에 붙어 따라옵니다(제 이름 탭이 왼쪽 끝에 붙는 것과 같은 결). 탭 왼쪽이 뒤 장 왼쪽 + 둥근 값보다 앞이거나
        제 이름 탭(from — 그 오른쪽 + 틈) · 앞 상국 탭(+ 틈)과 닿으면 그 탭은 없고 뒤 장만. 화면 왼쪽 밖에서 이미 끝난 관계는 없습니다. 새 앱 bands.dart의 _paintHostTabs와 같은 셈 → [{ x, w, seg }] */
    _hostTabPlan(p, X, W, x1, from, flatR) {
      const segs = hostSegs(p, X);
      if (!segs.length) return [];
      const flatL = Math.max(x1 + G.radius, 6);
      let prevR = Math.max(from, flatL);
      const out = [];
      for (const s of segs) {
        if (s.r < Math.max(x1, 0) + 10) continue; // 화면 왼쪽 밖에서 이미 끝난 관계
        const pl = s.l + (s.atL ? PLATE.shift : 0); // 뒤 장의 양 끝 (_hostPlates와 같은 셈)
        const pr = pl + (s.r - s.l);
        const w = textWidth(s.h.host.name, TAB.hostSize, TAB.hostWt) + 2 * (TAB.sh + 6);
        const x = Math.min(pr - PLATE.radius, W - 6) - w;
        if (x < Math.max(pl + PLATE.radius, prevR)) continue;
        out.push({ x, w, seg: s });
        prevR = x + w + TAB.gap;
      }
      return out;
    }

    /** 뒤 장의 탭의 설명글: 상국 · 관계 · 기간 */
    _hostTabTip(p, s) {
      const rel = s.rel ? HT.relationName(s.rel) : '소속';
      const to = s.h.end == null && p.ongoing ? '현재' : HT.formatDate(s.b, s.h.endAt);
      return `${s.h.host.name} — ${p.name}이(가) 섬긴 상국 · ${rel} (${HT.formatDate(s.a, s.h.startAt)} ~ ${to})${s.h.note ? ` · ${s.h.note}` : ''}`;
    }

    /** 연합의 겹 탭 자리(설계 7-8 결정 3 C + 덧판 x2 A — 화면 _hostTabs · 그림 _hostTabsSVG · 끄는 동안의 자리 _backTabPlan 공용): 구성 나라 띠의 탭 줄, 가담이 시작한 해의 자리에
        이름 폭 탭 하나(시작이 띠 첫머리 · 화면 왼쪽 밖이면 평지 첫머리 · 제 이름 탭 뒤 from). 상국 탭이 먼저 자리를 잡고(host — _hostTabPlan 그대로라 연합 탭을 더해도 상국 탭은 1px도 안 움직임),
        연합 탭은 그 자리에서 다른 탭(앉은 상국 탭 · 앞 연합 탭 — 뒤 장까지)과 TAB.gap 안으로 닿지 않고 오른쪽 평지 끝(flatR)을 넘지 않을 때만 — 아니면 이 띠에서는 그리지 않음
        (상국 탭처럼 오른쪽으로 밀지 않음: 밀면 시작 해가 어긋남 — 다른 구성 띠 · 올림 · 단체 창에서). 화면 왼쪽 밖에서 이미 끝난 가담은 없음.
        표시 체크 '단체'가 꺼져 있으면(내보내기의 연표처럼 show에 groups가 없어도) 없음 → [{ x, w(앞 장 — 요소는 w + TAB.backDx), key, c: { group, start, end, role, note } }] */
    _coalTabPlan(p, X, W, x1, from, flatR, host = []) {
      if (!this.show || !this.show.groups) return [];
      const list = HT.coalitionsOf(p);
      if (!list.length) return [];
      const flatL = Math.max(x1 + G.radius, 6);
      const taken = host.map(q => [q.x, q.x + q.w]);
      const out = [];
      for (const c of list) {
        if (!(c.end > c.start) || X(c.end) < Math.max(x1, 0) + 10) continue;
        const x = Math.max(X(c.start), flatL, from);
        const w = textWidth(c.group.name, TAB.hostSize, TAB.hostWt) + 2 * TAB.coalPad;
        const r = x + w + TAB.backDx;
        if (r > flatR || !taken.every(([a, b]) => r + TAB.gap <= a || x >= b + TAB.gap)) continue;
        out.push({ x, w, key: `ct:${p.uid}:${c.group.uid}`, c });
        taken.push([x, r]);
      }
      return out;
    }

    /** 띠 위 탭 줄의 뒤 장들(상국 탭 + 연합의 겹 탭) — 끄는 동안 자리를 다시 잡을 때(_drawTrackScene) 요소의 data-k로 찾음 → [{ x, w, key }] */
    _backTabPlan(p, X, W, x1, from, flatR) {
      const host = this._hostTabPlan(p, X, W, x1, from, flatR);
      return host.map(q => ({ x: q.x, w: q.w, key: `ht:${p.uid}:${q.seg.k}` })).concat(this._coalTabPlan(p, X, W, x1, from, flatR, host));
    }

    /** 연합 탭의 설명글: 연합 이름 · 구성 나라 · 이 나라의 가담 기간 (글 딱지는 띠 위에 두지 않고 풍선에만) */
    _coalTabTip(p, c) {
      const g = c.group;
      const members = (g.memberList || []).map(m => m.name).filter(Boolean);
      return `${g.name} — 연합 · 구성 ${members.join(' · ')} · ${p.name}의 가담 ${HT.formatYear(c.start)} ~ ${HT.formatYear(c.end)}${c.role ? ` · ${c.role}` : ''}${c.note ? ` · ${c.note}` : ''} — 올리면 구성 나라 모두 진하게 · 누르면 단체 창`;
    }

    /** 상국 이름 탭(화면 — 건의 8의 2번 C): 제 이름 탭과 같은 높이(G.tab)의 탭이 PLATE.tabRise만큼 올라 뒤 장의 윗변에 섭니다.
        칠 · 테는 그 뒤 장과 같고, 뒤 장(z −3)보다 한 층 위(.tl-htab z −2 — common.css '뒤 장')에서 아래 1px(G.bw)로 뒤 장의 윗변 선을 덮어 탭과 뒤 장이 한 덩어리 윤곽(이음매 선 없음 — 감독 2026-10-14).
        올리면 같은 트랙의 상국 띠도 진해집니다(data-uid = 상국). 그 뒤에 연합의 겹 탭(.tl-htab.k-coal — 올리지 않고 예전 자리 · 층 그대로 · data-uid = 연합 단체: 누르면 단체 창 ·
        data-coal: 올리면 구성 나라 모두 진하게 _coalHover) */
    _hostTabs(p, X, W, x1, from, flatR) {
      let out = '';
      const host = this._hostTabPlan(p, X, W, x1, from, flatR);
      /* 서고 3단: 이름 색줄이 띠 안에 있으므로 상국 탭 · 연합 탭은 띠 위 받침 카드(6) 위에 솟는 낮은 탭(높이 12 — 새 앱 TagLook.tabH) · 그 줄은 올림 15(_tabOf) */
      const th = this._seogoOn() ? 12 : TAG.head;
      const tt = this._seogoOn() ? -(PLATE.rise + 1 + 12) : -TAG.head;
      for (const { x, w, seg: s } of host)
        out += `<i class="tl-htab is-${s.look}" data-k="ht:${esc(p.uid)}:${s.k}" data-uid="${esc(s.h.host.uid)}" data-row="${p._row}" data-band="${esc(p.uid)}" title="${esc(this._hostTabTip(p, s))}" style="left:${cx(x)}px;top:${tt}px;width:${cx(w)}px;height:${th}px;--c:${s.h.host.color}">${tabSvg(w, th, TAB.sh)}<b>${esc(s.h.host.name)}</b></i>`;
      for (const { x, w, key, c } of this._coalTabPlan(p, X, W, x1, from, flatR, host))
        out += `<i class="tl-htab k-coal${this._coalHot === c.group.uid ? ' is-coal-on' : ''}" data-k="${esc(key)}" data-uid="${esc(c.group.uid)}" data-coal="${esc(c.group.uid)}" data-row="${p._row}" data-band="${esc(p.uid)}" title="${esc(this._coalTabTip(p, c))}" style="left:${cx(x)}px;top:${tt}px;width:${cx(w + TAB.backDx)}px;height:${th}px;--c:${c.group.color}">${coalTabSvg(w, th)}<b>${esc(c.group.name)}</b></i>`;
      return out;
    }

    /** 뒤 장(화면 — 건의 8의 2번 C · 감독 확정 2026-10-14 '옆은 맞추고 위로만 5px'): 속국 띠 뒤(.tl-plate z −3 — 제 이름 탭 · 띠 아래 · 상국 탭 위)에 상국 빛깔의 종이 한 장씩 —
        띠와 같은 높이 · 둥근 10, 가로는 관계의 시작 ~ 끝(PLATE.shift 0 — 띠 끝 밖으로 나오지 않음), PLATE.rise만큼 위로 어긋나 띠 위로 그만큼 드러남.
        같은 상국 아래에서 관계만 바뀌면(jl · jr) 맞닿은 쪽은 모서리 · 테 없이 이어지고 짙기만 바뀜. 뒤 장들 다음에 띠 자리의 종이빛 받침(.tl-plate-back — 띠와 같은 자리 · 같은 모서리,
        둘레로 --tl-plate-gap의 틈): 띠가 뒤 장 위에 살짝 떠 보이고, 흐린 띠(고름 · 강조) 너머로 뒤 장이 비치지 않음.
        드러난 윗단에 올리면 풍선 '상국 · 관계 · 기간'(상국 탭과 같은 글) · 누르면 상국 상세 · 같은 트랙의 상국 띠가 진해짐(data-uid = 상국 — 상국 탭과 같은 길). 화면 밖으로 멀리 뻗은 쪽은 2 × 둥근 값까지만 */
    _hostPlates(p, X, W, bl, bw, bcls, lift = 0) {
      const lv = lift ? `;--lift:${lift}px` : ''; // 서고: 속국 띠의 몸통 아랫변을 올린 몫 — 뒤 장 · 받침도 띠와 같은 키(common.css)
      const segs = hostSegs(p, X);
      if (!segs.length) return '';
      const ext = 2 * PLATE.radius;
      let out = '';
      for (const s of segs) {
        const l0 = s.l + (s.atL ? PLATE.shift : 0);
        const r0 = l0 + (s.r - s.l);
        if (r0 < -ext || l0 > W + ext || r0 - l0 < 1) continue;
        const l = Math.max(l0, -ext);
        const r = Math.min(r0, W + ext);
        out += `<i class="tl-plate is-${s.look}${l > l0 ? ' clip-l' : ''}${r < r0 ? ' clip-r' : ''}${s.jl ? ' j-l' : ''}${s.jr ? ' j-r' : ''}" data-k="pl:${esc(p.uid)}:${s.k}" data-uid="${esc(s.h.host.uid)}" data-row="${p._row}" data-band="${esc(p.uid)}" title="${esc(this._hostTabTip(p, s))}" style="left:${cx(l)}px;width:${cx(r - l)}px;top:${this._seogoOn() ? -(PLATE.rise + 1) : -(G.tab - 1)}px;--c:${s.h.host.color}${lv}"></i>`; // 한 장 꼬리표: 이름 색줄 위로 탭 자리의 남은 몫만큼 비침(서고 모양 2단 나-1) · 서고 3단: 띠 윗변 위로 받침 카드 6
      }
      if (out) out += `<i class="tl-plate-back${bcls}" data-k="pb:${esc(p.uid)}" style="left:${cx(bl)}px;width:${cx(bw)}px${lv}"></i>`;
      return out;
    }

    /** 띠 둘레의 종이빛 틈(px — 그림 내보내기): css 변수 --tl-plate-gap(:root — 감독 확인 그림의 '틈 있음 · 없음'을 같은 코드로 · 화면은 css가 바로 씀) · 읽을 수 없으면 PLATE.gap */
    _plateGap() {
      try {
        const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--tl-plate-gap'));
        return Number.isFinite(v) ? Math.max(0, v) : PLATE.gap;
      } catch (_) {
        return PLATE.gap;
      }
    }

    /** 뒤 장(그림 내보내기): 화면과 같은 자리(hostSegs) · 같은 칠(상국 색의 몫 — oklab) · 같은 테 · 같은 이음(jl · jr), 그다음 띠 자리의 종이빛 받침(띠 + 틈).
        상국 탭(_hostTabsSVG 'host') · 제 이름 탭 · 띠보다 먼저 그려 그 아래 층에 */
    _hostPlatesSVG(p, X, W, GW, y, bandH, rl, rr, PAPER, INK, gap) {
      const segs = hostSegs(p, X);
      if (!segs.length) return '';
      const n = v => Number(v).toFixed(2).replace(/\.?0+$/, '');
      const ext = 2 * PLATE.radius;
      const R = PLATE.radius;
      let svg = '';
      for (const s of segs) {
        const l0 = s.l + (s.atL ? PLATE.shift : 0);
        const r0 = l0 + (s.r - s.l);
        if (r0 < -ext || l0 > W + ext || r0 - l0 < 1) continue;
        const l = Math.max(l0, -ext);
        const r = Math.min(r0, W + ext);
        const c = s.h.host.color;
        const k = PLATE.mix[s.look] || 0;
        const dash = s.look === 'nominal' ? ' stroke-dasharray="1 2"' : s.look === 'plain' ? ' stroke-dasharray="3 2"' : '';
        /* 둥근 네모(맞닿은 쪽은 모서리 · 세로 테 없이). 아랫변 쪽은 띠 자리의 받침이 덮으므로 테는 윗변과 양옆만(⊓ 꼴) */
        const t = y - PLATE.rise + 0.5;
        const b = t + Math.max(1, bandH - 1);
        const L = GW + l + (s.jl ? 0 : 0.5);
        const Rr = GW + r - (s.jr ? 0 : 0.5);
        const rL = s.jl ? 0 : R - 0.5;
        const rR = s.jr ? 0 : R - 0.5;
        const d = `${s.jl ? `M${n(L)},${n(t)}` : `M${n(L)},${n(b)} V${n(t + rL)} A${n(rL)},${n(rL)} 0 0 1 ${n(L + rL)},${n(t)}`} H${n(Rr - rR)}${s.jr ? '' : ` A${n(rR)},${n(rR)} 0 0 1 ${n(Rr)},${n(t + rR)} V${n(b)}`}`;
        if (k) svg += `<path d="${d}${s.jr ? ` L${n(Rr)},${n(b)}` : ''} L${n(L)},${n(b)} Z" fill="${mixOk(c, PAPER, k)}"/>`;
        svg += `<path d="${d}" fill="none" stroke="${mixOk(c, INK, PLATE.edge)}"${dash}/>`;
      }
      if (svg) svg += `<rect x="${n(GW + rl - gap)}" y="${n(y - gap)}" width="${n(Math.max(2, rr - rl) + 2 * gap)}" height="${n(bandH + 2 * gap)}" rx="${n(G.radius + gap)}" fill="${PAPER}"/>`;
      return svg;
    }

    /** 상국 이름 탭(그림 내보내기): 화면과 같은 자리 · 같은 윤곽 · 같은 높이(G.tab · PLATE.tabRise) · 뒤 장과 같은 칠 · 테. part = 'host'(상국 탭 — 뒤 장 다음에 그려 그 윗변 선을 덮음) ·
        'coal'(연합의 겹 탭 — 뒤 장 다음, 제 이름 탭 층) · 'all'(둘 다) */
    _hostTabsSVG(p, X, W, GW, x1, from, flatR, y, txt, edge, mixHex, PAPER, INK, part = 'all') {
      const DASH = { nominal: ' stroke-dasharray="1.5 2"', plain: ' stroke-dasharray="3 2"' };
      let svg = '';
      const host = this._hostTabPlan(p, X, W, x1, from, flatR);
      if (part !== 'coal')
        for (const { x, w, seg: s } of host) {
          const c = s.h.host.color;
          const k = PLATE.mix[s.look] || 0;
          const ty = y - G.tab - PLATE.tabRise;
          const d = tabBump(GW + x, ty + 0.5, w, G.tab + G.bw - 0.5, TAB.sh);
          svg += `<path d="${d} Z" fill="${k ? mixOk(c, PAPER, k) : PAPER}"/><path d="${d}" fill="none" stroke="${mixOk(c, INK, PLATE.edge)}"${DASH[s.look] || ''}/>`;
          svg += txt(GW + x + w / 2, ty + 1 + (G.tab - 1) / 2 + TAB.hostSize * .35, s.h.host.name, { size: TAB.hostSize, weight: TAB.hostWt, anchor: 'middle', fill: mixHex(c, INK, s.look === 'owned' || s.look === 'occupied' ? 0.28 : 0.45) });
        }
      if (part === 'host') return svg;
      /* 연합의 겹 탭(화면 _hostTabs와 같은 자리 _coalTabPlan): 뒤 장(연합 색 18% · 4px 오른쪽 · 3px 위) 다음에 앞 장(34%) — 칠은 종이에 섞은 불투명 색(앞 장이 뒤 장을 가림) */
      for (const { x, w, c } of this._coalTabPlan(p, X, W, x1, from, flatR, host)) {
        const col = c.group.color;
        const back = tabBump(GW + x + TAB.backDx, y - G.tab + 0.5 - TAB.backDy, w, G.tab + G.bw - 0.5 + TAB.backDy, TAB.sh);
        const d = tabBump(GW + x, y - G.tab + 0.5, w, G.tab + G.bw - 0.5, TAB.sh);
        svg += `<path d="${back} Z" fill="${mixHex(col, PAPER, 0.18)}"/><path d="${back}" fill="none" stroke="${edge(col)}"/><path d="${d} Z" fill="${mixHex(col, PAPER, 0.34)}"/><path d="${d}" fill="none" stroke="${edge(col)}"/>`;
        svg += txt(GW + x + w / 2, y - G.tab + 1 + (G.tab - 1) / 2 + TAB.hostSize * .35, c.group.name, { size: TAB.hostSize, weight: TAB.hostWt, anchor: 'middle', fill: mixHex(col, INK, 0.3) });
      }
      return svg;
    }

    _depCells(p, X, ox, iw, top0, cut, rowLanes) {
      const P = G.pad2;
      let out = '';
      for (const it of p._dep.items) {
        if (!it.inn) continue;
        const segs = it.segs.filter(s => s.side === 'in');
        const top = top0 + depInTop(rowLanes, it.inLane);
        const strip = layoutStrip(segs, () => it.p.uid, s => X(s.a) - ox, s => X(s.b) - ox, P, iw - P, 2);
        const row = this._depAltRow(it, strip, false, cut);
        const plan = this._altPlan(p, row, { X: t => X(t) - ox, lo: P, hi: iw - P, h: G.dep, now: it.p.endY });
        row.forEach((u, k) => {
          const { seg: s, l, w, jl, jr, label, unk } = u;
          const z = plan.zones.get(k);
          const dx = plan.shift.get(k) || 0;
          const flat = plan.litDim && plan.litDim.has(k) ? this._litCls(l, w, true) : { cls: '', css: '' };
          out += `<i class="tl-dep is-${s.look}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${unk.cls}${zoneCls(z)}${flat.cls}" data-uid="${esc(it.p.uid)}" data-row="${p._row}" style="left:${cx(l)}px;width:${cx(w)}px;top:${top}px;--c:${it.p.color}${unk.css}${z ? zoneCss(z, u.bl) : ''}${flat.css}" title="${esc(this._depTip(p, it, s) + altTip(u.c, u.base))}"><b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(label)}</b></i>`;
        });
        out += this._altMarksHTML(null, row, plan, { top, h: G.dep, vlo: P, vw: iw - P, gx: ox, color: () => it.p.color, spot: u => this._isSpot(it.p.uid, u.ref) });
      }
      return out;
    }

    /** 매달린 이름표 (상국 띠 아래 — 스스로 다스린 속국: 빈 탭 조공 · 봉국 · 자치령 · 칠한 탭 종속 · 보호 · 위성 · 점선 탭 명목상 · 파선 탭 소속 · 구성국 · 동군연합).
        줄(lane)마다 속국 하나, 띠 아랫변 밑으로 2px 끼워 매달고(책갈피 탭처럼 띠보다 아래 층) 둘째 줄부터는 윗줄 밑에 이어 매답니다.
        같은 속국이 밖에서 안으로(또는 안에서 밖으로) 옮긴 때는 세로 끈 하나가 매달린 탭과 품은 칸을 잇습니다. 둥근 모서리 아래에 매달리지 않게 띠 끝에서 10px 안쪽 */
    _depHangs(tr, p, X, W, gr, lit = { cols: null, cls: '' }, ox = 0) {
      const row = p._row;
      const bandH = (tr.rowHs[row] ?? tr.rowH) - ((tr.rowCut && tr.rowCut[row]) || 0);
      const pitch = HANG.pitch; // 매달린 탭 한 줄(높이도 같음 — 줄 사이 틈 없이 둘째 줄부터 가는 가름선 is-deep)
      const xa = X(p.startUnknown ? p.start : bandStart(p));
      const xb = X(p.endUnknown ? p.endY : bandEnd(p));
      const lo = xa < -1 ? -1 : xa + 10;
      const hi = xb > W + 1 ? W + 1 : xb - 10;
      let out = '';
      for (const it of p._dep.items) {
        const key = `${esc(p.uid)}:${esc(it.p.uid)}`;
        if (it.out) {
          const top = bandH - 2 + it.outLane * pitch;
          const segs = it.segs.filter(s => s.side === 'out');
          const strip = layoutStrip(segs, () => it.p.uid, s => X(s.a), s => X(s.b), lo, hi, 2);
          const cells = this._depAltRow(it, strip, true, { l: xa < -1, r: xb > W + 1 });
          const plan = this._altPlan(null, cells, { X, lo, hi, h: pitch, now: it.p.endY, litEdges: this._litEdges && this._litEdges.map(x => x + ox) });
          const mask = (l, w) => {
            if (!lit.cols) return '';
            const pixels = cols => mergeCols(cols.map(([a, b]) => [HT.clamp(X(a) - l, 0, w), HT.clamp(X(b) - l, 0, w)]));
            return `;--lm:${litMask(lit.to ? litSegs(pixels(lit.to), pixels(lit.from)) : litSegs(pixels(lit.cols), null), 0, w, w)}`;
          };
          cells.forEach((u, k) => {
            const { seg: s, l, w, jl, jr, atL, atR, label, unk } = u;
            const sk = it.segs.indexOf(s); // 열쇠는 자료의 차례로 — 화면 밖으로 나간 구간이 있어도 남은 구간의 열쇠가 바뀌지 않게
            const z = plan.zones.get(k);
            const dx = plan.shift.get(k) || 0;
            const clip = `${atL && xa < -1 ? ' clip-l' : ''}${atR && xb > W + 1 ? ' clip-r' : ''}`;
            const flat = plan.litDim && plan.litDim.has(k) ? ' lit-flat' : '';
            out += `<i class="tl-hang is-${s.look}${it.outLane ? ' is-deep' : ''}${jl ? ' j-l' : ''}${jr ? ' j-r' : ''}${clip}${unk.cls}${zoneCls(z)}${lit.cls}${flat}" data-k="hg:${key}:${sk}" data-uid="${esc(it.p.uid)}" data-row="${row}" data-band="${esc(p.uid)}" style="left:${cx(l)}px;width:${cx(w)}px;top:${cx(top)}px;height:${pitch}px;--c:${it.p.color}${unk.css}${z ? zoneCss(z, u.bl) : ''}${mask(l, w)}" title="${esc(this._depTip(p, it, s) + altTip(u.c, u.base))}"><b${dx ? ` style="translate:${cx(dx)}px"` : ''}>${esc(label)}</b></i>`;
          });
          const marks = this._altMarksHTML(null, cells, plan, { top: 0, h: pitch, vlo: lo, vw: hi, color: () => it.p.color, spot: u => this._isSpot(it.p.uid, u.ref) });
          if (marks) out += `<i class="tl-dep-marks${lit.cls}" data-k="hg:${key}:marks" data-uid="${esc(it.p.uid)}" data-row="${row}" data-band="${esc(p.uid)}" style="left:0;top:${cx(top)}px;width:${W}px;height:${pitch}px;--c:${it.p.color}${mask(0, W)}">${marks}</i>`;
        }
        if (it.out && it.inn) {
          /* 밖 ↔ 안으로 옮긴 때: 이어진 두 구간의 경계에 세로 끈 (매달린 탭의 가운데 ↔ 품은 칸의 가운데) */
          for (let k = 1; k < it.segs.length; k++) {
            const a = it.segs[k - 1];
            const b = it.segs[k];
            if (a.side === b.side || Math.abs(X(a.b) - X(b.a)) > 1.5) continue;
            const x = X(b.a);
            if (x < lo || x > hi) continue;
            const yIn = gr.depTop + depInTop(depRowLanes(gr), it.inLane) + G.dep / 2;
            const yOut = bandH - 2 + it.outLane * pitch + HANG.linkOut;
            if (depLinkBlocked(p._dep, it, X, x)) continue; // 다른 이름표를 가로지르면 긋지 않음
            out += `<i class="tl-hang-link" data-k="hl:${key}:${k}" data-row="${row}" data-band="${esc(p.uid)}" style="left:${cx(x)}px;top:${cx(Math.min(yIn, yOut))}px;height:${cx(Math.abs(yOut - yIn))}px;--c:${it.p.color}"></i>`;
          }
        }
      }
      return out;
    }

    /** 그림 내보내기의 속국 이름표 (화면의 _depCells · _depHangs와 같은 자리 · 같은 모양) → { svg, hatch(점령 빗금 무늬를 썼는지) }.
        그림의 띠는 반투명이라 탭을 띠 밑에 끼우지 않고, 첫 줄은 띠 아랫변에서 · 둘째 줄부터는 윗줄 밑에서 시작합니다(윗변은 긋지 않음 — 둘째 줄부터는 가는 가름선) */
    _depSVG(tr, p, X, W, GW, y, bandH, gr, n, txt, edge, mixHex, PAPER, fadeMask, svgPlan, svgAlt) {
      const pitch = HANG.pitch; // 매달린 탭 한 줄(높이도 같음 — 줄 사이 틈 없이 둘째 줄부터 가는 가름선 is-deep)
      const xa = X(p.startUnknown ? p.start : bandStart(p));
      const xb = X(p.endUnknown ? p.endY : bandEnd(p));
      const lo = xa < 0 ? -12 : xa + 10;
      const hi = xb > W ? W + 12 : xb - 10;
      const FILL = { loose: 0.1, firm: 0.34, nominal: 0.1, plain: 0, held: 0.24, owned: 0.52, occupied: 0.2 };
      const DASH = { nominal: ' stroke-dasharray="1.5 2"', plain: ' stroke-dasharray="3 2"' };
      let svg = '';
      let hatch = false;
      const hung = !this._hangsFolded(p.uid); // 매달린 탭을 접어 둔 상국은 탭 · 세로 끈 없이 (화면과 같게)
      for (const it of p._dep.items) {
        const c = it.p.color;
        const fl = (s, jl, w) => (s.h.startUnknown && !jl ? Math.min(FADE, w * 0.4) : 0);
        const fr = (s, jr, w) => (s.h.endUnknown && !jr ? Math.min(FADE, w * 0.4) : 0);
        if (it.out && hung) {
          const vt = y + bandH + (it.outLane ? it.outLane * pitch - 2 : 0);
          const vb = y + bandH + it.outLane * pitch + (HANG.pitch - 2);
          const strip = layoutStrip(it.segs.filter(s => s.side === 'out'), () => it.p.uid, s => X(s.a), s => X(s.b), lo, hi, 2);
          const row = this._depAltRow(it, strip, true);
          const plan = svgPlan(row, { X, lo, hi, h: vb - vt, now: it.p.endY });
          strip.forEach(({ it: s, l, r, jl, jr }, k) => {
            const w = r - l;
            const rl = jl ? 0 : Math.min(6, w / 2);
            const rr = jr ? 0 : Math.min(6, w / 2);
            const body = `V${n(vb - rr)}${rr ? `a${n(rr)} ${n(rr)} 0 0 1 ${n(-rr)} ${n(rr)}` : ''}H${n(GW + l + rl)}${rl ? `a${n(rl)} ${n(rl)} 0 0 1 ${n(-rl)} ${n(-rl)}` : ''}V${n(vt)}`;
            const [defs, mask] = fadeMask(GW + l, vt, w, vb - vt, fl(s, jl, w), fr(s, jr, w));
            svg += `${defs}<path d="M${n(GW + l)} ${n(vt)}H${n(GW + r)}${body}Z" fill="${s.look === 'plain' ? PAPER : c}" fill-opacity="${s.look === 'plain' ? 1 : FILL[s.look]}"${mask}/>`;
            /* 테두리: 오른쪽 · 아래 · 왼쪽만 (이어 붙은 쪽의 옆변은 이웃이 그음) — 둘째 줄부터는 윗줄과 가르는 가는 선 */
            const arc = (dx, dy) => `a${n(Math.abs(dx))} ${n(Math.abs(dy))} 0 0 1 ${n(dx)} ${n(dy)}`;
            const rim = `${jr ? `M${n(GW + r)} ${n(vb)}` : `M${n(GW + r)} ${n(vt)}V${n(vb - rr)}${rr ? arc(-rr, rr) : ''}`}H${n(GW + l + rl)}${rl ? arc(-rl, -rl) : ''}${jl ? '' : `V${n(vt)}`}`;
            svg += `<path d="${rim}" fill="none" stroke="${edge(c, 0.92)}" stroke-opacity="0.85"${DASH[s.look] || ''}${mask}/>`;
            if (it.outLane) svg += `<line x1="${n(GW + l)}" y1="${n(vt)}" x2="${n(GW + r)}" y2="${n(vt)}" stroke="${edge(c, 0.92)}" stroke-opacity="0.4"${mask}/>`;
            const label = jl ? '' : this._depLabel(it, w - 4, HANG.font);
            if (label) svg += txt(GW + l + 7 + (plan.shift.get(k) || 0), (vt + vb) / 2 + HANG.font * 0.35, label, { size: HANG.font, weight: 650, fill: mixHex(c, '#000000', 0.45) });
          });
          svg += svgAlt(row, plan, { ox: GW, top: vt, h: vb - vt, color: () => c });
        }
        if (it.inn) {
          const top = y + gr.depTop + depInTop(depRowLanes(gr), it.inLane);
          const x1 = X(bandStart(p));
          const x2 = X(bandEnd(p));
          const strip = layoutStrip(it.segs.filter(s => s.side === 'in'), () => it.p.uid, s => X(s.a), s => X(s.b), Math.max(x1, -12) + 4, Math.min(x2, W + 12) - 4, 2);
          const row = this._depAltRow(it, strip);
          const plan = svgPlan(row, { X, lo: Math.max(x1, -12) + 4, hi: Math.min(x2, W + 12) - 4, h: G.dep, now: it.p.endY });
          strip.forEach(({ it: s, l, r, jl, jr }, k) => {
            const w = r - l;
            const rl = jl ? 0 : Math.min(6, w / 2);
            const rr = jr ? 0 : Math.min(6, w / 2);
            const d = `M${n(GW + l + rl)} ${n(top)}H${n(GW + r - rr)}${rr ? `a${n(rr)} ${n(rr)} 0 0 1 ${n(rr)} ${n(rr)}V${n(top + G.dep - rr)}a${n(rr)} ${n(rr)} 0 0 1 ${n(-rr)} ${n(rr)}` : `V${n(top + G.dep)}`}H${n(GW + l + rl)}${rl ? `a${n(rl)} ${n(rl)} 0 0 1 ${n(-rl)} ${n(-rl)}V${n(top + rl)}a${n(rl)} ${n(rl)} 0 0 1 ${n(rl)} ${n(-rl)}` : `V${n(top)}`}Z`;
            const [defs, mask] = fadeMask(GW + l, top, w, G.dep, fl(s, jl, w), fr(s, jr, w));
            svg += `${defs}<path d="${d}" fill="${c}" fill-opacity="${FILL[s.look]}" stroke="${edge(c, 0.92)}" stroke-opacity="0.85"${mask}/>`;
            if (s.look === 'occupied') {
              hatch = true;
              svg += `<path d="${d}" fill="url(#tl-dep-hatch)" ${mask}/>`;
            }
            const label = jl ? '' : this._depLabel(it, w);
            if (label) svg += txt(GW + l + 6 + (plan.shift.get(k) || 0), top + G.dep / 2 + 3.5, label, { size: 9.5, weight: 650, fill: mixHex(c, '#000000', s.look === 'owned' ? 0.3 : 0.45) });
          });
          svg += svgAlt(row, plan, { ox: GW, top, h: G.dep, color: () => c });
        }
        if (it.out && it.inn && hung) {
          for (let k = 1; k < it.segs.length; k++) {
            const a = it.segs[k - 1];
            const b = it.segs[k];
            if (a.side === b.side || Math.abs(X(a.b) - X(b.a)) > 1.5) continue;
            const x = X(b.a);
            if (x < lo || x > hi) continue;
            const yIn = y + gr.depTop + depInTop(depRowLanes(gr), it.inLane) + G.dep / 2;
            const yOut = y + bandH - 2 + it.outLane * pitch + HANG.linkOut;
            if (depLinkBlocked(p._dep, it, X, x)) continue;
            svg += `<line x1="${n(GW + x)}" y1="${n(Math.min(yIn, yOut))}" x2="${n(GW + x)}" y2="${n(Math.max(yIn, yOut))}" stroke="${edge(c, 0.84)}" stroke-width="1.5" stroke-linecap="round"/>`;
          }
        }
      }
      return { svg, hatch };
    }

    _hollowHTML(p, X, ox, iw) {
      const list = this._hosted && this._hosted.get(p.uid);
      if (!list) return '';
      let out = '';
      for (const s of list) {
        const za = X(Math.max(s.start, bandStart(p))) - ox;
        const zb = X(Math.min(s.endY, bandEnd(p))) - ox;
        if (zb - za < 0.5 || zb < 0 || za > iw) continue;
        const zl = Math.max(za, 0);
        const zw = Math.min(zb, iw) - zl;
        if (zw < 0.5) continue;
        out += `<i class="tl-zone z-hollow${zl <= 0.5 ? ' at-s' : ''}${zl + zw >= iw - 0.5 ? ' at-e' : ''}" style="left:${cx(zl)}px;width:${cx(zw)}px;--sc:${s.color}" title="${esc(`${s.label || '할거'} — ${s.name} (${HT.formatRange(s)}) · 이름만 남은 본국, 실제 다스림은 흩어짐`)}"></i>`;
      }
      return out;
    }

    /** 할거기 왼쪽 위의 작은 단추 '▸ 〈성격〉 n' (.tl-mem과 같은 꼴 — 첫 글줄, 사건 글자가 피해 감): 띠에서 바로 그 대범위의 모아 보기를 켜고 끕니다 (data-scope → toggleScope) */
    _scopeBtnsHTML(tr, p, X, W, x2, g, reserved, noDot) {
      const list = this._hosted && this._hosted.get(p.uid);
      if (!list) return '';
      let out = '';
      for (const s of list) {
        const n = (s.members || []).filter(m => tr.periods.includes(m)).length;
        const a = Math.max(s.start, bandStart(p));
        const b = Math.min(s.endY, bandEnd(p));
        if (!n || b <= a) continue;
        const on = this.scopeOn(s);
        const txt = `${on ? '▾' : '▸'} ${s.label || '대범위'} ${n}`;
        const bird = !!this._bird; // 조감: 높이 10 · 8.5px 글자의 작은 단추, 자리는 띠(구간) 시작에 고정 — 화면 가장자리를 따라오지 않음(옆으로 옮겨도 점이 숨거나 드러나지 않게)
        const w = bird ? textWidth(txt, 8.5, 600) + 8 : textWidth(txt, 10) + 14;
        let bx = (bird ? X(a) : Math.max(X(a), 0)) + 6;
        for (let k = 0; k < 6; k++) {
          const hit = reserved.find(([l, r]) => bx < r && bx + w > l); // 소속 단추 · 건국 네모 · 앞 단추를 비켜
          if (!hit) break;
          bx = hit[1] + 3;
        }
        if (bx + w > (bird ? Math.min(X(b), x2) : Math.min(X(b), x2, W)) - 6) continue;
        const by = bird ? (g.lineH - 10) / 2 : g.textTop + Math.round((g.lineH - 16) / 2);
        out += `<button type="button" class="tl-mem tl-scopebtn${bird ? ' is-bird' : ''}${on ? ' is-open' : ''}" data-k="sb:${esc(s.uid)}" data-scope="${esc(s.uid)}" data-row="${p._row}" data-band="${esc(p.uid)}" style="left:${cx(bx)}px;top:${by}px;--c:${s.color}" title="${esc(`${s.name} — ${s.label || '대범위'} ${n}곳 · ${on ? '모아 보기 끄기' : '모아 보기 켜기 (이 줄 바로 아래에 모임)'}`)}">${esc(txt)}</button>`;
        reserved.push(bird ? [bx - BIRD_NAME.clear, bx + w + BIRD_NAME.clear] : [bx - 3, bx + w + 3]);
        if (noDot) noDot.push([bx - 3, bx + w + 3, 1]);
      }
      return out;
    }

    /** 그림으로 내보내기의 대범위 테두리 (화면과 같은 자리 — 띠보다 먼저 그려 뒤에) */
    _scopesSVG(tr, top, X, W, GW) {
      let out = '';
      for (const b of tr.scopeBranches || []) {
        const box = this._scopeBox(tr, b);
        if (!box) continue;
        let xl = Infinity;
        let xr = -Infinity;
        for (const p of b.list) {
          xl = Math.min(xl, X(bandStart(p)) - (p.startUnknown ? FADE : 0));
          xr = Math.max(xr, X(bandEnd(p)) + (p.endUnknown ? FADE : 0));
        }
        xl -= G.scopePadX;
        xr += G.scopePadX;
        if (b.board) [xl, xr] = [0, W]; // 집합 보기: 가로 전체 · 이름표는 늘 (화면과 같게 — _scopeX)
        if (xr < 0 || xl > W) continue;
        const l = GW + Math.max(xl, -12);
        const r = GW + Math.min(xr, W + 12);
        const y0 = top + box.top;
        const y1 = y0 + box.height;
        const c = b.s.color;
        const ink = mixHex(c, '#000000', 0.84);
        const rr = this._bird ? 8 : 12; // 조감은 테두리 모서리도 작게 (화면과 같게)
        out += box.hung
          ? `<path d="M${cx(l + 0.5)} ${cx(y0)}V${cx(y1 - rr)}a${rr} ${rr} 0 0 0 ${rr} ${rr}H${cx(r - rr - 0.5)}a${rr} ${rr} 0 0 0 ${rr} ${-rr}V${cx(y0)}" fill="${c}" fill-opacity="0.08" stroke="${ink}" stroke-opacity="0.55"/>`
          : `<rect x="${cx(l + 0.5)}" y="${cx(y0 + 0.5)}" width="${cx(Math.max(4, r - l - 1))}" height="${cx(box.height - 1)}" rx="${rr}" fill="${c}" fill-opacity="0.08" stroke="${ink}" stroke-opacity="0.55"/>`;
        if (b.s.rangeFrom !== 'members') {
          const a = HT.clamp(GW + X(b.s.start), l + 1, r - 1);
          const e = HT.clamp(GW + X(b.s.endY), l + 1, r - 1);
          if (e - a >= 1 && (a > l + 1.5 || e < r - 1.5)) out += `<rect x="${cx(a)}" y="${cx(y0 + 1)}" width="${cx(e - a)}" height="${cx(box.height - 2)}" fill="${c}" fill-opacity="0.1"/>`;
        }
        if (xl >= 0) out += `<text x="${cx(l + 10)}" y="${cx(y0 + (this._bird ? 9.5 : 12))}" font-size="${this._bird ? 9 : 10}" font-weight="700" fill="${mixHex(c, '#000000', 0.6)}">${esc(b.s.name)}${b.s.label ? `<tspan font-weight="500" fill-opacity="0.75"> · ${esc(b.s.label)}</tspan>` : ''}</text>`;
      }
      return out;
    }

    /** 그림으로 내보내기의 할거기 칠 (화면의 z-hollow — 띠 바탕의 가운데를 종이빛으로 덮고 양 끝에 점선) */
    _hollowSVG(p, X, W, GW, y, bandH) {
      const list = this._hosted && this._hosted.get(p.uid);
      if (!list) return '';
      let out = '';
      for (const s of list) {
        const a = Math.max(X(Math.max(s.start, bandStart(p))), -12);
        const b = Math.min(X(Math.min(s.endY, bandEnd(p))), W + 12);
        if (b - a < 1) continue;
        out += `<rect x="${cx(GW + a)}" y="${cx(y + 4)}" width="${cx(b - a)}" height="${cx(Math.max(0, bandH - 8))}" fill="#ffffff" fill-opacity="0.62"/>`;
        out += `<path d="M${cx(GW + a)} ${cx(y + 2)}V${cx(y + bandH - 2)}M${cx(GW + b)} ${cx(y + 2)}V${cx(y + bandH - 2)}" stroke="${mixHex(s.color, '#000000', 0.84)}" stroke-opacity="0.5" stroke-dasharray="2 2"/>`;
      }
      return out;
    }

    /* ---------- 모여드는 움직임 (docs/구상-체제-확장.md 7-3) ----------
       대범위를 켜고 끄는 한 번에만: 구성 정권의 줄이 옛 자리에서 새 자리로 흘러 모이고(끄면 제 민족 묶음으로 흩어지고), 트랙 높이와 한 시계로 함께 도착합니다 —
       HT.motion.T.move · C.spring 글자 그대로, _applyFlip이 높이 전환을 거는 같은 호출 안에서 출발. 스크롤은 0px(트랙 위쪽을 붙잡음 — toggleScope), 옛 · 새 자리는 화면 좌표로 잽니다.
       새 줄마다 셋 가운데 하나 (tr._gather.rows — 줄별 dy 표, 적용 함수는 _gatherAnim 하나):
         · 새 줄의 정권이 모두 같은 옛 줄에서 옴 → 줄째로 이동 (탭 · 사건 · 기간 막대 · 건국·멸망 네모 · 왼쪽 줄 이름 · 민족 딱지 함께)
         · 섞임 (끌 때 승계 사슬 줄로 합쳐지는 구성 정권) → 줄의 기준은 구성 정권이 아닌 쪽의 옛 줄, 다른 옛 줄에서 온 정권은 줄 안에서 정권 단위로(b: · tab: · m: 요소, 그 띠에 그려지는 인물 막대 · 기관 칸 · 할거 단추, 그 네모) 옮기고 그 정권의 사건은 떠오름
         · 옛 줄이 접혀 있었음 / 접힌 민족 줄로 들어감 (가는 막대 ↔ 띠) → 옮기지 않고 떠오름만 (--t-in)
       승계선 · 소속선은 그림 전체(.tl-links)가 기다렸다가(T.move − T.in) 떠올라 이동과 같은 순간에 도착하고, 민족 칸 · 다른 대범위 테두리 · 민족 딱지는 top · height 전환(같은 길이 · 같은 곡선)으로 흐릅니다.
       다시 그려지는 것은 _gatherDraw가 그릴 때마다 지난 시간만큼 앞당겨 같은 시계에 다시 붙입니다. 자료 갱신(주기적 setData)에는 없고(_gatherReq가 없음), 동작 줄이기면 즉시 */

    /** 다시 짓기 직전의 옛 자리 (화면 좌표 — 흐르는 높이 · 진행 중인 이동까지 든, 지금 보이는 자리): 줄마다의 위쪽 · 정권마다 놓였던 줄과 그 띠의 자리 · 민족 칸 · 다른 테두리,
        그리고 창이 열린 항목의 줄이 지금 보이는지. 동작 줄이기 · 접힌 트랙이면 자리는 재지 않습니다(토글 한 번에만 끄는 것은 그래도 끔 — _gather) */
    _gatherFirst(tr, s, on) {
      const req = { trackId: s.track, uid: s.uid, on, first: null, anchorSeen: false };
      const a = this.anchorUid ? this._anchorLane() : null;
      if (a) {
        const ab = a.lane.getBoundingClientRect();
        const bb = this.bodyEl.getBoundingClientRect();
        req.anchorSeen = ab.bottom > bb.top && ab.top < bb.bottom;
      }
      if (!tr || tr.folded || !tr.el || !tr.el.isConnected || !tr.laneEls || reduceMotion()) return req;
      const rows = tr.laneEls.map((el, r) => ({ top: el.getBoundingClientRect().top, hidden: tr.hiddenRows.has(r), folded: tr.foldedRows.has(r) }));
      const bands = new Map(); // 정권 uid → 그 띠에서 잰 줄의 자리 (정권 단위로 옮겨지던 중에 다시 눌렀으면 그만큼 비낀 자리)
      for (const lane of tr.laneEls) for (const c of lane.children) if (!c._ghost && c.dataset.k && c.dataset.k.startsWith('b:')) bands.set(c.dataset.k.slice(2), c.getBoundingClientRect().top - c.offsetTop);
      const periods = new Map();
      for (const p of tr.periods) {
        const r = p._row;
        if (r == null || p._hidden || p._under || p._overlay || !rows[r]) continue;
        periods.set(p.uid, { row: r, top: bands.has(p.uid) ? bands.get(p.uid) : rows[r].top });
      }
      const boxes = (sel, key) => {
        const m = new Map();
        tr.el.querySelectorAll(sel).forEach(el => {
          const b = el.getBoundingClientRect();
          if (b.height > 0 && el.getAttribute(key)) m.set(el.getAttribute(key), { top: b.top, height: b.height });
        });
        return m;
      };
      req.first = { rows, periods, common: tr.commonRow, peoples: boxes('.tl-people', 'data-fold-people'), scopes: boxes('.tl-lanes > .tl-scope', 'data-uid'), ghosts: [], reborn: null };
      /* 끄는 대범위의 테두리 · 왼쪽 칸 — 다시 지으면 없어지므로 옛 요소를 잔상으로 남깁니다 (_gatherGhost) */
      if (!on)
        req.first.ghosts = [tr.lanesEl.querySelector(`:scope > .tl-scope[data-uid="${CSS.escape(s.uid)}"]`), tr.el.querySelector(`.tl-people[data-fold-people="${CSS.escape(`${s.track}|__scope:${s.uid}`)}"]`)].filter(
          el => el && el.getBoundingClientRect().height > 0 && (el._o0 = +getComputedStyle(el).opacity) > 0 // 막 떠오르던 중이면 그 밝기에서
        );
      else
        /* 끄던 대범위를 도중에 다시 켬: 아직 옅어지던 잔상의 지금 밝기 — 새 테두리 · 왼쪽 칸이 밝기 0이 아니라 여기서 이어 떠오릅니다 (_gather · 다시 지으면 잔상은 없어짐) */
        tr.el.querySelectorAll('.tl-scope, .tl-people').forEach(el => {
          if (el._ghost === s.uid) (req.first.reborn || (req.first.reborn = {}))[el.classList.contains('tl-scope') ? 'scope' : 'people'] = +getComputedStyle(el).opacity;
        });
      return req;
    }

    /** 모여듦의 출발 (setData에서 _applyFlip 바로 다음 — 높이 전환을 건 같은 호출): 새 자리를 재어 줄별 dy 표를 만들고, 줄 · 선 그림 · 민족 칸 · 테두리를 한 시계로 출발시킵니다.
        함께 출발하는 데려오기(따로 오는 둘째 막 없음): 창이 열린 항목의 줄이 보이다가 가려지게 되면 최소 거리로, 아니면 켠 테두리가 화면에 걸리지 않을 때만(_gatherReveal) —
        줄을 붙잡았으면(_gatherHold) 같은 판정을 붙잡기의 곡선에 실어 함께 */
    _gather(before) {
      const req = this._gatherReq;
      this._gatherReq = null;
      const tr = req ? this.tracks.find(t => t.id === req.trackId) : null;
      if (!tr || !tr.el) return;
      /* 토글 한 번에만 끕니다: 트랙 전체 떠오름 · 새로 생김/없어짐 효과(줄 번호가 바뀌어 엉뚱한 것이 떠오르거나 물러남) — 떠오르는 것은 테두리 · 왼쪽 칸과 옛 자리가 없던 것뿐 */
      tr.el.classList.remove('is-opening', 'is-closing');
      tr.el._openedAt = null;
      tr._was = null;
      if (tr.folded) return;
      const F = req.first;
      /* 실제로 줄을 붙잡았을 때만 true — 그때 가려지는 것의 데려오기는 _gatherHold가 붙잡기와 같은 곡선에 싣습니다.
         동작 줄이기면 누른 본국 줄은 다시 짓기가 이미 제자리에 두었으므로(_snapshot — 창이 열려 있으면 _pressStill) 아래의 데려오기만 (켠 테두리가 화면 밖이면 최소 거리) */
      let held = false;
      if (F && tr.laneEls && before.tracks.has(tr.id) && !reduceMotion()) {
        const T = HT.motion.T;
        const now = tr.laneEls.map(el => el.getBoundingClientRect().top); // 새 자리 (남은 스크롤 보정까지 든 화면 좌표)
        const sc = (this.scopes || []).find(x => x.uid === req.uid);
        const members = new Set(((sc && sc.members) || []).map(m => m.uid));
        const inTrack = new Map(tr.periods.map(p => [p.uid, p]));
        const ownerOf = e => {
          let q = inTrack.get(e._place ? e._place.polityUid : e.polityUid);
          while (q && q._hidden) q = q._host;
          return q ? q.uid : null;
        };
        const plan = new Map();
        for (let r = 0; r < tr.rows; r++) {
          if (tr.hiddenRows.has(r) || !tr.laneEls[r]) continue;
          const folded = tr.foldedRows.has(r);
          const src = p => {
            const o = F.periods.get(p.uid);
            const old = o && F.rows[o.row];
            return old && !old.hidden && old.folded === folded ? o : null; // 가는 막대 ↔ 띠는 옮기지 않음
          };
          const list = r === tr.commonRow ? [] : (tr.rowPeriods[r] || []).filter(p => !p._hidden);
          let base = -1;
          if (r === tr.commonRow) base = F.common >= 0 && F.rows[F.common] && !F.rows[F.common].hidden ? F.common : -1;
          else {
            const n = new Map(); // 옛 줄 → 거기서 온 정권 수 (구성 정권이 아닌 쪽으로 — 없으면 구성 정권의 첫째)
            for (const p of list) {
              const o = !members.has(p.uid) && src(p);
              if (o) n.set(o.row, (n.get(o.row) || 0) + 1);
            }
            if (!n.size) {
              const o = list.map(src).find(Boolean);
              if (o) n.set(o.row, 1);
            }
            for (const [row, k] of n) if (base < 0 || k > n.get(base)) base = row;
          }
          if (base < 0) {
            plan.set(r, { dy: 0, all: true }); // 옛 자리가 없음 — 옮기지 않고 떠오름만
            continue;
          }
          const b = F.rows[base].top;
          const x = { dy: Math.abs(b - now[r]) >= 0.5 ? b - now[r] : 0, all: false, els: new Map(), fadeP: new Set(), fadeE: new Set() };
          const owners = new Set(); // 사건이 떠오를 정권 (다른 옛 줄에서 왔거나 옛 자리가 없음)
          for (const p of list) {
            const o = src(p);
            if (!o) {
              x.fadeP.add(p.uid);
              owners.add(p.uid);
              continue;
            }
            if (Math.abs(o.top - b) >= 0.5) x.els.set(p.uid, o.top - b);
            if (o.row !== base) owners.add(p.uid);
          }
          if (owners.size) for (const e of tr.eventsByRow[r] || []) if (owners.has(ownerOf(e))) x.fadeE.add(`${e.uid}:${e._pi || 0}`);
          if (x.dy || x.els.size || x.fadeP.size || x.fadeE.size) plan.set(r, x);
        }
        const g = (tr._gather = { rows: plan, t0: HT.motion.now(), ref: null, until: 0 });
        g.until = g.t0 + T.move + 40;
        for (const [r, x] of plan) if (x.dy) x.anim = this._gatherAnim(tr.laneEls[r], g, x.dy);
        if (tr.linksEl) this._gatherAnim(tr.linksEl, g, 0, T.move - T.in); // 승계선 · 소속선: 기다렸다가 떠올라 이동과 같은 순간에 도착 (새 자리에 그려진 선이 움직이는 줄을 가로지르지 않게)
        /* 민족 칸 · 다른 대범위 테두리 · 민족 딱지: 옛 자리 · 옛 높이로 되돌렸다가 새 자리로 흐르게 (전환 — 줄과 같은 길이 · 같은 곡선 · 같은 출발 프레임).
           옛 자리가 없던 것(다시 나타난 민족 칸 · 떠오르는 줄의 딱지)은 떠오름, 방금 켠 대범위의 테두리 · 왼쪽 칸은 제 떠오름(is-born) */
        const flips = []; // [요소, 옛 자리까지의 거리, 옛 높이(그대로면 null)]
        const flip = (el, old) => {
          const nb = el.getBoundingClientRect();
          if (Math.abs(old.top - nb.top) >= 0.5 || Math.abs(old.height - nb.height) >= 0.5) flips.push([el, old.top - nb.top, old.height]);
        };
        tr.el.querySelectorAll('.tl-people').forEach(el => {
          if (el.classList.contains('is-born') || el.classList.contains('is-collapsed')) return;
          const old = F.peoples.get(el.dataset.foldPeople);
          if (old) flip(el, old);
          else this._gatherAnim(el, g);
        });
        tr.lanesEl.querySelectorAll(':scope > .tl-scope').forEach(el => {
          const old = !el.classList.contains('is-born') && !el.classList.contains('is-collapsed') && F.scopes.get(el.dataset.uid);
          if (old) flip(el, old);
        });
        tr.el.querySelectorAll('.tl-pchip').forEach(el => {
          const x = plan.get(Number(el.dataset.pchip));
          if (!x || el.classList.contains('is-collapsed')) return;
          if (x.all) this._gatherAnim(el, g);
          else if (x.dy) flips.push([el, x.dy, null]);
        });
        const keep = flips.map(([el]) => [el.style.top, el.style.height]);
        for (const [el, dy, h] of flips) {
          el.style.transition = 'none';
          el.style.top = `${cx(parseFloat(el.style.top) + dy)}px`;
          if (h != null) el.style.height = `${cx(h)}px`;
        }
        if (flips.length) tr.el.getBoundingClientRect(); // 옛 자리를 한 번 그리게 한 뒤
        flips.forEach(([el], i) => {
          el.style.transition = '';
          el.style.top = keep[i][0];
          el.style.height = keep[i][1];
        });
        for (const el of F.ghosts) this._gatherGhost(tr, el, req.uid);
        /* 끄던 대범위를 도중에 다시 켰으면 새 테두리 · 왼쪽 칸은 제 떠오름(is-born — 밝기 0부터) 대신 잔상이 있던 밝기에서 이어 떠오름: 보이던 테두리가 한 프레임에 꺼졌다 다시 떠오르지 않게 */
        if (F.reborn)
          [
            ['scope', tr.lanesEl.querySelector(`:scope > .tl-scope.is-born[data-uid="${CSS.escape(req.uid)}"]`)],
            ['people', tr.el.querySelector(`.tl-people.is-born[data-fold-people="${CSS.escape(`${tr.id}|__scope:${req.uid}`)}"]`)],
          ].forEach(([k, el]) => {
            if (!el || F.reborn[k] == null) return;
            el.classList.remove('is-born');
            this._gatherAnim(el, g, 0, 0, F.reborn[k]);
          });
        held = this._gatherHold(tr, req, plan, members, ownerOf);
      } else if (req.pressUid && reduceMotion()) held = this._pressStill(tr, req); // 동작 줄이기: 창이 열려 있어도 누른 본국 줄이 먼저 (창이 없으면 다시 짓기가 이미 붙잡음)
      if (held) return;
      if (req.anchorSeen && this._anchorLane()) this._revealAnchor(); // 보이던 고른 줄(모여드는 정권의 것)이 가려지게 되면 최소 거리로 (잘 보이면 0px)
      else if (req.on) this._gatherReveal(tr, req.uid);
    }

    /** 끈 대범위의 테두리 · 왼쪽 칸의 잔상: 옛 요소를 새 트랙의 같은 자리에 두어, 구성 정권이 흩어지는 동안 남아 있다가 이동과 같은 순간에 끝나도록 옅어지며 사라집니다
        (T.move − T.out 기다린 뒤 T.out — 끝나는 시각이 줄의 이동과 같음). 찾기 · 고르기 · 누르기의 대상이 아니고, 순번으로 짝짓는 코드(_placeScopes · _drawScopes · _collapseRows · _placePchips)가
        건드리지 않게 진짜 요소들 뒤에 붙입니다. _ghost에는 그 대범위의 uid를 적어 두어, 옅어지는 도중에 다시 켜면 그 밝기에서 이어 떠오르게 합니다(_gatherFirst) */
    _gatherGhost(tr, el, uid) {
      const M = HT.motion;
      el.classList.remove('is-born', 'is-selected', 'is-match', 'is-dim'); // 다시 붙일 때 떠오름 키프레임이 되풀이되지 않게
      el.removeAttribute('data-uid');
      el.removeAttribute('data-fold-people');
      el.inert = true;
      el._ghost = uid;
      if (el.classList.contains('tl-scope')) tr.lanesEl.insertBefore(el, tr.laneEls[0] || null);
      else tr.el.querySelector('.tl-peoples').appendChild(el);
      const a = el.animate([{ opacity: el._o0 }, { opacity: 0 }], { duration: M.T.out, delay: M.T.move - M.T.out, easing: 'ease-in', fill: 'both' });
      if (M.rate !== 1) a.playbackRate = M.rate;
      a.onfinish = a.oncancel = () => el.remove();
    }

    /** 붙잡을 줄 (움직임 원칙 ⑧ — 누른 것 · 고른 것은 제자리): 본국 띠의 단추를 눌렀으면 본국 줄(창이 어디에 열려 있든 — 손 밑의 것이 먼저),
        아니면 창이 열린 항목이 이 트랙에 있고 모여드는 정권의 것이 아닐 때 그 줄. 위쪽 줄이 빠지거나 더해져 그 줄이 새 자리로 옮겨지면(dy), 스크롤을 한 번에 옮기지 않고
        줄 이동과 같은 곡선 · 같은 진행(줄 움직임의 진행값)으로 조금씩 옮겨 그 줄은 화면에서 1px도 움직이지 않고 나머지가 함께 미끄러집니다.
        누른 본국 줄을 붙잡은 채 다 모였을 때 가려지는 것이 있으면 — 보이던 고른 줄이 옮겨져 여유 밖으로 나가거나(창이 열려 있으면 이것만), 창이 없거나 안 보이던 때는
        켠 테두리의 머리와 첫 줄이 화면에 걸리지 않으면 — 그 최소 거리를 같은 곡선에 더해 함께 데려옵니다(본국 줄도 그만큼만 옮겨짐 — ⑧의 데려오기 예외, 본국 줄은 화면 안에 남음).
        스크롤이 닿는 데까지만. 붙잡았으면 true (그때는 따로 데려오지 않음) */
    _gatherHold(tr, req, plan, members, ownerOf) {
      const M = HT.motion;
      const a = this.anchorUid ? this._anchorLane() : null;
      let row = -1;
      let uid = null;
      const hp = req.pressUid ? tr.periods.find(q => q.uid === req.pressUid) : null;
      const pressed = !!(hp && hp._row != null && !hp._hidden && !tr.hiddenRows.has(hp._row) && tr.laneEls[hp._row]);
      if (pressed) [row, uid] = [hp._row, hp.uid];
      else if (a && a.tr === tr) {
        const p = tr.periods.find(q => q.uid === this.anchorUid);
        const e = !p && tr.events.find(q => q.uid === this.anchorUid);
        const own = p ? p.uid : e ? ownerOf(e) : null;
        if (!members.has(own)) [row, uid] = [a.row, own]; // 모여드는 정권의 것이면 그 줄은 함께 움직이고 가려질 때만 데려옴 (_gather) · 다른 트랙의 고른 줄은 지금처럼 닻이
      }
      if (row < 0) return false;
      const x = plan.get(row);
      if (x && x.all) return false; // 옛 자리가 없던 줄 (떠오름)
      const D = x ? x.dy + ((uid && x.els.get(uid)) || 0) : 0; // 그 줄이 지금 보이는 자리 − 새 자리
      const s0 = this.bodyEl.scrollTop;
      const { tops, total } = this._modelTops(); // 다 흐른 뒤의 배치 (아래 트랙은 높이 흐름을 따라 내려가므로 화면이 아니라 모델로)
      const sF = pressed ? this._pressScroll(tr, req, row, s0, D) : HT.clamp(s0 - D, 0, Math.max(0, total - this.bodyEl.clientHeight)); // 붙잡은 채 다 모였을 때의 스크롤
      const K = s0 - sF; // 스크롤이 옮겨 갈 거리 = 그 줄이 옮겨진 만큼 + 데려오기
      if (Math.abs(K) < 0.5) return true;
      /* 진행값의 시계: 그 줄의 이동, 없으면(그 줄은 그대로이고 데려오기만) 다른 줄의 이동 — 모두 같은 프레임에 같은 길이 · 곡선으로 출발했으므로 같은 값. 옮기는 줄이 없으면 같은 모양의 빈 움직임 */
      let clock = (x && x.anim) || [...plan.values()].map(y => y.anim).find(Boolean);
      if (!clock) {
        clock = tr.el.animate([], { duration: M.T.move, easing: M.C.spring });
        if (M.rate !== 1) clock.playbackRate = M.rate;
      }
      const prog = () => {
        if (clock.playState === 'finished' || clock.playState === 'idle') return 1;
        const pr = clock.effect.getComputedTiming().progress;
        return pr == null ? 1 : pr;
      };
      if (a) {
        /* 창이 열려 있으면 스크롤은 닻(_keepAnchor)이 씁니다: 닻 자리(_anchorOff)가 스크롤을 s0 − K × 진행값으로 옮기도록 스프링 자리에 같은 모양의 따라가기를 둡니다.
           닻 줄의 자리는 그때그때 재므로 닻이 이 트랙 아래 트랙에 있어 높이 흐름을 따라 내려가도 맞습니다(도중에 데려오기가 걸리면 그 자리 · 그 값에서 진짜 스프링으로 넘어감) */
        const self = this;
        const fin = tops.get(a.tr) + a.tr.rowTop[a.row];
        const abs = () => {
          const c = self._anchorLane();
          return c ? self._laneAbs(c) : fin;
        };
        this._anchorTo = null;
        this._anchorOff = abs() - s0;
        this._anchorSpring = {
          target: fin - sF,
          value: () => abs() - s0 + K * prog(),
          velocity: () => 0,
          done: () => prog() >= 1,
          set(to, v, t) {
            return (self._anchorSpring = self._newAnchorSpring(this.value()).set(to, null, t));
          },
        };
        this._anchorLoop(M.T.move + 80);
      } else {
        const off0 = tr.el.offsetTop + tr.laneEls[row].offsetTop - s0;
        const held = { tr, row, until: M.now() + M.T.move + 80 };
        Object.defineProperty(held, 'off', { enumerable: true, get: () => off0 + K * prog(), set: () => {} }); // 붙잡은 줄의 화면 자리 = 그 줄의 이동을 되돌리는 만큼 (+ 데려오기)
        this._held = held;
        this._anchorLoop(M.T.move + 80, held);
      }
      return true;
    }

    /** 누른 본국 줄(row — 새 줄 번호)을 붙잡은 채 다 모였을 때의 스크롤: 그 줄이 D만큼(지금 보이는 자리 − 새 자리) 옮겨졌으면 스크롤도 그만큼(s0 − D).
        가려지는 것이 있으면 최소 거리를 더합니다 — 창이 열린 항목의 줄이 보이다가 옮겨져 여유 밖으로 나가면 그 줄을(_revealTo), 창이 없거나 안 보이던 때는
        켠 테두리의 머리와 첫 줄이 화면에 걸리지 않으면 그만큼(_scopeMiss). 데려오느라 본국 줄이 화면 밖으로 나가지는 않게(둘 다 들어가지 않으면 누른 줄이 먼저), 스크롤이 닿는 데까지 */
    _pressScroll(tr, req, row, s0, D) {
      const a = this.anchorUid ? this._anchorLane() : null;
      const b = this.bodyEl;
      const { tops, total } = this._modelTops();
      const max = Math.max(0, total - b.clientHeight);
      const sHold = HT.clamp(s0 - D, 0, max);
      let sF = sHold;
      if (a && req.anchorSeen) {
        const abs = tops.get(a.tr) + a.tr.rowTop[a.row];
        const f = abs - sF; // 다 모였을 때 그 줄의 자리 — 지금 보이는 자리와 같으면(옮겨지지 않음) 그대로
        const seen = a.lane.getBoundingClientRect().top - b.getBoundingClientRect().top;
        if (!a.tr.hiddenRows.has(a.row) && Math.abs(f - seen) >= 0.5) sF = abs - this._revealTo(a, f); // 잘 보이면 0px
      } else if (req.on) {
        const m = this._scopeMiss(tr, req.uid, sF);
        if (m) sF = HT.clamp(sF - (m.to - m.top), 0, max);
      }
      const at = tops.get(tr) + tr.rowTop[row];
      return HT.clamp(sF, Math.min(sHold, at + tr.rowHs[row] - b.clientHeight), Math.max(sHold, at));
    }

    /** 동작 줄이기에서 창이 열린 채 본국 띠의 단추를 누름: 다시 짓기는 닻(창이 열린 항목)을 붙잡았으므로(_snapshot), 누른 본국 줄이 누르기 전 자리(req.pressOff)에 오도록
        닻 자리를 한 번에 옮깁니다 — 가려지는 것은 움직일 때와 같은 판정(_pressScroll). 옮겼으면 true */
    _pressStill(tr, req) {
      const a = this._anchorLane();
      const r = req.pressOff == null || !a ? -1 : this._uidRow(tr, req.pressUid);
      if (r < 0 || !tr.laneEls || !tr.laneEls[r]) return false;
      const s0 = this.bodyEl.scrollTop;
      const sF = this._pressScroll(tr, req, r, s0, req.pressOff - (tr.el.offsetTop + tr.laneEls[r].offsetTop - s0));
      this._anchorSpring = this._anchorTo = null;
      this._anchorOff = this._laneAbs(a) - sF;
      this._keepAnchor();
      return true;
    }

    /** 모여듦의 움직임 하나 — 적용 함수는 이것 하나뿐입니다(움직임-개선안 4-2의 한 숫자 구동이 들어오면 여기만 같은 스프링 값으로 바꿔 끼움).
        dy면 그만큼 떨어진 옛 자리에서 제자리로(T.move · C.spring), 아니면 떠오름(T.in · C.ease — wait만큼 기다렸다가, 밝기 o0에서). 끝 밝기 · 끝 자리는 적지 않습니다(제 자리 · 제 밝기로).
        이미 흐르던 모여듦에 늦게 붙는 것(다시 그려진 것)은 첫 움직임이 지난 시간만큼 앞당겨 붙어 같은 시계로 이어집니다 — 아직 출발 전이면 같은 프레임에 함께 출발 */
    _gatherAnim(el, g, dy = 0, wait = 0, o0 = 0) {
      const M = HT.motion;
      const ref = g.ref;
      const since = !ref ? 0 : ref.playState !== 'idle' ? ref.currentTime || 0 : M.now() - g.t0;
      const svg = el instanceof SVGElement && !(el instanceof SVGSVGElement);
      const kf = dy ? (svg ? { transform: `translateY(${cx(dy)}px)` } : { translate: `0 ${cx(dy)}px` }) : { opacity: o0 };
      kf.offset = 0;
      const a = el.animate([kf], { duration: dy ? M.T.move : M.T.in, easing: dy ? M.C.spring : M.C.ease, delay: wait - since, fill: 'backwards' });
      if (M.rate !== 1) a.playbackRate = M.rate; // 느리게 보기: 다음 프레임을 기다리지 않고 지금부터 같은 빠르기로
      if (!ref) g.ref = a;
      el._gat = g;
      return a;
    }

    /** 모여드는 동안의 그리기마다 (_drawTrack 끝): 이번에 새로 지어진 것을 같은 시계에 다시 붙입니다 — 줄 안의 것은 처음 한 번(정권 단위 이동 · 떠오름),
        왼쪽 줄 이름은 다시 쓰였을 때, 건국·멸망 네모는 그림을 통째로 다시 쓰므로 그릴 때마다. 다 흐르면 표를 버립니다 */
    _gatherDraw(tr) {
      const g = tr._gather;
      if (HT.motion.now() > g.until) return (tr._gather = null);
      /* 줄 안 요소의 몫: 수 = 정권 단위 이동의 거리, 0 = 떠오름, null = 줄과 함께 */
      const act = (x, k, el) => {
        if (x.all) return 0;
        const i = k.indexOf(':');
        if (i < 0) return null;
        const pre = k.slice(0, i);
        const rest = k.slice(i + 1);
        /* 정권에 딸린 것은 그 정권(띠)과 함께: 띠 · 탭 · 소속 단추 · 작은 막대는 키가 '앞말:정권 uid', 인물 막대 · 기관 칸 · 할거 단추 · 속국 이름표(매달린 탭 · 세로 끈)는 그려지는 띠가 data-band
           (키는 '인물:섬긴 정권' · '기관:상국' · '대범위' — 숨은 상국의 기관은 그것이 접혀 든 보이는 띠에), 한 칸으로 줄어든 인물 단은 키가 'fd:띠 uid' */
        const pu = /^(b|tab|m|mb|fd|hb)$/.test(pre) ? rest : /^(f|o|sb|hg|hl|ht)$/.test(pre) ? el.getAttribute('data-band') : null;
        if (pu != null) return x.els.has(pu) ? x.els.get(pu) : x.fadeP.has(pu) ? 0 : null;
        return x.fadeE.has(rest) || x.fadeE.has(rest.slice(0, rest.lastIndexOf(':'))) ? 0 : null; // 사건 · 기간 막대 · 구슬 …: 키가 '앞말:사건키(:번호)'
      };
      tr.laneEls.forEach((lane, r) => {
        const x = g.rows.get(r);
        if (!x || !(x.all || x.els.size || x.fadeP.size || x.fadeE.size)) return;
        for (const c of lane.children) {
          if (c._gat === g || c._ghost || !c.dataset.k) continue;
          const d = act(x, c.dataset.k, c);
          if (d != null) this._gatherAnim(c, g, d);
          else c._gat = g;
        }
      });
      const first = tr.rowsEl && tr.rowsEl.firstElementChild;
      if (first && first._gat !== g)
        for (const el of tr.rowsEl.children) {
          const x = g.rows.get(Number(el.dataset.row));
          if (x && (x.all || x.dy)) this._gatherAnim(el, g, x.all ? 0 : x.dy);
          else el._gat = g;
        }
      if (tr.marksEl)
        for (const grp of tr.marksEl.children) {
          const x = grp._gat === g ? null : g.rows.get(Number(grp.dataset.row));
          grp._gat = g;
          if (!x) continue;
          if (x.all || x.dy) this._gatherAnim(grp, g, x.all ? 0 : x.dy);
          if (!x.all)
            for (const pg of grp.children) {
              const uid = pg.getAttribute('data-p');
              if (x.els.has(uid)) this._gatherAnim(pg, g, x.els.get(uid));
              else if (x.fadeP.has(uid)) this._gatherAnim(pg, g);
            }
        }
    }

    /** 켠 대범위의 테두리가 화면에 걸리지 않으면(머리 + 첫 줄이 다 보이지 않으면) 지금의 데려오기 장치(_bringRow — 되튐 없는 스프링)로 최소 거리만. 걸려 있으면 0px.
        모여드는 이동과 함께 출발합니다 (누른 본국 줄을 붙잡을 때는 _gatherHold가 같은 판정을 붙잡기에 싣습니다) */
    _gatherReveal(tr, uid) {
      const m = this._scopeMiss(tr, uid, this.bodyEl.scrollTop);
      if (m) this._bringRow(tr, m.row, m.to + tr.rowTop[m.row] - m.box.top);
    }

    /** 스크롤이 sTop일 때 켠 대범위의 테두리가 화면에 걸리는가 — 걸리면 null, 아니면 { row: 가지의 펴진 첫 줄, box, top: 테두리 위쪽의 화면 자리, to: 데려다 놓을 자리 }:
        위로 나갔으면 위쪽 여유(SAFE_Y)에, 아래로 나갔으면 머리와 첫 줄이 아래쪽 여유 안에 들도록 */
    _scopeMiss(tr, uid, sTop) {
      const b = (tr.scopeBranches || []).find(x => x.uid === uid);
      const box = b && b.box;
      let fv = -1;
      if (box) for (let r = b.first; r < b.first + b.count && fv < 0; r++) if (!tr.hiddenRows.has(r)) fv = r;
      if (fv < 0) return null;
      const H = this.bodyEl.clientHeight;
      const top = tr.el.offsetTop + box.top - sTop; // 다 모인 뒤의 테두리 위쪽 (줄은 이미 새 자리에 지어져 있음)
      const need = Math.min(box.height, tr.rowTop[fv] + tr.rowHs[fv] - box.top);
      if (Math.min(H, top + box.height) - Math.max(0, top) >= need - 0.5) return null;
      return { row: fv, box, top, to: top < 0 ? SAFE_Y : Math.max(SAFE_Y, H - SAFE_Y - need) };
    }

    /* ---------- 그림으로 내보내기 ---------- */
    /** 그림 내보내기: 띠 뒤 층(plan.back)을 화면과 같은 굵기 · 짙기로 — 띠 자리는 가림막(holes — 띠 모양의 검은 칸)으로 가려 화면처럼 띠에 가려집니다(그림의 띠는 반투명 칠이라).
        ox · oy = 그림에서 줄 좌표의 원점, box = 가림막의 범위, pal = { PAPER, edge(c) } */
    _backSVG(plan, holes, id, ox, oy, box, pal) {
      if (!plan.back.length) return '';
      const n = v => Number(v).toFixed(1);
      const out = plan.back.map(b => {
        if (b.k === 'part') return `<path d="M${n(b.x)} ${n(b.y1)} V${n(b.y2)}" fill="none" stroke="${b.color}" stroke-width="1.3" stroke-dasharray="2 3" opacity="${b.ref ? 0.3 : 0.8}"/><circle cx="${n(b.x)}" cy="${n(b.y2)}" r="2" fill="${b.color}" opacity="${b.ref ? 0.3 : 0.9}"/>`;
        if (b.k === 'ring') return `<circle cx="${n(b.x)}" cy="${n(b.y)}" r="2.75" fill="${pal.PAPER}" stroke="${b.color}" stroke-width="1.6" opacity="${b.ref ? 0.2 : 0.5}"/>`;
        if (b.k === 'bundle') return `<path d="${b.d}" fill="none" stroke="${b.color}" stroke-width="1.6" stroke-dasharray="${b.kind.dash}" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.5"/><circle cx="${n(b.end[0])}" cy="${n(b.end[1])}" r="2.5" fill="${pal.PAPER}" stroke="${b.color}" stroke-width="1.3" opacity="0.6"/>`;
        /* 가는 선(부분 승계)은 화면처럼 제 굵기 · 픽셀 칸 맞춤 · 짙기 PARTIAL — 그 밖의 선은 예전 그대로 */
        const thin = thinOf(b.kind, b.sg);
        return thin
          ? `<path d="${roundHV(crispHV(b.pts, thin), b.r)}" fill="none" stroke="${b.color}" stroke-width="${thin.w}" stroke-opacity="${b.ref ? 0.2 : PARTIAL}" stroke-linecap="round" stroke-linejoin="round"/>`
          : `<path d="${roundHV(b.pts, b.r)}" fill="none" stroke="${b.color}" stroke-width="1.6" stroke-opacity="${b.ref ? 0.2 : 0.5}" stroke-linecap="round" stroke-linejoin="round"${b.kind.dash ? ` stroke-dasharray="${b.kind.dash}"` : ''}/>`;
      });
      return `<mask id="${id}" maskUnits="userSpaceOnUse" x="${n(box.x)}" y="${n(box.y)}" width="${n(box.w)}" height="${n(box.h)}"><rect x="${n(box.x)}" y="${n(box.y)}" width="${n(box.w)}" height="${n(box.h)}" fill="#fff"/>${holes.join('')}</mask><g mask="url(#${id})"><g transform="translate(${n(ox)} ${n(oy)})">${out.join('')}</g></g>`;
    }

    /** 그림 내보내기: 띠 위 층 — 줄 · 정권 차례대로 문 → 관문 · 다리 · 고리 → 건국 · 멸망 네모 (화면의 .tl-marks와 같은 자리 · 같은 차례) */
    _marksSVG(tr, plan, X, W, ox, oy, pal) {
      const n = v => Number(v).toFixed(1);
      const hs = G.sq / 2;
      const byRow = new Map();
      const slot = (row, uid) => {
        if (!byRow.has(row)) byRow.set(row, new Map());
        const m = byRow.get(row);
        if (!m.has(uid)) m.set(uid, { pre: '', sq: '' });
        return m.get(uid);
      };
      for (const p of tr.periods) {
        if (p._folded || p._hidden || p._under || p._overlay || p._row == null || (tr.hiddenRows && tr.hiddenRows.has(p._row))) continue;
        const y = this._anchorY(tr, p._row);
        const { fc, ec, showF, showE } = this._squares(p, X, ((tr.geos && tr.geos[p._row]) || tr.geo).lines, W);
        const ink = pal.edge(p.color);
        let out = '';
        if (showF)
          out += p.startUnknown
            ? `<circle cx="${n(fc)}" cy="${n(y)}" r="4" fill="${pal.PAPER}" stroke="${ink}" stroke-width="1.4" stroke-dasharray="2 2"/>`
            : `<rect x="${n(fc - hs)}" y="${n(y - hs)}" width="${G.sq}" height="${G.sq}" rx="2" fill="${p.color}" stroke="${ink}" stroke-width="1"/>`;
        if (showE)
          out += p.endUnknown
            ? `<circle cx="${n(ec)}" cy="${n(y)}" r="4" fill="${pal.PAPER}" stroke="${ink}" stroke-width="1.4" stroke-dasharray="2 2"/>`
            : `<rect x="${n(ec - hs)}" y="${n(y - hs)}" width="${G.sq}" height="${G.sq}" rx="2" fill="${pal.PAPER}" stroke="${ink}" stroke-width="1.6"/>`;
        if (out) slot(p._row, p.uid).sq += out;
      }
      for (const t of plan.top) {
        let out;
        if (t.door) out = `<rect x="${n(t.door.x)}" y="${n(t.door.y)}" width="${n(t.door.w)}" height="${n(t.door.h)}" rx="1" fill="${pal.PAPER}"${t.door.ref ? ' opacity="0.2"' : ''}/>`; // 부정된 나라에 닿는 선의 문은 선과 함께 옅게 (화면과 같게)
        else {
          const l = t.line;
          const segs = l.segs.map(s => `<path d="M${n(s.x1)} ${n(s.y1)} L${n(s.x2)} ${n(s.y2)}" fill="none" stroke="${pal.edge(s.c)}" stroke-width="${s.w || 1.6}"${l.type === 'partial' ? ` stroke-opacity="${PARTIAL / 0.9}"` : ''}/>`).join(''); // 부분 승계의 조각은 묶음 .9 안에서 PARTIAL까지 (합류 조각은 그대로)
          const ring = l.ring ? `<circle cx="${n(l.ring.x)}" cy="${n(l.ring.y)}" r="2.75" fill="${pal.PAPER}" stroke="${pal.edge(l.ring.c)}" stroke-width="1.6"/>` : '';
          const join = l.join ? `<rect x="${n(l.join.x)}" y="${n(l.join.y)}" width="${n(l.join.w)}" height="${n(l.join.h)}" rx="${n(l.join.h / 2)}" fill="${pal.edge(l.join.c)}"/>` : ''; // 합류 조각
          out = `<g opacity="${l.ref ? 0.2 : 0.9}">${segs}${ring}${join}</g>`;
        }
        slot(t.row, t.uid).pre += out;
      }
      const body = [...byRow.values()].map(m => [...m.values()].map(v => v.pre + v.sq).join('')).join('');
      return body ? `<g transform="translate(${n(ox)} ${n(oy)})">${body}</g>` : '';
    }

    toSVG({ width = 1800, title = '' } = {}) {
      const G = this._G(); // 조감이면 조감 값 묶음 (줄 사이 · 여백 · 탭 0 · 접힌 줄 …)
      const bird = this._bird; // 조감: 화면과 같게 — 띠 하나뿐인 줄 · 띠 안 이름 · 점 · 알약 · 네모 없는 승계선 (줄 이름 칸은 모양 c면 색 점만)
      const GW = this.gutter;
      const W = Math.max(200, Math.round(width) - GW);
      const { start, end } = this.view;
      const k = W / (end - start);
      const X = y => (y - start) * k;
      const n = v => Number(v).toFixed(1);
      const titleH = title ? 46 : 10;
      const axisH = 28;
      const svgW = GW + W;
      const bodyTop = titleH + axisH;
      const heights = this.tracks.map(tr => tr.height);
      const total = Math.round(bodyTop + heights.reduce((a, b) => a + b, 0) + 24);
      const txt = (x, y, str, o = {}) =>
        `<text x="${n(x)}" y="${n(y)}" font-size="${o.size || 12}" font-weight="${o.weight || 400}" fill="${o.fill || '#000000'}"${o.anchor ? ` text-anchor="${o.anchor}"` : ''}>${esc(str)}</text>`;

      const INK = '#000000';
      const MUTED = '#666666';
      const PAPER = '#ffffff';
      const edge = (c, k = 0.84) => mixHex(c, INK, k);
      const plateGap = this._plateGap(); // 뒤 장 위 띠 둘레의 종이빛 틈 (화면의 --tl-plate-gap과 같은 값)
      /* 칸의 미정 (화면의 unk-s · unk-e처럼): 사각형 (x, w)의 왼쪽 fl · 오른쪽 fr 픽셀이 옅어지며 사라지는 가림막 → [가림막 정의, 사각형에 붙일 mask 속성] */
      let fadeN = 0;
      const fadeMask = (x, y, w, h, fl, fr) => {
        if (!(fl > 0) && !(fr > 0)) return ['', ''];
        const id = `tlunk${++fadeN}`;
        const at = v => HT.clamp(v / Math.max(1, w), 0, 1).toFixed(3);
        const stops = [[0, fl > 0 ? 0 : 1], [at(fl || 0), 1], [at(w - (fr || 0)), 1], [1, fr > 0 ? 0 : 1]].map(([o, a]) => `<stop offset="${o}" stop-color="#fff" stop-opacity="${a}"/>`).join('');
        return [
          `<linearGradient id="${id}g" gradientUnits="userSpaceOnUse" x1="${n(x)}" y1="0" x2="${n(x + w)}" y2="0">${stops}</linearGradient><mask id="${id}" maskUnits="userSpaceOnUse" x="${n(x - 2)}" y="${n(y - 2)}" width="${n(w + 4)}" height="${n(h + 4)}"><rect x="${n(x - 2)}" y="${n(y - 2)}" width="${n(w + 4)}" height="${n(h + 4)}" fill="url(#${id}g)"/></mask>`,
          ` mask="url(#${id})"`,
        ];
      };
      /* 렌즈 칸 한 줄 (화면의 _lensCells와 같게 — 설계 7-8 결정 5 A): L = HT.lensCellsOf, ly · LH = 지도자 칸 자리, left · bw = 띠의 왼쪽 · 폭, x1 · x2 = 띠의 양 끝(그림 좌표).
         이어지는 칸은 하나의 긴 둥근 칸(바깥 끝만 둥글게) + 구분선, 칸마다 갈래 색 40% 칠 · 연정 칸은 위아래 두 색, 테두리는 무리의 첫 칸 색의 짙은 선 */
      let lensN = 0;
      const lensSVG = (L, ly, LH, left, bw, x1, x2) => {
        let out = '';
        const cells = layoutStrip(L.cells, () => 0, c => X(c.start) - left, c => X(c.end) - left, 4, bw - 4);
        const box = (a, b, rl0, rr0) => {
          const rl = Math.min(rl0, Math.max(0, Math.floor((b - a) / 2)));
          const rr = Math.min(rr0, Math.max(0, Math.floor((b - a) / 2)));
          return `M${n(a + rl)} ${n(ly)} H${n(b - rr)} ${rr ? `a${rr} ${rr} 0 0 1 ${rr} ${rr} V${n(ly + LH - rr)} a${rr} ${rr} 0 0 1 ${-rr} ${rr}` : `V${n(ly + LH)}`} H${n(a + rl)} ${rl ? `a${rl} ${rl} 0 0 1 ${-rl} ${-rl} V${n(ly + rl)} a${rl} ${rl} 0 0 1 ${rl} ${-rl}` : `V${n(ly)}`} Z`;
        };
        let run = [];
        const flush = () => {
          if (!run.length) return;
          const s = run[0].atL && x1 < 0 ? -12 : left + run[0].l;
          const e = run[run.length - 1].atR && x2 > W ? W + 12 : left + run[run.length - 1].r;
          const u0 = run[0];
          const u1 = run[run.length - 1];
          const fl = u0.it.startUnknown && !(u0.atL && x1 < 0) ? Math.min(FADE, (u0.r - u0.l) * 0.4) : 0;
          const fr = u1.it.endUnknown && !(u1.atR && x2 > W) ? Math.min(FADE, (u1.r - u1.l) * 0.4) : 0;
          const [defs, mask] = fadeMask(GW + s, ly, e - s, LH, fl, fr);
          if (mask) out += `${defs}<g${mask}>`;
          run.forEach((u, j) => {
            const last = j === run.length - 1;
            const d = box(GW + (j === 0 ? s : left + u.l), GW + (last ? e : left + u.r), j === 0 ? 5 : 0, last ? 5 : 0);
            if (!u.it.color2) out += `<path d="${d}" fill="${mixHex(u.it.color, PAPER, 0.4)}"/>`;
            else {
              const id = `tllens${++lensN}`;
              const a = GW + (j === 0 ? s : left + u.l);
              const b = GW + (last ? e : left + u.r);
              out += `<clipPath id="${id}"><path d="${d}"/></clipPath><g clip-path="url(#${id})"><rect x="${n(a)}" y="${n(ly)}" width="${n(b - a)}" height="${n(LH / 2)}" fill="${mixHex(u.it.color, PAPER, 0.42)}"/><rect x="${n(a)}" y="${n(ly + LH / 2)}" width="${n(b - a)}" height="${n(LH / 2)}" fill="${mixHex(u.it.color2, PAPER, 0.42)}"/></g>`;
            }
          });
          out += `<rect x="${n(GW + s)}" y="${n(ly)}" width="${n(e - s)}" height="${LH}" rx="5" fill="none" stroke="${edge(u0.it.color, 0.92)}"/>`;
          if (mask) out += '</g>';
          run.forEach((u, j) => {
            const c = u.it;
            if (j > 0) out += `<line x1="${n(GW + left + u.l)}" y1="${n(ly + 2)}" x2="${n(GW + left + u.l)}" y2="${n(ly + LH - 2)}" stroke="${edge(c.color, 0.92)}" stroke-opacity="0.7"${c.startUnknown || run[j - 1].it.endUnknown ? ' stroke-dasharray="2 2"' : ''}/>`;
            const cw = u.r - u.l;
            const text = cw > textWidth(c.name, 11.5, 600) + 12 ? c.name : (c.n || 1) > 1 && c.short && cw > textWidth(c.short, 11.5, 600) + 12 ? c.short : '';
            if (text) out += txt(GW + left + (u.l + u.r) / 2, ly + LH / 2 + 3.5, text, { size: 10.5, weight: 600, anchor: 'middle', fill: mixHex(c.color, INK, 0.3) });
          });
          run = [];
        };
        for (const u of cells) {
          if (!u.jl) flush();
          run.push(u);
        }
        flush();
        return out;
      };
      /* 단체 칸 한 줄 (화면의 _groupCells와 같은 자리 · 이음 · 줄임 — 설계 7-8 결정 1 A · 2 A + 덧판 x1 A · x3 C): gy · GH = 줄의 위 · 높이(단체 단 13 · 붕당 렌즈는 지도자 자리 20).
         집권 = 단체 색 40% · 실권 = 78% + 그 색 64%의 짙은 테두리 · 먹빛 글 · 연정 = 위아래 두 색(42%) + 단체 수만큼 색 점(지름 6) · 짝을 모르는 연정 = 위 반 제 색 · 아래 반 종이빛 + 점 하나.
         이어지는 칸은 하나의 긴 둥근 칸(바깥 끝만 둥글게 — 반지름 4 · 렌즈 5) + 구분선. 글 · 점은 들어갈 때만(화면과 같은 문턱) */
      let groupN = 0;
      const groupSVG = (cells0, gy, GH, left, bw, x1, x2, lens = false) => {
        let out = '';
        const size = lens ? 11.5 : 8.5;
        const pad = lens ? 12 : 10;
        const R = lens ? 5 : 4;
        const cells = layoutStrip(cells0, () => 0, c => X(c.start) - left, c => X(c.end) - left, 4, bw - 4);
        const box = (a, b, rl0, rr0) => {
          const rl = Math.min(rl0, Math.max(0, Math.floor((b - a) / 2)));
          const rr = Math.min(rr0, Math.max(0, Math.floor((b - a) / 2)));
          return `M${n(a + rl)} ${n(gy)} H${n(b - rr)} ${rr ? `a${rr} ${rr} 0 0 1 ${rr} ${rr} V${n(gy + GH - rr)} a${rr} ${rr} 0 0 1 ${-rr} ${rr}` : `V${n(gy + GH)}`} H${n(a + rl)} ${rl ? `a${rl} ${rl} 0 0 1 ${-rl} ${-rl} V${n(gy + rl)} a${rl} ${rl} 0 0 1 ${rl} ${-rl}` : `V${n(gy)}`} Z`;
        };
        const mixOf = c => (c.real ? 0.78 : c.n > 1 || c.solo ? 0.42 : 0.4);
        let run = [];
        const flush = () => {
          if (!run.length) return;
          const s = run[0].atL && x1 < 0 ? -12 : left + run[0].l;
          const e = run[run.length - 1].atR && x2 > W ? W + 12 : left + run[run.length - 1].r;
          const u0 = run[0];
          const u1 = run[run.length - 1];
          const fl = u0.it.startUnknown && !(u0.atL && x1 < 0) ? Math.min(FADE, (u0.r - u0.l) * 0.4) : 0;
          const fr = u1.it.endUnknown && !(u1.atR && x2 > W) ? Math.min(FADE, (u1.r - u1.l) * 0.4) : 0;
          const [defs, mask] = fadeMask(GW + s, gy, e - s, GH, fl, fr);
          if (mask) out += `${defs}<g${mask}>`;
          run.forEach((u, j) => {
            const c = u.it;
            const last = j === run.length - 1;
            const a = GW + (j === 0 ? s : left + u.l);
            const b = GW + (last ? e : left + u.r);
            const d = box(a, b, j === 0 ? R : 0, last ? R : 0);
            if (!c.color2 && !c.solo) out += `<path d="${d}" fill="${mixHex(c.color, PAPER, mixOf(c))}"/>`;
            else {
              const id = lens ? `tllens${++lensN}` : `tlgrp${++groupN}`; // 붕당 렌즈의 연정 칸은 렌즈 칸과 같은 이름 · 같은 셈(lensN — 한 그림 안에서 겹치지 않게)
              out += `<clipPath id="${id}"><path d="${d}"/></clipPath><g clip-path="url(#${id})"><rect x="${n(a)}" y="${n(gy)}" width="${n(b - a)}" height="${n(GH / 2)}" fill="${mixHex(c.color, PAPER, mixOf(c))}"/><rect x="${n(a)}" y="${n(gy + GH / 2)}" width="${n(b - a)}" height="${n(GH / 2)}" fill="${c.solo ? PAPER : mixHex(c.color2, PAPER, mixOf(c))}"/></g>`;
            }
          });
          out += `<rect x="${n(GW + s)}" y="${n(gy)}" width="${n(e - s)}" height="${GH}" rx="${R}" fill="none" stroke="${u0.it.real ? edge(u0.it.color, 0.64) : edge(u0.it.color, 0.92)}"/>`;
          if (mask) out += '</g>';
          run.forEach((u, j) => {
            const c = u.it;
            if (j > 0) out += `<line x1="${n(GW + left + u.l)}" y1="${n(gy + 2)}" x2="${n(GW + left + u.l)}" y2="${n(gy + GH - 2)}" stroke="${c.real ? edge(c.color, 0.64) : edge(c.color, 0.92)}" stroke-opacity="0.7"${c.startUnknown || run[j - 1].it.endUnknown ? ' stroke-dasharray="2 2"' : ''}/>`;
            const cw = u.r - u.l;
            const nd = c.solo ? 1 : c.n > 1 ? c.n : 0;
            const dw = nd ? nd * 9 + 3 : 0;
            const fits = t => !!t && cw >= dw + textWidth(t, size, 600) + pad;
            const first = [...c.name][0] || '';
            const text = nd ? (fits(c.name) ? c.name : c.n > 1 && fits(c.short) ? c.short : c.solo && fits(first) ? first : '') : fits(c.name) ? c.name : cw >= textWidth(first, size, 600) + 8 ? first : '';
            const dots = nd > 0 && (!!text || cw >= dw + 6);
            const tw = text ? textWidth(text, size, 600) + 6 : 0;
            let x0 = GW + left + (u.l + u.r) / 2 - ((dots ? nd * 9 : 0) + tw) / 2; // 점 + 글 한 덩어리를 칸 가운데에 (화면의 가운데 맞춤)
            if (dots)
              for (const cc of c.solo ? [c.color] : c.colors) {
                out += `<circle cx="${n(x0 + 6)}" cy="${n(gy + GH / 2)}" r="2.5" fill="${cc}" stroke="${edge(cc, 0.64)}"/>`;
                x0 += 9;
              }
            if (text) out += txt(x0 + 3 + textWidth(text, size, 600) / 2, gy + GH / 2 + size * .35, text, { size, weight: 600, anchor: 'middle', fill: c.real ? mixHex(c.color, INK, 0.1) : mixHex(c.color, INK, 0.3) });
          });
          run = [];
        };
        for (const u of cells) {
          if (!u.jl) flush();
          run.push(u);
        }
        flush();
        return out;
      };
      /* 칸의 이설 · 모호한 칸 (디테일 건의 4 — 화면과 같은 계획 altRowPlan, 문턱은 하나): 유령 구분선 = 1px 점선('1 2') · 이름 밑 '이설 있음' · 이름표 비킴 · 무늬(세로 줄 · 빗금) · 점선 경계 */
      const svgPlan = (row, o) => altRowPlan(row, Object.assign({ alt: this.showAlt && !this._bird, now: null }, o));
      let zoneN = 0;
      const zoneDefs = new Map(); // 무늬 정의 (색 · 종류마다 하나)
      const zoneFill = (c, kind) => {
        const key = `${kind === 'estimated' ? 'e' : 'h'}${HT.hex6(c)}`;
        if (!zoneDefs.has(key)) {
          const id = `tlz${++zoneN}`;
          const col = mixHex(c, INK, 0.92);
          zoneDefs.set(key, { id, def: kind === 'estimated' ? `<pattern id="${id}" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="1.5" height="4" fill="${col}" fill-opacity="0.42"/></pattern>` : `<pattern id="${id}" width="4.5" height="4.5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="1.5" height="4.5" fill="${col}" fill-opacity="0.42"/></pattern>` });
        }
        return `url(#${zoneDefs.get(key).id})`;
      };
      /* 계획 하나를 그림으로: ox = 줄 좌표 → 그림 x(GW 포함), top = 칸 줄의 y, color(u) = 칸의 색. 무늬는 칸 안쪽(테두리 1px 안), 점선 경계는 칸 밖으로 나가지 않게 */
      const svgAlt = (row, plan, { ox, top: ty, h, color, bottom = 2 }) => {
        let out = '';
        plan.zones.forEach((z, i) => {
          const u = row[i];
          const c = color(u);
          for (const q of z.layers) out += `<rect x="${n(ox + u.l + q.a)}" y="${n(ty + 1)}" width="${n(q.b - q.a)}" height="${n(h - 2)}" fill="${zoneFill(c, q.kind)}"/>`;
          /* 이어 붙지 않은 칸 끝이 연대 폭 안이면 그 옆 변(둥근 모서리 사이의 곧은 부분)을 점선으로 — 이어 붙은 칸 사이 구분선은 칸을 그리는 곳에서(zoneDiv) */
          const r0 = Math.min(5, h / 2 - 1);
          for (const [on, x] of [[z.zl && !u.jl, u.l + 0.5], [z.zr, u.r - 0.5]])
            if (on) out += `<line x1="${n(ox + x)}" y1="${n(ty + r0)}" x2="${n(ox + x)}" y2="${n(ty + h - r0)}" stroke="${PAPER}" stroke-width="1.4"/><line x1="${n(ox + x)}" y1="${n(ty + r0)}" x2="${n(ox + x)}" y2="${n(ty + h - r0)}" stroke="${edge(c, 0.92)}" stroke-dasharray="1 1"/>`;
        });
        for (const m of plan.lines) {
          if (ox + m.x < GW - 1 || ox + m.x > GW + W) continue;
          out += `<line x1="${n(ox + m.x + 0.5)}" y1="${n(ty + 2)}" x2="${n(ox + m.x + 0.5)}" y2="${n(ty + h - bottom)}" stroke="${edge(color(row[m.owner]), 0.92)}" stroke-opacity="0.75" stroke-dasharray="1 2"/>`;
        }
        for (const q of plan.has) out += `<line x1="${n(ox + q.x0)}" y1="${n(ty + q.y + 0.5)}" x2="${n(ox + q.x1)}" y2="${n(ty + q.y + 0.5)}" stroke="${edge(color(row[q.i]), 0.92)}" stroke-opacity="0.75" stroke-dasharray="1 2"/>`;
        return out;
      };
      const zoneDiv = (plan, j) => !!(plan && plan.zones.get(j) && plan.zones.get(j).zl); // 이 칸 왼쪽의 구분선이 연대 폭 안 — 점선 '1 1'
      let axis = '';
      let grid = '';
      const step = AXIS_STEPS.find(s => s * k >= 110) || AXIS_STEPS[AXIS_STEPS.length - 1];
      for (let y = Math.ceil(start / step) * step; y <= end; y += step) {
        const x = GW + X(y);
        grid += `<line x1="${n(x)}" y1="${bodyTop}" x2="${n(x)}" y2="${total - 24}" stroke="#cccccc" stroke-dasharray="1 3"/>`;
        axis += txt(x, titleH + 19, HT.formatAxisYear(y), { fill: MUTED, anchor: 'middle' });
      }
      /* 접힌 줄의 막대: 단은 화면과 같게 자료로 정해 둔 것 */
      const miniBars = (list, y0, laneKey = '_laneAll', boxH = 0) => {
        const top0 = bird ? (boxH - (2 * G.miniPitch + G.mini)) / 2 : G.miniTop; // 화면의 _miniBars와 같은 자리
        let out = '';
        for (const p of list) {
          const x1 = X(bandStart(p));
          const x2 = X(bandEnd(p));
          if (x2 < 0 || x1 > W) continue;
          const lane = p[laneKey] || 0;
          const l = Math.max(x1, 0);
          out += `<rect x="${n(GW + l)}" y="${n(y0 + top0 + lane * G.miniPitch)}" width="${n(Math.max(3, Math.min(x2, W) - l))}" height="${G.mini}" rx="${G.mini / 2}" fill="${p.color}" fill-opacity="0.7" stroke="${edge(p.color)}" stroke-opacity="0.55"/>`;
        }
        return out;
      };

      let body = '';
      let labels = '';
      let top = bodyTop;
      let depHatch = false; // 점령지의 빗금 칸을 그렸으면 무늬 정의를 넣음
      const orgDefs = new Map(); // 기관 칸 · 구역 탭의 성긴 ／ 빗금(빛깔마다 하나 — 화면의 .tl-org.is-agency · .is-zone과 같은 4px/8px · 135°, 묶음 3 · 2번)
      const orgHatch = c => {
        if (!orgDefs.has(c)) orgDefs.set(c, { id: `tlo${orgDefs.size + 1}`, def: `<pattern id="tlo${orgDefs.size + 1}" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(-45)"><rect width="4" height="8" fill="${c}" fill-opacity="0.2"/></pattern>` });
        return `url(#${orgDefs.get(c).id})`;
      };
      this.tracks.forEach((tr, ti) => {
        const g = tr.geo;
        const geoOf = r => (tr.geos && tr.geos[r]) || g;
        const trH = heights[ti];
        const hidden = r => tr.hiddenRows && tr.hiddenRows.has(r);
        labels += `<rect x="0" y="${n(top)}" width="${GW}" height="${trH}" fill="#ffffff"/><rect x="0" y="${n(top)}" width="${COL.track}" height="${trH}" fill="#ebebeb"/>`;
        labels += txt(COL.track / 2, top + trH / 2 + 4, tr.name, { size: 12, weight: 500, anchor: 'middle' });
        if (tr.folded) {
          body += miniBars(tr.periods.filter(p => !p._hidden && !p._overlay && !p._under), top, '_laneAll', G.folded);
        } else {
          for (const r of tr.foldedRows) if (!hidden(r)) body += miniBars(tr.rowPeriods[r] || [], top + tr.rowTop[r], '_laneRow', G.foldedGroup);
          body += this._scopesSVG(tr, top, X, W, GW); // 대범위 테두리 (띠보다 먼저 — 뒤에)
          const backAt = body.length; // 승계선 · 소속선(띠 뒤 층)은 띠보다 먼저 — 자리는 띠를 다 그린 뒤에 정하므로(책갈피 탭의 끝) 여기에 끼워 넣음
          const holes = []; // 띠 자리의 가림막 — 띠 뒤 선이 반투명 띠 칠 너머로 비치지 않게 (화면처럼 띠에 가려짐)
          const svgTab = new Map(); // 정권 → 책갈피 탭의 오른쪽 끝 (그림의 폭으로 잰 것 — 소속선이 탭을 비켜 내려옴)
          const bzones = Array.from({ length: tr.rows }, () => []); // 조감: 줄 → 띠 안 이름 · 단추 자리 (화면의 bnm — 점 · 알약을 두지 않음 · 내림줄이 비켜 감)
          for (const p of tr.periods) {
            if (p._hidden || p._overlay || p._under || p._folded || p._row == null || hidden(p._row)) continue;
            const x1 = X(bandStart(p));
            const x2 = X(bandEnd(p));
            if (x2 < 0 || x1 > W) continue;
            const left = Math.max(x1, 0);
            const w = Math.max(3, Math.min(x2, W) - left);
            const y = top + tr.rowTop[p._row];
            const bandH = tr.rowHs[p._row] - ((tr.rowCut && tr.rowCut[p._row]) || 0);
            /* 띠 모양은 종류의 갈래로 (화면과 같게): 종속 갈래 · 망명 정부 · 부흥·저항 세력 = 옅은 칠(+ 세력은 왼쪽 깃대) · 조직체 = 점점선 · 연맹 = 아주 옅은 칠.
               종속 갈래는 점선이 아닙니다(점선은 추정 · 미정 연대의 몫) — 누구를 어떻게 섬겼는지는 상국 띠의 속국 이름표(_depSVG)로 */
            const dash = p.startUnknown || p.endUnknown ? ' stroke-dasharray="4 3"' : p.polityKind === 'org' || p.polityKind === 'client' ? ' stroke-dasharray="1.5 2.5"' : ''; // 복속 세력(client)은 조직체의 점선 테두리를 빌림(묶음 3 · 3번)
            const bandFill = p.polityKind === 'federation' ? 0.06 : isDepKind(p.polityKind) || p.polityKind === 'exile' || p.polityKind === 'movement' ? 0.09 : 0.24;
            /* 화면 밖으로 이어지는 띠는 그림 가장자리 너머까지 그려 둥근 끝이 잘려 보이게 (화면의 clip-l/clip-r처럼) */
            const rl = x1 < 0 ? -12 : x1;
            const rr = x2 > W ? W + 12 : x2;
            /* 실재성 (화면과 같게): 전설은 위에서 아래로 옅어지는 안개, 반전설은 아래 1/3만, 부정됨은 색을 뺀 회색 (가림막은 아래 defs) */
            const hs = HT.historicityOf(p);
            const fogId = hs === 'refuted' ? 'legendary' : hs; // 부정됨 = 전설과 같은 안개를 색 없이 회색으로 (묶음 5 · 5번)
            const fog = hs === 'legendary' || hs === 'semi' || hs === 'refuted' ? ` mask="url(#hs-${fogId})"` : '';
            const bandC = hs === 'refuted' ? MUTED : p.color;
            holes.push(`<rect x="${n(GW + rl)}" y="${n(y)}" width="${n(Math.max(2, rr - rl))}" height="${n(bandH)}" rx="${G.radius}" fill="${fog ? `url(#hs-h-${fogId})` : '#000'}"/>`); // 전설 · 반전설 · 부정됨 띠는 안개만큼만 (화면처럼 아래쪽으로 비침)
            const bandSvg = `<rect x="${n(GW + rl + 0.5)}" y="${n(y + 0.5)}" width="${n(Math.max(2, rr - rl - 1))}" height="${n(bandH - 1)}" rx="${G.radius}" fill="${bandC}" fill-opacity="${bandFill}" stroke="${edge(bandC)}"${hs === 'refuted' ? ' stroke-opacity="0.6"' : ''}${dash}${fog}/>`;
            /* 책갈피 탭 (화면과 같게): 띠 위 왼쪽에 정권 이름 — 띠 밑에 끼워져 윗변 위로 빠져나온 플래그.
               아래는 곧게 잘리고(아래 테두리 없음) 위 모서리만 둥글며, 띠가 드리운 옅은 그늘이 아랫변에 집니다.
               탭의 모양은 띠보다 먼저 그려 띠 밑에 두고 띠의 윗 테두리 두께(G.bw)만큼만 띠 밑으로 넣습니다 — 띠의 테두리가 그 1px를 덮어 둥근 모서리와 탭 사이에 틈이 없음 (이름 글자와 딱지는 띠 다음에 그려 위에 보임).
               무엇을 적는가는 화면의 탭과 같은 결정(tabParts — 같은 탭 자리 · 같은 폭 셈)이라 딱지의 차례 · 수가 화면과 같습니다: 이름 → 종류 · 관계 딱지(옛 종류의 종속 · 연맹 · 조직 · 시대 … 도)
               → 실재성 딱지 → 지위 딱지(지위 단이 없는 줄에서 지위가 하나뿐인 정권 · 함께 들어갈 때만). 모두 들어가지 않으면 화면처럼 이름의 첫 글자만, 그것도 안 되면 탭 없이 */
            /* 간지 탭(묶음 3 · 1번 L — 화면의 _drawTrack과 같은 자리 · 같은 윤곽): 발은 띠의 둥근 모서리가 끝나는 곳부터, 칠은 띠와 같은 옅기(bandFill) · 선은 띠 테두리 · 밑변 없음. 띠보다 먼저 그려 띠 밑에 */
            const flatL = Math.max(x1 + G.radius, 6);
            const tabL0 = p.startUnknown ? Math.max(X(p.start), 0) + 6 : flatL;
            const tabR0 = p.endUnknown ? Math.min(X(p.endY), W) - 6 : Math.min(x2 - G.radius, W - 6);
            const tp = tabParts(p, bird ? -1 : tabR0 - tabL0, tabRank(p, this.show, geoOf(p._row).rankH), TAB.ext * 2); // 조감은 탭 없음 (들 폭 −1 → 모양 '') — 띠 안 이름은 아래
            const chipW = t => textWidth(t, 8.5) + 10; // 딱지 하나가 그림의 탭에서 차지하는 폭 (딱지 칸 + 사이 여백)
            const chips = tp.mode !== 'full' ? [] : tp.kds.map(k => ({ t: k.t, k: 'kd' })).concat(tp.hs ? [{ t: tp.hsTag, k: 'hs' }] : [], tp.rk ? [{ t: tp.rk.name, k: 'rk', lv: tp.rk.level || 0 }] : []);
            const tabName = tp.mode === 'short' ? p.name.slice(0, 1) : p.name;
            const nameW = textWidth(tabName, 9.5, 700) + 14;
            const tabFits = !!tp.mode;
            if (tabFits) svgTab.set(p.uid, tabL0 + tp.width);
            const tx = GW + tabL0; // 화면의 탭 왼쪽 (시작이 미정이면 사라지는 꼬리 안쪽 — 그림의 띠는 꼬리 없이 그 자리에서 시작)
            const tin = tp.mode === 'full' ? TAB.ext : 0; // 온 이름 탭은 어깨 7 + 안 여백 6이라 글이 예전(여백 7)보다 6px 안쪽에서 · 첫 글자 탭은 어깨 4 + 안 여백 3 = 7로 그대로
            /* 뒤 장 · 받침 → 상국 이름 탭(건의 8의 2번 C — 화면과 같은 자리 · 칠 · 층: 뒤 장 < 받침 < 상국 탭 < 제 이름 탭 < 연합 탭 < 띠) — 상국 탭이 뒤 장의 윗변 선을 덮어 한 덩어리 */
            const hostFrom = tabFits ? tabL0 + tp.width + TAB.gap : flatL;
            if (!bird) body += this._hostPlatesSVG(p, X, W, GW, y, bandH, rl, rr, PAPER, INK, plateGap);
            if (!bird) body += this._hostTabsSVG(p, X, W, GW, x1, hostFrom, tabR0, y, txt, edge, mixHex, PAPER, INK, 'host');
            if (tabFits) {
              const d = tabBump(tx, y - G.tab + 0.5, tp.width, G.tab + G.bw - 0.5, tp.mode === 'short' ? TAB.shShort : TAB.sh);
              body += `<path d="${d} Z" fill="${bandC}" fill-opacity="${bandFill}"/><path d="${d}" fill="none" stroke="${edge(bandC)}"${hs === 'refuted' ? ' stroke-opacity="0.6"' : ''}${dash}/>`;
            }
            /* 연합의 겹 탭: 띠 윗변 · 제 이름 탭 층 — 예전 자리 그대로(_coalTabPlan) */
            if (!bird) body += this._hostTabsSVG(p, X, W, GW, x1, hostFrom, tabR0, y, txt, edge, mixHex, PAPER, INK, 'coal');
            body += bandSvg;
            /* 시대 띠의 다른 견해: 띠 윗변의 작은 빈 고리 (화면의 .tl-palt와 같은 자리 — '이설' 체크가 켜져 있을 때 · 조감이 아닐 때: 화면 _drawTrack과 같은 조건) */
            if (this.showAlt && !bird)
              for (const a of HT.datedAlts(p))
                for (const yv of [a.start, a.end]) {
                  if (yv == null) continue;
                  const ax = X(yv);
                  if (ax < x1 - 4 || ax > x2 + 4 || ax < -4 || ax > W + 4) continue;
                  body += `<circle cx="${n(GW + ax + 0.5)}" cy="${n(y + 1)}" r="3.25" fill="${PAPER}" stroke="${p.color}" stroke-width="1.5"/>`;
                }
            if (p.polityKind === 'movement' && x1 >= 0) body += `<rect x="${n(GW + x1 + 3)}" y="${n(y + 5)}" width="3" height="${n(Math.max(2, bandH - 10))}" rx="1.5" fill="${edge(bandC)}" fill-opacity="0.8"${fog}/>`; // 부흥·저항 세력의 왼쪽 깃대 (전설 · 반전설이면 띠와 같은 안개 가림막 — 화면처럼 함께 옅어짐)
            body += this._hollowSVG(p, X, W, GW, y, bandH); // 상징적 본국의 할거기 칠 (칸보다 먼저 — 칸은 또렷하게)
            if (bird && bird.name) {
              /* 조감의 띠 안 이름 (화면과 같은 _birdName — 문턱 하나) · 그 뒤 단추 자리(그리지 않고 비움 — 점 자리가 화면과 같게) */
              const nm = this._birdName(p, X);
              if (nm.text && nm.l >= -0.5 && nm.l + nm.w <= W + 0.5) { // 화면처럼 그림 안에 다 드는 이름만 (가장자리에 반쯤 잘린 이름 없이) — 자리는 아래에서 그대로 비움
                const nmSvg = txt(GW + nm.l, y + bandH / 2 + 3.5, nm.text, { size: BIRD_NAME.size, weight: BIRD_NAME.wt, fill: hs === 'refuted' ? MUTED : mixHex(bandC, INK, 0.3) });
                body += hs === 'legendary' ? nmSvg.replace('<text ', '<text font-style="italic" ') : nmSvg;
                if (hs === 'refuted') body += `<line x1="${n(GW + nm.l)}" y1="${n(y + bandH / 2)}" x2="${n(GW + nm.l + nm.w)}" y2="${n(y + bandH / 2)}" stroke="${MUTED}" stroke-width="1"/>`;
              }
              if (nm.text) {
                bzones[p._row].push([nm.l - BIRD_NAME.clear, nm.l + nm.w + BIRD_NAME.clear]);
                this._birdBtns(tr, p, X, W, x2, bzones[p._row], nm.l + nm.w);
              }
            }
            if (tabFits) {
              const nameSvg = txt(tx + tin + nameW / 2, y - G.tab + 1 + (G.tab - 1) / 2 + 9 * .35, tabName, { size: 9, weight: 700, anchor: 'middle', fill: hs === 'refuted' ? edge(bandC, 0.45) : mixHex(bandC, INK, 0.22) });
              body += hs === 'legendary' ? nameSvg.replace('<text ', '<text font-style="italic" ') : nameSvg;
              if (hs === 'refuted') body += `<line x1="${n(tx + tin + 7)}" y1="${n(y - G.tab + 1 + (G.tab - 1) / 2)}" x2="${n(tx + tin + nameW - 7)}" y2="${n(y - G.tab + 1 + (G.tab - 1) / 2)}" stroke="${edge(bandC, 0.45)}" stroke-width="1"/>`;
              /* 딱지: 테두리 없는 옅은 칩 (화면의 '.tl-lane .tl-tab small'과 같게 — 종류는 띠 색 30%, 실재성은 회색, 지위는 서열 짙기(HT.RANK_MIX)를 종이빛에 섞은 칠) — 칩 사이 4px */
              let c = nameW;
              for (const ch of chips) {
                const cw = textWidth(ch.t, 8.5) + 6;
                const fill = ch.k === 'hs' ? MUTED : ch.k === 'rk' ? mixHex(p.color, PAPER, HT.RANK_MIX[ch.lv] / 100) : PAPER; // 종류 딱지는 필름 위의 종이빛 칩 (화면과 같게)
                const ink = ch.k === 'hs' ? edge(bandC, 0.45) : ch.k === 'rk' ? (ch.lv ? edge(p.color, 0.4) : MUTED) : edge(bandC, 0.7);
                body += `<rect x="${n(tx + tin + c - 4)}" y="${n(y - G.tab + 1 + (G.tab - 1 - 8.5 * 1.2) / 2 - 3)}" width="${n(cw)}" height="${8.5 * 1.2 + 6}" rx="2" fill="${fill}" fill-opacity="${ch.k === 'hs' ? 0.2 : ch.k === 'rk' ? 0.85 : 0.5}"/>`;
                body += txt(tx + tin + c - 4 + cw / 2, y - G.tab + 1 + (G.tab - 1) / 2 + 8.5 * .35, ch.t, { size: 8.5, weight: ch.k === 'rk' ? 600 : 500, anchor: 'middle', fill: ink });
                c += chipW(ch.t);
              }
            }
            /* 왕조 칸 */
            if (g.dynastyH) {
              const yrow = [];
              for (const d of this._dynOf(p)) {
                const da = X(d.start);
                const db = X(d.end);
                const a2 = da > left + 4 ? da + 0.5 : x1 < 0 ? -12 : left + 4;
                const b2 = db < left + w - 4 ? db - 0.5 : x2 > W ? W + 12 : left + w - 4;
                if (b2 - a2 < 1) continue;
                const yy = d.dynasty;
                const short = yy.name.replace(/\s*(왕조|왕가|가문|家|朝)$/, '');
                const cw = b2 - a2;
                const text = cw >= textWidth(yy.name, 10, 650) + 14 ? yy.name : short && cw >= textWidth(short, 10, 650) + 12 ? short : '';
                yrow.push({ l: a2, r: b2, c: dynCellOf(d, yy), y: yy, key: `dyn:${yy.uid}:${d.start}`, base: { start: d.start, end: d.end }, ink: text ? { text, size: 10, wt: 650, lh: 12 } : null, bl: cw < 8 ? 0 : 1, br: cw < 8 ? 0 : 1 });
              }
              const yplan = svgPlan(yrow, { X, lo: X(bandStart(p)) + 4, hi: X(bandEnd(p)) - 4, h: g.dynastyH, now: p.endY });
              yrow.forEach((u, k) => {
                body += `<rect x="${n(GW + u.l)}" y="${n(y + g.dynastyTop)}" width="${n(u.r - u.l)}" height="${g.dynastyH}" rx="6" fill="${u.y.color}" fill-opacity="0.45" stroke="${edge(u.y.color, 0.92)}"/>`;
                if (u.r - u.l > textWidth(u.y.name, 10, 650) + 14) body += txt(GW + (u.l + u.r) / 2 + (yplan.shift.get(k) || 0), y + g.dynastyTop + g.dynastyH / 2 + 3.5, u.y.name, { size: 10, weight: 650, anchor: 'middle', fill: edge(u.y.color, 0.5) });
              });
              body += svgAlt(yrow, yplan, { ox: GW, top: y + g.dynastyTop, h: g.dynastyH, color: u => u.y.color });
            }
            /* 시기 구분(학계) 단: 화면과 같은 자리 · 같은 이음, 종이빛 중립 칸 */
            const gp = geoOf(p._row);
            if (gp.phaseH && p.phaseSchemes) {
              p.phaseSchemes.slice(0, G.phaseMax).forEach((sc, k) => {
                const py = y + gp.phaseTop + k * (G.phase + G.phaseGap);
                const cells = layoutStrip(sc.spans, () => '', c => X(c.start) - left, c => X(c.end) - left, 4, w - 4);
                const multi = p.phaseSchemes.length > 1;
                const prow = cells.map((u, j) => {
                  const cw = u.r - u.l;
                  const tag = multi && j === 0 ? sc.scheme : '';
                  const nameW = textWidth(u.it.name, 9.5, 500) + 10;
                  const withTag = !!tag && cw >= textWidth(tag, 8, 600) + 12 + nameW;
                  const full = cw >= nameW;
                  const narrow = !full && cw >= textWidth(u.it.name.slice(0, 1), 9.5, 500) + 6;
                  const unk = unkCell(u.it, j && cells[j - 1].it, u.jl, cw, full ? (withTag ? textWidth(tag, 8, 600) + 12 : 0) + textWidth(u.it.name, 9.5, 500) : narrow ? cw : null, u.atL && x1 < 0, u.atR && x2 > W);
                  return { l: u.l, r: u.r, jl: u.jl, jr: u.jr, c: u.it, key: `phase:${u.it.ci}`, base: cellBaseOf(u.it, p, `phase:${u.it.ci}`), ink: full || narrow ? { text: u.it.name, size: 9.5, wt: 500, lh: 9.5 * 1.2 } : null, fixed: narrow || withTag, bl: cw < 8 ? 0 : 1, br: cw < 8 || u.jr ? 0 : 1, fade: unkFade(unk, u.l, u.r) };
                });
                const pplan = svgPlan(prow, { X: t => X(t) - left, lo: X(bandStart(p)) - left + 4, hi: X(bandEnd(p)) - left - 4, h: G.phase, now: p.endY });
                let run = [];
                const flush = () => {
                  if (!run.length) return;
                  const s = run[0].atL && x1 < 0 ? -12 : left + run[0].l;
                  const e = run[run.length - 1].atR && x2 > W ? W + 12 : left + run[run.length - 1].r;
                  /* 칸의 미정 (화면의 시기 칸 · 지도자 칸과 같은 규칙): 긴 칸의 바깥 끝이 미정이면 그쪽이 옅어지며 사라지고, 안쪽 경계가 미정이면 구분선이 점선 */
                  const u0 = run[0];
                  const u1 = run[run.length - 1];
                  const fl = u0.it.startUnknown && !(u0.atL && x1 < 0) ? Math.min(FADE, (u0.r - u0.l) * 0.4) : 0;
                  const fr = u1.it.endUnknown && !(u1.atR && x2 > W) ? Math.min(FADE, (u1.r - u1.l) * 0.4) : 0;
                  const [defs, mask] = fadeMask(GW + s, py, e - s, G.phase, fl, fr);
                  body += `${defs}<rect x="${n(GW + s)}" y="${n(py)}" width="${n(e - s)}" height="${G.phase}" rx="4" fill="${PAPER}" fill-opacity="0.8" stroke="${mixHex(MUTED, PAPER, 0.7)}"${mask}/>`;
                  run.forEach((u, j) => {
                    const ci = cells.indexOf(u);
                    if (j > 0) body += `<line x1="${n(GW + left + u.l)}" y1="${n(py + 2)}" x2="${n(GW + left + u.l)}" y2="${n(py + G.phase - 2)}" stroke="${mixHex(MUTED, PAPER, 0.7)}"${u.it.startUnknown || run[j - 1].it.endUnknown ? ' stroke-dasharray="2 2"' : zoneDiv(pplan, ci) ? ' stroke-dasharray="1 1"' : ''}/>`;
                    if (u.r - u.l > textWidth(u.it.name, 9.5, 500) + 10) body += txt(GW + left + (u.l + u.r) / 2 + (pplan.shift.get(ci) || 0), py + G.phase / 2 + 3, u.it.name, { size: 9, anchor: 'middle', fill: MUTED });
                  });
                  run = [];
                };
                for (const u of cells) {
                  if (!u.jl) flush();
                  run.push(u);
                }
                flush();
                body += svgAlt(prow, pplan, { ox: GW + left, top: py, h: G.phase, color: () => MUTED });
              });
            }
            /* 렌즈(설계 7-8 결정 5 A — 화면의 _lensRow와 같은 규칙): 지도자 칸 자리에 그 주제의 칸, 체제를 지위로 대신하면 지위 칸이 지도자 자리 · 지도자 칸이 지위 단 자리 */
            const lensS = this.themeLens && g.leaderH && !bird ? HT.lensCellsOf(p, this.themeLens.id) : null;
            const lensRank = !!lensS && lensS.src === 'rank';
            /* 지위 단: 화면과 같은 자리 · 같은 이음, 칸마다 서열 짙기(HT.RANK_MIX — 화면과 같은 표) */
            if ((gp.rankH || lensRank) && p.rankSpans) {
              const ry = y + (lensRank ? gp.leaderTop : gp.rankTop);
              const RH = lensRank ? g.leaderH : G.rank; // 렌즈로 지도자 칸 자리에 그릴 때는 그 높이 · 큰 글
              const RS = lensRank ? 11.5 : 9.5;
              const cells = layoutStrip(p.rankSpans, () => 0, c => X(c.start) - left, c => X(c.end) - left, 4, w - 4);
              const rrow = cells.map((u, j) => {
                const cw = u.r - u.l;
                const text = cw >= textWidth(u.it.name, RS, 600) + 10 ? u.it.name : cw >= textWidth(u.it.name.slice(0, 1), RS, 600) + 8 ? u.it.name.slice(0, 1) : '';
                const unk = unkCell(u.it, j && cells[j - 1].it, u.jl, cw, text ? textWidth(text, RS, 600) : null, u.atL && x1 < 0, u.atR && x2 > W);
                return { l: u.l, r: u.r, jl: u.jl, jr: u.jr, c: u.it, key: `rank:${u.it.i}`, base: cellBaseOf(u.it, p, `rank:${u.it.i}`), ink: text ? { text, size: RS, wt: 600, lh: RS * 1.2 } : null, bl: cw < 8 ? 0 : 1, br: cw < 8 || u.jr ? 0 : 1, fade: unkFade(unk, u.l, u.r) };
              });
              const rplan = svgPlan(rrow, { X: t => X(t) - left, lo: X(bandStart(p)) - left + 4, hi: X(bandEnd(p)) - left - 4, h: RH, now: p.endY });
              /* 칸 하나의 바탕: 무리의 바깥쪽 끝만 둥글게 (이어진 쪽은 곧게) */
              const box = (a, b, rl0, rr0, rl = Math.min(rl0, Math.max(0, Math.floor((b - a) / 2))), rr = Math.min(rr0, Math.max(0, Math.floor((b - a) / 2)))) => `M${n(a + rl)} ${n(ry)} H${n(b - rr)} ${rr ? `a${rr} ${rr} 0 0 1 ${rr} ${rr} V${n(ry + RH - rr)} a${rr} ${rr} 0 0 1 ${-rr} ${rr}` : `V${n(ry + RH)}`} H${n(a + rl)} ${rl ? `a${rl} ${rl} 0 0 1 ${-rl} ${-rl} V${n(ry + rl)} a${rl} ${rl} 0 0 1 ${rl} ${-rl}` : `V${n(ry)}`} Z`;
              let run = [];
              const flush = () => {
                if (!run.length) return;
                const s = run[0].atL && x1 < 0 ? -12 : left + run[0].l;
                const e = run[run.length - 1].atR && x2 > W ? W + 12 : left + run[run.length - 1].r;
                /* 칸의 미정 (지도자 칸과 같은 규칙): 긴 칸의 바깥 끝이 미정이면 그쪽이 옅어지며 사라지고, 안쪽 경계가 미정이면 구분선이 점선 */
                const u0 = run[0];
                const u1 = run[run.length - 1];
                const fl = u0.it.startUnknown && !(u0.atL && x1 < 0) ? Math.min(FADE, (u0.r - u0.l) * 0.4) : 0;
                const fr = u1.it.endUnknown && !(u1.atR && x2 > W) ? Math.min(FADE, (u1.r - u1.l) * 0.4) : 0;
                const [defs, mask] = fadeMask(GW + s, ry, e - s, RH, fl, fr);
                if (mask) body += `${defs}<g${mask}>`;
                run.forEach((u, j) => {
                  const mix = HT.RANK_MIX[u.it.level || 0] / 100;
                  const last = j === run.length - 1;
                  body += `<path d="${box(GW + (j === 0 ? s : left + u.l), GW + (last ? e : left + u.r), j === 0 ? 4 : 0, last ? 4 : 0)}" fill="${mixHex(p.color, PAPER, mix)}" fill-opacity="${mix > 0 ? 1 : 0.62}"/>`;
                });
                body += `<rect x="${n(GW + s)}" y="${n(ry)}" width="${n(e - s)}" height="${RH}" rx="4" fill="none" stroke="${edge(p.color, 0.92)}"/>`;
                if (mask) body += '</g>';
                run.forEach((u, j) => {
                  const ci = cells.indexOf(u);
                  if (j > 0) body += `<line x1="${n(GW + left + u.l)}" y1="${n(ry + 2)}" x2="${n(GW + left + u.l)}" y2="${n(ry + RH - 2)}" stroke="${edge(p.color, 0.92)}" stroke-opacity="0.7"${u.it.startUnknown || run[j - 1].it.endUnknown ? ' stroke-dasharray="2 2"' : zoneDiv(rplan, ci) ? ' stroke-dasharray="1 1"' : ''}/>`;
                  if (u.r - u.l > textWidth(u.it.name, RS, 600) + 10) body += txt(GW + left + (u.l + u.r) / 2 + (rplan.shift.get(ci) || 0), ry + RH / 2 + (lensRank ? 3.5 : 3), u.it.name, { size: lensRank ? 10.5 : 9, weight: 600, anchor: 'middle', fill: '#666666' });
                });
                run = [];
              };
              for (const u of cells) {
                if (!u.jl) flush();
                run.push(u);
              }
              flush();
              body += svgAlt(rrow, rplan, { ox: GW + left, top: ry, h: RH, color: () => p.color });
            }
            /* 렌즈를 켠 동안 지도자 칸: 그 주제 자료가 없는 나라는 옅게(dim) · 지위로 대신한 체제 렌즈면 지위 단 자리에 작게(mini) · 제도 · 붕당 칸이 있으면 그리지 않음(아래 렌즈 칸) */
            /* 단체 단(화면의 _groupRows와 같은 자리 · 같은 칸 — 설계 7-8 결정 1 A · 2 A + 덧판): 위 = 집권 · 아래 = 실권, 붕당 렌즈면 집권 줄 자리에 지도자 칸(작게)이 오고 집권 칸은 아래 렌즈 칸 자리로 */
            const gS = gp.powerH || gp.realH ? HT.groupStrip(p) : null;
            const lensGroup = !!lensS && lensS.src === 'group';
            if (gS && gp.powerH && gS.power.length && !lensGroup) body += groupSVG(gS.power, y + gp.powerTop, G.power, left, w, x1, x2);
            if (gS && gp.realH && gS.real.length) body += groupSVG(gS.real, y + gp.realTop, G.power, left, w, x1, x2);
            const nomSet = g.leaderH && this._groupsOn() ? HT.groupStrip(p).nominal : null; // 명목 지도자 칸 — 이름 글만 50% (화면의 is-nominal)
            const leadRows = !lensS ? [[g.leaderH ? p.leaders : null, gp.leaderTop, g.leaderH]] : !lensS.src ? [[this.show.leaders ? p.leaders : null, gp.leaderTop, g.leaderH, { dim: true }]] : lensRank && gp.rankH && this.show.leaders ? [[p.leaders, gp.rankTop, G.rank, { mini: true }]] : lensGroup && gp.powerH && this.show.leaders ? [[p.leaders, gp.powerTop, G.power, { mini: true }]] : [];
            for (const [list, cTop, cH, lo = {}] of leadRows.concat([[g.cabinetH ? p.cabinets : null, gp.cabinetTop, g.cabinetH]])) {
              const b0 = body.length;
              /* 이어지는 칸은 하나의 긴 둥근 칸 + 가는 구분선 (화면과 같은 배치) */
              const cells = layoutStrip((list || []).map((c, i) => ({ c, i })), v => v.c.dynasty || v.c.dynastyAuto || '', v => X(v.c.start) - left, v => X(v.c.end ?? p.endY) - left, 4, w - 4);
              /* 이설 · 모호한 칸: 화면과 같은 이름표 규칙(글자 크기 · 앞글자만)으로 계획 — 선 · '이설 있음'의 자리가 화면과 같게 */
              const kindC = list === p.leaders ? 'leader' : 'cabinet';
              const [csz, cwt] = lo.mini ? [9.5, 600] : kindC === 'leader' ? [11.5, 600] : [10.5, 500];
              const crow = cells.map((u, j) => {
                const cw = u.r - u.l;
                const text = kindC === 'leader' ? HT.leaderLabel(u.it.c, this.leaderMode, this.leaderOrdinal) : u.it.c.name;
                const full = cw >= textWidth(text, csz, cwt) + 12;
                const narrow = !full && cw >= textWidth(text.slice(0, 1), csz, cwt) + 8;
                const unk = unkCell(u.it.c, j && cells[j - 1].it.c, u.jl, cw, full ? textWidth(text, csz, cwt) : narrow ? cw : null, u.atL && x1 < 0, u.atR && x2 > W);
                return { l: u.l, r: u.r, jl: u.jl, jr: u.jr, c: u.it.c, key: `${kindC}:${u.it.i}`, base: cellBaseOf(u.it.c, p, `${kindC}:${u.it.i}`), ink: full || narrow ? { text, size: csz, wt: cwt, lh: csz * 1.2 } : null, fixed: narrow, bl: cw < 8 ? 0 : 1, br: cw < 8 || u.jr ? 0 : 1, fade: unkFade(unk, u.l, u.r), hasMax: kindC === 'leader' && this.show.houses && u.it.c.houseId ? cH - 5 : undefined }; // 가문 줄 위까지 (화면과 같게)
              });
              const cplan = svgPlan(crow, { X: t => X(t) - left, lo: X(bandStart(p)) - left + 4, hi: X(bandEnd(p)) - left - 4, h: cH, now: p.endY });
              let run = [];
              const flush = () => {
                if (!run.length) return;
                const s = run[0].atL && x1 < 0 ? -12 : left + run[0].l;
                const e = run[run.length - 1].atR && x2 > W ? W + 12 : left + run[run.length - 1].r;
                /* 칸의 미정: 긴 칸의 바깥 끝이 미정이면 그쪽이 옅어지며 사라지고, 안쪽 경계가 미정이면 구분선이 점선 */
                const u0 = run[0];
                const u1 = run[run.length - 1];
                const fl = u0.it.c.startUnknown && !(u0.atL && x1 < 0) ? Math.min(FADE, (u0.r - u0.l) * 0.4) : 0;
                const fr = u1.it.c.endUnknown && !(u1.atR && x2 > W) ? Math.min(FADE, (u1.r - u1.l) * 0.4) : 0;
                const [defs, mask] = fadeMask(GW + s, y + cTop, e - s, cH, fl, fr);
                body += `${defs}<rect x="${n(GW + s)}" y="${n(y + cTop)}" width="${n(e - s)}" height="${cH}" rx="5" fill="${PAPER}" fill-opacity="0.62" stroke="${edge(p.color, 0.92)}"${mask}/>`;
                run.forEach((u, j) => {
                  const ci = cells.indexOf(u);
                  if (j > 0) body += `<line x1="${n(GW + left + u.l)}" y1="${n(y + cTop + 2)}" x2="${n(GW + left + u.l)}" y2="${n(y + cTop + cH - 2)}" stroke="${edge(p.color, 0.92)}" stroke-opacity="0.7"${u.it.c.startUnknown || run[j - 1].it.c.endUnknown ? ' stroke-dasharray="2 2"' : zoneDiv(cplan, ci) ? ' stroke-dasharray="1 1"' : ''}/>`;
                  const cname = list === p.leaders ? HT.leaderLabel(u.it.c, this.leaderMode, this.leaderOrdinal) : u.it.c.name;
                  const ctext = u.r - u.l > textWidth(cname, lo.mini ? 9.5 : 10.5, 600) + 12 ? txt(GW + left + (u.l + u.r) / 2 + (cplan.shift.get(ci) || 0), y + cTop + cH / 2 + (lo.mini ? 3 : 3.5), cname, { size: lo.mini ? 8.5 : 10, anchor: 'middle', fill: '#666666' }) : '';
                  body += ctext && list === p.leaders && nomSet && nomSet.has(u.it.i) ? ctext.replace('<text ', '<text fill-opacity="0.5" ') : ctext; // 명목 지도자는 이름만 옅게
                });
                /* 가문 줄 (화면과 같은 규칙 — 표시 체크 '가문'이 켜져 있을 때). 긴 칸의 바깥 끝이 미정이면 칸과 같은 가림막으로 함께 옅어짐 */
                if (list === p.leaders && this.show.houses)
                  for (const hr of houseRuns(run, { l: x1 < 0, r: x2 > W }))
                    body += `<rect x="${n(GW + left + hr.l)}" y="${n(y + cTop + cH - 3)}" width="${n(hr.r - hr.l)}" height="2" rx="1" fill="${edge(hr.color, 0.72)}"${mask}/>`;
                run = [];
              };
              for (const u of cells) {
                if (!u.jl) flush();
                run.push(u);
              }
              flush();
              body += svgAlt(crow, cplan, { ox: GW + left, top: y + cTop, h: cH, color: () => p.color, bottom: kindC === 'leader' && this.show.houses ? 4 : 2 });
              if (lo.dim && body.length > b0) body = `${body.slice(0, b0)}<g opacity="0.4">${body.slice(b0)}</g>`; // 그 주제 자료가 없는 나라의 지도자 칸 (화면의 is-nolens)
            }
            /* 렌즈 칸 (화면의 _lensCells와 같은 자리 · 이음 · 글 줄임): 갈래 색 40% 칠 + 그 색의 테두리, 붕당의 연정 칸은 위아래 두 색 */
            if (lensS && lensS.src === 'inst') body += lensSVG(lensS, y + gp.leaderTop, g.leaderH, left, w, x1, x2);
            if (lensGroup) body += groupSVG(lensS.cells, y + gp.leaderTop, g.leaderH, left, w, x1, x2, true); // 붕당 렌즈 — 집권 단의 칸을 지도자 자리에 (화면의 _groupCells와 같은 꼴)
            /* 속국 이름표 (화면의 _depCells · _depHangs와 같게): 이 띠가 상국이면 품은 칸 · 매달린 탭 · 옮긴 때의 세로 끈 — 속국 띠 안에는 상국을 그리지 않음 */
            if (!this._bird && p._dep) {
              const dp = this._depSVG(tr, p, X, W, GW, y, bandH, geoOf(p._row), n, txt, edge, mixHex, PAPER, fadeMask, svgPlan, svgAlt);
              body += dp.svg;
              if (dp.hatch) depHatch = true;
            }
          }
          /* 기관(띠 안 맨 아래 기관 칸) · 구역(띠 아래로 내려오는 탭) */
          for (const p of tr.overlays || []) {
            const zone = p.scale === 'zone';
            for (const h of p.hosts) {
              let host = tr.periods.find(q => q.uid === h.host.uid);
              while (host && host._hidden) host = host._host;
              if (!host || host._row == null || tr.foldedRows.has(host._row) || hidden(host._row)) continue;
              if (bird || (!zone && !g.organH)) continue; // 조감에는 기관 칸 · 구역 탭이 없음 (화면과 같게)
              const a = X(Math.max(bandStart(p), h.start ?? -Infinity, bandStart(host)));
              const b = X(Math.min(bandEnd(p), h.end ?? Infinity, bandEnd(host)));
              const hb0 = X(bandStart(host)) - (host.startUnknown ? FADE : 0);
              const hb1 = X(bandEnd(host)) + (host.endUnknown ? FADE : 0);
              const inset = zone ? 10 : G.bw + G.pad2;
              const l = Math.max(a > hb0 + inset ? a + 0.5 : hb0 + inset, -12);
              const r = Math.min(b < hb1 - inset ? b - 0.5 : hb1 - inset, W + 12);
              if (r - l < 2 || r < 0 || l > W) continue;
              const rowY = top + tr.rowTop[host._row];
              const bandH = tr.rowHs[host._row] - ((tr.rowCut && tr.rowCut[host._row]) || 0);
              const oy = zone ? rowY + bandH + G.zoneGap + (tr.hangRowLanes.get(host._row) || 0) * HANG.pitch + (p._zoneLane[h.host.uid] ?? 0) * (G.zoneTab + G.zoneGap) : rowY + geoOf(host._row).organTop; // 속국 이름표가 매달린 줄 아래에 (화면과 같게)
              const oh = zone ? G.zoneTab : g.organH;
              body += `<rect x="${n(GW + l)}" y="${n(oy)}" width="${n(r - l)}" height="${oh}" rx="5" fill="${p.color}" fill-opacity="${zone ? 0.06 : 0.1}"/><rect x="${n(GW + l)}" y="${n(oy)}" width="${n(r - l)}" height="${oh}" rx="5" fill="${orgHatch(p.color)}" stroke="${edge(p.color, 0.92)}" stroke-opacity="0.75"${zone ? '' : ' stroke-dasharray="3 2"'}/>`; // 기관 · 구역은 둘 다 성긴 빗금(외세의 손길 — 묶음 3 · 2번)
              /* 기관 · 구역 항목 자신의 이설 (화면과 같은 계획 — 칸 하나짜리 줄, 이름은 보이는 폭의 가운데) */
              const named = r - l > textWidth(p.name, zone ? 9.5 : 10.5, 600) + 14;
              const oalts = HT.datedAlts(p);
              const vl = Math.max(l, 0);
              const vr = Math.min(r, W);
              const orow = oalts.length ? [{ l, r, c: { alternatives: oalts }, key: `org:${p.uid}`, base: itemBaseOf(p), ink: named ? { text: p.name, size: zone ? 9 : 10, wt: 400, lh: oh, c: (vl + vr) / 2 } : null, bl: 1, br: 1 }] : [];
              const oplan = orow.length ? svgPlan(orow, { X, lo: l, hi: r, h: oh, now: p.endY }) : null;
              if (named) body += txt(GW + (vl + vr) / 2 + ((oplan && oplan.shift.get(0)) || 0), oy + oh / 2 + 3.5, p.name, { size: zone ? 9 : 10, anchor: 'middle', fill: '#666666' });
              if (oplan) body += svgAlt(orow, oplan, { ox: GW, top: oy, h: oh, color: () => p.color });
            }
          }
          /* 인물 단 (화면과 같은 배치 — _figureGroups): 활동 막대는 둥근 칸, 빽빽하면 한 칸. 수명선은 화면에서도 올렸을 때만 보이므로 그리지 않습니다 */
          for (const { host, row, g: fg, vlo, vhi, bars, avg } of this._figureGroups(tr, X, W)) {
            const fy = top + tr.rowTop[row] + fg.figTop;
            if (bars.length > 1 && avg < 6) {
              body += `<rect x="${n(GW + vlo)}" y="${n(fy)}" width="${n(vhi - vlo)}" height="${G.figure}" rx="6" fill="${host.color}" fill-opacity="0.12" stroke="${edge(host.color, 0.92)}" stroke-opacity="0.7" stroke-dasharray="2 2"/>`;
              const label = `인물 ${bars.length}명`;
              if (vhi - vlo > textWidth(label, 10, 500) + 12) body += txt(GW + (vlo + vhi) / 2, fy + G.figure / 2 + 3.5, label, { size: 10, anchor: 'middle', fill: '#666666' });
              continue;
            }
            for (const { x, la, rb } of bars) {
              const l = Math.max(la, -12);
              const r = Math.min(rb, W + 12);
              const c = x.s.color || host.color;
              const by = fy + x.lvl * (G.figure + G.figGap);
              /* 활동 막대의 이설 · 모호한 연대 — 화면과 같은 계획(같은 단의 다른 사람 막대에는 선을 긋지 않음) */
              const fl0 = Math.max(la, 0);
              const fw0 = Math.min(rb, W) - fl0;
              const fwt = (x.f.importance || 2) >= 3 ? 700 : 500;
              const fplain = fw0 >= textWidth(x.f.name, 10, fwt) + 12 ? x.f.name : fw0 >= textWidth(x.f.name.slice(0, 1), 10, fwt) + 8 ? x.f.name.slice(0, 1) : '';
              const ftw = fplain ? textWidth(fplain, 10, fwt) : null;
              const funk = fw0 >= 8 ? unkCell(this._figUnk(x.s, host), null, false, fw0, ftw, la < 0, rb > W) : null;
              const frow = [{ l: fl0, r: fl0 + fw0, c: figBarCell(x.f, x.s), key: `fig:${x.f.uid}:${x.s.polityUid}:${x.i || 0}`, base: { start: x.s.from, startAt: x.s.fromAt, end: x.s.to, endAt: x.s.toAt, startUnknown: x.s.fromUnknown, endUnknown: x.s.toUnknown }, ink: fplain ? { text: fplain, size: 10, wt: fwt, lh: 10 } : null, bl: fw0 < 8 ? 0 : 1, br: fw0 < 8 ? 0 : 1, fade: unkFade(funk, fl0, fl0 + fw0) }].concat(bars.filter(q => q.x !== x && q.x.lvl === x.lvl).map(q => ({ l: q.la, r: q.rb, ink: { text: '·', size: 10, wt: 500 }, fixed: true, c: null })));
              const fplan = svgPlan(frow, { X, lo: X(bandStart(host)) + G.bw + G.pad2, hi: X(bandEnd(host)) - G.bw - G.pad2, h: G.figure, now: x.f.endY });
              const strong = (x.f.importance || 2) >= 3;
              /* 칸의 미정: 섬긴 기간의 미정인 끝이 옅어지며 사라짐 (화면과 같은 조건 — 막대의 그 끝이 진짜 끝이고 화면에 잘리지 않았을 때 · 아주 좁은 막대는 그대로) */
              const fu = rb - la >= 8 ? this._figUnk(x.s, host) : {};
              const [fdefs, fmask] = fadeMask(GW + l, by, Math.max(1, r - l), G.figure, fu.startUnknown && la >= 0 ? Math.min(FADE, (rb - la) * 0.4) : 0, fu.endUnknown && rb <= W ? Math.min(FADE, (rb - la) * 0.4) : 0);
              body += `${fdefs}<rect x="${n(GW + l)}" y="${n(by)}" width="${n(Math.max(1, r - l))}" height="${G.figure}" rx="7" fill="${mixHex(c, PAPER, strong ? 0.5 : 0.3)}" stroke="${edge(c, 0.92)}" stroke-opacity="${strong ? 1 : 0.75}"${fmask}/>`;
              const sl = Math.max(la, 0);
              const sw = Math.min(rb, W) - sl;
              if (sw > textWidth(x.f.name, 10, strong ? 700 : 500) + 12) body += txt(GW + sl + sw / 2 + (fplan.shift.get(0) || 0), by + G.figure / 2 + 3.5, x.f.name, { size: 10, weight: strong ? 700 : 500, anchor: 'middle', fill: edge(c, 0.4) });
              for (const i of [...fplan.zones.keys()]) if (i) fplan.zones.delete(i); // 다른 사람 막대의 무늬는 그 막대 차례에
              body += svgAlt(frow, fplan, { ox: GW, top: by, h: G.figure, color: () => c });
            }
          }
          for (let row = 0; row < tr.rows; row++) {
            if (hidden(row)) continue;
            const pick = (tr.rowPeriods[row] || []).find(q => q.start <= (start + end) / 2 && (start + end) / 2 <= q.endY) || (tr.rowPeriods[row] || [])[0];
            /* 접힌 줄은 화면의 왼쪽 줄 이름처럼 접힌 묶음의 이름 (민족 묶음 · 접힌 대범위 가지 — 그 가지의 이름) */
            const gp = tr.foldedRows.has(row) ? tr.groups.find(x => x.first === row && x.folded) : null;
            const name = gp && gp.name ? gp.name : pick ? (tr.foldedRows.has(row) ? pick.peopleName || pick.name : pick.name) : '';
            /* 조감: 줄 이름은 10.5px (모양 c는 글 없이 제 색 점만 — 화면의 줄 이름 칸과 같게) */
            if (name && bird && !bird.name) labels += `<circle cx="${n(COL.track + this.depth * COL.people + 8 + 2.5)}" cy="${n(top + this._rowMid(tr, row))}" r="2.5" fill="${gp && gp.color ? gp.color : pick ? pick.color : tr.color}"/>`;
            else if (name) {
              /* 원어 병기(10건 3 · 감독 결정 D2-2 — 화면의 왼쪽 줄 이름 칸과 같은 원어): 그림의 줄 이름 칸에 들 때만 이름 뒤 4px에 보통 굵기 · 옅은 빛, 글 방향은 가둠 */
              const lx = COL.track + this.depth * COL.people + 8;
              const o = !bird && !gp && !tr.foldedRows.has(row) && pick && this.origOf ? this.origOf(pick) : null;
              if (o && textWidth(name, 12, 700) + 4 + textWidth(o.text, 12, 400) <= GW - lx - 8)
                labels += `<text x="${n(lx)}" y="${n(top + this._rowMid(tr, row) + 4)}" font-size="12" font-weight="700" fill="${INK}">${esc(name)}<tspan dx="4" font-weight="400" fill="${MUTED}" style="unicode-bidi:isolate">${esc(o.text)}</tspan></text>`;
              else labels += txt(lx, top + this._rowMid(tr, row) + (bird ? 3.5 : 4), name, { size: bird ? 10.5 : 12, weight: 700 });
            }
          }
          /* 건국 · 멸망 네모 · 승계선 · 소속선 (화면과 같은 자리 — _linkPlan): 선은 띠 뒤(위에서 남겨 둔 자리에 끼움), 네모 · 관문 · 다리 · 문은 사건 다음(맨 위 — 화면의 .tl-marks).
             사건 글자는 화면처럼 네모(글줄이 하나인 줄)와 내림줄을 비켜 갑니다 */
          const zScreen = tr._bnmZ;
          tr._bnmZ = bird ? bzones : null; // 조감: 내림줄 · 오름줄이 띠 안 이름 · 단추를 비켜 가게 (화면과 같은 규칙 — 그림의 폭으로 잰 자리)
          const plan = this._linkPlan(tr, X, W, { tabR: p => (svgTab.has(p.uid) ? svgTab.get(p.uid) : null) });
          tr._bnmZ = zScreen;
          body = body.slice(0, backAt) + this._backSVG(plan, holes, `tllk${ti}`, GW, top, { x: GW - 20, y: top - 20, w: W + 40, h: trH + 40 }, { PAPER, edge }) + body.slice(backAt);
          const reserved = Array.from({ length: tr.rows }, (_, r) => Array.from({ length: geoOf(r).lines }, () => []));
          const noDot = Array.from({ length: tr.rows }, () => []);
          for (const p of tr.periods) {
            if (p._hidden || p._overlay || p._under || p._folded || p._row == null || hidden(p._row)) continue;
            if (X(bandEnd(p)) < 0 || X(bandStart(p)) > W) continue;
            const nL = geoOf(p._row).lines;
            this._sqZones(this._squares(p, X, nL, W), reserved[p._row].slice(0, nL === 1 ? 1 : 2), nL === 1 ? noDot[p._row] : null);
          }
          for (const z of plan.zones) for (const zk of z.lines) if (reserved[z.row] && reserved[z.row][zk]) reserved[z.row][zk].push([z.l, z.r]);
          const bounds = new Map(tr.periods.map(p => [p.uid, [X(bandStart(p)), X(bandEnd(p))]]));
          for (const p of tr.periods) {
            if (!p._hidden) continue;
            let h = p._host;
            while (h && h._hidden) h = h._host;
            if (h && bounds.has(h.uid)) bounds.set(p.uid, bounds.get(h.uid));
          }
          const ctx = { bandBounds: bounds, expanded: new Set(), reserved, noDot };
          if (bird) {
            /* 조감: 화면과 같은 띠 범위(미정인 끝은 사라지는 꼬리까지 · 바탕 문화는 없음 · 기관 · 구역은 얹히는 띠 안) · 사건 이름 없이 · 띠 안 이름 · 단추 자리의 점은 숨김 */
            for (const p of tr.periods) {
              if (p._under) bounds.delete(p.uid);
              else if (!p._hidden && !p._overlay) bounds.set(p.uid, [X(bandStart(p)) - (p.startUnknown ? FADE : 0), X(bandEnd(p)) + (p.endUnknown ? FADE : 0)]);
            }
            for (const p of tr.periods) {
              if (!p._hidden) continue;
              let h = p._host;
              while (h && h._hidden) h = h._host;
              if (h && bounds.has(h.uid)) bounds.set(p.uid, bounds.get(h.uid));
            }
            for (const p of tr.overlays || []) {
              const host = p.hosts
                .map(h => {
                  let q = tr.periods.find(x => x.uid === h.host.uid);
                  while (q && q._hidden) q = q._host;
                  return q;
                })
                .find(q => q && q._row === p._row && bounds.has(q.uid));
              const hb = host && bounds.get(host.uid);
              const ob = [X(bandStart(p)), X(bandEnd(p))];
              if (!hb) bounds.delete(p.uid);
              else bounds.set(p.uid, Math.min(ob[1], hb[1]) > Math.max(ob[0], hb[0]) ? [Math.max(ob[0], hb[0]), Math.min(ob[1], hb[1])] : hb);
            }
            Object.assign(ctx, { minImp: 99, bird: { zones: bzones, common: tr.commonRow } });
          }
          for (let row = 0; row < tr.rows; row++) {
            if (hidden(row) || tr.foldedRows.has(row)) continue;
            const rowY = top + tr.rowTop[row];
            const placed = bird && !bird.dots ? [] : this._placeRow(tr.eventsByRow[row] || [], X, W, tr, ctx, row); // 조감 b · c는 점 · 알약 없음
            const levels = Array.from({ length: g.railLevels || 2 }, () => []);
            const lensId = this.themeLens ? this.themeLens.id : null; // 렌즈: 그 주제가 아닌 사건 · 묶음은 옅게(.26) · 그 주제의 사건은 주제 색 고리 (화면의 is-lens · no-lens)
            for (const cl of placed.clusters || []) {
              const lead = cl.lead.e;
              const c = (lead._place && lead._place.polityColor) || lead.polityColor || lead.color;
              const ly = rowY + geoOf(row).textTop + cl.sub * g.lineH + g.lineH / 2;
              const cb0 = body.length;
              const cdim = !!lensId && !cl.members.some(m => HT.lensEventHit(m.e, lensId));
              const cwrap = () => {
                if (cdim && body.length > cb0) body = `${body.slice(0, cb0)}<g opacity="0.26">${body.slice(cb0)}</g>`;
              };
              if (bird || cl.sm) {
                /* 조감의 알약(과 보통 밀도의 좁은 띠에서 작게 그린 알약): 높이 10 · 8px 글자 · 안쪽 1px 테 (화면과 같게 — 자리 선 · 눈금 없음) */
                body += `<rect x="${n(GW + cl.x - cl.w / 2 + 0.5)}" y="${n(ly - 4.5)}" width="${n(cl.w - 1)}" height="9" rx="4.5" fill="${mixHex(c, PAPER, 0.24)}" stroke="${edge(c)}" stroke-opacity="0.55"/>`;
                body += txt(GW + cl.x, ly + 3, String(cl.members.length), { size: 8, weight: 700, anchor: 'middle', fill: edge(c, 0.55) });
                cwrap();
                continue;
              }
              if (cl.r - cl.l > cl.w - 8) body += `<line x1="${n(GW + cl.l)}" y1="${n(ly + 5.5)}" x2="${n(GW + cl.r)}" y2="${n(ly + 5.5)}" stroke="${edge(c)}" stroke-opacity="0.45" stroke-width="1"/>`;
              body += `<rect x="${n(GW + cl.x - cl.w / 2)}" y="${n(ly - 6.5)}" width="${n(cl.w)}" height="13" rx="6.5" fill="${mixHex(c, PAPER, 0.28)}" stroke="${edge(c)}" stroke-opacity="0.7"/>`;
              body += txt(GW + cl.x, ly + 3.5, String(cl.members.length), { size: 9.5, weight: 700, anchor: 'middle', fill: edge(c, 0.55) });
              cwrap();
            }
            for (const it of placed) {
              const ev = it.e;
              const eb0 = body.length;
              const lensHit = !!lensId && HT.lensEventHit(ev, lensId);
              const ewrap = () => {
                if (lensId && !lensHit && body.length > eb0) body = `${body.slice(0, eb0)}<g opacity="0.26">${body.slice(eb0)}</g>`;
              };
              const c = (ev._place && ev._place.polityColor) || ev.polityColor || ev.color;
              const ly = rowY + geoOf(row).textTop + it.sub * g.lineH + g.lineH / 2;
              const alts = this.showAlt && !it.sec ? HT.datedAlts(ev) : [];
              const fuzzy = ev.startRange || ev.endRange;
              if (!bird && (it.ranged || fuzzy || alts.length)) {
                /* 화면과 같은 규칙: 기간 막대 칸의 2~3단, 띠 안쪽으로 가둠. 그림 가장자리를 넘는 쪽에는 끝 세로바를 그리지 않습니다 */
                const C = it.clamp;
                const xs = it.ranged ? [it.rx, it.rx2] : [C(it.x)];
                if (ev.startRange) xs.push(C(X(ev.startRange[0])), C(X(ev.startRange[1])));
                if (ev.endRange) xs.push(C(X(ev.endRange[0])), C(X(ev.endRange[1])));
                alts.forEach(a => xs.push(C(X(a.start)), C(X(a.end ?? a.start))));
                const lvl = pickLevel(levels, Math.min(...xs) - 4, Math.max(...xs) + 4);
                const ry = rowY + geoOf(row).railTop + 3.5 + lvl * G.railPitch;
                const bar = (x, op = 1) => `<rect x="${n(GW + x)}" y="${n(ry - 3)}" width="1.5" height="6" rx="0.75" fill="${edge(c)}" fill-opacity="${op}"/>`;
                if (it.ranged) {
                  const l = Math.max(it.rx, -4);
                  const r = Math.min(it.rx2, W + 4);
                  if (ev.treaty) {
                    /* 조약: 겹줄 가는 선 (함께 겪은 자리는 점선 겹줄) + 발효가 체결과 다르면 작은 마름모 눈금 — 화면과 같은 규칙 */
                    for (const dy of [-1.5, 1.5]) body += `<line x1="${n(GW + l)}" y1="${n(ry + dy)}" x2="${n(GW + Math.max(l + 2, r))}" y2="${n(ry + dy)}" stroke="${edge(c, 0.92)}" stroke-opacity="0.8" stroke-width="1"${it.sec ? ' stroke-dasharray="4 3"' : ''}/>`;
                    const eff = ev.treaty.effective;
                    const fx0 = eff != null && Math.abs(eff - ev.start) > 1e-6 ? X(eff) : NaN;
                    if (fx0 > it.rx + 3 && fx0 < Math.min(it.rx2, W + 4) - 3) body += `<polygon points="${[[0, -3], [3, 0], [0, 3], [-3, 0]].map(([a, b]) => `${n(GW + fx0 + a)},${n(ry + b)}`).join(' ')}" fill="${edge(c)}"/>`;
                  } else {
                    body += it.sec
                      ? `<line x1="${n(GW + l)}" y1="${n(ry)}" x2="${n(GW + Math.max(l + 2, r))}" y2="${n(ry)}" stroke="${edge(c, 0.92)}" stroke-opacity="0.8" stroke-width="2" stroke-dasharray="4 3"/>`
                      : `<rect x="${n(GW + l)}" y="${n(ry - 1)}" width="${n(Math.max(2, r - l))}" height="2" rx="1" fill="${edge(c, 0.92)}" fill-opacity="0.8"/>`;
                  }
                  if (it.rx >= 0) body += bar(it.rx);
                  if (it.rx2 <= W) body += bar(it.rx2 - 1.5);
                }
                if (!it.ranged) {
                  /* 점 사건: 점선 실에 꿴 구슬 (화면과 같은 규칙 — 연대 폭의 눈금 없음) */
                  const { beads, edges, lo, hi } = beadsOf(ev, alts, C(it.x), C, X, false);
                  if (hi - lo >= 3) {
                    body += `<line x1="${n(GW + lo)}" y1="${n(ry)}" x2="${n(GW + hi)}" y2="${n(ry)}" stroke="${edge(c, 0.92)}" stroke-opacity="0.75" stroke-width="1" stroke-dasharray="1 2"/>`;
                    for (const d of edges) body += `<line x1="${n(GW + d.x)}" y1="${n(ry - 2.5)}" x2="${n(GW + d.x)}" y2="${n(ry + 2.5)}" stroke="${edge(c, 0.92)}" stroke-width="1"/>`;
                    for (const b of beads) body += `<circle cx="${n(GW + b.x)}" cy="${n(ry)}" r="2.6" fill="${b.kind === 'alt' ? PAPER : edge(c, 0.92)}" stroke="${edge(c)}" stroke-width="${b.kind === 'alt' ? 1.2 : 0.8}"/>`;
                  }
                }
                if (it.ranged) for (const rg of [ev.startRange, ev.endRange]) {
                  if (!rg) continue;
                  const l = C(X(rg[0]));
                  const r = Math.max(l + 2, C(X(rg[1])));
                  body += `<rect x="${n(GW + l)}" y="${n(ry - 2.5)}" width="${n(r - l)}" height="5" rx="2.5" fill="${c}" fill-opacity="0.3"/>`;
                }
                if (it.ranged && alts.length) {
                  const base = it.ranged ? it.rx : C(it.x);
                  const axs = alts.map(a => {
                    const x = C(X(a.start));
                    return Math.abs(x - base) < 4 ? base + (x < base ? -4 : x > base ? 4 : -4) : x;
                  });
                  const lo = Math.min(...axs, base);
                  const hi = Math.max(...axs, base);
                  body += `<line x1="${n(GW + lo)}" y1="${n(ry)}" x2="${n(GW + hi)}" y2="${n(ry)}" stroke="${edge(c, 0.92)}" stroke-width="1" stroke-dasharray="3 2" stroke-opacity="0.8"/>`;
                  axs.forEach(x => (body += `<line x1="${n(GW + x)}" y1="${n(ry - 4.5)}" x2="${n(GW + x)}" y2="${n(ry + 4.5)}" stroke="${edge(c)}" stroke-width="1.5" stroke-dasharray="2 2"/>`));
                  /* 이설의 끝 (화면과 같은 규칙 altEnds) */
                  const ends = altEnds(ev, alts, it.rx2, C, X);
                  if (ends.length) {
                    const lo2 = Math.min(...ends.map(q => q.x), it.rx2);
                    const hi2 = Math.max(...ends.map(q => q.x), it.rx2);
                    body += `<line x1="${n(GW + lo2)}" y1="${n(ry)}" x2="${n(GW + hi2)}" y2="${n(ry)}" stroke="${edge(c, 0.92)}" stroke-width="1" stroke-dasharray="3 2" stroke-opacity="0.8"/>`;
                    ends.forEach(q => (body += `<line x1="${n(GW + q.x)}" y1="${n(ry - 4.5)}" x2="${n(GW + q.x)}" y2="${n(ry + 4.5)}" stroke="${edge(c)}" stroke-width="1.5" stroke-dasharray="2 2"/>`));
                  }
                }
              }
              if (it.hidden) {
                ewrap();
                continue; // 알약에 묶였거나 이름 붙은 사건에 겹쳐 쌓임
              }
              if (it.more) body += `<circle cx="${n(GW + it.x + 2.2)}" cy="${n(ly - 2.2)}" r="3.5" fill="${PAPER}" stroke="${edge(c)}" stroke-width="0.8"/>`;
              if (ev.treaty) {
                /* 조약: 마름모 인장 — 제 자리는 채운 마름모, 다른 당사국 자리는 속 빈 마름모 (대각선이 점의 지름을 넘지 않게) */
                const r = bird || it.sm ? 2.8 : it.sec ? 4.4 : 3.6;
                body += `<polygon points="${[[0, -r], [r, 0], [0, r], [-r, 0]].map(([a, b]) => `${n(GW + it.x + a)},${n(ly + b)}`).join(' ')}" fill="${it.sec ? '#ffffff' : c}" stroke="${edge(c)}" stroke-width="${it.sec ? 1.3 : 0.8}" stroke-linejoin="round"/>`;
              } else if (bird || it.sm) body += `<circle cx="${n(GW + it.x)}" cy="${n(ly)}" r="4.5" fill="${mixHex(c, PAPER, 0.12)}"/><circle cx="${n(GW + it.x)}" cy="${n(ly)}" r="${it.child ? 2 : 2.5}" fill="${it.sec ? '#ffffff' : c}" stroke="${edge(c)}" stroke-width="${it.sec ? 1.2 : 0.8}"/>`; // 조감의 점(과 보통 밀도의 좁은 띠에서 작게 그린 점): 5px + 둘레 2px (화면과 같게)
              else body += `<circle cx="${n(GW + it.x)}" cy="${n(ly)}" r="3.5" fill="${it.sec ? '#ffffff' : c}" stroke="${edge(c)}" stroke-width="${it.sec ? 1.5 : 0.8}"/>`;
              if (lensHit) body += `<circle cx="${n(GW + it.x)}" cy="${n(ly)}" r="${bird || it.sm ? 4.5 : 5.5}" fill="none" stroke="${edge(this.themeLens.color, 0.85)}" stroke-width="1.5"/>`; // 렌즈 주제 색 고리 (화면의 is-lens)
              if (it.label) body += txt(it.flip ? GW + it.x - 8 : GW + it.x + 8, ly + 4, it.text, { size: g.font, anchor: it.flip ? 'end' : 'start', fill: INK });
              ewrap();
            }
          }
          body += this._marksSVG(tr, plan, X, W, GW, top, { PAPER, edge }); // 맨 위 (화면의 .tl-marks)
        }
        top += trH;
        body += `<line x1="0" y1="${n(top)}" x2="${svgW}" y2="${n(top)}" stroke="#cccccc"/>`;
      });

      const head =
        `<rect width="${svgW}" height="${total}" fill="${PAPER}"/>` +
        (title ? txt(16, 32, title, { size: 20, weight: 500 }) : '') +
        txt(svgW - 8, total - 8, (() => {
          const sub = HT.cal ? HT.cal.subStep(k) : null;
          const p = !sub ? 'y' : sub.unit === 'mo' ? 'm' : sub.unit === 'd' ? 'd' : 'h';
          const f = t => (p === 'y' ? HT.formatYear(t) : HT.cal.formatT(t, p));
          return `${f(start)} ~ ${f(end)}`;
        })(), { size: 11, fill: MUTED, anchor: 'end' });

      return (
        `<svg xmlns="http://www.w3.org/2000/svg" width="${svgW}" height="${total}" viewBox="0 0 ${svgW} ${total}" font-family="Pretendard, ChosunKm, Malgun Gothic, Apple SD Gothic Neo, Noto Sans KR, sans-serif">` +
        `<defs><clipPath id="tlclip"><rect x="${GW}" y="${bodyTop}" width="${W}" height="${total - bodyTop}"/></clipPath>${body.includes('url(#hs-') ? HS_SVG_DEFS : ''}${depHatch ? DEP_HATCH_SVG : ''}${[...orgDefs.values()].map(z => z.def).join('')}${[...zoneDefs.values()].map(z => z.def).join('')}</defs>` +
        head + grid + `<g clip-path="url(#tlclip)">${body}</g>` + labels + axis + '</svg>'
      );
    }
  }

  /* (공개 — 검사용) 책갈피 탭의 글을 정하는 함수들: 화면과 그림 내보내기가 같은 것을 부릅니다 (scripts/dev-smoke.mjs ㉒가 노드에서 확인) */
  Timeline.tabParts = tabParts;
  Object.assign(Timeline, { intervalIndex, intervalQuery, intervalHas, visibleRows });
  Timeline.depProxies = depProxies; // 속국 이름표 목록 (dev-smoke가 노드에서 확인)
  Timeline.TAB = TAB; // 간지 탭의 값 (dev-smoke · 새 앱 내보내기가 확인)
  Timeline.PLATE = PLATE; // 상국 표기 C의 값 — 뒤 장의 어긋남 · 둥근 값 · 칠 (dev-smoke가 확인)
  Timeline.EPOCH_FOLD = EPOCH_FOLD; // 시대 접기의 열쇠 (날짜 칸 묶음 기억 axisOpen — 새 검사 · 새 앱이 같은 이름을 씀)
  Timeline.depLook = depLook; // 소속 하나의 모습(빈 · 칠한 · 점선 · 파선 · 옅은 · 짙은 · 빗금) — 새 앱 내보내기의 뒤 장의 탭(구역 47)이 같은 규칙으로
  Timeline.tabBump = tabBump;
  /** (범례 — viewer.js) 상국 표기 견본(건의 8의 2번 C — 감독 확정 2026-10-14): 띠 뒤의 뒤 장(상국 빛깔 — 종속 · 보호 · 위성의 짙기)이 위로 드러나고, 그 평평한 윗변의 오른쪽 끝(관계가 끝나는 쪽)에
      같은 칠 · 테의 상국 탭(이음매 선 없이 한 덩어리) · 띠 윗변 왼쪽에 제 이름 탭 · 띠 둘레의 종이빛 틈. 연표와 같은 윤곽(tabBump · 어깨 4) · 같은 차례(뒤 장 < 받침 < 상국 탭 < 제 이름 탭 < 띠) ·
      뒤 장의 어긋남 · 틈 · 탭 올림은 연표 값(PLATE)의 0.6배 · 폭 34 · 높이 15 */
  Timeline.hostTabSample = (cp = '#bba395', cq = '#a0bcc5') => {
    const W = 34, H = 15, k = 0.6;
    const rise = PLATE.rise * k, shift = PLATE.shift * k, gap = PLATE.gap * k, th = 8 - rise;
    const bx = 0.5, by = 8.5, bw = 33, bh = 6;
    const f = v => Number(v).toFixed(2).replace(/\.?0+$/, '');
    const pl = bx + 10 + shift, pw = bw - 10; // 뒤 장: 관계가 띠 중간에서 시작해 띠 끝까지
    const own = tabBump(1.5, 0.5, 12, 8, 4), host = tabBump(pl + pw - 3 - 12, 0.5, 12, th + 1, 4);
    const fill = mixOk(cq, '#ffffff', PLATE.mix.firm), line = mixOk(cq, '#000000', PLATE.edge);
    return `<svg class="lg-seam" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" aria-hidden="true"><rect x="${f(pl)}" y="${f(by - rise)}" width="${f(pw)}" height="${bh}" rx="3" fill="${fill}" stroke="${line}"/><rect x="${f(bx - gap)}" y="${f(by - gap)}" width="${f(bw + 2 * gap)}" height="${f(bh + 2 * gap)}" rx="${f(3 + gap)}" fill="#ffffff"/><path d="${host} Z" fill="${fill}"/><path d="${host}" fill="none" stroke="${line}"/><path d="${own} Z" fill="${cp}" fill-opacity=".16"/><path d="${own}" fill="none" stroke="${cp}"/><rect x="${bx}" y="${by}" width="${bw}" height="${bh}" rx="3" fill="${cp}" fill-opacity=".16" stroke="${cp}"/></svg>`;
  };
  /** (범례 — viewer.js가 부를 자리) 연합의 겹 탭 견본: 띠 윗변 위에 같은 윤곽(tabBump · 어깨 4)의 앞 장과, 4px 오른쪽 · 3px 위의 뒤 장(연표 TAB.backDx · backDy와 같은 어긋남) — 폭 34 · 높이 15 */
  Timeline.coalTabSample = (cp = '#bba395', cc = '#9dbea8') => {
    const W = 34, H = 15;
    const back = tabBump(12.5, 0.5, 15, 11, 4), front = tabBump(8.5, 3.5, 15, 8, 4);
    return `<svg class="lg-seam" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" aria-hidden="true"><path d="${back} Z" fill="${mixHex(cc, '#ffffff', 0.18)}"/><path d="${back}" fill="none" stroke="${cc}"/><path d="${front} Z" fill="${mixHex(cc, '#ffffff', 0.34)}"/><path d="${front}" fill="none" stroke="${cc}"/><rect x="0.5" y="11.5" width="${W - 1}" height="${H - 12}" rx="2" fill="${cp}" fill-opacity=".16" stroke="${cp}"/></svg>`;
  };
  /** (범례 — viewer.js가 부를 자리) 단체 단 견본(설계 7-8 결정 1 · 2 + 덧판): kind 'power' 집권 칸(40%) · 'real' 실권 칸(78% · 짙은 테두리) · 'coal' 연정 칸(위아래 두 색 + 점 둘) — 폭 34 · 높이 11 */
  Timeline.groupCellSample = (kind = 'power', c = '#bbacc8', c2 = '#9dbea8') => {
    const W = 34, H = 11;
    const fill = kind === 'real' ? mixHex(c, '#ffffff', 0.78) : mixHex(c, '#ffffff', 0.4);
    const line = kind === 'real' ? mixHex(c, '#000000', 0.64) : mixHex(c, '#000000', 0.92);
    const body = kind === 'coal'
      ? `<clipPath id="lgg-${kind}"><rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="3"/></clipPath><g clip-path="url(#lgg-${kind})"><rect x="0" y="0" width="${W}" height="${H / 2}" fill="${mixHex(c, '#ffffff', 0.42)}"/><rect x="0" y="${H / 2}" width="${W}" height="${H / 2}" fill="${mixHex(c2, '#ffffff', 0.42)}"/></g><circle cx="13" cy="${H / 2}" r="2.5" fill="${c}" stroke="${mixHex(c, '#000000', 0.64)}"/><circle cx="21" cy="${H / 2}" r="2.5" fill="${c2}" stroke="${mixHex(c2, '#000000', 0.64)}"/>`
      : `<rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="3" fill="${fill}"/>`;
    return `<svg class="lg-seam" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" aria-hidden="true">${body}<rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="3" fill="none" stroke="${line}"/></svg>`;
  };
  Timeline.tabRank = tabRank;
  /* (공개 — 검사용) 승계선의 모양과 이음매: 종류 표 · 줄 만들기 · 네모 비키기 · 다리 · 관문 (scripts/dev-smoke.mjs ㉝가 노드에서 기하를 확인) */
  Object.assign(Timeline, { SUCC_KINDS, succKind, chainRows, seamPush, seamBridge, gatePiece, beatRuns, thinOf, SQ_CLEAR, G, litShift, nameSnap });
  /* (공개 — 검사용) 조감: 값 묶음 · 모양 셋 · 자동 조감의 문턱 · 띠 안 이름 · 짧은 끝 · 세로 이름 줄이기 (scripts/dev-smoke.mjs ㉞가 노드에서 배치 · 이름 · 점 · 승계선을 확인) */
  Object.assign(Timeline, { BIRD, G_BIRD, BIRD_AUTO, BIRD_NAME, STUB, shortNames });
  /** (범례 — viewer.js) 맞닿은 승계의 견본: 두 띠 끝 · 비켜 앉은 네모 · 문 · 다리를 화면과 같은 도우미(seamBridge)로 — 폭 34 · 높이 15 */
  Timeline.seamSample = (type, cq = '#bba395', cp = '#a0bcc5') => {
    const kind = succKind(type);
    const W = 34;
    const H = 15;
    const y = H / 2;
    const seam = W / 2;
    const m = G.bw + 2 + G.sq / 2 + seamPush(0, kind !== SUCC_KINDS.direct);
    const hs = G.sq / 2;
    const br = seamBridge({ qe: seam, pf: seam, xa: seam - m + hs + 1, xb: seam + m - hs - 1, y, kind });
    const f = v => Number(v).toFixed(2);
    const doors = br.doors.map(d => `<rect class="tl-door${d.seam ? ' is-seam' : ''}" x="${f(d.x)}" y="${f(d.y)}" width="${f(d.w)}" height="${f(d.h)}" rx="1" style="--da:${cq};--ka:24%;--db:${cp};--kb:24%"/>`).join('');
    const segs = br.segs.map(s => `<path class="tl-seg" d="M${f(s.x1)} ${f(s.y1)} L${f(s.x2)} ${f(s.y2)}" style="--c:${s.side === 'q' ? cq : cp}${s.w ? `;stroke-width:${s.w}px;opacity:${(PARTIAL / 0.9).toFixed(2)}` : ''}"/>`).join(''); // 가는 선(부분 승계)은 연표처럼 옅게 — 묶음 .9 안에서 PARTIAL까지
    const ring = br.ring ? `<circle class="tl-seg is-ring" cx="${f(br.ring.x)}" cy="${f(br.ring.y)}" r="2.75" style="--c:${cq}"/>` : '';
    return `<svg class="lg-seam" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" aria-hidden="true"><rect class="b" x="-12" y="0.5" width="${f(seam + 11.5)}" height="${H - 1}" rx="4" style="--c:${cq}"/><rect class="b" x="${f(seam + 0.5)}" y="0.5" width="${f(W - seam + 11.5)}" height="${H - 1}" rx="4" style="--c:${cp}"/>${doors}<g class="s">${segs}${ring}</g><rect class="tl-sq is-fall" x="${f(seam - m - hs)}" y="${f(y - hs)}" width="${G.sq}" height="${G.sq}" rx="2" style="--c:${cq}"/><rect class="tl-sq is-found" x="${f(seam + m - hs)}" y="${f(y - hs)}" width="${G.sq}" height="${G.sq}" rx="2" style="--c:${cp}"/></svg>`;
  };
  /** (범례 — viewer.js) 부분 승계의 가는 선 견본: 폭 w의 가는 실선 하나 — 연표와 같은 굵기(보통 밀도의 가는 선 값) · 같은 짙기(PARTIAL) */
  Timeline.thinSample = (c = '#bba395', w = 22) => {
    const H = 9;
    return `<svg class="lg-thin" width="${w}" height="${H}" viewBox="0 0 ${w} ${H}" aria-hidden="true"><path d="M0 ${crispAt(H / 2, THIN)} H${w}" fill="none" stroke="${c}" stroke-width="${THIN.w}" stroke-opacity="${PARTIAL}"/></svg>`;
  };
  /** (범례 — viewer.js) 합류 견본: 위에서 곧게 내려온 선이 후대 띠의 위 테두리에 닿고, 닿는 자리에 선대 색의 합류 조각 (joinPiece — 연표와 같은 도우미) */
  Timeline.joinSample = (cq = '#bba395', cp = '#a0bcc5') => {
    const W = 34;
    const H = 15;
    const yb = 9; // 후대 띠의 위 테두리(바깥 변)
    const x = 17;
    const f = v => Number(v).toFixed(2);
    const j = joinPiece({ x, edgeY: yb, dir: 1 });
    return `<svg class="lg-seam" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" aria-hidden="true"><rect class="b" x="-12" y="${f(yb + 0.5)}" width="${W + 24}" height="${f(H - yb - 1)}" rx="4" style="--c:${cp}"/><path class="tl-link is-direct" d="M${x} 0 V${f(yb)}" stroke="${cq}" style="opacity:.5"/><rect class="tl-seg is-join" x="${f(j.x)}" y="${f(j.y)}" width="${f(j.w)}" height="${f(j.h)}" rx="${f(j.h / 2)}" style="--c:${cq}"/></svg>`;
  };
  Object.assign(Timeline, { joinPiece, THIN, PARTIAL });
  /* (공개 — 검사용) 칸의 이설 · 모호한 칸의 자리를 정하는 순수 함수들: 화면과 그림 내보내기가 같은 것을 부릅니다 (scripts/dev-smoke.mjs ㊳) */
  Timeline.altEdges = altEdges;
  Timeline.altMarks = altMarks;
  Timeline.altRowPlan = altRowPlan;
  Timeline.dynCellOf = dynCellOf;
  HT.Timeline = Timeline;
})();

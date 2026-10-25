/* 조각 ④ 결정 판 — 공통 도움(s4-0-common) · by Fable(2026-10-15)
   갈래 E(t-e.js — 머리 24 · 흰 층 16 · 구멍 · 꼬리 마름모)를 바탕으로 집권 · 실권 · 지도자 흰 층을 여러 단 쌓고,
   손잡이(머리 줄 단추 `▸ 단체 n` / 흰 꼬리표 `⌄ n`) · 띠 밑 집권 사슬(d7-c) · 펼친 단체 줄 · 옮겨 앉기 실(d3-a) · 풀린 그릇 열쇠표를 그린다.
   공통 파일(t-common.js의 window.TAG · render.js의 BASE)은 고치지 않고 그리는 때에만 찾아 쓴다.
   갈래 파일(s4-<갈림>-<갈래>.js)은 window.S4.register({ id, code, name, idea, pro, con, rec, opt })로 등록한다.
   장면(1180 ~ 1700년): 한국 — 고려(실권 층) · 최씨 정권(제 띠 + 받침 카드) · 조선(여섯 붕당) / 중국 — 명(집권 없는 단체 둘) / 라틴 유럽 — 보헤미아 왕국의 옮겨 앉기(1526). */
const { E, TW, base, px, mix, mixOk, fit, INK } = K;
const P = K.P;
const TAG = () => window.TAG;
const HEAD = 24, LINE = 21, FLOOR = 16;
const M = { top: 124, clipTop: 118, tabH: 15, tabH0: 5, tabHS: 20, bandH: 24, cellsH: 40, gap: 3, trackGap: 4, cultureGap: 9, laneH: 14, laneGap: 3 };

/* ══ 자료 ══ */
const GORYEO = [['의종', 1146, 1170], ['명종', 1170, 1197], ['신종', 1197, 1204], ['희종', 1204, 1211], ['강종', 1211, 1213], ['고종', 1213, 1259], ['원종', 1259, 1274], ['충렬왕', 1274, 1308], ['충선왕', 1308, 1313], ['충숙왕', 1313, 1339], ['충혜왕', 1339, 1344], ['충목왕', 1344, 1348], ['충정왕', 1348, 1351], ['공민왕', 1351, 1374], ['우왕', 1374, 1388], ['창왕', 1388, 1389], ['공양왕', 1389, 1392]];
const JOSEON = [['태조', 1392, 1398], ['정종', 1398, 1400], ['태종', 1400, 1418], ['세종', 1418, 1450], ['문종', 1450, 1452], ['단종', 1452, 1455], ['세조', 1455, 1468], ['예종', 1468, 1469], ['성종', 1469, 1494], ['연산군', 1494, 1506], ['중종', 1506, 1544], ['인종', 1544, 1545], ['명종', 1545, 1567], ['선조', 1567, 1608], ['광해군', 1608, 1623], ['인조', 1623, 1649], ['효종', 1649, 1659], ['현종', 1659, 1674], ['숙종', 1674, 1720]];
const CHOE = [['최충헌', 1196, 1219], ['최우', 1219, 1249], ['최항', 1249, 1257], ['최의', 1257, 1258]];
const MING = [['홍무제', 1368, 1398], ['건문제', 1398, 1402], ['영락제', 1402, 1424], ['홍희제', 1424, 1425], ['선덕제', 1425, 1435], ['정통제', 1435, 1449], ['경태제', 1449, 1457], ['천순제', 1457, 1464], ['성화제', 1464, 1487], ['홍치제', 1487, 1505], ['정덕제', 1505, 1521], ['가정제', 1521, 1567], ['융경제', 1567, 1572], ['만력제', 1572, 1620], ['천계제', 1620, 1627], ['숭정제', 1627, 1644]];
const BOH1 = [['오타카르 1세', 1198, 1230], ['바츨라프 1세', 1230, 1253], ['오타카르 2세', 1253, 1278], ['바츨라프 2세', 1278, 1305], ['얀', 1310, 1346], ['카렐 4세', 1346, 1378], ['바츨라프 4세', 1378, 1419], ['지기스문트', 1419, 1437], ['라디슬라우스', 1453, 1457], ['이르지', 1458, 1471], ['블라디슬라프', 1471, 1516], ['루드비크', 1516, 1526]];
const BOH2 = [['페르디난트 1세', 1526, 1564], ['막시밀리안', 1564, 1576], ['루돌프 2세', 1576, 1611], ['마티아스', 1611, 1619], ['페르디난트 2세', 1619, 1637], ['페르디난트 3세', 1637, 1657], ['레오폴트 1세', 1657, 1705]];
/* 조선의 집권 사슬 [이름, 시작, 끝, 색] */
const RULE = [['훈구', 1455, 1567, P.slate], ['사림', 1567, 1575, P.sand], ['동인', 1575, 1591, P.mint], ['남인', 1591, 1599, P.sage], ['북인', 1599, 1623, P.lav], ['서인', 1623, 1674, P.peach]];

const DETAIL = {
  seoin: { path: ['동아시아', '한국', '조선'], title: '서인', when: '1575 ~ 1683년', kind: '단체', group: '영토가 본업이 아닌 것',
    text: '사림이 동서로 갈릴 때 심의겸 쪽에 선 붕당. 1623년 인조반정으로 정권을 잡았고, 1683년 노론과 소론으로 갈라졌다.',
    facts: [['그릇', '조선'], ['갈래', '붕당'], ['집권', '1623 ~ 1674']],
    offices: [{ n: '영수', count: 3, rows: [['심의겸', '1575 ~'], ['정철', '1589 ~'], ['김류', '1623 ~']] }],
    links: [['앞', '사림', '갈라짐'], ['뒤', '노론 · 소론', '갈라짐']] },
  choe: { path: ['동아시아', '한국'], title: '최씨 정권', when: '1196 ~ 1258년', kind: '실권 정권', group: '다스리는 것',
    text: '최충헌이 이의민을 몰아내고 세운 무신 정권. 고려 왕을 받들되 나라의 실권을 쥐었고 4대 62년을 이었다.',
    facts: [['명목 군주', '고려'], ['그릇', '고려'], ['도읍', '개경']],
    offices: [{ n: '집정', count: 4, rows: [['최충헌', '1196 ~ 1219'], ['최우', '1219 ~ 1249'], ['최항', '1249 ~ 1257'], ['최의', '1257 ~ 1258']] }],
    links: [['앞', '이의민 정권', '직접'], ['뒤', '김준 정권', '직접']] },
  boh: { path: ['라틴 유럽', '합스부르크 군주국'], title: '보헤미아 왕국', when: '1198 ~ 1918년', kind: '제후국', group: '다스리는 것',
    text: '프라하를 도읍으로 한 체코 땅의 왕국. 1526년 합스부르크가의 페르디난트 1세가 왕위를 이어 합스부르크 군주국으로 옮겨 앉았다.',
    facts: [['그릇', '합스부르크 군주국'], ['도읍', '프라하']],
    offices: [{ n: '그릇', count: 2, rows: [['신성 로마', '1198 ~ 1526'], ['합스부르크 군주국', '1526 ~ 1918']] }],
    links: [['앞', '보헤미아 공국', '직접']] },
};

/* ══ 장면 ══ opt: { chain: 'floor' | 'lane', handle: 'btn' | 'tag' | null, open, real, move: 'A' | 'B' | null, detail } */
function scene(S, opt) {
  const GR = window.SCENE_GROUP;
  const O = (n, a, b, c, t, more = {}) => ({ n, a, b, c, t, g: GR[t], ...more });
  const V = (n, y, imp) => ({ n, y, imp: !!imp });
  S.win = { y0: 1180, y1: 1700 }; S.title = '1180 ~ 1700년';
  S.labels = [{ n: '몽골 제국 시대', a: 1206, b: 1368 }, { n: '르네상스', a: 1400, b: 1600 }, { n: '대항해 시대', a: 1450, b: 1650 }];
  const goryeo = O('고려', 918, 1392, P.rose, '국가', { cells: GORYEO, ev: [V('몽골 침입', 1231), V('위화도 회군', 1388, 1)] });
  if (opt.real) goryeo.real = [{ n: '최씨 정권', a: 1196, b: 1258, c: P.butter }];
  const joseon = O('조선', 1392, 1897, P.sky, '국가', { from: 'direct', cells: JOSEON, ev: [V('훈민정음', 1446, 1), V('임진왜란', 1592, 1), V('인조반정', 1623)], groups: 6, open: !!opt.open });
  const row1 = { label: '고려 · 조선', items: [goryeo, joseon] };
  if (opt.chain === 'floor') joseon.power = RULE.map(([n, a, b, c]) => ({ n, a, b, c }));
  else row1.lane = { grp: true, chains: [{ at: 1455, count: 6, items: RULE, open: !!opt.open }] };
  const choe = O('최씨 정권', 1196, 1258, P.butter, '실권 정권', { serve: { to: '고려', c: P.rose, rel: '명목상', a: 1196 }, cells: CHOE });
  const kr = [row1];
  if (opt.open) kr.push(
    { grp: true, items: [O('훈구', 1453, 1567, P.slate, '단체'), O('동인', 1575, 1591, P.mint, '단체', { cross: { from: '사림', how: 'direct' } }), O('북인', 1591, 1623, P.lav, '단체', { from: 'direct' })] },
    { grp: true, items: [O('사림', 1470, 1575, P.sand, '단체'), O('서인', 1575, 1683, P.peach, '단체', { from: 'direct' })] },
    { grp: true, items: [O('남인', 1591, 1800, P.sage, '단체', { cross: { from: '동인', how: 'direct' } })] });
  kr.push({ label: '최씨 정권', items: [choe] });
  const ming = O('명', 1368, 1644, P.peach, '국가', { cells: MING, ev: [V('정화의 원정', 1405, 1), V('토목의 변', 1449)], groups: 2, groupNames: [['동림당', P.mint], ['엄당', P.lav]] });
  const cnRow = { label: '명', items: [ming] };
  if (opt.chain === 'lane') cnRow.lane = { grp: true, chains: [{ at: 1604, count: 2, items: [] }] };
  S.cultures = [{ n: '동아시아', tracks: [
    { n: '한국', leaders: true, lines: 2, rows: kr },
    { n: '중국', leaders: true, lines: 2, rows: [cnRow] },
  ] }];
  if (opt.move) {
    const b1 = O('보헤미아 왕국', 1198, 1526, P.peri, '제후국', { mv: 'boh', keys: [{ n: '신성 로마', a: 1198 }], cells: BOH1 });
    const b2 = O('보헤미아 왕국', 1526, 1918, P.peri, '제후국', { mv: 'boh', keys: [{ n: '합스부르크 군주국', a: 1526 }], cells: BOH2 });
    const aut = O('오스트리아', 1156, 1918, P.sage, '제후국', { keys: [{ n: '신성 로마', a: 1156 }] });
    const hun = O('헝가리 왕국', 1000, 1918, P.butter, '국가', { keys: [{ n: '합스부르크 군주국', a: 1526 }] });
    const rows = opt.move === 'A' ? [[b1], [b2], [aut], [hun]] : [[b1, b2], [aut], [hun]];
    S.cultures.push({ n: '라틴 유럽', tracks: [{ n: '라틴 유럽', leaders: true, lines: 2, rows: rows.map(items => ({ key: true, items })) }] });
  }
  S.detail = DETAIL[opt.detail || 'seoin'];
  /* 흰 층 차례(계약 3절: 집권 → 실권 → 지도자) · 꼬리 마름모 자리(뒤로 이어지는 객체) */
  for (const C of S.cultures) for (const Tr of C.tracks) for (const r of Tr.rows) r.items.forEach((o, i) => {
    o.floors = [];
    if (o.power) o.floors.push({ kind: 'power', cells: o.power });
    if (o.real) o.floors.push({ kind: 'real', cells: o.real });
    if (o.cells) o.floors.push({ kind: 'leader', cells: o.cells.map(([n, a, b]) => ({ n, a, b })) });
    if (o.from && i) r.items[i - 1].out = true;
  });
  const all = S.cultures.flatMap(C => C.tracks.flatMap(Tr => Tr.rows.flatMap(r => r.items)));
  for (const o of all) if (o.cross) { const a = all.find(q => q.n === o.cross.from); if (a) a.out = true; }
  return S;
}

/* ══ 줄 쌓기 — 갈래 E(t-common layoutSeogo)와 같되 흰 층을 객체마다 세고(줄 = 가장 많은 것), 사슬 줄(lane)과 단체 줄(grp · 왼쪽 칸 한 칸 들임)을 더함 ══ */
function layout(S, L, M) {
  let y = M.top, ri = 0, ti = 0, ci = 0;
  const rec = { rows: [], tracks: [] };
  for (const cu of S.cultures) {
    const C = L.cultures[ci++]; C.y0 = y;
    for (const tr of cu.tracks) {
      const Tr = L.tracks[ti++]; Tr.y0 = y;
      for (const r of tr.rows) {
        const row = L.rows[ri++];
        const top = r.items.some(o => o.serve) ? M.tabHS : r.key ? M.tabH : M.tabH0;
        const lines = tr.lines || 1, head = HEAD + (lines - 1) * LINE;
        const nf = Math.max(0, ...r.items.map(o => (o.floors || []).length));
        row.y = y; row.yBand = y + top; row.h = head + nf * FLOOR;
        row.spec = { seogo: true, lines, head, floors: nf, chain: 0 };
        if (r.grp) row.depth = 1;
        y += top + row.h;
        if (row.lane) { row.laneY = y + M.laneGap; y += M.laneGap + M.laneH; }
        rec.rows.push({ label: r.label || r.items.map(o => o.n).join(' · '), track: tr.n, y: row.y, yBand: row.yBand, h: row.h, bottom: y, grp: !!r.grp });
        y += M.gap;
      }
      Tr.y1 = y - M.gap; y += M.trackGap;
      rec.tracks.push({ n: tr.n, y0: Tr.y0, y1: Tr.y1 });
    }
    C.y1 = y - M.trackGap; y += M.cultureGap;
  }
  L.bottom = y;
  return rec;
}

/* ══ 작은 재료 ══ */
/** 선 아이콘 꺾쇠(Lucide chevron 규격 — 24칸 · 굵기 1.5)를 up · down으로 */
function chev(g, dir, x, y, size, color) {
  const s = size / 24, pts = dir === 'up' ? [[6, 15], [12, 9], [18, 15]] : [[6, 9], [12, 15], [18, 9]];
  E('path', { d: pts.map(([a, b], i) => `${i ? 'L' : 'M'}${x + a * s},${y + b * s}`).join(' '), fill: 'none', stroke: color, 'stroke-width': 1.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, g);
}
/** (ㄱ) 머리 줄 단추 — 지금 앱 `▸ 속국 n`과 한 가족(scopes.dart ScopeMarks: 높이 16 · 좌우 6 · 모서리 5 · 글 10 · 종이색 칠 + 띠 테 빛깔 1px) */
function button(th, p, o, text, x, cy) {
  const w = Math.round(th.tw(text, 10, 'ui', 400) + 14), X = px(x), Y = px(cy - 8);
  E('path', { d: K.rr(X, Y, w, 16, 5), fill: th.tok.paper, stroke: th.edgeOf(o.c) }, p.band);
  th.t(p.band, X + 7, base(cy, 10), text, 'ui', { size: 10, wt: 400, fill: mix(o.c, .30, INK) });
  return { x0: X, x1: X + w };
}
/** (ㄴ) 흰 꼬리표 손잡이 — 목업 d7-c(모따기 3 · 선 아이콘 ⌄ 10 · 수 8.5 400 먹 60) · x0 = 왼쪽(.5 맞춤) · y = 윗변(.5 맞춤) */
function whiteTag(th, p, cnt, x0, y, h, open) {
  const k = a => th.k(a), w = Math.round(4 + 10 + 3 + TW(cnt, 8.5, 400) + 5);
  E('path', { d: TAG().outline(x0, y, x0 + w, h, 'cham', false, { c: 3 }), fill: th.tok.paper, stroke: k(.4) }, p.band);
  chev(p.band, open ? 'up' : 'down', x0 + 4, y + (h - 10) / 2, 10, k(.6));
  th.t(p.band, x0 + 17, base(y + h / 2, 8.5), cnt, 'ui', { size: 8.5, wt: 400, fill: k(.6) });
  return { x0, x1: x0 + w };
}
/** (감독 2026-10-15 안) 포스트잇 플래그 — 꼬리표 윗변에 살짝 얹힌 빗금 꼬리(접은 기능이 있다는 표시 · 글 없음).
 *  누르면 같은 플래그가 위로 늘어나 창이 된다: 머리(이름 + 수 + 펼침 선 아이콘) 아래에 접힌 것의 목록(색 점 + 이름).
 *  x = 플래그 왼쪽 · top = 꼬리표 윗변 · items = [[이름, 색]] · open = 창 */
const FLAG = { w: 14, h: 7, hatch: 3 };
function flag(th, p, o, x, top, items, open, title) {
  const k = a => th.k(a), edge = th.edgeOf(o.c), X = px(x), T = px(top);
  const fillC = mixOk(o.c, .5, th.tok.paper);
  const layer = open ? p.over : p.band;
  if (!open) {
    E('path', { d: `M${X},${T} V${T - FLAG.h} H${X + FLAG.w} V${T}`, fill: fillC, stroke: edge }, layer);
    for (let i = 1; i <= FLAG.hatch; i++) {
      const a = X + i * 4 - 2;
      E('line', { x1: a, y1: T - .5, x2: a + 4, y2: T - FLAG.h + .5, stroke: edge, 'stroke-opacity': .55 }, layer);
    }
    return { x0: X, x1: X + FLAG.w };
  }
  /* 창: 폭은 머리 글에 맞춤 · 줄 16 · 아래는 꼬리표 윗변에 붙음(플래그가 늘어난 꼴 — 아랫단에 빗금 띠 7) */
  const head = `${title} ${items.length}`, rowH = 16, pad = 7;
  const w = Math.round(Math.max(th.tw(head, 10, 'ui', 700) + 30, ...items.map(([n]) => th.tw(n, 9.5, 'body', 400) + 26)) + pad);
  const h = 20 + items.length * rowH + 4 + FLAG.h;
  const Y0 = T - h;
  E('path', { d: `M${X},${T} V${Y0} H${X + w} V${T}`, fill: th.tok.paper, stroke: edge }, layer);
  // 아랫단 = 닫힌 플래그의 빗금 꼬리 그대로(어디서 나온 창인지)
  E('rect', { x: X + .5, y: T - FLAG.h, width: w - 1, height: FLAG.h - .5, fill: fillC }, layer);
  for (let a = X + 2; a < X + w - 4; a += 4) E('line', { x1: a, y1: T - .5, x2: a + 4, y2: T - FLAG.h + .5, stroke: edge, 'stroke-opacity': .55 }, layer);
  E('line', { x1: X, x2: X + w, y1: T - FLAG.h + .5, y2: T - FLAG.h + .5, stroke: edge }, layer);
  // 머리: 이름 + 수 · 오른쪽 끝에 '제 줄로 펼침' 선 아이콘(테 안의 줄)
  th.t(layer, X + pad, base(Y0 + 10.5, 10), title, 'ui', { size: 10, wt: 700, fill: k(.85) });
  th.t(layer, X + pad + th.tw(title, 10, 'ui', 700) + 4, base(Y0 + 10.5, 10), String(items.length), 'ui', { size: 10, wt: 400, fill: k(.5) });
  const ix = X + w - 16, iy = Y0 + 5;
  E('rect', { x: ix + .5, y: iy + .5, width: 10, height: 10, rx: 1.5, fill: 'none', stroke: k(.6) }, layer);
  E('line', { x1: ix + 3, x2: ix + 8, y1: iy + 4.5, y2: iy + 4.5, stroke: k(.6) }, layer);
  E('line', { x1: ix + 3, x2: ix + 6, y1: iy + 7.5, y2: iy + 7.5, stroke: k(.6) }, layer);
  E('line', { x1: X + 4, x2: X + w - 4, y1: Y0 + 20.5, y2: Y0 + 20.5, stroke: k(.12) }, layer);
  items.forEach(([n, c], i) => {
    const cy = Y0 + 20 + 2 + i * rowH + rowH / 2;
    E('circle', { cx: X + pad + 3, cy, r: 3, fill: th.fillOf(c), stroke: th.edgeOf(c) }, layer);
    th.t(layer, X + pad + 11, base(cy, 9.5), n, 'body', { size: 9.5, wt: 400, fill: k(.8) });
  });
  return { x0: X, x1: X + w };
}

/** 풀린 그릇의 열쇠표(앱 FolderLook: 높이 12 · 띠 윗변 위 2 · 둥근 끝 6 · 구멍 6 · 글 8.5 먹 65 · 띠 시작 + 16에서 45° 실) */
function keys(th, p, o, b) {
  const k = a => th.k(a); let last = -1e9;
  for (const t of o.keys) {
    const xa = Math.max(px(p.X(t.a)), (b.cl ? p.CL : b.X0) + 16), w = Math.round(th.tw(t.n, 8.5, 'name') + 17), h = 12;
    const kx = Math.max(xa + 3, last + 4), ky = b.Y - h - 2;
    E('path', { d: `M${xa},${b.Y} L${kx + 6},${ky + 6}`, stroke: k(.45), fill: 'none' }, p.under);
    E('path', { d: TAG().outline(kx, ky, kx + w, h, 'key', false, { r: 6 }), fill: th.tok.paper, stroke: k(.4) }, p.under);
    E('circle', { cx: kx + 6, cy: ky + 6, r: 1.5, fill: th.tok.paper, stroke: k(.45) }, p.under);
    th.t(p.under, kx + 11, base(ky + 6, 8.5), t.n, 'name', { size: 8.5, fill: k(.65) });
    last = kx + w;
  }
}
/** 흰 층의 윤곽(t-e floor) — 왼쪽 아래 귀만 꼬리표 꼴을 따름 */
function floorD(x0, ys, x1, yb, kind, cl, tagH) {
  const TG = TAG();
  if (cl || kind === 'plain') return `M${x1},${ys} H${x0} V${yb} H${x1} Z`;
  if (kind === 'key') { const r = Math.min(TG.KEYR, tagH / 2, yb - ys); return `M${x1},${ys} H${x0} V${yb - r} A${r},${r} 0 0 0 ${x0 + r},${yb} H${x1} Z`; }
  const c = Math.min(TG.CH, yb - ys); return `M${x1},${ys} H${x0} V${yb - c} L${x0 + c},${yb} H${x1} Z`;
}
/** 명목 지도자 — 제 기간의 절반 이상이 실권 칸과 겹침(core.js groupStrip) */
function nominal(o, c) {
  if (!o.real) return false;
  const len = c.b - c.a; if (len <= 0) return false;
  let ov = 0; for (const r of o.real) ov += Math.max(0, Math.min(c.b, r.b) - Math.max(c.a, r.a));
  return ov * 2 >= len;
}
/** 흰 층 한 단 — leader(t-e 그대로: 세로 금 먹 20 · 글 8.5 400) · power(단체 색 24% 칠 · 글 8.5 700) · real(단체 색 45% 칠 · 금 64% + 먹 · 글 먹빛) */
function paintFloor(th, p, o, b, f, top, kind) {
  const k = a => th.k(a), yb = top + FLOOR, lo = b.X0 + (b.cl ? 2 : 6), hi = b.X1 - 2;
  let lastX = -1;
  const divider = (xx, col) => { const q = Math.round(xx) + .5; if (Math.abs(q - lastX) < 2.5 || q < b.X0 + 3 || q > b.X1 - 3) return; E('line', { x1: q, x2: q, y1: top + 1, y2: yb - 1, stroke: col }, p.band); lastX = q; };
  for (const c of f.cells) {
    const xa = Math.max(p.X(c.a), lo, p.CL - 1), xe = Math.min(p.X(c.b), hi);
    if (xe - xa < 1) continue;
    if (f.kind === 'leader') {
      for (const xx of [xa, xe]) divider(xx, k(.2));
      if (th.tw(c.n, 8.5, 'body', 400) <= xe - xa - 6) th.t(p.band, xa + 3, base(top + FLOOR / 2, 8.5), c.n, 'body', { size: 8.5, wt: 400, fill: K.nameInk(o.c), op: nominal(o, c) ? .5 : null });
      continue;
    }
    const real = f.kind === 'real', l = Math.round(xa), r = Math.round(xe);
    E('rect', { x: l, y: top + .5, width: r - l, height: FLOOR - 1, fill: real ? mix(c.c, .45, th.tok.paper) : th.fillOf(c.c) }, p.band);
    for (const xx of [xa, xe]) divider(xx, real ? mixOk(c.c, .64, INK) : k(.2));
    const s = fit(c.n, xe - xa - 6, 8.5, 700);
    if (s) th.t(p.band, xa + 3, base(top + FLOOR / 2, 8.5), s, 'name', { size: 8.5, fill: real ? mix(c.c, .10, INK) : K.tabInk(c.c) });
  }
}

/* ══ 객체 = 갈래 E 꼬리표 + 흰 층 여러 단 + 손잡이 ══ */
function object(th, S, p, o, g, opt) {
  const TG = TAG(), b = TG.geom(p, o, g), k = a => th.k(a), sel = !!o.selected, kind = TG.kindOf(o);
  const head = b.sp.head || HEAD, floors = o.floors || [], hh = head - 1, H = hh + floors.length * FLOOR;
  g.tagBottom = b.Y + H;
  const cd = o.serve ? TG.card(th, p, o, g, b, b.Y, H, kind) : null;
  if (o.keys) keys(th, p, o, b);
  const { edge } = TG.paintTag(th, p, o, b, b.X0, b.Y, H, kind, p.band);
  const tops = [];
  if (floors.length) {
    const ys = b.Y + hh, yb = b.Y + H, xr = b.XR;
    E('path', { d: floorD(b.X0, ys, xr, yb, kind, b.cl, H), fill: b.fuzzy ? TG.fade(p, b.X1, b.XR, '#ffffff') : '#ffffff', stroke: 'none' }, p.band);
    const line = b.fuzzy ? TG.fade(p, b.X1, b.XR, edge) : edge;
    floors.forEach((f, i) => {
      const top = ys + i * FLOOR; tops.push(top);
      E('path', { d: `M${b.cl ? b.X0 : b.X0 + .5},${top} H${xr}`, stroke: line }, p.band);
      paintFloor(th, p, o, b, f, top, kind);
    });
    if (kind !== 'plain') E('path', { d: TG.outline(b.X0, b.Y, b.XR, H, kind, b.cl, { open: b.fuzzy }), fill: 'none', stroke: b.fuzzy ? TG.fade(p, b.X1, b.XR, edge) : edge, 'stroke-dasharray': o.rival ? '3 2' : null }, p.band);
  }
  const tie = g.tie = { xe: b.X1 };
  let nx = p.CL + 6;
  if (!b.cl && !b.short) { tie.hx = TG.holeX(b, kind); tie.hy = b.Y + TG.HOLE; nx = tie.hx + 7; TG.hole(th, p, tie.hx, tie.hy, sel); }
  if (o.out && !b.cr && !b.short) { tie.dx = b.X1 - 7; tie.dy = b.Y + TG.HOLE; }
  const rlim = Math.min(tie.dx != null ? tie.dx - 8 : b.X1 - 6, p.CR - 6);
  const l1 = b.y0 + 12, lines = Array.from({ length: b.lines }, (_, i) => l1 + i * TG.G.line), busy = lines.map(() => []);
  const s = b.short ? '' : fit(o.n, rlim - nx, 9, 700);
  let nameEnd = nx;
  if (s) { th.t(p.band, nx, base(l1, 9), s, 'name', { size: 9, fill: sel ? INK : o.rival ? k(.6) : o.g === '무리' ? K.nameInk(o.c) : K.tabInk(o.c) }); nameEnd = nx + th.tw(s, 9, 'name'); busy[0].push([nx - 4, nameEnd + 4]); }
  if (tie.dx != null) busy[0].push([tie.dx - 6, tie.dx + 6]);
  /* 손잡이 — 단체가 든 나라(o.groups = 접힌 단체 수)에만 */
  if (o.groups && opt.handle) {
    const cnt = String(o.groups);
    if (opt.handle === 'flag') {
      // 플래그 = 구멍(과 매다는 실) 오른쪽 6 · 윗변에 얹힘. 펼친 창은 그 자리에서 위로.
      const fx = (tie.hx ?? b.X0 + 7) + 6;
      const list = o.groupNames || RULE.map(([n, , , c]) => [n, c]);
      flag(th, p, o, fx, b.Y, list, opt.flagOpen === o.n, '단체');
    } else if (opt.handle === 'btn') {
      const hb = button(th, p, o, `${o.open ? '▾' : '▸'} 단체 ${cnt}`, nameEnd + 4, l1);
      if (hb.x1 <= rlim) busy[0].push([hb.x0 - 3, hb.x1 + 3]);
    } else {
      const pi = floors.findIndex(f => f.kind === 'power');
      if (pi >= 0) {
        const first = floors[pi].cells[0], x1 = px(p.X(first.a)) - 3, w = Math.round(4 + 10 + 3 + TW(cnt, 8.5, 400) + 5);
        whiteTag(th, p, cnt, x1 - w, tops[pi] + 2, 12, o.open);   // 집권 층 첫 칸 왼쪽 · 위아래 2 띄움
      } else {
        const hb = whiteTag(th, p, cnt, px(nameEnd + 4), px(l1 - 6), 12, o.open);   // 집권 층이 없으면 머리 줄
        busy[0].push([hb.x0 - 3, hb.x1 + 3]);
      }
    }
  }
  TG.events(th, p, o, b, { lines, busy, size: 9.5, dot: 2.5, gap: 3.5, lo: (b.cl ? p.CL : b.X0) + 14, hi: b.X1 - 9, rlim });
  if (cd) { const tr = Math.min(cd.xr, p.CR) - 8; if (tr - TG.hostW(th, o.serve) > cd.xs + 30) TG.hostTab(th, p, cd, tr, cd.cy); }
  if (sel) E('path', { d: TG.outline(b.X0 - 2, b.Y - 2, b.XR + 2, H + 4, kind, b.cl, { c: 6, r: 14 }), fill: 'none', stroke: INK, 'stroke-width': 1.5 }, p.over);
}

/* ══ ②(나) 띠 밑 집권 사슬 + 손잡이 — 목업 d7-c 그대로(직위 줄 자리 · 띠 아래 틈 3 · 높이 14 · 첫 칸 둥근 끝 + 구멍 + 실) ══ */
function lanes(th, S, p, L) {
  const k = a => th.k(a), tk = th.tok, Mm = th.M, TG = TAG();
  const other = L.lanes.filter(r => !r.lane.grp);
  if (other.length) window.BASE.lanes.call(th, S, p, Object.assign({}, L, { lanes: other }));
  for (const r of L.lanes) {
    const ln = r.lane; if (!ln.grp) continue;
    const y = px(r.laneY), h = Mm.laneH - 1, top = y - Mm.laneGap - 1;
    for (const ch of ln.chains) {
      const xs = px(p.X(ch.at));
      let prev = null;
      ch.items.forEach(([n, a, bb, c], i) => {
        const x0 = prev ?? px(p.X(a)), x1 = Math.round(Math.min(p.X(bb), p.CR + 30)) - .5, kind = i ? 'plain' : 'key';
        E('path', { d: TG.outline(x0, y, x1, h, kind, false, { r: h / 2 }), fill: th.fillOf(c), stroke: th.edgeOf(c) }, p.band);
        let tx = x0 + 4;
        if (!i) {
          const hx = x0 + 5.5, hy = y + h / 2;
          E('path', { d: `M${hx},${hy - 1.5} V${top}`, stroke: k(.45), fill: 'none' }, p.band);
          E('circle', { cx: hx, cy: hy, r: 1.5, fill: tk.paper, stroke: k(.45) }, p.band);
          tx = x0 + 11;
        }
        const s = fit(n, Math.min(x1, p.CR) - tx - 3, 8.5, 700);
        if (s) th.t(p.band, tx, base(y + h / 2, 8.5), s, 'name', { size: 8.5, fill: th.tabInkOf(c) });
        prev = x1;
      });
      const cnt = String(ch.count), w = Math.round(4 + 10 + 3 + TW(cnt, 8.5, 400) + 5);
      const x1 = ch.items.length ? xs - 3 : xs + w;
      whiteTag(th, p, cnt, x1 - w, y, h, ch.open);
    }
  }
}

/* ══ 실 — 줄 건너는 승계(갈라짐 · 세로 통로는 띠 뒤 · 구멍으로 드는 토막만 띠 위) · ⑤ 옮겨 앉기 ══ */
function cross(th, p, L) {
  const all = L.rows.flatMap(r => r.items), k = a => th.k(a);
  for (const o of all) {
    if (!o.cross || !o.geo || !o.geo.tie || o.geo.tie.hx == null) continue;
    const a = all.find(q => q.n === o.cross.from && q.geo);
    if (!a || !a.geo.tie || a.geo.tie.dx == null) continue;
    const ab = a.geo.bb, nx = ab.next && ab.next.geo ? ab.next.geo.bb : null;
    const xv = nx && nx.X0 - ab.X1 < 12 ? (ab.X1 + nx.X0) / 2 : ab.X1 + 8;
    const { dx, dy } = a.geo.tie, { hx, hy } = o.geo.tie;
    const r = Math.min(6, Math.abs(hy - dy) / 2, Math.max(0, hx - 2.5 - xv)), up = hy < dy ? -1 : 1;
    const st = { stroke: k(.5), 'stroke-width': 1.5, fill: 'none', 'stroke-linejoin': 'round', 'stroke-dasharray': o.cross.how === 'indirect' ? '3 2' : null };
    // 마름모 → 통로로 굽는 토막과 구멍으로 드는 토막은 띠 위 · 세로 통로만 띠 뒤(다른 꼬리표 뒤로 지남)
    E('path', { d: `M${dx},${dy} H${xv - r} Q${xv},${dy} ${xv},${dy + up * r}`, ...st }, p.over);
    E('path', { d: `M${xv},${dy + up * r} V${hy - up * r}`, ...st }, p.links);
    E('path', { d: `M${xv},${hy - up * r} Q${xv},${hy} ${xv + r},${hy} H${hx - 2.5}`, ...st }, p.over);
    TAG().diamond(p, dx, dy, a.c);
  }
}
/** ⑤ 옮겨 앉기 — 같은 mv의 토막 둘. 다른 줄(A): d3-a 규칙(앞 토막 아랫변의 매듭 → 옮긴 해 왼쪽 6으로 곧게 → 반지름 6 사분원 → 뒤 토막 구멍 · 점선은 띠 뒤 · 구멍 토막은 띠 위).
 *  같은 줄(B): 이음매 가운데 · 구멍 높이에 매듭 + 구멍으로 드는 짧은 실만 */
function moves(th, p, L) {
  const k = a => th.k(a), m = {};
  for (const r of L.rows) for (const o of r.items) if (o.mv && o.geo && o.geo.tie) (m[o.mv] || (m[o.mv] = [])).push(o);
  for (const id in m) {
    const a = m[id].sort((x, y) => x.a - y.a);
    for (let i = 1; i < a.length; i++) {
      const A = a[i - 1].geo, B = a[i].geo, ba = A.bb, bb = B.bb, hx = B.tie.hx, hy = B.tie.hy;
      if (hx == null) continue;
      if (A.row === B.row) {
        const cx = (ba.X1 + bb.X0) / 2;
        E('path', { d: `M${cx},${hy} H${hx - 3}`, stroke: k(.5), 'stroke-width': 1.5, fill: 'none' }, p.over);
        E('circle', { cx, cy: hy, r: 2, fill: k(.5) }, p.over);
        continue;
      }
      const R = 6, down = hy > A.tie.hy, vx = Math.round(Math.min(ba.X1, bb.X0) - 6) + .5;
      const y0 = down ? A.tagBottom : ba.Y, y1 = hy, ex = hx - 3;
      const st = { fill: 'none', stroke: k(.5), 'stroke-width': 1.5, 'stroke-dasharray': '3 2' };
      E('path', { d: `M${vx},${y0} V${y1 + (down ? -R : R)} Q${vx},${y1} ${vx + R},${y1} H${bb.X0}`, ...st }, p.links);
      E('path', { d: `M${bb.X0},${y1} H${ex}`, ...st, 'stroke-dasharray': null }, p.over);
      E('circle', { cx: vx, cy: y0, r: 2, fill: k(.5) }, p.over);
    }
  }
}

/* ══ 등록 ══ */
function register(def) {
  const opt = def.opt || {};
  window.THEMES.push({
    id: def.id, code: def.code, name: def.name, keepB: false, by: 'Fable', rec: !!def.rec,
    idea: def.idea || '', pro: def.pro || '', con: def.con || '',
    M: Object.assign({}, M, def.M || {}),
    opt,
    scene(S) { return scene(S, opt); },
    frame(S, p, L) { const rec = layout(S, L, this.M); (window.S4_REC || (window.S4_REC = {}))[this.id] = rec; window.BASE.frame.call(this, S, p, L); },
    object(S, p, o, g) { object(this, S, p, o, g, opt); },
    link(S, p, a, b, how) { TAG().tieLink(this, p, a, b, how); },
    lanes(S, p, L) { lanes(this, S, p, L); },
    extra(S, p, L) { cross(this, p, L); moves(this, p, L); },
  });
}
window.S4 = { register, scene, layout, object, lanes, cross, moves, M, RULE };

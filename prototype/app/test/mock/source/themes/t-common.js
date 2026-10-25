/* 꼬리표 — 실제 띠에 입히기 · 공통 도움(t-common) — by 메인
   새 앱의 띠 짜임(layout.dart _bandOf · bands.dart _paintBand/_paintTab/paintHostSheets · strips.dart · links.dart)을 흉내 내는
   줄 쌓기 · 단 · 글줄 · 네모 · 승계선과, 서고의 꼬리표 · 구멍 · 꼬리 마름모(blend.js · h-c.js)를 갈래 파일(t-0 · t-a · t-b · t-c · t-d)이 함께 씀.
   이 파일은 이름 차례로 갈래 파일보다 뒤에 읽힘 → 갈래 파일은 그리는 때에만 window.TAG를 찾음(불러올 때 쓰지 않음).
   마지막에 판 목록을 갈래 차례(t-0 · t-a · t-b · t-c · t-d)로 맞춤. */
const { INK, E, T, TW, base, px, rr, mix, mixOk, tabPath } = K;
const P = K.P;
/* 새 앱의 G(layout.dart:19-31) — 탭 줄 18 · 줄 사이 8 · 트랙 아래 9 · 띠 안 위아래 4 · 지도자 칸 22 + 3 · 글줄 21 · 미정 꼬리 44 */
const G = { tab: 18, gap: 8, pad: 9, inset: 4, leader: 22, slot: 3, line: 21, fade: 44 };
const PEEK = 6, KEYR = 12, CH = 5, HOLE = 6, DIA = 3;

/* ══ 장면 — 1330 ~ 1520년 · 동아시아 한 문화권 · 트랙 넷(모두 지도자 칸 + 사건 글줄 둘 — 앱은 트랙의 줄이 여섯 이하면 글줄 둘) ══ */
function scene(S) {
  const GR = window.SCENE_GROUP;
  const O = (n, a, b, c, t, more = {}) => ({ n, a, b, c, t, g: GR[t], ...more });
  const V = (n, y, imp) => ({ n, y, imp: !!imp });
  S.win = { y0: 1330, y1: 1520 };
  S.title = '1330 ~ 1520년';
  S.labels = [{ n: '남북조 시대', a: 1336, b: 1392 }, { n: '전국 시대', a: 1467, b: 1590 }];
  S.cultures = [{ n: '동아시아', tracks: [
    { n: '한국', leaders: true, lines: 2, rows: [
      { label: '고려 · 조선', items: [
        O('고려', 918, 1392, P.rose, '국가', { cells: [['충숙왕', 1332, 1339], ['충혜왕', 1339, 1344], ['충목왕', 1344, 1348], ['충정왕', 1348, 1351], ['공민왕', 1351, 1374], ['우왕', 1374, 1388], ['창왕', 1388, 1389], ['공양왕', 1389, 1392]],
          ev: [V('홍건적 침입', 1359), V('위화도 회군', 1388, 1)] }),
        O('조선', 1392, 1897, P.sky, '국가', { from: 'direct', selected: true,
          cells: [['태조', 1392, 1398], ['정종', 1398, 1400], ['태종', 1400, 1418], ['세종', 1418, 1450], ['문종', 1450, 1452], ['단종', 1452, 1455], ['세조', 1455, 1468], ['예종', 1468, 1469], ['성종', 1469, 1494], ['연산군', 1494, 1506], ['중종', 1506, 1544]],
          ev: [V('한양 천도', 1394), V('왕자의 난', 1398), V('대마도 정벌', 1419), V('훈민정음', 1446, 1), V('계유정난', 1453), V('경국대전', 1485), V('무오사화', 1498), V('중종반정', 1506)] }),
      ] },
      { label: '탐라 · 대금', items: [O('탐라', 1105, 1404, P.mint, '국가'), O('대금', 1453.6, 1454.1, P.mocha, '국가')] },
    ] },
    { n: '중국', leaders: true, lines: 2, rows: [
      { label: '원 · 명', items: [
        O('원', 1271, 1368, P.peri, '국가', { serve: { to: '몽골 제국', c: P.sand, rel: '명목상', a: 1271 }, cells: [['문종', 1329, 1332], ['혜종', 1333, 1368]], ev: [V('홍건적의 난', 1351)] }),
        O('명', 1368, 1644, P.peach, '국가', { from: 'direct',
          cells: [['홍무제', 1368, 1398], ['건문제', 1398, 1402], ['영락제', 1402, 1424], ['홍희제', 1424, 1425], ['선덕제', 1425, 1435], ['정통제', 1435, 1449], ['경태제', 1449, 1457], ['천순제', 1457, 1464], ['성화제', 1464, 1487], ['홍치제', 1487, 1505], ['정덕제', 1505, 1521]],
          ev: [V('정난의 변', 1399), V('정화의 원정', 1405, 1), V('토목의 변', 1449)] }),
      ] },
      { label: '북원 · 건주 여진', items: [
        O('북원', 1368, 1388, P.slate, '국가', { fuzzyE: true, cross: { from: '원', how: 'direct' }, cells: [['혜종', 1368, 1370], ['소종', 1370, 1378], ['천원제', 1378, 1388]] }),
        O('건주 여진', 1403, 1616, P.sage, '집단'),
      ] },
    ] },
    { n: '티베트', leaders: true, lines: 2, rows: [
      { label: '겔룩파', items: [O('겔룩파', 1409, 9999, P.butter, '교단', { cells: [['쫑카파', 1409, 1419], ['걀찹 제', 1419, 1431], ['케둡 제', 1431, 1438], ['바소', 1438, 1450]], ev: [V('데풍 사원', 1416), V('세라 사원', 1419), V('타실훈포 사원', 1447)] })] },
    ] },
    { n: '일본', leaders: true, lines: 2, rows: [
      { label: '조정', items: [O('조정', 538, 9999, P.lav, '국가', { cells: [['고다이고', 1318, 1336], ['고묘', 1336, 1348], ['스코', 1348, 1351], ['고코곤', 1352, 1371], ['고엔유', 1371, 1382], ['고코마쓰', 1382, 1412], ['쇼코', 1412, 1428], ['고하나조노', 1428, 1464], ['고쓰치미카도', 1464, 1500], ['고카시와바라', 1500, 1526]], ev: [V('남북조 합일', 1392, 1)] })] },
      { label: '남조', items: [O('남조', 1336, 1392, P.pink, '정부', { rival: true, cells: [['고다이고', 1336, 1339], ['고무라카미', 1339, 1368], ['조케이', 1368, 1383], ['고카메야마', 1383, 1392]] })] },
      { label: '막부', items: [O('무로마치 막부', 1336, 1573, P.sand, '실권 정권', { serve: { to: '조정', c: P.lav, rel: '명목상', a: 1336 },
        cells: [['다카우지', 1338, 1358], ['요시아키라', 1358, 1367], ['요시미쓰', 1368, 1394], ['요시모치', 1394, 1423], ['요시카즈', 1423, 1425], ['요시노리', 1429, 1441], ['요시카쓰', 1442, 1443], ['요시마사', 1449, 1473], ['요시히사', 1473, 1489], ['요시타네', 1490, 1493], ['요시즈미', 1494, 1508], ['요시타네', 1508, 1521]],
        ev: [V('오에이의 난', 1399), V('가키쓰의 난', 1441), V('오닌의 난', 1467, 1), V('메이오 정변', 1493)] })] },
    ] },
  ] }];
  S.detail = {
    path: ['동아시아', '한국'], title: '조선', when: '1392 ~ 1897년', kind: '국가', group: '다스리는 것',
    text: '이성계가 고려를 이어 세운 나라. 한양에 도읍하고 성리학을 나라의 틀로 삼았다.',
    facts: [['도읍', '한양'], ['왕실', '전주 이씨'], ['트랙', '한국']],
    offices: [{ n: '왕', count: 27, rows: [['태조 이성계', '1392 ~ 1398'], ['정종', '1398 ~ 1400'], ['태종', '1400 ~ 1418'], ['세종', '1418 ~ 1450']] }],
    links: [['앞', '고려', '직접']],
  };
  /* 뒤로 이어지는 객체(꼬리 마름모 자리) — 같은 줄의 다음 객체가 from을 가졌거나, 다른 줄 객체가 cross.from으로 가리킴 */
  const all = [];
  for (const C of S.cultures) for (const Tr of C.tracks) for (const r of Tr.rows) { r.items.forEach((o, i) => { all.push(o); if (o.from && i) r.items[i - 1].out = true; }); }
  for (const o of all) if (o.cross) { const a = all.find(q => q.n === o.cross.from); if (a) a.out = true; }
  return S;
}

/* ══ 줄 쌓기 ══ */
const bandH = tr => G.inset + (tr.leaders ? G.leader + G.slot : 0) + (tr.lines || 1) * G.line + G.inset;
/** 지금 앱 그대로(layout.dart _stack · _bandOf): 줄 위 틈 = 탭 18(트랙 둘째 줄부터 + 8) · 띠 = 4 + 지도자 25 + 글줄 21 × n + 4 · 트랙 아래 9 */
function layoutApp(S, L, M) {
  let y = M.top, ri = 0, ti = 0, ci = 0;
  for (const cu of S.cultures) {
    const C = L.cultures[ci++]; C.y0 = y;
    for (const tr of cu.tracks) {
      const Tr = L.tracks[ti++]; Tr.y0 = y;
      tr.rows.forEach((r, i) => {
        const row = L.rows[ri++], gap = (i ? G.gap : 0) + G.tab;
        row.y = y; row.yBand = y + gap; row.h = bandH(tr);
        row.spec = { leaders: !!tr.leaders, lines: tr.lines || 1 };
        y += gap + row.h;
      });
      Tr.y1 = y + 2; y += G.pad;
    }
    C.y1 = y - 4;
  }
  L.bottom = y;
}
/** 서고 그대로(blend.js relayout): 줄 위 틈 5(섬기는 객체가 있는 줄 20) · 꼬리표 머리 24(+ 글줄 21 × (n − 1)) · 칸이 있는 줄만 사슬 16 · 줄 사이 3 · 트랙 사이 4 */
function layoutSeogo(S, L, M) {
  let y = M.top, ri = 0, ti = 0, ci = 0;
  for (const cu of S.cultures) {
    const C = L.cultures[ci++]; C.y0 = y;
    for (const tr of cu.tracks) {
      const Tr = L.tracks[ti++]; Tr.y0 = y;
      for (const r of tr.rows) {
        const row = L.rows[ri++];
        const top = r.items.some(o => o.serve) ? M.tabHS : M.tabH0;
        const head = 24 + ((tr.lines || 1) - 1) * G.line, chain = tr.leaders && r.items.some(o => o.cells) ? M.chainH : 0;
        row.y = y; row.yBand = y + top; row.h = head + chain;
        row.spec = { seogo: true, lines: tr.lines || 1, head, chain };
        y += top + row.h + M.gap;
      }
      Tr.y1 = y - M.gap; y += M.trackGap;
    }
    C.y1 = y - M.trackGap;
  }
  L.bottom = y;
}

/* ══ 띠 자리 ══ b = 그릴 띠의 값(1px 선 맞춤 끝남) */
function geom(p, o, g) {
  const sp = (g.row && g.row.spec) || { leaders: false, lines: 1, head: Math.round(g.h), chain: 0, parts: true };
  let x0 = g.x0, x1 = g.x1, short = false;
  if (!g.cl && !g.cr && x1 - x0 < 6) { const m = Math.round((x0 + x1) / 2); x0 = m - 3; x1 = m + 3; short = true; } // 6px 알약(bands.dart _minBandPx)
  const X0 = px(x0), X1 = Math.round(x1) - .5, y0 = Math.round(g.y), H = Math.round(g.h);
  const lines = sp.lines || 1, leaders = !!sp.leaders;
  const textTop = y0 + G.inset + (leaders ? G.leader + G.slot : 0);
  const it = g.row ? g.row.items : [], k = it.indexOf(o), prev = it[k - 1], next = it[k + 1];
  const b = {
    X0, X1, y0, Y: y0 + .5, H, B: y0 + H - .5, w: X1 - X0, short, cl: !!g.cl, cr: !!g.cr, fuzzy: !!o.fuzzyE && !g.cr, sp, lines, leaders,
    seamL: !!(prev && prev.b === o.a), seamR: !!(next && next.a === o.b), next,
    leaderTop: y0 + G.inset, textTop, lineY: i => textTop + G.line / 2 + i * G.line, anchor: lines > 1 ? textTop + G.line : textTop + G.line / 2,
  };
  b.XR = b.fuzzy ? b.X1 + G.fade : b.X1; // 미정 끝은 44px 꼬리
  g.bb = b;
  return b;
}
const kindOf = o => o.g === '영토 밖' ? 'key' : o.g === '무리' ? 'plain' : 'cham';
/** 구멍의 가로 자리 — 왼쪽에서 7(확정). 영토 밖(둥근 끝 반지름 12)은 7이면 구멍 테가 둥근 끝에 닿아(0.7px) 9로 비킴 */
const holeX = (b, kind) => b.X0 + (kind === 'key' ? 9 : 7);

/** 꼬리표 윤곽 — kind 'cham'(왼쪽 두 귀 모따기 5) · 'key'(왼쪽 둥근 끝 — 반지름 상한 12) · 'plain'(직각). 오른쪽은 늘 직각.
 *  cl = 왼쪽이 화면 밖 · open = 오른쪽 세로 테 없음(미정 꼬리) */
function outline(x0, y, x1, h, kind, cl, o = {}) {
  const yb = y + h, w = x1 - x0;
  let d;
  if (cl || kind === 'plain') d = `M${x1},${y} H${x0} V${yb} H${x1}`;
  else if (kind === 'key') { const r = Math.min(o.r ?? KEYR, h / 2, w); d = `M${x1},${y} H${x0 + r} A${r},${r} 0 0 0 ${x0},${y + r} V${yb - r} A${r},${r} 0 0 0 ${x0 + r},${yb} H${x1}`; }
  else { const c = Math.min(o.c ?? CH, w / 2, h / 2); d = `M${x1},${y} H${x0 + c} L${x0},${y + c} V${yb - c} L${x0 + c},${yb} H${x1}`; }
  return o.open ? d : d + ' Z';
}
/** 미정 끝의 옅어짐 — 진짜 끝(xa)에서 44px 뒤(xb)까지 */
function fade(p, xa, xb, color) {
  const id = K.id('fade'), gr = E('linearGradient', { id, gradientUnits: 'userSpaceOnUse', x1: xa, x2: xb, y1: 0, y2: 0 }, p.defs);
  E('stop', { offset: 0, 'stop-color': color, 'stop-opacity': 1 }, gr);
  E('stop', { offset: 1, 'stop-color': color, 'stop-opacity': 0 }, gr);
  return `url(#${id})`;
}
/** 꼬리표 하나 칠하기 — 칠 · 테(무리는 테 없음 · 대립은 점선 테 · 미정은 오른쪽이 옅어지며 열림) */
function paintTag(th, p, o, b, x0, y, h, kind, layer, extra = {}) {
  const fill = th.fillOf(o.c), edge = th.edgeOf(o.c);
  const f = b.fuzzy ? fade(p, b.X1, b.XR, fill) : fill, s = b.fuzzy ? fade(p, b.X1, b.XR, edge) : edge;
  E('path', { d: extra.d || outline(x0, y, b.XR, h, kind, b.cl), fill: f, stroke: 'none' }, layer);
  if (kind !== 'plain') E('path', { d: extra.dOpen || outline(x0, y, b.XR, h, kind, b.cl, { open: b.fuzzy }), fill: 'none', stroke: s, 'stroke-dasharray': o.rival ? '3 2' : null }, layer);
  return { fill, edge };
}

/* ══ 띠 안의 단 — 지금 앱의 지도자 칸(strips.dart: 둥근 6 · 높이 22 · 종이 62% / 번갈아 제 색 12% · 테 = 제 색 92% + 먹 · 글 11.5 · 제 색 30% + 먹) ══ */
function appCells(th, p, o, b, lo, hi, top, bandFill) {
  if (!o.cells || !b.leaders) return;
  const soft = mixOk(o.c, .92, INK), ink = mix(o.c, .30, INK), on = mix('#ffffff', .62, bandFill), alt = mix(o.c, .12, '#ffffff');
  let i = 0;
  for (const [n, a, e] of o.cells) {
    const xa = Math.max(p.X(a), lo), xe = Math.min(p.X(e), hi);
    i++;
    if (xe - xa < 2) continue;
    const l = Math.round(xa) + .5, r = Math.round(xe) - .5, w = r - l;
    E('path', { d: rr(l, top + .5, w, G.leader - 1, Math.min(6, w / 2)), fill: i % 2 ? on : alt, stroke: soft }, p.band);
    const full = th.tw(n, 11.5, 'body') + 12 <= w, head = !full && th.tw(n[0], 11.5, 'body') + 8 <= w;
    if (full || head) th.t(p.band, (l + r) / 2, base(top + G.leader / 2, 11.5), full ? n : n[0], 'body', { size: 11.5, fill: ink, anchor: 'middle' });
  }
}
/** 서고 사슬 — 꼬리표 아래 이어 붙인 흰 꼬리표(모따기 3 · 먹 25) · 칸 글 8.5는 다 들어갈 때만 */
function chain(th, p, o, b, y, h, kind) {
  if (!o.cells) return;
  const k = a => th.k(a), x0 = b.X0, x1 = b.X1, ck = kind === 'key' ? 'key' : 'cham';
  E('path', { d: outline(x0, y, x1, h, ck, b.cl, { c: 3, r: Math.min(KEYR, h / 2) }), fill: '#ffffff', stroke: k(.25) }, p.band);
  let lastX = -1;
  for (const [n, a, e] of o.cells) {
    const xa = Math.max(p.X(a), x0 + 2, p.CL - 1), xe = Math.min(p.X(e), x1 - 2);
    if (xe - xa < 1) continue;
    for (const xx of [xa, xe]) { const q = Math.round(xx) + .5; if (Math.abs(q - lastX) < 2.5 || q < x0 + 3 || q > x1 - 3) continue; E('line', { x1: q, x2: q, y1: y + 1, y2: y + h - 1, stroke: k(.2) }, p.band); lastX = q; }
    if (th.tw(n, 8.5, 'body', 400) <= xe - xa - 6) th.t(p.band, xa + 3, base(y + h / 2, 8.5), n, 'body', { size: 8.5, wt: 400, fill: K.nameInk(o.c) });
  }
}

/* ══ 사건 글줄 — 점 + 이름(앱: 점 반지름 3.5 · 이름 11.5 · 띠 안쪽 9로 당김 · 글줄 둘에 번갈아 · 겹치면 뺌) ══
   opt: { lines[가운데 y] · lo · hi(점 자리) · rlim(이름 끝) · busy[글줄마다 막힌 구간] · size · dot · gap } */
function events(th, p, o, b, opt) {
  if (!o.ev) return;
  const size = opt.size ?? 11.5, dot = opt.dot ?? 3.5, gap = opt.gap ?? 6, busy = opt.busy || opt.lines.map(() => []);
  for (const e of [...o.ev].sort((u, v) => u.y - v.y)) {
    const x = Math.min(Math.max(p.X(e.y), opt.lo), opt.hi);
    if (p.X(e.y) < opt.lo - 30) continue;
    const wt = e.imp ? 700 : 400, w = th.tw(e.n, size, 'body', wt), a = x - dot - 1, z = x + dot + gap + w + 2;
    if (z > opt.rlim) continue;
    for (let li = 0; li < opt.lines.length; li++) {
      if (busy[li].some(([u, v]) => a < v + 4 && z > u - 4)) continue;
      const cy = opt.lines[li];
      E('circle', { cx: x, cy, r: dot, fill: th.edgeOf(o.c) }, p.band);
      th.t(p.band, x + dot + gap, base(cy, size), e.n, 'body', { size, wt, fill: e.imp ? th.k(1) : th.k(.72) });
      busy[li].push([a, z]);
      break;
    }
  }
}

/* ══ 구멍 · 꼬리 마름모 · 실(h-c.js 그대로) ══ */
function hole(th, p, x, y, sel) { E('circle', { cx: x, cy: y, r: 2.5, fill: '#ffffff', stroke: sel ? INK : th.k(.45) }, p.band); }
function diamond(p, cx, cy, c) { E('path', { d: `M${cx},${cy - DIA} L${cx + DIA},${cy} L${cx},${cy + DIA} L${cx - DIA},${cy} Z`, fill: mixOk(c, .6, INK), stroke: 'none' }, p.over); }
/** 마름모 가운데(dx, dy) → 뒤 꼬리표의 구멍(hx, hy). 줄을 건너면 세로 통로 xv에서 곧게 굽음 */
function thread(th, p, dx, dy, hx, hy, ind, xv) {
  let d;
  if (Math.abs(dy - hy) < 1) d = `M${dx},${dy} H${hx - 2.5}`;
  else {
    const r = Math.min(6, Math.abs(hy - dy) / 2, Math.max(0, hx - 2.5 - xv)), up = hy < dy ? -1 : 1;
    d = `M${dx},${dy} H${xv - r} Q${xv},${dy} ${xv},${dy + up * r} V${hy - up * r} Q${xv},${hy} ${xv + r},${hy} H${hx - 2.5}`;
  }
  E('path', { d, stroke: th.k(.5), 'stroke-width': 1.5, 'stroke-dasharray': ind ? '3 2' : null, fill: 'none', 'stroke-linejoin': 'round' }, p.over);
}
/** 꼬리표 갈래의 승계 — 같은 줄(link) · 줄 건넘(extra) 모두 g.tie = { hx, hy(구멍) · dx, dy(마름모) · xe(오른쪽 끝) } 로 */
function tieLink(th, p, a, b, how) {
  if (!a.tie || !b.tie || a.tie.dx == null || b.tie.hx == null) return;
  if (b.tie.hx - a.tie.dx < 10) return;
  thread(th, p, a.tie.dx, a.tie.dy, b.tie.hx, b.tie.hy, how === 'indirect', a.tie.xe);
  diamond(p, a.tie.dx, a.tie.dy, a.o.c);
}
function tieCross(th, p, L) {
  const all = L.rows.flatMap(r => r.items);
  for (const o of all) {
    if (!o.cross || !o.geo || !o.geo.tie) continue;
    const a = all.find(q => q.n === o.cross.from && q.geo);
    if (!a || !a.geo.tie || a.geo.tie.dx == null) continue;
    // 세로 통로: 같은 줄의 다음 꼬리표와 맞닿으면 그 틈의 가운데, 아니면 끝 + 8
    const ab = a.geo.bb, nx = ab.next && ab.next.geo ? ab.next.geo.bb : null;
    const xv = nx && nx.X0 - ab.X1 < 12 ? (ab.X1 + nx.X0) / 2 : ab.X1 + 8;
    thread(th, p, a.geo.tie.dx, a.geo.tie.dy, o.geo.tie.hx, o.geo.tie.hy, o.cross.how === 'indirect', xv);
    diamond(p, a.geo.tie.dx, a.geo.tie.dy, a.c);
  }
}

/* ══ 섬김 — 서고의 받침 카드(상국 빛깔 24% · 꼬리표 뒤 · 위로 6 드러남 · 뒤가 떨어져 있으면 오른쪽으로도 6) ══ */
function card(th, p, o, g, b, top, h, kind) {
  const s = o.serve, later = p.X(s.a) > g.x0 + 1, xs = later ? px(p.X(s.a)) : b.X0;
  const dx = b.next && p.X(b.next.a) - p.X(o.b) < 16 ? 0 : PEEK;
  const fill = th.fillOf(s.c), stroke = th.edgeOf(s.c), cy = top - PEEK, xr = Math.min(b.X1 + (b.cr ? 0 : dx), p.CR + 40);
  E('path', { d: outline(xs + dx, cy, xr, h, kind, b.cl || later), fill, stroke }, p.under);
  return { xs: xs + dx, xr, cy, fill, stroke, s };
}
/** 상국 이름 탭(서고 — 왼쪽 위 모따기 4 · 높이 12) — 받침 카드 윗변(yb)에서 솟음 · 오른쪽 끝 tr */
function hostTab(th, p, cd, tr, yb) {
  const s = cd.s, w = th.tw(s.to, 8.5, 'name') + 14, ht = 12, c = 4, tl = tr - w;
  E('path', { d: `M${tl},${yb + 1} V${yb - ht + c} L${tl + c},${yb - ht} H${tr} V${yb + 1} Z`, fill: cd.fill }, p.under);
  E('path', { d: `M${tl},${yb} V${yb - ht + c} L${tl + c},${yb - ht} H${tr} V${yb}`, fill: 'none', stroke: cd.stroke }, p.under);
  th.t(p.under, tl + 7, base(yb - ht / 2, 8.5), s.to, 'name', { size: 8.5, fill: K.tabInk(s.c) });
  return tl;
}
const hostW = (th, s) => th.tw(s.to, 8.5, 'name') + 14;

/* ══ 판 차례 ══ 이 파일이 마지막에 읽히므로 여기서 갈래 차례를 맞춤 */
const ORDER = ['t-0', 't-a', 't-b', 't-c', 't-d'];
window.THEMES.sort((a, b) => (ORDER.indexOf(a.id) + 1 || 99) - (ORDER.indexOf(b.id) + 1 || 99));

window.TAG = { G, PEEK, KEYR, CH, HOLE, DIA, scene, layoutApp, layoutSeogo, geom, kindOf, holeX, outline, fade, paintTag, appCells, chain, events, hole, diamond, thread, tieLink, tieCross, card, hostTab, hostW };

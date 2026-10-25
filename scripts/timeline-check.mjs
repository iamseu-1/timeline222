/* 실제 브라우저에서 성능 개선의 표시·입력·재사용을 검사합니다. 가상 자료는 별도 창의 메모리에만 둡니다.
   node scripts/timeline-check.mjs <검사할 폴더> <결과 폴더>
   Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을 지정합니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/연표-성능');
const built = process.argv.includes('--built');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const served = built ? path.join(root, 'dist', rel.startsWith('maker/') ? '' : 'web') : root;
    const file = path.resolve(served, rel);
    if (!file.startsWith(served + path.sep)) { res.writeHead(403); res.end(); return; }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js' || rel === 'maker/js/viewer.js') {
      const text = bytes.toString('utf8'), marker = '/* ---------- 팩 & 모델 ---------- */';
      assert.equal(text.split(marker).length, 2);
      bytes = Buffer.from(text.replace(marker, 'window.__tl=timeline;window.__state=state;\n' + marker));
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 포장본: built, 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  await page.goto('http://127.0.0.1:' + server.address().port + '/index.html');
  await page.waitForFunction(() => window.__tl && window.__state.model);
  await page.evaluate(() => {
    window.__load = raw => {
      const result = HT.normalizePack(raw);
      if (!result.pack || result.errors.length) throw Error(JSON.stringify(result.errors));
      const model = HT.buildModel([result.pack], null), tl = __tl;
      __state.model = model;
      tl.setSelected(null); tl.setHighlight(null); tl.setDensity(0);
      Object.assign(tl.show, { eras: false, capitals: false, epochs: false, ganji: false });
      tl.setData(model, { enter: false });
      return model;
    };
    const raw = { format: 'history-timeline-dlc', formatVersion: 3, id: 'performance-check', name: '가상 성능 검사', tracks: [{ id: 'plain', name: '가상 들녘' }], periods: [], events: [] };
    for (let r = 0; r < 30; r++) {
      raw.periods.push({ id: 'p' + r, name: '들녘국 ' + (r + 1), track: 'plain', people: '들녘 ' + (r + 1), start: 80, end: 1520, leaders: [{ name: '해든', start: 80, end: 740 }, { name: '새봄', start: 740, end: 1520 }] });
      for (let n = 0; n < 120; n++) raw.events.push({ id: `e${r}-${n}`, polity: 'p' + r, track: 'plain', title: ['공동 회의', '규약 공표', '항구 확장', '교역로 개방'][n % 4], start: 100 + Math.floor(n / 10) * 112 + (n % 10 < 7 ? (n % 10) * .9 : 40 + (n % 10 - 7) * 24) + (r % 3), category: 'politics', importance: n % 5 === 0 ? 3 : 2 });
    }
    window.__fixture = raw;
    __load(raw); __tl.setView(460, 1020); __tl.bodyEl.scrollTop = 0;
    window.__visible = () => {
      const box = __tl.bodyEl.getBoundingClientRect();
      return __tl.tracks.flatMap(tr => (tr.laneEls || []).filter(lane => { const r = lane.getBoundingClientRect(); return r.height > 0 && r.bottom > box.top && r.top < box.bottom; }).map(lane => [tr.id, lane.dataset.row, lane.innerHTML]));
    };
    window.__pan = (step = 2) => {
      __tl.bodyEl.classList.add('is-dragging');
      __tl.view = { start: __tl.view.start + step, end: __tl.view.end + step };
      __tl._draw();
    };
  });
  await page.waitForTimeout(500);
  const compare = await page.evaluate(() => {
    const tl = __tl, tr = tl.tracks[0], before = JSON.stringify(__visible()), heights = JSON.stringify([tr.height, tr.rowTop, tr.rowHs]);
    const drawn = tr._drawRows.size, count = tr.rows;
    tr._drawRows = null;
    tl._drawTrack(tr, y => (y - tl.view.start) * tl.W / tl.span(), tl.W);
    const same = before === JSON.stringify(__visible()), stable = heights === JSON.stringify([tr.height, tr.rowTop, tr.rowHs]);
    tl._draw();
    return { same, stable, drawn, count };
  });
  check(compare.same && compare.stable && compare.drawn < compare.count, '보이는 줄은 전체 그리기와 같고 전체 높이는 보존', compare);
  const reads = await page.evaluate(() => {
    const tl = __tl, body = tl.bodyEl;
    const height = Object.getOwnPropertyDescriptor(Element.prototype, 'clientHeight').get;
    const anchor = tl._autoAnchor;
    let heights = 0, anchors = 0;
    Object.defineProperty(body, 'clientHeight', { configurable: true, get() { heights++; return height.call(this); } });
    tl._autoAnchor = function () { anchors++; return anchor.call(this); };
    try { body.classList.add('is-dragging'); tl._draw(); }
    finally { delete body.clientHeight; tl._autoAnchor = anchor; body.classList.remove('is-dragging'); }
    return { heights, anchors };
  });
  check(reads.heights === 1 && reads.anchors === 0, '끌기 중 화면 높이는 한 번만 읽고 쓰지 않는 닻 계산은 생략', reads);
  const reuse = await page.evaluate(() => {
    __pan();
    const tr = __tl.tracks[0], scene = tr._panScene || tr._eventScene;
    const el = tr.laneEls[0].querySelector('.tl-ev');
    if (!scene || !el) return { scene: false };
    const x = el.getBoundingClientRect().x;
    __pan(3);
    const x2 = el.getBoundingClientRect().x;
    const reused = (tr._panScene || tr._eventScene) === scene && el.isConnected;
    window.__kept = el;
    return { scene: true, reused, shift: x2 - x, expected: -3 * __tl.W / __tl.span(), layers: tr.el.querySelectorAll('.tl-pan-events').length };
  });
  check(reuse.reused && Math.abs(reuse.shift - reuse.expected) < .15, '이동 중 기존 사건 요소를 보존하고 연도에 맞춰 이동', reuse);
  const changes = await page.evaluate(() => {
    const tl = __tl, tr = tl.tracks[0], uid = __kept.dataset.uid;
    const scene = () => tr._panScene || tr._eventScene;
    let old = scene(); tl.setSelected(uid); tl._draw();
    const selection = old !== scene() && !!tl.root.querySelector('.tl-ev.is-selected');
    old = scene(); tl.setHighlight(new Set([tr.events[12].uid])); tl._draw();
    const search = old !== scene();
    old = scene(); tl.setShowAlt(false); tl._draw();
    const alternatives = old !== scene();
    old = scene(); tl.setLens('local'); tl._draw();
    const lens = old !== scene();
    old = scene(); __pan(200);
    const boundary = old !== scene() && !tr._eventReuse;
    tl.view.end -= 30; tl._draw();
    const zoom = !tr._panScene && !tr._eventScene && !tr.el.querySelector('.tl-pan-events');
    tl.bodyEl.classList.remove('is-dragging'); tl._draw();
    return { selection, search, alternatives, lens, boundary, zoom, settled: !tl.root.querySelector('[data-pan],[data-ink]') };
  });
  check(Object.values(changes).every(Boolean), '선택·검색·이설·관점·여유 범위·확대·정착 때 재사용을 갱신', changes);
  await page.evaluate(() => { __tl.bodyEl.scrollTop = __tl.bodyEl.scrollHeight; });
  await page.waitForTimeout(80);
  const bottom = await page.evaluate(() => {
    const tr = __tl.tracks[0];
    return { last: !!tr.laneEls.at(-1).querySelector('.tl-band'), first: tr.laneEls[0].childElementCount, rows: tr._drawRows.size };
  });
  check(bottom.last && bottom.first === 0, '세로 스크롤로 들어온 줄을 채우고 멀어진 줄을 비움', bottom);
  await page.evaluate(() => { __tl.bodyEl.scrollTop = 0; __tl.setSelected(null); __tl.setHighlight(null); __tl.setShowAlt(true); __tl.setLens(''); __tl.setView(460, 1020); });
  await page.waitForTimeout(150);
  await page.evaluate(() => { __pan(); __pan(3); });
  const edges = await page.evaluate(() => {
    const box = __tl.bodyEl.getBoundingClientRect(), lo = box.left + __tl.gutter, hi = box.right;
    const clipped = [], vertical = [], duplicates = [];
    for (const lane of __tl.root.querySelectorAll('.tl-lane')) {
      const keys = new Set(), band = lane.querySelector('.tl-band')?.getBoundingClientRect();
      for (const el of lane.querySelectorAll('.tl-ev')) {
        if (keys.has(el.dataset.k)) duplicates.push(el.dataset.k);
        keys.add(el.dataset.k);
        const r = el.getBoundingClientRect();
        if (band && (r.top < band.top - 1 || r.bottom > band.bottom + 1)) vertical.push([el.dataset.k, r.top, r.bottom, band.top, band.bottom]);
      }
    }
    for (const el of __tl.root.querySelectorAll(':is(.tl-pan-events,.tl-pan-scene) .t, :is(.tl-pan-events,.tl-pan-scene) .y, :is(.tl-pan-events,.tl-pan-scene) .cnt, :is(.tl-pan-events,.tl-pan-scene) .tl-clu > b')) {
      if (getComputedStyle(el).visibility === 'hidden') continue;
      const r = el.getBoundingClientRect();
      if (r.right < lo || r.left > hi) continue;
      if (r.left < lo - 1 || r.right > hi + 1) clipped.push(el.textContent);
    }
    const dot = [...__tl.root.querySelectorAll(':is(.tl-pan-events,.tl-pan-scene) .tl-ev .d')].find(el => { const r = el.getBoundingClientRect(); return r.left > lo + 100 && r.right < hi - 100 && r.top > box.top && r.bottom < box.bottom; });
    const r = dot.getBoundingClientRect(), hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return { clipped, vertical, duplicates, clickable: hit?.closest('.tl-ev') === dot.parentElement, labels: __tl.root.querySelectorAll(':is(.tl-pan-events,.tl-pan-scene) .t').length, clusters: __tl.root.querySelectorAll(':is(.tl-pan-events,.tl-pan-scene) .tl-clu').length };
  });
  check(!edges.clipped.length && !edges.vertical.length && !edges.duplicates.length && edges.clickable && edges.labels > 0 && edges.clusters > 0, '이동 중 이름·개수는 반쯤 잘리지 않고 사건 누르기가 유지', edges);
  await page.screenshot({ path: path.join(output, '이동중-1920-1배.png') });
  const transition = await page.evaluate(() => {
    const tl = __tl;
    tl.setDensity(2); tl.relayout(); tl.bodyEl.classList.remove('is-dragging'); tl._draw();
    const bird = tl.isBird() && !tl.root.querySelector('.tl-pan-events');
    tl.setDensity(0); tl.relayout(); tl._draw();
    const svg = tl.toSVG({ width: 1920, title: '가상 연표 전체 저장' });
    return { bird, svg: svg.startsWith('<svg') && svg.includes('들녘국 30') && !svg.includes('data-pan') && !svg.includes('NaN') };
  });
  check(transition.bird && transition.svg, '이동 중 밀도 전환과 전체 그림 저장에 화면 밖 자료도 보존', transition);
  await page.waitForTimeout(450);
  /* 견본 DLC(samples/*.json — 지금은 등불 연대기 하나: 칸 이설 · 칸 장소 · 미상 칸 · 인물 · 실재성 · 나라 종류 · 부분 승계 · 시기 구분 · 칭호 · 대범위 · 조약을 모두 담음) */
  const samples = fs.readdirSync(path.join(root, 'samples')).filter(n => n.endsWith('.json')).map(n => path.basename(n, '.json'));
  check(samples.length > 0, '견본 DLC가 하나 이상 있음', samples);
  for (const name of samples) {
    const raw = JSON.parse(fs.readFileSync(path.join(root, 'samples', name + '.json'), 'utf8'));
    await page.evaluate(raw => {
      const model = __load(raw), tl = __tl;
      const dates = model.periods.flatMap(p => [p.start, p.endY]).filter(Number.isFinite);
      const lo = Math.min(...dates), hi = Math.max(...dates);
      tl.setView(lo - 20, hi + 20); tl.bodyEl.scrollTop = 0;
    }, raw);
    await page.waitForTimeout(120);
    const result = await page.evaluate(() => {
      const tl = __tl;
      tl._draw(); __pan(tl.span() / 500); __pan(tl.span() / 500);
      tl.setSelected(tl.tracks.find(t => t.events.length)?.events[0]?.uid || null); tl._draw();
      tl.bodyEl.classList.remove('is-dragging'); tl._draw();
      const svg = tl.toSVG({ width: 1920 });
      const selected = tl.selected;
      tl.toggleFold(tl.tracks[0].id); tl._draw(); tl.toggleFold(tl.tracks[0].id); tl._draw();
      return { bands: tl.root.querySelectorAll('.tl-band,.tl-mini').length, svg: !svg.includes('NaN') && !svg.includes('undefined') && svg.startsWith('<svg'), selected: tl.selected === selected };
    });
    check(result.bands > 0 && result.svg && result.selected, name + ' 이동·선택·접기·저장', result);
  }
  /* D1-W3 — 성씨 풍선(결정 6 A) · 가문 조명(결정 7 A) — 가상 가문 자료(손 자료). 확정 설계 5-2 · 5-3 · 10절 14번('함께').
     가문 조명 구간 · 아래 파는 HT.houseSpans · HT.houseUnder(D1-W1)가 있으면 그것을, 없으면 이 검사 안의 대역(설계 2-4 자의 꼴 — 같은 가문이 맞닿은 칸은 한 구간,
     지도자 칸이 없는 나라는 국성 기간)을 씁니다. 화소 비교는 켜고 끄기를 한 번 거친 화면에서(첫 다시 그리기의 띠 모서리 반 화소 — 옛 코드도 같음) */
  const KIN = { format: 'history-timeline-dlc', formatVersion: 3, id: 'house-light-check', name: '가상 가문 조명 검사',
    tracks: [{ id: 'hl-sea', name: '가상 바닷가' }, { id: 'hl-field', name: '가상 들녘' }],
    houses: [
      { id: 'h-on', name: '물빛 온씨', surname: '온', seat: '물빛', color: '#d7c18e' },
      { id: 'h-on-ba', name: '바람대군파', parent: 'h-on', color: '#dab195' },
      { id: 'h-ha', name: '재마루 하씨', surname: '하', seat: '재마루', color: '#a0bcc5' },
      { id: 'h-on-dl', name: '들빛 온씨', surname: '온', seat: '들빛', color: '#d4a39b' },
    ],
    periods: [
      { id: 'garam', track: 'hl-sea', name: '가람 나라', start: 400, end: 900, house: 'h-ha', leaders: [
        { name: '첫 임금', start: 400, end: 440, house: 'h-ha' },
        { name: '둘째 임금', start: 440, end: 480, house: 'h-on', names: [{ text: 'Dulkkae', kind: 'roman' }] },
        { name: '셋째 임금', start: 480, end: 520, house: 'h-on' },
        { name: '넷째 임금', start: 520, end: 570, house: 'h-ha' },
        { name: '다섯째 임금', start: 570, end: 620, house: 'h-on-ba', note: '본가에서 갈라진 파에서 오름' },
        { name: '여섯째 임금', start: 620, end: 700, house: 'h-ha' },
        { name: '일곱째 임금', start: 700, end: 780 },
        { name: '여덟째 임금', start: 780, end: 900, house: 'h-on' },
      ] },
      { id: 'nuri', track: 'hl-sea', name: '누리 나라', start: 470, startRange: [420, 520], end: 760, house: 'h-on-dl' },
      { id: 'dalbit', track: 'hl-field', name: '달빛 나라', start: 350, end: 950, leaders: [{ name: '달 임금', start: 350, end: 600 }, { name: '별 임금', start: 600, end: 950 }] },
    ],
    dynasties: [{ id: 'on-dyn', track: 'hl-sea', name: '온씨 왕조', start: 440, end: 520, polities: '가람 나라', house: 'h-on' }],
    events: [
      { id: 'e1', track: 'hl-sea', polity: 'garam', title: '바닷가 장터 열림', start: 590, category: 'politics' },
      { id: 'e2', track: 'hl-sea', polity: 'garam', title: '물길 넓힘', start: 610, category: 'politics' },
      { id: 'e3', track: 'hl-sea', polity: 'nuri', title: '들판 개간', start: 600, category: 'politics' },
    ] };
  await page.evaluate(raw => {
    window.__houseIds = (m, id) => (HT.houseUnder ? HT.houseUnder(m, id) : (m.houses || []).filter(h => (h.path || [h.id]).includes(id)).map(h => h.id));
    window.__houseSpans = (m, ids) => {
      if (HT.houseSpans) return HT.houseSpans(m, ids, { branches: true });
      const set = new Set(ids), out = [];
      for (const p of m.periods) {
        if (p.leaders && p.leaders.length) {
          let cur = null;
          for (const c of p.leaders) {
            const e = c.end ?? p.endY;
            if (!set.has(c.houseId)) { cur = null; continue; }
            if (cur && cur.end >= c.start) cur.end = Math.max(cur.end, e);
            else out.push((cur = { uid: p.uid, start: c.start, end: e }));
          }
        } else if (p.houseId && set.has(p.houseId)) out.push({ uid: p.uid, start: p.startRange ? p.startRange[0] : p.start, end: p.endY });
      }
      return out;
    };
    /* 띠 · 가문 줄 · 사건 글의 자리 (켜기 전과 견줌 — 띠 높이 · 가문 줄 · 사건 글이 그대로인가) */
    window.__geo = () => {
      const r = el => { const b = el.getBoundingClientRect(); return [b.x, b.y, b.width, b.height].map(v => Math.round(v * 10) / 10).join(','); };
      return {
        tracks: __tl.tracks.map(t => t.height),
        bands: [...__tl.root.querySelectorAll('.tl-band')].map(el => el.dataset.uid + ':' + r(el)),
        houselines: [...__tl.root.querySelectorAll('.tl-houseline')].map(el => r(el) + ':' + el.style.getPropertyValue('--hc')),
        labels: [...__tl.root.querySelectorAll('.tl-ev .t')].map(el => el.textContent + ':' + r(el)),
      };
    };
    __tl.show.houses = true; // 가문 줄(표시 체크 '가문')을 켠 채 — 조명이 가문 줄을 바꾸지 않는지
    __load(raw);
    __tl.setView(330, 980); __tl.bodyEl.scrollTop = 0;
  }, KIN);
  await page.mouse.move(1900, 1070);
  await page.evaluate(() => { __tl.setHouse('h-ha'); __tl.setHouse(null); });
  await page.waitForTimeout(200);
  const houseBefore = await page.screenshot();
  const geo0 = await page.evaluate(() => __geo());
  const zoneBox = await page.evaluate(() => { const z = __tl.root.querySelector(`.tl-band[data-uid="${CSS.escape(__state.model.periods.find(p => p.id === 'nuri').uid)}"] .tl-zone`).getBoundingClientRect(); return { x: Math.round(z.x) + 4, y: Math.round(z.y) + 4, width: Math.round(z.width) - 8, height: Math.round(z.height) - 8 }; });
  const zone0 = await page.screenshot({ clip: zoneBox });
  await page.evaluate(() => {
    const m = __state.model, ids = [...new Set(['h-on', 'h-on-dl'].flatMap(id => __houseIds(m, id)))]; // 성씨 '온'의 가문 모두(아래 파 포함)
    window.__litSpans = __houseSpans(m, ids);
    __tl.setHouse(ids, { spans: __litSpans, dim: true });
  });
  await page.waitForTimeout(200);
  const lit = await page.evaluate(() => {
    const m = __state.model, u = id => m.periods.find(p => p.id === id).uid;
    const band = id => __tl.root.querySelector(`.tl-band[data-uid="${CSS.escape(u(id))}"]`);
    const kids = el => [...el.children];
    const nuri = band('nuri'), at = sel => kids(nuri).findIndex(el => el.matches(sel));
    const lastZone = Math.max(...kids(nuri).map((el, i) => (el.matches('.tl-zone') ? i : -1)));
    const op = el => Number(getComputedStyle(el).opacity);
    const cells = id => [...band(id).querySelectorAll('.tl-cell.k-leader[data-cell]')].map(el => ({ house: el.classList.contains('is-house'), other: el.classList.contains('is-other-house'), op: op(el) }));
    /* 맨 위 날짜 칸의 괄호: 조명 구간을 겹치거나 맞닿으면 하나로 — 보기 안에 든 것만 */
    const merged = [];
    for (const s of __litSpans.slice().sort((a, b) => a.start - b.start)) { const l = merged[merged.length - 1]; if (l && s.start <= l[1]) l[1] = Math.max(l[1], s.end); else merged.push([s.start, s.end]); }
    const want = merged.filter(([a, b]) => b > __tl.view.start && a < __tl.view.end).length;
    return {
      paint: { garam: band('garam').querySelectorAll('.tl-spot.of-house').length, nuri: nuri.querySelectorAll('.tl-spot.of-house').length, dalbit: band('dalbit').querySelectorAll('.tl-spot').length },
      order: { spots: at('.tl-spots'), lastZone, garamSpots: kids(band('garam')).findIndex(el => el.matches('.tl-spots')), garamFirstCell: kids(band('garam')).findIndex(el => el.matches('.tl-cell, .tl-dyn')) },
      brackets: __tl.axisEl.querySelectorAll('.tl-spot-brk').length, want,
      garam: cells('garam'), dalbit: cells('dalbit'),
      geo: JSON.stringify(__geo()),
    };
  });
  const zone1 = await page.screenshot({ clip: zoneBox });
  const meanDiff = await page.evaluate(async ([a, b]) => {
    const load = src => new Promise(res => { const i = new Image(); i.onload = () => res(i); i.src = 'data:image/png;base64,' + src; });
    const [ia, ib] = await Promise.all([load(a), load(b)]);
    const px = i => { const c = document.createElement('canvas'); c.width = i.width; c.height = i.height; const g = c.getContext('2d'); g.drawImage(i, 0, 0); return g.getImageData(0, 0, i.width, i.height).data; };
    const pa = px(ia), pb = px(ib);
    let s = 0;
    for (let k = 0; k < pa.length; k += 4) s += (Math.abs(pa[k] - pb[k]) + Math.abs(pa[k + 1] - pb[k + 1]) + Math.abs(pa[k + 2] - pb[k + 2])) / 3;
    return s / (pa.length / 4);
  }, [zone0.toString('base64'), zone1.toString('base64')]);
  check(lit.paint.garam >= 3 && lit.paint.nuri === 1 && lit.paint.dalbit === 0, '가문 조명: 그 성의 가문(아래 파 포함)이 다스린 띠마다 칸 조명과 같은 칠 — 다른 나라 띠는 칠 없음', lit.paint);
  check(lit.order.lastZone >= 0 && lit.order.spots > lit.order.lastZone && lit.order.garamSpots >= 0 && lit.order.garamSpots < lit.order.garamFirstCell && meanDiff > 3, '가문 조명의 칠이 추정 빗금(.tl-zone) 위 · 칸 · 사건 아래 — 빗금 구간에서도 칠이 보임(10절 14번)', { order: lit.order, meanDiff });
  check(lit.brackets === lit.want && lit.want >= 2, '맨 위 날짜 칸 괄호: 조명 구간을 겹치거나 맞닿으면 하나로', { brackets: lit.brackets, want: lit.want });
  check(lit.garam.every(c => (c.house ? c.op === 1 && !c.other : c.other && Math.abs(c.op - 0.55) < 1e-6)) && lit.garam.some(c => c.house) && lit.dalbit.every(c => c.op === 1 && !c.other), '조명된 띠 안의 다른 가문 지도자 칸만 .55 — 그 가문 칸은 진하게, 다른 나라 띠는 그대로', { garam: lit.garam, dalbit: lit.dalbit });
  check(lit.geo === JSON.stringify(geo0), '가문 조명 중에도 띠 높이 · 자리 · 가문 줄(.tl-houseline) · 사건 글이 그대로', JSON.parse(lit.geo).tracks);
  await page.evaluate(() => __tl.setHouse(null));
  await page.waitForTimeout(200);
  const houseAfter = await page.screenshot();
  check(houseAfter.equals(houseBefore), '가문 조명을 켰다 끈 뒤 화면 = 켜기 전 화면(화소)');
  const oldForm = await page.evaluate(() => {
    __tl.setHouse('h-on'); __tl._draw();
    const r = { house: __tl.root.querySelectorAll('.tl-cell.is-house').length, spots: __tl.root.querySelectorAll('.tl-spot').length, brackets: __tl.axisEl.querySelectorAll('.tl-spot-brk').length, other: __tl.root.querySelectorAll('.is-other-house').length };
    __tl.setHouse(null); __tl._draw();
    return r;
  });
  check(oldForm.house === 3 && !oldForm.spots && !oldForm.brackets && !oldForm.other, '옛 꼴 setHouse(id): 그 가문의 칸만 진하게 — 칠 · 괄호 · 옅게 없음', oldForm);
  const spotOrder = await page.evaluate(() => {
    const m = __state.model, uid = m.periods.find(p => p.id === 'nuri').uid;
    __tl.setSpotlight({ uid, start: 430, end: 500 }); __tl._draw();
    const kids = [...__tl.root.querySelector(`.tl-band[data-uid="${CSS.escape(uid)}"]`).children];
    const r = { spots: kids.findIndex(el => el.matches('.tl-spots')), lastZone: Math.max(...kids.map((el, i) => (el.matches('.tl-zone') ? i : -1))) };
    __tl.setSpotlight(null); __tl._draw();
    return r;
  });
  check(spotOrder.spots > spotOrder.lastZone && spotOrder.lastZone >= 0, '칸 조명 · 메아리의 칠도 빗금 위(같은 칠은 같은 차례 — 10절 14번 함께)', spotOrder);
  await page.waitForTimeout(200);
  /* 풍선: 지도자 칸에 올림 → 칸 아래 8px · 연표 안 · 칸과 겹치지 않음 · 맨 위 층(사건 글이 위로 비치지 않음) · 띠 높이 그대로 · 설명글은 aria-label로 */
  const hoverAt = async sel => {
    const b = await page.locator(sel).first().boundingBox();
    await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
    await page.waitForTimeout(320);
    return page.evaluate(sel => {
      const el = __tl.root.querySelector('.tl-htip'), cell = __tl.root.querySelector(sel);
      if (!el || el.hidden) return { shown: false };
      const r = el.getBoundingClientRect(), c = cell.getBoundingClientRect(), body = __tl.bodyEl.getBoundingClientRect();
      const pts = [0.1, 0.5, 0.9].flatMap(fx => [0.1, 0.5, 0.9].map(fy => [r.left + r.width * fx, r.top + r.height * fy]));
      return {
        shown: true, text: el.textContent, house: el.querySelector('[data-tip-house]')?.textContent || '', rows: [...el.querySelectorAll('dt')].map(d => d.textContent),
        below: r.top >= c.bottom + 7.5, inside: r.left >= body.left + __tl.gutter - 0.5 && r.right <= body.right + 0.5 && r.top >= body.top - 0.5 && r.bottom <= body.bottom + 0.5,
        clear: r.bottom <= c.top || r.top >= c.bottom || r.right <= c.left || r.left >= c.right,
        top: pts.every(([x, y]) => el.contains(document.elementFromPoint(x, y))),
        title: cell.getAttribute('title'), aria: cell.getAttribute('aria-label') || '', right: body.right - r.right, shifted: r.left < c.left - 8.5,
        geo: JSON.stringify(__geo()),
      };
    }, sel);
  };
  const tipLeader = await hoverAt('.tl-band .tl-cell.k-leader[data-cell="leader:4"]');
  check(tipLeader.shown && /다섯째 임금/.test(tipLeader.text) && tipLeader.rows.join() === '성씨,본관,가문' && /온/.test(tipLeader.text) && /물빛/.test(tipLeader.text) && /물빛 온씨\s*›\s*바람대군파/.test(tipLeader.house) && /가문을 누르면 가문 조명/.test(tipLeader.text), '풍선: 이름 · 기간 · 성씨 · 본관 · 가문(파면 본가 길) · 누르는 길 — 없는 줄(왕조)은 뺌', tipLeader.text);
  check(tipLeader.below && tipLeader.inside && tipLeader.clear && tipLeader.top, '풍선: 칸 아래 8px · 연표 안(띠 밖 화면으로 돌출 없음) · 칸을 가리지 않음 · 맨 위 층이라 사건 글과 섞이지 않음', tipLeader);
  check(tipLeader.title === '' && /다섯째 임금/.test(tipLeader.aria) && tipLeader.geo === JSON.stringify(geo0), '풍선이 뜨는 칸은 설명글(title)을 걷고 aria-label로 · 풍선이 떠도 띠 높이 · 가문 줄 · 사건 글 자리 그대로', { title: tipLeader.title, aria: tipLeader.aria });
  const calls = [];
  await page.evaluate(() => { window.__keepSelect = __tl.opts.onSelect; __tl.opts.onSelect = (...a) => window.__selCalls.push(a); window.__selCalls = []; });
  await page.locator('.tl-htip [data-tip-house]').click();
  calls.push(...(await page.evaluate(() => { const c = __selCalls; __tl.opts.onSelect = __keepSelect; return c; })));
  const closed = await page.evaluate(() => __tl.root.querySelector('.tl-htip').hidden);
  check(calls.length === 1 && calls[0][0] === 'house:h-on-ba' && closed, '풍선의 가문을 누르면 그 가문 창(가문 조명)으로 — 풍선은 걷힘', calls);
  await page.mouse.move(1900, 1070);
  await page.waitForTimeout(150);
  const tipDyn = await hoverAt('.tl-band .tl-dyn');
  check(tipDyn.shown && /온씨 왕조/.test(tipDyn.text) && tipDyn.rows.join() === '성씨,본관,가문' && tipDyn.title === '' && tipDyn.inside, '왕조 칸에도 풍선(성씨 · 본관 · 가문) · 설명글은 aria-label로', tipDyn.text);
  await page.mouse.move(1900, 1070);
  await page.waitForTimeout(350);
  const gone = await page.evaluate(() => __tl.root.querySelector('.tl-htip').hidden);
  await page.evaluate(() => { __tl.setView(330, 800); }); // 마지막 칸(780~)이 화면 오른쪽 끝에 걸림
  await page.waitForTimeout(250);
  const tipEdge = await hoverAt('.tl-band .tl-cell.k-leader[data-cell="leader:7"]');
  check(gone && tipEdge.shown && tipEdge.inside && tipEdge.shifted && tipEdge.right >= 9.5, '마우스를 떼면 풍선이 걷히고, 화면 끝의 칸에서는 풍선이 화면 안으로 비킴', { gone, right: tipEdge.right, shifted: tipEdge.shifted });
  await page.mouse.move(1900, 1070);
  await page.evaluate(() => { __tl.show.houses = false; });
  const fixture = await page.evaluate(() => __fixture);
  await context.close();
  const motion = await browser.newContext({ viewport: { width: 1920, height: 1080 }, reducedMotion: 'no-preference', serviceWorkers: 'block' });
  const real = await motion.newPage();
  real.on('pageerror', e => report.오류.push(e.message));
  await real.goto('http://127.0.0.1:' + server.address().port + '/index.html');
  await real.waitForFunction(() => window.__tl && document.querySelector('.tl-band'));
  await real.waitForTimeout(600);
  const input = await real.evaluate(() => ({ view: { ...__tl.view }, box: __tl.bodyEl.getBoundingClientRect().toJSON() }));
  await real.mouse.move(1100, 500); await real.mouse.down(); await real.mouse.move(1350, 510, { steps: 12 }); await real.mouse.up();
  await real.waitForTimeout(450);
  const moved = await real.evaluate(() => ({ ...__tl.view }));
  await real.mouse.wheel(0, -200); await real.waitForTimeout(450);
  const zoomed = await real.evaluate(() => ({ ...__tl.view }));
  check(moved.start !== input.view.start && zoomed.end - zoomed.start < moved.end - moved.start, '일반 움직임 설정에서 실제 마우스 끌기·휠 확대 입력');
  await real.screenshot({ path: path.join(output, '기본팩-1920-1배.png') });
  await real.evaluate(raw => {
    const model = HT.buildModel([HT.normalizePack(raw).pack], null);
    __state.model = model; __tl.setData(model); __tl.setView(460, 1020);
  }, fixture);
  await real.waitForTimeout(800);
  const flowing = await real.evaluate(() => {
    const tl = __tl;
    tl.bodyEl.classList.add('is-dragging'); tl._draw();
    tl.setDensity(2); tl.relayout(); tl._draw();
    const clean = !tl.root.querySelector('.tl-pan-events');
    tl.bodyEl.classList.remove('is-dragging');
    tl.setDensity(0); tl.relayout();
    return clean;
  });
  await real.waitForTimeout(850);
  const restored = await real.evaluate(() => {
    const tl = __tl, tr = tl.tracks[0]; tl._draw();
    return !tl.isBird() && tr._drawRows?.size < tr.rows && !!tr.laneEls[0].querySelector('.tl-ev');
  });
  check(flowing && restored, '일반 움직임에서 이동 중 조감 전환 후 줄·사건을 복원');
  await motion.close();
  const makerContext = await browser.newContext({ viewport: { width: 1920, height: 1080 }, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const maker = await makerContext.newPage();
  maker.on('pageerror', e => report.오류.push(e.message));
  await maker.goto('http://127.0.0.1:' + server.address().port + '/' + (built ? 'maker/' : '') + 'dlc-maker.html');
  await maker.locator('[data-start-new]').waitFor();
  await maker.locator('[data-start-new] [name="name"]').fill('가상 성능 확인');
  await maker.locator('[data-start-new] [name="id"]').fill('performance-maker');
  await maker.locator('[data-start-new] [name="how"][value="base"]').check();
  await maker.locator('[data-start-new] button[type="submit"]').click();
  await maker.waitForFunction(() => window.__tl && document.querySelector('#mkStart').hidden && document.querySelector('.tl-band'));
  await maker.waitForTimeout(200);
  const makerOK = await maker.evaluate(() => {
    const tl = __tl;
    tl.bodyEl.classList.add('is-dragging'); tl.view.start += 2; tl.view.end += 2; tl._draw();
    tl.view.start += 2; tl.view.end += 2; tl._draw();
    tl.bodyEl.classList.remove('is-dragging'); tl._draw();
    return !!tl.root.querySelector('.tl-band') && !tl.root.querySelector('.tl-pan-events');
  });
  check(makerOK, '메이커 작업실의 미리보기 이동·정착');
  await maker.screenshot({ path: path.join(output, '메이커-1920-1배.png') });
  await makerContext.close();
  check(report.오류.length === 0, '브라우저 실행 오류 없음', report.오류);
} catch (e) { report.오류.push(e.stack || String(e)); process.exitCode = 1; }
finally { await browser.close(); server.close(); fs.writeFileSync(path.join(output, '화면검사.json'), JSON.stringify(report, null, 2) + '\n'); }
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류, 결과: output }));

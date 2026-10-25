/* 서고 배치 3단(메이커 미리보기)을 실제 브라우저에서 확인합니다 — 인수인계 5-14.
   node scripts/seogo-check.mjs <검사할 폴더> <결과 폴더>   (크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT로 — 다른 브라우저 검사와 같게)
   등불 연대기 견본을 작업본으로 독립 브라우저의 저장소에만 넣고:
   ① 서고 갈래(.tl.is-seogo) · 문화권 머리 단(쓰는 문화권마다 하나 · 높이 20 · 기본 문화권 하나만 펼침 · 접힌 문화권의 트랙은 높이 0 · 머리 단 안 작은 꼬리표)
   ② 두 장 꼬리표: 띠 안 구멍 · 띠 위 .tl-head 없음 · 이름 글(.tl-tab)이 띠 안 top 0 · 칸 층 14 · 사건 칸 18
   ③ 왼쪽 칸: 민족 칸 없음 · 줄 이름 = 작은 꼬리표 그림 + 띠 이름 · 줄 이름의 위가 띠의 위와 같음
   ④ 승계선: 떠나는 띠의 꼬리 마름모 · 선의 끝이 뒤 띠의 구멍 왼쪽 테
   ⑤ 그릇 세 상태: 펼침(폴더 --bodyTop · 매다는 실 · 왼쪽 칸 폴더 그림) · 접음(닫힌 폴더의 작은 꼬리표) · 풂(열쇠표) · 오른쪽 클릭 차림표 맨 위 세 줄
   ⑥ 문화권 머리 단 누르면 펴짐 · 기억(ht.maker.ui foldedSpheres)  ⑦ 1배 그림 · 콘솔 오류 없음 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/서고3단-검사');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (ok, text, details) => { report.검사.push({ 검사: text, 결과: !!ok, ...(details !== undefined ? { 자세히: details } : {}) }); if (!ok) report.오류.push(text + (details !== undefined ? ' ' + JSON.stringify(details) : '')); };

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json', '.woff2': 'font/woff2' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    const bytes = fs.readFileSync(file);
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, locale: 'ko-KR' });
const draft = JSON.parse(fs.readFileSync(path.join(root, 'samples/sample-lantern.json'), 'utf8'));
await context.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d)); localStorage.setItem('ht.maker.ui', JSON.stringify({})); }, draft);
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
const settle = ms => page.waitForTimeout(ms);
try {
  await page.goto(base + 'dlc-maker.html');
  await page.locator('#timeline .tl-track').first().waitFor({ timeout: 30000 });
  await settle(1200);

  /* ① 서고 갈래 · 문화권 머리 단 */
  const s1 = await page.evaluate(() => {
    const tl = HT.liveTimeline;
    const heads = [...document.querySelectorAll('#timeline .tl-sphere')].map(e => ({ id: e.dataset.sphere, h: e.querySelector('.tl-sphere-rows') ? e.querySelector('.tl-sphere-rows').offsetTop : e.getBoundingClientRect().height, // 머리 단 자체 — 과제 9의 단 밑 줄(시대 · 주기 · 사람)이 있으면 그 줄이 시작하는 자리
      folded: e.classList.contains('is-folded'), tags: e.querySelectorAll('.tl-stag').length, text: e.querySelector('b').textContent }));
    const tracks = tl.tracks.map(t => ({ id: t.id, sphere: t.sphere, hidden: !!t._sphereHidden, h: t.el ? t.el.getBoundingClientRect().height : -1 }));
    return { seogo: document.querySelector('#timeline').classList.contains('is-seogo'), heads, tracks, used: [...new Set(tl.tracks.map(t => t.sphere))].length, open: heads.filter(h => !h.folded).length };
  });
  check(s1.seogo, '① 메이커 미리보기가 서고 갈래(.tl.is-seogo)');
  check(s1.heads.length === s1.used && s1.heads.every(h => h.h === 20), '① 쓰는 문화권마다 머리 단 하나 · 높이 20', { 머리단: s1.heads.length, 문화권: s1.used, 높이: s1.heads.map(h => h.h) });
  check(s1.open === 1 && !s1.heads[0].folded, '① 처음에는 기본 문화권(고치는 DLC의 첫 트랙) 하나만 펼침', s1.heads.map(h => `${h.text}${h.folded ? ' 접힘' : ' 펼침'}`));
  check(s1.tracks.filter(t => t.hidden).every(t => t.h === 0) && s1.tracks.filter(t => !t.hidden).every(t => t.h > 0), '① 접힌 문화권의 트랙은 높이 0 · 펼친 문화권의 트랙은 보임', s1.tracks);
  check(s1.heads.filter(h => h.folded).some(h => h.tags > 0), '① 접힌 문화권 머리 단 안에 작은 꼬리표', s1.heads.map(h => h.tags));

  /* ② 두 장 꼬리표 */
  await page.evaluate(() => HT.liveTimeline.setView(500, 1200));
  await settle(900);
  const s2 = await page.evaluate(() => {
    const tl = HT.liveTimeline;
    const G = tl._G();
    const bands = [...document.querySelectorAll('#timeline .tl-track:not(.is-folded) .tl-lane .tl-band.is-tag')];
    const heads = document.querySelectorAll('#timeline .tl-head').length;
    const holes = bands.filter(b => b.querySelector(':scope > .tl-hole')).length;
    const tabs = [...document.querySelectorAll('#timeline .tl-lane .tl-tab')].map(t => parseFloat(t.style.top));
    const tr = tl.tracks.find(t => !t.folded);
    const geo = tr && tr.geos && tr.geos.find(g => g.leaderH);
    const cellHs = [...document.querySelectorAll('#timeline .tl-band .tl-cell.k-leader')].slice(0, 5).map(c => c.getBoundingClientRect().height);
    return { bands: bands.length, heads, holes, tabs: [...new Set(tabs)], G: { head: G.head, line: G.line, leader: G.leader, slotGap: G.slotGap, tab: G.tab }, geo: geo && { dynastyTop: geo.dynastyTop, leaderTop: geo.leaderTop, textTop: geo.textTop, lineH: geo.lineH, rowH: geo.rowH }, cellHs };
  });
  check(s2.bands > 0 && s2.heads === 0 && s2.holes > 0, '② 띠 위 이름 색줄(.tl-head) 없이 띠 안에 구멍', { 띠: s2.bands, head: s2.heads, 구멍: s2.holes });
  check(s2.tabs.length === 1 && s2.tabs[0] === 0, '② 이름 글(.tl-tab)이 띠 안 top 0', s2.tabs);
  check(s2.G.head === 14 && s2.G.line === 18 && s2.G.leader === 14 && s2.G.slotGap === 0, '② 값 묶음: 색줄 14 · 사건 칸 18 · 칸 층 14 · 틈 0', s2.G);
  check(s2.geo && s2.geo.dynastyTop >= 14 && s2.geo.leaderTop >= 14 && s2.geo.textTop > s2.geo.leaderTop && s2.geo.lineH === 18, '② 줄 자리: 칸 층이 색줄 아래 · 사건 칸이 칸 층 아래', s2.geo);
  check(s2.cellHs.length && s2.cellHs.every(h => Math.abs(h - 14) <= 1), '② 지도자 칸 높이 14', s2.cellHs);

  /* ③ 왼쪽 칸 */
  const s3 = await page.evaluate(() => {
    const tl = HT.liveTimeline;
    const tr = tl.tracks.find(t => !t.folded && t.rows > 0);
    const sec = tr.el;
    const peoples = getComputedStyle(sec.querySelector('.tl-peoples')).display;
    const rows = [...sec.querySelectorAll('.tl-rows .tl-row.is-seogo')].slice(0, 4).map(r => ({ row: r.dataset.row, top: r.getBoundingClientRect().top, text: r.textContent.trim(), tag: !!r.querySelector('.tl-rtag') }));
    const lanes = rows.map(r => sec.querySelector(`.tl-lane[data-row="${r.row}"]`).getBoundingClientRect().top);
    const nm = sec.querySelector('.tl-rows .tl-row.is-seogo .nm');
    const nmStyle = nm && getComputedStyle(nm);
    return { gutter: tl.gutter, peoples, rows, lanes, font: nmStyle && `${nmStyle.fontSize}/${nmStyle.fontWeight}/${nmStyle.lineHeight}` };
  });
  check(s3.peoples === 'none' && s3.rows.length && s3.rows.every(r => r.tag && r.text), '③ 민족 칸 없이 줄 이름 = 작은 꼬리표 그림 + 띠 이름', { 민족칸: s3.peoples, 줄: s3.rows.map(r => r.text) });
  check(s3.rows.every((r, i) => Math.abs(r.top - s3.lanes[i]) <= 0.5), '③ 줄 이름의 위 = 띠(줄)의 위', s3.rows.map((r, i) => r.top - s3.lanes[i]));
  check(s3.font === '11px/700/14px', '③ 줄 이름 글 11 굵게 · 글줄 14', s3.font);

  /* ④ 승계선 */
  const s4 = await page.evaluate(() => {
    const tl = HT.liveTimeline;
    const out = { diamonds: 0, links: 0, matched: 0, samples: [] };
    for (const tr of tl.tracks) {
      if (!tr.marksEl || tr.folded) continue;
      const ds = [...tr.marksEl.querySelectorAll('.tl-diamond')];
      out.diamonds += ds.length;
      for (const l of tr.linksEl.querySelectorAll('path.tl-link[data-from]')) {
        out.links++;
        const m = l.getAttribute('d').match(/^M([-\d.]+) ([-\d.]+)/);
        if (!m) continue;
        const [x, y] = [Number(m[1]), Number(m[2])];
        const d = ds.find(p => { const pt = p.getAttribute('points').split(' ')[1].split(','); return Math.abs(Number(pt[0]) - 3 - x) < 0.6 && Math.abs(Number(pt[1]) - y) < 0.6; });
        if (d) out.matched++;
        if (out.samples.length < 3) out.samples.push({ from: l.dataset.from, x, y, diamond: !!d });
      }
    }
    return out;
  });
  check(s4.diamonds > 0 && s4.links > 0 && s4.matched >= s4.diamonds, '④ 승계선이 떠나는 띠마다 꼬리 마름모 · 선이 마름모 가운데에서 시작(내림줄 · 합류는 마름모 밑에서)', s4);

  /* ⑤ 그릇 세 상태 — 폴더 왼쪽 끝이 화면 안에 들게(이름표가 보이게) 380 ~ 1200 */
  await page.evaluate(() => HT.liveTimeline.setView(380, 1200));
  await settle(900);
  const shot = async name => { const b = await page.locator('#timeline').boundingBox(); if (b) await page.screenshot({ path: path.join(output, name), clip: b }); };
  await page.evaluate(() => HT.liveTimeline.setScopeState(HT.liveTimeline.scopes.find(x => x.track === 'hayeon').uid, 'closed'));
  await settle(900);
  await shot('5-그릇-접음.png');
  await page.evaluate(() => HT.liveTimeline.setScopeState(HT.liveTimeline.scopes.find(x => x.track === 'hayeon').uid, 'loose'));
  await settle(900);
  await shot('6-그릇-풂.png');
  const s5 = await page.evaluate(async () => {
    const tl = HT.liveTimeline;
    const s = tl.scopes.find(x => tl.tracks.some(t => t.id === x.track && !t.folded));
    if (!s) return { none: true };
    const trOf = () => tl.tracks.find(t => t.id === s.track); // 다시 지으면 트랙 객체가 새로 생기므로 상태를 바꿀 때마다 다시 찾음
    const wait = () => new Promise(r => setTimeout(r, 700));
    tl.setScopeState(s.uid, 'open');
    await wait();
    let tr = trOf();
    const el = tr.lanesEl.querySelector(`.tl-scope[data-uid="${CSS.escape(s.uid)}"]`);
    if (el) el.scrollIntoView({ block: 'center' });
    await wait();
    const r = el && el.getBoundingClientRect();
    const axis = document.querySelector('#timeline .tl-axis');
    const ab = axis ? axis.getBoundingClientRect().bottom : 0;
    const o = { name: s.name, open: tl.scopeStateOf(s.uid), bodyTop: el && el.style.getPropertyValue('--bodyTop'), threads: tr.lanesEl.querySelectorAll('.tl-thread').length, folder: !!tr.el.querySelector('.tl-rows .tl-folder'), box: r && { x: r.left + r.width / 2, y: Math.max(r.top + 40, ab + 8) } }; // 누를 자리: 날짜 칸 아래 · 폴더 안
    tl.setScopeState(s.uid, 'closed');
    await wait();
    tr = trOf();
    o.closed = tl.scopeStateOf(s.uid);
    o.closedTags = tr.lanesEl.querySelectorAll('.tl-lane.is-folded .tl-stag').length;
    o.closedFolder = !!tr.el.querySelector('.tl-rows .tl-folder.is-closed');
    tl.setScopeState(s.uid, 'loose');
    await wait();
    tr = trOf();
    o.loose = tl.scopeStateOf(s.uid);
    o.keys = tr.lanesEl.querySelectorAll('.tl-key').length;
    tl.setScopeState(s.uid, 'open');
    await wait();
    tr = trOf();
    const el2 = tr.lanesEl.querySelector(`.tl-scope[data-uid="${CSS.escape(s.uid)}"]`);
    if (el2) el2.scrollIntoView({ block: 'center' });
    await wait();
    const r2 = el2 && el2.getBoundingClientRect();
    o.box = r2 && { x: r2.left + r2.width / 2, y: Math.max(r2.top + 40, ab + 8) }; // 누를 자리는 마지막으로 지은 폴더에서
    return o;
  });
  if (s5.none) check(false, '⑤ 보이는 트랙에 대범위가 없어 세 상태를 못 봄');
  else {
    check(s5.open === 'open' && s5.bodyTop && s5.threads > 0 && s5.folder, '⑤ 펼침: 폴더 몸통 자리(--bodyTop) · 매다는 실 · 왼쪽 칸 폴더', s5);
    check(s5.closed === 'closed' && s5.closedTags > 0 && s5.closedFolder, '⑤ 접음: 닫힌 폴더의 작은 꼬리표 · 왼쪽 칸 접힌 폴더', { closed: s5.closed, tags: s5.closedTags, folder: s5.closedFolder });
    check(s5.loose === 'loose' && s5.keys > 0, '⑤ 풂: 구성 띠 위에 열쇠표', { loose: s5.loose, keys: s5.keys });
    if (s5.box) {
      await page.mouse.click(s5.box.x, s5.box.y, { button: 'right' });
      await settle(300);
      const menu = await page.evaluate(() => [...document.querySelectorAll('#ctxMenu .ctx-item, #ctxMenu .ctx-title, #ctxMenu [class*="ctx"]')].map(e => e.textContent.replace(/\s+/g, ' ').trim()).filter((t, i, a) => t && t !== a[i - 1]).slice(0, 8)); // 이어 같은 글(차림 줄과 그 안 글)은 하나로 — 과제 9에서 선반 줄이 더해짐
      check(menu.some(t => t.includes('그릇')) && ['펼침', '선반', '접음', '풂'].every(w => menu.some(t => t.startsWith(w))), '⑤ 그릇 안 오른쪽 클릭 차림표 맨 위에 펼침 · 선반 · 접음 · 풂', menu);
      await page.keyboard.press('Escape');
      await settle(200);
    }
  }
  await page.screenshot({ path: path.join(output, '1-서고3단-그릇펼침.png') });
  await shot('4-그릇-펼침.png');

  /* ⑥ 문화권 머리 단 누르기 */
  const folded = page.locator('#timeline .tl-sphere.is-folded').first();
  const fid = await folded.getAttribute('data-sphere');
  await folded.click();
  await settle(3000); // 작업실 설정은 몇 초 늦게 저장됨
  const s6 = await page.evaluate(id => {
    const tl = HT.liveTimeline;
    const ui = JSON.parse(localStorage.getItem('ht.ui') || '{}'); // 보기 설정(state.ui)은 HT.KEYS.ui = 'ht.ui'에
    const s = tl.spheres.find(x => x.id === id);
    return { folded: s.folded, trackH: s.tracks.map(t => t.el.getBoundingClientRect().height), remembered: Array.isArray(ui.foldedSpheres) && !ui.foldedSpheres.includes(id), open: tl.spheres.filter(x => !x.folded).length };
  }, fid);
  check(!s6.folded && s6.trackH.every(h => h > 0) && s6.remembered && s6.open === 2, '⑥ 머리 단을 누르면 그 문화권이 펴지고 기억됨(ht.ui foldedSpheres)', s6);
  await page.screenshot({ path: path.join(output, '2-서고3단-문화권둘.png') });
  /* 본국에 매달리지 않은 폴더(청림 트랙의 대범위)도 펼쳐 찍음 — 어깨 탭이 몸통 위에 */
  const s7 = await page.evaluate(async () => {
    const tl = HT.liveTimeline;
    const s = tl.scopes.find(x => x.track === 'cheongnim');
    if (!s) return null;
    const t0 = tl.tracks.find(t => t.id === s.track);
    if (t0 && t0._sphereHidden) tl.toggleFoldSphere(t0.sphere, false); // 그 트랙의 문화권이 접혀 있으면 먼저 폄
    await new Promise(r => setTimeout(r, 900));
    tl.setScopeState(s.uid, 'open');
    await new Promise(r => setTimeout(r, 900));
    const tr = tl.tracks.find(t => t.id === s.track);
    const el = tr.lanesEl.querySelector(`.tl-scope[data-uid="${CSS.escape(s.uid)}"]`);
    const b = tr.scopeBranches.find(x => x.uid === s.uid);
    const lane = tr.laneEls[b.first];
    const name = el.querySelector('.tl-scope-name');
    const body = parseFloat(getComputedStyle(el, '::before').top);
    const r = { el: el.getBoundingClientRect().top, lane: lane.getBoundingClientRect().top, name: name.getBoundingClientRect().top, bodyTop: body, hung: b.box.hung };
    el.scrollIntoView({ block: 'center' });
    return { name: s.name, gap: r.lane - (r.el + r.bodyTop), nameAbove: r.name + 15 <= r.el + r.bodyTop, hung: r.hung };
  });
  if (s7) check(!s7.hung && Math.abs(s7.gap - 16) <= 0.5 && s7.nameAbove, '⑥ 매달리지 않은 폴더: 몸통 윗변이 첫 띠 윗변 위 16 · 어깨 탭이 몸통 위', s7);
  await settle(400);
  await shot('7-폴더-청림.png');
  const tlBox = await page.locator('#timeline').boundingBox();
  if (tlBox) await page.screenshot({ path: path.join(output, '3-서고3단-연표.png'), clip: tlBox });
  check(!errors.length, '⑦ 콘솔 오류 없음', errors.slice(0, 5));
} finally {
  await browser.close();
  server.close();
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
  console.log(`${report.오류.length ? '문제 ' + report.오류.length : '모두 통과'} · ${report.검사.length}건 · ${output}`);
  for (const e of report.오류) console.log('  ✗ ' + e);
}

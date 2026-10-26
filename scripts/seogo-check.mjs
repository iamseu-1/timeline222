/* 서고 배치 3단(메이커 미리보기)을 실제 브라우저에서 확인합니다 — 인수인계 5-14.
   node scripts/seogo-check.mjs <검사할 폴더> <결과 폴더>   (크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT로 — 다른 브라우저 검사와 같게)
   등불 연대기 견본을 작업본으로 독립 브라우저의 저장소에만 넣고:
   ① 서고 갈래(.tl.is-seogo) · 문화권 머리 단(쓰는 문화권마다 하나 · 높이 20 · 기본 문화권 하나만 펼침 · 접힌 문화권의 트랙은 높이 0 · 머리 단 안 작은 꼬리표)
   ② 두 장 꼬리표: 띠 안 구멍 · 띠 위 .tl-head 없음 · 이름 글(.tl-tab)이 띠 안 top 0 · 칸 층 14 · 사건 칸 18
   ③ 왼쪽 칸: 민족 칸 없음 · 줄 이름 = 작은 꼬리표 그림 + 띠 이름 · 줄 이름의 위가 띠의 위와 같음
   ④ 승계선: 떠나는 띠의 꼬리 마름모 · 선의 끝이 뒤 띠의 구멍 왼쪽 테
   ⑤ 그릇 세 상태: 펼침(폴더 --bodyTop · 매다는 실 · 왼쪽 칸 폴더 그림) · 접음(닫힌 폴더의 작은 꼬리표) · 풂(열쇠표) · 오른쪽 클릭 차림표 맨 위 세 줄
   ⑥ 문화권 머리 단 누르면 펴짐 · 기억(ht.maker.ui foldedSpheres)  ⑦ 1배 그림 · 콘솔 오류 없음
   ⑧ 직위 줄 더의 줄 높이(4단계 배치 갈래 · 감독 결정 G7 가 · 계약 1-1 덧붙임): 형식 4 시험 자료 f4-office4를 메이커가 파일을 열 때처럼 옛 꼴로 내려(HT.F4.down) 새 창에 넣고 —
      직위 줄 더가 있는 줄의 몸통이 n × 14만큼 높음(직위 줄 더를 걷고 다시 지은 배치와 견줌) · 내각 다음 자리 · 같은 줄의 수가 다른 두 띠가 제 층만 맞붙음 ·
      직위 줄 더 칸 수(빌린 줄은 출처의 칸) · 글자 겹침 · 띠 밖 돌출 없음 · 표시 체크 '지도자'를 끄면 층 없음 · 콘솔 오류 없음
   ⑨ 지도자 두 단(4단계 배치 갈래 둘째 · 감독 고름 더 정통성 넷 가 다듬은 꼴 lg2-ga · 계약 1-1 덧붙임): 형식 4 시험 자료 f4-legit를 옛 꼴로 내려(HT.F4.down) 새 창에 넣고 —
      하연 · 설원 띠의 지도자 층이 28(두 단 · 칸마다 제 단 자리) · 같은 줄의 한 단 띠(두레 뒤나라 · 갈매 후왕국)는 제 14만 맞붙음 · 섭정 · 명목만 있는 띠(여울)와
      정통성 없이 겹친 띠(버들) · 주장이 맞닿기만 한 띠(자갈)는 14 · 다섯 겹 공동(물레)은 4단까지 · 두 단 칸 수 · 이름 글자 겹침 · 띠 밖 돌출 없음 · 콘솔 오류 없음
   ⑩ 띠마다 제 몸통 높이(과제 8 걸음 3 · 줄어드는 층): 같은 창에서 짧은 몸통 줄(갈매 · 나루터 · 솔)의 칸 뭉치 = 띠들 몸통의 큰 값(줄어드는 층을 0으로 둔 배치와 견줘 14 낮음 ·
      모래톱은 그대로 · 산호는 28 · 벼랑은 줄어들 몫 8층을 7층 98에서 자름 — 가장 긴 몸통이 사건 칸 위 14) · 표시 체크 '내각'을 끄면 줄이지 않음 · 기관 층은 줄 값(기관 칸 주인의 줄만 · 기관 칸은 주인 띠 몸통의 기관 층) ·
      등불 연대기(첫 창)의 줄어든 줄에서 사건 칸이 제 칸 뭉치 바로 밑 */
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
        /* 마름모 가운데에서 · 내림줄 · 합류 내림줄 · 꼬리 내림((가-0) · (나-2))은 마름모 밑(위) 4.5에서 — 같은 x (명세 04 3-6) */
        const d = ds.find(p => { const pt = p.getAttribute('points').split(' ')[1].split(','); const dy = Math.abs(Number(pt[1]) - y); return Math.abs(Number(pt[0]) - 3 - x) < 0.6 && (dy < 0.6 || Math.abs(dy - 4.5) < 0.6); });
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

  /* ⑧ 직위 줄 더의 줄 높이(G7 가) — 갈대 줄: 갈대 왕국(재상 + 서기 빌림 = 2) · 갈대 후왕국(재상 = 1)이 승계로 한 줄 → 줄 값 2 ·
     모래터: 모래 서원(지도자 · 내각 없이 서기 1) · 모래 부족국(0)은 줄이 따로 */
  const raw4 = JSON.parse(fs.readFileSync(path.join(root, 'prototype/fixtures/oracle/f4-office4.json'), 'utf8'));
  const lowered = await page.evaluate(r => {
    const notes = [];
    const d = HT.F4.down(r, m => notes.push(m));
    d.f4extras = HT.F4.extrasOf(r);
    if (notes.length) d.f4notes = notes;
    return d;
  }, raw4);
  const ctx8 = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, locale: 'ko-KR' });
  await ctx8.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d)); localStorage.setItem('ht.maker.ui', JSON.stringify({})); }, lowered);
  const page8 = await ctx8.newPage();
  const errors8 = [];
  page8.on('pageerror', e => errors8.push(String(e)));
  page8.on('console', m => { if (m.type() === 'error') errors8.push(m.text()); });
  await page8.goto(base + 'dlc-maker.html');
  await page8.locator('#timeline .tl-track').first().waitFor({ timeout: 30000 });
  await page8.waitForTimeout(1200);
  await page8.evaluate(() => HT.liveTimeline.setView(280, 1020));
  await page8.waitForTimeout(900);
  const s8 = await page8.evaluate(async () => {
    const tl = HT.liveTimeline;
    const wait = () => new Promise(r => setTimeout(r, 900));
    const ids = ['o-reed', 'o-reed2', 'o-scribe', 'o-sand'];
    const find = id => {
      for (const tr of tl.tracks) {
        const p = tr.periods.find(q => q.uid === `f4-office4/${id}`);
        if (p) return { tr, p };
      }
      return null;
    };
    const rows = () => Object.fromEntries(ids.map(id => {
      const { tr, p } = find(id);
      const g = tr.geos[p._row];
      return [id, { row: p._row, rowH: g.rowH, laneH: tr.laneEls[p._row].getBoundingClientRect().height }];
    }));
    const info = {};
    for (const id of ids) {
      const { tr, p } = find(id);
      const g = tr.geos[p._row];
      const { gb, lift } = tl._bandGeo(tr, p);
      const el = tr.lanesEl.querySelector(`.tl-band[data-uid="${CSS.escape(p.uid)}"]`);
      const br = el.getBoundingClientRect();
      const cells = [...el.querySelectorAll('.tl-cell.k-office')];
      const out = (r, q) => r.top < q.top - 0.5 || r.bottom > q.bottom + 0.5 || r.left < q.left - 0.5 || r.right > q.right + 0.5;
      info[id] = {
        row: p._row, offices: g.offices, officeH: g.officeH, officeTop: g.officeTop, cabinetEnd: g.cabinetTop + g.cabinetH,
        own: tl._officeN(p), gbOfficeTop: gb.officeTop, floorEnd: gb.floorEnd, lift, bandH: br.height,
        cells: cells.length, refs: cells.map(c => c.dataset.cell), cellTops: [...new Set(cells.map(c => c.offsetTop))].sort((a, b) => a - b),
        outside: cells.filter(c => out(c.getBoundingClientRect(), br)).length,
        textOut: cells.filter(c => { const b = c.querySelector('b'); return !!b && out(b.getBoundingClientRect(), c.getBoundingClientRect()); }).length,
      };
    }
    /* 글자 겹침: 직위 줄 더 칸의 글과 같은 줄의 다른 글(칸 글 · 이름 글 · 사건 글 · 해)이 겹치지 않음 */
    let overlaps = 0;
    const samples = [];
    for (const tr of tl.tracks) {
      for (const lane of tr.laneEls) {
        const office = [...lane.querySelectorAll('.tl-cell.k-office b')];
        if (!office.length) continue;
        const all = [...lane.querySelectorAll('.tl-cell b, .tl-dyn b, .tl-tab, .tl-ev .t, .tl-ev .y')];
        for (const a0 of office) {
          const a = a0.getBoundingClientRect();
          for (const e of all) {
            if (e === a0) continue;
            const b = e.getBoundingClientRect();
            const w = Math.min(a.right, b.right) - Math.max(a.left, b.left), h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
            if (w > 0.5 && h > 0.5) {
              overlaps++;
              if (samples.length < 3) samples.push([a0.textContent, e.textContent]);
            }
          }
        }
      }
    }
    const withRows = rows();
    /* 직위 줄 더를 걷고 다시 지은 배치와 견줌(모델의 offices만 잠시 비움) */
    const saved = new Map();
    for (const p of tl._data.periods) if (p.offices) { saved.set(p, p.offices); delete p.offices; }
    tl.relayout();
    await wait();
    const withoutRows = rows();
    for (const [p, o] of saved) p.offices = o;
    tl.relayout();
    await wait();
    /* 표시 체크 '지도자'를 끄면 직위 줄 더 층도 없음 */
    tl.setShow({ leaders: false });
    await wait();
    const off = Object.fromEntries(ids.map(id => { const { tr, p } = find(id); return [id, tr.geos[p._row].officeH]; }));
    const offCells = document.querySelectorAll('#timeline .tl-cell.k-office').length;
    tl.setShow({ leaders: true });
    await wait();
    return { info, overlaps, samples, withRows, withoutRows, off, offCells };
  });
  const I = s8.info;
  const grow = id => ({ 줄: s8.withRows[id].rowH - s8.withoutRows[id].rowH, 화면: Math.round((s8.withRows[id].laneH - s8.withoutRows[id].laneH) * 10) / 10 });
  check(I['o-reed'].row === I['o-reed2'].row && I['o-reed'].offices === 2 && I['o-scribe'].offices === 1 && I['o-sand'].offices === 0, '⑧ 줄의 직위 줄 더 수 = 그 줄 띠들 가운데 큰 값(갈대 줄 2 · 모래 서원 줄 1 · 모래 부족국 줄 0)', Object.fromEntries(Object.entries(I).map(([k, v]) => [k, { 줄: v.row, 수: v.offices, 제수: v.own }])));
  check([['o-reed', 28], ['o-scribe', 14], ['o-sand', 0]].every(([id, n]) => grow(id).줄 === n && Math.abs(grow(id).화면 - n) <= 0.5), '⑧ 직위 줄 더가 있는 줄의 몸통이 n × 14만큼 높음(직위 줄 더를 걷고 다시 지은 배치와 견줌 — 자료 · 화면)', { 갈대: grow('o-reed'), 모래서원: grow('o-scribe'), 모래부족국: grow('o-sand') });
  check(I['o-reed'].officeTop === I['o-reed'].cabinetEnd && I['o-reed'].officeH === 28, '⑧ 직위 줄 더 층은 내각 다음(예속 앞)', { officeTop: I['o-reed'].officeTop, 내각끝: I['o-reed'].cabinetEnd, officeH: I['o-reed'].officeH });
  check(I['o-reed'].gbOfficeTop === I['o-reed2'].gbOfficeTop && I['o-reed'].floorEnd - I['o-reed2'].floorEnd === 14 && I['o-reed2'].lift - I['o-reed'].lift === 14 && Math.abs(I['o-reed'].bandH - I['o-reed2'].bandH - 14) <= 0.5 && I['o-reed2'].cellTops.length === 1,
    '⑧ 같은 줄의 수가 다른 두 띠(갈대 왕국 2 · 후왕국 1)가 제 층만 맞붙음 — 남는 층만큼 몸통이 짧음', { 왕국: { 층: I['o-reed'].gbOfficeTop, 끝: I['o-reed'].floorEnd, 높이: I['o-reed'].bandH }, 후왕국: { 층: I['o-reed2'].gbOfficeTop, 끝: I['o-reed2'].floorEnd, 높이: I['o-reed2'].bandH, 칸위: I['o-reed2'].cellTops } });
  check(I['o-scribe'].gbOfficeTop === 14 && I['o-scribe'].cellTops.length === 1, '⑧ 지도자 · 내각 칸이 없는 띠(모래 서원)는 직위 줄 더 층이 색줄 바로 밑', { 층: I['o-scribe'].gbOfficeTop, 칸위: I['o-scribe'].cellTops });
  check(I['o-reed'].cells === 4 && I['o-reed2'].cells === 1 && I['o-scribe'].cells === 2 && I['o-sand'].cells === 0 && I['o-reed'].refs.filter(r => r.startsWith('office:1:')).length === 2, '⑧ 직위 줄 더 칸 수(빌린 서기 줄은 출처 모래 서원의 칸 둘)', Object.fromEntries(Object.entries(I).map(([k, v]) => [k, v.refs])));
  check(s8.overlaps === 0 && Object.values(I).every(v => !v.outside && !v.textOut), '⑧ 직위 줄 더 칸의 글자 겹침 · 띠 밖 돌출 없음', { 겹침: s8.overlaps, 보기: s8.samples, 돌출: Object.fromEntries(Object.entries(I).map(([k, v]) => [k, [v.outside, v.textOut]])) });
  check(Object.values(s8.off).every(h => !h) && s8.offCells === 0, "⑧ 표시 체크 '지도자'를 끄면 직위 줄 더 층 · 칸 없음", { 층: s8.off, 칸: s8.offCells });
  const tl8 = await page8.locator('#timeline').boundingBox();
  if (tl8) await page8.screenshot({ path: path.join(output, '8-직위줄더.png'), clip: tl8 });
  check(!errors8.length, '⑧ 콘솔 오류 없음', errors8.slice(0, 5));

  /* ⑩의 사건 자리 — 등불 연대기(첫 창): 줄어든 줄(줄어드는 층이 있는 줄)의 흰 사건 칸이 그 사건이 앉은 띠의 칸 뭉치 바로 밑(띠 몸통 _bandGeo의 textTop = floorEnd) */
  const s10e = await page.evaluate(async () => {
    const tl = HT.liveTimeline;
    for (const s of tl.spheres || []) if (s.folded) tl.toggleFoldSphere(s.id, false);
    await new Promise(r => setTimeout(r, 900));
    tl.setView(-200, 1800);
    await new Promise(r => setTimeout(r, 900));
    const rows = [], evs = [];
    for (const tr of tl.tracks) {
      if (tr.folded || tr._sphereHidden) continue;
      tr.geos.forEach((g, r) => {
        if (!g.shrink || (tr.hiddenRows && tr.hiddenRows.has(r))) return;
        const bands = (tr.rowPeriods[r] || []).filter(p => !p._overlay && !p._hidden && !p._under).map(p => ({ p, b: tl._bandGeo(tr, p), el: tr.lanesEl.querySelector(`.tl-band[data-uid="${CSS.escape(p.uid)}"]`) }));
        rows.push({ track: tr.id, row: r, shrink: g.shrink, textTop: g.textTop, top: Math.max(...bands.map(x => x.b.gb.floorEnd)), lifts: bands.map(x => x.b.lift) });
        for (const ev of tr.laneEls[r].querySelectorAll(':scope > .tl-ev')) {
          const x = ev.getBoundingClientRect().left;
          const host = bands.find(q => q.el && q.el.getBoundingClientRect().left <= x && x <= q.el.getBoundingClientRect().right);
          if (host) evs.push({ track: tr.id, row: r, band: host.p.name, top: parseFloat(ev.style.top), want: host.b.gb.floorEnd });
        }
      });
    }
    return { rows, evs };
  });
  check(s10e.rows.length >= 2 && s10e.rows.every(r => r.top === r.textTop && Math.min(...r.lifts) === 0 && r.lifts.every(l => l >= 0)), '⑩ 등불 연대기: 줄어든 줄의 칸 뭉치 = 띠들 몸통의 큰 값(가장 긴 몸통의 띠는 올림 없이 줄의 사건 칸에 맞닿음)', s10e.rows);
  check(s10e.evs.length > 0 && s10e.evs.every(e => e.top === e.want), '⑩ 등불 연대기: 줄어든 줄의 사건 칸이 제 띠 칸 뭉치 바로 밑', { 사건: s10e.evs.length, 어긋남: s10e.evs.filter(e => e.top !== e.want).slice(0, 5) });

  /* ⑨ 지도자 두 단 · ⑩ 줄어드는 층 — 형식 4 시험 자료 f4-legit(다듬기 판 정통성 장면 + 곁 · 몸통 트랙)를 메이커가 파일을 열 때처럼 옛 꼴로 내려 새 창에 */
  const rawL = JSON.parse(fs.readFileSync(path.join(root, 'prototype/fixtures/oracle/f4-legit.json'), 'utf8'));
  const loweredL = await page.evaluate(r => {
    const notes = [];
    const d = HT.F4.down(r, m => notes.push(m));
    d.f4extras = HT.F4.extrasOf(r);
    if (notes.length) d.f4notes = notes;
    return d;
  }, rawL);
  const ctx9 = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, locale: 'ko-KR' });
  await ctx9.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d)); localStorage.setItem('ht.maker.ui', JSON.stringify({})); }, loweredL);
  const page9 = await ctx9.newPage();
  const errors9 = [];
  page9.on('pageerror', e => errors9.push(String(e)));
  page9.on('console', m => { if (m.type() === 'error') errors9.push(m.text()); });
  await page9.goto(base + 'dlc-maker.html');
  await page9.locator('#timeline .tl-track').first().waitFor({ timeout: 30000 });
  await page9.waitForTimeout(1200);
  const s9 = await page9.evaluate(async () => {
    const tl = HT.liveTimeline;
    const wait = () => new Promise(r => setTimeout(r, 900));
    for (const s of tl.spheres || []) if (s.folded) tl.toggleFoldSphere(s.id, false);
    await wait();
    tl.setView(985, 1235);
    await wait();
    const BW = tl._G().bw;
    const find = id => {
      for (const tr of tl.tracks) {
        const p = tr.periods.find(q => q.uid === `f4-legit/${id}`);
        if (p) return { tr, p };
      }
      return null;
    };
    const out = (r, q) => r.top < q.top - 0.5 || r.bottom > q.bottom + 0.5 || r.left < q.left - 0.5 || r.right > q.right + 0.5;
    /* 그 띠의 줄이 보이게 tl-body를 옮김 — 문화권을 펼치면 펼친 문화권이 보이게 아래로 밀려, 화면 밖 트랙의 띠는 그려지지 않으므로(몸통 줄이 늘면 첫 트랙이 밖으로) */
    const into = async (tr, p) => {
      const lane = tr.laneEls[p._row], body = tr.lanesEl.closest('.tl-body');
      const r = lane.getBoundingClientRect(), b = body.getBoundingClientRect();
      if (r.top >= b.top && r.bottom <= b.bottom) return;
      body.scrollTop += r.top - b.top - 40;
      await wait();
    };
    const info = {};
    for (const id of ['o-hayeon', 'o-empire', 'o-ford', 'o-willow', 'o-pebble', 'o-wheel', 'o-dure', 'o-dure2', 'o-gull', 'o-gull2']) {
      const { tr, p } = find(id);
      await into(tr, p);
      const g = tr.geos[p._row];
      const { gb, lift } = tl._bandGeo(tr, p);
      const el = tr.lanesEl.querySelector(`.tl-band[data-uid="${CSS.escape(p.uid)}"]`);
      const br = el.getBoundingClientRect();
      const ll = tl._leaderLanes(p);
      const cells = [...el.querySelectorAll('.tl-cell.k-leader')].map(c => {
        const i = Number(c.dataset.cell.split(':')[1]);
        const top = parseFloat(c.style.top);
        return { i, ref: c.dataset.cell, lane: Math.round((top - (gb.leaderTop - BW)) / 14), want: Math.min(ll.n - 1, ll.lane[i] || 0), h: c.getBoundingClientRect().height, outside: out(c.getBoundingClientRect(), br), textOut: (() => { const b = c.querySelector('b'); return !!b && out(b.getBoundingClientRect(), c.getBoundingClientRect()); })() };
      });
      info[id] = {
        name: p.name, row: p._row, rowLeaderH: g.leaderH, rowTiers: g.leaderTiers, tiers: gb.leaderTiers, n: ll.n, over: ll.over, leaderTop: gb.leaderTop, cabinetTop: gb.cabinetTop, cabinetH: g.cabinetH,
        floorEnd: gb.floorEnd, lift, bandH: br.height, cells: cells.length, laneCounts: [0, 1, 2, 3].map(k => cells.filter(c => c.lane === k).length),
        lane1: cells.filter(c => c.lane === 1).map(c => c.ref), wrongLane: cells.filter(c => c.lane !== c.want).map(c => c.ref), tops: [...new Set(cells.map(c => c.lane))].sort(),
        heights: [...new Set(cells.map(c => Math.round(c.h)))], outside: cells.filter(c => c.outside).length, textOut: cells.filter(c => c.textOut).length,
      };
    }
    /* 이름 글자 겹침: 두 단 띠의 지도자 칸 글과 같은 줄의 다른 글(칸 글 · 이름 글 · 사건 글 · 해) — 다섯 겹 공동(물레)의 마지막 단에 넘친 칸끼리는 계약대로 겹치므로 뺌 */
    let overlaps = 0;
    const samples = [];
    for (const id of ['o-hayeon', 'o-empire', 'o-wheel', 'o-dure', 'o-gull']) {
      const { tr, p } = find(id);
      await into(tr, p);
      const ll = tl._leaderLanes(p);
      const lane = tr.laneEls[p._row];
      const band = lane.querySelector(`.tl-band[data-uid="${CSS.escape(p.uid)}"]`);
      const mine = [...band.querySelectorAll('.tl-cell.k-leader b')];
      const all = [...lane.querySelectorAll('.tl-cell b, .tl-dyn b, .tl-tab, .tl-ev .t, .tl-ev .y')];
      const laneOf = e => { const c = e.closest('.tl-cell.k-leader'); return c && c.closest('.tl-band') === band ? Math.min(ll.n - 1, ll.lane[Number(c.dataset.cell.split(':')[1])] || 0) : -1; };
      for (const a0 of mine) {
        const a = a0.getBoundingClientRect();
        for (const e of all) {
          if (e === a0) continue;
          if (ll.over && laneOf(a0) === ll.n - 1 && laneOf(e) === ll.n - 1) continue;
          const b = e.getBoundingClientRect();
          const w = Math.min(a.right, b.right) - Math.max(a.left, b.left), h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
          if (w > 0.5 && h > 0.5) {
            overlaps++;
            if (samples.length < 3) samples.push([a0.textContent, e.textContent]);
          }
        }
      }
    }
    return { info, overlaps, samples };
  });
  const L = s9.info;
  check(['o-hayeon', 'o-empire'].every(id => L[id].rowLeaderH === 28 && L[id].rowTiers === 2 && L[id].tiers === 2 && L[id].tops.join() === '0,1' && L[id].heights.join() === '14'),
    '⑨ 하연 왕국 · 설원 제국의 지도자 층이 28(두 단 · 칸 높이 14)', Object.fromEntries(['o-hayeon', 'o-empire'].map(id => [L[id].name, { 줄층: L[id].rowLeaderH, 단: L[id].tiers, 칸단: L[id].tops, 높이: L[id].heights }])));
  check(L['o-hayeon'].lane1.join() === 'leader:2' && L['o-empire'].lane1.join() === 'leader:6' && Object.values(L).every(v => !v.wrongLane.length),
    '⑨ 두 단 칸 수 · 자리: 하연 아래 단 = 다빈왕(공동) 하나 · 설원 아래 단 = 물안개 공(주장) 하나 · 모든 칸이 제 단(_leaderLanes) 자리', Object.fromEntries(Object.values(L).map(v => [v.name, { 단마다: v.laneCounts, 아래단: v.lane1, 어긋남: v.wrongLane }])));
  check(L['o-dure2'].row === L['o-dure'].row && L['o-dure'].rowTiers === 2 && L['o-dure2'].tiers === 1 && L['o-dure'].floorEnd - L['o-dure2'].floorEnd === 14 && L['o-dure2'].lift - L['o-dure'].lift === 14 && Math.abs(L['o-dure'].bandH - L['o-dure2'].bandH - 14) <= 0.5 &&
    L['o-gull2'].row === L['o-gull'].row && L['o-gull2'].tiers === 1 && L['o-gull2'].cabinetTop === L['o-gull2'].leaderTop + 14,
    '⑨ 같은 줄의 한 단 띠는 제 14만 맞붙음(두레 뒤나라 — 몸통 14 짧음 · 갈매 후왕국 — 내각 층이 제 지도자 한 단 바로 밑)', { 두레앞: [L['o-dure'].floorEnd, L['o-dure'].lift, L['o-dure'].bandH], 두레뒤: [L['o-dure2'].floorEnd, L['o-dure2'].lift, L['o-dure2'].bandH], 갈매후: { 지도자: L['o-gull2'].leaderTop, 내각: L['o-gull2'].cabinetTop } });
  check(['o-ford', 'o-willow', 'o-pebble'].every(id => L[id].rowLeaderH === 14 && L[id].tiers === 1 && L[id].tops.join() === '0'),
    '⑨ 섭정 · 명목만 있는 띠(여울) · 정통성 없이 겹친 띠(버들) · 주장이 맞닿기만 한 띠(자갈)는 지도자 층 14', Object.fromEntries(['o-ford', 'o-willow', 'o-pebble'].map(id => [L[id].name, L[id].rowLeaderH])));
  check(L['o-wheel'].rowTiers === 4 && L['o-wheel'].rowLeaderH === 56 && L['o-wheel'].tops.join() === '0,1,2,3' && L['o-wheel'].over === 1, '⑨ 다섯 겹 공동(물레)은 4단까지(넘친 칸 하나는 마지막 단)', { 단: L['o-wheel'].rowTiers, 층: L['o-wheel'].rowLeaderH, 칸단: L['o-wheel'].laneCounts, 넘침: L['o-wheel'].over });
  check(s9.overlaps === 0 && Object.values(L).every(v => !v.outside && !v.textOut), '⑨ 지도자 칸의 이름 글자 겹침 · 띠 밖 돌출 없음', { 겹침: s9.overlaps, 보기: s9.samples, 돌출: Object.fromEntries(Object.values(L).map(v => [v.name, [v.outside, v.textOut]])) });
  for (const id of ['seolryeong', 'gyeot', 'momtong']) {
    const box = await page9.locator(`#timeline .tl-track[data-track="${id}"]`).boundingBox();
    if (box) {
      await page9.locator(`#timeline .tl-track[data-track="${id}"]`).scrollIntoViewIfNeeded();
      await page9.waitForTimeout(300);
      const b2 = await page9.locator(`#timeline .tl-track[data-track="${id}"]`).boundingBox();
      if (b2) await page9.screenshot({ path: path.join(output, `9-정통성두단-${id}.png`), clip: { x: b2.x, y: Math.max(0, b2.y), width: b2.width, height: Math.min(b2.height, 1080 - Math.max(0, b2.y)) } });
    }
  }

  /* ⑩ 줄어드는 층 — 몸통 트랙: 갈매 줄(두 단 + 내각) · 나루터 줄(기관이 한 띠에만) · 솔 줄(지위 변천 + 내각 + 직위 줄 더)은 14 줄고, 모래톱 줄(한 띠가 모든 층)은 그대로.
     산호 줄(시기 둘 / 내각 + 직위 줄 더 둘)은 28 · 벼랑 줄(네 겹 공동 / 시기 셋 + 기관 + 식민 예속 / 내각 + 직위 줄 더 셋 — 띠마다 8층 이상 모자람)은 7층(98)에서 자름.
     서고 미리보기는 사슬이 없어 지위도 센다 — 솔 줄은 14 줄지만 내보내기(새 앱 — 지위는 흰 사슬)의 줄 비트 28 ~ 30은 0(계약 1-1 덧붙임 '줄어드는 층의 셈') */
  const s10 = await page9.evaluate(async () => {
    const tl = HT.liveTimeline;
    const wait = () => new Promise(r => setTimeout(r, 900));
    const ids = ['o-gull', 'o-quay', 'o-shoal', 'o-pine', 'o-reef', 'o-cliff'];
    const find = id => {
      for (const tr of tl.tracks) {
        const p = tr.periods.find(q => q.uid === `f4-legit/${id}`);
        if (p) return { tr, p };
      }
      return null;
    };
    const rows = () => Object.fromEntries(ids.map(id => {
      const { tr, p } = find(id);
      const g = tr.geos[p._row];
      const bands = (tr.rowPeriods[p._row] || []).filter(q => !q._overlay && !q._hidden).map(q => tl._bandGeo(tr, q));
      return [id, { row: p._row, shrink: g.shrink, rowH: g.rowH, textTop: g.textTop, unionEnd: g.unionEnd, laneH: tr.laneEls[p._row].getBoundingClientRect().height, top: Math.max(...bands.map(b => b.gb.floorEnd)), lifts: bands.map(b => b.lift), organH: g.organH }];
    }));
    const withRows = rows();
    /* 줄어드는 층을 0으로 둔 배치와 견줌(띠마다 뺀 층 up을 잠시 0으로 — 줄어드는 몫 = 그 가운데 작은 값) */
    const own = tl._bandGeo;
    tl._bandGeo = function (tr, p) { return Object.assign({}, own.call(this, tr, p), { up: 0 }); };
    tl.relayout();
    await wait();
    const flat = rows();
    delete tl._bandGeo;
    tl.relayout();
    await wait();
    /* 표시 체크 '내각'을 끄면 줄이지 않음(그 줄에 자료로 있는 층을 보기가 빼므로) */
    tl.setShow({ cabinets: false });
    await wait();
    const noCab = rows();
    tl.setShow({ cabinets: true });
    await wait();
    /* 기관 층은 줄 값: 나루터 세관(기관)이 얹힌 나루터 후국의 줄만 층이 있고, 기관 칸은 주인 띠 몸통의 기관 층(그 띠가 갖지 않은 내각 층을 빼고 맞붙인 자리) */
    const { tr: qt, p: q2 } = find('o-quay2');
    { // 기관 칸이 그려지게 나루터 줄을 화면 안으로(⑨의 into와 같은 까닭)
      const lane = qt.laneEls[q2._row], body = qt.lanesEl.closest('.tl-body');
      const r = lane.getBoundingClientRect(), b = body.getBoundingClientRect();
      if (r.top < b.top || r.bottom > b.bottom) { body.scrollTop += r.top - b.top - 40; await wait(); }
    }
    const org = qt.lanesEl.querySelector(`.tl-org.is-agency[data-band="${CSS.escape(q2.uid)}"]`);
    const organ = { top: org ? parseFloat(org.style.top) : null, want: tl._bandGeo(qt, q2).gb.organTop, rows: qt.geos.map(g => g.organH) };
    return { withRows, flat, noCab, organ };
  });
  const W10 = s10.withRows, F10 = s10.flat;
  const ids10 = () => Object.keys(W10);
  const uncut10 = () => ids10().filter(id => id !== 'o-cliff');
  check(['o-gull', 'o-quay', 'o-pine'].every(id => W10[id].shrink === 14) && W10['o-shoal'].shrink === 0 && W10['o-reef'].shrink === 28 && uncut10().every(id => W10[id].top === W10[id].textTop && W10[id].textTop === W10[id].unionEnd - W10[id].shrink && Math.min(...W10[id].lifts) === 0),
    '⑩ 짧은 몸통 줄의 칸 뭉치 = 띠들 몸통의 큰 값(갈매 · 나루터 · 솔 14 줄음 · 산호 28 줄음 · 모래톱 그대로)', Object.fromEntries(ids10().map(id => [id, { 줄음: W10[id].shrink, 뭉치끝: W10[id].top, 사건칸: W10[id].textTop, 올림: W10[id].lifts }])));
  check(W10['o-cliff'].shrink === 98 && W10['o-cliff'].textTop === W10['o-cliff'].unionEnd - 98 && W10['o-cliff'].top === W10['o-cliff'].textTop - 14 && Math.min(...W10['o-cliff'].lifts) === 14,
    '⑩ 벼랑 줄: 줄어들 몫이 8층이어도 7층(98)에서 자름 — 가장 긴 몸통의 띠도 사건 칸 위 14(덜 줄어 안전)', { 줄음: W10['o-cliff'].shrink, 뭉치끝: W10['o-cliff'].top, 사건칸: W10['o-cliff'].textTop, 층끝: W10['o-cliff'].unionEnd, 올림: W10['o-cliff'].lifts });
  check(ids10().every(id => F10[id].shrink === 0 && F10[id].rowH - W10[id].rowH === W10[id].shrink && Math.abs(F10[id].laneH - W10[id].laneH - W10[id].shrink) <= 0.5),
    '⑩ 줄어드는 층을 0으로 둔 배치와 견줌 — 줄 높이가 줄어든 몫만큼 낮음(자료 · 화면)', Object.fromEntries(ids10().map(id => [id, { 줄: F10[id].rowH - W10[id].rowH, 화면: Math.round((F10[id].laneH - W10[id].laneH) * 10) / 10 }])));
  check(ids10().every(id => s10.noCab[id].shrink === 0), "⑩ 표시 체크 '내각'을 끄면 줄이지 않음", Object.fromEntries(ids10().map(id => [id, s10.noCab[id].shrink])));
  check(s10.organ.top === s10.organ.want && W10['o-quay'].organH === 14 && W10['o-cliff'].organH === 14 && s10.organ.rows.filter(h => h).length === 2, '⑩ 기관 층은 줄 값(기관 칸 주인이 있는 나루터 · 벼랑 줄만) · 기관 칸은 주인 띠 몸통의 기관 층', s10.organ);
  check(!errors9.length, '⑨ ⑩ 콘솔 오류 없음', errors9.slice(0, 5));
} finally {
  await browser.close();
  server.close();
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
  console.log(`${report.오류.length ? '문제 ' + report.오류.length : '모두 통과'} · ${report.검사.length}건 · ${output}`);
  for (const e of report.오류) console.log('  ✗ ' + e);
}

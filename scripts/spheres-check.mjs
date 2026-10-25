/* 문화권 사전(spheres)을 실제 브라우저의 메이커에서 확인합니다.
   node scripts/spheres-check.mjs <검사할 폴더> <결과 폴더>   (크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT로 — 다른 브라우저 검사와 같게)
   가상 작업본(안개 섬 · 재 줄 트랙 둘, 문화권 '안개 바다권' 하나)을 독립 브라우저의 저장소에만 넣고:
   ① 넣기 메뉴 → 문화권 → 편집 표(그리드)에 문화권 줄 · 열  ② 바탕 창 「문화권」 탭(트랙 다음) · 기본 문화권 가져오기 후보 · ＋ 추가 → 이름 적기 → 작업본에 실림
   ③ 바탕 창 「트랙」 탭의 문화권 고르기 칸에 이 DLC의 문화권이 있고 고르면 작업본에 실림  ④ 파일로 낼 때 spheres · 형식 버전 3  ⑤ 1배 그림 · 콘솔 오류 없음 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/문화권-검사');
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
const draft = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'smoke-world', name: '검사 세계', version: '1.0.0',
  spheres: [{ id: 'mist-sea', name: '안개 바다권', description: '가상 세계' }],
  tracks: [{ id: 'fog-isles', name: '안개 섬', color: '#88aacc', sphere: 'mist-sea' }, { id: 'ash-row', name: '재 줄', color: '#ccaa88' }],
  periods: [{ id: 'p1', track: 'fog-isles', name: '안개국', start: 100, end: 300 }, { id: 'p2', track: 'ash-row', name: '재국', start: 100, end: 300 }],
};
await context.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d)); localStorage.setItem('ht.maker.refs', JSON.stringify({ [d.id]: [{ id: 'east-asia-base', show: true, locked: true }] })); localStorage.setItem('ht.maker.ui', JSON.stringify({})); }, draft); // 기본팩을 불러온 팩으로 — 그 문화권(동아시아)이 가져오기 · 고르기 칸에 보이게
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
try {
  await page.goto(base + 'dlc-maker.html');
  await page.locator('#mkMenus [data-menu="insert"]').waitFor({ timeout: 20000 });
  await page.waitForTimeout(800);
  const stored = () => page.evaluate(() => JSON.parse(localStorage.getItem('ht.maker.draft') || 'null'));
  const fmt = await page.evaluate(() => { const d = JSON.parse(localStorage.getItem('ht.maker.draft')); const r = HT.normalizePack(d); return { warnings: r.warnings.map(w => w.msg), spheres: r.pack.spheres, isSphere: HT.isSphere('mist-sea'), order: HT.sphereOf('mist-sea').order }; });
  check(fmt.spheres && fmt.spheres.length === 1 && fmt.isSphere && fmt.order === 1000 && !fmt.warnings.length, '① 작업본의 문화권을 읽고 모델의 사전에 듦(차례 1000 · 경고 없음)', fmt);

  /* ① 넣기 메뉴 → 문화권 → 편집 표 */
  await page.locator('#mkMenus [data-menu="insert"]').click();
  await page.waitForTimeout(200);
  const items = await page.evaluate(() => [...document.querySelectorAll('#ctxMenu .ctx-label')].map(c => c.textContent.trim()));
  check(items.includes('문화권') && items.indexOf('문화권') === items.indexOf('트랙') + 1, '① 넣기 메뉴에 문화권이 트랙 다음에', items.filter(t => /트랙|문화권|분류/.test(t)));
  await page.locator('#ctxMenu').getByText('문화권', { exact: true }).click();
  await page.waitForTimeout(400);
  const grid = await page.evaluate(() => ({ status: (document.querySelector('[data-grid-status]') || {}).textContent, head: [...document.querySelectorAll('.mk-grid-head [role="columnheader"], .mk-grid-head > *')].map(h => h.textContent.trim()), rows: [...document.querySelectorAll('.mk-grid-rows [role="row"]')].map(r => r.textContent.replace(/\s+/g, ' ').trim()) }));
  check(/문화권 1줄/.test(grid.status || '') && grid.head.join('|').includes('id') && grid.head.join('|').includes('순서') && grid.rows.some(r => r.includes('안개 바다권')), '① 편집 표가 문화권 1줄 · 열(id · 이름 · 순서 · 설명 · 쓰는 곳)', grid);
  await page.screenshot({ path: path.join(output, '1-편집표-문화권.png') });

  /* ② 바탕 창 「문화권」 탭 */
  await page.locator('[data-grid-base-tools]').click();
  await page.waitForTimeout(400);
  const tabs = await page.evaluate(() => [...document.querySelectorAll('#mkBaseTabs [data-base-tab]')].map(b => ({ k: b.dataset.baseTab, on: b.getAttribute('aria-selected') === 'true', text: b.textContent.trim() })));
  check(tabs[0]?.k === 'tracks' && tabs[1]?.k === 'spheres' && tabs[1].on && tabs[1].text.startsWith('문화권'), '② 바탕 창의 탭 차례(트랙 → 문화권)와 문화권 탭이 열림', tabs.map(t => t.k));
  const imp = await page.evaluate(() => [...document.querySelectorAll('#mkBaseBody .mk-import li')].map(li => li.textContent.replace(/\s+/g, ' ').trim()));
  check(imp.length === 1 && imp[0].includes('동아시아') && imp[0].includes('east-asia') && imp[0].includes('동아시아사 기본팩'), '② 가져오기 후보는 기본팩의 동아시아 하나뿐(프로그램에 든 문화권 없음)', imp);
  await page.locator('#mkBaseBody [data-act="add"]').click();
  await page.waitForTimeout(300);
  const rowCount = await page.locator('#mkBaseBody table[data-list="spheres"] tr[data-i]').count();
  check(rowCount === 2, '② ＋ 문화권 추가로 줄이 하나 더', rowCount);
  const newRow = page.locator('#mkBaseBody table[data-list="spheres"] tr[data-i="1"]');
  const newId = await newRow.locator('input[name="id"]').inputValue();
  await newRow.locator('input[name="name"]').fill('재 들판권');
  await newRow.locator('input[name="order"]').fill('150');
  await newRow.locator('input[name="order"]').press('Tab');
  await page.waitForTimeout(900);
  let d = await stored();
  check(d.spheres.length === 2 && d.spheres[1].id === newId && d.spheres[1].name === '재 들판권' && d.spheres[1].order === 150, '② 적은 이름 · 순서가 작업본에 실림', d.spheres);
  await page.screenshot({ path: path.join(output, '2-바탕창-문화권.png') });

  /* ③ 바탕 창 「트랙」 탭의 문화권 고르기 칸 */
  await page.locator('#mkBaseTabs [data-base-tab="tracks"]').click();
  await page.waitForTimeout(400);
  const sel = page.locator('#mkBaseBody table[data-list="tracks"] tr[data-i="1"] select[name="sphere"]');
  const opts = await sel.evaluate(s => [...s.options].map(o => ({ v: o.value, t: o.textContent, hint: o.title })));
  check(opts[0].v === '' && opts[0].t === '없음' && opts.some(o => o.v === 'mist-sea' && o.t === '안개 바다권') && opts.some(o => o.v === newId && o.t === '재 들판권' && o.hint === '이 DLC의 문화권') && opts.some(o => o.v === 'east-asia' && o.t === '동아시아') && !opts.some(o => o.v === 'oceania'), '③ 트랙의 문화권 고르기 칸에 없음 + 기본팩의 동아시아 + 이 DLC의 문화권(프로그램의 것 없음)', opts);
  await sel.selectOption(newId);
  await page.waitForTimeout(900);
  d = await stored();
  check(d.tracks[1].sphere === newId, '③ 고른 문화권이 트랙에 실림', d.tracks.map(t => t.sphere));
  await page.screenshot({ path: path.join(output, '3-바탕창-트랙.png') });
  const trackOrder = await page.evaluate(() => { const d = JSON.parse(localStorage.getItem('ht.maker.draft')); const m = HT.buildModel([HT.normalizePack(d).pack]); return { tracks: m.tracks.map(t => `${t.id}:${t.sphere}`), spheres: m.spheres.filter(s => s.packId).map(s => `${s.id}@${s.order}`) }; });
  check(trackOrder.tracks.join() === 'ash-row:' + newId + ',fog-isles:mist-sea', '③ 모델의 트랙 차례가 문화권 차례(150 → 1000)', trackOrder);

  /* ④ 파일로 */
  const file = await page.evaluate(() => { const d = JSON.parse(localStorage.getItem('ht.maker.draft')); const r = HT.normalizePack(d); return { v: HT.packToJSON(r.pack).formatVersion, spheres: HT.packToJSON(r.pack).spheres, warnings: r.warnings.map(w => w.msg) }; });
  check(file.v === 3 && file.spheres.length === 2 && !file.warnings.length, '④ 파일로 낼 때 spheres 둘 · 형식 버전 3 · 경고 없음', file);

  /* ⑤ 지우기 — 쓰는 곳이 있는 줄 */
  await page.locator('#mkBaseTabs [data-base-tab="spheres"]').click();
  await page.waitForTimeout(300);
  const uses = await page.evaluate(() => [...document.querySelectorAll('#mkBaseBody table[data-list="spheres"] tr[data-i] .mk-use')].map(td => td.textContent.trim()));
  check(uses.length === 2 && uses.every(u => u && u !== '—'), '⑤ 문화권마다 쓰는 곳(트랙 1)', uses);
} catch (e) {
  report.오류.push(String(e && e.stack || e));
}
report.콘솔오류 = errors;
if (errors.length) report.오류.push(`콘솔 오류 ${errors.length}건`);
fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
await browser.close();
server.close();
console.log(report.검사.map(c => `${c.결과 ? '○' : '✗'} ${c.검사}`).join('\n'));
console.log(report.오류.length ? `오류 ${report.오류.length}건:\n${report.오류.join('\n')}` : '오류 없음');
process.exit(report.오류.length ? 1 : 0);

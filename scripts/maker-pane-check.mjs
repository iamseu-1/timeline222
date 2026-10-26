/* D3: 떼어 낸 편집 창의 쌓임, 붙은 속성 칸, 860px 경계를 실제 브라우저에서 확인합니다.
   node scripts/maker-pane-check.mjs <작업 폴더> <새 결과 폴더> */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.');
const output = path.resolve(process.argv[3]);
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const report = { 화면: '1920×1080 · 100% · 1배 / 경계 860·861px', 검사: [], 오류: [] };
const check = (ok, 검사, 근거) => report.검사.push({ 검사, 통과: !!ok, 근거 });
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent((req.url || '/').split('?')[0]).replace(/^\/+/, '') || 'dlc-maker.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js') bytes = Buffer.from(bytes.toString().replace('if (maker) maker.start();', 'if (maker) maker.start(); window.__maker = maker;'));
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2' };
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
  await context.addInitScript(() => {
    localStorage.setItem('ht.maker.draft', JSON.stringify({ format: 'history-timeline-dlc', formatVersion: 2, id: 'pane-check', name: '가상 편집 창 검사', version: '1.0.0', tracks: [{ id: 'sea', name: '바다 땅' }], periods: [{ id: 'haeon', track: 'sea', name: '해온국', start: 520, end: 700, leaders: [{ name: '솔빛', start: 520, end: 560 }] }], events: [] }));
  });
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/dlc-maker.html`);
  await page.waitForFunction(() => window.__maker && document.querySelector('#mkStart').hidden);
  await page.evaluate(() => HT.viewer.openEditor('pane-check/haeon'));
  await page.locator('#editPane').waitFor({ state: 'visible' });
  const drag = async (selector, x, y) => {
    const b = await page.locator(selector).boundingBox();
    await page.mouse.move(b.x + 28, b.y + 14);
    await page.mouse.down();
    await page.mouse.move(x, y, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(200);
  };
  const topAt = (x, y) => page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.closest('#editPane, #mkBaseWin, #mkRight')?.id, [x, y]);
  await drag('#editPane [data-pane-drag]', 600, 160);
  const ep = await page.locator('#editPane').boundingBox();
  check(await topAt(ep.x + 30, ep.y + 80) === 'editPane', '떼어 낸 편집 창이 연표 위에 그려지고 눌림', ep);
  await page.evaluate(() => { HT.viewer.openDetail('pane-check/haeon'); __maker.openBase('tracks', -1, true); });
  await drag('#mkBaseWin [data-win-drag]', 1480, 200);
  // 편집 창을 맨 앞으로 올려도 붙은 속성 칸은 함께 올라오지 않아야 합니다.
  await page.locator('#editPane [data-pane-drag]').click({ position: { x: 30, y: 15 } });
  const base = await page.locator('#mkBaseWin').boundingBox();
  const hit = await topAt(1800, base.y + 100);
  check(hit === 'mkBaseWin', '붙은 속성 칸이 다른 떠 있는 창을 덮지 않음', { hit, base });
  await page.screenshot({ path: path.join(output, '떠있는-편집창-1920-1배.png') });
  for (const width of [860, 861, 1920]) {
    await page.setViewportSize({ width, height: 1080 });
    await page.waitForTimeout(250);
    await page.evaluate(() => __maker.openBase('tracks', -1, true));
    const b = await page.locator('#mkBaseWin').boundingBox();
    const baseHit = await topAt(Math.min(width - 20, b.x + 40), b.y + 30);
    check(baseHit === 'mkBaseWin', `${width}px: 나중에 연 바탕 자료 창이 맨 위`, { baseHit, b });
    await page.locator('#mkBaseWin [data-win-close]').focus();
    await page.keyboard.press('Escape');
    const p = await page.locator('#editPane').boundingBox();
    check(await topAt(p.x + 30, p.y + 60) === 'editPane', `${width}px: 바탕 자료를 닫으면 편집 창이 보임`, p);
    await page.screenshot({ path: path.join(output, `편집창-경계-${width}-1배.png`) });
  }
  await page.locator('#editPane [data-pane="dock"]').click();
  check(await page.evaluate(() => document.querySelector('#editPane').parentElement.id === 'mkRight' && document.querySelector('#editPane').classList.contains('is-docked')), '다시 붙이면 오른쪽 창의 원래 자리로 돌아감');
  check(report.오류.length === 0, '브라우저 오류 0건', report.오류);
  assert.equal(report.검사.filter(x => !x.통과).length, 0, JSON.stringify(report.검사.filter(x => !x.통과)));
  console.log(`maker-pane-check: ${report.검사.length}개 통과`);
} finally {
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2) + '\n');
  await browser.close(); server.close();
}

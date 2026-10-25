/* 메이커 미리보기 연표를 실제 브라우저로 찍습니다(1920×1080 · 100% — 감독 화면 1배).
   node scripts/maker-shoot.mjs <검사할 폴더> <결과 폴더> [--tag=이름] [--draft=samples/sample-lantern.json] [--from=<해> --to=<해>] [--fold-spheres=none|default] [--click=<CSS 선택자>,…]
   --click: 찍기 전에 차례로 누를 것(쉼표로 여럿 — 표 탭 · 폼 열기 등 · 하나마다 0.5초 기다림). 리메이크 5단계 과제 0 — 형식 4 작업본(--draft=prototype/fixtures/f4/<파일>)의 폼 · 표 · 미리보기를 찍을 때.
   크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT(그 package.json)로 — 다른 브라우저 검사와 같게.
   작업본(기본: 등불 연대기 견본)을 독립 브라우저의 저장소에만 넣고 메이커를 띄워, 미리보기 연표를 지정한 해 범위로 맞춘 뒤 화면 전체와 연표 부분을 찍습니다.
   감독 자료(%APPDATA% · 브라우저 저장소)는 건드리지 않습니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const m = a.match(/^--([^=]+)=?(.*)$/); return [m[1], m[2] === '' ? true : m[2]]; }));
const plain = process.argv.slice(2).filter(a => !a.startsWith('--'));
const root = path.resolve(plain[0] || '.'), output = path.resolve(plain[1] || '배포/메이커-찍기');
const tag = args.tag || '미리보기';
const draftFile = path.resolve(root, args.draft || 'samples/sample-lantern.json');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });

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
const draft = JSON.parse(fs.readFileSync(draftFile, 'utf8'));
const ui = {};
await context.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d.draft)); localStorage.setItem('ht.maker.ui', JSON.stringify(d.ui)); }, { draft, ui });
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
try {
  await page.goto(base + 'dlc-maker.html');
  await page.locator('#timeline .tl-track').first().waitFor({ timeout: 30000 });
  await page.waitForTimeout(1200);
  if (args.from && args.to) {
    await page.evaluate(([a, b]) => { const tl = HT.liveTimeline; if (tl) tl.setView(Number(a), Number(b)); }, [args.from, args.to]);
    await page.waitForTimeout(900);
  }
  if (args.click) {
    for (const sel of String(args.click).split(',').map(s => s.trim()).filter(Boolean)) {
      await page.locator(sel).first().click({ timeout: 10000 });
      await page.waitForTimeout(500);
    }
  }
  const info = await page.evaluate(() => {
    const tl = HT.liveTimeline || null;
    const tracks = [...document.querySelectorAll('#timeline .tl-track')].map(t => ({ id: t.dataset.track, h: t.getBoundingClientRect().height, folded: t.classList.contains('is-folded') }));
    const spheres = [...document.querySelectorAll('#timeline .tl-sphere')].map(t => ({ id: t.dataset.sphere, h: t.getBoundingClientRect().height, folded: t.classList.contains('is-folded') }));
    return { view: tl && tl.view, tracks, spheres, gutter: tl && tl.gutter };
  });
  await page.screenshot({ path: path.join(output, `${tag}-화면.png`) });
  const tlBox = await page.locator('#timeline').boundingBox();
  if (tlBox) await page.screenshot({ path: path.join(output, `${tag}-연표.png`), clip: tlBox });
  fs.writeFileSync(path.join(output, `${tag}-정보.json`), JSON.stringify({ info, errors }, null, 2));
  console.log(`찍음: ${output} · ${tag} · 트랙 ${info.tracks.length} · 문화권 단 ${info.spheres.length} · 오류 ${errors.length}`);
  if (errors.length) console.log(errors.join('\n'));
} finally {
  await browser.close();
  server.close();
}

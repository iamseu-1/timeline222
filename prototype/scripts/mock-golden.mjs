/* 목업 기준 그림 — 크롬이 그린 자바스크립트 목업 판의 갈래를 1배로 찍고 글줄 자리를 뽑는다(계획 한 벌 P1 과제 5).
   node prototype/scripts/mock-golden.mjs [<판 html>] <갈래 id,…> [<출력 폴더>]
     판 기본 = prototype/results/mock/source/board-s4.html(mock-build-board.mjs가 원본 사본 app/test/mock/source로 지은 것) · 출력 기본 = app/test/mock/goldens
     → <id>.png(1920×1080 · 배율 1 · 화면 SVG만) · <id>.text.json(화면 SVG의 글줄마다 — 그린 차례)
   글줄 하나: { s: 글(이어진 빈칸은 하나로 · 앞뒤 다듬음 — SVG처럼), x: 첫 글자의 시작 x, baseline: 바탕선 y(둘 다 화면 px),
     size · wt: 계산된 글자 크기 · 굵기, anchor: text-anchor, w: 크롬이 잰 글줄 폭(getComputedTextLength), box: 글 상자 [왼 · 위 · 오른 · 아래] }
   app/test/mock/parity_test.dart가 같은 갈래를 Dart 판으로 그려 이 그림과 글줄 자리 · 잉크를 견준다.
   기준이 엉뚱한 것을 재지 않게, 하나라도 어긋나면 종료 코드 1:
     · 판의 지문 — 판 옆의 mock-sha.txt(목업 파일마다 SHA-256 앞 12자 · 옮긴 Dart 머리말과 같은 판)와 판이 품은 스크립트가 같다
       (build.mjs가 kit · scene · render를 그대로, themes.js 뒤에 themes/<파일>을 '(function () { … })();'로 싸서 품는다)
     · 품은 글꼴이 실렸다(document.fonts) · 글줄마다 (첫 글꼴 이름, 굵기)가 품은 꼴에 그대로 있다(600을 700 꼴로 그리는 구멍)
     · 글줄마다 크롬이 실제로 쓴 글꼴(개발 도구의 CSS.getPlatformFontsForNode)이 품은 글꼴뿐이다 — 허락은 ALLOW(Dart 판이 같은 대체 줄을 흉내 내는 것)만
     · 판에 오류가 없다
   품은 글꼴의 SHA-256 앞 12자 · 브라우저 판(Edge로 대신 열었는지)을 알린다 — 앱 글꼴(assets/fonts)과 같은 파일이어야 글자 대조가 뜻이 있다.
   Playwright는 HT_PLAYWRIGHT_ROOT(그것이 있는 곳의 아무 .js)를 먼저 보고, 없을 때만 사용자 폴더(%USERPROFILE%)의 옛 codex 런타임 자리를 쓴다(지금 PC는 사용자 환경 변수 — 인수인계 3절)
   (cleartype-fixtures.mjs와 같음). */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

/* 품은 글꼴 밖으로 가도 되는 글자 → 크롬(Windows)이 시스템 대체로 고르는 글꼴. svg_lite.dart의 mockFallback이 같은 글꼴을 싣는다. */
const ALLOW = new Map([['▸', 'Cambria Math']]);

const here = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const withBoard = /\.html?$/i.test(argv[0] ?? '');
const board = withBoard ? argv[0] : path.join(here, '../results/mock/source/board-s4.html');
const [idList, outDir = path.join(here, '../app/test/mock/goldens')] = withBoard ? argv.slice(1) : argv;
if (!idList) {
  console.error('사용: mock-golden.mjs [<판 html>] <갈래 id,…> [<출력 폴더>]');
  process.exit(2);
}
const ids = idList.split(',').map(s => s.trim()).filter(Boolean);
const fail = msg => {
  console.error(msg);
  process.exit(1);
};
const sha12 = data => crypto.createHash('sha256').update(data).digest('hex').slice(0, 12);
if (!fs.existsSync(board)) fail(`판이 없습니다: ${board} — node prototype/scripts/mock-build-board.mjs로 먼저 지을 것`);

// 판의 지문 — 판이 품은 목업 스크립트가 mock-sha.txt의 판과 같은가
const html = fs.readFileSync(board, 'utf8');
const shaFile = path.join(path.dirname(path.resolve(board)), 'mock-sha.txt');
if (!fs.existsSync(shaFile)) fail(`판 옆에 지문 파일이 없습니다: ${shaFile}`);
const want = new Map(fs.readFileSync(shaFile, 'utf8').split(/\r?\n/).filter(Boolean).map(l => {
  const m = l.match(/^([0-9a-f]{12})\s+\*?(.+)$/);
  if (!m) fail(`지문 파일의 줄을 읽지 못했습니다: ${l}`);
  return [m[2].trim(), m[1]];
}));
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const themesAt = scripts.findIndex(s => s.includes('/* themes/'));
if (themesAt < 3) fail('판에서 목업 스크립트(kit · scene · render · themes)를 찾지 못했습니다');
const got = new Map([['kit.js', scripts[themesAt - 3]], ['scene.js', scripts[themesAt - 2]], ['render.js', scripts[themesAt - 1]]]);
const chunks = scripts[themesAt].split(/\n\/\* themes\/(\S+) \*\/\n\(function \(\) \{\n/);
got.set('themes.js', chunks[0]);
for (let i = 1; i < chunks.length; i += 2) {
  const body = chunks[i + 1].replace(/\n\}\)\(\);\n?$/, '');
  got.set(`themes/${chunks[i]}`, body);
}
const shaBad = [...new Set([...want.keys(), ...got.keys()])].filter(k => !got.has(k) || want.get(k) !== sha12(got.get(k)));
if (shaBad.length) fail(`판 지문이 mock-sha.txt와 다릅니다: ${shaBad.map(k => `${k} ${got.has(k) ? sha12(got.get(k)) : '없음'} ↔ ${want.get(k) ?? '없음'}`).join(' · ')}`);
console.log(`판 지문: mock-sha.txt와 같음(파일 ${want.size})`);

// 품은 글꼴의 지문(앱 assets/fonts와 견줄 것)
const embedded = [...html.matchAll(/@font-face\s*\{([^}]*?)src:\s*url\("data:[^;]+;base64,([A-Za-z0-9+/=]+)"\)/g)]
  .map(m => `${(m[1].match(/font-family:\s*"?([^";]+)/) || [])[1]} ${(m[1].match(/font-weight:\s*(\d+)/) || [])[1]} sha256 ${sha12(Buffer.from(m[2], 'base64'))}`);
console.log(`품은 글꼴 파일: ${embedded.join(' · ')}`);

const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || `${(process.env.USERPROFILE || os.homedir()).replace(/\\/g, '/')}/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/x.js`)('playwright');
let edge = false;
const browser = await chromium.launch().catch(() => {
  edge = true;
  return chromium.launch({ channel: 'msedge' });
});
console.log(`브라우저: ${edge ? 'msedge(내장 크로미움을 열지 못해 대신)' : 'chromium'} ${browser.version()}`);
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(pathToFileURL(path.resolve(board)).href);
await page.waitForFunction(() => document.body.dataset.ready === '1', null, { timeout: 90000 });

// 판이 품은 글꼴(@font-face)이 실렸는가 — 덜 실렸으면 크롬이 다른 글꼴로 그린 그림이 기준이 된다.
const faces = await page.evaluate(async () => {
  await document.fonts.ready;
  return [...document.fonts].map(f => ({ family: f.family.replace(/"/g, ''), weight: f.weight, status: f.status }));
});
const checks = await page.evaluate(fs => fs.map(f => [f, document.fonts.check(f)]), faces.map(f => `${f.weight} 9px "${f.family}"`));
console.log('품은 글꼴: ' + faces.map(f => `${f.family} ${f.weight} ${f.status}`).join(' · ') + ' / check ' + checks.map(([f, ok]) => `${f} ${ok}`).join(' · '));
if (!faces.length || faces.some(f => f.status !== 'loaded') || checks.some(([, ok]) => !ok)) fail('품은 글꼴이 덜 실렸습니다');
const faceKeys = new Set(faces.map(f => `${f.family}|${f.weight}`));

const cdp = await page.context().newCDPSession(page);
await cdp.send('DOM.enable');
await cdp.send('CSS.enable');
const target = path.resolve(outDir);
fs.mkdirSync(target, { recursive: true });

for (const id of ids) {
  const shown = await page.evaluate(id => {
    window.showDir(id);
    const bar = document.querySelector('#full .bar');
    if (bar) bar.style.display = 'none';
    document.getElementById('full').scrollTop = 0;
    return location.hash === '#v-' + id;
  }, id);
  if (!shown) fail(`판에 없는 갈래: ${id}`);
  await page.waitForTimeout(200);

  const lines = await page.evaluate(() => {
    const svg = document.querySelector('#full .host > svg');
    const r = svg.getBoundingClientRect();
    if (r.left !== 0 || r.top !== 0 || r.width !== 1920 || r.height !== 1080) throw new Error(`화면 SVG가 화면 0,0 · 1920×1080이 아닙니다: ${r.left},${r.top} ${r.width}×${r.height}`);
    const out = [];
    for (const t of svg.querySelectorAll('text')) {
      const s = t.textContent.replace(/\s+/g, ' ').trim();
      if (!s) continue;
      const cs = getComputedStyle(t);
      const m = t.getScreenCTM();
      const start = new DOMPoint(t.getStartPositionOfChar(0).x, t.getStartPositionOfChar(0).y).matrixTransform(m);
      const box = t.getBoundingClientRect();
      const r3 = v => +v.toFixed(3);
      out.push({
        s, x: r3(start.x), baseline: r3(start.y), size: parseFloat(cs.fontSize), wt: +cs.fontWeight, anchor: cs.textAnchor,
        w: r3(t.getComputedTextLength() * m.a), box: [box.left, box.top, box.right, box.bottom].map(r3),
        family: cs.fontFamily.split(',')[0].replace(/["']/g, '').trim(),
      });
    }
    return out;
  });
  // 글줄의 (첫 글꼴, 굵기)가 품은 꼴에 그대로 있는가 — 없으면 크롬은 가까운 꼴(600 → 700)이나 시스템 글꼴로 그린다
  const noFace = lines.filter(l => !faceKeys.has(`${l.family}|${l.wt}`));
  if (noFace.length) fail(`${id}: 품은 꼴에 없는 글꼴 · 굵기: ${[...new Set(noFace.map(l => `${l.family} ${l.wt}`))].join(' · ')}`);
  for (const l of lines) delete l.family;

  // 글줄마다 크롬이 실제로 쓴 글꼴(이름 → 글자 수) — 품은 글꼴 밖은 ALLOW의 글자 수와 꼭 맞아야 한다
  const { root } = await cdp.send('DOM.getDocument', { depth: 0 });
  const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: '#full .host > svg text' });
  const used = new Map(), away = [];
  let bad = 0;
  for (const nodeId of nodeIds) {
    const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
    for (const f of fonts) used.set(f.familyName, (used.get(f.familyName) || 0) + f.glyphCount);
    const other = fonts.filter(f => !(f.isCustomFont && /^Pretendard/.test(f.familyName)));
    if (!other.length) continue;
    const { outerHTML } = await cdp.send('DOM.getOuterHTML', { nodeId });
    const text = outerHTML.replace(/<[^>]*>/g, '').trim();
    const allowed = new Map();
    for (const ch of text) if (ALLOW.has(ch)) allowed.set(ALLOW.get(ch), (allowed.get(ALLOW.get(ch)) || 0) + 1);
    const ok = other.every(f => !f.isCustomFont && allowed.get(f.familyName) === f.glyphCount) && other.length === allowed.size;
    if (!ok) bad++;
    away.push(`${ok ? '허락' : '어긋남'} ${text} ← ${other.map(f => `${f.familyName}${f.isCustomFont ? '(품음)' : ''} ${f.glyphCount}`).join(' · ')}`);
  }

  console.log(`${id}: 글줄 ${lines.length} · 쓴 글꼴 ${[...used].map(([n, c]) => `${n} ${c}`).join(' · ')}`);
  for (const a of away) console.log(`  ${a}`);
  if (bad) fail(`${id}: 품은 글꼴 밖으로 간 글줄 ${bad} — 허락 목록(ALLOW)에 없는 대체 글꼴. 더하려면 Dart 대체 줄(svg_lite.dart mockFallback)이 같은 글꼴로 그리는지 확인한 뒤 ALLOW에 더함`);

  const png = await page.screenshot({ clip: { x: 0, y: 0, width: 1920, height: 1080 } });
  fs.writeFileSync(path.join(target, `${id}.png`), png);
  fs.writeFileSync(path.join(target, `${id}.text.json`), JSON.stringify(lines, null, 1) + '\n');
  console.log(`  → ${id}.png ${png.length}B · ${id}.text.json`);
}
await browser.close();
if (errors.length) fail(errors.join('\n'));

// ClearType 견줌의 크롬 기준(계획 한 벌 P2 과제 6): 목업 판을 크롬 1배로 열어, 기준 낱말과 같은 SVG 글줄마다
// 글 · 크기 · 굵기 · 시작 x · 바탕선 y · 글자 색 · 바탕색을 words.json에, 그 둘레(글 상자 + 3px)를 chrome-<번호>.png로 남긴다.
// 사용: node prototype/scripts/cleartype-fixtures.mjs <판 html> <갈래 id> <낱말,낱말,…> <출력 폴더>
//  Playwright는 HT_PLAYWRIGHT_ROOT(그것이 있는 곳의 아무 .js)를 먼저 보고, 없을 때만 사용자 폴더(%USERPROFILE%)의 옛 codex 런타임 자리를 쓴다(지금 PC는 사용자 환경 변수 — 인수인계 3절).
//  예: node prototype/scripts/cleartype-fixtures.mjs ".claude/research/stage2/slice4/board/s4-flag.html" s4-6-flag-open 임진왜란,조선,훈민정음,1350,서인,최씨 정권,단체 prototype/app/test/fixtures/cleartype
// 낱말 사이 이어진 빈칸은 SVG처럼 하나로 센다. 같은 낱말이 여러 번 나오면 모두 남긴다(크기 · 색이 다르다).
// 바탕색은 글자를 숨긴 같은 조각에서 가장 많은 색. 조각 안에 바탕색이 아닌 화소(띠의 선 등)가 있으면 그 수를 `others`로 적는다 —
// 견주는 검사는 글자를 숨긴 조각이 바탕색인 화소만 센다(`mask`: 행마다 비트 문자열 — 1 = 셈).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const [board, dirId, wordList, outDir] = process.argv.slice(2);
if (!board || !dirId || !wordList || !outDir) {
  console.error('사용: cleartype-fixtures.mjs <판 html> <갈래 id> <낱말,낱말,…> <출력 폴더>');
  process.exit(2);
}
const words = wordList.split(',').map(w => w.replace(/\s+/g, ' ').trim()).filter(Boolean);
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || `${(process.env.USERPROFILE || os.homedir()).replace(/\\/g, '/')}/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/x.js`)('playwright');
const browser = await chromium.launch().catch(() => chromium.launch({ channel: 'msedge' }));
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(pathToFileURL(path.resolve(board)).href);
await page.waitForFunction(() => document.body.dataset.ready === '1', null, { timeout: 90000 });
await page.evaluate(id => window.showDir(id), dirId);
await page.evaluate(() => {
  const bar = document.querySelector('#full .bar');
  if (bar) bar.style.display = 'none';
  document.getElementById('full').scrollTop = 0;
});
await page.waitForTimeout(200);

// 글줄마다의 값(화면 px — getScreenCTM으로 옮김)
const found = await page.evaluate(words => {
  const hex = rgb => '#' + rgb.match(/\d+(\.\d+)?/g).slice(0, 3).map(v => Math.round(+v).toString(16).padStart(2, '0')).join('');
  const out = [];
  document.querySelectorAll('#full text').forEach((t, index) => {
    const text = t.textContent.replace(/\s+/g, ' ').trim();
    if (!words.includes(text)) return;
    const cs = getComputedStyle(t);
    const m = t.getScreenCTM();
    const at = p => new DOMPoint(p.x, p.y).matrixTransform(m);
    const chars = [];
    for (let i = 0; i < t.getNumberOfChars(); i++) chars.push(+at(t.getStartPositionOfChar(i)).x.toFixed(3));
    const start = at(t.getStartPositionOfChar(0));
    const box = t.getBoundingClientRect();
    let alpha = +cs.fillOpacity;
    for (let e = t; e && e.nodeType === 1; e = e.parentElement) alpha *= +getComputedStyle(e).opacity;
    out.push({
      index, text, size: parseFloat(cs.fontSize), weight: +cs.fontWeight, family: cs.fontFamily.split(',')[0].replace(/"/g, '').trim(),
      x: +start.x.toFixed(3), baseline: +start.y.toFixed(3), color: hex(cs.fill), alpha, spacing: cs.letterSpacing, chars,
      box: [box.left, box.top, box.right, box.bottom],
    });
  });
  return out;
}, words);

const missing = words.filter(w => !found.some(f => f.text === w));
if (missing.length) { console.error('판에 없는 낱말: ' + missing.join(', ')); process.exit(1); }
const odd = found.filter(f => f.alpha !== 1 || f.spacing !== 'normal' || f.family !== 'Pretendard');
if (odd.length) { console.error('불투명한 프리텐다드 · 자간 없음이 아닌 글줄: ' + odd.map(f => f.text).join(', ')); process.exit(1); }

const pad = 3;
for (const f of found) {
  const x0 = Math.floor(f.box[0]) - pad, y0 = Math.floor(f.box[1]) - pad;
  f.crop = [x0, y0, Math.ceil(f.box[2]) + pad - x0, Math.ceil(f.box[3]) + pad - y0];
}
// 차례: 낱말 목록의 차례 → 판의 차례
found.sort((a, b) => words.indexOf(a.text) - words.indexOf(b.text) || a.index - b.index);

const shoot = f => page.screenshot({ clip: { x: f.crop[0], y: f.crop[1], width: f.crop[2], height: f.crop[3] } });
const withText = [];
for (const f of found) withText.push(await shoot(f));
await page.evaluate(() => document.querySelectorAll('#full text').forEach(t => { t.style.visibility = 'hidden'; }));
await page.waitForTimeout(100);
const bare = [];
for (const f of found) bare.push(await shoot(f));

// 글자를 숨긴 조각의 화소를 읽어 바탕색 · 셀 화소를 정한다(브라우저의 캔버스로 PNG를 푼다).
const reader = await browser.newPage();
const plain = await reader.evaluate(async list => {
  const out = [];
  for (const url of list) {
    const img = new Image();
    img.src = url;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = img.width;
    c.height = img.height;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    const count = new Map();
    for (let i = 0; i < d.length; i += 4) {
      const k = (d[i] << 16) | (d[i + 1] << 8) | d[i + 2];
      count.set(k, (count.get(k) || 0) + 1);
    }
    const bg = [...count.entries()].sort((a, b) => b[1] - a[1])[0][0];
    const rows = [];
    let others = 0;
    for (let y = 0; y < c.height; y++) {
      let row = '';
      for (let x = 0; x < c.width; x++) {
        const i = (y * c.width + x) * 4;
        const same = Math.abs(d[i] - (bg >> 16)) <= 2 && Math.abs(d[i + 1] - ((bg >> 8) & 255)) <= 2 && Math.abs(d[i + 2] - (bg & 255)) <= 2;
        row += same ? '1' : '0';
        if (!same) others++;
      }
      rows.push(row);
    }
    out.push({ bg: '#' + bg.toString(16).padStart(6, '0'), others, rows });
  }
  return out;
}, bare.map(b => 'data:image/png;base64,' + b.toString('base64')));
await browser.close();
if (errors.length) { console.error(errors.join('\n')); process.exit(1); }

const target = path.resolve(outDir);
fs.mkdirSync(target, { recursive: true });
const list = found.map((f, i) => {
  const n = i + 1;
  fs.writeFileSync(path.join(target, `chrome-${n}.png`), withText[i]);
  return {
    n, text: f.text, size: f.size, weight: f.weight, x: f.x, baseline: f.baseline, color: f.color, bg: plain[i].bg,
    crop: f.crop, chars: f.chars, others: plain[i].others, ...(plain[i].others ? { mask: plain[i].rows } : {}),
  };
});
const json = JSON.stringify({ board: path.basename(board), dir: dirId, words: list }, null, 1);
fs.writeFileSync(path.join(target, 'words.json'), json + '\n');
const bytes = list.reduce((sum, w) => sum + fs.statSync(path.join(target, `chrome-${w.n}.png`)).size, 0);
for (const w of list) console.log(`${w.n} ${w.text} ${w.size}px · x ${w.x} · 바탕선 ${w.baseline} · ${w.color} on ${w.bg} · 조각 ${w.crop.join('×')} · 바탕 밖 ${w.others}`);
console.log(`조각 ${list.length}개 · PNG 합 ${bytes}B → ${target}`);

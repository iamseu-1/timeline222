// 기준 덤프: 지금 연표(브라우저 · 1920×1080 · 100%)의 한 장면을 요소마다 — 자리 · 제 글자 · 브라우저가 셈한 모양 — 적어 낸다.
// css의 겹겹이 덮어쓴 규칙과 color-mix를 눈으로 풀지 않고, 브라우저가 실제로 그린 값을 숫자로 읽어 새 그리기와 대조하기 위해서다.
// 웹 연표의 코드 · 견본은 읽기만 한다(불러오는 방법은 compare-shots.mjs와 같다 — 내보내는 길에 연표 객체를 창에 걸어 둘 뿐, 파일은 고치지 않는다).
// 사용: HT_PLAYWRIGHT_ROOT=<playwright가 있는 곳의 아무 .js> node prototype/scripts/dump-dom.mjs [--scene 이름 --start 해 --end 해 --scroll px] [--out 폴더]
//       장면을 주지 않으면 비교 그림의 세 장면(전체 · 밀집-세부 · 한-나라의-100년)을 모두 뜬다. 결과: <out>/<이름>.json · <이름>.png
//       자료는 견본 등불 연대기(samples/sample-lantern.json — 실제 역사 이름이 없는 따로 세계) 하나.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(prototype, '..');
const args = process.argv.slice(2);
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null; };
const out = path.resolve(option('--out') || path.join(prototype, 'results', 'dom'));
fs.mkdirSync(out, { recursive: true });

export const SCENES = [
  { name: '전체', start: -700, end: 1750, scroll: 0 }, // 안개 시대(-620) ~ 헌정 시대
  { name: '밀집-세부', start: 900, end: 1065, scroll: 0 }, // 사건이 몰린 165년(1031년 대격변)
  { name: '한-나라의-100년', start: 300, end: 400, scroll: 0 }, // 등불 왕국의 100년
];
const scenes = option('--scene')
  ? [{ name: option('--scene'), start: Number(option('--start')), end: Number(option('--end')), scroll: Number(option('--scroll') || 0) }]
  : SCENES;
for (const s of scenes) assert.ok(Number.isFinite(s.start) && Number.isFinite(s.end) && s.end > s.start, `장면의 기간이 잘못되었습니다: ${s.name}`);

const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
const fixture = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let data = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      const marker = '/* ---------- 팩 & 모델 ---------- */', text = data.toString('utf8');
      assert.equal(text.split(marker).length, 2, 'viewer.js에서 연표 객체를 걸 자리를 찾지 못했습니다');
      data = Buffer.from(text.replace(marker, 'window.__tl=timeline;window.__state=state;\n' + marker));
    }
    res.writeHead(200, { 'Content-Type': (mime[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(data);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));

// 쪽 안에서 도는 덤프. 보이는 요소만(화면에 걸친 것 · 크기가 있는 것) 적는다.
function dumpPage() {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const hexMemo = new Map();
  const hex = color => {
    if (!color || color === 'transparent') return '#00000000';
    if (hexMemo.has(color)) return hexMemo.get(color);
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = '#000';
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
    // 반투명 색은 캔버스가 미리 곱해 되돌려 주며 어긋날 수 있어, 불투명으로 한 번 더 칠해 색을 읽고 투명도는 따로 읽는다
    let value;
    if (a === 255 || a === 0) value = '#' + [r, g, b, a].map(v => v.toString(16).padStart(2, '0')).join('');
    else {
      const m = /\/\s*([\d.]+%?)\s*\)$/.exec(color) || /rgba\([^)]*,\s*([\d.]+)\s*\)$/.exec(color);
      const alpha = m ? (m[1].endsWith('%') ? parseFloat(m[1]) / 100 : parseFloat(m[1])) : a / 255;
      const opaque = color.replace(/\/\s*[\d.]+%?\s*\)$/, ')').replace(/^rgba\(([^)]*),\s*[\d.]+\s*\)$/, 'rgb($1)');
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = opaque;
      ctx.fillRect(0, 0, 1, 1);
      const d = ctx.getImageData(0, 0, 1, 1).data;
      value = '#' + [d[0], d[1], d[2], Math.round(alpha * 255)].map(v => v.toString(16).padStart(2, '0')).join('');
    }
    hexMemo.set(color, value);
    return value;
  };
  const num = v => Math.round(parseFloat(v) * 100) / 100;
  const styleOf = (cs, isSvg) => {
    const s = {};
    if (isSvg) {
      if (cs.stroke && cs.stroke !== 'none') { s.st = hex(cs.stroke); s.sw = num(cs.strokeWidth); if (cs.strokeDasharray !== 'none') s.sd = cs.strokeDasharray; if (cs.strokeLinecap !== 'butt') s.sc = cs.strokeLinecap; }
      if (cs.fill && cs.fill !== 'none') s.fill = hex(cs.fill);
      if (cs.fillOpacity !== '1') s.fo = num(cs.fillOpacity);
      if (cs.strokeOpacity !== '1') s.so = num(cs.strokeOpacity);
    } else {
      const bg = hex(cs.backgroundColor);
      if (!bg.endsWith('00')) s.bg = bg;
      if (cs.backgroundImage !== 'none') s.bgi = cs.backgroundImage.replace(/\s+/g, ' ').slice(0, 400);
      if (cs.backgroundImage !== 'none' && cs.backgroundSize !== 'auto') s.bgs = cs.backgroundSize;
      for (const [k, side] of [['t', 'Top'], ['r', 'Right'], ['b', 'Bottom'], ['l', 'Left']]) {
        const w = num(cs[`border${side}Width`]), st = cs[`border${side}Style`];
        if (w > 0 && st !== 'none') s['b' + k] = `${w} ${st} ${hex(cs[`border${side}Color`])}`;
      }
      const radius = [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(v => v.replace(/px/g, ''));
      if (radius.some(v => v !== '0')) s.br = radius.every(v => v === radius[0]) ? radius[0] : radius.join(' ');
      if (cs.boxShadow !== 'none') s.sh = cs.boxShadow.replace(/\s+/g, ' ').slice(0, 300);
      if (cs.outlineStyle !== 'none' && num(cs.outlineWidth) > 0) s.ol = `${num(cs.outlineWidth)} ${cs.outlineStyle} ${hex(cs.outlineColor)}`;
      if (cs.maskImage && cs.maskImage !== 'none') s.mask = cs.maskImage.replace(/\s+/g, ' ').slice(0, 300);
      if (cs.writingMode !== 'horizontal-tb') s.wm = cs.writingMode;
      if (cs.textDecorationLine !== 'none') s.td = cs.textDecorationLine;
    }
    s.fg = hex(cs.color);
    s.fs = num(cs.fontSize);
    s.fw = Number(cs.fontWeight);
    if (cs.fontStyle !== 'normal') s.fi = cs.fontStyle;
    if (cs.letterSpacing !== 'normal') s.ls = cs.letterSpacing;
    if (cs.opacity !== '1') s.op = num(cs.opacity);
    if (cs.transform !== 'none') s.tf = cs.transform;
    if (cs.visibility !== 'visible') s.vis = cs.visibility;
    if (cs.textAlign !== 'start') s.ta = cs.textAlign;
    if (cs.lineHeight !== 'normal') s.lh = num(cs.lineHeight);
    if (cs.paddingLeft !== '0px' || cs.paddingRight !== '0px') s.px = `${num(cs.paddingLeft)} ${num(cs.paddingRight)}`;
    if (cs.zIndex !== 'auto') s.z = Number(cs.zIndex);
    return s;
  };
  const styles = [], styleIndex = new Map();
  const styleRef = s => {
    const key = JSON.stringify(s);
    if (!styleIndex.has(key)) { styleIndex.set(key, styles.length); styles.push(s); }
    return styleIndex.get(key);
  };
  const vw = innerWidth, vh = innerHeight;
  const items = [], indexOf = new Map();
  const roots = [...document.querySelectorAll('.tl, .dock, .zoom-controls, #viewRange, .detail, .legend')].filter(el => !el.closest('[hidden]'));
  const seen = new Set();
  const visit = el => {
    if (seen.has(el)) return;
    seen.add(el);
    const isSvg = el instanceof SVGElement;
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return;
    const rect = el.getBoundingClientRect();
    const onScreen = rect.right >= -40 && rect.left <= vw + 40 && rect.bottom >= -40 && rect.top <= vh + 40;
    const sized = rect.width > 0 || rect.height > 0;
    if (onScreen && sized) {
      let own = '';
      for (const n of el.childNodes) if (n.nodeType === 3) own += n.nodeValue;
      own = own.replace(/\s+/g, ' ').trim();
      const item = { c: isSvg ? `<${el.tagName.toLowerCase()}> ${el.getAttribute('class') || ''}`.trim() : (typeof el.className === 'string' ? el.className : '') || `<${el.tagName.toLowerCase()}>`, r: [rect.left, rect.top, rect.width, rect.height].map(v => Math.round(v * 100) / 100), s: styleRef(styleOf(cs, isSvg)) };
      if (own) item.t = own;
      for (const [key, attr] of [['k', 'data-k'], ['uid', 'data-uid'], ['row', 'data-row'], ['cell', 'data-cell'], ['tip', 'title']]) {
        const v = el.getAttribute(attr);
        if (v) item[key] = attr === 'title' ? v.slice(0, 80) : v;
      }
      if (isSvg) for (const attr of ['d', 'x', 'y', 'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'width', 'height', 'rx', 'points', 'transform']) {
        const v = el.getAttribute(attr);
        if (v) (item.a ||= {})[attr] = v.length > 600 ? v.slice(0, 600) + '…' : v;
      }
      const parent = el.parentElement && indexOf.get(el.parentElement);
      if (parent != null) item.p = parent;
      indexOf.set(el, items.length);
      items.push(item);
      if (!isSvg) for (const pseudo of ['::before', '::after']) {
        const ps = getComputedStyle(el, pseudo);
        if (!ps.content || ps.content === 'none' || ps.content === 'normal') continue;
        const s = styleOf(ps, false);
        s.content = ps.content.slice(0, 40);
        s.box = [ps.position, ps.left, ps.top, ps.right, ps.bottom, ps.width, ps.height].join(' ');
        items.push({ c: `${item.c} ${pseudo}`, r: item.r, s: styleRef(s), p: indexOf.get(el) });
      }
    }
    // 화면 밖의 큰 상자 안에도 보이는 자식이 있을 수 있다(세로로 긴 트랙) — 자식은 늘 본다
    for (const child of el.children) visit(child);
  };
  roots.forEach(visit);
  const tl = window.__tl;
  const body = tl.bodyEl.getBoundingClientRect();
  return {
    scene: { start: tl.view.start, end: tl.view.end, scrollTop: tl.bodyEl.scrollTop, W: tl.W, gutter: tl.gutter, bodyTop: body.top, bodyLeft: body.left, viewport: [vw, vh], density: tl.density, bird: !!tl._bird },
    model: { tracks: tl.tracks.map(tr => ({ id: tr.id, name: tr.name, color: tr.color, rows: tr.rows, height: tr.height, hidden: [...tr.hiddenRows], rowTop: tr.rowTop, rowHs: tr.rowHs, rowGap: tr.rowGap })) },
    styles, items,
  };
}

const browser = await chromium.launch({ channel: 'msedge', headless: true });
const errors = [];
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('http://127.0.0.1:' + server.address().port);
  await page.waitForFunction(() => window.__state?.model);
  await page.evaluate(raw => {
    const model = HT.buildModel([HT.normalizePack(raw).pack], null);
    __state.model = model;
    __tl.setData(model, { enter: false });
  }, fixture);
  for (const scene of scenes) {
    await page.evaluate(s => { __tl.setDensity(0); __tl.relayout(); __tl.setView(s.start, s.end); __tl.bodyEl.scrollTop = s.scroll; }, scene);
    await page.waitForTimeout(700);
    await page.evaluate(s => { __tl.bodyEl.scrollTop = s.scroll; }, scene);
    await page.waitForTimeout(200);
    const dump = await page.evaluate(dumpPage);
    dump.scene.name = scene.name;
    fs.writeFileSync(path.join(out, `${scene.name}.json`), JSON.stringify(dump));
    await page.screenshot({ path: path.join(out, `${scene.name}.png`) });
    const kinds = new Map();
    for (const it of dump.items) { const key = it.c.split(' ')[0]; kinds.set(key, (kinds.get(key) || 0) + 1); }
    console.log(`${scene.name}: 요소 ${dump.items.length}개 · 모양 ${dump.styles.length}가지 · 띠 ${kinds.get('tl-band') || 0} · 칸 ${kinds.get('tl-cell') || 0} · 사건 ${kinds.get('tl-ev') || 0}`);
  }
} finally {
  await browser.close();
  server.close();
}
if (errors.length) console.error('지금 연표의 쪽에서 난 오류:', errors);
console.log('저장: ' + out);

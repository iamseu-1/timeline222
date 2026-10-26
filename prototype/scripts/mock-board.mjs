/* 목업 고르기 판 — app/test/mock/board_test.dart가 찍은 그림(board.json)을 고르기 판 HTML로 묶는다.
   node prototype/scripts/mock-board.mjs <판 폴더>        (예: prototype/results/mock/board/s4)
     → <판 폴더>/<판>.html · <판 폴더>/fonts/Pretendard-Regular.otf · Pretendard-Bold.otf
   머리(판 이름 · 한 줄 설명) · 두 칸 격자의 카드(갈래 코드 · 이름 · 추천 · 지은이 · 착상 · 장단점 · 1배 그림 · 부품 판 · 2배 조각) ·
   그림을 누르면 1배 전체 보기(← → · Esc · 주소의 #v-<id> · 화면 아래에 부품 판 · 조각). 부품 판은 원본 판과 같은 자리 · 같은 꼴(.partsbox), 조각은 그 아래에 덧붙임. 꼴(CSS)은 자바스크립트 목업 판(board-s4.src.html)의 <style>을 글자 그대로 —
   감독이 보는 꼴이 같게. SVG 대신 PNG를 거는 데 필요한 몇 줄만 뒤에 더했다.
   그림 · 글꼴은 상대 경로로 걸어 판 폴더째 옮겨도 열린다. board.json이 가리키는 그림이 없으면 종료 코드 1. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = process.argv[2];
if (!dir) {
  console.error('사용: node mock-board.mjs <판 폴더>   — board_test.dart가 남긴 board.json이 있는 곳');
  process.exit(2);
}
const fail = msg => {
  console.error(msg);
  process.exit(1);
};
const bf = path.join(dir, 'board.json');
if (!fs.existsSync(bf)) fail(`board.json이 없습니다: ${bf} — 먼저 board_test.dart로 판을 찍을 것`);
const board = JSON.parse(fs.readFileSync(bf, 'utf8'));
const name = board.board || path.basename(path.resolve(dir));
const themes = board.themes || [];
if (!themes.length) fail(`판에 갈래가 없습니다: ${bf}`);

// 걸 그림이 모두 있는가
const missing = [];
for (const t of themes) {
  for (const f of [t.full, ...('parts' in t ? [t.parts] : []), ...(t.crops || []).flatMap(c => [c.x1, c.x2])]) if (!f || !fs.existsSync(path.join(dir, f))) missing.push(`${t.id}: ${f}`);
}
if (missing.length) fail(`그림이 없습니다:\n  ${missing.join('\n  ')}`);

// 판이 품는 글꼴 — 앱 글꼴을 판 폴더에 베낀다(크롬 판이 품는 Pretendard 400 · 700과 같은 파일)
const fontsFrom = path.join(path.dirname(fileURLToPath(import.meta.url)), '../app/assets/fonts');
fs.mkdirSync(path.join(dir, 'fonts'), { recursive: true });
for (const f of ['Pretendard-Regular.otf', 'Pretendard-Bold.otf']) fs.copyFileSync(path.join(fontsFrom, f), path.join(dir, 'fonts', f));

/* 자바스크립트 목업 판의 <style> 그대로(글꼴 자리 __FONT_R__ · __FONT_B__만 판 폴더의 파일로) */
const STYLE = `@font-face { font-family: "Pretendard"; font-weight: 400; src: url("__FONT_R__") format("opentype"); }
@font-face { font-family: "Pretendard"; font-weight: 700; src: url("__FONT_B__") format("opentype"); }
:root { --ink: #000; --ink80: rgba(0,0,0,.8); --ink60: rgba(0,0,0,.6); --ink40: rgba(0,0,0,.4); --ink20: rgba(0,0,0,.2); --ink8: rgba(0,0,0,.08); --ink4: rgba(0,0,0,.04); }
* { box-sizing: border-box; }
html, body { margin: 0; background: #fff; color: #000; font: 14px/22px "Pretendard", "Malgun Gothic", sans-serif; }
.page { width: 1840px; margin: 0 auto; padding: 0 0 120px; }
h1 { font-size: 26px; line-height: 34px; margin: 32px 0 6px; letter-spacing: -.02em; }
.lede { color: var(--ink60); font-size: 15px; line-height: 24px; margin: 0 0 18px; max-width: 1240px; }
.grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 18px; }
.card { border: 1px solid var(--ink20); border-radius: 12px; padding: 12px; }
.card header { display: flex; align-items: center; gap: 9px; margin: 0 0 4px; }
.code { display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 4px; background: #000; color: #fff; font-size: 12px; font-weight: 700; }
.card h3 { margin: 0; font-size: 17px; line-height: 24px; letter-spacing: -.01em; }
.tag { display: inline-flex; align-items: center; height: 20px; padding: 0 7px; border: 1px solid var(--ink20); border-radius: 4px; font-size: 11.5px; color: var(--ink60); }
.tag.rec { border-color: #000; color: #000; font-weight: 700; }
.idea { margin: 0 0 6px; font-size: 13.5px; line-height: 21px; color: var(--ink80); }
.pc { display: flex; gap: 18px; margin: 0 0 10px; font-size: 12.5px; line-height: 19px; color: var(--ink60); }
.pc b { color: #000; margin-right: 5px; }
.thumb { display: block; width: 100%; border: 1px solid var(--ink8); border-radius: 6px; cursor: zoom-in; overflow: hidden; }
.thumb svg { display: block; width: 100%; height: auto; }
.partsbox { margin-top: 8px; border: 1px solid var(--ink8); border-radius: 6px; overflow: hidden; }
.partsbox svg { display: block; width: 100%; height: auto; }
.open { margin-top: 8px; display: flex; gap: 8px; }
.open button { height: 30px; padding: 0 12px; border: 1px solid var(--ink20); border-radius: 6px; background: #fff; font: inherit; font-size: 13px; cursor: pointer; }
.open button:hover { background: var(--ink4); }
/* 1배 보기 — 화면 전체 */
#full { position: fixed; inset: 0; background: #fff; display: none; overflow: auto; z-index: 50; }
#full.on { display: block; }
#full .bar { position: fixed; right: 16px; bottom: 16px; display: flex; gap: 6px; z-index: 51; }
#full .bar button { height: 32px; padding: 0 12px; border: 1px solid #000; border-radius: 6px; background: #fff; font: inherit; font-size: 13px; font-weight: 700; cursor: pointer; }
#full .bar span { height: 32px; display: inline-flex; align-items: center; padding: 0 12px; border-radius: 6px; background: #000; color: #fff; font-size: 13px; font-weight: 700; }
#full svg.screen { display: block; }`;

/* PNG 판에 더한 것 — 그림(img)을 SVG 자리와 같은 꼴로 · 조각 칸은 부품 판 칸과 같은 꼴로 그 아래에 · 조각이 여럿이면 사이에 선 */
const EXTRA = `.thumb img, .partsbox img { display: block; width: 100%; height: auto; }
.partsbox img + img { border-top: 1px solid var(--ink8); }
#full img.screen { display: block; }
#full img.crop { display: block; margin: 0 60px 80px; }`;

const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const src = f => esc(encodeURI(f.replace(/\\/g, '/')));

const cards = themes.map(t => `<article class="card" id="d-${esc(t.id)}"><header><span class="code">${esc(t.code)}</span><h3>${esc(t.name)}</h3>${t.rec ? '<span class="tag rec">추천</span>' : ''}<span class="tag">${esc(t.by)}</span></header>`
  + `<p class="idea">${esc(t.idea)}</p><div class="pc"><span><b>장</b>${esc(t.pro)}</span><span><b>단</b>${esc(t.con)}</span></div>`
  + `<div class="thumb"><img src="${src(t.full)}" width="1920" height="1080" alt="${esc(t.name)}"></div>`
  + (t.parts ? `<div class="partsbox"><img src="${src(t.parts)}" width="1800" height="300" alt="부품 판"></div>` : '')
  + ((t.crops || []).length ? `<div class="partsbox crops">${t.crops.map(c => `<img src="${src(c.x2)}" alt="2배 조각">`).join('')}</div>` : '')
  + '</article>').join('\n    ');
const list = themes.map(t => ({ id: t.id, code: t.code ?? '', name: t.name ?? '', full: encodeURI(t.full), parts: t.parts ? encodeURI(t.parts) : null, crops: (t.crops || []).map(c => encodeURI(c.x2)) }));

const html = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(board.title || name)}</title>
<style>
${STYLE.replace('__FONT_R__', 'fonts/Pretendard-Regular.otf').replace('__FONT_B__', 'fonts/Pretendard-Bold.otf')}
${EXTRA}
</style>
</head>
<body>
<div class="page">
  <h1>${esc(board.title || name)}</h1>
  <p class="lede">${esc(board.lede)}</p>
  <div class="grid" id="grid">
    ${cards}
  </div>
</div>
<div id="full"><div class="host"></div><div class="bar"><span id="fname"></span><button id="prev">←</button><button id="next">→</button><button id="close">닫기</button></div></div>
<script>
(() => {
  const list = ${JSON.stringify(list).replace(/</g, '\\u003c')};
  const full = document.getElementById('full'), host = full.querySelector('.host');
  let cur = 0;
  function show(i) {
    cur = (i + list.length) % list.length;
    const t = list[cur];
    host.innerHTML = '';
    const s = new Image(1920, 1080); s.className = 'screen'; s.src = t.full; host.appendChild(s);
    if (t.parts) { const q = new Image(1800, 300); q.className = 'parts'; q.style.margin = '24px 60px 80px'; q.src = t.parts; host.appendChild(q); }
    for (const c of t.crops) { const q = new Image(); q.className = 'crop'; q.src = c; host.appendChild(q); }
    document.getElementById('fname').textContent = t.code + ' ' + t.name;
    full.classList.add('on'); location.hash = 'v-' + t.id;
  }
  document.querySelectorAll('#grid .card .thumb').forEach((el, i) => { el.onclick = () => show(i); });
  document.getElementById('prev').onclick = () => show(cur - 1);
  document.getElementById('next').onclick = () => show(cur + 1);
  document.getElementById('close').onclick = () => { full.classList.remove('on'); history.replaceState(null, '', location.pathname); };
  addEventListener('keydown', e => { if (!full.classList.contains('on')) return; if (e.key === 'ArrowLeft') show(cur - 1); if (e.key === 'ArrowRight') show(cur + 1); if (e.key === 'Escape') document.getElementById('close').onclick(); });
  const m = location.hash.match(/^#v-(.+)$/); if (m) { const i = list.findIndex(t => t.id === decodeURIComponent(m[1])); if (i >= 0) show(i); }
  window.showDir = tid => { const i = list.findIndex(t => t.id === tid); if (i >= 0) show(i); };
  window.closeDir = () => document.getElementById('close').onclick();
  document.body.dataset.ready = '1';
})();
</script>
</body>
</html>
`;
const out = path.join(dir, `${name}.html`);
fs.writeFileSync(out, html);
console.log(`${out} — 갈래 ${themes.length} · 부품 판 ${themes.filter(t => t.parts).length} · 조각 ${themes.reduce((n, t) => n + (t.crops || []).length, 0)} · ClearType ${board.cleartype ? '켬' : '끔'} · 찍기 ${board.seconds}초`);

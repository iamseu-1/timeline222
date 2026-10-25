/* 공용 목업 도구 — 고르기 판(board.html) 만들기. 결정마다 '지금 모습'과 안 A · B · C의 그림을 제 크기(1px = 1px)로 나란히 둡니다.
 * 그림은 <img>에 width · height를 적고 CSS로 줄이지 않습니다(넓으면 그 그림 칸만 가로로 밀어 봄). 바탕은 밝은 종이색, 글은 한국어.
 *
 * ── 쓰는 법 ──────────────────────────────────────────────────────────────
 *   import { writeBoard } from '/home/user/timeline/scripts/mock/board.mjs';
 *   writeBoard({
 *     out: '/home/user/timeline/.claude/research/10건/D1/board.html',    // 그림(PNG)과 같은 폴더 권장 — 그림 길은 이 파일 기준 상대로 적힘
 *     branch: 'D1 · 계승과 가문',            // 갈래 이름 (맨 위 큰 글)
 *     title: '계승표 · 가문 표시 고르기',      // 판 제목
 *     date: '2026-10-12',                    // 기본값 그대로
 *     lead: '무엇을 고르는 판인지 두세 줄',
 *     notice: '…',                           // 기본: '예시 항목은 확인용 · 고증 아님' 안내 (끄려면 '')
 *     decisions: [{
 *       id: 'd1', title: '즉위 구분선의 모양', desc: '물음 · 배경',
 *       now: 'now-d1.png' | { src, caption } | [그림…],          // 지금 모습
 *       options: [{ key: 'A', name: '가는 점선', img: 'd1-a.png' | imgs: [{ src, caption }…], desc: '설명',
 *                   pros: ['좋은 점'], cons: ['걸리는 점'],
 *                   checks: { '새 앱': '같은 모습 가능 — …', '띠 높이': '+0px', '성능': '…', '휴대폰': '…' } }, …],
 *       recommend: 'B', why: '추천 까닭',
 *     }],
 *     sections: [{ title: '덧붙임', desc: '…', images: ['x.png'] }],  // 결정이 아닌 그림 묶음(선택)
 *   });
 *   글 칸(desc · why · caption …)은 그대로 적히고 줄바꿈은 살림. HTML을 쓰려면 descHtml · whyHtml.
 *   판에는 결정마다 고르기 단추(A · B · C · 다른 안)와 덧붙일 말 칸이 있고, '고른 것 복사'로 감독이 고른 것을 글 한 덩이로 복사합니다(이 브라우저에만 기억).
 * ───────────────────────────────────────────────────────────────────────── */
import fs from 'node:fs';
import path from 'node:path';

export const DEFAULT_NOTICE = '판에 얹은 예시 항목(나라 · 사람 · 사건)은 모양을 보기 위한 확인용이며 고증이 아닙니다. 새로 생기는 단추 · 안내 글에는 실제 역사 이름을 넣지 않습니다.';
export const DEFAULT_BASIS = '지금 모습 = 고정 사본(HEAD 6db35c4)의 웹 연표 · 1920×1080 · 100% · 1배 · 동작 줄이기. 새 앱은 1배에서 웹과 같은 모습이므로 이 판으로 고릅니다.';

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const text = s => esc(s).replace(/\n/g, '<br>');

/** 그림 파일의 가로 · 세로 (PNG · JPEG) — 모르면 null */
export function imageSize(file) {
  try {
    const b = fs.readFileSync(file);
    if (b.length > 24 && b.toString('ascii', 1, 4) === 'PNG') return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
    if (b[0] === 0xff && b[1] === 0xd8) {
      let i = 2;
      while (i < b.length) {
        if (b[i] !== 0xff) { i++; continue; }
        const m = b[i + 1], len = b.readUInt16BE(i + 2);
        if (m >= 0xc0 && m <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(m)) return { width: b.readUInt16BE(i + 7), height: b.readUInt16BE(i + 5) };
        i += 2 + len;
      }
    }
  } catch { /* 없는 파일 */ }
  return null;
}

/** 그림 하나: 'a.png' | { src, caption, alt, title } → <figure> (제 크기 · 넓으면 가로 스크롤) */
function figure(img, dir) {
  const o = typeof img === 'string' ? { src: img } : img;
  const abs = path.isAbsolute(o.src) ? o.src : path.resolve(dir, o.src);
  const rel = path.relative(dir, abs).split(path.sep).join('/');
  const size = imageSize(abs);
  if (!size) console.warn(`  [판] 그림을 읽지 못함(크기 모름): ${abs}`);
  const wh = size ? ` width="${size.width}" height="${size.height}"` : '';
  const dim = size ? `${size.width}×${size.height}` : '크기 모름';
  const href = encodeURI(rel);
  return `<figure class="shot">
  ${o.title ? `<div class="shot-title">${esc(o.title)}</div>` : ''}<div class="scroll" tabindex="0"><a href="${href}" target="_blank" rel="noopener" title="새 탭에서 제 크기로 열기"><img src="${href}"${wh} alt="${esc(o.alt || o.caption || o.title || rel)}"></a></div>
  <figcaption>${o.caption ? `${text(o.caption)} · ` : ''}<span class="dim">${dim} · 1배</span></figcaption>
</figure>`;
}
const imagesOf = x => [].concat(x.imgs || x.images || x.img || []).filter(Boolean);

function checksTable(checks) {
  const rows = Object.entries(checks || {}).filter(([, v]) => v != null && v !== '');
  if (!rows.length) return '';
  return `<dl class="checks">${rows.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${text(v)}</dd>`).join('')}</dl>`;
}
function list(items, cls, mark) {
  items = [].concat(items || []).filter(Boolean);
  return items.length ? `<ul class="${cls}">${items.map(i => `<li><span class="mk">${mark}</span>${text(i)}</li>`).join('')}</ul>` : '';
}

function decisionHTML(d, n, dir) {
  const id = d.id || `d${n}`;
  const options = d.options || [];
  const nowImgs = [].concat(d.now || []).filter(Boolean);
  const now = nowImgs.length
    ? `<article class="cand is-now">
  <header><span class="key key-now">지금</span><h3>지금 모습</h3></header>
  ${nowImgs.map(i => figure(i, dir)).join('\n')}
  ${d.nowDesc ? `<div class="txt"><p>${text(d.nowDesc)}</p></div>` : ''}
</article>`
    : '';
  const opts = options
    .map(o => {
      const rec = d.recommend && o.key === d.recommend;
      return `<article class="cand${rec ? ' is-rec' : ''}" id="${esc(id)}-${esc(o.key)}">
  <header><span class="key">${esc(o.key)}</span><h3>${esc(o.name || '')}</h3>${rec ? '<span class="rec-badge">추천</span>' : ''}</header>
  ${imagesOf(o).map(i => figure(i, dir)).join('\n')}
  <div class="txt">
    ${o.descHtml ? `<div class="desc">${o.descHtml}</div>` : o.desc ? `<p class="desc">${text(o.desc)}</p>` : ''}
    ${list(o.pros, 'pros', '＋')}${list(o.cons, 'cons', '－')}
    ${checksTable(o.checks)}
  </div>
</article>`;
    })
    .join('\n');
  const recOpt = options.find(o => o.key === d.recommend);
  const why = d.whyHtml || (d.why ? text(d.why) : '');
  const keys = options.map(o => o.key).concat(['다른 안']);
  return `<section class="decision" id="${esc(id)}" data-id="${esc(id)}" data-title="${esc(d.title || '')}">
  <h2><span class="num">결정 ${n}</span>${esc(d.title || '')}</h2>
  ${d.descHtml ? `<div class="lead">${d.descHtml}</div>` : d.desc ? `<p class="lead">${text(d.desc)}</p>` : ''}
  <div class="cands">
${now}
${opts}
  </div>
  ${d.recommend ? `<div class="recbox"><b>추천 — 안 ${esc(d.recommend)}${recOpt && recOpt.name ? ` · ${esc(recOpt.name)}` : ''}</b>${why ? `<p>${why}</p>` : ''}</div>` : ''}
  ${options.length ? `<div class="pick" role="group" aria-label="결정 ${n} 고르기">
    <span class="pick-label">고름</span>
    ${keys.map(k => `<label class="pick-opt"><input type="radio" name="pick-${esc(id)}" value="${esc(k)}"><span>${k === '다른 안' ? '다른 안' : `안 ${esc(k)}`}</span></label>`).join('')}
    <label class="pick-memo"><span>덧붙일 말</span><textarea name="memo-${esc(id)}" rows="1" aria-label="결정 ${n}에 덧붙일 말"></textarea></label>
  </div>` : ''}
</section>`;
}

const CSS = `
:root{--paper:#f7f2ea;--card:#fffdf9;--line:#e6dccd;--ink:#3a332d;--soft:#7a6e62;--faint:#a3978a;--rec:#dab195;--rec-bg:#fbf1e6;--now:#a4b1b7;--pick:#9dbea8;color-scheme:light}
*{box-sizing:border-box}
html{background:var(--paper)}
body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.6 Pretendard,"Pretendard Variable","Apple SD Gothic Neo","Malgun Gothic",sans-serif;-webkit-font-smoothing:antialiased;overflow-x:hidden}
main{padding:28px 24px 80px}
.top{max-width:1100px;margin:0 0 28px}
.branch{display:inline-block;font-size:13px;font-weight:600;color:var(--soft);background:var(--card);border:1px solid var(--line);border-radius:999px;padding:2px 12px}
h1{font-size:28px;line-height:1.3;margin:10px 0 6px;letter-spacing:-.01em}
.meta{color:var(--soft);font-size:13px;margin:0 0 12px}
.meta b{color:var(--ink);font-weight:600}
.notice{background:#fbf3df;border:1px solid #ecdcb5;border-radius:12px;padding:8px 14px;font-size:13.5px;margin:10px 0}
.basis{font-size:13px;color:var(--soft);margin:6px 0}
.dpr{display:none;background:#f6e3df;border:1px solid #e6c4bd;border-radius:12px;padding:8px 14px;font-size:13.5px;margin:10px 0}
.lead-top{margin:12px 0;max-width:980px}
.toc{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 18px;margin:16px 0 0}
.toc h2{font-size:14px;margin:0 0 6px;color:var(--soft);font-weight:600}
.toc ol{margin:0;padding-left:22px}
.toc li{margin:2px 0}
.toc a{color:var(--ink);text-decoration:none;border-bottom:1px solid var(--line)}
.toc .r{color:var(--soft);font-size:13px;margin-left:6px}
.decision{margin:40px 0 0;padding-top:12px;border-top:1px solid var(--line)}
.decision h2{font-size:21px;margin:6px 0 4px;letter-spacing:-.01em}
.decision h2 .num{display:inline-block;font-size:13px;font-weight:600;color:var(--soft);background:var(--card);border:1px solid var(--line);border-radius:8px;padding:0 8px;margin-right:10px;vertical-align:3px}
.lead{max-width:980px;margin:4px 0 16px;color:var(--ink)}
.cands{display:flex;flex-wrap:wrap;gap:20px;align-items:flex-start}
.cand{flex:0 1 auto;min-width:320px;max-width:100%;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:12px 14px 14px}
.cand.is-now{background:#fbfaf8}
.cand.is-rec{border:2px solid var(--rec);background:var(--rec-bg);padding:11px 13px 13px}
.cand header{display:flex;align-items:center;gap:10px;margin:0 0 10px}
.cand h3{font-size:16px;margin:0;font-weight:600}
.key{display:inline-flex;align-items:center;justify-content:center;min-width:28px;height:28px;padding:0 8px;border-radius:9px;background:#efe6d9;font-weight:700;font-size:15px}
.key-now{background:#e7ebed;font-size:13px;font-weight:600}
.is-rec .key{background:var(--rec);color:#3b2a1d}
.rec-badge{margin-left:auto;font-size:12.5px;font-weight:700;color:#5a3d22;background:var(--rec);border-radius:999px;padding:2px 10px}
.shot{margin:0 0 10px}
.shot-title{font-size:13px;color:var(--soft);margin:0 0 4px}
.scroll{overflow-x:auto;overflow-y:hidden;max-width:100%;border-radius:10px;border:1px solid var(--line);background:#fff}
.scroll:focus-visible{outline:2px solid var(--rec);outline-offset:2px}
.scroll img{display:block;max-width:none;min-width:0;image-rendering:auto}
.scroll a{display:block;width:max-content}
figcaption{font-size:12.5px;color:var(--soft);margin:5px 2px 0}
.dim{color:var(--faint)}
.txt{width:0;min-width:100%}
.txt p{margin:4px 0}
.desc{margin:4px 0}
ul.pros,ul.cons{list-style:none;padding:0;margin:6px 0}
ul.pros li,ul.cons li{margin:2px 0;padding-left:20px;position:relative}
.mk{position:absolute;left:0;font-weight:700}
.pros .mk{color:#6f9a7f}.cons .mk{color:#b07a70}
dl.checks{display:grid;grid-template-columns:max-content 1fr;gap:3px 12px;margin:8px 0 0;padding:8px 10px;background:#f8f3ec;border-radius:10px;font-size:13.5px}
dl.checks dt{color:var(--soft);font-weight:600}
dl.checks dd{margin:0}
.recbox{max-width:980px;margin:16px 0 0;background:var(--rec-bg);border:1px solid #ecd6bf;border-radius:14px;padding:10px 16px}
.recbox p{margin:4px 0 0}
.pick{display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px;margin:14px 0 0;max-width:980px}
.pick-label{font-weight:600;color:var(--soft);font-size:13.5px}
.pick-opt{display:inline-flex;align-items:center;gap:6px;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:4px 12px;cursor:pointer;font-size:14px}
.pick-opt:has(input:checked){border-color:var(--pick);background:#eaf3ed;font-weight:600}
.pick-opt input{accent-color:#6f9a7f;margin:0}
.pick-memo{display:flex;align-items:center;gap:8px;flex:1 1 280px;font-size:13.5px;color:var(--soft)}
.pick-memo textarea{flex:1;min-height:34px;resize:vertical;font:inherit;color:var(--ink);background:var(--card);border:1px solid var(--line);border-radius:10px;padding:5px 10px}
.extra{margin:40px 0 0;padding-top:12px;border-top:1px solid var(--line)}
.extra h2{font-size:19px;margin:6px 0 4px}
.copybar{position:fixed;right:20px;bottom:20px;display:flex;gap:8px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:8px 10px;box-shadow:0 6px 24px rgba(80,60,40,.12);z-index:5}
.copybar button{font:inherit;font-size:14px;font-weight:600;background:var(--rec);color:#3b2a1d;border:0;border-radius:10px;padding:6px 14px;cursor:pointer}
.copybar span{font-size:13px;color:var(--soft)}
@media (max-width:700px){main{padding:18px 16px 90px}h1{font-size:23px}.cand{min-width:0;width:100%}}
`;

const SCRIPT = `
(function(){
  if (window.devicePixelRatio && Math.abs(window.devicePixelRatio - 1) > 0.01) {
    var w = document.getElementById('dpr');
    if (w) { w.style.display = 'block'; w.textContent = '지금 화면 배율이 ' + Math.round(window.devicePixelRatio * 100) + '%입니다 — 그림을 1배(1px = 화면 1px)로 보려면 브라우저 확대를 100%(Ctrl+0)로, 디스플레이 배율도 100%로 맞춰 보세요.'; }
  }
  var KEY = 'mock-board:' + location.pathname;
  var saved = {};
  try { saved = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { saved = {}; }
  var save = function(){ try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {} };
  document.querySelectorAll('.decision').forEach(function(sec){
    var id = sec.dataset.id, s = saved[id] || {};
    sec.querySelectorAll('input[type=radio]').forEach(function(r){
      if (s.pick === r.value) r.checked = true;
      r.addEventListener('change', function(){ saved[id] = Object.assign({}, saved[id], { pick: r.value }); save(); });
    });
    var memo = sec.querySelector('textarea');
    if (memo) {
      if (s.memo) memo.value = s.memo;
      memo.addEventListener('input', function(){ saved[id] = Object.assign({}, saved[id], { memo: memo.value }); save(); });
    }
  });
  var btn = document.getElementById('copyPicks'), note = document.getElementById('copyNote');
  if (btn) btn.addEventListener('click', function(){
    var lines = [document.body.dataset.board + ' — 고른 것'];
    document.querySelectorAll('.decision').forEach(function(sec, i){
      var r = sec.querySelector('input[type=radio]:checked'), m = sec.querySelector('textarea');
      lines.push('결정 ' + (i + 1) + ' (' + sec.dataset.title + '): ' + (r ? (r.value === '다른 안' ? '다른 안' : '안 ' + r.value) : '아직 안 고름') + (m && m.value.trim() ? ' — ' + m.value.trim() : ''));
    });
    var t = lines.join('\\n');
    var done = function(ok){ note.textContent = ok ? '복사했습니다' : '복사하지 못했습니다 — 글을 직접 골라 복사하세요'; };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(t).then(function(){ done(true); }, function(){ fallback(); });
    else fallback();
    function fallback(){
      var ta = document.createElement('textarea'); ta.value = t; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.left = '-9999px';
      document.body.appendChild(ta); ta.select();
      var ok = false; try { ok = document.execCommand('copy'); } catch (e) {}
      ta.remove(); done(ok);
    }
  });
})();
`;

/** board.html을 만듭니다 — 돌려줌: 쓴 파일의 절대 경로 */
export function writeBoard({ out, branch = '', title = '고르기 판', date = '2026-10-12', lead = '', leadHtml = '', notice = DEFAULT_NOTICE, basis = DEFAULT_BASIS, decisions = [], sections = [], picker = true } = {}) {
  if (!out) throw new Error('writeBoard: out(board.html 경로)이 필요합니다');
  out = path.resolve(out);
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const toc = decisions.length
    ? `<nav class="toc" aria-label="결정 목록"><h2>결정 목록</h2><ol>${decisions
        .map((d, i) => {
          const rec = (d.options || []).find(o => o.key === d.recommend);
          return `<li><a href="#${esc(d.id || `d${i + 1}`)}">${esc(d.title || `결정 ${i + 1}`)}</a>${(d.options || []).length ? `<span class="r">안 ${(d.options || []).map(o => esc(o.key)).join(' · ')}${d.recommend ? ` — 추천 ${esc(d.recommend)}${rec && rec.name ? ` (${esc(rec.name)})` : ''}` : ''}</span>` : ''}</li>`;
        })
        .join('')}</ol></nav>`
    : '';
  const extras = sections
    .map(s => `<section class="extra"><h2>${esc(s.title || '')}</h2>${s.descHtml ? `<div class="lead">${s.descHtml}</div>` : s.desc ? `<p class="lead">${text(s.desc)}</p>` : ''}<div class="cands">${imagesOf(s).map(i => `<article class="cand">${figure(i, dir)}</article>`).join('\n')}</div></section>`)
    .join('\n');
  const boardName = [branch, title].filter(Boolean).join(' · ');
  const html = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>${CSS}</style>
</head>
<body data-board="${esc(boardName)}">
<main>
  <header class="top">
    ${branch ? `<span class="branch">${esc(branch)}</span>` : ''}
    <h1>${esc(title)}</h1>
    <p class="meta"><b>${esc(date)}</b>${decisions.length ? ` · 결정 ${decisions.length}건` : ''} · 그림은 모두 제 크기(1px = 1px) — 넓은 그림은 그 칸을 가로로 밀어 봅니다 · 그림을 누르면 새 탭에서 제 크기로</p>
    <div class="dpr" id="dpr" role="note"></div>
    ${notice ? `<p class="notice"><b>확인용 · 고증 아님</b> — ${text(notice)}</p>` : ''}
    ${basis ? `<p class="basis">${text(basis)}</p>` : ''}
    ${leadHtml ? `<div class="lead-top">${leadHtml}</div>` : lead ? `<p class="lead-top">${text(lead)}</p>` : ''}
    ${toc}
  </header>
${decisions.map((d, i) => decisionHTML(d, i + 1, dir)).join('\n')}
${extras}
</main>
${picker && decisions.some(d => (d.options || []).length) ? '<div class="copybar"><span id="copyNote" aria-live="polite"></span><button type="button" id="copyPicks">고른 것 복사</button></div>' : ''}
<script>${SCRIPT}</script>
</body>
</html>
`;
  fs.writeFileSync(out, html);
  return out;
}

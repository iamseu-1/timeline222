/* 자바스크립트 목업 판 다시 짓기 — 원본 사본(app/test/mock/source)의 판 틀에 글꼴 · 스크립트를 품어 한 장으로.
   node prototype/scripts/mock-build-board.mjs [원본 폴더] [출력 html]
     기본: app/test/mock/source → prototype/results/mock/source/board-s4.html(git 밖 · 4MB쯤) + 옆에 mock-sha.txt
   사본의 build.mjs와 같은 짜임(같은 바꿔 넣기 · 같은 차례 — themes.js 뒤에 themes/<파일>을 '(function () { … })();'로 싸서 · 차례는 themes/order.json)이되,
   build.mjs가 기대는 저장소 밖 자리 둘만 넘겨받는다: 글꼴은 앱 assets/fonts의 Pretendard 400 · 700(판이 품던 것과 같은 파일), 판 틀은 board-s4.src.html.
   크롬 기준 그림(mock-golden.mjs)은 이 판에서 뽑는다 — mock-golden이 판 옆의 mock-sha.txt로 판이 품은 스크립트의 지문을 본다.
   짓기 전에 원본 사본의 파일마다 SHA-256 앞 12자가 mock-sha.txt와 같은지 보고, 다르면 종료 코드 1. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = n => { const a = args.find(x => x.startsWith(`--${n}=`)); if (a) args.splice(args.indexOf(a), 1); return a ? a.slice(n.length + 3) : null; };
const srcName = opt('src') || 'board-s4.src.html';
const dir = path.resolve(args[0] || path.join(scripts, '../app/test/mock/source'));
const out = path.resolve(args[1] || path.join(scripts, '../results/mock/source/board-s4.html'));
const fonts = path.join(scripts, '../app/assets/fonts');
const fail = msg => {
  console.error(msg);
  process.exit(1);
};
const sha12 = data => crypto.createHash('sha256').update(data).digest('hex').slice(0, 12);

// 원본 사본의 지문 — mock-sha.txt의 판과 같은가(줄 끝 하나라도 바뀌면 다름)
const shaFile = path.join(dir, 'mock-sha.txt');
if (!fs.existsSync(shaFile)) fail(`원본 폴더에 mock-sha.txt가 없습니다: ${shaFile}`);
const want = fs.readFileSync(shaFile, 'utf8').split(/\r?\n/).filter(Boolean).map(l => l.match(/^([0-9a-f]{12})\s+\*?(.+)$/) || fail(`지문 줄을 읽지 못했습니다: ${l}`));
const bad = want.filter(([, sha, f]) => !fs.existsSync(path.join(dir, f.trim())) || sha12(fs.readFileSync(path.join(dir, f.trim()))) !== sha);
if (bad.length) fail(`원본 사본이 mock-sha.txt와 다릅니다: ${bad.map(([, sha, f]) => `${f.trim()}(${sha})`).join(' · ')}`);

// build.mjs 그대로: 판 틀의 자리마다 한 곳씩 바꿔 넣는다
let html = fs.readFileSync(path.join(dir, srcName), 'utf8');
const swap = (key, val) => { const n = html.split(key).length - 1; if (n !== 1) throw Error(`${key}: ${n}곳`); html = html.replace(key, () => val); };
const b64 = (f, type) => `data:${type};base64,` + fs.readFileSync(f).toString('base64');
swap('__FONT_R__', b64(path.join(fonts, 'Pretendard-Regular.otf'), 'font/otf'));
swap('__FONT_B__', b64(path.join(fonts, 'Pretendard-Bold.otf'), 'font/otf'));
for (const [k, f] of [['__KIT__', 'kit.js'], ['__SCENE__', 'scene.js'], ['__RENDER__', 'render.js']]) swap(k, fs.readFileSync(path.join(dir, f), 'utf8'));
const tdir = path.join(dir, 'themes');
let order = null;
try { order = JSON.parse(fs.readFileSync(path.join(tdir, 'order.json'), 'utf8')); } catch { /* 없으면 이름 차례 */ }
const rank = f => { const i = order ? order.indexOf(f.replace(/\.js$/, '')) : -1; return i < 0 ? 999 : i; };
const tfiles = fs.readdirSync(tdir).filter(f => f.endsWith('.js')).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
const parts = [fs.readFileSync(path.join(dir, 'themes.js'), 'utf8')];
for (const f of tfiles) parts.push(`/* themes/${f} */\n(function () {\n${fs.readFileSync(path.join(tdir, f), 'utf8')}\n})();`);
swap('__THEMES__', parts.join('\n'));

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
fs.copyFileSync(shaFile, path.join(path.dirname(out), 'mock-sha.txt'));
console.log(`${out} — ${(fs.statSync(out).size / 1048576).toFixed(1)}MB · 갈래 파일 ${tfiles.length} · sha256 ${sha12(fs.readFileSync(out))} · 옆에 mock-sha.txt`);

/* 서류철 개편 목업 판 — board.src.html에 글꼴 · 스크립트를 품어 한 장으로.
   node build.mjs                                         → ../서류철-개편-목업.html (모든 방향)
   node build.mjs --only=tag,binder --out=out/tag.html    → 고른 방향만(에이전트가 저마다 확인할 때 — 서로 덮어쓰지 않게)
   방향은 themes.js(기준) + themes/*.js(방향마다 한 파일 · 차례는 themes/order.json) */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../../..');
const arg = n => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=')[1];
const only = (arg('only') || '').split(',').filter(Boolean);
const b64 = (f, type) => `data:${type};base64,` + fs.readFileSync(f).toString('base64');
let html = fs.readFileSync(path.join(here, arg('src') || 'board.src.html'), 'utf8'); // --src=<판 틀> (구멍 판 등)
const swap = (key, val) => { const n = html.split(key).length - 1; if (n !== 1) throw Error(`${key}: ${n}곳`); html = html.replace(key, () => val); };
swap('__FONT_R__', b64(path.join(repo, 'fonts/Pretendard-Regular.otf'), 'font/otf'));
swap('__FONT_B__', b64(path.join(repo, 'fonts/Pretendard-Bold.otf'), 'font/otf'));
// 글꼴은 프리텐다드 고정(감독 '폰트는 건들지마') — 명조는 싣지 않음
for (const [k, f] of [['__KIT__', 'kit.js'], ['__SCENE__', 'scene.js'], ['__RENDER__', 'render.js']]) swap(k, fs.readFileSync(path.join(here, f), 'utf8'));
const tdir = path.join(here, 'themes');
let order = null;
try { order = JSON.parse(fs.readFileSync(path.join(tdir, 'order.json'), 'utf8')); } catch { /* 없으면 이름 차례 */ }
const rank = f => { const i = order ? order.indexOf(f.replace(/\.js$/, '')) : -1; return i < 0 ? 999 : i; };
let tfiles = fs.readdirSync(tdir).filter(f => f.endsWith('.js')).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
if (only.length) tfiles = tfiles.filter(f => only.includes(f.replace(/\.js$/, '')));
const parts = [fs.readFileSync(path.join(here, 'themes.js'), 'utf8')];
for (const f of tfiles) parts.push(`/* themes/${f} */\n(function () {\n${fs.readFileSync(path.join(tdir, f), 'utf8')}\n})();`);
swap('__THEMES__', parts.join('\n'));
const out = arg('out') ? path.resolve(here, arg('out')) : path.join(here, '..', '2단계-결정-목업.html');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
console.log(out, (fs.statSync(out).size / 1048576).toFixed(1) + 'MB', '방향 파일', tfiles.length);

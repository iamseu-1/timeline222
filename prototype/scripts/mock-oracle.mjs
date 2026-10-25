// 목업 정답지 뽑기: 자바스크립트 목업(kit.js · scene.js · render.js)을 노드의 빈 전역에서 돌려, Dart로 옮긴 것과 견줄 수를 JSON으로 적는다.
// 사용: node prototype/scripts/mock-oracle.mjs <목업 폴더> <출력 kit.json> [<출력 layout.json>]
// 목업 폴더(읽기만): 원본은 D:/Timeline/.claude/research/stage2/mock(저장소 밖 연구 폴더).
//   옆 세션이 원본을 고칠 수 있으므로, 정답지와 옮긴 것이 같은 판을 가리키게 지문을 확인한 사본(app/test/mock/source — 저장소에 둔 원본 사본)에서 뽑는다.
//   어느 판인지는 출력의 source(SHA-256 앞 12자)에 남는다.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';

const [dir, outKit, outLayout] = process.argv.slice(2);
if (!dir || !outKit) {
  console.error('사용: node prototype/scripts/mock-oracle.mjs <목업 폴더> <출력 kit.json> [<출력 layout.json>]');
  process.exit(2);
}
// 화면을 만들지 않으므로 DOM은 빈 껍데기만 둔다(글 폭은 kit.json에 넣지 않는다 — 크롬의 글 폭은 그림 대조가 다룬다).
const el = () => ({ setAttribute() {}, appendChild() {}, style: {}, set innerHTML(v) {}, set textContent(v) {} });
const ctx = { document: { createElementNS: el, createElement: () => ({ getContext: () => ({ measureText: s => ({ width: String(s).length * 7 }), font: '' }) }) } };
ctx.window = ctx;
vm.createContext(ctx);
const run = f => vm.runInContext(fs.readFileSync(path.join(dir, f), 'utf8'), ctx, { filename: f });
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, f))).digest('hex').slice(0, 12);

run('kit.js');
const K = ctx.K;
const colors = Object.values(K.P);
const ps = [0, .08, .24, .45, .84, .92, 1];
const out = { source: { 'kit.js': sha('kit.js') }, mix: [], mixOk: [], fn: [], ink3: [], paper: [], rr: [], tab: [], poly: [], px: [], base: [] };
for (const c of colors) for (const p of ps) {
  out.mix.push([c, p, K.mix(c, p)]);
  out.mixOk.push([c, p, K.mixOk(c, p, K.INK)]);
}
for (const c of colors) out.fn.push([c, K.edge(c), K.edgeSoft(c), K.fillC(c), K.fillC(c, .09), K.tabInk(c), K.nameInk(c), K.ink(.6)]);
// render.js가 실제로 부르는 꼴 — 먹 · 종이를 넘기는 ink(a, paper, ink), 종이(또는 INK) 위로 섞는 mixOk · mix · fillC.
// 방향의 tok은 지금 모두 흰 종이 · 검은 먹이므로 그것에 더해, 밑색이 다른 경우를 보려 누런 종이 · 짙은 먹을 하나 더한다.
for (const [paper, ink] of [['#ffffff', '#000000'], ['#f4efe6', '#2a2a2a']]) for (const a of [.035, .05, .12, .2, .5, .8]) out.ink3.push([a, paper, ink, K.ink(a, paper, ink)]);
for (const paper of ['#ffffff', '#f4efe6', K.INK]) for (const c of colors) out.paper.push([c, paper, K.mixOk(c, .35, paper), K.mixOk(c, .55, paper), K.mixOk(c, .7, paper), K.mix(c, .5, paper), K.fillC(c, .09, paper)]);
for (const a of [[10, 20, 100, 24, 10], [10, 20, 100, 24, 30], [0.5, 1.5, 40, 13, [5, 5, 0, 0]], [3, 4, 8, 8, 12, 2], [-7.5, 0, 60, 30, 0]]) out.rr.push([a, K.rr(...a)]);
for (const a of [[100, 160, 140, 13], [100.5, 130.5, 140.5, 20, 9], [0, 14, 10, 13, 7]]) out.tab.push([a, K.tabPath(...a)]);
out.poly.push([[[0, 0], [40, 0], [40, 20], [0, 20]], 4, K.roundPoly([[0, 0], [40, 0], [40, 20], [0, 20]], 4)]);
for (const v of [-2.5, -2.4, 0, 2.5, 7.49, 100.5]) out.px.push([v, K.px(v)]);
for (const [cy, s] of [[28, 15], [69, 11], [140.5, 8.5]]) out.base.push([cy, s, K.base(cy, s)]);
fs.writeFileSync(outKit, JSON.stringify(out, null, 1));

if (outLayout) {
  run('scene.js');
  run('render.js');
  const L = ctx.layoutScene(JSON.parse(JSON.stringify(ctx.SCENE)), ctx.BASE.M);
  const rows = L.rows.map(r => ({ y: r.y, yBand: r.yBand, h: r.h, depth: r.depth, laneY: r.laneY ?? null, items: r.items.map(o => o.n) }));
  const containers = L.containers.map(c => ({ n: c.n, depth: c.depth, yTop: c.yTop, yBottom: c.yBottom, rows: c.rows.length }));
  const cultures = L.cultures.map(c => ({ n: c.n, y0: c.y0, y1: c.y1, closed: !!c.closed, rowY: c.rowY ?? null }));
  fs.writeFileSync(outLayout, JSON.stringify({ source: { 'scene.js': sha('scene.js'), 'render.js': sha('render.js') }, bottom: L.bottom, rows, containers, cultures }, null, 1));
}
console.log('정답지', outKit, outLayout || '');

/* 목업 나무 대조 — 원본 JS 목업과 Dart로 옮긴 목업이 같은 요소 나무를 짓는지 갈래마다 견준다.
   node prototype/scripts/mock-tree.mjs [<목업 폴더> <Dart 덤프 폴더>] [--rerun "<Dart 덤프 명령>"]
     목업 폴더  = kit.js · scene.js · render.js · themes.js · themes/*.js가 든 곳(옮긴 Dart 머리말의 지문과 같은 판) — 기본 app/test/mock/source(원본 사본)
     덤프 폴더  = app/test/mock/tree_dump_test.dart가 남긴 곳 — 기본 prototype/results/mock/tree(<id>.json · ids.json · widths.json)
   먼저 판 지문을 맞춘다: 목업 폴더에서 싣는 파일마다 SHA-256 앞 12자가 app/lib/mock/**.dart 머리말의 '<이름>.js(sha256 …)'와 같아야 하고,
   머리말에 적힌 파일이 모두 있어야 한다(다른 판 · 잘못된 폴더를 견주지 않게).
   원본을 노드 vm의 작은 DOM 흉내로 판(board-s4)의 차례대로 싣고(build.mjs와 같은 파일 차례), 기준 방향 + 판의 갈래(opt가 있는 것)
   + 연습 갈래 둘(아래 DRILLS)마다 renderScreen · renderParts를 불러 요소 나무를 짓는다. 글 폭(canvas measureText)은 Dart가 잰 표(widths.json)에서 읽는다 —
   같은 폭이면 옮긴 갈래가 원본과 같은 나무를 지어야 한다(크롬과의 글 폭 차이는 그림 대조가 본다).
   갈래 목록도 맞춘다: 원본 쪽 목록(기준 방향 + 판 갈래 + 연습)이 Dart가 덤프한 차례(ids.json)와 차례까지 같고 판 갈래가 하나 이상이어야 한다.
   견주는 것: 요소 이름 · 속성(두 쪽 합집합 · 글로) · 글 · 자식 수 · 아이콘 속(innerHTML 글 ↔ Dart가 읽은 자식) · 갈래의 값(meta: 이름 · opt · 합친 M · tok · 줄 기록).
   자동 번호(K.id — 앱 전체에서 늘어 두 쪽이 다름)는 나무마다 처음 나온 차례로 다시 매긴다(clip12 → clip#1) — 무엇을 가리키는지는 견준다.
   표에 없던 글 폭을 노드가 물으면 queries.json에 모은다 — Dart 덤프를 다시 돌리면 그것까지 잰다(--rerun이 있으면 스스로 다시 돌려 다섯 번까지).
   지문 · 목록 · 나무 · 값이 하나라도 다르거나 빠진 폭이 있으면 종료 코드 1. */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const flag = n => { const i = args.indexOf(`--${n}`); if (i < 0) return null; const v = args[i + 1]; args.splice(i, 2); return v; };
const rerun = flag('rerun');
const here = path.dirname(fileURLToPath(import.meta.url));
const [mockDir = path.join(here, '../app/test/mock/source'), dumpDir = path.join(here, '../results/mock/tree')] = args;
if (args.length === 1) { console.error('사용: node mock-tree.mjs [<목업 폴더> <Dart 덤프 폴더>] [--rerun "<명령>"]'); process.exit(2); }

/* 판의 파일 차례 — build.mjs 그대로(themes/order.json의 차례 · 없으면 이름 차례) */
function sources() {
  const tdir = path.join(mockDir, 'themes');
  let order = null;
  try { order = JSON.parse(fs.readFileSync(path.join(tdir, 'order.json'), 'utf8')); } catch { /* 없으면 이름 차례 */ }
  const rank = f => { const i = order ? order.indexOf(f.replace(/\.js$/, '')) : -1; return i < 0 ? 999 : i; };
  const tfiles = fs.readdirSync(tdir).filter(f => f.endsWith('.js')).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
  const out = ['kit.js', 'scene.js', 'render.js', 'themes.js'].map(f => [f, fs.readFileSync(path.join(mockDir, f), 'utf8'), path.join(mockDir, f)]);
  for (const f of tfiles) out.push([`themes/${f}`, `(function () {\n${fs.readFileSync(path.join(tdir, f), 'utf8')}\n})();`, path.join(tdir, f)]);
  return out;
}

/* 판 지문 — Dart 머리말(주석 줄)의 '<이름>.js(sha256 앞 12자)' · '<이름>.js(앞 12자)'와 목업 폴더에서 싣는 파일을 맞춘다 */
function fingerprints() {
  const dartDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../app/lib/mock');
  const want = new Map(), errs = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      if (!e.name.endsWith('.dart')) continue;
      for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
        if (!line.trimStart().startsWith('//')) continue;
        for (const m of line.matchAll(/([\w.-]+\.js)\((?:sha256 )?([0-9a-f]{12})\)/g)) {
          const had = want.get(m[1]), from = path.relative(dartDir, p).replace(/\\/g, '/');
          if (had && had.sha !== m[2]) errs.push(`${m[1]}: 머리말끼리 다름 — ${had.from} ${had.sha} · ${from} ${m[2]}`);
          else if (!had) want.set(m[1], { sha: m[2], from });
        }
      }
    }
  };
  walk(dartDir);
  const got = new Map(sources().map(([name, , file]) => [path.basename(name), crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 12)]));
  for (const [name, sha] of got) {
    const w = want.get(name);
    if (!w) errs.push(`${name}: 목업 폴더에 있으나 옮긴 판(Dart 머리말)에 없음 — ${sha}`);
    else if (w.sha !== sha) errs.push(`${name}: 목업 ${sha} ≠ 옮긴 판 ${w.sha}(${w.from})`);
  }
  for (const [name, w] of want) if (!got.has(name)) errs.push(`${name}: 옮긴 판(${w.from})에 있으나 목업 폴더에 없음`);
  return { n: got.size, errs };
}

/* 연습 갈래 둘(원본에 없음) — s4가 쓰지 않는 t-common 함수(장면 · layoutApp · layoutSeogo · appCells · chain · tieCross · fade 등)도
   원본과 같은 나무를 짓는지 보려고 둔다. app/test/mock/tree_dump_test.dart의 _DrillApp · _DrillSeogo와 같은 꼴(두 쪽을 함께 고칠 것). */
const DRILLS = `(function () {
  const TAG = window.TAG, BASE = window.BASE;
  window.DRILLS = [
    { id: 't-drill-app', M: { top: 128 },
      scene(S) { return TAG.scene(S); },
      frame(S, p, L) { TAG.layoutApp(S, L, this.M); BASE.frame.call(this, S, p, L); },
      object(S, p, o, g) {
        const b = TAG.geom(p, o, g), kind = TAG.kindOf(o);
        const { fill } = TAG.paintTag(this, p, o, b, b.X0, b.Y, b.H - 1, kind, p.band);
        TAG.appCells(this, p, o, b, b.X0 + 4, b.X1 - 4, b.leaderTop, fill);
        TAG.events(this, p, o, b, { lines: [b.lineY(0), b.lineY(1)], lo: b.X0 + 9, hi: b.X1 - 9, rlim: b.X1 - 4 });
      },
    },
    { id: 't-drill-seogo', M: { top: 128, tabH0: 5, tabHS: 20, chainH: 16, gap: 3, trackGap: 4 },
      scene(S) { return TAG.scene(S); },
      frame(S, p, L) { TAG.layoutSeogo(S, L, this.M); BASE.frame.call(this, S, p, L); },
      object(S, p, o, g) {
        const b = TAG.geom(p, o, g), kind = TAG.kindOf(o), head = b.sp.head, ch = b.sp.chain;
        const cd = o.serve ? TAG.card(this, p, o, g, b, b.Y, head - 1, kind) : null;
        TAG.paintTag(this, p, o, b, b.X0, b.Y, head - 1, kind, p.band);
        if (ch) TAG.chain(this, p, o, b, b.Y + head - 1, ch, kind);
        const tie = g.tie = { xe: b.X1 };
        if (!b.cl && !b.short) { tie.hx = TAG.holeX(b, kind); tie.hy = b.Y + TAG.HOLE; TAG.hole(this, p, tie.hx, tie.hy, !!o.selected); }
        if (o.out && !b.cr && !b.short) { tie.dx = b.X1 - 7; tie.dy = b.Y + TAG.HOLE; }
        if (cd) { const tr = Math.min(cd.xr, p.CR) - 8; if (tr - TAG.hostW(this, o.serve) > cd.xs + 30) TAG.hostTab(this, p, cd, tr, cd.cy); }
      },
      link(S, p, a, b, how) { TAG.tieLink(this, p, a, b, how); },
      extra(S, p, L) { TAG.tieCross(this, p, L); },
    },
  ];
})();`;

/* 원본을 돌려 갈래마다 나무 · 값 · 빠진 폭을 얻는다 */
function runJs(widths) {
  class El {
    constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.style = {}; this.textContent = ''; this.inner = null; }
    setAttribute(k, v) { this.attrs[k] = String(v); }
    removeAttribute(k) { delete this.attrs[k]; }
    appendChild(c) { this.children.push(c); return c; }
    set innerHTML(s) { this.inner = String(s); }
  }
  let missing = new Set();
  const ctx = {
    font: '',
    measureText(s) {
      const key = this.font + '|' + s;
      if (key in widths) return { width: widths[key] };
      missing.add(key);
      return { width: 0 };
    },
  };
  const sb = { document: { createElementNS: (ns, tag) => new El(tag), createElement: () => ({ getContext: () => ctx }) }, console };
  sb.window = sb;
  vm.createContext(sb);
  for (const [name, src] of sources()) vm.runInContext(src, sb, { filename: name });
  vm.runInContext(DRILLS, sb, { filename: 'drills' });
  const dump = e => {
    const at = { ...e.attrs };
    if (e.style.fontFamily) at['font-family'] = e.style.fontFamily;
    const o = { tag: e.tag, at };
    if (e.tag === 'text') o.text = String(e.textContent);
    if (e.inner != null) o.inner = e.inner;
    if (e.children.length) o.ch = e.children.map(dump);
    return o;
  };
  // 판 board-s4가 그리는 것 = opt가 있는 갈래 · 그 앞에 기준 방향 · 뒤에 연습 갈래
  const themes = [['base', {}], ...sb.THEMES.filter(t => t.opt).map(t => [t.id, t]), ...sb.DRILLS.map(t => [t.id, t])];
  const out = [];
  for (const [id, theme] of themes) {
    missing = new Set();
    const r = sb.renderScreen(null, theme), parts = sb.renderParts(null, theme), th = r.th;
    const meta = {
      id: th.id, code: th.code ?? null, name: th.name, idea: th.idea ?? null, pro: th.pro ?? null, con: th.con ?? null, rec: !!th.rec, by: th.by ?? null,
      opt: th.opt ?? null, M: th.M, tok: th.tok, layoutRec: (sb.S4_REC || {})[id] ?? null,
    };
    out.push({ id, meta: JSON.parse(JSON.stringify(meta)), screen: dump(r.p.svg), parts: dump(parts), missing: [...missing] });
  }
  return out;
}

/* 견주기 */
/** 자동 번호를 나무 안에서 처음 나온 차례로 다시 매긴 사본(요소는 문서 차례 · 속성은 이름 차례로 훑음 — 두 쪽이 같은 차례로 만남) */
function renumber(tree) {
  const seen = new Map(), count = new Map();
  const to = (p, d) => {
    if (!seen.has(p + d)) { count.set(p, (count.get(p) || 0) + 1); seen.set(p + d, `${p}#${count.get(p)}`); }
    return seen.get(p + d);
  };
  const walk = e => {
    const at = {};
    for (const k of Object.keys(e.at).sort()) {
      const v = e.at[k];
      at[k] = k === 'id' ? v.replace(/^([A-Za-z]+)(\d+)$/, (_, p, d) => to(p, d)) : v.replace(/url\(#([A-Za-z]+)(\d+)\)/g, (_, p, d) => `url(#${to(p, d)})`);
    }
    return e.ch ? { ...e, at, ch: e.ch.map(walk) } : { ...e, at };
  };
  return walk(tree);
}
const inner = ch => (ch || []).map(c => `<${c.tag} ${Object.entries(c.at).map(([k, v]) => `${k}="${v}"`).join(' ')}/>`).join('');
function compareTree(x, y, at, diffs, n) {
  n.el++;
  if (x.tag !== y.tag) { diffs.push(`${at}: 요소 ${x.tag} ≠ ${y.tag}`); return; }
  for (const k of new Set([...Object.keys(x.at), ...Object.keys(y.at)])) {
    n.at++;
    if (x.at[k] !== y.at[k]) diffs.push(`${at}<${x.tag}> @${k}: js=${JSON.stringify(x.at[k])} dart=${JSON.stringify(y.at[k])}`);
  }
  if (x.tag === 'text') n.text++;
  if ((x.text ?? null) !== (y.text ?? null)) diffs.push(`${at}<${x.tag}> 글: js=${JSON.stringify(x.text)} dart=${JSON.stringify(y.text)}`);
  if (x.inner != null) {
    if (x.ch?.length) diffs.push(`${at}<${x.tag}> innerHTML과 자식이 함께 있음`);
    if (x.inner !== inner(y.ch)) diffs.push(`${at}<${x.tag}> 아이콘 속: js=${JSON.stringify(x.inner)} dart=${JSON.stringify(inner(y.ch))}`);
    return;
  }
  const xc = x.ch || [], yc = y.ch || [];
  if (xc.length !== yc.length) diffs.push(`${at}<${x.tag}> 자식 ${xc.length} ≠ ${yc.length}`);
  for (let i = 0; i < Math.min(xc.length, yc.length); i++) compareTree(xc[i], yc[i], `${at}/${i}`, diffs, n);
}
function compareValue(x, y, at, diffs) {
  if (x !== null && y !== null && typeof x === 'object' && typeof y === 'object' && Array.isArray(x) === Array.isArray(y)) {
    for (const k of new Set([...Object.keys(x), ...Object.keys(y)])) compareValue(x[k], y[k], `${at}.${k}`, diffs);
  } else if (x !== y) diffs.push(`${at}: js=${JSON.stringify(x)} dart=${JSON.stringify(y)}`);
}

function once() {
  const wf = path.join(dumpDir, 'widths.json');
  const widths = fs.existsSync(wf) ? JSON.parse(fs.readFileSync(wf, 'utf8')) : {};
  const js = runJs(widths);
  const rows = [], allMissing = new Set();
  let bad = 0;
  // 갈래 목록 — 원본 쪽(기준 방향 + 판 갈래 + 연습)과 Dart가 덤프한 차례가 같아야 한다(한쪽이 적게 실려 거짓 통과하지 않게)
  const jsIds = js.map(t => t.id), idf = path.join(dumpDir, 'ids.json');
  const dartIds = fs.existsSync(idf) ? JSON.parse(fs.readFileSync(idf, 'utf8')) : null;
  const board = jsIds.filter(id => id !== 'base' && !id.startsWith('t-drill')).length;
  const listErr = !dartIds ? `Dart 갈래 목록 없음: ${idf}`
    : JSON.stringify(jsIds) !== JSON.stringify(dartIds) ? `갈래 목록이 다름\n  js   = ${jsIds.join(' ')}\n  dart = ${dartIds.join(' ')}`
      : board < 1 ? '판 갈래가 하나도 실리지 않음' : null;
  if (listErr) bad++;
  const total = { el: 0, at: 0, text: 0 };
  for (const t of js) {
    const f = path.join(dumpDir, `${t.id}.json`), diffs = [];
    const n = { el: 0, at: 0, text: 0 };
    if (!fs.existsSync(f)) diffs.push(`Dart 덤프 없음: ${f}`);
    else {
      const d = JSON.parse(fs.readFileSync(f, 'utf8'));
      compareTree(renumber(t.screen), renumber(d.screen), 'screen', diffs, n);
      compareTree(renumber(t.parts), renumber(d.parts), 'parts', diffs, n);
      compareValue(t.meta, d.meta, 'meta', diffs);
    }
    t.missing.forEach(k => allMissing.add(k));
    if (diffs.length || t.missing.length) bad++;
    for (const k of ['el', 'at', 'text']) total[k] += n[k];
    rows.push({ id: t.id, n, diffs, missing: t.missing.length });
  }
  return { rows, allMissing, bad, total, listErr, board };
}

const fp = fingerprints();
if (fp.errs.length) {
  console.log(`판 지문이 옮긴 판과 다름 — 견주지 않음(${mockDir})`);
  for (const e of fp.errs) console.log('  ' + e);
  process.exit(1);
}
console.log(`판 지문: 목업 파일 ${fp.n}개가 옮긴 판(Dart 머리말)과 같음`);

let res;
for (let round = 1; ; round++) {
  res = once();
  if (!res.allMissing.size) break;
  const qf = path.join(dumpDir, 'queries.json');
  const old = fs.existsSync(qf) ? JSON.parse(fs.readFileSync(qf, 'utf8')) : [];
  fs.writeFileSync(qf, JSON.stringify([...new Set([...old, ...res.allMissing])]));
  if (!rerun || round >= 5) break;
  console.log(`빠진 글 폭 ${res.allMissing.size} — queries.json에 모으고 Dart 덤프를 다시 돌림(${round})`);
  execSync(rerun, { stdio: 'inherit', shell: true });
}

console.log(res.listErr ? `갈래 목록: ${res.listErr}` : `갈래 목록: 기준 방향 + 판 ${res.board} + 연습 — Dart 덤프(ids.json)와 차례까지 같음`);
console.log('갈래\t요소\t속성\t글\tdiffs\tmissing');
for (const r of res.rows) {
  console.log(`${r.id}\t${r.n.el}\t${r.n.at}\t${r.n.text}\t${r.diffs.length}\t${r.missing}`);
  for (const d of r.diffs.slice(0, 20)) console.log('  ' + d);
  if (r.diffs.length > 20) console.log(`  … 그 밖 ${r.diffs.length - 20}`);
}
const nd = res.rows.reduce((a, r) => a + r.diffs.length, 0);
const drills = res.rows.filter(r => r.id.startsWith('t-drill')).length;
console.log(`갈래 ${res.rows.length - drills} + 연습 ${drills} · 요소 ${res.total.el} · 속성 ${res.total.at} · 글 ${res.total.text} · diffs ${nd} · missing ${res.allMissing.size}`);
if (res.allMissing.size) console.log(`빠진 글 폭 ${res.allMissing.size}개를 ${path.join(dumpDir, 'queries.json')}에 모았음 — Dart 덤프(tree_dump_test.dart)를 다시 돌린 뒤 다시 견줄 것`);
process.exit(res.bad ? 1 : 0);

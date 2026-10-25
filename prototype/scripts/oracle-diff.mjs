// 정답지 견주기(P3 과제 4) — 손질 전 · 뒤에 뽑은 정답지 폴더 둘을 자료마다 견줘, 다른 경로와 그 값(전 → 뒤)을 적는다.
// 웹 코드 · 내보내기 모듈을 손질한 커밋(예: 글 비교를 UTF-16 차례로 바꾼 것)이 정답지의 어디를 바꾸는지 목록으로 남기려고 쓴다. 정답지 파일은 읽기만 한다.
//
// 사용(작업 폴더에서):
//   node prototype/scripts/layout-oracle.mjs                                     # 손질 전 정답지
//   mv prototype/results/oracle prototype/results/oracle-before                  # 따로 둔다
//   …손질…; node prototype/scripts/layout-oracle.mjs                              # 손질 뒤 정답지
//   node prototype/scripts/oracle-diff.mjs oracle-before oracle [--only=<자료>,…] [--max=<파일마다 적을 경로 수>] [--shapes]
//     폴더 이름은 그대로 열리면 그 폴더, 아니면 prototype/results/<이름>. 자료 폴더 안의 *.json을 같은 이름끼리 견준다.
//     --only    자료 이름을 골라 견줌(없으면 두 폴더에 있는 모든 자료)
//     --max     파일마다 적는 다른 경로의 수(기본 12 — 나머지는 개수로만)
//     --shapes  다른 경로를 모양(순번을 *로)별로 묶어 개수를 적음 — 한 가지 고침이 퍼뜨린 곳을 한눈에
// 같음의 기준: JSON 트리가 값 · 배열 순서 · 열쇠 모두 같고(수는 f64로 정확히 — JSON.parse가 읽은 그대로), 열쇠 **차례**도 같아야 같다(덤프 규칙이 JS 열쇠 차례를 적는다).
// 머리 `$oracle`(시각 · 시간대 · 원본 SHA)은 따로 견줘 알린다 — 다르면 '머리만 다름' 경고(경로 수에 넣지 않음 · 합계 줄에 경고로 셈).
// 종료 코드: 0 = 견준 파일이 있고 모두 같음 · 1 = 다른 경로 · 한쪽에만 있는 자료/파일이 있음 · 2 = 사용 잘못, 또는 **빈 견줌**(자료가 0개이거나 견준 파일이 0개인 자료가 있음 — 빈 입력은 '같음'이 아니다).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const results = path.resolve(here, '..', 'results');
const die = msg => { console.error(`oracle-diff: ${msg}`); process.exit(2); };

const positional = process.argv.slice(2).filter(a => !a.startsWith('--'));
const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));
for (const k of Object.keys(args)) if (!['only', 'max', 'shapes'].includes(k)) die(`모르는 인자 --${k} (only · max · shapes)`);
if (positional.length !== 2) die('사용: node prototype/scripts/oracle-diff.mjs <전 폴더> <뒤 폴더> [--only=<자료>,…] [--max=<n>] [--shapes]');
for (const k of ['only', 'max']) if (args[k] !== undefined && !args[k]) die(`--${k}에 값이 없습니다 (--${k}=<값>)`);
if (args.shapes) die(`--shapes는 값 없이 씁니다 (받은 값: ${args.shapes})`);
const max = args.max === undefined ? 12 : Number(args.max);
if (!Number.isInteger(max) || max < 0) die(`--max는 0 이상의 정수여야 합니다: ${args.max}`);
const csv = text => (text || '').split(',').map(s => s.trim()).filter(Boolean);
if (args.only !== undefined && !csv(args.only).length) die(`--only에 자료 이름이 없습니다: ${args.only}`);

const dirOf = name => {
  const direct = path.resolve(name);
  if (fs.existsSync(direct) && fs.statSync(direct).isDirectory()) return direct;
  const under = path.join(results, name);
  if (fs.existsSync(under) && fs.statSync(under).isDirectory()) return under;
  return die(`폴더가 없습니다: ${name} (cwd 기준과 prototype/results/ 아래를 찾았습니다)`);
};
const [beforeDir, afterDir] = positional.map(dirOf);
if (beforeDir === afterDir) die('같은 폴더를 견줄 수 없습니다');

const subdirs = dir => fs.readdirSync(dir, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort();
const jsonFiles = dir => fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort();

const kind = v => (v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v);
/** 다른 경로를 모은다(경로는 열쇠 · 순번을 '.'로 이은 것 — 맨 위는 빈 글). 모양이 다르면 그 자리에서 멈춘다(안쪽까지 내려가지 않음). */
function walk(a, b, p, out) {
  const ka = kind(a);
  const kb = kind(b);
  if (ka !== kb) { out.push({ p, a, b, why: '꼴' }); return; }
  if (ka === 'array') {
    if (a.length !== b.length) out.push({ p: p ? `${p}.length` : 'length', a: a.length, b: b.length, why: '길이' });
    const n = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) walk(a[i], b[i], p ? `${p}.${i}` : String(i), out);
    return;
  }
  if (ka === 'object') {
    const ak = Object.keys(a);
    const bk = Object.keys(b);
    for (const k of ak) if (!(k in b)) out.push({ p: p ? `${p}.${k}` : k, a: a[k], b: undefined, why: '뒤에서 빠짐' });
    for (const k of bk) if (!(k in a)) out.push({ p: p ? `${p}.${k}` : k, a: undefined, b: b[k], why: '뒤에서 더해짐' });
    for (const k of ak) if (k in b) walk(a[k], b[k], p ? `${p}.${k}` : k, out);
    const ac = ak.filter(k => k in b);
    const bc = bk.filter(k => k in a);
    if (ac.some((k, i) => k !== bc[i])) out.push({ p, a: ac, b: bc, why: '열쇠 차례' });
    return;
  }
  if (!Object.is(a, b)) out.push({ p, a, b, why: '값' });
}

const show = v => {
  if (v === undefined) return '(없음)';
  const s = JSON.stringify(v);
  return s.length > 70 ? `${s.slice(0, 67)}…` : s;
};
const shapeOf = p => p.replace(/(^|\.)\d+(?=\.|$)/g, '$1*');

const onlyNames = csv(args.only);
const beforeSets = subdirs(beforeDir);
const afterSets = subdirs(afterDir);
const names = [...new Set([...beforeSets, ...afterSets])].sort().filter(n => !onlyNames.length || onlyNames.includes(n));
for (const n of onlyNames) if (!beforeSets.includes(n) && !afterSets.includes(n)) die(`두 폴더 어디에도 없는 자료: ${n}`);
/* 빈 견줌은 '같음'이 아니다 — 자료 폴더가 하나도 없으면(빈 폴더 · 자료 폴더 하나를 넘김) 가짜 0이 나오지 않게 여기서 멈춘다 */
if (!names.length) {
  for (const [label, dir, sets] of [['전', beforeDir, beforeSets], ['뒤', afterDir, afterSets]]) {
    if (!sets.length) console.error(`oracle-diff: ${label} 폴더에 자료 폴더가 없습니다${jsonFiles(dir).length ? ' — .json 파일이 바로 들어 있습니다(자료 폴더 하나를 넘긴 듯합니다. 자료 폴더들이 든 윗단계를 넘기세요)' : ''}: ${dir}`);
  }
  die('견줄 자료가 0개입니다 — 빈 견줌은 같음이 아닙니다');
}

let sameSets = 0;
let diffPaths = 0;
let diffSets = 0;
let missing = 0;
let headers = 0;
let comparedTotal = 0;
let emptySets = 0;
console.log(`전: ${beforeDir}\n뒤: ${afterDir}`);
for (const name of names) {
  if (!beforeSets.includes(name) || !afterSets.includes(name)) {
    console.log(`자료 ${name} — ${beforeSets.includes(name) ? '뒤' : '전'} 폴더에 없음`);
    missing++;
    continue;
  }
  const bd = path.join(beforeDir, name);
  const ad = path.join(afterDir, name);
  const bf = jsonFiles(bd);
  const af = jsonFiles(ad);
  const lines = [];
  let count = 0;
  let headerOnly = 0;
  let compared = 0;
  for (const f of [...new Set([...bf, ...af])].sort()) {
    if (!bf.includes(f) || !af.includes(f)) {
      lines.push(`  ${f}: ${bf.includes(f) ? '뒤' : '전'}에 없는 파일`);
      missing++;
      continue;
    }
    compared++;
    const bt = fs.readFileSync(path.join(bd, f), 'utf8');
    const at = fs.readFileSync(path.join(ad, f), 'utf8');
    if (bt === at) continue;
    const bj = JSON.parse(bt);
    const aj = JSON.parse(at);
    const { $oracle: bh, ...brest } = bj;
    const { $oracle: ah, ...arest } = aj;
    const diffs = [];
    walk(brest, arest, '', diffs);
    const headerDiffers = JSON.stringify(bh) !== JSON.stringify(ah);
    if (!diffs.length) {
      if (headerDiffers) { lines.push(`  ${f}: 머리($oracle)만 다름 — ${show(bh)} → ${show(ah)}`); headerOnly++; headers++; }
      else { lines.push(`  ${f}: 트리는 같고 글자(들여쓰기 · 수 글 …)만 다름`); count++; }
      continue;
    }
    count += diffs.length;
    lines.push(`  ${f}: 다른 경로 ${diffs.length}곳${headerDiffers ? ' (머리도 다름)' : ''}`);
    if (args.shapes !== undefined) {
      const by = new Map();
      for (const d of diffs) by.set(shapeOf(d.p), (by.get(shapeOf(d.p)) || 0) + 1);
      for (const [s, n] of [...by].sort((x, y) => y[1] - x[1])) lines.push(`    ${s} × ${n}`);
    }
    for (const d of diffs.slice(0, max)) lines.push(`    ${d.p || '(루트)'} [${d.why}]: ${show(d.a)} → ${show(d.b)}`);
    if (diffs.length > max) lines.push(`    … ${diffs.length - max}곳 더`);
  }
  comparedTotal += compared;
  if (!compared) {
    emptySets++;
    console.log(`자료 ${name} — 견준 파일 0개 (전 ${bf.length}개 · 뒤 ${af.length}개의 .json 가운데 이름이 같은 것이 없음) — 같음이 아니라 빈 견줌`);
    for (const l of lines) console.log(l);
  } else if (!count && !lines.some(l => l.includes('없는 파일'))) {
    sameSets++;
    console.log(`자료 ${name} — 같음 (견준 파일 ${compared}개${headerOnly ? ` · 경고: 머리($oracle)만 다른 ${headerOnly}개` : ''})`);
    for (const l of lines) console.log(l);
  } else {
    diffSets++;
    diffPaths += count;
    console.log(`자료 ${name} — 다름 (${count}곳)`);
    for (const l of lines) console.log(l);
  }
}
console.log(`합계: 자료 ${names.length}개 · 견준 파일 ${comparedTotal}개 · 같은 자료 ${sameSets} · 다른 자료 ${diffSets} · 다른 경로 ${diffPaths}곳 · 한쪽에만 있는 것 ${missing}` + (emptySets ? ` · 빈 견줌 ${emptySets}` : '') + (headers ? ` · 경고(머리 $oracle만 다른 파일) ${headers}개` : ''));
if (emptySets || !comparedTotal) die(`견준 파일이 0개인 자료가 ${emptySets}개 있습니다 — 빈 견줌은 같음이 아닙니다`);
process.exit(diffPaths || missing ? 1 : 0);

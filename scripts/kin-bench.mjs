/* 계보 측정 (D1-T) — 가상 대가족(scripts/kin-sample.mjs)으로 모델 · 계보 뼈대 · 승계표 · 세계표 · 메이커 고침을 잽니다.
   기준: D1 확정 설계(docs/설계-10건/ 의 '1-2 … 가문-확정.md') 6-1 합격선 · 6-2 예산 · 6-4 잰 근거 · 6-5 ②. timeline-bench.mjs의 틀.

   ① 모델(노드 — 브라우저 없음)
      node scripts/kin-bench.mjs --model [--core <core.js>] [--calendar <calendar.js>] [--runs 3] [--out <결과 폴더>] [--tag <이름>] [--part 가,나,다,라,마] [--big] [--stub] [--quick]
      * --core: 잴 core.js(기본 js/core.js). 시작 커밋의 코드를 재려면 git show <커밋>:js/core.js 를 임시 폴더에 꺼내 그 경로를 줍니다.
      * 재는 것: normalizePack · buildModel(판 넷 · 1만) · 동아시아 기본팩에 더할 때의 늘어남 · 2만 → 5만 · 고리 있음/없음 · familyOf(본가 · 파 포함)
        · 계보 뼈대(HT.kinSkeleton · kinDefaultOpen · kinLayout · successionRows · kinRecord — 있을 때만, 5만) · 보이는 것 고르기(이분 탐색)
      * 판정: 6-1 '모델 · 메이커 다시 짓기'(계보 전용 1만(id)을 더해도 buildModel + ≤ 150ms · 이름 참조 ≤ id 참조 × 1.2 · 2만 → 5만 ≤ 3배 · 고리 1건 ≤ 고리 없음 × 1.2)
        · '자리 셈'(5만: 접기 1회 ≤ 2ms · 보이는 것 고르기 ≤ 0.1ms) · '모두 펼침 줄 수 ≤ 사람 + 지도자' · 6-2 '뼈대 짓기 처음 ≤ 30ms'
        · 6-4 재현(이름 참조 1만이 id 참조보다 몇 배 · 3초대인지)
      * 계보 전용(lineageOnly)을 읽지 못하는 코드(형식 3 D1 이전)에서는 날짜 없는 계보 전용 인물이 오류로 빠지므로, 선형 · 고리 · 더하기 판정을 띠 인물 판으로 잽니다(결과에 적음).
      * --stub: 뼈대 도우미가 없을 때 이 파일 안의 대역(생성기가 아는 나무로 지은 뼈대 · 설계 4-4 정수 칸 셈 · 3-4 줄 규칙)으로 측정 길을 끝까지 돌려 봅니다(수치는 '대역').
        도우미가 있으면 대역 칸 셈(설계 4-4를 그대로 옮긴 것)을 진짜 HT.kinLayout과 같은 뼈대 · 같은 펼침에 돌려 정수가 같은지 견줍니다(대조).
      * --big: 20만도 · --quick: 1만까지만(2만 · 5만 · 고리 빼고) · --runs: 되풀이 수(중앙값) · --part: (가) 판 넷 1만 (나) 기본팩에 더하기 (다) 2만 → 5만 · 고리
        (라) familyOf (마) 계보 뼈대 가운데 고른 것만 · --tag: 결과 파일 이름 꼬리
      * 시간: 벽시계와 CPU 시간을 함께 적고, 20ms 넘는 일은 둘 가운데 작은 값으로 판정합니다(여러 작업자가 CPU를 나눠 쓰는 상자에서 벽시계가 부풀므로).
        처음에 '기계 빠르기 눈금'(늘 같은 일의 CPU ms)과 부하를 적어, 다른 때 · 다른 기계의 결과를 나눠 견줄 수 있게 합니다.
   ② 브라우저(Playwright · 1920×1080 · 배율 1 · reducedMotion 'no-preference' — 움직임을 재므로)
      HT_BROWSER=chromium HT_PLAYWRIGHT_ROOT=… node scripts/kin-bench.mjs <검사할 폴더> <결과 폴더> [--size 50000] [--maker-size 10000] [--only 승계표,세계표,메이커]
      구간 1 승계표: 열기 → 모두 펼치기 → 끝까지 밀기(휠 12칸씩) → 접기 · 펼치기 20회(400ms 간격)
      구간 2 세계표: 열기 → 8방향 끌기 + 관성 → 접기 20회 → 찾아 데려오기 → 전체도 누르기
      구간 3 메이커 칸 고침 3회(작업본 = 가상 대가족 --maker-size명 · 편집 창에서 지도자 줄의 메모 칸을 고치고 저장 → 모델 다시 짓기)
      기록: rAF 간격(놓침 = 1.5T 넘음 · T는 처음 1초 쉬는 동안의 중앙값) · 연달아 놓침 · 50ms 넘는 장면 · long-animation-frame / longtask 50ms 이상 수
            · 창 안 요소 수 · 모델 짓기 시간. 판정은 6-1(놓침 ≤ 1% · 연달아 0 · 50ms 넘는 장면 0 · 창 안 요소 ≤ 400 · 긴 장면 0).
      승계표 · 세계표 창(D1-W2)이 아직 없으면 그 구간은 '건너뜀'으로 적습니다. 클라우드 headless는 rAF가 60Hz라 144Hz 판정은 감독 PC에서(D1-G) —
      HT_HEADED=1이면 창을 띄워 잽니다(창이 가려지거나 다른 프로그램이 돌면 놓침이 생겨 측정이 무효).
   자료는 메모리 · 시험 창에만 두고, packs/ · samples/ 지문(sha256)을 처음과 끝에 견줍니다. 결과는 <결과 폴더>/계보-모델-측정.json · 계보-화면-측정.json(+ 1배 그림). */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { kinSample, fingerprint, SEED } from './kin-sample.mjs';

const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] != null ? args[i + 1] : def;
};
const has = name => args.includes(name);
const median = a => {
  const b = a.slice().sort((x, y) => x - y);
  return b.length ? b[Math.floor((b.length - 1) / 2)] : NaN;
};
const r1 = v => (v == null || Number.isNaN(v) ? null : Math.round(v * 10) / 10);
const r3 = v => (v == null || Number.isNaN(v) ? null : Math.round(v * 1000) / 1000);

/* ---------- 대역: 생성기가 아는 나무로 지은 계보 뼈대 (설계 2-4 아의 꼴 — par · size · gen · bits · key …) ---------- */
const TREE_RANK = { 생부: 0, 부: 1, '': 2, 양부: 3, 후손: 4, 양모: 5, 생모: 6, 모: 6 };
export function standInSkeleton(sample) {
  const { persons, cells } = sample.tree;
  const lineage = sample.pack.figures.some(f => f.lineageOnly);
  const inSet = p => p.kind === 'leader' || p.kind === 'member' || p.kind === 'outer';
  const nodes = persons.filter(inSet);
  const twin = new Set(cells.filter(c => c.plan === '두 나라').map(c => c.p));
  const pick = new Map(); // 사람 → { parent, row }
  const kids = new Map();
  const side = new Set();
  const warnings = [];
  for (const p of nodes) {
    const rows = p.parents.filter(x => x.p && inSet(x.p) && x.p.i < p.i); // 뒤에 지은 사람을 부모로 적은 줄(고리)은 넣지 않고 경고
    for (const x of p.parents) if (x.p && inSet(x.p) && x.p.i >= p.i) warnings.push(`고리: ${p.name} ← ${x.p.name}`);
    if (!rows.length) continue;
    rows.sort((a, b) => (TREE_RANK[a.as] ?? 7) - (TREE_RANK[b.as] ?? 7));
    pick.set(p, rows[0]);
    if (rows.length > 1) side.add(p);
    (kids.get(rows[0].p) || kids.set(rows[0].p, []).get(rows[0].p)).push(p);
  }
  const birthOf = p => p.birth;
  const cellStart = p => (p.kind === 'leader' ? cells.find(c => c.p === p).start : Infinity);
  const order = (a, b) => (a.sib ?? 1e9) - (b.sib ?? 1e9) || birthOf(a) - birthOf(b) || cellStart(a) - cellStart(b) || a.i - b.i;
  const roots = nodes.filter(p => !pick.has(p)).sort(order);
  const n = nodes.length;
  const par = new Int32Array(n), size = new Int32Array(n), gen = new Int32Array(n), bits = new Int32Array(n);
  const at = new Map();
  const name = new Array(n), key = new Array(n);
  let k = 0;
  const stack = roots.slice().reverse().map(p => [p, -1]);
  while (stack.length) {
    const [p, up] = stack.pop();
    const i = k++;
    at.set(p, i);
    par[i] = up;
    const row = pick.get(p);
    gen[i] = up < 0 ? 0 : gen[up] + (row && row.gen ? row.gen : 1);
    bits[i] = (p.kind !== 'outer' ? 1 : 0) | (p.unknown ? 2 : 0) | (side.has(p) ? 8 : 0) | (p.pa ? 16 : 0) | (p.kind === 'leader' ? 32 : 0) | (lineage && p.kind !== 'leader' ? 64 : 0) | (twin.has(p) ? 256 : 0);
    name[i] = p.name;
    key[i] = p.kind === 'leader' ? `c:${sample.pack.id}/${sample.tree.polity.id}|leader:${p.cell}` : `f:${sample.pack.id}/${p.id}`;
    const ch = (kids.get(p) || []).slice().sort(order);
    for (let c = ch.length - 1; c >= 0; c--) stack.push([ch[c], i]);
  }
  for (let i = n - 1; i >= 0; i--) {
    size[i] += 1;
    if (par[i] >= 0) size[par[i]] += size[i];
  }
  const leaderAt = cells.map(c => at.get(c.p));
  return { key: `kin:${sample.tree.root}`, n, par, size, gen, bits, name, key, warnings, leaderAt, standIn: true };
}

/* ---------- 정수 칸 셈 — 설계 4-4를 그대로 옮긴 것(대역 · 대조용). 돌려주는 꼴은 HT.kinLayout과 같음 ---------- */
export function refLayout(skel, open) {
  const { n, par, size, gen, bits } = skel;
  const w = new Int32Array(n), x = new Int32Array(n), left = new Int32Array(n), sum = new Int32Array(n), next = new Int32Array(n);
  const first = new Int32Array(n).fill(-1), last = new Int32Array(n).fill(-1);
  const vis = [];
  for (let i = 0; i < n; ) {
    vis.push(i);
    i += open[i] ? 1 : size[i];
  }
  const side = i => ((bits[i] & 8) !== 0 ? 1 : 0);
  const showsKids = i => open[i] && size[i] > 1;
  for (let k = vis.length - 1; k >= 0; k--) {
    const i = vis[k];
    w[i] = showsKids(i) ? side(i) + sum[i] : 4 + side(i);
    if (par[i] >= 0) sum[par[i]] += w[i];
  }
  let rootCursor = 0;
  for (const i of vis) {
    if (par[i] < 0) {
      left[i] = rootCursor;
      rootCursor += w[i];
    } else {
      left[i] = next[par[i]];
      next[par[i]] += w[i];
    }
    next[i] = left[i] + side(i);
  }
  for (let k = vis.length - 1; k >= 0; k--) {
    const i = vis[k];
    x[i] = showsKids(i) ? Math.floor((x[first[i]] + x[last[i]]) / 2) : left[i] + side(i) + 2;
    const p = par[i];
    if (p >= 0) {
      if (last[p] < 0) last[p] = i;
      first[p] = i;
    }
  }
  let gens = 0;
  for (const i of vis) gens = Math.max(gens, gen[i] + 1);
  const count = new Int32Array(gens);
  for (const i of vis) count[gen[i]]++;
  const rows = Array.from(count, c => new Int32Array(c));
  const fill = new Int32Array(gens);
  for (const i of vis) rows[gen[i]][fill[gen[i]]++] = i;
  return { x, w, rows, width: rootCursor };
}

/* 대역 기본 펼침(설계 4-5): 200명 이하 모두 · 넘으면 지도자 · 그 조상 펼침(자녀 1대가 보임) · 파조는 접힘 · 지도자가 없으면 위 3세대 */
export function refDefaultOpen(skel) {
  const { n, par, gen, bits } = skel;
  const open = new Uint8Array(n);
  if (n <= 200) return open.fill(1);
  let leaders = 0;
  for (let i = 0; i < n; i++) if (bits[i] & 32) {
    leaders++;
    for (let a = i; a >= 0 && !open[a]; a = par[a]) open[a] = 1;
  }
  if (!leaders) for (let i = 0; i < n; i++) open[i] = gen[i] < 2 ? 1 : 0;
  for (let i = 0; i < n; i++) if ((bits[i] & 16) && !(bits[i] & 32)) open[i] = 0;
  return open;
}

/* 대역 승계표 줄(설계 3-4) — Int32Array [갈래(0 지도자 · 1 사람 · 2 건너뛰기), 번호(지도자는 칸 번호 · 그 밖은 뼈대 번호), 들여쓰기] × 줄 */
export function refSuccessionRows(skel, open) {
  const out = [];
  const leaderNodes = new Set(skel.leaderAt);
  const seen = new Set();
  skel.leaderAt.forEach((s, m) => {
    out.push(0, m, 0);
    if (s == null || seen.has(s) || !open[s]) return;
    seen.add(s);
    for (let j = s + 1; j < s + skel.size[s]; ) {
      const ind = Math.min(skel.gen[j] - skel.gen[s], 8);
      if (leaderNodes.has(j)) {
        out.push(2, j, ind);
        j += skel.size[j];
      } else {
        out.push(1, j, ind);
        j += open[j] ? 1 : skel.size[j];
      }
    }
  });
  return Int32Array.from(out);
}

/** 보이는 것 고르기(세계표) — 세대마다 rows[g]를 화면 x 범위(칸 단위)로 이분 탐색. 돌려주는 값 = 보이는 카드 수 */
function pickVisible(lay, g0, g1, u0, u1) {
  let count = 0;
  for (let g = g0; g <= g1 && g < lay.rows.length; g++) {
    const row = lay.rows[g];
    let lo = 0, hi = row.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (lay.x[row[mid]] + 2 < u0) lo = mid + 1;
      else hi = mid;
    }
    for (let k = lo; k < row.length && lay.x[row[k]] - 2 <= u1; k++) count++;
  }
  return count;
}

/* ---------- ① 모델 ---------- */
async function modelBench() {
  if (!globalThis.gc && !process.execArgv.includes('--expose-gc')) {
    const r = spawnSync(process.execPath, ['--expose-gc', '--max-old-space-size=6144', fileURLToPath(import.meta.url), ...args], { stdio: 'inherit' });
    process.exit(r.status ?? 1);
  }
  const corePath = path.resolve(opt('--core', path.join(here, 'js/core.js')));
  const calPath = path.resolve(opt('--calendar', path.join(here, 'js/calendar.js')));
  const runs = Math.max(1, Number(opt('--runs', 3)));
  const out = path.resolve(opt('--out', path.join(here, '배포/측정/계보-성능')));
  const big = has('--big'), quick = has('--quick'), stub = has('--stub');
  const parts = new Set(String(opt('--part', '가,나,다,라,마')).split(','));
  const before = fingerprint(here);
  /* 노드에서 core.js를 돌릴 바탕(dev-smoke와 같은 꼴) */
  const noop = () => {};
  const el = () => ({ style: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false }, appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop, querySelector: () => null, querySelectorAll: () => [], getContext: () => ({ measureText: t => ({ width: String(t).length * 7 }) }) });
  const g = globalThis;
  g.window = g;
  g.document = { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop, removeEventListener: noop, getAnimations: () => [] };
  const store = new Map();
  g.localStorage = { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
  g.matchMedia = () => ({ matches: false, addEventListener: noop, addListener: noop });
  g.getComputedStyle = () => ({ getPropertyValue: () => '' });
  g.requestAnimationFrame = cb => setTimeout(() => cb(Date.now()), 0);
  g.cancelAnimationFrame = id => clearTimeout(id);
  if (!g.navigator) g.navigator = { userAgent: 'node' };
  vm.runInThisContext(fs.readFileSync(calPath, 'utf8'), { filename: calPath });
  vm.runInThisContext(fs.readFileSync(corePath, 'utf8'), { filename: corePath });
  const HT = g.HT;
  for (const m of fs.readFileSync(path.join(here, 'index.html'), 'utf8').matchAll(/<script src="(packs\/[^"]+)"/g)) vm.runInThisContext(fs.readFileSync(path.join(here, m[1]), 'utf8'), { filename: m[1] });
  const basePacks = HT.getBuiltinPacks().map(raw => HT.normalizePack(raw).pack).filter(Boolean);

  const helpers = ['kinSkeleton', 'kinDefaultOpen', 'kinLayout', 'successionRows', 'kinOf', 'kinRecord'].filter(k => typeof HT[k] === 'function');
  const probe = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 3, id: 'kin-probe', name: '확인', tracks: [{ id: 't', name: '가' }], figures: [{ id: 'a', track: 't', name: '가', lineageOnly: true }] });
  const lineageOk = !!(probe.pack && !probe.errors.length && (probe.pack.figures || []).some(f => f.lineageOnly));
  const K = lineageOk ? 'lineage' : 'band';
  const report = { 기준: corePath, 씨앗: SEED, 되풀이: runs, 도우미: helpers, 계보전용읽기: lineageOk, 판정판: K === 'lineage' ? '계보 전용' : '띠 인물(계보 전용을 읽지 못하는 코드)', 결과: [], 판정: [], 오류: [] };
  const log = (...a) => console.log(...a);
  log(`코어: ${path.relative(here, corePath) || corePath} · 계보 전용 읽기 ${lineageOk ? '됨' : '안 됨(형식 3 D1 이전)'} · 도우미 ${helpers.length ? helpers.join(' · ') : '없음'}${stub ? ' · 대역 켬' : ''}`);
  const gc = () => globalThis.gc && globalThis.gc();
  /* 기계 빠르기 눈금: 늘 같은 일(정수 20만 정렬 · 글 열쇠 Map 20만)의 CPU ms — 다른 때 · 다른 기계의 결과를 견줄 때 나눔(눈금 100ms 기준으로 고친 값을 함께 적음) */
  {
    const one = () => {
      const c0 = process.cpuUsage();
      const a = Int32Array.from({ length: 200000 }, (_, i) => (i * 7919 + SEED) % 1000003).sort();
      const m = new Map();
      for (let i = 0; i < 200000; i++) m.set(`k${a[i]}`, i);
      const d = process.cpuUsage(c0);
      return (d.user + d.system) / 1000 + (m.size > 0 ? 0 : 1);
    };
    one();
    report.눈금ms = r1(median([one(), one(), one(), one(), one()]));
    log(`기계 빠르기 눈금 ${report.눈금ms}ms(CPU · 작을수록 빠름) · 부하 ${(await import('node:os')).loadavg().map(v => v.toFixed(1)).join(' / ')}`);
  }
  /* 벽시계와 CPU 시간을 함께 잽니다. 이 상자는 여러 작업자가 CPU를 나눠 써서 긴 일의 벽시계가 부풀므로, 20ms 넘는 일은 둘 가운데 작은 값을 ms로 하고
     (짧은 일은 CPU 시간의 눈금이 거칠어 벽시계 그대로) 둘 다 적습니다. warm = 세지 않고 먼저 돌리는 수(JIT 데우기 — 첫 실행은 first에 따로) */
  const time = (fn, n = runs, warm = 0) => {
    const t = [], c = [];
    let v;
    let first = null;
    for (let r = 0; r < warm; r++) {
      const t0 = performance.now();
      v = fn();
      if (first == null) first = performance.now() - t0;
    }
    for (let r = 0; r < n; r++) {
      gc();
      const c0 = process.cpuUsage();
      const t0 = performance.now();
      v = fn();
      t.push(performance.now() - t0);
      const d = process.cpuUsage(c0);
      c.push((d.user + d.system) / 1000);
    }
    const wall = median(t), cpu = median(c);
    const pick = (a, b) => (a > 20 ? Math.min(a, b) : a);
    return { ms: pick(wall, cpu), wall, cpu, first: first ?? pick(t[0], c[0]), all: t.map(r1), v };
  };
  /** 사람 잇기 · 혈연 경고(model.peopleWarnings — 없으면 model.warnings)의 글 */
  const warnOf = m => (m.peopleWarnings || m.warnings || []).map(w => (typeof w === 'string' ? w : w.msg || ''));
  const cache = new Map();
  const sample = (size, kind, o = {}) => {
    const k = `${size}|${kind}|${o.cycle !== false}|${o.house || 'written'}`;
    if (!cache.has(k)) cache.set(k, kinSample({ size, kind, ...o }));
    return cache.get(k);
  };
  const norm = s => {
    const raw = JSON.parse(s.json);
    const t = time(() => HT.normalizePack(JSON.parse(JSON.stringify(raw))), Math.min(runs, 2));
    return { ms: t.ms, r: t.v };
  };
  const row = o => {
    report.결과.push(o);
    log(`  ${o.무엇}${o.판 ? ` [${o.판}]` : ''}${o.크기 ? ` ${o.크기.toLocaleString('ko-KR')}` : ''}: ${Object.entries(o).filter(([k]) => !['무엇', '판', '크기'].includes(k)).map(([k, v]) => `${k} ${typeof v === 'object' ? JSON.stringify(v) : v}`).join(' · ')}`);
  };
  /* 대역으로 잰 것은 합격선에 견주지 않고 '참고'로만 적습니다(측정 길이 끝까지 도는지 보는 몫) */
  const judge = (what, ok, detail) => {
    const ref = detail && detail.쓴것 === '대역';
    report.판정.push({ 무엇: what, 통과: ref ? null : ok, ...(ref ? { 참고: '대역 — 합격선에 견주지 않음' } : {}), ...detail });
    log(`  ${ref ? '참고(대역)' : ok ? '통과' : '넘음'} — ${what} ${JSON.stringify(detail)}`);
  };

  /* (가) 판 넷 · 1만 — 읽기 · 모델(6-4 첫 줄 재현: 이름 참조가 이차) */
  const built = {};
  if (parts.has('가')) log('(가) 판 넷 · 1만');
  for (const kind of parts.has('가') ? ['band-id', 'band-name', 'lineage-id', 'lineage-name'] : []) {
    const s = sample(10000, kind);
    const nz = norm(s);
    if (!nz.r.pack) {
      row({ 무엇: '읽기 실패', 판: kind, 오류: nz.r.errors.slice(0, 3).map(e => e.msg) });
      continue;
    }
    const m = time(() => HT.buildModel([nz.r.pack], null));
    built[kind] = { ms: m.ms, model: m.v, pack: nz.r.pack };
    row({ 무엇: '읽기 · 모델', 판: kind, 크기: 10000, 바이트: Buffer.byteLength(s.json), 읽기ms: r1(nz.ms), 오류: nz.r.errors.length, 경고: nz.r.warnings.length, 모델ms: r1(m.ms), 벽시계ms: r1(m.wall), CPUms: r1(m.cpu), 벽시계전부: m.all, 띠인물: (m.v.figures || []).length, 계보전용: (m.v.lineageFigures || []).length, 사람경고: warnOf(m.v).length, 사람경고보기: warnOf(m.v).slice(0, 2) });
  }
  const pair = K === 'lineage' ? ['lineage-id', 'lineage-name'] : ['band-id', 'band-name'];
  if (built[pair[0]] && built[pair[1]]) {
    const ratio = built[pair[1]].ms / built[pair[0]].ms;
    judge('이름 참조 ≤ id 참조 × 1.2 (1만 · buildModel)', ratio <= 1.2, { 판: pair.join(' / '), id참조ms: r1(built[pair[0]].ms), 이름참조ms: r1(built[pair[1]].ms), 배: r3(ratio) });
    if (built['band-id'] && built['band-name'])
      row({
        무엇: `6-4 첫 줄 ${lineageOk ? '견줌' : '재현'} — 1만 · 부모를 이름으로(띠 인물)`,
        이름참조ms: r1(built['band-name'].ms),
        id참조ms: r1(built['band-id'].ms),
        배: r1(built['band-name'].ms / built['band-id'].ms),
        설계값: '3,601ms(id 214ms · 16.8배) — D1 이전 코드',
        ...(lineageOk ? {} : { '3초대': built['band-name'].ms >= 2500 && built['band-name'].ms < 5000, '눈금으로 고친 이름참조ms': r1((built['band-name'].ms * 100) / report.눈금ms) }),
      });
  }
  for (const k of Object.keys(built)) built[k].model = null;

  /* (나) 동아시아 기본팩에 더하기(6-1: 계보 전용 1만(id)을 더해도 + ≤ 150ms) */
  if (parts.has('나')) {
    log('(나) 기본팩에 더하기');
    const add = sample(10000, `${K}-id`);
    const pk = norm(add).r.pack;
    const a = time(() => HT.buildModel(basePacks, null));
    const b = time(() => HT.buildModel([...basePacks, pk], null));
    row({ 무엇: '기본팩 모델', 모델ms: r1(a.ms), '+1만ms': r1(b.ms), 늘어남ms: r1(b.ms - a.ms), 판: `${K}-id` });
    judge(`buildModel + ${K === 'lineage' ? '계보 전용' : '띠 인물'} 1만(id) ≤ + 150ms`, b.ms - a.ms <= 150, { 기본ms: r1(a.ms), 더한ms: r1(b.ms), 늘어남ms: r1(b.ms - a.ms) });
  }

  if (!quick) {
    /* (다) 선형 2만 → 5만 · 고리 */
    const kind = `${K}-id`;
    const p5 = norm(sample(50000, kind)).r.pack;
    const m5 = time(() => HT.buildModel([p5], null), parts.has('다') ? Math.min(runs, 2) : 1);
    if (parts.has('다')) {
      log('(다) 2만 → 5만 · 고리');
      const p2 = norm(sample(20000, kind)).r.pack;
      const m2 = time(() => HT.buildModel([p2], null), Math.min(runs, 2));
      judge('2만 → 5만 ≤ 3배 (buildModel)', m5.ms / m2.ms <= 3, { 판: kind, '2만ms': r1(m2.ms), '5만ms': r1(m5.ms), 배: r3(m5.ms / m2.ms) });
      const pc = norm(sample(20000, kind)).r.pack;
      const pn = norm(sample(20000, kind, { cycle: false })).r.pack;
      const mc = time(() => HT.buildModel([pc], null), Math.min(runs, 2));
      const mn = time(() => HT.buildModel([pn], null), Math.min(runs, 2));
      judge('고리 1건 ≤ 고리 없음 × 1.2 (2만 · buildModel)', mc.ms / mn.ms <= 1.2, { 판: kind, 고리ms: r1(mc.ms), 없음ms: r1(mn.ms), 배: r3(mc.ms / mn.ms), 고리경고: warnOf(mc.v).filter(w => /고리/.test(w)).length });
      const fc = time(() => HT.familyOf(mc.v, 'kin-on'), 1);
      const fn = time(() => HT.familyOf(mn.v, 'kin-on'), 1);
      row({ 무엇: 'familyOf 본가 — 고리 있음/없음', 판: kind, 크기: 20000, 고리ms: r1(fc.ms), 없음ms: r1(fn.ms), 사람: fn.v && fn.v.nodes ? fn.v.nodes.length : null, 설계값: '28,965ms / 133ms(HEAD · 한 가문)' });
    }

    /* (라) 5만 · familyOf(6-4: 5만 · 한 가문 1,000ms · 915ms · 5.6MB) · 뼈대 */
    const model5 = m5.v;
    if (parts.has('라')) {
      log('(라) 5만 · familyOf');
      const f5 = time(() => HT.familyOf(model5, 'kin-on'), 1);
      const fj = f5.v ? JSON.stringify({ nodes: f5.v.nodes, edges: f5.v.edges }) : ''; // A 가-6의 x_family 꼴(노드 · 선 전부)
      const fb = lineageOk ? time(() => HT.familyOf(model5, 'kin-on', { branches: true }), 1) : { ms: null, v: null }; // D1 이전 코드는 선택을 모름
      row({ 무엇: 'familyOf 본가', 판: kind, 크기: 50000, 모델ms: r1(m5.ms), familyOfms: r1(f5.ms), 사람: f5.v && f5.v.nodes ? f5.v.nodes.length : null, JSON_MB: r3(Buffer.byteLength(fj) / 1048576), '파 포함ms': r1(fb.ms), '파 포함 사람': fb.v && fb.v.nodes ? fb.v.nodes.length : null, 설계값: '1,000 · 915ms · 5.6MB(한 가문)' });
      const m1 = HT.buildModel([norm(sample(10000, kind)).r.pack], null);
      const f1 = HT.familyOf(m1, 'kin-on');
      const f1b = HT.familyOf(m1, 'kin-on', { branches: true });
      row({ 무엇: 'familyOf 본가 사람 수(1만 · 파 14)', 판: kind, 본가만: f1 && f1.nodes ? f1.nodes.length : null, '파 포함': f1b && f1b.nodes ? f1b.nodes.length : null, 설계값: '3,679(파 12 · 파 사람 6천여 명이 빠짐)' });
    }

    /* (마) 계보 뼈대 — 5만(--big이면 20만도) */
    const sizes = !parts.has('마') ? [] : big ? [50000, 200000] : [50000];
    for (const size of sizes) {
      log(`(마) 계보 뼈대 ${size.toLocaleString('ko-KR')}`);
      const s = sample(size, `${K}-id`);
      const model = size === 50000 ? model5 : HT.buildModel([norm(s).r.pack], null);
      const real = helpers.includes('kinSkeleton') && helpers.includes('kinLayout');
      if (!real && !stub) {
        row({ 무엇: '계보 뼈대', 크기: size, 결과: '건너뜀 — HT.kinSkeleton · HT.kinLayout 없음(D1-W1 전). --stub이면 대역으로' });
        continue;
      }
      const by = real ? 'HT' : '대역';
      const skelT = real ? time(() => HT.kinSkeleton(model, 'kin:kin-on'), 1) : time(() => standInSkeleton(s), 1);
      const skel = skelT.v;
      const again = real ? time(() => HT.kinSkeleton(model, 'kin:kin-on'), 1) : null;
      const n = skel ? skel.n ?? (skel.par ? skel.par.length : 0) : 0;
      if (!n) {
        row({ 무엇: '계보 뼈대', 크기: size, 결과: '뼈대가 비었음', 쓴것: by });
        continue;
      }
      const L = real ? (sk, o) => HT.kinLayout(sk, o) : refLayout;
      const openAll = new Uint8Array(n).fill(1);
      const all = time(() => L(skel, openAll), Math.max(runs, 7), 3);
      const defOpen = real && helpers.includes('kinDefaultOpen') ? HT.kinDefaultOpen(skel) : refDefaultOpen(skel);
      const def = time(() => L(skel, defOpen), Math.max(runs, 7), 2);
      /* 접기 1회: 모두 펼친 상태에서 하위가 가장 큰 뿌리 아닌 마디 하나를 접었다가 다시 셈 */
      let fold = -1;
      for (let i = 1; i < n; i++) if (skel.par[i] >= 0 && (fold < 0 || skel.size[i] > skel.size[fold]) && skel.size[i] < n / 2) fold = i;
      const folded = openAll.slice();
      folded[fold] = 0;
      const once = time(() => L(skel, folded), Math.max(runs, 9), 2);
      const refAll = time(() => refLayout(skel, openAll), Math.max(runs, 7), 3); // 같은 계약의 대역 셈(설계 4-4를 그대로 옮김) — 견줌
      /* 보이는 것 고르기: 창 830 × 910(카드 칸 140 · 세대 82) — 모두 펼침의 가운데 */
      const lay = all.v;
      const u0 = Math.floor(lay.width / 2) - 12, u1 = u0 + Math.ceil(830 / 35), g0 = Math.max(0, Math.floor(lay.rows.length / 2) - 5);
      let shown = 0;
      const pickT = time(() => (shown = pickVisible(lay, g0, g0 + Math.ceil(910 / 82), u0, u1)), Math.max(runs, 20), 5);
      /* 처음 열 때(6-2)의 뼈대 짓기: 데운 뒤 — 같은 팩으로 모델을 한 번 더 지어(캐시 없는 새 모델) 다시 잼 */
      let warmSkelMs = null;
      if (real) {
        const m2 = HT.buildModel([norm(s).r.pack], null);
        warmSkelMs = time(() => HT.kinSkeleton(m2, 'kin:kin-on'), 1).ms;
      }
      row({ 무엇: '계보 뼈대 · 정수 칸 셈', 쓴것: by, 크기: size, 마디: n, '뼈대ms(첫 실행)': r1(skelT.ms), '뼈대ms(데운 뒤 · 새 모델)': r1(warmSkelMs), '다시 부름ms(캐시)': again ? r3(again.ms) : null, '모두 펼침ms(첫)': r1(all.first), '모두 펼침ms': r1(all.ms), '대역 셈 모두 펼침ms': r1(refAll.ms), 기본펼침ms: r1(def.ms), '접기 1회ms': r3(once.ms), '고르기ms': r3(pickT.ms), 보이는카드: shown, '모두 펼침 폭px': lay.width * 35, 설계값: '모두 펼침 0.8ms(첫 21) · 접기 1.3ms · 고르기 0.03ms · 폭 약 390만 px' });
      if (size === 50000) {
        const sk30 = warmSkelMs ?? skelT.ms;
        judge('뼈대 짓기 처음 열 때 ≤ 30ms (5만 · 6-2 웹 예산 — 데운 뒤)', sk30 <= 30, { 쓴것: by, ms: r1(sk30), 첫실행ms: r1(skelT.ms) });
        judge('접기 1회 ≤ 2ms (5만)', once.ms <= 2, { 쓴것: by, ms: r3(once.ms) });
        judge('보이는 것 고르기 ≤ 0.1ms (5만)', pickT.ms <= 0.1, { ms: r3(pickT.ms) });
      }
      if (real) {
        /* 대조: 설계 4-4를 그대로 옮긴 대역 칸 셈 = HT.kinLayout? (보이는 마디의 x · w · 세대 줄 · 폭) */
        const diff = [];
        for (const [nm, op] of [['모두 펼침', openAll], ['기본', defOpen], ['접기 1', folded]]) {
          const a = L(skel, op), b = refLayout(skel, op);
          const bad = [];
          if (a.width !== b.width) bad.push(`폭 ${a.width} ≠ ${b.width}`);
          for (let g2 = 0; g2 < Math.max(a.rows.length, b.rows.length); g2++) {
            const ra = a.rows[g2] || [], rb = b.rows[g2] || [];
            if (ra.length !== rb.length || ra.some((v, k) => v !== rb[k])) {
              bad.push(`세대 ${g2} 줄이 다름`);
              break;
            }
          }
          for (const row2 of b.rows) for (const i of row2) if (a.x[i] !== b.x[i] || a.w[i] !== b.w[i]) {
            bad.push(`마디 ${i}: x ${a.x[i]}/${b.x[i]} · w ${a.w[i]}/${b.w[i]}`);
            break;
          }
          if (bad.length) diff.push(`${nm}: ${bad.slice(0, 3).join(' · ')}`);
        }
        row({ 무엇: '대조 — HT.kinLayout = 설계 4-4 그대로 옮긴 셈', 크기: size, 같음: !diff.length, 다름: diff });
      }
      /* 승계표 줄(모두 펼침) — 줄 수 ≤ 사람 + 지도자 */
      const polity = model.periods.find(p => p.id === 'kin-garam');
      let rows = null, rowsT = null, by2 = '';
      if (helpers.includes('successionRows') && real) {
        /* 모두 펼침: HT.successionOpen(…, 'all')이 있으면 그것, 없으면 { 뼈대 uid: 모두 1 } (W1이 정한 꼴 — 이음새 기록 D1-W1) */
        const openS = typeof HT.successionOpen === 'function' ? HT.successionOpen(model, polity, 'all') : { [skel.uid]: openAll };
        try {
          rowsT = time(() => HT.successionRows(model, polity, openS));
          rows = rowsT.v;
          by2 = 'HT';
        } catch (e) {
          report.오류.push(`successionRows: ${e.message}`);
        }
      } else if (stub || !real) {
        const sk = real ? null : skel;
        if (sk) {
          rowsT = time(() => refSuccessionRows(sk, openAll));
          rows = rowsT.v;
          by2 = '대역';
        }
      }
      if (rows) {
        const count = rows.length / 3; // 줄마다 [갈래, 번호, 깊이] — 설계 2-4 자 · 이음새 기록 D1-W1의 꼴
        const people = n;
        const seen = new Set();
        let twice = 0;
        for (let k = 0; k < rows.length; k += 3) if (rows[k] === 1) (seen.has(rows[k + 1]) ? twice++ : seen.add(rows[k + 1]));
        row({ 무엇: '승계표 줄(모두 펼침)', 쓴것: by2, 크기: size, 줄: count, 사람줄: seen.size, '두 번 나온 사람': twice, ms: r1(rowsT.ms), '첫ms': r1(rowsT.first), '사람 + 지도자': people + polity.leaders.length });
        judge('승계표 모두 펼침 줄 수 ≤ 사람 + 지도자 · 한 사람은 한 번만', count <= people + polity.leaders.length && !twice, { 쓴것: by2, 줄: count, 한도: people + polity.leaders.length, 두번: twice });
      }
      if (real) {
        /* 뼈대의 열거 칸 = 앱 열 꼴 기록의 열(이음새 기록 D1-E ② · D1-W1) — JSON 크기 · V8 풀기(설계 6-4: 5만 2.4MB · 8.7ms) */
        const json = JSON.stringify(skel, (k, v) => (ArrayBuffer.isView(v) ? Array.from(v) : v));
        const parse = time(() => JSON.parse(json), Math.max(runs, 3));
        row({ 무엇: '뼈대 JSON(열 꼴)', 크기: size, MB: r3(Buffer.byteLength(json) / 1048576), '사람당 B': r1(Buffer.byteLength(json) / n), 'V8 풀기ms': r1(parse.ms), 설계값: '5만 2.4MB(사람당 49B) · 8.7ms' });
      }
      if (helpers.includes('kinRecord')) {
        try {
          const rec = time(() => HT.kinRecord(skel, { limit: 50000 }), 1);
          const bytes = rec.v.reduce((a, x) => a + Buffer.byteLength(typeof x.json === 'string' ? x.json : JSON.stringify(x.json)), 0);
          const parse = time(() => rec.v.forEach(x => JSON.parse(typeof x.json === 'string' ? x.json : JSON.stringify(x.json))));
          row({ 무엇: '앱 기록(열 꼴)', 크기: size, 기록: rec.v.length, MB: r3(bytes / 1048576), '사람당 B': r1(bytes / n), 짓기ms: r1(rec.ms), 'V8 풀기ms': r1(parse.ms), 설계값: '5만 2.4MB(사람당 49B) · 8.7ms' });
        } catch (e) {
          report.오류.push(`kinRecord: ${e.message}`);
        }
      }
    }
  }
  const after = fingerprint(here);
  report.자료보존 = JSON.stringify(before) === JSON.stringify(after);
  log(`packs/ · samples/ 지문 ${Object.keys(before).length}개 — 처음 = 끝: ${report.자료보존 ? '같음' : '다름!'}`);
  fs.mkdirSync(out, { recursive: true });
  const file = path.join(out, `계보-모델-측정${opt('--tag', '') ? '-' + opt('--tag', '') : ''}.json`);
  fs.writeFileSync(file, JSON.stringify(report, null, 2) + '\n');
  log(`결과: ${file}`);
  if (!report.자료보존) process.exit(1);
}

/* ---------- ② 브라우저 ---------- */
async function browserBench() {
  const root = path.resolve(args[0] || '.');
  const output = path.resolve(args[1] && !args[1].startsWith('--') ? args[1] : path.join(here, '배포/측정/계보-성능'));
  const size = Number(opt('--size', 50000));
  const makerSize = Number(opt('--maker-size', 10000));
  const only = new Set(String(opt('--only', '승계표,세계표,메이커')).split(','));
  const require = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url);
  const { chromium } = require('playwright');
  fs.mkdirSync(output, { recursive: true });
  const before = fingerprint(root);
  const blobs = new Map();
  const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' };
  const MARK = '/* ---------- 팩 & 모델 ---------- */';
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    if (blobs.has(rel)) {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      return void res.end(blobs.get(rel));
    }
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) return void (res.writeHead(403), res.end());
    try {
      let body = fs.readFileSync(file);
      if (rel === 'js/viewer.js') {
        const src = body.toString('utf8');
        if (src.split(MARK).length !== 2) throw new Error('측정 창구 자리를 찾지 못함');
        body = Buffer.from(src.replace(MARK, 'window.__tl=timeline;window.__state=state;window.__open=openDetail;\n' + MARK));
      }
      res.writeHead(200, { 'Content-Type': (mime[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  /* HT_HEADED=1: 창을 띄워 잼 — 머리 없는 브라우저의 rAF는 화면 주사율(144Hz)을 따르지 않으므로 감독 PC 판정은 이것으로(D1 결합) */
  const headed = process.env.HT_HEADED === '1';
  const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: !headed });
  const report = { 화면: '1920×1080 · 배율 1', 움직임: 'no-preference', 창: headed ? '띄움(HT_HEADED=1)' : '머리 없음', 크기: size, 메이커크기: makerSize, 구간: [], 오류: [] };
  /* 장면 기록기 — rAF 간격 · 긴 장면(long-animation-frame · longtask) */
  const INIT = () => {
    window.__kinPerf = { loaf: [], long: [] };
    try {
      new PerformanceObserver(l => l.getEntries().forEach(e => window.__kinPerf.loaf.push([e.startTime, e.duration]))).observe({ type: 'long-animation-frame', buffered: true });
    } catch {}
    try {
      new PerformanceObserver(l => l.getEntries().forEach(e => window.__kinPerf.long.push([e.startTime, e.duration]))).observe({ type: 'longtask', buffered: true });
    } catch {}
    window.__begin = () => {
      const r = (window.__rec = { frames: [], t0: performance.now() });
      const tick = t => {
        if (window.__rec !== r) return;
        r.frames.push(t);
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    };
    window.__end = () => {
      const r = window.__rec;
      window.__rec = null;
      const t1 = performance.now();
      const iv = r.frames.slice(1).map((t, k) => t - r.frames[k]);
      const inWin = l => l.filter(([t, d]) => t + d >= r.t0 && t <= t1 && d >= 50).length;
      return { 간격: iv, 긴장면: inWin(window.__kinPerf.loaf), 긴작업: inWin(window.__kinPerf.long), ms: t1 - r.t0 };
    };
  };
  const summarize = (raw, T) => {
    const iv = raw.간격;
    const miss = iv.map(d => d > 1.5 * T);
    let run = 0, maxRun = 0;
    for (const m of miss) {
      run = m ? run + 1 : 0;
      maxRun = Math.max(maxRun, run);
    }
    const missed = miss.filter(Boolean).length;
    const sorted = iv.slice().sort((a, b) => a - b);
    return { 장면: iv.length, 놓침: missed, '놓침%': r1((100 * missed) / Math.max(1, iv.length)), 연달아놓침: maxRun >= 2 ? maxRun : 0, '50ms넘음': iv.filter(d => d > 50).length, p95ms: r1(sorted[Math.floor(sorted.length * 0.95)] || 0), 최대ms: r1(sorted[sorted.length - 1] || 0), 긴장면: raw.긴장면, 긴작업: raw.긴작업, 구간ms: Math.round(raw.ms) };
  };
  const pass = s => s['놓침%'] <= 1 && !s.연달아놓침 && !s['50ms넘음'] && !s.긴장면;
  const seg = (name, part, s, extra = {}) => {
    const o = { 구간: name, 부분: part, ...s, ...extra, 판정: pass(s) && (extra.창안요소 == null || extra.창안요소 <= 400) ? '통과' : '넘음' };
    report.구간.push(o);
    console.log(`  ${name} · ${part}: ${o.판정} — 놓침 ${s.놓침}/${s.장면}(${s['놓침%']}%) · 연달아 ${s.연달아놓침} · 50ms 넘음 ${s['50ms넘음']} · 긴 장면 ${s.긴장면}${extra.창안요소 != null ? ` · 창 안 요소 ${extra.창안요소}` : ''}`);
  };
  const skip = (name, why) => {
    report.구간.push({ 구간: name, 결과: '건너뜀', 까닭: why });
    console.log(`  ${name}: 건너뜀 — ${why}`);
  };
  const ctxOpts = { viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, colorScheme: 'light', serviceWorkers: 'block', reducedMotion: 'no-preference' };
  /** 처음 1초 쉬는 동안의 rAF 간격 중앙값 = T */
  const calibrate = async page => {
    await page.evaluate(() => window.__begin());
    await page.waitForTimeout(1000);
    const raw = await page.evaluate(() => window.__end());
    return median(raw.간격) || 16.7;
  };
  try {
    /* 견본: 계보 전용을 읽는 코드인지 시험 창에서 보고 판을 고름 */
    const probeCtx = await browser.newContext(ctxOpts);
    const probe = await probeCtx.newPage();
    await probe.goto(`${base}/index.html`);
    await probe.waitForFunction(() => window.__tl && window.HT && window.__state && window.__state.model);
    const lineageOk = await probe.evaluate(() => {
      const r = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 3, id: 'kin-probe', name: '확인', tracks: [{ id: 't', name: '가' }], figures: [{ id: 'a', track: 't', name: '가', lineageOnly: true }] });
      return !!(r.pack && !r.errors.length && (r.pack.figures || []).some(f => f.lineageOnly));
    });
    await probeCtx.close();
    const kind = lineageOk ? 'lineage-id' : 'band-id';
    report.판 = kind;
    const big = kinSample({ size, kind });
    blobs.set('__kin/sample.json', big.json);
    const packId = big.pack.id;
    console.log(`견본 ${big.file} (${(Buffer.byteLength(big.json) / 1048576).toFixed(1)}MB)`);

    if (only.has('승계표') || only.has('세계표')) {
      const context = await browser.newContext(ctxOpts);
      await context.addInitScript(INIT);
      const page = await context.newPage();
      page.on('pageerror', e => report.오류.push(e.message));
      await page.goto(`${base}/index.html`);
      await page.waitForFunction(() => window.__tl && window.HT && window.__state && window.__state.model);
      const T = await calibrate(page);
      report.T = r1(T);
      const load = await page.evaluate(async () => {
        const raw = await (await fetch('/__kin/sample.json')).json();
        const t0 = performance.now();
        const r = HT.normalizePack(raw);
        const t1 = performance.now();
        const model = HT.buildModel([...(window.__state.packs || []), r.pack].filter(Boolean), null); // 연표에 실린 팩(기본팩) + 가상 대가족
        const t2 = performance.now();
        window.__state.model = model;
        window.__tl.setData(model, { enter: false });
        return { 읽기ms: t1 - t0, 모델ms: t2 - t1, 오류: r.errors.length };
      });
      report.불러오기 = { 읽기ms: r1(load.읽기ms), 모델ms: r1(load.모델ms), 오류: load.오류 };
      console.log(`  T ${r1(T)}ms · 읽기 ${r1(load.읽기ms)}ms · 모델 ${r1(load.모델ms)}ms`);

      /* 구간 1 — 승계표 */
      if (only.has('승계표')) {
        const uid = `${packId}/kin-garam`;
        await page.evaluate(u => window.__begin() || window.__open(u, { cell: 'succession' }), uid);
        const tree = page.locator('#detail [role="tree"]').first();
        const ok = await tree.waitFor({ timeout: 3000 }).then(() => true, () => false);
        const openRaw = await page.evaluate(() => window.__end());
        if (!ok) skip('승계표', '승계표 창(#detail 안 role="tree")이 없음 — D1-W2 전');
        else {
          seg('승계표', '열기', summarize(openRaw, T));
          await page.screenshot({ path: path.join(output, '승계표-1920-1배.png') });
          const count = () => page.evaluate(() => document.querySelector('#detail').querySelectorAll('*').length);
          const button = name => page.locator('#detail button', { hasText: name }).first();
          await page.evaluate(() => window.__begin());
          if (await button('모두 펼치기').count()) await button('모두 펼치기').click();
          await page.waitForTimeout(800);
          seg('승계표', '모두 펼치기', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
          await page.screenshot({ path: path.join(output, '승계표-모두-펼침-1920-1배.png') });
          const box = await tree.boundingBox();
          await page.mouse.move(box.x + box.width / 2, box.y + Math.min(box.height / 2, 300));
          await page.evaluate(() => window.__begin());
          for (let k = 0; k < 400; k++) {
            await page.mouse.wheel(0, 12 * 100);
            await page.waitForTimeout(32);
            const done = await tree.evaluate(el => {
              const s = el.closest('.detail-body') || el;
              return s.scrollTop + s.clientHeight >= s.scrollHeight - 2;
            });
            if (done) break;
          }
          seg('승계표', '끝까지 밀기', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
          await page.evaluate(() => {
            const s = document.querySelector('#detail [role="tree"]').closest('.detail-body') || document.querySelector('#detail [role="tree"]');
            s.scrollTop = 0;
          });
          await page.waitForTimeout(300);
          /* 접고 펴기는 설계 3-6의 키(ARIA tree — Home으로 첫 줄 · Space로 접기 · 펼치기) — 줄 몸통을 누르면 그 사람의 창으로 바뀌므로 누르지 않음 */
          await tree.focus();
          await page.keyboard.press('Home');
          await page.evaluate(() => window.__begin());
          for (let k = 0; k < 20; k++) {
            await page.keyboard.press('Space');
            await page.waitForTimeout(400);
          }
          seg('승계표', '접기 · 펼치기 20회', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
        }
      }

      /* 구간 2 — 세계표 */
      if (only.has('세계표')) {
        await page.evaluate(() => window.__open('house:kin-on'));
        const opener = page.locator('#detail button', { hasText: '세계표' }).first();
        const has2 = await opener.waitFor({ timeout: 3000 }).then(() => true, () => false);
        if (!has2) skip('세계표', '가문 창에 세계표 단추가 없음 — D1-W2 전');
        else {
          await page.evaluate(() => window.__begin());
          await opener.click();
          /* 세계표 창 = 상세 창 꼴(.detail)의 떠 있는 창 가운데 ARIA tree를 품은 것(설계 4-1 · 4-6) — 상세 창 자리(#detail)는 뺌 */
          const win = page.locator('.detail:not(#detail):has([role="tree"])').first();
          const ok = await win.waitFor({ timeout: 8000 }).then(() => true, () => false);
          const openRaw = await page.evaluate(() => window.__end());
          if (!ok) skip('세계표', '세계표 창(.detail 꼴의 떠 있는 창 · 안에 role="tree")을 찾지 못함 — 손잡이는 D1-W2와 결합 때 맞춤');
          else {
            const count = () => win.evaluate(el => el.querySelectorAll('*').length);
            seg('세계표', '열기', summarize(openRaw, T), { 창안요소: await count() });
            await page.screenshot({ path: path.join(output, '세계표-1920-1배.png') });
            const box = await win.boundingBox();
            const cx = box.x + box.width / 2, cy = box.y + box.height / 2;
            await page.evaluate(() => window.__begin());
            for (const [dx, dy] of [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]) {
              await page.mouse.move(cx, cy);
              await page.mouse.down();
              for (let k = 1; k <= 10; k++) {
                await page.mouse.move(cx + dx * k * 24, cy + dy * k * 24);
                await page.waitForTimeout(8);
              }
              await page.mouse.up();
              await page.waitForTimeout(350); // 관성 250ms + 여유
            }
            seg('세계표', '8방향 끌기 + 관성', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
            /* 접기 20회: 카드 몸통을 누르면 칸 창 · 인물 창이 열리므로(설계 4-5) 키로 — 나무에 초점 · Space(설계 4-6 = 3-6) */
            await win.locator('[role="tree"]').first().focus();
            await page.evaluate(() => window.__begin());
            for (let k = 0; k < 20; k++) {
              await page.keyboard.press('Space');
              await page.waitForTimeout(400);
            }
            seg('세계표', '접기 · 펼치기 20회', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
            const find = win.locator('input[type="text"], input:not([type])').first();
            if (await find.count()) {
              const deep = big.tree.persons.filter(p => p.kind === 'member' && !p.unknown).reduce((a, p) => ((p.depth || 0) > (a.depth || 0) ? p : a));
              await page.evaluate(() => window.__begin());
              await find.fill(deep.name);
              await find.press('Enter');
              await page.waitForTimeout(900);
              seg('세계표', '찾아 데려오기', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
            } else skip('세계표 · 찾아 데려오기', '찾기 칸이 없음');
            const canvas = win.locator('canvas').last();
            if (await canvas.count()) {
              const cb = await canvas.boundingBox();
              await page.evaluate(() => window.__begin());
              for (const f of [0.1, 0.5, 0.9]) {
                await page.mouse.click(cb.x + cb.width * f, cb.y + cb.height / 2);
                await page.waitForTimeout(500);
              }
              seg('세계표', '전체도 누르기', summarize(await page.evaluate(() => window.__end()), T), { 창안요소: await count() });
            } else skip('세계표 · 전체도', '전체도 캔버스가 없음');
          }
        }
      }
      await context.close();
    }

    /* 구간 3 — 메이커 칸 고침 3회 */
    if (only.has('메이커')) {
      const small = kinSample({ size: makerSize, kind });
      const context = await browser.newContext(ctxOpts);
      await context.addInitScript(INIT);
      await context.addInitScript(d => {
        try {
          if (!localStorage.getItem('ht.maker.draft')) localStorage.setItem('ht.maker.draft', d);
        } catch {}
      }, JSON.stringify(small.pack));
      const page = await context.newPage();
      page.on('pageerror', e => report.오류.push(e.message));
      page.on('dialog', d => d.dismiss());
      await page.goto(`${base}/dlc-maker.html`);
      const ready = await page.waitForFunction(id => document.querySelector('#mkStart')?.hidden && document.querySelector(`[data-tuid="${id}/kin-garam"]`), small.pack.id, { timeout: 60000 }).then(() => true, () => false);
      if (!ready) skip('메이커', `작업본(${makerSize}명)이 메이커 구조 나무에 뜨지 않음`);
      else {
        const T = await calibrate(page);
        await page.evaluate(() => {
          const b = HT.buildModel;
          window.__builds = [];
          HT.buildModel = function (...a) {
            const t0 = performance.now();
            try {
              return b.apply(this, a);
            } finally {
              window.__builds.push(performance.now() - t0);
            }
          };
        });
        await page.locator(`[data-tuid="${small.pack.id}/kin-garam"]`).click();
        const form = page.locator('form:has([data-cells="leaders"])').first();
        await form.waitFor({ state: 'attached' });
        await form.locator('details[data-adv="cells"]').evaluate(el => (el.open = true)).catch(() => {});
        /* 지도자 줄의 메모 칸을 고치고 저장(이름을 고치면 그 칸을 가리키는 "나라:지도자@해" 참조가 끊기므로 메모) */
        for (let k = 0; k < 3; k++) {
          const note = form.locator('[data-cells="leaders"] .cell-row .c-note').nth(k + 1);
          await page.evaluate(() => {
            window.__builds.length = 0;
            window.__begin();
          });
          await note.fill(`측정 고침 ${k + 1}`);
          await page.keyboard.press('Control+s');
          await page.waitForTimeout(1500);
          const builds = await page.evaluate(() => window.__builds.slice());
          seg('메이커', `칸 고침 ${k + 1}`, summarize(await page.evaluate(() => window.__end()), T), { 모델짓기ms: builds.map(r1) });
        }
        await page.screenshot({ path: path.join(output, '메이커-칸-고침-1920-1배.png') });
      }
      await context.close();
    }
  } catch (e) {
    report.오류.push(String(e && e.stack ? e.stack : e));
  } finally {
    await browser.close();
    server.close();
  }
  const after = fingerprint(root);
  report.자료보존 = JSON.stringify(before) === JSON.stringify(after);
  fs.writeFileSync(path.join(output, '계보-화면-측정.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`packs/ · samples/ 지문 — 처음 = 끝: ${report.자료보존 ? '같음' : '다름!'} · 오류 ${report.오류.length}`);
  if (report.오류.length) console.log(report.오류.slice(0, 5).join('\n'));
  if (!report.자료보존 || report.오류.length) process.exit(1);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (has('--model')) await modelBench();
  else await browserBench();
}

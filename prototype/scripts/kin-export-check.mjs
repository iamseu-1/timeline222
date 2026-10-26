// D1-E 내보내기 점검 — 계보 뼈대(갈래 kin) · 가문 x_kin · 정권 x_lineage의 line · seam · kinAt · 계보 전용 인물 기록(확정 설계 docs/설계-10건/1-2-계승과-가문-확정.md
// 8-1 · 9-2 D1-E, 그 문서 끝 '구현 이음새 기록'의 D1-E 절). 내보내기 모듈(export/kin.mjs · entities.mjs)을 같은 웹 코드 위에서 '이 일 전' 모듈과 견준다.
//
//   ① 바이트 대조: 등불 연대기(견본 samples/sample-lantern.json) · 동아시아를 이 일 전 모듈(--base, 기본 d1d6e18)과 지금 모듈로 내보내 entities 밖은 바이트까지 같은지,
//      entities는 갈래별로 늘고 준 것 · 바뀐 열쇠(x_family → x_kin 등)를 목록으로 남긴다(바뀐 열쇠가 허용 목록 밖이면 문제).
//   ② 열 꼴 기록: 손으로 만든 뼈대(파 · 양자 · 건너뜀 · 이름 미상 · 두 나라 · 고리 없는 숲)로 recordOf → splitKin(작은 상한 · 5만 + 1) → joinKin = 한 벌(바이트까지) ·
//      꼬투리 · 덩어리 uid · extraFar · 정수 칸 셈(4-4)이 합친 것 = 한 벌.
//   ③ 견본 내보내기: sample-lantern(2.0.0 — 가문 21(적은 것 17 · 저절로 4) · 파 7 · 계보 전용 인물 4 · 부모 · 배우자 · 지도자 칸의 승계) — x_kin · kinAt이 가리키는 뼈대 · 번호가 맞고 매달린 고리 0, 계보 전용 인물 기록에 활동 칸 없음.
//   ④ 정답 자리 · 앱 고정 자료: prototype/app/test/fixtures/kin-<견본>.json(엔진 entity 답 꼴) · kin-golden-<견본>.json(HT.kinLayout · HT.successionRows) ·
//      kin-chunks-<견본>.json(작은 상한으로 나눈 기록). 웹 도우미(D1-W1)가 없으면 대역(--stand-in — 이 파일 안의 가짜 함수)으로만 돌리고 고정 자료는 쓰지 않는다.
//   ⑤ (선택 — --tool <archive-tool>) 저장소 짓기: 견본 · 가상 대가족 1만 → import-layout → verify-tiles 2000(누락 · 중복 0) · 기록 크기 · 가져오기 시간.
//
// 웹 코드(js · packs · samples · index.html · export-layout.mjs)는 --web <git 판>(기본 HEAD — 같은 작업 폴더의 다른 작업자가 고치는 중인 파일을 피함) · --web live(작업 트리)에서
// 임시 폴더(HT_KIN_TMP — 기본 prototype/results/kin-check)에 거울로 펴고, 내보내기 모듈만 '이 일 전'(--base 판)과 '지금'(작업 트리)으로 바꿔 끼운다.
// 내보내기는 거울마다 따로 된 노드 프로세스(--worker)에서 돌린다(웹 코드를 전역에 한 번만 싣게).
// 사용: node prototype/scripts/kin-export-check.mjs [--stand-in] [--web HEAD|live|<판>] [--base <판>] [--no-fixtures] [--skip-east-asia] [--skip-compare] [--tool <archive-tool>]
//        --skip-compare: ① 바이트 대조(등불 연대기 · 동아시아 — 무거움)를 건너뛰고 ② ③ ④만(고정 자료를 가볍게 다시 낼 때 — D1 결합). PC 검사는 이것 없이 돌린다
//        [--family <이름>=<가상 대가족 JSON>[@<견줄 JSON>],…] (D1-T의 scripts/kin-sample.mjs가 만든 것 — 마디 2천 이하인 것만 앱 고정 자료로 씀 · 예: family-1000=…/kin-1000-lineage-id.json)
//        '@<견줄 JSON>'은 이 일 전 모듈로 내보내 크기를 견줄 판(계보 전용 판은 이 일 전 모듈이 모르므로 같은 사람의 띠 인물 판 band-id를 준다)
// 견본 · 기본팩 · packs/ · samples/는 읽기만 한다. 검사 자료의 이름은 모두 가상이다.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { useCalendarCopy } from './oracle/cal-copy.mjs';

useCalendarCopy('kin-export-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROTOTYPE = path.resolve(HERE, '..');
const ROOT = path.resolve(PROTOTYPE, '..');
const arg = (name, fallback = null) => {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
};
const flag = name => process.argv.includes(name);

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  대역(가짜 함수) — 웹 도우미(D1-W1이 js/core.js에 두는 것)가 아직 없을 때만, 이 검사 프로세스의 HT에만 단다.
 *  계약 꼴(확정 설계 2-4 자 · 3-3 · 4-4 · 4-5)대로 짓되 모델 규칙(가문 물려받기 · 파조 풀기 …)은 흉내만 낸다 — 내보내기의 길을 시험하는 용도.
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
const BIT = { member: 1, unknown: 2, missing: 4, side: 8, founder: 16, leader: 32, lineage: 64, stub: 128, two: 256 };

/** 정수 칸 셈(4-4) — 대역이자 대조용 두 번째 구현. skel: { size, gen, bits } 열(배열 · Int32Array), open: 마디마다 0 · 1. */
export function layoutStandIn(skel, open) {
  const n = skel.size.length;
  const { size, gen, bits } = skel;
  const x = new Int32Array(n);
  const w = new Int32Array(n);
  const left = new Int32Array(n);
  const side = i => (bits[i] & BIT.side ? 1 : 0);
  const kids = i => {
    const out = [];
    if (!open[i] || size[i] < 2) return out;
    for (let j = i + 1; j < i + size[i]; j += size[j]) out.push(j);
    return out;
  };
  // 보이는 마디(앞 차례) — 접힌 하위는 i += size[i]
  const vis = [];
  const roots = [];
  for (let i = 0; i < n; ) {
    roots.push(i);
    const stack = [i];
    while (stack.length) {
      const v = stack.pop();
      vis.push(v);
      const ks = kids(v);
      for (let k = ks.length - 1; k >= 0; k--) stack.push(ks[k]);
    }
    i += size[i];
  }
  for (let k = vis.length - 1; k >= 0; k--) {
    const i = vis[k];
    const ks = kids(i);
    if (!ks.length) w[i] = 4 + side(i);
    else {
      let s = side(i);
      for (const c of ks) s += w[c];
      w[i] = s;
    }
  }
  let acc = 0;
  for (const r of roots) {
    left[r] = acc;
    acc += w[r];
  }
  for (const i of vis) {
    let l = left[i] + side(i);
    for (const c of kids(i)) {
      left[c] = l;
      l += w[c];
    }
  }
  for (let k = vis.length - 1; k >= 0; k--) {
    const i = vis[k];
    const ks = kids(i);
    x[i] = ks.length ? Math.floor((x[ks[0]] + x[ks[ks.length - 1]]) / 2) : left[i] + side(i) + 2;
  }
  let gens = 0;
  for (let i = 0; i < n; i++) if (gen[i] + 1 > gens) gens = gen[i] + 1;
  const rowsA = Array.from({ length: gens }, () => []);
  for (const i of vis) rowsA[gen[i]].push(i);
  return { x, w, rows: rowsA.map(r => Int32Array.from(r)), width: acc };
}

/** 기본 펼침(4-5) 대역 */
function defaultOpenStandIn(skel) {
  const n = skel.size.length;
  const open = new Uint8Array(n);
  if (n <= 200) return open.fill(1);
  const { par, bits, gen } = skel;
  let leaders = false;
  for (let i = 0; i < n; i++)
    if (bits[i] & BIT.leader) {
      leaders = true;
      for (let a = i; a >= 0; a = par[a]) open[a] = 1;
    }
  if (!leaders) {
    const top = new Int32Array(n);
    for (let i = 0; i < n; i++) top[i] = par[i] >= 0 ? top[par[i]] : gen[i];
    for (let i = 0; i < n; i++) if (gen[i] - top[i] < 2) open[i] = 1;
  }
  for (let i = 0; i < n; i++) if (bits[i] & BIT.founder) open[i] = 0;
  return open;
}

function installStandIns(HT) {
  if (typeof HT.kinSkeleton === 'function') return false;
  const cache = new WeakMap();
  const PRI = ['birth-father', 'father', '', 'adoptive-father', 'ancestor', 'adoptive-mother', 'birth-mother', 'mother'];
  const rank = as => {
    const k = PRI.indexOf(as || '');
    return k < 0 ? 2 : k;
  };
  const underOf = (model, id) => {
    const out = [];
    const seen = new Set();
    const walk = q => {
      if (seen.has(q)) return;
      seen.add(q);
      out.push(q);
      const h = model.houseMap.get(q);
      for (const c of (h && h.children) || []) walk(c);
    };
    walk(id);
    return out;
  };
  const rootOf = (model, id) => {
    const h = model.houseMap.get(id);
    return h && h.path && h.path.length ? h.path[0] : id;
  };
  const build = (model, key) => {
    const persons = model.persons || [];
    const ord = new Map(persons.map((p, i) => [p, i]));
    let set;
    let houseIds = null;
    let houseTop = null;
    if (key.startsWith('kin:polity:')) {
      const P = model.byUid.get(key.slice('kin:polity:'.length));
      if (!P) return null;
      const seeds = (P.leaders || []).map((c, i) => HT.personOf(model, P, `leader:${i}`)).filter(nd => nd && !nd.houseId);
      set = new Set();
      const stack = seeds.slice();
      while (stack.length) {
        const nd = stack.pop();
        if (set.has(nd)) continue;
        set.add(nd);
        for (const e of nd.children) stack.push(e.node);
      }
    } else {
      houseTop = key.slice(4);
      if (!model.houseMap.get(houseTop)) return null;
      houseIds = underOf(model, houseTop);
      const ids = new Set(houseIds);
      const members = persons.filter(nd => nd.houseId && ids.has(nd.houseId));
      set = new Set(members);
      for (const nd of members) for (const e of nd.children) set.add(e.node);
    }
    const isMember = nd => (houseIds ? !!nd.houseId && houseIds.includes(nd.houseId) : !nd.houseId);
    const treeParent = new Map();
    for (const nd of set) {
      const ps = nd.parents.filter(e => set.has(e.node)).sort((a, b) => rank(a.as) - rank(b.as) || ord.get(a.node) - ord.get(b.node));
      if (ps.length) treeParent.set(nd, ps[0]);
    }
    const kidsOf = new Map();
    for (const [nd, e] of treeParent) (kidsOf.get(e.node) || kidsOf.set(e.node, []).get(e.node)).push(nd);
    const birth = nd => (nd.figure && Number.isFinite(nd.figure.birth) ? nd.figure.birth : Infinity);
    const first = nd => (nd.cells.length ? Math.min(...nd.cells.map(c => c.c.start)) : Infinity);
    const sortKey = (a, b) =>
      ((a.figure && a.figure.order) ?? Infinity) - ((b.figure && b.figure.order) ?? Infinity) || birth(a) - birth(b) || first(a) - first(b) || ord.get(a) - ord.get(b) || 0;
    const roots = [...set].filter(nd => !treeParent.has(nd)).sort(sortKey);
    const list = [];
    const seen = new Set();
    const visit = start => {
      const stack = [start];
      while (stack.length) {
        const nd = stack.pop();
        if (seen.has(nd)) continue;
        seen.add(nd);
        list.push(nd);
        const ks = (kidsOf.get(nd) || []).slice().sort(sortKey);
        for (let k = ks.length - 1; k >= 0; k--) stack.push(ks[k]);
      }
    };
    for (const r of roots) visit(r);
    for (const nd of [...set].sort((a, b) => ord.get(a) - ord.get(b))) if (!seen.has(nd)) visit(nd); // 고리 — 뿌리로
    const n = list.length;
    const idx = new Map(list.map((nd, i) => [nd, i]));
    const par = new Int32Array(n).fill(-1);
    const gen = new Int32Array(n);
    const edge = new Int32Array(n);
    for (let i = 0; i < n; i++) {
      const e = treeParent.get(list[i]);
      if (e && idx.get(e.node) < i) {
        par[i] = idx.get(e.node);
        gen[i] = gen[par[i]] + (e.as === 'ancestor' ? e.gen || 1 : 1);
        edge[i] = /^adoptive-/.test(e.as || '') ? 1 : e.as === 'ancestor' ? 2 : 0;
      }
    }
    const size = new Int32Array(n).fill(1);
    for (let i = n - 1; i > 0; i--) if (par[i] >= 0) size[par[i]] += size[i];
    // 자식이 앞 차례 구간 밖으로 나가지 않게(고리로 뿌리가 된 마디의 자식 등) — 대역은 앞 차례 = 보이는 차례로 다시 맞춘다
    for (let i = 0; i < n; i++) if (par[i] >= 0 && !(i > par[i] && i < par[i] + size[par[i]])) par[i] = -1;
    const extra = [];
    const bits = new Int32Array(n);
    const branchList = houseIds ? houseIds.map(id => model.houseMap.get(id)).filter(Boolean) : [];
    const bIndex = new Map(branchList.map((h, j) => [h.id, j]));
    const colors = [''];
    const cIndex = new Map([['', 0]]);
    const ci = c => {
      if (!cIndex.has(c)) {
        cIndex.set(c, colors.length);
        colors.push(c);
      }
      return cIndex.get(c);
    };
    const color = new Int32Array(n);
    const color2 = new Int32Array(n);
    const branch = new Int32Array(n);
    const name = [];
    const sub = [];
    const keys = [];
    const cells = {};
    for (let i = 0; i < n; i++) {
      const nd = list[i];
      for (const e of nd.parents) {
        if (!set.has(e.node) || (treeParent.get(nd) && treeParent.get(nd) === e)) continue;
        const j = idx.get(e.node);
        extra.push(j, i, /^adoptive-/.test(e.as || '') ? 1 : e.as === 'ancestor' ? 2 : 0, e.gen || 1);
        bits[i] |= BIT.side;
      }
      if (isMember(nd)) bits[i] |= BIT.member;
      if (nd.unknown) bits[i] |= BIT.unknown;
      if (nd.missing) bits[i] |= BIT.missing;
      const led = nd.cells.filter(c => c.kind === 'leader');
      if (led.length) bits[i] |= BIT.leader;
      if (nd.figure && nd.figure.lineageOnly) bits[i] |= BIT.lineage;
      const polities = [...new Set(led.map(c => c.p))];
      if (polities.length > 1) bits[i] |= BIT.two;
      if (polities[0]) color[i] = ci(polities[0].color || '');
      if (polities[1]) color2[i] = ci(polities[1].color || '');
      branch[i] = nd.houseId && bIndex.has(nd.houseId) ? bIndex.get(nd.houseId) : 0;
      name.push(nd.unknown ? '미상' : nd.name || '');
      sub.push(led.length ? led.map(c => `${c.p.name}`).join(' · ') : '');
      keys.push(nd.key);
      for (const c of led) cells[`${c.p.uid}|${c.ref}`] = i;
    }
    const branches = branchList.map(h => {
      const f = h.parent ? list.findIndex(nd => nd.name && nd.name === h.founder) : -1;
      if (f >= 0) bits[f] |= BIT.founder;
      return { uid: h.uid, name: h.name || h.id, color: h.color || '', at: f, up: h.parent && bIndex.has(h.parent) ? bIndex.get(h.parent) : -1 };
    });
    return { n, par, size, gen, bits, edge, branch, color, color2, name, sub, key: keys, extra, colors, branches, cells, warnings: [], _index: new Map(keys.map((k, i) => [k, i])) };
  };
  const skelOf = (model, key) => {
    let m = cache.get(model);
    if (!m) cache.set(model, (m = new Map()));
    if (!m.has(key)) m.set(key, build(model, key));
    return m.get(key);
  };
  HT.kinSkeleton = skelOf;
  HT.kinOf = (model, p, i) => {
    const nd = HT.personOf(model, p, `leader:${i}`);
    if (!nd) return null;
    const key = nd.houseId ? `kin:${rootOf(model, nd.houseId)}` : `kin:polity:${p.uid}`;
    const sk = skelOf(model, key);
    const at = sk ? sk._index.get(nd.key) : undefined;
    return at == null ? null : { key, at };
  };
  HT.kinLayout = layoutStandIn;
  HT.kinDefaultOpen = defaultOpenStandIn;
  HT.accessionLine = acc => {
    const a = acc || {};
    if (['usurpation', 'coup', 'conquest'].includes(a.how)) return 1;
    if (a.kinUnknown || a.howUnknown) return 2;
    if (a.how === 'abdication') return 3;
    if (a.how === 'restoration') return 4;
    if (a.kin || a.how) return 5;
    return 0;
  };
  HT.accessionSeam = (model, r) => [r.accession.kinName, r.accession.howName].filter(Boolean).join(' · ');
  HT.polityHead = (model, p) =>
    [
      { role: 'track', text: (model.trackMap.get(p.track) || {}).name || '', field: 'track' },
      { role: 'people', text: p.peopleName || '', field: 'people' },
      { role: 'name', text: p.name || '', uid: p.uid, field: 'name' },
    ].filter(c => c.text);
  HT.houseHead = (model, h) => [{ role: 'name', text: h.name || h.id, uid: h.uid, field: 'name' }, { role: 'track', text: '대역 구분', auto: true, field: 'track' }];
  HT.houseUnder = underOf;
  HT.houseSpans = (model, ids) => {
    const set = new Set(ids);
    const out = [];
    for (const id of set) {
      const h = model.houseMap.get(id);
      for (const mb of (h && h.members) || []) {
        if ((mb.role === 'leader' || mb.role === 'cabinet') && mb.cell) {
          const sp = HT.cellSpan(mb.cell, mb.item, mb.ref);
          out.push({ uid: mb.item.uid, start: sp.lo, end: sp.hi });
        } else if (mb.role === 'dynasty' && mb.item)
          for (const hh of mb.item.hosts || []) for (const d of hh.host.dynasties || []) if (d.dynasty === mb.item) out.push({ uid: hh.host.uid, start: d.start, end: d.end });
      }
    }
    return out;
  };
  HT.houseEras = (model, id) => {
    const h = model.houseMap.get(id);
    const by = new Map();
    for (const mb of (h && h.members) || [])
      if (mb.role === 'leader' && mb.cell) (by.get(mb.item) || by.set(mb.item, []).get(mb.item)).push({ start: mb.cell.start, end: mb.cell.end ?? mb.item.endY });
    return [...by].map(([p, cells]) => ({ uid: p.uid, name: p.name, color: p.color, start: p.start, end: p.endY, cells }));
  };
  return true;
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  일꾼(--worker <job.json>): 거울의 base.mjs로 내보내 결과를 파일로
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
async function worker(jobFile) {
  const job = JSON.parse(fs.readFileSync(jobFile, 'utf8'));
  const base = await import(pathToFileURL(path.join(job.mirror, 'prototype', 'scripts', 'export', 'base.mjs')).href);
  let ctx;
  let HT;
  if (job.pack) {
    process.env.HT_EXPORT_PACK = job.pack;
    ctx = await base.loadContext();
    HT = ctx.HT;
  } else {
    HT = base.bootWeb();
    const raws = job.samples.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));
    ctx = base.contextOf(HT, raws, job.samples.slice(1));
  }
  const standIn = job.standIn ? installStandIns(HT) : false;
  const t0 = Date.now();
  const has = name => fs.existsSync(path.join(job.mirror, 'prototype', 'scripts', 'export', `${name}.mjs`));
  const out = await base.runModules(ctx, { has });
  const ms = Date.now() - t0;
  const res = { ms, standIn, helpers: HELPERS.filter(k => typeof HT[k] === 'function'), notes: ctx.notes };
  if (job.out) fs.writeFileSync(job.out, JSON.stringify(out) + '\n');
  if (job.htpack) fs.writeFileSync(job.htpack, await HT.packFile.build(ctx.raw));
  if (job.golden) res.golden = goldenOf(HT, ctx.model, out, job.golden);
  // W1이 HT.kinRecord(앱용 열 꼴 기록 — 2-4 자)를 두었으면 export/kin.mjs의 기록과 바이트까지 같은지(두 구현이 갈라지지 않게)
  if (typeof HT.kinRecord === 'function') {
    const kin = await import(pathToFileURL(path.join(job.mirror, 'prototype', 'scripts', 'export', 'kin.mjs')).href);
    const diff = [];
    for (const e of out.entities.filter(q => q.kind === 'kin' && !JSON.parse(q.json).root)) {
      const skel = HT.kinSkeleton(ctx.model, e.uid);
      const mine = kin.splitKin(kin.recordOf(skel, e.uid), kin.KIN_LIMIT).map(r => JSON.stringify(r));
      const theirs = Array.from(HT.kinRecord(skel, { limit: kin.KIN_LIMIT }) || [], r => (typeof r.json === 'string' ? r.json : JSON.stringify(r.json)));
      if (JSON.stringify(mine) !== JSON.stringify(theirs)) diff.push(e.uid);
    }
    res.kinRecordDiff = diff;
  }
  fs.writeFileSync(job.result, JSON.stringify(res) + '\n');
}
const HELPERS = ['kinSkeleton', 'kinOf', 'kinLayout', 'kinDefaultOpen', 'successionRows', 'kinRecord', 'accessionLine', 'accessionSeam', 'polityHead', 'houseHead', 'houseSpans', 'houseUnder', 'houseEras'];

/** 결정적 난수(LCG — 씨앗 20260921) */
const lcg = seed => {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
};
const arr = v => Array.from(v || []);
const closedOf = open => {
  const out = [];
  for (let i = 0; i < open.length; i++) if (!open[i]) out.push(i);
  return out;
};

/** 정답 자리(이음새 기록 ⑥): 뼈대마다 모두 펼침 · 기본 · 접힘 32가지의 HT.kinLayout, 정권마다 승계표 줄(HT.successionRows가 있을 때). */
function goldenOf(HT, model, out, opt) {
  const g = { v: 1, sample: opt.sample, records: `kin-${opt.sample}.json`, by: opt.standIn ? 'stand-in' : 'HT', layout: [], succession: [] };
  const roots = out.entities.filter(e => e.kind === 'kin' && !JSON.parse(e.json).root).map(e => e.uid);
  const rnd = lcg(20260921);
  for (const uid of roots.slice(0, opt.maxSkeletons || roots.length)) {
    const skel = HT.kinSkeleton(model, uid);
    const n = skel.n ?? skel.par.length;
    const states = [];
    const take = (name, open) => {
      const r = HT.kinLayout(skel, open);
      states.push({ name, closed: closedOf(open), x: arr(r.x), w: arr(r.w), rows: arr(r.rows).map(arr), width: r.width });
    };
    take('all', new Uint8Array(n).fill(1));
    take('default', Uint8Array.from(HT.kinDefaultOpen(skel)));
    if (n > 1)
      for (let k = 1; k <= 32; k++) {
        const p = ((k % 4) + 1) / 8;
        const open = new Uint8Array(n).fill(1);
        for (let i = 0; i < n; i++) if ((skel.size[i] | 0) > 1 && rnd() < p) open[i] = 0;
        take(`fold-${String(k).padStart(2, '0')}`, open);
      }
    g.layout.push({ uid, n, states });
  }
  if (typeof HT.successionRows === 'function') {
    // 승계표 줄: 지도자 둘 이상인 나라마다 처음(지도자만) · 수준 넷(HT.successionOpen이 있으면) — open과 줄은 웹 도우미가 주고받는 꼴 그대로
    const plain = v => (v == null ? null : ArrayBuffer.isView(v) ? arr(v) : Array.isArray(v) ? v.map(plain) : typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, q]) => [k, plain(q)])) : v);
    for (const p of model.periods || []) {
      if (p.kind !== 'period' || (p.leaders || []).length < 2) continue;
      const states = [];
      try {
        const levels = typeof HT.successionOpen === 'function' ? ['leaders', 'children', 'branches', 'all'] : [];
        states.push({ name: 'default', open: null, rows: arr(HT.successionRows(model, p)) });
        for (const lv of levels) {
          const open = HT.successionOpen(model, p, lv);
          states.push({ name: lv, open: plain(open), rows: arr(HT.successionRows(model, p, open)) });
        }
      } catch (e) {
        g.successionError = String(e && e.message);
        break;
      }
      if (states.some(st => st.rows.length > 3 * (p.leaders || []).length) || opt.allPolities) g.succession.push({ polity: p.uid, states });
      else if (g.succession.length < 3) g.succession.push({ polity: p.uid, states }); // 줄이 펼쳐지지 않는 나라는 셋까지만(크기)
    }
  }
  return g;
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  ② 열 꼴 기록 — 손으로 만든 뼈대(모델 없이)
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
/** 손 뼈대: 숲 r개 · 자식 수 · 파조 · 양자 덧선 · 건너뜀 · 이름 미상 · 두 나라 — 결정적 */
function handSkeleton({ n, roots = 2, seed = 20260921, founders = 6, extras = 0.03 }) {
  const rnd = lcg(seed);
  const parent = new Int32Array(n).fill(-1);
  // 트리: 앞 차례가 곧 마디 번호가 되도록 부모 → 자식 목록을 지은 뒤 앞 차례로 다시 매긴다
  const kids = Array.from({ length: n }, () => []);
  for (let i = roots; i < n; i++) {
    const p = Math.floor(rnd() * Math.min(i, Math.max(roots, Math.floor(i * 0.9) + 1)));
    parent[i] = p;
    kids[p].push(i);
  }
  const order = [];
  const stack = [];
  for (let r = roots - 1; r >= 0; r--) stack.push(r);
  while (stack.length) {
    const v = stack.pop();
    order.push(v);
    for (let k = kids[v].length - 1; k >= 0; k--) stack.push(kids[v][k]);
  }
  const pos = new Int32Array(n);
  order.forEach((v, i) => (pos[v] = i));
  const par = new Int32Array(n).fill(-1);
  for (let i = 0; i < n; i++) par[pos[i]] = parent[i] >= 0 ? pos[parent[i]] : -1;
  const size = new Int32Array(n).fill(1);
  for (let i = n - 1; i > 0; i--) if (par[i] >= 0) size[par[i]] += size[i];
  const gen = new Int32Array(n);
  const edge = new Int32Array(n);
  for (let i = 0; i < n; i++)
    if (par[i] >= 0) {
      const skip = rnd() < 0.01 ? 2 + Math.floor(rnd() * 5) : 1;
      gen[i] = gen[par[i]] + skip;
      edge[i] = skip > 1 ? 2 : rnd() < 0.03 ? 1 : 0;
      if (rnd() < 0.05) edge[i] += 4;
    }
  const bits = new Int32Array(n);
  const branch = new Int32Array(n);
  const color = new Int32Array(n);
  const color2 = new Int32Array(n);
  const branches = [{ uid: 'house:hand-root', name: '손 뿌리 가문', color: '#a0bcc5', at: -1, up: -1 }];
  const big = [];
  for (let i = 0; i < n; i++) if (size[i] >= Math.max(3, Math.floor(n / 40))) big.push(i);
  for (let k = 0; k < founders && big.length; k++) {
    const f = big[Math.floor(rnd() * big.length)];
    if (bits[f] & BIT.founder) continue;
    bits[f] |= BIT.founder;
    const up = (() => {
      for (let a = par[f]; a >= 0; a = par[a]) if (bits[a] & BIT.founder) return branches.findIndex(b => b.at === a);
      return 0;
    })();
    branches.push({ uid: `house:hand-b${k}`, name: `손 가지 ${k}파`, color: `#${(0x405060 + k * 0x101010).toString(16)}`, at: f, up });
  }
  // 파 번호: 가장 가까운 파조 조상(자기 포함)
  for (let i = 0; i < n; i++) {
    const b = branches.findIndex(q => q.at === i);
    branch[i] = b > 0 ? b : par[i] >= 0 ? branch[par[i]] : 0;
  }
  const extra = [];
  for (let i = 0; i < n; i++) {
    bits[i] |= rnd() < 0.85 ? BIT.member : 0;
    if (rnd() < 0.02) bits[i] |= BIT.unknown;
    if (rnd() < 0.02) bits[i] |= BIT.lineage;
    if (rnd() < 0.03) {
      bits[i] |= BIT.leader;
      color[i] = 1 + Math.floor(rnd() * 3);
      if (rnd() < 0.2) {
        bits[i] |= BIT.two;
        color2[i] = 1 + Math.floor(rnd() * 3);
      }
    }
    if (i > 0 && rnd() < extras) {
      const from = Math.floor(rnd() * n);
      if (from !== i) {
        extra.push([from, i, 1, 1]);
        bits[i] |= BIT.side;
      }
    }
  }
  const cells = new Map();
  for (let i = 0; i < n; i++) if (bits[i] & BIT.leader) cells.set(`hand/p${i % 5}|leader:${i}`, i);
  return {
    n, par, size, gen, bits, edge, branch, color, color2, colors: ['', '#a0bcc5', '#d8b48a', '#9fc29a'], branches, extra, cells,
    name: Array.from({ length: n }, (_, i) => (bits[i] & BIT.unknown ? '미상' : `가상${i}`)),
    sub: Array.from({ length: n }, (_, i) => (bits[i] & BIT.leader ? `손 나라 ${i}대` : '')),
    key: Array.from({ length: n }, (_, i) => `f:hand/p-${i}`),
    warnings: ['손 뼈대 — 검사용'],
  };
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  본 점검
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
async function main() {
  const kinMod = await import(pathToFileURL(path.join(HERE, 'export', 'kin.mjs')).href);
  const { recordOf, splitKin, joinKin, KIN_LIMIT } = kinMod;
  const standIn = flag('--stand-in');
  const webRev = arg('--web', 'HEAD');
  const baseRev = arg('--base', 'd1d6e18');
  const tool = arg('--tool', process.env.HT_ARCHIVE_TOOL || '');
  const writeFixtures = !flag('--no-fixtures');
  const tmp = path.resolve(process.env.HT_KIN_TMP || path.join(PROTOTYPE, 'results', 'kin-check'));
  fs.mkdirSync(tmp, { recursive: true });
  const report = { 웹: webRev, 이전모듈: baseRev, 대역: standIn, 열꼴: {}, 대조: {}, 견본: {}, 문제: [], 결합때: [] };
  const problem = (where, text) => report.문제.push(`${where}: ${text}`);
  const MB = n => Math.round((n / 1048576) * 1000) / 1000;

  /* ---------- ② 열 꼴 기록 (모델 없이) ---------- */
  {
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const cases = [
      { name: '작은 숲 · 상한 7', n: 60, roots: 3, limit: 7 },
      { name: '중간 · 상한 50', n: 900, roots: 2, limit: 50, founders: 10 },
      { name: '파조 없음 · 상한 30', n: 400, roots: 1, limit: 30, founders: 0 },
      { name: `5만 + 1 · 상한 ${KIN_LIMIT}`, n: KIN_LIMIT + 1, roots: 1, limit: KIN_LIMIT, founders: 12 },
    ];
    for (const c of cases) {
      const skel = handSkeleton(c);
      const rec = recordOf(skel, 'kin:hand-root');
      const again = recordOf(skel, 'kin:hand-root');
      const row = { 마디: rec.n, 기록KB: Math.round(JSON.stringify(rec).length / 1024) };
      if (!same(rec, again)) problem(c.name, '같은 뼈대의 기록이 두 번 다르게 나옵니다');
      if (Object.keys(rec).join() !== 'v,uid,n,gens,par,size,gen,bits,edge,branch,color,color2,name,sub,key,extra,colors,branches,cells,stubs,warnings') problem(c.name, `열쇠 차례가 다릅니다: ${Object.keys(rec)}`);
      const parts = splitKin(rec, c.limit);
      row.덩어리 = parts.length;
      row.가장큰덩어리 = Math.max(...parts.map(p => p.n));
      if (parts.some(p => p.n > c.limit)) problem(c.name, `상한을 넘는 덩어리가 남았습니다(${row.가장큰덩어리})`);
      const uids = new Set(parts.map(p => p.uid));
      if (uids.size !== parts.length) problem(c.name, '덩어리 uid가 겹칩니다');
      let stubs = 0;
      let far = 0;
      for (const p of parts) {
        for (const [k, st] of Object.entries(p.stubs)) {
          stubs++;
          if (!uids.has(st.key)) problem(c.name, `꼬투리가 없는 덩어리를 가리킵니다: ${st.key}`);
          if (!(p.bits[k] & BIT.stub) || p.size[k] !== 1) problem(c.name, `꼬투리 마디의 비트 · size가 틀립니다: ${p.uid} ${k}`);
          const child = parts.find(q => q.uid === st.key);
          if (child.key[0] !== p.key[k] || child.root.upAt !== Number(k) || child.root.up !== p.uid) problem(c.name, `꼬투리와 덩어리 뿌리가 다른 사람입니다: ${st.key}`);
          if (child.par[0] !== -1) problem(c.name, `덩어리 뿌리의 par가 −1이 아닙니다: ${st.key}`);
        }
        far += (p.extraFar || []).length;
        if (p.root && p.warnings.length) problem(c.name, '덩어리 기록에 경고가 실렸습니다(뿌리 기록에만)');
      }
      row.꼬투리 = stubs;
      row.걸친덧선 = far;
      // 파조 꼬투리는 kin:<파 가문 id>
      for (const p of parts) if (p.root && (p.bits[0] & BIT.founder) && !/^kin:hand-b\d+$/.test(p.uid)) problem(c.name, `파조 덩어리의 uid가 kin:<파 id>가 아닙니다: ${p.uid}`);
      const joined = joinKin(parts);
      if (!same(joined, rec)) {
        const diff = Object.keys(rec).filter(k => !same(rec[k], joined[k]));
        problem(c.name, `합친 기록이 한 벌과 다릅니다: ${diff.join(', ')}`);
      }
      // 일부만 받은 합치기(뿌리 + 덩어리 하나) — 남은 꼬투리가 그대로
      if (parts.length > 2) {
        const partial = joinKin([parts[0], parts[1]]);
        const left = Object.keys(partial.stubs).length;
        const count = p => Object.keys(p.stubs).length;
        const want = parts[1].root.up === parts[0].uid ? count(parts[0]) - 1 + count(parts[1]) : count(parts[0]);
        if (left !== want) problem(c.name, `일부 합치기의 남은 꼬투리 수가 틀립니다(${left} — 기대 ${want})`);
      }
      // 정수 칸 셈(4-4 대역 구현): 합친 것 = 한 벌, 모두 펼침 폭 = Σ 잎, 카드 겹침 0
      const rnd = lcg(7);
      for (let t = 0; t < 4; t++) {
        const open = new Uint8Array(rec.n).fill(1);
        if (t) for (let i = 0; i < rec.n; i++) if (rec.size[i] > 1 && rnd() < t / 6) open[i] = 0;
        const a = layoutStandIn(rec, open);
        const b = layoutStandIn(joined, open);
        if (!same(arr(a.x), arr(b.x)) || a.width !== b.width) problem(c.name, '합친 기록의 자리가 한 벌과 다릅니다');
        for (const r of a.rows) for (let k = 1; k < r.length; k++) if (a.x[r[k]] - a.x[r[k - 1]] < 4) problem(c.name, `같은 세대 카드가 겹칩니다(${r[k - 1]} · ${r[k]})`);
      }
      // 덩어리 하나만으로도 셈이 돈다(꼬투리 = 접힌 마디)
      const solo = layoutStandIn(parts[0], new Uint8Array(parts[0].n).fill(1));
      if (!(solo.width > 0)) problem(c.name, '뿌리 덩어리 혼자 셈한 폭이 0입니다');
      report.열꼴[c.name] = row;
    }
    // 덧선 차례 · color2 비움 · 칸 표 차례
    const s = handSkeleton({ n: 30, roots: 1, extras: 0.3 });
    s.color2 = new Int32Array(30);
    const r = recordOf(s, 'kin:x');
    if (r.color2.length) problem('열 꼴', '두 나라가 없는데 color2가 비지 않았습니다');
    for (let k = 4; k < r.extra.length; k += 4) if (r.extra[k + 1] < r.extra[k - 3] || (r.extra[k + 1] === r.extra[k - 3] && r.extra[k] < r.extra[k - 4])) problem('열 꼴', '덧선 차례가 (to, from) 오름이 아닙니다');
  }

  /* ---------- 거울 짓기 ---------- */
  const git = (...a) => execFileSync('git', a, { cwd: ROOT, maxBuffer: 1 << 30 });
  const mirror = (name, exportFrom) => {
    const dir = path.join(tmp, name);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    const webPaths = ['js', 'packs', 'samples', 'index.html', 'prototype/scripts/export-layout.mjs'];
    if (webRev === 'live') {
      for (const p of webPaths) fs.cpSync(path.join(ROOT, p), path.join(dir, p), { recursive: true });
    } else {
      const tar = path.join(tmp, `${name}.tar`);
      fs.writeFileSync(tar, git('archive', '--format=tar', webRev, ...webPaths));
      execFileSync('tar', ['-xf', tar, '-C', dir]);
      fs.rmSync(tar);
    }
    const exp = path.join(dir, 'prototype', 'scripts', 'export');
    fs.rmSync(exp, { recursive: true, force: true });
    fs.mkdirSync(exp, { recursive: true });
    if (exportFrom === 'live') {
      for (const f of fs.readdirSync(path.join(HERE, 'export'))) if (f.endsWith('.mjs')) fs.copyFileSync(path.join(HERE, 'export', f), path.join(exp, f));
    } else {
      const tar = path.join(tmp, `${name}-export.tar`);
      // 옛 2판 시연(_v2-원본.mjs)은 일꾼이 부르지 않고, 한글 파일 이름이라 Windows의 tar가 풀지 못한다 — 빼고 편다.
      fs.writeFileSync(tar, git('archive', '--format=tar', exportFrom, 'prototype/scripts/export', ':(exclude)prototype/scripts/export/_v2-*'));
      execFileSync('tar', ['-xf', tar, '-C', dir]);
      fs.rmSync(tar);
    }
    return dir;
  };
  const oldDir = mirror('이전', baseRev);
  const newDir = mirror('지금', 'live');
  let jobN = 0;
  const run = job => {
    const file = path.join(tmp, `job-${++jobN}.json`);
    job.result = path.join(tmp, `result-${jobN}.json`);
    fs.writeFileSync(file, JSON.stringify(job));
    const r = spawnSync(process.execPath, ['--max-old-space-size=6144', fileURLToPath(import.meta.url), '--worker', file], { stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 28 });
    if (r.status !== 0) throw new Error(`일꾼이 실패했습니다(${job.what}): ${r.stderr.toString().slice(-3000)}`);
    return JSON.parse(fs.readFileSync(job.result, 'utf8'));
  };

  /* ---------- ① 바이트 대조 ---------- */
  const ALLOWED = {
    // x_spots를 뺌: 웹 HT.houseSpans(지도자 칸 · 지도자 칸 없는 나라의 국성 기간 — 확정 설계 5-3)에 내각 · 왕조 칸만 있는 가문은 구간이 없다(A1-a는 내각 · 왕조 칸까지 담았음 — 보고에 셈)
    house: { removed: ['x_family', 'x_spots'], added: ['x_kin', 'x_head', 'x_under', 'x_eras', 'x_memberCount'], changed: ['x_spots', 'x_members'] },
    period: { added: ['x_lineage', 'x_head'], changed: ['x_lineage'] },
    surname: { added: ['x_spots'] },
  };
  const compare = (where, a, b) => {
    const A = JSON.parse(fs.readFileSync(a, 'utf8'));
    const B = JSON.parse(fs.readFileSync(b, 'utf8'));
    const row = { 바깥: '같음', 기록: {} };
    for (const k of new Set([...Object.keys(A), ...Object.keys(B)])) {
      if (k === 'entities') continue;
      if (JSON.stringify(A[k]) !== JSON.stringify(B[k])) {
        row.바깥 = '다름';
        problem(where, `entities 밖의 '${k}'가 다릅니다`);
      }
    }
    const ea = new Map(A.entities.map(e => [e.uid, e]));
    const eb = new Map(B.entities.map(e => [e.uid, e]));
    const bump = (kind, what, key) => {
      const o = (row.기록[kind] = row.기록[kind] || {});
      const k = key ? `${what} ${key}` : what;
      o[k] = (o[k] || 0) + 1;
    };
    for (const [uid, e] of eb) if (!ea.has(uid)) bump(e.kind, '새 기록');
    for (const [uid, e] of ea) {
      const f = eb.get(uid);
      if (!f) {
        bump(e.kind, '없어진 기록');
        problem(where, `기록이 없어졌습니다: ${uid}`);
        continue;
      }
      if (e.json === f.json && e.pack === f.pack && e.kind === f.kind) continue;
      if (e.kind !== f.kind || e.pack !== f.pack) problem(where, `갈래 · 귀속이 바뀌었습니다: ${uid}`);
      const x = JSON.parse(e.json);
      const y = JSON.parse(f.json);
      const allow = ALLOWED[e.kind] || {};
      for (const k of new Set([...Object.keys(x), ...Object.keys(y)])) {
        if (!(k in y)) {
          bump(e.kind, '뺀 열쇠', k);
          if (!(allow.removed || []).includes(k)) problem(where, `허용하지 않은 열쇠를 뺐습니다: ${uid} ${k}`);
        } else if (!(k in x)) {
          bump(e.kind, '더한 열쇠', k);
          if (!(allow.added || []).includes(k)) problem(where, `허용하지 않은 열쇠를 더했습니다: ${uid} ${k}`);
        } else if (JSON.stringify(x[k]) !== JSON.stringify(y[k])) {
          bump(e.kind, '바뀐 열쇠', k);
          if (!(allow.changed || []).includes(k)) problem(where, `허용하지 않은 열쇠가 바뀌었습니다: ${uid} ${k}`);
          if (k === 'x_lineage') {
            // 지금 있던 줄의 값은 그대로(더해지기만 — line · seam · kinAt)
            for (const [ref, l] of Object.entries(x[k])) {
              const m = y[k][ref] || {};
              for (const kk of Object.keys(l)) if (JSON.stringify(l[kk]) !== JSON.stringify(m[kk])) problem(where, `x_lineage의 있던 값이 바뀌었습니다: ${uid} ${ref} ${kk}`);
              for (const kk of Object.keys(m)) if (!(kk in l) && !['line', 'seam', 'kinAt'].includes(kk)) problem(where, `x_lineage에 허용하지 않은 칸: ${uid} ${ref} ${kk}`);
            }
          }
          if (k === 'x_members' && !(y.x_memberCount > 200)) problem(where, `x_members가 상한 없이 바뀌었습니다: ${uid}`);
        }
      }
    }
    const lost = (row.기록.house || {})['뺀 열쇠 x_spots'];
    if (lost) report.결합때.push(`${where}: 가문 ${lost}개의 x_spots가 없어짐 — 웹 HT.houseSpans가 지도자 칸만 셈(내각 · 왕조 칸만 있는 가문). A1-a 때는 내각 · 왕조 칸까지 조명했음 — 감독 · W1 확인거리`);
    row.기록수 = `${A.entities.length} → ${B.entities.length}`;
    row.항목기록MB = `${MB(A.entities.reduce((s, e) => s + e.json.length, 0))} → ${MB(B.entities.reduce((s, e) => s + e.json.length, 0))}`;
    return row;
  };
  const configs = flag('--skip-compare') ? [] : [{ name: '등불연대기', samples: ['sample-lantern'] }];
  if (!flag('--skip-east-asia') && !flag('--skip-compare')) configs.push({ name: '동아시아', pack: 'east-asia' });
  if (flag('--skip-compare')) report.결합때.push('① 바이트 대조(등불 연대기 · 동아시아)를 --skip-compare로 건너뜀 — PC에서 이것 없이 다시 돌림');
  for (const c of configs) {
    const job = d => (c.pack ? { pack: c.pack } : { samples: c.samples.map(s => path.join(d, 'samples', `${s}.json`)) });
    const a = path.join(tmp, `${c.name}-이전.json`);
    const b = path.join(tmp, `${c.name}-지금.json`);
    const ra = run(Object.assign(job(oldDir), { what: `${c.name} 이전`, mirror: oldDir, out: a }));
    const rb = run(Object.assign(job(newDir), { what: `${c.name} 지금`, mirror: newDir, out: b, standIn }));
    const row = compare(c.name, a, b);
    row.내보내기ms = `${ra.ms} → ${rb.ms}`;
    row.계보 = rb.notes.계보 || '웹 도우미 없음 — 뼈대 기록 0';
    row.웹도우미 = rb.helpers.length ? rb.helpers.join(' · ') : '없음';
    report.대조[c.name] = row;
  }

  /* ---------- ③ ④ 견본 내보내기 · 정답 자리 · 앱 고정 자료 ---------- */
  const samples = [];
  for (const s of ['sample-lantern']) if (fs.existsSync(path.join(newDir, 'samples', `${s}.json`))) samples.push({ name: s, files: [path.join(newDir, 'samples', `${s}.json`)] });
  const family = arg('--family', '');
  for (const one of family.split(',').filter(Boolean)) {
    const [name, rest] = one.includes('=') ? one.split('=') : [path.basename(one, '.json'), one];
    const [file, before] = rest.split('@');
    samples.push({ name, files: [path.resolve(file)], family: true, before: before ? [path.resolve(before)] : [path.resolve(file)] });
  }
  const fixtures = path.join(PROTOTYPE, 'app', 'test', 'fixtures');
  for (const s of samples) {
    const outFile = path.join(tmp, `${s.name}.json`);
    const htpack = path.join(tmp, `${s.name}.htpack`);
    const res = run({ what: s.name, mirror: newDir, samples: s.files, out: outFile, htpack, standIn, golden: { sample: s.name, standIn } });
    const out = JSON.parse(fs.readFileSync(outFile, 'utf8'));
    const small = !s.family || (res.notes.계보 && res.notes.계보.마디 <= 2000); // 앱 고정 자료로 쓸 만큼 작은가
    const row = { 내보내기ms: res.ms, 웹도우미: res.helpers.length ? res.helpers.join(' · ') : '없음', 대역: res.standIn, 계보: res.notes.계보 || null };
    const kinRecs = out.entities.filter(e => e.kind === 'kin');
    const byUid = new Map(out.entities.map(e => [e.uid, e]));
    row.뼈대기록 = kinRecs.length;
    if (!res.helpers.includes('kinSkeleton')) {
      report.결합때.push(`${s.name}: 웹 도우미 HT.kinSkeleton이 없어 뼈대 기록 0 — D1-W1이 들어오면(또는 --stand-in) 다시 돌림`);
      report.견본[s.name] = row;
      continue;
    }
    if (!kinRecs.length) problem(s.name, '뼈대 기록(갈래 kin)이 없습니다');
    // 기록마다 다시 풀어 꼴 확인
    for (const e of kinRecs) {
      const b = JSON.parse(e.json);
      if (b.uid !== e.uid) problem(s.name, `기록 머리 uid가 엔트리 uid와 다릅니다: ${e.uid}`);
      for (const k of ['par', 'size', 'gen', 'bits', 'edge', 'branch', 'color', 'name', 'sub', 'key']) if (b[k].length !== b.n) problem(s.name, `열 ${k}의 길이가 n이 아닙니다: ${e.uid}`);
      const seenKey = new Set(b.key);
      if (seenKey.size !== b.n) problem(s.name, `한 뼈대에 같은 사람이 두 번 있습니다: ${e.uid}`);
      let sum = 0;
      for (let i = 0; i < b.n; i++) if (b.par[i] < 0) sum += b.size[i];
      if (sum !== b.n) problem(s.name, `뿌리 size 합이 n이 아닙니다: ${e.uid}`);
    }
    // x_kin · kinAt이 가리키는 마디가 그 사람인가
    let pointed = 0;
    for (const e of out.entities) {
      const b = JSON.parse(e.json);
      const keyOk = (where, key, at, want) => {
        pointed++;
        const r = byUid.get(key);
        if (!r) return problem(s.name, `${where}: 뼈대 기록이 없습니다 ${key}`);
        const rec = JSON.parse(r.json);
        if (Object.keys(rec.stubs).length) return; // 나눈 뼈대는 한 벌 번호 — 아래 합치기 검사에서
        if (want && rec.key[at] !== want) problem(s.name, `${where}: ${key}[${at}]가 ${want}가 아니라 ${rec.key[at]}`);
      };
      if (e.kind === 'figure' && b.lineageOnly) {
        if ('services' in b || 'importance' in b) problem(s.name, `계보 전용 인물 기록에 활동 칸이 있습니다: ${e.uid}`);
        if ('x_person' in b || 'x_services' in b) problem(s.name, `계보 전용 인물 기록에 x_person · x_services가 있습니다: ${e.uid}`);
        if (!b.x_kin) problem(s.name, `계보 전용 인물에 x_kin이 없습니다: ${e.uid}`);
        else keyOk(e.uid, b.x_kin.key, b.x_kin.at, `f:${e.uid}`);
        if (!(b.x_find && /^계보 전용/.test(b.x_find.sub || ''))) problem(s.name, `계보 전용 인물의 찾을 글 곁글이 없습니다: ${e.uid}`);
      }
      if (e.kind === 'house' && b.x_family) problem(s.name, `가문 기록에 x_family가 남았습니다: ${e.uid}`);
      if (e.kind === 'house' && b.x_kin) keyOk(e.uid, b.x_kin.key, b.x_kin.at ?? null, null);
      for (const [ref, l] of Object.entries(b.x_lineage || {})) if (l.kinAt) keyOk(`${e.uid} ${ref}`, l.kinAt[0], l.kinAt[1], null);
    }
    row.가리킴 = pointed;
    if (res.kinRecordDiff) {
      row.HT_kinRecord = res.kinRecordDiff.length ? `export/kin.mjs와 다름 ${res.kinRecordDiff.length}` : 'export/kin.mjs와 같음';
      if (res.kinRecordDiff.length) problem(s.name, `HT.kinRecord(웹)와 export/kin.mjs의 기록이 다릅니다: ${res.kinRecordDiff.slice(0, 5).join(', ')}`);
    }
    // 작은 상한으로 나눠 다시 합치기 = 한 벌(견본의 진짜 뼈대로)
    const roots = kinRecs.map(e => JSON.parse(e.json)).filter(b => !b.root);
    const biggest = roots.sort((a, b) => b.n - a.n)[0];
    if (biggest && biggest.n > 4) {
      const limit = Math.max(3, Math.floor(biggest.n / 3));
      const parts = splitKin(biggest, limit);
      const joined = joinKin(parts);
      if (JSON.stringify(joined) !== JSON.stringify(biggest)) problem(s.name, '견본 뼈대를 나눠 합친 것이 한 벌과 다릅니다');
      row.나눠합치기 = `${biggest.uid} ${biggest.n}마디 → 상한 ${limit} · ${parts.length}덩어리 → 한 벌과 같음`;
      if (writeFixtures && !res.standIn && small) fs.writeFileSync(path.join(fixtures, `kin-chunks-${s.name}.json`), JSON.stringify({ limit, records: parts.map(p => ({ uid: p.uid, kind: 'kin', json: JSON.stringify(p) })) }, null, 1) + '\n');
    }
    // 정답 자리: 두 번 돌려 같은가 + 대역 구현과 같은가(웹 도우미가 있을 때 — 두 구현의 대조)
    const g = res.golden;
    row.정답 = { 뼈대: g.layout.length, 접힘: g.layout.reduce((a, l) => a + l.states.length, 0), 승계표: g.succession.length, 낸것: g.by };
    if (g.successionError) problem(s.name, `HT.successionRows가 실패했습니다: ${g.successionError}`);
    if (!g.succession.length && !res.helpers.includes('successionRows')) report.결합때.push(`${s.name}: 승계표 줄 정답(HT.successionRows) — W1 도우미가 들어오면 다시 돌림`);
    for (const l of g.layout) {
      const rec = roots.find(b => b.uid === l.uid) || JSON.parse(byUid.get(l.uid).json);
      for (const st of l.states) {
        const open = new Uint8Array(l.n).fill(1);
        for (const i of st.closed) open[i] = 0;
        const mine = layoutStandIn(rec, open);
        const visible = new Set(arr(mine.rows).flatMap(arr));
        const xs = st.x.filter((_, i) => visible.has(i));
        const ys = arr(mine.x).filter((_, i) => visible.has(i));
        if (JSON.stringify(xs) !== JSON.stringify(ys) || st.width !== mine.width || JSON.stringify(st.rows.filter(r => r.length)) !== JSON.stringify(arr(mine.rows).map(arr).filter(r => r.length)))
          problem(s.name, `정답 자리(${g.by})와 이 검사의 4-4 구현이 다릅니다: ${l.uid} ${st.name}`);
      }
    }
    const res2 = run({ what: `${s.name} 두 번째`, mirror: newDir, samples: s.files, out: null, standIn, golden: { sample: s.name, standIn } });
    if (JSON.stringify(res2.golden) !== JSON.stringify(g)) problem(s.name, '정답 자리가 두 번 돌려 다릅니다');
    // 앱 고정 자료(웹 도우미로 낸 것만 — 대역 결과는 임시 폴더에만)
    const fixtureDir = writeFixtures && !res.standIn && small && kinRecs.length ? fixtures : tmp;
    // 앱 고정 자료: 견본은 뼈대 · 가문 · 성씨 · 계보 전용 인물 · 승계 줄이 있는 정권, 가상 대가족은 뼈대 · 가문 + 정답 승계표의 정권만(크기 — 창 검사는 견본으로).
    // 정답의 succession에 든 정권은 늘 싣는다 — 앱 검사(kin_layout_test)가 그 정권 기록의 x_lineage[].kinAt으로 지도자 자리를 짓는다(D1 결합 때 고침: 가상 대가족에 정권이 빠져 있었음)
    const succPolities = new Set((g.succession || []).map(p => p.polity));
    const keep = out.entities.filter(e => ['kin', 'house'].includes(e.kind) || (e.kind === 'period' && succPolities.has(e.uid)) || (!s.family && (e.kind === 'surname' || (e.kind === 'figure' && JSON.parse(e.json).lineageOnly) || (e.kind === 'period' && JSON.parse(e.json).x_lineage))));
    fs.writeFileSync(path.join(fixtureDir, `kin-${s.name}.json`), JSON.stringify(keep.map(e => ({ uid: e.uid, kind: e.kind, json: e.json })), null, 1) + '\n');
    fs.writeFileSync(path.join(fixtureDir, `kin-golden-${s.name}.json`), JSON.stringify(g) + '\n');
    row.고정자료 = fixtureDir === fixtures ? `prototype/app/test/fixtures/kin-${s.name}.json · kin-golden-${s.name}.json · kin-chunks-${s.name}.json` : `임시 폴더만(${res.standIn ? '대역' : !small ? '크다' : '--no-fixtures'})`;
    if (res.standIn) report.결합때.push(`${s.name}: 웹 도우미(D1-W1)가 들어오면 --stand-in 없이 다시 돌려 앱 고정 자료 kin-*.json을 씀`);

    /* 가상 대가족: 이 일 전 모듈로 낸 항목 기록과 크기를 견준다(A1-a 기준의 두 배를 넘으면 문제 — 확정 설계 9-2 D1-E) */
    let before = null;
    if (s.family) {
      const oldOut = path.join(tmp, `${s.name}-이전.json`);
      try {
        const r0 = run({ what: `${s.name} 이전`, mirror: oldDir, samples: s.before, out: oldOut, htpack: path.join(tmp, `${s.name}-이전.htpack`) });
        const o = JSON.parse(fs.readFileSync(oldOut, 'utf8'));
        const sz = list => list.reduce((a, e) => a + e.json.length, 0);
        before = { out: oldOut, ms: r0.ms, htpack: path.join(tmp, `${s.name}-이전.htpack`) };
        row.이전대비 = { 견준판: path.basename(s.before[0]), 항목기록MB: `${MB(sz(o.entities))} → ${MB(sz(out.entities))}`, 배: Math.round((sz(out.entities) / sz(o.entities)) * 100) / 100, 내보내기ms: `${r0.ms} → ${res.ms}` };
        if (sz(out.entities) > 2 * sz(o.entities)) problem(s.name, `항목 기록이 이 일 전의 두 배를 넘습니다(${row.이전대비.항목기록MB}) — 멈추고 보고`);
      } catch (e) {
        row.이전대비 = `이 일 전 모듈로 내보낼 수 없음(${String(e.message).split('\n').find(l => /Error: /.test(l)) || '실패'}) — '@<띠 인물 판>'으로 견줌`;
      }
    }

    /* ⑤ 저장소 짓기 */
    if (tool) {
      if (before) {
        const db0 = path.join(tmp, `${s.name}-이전.db`);
        for (const f of [db0, `${db0}-wal`, `${db0}-shm`]) if (fs.existsSync(f)) fs.rmSync(f);
        const t = Date.now();
        execFileSync(tool, ['import-layout', before.htpack, before.out, db0], { stdio: ['ignore', 'pipe', 'pipe'] });
        row.이전대비.가져오기ms = Date.now() - t;
      }
      const db = path.join(tmp, `${s.name}.db`);
      for (const f of [db, `${db}-wal`, `${db}-shm`]) if (fs.existsSync(f)) fs.rmSync(f);
      const t0 = Date.now();
      execFileSync(tool, ['import-layout', htpack, outFile, db], { stdio: ['ignore', 'pipe', 'pipe'] });
      const ms = Date.now() - t0;
      const verify = JSON.parse(execFileSync(tool, ['verify-tiles', db, '2000']).toString().trim().split('\n').pop());
      const ask = q => JSON.parse(execFileSync(tool, ['query', db, JSON.stringify(q)], { maxBuffer: 1 << 28 }).toString());
      const big = kinRecs.slice().sort((a, b) => b.json.length - a.json.length)[0];
      const t1 = Date.now();
      const back = big ? ask({ op: 'entity', uid: big.uid }) : null;
      if (row.이전대비) row.이전대비.가져오기ms = `${row.이전대비.가져오기ms} → ${ms}`;
      row.엔진 = { 가져오기ms: ms, 저장소MB: MB(fs.statSync(db).size), 항목기록MB: MB(out.entities.reduce((a, e) => a + e.json.length, 0)), 뼈대기록MB: MB(kinRecs.reduce((a, e) => a + e.json.length, 0)), 타일: verify.타일, 누락_중복: verify.누락_중복, 가장큰뼈대entityms: Date.now() - t1 };
      if (verify.누락_중복 !== 0) problem(s.name, `verify-tiles 누락 · 중복 ${verify.누락_중복}`);
      if (big && !(back && back.kind === 'kin' && back.json === big.json)) problem(s.name, `엔진 entity가 뼈대 기록을 그대로 돌려주지 않습니다: ${big.uid}`);
    }
    report.견본[s.name] = row;
  }
  if (!family) report.결합때.push('가상 대가족(D1-T의 scripts/kin-sample.mjs)으로 --family 1만 · 1천을 다시 돌림');

  fs.writeFileSync(path.join(tmp, 'kin-export-check.json'), JSON.stringify(report, null, 1) + '\n');
  console.log(JSON.stringify(report, null, 1));
  if (report.문제.length) {
    console.error(`문제 ${report.문제.length}건`);
    process.exit(1);
  }
  console.log('문제 없음');
}

if (flag('--worker')) await worker(arg('--worker'));
else await main();

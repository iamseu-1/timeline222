// 계보 뼈대를 새 앱(아카이브)으로 — 확정 설계 docs/설계-10건/1-2-계승과-가문-확정.md 8-1과 그 문서 끝 '구현 이음새 기록'의 D1-E 절.
// 웹 모델의 계보 뼈대(HT.kinSkeleton — 승계표 · 세계표 · 내보내기가 함께 쓰는 하나)를 항목 기록의 새 갈래 `kin`에 **열(column) 꼴 JSON**으로 싣는다.
//   · 기록 하나 = 뼈대 하나(uid `kin:<뿌리 가문 id>` · `kin:polity:<정권 uid>`). 마디가 5만(KIN_LIMIT)을 넘으면 덩어리로 나눈다(splitKin) — 웹은 나누지 않는다.
//   · 나눈 덩어리를 모두 합치면(joinKin) 나누지 않은 한 벌과 바이트까지 같다 — 앱 lib/ui/kin/kin_record.dart가 같은 규칙을 Dart로 옮긴다(이 파일이 본보기).
//   · 엔진 스키마 · 판은 그대로다(기록은 해석 없이 entity 조회로 돌아간다).
// 웹 도우미(HT.kinSkeleton · HT.kinOf …)가 없으면(형식 3 계보가 아직 없는 웹 코드) 아무것도 싣지 않는다 — 있으면 쓰고 없으면 조용히 비켜 간다.
// 내보내기 모듈은 node: 가져오기를 쓰지 않는다(메이커의 브라우저 일꾼에서도 돈다 — B5).

/** 덩어리 상한(마디 수) — 확정 설계 8-1 · 10절 17번. */
export const KIN_LIMIT = 50000;
/** 열 꼴 기록의 판. 열 이름 · 차례를 바꾸면 올린다. */
export const KIN_VERSION = 1;

/** 마디 비트(2-4 아) — 1 구성원 · 2 이름 미상 · 4 찾지 못함 · 8 옆구리 덧선 · 16 파조 · 32 지도자 · 64 계보 전용 · 128 꼬투리 · 256 두 나라 */
export const BIT = { member: 1, unknown: 2, missing: 4, side: 8, founder: 16, leader: 32, lineage: 64, stub: 128, two: 256 };

const INT_COLUMNS = ['par', 'size', 'gen', 'bits', 'edge', 'branch', 'color'];

/** 뼈대의 마디 수. */
const sizeOf = skel => (skel ? (Number.isInteger(skel.n) ? skel.n : skel.par ? skel.par.length : 0) : 0);

/** 덧선을 [from, to, 갈래, gen] 줄들로(뼈대가 평평한 줄이든 묶음 줄이든). */
function extraTuples(src) {
  const out = [];
  if (!src) return out;
  const list = Array.from(src);
  if (list.length && Array.isArray(list[0])) {
    for (const e of list) out.push([e[0] | 0, e[1] | 0, e[2] | 0, e[3] | 0]);
  } else if (list.length && list[0] && typeof list[0] === 'object') {
    for (const e of list) out.push([e.from | 0, e.to | 0, (e.kind ?? e.edge ?? 0) | 0, (e.gen ?? 0) | 0]);
  } else {
    for (let i = 0; i + 3 < list.length; i += 4) out.push([list[i] | 0, list[i + 1] | 0, list[i + 2] | 0, list[i + 3] | 0]);
  }
  return out;
}
/** 덧선의 고정 차례 — (to, from, 갈래, gen) 오름. 한 벌 · 합친 덩어리가 같은 바이트를 내게. */
const byExtra = (a, b) => a[1] - b[1] || a[0] - b[0] || a[2] - b[2] || a[3] - b[3];
const flat = tuples => {
  const out = [];
  for (const t of tuples.sort(byExtra)) out.push(t[0], t[1], t[2], t[3]);
  return out;
};
/** 칸 표(칸 열쇠 → 번호)의 고정 차례 — 번호 · 열쇠 오름. */
function sortedCells(entries) {
  entries.sort((a, b) => a[1] - b[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const o = {};
  for (const [k, v] of entries) o[k] = v;
  return o;
}
const gensOf = gen => {
  let g = -1;
  for (const v of gen) if (v > g) g = v;
  return g + 1;
};

/**
 * 뼈대(HT.kinSkeleton의 값) → 나누지 않은 열 꼴 기록 하나(객체 — JSON.stringify로 싣는다). 열쇠 차례는 고정(이음새 기록 ②).
 * 뼈대의 정수 열은 Int32Array든 배열이든 받는다. 색은 번호 열(color · color2) + 색 표(colors — 0번은 종이빛 '')다.
 */
export function recordOf(skel, uid) {
  const n = sizeOf(skel);
  const ints = (k, fill = 0) => {
    const src = skel[k];
    const a = new Array(n);
    for (let i = 0; i < n; i++) a[i] = src && src[i] != null ? src[i] | 0 : fill;
    return a;
  };
  const strs = k => {
    const src = skel[k];
    const a = new Array(n);
    for (let i = 0; i < n; i++) a[i] = src && src[i] != null ? String(src[i]) : '';
    return a;
  };
  // 색: 뼈대가 색 표를 주면 그대로, 색 열에 글('#a0bcc5')을 담아 주면 여기서 표로 모은다.
  let colors = Array.isArray(skel.colors) ? skel.colors.map(c => String(c ?? '')) : null;
  let color;
  let color2;
  const rawColor = skel.color ? Array.from(skel.color) : [];
  const rawColor2 = skel.color2 ? Array.from(skel.color2) : [];
  if (!colors && (rawColor.some(v => typeof v === 'string') || rawColor2.some(v => typeof v === 'string'))) {
    colors = [''];
    const at = new Map([['', 0]]);
    const idx = v => {
      const s = v == null ? '' : String(v);
      if (!at.has(s)) {
        at.set(s, colors.length);
        colors.push(s);
      }
      return at.get(s);
    };
    color = Array.from({ length: n }, (_, i) => idx(rawColor[i]));
    color2 = rawColor2.length ? Array.from({ length: n }, (_, i) => idx(rawColor2[i])) : [];
  } else {
    colors = colors || [''];
    color = ints('color');
    color2 = rawColor2.length ? ints('color2') : [];
  }
  if (color2.length && !color2.some(Boolean)) color2 = []; // 두 나라 지도자가 없으면 빈 열
  const colorText = c => (typeof c === 'number' ? colors[c] || '' : c == null ? '' : String(c));
  const branches = Array.from(skel.branches || [], b => ({
    uid: String(b.uid || (b.id ? `house:${b.id}` : '')),
    name: String(b.name || ''),
    color: colorText(b.color),
    at: Number.isInteger(b.at) ? b.at : Number.isInteger(b.founder) ? b.founder : -1,
    up: Number.isInteger(b.up) ? b.up : Number.isInteger(b.parent) ? b.parent : -1,
  }));
  const cellsIn = skel.cells instanceof Map ? [...skel.cells] : Object.entries(skel.cells || {});
  const gen = ints('gen');
  return {
    v: KIN_VERSION,
    uid,
    n,
    gens: gensOf(gen),
    par: ints('par', -1),
    size: ints('size', 1),
    gen,
    bits: ints('bits'),
    edge: ints('edge'),
    branch: ints('branch'),
    color,
    color2,
    name: strs('name'),
    sub: strs('sub'),
    key: strs('key'),
    extra: flat(extraTuples(skel.extra)),
    colors,
    branches,
    cells: sortedCells(cellsIn.map(([k, v]) => [String(k), v | 0])),
    stubs: {},
    warnings: Array.from(skel.warnings || [], w => (typeof w === 'string' ? w : String((w && (w.msg || w.text || w.message)) || w))),
  };
}

/** 덩어리 uid — 꼬투리 마디가 파조면 그 파의 `kin:<파 가문 id>`, 아니면 `<뿌리 뼈대 uid>#<안정 열쇠>`(이음새 기록 ③). */
function chunkUid(rec, s) {
  if (rec.bits[s] & BIT.founder) {
    const b = rec.branches.find(x => x.at === s && x.uid);
    if (b) return `kin:${b.uid.replace(/^house:/, '')}`;
  }
  return `${rec.uid}#${rec.key[s]}`;
}

/**
 * 나누지 않은 기록 → 덩어리 기록들(뿌리 기록이 첫째). 상한을 넘지 않으면 [rec] 그대로.
 * 뗄 마디: 상한을 넘는 덩어리마다, 그 덩어리 뿌리가 아닌 마디 가운데 그 덩어리 안 하위 수가 2 이상 · 덩어리 마디 수 미만인 파조(비트 16) 중 가장 큰 것(같으면 앞 차례),
 * 파조가 없으면 아무 마디 중 가장 큰 것. 뗀 마디는 남은 쪽에 꼬투리(접힌 카드 · 비트 128 · size 1)로 남고, 떼어 낸 덩어리는 그 마디를 번호 0으로 시작한다.
 */
export function splitKin(rec, limit = KIN_LIMIT) {
  const n = rec.n;
  if (n <= limit) return [rec];
  const { size, par, bits } = rec;
  const cut = new Set(); // 뗀 마디(한 벌 번호)
  /** 덩어리(뿌리 r — 뿌리 기록은 −1)의 마디들(앞 차례 · 꼬투리 포함) */
  const nodesOf = r => {
    const out = [];
    const end = r < 0 ? n : r + size[r];
    for (let i = r < 0 ? 0 : r; i < end; ) {
      out.push(i);
      i += cut.has(i) && i !== r ? size[i] : 1;
    }
    return out;
  };
  const warnings = [];
  for (let guard = 0; guard < n; guard++) {
    let moved = false;
    for (const r of [-1, ...[...cut].sort((a, b) => a - b)]) {
      for (;;) {
        const list = nodesOf(r);
        if (list.length <= limit) break;
        // 덩어리 안 하위 수(꼬투리는 1)를 뒤에서부터 모은다
        const sub = new Map();
        for (let k = list.length - 1; k >= 0; k--) {
          const i = list[k];
          sub.set(i, (sub.get(i) || 0) + 1);
          const p = par[i];
          if (i !== r && p >= 0) sub.set(p, (sub.get(p) || 0) + sub.get(i)); // 부모는 앞 차례라 뒤에서 훑으면 자식이 먼저 끝난다
        }
        let best = -1;
        let bestKey = null;
        for (const i of list) {
          if (i === r || cut.has(i)) continue;
          const s = sub.get(i);
          if (s < 2 || s >= list.length) continue; // 덩어리 전체를 품는 마디(숲의 유일한 뿌리 등)는 떼어도 줄지 않는다
          const key = [(bits[i] & BIT.founder) ? 1 : 0, s];
          if (!bestKey || key[0] > bestKey[0] || (key[0] === bestKey[0] && key[1] > bestKey[1])) {
            best = i;
            bestKey = key;
          }
        }
        if (best < 0) {
          warnings.push(`덩어리 ${r < 0 ? rec.uid : chunkUid(rec, r)}의 마디 ${list.length}개가 상한 ${limit}을 넘지만 뗄 하위 나무가 없어 나누지 않았습니다.`);
          break;
        }
        cut.add(best);
        moved = true;
      }
    }
    if (!moved) break;
  }
  if (!cut.size) {
    const one = Object.assign({}, rec, { warnings: rec.warnings.concat(warnings) });
    return [one];
  }
  // 마디마다 제 집(꼬투리가 아닌 자리로 든 덩어리의 뿌리 — 뿌리 기록은 −1)
  const home = new Int32Array(n).fill(-1);
  for (let i = 0; i < n; i++) home[i] = cut.has(i) ? i : par[i] >= 0 ? home[par[i]] : -1;
  const roots = [-1, ...[...cut].sort((a, b) => a - b)];
  const uidOf = r => (r < 0 ? rec.uid : chunkUid(rec, r));
  const lists = new Map(roots.map(r => [r, nodesOf(r)]));
  const local = new Map(roots.map(r => [r, new Map(lists.get(r).map((i, k) => [i, k]))]));
  const tuples = new Map(roots.map(r => [r, []]));
  const far = new Map(roots.map(r => [r, []]));
  const ex = rec.extra;
  for (let k = 0; k + 3 < ex.length; k += 4) {
    const [from, to, kind, gen] = [ex[k], ex[k + 1], ex[k + 2], ex[k + 3]];
    const hTo = home[to];
    if (home[from] === hTo) tuples.get(hTo).push([local.get(hTo).get(from), local.get(hTo).get(to), kind, gen]);
    else far.get(hTo).push({ from: rec.key[from], fromAt: from, to: local.get(hTo).get(to), kind, gen });
  }
  const cellsBy = new Map(roots.map(r => [r, []]));
  for (const [key, i] of Object.entries(rec.cells)) cellsBy.get(home[i]).push([key, local.get(home[i]).get(i)]);
  const out = [];
  for (const r of roots) {
    const list = lists.get(r);
    const map = local.get(r);
    const m = list.length;
    const pick = col => list.map(i => col[i]);
    const parL = list.map(i => (i === r || par[i] < 0 ? -1 : map.get(par[i])));
    const sizeL = new Array(m).fill(1);
    for (let k = m - 1; k > 0; k--) if (parL[k] >= 0) sizeL[parL[k]] += sizeL[k];
    const bitsL = list.map(i => (cut.has(i) && i !== r ? bits[i] | BIT.stub : bits[i]));
    const stubs = {};
    list.forEach((i, k) => {
      if (cut.has(i) && i !== r) stubs[k] = { key: uidOf(i), n: size[i] };
    });
    const gen = pick(rec.gen);
    const o = {
      v: rec.v,
      uid: uidOf(r),
      n: m,
      gens: gensOf(gen),
      par: parL,
      size: sizeL,
      gen,
      bits: bitsL,
      edge: pick(rec.edge),
      branch: pick(rec.branch),
      color: pick(rec.color),
      color2: rec.color2.length && list.some(i => rec.color2[i]) ? pick(rec.color2) : [],
      name: pick(rec.name),
      sub: pick(rec.sub),
      key: pick(rec.key),
      extra: flat(tuples.get(r)),
      colors: rec.colors,
      branches: rec.branches,
      cells: sortedCells(cellsBy.get(r)),
      stubs,
      warnings: r < 0 ? rec.warnings.concat(warnings) : [],
    };
    if (r >= 0) {
      const up = par[r] >= 0 ? home[par[r]] : -1; // 꼬투리를 가진 덩어리
      o.root = { uid: rec.uid, at: r, up: uidOf(up), upAt: local.get(up).get(r) };
      const fr = far.get(r);
      if (fr.length) o.extraFar = fr.sort((a, b) => a.to - b.to || a.fromAt - b.fromAt || a.kind - b.kind || a.gen - b.gen);
    }
    out.push(o);
  }
  // 뿌리 덩어리에 든 '다른 덩어리 부모'의 덧선은 없다(자식 쪽에 싣는다) — far.get(-1)은 자식이 뿌리 덩어리에 있고 부모가 덩어리에 있는 선
  const rootFar = far.get(-1);
  if (rootFar.length) out[0].extraFar = rootFar.sort((a, b) => a.to - b.to || a.fromAt - b.fromAt || a.kind - b.kind || a.gen - b.gen);
  return out;
}

/**
 * 덩어리 기록들 → 하나로 합친 기록(앱 kin_record.dart의 본보기). records의 첫째가 뿌리 기록(`root` 없음)이다.
 * 받지 않은 덩어리의 꼬투리는 꼬투리(비트 128 · size 1 · stubs)로 남고, 두 끝이 다 들어오지 않은 덧선은 extraFar로 남는다.
 * 모든 덩어리를 받으면 나누지 않은 한 벌과 바이트까지 같다.
 */
export function joinKin(records) {
  const main = records.find(r => !r.root) || records[0];
  const byUid = new Map(records.map(r => [r.uid, r]));
  const seq = []; // [기록, 그 안 번호]
  const walk = rec => {
    for (let k = 0; k < rec.n; k++) {
      const st = rec.stubs[k];
      const child = st ? byUid.get(st.key) : null;
      if (child && child !== rec) walk(child);
      else seq.push([rec, k]);
    }
  };
  walk(main);
  const n = seq.length;
  const at = new Map(); // 기록 uid → (그 안 번호 → 합친 번호)
  seq.forEach(([rec, k], i) => {
    if (!at.has(rec.uid)) at.set(rec.uid, new Map());
    at.get(rec.uid).set(k, i);
  });
  const col = name => seq.map(([rec, k]) => rec[name][k]);
  const par = seq.map(([rec, k]) => {
    if (rec.par[k] >= 0) return at.get(rec.uid).get(rec.par[k]);
    if (rec.root) {
      // 덩어리의 뿌리 — 꼬투리의 부모(꼬투리를 가진 기록 안)
      const up = byUid.get(rec.root.up);
      const p = up ? up.par[rec.root.upAt] : -1;
      return p >= 0 ? at.get(up.uid).get(p) : -1;
    }
    return -1;
  });
  const size = new Array(n).fill(1);
  for (let i = n - 1; i > 0; i--) if (par[i] >= 0) size[par[i]] += size[i];
  const keyAt = new Map(seq.map(([rec, k], i) => [rec.key[k], i]));
  const tuples = [];
  const far = [];
  for (const rec of records) {
    if (!at.has(rec.uid)) continue;
    const map = at.get(rec.uid);
    for (let k = 0; k + 3 < rec.extra.length; k += 4) tuples.push([map.get(rec.extra[k]), map.get(rec.extra[k + 1]), rec.extra[k + 2], rec.extra[k + 3]]);
    for (const f of rec.extraFar || []) {
      const from = keyAt.get(f.from);
      if (from != null) tuples.push([from, map.get(f.to), f.kind, f.gen]);
      else far.push({ from: f.from, fromAt: f.fromAt, to: map.get(f.to), kind: f.kind, gen: f.gen });
    }
  }
  const cells = [];
  const stubs = {};
  for (const rec of records) {
    if (!at.has(rec.uid)) continue;
    const map = at.get(rec.uid);
    for (const [key, k] of Object.entries(rec.cells)) cells.push([key, map.get(k)]);
    for (const [k, st] of Object.entries(rec.stubs)) if (!byUid.has(st.key) && map.has(Number(k))) stubs[map.get(Number(k))] = st;
  }
  const gen = col('gen');
  const color2 = seq.map(([rec, k]) => (rec.color2.length ? rec.color2[k] : 0));
  const o = {
    v: main.v,
    uid: main.uid,
    n,
    gens: gensOf(gen),
    par,
    size,
    gen,
    bits: seq.map(([rec, k]) => (rec.stubs[k] && byUid.has(rec.stubs[k].key) ? rec.bits[k] & ~BIT.stub : rec.bits[k])),
    edge: col('edge'),
    branch: col('branch'),
    color: col('color'),
    color2: color2.some(Boolean) ? color2 : [],
    name: col('name'),
    sub: col('sub'),
    key: col('key'),
    extra: flat(tuples),
    colors: main.colors,
    branches: main.branches,
    cells: sortedCells(cells),
    stubs,
    warnings: main.warnings.filter(w => !/^덩어리 /.test(w)),
  };
  if (far.length) o.extraFar = far.sort((a, b) => a.to - b.to || a.fromAt - b.fromAt || a.kind - b.kind || a.gen - b.gen);
  return o;
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  모델 → 뼈대 기록 · 사람 자리 · 가문 x_kin (entities.mjs가 부른다)
 * ════════════════════════════════════════════════════════════════════════════════════════════ */

/** 이 뼈대의 마디 i가 든 기록(덩어리) uid — 나누지 않았으면 뿌리 uid. */
function homeOf(parts, i) {
  // parts: [{ uid, at(한 벌 번호 — 뿌리 기록은 −1), end }] 깊은 것이 뒤
  let best = parts[0];
  for (const p of parts) if (p.at >= 0 && i >= p.at && i < p.end && (best.at < 0 || p.at >= best.at)) best = p;
  return best.uid;
}

/**
 * 모델의 모든 뼈대를 지어 기록으로 — 돌려주는 값:
 *   records: [{ uid, body(기록 객체), rootUid, houseId|polityUid }] (덩어리 포함 · 뿌리 기록이 먼저)
 *   personAt: Map(사람 자리 열쇠 'f:<uid>' … → { key, at, chunk? }) — 구성원으로 든 자리가 먼저(없으면 처음 든 자리)
 *   cellAt: Map('<정권 uid>|leader:3' → [뼈대 uid, 번호])
 *   houseKin: Map(가문 id → x_kin)
 *   notes: 집계
 * 웹 도우미(HT.kinSkeleton)가 없으면 null.
 */
export function kinCollect(model, HT, { limit = KIN_LIMIT } = {}) {
  if (typeof HT.kinSkeleton !== 'function' || !model) return null;
  const houses = model.houses || [];
  const keys = [];
  const seenKey = new Set();
  const want = (key, owner) => {
    if (!key || seenKey.has(key)) return;
    seenKey.add(key);
    keys.push([key, owner]);
  };
  // 뿌리 가문(본가 길의 맨 위)마다 하나
  for (const h of houses) {
    const top = h.path && h.path.length ? h.path[0] : h.id;
    if (top === h.id) want(`kin:${h.id}`, { houseId: h.id });
  }
  // 가문이 없는 지도자가 있는 정권 — HT.kinOf가 'kin:polity:…'를 주는 것
  if (typeof HT.kinOf === 'function')
    for (const p of model.periods || []) {
      if (p.kind !== 'period') continue;
      (p.leaders || []).forEach((c, i) => {
        const k = HT.kinOf(model, p, i);
        if (k && typeof k.key === 'string' && k.key.startsWith('kin:polity:')) want(k.key, { polityUid: k.key.slice('kin:polity:'.length) }); // 귀속은 열쇠의 정권(두 나라 지도자는 첫 칸의 나라)
      });
    }
  const records = [];
  const personAt = new Map();
  const cellAt = new Map();
  const houseKin = new Map();
  const notes = { 뼈대: 0, 덩어리: 0, 마디: 0, 가장큰뼈대: 0 };
  const chunkSpans = new Map(); // 뿌리 뼈대 uid → 덩어리 구간들
  for (const [key, owner] of keys) {
    const skel = HT.kinSkeleton(model, key);
    const n = sizeOf(skel);
    if (!n) continue;
    const rec = recordOf(skel, key);
    const parts = splitKin(rec, limit);
    notes.뼈대++;
    notes.덩어리 += parts.length - 1;
    notes.마디 += n;
    notes.가장큰뼈대 = Math.max(notes.가장큰뼈대, n);
    const spans = parts.map(p => (p.root ? { uid: p.uid, at: p.root.at, end: p.root.at + rec.size[p.root.at] } : { uid: p.uid, at: -1, end: n }));
    const chunkOf = i => {
      const u = homeOf(spans, i);
      return u === key ? null : u;
    };
    chunkSpans.set(key, spans);
    for (const p of parts) records.push(Object.assign({ uid: p.uid, body: p, rootUid: key }, owner));
    // 사람 자리 → 뼈대 자리(구성원으로 든 곳이 먼저)
    for (let i = 0; i < n; i++) {
      const k = rec.key[i];
      const member = !!(rec.bits[i] & BIT.member);
      const cur = personAt.get(k);
      if (cur && (cur.member || !member)) continue;
      const o = { key, at: i, member };
      const ch = chunkOf(i);
      if (ch) o.chunk = ch;
      personAt.set(k, o);
    }
    for (const [cell, i] of Object.entries(rec.cells)) if (!cellAt.has(cell)) cellAt.set(cell, [key, i]);
    // 가문 x_kin — 뿌리 가문과 그 아래 파마다
    const B = rec.branches;
    const under = b => {
      const out = [];
      B.forEach((x, j) => {
        for (let u = j, guard = 0; u >= 0 && guard <= B.length; u = B[u].up, guard++)
          if (u === b) {
            out.push(j);
            break;
          }
      });
      return out;
    };
    const rangeOf = b => {
      // 파의 뿌리 번호(파조 · 못 풀면 그 파 마디를 모두 품는 가장 작은 하위 나무) · 사람 수 · 세대 줄 수
      const set = new Set(under(b));
      let at = B[b].at;
      const isRoot = B[b].up < 0 && owner.houseId && B[b].uid === `house:${owner.houseId}`;
      if (isRoot) at = -1;
      else if (!(at >= 0)) {
        // 가장 작은 하위 나무 — 공통 조상
        let lca = -2;
        for (let i = 0; i < n; i++) {
          if (!set.has(rec.branch[i]) || !(rec.bits[i] & BIT.member)) continue;
          if (lca === -2) {
            lca = i;
            continue;
          }
          let a = lca;
          while (a >= 0 && !(i >= a && i < a + rec.size[a])) a = rec.par[a];
          lca = a;
          if (lca < 0) break;
        }
        at = lca >= 0 ? lca : -1;
      }
      let cnt = 0;
      let lo = Infinity;
      let hi = -Infinity;
      const take = i => {
        cnt++;
        if (rec.gen[i] < lo) lo = rec.gen[i];
        if (rec.gen[i] > hi) hi = rec.gen[i];
      };
      if (isRoot) for (let i = 0; i < n; i++) take(i);
      else if (at >= 0) for (let i = at; i < at + rec.size[at]; i++) take(i);
      else for (let i = 0; i < n; i++) if (set.has(rec.branch[i])) take(i);
      return { at, n: cnt, gens: cnt ? hi - lo + 1 : 0, isRoot, set };
    };
    B.forEach((b, j) => {
      const id = b.uid.replace(/^house:/, '');
      if (!id || houseKin.has(id)) return;
      const r = rangeOf(j);
      if (!r.n && !r.isRoot) return;
      const o = { key };
      if (r.at >= 0) {
        o.at = r.at;
        const ch = chunkOf(r.at);
        if (ch) o.chunk = ch;
      }
      o.n = r.n;
      o.gens = r.gens;
      o.branches = under(j)
        .filter(q => q !== j)
        .map(q => {
          const rq = rangeOf(q);
          return { uid: B[q].uid, name: B[q].name, color: B[q].color, n: rq.n };
        });
      houseKin.set(id, o);
    });
    if (owner.houseId && !houseKin.has(owner.houseId)) {
      // 파 표에 뿌리 가문이 없는 뼈대(웹이 그렇게 지었다면) — 뿌리 가문은 한 벌 전체
      houseKin.set(owner.houseId, { key, n, gens: rec.gens, branches: B.map(b => ({ uid: b.uid, name: b.name, color: b.color, n: rangeOf(B.indexOf(b)).n })) });
    }
  }
  /** 한 벌 번호 → { chunk } (나눈 덩어리 안이면) · 빈 객체 */
  const chunkAt = (key, i) => {
    const sp = chunkSpans.get(key);
    if (!sp) return {};
    const u = homeOf(sp, i);
    return u === key ? {} : { chunk: u };
  };
  return { records, personAt, cellAt, houseKin, notes, chunkAt };
}

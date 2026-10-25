/* 역사 연표 — 승계표 · 세계표 보기 (연표 · 메이커 둘 다)
 *
 * 나라 상세의 승계표(지도자 카드 · 접고 펼치기 · 보이는 줄만 그리기)와 세계표(가문 · 세대 · 선)를 그립니다.
 * 기준: docs/설계-10건/의 D1 확정 설계(1-2 … 가문-확정.md) 3절 · 4절 · 5절. 창을 여는 길 · 창의 머리 · 바닥 글은 js/viewer.js가 맡고, 이 파일은 목록 · 나무만 그립니다.
 *
 * 자료는 모두 js/core.js의 계약 도우미에서 옵니다(이 파일은 자리를 셈하지 않고 그리기만):
 *   HT.kinSkeleton(model, key) 계보 뼈대(앞 차례 정수 배열 — par · size · gen · bits · edge · branch · color · name · sub · key · extra · branches · cells)
 *   HT.kinLayout(skel, open) 정수 칸 셈 { x, w, rows, width } · HT.kinDefaultOpen(skel) 기본 펼침 Uint8Array
 *   HT.kinOf(model, 정권, i) 지도자 칸의 { key, at } · HT.successionRows(model, 정권, open) 승계표 줄 · HT.accessionLine(acc) 선 갈래 0~5 · HT.accessionSeam(model, ruler) 이음매 글
 *   도우미가 없으면(옛 core.js) HT.kinView.ready()가 거짓이라 뷰어가 단추를 두지 않습니다 — 옛 화면은 그대로입니다.
 * 새 앱(아카이브)의 lib/ui/kin/*.dart가 같은 뼈대 · 같은 정수 셈 · 같은 줄 규칙으로 같은 모습을 그립니다(1배 치수는 아래 상수 그대로).
 *
 * 그리기는 보이는 것만: 승계표는 줄 높이 누적합(Int32Array) + 이분 탐색으로 보이는 줄 + 위아래 8줄, 세계표는 세대마다 보이는 번호(rows[g])를 x로 이분 탐색.
 * 요소는 열쇠(안정 열쇠)로 다시 쓰고, 세계표의 선은 갈래마다 SVG path 하나에 모아 그립니다 — 창 안 요소는 400개를 넘지 않습니다.
 * 움직임은 토큰만(HT.motion.T · C — 동작 줄이기면 CSS가 길이를 줄임): 누른 줄 · 카드는 화면에서 0px, 나머지는 옛 자리 → 새 자리(--t-move · 되튐 없는 스프링),
 * 새로 나타나는 것은 제자리에서 --t-in, 접혀 사라지는 것은 --t-out.
 */
(function () {
  'use strict';
  const HT = window.HT;
  if (!HT) return;
  const esc = HT.escapeHtml;
  const MT = () => (HT.motion && HT.motion.T) || { micro: 120, out: 160, in: 200, move: 360 };
  const MC = () => (HT.motion && HT.motion.C) || { ease: 'cubic-bezier(.25, .8, .25, 1)', spring: 'cubic-bezier(.32, .72, 0, 1)' };
  const now = () => (HT.motion && HT.motion.now ? HT.motion.now() : performance.now());

  /* ---------- 뼈대 비트 · 선 갈래 (계약 2-4 아 · 3-3) ---------- */
  const B_MEMBER = 1;
  const B_UNKNOWN = 2;
  const B_MISSING = 4;
  const B_SIDE = 8;
  const B_FOUNDER = 16;
  const B_LEADER = 32;
  const B_STUB = 128;
  const B_TWO = 256;
  /** HT.accessionLine의 0~5 → 이음매 무늬 이름 (css/viewer.css의 data-line) */
  const LINE_NAMES = ['none', 'cut', 'unk', 'two', 'res', 'solid'];
  /** 승계표 줄(HT.successionRows)의 갈래 — 셋씩 [갈래, 번호, 들여쓰기] */
  const ROW_LEADER = 0;
  const ROW_PERSON = 1;
  const ROW_SKIP = 2;

  /* ---------- 1배 치수 (새 앱과 같은 수) ---------- */
  const S_CARD = 34; // 승계표 지도자 카드
  const S_SEAM = 22; // 이음매
  const S_ROW = 28; // 사람 줄 · 건너뛰기 줄
  const S_INDENT = 14; // 한 대 들여쓰기
  const S_OVERSCAN = 8; // 보이는 줄 위아래로 더 그리는 줄 수
  const F_U = 35; // 세계표 단위 u
  const F_CW = 124; // 카드 폭
  const F_CH = 42; // 카드 높이
  const F_GH = 82; // 세대 줄 높이 (카드 42 + 사이 40)
  const F_HALF = 62; // 카드 왼쪽 = x · u − 62
  const F_PADX = 30; // 세대 번호 칸
  const F_PADY = 22; // '세대' 머리 줄
  const F_FAR = 48; // 덧선을 선으로 그리는 두 끝의 거리(u) — 12칸
  const F_CAP = 200; // 그리는 카드 수 상한
  const F_RING = 14; // 이름 미상 원의 지름 (보통 단계 — 글자 없이 원 하나 · 건의 8의 4-다)
  /* 보기 단계 표 (건의 8의 4-가 — 감독 선택 2026-10-13, 새 앱 KinScale과 같은 수): 한 줄 = 한 단계 — 뒷날 '좁게'를 줄 하나로 더할 수 있게.
     자리 셈(정수 칸 x · 세대)은 그대로 두고 px만 바뀝니다: 사람 왼쪽 = x · u − 폭/2, 선이 꺾이는 높이 = 사람 위 + 높이 + (세대 줄 − 높이)/2.
     u 단위 · w×h 사람(카드 · 점) · row 세대 줄 · r 둥근 정도 · dots 점으로 그림(이름 · 곁글 · 손잡이 · 알약 · 파 이름표 · 꼬리표 없이 — 이름은 올리면 풍선) */
  const F_SCALES = [
    { id: 'normal', name: '보통', u: F_U, w: F_CW, h: F_CH, row: F_GH, r: 11, dots: false },
    { id: 'dot', name: '점', u: 6, w: 12, h: 12, row: 30, r: 6, dots: true },
  ];

  const ready = () => ['kinSkeleton', 'kinLayout', 'kinDefaultOpen'].every(k => typeof HT[k] === 'function');
  const succReady = () => ready() && ['successionRows', 'kinOf', 'accessionLine', 'accessionSeam', 'lineageOf'].every(k => typeof HT[k] === 'function');
  const yr = t => {
    if (t == null || !isFinite(t)) return '';
    const y = HT.yearOf ? HT.yearOf(t) : Math.floor(t + 1e-9);
    return y < 0 ? `기원전 ${-y}` : String(y);
  };
  const reduced = () => MT().move <= 0;

  /* ---------- 뼈대 읽기 — 모델마다 캐시 (메이커가 모델을 다시 지으면 함께 버림) ---------- */
  const skelCache = new WeakMap();
  /** 계약 뼈대 → 그리기에 쓰는 꼴(배열은 그대로 · 색 번호는 색 글로) */
  function wrap(raw, key) {
    const n = raw.n != null ? raw.n : raw.par.length;
    const keys = Array.isArray(raw.key) ? raw.key : raw.keys || [];
    const colors = Array.isArray(raw.colors) ? raw.colors : null;
    const css = v => (colors ? colors[v] || '' : typeof v === 'string' ? v : '');
    let gens = raw.gens;
    if (gens == null) {
      gens = 0;
      for (let i = 0; i < n; i++) if (raw.gen[i] + 1 > gens) gens = raw.gen[i] + 1;
    }
    let index = null;
    return {
      raw,
      id: raw.uid || (typeof raw.key === 'string' ? raw.key : key),
      n,
      gens,
      keys,
      par: raw.par,
      size: raw.size,
      gen: raw.gen,
      bits: raw.bits,
      edge: raw.edge || [],
      branch: raw.branch || [],
      names: raw.name || [],
      subs: raw.sub || [],
      extra: raw.extra || [],
      branches: raw.branches || [],
      cells: raw.cells || {},
      stubs: raw.stubs || {},
      color: i => css(raw.color ? raw.color[i] : 0),
      color2: i => (raw.color2 && raw.color2.length ? css(raw.color2[i]) : ''),
      indexOf(k) {
        if (!index) {
          index = new Map();
          keys.forEach((q, i) => index.set(q, i));
        }
        return index.has(k) ? index.get(k) : -1;
      },
    };
  }
  /** 뼈대 열쇠(kin:<뿌리 가문 id> · kin:polity:<정권 uid>) → 그리기 꼴 (없으면 null) */
  function skeleton(model, key) {
    if (!model || !key || !ready()) return null;
    let m = skelCache.get(model);
    if (!m) skelCache.set(model, (m = new Map()));
    if (m.has(key)) return m.get(key);
    let raw = null;
    try {
      raw = HT.kinSkeleton(model, key);
    } catch (err) {
      console.warn('계보 뼈대를 짓지 못했습니다', key, err);
    }
    const s = raw && raw.par && raw.size ? wrap(raw, key) : null;
    m.set(key, s);
    return s;
  }
  /**
   * 뼈대를 나눠 지어 둠(4-6 · 6-1 — 50ms를 넘을 큰 뼈대는 몇 ms마다 양보하며 짓고, 그동안 '짓고 있습니다'): 열쇠가 모두 지어져 있으면 null,
   * 아니면 다 지으면 풀리는 Promise. 웹 도우미 HT.kinSkeletonAsync(D1-W1 — HT.kinSkeleton과 같은 뼈대 · 같은 캐시)가 없으면 null(지금처럼 동기로 지음).
   * 이미 지어진 열쇠면 HT.kinSkeletonAsync가 곧바로 풀리므로 같은 장면 안에서 끝납니다(화면에 '짓고 있습니다'가 남지 않음).
   */
  const warm = new WeakMap(); // 모델 → 나눠 지어 둔 열쇠
  function prepare(model, keys) {
    if (!model || typeof HT.kinSkeletonAsync !== 'function') return null;
    let done = warm.get(model);
    if (!done) warm.set(model, (done = new Set()));
    const cached = skelCache.get(model);
    const need = [...new Set(keys || [])].filter(k => typeof k === 'string' && k && !done.has(k) && !(cached && cached.has(k)));
    if (!need.length) return null;
    return Promise.all(
      need.map(k =>
        HT.kinSkeletonAsync(model, k).catch(err => {
          console.warn('계보 뼈대를 짓지 못했습니다', k, err);
          return null;
        })
      )
    ).then(() => {
      for (const k of need) done.add(k);
    });
  }
  /** 승계표가 쓸 뼈대 열쇠 — 지도자 칸 사람의 뼈대(사람 자리의 kinKey — HT.kinOf가 짓는 것과 같은 열쇠) */
  function succKeys(model, P) {
    const out = [];
    if (!P || typeof HT.personOf !== 'function') return out;
    (P.leaders || []).forEach((c, i) => {
      let n = null;
      try {
        n = HT.personOf(model, P, `leader:${i}`);
      } catch (err) {
        n = null;
      }
      if (n && n.kinKey) out.push(n.kinKey);
    });
    return out;
  }
  /** 승계표 창을 열기 전에: 뼈대가 다 지어져 있으면 null, 아니면 나눠 짓는 Promise(viewer가 그동안 '승계표를 짓고 있습니다'를 띄움) */
  const succPrepare = (model, P) => prepare(model, succKeys(model, P));
  /** i의 자식들(앞 차례 — 자식 차례) */
  function* kidsOf(S, i) {
    const end = i + S.size[i];
    for (let j = i + 1; j < end; j += S.size[j]) yield j;
  }
  /** 파(가문 uid 'house:<id>')의 뿌리 번호 — 파조, 못 풀면 그 파와 아래 파 마디를 모두 품는 가장 작은 하위 나무의 뿌리 (없으면 −1) */
  function branchRoot(S, houseUid) {
    const b = S.branches.findIndex(x => x && x.uid === houseUid);
    if (b < 0) return -1;
    if (S.branches[b].at >= 0) return S.branches[b].at;
    const under = new Set([b]);
    for (let grew = true; grew; ) {
      grew = false;
      S.branches.forEach((x, k) => {
        if (!under.has(k) && x && under.has(x.up)) {
          under.add(k);
          grew = true;
        }
      });
    }
    let lo = -1;
    let hi = -1;
    for (let i = 0; i < S.n; i++)
      if (under.has(S.branch[i])) {
        if (lo < 0) lo = i;
        hi = i;
      }
    if (lo < 0) return -1;
    let a = lo;
    while (a >= 0 && a + S.size[a] <= hi) a = S.par[a];
    return a;
  }

  /* ---------- 접힘 기억 (보기 설정 — 파일이 아님) ----------
     기본에서 달라진 것만 안정 열쇠로: { b: 기본 갈래, x: [바꾼 열쇠 …] } — 2,000개를 넘으면 오래된 것부터 버립니다 */
  const MEMO_MAX = 2000;
  function memo(store, id) {
    let v = null;
    try {
      v = store && store.get ? store.get(id) : null;
    } catch (err) {
      v = null;
    }
    const st = v && typeof v === 'object' && Array.isArray(v.x) ? { b: String(v.b || ''), x: v.x.filter(k => typeof k === 'string'), top: typeof v.top === 'string' ? v.top : '' } : { b: '', x: [], top: '' };
    const set = new Set(st.x);
    const save = () => {
      try {
        if (store && store.set) store.set(id, { b: st.b, x: [...set], top: st.top });
      } catch (err) {
        /* 기억은 편의 — 못 적어도 화면은 그대로 */
      }
    };
    return {
      base: () => st.b,
      has: k => set.has(k),
      top: () => st.top,
      setTop(k) {
        st.top = k || '';
        save();
      },
      reset(b) {
        st.b = b;
        set.clear();
        save();
      },
      flip(k) {
        if (set.has(k)) set.delete(k);
        else {
          set.add(k);
          while (set.size > MEMO_MAX) set.delete(set.values().next().value);
        }
        save();
      },
      keys: () => [...set],
    };
  }

  /* ---------- 이분 탐색 ---------- */
  /** 오름차순 ys에서 ys[i] <= v < ys[i + 1]인 i (ys 길이 = 줄 수 + 1) */
  function rowAt(ys, count, v) {
    let lo = 0;
    let hi = count - 1;
    if (hi < 0) return 0;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (ys[mid] <= v) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  }

  /* ---------- 범례 ---------- */
  function legendHTML(kind) {
    const it = (cls, text) => `<span><i class="kv-lg ${cls}" aria-hidden="true"></i>${esc(text)}</span>`;
    if (kind === 'succession')
      return `<div class="kv-legend" aria-label="선 모양">${[it('is-solid', '세습 · 추대'), it('is-two', '선양'), it('is-cut', '찬탈 · 정변'), it('is-unk', '관계 · 방식 미상'), it('is-res', '복위(같은 사람)')].join('')}</div>`;
    return `<div class="kv-legend" aria-label="그림 보기">${[it('is-ruler', '지도자(나라 색 · 대수)'), it('is-paper', '지도자 아님'), it('is-line', '부모 → 자식'), it('is-adopt', '양자(양부)'), it('is-skip', '여러 대 건너뜀(n대손)'), it('is-ring', '이름 미상')].join('')}</div>`;
  }

  /* ======================================================================
     승계표 — 상세 창 몸통 안의 세로 목록 (3절)
     ====================================================================== */
  /**
   * o = { host(목록을 붙일 빈 요소), scroller(밀어 보는 상자 — .detail-body), model, polity, store({ get, set } — 접힘 기억),
   *       focus(데려갈 지도자 번호), expand(그 카드를 펼친 채), onOpen(action), onMenu(action, x, y) }
   * action = { type: 'cell', polity, i } · { type: 'person', key, skel, at } · { type: 'house', id }
   * 돌려주는 것: { setLevel(l), expandAll(), collapseAll(), goLeader(m), focus(), destroy(), stats() }
   */
  function succession(o) {
    const { host, scroller, model, polity: P } = o;
    const lin = HT.lineageOf(model, P) || { rulers: [] };
    const rulers = lin.rulers || [];
    const K = rulers.length;
    const kinAt = rulers.map((r, m) => {
      try {
        const k = HT.kinOf(model, P, m);
        return k && k.key != null && k.at >= 0 ? k : null;
      } catch (err) {
        return null;
      }
    });
    const sk = new Map();
    for (const k of kinAt)
      if (k && !sk.has(k.key)) {
        const s = skeleton(model, k.key);
        if (s && k.at < s.n) sk.set(k.key, s);
      }
    for (let m = 0; m < K; m++) if (kinAt[m] && !sk.has(kinAt[m].key)) kinAt[m] = null;
    /* 뼈대마다 이 나라 지도자의 자리 → 지도자 번호(처음 오른 칸) */
    const leadAt = new Map();
    kinAt.forEach((k, m) => {
      if (!k) return;
      const mm = leadAt.get(k.key) || leadAt.set(k.key, new Map()).get(k.key);
      if (!mm.has(k.at)) mm.set(k.at, m);
    });
    /** 같은 사람이 앞서 오른 칸(복위 — 처음 카드에서만 펼침) */
    const firstOf = rulers.map((r, m) => {
      if (!r.person) return m;
      for (let j = 0; j < m; j++) if (rulers[j].person === r.person) return j;
      return m;
    });
    /* 펼침(HT.successionRows의 open 꼴): Map(뼈대 uid → 마디마다 1 · 0) — 빠진 것은 접힘. 지도자 카드의 펼침 = 그 사람의 마디(kinOf의 at) */
    const opens = new Map();
    for (const [key, s] of sk) opens.set(key, new Uint8Array(s.n));
    const nodeOpen = key => opens.get(key);
    const cardOpen = m => (kinAt[m] ? nodeOpen(kinAt[m].key)[kinAt[m].at] : 0);
    const mem = memo(o.store, P.uid);
    const ordText = m => (rulers[m] && rulers[m].ordinal != null ? `${rulers[m].ordinal}대` : rulers[m] ? rulers[m].name : '');

    /* 수준: L 지도자만 · C 자녀까지 · B 파 이름까지 · A 모두 (HT.successionOpen의 'leaders' · 'children' · 'branches' · 'all') */
    const LEVELS = { L: 'leaders', C: 'children', B: 'branches', A: 'all' };
    function applyLevel(lv) {
      for (const op of opens.values()) op.fill(0);
      if (lv === 'L') return;
      let preset = null;
      try {
        preset = typeof HT.successionOpen === 'function' ? HT.successionOpen(model, P, LEVELS[lv]) : null;
      } catch (err) {
        preset = null;
      }
      for (const [key, op] of opens) {
        const src = preset ? (preset instanceof Map ? preset.get(key) : preset[key]) : null;
        if (src) for (let i = 0; i < op.length; i++) op[i] = src[i] ? 1 : 0;
        else if (!preset) {
          const s = sk.get(key);
          for (let i = 0; i < s.n; i++) op[i] = lv === 'A' || (lv === 'B' && !(s.bits[i] & B_FOUNDER)) ? 1 : 0;
          for (const at of leadAt.get(key).keys()) op[at] = 1;
        }
      }
    }
    function restore() {
      applyLevel(LEVELS[mem.base()] ? mem.base() : 'L');
      for (const k of mem.keys()) {
        const t = k.indexOf('\t');
        const key = k.slice(0, t);
        const s = sk.get(key);
        const i = s ? s.indexOf(k.slice(t + 1)) : -1;
        if (i >= 0) nodeOpen(key)[i] ^= 1;
      }
    }
    restore();
    const setOpen = (key, i, v) => {
      const op = nodeOpen(key);
      if (!op || !!op[i] === !!v) return;
      op[i] = v ? 1 : 0;
      mem.flip(`${key}\t${sk.get(key).keys[i]}`);
    };
    const setCard = (m, v) => {
      if (m >= 0 && m < K && kinAt[m]) setOpen(kinAt[m].key, kinAt[m].at, v);
    };

    /* ---------- 줄 짓기 ---------- */
    let rows = [];
    let ys = new Int32Array(1);
    let lineOfM = [];
    const lineOf = m => {
      if (lineOfM[m] == null) {
        let v = 0;
        try {
          v = HT.accessionLine(rulers[m].accession || {}) | 0;
        } catch (err) {
          v = 0;
        }
        lineOfM[m] = v >= 0 && v <= 5 ? v : 0;
      }
      return lineOfM[m];
    };
    function rawRows() {
      try {
        const r = HT.successionRows(model, P, opens);
        return r && typeof r.length === 'number' ? r : [];
      } catch (err) {
        console.warn('승계표 줄을 짓지 못했습니다', err);
        return [];
      }
    }
    /* 줄 갈래: 지도자 줄 [0, 칸 번호 m, 0] · 사람 줄 [1, 뼈대 번호 j, 깊이] · 건너뛰기 줄 [2, 그 지도자의 처음 칸 번호 m', 깊이] — 깊이는 그릴 때 8에서 자름 */
    const count = new Int32Array(K).fill(-1);
    if (typeof HT.successionReach === 'function')
      for (let m = 0; m < K; m++) {
        try {
          count[m] = HT.successionReach(model, P, m) | 0;
        } catch (err) {
          count[m] = -1;
        }
      }
    function build() {
      const raw = rawRows();
      const out = [];
      let curKey = null;
      let curM = -1;
      for (let r = 0; r + 2 < raw.length; r += 3) {
        const kind = raw[r];
        const idx = raw[r + 1];
        const third = raw[r + 2];
        if (kind === ROW_LEADER) {
          if (idx < 0 || idx >= K) continue;
          if (out.length) out.push({ t: 'S', m: idx, k: `S${idx}`, h: S_SEAM });
          out.push({ t: 'L', m: idx, k: `L${idx}`, h: S_CARD });
          curM = idx;
          curKey = kinAt[idx] ? kinAt[idx].key : null;
        } else if (curKey && kind === ROW_PERSON) {
          const s = sk.get(curKey);
          if (idx < 0 || idx >= s.n) continue;
          out.push({ t: 'P', m: curM, key: curKey, j: idx, d: Math.max(1, third | 0), k: `P${curKey}\t${s.keys[idx]}`, h: S_ROW });
        } else if (curKey && kind === ROW_SKIP) {
          if (idx < 0 || idx >= K) continue;
          const j = kinAt[idx] && kinAt[idx].key === curKey ? kinAt[idx].at : -1;
          out.push({ t: 'K', m: curM, to: idx, key: curKey, j, d: Math.max(1, third | 0), k: `K${idx}`, h: S_ROW });
        }
      }
      /* 지도자 카드 아래 펼친 줄은 다음 이음매의 선을 왼쪽 여백에 이어 받음 */
      let pend = [];
      for (const row of out) {
        if (row.t === 'P' || row.t === 'K') pend.push(row);
        else if (row.t === 'S') {
          for (const q of pend) q.ln = lineOf(row.m);
          pend = [];
        } else if (row.t === 'L') pend = [];
      }
      rows = out;
      ys = new Int32Array(out.length + 1);
      for (let i = 0; i < out.length; i++) ys[i + 1] = ys[i] + out[i].h;
    }

    /* 지도자 카드의 '후손 n' — 펼침 구간의 사람 수(다음 지도자 아래는 셈하지 않음). 줄 목록의 셋째 수가 있으면 그것 */
    const descN = new Map();
    function descCount(m) {
      if (count[m] >= 0) return count[m];
      if (descN.has(m)) return descN.get(m);
      const k = kinAt[m];
      let n = 0;
      if (k && firstOf[m] === m) {
        const s = sk.get(k.key);
        const lead = leadAt.get(k.key);
        const end = k.at + s.size[k.at];
        for (let j = k.at + 1; j < end; ) {
          if (lead.has(j) && lead.get(j) !== m) j += s.size[j];
          else {
            n++;
            j++;
          }
        }
      }
      descN.set(m, n);
      return n;
    }
    const loops = [];
    for (let m = 0; m < K; m++) if (firstOf[m] !== m) loops.push({ a: firstOf[m], b: m });

    /* ---------- 줄 글 ---------- */
    const elsewhereHTML = list => {
      const xs = (list || []).filter(r => r && r.uid !== P.uid);
      if (!xs.length) return '';
      const chip = r => `<button type="button" class="kv-else" style="--c:${esc(r.color || '')}" data-kv-cell="${esc(r.uid)}" data-kv-ref="${esc(r.ref || `leader:${r.i}`)}" tabindex="-1" title="${esc(`${r.name}${r.ordinal != null ? ` ${r.ordinal}대` : ''} — 그 칸`)}">${esc(r.name)}${r.ordinal != null ? ` ${r.ordinal}대` : ''}</button>`;
      return xs.length > 2 ? `${xs.slice(0, 2).map(chip).join('')}<span class="kv-more">+${xs.length - 2}</span>` : xs.map(chip).join('');
    };
    function leaderHTML(m) {
      const r = rulers[m];
      const c = r.cell || {};
      const end = c.end != null ? c.end : c.endY;
      const when = `${c.startUnknown ? '미정' : yr(c.start)} ~ ${c.endUnknown ? '미정' : end != null ? yr(end) : ''}`.trim();
      let pill = '';
      if (firstOf[m] !== m) pill = `<button type="button" class="kv-pill is-back" data-kv-goto="${firstOf[m]}" tabindex="-1">${esc(ordText(firstOf[m]))}에서</button>`; // 화살표 없이 (건의 8의 5번 A — 고리의 화살촉이 이 카드를 가리킴)
      else if (kinAt[m]) {
        const n = descCount(m);
        const op = cardOpen(m);
        if (n) pill = `<button type="button" class="kv-pill" data-kv-pill="${m}" tabindex="-1" aria-label="${esc(`후손 ${n}명 ${op ? '접기' : '펼치기'}`)}">후손 ${n} ${op ? '▾' : '▸'}</button>`;
      }
      return `<em>${r.ordinal != null ? `${r.ordinal}대` : ''}</em><b>${esc(r.name)}</b>${firstOf[m] !== m ? '<span class="kv-again">다시</span>' : ''}${elsewhereHTML(r.elsewhere)}<small>${esc(when)}</small>${pill}`;
    }
    function seamHTML(m) {
      const r = rulers[m];
      let txt = '';
      try {
        txt = String(HT.accessionSeam(model, r) || '');
      } catch (err) {
        txt = '';
      }
      let html = esc(txt);
      const kn = r.accession && r.accession.kinName;
      if (kn && html.includes(esc(kn))) html = html.replace(esc(kn), `<b>${esc(kn)}</b>`);
      html = html.replace(/(관계 미상|방식 미상|전임자 미상)/g, '<i>$1</i>');
      if (r.restored && !/같은 사람/.test(txt) && firstOf[m] !== m) html += `${html ? ' ' : ''}<i>— ${esc(ordText(firstOf[m]))}와 같은 사람</i>`;
      return `<span>${html}</span>`;
    }
    function personHTML(row) {
      if (row.t === 'K') return `<button type="button" class="kv-skip" data-kv-goto="${row.to}" tabindex="-1">→ ${esc(`${ordText(row.to)} ${rulers[row.to].name}`)}</button>`;
      const s = sk.get(row.key);
      const j = row.j;
      const b = s.bits[j];
      const kids = s.size[j] > 1 && !(b & B_STUB);
      const op = nodeOpen(row.key)[j];
      const node = model.personIndex ? model.personIndex.get(s.keys[j]) : null;
      const tw = kids ? `<i class="kv-tw" data-kv-tw aria-hidden="true">${op ? '▾' : '▸'}</i>` : '<i class="kv-tw" aria-hidden="true"></i>';
      const deep = row.d > 8 ? `<em class="kv-deep">+${row.d - 8}대</em>` : '';
      const name = b & B_UNKNOWN ? '<i class="kv-ring" aria-hidden="true"></i><span class="kv-nm">이름 미상</span>' : `<span class="kv-nm">${esc(s.names[j] || '')}</span>`;
      const sub = s.subs[j] && !(b & B_UNKNOWN) ? `<small>${esc(s.subs[j])}</small>` : '';
      let tail = '';
      if (b & B_FOUNDER) {
        const br = s.branches.find(x => x && x.at === j) || s.branches[s.branch[j]] || null;
        if (br) tail += `<button type="button" class="kv-pill is-branch" data-kv-branch tabindex="-1" style="--c:${esc(br.color || '')}">${esc(br.name)} · ${s.size[j]}명 ${op ? '▾' : '▸'}</button>`;
      }
      if (b & B_LEADER && node)
        for (const q of (node.cells || []).filter(q => q.kind === 'leader' && q.p !== P).slice(0, 2))
          tail += `<button type="button" class="kv-else" style="--c:${esc(q.p.color || '')}" data-kv-cell="${esc(q.p.uid)}" data-kv-ref="${esc(q.ref)}" tabindex="-1">${esc(q.p.name)}${q.c && q.c.ordinal != null ? ` ${q.c.ordinal}대` : ''}</button>`;
      if (!(b & B_MEMBER) && node && node.houseId && model.houseMap && model.houseMap.get(node.houseId)) {
        const h = model.houseMap.get(node.houseId);
        tail += `<button type="button" class="kv-else is-house" style="--c:${esc(h.color || '')}" data-kv-house="${esc(h.id)}" tabindex="-1">${esc(h.name)}</button>`;
      }
      return `${deep}${tw}${name}${sub}${tail}`;
    }
    function rowClass(row, i) {
      let c = `kv-row is-${row.t}`;
      if (row.t === 'P' || row.t === 'K') {
        const s = sk.get(row.key);
        const b = s.bits[row.j];
        if (!(b & B_MEMBER)) c += ' is-out';
        if (b & (B_MISSING | B_UNKNOWN)) c += ' is-faint';
      }
      if (row.t === 'L' && lastLeaderRow === i) c += ' is-last';
      if (i === act) c += ' is-act';
      return c;
    }
    function rowSig(row) {
      if (row.t === 'L') {
        const k = kinAt[row.m];
        return `L${k ? cardOpen(row.m) : 0}`;
      }
      if (row.t === 'P') return `P${nodeOpen(row.key)[row.j]}${row.d}${row.ln}`;
      if (row.t === 'K') return `K${row.ln}`;
      return 'S';
    }
    function rowHTML(row) {
      if (row.t === 'L') return leaderHTML(row.m);
      if (row.t === 'S') return seamHTML(row.m);
      return personHTML(row);
    }

    /* ---------- 그리기 ---------- */
    host.classList.add('kv-succ');
    host.setAttribute('role', 'tree');
    host.setAttribute('aria-label', `${P.name} 승계표`);
    host.tabIndex = 0;
    host.style.setProperty('--c', P.color || '');
    const els = new Map(); // 열쇠 → 요소
    const loopEls = new Map();
    let act = -1;
    let lastLeaderRow = -1;
    let raf = 0;
    const listTop = () => host.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop;
    const rowEl = (row, i) => {
      let el = els.get(row.k);
      if (!el || el._leaving) {
        el = document.createElement('div');
        el.dataset.k = row.k;
        el.id = `kvs-${(host._seq = (host._seq || 0) + 1)}`;
        host.appendChild(el);
        els.set(row.k, el);
        el._new = true;
      }
      const sig = rowSig(row);
      if (el._sig !== sig) {
        el.innerHTML = rowHTML(row);
        el._sig = sig;
      }
      el.className = rowClass(row, i);
      el._row = i;
      if (row.t === 'L' || row.t === 'P' || row.t === 'K') {
        el.setAttribute('role', 'treeitem');
        el.setAttribute('aria-level', row.t === 'L' ? '1' : String(1 + Math.min(row.d || 1, 30)));
        const ex = row.t === 'L' ? (kinAt[row.m] && firstOf[row.m] === row.m && descCount(row.m) ? !!cardOpen(row.m) : null) : row.t === 'P' && sk.get(row.key).size[row.j] > 1 ? !!nodeOpen(row.key)[row.j] : null;
        if (ex == null) el.removeAttribute('aria-expanded');
        else el.setAttribute('aria-expanded', String(ex));
      } else el.setAttribute('role', 'none');
      if (row.ln != null) el.dataset.line = LINE_NAMES[row.ln];
      else if (row.t === 'S') el.dataset.line = LINE_NAMES[lineOf(row.m)];
      else delete el.dataset.line;
      if (row.d) el.style.setProperty('--d', String(Math.min(row.d, 8)));
      return el;
    };
    function place(el, y) {
      el._y = y;
      el.style.transform = `translateY(${y}px)`;
    }
    function render(from = null) {
      raf = 0;
      if (!host.isConnected) return;
      const top = scroller.scrollTop - listTop();
      const vh = scroller.clientHeight || 600;
      const count = rows.length;
      const a = Math.max(0, rowAt(ys, count, Math.max(0, top)) - S_OVERSCAN);
      const b = Math.min(count, rowAt(ys, count, Math.max(0, top + vh)) + 1 + S_OVERSCAN);
      const want = new Set();
      const T = MT();
      const ease = MC().spring;
      const show = i => {
        const row = rows[i];
        want.add(row.k);
        const el = rowEl(row, i);
        const y = ys[i];
        const old = el._new ? (from && from.has(row.k) ? from.get(row.k) : null) : el._y;
        place(el, y);
        if (el._new) {
          el._new = false;
          if (from && old == null && T.in > 0) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: T.in, easing: MC().ease });
          else if (old != null && old !== y && T.move > 0) el.animate([{ transform: `translateY(${old}px)` }, { transform: `translateY(${y}px)` }], { duration: T.move, easing: ease });
        } else if (from && old != null && old !== y && T.move > 0) el.animate([{ transform: `translateY(${old}px)` }, { transform: `translateY(${y}px)` }], { duration: T.move, easing: ease });
      };
      for (let i = a; i < b; i++) show(i);
      if (act >= 0 && act < count && !want.has(rows[act].k)) show(act); // 키보드로 고른 줄은 늘 그려 둠 (aria-activedescendant)
      for (const [k, el] of els) {
        if (want.has(k) || el._leaving) continue;
        const ni = from ? rowsIndex.get(k) : null;
        if (from && T.out > 0 && ni == null) {
          /* 접혀 사라지는 줄: 제자리에서 옅어짐 */
          el._leaving = true;
          els.delete(k);
          el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: T.out, easing: 'ease-in' }).finished.then(() => el.remove(), () => el.remove());
        } else if (from && T.move > 0 && ni != null && ys[ni] !== el._y) {
          /* 화면 밖으로 밀려나는 줄: 새 자리까지 흐른 뒤 걷음 */
          const y0 = el._y;
          el._leaving = true;
          els.delete(k);
          place(el, ys[ni]);
          el.animate([{ transform: `translateY(${y0}px)` }, { transform: `translateY(${ys[ni]}px)` }], { duration: T.move, easing: ease }).finished.then(() => el.remove(), () => el.remove());
        } else {
          els.delete(k);
          el.remove();
        }
      }
      renderLoops(top, vh, from);
      if (act >= 0 && act < count) host.setAttribute('aria-activedescendant', els.get(rows[act].k) ? els.get(rows[act].k).id : '');
      else host.removeAttribute('aria-activedescendant');
    }
    /* 복위 고리: 같은 사람의 두 카드 가운데를 오른쪽 여백에서 잇는 ']' — 펼친 줄만큼 길어짐. 화살촉은 아래 끝(다시 오른 카드 쪽 — 시간이 흐르는 쪽, 건의 8의 5번 A · css/viewer.css .kv-loop::before) */
    function renderLoops(top, vh, from) {
      const seen = new Set();
      for (const { a, b } of loops) {
        const ia = rowsIndex.get(`L${a}`);
        const ib = rowsIndex.get(`L${b}`);
        if (ia == null || ib == null) continue;
        const y1 = ys[ia] + S_CARD / 2;
        const y2 = ys[ib] + S_CARD / 2;
        if (y2 < top - 200 || y1 > top + vh + 200) continue;
        const k = `R${b}`;
        seen.add(k);
        let el = loopEls.get(k);
        const fresh = !el;
        if (!el) {
          el = document.createElement('i');
          el.className = 'kv-loop';
          el.setAttribute('aria-hidden', 'true');
          host.appendChild(el);
          loopEls.set(k, el);
        }
        const old = el._h != null ? [el._y, el._h] : null;
        el._y = y1;
        el._h = y2 - y1;
        el.style.transform = `translateY(${y1}px)`;
        el.style.height = `${y2 - y1}px`;
        if (from && old && (old[0] !== y1 || old[1] !== y2 - y1) && MT().move > 0)
          el.animate([{ transform: `translateY(${old[0]}px)`, height: `${old[1]}px` }, { transform: `translateY(${y1}px)`, height: `${y2 - y1}px` }], { duration: MT().move, easing: MC().spring });
        else if (fresh && from && MT().in > 0) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: MT().in });
      }
      for (const [k, el] of loopEls)
        if (!seen.has(k)) {
          el.remove();
          loopEls.delete(k);
        }
    }
    let rowsIndex = new Map();
    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(() => render());
    };
    function relayout({ anchor = null, animate = true } = {}) {
      const from = new Map();
      rows.forEach((r, i) => from.set(r.k, ys[i]));
      const keepK = anchor === 'top' ? topKey() : null;
      const keepOff = keepK ? from.get(keepK) - (scroller.scrollTop - listTop()) : 0;
      const actK = act >= 0 && rows[act] ? rows[act].k : null;
      const oldRows = rows;
      lineOfM = [];
      build();
      rowsIndex = new Map(rows.map((r, i) => [r.k, i]));
      lastLeaderRow = -1;
      for (let i = rows.length - 1; i >= 0; i--)
        if (rows[i].t === 'L') {
          lastLeaderRow = i;
          break;
        }
      act = actK != null && rowsIndex.has(actK) ? rowsIndex.get(actK) : Math.min(act, rows.length - 1);
      host.style.height = `${ys[rows.length]}px`;
      if (keepK) {
        let k = keepK;
        if (!rowsIndex.has(k)) {
          /* 붙잡은 줄이 접혀 사라졌으면 그 줄이 딸린 지도자 카드를 */
          const old = oldRows.find(r => r.k === k);
          k = old ? `L${old.m}` : null;
        }
        if (k && rowsIndex.has(k)) scroller.scrollTop = listTop() + ys[rowsIndex.get(k)] - keepOff;
      }
      render(animate && !reduced() ? from : null);
    }
    const topKey = () => {
      if (!rows.length) return null;
      const i = rowAt(ys, rows.length, Math.max(0, scroller.scrollTop - listTop()));
      return rows[i] ? rows[i].k : null;
    };

    /* ---------- 접고 펴기 ---------- */
    function toggleLeader(m, deep = false) {
      const k = kinAt[m];
      if (!k || firstOf[m] !== m) return;
      const v = !cardOpen(m);
      setCard(m, v);
      if (deep && v) {
        const s = sk.get(k.key);
        const lead = leadAt.get(k.key);
        for (let j = k.at + 1; j < k.at + s.size[k.at]; ) {
          if (lead.has(j) && lead.get(j) !== m) j += s.size[j];
          else {
            setOpen(k.key, j, 1);
            j++;
          }
        }
      }
      relayout();
    }
    function toggleNode(key, j, { deep = false, value = null } = {}) {
      const s = sk.get(key);
      if (!s || s.size[j] <= 1) return;
      const v = value == null ? !nodeOpen(key)[j] : !!value;
      setOpen(key, j, v);
      if (deep && v) for (let q = j + 1; q < j + s.size[j]; q++) setOpen(key, q, 1);
      relayout();
    }
    function setLevel(lv) {
      mem.reset(lv);
      applyLevel(lv);
      relayout({ anchor: 'top' });
    }
    /** 그 지도자 카드로 — 화면 안에 있으면 0px, 아니면 위에서 조금 아래로 (smooth면 스프링으로 흘러감) */
    let flyRaf = 0;
    function goLeader(m, { smooth = true, expand = false } = {}) {
      const mm = Math.max(0, Math.min(K - 1, m | 0));
      if (expand && kinAt[mm] && firstOf[mm] === mm && !cardOpen(mm)) {
        setCard(mm, 1);
        relayout({ animate: false });
      }
      const i = rowsIndex.get(`L${mm}`);
      if (i == null) return;
      act = i;
      const lt = listTop();
      const y = lt + ys[i];
      const vh = scroller.clientHeight;
      const cur = scroller.scrollTop;
      if (y >= cur + 8 && y + S_CARD <= cur + vh - 36) return render();
      const target = Math.max(0, Math.min(scroller.scrollHeight - vh, y - Math.min(96, vh * 0.2)));
      cancelAnimationFrame(flyRaf);
      if (!smooth || reduced() || !HT.motion || !HT.motion.Spring) {
        scroller.scrollTop = target;
        return render();
      }
      const sp = new HT.motion.Spring(cur, { response: MT().move / 1000, restDelta: 0.5 });
      sp.set(target);
      const step = () => {
        const t = now();
        scroller.scrollTop = sp.value(t);
        if (!sp.done(t)) flyRaf = requestAnimationFrame(step);
        else scroller.scrollTop = target;
      };
      flyRaf = requestAnimationFrame(step);
      const stop = () => {
        cancelAnimationFrame(flyRaf);
        scroller.removeEventListener('wheel', stop);
        scroller.removeEventListener('pointerdown', stop);
      };
      scroller.addEventListener('wheel', stop, { passive: true, once: true });
      scroller.addEventListener('pointerdown', stop, { once: true });
    }

    /** 그 사람의 줄로 — 그 사람이 딸린 지도자 카드부터 조상을 펼쳐 둠 (세계표 · 인물 창의 '승계표에서 보기') */
    function goPerson(key, at0, { smooth = false } = {}) {
      const s = sk.get(key);
      if (!s || at0 < 0 || at0 >= s.n) return false;
      const lead = leadAt.get(key);
      let changed = false;
      for (let q = s.par[at0]; q >= 0; q = s.par[q]) {
        if (lead.has(q)) {
          const m = lead.get(q);
          if (!cardOpen(m)) {
            setCard(m, 1);
            changed = true;
          }
          break;
        }
        if (!nodeOpen(key)[q]) {
          setOpen(key, q, 1);
          changed = true;
        }
      }
      if (changed) relayout({ animate: false });
      const i = rowsIndex.get(`P${key}\t${s.keys[at0]}`);
      if (i == null) return false;
      act = i;
      const target = Math.max(0, listTop() + ys[i] - Math.min(120, scroller.clientHeight * 0.3));
      void smooth;
      scroller.scrollTop = target;
      render();
      return true;
    }

    /* ---------- 누름 ---------- */
    function rowOf(el) {
      const r = el && el.closest ? el.closest('.kv-row') : null;
      return r && r._row != null && rows[r._row] && rows[r._row].k === r.dataset.k ? rows[r._row] : null;
    }
    function openRow(row) {
      if (!row || !o.onOpen) return;
      if (row.t === 'L') return o.onOpen({ type: 'cell', polity: P, i: row.m });
      if (row.t === 'K') return goLeader(row.to);
      if (row.t === 'P') return o.onOpen({ type: 'person', key: sk.get(row.key).keys[row.j], skel: row.key, at: row.j, polity: P });
    }
    function onClick(e) {
      const t = e.target;
      const go = t.closest('[data-kv-goto]');
      if (go && go.dataset.kvGoto !== '') return goLeader(Number(go.dataset.kvGoto));
      const cellBtn = t.closest('[data-kv-cell]');
      if (cellBtn && o.onOpen) {
        const p = model.byUid.get(cellBtn.dataset.kvCell);
        const m = /leader:(\d+)/.exec(cellBtn.dataset.kvRef || '');
        if (p && m) return o.onOpen({ type: 'cell', polity: p, i: Number(m[1]) });
      }
      const hb = t.closest('[data-kv-house]');
      if (hb && o.onOpen) return o.onOpen({ type: 'house', id: hb.dataset.kvHouse });
      const pill = t.closest('[data-kv-pill]');
      if (pill) return toggleLeader(Number(pill.dataset.kvPill), e.altKey);
      const row = rowOf(t);
      if (!row) return;
      act = rowsIndex.get(row.k);
      if (row.t === 'P' && (t.closest('[data-kv-tw]') || t.closest('[data-kv-branch]'))) {
        const branch = !!t.closest('[data-kv-branch]');
        const v = !nodeOpen(row.key)[row.j];
        return toggleNode(row.key, row.j, { deep: e.altKey || (branch && v), value: v });
      }
      openRow(row);
    }
    function onMenu(e) {
      const row = rowOf(e.target);
      if (!row || row.t !== 'P' || !o.onMenu) return;
      e.preventDefault();
      o.onMenu({ type: 'person', key: sk.get(row.key).keys[row.j], skel: row.key, at: row.j, polity: P }, e.clientX, e.clientY);
    }
    /* ---------- 키보드 (ARIA tree — 3-6) ---------- */
    let typed = '';
    let typedAt = 0;
    const itemRows = () => rows.map((r, i) => (r.t === 'S' ? -1 : i)).filter(i => i >= 0);
    function moveAct(i) {
      if (i == null || i < 0 || i >= rows.length) return;
      act = i;
      const lt = listTop();
      const y = lt + ys[i];
      const vh = scroller.clientHeight;
      if (y < scroller.scrollTop) scroller.scrollTop = y - 8;
      else if (y + rows[i].h > scroller.scrollTop + vh - 30) scroller.scrollTop = y + rows[i].h - vh + 30;
      render();
    }
    function parentRow(i) {
      const row = rows[i];
      if (!row || row.t === 'L') return -1;
      const s = sk.get(row.key);
      const p = s.par[row.j];
      const k = kinAt[row.m];
      if (k && p === k.at) return rowsIndex.get(`L${row.m}`);
      const pk = `P${row.key}\t${s.keys[p]}`;
      return rowsIndex.has(pk) ? rowsIndex.get(pk) : rowsIndex.get(`L${row.m}`);
    }
    function onKey(e) {
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      const list = itemRows();
      if (!list.length) return;
      if (act < 0 || !rows[act] || rows[act].t === 'S') act = list[0];
      const pos = list.indexOf(act);
      const row = rows[act];
      const k = e.key;
      const done = () => {
        e.preventDefault();
        e.stopPropagation();
      };
      const expanded = () => (row.t === 'L' ? !!cardOpen(row.m) : row.t === 'P' && !!nodeOpen(row.key)[row.j]);
      const canExpand = () => (row.t === 'L' ? !!kinAt[row.m] && firstOf[row.m] === row.m && descCount(row.m) > 0 : row.t === 'P' && sk.get(row.key).size[row.j] > 1);
      if (k === 'ArrowDown') return done(), moveAct(list[Math.min(list.length - 1, pos + 1)]);
      if (k === 'ArrowUp') return done(), moveAct(list[Math.max(0, pos - 1)]);
      if (k === 'Home') return done(), moveAct(list[0]);
      if (k === 'End') return done(), moveAct(list[list.length - 1]);
      if (k === 'ArrowRight') {
        done();
        if (canExpand() && !expanded()) return row.t === 'L' ? toggleLeader(row.m) : toggleNode(row.key, row.j, { value: 1 });
        if (expanded()) return moveAct(list[Math.min(list.length - 1, pos + 1)]);
        return;
      }
      if (k === 'ArrowLeft') {
        done();
        if (canExpand() && expanded()) return row.t === 'L' ? toggleLeader(row.m) : toggleNode(row.key, row.j, { value: 0 });
        const p = parentRow(act);
        return p != null && p >= 0 ? moveAct(p) : undefined;
      }
      if (k === 'Enter') return done(), openRow(row);
      if (k === ' ' || k === 'Spacebar') {
        done();
        if (canExpand()) return row.t === 'L' ? toggleLeader(row.m) : toggleNode(row.key, row.j);
        return;
      }
      if (k === '*') {
        done();
        /* 같은 층(같은 부모)의 줄을 모두 펼침 — 지도자 줄이면 모든 지도자 */
        if (row.t === 'L') {
          for (let m = 0; m < K; m++) if (kinAt[m] && firstOf[m] === m && descCount(m)) setCard(m, 1);
        } else {
          const s = sk.get(row.key);
          const p = s.par[row.j];
          if (p >= 0) for (const c of kidsOf(s, p)) if (s.size[c] > 1) setOpen(row.key, c, 1);
        }
        return relayout();
      }
      if (k.length === 1 && /\S/.test(k)) {
        done();
        const t = now();
        typed = t - typedAt < 700 ? typed + k : k;
        typedAt = t;
        const name = r => (r.t === 'L' ? rulers[r.m].name : sk.get(r.key).names[r.j] || '');
        const order = list.slice(pos + (typed.length === 1 ? 1 : 0)).concat(list.slice(0, pos + (typed.length === 1 ? 1 : 0)));
        const hit = order.find(i => name(rows[i]).toLowerCase().startsWith(typed.toLowerCase()));
        if (hit != null) moveAct(hit);
      }
    }
    const onScroll = () => {
      schedule();
      clearTimeout(host._topT);
      host._topT = setTimeout(() => {
        const k = topKey();
        if (k && k !== mem.top()) mem.setTop(k);
      }, 300);
    };
    host.addEventListener('click', onClick);
    host.addEventListener('contextmenu', onMenu);
    host.addEventListener('keydown', onKey);
    host.addEventListener('focus', () => {
      if (act < 0) {
        const list = itemRows();
        if (list.length) act = list[0];
      }
      render();
    });
    scroller.addEventListener('scroll', onScroll, { passive: true });
    const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(schedule) : null;
    if (ro) ro.observe(scroller);

    /* 처음: 기억한 펼침 + 데려갈 카드 */
    relayout({ animate: false });
    if (o.focusPerson && goPerson(o.focusPerson.key, o.focusPerson.at)) {
      /* 데려옴 */
    } else if (o.focus != null && o.focus >= 0 && o.focus < K) goLeader(o.focus, { smooth: false, expand: !!o.expand });
    else if (mem.top() && rowsIndex.has(mem.top())) {
      scroller.scrollTop = listTop() + ys[rowsIndex.get(mem.top())];
      render();
    }

    return {
      host,
      setLevel,
      level: () => mem.base() || 'L',
      expandAll: () => setLevel('A'),
      collapseAll: () => setLevel('L'),
      goLeader,
      goPerson,
      focus: () => host.focus({ preventScroll: true }),
      rows: () => rows.map(r => ({ t: r.t, m: r.m, j: r.j, key: r.key, d: r.d, k: r.k })),
      stats: () => ({ rows: rows.length, people: rows.filter(r => r.t === 'P').length, leaders: K, dom: host.querySelectorAll('*').length + 1 }),
      destroy() {
        cancelAnimationFrame(raf);
        cancelAnimationFrame(flyRaf);
        scroller.removeEventListener('scroll', onScroll);
        if (ro) ro.disconnect();
      },
    };
  }

  /* ======================================================================
     세계표 — 가문 창 왼쪽의 떠 있는 창 (4절)
     ====================================================================== */
  let famCtl = null; // 한 번에 하나
  /** 파의 뿌리에서 볼 때: 뿌리 뼈대의 하위 구간을 새로 짓지 않고 번호만 옮겨 봄 (gen은 그 뿌리를 0으로) */
  function slice(S, at) {
    const n = S.size[at];
    const raw = S.raw;
    const sub = arr => (arr && typeof arr.subarray === 'function' ? arr.subarray(at, at + n) : arr ? arr.slice(at, at + n) : arr);
    const par = new Int32Array(n);
    const gen = new Int32Array(n);
    const g0 = S.gen[at];
    for (let i = 0; i < n; i++) {
      par[i] = i === 0 ? -1 : S.par[at + i] - at;
      gen[i] = S.gen[at + i] - g0;
    }
    const extra = [];
    const E = S.extra;
    for (let q = 0; q + 3 < E.length; q += 4) if (E[q] >= at && E[q] < at + n && E[q + 1] >= at && E[q + 1] < at + n) extra.push(E[q] - at, E[q + 1] - at, E[q + 2], E[q + 3]);
    const cells = {};
    for (const [c, i] of Object.entries(S.cells)) if (i >= at && i < at + n) cells[c] = i - at;
    let gens = 0;
    for (let i = 0; i < n; i++) if (gen[i] + 1 > gens) gens = gen[i] + 1;
    const out = Object.assign({}, raw, {
      n,
      gens,
      par,
      size: sub(raw.size),
      gen,
      bits: sub(raw.bits),
      edge: sub(raw.edge),
      branch: sub(raw.branch),
      color: sub(raw.color),
      color2: raw.color2 && raw.color2.length ? sub(raw.color2) : raw.color2,
      name: sub(raw.name),
      sub: sub(raw.sub),
      extra,
      cells,
    });
    if (Array.isArray(raw.key)) out.key = sub(raw.key);
    else if (raw.keys) out.keys = sub(raw.keys);
    const w = wrap(out, `${S.id}@${at}`);
    w.id = `${S.id}@${S.keys[at]}`;
    w.base = g0;
    w.up = S.par[at] >= 0 ? S.par[at] : -1;
    w.upName = w.up >= 0 ? S.names[w.up] : '';
    return w;
  }

  /** 카드 곁글(10.5px)이 곁글 칸 110px(카드 124 − 안쪽 30 + 양옆 8)을 넘을까 — 한글 · 한자는 글자 폭 1em, 나머지는 약 .6em으로 어림(넘으면 왼쪽 맞춤 + 끝 옅게) */
  function subWide(t) {
    let w = 0;
    for (const ch of t || '') w += /[\u1100-\u11ff\u3000-\u9fff\uac00-\ud7af\uf900-\ufaff]/.test(ch) ? 10.5 : 6.3;
    return w > 110;
  }
  /** 세계표 창 자리: 가문 창 왼쪽(겹치지 않게), 좁으면 왼쪽 끝 — 끌어 옮긴 자리('@win')는 기억 */
  function placeFamily(el, o) {
    const sr = o.stage.getBoundingClientRect();
    const near = o.placeNear && !o.placeNear.hidden ? o.placeNear.getBoundingClientRect() : null;
    const W = Math.min(830, Math.max(360, (near ? near.left - sr.left : sr.width) - 24));
    const H = Math.min(910, sr.height - 24);
    const saved = o.store && o.store.get ? o.store.get('@win') : null;
    let x = near ? near.left - sr.left - 12 - W : sr.width - 12 - W;
    let y = 12;
    if (saved && isFinite(saved.x) && isFinite(saved.y)) {
      x = saved.x;
      y = saved.y;
    }
    x = Math.max(12 - W + 120, Math.min(sr.width - 120, x));
    y = Math.max(0, Math.min(sr.height - 48, y));
    Object.assign(el.style, { left: `${Math.round(x)}px`, top: `${Math.round(y)}px`, width: `${Math.round(W)}px`, height: `${Math.round(H)}px` });
  }
  /**
   * 큰 뼈대를 나눠 짓는 동안의 세계표 창(4-6): 같은 자리 · 같은 머리 칩 · 제목에 '세계표를 짓고 있습니다'(--t-in)만 — 다 지으면 진짜 창으로 바꿉니다.
   * 그사이 닫거나(✕ · Esc) 다른 세계표를 열면 지은 뒤에도 열지 않습니다. 돌려주는 것은 family()와 같은 이름의 손잡이(지금은 빈 값).
   */
  function familyLater(o, wait) {
    const el = document.createElement('section');
    el.className = 'detail kv-fam is-building';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-label', o.title || '세계표');
    el.setAttribute('aria-busy', 'true');
    el.innerHTML = `
      <div class="detail-head">
        <div class="badges">${o.headHTML || ''}</div>
        <button class="icon-btn" data-kv="close" type="button" aria-label="세계표 닫기">✕</button>
      </div>
      <div class="kv-title"><h2>${esc(o.title || '세계표')}</h2></div>
      <div class="kv-view kv-wait"><div class="kv-building">세계표를 짓고 있습니다</div></div>`;
    o.stage.appendChild(el);
    placeFamily(el, o);
    let over = false;
    function close({ quiet = false } = {}) {
      if (over) return;
      over = true;
      el.remove();
      if (famCtl === api) famCtl = null;
      if (!quiet && o.onClose) o.onClose();
    }
    el.addEventListener('click', e => {
      if (e.target.closest('[data-kv="close"]')) return close();
      if (o.onLink) o.onLink(e.target, e);
    });
    el.addEventListener('keydown', e => {
      if (e.key !== 'Escape' || e.defaultPrevented) return;
      e.preventDefault();
      e.stopPropagation();
      close();
    });
    const api = {
      el,
      key: o.key,
      house: o.house || null,
      building: true,
      close,
      focusKey: k => {
        o.focusKey = k;
      },
      reveal: () => {},
      toggle: () => {},
      setBase: () => {},
      open: () => false,
      indexOf: () => -1,
      layout: () => null,
      scroll: () => o.scroll || null,
      focusedKey: () => o.focusKey || null,
      cardRect: () => null,
      stats: () => ({ n: 0, cards: 0, dom: el.querySelectorAll('*').length + 1, visible: 0, building: true }),
    };
    famCtl = api;
    wait.then(() => {
      if (over || famCtl !== api) return;
      over = true;
      famCtl = null;
      el.remove();
      family(Object.assign({}, o, { built: true }));
    });
    return api;
  }

  /**
   * o = { stage(붙일 곳 — 연표 무대), model, key(뿌리 뼈대 열쇠), house(가문 — 파면 그 파), focusKey(데려갈 사람의 안정 열쇠), headHTML(머리 칩 HTML),
   *       title, store({ get, set }), placeNear(가문 창 요소 — 그 왼쪽에), onOpen(action), onLink(el, e), onMenu(action, x, y), onClose(),
   *       footHTML(바닥 줄 끝에 붙일 단추 — 메이커의 '＋ 사람'. 누름은 onLink로), again(새 모델로 다시 짓는 창 — 들어오는 움직임 없음) }
   * 돌려주는 것: { el, close(), focusKey(k), refresh(model), stats() }
   */
  function family(o) {
    if (famCtl) famCtl.close({ quiet: true });
    const wait = o.built ? null : prepare(o.model, [o.key]);
    if (wait) return familyLater(o, wait);
    const model = o.model;
    const root = skeleton(model, o.key);
    if (!root) return null;
    let at = -1;
    if (o.house && o.house.parent) at = branchRoot(root, `house:${o.house.id}`);
    const S = at > 0 ? slice(root, at) : root;
    const viewRaw = () => S.raw; // 파면 번호를 옮긴 하위 구간(slice), 아니면 뿌리 뼈대 그대로 — HT.kinLayout · kinDefaultOpen이 받는 꼴
    const base = S.base || 0;
    const mem = memo(o.store, S.id);
    /* 보기 단계(F_SCALES — 아래 줄의 [보통 | 점] · V · Ctrl+휠). 다시 지은 창(o.scale)은 보던 단계 그대로 */
    let sc = F_SCALES[Math.max(0, Math.min(F_SCALES.length - 1, o.scale | 0))];
    const half = () => sc.w >> 1; // 사람 폭의 반 (보통 62 · 점 6)
    const elbow = () => sc.h + (sc.row - sc.h) / 2; // 부모 → 자식 선이 꺾이는 높이(사람 윗변에서 — 보통 62 · 점 21)

    /* ---------- 펼침 ---------- */
    let open = null;
    const defOpen = () => {
      let d = null;
      try {
        d = HT.kinDefaultOpen(viewRaw());
      } catch (err) {
        d = null;
      }
      const u = new Uint8Array(S.n);
      if (d && d.length >= S.n) u.set(d.subarray ? d.subarray(0, S.n) : d.slice(0, S.n));
      else u.fill(1);
      return u;
    };
    function baseOpen(b) {
      if (b === 'a') return new Uint8Array(S.n).fill(1);
      if (b === 'n') return new Uint8Array(S.n);
      if (/^g\d+$/.test(b)) {
        const lim = Number(b.slice(1));
        const u = new Uint8Array(S.n);
        for (let i = 0; i < S.n; i++) u[i] = S.gen[i] < lim - 1 ? 1 : 0;
        return u;
      }
      return defOpen();
    }
    open = baseOpen(mem.base());
    for (const k of mem.keys()) {
      const i = S.indexOf(k);
      if (i >= 0) open[i] ^= 1;
    }
    const setOpen = (i, v) => {
      if (!!open[i] === !!v) return;
      open[i] = v ? 1 : 0;
      mem.flip(S.keys[i]);
    };

    /* ---------- 창 ---------- */
    const el = document.createElement('section');
    el.className = `detail kv-fam${sc.dots ? ' is-dots' : ''}`;
    if (o.again) el.style.animation = 'none'; // 새 모델로 다시 지은 창(메이커에서 사람을 더함 등)은 들어오는 움직임 없이 제자리에
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-label', o.title || '세계표');
    let leaders = 0;
    for (let i = 0; i < S.n; i++) if (S.bits[i] & B_LEADER) leaders++;
    el.innerHTML = `
      <div class="detail-head" data-kv-drag>
        <div class="badges">${o.headHTML || ''}</div>
        <button class="icon-btn" data-kv="close" type="button" aria-label="세계표 닫기">✕</button>
      </div>
      <div class="kv-title"><h2>${esc(o.title || '세계표')}</h2><span>사람 ${S.n.toLocaleString()}${leaders ? ` · 지도자 ${leaders.toLocaleString()}` : ''}</span></div>
      ${at > 0 && S.upName ? `<p class="kv-crumb">본가 쪽: <button type="button" class="linky" data-kv-up>${esc(S.upName)}</button> 아래에서 갈라짐</p>` : ''}
      ${legendHTML('family')}
      <div class="kv-view" tabindex="0" role="tree" aria-label="${esc(o.title || '세계표')}">
        <div class="kv-plane"><svg class="kv-edges" aria-hidden="true"></svg></div>
        <div class="kv-gens" aria-hidden="true"><span class="kv-genhead">세대</span></div>
        <div class="kv-building" hidden>세계표를 짓고 있습니다</div>
        <div class="kv-tip" role="tooltip" hidden></div>
      </div>
      <div class="kv-over" aria-label="전체도 — 누르거나 끌면 그리로"><canvas></canvas><i class="kv-over-box"></i></div>
      <div class="detail-foot kv-foot">
        <div class="kv-seg" role="radiogroup" aria-label="보기 단계" title="보기 단계 (V · Ctrl+휠)">${F_SCALES.map((z, k) => `<button type="button" role="radio" data-kv-scale="${k}" aria-checked="${z === sc}">${esc(z.name)}</button>`).join('')}</div>
        <button class="btn btn-sm" data-kv="all" type="button">모두 펼치기</button>
        <button class="btn btn-sm" data-kv="none" type="button">모두 접기</button>
        <label class="kv-lv">세대 수준 <select data-kv="level"></select></label>
        <label class="kv-find">찾기 <input data-kv="find" type="text" autocomplete="off" spellcheck="false"></label>
        ${o.footHTML || ''}
      </div>`;
    const view = el.querySelector('.kv-view');
    const plane = el.querySelector('.kv-plane');
    const svg = el.querySelector('.kv-edges');
    const gensEl = el.querySelector('.kv-gens');
    const canvas = el.querySelector('.kv-over canvas');
    const box = el.querySelector('.kv-over-box');
    const findIn = el.querySelector('[data-kv="find"]');
    const lvSel = el.querySelector('[data-kv="level"]');
    const SVGNS = 'http://www.w3.org/2000/svg';
    const PATHS = ['solid', 'adopt', 'skip', 'solid is-weak', 'adopt is-weak', 'skip is-weak'];
    const paths = PATHS.map(c => {
      const p = document.createElementNS(SVGNS, 'path');
      p.setAttribute('class', `kv-e ${c}`);
      svg.appendChild(p);
      return p;
    });
    {
      const opts = ['<option value="">—</option>'];
      const top = Math.min(S.gens, 30);
      for (let g = 2; g <= top; g++) opts.push(`<option value="g${g}">${g}세대까지</option>`);
      lvSel.innerHTML = opts.join('');
      lvSel.value = /^g\d+$/.test(mem.base()) ? mem.base() : '';
    }
    o.stage.appendChild(el);
    /* 자리: 가문 창 왼쪽(겹치지 않게), 좁으면 왼쪽 끝 — 끌어 옮긴 자리는 기억 */
    const stageR = () => o.stage.getBoundingClientRect();
    const placeWin = () => placeFamily(el, o);
    placeWin();

    /* ---------- 자리 셈 ---------- */
    let L = null;
    let vis = new Uint8Array(S.n);
    let contentW = 0;
    let contentH = 0;
    let sx = 0;
    let sy = 0;
    const cardX = i => F_PADX + L.x[i] * sc.u - half();
    const cardY = i => F_PADY + S.gen[i] * sc.row;
    /** 판의 크기 — 단계가 바뀌면 이것만 다시 (자리 셈 L은 그대로) */
    function dims() {
      contentW = F_PADX + (L.width || 0) * sc.u + 16;
      contentH = F_PADY + S.gens * sc.row;
    }
    function layout() {
      L = HT.kinLayout(viewRaw(), open);
      vis = new Uint8Array(S.n);
      for (const r of L.rows || []) for (let q = 0; q < r.length; q++) vis[r[q]] = 1;
      dims();
    }
    const vw = () => view.clientWidth || 800;
    const vh = () => view.clientHeight || 600;
    /** 스크롤을 내용 안으로 — fx · fy(옮기기 전 자리)를 주면 그 자리까지는 허락(접어서 내용이 줄어도 누른 카드가 0px로 남게: 더 밖으로는 못 가고 안쪽으로만) */
    const clampScroll = (fx = null, fy = null) => {
      const hx = Math.max(0, contentW - vw());
      const hy = Math.max(0, contentH - vh());
      sx = Math.max(Math.min(0, fx == null ? 0 : fx), Math.min(Math.max(hx, fx == null ? hx : fx), sx));
      sy = Math.max(Math.min(0, fy == null ? 0 : fy), Math.min(Math.max(hy, fy == null ? hy : fy), sy));
    };

    /* ---------- 그리기 ---------- */
    const cards = new Map(); // 번호 → 요소
    const deco = new Map(); // 알약 · 파 이름표 · 딱지 — 열쇠 → 요소
    let anim = null; // { from: Map(i → [x, y]), sp, t0, fromScroll }
    let focus = -1;
    let raf = 0;
    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(frame);
    };
    function posOf(i, p) {
      /* p = 움직임 진행(0 → 1). 옛 자리가 없는 카드(새로 펼친 자식)는 옛 자리가 있던 가장 가까운 조상의 자리에서 흘러나옴 */
      const nx = cardX(i);
      const ny = cardY(i);
      if (!anim || p >= 1) return [nx, ny];
      let f = anim.from.get(i);
      if (!f) {
        if (!anim.origin.has(i)) {
          let a = S.par[i];
          while (a >= 0 && !anim.from.has(a)) a = S.par[a];
          anim.origin.set(i, a >= 0 ? anim.from.get(a) : null);
        }
        f = anim.origin.get(i);
        if (!f) return [nx, ny];
      }
      return [f[0] + (nx - f[0]) * p, f[1] + (ny - f[1]) * p];
    }
    function cardClass(i) {
      const b = S.bits[i];
      let c = 'kv-p';
      if (b & B_UNKNOWN) c += ' is-unk';
      else if (b & B_LEADER) c += S.color2(i) || b & B_TWO ? ' is-ruler is-two' : ' is-ruler';
      else c += ' is-paper';
      if (!(b & B_MEMBER)) c += ' is-out';
      if (b & B_MISSING) c += ' is-miss';
      if (!sc.dots && !(b & B_UNKNOWN) && (S.size[i] > 1 || b & B_STUB)) c += open[i] && !(b & B_STUB) ? ' is-open' : ' is-closed'; // 점 단계 · 이름 미상의 원에는 손잡이가 없음(접기는 Space · 모두 접기 — 목업 #s4 '후')
      if (i === focus) c += ' is-focus';
      if (!sc.dots && !(b & B_UNKNOWN) && subWide(S.subs[i])) c += ' is-lsub'; // 곁글이 카드보다 길면 끝을 옅게
      return c;
    }
    function cardEl(i) {
      let c = cards.get(i);
      if (!c) {
        c = document.createElement('div');
        c.dataset.i = String(i);
        c.id = `kvf-${i}`;
        c.setAttribute('role', 'treeitem');
        const b = S.bits[i];
        /* 이름 미상은 글자 없이 원 하나(건의 8의 4-다), 점 단계는 점만 — 이름은 올리면 풍선(.kv-tip). 읽어 주는 이름은 aria-label에 */
        const bare = !!(b & B_UNKNOWN) || sc.dots;
        c.textContent = bare ? '' : S.names[i] || '';
        const sub = b & B_UNKNOWN ? '' : S.subs[i] || '';
        if (sub && !sc.dots) c.dataset.sub = sub;
        const c1 = S.color(i);
        const c2 = S.color2(i);
        if (c1) c.style.setProperty('--c', c1);
        if (c2) c.style.setProperty('--c2', c2);
        c.setAttribute('aria-level', String(S.gen[i] + 1));
        const label = `${b & B_UNKNOWN ? '이름 미상' : S.names[i] || ''}${sub ? ` · ${sub}` : ''}`;
        if (bare) c.setAttribute('aria-label', label);
        else c.title = label;
        plane.appendChild(c);
        cards.set(i, c);
        c._new = true;
      }
      const cls = cardClass(i);
      if (c.className !== cls) c.className = cls;
      if (S.size[i] > 1 || S.bits[i] & B_STUB) c.setAttribute('aria-expanded', String(!!open[i] && !(S.bits[i] & B_STUB)));
      return c;
    }
    function decoEl(k, cls, html, x, y, attrs = {}) {
      let d = deco.get(k);
      if (!d) {
        d = document.createElement(attrs.button ? 'button' : 'span');
        if (attrs.button) {
          d.type = 'button';
          d.tabIndex = -1;
        }
        plane.appendChild(d);
        deco.set(k, d);
        d._new = true;
      }
      if (d._cls !== cls) d.className = d._cls = cls;
      if (d._html !== html) d.innerHTML = d._html = html;
      for (const [a, v] of Object.entries(attrs)) if (a !== 'button') d.setAttribute(a, v);
      d.style.transform = `translate(${x}px, ${y}px)`;
      d._seen = true;
      return d;
    }
    /** 같은 세대의 보이는 번호(왼 → 오른)에서 화면 x 범위에 드는 구간 — 블록이 걸칠 수 있게 양쪽 하나씩 더 */
    function rowRange(g, x0, x1) {
      const r = L.rows[g];
      if (!r || !r.length) return [0, 0, r];
      let lo = 0;
      let hi = r.length;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (cardX(r[mid]) + sc.w < x0) lo = mid + 1;
        else hi = mid;
      }
      let a = lo;
      let b = lo;
      while (b < r.length && cardX(r[b]) <= x1) b++;
      return [Math.max(0, a - 1), Math.min(r.length, b + 1), r];
    }
    function frame() {
      raf = 0;
      if (!el.isConnected || !L) return;
      let p = 1;
      if (anim) {
        const t = now();
        p = Math.min(1, Math.max(0, anim.sp.value(t)));
        if (anim.sp.done(t)) {
          p = 1;
          anim = null;
        }
      }
      draw(p);
      if (anim) schedule();
    }
    function draw(p) {
      const W = vw();
      const H = vh();
      const mx = 240;
      const my = sc.row * 2;
      const x0 = sx - mx;
      const x1 = sx + W + mx;
      const g0 = Math.max(0, Math.floor((sy - my - F_PADY) / sc.row));
      const g1 = Math.min(S.gens - 1, Math.ceil((sy + H + my - F_PADY) / sc.row));
      plane.style.transform = `translate(${-sx}px, ${-sy}px)`;
      const want = [];
      for (let g = g0; g <= g1; g++) {
        const [a, b, r] = rowRange(g, x0, x1);
        for (let q = a; q < b; q++) want.push(r[q]);
      }
      /* 상한: 화면 가운데에서 먼 것부터 버림 */
      if (want.length > F_CAP) {
        const cx = sx + W / 2;
        const cy = sy + H / 2;
        want.sort((u, v) => Math.hypot(cardX(u) + half() - cx, cardY(u) - cy) - Math.hypot(cardX(v) + half() - cx, cardY(v) - cy));
        want.length = F_CAP;
      }
      if (focus >= 0 && vis[focus] && !want.includes(focus)) want.push(focus);
      /* 움직이는 동안: 사라질 카드(옛 자리에 있던 것)도 그 부모 쪽으로 모이며 옅어짐 */
      const keep = new Set(want);
      const T = MT();
      for (const i of want) {
        const c = cardEl(i);
        const [x, y] = posOf(i, p);
        c.style.transform = `translate(${x}px, ${y}px)`;
        if (c._new) {
          c._new = false;
          if (anim && !anim.from.has(i) && T.in > 0) c.animate([{ opacity: 0 }, { opacity: 1 }], { duration: T.in, easing: MC().ease });
        }
        if (c._gone) {
          c._gone = false;
          c.style.opacity = '';
        }
      }
      for (const [i, c] of cards) {
        if (keep.has(i)) continue;
        if (anim && anim.from.has(i) && !vis[i] && p < 1) {
          /* 접혀 사라지는 카드: 접은 조상의 새 자리로 모이며 옅어짐 */
          let up = S.par[i];
          while (up >= 0 && !vis[up]) up = S.par[up];
          const f = anim.from.get(i);
          const tx = up >= 0 ? cardX(up) : f[0];
          const ty = up >= 0 ? cardY(up) : f[1];
          const q = Math.min(1, p * (T.move / Math.max(1, T.out)));
          c.style.transform = `translate(${f[0] + (tx - f[0]) * p}px, ${f[1] + (ty - f[1]) * p}px)`;
          c.style.opacity = String(Math.max(0, 1 - q));
          c._gone = true;
          continue;
        }
        c.remove();
        cards.delete(i);
      }
      drawEdges(p, g0, g1, x0, x1, keep);
      drawDeco(p, keep);
      drawGens(g0, g1);
      drawBox();
      placeTip();
      if (focus >= 0 && cards.get(focus)) view.setAttribute('aria-activedescendant', cards.get(focus).id);
      else view.removeAttribute('aria-activedescendant');
    }
    /* 선: 부모 → 자식 꺾인 실선(형제는 가로 토막 하나) · 짧은 파선(나무 부모가 양부 · 양모) · 긴 파선(n대손) · +4 옅게 — 갈래마다 path 하나.
       보통 단계의 이름 미상은 원 하나(지름 14)라 부모 선은 원 아래에서 나가고 자식으로 오는 선은 원 위에 닿음(건의 8의 4-다) */
    function drawEdges(p, g0, g1, x0, x1, keep) {
      const ds = ['', '', '', '', '', ''];
      const add = (k, d) => (ds[k] += d);
      const mid = i => posOf(i, p);
      const hf = half();
      const bend = elbow();
      const ring = i => !sc.dots && S.bits[i] & B_UNKNOWN;
      const bottomOf = (i, y) => (ring(i) ? y + sc.h / 2 + F_RING / 2 : y + sc.h);
      const topOf = (i, y) => (ring(i) ? y + sc.h / 2 - F_RING / 2 : y);
      for (let g = Math.max(0, g0 - 1); g <= g1; g++) {
        const [a, b, r] = rowRange(g, x0 - 600, x1 + 600);
        for (let q = a; q < b; q++) {
          const i = r[q];
          if (!open[i] || S.size[i] <= 1 || S.bits[i] & B_STUB) continue;
          const [px, py] = mid(i);
          const ax = px + hf;
          const ay = bottomOf(i, py);
          const yMid = py + bend;
          for (const c of kidsOf(S, i)) {
            if (!vis[c]) continue;
            const [cx0, cy] = mid(c);
            const cx = cx0 + hf;
            const e = S.edge[c] | 0;
            const kind = e & 3;
            const k = (kind === 2 ? 2 : kind === 1 ? 1 : 0) + (e & 4 ? 3 : 0);
            add(k, `M${ax} ${ay}V${yMid}H${cx}V${topOf(c, cy)}`);
          }
        }
      }
      /* 덧선(양자 · 둘째 부모): 두 끝이 12칸 안이고 하나라도 화면 근처 — 옆구리로 들어감 */
      const E = S.extra;
      for (let q = 0; q + 3 < E.length; q += 4) {
        const f = E[q];
        const t = E[q + 1];
        if (!vis[f] || !vis[t]) continue;
        if (Math.abs(L.x[f] - L.x[t]) > F_FAR) continue;
        if (!keep.has(f) && !keep.has(t)) continue;
        const [fx0, fy] = mid(f);
        const [tx0, ty] = mid(t);
        const fx = fx0 + hf;
        const fMid = fy + bend;
        const side = sc.dots ? tx0 - 3 : S.bits[t] & B_SIDE ? tx0 - 21 : tx0 - 4;
        const kind = E[q + 2] | 0;
        const k = ((kind & 3) === 2 ? 2 : 1) + (kind & 4 ? 3 : 0);
        add(k, `M${fx} ${bottomOf(f, fy)}V${fMid}H${side}V${ty + sc.h / 2}H${ring(t) ? tx0 + hf - F_RING / 2 : tx0}`);
      }
      paths.forEach((pa, k) => {
        if (pa._d !== ds[k]) pa.setAttribute('d', (pa._d = ds[k]));
      });
    }
    /* 알약 · 파 이름표 · 딱지 (겹치지 않는 자리 — 4-3 · 4-5) */
    function drawDeco(p, keep) {
      if (sc.dots) {
        /* 점 단계: 알약 · 파 이름표 · 딱지 · 꼬리표 없이 점과 선만 */
        for (const d of deco.values()) d.remove();
        deco.clear();
        return;
      }
      for (const d of deco.values()) d._seen = false;
      for (const i of keep) {
        if (!vis[i]) continue;
        const [x, y] = posOf(i, p);
        const b = S.bits[i];
        const closed = (S.size[i] > 1 && !open[i]) || b & B_STUB;
        /* 파 이름표: 파조 카드 윗변 바로 위 왼쪽, 가운데 8px 앞까지 */
        if (b & 16 && i !== 0) {
          const br = S.branches.find(z => z && z.at === (at > 0 ? i + at : i)) || S.branches[S.branch[i]];
          if (br) decoEl(`b${i}`, 'kv-blabel', `${esc(br.name)}`, x, y - 18, { button: true, style: `--c:${br.color || ''}`, 'data-kv-br': String(i), title: `${br.name} — 누르면 파째 접고 펴기 · 오른쪽 누르기는 가문 창` });
        }
        const far = farOf(i);
        if (closed) {
          const n = b & B_STUB ? (S.stubs[String(i)] || {}).n || S.size[i] : S.size[i] - 1;
          const br = b & 16 ? S.branches.find(z => z && z.at === (at > 0 ? i + at : i)) : null;
          const txt = br ? `${esc(br.name)} · ${(br ? S.size[i] : n).toLocaleString()}명` : `후손 ${n.toLocaleString()}명`;
          decoEl(`p${i}`, `kv-fpill${far.from || far.to ? ' is-right' : ''}`, txt, x + (far.from || far.to ? F_HALF + 8 : F_HALF), y + F_CH + 4, { button: true, 'data-kv-open': String(i) });
        }
        if (far.from) decoEl(`af${i}`, 'kv-far', `${esc(far.from.text)} →`, x, y + F_CH + 3, { button: true, 'data-kv-fly': String(far.from.to) });
        else if (far.to && !closed) decoEl(`at${i}`, 'kv-far is-right', esc(far.to.text), x + F_HALF + 8, y + F_CH + 3, { button: true, 'data-kv-fly': String(far.to.from) });
      }
      /* 나무 선의 딱지: 양자(나무 부모가 양부) · n대손 */
      for (const i of keep) {
        if (!vis[i] || S.par[i] < 0 || !vis[S.par[i]]) continue;
        const e = S.edge[i] & 3;
        if (!e) continue;
        const [x, y] = posOf(i, p);
        const pg = S.gen[S.par[i]];
        const n = S.gen[i] - pg;
        const yMid = posOf(S.par[i], p)[1] + F_CH + 20;
        if (e === 2) decoEl(`g${i}`, 'kv-tag', `${n}대손`, x + F_HALF, (yMid + y) / 2, {});
        else if (e === 1) decoEl(`g${i}`, 'kv-tag', '양자', x + F_HALF, yMid + 10, {});
      }
      /* 덧선의 딱지: 가로 토막(세대 사이 틈)의 가운데 — 양자 · n대손 */
      const E = S.extra;
      for (let q = 0; q + 3 < E.length; q += 4) {
        const f = E[q];
        const t = E[q + 1];
        if (!vis[f] || !vis[t] || Math.abs(L.x[f] - L.x[t]) > F_FAR || (!keep.has(f) && !keep.has(t))) continue;
        const [fx0, fy] = posOf(f, p);
        const [tx0, ty] = posOf(t, p);
        const kind = E[q + 2] & 3;
        const side = S.bits[t] & B_SIDE ? tx0 - 21 : tx0 - 4;
        const text = kind === 2 ? `${E[q + 3] || 1}대손` : kind === 1 ? '양자' : '';
        if (!text) continue;
        /* 두 세대 이상 떨어지면 자식 옆구리로 내려가는 세로 토막 위(그 위 세대 사이 틈의 위쪽 반 — 카드 · 빗과 겹치지 않음), 바로 아래 세대면 가로 토막 가운데 */
        if (S.gen[t] - S.gen[f] >= 2) decoEl(`e${q}`, 'kv-tag', text, side, ty - 30, {});
        else decoEl(`e${q}`, 'kv-tag', text, (fx0 + F_HALF + side) / 2, fy + F_CH + 20, {});
      }
      for (const [k, d] of deco)
        if (!d._seen) {
          d.remove();
          deco.delete(k);
        }
    }
    /* 먼 덧선의 꼬리표 — 이 마디가 양부(from) · 양자(to)인 먼 덧선 하나씩 */
    let farMap = null;
    function farOf(i) {
      if (!farMap) {
        farMap = new Map();
        const E = S.extra;
        for (let q = 0; q + 3 < E.length; q += 4) {
          const f = E[q];
          const t = E[q + 1];
          if (!vis[f] || !vis[t] || Math.abs(L.x[f] - L.x[t]) <= F_FAR) continue;
          const ad = (E[q + 2] & 3) === 1;
          const a = farMap.get(f) || farMap.set(f, {}).get(f);
          if (!a.from) a.from = { to: t, text: `${ad ? '양자' : '자손'} ${S.names[t] || '이름 미상'}` };
          const z = farMap.get(t) || farMap.set(t, {}).get(t);
          if (!z.to) z.to = { from: f, text: `${ad ? '양가' : '부모'} ${S.names[f] || '이름 미상'}` };
        }
      }
      return farMap.get(i) || {};
    }
    const genEls = new Map();
    function drawGens(g0, g1) {
      const seen = new Set();
      for (let g = g0; g <= g1; g++) {
        let s = genEls.get(g);
        if (!s) {
          s = document.createElement('span');
          s.className = 'kv-gen';
          s.textContent = String(g + base + 1);
          gensEl.appendChild(s);
          genEls.set(g, s);
        }
        s.style.transform = `translateY(${F_PADY + g * sc.row + sc.h / 2 - 8 - sy}px)`;
        seen.add(g);
      }
      for (const [g, s] of genEls)
        if (!seen.has(g)) {
          s.remove();
          genEls.delete(g);
        }
      gensEl.firstElementChild.style.transform = `translateY(${-sy}px)`;
    }
    /* ---------- 전체도 (보이는 사람 모두 — 세대 × 칸 1px 막대, 자리 셈이 바뀔 때만 다시) ---------- */
    function drawOverview() {
      const cw = Math.max(40, canvas.parentElement.clientWidth || 600);
      const ch = 56;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      canvas.width = Math.round(cw * dpr);
      canvas.height = Math.round(ch * dpr);
      canvas.style.width = `${cw}px`;
      canvas.style.height = `${ch}px`;
      const g = canvas.getContext('2d');
      if (!g) return;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, cw, ch);
      const sxk = cw / Math.max(1, contentW);
      const syk = ch / Math.max(1, contentH);
      const ink = getComputedStyle(el).getPropertyValue('--text-3').trim() || '#8f897d';
      g.fillStyle = ink;
      g.globalAlpha = 0.55;
      const rh = Math.max(1, sc.h * syk);
      for (let gg = 0; gg < (L.rows || []).length; gg++) {
        const r = L.rows[gg];
        const y = (F_PADY + gg * sc.row) * syk;
        for (let q = 0; q < r.length; q++) {
          const i = r[q];
          g.fillRect(cardX(i) * sxk, y, Math.max(1, sc.w * sxk), rh);
        }
      }
      g.globalAlpha = 1;
    }
    function drawBox() {
      const cw = canvas.clientWidth || 1;
      const ch = 56;
      const kx = cw / Math.max(1, contentW);
      const ky = ch / Math.max(1, contentH);
      const w = Math.max(6, Math.min(cw, vw() * kx));
      const h = Math.max(6, Math.min(ch, vh() * ky));
      box.style.transform = `translate(${Math.min(cw - w, sx * kx)}px, ${Math.min(ch - h, sy * ky)}px)`;
      box.style.width = `${w}px`;
      box.style.height = `${h}px`;
    }

    /* ---------- 접고 펴기 — 누른 카드는 화면에서 0px ---------- */
    function relayout(pin = -1, { animate = true } = {}) {
      const from = new Map();
      if (L) for (const i of cards.keys()) if (vis[i]) from.set(i, [cardX(i), cardY(i)]);
      const px = pin >= 0 && L && vis[pin] ? cardX(pin) - sx : null;
      const py = pin >= 0 && L && vis[pin] ? cardY(pin) - sy : null;
      /* 화면 밖에서 들어올 카드의 옛 자리도 (그 사이 보이던 것만) */
      const oldL = L;
      const oldVis = vis;
      layout();
      farMap = null;
      if (oldL) for (let g = 0; g < (oldL.rows || []).length; g++) {
        const r = oldL.rows[g];
        for (let q = 0; q < r.length; q++) {
          const i = r[q];
          if (from.has(i) || !vis[i]) continue;
          const nx = cardX(i);
          const ox = F_PADX + oldL.x[i] * sc.u - half();
          if (Math.abs(nx - sx) < vw() * 2 || Math.abs(ox - sx) < vw() * 2) from.set(i, [ox, F_PADY + S.gen[i] * sc.row]);
        }
      }
      const sx0 = sx;
      const sy0 = sy;
      if (px != null) {
        sx = cardX(pin) - px;
        sy = cardY(pin) - py;
      }
      if (px != null) clampScroll(sx, sy);
      else clampScroll();
      drawOverview();
      if (animate && !reduced() && from.size && HT.motion && HT.motion.Spring) {
        /* 옛 자리 → 새 자리를 화면 자리로 잇습니다: 옛 자리를 스크롤이 옮긴 만큼 밀어 두면, 누른 카드는 두 자리가 같아 화면에서 0px */
        const dx = sx - sx0;
        const dy = sy - sy0;
        for (const [i, f] of from) from.set(i, [f[0] + dx, f[1] + dy]);
        void oldVis;
        anim = { from, origin: new Map(), sp: new HT.motion.Spring(0, { response: MT().move / 1000, restDelta: 0.002, restSpeed: 0.02 }) };
        anim.sp.set(1);
      } else anim = null;
      schedule();
    }
    function toggle(i, { deep = false, value = null } = {}) {
      if (i < 0 || i >= S.n || S.size[i] <= 1) return;
      const v = value == null ? !open[i] : !!value;
      setOpen(i, v);
      if (deep && v) for (let q = i + 1; q < i + S.size[i]; q++) setOpen(q, 1);
      relayout(i);
    }
    function setBase(b) {
      mem.reset(b);
      open = baseOpen(b);
      lvSel.value = /^g\d+$/.test(b) ? b : '';
      relayout(focus >= 0 && vis[focus] ? focus : -1);
    }

    /* ---------- 보기 단계 바꾸기 (건의 8의 4-가) ----------
       바꿀 때 기준이 되는 사람(keep — 키보드 초점 · 누른 점, 없으면 at(창 안 좌표 — 커서) · 그것도 없으면 가운데에서 가장 가까운 사람)이 화면에서 제자리에 남습니다 */
    const segBtns = [...el.querySelectorAll('[data-kv-scale]')];
    function nearest(px, py) {
      let best = -1;
      let bd = Infinity;
      for (const r of L.rows || [])
        for (let q = 0; q < r.length; q++) {
          const i = r[q];
          const d = Math.abs(cardX(i) + half() - px) + Math.abs(cardY(i) + sc.h / 2 - py);
          if (d < bd) {
            bd = d;
            best = i;
          }
        }
      return best;
    }
    /** 한눈 보기(점 단계에 세그먼트 · V로 들 때 — 목업 '점' 그림처럼 맨 위부터 한 화면): 판이 창보다 좁으면 가로 가운데, 넓으면 왼쪽 끝부터(세대 번호 칸 다음 틈 12) · 세로는 맨 위 */
    function overview() {
      let lo = Infinity;
      let hi = -Infinity;
      for (const r of L.rows || [])
        if (r.length) {
          lo = Math.min(lo, cardX(r[0]));
          hi = Math.max(hi, cardX(r[r.length - 1]) + sc.w);
        }
      const gut = 24; // 세대 번호 칸(.kv-gens)
      const room = vw() - gut;
      sx = !isFinite(lo) ? 0 : hi - lo + 24 <= room ? lo - gut - (room - (hi - lo)) / 2 : lo - gut - 12;
      sy = 0;
      clampScroll(sx, sy); // 판 밖 가운데 · 왼쪽 틈도 허락
    }
    /** 단계 바꾸기 — fit: 점으로 들 때 한눈 보기(세그먼트 · V). 제자리 유지는 Ctrl+휠(커서 밑 사람) · 점 누르기 · 보통으로 돌아올 때(가운데 사람 · V는 키보드 초점 사람) */
    function setScale(k, { at = null, keep = -1, fit = false } = {}) {
      const next = F_SCALES[Math.max(0, Math.min(F_SCALES.length - 1, k | 0))];
      if (!next || next === sc || !L) return false;
      cancelAnimationFrame(coast);
      stopFly();
      anim = null;
      const pt = at || [vw() / 2, vh() / 2];
      const i = keep >= 0 && vis[keep] ? keep : nearest(pt[0] + sx, pt[1] + sy);
      const before = i >= 0 ? [cardX(i) + half() - sx, cardY(i) + sc.h / 2 - sy] : null;
      sc = next;
      el.classList.toggle('is-dots', !!sc.dots);
      /* 사람 요소는 꼴이 달라 새로 지음(글 · 곁글 · 풍선) — 장식도 비움 */
      for (const c of cards.values()) c.remove();
      cards.clear();
      for (const d of deco.values()) d.remove();
      deco.clear();
      dims();
      if (fit && sc.dots) overview();
      else if (before) {
        sx = cardX(i) + half() - before[0];
        sy = cardY(i) + sc.h / 2 - before[1];
        clampScroll(sx, sy); // 그 사람이 제자리에 남게 — 판 밖으로 조금 나가도 허락
      } else clampScroll();
      for (const b of segBtns) b.setAttribute('aria-checked', String(Number(b.dataset.kvScale) === F_SCALES.indexOf(sc)));
      showTip(-1);
      drawOverview();
      schedule();
      return true;
    }
    /* 풍선: 점 단계의 사람 · 보통 단계의 이름 미상에 올리면 '이름 · 곁글'(먹 바탕 · 종이 글 11.5 · 둥근 4) */
    const tipEl = el.querySelector('.kv-tip');
    let tipAt = -1;
    const tipText = i => (S.bits[i] & B_UNKNOWN ? '이름 미상' : sc.dots ? `${S.names[i] || ''}${S.subs[i] ? ` · ${S.subs[i]}` : ''}` : '');
    function showTip(i) {
      const t = i >= 0 && vis[i] ? tipText(i) : '';
      tipAt = t ? i : -1;
      if (!t) return void (tipEl.hidden = true);
      if (tipEl.textContent !== t) tipEl.textContent = t;
      tipEl.hidden = false;
      placeTip();
    }
    function placeTip() {
      if (tipAt < 0 || tipEl.hidden) return;
      const top = sc.dots ? cardY(tipAt) : cardY(tipAt) + sc.h / 2 - F_RING / 2; // 점 · 원의 위쪽 6px 위
      tipEl.style.transform = `translate(${Math.round(cardX(tipAt) + half() - sx)}px, ${Math.round(top - 6 - sy)}px)`;
    }

    /* ---------- 데려가기 (찾기 · 전체도 · 꼬리표) ---------- */
    let fly = null;
    function flyTo(tx, ty, smooth = true) {
      const W = vw();
      const H = vh();
      const gx = Math.max(0, Math.min(Math.max(0, contentW - W), tx - W / 2));
      const gy = Math.max(0, Math.min(Math.max(0, contentH - H), ty - H / 2));
      cancelAnimationFrame(fly && fly.raf);
      if (!smooth || reduced() || !HT.motion || !HT.motion.Spring) {
        sx = gx;
        sy = gy;
        return schedule();
      }
      const spx = new HT.motion.Spring(sx, { response: MT().move / 1000, restDelta: 0.5 });
      const spy = new HT.motion.Spring(sy, { response: MT().move / 1000, restDelta: 0.5 });
      spx.set(gx);
      spy.set(gy);
      fly = { raf: 0 };
      const step = () => {
        const t = now();
        sx = spx.value(t);
        sy = spy.value(t);
        frame();
        if (!(spx.done(t) && spy.done(t))) fly.raf = requestAnimationFrame(step);
        else {
          sx = gx;
          sy = gy;
          fly = null;
          schedule();
        }
      };
      fly.raf = requestAnimationFrame(step);
    }
    const stopFly = () => {
      if (fly) cancelAnimationFrame(fly.raf);
      fly = null;
    };
    function reveal(i, { smooth = true } = {}) {
      if (i < 0 || i >= S.n) return;
      let changed = false;
      for (let q = S.par[i]; q >= 0; q = S.par[q])
        if (!open[q]) {
          setOpen(q, 1);
          changed = true;
        }
      if (changed) relayout(-1, { animate: false });
      focus = i;
      flyTo(cardX(i) + half(), cardY(i) + sc.h / 2, smooth);
    }
    function focusKey(k, opts) {
      const i = S.indexOf(k);
      if (i >= 0) reveal(i, opts);
      return i >= 0;
    }
    let finds = [];
    let findAt = -1;
    function runFind(next = false) {
      const q = findIn.value.trim().toLowerCase();
      if (!q) return;
      if (!next || !finds.length || finds._q !== q) {
        finds = [];
        for (let i = 0; i < S.n; i++) if (!(S.bits[i] & B_UNKNOWN) && String(S.names[i] || '').toLowerCase().includes(q)) finds.push(i);
        finds._q = q;
        findAt = -1;
      }
      if (!finds.length) return findIn.setAttribute('aria-invalid', 'true');
      findIn.removeAttribute('aria-invalid');
      findAt = (findAt + 1) % finds.length;
      reveal(finds[findAt]);
    }

    /* ---------- 손: 끌기(문턱 5px · 관성 250ms) · 휠 · Shift+휠 ---------- */
    let drag = null;
    let coast = 0;
    let moved = false;
    view.addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      cancelAnimationFrame(coast);
      stopFly();
      drag = { id: e.pointerId, x: e.clientX, y: e.clientY, sx, sy, on: false, samples: [[e.timeStamp, e.clientX, e.clientY]] };
      moved = false;
    });
    view.addEventListener('pointermove', e => {
      if (!drag || e.pointerId !== drag.id) return;
      const dx = e.clientX - drag.x;
      const dy = e.clientY - drag.y;
      if (!drag.on) {
        if (Math.hypot(dx, dy) < 5) return;
        drag.on = true;
        moved = true;
        drag.x = e.clientX;
        drag.y = e.clientY;
        drag.sx = sx;
        drag.sy = sy;
        try {
          view.setPointerCapture(e.pointerId);
        } catch (err) {
          /* 잡지 못해도 끌기는 됨 */
        }
        view.classList.add('is-dragging');
        return;
      }
      const ox = sx;
      const oy = sy;
      sx = drag.sx - (e.clientX - drag.x);
      sy = drag.sy - (e.clientY - drag.y);
      clampScroll(ox, oy);
      drag.samples.push([e.timeStamp, e.clientX, e.clientY]);
      while (drag.samples.length > 2 && e.timeStamp - drag.samples[0][0] > 80) drag.samples.shift();
      schedule();
    });
    const endDrag = e => {
      if (!drag || e.pointerId !== drag.id) return;
      const d = drag;
      drag = null;
      view.classList.remove('is-dragging');
      if (!d.on || reduced()) return;
      const s = d.samples;
      const a = s[0];
      const z = s[s.length - 1];
      const dt = Math.max(1, z[0] - a[0]);
      let vx = -((z[1] - a[1]) / dt) * 1000;
      let vy = -((z[2] - a[2]) / dt) * 1000;
      if (e.timeStamp - z[0] > 60 || Math.hypot(vx, vy) < 50) return;
      let last = performance.now();
      const step = t => {
        const dts = Math.max(0, (t - last) / 1000);
        last = t;
        const k = Math.exp(-dts / 0.25);
        const ox = sx;
        const oy = sy;
        sx += vx * dts;
        sy += vy * dts;
        vx *= k;
        vy *= k;
        const bx = sx;
        const by = sy;
        clampScroll(ox, oy);
        if (bx !== sx) vx = 0;
        if (by !== sy) vy = 0;
        frame();
        if (Math.hypot(vx, vy) > 15) coast = requestAnimationFrame(step);
      };
      coast = requestAnimationFrame(step);
    };
    view.addEventListener('pointerup', endDrag);
    view.addEventListener('pointercancel', endDrag);
    view.addEventListener(
      'wheel',
      e => {
        if (e.ctrlKey) {
          /* Ctrl+휠: 아래로 굴리면 점 · 위로 굴리면 보통 — 커서 밑의 사람이 제자리 (브라우저 확대는 막음) */
          e.preventDefault();
          if (!e.deltaY) return;
          const r = view.getBoundingClientRect();
          return void setScale(F_SCALES.indexOf(sc) + (e.deltaY > 0 ? 1 : -1), { at: [e.clientX - r.left - view.clientLeft, e.clientY - r.top - view.clientTop] });
        }
        e.preventDefault();
        cancelAnimationFrame(coast);
        stopFly();
        const k = e.deltaMode === 1 ? 32 : e.deltaMode === 2 ? vh() : 1;
        const ox = sx;
        const oy = sy;
        if (e.shiftKey && !e.deltaX) sx += e.deltaY * k;
        else {
          sx += e.deltaX * k;
          sy += e.deltaY * k;
        }
        clampScroll(ox, oy);
        schedule();
      },
      { passive: false }
    );

    /* ---------- 누름 ---------- */
    const cardOf = t => {
      const c = t.closest ? t.closest('.kv-p') : null;
      return c && c.dataset.i != null ? Number(c.dataset.i) : -1;
    };
    const actionOf = i => ({ type: 'person', key: S.keys[i], skel: root.id, at: at > 0 ? i + at : i });
    el.addEventListener('click', e => {
      if (moved) {
        moved = false;
        return;
      }
      const t = e.target;
      const seg = t.closest('[data-kv-scale]');
      if (seg) return void setScale(Number(seg.dataset.kvScale), { fit: true });
      const btn = t.closest('[data-kv]');
      if (btn && btn.tagName === 'BUTTON') {
        const a = btn.dataset.kv;
        if (a === 'close') return close();
        if (a === 'all') return setBase('a');
        if (a === 'none') return setBase('n');
        return;
      }
      if (t.closest('[data-kv-up]') && o.onOpen && at > 0) return o.onOpen({ type: 'person', key: root.keys[S.up], skel: root.id, at: S.up });
      const fl = t.closest('[data-kv-fly]');
      if (fl) return reveal(Number(fl.dataset.kvFly));
      const op = t.closest('[data-kv-open]');
      if (op) return toggle(Number(op.dataset.kvOpen), { value: 1, deep: e.altKey });
      const br = t.closest('[data-kv-br]');
      if (br) {
        const i = Number(br.dataset.kvBr);
        const v = !open[i];
        return toggle(i, { value: v, deep: v });
      }
      const i = cardOf(t);
      if (i >= 0 && sc.dots) {
        /* 점을 누르면 보통으로 돌아오며(그 사람이 제자리) 그 사람에게 날아감 */
        setScale(0, { keep: i });
        return reveal(i);
      }
      if (i >= 0) {
        focus = i;
        const c = cards.get(i);
        const r = c ? c.getBoundingClientRect() : null;
        /* 카드 오른쪽 위 ▸ · ▾(16px) 자리는 접고 펴기, 몸통은 그 사람의 창 */
        if (r && !(S.bits[i] & B_UNKNOWN) && (S.size[i] > 1 || S.bits[i] & B_STUB) && e.clientX > r.right - 22 && e.clientY < r.top + 20) return toggle(i, { deep: e.altKey });
        if (o.onOpen) o.onOpen(actionOf(i));
        return schedule();
      }
      if (o.onLink) o.onLink(t, e);
    });
    view.addEventListener('pointerover', e => {
      const i = cardOf(e.target);
      if (i !== tipAt) showTip(i);
    });
    view.addEventListener('pointerleave', () => showTip(-1));
    el.addEventListener('contextmenu', e => {
      e.stopPropagation(); // 창 안의 오른쪽 누르기는 연표의 메뉴로 가지 않음
      const br = e.target.closest('[data-kv-br]');
      if (br && o.onOpen) {
        const i = Number(br.dataset.kvBr);
        const b = S.branches.find(z => z && z.at === (at > 0 ? i + at : i)) || S.branches[S.branch[i]];
        if (b) {
          e.preventDefault();
          return o.onOpen({ type: 'house', id: String(b.uid).replace(/^house:/, '') });
        }
      }
      const i = cardOf(e.target);
      if (i < 0 || !o.onMenu) return;
      e.preventDefault();
      o.onMenu(actionOf(i), e.clientX, e.clientY);
    });
    lvSel.addEventListener('change', () => setBase(lvSel.value || 'd'));
    findIn.addEventListener('keydown', e => {
      if (e.key === 'Enter') {
        e.preventDefault();
        runFind(true);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        view.focus({ preventScroll: true });
      }
    });
    findIn.addEventListener('input', () => {
      finds = [];
      findIn.removeAttribute('aria-invalid');
    });
    /* 전체도: 누르거나 끌면 그리로 */
    const over = el.querySelector('.kv-over');
    let overDrag = false;
    const overGo = (e, smooth) => {
      const r = canvas.getBoundingClientRect();
      const kx = contentW / Math.max(1, r.width);
      const ky = contentH / 56;
      flyTo((e.clientX - r.left) * kx, (e.clientY - r.top) * ky, smooth);
    };
    over.addEventListener('pointerdown', e => {
      overDrag = true;
      try {
        over.setPointerCapture(e.pointerId);
      } catch (err) {
        /* 없음 */
      }
      overGo(e, true);
    });
    over.addEventListener('pointermove', e => overDrag && overGo(e, false));
    over.addEventListener('pointerup', () => (overDrag = false));
    over.addEventListener('pointercancel', () => (overDrag = false));
    /* 창 끌어 옮기기: 머리 줄(단추 · 칩 밖) — 메이커 떠 있는 창과 같은 손잡이 */
    const head = el.querySelector('[data-kv-drag]');
    head.addEventListener('pointerdown', e => {
      if (e.button !== 0 || e.target.closest('button, a, input, select')) return;
      const r0 = el.getBoundingClientRect();
      const sr = stageR();
      const st = { x: e.clientX, y: e.clientY, l: r0.left - sr.left, t: r0.top - sr.top };
      try {
        head.setPointerCapture(e.pointerId);
      } catch (err) {
        /* 없음 */
      }
      const mv = ev => {
        const x = Math.max(120 - el.offsetWidth, Math.min(sr.width - 120, st.l + ev.clientX - st.x));
        const y = Math.max(0, Math.min(sr.height - 48, st.t + ev.clientY - st.y));
        el.style.left = `${Math.round(x)}px`;
        el.style.top = `${Math.round(y)}px`;
      };
      const up = () => {
        head.removeEventListener('pointermove', mv);
        head.removeEventListener('pointerup', up);
        head.removeEventListener('pointercancel', up);
        if (o.store && o.store.set) o.store.set('@win', { x: parseFloat(el.style.left), y: parseFloat(el.style.top) });
      };
      head.addEventListener('pointermove', mv);
      head.addEventListener('pointerup', up);
      head.addEventListener('pointercancel', up);
    });

    /* ---------- 키보드 (4-6) ---------- */
    function sameGen(i, dir) {
      const r = L.rows[S.gen[i]];
      if (!r) return -1;
      let lo = 0;
      let hi = r.length - 1;
      let pos = -1;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (r[mid] === i) {
          pos = mid;
          break;
        }
        if (L.x[r[mid]] < L.x[i] || (L.x[r[mid]] === L.x[i] && r[mid] < i)) lo = mid + 1;
        else hi = mid - 1;
      }
      if (pos < 0) pos = r.indexOf(i);
      const q = pos + dir;
      return q >= 0 && q < r.length ? r[q] : -1;
    }
    function keyGo(i) {
      if (i < 0 || !vis[i]) return;
      focus = i;
      const x = cardX(i);
      const y = cardY(i);
      const W = vw();
      const H = vh();
      if (x < sx + 8 || x + sc.w > sx + W - 8 || y < sy + 8 || y + sc.h > sy + H - 8) flyTo(x + half(), y + sc.h / 2);
      else if (!anim) frame(); // 초점 테두리는 그 자리에서 곧바로
      else schedule();
    }
    view.addEventListener('keydown', e => {
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      const k = e.key;
      const done = () => {
        e.preventDefault();
        e.stopPropagation();
      };
      if (k === 'Escape') return done(), close();
      if (k === 'f' || k === 'F') return done(), findIn.focus();
      if (k === 'v' || k === 'V') return done(), setScale((F_SCALES.indexOf(sc) + 1) % F_SCALES.length, { keep: focus >= 0 && vis[focus] ? focus : -1, fit: true }); // 연표의 조감과 같은 키 — 단계 표의 차례로 돎
      if (focus < 0 || !vis[focus]) {
        const r0 = L.rows[0];
        focus = r0 && r0.length ? r0[0] : -1;
      }
      const i = focus;
      if (i < 0) return;
      if (k === 'ArrowUp') return done(), keyGo(S.par[i]);
      if (k === 'ArrowDown') {
        done();
        if (S.size[i] <= 1) return;
        if (!open[i]) toggle(i, { value: 1 });
        return keyGo(i + 1);
      }
      if (k === 'ArrowLeft' || k === 'ArrowRight') {
        done();
        const dir = k === 'ArrowLeft' ? -1 : 1;
        const p = S.par[i];
        if (p >= 0) {
          const sib = [...kidsOf(S, p)];
          const q = sib.indexOf(i) + dir;
          if (q >= 0 && q < sib.length) return keyGo(sib[q]);
        }
        return keyGo(sameGen(i, dir));
      }
      if (k === ' ' || k === 'Spacebar') return done(), toggle(i);
      if (k === 'Enter') return done(), o.onOpen && o.onOpen(actionOf(i));
      if (k === '*') {
        done();
        const p = S.par[i];
        const sib = p >= 0 ? [...kidsOf(S, p)] : [i];
        for (const c of sib) if (S.size[c] > 1) setOpen(c, 1);
        return relayout(i);
      }
      if (k === 'Home') return done(), keyGo(L.rows[S.gen[i]][0]);
      if (k === 'End') {
        done();
        const r = L.rows[S.gen[i]];
        return keyGo(r[r.length - 1]);
      }
    });
    el.addEventListener('keydown', e => {
      if (e.key === 'Escape' && !e.defaultPrevented && !e.target.closest('input, select')) {
        e.preventDefault();
        e.stopPropagation();
        close();
      }
    });
    const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(() => {
      clampScroll(sx, sy);
      drawOverview();
      schedule();
    }) : null;
    if (ro) ro.observe(view);

    /* ---------- 처음: 큰 뼈대는 '짓고 있습니다'를 띄운 뒤 다음 장면에 ---------- */
    const building = el.querySelector('.kv-building');
    const start = () => {
      layout();
      building.hidden = true;
      clampScroll();
      drawOverview();
      if (o.scroll && Array.isArray(o.scroll)) {
        /* 다시 지은 창(메이커가 모델을 다시 지음): 보던 자리 · 초점 그대로 */
        sx = o.scroll[0];
        sy = o.scroll[1];
        clampScroll();
        if (o.focusKey && S.indexOf(o.focusKey) >= 0) focus = S.indexOf(o.focusKey);
        schedule();
      } else if (o.focusKey && S.indexOf(o.focusKey) >= 0) reveal(S.indexOf(o.focusKey), { smooth: false });
      else {
        /* 처음 자리: 맨 위 가운데(뿌리 카드가 보이게) */
        const r0 = L.rows[0];
        if (r0 && r0.length) {
          const i0 = r0[0];
          sx = Math.max(0, cardX(i0) + half() - vw() / 2);
          clampScroll();
        }
        schedule();
      }
    };
    if (S.n > 20000) {
      building.hidden = false;
      requestAnimationFrame(() => setTimeout(start, 0));
    } else start();

    function close({ quiet = false } = {}) {
      if (!el.isConnected) return;
      cancelAnimationFrame(raf);
      cancelAnimationFrame(coast);
      stopFly();
      if (ro) ro.disconnect();
      el.remove();
      if (famCtl === api) famCtl = null;
      if (!quiet && o.onClose) o.onClose();
    }
    const api = {
      el,
      key: o.key,
      house: o.house || null,
      close,
      focusKey,
      reveal,
      toggle,
      setBase,
      open: i => !!open[i],
      indexOf: k => S.indexOf(k),
      layout: () => L,
      scroll: () => [sx, sy],
      focusedKey: () => (focus >= 0 ? S.keys[focus] : null),
      firstKey: () => (S.n ? S.keys[0] : null),
      cardRect: i => (L && vis[i] ? { x: cardX(i), y: cardY(i), w: sc.w, h: sc.h } : null),
      scale: () => F_SCALES.indexOf(sc),
      setScale: (k, opts) => setScale(k, opts),
      stats: () => ({ n: S.n, cards: cards.size, dom: el.querySelectorAll('*').length + 1, visible: L ? L.rows.reduce((s, r) => s + r.length, 0) : 0 }),
    };
    famCtl = api;
    if (o.focusTree !== false) view.focus({ preventScroll: true, focusVisible: false });
    return api;
  }

  HT.kinView = {
    ready,
    succReady,
    skeleton,
    prepare,
    succPrepare,
    branchRoot,
    succession,
    family,
    legendHTML,
    current: () => famCtl,
    closeFamily: () => famCtl && famCtl.close(),
    bits: { MEMBER: B_MEMBER, UNKNOWN: B_UNKNOWN, MISSING: B_MISSING, SIDE: B_SIDE, FOUNDER: B_FOUNDER, LEADER: B_LEADER, STUB: B_STUB, TWO: B_TWO },
  };
})();

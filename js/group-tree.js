/* 역사 연표 — 단체 계보 창 (HT.groupTreeLayout · HT.groupTree)
 *
 * 설계 D5 결정 4 — 감독 선택 A '아래쪽 넓은 창 · 가로 시간 나무'(docs/설계-10건/7-8-단체와-렌즈.md · docs/설계-10건/감독-선택.md D5).
 * 감독 덧붙임(원문): "집권한 부분에 겉에 아주 얇은 진한 테두리로 살짝 구분." — 막대 안 집권 구간(집권 · 연정 · 실권)에 1px 짙은 테두리.
 * 감독 원칙(결정 2 · 3 덧붙임): 띠 · 창의 구분은 글 딱지가 아니라 테두리 · 모양 · 색으로 — 막대 안에는 이름 · 기간 말고 글을 두지 않습니다.
 *
 * 창: 연표 아래쪽에 붙는 넓은 창(연표 폭 그대로 · 위 모서리만 둥근 20px). 나무의 연도 눈금이 위 연표와 같은 x에 놓여(연표를 밀거나 당기면 나무도 함께 —
 *     연표의 onViewChange마다 다시 그림) 막대가 위 띠의 축소판처럼 세로로 줄을 맞춥니다. 왼쪽(연표의 이름 칸 자리)에 고른 단체와 안내 글.
 *   · 막대 = 단체 하나(있던 기간 — 단체 색 22% · 그 색의 테두리). 안의 짙은 칠 = 집권(실권 칸도), 중간 칠 = 연정 — 둘 다 1px 짙은 테두리(감독 덧붙임).
 *     연정 = 칸 이름이 연정 · 공동 · 연립이거나, 같은 나라에 있던 다른 단체의 집권 칸과 겹친 부분(설계 결정 1 '같은 나라 같은 때 둘 이상이면 연정').
 *   · 이음선(D1 결정 4 B와 같은 말씨): 갈라짐 = 실선 가지 · 합쳐짐 = 모이는 실선 + 네모 · 이름 바꿈 = 다리(두 작은 네모 사이 선 — 같은 줄로 이어 씀) ·
 *     방식 미상 = 2px 점선(둥근 점) + 글 '방식 미상' · 적지 않음 = 옅은 1px 선 · 글 없음.
 *     '방식 미상'은 앞선 단체의 how가 'unknown'일 때(HT.GROUP_HOWS의 '미상' — 메이커의 '이어진 방식'에서 고르거나 '미상' · '모름' · '불명'으로 적음). 비우면 '적지 않음'.
 *   · 막대를 누르면 그 단체를 고름: 위 연표의 그 나라 띠에 집권 구간이 조명되고(timeline.setSpotlight) — 연표에 집권 단(결정 1)이 있으면
 *     timeline.setGroupFocus(uid)로 그 단체의 칸만 진하게 — 왼쪽에 이름 · 기간 · 집권 n번 · 연정 m번과 [단체 창] [이 시기로]. 두 번 누르면 단체 창.
 *     이음선을 누르면 그 일의 사건(뒤 단체의 '맺은 사건' — 없으면 누를 수 없음).
 *   · 열 때 보기: 나무 전체가 보기 밖이면 나무 전체로, 나무는 보이지만 고른 채로 연 단체가 보기 밖이면 그 단체의 기간으로(상세 창이 가리지 않은 부분에).
 *
 * 배치(HT.groupTreeLayout — 화면과 무관한 셈 · 새 앱도 같은 셈을 따르면 같은 나무):
 *   ① 모으기: 그 나라에 있던(within) 단체 + 연 단체 + 그들과 앞선/뒤를 이은 단체로 닿는 모두.
 *   ② 줄: 뿌리(모인 단체 안에 앞선 단체가 없는 것)를 시작 차례로, 각 단체 아래에 그 단체에서 나온 단체를 앞 줄부터(먼저 순회 · pre-order).
 *      한 부모의 아이들은 늦게 시작한 것을 부모 가까이(위)에 — 이음선이 부모 줄에서 아이 줄까지 내려가는 동안 사이 줄의 막대는 모두 그 아이보다 늦게 시작하므로
 *      선이 막대를 가로지르지 않습니다. 이름 바꿈으로 이어지고 기간이 겹치지 않으면 같은 줄에 이어 씀(다리).
 *      합쳐진 단체는 앞선 단체 가운데 가장 아래 줄에 놓인 것 밑에(첫 순회로 줄을 본 뒤 다시 순회).
 *   ③ 고리(앞선 단체가 서로를 가리킴)는 남은 것 가운데 먼저 시작한 단체를 뿌리로 끊습니다.
 *
 * 쓰는 법(js/viewer.js): const tree = HT.groupTree.mount({ timeline, stage, model: () => 모델, openItem(uid), openPolity(uid) });
 *   tree.open({ polityUid, groupUid }) · tree.close() · tree.isOpen() · tree.sync()(연표가 다시 그릴 때) · tree.refresh()(모델이 바뀜) · tree.restoreSpot()
 * timeline.js의 공개 값만 읽습니다(view · W · gutter · bodyEl · _gridX(연도 눈금 자리 — 읽기만) · _laneOf/_laneAbs(그 나라 줄을 창 위로 데려올 때 — 있을 때만)).
 * core.js 뒤 · viewer.js 앞에 읽습니다. 움직임은 토큰만(--t-in 등장 · --t-move 세로 데려오기 · --t-micro 올림 — 되튐 없음). */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});

  /* ---------- 배치 (순수 셈) ---------- */
  /** 집권 칸의 종류: real(실권) · coal(이름이 연정) · power(집권) — 띠 위 단체 단과 같은 낱말 표 · 같은 셈(core.js HT.powerSpanKind · HT.POWER_WORDS) */
  const spanKind = c => HT.powerSpanKind(c.name);
  const KIND_WORD = { power: '집권', coal: '연정', real: '실권' };
  const HOW_KIND = { split: 'split', merge: 'merge', rename: 'rename', unknown: 'unknown' };
  const EPS = 1e-6;

  /** 단체의 집권 덩이 [{ a, b, kind }] — 있던 기간으로 자르고, 다른 단체의 집권(실권 빼고 — other: [시작, 끝] 목록)과 겹친 집권은 연정으로, 맞닿은 같은 종류는 한 덩이로 */
  function powerSegs(g, other) {
    const lo = g.start;
    const hi = g.endY;
    const out = [];
    for (const c of g.powerSpans || []) {
      const a = Math.max(c.start, lo);
      const b = Math.min(c.end, hi);
      if (!(b > a)) continue;
      const kind = spanKind(c);
      if (kind !== 'power' || !other.length) {
        out.push({ a, b, kind });
        continue;
      }
      const cuts = [a, b];
      for (const [x, y] of other) {
        if (x > a && x < b) cuts.push(x);
        if (y > a && y < b) cuts.push(y);
      }
      const pts = [...new Set(cuts)].sort((p, q) => p - q);
      for (let i = 0; i + 1 < pts.length; i++) {
        const m = (pts[i] + pts[i + 1]) / 2;
        out.push({ a: pts[i], b: pts[i + 1], kind: other.some(([x, y]) => x <= m && m <= y) ? 'coal' : 'power' });
      }
    }
    out.sort((p, q) => p.a - q.a || p.b - q.b);
    const merged = [];
    for (const s of out) {
      const l = merged[merged.length - 1];
      if (l && l.kind === s.kind && s.a <= l.b + EPS) l.b = Math.max(l.b, s.b);
      else merged.push(Object.assign({}, s));
    }
    return merged;
  }
  /** 집권 n번 · 연정 m번 · 실권 k번 (덩이 수 — 맞닿은 같은 종류는 한 번) */
  const countText = segs => ['power', 'coal', 'real'].map(k => [k, segs.filter(s => s.kind === k).length]).filter(([, n]) => n).map(([k, n]) => `${KIND_WORD[k]} ${n}번`).join(' · ');

  /** 나무 배치: { nodes: [{ g, row, segs, count, inEdges }], edges: [{ from, to, how, kind, note, same, x }], rows, polity }.
      polityUid — 그 나라에 있던 단체를 모음 · groupUid — 그 단체(와 닿는 단체)를 꼭 넣음 */
  HT.groupTreeLayout = (model, { polityUid = null, groupUid = null } = {}) => {
    const all = (model && model.groups) || [];
    const inPolity = g => (g.withinList || []).some(w => w.polityUid && w.polityUid === polityUid);
    const set = new Set();
    const stack = all.filter(g => (polityUid && inPolity(g)) || (groupUid && g.uid === groupUid));
    while (stack.length) {
      const g = stack.pop();
      if (!g || set.has(g)) continue;
      set.add(g);
      for (const f of g.fromList || []) if (f.group) stack.push(f.group);
      for (const f of g.intoList || []) if (f.group) stack.push(f.group);
    }
    const list = [...set].sort((a, b) => a.start - b.start || b.endY - a.endY || HT.cmp16(String(a.name), String(b.name)));
    const seq = new Map(list.map((g, i) => [g, i]));
    const edges = [];
    const parentsOf = new Map(list.map(g => [g, []]));
    const mergeOf = new Map(); // 앞선 단체 → 그 단체가 합쳐 든 단체의 차례(+1) — 형제 줄을 고를 때 합쳐질 앞선 단체끼리 붙여 둠 (없으면 0)
    for (const g of list)
      (g.fromList || []).forEach((f, i) => {
        if (!f.group || !set.has(f.group) || f.group === g || parentsOf.get(g).some(e => e.from === f.group)) return;
        const e = { from: f.group, to: g, how: f.how || '', note: f.note || '', i };
        edges.push(e);
        parentsOf.get(g).push(e);
      });
    for (const g of list) {
      const ps = parentsOf.get(g);
      if (ps.length > 1) for (const e of ps) if (!mergeOf.has(e.from)) mergeOf.set(e.from, seq.get(g) + 1);
    }
    const mergeKey = g => mergeOf.get(g) || 0;
    /* 한 번 순회: primary(아이 → 그 아이를 매단 이음) */
    const place = primary => {
      const kids = new Map(list.map(g => [g, []]));
      for (const g of list) {
        const e = primary.get(g);
        if (e) kids.get(e.from).push(e);
      }
      /* 이름 바꿈으로 이어 쓰기: 부모가 끝난 뒤에 시작한(겹치지 않는) 이름 바꿈 아이 하나 — 가장 먼저 시작한 것 */
      const cont = new Map();
      for (const g of list) {
        const c = kids.get(g).filter(e => e.how === 'rename' && e.to.start >= g.endY - EPS).sort((a, b) => a.to.start - b.to.start)[0];
        if (c) cont.set(g, c);
      }
      const rowOf = new Map();
      const order = new Map();
      let rows = 0;
      let n = 0;
      const visit = (g, row) => {
        if (rowOf.has(g)) return;
        const lane = [g];
        rowOf.set(g, row);
        order.set(g, n++);
        for (let c = cont.get(g); c && !rowOf.has(c.to); c = cont.get(c.to)) {
          rowOf.set(c.to, row);
          order.set(c.to, n++);
          lane.push(c.to);
        }
        const ch = lane.flatMap(m => kids.get(m).filter(e => cont.get(m) !== e));
        /* 이음선이 내려오는 x(vx: 부모가 끝난 뒤 시작한 아이는 부모의 끝, 부모 안에서 갈라진 아이는 제 시작)가 큰 아이를 부모 가까이(위)에 —
           사이 줄의 막대는 모두 그 x보다 뒤에서 시작하므로 이음선이 막대를 가로지르지 않습니다. 같은 x면 합쳐질 단체의 앞선 단체들을 붙여 뒤에, 그다음 시작 차례 */
        const vx = e => (e.to.start >= e.from.endY - EPS ? e.from.endY : e.to.start);
        ch.sort((a, b) => vx(b) - vx(a) || mergeKey(a.to) - mergeKey(b.to) || a.to.start - b.to.start || b.to.endY - a.to.endY || seq.get(a.to) - seq.get(b.to));
        for (const e of ch) if (!rowOf.has(e.to)) visit(e.to, rows++);
      };
      for (const g of list) if (!primary.get(g)) visit(g, rows++);
      for (const g of list) if (!rowOf.has(g)) visit(g, rows++); // 고리 — 남은 것 가운데 먼저 시작한 단체부터
      return { rowOf, order, rows, cont };
    };
    let primary = new Map(list.map(g => [g, parentsOf.get(g)[0] || null]));
    const first = place(primary);
    primary = new Map(
      list.map(g => {
        const ps = parentsOf.get(g);
        return [g, ps.length < 2 ? ps[0] || null : ps.reduce((a, e) => (first.order.get(e.from) > first.order.get(a.from) ? e : a), ps[0])];
      })
    );
    const { rowOf, rows, cont } = place(primary);
    /* 같은 나라에 있던 단체끼리(연정 셈): 나라마다 그 나라에 있던 단체들의 집권 칸(실권 빼고)을 한 번 모아 둠 */
    const byPolity = new Map();
    const polsOf = new Map();
    for (const g of list) {
      const pols = [...new Set((g.withinList || []).map(w => w.polityUid).filter(Boolean))];
      polsOf.set(g, pols);
      for (const u of pols) {
        if (!byPolity.has(u)) byPolity.set(u, []);
        for (const c of g.powerSpans || []) if (spanKind(c) !== 'real' && c.end > c.start) byPolity.get(u).push([c.start, c.end, g]);
      }
    }
    const nodes = list.map(g => {
      const other = [];
      const seen = new Set();
      for (const u of polsOf.get(g))
        for (const sp of byPolity.get(u)) {
          if (sp[2] === g || seen.has(sp)) continue;
          seen.add(sp);
          other.push(sp);
        }
      const segs = powerSegs(g, other);
      return { g, row: rowOf.get(g), segs, count: countText(segs), inEdges: parentsOf.get(g) };
    });
    for (const e of edges) {
      const merge = parentsOf.get(e.to).length > 1;
      e.same = cont.get(e.from) === e;
      e.kind = merge ? 'merge' : HOW_KIND[e.how] || (e.how ? 'split' : 'blank');
      if (e.kind === 'split' && !e.how) e.kind = 'blank';
      e.ev = e.to.eventItem || null;
    }
    const P = polityUid && model.byUid ? model.byUid.get(polityUid) : null;
    return { nodes, edges, rows, polity: P || null, start: list.length ? Math.min(...list.map(g => g.start)) : 0, end: list.length ? Math.max(...list.map(g => g.endY)) : 0 };
  };

  /* ---------- 창 ---------- */
  const TOP = 6; // 나무 안 첫 줄 위 여백
  const PITCH = 30; // 줄 간격
  const BH = 20; // 막대 높이
  const LINE = 'color-mix(in srgb, var(--text-2) 78%, transparent)';
  const FAINT = 'color-mix(in srgb, var(--text-3) 55%, transparent)';
  const esc = s => (HT.escapeHtml ? HT.escapeHtml(s) : String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]));
  const yr = t => (HT.formatAxisYear ? HT.formatAxisYear(t) : String(Math.round(t)));
  const f1 = v => Math.round(v * 10) / 10;

  /** 선 견본 — 갈라짐 · 합쳐짐 · 이름 바꿈 · 방식 미상 · 적지 않음 + 막대 견본(집권 · 연정 · 있던 기간) */
  function legendIcon(k) {
    if (k === 'split') return '<svg width="24" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M2 7 H8 M8 2 V12 M8 2 H22 M8 12 H22"/></svg>';
    if (k === 'merge') return '<svg width="24" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M2 2 H14 M2 12 H14 M14 2 V12 M14 7 H22"/><rect x="11" y="4" width="6" height="6" rx="1.5" fill="var(--surface)" stroke-width="1.5"/></svg>';
    if (k === 'rename') return '<svg width="26" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="1" y="3" width="6" height="8" rx="2" fill="var(--surface)" stroke-width="1.5"/><path d="M7 7 H19"/><rect x="19" y="3" width="6" height="8" rx="2" fill="var(--surface)" stroke-width="1.5"/></svg>';
    if (k === 'unknown') return '<svg width="24" height="14" fill="none" stroke="currentColor" aria-hidden="true"><path d="M3 7 H22" stroke-width="2" stroke-dasharray="0 4.2" stroke-linecap="round"/></svg>';
    return `<svg width="24" height="14" fill="none" aria-hidden="true"><path d="M2 7.5 H22" stroke="${FAINT}" stroke-width="1"/></svg>`;
  }
  const legendHTML = () =>
    `<div class="gt-legend">${[['split', '갈라짐'], ['merge', '합쳐짐'], ['rename', '이름 바꿈'], ['unknown', '방식 미상'], ['blank', '적지 않음']]
      .map(([k, t]) => `<span>${legendIcon(k)}${t}</span>`)
      .join('')}<span><i class="gt-sw is-power"></i>집권</span><span><i class="gt-sw is-coal"></i>연정</span><span><i class="gt-sw"></i>있던 기간</span></div>`;
  const HINT = '막대를 누르면 위 연표의 그 나라 띠에 그 단체의 집권 기간이 조명됩니다. 이음선을 누르면 그 일(갈라짐 · 합쳐짐 · 이름 바꿈)의 사건. 연표를 밀거나 당기면 나무도 함께 움직입니다.';

  let measureCtx = null;
  const widths = new Map(); // 글 폭 기억 — 연표를 끄는 동안 매 프레임 다시 재지 않게
  /** 글 폭(px) — 막대 안 이름이 들어가는지 (잘린 글자 없이: 이름 + 기간 → 이름 → 첫 글자 → 없음) */
  const textW = (text, size, weight, family) => {
    const key = `${weight}|${size}|${family}|${text}`;
    let w = widths.get(key);
    if (w != null) return w;
    if (!measureCtx) measureCtx = document.createElement('canvas').getContext('2d');
    measureCtx.font = `${weight} ${size}px ${family}`;
    w = measureCtx.measureText(text).width;
    if (widths.size > 4000) widths.clear();
    widths.set(key, w);
    return w;
  };

  HT.groupTree = {
    legendIcon,
    mount({ timeline, stage, model, openItem = () => {}, openPolity = () => {} }) {
      const el = document.createElement('section');
      el.className = 'gtree';
      el.id = 'groupTree';
      el.hidden = true;
      el.setAttribute('aria-label', '단체 계보');
      el.innerHTML = `
        <div class="gt-head"><div class="badges"></div><button class="icon-btn" type="button" data-gt="close" aria-label="닫기">✕</button></div>
        <div class="gt-title"><h2>단체 계보</h2><span class="gt-sub"></span></div>
        ${legendHTML()}
        <div class="gt-main">
          <aside class="gt-side"></aside>
          <div class="gt-plot"><div class="gt-axis" aria-hidden="true"></div><div class="gt-scroll"><svg class="gt-svg" xmlns="http://www.w3.org/2000/svg"></svg></div></div>
        </div>
        <div class="gt-foot"><button class="btn btn-sm" type="button" data-gt="polity">◀ 나라 상세</button><button class="btn btn-sm" type="button" data-gt="close">닫기</button></div>`;
      stage.appendChild(el);
      const $ = s => el.querySelector(s);
      const svg = $('.gt-svg');
      const st = { open: false, polityUid: null, groupUid: null, lay: null, sel: null, key: '', spot: null };

      const plotGeom = () => {
        const sr = el.getBoundingClientRect();
        const br = timeline.bodyEl.getBoundingClientRect();
        const left = br.left + timeline.gutter - sr.left;
        return { left, width: Math.max(60, timeline.W || br.width - timeline.gutter), sr };
      };
      /** 연도 눈금: 연표가 이번에 그은 눈금 자리(_gridX)를 그대로 — 없으면 고른 간격으로 */
      const ticksOf = (start, k, W) => {
        const xs = Array.isArray(timeline._gridX) && timeline._gridX.length ? timeline._gridX : null;
        if (xs) return xs.map(x => ({ x, t: start + x / k }));
        const steps = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000];
        const step = steps.find(s => s * k >= 96) || 5000;
        const out = [];
        for (let t = Math.ceil(start / step) * step; (t - start) * k <= W; t += step) out.push({ x: (t - start) * k, t });
        return out;
      };

      /** 막대 이름: 보이는 부분 안에 들어가는 만큼 — 이름 + 기간 → 이름 → 첫 글자 → 없음 (잘린 글자 · 띠 밖 돌출 없음) */
      let famCache = '';
      const fam = () => famCache || (famCache = getComputedStyle(el).fontFamily || 'sans-serif');
      function label(g, vx1, vx2) {
        const room = vx2 - vx1 - 14;
        const name = String(g.name || '');
        const range = `${yr(g.start)}–${yr(g.endY)}`;
        const f = fam();
        const wn = textW(name, 12, 650, f);
        const wr = textW(range, 10.5, 500, f);
        if (wn + 6 + wr <= room) return { name, range };
        if (wn <= room) return { name, range: '' };
        const c = [...name][0] || '';
        if (c && textW(c, 12, 650, f) <= room) return { name: c, range: '', short: true };
        return null;
      }

      function render(force = false) {
        if (!st.open || !st.lay) return;
        const v = timeline.view;
        const { left, width: W } = plotGeom();
        const key = `${v.start}|${v.end}|${W}|${left}`; // 고른 단체가 바뀌는 것은 다시 그리지 않고 표시만 (select — 두 번 누르기의 대상이 그대로 남게)
        if (!force && key === st.key) return;
        st.key = key;
        const plot = $('.gt-plot');
        plot.style.left = `${f1(left)}px`;
        plot.style.width = `${f1(W)}px`;
        const side = $('.gt-side');
        side.style.width = `${Math.max(0, f1(left - 34))}px`;
        side.hidden = left < 120;
        const k = W / (v.end - v.start);
        const X = t => (t - v.start) * k;
        const lay = st.lay;
        const H = TOP + Math.max(1, lay.rows) * PITCH;
        const cy = r => TOP + r * PITCH + BH / 2;
        /* 연도 눈금 — 글은 위 띠(고정), 세로선은 나무 안 */
        const ticks = ticksOf(v.start, k, W);
        $('.gt-axis').innerHTML = ticks
          .filter(tk => Math.abs(tk.t - Math.round(tk.t)) < 1e-6 && tk.x >= 14 && tk.x <= W - 14)
          .map(tk => `<span style="left:${f1(tk.x)}px">${esc(yr(Math.round(tk.t)))}</span>`)
          .join('');
        let s = ticks.map(tk => `<line class="gt-gl" x1="${f1(tk.x)}" y1="0" x2="${f1(tk.x)}" y2="${H}"/>`).join('');
        /* 막대 자리 (이음선이 닿는 머리는 5px 들여 선이 보이게, 이름 바꿈 다리는 4px씩 비움) */
        const geo = new Map();
        const into = new Map(lay.nodes.map(n => [n.g, []]));
        for (const e of lay.edges) into.get(e.from).push(e);
        for (const n of lay.nodes) {
          const g = n.g;
          let x1 = X(g.start);
          let x2 = X(g.endY);
          if (n.inEdges.some(e => e.same)) x1 += 4;
          else if (n.inEdges.length) x1 += 5;
          if (into.get(g).some(e => e.same)) x2 -= 4;
          else if (into.get(g).some(e => !e.same && X(e.to.start) >= x2 - 1)) x2 -= 3; // 끝에서 아이가 나오면 줄기가 보이게 3px 비움
          if (x2 - x1 < 2) x2 = x1 + 2;
          geo.set(g, { x1, x2, y: cy(n.row) - BH / 2, cy: cy(n.row), row: n.row });
        }
        /* 보이는 자리만 그림: 나무 안 세로 밀기로 보이는 줄(위아래 여섯 줄 여유) · 연표 폭(좌우 40px 여유) — 단체가 많아도 한 번 그리기가 가볍게 */
        const sc = $('.gt-scroll');
        const r0 = Math.floor((sc.scrollTop - TOP) / PITCH) - 6;
        const r1 = Math.ceil((sc.scrollTop + (sc.clientHeight || 400)) / PITCH) + 6;
        const rowsIn = (ra, rb) => Math.max(ra, rb) >= r0 && Math.min(ra, rb) <= r1;
        const xsIn = (xa, xb) => Math.max(xa, xb) >= -40 && Math.min(xa, xb) <= W + 40;
        /* 이음선 (막대 아래에 먼저) */
        const lines = [];
        const hits = [];
        const labels = [];
        const style = kind => (kind === 'blank' ? `stroke="${FAINT}" stroke-width="1"` : kind === 'unknown' ? `stroke="${LINE}" stroke-width="2" stroke-dasharray="0 4.2" stroke-linecap="round"` : `stroke="${LINE}" stroke-width="2"`);
        const shift = new Map(); // 한 부모에서 같은 x로 다른 꼴의 선이 둘 이상이면 뒤의 꼴을 6px 오른쪽으로 (선이 포개져 꼴이 섞이지 않게)
        for (const e of lay.edges) {
          if (e.same || e.kind === 'merge') continue;
          const k2 = `${e.from.uid}|${Math.round(X(e.to.start >= e.from.endY - EPS ? e.from.endY : e.to.start))}`;
          const seen = shift.get(k2) || [];
          if (!seen.includes(e.kind)) seen.push(e.kind);
          shift.set(k2, seen);
          e._dx = seen.indexOf(e.kind) * 6;
        }
        const tip = e => {
          const word = { split: '갈라짐', merge: '합쳐짐', rename: '이름 바꿈', unknown: '방식 미상', blank: '방식을 적지 않음' }[e.kind];
          return `${word} — ${e.from.name} → ${e.to.name} · ${yr(e.to.start)}${e.note ? ` · ${e.note}` : ''}${e.ev ? ' · 누르면 그 사건' : ''}`;
        };
        const mergeDone = new Set();
        for (const e of lay.edges) {
          const a = geo.get(e.from);
          const b = geo.get(e.to);
          if (!a || !b || !rowsIn(a.row, b.row) || !xsIn(Math.min(a.x2, X(e.to.start)), b.x1)) continue;
          if (e.same) {
            /* 이름 바꿈 — 같은 줄: 앞 막대 끝과 뒤 막대 머리 사이 다리 */
            const xa = a.x2;
            const xb = b.x1;
            const d = `M${f1(xa + 3)} ${f1(b.cy)} H${f1(Math.max(xa + 3, xb - 3))}`;
            lines.push(`<path d="${d}" ${style('split')} fill="none"/><rect class="gt-knot" x="${f1(xa - 2)}" y="${f1(b.cy - 4)}" width="5" height="8" rx="1.5"/><rect class="gt-knot" x="${f1(xb - 3)}" y="${f1(b.cy - 4)}" width="5" height="8" rx="1.5"/>`);
            hits.push({ e, d: `M${f1(xa - 2)} ${f1(b.cy)} H${f1(xb + 2)}` });
            continue;
          }
          /* 세로 줄기의 x: 합쳐짐은 모이는 자리(뒤 단체의 머리), 부모가 끝난 뒤 시작한 아이는 부모의 끝(거기서 아이 줄을 따라 머리까지), 부모 안에서 갈라진 아이는 제 시작 */
          const after = e.kind !== 'merge' && e.to.start >= e.from.endY - EPS;
          const x = Math.max(X(after ? e.from.endY : e.to.start), a.x1 + 2) + (e._dx || 0);
          const down = b.row > a.row;
          const inside = x > a.x1 + 2 && x < a.x2 - 2;
          const y0 = inside ? (down ? a.y + BH : a.y) : a.cy;
          let d = '';
          if (!inside && x > a.x2 + 0.5) d += `M${f1(a.x2)} ${f1(a.cy)} H${f1(x)} `;
          d += `M${f1(x)} ${f1(y0)} V${f1(b.cy)}`;
          if (e.kind === 'merge') {
            lines.push(`<path d="${d}" ${style('split')} fill="none"/>`);
            hits.push({ e, d });
            if (!mergeDone.has(e.to)) {
              mergeDone.add(e.to);
              lines.push(`<path d="M${f1(x)} ${f1(b.cy)} H${f1(b.x1)}" ${style('split')} fill="none"/>`);
              labels.push(`<rect class="gt-knot" x="${f1(x - 4)}" y="${f1(b.cy - 4)}" width="8" height="8" rx="1.5"/>`); // 모이는 자리의 네모 (선 위에)
            }
            continue;
          }
          d += ` H${f1(b.x1)}`;
          lines.push(`<path d="${d}" ${style(e.kind === 'rename' ? 'split' : e.kind)} fill="none"/>`);
          if (e.kind === 'rename') labels.push(`<rect class="gt-knot" x="${f1(b.x1 - 6)}" y="${f1(b.cy - 4)}" width="5" height="8" rx="1.5"/>`);
          hits.push({ e, d });
          if (e.kind === 'unknown') {
            /* '방식 미상' 글 — 아이 줄의 선 왼쪽에(그 줄은 아이 막대부터 시작하므로 비어 있음). 보이는 곳에 들어갈 때만 */
            const w = textW('방식 미상', 11, 600, fam());
            const tx = x - 8;
            if (tx - w >= 2) labels.push(`<text class="gt-how" x="${f1(tx)}" y="${f1(b.cy + 4)}" text-anchor="end">방식 미상</text>`);
          }
        }
        s += `<g class="gt-lines">${lines.join('')}</g>`;
        /* 막대 */
        const sel = st.sel;
        let bars = '';
        for (const n of lay.nodes) {
          const g = n.g;
          const { x1, x2, y } = geo.get(g);
          if (!rowsIn(n.row, n.row) || !xsIn(x1, x2)) continue;
          const vx1 = Math.max(x1, 0);
          const vx2 = Math.min(x2, W);
          const c = g.color;
          const here = sel === g;
          if (!n.tip) n.tip = esc(`${g.name}${g.typeName ? ` · ${g.typeName}` : ''} · ${HT.formatRange ? HT.formatRange(g) : `${yr(g.start)}–${yr(g.endY)}`}${n.count ? ` · ${n.count}` : ''} — 누르면 연표에 조명 · 두 번 누르면 단체 창`);
          let b = `<g class="gt-bar${here ? ' is-here' : ''}" data-uid="${esc(g.uid)}" role="button" tabindex="0" aria-label="${n.tip}" style="--c:${c}"><title>${n.tip}</title>`;
          b += `<rect class="gt-base" x="${f1(x1)}" y="${f1(y)}" width="${f1(x2 - x1)}" height="${BH}" rx="7"/>`;
          for (const sg of n.segs) {
            const a = Math.max(X(sg.a), x1) + 0.5;
            const z = Math.min(X(sg.b), x2) - 0.5;
            if (z - a < 1) continue;
            b += `<rect class="gt-seg is-${sg.kind}" x="${f1(a)}" y="${f1(y + 0.5)}" width="${f1(z - a)}" height="${BH - 1}" rx="6"/>`;
          }
          if (vx2 - vx1 > 4) {
            const lb = label(g, vx1, vx2);
            if (lb) b += `<text class="gt-name" x="${f1(vx1 + 8)}" y="${f1(y + 14)}">${esc(lb.name)}${lb.range ? `<tspan class="gt-yr" dx="6">${esc(lb.range)}</tspan>` : ''}</text>`;
          }
          bars += `${b}</g>`;
        }
        s += bars + labels.join('');
        /* 누르는 자리(투명한 굵은 선) — 사건이 있는 이음만 */
        s += hits.filter(h => h.e.ev).map(h => `<path class="gt-hit" d="${h.d}" data-ev="${esc(h.e.ev.uid)}"><title>${esc(tip(h.e))}</title></path>`).join('');
        svg.setAttribute('width', f1(W));
        svg.setAttribute('height', H);
        svg.setAttribute('viewBox', `0 0 ${f1(W)} ${H}`);
        svg.innerHTML = s;
      }

      function sideHTML() {
        const g = st.sel;
        if (!g) return `<p class="gt-hint">${esc(HINT)}</p>`;
        const n = st.lay.nodes.find(q => q.g === g);
        return `<p class="gt-pick"><b>${esc(g.name)}</b> <small>— 연표에 조명 중</small></p><p class="gt-when">${esc(HT.formatRange ? HT.formatRange(g) : `${yr(g.start)}–${yr(g.endY)}`)}${n && n.count ? `<br>${esc(n.count)}` : ''}</p><div class="gt-acts"><button class="btn btn-sm" type="button" data-gt="item">단체 창</button><button class="btn btn-sm" type="button" data-gt="focus">이 시기로</button></div><p class="gt-hint">${esc(HINT)}</p>`;
      }
      function head() {
        const P = st.lay.polity;
        $('.badges').innerHTML = `${P ? `<button type="button" class="badge is-link" style="--c:${P.color}" data-gt="polity" title="${esc(`${P.name} 상세`)}">${esc(P.name)}</button>` : ''}<span class="badge is-kind">단체 계보</span>`;
        $('.gt-sub').textContent = [P ? P.name : '', `단체 ${st.lay.nodes.length}`, '연도 눈금은 연표와 같은 자리'].filter(Boolean).join(' · ');
        $('.gt-foot [data-gt="polity"]').hidden = !P;
      }

      /** 고른 단체의 조명: 있던 나라 띠마다 집권 덩이(없으면 있던 기간) */
      function spotsOf(g) {
        const n = st.lay && st.lay.nodes.find(q => q.g === g);
        const rows = (g.withinList || []).filter(w => w.polityUid);
        const out = [];
        for (const w of rows) {
          const lo = w.start != null ? w.start : g.start;
          const hi = w.end != null ? w.end : g.endY;
          const segs = n && n.segs.length ? n.segs : [{ a: g.start, b: g.endY }];
          for (const sg of segs) {
            const a = Math.max(sg.a, lo);
            const b = Math.min(sg.b, hi);
            if (b > a) out.push({ uid: timeline.shownBandOf ? timeline.shownBandOf(w.polityUid) || w.polityUid : w.polityUid, start: a, end: b, group: g.uid });
          }
        }
        return out;
      }
      function applySpot() {
        const g = st.sel;
        st.spot = g ? spotsOf(g) : null;
        timeline.setSpotlight(st.spot && st.spot.length ? st.spot : null);
        if (typeof timeline.setGroupFocus === 'function') timeline.setGroupFocus(g ? g.uid : null); // 집권 단(설계 결정 1 — js/timeline.js)이 있으면 그 단체의 칸만 진하게
      }
      function select(g) {
        st.sel = g || null;
        st.groupUid = g ? g.uid : null;
        $('.gt-side').innerHTML = sideHTML();
        applySpot();
        if (!st.key) return render(true);
        for (const b of svg.querySelectorAll('.gt-bar')) b.classList.toggle('is-here', !!g && b.dataset.uid === g.uid);
      }

      /** 그 나라 띠를 연표의 보이는 자리(창 위쪽 — css가 연표를 창 위까지만 줄임)로 데려옵니다: 연표의 세로 닻(setAnchor reveal — 이미 보이면 1px도 안 움직이고,
          가려졌으면 최소 거리를 되튐 없는 스프링으로). 다른 창이 다른 줄을 닻으로 잡고 있으면 그 닻을 뺏지 않습니다. 창이 잡은 닻은 닫을 때 놓습니다 */
      function revealBand(uid) {
        if (!uid) return;
        const cur = timeline.anchorUid || null;
        if (cur && cur !== uid) return;
        st.anchored = !cur;
        timeline.setAnchor(uid, { reveal: true });
      }

      /** 그 단체의 기간이 넉넉히 들어오는 보기 [시작, 끝] — 앞뒤로 15%(적어도 2년). '이 시기로' · 고른 채로 열 때 */
      const periodView = g => {
        const pad = Math.max(2, (g.endY - g.start) * 0.15);
        return [g.start - pad, g.endY + pad];
      };

      function syncStage() {
        stage.classList.toggle('has-gtree', st.open);
        if (st.open) stage.style.setProperty('--gt-h', `${el.offsetHeight}px`);
        else stage.style.removeProperty('--gt-h');
      }

      const api = {
        el,
        isOpen: () => st.open,
        state: st,
        /** 창을 엽니다 — polityUid(그 나라의 단체들) · groupUid(그 단체를 고른 채로) */
        open({ polityUid = null, groupUid = null } = {}) {
          const m = model();
          const g = groupUid ? m.byUid.get(groupUid) : null;
          if (!polityUid && g) polityUid = g.polityUid || null;
          const lay = HT.groupTreeLayout(m, { polityUid, groupUid });
          if (!lay.nodes.length) return false;
          const wasOpen = st.open;
          Object.assign(st, { open: true, polityUid, lay, key: '' });
          el.hidden = false;
          if (!wasOpen) {
            el.classList.remove('is-in');
            void el.offsetWidth;
            el.classList.add('is-in');
          }
          syncStage();
          head();
          const pick = g && lay.nodes.some(n => n.g === g) ? g : null;
          /* 나무가 연표의 보기 범위와 하나도 겹치지 않으면 나무 전체가 들어오게. 나무는 보이지만 고른 단체가 보기 밖이면 그 단체의 기간으로
             ('이 시기로'와 같은 틀을 상세 창이 가리지 않은 부분에 — 고른 단체의 막대와 위 연표의 조명이 보이게 · 조금이라도 보이면 그대로) */
          const v = timeline.view;
          const seen = q => q.endY > v.start && q.start < v.end;
          if (!lay.nodes.some(n => seen(n.g))) {
            const pad = Math.max(2, (lay.end - lay.start) * 0.06);
            timeline.setView(lay.start - pad, lay.end + pad, { animate: true });
          } else if (pick && !seen(pick)) {
            const [s, e] = periodView(pick);
            timeline.setView(s, e, { animate: true, inset: true });
          }
          select(pick);
          if (polityUid) requestAnimationFrame(() => revealBand(polityUid));
          return true;
        },
        close() {
          if (!st.open) return;
          st.open = false;
          st.sel = null;
          el.hidden = true;
          syncStage();
          const mine = timeline.spots || [];
          if (st.spot && st.spot.length && mine.length && mine.every(s => st.spot.includes(s))) timeline.setSpotlight(null); // 이 창이 켠 조명만 걷음 (그사이 다른 창이 켠 조명은 그대로)
          st.spot = null;
          if (st.anchored && timeline.anchorUid === st.polityUid) timeline.setAnchor(null); // 이 창이 잡은 세로 닻만 놓음 (상세 창이 잡은 닻은 그대로)
          st.anchored = false;
          if (typeof timeline.setGroupFocus === 'function') timeline.setGroupFocus(null);
        },
        /** 연표가 다시 그렸을 때(보기 · 폭이 바뀜) */
        sync() {
          if (st.open) render();
        },
        /** 모델이 바뀌었을 때 — 같은 나라 · 같은 단체로 다시 (없어졌으면 닫음) */
        refresh() {
          if (!st.open) return;
          const m = model();
          const keep = st.sel ? st.sel.uid : null;
          const lay = HT.groupTreeLayout(m, { polityUid: st.polityUid, groupUid: keep });
          if (!lay.nodes.length) return api.close();
          st.lay = lay;
          st.key = '';
          head();
          const g = keep ? m.byUid.get(keep) : null;
          st.sel = null;
          select(g && lay.nodes.some(n => n.g === g) ? g : null);
        },
        /** 다른 창이 연표의 조명을 지운 뒤 — 고른 단체의 조명을 다시 */
        restoreSpot() {
          if (st.open && st.sel && !(timeline.spots && timeline.spots.length)) applySpot();
        },
        layout: () => st.lay,
      };

      el.addEventListener('click', e => {
        const b = e.target.closest('[data-gt]');
        if (b) {
          const act = b.dataset.gt;
          if (act === 'close') return api.close();
          if (act === 'polity' && st.lay.polity) return openPolity(st.lay.polity.uid);
          if (act === 'item' && st.sel) return openItem(st.sel.uid);
          if (act === 'focus' && st.sel) {
            const [s, e] = periodView(st.sel);
            return timeline.setView(s, e, { animate: true });
          }
          return;
        }
        const hit = e.target.closest('.gt-hit[data-ev]');
        if (hit) return openItem(hit.dataset.ev);
        const bar = e.target.closest('.gt-bar');
        if (bar) {
          const g = model().byUid.get(bar.dataset.uid);
          if (g) select(g);
        }
      });
      let scrollRaf = 0;
      $('.gt-scroll').addEventListener(
        'scroll',
        () => {
          if (scrollRaf) return;
          scrollRaf = requestAnimationFrame(() => {
            scrollRaf = 0;
            if (st.open && st.lay && st.lay.rows * PITCH > $('.gt-scroll').clientHeight) render(true); // 나무 안 세로 밀기 — 새로 보이는 줄을 그림
          });
        },
        { passive: true }
      );
      el.addEventListener('dblclick', e => {
        const bar = e.target.closest('.gt-bar');
        if (bar) openItem(bar.dataset.uid);
      });
      el.addEventListener('keydown', e => {
        const bar = e.target.closest && e.target.closest('.gt-bar');
        if (!bar || (e.key !== 'Enter' && e.key !== ' ')) return;
        e.preventDefault();
        const g = model().byUid.get(bar.dataset.uid);
        if (!g) return;
        if (st.sel === g) openItem(g.uid);
        else {
          select(g);
          const again = el.querySelector(`.gt-bar[data-uid="${CSS.escape(g.uid)}"]`);
          if (again) again.focus();
        }
      });
      /* Esc의 차례(한 번에 하나씩, 위에 떠 있는 것부터): 차림표(⋯ · 렌즈) · 노선도 · 묶음 카드 → 상세 창 → 이 창 → 렌즈 끔(js/lens-ui.js) → 집중 모드 끔.
         렌즈의 듣개가 잡는 단계(capture)에서 먼저 듣으므로 이 창도 잡는 단계에서 — 이 파일이 먼저 읽혀 먼저 등록되어 렌즈보다 앞에 섭니다.
         위에 무엇이 떠 있으면(차림표 · 상세 창 …) 그쪽 듣개에 맡기고 아무것도 하지 않습니다 */
      document.addEventListener(
        'keydown',
        e => {
          if (e.key !== 'Escape' || e.defaultPrevented || !st.open || e.isComposing) return;
          if (document.querySelector('dialog[open], .ctx-menu:not([hidden]), .tl-metro:not([hidden]), .tl-card:not([hidden])')) return;
          const a = document.activeElement;
          if (a && (/INPUT|TEXTAREA|SELECT/.test(a.tagName) || a.isContentEditable || (a.closest && a.closest('#editPane, .mk-win, .fp-win, #mkProps, #mkStart')))) return;
          const detail = document.getElementById('detail');
          if (detail && !detail.hidden) return;
          e.preventDefault();
          e.stopImmediatePropagation();
          api.close();
        },
        true
      );
      /* 창 크기가 바뀌면 높이를 연표 쪽 자리(상세 창 · 확대 단추가 피할 자리)에 다시 알림 */
      if (typeof ResizeObserver === 'function') new ResizeObserver(() => st.open && syncStage()).observe(el);
      return api;
    },
  };
})();

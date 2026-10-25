// 상세 창이 읽는 항목 기록(계약 1절의 entities · 4절 · 6-9절). 모델의 시대(정권) · 사건 · 인물 · 시대 구분 · 대범위 · 기관 · 문화 · 왕조 · 가문을 {uid, kind, json}으로.
// 형식 3(설계 docs/설계-10건/A-아카이브-이음.md · 계약 초안 6-9 다 = 그 문서 부록 가-6)의 새 기록도 같은 길로 싣는다:
// 단체(group) · 제도(institution) · 지명(place:) · 성씨(surname:) · 주제 사전(themes 하나) · 모아 보기 판(view:) · 지도(map: — 그림 뺌) · 글꼴(font: — 바이트 뺌).
// 모든 기록에 `pack`(이 배치의 packs[] 순번 — 자료집 귀속)을 단다. 엔진은 전부터 entities[].pack을 읽는다(legacy.rs pack_at).
// 모델 객체는 서로를 가리키므로(p.successors[].to · f.services[].polity · e.children[] …) 안전한 직렬화기를 쓴다:
// 뿌리가 아닌 곳에서 uid를 가진 객체를 만나면 {"$ref": uid, "name": 이름}으로 바꾸고, '_'로 시작하는 배치용 값 · 함수 · 순환은 뺀다.
//
// 그 $ref만으로는 상세 창이 목록 한 줄도 그릴 수 없다(연도 글 · 색 · 종류가 빠진다). 새 엔진은 모델을 다 올리지 않으므로,
// 지금 연표의 상세 창(js/viewer.js의 openDetail과 그 아래 함수들)이 state.model.byUid를 넘나들며 즉석에서 찾던 것을 넣을 때 미리 풀어 둔다(명세 06의 9절 ㈎).
// 미리 푼 값은 모두 x_로 시작한다(지금의 값은 그대로 둔다 — 더하기만). 값의 표는 계약 6-9절.
//   · x_의 시간(span · at · 경계)은 계약 4절의 약속대로 **정수 분**이다(json 본문의 옛 값은 모델의 해 좌표 그대로).
//   · x_의 색은 json 본문과 같은 css 글자('#a0bcc5')다.
//   · 검색의 찾을 글은 `x_find`(지금 연표 runSearch의 찾을 글에서 이름 · 제목 · 설명을 뺀 것 — 엔진이 이름 표 hay · 사건 덧줄로 편다).
//     웹 몫 W0(`HT.searchHay`)이 아직 없어 js/viewer.js runSearch의 식을 여기에 옮겨 쓴다(findOf) — 웹이 식을 바꾸면 웹 대조(A1-f · g)가 잡는다.
// 내보내기 모듈은 node: 가져오기를 쓰지 않는다(메이커의 브라우저 일꾼에서도 돈다 — B5).
import { minute, runScript } from './base.mjs';
import { kinCollect } from './kin.mjs';

const DEPTH = 14; // 더 깊이 파고들지 않는다(자료가 깊어도 상세 창이 읽는 만큼은 이 안에 든다)
const MEMBER_FIGURES = 200; // 가문 창 구성원 목록에 싣는 띠 인물 수(넘으면 x_memberCount — 나머지는 세계표에서)

/** 사람 자리(모델의 personIndex 노드 — 형식 3 사람 잇기)인가. uid가 없고 부모 · 자식 · 칸으로 서로를 가리켜 펴면 끝없이 커지므로 이름만 남긴다. */
const isPersonNode = v => typeof v.key === 'string' && Array.isArray(v.cells) && Array.isArray(v.parents) && Array.isArray(v.children);

/** 모델 항목 하나를 상세 창이 읽을 수 있는 꼴로. 뿌리만 통째로 풀고, 안쪽의 다른 항목은 가리키는 표(＄ref)로 남긴다.
    refs(Set)를 주면 만든 $ref의 uid를 모은다(끝의 점검 — 가리킨 곳마다 기록이 있어야 한다). */
export function plain(root, refs = null) {
  const stack = new Set();
  const walk = (v, depth, atRoot) => {
    if (v === undefined || v === null) return null;
    const t = typeof v;
    if (t === 'number') return Number.isFinite(v) ? v : null;
    if (t === 'string' || t === 'boolean') return v;
    if (t !== 'object') return null; // 함수 · 심볼
    if (Array.isArray(v)) return depth >= DEPTH ? [] : v.map(x => walk(x, depth + 1, false));
    if (v instanceof Date) return v.toISOString();
    if (v instanceof Map || v instanceof Set || ArrayBuffer.isView(v)) return null;
    if (!atRoot && typeof v.uid === 'string' && v.uid) {
      if (refs) refs.add(v.uid);
      return { $ref: v.uid, name: v.name || v.title || '' };
    }
    if (!atRoot && isPersonNode(v)) return { name: v.name || '' }; // 사람 자리 — 풀어 둔 값은 x_people · x_persons · x_person에
    if (stack.has(v) || depth >= DEPTH) return null; // 순환 · 너무 깊은 곳
    stack.add(v);
    const o = {};
    for (const k of Object.keys(v)) {
      if (k.startsWith('_')) continue; // 배치용 값(_row · _place · _dep …)은 자료가 아니다
      const val = v[k];
      if (val === undefined || typeof val === 'function') continue;
      o[k] = walk(val, depth + 1, false);
    }
    stack.delete(v);
    return o;
  };
  return walk(root, 0, true);
}

/** 해 좌표 → 정수 분(빈 값은 null). */
const M = t => (t == null || !Number.isFinite(t) ? null : minute(t));
/** 구간 [a, b] → [분, 분] (뒤집히면 앞쪽으로 맞춤). 시작이 없으면 null. */
const spanOf = (a, b) => {
  const lo = M(a);
  if (lo == null) return null;
  const hi = M(b);
  return [lo, hi == null ? lo : Math.max(lo, hi)];
};
/** 빈 것(없음 · 빈 배열 · 빈 객체)은 싣지 않는다 — 기록이 부풀지 않게. */
const some = v => (v == null || (Array.isArray(v) && !v.length) || (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length) ? null : v);

/** 지금 연표의 날짜 글(js/viewer.js 40~74줄)을 그대로 — 목록 한 줄의 연도 글이 창과 같아야 한다. */
function textOf(HT) {
  const whenText = (t, at) => {
    if (t == null || !Number.isFinite(t)) return '';
    if ((at && HT.atFits(at, t)) || Number.isInteger(t)) return HT.formatDate(t, at);
    return HT.cal.formatT(t, 'd');
  };
  const endText = t => (Math.abs(t - HT.NOW_T) < 1e-9 ? '현재' : whenText(t));
  const endWhen = x => (x.ongoing ? '현재' : HT.formatWhen(x, x.end != null ? 'end' : 'start'));
  /** 칸의 기간 글 — 끝을 비운 칸은 풀어 둔 끝으로, 칸의 미정은 '미정', 진행 중인 정권의 끝까지면 '현재'. */
  const cellWhen = (c, useEndY, p) =>
    HT.formatRange({
      start: c.start, startAt: c.startAt, end: useEndY ? c.endY : c.end, endAt: useEndY ? c.endYAt : c.endAt,
      startUnknown: c.startUnknown, endUnknown: c.endUnknown || (useEndY && c.endYAuto), ongoing: HT.cellToNow(c, p),
    });
  /** 활동 기록 한 줄의 기간 글(인물 창). */
  const serviceWhen = (f, s) => `${s.fromUnknown ? '미정' : whenText(s.from, s.fromAt)} ~ ${f.ongoing && s.to === f.endY ? '현재' : s.toUnknown ? '미정' : whenText(s.to, s.toAt)}`;
  /** 시작 · 끝을 적은 것(이름의 쓴 기간 · 배우자의 함께한 기간)의 글 — js/viewer.js nameWhen · spanSmall과 같은 글. 아무것도 없으면 ''. */
  const sideSpan = s =>
    s.start != null || s.end != null || s.startUnknown || s.endUnknown
      ? `${s.startUnknown ? '미정' : s.start != null ? whenText(s.start, s.startAt) : ''} ~ ${s.endUnknown ? '미정' : s.end != null ? whenText(s.end, s.endAt) : ''}`.trim()
      : '';
  /** 기간 글(js/viewer.js spanText) — 단체의 있던 나라 · 제도의 같은 갈래. */
  const spanText = r => HT.formatRange({ start: r.start, startAt: r.startAt, end: r.end, endAt: r.endAt, startUnknown: r.startUnknown, endUnknown: r.endUnknown });
  return { whenText, endText, endWhen, cellWhen, serviceWhen, sideSpan, spanText };
}

/** 목록 한 줄에 쓰는 가장 작은 꼴 — uid · 이름 · 색 · 연도 글. */
const brief = (HT, p, extra) => (p ? Object.assign({ uid: p.uid, name: p.name || p.title || '', color: p.color || '', when: HT.formatRange(p) }, extra) : null);

/** 상세 창이 모델을 넘나들며 찾던 것을 미리 푼다 → Map(uid → { x_… }). */
function crossRefs(ctx, kin, docBodies) {
  const { model, HT } = ctx;
  const T = textOf(HT);
  const ex = new Map();
  const put = (x, key, value) => {
    const v = some(value);
    if (v == null || !x || !x.uid) return;
    let o = ex.get(x.uid);
    if (!o) ex.set(x.uid, (o = {}));
    o[key] = v;
  };
  const periods = model.periods || [];
  const figures = model.figures || [];
  const byUid = model.byUid;

  /* ---------- 승계 상대(양쪽 · 종류 · 세기 · 합류 해) — js/viewer.js:822 successionHTML ---------- */
  const edgeOf = (e, other) => {
    const o = brief(HT, other, { type: e.type || 'indirect' });
    if (!o) return null;
    if (e.type === 'partial') {
      o.degree = e.degree == null ? HT.SUCC_DEGREE_DEFAULT : e.degree; // 정도(1 약 · 2 중 · 3 강) — 선에는 그리지 않고 상세 창의 이름 뒤 글 '정도 중'으로
      o.degreeName = HT.succDegreeName(o.degree);
      if ((e.parts || []).length) o.parts = e.parts.map(HT.succPartName); // 이어진 것(지배층 · 백성 …)
    }
    if (HT.succAbsorbs(e.from, e.to)) {
      o.join = HT.formatYear(e.from.endY); // 흡수(합류) — 이름 뒤 옅은 글 '· n년 합류'
      o.joinAt = M(e.from.endY);
    }
    if (e.note) o.note = e.note;
    return o;
  };

  /* ---------- 소속 상대(양쪽 · 관계 · 기간) — js/viewer.js:847 partOfHTML ---------- */
  const hostRow = (x, h) => {
    const o = brief(HT, h.host, { kind: HT.kindName(h.host.polityKind) });
    if (!o) return null;
    o.when = h.start != null || h.end != null || h.startUnknown || h.endUnknown
      ? `${h.startUnknown ? '미정' : h.start != null ? T.whenText(h.start, h.startAt) : HT.formatWhen(x, 'start')} ~ ${h.endUnknown ? '미정' : h.end != null ? T.whenText(h.end, h.endAt) : T.endWhen(x)}`
      : '전 기간';
    o.span = spanOf(h.start != null ? h.start : x.start, h.end != null ? h.end : x.endY);
    if (h.relation) o.rel = HT.relationName(h.relation);
    if (h.note) o.note = h.note;
    if (h.host.peopleId) Object.assign(o, { peopleId: h.host.peopleId, people: h.host.peopleName || '' }); // 상위 띠 아래 놓인 나라의 민족 한마디
    return o;
  };
  const memberRow = (x, p) => {
    const o = brief(HT, p, { kind: HT.kindName(p.polityKind) });
    if (!o) return null;
    const rels = [...new Set((p.hosts || []).filter(h => h.host === x).map(h => h.relation).filter(Boolean))];
    if (rels.length) o.rels = rels.map(r => HT.relationName(r));
    if (p.polityKind === 'overlay') o.organ = 1; // 위에 놓인 기관 — 딸린 정권과 따로 묶는다
    return o;
  };

  /* ---------- 대범위 목록(칩 · 모아 보기 스위치) — js/viewer.js:1006 scopeListHTML ---------- */
  const scopeRow = s => {
    const o = { uid: s.uid, name: s.name || '', color: s.color || '' };
    if (s.label) o.label = s.label;
    if (s.host) o.host = { uid: s.host.uid, name: s.host.name, after: s.afterHost ? 1 : 0 };
    return o;
  };

  /* ---------- 지도자 칸 ↔ 같은 이름의 인물 — js/viewer.js figureOfLeader · leadersOfFigure ----------
     형식 3의 사람 잇기(HT.personOf)가 생겼어도 지금 연표의 '같은 이름의 인물' 줄 · 인물 창의 '같은 이름의 지도자'는 이 이름 규칙 그대로다.
     칸에 적은 사람(person)은 따로 `x_persons[칸].figure` · `x_person`으로 싣고, 창은 둘이 다를 때만 '사람:' 줄을 세운다(웹 cellPersonHTML) —
     그래서 이 둘은 이름 규칙으로 둔다(설계 결함 6의 '사람 잇기 기준'은 x_persons · x_person이 맡는다 — 바꾸면 웹 창과 어긋난다). */
  const figureOfLeader = (p, c) => {
    if (!figures.length) return null;
    const names = [c.name, c.temple, c.title, c.given].filter(Boolean);
    const end = c.end == null ? p.endY : c.end;
    return figures.find(q => [q.name].concat(q.aka || []).some(n => names.includes(n)) && q.spanMin <= end && c.start <= q.spanMax + 1 && (q.track === p.track || (q.services || []).some(s => s.polity === p))) || null;
  };
  const leaderFigure = new Map(); // 정권 uid → { 'leader:3': 인물 }
  const figureLeaders = new Map(); // 인물 uid → [{ p, c, i }]
  for (const p of periods) {
    const leaders = p.leaders || [];
    if (!leaders.length || !figures.length) continue;
    leaders.forEach((c, i) => {
      const f = figureOfLeader(p, c);
      if (!f) return;
      const map = leaderFigure.get(p.uid) || leaderFigure.set(p.uid, new Map()).get(p.uid);
      map.set(`leader:${i}`, f);
      const list = figureLeaders.get(f.uid) || figureLeaders.set(f.uid, []).get(f.uid);
      list.push({ p, c, i });
    });
  }

  /* ---------- 정권마다 '이 나라의 사건 수'와 기간 (공동 사건은 그 나라 줄에 그려지는 자리까지 센다) ---------- */
  const evStat = new Map();
  for (const e of model.events || []) {
    const places = e.placements && e.placements.length ? e.placements : [{ polityUid: e.polityUid }];
    for (const uid of new Set(places.map(pl => pl.polityUid).filter(Boolean))) {
      const s = evStat.get(uid) || evStat.set(uid, { n: 0, lo: Infinity, hi: -Infinity }).get(uid);
      s.n++;
      s.lo = Math.min(s.lo, e.start);
      s.hi = Math.max(s.hi, e.endY == null ? e.start : e.endY);
    }
  }

  /* ---------- 왕조: 본가 · 분가는 왕조 이름으로만 이어져 있어 모델 전체를 훑어야 찾을 수 있다 — js/viewer.js:914~916 ---------- */
  const dyns = periods.filter(q => q.polityKind === 'dynasty');
  const dynBy = new Map();
  for (const d of dyns) {
    if (!dynBy.has(d.name)) dynBy.set(d.name, d);
    if (d.id && !dynBy.has(d.id)) dynBy.set(d.id, d);
  }

  /* ========== 정권 · 기관 · 문화 · 왕조 ========== */
  for (const x of periods) {
    const kind = HT.itemKindOf(x);
    /* 칸마다의 경계 [lo, hi) — 이웃 칸을 봐야 정해지는 값이라 넣을 때 확정한다(HT.cellBounds · HT.cellSpan).
       조명 · 그 시기의 사건 · 이 시기의 인물 · '🎯 이 시기로' · 같은 해 보기가 모두 이 값을 본다. */
    const bounds = {};
    for (const K of HT.CELL_KINDS) {
      HT.cellsOf(x, K).forEach((c, i) => {
        if (!c || c.start == null || !Number.isFinite(c.start)) return;
        const ref = `${K.id}:${i}`;
        const sp = HT.cellSpan(c, x, ref);
        const b = spanOf(sp.lo, sp.hi);
        if (b) bounds[ref] = b;
      });
    }
    put(x, 'x_cellBounds', bounds);

    const st = evStat.get(x.uid);
    if (st) put(x, 'x_eventStat', { count: st.n, span: spanOf(st.lo, st.hi) });

    // 이 정권을 섬긴 인물(정권 상세의 '인물' 목록) — $ref에는 없는 역할 · 직함 · 기간 글까지
    put(x, 'x_served', (x.servedBy || []).map(r => {
      const o = { uid: r.figure.uid, name: r.figure.name || '', color: r.figure.color || '', when: T.serviceWhen(r.figure, r.service) };
      if (r.figure.role) o.role = r.figure.role;
      if (r.service.office && r.service.office !== r.figure.role) o.office = r.service.office;
      o.span = spanOf(r.service.start, r.service.endY);
      return o;
    }));

    put(x, 'x_scopes', (x.scopes || []).map(scopeRow));
    put(x, 'x_hostedScopes', (x.hostedScopes || []).map(scopeRow));

    const lf = leaderFigure.get(x.uid);
    if (lf) {
      const o = {};
      for (const [ref, f] of lf) o[ref] = { uid: f.uid, name: f.name || '', role: f.role || '' };
      put(x, 'x_leaderFigures', o);
    }

    if (x.polityKind === 'dynasty') {
      /* 왕조 창: 다스린 나라 · 가문(본가 · 분가) · 그 왕조의 지도자 · 다스린 띠마다의 조명 — js/viewer.js:905~932 · DETAIL_KINDS의 'dynasty' */
      const pt = (t, text) => ({ t, text });
      const ruled = (x.hosts || [])
        .map(h => {
          const a0 = h.start != null ? pt(h.start, h.startUnknown ? '미정' : T.whenText(h.start, h.startAt)) : pt(x.start, h.startUnknown ? '미정' : HT.formatWhen(x, 'start'));
          const a1 = pt(h.host.start, HT.formatWhen(h.host, 'start'));
          const b0 = h.end != null ? pt(h.end, h.endUnknown ? '미정' : T.whenText(h.end, h.endAt)) : pt(x.endY, h.endUnknown ? '미정' : T.endWhen(x));
          const b1 = pt(h.host.endY, T.endWhen(h.host));
          const a = a1.t > a0.t ? a1 : a0; // 늦은 시작 · 이른 끝
          const b = b1.t < b0.t ? b1 : b0;
          return { h, a, b };
        })
        .filter(r => r.b.t >= r.a.t);
      put(x, 'x_ruled', ruled.map(({ h, a, b }) => {
        const o = brief(HT, h.host, { kind: HT.kindName(h.host.polityKind) });
        o.when = `${a.text} ~ ${b.text}`;
        o.span = spanOf(a.t, b.t);
        if (h.note) o.note = h.note;
        return o;
      }));
      const rulers = [];
      for (const { h } of ruled)
        (h.host.leaders || []).forEach((c, i) => {
          if ((c.dynasty || c.dynastyAuto) !== x.name) return;
          rulers.push({ host: h.host, c, i });
        });
      rulers.sort((a, b) => a.c.start - b.c.start);
      put(x, 'x_rulers', rulers.map(({ host, c, i }) => ({
        uid: host.uid, name: host.name || '', ref: `leader:${i}`, label: HT.leaderLabel(c, 'auto'), when: T.cellWhen(c, false, host), at: M(c.start),
      })));
      const main = x.house ? dynBy.get(x.house) : null;
      if (main && main !== x) put(x, 'x_houseMain', brief(HT, main));
      put(x, 'x_branches', dyns.filter(q => q !== x && q.house && (q.house === x.name || q.house === x.id)).map(q => brief(HT, q)));
      // 다스린 띠마다의 기간 조명(창을 열 때 그대로 쓰는 값)
      const spots = [];
      for (const h of x.hosts || [])
        for (const d of h.host.dynasties || [])
          if (d.dynasty === x && !spots.some(s => s.uid === h.host.uid && s.start === M(d.start))) spots.push({ uid: h.host.uid, start: M(d.start), end: M(d.end) });
      put(x, 'x_spots', spots);
    } else {
      /* 정권 · 기관 · 문화: 승계 · 소속 · 다스린 왕조 */
      const pre = (x.predecessors || []).map(e => edgeOf(e, e.from)).filter(Boolean);
      const post = (x.successors || []).map(e => edgeOf(e, e.to)).filter(Boolean);
      put(x, 'x_succ', some(pre) || some(post) ? Object.assign(pre.length ? { pre } : {}, post.length ? { post } : {}) : null);
      const hosts = (x.hosts || []).map(h => hostRow(x, h)).filter(Boolean);
      const members = (x.members || []).map(p => memberRow(x, p)).filter(Boolean);
      put(x, 'x_partOf', hosts.length || members.length ? Object.assign(hosts.length ? { hosts } : {}, members.length ? { members } : {}) : null);
      put(x, 'x_dynasties', (x.dynasties || []).map(d => {
        const o = brief(HT, d.dynasty);
        if (!o) return null;
        o.when = `${T.whenText(d.start)} ~ ${T.endText(d.end)}`;
        o.span = spanOf(d.start, d.end);
        if (d.note) o.note = d.note;
        return o;
      }).filter(Boolean));
    }
  }

  /* ========== 사건 · 조약 ========== */
  for (const e of model.events || []) {
    put(e, 'x_children', (e.children || []).map(c => ({ uid: c.uid, title: c.title || '', when: HT.formatRange(c), span: spanOf(c.start, c.endY) })));
    if (e.parentUid) put(e, 'x_parent', { uid: e.parentUid, title: e.parentTitle || '' });
    put(e, 'x_figures', (e.figureRefs || []).map(r => {
      const f = r.uid ? byUid.get(r.uid) : null;
      const o = { name: r.name || '' };
      if (f) Object.assign(o, { uid: f.uid, role: f.role || '', color: f.color || '' }); // 못 찾은 이름은 uid 없이 — 회색 칩
      return o;
    }));
    const refs = e.treatyRefs || null;
    if (refs) {
      /* 당사국 · 서명자: 풀어낸 기록에 uid가 있어 ＄ref로 접히면 편 · 역할 · 서명자가 모두 사라진다 — 통째로 다시 싣는다(js/viewer.js:1790 treatyPartiesHTML) */
      put(e, 'x_parties', (refs.parties || []).map(r => {
        const o = { name: r.name || '' };
        if (r.uid) Object.assign(o, { uid: r.uid, color: r.color || '' });
        if (r.polity && r.uid && !r.byName) o.wrote = r.polity; // 적은 이름을 찾지 못해 그 해의 그 나라로 놓은 당사국
        if (r.role) o.role = r.role;
        if (r.side != null) o.side = r.side;
        if ((r.signatories || []).length)
          o.signers = r.signatories.map(s => {
            const q = { name: s.name || '' };
            if (s.title) q.title = s.title;
            if (s.figureUid) q.uid = s.figureUid; // 같은 이름의 인물 — 누르면 인물 창
            return q;
          });
        return o;
      }));
    }
    const back = e.treatyBackRefs || null;
    const related = [];
    const row = (tag, uid, fallback) => {
      const q = uid ? byUid.get(uid) : null;
      if (q) related.push({ tag, uid: q.uid, title: q.title || q.name || '', when: HT.formatRange(q) });
      else if (fallback) related.push({ tag, name: fallback }); // 연표에서 찾지 못한 사건 — 누를 수 없는 줄
    };
    const t = e.treaty ? HT.readTreaty(e.treaty) || {} : null;
    if (t && t.concludes) row('끝낸 전쟁', refs && refs.concludes, t.concludes);
    if (t && t.supersedes) row('대체한 옛 조약', refs && refs.supersedes, t.supersedes);
    for (const uid of (back && back.supersededBy) || []) row('대체한 새 조약', uid);
    for (const uid of (back && back.concludedBy) || []) row('끝낸 조약', uid);
    put(e, 'x_related', related);
  }

  /* ========== 인물 ========== */
  for (const f of figures) {
    put(f, 'x_services', (f.services || []).map(s => {
      const o = { name: s.polityName || '', when: T.serviceWhen(f, s), span: spanOf(s.start, s.endY) };
      if (s.polityUid) o.uid = s.polityUid;
      if (s.office) o.office = s.office;
      if (s.polity && s.polity.track !== f.track) o.track = (model.trackMap.get(s.polity.track) || {}).name || s.polity.track; // 다른 트랙 표시
      if (s.note) o.note = s.note;
      if (s.auto) o.auto = 1; // 활동 시기로 짐작한 자리
      if (!s.polity) o.missing = 1; // 연표에서 찾지 못한 정권
      return o;
    }));
    const signed = (f.signedTreaties || []).filter(r => byUid.has(r.event.uid));
    put(f, 'x_signed', signed.map(({ event: e, party, signer }) => {
      const o = { uid: e.uid, title: e.title || '', when: HT.formatRange(e), color: e.polityColor || e.color || '', party: party.name || '' };
      if (signer.title) o.role = signer.title;
      return o;
    }));
    put(f, 'x_events', (f.events || [])
      .filter(e => !signed.some(r => r.event === e)) // 서명한 조약은 아래 목록에만 — 두 번 나오지 않게
      .sort((a, b) => a.start - b.start)
      .map(e => {
        const o = { uid: e.uid, title: e.title || '', when: HT.formatRange(e), color: e.polityColor || e.color || '' };
        if (e.treaty) o.treaty = 1;
        return o;
      }));
    put(f, 'x_leaders', (figureLeaders.get(f.uid) || []).map(({ p, c, i }) => ({
      uid: p.uid, name: p.name || '', ref: `leader:${i}`, label: HT.leaderLabel(c, 'auto'),
    })));
    /* 같은 시기의 지도자: 섬긴 정권마다, 활동 기록의 기간 [시작, 끝)과 지도자 칸이 품는 구간 [lo, hi)가 겹치는 지도자(js/viewer.js:1287~1298) */
    const rulers = [];
    const seen = new Set();
    for (const s of f.services || [])
      if (s.polity)
        (s.polity.leaders || []).forEach((c, i) => {
          const key = `${s.polity.uid}:${i}`;
          const { lo, hi } = HT.cellSpan(c, s.polity, `leader:${i}`);
          if (seen.has(key) || !HT.spanMeets(s.start, s.endY, lo, hi)) return;
          seen.add(key);
          rulers.push({ p: s.polity, c, i });
        });
    rulers.sort((a, b) => a.c.start - b.c.start);
    put(f, 'x_rulers', rulers.map(({ p, c, i }) => ({
      uid: p.uid, name: p.name || '', ref: `leader:${i}`, label: HT.leaderLabel(c, 'auto'), when: T.cellWhen(c, false, p),
    })));
    put(f, 'x_spots', (f.services || []).filter(s => s.shown && s.polityUid).map(s => ({ uid: s.polityUid, start: M(s.start), end: M(s.endY) })));
  }

  /* ========== 시대 구분 · 대범위 ========== */
  for (const ep of model.epochs || []) put(ep, 'x_scopes', (ep.scopes || []).map(scopeRow));
  for (const s of model.scopes || [])
    put(s, 'x_members', (s.members || []).map(m => {
      const o = brief(HT, m, { kind: m.peopleName || HT.kindName(m.polityKind) });
      if (m.track !== s.track) o.other = 1; // 다른 트랙 — 모이지 않는다
      return o;
    }));

  /* ========== 가문(제 항목이 없어 새 기록으로) ========== */
  for (const h of model.houses || []) {
    const H = id => model.houseMap.get(id);
    const chip = q => (q ? { uid: q.uid, name: q.name || '', color: q.color || '' } : null);
    put(h, 'x_path', (h.path || []).map(H).filter(Boolean).map(chip)); // 본가에서 이 가문까지
    put(h, 'x_branches', (h.children || []).map(H).filter(Boolean).map(chip)); // 갈라져 나간 분가
    put(h, 'x_nations', h.members.filter(mb => mb.role === 'period').map(mb => chip(mb.item)).filter(Boolean)); // 국성으로 삼은 나라
    /* 구성원 상한(확정 설계 8-1 · D1-E 이음새 기록 ④): 지도자 · 내각 · 왕조는 모두, 띠 인물은 처음 MEMBER_FIGURES명 + x_memberCount(띠 인물 전체 수).
       계보 전용 인물은 구성원이 아니다(모델이 h.members에 넣지 않음 — 사람 수는 x_kin.n). */
    const figs = h.members.filter(mb => mb.role === 'figure');
    const over = figs.length > MEMBER_FIGURES ? new Set(figs.slice(MEMBER_FIGURES)) : null;
    if (over) put(h, 'x_memberCount', figs.length);
    put(h, 'x_members', h.members.filter(mb => mb.role !== 'period' && !(over && over.has(mb))).map(mb => {
      const it = mb.item;
      /* 구성원은 나라별로 묶는다: 지도자 · 내각은 그 나라, 왕조는 처음 다스린 나라, 인물은 섬긴 나라(js/viewer.js:1552) */
      const nation = mb.role === 'leader' || mb.role === 'cabinet' ? it : mb.role === 'dynasty' ? ((it.hosts || [])[0] || {}).host : (it.polityUid && byUid.get(it.polityUid)) || null;
      const o = { role: mb.role, uid: it.uid, name: it.name || it.title || '' };
      if (mb.cell) {
        o.ref = mb.ref || '';
        o.name = mb.role === 'leader' ? HT.leaderLabel(mb.cell, 'auto') : mb.cell.name || '';
        o.when = T.cellWhen(mb.cell, false, it);
        o.at = M(mb.cell.start);
        o.of = it.name || ''; // 그 칸이 든 정권의 이름
      } else {
        o.when = HT.formatRange(it);
      }
      if (mb.auto) o.auto = 1; // 적지 않아 왕조 · 국성으로 짐작한 가문
      if (nation) Object.assign(o, { nation: nation.uid, nationName: nation.name || '' });
      return o;
    }));
  }

  format3Refs(ctx, T, put, figureOfLeader, kin, docBodies);
  groupWindowRefs(ctx, put); // 단체 계보 창 · 법의 내력 · 의석 막대(D5 결정 4 · 7 — 새 앱 몫)
  return ex;
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  형식 3의 미리 푼 값 — 설계 A 부록 가-6(계약 초안 6-9 다). 글은 js/viewer.js가 만드는 글 그대로:
 *  namesHTML · personLink · kinLinesHTML · cellPersonHTML · figurePersonHTML · placeHTML · groupDetailHTML ·
 *  institutionDetailHTML · periodLensHTML · lensBadgesHTML · lensBottomHTML. 읽는 쪽은 새 앱의 detail_format3.dart ·
 *  detail_group.dart · detail_cell.dart · detail_item.dart · detail_people.dart(A1-c · A1-d)다.
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
function format3Refs(ctx, T, put, figureOfLeader, kin, docBodies) {
  const { model, HT } = ctx;
  const M = t => (t == null || !Number.isFinite(t) ? null : minute(t));
  const span = (a, b) => {
    const lo = M(a);
    if (lo == null) return null;
    const hi = M(b);
    return [lo, hi == null ? lo : Math.max(lo, hi)];
  };
  const byUid = model.byUid;
  const trackName = id => (model.trackMap.get(id) || {}).name || id || '';
  const placeMap = model.placeMap || new Map();
  const surnameMap = model.surnameMap || new Map();
  const has = (o, k, v) => {
    if (v != null && v !== '' && !(Array.isArray(v) && !v.length)) o[k] = v;
    return o;
  };

  /* ---------- 계보(D1 — 확정 설계 8-1 · 이음새 기록 D1-E): 뼈대 자리 · 머리 칩 · 조명 구간. 웹 도우미가 없으면 싣지 않는다 ---------- */
  /** 지도자 칸의 뼈대 자리 [뿌리 뼈대 uid, 한 벌 번호] — HT.kinOf가 먼저, 없으면 뼈대의 칸 표. 실린 뼈대가 아니면 null */
  const kinAtOf = (p, ref, i) => {
    if (!kin) return null;
    const k = typeof HT.kinOf === 'function' ? HT.kinOf(model, p, i) : null;
    if (k && typeof k.key === 'string' && Number.isInteger(k.at) && kin.roots.has(k.key)) return [k.key, k.at];
    const c = kin.cellAt.get(`${p.uid}|${ref}`);
    return c ? c.slice() : null;
  };
  /** 머리 칩(HT.polityHead · HT.houseHead) → [{ role, text, title?, uid?, doc?, auto?: 1 }] — field(메이커가 고칠 칸)는 뺀다.
      uid는 항목 기록이 있는 것만(정권 · 가문 · 성씨). 웹이 문서 열쇠로 가리키는 칩(구분 'track:<id>' · 민족 'people:<id>')은 그 문서에 본문이 있으면
      doc(문서 열쇠 — 기록 uid는 'doc:<열쇠>'), 없으면 둘 다 없음(누를 수 없는 칩 — 확정 설계 3-2 · 4-2). */
  const headChips = list =>
    Array.isArray(list)
      ? list
          .filter(c => c && c.text)
          .map(c => {
            const o = { role: String(c.role || ''), text: String(c.text) };
            if (c.title) o.title = String(c.title);
            const u = c.uid ? String(c.uid) : '';
            if (u && (byUid.has(u) || (model.houseMap && model.houseMap.has(u.replace(/^house:/, '')) && u.startsWith('house:')) || (u.startsWith('surname:') && surnameMap.has(u.slice(8))))) o.uid = u;
            else if (u && docBodies && docBodies.has(u)) o.doc = u;
            if (c.auto) o.auto = 1;
            return o;
          })
      : null;
  /** 해 좌표의 구간 [{ uid, start, end }] → 정수 분(계약 4절) */
  const spotsMin = list =>
    (Array.isArray(list) ? list : [])
      .map(q => {
        const sp = span(q.start, q.end);
        return sp && q.uid ? { uid: q.uid, start: sp[0], end: sp[1] } : null;
      })
      .filter(Boolean);
  /** 가문과 아래 파 모두의 id(자기 포함) — HT.houseUnder, 없으면 분가(children)를 따라 */
  const underOf = id => {
    if (typeof HT.houseUnder === 'function') return Array.from(HT.houseUnder(model, id) || [id]);
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

  /* ---------- 이름 줄 x_names — namesHTML: main(원어 · 로마자 · 종류 없는 이름) · other(그 밖의 이름), 이름마다 nameTag 글 ---------- */
  const nameTag = n => [n.kind ? HT.nameKindName(n.kind) : '', n.lang ? HT.langName(n.lang) : '', T.sideSpan(n), n.note || ''].filter(Boolean).join(' · ');
  const nameRow = n => {
    const o = { text: n.text };
    if (n.lang) o.lang = n.lang;
    const tag = nameTag(n);
    if (tag) o.tag = tag;
    return o;
  };
  const namesLine = list => {
    if (!Array.isArray(list) || !list.length) return null;
    const { main, other } = HT.namesSplit(list);
    if (!main.length && !other.length) return null;
    const o = {};
    if (main.length) o.main = main.map(nameRow);
    if (other.length) o.other = other.map(nameRow);
    return o;
  };
  for (const list of [model.periods, model.events, model.figures, model.lineageFigures, model.houses, model.groups, model.institutions, model.places, model.surnames, model.views, model.maps])
    for (const x of list || []) put(x, 'x_names', namesLine(x.names));

  /* ---------- 사람 고리 — personLink(n, here): 같은 나라의 칸 → 인물 → 다른 나라의 첫 칸 → 글(미상 · 못 찾은 이름) ---------- */
  const ring = (n, here = null) => {
    if (!n) return null;
    if (n.unknown) return { name: '미상', unknown: 1 };
    const same = here ? n.cells.find(q => q.p === here && q.kind === 'leader') : null;
    if (same) return { name: n.name, uid: here.uid, ref: same.ref, polity: here.name || '' };
    if (n.figure && byUid.has(n.figure.uid)) return { name: n.name, uid: n.figure.uid };
    const c = n.cells[0];
    if (c) return { name: n.name, uid: c.p.uid, ref: c.ref, polity: c.p.name || '' };
    return n.missing ? { name: n.name, missing: 1 } : { name: n.name };
  };
  /** 부모 줄의 관계 글 — kinRoleText(부 · 모 · 'n대 조상' · 없으면 '부모') */
  const kinRoleText = e => (e.as === 'ancestor' ? `${e.gen ? `${e.gen}대 ` : ''}조상` : e.as ? HT.parentRoleName(e.as) : '부모');
  /** 혈연 줄들(kinLinesHTML) · 속한 단체(personGroupsHTML) — 사람 자리 n을 here(지금 보는 나라)에서 본 것 */
  const kinOf = (n, here) => {
    const o = {};
    has(o, 'parents', n.parents.map(e => {
      const r = Object.assign(ring(e.node, here), { as: kinRoleText(e) });
      if (e.certainty) r.certainty = HT.certaintyName(e.certainty) || e.certainty;
      if (e.note) r.note = e.note;
      return r;
    }));
    has(o, 'spouses', n.spouses.map(e => has(ring(e.node, here), 'when', T.sideSpan(e))));
    has(o, 'children', n.children.map(e => has(ring(e.node, here), 'as', e.as === 'ancestor' ? `${e.gen ? `${e.gen}대` : ''} 후손`.trim() : /^adoptive-/.test(e.as || '') ? '양자' : '')));
    has(o, 'groups', (n.groups || []).map(g => ({ uid: g.uid, name: g.name || '' })));
    return o;
  };

  /* ---------- 상세 창 머리 x_nameHead (10건 3 · 감독 결정 D2-1 A · 4 B — 갈래 D2 · 웹 viewer.js namesHeadHTML · namesRestHTML · namesLineHTML) ----------
   * HT.namesHead의 셋 그대로: first = 첫 원어 · second = 첫 로마자(없으면 현지음 → 한자음) · rest = 두 줄에 오르지 않은 나머지(나온 차례).
   * 이름 하나 = { text, lang?, langName?(언어 이름 — HT.langName), kind?(종류 이름 — HT.nameKindName), when?(쓴 기간 글), note?, mw? }.
   *   풍선 글(웹 nameTip = 종류 · 언어 이름 · 쓴 기간 · 메모)과 '다른 이름' 칸의 세 칸(종류 · 글 · 쓴 기간 · 메모)을 앱이 이 칸들로 잇는다.
   *   mw = 내장 창 표(HT.GLYPH_WINDOW)에 없는 글자의 코드 포인트(나온 차례 · 겹치지 않게 · 비면 싣지 않음) — 앱은 켜진 글꼴 팩의 범위로
   *   이 목록만 다시 보고, 남는 글자가 있으면 글 대신 '원어 — ○○ · 글꼴 없음' 딱지(설계 3-9 7-6 · 7-8).
   * 기존 x_names(F1 꼴)는 그대로 둔다 — 이 열쇠가 없는 옛 저장소는 앱이 x_names로 예전처럼 그린다. */
  const headItem = n => {
    const o = { text: n.text };
    if (n.lang) Object.assign(o, { lang: n.lang, langName: HT.langName(n.lang) });
    if (n.kind) o.kind = HT.nameKindName(n.kind);
    const when = T.sideSpan(n);
    if (when) o.when = when;
    if (n.note) o.note = n.note;
    const mw = HT.glyphMissing(n.text, HT.GLYPH_WINDOW);
    if (mw.length) o.mw = mw;
    return o;
  };
  const headOf = list => {
    if (!HT.namesHead || !Array.isArray(list) || !list.length) return null;
    const { first, second, rest } = HT.namesHead(list);
    if (!first && !second && !rest.length) return null;
    const o = {};
    if (first) o.first = headItem(first);
    if (second) o.second = headItem(second);
    if (rest.length) o.rest = rest.map(headItem);
    return o;
  };
  for (const list of [model.periods, model.events, model.figures, model.lineageFigures, model.houses, model.groups, model.institutions, model.places, model.surnames, model.views, model.maps])
    for (const x of list || []) put(x, 'x_nameHead', headOf(x.names));
  // 가문 창의 성 한 줄("성 ○ — 원어 · 로마자" — 웹 namesLineHTML(sn.names, 'polity', …))의 재료. x_surname(F1 꼴)은 그대로 둔다
  for (const h of model.houses || []) {
    const sn = h.surnameId ? surnameMap.get(h.surnameId) : null;
    if (sn) put(h, 'x_surnameHead', headOf(sn.names));
  }

  /* ---------- 지명 줄 — placeHTML(ref, lead): 이름 · 위 구역(가까운 것부터) · 원어 ---------- */
  const placeLine = pl => {
    if (!pl) return null;
    const o = { name: pl.name, uid: pl.uid };
    has(o, 'up', (pl.path || []).slice(0, -1).reverse().map(id => (placeMap.get(id) || {}).name).filter(Boolean));
    const names = namesLine(pl.names);
    if (names) o.names = names;
    const head = headOf(pl.names); // 딸린 한 줄(웹 namesLineHTML — "지명 ○○ — 원어 · 로마자 · 다른 이름 …")의 재료 · 갈래 D2
    if (head) o.head = head;
    return o;
  };

  /* ========== 정권: 칸의 이름 줄 · 자리 이음 · 칸의 사람 · 도읍의 지명 · 단체 · 제도 칩 ========== */
  for (const x of model.periods || []) {
    const cellNames = {};
    const cellHeads = {}; // 칸 창의 머리(x_nameHead와 같은 꼴 — 갈래 D2)
    for (const K of HT.CELL_KINDS) HT.cellsOf(x, K).forEach((c, i) => {
      const line = c && namesLine(c.names);
      if (line) cellNames[`${K.id}:${i}`] = line;
      const head = c && headOf(c.names);
      if (head) cellHeads[`${K.id}:${i}`] = head;
    });
    put(x, 'x_cellNames', cellNames);
    put(x, 'x_cellNameHead', cellHeads);
    if (HT.itemKindOf(x) !== 'period') continue;

    // 자리 이음(HT.lineageOf — 지도자를 칸 참조 열쇠로). 화면은 칸에 accession을 적었을 때만 줄을 세운다.
    const lin = HT.lineageOf(model, x);
    const lineage = {};
    for (const r of (lin && lin.rulers) || []) {
      const a = r.accession || {};
      const o = {};
      if (a.from && !a.fromUnknown) o.from = ring(a.from, x);
      if (a.fromAuto && a.from) o.fromAuto = 1;
      if (a.fromUnknown) o.fromUnknown = 1;
      if (a.kin) Object.assign(o, { kin: a.kinName, kinId: a.kin });
      if (a.kinUnknown) o.kinUnknown = 1;
      if (a.how) Object.assign(o, { how: a.howName, howId: a.how });
      if (a.howUnknown) o.howUnknown = 1;
      if (a.note) o.note = a.note;
      if (r.restored) o.restored = 1;
      has(o, 'elsewhere', (r.elsewhere || []).map(q => ({ name: r.person ? r.person.name : '', uid: q.uid, ref: q.ref, polity: q.name || '' })));
      /* 승계표(D1 — 확정 설계 3-3 · 8-1, 이음새 기록 ①): 선 갈래 line(0~5) · 이음매 글 seam(웹 글 그대로 — 앱은 글을 만들지 않음) ·
         뼈대 자리 kinAt [뿌리 뼈대 uid, 한 벌 앞 차례 번호]. `kin`은 위의 관계 글이라 뼈대 자리는 kinAt이다. */
      if (typeof HT.accessionLine === 'function') o.line = HT.accessionLine(r.accession, r) | 0;
      if (typeof HT.accessionSeam === 'function') has(o, 'seam', HT.accessionSeam(model, r) || '');
      const at = kinAtOf(x, r.ref, r.i);
      if (at) o.kinAt = at;
      if (Object.keys(o).length) lineage[r.ref] = o;
    }
    put(x, 'x_lineage', lineage);
    // 승계표 머리 칩(3-2 — 구분 › 민족 › 국가 이름 · 꼬리표): 지도자가 있는 나라만. field(메이커 몫)는 뺀다 — 앱은 링크만.
    if (typeof HT.polityHead === 'function' && (x.leaders || []).length) put(x, 'x_head', headChips(HT.polityHead(model, x)));

    // 칸의 사람(지도자 · 사람을 적은 내각 — cellPersonHTML): 사람 · 같은 사람의 다른 칸 · 혈연 · 속한 단체
    const persons = {};
    for (const [kind, list] of [['leader', x.leaders || []], ['cabinet', x.cabinets || []]])
      list.forEach((c, i) => {
        const ref = `${kind}:${i}`;
        const n = HT.personOf(model, x, ref);
        if (!n) return;
        const o = {};
        // 내각 칸의 '사람:' 줄은 이름이 같은 인물과 다를 때만 선다(웹 n.figure !== figureOfLeader) — 화면이 지도자 칸만 x_leaderFigures로 가리므로 여기서 가린다.
        if (n.figure && byUid.has(n.figure.uid) && (kind === 'leader' || n.figure !== figureOfLeader(x, c))) o.figure = has({ uid: n.figure.uid, name: n.figure.name || '' }, 'role', n.figure.role);
        has(o, 'others', n.cells.filter(q => !(q.p === x && q.ref === ref)).map(q => ({ name: n.name, uid: q.p.uid, ref: q.ref, polity: q.p.name || '', when: T.cellWhen(q.c, false, q.p) })));
        Object.assign(o, kinOf(n, x));
        if (Object.keys(o).length) persons[ref] = o;
      });
    put(x, 'x_persons', persons);

    // 도읍의 지명 줄 — 원어나 위 구역이 있을 때만(placeHTML(c.city, '지명'))
    const cellPlaces = {};
    (x.capitals || []).forEach((c, i) => {
      const pl = c && HT.placeOf(model, c.city);
      if (pl && ((pl.names || []).length || pl.parentId)) cellPlaces[`capital:${i}`] = placeLine(pl);
    });
    put(x, 'x_cellPlaces', cellPlaces);

    // 나라의 단체 · 제도 칩(periodLensHTML — x.kind === 'period'만)
    if (x.kind === 'period') {
      put(x, 'x_groupLinks', (x.groupLinks || []).map(l => has({ uid: l.group.uid, name: l.group.name || '', color: l.group.color || '', role: l.role }, 'typeName', l.group.typeName)));
      put(x, 'x_institutions', (x.institutionList || []).map(i => {
        const o = { uid: i.uid, name: i.name || '', theme: i.themeId || '', themeName: i.themeName || '' };
        has(o, 'family', i.family);
        o.color = i.color || '';
        has(o, 'title', `${i.themeName} — ${(i.spanList || []).map(s => s.name).join(' → ')}`);
        return o;
      }));
    }
  }

  /* ========== 인물: 다스린 칸 · 혈연 · 속한 단체(figurePersonHTML) ========== */
  for (const f of model.figures || []) {
    const n = HT.personOf(model, f);
    if (!n) continue;
    const o = {};
    has(o, 'ruled', n.cells.filter(q => q.kind === 'leader').map(q => ({ uid: q.p.uid, ref: q.ref, name: q.p.name || '', label: HT.leaderLabel(q.c, 'auto'), when: T.cellWhen(q.c, false, q.p) })));
    Object.assign(o, kinOf(n, null));
    put(f, 'x_person', o);
  }

  /* ========== 사건: 장소 · 법 · 선거 · 이 일로 맺은 단체(placeHTML · lensBadgesHTML · lensBottomHTML — x.kind === 'event') ========== */
  for (const e of model.events || []) {
    if (e.kind !== 'event') continue;
    if (e.place) put(e, 'x_place', placeLine(HT.placeOf(model, e.place)));
    const law = e.law ? HT.readLaw(e.law) : null;
    if (law) {
      const o = {};
      has(o, 'name', law.name);
      if (law.act) Object.assign(o, { act: law.act, actName: HT.lawActName(law.act) });
      has(o, 'articles', law.articles);
      has(o, 'note', law.note);
      put(e, 'x_law', o);
    }
    const el = e.election ? HT.readElection(e.election) : null;
    if (el) {
      const o = {};
      has(o, 'office', el.office);
      o.results = (el.results || []).map(r => {
        const q = { who: r.who };
        if (r.votes != null) q.votes = r.votes;
        if (r.seats != null) q.seats = r.seats;
        if (r.won) q.won = 1;
        return q;
      });
      has(o, 'note', el.note);
      put(e, 'x_election', o);
    }
    put(e, 'x_groups', (e.groupRefs || []).map(g => has({ uid: g.uid, name: g.name || '', color: g.color || '' }, 'typeName', g.typeName)));
  }

  /* ========== 가문: 성 · 세계표 · 가문 조명 ========== */
  const spotsOf = list => {
    // 정권마다 칸의 기간 [lo, hi]를 시작 순으로 이어 붙인다(겹치거나 맞닿으면 하나로).
    const by = new Map();
    for (const { uid, lo, hi } of list) {
      if (lo == null) continue;
      (by.get(uid) || by.set(uid, []).get(uid)).push([lo, hi == null ? lo : Math.max(lo, hi)]);
    }
    const out = [];
    for (const [uid, spans] of by) {
      spans.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
      let cur = null;
      for (const s of spans) {
        if (cur && s[0] <= cur.end) cur.end = Math.max(cur.end, s[1]);
        else out.push((cur = { uid, start: s[0], end: s[1] }));
      }
    }
    return out.sort((a, b) => a.start - b.start || (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
  };
  /* 계보 전용 인물의 가문(사람 자리의 가문 — 적은 것 → 파조 → 물려받기)별 수 — 웹 viewer.js kinFigureHouse와 같은 규칙 */
  const lineageByHouse = new Map();
  for (const f of model.lineageFigures || []) {
    const n = HT.personOf ? HT.personOf(model, f) : null;
    const hid = (n && n.houseId) || f.houseId || '';
    if (hid) lineageByHouse.set(hid, (lineageByHouse.get(hid) || 0) + 1);
  }
  for (const h of model.houses || []) {
    const sn = h.surnameId ? surnameMap.get(h.surnameId) : null;
    if (sn) put(h, 'x_surname', has({ uid: sn.uid, name: sn.name }, 'names', namesLine(sn.names)));
    /* 세계표(D1): A 가-6의 x_family(노드 · 선 전부 JSON)는 싣지 않고 열 꼴 뼈대 기록(갈래 kin)을 가리키는 x_kin을 단다(확정 설계 8-1).
       x_head(머리 칩 — 짐작은 auto) · x_under(아래 파까지의 가문 id — 띠 구역 42 text2와 같은 글, 파가 있을 때만) · x_eras(다스린 기간 막대). */
    const hk = kin && kin.houseKin.get(h.id);
    if (hk) {
      // lineage = 계보 전용 인물 수(아래 파 포함) — 웹 가문 창의 '계보 전용 인물 n명 · 세계표에서 보기' 줄과 같은 수(D1 결합 덧붙임 — 0이면 뺌)
      const nl = underOf(h.id).reduce((sum, id) => sum + (lineageByHouse.get(id) || 0), 0);
      put(h, 'x_kin', nl ? Object.assign({}, hk, { lineage: nl }) : hk);
    }
    if (typeof HT.houseHead === 'function') put(h, 'x_head', headChips(HT.houseHead(model, h)));
    const under = underOf(h.id);
    if (under.length > 1) put(h, 'x_under', under);
    if (typeof HT.houseEras === 'function')
      put(h, 'x_eras', (HT.houseEras(model, h.id) || []).map(r => {
        const P = r.polity && typeof r.polity === 'object' ? r.polity : r.uid ? byUid.get(r.uid) : null;
        const o = { uid: r.uid || (P && P.uid) || '', name: r.name || (P && P.name) || '', color: r.color || (P && P.color) || '' };
        const sp = Array.isArray(r.span) ? span(r.span[0], r.span[1]) : span(r.start ?? (P && P.start), r.end ?? (P && P.endY));
        if (sp) o.span = sp;
        o.cells = (r.cells || r.spans || []).map(c => (Array.isArray(c) ? span(c[0], c[1]) : span(c.start, c.end))).filter(Boolean);
        // 내각(실권) 자리에 있던 구간(감독 건의 2026-10-14 5번) — 있을 때만 싣는다(옛 앱은 모르는 열쇠를 건너뜀)
        const real = (r.real || []).map(c => span(c[0], c[1])).filter(Boolean);
        if (real.length) o.real = real;
        // 끝이 열린 구간의 차례(글로는 '~ 미정') — 있을 때만
        if (r.openCells && r.openCells.length) o.openCells = r.openCells;
        if (r.openReal && r.openReal.length) o.openReal = r.openReal;
        return o;
      }));
    // 가문 조명: 아래 파까지(10절 12번) — HT.houseSpans(맞닿은 칸 잇기 · 칸 없는 나라는 국성 기간). 웹 도우미가 없으면 지금(A1-a)처럼 이 가문의 칸만.
    if (typeof HT.houseSpans === 'function') {
      put(h, 'x_spots', spotsMin(HT.houseSpans(model, under, { branches: true })));
      continue;
    }
    const spots = [];
    for (const mb of h.members || []) {
      if ((mb.role === 'leader' || mb.role === 'cabinet') && mb.cell && mb.item) {
        const sp = HT.cellSpan(mb.cell, mb.item, mb.ref);
        spots.push({ uid: mb.item.uid, lo: M(sp.lo), hi: M(sp.hi) });
      } else if (mb.role === 'dynasty' && mb.item)
        for (const hh of mb.item.hosts || []) for (const d of hh.host.dynasties || []) if (d.dynasty === mb.item) spots.push({ uid: hh.host.uid, lo: M(d.start), hi: M(d.end) });
    }
    put(h, 'x_spots', spotsOf(spots));
  }

  /* ========== 단체 — groupDetailHTML ========== */
  const rowWhen = r => (r.given || r.startUnknown || r.endUnknown ? T.spanText(r) : '');
  const polityRow = r => {
    const o = { name: r.name || '' };
    if (r.polityUid && byUid.has(r.polityUid)) Object.assign(o, { uid: r.polityUid, color: r.color || '' });
    return o;
  };
  for (const g of model.groups || []) {
    put(g, 'x_type', g.typeName);
    put(g, 'x_span', span(g.start, g.endY));
    put(g, 'x_within', (g.withinList || []).map(r => {
      const o = has(polityRow(r), 'when', rowWhen(r));
      const s = span(r.start, r.end);
      if (s) o.span = s;
      return o;
    }));
    put(g, 'x_members', (g.memberList || []).map(r => {
      const o = polityRow(r);
      has(o, 'role', r.role);
      if (r.track !== g.track) has(o, 'track', trackName(r.track));
      has(o, 'when', rowWhen(r));
      has(o, 'note', r.note);
      const s = span(r.start, r.end);
      if (s) o.span = s;
      return o;
    }));
    put(g, 'x_power', (g.powerSpans || []).map(c => {
      const o = { name: c.name || '', when: T.cellWhen(c, false, g) };
      const s = span(c.start, c.end);
      if (s) o.span = s;
      has(o, 'note', c.note);
      if (c.endAuto) o.endAuto = 1;
      if (c.endUnknown) o.endUnknown = 1;
      return o;
    }));
    const how = f => {
      const o = {};
      if (f.how) Object.assign(o, { how: f.how, howName: HT.groupHowName(f.how) });
      return has(o, 'note', f.note);
    };
    put(g, 'x_from', (g.fromList || []).map(f => Object.assign(f.group ? { uid: f.group.uid, name: f.group.name || '' } : { name: f.name || '', missing: 1 }, how(f))));
    put(g, 'x_into', (g.intoList || []).map(f => Object.assign({ uid: f.group.uid, name: f.group.name || '' }, how(f))));
    // 구성원 칩(memberChipHTML): 인물 → 인물 창 · 인물 없는 사람 자리의 첫 칸 → 그 칸 · 못 찾은 이름은 누를 수 없는 칩
    put(g, 'x_people', (g.peopleList || []).map(p => {
      if (p.uid && p.figure) return has(has({ name: p.figure.name || '', uid: p.uid }, 'role', p.figure.role), 'color', p.figure.color);
      const c = p.person && p.person.cells[0];
      if (c) return has({ name: p.person.name || '', uid: c.p.uid, ref: c.ref, polity: c.p.name || '' }, 'color', c.p.color);
      return { name: p.name || '', missing: 1 };
    }));
    if (g.eventItem) put(g, 'x_event', { uid: g.eventItem.uid, title: g.eventItem.title || '', when: HT.formatRange(g.eventItem) });
    put(g, 'x_warnings', (g.warnings || []).slice());
  }

  /* ========== 제도 — institutionDetailHTML ========== */
  for (const it of model.institutions || []) {
    const P = it.polityItem || null;
    put(it, 'x_theme', has({ id: it.themeId || '', name: it.themeName || '' }, 'color', it.themeColor));
    put(it, 'x_polity', P && byUid.has(P.uid) ? { uid: P.uid, name: P.name || '', color: P.color || '' } : { name: it.polityName || '' });
    put(it, 'x_spans', (it.spanList || []).map(sp => {
      const o = { name: sp.name || '', when: HT.phaseRangeText(sp, P) };
      const s = span(sp.start, sp.end);
      if (s) o.span = s;
      has(o, 'note', sp.note);
      if (sp.from) {
        const f = { polity: sp.from.polity || '' };
        has(f, 'name', sp.from.name);
        if (sp.fromItem && byUid.has(sp.fromItem.uid)) Object.assign(f, { uid: sp.fromItem.uid, color: sp.fromItem.color || '' });
        o.from = f;
      }
      if (sp.guess) o.guess = 1;
      return o;
    }));
    put(it, 'x_same', (it.sameFamily || []).map(q => ({ uid: q.uid, name: q.name || '', polity: q.polityName || '', color: q.color || '', when: T.spanText({ start: q.start, end: q.endY }) })));
    put(it, 'x_warnings', (it.warnings || []).slice());
  }

  /* ========== 지명 · 성씨 ========== */
  for (const pl of model.places || []) {
    put(pl, 'x_path', (pl.path || []).slice(0, -1).map(id => placeMap.get(id)).filter(Boolean).map(q => ({ uid: q.uid, name: q.name })));
    put(pl, 'x_children', (pl.children || []).map(id => placeMap.get(id)).filter(Boolean).map(q => ({ uid: q.uid, name: q.name })));
    put(pl, 'x_uses', (pl.uses || []).map(u => {
      if (u.role === 'map') {
        const m = model.mapMap && model.mapMap.get(u.mapId);
        return m ? { role: 'map', uid: m.uid, name: m.name || m.id } : { role: 'map', name: u.mapId || '', missing: 1 };
      }
      const it = u.item;
      if (!it || !byUid.has(it.uid)) return null;
      const o = { role: u.role, uid: it.uid };
      if (u.ref) o.ref = u.ref;
      o.name = it.title || it.name || '';
      const cell = u.ref ? HT.cellsOf(it, u.ref.split(':')[0])[Number(u.ref.split(':')[1])] : null;
      o.when = cell ? T.cellWhen(cell, cell.end == null, it) : HT.formatRange(it);
      return o;
    }).filter(Boolean));
  }
  for (const sn of model.surnames || []) {
    put(sn, 'x_houses', (sn.houses || []).map(id => model.houseMap.get(id)).filter(Boolean).map(h => ({ uid: h.uid, name: h.name || '', color: h.color || '' })));
    // 성씨 조명(결정 7 A): 그 성의 모든 가문(과 아래 파)의 구간 — 같은 칠
    if (typeof HT.houseSpans === 'function' && (sn.houses || []).length) {
      const ids = [...new Set((sn.houses || []).flatMap(id => underOf(id)))];
      put(sn, 'x_spots', spotsMin(HT.houseSpans(model, ids, { branches: true })));
    }
  }

  /* ========== 계보 전용 인물(D1 — model.lineageFigures): 뼈대 자리 x_kin. x_person은 싣지 않는다(부모 · 자식은 뼈대에서) ========== */
  for (const f of model.lineageFigures || []) {
    // 그 사람이 구성원으로 든 뼈대 — HT.kinOfPerson(웹)이 먼저, 없으면 뼈대들의 안정 열쇠에서(구성원으로 든 자리 먼저)
    const w = kin && typeof HT.kinOfPerson === 'function' ? HT.kinOfPerson(model, `f:${f.uid}`) : null;
    const at = w && kin.roots.has(w.key) ? Object.assign({ key: w.key, at: w.at }, kin.chunkAt(w.key, w.at)) : kin && kin.personAt.get(`f:${f.uid}`);
    if (at) put(f, 'x_kin', has({ key: at.key, at: at.at }, 'chunk', at.chunk));
  }

  /* ========== 모아 보기 판 · 지도 — 나르기만(화면은 A3) ========== */
  for (const v of model.views || []) {
    const out = [];
    const seen = new Set();
    for (const ref of HT.readScopeRefs(v.memberRefs)) {
      const m = (v.members || []).find(p => (p.name === ref.polity || p.id === ref.polity || p.uid === ref.polity) && (!ref.track || p.track === ref.track));
      const key = m ? m.uid : `?${HT.scopeRefText(ref)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(m ? { uid: m.uid, name: m.name || '', color: m.color || '' } : { name: HT.scopeRefText(ref), missing: 1 });
    }
    for (const m of v.members || []) if (!seen.has(m.uid)) {
      seen.add(m.uid);
      out.push({ uid: m.uid, name: m.name || '', color: m.color || '' });
    }
    put(v, 'x_members', out);
    if (v.start != null) put(v, 'x_span', span(v.start, v.endY));
  }
  for (const m of model.maps || []) {
    put(m, 'x_scenes', (m.scenes || []).map(s => {
      const owners = {};
      for (const [rid, ref] of Object.entries(s.owners || {})) {
        const it = (s.items || {})[rid];
        owners[rid] = it && byUid.has(it.uid) ? { uid: it.uid, name: it.name || '', color: it.color || '' } : { name: HT.scopeRefText(HT.readScopeRef(ref)) || String(ref ?? ''), missing: 1 };
      }
      const o = { year: s.year, at: M(s.year) };
      if (s.yearAt) o.yearAt = s.yearAt;
      o.owners = owners;
      has(o, 'note', s.note);
      return o;
    }));
  }
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  단체 계보 창 · 법의 내력 · 의석 막대 — 설계 D5 결정 4 A · 7 A(docs/설계-10건/7-8-단체와-렌즈.md 9절)의 새 앱 몫.
 *  웹은 창을 열 때 모델에서 셉니다(js/group-tree.js HT.groupTreeLayout · js/viewer.js lawVoteIndex · lawTopHTML · electionTopHTML · lensBottomHTML).
 *  새 앱은 모델이 없으므로 같은 셈을 여기서 한 번 돌려 x_로 싣고, 앱(prototype/app/lib/ui/group_tree.dart · detail_format3.dart)은 그리기만 합니다.
 *  계보 나무의 배치는 웹 파일(js/group-tree.js — 화면과 무관한 셈 HT.groupTreeLayout)을 그대로 불러 씁니다 — 같은 셈이라 같은 나무.
 *    정권 x_groupTree — 그 나라에 있던 단체의 나무(웹 '단체' 상자의 '단체 계보' 단추가 여는 것 — 있던 단체가 하나라도 있는 나라만)
 *    단체 x_treeAt    — 단체 창의 '단체 계보'가 여는 나무가 그 단체의 나라 나무와 같으면 그 나라의 uid(나무를 두 번 싣지 않게)
 *    단체 x_groupTree — 다르면(나라 없이 앞뒤 단체만 있는 단체 · 구성 나라로만 든 연합) 그 단체의 나무
 *      나무 = { polity?: {uid,name,color}, span:[분,분], rows, nodes:[{uid,name,color,row,span,when,range,type?,count?,segs?:[[분,분,종류]],spots?}],
 *               edges?:[{from,to,kind,same?,after?,ev?,tip}] }
 *      segs의 종류: 0 집권 · 1 연정 · 2 실권. spots = 막대를 누르면 위 연표에 켤 조명 [{uid,start,end}](분 — 웹 spotsOf)
 *      edges의 kind: split · merge · rename · unknown(방식 미상) · blank(적지 않음), same = 이름 바꿈을 같은 줄에 이어 씀,
 *      after = 뒤 단체가 앞 단체가 끝난 뒤 시작(세로 줄기의 자리), ev = 이음선을 누르면 열 사건, tip = 이음선 풍선 글(웹 그대로)
 *    사건 x_lawHistory — 법의 내력 { n, orig?, rows:[{word, when, here?, at?, uid?, title?, note?, gap?}] } (법 이름이 있고 조약이 아닌 법 사건)
 *    사건 x_lawArts    — 조항 [{no?, title?, text}] (머리 번호를 뗀 조약 조항 꼴)
 *    사건 x_lawRelated · x_voteRelated — 관련 [{tag, uid, text, when}] (그때의 법률 · 앞 고침 / 그때의 선거 방식 · 앞 선거 · 다음 선거)
 *    사건 x_vote — 결과 { by:'seats'|'votes'|'', total, cap?, linked?, rows:[{who, color, uid?, votes?, seats?, won?, part?}] } (선거 사건이면 늘 — 결과를 적지 않았으면 rows 빈 목록)
 *  모두 새 열쇠라 있던 기록의 다른 열쇠는 1바이트도 바뀌지 않고, 단체 · 법 · 선거가 없는 자료(동아시아 · 월흔해)는 기록이 그대로입니다.
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
function groupWindowRefs(ctx, put) {
  const { model, HT } = ctx;
  if (!(model.groups || []).length && !(model.events || []).some(e => e.law || e.election)) return;
  if (typeof HT.groupTreeLayout !== 'function') runScript('js/group-tree.js'); // 웹 계보 창의 배치 셈(화면 요소는 창을 열 때만 만듦 — 불러오기만으로는 쓰지 않음)
  const M = t => (t == null || !Number.isFinite(t) ? null : minute(t));
  const byUid = model.byUid;
  const has = (o, k, v) => {
    if (v != null && v !== '' && !(Array.isArray(v) && !v.length)) o[k] = v;
    return o;
  };
  const EPS = 1e-6;
  const yr = t => HT.formatAxisYear(t);

  /* ---------- 단체 계보 나무 ---------- */
  const SEG = { power: 0, coal: 1, real: 2 };
  const WORD = { split: '갈라짐', merge: '합쳐짐', rename: '이름 바꿈', unknown: '방식 미상', blank: '방식을 적지 않음' };
  /** 고른 단체의 조명(웹 spotsOf): 있던 나라 띠마다 집권 덩이(없으면 있던 기간) */
  const spotsOf = (g, n) => {
    const out = [];
    for (const w of g.withinList || []) {
      if (!w.polityUid || !byUid.has(w.polityUid)) continue;
      const lo = w.start != null ? w.start : g.start;
      const hi = w.end != null ? w.end : g.endY;
      for (const sg of n.segs.length ? n.segs : [{ a: g.start, b: g.endY }]) {
        const a = Math.max(sg.a, lo);
        const b = Math.min(sg.b, hi);
        if (b > a) out.push({ uid: w.polityUid, start: M(a), end: M(b) });
      }
    }
    return out;
  };
  const treeOf = lay => {
    const idx = new Map(lay.nodes.map((n, i) => [n.g, i]));
    const o = {};
    if (lay.polity && byUid.has(lay.polity.uid)) o.polity = { uid: lay.polity.uid, name: lay.polity.name || '', color: lay.polity.color || '' };
    o.span = [M(lay.start), Math.max(M(lay.start), M(lay.end))];
    o.rows = lay.rows;
    o.nodes = lay.nodes.map(n => {
      const g = n.g;
      const q = { uid: g.uid, name: g.name || '', color: g.color || '', row: n.row, span: [M(g.start), Math.max(M(g.start), M(g.endY))], when: HT.formatRange(g), range: `${yr(g.start)}–${yr(g.endY)}` };
      has(q, 'type', g.typeName);
      has(q, 'count', n.count);
      has(q, 'segs', n.segs.map(s => [M(s.a), M(s.b), SEG[s.kind]]));
      has(q, 'spots', spotsOf(g, n));
      return q;
    });
    has(
      o,
      'edges',
      lay.edges.map(e => {
        const q = { from: idx.get(e.from), to: idx.get(e.to), kind: e.kind };
        if (e.same) q.same = 1;
        if (e.to.start >= e.from.endY - EPS) q.after = 1;
        if (e.ev && byUid.has(e.ev.uid)) q.ev = e.ev.uid;
        q.tip = `${WORD[e.kind]} — ${e.from.name} → ${e.to.name} · ${yr(e.to.start)}${e.note ? ` · ${e.note}` : ''}${q.ev ? ' · 누르면 그 사건' : ''}`;
        return q;
      })
    );
    return o;
  };
  const sig = lay => lay.nodes.map(n => n.g.uid).join('\n');
  const polityTree = new Map(); // 나라 uid → 그 나라 나무의 단체 목록(같은 나무인지 견줄 서명)
  for (const p of model.periods || []) {
    if (p.kind !== 'period' || !(p.groupLinks || []).some(l => l.role === 'within')) continue;
    const lay = HT.groupTreeLayout(model, { polityUid: p.uid });
    if (!lay.nodes.length) continue;
    put(p, 'x_groupTree', treeOf(lay));
    polityTree.set(p.uid, sig(lay));
  }
  for (const g of model.groups || []) {
    // 웹 단체 창의 '단체 계보' 단추가 서는 때: 나라를 찾은 있던 나라 · 앞선 단체 · 뒤를 이은 단체 가운데 하나라도
    if (!((g.withinList || []).some(r => r.polityUid) || (g.fromList || []).length || (g.intoList || []).length)) continue;
    const lay = HT.groupTreeLayout(model, { polityUid: g.polityUid || null, groupUid: g.uid });
    if (!lay.nodes.length) continue;
    if (g.polityUid && polityTree.get(g.polityUid) === sig(lay)) put(g, 'x_treeAt', g.polityUid);
    else put(g, 'x_groupTree', treeOf(lay));
  }

  /* ---------- 법의 내력 · 의석 막대 (웹 lawVoteIndex — 같은 나라(못 찾으면 같은 트랙) · 같은 법 이름, 날짜 차례 · 같은 때면 제정 → 개정 → 폐지) ---------- */
  const ACT = { enact: 0, amend: 1, repeal: 2 };
  const keyOf = e => e.polityUid || `track:${e.track}`;
  const laws = new Map();
  const votes = new Map();
  const pushTo = (map, k, v) => (map.has(k) ? map.get(k).push(v) : map.set(k, [v]));
  for (const e of model.events || []) {
    const law = e.law ? HT.readLaw(e.law) : null;
    if (law && law.name) pushTo(laws, `${keyOf(e)}|${law.name}`, { e, law });
    const el = e.election ? HT.readElection(e.election) : null;
    if (el) pushTo(votes, keyOf(e), { e, el });
  }
  for (const list of laws.values()) list.sort((a, b) => a.e.start - b.e.start || (ACT[a.law.act] ?? 1) - (ACT[b.law.act] ?? 1));
  for (const list of votes.values()) list.sort((a, b) => a.e.start - b.e.start);
  /** 날짜 글의 자세함 'y' · 'm' · 'd' · 'h'(웹 precOf) */
  const precOf = (x, key = 'start') => {
    const at = HT.atOf(x, key);
    const r = at ? HT.cal.parse(at) : null;
    return r && r.ok && r.prec !== 'x' ? (r.prec === 'min' ? 'h' : r.prec) : 'y';
  };
  /** 두 때 사이의 간격 글(웹 gapText) */
  const gapText = (a, aAt, b, bAt) => {
    const d = b - a;
    if (!(d > 1e-6)) return '';
    const pa = precOf({ start: a, startAt: aAt });
    const pb = precOf({ start: b, startAt: bAt });
    const fine = p => p === 'd' || p === 'h';
    if (fine(pa) && fine(pb)) {
      const days = Math.round(d * 365.2425);
      if (days < 62) return `${days}일 뒤`;
      if (days < 730) return `${Math.round(days / 30.44)}개월 뒤`;
    } else if (pa !== 'y' && pb !== 'y') {
      const mo = Math.round(d * 12);
      if (mo < 24) return mo ? `${mo}개월 뒤` : '';
    }
    const y = Math.round(d);
    return y >= 1 ? `${y}년 뒤` : '같은 해';
  };
  /** 사건의 자유 날짜 글이 연대와 다르면 '원문 표기'로 남길 글(웹 dateNoteOf) */
  const dateNoteOf = x => {
    const s = String(x.date || '').trim();
    if (!s) return '';
    const r = HT.cal.parse(s);
    return r && r.ok && Math.abs(r.t - x.start) < 1e-6 ? '' : s;
  };
  /** 그 나라에서 그해에 쓰던 제도 칸(웹 institutionAt) */
  const institutionAt = (e, themeId, t) => {
    if (!e.polityUid || !model.institutionIndex) return null;
    for (const inst of model.institutionIndex.byPolity.get(e.polityUid) || []) {
      if (inst.themeId !== themeId) continue;
      const sp = (inst.spanList || []).find(s => s.start <= t && (t < s.end || (s.end === inst.endY && t <= s.end)));
      if (sp) return { inst, sp };
    }
    return null;
  };
  const rel = (tag, uid, text, when) => has({ tag, uid, text: text || '' }, 'when', when);
  const num = n => (n == null ? '—' : HT.groupDigits(Number(n)));
  const PAL = HT.PASTEL.map(c => c.id);
  for (const x of model.events || []) {
    if (x.kind !== 'event') continue;
    const law = x.law ? HT.readLaw(x.law) : null;
    if (law) {
      const list = law.name ? laws.get(`${keyOf(x)}|${law.name}`) || [{ e: x, law }] : null;
      const i = list ? list.findIndex(r => r.e === x) : -1;
      if (list && !x.treaty) {
        // 법의 내력 — 기본 기간 줄 자리(조약은 조약의 날짜 진행 표가 그 자리)
        const P = x.polityUid ? byUid.get(x.polityUid) : null;
        const rows = list.map(({ e, law: l }) => ({ word: l.act ? HT.lawActName(l.act) : '기록', t: e.startUnknown ? null : e.start, at: e.startAt, text: e.startUnknown ? '미정' : HT.formatWhen(e, 'start'), e, here: e === x }));
        const last = list[list.length - 1];
        if (!last || last.law.act !== 'repeal') {
          const ended = P && !P.ongoing && P.endY != null && P.endY < HT.CURRENT_YEAR;
          rows.push({ word: '폐지', t: null, text: '기록 없음', note: ended ? '— 나라가 끝날 때까지 쓴 것으로 봄' : '— 지금도 쓰는 것으로 봄' });
        }
        const out = rows.map((r, k) => {
          const prev = rows[k - 1];
          const o = { word: r.word, when: r.text };
          if (r.here) {
            o.here = 1;
            if (r.t != null) o.at = M(r.t);
          } else if (r.e) Object.assign(o, { uid: r.e.uid, title: r.e.title || '' });
          has(o, 'note', r.note);
          has(o, 'gap', prev && prev.t != null && r.t != null ? gapText(prev.t, prev.at, r.t, r.at) : '');
          return o;
        });
        put(x, 'x_lawHistory', has({ n: list.length, rows: out }, 'orig', dateNoteOf(x)));
      }
      put(
        x,
        'x_lawArts',
        (law.articles || []).map(a => {
          const s = HT.splitArticles(a)[0] || { no: '', title: '', text: a };
          return has(has(has({}, 'no', s.no), 'title', s.title), 'text', s.text);
        })
      );
      const related = [];
      const cur = institutionAt(x, 'law', x.start);
      if (cur && byUid.has(cur.inst.uid)) related.push(rel('그때의 법률', cur.inst.uid, cur.sp.name, HT.phaseRangeText(cur.sp, cur.inst.polityItem)));
      const prev = list && i > 0 ? list[i - 1].e : null;
      if (prev) related.push(rel('앞 고침', prev.uid, prev.title, HT.formatRange(prev)));
      put(x, 'x_lawRelated', related);
    }
    const el = x.election ? HT.readElection(x.election) : null;
    if (el) {
      // 결과의 모임마다: 단체 이름과 같으면 그 단체(이 나라에 있던 단체를 먼저), 아니면 팔레트 색(한 선거 안에서 겹치지 않게 다음 색으로) — 웹 voteRowsOf
      const used = new Set();
      const rows = (el.results || []).map(r => {
        const same = (model.groups || []).filter(g => g.name === r.who);
        const g = same.find(q => (q.withinList || []).concat(q.memberList || []).some(w => w.polityUid && w.polityUid === x.polityUid)) || same[0] || null;
        let color = g ? g.color : HT.autoColor(`party:${r.who}`);
        if (!g) for (let k = PAL.indexOf(color), n = 0; used.has(color) && n < PAL.length; n++) color = PAL[(k + n + 1) % PAL.length];
        used.add(color);
        return Object.assign({}, r, { group: g && byUid.has(g.uid) ? g : null, color });
      });
      const hasVotes = rows.some(r => r.votes != null);
      const hasSeats = rows.some(r => r.seats != null);
      const by = hasSeats ? 'seats' : hasVotes ? 'votes' : '';
      const total = by ? rows.reduce((s, r) => s + (r[by] || 0), 0) : 0;
      const part = r => `${r.who} ${by === 'seats' ? `${num(r.seats)}석` : `${num(r.votes)}표 · ${((100 * (r.votes || 0)) / total).toFixed(1)}%`}`;
      const o = {
        by,
        total,
        rows: rows.map(r => {
          const q = { who: r.who, color: r.color };
          if (r.group) q.uid = r.group.uid;
          if (r.votes != null) q.votes = r.votes;
          if (r.seats != null) q.seats = r.seats;
          if (r.won) q.won = 1;
          if (total > 0 && r[by]) q.part = part(r);
          return q;
        }),
      };
      if (total > 0) {
        const top = rows.reduce((a, r) => ((r[by] || 0) > (a[by] || 0) ? r : a), rows[0]);
        if (by === 'seats') {
          const half = Math.floor(total / 2) + 1;
          o.cap = top.seats >= half ? `과반 ${num(half)}석 — ${top.who} ${num(top.seats)}석` : `과반 ${num(half)}석 — 넘은 모임 없음 · 가장 많은 ${top.who} ${num(top.seats)}석`;
        } else o.cap = `가장 많은 표 — ${top.who} ${((100 * (top.votes || 0)) / total).toFixed(1)}%`;
      }
      if (rows.some(r => r.group)) o.linked = 1;
      put(x, 'x_vote', o); // 결과를 적지 않은 선거도 싣는다(rows 빈 목록 — 앱이 새 결과 상자 · 옛 선거 표를 가리는 표시)
      const related = [];
      const cur = institutionAt(x, 'election', x.start);
      if (cur && byUid.has(cur.inst.uid)) related.push(rel('그때의 선거 방식', cur.inst.uid, cur.sp.name, HT.phaseRangeText(cur.sp, cur.inst.polityItem)));
      const list = votes.get(keyOf(x)) || [];
      const i = list.findIndex(r => r.e === x);
      const office = r => (r.el.office && r.el.office !== el.office ? ` · ${r.el.office}` : '');
      if (i > 0) related.push(rel('앞 선거', list[i - 1].e.uid, `${list[i - 1].e.title}${office(list[i - 1])}`, HT.formatRange(list[i - 1].e)));
      if (i >= 0 && i < list.length - 1) related.push(rel('다음 선거', list[i + 1].e.uid, `${list[i + 1].e.title}${office(list[i + 1])}`, HT.formatRange(list[i + 1].e)));
      put(x, 'x_voteRelated', related);
    }
  }
}

/* ════════════════════════════════════════════════════════════════════════════════════════════
 *  찾을 글 x_find — js/viewer.js runSearch의 찾을 글(_hay · hit)을 그대로 옮긴 것(설계 A 3-2). 웹 몫 W0으로 HT.searchHay가 생기면 그것을 부른다.
 *  hay: 소문자 · **이름 · 제목 · 설명은 뺀다**(이름은 엔진의 이름 표 name이, 설명은 엔진이 $.description을 이어 붙이고, 사건의 제목 · 설명은 본문 색인에 이미 있다).
 *  cells: 칸 참조('leader:3' · 'era:2' · 'capital:0' — 엔진 names.cell_ref와 같은 글) → 그 칸의 찾을 글(칸 이름도 넣는다 — 띠에 적히는 이름이
 *         묘호 · 시기 이름일 수 있어). 도읍 칸은 지명 사전의 원어까지.
 *  sub · span · color · row: 단체 · 제도의 결과 줄 곁글(웹 결과 줄의 글) · 기간(분) · 색 · 줄을 빌릴 정권 uid.
 *  날짜 · 간지 검색에는 단체 · 제도 · 가문을 넣지 않는다(엔진 search_year의 몫 — 웹도 !dq && !ganji일 때만).
 * ════════════════════════════════════════════════════════════════════════════════════════════ */
function findOf(ctx) {
  const { model, HT } = ctx;
  const found = new Map();
  // 웹 몫 W0(HT.searchHay를 js/core.js로 떼기)은 아직 없다 — 그 함수의 꼴이 정해지면 아래 식 대신 그것 하나를 부른다(웹과 내보내기가 같은 함수).
  const trackName = id => (model.trackMap.get(id) || { name: id }).name || '';
  const str = v => (v == null ? '' : String(v));
  // 웹은 칸을 ' '로 잇기만 한다 — 낱말에는 빈칸이 없으므로 빈칸을 하나로 줄여도 찾히는 것이 같다(기록만 작아진다).
  const join = parts => parts.map(str).join(' ').replace(/\s+/g, ' ').trim().toLowerCase();
  const names = HT.namesText;
  const treatyHay = x => {
    const t = x && x.treaty ? HT.readTreaty(x.treaty) || {} : null;
    if (!t) return '';
    const refs = (x.treatyRefs && x.treatyRefs.parties) || [];
    return ['조약', HT.treatyTypeName(t.type), t.formal, t.place, (t.languages || []).join(' ')]
      .concat((t.parties || []).map(p => `${p.polity || ''} ${p.role || ''} ${HT.signersText(p.signatories)}`), refs.map(r => r.name), (t.articles || []).map(a => `${a.no || ''} ${a.title || ''}`))
      .filter(Boolean)
      .join(' ');
  };
  const put = (x, o) => {
    for (const k of Object.keys(o)) if (o[k] == null || o[k] === '' || (typeof o[k] === 'object' && !Array.isArray(o[k]) && !Object.keys(o[k]).length)) delete o[k];
    if (Object.keys(o).length) found.set(x.uid, o);
  };
  /* 시대 · 사건(state.visible): 이름 · 설명 · 태그 · 날짜 · 트랙 · 관점 · 민족 · 종류 · 소속 · 조약 · 실재성 · 이름 목록 · 장소 */
  const item = x => [
    (x.tags || []).join(' '), x.date, trackName(x.track),
    (x.perspectives || []).map(v => `${v.title || ''} ${v.description || ''}`).join(' '),
    x.peopleName || x.people || '', x.polityKind && x.polityKind !== 'state' ? HT.kindName(x.polityKind) : '', x.partOfName || '',
    treatyHay(x),
    HT.historicityOf(x) ? HT.historicityName(HT.historicityOf(x)) : '', x.historicityNote || '',
    names(x.names), x.place || '',
  ];
  for (const x of model.periods || []) {
    const o = { hay: join(item(x)) };
    // 칸(HT.CELL_KINDS의 모든 종류 — x.kind === 'period'만): 이름 · 묘호 · 시호 · 이름 · 도시 · 시기 이름 · 묶음 · 메모 · 이름 목록 · 도읍의 지명 원어
    if (x.kind === 'period') {
      const cells = {};
      for (const K of HT.CELL_KINDS)
        HT.cellsOf(x, K).forEach((c, i) => {
          if (!c) return;
          const hay = join([c.name, c.temple, c.title, c.given, c.city, c.label, c.group, c.note, names(c.names), K.id === 'capital' ? names((HT.placeOf(model, c.city) || {}).names) : '']);
          if (hay) cells[`${K.id}:${i}`] = hay;
        });
      o.cells = cells;
    }
    put(x, o);
  }
  for (const e of model.events || []) put(e, { hay: join(item(e)) });
  /* 인물: 다른 이름 · 역할 · 가문 · 태그 · 트랙 · 섬긴 정권(이름 · 직함 · 메모) · 이름 목록 */
  for (const f of model.figures || [])
    put(f, { hay: join([(f.aka || []).join(' '), f.role, f.house, (f.tags || []).join(' '), trackName(f.track), (f.services || []).map(s => `${s.polityName || ''} ${s.office || ''} ${s.note || ''}`).join(' '), names(f.names)]) });
  /* 계보 전용 인물(D1): 같은 찾을 글(활동 기록은 띠에 그리지 않으므로 뺌) · 결과 줄 곁글 '계보 전용 · <가문 · 파 이름>'(가문이 없으면 '계보 전용') — 해 칸은 비운다 */
  for (const f of model.lineageFigures || []) {
    const n = HT.personOf ? HT.personOf(model, f) : null;
    const hid = (n && n.houseId) || f.houseId || '';
    const h = hid && model.houseMap ? model.houseMap.get(hid) : null;
    put(f, { hay: join([(f.aka || []).join(' '), f.role, f.house, (f.tags || []).join(' '), trackName(f.track), names(f.names)]), sub: h ? `계보 전용 · ${h.name || h.id}` : '계보 전용' });
  }
  /* 시대 구분: 메모 · 트랙 이름(설명은 웹도 보지 않는다 — 엔진도 붙이지 않는다) */
  for (const ep of model.epochs || []) put(ep, { hay: join([ep.note, ep.trackName]) });
  /* 대범위: 표시 이름 · 메모 · 트랙 이름 · '대범위' · 구성 정권 이름 */
  for (const s of model.scopes || []) put(s, { hay: join([s.label, s.note, s.trackName, '대범위', (s.members || []).map(m => m.name).join(' ')]) });
  /* 가문: 성 · 본관 · 시조 · 이름 목록 · 성씨 사전의 이름 목록 */
  for (const h of model.houses || [])
    put(h, { hay: join([h.surname, h.seat, h.founder, names(h.names), names(((model.surnameMap && model.surnameMap.get(h.surnameId)) || {}).names)]) });
  /* 단체: 종류 · '단체' · 메모 · 있던 나라 · 구성 나라 · 구성원(적은 이름 · 사람 자리의 이름) · 이름 목록 / 결과 줄 곁글 '단체 · 종류' */
  for (const g of model.groups || [])
    put(g, {
      hay: join([g.typeName, '단체', g.note, (g.withinList || []).concat(g.memberList || []).map(r => r.name).join(' '), (g.peopleList || []).map(r => `${r.name} ${r.person ? r.person.name : ''}`).join(' '), names(g.names)]),
      sub: `단체${g.typeName ? ` · ${g.typeName}` : ''}`,
      span: spanOfMinutes(g.start, g.endY),
      color: g.color || '',
      row: g.polityUid || '',
    });
  /* 제도: '제도' · 갈래 · 칸 이름 · 칸 메모 · 이름 목록 · 주제의 이름 목록 / 결과 줄 곁글 '제도 · 갈래' */
  for (const it of model.institutions || [])
    put(it, {
      hay: join(['제도', it.family, (it.spanList || []).map(sp => `${sp.name} ${sp.note || ''}`).join(' '), names(it.names), names(((model.themeMap && model.themeMap.get(it.themeId)) || {}).names)]),
      sub: `제도${it.family ? ` · ${it.family}` : ''}`,
      span: spanOfMinutes(it.start, it.endY),
      color: it.color || '',
      row: it.polityUid || '',
    });
  return found;
}

/** 구간 [a, b] → [분, 분] (뒤집히면 앞쪽으로 맞춤). 시작이 없으면 null. */
function spanOfMinutes(a, b) {
  const lo = a == null || !Number.isFinite(a) ? null : minute(a);
  if (lo == null) return null;
  const hi = b == null || !Number.isFinite(b) ? null : minute(b);
  return [lo, hi == null ? lo : Math.max(lo, hi)];
}

/** 그림 · 글꼴의 바이트(데이터 URL)는 싣지 않고 크기만 — {"$bytes": 글자 수}(A3에서 blobs 표로 · 설계 7절 확인거리 5). */
function dropBytes(v) {
  if (typeof v === 'string') return /^data:/i.test(v) ? { $bytes: v.length } : v;
  if (Array.isArray(v)) return v.map(dropBytes);
  if (v && typeof v === 'object') {
    for (const k of Object.keys(v)) v[k] = dropBytes(v[k]);
    return v;
  }
  return v;
}

export function contribute(ctx, out) {
  const { model, HT } = ctx;
  // 계보 뼈대(D1 — export/kin.mjs): 웹 도우미 HT.kinSkeleton이 있을 때만. 미리 푼 값(x_kin · x_lineage의 kinAt)이 이것을 가리킨다.
  const kin = kinCollect(model, HT);
  if (kin) kin.roots = new Set(kin.records.filter(r => r.uid === r.rootUid).map(r => r.uid));
  // 본문이 있는 문서의 열쇠(머리 칩의 구분 · 민족 → 문서 창) — 문서 모듈(docs)이 먼저 실었다
  const docBodies = new Set();
  for (const e of out.entities) if (e.kind === 'doc' && e.uid.startsWith('doc:') && !JSON.parse(e.json).empty) docBodies.add(e.uid.slice(4));
  const extra = crossRefs(ctx, kin, docBodies);
  /* 리메이크 3단계(계약 1-1 초안): 인물의 칭호 묶음 x_titles — 사람 창이 그대로 그림(HT.personTitles와 같은 칸 · 같은 차례).
     [{ uid: 객체 띠 uid, cell: 칸 순번, office: '지도자' | '내각', name: 객체 이름, start · end: 분, rank: 지위 }] · 칭호가 없으면 싣지 않음 */
  for (const n of model.persons || []) {
    const fu = n && n.figure && n.figure.uid;
    if (!fu) continue;
    const titles = (n.cells || [])
      .filter(q => q && q.p && q.c && (q.kind === 'leader' || q.kind === 'cabinet'))
      .map(q => {
        const sp = HT.cellSpan(q.c, q.p, q.ref);
        return { uid: q.p.uid, cell: q.i, office: q.kind === 'leader' ? '지도자' : '내각', name: q.p.name || q.p.id || '', start: minute(sp.start), end: minute(sp.end ?? q.p.endY), rank: q.c.rank || '' };
      })
      .sort((a, b) => (a.start ?? 0) - (b.start ?? 0));
    if (!titles.length) continue;
    if (!extra.has(fu)) extra.set(fu, {});
    extra.get(fu).x_titles = titles;
  }
  const finds = findOf(ctx);
  const kinds = {};
  let bytes = 0;
  let xBytes = 0;
  let findBytes = 0;
  const refs = new Map(); // 기록 uid → 본문의 $ref uid들
  /* 자료집 귀속(pack — 이 배치의 packs[] 순번): 모델 항목은 packId → uid의 앞머리(ctx.packOf). 저절로 생긴 사전 항목(지명 · 성씨 · 가문 — packId가 빈 글)은
     그것을 쓴 항목 가운데 켠 차례로 가장 앞선 DLC(그 DLC를 끄면 사라질 쓰임만 남지 않게). 아무도 쓰지 않으면 기본(0). */
  const packOfItem = x => ctx.packOf(x);
  const memo = new Map();
  const autoPack = (x, users) => {
    if (x.packId) return packOfItem(x);
    if (memo.has(x.uid)) return memo.get(x.uid);
    memo.set(x.uid, 0); // 고리를 막는다
    let best = Infinity;
    for (const u of users()) if (u != null && u < best) best = u;
    const v = Number.isFinite(best) ? best : 0;
    memo.set(x.uid, v);
    return v;
  };
  const placePack = pl =>
    autoPack(pl, () => [
      ...(pl.uses || []).map(u => (u.item ? packOfItem(u.item) : u.mapId && model.mapMap && model.mapMap.get(u.mapId) ? packOfItem(model.mapMap.get(u.mapId)) : null)),
      ...(pl.children || []).map(id => (model.placeMap.get(id) ? placePack(model.placeMap.get(id)) : null)),
    ]);
  const housePack = h => autoPack(h, () => (h.members || []).map(mb => (mb.item ? packOfItem(mb.item) : null)));
  const surnamePack = sn => autoPack(sn, () => (sn.houses || []).map(id => (model.houseMap.get(id) ? housePack(model.houseMap.get(id)) : null)));
  const packFor = (x, kind) => (kind === 'place' ? placePack(x) : kind === 'surname' ? surnamePack(x) : kind === 'house' ? housePack(x) : packOfItem(x));

  const push = (uid, kind, body, pack) => {
    const json = JSON.stringify(body);
    bytes += json.length;
    kinds[kind] = (kinds[kind] || 0) + 1;
    out.entities.push({ uid, kind, json, pack });
  };
  const add = (x, strip = null) => {
    if (!x || typeof x.uid !== 'string' || !x.uid) return;
    const kind = x.itemKind || (HT.itemKindOf ? HT.itemKindOf(x) : x.kind) || 'period';
    const mine = new Set();
    let body = plain(x, mine);
    if (strip) body = strip(body);
    refs.set(x.uid, mine);
    const more = extra.get(x.uid);
    if (more) {
      xBytes += JSON.stringify(more).length;
      Object.assign(body, more); // 미리 푼 값은 뒤에(지금의 값은 그대로)
    }
    const find = finds.get(x.uid);
    if (find) {
      findBytes += JSON.stringify(find).length;
      body.x_find = find;
    }
    push(x.uid, kind, body, packFor(x, kind));
  };
  for (const p of model.periods || []) add(p); // 정권 · 기관(overlay) · 문화 · 왕조가 같은 틀에 들어 있다(itemKind로 갈린다)
  for (const e of model.events || []) add(e);
  for (const f of model.figures || []) add(f);
  // 계보 전용 인물(D1): 갈래는 인물(figure)이고 본문은 활동 칸(활동 기록 · 중요도)을 뺀 것 — 띠에 그리지 않는다(확정 설계 8-1).
  for (const f of model.lineageFigures || [])
    add(f, body => {
      for (const k of ['services', 'service', 'importance']) delete body[k];
      return body;
    });
  for (const e of model.epochs || []) add(e);
  for (const s of model.scopes || []) add(s);
  for (const h of model.houses || []) add(h); // 가문은 연표에 제 줄이 없어 byUid에 들지 않는다 — uid는 'house:<id>'
  /* 형식 3의 새 기록 — 가문 · 단체 · 제도는 모델 차례 그대로(엔진이 이 차례로 검색 결과를 낸다 · 제도는 모델이 주제 차례로 둔다). */
  for (const g of model.groups || []) add(g); // 단체 — uid '<DLC id>/<id>'
  for (const it of model.institutions || []) add(it); // 제도
  for (const pl of model.places || []) add(pl); // 지명 — uid 'place:<id>'
  for (const sn of model.surnames || []) add(sn); // 성씨 — uid 'surname:<id>'
  if ((model.themes || []).length) {
    // 주제 사전 하나 — `name` 칸이 없어 이름 표에 들지 않는다(엔진의 허용 목록 밖이기도 하다).
    const list = model.themes.map(t => {
      const o = { id: t.id, name: t.name || '', color: t.color || '', order: t.order };
      if (t.auto) o.auto = 1;
      if (Array.isArray(t.names) && t.names.length) o.names = plain(t.names);
      return o;
    });
    push('themes', 'themes', { list }, 0);
  }
  for (const v of model.views || []) add(v); // 모아 보기 판 — 나르기만(판 화면 · 판 변형은 A3)
  // 지도: 장면(scenes)은 x_scenes로 풀어 싣고 본문에서는 뺀다(틀 frames와 같은 것을 두 번 싣지 않게). 그림 데이터 URL은 크기만.
  for (const m of model.maps || []) add(m, body => {
    delete body.scenes;
    delete body.regionMap;
    return dropBytes(body);
  });
  for (const f of model.fonts || []) add(f, dropBytes); // 글꼴: src(데이터 URL)는 크기만
  // 계보 뼈대 기록(갈래 kin — 열 꼴 JSON · 나눈 덩어리 포함). 귀속은 뿌리 가문의 DLC(가문이 없는 지도자의 뼈대는 그 정권의 DLC).
  let kinBytes = 0;
  for (const r of (kin && kin.records) || []) {
    const pack = r.houseId && model.houseMap.get(r.houseId) ? housePack(model.houseMap.get(r.houseId)) : r.polityUid && model.byUid.get(r.polityUid) ? packOfItem(model.byUid.get(r.polityUid)) : 0;
    const before = bytes;
    push(r.uid, 'kin', r.body, pack);
    kinBytes += bytes - before;
  }

  const seen = new Set();
  for (const e of out.entities) {
    if (seen.has(e.uid)) throw new Error(`항목 기록의 uid가 겹칩니다: ${e.uid}`);
    seen.add(e.uid);
  }
  /* 가리키는 uid는 모두 제 기록이 있어야 한다(상세 창이 한 번 더 찾아 나서지 않게) — 미리 푼 값(x_)의 uid · 본문의 $ref · 찾을 글의 빌린 줄(x_find.row).
     경계는 [lo, hi]가 뒤집히지 않아야 한다. 못 찾은 것은 uid 없이 이름만(missing:1) 싣는 것이 약속이므로 예외 목록을 두지 않는다. */
  let links = 0;
  let refLinks = 0;
  const check = (v, uid) => {
    if (Array.isArray(v)) return v.forEach(q => check(q, uid));
    if (!v || typeof v !== 'object') return;
    if (typeof v.uid === 'string' && v.uid) {
      links++;
      if (!seen.has(v.uid)) throw new Error(`미리 푼 값이 없는 기록을 가리킵니다: ${uid} → ${v.uid}`);
    }
    if (typeof v.nation === 'string' && v.nation && !seen.has(v.nation)) throw new Error(`구성원의 나라 기록이 없습니다: ${uid} → ${v.nation}`);
    for (const k of Object.keys(v)) check(v[k], uid);
  };
  for (const [uid, more] of extra) {
    for (const [k, v] of Object.entries(more)) {
      if (k === 'x_cellBounds') {
        for (const [ref, b] of Object.entries(v)) if (!(b[0] <= b[1])) throw new Error(`칸의 경계가 뒤집혔습니다: ${uid} ${ref} ${b}`);
      } else check(v, uid);
    }
  }
  for (const [uid, find] of finds) {
    if (find.row && !seen.has(find.row)) throw new Error(`찾을 글의 빌린 줄이 없는 기록을 가리킵니다: ${uid} → ${find.row}`);
    if (find.span && !(find.span[0] <= find.span[1])) throw new Error(`찾을 글의 기간이 뒤집혔습니다: ${uid}`);
  }
  for (const [uid, mine] of refs)
    for (const to of mine) {
      refLinks++;
      if (!seen.has(to)) throw new Error(`본문의 $ref가 없는 기록을 가리킵니다: ${uid} → ${to}`);
    }
  /* 계보(D1): x_kin · x_lineage의 kinAt이 가리키는 뼈대 기록, 뼈대 기록의 꼬투리 · 위 덩어리 · 파 표의 가문이 모두 있어야 한다. 번호는 한 벌 안. */
  if (kin) {
    const kinRec = new Map(kin.records.map(r => [r.uid, r.body]));
    const totalOf = key => {
      // 나눈 뼈대는 꼬투리 아래까지 센 한 벌 마디 수
      let n = 0;
      const walk = uid => {
        const b = kinRec.get(uid);
        if (!b) throw new Error(`뼈대 덩어리 기록이 없습니다: ${uid}`);
        n += b.n;
        for (const st of Object.values(b.stubs)) {
          n -= 1;
          walk(st.key);
        }
      };
      walk(key);
      return n;
    };
    const pointAt = (uid, key, at, chunk) => {
      if (!kinRec.has(key)) throw new Error(`뼈대 기록이 없는 곳을 가리킵니다: ${uid} → ${key}`);
      if (at != null && !(Number.isInteger(at) && at >= 0 && at < totalOf(key))) throw new Error(`뼈대 번호가 범위 밖입니다: ${uid} → ${key} ${at}`);
      if (chunk != null && !kinRec.has(chunk)) throw new Error(`뼈대 덩어리 기록이 없습니다: ${uid} → ${chunk}`);
    };
    for (const [uid, more] of extra) {
      if (more.x_kin) pointAt(uid, more.x_kin.key, more.x_kin.at, more.x_kin.chunk);
      for (const [ref, l] of Object.entries(more.x_lineage || {})) if (l.kinAt) pointAt(`${uid} ${ref}`, l.kinAt[0], l.kinAt[1], null);
    }
    for (const [uid, b] of kinRec) {
      for (const br of b.branches) if (br.uid && !seen.has(br.uid)) throw new Error(`뼈대의 파 표가 없는 가문을 가리킵니다: ${uid} → ${br.uid}`);
      for (const st of Object.values(b.stubs)) if (!kinRec.has(st.key)) throw new Error(`꼬투리가 없는 덩어리를 가리킵니다: ${uid} → ${st.key}`);
      if (b.root && !kinRec.has(b.root.up)) throw new Error(`덩어리의 위 기록이 없습니다: ${uid} → ${b.root.up}`);
      if (b.par.length !== b.n || b.key.length !== b.n) throw new Error(`뼈대 열의 길이가 n과 다릅니다: ${uid}`);
    }
  }
  const MB = n => Math.round((n / 1048576) * 100) / 100;
  ctx.notes.항목기록 = Object.assign({ 크기MB: MB(bytes), 미리푼값MB: MB(xBytes), 찾을글MB: MB(findBytes), 이은고리: links, 본문고리: refLinks }, kinds);
  if (kin) ctx.notes.계보 = Object.assign({ 기록MB: MB(kinBytes) }, kin.notes);
}

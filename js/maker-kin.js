/* 역사 연표 — 메이커의 계보 입력 (메이커만)
 *
 * 계층 입력 창(한 줄 = 한 사람 · 들여쓰기 = 세대) · 머리 칩 고치기(HT.maker.kin.editHead) 같은 메이커 쪽 계보 도구를 둡니다.
 * 기준: D1 확정 설계(docs/설계-10건/ 폴더의 '1-2 … 가문-확정' 문서) 7절(D1-M1). 이음새의 꼴은 같은 문서 끝 '구현 이음새 기록'의 D1-M1 절.
 *
 * 밖으로 내는 것 (이름 · 꼴은 계약 — 바꾸지 않습니다)
 *   HT.maker.kin.editHead({ kind: 'polity' | 'house', uid, field, anchor?, value?, remove? }) → Promise<boolean>
 *     승계표 · 세계표 머리 칩(W2 — js/kin-view.js · viewer.js)이 메이커 미리 보기에서 칩 ✏️ · 점선 빈 칩 · 꼬리표 ✕ · ＋ 꼬리표를 누르면 부릅니다.
 *   HT.maker.kin.ready() → 작업본을 들고 있어 고칠 수 있는지 (✏️를 보일지)
 *   HT.maker.kin.outline({ uid?, text? }) → 계층 입력 창 (uid = 뿌리 사람, text = 붙여넣은 족보 들여쓰기 글)
 *   HT.maker.kin.addRelative({ key, rel?, anchor? }) · removePerson({ key }) · removable(key) → 세계표 · 승계표 창 안의 사람 더하기(자식 · 형제 · 배우자 · 부모) · 지우기
 *   HT.makerKin.planPeople · applyPeople → 통째 붙여넣기의 인물 층(js/maker-paste.js)을 나라를 저장한 뒤 내 DLC의 인물로
 *   HT.makerKin — 화면 없이 도는 계산(사람 참조 글 · 사람 찾기 · 계층 글 읽기 · 적용 계획 · 칩 고침)과 mount(ctx, api)(js/maker.js의 start가 부름) ·
 *     사람 찾기 상자 attachFinder(표 · 바탕 자료 · 한꺼번에 고치기의 사람 칸) · 검사 창의 알림 checks
 *
 * 사람을 가리키는 글(7-4): 같은 트랙에서 그 이름이 하나뿐이면 이름, 겹치면 인물 id(남의 팩은 uid) · 지도자 칸 { polity, leader, start }.
 * 파조는 늘 id(남의 팩은 uid) · '나라:지도자@해'로 적습니다(2-4 라 — 시조 · 파조 글은 경고 없이 찾으므로 이름이 겹치면 엉뚱한 사람에 붙음).
 */
(function () {
  'use strict';
  const HT = window.HT;
  const str = v => (v == null ? '' : String(v).trim());
  const arr = v => (Array.isArray(v) ? v : []);
  const esc = s => (HT.escapeHtml ? HT.escapeHtml(s) : String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]));
  const clone = x => JSON.parse(JSON.stringify(x));
  let ctx = null;
  let api = null;

  /* ================= 사람 찾기 (모델 — 띠 인물 + 계보 전용 인물 · 지도자 칸) ================= */
  /** 모델의 인물: 띠 인물(model.figures) + 계보 전용 인물(model.lineageFigures — D1-W1). 계보 전용 표시만 있고 아직 떼지 않은 모델이어도 같은 목록 */
  const figuresOf = model => {
    const seen = new Set();
    const out = [];
    for (const f of arr(model && model.figures).concat(arr(model && model.lineageFigures))) if (f && !seen.has(f.uid)) { seen.add(f.uid); out.push(f); }
    return out;
  };
  const isLineage = f => !!f && f.lineageOnly === true;
  const namesOfFig = f => [...new Set([f.name].concat(arr(f.aka), arr(f.names).map(n => n && n.text)).map(str).filter(Boolean))];
  const leaderNames = c => [c.name, c.temple, c.title, c.given].map(str).filter(Boolean);
  const leaderName = c => leaderNames(c)[0] || '';
  const ixCache = new WeakMap();
  /** 모델마다 한 번: 인물(uid · 이름) · 지도자 칸(이름) · 사람 자리의 차례 */
  function peopleIndex(model) {
    if (!model) return { figs: [], byName: new Map(), figByUid: new Map(), cells: [], cellByName: new Map(), order: new Map() };
    let ix = ixCache.get(model);
    if (ix) return ix;
    const figs = figuresOf(model);
    const byName = new Map();
    const figByUid = new Map();
    for (const f of figs) {
      figByUid.set(f.uid, f);
      for (const n of namesOfFig(f)) (byName.get(n) || byName.set(n, []).get(n)).push(f);
    }
    const cells = [];
    const cellByName = new Map();
    for (const p of arr(model.periods)) {
      if (HT.itemKindOf(p) !== 'period') continue;
      arr(p.leaders).forEach((c, i) => {
        const x = { p, i, c, key: `c:${p.uid}|leader:${i}` };
        cells.push(x);
        for (const n of leaderNames(c)) (cellByName.get(n) || cellByName.set(n, []).get(n)).push(x);
      });
    }
    const order = new Map(arr(model.persons).map((n, i) => [n, i]));
    ix = { figs, byName, figByUid, cells, cellByName, order };
    ixCache.set(model, ix);
    return ix;
  }
  const nodeOfKey = (model, key) => (model && model.personIndex && key ? model.personIndex.get(key) || null : null);
  /** 사람 자리 → 적을 대상 { node, key, fig, cell, name, track, packId, unknown } */
  function targetOfNode(n) {
    if (!n) return null;
    const fig = n.figure || null;
    const cx = !fig ? arr(n.cells).find(x => x.kind === 'leader') || null : null;
    return { node: n, key: n.key, fig, cell: cx ? { p: cx.p, i: cx.i, c: cx.c } : null, name: n.unknown ? '미상' : fig ? fig.name : cx ? leaderName(cx.c) || n.name : n.name, track: fig ? fig.track : cx ? cx.p.track : '', packId: fig ? fig.packId : cx ? cx.p.packId : '', unknown: !!n.unknown };
  }
  const targetOfFig = (model, f) => targetOfNode(HT.personOf ? HT.personOf(model, f) : null) || { node: null, key: `f:${f.uid}`, fig: f, cell: null, name: f.name, track: f.track, packId: f.packId, unknown: false };
  const targetOfCell = (model, x) => targetOfNode(nodeOfKey(model, x.key)) || { node: null, key: x.key, fig: null, cell: { p: x.p, i: x.i, c: x.c }, name: leaderName(x.c), track: x.p.track, packId: x.p.packId, unknown: false };
  /** 사람 자리 열쇠 → 대상 */
  const targetOfKey = (model, key) => {
    const n = nodeOfKey(model, key);
    if (n) return targetOfNode(n);
    const f = String(key).startsWith('f:') ? peopleIndex(model).figByUid.get(String(key).slice(2)) : null;
    return f ? targetOfFig(model, f) : null;
  };
  const sameTarget = (a, b) => !!a && !!b && (a.node && b.node ? a.node === b.node : a.key === b.key);
  const uniqTargets = list => {
    const out = [];
    for (const t of list) if (t && !out.some(o => sameTarget(o, t))) out.push(t);
    return out;
  };
  /**
   * 친 글(사람 참조 — 인물 id · uid · 이름 · '나라:지도자@해') → 그 글이 가리킬 수 있는 사람들 [대상].
   * env = { model, draftId }. id · uid · 칸 참조는 하나, 이름은 같은 이름의 인물 모두(인물이 없으면 지도자 칸 — 같은 사람의 칸은 하나로)
   */
  function findPeople(text, env) {
    const model = env.model;
    const s = str(text);
    if (!s || !model) return [];
    const ix = peopleIndex(model);
    const byId = ix.figByUid.get(s.includes('/') ? s : `${env.draftId || ''}/${s}`) || (!s.includes('/') && ix.figs.find(f => f.id === s));
    if (byId) return [targetOfFig(model, byId)];
    const r = HT.readPersonRef(s);
    if (r && typeof r === 'object') {
      const hit = ix.cells.filter(x => (x.p.name === r.polity || x.p.id === r.polity || x.p.uid === r.polity) && (!r.track || x.p.track === r.track) && leaderNames(x.c).includes(r.leader));
      const at = r.start == null ? hit : hit.filter(x => Math.floor(x.c.start + 1e-9) === Math.floor(r.start + 1e-9));
      return uniqTargets((at.length ? at : hit).slice(0, 1).map(x => targetOfCell(model, x)));
    }
    const figs = arr(ix.byName.get(s));
    if (figs.length) return uniqTargets(figs.map(f => targetOfFig(model, f)));
    return uniqTargets(arr(ix.cellByName.get(s)).map(x => targetOfCell(model, x)));
  }
  /** 후보 가운데 하나 — 하나뿐이면 그것, 여럿이면 같은 트랙의 것이 하나뿐일 때만 (아니면 null — 고를 수 없음) */
  function pickOne(list, track) {
    if (list.length === 1) return list[0];
    const same = list.filter(t => t.track === track);
    return same.length === 1 ? same[0] : null;
  }
  /** 이번에 함께 만드는 사람 목록의 이름 표 (목록마다 한 번 — 수만 줄을 붙여도 이름 찾기가 줄 수에 비례) */
  const extraCache = new WeakMap();
  const extraByName = extra => {
    let m = extraCache.get(extra);
    if (!m) {
      m = new Map();
      for (const e of extra) { const n = str(e.name); (m.get(n) || m.set(n, []).get(n)).push(e); }
      extraCache.set(extra, m);
    }
    return m;
  };
  /** 같은 트랙 · 같은 이름의 나라가 여럿이면 id(제 팩) · uid, 아니면 이름 — 지도자 칸 참조의 나라 자리 */
  const polityWord = (model, p, draftId) => (arr(model.periods).filter(q => q !== p && HT.itemKindOf(q) === 'period' && q.track === p.track && q.name === p.name).length ? (p.packId === draftId ? p.id : p.uid) : p.name);
  /**
   * 사람을 가리키는 글 (확정 설계 7-4): 이름으로 찾아도 이 사람이 나오면 이름, 아니면 인물 id(제 팩 · 이번에 만드는 사람) · uid(남의 팩) · 지도자 칸 { track?, polity, leader, start }.
   * t = 대상(targetOfNode · targetOfFig · 새 사람 { isNew: true, id, name, track }).
   * env = { model, draftId, track(적는 쪽의 트랙), extra(이번에 함께 만드는 새 사람 [{ id, name, track }] · 이름을 바꾸는 제 인물 [{ id, uid, name, track }]), strict(이름을 쓰지 않음 — 파조) }
   * 이름 '미상'(이름 미상의 사람) · ':' '@'가 든 이름은 늘 id (글로 적으면 줄마다 새 빈 고리 · 칸 참조로 읽힘)
   */
  function whoRef(t, env) {
    if (!t) return '';
    const model = env.model;
    const draftId = env.draftId || '';
    const track = env.track || '';
    const extra = arr(env.extra);
    const ix = peopleIndex(model);
    const name = str(t.name);
    const risky = env.strict || !name || HT.isUnknownWho(name) || /[:@/]/.test(name) || t.unknown;
    if (t.isNew || t.fig) {
      const own = t.isNew || t.fig.packId === draftId;
      const id = t.isNew ? t.id : own ? t.fig.id : t.fig.uid;
      if (risky) return id;
      const me = t.isNew ? `new:${t.id}` : t.fig.uid;
      /* 이름으로 찾을 때의 후보(모델의 인물 + 이번에 만드는 · 이름을 바꾸는 사람 + 이 사람): 하나뿐이거나, 같은 트랙의 것이 이 사람 하나뿐이면 이름 (core.js의 인물 찾기 점수와 같은 뜻) */
      const seen = new Set([me]);
      let total = 1;
      let sameTrack = t.track === track ? 1 : 0;
      const count = (cid, tr) => { if (seen.has(cid)) return; seen.add(cid); total++; if (tr === track) sameTrack++; };
      for (const f of arr(ix.byName.get(name))) count(f.uid, f.track);
      for (const e of arr(extraByName(extra).get(name))) count(e.uid || `new:${e.id}`, e.track); // e.uid — 이번에 이름을 바꾸는 제 인물(모델에는 옛 이름)
      if (total === 1) return name;
      return t.track === track && sameTrack === 1 ? name : id;
    }
    if (t.cell) {
      const { p, c } = t.cell;
      const nm = leaderName(c);
      const obj = () => Object.assign(p.track !== track ? { track: p.track } : {}, { polity: polityWord(model, p, draftId), leader: nm }, isFinite(c.start) ? { start: Math.floor(c.start + 1e-9) } : {});
      if (risky || !nm || ix.byName.has(nm) || extraByName(extra).has(nm)) return obj();
      const all = arr(ix.cellByName.get(nm));
      const keyOf = x => { const n = nodeOfKey(model, x.key); return n ? n.key : x.key; };
      const mine = t.node ? t.node.key : `c:${p.uid}|leader:${t.cell.i}`;
      const same = all.filter(x => x.p.track === track);
      const pool = same.length ? same : all;
      return pool.length && pool.every(x => keyOf(x) === mine) ? nm : obj();
    }
    return name;
  }
  /** 사람 참조 → 한 칸 글 (표 · 폼의 칸) */
  const refText = r => (r && typeof r === 'object' ? HT.personRefText(r) : str(r));

  /* ---------- 인물의 부모 줄 (표의 부 · 모 · 양부 · 생부 열) ---------- */
  /** 그 역할의 첫 부모 줄의 글 (미상이면 '미상') */
  function parentText(x, role) {
    const q = arr(x && x.parents).find(p => p && typeof p === 'object' && (HT.parentRole(p.as) || str(p.as)) === role);
    if (!q) return '';
    return q.whoUnknown === true || HT.isUnknownWho(q.who) ? '미상' : refText(q.who);
  }
  /** 그 역할의 첫 부모 줄만 바꿉니다 — 다른 줄 · 그 줄의 확실성 · 메모는 그대로. ref가 비면 그 줄을 지우고, '미상'이면 whoUnknown */
  function setParent(x, role, ref) {
    const list = arr(x.parents).slice();
    const i = list.findIndex(p => p && typeof p === 'object' && (HT.parentRole(p.as) || str(p.as)) === role);
    const empty = ref == null || (typeof ref === 'string' && !ref.trim());
    if (empty) {
      if (i >= 0) list.splice(i, 1);
    } else {
      const who = typeof ref === 'string' && HT.isUnknownWho(ref) ? { whoUnknown: true } : { who: ref };
      const keep = i >= 0 ? Object.fromEntries(Object.entries(list[i]).filter(([k]) => !['who', 'whoUnknown', 'name'].includes(k))) : { as: role };
      const row = Object.assign(who, keep);
      if (!row.as) row.as = role;
      if (i >= 0) list[i] = row;
      else list.push(row);
    }
    if (list.length) x.parents = list;
    else delete x.parents;
  }

  /* ================= 계층 입력 — 글 읽기 · 쓰기 (확정 설계 7-2 ⑤) ================= */
  const INDENT = '  ';
  /** 들여쓰기 글(탭 하나 = 한 세대 · 공백 둘 = 한 세대) → 세대 수 */
  const depthOf = lead => {
    let tabs = 0;
    let spaces = 0;
    for (const ch of lead) if (ch === '\t') tabs++; else spaces++;
    return tabs + Math.floor(spaces / 2);
  };
  /** 날짜 한쪽 글 → null(비움) · { unknown } · { t, at } · { error } (maker-paste의 readEdge와 같은 읽기) */
  function readEdge(text) {
    const s = str(text);
    if (!s) return null;
    if (HT.isUnknownText(s) || HT.isUnknownWho(s)) return { unknown: true };
    const d = HT.readDate(s);
    return d && Number.isFinite(d.t) ? d : { error: (d && d.error) || '', text: s };
  }
  /**
   * 계층 입력의 한 줄 → { depth, name, birthText, deathText, adopted, branch, unknown, birth, death, error }.
   * 줄 꼴: '이름 (생 ~ 몰)' · 줄 끝 '[○○파]'(이 사람이 파조) · '(양자)'(위 줄이 양부) · 이름 '미상'(이름 미상의 사람) — 차례는 자유
   */
  const lineCache = new Map(); // 줄 글 → 읽은 것 (글을 칠 때마다 다시 읽으므로 — 바뀌지 않은 줄은 그대로)
  function readLine(raw) {
    const key = String(raw ?? '');
    const hit = lineCache.get(key);
    if (hit) return Object.assign({}, hit);
    const row = readLineNow(key);
    if (lineCache.size > 20000) lineCache.clear();
    lineCache.set(key, row);
    return Object.assign({}, row);
  }
  function readLineNow(raw) {
    const m = /^([\t ]*)([\s\S]*)$/.exec(String(raw ?? ''));
    const row = { depth: depthOf(m[1]), name: '', birthText: '', deathText: '', adopted: false, branch: '', unknown: false, birth: null, death: null, error: '' };
    let s = m[2].trim();
    for (let guard = 0; guard < 8 && s; guard++) {
      let mm = /\[([^[\]]*)\]$/.exec(s);
      if (mm) {
        row.branch = mm[1].trim();
        if (!row.branch) row.error = '[ ] 안에 파 이름이 없음';
        s = s.slice(0, mm.index).trim();
        continue;
      }
      mm = /[(（]([^()（）]*)[)）]$/.exec(s);
      if (mm) {
        const inner = mm[1].trim();
        if (inner === '양자') {
          row.adopted = true;
          s = s.slice(0, mm.index).trim();
          continue;
        }
        if (/[~～∼]/.test(inner)) {
          const [a, b] = inner.split(/[~～∼]/);
          row.birthText = str(a);
          row.deathText = str(b);
          s = s.slice(0, mm.index).trim();
          continue;
        }
      }
      break;
    }
    row.name = s;
    if (!s) row.error = row.error || '이름이 없음';
    if (HT.isUnknownWho(s)) {
      row.unknown = true;
      row.name = '미상';
    }
    for (const k of ['birth', 'death']) {
      const d = readEdge(row[`${k}Text`]);
      if (d && d.error != null) row.error = row.error || `${k === 'birth' ? '태어난' : '죽은'} 때 "${d.text}"을(를) 읽을 수 없음${d.error ? ` (${d.error})` : ''}`;
      else row[k] = d;
    }
    if (row.birth && row.death && !row.birth.unknown && !row.death.unknown && HT.endBound(row.death.t, row.death.at) < row.birth.t) row.error = row.error || '죽은 때가 태어난 때보다 앞섬';
    return row;
  }
  /** 날짜 칸 글 쓰기 */
  const dateText = (x, k) => (!x ? '' : x[`${k}Unknown`] || HT.isUnknownText(x[k]) ? '미정' : HT.dateInputValue(x, k) || '');
  /** 한 줄 쓰기 (readLine의 거꾸로) — '이름 (생 ~ 몰) (양자) [○○파]' */
  function writeLine(r) {
    let s = INDENT.repeat(Math.max(0, r.depth || 0)) + (r.unknown ? '미상' : str(r.name));
    const b = str(r.birthText);
    const d = str(r.deathText);
    if (b || d) s += b && d ? ` (${b} ~ ${d})` : b ? ` (${b} ~)` : ` (~ ${d})`;
    if (r.adopted) s += ' (양자)';
    if (str(r.branch)) s += ` [${str(r.branch)}]`;
    return s;
  }
  /** 붙여넣은 글이 족보 들여쓰기 꼴인지 — 둘 이상의 줄, 들여쓴 줄이 있고 첫 줄은 들여쓰지 않음, 들여쓰기 뒤에는 탭(표의 열)이 없음 */
  function looksLikeOutline(text) {
    const lines = String(text || '').split(/\r?\n/).filter(l => l.trim());
    if (lines.length < 2 || /^[\t ]/.test(lines[0])) return false;
    if (lines.some(l => /\S\t/.test(l))) return false;
    return lines.some(l => /^(\t| {2})/.test(l));
  }
  /** 바뀐 차례를 매길 때 쓰는 자식 차례 열쇠 (확정 설계 2-4 아 — order · 생년 · 첫 칸 시작 · 모델 차례) */
  function sortKeyOf(model, n, raw) {
    const ix = peopleIndex(model);
    const f = n && n.figure;
    const ord = raw && Number.isInteger(raw.order) ? raw.order : f && Number.isInteger(f.order) ? f.order : null;
    const birth = f && isFinite(f.birth) ? f.birth : null;
    const c0 = n && arr(n.cells)[0];
    return [ord, birth, c0 && isFinite(c0.c.start) ? c0.c.start : null, n && Number.isFinite(n.seq) ? n.seq : n && ix.order.has(n) ? ix.order.get(n) : Infinity]; // 넷째 = 모델 차례(D1-W1의 사람 자리 seq — 뼈대의 차례 열쇠와 같은 값)
  }
  const cmpKey = (a, b) => {
    for (let i = 0; i < a.length; i++) {
      const x = a[i] == null ? Infinity : a[i];
      const y = b[i] == null ? Infinity : b[i];
      if (x !== y) return x < y ? -1 : 1;
    }
    return 0;
  };
  const TREE_ROLE = { 'birth-father': 0, father: 1, '': 2, 'adoptive-father': 3, 'adoptive-mother': 5, 'birth-mother': 6, mother: 6 }; // 나무 부모 고르기 (2-4 아 — 후손 gen은 계층 글에 적지 않음)
  const roleOf = e => HT.parentRole(e.as) || str(e.as);
  const treeRank = e => (roleOf(e) === 'ancestor' ? null : roleOf(e) in TREE_ROLE ? TREE_ROLE[roleOf(e)] : 4);
  /** 이 사람이 파조인 분가(파) 이름 — 모델의 founderNode(D1-W1), 없으면 제 작업본 가문의 founder 글을 찾아 */
  function branchOf(model, n, env) {
    for (const h of arr(model.houses)) if (h.parentId && h.founderNode === n) return h.name;
    if (!env || !env.draft) return '';
    for (const h of arr(env.draft.houses)) {
      if (!h || !str(h.parent) || !str(h.founder)) continue;
      const hit = findPeople(h.founder, env);
      if (hit.length === 1 && hit[0].node === n) return str(h.name) || h.id;
    }
    return '';
  }
  /**
   * 뿌리 사람 아래 자손의 계층 글 (확정 설계 7-2 ⑤) — 나무 부모는 생부 > 부 > 구분 없음 > 양부 > 양모 > 생모 · 모(2-4 아), 형제 차례는 sortKeyOf.
   * → { rows: [{ key, depth, name, birthText, deathText, adopted, branch, parentKey }], text }
   */
  function deriveOutline(model, root, env = {}) {
    if (!model || !root) return { rows: [], text: '' };
    const draft = env.draft || null;
    const rawOf = n => (draft && n.figure && n.figure.packId === draft.id ? arr(draft.figures).find(f => f && f.id === n.figure.id) || null : null);
    const reach = new Set([root]);
    for (const queue = [root]; queue.length; ) {
      const n = queue.shift();
      for (const e of arr(n.children)) if (treeRank(e) != null && !reach.has(e.node)) { reach.add(e.node); queue.push(e.node); }
    }
    const treeParent = new Map();
    for (const n of reach) {
      if (n === root) continue;
      let best = null;
      for (const e of arr(n.parents)) {
        const r = treeRank(e);
        if (r == null || !reach.has(e.node) || e.node === n) continue;
        if (!best || r < best.r) best = { r, e };
      }
      if (best) treeParent.set(n, best.e);
    }
    const kids = new Map();
    for (const [n, e] of treeParent) (kids.get(e.node) || kids.set(e.node, []).get(e.node)).push(n);
    for (const list of kids.values()) list.sort((a, b) => cmpKey(sortKeyOf(model, a, rawOf(a)), sortKeyOf(model, b, rawOf(b))));
    const rows = [];
    const seen = new Set();
    const stack = [[root, 0, null]];
    while (stack.length) {
      const [n, depth, parent] = stack.pop();
      if (seen.has(n)) continue;
      seen.add(n);
      const f = rawOf(n) || n.figure;
      const e = treeParent.get(n);
      rows.push({ key: n.key, depth, name: n.unknown ? '미상' : n.figure ? n.figure.name : n.name, unknown: !!n.unknown || (!!n.figure && HT.isUnknownWho(n.figure.name)), birthText: dateText(f, 'birth'), deathText: dateText(f, 'death'), adopted: !!e && /^adoptive-/.test(roleOf(e)), branch: branchOf(model, n, env), parentKey: parent ? parent.key : null });
      const list = kids.get(n) || [];
      for (let i = list.length - 1; i >= 0; i--) stack.push([list[i], depth + 1, n]);
    }
    return { rows, text: rows.map(writeLine).join('\n') };
  }

  /* ---------- 줄의 사람 이어 두기 (글을 고쳐도 같은 줄은 같은 사람) ----------
     글 칸의 줄마다 사람 열쇠(처음 글을 지을 때의 사람 자리 · 고른 사람 · '#new' 새 사람으로 고정)를 둡니다. 고칠 때마다 앞 · 뒤의 같은 줄을 빼고
     가운데 바뀐 곳에서 같은 글 → 같은 이름 → (줄 수가 같으면) 차례로 잇고, 남은 열쇠는 '지운 줄'로 두었다가 같은 이름의 줄이 다시 나타나면 이어 줍니다(잘라 붙여 옮기기) */
  function remapKeys(oldLines, oldKeys, newLines, removed) {
    let p = 0;
    while (p < oldLines.length && p < newLines.length && oldLines[p] === newLines[p]) p++;
    let q = 0;
    while (q < oldLines.length - p && q < newLines.length - p && oldLines[oldLines.length - 1 - q] === newLines[newLines.length - 1 - q]) q++;
    const oldMid = oldLines.slice(p, oldLines.length - q).map((l, i) => ({ l, k: oldKeys[p + i], name: readLine(l).name, used: false }));
    const newMid = newLines.slice(p, newLines.length - q);
    const newNames = newMid.map(l => readLine(l).name);
    const mid = newMid.map(() => null);
    /* 같은 글 · 같은 이름의 옛 줄을 차례대로 꺼내는 표 (수만 줄을 통째로 바꿔 붙여도 줄 수에 비례) */
    const byText = new Map();
    const byName = new Map();
    const put = (m, k, o) => (m.get(k) || m.set(k, []).get(k)).push(o);
    for (const o of oldMid) if (o.k) { put(byText, o.l, o); if (o.name) put(byName, o.name, o); }
    const takeFrom = (m, k) => { const list = m.get(k); if (!list) return null; while (list.length && list[0].used) list.shift(); return list.length ? list.shift() : null; };
    const take = (j, o) => { mid[j] = o.k; o.used = true; };
    newMid.forEach((l, j) => { const o = takeFrom(byText, l); if (o) take(j, o); });
    newMid.forEach((l, j) => { if (mid[j] || !newNames[j]) return; const o = takeFrom(byName, newNames[j]); if (o) take(j, o); });
    if (oldMid.length === newMid.length) newMid.forEach((l, j) => { if (!mid[j] && str(l) && oldMid[j].k && !oldMid[j].used) take(j, oldMid[j]); });
    for (const o of oldMid) if (o.k && !o.used && o.k !== '#new') removed.set(o.k, o.name);
    const gone = new Map();
    for (const [k, n] of removed) put(gone, n, k);
    newMid.forEach((l, j) => {
      if (mid[j] || !str(l)) return;
      const back = gone.get(newNames[j]);
      if (back && back.length === 1 && removed.has(back[0])) { mid[j] = back[0]; removed.delete(back[0]); }
    });
    return oldKeys.slice(0, p).concat(mid, oldKeys.slice(oldKeys.length - q));
  }

  /* ---------- 적용 계획 ---------- */
  const houseRefWord = (model, h) => (arr(model.houses).filter(x => x !== h && x.name === h.name).length ? h.id : h.name);
  /** 사람 자리의 가문 (D1-W1의 사람 가문 houseId — 없으면 인물 · 칸의 가문) */
  const houseOfNode = n => (!n ? null : n.houseId || (n.figure && n.figure.houseId) || (arr(n.cells)[0] && arr(n.cells)[0].c.houseId) || null);
  /**
   * 계층 글 → 적용 계획 { rows, errors, ops, sum } (작업본 · 모델은 고치지 않음).
   * s = { model, draft, lines(글의 줄), keys(줄마다 사람 열쇠 · '#new' · null), root(뿌리 사람 자리 · 없으면 붙여넣기 — 맨 위 줄마다 이름으로 찾음), orig(처음 글의 줄 열쇠 → 줄) }
   * ops = { add: [{ row, id, name, track, parent, adopted, birth, death, unknown }], move: [{ row, target, from, to, adopted }], rename: [{ row, target, from, to }],
   *         dates: [{ row, target }], branch: [{ row, name, house(있는 가문 · 없으면 null), parentHouse, person }], order: [{ target | newId, order }], remove: [{ target, from }] }
   */
  function planOutline(s) {
    const model = s.model;
    const draft = s.draft;
    const draftId = draft ? draft.id : '';
    const env = { model, draftId, draft };
    const orig = s.orig || new Map();
    const rows = [];
    const errors = [];
    const lines = s.lines;
    const keys = s.keys || [];
    const bad = (row, msg) => { if (!row.error) row.error = msg; };
    const stack = [];
    lines.forEach((line, li) => {
      if (!str(line)) return;
      const r = Object.assign(readLine(line), { li, line: li + 1, key: keys[li] || null, parent: null, kids: [], target: null, newId: '', cands: null });
      while (stack.length && stack[stack.length - 1].depth >= r.depth) stack.pop();
      const top = stack[stack.length - 1] || null;
      if (top && r.depth > top.depth + 1) bad(r, '들여쓰기가 위 줄보다 두 단계 이상 깊음');
      if (!top && r.depth > 0) bad(r, '첫 줄보다 들여쓴 줄이 위에 없음');
      r.parent = top && r.depth > top.depth ? top : null;
      if (r.parent) r.parent.kids.push(r);
      stack.push(r);
      rows.push(r);
    });
    /* 뿌리 */
    if (s.root) {
      const first = rows[0];
      rows.forEach((r, i) => { if (i && r.depth === 0) bad(r, '뿌리는 첫 줄 하나뿐입니다 — 이 줄을 들여 쓰세요'); });
      if (first) {
        if (first.key && first.key !== s.root.key) bad(first, '첫 줄은 뿌리 사람이어야 합니다');
        first.key = s.root.key;
        first.target = targetOfNode(s.root);
      }
    }
    /* 줄 → 사람: 열쇠가 있으면 그 사람, 없으면 부모 줄의 사람의 같은 이름 자식 · (붙여넣기의 맨 위 줄은) 이름으로 찾기 · 아니면 새 사람 */
    const boundKeys = new Set();
    for (const r of rows) {
      if (r.target) { boundKeys.add(r.target.key); continue; }
      if (r.key && r.key !== '#new') {
        const t = targetOfKey(model, r.key);
        if (t) { r.target = t; boundKeys.add(t.key); continue; }
      }
      if (r.key === '#new' || r.unknown) continue;
      const p = r.parent;
      if (p && p.target && p.target.node) {
        const same = arr(p.target.node.children).map(e => e.node).filter(n => !boundKeys.has(n.key) && (n.figure ? namesOfFig(n.figure) : [n.name]).includes(r.name));
        if (same.length >= 1) { r.target = targetOfNode(same[0]); boundKeys.add(same[0].key); continue; }
      }
      if (!p && !s.root) {
        const hits = findPeople(r.name, env).filter(t => !boundKeys.has(t.key));
        if (hits.length === 1) { r.target = hits[0]; boundKeys.add(hits[0].key); }
        else if (hits.length > 1) { r.cands = hits; bad(r, `같은 이름의 사람이 ${hits.length}명 — 오른쪽에서 고르세요`); }
      }
    }
    for (const r of rows) if (r.error) errors.push(r);
    /* 새 사람의 id · 트랙 */
    const taken = new Set();
    if (draft) for (const list of (HT.draft && HT.draft.LISTS) || []) for (const x of arr(draft[list])) if (x && x.id) taken.add(x.id);
    for (const f of figuresOf(model)) if (f.packId === draftId) taken.add(f.id);
    const firstTrack = (draft && arr(draft.tracks)[0] && draft.tracks[0].id) || (arr(model && model.tracks)[0] || {}).id || '';
    const trackOf = r => (r.target ? r.target.track : r.newTrack) || (r.parent ? trackOf(r.parent) : '') || (s.root ? targetOfNode(s.root).track : '') || firstTrack;
    const extra = [];
    for (const r of rows) {
      if (r.target) continue;
      r.newTrack = trackOf(r);
      const seed = `${r.newTrack}|${r.name}|${r.parent ? r.parent.key || r.parent.newId || r.parent.name : ''}|${r.li}`;
      const base = HT.makerKit && HT.makerKit.uniqueId ? HT.makerKit.uniqueId(`fk-${HT.hash(seed)}`, taken) : `fk-${HT.hash(seed)}`;
      r.newId = base;
      taken.add(base);
      extra.push({ id: base, name: r.name, track: r.newTrack });
    }
    const targetOfRow = r => r.target || (r.newId ? { isNew: true, id: r.newId, name: r.name, track: r.newTrack, unknown: r.unknown } : null);
    const refFor = (t, track, strict = false) => whoRef(t, { model, draftId, track, extra, strict });
    const ops = { add: [], move: [], rename: [], dates: [], branch: [], order: [], remove: [], skipped: [] };
    const own = t => !!t && !t.isNew && ((t.fig && t.fig.packId === draftId) || (!t.fig && t.cell && t.cell.p.packId === draftId));
    const ownFig = t => !!t && !t.isNew && !!t.fig && t.fig.packId === draftId;
    for (const r of rows) {
      const parentT = r.parent ? targetOfRow(r.parent) : null;
      if (!r.target) {
        if (r.parent && r.parent.target && r.parent.target.unknown && !r.parent.target.fig) bad(r, '부모가 파일에 사람으로 적히지 않은 미상이라 이을 수 없음');
        ops.add.push({ row: r, id: r.newId, name: r.name, track: r.newTrack, parent: parentT ? refFor(parentT, r.newTrack) : null, adopted: r.adopted, birth: r.birth, death: r.death, unknown: r.unknown });
        continue;
      }
      const o = orig.get(r.target.key) || (r.key ? orig.get(r.key) : null);
      const toKey = r.parent ? (r.parent.target ? r.parent.target.key : `new:${r.parent.newId}`) : null;
      if (o && r !== rows[0]) {
        if ((o.parentKey || null) !== toKey || !!o.adopted !== !!r.adopted) {
          if (!own(r.target)) ops.skipped.push(`${r.name}: 다른 DLC의 사람이라 부모를 바꾸지 않았습니다`);
          else if (r.parent) ops.move.push({ row: r, target: r.target, from: o.parentKey ? targetOfKey(model, o.parentKey) : null, to: refFor(parentT, r.target.track), adopted: r.adopted });
        }
      } else if (!o && r.parent && r.parent.target && r.parent.target.node) {
        /* 이름으로 이은 줄: 그 부모와 이미 이어져 있고 (양자) 표시만 다르면 고침 */
        const e = arr(r.target.node && r.target.node.parents).find(q => q.node === r.parent.target.node);
        if (e && /^adoptive-/.test(roleOf(e)) !== !!r.adopted && own(r.target)) ops.move.push({ row: r, target: r.target, from: r.parent.target, to: refFor(parentT, r.target.track), adopted: r.adopted });
        if (!e && own(r.target)) ops.move.push({ row: r, target: r.target, from: null, to: refFor(parentT, r.target.track), adopted: r.adopted });
      } else if (!o && r.parent && !r.parent.target) {
        if (own(r.target)) ops.move.push({ row: r, target: r.target, from: null, to: refFor(parentT, r.target.track), adopted: r.adopted });
      }
      const was = o || { name: r.target.name, birthText: dateText(r.target.fig, 'birth'), deathText: dateText(r.target.fig, 'death') };
      if (!r.unknown && str(was.name) !== r.name) {
        if (ownFig(r.target)) ops.rename.push({ row: r, target: r.target, from: str(was.name), to: r.name });
        else ops.skipped.push(`${was.name}: 다른 DLC의 사람 · 지도자 칸이라 이름을 바꾸지 않았습니다`);
      }
      if ((r.birthText || r.deathText || o) && (str(was.birthText) !== r.birthText || str(was.deathText) !== r.deathText)) {
        if (ownFig(r.target)) ops.dates.push({ row: r, target: r.target });
        else if (r.birthText || r.deathText) ops.skipped.push(`${r.name}: 다른 DLC의 사람 · 지도자 칸이라 생몰을 바꾸지 않았습니다`);
      }
    }
    /* 파조 표시 → 가문 줄 { parent, founder } */
    const houseByName = name => arr(model && model.houses).find(h => h.name === name) || null;
    const newHouses = new Map();
    const houseOfRow = r => {
      if (!r) return s.root ? houseOfNode(s.root) : null;
      if (r.branch) return newHouses.has(r.branch) ? newHouses.get(r.branch).id : (houseByName(r.branch) || {}).id || null;
      if (r.target && r.target.node) return houseOfNode(r.target.node);
      return houseOfRow(r.parent);
    };
    for (const r of rows) {
      if (!r.branch) continue;
      const o = r.target ? orig.get(r.target.key) : null;
      if (o && o.branch === r.branch) continue;
      const person = targetOfRow(r);
      const founder = refFor(person, '', true);
      const h = houseByName(r.branch);
      if (h) {
        const mine = draft && arr(draft.houses).some(x => x && x.id === h.id);
        if (!mine) { ops.skipped.push(`${r.branch}: 다른 DLC의 가문이라 파조를 적지 않았습니다(가문은 덮어쓰기 대상이 아님)`); continue; }
        ops.branch.push({ row: r, name: r.branch, house: h.id, founder });
        continue;
      }
      if (newHouses.has(r.branch)) { bad(r, `파 "${r.branch}"을(를) 두 줄에 적었습니다`); continue; }
      const parentHouseId = houseOfRow(r.parent);
      const ph = parentHouseId && model.houseMap ? model.houseMap.get(parentHouseId) : null;
      const pnew = parentHouseId && [...newHouses.values()].find(x => x.id === parentHouseId);
      const id = HT.makerKit && HT.makerKit.uniqueId ? HT.makerKit.uniqueId(`house-${HT.hash(r.branch)}`, new Set(arr(draft && draft.houses).map(x => x && x.id).concat(arr(model && model.houses).map(x => x.id), [...newHouses.values()].map(x => x.id)))) : `house-${HT.hash(r.branch)}`;
      const nh = { id, name: r.branch, parent: pnew ? pnew.id : ph ? houseRefWord(model, ph) : '', founder };
      newHouses.set(r.branch, nh);
      ops.branch.push({ row: r, name: r.branch, house: null, create: nh, founder });
    }
    /* 형제 순서: 글의 차례가 저절로 나는 차례와 다르면 그 형제들에 order 1 · 2 … */
    const groups = [];
    if (rows.length) {
      const tops = rows.filter(r => !r.parent);
      if (!s.root) groups.push(tops);
      for (const r of rows) if (r.kids.length > 1) groups.push(r.kids);
    }
    for (const list of groups) {
      if (list.length < 2) continue;
      const keyOf = r => (r.target ? sortKeyOf(model, r.target.node, ownFig(r.target) ? arr(draft && draft.figures).find(f => f && f.id === r.target.fig.id) : null) : [null, r.birth && !r.birth.unknown ? r.birth.t : null, null, 1e12 + r.li]);
      const sorted = list.slice().sort((a, b) => cmpKey(keyOf(a), keyOf(b)));
      if (sorted.every((r, i) => r === list[i])) continue;
      list.forEach((r, i) => {
        if (r.target && !ownFig(r.target)) { ops.skipped.push(`${r.name}: 다른 DLC의 사람 · 지도자 칸이라 형제 순서를 적지 않았습니다`); return; }
        ops.order.push(r.target ? { target: r.target, order: i + 1 } : { newId: r.newId, order: i + 1 });
      });
    }
    /* 지운 줄: 처음 글에 있던 사람 가운데 지금 어느 줄에도 없는 사람 */
    const present = new Set(rows.filter(r => r.target).map(r => r.target.key));
    for (const [k, o] of orig) {
      if (present.has(k) || (s.root && k === s.root.key)) continue;
      const t = targetOfKey(model, k);
      if (!t) continue;
      ops.remove.push({ target: t, from: o.parentKey ? targetOfKey(model, o.parentKey) : null, lineage: !!t.fig && isLineage(t.fig) && t.fig.packId === draftId, own: own(t) });
    }
    for (const r of rows) if (r.error && !errors.includes(r)) errors.push(r);
    const sum = { add: ops.add.length, move: ops.move.length, rename: ops.rename.length, dates: ops.dates.length, branch: ops.branch.length, order: ops.order.length ? 1 : 0, remove: ops.remove.length };
    return { rows, errors, ops, sum, extra };
  }
  /** 날짜 칸 쓰기 (인물의 birth · death) */
  function putDate(x, k, d) {
    delete x[`${k}At`];
    delete x[`${k}Unknown`];
    if (!d) delete x[k];
    else if (d.unknown) { x[k] = '미정'; x[`${k}Unknown`] = true; }
    else { x[k] = d.t; if (d.at) x[`${k}At`] = d.at; }
  }
  /** 작업본 안의 사람 참조 글 from → to (인물의 부모 · 배우자, 지도자 · 내각 칸의 사람 · 전임자 · 부모 · 배우자, 단체 구성원, 가문의 시조) — 이름으로 적은 곳만 */
  function renameWho(d, from, to) {
    let n = 0;
    const fix = v => (typeof v === 'string' && v.trim() === from ? (n++, to) : v);
    const kin = list => { for (const q of arr(list)) if (q && typeof q === 'object' && q.who != null) q.who = fix(q.who); };
    for (const f of arr(d.figures)) { kin(f.parents); kin(f.spouses); }
    for (const p of arr(d.periods)) for (const k of ['leaders', 'reigns', 'cabinets']) for (const c of arr(p[k])) {
      if (!c || typeof c !== 'object' || Array.isArray(c)) continue;
      if (c.person != null) c.person = fix(c.person);
      if (c.accession && typeof c.accession === 'object' && c.accession.from != null) c.accession.from = fix(c.accession.from);
      kin(c.parents);
      kin(c.spouses);
    }
    for (const g of arr(d.groups)) if (Array.isArray(g.people)) g.people = g.people.map(fix);
    for (const h of arr(d.houses)) if (h && h.founder != null) h.founder = fix(h.founder);
    return n;
  }
  /** 사람의 부모 줄을 적을 곳 — 인물이 있으면 인물(제 작업본), 없으면 제 나라의 첫 지도자 칸 (7-4) */
  function kinHolder(d, t) {
    if (t.fig && t.fig.packId === d.id) return arr(d.figures).find(f => f && f.id === t.fig.id) || null;
    if (!t.fig && t.cell && t.cell.p.packId === d.id) {
      const p = arr(d.periods).find(q => q && q.id === t.cell.p.id);
      const list = p && (p.leaders || p.reigns);
      return list && list[t.cell.i] && typeof list[t.cell.i] === 'object' && !Array.isArray(list[t.cell.i]) ? list[t.cell.i] : null;
    }
    return null;
  }
  /** 부모 줄 가운데 그 사람(from)을 가리키는 줄의 자리 (없으면 -1) */
  function parentLineOf(holder, from, env) {
    if (!from) return -1;
    return arr(holder.parents).findIndex(q => {
      if (!q || typeof q !== 'object' || q.whoUnknown) return false;
      const hits = findPeople(refText(q.who), env);
      return hits.some(t => sameTarget(t, from));
    });
  }
  /** 계획을 작업본(사본)에 적용합니다 — 한 걸음(api.transact)으로 부르는 쪽이 감쌈. opts.remove = 지운 줄도 적용 */
  function applyOutline(d, plan, model, opts = {}) {
    const env = { model, draftId: d.id, draft: d };
    const ops = plan.ops;
    if (!Array.isArray(d.figures)) d.figures = [];
    for (const a of ops.add) {
      const f = { id: a.id, track: a.track, name: a.unknown ? '미상' : a.name, lineageOnly: true };
      if (a.parent != null && a.parent !== '') f.parents = [{ who: a.parent, as: a.adopted ? 'adoptive-father' : 'father' }];
      if (a.birth) putDate(f, 'birth', a.birth);
      if (a.death) putDate(f, 'death', a.death);
      d.figures.push(f);
    }
    for (const m of ops.move) {
      const h = kinHolder(d, m.target);
      if (!h) continue;
      const i = parentLineOf(h, m.from, env);
      const as = m.adopted ? 'adoptive-father' : i >= 0 && !/^adoptive-/.test(HT.parentRole(h.parents[i].as) || '') ? h.parents[i].as || 'father' : 'father';
      if (i >= 0) {
        const keep = Object.fromEntries(Object.entries(h.parents[i]).filter(([k]) => !['who', 'whoUnknown', 'name', 'as', 'gen'].includes(k)));
        h.parents[i] = Object.assign({ who: m.to, as }, keep);
      } else h.parents = arr(h.parents).concat({ who: m.to, as });
    }
    for (const r of ops.rename) {
      const f = arr(d.figures).find(x => x && x.id === r.target.fig.id);
      if (!f) continue;
      const byName = whoRef(r.target, { model, draftId: d.id, track: r.target.track }) === r.from;
      f.name = r.to;
      if (byName) renameWho(d, r.from, r.to);
    }
    for (const x of ops.dates) {
      const f = arr(d.figures).find(y => y && y.id === x.target.fig.id);
      if (!f) continue;
      putDate(f, 'birth', x.row.birth);
      putDate(f, 'death', x.row.death);
    }
    for (const o of ops.order) {
      const id = o.newId || (o.target.fig && o.target.fig.id);
      const f = arr(d.figures).find(y => y && y.id === id);
      if (f) f.order = o.order;
    }
    if (ops.branch.length && !Array.isArray(d.houses)) d.houses = [];
    for (const b of ops.branch) {
      if (b.create) {
        const h = { id: b.create.id, name: b.create.name };
        if (b.create.parent) h.parent = b.create.parent;
        h.founder = b.create.founder;
        d.houses.push(h);
      } else {
        const h = arr(d.houses).find(x => x && x.id === b.house);
        if (h) h.founder = b.founder;
      }
    }
    if (opts.remove)
      for (const x of ops.remove) {
        if (x.lineage) HT.draft.removeOwn(d, x.target.fig.id);
        else if (x.own) {
          const h = kinHolder(d, x.target);
          const i = h ? parentLineOf(h, x.from, env) : -1;
          if (i >= 0) {
            h.parents.splice(i, 1);
            if (!h.parents.length) delete h.parents;
          }
        }
      }
    return d;
  }

  /* ================= 통째 붙여넣기의 인물 층 (js/maker-paste.js parseWhole의 people) ================= */
  /**
   * 인물 층 → 작업본에 적을 계획. nation = 방금 저장한 나라(모델 항목 — 검사에서 떨어졌으면 { name, track }).
   * 같은 트랙 · 같은 이름의 제 인물이 하나 있으면 그 사람을 고치고(적은 칸만), 없으면 새 사람. 부 · 모 · 양부 · 배우자 글은
   * 이 블록의 사람 → 이 나라의 지도자 칸(대표 이름 · 묘호 · 시호 · 본명, "이름@해") → 사람 찾기(7-4) 차례로 찾아 7-4의 글(whoRef)로 적고, 못 찾으면 글 그대로(loose).
   * → { add: [인물], update: [인물(통째)], skipped: [글], loose: [글] }
   */
  function planPeople(model, draft, nation, people) {
    const draftId = draft.id;
    const track = str(nation && nation.track) || (arr(draft.tracks)[0] || {}).id || '';
    const own = arr(draft.figures);
    const taken = new Set();
    for (const list of (HT.draft && HT.draft.LISTS) || ['figures']) for (const x of arr(draft[list])) if (x && x.id) taken.add(x.id);
    const skipped = [];
    const loose = [];
    const rows = [];
    for (const p of arr(people)) {
      const same = own.filter(f => f && f.name === p.name && str(f.track) === track);
      if (same.length > 1) { skipped.push(`${p.name}(같은 트랙에 같은 이름의 인물이 여럿)`); continue; }
      let id = same.length ? same[0].id : '';
      if (!id) {
        const base = `fk-${HT.hash(`${track}|${p.name}|${(nation && nation.name) || ''}`)}`;
        id = HT.makerKit && HT.makerKit.uniqueId ? HT.makerKit.uniqueId(base, taken) : base;
        taken.add(id);
      }
      rows.push({ p, id, old: same[0] || null });
    }
    const ix = peopleIndex(model);
    const extra = rows.filter(x => !x.old).map(x => ({ id: x.id, name: x.p.name, track }));
    const env = { model, draftId, track, extra };
    const byName = new Map(rows.map(x => [x.p.name, x]));
    const P = nation && nation.uid && model.byUid ? model.byUid.get(nation.uid) : null;
    const cells = P ? arr(P.leaders).map((c, i) => ({ p: P, i, c, key: `c:${P.uid}|leader:${i}` })) : [];
    const ref = s => {
      if (HT.isUnknownWho(s)) return '미상';
      const b = byName.get(s);
      if (b) {
        const f = b.old && ix.figByUid.get(`${draftId}/${b.id}`);
        return whoRef(f ? targetOfFig(model, f) : { isNew: true, id: b.id, name: b.p.name, track }, env);
      }
      const [nm, at] = s.split('@').map(x => x.trim());
      const y = at && /^-?\d+$/.test(at) ? Number(at) : null;
      const hit = cells.filter(x => leaderNames(x.c).includes(nm) && (y == null || Math.floor(x.c.start + 1e-9) === y));
      if (hit.length === 1) return whoRef(targetOfCell(model, hit[0]), env);
      const one = pickOne(findPeople(s, env), track);
      if (one) return whoRef(one, env);
      loose.push(s);
      return s;
    };
    const out = { add: [], update: [], skipped, loose };
    for (const { p, id, old } of rows) {
      const f = old ? clone(old) : { id, track, name: p.name };
      if (!old || p.kindSet) {
        if (p.lineageOnly) {
          f.lineageOnly = true;
          delete f.importance;
        } else delete f.lineageOnly;
      }
      for (const k of ['role', 'description', 'house', 'order', 'importance']) if (p[k] != null) f[k] = p[k];
      for (const k of ['birth', 'death']) {
        if (p[k] == null) continue;
        f[k] = p[k];
        delete f[`${k}Unknown`];
        if (p[`${k}At`]) f[`${k}At`] = p[`${k}At`];
        else delete f[`${k}At`];
      }
      if (p.aka) f.aka = [...new Set(arr(f.aka).concat(p.aka))];
      if (p.names) {
        f.names = arr(f.names).slice();
        for (const n of p.names) if (!f.names.some(q => q && q.text === n.text && (q.lang || '') === (n.lang || ''))) f.names.push(Object.assign({}, n));
      }
      for (const [k, role] of [['father', 'father'], ['mother', 'mother'], ['adoptive', 'adoptive-father']]) {
        if (!p.refs[k]) continue;
        setParent(f, role, ref(p.refs[k]));
        const line = arr(f.parents).find(q => q && (HT.parentRole(q.as) || str(q.as)) === role);
        if (line && p.certainty) line.certainty = p.certainty;
      }
      for (const s of arr(p.refs.spouses)) {
        const who = ref(s);
        if (who === '미상') continue;
        const txt = refText(who);
        if (!arr(f.spouses).some(q => q && refText(q.who) === txt)) f.spouses = arr(f.spouses).concat({ who });
      }
      if (p.service && nation && nation.name) {
        const polity = P ? polityWord(model, P, draftId) : nation.name;
        const row = Object.assign({ polity }, p.service);
        const list = arr(f.service).slice();
        const i = list.findIndex(q => (q && typeof q === 'object' ? q.polity : q) === polity);
        if (i >= 0) list[i] = Object.assign({}, typeof list[i] === 'object' ? list[i] : {}, row);
        else list.push(row);
        f.service = list;
      }
      (old ? out.update : out.add).push(f);
    }
    return out;
  }
  /** 인물 층의 계획을 작업본(사본)에 — 한 걸음(api.transact)으로 부르는 쪽이 감쌈 */
  function applyPeople(d, plan) {
    if (!Array.isArray(d.figures)) d.figures = [];
    for (const f of plan.update) {
      const i = d.figures.findIndex(x => x && x.id === f.id);
      if (i >= 0) d.figures[i] = clone(f);
      else d.figures.push(clone(f));
    }
    for (const f of plan.add) d.figures.push(clone(f));
    return d;
  }

  /* ================= 세계표 · 승계표 창 안에서 사람 더하기 (HT.maker.kin.addRelative) ================= */
  const REL_WORD = { child: '자식', sibling: '형제', spouse: '배우자', parent: '부모' };
  const PARENT_WORD = { father: '부', mother: '모', 'adoptive-father': '양부', 'adoptive-mother': '양모' };
  /**
   * 기준 사람(사람 자리 열쇠 key) 곁에 새 사람 하나 — 계산만. o = { rel: child | sibling | spouse | parent, name, unknown(이름 미상), role, birth, death(readEdge 꼴 — 없으면 null),
   *   as: father | mother(자식이면 기준이 부 · 모, 부모면 새 사람이 부 · 모), adopted(양자 · 양부모), lineage(계보 전용 — 기본 참) }.
   * → { error } 또는 { fig(새 인물), edit({ target, line } — 부모 더하기: 기준의 부모 줄), newKey, base(기준 이름) }
   */
  function planRelative(model, draft, key, o) {
    const t = targetOfKey(model, key);
    if (!t) return { error: '기준 사람을 찾지 못했습니다.' };
    const rel = o.rel;
    const name = o.unknown ? '미상' : str(o.name);
    if (!name) return { error: '이름을 적거나 「미상」을 고릅니다.' };
    if (!o.unknown && HT.isUnknownWho(name)) return { error: '이름을 모르면 「미상」을 고릅니다.' };
    const lineage = o.lineage !== false || o.unknown;
    if (!lineage && !o.birth && !o.death) return { error: '띠 인물은 생 · 몰 가운데 하나가 있어야 합니다 — 모르면 계보 전용으로.' };
    if (o.birth && o.death && o.birth.t != null && o.death.t != null && o.death.t < o.birth.t) return { error: '몰이 생보다 앞섭니다.' };
    const draftId = draft.id;
    const track = t.track || (arr(draft.tracks)[0] || {}).id || (arr(model.tracks)[0] || {}).id || '';
    const taken = new Set();
    for (const list of (HT.draft && HT.draft.LISTS) || ['figures']) for (const x of arr(draft[list])) if (x && x.id) taken.add(x.id);
    const base = `fk-${HT.hash(`${track}|${name}|${t.key}|${rel}|${arr(draft.figures).length}`)}`;
    const id = HT.makerKit && HT.makerKit.uniqueId ? HT.makerKit.uniqueId(base, taken) : base;
    const me = { isNew: true, id, name, track, unknown: !!o.unknown };
    const env = { model, draftId, track, extra: [{ id, name, track }] };
    const f = { id, track, name };
    if (lineage) f.lineageOnly = true;
    if (str(o.role)) f.role = str(o.role);
    if (o.birth) putDate(f, 'birth', o.birth);
    if (o.death) putDate(f, 'death', o.death);
    const ghost = x => !!x && x.unknown && !x.fig; // 파일에 사람으로 적히지 않은 미상(빈 고리) — 가리킬 수 없음
    let edit = null;
    if (rel === 'child') {
      if (ghost(t)) return { error: '기준이 파일에 사람으로 적히지 않은 미상이라 이을 수 없습니다.' };
      const as = o.as === 'mother' ? (o.adopted ? 'adoptive-mother' : 'mother') : o.adopted ? 'adoptive-father' : 'father';
      f.parents = [{ who: whoRef(t, env), as }];
    } else if (rel === 'sibling') {
      const ps = arr(t.node && t.node.parents).filter(e => e && e.node && roleOf(e) !== 'ancestor' && !ghost(targetOfNode(e.node)));
      if (!ps.length) return { error: `«${t.name}»의 부모가 적혀 있지 않아 형제로 이을 수 없습니다 — 부모를 먼저 더합니다.` };
      f.parents = ps.map(e => ({ who: whoRef(targetOfNode(e.node), env), as: roleOf(e) || 'father' }));
    } else if (rel === 'spouse') {
      if (ghost(t)) return { error: '기준이 파일에 사람으로 적히지 않은 미상이라 이을 수 없습니다.' };
      f.spouses = [{ who: whoRef(t, env) }];
    } else if (rel === 'parent') {
      if (!t.fig && !t.cell) return { error: '기준이 인물이나 지도자 칸이 아니라 부모를 적을 곳이 없습니다.' };
      const as = o.as === 'mother' ? (o.adopted ? 'adoptive-mother' : 'mother') : o.adopted ? 'adoptive-father' : 'father';
      const same = arr(t.node && t.node.parents).find(e => e && roleOf(e) === as && !ghost(targetOfNode(e.node)));
      if (same) return { error: `«${t.name}»에게는 ${PARENT_WORD[as]} «${targetOfNode(same.node).name}»이(가) 이미 있습니다 — 바꾸려면 그 사람의 편집 창에서.` };
      edit = { target: t, line: { who: whoRef(me, Object.assign({}, env, { track: t.track || track })), as } };
    } else return { error: '관계를 고릅니다.' };
    return { fig: f, edit, newKey: `f:${draftId}/${id}`, base: t.name };
  }
  /** 기준의 부모 줄에 한 줄 — 같은 역할의 이름 미상 줄(빈 고리)이 있으면 그 줄을 바꿈 */
  function putParentLine(h, line) {
    const list = arr(h.parents).slice();
    const i = list.findIndex(q => q && typeof q === 'object' && (q.whoUnknown === true || HT.isUnknownWho(q.who)) && (HT.parentRole(q.as) || str(q.as) || 'father') === line.as);
    if (i >= 0) list[i] = Object.assign({}, line, Object.fromEntries(Object.entries(list[i]).filter(([k]) => !['who', 'whoUnknown', 'name', 'as'].includes(k)))); // 그 줄의 확실성 · 메모는 그대로
    else list.push(Object.assign({}, line));
    h.parents = list;
  }
  /** 계획을 작업본(사본)에 — 한 걸음(api.transact)으로 부르는 쪽이 감쌈. 남의 DLC의 사람에 부모를 적으면 덮어쓰기(패치) */
  function applyRelative(d, plan, a) {
    if (!Array.isArray(d.figures)) d.figures = [];
    d.figures.push(clone(plan.fig));
    if (!plan.edit) return d;
    const t = plan.edit.target;
    const h = kinHolder(d, t);
    if (h) {
      putParentLine(h, plan.edit.line);
      return d;
    }
    const x = t.fig || (t.cell && t.cell.p);
    if (!x || !a || !a.rawOf) throw Error('부모 줄을 적을 곳을 찾지 못했습니다.');
    const before = a.rawOf(x);
    const after = clone(before);
    const holder = t.fig ? after : arr(after.leaders || after.reigns)[t.cell.i];
    if (!holder || typeof holder !== 'object') throw Error('부모 줄을 적을 지도자 칸을 찾지 못했습니다.');
    putParentLine(holder, plan.edit.line);
    HT.makerGrid.patchItem(d, (a.baseModel && a.baseModel().byUid.get(x.uid)) || x, before, after);
    return d;
  }

  /* ================= 가문 머리 값의 짐작 (바탕 자료 표의 '짐작: …' 딱지) ================= */
  /** 가문(id)의 구분 · 민족 짐작 글 (D1-W1의 trackAuto · peopleAuto — 구분은 트랙 이름으로) — 적은 값이 있거나 짐작이 없으면 '' */
  function houseGuess(model, id, field) {
    const h = model && model.houseMap ? model.houseMap.get(id) : null;
    if (!h) return '';
    if (field === 'track') {
      const v = str(h.trackAuto === true ? h.track : h.trackAuto);
      if (!v || str(h.track) && h.trackAuto !== true) return '';
      const t = model.trackMap && model.trackMap.get(v);
      return t ? t.name : v;
    }
    if (field === 'people') {
      const v = str(h.peopleAuto === true ? h.people : h.peopleAuto);
      return !v || (str(h.people) && h.peopleAuto !== true) ? '' : v;
    }
    return '';
  }

  /* ================= 검사 창의 알림 (확정 설계 7-5) ================= */
  const KIN_LIMIT = 50000;
  /** 모델에서야 알 수 있는 계보 알림 — 한 뿌리 가문의 사람이 덩어리 상한(5만)을 넘으면 새 앱에는 파별로 나뉘어 실림. [{ msg, kind: 'houses', index }] */
  function checks(model, draft) {
    const out = [];
    if (!model || !draft || !model.houseMap) return out;
    const count = new Map();
    for (const n of arr(model.persons)) {
      const id = n.houseId;
      const h = id ? model.houseMap.get(id) : null;
      if (!h) continue;
      const root = arr(h.path)[0] || h.id;
      count.set(root, (count.get(root) || 0) + 1);
    }
    for (const [id, n] of count) {
      if (n <= KIN_LIMIT) continue;
      const h = model.houseMap.get(id);
      const index = arr(draft.houses).findIndex(x => x && x.id === id);
      if (h && (h.packId === draft.id || index >= 0)) out.push({ msg: `가문 «${h.name}»의 계보가 ${n.toLocaleString('ko-KR')}명으로 덩어리 상한(${KIN_LIMIT.toLocaleString('ko-KR')}명)을 넘어, 새 앱(아카이브)에는 파별로 나뉘어 실리고 세계표의 모두 펼치기는 파 단위로만 됩니다.`, kind: 'houses', index });
    }
    return out;
  }

  /* ================= 사람 찾기 상자 (세 글자 넘게 치면 — 계보 전용 인물은 자동 완성 목록에 없으므로) ================= */
  let finderSeq = 0;
  /**
   * 사람 칸(input)에 붙는 찾기 상자: 세 글자 이상이면 이름이 든 사람(인물 · 계보 전용 인물 · 지도자 칸)을 12명까지 아래에 보이고, 고르면 7-4의 글(whoRef)로 칸을 채웁니다.
   * opts = { track: () => 적는 쪽의 트랙, strict: 파조처럼 늘 id · 칸 참조로, model: () => 모델, draftId: () => 작업본 id }. 돌려주는 값: 떼는 함수
   */
  function attachFinder(input, opts = {}) {
    if (!input || input.dataset.kinFinder) return () => {};
    const getModel = opts.model || (() => (ctx && ctx.state ? ctx.state.model : null));
    const getDraft = opts.draftId || (() => (api && api.draft ? api.draft.id : ''));
    const id = `mkKinFind${++finderSeq}`;
    input.dataset.kinFinder = id;
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-controls', id);
    const box = document.createElement('div');
    box.className = 'mk-kin-find';
    box.id = id;
    box.setAttribute('role', 'listbox');
    box.hidden = true;
    document.body.append(box);
    let items = [];
    let at = -1;
    let picked = false; // 고른 뒤 칸을 채우며 낸 input으로는 다시 열지 않음
    const place = () => {
      const r = input.getBoundingClientRect();
      const w = Math.max(260, r.width);
      box.style.left = `${Math.max(8, Math.min(innerWidth - w - 8, r.left))}px`;
      box.style.top = `${Math.min(innerHeight - 40, r.bottom + 2)}px`;
      box.style.width = `${w}px`;
    };
    const close = () => { box.hidden = true; items = []; at = -1; input.setAttribute('aria-expanded', 'false'); input.removeAttribute('aria-activedescendant'); };
    const paint = () => {
      box.innerHTML = items.map((t, i) => {
        const f = t.fig;
        const years = f ? [dateText(f, 'birth'), dateText(f, 'death')].filter(Boolean).join('~') : t.cell ? `${t.cell.p.name} ${HT.formatAxisYear ? HT.formatAxisYear(t.cell.c.start) : t.cell.c.start}` : '';
        const tr = getModel() && getModel().trackMap ? (getModel().trackMap.get(t.track) || {}).name || t.track : t.track;
        return `<div role="option" id="${id}-${i}" class="mk-kin-opt${i === at ? ' is-on' : ''}" data-i="${i}" aria-selected="${i === at}"><b>${esc(t.name)}</b><small>${esc([tr, years, f && isLineage(f) ? '계보 전용' : t.cell ? '지도자' : '', f ? f.id : ''].filter(Boolean).join(' · '))}</small></div>`;
      }).join('');
      if (at >= 0) input.setAttribute('aria-activedescendant', `${id}-${at}`);
    };
    const search = () => {
      const q = str(input.value);
      const model = getModel();
      if ([...q].length < 3 || !model) return close();
      const ix = peopleIndex(model);
      const out = [];
      const ql = q.toLowerCase();
      for (const f of ix.figs) {
        if (out.length >= 12) break;
        if (namesOfFig(f).some(n => n.toLowerCase().includes(ql)) || f.id === q) out.push(targetOfFig(model, f));
      }
      for (const x of ix.cells) {
        if (out.length >= 12) break;
        if (leaderNames(x.c).some(n => n.toLowerCase().includes(ql))) {
          const t = targetOfCell(model, x);
          if (!out.some(o => sameTarget(o, t))) out.push(t);
        }
      }
      items = out;
      at = items.length ? 0 : -1;
      if (!items.length) return close();
      place();
      paint();
      box.hidden = false;
      input.setAttribute('aria-expanded', 'true');
    };
    const pick = i => {
      const t = items[i];
      if (!t) return;
      const track = opts.track ? opts.track() : '';
      const ref = whoRef(t, { model: getModel(), draftId: getDraft(), track, strict: !!opts.strict });
      input.value = refText(ref);
      if (ref && typeof ref === 'object') input.dataset.ref = JSON.stringify(ref);
      else delete input.dataset.ref;
      close();
      picked = true;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      picked = false;
      if (opts.onPick) opts.onPick(ref, t);
    };
    const onInput = () => { if (!picked) search(); };
    const onKey = e => {
      if (box.hidden || e.isComposing) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        e.stopImmediatePropagation();
        at = (at + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
        paint();
      } else if (e.key === 'Enter' && at >= 0) {
        e.preventDefault();
        e.stopImmediatePropagation();
        pick(at);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        e.stopImmediatePropagation();
        close();
      }
    };
    const onDown = e => {
      const o = e.target.closest('[data-i]');
      e.preventDefault(); // 칸의 초점을 지킴 (표의 칸은 초점을 잃으면 적용됨)
      if (o) pick(Number(o.dataset.i));
    };
    const onBlur = () => setTimeout(close, 0);
    input.addEventListener('input', onInput);
    input.addEventListener('keydown', onKey);
    input.addEventListener('blur', onBlur);
    box.addEventListener('pointerdown', onDown);
    const detach = () => {
      input.removeEventListener('input', onInput);
      input.removeEventListener('keydown', onKey);
      input.removeEventListener('blur', onBlur);
      box.remove();
      delete input.dataset.kinFinder;
    };
    /* 칸이 문서에서 빠지면(표를 다시 그림) 상자도 치웁니다 */
    const watch = new MutationObserver(() => { if (!input.isConnected) { watch.disconnect(); detach(); } });
    watch.observe(document.body, { childList: true, subtree: true });
    return detach;
  }

  /* ================= 머리 칩 고치기 (확정 설계 7-1 — HT.maker.kin.editHead) ================= */
  const FIELD_WORD = { track: '구분(트랙)', people: '민족', name: '이름', seat: '본관 성씨', tags: '꼬리표' };
  const normField = f => (['seat', 'surname', 'seatSurname', 'origin'].includes(f) ? 'seat' : ['tag', 'tags'].includes(f) ? 'tags' : f);
  const readTags = v => [...new Set((Array.isArray(v) ? v : typeof v === 'string' ? v.split(/[,，]/) : []).map(str).filter(Boolean))];
  /** 고칠 대상: 정권 → { kind, x(모델 항목), own, raw(작업본 · 남의 것은 원본 + 걸린 패치) } · 가문 → { kind, h(모델 가문), own, raw, path } */
  function headTarget(c, a, opts) {
    const model = c.state.model;
    const draft = a.draft;
    if (opts.kind === 'polity') {
      const x = model.byUid.get(opts.uid) || null;
      if (!x || HT.itemKindOf(x) !== 'period') return { error: '나라를 찾지 못했습니다.' };
      const own = x.packId === draft.id;
      if (!own && a.isLocked && a.isLocked(x)) return { error: `잠긴 팩 «${x.packName}»의 나라입니다 — 불러온 팩 탭에서 자물쇠를 풀면 고칠 수 있습니다.` };
      return { kind: 'polity', x, own, word: x.name };
    }
    if (opts.kind === 'house') {
      const id = String(opts.uid || '').replace(/^house:/, '');
      const h = model.houseMap ? model.houseMap.get(id) || arr(model.houses).find(q => q.name === id) : null;
      if (!h) return { error: '가문을 찾지 못했습니다.' };
      return { kind: 'house', h, own: arr(draft.houses).some(q => q && q.id === h.id), word: h.name };
    }
    return { error: '고칠 수 없는 칩입니다.' };
  }
  /** 가문의 원래 칸을 고칠 수 있는지 — 제 작업본의 것 · 이름으로만 적힌 가문(작업본에 등록해 고침). 남의 DLC 가문은 아님(가문은 덮어쓰기 대상이 아님 — 10절 9번) */
  const houseEditable = (h, draft) => arr(draft.houses).some(q => q && q.id === h.id) || h.auto;
  /** 본관 성씨를 고칠 가문: 본가 길에서 본관이나 성을 적은 첫 가문(제 것부터 위로), 없으면 뿌리 가문 */
  function seatHouse(model, h) {
    const path = arr(h.path).length ? h.path.map(id => model.houseMap.get(id)).filter(Boolean) : [h];
    for (let i = path.length - 1; i >= 0; i--) if (str(path[i].seat) || str(path[i].surname)) return path[i];
    return path[0] || h;
  }
  /** 작업본의 가문 줄 — 이름으로만 적힌 가문이면 같은 이름으로 등록해 돌려줍니다 */
  function houseRaw(d, h, model) {
    let raw = arr(d.houses).find(q => q && q.id === h.id);
    if (!raw && h.auto) {
      if (!Array.isArray(d.houses)) d.houses = [];
      const taken = new Set(arr(d.houses).map(q => q && q.id).concat(arr(model.houses).map(q => q.id)));
      raw = { id: HT.makerKit.uniqueId(`house-${HT.hash(h.name)}`, taken), name: h.name };
      d.houses.push(raw);
    }
    return raw || null;
  }
  /**
   * 칩 고침을 작업본에 — 한 걸음. 정권: 제 것은 그 칸, 남의 것은 패치 set(PATCHABLE의 track · people · name · tags). 가문: 제 것(이름만 적힌 가문은 등록)만.
   * v = 적을 값 (track: 트랙 id · people: 민족 이름이나 id · name: 글 · seat: { seat, surname } · tags: { add | remove })
   */
  async function writeHead(c, a, t, field, v) {
    const model = c.state.model;
    const label = `${t.kind === 'polity' ? '나라' : '가문'} «${t.word}»의 ${FIELD_WORD[field] || field} 고침`;
    if (t.kind === 'polity') {
      const x = t.x;
      if (field === 'track' || field === 'people') {
        /* 구조 나무의 놓아서 채우기와 같은 길 — 트랙은 '딸린 사건 · 인물도 함께?' 물음(B3 moveTrack), 민족은 사전의 이름 · id(dictRef) */
        if (a.applyDrop) {
          const drop = field === 'track' ? { type: 'track', track: v } : { type: 'people', id: v ? (model.peopleMap && (model.peopleMap.get(v) || [...model.peopleMap.values()].find(p => p.name === v)) || {}).id || '' : '', track: x.track };
          if (field === 'people' && v && !drop.id) return writePolity(c, a, x, raw => (raw.people = v), label);
          return !!(await a.applyDrop([x.uid], drop));
        }
        return writePolity(c, a, x, raw => (v ? (raw[field] = v) : delete raw[field]), label);
      }
      if (field === 'name') {
        const to = str(v);
        if (!to) { HT.toast('나라 이름은 비울 수 없습니다.', 'error'); return false; }
        return writePolity(c, a, x, (raw, d) => {
          const before = clone(raw);
          raw.name = to;
          if (t.own && HT.makerFind) HT.makerFind.renameReferences(d, 'periods', before, raw, c.state.packs);
        }, label);
      }
      if (field === 'tags') {
        return writePolity(c, a, x, raw => {
          const now = readTags(raw.tags);
          const next = v && v.remove != null ? now.filter(g => g !== str(v.remove)) : [...new Set(now.concat(readTags(v && v.add != null ? v.add : v)))];
          if (next.length) raw.tags = next;
          else delete raw.tags;
        }, label);
      }
      HT.toast('이 칩은 고칠 수 없습니다.', 'error');
      return false;
    }
    const h = t.h;
    const target = field === 'seat' ? seatHouse(model, h) : h;
    if (!houseEditable(target, a.draft)) {
      HT.toast(`«${target.name}»은(는) 다른 DLC의 가문이라 고칠 수 없습니다 — 가문은 덮어쓰기 대상이 아닙니다. 이 DLC에 새 파(분가)를 만들 수는 있습니다.`, 'error');
      return false;
    }
    if (field === 'name' && !str(v)) { HT.toast('가문 이름은 비울 수 없습니다.', 'error'); return false; }
    const T = HT.makerKit.BASE_TABLES.houses;
    return !!(await a.transact(d => {
      const raw = houseRaw(d, target, model);
      if (!raw) throw Error('가문을 작업본에서 찾지 못했습니다.');
      if (field === 'track' || field === 'people') {
        if (str(v)) raw[field] = str(v);
        else delete raw[field];
      } else if (field === 'name') {
        const from = str(raw.name) || raw.id;
        raw.name = str(v);
        if (from !== raw.name) HT.makerKit.renameRefs(d, T, 'name', from, raw.name);
      } else if (field === 'seat') {
        for (const k of ['seat', 'surname']) {
          if (str(v && v[k])) raw[k] = str(v[k]);
          else delete raw[k];
        }
      } else if (field === 'tags') {
        const now = readTags(raw.tags);
        const next = v && v.remove != null ? now.filter(g => g !== str(v.remove)) : [...new Set(now.concat(readTags(v && v.add != null ? v.add : v)))];
        if (next.length) raw.tags = next;
        else delete raw.tags;
      } else throw Error('이 칩은 고칠 수 없습니다.');
      return d;
    }, label));
  }
  /** 정권의 칸 고침 — 제 것은 작업본의 그 항목, 남의 것은 바뀐 칸만 패치로 (메이커의 한꺼번에 고치기 · 놓아서 채우기와 같은 길) */
  function writePolity(c, a, x, fn, label) {
    return a.transact(d => {
      if (x.packId === d.id) {
        const hit = HT.draft.findOwn(d, x.id);
        if (!hit) throw Error('나라를 작업본에서 찾지 못했습니다.');
        fn(hit.item, d);
      } else {
        const before = a.rawOf(x);
        const after = clone(before);
        fn(after, d);
        HT.makerGrid.patchItem(d, a.baseModel().byUid.get(x.uid) || x, before, after);
      }
      return d;
    }, label);
  }
  /** 작은 고르기(칩 아래 · 없으면 가운데) — 고르면 resolve(값), 닫으면 resolve(undefined) */
  function popover(anchor, title, bodyHTML, wire, cls = '') {
    return new Promise(resolve => {
      const pop = document.createElement('div');
      pop.className = cls ? `mk-kin-pop ${cls}` : 'mk-kin-pop';
      pop.setAttribute('role', 'dialog');
      pop.setAttribute('aria-label', title);
      pop.innerHTML = `<div class="mk-kin-pop-head"><b>${esc(title)}</b><button type="button" class="icon-btn" data-pop-close aria-label="닫기">✕</button></div><div class="mk-kin-pop-body">${bodyHTML}</div>`;
      document.body.append(pop);
      const r = anchor && anchor.isConnected ? anchor.getBoundingClientRect() : null;
      const w = pop.offsetWidth;
      const hgt = pop.offsetHeight;
      const x = r ? Math.max(8, Math.min(innerWidth - w - 8, r.left)) : Math.round((innerWidth - w) / 2);
      const y = r ? (r.bottom + 6 + hgt > innerHeight - 8 ? Math.max(8, r.top - 6 - hgt) : r.bottom + 6) : Math.round((innerHeight - hgt) / 3);
      pop.style.left = `${x}px`;
      pop.style.top = `${y}px`;
      let done = false;
      const finish = v => {
        if (done) return;
        done = true;
        document.removeEventListener('pointerdown', outside, true);
        document.removeEventListener('keydown', onKey, true);
        pop.remove();
        if (anchor && anchor.isConnected && anchor.focus) anchor.focus({ preventScroll: true });
        resolve(v);
      };
      const outside = e => { if (!pop.contains(e.target) && !(e.target.closest && e.target.closest('.mk-kin-find'))) finish(undefined); };
      const onKey = e => { if (e.key === 'Escape' && !e.defaultPrevented) { e.preventDefault(); e.stopPropagation(); finish(undefined); } };
      document.addEventListener('pointerdown', outside, true);
      document.addEventListener('keydown', onKey, true);
      pop.querySelector('[data-pop-close]').addEventListener('click', () => finish(undefined));
      wire(pop, finish);
      const first = pop.querySelector('[data-pop-focus]') || pop.querySelector('input, select, button:not([data-pop-close])');
      if (first) first.focus();
    });
  }
  /** 칩마다 고르기 창의 몸통과 이음 → 고른 값 (닫으면 undefined) */
  function pickHead(c, a, t, field, opts) {
    const model = c.state.model;
    const anchor = opts.anchor || null;
    const word = FIELD_WORD[field] || field;
    const title = `${t.word} — ${word}`;
    const raw = t.kind === 'polity' ? (t.own ? (HT.draft.findOwn(a.draft, t.x.id) || {}).item || {} : a.rawOf(t.x) || {}) : arr(a.draft.houses).find(q => q && q.id === t.h.id) || {};
    const guessBox = g => (g ? `<p class="mk-kin-pop-guess"><span class="mk-guess">짐작: ${esc(g.text)}</span> <button type="button" class="btn btn-sm" data-pop-guess="${esc(g.value)}">짐작 값을 적기</button></p>` : '');
    if (field === 'track') {
      const cur = t.kind === 'polity' ? t.x.track : str(raw.track);
      const g = t.kind === 'house' && !cur && str(t.h.trackAuto) ? { text: houseGuess(model, t.h.id, 'track'), value: t.h.trackAuto } : null;
      const opts2 = arr(model.tracks).map(x => `<option value="${esc(x.id)}"${x.id === cur ? ' selected' : ''}>${esc(x.name)}</option>`).join('');
      return popover(anchor, title, `${guessBox(g)}<label class="mk-kin-pop-row">트랙 <select data-pop-val data-pop-focus>${t.kind === 'house' ? `<option value=""${cur ? '' : ' selected'}>비움 (짐작에 맡김)</option>` : ''}${opts2}</select></label><div class="mk-kin-pop-foot"><button type="button" class="btn btn-sm btn-primary" data-pop-ok>적용</button></div>`, (pop, done) => {
        pop.querySelector('[data-pop-ok]').addEventListener('click', () => done(pop.querySelector('[data-pop-val]').value));
        const gb = pop.querySelector('[data-pop-guess]');
        if (gb) gb.addEventListener('click', () => done(gb.dataset.popGuess));
      });
    }
    if (field === 'people') {
      const cur = t.kind === 'polity' ? str(raw.people) || (t.x.peopleId && model.peopleMap && (model.peopleMap.get(t.x.peopleId) || {}).name) || '' : str(raw.people);
      const g = t.kind === 'house' && !cur && str(t.h.peopleAuto) ? { text: houseGuess(model, t.h.id, 'people'), value: t.h.peopleAuto } : null;
      const list = model.peopleMap ? [...model.peopleMap.values()] : arr(model.peoples);
      const depth = p => Math.max(0, arr(p.path || p.peoplePath).length - 1);
      const kids = new Map();
      for (const p of list) (kids.get(p.parentId || '') || kids.set(p.parentId || '', []).get(p.parentId || '')).push(p);
      const ordered = [];
      const walk = (pid, seen) => { for (const p of (kids.get(pid) || []).sort((x, y) => (x.order ?? 1e9) - (y.order ?? 1e9) || String(x.name).localeCompare(String(y.name), 'ko'))) if (!seen.has(p.id)) { seen.add(p.id); ordered.push(p); walk(p.id, seen); } };
      walk('', new Set());
      for (const p of list) if (!ordered.includes(p)) ordered.push(p);
      const items = ordered.map(p => `<button type="button" class="mk-kin-pop-item${p.name === cur || p.id === cur ? ' is-on" data-pop-focus aria-current="true' : ''}" style="--d:${depth(p)}" data-pop-pick="${esc(p.name)}">${p.color ? `<i class="dot" style="--c:${esc(p.color)}" aria-hidden="true"></i>` : ''}${esc(p.name)}</button>`).join('');
      return popover(anchor, title, `${guessBox(g)}<div class="mk-kin-pop-list" role="listbox" aria-label="민족 — 위 단계에도 놓을 수 있습니다">${items || '<p class="hint">등록된 민족이 없습니다 — 바탕 자료의 민족에서 만듭니다.</p>'}</div><div class="mk-kin-pop-foot">${cur ? '<button type="button" class="btn btn-sm" data-pop-clear>비우기</button>' : ''}</div>`, (pop, done) => {
        pop.addEventListener('click', e => {
          const b = e.target.closest('[data-pop-pick]');
          if (b) done(b.dataset.popPick);
          if (e.target.closest('[data-pop-clear]')) done('');
          const gb = e.target.closest('[data-pop-guess]');
          if (gb) done(gb.dataset.popGuess);
        });
      });
    }
    if (field === 'name') {
      const cur = t.kind === 'polity' ? str(raw.name) || t.x.name : str(raw.name) || t.h.name;
      return popover(anchor, title, `<label class="mk-kin-pop-row">이름 <input data-pop-val data-pop-focus value="${esc(cur)}" autocomplete="off"></label><p class="hint">이 이름으로 가리키던 곳도 따라 바뀝니다.</p><div class="mk-kin-pop-foot"><button type="button" class="btn btn-sm btn-primary" data-pop-ok>적용</button></div>`, (pop, done) => {
        const inp = pop.querySelector('[data-pop-val]');
        inp.select();
        inp.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); done(inp.value); } });
        pop.querySelector('[data-pop-ok]').addEventListener('click', () => done(inp.value));
      });
    }
    if (field === 'seat') {
      const target = seatHouse(model, t.h);
      const r2 = arr(a.draft.houses).find(q => q && q.id === target.id) || target;
      const note = target !== t.h ? `<p class="mk-kin-pop-note">본가 «${esc(target.name)}»의 값을 고칩니다 — 아래 파는 이 값을 물려받습니다.</p>` : '';
      return popover(anchor, `${target.name} — 본관 성씨`, `${note}<label class="mk-kin-pop-row">본관 <input data-pop-seat data-pop-focus value="${esc(str(r2.seat))}" autocomplete="off"></label><label class="mk-kin-pop-row">성 <input data-pop-surname value="${esc(str(r2.surname))}" autocomplete="off"></label><div class="mk-kin-pop-foot"><button type="button" class="btn btn-sm btn-primary" data-pop-ok>적용</button></div>`, (pop, done) => {
        const val = () => ({ seat: pop.querySelector('[data-pop-seat]').value, surname: pop.querySelector('[data-pop-surname]').value });
        pop.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.isComposing && e.target.matches('input')) { e.preventDefault(); done(val()); } });
        pop.querySelector('[data-pop-ok]').addEventListener('click', () => done(val()));
      });
    }
    if (field === 'tags') {
      const now = readTags(raw.tags);
      const chips = now.map(g => `<span class="badge mk-kin-tag">${esc(g)} <button type="button" class="icon-btn" data-pop-remove="${esc(g)}" aria-label="${esc(g)} 꼬리표 지우기">✕</button></span>`).join('');
      return popover(anchor, title, `${chips ? `<p class="chips">${chips}</p>` : ''}<label class="mk-kin-pop-row">새 꼬리표 <input data-pop-val data-pop-focus autocomplete="off" aria-label="더할 꼬리표 — 쉼표로 여럿"></label><div class="mk-kin-pop-foot"><button type="button" class="btn btn-sm btn-primary" data-pop-ok>더하기</button></div>`, (pop, done) => {
        const inp = pop.querySelector('[data-pop-val]');
        inp.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); if (readTags(inp.value).length) done({ add: inp.value }); } });
        pop.querySelector('[data-pop-ok]').addEventListener('click', () => { if (readTags(inp.value).length) done({ add: inp.value }); });
        pop.addEventListener('click', e => { const b = e.target.closest('[data-pop-remove]'); if (b) done({ remove: b.dataset.popRemove }); });
      });
    }
    HT.toast('이 칩은 고칠 수 없습니다.', 'error');
    return Promise.resolve(undefined);
  }
  async function editHeadImpl(c, a, opts) {
    const field = normField(str(opts.field));
    const t = headTarget(c, a, opts);
    if (t.error) { HT.toast(t.error, 'error'); return false; }
    if (!FIELD_WORD[field] || (t.kind === 'polity' && field === 'seat')) { HT.toast('이 칩은 고칠 수 없습니다.', 'error'); return false; }
    if (t.kind === 'house') {
      const target = field === 'seat' ? seatHouse(c.state.model, t.h) : t.h;
      if (!houseEditable(target, a.draft)) {
        HT.toast(`«${target.name}»은(는) 다른 DLC의 가문이라 고칠 수 없습니다 — 가문은 덮어쓰기 대상이 아닙니다. 이 DLC에 새 파(분가)를 만들 수는 있습니다.`, 'error');
        return false;
      }
    }
    let v;
    if (field === 'tags' && opts.remove != null) v = { remove: opts.remove };
    else if (opts.value !== undefined) v = field === 'tags' ? { add: opts.value } : field === 'seat' && typeof opts.value === 'string' ? { seat: opts.value, surname: '' } : opts.value;
    else v = await pickHead(c, a, t, field, opts);
    if (v === undefined) return false;
    return writeHead(c, a, t, field, v);
  }

  /* ================= 계층 입력 창 (확정 설계 7-2 ⑤ — HT.maker.kin.outline) ================= */
  const SLASH = [
    { id: 'branch', label: '파 — 이 사람이 파조', hint: '[이름파]' },
    { id: 'adopted', label: '양자 — 위 줄이 양부', hint: '(양자)' },
    { id: 'unknown', label: '미상 — 이름 미상의 사람', hint: '미상' },
    { id: 'dates', label: '생몰', hint: '(생 ~ 몰)' },
  ];
  const ROW_H = 26;
  async function outlineImpl(c, a, opts) {
    const model = c.state.model;
    let root = null;
    if (opts.uid) {
      const k = String(opts.uid);
      root = nodeOfKey(model, /^[fcn]:/.test(k) ? k : `f:${k}`);
      if (!root) { HT.toast('뿌리로 고른 사람을 찾지 못했습니다 — 검사에서 떨어진 인물이면 먼저 고치세요.', 'error'); return false; }
    }
    const env = { model, draftId: a.draft.id, draft: a.draft };
    const d0 = root ? deriveOutline(model, root, env) : { rows: [], text: '' };
    const orig = new Map(d0.rows.map(r => [r.key, r]));
    let lines = d0.rows.length ? d0.text.split('\n') : [];
    let keys = d0.rows.map(r => r.key);
    if (opts.text) {
      const add = String(opts.text).replace(/\r\n?/g, '\n').split('\n').filter(l => str(l));
      const base = root ? 1 : 0;
      lines = lines.concat(add.map(l => INDENT.repeat(base) + l));
      keys = keys.concat(add.map(() => null));
    }
    const removed = new Map();
    const rootName = root ? targetOfNode(root).name : '';
    return new Promise(resolve => {
      const dlg = document.createElement('dialog');
      dlg.className = 'dlc-dialog mk-box mk-kin-dlg';
      dlg.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>계층 입력${root ? ` — ${esc(rootName)}` : ''}</h2><button type="button" class="icon-btn" data-kin-cancel aria-label="닫기">✕</button></div>
        <div class="dlg-body mk-kin-body">
          <div class="mk-kin-edit"><label class="mk-kin-label" for="mkKinText">한 줄에 한 사람 · 들여쓰기(Tab이나 공백 둘)가 한 세대</label><textarea id="mkKinText" data-kin-text spellcheck="false" autocomplete="off" wrap="off"></textarea>
            <p class="mk-kin-help">줄 꼴: <code>이름 (생 ~ 몰)</code> · 줄 끝 <code>[○○파]</code> = 이 사람이 파조 · <code>(양자)</code> = 위 줄이 양부 · 이름 <code>미상</code> = 이름 미상의 사람. <kbd>/</kbd>를 치면 넣을 것 목록이 뜹니다. ${root ? '첫 줄은 뿌리입니다.' : '맨 위 줄은 같은 이름의 사람이 있으면 그 사람으로 잇습니다.'}</p></div>
          <div class="mk-kin-view" data-kin-view role="tree" aria-label="나무 미리 보기"><div class="mk-kin-rows" data-kin-rows></div></div>
        </div>
        <div class="dlg-foot"><p class="mk-kin-sum" data-kin-sum role="status" aria-live="polite"></p><button type="button" class="btn" data-kin-cancel>취소</button><button type="button" class="btn btn-primary" data-kin-apply>적용</button></div></div>`;
      document.body.append(dlg);
      const ta = dlg.querySelector('[data-kin-text]');
      const view = dlg.querySelector('[data-kin-view]');
      const rowsEl = dlg.querySelector('[data-kin-rows]');
      const sumEl = dlg.querySelector('[data-kin-sum]');
      const applyBtn = dlg.querySelector('[data-kin-apply]');
      ta.value = lines.join('\n');
      let plan = null;
      let queued = 0;
      const recompute = () => {
        plan = planOutline({ model, draft: a.draft, lines, keys, root, orig });
        const s = plan.sum;
        const parts = [s.add && `새 사람 ${s.add}`, s.move && `부모 바꿈 ${s.move}`, s.rename && `이름 바꿈 ${s.rename}`, s.dates && `생몰 ${s.dates}`, s.branch && `파 ${s.branch}`, s.order && '형제 순서', s.remove && `지운 줄 ${s.remove}`].filter(Boolean);
        sumEl.innerHTML = plan.errors.length ? `<b class="mk-bad">빨간 줄 ${plan.errors.length}개</b> — 고치면 적용할 수 있습니다${parts.length ? ` · ${esc(parts.join(' · '))}` : ''}` : parts.length ? esc(parts.join(' · ')) + (plan.ops.skipped.length ? ` · 건너뜀 ${plan.ops.skipped.length}` : '') : '바뀐 것이 없습니다.';
        applyBtn.disabled = !!plan.errors.length || !parts.length;
        rowsEl.style.height = `${plan.rows.length * ROW_H}px`;
        paintRows();
      };
      const paintRows = () => {
        if (!plan) return;
        const top = Math.max(0, Math.floor(view.scrollTop / ROW_H) - 8);
        const end = Math.min(plan.rows.length, top + Math.ceil(view.clientHeight / ROW_H) + 16);
        const html = [];
        for (let i = top; i < end; i++) {
          const r = plan.rows[i];
          const chips = [r.target ? '' : '<span class="mk-kin-chip is-new">새</span>', r.adopted ? '<span class="mk-kin-chip">양자</span>' : '', r.branch ? `<span class="mk-kin-chip is-branch">${esc(r.branch)}</span>` : '', r.target && r.target.fig && isLineage(r.target.fig) ? '' : r.target && r.target.cell ? '<span class="mk-kin-chip">지도자</span>' : ''].join('');
          const years = [r.birthText, r.deathText].some(Boolean) ? `<small>${esc(r.birthText)} ~ ${esc(r.deathText)}</small>` : '';
          const pickBox = r.cands ? `<select data-kin-pick="${r.li}" aria-label="${esc(r.name)} — 같은 이름의 사람 고르기"><option value="">고르기…</option>${r.cands.map(t => `<option value="${esc(t.key)}">${esc(t.name)} · ${esc((model.trackMap && (model.trackMap.get(t.track) || {}).name) || t.track)}${t.fig ? ` · ${esc(t.fig.id)}` : t.cell ? ` · ${esc(t.cell.p.name)}` : ''}</option>`).join('')}<option value="#new">새 사람으로</option></select>` : '';
          html.push(`<div class="mk-kin-row${r.error ? ' is-bad' : ''}" role="treeitem" aria-level="${r.depth + 1}" style="top:${i * ROW_H}px;--d:${r.depth}" data-line="${r.li}"><i class="mk-kin-dot${r.unknown ? ' is-unknown' : ''}" aria-hidden="true"></i><span class="mk-kin-name">${r.unknown ? '이름 미상' : esc(r.name)}</span>${years}${chips}${r.error ? `<em class="mk-kin-err">${r.line}번째 줄: ${esc(r.error)}</em>` : ''}${pickBox}</div>`);
        }
        rowsEl.innerHTML = html.join('');
      };
      const sync = () => {
        const next = ta.value.split('\n');
        keys = remapKeys(lines, keys, next, removed);
        lines = next;
        if (!queued) queued = requestAnimationFrame(() => { queued = 0; recompute(); });
      };
      ta.addEventListener('input', sync);
      view.addEventListener('scroll', () => requestAnimationFrame(paintRows));
      view.addEventListener('change', e => {
        const s = e.target.closest('[data-kin-pick]');
        if (!s || !s.value) return;
        keys[Number(s.dataset.kinPick)] = s.value;
        recompute();
      });
      view.addEventListener('click', e => {
        const row = e.target.closest('[data-line]');
        if (!row || e.target.closest('select')) return;
        const li = Number(row.dataset.line);
        let pos = 0;
        for (let i = 0; i < li; i++) pos += lines[i].length + 1;
        ta.focus();
        ta.setSelectionRange(pos, pos + lines[li].length);
      });
      /* 키: Tab · Shift+Tab = 고른 줄 들여쓰기 · 내어쓰기, / = 넣을 것 목록 */
      const lineRange = () => {
        const v = ta.value;
        const a0 = v.lastIndexOf('\n', ta.selectionStart - 1) + 1;
        let b0 = v.indexOf('\n', ta.selectionEnd);
        if (b0 < 0) b0 = v.length;
        return [a0, b0];
      };
      const replaceRange = (a0, b0, text, selA, selB) => {
        ta.setSelectionRange(a0, b0);
        if (!document.execCommand || !document.execCommand('insertText', false, text)) {
          ta.setRangeText(text, a0, b0, 'end');
          ta.dispatchEvent(new Event('input', { bubbles: true }));
        }
        if (selA != null) ta.setSelectionRange(selA, selB);
      };
      let slash = null;
      const closeSlash = () => { if (slash) { slash.remove(); slash = null; } };
      const openSlash = () => {
        closeSlash();
        const [a0] = lineRange();
        const lineNo = ta.value.slice(0, a0).split('\n').length - 1;
        slash = document.createElement('div');
        slash.className = 'mk-kin-slash';
        slash.setAttribute('role', 'listbox');
        slash.setAttribute('aria-label', '넣을 것');
        slash.innerHTML = SLASH.map((s, i) => `<div role="option" class="mk-kin-opt${i ? '' : ' is-on'}" data-slash="${s.id}" aria-selected="${!i}"><b>${esc(s.label)}</b><small>${esc(s.hint)}</small></div>`).join('');
        const lh = parseFloat(getComputedStyle(ta).lineHeight) || 20;
        const er = ta.getBoundingClientRect();
        const pr = dlg.querySelector('.mk-kin-edit').getBoundingClientRect();
        slash.style.left = `${er.left - pr.left + 24}px`;
        slash.style.top = `${Math.min(er.bottom - pr.top - 8, er.top - pr.top + 8 + (lineNo + 1) * lh - ta.scrollTop)}px`;
        dlg.querySelector('.mk-kin-edit').append(slash);
        slash.addEventListener('pointerdown', e => { const o = e.target.closest('[data-slash]'); e.preventDefault(); if (o) doSlash(o.dataset.slash); });
      };
      const doSlash = id => {
        closeSlash();
        const caret = ta.selectionStart;
        const hasSlash = ta.value[caret - 1] === '/';
        if (hasSlash) replaceRange(caret - 1, caret, '');
        const [a0, b0] = lineRange();
        const r = readLine(ta.value.slice(a0, b0));
        const lead = (/^[\t ]*/.exec(ta.value.slice(a0, b0)) || [''])[0];
        const base = { depth: 0, name: r.name, birthText: r.birthText, deathText: r.deathText, adopted: r.adopted, branch: r.branch, unknown: r.unknown };
        if (id === 'branch') base.branch = `${r.name && !r.unknown ? r.name : ''}파`;
        if (id === 'adopted') base.adopted = true;
        if (id === 'unknown') { base.unknown = true; base.name = '미상'; }
        let text = lead + writeLine(base).replace(/^ +/, '');
        if (id === 'dates' && !r.birthText && !r.deathText) {
          const at = (lead + (base.unknown ? '미상' : base.name)).length;
          text = `${text.slice(0, at)} ( ~ )${text.slice(at)}`;
          replaceRange(a0, b0, text, a0 + at + 2, a0 + at + 2);
          return;
        }
        replaceRange(a0, b0, text, a0 + text.length, a0 + text.length);
      };
      ta.addEventListener('keydown', e => {
        if (e.isComposing) return;
        if (slash) {
          const opts2 = [...slash.querySelectorAll('[data-slash]')];
          const at = opts2.findIndex(o => o.classList.contains('is-on'));
          if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            const n = (at + (e.key === 'ArrowDown' ? 1 : -1) + opts2.length) % opts2.length;
            opts2.forEach((o, i) => { o.classList.toggle('is-on', i === n); o.setAttribute('aria-selected', String(i === n)); });
            return;
          }
          if (e.key === 'Enter' || e.key === 'Tab') { e.preventDefault(); doSlash(opts2[Math.max(0, at)].dataset.slash); return; }
          if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeSlash(); return; }
          closeSlash();
        }
        if (e.key === 'Tab') {
          e.preventDefault();
          const [a0, b0] = lineRange();
          const block = ta.value.slice(a0, b0).split('\n');
          const out = block.map(l => (e.shiftKey ? l.replace(/^(\t| {1,2})/, '') : INDENT + l)).join('\n');
          replaceRange(a0, b0, out, a0, a0 + out.length);
          return;
        }
        if (e.key === '/' && !e.ctrlKey && !e.altKey && !e.metaKey) setTimeout(openSlash, 0);
      });
      ta.addEventListener('blur', () => setTimeout(closeSlash, 0));
      let settled = false;
      const close = ok => {
        if (settled) return;
        settled = true;
        closeSlash();
        if (dlg.open) dlg.close();
        dlg.remove();
        resolve(ok);
      };
      const changed = () => ta.value !== d0.text + (opts.text ? '' : '') || !!opts.text;
      const cancel = async () => {
        if (changed() && plan && Object.values(plan.sum).some(Boolean)) {
          const q = await a.ask('계층 입력에서 고친 것을 적용하지 않고 닫을까요?', { title: '계층 입력', yes: '닫기', no: '이어서 고치기', plainNo: true });
          if (q !== 'yes') return;
        }
        close(false);
      };
      dlg.addEventListener('cancel', e => { e.preventDefault(); cancel(); });
      dlg.addEventListener('click', e => { if (e.target.closest('[data-kin-cancel]')) cancel(); });
      applyBtn.addEventListener('click', async () => {
        recompute();
        if (!plan || plan.errors.length) return;
        let withRemove = false;
        const rm = plan.ops.remove;
        if (rm.length) {
          const lineage = rm.filter(x => x.lineage);
          const cut = rm.filter(x => !x.lineage && x.own);
          const foreign = rm.length - lineage.length - cut.length;
          const used = lineage.filter(x => arr(model.events).some(ev => arr(ev.figures).some(f => f && (f.uid === x.target.fig.uid || f === x.target.fig))) || arr(x.target.node && x.target.node.groups).length).length;
          const q = await a.ask(`지운 줄 ${rm.length}개: ${[lineage.length && `계보 전용 인물 ${lineage.length}명은 작업본에서 지우고`, cut.length && `띠 인물 · 지도자 ${cut.length}명은 이 부모와의 줄만 끊습니다`, foreign && `다른 DLC의 사람 ${foreign}명은 그대로 둡니다`].filter(Boolean).join(', ')}.${used ? ` 그 가운데 ${used}명은 사건의 관련 인물이나 단체의 구성원으로 쓰입니다 — 그곳에는 이름만 남습니다.` : ''}`, { title: '계층 입력 — 지운 줄', yes: '지우고 적용', no: '지우지 않고 적용', plainNo: true });
          if (q === 'cancel') return;
          withRemove = q === 'yes';
        }
        const p = plan;
        const big = p.rows.length > 20 || p.ops.add.length > 20;
        const ok = await a.transact(d => applyOutline(d, p, model, { remove: withRemove }), `계층 입력 적용 (${[p.sum.add && `새 사람 ${p.sum.add}`, p.sum.move && `부모 바꿈 ${p.sum.move}`, p.sum.rename && `이름 ${p.sum.rename}`, p.sum.branch && `파 ${p.sum.branch}`, withRemove && p.sum.remove && `지움 ${p.sum.remove}`].filter(Boolean).join(' · ') || '고침'})`, { snapshot: big });
        if (!ok) return;
        if (p.ops.skipped.length) HT.toast(`적용했습니다. 건너뛴 것 ${p.ops.skipped.length}개: ${p.ops.skipped.slice(0, 3).join(' · ')}${p.ops.skipped.length > 3 ? ' …' : ''}`);
        else HT.toast('계층 입력을 적용했습니다.', 'ok');
        close(true);
      });
      dlg.showModal();
      recompute();
      ta.focus();
      ta.setSelectionRange(ta.value.length, ta.value.length);
    });
  }

  /* ================= 세계표 · 승계표 창의 사람 더하기 · 지우기 (HT.maker.kin.addRelative · removePerson) =================
     카드 메뉴(＋ 자식 · 형제 · 배우자 · 부모)와 세계표 바닥의 「＋ 사람」이 부릅니다. 새 사람은 내 DLC의 인물(기본 계보 전용) — 한 걸음, 되돌리기 한 번 */
  const REL_ORDER = ['child', 'sibling', 'spouse', 'parent'];
  async function addRelativeImpl(c, a, opts) {
    const model = c.state.model;
    const t = targetOfKey(model, opts.key);
    if (!t) { HT.toast('기준 사람을 찾지 못했습니다.', 'error'); return false; }
    let rel = REL_ORDER.includes(opts.rel) ? opts.rel : 'child';
    let as = 'father';
    const segHTML = (name, list, cur) => `<div class="kv-seg mk-kin-seg" role="radiogroup" aria-label="${name === 'rel' ? '관계' : '자리'}" data-seg="${name}">${list.map(([v, w]) => `<button type="button" role="radio" data-v="${v}" aria-checked="${v === cur}">${w}</button>`).join('')}</div>`;
    const body = `<p class="mk-kin-pop-note">기준 <b>${esc(t.name)}</b></p>
      ${segHTML('rel', REL_ORDER.map(r => [r, REL_WORD[r]]), rel)}
      <div class="mk-kin-pop-row"><label class="mk-kin-pop-field">이름 <input data-f="name" data-pop-focus autocomplete="off" spellcheck="false"></label><label class="check"><input type="checkbox" data-f="unknown"> 미상</label></div>
      <label class="mk-kin-pop-row">직함 <input data-f="role" autocomplete="off" spellcheck="false"></label>
      <div class="mk-kin-pop-row"><label class="mk-kin-pop-field">생 <input data-f="birth" autocomplete="off" spellcheck="false"></label><label class="mk-kin-pop-field">몰 <input data-f="death" autocomplete="off" spellcheck="false"></label></div>
      <div class="mk-kin-pop-row" data-when-as><span data-as-word></span>${segHTML('as', [['father', '부'], ['mother', '모']], as)}<label class="check"><input type="checkbox" data-f="adopted"> <span data-adopt-word></span></label></div>
      <label class="check"><input type="checkbox" data-f="lineage" checked> 계보 전용</label>
      <p class="mk-kin-pop-err" data-err role="alert" hidden></p>
      <div class="mk-kin-pop-foot"><button type="button" class="btn btn-sm" data-pop-outline title="여러 사람을 한 번에 — 들여쓰기 글">계층 입력</button><span class="spacer"></span><button type="button" class="btn btn-sm btn-primary" data-pop-ok>더하기</button></div>`;
    const plan = await popover(opts.anchor || null, '사람 더하기', body, (pop, done) => {
      const $f = k => pop.querySelector(`[data-f="${k}"]`);
      const err = pop.querySelector('[data-err]');
      const sync = () => {
        for (const g of pop.querySelectorAll('[data-seg]')) for (const b of g.children) b.setAttribute('aria-checked', String(b.dataset.v === (g.dataset.seg === 'rel' ? rel : as)));
        const row = pop.querySelector('[data-when-as]');
        row.hidden = rel !== 'child' && rel !== 'parent';
        pop.querySelector('[data-as-word]').textContent = rel === 'child' ? '기준' : '새 사람';
        pop.querySelector('[data-adopt-word]').textContent = rel === 'child' ? '양자' : as === 'mother' ? '양모' : '양부';
        $f('name').disabled = $f('unknown').checked;
        $f('lineage').disabled = $f('unknown').checked;
        err.hidden = true;
      };
      const submit = () => {
        const dates = {};
        for (const k of ['birth', 'death']) {
          const d = readEdge($f(k).value);
          if (d && d.error != null) { err.textContent = `${k === 'birth' ? '생' : '몰'} "${d.text}"을(를) 읽을 수 없습니다${d.error ? ` (${d.error})` : ''}`; err.hidden = false; return; }
          dates[k] = d && !d.unknown ? d : null;
        }
        const p = planRelative(c.state.model, a.draft, t.key, { rel, as, name: $f('name').value, unknown: $f('unknown').checked, role: $f('role').value, birth: dates.birth, death: dates.death, adopted: $f('adopted').checked, lineage: $f('lineage').checked });
        if (p.error) { err.textContent = p.error; err.hidden = false; return; }
        done(Object.assign(p, { rel }));
      };
      pop.addEventListener('click', e => {
        const b = e.target.closest('[data-seg] [data-v]');
        if (b) {
          if (b.parentElement.dataset.seg === 'rel') rel = b.dataset.v;
          else as = b.dataset.v;
          sync();
        }
        if (e.target.closest('[data-pop-ok]')) submit();
        if (e.target.closest('[data-pop-outline]')) done({ outline: true });
      });
      pop.addEventListener('change', sync);
      pop.addEventListener('keydown', e => {
        if (e.key === 'Enter' && e.target.matches('input:not([type="checkbox"])') && !e.isComposing) { e.preventDefault(); submit(); }
      });
      sync();
    }, 'mk-kin-add');
    if (!plan) return false;
    if (plan.outline) return outline({ uid: t.key });
    /* 남의 DLC 사람에게 부모를 적으면 덮어쓰기 — 잠긴 팩이면 못 함 */
    const host = plan.edit && !kinHolder(a.draft, plan.edit.target) ? plan.edit.target.fig || (plan.edit.target.cell && plan.edit.target.cell.p) : null;
    if (host && a.isLocked && a.isLocked(host)) { HT.toast(`잠긴 팩 «${host.packName}»의 사람이라 부모를 적을 수 없습니다 — 불러온 팩 탭에서 자물쇠를 풀고 다시.`, 'error'); return false; }
    const editingHost = plan.edit && c.state.editing && c.state.editing === (plan.edit.target.fig ? plan.edit.target.fig.uid : plan.edit.target.cell && plan.edit.target.cell.p.uid);
    const ok = await a.transact(d => applyRelative(d, plan, a), `«${plan.base}»의 ${REL_WORD[plan.rel]} «${plan.fig.name}» 더함`, { keepEditor: !editingHost });
    if (!ok) return false;
    const fc = HT.kinView && HT.kinView.current && HT.kinView.current();
    const shown = !!fc && fc.indexOf(plan.newKey) >= 0;
    if (shown) fc.focusKey(plan.newKey);
    /* 세계표는 그 가문의 사람만 — 시조의 부모 · 다른 가문의 배우자 · 모계 자식은 이 표 밖(인물 창 · 승계표 · 그 사람의 가문 세계표에서 봄) */
    HT.toast(`${REL_WORD[plan.rel]} «${plan.fig.name}»을(를) 더했습니다.${fc && !shown ? ' 이 가문 밖의 사람이라 지금 세계표에는 놓이지 않습니다 — 인물 창에서 봅니다.' : ''}`, 'ok');
    return plan.newKey;
  }
  /** 내 DLC의 인물 지우기 (세계표 카드 메뉴) — 그 사람을 가리키던 부모 · 배우자 줄에는 이름만 남음(검사 창에 알림) */
  async function removePersonImpl(c, a, opts) {
    const model = c.state.model;
    const t = targetOfKey(model, opts.key);
    if (!t || !t.fig || t.fig.packId !== a.draft.id) { HT.toast('내 DLC의 인물만 지울 수 있습니다 — 지도자는 나라 편집 창에서, 다른 DLC의 사람은 그 사람의 창에서 숨깁니다.', 'error'); return false; }
    const kids = arr(t.node && t.node.children).length;
    const spouses = arr(t.node && t.node.spouses).length;
    const tie = [kids && `자식 ${kids}명`, spouses && `배우자 ${spouses}명`].filter(Boolean).join(' · ');
    const q = await a.ask(`«${t.name}»을(를) 작업본에서 지웁니다.${tie ? ` 이 사람과 이어진 ${tie}의 줄에는 이름만 남습니다.` : ''}`, { title: '사람 지우기', yes: '지우기', no: '', danger: true });
    if (q !== 'yes') return false;
    return !!(await a.transact(d => (HT.draft.removeOwn(d, t.fig.id), d), `«${t.name}» 지움`, { keepEditor: c.state.editing !== t.fig.uid }));
  }

  /* ================= 이음 ================= */
  /** js/maker.js의 start()가 작업실을 세운 뒤 부릅니다 — ctx = viewer.js가 메이커에 넘긴 것, api = 메이커의 편집 길(transact · draft · isLocked · rawOf · baseModel · ask · applyDrop) */
  function mount(c, a) {
    ctx = c;
    api = a;
  }
  const ready = () => !!(api && api.draft && ctx && ctx.state && ctx.state.model);
  /** 머리 칩 고치기 (확정 설계 7-1) */
  async function editHead(opts = {}) {
    if (!ready()) return false;
    try {
      return !!(await editHeadImpl(ctx, api, opts || {}));
    } catch (error) {
      HT.toast(error.message || '칩을 고치지 못했습니다.', 'error');
      return false;
    }
  }
  /** 계층 입력 창 (확정 설계 7-2 ⑤) */
  async function outline(opts = {}) {
    if (!ready()) return false;
    if (document.querySelector('dialog.mk-kin-dlg')) return false;
    return !!(await outlineImpl(ctx, api, opts || {}));
  }
  HT.makerKin = {
    mount, figuresOf, peopleIndex, findPeople, pickOne, whoRef, refText, parentText, setParent, targetOfNode, targetOfKey,
    readLine, writeLine, looksLikeOutline, deriveOutline, remapKeys, planOutline, applyOutline, renameWho, houseGuess, checks, attachFinder, KIN_LIMIT,
    planPeople, applyPeople, planRelative, applyRelative,
  };
  /** 세계표 · 승계표 창의 사람 더하기 — { key(기준 사람 자리 열쇠), rel?, anchor? } → 새 사람의 열쇠 (못 하면 false) */
  async function addRelative(opts = {}) {
    if (!ready() || document.querySelector('.mk-kin-add')) return false;
    try {
      return await addRelativeImpl(ctx, api, opts || {});
    } catch (error) {
      HT.toast(error.message || '사람을 더하지 못했습니다.', 'error');
      return false;
    }
  }
  /** 내 DLC의 인물 지우기 — { key } */
  async function removePerson(opts = {}) {
    if (!ready()) return false;
    return !!(await removePersonImpl(ctx, api, opts || {}));
  }
  /** 그 사람을 지울 수 있는지(내 DLC의 인물) — 메뉴에 '지우기'를 둘지 */
  const removable = key => {
    if (!ready()) return false;
    const t = targetOfKey(ctx.state.model, key);
    return !!(t && t.fig && t.fig.packId === api.draft.id);
  };
  HT.maker = HT.maker || {};
  HT.maker.kin = { editHead, ready, outline, addRelative, removePerson, removable };
})();

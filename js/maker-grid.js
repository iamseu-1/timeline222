/* DLC 메이커 — 표 계산과 보이는 줄만 그리는 편집 표. 연표 배포물에서는 읽지 않습니다. */
(function () {
  'use strict';
  const HT = window.HT, clone = x => JSON.parse(JSON.stringify(x)), arr = x => Array.isArray(x) ? x : [];
  const col = (key, label, type = 'text', extra = {}) => ({ key, label, type, ...extra });
  const date = (key, label) => col(key, label, 'date');
  const common = [date('start', '시작'), date('end', '끝'), col('track', '트랙', 'track')];
  const tail = [col('description', '설명'), col('note', '메모'), col('document', '문서', 'document')];
  const subNames = { leaders: '지도자', cabinets: '내각', eras: '연호', capitals: '도읍', phases: '시기', ranks: '지위' };
  const words = { periods: '객체', events: '사건', figures: '사람', organs: '기관', cultures: '문화', dynasties: '왕조', epochs: '시대 구분', scopes: '대범위', tracks: '트랙', spheres: '문화권', categories: '분류', peoples: '민족', rankDefs: '지위', houses: '가문', patches: '덮어쓰기' };
  const choices = {
    importance: () => [{ id: '1', name: '낮음' }, { id: '2', name: '보통' }, { id: '3', name: '높음' }],
    kind: () => HT.POLITY_KINDS,
    otype: () => HT.F4.TYPES.filter(t => t.id !== 'person'), // 형식 4의 객체 종류(사람은 인물 표)
    status: () => HT.F4.STATUSES,
    certainty: () => HT.CERTAINTY,
    historicity: () => HT.HISTORICITY,
    check: () => [{ id: '계보 전용', name: '계보 전용' }], // 체크 칸은 지금 계보 전용 하나 (D1 — 고르기: 비움 · 계보 전용)
  };
  const schemas = {
    periods: [col('color', '색', 'color'), col('name', '이름'), ...common, col('kind', '종류', 'kind'), col('type', '객체 종류', 'otype'), col('status', '정통성', 'status'), col('importance', '중요도', 'importance'), col('people', '민족'), col('partOf', '소속'), col('historicity', '실재성', 'historicity'), col('certainty', '확실성', 'certainty'), ...Object.entries(subNames).map(([k, n]) => col(k, n, 'children')), ...tail],
    events: [date('start', '날짜'), date('end', '끝'), col('title', '제목'), col('track', '트랙', 'track'), col('category', '분류', 'category'), col('importance', '중요도', 'importance'), col('spot', '자리', 'number'), col('polity', '정권'), col('source', '출처'), ...tail],
    /* 계보(D1 확정 설계 7-2 ④): 계보 전용(체크) · 부 · 모 · 양부 · 생부(사람 참조 — 그 역할의 부모 줄 하나만 고침) · 형제 순서. 가문 열에 파 이름을 적습니다 */
    figures: [col('name', '이름'), date('birth', '태어남'), date('death', '사망'), ...common, col('service', '활동 기록', 'detail'), col('role', '역할'), col('importance', '중요도', 'importance'), col('house', '가문'), col('lineageOnly', '계보 전용', 'check'), ...['father', 'mother', 'adoptive-father', 'birth-father'].map(role => col(`kin:${role}`, HT.parentRoleName ? HT.parentRoleName(role) : role, 'kin', { role })), col('order', '형제 순서', 'number'), ...tail],
    organs: [col('name', '이름'), ...common, col('host', '소속'), ...tail],
    cultures: [col('name', '이름'), ...common, col('people', '민족'), col('partOf', '소속'), ...tail],
    dynasties: [col('name', '이름'), ...common, col('polities', '정권', 'list'), col('house', '가문'), ...tail],
    epochs: [col('name', '이름'), ...common, col('sphere', '문화권', 'select', { options: (draft, model) => HT.makerKit.sphereChoices(draft, model) }), col('color', '색', 'color'), ...tail], // 문화권(형식 4 더하기 · 5단계 과제 6) — 트랙과 양자택일(둘 다면 트랙 우선 · 검사 경고)
    scopes: [col('name', '이름'), ...common, col('members', '구성 정권', 'list'), col('host', '상징적 본국'), col('epoch', '시대 구분'), ...tail],
    patches: [col('target', '대상', 'readonly'), col('pack', '대상 팩', 'readonly'), col('set', '고친 칸', 'readonly'), col('hide', '숨김', 'readonly'), col('note', '메모'), col('actions', '동작', 'readonly')], // 메모(왜 바꿨는지)만 고칠 수 있음 — 2026-10-23
  };
  function columns(source) {
    if (source.sub) {
      const cols = [col(source.sub === 'capitals' ? 'city' : 'name', source.sub === 'ranks' ? '지위' : source.sub === 'capitals' ? '도시' : '이름'), date('start', '시작'), date('end', '끝')];
      if (source.sub === 'leaders') cols.push(col('ordinal', '대수', 'number'), col('temple', '묘호'), col('title', '시호'), col('given', '본명'), col('house', '가문'), col('rank', '지위'));
      if (source.sub === 'capitals') cols.push(col('as', '그때 이름'), col('role', '역할'), col('label', '시기 이름'), col('group', '묶음'), col('event', '천도 사건'));
      return cols.concat(col('certainty', '확실성', 'certainty'), col('note', '메모'));
    }
    const base = HT.makerKit.BASE_TABLES[source.list];
    return schemas[source.list] || (base && base.cols ? base.cols.map(c => ({ ...c })).concat(col('uses', '쓰는 곳', 'readonly')) : []);
  }
  function rowsOf(draft, source, create = false) {
    if (!draft) return [];
    if (!source.sub) return create ? (draft[source.list] ||= []) : arr(draft[source.list]);
    const p = arr(draft.periods).find(x => x.id === source.parent);
    if (!p) return [];
    if (source.sub === 'phases') {
      if (create) p.phases = HT.readPhases(p.phases).list;
      if (create && !p.phases.length) p.phases = [{ scheme: '시기', spans: [] }];
      const sys = (create ? p.phases : HT.readPhases(p.phases).list)[source.system || 0];
      return sys ? create ? (sys.spans ||= []) : arr(sys.spans) : [];
    }
    const key = source.sub === 'leaders' && !p.leaders && p.reigns ? 'reigns' : source.sub;
    return create ? (p[key] ||= []) : arr(p[key]);
  }
  function objectRow(x, sub) {
    if (sub === 'capitals') return clone(HT.formCell('capitals', x) || {});
    if (typeof x === 'string') return { name: x };
    if (!Array.isArray(x)) return clone(x || {});
    const o = { name: x[0], start: x[1], end: x[2] };
    if (x[3] != null) o.note = x[3];
    return o;
  }
  /** 체크 칸(계보 전용)의 글 → true · false (읽지 못하면 null) */
  const readCheck = (s, c) => {
    const t = String(s ?? '').trim().toLowerCase();
    if (!t || ['아니요', '아니오', '아님', '거짓', 'false', '0', 'n', 'no', 'x', '-', '✕', '✗'].includes(t)) return false;
    if (['예', '네', '참', 'true', '1', 'y', 'yes', 'o', 'v', '✓', '✔', '☑', String(c && c.label || '').toLowerCase()].includes(t)) return true;
    return null;
  };
  /** 부모 칸을 읽을 때 한 번만 짓는 것 — 같은 붙여넣기 안의 줄(이름 → 차례대로 · id), 새 줄 · 이름을 바꾼 줄(모델에는 아직 그 이름이 없음 — 7-4의 '이름이 하나뿐인가'에 셈).
      batch = [{ index, x, fresh }] (차례 오름) */
  function kinContext(draft, model, batch = []) {
    const K = HT.makerKin, ix = K ? K.peopleIndex(model) : null, modelFig = y => (ix && ix.figByUid.get(`${draft.id}/${y.id}`)) || null;
    const fresh = new Set(batch.filter(r => r.fresh).map(r => r.x));
    const extra = batch.filter(r => r.fresh || (modelFig(r.x) && modelFig(r.x).name !== r.x.name)).map(r => Object.assign({ id: r.x.id, name: r.x.name, track: r.x.track }, r.fresh ? {} : { uid: `${draft.id}/${r.x.id}` }));
    const byName = new Map(), byId = new Map();
    for (const r of batch) { const n = String(r.x.name || '').trim(); (byName.get(n) || byName.set(n, []).get(n)).push(r); byId.set(r.x.id, r); }
    return { draft, model, modelFig, fresh, extra, byName, byId };
  }
  /** 부모 칸(kin:역할)의 친 글 → 적을 사람 참조 (확정 설계 7-4 — js/maker-kin.js의 whoRef). 찾지 못하면 친 글 그대로(모델이 그 이름의 자리를 만들고 검사에서 알림), 같은 이름이 여럿이면 Error.
      같은 붙여넣기 안에 그 이름이 있으면 바로 위 줄 가운데 가장 가까운 것(없으면 아래의 가장 가까운 것). 돌려주는 값: { ref, missing } */
  function kinRef(text, x, index, kc) {
    const K = HT.makerKin, s = String(text ?? '').trim();
    if (!s || !K) return { ref: s, missing: false };
    if (HT.isUnknownWho(s)) return { ref: '미상', missing: false };
    const env = { model: kc.model, draftId: kc.draft.id, track: x.track, extra: kc.extra };
    const asTarget = y => { const f = !kc.fresh.has(y) && kc.modelFig(y); return f ? Object.assign({}, K.targetOfNode(HT.personOf(kc.model, f)) || { fig: f, key: `f:${f.uid}` }, { fig: f, name: y.name, track: y.track }) : { isNew: true, id: y.id, name: y.name, track: y.track }; };
    const sameId = kc.byId.get(s);
    if (sameId && sameId.x !== x) return { ref: K.whoRef(asTarget(sameId.x), env), missing: false };
    const named = (kc.byName.get(s) || []).filter(r => r.x !== x);
    if (named.length) {
      let lo = 0, hi = named.length; // 차례 오름 — index보다 앞선 것 가운데 마지막(이분 탐색)
      while (lo < hi) { const m = (lo + hi) >> 1; if (named[m].index < index) lo = m + 1; else hi = m; }
      return { ref: K.whoRef(asTarget((named[lo - 1] || named[lo]).x), env), missing: false };
    }
    const hits = K.findPeople(s, { model: kc.model, draftId: kc.draft.id });
    const one = K.pickOne(hits, x.track);
    if (one) return { ref: K.whoRef(one, env), missing: false };
    if (hits.length > 1) throw Error(`"${s}"은(는) 같은 이름의 사람이 ${hits.length}명이라 고를 수 없습니다 — 칸에서 세 글자 넘게 쳐 뜨는 찾기 상자로 고르거나 인물 id로 적으세요.`);
    return { ref: s, missing: true };
  }
  function value(draft, source, row, c) {
    const x = source.sub ? objectRow(row, source.sub) : row;
    if (c.nest) return HT.makerKit.nestGet(x, c.nest) ?? ''; // 안쪽 열쇠 칸(문화권의 지도자 표기 낱말 — 6단계 D3)
    if (c.type === 'check') return x[c.key] === true ? c.label : '';
    if (c.type === 'kin') return HT.makerKin ? HT.makerKin.parentText(x, c.role) : '';
    if (c.type === 'date') return x[c.key + 'Unknown'] || HT.isUnknownText(x[c.key]) ? '미정' : c.key === 'end' && x.ongoing ? '현재' : HT.dateInputValue(x, c.key) || '';
    if (c.type === 'document') return (draft.documents || {})[x.id] || (draft.documents || {})[draft.id + '/' + x.id] || '';
    if (c.key === 'uses') return HT.makerKit.findUsers(draft, HT.makerKit.BASE_TABLES[source.list], x).length;
    if (c.key === 'pack' && source.list === 'patches') return String(x.target || '').split('/')[0];
    if (c.key === 'set' && source.list === 'patches') return Object.keys(x.set || {}).join(' · ');
    if (c.type === 'children' || c.type === 'detail') return arr(x[c.key]).length;
    if (Array.isArray(x[c.key])) return x[c.key].map(v => typeof v === 'object' ? v.polity || v.name || '' : v).join(', ');
    if (x[c.key] && typeof x[c.key] === 'object') return x[c.key].polity || x[c.key].name || '속성에서 고치기';
    return x[c.key] ?? '';
  }
  function options(c, draft, model) {
    if (c.options) return typeof c.options === 'function' ? c.options(draft, model) : c.options; // 함수면 (작업본, 모델)로 — 트랙의 문화권(켠 DLC · 작업본이 만든 것까지)
    if (c.type === 'track') return [...new Map([...(model?.tracks || []), ...arr(draft.tracks)].map(x => [x.id, x])).values()];
    if (c.type === 'category') return [...new Map([...HT.DEFAULT_CATEGORIES, ...arr(draft.categories)].map(x => [x.id, x])).values()];
    return choices[c.type]?.() || [];
  }
  const norm = s => String(s).toLowerCase().replace(/[\s_·.()]/g, '');
  const structuredValue = v => v && typeof v === 'object' && (!Array.isArray(v) || v.some(x => x && typeof x === 'object'));
  function parse(c, text, row, draft, source, model) {
    const s = String(text).trim(), k = c.key;
    if (['readonly', 'children', 'detail'].includes(c.type)) throw Error('속성 창이나 하위 표에서 고칩니다.');
    if (c.nest) { HT.makerKit.nestSet(row, c.nest, s); return; } // 안쪽 열쇠 칸 — 비우면 그 칸을, 안이 다 비면 바깥 열쇠도 지움
    if (structuredValue(row[k]) && c.type !== 'date') throw Error('기간이나 부가 정보가 있는 값은 속성 창에서 고칩니다.');
    if (['name', 'title', 'id'].includes(k) && !s) throw Error('비울 수 없는 칸입니다.');
    if (c.type === 'date') {
      delete row[k + 'At']; delete row[k + 'Unknown']; delete row[k + 'Hint'];
      if (k === 'end') delete row.ongoing;
      if (!s) { delete row[k]; return; }
      if (HT.isUnknownText(s)) { row[k] = '미정'; row[k + 'Unknown'] = true; return; }
      if (k === 'end' && HT.isOngoingText(s)) { delete row[k]; row.ongoing = true; return; }
      const d = HT.readDate(s);
      if (!d || !Number.isFinite(d.t)) throw Error(d?.error || '날짜를 읽을 수 없습니다.');
      row[k] = d.t; if (d.at) row[k + 'At'] = d.at; return;
    }
    if (c.type === 'id' && (!HT.ID_RE.test(s) || arr(draft[source.list]).some(x => x !== row && x.id === s && x.id !== row.id))) throw Error('영문·숫자·- _ .로 겹치지 않는 id를 적으세요.');
    if (c.type === 'color' && s && !/^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(s) && !arr(HT.PASTEL).some(x => x.id === s)) throw Error('색은 # 뒤의 색 번호 또는 팔레트 이름으로 적으세요.');
    if (c.type === 'check') {
      const on = readCheck(s, c);
      if (on == null) throw Error('예 · 아니요(또는 비움)로 적으세요.');
      if (on) row[k] = true; else delete row[k];
      return;
    }
    if (c.type === 'kin') { HT.makerKin?.setParent(row, c.role, kinRef(s, row, -1, kinContext(draft, model)).ref); return; }
    if (c.type === 'number' || c.type === 'importance') {
      if (!s) { delete row[k]; return; }
      const opts = options(c, draft, model), match = opts.find(x => x.name === s);
      const n = Number(match ? match.id : s);
      if (!Number.isFinite(n) || c.type === 'importance' && ![1, 2, 3].includes(n) && !(n === 0 && source.list === 'periods') || k === 'spot' && (n < 0 || n > 1)) throw Error(k === 'spot' ? '0(처음) ~ 1(끝) 사이의 수를 적으세요 — 비우면 가운데.' : '범위에 맞는 숫자를 적으세요.');
      row[k] = n; return;
    }
    const opts = options(c, draft, model);
    if (opts.length && s) {
      const hit = opts.find(x => x.id === s || x.name === s || x.short === s);
      if (!hit) throw Error('목록에 있는 값을 고르세요.');
      row[k] = hit.id; return;
    }
    if (c.type === 'list') row[k] = s.split(/[,，]/).map(x => x.trim()).filter(Boolean);
    else if (!s) delete row[k];
    else row[k] = s;
  }
  function rowProblem(x, source) {
    if (!String(x.title || x.name || x.epoch || x.city || x.temple || x.given || '').trim() && source.list !== 'patches') return '이름 또는 제목이 필요합니다.';
    for (const [a, b] of [['start', 'end'], ['birth', 'death']]) {
      const s = HT.readDate(x[a], x[a + 'At']), e = HT.readDate(x[b], x[b + 'At']);
      if (s && e && Number.isFinite(s.t) && Number.isFinite(e.t) && e.t < s.t) return '끝이 시작보다 앞설 수 없습니다.';
    }
    if (!source.sub && ['periods', 'events', 'organs', 'cultures', 'dynasties', 'epochs'].includes(source.list)) {
      if (x.start == null && x.end == null) return '시작 또는 미정 연대가 필요합니다.';
      if (source.list !== 'epochs' && !x.track) return '트랙을 고르세요.';
    }
    return '';
  }
  function moveCellDocuments(draft, uid, before, after, change = null) {
    const moves = [];
    const cells = (x, kind) => {
      if (kind === 'phases') return HT.readPhases(x.phases).list.flatMap(s => arr(s.spans).map(c => ({ ...objectRow(c), docName: s.scheme ? `${s.scheme} · ${c.name}` : c.name })));
      return arr(x[kind] || (kind === 'leaders' ? x.reigns : null)).map(c => { const o = objectRow(c, kind); return { ...o, name: o.name || o.as || o.city || o.temple || o.title || o.given }; });
    };
    for (const key of Object.keys(draft.documents || {})) {
      const parsed = HT.docKey.parse(HT.docKey.absolute(key, draft.id)); if (parsed.type !== 'cell' || parsed.uid !== uid) continue;
      const a = cells(before, parsed.cellKind), b = cells(after, parsed.cellKind);
      const i = a.findIndex(c => (c.docName || c.name) === parsed.name && (c.start == null || Math.floor(HT.readDate(c.start, c.startAt)?.t + 1e-9) === parsed.start));
      if (i < 0 || !b[i]) continue;
      let start = HT.readDate(b[i].start, b[i].startAt)?.t;
      if (!Number.isFinite(start)) start = change?.part === 'move' ? HT.makerDrag.moveDate(parsed.start, null, change.amount, change.unit).value : parsed.start;
      const base = HT.docKey.cell(parsed.uid, parsed.cellKind, { ...b[i], start }), full = HT.docKey.join(base, parsed.sub);
      const target = key.includes(draft.id + '/') ? full : full.replace('cell:' + draft.id + '/', 'cell:');
      if (target !== key) moves.push([key, target, draft.documents[key]]);
    }
    const oldKeys = new Set(moves.map(x => x[0]));
    for (const [, target] of moves) if (Object.hasOwn(draft.documents, target) && !oldKeys.has(target)) throw Error('옮길 칸 문서와 같은 이름의 문서가 이미 있습니다.');
    for (const [key] of moves) delete draft.documents[key];
    for (const [, target, text] of moves) draft.documents[target] = text;
    return moves.length;
  }
  function plan(draft, source, writes, model = null, packs = [], opts = {}) {
    const next = clone(draft), rows = rowsOf(next, source, true), cols = columns(source), errors = [], grouped = new Map();
    let added = 0, changed = 0;
    /* 부모 칸(kin:역할)은 두 번 읽습니다 — 먼저 줄을 모두 만들고(같은 붙여넣기의 새 사람도 id가 생김), 다음에 부모 글을 같은 붙여넣기 안의 이름 → 작업본 · 켠 팩의 사람 차례로 찾아 적습니다(확정 설계 7-2 ④).
       족보 붙여넣기(부모 열이 있고 활동 시작 · 끝 · 계보 전용 열이 없음)의 새 줄은 계보 전용 인물로(활동 시작을 지어 넣지 않음) */
    const kinCells = [], accepted = [], missing = [];
    const kinPaste = source.list === 'figures' && !source.sub && writes.some(w => /^kin:/.test(w.key)) && !writes.some(w => ['start', 'end', 'lineageOnly'].includes(w.key));
    let lineageAdded = 0;
    const usedIds = new Set(HT.draft.LISTS.flatMap(k => arr(next[k]).map(o => o.id))); // 새 줄 id — 한 번 모으고 줄마다 더함(수천 줄 붙여넣기에서 줄마다 모두 다시 모으지 않게)
    for (const w of writes) { if (!Number.isInteger(w.row) || w.row < 0) continue; if (!grouped.has(w.row)) grouped.set(w.row, []); grouped.get(w.row).push(w); }
    for (const [index, cells] of grouped) {
      const existing = rows[index], fresh = !existing;
      const x = source.sub ? objectRow(existing, source.sub) : clone(existing || {});
      const old = clone(x), used = usedIds;
      if (fresh && !source.sub) { x.id = HT.makerKit.uniqueId(source.list.replace(/s$/, '') + '-1', used); x[source.list === 'events' ? 'title' : 'name'] = '새 ' + words[source.list]; if (HT.makerKit.kindOfList(source.list)) { x.track = rows.at(-1)?.track || arr(next.tracks)[0]?.id || model?.tracks?.[0]?.id || ''; x.start = rows.at(-1)?.start ?? 1; } }
      if (fresh && source.sub) { x[source.sub === 'capitals' ? 'city' : 'name'] = '새 ' + subNames[source.sub]; x.start = arr(next.periods).find(p => p.id === source.parent)?.start ?? 1; }
      const docs = [], kins = [];
      for (const w of cells) {
        const c = cols.find(c => c.key === w.key); if (!c) { errors.push({ ...w, message: '알 수 없는 열입니다.' }); continue; }
        if (c.type === 'kin') { kins.push({ w, c }); continue; }
        const before = clone(x);
        try { if (c.type === 'document') docs.push(String(w.text)); else parse(c, w.text, x, next, source, model); }
        catch (error) { for (const k of Object.keys(x)) delete x[k]; Object.assign(x, before); errors.push({ ...w, message: error.message }); }
      }
      if (fresh && kinPaste && x.lineageOnly !== false) { x.lineageOnly = true; delete x.start; lineageAdded++; }
      const problem = rowProblem(x, source);
      if (problem) { for (const w of cells) errors.push({ ...w, message: problem }); continue; }
      const same = !fresh && JSON.stringify(old) === JSON.stringify(x) && !docs.length;
      if (fresh) { rows.push(x); added++; } else { rows[index] = x; if (!same) changed++; }
      accepted.push({ index, x, fresh, same, old });
      if (x.id) usedIds.add(x.id);
      for (const k of kins) kinCells.push({ ...k, index, x });
      if (!source.sub) {
        const table = HT.makerKit.BASE_TABLES[source.list];
        if (table?.cols) for (const k of ['id', 'name']) if (old[k] && x[k] !== old[k] && !(k === 'name' && HT.makerKit.shadowOf(packs.filter(p => p.id !== draft.id), source.list, old.id))) HT.makerKit.renameRefs(next, table, k, old[k], x[k]);
        if (source.list === 'epochs' && old.name !== x.name) HT.makerKit.renameEpochRefs(next, old, old.name, x.name);
        if (source.list === 'periods' && old.name && old.name !== x.name) HT.makerFind?.renameReferences(next, source.list, old, x);
        if (docs.length) { next.documents ||= {}; const key = Object.hasOwn(next.documents, draft.id + '/' + x.id) ? draft.id + '/' + x.id : x.id; next.documents[key] = docs.at(-1); }
      }
    }
    if (kinCells.length) {
      const kc = kinContext(next, model, accepted.slice().sort((a, b) => a.index - b.index));
      const used = new Set(HT.draft.LISTS.flatMap(k => arr(next[k]).map(o => o.id)));
      const made = new Map(); // 못 찾은 이름 → 이번에 만든 새 사람 (같은 이름은 한 사람)
      const acceptedOf = new Map(accepted.map(a => [a.x, a]));
      for (const k of kinCells) {
        try {
          let r = kinRef(k.w.text, k.x, k.index, kc);
          if (r.missing && opts.createMissing) {
            let y = made.get(r.ref);
            if (!y) {
              y = { id: HT.makerKit.uniqueId('fk-' + HT.hash(`${k.x.track}|${r.ref}`), used), track: k.x.track, name: r.ref, lineageOnly: true };
              used.add(y.id); rows.push(y); made.set(r.ref, y); added++; lineageAdded++;
            }
            r = { ref: y.id, missing: false };
          }
          if (r.missing) missing.push({ row: k.w.row, key: k.w.key, text: String(k.w.text).trim() });
          const before = JSON.stringify(k.x.parents ?? null);
          HT.makerKin?.setParent(k.x, k.c.role, r.ref);
          const rec = acceptedOf.get(k.x);
          if (rec && rec.same && !rec.fresh && JSON.stringify(k.x.parents ?? null) !== before) { rec.same = false; changed++; }
        } catch (error) { errors.push({ ...k.w, message: error.message }); }
      }
    }
    if (source.sub) { const before = arr(draft.periods).find(p => p.id === source.parent), after = arr(next.periods).find(p => p.id === source.parent); if (before && after) moveCellDocuments(next, draft.id + '/' + before.id, before, after); }
    return { draft: next, errors, added, changed, missing, lineageAdded };
  }
  /** 인물 표의 머리글 별칭 — 족보 붙여넣기(이름 · 부 · 파 · 생 · 몰 …)의 낱말은 js/maker-paste.js의 FIELDS.genealogy 한 곳에 (부 = 아버지 · 부친, 생 = 출생 · 생년 …) */
  const GENEALOGY_KEY = { birth: 'birth', death: 'death', house: 'house', lineageOnly: 'lineageOnly', order: 'order', 'kin:father': 'father', 'kin:mother': 'mother', 'kin:adoptive-father': 'adoptive-father', 'kin:birth-father': 'birth-father' };
  function headAliases(source, c) {
    if (source.list !== 'figures' || source.sub || !GENEALOGY_KEY[c.key]) return [];
    const f = arr(HT.makerPaste?.FIELDS?.genealogy).find(f => f.key === GENEALOGY_KEY[c.key]);
    return f ? f.aliases : [];
  }
  function pasteWrites(text, source, orderedRows, startRow, startCol, shownCols = columns(source), nextRow = Math.max(startRow, ...orderedRows.map(i => i + 1))) {
    const rows = HT.makerKit.parseTable(text); if (!rows.length) return [];
    const all = columns(source);
    const byHead = h => all.find(c => [c.key, c.label, ...(HT.makerKit.PASTE_HEAD[c.key === 'name' ? 'title' : c.key] || []), ...headAliases(source, c)].some(a => norm(a) === norm(h)));
    const headers = rows[0].map(byHead), hasHead = headers.filter(Boolean).length >= Math.max(1, Math.ceil(rows[0].length / 2));
    const body = hasHead ? rows.slice(1) : rows, writes = [];
    body.forEach((r, i) => r.forEach((text, j) => {
      const c = hasHead ? headers[j] : shownCols[startCol + j];
      if (c) writes.push({ row: orderedRows[startRow + i] ?? nextRow + Math.max(0, startRow + i - Math.max(orderedRows.length, startRow)), key: c.key, text });
    }));
    return writes;
  }
  function mount(host, ctx, api, preferences, remember, initialSource = null) {
    const esc = HT.esc || ctx.esc;
    let source = initialSource || { list: preferences.list && words[preferences.list] ? preferences.list : 'periods' }, selected = { a: [0, 0], b: [0, 0] }, rowMode = false, chosen = new Set(), viewRows = [], shown = [], sort = null, query = '', editor = null, errorCells = new Map(), currentDraft = null, childGrid = null;
    let active = false, top = 0, busy = false;
    const status = msg => { host.querySelector('[data-grid-status]').textContent = msg; };
    const pref = () => preferences[source.sub || source.list] ||= {};
    const save = () => { preferences.list = source.list; remember(); };
    const bounds = () => ({ r0: Math.min(selected.a[0], selected.b[0]), r1: Math.max(selected.a[0], selected.b[0]), c0: Math.min(selected.a[1], selected.b[1]), c1: Math.max(selected.a[1], selected.b[1]) });
    function shell() {
      host.innerHTML = `<div class="mk-grid"><div class="mk-grid-tools"><label>목록 <select data-grid-list aria-label="표 목록">${Object.entries(words).map(([k, n]) => `<option value="${k}">${n}</option>`).join('')}</select></label><label>찾기 <input data-grid-query aria-label="표에서 찾기"></label><button class="btn btn-sm" data-grid-columns>열 설정</button><button class="btn btn-sm" data-grid-paste>표 붙여넣기</button><button class="btn btn-sm" data-grid-bulk>한꺼번에 고치기</button></div><div data-grid-sub class="mk-grid-sub" hidden></div><div class="mk-grid-scroll" tabindex="0" role="grid" aria-label="DLC 편집 표"><div class="mk-grid-head" role="row"></div><div class="mk-grid-rows"></div></div><div class="mk-grid-status" data-grid-status aria-live="polite"></div></div>`;
      host.querySelector('[data-grid-list]').value = source.list;
      if (!source.sub && HT.makerKit.BASE_TABLES[source.list]) host.querySelector('.mk-grid-tools').insertAdjacentHTML('beforeend', '<button type="button" class="btn btn-sm" data-grid-base-tools>바탕 가져오기·문서</button>');
      if (initialSource) { host.querySelector('[data-grid-list]').closest('label').hidden = true; host.querySelector('[data-grid-bulk]').hidden = true; }
      if (!source.sub && source.list === 'figures' && HT.maker?.kin) host.querySelector('.mk-grid-tools').insertAdjacentHTML('beforeend', '<button type="button" class="btn btn-sm" data-grid-kin title="고른 줄의 사람을 뿌리로 자손을 한 줄 = 한 사람 · 들여쓰기 = 세대 글로 고칩니다 (족보 들여쓰기 글을 붙여넣어도 됨)">계층 입력</button>');
      if (!initialSource) host.querySelector('[data-grid-status]').insertAdjacentHTML('beforebegin', '<div class="mk-grid-child-host" data-grid-child-host hidden></div>');
      if (source.sub === 'phases') {
        const parent = arr(api.draft.periods).find(x => x.id === source.parent), systems = HT.readPhases(parent?.phases).list;
        host.querySelector('.mk-grid-tools').insertAdjacentHTML('afterbegin', `<label>시기 체계 <select data-grid-system>${(systems.length ? systems : [{ scheme: '시기' }]).map((s, i) => `<option value="${i}" ${i === (source.system || 0) ? 'selected' : ''}>${esc(s.scheme || '체계 ' + (i + 1))}</option>`).join('')}</select></label>`);
      }
      host.querySelector('.mk-grid-scroll').addEventListener('scroll', () => { if (!editor) paintRows(); });
    }
    const scroll = () => host.querySelector('.mk-grid-scroll');
    function refresh() {
      if (!active || !api.draft || editor) return;
      if (currentDraft && currentDraft.id !== api.draft.id) {
        childGrid?.hide(); childGrid = null; source = { list: source.list }; selected = { a: [0, 0], b: [0, 0] }; chosen.clear(); rowMode = false; query = ''; sort = null; errorCells.clear(); shell();
      }
      const all = columns(source), settings = pref();
      const order = arr(settings.order), hidden = new Set(arr(settings.hidden));
      shown = all.filter(c => !hidden.has(c.key)).sort((a, b) => (order.includes(a.key) ? order.indexOf(a.key) : 999) - (order.includes(b.key) ? order.indexOf(b.key) : 999));
      if (!shown.length) shown = all;
      const picked = new Set([...chosen].map(i => viewRows[i]?.x.id || (viewRows[i] ? JSON.stringify(viewRows[i].x) : null))), raws = rowsOf(api.draft, source);
      viewRows = raws.map((x, i) => ({ x, i })).filter(r => !query || all.some(c => String(value(api.draft, source, r.x, c)).toLocaleLowerCase().includes(query)));
      if (sort) viewRows.sort((a, b) => String(value(api.draft, source, a.x, sort.c)).localeCompare(String(value(api.draft, source, b.x, sort.c)), 'ko', { numeric: true }) * sort.dir);
      if (rowMode) chosen = new Set(viewRows.flatMap((r, i) => picked.has(r.x.id || JSON.stringify(r.x)) ? [i] : []));
      const template = '42px ' + shown.map(c => Math.max(72, Math.min(600, Number(settings.widths?.[c.key]) || (c.type === 'date' ? 128 : 144))) + 'px').join(' ');
      host.style.setProperty('--mk-grid-cols', template);
      host.querySelector('.mk-grid-head').innerHTML = '<button data-grid-all aria-label="모든 줄 고르기">#</button>' + shown.map(c => `<button data-grid-sort="${esc(c.key)}" role="columnheader">${esc(c.label)}${sort?.c.key === c.key ? sort.dir === 1 ? ' ↑' : ' ↓' : ''}</button>`).join('');
      const sc = scroll(); sc.setAttribute('aria-rowcount', viewRows.length + 2); sc.setAttribute('aria-colcount', shown.length + 1);
      currentDraft = api.draft;
      paintRows(); status(`${words[source.list]} ${viewRows.length}줄${source.sub ? ' · ' + subNames[source.sub] : ''} · Enter로 고치기 · Ctrl+V 붙여넣기 · Ctrl+D 아래로 채우기`);
      childGrid?.refresh();
    }
    function paintRows() {
      const sc = scroll(); if (!sc) return;
      top = Math.max(0, Math.floor(sc.scrollTop / 28) - 3);
      const end = Math.min(viewRows.length + 1, top + Math.ceil(sc.clientHeight / 28) + 8), b = bounds();
      const html = [];
      for (let r = top; r < end; r++) {
        const row = viewRows[r], rawIndex = row?.i ?? rowsOf(api.draft, source).length;
        html.push(`<div role="row" class="mk-grid-row ${rowMode && chosen.has(r) ? 'is-selected' : ''}" style="top:${r * 28}px" aria-rowindex="${r + 2}"><button class="mk-grid-rowhead" data-grid-row="${r}" aria-label="${r + 1}번째 줄 고르기">${row ? r + 1 : '+'}</button>${shown.map((c, j) => {
          const err = errorCells.get(rawIndex + ':' + c.key), v = row ? value(api.draft, source, row.x, c) : '';
          let content = esc(options(c, api.draft, ctx.state.model).find(o => String(o.id) === String(v))?.name || String(v));
          const shadow = row && !source.sub && c.key === 'name' && HT.makerKit.BASE_TABLES[source.list]?.cols && HT.makerKit.shadowOf(ctx.state.packs.filter(p => p.id !== api.draft.id), source.list, row.x.id);
          if (shadow) content += ` <small title="${esc(shadow.name)}의 정의가 먼저 쓰입니다">다른 DLC 우선</small>`;
          if (row && source.list === 'patches' && c.key === 'actions') content = `<button type="button" class="btn btn-sm" data-grid-patch="view" data-row="${r}">보기</button> <button type="button" class="btn btn-sm" data-grid-patch="undo" data-row="${r}">되돌리기</button>`;
          if (row && c.type === 'color') content = `<span class="mk-grid-swatch" style="background:${esc(v ? HT.pastel(v) : HT.autoColor(row.x.id || row.x.name || ''))}"></span>${v ? content : '자동'}`;
          /* 가문의 구분 · 민족을 비우면 모델이 짐작한 값(D1 2-4 바 — 파일에 적지 않음)을 칸 안 딱지로 (입력 칸의 회색 예시 글이 아님) */
          if (row && !v && !source.sub && source.list === 'houses' && (c.key === 'track' || c.key === 'people') && HT.makerKin) { const g = HT.makerKin.houseGuess(ctx.state.model, row.x.id, c.key); if (g) content = `<span class="mk-guess" title="비워 두면 이 값으로 봅니다 — 적으려면 칸을 고치세요">짐작: ${esc(g)}</span>`; }
          return `<div role="gridcell" data-grid-cell="${r}:${j}" class="mk-grid-cell ${!rowMode && r >= b.r0 && r <= b.r1 && j >= b.c0 && j <= b.c1 ? 'is-selected' : ''} ${err ? 'is-invalid' : ''}" aria-selected="${!rowMode && r >= b.r0 && r <= b.r1 && j >= b.c0 && j <= b.c1}" title="${esc(err || String(v))}">${content}${row && ['children', 'detail'].includes(c.type) ? ' ↗' : ''}</div>`;
        }).join('')}</div>`);
      }
      const list = host.querySelector('.mk-grid-rows'); list.style.height = (viewRows.length + 1) * 28 + 'px'; list.innerHTML = html.join('');
    }
    function setSource(next) { childGrid?.hide(); childGrid = null; source = next; selected = { a: [0, 0], b: [0, 0] }; chosen.clear(); rowMode = false; sort = null; query = ''; errorCells.clear(); shell(); refresh(); save(); }
    function paintSelection() {
      const b = bounds();
      for (const el of host.querySelectorAll('[data-grid-cell]')) {
        if (el.closest('.mk-grid') !== host.querySelector('.mk-grid')) continue;
        const [r, c] = el.dataset.gridCell.split(':').map(Number), on = rowMode ? chosen.has(r) : r >= b.r0 && r <= b.r1 && c >= b.c0 && c <= b.c1;
        el.classList.toggle('is-selected', on); el.setAttribute('aria-selected', String(on));
      }
    }
    function subBar(parent) {
      if (initialSource) return;
      const bar = host.querySelector('[data-grid-sub]'); bar.hidden = false;
      bar.innerHTML = `<strong>${esc(parent.name)}의 하위 표</strong>${Object.entries(subNames).map(([k, n]) => `<button class="btn btn-sm" data-grid-child="${k}" data-parent="${esc(parent.id)}">${n}</button>`).join('')}<button class="btn btn-sm" data-grid-main>하위 표 접기</button>`;
      if (!childGrid || childGrid.source().parent !== parent.id) showChild(parent, 'leaders');
    }
    function showChild(parent, sub) {
      if (initialSource) return;
      const childHost = host.querySelector('[data-grid-child-host]'); childHost.hidden = false;
      if (!childGrid) {
        preferences.children ||= {};
        childGrid = mount(childHost, ctx, api, preferences.children, remember, { list: 'periods', parent: parent.id, sub });
        for (const type of ['click', 'dblclick', 'pointerdown', 'pointerover', 'change', 'input']) childHost.addEventListener(type, e => e.stopPropagation());
      } else childGrid.setSource({ list: 'periods', parent: parent.id, sub });
      childGrid.show();
    }
    async function apply(writes, preview = false) {
      if (busy || !writes.length) return;
      busy = true;
      try {
        const original = api.draft, before = HT.makerHistory.content(original), target = { ...source };
        let result = plan(original, target, writes, ctx.state.model, ctx.state.packs);
        errorCells = new Map(result.errors.map(e => [e.row + ':' + e.key, e.message]));
        if (!result.added && !result.changed) { paintRows(); status(result.errors[0]?.message || '바뀐 칸이 없습니다.'); return; }
        const opts = {};
        if (preview && (result.added || result.errors.length || result.missing.length)) {
          const answer = await confirmPlan(result);
          if (!answer) return;
          opts.createMissing = answer.createMissing;
        }
        if (api.draft !== original || HT.makerHistory.content(api.draft) !== before) { status('작업본이 바뀌었습니다. 다시 붙여넣어 주세요.'); return; }
        const applied = await api.transact(fresh => { result = plan(fresh, target, writes, ctx.state.model, ctx.state.packs, opts); return result.draft; }, `표 ${result.added}줄 더함 · ${result.changed}줄 고침`, { snapshot: !!result.added || result.changed > 20 });
        if (!applied) { refresh(); return; }
        refresh(); status(`더함 ${result.added}줄 · 고침 ${result.changed}줄${result.errors.length ? ` · 넣지 않은 칸 ${result.errors.length}개` : ''}`);
      } finally { busy = false; }
    }
    /** 붙여넣기 확인 — 넣으면 { createMissing }(찾지 못한 부모를 새 사람으로 만들지), 취소하면 null */
    function confirmPlan(result) {
      return new Promise(resolve => {
        const box = document.createElement('dialog'); box.className = 'dlc-dialog mk-box';
        const miss = result.missing || [], names = [...new Set(miss.map(m => m.text))];
        const missHTML = miss.length ? `<p class="mk-bad">찾지 못한 부모 ${names.length}명 — 작업본과 켠 팩에 그 이름의 사람이 없습니다.</p><ul class="mk-paste-problems">${miss.slice(0, 20).map(m => `<li class="is-bad">${m.row + 1}번째 줄 · ${esc(m.text)}</li>`).join('')}</ul><label class="check"><input type="checkbox" data-create-missing> 못 찾은 ${names.length}명을 새 사람(계보 전용)으로 만들기 — 끄면 적은 이름 그대로 남고 검사에서 알립니다</label>` : '';
        box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>표 붙여넣기 확인</h2></div><div class="dlg-body"><p>더할 것 ${result.added}줄 · 고칠 것 ${result.changed}줄 · 걸린 칸 ${result.errors.length}개</p>${result.lineageAdded ? `<p>새 줄 ${result.lineageAdded}개는 계보 전용 인물로 넣습니다(활동 시작 · 끝 · 계보 전용 열이 없는 족보 붙여넣기 — 띠에 놓지 않음).</p>` : ''}${missHTML}${result.errors.length ? `<p>걸린 칸은 원래 값을 유지합니다.</p><ul>${result.errors.slice(0, 20).map(e => `<li>${e.row + 1}번째 줄 · ${esc(e.message)}</li>`).join('')}</ul>` : ''}<button class="btn primary" data-accept>넣기</button> <button class="btn" data-cancel>취소</button></div></div>`;
        let createMissing = false;
        box.addEventListener('change', e => { if (e.target.matches('[data-create-missing]')) createMissing = e.target.checked; });
        box.addEventListener('click', e => { if (e.target.closest('[data-accept]')) box.close('yes'); if (e.target.closest('[data-cancel]')) box.close(); });
        box.addEventListener('close', () => { resolve(box.returnValue === 'yes' ? { createMissing } : null); box.remove(); }); document.body.append(box); box.showModal();
      });
    }
    function edit(initial) {
      if (editor) return;
      const [r, j] = selected.b, c = shown[j], row = viewRows[r]; if (!c) return;
      if (source.list === 'patches' && (c.type === 'readonly' || !row)) return; // 덮어쓰기 표는 메모 칸만 고침(줄을 새로 만들지는 않음)
      if (c.type === 'children') { if (row) { const parent = row.x; subBar(parent); showChild(parent, c.key); } return; }
      if (c.type === 'detail') { if (row) api.openItem(api.draft.id + '/' + row.x.id); return; }
      if (row && !source.sub && structuredValue(row.x[c.key]) && c.type !== 'date') { api.openItem(api.draft.id + '/' + row.x.id); return; }
      if (c.type === 'readonly') return;
      const el = host.querySelector(`[data-grid-cell="${r}:${j}"]`); if (!el) return;
      if (c.type === 'color' && initial == null) { const draft = api.draft, target = source; HT.pickColor(el, row?.x.color ? HT.pastel(row.x.color) : '').then(v => { if (v != null && api.draft === draft && source === target) apply([{ row: row?.i ?? rowsOf(api.draft, source).length, key: c.key, text: v }]); }); return; }
      const opts = options(c, api.draft, ctx.state.model), input = document.createElement(opts.length ? 'select' : 'input');
      input.setAttribute('aria-label', c.label); input.dataset.gridEditor = '';
      if (opts.length) input.innerHTML = '<option value="">비움</option>' + opts.map(o => `<option value="${esc(o.id)}">${esc(o.name || o.id)}</option>`).join('');
      input.value = initial ?? (row ? value(api.draft, source, row.x, c) : ''); el.replaceChildren(input); editor = input; input.focus(); if (input.select && initial == null) input.select();
      /* 사람 칸(부 · 모 · 양부 · 생부 · 가문의 시조): 세 글자 넘게 치면 사람 찾기 상자 (계보 전용 인물은 자동 완성 목록에 없음 — js/maker-kin.js). 민족 칸: 자동 완성 */
      if (!opts.length && (c.type === 'kin' || c.person) && HT.makerKin) HT.makerKin.attachFinder(input, { track: () => row?.x.track || '', strict: !!c.person });
      if (!opts.length && c.suggest) { const dl = document.createElement('datalist'); dl.id = `mkGridSuggest-${c.key}`; dl.innerHTML = c.suggest(api.draft, ctx.state.model).map(n => `<option value="${esc(n)}"></option>`).join(''); el.append(dl); input.setAttribute('list', dl.id); }
      const finish = async (cancel, fill, step) => {
        if (editor !== input) return; const text = input.value; editor = null;
        if (!cancel) {
          const b = fill ? bounds() : { r0: r, r1: r, c0: j, c1: j }, writes = [];
          for (let y = b.r0; y <= b.r1; y++) for (let x = b.c0; x <= b.c1; x++) if (shown[x]) writes.push({ row: viewRows[y]?.i ?? rowsOf(api.draft, source).length + y - viewRows.length, key: shown[x].key, text });
          await apply(writes);
        } else paintRows();
        if (step) { const nr = Math.min(viewRows.length, Math.max(0, r + (step === 'row' ? 1 : 0))), nc = step === 'col' ? (j + 1) % shown.length : j; selected = { a: [nr, nc], b: [nr, nc] }; }
        paintRows(); scroll().focus({ preventScroll: true });
      };
      input.addEventListener('keydown', e => { if (e.isComposing) return; if (['Escape', 'Enter', 'Tab'].includes(e.key)) { e.preventDefault(); e.stopPropagation(); finish(e.key === 'Escape', e.ctrlKey && e.key === 'Enter', e.key === 'Tab' ? 'col' : e.key === 'Enter' && !e.ctrlKey ? 'row' : null); } });
      input.addEventListener('blur', () => finish(false));
    }
    function copy(e) {
      const b = bounds(), lines = [], indexes = rowMode ? [...chosen].sort((a, b) => a - b) : Array.from({ length: b.r1 - b.r0 + 1 }, (_, i) => b.r0 + i);
      const cols = rowMode ? shown : shown.slice(b.c0, b.c1 + 1);
      const quote = v => /[\t\n"\r]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v);
      for (const r of indexes) if (viewRows[r]) lines.push(cols.map(c => quote(value(api.draft, source, viewRows[r].x, c))).join('\t'));
      e.preventDefault(); e.stopPropagation(); e.clipboardData.setData('text/plain', lines.join('\n'));
    }
    async function remove() {
      if (rowMode) {
        const indexes = [...chosen].map(r => viewRows[r]?.i).filter(i => i != null);
        const table = !source.sub && HT.makerKit.BASE_TABLES[source.list];
        if (table) {
          const raws = rowsOf(api.draft, source), uses = indexes.reduce((n, i) => n + (table.cols ? HT.makerKit.findUsers(api.draft, table, raws[i]).length : table.uses?.(api.draft, raws[i]).length || 0), 0);
          if (uses && !confirm(`고른 바탕 자료를 쓰는 곳이 ${uses}개 있습니다. 지우면 해당 항목의 연결이 끊길 수 있습니다. 지울까요?`)) return;
        }
        await api.transact(d => { const rows = rowsOf(d, source, true); for (const i of indexes.sort((a, b) => b - a)) { if (!source.sub && source.list !== 'patches') { const row = rows[i]; if (HT.makerKit.kindOfList(source.list)) { HT.draft.removeOwn(d, row.id); continue; } } rows.splice(i, 1); } return d; }, `표 ${indexes.length}줄 지움`, { snapshot: indexes.length > 20 });
        chosen.clear(); refresh(); return;
      }
      const b = bounds(), writes = [];
      for (let r = b.r0; r <= b.r1; r++) for (let j = b.c0; j <= b.c1; j++) if (viewRows[r]) writes.push({ row: viewRows[r].i, key: shown[j].key, text: '' });
      await apply(writes);
    }
    async function fillDown() {
      if (rowMode) {
        if (!source.sub && HT.makerKit.kindOfList(source.list)) return api.duplicateSelection();
        if (source.list === 'patches') { status('덮어쓰기는 같은 대상으로 복제하지 않습니다.'); return; }
        const picks = [...chosen].map(r => viewRows[r]?.i).filter(i => i != null);
        await api.transact(d => { const rows = rowsOf(d, source, true); for (const i of picks) { const x = clone(rows[i]); if (!source.sub) { x.id = HT.makerKit.uniqueId(x.id + '-copy', new Set(rows.map(r => r.id))); x.name = (x.name || '') + ' 복사본'; } rows.push(x); } return d; }, `표 ${picks.length}줄 복제`, { snapshot: picks.length > 20 }); refresh(); return;
      }
      const b = bounds(), writes = [];
      if (!viewRows[b.r0]) return;
      for (let r = b.r0 + 1; r <= b.r1; r++) for (let j = b.c0; j <= b.c1; j++) if (viewRows[r]) writes.push({ row: viewRows[r].i, key: shown[j].key, text: value(api.draft, source, viewRows[b.r0].x, shown[j]) });
      await apply(writes);
    }
    function columnBox() {
      const box = document.createElement('dialog'); box.className = 'dlc-dialog mk-box'; const settings = pref(), all = columns(source);
      box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>표 열 설정</h2></div><form class="dlg-body"><p>표시 여부·너비·순서를 이 컴퓨터에 기억합니다.</p>${all.map((c, i) => `<label class="mk-grid-colsetting"><input type="checkbox" name="show:${c.key}" ${shown.some(x => x.key === c.key) ? 'checked' : ''}>${esc(c.label)} <input type="number" min="72" max="600" name="width:${c.key}" aria-label="${esc(c.label)} 너비" value="${settings.widths?.[c.key] || 144}"><input type="number" min="1" max="${all.length}" name="order:${c.key}" aria-label="${esc(c.label)} 순서" value="${settings.order?.includes(c.key) ? settings.order.indexOf(c.key) + 1 : i + 1}"></label>`).join('')}<button type="submit" class="btn primary">적용</button> <button type="button" class="btn" data-cancel>취소</button></form></div>`;
      box.querySelector('form').addEventListener('submit', e => { e.preventDefault(); const f = new FormData(e.target); settings.hidden = all.filter(c => !f.has('show:' + c.key)).map(c => c.key); settings.widths = Object.fromEntries(all.map(c => [c.key, Math.max(72, Math.min(600, Number(f.get('width:' + c.key)) || 144))])); settings.order = all.slice().sort((a, b) => Number(f.get('order:' + a.key)) - Number(f.get('order:' + b.key))).map(c => c.key); save(); box.close(); refresh(); });
      box.querySelector('[data-cancel]').onclick = () => box.close(); box.onclose = () => box.remove(); document.body.append(box); box.showModal();
    }
    function pasteBox() {
      const box = document.createElement('dialog'); box.className = 'dlc-dialog mk-box';
      box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>${esc(words[source.list])} 표 붙여넣기</h2></div><form class="dlg-body"><label>표 글<textarea name="table" rows="12" aria-label="붙여넣을 표"></textarea></label><p>첫 줄에 열 이름을 적으면 해당 열로 맞춥니다. 새 줄과 잘못된 칸은 넣기 전에 확인합니다.</p><button class="btn primary" type="submit">확인</button> <button class="btn" type="button" data-cancel>취소</button></form></div>`;
      box.querySelector('form').onsubmit = e => { e.preventDefault(); const text = new FormData(e.target).get('table'); box.close(); paste(text); }; box.querySelector('[data-cancel]').onclick = () => box.close(); box.onclose = () => box.remove(); document.body.append(box); box.showModal(); box.querySelector('textarea').focus();
    }
    function paste(text) {
      /* 족보를 옮겨 적은 들여쓰기 글(한 줄 = 한 사람 · 들여쓰기 = 세대)은 계층 입력 창으로 — 같은 읽기(확정 설계 7-2 ⑤) */
      if (!source.sub && source.list === 'figures' && HT.makerKin?.looksLikeOutline(text) && HT.maker?.kin) { HT.maker.kin.outline({ text }); return Promise.resolve(); }
      const b = bounds(); return apply(pasteWrites(text, source, viewRows.map(x => x.i), b.r0, b.c0, shown, rowsOf(api.draft, source).length), true);
    }
    const ownEvent = e => e.target.closest('.mk-grid') === host.querySelector('.mk-grid');
    host.addEventListener('change', e => { if (!ownEvent(e)) return; if (e.target.matches('[data-grid-list]')) setSource({ list: e.target.value }); if (e.target.matches('[data-grid-system]')) setSource({ ...source, system: Number(e.target.value) }); });
    host.addEventListener('input', e => { if (!ownEvent(e)) return; if (e.target.matches('[data-grid-query]')) { query = e.target.value.toLocaleLowerCase(); selected = { a: [0, 0], b: [0, 0] }; scroll().scrollTop = 0; refresh(); } });
    host.addEventListener('click', e => {
      if (!ownEvent(e)) return;
      const action = e.target.closest('[data-grid-patch]');
      if (action) { const row = viewRows[Number(action.dataset.row)]?.x; if (row) { if (action.dataset.gridPatch === 'view') api.openItem(row.target); else api.transact(d => { HT.draft.unpatch(d, row.target); return d; }, '덮어쓰기 되돌리기'); } return; }
      const c = e.target.closest('[data-grid-cell]'); if (c && !editor) { const at = c.dataset.gridCell.split(':').map(Number); if (!moved) selected = { a: e.shiftKey ? selected.a : at, b: at }; moved = false; rowMode = false; paintSelection(); scroll().focus({ preventScroll: true }); }
      const r = e.target.closest('[data-grid-row]'); if (r) { const n = Number(r.dataset.gridRow); if (!viewRows[n]) { selected = { a: [n, 0], b: [n, 0] }; rowMode = false; edit(); return; } if (e.shiftKey) { const start = selected.a[0]; for (let i = Math.min(start, n); i <= Math.max(start, n); i++) chosen.add(i); } else if (e.ctrlKey || e.metaKey) { chosen.has(n) ? chosen.delete(n) : chosen.add(n); } else chosen = new Set([n]); selected = { a: [n, 0], b: [n, shown.length - 1] }; rowMode = true; if (!source.sub) { api.selectItems([...chosen].map(i => api.draft.id + '/' + viewRows[i]?.x.id)); if (source.list === 'periods' && chosen.size === 1) subBar(viewRows[n].x); } paintRows(); scroll().focus({ preventScroll: true }); }
      const s = e.target.closest('[data-grid-sort]'); if (s) { const c = shown.find(x => x.key === s.dataset.gridSort); sort = sort?.c === c ? sort.dir === 1 ? { c, dir: -1 } : null : { c, dir: 1 }; refresh(); }
      const child = e.target.closest('[data-grid-child]'); if (child) { const parent = api.draft.periods.find(x => x.id === child.dataset.parent); showChild(parent, child.dataset.gridChild); }
      if (e.target.closest('[data-grid-main]')) { childGrid?.hide(); host.querySelector('[data-grid-child-host]').hidden = true; host.querySelector('[data-grid-sub]').hidden = true; }
      if (e.target.closest('[data-grid-columns]')) columnBox();
      if (e.target.closest('[data-grid-paste]')) pasteBox();
      if (e.target.closest('[data-grid-bulk]')) api.openBulk();
      if (e.target.closest('[data-grid-base-tools]')) api.openBaseTools(source.list);
      if (e.target.closest('[data-grid-kin]')) { const r = viewRows[rowMode && chosen.size ? [...chosen][0] : selected.b[0]]; HT.maker.kin.outline(r ? { uid: api.draft.id + '/' + r.x.id } : {}); }
      if (e.target.closest('[data-grid-all]')) { rowMode = true; chosen = new Set(viewRows.map((_, i) => i)); if (!source.sub && HT.makerKit.kindOfList(source.list)) api.selectItems(viewRows.map(r => api.draft.id + '/' + r.x.id)); paintRows(); scroll().focus({ preventScroll: true }); }
    });
    host.addEventListener('dblclick', e => { if (ownEvent(e) && e.target.closest('[data-grid-cell]') && !editor) edit(); });
    let picking = false, moved = false;
    host.addEventListener('pointerdown', e => { if (!ownEvent(e)) return; const c = e.target.closest('[data-grid-cell]'); if (c && !editor && e.button === 0) { const at = c.dataset.gridCell.split(':').map(Number); selected = { a: e.shiftKey ? selected.a : at, b: at }; picking = true; moved = false; rowMode = false; } });
    host.addEventListener('pointerover', e => { if (!ownEvent(e)) return; const c = e.target.closest('[data-grid-cell]'); if (picking && e.buttons === 1 && c) { selected.b = c.dataset.gridCell.split(':').map(Number); moved = true; paintSelection(); } });
    document.addEventListener('pointerup', () => { picking = false; });
    host.addEventListener('copy', e => { if (ownEvent(e) && !editor && e.target.closest('.mk-grid-scroll')) copy(e); });
    host.addEventListener('cut', e => { if (ownEvent(e) && !editor && e.target.closest('.mk-grid-scroll')) { copy(e); remove(); } });
    host.addEventListener('paste', e => { if (ownEvent(e) && !editor && e.target.closest('.mk-grid-scroll')) { e.preventDefault(); e.stopPropagation(); paste(e.clipboardData.getData('text/plain')); } });
    host.addEventListener('keydown', e => {
      if (!ownEvent(e) || editor || e.isComposing || !e.target.closest('.mk-grid-scroll')) return;
      const key = e.key.toLowerCase(), ctrl = e.ctrlKey || e.metaKey;
      if (ctrl && ['c', 'v', 'x', 'z', 'y'].includes(key)) return;
      if (ctrl && key === 'd') { e.preventDefault(); e.stopPropagation(); fillDown(); return; }
      if (ctrl && key === 'a') { e.preventDefault(); e.stopPropagation(); selected = { a: [0, 0], b: [Math.max(0, viewRows.length - 1), shown.length - 1] }; rowMode = false; paintRows(); return; }
      if (e.key === 'Delete') { e.preventDefault(); e.stopPropagation(); remove(); return; }
      if (['Enter', 'F2'].includes(e.key)) { e.preventDefault(); e.stopPropagation(); edit(); return; }
      if (e.key.startsWith('Arrow')) { e.preventDefault(); e.stopPropagation(); const [r, c] = selected.b, at = [Math.max(0, Math.min(viewRows.length, r + (e.key === 'ArrowDown' ? 1 : e.key === 'ArrowUp' ? -1 : 0))), Math.max(0, Math.min(shown.length - 1, c + (e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0)))]; selected = { a: e.shiftKey ? selected.a : at, b: at }; rowMode = false; if (at[0] * 28 < scroll().scrollTop) scroll().scrollTop = at[0] * 28; if (at[0] * 28 > scroll().scrollTop + scroll().clientHeight - 60) scroll().scrollTop = at[0] * 28 - scroll().clientHeight + 60; paintRows(); return; }
      if (e.key.length === 1 && !ctrl && !e.altKey) { e.preventDefault(); e.stopPropagation(); edit(e.key); }
    });
    return { show(list) { active = true; if (!host.querySelector('.mk-grid') || list && list !== source.list) { if (list && words[list]) source = { list }; shell(); } if (childGrid && !host.querySelector('[data-grid-child-host]').hidden) childGrid.show(); refresh(); }, hide() { active = false; editor = null; childGrid?.hide(); }, setSource, refresh, pasteBox, paste, source: () => ({ ...source }), isActive: () => active, command(id) { if (!active || !host.contains(document.activeElement)) return false; if (childGrid?.command(id)) return true; if (id === 'duplicate') fillDown(); else if (id === 'delete') remove(); else return false; return true; } };
  }
  function patchItem(draft, base, before, after) {
    const changed = {};
    for (const key of HT.PATCHABLE) if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) changed[key] = after[key] ?? null;
    HT.draft.patchForeign(draft, base, changed);
  }
  /* ---------- 한꺼번에 고치기(여러 항목 일괄 고침) ----------
     10건 5(나) 1: 예전 여덟 칸(트랙 · 종류 · 분류 · 중요도 · 민족 · 색 · 실재성 · 확실성)과 날짜 옮기기에 넷을 더했습니다 —
     국성 · 가문(house) · 태그 더하기/빼기(사건) · 대범위에 넣기/빼기(고치는 DLC의 대범위만 — 남의 대범위는 패치 대상이 아님) · 소속 정하기(상위 정권 하나 · 기간 없음 · 관계 고르기).
     남의 항목은 예전처럼 바뀐 칸만 덮어쓰기(패치)로 적고, 한 번 적용이 되돌리기 한 걸음(api.transact)입니다.
     고른 항목 가운데 하나도 받을 수 없는 칸(사건만 골랐는데 국성 …)은 고칠 칸 목록에서 감춥니다 */
  const BULK_FIELDS = [col('track', '트랙', 'track'), col('kind', '종류', 'kind'), col('category', '분류', 'category'), col('importance', '중요도', 'importance'), col('people', '민족'), col('color', '색', 'color'), col('historicity', '실재성', 'historicity'), col('certainty', '확실성', 'certainty'), col('house', '국성 · 가문'), col('tags', '태그', 'tags'), col('scope', '대범위', 'scope'), col('partOf', '소속', 'partOf'), col('lineageOnly', '계보 전용', 'check'), col('kin:father', '부', 'kin', { role: 'father' })];
  /** 새 칸을 받는 목록 — 국성(시대) · 가문(인물 · 왕조) / 태그(사건) / 대범위의 구성 정권 · 소속(시대) / 계보 전용 · 부(인물 — D1 확정 설계 7-2 ④) */
  const BULK_LISTS = { house: ['periods', 'figures', 'dynasties'], tags: ['events'], scope: ['periods'], partOf: ['periods'], lineageOnly: ['figures'], 'kin:father': ['figures'] };
  const listOfKind = kind => (kind ? Object.keys(words).find(k => HT.makerKit.kindOfList(k) === kind) || null : null);
  /** 그 목록의 항목이 이 칸을 받는지 — 예전 칸은 표의 열이 정합니다(columns). 대범위는 고치는 DLC에 대범위가 있을 때만 */
  const bulkFits = (key, list, draft) => !!list && (BULK_LISTS[key] ? BULK_LISTS[key].includes(list) && (key !== 'scope' || arr(draft && draft.scopes).length > 0) : columns({ list }).some(c => c.key === key));
  /** 태그 글(쉼표로 여럿) · 배열 → 겹치지 않는 태그 목록 (파일 읽기와 같은 쉼표 나누기 — 전각 쉼표도) */
  const readTags = v => [...new Set((Array.isArray(v) ? v : typeof v === 'string' ? v.split(/[,，]/) : []).map(t => String(t ?? '').trim()).filter(Boolean))];
  /** 대범위의 구성 정권 글(이름 · id · uid · "트랙:이름" · { track, polity })이 이 나라를 가리키는지 — 연표가 구성 정권을 찾는 규칙(같은 트랙의 이름 · id, 또는 uid)과 같게 */
  const scopeHas = (ref, p, track) => { const r = HT.readScopeRef(ref); return !!r && (r.polity === p.uid || (r.track || track) === p.track && (r.polity === p.name || r.polity === p.id)); };
  const scopeMembers = s => (Array.isArray(s.members) ? s.members : s.members == null || s.members === '' ? [] : [s.members]);
  /** 소속으로 적을 나라(이름 · id · uid — 같은 트랙 먼저)가 x 아래(소속의 소속 …)에 있는지 — 그러면 x를 거기에 두면 돌고 도는 소속 (maker-shell.js의 isUnder와 같은 규칙) */
  const underOf = (model, ref, x) => {
    const cands = arr(model && model.periods).filter(q => q.itemKind === 'period' && q !== x && (q.uid === ref || q.name === ref || q.id === ref));
    const same = cands.filter(q => q.track === x.track);
    for (const target of same.length ? same : cands) {
      const seen = new Set();
      for (const list = [target]; list.length; ) {
        const q = list.pop();
        if (q === x) return true;
        if (seen.has(q)) continue;
        seen.add(q);
        for (const h of q.hosts || []) if (h && h.host) list.push(h.host);
      }
    }
    return false;
  };
  /** 소속을 덮어쓰면 사라지는 것이 있는지 — 소속이 여럿이거나, 한 줄이어도 기간 · 메모 · 연대 폭 같은 것이 적혀 있으면 */
  const partOfLoses = v => { const list = HT.readPartOf(v, { relation: true }); return list.length > 1 || list.some(x => Object.keys(x).some(k => !['polity', 'relation', 'nest'].includes(k))); };
  /**
   * 한꺼번에 고치기의 계산(화면 없이) — draft를 그 자리에서 고쳐 { draft, changed, same, skipped, reasons }를 돌려줍니다.
   * op = { key, text, mode: 'add' | 'remove'(태그 · 대범위), relation(소속), unit(날짜 옮기기) } · 대범위는 text가 고치는 DLC의 대범위 id.
   * env = { model, isLocked, rawOf, baseModel } (메이커의 api와 같은 이름). 고칠 수 없는 입력은 Error를 던집니다(api.transact가 알림으로 보여 줌)
   */
  function bulkPlan(draft, uids, op, env) {
    const model = env.model, out = { draft, changed: 0, same: 0, skipped: 0, reasons: [] };
    const skip = why => { out.skipped++; if (!out.reasons.includes(why)) out.reasons.push(why); };
    const ownOf = uid => HT.draft.isOwnUid(draft, uid) && HT.draft.findOwn(draft, uid.slice(draft.id.length + 1));
    if (op.key === 'shift') { const r = HT.makerDrag.applyItems(draft, uids, { part: 'move', amount: Number(op.text), unit: op.unit }, { state: { model } }, env); return { ...out, draft: r.draft, changed: r.changed, skipped: r.skipped }; }
    if (op.key === 'scope') {
      const scope = arr(draft.scopes).find(s => s.id === op.text);
      if (!scope) throw Error('고른 대범위를 고치는 DLC에서 찾지 못했습니다.');
      for (const uid of uids) {
        const own = ownOf(uid), m = model.byUid.get(uid);
        if ((own ? own.list : listOfKind(m && m.itemKind)) !== 'periods') { skip('대범위에는 시대(나라)만 들어감'); continue; }
        const p = m && m.itemKind === 'period' ? m : { uid, id: own.item.id, name: own.item.name, track: own.item.track };
        if (p.track !== scope.track) { skip('대범위와 트랙이 다른 나라'); continue; }
        if (scope.host != null && scopeHas(scope.host, p, scope.track)) { skip('상징적 본국은 구성 정권에 넣지 않음'); continue; }
        const members = scopeMembers(scope), has = members.some(r => scopeHas(r, p, scope.track));
        if (op.mode === 'remove' ? !has : has) { out.same++; continue; }
        /* 넣을 때는 이름으로(폼과 같음) — 같은 트랙에 같은 이름의 나라가 둘 이상이면 uid로 */
        scope.members = op.mode === 'remove' ? members.filter(r => !scopeHas(r, p, scope.track)) : members.concat(arr(model.periods).filter(q => q.track === p.track && q.name === p.name).length > 1 ? p.uid : p.name);
        out.changed++;
      }
      if (!scopeMembers(scope).length) throw Error(`대범위 «${scope.name || scope.epoch || scope.id}»에 구성 정권이 하나도 남지 않습니다 — 대범위를 없애려면 그 편집 창에서 지우세요.`);
      return out;
    }
    const c = BULK_FIELDS.find(x => x.key === op.key);
    if (!c) throw Error('알 수 없는 칸입니다.');
    for (const uid of uids) {
      const own = ownOf(uid), m = model.byUid.get(uid);
      if (!own && (!m || env.isLocked(m) || ['epoch', 'scope'].includes(m.itemKind))) { skip('잠겼거나 덮어쓸 수 없는 항목'); continue; }
      const list = own ? own.list : listOfKind(m && m.itemKind);
      if (!bulkFits(c.key, list, draft)) { skip('그 칸이 없는 항목'); continue; }
      const before = own ? own.item : env.rawOf(m), raw = clone(before);
      if (c.key === 'tags') {
        const want = readTags(op.text), now = readTags(raw.tags), next = op.mode === 'remove' ? now.filter(t => !want.includes(t)) : [...new Set(now.concat(want))];
        if (JSON.stringify(next) !== JSON.stringify(now)) { if (next.length) raw.tags = next; else delete raw.tags; }
      } else if (c.key === 'partOf') {
        const polity = String(op.text ?? '').trim();
        if (polity && (polity === raw.name || polity === raw.id)) { skip('제 자신을 소속으로 둘 수 없음'); continue; }
        if (polity && m && underOf(model, polity, m)) { skip('제 아래 나라에는 놓을 수 없음'); continue; } // 소속이 돌고 돌면(가 → 다 → 나 → 가) 연표가 그릴 수 없음 — 구조 나무 끌어 놓기와 같은 막기
        if (!polity) delete raw.partOf;
        else raw.partOf = HT.compactPartOf([Object.assign({ polity }, HT.relationId(op.relation) ? { relation: HT.relationId(op.relation) } : {})]);
      } else parse(c, op.text, raw, draft, { list }, model);
      if (JSON.stringify(raw) === JSON.stringify(before)) { out.same++; continue; }
      if (own) { for (const k of Object.keys(own.item)) delete own.item[k]; Object.assign(own.item, raw); }
      else patchItem(draft, env.baseModel().byUid.get(uid) || m, before, raw);
      out.changed++;
    }
    return out;
  }
  /* 오른쪽 칸의 한꺼번에 고치기는 고칠 때마다(되돌리기 기록이 바뀔 때마다) 새로 그려지므로, 고르던 칸과 마지막 결과 글을 이어 보여 줍니다 (작업실 화면 상태 — 파일에 들어가지 않음) */
  let bulkMemo = { field: '', sig: '', at: null, result: '' }, bulkSeq = 0;
  function bulkDialog(ctx, api, container = null) {
    const uids = api.selection(), esc = ctx.esc;
    if (!uids.length) { HT.toast('고칠 항목을 먼저 고르세요.'); return; }
    const box = container || document.createElement('dialog'); if (!container) box.className = 'dlc-dialog mk-box';
    const draft0 = api.draft, model0 = ctx.state.model, seq = ++bulkSeq, sig = uids.join('|');
    const ownOf = uid => HT.draft.isOwnUid(api.draft, uid) && HT.draft.findOwn(api.draft, uid.slice(api.draft.id.length + 1));
    const lists = [...new Set(uids.map(uid => { const own = ownOf(uid); return own ? own.list : listOfKind(model0.byUid.get(uid)?.itemKind); }).filter(Boolean))];
    /* 국성은 시대의 칸 · 가문은 인물 · 왕조의 칸 — 고른 것에 맞는 이름으로 */
    const houseWord = lists.includes('periods') ? lists.some(l => l !== 'periods' && BULK_LISTS.house.includes(l)) ? '국성 · 가문' : '국성' : '가문';
    const fields = BULK_FIELDS.filter(c => lists.some(l => bulkFits(c.key, l, draft0))).map(c => (c.key === 'house' ? { ...c, label: houseWord } : c));
    const relationOptions = '<option value="">관계 없음</option>' + [['종속', r => r.autonomy != null], ['그 밖', r => r.autonomy == null]].map(([label, pick]) => `<optgroup label="${label}">${HT.RELATIONS.filter(pick).map(r => `<option value="${esc(r.id)}">${esc(r.name)}</option>`).join('')}</optgroup>`).join('');
    const houseList = fields.some(c => c.key === 'house') ? `<datalist id="mkBulkHouses${seq}">${[...new Set(arr(model0.houses).map(h => h.name).filter(Boolean))].map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>` : '';
    const polityList = fields.some(c => c.key === 'partOf') ? `<datalist id="mkBulkPolities${seq}">${[...new Set(arr(model0.periods).filter(p => p.itemKind === 'period').map(p => p.name).filter(Boolean))].map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>` : '';
    box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>${uids.length}개 한꺼번에 고치기</h2></div><form class="dlg-body"><label>고칠 칸 <select name="field">${fields.map(c => `<option value="${c.key}">${esc(c.label)}</option>`).join('')}<option value="shift">날짜 옮기기</option></select></label><label data-bulk-mode hidden>할 일 <select name="mode"></select></label><label data-bulk-value>새 값 <input name="value" aria-label="한꺼번에 넣을 값"></label><label data-bulk-rel hidden>소속 관계 <select name="relation" aria-label="소속 관계">${relationOptions}</select></label><label data-bulk-unit hidden>이동 단위 <select name="unit"><option value="year">년</option><option value="month">개월</option><option value="day">일</option></select></label><p data-bulk-current></p><p class="problems" data-bulk-warn hidden></p><p>잠긴 항목과 해당 칸이 없는 항목은 건너뜁니다. 날짜를 옮기면 안의 줄도 함께 옮깁니다.</p><button class="btn primary" type="submit">적용</button> <button class="btn" type="button" data-close>닫기</button><p role="status" data-bulk-result></p>${houseList}${polityList}</form></div>`;
    const form = box.querySelector('form'), warn = box.querySelector('[data-bulk-warn]');
    let confirmed = '';
    /** 파일 그대로의 값 — 제 항목은 작업본, 남의 항목은 원본 + 덮어쓰기(못 찾으면 모델의 항목) */
    const rawFor = uid => { const own = ownOf(uid); if (own) return own.item; const m = ctx.state.model.byUid.get(uid); try { return api.rawOf(m) || m; } catch { return m; } };
    const relName = id => HT.relationInfo(id)?.name || id;
    const partText = v => HT.readPartOf(v, { relation: true }).map(x => x.polity + (x.relation ? ` (${relName(x.relation)})` : '') + (x.start != null || x.end != null || x.startUnknown || x.endUnknown ? ' · 기간' : '')).join(' → ');
    const eligible = key => uids.filter(uid => { const own = ownOf(uid); return bulkFits(key, own ? own.list : listOfKind(ctx.state.model.byUid.get(uid)?.itemKind), api.draft); });
    const scopeWord = s => s.name || s.epoch || s.id;
    function paintCurrent() {
      const key = form.elements.field.value, c = fields.find(c => c.key === key), cur = box.querySelector('[data-bulk-current]');
      if (key === 'shift') { cur.textContent = '양수는 뒤로, 음수는 앞으로 옮깁니다.'; return; }
      if (key === 'tags') {
        const count = new Map();
        for (const uid of eligible('tags')) for (const t of readTags(rawFor(uid)?.tags)) count.set(t, (count.get(t) || 0) + 1);
        cur.textContent = (count.size ? '지금 태그: ' + [...count].map(([t, n]) => `${t} ${n}`).join(' · ') : '지금 태그 없음') + '. 쉼표로 여럿을 적습니다.';
        return;
      }
      if (key === 'scope') {
        const s = arr(api.draft.scopes).find(x => x.id === form.elements.value.value), periods = eligible('scope');
        const inside = s ? periods.filter(uid => { const m = ctx.state.model.byUid.get(uid) || { uid, ...rawFor(uid) }; return scopeMembers(s).some(r => scopeHas(r, m, s.track)); }).length : 0;
        cur.textContent = `고른 나라 ${periods.length}개 가운데 ${inside}개가 이 대범위에 들어 있습니다. 고치는 DLC의 대범위만 고를 수 있고, 대범위와 같은 트랙의 나라만 들어갑니다(불러온 나라도 넣을 수 있음 — 그 나라는 고치지 않음).`;
        return;
      }
      if (key === 'partOf') {
        const values = [...new Set(eligible('partOf').map(uid => partText(rawFor(uid)?.partOf)))];
        cur.textContent = (values.length === 1 ? '현재 값: ' + (values[0] || '비움') : '현재 값: 여러 값') + '. 상위 정권 하나로 정합니다(기간 없음) — 비우면 소속을 지웁니다.';
        return;
      }
      const opts = c ? options(c, api.draft, ctx.state.model) : [];
      const values = [...new Set(uids.map(uid => { const own = ownOf(uid); const x = own ? own.item : ctx.state.model.byUid.get(uid); return c && ['check', 'kin'].includes(c.type) ? (x ? value(api.draft, { list: 'figures' }, x, c) : '') : String(x?.[key] ?? ''); }))];
      cur.textContent = values.length === 1 ? '현재 값: ' + (opts.find(o => String(o.id) === values[0])?.name || values[0] || '비움') : '현재 값: 여러 값';
      if (values.length === 1) form.elements.value.value = values[0];
    }
    function update() {
      const key = form.elements.field.value, c = fields.find(c => c.key === key), opts = c ? options(c, api.draft, ctx.state.model) : [];
      confirmed = ''; warn.hidden = true;
      box.querySelector('[data-bulk-mode]').hidden = !['tags', 'scope'].includes(key);
      form.elements.mode.innerHTML = key === 'scope' ? '<option value="add">넣기</option><option value="remove">빼기</option>' : '<option value="add">더하기</option><option value="remove">빼기</option>';
      box.querySelector('[data-bulk-rel]').hidden = key !== 'partOf';
      box.querySelector('[data-bulk-value]').innerHTML = key === 'shift' ? '이동할 양 <input name="value" type="number" step="1" value="1" aria-label="이동할 양">'
        : key === 'scope' ? `대범위 <select name="value" aria-label="넣거나 뺄 대범위">${arr(api.draft.scopes).map(s => `<option value="${esc(s.id)}">${esc(scopeWord(s))}</option>`).join('')}</select>`
        : key === 'tags' ? '태그 <input name="value" autocomplete="off" aria-label="더하거나 뺄 태그 — 쉼표로 여럿">'
        : key === 'partOf' ? `상위 정권 <input name="value" autocomplete="off" list="mkBulkPolities${seq}" aria-label="상위 정권 — 비우면 소속을 지웁니다">`
        : key === 'house' ? `새 값 <input name="value" autocomplete="off" list="mkBulkHouses${seq}" aria-label="한꺼번에 넣을 ${esc(houseWord)}">`
        : c?.type === 'check' ? `새 값 <select name="value" aria-label="한꺼번에 넣을 ${esc(c.label)}"><option value="${esc(c.label)}">${esc(c.label)}</option><option value="">${esc(c.label)} 아님</option></select>`
        : c?.type === 'kin' ? `${esc(c.label)} <input name="value" autocomplete="off" aria-label="고른 사람들의 ${esc(c.label)} — 사람 이름 · 인물 id · 나라:지도자@해 (세 글자 넘게 치면 찾기 상자 · 비우면 지움)">`
        : `새 값 ${opts.length ? `<select name="value" aria-label="한꺼번에 넣을 값"><option value="">비움</option>${opts.map(o => `<option value="${esc(o.id)}">${esc(o.name || o.id)}</option>`).join('')}</select>` : '<input name="value" aria-label="한꺼번에 넣을 값">'}`;
      box.querySelector('[data-bulk-unit]').hidden = key !== 'shift';
      if (c?.type === 'kin' && HT.makerKin) HT.makerKin.attachFinder(form.elements.value, { track: () => '' });
      if (key === 'scope') form.elements.value.onchange = paintCurrent;
      if (key === 'partOf') {
        /* 고른 나라들의 소속이 모두 같은 한 줄(기간 없음)이면 그 값으로 채워 둡니다 */
        const one = [...new Set(eligible('partOf').map(uid => JSON.stringify(HT.readPartOf(rawFor(uid)?.partOf, { relation: true }))))];
        const list = one.length === 1 ? JSON.parse(one[0]) : [];
        if (list.length === 1 && !partOfLoses(list)) { form.elements.value.value = list[0].polity; form.elements.relation.value = list[0].relation || ''; }
        else form.elements.relation.value = '';
      }
      paintCurrent();
    }
    if (bulkMemo.field && (bulkMemo.field === 'shift' || fields.some(c => c.key === bulkMemo.field))) form.elements.field.value = bulkMemo.field;
    form.elements.field.onchange = update; update();
    if (bulkMemo.sig === sig && bulkMemo.at === (api.history ? api.history.index : null) && bulkMemo.result) box.querySelector('[data-bulk-result]').textContent = bulkMemo.result;
    form.onsubmit = async e => {
      e.preventDefault(); const original = api.draft, key = form.elements.field.value, text = form.elements.value.value, c = fields.find(c => c.key === key);
      const op = { key, text, unit: form.elements.unit.value, mode: form.elements.mode.value === 'remove' ? 'remove' : 'add', relation: form.elements.relation.value };
      const say = msg => { box.querySelector('[data-bulk-result]').textContent = msg; };
      bulkMemo = { ...bulkMemo, field: key }; // 적용하는 사이에 오른쪽 칸이 새로 그려져도 고르던 칸이 남게
      if (key === 'tags' && !readTags(text).length) { say('더하거나 뺄 태그를 적으세요.'); return; }
      if (key === 'scope' && !text) { say('대범위를 고르세요.'); return; }
      if (key === 'partOf') {
        /* 소속이 여럿이거나 기간이 적힌 항목은 덮어쓰면 그 목록이 사라지므로, 한 번 알리고 다시 누르면 적용합니다 */
        const crowded = eligible('partOf').filter(uid => partOfLoses(rawFor(uid)?.partOf)), now = JSON.stringify([text.trim(), op.relation]);
        if (crowded.length && confirmed !== now) {
          const names = crowded.slice(0, 5).map(uid => rawFor(uid)?.name || uid).join(', ') + (crowded.length > 5 ? ` 외 ${crowded.length - 5}개` : '');
          warn.textContent = `소속이 여럿이거나 기간 · 메모가 적힌 항목 ${crowded.length}개(${names})의 소속 목록을 ${text.trim() ? '이 한 줄로 바꿉니다' : '지웁니다'}. 그대로 하려면 [적용]을 한 번 더 누르세요.`;
          warn.hidden = false; confirmed = now; return;
        }
      }
      warn.hidden = true;
      let r = null, failure = '';
      const env = { model: ctx.state.model, isLocked: api.isLocked, rawOf: api.rawOf, baseModel: api.baseModel };
      const name = key === 'shift' ? '여러 항목 날짜 옮기기' : key === 'tags' ? `태그 한꺼번에 ${op.mode === 'remove' ? '뺌' : '더함'}` : key === 'scope' ? `대범위에 한꺼번에 ${op.mode === 'remove' ? '뺌' : '넣음'}` : `${c.label} 한꺼번에 고침`;
      const ok = await api.transact(draft => {
        if (draft.id !== original.id) throw Error('고치는 DLC가 바뀌었습니다.');
        try { r = bulkPlan(draft, uids, op, { ...env, model: ctx.state.model }); } catch (error) { failure = error.message; throw error; }
        return r.draft;
      }, name, { snapshot: uids.length > 20 });
      const why = r && r.reasons.length ? ` (${r.reasons.join(' · ')})` : '';
      const result = ok ? `${r.changed}개 고침 · ${r.skipped}개 건너뜀${why}${r.same ? ` · ${r.same}개는 이미 그대로` : ''}` : failure || (r && !r.changed && r.same ? `이미 모두 그대로입니다 · ${r.skipped}개 건너뜀${why}` : '적용한 고침이 없습니다. 입력과 잠금 상태를 확인하세요.');
      bulkMemo = { field: key, sig, at: ok && api.history ? api.history.index : null, result: ok ? result : '' };
      say(result); confirmed = '';
      /* 적용은 열려 있던 편집 창을 먼저 닫는데(api.transact → 편집 창 닫기), 그때 고른 것이 풀리면 이어서 고칠 수 없으므로 같은 항목들을 다시 고릅니다
         (오른쪽 칸이 새로 그려지며 위의 결과 글을 이어 보여 줌) */
      if (ok && api.selectItems && api.selection && !api.selection().length) api.selectItems(uids);
    };
    if (container) {
      box.querySelector('[data-close]').hidden = true;
      form.insertAdjacentHTML('beforeend', '<p class="mk-bulk-actions"><button type="button" class="btn btn-sm" data-bulk-copy>복제</button> <button type="button" class="btn btn-sm" data-bulk-delete>지우기</button></p>');
      form.querySelector('[data-bulk-copy]').onclick = () => api.duplicateSelection(uids);
      form.querySelector('[data-bulk-delete]').onclick = () => api.deleteSelection();
      const foreign = uids.filter(uid => !HT.draft.isOwnUid(api.draft, uid));
      if (foreign.length) { const b = document.createElement('button'); b.type = 'button'; b.className = 'btn btn-sm'; b.textContent = '불러온 항목을 내 DLC로 복사'; b.onclick = () => api.duplicateSelection(foreign); form.querySelector('.mk-bulk-actions').append(b); }
    }
    else { box.querySelector('[data-close]').onclick = () => box.close(); box.onclose = () => box.remove(); document.body.append(box); box.showModal(); }
  }
  HT.makerGrid = { words, subNames, columns, rowsOf, objectRow, value, options, parse, plan, pasteWrites, moveCellDocuments, patchItem, mount, bulkDialog, bulkPlan, bulkFits, BULK_FIELDS };
})();

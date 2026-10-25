/* 역사 연표 — 메이커의 함께 만드는 틀 (dlc-maker.html에서만 읽힘 · 10건 D3 결정 6 A — docs/설계-10건/4-5-메이커-블록과-묶음.md · 감독-선택.md D3)
 *
 * 틀 = 묻는 칸 몇 개(나라 · 해 · 이름 …)를 한 번만 적으면 여러 줄 · 항목을 함께 만드는 것입니다(16건 8번 '한번에 입력'을 이 틀로 읽음 — 감독 선택).
 *   기본 틀 셋: 새 지도자(지도자 줄 + 연호 줄 + 승계 사건) · 천도(도읍 줄 + 천도 사건) · 개원(연호 줄 + 개원 사건) — 그 뒤에 만든 사람의 틀.
 *   빈칸 채우기 창: '＋ 더' 메뉴 · 메뉴 줄 '넣기' · 명령 찾기(Ctrl+K) · 편집 창의 '/' 목록에서 틀을 고르면 → 묻는 칸만 적고 '만들어질 것'을 미리 본 뒤
 *     [만들기] = 작업본 고침 한 번(api.transact — 되돌리기 한 걸음). 같은 해는 한 번만 적고, 전임자(앞 줄)의 끝을 그 해로 잇는 일도 미리 글에 보입니다.
 *   틀 관리 창: 틀 목록(이 차례대로 메뉴에 보임 · Alt+↑↓로 차례) · 이름 · 묻는 칸(＋ 칸 · 해/글 · 비워도 됨) · 만드는 것(지도자 · 내각 · 연호 · 도읍 · 지위 줄 · 사건)
 *     · 이 틀 지우기 · 기본 틀 되살리기. 블록 메뉴의 '틀로 저장…'(편집 창에서 줄을 고르고 손잡이 ⋮⋮)은 그 줄들의 꼴로 채운 새 틀을 이 창에 엶.
 * 틀은 작업실 설정(ht.maker.templates — 이 브라우저, DLC 파일에 들어가지 않음 · 형식 변화 없음). 만드는 것은 지금 열쇠(leaders · cabinets · eras · capitals · ranks · events)뿐이고
 * 칸은 편집 창이 적는 것과 같은 꼴({ name | city, start, role? } · 사건 { title, start, track, polity, category })이라, 틀로 만든 파일과 손으로 적은 파일이 다르지 않습니다
 * (형식 3 열쇠를 쓰지 않으므로 형식 버전도 그대로 — 내보내기 · 새 앱은 늘 보던 칸만 받음).
 * 앞부분(HT.makerTemplates의 표 · 계산 — readStore · plan · applyPlan · fromRows)은 화면 없이도 돌고(검사가 부름), mount(ctx, api)가 두 창과 메뉴 줄을 붙입니다(js/maker.js의 start). */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const esc = s => HT.escapeHtml(String(s ?? ''));
  const arr = v => (Array.isArray(v) ? v : []);
  const str = v => (typeof v === 'string' ? v.trim() : '');
  const clone = x => JSON.parse(JSON.stringify(x));

  /* ================= 표 · 계산 (화면 없음) ================= */
  const KEY = 'ht.maker.templates'; // 작업실 설정: { v: 1, list: [틀 …], openAfter } — 없으면 기본 틀 셋
  const LIMITS = { templates: 40, asks: 12, makes: 12, name: 40, label: 20, text: 200 };
  /** 만드는 것의 종류 — main: 글 칸 열쇠(묻는 칸을 {칸 이름}으로 넣음) · prev: 앞 줄의 이름(있으면 '전임자의 끝을 이 해로 이음'을 고를 수 있음) */
  const KINDS = {
    leaders: { word: '지도자 줄', main: 'name', mainWord: '이름', prev: '전임자', rowWord: '지도자 이름' },
    cabinets: { word: '내각 줄', main: 'name', mainWord: '이름', prev: '전임 내각', rowWord: '내각 이름' },
    eras: { word: '연호 줄', main: 'name', mainWord: '이름', prev: '이전 연호', rowWord: '연호' },
    capitals: { word: '도읍 줄', main: 'city', mainWord: '도시', rowWord: '도읍' },
    ranks: { word: '지위 줄', main: 'name', mainWord: '지위', prev: '이전 지위', rowWord: '지위' },
    event: { word: '사건', main: 'title', mainWord: '제목' },
  };
  const KIND_ORDER = ['leaders', 'cabinets', 'eras', 'capitals', 'ranks', 'event'];
  const POLITY = { id: 'polity', label: '나라', type: 'polity' };
  const DEFAULTS = [
    {
      id: 'b-leader',
      name: '새 지도자',
      asks: [POLITY, { id: 'year', label: '승계 해', type: 'year' }, { id: 'who', label: '지도자 이름', type: 'text' }, { id: 'era', label: '연호', type: 'text', optional: true }],
      makes: [
        { kind: 'leaders', text: '{지도자 이름}', start: 'year', link: true },
        { kind: 'eras', text: '{연호}', start: 'year', link: true },
        { kind: 'event', text: '{지도자 이름} 승계', start: 'year', category: 'politics' },
      ],
    },
    {
      id: 'b-capital',
      name: '천도',
      asks: [POLITY, { id: 'year', label: '천도 해', type: 'year' }, { id: 'city', label: '새 도읍', type: 'text' }],
      makes: [
        { kind: 'capitals', text: '{새 도읍}', start: 'year', role: 'main' },
        { kind: 'event', text: '{새 도읍} 천도', start: 'year', category: 'politics' },
      ],
    },
    {
      id: 'b-era',
      name: '개원',
      asks: [POLITY, { id: 'year', label: '개원 해', type: 'year' }, { id: 'era', label: '새 연호', type: 'text' }],
      makes: [
        { kind: 'eras', text: '{새 연호}', start: 'year', link: true },
        { kind: 'event', text: '{새 연호} 개원', start: 'year', category: 'politics' },
      ],
    },
  ];
  const ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
  const TOKEN = /\{([^{}]{1,20})\}/g;
  const cleanLabel = v => str(v).replace(/[{}]/g, '').slice(0, LIMITS.label).trim();
  const newId = (prefix, taken) => {
    let id;
    do id = `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    while (taken && taken.has(id));
    return id;
  };

  /** 받침에 맞는 조사 — 한글이 아닌 끝(숫자 · 영문)은 둘 다 적음 ('을(를)') */
  function josa(word, a, b) {
    const w = String(word ?? '');
    const c = w.trim().slice(-1).charCodeAt(0);
    if (!(c >= 0xac00 && c <= 0xd7a3)) return `${w}${a}(${b})`;
    const jong = (c - 0xac00) % 28;
    if (a === '으로') return `${w}${jong && jong !== 8 ? '으로' : '로'}`; // ㄹ 받침은 '로'
    return `${w}${jong ? a : b}`;
  }
  /** «낱말» + 조사 ('«승계 해»를') */
  const quoted = (w, a, b) => `«${w}»${josa(w, a, b).slice(String(w ?? '').length)}`;

  /** 틀 하나를 읽어 바로잡음 — 모르는 값 · 한도 밖은 버리고, 나라 칸은 늘 맨 앞에 하나, 해 칸이 없으면 하나 더함 (null = 쓸 수 없는 틀) */
  function cleanTemplate(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const id = ID_RE.test(str(raw.id)) ? str(raw.id) : '';
    const name = str(raw.name).slice(0, LIMITS.name);
    if (!id || !name) return null;
    const asks = [Object.assign({}, POLITY)];
    for (const a of arr(raw.asks)) {
      if (!a || typeof a !== 'object' || a.type === 'polity' || a.id === 'polity' || asks.length >= LIMITS.asks) continue;
      const aid = str(a.id);
      const label = cleanLabel(a.label);
      if (!ID_RE.test(aid) || !label || asks.some(x => x.id === aid || x.label === label)) continue;
      const type = a.type === 'year' ? 'year' : 'text';
      asks.push(Object.assign({ id: aid, label, type }, a.optional === true && type === 'text' ? { optional: true } : {}));
    }
    if (!asks.some(a => a.type === 'year')) {
      let label = '해';
      for (let n = 2; asks.some(a => a.label === label); n++) label = `해 ${n}`;
      let aid = 'year';
      for (let n = 2; asks.some(a => a.id === aid); n++) aid = `year${n}`;
      asks.splice(1, 0, { id: aid, label, type: 'year' });
    }
    const years = asks.filter(a => a.type === 'year');
    const makes = [];
    for (const m of arr(raw.makes)) {
      if (!m || typeof m !== 'object' || !KINDS[m.kind] || makes.length >= LIMITS.makes) continue;
      const o = { kind: m.kind, text: String(m.text ?? '').slice(0, LIMITS.text), start: years.some(a => a.id === m.start) ? m.start : years[0].id };
      if (KINDS[m.kind].prev && m.link === true) o.link = true;
      if (m.kind === 'capitals') o.role = (HT.CAPITAL_ROLES || []).some(r => r.id === m.role) ? m.role : 'main';
      if (m.kind === 'event' && str(m.category)) o.category = str(m.category).slice(0, 64);
      makes.push(o);
    }
    return { id, name, asks, makes };
  }
  /** 작업실 설정 읽기 — 적힌 것이 없으면 기본 틀 셋(지운 기본 틀은 '기본 틀 되살리기'로) */
  function readStore(raw) {
    const o = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null;
    if (!o || !Array.isArray(o.list)) return { list: DEFAULTS.map(t => cleanTemplate(clone(t))), openAfter: !o || o.openAfter !== false };
    const list = [];
    for (const t of o.list) {
      const c = cleanTemplate(t);
      if (c && !list.some(x => x.id === c.id) && list.length < LIMITS.templates) list.push(c);
    }
    return { list, openAfter: o.openAfter !== false };
  }
  /** 글 칸의 {칸 이름}을 뺀 글 (사건 제목의 고정 글 — 메뉴의 한 줄 요약) */
  const literal = text => String(text || '').replace(TOKEN, ' ').replace(/\s+/g, ' ').trim();
  /** 메뉴의 한 줄 요약: '지도자 줄 + 연호 줄 + 승계 사건' */
  const summaryOf = t => t.makes.map(m => (m.kind === 'event' ? (literal(m.text) ? `${literal(m.text)} 사건` : '사건') : KINDS[m.kind].word)).join(' + ') || '만들 것 없음';
  /** 글 칸의 {칸 이름}을 적은 값으로 — empties: 값이 빈 칸 · unknown: 없는 칸 이름. 나라 칸은 고른 나라의 이름(values.$polityName) */
  function fillText(t, text, values) {
    const byLabel = new Map(t.asks.map(a => [a.label, a]));
    const empties = [];
    const unknown = [];
    const out = String(text || '').replace(TOKEN, (all, label) => {
      const a = byLabel.get(label.trim());
      if (!a) {
        unknown.push(label);
        return all;
      }
      const v = a.type === 'polity' ? str(values.$polityName) : str(values[a.id]);
      if (!v) empties.push(a);
      return v;
    });
    return { text: out.replace(/\s+/g, ' ').trim(), empties, unknown };
  }
  /** 해 칸의 글 → { value(파일에 적을 값 — 서력 연도만이면 수, 날짜 · 음력이면 적은 글 그대로), t } · { error } · null(빈 칸) */
  function readYear(text) {
    const s = str(text);
    if (!s) return null;
    const d = HT.readDate(s);
    if (!d || !Number.isFinite(d.t)) return { error: (d && d.error) || '날짜를 읽을 수 없습니다.' };
    const plain = d.prec === 'y' && (!d.cal || d.cal === 'civil') && !d.at && Number.isInteger(d.t);
    return { value: plain ? d.t : s, t: d.t };
  }
  const yearText = y => (!y ? '' : typeof y.value === 'number' ? HT.formatAxisYear(y.value) : String(y.value));
  const listKey = (item, kind) => (kind === 'leaders' && !Array.isArray(item.leaders) && Array.isArray(item.reigns) ? 'reigns' : kind);
  const cellOf = (kind, raw) => (raw && typeof raw === 'object' ? HT.formCell(kind, raw) || {} : typeof raw === 'string' ? { name: raw } : {});
  const cellName = c => str(c.name) || str(c.city) || str(c.as) || str(c.temple) || str(c.title) || str(c.given) || '이름 없음';
  /** 목록에서 t 바로 앞에 시작한 줄(전임자 — { i, c }) · 같은 해에 시작한 줄들 */
  function neighbours(list, kind, t) {
    let prev = null;
    const same = [];
    arr(list).forEach((raw, i) => {
      const c = cellOf(kind, raw);
      if (!Number.isFinite(c.start)) return;
      if (Math.abs(c.start - t) < 1e-9) same.push({ i, c });
      else if (c.start < t && (!prev || c.start >= prev.c.start)) prev = { i, c };
    });
    return { prev, same };
  }
  /** 전임자 잇기: 'set'(끝이 비었거나 미정 · 이 해보다 늦음 → 이 해로 고침) · 'same'(이미 이 해에 끝남) · 'gap'(더 일찍 끝남 — 그대로) · null(전임자 없음) */
  function linkOf(prev, t) {
    if (!prev) return null;
    const e = prev.c.end;
    if (prev.c.endUnknown || !Number.isFinite(e) || e > t + 1e-9) return 'set';
    return Math.abs(e - t) < 1e-9 ? 'same' : 'gap';
  }
  /** 사건이 가리킬 나라 글 — 같은 트랙에 같은 이름이 없으면 이름, 있으면 id(이 DLC) · uid(불러온 팩) (구조 나무 끌기의 나라 글과 같은 규칙) */
  function polityRef(model, p, draftId) {
    const same = arr(model && model.periods).filter(q => q !== p && q.track === p.track && (q.name === p.name || q.id === p.name || q.uid === p.name));
    return !same.length ? p.name : p.packId === draftId ? p.id : p.uid;
  }
  const spanText = p => {
    const a = Number.isFinite(p.start) ? HT.formatAxisYear(p.start) : '';
    const b = p.ongoing ? '현재' : Number.isFinite(p.endY) ? HT.formatAxisYear(p.endY) : '';
    return a && b && a !== b ? `${a}–${b}` : a;
  };

  /** 만들 계획. values = { 칸 id: 적은 글, '@ev<i>': 고쳐 적은 사건 제목 } · env = { model, draftId, rawOf(나라) → 파일 그대로의 그 나라 }
      → { problems: [{ ask?, text }], polity, items: [{ i, kind, word, text, y, skip?, cell?, event?, note?, warn?, wantLink }], n(만들어질 수) } */
  function plan(t, values, env) {
    const problems = [];
    const model = env.model;
    const polity = values.polity && model && model.byUid ? model.byUid.get(values.polity) || null : null;
    if (!polity || HT.itemKindOf(polity) !== 'period') problems.push({ ask: 'polity', text: '나라를 고르세요.' });
    const v = Object.assign({}, values, { $polityName: polity ? polity.name : '' });
    const years = {};
    for (const a of t.asks) {
      if (a.type === 'polity') continue;
      const s = str(values[a.id]);
      if (a.type === 'year') {
        const y = readYear(s);
        if (!y) problems.push({ ask: a.id, text: `${quoted(a.label, '을', '를')} 적으세요.` });
        else if (y.error) problems.push({ ask: a.id, text: `«${a.label}»: ${y.error}` });
        else years[a.id] = y;
      } else if (!s && !a.optional) problems.push({ ask: a.id, text: `${quoted(a.label, '을', '를')} 적으세요.` });
    }
    let raw = null;
    if (polity && env.rawOf) {
      try {
        raw = env.rawOf(polity);
      } catch (e) {
        problems.push({ ask: 'polity', text: e.message || '나라의 원본을 찾지 못했습니다.' });
      }
    }
    const items = [];
    t.makes.forEach((m, i) => {
      const K = KINDS[m.kind];
      const f = fillText(t, m.text, v);
      const over = m.kind === 'event' ? str(values[`@ev${i}`]) : '';
      const text = over || f.text;
      const y = years[m.start];
      const it = { i, kind: m.kind, word: K.word, text, y, wantLink: !!m.link };
      items.push(it);
      if (f.unknown.length) problems.push({ text: `만들 것 ${i + 1}(${K.word})에 없는 칸 {${f.unknown[0]}}이 있습니다 — 틀 관리에서 고치세요.` });
      const skipBy = !over && f.empties.find(a => a.optional);
      if (skipBy) {
        it.skip = `${quoted(skipBy.label, '이', '가')} 비어 건너뜀`;
        return;
      }
      if (!y || !polity || (!over && f.empties.length)) return; // 적을 칸이 남음 (problems에 이미)
      if (!text) {
        problems.push({ text: `만들 것 ${i + 1}(${K.word})의 ${josa(K.mainWord, '이', '가')} 비었습니다.` });
        return;
      }
      const out = y.t < polity.start - 1e-9 || (Number.isFinite(polity.endY) && !polity.ongoing && y.t >= polity.endY + 1);
      if (m.kind === 'event') {
        const cat = m.category && model.categoryMap ? model.categoryMap.get(m.category) : null;
        it.event = Object.assign({ title: text, start: y.value, track: polity.track, polity: polityRef(model, polity, env.draftId) }, cat ? { category: cat.id } : {});
        it.note = [yearText(y), polity.name, cat ? cat.name : ''].filter(Boolean).join(' · ');
      } else {
        it.cell = Object.assign({ [K.main]: text, start: y.value }, m.kind === 'capitals' && m.role && m.role !== 'main' ? { role: m.role } : {});
        const nb = neighbours(raw ? raw[listKey(raw, m.kind)] : [], m.kind, y.t);
        if (nb.same.length) it.warn = nb.same.some(s => cellName(s.c) === text) ? '같은 해 · 같은 이름의 줄이 이미 있음' : `같은 해에 시작하는 줄 «${cellName(nb.same[0].c)}»이(가) 이미 있음`;
        if (m.link && K.prev) {
          const how = linkOf(nb.prev, y.t);
          const who = nb.prev ? `${K.prev} ${cellName(nb.prev.c)}` : '';
          it.note =
            how === 'set' ? `${who}의 끝을 ${yearText(y)}에 맞춰 이음`
            : how === 'same' ? `${who}의 끝 ${yearText(y)}에 이어짐`
            : how === 'gap' ? `${who}의 끝 ${HT.formatAxisYear(nb.prev.c.end)} 그대로 — 사이가 빔`
            : `${K.prev} 없음 — 첫 줄`;
        }
      }
      if (out && !it.warn) it.warn = `나라 기간(${spanText(polity)}) 밖`;
    });
    return { problems, polity, items, n: items.filter(x => !x.skip && (x.cell || x.event)).length };
  }
  /** 앞 줄의 끝을 고침 — 짧은 꼴 [이름, 시작, 끝, 메모]은 셋째 칸, 객체는 end(미정 · 날짜 글 · 배치용 연도는 걷어 냄) */
  function setEnd(list, i, value) {
    const r = list[i];
    if (Array.isArray(r)) {
      while (r.length < 2) r.push(null);
      r[2] = value;
    } else if (typeof r === 'string') list[i] = { name: r, end: value };
    else if (r && typeof r === 'object') {
      r.end = value;
      for (const k of ['endUnknown', 'endAt', 'endHint', 'endAuto']) delete r[k];
    }
  }
  /** 계획을 작업본에 (api.transact 안에서 — 한 걸음). 나라가 이 DLC의 것이면 그 자리에서, 불러온 팩(잠김을 푼 것)의 것이면 사본을 고쳐 바뀐 칸만 덮어쓰기로
      (편집 창의 '다른 나라로 옮기기' · 구조 나무 끌기와 같은 길). env = { model, rawOf, isLocked, baseModel } — 만든 수를 돌려줌 */
  function applyPlan(draft, p, env) {
    const D = HT.draft;
    const pol = p.polity;
    if (!pol) throw Error('나라를 고르세요.');
    const own = D.isOwnUid(draft, pol.uid) && D.findOwn(draft, pol.uid.slice(draft.id.length + 1));
    let item;
    let done = () => {};
    if (own) item = own.item;
    else {
      if (env.isLocked && env.isLocked(pol)) throw Error(`잠긴 팩 «${pol.packName}»의 나라라 고칠 수 없습니다 — 불러온 팩 탭에서 자물쇠를 풀면 됩니다.`);
      const before = env.rawOf(pol);
      if (!before) throw Error('고칠 나라의 원본을 찾지 못했습니다.');
      item = clone(before);
      done = () => HT.makerGrid.patchItem(draft, (env.baseModel && env.baseModel().byUid.get(pol.uid)) || pol, before, item);
    }
    let n = 0;
    for (const it of p.items) {
      if (it.skip || !it.cell) continue;
      const key = listKey(item, it.kind);
      const list = Array.isArray(item[key]) ? item[key] : (item[key] = []);
      if (it.wantLink) {
        const nb = neighbours(list, it.kind, it.y.t);
        if (linkOf(nb.prev, it.y.t) === 'set') setEnd(list, nb.prev.i, it.y.value);
      }
      const k = list.findIndex(r => {
        const s = cellOf(it.kind, r).start;
        return Number.isFinite(s) && s > it.y.t + 1e-9;
      }); // 시작 순 자리 (저장하면 편집 창도 시작 순으로 다시 놓음)
      list.splice(k < 0 ? list.length : k, 0, clone(it.cell));
      n++;
    }
    done();
    for (const it of p.items) {
      if (it.skip || !it.event) continue;
      D.addItem(draft, 'event', clone(it.event));
      n++;
    }
    if (env.model) D.ensureRefs(draft, env.model); // 불러온 팩의 트랙에 사건을 두면 그 트랙도 이 DLC에 적힘
    return n;
  }
  /** 편집 창에서 고른 줄들 → 새 틀(같은 꼴: 줄마다 이름 칸 하나 · 같은 해는 해 칸 하나). rows = [{ kind, item(읽은 줄) }] · taken = 이미 있는 틀 이름 */
  function fromRows(rows, taken = []) {
    const years = [];
    const texts = [];
    const makes = [];
    const all = () => [POLITY, ...years, ...texts];
    const label = base => {
      let l = base;
      for (let n = 2; all().some(a => a.label === l); n++) l = `${base} ${n}`;
      return l;
    };
    const aid = base => {
      let id = base;
      for (let n = 2; all().some(a => a.id === id); n++) id = `${base}${n}`;
      return id;
    };
    const byStart = new Map();
    for (const { kind, item } of arr(rows)) {
      const K = KINDS[kind];
      if (!K || kind === 'event' || !item) continue;
      const key = String(item.start ?? '');
      let y = byStart.get(key);
      if (!y) {
        y = aid('year');
        years.push({ id: y, label: label('해'), type: 'year' });
        byStart.set(key, y);
      }
      const l = label(K.rowWord);
      texts.push({ id: aid('a'), label: l, type: 'text' });
      const m = { kind, text: `{${l}}`, start: y };
      if (K.prev) m.link = true;
      if (kind === 'capitals' && item.role && item.role !== 'main') m.role = item.role;
      makes.push(m);
    }
    if (!makes.length) return null;
    let name = '새 틀';
    for (let n = 2; taken.includes(name); n++) name = `새 틀 ${n}`;
    return cleanTemplate({ id: newId('t-'), name, asks: all(), makes });
  }
  /** 틀 관리 창의 저장 전 검사 → [{ i(틀 자리), text }] */
  function validate(list) {
    const out = [];
    list.forEach((t, i) => {
      const nm = str(t.name);
      const who = nm ? `틀 «${nm}»` : `틀 ${i + 1}`;
      if (!nm) out.push({ i, text: `${who}: 이름을 적으세요.` });
      else if (list.findIndex(x => str(x.name) === nm) !== i) out.push({ i, text: `${who}: 같은 이름의 틀이 이미 있습니다.` });
      const labels = t.asks.map(a => a.label);
      if (labels.some((l, k) => !l || labels.indexOf(l) !== k)) out.push({ i, text: `${who}: 묻는 칸의 이름이 비었거나 겹칩니다.` });
      if (!t.asks.some(a => a.type === 'year')) out.push({ i, text: `${who}: 해 칸이 하나는 있어야 합니다.` });
      if (!t.makes.length) out.push({ i, text: `${who}: 만들 것이 없습니다 — '＋ 만들 것 더하기'로 더하세요.` });
      t.makes.forEach((m, k) => {
        const K = KINDS[m.kind];
        const f = fillText(t, m.text, {});
        if (!str(m.text)) out.push({ i, text: `${who}의 만들 것 ${k + 1}(${K.word}): ${josa(K.mainWord, '을', '를')} 적으세요.` });
        else if (f.unknown.length) out.push({ i, text: `${who}의 만들 것 ${k + 1}(${K.word}): 없는 칸 {${f.unknown[0]}}` });
        if (!t.asks.some(a => a.type === 'year' && a.id === m.start)) out.push({ i, text: `${who}의 만들 것 ${k + 1}(${K.word}): 해 칸을 고르세요.` });
      });
    });
    return out;
  }

  /* ================= 화면 ================= */
  function mount(ctx, api) {
    const state = ctx.state;
    let store = readStore(HT.store.get(KEY, null));
    const reload = () => (store = readStore(HT.store.get(KEY, null))); // 다른 메이커 탭이 고쳤을 수도
    const saveStore = () => HT.store.set(KEY, { v: 1, list: store.list, openAfter: store.openAfter });
    const find = id => store.list.find(t => t.id === id) || null;
    const D = HT.draft;
    /** 파일 그대로의 나라: 이 DLC의 것은 작업본의 그 항목, 불러온 팩의 것은 원본(+ 이미 건 덮어쓰기) */
    const rawOf = x => {
      if (api.isOwn(x)) {
        const hit = api.draft && D.findOwn(api.draft, x.id);
        return hit ? hit.item : null;
      }
      return api.rawOf(x);
    };
    const env = () => ({ model: state.model, draftId: api.draft ? api.draft.id : '', rawOf, isLocked: x => api.isLocked(x), baseModel: api.baseModel });
    const usable = x => !!x && HT.itemKindOf(x) === 'period' && (api.isOwn(x) || !api.isLocked(x));
    function polities() {
      const all = arr(state.model && state.model.periods).filter(usable);
      const by = (a, b) => (a.start - b.start) || String(a.name).localeCompare(String(b.name), 'ko');
      return { mine: all.filter(x => api.isOwn(x)).sort(by), theirs: all.filter(x => !api.isOwn(x)).sort((a, b) => String(a.packName).localeCompare(String(b.packName), 'ko') || by(a, b)) };
    }
    function defaultPolity(pref) {
      const ok = uid => (uid && usable(state.model.byUid.get(uid)) ? uid : '');
      const P = polities();
      return ok(pref) || ok(state.editing) || ok(api.selection()[0]) || ((P.mine[0] || P.theirs[0] || {}).uid || '');
    }

    /* ---------- 빈칸 채우기 창 ---------- */
    let fillDlg = null;
    let fill = null; // { t, dirty: Set(사건 제목을 고친 만들 것 자리), tried, plan }
    function buildFill() {
      fillDlg = document.body.appendChild(Object.assign(document.createElement('dialog'), { className: 'mk-tpl', id: 'mkTplFill' }));
      fillDlg.setAttribute('aria-labelledby', 'mkTplFillTitle');
      fillDlg.addEventListener('click', e => {
        if (e.target === fillDlg || e.target.closest('[data-close]')) fillDlg.close();
      });
      fillDlg.addEventListener('input', e => {
        if (!fill) return;
        fill.failed = '';
        const ev = e.target.closest('[data-ev]');
        if (ev) {
          if (str(ev.value)) fill.dirty.add(Number(ev.dataset.ev));
          else fill.dirty.delete(Number(ev.dataset.ev)); // 비우면 다시 틀이 짓는 글로
        }
        renderFill();
      });
      fillDlg.addEventListener('change', e => e.target.matches('[data-ask="polity"]') && renderFill());
      fillDlg.addEventListener('submit', e => {
        e.preventDefault();
        submitFill();
      });
      fillDlg.addEventListener('close', () => (fill = null));
    }
    function readFill() {
      const values = {};
      for (const el of fillDlg.querySelectorAll('[data-ask]')) values[el.dataset.ask] = el.value;
      for (const el of fillDlg.querySelectorAll('[data-ev]')) if (fill.dirty.has(Number(el.dataset.ev))) values[`@ev${el.dataset.ev}`] = el.value;
      return values;
    }
    /** 이 칸을 비우면 건너뛰는 것들의 이름 ('연호 줄') */
    const skipWords = (t, a) => t.makes.filter(m => fillText(t, m.text, {}).empties.includes(a)).map(m => (m.kind === 'event' ? '사건' : KINDS[m.kind].word)).join(' · ');
    function openFill(id, opts = {}) {
      reload();
      const t = find(id);
      if (!t) return HT.toast('그 틀을 찾지 못했습니다 — 틀 관리에서 지웠을 수 있습니다.', 'error');
      if (!api.draft) return HT.toast('고칠 DLC가 없습니다 — 파일 ▸ 처음 화면에서 DLC를 고르세요.', 'error');
      const P = polities();
      if (!P.mine.length && !P.theirs.length) return HT.toast('틀로 채울 나라가 없습니다 — 먼저 시대(나라)를 더하거나 불러온 팩의 자물쇠를 푸세요.', 'error');
      if (!fillDlg) buildFill();
      fill = { t, dirty: new Set(), tried: false, plan: null, raws: new Map() }; // raws: 창이 떠 있는 동안 나라 원본(불러온 팩의 것은 팩 하나를 통째로 풀어 얻으므로 치는 글자마다 다시 풀지 않게 — 창은 모달이라 작업본은 그대로)
      const cur = defaultPolity(opts.polity);
      const trackName = id => ((state.model.trackMap && state.model.trackMap.get(id)) || {}).name || id;
      const group = (list, keyOf, labelOf) => {
        const m = new Map();
        for (const x of list) {
          const k = keyOf(x);
          if (!m.has(k)) m.set(k, []);
          m.get(k).push(x);
        }
        return [...m].map(([k, xs]) => `<optgroup label="${esc(labelOf(k))}">${xs.map(x => `<option value="${esc(x.uid)}"${x.uid === cur ? ' selected' : ''}>${esc(`${x.name} (${spanText(x)})`)}</option>`).join('')}</optgroup>`).join('');
      };
      const polSel = group(P.mine, x => x.track, k => `이 DLC — ${trackName(k)}`) + group(P.theirs, x => x.packName, k => `«${k}» — 덮어쓰기로`);
      const asks = t.asks
        .map(a => {
          if (a.type === 'polity') return `<label class="field"><span>${esc(a.label)}</span><select data-ask="polity">${polSel}</select></label>`;
          const hint = a.optional ? ` <small>(비우면 ${esc(josa(skipWords(t, a) || '그 줄', '은', '는'))} 건너뜀)</small>` : a.type === 'year' ? ' <small>(연도 · 날짜)</small>' : '';
          return `<label class="field"><span>${esc(a.label)}${hint}</span><input data-ask="${esc(a.id)}" autocomplete="off" spellcheck="false" maxlength="80"></label>`;
        })
        .join('');
      const evs = t.makes.map((m, i) => ({ m, i })).filter(x => x.m.kind === 'event');
      const evFields = evs.map((x, k) => `<label class="field field-wide"><span>사건 제목${evs.length > 1 ? ` ${k + 1}` : ''} <small>(틀이 지은 글 — 고쳐도 됩니다)</small></span><input data-ev="${x.i}" autocomplete="off" spellcheck="false" maxlength="200"></label>`).join('');
      const words = t.makes.map(m => (m.kind === 'event' ? (literal(m.text) ? `${literal(m.text)} 사건` : '사건') : KINDS[m.kind].word));
      const lead = `${josa(words.join(' · ') || '만들 것', '을', '를')} 한 번에 만듭니다. 같은 해는 한 번만 적습니다.`;
      fillDlg.innerHTML = `<form class="dlg" method="dialog" novalidate>
        <div class="dlg-head"><h2 id="mkTplFillTitle">틀로 만들기 — ${esc(t.name)}</h2><button type="button" class="icon-btn" data-close aria-label="닫기">✕</button></div>
        <div class="dlg-body"><p class="lead">${esc(lead)}</p><div class="form-grid">${asks}${evFields}</div><ul class="problems" data-fill-problems hidden></ul>
          <div class="mk-made" aria-live="polite"><h4><span data-made-n></span><small>되돌리기 한 걸음</small></h4><ol data-made></ol></div></div>
        <div class="dlg-foot"><label class="check"><input type="checkbox" data-open-after${store.openAfter ? ' checked' : ''}> <span data-open-label></span></label><span class="spacer"></span><button type="button" class="btn" data-close>취소</button><button type="submit" class="btn btn-primary">만들기</button></div>
      </form>`;
      renderFill();
      fillDlg.showModal();
      const first = [...fillDlg.querySelectorAll('[data-ask]')].find(el => el.dataset.ask !== 'polity' && !el.value) || fillDlg.querySelector('[data-ask="polity"]');
      if (first) first.focus();
      return true;
    }
    function renderFill() {
      if (!fill || !fillDlg.open && !fillDlg.isConnected) return;
      const values = readFill();
      const e = env();
      const raws = fill.raws;
      e.rawOf = x => (raws.has(x.uid) ? raws.get(x.uid) : (raws.set(x.uid, rawOf(x)), raws.get(x.uid)));
      const p = plan(fill.t, values, e);
      if (fill.tried && !p.problems.length && !p.n) p.problems.push({ text: '만들 것이 없습니다 — 비운 칸 때문에 모두 건너뜁니다.' });
      fill.plan = p;
      /* 사건 제목: 고치지 않은 것은 틀이 지은 글로 따라감 */
      for (const el of fillDlg.querySelectorAll('[data-ev]')) {
        const i = Number(el.dataset.ev);
        if (fill.dirty.has(i)) continue;
        el.value = fillText(fill.t, fill.t.makes[i].text, Object.assign({}, values, { $polityName: p.polity ? p.polity.name : '' })).text;
      }
      const pol = p.polity;
      fillDlg.querySelector('[data-open-label]').textContent = `만든 뒤 ${pol ? pol.name : '그 나라'} 편집 창 열기`;
      fillDlg.querySelector('[data-made-n]').textContent = `만들어질 것 ${p.n}`;
      fillDlg.querySelector('[data-made]').innerHTML = p.items
        .map(it => {
          const k = `<span class="k">${esc(it.word)}</span>`;
          if (it.skip) return `<li class="is-skip">${k}<span class="t">${esc(it.skip)}</span></li>`;
          if (!it.cell && !it.event) return `<li class="is-wait">${k}<span class="t">${esc(it.text || '…')}</span><span class="y">적을 칸이 남음</span></li>`;
          const tail = `${it.note && it.kind !== 'event' ? `<span class="ok">${esc(it.note)}</span>` : ''}${it.warn ? `<span class="w">${esc(it.warn)}</span>` : ''}`;
          if (it.event) return `<li>${k}<b>${esc(it.text)}</b><span class="y">${esc(it.note)}</span>${tail}</li>`;
          return `<li>${k}<i class="dot" style="--c:${esc(pol.color || 'var(--line-strong)')}" aria-hidden="true"></i><span class="p">${esc(pol.name)} ·</span><b>${esc(it.text)}</b><span class="y">${esc(yearText(it.y))}–</span>${tail}</li>`;
        })
        .join('');
      const box = fillDlg.querySelector('[data-fill-problems]');
      const show = (fill.tried ? p.problems : []).concat(fill.failed ? [{ text: fill.failed }] : []);
      box.hidden = !show.length;
      box.innerHTML = show.map(x => `<li>${esc(x.text)}</li>`).join('');
      for (const el of fillDlg.querySelectorAll('[data-ask]')) el.toggleAttribute('aria-invalid', fill.tried && p.problems.some(x => x.ask === el.dataset.ask));
    }
    async function submitFill() {
      if (!fill) return;
      fill.tried = true;
      renderFill();
      const p = fill.plan;
      if (p.problems.length) {
        const bad = p.problems.find(x => x.ask);
        const el = bad && fillDlg.querySelector(`[data-ask="${CSS.escape(bad.ask)}"]`);
        if (el) el.focus();
        return;
      }
      const t = fill.t;
      const openAfter = fillDlg.querySelector('[data-open-after]').checked;
      if (store.openAfter !== openAfter) {
        store.openAfter = openAfter;
        saveStore();
      }
      const uid = p.polity.uid;
      const e = env();
      let made = 0;
      let err = '';
      /* 창은 만든 뒤에 닫음 — 편집 창의 저장하지 않은 고침을 묻는 창(그 위에 뜸)에서 그만두거나 만들지 못하면 적은 칸을 그대로 두고 까닭을 창 안에(알림은 창 뒤에 가려짐) */
      const ok = await api.transact(draft => {
        try {
          made = applyPlan(draft, p, e);
        } catch (x) {
          err = (x && x.message) || String(x);
          throw x;
        }
        return draft;
      }, `틀 «${t.name}» — ${p.n}개 만듦`);
      if (!ok) {
        if (fill && fillDlg.open) {
          fill.failed = err || '만들지 못했습니다 — 편집 창의 물음에서 그만두었거나 다른 고침이 먼저 저장되었습니다. 다시 누르세요.';
          fill.raws.clear(); // 묻는 창에서 편집 창의 고침을 저장했을 수도 — 미리 글은 새 원본으로
          renderFill();
        }
        return;
      }
      if (fillDlg.open) fillDlg.close();
      HT.toast(`틀 «${t.name}»(으)로 ${made}개를 만들었습니다 — 되돌리기 한 번에 돌아옵니다.`, 'ok');
      if (openAfter && state.model.byUid.has(uid)) await ctx.openEditorFor(uid);
    }

    /* ---------- 틀 관리 창 ---------- */
    let man = null; // { dlg, work: [틀 사본], cur, dirty, askEdit(묻는 칸 자리 · -1), addOpen, msg, problems }
    const curT = () => (man && man.work[man.cur]) || null;
    const mark = () => {
      man.dirty = true;
      man.msg = '';
    };
    function buildMan() {
      const dlg = document.body.appendChild(Object.assign(document.createElement('dialog'), { className: 'mk-tpl is-wide', id: 'mkTplMan' }));
      dlg.setAttribute('aria-labelledby', 'mkTplManTitle');
      man = { dlg, work: [], cur: 0, dirty: false, askEdit: -1, addOpen: false, msg: '', problems: [] };
      dlg.innerHTML = `<div class="dlg">
        <div class="dlg-head"><h2 id="mkTplManTitle">틀 관리</h2><button type="button" class="icon-btn" data-man-close aria-label="닫기">✕</button></div>
        <div class="dlg-body"><p class="lead">틀은 이 작업실의 설정입니다 — DLC 파일에는 들어가지 않습니다. 목록의 차례대로 '＋ 더' · 명령 찾기 · '/' 상자에 보입니다.</p>
          <ul class="problems" data-man-problems hidden></ul>
          <div class="mk-tm"><div class="mk-tm-list" role="listbox" aria-label="틀 목록 — Alt+↑↓로 차례를 바꿉니다"></div><div class="mk-tm-edit"></div></div></div>
        <div class="dlg-foot"><button type="button" class="btn btn-danger" data-tm-del>이 틀 지우기</button><span class="spacer"></span><span class="mk-tm-msg" role="status" data-man-msg></span><button type="button" class="btn" data-man-close>닫기</button><button type="button" class="btn btn-primary" data-tm-save>저장</button></div>
      </div>`;
      dlg.addEventListener('cancel', e => {
        e.preventDefault(); // Esc — 저장하지 않은 고침이 있으면 묻고 닫음
        closeMan();
      });
      dlg.addEventListener('click', onManClick);
      dlg.addEventListener('input', onManInput);
      dlg.addEventListener('change', onManChange);
      dlg.addEventListener('keydown', onManKey);
    }
    function openManager(opts = {}) {
      reload();
      if (!man) buildMan();
      man.work = clone(store.list);
      man.cur = 0;
      man.dirty = false;
      man.askEdit = -1;
      man.addOpen = false;
      man.msg = '';
      man.problems = [];
      if (opts.add) {
        man.work.push(opts.add);
        man.cur = man.work.length - 1;
        man.dirty = true;
        man.msg = '고른 줄들로 채운 새 틀입니다 — 이름을 정하고 저장하세요.';
      } else if (opts.id) man.cur = Math.max(0, man.work.findIndex(t => t.id === opts.id));
      renderMan();
      if (!man.dlg.open) man.dlg.showModal();
      const nm = man.dlg.querySelector('[data-tm-name]');
      if (nm && opts.add) {
        nm.focus();
        nm.select();
      } else (man.dlg.querySelector('.mk-tm-item.is-on') || man.dlg.querySelector('[data-tm-new]')).focus();
      return true;
    }
    function askChip(a, i) {
      if (a.type === 'polity') return `<span class="mk-tm-ask is-fixed" title="나라는 늘 묻습니다 — 만드는 줄은 모두 이 나라에, 사건은 이 나라의 트랙에">${esc(a.label)}</span>`;
      return `<button type="button" class="mk-tm-ask${man.askEdit === i ? ' is-on' : ''}" data-ask-i="${i}" aria-expanded="${man.askEdit === i}">${esc(a.label)}${a.type === 'year' && !/해$/.test(a.label) ? '<small>해</small>' : ''}${a.optional ? '<small>비워도 됨</small>' : ''}</button>`; // 해 칸은 이름이 '…해'가 아니면 '해' 딱지
    }
    function askEditHTML(t) {
      const a = t.asks[man.askEdit];
      if (!a) return '';
      return `<div class="mk-tm-askedit"><label class="field"><span>칸 이름</span><input data-ae-label value="${esc(a.label)}" maxlength="${LIMITS.label}" autocomplete="off" spellcheck="false"></label>
        <label class="field"><span>종류</span><select data-ae-type><option value="text"${a.type === 'text' ? ' selected' : ''}>글</option><option value="year"${a.type === 'year' ? ' selected' : ''}>해(연도 · 날짜)</option></select></label>
        <label class="check"${a.type === 'year' ? ' hidden' : ''}><input type="checkbox" data-ae-opt${a.optional ? ' checked' : ''}> 비워도 됨 — 비우면 이 칸을 쓰는 것은 건너뜀</label>
        <span class="spacer"></span><button type="button" class="btn btn-sm" data-ae-del>이 칸 빼기</button><button type="button" class="btn btn-sm" data-ae-done>닫기</button></div>`;
    }
    function makeHTML(t, m, i) {
      const K = KINDS[m.kind];
      const years = t.asks.filter(a => a.type === 'year');
      const start = `<label class="mk-tm-f"><span>${m.kind === 'event' ? '해' : '시작'}</span><select data-mk-start>${years.map(a => `<option value="${esc(a.id)}"${a.id === m.start ? ' selected' : ''}>${esc(a.label)}</option>`).join('')}</select></label>`;
      const cats = arr(state.model && state.model.categories);
      const extra =
        m.kind === 'event'
          ? `<label class="mk-tm-f"><span>분류</span><select data-mk-cat><option value="">기타</option>${cats.map(c => `<option value="${esc(c.id)}"${c.id === m.category ? ' selected' : ''}>${esc(c.name)}</option>`).join('')}</select></label><span class="mk-tm-note">나라 = 묻는 칸 «나라»(사건은 그 나라의 트랙에)</span>`
          : m.kind === 'capitals'
            ? `<label class="mk-tm-f"><span>역할</span><select data-mk-role>${(HT.CAPITAL_ROLES || []).map(r => `<option value="${r.id}"${r.id === (m.role || 'main') ? ' selected' : ''}>${esc(r.name)}</option>`).join('')}</select></label>`
            : K.prev
              ? `<label class="check"><input type="checkbox" data-mk-link${m.link ? ' checked' : ''}> ${esc(K.prev)}의 끝도 이 해로 이음</label>`
              : '';
      const ins = t.asks.map(a => `<button type="button" data-ins="${esc(a.label)}" title="{${esc(a.label)}} 넣기 — 만들 때 그 칸에 적은 값으로 바뀝니다">${esc(a.label)}</button>`).join('');
      return `<div class="mk-tm-make" data-make-i="${i}">
        <div class="mk-tm-mrow"><span class="k">${esc(K.word)}</span><label class="mk-tm-f is-main"><span>${esc(K.mainWord)}</span><input data-mk-text value="${esc(m.text)}" maxlength="${LIMITS.text}" autocomplete="off" spellcheck="false" aria-label="${esc(`${K.word}의 ${K.mainWord} — {칸 이름}은 만들 때 그 칸의 값으로 바뀝니다`)}"></label>${start}
          <span class="mk-tm-acts"><button type="button" class="icon-btn" data-mk-up aria-label="위로"${i ? '' : ' disabled'}>↑</button><button type="button" class="icon-btn" data-mk-down aria-label="아래로"${i < t.makes.length - 1 ? '' : ' disabled'}>↓</button><button type="button" class="icon-btn" data-mk-del aria-label="이 만들 것 빼기">✕</button></span></div>
        <div class="mk-tm-mrow is-sub">${extra}<span class="mk-tm-ins"><span>칸 넣기</span>${ins}</span></div>
      </div>`;
    }
    function renderMan() {
      const t = curT();
      const dlg = man.dlg;
      const missing = DEFAULTS.filter(d => !man.work.some(w => w.id === d.id));
      dlg.querySelector('.mk-tm-list').innerHTML =
        man.work.map((w, i) => `<button type="button" class="mk-tm-item${i === man.cur ? ' is-on' : ''}" data-tm-i="${i}" role="option" aria-selected="${i === man.cur}" title="Alt+↑↓로 차례를 바꿉니다"><span>${esc(w.name || '이름 없음')}</span><small>${w.id.startsWith('b-') ? '기본' : '내 틀'}</small></button>`).join('') +
        `<button type="button" class="btn btn-sm" data-tm-new>＋ 새 틀</button>${missing.length ? `<button type="button" class="btn btn-sm" data-tm-restore title="${esc(missing.map(d => d.name).join(' · '))}">기본 틀 되살리기 ${missing.length}</button>` : ''}`;
      dlg.querySelector('.mk-tm-edit').innerHTML = !t
        ? '<p class="hint">틀이 없습니다 — ＋ 새 틀로 만드세요.</p>'
        : `<label class="field mk-tm-name"><span>틀 이름</span><input data-tm-name value="${esc(t.name)}" maxlength="${LIMITS.name}" autocomplete="off" spellcheck="false"></label>
          <h5>묻는 칸 <small>(만들 때 한 번만 적음 · 누르면 고침)</small></h5>
          <div class="mk-tm-asks">${t.asks.map(askChip).join('')}<button type="button" class="btn btn-sm" data-ask-add${t.asks.length >= LIMITS.asks ? ' disabled' : ''}>＋ 칸</button></div>
          ${askEditHTML(t)}
          <h5>만드는 것 <small>(이 차례대로 · {칸 이름}은 그 칸의 값으로)</small></h5>
          <div class="mk-tm-makes">${t.makes.map((m, i) => makeHTML(t, m, i)).join('') || '<p class="hint">아직 없습니다.</p>'}</div>
          <button type="button" class="btn btn-sm" data-mk-add aria-expanded="${man.addOpen}"${t.makes.length >= LIMITS.makes ? ' disabled' : ''}>＋ 만들 것 더하기</button>
          ${man.addOpen ? `<div class="mk-tm-kinds">${KIND_ORDER.map(k => `<button type="button" class="btn btn-sm" data-mk-kind="${k}">＋ ${esc(KINDS[k].word)}</button>`).join('')}</div>` : ''}
          <p class="note">편집 창에서 줄 여럿을 고르고(Shift+손잡이 ⋮⋮) 블록 메뉴의 '틀로 저장…'을 눌러도 이 창이 그 줄들로 채워져 열립니다.</p>`;
      const pb = dlg.querySelector('[data-man-problems]');
      pb.hidden = !man.problems.length;
      pb.innerHTML = man.problems.map(x => `<li>${esc(x.text)}</li>`).join('');
      dlg.querySelector('[data-man-msg]').textContent = man.msg || (man.dirty ? '저장하지 않은 고침이 있습니다' : '');
      dlg.querySelector('[data-tm-del]').disabled = !t;
    }
    const focusIn = sel => {
      const el = man.dlg.querySelector(sel);
      if (el) el.focus();
      return el;
    };
    /** 묻는 칸 이름을 바꾸면 만드는 것의 {옛 이름}도 함께 */
    function renameAsk(t, a, label) {
      const l = cleanLabel(label);
      if (!l) return '칸 이름을 적으세요.';
      if (t.asks.some(x => x !== a && x.label === l)) return `«${l}» 칸이 이미 있습니다.`;
      if (l === a.label) return '';
      for (const m of t.makes) m.text = m.text.split(`{${a.label}}`).join(`{${l}}`);
      a.label = l;
      return '';
    }
    function removeAsk(t, i) {
      const a = t.asks[i];
      if (!a || a.type === 'polity') return '';
      const otherYear = t.asks.find(x => x !== a && x.type === 'year');
      if (a.type === 'year' && !otherYear) return '해 칸이 하나는 있어야 합니다 — 다른 해 칸을 먼저 더하세요.';
      for (const m of t.makes) {
        m.text = m.text.split(`{${a.label}}`).join('').replace(/\s+/g, ' ').trim();
        if (m.start === a.id) m.start = otherYear.id;
      }
      t.asks.splice(i, 1);
      return '';
    }
    function onManClick(e) {
      const b = e.target.closest('button');
      if (!b || b.disabled) return;
      const t = curT();
      if (b.matches('[data-man-close]')) return closeMan();
      if (b.matches('[data-tm-save]')) return saveMan();
      if (b.dataset.tmI != null) {
        man.cur = Number(b.dataset.tmI);
        man.askEdit = -1;
        man.addOpen = false;
        renderMan();
        return focusIn(`[data-tm-i="${man.cur}"]`);
      }
      if (b.matches('[data-tm-new]')) {
        const names = man.work.map(w => w.name);
        let name = '새 틀';
        for (let n = 2; names.includes(name); n++) name = `새 틀 ${n}`;
        man.work.push(cleanTemplate({ id: newId('t-', new Set(man.work.map(w => w.id))), name, asks: [POLITY, { id: 'year', label: '해', type: 'year' }], makes: [] }));
        man.cur = man.work.length - 1;
        man.askEdit = -1;
        man.addOpen = true;
        mark();
        renderMan();
        const nm = focusIn('[data-tm-name]');
        if (nm) nm.select();
        return;
      }
      if (b.matches('[data-tm-restore]')) {
        for (const d of DEFAULTS) if (!man.work.some(w => w.id === d.id)) man.work.push(cleanTemplate(clone(d)));
        mark();
        renderMan();
        return focusIn('[data-tm-new]');
      }
      if (b.matches('[data-tm-del]') && t) {
        man.work.splice(man.cur, 1);
        man.cur = Math.max(0, Math.min(man.cur, man.work.length - 1));
        man.askEdit = -1;
        mark();
        man.msg = `틀 «${t.name}»을(를) 뺐습니다 — 저장하면 지워집니다.`;
        renderMan();
        return focusIn('.mk-tm-item.is-on') || focusIn('[data-tm-new]');
      }
      if (!t) return;
      if (b.dataset.askI != null) {
        const i = Number(b.dataset.askI);
        man.askEdit = man.askEdit === i ? -1 : i;
        renderMan();
        return man.askEdit >= 0 ? focusIn('[data-ae-label]') : focusIn(`[data-ask-i="${i}"]`);
      }
      if (b.matches('[data-ask-add]')) {
        let label = '새 칸';
        for (let n = 2; t.asks.some(a => a.label === label); n++) label = `새 칸 ${n}`;
        let id = 'a';
        for (let n = 2; t.asks.some(a => a.id === id); n++) id = `a${n}`;
        t.asks.push({ id, label, type: 'text' });
        man.askEdit = t.asks.length - 1;
        mark();
        renderMan();
        const el = focusIn('[data-ae-label]');
        if (el) el.select();
        return;
      }
      if (b.matches('[data-ae-done]')) {
        const i = man.askEdit;
        man.askEdit = -1;
        renderMan();
        return focusIn(`[data-ask-i="${i}"]`);
      }
      if (b.matches('[data-ae-del]')) {
        const why = removeAsk(t, man.askEdit);
        if (why) man.msg = why;
        else {
          man.askEdit = -1;
          mark();
        }
        renderMan();
        return focusIn('[data-ask-add]');
      }
      const row = b.closest('[data-make-i]');
      const i = row ? Number(row.dataset.makeI) : -1;
      if (b.dataset.ins != null && row) {
        const input = row.querySelector('[data-mk-text]');
        const tok = `{${b.dataset.ins}}`;
        const s = input.selectionStart ?? input.value.length;
        const end = input.selectionEnd ?? s;
        input.value = input.value.slice(0, s) + tok + input.value.slice(end);
        input.focus();
        input.setSelectionRange(s + tok.length, s + tok.length);
        t.makes[i].text = input.value;
        mark();
        man.dlg.querySelector('[data-man-msg]').textContent = '저장하지 않은 고침이 있습니다';
        return;
      }
      if (b.matches('[data-mk-up], [data-mk-down]') && row) {
        const j = i + (b.matches('[data-mk-up]') ? -1 : 1);
        [t.makes[i], t.makes[j]] = [t.makes[j], t.makes[i]];
        mark();
        renderMan();
        return focusIn(`[data-make-i="${j}"] ${b.matches('[data-mk-up]') ? '[data-mk-up]' : '[data-mk-down]'}:not([disabled])`) || focusIn(`[data-make-i="${j}"] [data-mk-text]`);
      }
      if (b.matches('[data-mk-del]') && row) {
        t.makes.splice(i, 1);
        mark();
        renderMan();
        return focusIn(`[data-make-i="${Math.min(i, t.makes.length - 1)}"] [data-mk-text]`) || focusIn('[data-mk-add]');
      }
      if (b.matches('[data-mk-add]')) {
        man.addOpen = !man.addOpen;
        renderMan();
        return focusIn(man.addOpen ? '[data-mk-kind]' : '[data-mk-add]');
      }
      if (b.dataset.mkKind) {
        const kind = b.dataset.mkKind;
        const year = t.asks.find(a => a.type === 'year');
        const m = { kind, text: '', start: year.id };
        if (KINDS[kind].prev) m.link = true;
        if (kind === 'capitals') m.role = 'main';
        if (kind === 'event') m.category = 'politics';
        t.makes.push(m);
        man.addOpen = false;
        mark();
        renderMan();
        return focusIn(`[data-make-i="${t.makes.length - 1}"] [data-mk-text]`);
      }
    }
    function onManInput(e) {
      const t = curT();
      if (!t) return;
      const el = e.target;
      if (el.matches('[data-tm-name]')) {
        t.name = el.value.slice(0, LIMITS.name);
        const item = man.dlg.querySelector(`[data-tm-i="${man.cur}"] span`);
        if (item) item.textContent = str(t.name) || '이름 없음';
      } else if (el.matches('[data-mk-text]')) {
        t.makes[Number(el.closest('[data-make-i]').dataset.makeI)].text = el.value;
      } else return;
      mark();
      man.dlg.querySelector('[data-man-msg]').textContent = '저장하지 않은 고침이 있습니다';
    }
    function onManChange(e) {
      const t = curT();
      if (!t) return;
      const el = e.target;
      const row = el.closest('[data-make-i]');
      const m = row ? t.makes[Number(row.dataset.makeI)] : null;
      if (el.matches('[data-ae-label]')) {
        const a = t.asks[man.askEdit];
        const why = a ? renameAsk(t, a, el.value) : '';
        man.msg = why;
        if (!why) mark();
        renderMan();
        return focusIn('[data-ae-label]');
      }
      if (el.matches('[data-ae-type]')) {
        const a = t.asks[man.askEdit];
        if (!a) return;
        if (el.value === 'text' && a.type === 'year') {
          const other = t.asks.find(x => x !== a && x.type === 'year');
          if (!other) {
            man.msg = '해 칸이 하나는 있어야 합니다.';
            renderMan();
            return focusIn('[data-ae-type]');
          }
          for (const mk of t.makes) if (mk.start === a.id) mk.start = other.id;
        }
        a.type = el.value === 'year' ? 'year' : 'text';
        if (a.type === 'year') delete a.optional;
        mark();
        renderMan();
        return focusIn('[data-ae-type]');
      }
      if (el.matches('[data-ae-opt]')) {
        const a = t.asks[man.askEdit];
        if (!a) return;
        if (el.checked) a.optional = true;
        else delete a.optional;
        mark();
        renderMan();
        return focusIn('[data-ae-opt]');
      }
      if (!m) return;
      if (el.matches('[data-mk-start]')) m.start = el.value;
      else if (el.matches('[data-mk-link]')) {
        if (el.checked) m.link = true;
        else delete m.link;
      } else if (el.matches('[data-mk-role]')) m.role = el.value;
      else if (el.matches('[data-mk-cat]')) {
        if (el.value) m.category = el.value;
        else delete m.category;
      } else return;
      mark();
      man.dlg.querySelector('[data-man-msg]').textContent = '저장하지 않은 고침이 있습니다';
    }
    function onManKey(e) {
      const item = e.target.closest && e.target.closest('[data-tm-i]');
      if (!item || !e.altKey || (e.key !== 'ArrowUp' && e.key !== 'ArrowDown')) return;
      e.preventDefault();
      const i = Number(item.dataset.tmI);
      const j = i + (e.key === 'ArrowUp' ? -1 : 1);
      if (j < 0 || j >= man.work.length) return;
      [man.work[i], man.work[j]] = [man.work[j], man.work[i]];
      man.cur = j;
      mark();
      renderMan();
      focusIn(`[data-tm-i="${j}"]`);
    }
    function saveMan() {
      const list = man.work.map(t => Object.assign({}, t, { name: str(t.name) }));
      const problems = validate(list);
      man.problems = problems;
      if (problems.length) {
        man.cur = problems[0].i;
        man.msg = '고칠 것이 있어 저장하지 않았습니다';
        renderMan();
        return false;
      }
      store.list = list.map(cleanTemplate).filter(Boolean);
      saveStore();
      man.work = clone(store.list);
      man.dirty = false;
      man.msg = '저장했습니다';
      renderMan();
      return true;
    }
    async function closeMan() {
      if (man.dirty) {
        const a = await api.ask('저장하지 않은 틀 고침이 있습니다.', { title: '틀 관리', yes: '저장하고 닫기', no: '버리고 닫기' });
        if (a === 'cancel') return;
        if (a === 'yes' && !saveMan()) return;
      }
      man.dirty = false;
      man.dlg.close();
    }

    /* ---------- 블록 메뉴 '틀로 저장…' · '/' 목록 (js/maker-blocks.js의 덧붙임 자리) ---------- */
    function saveRows(rows, kinds) {
      const read = rows.map((r, i) => ({ kind: kinds[i], item: HT.makerBlocks.readRow(r, kinds[i]).item })).filter(x => x.item);
      reload();
      const t = fromRows(read, store.list.map(x => x.name));
      if (!t) return HT.toast('틀로 저장할 줄이 없습니다 — 지도자 · 내각 · 연호 · 도읍 · 지위 줄을 고르세요.', 'error');
      return openManager({ add: t });
    }
    if (HT.makerBlocks && HT.makerBlocks.extras) {
      HT.makerBlocks.extras.menu.push(({ rows }) => {
        const kinds = arr(rows).map(r => (r.parentElement && r.parentElement.dataset.cells) || '');
        if (!kinds.length || !kinds.every(k => KINDS[k] && k !== 'event')) return [];
        return [{ label: '틀로 저장…', run: () => saveRows(rows, kinds) }];
      });
      HT.makerBlocks.extras.slash.push(() => {
        reload();
        return store.list
          .map(t => ({ group: '틀', label: t.name, find: '틀', sub: summaryOf(t), run: () => openFill(t.id, { polity: state.editing }) })) // '틀' 무리 제목 아래 틀 이름만(판 d5-a) — '/틀'로도 걸러짐
          .concat({ group: '틀', label: '틀 관리…', sub: '틀 만들기 · 고치기', run: () => openManager() });
      });
    }

    /* ---------- 메뉴 줄 · '＋ 더' · 명령 찾기에 붙일 줄 (js/maker-shell.js가 부름) ---------- */
    function menuItems() {
      reload();
      const has = !!api.draft;
      return [{ sep: true }, { title: '틀로 만들기' }, ...store.list.map(t => ({ label: `${t.name} — ${summaryOf(t)}`, disabled: !has, run: has ? () => openFill(t.id) : null })), { label: '틀 관리…', run: () => openManager() }];
    }
    function commands() {
      reload();
      return store.list.map(t => ({ label: `틀로 만들기: ${t.name} — ${summaryOf(t)}`, key: '틀', run: () => (api.draft ? openFill(t.id) : HT.toast('고칠 DLC가 없습니다.', 'error')) })).concat({ label: '틀 관리…', key: '틀', run: () => openManager() });
    }
    return { list: () => (reload(), store.list), openFill, openManager, menuItems, commands };
  }

  HT.makerTemplates = { KEY, KINDS, DEFAULTS, LIMITS, josa, cleanTemplate, readStore, summaryOf, fillText, readYear, plan, applyPlan, fromRows, validate, mount };
})();

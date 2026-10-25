/* 역사 연표 — DLC 메이커 작업실 틀 (dlc-maker.html에서만 읽힘 — js/maker.js 다음, js/viewer.js 앞)
   docs/구상-메이커-팩.md 3절: 메뉴 줄 · 도구 줄 · 왼쪽(구조 · 불러온 팩) · 가운데 탭 · 오른쪽 속성 · 아래 창 · 상태 줄 · 처음 화면.
   앞부분(HT.makerShell의 표 · 계산)은 화면 없이 돌아 dev-smoke가 노드에서 검사하고, 뒷부분 mount(ctx, api)가 화면을 붙입니다 — js/maker.js의 start가 부름 */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const arr = v => (Array.isArray(v) ? v : []);
  const str = v => (typeof v === 'string' ? v.trim() : '');

  /* ================= 순수 부품 ================= */
  const UI_KEY = 'ht.maker.ui';
  const MENUS = [['file', '파일'], ['edit', '편집'], ['view', '보기'], ['insert', '넣기'], ['tools', '도구'], ['help', '도움말']];
  /** 명령 표 — 메뉴 줄 · 도구 줄 · 단축키가 이 한 표를 봅니다(6단계의 명령 찾기도). key: 보여 줄 단축키 ·
      by: 'viewer'면 그 키는 js/viewer.js가 이미 받음(틀은 받지 않음 — 두 번 돌지 않게) · soon: 그 단계에서 만듦(흐리게) · sep: 구분선 */
  const COMMANDS = [
    { id: 'start', menu: 'file', label: '처음 화면' },
    { id: 'new', menu: 'file', label: '새 DLC…' },
    { id: 'open', menu: 'file', label: '열기 (.htpack)…', key: 'Ctrl+O' },
    { id: 'edit-installed', menu: 'file', label: '설치된 DLC에서 고치기…' },
    { sep: true, menu: 'file' },
    { id: 'reflect', menu: 'file', label: '반영', key: 'Ctrl+E', by: 'viewer' },
    { id: 'export', menu: 'file', label: '팩 파일로 내보내기 (.htpack)', key: 'Ctrl+Shift+E' },
    { id: 'export-legacy', menu: 'file', label: '옛 형식(3)으로 내보내기 (.htpack)' },
    { id: 'image', menu: 'file', label: '그림으로 내보내기 · 인쇄', key: 'P', by: 'viewer' },
    { sep: true, menu: 'file' },
    { id: 'to-timeline', menu: 'file', label: '연표로 ↗' },
    { id: 'undo', menu: 'edit', label: '되돌리기', key: 'Ctrl+Z' },
    { id: 'redo', menu: 'edit', label: '다시 하기', key: 'Ctrl+Y' },
    { sep: true, menu: 'edit' },
    { id: 'cut', menu: 'edit', label: '잘라내기', key: 'Ctrl+X' },
    { id: 'copy', menu: 'edit', label: '복사', key: 'Ctrl+C' },
    { id: 'paste', menu: 'edit', label: '붙여넣기', key: 'Ctrl+V' },
    { id: 'duplicate', menu: 'edit', label: '복제', key: 'Ctrl+D' },
    { id: 'delete', menu: 'edit', label: '지우기', key: 'Delete' },
    { id: 'select-all', menu: 'edit', label: '모두 고르기', key: 'Ctrl+A' },
    { sep: true, menu: 'edit' },
    { id: 'bulk', menu: 'edit', label: '한꺼번에 고치기…' },
    { id: 'replace', menu: 'edit', label: '찾아 바꾸기', key: 'Ctrl+H' },
    { id: 'rename', menu: 'edit', label: '이름 바꾸기', key: 'F2' },
    { id: 'move-to', menu: 'edit', label: '옮기기… (구조 나무의 갈 곳 고르기)' },
    { id: 'tab-timeline', menu: 'view', label: '연표', key: 'Ctrl+1' },
    { id: 'tab-table', menu: 'view', label: '표', key: 'Ctrl+2' },
    { id: 'tab-wiki', menu: 'view', label: '문서', key: 'Ctrl+3' },
    { sep: true, menu: 'view' },
    { id: 'toggle-left', menu: 'view', label: '왼쪽 창', key: 'Ctrl+B' },
    { id: 'toggle-right', menu: 'view', label: '오른쪽 창', key: 'Ctrl+Alt+B' },
    { id: 'toggle-bottom', menu: 'view', label: '아래 창', key: 'Ctrl+J' },
    { sep: true, menu: 'view' },
    { id: 'filter', menu: 'view', label: '필터 · 표시 설정', key: 'F', by: 'viewer' },
    { id: 'legend', menu: 'view', label: '범례', key: 'L', by: 'viewer' },
    { id: 'zen', menu: 'view', label: '집중 모드', key: 'Z', by: 'viewer' },
    { id: 'fit', menu: 'view', label: '전체 보기', key: '0', by: 'viewer' },
    { sep: true, menu: 'view' },
    { id: 'kin-succ', menu: 'view', label: '승계표' }, // 고른 나라 — 없으면 고르기 메뉴 (js/viewer.js openKin · kinPick)
    { id: 'kin-fam', menu: 'view', label: '세계표' }, // 고른 나라 · 가문 · 인물 — 창 안에서 사람 더하기 (js/maker-kin.js addRelative)
    { sep: true, menu: 'view' },
    { id: 'dim-light', menu: 'view', label: '불러온 팩 흐리기: 옅게' },
    { id: 'dim-mid', menu: 'view', label: '불러온 팩 흐리기: 보통' },
    { id: 'dim-strong', menu: 'view', label: '불러온 팩 흐리기: 진하게' },
    /* 넣기: 항목 종류(연표의 추가 종류 — viewer가 ctx.cmd로 넘김)는 화면에서 이 앞에 붙습니다 */
    { id: 'base:epochs', menu: 'insert', label: '시대 구분' },
    { id: 'base:tracks', menu: 'insert', label: '트랙' },
    { id: 'base:spheres', menu: 'insert', label: '문화권' },
    { id: 'base:yearCycles', menu: 'insert', label: '주기' }, // 문화권별 주기 줄 — 바탕 창의 표(편집 표에는 없음 · 5단계 과제 6)
    { id: 'base:categories', menu: 'insert', label: '분류' },
    { id: 'base:peoples', menu: 'insert', label: '민족' },
    { id: 'base:rankDefs', menu: 'insert', label: '지위' },
    { id: 'base:houses', menu: 'insert', label: '가문' },
    { sep: true, menu: 'insert' },
    { id: 'paste-table', menu: 'insert', label: '표 붙여넣기…' },
    { id: 'paste-whole', menu: 'insert', label: '나라 통째 붙여넣기…' }, // 칸 채우기 답 하나로 시대 편집 창의 모든 칸 (js/maker-paste.js openWhole)
    { id: 'kin-outline', menu: 'insert', label: '계층 입력 (족보)…' }, // 한 줄 = 한 사람 · 들여쓰기 = 세대 — 고른 인물이 뿌리 (js/maker-kin.js · D1 확정 설계 7-2 ⑤)
    { id: 'check', menu: 'tools', label: '검사 — 문제 창' },
    { id: 'changes', menu: 'tools', label: '고친 것 · 덮어쓰기 목록' },
    { id: 'blanks', menu: 'tools', label: '빈 칸 점검' },
    { id: 'history', menu: 'tools', label: '작업 기록' },
    { id: 'autosave', menu: 'tools', label: '자동 저장 기록…' },
    { sep: true, menu: 'tools' },
    { id: 'year', menu: 'tools', label: '같은 해 보기', key: 'Y', by: 'viewer' },
    { id: 'measure', menu: 'tools', label: '기간 재기', key: 'R', by: 'viewer' },
    { sep: true, menu: 'tools' },
    { id: 'find', menu: 'tools', label: '명령·항목 찾기', key: 'Ctrl+K' },
    { id: 'keys', menu: 'help', label: '단축키', key: '?' },
    { id: 'guide', menu: 'help', label: '메이커 안내' },
  ];
  const LIMITS = { left: { min: 200, max: 480, def: 280 }, right: { min: 320, def: 380 }, bottom: { min: 120, def: 220 } };

  /** 키 이름: 'Ctrl+Shift+E' 꼴 — metaKey도 Ctrl. 글자 · 숫자는 e.code로 읽어 한글 자판 · 조합 중에도 같은 이름('ㅠ' → B).
      '?' · '+'처럼 Shift로 나오는 기호는 Shift를 붙이지 않음. 수식 키만 누르면 '' */
  function keyName(e) {
    const k = e.key || '';
    if (!k || ['Control', 'Shift', 'Alt', 'Meta'].includes(k)) return '';
    const m = /^(?:Key([A-Z])|Digit([0-9]))$/.exec(e.code || '');
    const base = m ? m[1] || m[2] : k === ' ' ? 'Space' : k.length === 1 ? k.toUpperCase() : k;
    const symbol = !m && k.length === 1 && !/[A-Za-z0-9]/.test(k);
    return [(e.ctrlKey || e.metaKey) && 'Ctrl', e.altKey && 'Alt', e.shiftKey && !symbol && 'Shift', base].filter(Boolean).join('+');
  }

  /** 작업실 배치 기억(ht.maker.ui) 읽기 — 모르는 값 · 한도 밖은 기본값 · 한도로. 오른쪽 · 아래의 최대(화면의 60%)는 그릴 때 */
  function readUi(raw) {
    const o = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    const part = k => (o[k] && typeof o[k] === 'object' && !Array.isArray(o[k]) ? o[k] : {});
    const num = (v, min, max, def) => (typeof v === 'number' && isFinite(v) ? Math.round(Math.min(max, Math.max(min, v))) : def);
    const pick = (v, list, def) => (list.includes(v) ? v : def);
    const L = part('left');
    const R = part('right');
    const B = part('bottom');
    return {
      left: { open: L.open !== false, w: num(L.w, LIMITS.left.min, LIMITS.left.max, LIMITS.left.def), tab: pick(L.tab, ['tree', 'packs'], 'tree') },
      right: { open: R.open !== false, w: num(R.w, LIMITS.right.min, 4000, LIMITS.right.def), wide: R.wide === true },
      bottom: { open: B.open === true, h: num(B.h, LIMITS.bottom.min, 4000, LIMITS.bottom.def), tab: pick(B.tab, ['problems', 'changes', 'history', 'autosave', 'replace', 'blanks'], 'problems') },
      center: pick(o.center, ['timeline', 'table'], 'timeline'), // 문서 탭은 열 문서가 있어야 하므로 기억하지 않음
      grid: JSON.parse(JSON.stringify(part('grid'))),
      findHidden: arr(o.findHidden).filter(x => typeof x === 'string'),
      dim: pick(o.dim, ['light', 'mid', 'strong'], 'mid'),
      tree: Object.fromEntries(Object.entries(part('tree')).filter(([, v]) => typeof v === 'boolean')),
    };
  }

  /* ---------- 구조 나무 (설계 3-4) ---------- */
  const yearOf = v => (typeof v === 'number' && isFinite(v) ? HT.formatAxisYear(v) : typeof v === 'string' ? v.trim().slice(0, 12) : '');
  const byStart = (a, b) => a.t - b.t || a.name.localeCompare(b.name, 'ko');
  /** 구조 탭의 나무: 작업본(draft — 파일 그대로)의 부분을 묶음으로. model(있으면)에서 색 · 해를 읽고, bad(항목 id 모음)는 붉은 점.
      묶음 { key, label, n, kids? | rows? | base? } · 줄 { uid | doc | cover, name, years, color, bad, kind(폼 종류 · 'patch' · 'doc' · 'cover'), t(차례용 시작 해) } */
  function treeOf(draft, { model = null, bad = new Set(), fig = 'all' } = {}) {
    if (!draft) return [];
    const id = draft.id;
    const byUid = model && model.byUid ? model.byUid : new Map();
    const row = (x, kind) => {
      const m = byUid.get(`${id}/${x.id}`);
      const s = m && isFinite(m.start) ? m.start : x.start;
      const e = m ? (m.ongoing ? null : isFinite(m.endY) ? m.endY : m.end) : x.end;
      const a = yearOf(s);
      const b = yearOf(e);
      return { uid: `${id}/${x.id}`, name: str(x.name) || str(x.title) || str(x.epoch) || x.id, years: a && b && b !== a ? `${a}–${b}` : a, color: (m && m.color) || str(x.color), bad: bad.has(x.id), kind, t: typeof s === 'number' && isFinite(s) ? s : Infinity };
    };
    const items = list => arr(draft[list]).filter(x => x && typeof x === 'object' && x.id);
    const rowsOf = (list, kind) => items(list).map(x => row(x, kind)).sort(byStart);
    const n = list => items(list).length;
    const trackName = t => str((arr(draft.tracks).find(o => o && o.id === t) || {}).name) || t || '트랙 없음';
    const byTrack = (list, kind, head, label) => {
      const groups = new Map();
      for (const x of items(list)) {
        const t = str(x.track);
        if (!groups.has(t)) groups.set(t, []);
        groups.get(t).push(row(x, kind));
      }
      return [...groups].map(([t, rows]) => ({ key: `${head}:${t}`, label: label(trackName(t)), n: rows.length, rows: rows.sort(byStart) }));
    };
    const more = rowsOf('dynasties', 'dynasty').concat(rowsOf('organs', 'organ'), rowsOf('cultures', 'culture'));
    const patches = arr(draft.patches)
      .filter(p => p && typeof p.target === 'string' && p.target)
      .map(p => {
        const m = byUid.get(p.target);
        return { uid: p.target, name: m ? m.title || m.name : p.target, years: p.hide ? '숨김' : `고침 ${Object.keys(p.set || {}).length}칸`, color: (m && m.color) || '', bad: false, kind: 'patch', t: 0 };
      });
    /* 형식 3의 단체 · 제도 (통합 — 보기만: 누르면 편집 창의 폼 · 묶음 머리는 바탕 자료의 목록. 놓아서 채우기는 아직 — 단체 · 제도를 가리키는 칸이 나라 쪽에 없음).
       제도는 이름 칸이 없어 모델의 이름(나라 · 주제) — 모델에 없으면(자리를 못 정함) 적은 나라 · 주제 */
    const instName = x => {
      const m = byUid.get(`${id}/${x.id}`);
      const ref = HT.readInstPolity ? HT.readInstPolity(x.polity, x.track) : null;
      return (m && m.name) || [ref ? ref.polity : str(x.polity), Array.isArray(x.theme) ? str(x.theme[0]) : str(x.theme)].filter(Boolean).join(' · ') || x.id;
    };
    const lens = { groups: rowsOf('groups', 'group'), institutions: items('institutions').map(x => Object.assign(row(x, 'institution'), { name: instName(x) })).sort(byStart) };
    const docs = Object.keys(draft.documents || {}).map(k => {
      const own = items('periods').concat(items('events'), items('figures'), items('organs'), items('cultures'), items('dynasties'), items('epochs'), items('scopes'), items('groups')).find(x => x.id === k.split('//')[0]);
      return { doc: k, name: own ? `${str(own.name) || str(own.title) || own.id}${k.includes('//') ? ` / ${k.split('//').slice(1).join(' / ')}` : ''}` : k, years: '', color: '', bad: false, kind: 'doc', t: 0 };
    });
    return [
      {
        key: 'base', label: '바탕', n: n('tracks') + n('categories') + n('peoples') + n('rankDefs') + n('houses') + n('surnames') + n('places') + n('themes'),
        /* 성씨 · 지명(형식 3 F1) · 주제(형식 3 F2)도 바탕 자료의 표 — 줄을 누르면 그 표 */
        kids: [['tracks', '트랙'], ['spheres', '문화권'], ['yearCycles', '주기'], ['categories', '분류'], ['peoples', '민족'], ['rankDefs', '지위'], ['houses', '가문'], ['surnames', '성씨'], ['places', '지명'], ['themes', '주제']].map(([l, label]) => ({ key: `base:${l}`, label, n: n(l), base: l })),
      },
      { key: 'history', label: '역사', n: n('periods') + more.length, kids: byTrack('periods', 'period', 'periods', t => `객체 — ${t}`).concat({ key: 'history:more', label: '왕조 · 기관 · 문화', n: more.length, rows: more }) },
      { key: 'events', label: '사건', n: n('events'), kids: byTrack('events', 'event', 'events', t => t) },
      /* 인물: 계보 전용 인물(D1 — 띠에 놓지 않는 족보의 사람, 수천 명일 수 있음)을 거르기 — fig = 'all' · 'hide'(계보 전용 숨기기) · 'only'(계보 전용만) */
      (() => {
        const rows = items('figures').filter(x => (fig === 'hide' ? x.lineageOnly !== true : fig === 'only' ? x.lineageOnly === true : true)).map(x => row(x, 'figure')).sort(byStart);
        return { key: 'figures', label: fig === 'only' ? '사람 — 계보 전용' : fig === 'hide' ? '사람 — 띠 인물' : '사람', n: rows.length, rows };
      })(),
      { key: 'split', label: '구분', n: n('epochs') + n('scopes'), kids: [{ key: 'split:epochs', label: '시대 구분', n: n('epochs'), rows: rowsOf('epochs', 'epoch') }, { key: 'split:scopes', label: '대범위', n: n('scopes'), rows: rowsOf('scopes', 'scope') }] },
      { key: 'lens', label: '단체 · 제도', n: lens.groups.length + lens.institutions.length, kids: [{ key: 'lens:groups', label: '단체', n: lens.groups.length, rows: lens.groups }, { key: 'lens:institutions', label: '제도', n: lens.institutions.length, rows: lens.institutions }] },
      { key: 'patches', label: '덮어쓰기', n: patches.length, rows: patches },
      { key: 'docs', label: '문서', n: docs.length, rows: docs },
      { key: 'images', label: '그림', n: (draft.cover ? 1 : 0) + arr(draft.images).length, rows: [
        { cover: true, name: '표지', years: draft.cover ? '1장' : '없음', color: '', bad: false, kind: 'cover', t: 0 },
        { gallery: true, name: '문서 그림', years: `${arr(draft.images).length}장`, color: '', bad: false, kind: 'images', t: 0 },
      ] },
    ];
  }
  /** 찾기(이름 · 해 글): 맞는 줄만 남기고 빈 묶음은 뺍니다 — 남은 묶음은 펼친 것으로(open). 바탕 줄(base)은 줄이 없으므로 찾는 동안 뺌 */
  function filterTree(tree, q) {
    const s = str(q).toLowerCase();
    if (!s) return tree;
    const hit = r => r.name.toLowerCase().includes(s) || String(r.years || '').toLowerCase().includes(s);
    const walk = grp => {
      if (grp.rows) {
        const rows = grp.rows.filter(hit);
        return rows.length ? Object.assign({}, grp, { rows, n: rows.length, open: true }) : null;
      }
      if (grp.kids) {
        const kids = grp.kids.map(walk).filter(Boolean);
        return kids.length ? Object.assign({}, grp, { kids, n: kids.reduce((a, k) => a + k.n, 0), open: true }) : null;
      }
      return null;
    };
    return tree.map(walk).filter(Boolean);
  }

  /* ---------- 구조 나무의 보기 갈래 (docs/구상-연표-확장-10건.md 3-4 (나) — 놓아서 채우기) ----------
     가리키는 칸(민족 · 소속 · 국성 · 대범위의 구성원 · 트랙)은 치지 않고, 나라 줄을 그 칸의 가지에 끌어 놓아 채웁니다.
     보기 갈래는 작업실 설정(ht.maker.tree — 파일에 들어가지 않음): view = 'kind'(종류별 — 지금 나무) · 'people' · 'partOf' · 'house' · 'scope', ref = 불러온 팩의 나라도 보임.
     나무는 모델(켜진 팩 + 작업본)에서 짓습니다 — 묶음 { key, label, n, kids, rows, drop?, drag?, add?, color?, title? } · 줄 { uid, name, years, color, kind, ref, t, kids?, drop?, from? }.
     drop은 놓을 곳의 뜻({ type: 'track' | 'people' | 'partOf' | 'house' | 'scope', … }), drag는 끌 수 있는 묶음 머리(트랙 · 민족 — 차례 바꾸기) */
  const TREE_KEY = 'ht.maker.tree';
  const TREE_VIEWS = [['kind', '종류별'], ['people', '민족으로'], ['partOf', '소속으로'], ['house', '가문(국성)으로'], ['scope', '대범위로']];
  /** 보기 갈래 기억 읽기 — 모르는 값은 기본(종류별 · 불러온 팩 숨김) */
  function readTreeUi(raw) {
    const o = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    return { view: TREE_VIEWS.some(([v]) => v === o.view) ? o.view : 'kind', ref: o.ref === true, fig: ['hide', 'only'].includes(o.fig) ? o.fig : 'all' };
  }
  const yearsOf = x => {
    const a = yearOf(x.start);
    const b = x.ongoing ? '현재' : yearOf(isFinite(x.endY) ? x.endY : x.end);
    return a && b && b !== a ? `${a}–${b}` : a;
  };
  /** 보기 갈래의 나무. opts: model · own(고치는 DLC id) · include(나라를 보일지) · ownTracks · ownPeoples · ownHouses(작업본이 정의한 id 모음) · bornIn(이번에 만든 민족 · 가문 id → 트랙) · bad */
  function viewTreeOf(view, { model, own = '', include = () => true, ownTracks = new Set(), ownPeoples = new Set(), ownHouses = new Set(), bornIn = new Map(), bad = new Set() } = {}) {
    if (!model || view === 'kind') return [];
    const polities = (model.periods || []).filter(p => HT.itemKindOf(p) === 'period' && include(p));
    const row = (p, extra) => Object.assign({ uid: p.uid, name: p.name || p.id, years: yearsOf(p), color: p.color || '', kind: 'period', ref: p.packId !== own, pack: p.packName || '', bad: p.packId === own && bad.has(p.id), t: isFinite(p.start) ? p.start : Infinity }, extra);
    const startOf = g => Math.min(...(g.rows || []).map(r => r.t), ...(g.kids || []).map(startOf), Infinity);
    const countOf = g => (g.rows || []).reduce((a, r) => a + 1 + (r.kids ? countRows(r.kids) : 0), 0) + (g.kids || []).reduce((a, k) => a + countOf(k), 0);
    const countRows = rows => rows.reduce((a, r) => a + 1 + (r.kids ? countRows(r.kids) : 0), 0);
    const finish = g => {
      (g.kids || []).forEach(finish);
      if (g.rows) g.rows.sort(byStart);
      g.n = countOf(g);
      return g;
    };
    const tracks = (model.tracks || []).filter(t => ownTracks.has(t.id) || polities.some(p => p.track === t.id));
    const trackGroup = (t, kids, add) => ({ key: `v:${view}:${t.id}`, label: t.name || t.id, color: t.color || '', kids, rows: [], drop: { type: 'track', track: t.id }, drag: { type: 'track', id: t.id }, add, title: `트랙 «${t.name || t.id}» — 나라 줄을 이 머리에 놓으면 이 트랙으로 옮깁니다 · 트랙 머리끼리 끌면 차례가 바뀝니다` });
    /* 민족 · 가문처럼 parent로 이어지는 사전의 나무 (단계 수 제한 없음) — 나라가 붙은 가지와 그 조상, 그 가지의 하위 가지(빈 것도 — 놓을 곳), 쓰이지 않은 제 뿌리 */
    const dictTree = (t, list, { type, word, map, pathOf, isOwnDef, used }) => {
      const root = { kids: [] };
      const nodes = new Map();
      const ensure = (parent, d) => {
        if (nodes.has(d.id)) return nodes.get(d.id);
        const g = { key: `v:${view}:${t.id}:${d.id}`, label: d.name || d.id, color: d.color || '', kids: [], rows: [], order: isFinite(d.order) ? d.order : 1e9, def: d, drop: { type, id: d.id, track: t.id }, add: { type, parent: d.id, track: t.id } };
        if (type === 'people') g.drag = { type: 'people', id: d.id, parent: d.parentId || '', track: t.id };
        nodes.set(d.id, g);
        parent.kids.push(g);
        return g;
      };
      const none = { key: `v:${view}:${t.id}:-`, label: `${word} 없음`, kids: [], rows: [], drop: { type, id: '', track: t.id }, title: `여기에 놓으면 ${word}을(를) 비웁니다` };
      for (const p of list) {
        const path = pathOf(p);
        if (!path.length) {
          none.rows.push(row(p));
          continue;
        }
        let node = root;
        for (const d of path) node = ensure(node, d);
        node.rows.push(row(p));
      }
      /* 하위 가지(나라가 없어도 놓을 곳으로) — 넓이 우선으로 나무 끝까지 */
      for (let i = 0, all = [...nodes.values()]; i < all.length; i++) {
        for (const cid of all[i].def.children || []) {
          const c = map.get(cid);
          if (c && !nodes.has(c.id)) all.push(ensure(all[i], c));
        }
      }
      /* 쓰이지 않은 제 뿌리 · 이번에 이 트랙에서 만든 뿌리 */
      for (const d of map.values()) {
        if (d.parentId || nodes.has(d.id)) continue;
        if (bornIn.get(`${type}:${d.id}`) === t.id || (isOwnDef(d.id) && !used.has(d.id) && !bornIn.has(`${type}:${d.id}`))) {
          const g = ensure(root, d);
          for (let i = 0, all = [g]; i < all.length; i++) for (const cid of all[i].def.children || []) { const c = map.get(cid); if (c && !nodes.has(c.id)) all.push(ensure(all[i], c)); }
        }
      }
      const sortKids = g => {
        g.kids.sort((a, b) => a.order - b.order || startOf(a) - startOf(b) || a.label.localeCompare(b.label, 'ko'));
        g.kids.forEach(sortKids);
      };
      sortKids(root);
      return root.kids.concat(none);
    };
    const usedSet = paths => {
      const s = new Set();
      for (const p of model.periods || []) for (const d of paths(p)) s.add(d.id);
      return s;
    };

    if (view === 'people') {
      const map = model.peopleMap || new Map();
      const pathOf = p => (p.peoplePath || []).filter(Boolean);
      const used = usedSet(pathOf);
      return tracks.map(t => finish(trackGroup(t, dictTree(t, polities.filter(p => p.track === t.id), { type: 'people', word: '민족', map, pathOf, isOwnDef: id => ownPeoples.has(id), used }), { type: 'people', parent: '', track: t.id })));
    }
    if (view === 'house') {
      const map = model.houseMap || new Map();
      const pathOf = p => (p.houseId && map.get(p.houseId) ? (map.get(p.houseId).path || [p.houseId]).map(id => map.get(id)).filter(Boolean) : []);
      const used = usedSet(pathOf);
      const trees = tracks.map(t => trackGroup(t, dictTree(t, polities.filter(p => p.track === t.id), { type: 'house', word: '가문', map, pathOf, isOwnDef: id => ownHouses.has(id), used }), { type: 'house', parent: '', track: t.id }));
      /* 계보 전용 인물(D1 확정 설계 7-2 ⑧): 사람의 가문(파 — 파조 · 부계 물려받기, D1-W1의 사람 자리 houseId)의 가지 아래 '계보 전용' 묶음으로. 접힌 가지는 그리지 않으므로 수천 명이어도 됨 */
      const lineage = [...new Set((model.lineageFigures || []).concat((model.figures || []).filter(f => f.lineageOnly === true)))].filter(f => include(f));
      if (lineage.length) {
        const nodes = new Map(); // 가문 id → [{ track, group }]
        const walk = (g, track) => { if (g.def && g.drop && g.drop.type === 'house') (nodes.get(g.def.id) || nodes.set(g.def.id, []).get(g.def.id)).push({ track, g }); (g.kids || []).forEach(k => walk(k, track)); };
        for (const tg of trees) walk(tg, tg.drop.track);
        const by = new Map();
        for (const f of lineage) {
          const n = HT.personOf ? HT.personOf(model, f) : null;
          const hid = (n && n.houseId) || f.houseId || '';
          const spots = nodes.get(hid);
          if (!spots) continue;
          const spot = spots.find(x => x.track === f.track) || spots[0];
          (by.get(spot.g) || by.set(spot.g, []).get(spot.g)).push(f);
        }
        for (const [g, list] of by) {
          const rows = list.map(f => ({ uid: f.uid, name: f.name || f.id, years: [yearOf(f.birth), yearOf(f.death)].filter(Boolean).join('–'), color: '', kind: 'figure', ref: f.packId !== own, pack: f.packName || '', bad: false, t: isFinite(f.birth) ? f.birth : Infinity }));
          g.kids.unshift({ key: `${g.key}:kin`, label: '계보 전용', kids: [], rows, shut: true, title: '이 가문(파)의 계보 전용 인물 — 띠에 놓지 않는 족보의 사람' });
        }
      }
      return trees.map(finish);
    }
    if (view === 'partOf') {
      return tracks.map(t => {
        const list = polities.filter(p => p.track === t.id);
        const shown = new Set(list.map(p => p.uid));
        const rows = new Map(list.map(p => [p.uid, row(p, { kids: [], drop: { type: 'partOf', id: p.uid, track: t.id } })]));
        /* 첫 상위가 같은 트랙에 보이면 그 줄 아래에 — 돌고 도는 소속은 끊음 */
        const parentOf = p => {
          const h = (p.hosts || [])[0];
          return h && h.host && h.host.track === t.id && shown.has(h.host.uid) ? h.host : null;
        };
        const top = [];
        const out = [];
        for (const p of list) {
          let up = parentOf(p);
          for (let k = 0, q = up; q && k < 64; k++, q = parentOf(q)) if (q === p) up = null;
          const r = rows.get(p.uid);
          const h = (p.hosts || [])[0];
          if (h && h.relation) r.years = `${r.years} · ${HT.relationName(h.relation) || h.relation}`;
          if (up) rows.get(up.uid).kids.push(r);
          else if ((p.hosts || []).length || (p.partOf != null && p.partOf !== '' && !(Array.isArray(p.partOf) && !p.partOf.length))) out.push(r);
          else top.push(r);
        }
        const sortRows = list => {
          list.sort(byStart);
          for (const r of list) sortRows(r.kids);
          return list;
        };
        const kids = [{ key: `v:partOf:${t.id}:-`, label: '소속 없음', kids: [], rows: sortRows(top), drop: { type: 'partOf', id: '', track: t.id }, title: '나라 줄을 다른 나라 줄에 놓으면 그 나라에 속하고(관계를 고름), 이 머리에 놓으면 소속을 지웁니다' }];
        if (out.length) kids.push({ key: `v:partOf:${t.id}:out`, label: '상위가 다른 트랙 · 보기 밖', kids: [], rows: sortRows(out), title: '상위 나라가 다른 트랙에 있거나 이 보기에 없는 나라 — 여기에는 놓을 수 없습니다' });
        return finish(trackGroup(t, kids));
      });
    }
    if (view === 'scope') {
      return tracks.map(t => {
        const list = polities.filter(p => p.track === t.id);
        const scopes = (model.scopes || []).filter(s => s.track === t.id);
        const inScope = new Set();
        const kids = scopes.map(s => {
          const rows = (s.members || []).filter(m => m.track === t.id && include(m)).map(m => (inScope.add(m.uid), row(m, { from: s.uid })));
          const mine = s.packId === own;
          return { key: `v:scope:${s.uid}`, label: `${s.name}${s.label ? ` · ${s.label}` : ''}`, color: s.color || '', kids: [], rows, drop: { type: 'scope', id: s.uid, own: mine, track: t.id }, title: mine ? `대범위 «${s.name}» — 나라 줄을 놓으면 구성 정권이 됩니다` : `«${s.packName}»의 대범위 — 남의 대범위는 고칠 수 없습니다` };
        });
        kids.push({ key: `v:scope:${t.id}:-`, label: '대범위 없음', kids: [], rows: list.filter(p => !inScope.has(p.uid)).map(p => row(p)), drop: { type: 'scope', id: '', track: t.id }, title: '대범위의 줄을 여기에 놓으면 그 대범위에서 뺍니다' });
        return finish(trackGroup(t, kids));
      });
    }
    return [];
  }
  /** 보기 갈래 나무의 찾기 — 이름 · 해가 맞는 줄(소속 아래 줄까지)과 이름이 맞는 가지를 남기고, 남은 가지는 펼친 것으로 */
  function filterView(tree, q) {
    const s = str(q).toLowerCase();
    if (!s) return tree;
    const hit = r => r.name.toLowerCase().includes(s) || String(r.years || '').toLowerCase().includes(s);
    const rowsOf = rows =>
      rows
        .map(r => {
          const kids = rowsOf(r.kids || []);
          return hit(r) ? r : kids.length ? Object.assign({}, r, { kids }) : null;
        })
        .filter(Boolean);
    const walk = g => {
      if (g.label.toLowerCase().includes(s)) return Object.assign({}, g, { open: true });
      const rows = rowsOf(g.rows || []);
      const kids = (g.kids || []).map(walk).filter(Boolean);
      return rows.length || kids.length ? Object.assign({}, g, { rows, kids, open: true }) : null;
    };
    return tree.map(walk).filter(Boolean);
  }
  /** 차례(order) 다시 매기기: list = 형제들의 지금 차례 [{ id, order, editable }], 끈 것(moved)을 at 자리(형제에서 끈 것을 뺀 목록의 자리)로.
      바꿀 것만 { id: 새 order } — 끈 것만 앞뒤 사이의 정수로 두는 것이 먼저이고, 자리가 없으면 고칠 수 있는 형제를 10씩 다시 매깁니다(고칠 수 없는 형제가 끼면 null) */
  function planOrder(list, moved, at) {
    const me = list.find(x => x.id === moved);
    if (!me || !me.editable) return null;
    const seq = list.filter(x => x.id !== moved);
    seq.splice(Math.max(0, Math.min(seq.length, at)), 0, me);
    if (seq.map(x => x.id).join('\n') === list.map(x => x.id).join('\n')) return {};
    const i = seq.indexOf(me);
    const lo = i > 0 ? seq[i - 1].order : null;
    const hi = i < seq.length - 1 ? seq[i + 1].order : null;
    if (lo == null && hi == null) return {};
    let v;
    if (lo == null) v = Math.floor(hi) - 10;
    else if (hi == null) v = Math.floor(lo) + 10;
    else if (hi - lo > 1) v = Math.floor((lo + hi) / 2);
    else if (hi > lo) v = (lo + hi) / 2;
    if (v != null && (lo == null || v > lo) && (hi == null || v < hi)) return { [moved]: v };
    if (!seq.every(x => x.editable)) return null;
    const out = {};
    seq.forEach((x, k) => (x.order !== (k + 1) * 10 ? (out[x.id] = (k + 1) * 10) : 0));
    return out;
  }

  /* ---------- 작업 폴더 (10건 D3 결정 7 A — docs/설계-10건/4-5-메이커-블록과-묶음.md · 감독-선택.md D3) ----------
     만든 사람이 '지금 고치는 것'을 묶어 두는 곳 — 구조 나무 맨 위(팩 줄 바로 아래) '작업 폴더' 갈래, 어느 보기 갈래에서든 함께 보임.
     항목은 바로 가기(같은 항목이 자동 묶음에도 그대로 · 한 항목이 여러 폴더에 들어도 됨). 작업실 설정(ht.maker.folders — 이 브라우저, DLC 파일에 들어가지 않음 · 형식 변화 없음):
     { [작업본 DLC id]: [{ id, name, color(파스텔 열둘 가운데 하나), items: [항목 uid …] }] }. '집합 보기로 내보내기'만 작업본을 고침(형식 3 views 항목 하나 — 그 파일만 형식 3) */
  const FOLDER_KEY = 'ht.maker.folders';
  const FOLDER_LIMITS = { folders: 60, items: 2000, name: 40 };
  /** 한 DLC의 폴더 목록 읽기 — 모르는 값은 버리고, 색은 파스텔 열둘 가운데 하나로, 같은 항목은 한 번만 */
  function readFolders(raw, draftId) {
    const o = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    const pastel = (HT.PASTEL || []).map(c => c.id);
    const seen = new Set();
    const out = [];
    for (const f of arr(o[draftId])) {
      if (!f || typeof f !== 'object' || !/^[A-Za-z0-9_-]{1,40}$/.test(String(f.id || '')) || seen.has(f.id) || out.length >= FOLDER_LIMITS.folders) continue;
      seen.add(f.id);
      out.push({ id: f.id, name: str(f.name).slice(0, FOLDER_LIMITS.name) || '폴더', color: pastel.includes(f.color) ? f.color : pastel[out.length % pastel.length] || '', items: [...new Set(arr(f.items).filter(u => typeof u === 'string' && u))].slice(0, FOLDER_LIMITS.items) });
    }
    return out;
  }
  /** 고치는 DLC의 id가 바뀌면(팩 정보에서 id를 고침) 그 폴더도 새 id로 — 제 항목의 바로 가기(옛 id/항목)도 함께 (js/maker.js의 restoreWork가 부름) */
  function moveFolders(oldId, newId) {
    if (!HT.store || !oldId || !newId || oldId === newId) return;
    const all = HT.store.get(FOLDER_KEY, null);
    if (!all || typeof all !== 'object' || !Array.isArray(all[oldId])) return;
    const move = u => (typeof u === 'string' && u.startsWith(`${oldId}/`) ? `${newId}${u.slice(oldId.length)}` : u);
    all[newId] = all[oldId].map(f => Object.assign({}, f, { items: arr(f && f.items).map(move) }));
    delete all[oldId];
    HT.store.set(FOLDER_KEY, all);
  }

  /* ================= 작업실 화면 ================= */
  const NARROW = 860;
  const isTyping = a => !!a && (/^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName) || !!a.isContentEditable);
  /** 틀을 붙이기 전(연표가 처음 그려지기 전)에 배치 변수를 한 번 — 연표가 처음부터 제 크기로 (뒤에 mount가 같은 값으로 다시 적음) */
  function earlyVars() {
    const b = document.body;
    if (!b || !b.dataset || b.dataset.app !== 'make' || !HT.store || !b.style || !b.style.setProperty) return;
    const ui = readUi(HT.store.get(UI_KEY, null));
    const wide = innerWidth > NARROW;
    b.style.setProperty('--mk-left', `${wide && ui.left.open && innerWidth >= 1100 ? ui.left.w : 0}px`);
    b.style.setProperty('--mk-right', '0px'); // 고른 것이 없는 첫 화면은 접은 채 시작
    b.style.setProperty('--mk-bottom', `${wide && ui.bottom.open ? Math.min(Math.floor(innerHeight * 0.6), ui.bottom.h) : 0}px`);
    b.classList.toggle('mk-left-open', ui.left.open && innerWidth >= 1100);
    b.classList.remove('mk-right-open');
  }

  function mount(ctx, api) {
    const { $, state, timeline, esc } = ctx;
    const body = document.body;
    const ui = readUi(HT.store.get(UI_KEY, null));
    let leftShut = innerWidth < 1100; // 좁은 창에서는 왼쪽을 접은 채 시작 — 기억(ui.left.open)은 그대로
    let center = ui.center;
    let props = 'empty';
    const save = () => HT.store.set(UI_KEY, ui);
    const narrow = () => innerWidth <= NARROW;
    const leftOpen = () => ui.left.open && !leftShut;
    const rightMax = () => Math.max(LIMITS.right.min, Math.floor(innerWidth * 0.6));
    const rightW = () => (ui.right.wide ? rightMax() : Math.min(rightMax(), ui.right.w));
    const bottomMax = () => Math.max(LIMITS.bottom.min, Math.floor(innerHeight * 0.6));
    const click = sel => {
      const el = $(sel);
      if (el) el.click();
    };
    /** 지금 다루는 항목: 구조에서 줄에 초점이 있으면 그 줄, 아니면 오른쪽 창(편집 창 · 상세)의 항목 — Delete · F2 · 메뉴가 같은 것을 가리키게 */
    const current = () => {
      const a = document.activeElement;
      const row = a && a.closest && a.closest('#mkTree [data-tuid]');
      return (row && row.dataset.tuid) || (!$('#editPane').hidden && state.editing) || (!$('#detail').hidden && state.selected) || null;
    };
    const startEl = $('#mkStart');
    const statusEl = $('#mkStatus');
    const bottomEl = $('#mkBottom');
    const propsEl = $('#mkProps');
    const pane = $('#editPane');
    const detail = $('#detail');
    const dimEl = document.head.appendChild(Object.assign(document.createElement('style'), { id: 'mkRefDim' })); // 불러온 팩 흐리기 (HT.makerKit.refDimCSS)

    const hasRightContent = () => api.selection().length > 1 || props === 'info' || !detail.hidden || (!pane.hidden && !pane.classList.contains('is-floating'));
    const rightOpen = () => ui.right.open && hasRightContent();

    /* ---------- 배치: 크기는 CSS 변수 하나씩 — 바꿀 때 한 번에 ---------- */
    let layoutRaf = 0;
    function layout() {
      const n = narrow();
      body.style.setProperty('--mk-left', `${!n && leftOpen() ? ui.left.w : 0}px`);
      body.style.setProperty('--mk-right', `${!n && rightOpen() ? rightW() : 0}px`);
      body.style.setProperty('--mk-bottom', `${!n && ui.bottom.open ? Math.min(bottomMax(), ui.bottom.h) : 0}px`);
      body.classList.toggle('mk-left-open', leftOpen());
      body.classList.toggle('mk-right-open', rightOpen());
      bottomEl.hidden = !ui.bottom.open;
      const wideBtn = pane.querySelector('[data-pane="wide"]');
      if (wideBtn) {
        wideBtn.textContent = ui.right.wide ? '좁게' : '넓게';
        wideBtn.setAttribute('aria-pressed', String(ui.right.wide));
        wideBtn.title = ui.right.wide ? '오른쪽 창을 제 폭으로 되돌립니다' : '오른쪽 창을 가장 넓게(화면의 60%) 펼칩니다 — 왼쪽 가장자리를 끌어 폭을 맞출 수도 있습니다';
      }
    }
    const layoutSoon = () => layoutRaf || (layoutRaf = requestAnimationFrame(() => ((layoutRaf = 0), layout())));
    function setLeft(open) {
      leftShut = false;
      ui.left.open = !!open;
      save();
      layout();
    }
    function setRight(open) {
      ui.right.open = !!open;
      save();
      layout();
    }
    function setBottom(open) {
      ui.bottom.open = !!open;
      save();
      layout();
      if (open) renderBottomTabs();
    }
    const revealRight = () => setRight(true);
    function setRightWide(on) {
      ui.right.wide = !!on;
      save();
      layout();
    }
    window.addEventListener('resize', layoutSoon);
    /* 가장자리 끌기 — 끄는 동안은 한 프레임에 한 번, 놓으면 기억 */
    const grip = (sel, get, put) =>
      api.dragOn($(sel), {
        start: () => !narrow() && get(),
        move: (dx, dy, e, s) => {
          body.classList.add('mk-resizing');
          put(s, dx, dy);
          layoutSoon();
        },
        end: moved => {
          body.classList.remove('mk-resizing');
          if (!moved) return;
          save();
          layout(); // 끄는 동안은 프레임마다(layoutSoon) — 놓을 때 마지막 값을 한 번 더
        },
      });
    grip('[data-grip="left"]', () => leftOpen() && { w: ui.left.w }, (s, dx) => (ui.left.w = Math.round(Math.min(LIMITS.left.max, Math.max(LIMITS.left.min, s.w + dx)))));
    grip('[data-grip="right"]', () => ui.right.open && { w: rightW() }, (s, dx) => {
      ui.right.w = Math.round(Math.min(rightMax(), Math.max(LIMITS.right.min, s.w - dx)));
      ui.right.wide = false;
    });
    grip('[data-grip="bottom"]', () => ui.bottom.open && { h: Math.min(bottomMax(), ui.bottom.h) }, (s, dx, dy) => (ui.bottom.h = Math.round(Math.min(bottomMax(), Math.max(LIMITS.bottom.min, s.h - dy)))));
    for (const [sel, reset] of [['[data-grip="left"]', () => (ui.left.w = LIMITS.left.def)], ['[data-grip="right"]', () => ((ui.right.w = LIMITS.right.def), (ui.right.wide = false))], ['[data-grip="bottom"]', () => (ui.bottom.h = LIMITS.bottom.def)]])
      $(sel).addEventListener('dblclick', () => {
        reset();
        save();
        layout();
      });

    /* ---------- 명령 ---------- */
    const needDraft = new Set(['undo', 'redo', 'copy', 'cut', 'paste', 'duplicate', 'select-all', 'history', 'autosave', 'reflect', 'export', 'export-legacy', 'delete', 'rename', 'paste-table', 'paste-whole', 'check', 'changes', 'move-to', 'kin-outline']);
    function enabled(id) {
      if ((id.startsWith('base:') || needDraft.has(id)) && !api.draft) return false;
      if (id === 'move-to') return moveSources().length > 0;
      if (id === 'toggle-right') return hasRightContent();
      if (id === 'undo') return api.history.canUndo;
      if (id === 'redo') return api.history.canRedo;
      if (['copy', 'cut', 'duplicate'].includes(id)) return !!api.selection().length;
      if (id === 'delete' || id === 'rename') return !!current() && !!state.model.byUid.get(current());
      return true;
    }
    const checked = id =>
      ({
        'toggle-left': leftOpen(), 'toggle-right': rightOpen(), 'toggle-bottom': ui.bottom.open,
        filter: $('#filterbar').classList.contains('is-open'), legend: !$('#legend').hidden, zen: body.classList.contains('is-zen'),
        'dim-light': ui.dim === 'light', 'dim-mid': ui.dim === 'mid', 'dim-strong': ui.dim === 'strong',
        'tab-timeline': center === 'timeline', 'tab-table': center === 'table', 'tab-wiki': center === 'wiki',
      })[id] || false;
    function deleteCurrent() {
      if (api.selection().length > 1) return api.deleteSelection();
      const uid = current();
      if (uid) ctx.cmd.deleteItem(uid);
    }
    /** 보기 → 승계표 · 세계표: 고른 항목(구조 나무 · 편집 창 · 상세)에서 열 수 있으면 그것, 아니면 고르기 메뉴(보기 메뉴 자리에) */
    function openKin(which) {
      const uid = current();
      const k = uid ? ctx.kinPlan(uid) : {};
      if (which === 'succession' ? k.succ : k.fam) return ctx.openKin(uid, which);
      const b = $('#mkMenus [data-menu="view"]');
      const r = b ? b.getBoundingClientRect() : { left: 80, bottom: 40 };
      ctx.kinPick(which, r.left, r.bottom + 2);
    }
    function renameCurrent() {
      const uid = current();
      if (!uid) return;
      if (!(state.editing === uid && !pane.hidden)) HT.viewer.openEditor(uid);
      setTimeout(() => {
        const f = document.querySelector('#editorForm [name="name"], #editorForm [name="title"]');
        if (f && !pane.hidden) {
          f.focus();
          f.select();
        }
      }, 0); // 편집 창을 새로 열었으면 채운 뒤에 — 프레임을 기다리지 않음(그리기가 쉬는 창에서도)
    }
    function focusSearch() {
      const s = $('#searchInput');
      s.focus();
      s.select();
    }
    function setDim(level) {
      ui.dim = level;
      save();
      update();
    }
    const RUN = {
      undo: () => api.undo(), redo: () => api.redo(),
      copy: () => api.copySelection(), cut: () => api.deleteSelection({ cut: true }),
      paste: () => api.pasteSelection(), duplicate: () => api.duplicateSelection(),
      'select-all': () => api.selectItems(HT.makerKit.itemLists().flatMap(k => (api.draft[k] || []).map(x => `${api.draft.id}/${x.id}`))),
      history: () => api.openHistory(), autosave: () => api.openSnapshots(),
      start: () => showStart(),
      new: () => showStart('new'),
      open: () => api.openFile(),
      'edit-installed': () => showStart('installed'),
      reflect: () => api.reflect(),
      export: () => api.exportFile(),
      'export-legacy': () => api.exportLegacy(), // 옛 앱 · 옛 모듈용(형식 3 — 빠지는 칸을 묻고) — js/maker.js exportLegacy
      image: () => click('#imageBtn'),
      'to-timeline': () => api.toTimeline(), // 본 프로그램 미리보기(컴퓨터 메이커 앱) — js/maker.js toTimeline
      delete: deleteCurrent,
      rename: renameCurrent,
      'move-to': () => openMove(),
      'tab-timeline': () => setCenter('timeline'),
      'tab-table': () => setCenter('table'),
      'tab-wiki': () => setCenter('wiki'),
      'toggle-left': () => setLeft(!leftOpen()),
      'toggle-right': () => setRight(!ui.right.open),
      'toggle-bottom': () => setBottom(!ui.bottom.open),
      filter: () => click('#filterToggle'),
      legend: () => click('#legendBtn'),
      zen: () => ctx.cmd.setZen(!body.classList.contains('is-zen')),
      fit: () => timeline.fitAll(),
      'dim-light': () => setDim('light'),
      'dim-mid': () => setDim('mid'),
      'dim-strong': () => setDim('strong'),
      'paste-table': () => { setCenter('table'); grid.pasteBox(); },
      'paste-whole': () => api.pasteWhole(),
      'kin-outline': () => { const uid = current(); const x = uid && state.model.byUid.get(uid); HT.maker && HT.maker.kin && HT.maker.kin.outline(x && x.itemKind === 'figure' ? { uid } : {}); },
      'kin-succ': () => openKin('succession'),
      'kin-fam': () => openKin('family'),
      bulk: () => api.openBulk(),
      replace: () => openBottom('replace'), blanks: () => openBottom('blanks'),
      check: () => openBottom('problems'),
      changes: () => openBottom('changes'),
      year: () => click('#yearBtn'),
      measure: () => click('#measureBtn'),
      find: () => finder.openPalette(),
      keys: () => openKeys(),
      guide: () => openGuide(),
    };
    function run(id) {
      if (!enabled(id)) return;
      if (id.startsWith('base:')) return openTable(id.slice(5));
      if (grid.command(id)) return;
      if (RUN[id]) RUN[id]();
    }

    /* ---------- 메뉴 줄 (펼침은 viewer의 메뉴 틀 #ctxMenu — 우클릭 메뉴와 같은 모양) ---------- */
    const menus = $('#mkMenus');
    const menuEl = $('#ctxMenu');
    menus.innerHTML = MENUS.map(([id, label]) => `<button type="button" class="mk-menu" data-menu="${id}" aria-haspopup="menu" aria-expanded="false">${label}</button>`).join('');
    let openMenu = '';
    let wasOpen = '';
    const itemOf = c =>
      c.sep ? { sep: true } : { label: c.soon ? `${c.label} (${c.soon}단계)` : c.label, key: c.key, disabled: !!c.soon || !enabled(c.id), checked: checked(c.id), run: c.soon || !enabled(c.id) ? null : () => run(c.id) };
    function menuItems(menu) {
      const list = COMMANDS.filter(c => c.menu === menu).map(itemOf);
      if (menu !== 'insert') return list;
      const kinds = ctx.cmd.addKinds().map(kind => ({ label: `＋ ${HT.FORMS[kind].word}`, key: ctx.cmd.addKeyOf(kind), disabled: !api.draft, run: api.draft ? () => ctx.cmd.openAdd(kind) : null }));
      return kinds.concat({ sep: true }, list, api.templates ? api.templates.menuItems() : []); // 함께 만드는 틀 (10건 D3 결정 6 A — js/maker-templates.js)
    }
    function showMenuOf(btn) {
      const r = btn.getBoundingClientRect();
      openMenu = btn.dataset.menu;
      for (const b of menus.children) b.setAttribute('aria-expanded', String(b === btn));
      ctx.cmd.showMenu(menuItems(openMenu), r.left, r.bottom + 2);
    }
    menus.addEventListener('pointerdown', e => {
      const b = e.target.closest('[data-menu]');
      wasOpen = b && !menuEl.hidden && openMenu === b.dataset.menu ? openMenu : ''; // 문서의 pointerdown(메뉴 닫기)보다 먼저 — 열린 메뉴를 다시 누르면 닫기로
    });
    menus.addEventListener('click', e => {
      const b = e.target.closest('[data-menu]');
      if (b && wasOpen !== b.dataset.menu) showMenuOf(b);
    });
    menus.addEventListener('pointerover', e => {
      const b = e.target.closest('[data-menu]');
      if (b && openMenu && !menuEl.hidden && b.dataset.menu !== openMenu) showMenuOf(b);
    });
    new MutationObserver(() => {
      if (!menuEl.hidden) return;
      openMenu = '';
      for (const b of menus.children) b.setAttribute('aria-expanded', 'false');
    }).observe(menuEl, { attributes: true, attributeFilter: ['hidden'] });
    /* '＋ 더'(도구 줄 — 연표 js/viewer.js가 그 단추에 붙인 '항목 추가' 메뉴)에 '틀로 만들기' 갈래 (10건 D3 결정 6 A): 메이커에서만, 도구 줄의 잡는 단계에서 받아
       연표의 메뉴와 같은 '항목 추가' 줄(같은 글 · 단축키 · 길 — viewer의 addMenuItems) 뒤에 틀 목록 · '틀 관리…'를 붙인 한 메뉴로 엶. 틀 부품이 없으면 연표의 메뉴 그대로 */
    const addMoreBtn = $('#addPeriodBtn');
    if (addMoreBtn && api.templates)
      $('#mkTools').addEventListener(
        'click',
        e => {
          if (!e.target.closest || e.target.closest('#addPeriodBtn') !== addMoreBtn) return;
          e.stopPropagation(); // 단추에 붙은 연표의 메뉴는 열지 않음 (아래가 같은 줄 + 틀)
          if (!menuEl.hidden) return ctx.cmd.hideMenu(); // 열린 메뉴를 다시 누르면 닫기 (연표의 단추와 같게)
          const r = addMoreBtn.getBoundingClientRect();
          const adds = ctx.cmd.addKinds().map(kind => ({ label: HT.FORMS[kind].addLabel || `＋ ${HT.FORMS[kind].word} 추가`, key: ctx.cmd.addKeyOf(kind), run: () => ctx.cmd.openAdd(kind) }));
          ctx.cmd.showMenu([{ title: '항목 추가' }, ...adds, ...api.templates.menuItems()], r.left, r.bottom + 6);
        },
        true
      );

    /* ---------- 도구 줄 · 상태 줄 · 가운데 탭 · 아래 창 머리의 [data-cmd] ---------- */
    for (const b of $('#mkTools').querySelectorAll('[data-cmd]')) {
      const c = COMMANDS.find(x => x.id === b.dataset.cmd);
      if (c && c.soon) {
        b.disabled = true;
        b.classList.add('is-soon'); // 좁은 창에서는 숨김 (css/maker.css — 반영 · 파일로가 밀려 나가지 않게)
        b.title = `${c.label} — ${c.soon}단계에서 만듭니다`;
      } else if (c && c.key && !b.title) b.title = `${c.label} (${c.key})`;
    }
    document.addEventListener('click', e => {
      const b = e.target.closest('#mkTools [data-cmd], #mkStatus [data-cmd], #mkCTabs [data-cmd], #mkBottom [data-cmd], #mkProps [data-add], #mkTools [data-add], #mkStatus [data-st-packs]');
      if (!b || b.disabled) return;
      if (b.hasAttribute('data-st-packs')) return setLeftTab('packs');
      if (b.dataset.add) return api.draft ? ctx.cmd.openAdd(b.dataset.add) : showStart();
      run(b.dataset.cmd);
    });
    $('#mkDoc').addEventListener('click', () => api.draft && api.openInfo());

    /* ---------- 단축키: Ctrl 조합은 어디서나, 나머지(Delete · F2 · ?)는 글 칸 · 편집 창 · 팩 정보 밖에서만 ---------- */
    const KEYED = new Map(COMMANDS.filter(c => c.key && !c.soon && c.by !== 'viewer').map(c => [c.key, c]));
    document.addEventListener('keydown', e => {
      if (e.defaultPrevented || e.isComposing) return;
      const name = keyName(e);
      const c = name && KEYED.get(name === 'Ctrl+Shift+Z' ? 'Ctrl+Y' : name);
      if (!c || document.querySelector('dialog[open]')) return;
      if (!startEl.hidden && c.id !== 'open') return; // 처음 화면에서는 열기(Ctrl+O)만
      const ctrl = name.startsWith('Ctrl+');
      const a = document.activeElement;
      if (isTyping(a) && ['undo', 'redo', 'cut', 'copy', 'paste', 'select-all', 'duplicate'].includes(c.id)) return;
      if (['copy', 'cut', 'paste'].includes(c.id)) return; // 시스템 복사·붙여넣기 이벤트가 자료를 받습니다.
      if (!ctrl && (isTyping(a) || (a && a.closest && a.closest('#editPane, #mkProps, .mk-win, .fp-win, #ctxMenu')))) return;
      e.preventDefault();
      run(c.id);
    });

    document.addEventListener('keydown', e => {
      if (e.defaultPrevented || e.isComposing || e.key !== '/' || isTyping(e.target) || document.querySelector('dialog[open]')) return;
      e.preventDefault(); e.stopImmediatePropagation(); finder.openPalette();
    }, true);
    /* ---------- 왼쪽 탭 ---------- */
    const leftEl = $('#mkLeft');
    function paintLeftTab() {
      for (const b of leftEl.querySelectorAll('[data-ltab]')) {
        const on = b.dataset.ltab === ui.left.tab;
        b.classList.toggle('is-on', on);
        b.setAttribute('aria-selected', String(on));
      }
      for (const p of leftEl.querySelectorAll('[data-lpanel]')) p.hidden = p.dataset.lpanel !== ui.left.tab;
    }
    function setLeftTab(tab) {
      ui.left.tab = tab;
      save();
      paintLeftTab();
      if (!leftOpen()) setLeft(true);
    }
    leftEl.addEventListener('click', e => {
      const t = e.target.closest('[data-ltab]');
      if (t) setLeftTab(t.dataset.ltab);
    });

    /* ---------- 왼쪽 '구조' (설계 3-4): 누르면 오른쪽에서 고침 · 두 번 누르면 이름 칸 · 묶음 이름은 펼치기(바탕 줄은 바탕 자료 창) ---------- */
    const treeEl = $('#mkTree');
    const findEl = $('#mkTreeFind');
    const CAP = 300; // 한 묶음에 그리는 줄 — 넘으면 '… n개 더' (찾기로 좁힘)
    const DEFAULT_OPEN = new Set(['history']);
    let selUid = null, anchorUid = null;
    /* 보기 갈래(종류별 · 민족으로 · 소속으로 · 가문으로 · 대범위로)와 '불러온 팩도' — 작업실 설정(ht.maker.tree, 파일에 들어가지 않음) */
    const treeUi = readTreeUi(HT.store.get(TREE_KEY, null));
    const saveTreeUi = () => HT.store.set(TREE_KEY, treeUi);
    const bornIn = new Map(); // 이번에 나무에서 만든 민족 · 가문('people:id' · 'house:id') → 만든 트랙 — 아직 나라가 없어도 그 트랙의 나무에 보이게 (기억하지 않음)
    let dropReg = []; // 지금 그린 나무의 놓을 곳 · 끌 머리 · ＋ 단추의 뜻 — data-drop · data-drag · data-tadd는 이 목록의 자리 (그릴 때마다 새로)
    const reg = o => (dropReg.push(o), dropReg.length - 1);
    let treeDrag = null; // 나무 끌기 (HT.makerDrag.slot — 아래 '끌기'에서 붙임)
    treeEl.insertAdjacentHTML(
      'beforebegin',
      `<div class="mk-tview"><label><span>보기</span><select data-tview aria-label="구조 나무의 보기 갈래 — 나라 줄을 가지에 끌어 놓으면 그 칸이 채워집니다">${TREE_VIEWS.map(([v, l]) => `<option value="${v}">${l}</option>`).join('')}</select></label><label class="mk-tview-ref" title="불러온 팩(눈을 켠 것)의 나라도 나무에 보입니다 — 놓으면 그 나라는 덮어쓰기로 고칩니다(잠긴 팩은 건너뜀)"><input type="checkbox" data-tref> 불러온 팩도</label><label class="mk-tview-fig" hidden title="인물 묶음에서 계보 전용 인물(띠에 놓지 않는 족보의 사람)을 거릅니다"><span>인물</span><select data-tfig aria-label="인물 거르기"><option value="all">모두</option><option value="hide">계보 전용 숨기기</option><option value="only">계보 전용만</option></select></label></div>`
    );
    const viewBar = treeEl.previousElementSibling;
    function paintTreeBar() {
      viewBar.querySelector('[data-tview]').value = treeUi.view;
      viewBar.querySelector('[data-tref]').checked = treeUi.ref;
      viewBar.querySelector('.mk-tview-ref').hidden = treeUi.view === 'kind';
      /* 인물 거르기는 종류별 나무에서, 작업본에 계보 전용 인물이 있을 때만 (D1) */
      const figBox = viewBar.querySelector('.mk-tview-fig');
      figBox.hidden = treeUi.view !== 'kind' || !(api.draft && arr(api.draft.figures).some(f => f && f.lineageOnly === true));
      figBox.querySelector('[data-tfig]').value = treeUi.fig;
    }
    viewBar.addEventListener('change', e => {
      if (e.target.matches('[data-tview]')) treeUi.view = e.target.value;
      else if (e.target.matches('[data-tref]')) treeUi.ref = e.target.checked;
      else if (e.target.matches('[data-tfig]')) treeUi.fig = e.target.value;
      else return;
      saveTreeUi();
      renderTree();
    });
    /** 검사 오류가 가리키는 제 항목 id */
    function badIds() {
      const d = api.draft;
      const ids = new Set();
      for (const x of (api.check && api.check.errors) || []) {
        const it = d && x && Array.isArray(d[x.kind]) ? d[x.kind][x.index] : null;
        if (it && it.id) ids.add(it.id);
      }
      return ids;
    }
    const isOpenGroup = g => (g.open ? true : g.key in ui.tree ? ui.tree[g.key] : DEFAULT_OPEN.has(g.key) || g.key.startsWith('periods:')); // 처음에는 역사와 그 트랙별 시대를 펼침 (목업 A)
    const rowHTML = (r, depth) => {
      const attr = r.cover ? 'data-tinfo' : r.gallery ? 'data-timages' : r.doc ? `data-tdoc="${esc(r.doc)}"` : `data-tuid="${esc(r.uid)}"`;
      const handle = r.kind === 'period' || r.kind === 'event' ? '<span class="mk-handle" aria-hidden="true">⋮⋮</span>' : ''; // 트랙 묶음에 끌어 놓을 수 있는 줄 (놓아서 채우기)
      return `<button type="button" class="mk-trow d${depth}${r.uid && api.selection().includes(r.uid) ? ' is-sel' : ''}${r.bad ? ' is-bad' : ''}" ${attr} role="treeitem">${handle}<i${r.color ? ` style="--c:${esc(r.color)}"` : ' class="is-none"'} aria-hidden="true"></i><span>${esc(r.name)}</span>${r.years ? `<small>${esc(r.years)}</small>` : ''}</button>`;
    };
    /** 종류별 나무의 트랙 묶음(시대 — 트랙 · 사건의 트랙)은 놓을 곳: 그 종류의 줄을 놓으면 트랙을 옮깁니다 */
    const kindDrop = g => {
      const m = /^(periods|events):(.*)$/.exec(g.key);
      return m ? ` data-drop="${reg({ type: 'track', track: m[2], kinds: [m[1] === 'periods' ? 'period' : 'event'] })}"` : '';
    };
    function groupHTML(g, depth) {
      if (g.base) return `<button type="button" class="mk-tg d${depth} is-leaf" data-tbase="${esc(g.base)}" title="바탕 자료의 ${esc(g.label)} 표"><span>${esc(g.label)}</span><small>${g.n}</small></button>`;
      const has = g.key === 'base' || (g.kids ? g.kids.length > 0 && g.n > 0 : !!(g.rows && g.rows.length)); // 든 것이 없는 묶음은 펼치지 않음 (바탕은 표를 열러 늘 펼침)
      const open = !!has && isOpenGroup(g);
      const inner = !open ? '' : g.kids ? g.kids.map(k => groupHTML(k, depth + 1)).join('') : g.rows.slice(0, CAP).map(r => rowHTML(r, depth + 1)).join('') + (g.rows.length > CAP ? `<p class="mk-more">… ${g.rows.length - CAP}개 더 — 위 찾기 칸으로 좁히세요</p>` : '');
      return `<div class="mk-tgroup" role="group"><button type="button" class="mk-tg d${depth}${has ? '' : ' is-empty'}" data-tgroup="${esc(g.key)}" aria-expanded="${open}"${has ? '' : ' disabled'}${kindDrop(g)}><i class="car" aria-hidden="true">${has ? (open ? '▾' : '▸') : ''}</i><span>${esc(g.label)}</span><small>${g.n}</small></button>${inner}</div>`;
    }
    /* 보기 갈래의 나무 — 깊이는 제한이 없어 들여쓰기를 --d로 (css/maker.css .is-deep) */
    const ADD_WORD = { people: '민족', house: '가문' };
    const isOpenView = g => (g.open ? true : g.key in ui.tree ? ui.tree[g.key] : !g.shut); // shut: 처음에는 접힌 묶음 (계보 전용 인물 — 수천 명일 수 있음)
    const lockedUid = uid => {
      const x = state.model.byUid.get(uid);
      return !!x && !!api.isLocked && api.isLocked(x);
    };
    function vRowHTML(r, depth) {
      const tip = r.ref ? `«${r.pack}»의 나라 — ${lockedUid(r.uid) ? '잠긴 팩이라 놓아도 건너뜁니다(불러온 팩 탭에서 자물쇠를 풀면 고칠 수 있음)' : '놓으면 덮어쓰기로 적힙니다'}` : '';
      return `<button type="button" class="mk-trow is-deep${api.selection().includes(r.uid) ? ' is-sel' : ''}${r.bad ? ' is-bad' : ''}${r.ref ? ' is-ref' : ''}" style="--d:${depth}" data-tuid="${esc(r.uid)}"${r.from ? ` data-from="${esc(r.from)}"` : ''}${r.drop ? ` data-drop="${reg(r.drop)}"` : ''} role="treeitem"${tip ? ` title="${esc(tip)}"` : ''}>${r.kind === 'figure' ? '' : '<span class="mk-handle" aria-hidden="true">⋮⋮</span>'}<i${r.color ? ` style="--c:${esc(r.color)}"` : ' class="is-none"'} aria-hidden="true"></i><span>${esc(r.name)}</span>${r.years ? `<small>${esc(r.years)}</small>` : ''}</button>${(r.kids || []).map(k => vRowHTML(k, depth + 1)).join('')}`;
    }
    function vGroupHTML(g, depth) {
      const has = !!((g.kids && g.kids.length) || (g.rows && g.rows.length));
      const open = has && isOpenView(g);
      const rows = g.rows || [];
      const inner = !open ? '' : (g.kids || []).map(k => vGroupHTML(k, depth + 1)).join('') + rows.slice(0, CAP).map(r => vRowHTML(r, depth + 1)).join('') + (rows.length > CAP ? `<p class="mk-more is-deep" style="--d:${depth + 1}">… ${rows.length - CAP}개 더 — 위 찾기 칸으로 좁히세요</p>` : '');
      const word = g.add && ADD_WORD[g.add.type];
      const add = g.add ? `<button type="button" class="mk-tadd" data-tadd="${reg(g.add)}" title="${esc(`${g.add.parent ? `«${g.label}» 아래에` : `트랙 «${g.label}»에`} 새 ${word} — 이름만 치면 됩니다`)}">＋ ${word}</button>` : '';
      return `<div class="mk-tgroup" role="group"><div class="mk-tgh"><button type="button" class="mk-tg is-deep${depth ? '' : ' is-top'}${has ? '' : ' is-empty'}" style="--d:${depth}" data-tgroup="${esc(g.key)}" aria-expanded="${open}"${g.drop ? ` data-drop="${reg(g.drop)}"` : ''}${g.drag ? ` data-drag="${reg(g.drag)}"` : ''}${g.title ? ` title="${esc(g.title)}"` : ''}><i class="car" aria-hidden="true">${has ? (open ? '▾' : '▸') : ''}</i>${g.color ? `<i class="dot" style="--c:${esc(g.color)}" aria-hidden="true"></i>` : ''}<span>${esc(g.label)}</span><small>${g.n}</small></button>${add}</div>${inner}</div>`;
    }
    const VIEW_HINT = {
      people: '나라 줄을 민족 가지에 끌어 놓으면 그 민족이 됩니다(위 단계에 놓으면 그 단계로).',
      partOf: '나라 줄을 다른 나라 줄에 놓으면 그 나라에 속합니다 — 놓을 때 관계를 고릅니다.',
      house: '나라 줄을 가문 가지에 놓으면 그 가문이 국성이 됩니다.',
      scope: '나라 줄을 대범위에 놓으면 구성 정권이 됩니다(Ctrl을 누른 채 놓으면 원래 대범위에도 남음).',
    };
    function viewTree() {
      const d = api.draft;
      const rows = new Map((api.refRows ? api.refRows() : []).map(r => [r.id, r]));
      return viewTreeOf(treeUi.view, {
        model: state.model,
        own: d.id,
        include: x => x.packId === d.id || (treeUi.ref && !!rows.get(x.packId) && rows.get(x.packId).show !== false),
        ownTracks: new Set(arr(d.tracks).map(t => t && t.id)),
        ownPeoples: new Set(arr(d.peoples).map(p => p && p.id)),
        ownHouses: new Set(arr(d.houses).map(h => h && h.id)),
        bornIn,
        bad: badIds(),
      });
    }
    let viewQueued = false;
    function renderView(pack) {
      dropReg = [];
      const all = viewTree();
      const tree = filterView(all, findEl.value);
      const hint = `<p class="mk-thint">${esc(VIEW_HINT[treeUi.view])} 오른쪽 클릭 ▸ 옮기기…로도 됩니다.</p>`;
      treeEl.innerHTML = pack + folderSecHTML() + hint + (tree.length ? tree.map(g => vGroupHTML(g, 0)).join('') : `<p class="mk-empty">${all.length ? '맞는 항목이 없습니다.' : '이 보기에 보일 나라가 없습니다 — 시대를 더하거나 «불러온 팩도»를 켜세요.'}</p>`);
      if (treeDrag) treeDrag.refresh(); // 끄는 중에 다시 그렸으면 끄는 줄을 다시 접고 빈 자리를 지금 손 자리에 다시 (움직임 없이)
    }
    function renderTree() {
      const d = api.draft;
      dropReg = [];
      paintTreeBar();
      if (!d) {
        treeEl.innerHTML = '<p class="mk-empty">고칠 DLC가 없습니다 — 파일 ▸ 처음 화면.</p>';
        return;
      }
      const pack = `<button type="button" class="mk-trow is-pack${props === 'info' ? ' is-sel' : ''}" data-tinfo title="팩 정보"><span class="ic" aria-hidden="true">📦</span><b>${esc(d.name)}</b><small>v${esc(d.version)}</small></button>`;
      if (treeUi.view !== 'kind') {
        /* 보기 갈래의 나무는 모델로 짓는데, 작업본이 바뀌면 이 함수는 새 모델이 state.model에 놓이기 전(maker.buildModel 안)에 불립니다 —
           그래서 지금 흐름이 끝난 뒤(마이크로태스크)에 한 번 그립니다. 같은 흐름에서 여러 번 불려도 한 번 */
        if (!viewQueued) {
          viewQueued = true;
          queueMicrotask(() => {
            viewQueued = false;
            if (api.draft && treeUi.view !== 'kind') renderView(pack);
          });
        }
        return;
      }
      const tree = filterTree(treeOf(d, { model: state.model, bad: badIds(), fig: arr(d.figures).some(f => f && f.lineageOnly === true) ? treeUi.fig : 'all' }), findEl.value);
      const fsec = folderSecHTML(); // 작업 폴더 — 팩 줄 바로 아래 (10건 D3 결정 7 A)
      treeEl.innerHTML = pack + fsec + (tree.length ? tree.map(g => groupHTML(g, 0)).join('') : fsec ? '' : '<p class="mk-empty">맞는 항목이 없습니다.</p>');
      if (treeDrag) treeDrag.refresh();
    }
    /** 누른 항목: 오른쪽에서 고치고, 보이는 기간 밖일 때만 연표를 그리로 (움직임 원칙 — 필요할 때만) */
    function pickUid(uid) {
      const x = state.model.byUid.get(uid);
      if (x) {
        const opened = ctx.openEditorFor(uid);
        const v = timeline.view;
        const s = isFinite(x.spanMin) ? x.spanMin : x.start;
        const e = isFinite(x.spanMax) ? x.spanMax : isFinite(x.endY) ? x.endY : s;
        if (isFinite(s) && (e < v.start || s > v.end)) timeline.focusOn(x);
        return opened;
      }
      const p = api.pseudo(uid); // 검사에서 떨어져 연표에 없는 제 항목도 고칠 수 있게
      if (p) return ctx.openEditor(p, p.itemKind);
      HT.toast('이 항목은 지금 연표에 없습니다 — 덮어쓰기 대상이면 그 팩을 불러와야 보입니다.');
    }
    /** 오른쪽에 열린 항목의 줄에 표시 (연표 · 검색에서 골라도 따라감) */
    function syncTreeSel() {
      const uid = current();
      if (uid !== selUid) { selUid = uid; const el = uid && treeEl.querySelector(`[data-tuid="${CSS.escape(uid)}"]`); if (el && api.selection().length < 2) el.scrollIntoView({ block: 'nearest' }); }
      api.paintSelection();
    }
    findEl.addEventListener('input', renderTree); // 찾기 칸은 나무 밖 — 나무만 다시 그려 한글 조합이 끊기지 않음
    treeEl.addEventListener('click', e => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.tadd != null) return startAdd(b);
      if (b.hasAttribute('data-fnew')) return startFolderNew(); // 작업 폴더의 ＋
      if (b.dataset.tgroup) {
        ui.tree[b.dataset.tgroup] = b.getAttribute('aria-expanded') !== 'true';
        save();
        renderTree();
        const group = b.dataset.tgroup, list = group.startsWith('periods:') ? 'periods' : group.startsWith('events:') || group === 'events' ? 'events' : group === 'figures' ? 'figures' : group.startsWith('split:') ? group.slice(6) : group.startsWith('lens:') ? group.slice(5) : group === 'patches' ? 'patches' : null;
        if (list) openTable(list);
        return;
      }
      if (b.dataset.tbase) return openTable(b.dataset.tbase);
      if (b.hasAttribute('data-timages')) return HT.makerImages.openGallery({ maker: HT.viewer.maker, esc });
      if ('tinfo' in b.dataset) return api.openInfo();
      if (b.dataset.tdoc) return ctx.openWiki(HT.docKey.absolute(b.dataset.tdoc, api.draft.id));
      if (b.dataset.tuid) {
        const uid = b.dataset.tuid;
        if (e.shiftKey && anchorUid) {
          const rows = [...treeEl.querySelectorAll('[data-tuid]')].map(x => x.dataset.tuid), a = rows.indexOf(anchorUid), z = rows.indexOf(uid);
          if (a >= 0 && z >= 0) return api.selectItems(rows.slice(Math.min(a, z), Math.max(a, z) + 1));
        }
        anchorUid = uid;
        if (e.ctrlKey || e.metaKey) return api.toggleSelection(uid);
        api.selectItems([uid]);
        Promise.resolve(pickUid(uid)).then(ok => { if (ok !== false) treeEl.querySelector(`[data-tuid="${CSS.escape(uid)}"]`)?.focus({ preventScroll: true }); });
      }
    });
    treeEl.addEventListener('dblclick', e => !e.ctrlKey && !e.metaKey && !e.shiftKey && e.target.closest('[data-tuid]') && renameCurrent());
    treeEl.addEventListener('keydown', e => {
      if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
      const list = [...treeEl.querySelectorAll('button:not([disabled])')];
      const i = list.indexOf(document.activeElement);
      const next = list[Math.max(0, Math.min(list.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))];
      e.preventDefault(); // 연표의 방향키(옮기기)로 새지 않게
      if (next) next.focus();
    });
    treeEl.addEventListener('contextmenu', e => {
      /* 작업 폴더의 머리 · 폴더 머리 — 폴더 메뉴 (10건 D3 결정 7 A) */
      const fh = e.target.closest('[data-folder], [data-tgroup="folders"]');
      if (fh) {
        e.preventDefault();
        const r = fh.getBoundingClientRect();
        const kb = !e.clientX && !e.clientY; // 메뉴 키 · Shift+F10 — 머리 곁에
        return fh.dataset.folder != null ? folderMenu(fh.dataset.folder, kb ? r.right - 30 : e.clientX, kb ? r.top : e.clientY, fh) : ctx.cmd.showMenu([{ title: '작업 폴더' }, { label: '＋ 새 폴더', disabled: !api.draft, run: api.draft ? () => startFolderNew() : null }], kb ? r.left + 20 : e.clientX, kb ? r.bottom : e.clientY);
      }
      const head = e.target.closest('[data-drag]');
      if (head && !e.target.closest('[data-tuid]')) {
        e.preventDefault();
        return headMenu(head, e.clientX, e.clientY);
      }
      const b = e.target.closest('[data-tuid]');
      if (!b) return;
      e.preventDefault();
      const uid = b.dataset.tuid;
      const x = state.model.byUid.get(uid);
      const movable = !!x && DRAG_KINDS().includes(x.itemKind);
      ctx.cmd.showMenu(
        [
          { title: x ? x.title || x.name : uid },
          { label: '✎ 고치기', run: () => pickUid(uid) },
          { label: '🎯 연표에서 보기', disabled: !x, run: x ? () => timeline.focusOn(x) : null },
          { label: '📄 문서', key: 'W', run: () => ctx.openWiki(uid) },
          ...(x && x.itemKind === 'figure' && HT.maker && HT.maker.kin ? [{ label: '계층 입력… (이 사람이 뿌리)', run: () => HT.maker.kin.outline({ uid }) }] : []),
          { sep: true },
          { label: '옮기기… (갈 곳 고르기)', disabled: !movable, run: movable ? () => openMove(api.selection().includes(uid) ? moveSources() : [uid], b.dataset.from || '') : null },
          /* 작업 폴더 (10건 D3 결정 7 A): 넣기는 고른 줄 모두(이 줄이 고른 것 안이면) · 폴더 안의 줄이면 그 폴더에서 빼기 */
          { label: '폴더에 넣기…', disabled: !x, run: x ? () => folderPick(api.selection().includes(uid) ? api.selection().filter(u => !!byUidM(u)) : [uid], e.clientX, e.clientY) : null },
          ...(b.dataset.infolder ? [{ label: `폴더 «${(folders().find(f => f.id === b.dataset.infolder) || {}).name || ''}»에서 빼기`, run: () => folderRemove(b.dataset.infolder, [uid]) }] : []),
          { sep: true },
          { label: '복제', key: 'Ctrl+D', run: () => api.duplicateSelection([uid]) },
          { label: '복사', key: 'Ctrl+C', run: () => api.copySelection([uid]) },
          { sep: true },
          { label: x && api.isOwn(x) ? '🗑 지우기' : '🙈 숨기기', danger: true, disabled: !x, run: x ? () => ctx.cmd.deleteItem(uid) : null },
        ],
        e.clientX,
        e.clientY
      );
    });
    /* ---------- 놓아서 채우기 (docs/구상-연표-확장-10건.md 3-4 (나)) ----------
       나라 줄(종류별 나무에서는 시대 · 사건 줄)을 끌어 가지 머리에 놓으면 그 가지가 가리키는 칸이 채워집니다 — 민족 · 소속(관계를 고름) · 국성 · 대범위의 구성원 · 트랙.
       고른 줄이 여럿이면 함께, 한 번 놓기가 되돌리기 한 걸음(api.transact). 남의 항목(다른 DLC · 기본팩)은 지금 규칙대로 바뀐 칸만 덮어쓰기로, 잠긴 팩의 것은 건너뜀.
       트랙 · 민족 머리끼리 끌면 차례(order). 끄는 동안 놓을 곳에 미리 글("놓으면: 민족 → ○○ (3개)")과 놓을 수 없는 까닭. 키보드는 오른쪽 클릭 · 편집 메뉴의 '옮기기…' */
    const D = HT.draft;
    const clone = x => JSON.parse(JSON.stringify(x));
    const DRAG_KINDS = () => (treeUi.view === 'kind' ? ['period', 'event'] : ['period']);
    const byUidM = uid => state.model.byUid.get(uid) || null;
    const ownX = x => !!x && !!api.draft && x.packId === api.draft.id;
    const editableX = x => ownX(x) || !(api.isLocked && api.isLocked(x));
    /** 사전(민족 · 가문)의 항목을 가리키는 글 — 이름으로 찾아도 같은 것이 나오면 이름(폼과 같은 꼴), 아니면 id */
    const dictRef = (d, map) => (d.auto || (!map.has(d.name) && [...map.values()].find(x => x.name === d.name) === d) ? d.name : d.id);
    /** 나라를 가리키는 글(소속 · 대범위의 구성 정권) — 같은 트랙에서 이름이 하나뿐이면 이름, 아니면 id(같은 팩) · uid(남의 팩) */
    const polityRef = (target, fromPack) => {
      const same = state.model.periods.filter(q => q.track === target.track && q !== target && (q.name === target.name || q.id === target.name || q.uid === target.name));
      return !same.length ? target.name : target.packId === fromPack ? target.id : target.uid;
    };
    const hasPartOf = x => !(x.partOf == null || x.partOf === '' || (Array.isArray(x.partOf) && !x.partOf.length));
    /** target이 x 아래(소속의 소속 …)에 있는지 — 그러면 x를 target에 놓으면 돌고 도는 소속 */
    const isUnder = (target, x) => {
      const seen = new Set();
      for (let list = [target]; list.length; ) {
        const q = list.pop();
        if (q === x) return true;
        if (seen.has(q)) continue;
        seen.add(q);
        for (const h of q.hosts || []) if (h.host) list.push(h.host);
      }
      return false;
    };
    const result = (take, skip, what, op) => {
      if (!take.length) return { ok: false, reason: skip[0] || '바뀌는 것이 없음' };
      const why = [...new Set(skip)];
      return { ok: true, items: take, op, text: `놓으면: ${what} (${take.length}개)${skip.length ? ` · ${skip.length}개 건너뜀(${why.join(' · ')})` : ''}` };
    };
    /** 놓기 계획: p = { uids, from } (줄) 또는 { group } (머리), drop = 놓을 곳의 뜻 → { ok, text | reason, items, op } */
    function planFor(p, drop, { pos = 'after', ctrl = false } = {}) {
      if (!drop || !api.draft) return { ok: false, reason: '여기에는 놓을 수 없음' };
      if (drop.type === 'folder' || drop.type === 'folder-new' || (p.group && p.group.type === 'folder')) return planFolder(p, drop, { pos, ctrl }); // 작업 폴더 (작업실 설정 — 작업본은 그대로)
      if (p.group) return planGroup(p.group, drop, pos);
      if (!p.uids.length) return { ok: false, reason: '이 항목은 작업 폴더에만 놓을 수 있음' }; // 끌어 온 것이 모두 폴더에만 넣는 종류(인물 · 기관 …)
      const items = p.uids.map(byUidM).filter(Boolean);
      const take = [];
      const skip = [];
      const locked = x => !editableX(x) && (skip.push('잠긴 팩'), true);
      if (drop.type === 'track') {
        const t = state.model.trackMap.get(drop.track);
        if (!t) return { ok: false, reason: '트랙이 없음' };
        for (const x of items) {
          if (drop.kinds && !drop.kinds.includes(x.itemKind)) skip.push('다른 종류');
          else if (x.track === drop.track) skip.push('이미 이 트랙');
          else if (!locked(x)) take.push(x);
        }
        return result(take, skip, `트랙 → ${t.name}`, { type: 'track', track: drop.track });
      }
      if (drop.type === 'people' || drop.type === 'house') {
        const map = drop.type === 'people' ? state.model.peopleMap : state.model.houseMap || new Map();
        const d = drop.id ? map.get(drop.id) : null;
        const word = drop.type === 'people' ? '민족' : '국성';
        if (drop.id && !d) return { ok: false, reason: `${word}을(를) 찾지 못함` };
        for (const x of items) {
          const cur = (drop.type === 'people' ? x.peopleId : x.house ? x.houseId : '') || '';
          if (cur === (drop.id || '')) skip.push(d ? `이미 그 ${word}` : `${word}이(가) 없음`);
          else if (!locked(x)) take.push(x);
        }
        return result(take, skip, d ? `${word} → ${d.name}` : `${word} 비움`, { type: drop.type, id: drop.id || '' });
      }
      if (drop.type === 'partOf') {
        const target = drop.id ? byUidM(drop.id) : null;
        if (drop.id && !target) return { ok: false, reason: '나라를 찾지 못함' };
        for (const x of items) {
          if (target && x === target) skip.push('자기 자신');
          else if (target && x.track !== target.track) skip.push('같은 트랙이 아님');
          else if (target && isUnder(target, x)) skip.push('제 아래 나라에는 놓을 수 없음');
          else if (!target && !hasPartOf(x)) skip.push('소속이 없음');
          else if (!locked(x)) take.push(x);
        }
        const many = take.filter(x => Array.isArray(x.partOf) && (x.partOf.length > 1 || x.partOf.some(r => r && typeof r === 'object' && (r.start != null || r.end != null)))).length;
        const r = result(take, skip, target ? `소속 → ${target.name}` : '소속 지움', { type: 'partOf', id: target ? target.uid : '' });
        if (r.ok && target) r.text += ' — 놓은 뒤 관계를 고릅니다';
        if (r.ok && many) r.text += ` · 차례로 예속된 소속 ${many}개를 이 하나로 바꿈`;
        return r;
      }
      if (drop.type === 'scope') {
        const scope = drop.id ? byUidM(drop.id) : null;
        const from = p.from ? byUidM(p.from) : null;
        if (scope && !ownX(scope)) return { ok: false, reason: '남의 대범위 — 고칠 수 없음' };
        if (!scope && !from) return { ok: false, reason: '이미 대범위 밖' };
        if (!scope && !ownX(from)) return { ok: false, reason: '남의 대범위에서는 뺄 수 없음' };
        const out = !scope ? from : from && from !== scope && ownX(from) && !ctrl ? from : null; // 다른 대범위에서 끌어 왔으면 거기서 뺌 (Ctrl이면 남김)
        for (const x of items) {
          if (scope && x.track !== scope.track) skip.push('같은 트랙이 아님');
          else if (scope && scope.host === x) skip.push('상징적 본국');
          else if (scope && (scope.members || []).includes(x) && !out) skip.push('이미 그 대범위');
          else take.push(x);
        }
        if (out && take.length && (out.members || []).every(m => take.includes(m))) return { ok: false, reason: `«${out.name}»의 마지막 구성 정권은 뺄 수 없음 — Ctrl을 누른 채 놓으면 남김` };
        const what = scope ? `대범위 «${scope.name}»에 넣음${out ? ` · «${out.name}»에서 뺌` : ''}` : `대범위 «${from.name}»에서 뺌`;
        return result(take, skip, what, { type: 'scope', id: scope ? scope.uid : '', out: out ? out.uid : '' });
      }
      return { ok: false, reason: '여기에는 놓을 수 없음' };
    }
    /** 사전 줄을 고칠 수 있는지(차례): 이 DLC가 정의했고 다른 팩이 같은 id를 먼저 정의하지 않은 것 · 이름만 적힌 민족(저절로 생긴 것 — 놓으면 등록) */
    const editableDef = (list, id) => {
      if (list === 'peoples' && (state.model.peopleMap.get(id) || {}).auto) return true;
      const base = api.baseModel ? api.baseModel() : null;
      const shadow = base && (list === 'tracks' ? base.trackMap : base.peopleMap).has(id);
      return arr(api.draft[list]).some(o => o && o.id === id) && !shadow;
    };
    /** 끌 수 있는 머리(트랙 · 민족)의 형제 — 지금 나무에 놓인 차례 그대로 [{ id, label, order, editable }] */
    function siblingsOf(g) {
      const tree = viewTree();
      if (g.type === 'track') return tree.map(t => ({ id: t.drop.track, label: t.label, order: (state.model.trackMap.get(t.drop.track) || {}).order, editable: editableDef('tracks', t.drop.track) }));
      const top = tree.find(t => t.drop.track === g.track);
      const find = kids => {
        for (const k of kids) {
          if (k.drop && k.drop.type === 'people' && k.drop.id === g.id) return kids;
          const r = find(k.kids || []);
          if (r) return r;
        }
        return null;
      };
      return ((top && find(top.kids)) || []).filter(k => k.drag).map(k => ({ id: k.drop.id, label: k.label, order: (state.model.peopleMap.get(k.drop.id) || {}).order, editable: editableDef('peoples', k.drop.id) }));
    }
    function planGroup(g, drop, pos) {
      const isTrack = g.type === 'track';
      if (isTrack && drop.type !== 'track') return { ok: false, reason: '트랙은 트랙 머리끼리 끌어 차례를 바꿉니다' };
      if (!isTrack) {
        if (drop.type !== 'people' || !drop.id || drop.track !== g.track) return { ok: false, reason: '민족은 같은 부모 아래 민족 머리끼리 끌어 차례를 바꿉니다' };
        if (((state.model.peopleMap.get(drop.id) || {}).parentId || '') !== (g.parent || '')) return { ok: false, reason: '같은 부모 아래에서만 차례를 바꿉니다' };
      }
      const targetId = isTrack ? drop.track : drop.id;
      if (targetId === g.id) return { ok: false, reason: '제자리' };
      const list = siblingsOf(g);
      const target = list.find(x => x.id === targetId);
      if (!target || !list.some(x => x.id === g.id)) return { ok: false, reason: '같은 부모 아래에서만 차례를 바꿉니다' };
      const me = list.find(x => x.id === g.id);
      if (!me.editable) return { ok: false, reason: isTrack ? '다른 팩이 정한 트랙이라 차례를 바꿀 수 없음' : '다른 팩이 정한 민족이라 차례를 바꿀 수 없음' };
      let at = list.filter(x => x.id !== g.id).findIndex(x => x.id === targetId);
      if (pos === 'after') at++;
      const orders = planOrder(list, g.id, at);
      if (!orders) return { ok: false, reason: '다른 팩이 정한 형제 사이라 차례를 정할 자리가 없음' };
      if (!Object.keys(orders).length) return { ok: false, reason: '제자리' };
      return { ok: true, pos, text: `놓으면: 차례 — «${target.label}» ${pos === 'before' ? '앞' : '뒤'}으로`, op: { type: 'order', list: isTrack ? 'tracks' : 'peoples', orders } };
    }

    /* 놓은 뒤: 줄이 새 자리로 흐름(--t-move · 되튐 없음 · 움직임 줄이기면 없음) */
    const rowKey = el => (el.dataset.tuid ? `r:${el.dataset.tuid}` : `g:${el.dataset.tgroup}`);
    function positions() {
      const m = new Map();
      for (const el of treeEl.querySelectorAll('[data-tuid], [data-tgroup]')) if (!m.has(rowKey(el))) m.set(rowKey(el), el.getBoundingClientRect().top);
      return m;
    }
    function flip(before) {
      if (!before || !(HT.motion.T.move > 0) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      const seen = new Set();
      for (const el of treeEl.querySelectorAll('[data-tuid], [data-tgroup]')) {
        const k = rowKey(el);
        if (seen.has(k)) continue;
        seen.add(k);
        const y0 = before.get(k);
        const dy = y0 == null ? 0 : y0 - el.getBoundingClientRect().top;
        if (Math.abs(dy) >= 1) el.animate([{ transform: `translateY(${dy}px)` }, { transform: 'none' }], { duration: HT.motion.T.move, easing: HT.motion.C.spring });
      }
    }
    /** 항목들을 한 걸음에: 제 항목은 그 자리에서, 남의 항목은 원본과 견줘 바뀐 칸만 덮어쓰기로(잠긴 팩은 건너뜀) */
    function editItems(draft, items, fn) {
      let n = 0;
      for (const x of items) {
        const own = D.isOwnUid(draft, x.uid) && D.findOwn(draft, x.uid.slice(draft.id.length + 1));
        if (own) fn(own.item, x);
        else {
          if (api.isLocked(x)) continue;
          const before = api.rawOf(x);
          const after = clone(before);
          fn(after, x);
          HT.makerGrid.patchItem(draft, api.baseModel().byUid.get(x.uid) || x, before, after);
        }
        n++;
      }
      return n;
    }
    const scopeList = s => (Array.isArray(s.members) ? s.members : s.members == null || s.members === '' ? [] : [s.members]);
    const refHits = (raw, x, track) => {
      const r = HT.readScopeRef(raw);
      return !!r && (r.track || track) === x.track && (r.polity === x.name || r.polity === x.id || r.polity === x.uid);
    };
    /** 놓기의 뜻 → 항목 하나를 고치는 함수 fn(item, x) — 제 항목은 작업본의 그 자리, 남의 항목은 원본의 사본(editItems가 덮어쓰기로 바꿈) */
    function setterFor(op, relation) {
      const ref = (map, id) => (id ? dictRef(map.get(id), map) : '');
      const put = (key, v) => item => (v ? (item[key] = v) : delete item[key]);
      if (op.type === 'people') return put('people', ref(state.model.peopleMap, op.id));
      if (op.type === 'house') return put('house', ref(state.model.houseMap, op.id));
      if (op.type === 'track') return item => (item.track = op.track);
      if (op.type === 'partOf') {
        const t = op.id ? byUidM(op.id) : null;
        return (item, x) => {
          if (!t) return delete item.partOf;
          const r = polityRef(t, x.packId);
          item.partOf = relation ? [{ polity: r, relation }] : r;
        };
      }
      return null;
    }
    async function apply(plan, { relation = '', extra = null, name = '' } = {}) {
      const op = plan.op;
      const d0 = api.draft;
      const before = positions();
      const label = name || plan.text.replace(/^놓으면: /, '').replace(/ — 놓은 뒤 관계를 고릅니다/, '');
      const ok = await api.transact(draft => {
        if (draft.id !== d0.id) throw Error('고치는 DLC가 바뀌었습니다.');
        if (op.type === 'order') {
          for (const [id, v] of Object.entries(op.orders)) {
            let def = arr(draft[op.list]).find(o => o && o.id === id);
            const pe = op.list === 'peoples' ? state.model.peopleMap.get(id) : null;
            if (!def && pe && pe.auto) draft.peoples.push((def = { id: HT.makerKit.uniqueId(`people-${HT.hash(pe.name)}`, new Set([...state.model.peopleMap.keys(), ...arr(draft.peoples).map(o => o && o.id)])), name: pe.name })); // 이름만 적힌 민족 — 같은 이름으로 등록하면 그대로 그 민족
            if (def) def.order = v;
          }
          return draft;
        }
        if (op.type === 'scope') {
          const find = uid => arr(draft.scopes).find(o => o && `${draft.id}/${o.id}` === uid);
          const to = op.id ? find(op.id) : null;
          const out = op.out ? find(op.out) : null;
          for (const x of plan.items) {
            if (out) out.members = scopeList(out).filter(raw => !refHits(raw, x, out.track));
            if (to && !scopeList(to).some(raw => refHits(raw, x, to.track))) to.members = scopeList(to).concat(polityRef(x, draft.id));
          }
          return draft;
        }
        const fn = setterFor(op, relation);
        if (!fn) throw Error('놓을 수 없는 곳입니다.');
        editItems(draft, plan.items, fn);
        if (extra) extra(draft);
        D.ensureRefs(draft, state.model);
        return draft;
      }, label);
      if (ok) flip(before);
      return ok;
    }
    /** 소속에 놓을 때: 관계를 고르는 작은 메뉴 (DLC-형식.md '종류와 소속 관계'의 relation 표) */
    function relationMenu(plan, x, y) {
      const t = byUidM(plan.op.id);
      ctx.cmd.showMenu(
        [
          { title: `소속 → ${t ? t.name : ''} (${plan.items.length}개) · 관계` },
          { label: '관계 없음 — 상위 띠 아래에 접힘(구성)', run: () => apply(plan) },
          { sep: true },
          ...HT.RELATIONS.map(r => ({ label: r.name, run: () => apply(plan, { relation: r.id, name: `소속 → ${t ? t.name : ''} · ${r.name}` }) })),
        ],
        x,
        y
      );
    }
    /** 트랙 옮기기: 나라에 딸린 것(그 나라의 사건 · 섬긴 인물 · 아래에 접힌 나라)을 어떻게 할지 묻고, 옛 트랙의 대범위에서는 뺌(마지막 구성 정권이면 남김 — 검사 경고) */
    async function moveTrack(plan) {
      const T = plan.op.track;
      const moved = new Set(plan.items.filter(x => x.itemKind === 'period'));
      const members = [];
      for (const p of [...moved]) for (const m of p.members || []) if (m.singleHost && m.track === p.track && HT.itemKindOf(m) === 'period' && !moved.has(m) && !members.includes(m)) members.push(m);
      for (let i = 0; i < members.length; i++) for (const m of members[i].members || []) if (m.singleHost && m.track === members[i].track && HT.itemKindOf(m) === 'period' && !moved.has(m) && !members.includes(m)) members.push(m);
      const all = new Set([...moved, ...members]);
      const uids = new Set([...all].map(p => p.uid));
      const events = (state.model.events || []).filter(e => uids.has(e.polityUid) && e.track !== T && !plan.items.includes(e));
      const figures = (state.model.figures || []).filter(f => (f.services || []).some(s => uids.has(s.polityUid)));
      const scopes = arr(api.draft.scopes).filter(s => s && s.track !== T && [...moved].some(p => scopeList(s).some(raw => refHits(raw, p, s.track))));
      let withDeps = false;
      const n = members.length + events.length + figures.length;
      if (n) {
        const parts = [events.length && `사건 ${events.length}개`, figures.length && `섬긴 인물 ${figures.length}명`, members.length && `아래에 접힌 나라 ${members.length}개`].filter(Boolean).join(' · ');
        const a = await api.ask(`${moved.size ? `나라 ${moved.size}개` : `항목 ${plan.items.length}개`}를 트랙 «${(state.model.trackMap.get(T) || {}).name || T}»(으)로 옮깁니다. 딸린 것: ${parts}. 함께 옮길까요? (나라만 옮기면 딸린 사건은 옛 트랙의 그 해 나라에 붙고, 인물은 옛 트랙에서 그 나라를 찾지 못합니다)${scopes.length ? ` 옛 트랙의 대범위 ${scopes.length}개에서는 뺍니다.` : ''}`, { title: '트랙 옮기기', yes: '딸린 것도 함께 옮기기', no: '나라만 옮기기', plainNo: true });
        if (a === 'cancel') return false;
        withDeps = a === 'yes';
      }
      const items = plan.items.concat(withDeps ? members : []);
      const moveService = (item, f) => {
        const list = Array.isArray(item.service) ? item.service : [];
        if (!list.length) {
          if ((f.services || []).some(s => s.auto && uids.has(s.polityUid))) item.track = T; // 활동 기록 없이 그 나라에 저절로 놓인 사람 — 사람째로
          return;
        }
        item.service = list.map(s => {
          const raw = typeof s === 'string' ? HT.readScopeRef(s) : s && typeof s === 'object' ? { track: s.track, polity: s.polity } : null;
          const track = (raw && raw.track) || item.track;
          const hit = raw && [...all].find(p => p.track === track && (raw.polity === p.name || raw.polity === p.id || raw.polity === p.uid));
          if (!hit) return s;
          return typeof s === 'string' ? `${T}:${raw.polity}` : Object.assign({}, s, { track: T });
        });
      };
      return apply(Object.assign({}, plan, { items }), {
        extra: draft => {
          if (withDeps) {
            editItems(draft, events, item => (item.track = T));
            editItems(draft, figures, moveService);
          }
          for (const s0 of scopes) {
            const s = arr(draft.scopes).find(o => o && o.id === s0.id);
            if (!s) continue;
            const keep = scopeList(s).filter(raw => ![...moved].some(p => refHits(raw, p, s.track)));
            if (keep.length) s.members = keep; // 마지막 구성 정권이면 남김 (검사가 다른 트랙이라고 알림)
          }
        },
      });
    }
    async function perform(plan, x = 0, y = 0) {
      if (!plan || !plan.ok) return false;
      if (/^folder/.test(plan.op.type)) return folderDrop(plan);
      if (plan.op.type === 'partOf' && plan.op.id) return relationMenu(plan, x, y);
      if (plan.op.type === 'track') return moveTrack(plan);
      return apply(plan);
    }

    /* 끌기 — 메이커 안 끌기 한 꼴(HT.makerDrag.slot · js/maker-drag.js — 빈 자리 + 빈 자리 안 미리 글, 10건 D3 결정 3 C · 편집 창 블록 줄 끌기와 같음).
       누른 채 5px 넘게 움직이면 시작(누르기만 하면 지금처럼 고르기) · 끄는 줄은 제자리에서 접혀 빠지고, 놓을 곳에 빈 자리가 열려 그 안에 손 밑 사본과
       미리 글("놓으면: 민족 → ○○ (3개)") · 놓을 수 없는 곳이면 빈 자리 없이 사본 아래에 까닭 글만. 나무 끝에 가까우면 저절로 굴리고, 접힌 가지 위에 잠깐 머물면 펼침 */
    const sameDrag = (a, b) => !!a && !!b && a.type === b.type && a.id === b.id && (a.track || '') === (b.track || '');
    function payloadOf(el) {
      const label = (el.querySelector(':scope > span:not(.mk-handle)') || {}).textContent || '';
      const years = (el.querySelector(':scope > small') || {}).textContent || '';
      if (el.dataset.drag != null && !el.dataset.tuid) {
        const g = dropReg[Number(el.dataset.drag)];
        return g ? { group: Object.assign({}, g), label, years: '' } : null;
      }
      const uid = el.dataset.tuid;
      const x = byUidM(uid);
      if (!x) return null;
      /* uids = 가지에 놓아 칸을 채울 줄(시대 · 사건) · all = 작업 폴더에 넣을 줄(어느 종류든 — 인물 · 기관 · 덮어쓰기 대상도) · fromFolder = 폴더 안에서 끈 줄의 폴더 */
      const sel = api.selection();
      const all = sel.includes(uid) ? sel.filter(u => !!byUidM(u)) : [uid];
      const uids = all.filter(u => DRAG_KINDS().includes(byUidM(u).itemKind));
      return { uids, all, from: el.dataset.from || '', fromFolder: el.dataset.infolder || '', label, years };
    }
    /** 끄는 동안 접어 둘 줄 — 머리를 끌면 그 묶음 통째(머리 + 가지) */
    function liftedOf(p) {
      if (p.group) return [...treeEl.querySelectorAll('[data-drag]')].filter(el => sameDrag(dropReg[Number(el.dataset.drag)], p.group)).map(el => el.closest('.mk-tgroup') || el);
      return p.uids.flatMap(uid => [...treeEl.querySelectorAll(`[data-tuid="${CSS.escape(uid)}"]`)]);
    }
    function dropAt(at, y) {
      if (!at || !treeEl.contains(at)) return null;
      let t = at.closest('[data-drop]');
      if (!t) {
        const g = at.closest('.mk-tgroup');
        t = g && g.querySelector(':scope > .mk-tgh > [data-drop], :scope > [data-drop]');
      }
      if (!t) return null;
      const r = t.getBoundingClientRect();
      return { el: t, drop: dropReg[Number(t.dataset.drop)], pos: y < r.top + r.height / 2 ? 'before' : 'after' };
    }
    /** 빈 자리의 들여쓰기(px): 보기 갈래 나무는 --d 단계(14px), 종류별 나무는 d0 · d1 머리 아래 줄 자리 */
    const slotIndent = (el, inside) => (el.classList.contains('is-deep') ? ((Number(el.style.getPropertyValue('--d')) || 0) + (inside ? 1 : 0)) * 14 : inside ? (el.classList.contains('d1') ? 34 : 20) : el.classList.contains('d1') ? 20 : 0);
    /** 놓을 곳 → 빈 자리(HT.makerDrag.slot의 hit): 머리끼리 = 그 묶음 앞 · 뒤, 가지 머리 = 그 가지 첫 줄 자리, 나라 줄(소속으로) = 그 줄 바로 아래 */
    function hitFor(h, mods, p) {
      const plan = planFor(p, h.drop, { pos: h.pos, ctrl: mods.ctrl });
      const id = h.el.dataset.tgroup || h.el.dataset.tuid || '';
      const again = m => hitFor(h, m, p);
      if (!plan.ok) return { key: `${id}|no`, ok: false, reason: plan.reason, plan, mark: h.el, markClass: 'is-nodrop', again };
      if (plan.pos) return { key: `${id}|${plan.pos}`, ok: true, text: plan.text, plan, anchor: h.el.closest('.mk-tgroup') || h.el, where: plan.pos, indent: slotIndent(h.el, false), mark: h.el, markClass: `is-drop-${plan.pos}`, again };
      const head = !!h.el.dataset.tgroup;
      return { key: `${id}|in`, ok: true, text: plan.text, plan, anchor: head ? h.el.closest('.mk-tgh') || h.el : h.el, where: 'after', indent: slotIndent(h.el, true), mark: h.el, markClass: 'is-drop', ring: head ? h.el.closest('.mk-tgroup') : null, again };
    }
    treeDrag = HT.makerDrag.slot(treeEl, {
      grab: t => {
        const el = api.draft && t.closest && t.closest('[data-tuid], [data-drag]');
        return el && treeEl.contains(el) ? el : null;
      },
      payload: el => payloadOf(el),
      lifted: liftedOf,
      ghost: p => {
        const list = p.all || p.uids;
        const n = list ? list.length : 1;
        const x = list ? byUidM(list[0]) : null;
        const word = !x || x.itemKind === 'period' ? '나라' : x.itemKind === 'event' ? '사건' : (HT.FORMS[x.itemKind] || {}).word || '항목'; // 폴더에만 넣는 종류(인물 · 기관 …)는 제 이름
        return { name: `${p.label}${n > 1 ? ` 외 ${n - 1}` : ''}`, years: n > 1 ? '' : p.years, kind: p.group ? { track: '트랙', folder: '폴더' }[p.group.type] || '민족' : word };
      },
      hit: (x, y, mods, p, at) => {
        const h = dropAt(at, y);
        return h ? hitFor(h, mods, p) : null;
      },
      drop: (p, h, mods, ev) => perform(h.plan, ev ? ev.clientX : 0, ev ? ev.clientY : 0),
      refuse: (p, h) => h && !/^(제자리|이미)/.test(h.reason || '') && HT.toast(`놓을 수 없습니다 — ${h.reason}`), // 제자리에 도로 놓은 것은 조용히
      scroller: () => treeEl,
      hover: h => (h.mark && h.mark.dataset.tgroup && h.mark.getAttribute('aria-expanded') === 'false' && !h.mark.classList.contains('is-empty') ? h.mark.dataset.tgroup : ''),
      open: key => {
        ui.tree[key] = true;
        save();
        renderTree();
      },
      idle: '가지 머리 위에 놓으세요',
    });

    /* 머리(트랙 · 민족)의 차례를 키보드로: Alt+↑/↓ (볼거리 목록과 같은 키) · 오른쪽 클릭 메뉴. 나무 안 입력 칸의 ↑↓는 칸 옮기기로 새지 않게 */
    function orderStep(head, dir) {
      const g = dropReg[Number(head.dataset.drag)];
      if (!g) return;
      if (g.type === 'folder') return folderStep(g.id, dir); // 작업 폴더의 차례 (작업실 설정)
      const list = siblingsOf(g);
      const i = list.findIndex(x => x.id === g.id);
      const t = list[i + dir];
      if (!t) return HT.toast(dir < 0 ? '맨 위입니다.' : '맨 아래입니다.');
      const plan = planGroup(g, g.type === 'track' ? { type: 'track', track: t.id } : { type: 'people', id: t.id, track: g.track }, dir < 0 ? 'before' : 'after');
      if (!plan.ok) return HT.toast(`차례를 바꿀 수 없습니다 — ${plan.reason}`);
      const key = head.dataset.tgroup;
      apply(plan).then(ok => ok && treeEl.querySelector(`[data-tgroup="${CSS.escape(key)}"]`)?.focus({ preventScroll: false }));
    }
    function headMenu(head, x, y) {
      const g = dropReg[Number(head.dataset.drag)];
      if (!g) return;
      const tadd = head.parentElement && head.parentElement.querySelector('.mk-tadd');
      ctx.cmd.showMenu(
        [
          { title: head.querySelector('span') ? head.querySelector('span').textContent : '' },
          { label: '차례 위로', key: 'Alt+↑', run: () => orderStep(head, -1) },
          { label: '차례 아래로', key: 'Alt+↓', run: () => orderStep(head, 1) },
          ...(tadd ? [{ sep: true }, { label: tadd.textContent, run: () => startAdd(tadd) }] : []),
        ],
        x,
        y
      );
    }
    treeEl.addEventListener(
      'keydown',
      e => {
        if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
        if (e.target.closest('.mk-tnew')) return e.stopPropagation();
        if (!e.altKey) return;
        const head = e.target.closest('[data-drag]');
        if (!head) return;
        e.preventDefault();
        e.stopPropagation();
        orderStep(head, e.key === 'ArrowUp' ? -1 : 1);
      },
      true
    );

    /* '＋ 민족' · '＋ 가문': 가지 머리 아래에 이름 칸 하나 — Enter로 사전에 더하고 그 가지 아래에 생김(Esc · 비운 채 떠나면 그만둠) */
    function startAdd(btn) {
      const a = dropReg[Number(btn.dataset.tadd)];
      if (!a || !api.draft) return;
      for (const el of treeEl.querySelectorAll('.mk-tnew')) el.remove();
      const head = btn.closest('.mk-tgh');
      const depth = Number(head.querySelector('.mk-tg').style.getPropertyValue('--d') || 0) + 1;
      const word = ADD_WORD[a.type];
      head.insertAdjacentHTML('afterend', `<div class="mk-tnew is-deep" style="--d:${depth}"><input maxlength="40" autocomplete="off" spellcheck="false" aria-label="새 ${word} 이름 — Enter로 더하고 Esc로 그만둡니다"></div>`);
      const box = head.nextElementSibling;
      const input = box.querySelector('input');
      input.focus();
      input.addEventListener('keydown', e => {
        if (e.isComposing) return;
        if (e.key === 'Enter') {
          e.preventDefault();
          addDict(a, input.value);
        } else if (e.key === 'Escape') {
          e.preventDefault();
          e.stopPropagation();
          box.remove();
          btn.focus();
        }
      });
      input.addEventListener('blur', () => setTimeout(() => box.isConnected && !input.value.trim() && box.remove(), 0));
    }
    async function addDict(a, text) {
      const name = str(text);
      if (!name) return;
      const people = a.type === 'people';
      const word = ADD_WORD[a.type];
      const list = people ? 'peoples' : 'houses';
      const map = (people ? state.model.peopleMap : state.model.houseMap) || new Map();
      if ([...map.values()].some(x => x.name === name) || arr(api.draft[list]).some(x => x && x.name === name)) return HT.toast(`같은 이름의 ${word}이(가) 이미 있습니다 — 나라 줄을 그 가지에 놓으면 됩니다.`);
      const parent = a.parent ? map.get(a.parent) : null;
      const id = HT.makerKit.uniqueId(`${people ? 'people' : 'h'}-${HT.hash(name)}`, new Set([...map.keys(), ...arr(api.draft[list]).map(x => x && x.id)]));
      const def = Object.assign({ id, name }, parent ? { parent: dictRef(parent, map) } : {});
      bornIn.set(`${a.type}:${id}`, a.track);
      for (const el of treeEl.querySelectorAll('.mk-tnew')) el.remove();
      const ok = await api.transact(d => {
        d[list] = arr(d[list]).concat(def);
        return d;
      }, `${word} «${name}» 더함`);
      if (!ok) return bornIn.delete(`${a.type}:${id}`);
      const key = `v:${treeUi.view}:${a.track}:${id}`;
      const el = treeEl.querySelector(`[data-tgroup="${CSS.escape(key)}"]`);
      if (el) {
        el.scrollIntoView({ block: 'nearest' });
        el.focus({ preventScroll: true });
      }
      HT.toast(`${word} «${name}»을(를) 더했습니다 — 나라 줄을 끌어 이 가지에 놓으세요.`, 'ok');
    }

    /* '옮기기…' — 끌기와 같은 일을 키보드로: 갈 곳 목록(지금 보기 갈래의 모든 가지 · 소속으로는 나라 줄까지)에서 고름. 놓을 수 없는 곳은 까닭과 함께 흐리게 */
    function moveSources() {
      if (!api.draft) return [];
      const kinds = DRAG_KINDS();
      const ok = u => {
        const x = byUidM(u);
        return !!x && kinds.includes(x.itemKind);
      };
      const sel = api.selection().filter(ok);
      const cur = current();
      if (sel.length && (!cur || sel.includes(cur) || sel.length > 1)) return sel;
      return cur && ok(cur) ? [cur] : [];
    }
    function moveTargets() {
      const out = folders().map(f => ({ label: `작업 폴더 › ${f.name}`, drop: { type: 'folder', id: f.id } })); // 폴더에 넣기 — 끌어 놓기와 같음 (10건 D3 결정 7 A)
      if (treeUi.view === 'kind') {
        for (const t of state.model.tracks)
          for (const [kind, word] of [['period', '객체'], ['event', '사건']]) out.push({ label: `${word} — ${t.name}`, drop: { type: 'track', track: t.id, kinds: [kind] } });
        return out;
      }
      const rows = (list, path) =>
        list.forEach(r => {
          if (r.drop) out.push({ label: [...path, r.name].join(' › '), drop: r.drop });
          rows(r.kids || [], [...path, r.name]);
        });
      const walk = (g, path) => {
        const p = path.concat(g.label);
        if (g.drop) out.push({ label: p.join(' › '), drop: g.drop });
        (g.kids || []).forEach(k => walk(k, p));
        rows(g.rows || [], p);
      };
      viewTree().forEach(g => walk(g, []));
      return out;
    }
    let moveBox = null;
    function openMove(uids = moveSources(), from = '') {
      if (!uids.length) return HT.toast(treeUi.view === 'kind' ? '옮길 시대나 사건을 먼저 고르세요.' : '옮길 나라를 먼저 고르세요.');
      const payload = { uids, from };
      const targets = moveTargets().map(t => Object.assign(t, { plan: planFor(payload, t.drop) }));
      if (!moveBox) {
        moveBox = document.createElement('dialog');
        moveBox.className = 'dlc-dialog mk-box mk-move';
        document.body.appendChild(moveBox);
        moveBox.addEventListener('click', e => {
          if (e.target === moveBox || e.target.closest('[data-close]')) return moveBox.close();
          const b = e.target.closest('[data-move]');
          if (!b || b.disabled) return;
          const t = moveBox._targets[Number(b.dataset.move)];
          const r = b.getBoundingClientRect();
          moveBox.close();
          perform(t.plan, r.left + 24, r.bottom);
        });
        moveBox.addEventListener('input', e => {
          if (!e.target.matches('[data-move-find]')) return;
          const q = e.target.value.trim().toLowerCase();
          for (const b of moveBox.querySelectorAll('[data-move]')) b.hidden = !!q && !b.firstElementChild.textContent.toLowerCase().includes(q); // 갈 곳의 이름(경로)으로만
        });
        moveBox.addEventListener('keydown', e => {
          if (e.isComposing || (e.key !== 'ArrowDown' && e.key !== 'ArrowUp')) return;
          const list = [...moveBox.querySelectorAll('[data-move]:not([disabled]):not([hidden])')];
          const i = list.indexOf(document.activeElement);
          const next = list[i < 0 ? (e.key === 'ArrowDown' ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))];
          if (!next) return;
          e.preventDefault();
          next.focus();
        });
      }
      moveBox._targets = targets;
      const view = (TREE_VIEWS.find(([v]) => v === treeUi.view) || [])[1];
      moveBox.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>옮기기 — ${uids.length}개</h2><button type="button" class="icon-btn" data-close aria-label="닫기">✕</button></div><div class="dlg-body"><p class="hint">구조 나무의 보기 갈래 «${esc(view)}»의 갈 곳입니다 — 고르면 끌어 놓은 것과 같습니다(되돌리기 한 걸음). ↑↓로 고르고 Enter. 다른 칸을 채우려면 나무 위의 보기 갈래를 바꾸세요.</p><label class="field mk-move-find"><span>찾기</span><input data-move-find autocomplete="off" aria-label="갈 곳 찾기 — 이름 일부"></label><div class="mk-move-list" role="listbox" aria-label="갈 곳">${
        targets.length
          ? targets.map((t, i) => `<button type="button" role="option" data-move="${i}"${t.plan.ok ? '' : ' disabled'}><span>${esc(t.label)}</span><small>${esc(t.plan.ok ? t.plan.text.replace(/^놓으면: /, '') : t.plan.reason)}</small></button>`).join('')
          : '<p class="hint">갈 곳이 없습니다.</p>'
      }</div></div></div>`;
      moveBox.showModal();
      moveBox.querySelector('[data-move-find]').focus();
    }

    /* ---------- 작업 폴더 (10건 D3 결정 7 A) — 나무 맨 위 갈래 · 폴더 메뉴 · 끌어 놓기 · '폴더에 넣기…' · 집합 보기로 내보내기 ----------
       폴더는 작업실 설정(FOLDER_KEY — 이 브라우저, DLC 파일에 들어가지 않음)이라 넣기 · 빼기 · 이름 · 색 · 차례는 작업본의 고침(되돌리기)이 아닙니다.
       '집합 보기로 내보내기'만 작업본 고침 한 번(api.transact — 형식 3 views 항목 하나). 폴더 안의 줄은 바로 가기(data-tuid 그대로 — 누르면 고치기 · 끌면 같은 꼴 ·
       오른쪽 클릭 메뉴도 같고 '폴더에서 빼기'가 더 있음). 끌어 놓기는 구조 나무 끌기와 같은 꼴(빈 자리 + 미리 글 — HT.makerDrag.slot)이고 Ctrl을 누른 채 놓으면 원래 폴더에도 남음 */
    const FOLDER_COLORS = ['버터', '스카이', '민트', '라벤더', '피치', '핑크', '세이지', '페리윙클', '로즈', '샌드', '슬레이트', '모카'].map(n => (HT.PASTEL || []).find(c => c.name === n)).filter(Boolean).map(c => c.id);
    const afterRender = fn => queueMicrotask(fn); // 보기 갈래의 나무는 마이크로태스크에 그려지므로(renderTree) 그 뒤에
    function folders() {
      return api.draft ? readFolders(HT.store.get(FOLDER_KEY, null), api.draft.id) : [];
    }
    function saveFolders(list) {
      if (!api.draft) return;
      const all = HT.store.get(FOLDER_KEY, null);
      const o = all && typeof all === 'object' && !Array.isArray(all) ? all : {};
      if (list.length) o[api.draft.id] = list;
      else delete o[api.draft.id];
      if (!HT.store.set(FOLDER_KEY, o)) HT.toast('작업 폴더를 브라우저에 저장하지 못했습니다.', 'error');
      renderTree();
    }
    function newFolder(list, name = '', items = []) {
      let nm = str(name).slice(0, FOLDER_LIMITS.name);
      if (!nm) {
        nm = '새 폴더';
        for (let n = 2; list.some(f => f.name === nm); n++) nm = `새 폴더 ${n}`;
      }
      const used = new Set(list.map(f => f.color));
      let id;
      do id = `f-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
      while (list.some(f => f.id === id));
      return { id, name: nm, color: FOLDER_COLORS.find(c => !used.has(c)) || FOLDER_COLORS[list.length % FOLDER_COLORS.length] || '', items: [...new Set(items)].slice(0, FOLDER_LIMITS.items) };
    }
    const folderRow = (uid, fid) => {
      const x = byUidM(uid);
      return x ? { uid, fid, name: x.title || x.name || x.id, years: yearsOf(x), color: x.color || '' } : null;
    };
    const fRowHTML = r =>
      `<button type="button" class="mk-trow d2${api.selection().includes(r.uid) ? ' is-sel' : ''}" data-tuid="${esc(r.uid)}" data-infolder="${esc(r.fid)}" role="treeitem"><span class="mk-handle" aria-hidden="true">⋮⋮</span><i${r.color ? ` style="--c:${esc(r.color)}"` : ' class="is-none"'} aria-hidden="true"></i><span>${esc(r.name)}</span>${r.years ? `<small>${esc(r.years)}</small>` : ''}</button>`;
    /** 나무 맨 위(팩 줄 바로 아래)의 '작업 폴더' 갈래 — 어느 보기 갈래에서든 같음. 찾는 중이면 폴더 이름 · 줄 이름 · 해로 거르고, 맞는 것이 없으면 갈래째 숨김 */
    function folderSecHTML() {
      if (!api.draft) return '';
      const list = folders();
      const q = str(findEl.value).toLowerCase();
      const hit = r => r.name.toLowerCase().includes(q) || String(r.years || '').toLowerCase().includes(q);
      const shown = list
        .map(f => {
          const rows = f.items.map(u => folderRow(u, f.id)).filter(Boolean);
          const named = !q || f.name.toLowerCase().includes(q);
          return { f, rows: named ? rows : rows.filter(hit), n: rows.length, keep: named || rows.some(hit) };
        })
        .filter(x => x.keep);
      if (q && !shown.length) return '';
      const open = q ? true : ui.tree.folders !== false;
      const head = `<div class="mk-tgh"><button type="button" class="mk-tg d0" data-tgroup="folders" aria-expanded="${open}" data-drop="${reg({ type: 'folder-new' })}" title="작업 폴더 — 지금 고치는 것을 묶어 두는 곳(바로 가기 · 이 작업실에만 남고 DLC 파일에는 들어가지 않음). 항목 줄을 이 머리에 놓으면 새 폴더를 만들어 넣습니다"><i class="car" aria-hidden="true">${open ? '▾' : '▸'}</i><span>작업 폴더</span><small>${list.length}</small></button><button type="button" class="mk-tadd" data-fnew title="새 폴더 — 이름만 치면 됩니다" aria-label="새 폴더">＋</button></div>`;
      const body = !open
        ? ''
        : shown.length
          ? shown
              .map(({ f, rows, n }) => {
                const fo = !!q || ui.tree[`folder:${f.id}`] !== false;
                const inner = fo ? rows.slice(0, CAP).map(fRowHTML).join('') + (rows.length > CAP ? `<p class="mk-more">… ${rows.length - CAP}개 더 — 위 찾기 칸으로 좁히세요</p>` : '') : '';
                return `<div class="mk-tgroup" role="group"><div class="mk-tgh"><button type="button" class="mk-tg d1 mk-fhead" data-tgroup="folder:${esc(f.id)}" data-folder="${esc(f.id)}" aria-expanded="${fo && n > 0}" data-drop="${reg({ type: 'folder', id: f.id })}" data-drag="${reg({ type: 'folder', id: f.id })}" title="${esc(`폴더 «${f.name}» — 항목 줄을 끌어 놓으면 넣습니다 · 오른쪽 클릭은 폴더 메뉴(이름 · 색 · 집합 보기로 내보내기) · F2 이름 바꾸기 · Alt+↑↓ 차례 · Delete 폴더 지우기`)}"><i class="car" aria-hidden="true">${n ? (fo ? '▾' : '▸') : ''}</i><i class="mk-fold" style="--f:${esc(f.color)}" aria-hidden="true"></i><span>${esc(f.name)}</span><small>${n}</small></button></div>${inner}</div>`;
              })
              .join('')
          : `<p class="mk-thint mk-fhint">＋로 폴더를 만들거나 항목 줄을 이 머리에 끌어 놓으면 새 폴더에 들어갑니다 — 폴더의 항목은 바로 가기라 제자리에 그대로 있습니다.</p>`;
      return `<div class="mk-tgroup mk-fsec" role="group">${head}${body}</div>`;
    }
    /** 폴더에 놓기 계획 — 줄(들) → 폴더 · '작업 폴더' 머리(새 폴더) / 폴더 머리 → 폴더 머리(차례). 작업본은 그대로(작업실 설정) */
    function planFolder(p, drop, { pos, ctrl }) {
      const list = folders();
      if (p.group) {
        if (p.group.type !== 'folder') return { ok: false, reason: '작업 폴더에는 항목 줄을 놓습니다' };
        if (drop.type !== 'folder') return { ok: false, reason: '폴더는 폴더 머리끼리 끌어 차례를 바꿉니다' };
        const t = list.find(f => f.id === drop.id);
        if (!t || drop.id === p.group.id) return { ok: false, reason: '제자리' };
        const ids = list.map(f => f.id).filter(id => id !== p.group.id);
        const at = ids.indexOf(drop.id) + (pos === 'after' ? 1 : 0);
        const next = ids.slice(0, at).concat(p.group.id, ids.slice(at));
        if (next.join('\n') === list.map(f => f.id).join('\n')) return { ok: false, reason: '제자리' };
        return { ok: true, pos, text: `놓으면: 차례 — «${t.name}» ${pos === 'before' ? '앞' : '뒤'}으로`, op: { type: 'folder-order', order: next } };
      }
      const all = p.all || p.uids || [];
      if (!all.length) return { ok: false, reason: '넣을 항목이 없음' };
      const from = p.fromFolder ? list.find(f => f.id === p.fromFolder) || null : null;
      const out = from && !ctrl ? from : null; // 폴더 안에서 끌어 왔으면 거기서 뺌 (Ctrl이면 남김 — 대범위 끌기와 같은 말)
      const keep = from && !ctrl ? ' — Ctrl을 누른 채 놓으면 원래 폴더에도 남음' : '';
      if (drop.type === 'folder-new') return { ok: true, text: `놓으면: 새 폴더를 만들어 넣음 (${all.length}개)${out ? ` · «${out.name}»에서 뺌` : ''}${keep}`, op: { type: 'folder-new', from: out ? out.id : '' }, items: all };
      const f = list.find(x => x.id === drop.id);
      if (!f) return { ok: false, reason: '폴더를 찾지 못함' };
      if (from && from.id === f.id) return { ok: false, reason: '제자리' };
      const add = all.filter(u => !f.items.includes(u));
      if (!add.length && !out) return { ok: false, reason: '이미 이 폴더에 있음' };
      const skip = all.length - add.length;
      return { ok: true, text: `놓으면: 폴더 «${f.name}»에 넣음 (${add.length}개)${skip ? ` · ${skip}개는 이미 있음` : ''}${out ? ` · «${out.name}»에서 뺌` : ''}${keep}`, op: { type: 'folder', id: f.id, from: out ? out.id : '' }, items: all };
    }
    function folderDrop(plan) {
      const op = plan.op;
      const list = folders();
      if (op.type === 'folder-order') {
        const by = new Map(list.map(f => [f.id, f]));
        saveFolders(op.order.map(id => by.get(id)).filter(Boolean));
        return true;
      }
      const items = plan.items || [];
      const from = op.from ? list.find(f => f.id === op.from) : null;
      if (from) from.items = from.items.filter(u => !items.includes(u));
      if (op.type === 'folder-new') {
        const f = newFolder(list, '', items);
        list.push(f);
        ui.tree.folders = true;
        save();
        saveFolders(list);
        startFolderRename(f.id); // 놓자마자 이름 칸 (Enter · 비우고 떠나면 '새 폴더' 그대로)
        return true;
      }
      const f = list.find(x => x.id === op.id);
      if (!f) return false;
      f.items = [...new Set(f.items.concat(items))].slice(0, FOLDER_LIMITS.items);
      if (ui.tree[`folder:${f.id}`] === false) {
        ui.tree[`folder:${f.id}`] = true; // 넣은 것이 보이게 폄
        save();
      }
      saveFolders(list);
      return true;
    }
    function folderAdd(id, uids) {
      const list = folders();
      const f = list.find(x => x.id === id);
      if (!f) return;
      f.items = [...new Set(f.items.concat(uids))].slice(0, FOLDER_LIMITS.items);
      saveFolders(list);
    }
    function folderRemove(id, uids) {
      const list = folders();
      const f = list.find(x => x.id === id);
      if (!f) return;
      f.items = f.items.filter(u => !uids.includes(u));
      saveFolders(list);
    }
    function folderStep(id, dir) {
      const list = folders();
      const i = list.findIndex(f => f.id === id);
      const j = i + dir;
      if (i < 0) return;
      if (j < 0 || j >= list.length) return HT.toast(dir < 0 ? '맨 위입니다.' : '맨 아래입니다.');
      [list[i], list[j]] = [list[j], list[i]];
      saveFolders(list);
      afterRender(() => treeEl.querySelector(`[data-folder="${CSS.escape(id)}"]`)?.focus());
    }
    /** 나무 안 이름 칸 하나(새 폴더 · 이름 바꾸기 — 민족 · 가문 '＋'의 칸과 같은 꼴): Enter로 정하고 Esc로 그만둠 · 칸을 떠나면 적은 대로.
        done(이름 | null(Esc), 키로 끝냈는지 — 칸을 떠난 것이면 초점을 옮기지 않음: 사람이 누른 곳에 그대로) */
    function nameBox(after, depth, value, label, done) {
      for (const el of treeEl.querySelectorAll('.mk-tnew')) el.remove();
      after.insertAdjacentHTML('afterend', `<div class="mk-tnew is-deep" style="--d:${depth}"><input maxlength="${FOLDER_LIMITS.name}" autocomplete="off" spellcheck="false" aria-label="${esc(label)}"></div>`);
      const box = after.nextElementSibling;
      const input = box.querySelector('input');
      input.value = value;
      input.focus();
      input.select();
      let over = false;
      const finish = (ok, byKey) => {
        if (over) return;
        over = true;
        box.remove();
        done(ok ? str(input.value) : null, byKey);
      };
      input.addEventListener('keydown', e => {
        if (e.isComposing) return;
        if (e.key === 'Enter') {
          e.preventDefault();
          finish(true, true);
        } else if (e.key === 'Escape') {
          e.preventDefault();
          e.stopPropagation();
          finish(false, true);
        }
      });
      input.addEventListener('blur', () => setTimeout(() => box.isConnected && finish(true, false), 0));
    }
    function startFolderNew() {
      if (!api.draft) return;
      if (ui.tree.folders === false) {
        ui.tree.folders = true;
        save();
        renderTree();
      }
      afterRender(() => {
        const head = treeEl.querySelector('.mk-fsec > .mk-tgh');
        if (!head) return;
        nameBox(head, 1, '', '새 폴더 이름 — Enter로 만들고 Esc로 그만둡니다', (name, byKey) => {
          if (!name) return byKey && head.isConnected && head.querySelector('[data-fnew]').focus();
          const list = folders();
          const f = newFolder(list, name);
          list.push(f);
          saveFolders(list);
          if (byKey) afterRender(() => treeEl.querySelector(`[data-folder="${CSS.escape(f.id)}"]`)?.focus());
        });
      });
    }
    function startFolderRename(id) {
      afterRender(() => {
        const btn = treeEl.querySelector(`[data-folder="${CSS.escape(id)}"]`);
        const f = folders().find(x => x.id === id);
        if (!btn || !f) return;
        nameBox(btn.closest('.mk-tgh'), 2, f.name, `폴더 «${f.name}»의 이름 — Enter로 바꾸고 Esc로 그만둡니다`, (name, byKey) => {
          if (name && name !== f.name) {
            const list = folders();
            const g = list.find(x => x.id === id);
            if (g) {
              g.name = name.slice(0, FOLDER_LIMITS.name);
              saveFolders(list);
            }
          }
          if (byKey) afterRender(() => treeEl.querySelector(`[data-folder="${CSS.escape(id)}"]`)?.focus());
        });
      });
    }
    async function deleteFolder(id) {
      const f = folders().find(x => x.id === id);
      if (!f) return;
      if (f.items.length) {
        const a = await api.ask(`폴더 «${f.name}»을(를) 지웁니다. 든 항목 ${f.items.length}개는 제자리에 그대로 남습니다(폴더는 바로 가기 묶음). 폴더는 작업실 설정이라 되돌리기로 돌아오지 않습니다.`, { title: '폴더 지우기', yes: '폴더 지우기', no: '', danger: true });
        if (a !== 'yes') return;
      }
      saveFolders(folders().filter(x => x.id !== id));
      afterRender(() => treeEl.querySelector('[data-tgroup="folders"]')?.focus());
    }
    /** '폴더에 넣기…' — 항목 메뉴(오른쪽 클릭)에서: 폴더 목록 · 새 폴더 */
    function folderPick(uids, x, y) {
      if (!api.draft || !uids.length) return;
      const list = folders();
      ctx.cmd.showMenu(
        [
          { title: `폴더에 넣기 — ${uids.length}개` },
          ...list.map(f => {
            const has = uids.every(u => f.items.includes(u));
            return { label: f.name, checked: has, disabled: has, run: has ? null : () => folderAdd(f.id, uids) };
          }),
          ...(list.length ? [{ sep: true }] : []),
          {
            label: '＋ 새 폴더에 넣기',
            run: () => {
              const l = folders();
              const f = newFolder(l, '', uids);
              l.push(f);
              ui.tree.folders = true;
              save();
              saveFolders(l);
              startFolderRename(f.id);
            },
          },
        ],
        x,
        y
      );
    }
    /** 폴더를 이 DLC의 집합 보기(형식 3 views 항목 하나)로 — 같은 이름이 있으면 구성 나라를 바꿈. 집합 보기에는 나라만 듦(사건 · 인물은 알리고 뺌) */
    async function folderToView(id) {
      const f = folders().find(v => v.id === id);
      const d = api.draft;
      if (!f || !d) return;
      const xs = f.items.map(byUidM).filter(Boolean);
      const pols = xs.filter(v => HT.itemKindOf(v) === 'period');
      if (!pols.length) return HT.toast('폴더에 나라가 없어 집합 보기를 만들 수 없습니다 — 집합 보기에는 나라만 듭니다.', 'error');
      const counts = new Map();
      for (const v of xs) {
        const w = HT.itemKindOf(v) === 'period' ? '나라' : (HT.FORMS[v.itemKind] || {}).word || '항목';
        counts.set(w, (counts.get(w) || 0) + 1);
      }
      const what = [...counts].map(([w, n]) => `${w} ${n}`).join(' · ');
      const others = xs.length - pols.length;
      const same = arr(d.views).find(v => v && str(v.name) === f.name);
      const a = await api.ask(
        `폴더 «${f.name}»(${what})의 나라 ${pols.length}개로 이 DLC의 집합 보기 «${f.name}»을(를) ${same ? '다시 짭니다 — 같은 이름의 집합 보기의 구성 나라를 이 폴더의 나라로 바꿉니다' : '더합니다'}.${others ? ` 집합 보기에는 나라만 들어 ${others}개는 빠집니다.` : ''} 집합 보기는 DLC 파일에 담겨(형식 3) 반영하면 연표의 집합 보기 목록에 나옵니다. 되돌리기 한 번에 돌아옵니다.`,
        { title: '집합 보기로 내보내기', yes: same ? '구성 나라 바꾸기' : '집합 보기 더하기', no: '' }
      );
      if (a !== 'yes') return;
      /* 구성 나라 참조: { track, polity } — 같은 트랙에 같은 이름이 있으면 id(이 DLC) · uid(불러온 팩)로 (DLC-형식.md 'views') */
      const members = pols.map(p => ({ track: p.track, polity: state.model.periods.some(q => q !== p && q.track === p.track && HT.itemKindOf(q) === 'period' && q.name === p.name) ? (p.packId === d.id ? p.id : p.uid) : p.name }));
      let vid = '';
      const ok = await api.transact(draft => {
        draft.views = arr(draft.views);
        const hit = draft.views.find(v => v && str(v.name) === f.name);
        if (hit) {
          hit.members = members;
          vid = str(hit.id);
        } else {
          const taken = new Set([...draft.views.map(v => v && v.id), ...(state.model.viewMap ? state.model.viewMap.keys() : [])]);
          vid = HT.makerKit.uniqueId(`v-${HT.hash(f.name)}`, taken);
          draft.views.push(Object.assign({ id: vid, name: f.name, members }, HT.isColor(f.color) ? { color: f.color } : {}));
        }
        return draft;
      }, `폴더 «${f.name}» → 집합 보기`);
      if (!ok) return;
      const v = vid && state.model.viewMap ? state.model.viewMap.get(vid) : null;
      const miss = v ? pols.length - v.members.length : 0;
      HT.toast(`집합 보기 «${f.name}»에 나라 ${pols.length}개를 담았습니다${miss > 0 ? ` — ${miss}개는 찾지 못했습니다(검사 창)` : ''}. 반영하면 연표의 집합 보기 목록에 나옵니다.`, miss > 0 ? 'error' : 'ok');
    }
    /* 폴더 메뉴 — 오른쪽 누름 메뉴(.ctx-menu)와 같은 꼴에 색 견본 한 줄(파스텔 열둘). 견본을 고르면 메뉴는 그대로 두고 색만 바꿈 */
    let fmenu = null;
    function closeFolderMenu(back) {
      if (!fmenu || fmenu.hidden) return;
      fmenu.hidden = true;
      if (back) treeEl.querySelector(`[data-folder="${CSS.escape(fmenu._id || '')}"]`)?.focus({ preventScroll: true });
    }
    function folderMenuHTML(f) {
      const xs = f.items.map(byUidM).filter(Boolean);
      const pols = xs.filter(v => HT.itemKindOf(v) === 'period');
      const gone = f.items.length - xs.length;
      const entries = [
        { label: '이름 바꾸기', key: 'F2', run: () => startFolderRename(f.id) },
        { swatches: true },
        { label: '집합 보기로 내보내기…', disabled: !pols.length, sub: pols.length ? `나라 ${pols.length}` : '나라가 없음', run: () => folderToView(f.id) },
        { label: '폴더 안 항목 모두 고르기', disabled: !xs.length, run: () => api.selectItems(xs.map(v => v.uid)) },
        ...(gone ? [{ label: `없어진 항목 ${gone}개 정리`, sub: '지웠거나 꺼진 팩의 항목', run: () => folderRemove(f.id, f.items.filter(u => !byUidM(u))) }] : []),
        { sep: true },
        { label: '폴더 지우기 — 항목은 그대로', key: 'Delete', danger: true, run: () => deleteFolder(f.id) },
      ];
      const runs = [];
      const html = entries
        .map(it => {
          if (it.sep) return '<div class="ctx-sep"></div>';
          if (it.swatches)
            return `<div class="ctx-title">색</div><div class="mk-fsw" role="radiogroup" aria-label="폴더 색">${(HT.PASTEL || []).map(c => `<button type="button" role="radio" data-fsw="${c.id}" style="--c:${c.id}" aria-checked="${c.id === f.color}" aria-label="${esc(c.name)}" title="${esc(c.name)}"${c.id === f.color ? ' class="is-on"' : ''}></button>`).join('')}</div>`;
          runs.push(it.run);
          return `<button type="button" class="ctx-item${it.disabled ? ' is-disabled' : ''}${it.danger ? ' is-danger' : ''}" role="menuitem" data-i="${runs.length - 1}"${it.disabled ? ' aria-disabled="true"' : ''}><span class="ctx-label">${esc(it.label)}</span>${it.sub ? `<span class="mk-sub">${esc(it.sub)}</span>` : ''}${it.key ? `<span class="ctx-key">${esc(it.key)}</span>` : ''}</button>`;
        })
        .join('');
      return { runs, html: `<div class="ctx-title">${esc(`폴더 — ${f.name}`)}</div>${html}<div class="ctx-foot">항목을 폴더에 끌어 놓거나, 항목 메뉴의 '폴더에 넣기…'로 넣습니다 — 폴더는 이 작업실에만 남습니다</div>` };
    }
    function folderMenu(id, x, y) {
      const f = folders().find(v => v.id === id);
      if (!f) return;
      ctx.cmd.hideMenu();
      if (!fmenu) {
        fmenu = document.body.appendChild(Object.assign(document.createElement('div'), { className: 'ctx-menu mk-bmenu mk-fmenu', hidden: true }));
        fmenu.setAttribute('role', 'menu');
        fmenu.addEventListener('click', e => {
          const sw = e.target.closest('[data-fsw]');
          if (sw) {
            const list = folders();
            const g = list.find(v => v.id === fmenu._id);
            if (!g) return closeFolderMenu(false);
            g.color = sw.dataset.fsw;
            saveFolders(list);
            for (const b of fmenu.querySelectorAll('[data-fsw]')) {
              const on = b === sw;
              b.classList.toggle('is-on', on);
              b.setAttribute('aria-checked', String(on));
            }
            return;
          }
          const b = e.target.closest('.ctx-item');
          if (!b || b.classList.contains('is-disabled')) return;
          const run = fmenu._runs[Number(b.dataset.i)];
          closeFolderMenu(false);
          if (run) run();
        });
        fmenu.addEventListener('keydown', e => {
          if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            return closeFolderMenu(true);
          }
          if (e.key === 'Tab') return closeFolderMenu(false);
          const sws = [...fmenu.querySelectorAll('[data-fsw]')];
          const si = sws.indexOf(document.activeElement);
          if (si >= 0 && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
            e.preventDefault();
            return sws[(si + (e.key === 'ArrowRight' ? 1 : -1) + sws.length) % sws.length].focus();
          }
          if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
          e.preventDefault();
          e.stopPropagation();
          const stops = [...fmenu.querySelectorAll('.ctx-item:not(.is-disabled)')];
          const sw = fmenu.querySelector('[data-fsw].is-on') || sws[0];
          if (sw) stops.splice(1, 0, sw); // 이름 바꾸기 다음이 색 줄 (줄 안은 ←→)
          const at = si >= 0 ? stops.indexOf(sw) : stops.indexOf(document.activeElement);
          const next = stops[(at + (e.key === 'ArrowDown' ? 1 : -1) + stops.length) % stops.length];
          if (next) next.focus();
        });
        document.addEventListener('pointerdown', e => fmenu && !fmenu.hidden && !fmenu.contains(e.target) && closeFolderMenu(false), true);
        window.addEventListener('blur', () => closeFolderMenu(false));
      }
      const m = folderMenuHTML(f);
      fmenu._id = id;
      fmenu._runs = m.runs;
      fmenu.innerHTML = m.html;
      fmenu.hidden = false;
      fmenu.style.left = '0px';
      fmenu.style.top = '0px';
      const r = fmenu.getBoundingClientRect();
      fmenu.style.left = `${Math.max(4, Math.min(x, innerWidth - r.width - 4))}px`;
      fmenu.style.top = `${Math.max(4, Math.min(y, innerHeight - r.height - 4))}px`;
      const first = fmenu.querySelector('.ctx-item:not(.is-disabled)');
      if (first) first.focus({ preventScroll: true });
    }
    /* 폴더 머리의 키: F2 이름 바꾸기 · Delete 폴더 지우기(항목은 그대로) — 작업실의 F2 · Delete(고른 항목)보다 먼저 (Alt+↑↓ 차례는 위 orderStep) */
    treeEl.addEventListener('keydown', e => {
      if (e.isComposing || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
      const fh = e.target.closest && e.target.closest('[data-folder]');
      if (!fh || (e.key !== 'F2' && e.key !== 'Delete')) return;
      e.preventDefault();
      e.stopPropagation();
      if (e.key === 'F2') startFolderRename(fh.dataset.folder);
      else deleteFolder(fh.dataset.folder);
    });

    for (const ev of ['pointerup', 'keyup']) document.addEventListener(ev, () => queueMicrotask(() => { syncTreeSel(); updateTools(); }));
    new MutationObserver(syncTreeSel).observe(pane, { attributes: true, attributeFilter: ['hidden'] });
    new MutationObserver(syncTreeSel).observe(detail, { attributes: true, attributeFilter: ['hidden'] });

    /* ---------- 가운데 탭: 연표 · 편집 표 · 문서 ---------- */
    const centerEl = $('#mkCenter');
    const wikiEl = $('#wikiPane');
    const grid = HT.makerGrid.mount(centerEl, ctx, api, ui.grid, save);
    function openTable(list) {
      if (!HT.makerGrid.words[list]) return api.openBaseTools(list); // 편집 표가 없는 바탕 표(「주기」 — 줄에 id · 이름이 없음)는 바탕 창으로(5단계 과제 6)
      setCenter('table');
      grid.show(list);
    }
    const finder = HT.makerFind.mount(ctx, { ...api, get draft() { return api.draft; }, ui, remember: save, commands: () => [...COMMANDS, ...ctx.cmd.addKinds().map(kind => ({ label: `＋ ${HT.FORMS[kind].word}`, key: ctx.cmd.addKeyOf(kind), run: () => api.draft && ctx.cmd.openAdd(kind) })), ...(api.templates ? api.templates.commands() : [])], run, table: openTable, timeline: () => setCenter('timeline') });
    const docsHTML = () => {
      const d = api.draft;
      const rows = d ? (treeOf(d).find(g => g.key === 'docs') || { rows: [] }).rows : [];
      return `<div class="mk-center-card"><h3>문서</h3>${
        rows.length
          ? `<p class="hint">이 DLC의 문서 ${rows.length}개 — 누르면 엽니다. 연표나 구조에서 항목을 고른 채 [문서]를 누르면 그 항목의 문서가 열립니다.</p><ul>${rows.map(r => `<li><button type="button" data-center-doc="${esc(r.doc)}">${esc(r.name)}</button></li>`).join('')}</ul>`
          : '<p class="hint">아직 문서가 없습니다 — 항목을 고르고 오른쪽의 📄 문서 만들기로 씁니다.</p>'
      }</div>`;
    };

    function paintCenter() {
      for (const b of $('#mkCTabs').querySelectorAll('[data-ctab]')) {
        const on = b.dataset.ctab === center;
        b.classList.toggle('is-on', on);
        b.setAttribute('aria-selected', String(on));
      }
      centerEl.hidden = center === 'timeline' || (center === 'wiki' && !wikiEl.hidden);
      centerEl.classList.toggle('has-grid', center === 'table');
      if (center === 'table') grid.show();
      else { grid.hide(); if (!centerEl.hidden) centerEl.innerHTML = docsHTML(); }
    }
    function setCenter(tab) {
      if (tab === 'wiki' && current()) return ctx.openWiki(current()); // 문서 창이 열리면 아래 관찰이 탭을 '문서'로
      if (tab !== 'wiki' && !wikiEl.hidden) ctx.cmd.closeWiki();
      center = tab;
      if (tab !== 'wiki') {
        ui.center = tab;
        save();
      }
      paintCenter();
    }
    $('#mkCTabs').addEventListener('click', e => {
      const t = e.target.closest('[data-ctab]');
      if (t) setCenter(t.dataset.ctab);
    });
    centerEl.addEventListener('click', e => {
      if (e.target.closest('[data-center-table]')) return click('#tableBtn');
      const doc = e.target.closest('[data-center-doc]');
      if (doc && api.draft) ctx.openWiki(HT.docKey.absolute(doc.dataset.centerDoc, api.draft.id));
    });
    new MutationObserver(() => {
      if (!wikiEl.hidden) center = 'wiki';
      else if (center === 'wiki') center = ui.center;
      paintCenter();
    }).observe(wikiEl, { attributes: true, attributeFilter: ['hidden'] });

    /* ---------- 오른쪽 창: 바탕(고른 것 없음 · 팩 정보) 위에 상세 · 편집 창 — 그것이 열리면 접혀 있던 오른쪽을 폄 ---------- */
    propsEl.innerHTML = `<div class="mk-props-empty" data-props="empty">
        <p class="mk-empty-t">고른 것 없음</p>
        <p class="hint">연표나 왼쪽 구조에서 항목을 누르면 여기서 고칩니다.</p>
        <div class="mk-empty-add"><button type="button" class="btn btn-sm" data-add="period">＋ 객체</button><button type="button" class="btn btn-sm" data-add="event">＋ 사건</button><button type="button" class="btn btn-sm" data-add="figure">＋ 사람</button></div>
        <button type="button" class="btn btn-sm" data-props-info>📦 팩 정보</button>
      </div><div class="mk-props-info" data-props="info" hidden></div>`;
    propsEl.insertAdjacentHTML('beforeend', '<div class="mk-props-bulk" hidden></div>');
    let multiSignature = '';
    function paintMulti() {
      const uids = api.selection(), on = uids.length > 1, box = propsEl.querySelector('.mk-props-bulk');
      body.classList.toggle('mk-multi', on); box.hidden = !on;
      const signature = on ? uids.join('|') + ':' + api.history.index : '';
      if (signature !== multiSignature) {
        multiSignature = signature;
        if (on) { api.mountBulk(box); revealRight(); }
        else layout();
      }
    }
    propsEl.addEventListener('click', e => e.target.closest('[data-props-info]') && api.draft && api.openInfo());
    function showProps(mode) {
      props = mode;
      for (const el of propsEl.querySelectorAll('[data-props]')) el.hidden = el.dataset.props !== mode;
      if (mode !== 'empty') revealRight();
      else layout();
      syncTreeSel();
    }
    const syncRight = () => {
      if (hasRightContent()) revealRight();
      else layout();
    };
    new MutationObserver(syncRight).observe(pane, { attributes: true, attributeFilter: ['hidden', 'class'] });
    new MutationObserver(() => {
      if (!detail.hidden && props !== 'empty') showProps('empty');
      syncRight();
    }).observe(detail, { attributes: true, attributeFilter: ['hidden'], childList: true });

    /* ---------- 아래 창 (설계 3-1): [문제] [고친 것] — 몸통은 maker.js가 그림(api.renderBottom) ---------- */
    const btabs = bottomEl.querySelector('.mk-btabs');
    btabs.insertAdjacentHTML('beforeend', '<button type="button" data-btab="replace" role="tab">찾아 바꾸기</button><button type="button" data-btab="blanks" role="tab">빈 칸</button>');
    function renderBottomTabs() {
      for (const b of btabs.querySelectorAll('[data-btab]')) {
        const on = b.dataset.btab === ui.bottom.tab;
        b.classList.toggle('is-on', on);
        b.setAttribute('aria-selected', String(on));
      }
      api.renderBottom();
    }
    function openBottom(tab) {
      ui.bottom.tab = ['changes', 'history', 'autosave', 'replace', 'blanks'].includes(tab) ? tab : 'problems';
      if (ui.bottom.tab === 'autosave') api.loadSnapshots();
      if (!ui.bottom.open) return setBottom(true); // setBottom이 탭 · 몸통을 그림
      save();
      renderBottomTabs();
    }
    btabs.addEventListener('click', e => {
      const t = e.target.closest('[data-btab]');
      if (t) openBottom(t.dataset.btab);
    });

    /* ---------- 처음 화면 (설계 3-3): 새로 만들기 · 열기 · 이어서 고치기 · 설치된 DLC에서 고치기 ---------- */
    const ago = ms => {
      const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
      return s < 60 ? '방금' : s < 3600 ? `${Math.floor(s / 60)}분 전` : s < 86400 ? `${Math.floor(s / 3600)}시간 전` : `${Math.floor(s / 86400)}일 전`;
    };
    const refsSummary = () => (api.refRows ? (api.refRows().length ? `불러온 팩 ${api.refRows().length}` : '불러온 팩 없음') : '');
    function continueHTML(d) {
      const pack = HT.normalizePack(d).pack || d;
      const n = api.changes.length;
      const cat = HT.packCard.catName(d);
      return `<h3>이어서 고치기</h3><div class="mk-start-card mk-cont"><div class="pk-cover">${d.cover ? `<img src="${esc(d.cover)}" alt="">` : HT.autoCover(pack)}${cat ? `<span class="pk-cat">${esc(cat)}</span>` : ''}</div>
        <div class="mk-cont-body"><p class="mk-cont-name"><b>${esc(d.name)}</b> <span class="ver">v${esc(d.version)}</span></p>
          <p>${esc([HT.packCard.contentsText(pack), refsSummary()].filter(Boolean).join(' · '))}</p>
          <p>반영하지 않은 고침 <b>${n}</b>${typeof d._edited === 'number' ? ` · 마지막으로 고친 때 ${ago(d._edited)}` : ''}</p>
          <div class="mk-cont-btns"><button type="button" class="btn btn-primary" data-start="continue">이어서 고치기</button><button type="button" class="btn" data-start="reflect-close">${n ? '반영하고 닫기' : '닫기'}</button>${api.canRestore() ? '<button type="button" class="btn" data-start="restore" title="반영하지 않은 고침을 버리고 설치된 판을 다시 불러옵니다">↺ 설치된 판으로 되돌리기</button>' : ''}</div></div></div>`;
    }
    function startHTML() {
      const d = api.draft;
      const mine = state.packs.filter(p => !p.builtin);
      const hasBase = state.packs.some(p => p.builtin);
      return `<header class="mk-start-head"><span class="mk-logo">DLC 메이커</span><span class="hint">역사 연표의 DLC를 만드는 프로그램</span><span class="spacer"></span>
          <button type="button" class="btn btn-sm" data-start="guide">도움말</button><button type="button" class="btn btn-sm" data-start="to-timeline">연표로 ↗</button>${d ? '<button type="button" class="btn btn-sm" data-start="close" title="작업실로 (Esc)">작업실로 ✕</button>' : ''}</header>
        <div class="mk-start-grid">
          <div class="mk-start-col">
            <h3>새로 만들기</h3>
            <form class="mk-start-card" data-start-new novalidate>
              <label class="field"><span>이름</span><input name="name" autocomplete="off"></label>
              <label class="field"><span>id <small>(영문 · 숫자 · - _ .)</small></span><input name="id" autocomplete="off" spellcheck="false"></label>
              <label class="field"><span>분류</span><select name="category"><option value="">분류 없음</option>${HT.PACK_CATEGORIES.map(c => `<option value="${c.id}">${esc(c.name)} — ${esc(c.hint)}</option>`).join('')}</select></label>
              <fieldset class="mk-how"><legend>시작 방법</legend>
                <label><input type="radio" name="how" value="blank" checked><span><b>빈 DLC</b><small>아무것도 없이 — 트랙부터 만듭니다</small></span></label>
                <label${hasBase ? '' : ' class="is-off"'}><input type="radio" name="how" value="base"${hasBase ? '' : ' disabled'}><span><b>기본팩에 덧붙이기</b><small>기본팩을 불러온 채로(잠김) 시작 — 기본팩의 트랙 · 민족을 씁니다</small></span></label>
                <label><input type="radio" name="how" value="world"><span><b>가상 세계</b><small>이 DLC의 트랙 하나를 만들고 시작 — 소설 · 게임 세계관</small></span></label>
              </fieldset>
              <ul class="problems" data-start-problems hidden></ul>
              <button type="submit" class="btn btn-primary">만들기</button>
            </form>
            <h3>열기</h3>
            <div class="mk-start-card"><button type="button" class="btn" data-start="open">📂 DLC 파일 열기 (.htpack)</button><p class="hint">파일을 이 화면에 끌어다 놓아도 열립니다.</p></div>
          </div>
          <div class="mk-start-col is-wide">
            ${d ? continueHTML(d) : ''}
            <h3>설치된 DLC에서 고치기</h3>
            ${mine.length ? `<div class="mk-start-cards">${mine.map(p => HT.packCard.html(p, { tag: d && p.id === d.id ? '고치는 중' : '', hint: '누르면 이 DLC를 고칩니다' })).join('')}</div>` : '<p class="hint">설치한 DLC가 없습니다 — 새로 만들거나 파일을 여세요.</p>'}
            <p class="hint">기본팩은 직접 고치지 않습니다 — 내 DLC에 불러와 자물쇠를 풀고 덮어쓰거나, 항목을 내 DLC로 복사해 고칩니다.</p>
          </div>
        </div>`;
    }
    function fillNew() {
      const f = startEl.querySelector('[data-start-new]').elements;
      f.name.value = '새 DLC';
      const used = new Set(state.packs.map(p => p.id).concat(api.draft ? [api.draft.id] : []));
      const stem = `dlc-${HT.makerKit.today().replace(/-/g, '')}`;
      let id = stem;
      for (let k = 2; used.has(id); k++) id = `${stem}-${k}`;
      f.id.value = id;
    }
    function showStart(part) {
      startEl.innerHTML = startHTML(); // 보일 때 한 번만 그림 — 치는 동안 다시 그리지 않음
      startEl.hidden = false;
      fillNew();
      const focus = part === 'installed' ? startEl.querySelector('.mk-start-cards [data-pick-pack]') || startEl.querySelector('[data-start="open"]') : part === 'new' ? startEl.querySelector('[data-start-new] [name="name"]') : null;
      if (focus) focus.focus();
    }
    function hideStart() {
      if (api.draft) startEl.hidden = true; // 고칠 것이 없으면 처음 화면을 닫을 수 없음
    }
    startEl.addEventListener('click', async e => {
      const card = e.target.closest('[data-pick-pack]');
      if (card) return (await api.pick(card.dataset.pickPack)) && hideStart();
      const b = e.target.closest('[data-start]');
      if (!b) return;
      const act = b.dataset.start;
      if (act === 'close' || act === 'continue') return hideStart();
      if (act === 'open') return api.openFile();
      if (act === 'guide') return openGuide();
      if (act === 'to-timeline') return api.toTimeline();
      if (act === 'restore') return (await api.restoreInstalled()) && showStart();
      if (act === 'reflect-close' && (!api.changes.length || (await api.reflect()))) {
        api.closeDraft();
        showStart();
      }
    });
    startEl.addEventListener('keydown', e => {
      if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[data-pick-pack]')) {
        e.preventDefault();
        e.target.click();
      } else if (e.key === 'Escape' && api.draft) {
        e.preventDefault();
        hideStart();
      }
    });
    startEl.addEventListener('submit', async e => {
      e.preventDefault();
      const f = e.target.elements;
      const box = startEl.querySelector('[data-start-problems]');
      const problems = await api.createNew({ name: f.name.value.trim(), id: f.id.value.trim(), category: f.category.value, how: f.how.value });
      if (!problems) return;
      box.innerHTML = problems.map(p => `<li>${esc(p)}</li>`).join('');
      box.hidden = !problems.length;
      if (!problems.length) hideStart();
    });

    /* ---------- 상태 줄 · 메뉴 줄 · 도구 줄 ---------- */
    const savedText = () => {
      const sv = api.saved;
      if (!sv.ok) return '<span class="st-save is-bad">● 저장하지 못했습니다 — 파일로 내려받아 두세요</span>';
      const s = Math.max(0, Math.round((Date.now() - sv.at) / 1000));
      return `<span class="st-save is-ok">● 저장됨 · ${s < 60 ? '방금' : s < 3600 ? `${Math.floor(s / 60)}분 전` : `${Math.floor(s / 3600)}시간 전`}</span>`;
    };
    const refsText = () => {
      const rows = api.refRows ? api.refRows() : [];
      const one = rows.length === 1 ? rows[0] : null;
      return `<button type="button" class="st-btn" data-st-packs>불러온 팩: <b>${rows.length ? (one ? esc(one.name) : `${rows.length}개`) : '없음'}</b>${one ? (one.locked ? ' (잠김)' : ' (풀림)') : ''}</button>`;
    };
    function statusHTML() {
      const d = api.draft;
      if (!d) return '<span>고칠 DLC가 없습니다 — 파일 ▸ 처음 화면</span>';
      const c = api.check;
      const n = l => (Array.isArray(d[l]) ? d[l].length : 0);
      const next = api.nextVersion();
      const lineage = arr(d.figures).filter(f => f && f.lineageOnly === true).length; // 계보 전용 인물(D1)은 따로 — 없으면 예전 글 그대로
      return `${savedText()}<button type="button" class="st-btn" data-cmd="check">검사 <b>오류 ${c.errors.length}</b> · 경고 ${c.warnings.length}</button><span>이 DLC: <b>객체 ${n('periods')}</b> · 사건 ${n('events')} · ${lineage ? `띠 인물 ${n('figures') - lineage} · 계보 전용 ${lineage}` : `사람 ${n('figures')}`} · 트랙 ${n('tracks')}</span>${refsText()}<span data-selection-count></span><span class="spacer"></span><button type="button" class="st-btn st-changes" data-cmd="changes">고친 것 <b>${api.changes.length}</b>${next ? ` · 반영하면 v${esc(next)}` : ''}</button><button type="button" class="st-btn" data-cmd="keys">단축키 ?</button>`;
    }
    setInterval(() => {
      const el = statusEl.querySelector('.st-save');
      if (el && api.draft) el.outerHTML = savedText();
    }, 30000);
    function updateTools() {
      for (const b of $('#mkTools').querySelectorAll('[data-cmd]')) {
        const c = COMMANDS.find(x => x.id === b.dataset.cmd);
        if (c && !c.soon) b.disabled = !enabled(c.id);
      }
    }
    function update() {
      updateTools();
      const d = api.draft;
      const changes = api.changes;
      const { errors, warnings, notes } = api.check;
      $('#mkName').textContent = d ? d.name : '고칠 DLC 없음';
      $('#mkVer').textContent = d ? `v${d.version}` : '';
      $('#mkDoc').disabled = !d;
      const sv = api.saved;
      const saved = $('#mkSaved');
      saved.textContent = !d ? '' : sv.ok ? '● 저장됨' : '● 저장 못 함';
      saved.className = `mk-saved ${sv.ok ? 'is-ok' : 'is-bad'}`;
      for (const id of ['#mkReflect', '#mkFile', '#mkCheckBtn', '#mkChanges']) $(id).disabled = !d;
      const nErr = errors.length;
      const nWarn = warnings.length;
      const cb = $('#mkCheckBtn');
      cb.innerHTML = nErr + nWarn ? `검사 <b>${nErr + nWarn}</b>` : '검사 <span class="ok">✓</span>';
      cb.classList.toggle('is-bad', nErr > 0);
      cb.classList.toggle('is-warn', !nErr && nWarn > 0);
      cb.title = !d ? '' : nErr + nWarn ? `오류 ${nErr}개 · 경고 ${nWarn}개 — 누르면 문제 창 (오류가 있는 항목은 연표에 나오지 않고 반영할 때 빠집니다)` : '검사 — 오류도 경고도 없습니다';
      if (d && notes.length) cb.title += ` · 알림 ${notes.length}개(대범위를 켜면 승계 줄이 나뉘는 곳)`;
      const chg = $('#mkChanges');
      chg.innerHTML = `고친 것 <b>${changes.length}</b>`;
      chg.classList.toggle('is-dirty', changes.length > 0);
      chg.title = changes.length ? '반영하지 않은 고침이 있습니다 — 누르면 목록 (남의 항목에 건 덮어쓰기 되돌리기도 여기서)' : '반영하지 않은 고침이 없습니다 — 누르면 남의 항목에 건 덮어쓰기 목록';
      const alert = $('#mkAlert');
      alert.hidden = !api.broken;
      alert.textContent = api.broken ? `⚠ 작업본에 오류가 있어 마지막으로 성한 모습을 보여 줍니다 — ${api.broken}` : '';
      alert.title = alert.textContent;
      const dr = $('#mkDrift');
      const drift = api.drift;
      dr.hidden = !drift;
      dr.textContent = drift ? `⚠ ${drift.rec && drift.rec.sig ? '설치된 판이 바뀌었습니다' : '설치된 판과 어긋납니다'}` : '';
      dr.title = drift ? `${api.driftText()} 반영하면 설치된 판을 이 작업본으로 덮어씁니다 — 누르면 자세히` : '';
      statusEl.innerHTML = statusHTML();
      $('#mkProbN').textContent = nErr + nWarn || '';
      $('#mkChgN').textContent = changes.length || '';
      document.title = d ? `${d.name} — DLC 메이커` : 'DLC 메이커 — 역사 연표';
      dimEl.textContent = api.refRows ? HT.makerKit.refDimCSS(api.refRows(), ui.dim) : '';
      $('#mkRefCount').textContent = api.refRows ? api.refRows().length || '' : '';
      renderTree();
      api.paintSelection();
      if (ui.bottom.open) api.renderBottom();
      paintCenter();
    }

    /* ---------- 단축키 목록 · 메이커 안내 (작은 창 하나를 돌려씀) ---------- */
    let box = null;
    function dialog(title, html) {
      if (!box) {
        box = document.createElement('dialog');
        box.className = 'dlc-dialog mk-box';
        box.addEventListener('click', e => (e.target === box || e.target.closest('[data-close]')) && box.close());
        document.body.appendChild(box);
      }
      box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>${esc(title)}</h2><button type="button" class="icon-btn" data-close aria-label="닫기">✕</button></div><div class="dlg-body">${html}</div></div>`;
      box.showModal();
    }
    function openKeys() {
      const row = (label, key) => `<tr><td>${esc(label)}</td><td><kbd>${esc(key)}</kbd></td></tr>`;
      const own = COMMANDS.filter(c => c.key && !c.soon).map(c => row(c.label, c.key));
      const adds = ctx.cmd.addKinds().filter(k => ctx.cmd.addKeyOf(k)).map(k => row(`＋ ${HT.FORMS[k].word}`, ctx.cmd.addKeyOf(k)));
      const more = [['명령·항목 찾기', '/'], ['표 칸 고치기', 'Enter · F2'], ['표 아래로 채우기', 'Ctrl+D'], ['표 범위 채우기', 'Ctrl+Enter'], ['고른 항목 날짜 옮기기', 'Alt+←/→'], ['열 단위 옮기기', 'Alt+Shift+←/→'], ['빈 곳에 시대·사건 추가', 'Ctrl+끌기 · Ctrl+누르기'], ['끌기 취소', 'Esc'], ['고른 항목의 문서', 'W'], ['모든 트랙 접기 · 펴기', 'A'], ['연표 옮기기', '← →'], ['확대 · 축소', '+ −'], ['불러온 팩 탭', 'D']].map(([l, k]) => row(l, k));
      if (HT.formKeys) more.push(...HT.formKeys.KEYS.map(([l, k]) => row(l, k))); // 편집 창의 입력 칸 길잡이 (js/form-keys.js)
      if (HT.makerBlocks) more.push(...[['편집 창: 줄 메뉴(복제 · 옮기기 · 종류 바꾸기 · 다른 나라로)', '손잡이 ⋮⋮ 누르기'], ['편집 창: 여러 줄 고르기(둘이면 맞바꾸기)', 'Shift+손잡이'], ['편집 창: 줄 옮기기 · 종류 바꾸기', '손잡이 끌기'], ['편집 창: 블록 더하기 (글 칸 밖에서)', '/']].map(([l, k]) => row(l, k))); // 편집 창의 블록 (js/maker-blocks.js)
      more.push(...[['작업 폴더: 이름 바꾸기 · 폴더 지우기(항목은 그대로)', 'F2 · Delete'], ['작업 폴더: 차례', 'Alt+↑/↓'], ['작업 폴더: 넣으며 원래 폴더에도 남기기', 'Ctrl+놓기']].map(([l, k]) => row(l, k))); // 작업 폴더 (10건 D3 결정 7 A)
      dialog('단축키', `<table class="mk-keys">${own.concat(adds, more).join('')}</table><p class="hint">글 칸 안의 Ctrl+Z · C · X · V · A는 그 칸의 글자를 다룹니다. Ctrl+Shift+Z도 다시 하기입니다. 구조의 Ctrl+누르기는 여러 개, Shift+누르기는 사이 줄을 고릅니다.</p>`);
    }
    function openGuide() {
      dialog(
        '메이커 안내',
        `<ul class="mk-guide">
          <li>왼쪽 <b>구조</b>는 고치는 DLC에 든 것입니다 — 누르면 오른쪽 속성 창에서 고칩니다. 맨 위 📦은 팩 정보(이름 · 표지 · 태그 · 관계 · 판 기록).</li>
          <li>구조의 <b>보기</b>를 민족으로 · 소속으로 · 가문(국성)으로 · 대범위로 바꾸면 같은 나라들이 그 칸으로 묶입니다 — 나라 줄을 끌어 다른 가지에 놓으면 그 칸이 채워지고(여럿 고른 채로도 · 되돌리기 한 걸음), 트랙 머리에 놓으면 트랙을 옮깁니다. 트랙 · 민족 머리끼리 끌면 차례(<kbd>Alt+↑↓</kbd>도). 오른쪽 클릭 ▸ <b>옮기기…</b>로 키보드로도 됩니다.</li>
          <li><b>불러온 팩</b>은 함께 보며 쓸 다른 팩입니다 — 흐리게 보이고, 자물쇠가 잠겨 있으면 보기만 합니다. 자물쇠를 풀면 고친 칸이 이 DLC의 덮어쓰기로 들어갑니다.</li>
          <li><b>반영</b>(Ctrl+E)은 판을 올려 연표에 설치하고 판 기록 한 줄을 남깁니다. <b>파일로</b>는 팩 파일(.htpack)로 내려받습니다.</li>
          <li><b>표</b>(Ctrl+2)에서 내 자료를 한꺼번에 고칩니다. 시대 한 줄을 고르면 아래 하위 표가 열립니다. 여러 줄을 고르면 오른쪽에서 함께 고칠 수 있습니다.</li>
          <li>연표에서 고른 띠의 끝을 끌면 기간을 바꿉니다. <b>Alt+끌기</b>는 안의 날짜까지 함께 옮기고, <b>Esc</b>로 취소합니다.</li>
          <li>편집 창은 <b>블록</b>으로 묶여 있습니다 — 쓴 블록만 펼쳐 두고, 안 쓴 블록은 아래 칩(＋)이나 글 칸 밖에서 <kbd>/</kbd>로 더합니다. 줄 앞 손잡이 <b>⋮⋮</b>를 누르면 줄 메뉴(복제 · 옮기기 · 종류 바꾸기 · 다른 나라로 옮기기), 끌면 같은 목록에서는 자리, 다른 목록으로는 종류 바꾸기 — 놓을 자리에 빈 자리와 미리 글이 열립니다(구조 나무 끌기와 같은 꼴).</li>
          <li><b>틀로 만들기</b>(＋ 더 ▾ · 넣기 메뉴 · 명령 찾기 · 편집 창의 <kbd>/</kbd>)는 묻는 칸 몇 개만 적으면 여러 줄을 한 번에 만듭니다 — 새 지도자(지도자 줄 + 연호 줄 + 사건) · 천도 · 개원. 같은 해는 한 번만 적고, 만들기 한 번이 되돌리기 한 걸음입니다. 틀은 <b>틀 관리…</b>에서 고치거나 새로 만들고(이 작업실의 설정 — DLC 파일에는 들어가지 않음), 편집 창에서 줄을 고르고 손잡이 메뉴의 <b>틀로 저장…</b>으로도 만듭니다.</li>
          <li>구조 맨 위 <b>작업 폴더</b>는 지금 고치는 것을 묶어 두는 곳입니다 — 항목 줄을 폴더에 끌어 놓거나(＋로 새 폴더) 오른쪽 클릭 ▸ <b>폴더에 넣기…</b>. 폴더의 항목은 바로 가기라 제자리에 그대로 있고, 폴더는 이 작업실에만 남습니다. 폴더 메뉴(오른쪽 클릭)에서 이름 · 색 · <b>집합 보기로 내보내기</b>(폴더의 나라로 DLC의 집합 보기 하나).</li>
          <li><b>명령 찾기</b>(Ctrl+K)는 명령·항목·문서·날짜를 찾습니다. <b>찾아 바꾸기</b>(Ctrl+H)와 <b>빈 칸 점검</b>은 아래 창에 있습니다.</li>
          <li><b>형식 4</b>(2026-10-23): 저장은 형식 4입니다 — 「객체」(옛 시대) 폼의 종류(열여덟) · 정통성 · 중요도 · 소속 줄의 으뜸, 지도자 · 내각 자리의 <b>빌려 보기</b> · <b>직위 줄 더</b> · <b>실권</b>, 사람 폼의 칭호 묶음, 시대 구분의 문화권 · 「주기」 표가 그 칸입니다. 옛 앱용 파일은 파일 › <b>옛 형식(3)으로 내보내기</b>(빠지는 것을 먼저 보임). 미리보기 연표(서고)는 사람 띠 · 빌린 층 · 밑줄 실권 · 문화권 줄 · 상자 · <b>선반</b>(오른쪽 클릭 ▸ 그릇 상태)을 그립니다.</li>
          <li>자세한 설명: 프로그램 폴더의 README.md 4절(메이커) · DLC-형식.md(팩 형식 · '형식 4' 절) · docs/용어집.md 4-2(객체 · 그릇 · 선반 · 사람 객체 · 빌림 · 주기 줄).</li>
        </ul>`
      );
    }

    paintLeftTab();
    layout();
    paintCenter();
    if (ui.bottom.open) renderBottomTabs();
    return {
      update, paintMulti, openBottom, openTable, showStart, hideStart, showProps, setLeftTab, setRightWide, revealRight,
      propsMode: () => props,
      rightWidth: rightW,
      bottomTab: () => ui.bottom.tab,
      bottomOpen: () => ui.bottom.open,
      rightWide: () => ui.right.wide,
      dim: () => ui.dim,
      bottomBody: $('#mkBottomBody'),
      renderExtraBottom: tab => finder.render($('#mkBottomBody'), tab),
      propsInfo: propsEl.querySelector('[data-props="info"]'),
      packsBody: $('#mkPacks'),
      isStart: () => !startEl.hidden,
      /** 놓아서 채우기의 길을 코드로 — uids를 drop({ type: 'track' | 'people' | 'house' …, … })에 놓은 것처럼 (트랙은 '딸린 것도 함께?' 물음). 머리 칩 고치기(js/maker-kin.js)가 씀 */
      applyDrop: (uids, drop) => {
        const plan = planFor({ uids, from: '' }, drop);
        if (!plan || !plan.ok) { HT.toast(plan && plan.reason ? `바꾸지 않았습니다 — ${plan.reason}` : '바꾸지 않았습니다.'); return Promise.resolve(false); }
        return Promise.resolve(perform(plan));
      },
    };
  }

  earlyVars();
  HT.makerShell = { UI_KEY, MENUS, COMMANDS, LIMITS, keyName, readUi, treeOf, filterTree, mount };
  Object.assign(HT.makerShell, { TREE_KEY, TREE_VIEWS, readTreeUi, viewTreeOf, filterView, planOrder }); // 구조 나무의 보기 갈래 · 놓아서 채우기 (10건 4(나))
  Object.assign(HT.makerShell, { FOLDER_KEY, FOLDER_LIMITS, readFolders, moveFolders }); // 작업 폴더 (10건 D3 결정 7 A — 작업실 설정)
})();

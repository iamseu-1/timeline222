/* 역사 연표 — DLC 메이커 부품 (dlc-maker.html에서만 읽힘)
 * 메이커의 화면은 연표와 같은 js/viewer.js이고, 이 파일은 거기에 붙는 부품입니다 (지도 부품 HT.mapPlugin과 같은 방식: viewer.js가 HT.makerPlugin이 있을 때만 부름).
 * 맡는 일: 맨 위 메이커 줄 · 고치는 DLC(작업본) 고르기/새로 만들기/파일 열기 · 작업본을 얹은 모델 · 반영(판 올려 덮어쓰기) · 파일로 · 고친 것 목록 · 연표로(한 방향 — 연표에서 메이커로 오는 길은 없음) ·
 *   오른쪽에 붙은 편집 창의 틀(폭 조절 · 넓게 · 떼어 내기 — 폼을 채우고 저장하는 것은 viewer.js) · DLC 정보 · 바탕 자료 · 표 붙여넣기 · 검사.
 * 작업본을 고치는 계산은 js/core.js의 HT.draft와 이 파일 앞쪽의 HT.makerKit(바탕 자료의 열 설정표 · DLC id 바꾸기 · 표 붙여넣기)에 있고 — 둘 다 순수 함수라 scripts/dev-smoke.mjs가 노드에서 검사합니다 —
 * 부품은 그것을 부르고 브라우저에 임시 저장(HT.KEYS.draft)한 뒤 화면을 다시 짓게 합니다.
 * viewer.js가 넘겨주는 ctx: { $, state, K, timeline, esc, isEnabled, packById, refresh, reloadPacks, openDetail, closeDetail,
 *                            openEditor, openEditorFor, leaveEditor, closeEditor, editorDirty, syncEditor, openWiki, syncInset }
 * 작업본을 편집 창 밖에서 고치는 길(바탕 자료의 id · 이름 바꿈 · 고친 것의 되돌리기 · 다른 탭의 작업본)은 끝에 ctx.syncEditor를 불러 열린 편집 창이 옛 값을 들고 있지 않게 합니다 */
(function () {
  'use strict';
  const HT = window.HT;
  const str = v => (v == null ? '' : String(v).trim());
  const arr = v => (Array.isArray(v) ? v : []);

  /* ================= 메이커 도구 (순수 계산 — 화면 없이 돕니다) ================= */

  /** 작업본의 항목 목록: 시대 구분 + 연표에서 추가하는 항목들(HT.USER_LISTS — 인물처럼 더해지면 저절로 늘어납니다) + 대범위(시대 구분처럼 연표에서는 고치지 않는 부류 — 메이커에서만).
      차례는 쓰는 곳 요약("시대 1 · 대범위 2")의 차례이기도 합니다 */
  const itemLists = () => ['epochs'].concat(HT.USER_LISTS.map(l => l.list), ['scopes', 'groups', 'institutions']); // 단체 · 제도 칸(형식 버전 3)도 대범위처럼 메이커에서만
  /** 목록 이름 → 편집 창의 폼 종류(HT.FORMS의 열쇠) */
  const kindOfList = list => (list === 'epochs' ? 'epoch' : list === 'scopes' ? 'scope' : list === 'groups' ? 'group' : list === 'institutions' ? 'institution' : (HT.USER_LISTS.find(l => l.list === list) || {}).kind || null);

  /** obj 안의 길(path)을 따라가 끝 값마다 fn(값, 바꾸기, 그 값을 든 것)을 부릅니다. 길 글: 'track' · 'set.track'(안쪽 칸) · 'tracks[]'(목록의 값마다) · 'leaders[].house'(목록 안 칸마다) ·
      'frames[].owners{}'(객체의 값마다 — 지도 장면의 구역 id → 주인) */
  const walkPath = (obj, path, fn) => {
    const go = (o, segs) => {
      if (!o || typeof o !== 'object' || !segs.length) return;
      const [head, ...rest] = segs;
      if (head.endsWith('{}')) {
        const m = o[head.slice(0, -2)];
        if (!m || typeof m !== 'object' || Array.isArray(m)) return;
        for (const k of Object.keys(m)) rest.length ? go(m[k], rest) : m[k] != null && m[k] !== '' && fn(m[k], nv => (m[k] = nv), m);
        return;
      }
      const many = head.endsWith('[]');
      const key = many ? head.slice(0, -2) : head;
      const v = o[key];
      if (many) {
        if (!Array.isArray(v)) return;
        v.forEach((el, i) => (rest.length ? go(el, rest) : el != null && el !== '' && fn(el, nv => (v[i] = nv), v)));
      } else if (rest.length) go(v, rest);
      else if (v != null && v !== '') fn(v, nv => (o[key] = nv), o);
    };
    go(obj, String(path).split('.'));
  };

  /* ---------- 바탕 자료의 열 설정표 ----------
   * 바탕 자료 창의 칸(탭)마다 설정 한 덩어리 — 창을 그리기 · 칸 고치기 · 추가 · 삭제 · 가져오기 · 쓰는 곳 · id를 바꿀 때 참조 따라 고치기는 모두 이 표를 봅니다.
   * 새 칸(지위 사전 · 가문 …)은 설정 한 덩어리를 더해 끼웁니다: Object.assign(HT.makerKit.BASE_TABLES, { houses: { … } }) — 열쇠 = 작업본의 목록 이름, 탭의 차례 = 열쇠의 차례.
   *   word 부르는 말 · lead 안내 글 · idBase 새 줄 id의 바탕 글 · docPrefix 문서 키의 머리글(있으면 📄 단추 · id를 바꾸면 그 문서도 따라감)
   *   cols 열 목록: { key 항목의 열쇠(= 칸의 name) · label 머리글 · type 'color' | 'id' | 'text' | 'number' | 'list'(글 목록 — 칸에는 쉼표로) · title 풍선 도움말 · list 자동 완성 목록 id(foot이 만듦) }
   *   refs 다른 항목이 이 줄을 가리키는 길 — { 열 열쇠: [{ list, path, match?, map?, countOnly? }, …] }. id 열 · 여기 적은 열은 "참조 열"이라 칠 때마다가 아니라 칸에서 나올 때 한 번에 바꾸고,
   *        바뀐 값을 가리키던 곳을 모두 따라 고칩니다. list = 목록 이름(들) 또는 그것을 돌려주는 함수 · path = 그 항목 안의 길(walkPath — 중첩 참조도: 'leaders[].house') ·
   *        match(값, 이 줄의 값) 가리키는지(기본: 같음) · map(값, 옛 값, 새 값) 바꾼 값(기본: 새 값) · countOnly 쓰는 곳에만 세고 따라 고치지는 않는 길(지위의 별칭). 쓰는 곳(역참조)도 이 길들로 셉니다
   *   autoColor(x) 색을 비웠을 때 연표가 쓰는 색 · fresh(id) 새 줄 · foot(draft, model) 표 아래에 붙일 것 · tools(draft) 도구 줄에 더할 단추 ·
   *   builtin() 프로그램에 든 정의(가져오기 후보에 "기본"으로 — 지위) · delNote 쓰는 곳이 있는 줄을 지울 때 물음에 붙일 글(없으면 "검사에서 걸릴 수 있음")
   *   dropped(x) 이 줄이 파일을 읽을 때 빠지는 까닭(없으면 '') — 표에서 이름 칸에 표시합니다 (지위: 이름 없는 줄)
   *   form 이 칸은 표가 아니라 편집 창의 폼(HT.FORMS[form])으로 고칩니다 — 창에는 목록만 (예: 시대 구분) ·
   *   uses(draft, x) 폼으로 고치는 칸의 쓰는 곳([{ list, item }] — 목록에 "쓰는 곳"으로 보이고 지울 때 물음에 알림. 시대 구분: 그것을 가리키는 대범위) */
  const COL = {
    color: { key: 'color', label: '색', type: 'color' },
    id: { key: 'id', label: 'id', type: 'id', title: '영문·숫자·- _ . — 다른 DLC와 같은 id면 하나로 합쳐집니다' },
    name: { key: 'name', label: '이름', type: 'text' },
    order: { key: 'order', label: '순서', type: 'number', title: '작은 수일수록 위에 놓입니다 (비우면 자동)' },
  };
  /* 사건의 "함께 겪은 쪽" 칸(tracks)은 "트랙 id" 또는 "트랙 id:정권"을 적습니다 */
  const trackToken = { match: (v, id) => v === id || String(v).startsWith(`${id}:`), map: (v, from, to) => (v === from ? to : `${to}${String(v).slice(from.length)}`) };
  const PEOPLE_REFS = [
    { list: ['periods', 'cultures'], path: 'people' },
    { list: 'peoples', path: 'parent' },
    { list: 'patches', path: 'set.people' },
  ];
  const PASTEL_AT = i => HT.PASTEL[i % HT.PASTEL.length].id;
  const BASE_TABLES = {
    tracks: {
      word: '트랙', idBase: 'track', docPrefix: 'track',
      lead: '연표의 가로줄(나라·지역·주제)입니다. 다른 DLC나 기본팩과 id가 같으면 한 줄로 합쳐지고, 이름·색은 먼저 놓인 쪽을 따릅니다. 순서는 작은 수일수록 위에 놓입니다.',
      cols: [COL.color, COL.id, COL.name, COL.order],
      refs: {
        id: [
          { list: itemLists, path: 'track' },
          Object.assign({ list: 'events', path: 'tracks[]' }, trackToken),
          { list: itemLists, path: 'perspectives[].track' },
          { list: 'patches', path: 'set.track' },
          Object.assign({ list: 'patches', path: 'set.tracks[]' }, trackToken),
          { list: 'patches', path: 'set.perspectives[].track' },
        ],
      },
      autoColor: x => HT.autoColor(x.id || ''),
      fresh: (id, n) => ({ id, name: '', color: PASTEL_AT(n) }),
    },
    categories: {
      word: '분류', idBase: 'category', docPrefix: 'category',
      lead: '사건의 분류입니다. 아래 기본 분류는 만들지 않아도 쓸 수 있으니, 새로 필요한 분류만 만드세요.',
      cols: [COL.color, COL.id, COL.name],
      refs: { id: [{ list: 'events', path: 'category' }, { list: 'patches', path: 'set.category' }] },
      autoColor: x => HT.autoColor(x.id || ''),
      fresh: (id, n) => ({ id, name: '', color: PASTEL_AT(n + 3) }),
      foot: (draft, esc) => `<div class="mk-note"><b>기본 분류</b> <span class="chips">${HT.DEFAULT_CATEGORIES.map(c => `<span class="badge" style="--c:${c.color}">${esc(c.name)} <small>${esc(c.id)}</small></span>`).join('')}</span></div>`,
    },
    peoples: {
      word: '민족', idBase: 'people', docPrefix: 'people',
      lead: '트랙 안에서 정권을 묶는 단위입니다. 상위 민족을 적으면 단계가 생기고(단계 수 제한 없음) 연표 왼쪽에 단계마다 세로 칸이 나옵니다. 시대의 민족 칸에는 이름이나 id를 적습니다 — 등록하지 않은 이름도 쓸 수 있으니, 색·설명·상위 민족을 정할 때만 등록하면 됩니다.',
      cols: [COL.color, COL.id, Object.assign({}, COL.name, { title: '이름을 바꾸면 이 이름으로 적은 곳도 따라 바뀝니다' }), { key: 'parent', label: '상위 민족', type: 'text', list: 'mkBasePeopleList', title: '상위 민족(대명제)의 이름이나 id — 비우면 맨 위 단계' }, { key: 'description', label: '설명', type: 'text' }, COL.order],
      refs: { id: PEOPLE_REFS, name: PEOPLE_REFS },
      autoColor: x => HT.autoColor(`people:${x.id || ''}`),
      fresh: id => ({ id, name: '' }),
      foot: (draft, esc, model) => {
        const names = new Set(arr(draft.peoples).map(p => p.name || p.id));
        if (model) model.peoples.forEach(p => names.add(p.name));
        return `<datalist id="mkBasePeopleList">${[...names].filter(Boolean).sort().map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>`;
      },
    },
    epochs: {
      word: '시대 구분', form: 'epoch',
      lead: '연표 맨 위 날짜 칸에 파스텔 띠로 놓이는 시대 구분입니다. 트랙을 고르면 그 나라 줄에, 비우면 모든 나라 공통 줄에 놓입니다. 누르면 오른쪽 편집 창에서 고칩니다.',
      uses: (draft, raw) => arr(draft.scopes).filter(s => epochRefMatch(s, raw)).map(item => ({ list: 'scopes', item })), // 쓰는 곳 — 이 시대 구분을 가리키는 대범위
      delNote: '지우면 그 대범위는 시대 구분의 이름 · 기간 · 색을 물려받지 못합니다(검사에서 알림).',
    },
  };
  /* 민족의 배열 기준 (형식 버전 3 — 설계 6 결정 6 C · DLC-형식.md 'peoples'): 그 민족 묶음 안(제 줄 · 하위 민족)의 위아래 차례. 비우면 상위 민족의 것을 물려받고, 없으면 시작 해(지금 규칙) */
  BASE_TABLES.peoples.cols.push({
    key: 'rowOrder', label: '배열 기준', type: 'select',
    title: "이 민족 묶음 안(제 줄과 하위 민족)의 위아래 차례 — '북 → 남'이면 나라의 남북 위치(없으면 첫 정도의 지명 좌표)가 큰 줄이 위. 비우면 상위 민족의 것을 따르고, 없으면 시작 연도",
    options: [{ id: '', name: '상위 민족 따름', hint: '상위 민족의 기준 — 없으면 시작 연도' }].concat(HT.ROW_ORDERS.map(o => ({ id: o.id, name: o.name, hint: o.hint }))),
  });
  /* 트랙의 문화권(sphere — 형식 버전 3 · 리메이크 조각 ② · DLC-형식.md 'tracks'): 트랙 위의 한 층. 연표는 문화권마다 가로 머리 단을 두고 문화권째 접고 폅니다.
     비우면 문화권 없음(머리 단 없이 모든 문화권 뒤). 프로그램에 든 문화권은 없고 모두 DLC의 spheres(2026-10-23 — 동아시아는 기본팩의 것) */
  /** 문화권 고르기 칸의 선택지(2026-10-23) — 모델의 사전(켠 DLC들의 문화권 · 차례대로 — 동아시아는 기본팩의 것) + 이 작업본의 문화권(아직 모델에 들기 전 것도). 바탕 창 · 편집 표 · 폼이 (작업본, 모델)로 부릅니다.
      none = 비운 값의 이름(없으면 비운 줄을 두지 않음 — 편집 표는 '비움'을 제가 더함) */
  const sphereChoices = (draft, model, none = null, noneHint = '') => {
    const seen = new Map();
    for (const x of arr(model && model.spheres)) if (!seen.has(x.id)) seen.set(x.id, { id: x.id, name: x.name, hint: x.packId ? `DLC «${x.packId}»의 문화권` : '' });
    for (const x of arr(draft && draft.spheres)) if (x && str(x.id)) seen.set(str(x.id), { id: str(x.id), name: str(x.name) || str(x.id), hint: '이 DLC의 문화권' });
    return (none ? [{ id: '', name: none, hint: noneHint }] : []).concat([...seen.values()]);
  };
  BASE_TABLES.tracks.cols.push({
    key: 'sphere', label: '문화권', type: 'select',
    title: '이 트랙이 드는 문화권 — 연표가 문화권마다 머리 단을 두고 문화권째 접고 폅니다. 비우면 문화권 없이 모든 문화권 뒤에. 목록에 없는 문화권은 바탕 자료의 「문화권」에서 만듭니다',
    options: (draft, model) => sphereChoices(draft, model, '없음', '문화권 없이 — 머리 단 없이 모든 문화권 뒤에'),
  });
  /* 문화권 사전(spheres — 2026-10-23 · DLC-형식.md 'spheres'): DLC가 만드는 문화권. 트랙의 문화권 칸이 id로 가리킵니다(이름으로는 아님). 프로그램에 든 문화권은 없어
     동아시아도 기본팩의 것(다른 DLC · 기본팩에서 가져오기로). 탭은 트랙 바로 다음에 — 열쇠 차례가 탭 차례라 표를 다시 짭니다 */
  const SPHERE_REFS = [{ list: 'tracks', path: 'sphere' }];
  /* 지도자 표기 낱말(leaderLabels — 리메이크 6단계 D3 · 걸음 3): 칸(묘호 · 시호 · 이름)은 그대로 두고 화면에서 부르는 말만 — 팩 정보 폼과 「문화권」 표에 세 칸(비우면 기본).
     표의 칸은 안쪽 열쇠(nest — [바깥 열쇠, 안 열쇠])로 적고 읽습니다(바탕 창 baseCell · writeCol과 편집 표 js/maker-grid.js가 함께 씀 — 칸을 다 비우면 바깥 열쇠도 지움) */
  const LEADER_WORD_HINT = { temple: '치세명 · 교황명 · 라캅', title: '존호 · 별명', given: '본명 · 세례명' };
  const leaderLabelCols = whose =>
    ['temple', 'title', 'given'].map(k => ({
      key: `leaderLabels.${k}`, nest: ['leaderLabels', k], label: `${HT.LEADER_WORDS[k]} 칸 낱말`, type: 'text',
      title: `지도자의 ${HT.LEADER_WORDS[k]} 칸을 ${whose}에서 부르는 말(예: ${LEADER_WORD_HINT[k]}) — 칸 창 · 표기 고르기 · 풍선에 쓰입니다. 비우면 ${whose === '이 문화권' ? '팩의 낱말, 그것도 없으면 ' : ''}"${HT.LEADER_WORDS[k]}"`,
    }));
  /** 안쪽 열쇠 칸 읽기 · 쓰기(빈 글이면 그 칸을 지우고, 안이 비면 바깥 열쇠도) */
  const nestGet = (x, nest) => (x && x[nest[0]] && typeof x[nest[0]] === 'object' ? x[nest[0]][nest[1]] : undefined);
  const nestSet = (x, nest, text) => {
    const v = String(text ?? '').trim();
    const box = x[nest[0]] && typeof x[nest[0]] === 'object' && !Array.isArray(x[nest[0]]) ? x[nest[0]] : {};
    if (v) box[nest[1]] = v;
    else delete box[nest[1]];
    if (Object.keys(box).length) x[nest[0]] = box;
    else delete x[nest[0]];
  };
  {
    const rest = Object.assign({}, BASE_TABLES);
    for (const k of Object.keys(BASE_TABLES)) delete BASE_TABLES[k];
    BASE_TABLES.tracks = rest.tracks;
    delete rest.tracks;
    BASE_TABLES.spheres = {
      word: '문화권', idBase: 'sphere',
      lead: '트랙 위의 층인 문화권입니다. 연표는 문화권마다 가로 머리 단을 두고 문화권째 접고 폅니다. 트랙의 문화권 칸에서 고릅니다. 프로그램에 든 문화권은 없고 모두 DLC가 만듭니다 — 동아시아는 기본팩에 들어 있어 아래에서 가져올 수 있고, 다른 DLC와 id가 같으면 먼저 놓인 쪽이 쓰입니다. 순서는 작을수록 위(비우면 적은 것 뒤에 만든 차례)이고, 문화권을 적지 않은 트랙은 머리 단 없이 모든 문화권 뒤에 놓입니다.',
      cols: [COL.id, COL.name, Object.assign({}, COL.order, { title: '작을수록 위 — 비우면 적은 것 뒤에 만든 차례' }), { key: 'description', label: '설명', type: 'text' }].concat(leaderLabelCols('이 문화권')),
      refs: { id: SPHERE_REFS },
      fresh: id => ({ id, name: '' }),
      delNote: '지우면 그 트랙들은 문화권 없이(모든 문화권 뒤) 놓입니다 — 다른 켠 DLC에 같은 id가 있으면 그것을 따릅니다.',
    };
    /* 문화권별 주기 줄(yearCycles — 형식 4 더하기 · 리메이크 5단계 과제 6 · DLC-형식.md '형식 4 더하기'): 문화권마다 날짜 칸 아래 주기 줄 하나 — 이름 돌림(명칭 목록 · 기준 연도 · 줄 제목)
       또는 연호 눈금(연호 · 원년 · 간격 · 줄 제목). 줄에는 id가 없고 문화권이 열쇠(비우면 전체 줄 = 정보 창의 간지 설정 — HT.syncYearCycles로 서로 따라감: 탭을 열 때 간지 설정 → 전체 줄 · 표를 고치면 전체 줄 → 간지 설정).
       탭은 문화권 바로 다음에. 옛 앱은 전체 줄의 이름 돌림(최상위 yearCycle)만 그리고, 서고 미리보기의 주기 줄은 과제 9 */
    BASE_TABLES.yearCycles = {
      word: '주기',
      lead: '문화권마다 날짜 칸 아래에 놓이는 주기 줄입니다. 문화권을 비우면 전체 줄 — 정보 창의 간지 설정과 같은 것이라 서로 따라갑니다. 한 줄은 이름 돌림(명칭 목록 · 기준 연도 — 해마다 차례로 하나씩 돌아옴)이거나 연호 눈금(연호 · 원년 · 간격 — "연호 410년"처럼 셈)이고, 둘 다 적으면 이름 돌림으로 읽습니다. 문화권마다 한 줄만 — 겹친 줄은 뒤의 것이 빠집니다. 옛 앱은 전체 줄의 이름 돌림(간지 줄)만 그립니다.',
      cols: [
        { key: 'sphere', label: '문화권', type: 'select', title: '이 줄이 놓이는 문화권 — 비우면 전체 줄(정보 창의 간지 설정과 같은 줄)', options: (draft, model) => sphereChoices(draft, model, '전체', '모든 문화권 공통 — 정보 창의 간지 설정과 같은 줄') },
        { key: 'names', label: '명칭 목록', type: 'list', title: `이름 돌림 — 쉼표로 가른 둘 이상의 명칭(해마다 차례로 하나씩 돌아옴 · ${HT.YEAR_CYCLE_LIMITS.names}개 · 하나에 ${HT.YEAR_CYCLE_LIMITS.nameLen}자까지) · "육십갑자" 한 낱말이면 내장 육십갑자(이름 60개로 펴짐 · 기준 연도는 정해져 있음)` },
        { key: 'start', label: '기준 연도', type: 'text', title: '이름 돌림 — 첫 명칭이 붙는 해(그 앞뒤로 이어 셉니다 · 기원전은 "기원전 57"이나 -57)' },
        { key: 'era', label: '연호', type: 'text', title: '연호 눈금 — 연호 이름(명칭 목록을 비웠을 때 · 눈금은 "연호 n년")' },
        { key: 'from', label: '원년', type: 'text', title: '연호 눈금 — 연호 원년(0으로 세는 해 · 기원전은 "기원전 57"이나 -57)' },
        { key: 'step', label: '간격', type: 'number', title: '연호 눈금 — 몇 해마다 눈금을 긋는지(비우면 1)' },
        { key: 'label', label: '줄 제목', type: 'text', title: `날짜 칸 왼쪽의 줄 제목 — 비우면 이름 돌림은 "간지", 연호 눈금은 연호 이름 · ${HT.YEAR_CYCLE_LIMITS.label}자까지` },
      ],
      fresh: () => ({}),
      before: draft => HT.syncYearCycles(draft, 'cycle'), // 탭을 열 때: 정보 창의 간지 설정을 전체 줄로(바뀌었으면 참)
      after: draft => HT.syncYearCycles(draft, 'rows'), // 표를 고친 뒤: 전체 줄을 간지 설정으로
      delNote: '지우면 그 문화권의 주기 줄이 없어집니다 — 전체 줄을 지우면 정보 창의 간지 설정도 육십갑자로 돌아갑니다.',
    };
    Object.assign(BASE_TABLES, rest);
  }
  /** 대범위(s)가 이 DLC의 시대 구분(ep — 작업본의 것)을 가리키는지: id로, 또는 이름(name — 기본은 ep의 이름)으로. 시대 구분에 트랙이 있으면 트랙을 적지 않았거나
      같은 트랙인 대범위만 (HT.buildModel이 대범위의 시대 구분을 찾는 규칙과 같은 뜻) */
  const epochRefMatch = (s, ep, name = ep && ep.name) => {
    const v = str(s && s.epoch);
    if (!v || !ep) return false;
    if (v === str(ep.id)) return true;
    return !!str(name) && v === str(name) && (!str(ep.track) || !str(s.track) || str(s.track) === str(ep.track));
  };
  /** 시대 구분의 이름이 from → to로 바뀌었을 때, 그 이름으로 적은 대범위의 시대 구분 칸을 따라 고칩니다 (id로 적은 것은 그대로). 돌려주는 값: 고친 수 */
  function renameEpochRefs(draft, ep, from, to) {
    if (!str(from) || !str(to) || str(from) === str(to)) return 0;
    let n = 0;
    for (const s of arr(draft.scopes)) {
      if (!s || str(s.epoch) !== str(from) || !epochRefMatch(s, ep, from)) continue;
      s.epoch = str(to);
      n++;
    }
    return n;
  }
  /* 트랙 id를 가리키는 새 칸: 인물의 섬긴 기록(객체의 track · "트랙:정권" 글) · 조약 당사국 줄의 track — 패치에 담긴 것도 */
  BASE_TABLES.tracks.refs.id.push(
    { list: 'figures', path: 'service[].track' },
    Object.assign({ list: 'figures', path: 'service[]' }, trackToken),
    { list: 'events', path: 'treaty.parties[].track' },
    { list: 'patches', path: 'set.service[].track' },
    Object.assign({ list: 'patches', path: 'set.service[]' }, trackToken),
    { list: 'patches', path: 'set.treaty.parties[].track' }
  );
  /* 대범위(scopes): 구성 정권과 상징적 본국의 "트랙:이름" 글과 { track, polity }의 track — 제 트랙(track)은 대범위가 항목 목록(itemLists)에 들어 있어 위의 첫 길이 셉니다(여기에 또 적으면 두 번 봄).
     트랙을 적지 않은 "이름" 글은 정권 이름이라(사건의 tracks와 달리) 트랙 id와 같아도 건드리지 않습니다 */
  const scopeToken = { match: (v, id) => typeof v === 'string' && v.startsWith(`${id}:`), map: (v, from, to) => `${to}${v.slice(from.length)}` };
  BASE_TABLES.tracks.refs.id.push(
    Object.assign({ list: 'scopes', path: 'members[]' }, scopeToken),
    { list: 'scopes', path: 'members[].track' },
    Object.assign({ list: 'scopes', path: 'host' }, scopeToken),
    { list: 'scopes', path: 'host.track' }
  );
  /* 조약 당사국의 "트랙:이름" 글(DLC-형식.md 조약 절) — 당사국 줄이 글이거나, 트랙 칸이 빈 줄의 polity(없으면 name)에 적힌 것(HT.readTreaty가 트랙과 이름으로 나눔).
     트랙 칸이 있는 줄의 polity는 이름 그대로라 건드리지 않습니다 */
  const partyToken = key => ({
    match: (v, id, o) => !str(o && o.track) && (key === 'polity' || (o && o.polity == null)) && scopeToken.match(v, id),
    map: scopeToken.map,
  });
  for (const [list, pre] of [['events', 'treaty.parties'], ['patches', 'set.treaty.parties']])
    BASE_TABLES.tracks.refs.id.push(
      Object.assign({ list, path: `${pre}[]` }, scopeToken),
      Object.assign({ list, path: `${pre}[].polity` }, partyToken('polity')),
      Object.assign({ list, path: `${pre}[].name` }, partyToken('name'))
    );
  /* 지위 사전(rankDefs) · 가문(houses) — 파일 맨 위의 사전 목록 (DLC-형식.md의 rankDefs · houses 절의 칸 그대로).
     지위는 id → 이름 → 별칭으로, 가문은 id → 이름으로 찾으므로 id를 바꿔도 이름을 바꿔도 그 값으로 적은 곳이 따라갑니다(작업본 안만 — 남의 DLC가 적은 것은 그대로).
     지위 변천의 칸은 [지위, 시작, 끝, 메모] · "지위" · { name(또는 rank) } 세 꼴이라 한 칸을 통째로 보고 이름 자리만 바꿉니다 */
  const rankRef = v => (typeof v === 'string' ? v.trim() : Array.isArray(v) ? str(v[0]) : v && typeof v === 'object' ? str(v.name ?? v.rank) : '');
  const rankToken = {
    match: (v, value) => rankRef(v) === value,
    map: (v, from, to) => {
      if (typeof v === 'string') return to;
      if (Array.isArray(v)) v[0] = to;
      else if (v.name != null) v.name = to;
      else v.rank = to;
      return v;
    },
  };
  /* 별칭으로 적은 곳은 쓰는 곳에만 셉니다(countOnly — 별칭은 여러 개라 무엇이 무엇으로 바뀌었는지 알 수 없어 따라 고치지 않음) */
  const aliasToken = { countOnly: true, match: (v, al) => !!rankRef(v) && (Array.isArray(al) ? al : String(al).split(',')).map(str).includes(rankRef(v)) };
  const RANK_PATHS = [['periods', 'ranks[]'], ['periods', 'leaders[].rank'], ['periods', 'reigns[].rank'], ['patches', 'set.ranks[]'], ['patches', 'set.leaders[].rank'], ['patches', 'set.reigns[].rank']];
  const RANK_REFS = RANK_PATHS.map(([list, path]) => Object.assign({ list, path }, rankToken));
  /* 가문을 가리키는 칸: 시대의 국성 · 지도자 · 내각 칸 · 왕조 · 인물 · 다른 가문의 본가 — 패치에 담긴 것도 (HT.buildModel의 가문 잇기와 같은 길) */
  const HOUSE_REFS = [
    { list: 'periods', path: 'house' },
    { list: 'periods', path: 'leaders[].house' },
    { list: 'periods', path: 'reigns[].house' },
    { list: 'periods', path: 'cabinets[].house' },
    { list: 'dynasties', path: 'house' },
    { list: 'figures', path: 'house' },
    { list: 'houses', path: 'parent' },
    { list: 'patches', path: 'set.house' },
    { list: 'patches', path: 'set.leaders[].house' },
    { list: 'patches', path: 'set.reigns[].house' },
    { list: 'patches', path: 'set.cabinets[].house' },
  ];
  const nameCol = what => Object.assign({}, COL.name, { title: `이름을 바꾸면 이 이름으로 적은 ${what}도 따라 바뀝니다` });
  Object.assign(BASE_TABLES, {
    rankDefs: {
      word: '지위', idBase: 'rank',
      lead: '지위 사전입니다. 시대의 지위 변천과 지도자의 지위 칸에 id · 이름 · 별칭을 적으면 여기의 서열로 칸의 짙기가 정해집니다 — 서열은 클수록 높고, 비우면 서열 밖(중립 색)입니다. 별칭은 서열만 빌리고 화면에는 적은 글 그대로 나옵니다. 사전에 없는 지위도 적을 수 있고, 프로그램에 든 기본 지위는 만들지 않아도 쓰입니다 — 기본 지위는 아래에서 같은 id로 가져와 고치면 이 DLC의 것이 쓰이지만, 다른 DLC의 지위는 가져와도 그 DLC가 켜져 있는 동안에는 그쪽 정의가 먼저 쓰입니다.',
      cols: [
        COL.id,
        nameCol('지위 칸'),
        { key: 'tier', label: '서열', type: 'number', title: '클수록 높음 — 비우면 서열 밖' },
        { key: 'aliases', label: '별칭', type: 'list', title: '쉼표로 구분 — 별칭으로 적은 지위는 서열만 빌리고, 화면에는 적은 글 그대로' },
        { key: 'description', label: '설명', type: 'text' },
      ],
      refs: { id: RANK_REFS, name: RANK_REFS, aliases: RANK_PATHS.map(([list, path]) => Object.assign({ list, path }, aliasToken)) },
      builtin: () => HT.RANKS,
      fresh: id => ({ id, name: '' }),
      /* 파일을 읽을 때(HT.readRankDefs) 이름 없는 지위는 빠집니다 — 가문과 달리 id를 이름으로 삼지 않으므로, 서열 · 별칭을 적었어도 연표 · 반영 · 파일로에 없습니다 */
      dropped: x => (str(x.name) ? '' : '이름이 없어 연표에 쓰이지 않고, 반영하거나 파일로 낼 때 빠집니다 — 이름을 적어 주세요.'),
      delNote: '지우면 그 칸들의 지위는 사전에 없는 지위(서열 밖)로 남습니다 — 다른 DLC나 기본 지위에 같은 이름이 있으면 그것을 따릅니다.',
    },
    houses: {
      word: '가문', idBase: 'house', docPrefix: 'house',
      lead: '국성 · 왕가 · 집안 같은 가문입니다. 시대의 국성, 지도자 · 내각 칸, 왕조, 인물의 가문 칸에 이름이나 id를 적습니다 — 등록하지 않은 이름도 쓸 수 있으니, 성 · 본관 · 시조 · 본가 · 색 · 설명을 정할 때만 등록하면 됩니다. 본가를 적으면 본가 → 분가 나무가 됩니다.',
      cols: [
        COL.color,
        COL.id,
        nameCol('곳'),
        { key: 'surname', label: '성', type: 'text' },
        { key: 'seat', label: '본관', type: 'text' },
        { key: 'founder', label: '시조', type: 'text', person: true, title: '시조(본가가 있는 파면 파조) — 인물 id나 "나라:지도자@시작 해"로 적기를 권합니다. 세 글자 넘게 치면 사람 찾기 상자가 뜹니다(계보 전용 인물도)' },
        { key: 'parent', label: '본가', type: 'text', list: 'mkBaseHouseList', title: '본가(갈라져 나온 가문)의 이름이나 id — 비우면 맨 위' },
        /* 세계표 머리의 구분 · 민족 · 꼬리표 (형식 버전 3 — D1 확정 설계 2-2 · 7-2 ②). 비우면 모델이 짐작하고(파일에 적지 않음) 칸 옆 '짐작: …' 딱지로 보입니다 */
        { key: 'track', label: '구분(트랙)', type: 'track', title: '세계표 머리의 구분 — 비우면 국성으로 삼은 나라 · 지도자 칸이 든 나라 · 구성원의 트랙에서 짐작합니다' },
        { key: 'people', label: '민족', type: 'text', list: 'mkBaseHousePeopleList', suggest: (draft, model) => [...new Set(arr(draft && draft.peoples).map(p => p && (p.name || p.id)).concat(arr(model && model.peoples).map(p => p.name)))].filter(Boolean).sort(), title: '세계표 머리의 민족(이름이나 id) — 민족 이름을 바꾸면 따라 바뀝니다. 비우면 같은 나라들의 민족에서 짐작합니다' },
        { key: 'tags', label: '꼬리표', type: 'list', title: '세계표 머리 끝의 꼬리표 — 쉼표로 여럿' },
        { key: 'description', label: '설명', type: 'text' },
      ],
      refs: { id: HOUSE_REFS, name: HOUSE_REFS },
      autoColor: x => HT.pastel(HT.autoColor(`house:${x.id || ''}`)),
      fresh: id => ({ id, name: '' }),
      delNote: '지우면 그곳들은 적힌 글을 이름으로 삼는 "가문 목록에 없는 가문"이 됩니다(성 · 본관 · 본가 · 색이 없어짐).',
      foot: (draft, esc, model) => {
        const names = new Set(arr(draft.houses).map(h => h.name || h.id));
        if (model) (model.houses || []).forEach(h => names.add(h.name));
        const peoples = BASE_TABLES.houses.cols.find(c => c.key === 'people').suggest(draft, model);
        return `<datalist id="mkBaseHouseList">${[...names].filter(Boolean).sort().map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist><datalist id="mkBaseHousePeopleList">${peoples.map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>`;
      },
    },
  });
  /* 가문의 민족 · 구분(형식 버전 3 — D1): 민족의 이름 · id를 바꾸면, 트랙 id를 바꾸면 가문에 적은 것도 따라갑니다 */
  PEOPLE_REFS.push({ list: 'houses', path: 'people' });
  BASE_TABLES.tracks.refs.id.push({ list: 'houses', path: 'track' });
  /* 성씨 · 지명 사전 (형식 버전 3 — DLC-형식.md의 surnames · places 절의 칸 그대로). 이름 목록(names — 원어 · 로마자 · 기간)은 표의 칸 하나에 담을 수 없어
     줄 끝의 [文] 단추로 줄 아래에 펼치는 상자에서 고칩니다(names: true — 가문도 같음). 성씨는 가문의 성(surname)이, 지명은 도읍의 도시 · 사건의 장소 · 다른 지명의 위 구역이
     이름이나 id로 가리키므로 id를 바꿔도 이름을 바꿔도 그 값으로 적은 곳이 따라갑니다(작업본 안만) */
  const SURNAME_REFS = [{ list: 'houses', path: 'surname' }];
  /* 도읍 칸은 [도시, 시작, 끝, 역할] · { city } · { name }(옛 이름) 세 꼴이라 한 칸을 통째로 보고 도시 자리만 바꿉니다 (지위 변천의 rankToken과 같은 방식) */
  const capCity = v => (Array.isArray(v) ? str(v[0]) : v && typeof v === 'object' ? str(v.city ?? v.name) : '');
  const capToken = {
    match: (v, value) => capCity(v) === value,
    map: (v, from, to) => {
      if (Array.isArray(v)) v[0] = to;
      else if (v.city != null) v.city = to;
      else v.name = to;
      return v;
    },
  };
  const PLACE_REFS = [
    Object.assign({ list: 'periods', path: 'capitals[]' }, capToken),
    { list: 'events', path: 'place' },
    { list: 'places', path: 'parent' },
    { list: 'patches', path: 'set.place' },
    Object.assign({ list: 'patches', path: 'set.capitals[]' }, capToken),
    { list: 'maps', path: 'places[]' }, // 지도의 지명 글 목록 (형식 3 — 지도는 아직 입력 칸이 없어 파일로 적은 것만)
    { list: 'events', path: 'treaty.place' }, // 조약의 맺은 곳 (같은 이름이면 같은 지명 — DLC-형식.md 조약 절)
    { list: 'patches', path: 'set.treaty.place' },
  ];
  Object.assign(BASE_TABLES, {
    surnames: {
      word: '성씨', idBase: 'surname', docPrefix: 'surname', names: true,
      lead: '성씨 사전입니다. 가문의 성 칸에 이름이나 id를 적으면 이 성씨로 이어집니다 — 등록하지 않은 성도 쓸 수 있으니(연표가 가문들의 성에서 저절로 모음), 원어 · 로마자를 달 때만 등록하면 됩니다. 줄 끝의 文 단추로 이름(원어 등)을 적습니다.',
      cols: [COL.id, nameCol('가문의 성'), { key: 'description', label: '설명', type: 'text' }],
      refs: { id: SURNAME_REFS, name: SURNAME_REFS },
      fresh: id => ({ id, name: '' }),
      delNote: '지우면 그 가문들의 성은 "성씨 사전에 없는 성"으로 남습니다(원어 · 설명이 없어짐).',
    },
    places: {
      word: '지명', idBase: 'place', docPrefix: 'place', names: true,
      lead: '지명 사전입니다. 도읍의 도시 칸 · 사건의 장소 칸에 이름이나 id를 적으면 이 지명으로 이어집니다 — 등록하지 않은 이름도 쓸 수 있으니(그 이름으로 저절로 생김), 원어 · 좌표 · 위 구역을 달 때만 등록하면 됩니다. 좌표는 지도가 실제 지리면 경도, 위도 · 그림이면 그림의 픽셀입니다. 줄 끝의 文 단추로 이름(원어 등)을 적습니다.',
      cols: [
        COL.id,
        nameCol('도읍 · 장소'),
        { key: 'parent', label: '위 구역', type: 'text', list: 'mkBasePlaceList', title: '위 구역(이 지명을 품은 지명)의 이름이나 id — 비우면 맨 위' },
        { key: 'at', label: '좌표', type: 'pair', title: 'x, y 두 수 — 실제 지리면 경도, 위도 · 그림 지도면 픽셀 (비워도 됨)' },
        { key: 'note', label: '메모', type: 'text' },
        { key: 'description', label: '설명', type: 'text' },
      ],
      refs: { id: PLACE_REFS, name: PLACE_REFS },
      cellDocs: true, // 도읍 칸의 문서 열쇠(cell:나라:capitals:도시@해)가 도시 글을 담으므로, 따라 고친 도읍의 문서도 옮깁니다
      fresh: id => ({ id, name: '' }),
      delNote: '지우면 그곳들은 적힌 글을 이름으로 삼는 "지명 사전에 없는 지명"이 됩니다(원어 · 좌표 · 위 구역이 없어짐).',
      foot: (draft, esc, model) => {
        const names = new Set(arr(draft.places).map(p => p.name || p.id));
        if (model) (model.places || []).forEach(p => names.add(p.name));
        return `<datalist id="mkBasePlaceList">${[...names].filter(Boolean).sort().map(n => `<option value="${esc(n)}"></option>`).join('')}</datalist>`;
      },
    },
  });
  BASE_TABLES.houses.names = true; // 가문의 이름 목록도 줄 끝 文 단추로

  /* 대범위(scopes) — 시대 구분처럼 표가 아니라 편집 창의 폼(HT.FORMS.scope)으로 고칩니다. 창에는 이 DLC의 대범위 목록만(누르면 편집 창 · 📄 문서 · 🗑 삭제).
     꺼 두면 연표에 테두리가 없어 찾기 어려우므로 여기서 훑어 엽니다. 새 대범위는 [＋ 대범위 추가]나 연표의 추가 메뉴로 */
  Object.assign(BASE_TABLES, {
    scopes: {
      word: '대범위', form: 'scope',
      lead: '흩어진 나라들을 한 집합으로 묶어 켜고 끄는 대범위입니다. 누르면 오른쪽 편집 창에서 고칩니다(편집 창 맨 위의 [모아 보기]로 연표에서 켜고 끔). 구성 정권은 같은 트랙의 정권만 모입니다 — 무엇이 모이지 않는지는 [검사]에.',
    },
  });

  /* 주제 사전(themes) · 단체(groups) · 제도 칸(institutions) — 형식 버전 3 (DLC-형식.md의 같은 절 · docs/구상-연표-확장-10건.md 3-7 · 3-8).
     주제 사전은 지위 사전처럼 표로(내장 뼈대 여덟은 '가져오기'로 같은 id에 실어 고침), 단체 · 제도는 대범위처럼 편집 창의 폼으로 고칩니다.
     주제는 id → 이름으로 찾으므로 id를 바꿔도 이름을 바꿔도 그 값으로 적은 곳(제도의 주제 · 사건의 꼬리표 — 목록이나 쉼표 글)이 따라갑니다 */
  const themeText = { match: (v, value) => typeof v === 'string' && v.split(/[,，]/).map(str).includes(value), map: (v, from, to) => v.split(/[,，]/).map(str).map(x => (x === from ? to : x)).join(', ') };
  const THEME_REFS = [
    { list: 'events', path: 'theme[]' },
    Object.assign({ list: 'events', path: 'theme' }, themeText),
    { list: 'institutions', path: 'theme' },
    { list: 'patches', path: 'set.theme[]' },
    Object.assign({ list: 'patches', path: 'set.theme' }, themeText),
  ];
  Object.assign(BASE_TABLES, {
    themes: {
      word: '주제', idBase: 'theme',
      lead: '렌즈의 주제 사전입니다. 제도 칸의 주제와 사건의 주제 꼬리표에 id나 이름을 적습니다 — 프로그램에 든 기본 주제 여덟(체제 · 붕당 · 법률 · 선거제도 · 이념 · 군사제도 · 조세제도 · 선발제도)은 만들지 않아도 쓰이므로, 새 주제만 더하면 됩니다. 기본 주제의 이름 · 색 · 설명을 바꾸려면 아래에서 같은 id로 가져와 고칩니다. 연표의 렌즈 차림표에서 빼려면 \'렌즈에서 숨김\'을 켭니다(기본 주제는 가져와서 — 자료 · 상세 창은 그대로이고 렌즈 고르기에서만 빠짐). 사전에 없는 이름도 적을 수 있지만 검사에서 알립니다. 줄 끝의 文 단추로 이름(원어 등)을 적습니다.',
      cols: [
        COL.color,
        COL.id,
        nameCol('제도의 주제 · 사건의 꼬리표'),
        { key: 'kind', label: '갈래', type: 'text', title: '주제의 갈래 — 자유 글 (선택 · 렌즈 차림표에 한마디로 나옴)' },
        { key: 'description', label: '설명', type: 'text' },
        { key: 'hidden', label: '렌즈에서 숨김', type: 'check', title: '켜면 연표의 렌즈 차림표 · 단축키 S에서 이 주제가 빠집니다 — 켠 DLC 가운데 하나라도 숨기면 숨김 (형식 3)' },
      ],
      refs: { id: THEME_REFS.concat({ list: 'views', path: 'settings.lens' }), name: THEME_REFS }, // 판의 렌즈(settings.lens)는 주제 id 글 — id만 따라감
      builtin: () => HT.THEMES,
      autoColor: x => HT.pastel(HT.autoColor(`theme:${x.id || ''}`)),
      fresh: id => ({ id, name: '' }),
      /* 파일을 읽을 때(HT.readThemeDefs) 이름 없는 주제는 빠집니다 — 지위 사전과 같게. 다만 id만 적고 '렌즈에서 숨김'을 켠 줄은 숨김만 보태는 줄로 남습니다 */
      dropped: x => (str(x.name) || (x.hidden === true && str(x.id)) ? '' : '이름이 없어 연표에 쓰이지 않고, 반영하거나 파일로 낼 때 빠집니다 — 이름을 적어 주세요(렌즈에서 숨기기만 하려면 \'렌즈에서 숨김\'을 켬).'),
      delNote: '지우면 그곳들의 주제는 "사전에 없는 주제"로 남습니다(검사에서 알림) — 기본 주제와 id · 이름이 같으면 기본 주제를 따릅니다.',
    },
    groups: {
      word: '단체', form: 'group',
      lead: '붕당 · 정당 · 정권(실권 집단) · 세력 · 연합 같은 단체입니다. 누르면 오른쪽 편집 창에서 고칩니다. 연표에는 아직 띠 안 그림이 없어(모양은 설계에서 정함) 상세 창 · 검색 · 나라 상세의 칩으로 봅니다.',
    },
    institutions: {
      word: '제도', form: 'institution',
      lead: '나라마다 주제마다 이어지는 제도 칸입니다(렌즈의 재료). 누르면 오른쪽 편집 창에서 고칩니다. 같은 갈래의 제도는 나라가 달라도 같은 색으로 묶입니다.',
    },
  });
  BASE_TABLES.themes.names = true; // 주제의 이름 목록(원어 · 다른 이름 — 형식 3)도 가문 · 성씨 · 지명처럼 줄 끝 文 단추로
  /* 단체의 있던 나라 · 구성 나라와 제도의 나라 · 칸의 온 곳이 가리키는 트랙: { track } 칸과 "트랙:이름" 글 — 패치에 담긴 것도 (제 트랙 track은 항목 목록(itemLists)의 첫 길이 셈) */
  BASE_TABLES.tracks.refs.id.push(
    ...[['groups', ''], ['patches', 'set.']].flatMap(([list, pre]) => [
      Object.assign({ list, path: `${pre}within` }, scopeToken),
      Object.assign({ list, path: `${pre}within[]` }, scopeToken),
      { list, path: `${pre}within[].track` },
      Object.assign({ list, path: `${pre}members[]` }, scopeToken),
      { list, path: `${pre}members[].track` },
      Object.assign({ list, path: `${pre}spans[].from` }, scopeToken),
      { list, path: `${pre}spans[].from.track` },
      { list, path: `${pre}people[].track` }, // 단체의 구성원 — 지도자 칸으로 적은 사람 참조의 트랙 (형식 3 — 사람 잇기)
    ]),
    Object.assign({ list: 'institutions', path: 'polity' }, scopeToken),
    { list: 'institutions', path: 'polity.track' },
    Object.assign({ list: 'institutions', path: 'spans[].from' }, scopeToken),
    { list: 'institutions', path: 'spans[].from.track' }
  );
  /* 형식 3의 다른 나라 참조(F3 — 모아 보기 판의 구성 나라 · 지도 장면의 구역 주인: "트랙:이름" · { track, polity })와
     사람 참조의 트랙(F1 — 지도자 · 내각 칸의 사람 · 자리 이음의 앞 지도자 · 부모 · 배우자: { track, polity, leader, start }) — 패치에 담긴 것도 */
  const PERSON_TRACK_PATHS = ['leaders', 'reigns'].flatMap(k => [`${k}[].person.track`, `${k}[].accession.from.track`, `${k}[].parents[].who.track`, `${k}[].spouses[].who.track`]).concat('cabinets[].person.track');
  BASE_TABLES.tracks.refs.id.push(
    Object.assign({ list: 'views', path: 'members[]' }, scopeToken),
    { list: 'views', path: 'members[].track' },
    Object.assign({ list: 'maps', path: 'frames[].owners{}' }, scopeToken),
    { list: 'maps', path: 'frames[].owners{}.track' },
    ...PERSON_TRACK_PATHS.flatMap(path => [{ list: 'periods', path }, { list: 'patches', path: `set.${path}` }]),
    ...['parents[].who.track', 'spouses[].who.track'].flatMap(path => [{ list: 'figures', path }, { list: 'patches', path: `set.${path}` }])
  );
  /* 트랙의 설명(2026-10-23 — 전역 확대 ①): 트랙 문서(📄)와 별도의 짧은 설명 글 */
  BASE_TABLES.tracks.cols.push({ key: 'description', label: '설명', type: 'text', title: '트랙의 짧은 설명 — 긴 글은 줄 끝 📄 문서로' });
  /* 지도(maps — 형식 3 1단계) · 글꼴(fonts) · 영토(territory — 보류 중인 옛 지도의 형식) 표 (2026-10-23 — "메이커로 못 바꾸는 곳이 없도록" ⑤ ⑥ ⑧).
     깊은 칸(구역의 모양 · 장면의 주인 · 영토의 단위 · 소유 기록 …)은 JSON 글 칸(type 'json' — 읽히는 글만 작업본에 적고, 잘못된 글은 칸을 붉게 두고 적지 않음)으로,
     그림 · 글꼴 파일은 파일 칸(type 'file' — [파일] 단추로 골라 data URL로 담음 · 그림은 긴 변 1600px로 줄임)으로 적습니다.
     지도의 구역 · 장면은 줄 아래에 펼치는 하위 표(t.subs — 이름 상자와 같은 길)로, 지도에 놓을 지명은 글 목록(쉼표)으로.
     영토는 목록이 아니라 객체 하나라(t.object) 표에 줄이 하나뿐입니다 — [＋ 영토 추가]로 만들고 🗑로 통째로 지웁니다 */
  const JSON_TIP = 'JSON 글 — 읽히는 글만 저장되고, 잘못된 글은 칸이 붉게 남습니다(DLC-형식.md의 꼴 그대로)';
  Object.assign(BASE_TABLES, {
    maps: {
      word: '지도', idBase: 'map', docPrefix: 'map',
      lead: '그림 한 장을 바탕으로 한 지도(형식 3 · 1단계)입니다. 좌표 방식이 그림 좌표면 크기(너비, 높이)가 꼭 있어야 하고, 바탕 그림은 [파일]로 담습니다. 행정 층위 · 구역의 모양 · 장면의 주인은 형식 문서의 꼴 그대로 JSON 글로 적고, 구역 · 장면은 줄 끝의 단추로 줄 아래에 펼쳐 고칩니다. 지도만 담은 DLC는 팩 정보의 분류를 지도팩으로.',
      cols: [
        COL.id,
        COL.name,
        { key: 'crs', label: '좌표 방식', type: 'select', options: HT.MAP_CRS.map(c => ({ id: c.id, name: c.name })), title: '그림 좌표(그림의 화소 · 왼쪽 위가 0, 0) · 경위도' },
        { key: 'size', label: '크기', type: 'pair', title: '너비, 높이 — 그림 좌표 지도에 필수(바탕 그림의 화소 크기와 같게)' },
        { key: 'image', label: '바탕 그림', type: 'file', accept: 'image/png,image/jpeg,image/webp', image: true, limit: HT.PACK_LIMITS.mapImage, title: '바탕 그림 — png · jpg · webp (긴 변 1600px로 줄여 담음)' },
        { key: 'levels', label: '행정 층위', type: 'json', title: `행정 층위 — ["주", "군"] 또는 [{ "id": "…", "name": "…" }] (첫째가 가장 넓은 단위) · ${JSON_TIP}` },
        { key: 'places', label: '지명', type: 'list', title: '이 지도에 놓을 지명 — 지명 사전의 이름이나 id를 쉼표로' },
        { key: 'source', label: '출처', type: 'text', title: '그림 · 경계의 출처 — 올린 그림의 권리는 만든 사람의 몫' },
        { key: 'description', label: '설명', type: 'text' },
        { key: 'note', label: '메모', type: 'text' },
      ],
      subs: [
        {
          key: 'regions', word: '구역', fresh: () => ({ id: '', shape: [] }),
          cols: [
            { key: 'id', label: 'id', type: 'text', title: '이 지도 안에서 하나 — 무슨 글이든' },
            { key: 'name', label: '이름', type: 'text', title: '비우면 id' },
            { key: 'level', label: '층위', type: 'text', title: '행정 층위의 id' },
            { key: 'parent', label: '위 구역', type: 'text', title: '같은 지도의 구역 id' },
            { key: 'start', label: '시작', type: 'number', title: '구역이 생긴 해(비워도 됨)' },
            { key: 'end', label: '끝', type: 'number', title: '구역이 없어진 해 — 끝 해에는 이미 없음(비워도 됨)' },
            { key: 'shape', label: '모양', type: 'json', title: `고리 하나 [[x, y], …] 또는 여러 고리 [[[x, y], …], …] · ${JSON_TIP}` },
            { key: 'names', label: '이름 목록', type: 'json', title: `원어 · 옛 이름 — [{ "text": "…", "lang": "…" }] · ${JSON_TIP}` },
            { key: 'note', label: '메모', type: 'text' },
          ],
        },
        {
          key: 'frames', word: '장면', fresh: () => ({ year: '' }),
          cols: [
            { key: 'year', label: '열쇠 해', type: 'text', title: '수나 날짜 글(650-03-01) — 장면 하나 = 열쇠 해 하나' },
            { key: 'owners', label: '주인', type: 'json', title: `{ "구역 id": "나라 참조" } — null이면 주인 없는 땅 · 앞 장면을 이어받고 적은 구역만 바뀜 · ${JSON_TIP}` },
            { key: 'image', label: '그 해의 그림', type: 'file', accept: 'image/png,image/jpeg,image/webp', image: true, limit: HT.PACK_LIMITS.mapImage, title: '그 해의 그림 한 장 — 다음 그림이 있는 장면까지 이어 씀' },
            { key: 'note', label: '메모', type: 'text' },
          ],
        },
      ],
      fresh: id => ({ id, name: '', crs: 'image' }),
      delNote: '지우면 이 지도와 그 구역 · 장면이 모두 없어집니다(문서는 남음).',
    },
    fonts: {
      word: '글꼴', idBase: 'font',
      lead: 'DLC가 함께 싣는 글꼴입니다(형식 3). 글꼴 파일은 [파일]로 담고(woff2 · woff · ttf · otf — 하나에 약 2.9MB · 한 DLC에 여덟), 라이선스(쓸 수 있는 조건)를 비우면 그 글꼴은 빠집니다. 문자 꼬리표(Hang · Hani · Latn …)와 덮는 유니코드 범위(U+AC00-D7A3)는 쉼표로 여럿.',
      cols: [
        COL.id,
        { key: 'family', label: '글꼴 이름', type: 'text', title: '화면에서 고를 이름' },
        { key: 'src', label: '파일', type: 'file', accept: '.woff2,.woff,.ttf,.otf,font/woff2,font/woff,font/ttf,font/otf', limit: HT.PACK_LIMITS.font, title: '글꼴 파일 — woff2 · woff · ttf · otf' },
        { key: 'license', label: '라이선스', type: 'text', title: '쓸 수 있는 조건 — 비우면 이 글꼴은 빠짐' },
        { key: 'scripts', label: '문자', type: 'list', title: '문자 꼬리표(ISO 15924 네 글자 — Hang · Hani · Latn · Arab, 가상 문자는 Qaaa ~ Qabx) — 쉼표로 여럿' },
        { key: 'ranges', label: '유니코드 범위', type: 'list', title: '실제로 덮는 범위 — U+F1A00-F1A0B, U+AC00-D7A3 — 쉼표로 여럿' },
        { key: 'note', label: '메모', type: 'text' },
      ],
      fresh: id => ({ id, family: '' }),
      dropped: x => (str(x.family) && str(x.license) && str(x.src) ? '' : '글꼴 이름 · 파일 · 라이선스가 모두 있어야 연표에 실립니다 — 비운 칸을 채워 주세요.'),
      delNote: '지우면 이 글꼴로 그리던 원어 문자는 화면 글꼴로 돌아갑니다.',
    },
    territory: {
      word: '영토', object: true,
      lead: '옛 지형 팩 지도의 영토 자료입니다(보류 중인 형식 — 지도를 다시 붙이면 그대로 쓰임). 목록이 아니라 한 덩어리라 줄이 하나뿐입니다. 지도 전용 정권 · 조각 지명 · 단위 · 소유 기록은 형식 문서(DLC-형식.md의 territory 절)의 꼴 그대로 JSON 글로 적습니다. 그림 바탕의 새 지도는 「지도」 표에.',
      cols: [
        { key: 'basemap', label: '지형 팩', type: 'text', title: '지형 팩 id — 비우면 east-asia-v3' },
        { key: 'unitPacks', label: '단위 팩', type: 'list', title: '함께 불러올 단위 팩 id — 쉼표로 여럿' },
        { key: 'polities', label: '지도 전용 정권', type: 'json', title: `[{ "id", "name", "color", "start", "end", "kind", "track", "period" }] · ${JSON_TIP}` },
        { key: 'names', label: '조각 지명', type: 'json', title: `{ "조각 id": [[시작, 끝, "이름", "상위"], …] } · ${JSON_TIP}` },
        { key: 'units', label: '단위', type: 'json', title: `[{ "id", "name", "level", "parent", "start", "end", "cells": [조각 id…] }] · ${JSON_TIP}` },
        { key: 'ownership', label: '소유 기록', type: 'json', title: `{ "조각 id 또는 단위 id": [[시작, 끝, "트랙:정권", "상태", "상대"], …] } · ${JSON_TIP}` },
      ],
      fresh: () => ({}),
      delNote: '지우면 영토 자료가 통째로 없어집니다.',
    },
  });

  /** 단체 · 제도 칸 · 사건의 주제 검사 (메이커의 검사 창 — 모델에서야 알 수 있는 것만): 찾지 못한 나라 · 주제 · 앞선 단체 · 사건, 같은 나라 · 같은 주제의 제도끼리 겹치는 칸,
      찾은 구성 나라가 하나뿐인 연합(모두 모델 항목의 warnings), 자리를 정할 수 없어 연표에 없는 제도, 사전에 없는 주제를 단 사건. 한 줄은 { msg, kind, index } (index = 작업본 목록의 차례) */
  function lensChecks(pack, model, draft) {
    const out = [];
    if (!pack || !model || !draft) return out;
    for (const [list, word] of [['groups', '단체'], ['institutions', '제도']]) {
      for (const raw of arr(pack[list])) {
        const index = arr(draft[list]).findIndex(x => x && x.id === raw.id);
        if (index < 0) continue;
        const x = model.byUid.get(`${pack.id}/${raw.id}`);
        const label = `${word} #${index + 1} "${(x && x.name) || raw.name || [raw.polity, raw.theme].filter(Boolean).join(' · ') || raw.id}"`;
        if (!x) {
          if (list === 'institutions') out.push({ msg: `${label}: 나라도 칸의 연대도 찾지 못해 자리를 정할 수 없습니다 — 연표에 쓰이지 않습니다.`, kind: list, index });
          continue;
        }
        for (const w of arr(x.warnings)) out.push({ msg: `${label}: ${w}`, kind: list, index });
      }
    }
    for (const e of arr(pack.events)) {
      const x = model.byUid.get(`${pack.id}/${e.id}`);
      const auto = x ? arr(x.themeRefs).filter(t => t.auto) : [];
      if (!auto.length) continue;
      const index = arr(draft.events).findIndex(y => y && y.id === e.id);
      out.push({ msg: `사건 #${index + 1} "${e.title}": 주제 ${auto.map(t => `"${t.name}"`).join(' · ')}이(가) 주제 사전에 없습니다 — 그 이름으로 주제를 만들어 묶습니다(바탕 자료의 주제에 더하면 색 · 설명을 정할 수 있음).`, kind: 'events', index });
    }
    return out;
  }

  /** 대범위의 검사 (메이커의 검사 창 — 파일 검사(HT.normalizePack)가 주지 않는 것만): pack = 정규화한 작업본 · model = 그것을 얹은 모델 · rawList = 작업본의 scopes(검사 창의 줄 번호) ·
      fileWarnings = 파일 검사의 경고(같은 뜻을 두 번 적지 않게). 돌려주는 값 { warnings, notes } — 한 줄은 { msg, kind: 'scopes', index }.
      경고: 모델에서 찾지 못한 구성 정권 · 상징적 본국 · 시대 구분, 본국이 다른 트랙, 기간을 정할 수 없어 그려지지 않는 대범위, (파일 검사가 못 본) 다른 트랙의 구성 정권 · 구성 정권에 든 본국.
      알림(경고가 아님): 켜면 구성 정권이 승계로 한 줄을 쓰던 정권(같은 트랙 · 같은 민족 묶음 · 구성 정권도 본국도 아님)에게서 떠나 그 줄이 나뉘는 곳 — 승계선은 그대로 이어집니다 */
  function scopeChecks(pack, model, rawList, fileWarnings = []) {
    const out = { warnings: [], notes: [] };
    if (!pack || !model) return out;
    const peopleKey = p => (p.peoplePath || []).map(pe => (pe ? pe.id : '')).join('/');
    for (const raw of arr(pack.scopes)) {
      const index = arr(rawList).findIndex(x => x && x.id === raw.id);
      if (index < 0) continue;
      const s = model.byUid.get(`${pack.id}/${raw.id}`);
      const label = `대범위 #${index + 1} "${(s && s.name) || raw.name || raw.epoch || raw.id}"`;
      const put = (list, msg) => out[list].push({ msg: `${label}: ${msg}`, kind: 'scopes', index });
      if (!s) {
        put('warnings', '기간을 정할 것이 없어 연표에 그려지지 않습니다 — 시작 연도를 적거나, 시대 구분 · 구성 정권을 연표에서 찾을 수 있게 고쳐 주세요.');
        continue;
      }
      const filed = arr(fileWarnings).filter(w => w && w.kind === 'scopes' && w.index === index).map(w => w.msg);
      /* 파일 검사는 트랙을 적어 가리킨("트랙:정권") 다른 트랙의 구성 정권만 알립니다 — 모델 경고 가운데 그 정권들의 것만 빼고,
         트랙 없이 id · uid로 적었는데 다른 트랙에서 찾아진 정권의 경고는 남깁니다. 경고 글에는 이름만 있으므로 이름별 개수로 뺍니다(같은 이름이 둘이면 하나씩) */
      const told = new Map();
      if (filed.some(f => /다른 트랙의 정권/.test(f))) {
        const found = new Set();
        for (const ref of HT.readScopeRefs(s.memberRefs)) {
          if (!ref.track || ref.track === s.track) continue;
          const m = s.members.find(q => q !== s.host && q.track === ref.track && (q.name === ref.polity || q.id === ref.polity || q.uid === ref.polity));
          if (m) found.add(m);
        }
        for (const m of found) told.set(m.name, (told.get(m.name) || 0) + 1);
      }
      const dup = w => {
        const other = /^구성 정권 "(.*)"은\(는\) 다른 트랙에 있어 모이지 않습니다/.exec(w);
        if (other) {
          const n = told.get(other[1]) || 0;
          if (n) told.set(other[1], n - 1);
          return n > 0;
        }
        return /구성 정권에도 들어 있습니다/.test(w) && filed.some(f => /구성 정권에도 들어 있습니다/.test(f));
      };
      for (const w of arr(s.warnings)) if (!dup(w)) put('warnings', w);
      const inScope = new Set(s.members);
      const seen = new Set();
      for (const m of s.members) {
        if (m.track !== s.track) continue;
        const partners = arr(m.predecessors)
          .map(e => e && e.from)
          .filter(q => q && q.endY <= m.start + 1e-9)
          .concat(arr(m.successors).map(e => e && e.to).filter(q => q && q.start >= m.endY - 1e-9));
        for (const q of partners) {
          if (!q.uid || q === s.host || inScope.has(q) || q.track !== m.track || q.itemKind !== 'period' || peopleKey(q) !== peopleKey(m)) continue;
          const key = [m.uid, q.uid].sort().join('|');
          if (seen.has(key)) continue;
          seen.add(key);
          put('notes', `켜면 구성 정권 «${m.name}»이(가) 승계로 한 줄을 쓰던 «${q.name}»에게서 떠나 그 줄이 나뉩니다 — 승계선은 그대로 이어집니다. 함께 모으려면 «${q.name}»도 구성 정권에, 그 줄 바로 아래에 모으려면 상징적 본국으로 적습니다.`);
        }
      }
    }
    return out;
  }
  const specLists = spec => [].concat(typeof spec.list === 'function' ? spec.list() : spec.list);
  const refMatch = (spec, v, value, holder) => (spec.match ? spec.match(v, value, holder) : v === value);
  /** 이 줄(x)을 가리키는 항목들(역참조): [{ list, item }] — 참조 열마다 그 값을 가리키는 곳 */
  function findUsers(draft, table, x) {
    const out = [];
    const seen = new Set();
    for (const [key, specs] of Object.entries(table.refs || {})) {
      const value = x && x[key];
      if (value == null || value === '') continue;
      for (const spec of specs) {
        for (const list of specLists(spec)) {
          for (const item of arr(draft[list])) {
            if (!item || seen.has(item) || item === x) continue;
            let hit = false;
            walkPath(item, spec.path, (v, set, holder) => {
              if (refMatch(spec, v, value, holder)) hit = true;
            });
            if (hit) {
              seen.add(item);
              out.push({ list, item });
            }
          }
        }
      }
    }
    return out;
  }
  /** 문서 키 from(과 그 하위 문서)을 to로 옮깁니다 — 옮긴 수 */
  const moveDocs = (draft, from, to) => {
    let n = 0;
    for (const k of Object.keys(draft.documents || {})) {
      if (k !== from && !k.startsWith(`${from}//`)) continue;
      draft.documents[to + k.slice(from.length)] = draft.documents[k];
      delete draft.documents[k];
      n++;
    }
    return n;
  };
  /** 참조 열 key의 값이 from → to로 바뀌었을 때, 그 값을 가리키던 곳을 모두 따라 고칩니다(id가 바뀌면 그 줄의 문서도). 돌려주는 값: 고친 곳의 수 */
  function renameRefs(draft, table, key, from, to) {
    if (!from || from === to) return 0;
    let n = 0;
    const cellsBefore = table.cellDocs && HT.makerGrid && draft.documents ? JSON.parse(JSON.stringify(arr(draft.periods))) : null; // 도읍 칸 문서를 옮기려고 (지명)
    for (const spec of (table.refs || {})[key] || []) {
      if (spec.countOnly) continue; // 쓰는 곳에만 세는 길
      for (const list of specLists(spec)) {
        for (const item of arr(draft[list])) {
          walkPath(item, spec.path, (v, set, holder) => {
            if (!refMatch(spec, v, from, holder)) return;
            set(spec.map ? spec.map(v, from, to) : to);
            n++;
          });
        }
      }
    }
    if (key === 'id' && table.docPrefix && to) n += moveDocs(draft, `${table.docPrefix}:${from}`, `${table.docPrefix}:${to}`);
    /* 도시 글이 바뀐 도읍 칸의 문서(cell:나라:capitals:도시@해)도 새 열쇠로 — 같은 열쇠의 문서가 이미 있으면 그 칸은 그대로 둡니다 */
    if (cellsBefore)
      for (const before of cellsBefore) {
        const after = arr(draft.periods).find(q => q && q.id === before.id);
        if (!after || JSON.stringify(before.capitals) === JSON.stringify(after.capitals)) continue;
        try {
          n += HT.makerGrid.moveCellDocuments(draft, `${draft.id}/${before.id}`, before, after);
        } catch (e) {
          /* 옮길 자리에 다른 문서가 있음 — 그대로 */
        }
      }
    return n;
  }
  /** 단체의 이름이 from → to로 바뀌었을 때, 그 이름으로 적은 이 DLC의 앞선 단체(groups[].from — 글 · { group } · 패치의 set.from)를 따라 고칩니다(id로 적은 것은 그대로).
      옛 이름의 단체가 이 DLC에 또 있으면 어느 쪽을 가리켰는지 알 수 없어 그대로 둡니다. 돌려주는 값: 고친 곳의 수 */
  function renameGroupRefs(draft, group, from, to) {
    from = str(from);
    to = str(to);
    if (!from || !to || from === to || !group) return 0;
    if (arr(draft.groups).some(g => g && g.id !== group.id && str(g.name) === from)) return 0;
    let n = 0;
    const one = v => {
      if (typeof v === 'string') {
        if (str(v) !== from) return v;
        n++;
        return to;
      }
      if (v && typeof v === 'object' && !Array.isArray(v)) {
        const k = v.group != null ? 'group' : 'name';
        if (str(v[k]) === from) {
          v[k] = to;
          n++;
        }
      }
      return v;
    };
    const fix = holder => {
      if (holder && holder.from != null) holder.from = Array.isArray(holder.from) ? holder.from.map(one) : one(holder.from);
    };
    for (const g of arr(draft.groups)) if (g && g.id !== group.id) fix(g);
    for (const p of arr(draft.patches)) if (p && p.set && typeof p.set === 'object' && !Array.isArray(p.set)) fix(p.set);
    return n;
  }
  /** 쓰는 곳 요약 글: "시대 2 · 사건 5" */
  const usageText = users => {
    const count = new Map();
    for (const { list } of users) count.set(list, (count.get(list) || 0) + 1);
    return [...count].map(([list, n]) => `${listWord(list)} ${n}`).join(' · ');
  };
  const listWord = list =>
    list === 'patches'
      ? '패치'
      : kindOfList(list) && HT.FORMS[kindOfList(list)]
        ? HT.FORMS[kindOfList(list)].word
        : BASE_TABLES[list]
          ? BASE_TABLES[list].word
          : (Object.values(HT.FORMS || {}).find(F => F && F.list === list) || {}).word || { views: '모아 보기 판', maps: '지도' }[list] || list; // 항목 목록 밖의 폼(대범위)도 제 이름으로 · 폼이 아직 없는 형식 3의 판 · 지도도 한국어로
  /** base를 바탕으로 taken에 없는 id */
  const uniqueId = (base, taken) => {
    const stem = HT.ID_RE.test(base) ? base : `x-${HT.hash(base)}`;
    let id = stem;
    for (let k = 2; taken.has(id); k++) id = `${stem}-${k}`;
    return id;
  };
  /** 같은 id의 정의를 가진 팩 중 맨 앞의 것(없으면 null) — 바탕 자료의 사전(트랙 · 분류 · 민족 · 지위 · 가문)은 id로 합치며 먼저 놓인 정의가 이기는데,
      메이커의 모델은 켜져 있는 다른 팩들(packs) 뒤에 작업본을 얹으므로 이 팩이 켜져 있는 동안 작업본의 그 줄은 연표에 쓰이지 않습니다 */
  const shadowOf = (packs, list, id) => (id ? arr(packs).find(p => p && arr(p[list]).some(d => d && d.id === id)) || null : null);

  /** 작업본의 DLC id를 바꿉니다: 제 항목의 문서 키는 상대 키로 모아(새 id를 따라가게) · 제 항목을 가리키던 패치의 대상도 새 id로 · 함께 쓰면 좋은 DLC에서 자기 자신은 뺌.
      설치돼 있던 옛 id의 DLC와 다른 DLC가 옛 id의 항목에 건 패치 · 문서는 그대로입니다 (반영하면 새 DLC로 설치됨). 돌려주는 값: 고친 곳의 수 */
  function renameDlc(draft, to) {
    const from = draft.id;
    if (!to || to === from) return 0;
    let n = 0;
    const docs = {};
    for (const [k, text] of Object.entries(draft.documents || {})) {
      const rel = HT.docKey.relative(HT.docKey.absolute(k, from), from);
      if (rel !== k) n++;
      docs[rel] = text;
    }
    draft.documents = docs;
    for (const p of arr(draft.patches)) {
      if (!p || typeof p.target !== 'string' || !p.target.startsWith(`${from}/`)) continue;
      p.target = `${to}/${p.target.slice(from.length + 1)}`;
      n++;
    }
    draft.requires = arr(draft.requires).filter(r => r !== to);
    if (Array.isArray(draft.relations)) {
      draft.relations = draft.relations.filter(r => !r || r.id !== to); // 새 id를 가리키던 관계는 이제 자기 자신 — 지움
      if (!draft.relations.length) delete draft.relations;
    }
    draft.id = to;
    return n;
  }

  /* ---------- 바탕 판: 작업본이 어느 설치본에서 왔는지 ----------
   * 작업본은 가져온 뒤로 설치본을 따라가지 않습니다. 그래서 가져온(또는 마지막으로 반영한) 설치본의 지문을 따로 적어 두고(메이커 부품의 ORIGIN_KEY),
   * 설치본이 그 뒤에 바뀌면(DLC 관리의 설치 · 백업 복원 · 다른 탭의 반영) 무엇을 할지 여기서 정합니다 */
  const sortedJSON = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(n => [n, x[n]])) : x));
  const sigCache = new WeakMap();
  /** 정규화한 DLC의 지문 (없으면 null) — 내보낼 때와 같은 JSON(HT.packToJSON)을 열쇠 차례와 상관없이. 같은 팩 객체는 한 번만 셉니다 */
  const packSig = pack => {
    if (!pack || typeof pack !== 'object') return null;
    if (!sigCache.has(pack)) {
      const s = sortedJSON(HT.packToJSON(pack));
      sigCache.set(pack, `${s.length.toString(36)}-${HT.hash(s)}`);
    }
    return sigCache.get(pack);
  };
  /** 설치본과 작업본의 바탕을 견줘 할 일: rec = 적어 둔 바탕({ sig } — 이 작업본의 기록이 없으면 null, sig가 null이면 "설치본 없이 시작") ·
      cur = 지금 설치된 같은 id의 지문(없으면 null) · mine = 작업본의 지문(값이나 그 값을 내는 함수 — 필요할 때만 셉니다).
      'same' 그대로 · 'mark' 바탕을 지금 설치본으로 적기만 · 'adopt' 작업본에 제 고침이 없으니 설치본으로 다시 가져옴 · 'drift' 고침이 있으니 알리고, 반영할 때 덮어쓸지 물음 */
  const followOrigin = (rec, cur, mine) => {
    if (!cur) return rec ? 'same' : 'mark';
    if (rec && rec.sig === cur) return 'same';
    const m = typeof mine === 'function' ? mine() : mine;
    if (m && m === cur) return 'mark'; // 이미 같은 내용
    if (rec && rec.sig && m === rec.sig) return 'adopt';
    return 'drift';
  };

  /* ---------- 표 붙여넣기 (사건 · 시대) ----------
   * 표 계산 프로그램에서 복사한 표(탭으로 나뉜 글)나 CSV → 폼이 내놓는 꼴의 항목들. 첫 줄은 머리글 — 아래 별칭 가운데 하나면 그 열로 읽습니다 */
  const PASTE_HEAD = {
    title: ['제목', '사건', '사건명', '이름', '시대', '시대명', '정권', 'title', 'name'],
    start: ['시작', '시작연도', '시작일', '시작날짜', '연도', '년도', '해', 'start', 'year', 'from'],
    end: ['끝', '끝연도', '끝날짜', '종료', '종료연도', '종료일', 'end', 'to'],
    calendar: ['달력', '역법', 'calendar'],
    track: ['트랙', '나라', '국가', '지역', 'track', 'country'],
    category: ['분류', '카테고리', '종류', 'category'],
    importance: ['중요도', 'importance'],
    date: ['날짜', '세부날짜', '원문표기', 'date'],
    description: ['설명', '내용', 'description'],
    tags: ['태그', 'tags'],
    source: ['출처', 'source'],
    legendary: ['전승', 'legendary'],
    certainty: ['확실성', 'certainty'],
    people: ['민족', 'people'],
    kind: ['종류', '정권종류', 'kind'],
    partOf: ['소속', '상위정권', 'partof'],
  };
  const PASTE_KINDS = {
    event: {
      head: '제목\t시작\t끝\t트랙\t분류\t중요도\t설명',
      hint: '알아보는 머리글: 제목 · 시작 · 끝 · 트랙 · 분류 · 중요도(1~3) · 달력 · 날짜(원문 표기) · 설명 · 태그 · 출처 · 확실성. 시작·끝에는 연도나 날짜를 적습니다 — 기원전은 앞에 "기원전"이나 음수, 날짜는 연-월-일, 음력은 앞에 "음력". 모르면 "미정". 트랙·분류는 이름이나 id로 적고, 없는 이름이면 새로 만듭니다.',
    },
    period: {
      head: '이름\t시작\t끝\t트랙\t민족\t설명',
      hint: '알아보는 머리글: 이름 · 시작 · 끝 · 트랙 · 민족 · 종류 · 소속 · 설명 · 전승(예/아니오) · 확실성 · 달력. 끝에 "현재"라고 쓰면 지금까지 이어지는 시대가 되고, 연도를 모르면 "미정"이라고 씁니다. 트랙은 이름이나 id로 적고, 없는 이름이면 새로 만듭니다.',
    },
  };
  const CERT_ALIASES = { 확실: 'certain', 통설: 'accepted', 추정: 'estimated', 전승: 'legend' };
  const normHead = s => String(s).trim().toLowerCase().replace(/[\s_·.()]/g, '');
  /** 붙여넣은 글 → 줄마다 칸 목록 (첫 줄에 탭이 있으면 탭, 아니면 쉼표로 나눔 · 큰따옴표로 감싼 칸 안의 줄바꿈 · 쉼표 · "" 도 읽음) */
  function parseTable(text) {
    const src = String(text || '');
    const first = src.split(/\r?\n/, 1)[0] || '';
    const delim = first.includes('\t') ? '\t' : ',';
    const rows = [];
    let row = [];
    let cell = '';
    let quoted = false;
    for (let i = 0; i < src.length; i++) {
      const c = src[i];
      if (quoted) {
        if (c === '"' && src[i + 1] === '"') {
          cell += '"';
          i++;
        } else if (c === '"') quoted = false;
        else cell += c;
      } else if (c === '"' && cell === '') quoted = true;
      else if (c === delim) {
        row.push(cell);
        cell = '';
      } else if (c === '\n' || c === '\r') {
        if (c === '\r' && src[i + 1] === '\n') i++;
        row.push(cell);
        rows.push(row);
        row = [];
        cell = '';
      } else cell += c;
    }
    if (cell !== '' || row.length) {
      row.push(cell);
      rows.push(row);
    }
    return rows.filter(r => r.some(c => c.trim() !== ''));
  }
  const parseImp = v => {
    if (!v) return 2;
    if (/^[123]$/.test(v)) return Number(v);
    const stars = (v.match(/★/g) || []).length;
    if (stars) return HT.clamp(stars, 1, 3);
    return { 높음: 3, 상: 3, 보통: 2, 중: 2, 낮음: 1, 하: 1 }[v] || 2;
  };
  /** 종류 글 → 정권 종류 id (HT.POLITY_KINDS의 이름 · id와 흔한 다른 말 — 부를 때마다 만들어, 뒤에 더해진 종류도 알아봄) */
  /* 종류 낱말 → 종류 id: 파일 읽기(HT.polityKindId — 종류의 이름 · id · 딱지와 HT.KIND_WORDS)와 같은 표에, 붙여넣기에서만 받던 다른 말(연맹국가 · 연합)을 더합니다.
     뒤에 오는 것이 이기므로 종류 자신의 이름 · id · 딱지를 맨 뒤에 (HT.polityKindId와 같은 우선) */
  const kindAliases = () =>
    Object.fromEntries(
      [['연맹국가', 'federation'], ['연합', 'federation']]
        .concat(Object.entries(HT.KIND_WORDS || {}))
        .map(([w, id]) => [normHead(w), id])
        .concat(HT.POLITY_KINDS.flatMap(k => [k.name, k.id, k.short].filter(Boolean).map(w => [normHead(w), k.id])))
    );
  /**
   * 붙여넣은 표를 읽습니다. kind: 'event' | 'period'. opts = { tracks: [{ id, name }], categories: [{ id, name }], defaultTrack: 트랙 열이 없거나 빈 줄의 트랙 id }
   * → { error } (머리글 문제) 또는 { items: [폼이 내놓는 꼴의 항목], newTracks, newCats (새로 만들 트랙 · 분류), problems (건너뛸 줄 · 참고) }
   */
  function analyzePaste(text, kind, opts = {}) {
    const rows = parseTable(text);
    if (rows.length < 2) return { error: rows.length ? '머리글 아래에 내용 줄이 필요합니다.' : '', items: [], newTracks: [], newCats: [], problems: [] };
    const col = {};
    rows[0].map(normHead).forEach((h, i) => {
      for (const [key, aliases] of Object.entries(PASTE_HEAD)) if (col[key] == null && aliases.some(a => normHead(a) === h)) col[key] = i;
    });
    if (col.title == null || col.start == null) return { error: `머리글에서 "${kind === 'event' ? '제목' : '이름'}" 열과 "시작" 열을 찾지 못했습니다. 첫 줄이 머리글인지 확인하세요.`, items: [], newTracks: [], newCats: [], problems: [] };
    const tracks = arr(opts.tracks).map(t => ({ id: t.id, name: t.name }));
    const cats = arr(opts.categories).map(c => ({ id: c.id, name: c.name }));
    const newTracks = [];
    const newCats = [];
    const problems = [];
    const items = [];
    const find = (list, v) => list.find(x => normHead(x.id) === normHead(v) || normHead(x.name || '') === normHead(v));
    const get = (r, k) => (col[k] == null ? '' : String(r[col[k]] ?? '').trim());
    const KIND = kindAliases();
    /* 달력 열: 그 줄의 시작·끝에 달력 말이 없으면 붙여서 읽습니다 ("음력" + "연-월-일") — 모르는 달력이면 null */
    const calPrefix = v => {
      const w = normHead(v);
      if (!w || !HT.cal) return '';
      const c = HT.cal.CALENDARS.find(x => [x.id, x.name, ...x.words].some(a => normHead(a) === w));
      return c ? c.prefix : null;
    };
    const sameT = (a, b) => a != null && b != null && Math.abs(a - b) < 1e-9;
    rows.slice(1).forEach((r, n) => {
      const line = n + 2;
      const title = get(r, 'title');
      const pre = calPrefix(get(r, 'calendar'));
      const withCal = s => {
        if (!pre || !s || HT.isUnknownText(s) || HT.isOngoingText(s)) return s;
        const p = HT.cal.parse(s);
        return p && p.ok && p.cal === 'civil' && !/양력|서력/.test(s) ? `${pre}${s}` : s;
      };
      const startText = withCal(get(r, 'start'));
      const endText = withCal(get(r, 'end'));
      const startUnknown = HT.isUnknownText(startText);
      const ongoing = HT.isOngoingText(endText);
      const endUnknown = !ongoing && HT.isUnknownText(endText);
      const sd = startUnknown || !startText ? null : HT.readDate(startText);
      const ed = ongoing || endUnknown || !endText ? null : HT.readDate(endText);
      let start = sd ? sd.t : NaN;
      let end = ed ? ed.t : null;
      const startAt = sd && sd.at ? sd.at : null;
      let endAt = ed && ed.at ? ed.at : null;
      const bad = [];
      if (!title) bad.push(kind === 'event' ? '제목이 없음' : '이름이 없음');
      if (pre === null) bad.push(`달력 "${get(r, 'calendar')}"을(를) 알 수 없음`);
      if (startUnknown) {
        if (end == null || isNaN(end)) bad.push('시작이 미정이면 끝 연도가 필요함');
        else start = end;
      } else if (isNaN(start)) bad.push(startText ? `시작 "${startText}"을(를) 읽을 수 없음${sd && sd.error ? ` (${sd.error})` : ''}` : '시작이 없음');
      if (endUnknown) {
        end = start;
        endAt = null;
      }
      if (end != null && isNaN(end)) bad.push(`끝 "${endText}"을(를) 읽을 수 없음${ed && ed.error ? ` (${ed.error})` : ''}`);
      else if (end != null && !isNaN(start) && HT.endBound(end, endAt) < start) bad.push('끝이 시작보다 앞섬');
      if (bad.length) return problems.push(`${line}번째 줄: ${bad.join(', ')} — 건너뜁니다`);
      if (sameT(end, start) && !endUnknown && !startUnknown) end = endAt = null; // 같은 때에 끝나면 한 시점 — 시작이 미정이면 끝은 적은 사실이라 그대로 (배치용 연도로도 씀)

      const tv = get(r, 'track');
      let track = tv ? find(tracks, tv) : tracks.find(t => t.id === opts.defaultTrack) || null;
      if (!track) {
        const name = tv || '기본';
        const id = uniqueId(HT.ID_RE.test(name) ? name.toLowerCase() : `track-${HT.hash(name)}`, new Set(tracks.map(t => t.id)));
        track = { id, name, color: HT.autoColor(id) };
        tracks.push(track);
        newTracks.push(track);
      }
      const certRaw = get(r, 'certainty');
      let certainty = CERT_ALIASES[certRaw] || (HT.CERTAINTY.some(c => c.id === certRaw) ? certRaw : undefined);
      if (certRaw && !certainty) problems.push(`${line}번째 줄: 확실성 "${certRaw}"을(를) 알 수 없어 비워 둡니다.`);
      const obj = { track: track.id, start, startAt: startAt || null, end, endAt: end != null ? endAt || null : null, ongoing, startUnknown: startUnknown || undefined, endUnknown: endUnknown || undefined, description: get(r, 'description') };
      if (kind === 'event') {
        const cv = get(r, 'category');
        let cat = cv ? find(cats, cv) : null;
        if (cv && !cat) {
          const id = uniqueId(HT.ID_RE.test(cv) ? cv.toLowerCase() : `cat-${HT.hash(cv)}`, new Set(cats.map(c => c.id)));
          cat = { id, name: cv, color: HT.autoColor(id) };
          cats.push(cat);
          newCats.push(cat);
        }
        items.push(Object.assign(obj, {
          title,
          category: cat ? cat.id : '',
          importance: parseImp(get(r, 'importance')),
          date: get(r, 'date'),
          tags: get(r, 'tags').split(/[,，]/).map(s => s.trim()).filter(Boolean),
          source: get(r, 'source'),
          certainty,
        }));
      } else {
        const kindText = get(r, 'kind');
        const kindId = kindText ? KIND[normHead(kindText)] : '';
        if (kindText && !kindId) problems.push(`${line}번째 줄: 종류 "${kindText}"을(를) 알 수 없어 국가로 넣습니다.`);
        if (!certainty && /^(y|yes|o|true|1|예|전승|○|v)$/i.test(get(r, 'legendary'))) certainty = 'legend';
        items.push(Object.assign(obj, {
          name: title,
          people: get(r, 'people'),
          kind: kindId && kindId !== 'state' ? kindId : undefined,
          partOf: get(r, 'partOf') || undefined,
          certainty,
        }));
      }
    });
    return { items, newTracks, newCats, problems };
  }

  /* ---------- 시대 구분 폼 (HT.FORMS 틀 — 이름 · 기간 · 트랙 · 색 · 메모 · 설명 · 문서) ----------
   * 바탕 자료 창의 "시대 구분"과 연표에서 누른 제 시대 구분이 이 폼을 편집 창에 엽니다. 연표의 추가 메뉴에는 나오지 않습니다(add: false — 바탕 자료에서 추가) */
  const escH = s => HT.escapeHtml(s == null ? '' : s);
  const EPOCH_FORM = {
    word: '시대 구분',
    list: 'epochs',
    nameKey: 'name',
    add: false,
    fresh: o => {
      const s = { t: o.start, at: o.startAt || undefined };
      const e = HT.shiftDate(s, 100);
      return { track: '', start: s.t, startAt: s.at, end: e.t, endAt: e.at };
    },
    filterKeys: () => ({}),
    html: ({ tracks = [], spheres = [] }) => `
    <label class="field field-wide"><span>이름 <b class="req">*</b></span><input name="name" maxlength="80"></label>
    <div class="field"><span>시작 연도 <b class="req">*</b></span>${HT.yearFieldHTML('start', '연도', { unknown: true })}</div>
    <div class="field"><span>끝 연도</span>${HT.yearFieldHTML('end', '연도', { unknown: true })}<label class="check"><input type="checkbox" name="ongoing"> 현재까지 이어짐</label></div>
    <label class="field"><span>트랙 <small>(비우면 모든 나라 공통 줄)</small></span><select name="track"><option value="">공통 (모든 나라)</option>${tracks.map(t => `<option value="${escH(t.id)}">${escH(t.name || t.id)}</option>`).join('')}</select></label>
    <label class="field"><span>문화권 <small>(트랙 대신 — 그 문화권 머리 단 밑 시대 줄 · 트랙을 고르면 트랙이 우선)</small></span><select name="sphere"><option value="">없음</option>${spheres.map(s => `<option value="${escH(s.id)}">${escH(s.name || s.id)}</option>`).join('')}</select></label>
    <div class="field"><span>띠 색 <small>(고르지 않으면 자동)</small></span><span class="color-row"><label class="check"><input type="checkbox" name="useColor"> 따로 지정</label>${HT.swatchesHTML('color')}</span></div>
    <label class="field field-wide"><span>메모 <small>(짧게 — 설명이 없으면 상세에 보입니다)</small></span><input name="note" maxlength="200"></label>
    <label class="field field-wide"><span>설명</span><textarea name="description" rows="3"></textarea></label>
    <details class="field-wide adv" data-adv="dates">
      <summary>연대가 갈리는 경우 — 이설</summary>
      <div class="adv-body">${HT.altFieldHTML()}</div>
    </details>
    ${HT.wikiFieldHTML()}`,
    fill: (f, x) => {
      const el = f.elements;
      el.name.value = x.name || '';
      HT.fillRangeFields(f, x);
      el.track.value = x.track && [...el.track.options].some(o => o.value === x.track) ? x.track : '';
      if (el.sphere) {
        /* 문화권(형식 4 더하기 · 5단계 과제 6): 목록에 없는 id(켜지 않은 DLC의 문화권)는 잃지 않게 그대로 한 줄 더해 고른 채로 */
        if (x.sphere && ![...el.sphere.options].some(o => o.value === x.sphere)) el.sphere.insertAdjacentHTML('beforeend', `<option value="${escH(x.sphere)}">${escH(x.sphere)} (켠 DLC에 없음)</option>`);
        el.sphere.value = x.sphere || '';
      }
      el.useColor.checked = HT.isColor(x.color);
      HT.setSwatch(f, 'color', HT.isColor(x.color) ? x.color : '');
      el.note.value = x.note || '';
      el.description.value = x.description || '';
      HT.fillAlternatives(f, x); // 다른 견해만 (디테일 건의 4 — 시대 구분에는 확실성 · 연대 폭이 없음)
      const dates = f.querySelector('details[data-adv="dates"]');
      if (dates) dates.open = !!(x.alternatives && x.alternatives.length);
      if (el.wiki) {
        el.wiki.value = x.wiki || '';
        const box = f.querySelector('details[data-adv="wiki"]');
        if (box) box.open = !!x.wiki;
      }
      HT.bindSwatches(f);
    },
    read: f => {
      const el = f.elements;
      const problems = [];
      const r = HT.readRangeFields(f, problems);
      const item = {
        name: el.name.value.trim(),
        start: r.start,
        startAt: r.startAt,
        end: r.end,
        endAt: r.endAt,
        ongoing: r.ongoing,
        startUnknown: r.startUnknown || undefined,
        endUnknown: r.endUnknown || undefined,
        track: el.track.value || undefined,
        sphere: el.sphere && el.sphere.value ? el.sphere.value : undefined, // 트랙과 양자택일 — 둘 다 고르면 트랙이 우선(정규화가 경고 · 검사 창)
        color: el.useColor.checked && HT.isColor(el.color.value) ? el.color.value : undefined,
        note: el.note.value.trim(),
        description: el.description.value.trim(),
        alternatives: HT.readAlternativesField(f, problems),
        wiki: el.wiki && el.wiki.value.trim() ? el.wiki.value : undefined,
      };
      if (!item.name) problems.push('이름을 입력하세요.');
      return { item, problems };
    },
  };
  if (!HT.FORMS.epoch) HT.FORMS.epoch = EPOCH_FORM;

  /* ---------- 불러온 팩 (docs/구상-메이커-팩.md 3-5): 기본은 이 DLC만 — 덮어쓰기 대상 · 필요한 팩은 저절로(잠긴 채) ---------- */
  const REF_DIM = { light: 0.3, mid: 0.45, strong: 0.65 };
  /** ht.maker.refs 읽기: { DLC id: [{ id, show, locked }] } — 모르는 꼴 · 잘못된 id · 겹친 줄 · 자기 자신은 버림 */
  function readRefs(raw) {
    const out = {};
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out;
    for (const [k, list] of Object.entries(raw)) {
      if (!HT.ID_RE.test(k) || !Array.isArray(list)) continue;
      const seen = new Set();
      const rows = [];
      for (const r of list) {
        const id = r && typeof r.id === 'string' ? r.id.trim() : '';
        if (!HT.ID_RE.test(id) || id === k || seen.has(id)) continue;
        seen.add(id);
        rows.push({ id, show: r.show !== false, locked: r.locked !== false });
      }
      if (rows.length) out[k] = rows;
    }
    return out;
  }
  /** 덮어쓰기(패치)가 가리키는 팩 id — 대상 uid "<팩 id>/<항목 id>"의 앞 (자기 자신은 뺌) */
  const patchTargets = draft => [...new Set(arr(draft && draft.patches).map(p => str(p && p.target).split('/')[0]))].filter(id => id && HT.ID_RE.test(id) && id !== draft.id);
  /** 불러온 팩의 줄: 적어 둔 줄(stored) 다음에 저절로 드는 팩(덮어쓰기 대상 'patch' · 필요한 팩 'needs'). packs = 쓸 수 있는 팩(정규화한 것) */
  function refPlan(draft, stored, packs) {
    if (!draft) return [];
    const own = draft.id;
    const auto = new Map(patchTargets(draft).map(id => [id, 'patch']));
    for (const r of arr(draft.relations)) if (r && r.type === 'needs' && HT.ID_RE.test(str(r.id)) && r.id !== own && !auto.has(r.id)) auto.set(r.id, 'needs');
    const rows = [];
    const seen = new Set();
    const put = (id, show, locked) => {
      if (seen.has(id) || id === own) return;
      seen.add(id);
      const p = arr(packs).find(q => q.id === id);
      rows.push({ id, name: p ? p.name : id, version: p ? str(p.version) : '', builtin: !!(p && p.builtin), show, locked, auto: auto.get(id) || '', missing: !p });
    };
    for (const r of arr(stored)) if (r && HT.ID_RE.test(str(r.id))) put(r.id, r.show !== false, r.locked !== false);
    for (const id of auto.keys()) put(id, true, true);
    return rows;
  }
  /** 불러온 팩을 흐리게 하는 CSS — 연표 요소의 data-uid "<팩 id>/…"로 가려 냄. 잠긴 팩은 흐리기 값, 푼 팩은 +0.15. 숨긴 · 없는 팩은 뺌. 고른 항목(.is-selected)과 같은 팩 요소 안의 요소(겹쳐 흐려짐)는 뺌 */
  function refDimCSS(rows, dim) {
    const op = REF_DIM[dim] || REF_DIM.mid;
    const sel = id => `#timeline [data-uid^="${id}/"]:not(.is-selected):not([data-uid^="${id}/"] *)`;
    const rule = (list, v) => (list.length ? `${list.map(r => sel(r.id)).join(',\n')} { opacity: ${v}; filter: saturate(.55); }\n` : '');
    const shown = arr(rows).filter(r => r && r.show && !r.missing && HT.ID_RE.test(r.id));
    return rule(shown.filter(r => r.locked), op) + rule(shown.filter(r => !r.locked), Math.round((op + 0.15) * 100) / 100);
  }
  /** 덮어쓰기 대상 팩을 필요한 팩(needs)으로 — 없던 것만 더함 (설계 2-4). 돌려주는 값: 더한 수 — 0이면 작업본은 그대로(relations 칸도 만들지 않음) */
  function syncNeeds(draft, packs) {
    const have = new Set(arr(draft.relations).filter(r => r && r.type === 'needs').map(r => r.id));
    const add = patchTargets(draft).filter(id => !have.has(id));
    if (!add.length) return 0;
    draft.relations = arr(draft.relations).concat(
      add.map(id => {
        const p = arr(packs).find(q => q.id === id);
        return p ? { type: 'needs', id, name: p.name } : { type: 'needs', id };
      })
    );
    return add.length;
  }
  /** DLC id를 바꿀 때 불러온 팩 기록도 새 id로 (옛 id 기록은 지움) */
  function moveRefs(all, from, to) {
    const out = Object.assign({}, all);
    if (from !== to && out[from]) {
      out[to] = out[from];
      delete out[from];
    }
    return out;
  }

  /* ---------- 판 기록 (설계 3-7) · 팩 정보의 태그 · 관계 (3-6) ---------- */
  const NOTE_WORDS = { patches: '덮어쓰기', documents: '문서', info: 'DLC 정보', territory: '영토' };
  const VERB = { add: '더함', edit: '고침', remove: '뺌' };
  /** 반영하지 않은 고침(HT.draft.changes)의 요약 — 종류별 개수: '시대 2 더함 · 사건 5 고침' (DLC 정보 · 영토는 개수 없이) */
  function changelogNote(changes) {
    const order = [];
    const count = new Map();
    for (const c of arr(changes)) {
      if (!c || !VERB[c.type]) continue;
      const k = `${c.list}|${c.type}`;
      if (!count.has(k)) order.push(k);
      count.set(k, (count.get(k) || 0) + 1);
    }
    return order
      .map(k => {
        const [list, type] = k.split('|');
        const word = NOTE_WORDS[list] || (HT.draft.WORDS || {})[list] || list;
        return list === 'info' || list === 'territory' ? `${word} ${VERB[type]}` : `${word} ${count.get(k)} ${VERB[type]}`;
      })
      .join(' · ');
  }
  /** 판 기록에 새 줄을 맨 앞에 (200줄까지 — 넘으면 오래된 것부터 버림, 글은 500자까지) */
  const nextChangelog = (list, { version, date, note }) =>
    [{ version: str(version), date: str(date), note: str(note).slice(0, HT.PACK_LIMITS.noteLen) }].concat(arr(list).filter(c => c && typeof c === 'object')).slice(0, HT.PACK_LIMITS.changelog);
  /** 태그 더하기: { tags(새 배열), problem(못 더한 까닭 — 없으면 '') } — 같은 태그는 그대로 */
  function addTag(tags, text) {
    const v = str(text);
    const list = arr(tags).slice();
    if (!v || list.includes(v)) return { tags: list, problem: '' };
    if (v.length > HT.PACK_LIMITS.tagLen) return { tags: list, problem: `태그는 ${HT.PACK_LIMITS.tagLen}자까지입니다.` };
    if (list.length >= HT.PACK_LIMITS.tags) return { tags: list, problem: `태그는 ${HT.PACK_LIMITS.tags}개까지입니다.` };
    return { tags: list.concat(v), problem: '' };
  }
  /** 관계 더하기(작업본을 고침): type = needs · conflicts · after(relations) 또는 requires(함께 쓰면 좋음 — 있던 칸). 돌려주는 값: 못 더한 까닭('' = 더했거나 이미 있음) */
  function addRelation(draft, type, id, packs) {
    const v = str(id);
    if (!HT.ID_RE.test(v)) return 'id는 영문·숫자·- _ . 만 쓸 수 있습니다.';
    if (v === draft.id) return '자기 자신과는 관계를 맺지 않습니다.';
    if (type === 'requires') {
      if (!arr(draft.requires).includes(v)) draft.requires = arr(draft.requires).concat(v);
      return '';
    }
    if (!HT.PACK_RELATIONS.some(r => r.id === type)) return '모르는 관계입니다.';
    if (arr(draft.relations).some(r => r && r.type === type && r.id === v)) return '';
    const p = arr(packs).find(q => q.id === v);
    draft.relations = arr(draft.relations).concat(p ? { type, id: v, name: p.name } : { type, id: v });
    return '';
  }

  HT.makerKit = { BASE_TABLES, COL, itemLists, kindOfList, listWord, walkPath, findUsers, renameRefs, renameEpochRefs, renameGroupRefs, epochRefMatch, usageText, uniqueId, renameDlc, packSig, followOrigin, PASTE_HEAD, PASTE_KINDS, parseTable, analyzePaste, EPOCH_FORM, sphereChoices, nestGet, nestSet, leaderLabelCols };
  Object.assign(HT.makerKit, { shadowOf });
  HT.makerKit.scopeChecks = scopeChecks;
  HT.makerKit.lensChecks = lensChecks; // 단체 · 제도 칸 · 사건의 주제 검사 (형식 버전 3)
  Object.assign(HT.makerKit, { readRefs, patchTargets, refPlan, refDimCSS, syncNeeds, moveRefs }); // 불러온 팩 (2단계 과제 7)
  Object.assign(HT.makerKit, { changelogNote, nextChangelog, addTag, addRelation }); // 판 기록 · 팩 정보 (2단계 과제 10)
  /** 그 컴퓨터의 날짜 'YYYY-MM-DD' (판 기록 · 만든 날) */
  HT.makerKit.today = (d = new Date()) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

  /* ================= 메이커 부품 (화면) ================= */
  HT.makerPlugin = ctx => {
    const { $, state, K, timeline, esc } = ctx;
    const D = HT.draft;
    const kit = HT.makerKit;
    let draft = D.load(); // 고치는 DLC(작업본 = DLC JSON) — 아직 고르지 않았으면 null. 옛 메이커의 임시 저장본이 남아 있으면 그대로 이어받습니다
    let goodPack = null; // 마지막으로 검사를 통과한(정규화된) 작업본 — 작업본이 치명적 오류로 정규화되지 않는 동안에도 연표는 이것으로 그립니다
    let broken = ''; // 작업본이 검사를 통과하지 못하면 그 까닭 (메이커 줄에 알림)
    let changes = []; // 반영하지 않은 고침 (HT.draft.changes)
    let check = { errors: [], warnings: [], notes: [] }; // 작업본의 검사 결과 (메이커 줄의 검사 배지 · 검사 창 — notes는 경고가 아닌 알림: 배지에 세지 않음)
    let others = null; // 모델에 함께 들어간 다른 팩들 (작업본과 같은 id의 설치본은 뺌)
    let base = null; // others만으로 만든 모델 — 남의 항목을 고칠 때 견줄 원본. 필요할 때 만들고, 팩이 바뀌면 버립니다
    let drift = null; // 설치본이 작업본의 바탕과 달라졌는데 작업본에 고침이 있으면 { cur: 지금 설치본, rec: 적어 둔 바탕 } — 메이커 줄에 알리고, 반영할 때 덮어쓸지 묻습니다
    const narrow = () => window.matchMedia('(max-width: 860px)').matches; // 좁은 화면: 편집 창 · 떠 있는 창이 화면 전체를 덮는 시트 (css/maker.css와 같은 폭)
    let shell = null; // 작업실 틀 (js/maker-shell.js — start에서 붙임)
    let saved = { at: Date.now(), ok: true }; // 마지막 저장 (상태 줄 · 메뉴 줄)
    /* 편집 기본기 — 모든 작업본 저장이 아래 commit에서 기록됩니다. */
    const history = new HT.makerHistory.History(draft);
    const snapshots = HT.makerHistory.snapshots();
    let selectedItems = [], copiedItems = null, savedSnapshots = [], snapshotError = '', snapshotToken = 0;
    let snapshotText = HT.makerHistory.content(draft);
    const selection = () => selectedItems.slice();
    function selectItems(uids) {
      selectedItems = [...new Set(uids)].filter(uid => state.model.byUid.has(uid) || hasOwn(uid));
      paintSelection();
      return selectedItems;
    }
    async function clearSelection() {
      if (!(await ctx.leaveEditor())) return false;
      ctx.closeDetail();
      selectItems([]);
      if (shell) shell.showProps('empty');
      return true;
    }
    function toggleSelection(uid) {
      const next = selectedItems.includes(uid) ? selectedItems.filter(x => x !== uid) : selectedItems.concat(uid);
      return next.length ? selectItems(next) : clearSelection();
    }
    function paintSelection() {
      const picked = new Set(selectedItems);
      for (const el of document.querySelectorAll('#stage [data-uid]')) el.classList.toggle('mk-selected', picked.has(el.dataset.uid));
      for (const el of document.querySelectorAll('#mkTree [data-tuid]')) {
        const on = picked.has(el.dataset.tuid);
        el.classList.toggle('is-sel', on); el.setAttribute('aria-selected', String(on));
      }
      const note = document.querySelector('[data-selection-count]');
      if (note) note.textContent = selectedItems.length > 1 ? `${selectedItems.length}개 고름` : '';
      if (shell) shell.paintMulti();
      if (ctx.onSelection) ctx.onSelection(selectedItems.slice()); // 집합 보기의 '고른 나라' 막대 (js/views-ui.js)
    }
    function changeName(raw) {
      const previous = JSON.parse(history.rows[history.index].text);
      if (!previous || !raw) return '작업본 바꿈';
      const kinds = D.LISTS.filter(k => JSON.stringify(previous[k]) !== JSON.stringify(raw[k]));
      if (kinds.length === 1) return `${D.WORDS[kinds[0]] || '자료'} 고침`;
      if (JSON.stringify(previous.documents) !== JSON.stringify(raw.documents)) return '문서 고침';
      return kinds.length ? '여러 자료 고침' : '팩 정보 고침';
    }
    function restoreWork(raw, name, record = true) {
      if (!raw) return false;
      const oldId = draft && draft.id;
      draft = raw; goodPack = null; others = base = null;
      if (oldId && oldId !== draft.id) {
        refsAll = kit.moveRefs(refsAll, oldId, draft.id); saveRefs();
        if (HT.makerShell && HT.makerShell.moveFolders) HT.makerShell.moveFolders(oldId, draft.id); // 작업 폴더(작업실 설정 — DLC id마다)도 새 id로 (10건 D3 결정 7 A)
        const move = uid => typeof uid === 'string' && uid.startsWith(oldId + '/') ? draft.id + uid.slice(oldId.length) : uid;
        state.editing = move(state.editing); state.selected = move(state.selected);
        selectedItems = selectedItems.map(move);
        savedSnapshots = []; snapshotToken++;
      }
      if (record) commit(name);
      else {
        const ok = D.save(draft); saved = { at: Date.now(), ok };
        if (!ok) HT.toast('되돌린 작업본을 브라우저에 저장하지 못했습니다. [파일로] 내려받아 두세요.', 'error');
      }
      selectedItems = selectedItems.filter(uid => D.isOwnUid(draft, uid) && D.findOwn(draft, uid.slice(draft.id.length + 1)));
      ctx.refresh(); ctx.syncEditor();
      if (shell && shell.propsMode() === 'info') renderInfo();
      paintSelection();
      return true;
    }
    function historyGo(index) {
      flushSoon();
      const raw = history.go(index);
      return raw !== undefined && restoreWork(raw, '', false);
    }
    async function takeSnapshot(reason, { changedOnly = false } = {}) {
      if (!draft) return null;
      const raw = JSON.parse(JSON.stringify(draft)), text = HT.makerHistory.content(raw);
      if (changedOnly && text === snapshotText) return null;
      try {
        const row = await snapshots.save(raw, reason);
        if (draft && draft.id === raw.id) snapshotText = text;
        snapshotError = '';
        return row;
      } catch (error) {
        snapshotError = `자동 저장 기록을 남기지 못했습니다. 현재 작업본은 그대로입니다 — ${error.message || '저장 공간을 확인하세요.'}`;
        HT.toast(snapshotError, 'error'); return null;
      }
    }
    async function loadSnapshots() {
      const token = ++snapshotToken, id = draft && draft.id;
      if (!id) return;
      try {
        const rows = await snapshots.all(id);
        if (token !== snapshotToken || !draft || draft.id !== id) return;
        savedSnapshots = rows; snapshotError = '';
      } catch (error) { snapshotError = `자동 저장 기록을 읽지 못했습니다 — ${error.message}`; savedSnapshots = []; }
      if (shell && shell.bottomTab() === 'autosave') renderBottom();
    }
    function historyHTML() {
      return `<p class="hint">누르면 그 시점으로 돌아갑니다. 뒤의 걸음은 다시 할 수 있습니다. 이 창을 닫으면 작업 기록은 사라집니다.</p><ol class="mk-history">${history.rows.map((r, i) => `<li><button type="button" data-history="${i}" class="${i === history.index ? 'is-current' : i > history.index ? 'is-future' : ''}" aria-current="${i === history.index}"><span>${i === history.index ? '● ' : ''}${esc(r.name)}</span><time>${esc(new Date(r.at).toLocaleTimeString('ko-KR'))}</time></button></li>`).join('')}</ol>`;
    }
    function snapshotsHTML() {
      return `<p class="hint">이 컴퓨터에 최근 30개 시점을 보관합니다. 복원도 한 걸음으로 되돌릴 수 있습니다. <button type="button" class="btn btn-sm" data-snapshot-now>지금 시점 남기기</button></p>${snapshotError ? `<p role="alert">${esc(snapshotError)}</p>` : ''}<ol class="mk-history">${savedSnapshots.map(r => `<li><button type="button" data-snapshot="${r.key}"><span>${esc(new Date(r.at).toLocaleString('ko-KR'))} · ${esc(r.reason)}</span><small>항목 ${r.count}개 · 지금과 다른 곳 ${HT.makerHistory.difference(draft, r.raw)}개 · 이 시점으로 되돌리기</small></button></li>`).join('') || '<li class="hint">아직 남겨 둔 시점이 없습니다.</li>'}</ol>`;
    }
    async function restoreSnapshot(key) {
      const row = savedSnapshots.find(r => r.key === key);
      if (!row || !draft || row.pack !== draft.id) return;
      const target = draft;
      if (!(await ctx.leaveEditor('복원')) || draft !== target) return;
      flushSoon(); await takeSnapshot('자동 저장 기록 복원 전');
      if (draft !== target) return;
      restoreWork(JSON.parse(JSON.stringify(row.raw)), `자동 저장 시점 복원 — ${new Date(row.at).toLocaleTimeString('ko-KR')}`);
      await loadSnapshots(); HT.toast('저장된 시점을 복원했습니다. 되돌리기로 취소할 수 있습니다.', 'ok');
    }
    function copyBundle(uids = selection()) {
      if (!draft) return null;
      const sources = [D.clean(draft), ...state.packs.filter(p => p.id !== draft.id).map(p => D.clean(HT.packToJSON(p)))];
      for (const source of sources) {
        for (const patchPack of [...state.packs.filter(p => p.id !== draft.id), draft]) for (const patch of arr(patchPack.patches)) {
          if (!patch || !patch.target || !patch.target.startsWith(source.id + '/') || patch.hide) continue;
          const hit = D.findOwn(source, patch.target.slice(source.id.length + 1));
          if (hit) Object.assign(hit.item, JSON.parse(JSON.stringify(patch.set || {})));
        }
        for (const [key, doc] of state.model.docs) if (key.startsWith(source.id + '/') || key.startsWith('cell:' + source.id + '/')) source.documents[key] = doc.text;
      }
      const packet = HT.makerEdit.bundle(sources, uids);
      return packet.entries.length ? packet : null;
    }
    async function copySelection(uids = selection(), event = null) {
      const packet = copyBundle(uids); if (!packet) return false;
      copiedItems = packet;
      const plain = HT.makerEdit.tsv(packet), html = HT.makerEdit.clipboardHTML(packet);
      let system = false;
      if (event && event.clipboardData) {
        event.preventDefault(); event.clipboardData.setData('text/plain', plain); event.clipboardData.setData('text/html', html);
        event.clipboardData.setData('application/x-history-timeline+json', JSON.stringify(packet)); system = true;
      } else try {
        await navigator.clipboard.write([new ClipboardItem({ 'text/plain': new Blob([plain], { type: 'text/plain' }), 'text/html': new Blob([html], { type: 'text/html' }) })]); system = true;
      } catch (_) { /* 시스템 복사가 막혀도 이 창에서는 붙일 수 있습니다. */ }
      HT.toast(`${packet.entries.length}개를 ${system ? '복사했습니다.' : '이 창 안에 복사했습니다. 시스템 복사 권한은 없었습니다.'}`, 'ok');
      return true;
    }
    async function insertBundle(packet, duplicate = false) {
      if (!draft || !packet) return;
      const target = draft;
      if (!(await ctx.leaveEditor('붙여넣기')) || draft !== target) return;
      flushSoon();
      if (!duplicate || packet.entries.length > 20) await takeSnapshot(duplicate ? '여러 항목 복제 전' : '붙여넣기 전');
      if (draft !== target) return;
      const result = HT.makerEdit.insert(draft, packet, { duplicate });
      restoreWork(result.draft, `항목 ${result.uids.length}개 ${duplicate ? '복제' : '붙여넣음'}`);
      selectItems(result.uids);
      if (result.uids.length === 1) {
        await ctx.openEditorFor(result.uids[0]);
        if (duplicate) { const f = document.querySelector('#editorForm [name="name"], #editorForm [name="title"]'); if (f) { f.focus(); f.select(); } }
      }
      HT.toast(`항목 ${result.uids.length}개를 ${duplicate ? '복제' : '붙여넣기'}했습니다.`, 'ok');
    }
    async function pasteSelection(event = null) {
      if (!draft) return;
      let packet = null, text = '', available = false;
      if (event && event.clipboardData) {
        available = true; packet = HT.makerEdit.fromClipboard(event.clipboardData); text = event.clipboardData.getData('text/plain'); event.preventDefault();
      } else try {
        const data = {};
        for (const row of await navigator.clipboard.read()) for (const type of row.types) if (['text/html', 'text/plain'].includes(type)) data[type] = await (await row.getType(type)).text();
        available = true; packet = HT.makerEdit.fromClipboard({ getData: t => data[t] || '' }); text = data['text/plain'] || '';
      } catch (_) { /* 권한이 없으면 이 창에서 복사한 묶음을 씁니다. */ }
      if (!available) packet = copiedItems;
      if (packet) return insertBundle(packet);
      if (text.trim() && HT.makerPaste && HT.makerPaste.isWhole(text)) return pasteWhole(text); // 칸 채우기 답 통째 — 그 나라의 편집 창으로
      if (text.trim()) { openPaste(); pasteForm.elements.text.value = text; analyzePasteUI(); return; }
      HT.toast('붙여넣을 항목이 없습니다. 항목을 복사하거나 표 글을 복사한 뒤 Ctrl+V를 누르세요.');
    }
    async function duplicateSelection(uids = selection()) { return insertBundle(copyBundle(uids), true); }
    async function deleteSelection({ cut = false, event = null } = {}) {
      const target = draft;
      const chosen = selection();
      const own = chosen.filter(uid => hasOwn(uid));
      if (!own.length) return HT.toast('내 DLC 항목을 고르세요. 불러온 팩의 항목은 먼저 내 DLC로 복사할 수 있습니다.');
      if (cut && !(await copySelection(own, event))) return;
      if (draft !== target || !(await ctx.leaveEditor(cut ? '잘라내기' : '지우기')) || draft !== target) return;
      flushSoon(); if (own.length > 20) await takeSnapshot('여러 항목 지우기 전');
      if (draft !== target) return;
      for (const uid of own) D.removeOwn(draft, uid.slice(draft.id.length + 1));
      commit(`항목 ${own.length}개 ${cut ? '잘라냄' : '지움'}`);
      selectedItems = []; ctx.closeEditor(); ctx.refresh();
      HT.toast(`${own.length}개를 ${cut ? '잘라냈습니다.' : '지웠습니다.'}${own.length < chosen.length ? ' 불러온 팩의 항목은 그대로 두었습니다.' : ''}`, 'ok');
    }
    /* keepEditor: 편집 창이 연 항목을 건드리지 않는 고침(통째 붙여넣기의 '다른 나라에 넣을 것')은 편집 창을 닫지 않음 — 고친 뒤 ctx.syncEditor가 창을 맞춤 */
    async function transact(make, name, { snapshot = false, keepEditor = false } = {}) {
      if (!draft) return false;
      const target = draft;
      if ((!keepEditor && !(await ctx.leaveEditor(name))) || draft !== target) return false;
      flushSoon();
      const before = HT.makerHistory.content(draft);
      if (snapshot) await takeSnapshot(name + ' 전');
      if (draft !== target || before !== HT.makerHistory.content(draft)) {
        HT.toast('다른 고침이 먼저 저장됐습니다. 다시 실행해 주세요.'); return false;
      }
      try {
        const result = make(JSON.parse(JSON.stringify(draft)));
        if (!result || HT.makerHistory.content(result) === before) return false;
        return restoreWork(result, name);
      } catch (error) { HT.toast(error.message || '고침을 적용하지 못했습니다.', 'error'); return false; }
    }
    /* ---------- 집합 보기 (10건 6 — 감독 선택 D4 결정 3: 판을 만들고 · 고치고 · 지우는 것은 메이커에서만, 판은 그 DLC의 views — 형식 3 'DLC-형식.md 모아 보기 판') ----------
       js/views-ui.js(고른 나라 막대 · 판 목록의 고치기 · 지우기 · 시대 구분 카드의 저장)가 부릅니다. 판 하나 = views 한 항목 { id, name, members, start?, end? … } */
    /** 연표의 나라(uid) → views의 구성 나라 참조: 트랙 안에서 그 이름이 하나뿐이면 사람이 읽는 "트랙:이름"(트랙 id가 영문 · 숫자 꼴일 때 — 아니면 { track, polity }),
        같은 트랙에 같은 이름이 둘 이상이면 { track, polity: id(제 항목) · uid(남의 항목) } — 모델의 나라 찾기(polityFinder)가 이름 · id · uid를 모두 받음 */
    function viewRefOf(uid) {
      const p = state.model && state.model.byUid.get(uid);
      if (!p || HT.itemKindOf(p) !== 'period') return null;
      const twins = state.model.periods.filter(q => q.track === p.track && q.name === p.name && HT.itemKindOf(q) === 'period').length > 1;
      if (twins) return { track: p.track, polity: isOwn(p) ? p.id : p.uid };
      return /^[A-Za-z0-9_.-]+$/.test(p.track) ? `${p.track}:${p.name}` : { track: p.track, polity: p.name };
    }
    /** 판 저장 — view = { name, members: [나라 uid — 판 안의 차례], start?, startAt?, end?, endAt?, ongoing? }. id를 주면 그 판을 고칩니다(설명 · 메모 · 문서 · 보기 설정 · 색 · 이름 목록은 이어받고,
        연표에서 찾지 못하던 옛 구성 나라 참조는 뒤에 그대로 둠 — 다른 DLC를 켜면 다시 풀리게). 돌려주는 값: 판의 id (못 하면 null) */
    async function saveView(view, id = null) {
      if (!ready()) return null;
      const name = String((view && view.name) || '').trim();
      const refs = ((view && view.members) || []).map(viewRefOf).filter(Boolean);
      if (!name || !refs.length) return null;
      const found = r => state.model.periods.some(q => HT.itemKindOf(q) === 'period' && (!r.track || q.track === r.track) && (q.name === r.polity || q.id === r.polity || q.uid === r.polity));
      let out = id;
      const ok = await transact(d => {
        d.views = Array.isArray(d.views) ? d.views : [];
        const old = id ? d.views.find(x => x && x.id === id) : null;
        if (id && !old) throw Error('고칠 집합 보기를 찾지 못했습니다.');
        if (!old) {
          const used = new Set(d.views.map(x => x && x.id));
          const base = `v-${HT.hash(name)}`;
          out = base;
          for (let n = 2; used.has(out); n++) out = `${base}-${n}`;
        }
        const keep = old ? HT.readScopeRefs(old.members).filter(r => !found(r)).map(HT.compactScopeRef) : [];
        const o = Object.assign({}, old || {}, { id: out, name, members: refs.concat(keep) });
        for (const k of ['start', 'startAt', 'end', 'endAt', 'ongoing']) delete o[k];
        if (view.start != null && isFinite(view.start)) {
          o.start = view.start;
          if (view.startAt) o.startAt = view.startAt;
          if (view.ongoing) o.ongoing = true;
          else if (view.end != null && isFinite(view.end) && view.end >= view.start) {
            o.end = view.end;
            if (view.endAt) o.endAt = view.endAt;
          }
        }
        /* 나머지 칸(2026-10-23 — 전역 확대 ④): 색 · 설명 · 메모 · 보기 설정 · 이름 목록은 view에 그 열쇠가 있을 때만 바꿉니다(없으면 이어받음 — 폴더 → 집합 보기 같은 옛 길) */
        if ('color' in view) {
          if (HT.isColor(view.color)) o.color = view.color;
          else delete o.color;
        }
        for (const k of ['description', 'note']) {
          if (!(k in view)) continue;
          if (String(view[k] || '').trim()) o[k] = String(view[k]).trim();
          else delete o[k];
        }
        if ('settings' in view) {
          const s = view.settings && typeof view.settings === 'object' ? HT.readViewSettings(view.settings, () => {}) : null;
          if (s && Object.keys(s).length) o.settings = s;
          else delete o.settings;
        }
        if ('names' in view) {
          const n = HT.readNames(view.names);
          if (n.length) o.names = n;
          else delete o.names;
        }
        if (old) d.views[d.views.indexOf(old)] = o;
        else d.views.push(o);
        return d;
      }, id ? `집합 보기 고침 · ${name}` : `집합 보기 추가 · ${name}`);
      return ok ? out : null;
    }
    /** 판 지우기 — 그 판의 문서(view:id)도 함께. 돌려주는 값: 지웠는지 */
    async function removeView(id) {
      if (!ready()) return false;
      return !!(await transact(d => {
        const list = Array.isArray(d.views) ? d.views : [];
        const hit = list.find(x => x && x.id === id);
        if (!hit) throw Error('지울 집합 보기를 찾지 못했습니다.');
        d.views = list.filter(x => x !== hit);
        if (!d.views.length) delete d.views;
        if (d.documents) delete d.documents[`view:${id}`];
        return d;
      }, `집합 보기 지움 · ${(hit => (hit ? hit.name : id))(arr(draft && draft.views).find(x => x && x.id === id))}`));
    }
    function editableRaw(x) {
      if (isOwn(x)) return rawOf(x);
      const pack = state.packs.find(p => p.id === x.packId);
      if (!pack) throw Error('불러온 원본 자료를 찾지 못했습니다.');
      const hit = D.findOwn(D.clean(HT.packToJSON(pack)), x.id);
      if (!hit) throw Error('고칠 원본 항목을 찾지 못했습니다.');
      for (const p of [...state.packs.filter(p => p.id !== draft.id), draft]) for (const patch of arr(p.patches)) {
        if (patch.target === x.uid && !patch.hide) Object.assign(hit.item, JSON.parse(JSON.stringify(patch.set || {})));
      }
      return hit.item;
    }
    function openBulk() { if (draft) HT.makerGrid.bulkDialog(ctx, { ...editApi, get draft() { return draft; }, isLocked, rawOf: editableRaw, baseModel }); }
    const editApi = {
      transact, openBulk,
      mountBulk: target => HT.makerGrid.bulkDialog(ctx, { ...editApi, get draft() { return draft; }, isLocked, rawOf: editableRaw, baseModel }, target),
      openItem: uid => ctx.openEditorFor(uid),
      get history() { return history; }, selection, selectItems, clearSelection, toggleSelection, paintSelection, copySelection, pasteSelection, duplicateSelection, deleteSelection,
      undo: () => { flushSoon(); return history.canUndo && historyGo(history.index - 1); },
      redo: () => { flushSoon(); return history.canRedo && historyGo(history.index + 1); },
      openHistory: () => shell.openBottom('history'),
      openSnapshots: () => { savedSnapshots = []; shell.openBottom('autosave'); },
      loadSnapshots,
      takeSnapshot, restoreSnapshot,
    };

    /* 불러온 팩 (설계 3-5) — DLC마다 기억: ht.maker.refs = { DLC id: [{ id, show, locked }] }. 저절로 든 줄(덮어쓰기 대상 · 필요한 팩)은 보이기 · 자물쇠를 바꿨을 때만 적음 */
    const REFS_KEY = 'ht.maker.refs';
    let refsAll = kit.readRefs(HT.store.get(REFS_KEY, null));
    let refRows = [];
    const saveRefs = () => HT.store.set(REFS_KEY, refsAll);
    function storeRows(rows) {
      if (!draft) return;
      const keep = rows.filter(r => !r.auto || !r.show || !r.locked).map(r => ({ id: r.id, show: !!r.show, locked: !!r.locked }));
      if (keep.length) refsAll[draft.id] = keep;
      else delete refsAll[draft.id];
      saveRefs();
    }
    function setRefs(rows) {
      storeRows(rows);
      ctx.refresh();
    }

    /* ---------- 작업본을 얹은 모델 ---------- */
    /** 지금 연표에 놓인(설치된 · 내장된) 같은 id의 DLC — 고친 것을 셀 때의 기준 */
    const installedPack = () => (draft ? state.packs.find(p => p.id === draft.id) || null : null);
    const installedRaw = id => (HT.store.get(K.installed, []) || []).find(p => p && p.id === id) || null;

    /* ---------- 바탕 판 (HT.makerKit.followOrigin) ----------
     * 작업본을 가져오거나(설치본 고르기 · 파일 열기 · 새 DLC · 설치된 판으로 되돌리기) 반영할 때 그때의 설치본 지문을 { id, sig, version }으로 적어 둡니다 (설치본이 없으면 sig: null).
     * 모델을 지을 때마다 설치본이 그 지문과 같은지 보고, 다르면 — 작업본에 제 고침이 없으면 그 자리에서 새 설치본으로 다시 가져오고, 고침이 있으면 drift로 알립니다 */
    const ORIGIN_KEY = 'ht.maker.origin';
    const readOrigin = () => {
      const r = HT.store.get(ORIGIN_KEY, null);
      return draft && r && typeof r === 'object' && !Array.isArray(r) && r.id === draft.id ? r : null;
    };
    const markOrigin = pack => draft && HT.store.set(ORIGIN_KEY, { id: draft.id, sig: kit.packSig(pack), version: pack ? str(pack.version) : '' });
    /** buildModel이 부릅니다 (pack = 정규화한 작업본 — 검사를 통과하지 못했으면 null). 작업본을 새 설치본으로 다시 가져왔으면 true */
    function followOrigin(pack) {
      drift = null;
      const cur = installedPack();
      const rec = readOrigin();
      const what = kit.followOrigin(rec, kit.packSig(cur), () => kit.packSig(pack));
      if (what === 'mark') markOrigin(cur);
      else if (what === 'drift' || (what === 'adopt' && ctx.editorDirty())) drift = { cur, rec }; // 편집 창에 저장하지 않은 고침이 있으면 가져오지 않고 알립니다
      else if (what === 'adopt') {
        ctx.closeEditor(); // 편집 창이 옛 판의 값을 들고 있지 않게 (저장하면 새 판의 그 항목을 옛 값으로 되돌리게 됨)
        draft = D.clean(installedRaw(cur.id) || HT.packToJSON(cur));
        commit();
        markOrigin(cur);
        HT.toast(`설치된 «${cur.name}»이(가) v${cur.version}(으)로 바뀌어, 고친 것이 없던 작업본을 그 판으로 다시 불러왔습니다.`);
        return true;
      }
      return false;
    }
    /** 설치본이 따로 바뀐 사정 (drift가 있을 때) */
    function driftText() {
      const { cur, rec } = drift;
      const who = `«${cur.name}» v${cur.version}${cur.builtin ? '(기본 내장 팩)' : ''}`;
      if (rec && rec.sig) return `설치된 ${who}이(가) 이 작업본을 가져온 뒤에(가져올 때는 v${rec.version || '?'}) 바뀌었습니다 — DLC 관리의 설치 · 백업 복원 · 다른 탭의 반영 같은 것으로.`;
      if (rec) return `이 작업본과 id가 같은 ${who}이(가) 따로 설치되었습니다.`;
      return `설치된 ${who}과(와) 이 작업본이 같은 판에서 나왔는지 알 수 없습니다 (전에 저장해 둔 작업본).`;
    }

    /** viewer.js의 refresh가 부릅니다(all = 쓸 수 있는 모든 팩): 불러온 팩 + 정규화한 작업본 — 켜고 끔(ht.packs.state)은 보지 않음 */
    function buildModel(all) {
      refRows = kit.refPlan(draft, draft ? refsAll[draft.id] || [] : [], all);
      const want = new Set(refRows.filter(r => !r.missing).map(r => r.id));
      const list = all.filter(p => want.has(p.id) && !(draft && p.id === draft.id));
      if (!others || others.length !== list.length || others.some((p, i) => p !== list[i])) base = null;
      others = list;
      drift = null;
      let fresh = null; // 이번에 검사를 통과한 작업본 (대범위 검사는 그것을 얹은 모델로)
      if (draft) {
        let r = HT.normalizePack(draft);
        if (followOrigin(r.pack)) r = HT.normalizePack(draft);
        if (r.pack) goodPack = r.pack;
        fresh = r.pack;
        check = { errors: r.errors, warnings: r.warnings, notes: [] };
        broken = r.pack ? '' : (r.errors.find(e => e.kind === 'info') || r.errors[0] || { msg: '검사를 통과하지 못했습니다.' }).msg;
        changes = D.changes(r.pack, installedPack());
      } else {
        goodPack = null;
        broken = '';
        changes = [];
        check = { errors: [], warnings: [], notes: [] };
      }
      const model = HT.buildModel(goodPack ? others.concat([goodPack]) : others, null);
      if (fresh) {
        /* 대범위: 모델에서야 알 수 있는 것(찾지 못한 구성 정권 · 그려지지 않는 대범위)은 경고에, 켜면 승계 줄이 나뉘는 곳은 알림에 (HT.makerKit.scopeChecks) */
        const sc = kit.scopeChecks(fresh, model, draft.scopes, check.warnings);
        check.warnings = check.warnings.concat(sc.warnings);
        check.notes = sc.notes;
        check.warnings = check.warnings.concat(kit.lensChecks(fresh, model, draft)); // 단체 · 제도 칸 · 사건의 주제 (형식 버전 3 — 모델에서야 알 수 있는 것)
        /* 사람 · 계보(형식 버전 3): 모델에서야 알 수 있는 것 — 찾지 못한 사람 · 앞 지도자, 자리 이음의 관계와 혈연이 어긋남, 혈연의 고리 (이 DLC의 항목에 적힌 것만) */
        for (const w of model.peopleWarnings || []) if (w.packId === fresh.id) check.warnings.push({ msg: w.msg, kind: w.list, index: arr(draft[w.list]).findIndex(x => x && x.id === w.id) });
        if (HT.makerKin) check.notes = check.notes.concat(HT.makerKin.checks(model, fresh)); // 계보: 덩어리 상한(5만 명)을 넘는 가문 — 새 앱에는 파별로 나뉘어 실림 (D1 확정 설계 7-5)
        /* 배열 기준 '북 → 남'(형식 버전 3): 남북 위치가 없는 줄 머리 · 좌표 방식이 섞여 경위도로 본 지명 (이 DLC의 나라만 — HT.buildModel의 linkOrder) */
        for (const w of model.orderWarnings || []) if (w.packId === fresh.id) check.warnings.push({ msg: w.msg, kind: w.list, index: arr(draft[w.list]).findIndex(x => x && x.id === w.id) });
        for (const w of model.sphereWarnings || []) if (w.packId === fresh.id) check.warnings.push({ msg: w.msg, kind: w.list, index: arr(draft[w.list]).findIndex(x => x && x.id === w.id) }); // 만든 곳이 없는 문화권(2026-10-23)
        /* 형식 4의 칸(5단계 과제 8 — js/maker-check.js): 빌림 · 실권의 상대가 작업본 · 불러온 팩에서 풀리지 않으면 확인할 것, 빌림의 고리 · 종류에 맞지 않는 칸은 경고, 열 때의 다리 알림은 알림 */
        if (HT.makerCheck) {
          const fc = HT.makerCheck.f4Checks(draft, others);
          check.warnings = check.warnings.concat(fc.warnings);
          check.notes = check.notes.concat(fc.notes);
        }
      }
      updateBar();
      Promise.resolve().then(renderLive); // 창들은 새 모델이 state.model에 놓인 뒤에 (refresh가 끝난 다음)
      return model;
    }
    /* 원본 모델은 견주는 데만 씁니다 — 모델을 지으면 지위 자동 완성의 사전(HT.lastRankDefs — 마지막으로 만든 모델의 것)이 바뀌므로,
       작업본의 지위 사전이 빠진 원본의 것이 남지 않게 연표 모델의 사전으로 되돌려 둡니다 */
    const baseModel = () => {
      if (base) return base;
      const keep = HT.lastRankDefs;
      const keepThemes = [HT.lastThemes, HT.lastGroupNames]; // 주제 · 단체 자동 완성도 같은 까닭으로 (형식 버전 3)
      const full = state.model; // 연표 모델(작업본을 얹은 것) — 원본 모델을 지으면 바뀌는 문화권 사전 · 지도자 표기 낱말의 출처도 그것으로 되돌림(6단계 걸음 3 — HT.sphereOf · HT.leaderWords가 마지막 모델의 것을 봄)
      base = HT.buildModel(others || [], null);
      HT.lastRankDefs = keep;
      [HT.lastThemes, HT.lastGroupNames] = keepThemes;
      if (full && full.sphereMap) HT.useSpheres([...full.sphereMap.values()]);
      if (full && full.leaderLabelMap) HT.useLeaderLabels([...full.leaderLabelMap].map(([id, leaderLabels]) => ({ id, leaderLabels })), full.tracks);
      return base;
    };

    /* ---------- 작업본 고치기 (viewer.js의 저장 길이 부름) ---------- */
    const isDraftId = id => !!draft && draft.id === id;
    const isOwn = x => !!draft && !!x && x.packId === draft.id;
    const hasPatch = uid => !!draft && draft.patches.some(p => p && p.target === uid);
    /** 제 항목의 파일 그대로의 값(정규화한 작업본의 그 항목) — 편집기는 이것으로 채웁니다. 모델의 항목에는 짐작으로 배정된 색 · 파스텔로 맞춘 색 · 승계선으로 바뀐 칸처럼
        화면용 값이 섞여 있어, 그것으로 채우면 열어서 저장하는 순간 짐작이 자료로 굳습니다 */
    function rawOf(x) {
      if (!isOwn(x) || !goodPack) return null;
      for (const list of kit.itemLists()) {
        const it = arr(goodPack[list]).find(o => o.id === x.id);
        if (it) return it;
      }
      return null;
    }
    /** 작업본에 그 제 항목이 있는지 (검사에서 떨어져 연표에 없는 것까지) */
    const hasOwn = uid => !!draft && D.isOwnUid(draft, uid) && !!D.findOwn(draft, String(uid).slice(draft.id.length + 1));
    /** 제 항목(uid)을 작업본에서 꺼내 편집 창에 채울 수 있는 꼴로 — 검사에서 떨어져 연표에 나오지 않는 항목도 고칠 수 있게. 날짜 글은 해 좌표로 풀어 둡니다 (없으면 null) */
    function pseudo(uid) {
      if (!draft || !D.isOwnUid(draft, uid)) return null;
      const hit = D.findOwn(draft, String(uid).slice(draft.id.length + 1));
      if (!hit) return null;
      const raw = hit.item;
      const doc = state.model && state.model.docs.get(uid);
      const x = Object.assign({}, raw, { uid, packId: draft.id, packName: draft.name, itemKind: kit.kindOfList(hit.list), wiki: doc ? doc.text : str(raw.wiki) ? String(raw.wiki) : '' });
      for (const k of HT.DATE_KEYS) {
        const v = raw[k];
        if (typeof v !== 'string' || !v.trim()) continue;
        if (k === 'end' && HT.isOngoingText(v)) {
          x.end = null;
          x.ongoing = true;
        } else if (HT.isUnknownText(v)) {
          x[k] = typeof raw[`${k}Hint`] === 'number' ? raw[`${k}Hint`] : null;
          x[`${k}Unknown`] = true;
        } else {
          const d = HT.readDate(v, raw[`${k}At`]);
          if (d && isFinite(d.t)) {
            x[k] = d.t;
            x[`${k}At`] = d.at || undefined;
          }
        }
      }
      return x;
    }
    /** 고칠 DLC가 있는지 — 없으면 고르는 창을 열고 false */
    function ready() {
      if (draft) return true;
      if (shell) shell.showStart();
      return false;
    }
    /** 브라우저에 임시 저장. 화면은 부른 쪽이 refresh로 다시 짓습니다 (그때 메이커 줄도 갱신) */
    function commit(name) {
      const label = name || changeName(draft);
      if (draft) draft._edited = Date.now(); // 마지막으로 고친 때 — 처음 화면 (작업본에만 — 파일로 나가지 않음)
      history.push(draft, label);
      const ok = D.save(draft);
      saved = { at: Date.now(), ok };
      if (!ok) HT.toast('브라우저에 저장하지 못했습니다. 저장 공간을 확인하고, [파일로]로 내려받아 두세요.', 'error');
      return ok;
    }
    /** 폼에서 이름을 바꾼 제 항목을 이름으로 가리키던 이 DLC의 곳을 따라 고치고 알립니다(id로 적은 것은 그대로):
        시대 구분 → 그 이름으로 적은 대범위(대범위 폼의 자동 완성 · '시대 구분에서 가져오기'는 이름을 적으므로 — id는 폼에서 바꿀 수 없음),
        단체 → 그 이름으로 적은 뒤 단체의 앞선 단체(from — 단체 폼의 앞선 단체 칸은 이름을 자동 완성하므로) */
    function followRename(kind, before, obj) {
      const moved = kind === 'epoch' ? kit.renameEpochRefs(draft, before, before.name, obj.name) : kind === 'group' ? kit.renameGroupRefs(draft, before, before.name, obj.name) : 0;
      const what = kind === 'epoch' ? `이 시대 구분을 이름으로 가리키던 대범위 ${moved}개` : `이 단체를 이름으로 가리키던 앞선 단체 ${moved}곳`;
      if (moved) setTimeout(() => HT.toast(`저장했습니다 — ${what}도 새 이름으로 바꿨습니다.`, 'ok'), 0);
    }
    /** 편집기의 저장: 새 항목(x 없음) → 작업본의 목록에 · 제 항목 → 그 자리에서 · 남의 항목 → 원본과 견줘 바뀐 칸만 패치로. 문서 본문은 documents로. 돌려주는 값: 그 항목의 uid (못 하면 null) */
    function saveItem(kind, x, obj) {
      if (!ready()) return null;
      let uid;
      if (!x) uid = `${draft.id}/${D.addItem(draft, kind, obj)}`;
      else if (isOwn(x)) {
        const own = kind === 'epoch' || kind === 'group' ? D.findOwn(draft, x.id) : null;
        const before = own ? Object.assign({}, own.item) : null; // 시대 구분 · 단체의 옛 이름 · 트랙 (이름으로 가리키던 대범위 · 뒤 단체를 따라 고치려고)
        if (!D.updateOwn(draft, x.id, obj, rawOf(x) || x)) {
          HT.toast('고치는 DLC에서 이 항목을 찾지 못했습니다.', 'error');
          return null;
        }
        uid = x.uid;
        if (before) followRename(kind, before, obj);
      } else {
        if (isLocked(x)) {
          lockedToast(x); // 편집 창이 열린 채 잠가도 여기서 막힘
          return null;
        }
        const orig = baseModel().byUid.get(x.uid);
        if (!orig) {
          HT.toast('원본 항목을 찾지 못했습니다. 그 DLC가 켜져 있는지 확인하세요.', 'error');
          return null;
        }
        D.patchForeign(draft, orig, obj);
        uid = x.uid;
      }
      /* 폼의 문서 본문: 손댔을 때만 documents로 (열어서 그대로 저장하면 문서는 그대로) */
      const docNow = (state.model.docs.get(uid) || {}).text || '';
      if ('wiki' in obj && (obj.wiki || '') !== docNow) putDoc(uid, obj.wiki || '');
      D.ensureRefs(draft, state.model);
      commit(`${HT.FORMS[kind].word} «${obj.name || obj.title || '이름 없음'}» ${x ? '고침' : '더함'}`);
      return uid;
    }
    /** 문서: 다른 DLC의 글과 똑같으면(고치지 않았으면) 제 것을 두지 않습니다 */
    function putDoc(key, text) {
      const d = baseModel().docs.get(key);
      D.setDoc(draft, key, d && d.text === text ? '' : text);
    }
    function setDoc(key, text) {
      if (!ready()) return false;
      putDoc(key, String(text ?? ''));
      commit('문서 고침');
      return true;
    }
    /** 문서 그림 사전(형식 3 images — 10건 D3 결정 8 A · js/maker-images.js): edit(지금 목록의 사본) → 새 목록. 되돌리기 한 걸음.
        브라우저 저장소가 모자라면 되돌리고 false (표지 넣기와 같은 길) */
    function setImages(edit, name = '문서 그림 고침', also = null) {
      if (!ready()) return false;
      const old = draft.images;
      const oldDocs = also && draft.documents ? JSON.parse(JSON.stringify(draft.documents)) : null; // 이름을 바꾸면 문서의 고리도 함께(also) — 같은 되돌리기 한 걸음
      const next = edit(arr(old).map(x => Object.assign({}, x)));
      if (!Array.isArray(next)) return false;
      if (next.length) draft.images = next;
      else delete draft.images;
      if (also) also(draft);
      if (!commit(name)) {
        if (old) draft.images = old;
        else delete draft.images;
        if (oldDocs) draft.documents = oldDocs;
        commit();
        HT.toast('브라우저 저장 공간이 모자라 문서 그림을 고치지 못했습니다 — 더 작은 그림을 쓰거나 [파일로] 내려받아 두세요.', 'error');
        return false;
      }
      ctx.refresh();
      return true;
    }
    /** 제 항목은 삭제, 남의 항목은 숨김 패치 */
    function removeItem(x) {
      if (!ready()) return false;
      if (!isOwn(x) && isLocked(x)) {
        lockedToast(x);
        return false;
      }
      if (isOwn(x)) D.removeOwn(draft, x.id);
      else D.hideForeign(draft, x.uid);
      commit(`«${x.name || x.title}» ${isOwn(x) ? '지움' : '숨김'}`);
      return true;
    }
    /** 남의 항목에 건 패치(고침 · 숨김)를 걷어 원래대로 */
    function revertItem(x) {
      if (!ready()) return false;
      D.unpatch(draft, x.uid);
      commit(`«${x.name || x.title}» 덮어쓰기 걷기`);
      return true;
    }

    /* ---------- 메이커 줄 ---------- */
    function updateBar() {
      if (shell) shell.update(); // 메뉴 줄 · 도구 줄 · 상태 줄 · 구조 — 작업실 틀(js/maker-shell.js)이 그림
    }
    /** 메이커 줄의 "설치된 판이 바뀌었습니다"를 누르면: 사정을 알리고, 원하면 작업본의 고침을 버리고 설치된 판을 불러옵니다 */
    async function openDrift() {
      if (!drift) return;
      const a = await ask(`${driftText()} 작업본에 고친 것이 있어 새 판을 따라가지 않고 그대로 두었습니다. [반영]하면 설치된 판을 이 작업본으로 덮어씁니다 — 설치된 판에만 있는 것은 사라집니다. 설치된 판을 불러오면 이 작업본의 고침(편집 창의 저장하지 않은 것까지)을 버립니다.`, {
        title: '설치된 판',
        yes: '고침을 버리고 설치된 판 불러오기',
        no: '',
        danger: true,
      });
      const cur = installedPack();
      if (a !== 'yes' || !cur) return;
      await takeSnapshot('설치된 판 불러오기 전');
      setDraft(installedRaw(cur.id) || HT.packToJSON(cur), { keepHistory: true });
      HT.toast(`설치된 «${cur.name}» v${cur.version}을(를) 다시 불러왔습니다.`, 'ok');
    }

    /* ---------- 반영 · 파일로 ---------- */
    /** 반영: 검사 → 판 올림 → 설치된 같은 id의 DLC를 덮어씀(없으면 설치) · 켬 → 작업본도 새 판으로. 묻지 않습니다 —
        다만 설치된 판이 이 작업본을 가져온 뒤에 따로 바뀌었으면(drift) 그 판을 덮어쓸지 먼저 묻습니다.
        DLC를 만들 수 없는 오류면 멈추고 검사 창을, 항목 몇 개만 걸렸으면 반영한 뒤 검사 창을 엽니다(빠진 것이 보이게). 돌려주는 값(Promise): 반영했으면 true */
    async function reflect() {
      if (!ready()) return false;
      flushSoon();
      if (drift && installedPack() && changes.length) {
        const a = await ask(`${driftText()} 반영하면 그 판을 이 작업본으로 덮어씁니다 — 설치된 판에만 있는 것은 사라집니다.`, { title: '설치된 판을 덮어쓸까요', yes: '덮어쓰고 반영', no: '', danger: true });
        if (a !== 'yes' || !draft) return false;
      }
      const target = draft;
      await takeSnapshot('반영 전');
      if (draft !== target) return false;
      return reflectNow();
    }
    function reflectNow() {
      const { pack, errors } = HT.normalizePack(draft);
      if (!pack) {
        HT.toast(`반영하지 못했습니다 — ${(errors[0] && errors[0].msg) || '작업본이 검사를 통과하지 못했습니다.'}`, 'error');
        shell.openBottom('problems');
        return false;
      }
      const cur = installedPack();
      if (cur && !changes.length) {
        HT.toast('고친 것이 없어 반영할 것이 없습니다.');
        return false;
      }
      const version = D.bumpVersion(D.newerVersion(pack.version, cur ? cur.version : ''));
      /* 판 기록 한 줄(설계 3-7): 팩 정보에 적어 둔 말(_nextNote)이 있으면 그 말, 없으면 고친 것 요약 · 마지막 반영한 날 · 덮어쓰기 대상은 필요한 팩으로 */
      const today = kit.today();
      const next = D.clean(draft);
      kit.syncNeeds(next, state.packs);
      next.changelog = kit.nextChangelog(next.changelog, { version, date: today, note: str(next._nextNote) || kit.changelogNote(changes) });
      next.updated = today;
      delete next._nextNote;
      const done = HT.normalizePack(next);
      const json = Object.assign(HT.packToJSON(done.pack || pack), { version });
      const installed = HT.store.get(K.installed, []);
      const list = Array.isArray(installed) ? installed.slice() : [];
      const i = list.findIndex(p => p && p.id === json.id);
      if (i >= 0) list[i] = json;
      else list.push(json);
      if (!HT.store.set(K.installed, list)) {
        HT.toast('저장 공간이 부족해 반영하지 못했습니다 — 아무것도 바뀌지 않았습니다.', 'error');
        return false;
      }
      HT.store.set(K.packState, Object.assign({}, HT.store.get(K.packState, {}), { [json.id]: { enabled: true } }));
      Object.assign(draft, { relations: next.relations, changelog: next.changelog, updated: today }); // 설치가 된 뒤에야 작업본에도 (저장소가 모자라 설치가 안 되면 작업본은 그대로)
      delete draft._nextNote;
      if (!next.relations) delete draft.relations;
      draft.version = version;
      markOrigin(HT.normalizePack(json).pack); // 새 바탕은 방금 설치한 판 — 설치본을 다시 읽기 전에 (다시 읽으면서 "설치본이 바뀌었다"로 보지 않게)
      commit();
      ctx.reloadPacks();
      HT.toast(`«${json.name}»을(를) v${version}(으)로 반영했습니다.${errors.length ? ` 검사에서 걸린 항목 ${errors.length}개는 빠졌습니다 — 검사 창을 보세요.` : ''}`, errors.length ? 'error' : 'ok');
      if (errors.length) shell.openBottom('problems');
      return true;
    }
    /** 해 좌표 → 본 프로그램의 시간(1970년 기준 분) — 내보내기(prototype/scripts/export/base.mjs minute)와 같은 셈 */
    function appMinute(y) {
      const year = Math.floor(y), a = new Date(0), b = new Date(0);
      a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
      b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
      return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
    }
    /** 연표로 ↗ (2026-10-16 감독 "미리보기 하려면 그냥 앱에서 확인하게 해. 본 프로그램"): 컴퓨터의 메이커 앱이면 고치던 작업본을 본 프로그램(연표 앱)의
        미리보기로 띄웁니다 — 반영하지 않아도, 서재는 그대로(본 프로그램이 서재의 임시 사본 위에 얹음 · 보던 범위에서 열림 · 다시 누르면 새로 띄움).
        휴대폰은 알리기만(본 프로그램에 DLC를 넣는 길이 아직 없음 — 메이커 안 연표로 봄), 브라우저는 예전 웹 연표 창 */
    async function toTimeline() {
      if (!HT.platform.canPreviewApp) {
        if (HT.platform.mobile) return HT.toast('본 프로그램 미리보기는 컴퓨터의 메이커 앱에서 됩니다 — 휴대폰에서는 메이커 안 연표로 보세요.');
        return HT.platform.openPage('index.html');
      }
      if (!draft) return HT.toast('미리볼 작업본이 없습니다 — DLC를 열거나 새로 만드세요.');
      flushSoon();
      const { pack, errors } = HT.normalizePack(draft);
      if (!pack) return HT.toast(`미리보기를 만들지 못했습니다 — ${(errors[0] && errors[0].msg) || '작업본이 검사를 통과하지 못했습니다.'}`, 'error');
      try {
        const bytes = await HT.packFile.build(HT.packToJSON(pack));
        const v = ctx.timeline && ctx.timeline.view;
        const view = v && Number.isFinite(v.start) && Number.isFinite(v.end) && v.end > v.start ? [appMinute(v.start), appMinute(v.end)] : null;
        if (await HT.platform.previewInApp(bytes, pack.id, view)) HT.toast(`본 프로그램에서 «${pack.name}» 미리보기를 엽니다 — 작업본을 얹는 데 몇 초 걸립니다.`, 'ok');
      } catch (e) {
        HT.toast(`본 프로그램을 띄우지 못했습니다 — ${(e && e.message) || e}`, 'error');
      }
    }
    /** 파일로: 지금 작업본을 같은 판 번호의 **형식 4** 팩 파일(.htpack · 객체 목록 objects)로 내려받습니다 (반영과 별개 — docs/구상-메이커-팩.md 3-7).
        리메이크 5단계 과제 2부터 저장은 형식 4 — 옛 꼴 작업본을 올리고(HT.F4.up) 열 때 따로 둔 칸(draft.f4extras — 빌림 · 중요도 · 문화권 줄 …)을 되돌립니다. 옛 앱 · 옛 모듈용은 exportLegacy */
    async function exportFile() {
      if (!ready()) return;
      const { pack, errors } = HT.normalizePack(draft);
      if (!pack) return HT.toast(`파일로 만들지 못했습니다 — ${(errors[0] && errors[0].msg) || '작업본이 검사를 통과하지 못했습니다.'}`, 'error');
      try {
        const bytes = await HT.packFile.build(HT.F4.toFile(HT.packToJSON(pack), draft.f4extras));
        const ok = await HT.downloadBlob(HT.packFile.fileName(pack), new Blob([bytes], { type: HT.packFile.MIME }));
        if (ok !== false) HT.toast(`팩 파일(.htpack · 형식 4)을 저장했습니다.${errors.length ? ` 검사에서 걸린 항목 ${errors.length}개는 빠졌습니다.` : ''}`, 'ok');
      } catch (e) {
        HT.toast(`팩 파일을 만들지 못했습니다 — ${(e && e.message) || e}`, 'error');
      }
    }
    /** 옛 형식(3)으로: 옛 앱(0.0.3까지) · HistoryArchive 모듈이 읽는 꼴로 내려받습니다. 형식 4에만 있는 칸은 빠지므로 무엇이 빠지는지 보여 주고 묻습니다(계획 정한 것 #5) */
    async function exportLegacy() {
      if (!ready()) return;
      const { pack, errors } = HT.normalizePack(draft);
      if (!pack) return HT.toast(`파일로 만들지 못했습니다 — ${(errors[0] && errors[0].msg) || '작업본이 검사를 통과하지 못했습니다.'}`, 'error');
      const loss = HT.F4.lossOf(draft.f4extras, HT.packToJSON(pack)); // 빌림 · 직위 줄 더 · 실권은 작업본(옛 꼴)에서 셈(5단계 과제 4)
      if (loss.length) {
        const a = await ask(`옛 형식(3)에는 다음이 빠집니다.\n${loss.map(l => `· ${l}`).join('\n')}\n그래도 저장할까요?`, { title: '옛 형식으로 내보내기', yes: '저장', no: '', plainNo: true });
        if (a !== 'yes') return;
      }
      try {
        const bytes = await HT.packFile.build(HT.F4.legacyFile(HT.packToJSON(pack))); // 옛 꼴 그대로 + 옛 열쇠 yearCycle(「주기」 표의 전체 줄 — 5단계 과제 6)
        const ok = await HT.downloadBlob(HT.packFile.fileName(pack).replace(/\.htpack$/, '-형식3.htpack'), new Blob([bytes], { type: HT.packFile.MIME }));
        if (ok !== false) HT.toast(`옛 형식(3) 팩 파일을 저장했습니다.${loss.length ? ` 형식 4의 칸 ${loss.length}가지는 빠졌습니다.` : ''}${errors.length ? ` 검사에서 걸린 항목 ${errors.length}개는 빠졌습니다.` : ''}`, 'ok');
      } catch (e) {
        HT.toast(`팩 파일을 만들지 못했습니다 — ${(e && e.message) || e}`, 'error');
      }
    }

    /* ---------- 셋 가운데 고르기 (고치는 DLC 바꾸기 · 편집 창에서 다른 항목으로 · 닫기) ---------- */
    const askDialog = $('#mkAskDialog');
    let askDone = null; // 떠 있는 물음의 답을 받을 함수
    /** 물음에 답하고 창을 닫습니다 — 단추 · 바깥 누름 · Esc · 닫힘 어느 길로 와도 한 번만 (닫힘 알림을 기다리지 않고 바로 답합니다) */
    const answer = v => {
      const done = askDone;
      askDone = null;
      if (askDialog.open) askDialog.close(String(v));
      if (done) done(['yes', 'no'].includes(v) ? v : 'cancel');
    };
    /** 돌려주는 값: 'yes' · 'no' · 'cancel' (이미 다른 물음이 떠 있으면 'cancel'). no를 비우면 그 단추 없이 둘 가운데 고르기 · danger = 예가 되돌릴 수 없는 일(붉은 단추) ·
        plainNo = 아니요가 버리는 일이 아님(보통 단추 — 구조 나무의 '나라만 옮기기') */
    const ask = (text, { title = '확인', yes = '예', no = '아니요', danger = false, plainNo = false } = {}) =>
      new Promise(resolve => {
        if (askDialog.open || askDone) return resolve('cancel');
        $('#mkAskTitle').textContent = title;
        $('#mkAskText').textContent = text;
        $('#mkAskYes').textContent = yes;
        $('#mkAskYes').className = `btn ${danger ? 'btn-danger' : 'btn-primary'}`;
        $('#mkAskNo').className = plainNo ? 'btn' : 'btn btn-danger';
        $('#mkAskNo').textContent = no;
        $('#mkAskNo').hidden = !no;
        askDialog.returnValue = 'cancel';
        askDone = resolve;
        askDialog.showModal();
      });

    /* ---------- 고치는 DLC 바꾸기 ---------- */
    function setDraft(raw, { keepHistory = false } = {}) {
      flushSoon();
      if (HT.fieldPop) HT.fieldPop.detach(); // 큰 입력 창은 강제로 떼어 냄 — 같은 id의 새 작업본에서 같은 이름의 칸에 다시 묶여 옛 글이 새 파일을 덮지 않게
      ctx.closeEditor(); // 편집 창이 옛 작업본의 항목을 들고 있지 않게 (물을 것은 부른 쪽이 먼저 물었습니다)
      draft = D.clean(raw);
      selectedItems = []; savedSnapshots = []; snapshotToken++;
      if (!keepHistory) history.reset(draft);
      snapshotText = HT.makerHistory.content(draft);
      goodPack = null;
      others = base = null;
      commit();
      markOrigin(installedPack()); // 바탕 판: 지금 설치된 같은 id(없으면 없음) — 같은 id의 파일을 열 때는 openFile이 먼저 물었습니다
      ctx.closeDetail();
      ctx.refresh();
      if (shell && shell.propsMode() === 'info') renderInfo(); // 팩 정보가 열려 있으면 새 작업본으로
      if (shell && shell.bottomTab() === 'autosave') loadSnapshots();
    }
    /** 다른 DLC로 바꿉니다 — 편집 창에 저장하지 않은 고침이 있거나 반영하지 않은 고침이 있으면 먼저 묻습니다. getRaw() = 새 작업본이 될 DLC JSON */
    async function switchDraft(getRaw) {
      flushSoon(); // 팩 정보 · 바탕 자료에서 치던 글(잠깐 쉬었다 저장)을 먼저 저장 — 바꾸면서 잃지 않게
      if (!(await ctx.leaveEditor('바꾸기'))) return false;
      if (draft && changes.length) {
        const a = await ask(`«${draft.name}»에 반영하지 않은 고침이 ${changes.length}개 있습니다.`, { title: '고치는 DLC 바꾸기', yes: '반영하고 바꾸기', no: '버리고 바꾸기' });
        if (a === 'cancel') return false;
        if (a === 'yes' && !(await reflect())) return false;
      }
      await takeSnapshot('DLC 바꾸기 전');
      setDraft(getRaw());
      return true;
    }
    /** 설치한 DLC를 골라 고칩니다 (이미 고치는 DLC면 그대로 — 설치본이 그 뒤에 바뀐 것은 모델을 지을 때 따라가거나 메이커 줄에 알립니다) */
    async function pick(id) {
      if (isDraftId(id)) {
        if (drift) HT.toast(`${driftText()} 메이커 줄의 알림을 누르면 설치된 판을 불러올 수 있습니다.`);
        return true;
      }
      const raw = installedRaw(id);
      if (!raw) {
        HT.toast('설치한 DLC 가운데 그 DLC를 찾지 못했습니다. (기본 내장 팩은 직접 고치지 않고, 고치는 DLC의 패치로 고칩니다)', 'error');
        return false;
      }
      const ok = await switchDraft(() => raw);
      if (ok) HT.toast(`«${draft.name}» v${draft.version}을(를) 고칩니다.`, 'ok');
      return ok;
    }
    async function openFile(given) {
      const [file] = given ? [given] : await HT.pickFiles('.htpack');
      if (!file) return;
      let raw;
      let notes = [];
      let raw4 = null; // 형식 4 파일의 원본(옛 꼴 작업본에 남지 않는 칸을 저장 때 되돌리는 재료 — 5단계 과제 2)
      try {
        ({ raw, notes = [], raw4 = null } = await HT.packFile.read(file)); // 확장자와 전용 형식 · 손상 검사까지 통과한 팩만 (형식 4는 옛 꼴로 내려 받고 그 알림이 notes에 — 리메이크 1단계)
      } catch (err) {
        return HT.toast(err && err.packError ? err.message : 'DLC 파일을 읽을 수 없습니다.', 'error');
      }
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return HT.toast('DLC 파일 형식이 아닙니다.', 'error');
      if (raw.format === 'history-timeline-backup') return HT.toast('백업 파일입니다. 연표의 [DLC 관리 → DLC 설치]에서 복원하세요.', 'error');
      /* 큰 표지(휴대폰 사진 같은)는 작업본에 넣기 전에 줄입니다 — 작업본은 브라우저 저장소에 두므로(몇 MB짜리는 저장이 실패), 설치 길과 같은 문턱 */
      if (typeof raw.cover === 'string' && raw.cover.length > 300000) {
        try {
          raw.cover = await HT.packFile.fitCover(raw.cover, 1600, 900);
        } catch (e) {
          delete raw.cover;
          HT.toast('표지 그림을 줄이지 못해 표지 없이 엽니다.', 'error');
        }
      }
      if (raw.format !== HT.FORMAT && !confirm('DLC 형식 표시("format")가 없는 파일입니다. 그래도 열까요?')) return;
      /* 작업본은 형식 버전을 늘 이 프로그램의 것으로 적으므로 검사에는 "더 새로운 형식" 경고가 나오지 않습니다 — 열 때 여기서 묻습니다 */
      if (Number(raw.formatVersion) > HT.FORMAT_VERSION && !confirm(`더 새로운 형식 버전(${raw.formatVersion})으로 만들어진 파일입니다. 이 프로그램이 모르는 정보는 반영하거나 파일로 낼 때 빠집니다. 그래도 열까요?`)) return;
      /* id: 반영은 같은 id의 설치본을 묻지 않고 덮어쓰므로, 여기서 먼저 봅니다.
         쓸 수 있는 id가 없는 파일은 겹치지 않는 새 id로 (그냥 두면 기본 id "my-dlc"가 붙어 같은 id의 다른 DLC를 덮어쓸 수 있음) ·
         이미 설치된(기본 내장 포함) DLC와 id가 같으면 알리고 "새 id로 열기 / 그대로 열기 / 취소"를 고르게 합니다 */
      const fileId = str(raw.id);
      let fresh = ''; // 새로 매긴 id
      let renamed = false; // 쓸 수 있는 id를 새 id로 바꿨는지 (제 항목의 문서 · 패치가 새 id를 따라가게)
      if (!HT.ID_RE.test(fileId) || fileId === HT.USER_PACK.id) fresh = kit.uniqueId('my-dlc', usedIds());
      else {
        const same = state.packs.find(p => p.id === fileId);
        if (same) {
          const a = await ask(
            `이 파일의 id «${fileId}»는 이미 설치된 «${same.name}» v${same.version}${same.builtin ? '(기본 내장 팩)' : ''}과(와) 같습니다 (파일은 v${str(raw.version) || '?'}). 그대로 열어 [반영]하면 설치된 것을 이 파일의 내용으로 덮어씁니다. 새 id로 열면 반영할 때 따로 설치됩니다.`,
            { title: '같은 id의 DLC', yes: '새 id로 열기', no: '그대로 열기' }
          );
          if (a === 'cancel') return;
          if (a === 'yes') {
            fresh = kit.uniqueId(fileId, usedIds());
            renamed = true;
          }
        }
      }
      const extras = raw4 ? HT.F4.extrasOf(raw4) : null; // 객체 id마다 모으므로 DLC id를 바꿔도 그대로
      const getRaw = () => {
        const d = !fresh ? raw : !renamed ? D.clean(Object.assign({}, raw, { id: fresh })) : D.clean(raw);
        if (fresh && renamed) kit.renameDlc(d, fresh);
        if (extras) d.f4extras = extras;
        else delete d.f4extras;
        if (notes.length) d.f4notes = notes.slice(); // 다리(HT.F4.down)가 내리며 낸 알림 — 검사 창이 알림으로 올립니다(5단계 과제 8 · 토스트는 사라지므로)
        else delete d.f4notes;
        return d;
      };
      if (await switchDraft(getRaw)) {
        if (shell) shell.hideStart();
        HT.toast(`«${draft.name}»을(를) ${fresh ? `${renamed ? '새' : '파일에 쓸 수 있는 id가 없어 새'} id «${fresh}»로 ` : ''}열었습니다. [반영]을 눌러야 연표에 설치됩니다.${fresh ? ' id는 DLC 정보에서 바꿀 수 있습니다.' : ''}${notes.length ? ` ${notes.join(' ')}` : ''}`, 'ok');
      }
    }

    const usedIds = () => new Set(state.packs.map(p => p.id).concat(draft ? [draft.id] : []));
    /* ---------- 새로 만들기 (처음 화면 — 설계 3-3): 빈 DLC · 기본팩에 덧붙이기(기본팩을 잠긴 채 불러옴 — 과제 8) · 가상 세계(이 DLC의 트랙 하나) ---------- */
    /** 돌려주는 값(Promise): 문제 글 배열(비면 만듦) · null(바꾸기를 그만둠) */
    async function createNew({ name, id, category, how }) {
      const problems = [];
      if (!name) problems.push('이름을 적어 주세요.');
      if (!HT.ID_RE.test(id) || id === HT.USER_PACK.id) problems.push('id는 영문·숫자·- _ . 만 쓸 수 있습니다.');
      else if (usedIds().has(id)) problems.push('같은 id의 DLC가 이미 있습니다. 다른 id를 적어 주세요.');
      if (problems.length) return problems;
      const ok = await switchDraft(() => {
        const d = D.blank({ name, id });
        if (HT.PACK_CATEGORIES.some(c => c.id === category)) d.category = category;
        d.created = kit.today();
        if (how === 'world') d.tracks.push({ id: 'world', name });
        return d;
      });
      if (!ok) return null;
      if (how === 'base') {
        /* 기본팩에 덧붙이기: 기본팩을 잠긴 채 불러온 팩으로 (트랙 · 민족을 가져다 씀 — 항목을 넣으면 ensureRefs가 정의를 작업본에 옮겨 둠) */
        const rows = state.packs.filter(p => p.builtin).map(p => ({ id: p.id, show: true, locked: true }));
        if (rows.length) {
          refsAll[draft.id] = rows;
          saveRefs();
          ctx.refresh();
        }
      }
      HT.toast(`새 DLC «${draft.name}»을(를) 만들었습니다. ${how === 'world' ? `트랙 «${name}»에 ` : ''}항목을 더한 뒤 [반영]을 누르세요.`, 'ok');
      return [];
    }
    /** 작업본 닫기 (처음 화면의 '반영하고 닫기') — 작업본 · 바탕 판 기록을 지움 */
    function closeDraft() {
      flushSoon(); takeSnapshot('작업본 닫기 전');
      history.reset(null); selectedItems = [];
      if (HT.fieldPop) HT.fieldPop.detach();
      ctx.closeEditor();
      ctx.closeDetail();
      draft = goodPack = null;
      others = base = null;
      HT.store.remove(K.draft);
      HT.store.remove(ORIGIN_KEY);
      ctx.refresh();
      if (shell) shell.showProps('empty');
    }
    /** 끌어다 놓은 파일 · 연결 프로그램으로 넘어온 파일: 메이커에서는 설치가 아니라 열기 (하나씩) */
    function openDropped(files) {
      if (files.length > 1) HT.toast('파일은 한 번에 하나씩 엽니다 — 첫 파일을 엽니다.');
      return openFile(files[0]);
    }
    /** 이어서 고치기 카드의 [↺ 설치된 판으로 되돌리기] (옛 고르는 창에 있던 것): 반영하지 않은 고침을 버리고 설치된 판을 다시 불러옴 */
    const canRestore = () => {
      const cur = installedPack();
      return !!(draft && cur && !cur.builtin && changes.length && installedRaw(draft.id));
    };
    async function restoreInstalled() {
      if (!canRestore()) return false;
      const a = await ask(`«${draft.name}»의 반영하지 않은 고침 ${changes.length}개를 버리고 설치된 판을 다시 불러올까요?`, { title: '설치된 판으로 되돌리기', yes: '버리고 되돌리기', no: '', danger: true });
      if (a !== 'yes') return false;
      await takeSnapshot('설치된 판 불러오기 전');
      setDraft(installedRaw(draft.id), { keepHistory: true });
      HT.toast('설치된 판을 다시 불러왔습니다.', 'ok');
      return true;
    }

    /* ---------- 고친 것 목록 ---------- */
    /** 아래 창 [고친 것]의 몸통 글 */
    function changesHTML() {
      const names = uid => {
        const x = baseModel().byUid.get(uid);
        return x ? `${esc(x.title || x.name)} <small>${esc(HT.itemWord(x))} · ${esc(x.packName)}</small>` : `${esc(uid)} <small>지금 켜져 있는 DLC에 없는 항목</small>`;
      };
      /* 문서 키 → 읽을 만한 이름과 무엇의 문서인지: 항목(시대 · 사건 · 인물 · 대범위 …) · 칸(지도자 · 시기 …)의 문서는 그 항목 이름으로 (제 항목은 지금 모델에서, 남의 항목은 원본에서),
         민족 · 트랙 · 분류 · 가문("house:id")은 그 이름으로, 하위 문서는 뒤에 "/이름". 찾지 못하면 키 그대로 */
      const DEF_MAPS = { people: 'peopleMap', track: 'trackMap', category: 'categoryMap', house: 'houseMap' };
      const docName = key => {
        const p = HT.docKey.parse(HT.docKey.absolute(key, draft.id));
        const find = m => (p.uid ? m.byUid.get(p.uid) : DEF_MAPS[p.type] && m[DEF_MAPS[p.type]] ? m[DEF_MAPS[p.type]].get(p.id) : null);
        const x = find(state.model) || find(baseModel());
        if (!x) return esc(key);
        const CK = p.type === 'cell' ? HT.cellKind(p.cellKind) : null;
        const word = CK ? CK.name : p.uid ? HT.itemWord(x) : HT.ITEM_WORDS[p.type] || '';
        return `${esc(x.title || x.name)}${CK ? ` · ${esc(p.name)}` : ''}${p.sub ? `/${esc(p.sub.split('//').join('/'))}` : ''}${word ? ` <small>${esc(word)}</small>` : ''}`;
      };
      const label = c => {
        const what = esc(c.label.split(' · ')[0]);
        if (c.list === 'patches') return `${what} · ${names(c.key)}`;
        return c.list === 'documents' ? `${what} · ${docName(c.key)}` : esc(c.label);
      };
      const patches = draft ? draft.patches.filter(p => p && p.target) : [];
      /* 패치가 고친 칸 수 — 상세의 수정 내역 상자와 같은 규칙(HT.patchChanges: 날짜 글 짝 칸은 값 칸과 한 칸, 고치기 전과 같은 값인 칸은 세지 않음).
         이 DLC의 패치가 지금 모델에 얹혀 있지 않으면(대상이 꺼져 있을 때 …) 적힌 칸을 짝 칸만 합쳐 셉니다 */
      const patchCount = p => {
        const x = state.model && state.model.byUid.get(p.target);
        const i = x && x.patchedBy ? x.patchedBy.findIndex(e => isDraftId(e.id)) : -1;
        return i >= 0 ? HT.patchChanges(x, i).length : new Set(Object.keys(p.set || {}).map(k => HT.PATCH_AT_OF[k] || k)).size;
      };
      return `
        <section class="dlc-section">
          <h3>반영하지 않은 고침 <small>${changes.length}개 · [반영]을 누르면 판을 올려 연표에 설치합니다</small></h3>
          ${changes.length ? `<ul class="mk-change-list">${changes.slice(0, 200).map(c => `<li class="is-${c.type}">${label(c)}</li>`).join('')}${changes.length > 200 ? `<li>…외 ${changes.length - 200}개</li>` : ''}</ul>` : '<p class="hint">없습니다.</p>'}
        </section>
        <section class="dlc-section">
          <h3>남의 항목에 건 패치 <small>${patches.length}개 · 다른 DLC · 기본팩의 항목을 고치거나 숨긴 것</small></h3>
          ${
            patches.length
              ? `<ul class="mk-patch-list">${patches
                  .map(p => `<li><span class="mk-patch-name">${names(p.target)}</span><span class="pack-tag">${p.hide ? '숨김' : `고침 ${patchCount(p)}칸`}</span>${
                    p.hide ? '' : `<button type="button" class="btn btn-sm" data-show="${esc(p.target)}">보기</button>`
                  }<button type="button" class="btn btn-sm" data-unpatch="${esc(p.target)}">↩ 되돌리기</button></li>`)
                  .join('')}</ul>`
              : '<p class="hint">없습니다.</p>'
          }
        </section>`;
    }

    /* ---------- 끌기 (편집 창 · 떠 있는 창 공용) ----------
     * handle을 누르고 끌면 opts.move(dx, dy, 이벤트, 시작 때 돌려준 값)를 부릅니다. 포인터를 붙잡으므로 창 밖에서 손을 떼도 다른 곳이 눌린 것으로 처리되지 않습니다.
     * opts: skip(e) 이 누름은 무시(단추 · 입력 칸) · start(e) 시작할 때의 값(거짓이면 끌지 않음) · threshold 이만큼(px) 움직여야 끌기 · end(움직였는지, 시작 값) */
    function dragOn(handle, opts) {
      if (!handle) return;
      handle.addEventListener('pointerdown', e => {
        if (e.button !== 0 || (opts.skip && opts.skip(e))) return;
        const s = opts.start(e);
        if (!s) return;
        e.preventDefault(); // 끄는 동안 글이 골라지지 않게
        try {
          handle.setPointerCapture(e.pointerId);
        } catch (err) {
          /* 시험용 합성 포인터(활성 포인터가 아님)는 붙잡을 수 없습니다 — 끌기 처리는 그대로 이어 갑니다 */
        }
        const x0 = e.clientX;
        const y0 = e.clientY;
        let moved = false;
        const move = ev => {
          if (!moved && Math.hypot(ev.clientX - x0, ev.clientY - y0) < (opts.threshold || 3)) return; // 누르기만 한 것은 끌기가 아닙니다
          moved = true;
          opts.move(ev.clientX - x0, ev.clientY - y0, ev, s);
        };
        const end = () => {
          handle.removeEventListener('pointermove', move);
          handle.removeEventListener('pointerup', end);
          handle.removeEventListener('pointercancel', end);
          if (opts.end) opts.end(moved, s);
        };
        handle.addEventListener('pointermove', move);
        handle.addEventListener('pointerup', end);
        handle.addEventListener('pointercancel', end);
      });
    }
    const onControl = e => !!e.target.closest('button, input, select, textarea, a, label, [role="tab"]');

    /* ---------- 떠 있는 창 (바탕 자료 · 검사 · 떼어 낸 편집 창) — 막지 않음, 제목 줄을 끌어 옮기고 모서리를 끌어 크기를 바꿈, 자리 · 크기는 기억 ---------- */
    const WIN_KEY = 'ht.maker.wins';
    const winUi = (() => {
      const s = HT.store.get(WIN_KEY, null);
      return s && typeof s === 'object' && !Array.isArray(s) ? s : {};
    })();
    const saveWinUi = () => HT.store.set(WIN_KEY, winUi);
    const floats = []; // 떠 있는 창 요소들 — 누른 창이 맨 앞으로
    const num = v => (typeof v === 'number' && isFinite(v) ? Math.round(v) : null);
    /** 떠 있는 창의 자리 · 크기를 화면 안으로 (제목 줄이 늘 잡을 수 있게 남음) */
    const fitRect = ({ x, y, w, h }, minW, minH) => {
      const W = HT.clamp(w, minW, Math.max(minW, innerWidth - 16));
      const H = HT.clamp(h, minH, Math.max(minH, innerHeight - 16));
      return { x: HT.clamp(x, 120 - W, innerWidth - 120), y: HT.clamp(y, 0, Math.max(0, innerHeight - 48)), w: W, h: H };
    };
    const putRect = (el, r) => Object.assign(el.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
    /** 누른 창을 맨 앞으로 (떠 있는 창끼리의 차례 — 60부터, 메뉴(120)보다는 아래). 좁은 화면에서는 편집 창도 화면을 덮는 시트라 같은 차례에 듭니다 */
    function front(el) {
      const open = floats.filter(w => w !== el && !w.hidden && (w.classList.contains('is-floating') || narrow())).sort((a, b) => (Number(a.style.zIndex) || 0) - (Number(b.style.zIndex) || 0));
      open.concat([el]).forEach((w, i) => (w.style.zIndex = String(60 + i)));
    }
    function makeWin(el, name, def) {
      el.classList.add('is-floating');
      floats.push(el);
      const rect = () => {
        const s = winUi[name] || {};
        const w = num(s.w) || def.w;
        const h = num(s.h) || Math.min(def.h, innerHeight - 120);
        return fitRect({ x: num(s.x) ?? def.x(w), y: num(s.y) ?? 96, w, h }, 320, 220);
      };
      const place = () => putRect(el, rect());
      const remember = r => {
        winUi[name] = Object.assign({}, winUi[name], r);
      };
      dragOn(el.querySelector('[data-win-drag]'), {
        skip: e => onControl(e) || narrow(),
        start: () => {
          const r = el.getBoundingClientRect();
          return { x: r.left, y: r.top };
        },
        move: (dx, dy, e, s) => {
          remember({ x: Math.round(s.x + dx), y: Math.round(s.y + dy) });
          place();
        },
        end: moved => moved && saveWinUi(),
      });
      dragOn(el.querySelector('[data-win-corner]'), {
        start: () => !narrow() && { w: el.offsetWidth, h: el.offsetHeight },
        move: (dx, dy, e, s) => {
          remember({ w: Math.round(s.w + dx), h: Math.round(s.h + dy) });
          place();
        },
        end: moved => moved && saveWinUi(),
      });
      el.addEventListener('pointerdown', () => front(el), true);
      el.addEventListener('click', e => {
        if (e.target.closest('[data-win-close]')) api.close();
      });
      const api = {
        el,
        isOpen: () => !el.hidden,
        open() {
          if (def.render) def.render();
          place();
          el.hidden = false;
          front(el);
        },
        close() {
          el.hidden = true;
        },
        toggle() {
          if (el.hidden) api.open();
          else api.close();
        },
        place,
      };
      return api;
    }

    /* ---------- 편집 창: 오른쪽에 붙은 막지 않는 창 (상세 자리) ----------
     * 폼을 채우고 저장하는 것은 viewer.js(openEditor · saveEditor)이고, 여기서는 틀만: 붙박이 폭은 작업실의 오른쪽 창(js/maker-shell.js — 가장자리 끌기 · 넓게) ·
     * 머리의 넓게/좁게 · 제목 줄을 끌어 떼어 내면 떠 있는 창(자리 · 크기 기억, 모서리로 크기 조절, [다시 붙이기]). 폭과 모양은 이 브라우저의 화면 설정으로 기억합니다.
     * 좁은 화면(860px 이하)에서는 화면 전체를 덮는 시트 (css/maker.css) */
    const pane = $('#editPane');
    const PANE_KEY = 'ht.maker.pane';
    const PANE_MIN = 380; // 떠 있는 편집 창의 가장 작은 폭
    const paneUi = (() => {
      const s = HT.store.get(PANE_KEY, null) || {};
      return { w: num(s.w), wide: s.wide === true, float: s.float === true, x: num(s.x), y: num(s.y), fw: num(s.fw), fh: num(s.fh) };
    })();
    const savePaneUi = () => HT.store.set(PANE_KEY, paneUi);
    floats.push(pane);
    const isFloat = () => paneUi.float && !narrow();
    function layoutPane() {
      const float = isFloat();
      /* 쌓임 차례를 오른쪽 상세 칸에 전파하지 않습니다. 좁은 화면의 시트도 다른 창과 같은 부모에서 front()의 차례를 따릅니다. */
      const parent = float || narrow() ? document.body : $('#mkRight');
      if (parent && pane.parentElement !== parent) {
        const focus = pane.contains(document.activeElement) ? document.activeElement : null;
        parent.appendChild(pane);
        if (focus) focus.focus({ preventScroll: true });
      }
      pane.classList.toggle('is-floating', float);
      pane.classList.toggle('is-docked', !float);
      if (float) {
        const w = paneUi.fw || 520;
        const r = fitRect({ x: paneUi.x ?? innerWidth - w - 28, y: paneUi.y ?? 72, w, h: paneUi.fh || Math.round(innerHeight * 0.8) }, PANE_MIN, 320);
        putRect(pane, r);
      } else {
        pane.style.left = pane.style.top = pane.style.width = pane.style.height = '';
        if (!narrow()) pane.style.zIndex = ''; // 붙은 창은 상세 자리(css) — 좁은 화면의 시트는 떠 있는 창들과 같은 차례(front)
      }
      const wideBtn = pane.querySelector('[data-pane="wide"]');
      const dockBtn = pane.querySelector('[data-pane="dock"]');
      wideBtn.hidden = float;
      dockBtn.hidden = !float;
      pane.querySelector('[data-pane-drag]').title = float ? '제목 줄을 끌어 옮깁니다' : '제목 줄을 끌면 떼어 내 떠 있는 창이 됩니다';
      /* 붙은 모양(좁은 화면의 시트 포함)은 상세와 같은 자리 — 떠 있을 때 따로 열어 둔 상세가 편집 창 밑에 깔린 채 남지 않게 닫습니다
         ([다시 붙이기] · 화면을 좁힘). 남겨 두면 다음 refresh가 그 상세를 다시 열려다 편집 창을 그 항목으로 바꿉니다 */
      if (!float && !pane.hidden && !$('#detail').hidden) ctx.closeDetail();
    }
    const paneApi = {
      isOpen: () => !pane.hidden,
      /** 상세와 같은 자리를 쓰고 있는지 (붙어 있거나 좁은 화면의 시트) — 그러면 상세를 열기 전에 편집 창을 닫습니다 */
      blocks: () => !pane.hidden && !isFloat(),
      /** 연표의 오른쪽을 가린 폭 (viewer.js의 syncInset) — 떠 있으면 0 */
      cover: () => 0, // 작업실: 편집 창은 연표 밖(오른쪽 창 · 떠 있는 창)이라 연표를 가리지 않음
      show() {
        const was = !pane.hidden;
        layoutPane();
        pane.hidden = false;
        if (shell) {
          shell.showProps('empty');
          if (!isFloat()) shell.revealRight();
        }
        if (isFloat() || narrow()) front(pane);
        if (!was) HT.platform.trapBack(() => ctx.leaveEditor());
        ctx.syncInset();
      },
      hide() {
        if (pane.hidden) return;
        pane.hidden = true;
        HT.platform.releaseBack();
        ctx.syncInset();
      },
    };
    function setPaneWide(on) {
      if (shell) shell.setRightWide(on); // 붙박이 폭은 작업실의 오른쪽 창 (ht.maker.ui)
      ctx.syncInset();
    }
    dragOn(pane.querySelector('[data-pane-drag]'), {
      skip: e => onControl(e) || narrow(),
      threshold: 6,
      start: e => {
        const r = pane.getBoundingClientRect();
        return { ox: e.clientX - r.left, oy: e.clientY - r.top, w: r.width, h: r.height };
      },
      move: (dx, dy, e, s) => {
        if (!paneUi.float) {
          /* 붙어 있던 창을 떼어 냄: 기억한 떠 있는 크기(없으면 지금 크기 — 너무 넓으면 줄여서)로, 잡은 자리가 손 밑에 오게 */
          paneUi.float = true;
          paneUi.fw = paneUi.fw || Math.round(Math.min(s.w, 640));
          paneUi.fh = paneUi.fh || Math.round(Math.min(s.h, innerHeight * 0.8));
          s.ox = Math.min(s.ox, paneUi.fw - 60);
          pane.classList.add('is-resizing');
        }
        paneUi.x = Math.round(e.clientX - s.ox);
        paneUi.y = Math.round(e.clientY - s.oy);
        layoutPane();
        // 부모를 바꾸면 브라우저가 포인터 붙잡기를 놓으므로, 같은 끌기를 끝까지 이어 받습니다.
        pane.querySelector('[data-pane-drag]').setPointerCapture(e.pointerId);
        front(pane);
      },
      end: moved => {
        pane.classList.remove('is-resizing');
        if (!moved) return;
        savePaneUi();
        ctx.syncInset();
      },
    });
    dragOn(pane.querySelector('[data-pane-corner]'), {
      start: () => isFloat() && { w: pane.offsetWidth, h: pane.offsetHeight },
      move: (dx, dy, e, s) => {
        paneUi.fw = Math.round(Math.max(PANE_MIN, s.w + dx));
        paneUi.fh = Math.round(Math.max(320, s.h + dy));
        layoutPane();
      },
      end: moved => moved && savePaneUi(),
    });
    pane.addEventListener('pointerdown', () => (isFloat() || narrow()) && front(pane), true);
    pane.addEventListener('click', e => {
      const b = e.target.closest('[data-pane]');
      if (!b) return;
      const act = b.dataset.pane;
      if (act === 'close') ctx.leaveEditor();
      else if (act === 'paste-all') pasteWhole();
      else if (act === 'kin') {
        const r = b.getBoundingClientRect();
        ctx.kinPaneMenu(state.editing, r.left, r.bottom + 2);
      }
      else if (act === 'wide') setPaneWide(!(shell && shell.rightWide()));
      else if (act === 'dock') {
        paneUi.float = false;
        savePaneUi();
        layoutPane();
        ctx.syncInset();
      }
    });
    window.addEventListener('resize', () => {
      if (!pane.hidden) {
        layoutPane();
        ctx.syncInset();
      }
      for (const w of [baseWin]) if (w.isOpen()) w.place();
    });

    /* ---------- 팩 정보 (설계 3-6 — info.png): 오른쪽 창. 치는 대로 저장(잠깐 쉬었다 한 번에 — commitSoon), id는 칸을 떠날 때(renameTo).
       칸은 열 때만 그림 — 모델이 새로 지어져도 카드 · 표지 · 담긴 것 · 다음 반영 줄만 고침(치던 글 · 한글 조합이 끊기지 않게) ---------- */
    const L = HT.PACK_LIMITS;
    const REL_KINDS = [['needs', '필요한 팩'], ['requires', '함께 쓰면 좋음'], ['conflicts', '함께 못 씀'], ['after', '뒤에 불러오기']];
    const infoEl = () => shell && shell.propsInfo;
    const packNow = () => goodPack || HT.normalizePack(draft).pack || draft;
    const nextVer = () => (changes.length ? D.bumpVersion(D.newerVersion(draft.version, (installedPack() || {}).version || '')) : '');
    const tagsHTML = () =>
      arr(draft.tags).map((t, i) => `<span class="mk-chip">${esc(t)}<button type="button" data-tag-del="${i}" aria-label="${esc(t)} 빼기">✕</button></span>`).join('') +
      (arr(draft.tags).length < L.tags ? `<input data-tag-input maxlength="${L.tagLen}" aria-label="태그 더하기 — 치고 Enter" autocomplete="off">` : '');
    const hlRow = (h, i) => `<li><span class="mk-handle" data-hl-drag title="끌어 차례 바꾸기 (Alt+↑↓)" aria-hidden="true">⋮⋮</span><input data-hl-text value="${esc(h)}" maxlength="${L.highlightLen}" aria-label="볼거리 ${i + 1}" autocomplete="off"><button type="button" data-hl-del aria-label="이 줄 빼기">✕</button></li>`;
    function relsHTML() {
      const locked = new Set(kit.patchTargets(draft));
      const name = id => (state.packs.find(p => p.id === id) || {}).name || id;
      return REL_KINDS.map(([type, label]) => {
        const ids = type === 'requires' ? arr(draft.requires) : arr(draft.relations).filter(r => r && r.type === type).map(r => r.id);
        /* 관계의 보일 이름(relations[].name — 설치되어 있지 않을 때 보일 이름): 칩 안의 글 칸으로 직접 고침 (2026-10-23 — 전역 확대 ⑩) */
        const rel = id => arr(draft.relations).find(r => r && r.type === type && r.id === id) || {};
        const nameIn = id => (type === 'requires' ? '' : `<input data-rel-name="${esc(id)}" value="${esc(rel(id).name || '')}" aria-label="보일 이름" title="설치되어 있지 않을 때 보일 이름 — 비우면 설치된 팩 이름이나 id" autocomplete="off">`);
        const chip = id => (type === 'needs' && locked.has(id) ? `<span class="mk-chip is-locked" title="${esc(id)} — 덮어쓰기가 남아 있는 동안은 뺄 수 없음">${esc(name(id))}${nameIn(id)}<small>덮어쓰기 대상</small></span>` : `<span class="mk-chip" title="${esc(id)}">${esc(name(id))}${nameIn(id)}<button type="button" data-rel-del="${esc(id)}" aria-label="${esc(name(id))} 빼기">✕</button></span>`);
        return `<div class="mk-rel" data-rel="${type}"><b>${label}</b><div class="mk-chips">${ids.map(chip).join('')}<input list="mkPackIds" data-rel-input aria-label="${label} 더하기 — 설치된 팩을 고르거나 id를 적고 Enter" spellcheck="false" autocomplete="off"></div></div>`;
      }).join('');
    }
    /* 날짜 칸의 간지 설정 (형식 버전 3 — 설계 6 결정 8 B · 감독 선택 D4): 육십갑자(기본 — 열쇠 없음) · 기본으로 끔(false) · 다른 순환({ names, start, label }).
       보는 사람은 어느 쪽이든 연표 필터의 '간지'로 켜고 끕니다 */
    const cycleHTML = () => {
      const c = draft.yearCycle;
      const mode = c === false ? 'off' : c && typeof c === 'object' ? 'custom' : '';
      const cc = mode === 'custom' ? c : {};
      const opt = (v, text) => `<option value="${v}"${mode === v ? ' selected' : ''}>${text}</option>`;
      const hide = mode === 'custom' ? '' : ' hidden';
      return `<label class="field"><span>날짜 칸의 간지 설정 <small>(간지 줄 — 비우면 육십갑자 · 보는 사람은 연표 필터의 '간지'로 늘 켜고 끔 · 문화권별 줄은 바탕 자료의 「주기」 표 — 이 설정은 그 표의 전체 줄)</small></span><select name="yearCycleMode">${opt('', '육십갑자 (기본)')}${opt('off', '기본으로 끔 — 보는 사람이 필터에서 다시 켬')}${opt('custom', '다른 순환 — 명칭 목록 · 기준 연도 · 줄 제목')}</select></label>
          <label class="field" data-cycle-custom${hide}><span>명칭 목록 <small>(쉼표로 가름 · 둘 이상 · 해마다 차례로 하나씩 돌아옴 · ${HT.YEAR_CYCLE_LIMITS.names}개 · 하나에 ${HT.YEAR_CYCLE_LIMITS.nameLen}자까지)</small></span><input name="yearCycleNames" value="${esc(arr(cc.names).join(', '))}" autocomplete="off"></label>
          <label class="field" data-cycle-custom${hide}><span>기준 연도 <small>(첫 명칭이 붙는 해 — 그 앞뒤로 이어 셉니다 · 기원전은 "기원전 57"이나 -57)</small></span><input name="yearCycleStart" value="${esc(cc.start != null ? String(cc.start) : '')}" autocomplete="off"></label>
          <label class="field" data-cycle-custom${hide}><span>줄 제목 <small>(날짜 칸 왼쪽 · 비우면 "간지" · ${HT.YEAR_CYCLE_LIMITS.label}자까지)</small></span><input name="yearCycleLabel" value="${esc(cc.label || '')}" maxlength="${HT.YEAR_CYCLE_LIMITS.label}" autocomplete="off"></label>`;
    };
    /* 지도자 표기 낱말(leaderLabels — 리메이크 6단계 D3 · 걸음 3): 지도자 칸의 묘호 · 시호 · 이름 칸을 이 DLC에서 부르는 말. 비운 칸은 기본 낱말,
       문화권마다 다르면 바탕 자료의 「문화권」 표(그쪽이 이김 — HT.leaderWords). 치는 대로 작업본에(kit.nestSet — 다 비우면 열쇠를 지움) */
    const leaderWordsHTML = () =>
      `<div class="field"><span>지도자 표기 낱말 <small>(묘호 · 시호 · 이름 칸을 이 DLC에서 부르는 말 — 치세명 · 존호 · 본명처럼 · 칸 창 · 표기 고르기 · 풍선에 쓰임 · 비우면 묘호 · 시호 · 이름 · 문화권마다 다르면 바탕 자료의 「문화권」 표)</small></span><div class="mk-words">${['temple', 'title', 'given']
        .map(k => `<label><small>${esc(HT.LEADER_WORDS[k])} 칸</small><input name="leaderLabel-${k}" value="${esc(kit.nestGet(draft, ['leaderLabels', k]) || '')}" maxlength="20" aria-label="${esc(HT.LEADER_WORDS[k])} 칸의 낱말" autocomplete="off"></label>`)
        .join('')}</div></div>`;
    /** 간지 설정을 작업본에 — 다른 순환은 명칭 둘 이상 · 기준 연도가 읽힐 때만 적고, 아니면 알림(친 글은 칸에 그대로) */
    function saveCycle() {
      const el = infoEl();
      const v = name => (el.querySelector(`[name="${name}"]`) || { value: '' }).value;
      const mode = v('yearCycleMode');
      el.querySelectorAll('[data-cycle-custom]').forEach(x => (x.hidden = mode !== 'custom'));
      const problems = [];
      if (!mode) delete draft.yearCycle;
      else if (mode === 'off') draft.yearCycle = false;
      else {
        const names = v('yearCycleNames').split(/[,，]/).map(s => s.trim()).filter(Boolean);
        const d = v('yearCycleStart').trim() ? HT.readDate(v('yearCycleStart').trim()) : null;
        const label = v('yearCycleLabel').trim();
        if (names.length < 2) problems.push('명칭을 둘 이상 적어 주세요 (쉼표로 가름).');
        if (!d || isNaN(d.t) || Math.floor(d.t + 1e-9) === 0) problems.push('기준 연도(첫 명칭이 붙는 해)를 적어 주세요 — 0년은 없습니다.');
        if (!problems.length) draft.yearCycle = Object.assign({ names, start: Math.floor(d.t + 1e-9) }, label ? { label } : {});
      }
      showInfoProblems(problems);
      if (!problems.length) HT.syncYearCycles(draft, 'cycle'); // 「주기」 표의 전체 줄을 따라 맞춤(5단계 과제 6)
      if (!problems.length) commitSoon();
    }
    const clHTML = () =>
      arr(draft.changelog).map((c, i) => `<li data-cl="${i}"><input data-cl-f="version" class="is-ver" value="${esc(c.version)}" aria-label="판"><input data-cl-f="date" class="is-date" value="${esc(c.date || '')}" aria-label="날짜 (YYYY-MM-DD)"><input data-cl-f="note" value="${esc(c.note || '')}" maxlength="${L.noteLen}" aria-label="고친 것"><button type="button" data-cl-del aria-label="이 줄 빼기">✕</button></li>`).join('') ||
      '<li class="hint">아직 없음 — 반영하면 한 줄씩 저절로 쌓입니다.</li>';
    async function openInfo() {
      if (!ready()) return;
      if (!(await ctx.leaveEditor('이동'))) return; // 팩 정보는 편집 창 밑(같은 오른쪽 창) — 편집 창을 먼저 닫음
      ctx.closeDetail();
      selectItems([]);
      renderInfo();
      shell.showProps('info');
      const f = infoEl().querySelector('[name="name"]');
      if (f) f.focus();
    }
    function renderInfo() {
      const el = infoEl();
      if (!el || !draft) return;
      const cats = HT.PACK_CATEGORIES.map(c => `<option value="${c.id}"${draft.category === c.id ? ' selected' : ''}>${esc(c.name)} — ${esc(c.hint)}</option>`).join('');
      el.innerHTML = `<div class="ep-head mk-info-head"><h2>팩 정보</h2><button type="button" class="icon-btn" data-info="close" aria-label="닫기">✕</button></div>
        <div class="mk-info">
          <section><h3>DLC 관리에서 이렇게 보입니다</h3><div class="mk-info-card" data-info-card></div></section>
          <section><h3>표지 <small>16:9 — 없으면 시대 막대로 저절로 그립니다</small></h3>
            <div class="mk-cover-row"><div class="pk-cover" data-info-cover></div>
              <div class="mk-cover-btns"><button type="button" class="btn btn-sm" data-info="cover-file">그림 고르기…</button><button type="button" class="btn btn-sm" data-info="cover-shot">📷 지금 연표를 표지로</button><button type="button" class="btn btn-sm" data-info="cover-auto">자동 표지로</button></div></div></section>
          <label class="field"><span>이름 *</span><input name="name" value="${esc(draft.name)}" autocomplete="off"></label>
          <label class="field"><span>id *</span><input name="id" value="${esc(draft.id)}" autocomplete="off" spellcheck="false"></label>
          <p class="editor-note is-warn" data-info-idnote hidden></p>
          <label class="field"><span>판 <small>(반영하면 저절로 올라감)</small></span><input name="version" value="${esc(draft.version)}" autocomplete="off"></label>
          <label class="field"><span>분류</span><select name="category"><option value="">분류 없음</option>${cats}</select></label>
          <label class="field"><span>만든 사람</span><input name="author" value="${esc(draft.author || '')}" autocomplete="off"></label>
          <div class="field"><span>처음 만든 날 · 마지막 반영한 날 <small>(YYYY-MM-DD — 반영하면 저절로 적힘)</small></span><div class="mk-dates"><input name="created" value="${esc(draft.created || '')}" aria-label="처음 만든 날" autocomplete="off" spellcheck="false"><input name="updated" value="${esc(draft.updated || '')}" aria-label="마지막 반영한 날" autocomplete="off" spellcheck="false"></div></div>
          <div class="field"><span>태그 <small>(${L.tags}개까지 · ${L.tagLen}자까지 — 치고 Enter)</small></span><div class="mk-chips" data-info-tags>${tagsHTML()}</div></div>
          <label class="field"><span>짧은 소개 <small data-info-count>${(draft.summary || '').length}/${L.summary}</small></span><textarea name="summary" rows="2" maxlength="${L.summary}">${esc(draft.summary || '')}</textarea></label>
          <label class="field"><span>설명</span><textarea name="description" rows="4">${esc(draft.description || '')}</textarea></label>
          <div class="field"><span>볼거리 <small>(${L.highlights}줄까지 — ⋮⋮를 끌어 차례)</small></span><ol class="mk-rows" data-info-hl>${arr(draft.highlights).map(hlRow).join('')}</ol><button type="button" class="btn btn-sm" data-info="hl-add">＋ 줄 더하기</button></div>
          <div class="field"><span>관계</span><div class="mk-rels" data-info-rels>${relsHTML()}</div></div>
          ${leaderWordsHTML()}
          ${cycleHTML()}
          <datalist id="mkPackIds">${state.packs.filter(p => p.id !== draft.id).map(p => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</datalist>
          <div class="field"><span>판 기록</span>
            <div class="mk-cl-next"><b data-info-nextver></b><input data-info-next value="${esc(draft._nextNote || '')}" maxlength="${L.noteLen}" aria-label="다음 반영 때 판 기록에 남길 말 — 비우면 고친 것 요약" autocomplete="off"><small data-info-nextauto></small></div>
            <ol class="mk-cl" data-info-cl>${clHTML()}</ol><button type="button" class="btn btn-sm" data-info="cl-add">＋ 판 기록 줄</button></div>
          <p class="hint" data-info-contents></p>
          <ul class="problems" data-info-problems hidden></ul>
        </div>`;
      paintInfoCard();
    }
    /** 칸이 아닌 것만 새로: 카드 미리보기 · 표지 · 담긴 것 · 다음 반영 줄 · 자동 표지 단추 */
    function paintInfoCard() {
      const el = infoEl();
      if (!el || !draft || !el.querySelector('[data-info-card]')) return;
      const pack = packNow();
      el.querySelector('[data-info-card]').innerHTML = HT.packCard.html(pack, { hint: '연표의 DLC 관리 카드' });
      el.querySelector('[data-info-cover]').innerHTML = HT.packCard.coverHTML(pack);
      el.querySelector('[data-info-contents]').textContent = `담긴 것: ${HT.packCard.contentsText(pack)}`;
      const nv = nextVer();
      el.querySelector('[data-info-nextver]').textContent = nv ? `다음 반영 · v${nv}` : '다음 반영 (고친 것이 없음)';
      el.querySelector('[data-info-nextauto]').textContent = `비우면: ${kit.changelogNote(changes) || '고친 것 요약'}`;
      el.querySelector('[data-info="cover-auto"]').disabled = !draft.cover;
    }
    function showInfoProblems(list) {
      const box = infoEl().querySelector('[data-info-problems]');
      box.innerHTML = list.map(p => `<li>${esc(p)}</li>`).join('');
      box.hidden = !list.length;
    }
    const setOpt = (k, v) => (v ? (draft[k] = v) : delete draft[k]); // 새 칸 · 작업본에만 두는 칸은 비면 지움 (적은 것만 파일로)
    const hlValues = () => [...infoEl().querySelectorAll('[data-hl-text]')].map(i => i.value.trim()).filter(Boolean).slice(0, L.highlights);
    const saveHl = () => setOpt('highlights', hlValues().length ? hlValues() : null);
    function syncIdNote(id) {
      const note = infoEl().querySelector('[data-info-idnote]');
      note.hidden = !id || id === draft.id;
      if (!note.hidden)
        note.textContent = `id를 바꾸면 [반영]할 때 «${id}»라는 새 DLC로 설치됩니다.${installedPack() ? ` 설치돼 있던 «${draft.id}»는 그대로 남으니, 연표에서 둘 다 켜져 있으면 둘 다 보입니다 — 연표의 DLC 관리에서 끄거나 지우세요.` : ''} 이 DLC 안의 항목 · 문서 · 덮어쓰기 · 불러온 팩은 새 id를 따라갑니다. (칸을 떠나면 바뀜)`;
    }
    function onInfoInput(e) {
      const t = e.target;
      const problems = [];
      if (t.name === 'name') t.value.trim() ? (draft.name = t.value.trim()) : problems.push('이름을 적어 주세요.');
      else if (t.name === 'version') t.value.trim() ? (draft.version = t.value.trim()) : problems.push('판을 적어 주세요.');
      else if (t.name === 'author' || t.name === 'description') draft[t.name] = t.value.trim(); // 있던 칸 — 빈 글로 둠(옛 DLC 정보 창과 같게)
      else if (t.name === 'created' || t.name === 'updated') {
        /* 처음 만든 날 · 마지막 반영한 날 — YYYY-MM-DD만 (비우면 지움 · 다음 반영 때 다시 적힘) */
        const v = t.value.trim();
        if (v && !/^\d{4}-\d{2}-\d{2}$/.test(v)) problems.push(`${t.name === 'created' ? '처음 만든 날' : '마지막 반영한 날'}은 YYYY-MM-DD 꼴로 적어 주세요.`);
        else setOpt(t.name, v);
      } else if (t.dataset.relName != null) {
        const type = t.closest('[data-rel]').dataset.rel;
        const r = arr(draft.relations).find(x => x && x.type === type && x.id === t.dataset.relName);
        if (!r) return;
        if (t.value.trim()) r.name = t.value.trim();
        else delete r.name;
      }
      else if (t.name === 'summary') {
        setOpt('summary', t.value.trim());
        infoEl().querySelector('[data-info-count]').textContent = `${t.value.length}/${L.summary}`;
      } else if (t.name === 'id') return syncIdNote(t.value.trim());
      else if ('hlText' in t.dataset) saveHl();
      else if (t.dataset.clF) {
        const c = arr(draft.changelog)[Number(t.closest('[data-cl]').dataset.cl)];
        if (c) c[t.dataset.clF] = t.value.trim();
      } else if ('infoNext' in t.dataset) setOpt('_nextNote', t.value.trim());
      else if (/^yearCycle/.test(t.name || '')) return saveCycle(); // 날짜 칸의 간지 설정 (형식 버전 3)
      else if (/^leaderLabel-(temple|title|given)$/.test(t.name || '')) kit.nestSet(draft, ['leaderLabels', t.name.slice('leaderLabel-'.length)], t.value); // 지도자 표기 낱말(6단계 D3) — 비운 칸은 지움
      else return;
      showInfoProblems(problems);
      if (!problems.length) commitSoon();
    }
    /** id 바꾸기(칸을 떠날 때 · Enter): 편집 창을 먼저 닫고, 항목 · 문서 · 덮어쓰기 · 불러온 팩 기록이 새 id를 따라감 */
    async function renameTo(id) {
      if (!draft || id === draft.id) return;
      const problems = [];
      if (!HT.ID_RE.test(id) || id === HT.USER_PACK.id) problems.push('id는 영문·숫자·- _ . 만 쓸 수 있습니다.');
      else if (state.packs.some(p => p.id === id)) problems.push(`«${id}» id의 DLC가 이미 있습니다 — 반영하면 그 DLC를 덮어쓰게 되니 다른 id를 적어 주세요.`);
      showInfoProblems(problems);
      if (problems.length) return;
      if (!(await ctx.leaveEditor('바꾸기'))) return;
      flushSoon();
      const old = draft.id;
      kit.renameDlc(draft, id);
      refsAll = kit.moveRefs(refsAll, old, id);
      saveRefs();
      commit();
      ctx.refresh();
      renderInfo();
      HT.toast(`id를 «${id}»(으)로 바꿨습니다.`, 'ok');
    }
    const readAsDataURL = file =>
      new Promise((ok, no) => {
        const r = new FileReader();
        r.onload = () => ok(r.result);
        r.onerror = () => no(r.error);
        r.readAsDataURL(file);
      });
    /** 표지 넣기 (설계 2-6): 16:9 · 1600×900 이하로 줄여 작업본에 — 저장소가 모자라면 되돌림 */
    async function setCover(getSrc, what, opts = {}) {
      try {
        const src = await getSrc();
        if (!src) return;
        const fitted = await HT.packFile.fitCover(src, 1600, 900, opts);
        if (typeof fitted !== 'string' || fitted.length > HT.PACK_LIMITS.cover) return HT.toast('표지 그림이 너무 큽니다 — 더 작은 그림을 고르세요.', 'error');
        const old = draft.cover;
        draft.cover = fitted;
        if (!commit()) {
          setOpt('cover', old);
          commit();
          return;
        }
        ctx.refresh();
        paintInfoCard();
        HT.toast(`${what} 표지로 넣었습니다.`, 'ok');
      } catch (err) {
        HT.toast(`표지를 넣지 못했습니다 — ${(err && err.message) || err}`, 'error');
      }
    }
    function onInfoClick(e) {
      const b = e.target.closest('button');
      if (!b) return;
      const act = b.dataset.info;
      if (act === 'close') return shell.showProps('empty');
      if (act === 'cover-file')
        return setCover(async () => {
          const [f] = await HT.pickFiles('image/png,image/jpeg,image/webp');
          if (!f) return null;
          if (!/^image\/(png|jpeg|webp)$/.test(f.type)) throw new Error('png · jpg · webp 그림만 넣을 수 있습니다.');
          return readAsDataURL(f);
        }, '그림을');
      if (act === 'cover-shot') return setCover(() => `data:image/svg+xml;charset=utf-8,${encodeURIComponent(timeline.toSVG({ width: 1600 }))}`, '지금 연표를', { top: true });
      if (act === 'cover-auto') {
        delete draft.cover;
        commit();
        ctx.refresh();
        return paintInfoCard();
      }
      if (act === 'hl-add') {
        const list = infoEl().querySelector('[data-info-hl]');
        if (list.children.length >= L.highlights) return HT.toast(`볼거리는 ${L.highlights}줄까지입니다.`);
        list.insertAdjacentHTML('beforeend', hlRow('', list.children.length));
        return list.lastElementChild.querySelector('input').focus();
      }
      if ('hlDel' in b.dataset) {
        b.closest('li').remove();
        saveHl();
        return commitSoon();
      }
      if (b.dataset.tagDel != null) {
        const tags = arr(draft.tags).filter((t, i) => i !== Number(b.dataset.tagDel));
        setOpt('tags', tags.length ? tags : null);
        infoEl().querySelector('[data-info-tags]').innerHTML = tagsHTML();
        return commitSoon();
      }
      if (b.dataset.relDel != null) {
        const type = b.closest('[data-rel]').dataset.rel;
        if (type === 'requires') draft.requires = arr(draft.requires).filter(id => id !== b.dataset.relDel);
        else {
          const rest = arr(draft.relations).filter(r => !(r && r.type === type && r.id === b.dataset.relDel));
          setOpt('relations', rest.length ? rest : null);
        }
        infoEl().querySelector('[data-info-rels]').innerHTML = relsHTML();
        return commitSoon();
      }
      if (act === 'cl-add') {
        /* 판 기록 줄 손으로 더하기(2026-10-23 — 전역 확대 ⑩): 새것이 앞 — 지금 판 · 오늘 날짜 · 빈 글 */
        const list = arr(draft.changelog);
        if (list.length >= L.changelog) return HT.toast(`판 기록은 ${L.changelog}줄까지입니다.`);
        draft.changelog = [{ version: draft.version || '', date: new Date().toISOString().slice(0, 10), note: '' }].concat(list);
        infoEl().querySelector('[data-info-cl]').innerHTML = clHTML();
        const first = infoEl().querySelector('[data-info-cl] li input[data-cl-f="note"]');
        if (first) first.focus();
        return commitSoon();
      }
      if ('clDel' in b.dataset) {
        const i = Number(b.closest('[data-cl]').dataset.cl);
        const list = arr(draft.changelog).filter((c, k) => k !== i);
        setOpt('changelog', list.length ? list : null);
        infoEl().querySelector('[data-info-cl]').innerHTML = clHTML();
        return commitSoon();
      }
    }
    function onInfoKey(e) {
      const t = e.target;
      if (e.key === 'Enter' && !e.isComposing) {
        if ('tagInput' in t.dataset) {
          e.preventDefault();
          const r = kit.addTag(draft.tags, t.value);
          showInfoProblems(r.problem ? [r.problem] : []);
          if (r.problem) return;
          setOpt('tags', r.tags.length ? r.tags : null);
          const box = infoEl().querySelector('[data-info-tags]');
          box.innerHTML = tagsHTML();
          const next = box.querySelector('[data-tag-input]');
          if (next) next.focus();
          return commitSoon();
        }
        if ('relInput' in t.dataset) {
          e.preventDefault();
          const type = t.closest('[data-rel]').dataset.rel;
          const problem = kit.addRelation(draft, type, t.value, state.packs);
          showInfoProblems(problem ? [problem] : []);
          if (problem) return;
          infoEl().querySelector('[data-info-rels]').innerHTML = relsHTML();
          const again = infoEl().querySelector(`[data-rel="${type}"] [data-rel-input]`);
          if (again) again.focus();
          return commitSoon();
        }
        if (t.name === 'id') return t.blur(); // 칸을 떠나면(change) 바뀜
      }
      if (e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown') && 'hlText' in t.dataset) {
        e.preventDefault();
        const li = t.closest('li');
        const to = e.key === 'ArrowUp' ? li.previousElementSibling : li.nextElementSibling;
        if (!to) return;
        li.parentNode.insertBefore(li, e.key === 'ArrowUp' ? to : to.nextSibling);
        t.focus();
        saveHl();
        commitSoon();
      }
    }
    /** 볼거리 줄을 ⋮⋮로 끌어 차례 바꾸기 (포인터를 붙잡음 — 놓으면 저장) */
    function dragHighlight(handle, e0) {
      const li = handle.closest('li');
      const list = li.parentNode;
      handle.setPointerCapture(e0.pointerId);
      li.classList.add('is-dragging');
      const move = e => {
        const after = [...list.children].filter(x => x !== li).find(x => {
          const r = x.getBoundingClientRect();
          return e.clientY < r.top + r.height / 2;
        });
        list.insertBefore(li, after || null);
      };
      const up = () => {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', up);
        handle.removeEventListener('pointercancel', up);
        li.classList.remove('is-dragging');
        saveHl();
        commitSoon();
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', up);
      handle.addEventListener('pointercancel', up);
      e0.preventDefault();
    }

    /* ---------- 바탕 자료 창: 트랙 · 분류 · 민족 · 시대 구분 · 지위 · 가문 · 대범위 (열 설정표 — HT.makerKit.BASE_TABLES) ---------- */
    const baseEl = $('#mkBaseWin');
    const baseBody = $('#mkBaseBody');
    let baseTab = str(winUi.baseTab) || 'tracks';
    let baseFlash = -1; // 검사에서 넘어온 줄 (잠깐 비춤)
    const openNames = new Set(); // 이름 상자를 펼쳐 둔 줄 "목록:id" (형식 버전 3 — 다시 그려도 펼친 채로)
    /* 이름 상자에서 읽지 못한 줄(글이 없음 · 쓴 기간을 읽을 수 없음 · 그친 때가 앞섬)이 든 줄: "DLC id:목록:id" → { rows: 친 글 그대로, problems, valid: 저장한 이름 목록의 글 }.
       바탕 자료 표에는 저장 단계가 없어 읽은 줄만 작업본에 들어가므로, 친 글은 여기 두었다가 다시 그려도 그대로 보이고 줄 아래에 까닭을 붉게 보입니다(작업본의 이름 목록이 그새 바뀌었으면 버림) */
    const pendingNames = new Map();
    const namesKey = (list, x) => `${draft ? draft.id : ''}:${list}:${x.id}`;
    /** 이름 상자(nb)에 읽지 못한 줄의 표시 — 그 줄의 칸에 aria-invalid, 상자 아래에 까닭 글 */
    const markNames = (nb, problems) => {
      const bad = new Set(problems.map(m => Number((/이름 (\d+)번째 줄/.exec(m) || [])[1]) - 1));
      [...nb.querySelectorAll('[data-names-rows] > .name-row')].forEach((row, i) => {
        for (const inp of row.querySelectorAll('input')) {
          if (bad.has(i)) inp.setAttribute('aria-invalid', 'true');
          else inp.removeAttribute('aria-invalid');
        }
      });
      let note = nb.querySelector(':scope > .mk-names-problem');
      if (!problems.length) {
        if (note) note.remove();
        return;
      }
      if (!note) {
        note = document.createElement('p');
        note.className = 'mk-names-problem';
        note.setAttribute('role', 'alert');
        nb.append(note);
      }
      note.textContent = `${problems.join(' · ')} — 이 줄은 아직 저장되지 않았습니다(고치면 저장됩니다).`;
    };
    /* 처음 자리(기억한 자리가 없을 때): 바탕 자료는 왼쪽 */
    const baseWin = makeWin(baseEl, 'base', { w: 720, h: 560, x: () => 24, render: () => renderBase() });
    const tableOf = list => kit.BASE_TABLES[list] || null;
    const isRefCol = (t, col) => col.type === 'id' || !!(t.refs && t.refs[col.key]);
    /** 표의 줄들 — 목록 표는 작업본의 목록, 객체 표(영토 — t.object)는 그 객체 하나를 줄 하나로 (2026-10-23) */
    const rowsAt = list => {
      const t = tableOf(list);
      if (!draft) return [];
      return t && t.object ? (draft[list] && typeof draft[list] === 'object' && !Array.isArray(draft[list]) ? [draft[list]] : []) : arr(draft[list]);
    };
    const openSubs = new Set(); // 하위 표(지도의 구역 · 장면)를 펼쳐 둔 줄 "목록:id:하위" — 다시 그려도 펼친 채로
    /** data URL의 크기 글(어림) */
    const dataSize = src => {
      const n = Math.max(0, Math.round(((String(src).length - String(src).indexOf(',') - 1) * 3) / 4));
      return n >= 1048576 ? `${(n / 1048576).toFixed(1)}MB` : `${Math.max(1, Math.round(n / 1024))}KB`;
    };
    const fileToDataURL = file =>
      new Promise((ok, no) => {
        const r = new FileReader();
        r.onload = () => ok(String(r.result));
        r.onerror = () => no(r.error);
        r.readAsDataURL(file);
      });
    /** 파일 칸에 파일 담기: 그림은 긴 변 1600px로 줄이고(HT.namu.fitImage), 글꼴은 확장자대로 data:font/… 머리를 맞춥니다. 한도(col.limit)를 넘으면 알리고 담지 않음. 돌려주는 값: 담았는지 */
    async function pickInto(col, x) {
      const [f] = (await HT.pickFiles(col.accept)) || [];
      if (!f) return false;
      let src = await fileToDataURL(f);
      if (col.image) {
        if (!/^image\/(png|jpeg|webp)$/.test(f.type)) {
          HT.toast('png · jpg · webp 그림만 넣을 수 있습니다.', 'error');
          return false;
        }
        const fit = await HT.namu.fitImage(src, 1600, { force: src.length > 300000 || !/^data:image\/(png|jpeg|webp);base64,/.test(src) });
        src = fit.src;
      } else {
        const ext = (String(f.name).match(/\.(woff2|woff|ttf|otf)$/i) || [])[1];
        if (!ext) {
          HT.toast('woff2 · woff · ttf · otf 글꼴 파일만 넣을 수 있습니다.', 'error');
          return false;
        }
        src = src.replace(/^data:[^;,]*/, `data:font/${ext.toLowerCase()}`);
      }
      if (col.limit && src.length > col.limit) {
        HT.toast(`«${f.name}»이(가) 너무 큽니다 — 한도(${col.limit.toLocaleString('ko-KR')}자 · 약 ${dataSize('data:,' + 'x'.repeat(col.limit))})를 넘습니다.`, 'error');
        return false;
      }
      x[col.key] = src;
      return true;
    }
    /** 칸 하나를 작업본에 — JSON 칸은 읽히는 글만 적고(잘못된 글은 칸을 붉게 두고 적지 않음), 나머지는 writeCol. 돌려주는 값: 적었는지 */
    const writeField = (col, x, input) => {
      if (col.type === 'json') {
        const text = input.value.trim();
        if (!text) {
          delete x[col.key];
          input.removeAttribute('aria-invalid');
          return true;
        }
        try {
          x[col.key] = JSON.parse(text);
          input.removeAttribute('aria-invalid');
          return true;
        } catch {
          input.setAttribute('aria-invalid', 'true');
          return false;
        }
      }
      writeCol(col, x, col.type === 'check' ? input.checked : input.value);
      return true;
    };
    /** 이 목록의 새 줄에 쓸 id — 작업본과 연표(다른 DLC · 기본팩)에 없는 것으로 (같은 id면 한 줄로 합쳐지므로) */
    const freshId = (list, t) => kit.uniqueId(t.idBase || 'x', new Set(arr(draft[list]).map(x => x && x.id).concat(arr(others).flatMap(p => arr(p[list]).map(x => x.id)))));
    /** 다른 DLC · 기본팩에만 있는 정의 (가져오기 후보 [{ def, packName, builtin }]) — 같은 id는 먼저 놓인 것 하나. 프로그램에 든 정의(t.builtin — 기본 지위 · builtin: true)는 맨 끝에 */
    function importable(list) {
      const have = new Set(arr(draft[list]).map(x => x && x.id));
      const out = [];
      const t = tableOf(list);
      const sources = arr(others).map(p => [arr(p[list]), p.name, false]).concat(t && t.builtin ? [[arr(t.builtin()), '기본', true]] : []);
      for (const [defs, packName, builtin] of sources) {
        for (const def of defs) {
          if (!def || !def.id || have.has(def.id)) continue;
          have.add(def.id);
          out.push({ def, packName, builtin });
        }
      }
      return out;
    }
    const swatch = (color, attrs = '') => `<button type="button" class="sw mk-sw" style="--c:${esc(color)}"${attrs}></button>`;
    /** 고르기 칸의 선택지 — 목록이거나 (작업본, 모델)을 받는 함수(트랙의 문화권 — 켠 DLC · 작업본이 만든 문화권까지) */
    const colOptions = col => (typeof col.options === 'function' ? col.options(draft, state.model) : col.options);
    /* over: 이 칸만의 { tip 도움말(열의 것 대신), invalid 빠지는 줄 표시 } — 이름 칸에 */
    function baseCell(t, col, x, over = null) {
      if (col.type === 'color') return `<td class="mk-c-color">${swatch(x.color ? HT.pastel(x.color) : t.autoColor ? t.autoColor(x) : '#8b8f98', ' data-act="color" title="색 고르기" aria-label="색 고르기"')}</td>`;
      const v = col.nest ? kit.nestGet(x, col.nest) : col.type === 'json' ? (x[col.key] == null ? '' : JSON.stringify(x[col.key])) : (col.type === 'list' || col.type === 'pair') && Array.isArray(x[col.key]) ? x[col.key].join(', ') : x[col.key]; // pair: 지명의 좌표 [x, y] (형식 버전 3) · json: 깊은 칸은 JSON 글로 (지도 · 영토)
      const tip = (over && over.tip) || col.title;
      if (col.type === 'file') {
        /* 파일 칸(지도의 그림 · 글꼴 파일): 담긴 상태(그림이면 작은 그림 · 크기)와 [파일] · 비움 단추 — 값은 data URL (2026-10-23) */
        const src = str(x[col.key]);
        const state = src ? `${col.image && /^data:image\//.test(src) ? `<img class="mk-file-thumb" src="${esc(src)}" alt="">` : ''}<span>담김 · ${esc(dataSize(src))}</span>` : '<span class="mk-file-none">없음</span>';
        return `<td class="mk-c-file"><span class="mk-file-state">${state}</span><button type="button" class="btn btn-sm" data-act="file" data-key="${esc(col.key)}"${tip ? ` title="${esc(tip)}"` : ''}>파일</button>${src ? `<button type="button" class="icon-btn" data-act="file-clear" data-key="${esc(col.key)}" title="비움" aria-label="비움">✕</button>` : ''}</td>`;
      }
      const attrs = `name="${esc(col.key)}" value="${esc(v ?? '')}" aria-label="${esc(col.label)}"${col.list ? ` list="${esc(col.list)}"` : ''}${tip ? ` title="${esc(tip)}"` : ''}${over && over.invalid ? ' aria-invalid="true"' : ''}`;
      if (col.type === 'number') return `<td class="mk-c-num"><input type="number" step="1" ${attrs}></td>`;
      /* 가문의 구분 · 민족을 비우면 모델이 짐작한 값을 칸 옆 딱지로 (D1 — 입력 칸의 회색 예시 글이 아님) */
      const guess = !str(v) && t === kit.BASE_TABLES.houses && (col.key === 'track' || col.key === 'people') && HT.makerKin ? HT.makerKin.houseGuess(state.model, x.id, col.key) : '';
      const tag = guess ? `<span class="mk-guess" title="비워 두면 이 값으로 봅니다">짐작: ${esc(guess)}</span>` : '';
      if (col.type === 'check') return `<td class="mk-c-check"><input type="checkbox" name="${esc(col.key)}" aria-label="${esc(col.label)}"${tip ? ` title="${esc(tip)}"` : ''}${x[col.key] === true ? ' checked' : ''}></td>`; // 켜고 끄는 칸(주제 사전의 '렌즈에서 숨김' — 형식 3): 켜면 true, 끄면 칸을 지움
      if (col.type === 'select')
        /* 고르기 칸 (형식 버전 3 — 민족의 배열 기준): col.options [{ id, name, hint }] · 첫 줄 '' = 적지 않음. 값은 input 이벤트로 바로 적힘(writeCol의 빈 글 → 지움) */
        return `<td class="mk-c-text"><select name="${esc(col.key)}" aria-label="${esc(col.label)}"${tip ? ` title="${esc(tip)}"` : ''} style="width:100%;height:30px;font-size:13px">${colOptions(col).map(o => `<option value="${esc(o.id)}"${(v ?? '') === o.id ? ' selected' : ''}${o.hint ? ` title="${esc(o.hint)}"` : ''}>${esc(o.name)}</option>`).join('')}${v && !colOptions(col).some(o => o.id === v) ? `<option value="${esc(v)}" selected>${esc(v)} (모르는 값)</option>` : ''}</select></td>`;
      if (col.type === 'track') {
        const tracks = arr(state.model && state.model.tracks);
        return `<td class="mk-c-text"><select name="${esc(col.key)}" aria-label="${esc(col.label)}"${tip ? ` title="${esc(tip)}"` : ''}><option value=""${v ? '' : ' selected'}>비움</option>${tracks.map(tr => `<option value="${esc(tr.id)}"${tr.id === v ? ' selected' : ''}>${esc(tr.name)}</option>`).join('')}${v && !tracks.some(tr => tr.id === v) ? `<option value="${esc(v)}" selected>${esc(v)}</option>` : ''}</select>${tag}</td>`;
      }
      return `<td class="mk-c-${col.type === 'id' ? 'id' : col.type === 'json' ? 'json' : 'text'}"><input ${attrs}${col.type === 'id' || col.type === 'json' || col.person ? ' spellcheck="false" autocomplete="off"' : ''}${col.person ? ' data-person-col' : ''}>${tag}</td>`;
    }
    /** 같은 id가 켜져 있는 다른 팩에도 있는 줄(kit.shadowOf)의 도움말 — 그 팩이 켜져 있는 동안 연표에는 그쪽 정의가 쓰입니다 */
    const shadowText = (t, list, pack, x) => {
      const def = arr(pack[list]).find(d => d && d.id === x.id) || {};
      return `켜져 있는 «${pack.name}»에도 같은 id의 ${t.word} 정의(이름 «${def.name || def.id}»)가 있어, 그 DLC가 켜져 있는 동안 연표에는 그쪽 정의가 쓰입니다 — 이 줄에서 고친 것은 그동안 쓰이지 않고, 이름을 바꿔도 그 이름으로 적은 곳을 따라 바꾸지 않습니다. 이 DLC만의 것으로 쓰려면 id를 바꾸세요.`;
    };
    function tableTabHTML(list, t) {
      const byName = !!(t.refs && t.refs.name); // 이름으로도 가리키는 사전(민족 · 지위 · 가문) — 이름 바꾸기가 따라가므로, 다른 팩의 정의가 먼저 쓰이는 줄을 알립니다
      /* 하위 표(지도의 구역 · 장면 — t.subs): 줄 끝 단추로 줄 아래에 펼치는 표 (이름 상자와 같은 길 · 2026-10-23) */
      const subKey = (x, s) => `${list}:${x.id}:${s.key}`;
      const subBox = (x, i, s) => {
        const items = arr(x[s.key]);
        return `<tr class="mk-names-sub" data-sub-of="${i}"><td colspan="${t.cols.length + 2}"><div class="names-box mk-sub-box" data-base-sub="${i}" data-sub-key="${esc(s.key)}"><b class="mk-sub-cap">${esc(s.word)} ${items.length}</b>
          <div class="mk-table-wrap"><table class="mk-base-table is-sub"><thead><tr>${s.cols.map(c => `<th>${esc(c.label)}</th>`).join('')}<th></th></tr></thead><tbody>${items
            .map((r, j) => `<tr data-j="${j}">${s.cols.map(c => baseCell(t, c, r && typeof r === 'object' ? r : {})).join('')}<td class="mk-acts"><button type="button" class="icon-btn" data-sub-del title="삭제" aria-label="삭제">🗑</button></td></tr>`)
            .join('')}</tbody></table>${items.length ? '' : `<p class="mk-empty">${esc(s.word)} 없음</p>`}</div>
          <div class="toolbar"><button type="button" class="btn btn-sm" data-sub-add>＋ ${esc(s.word)} 추가</button></div></div></td></tr>`;
      };
      const rows = rowsAt(list)
        .map((x, i) => {
          const subBtns = (t.subs || [])
            .map(s => {
              const n = arr(x[s.key]).length;
              return `<button type="button" class="icon-btn mk-names-btn mk-sub-btn${n ? ' has-names' : ''}" data-act="sub" data-sub="${esc(s.key)}" aria-expanded="${openSubs.has(subKey(x, s))}" title="${esc(`${s.word}${n ? ` ${n}개` : ''} — 누르면 줄 아래에 펼칩니다`)}" aria-label="${esc(s.word)}">${esc(s.word.slice(0, 2))}${n ? `<small>${n}</small>` : ''}</button>`;
            })
            .join('');
          const subRows = (t.subs || []).filter(s => openSubs.has(subKey(x, s))).map(s => subBox(x, i, s)).join('');
          const users = kit.findUsers(draft, t, x);
          const names = users.slice(0, 12).map(u => u.item.title || u.item.name || u.item.target || u.item.id).filter(Boolean);
          const shadow = byName ? kit.shadowOf(others, list, x.id) : null;
          const shadowTip = shadow ? shadowText(t, list, shadow, x) : '';
          const drop = t.dropped ? t.dropped(x) : '';
          const nameOver = { tip: drop || shadowTip, invalid: !!drop };
          const nameKey = t.cols.some(c => c.key === 'name') ? 'name' : (t.cols.find(c => c.type === 'text') || {}).key; // 이름 열이 없는 표(글꼴)는 첫 글 칸에 빠지는 줄 표시
          /* 이름 목록(형식 버전 3 — t.names): 줄 끝 文 단추로 줄 아래에 펼치는 상자(이름 줄 — 편집 창의 이름 칸과 같은 줄 HT.nameRowHTML) */
          const nn = t.names ? arr(x.names).length : 0;
          const open = !!t.names && openNames.has(`${list}:${x.id}`);
          const namesBtn = t.names ? `<button type="button" class="icon-btn mk-names-btn${nn ? ' has-names' : ''}" data-act="names" aria-expanded="${open}" title="${esc(`이름(원어 등)${nn ? ` ${nn}개` : ''} — 누르면 줄 아래에 펼칩니다`)}" aria-label="이름(원어 등)">文${nn ? `<small>${nn}</small>` : ''}</button>` : '';
          const pend = open ? pendingNames.get(namesKey(list, x)) : null;
          const shownNames = pend && pend.valid === JSON.stringify(arr(x.names)) ? pend.rows.map(r => HT.nameRowHTML(r)).join('') : HT.namesRowsHTML(x.names); // 읽지 못한 줄이 있던 상자는 친 글 그대로
          const namesRow = open ? `<tr class="mk-names-sub" data-names-of="${i}"><td colspan="${t.cols.length + 2}"><div class="names-box" data-base-names="${i}"><div class="alt-rows" data-names-rows>${shownNames}</div><div class="toolbar"><button type="button" class="btn btn-sm" data-name-add>＋ 이름 추가</button></div></div></td></tr>` : '';
          return `<tr data-i="${i}"${i === baseFlash ? ' class="is-flash"' : ''}>${t.cols.map(col => baseCell(t, col, x, col.key === nameKey ? nameOver : null)).join('')}<td class="mk-use" title="${esc(names.join(', ') + (users.length > 12 ? ` …외 ${users.length - 12}` : ''))}">${esc(kit.usageText(users) || '—')}</td><td class="mk-acts">${
            shadow ? `<span class="mk-shadow-tag" title="${esc(shadowTip)}">다른 DLC 우선</span>` : ''
          }${namesBtn}${subBtns}${t.docPrefix ? '<button type="button" class="icon-btn" data-act="doc" title="문서" aria-label="문서">📄</button>' : ''}<button type="button" class="icon-btn" data-act="del" title="삭제" aria-label="삭제">🗑</button></td></tr>${namesRow}${subRows}`;
        })
        .join('');
      const cands = t.object ? [] : importable(list);
      const fromPack = cands.some(c => !c.builtin); // 다른 DLC · 기본팩에서 온 후보 (프로그램에 든 기본 지위가 아닌 것)
      return `<p class="lead">${esc(t.lead)}</p>
        <div class="toolbar">${t.object && rowsAt(list).length ? '' : `<button type="button" class="btn btn-primary btn-sm" data-act="add">＋ ${esc(t.word)} 추가</button>`}${t.tools ? t.tools(draft, esc) : ''}</div>
        <div class="mk-table-wrap"><table class="mk-base-table" data-list="${esc(list)}"><thead><tr>${t.cols.map(col => `<th>${esc(col.label)}</th>`).join('')}<th>쓰는 곳</th><th></th></tr></thead><tbody>${rows}</tbody></table>${
          rowsAt(list).length ? '' : `<p class="mk-empty">이 DLC에 든 ${esc(t.word)} 없음 — [＋ ${esc(t.word)} 추가]${t.object ? '로' : '나 아래의 가져오기로'}</p>`
        }</div>
        ${
          cands.length
            ? `<details class="mk-import"><summary>다른 DLC · 기본팩의 ${esc(t.word)} 가져오기 <small>${cands.length}개 · 같은 id로 이 DLC에 실어, 그 DLC 없이도 쓰이게</small></summary><p class="mk-import-note">${
                fromPack ? `다른 DLC · 기본팩에서 가져온 것은 그 팩이 켜져 있는 동안 그쪽 정의가 먼저 쓰여, 여기서 고쳐도 연표에 나오지 않습니다${byName ? "(표에 '다른 DLC 우선')" : ''}.` : ''
              }${cands.some(c => c.builtin) ? `${fromPack ? ' ' : ''}'기본'이라 적힌 것은 프로그램에 든 것이라, 가져와 고치면 이 DLC의 것이 쓰입니다.` : ''}</p><ul>${cands
                .map((c, j) => `<li>${t.cols.some(col => col.type === 'color') ? swatch(c.def.color ? HT.pastel(c.def.color) : t.autoColor ? t.autoColor(c.def) : '#8b8f98', ' disabled tabindex="-1" aria-hidden="true"') : ''}<b>${esc(c.def.name || c.def.id)}</b><small>${esc(c.def.id)} · ${esc(c.packName)}</small><button type="button" class="btn btn-sm" data-import="${j}">가져오기</button></li>`)
                .join('')}</ul>${cands.length > 1 ? `<div class="mk-import-all"><button type="button" class="btn btn-sm" data-import="all">${cands.length}개 모두 가져오기</button></div>` : ''}</details>`
            : ''
        }
        ${t.foot ? t.foot(draft, esc, state.model) : ''}${t.names ? HT.lineageListsHTML() : ''}`;
    }
    function formTabHTML(list, t) {
      const own = arr(draft[list]);
      const rows = own
        .map(raw => {
          const uid = `${draft.id}/${raw.id}`;
          const x = state.model.byUid.get(uid);
          const tr = x && x.track ? state.model.trackMap.get(x.track) : null;
          const users = t.uses ? t.uses(draft, raw) : null;
          const useCell = users ? `<td class="mk-use" title="${esc(users.map(u => u.item.name || u.item.epoch || u.item.id).filter(Boolean).join(', '))}">${esc(kit.usageText(users) || '—')}</td>` : '';
          return `<tr data-uid="${esc(uid)}" class="mk-row-link${x ? '' : ' is-bad'}" title="누르면 오른쪽 편집 창에서 고칩니다"><td class="mk-c-color">${swatch(x ? x.color : '#c9c2b8', ' disabled tabindex="-1" aria-hidden="true"')}</td><td><b>${esc(raw.name || raw.title || (x && x.name) || raw.epoch || raw.id)}</b></td><td class="mk-when">${x ? esc(HT.formatRange(x)) : '<span class="mk-bad">검사 오류 — 연표에 나오지 않음</span>'}</td><td>${esc(tr ? tr.name : raw.track ? raw.track : '공통')}</td>${useCell}<td class="mk-acts"><button type="button" class="icon-btn" data-act="doc" title="문서" aria-label="문서">📄</button><button type="button" class="icon-btn" data-act="del" title="삭제" aria-label="삭제">🗑</button></td></tr>`;
        })
        .join('');
      return `<p class="lead">${esc(t.lead)}</p>
        <div class="toolbar"><button type="button" class="btn btn-primary btn-sm" data-act="new">＋ ${esc(t.word)} 추가</button></div>
        <div class="mk-table-wrap"><table class="mk-base-table is-list"><thead><tr><th>색</th><th>이름</th><th>기간</th><th>트랙</th>${t.uses ? '<th>쓰는 곳</th>' : ''}<th></th></tr></thead><tbody>${rows}</tbody></table>${own.length ? '' : `<p class="mk-empty">이 DLC에 든 ${esc(t.word)} 없음</p>`}</div>`;
    }
    function renderBase() {
      const T = kit.BASE_TABLES;
      if (!T[baseTab]) baseTab = Object.keys(T)[0];
      $('#mkBaseTabs').innerHTML = Object.entries(T)
        .map(([k, t]) => `<button type="button" role="tab" data-base-tab="${esc(k)}" aria-selected="${k === baseTab}">${esc(t.word)}<small>${rowsAt(k).length}</small></button>`)
        .join('');
      const keep = baseBody.scrollTop;
      if (!draft) {
        baseBody.innerHTML = '<p class="hint">고칠 DLC를 먼저 고르세요.</p>';
        return;
      }
      const t = T[baseTab];
      baseBody.innerHTML = t.form ? formTabHTML(baseTab, t) : tableTabHTML(baseTab, t);
      for (const nb of baseBody.querySelectorAll('[data-base-names]')) {
        const x = arr(draft[baseTab])[Number(nb.dataset.baseNames)];
        const pend = x ? pendingNames.get(namesKey(baseTab, x)) : null;
        if (pend && pend.valid === JSON.stringify(arr(x.names))) markNames(nb, pend.problems);
      }
      baseBody.scrollTop = keep;
      if (baseFlash >= 0) {
        const tr = baseBody.querySelector('tr.is-flash');
        if (tr) tr.scrollIntoView({ block: 'nearest' });
        baseFlash = -1;
      }
    }
    /** 칸에서 나온 뒤(Tab · 다른 칸을 누름) 표를 다시 그립니다 — 초점이 옮겨 간 다음에, 그 줄 · 그 칸에 초점을 되돌려 줍니다 */
    const rerenderBase = () =>
      setTimeout(() => {
        const a = document.activeElement;
        const tr = a && baseBody.contains(a) ? a.closest('tr[data-i]') : null;
        const spot = tr ? { i: tr.dataset.i, name: a.name, act: a.dataset.act } : null;
        renderBase();
        if (!spot) return;
        const back = baseBody.querySelector(`tr[data-i="${spot.i}"] ${spot.name ? `[name="${CSS.escape(spot.name)}"]` : `[data-act="${CSS.escape(spot.act || '')}"]`}`);
        if (back) back.focus();
      }, 0);
    function openBase(tab, flashIndex = -1, tools = false) {
      if (!tools && shell && HT.makerGrid.words[tab]) return shell.openTable(tab);
      if (!ready()) return;
      if (tab && kit.BASE_TABLES[tab]) baseTab = tab;
      winUi.baseTab = baseTab;
      saveWinUi();
      baseFlash = flashIndex;
      baseBefore();
      baseWin.open();
    }
    /* 표의 맞춤 고리(「주기」 표 — HT.makerKit.BASE_TABLES[].before · after · 5단계 과제 6): before는 탭을 열 때(다른 입력의 값을 표로 — 바뀌었으면 저장), after는 표를 고쳐 저장하기 바로 전에(표의 값을 다른 입력으로) */
    const baseBefore = () => {
      const t = tableOf(baseTab);
      if (!draft || !t || !t.before || !t.before(draft, state.model)) return;
      commit();
      ctx.refresh();
    };
    const baseAfter = () => {
      const t = tableOf(baseTab);
      if (draft && t && t.after) t.after(draft, state.model);
    };
    /* 칸을 칠 때마다 작업본을 고치고, 화면(연표)은 잠깐 쉬었다가 한 번에 — 타자 중에 연표가 매번 다시 지어지지 않게 */
    let soonTimer = 0;
    const flushSoon = () => {
      if (!soonTimer) return;
      clearTimeout(soonTimer);
      soonTimer = 0;
      baseAfter();
      commit();
      ctx.refresh();
    };
    const commitSoon = () => {
      clearTimeout(soonTimer);
      soonTimer = setTimeout(() => {
        soonTimer = 0;
        baseAfter();
        commit();
        ctx.refresh();
      }, 320);
    };
    const writeCol = (col, x, text) => {
      if (col.nest) kit.nestSet(x, col.nest, text); // 안쪽 열쇠 칸(지도자 표기 낱말 — 6단계 D3)
      else if (col.type === 'check') {
        if (text === true) x[col.key] = true;
        else delete x[col.key];
      } else if (col.type === 'number') {
        if (text === '' || !isFinite(Number(text))) delete x[col.key];
        else x[col.key] = Number(text);
      } else if (col.type === 'list') {
        const list = [...new Set(text.split(/[,，]/).map(s => s.trim()).filter(Boolean))];
        if (list.length) x[col.key] = list;
        else delete x[col.key];
      } else if (col.type === 'pair') {
        /* 좌표 두 수 — 읽히면 [x, y], 아직 덜 친 글은 그대로(검사가 알려 줌), 비우면 지움 */
        if (!text.trim()) delete x[col.key];
        else x[col.key] = HT.readCoords(text) || text.trim();
      } else if (text.trim() === '' && col.type !== 'id') delete x[col.key];
      else x[col.key] = col.type === 'id' ? text.trim() : text;
    };
    const baseRow = el => {
      const tr = el.closest('tr[data-i]');
      const t = tableOf(baseTab);
      if (!tr || !t || t.form) return null;
      const i = Number(tr.dataset.i);
      const x = rowsAt(baseTab)[i];
      return x ? { t, i, x, tr } : null;
    };
    /** 하위 표(지도의 구역 · 장면) 안의 요소 → { t, s, x, i, items, j, r } (줄 밖이면 j · r 없음) */
    const subRow = el => {
      const box = el && el.closest ? el.closest('[data-base-sub]') : null;
      const t = tableOf(baseTab);
      if (!box || !t || !t.subs) return null;
      const i = Number(box.dataset.baseSub);
      const x = rowsAt(baseTab)[i];
      const s = t.subs.find(q => q.key === box.dataset.subKey);
      if (!x || !s) return null;
      const tr = el.closest('tr[data-j]');
      const items = arr(x[s.key]);
      const j = tr ? Number(tr.dataset.j) : -1;
      return { t, s, x, i, items, j, r: j >= 0 ? items[j] : null };
    };
    /* 이름 상자(형식 버전 3)의 줄을 고치면 그 줄의 이름 목록을 통째로 다시 적습니다 — 줄 추가 · 삭제(core.js의 문서 전체 단추)도 input으로 옵니다 */
    const writeNames = e => {
      const nb = e.target && e.target.closest ? e.target.closest('[data-base-names]') : null;
      if (!nb) return false;
      const x = arr(draft && draft[baseTab])[Number(nb.dataset.baseNames)];
      if (!x) return true;
      const host = nb.querySelector('[data-names-rows]');
      const problems = [];
      const list = HT.readNameRows(host, problems);
      if (list.length) x.names = list;
      else delete x.names;
      /* 읽지 못한 줄은 작업본에 들어가지 않으므로 — 친 글을 따로 두고(다시 그려도 남게) 그 줄과 까닭을 표시합니다 */
      if (problems.length) {
        const g = (row, cls) => ((row.querySelector(`.${cls}`) || {}).value ?? '').trim();
        const rows = [...host.children].filter(r => r.classList.contains('name-row')).map(row => ({ text: g(row, 'x-text'), lang: g(row, 'x-lang'), kind: g(row, 'x-kind'), start: g(row, 'x-start'), end: g(row, 'x-end'), note: g(row, 'x-note') }));
        pendingNames.set(namesKey(baseTab, x), { rows, problems, valid: JSON.stringify(arr(x.names)) });
      } else pendingNames.delete(namesKey(baseTab, x));
      markNames(nb, problems);
      const btn = baseBody.querySelector(`tr[data-i="${nb.dataset.baseNames}"] [data-act="names"]`);
      if (btn) {
        btn.classList.toggle('has-names', list.length > 0);
        btn.innerHTML = `文${list.length ? `<small>${list.length}</small>` : ''}`;
      }
      commitSoon();
      return true;
    };
    /* 사람 칸(가문의 시조): 세 글자 넘게 치면 사람 찾기 상자 — 계보 전용 인물은 자동 완성 목록에 없음 (js/maker-kin.js · 확정 설계 7-2 ②) */
    baseBody.addEventListener('focusin', e => {
      if (e.target.matches && e.target.matches('input[data-person-col]') && HT.makerKin) HT.makerKin.attachFinder(e.target, { strict: true });
    });
    baseBody.addEventListener('input', e => {
      if (writeNames(e)) return;
      const sr = subRow(e.target);
      if (sr) {
        /* 하위 표의 칸: 그 줄의 객체에 바로 (id도 참조 열이 아님 — 지도 안에서만 쓰는 글) */
        const col = sr.r && e.target.name ? sr.s.cols.find(c => c.key === e.target.name) : null;
        if (!col || !writeField(col, sr.r, e.target)) return;
        return commitSoon();
      }
      const r = baseRow(e.target);
      if (!r || !e.target.name) return;
      const col = r.t.cols.find(c => c.key === e.target.name);
      if (!col || isRefCol(r.t, col)) return; // 참조 열은 칸에서 나올 때 한 번에
      if (col.type === 'json') {
        if (!writeField(col, r.x, e.target)) return; // JSON 칸의 잘못된 글은 적지 않음(칸만 붉게)
      } else writeCol(col, r.x, col.type === 'check' ? e.target.checked : e.target.value);
      commitSoon();
    });
    baseBody.addEventListener('change', e => {
      const r = baseRow(e.target);
      if (!r || !e.target.name) return;
      const col = r.t.cols.find(c => c.key === e.target.name);
      if (!col || !isRefCol(r.t, col)) return;
      const from = str(e.target.defaultValue);
      const to = str(e.target.value);
      if (to === from) return;
      if (col.type === 'id' && (!HT.ID_RE.test(to) || rowsAt(baseTab).some((y, j) => j !== r.i && y && y.id === to))) {
        HT.toast('id는 영문·숫자·- _ . 만 쓸 수 있고, 이 목록의 다른 것과 겹치면 안 됩니다.', 'error');
        e.target.value = from;
        return;
      }
      flushSoon();
      /* 같은 id가 켜져 있는 다른 팩에도 있으면(kit.shadowOf) 연표에는 그쪽 정의가 쓰입니다 — 이름을 따라 고치면 가리키던 곳이 그 정의(옛 이름)에서 떨어져
         자동 가문 · 사전에 없는 지위가 되므로, 이름은 따라가지 않고 알리기만 합니다. id를 바꾸는 것은 이 DLC만의 정의로 떼어 내는 것이라 평소대로 따라갑니다 */
      const follow = ((r.t.refs || {})[col.key] || []).filter(s => !s.countOnly);
      const shadow = col.type === 'id' || !follow.length || !from || !to ? null : kit.shadowOf(others, baseTab, r.x.id);
      const kept = shadow ? kit.usageText(kit.findUsers(draft, { refs: { [col.key]: follow } }, { [col.key]: from })) : '';
      writeCol(col, r.x, to);
      if (col.type === 'id' && openNames.delete(`${baseTab}:${from}`)) openNames.add(`${baseTab}:${to}`); // 펼쳐 둔 이름 상자는 새 id로도 펼친 채로 (형식 버전 3)
      if (col.type === 'id' && pendingNames.has(`${draft.id}:${baseTab}:${from}`)) {
        pendingNames.set(`${draft.id}:${baseTab}:${to}`, pendingNames.get(`${draft.id}:${baseTab}:${from}`)); // 읽지 못한 이름 줄도 새 id로
        pendingNames.delete(`${draft.id}:${baseTab}:${from}`);
      }
      const n = from && to && !shadow ? kit.renameRefs(draft, r.t, col.key, from, to) : 0;
      commit();
      ctx.refresh();
      rerenderBase();
      /* 열린 편집 창도 따라가게: 폼에 남은 옛 값(옛 트랙 id · 옛 민족 이름)이 다음 저장 때 되살아나지 않게 — 초점이 옮겨 간 다음에 (그 칸을 누른 것이면 초점을 되돌려 줌) */
      if (n || col.type === 'id') setTimeout(() => ctx.syncEditor(from && to ? (item, list) => kit.renameRefs({ [list]: [item] }, r.t, col.key, from, to) : null), 0);
      if (n) HT.toast(`이 ${r.t.word}을(를) 가리키던 곳 ${n}개도 새 ${col.type === 'id' ? 'id' : col.label}(으)로 바꿨습니다.`, 'ok');
      else if (shadow)
        HT.toast(
          `켜져 있는 «${shadow.name}»에도 같은 id의 ${r.t.word} 정의가 있어, 그 DLC가 켜져 있는 동안 연표에는 그쪽 정의가 쓰입니다${kept ? ` — 그래서 옛 ${col.label} «${from}»(으)로 적은 곳(${kept})은 따라 바꾸지 않았습니다` : ''}. 이 DLC만의 것으로 쓰려면 id를 바꾸세요.`
        );
    });
    baseBody.addEventListener('click', async e => {
      const t = tableOf(baseTab);
      if (!t || !draft) return;
      const imp = e.target.closest('[data-import]');
      if (imp) {
        const cands = importable(baseTab);
        const picked = imp.dataset.import === 'all' ? cands : [cands[Number(imp.dataset.import)]].filter(Boolean);
        if (!picked.length) return;
        draft[baseTab] = arr(draft[baseTab]); // 형식 3 목록(지도 · 글꼴)은 작업본에 자리가 없을 수 있음
        for (const c of picked) {
          const { wiki, ...def } = c.def; // 본문은 그 DLC의 것 — 가져오지 않습니다
          draft[baseTab].push(JSON.parse(JSON.stringify(def)));
        }
        flushSoon();
        commit();
        ctx.refresh();
        renderBase();
        const one = picked[0].def;
        return HT.toast(picked.length > 1 ? `${t.word} ${picked.length}개를 가져왔습니다 — 같은 id라 연표에서 하나로 합쳐집니다.` : `«${one.name || one.id}»을(를) 가져왔습니다 — 같은 id라 연표에서 한 줄로 합쳐집니다.`, 'ok');
      }
      const b = e.target.closest('[data-act]');
      if (t.form) {
        const tr = e.target.closest('tr[data-uid]');
        const act = b ? b.dataset.act : tr ? 'open' : '';
        if (act === 'new') return ctx.openEditor(null, t.form);
        if (!tr) return;
        const uid = tr.dataset.uid;
        const x = state.model.byUid.get(uid) || pseudo(uid);
        if (!x) return;
        if (act === 'doc') return ctx.openWiki(uid);
        if (act === 'del') {
          const raw = t.uses ? (D.findOwn(draft, x.id) || {}).item : null;
          const used = raw ? kit.usageText(t.uses(draft, raw)) : ''; // 쓰는 곳 (시대 구분을 가리키는 대범위)
          if (!confirm(`«${x.name || x.title || x.epoch || x.id}» ${t.word}을(를) ${used ? `쓰는 곳(${used})이 있습니다. ${t.delNote || ''} 삭제할까요?` : '삭제할까요?'}`)) return;
          if (state.editing === uid) ctx.closeEditor();
          D.removeOwn(draft, x.id);
          commit();
          ctx.refresh();
          return renderBase();
        }
        ctx.openEditor(x, t.form); // 검사에서 떨어져 연표에 없는 것도 편집 창에서 고칩니다
        const m = state.model.byUid.get(uid);
        if (m) timeline.focusOn(m);
        return;
      }
      /* 하위 표(지도의 구역 · 장면)의 단추: 줄 추가 · 삭제 · 파일 (2026-10-23) */
      const sr = subRow(e.target);
      if (sr) {
        if (e.target.closest('[data-sub-add]')) {
          flushSoon();
          sr.x[sr.s.key] = arr(sr.x[sr.s.key]);
          sr.x[sr.s.key].push(sr.s.fresh ? sr.s.fresh() : {});
          commit();
          ctx.refresh();
          renderBase();
          const input = baseBody.querySelector(`[data-base-sub="${sr.i}"][data-sub-key="${CSS.escape(sr.s.key)}"] tbody tr:last-child input`);
          if (input) input.focus();
          return;
        }
        if (e.target.closest('[data-sub-del]') && sr.r) {
          if (!confirm(`이 ${sr.s.word} 줄을 지울까요?`)) return;
          flushSoon();
          sr.items.splice(sr.j, 1);
          if (!sr.items.length) delete sr.x[sr.s.key];
          commit();
          ctx.refresh();
          return renderBase();
        }
        if (b && sr.r && (b.dataset.act === 'file' || b.dataset.act === 'file-clear')) {
          const col = sr.s.cols.find(c => c.key === b.dataset.key);
          if (!col) return;
          flushSoon();
          if (b.dataset.act === 'file-clear') delete sr.r[col.key];
          else if (!(await pickInto(col, sr.r))) return;
          commit();
          ctx.refresh();
          return renderBase();
        }
        return;
      }
      if (!b) return;
      const act = b.dataset.act;
      if (act === 'add') {
        flushSoon();
        if (t.object) draft[baseTab] = t.fresh ? t.fresh() : {}; // 객체 표(영토): 한 덩어리를 만듦
        else {
          const id = freshId(baseTab, t);
          draft[baseTab] = arr(draft[baseTab]); // 형식 3 목록(지도 · 글꼴)은 작업본에 자리가 없을 수 있음
          draft[baseTab].push(t.fresh ? t.fresh(id, draft[baseTab].length) : { id, name: '' });
        }
        baseAfter();
        commit();
        ctx.refresh();
        renderBase();
        const input = baseBody.querySelector('tbody tr:last-child input[name="name"], tbody tr:last-child input[name="family"], tbody tr:last-child input');
        if (input) input.focus();
        return;
      }
      const r = baseRow(b);
      if (!r) return;
      if (act === 'doc') return ctx.openWiki(`${t.docPrefix}:${r.x.id}`);
      if (act === 'sub') {
        /* 하위 표 펼치기 · 접기 — 펼친 줄은 다시 그려도 펼친 채로 */
        const key = `${baseTab}:${r.x.id}:${b.dataset.sub}`;
        if (openSubs.has(key)) openSubs.delete(key);
        else openSubs.add(key);
        flushSoon();
        renderBase();
        const back = baseBody.querySelector(`tr[data-i="${r.i}"] [data-act="sub"][data-sub="${CSS.escape(b.dataset.sub)}"]`);
        if (back) back.focus();
        return;
      }
      if (act === 'file' || act === 'file-clear') {
        const col = t.cols.find(c => c.key === b.dataset.key);
        if (!col) return;
        flushSoon();
        if (act === 'file-clear') delete r.x[col.key];
        else if (!(await pickInto(col, r.x))) return;
        commit();
        ctx.refresh();
        return renderBase();
      }
      if (act === 'names') {
        /* 이름 상자 펼치기 · 접기 (형식 버전 3) — 펼친 줄은 다시 그려도 펼친 채로 */
        const key = `${baseTab}:${r.x.id}`;
        if (openNames.has(key)) openNames.delete(key);
        else openNames.add(key);
        flushSoon();
        renderBase();
        const back = baseBody.querySelector(`tr[data-i="${r.i}"] [data-act="names"]`);
        if (back) back.focus();
        return;
      }
      if (act === 'color') {
        const v = await HT.pickColor(b, r.x.color ? HT.pastel(r.x.color) : '');
        if (v == null) return;
        if (v) r.x.color = v;
        else delete r.x.color;
        flushSoon();
        commit();
        ctx.refresh();
        return renderBase();
      }
      if (act === 'del') {
        const used = kit.findUsers(draft, t, r.x).length;
        const name = r.x.name || r.x.id;
        if (!confirm(used ? `«${name}»을(를) 쓰는 곳이 ${used}개 있습니다. ${t.delNote || '지우면 그 항목들은 검사에서 걸릴 수 있습니다(다른 DLC에 같은 id가 있으면 저장할 때 다시 실립니다).'} 지울까요?` : t.object ? `${t.word} 자료를 통째로 지울까요?` : `«${name}»을(를) 지울까요?`)) return;
        flushSoon();
        if (t.object) delete draft[baseTab]; // 객체 표(영토): 통째로
        else draft[baseTab].splice(r.i, 1);
        baseAfter();
        commit();
        ctx.refresh();
        renderBase();
      }
    });
    $('#mkBaseTabs').addEventListener('click', e => {
      const b = e.target.closest('[data-base-tab]');
      if (!b) return;
      flushSoon();
      baseTab = b.dataset.baseTab;
      winUi.baseTab = baseTab;
      saveWinUi();
      baseBody.scrollTop = 0;
      baseBefore();
      renderBase();
    });

    /* ---------- 표 붙여넣기 (사건 · 시대) ---------- */
    const pasteDialog = $('#mkPasteDialog');
    const pasteForm = $('#mkPasteForm');
    let pasteResult = null;
    const pasteKind = () => (pasteForm.elements.kind.value === 'period' ? 'period' : 'event');
    function analyzePasteUI() {
      const kind = pasteKind();
      const out = $('#mkPastePreview');
      $('#mkPasteHint').textContent = kit.PASTE_KINDS[kind].hint;
      pasteResult = null;
      $('#mkPasteAdd').disabled = true;
      const m = state.model;
      const firstTrack = m.tracks.find(t => state.ui.tracks[t.id] !== false) || m.tracks[0];
      const r = kit.analyzePaste(pasteForm.elements.text.value, kind, { tracks: m.tracks, categories: m.categories.filter(c => c.id !== 'etc'), defaultTrack: firstTrack ? firstTrack.id : null });
      if (r.error != null && !r.items.length) {
        out.innerHTML = r.error ? `<p class="problems">${esc(r.error)}</p>` : '';
        return;
      }
      pasteResult = Object.assign({ kind }, r);
      const trackName = id => (r.newTracks.find(t => t.id === id) || m.trackMap.get(id) || { name: id }).name;
      const catName = id => (!id ? '기타' : (r.newCats.find(c => c.id === id) || m.categoryMap.get(id) || { name: id }).name);
      const heads = kind === 'event' ? ['제목', '시기', '트랙', '분류', '중요도'] : ['이름', '시기', '트랙', '민족'];
      const body = r.items
        .slice(0, 50)
        .map(x => `<tr><td>${esc(x.title || x.name)}</td><td>${esc(x.startUnknown ? (x.end != null && !x.ongoing && !x.endUnknown ? `미정 ~ ${HT.formatWhen(x, 'end')}` : '미정') : HT.formatRange(x))}</td><td>${esc(trackName(x.track))}</td>${kind === 'event' ? `<td>${esc(catName(x.category))}</td><td>${'★'.repeat(x.importance)}</td>` : `<td>${esc(x.people || '')}</td>`}</tr>`)
        .join('');
      const news = `${r.newTracks.length ? ` 새로 만들 트랙: ${r.newTracks.map(t => `<b>${esc(t.name)}</b>`).join(', ')}.` : ''}${r.newCats.length ? ` 새로 만들 분류: ${r.newCats.map(c => `<b>${esc(c.name)}</b>`).join(', ')}.` : ''}`;
      out.innerHTML = `
        <p><b>${r.items.length}개</b>를 넣을 수 있습니다.${news}</p>
        ${r.problems.length ? `<ul class="mk-paste-problems">${r.problems.slice(0, 10).map(p => `<li>${esc(p)}</li>`).join('')}${r.problems.length > 10 ? `<li>…외 ${r.problems.length - 10}개</li>` : ''}</ul>` : ''}
        ${r.items.length ? `<div class="mk-table-wrap"><table class="mk-base-table is-list"><thead><tr>${heads.map(h => `<th>${h}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table>${r.items.length > 50 ? `<p class="hint">…외 ${r.items.length - 50}개</p>` : ''}</div>` : ''}`;
      $('#mkPasteAdd').disabled = !r.items.length;
    }
    function openPaste() {
      if (!ready()) return;
      pasteForm.reset();
      pasteResult = null;
      analyzePasteUI();
      if (!pasteDialog.open) pasteDialog.showModal();
      pasteForm.elements.text.focus();
    }
    /* ---------- 통째 붙여넣기 (칸 채우기 답 하나 → 시대 편집 창의 모든 칸 — js/maker-paste.js의 openWhole) ----------
       편집 창의 [통째 붙여넣기] · 넣기 메뉴: 편집 창이 시대를 열고 있으면 그 시대에, 아니면 새 시대 편집 창을 열고.
       Ctrl+V로 답을 붙여넣으면(text): 열린 시대 편집 창이 비었거나 같은 이름이면 거기에, 아니면 답의 이름(· 트랙)과 같은 시대가 하나 있으면 그 시대의 편집 창(등록된 정권 고치기),
       없으면 새 시대 편집 창. 넣은 칸은 저장하지 않은 고침 — 저장은 편집 창의 [저장] */
    async function pasteWhole(text = '') {
      if (!ready() || !HT.makerPaste) return false;
      const P = HT.makerPaste;
      const form = $('#editorForm');
      const onPeriod = () => paneApi.isOpen() && state.editingKind === 'period';
      if (text) {
        const r = P.parseWhole(text, { tracks: state.model.tracks });
        const name = r.fields.name || '';
        const editingName = onPeriod() ? String(HT.FORMS.period.read(form).item.name || '') : '';
        const same = name ? state.model.periods.filter(p => p.itemKind === 'period' && p.name === name && (!r.fields.track || p.track === r.fields.track)) : [];
        if (onPeriod() && (!editingName || editingName === name)) {
          /* 열린 편집 창에 */
        } else if (same.length > 1) {
          HT.toast(`이름이 «${name}»인 시대가 여럿입니다 — 고칠 시대의 편집 창을 열고 「통째 붙여넣기」를 누르세요.`, 'error');
          return false;
        } else if (same.length === 1) {
          await ctx.openEditorFor(same[0].uid);
          if (!onPeriod() || state.editing !== same[0].uid) {
            HT.toast(`«${name}»의 편집 창을 열지 못했습니다 — 잠긴 팩이면 자물쇠를 풀고 다시 붙여넣으세요.`, 'error');
            return false;
          }
        } else if (!(await ctx.openEditor(null, 'period'))) return false;
      } else if (!onPeriod() && !(await ctx.openEditor(null, 'period'))) return false;
      if (!onPeriod()) return false;
      return P.openWhole({ form, tracks: () => state.model.tracks, spheres: () => state.model.spheres || [], eras: () => [...new Set([...(state.model.epochs || []), ...(state.model.scopes || [])].map(x => x && x.name).filter(Boolean))], read: () => HT.FORMS.period.read(form).item, refill: values => ctx.refillEditor(values), previewLinks, applyLinks, previewPeople, applyPeople, unlock }, text);
    }
    /* 통째 붙여넣기의 인물 층 — 이 나라를 저장한 뒤 내 DLC의 인물로(js/maker-kin.js planPeople · applyPeople). 같은 트랙 · 같은 이름의 제 인물은 고침 */
    function previewPeople(people, track) {
      const t = track || (draft.tracks[0] || {}).id || '';
      return (people || []).map(p => {
        const same = (draft.figures || []).filter(f => f && f.name === p.name && String(f.track || '') === t);
        return { name: p.name, status: same.length > 1 ? 'many' : same.length ? 'update' : 'new' };
      });
    }
    async function applyPeople(uid, item, people) {
      if (!HT.makerKin || !HT.makerKin.planPeople) return null;
      const nation = (uid && state.model.byUid.get(uid)) || item;
      const plan = HT.makerKin.planPeople(state.model, draft, nation, people);
      const res = { added: plan.add.length, updated: plan.update.length, skipped: plan.skipped, loose: plan.loose };
      if (!res.added && !res.updated) return res;
      const ok = await transact(d => HT.makerKin.applyPeople(d, plan), `통째 붙여넣기 — «${item.name}»의 인물 ${res.added + res.updated}명`, { keepEditor: true });
      return ok ? res : { added: 0, updated: 0, skipped: ['작업본을 고치지 못했습니다'], loose: [] };
    }
    /* 통째 붙여넣기의 '다른 나라에 넣을 것'(칸 블록의 이어받은나라 · 속했던나라 층 — 그 나라의 승계 칸 · 소속 칸에 이 나라):
       이름으로 찾되 같은 트랙을 먼저(하나뿐이어야), 제 것은 그 항목에 · 남의 것은 바뀐 칸만 덮어쓰기로(한꺼번에 고치기 · 놓아서 채우기와 같은 길) · 잠긴 팩은 자물쇠를 풀어야 */
    function linkTarget(name, track) {
      const all = state.model.periods.filter(p => p.itemKind === 'period' && p.name === name);
      const same = all.filter(p => p.track === track);
      const pick = same.length ? same : all;
      if (!pick.length) return { status: 'none' };
      if (pick.length > 1) return { status: 'many' };
      const x = pick[0];
      if (isLocked(x)) return { status: 'locked', x };
      return { status: isOwn(x) ? 'own' : 'patch', x };
    }
    /* 통째 붙여넣기의 '대범위에 넣을 것'(칸 블록의 시대구분 · 대범위 층 — js/maker-paste.js joinScope): 내 DLC의 대범위 · 시대 구분은 작업본(d)에서,
       남의 것은 모델에서 — 시대 구분은 이름으로 가리킬 수 있고, 남의 대범위는 패치 대상이 아니라 고치지 못함. 새 항목은 HT.draft.addItem으로(id를 매김) */
    const scopeCtx = d => ({
      epochs: state.model.epochs.filter(e => !isOwn(e)).map(e => ({ name: e.name, id: e.id, track: e.track })),
      scopes: state.model.scopes.filter(s => !isOwn(s)).map(s => ({ name: s.nameAuto ? '' : s.name, epoch: s.epochRef, track: s.track, packName: s.packName || s.packId })),
      add: (list, obj) => D.findOwn(d, D.addItem(d, list === 'epochs' ? 'epoch' : 'scope', obj)).item,
    });
    const isScopeItem = it => it && (it.kind === 'epoch' || it.kind === 'scope' || it.kind === 'cycle'); // cycle = 판 2 주기 층(「주기」 표)
    /** 주기 층: 다른 켠 DLC가 이미 가진 문화권별 주기(그 문화권은 새로 만들지 않음) */
    const otherCycleSpheres = () => (state.packs || []).filter(p => p && p.id !== draft.id).flatMap(p => (Array.isArray(p.yearCycles) ? p.yearCycles : []).map(c => c && c.sphere).filter(Boolean));
    /** 미리 보기: [{ name, kind, type, relation, status, packId, packName, result('added' · 'updated' · 'same' — 대범위는 'new'도), epochNew?, why? }] — 원본의 사본에 넣어 봄 */
    function previewLinks(items, name, track) {
      const copy = JSON.parse(JSON.stringify({ id: draft.id, epochs: draft.epochs || [], scopes: draft.scopes || [], yearCycles: draft.yearCycles || [] }));
      const ctx = Object.assign(scopeCtx(copy), { add: undefined }); // 사본에는 목록 끝에 그대로
      return (items || []).map(it => {
        if (it.kind === 'cycle') {
          const res = HT.makerPaste.joinCycle(copy, it, otherCycleSpheres());
          return Object.assign({}, it, { status: res.why ? 'none' : 'own', result: res.result, why: res.why || '' });
        }
        if (isScopeItem(it)) {
          const res = HT.makerPaste.joinScope(copy, it, { name, track }, ctx);
          return Object.assign({}, it, { status: res.why ? 'none' : 'own', result: res.result, epochNew: res.epochNew, why: res.why || '' });
        }
        const t = linkTarget(it.name, track);
        const o = Object.assign({}, it, { status: t.status, packId: t.x ? t.x.packId : '', packName: t.x ? t.x.packName || t.x.packId : '' });
        if (t.status === 'own' || t.status === 'patch') {
          try {
            o.result = HT.makerPaste.linkOther(JSON.parse(JSON.stringify(editableRaw(t.x))), it, name);
          } catch (e) {
            o.status = 'none';
          }
        }
        return o;
      });
    }
    /** 이 나라(name · id)를 저장한 뒤 그 나라들 · 대범위에 넣음 — 작업본 고침 한 번(되돌리기 한 걸음 · 편집 창은 그대로).
        → { names(넣은 나라), scopes(넣은 대범위 — 시대구분 층은 시대 구분 이름), epochs(새로 만든 시대 구분), skipped(못 넣은 것 — 까닭) } */
    async function applyLinks(name, track, items, id) {
      const plan = (items || []).filter(it => !isScopeItem(it)).map(it => ({ it, t: linkTarget(it.name, track) }));
      const skipped = plan.filter(p => p.t.status !== 'own' && p.t.status !== 'patch').map(p => `${p.it.name}(${({ locked: '잠김', none: '연표에 없음', many: '같은 이름이 여럿' })[p.t.status] || p.t.status})`);
      const names = [], scopes = [], epochs = [], scopeSkips = [];
      const work = plan.filter(p => p.t.status === 'own' || p.t.status === 'patch');
      const scopeWork = (items || []).filter(isScopeItem);
      if (!work.length && !scopeWork.length) return { names, scopes, epochs, skipped };
      const ok = await transact(d => {
        names.length = scopes.length = epochs.length = scopeSkips.length = 0;
        const ctx = scopeCtx(d);
        for (const it of scopeWork) {
          if (it.kind === 'cycle') {
            const res = HT.makerPaste.joinCycle(d, it, otherCycleSpheres());
            if (res.why) scopeSkips.push(`${it.name} 주기(${res.why})`);
            else if (res.result !== 'same') scopes.push(`${it.name} 주기`);
            continue;
          }
          const res = HT.makerPaste.joinScope(d, it, { name, track, id }, ctx);
          if (res.why) scopeSkips.push(`${it.name}(${res.why})`);
          else if (res.result !== 'same') scopes.push(it.name);
          if (res.epochNew) epochs.push(it.name);
        }
        for (const { it, t } of work) {
          if (t.status === 'own') {
            const hit = D.findOwn(d, t.x.id);
            if (hit && HT.makerPaste.linkOther(hit.item, it, name) !== 'same') names.push(it.name);
          } else {
            const before = editableRaw(t.x);
            const after = JSON.parse(JSON.stringify(before));
            if (HT.makerPaste.linkOther(after, it, name) === 'same') continue;
            HT.makerGrid.patchItem(d, baseModel().byUid.get(t.x.uid) || t.x, before, after);
            names.push(it.name);
          }
        }
        return d;
      }, `통째 붙여넣기 — «${name}»을(를) 다른 나라${scopeWork.length ? ' · 대범위' : ''}에`, { keepEditor: true });
      return ok ? { names: [...new Set(names)], scopes, epochs, skipped: skipped.concat(scopeSkips) } : { names: [], scopes: [], epochs: [], skipped: skipped.concat(scopeWork.map(it => `${it.name}(작업본을 고치지 못했습니다)`)) };
    }
    async function addPasted() {
      if (!pasteResult || !pasteResult.items.length) return false;
      const target = draft, analyzed = pasteResult;
      flushSoon(); await takeSnapshot('표 붙여넣기 전');
      if (draft !== target || pasteResult !== analyzed) return false;
      const { kind, items, newTracks, newCats } = analyzed;
      for (const t of newTracks) if (!draft.tracks.some(x => x.id === t.id)) draft.tracks.push({ id: t.id, name: t.name, color: t.color });
      for (const c of newCats) if (!draft.categories.some(x => x.id === c.id)) draft.categories.push({ id: c.id, name: c.name, color: c.color });
      const ids = items.map(obj => D.addItem(draft, kind, obj));
      D.ensureRefs(draft, state.model);
      commit();
      /* 넣은 것이 필터에 가려지지 않게: 트랙 · 분류 */
      for (const obj of items) {
        delete state.ui.tracks[obj.track];
        if (obj.category) delete state.ui.categories[obj.category];
      }
      ctx.refresh();
      const first = state.model.byUid.get(`${draft.id}/${ids[0]}`);
      if (first) timeline.focusOn(first);
      HT.toast(`${HT.FORMS[kind].word} ${items.length}개를 넣었습니다.${pasteResult.problems.length ? ` 건너뛴 줄 · 참고 ${pasteResult.problems.length}개.` : ''}`, 'ok');
      pasteResult = null;
      return true;
    }

    /* ---------- 문제 창(아래 창 [문제]): 작업본의 오류 · 경고 — 누르면 그 항목으로 가서 편집 창 ---------- */
    let issues = [];
    /** 아래 창 [문제]의 몸통 글 (issues를 채움 — 누르면 gotoIssue) */
    function problemsHTML() {
      if (!draft) return '<p class="hint">고칠 DLC를 먼저 고르세요.</p>';
      const { errors, warnings, notes } = check;
      issues = errors.map(x => ({ x, bad: true })).concat(warnings.map(x => ({ x, bad: false })), notes.map(x => ({ x, bad: false, note: true })));
      const cls = it => (it.bad ? 'is-bad' : it.note ? 'is-note' : 'is-warn');
      const word = it => (it.bad ? '오류' : it.note ? (it.x.confirm ? '확인할 것' : '알림') : '경고'); // 확인할 것 = 작업본 · 불러온 팩에서 풀리지 않은 참조(다른 팩의 것일 수 있음 — 5단계 과제 8)
      const confirms = notes.filter(x => x.confirm).length;
      return `
        <p class="mk-check-sum ${errors.length ? 'is-bad' : 'is-ok'}">${errors.length ? `고쳐야 할 오류 ${errors.length}개` : '✓ 오류가 없습니다.'}${warnings.length ? ` · 참고할 경고 ${warnings.length}개` : ''}${confirms ? ` · 확인할 것 ${confirms}개` : ''}${notes.length - confirms ? ` · 알림 ${notes.length - confirms}개` : ''}</p>
        <p class="hint">누르면 그 항목으로 가서 편집 창을 엽니다. 오류가 있는 항목은 연표에 나오지 않고, [반영]할 때 빠집니다.${confirms ? ' 확인할 것은 작업본 · 불러온 팩에서 찾지 못한 참조(빌림의 출처 · 실권의 상대)입니다 — 다른 팩의 객체면 그 팩을 불러오세요.' : ''}${notes.length - confirms ? ' 알림은 고칠 것이 아니라 알아 둘 것입니다(대범위를 켜면 승계로 이어 쓰던 줄이 나뉘는 곳 · 파일을 열 때 옛 꼴로 내리며 뺀 것).' : ''}</p>
        ${issues.length ? `<ul class="mk-check-list">${issues.map((it, i) => `<li><button type="button" data-issue="${i}" class="${cls(it)}"><b>${word(it)}</b><span>${esc(it.x.msg)}</span></button></li>`).join('')}</ul>` : ''}`;
    }
    /** 아래 창 몸통 (작업실 틀의 [문제] · [고친 것]) */
    function renderBottom() {
      if (!shell || !shell.bottomOpen()) return;
      if (['replace', 'blanks'].includes(shell.bottomTab())) { shell.renderExtraBottom(shell.bottomTab()); return; }
      shell.bottomBody.onclick = null; shell.bottomBody.onchange = null;
      if (shell.bottomTab() === 'history') { shell.bottomBody.innerHTML = historyHTML(); return; }
      if (shell.bottomTab() === 'autosave') { shell.bottomBody.innerHTML = snapshotsHTML(); return; }
      shell.bottomBody.innerHTML = shell.bottomTab() === 'changes' ? (draft ? changesHTML() : '<p class="hint">고칠 DLC를 먼저 고르세요.</p>') : problemsHTML();
    }
    /** 검사 결과 한 줄이 가리키는 곳으로: 항목 → 편집 창(연표에 없는 것도) · 트랙/분류/민족 → 바탕 자료의 그 줄 · 패치 → 그 대상 · DLC 전체 → DLC 정보 */
    function gotoIssue(x) {
      const list = x.kind;
      if (!list || list === 'info') return openInfo();
      const t = tableOf(list);
      if (t && !t.form) return openBase(list, x.index ?? -1);
      if (list === 'patches') {
        const p = arr(draft.patches)[x.index];
        const target = p && p.target ? state.model.byUid.get(p.target) || baseModel().byUid.get(p.target) : null;
        if (!target || !state.model.byUid.has(target.uid)) return HT.toast(p && p.hide ? '숨긴 항목입니다 — [고친 것]에서 되돌릴 수 있습니다.' : '패치의 대상이 지금 켜져 있는 DLC에 없습니다.', 'error');
        ctx.openEditorFor(target.uid);
        return timeline.focusOn(target);
      }
      const raw = arr(draft[list])[x.index];
      const kind = kit.kindOfList(list);
      if (!raw || !kind) return HT.toast('이 문제는 항목 하나를 가리키지 않습니다.');
      const uid = `${draft.id}/${raw.id}`;
      const m = state.model.byUid.get(uid);
      if (m) {
        ctx.openEditorFor(uid);
        if (m.lineageOnly === true) return; // 계보 전용 인물은 띠에 없음 (D1) — 편집 창만
        return timeline.focusOn(m);
      }
      const p = pseudo(uid);
      if (p) ctx.openEditor(p, kind);
    }

    /** 모델이 새로 지어진 뒤: 열려 있는 창들을 새 작업본으로 (바탕 자료 창은 거기서 타자 중이 아닐 때만 — 칸의 초점을 빼앗지 않게) */
    function renderLive() {
      renderPacks();
      if (shell && shell.propsMode() === 'info') paintInfoCard(); // 칸은 그대로 — 카드 · 표지 · 담긴 것 · 다음 반영 줄만
      renderBottom();
      paintSelection();
      if (baseWin.isOpen() && !baseEl.contains(document.activeElement)) renderBase();
    }

    /* 연표에서 넘겨받는 길은 없습니다 — 일방통행: 메이커 → 연표('연표로 ↗')의 한 방향뿐. 메이커는 늘 마지막에 고치던 작업본으로 뜹니다 */

    /* ---------- 왼쪽 '불러온 팩' 탭 (설계 3-5 — Apacks.png) ---------- */
    const ICON = {
      eye: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M1 8s2.6-4.8 7-4.8S15 8 15 8s-2.6 4.8-7 4.8S1 8 1 8z" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="8" cy="8" r="2.1" fill="currentColor"/></svg>',
      lock: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><rect x="3" y="7" width="10" height="7" rx="1.8" fill="currentColor"/><path d="M5.2 7V5.2a2.8 2.8 0 0 1 5.6 0V7" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>',
      unlock: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><rect x="3" y="7" width="10" height="7" rx="1.8" fill="currentColor"/><path d="M5.2 7V5.2a2.8 2.8 0 0 1 5.5-.6" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>',
    };
    const refRowHTML = r => {
      const p = state.packs.find(q => q.id === r.id);
      const why = r.auto === 'patch' ? '덮어쓰기 대상' : r.auto === 'needs' ? '필요한 팩' : '';
      const meta = r.missing ? '설치되어 있지 않음' : [r.builtin ? '내장' : `v${r.version}`, p ? HT.packCard.contentsText(p) : ''].filter(Boolean).join(' · ');
      return `<div class="mk-pack${r.show ? '' : ' is-hidden'}${r.missing ? ' is-missing' : ''}" data-ref="${esc(r.id)}">
        <button type="button" class="ic${r.show ? '' : ' is-off'}" data-ref-eye aria-pressed="${r.show}" aria-label="${esc(r.name)} ${r.show ? '숨기기' : '보이기'}" title="${r.show ? '연표에서 숨기기' : '연표에 보이기'}"${r.missing ? ' disabled' : ''}>${ICON.eye}</button>
        <div><b>${esc(r.name)}</b><small>${esc(meta)}${why ? ` · <em>${why}</em>` : ''}</small></div>
        <button type="button" class="ic${r.locked ? '' : ' is-open'}" data-ref-lock aria-pressed="${!r.locked}" aria-label="${esc(r.name)} ${r.locked ? '자물쇠 풀기' : '잠그기'}" title="${r.locked ? '자물쇠 풀기 — 이 팩의 항목도 고칩니다(고친 칸은 이 DLC의 덮어쓰기)' : '잠그기 — 보기만'}"${r.missing ? ' disabled' : ''}>${r.locked ? ICON.lock : ICON.unlock}</button>
        ${r.auto ? '' : '<button type="button" class="ic" data-ref-remove title="빼기" aria-label="빼기">✕</button>'}
      </div>`;
    };
    function renderPacks() {
      const el = shell && shell.packsBody;
      if (!el) return;
      if (!draft) {
        el.innerHTML = '<p class="mk-empty">고칠 DLC가 없습니다.</p>';
        return;
      }
      el.innerHTML = `<p class="mk-cap">고치는 DLC</p>
        <div class="mk-pack is-active"><i class="dot" aria-hidden="true"></i><div><b>${esc(draft.name)}</b><small>v${esc(draft.version)} · ${esc(HT.packCard.contentsText(goodPack || draft))}</small></div><span class="tag">편집 중</span></div>
        <p class="mk-cap">불러온 팩 <small>— 흐리게 보이고, 잠겨 있으면 보기만</small></p>
        ${refRows.map(refRowHTML).join('') || '<p class="hint">없음 — 이 DLC만 보입니다.</p>'}
        <button type="button" class="mk-add" data-ref-add>＋ 팩 불러오기</button>
        <p class="mk-note">불러온 팩은 이 DLC와 함께 기억합니다. 자물쇠를 풀면 그 팩의 항목도 고칠 수 있고, 고친 칸만 이 DLC의 덮어쓰기로 들어갑니다. 덮어쓰기 대상 · 필요한 팩은 저절로 들어와 뺄 수 없습니다.</p>`;
    }
    const copyRows = () => refRows.map(r => Object.assign({}, r));
    function addRefs(ids) {
      const rows = copyRows();
      for (const id of ids) if (draft && id !== draft.id && !rows.some(r => r.id === id)) rows.push({ id, show: true, locked: true, auto: '' });
      setRefs(rows);
    }
    function openRefPicker(btn) {
      const have = new Set(refRows.map(r => r.id));
      const cand = state.packs.filter(p => !have.has(p.id) && p.id !== draft.id);
      const r = btn.getBoundingClientRect();
      ctx.cmd.showMenu(
        [{ title: '팩 불러오기' }]
          .concat(cand.length ? cand.map(p => ({ label: `${p.name} ${p.builtin ? '(기본팩)' : `v${p.version}`}`, run: () => addRefs([p.id]) })) : [{ label: '더 불러올 설치된 팩이 없습니다', disabled: true }])
          .concat({ sep: true }, { label: '📂 파일에서 (.htpack)…', run: addRefsFromFile }),
        r.left,
        r.bottom + 4
      );
    }
    /** 파일에서 불러오기: 메이커 저장소에 설치하고(연표의 설치와 같은 길 — 조용히) 불러온 팩에 더함 */
    async function addRefsFromFile() {
      const files = await HT.pickFiles('.htpack');
      if (!files.length) return;
      const ids = await ctx.cmd.installFiles(files, { quiet: true });
      if (ids && ids.length) addRefs(ids);
    }
    const openPacks = () => shell && shell.setLeftTab('packs');
    /** 잠긴 팩의 항목인지 — 제 항목은 늘 아님, 불러온 팩 줄이 없으면(모르는 팩) 잠긴 것으로 */
    const isLocked = x => {
      if (!draft || !x || !x.packId || x.packId === draft.id) return false;
      const r = refRows.find(q => q.id === x.packId);
      return r ? r.locked : true;
    };
    function unlock(id) {
      setRefs(copyRows().map(r => (r.id === id ? Object.assign(r, { locked: false }) : r)));
      HT.toast('자물쇠를 풀었습니다 — 이 팩의 항목을 고치면 고친 칸만 이 DLC의 덮어쓰기로 들어갑니다.', 'ok');
    }
    const lockedToast = x => HT.toast(`잠긴 팩 «${x.packName}»의 항목입니다 — 불러온 팩 탭에서 자물쇠를 풀면 고칠 수 있습니다.`, 'error');

    /* ---------- 공개 ---------- */
    function start() {
      const api = {
        ...editApi,
        get draft() { return draft; },
        get changes() { return changes; },
        get check() { return check; },
        get broken() { return broken; },
        get drift() { return drift; },
        get saved() { return saved; },
        installed: () => installedPack(),
        nextVersion: () => (draft && changes.length ? D.bumpVersion(D.newerVersion(draft.version, (installedPack() || {}).version || '')) : ''),
        driftText: () => (drift ? driftText() : ''),
        isOwn, pseudo, dragOn,
        reflect, exportFile, exportLegacy, openInfo, openPaste, openDrift, pick,
        pasteWhole: () => pasteWhole(),
        openFile: () => openFile(),
        openBase: tab => openBase(tab),
        openBaseTools: tab => openBase(tab, -1, true),
        toTimeline,
        renderBottom,
        refRows: () => refRows,
        createNew,
        closeDraft,
        canRestore,
        restoreInstalled,
        /* 구조 나무의 놓아서 채우기(js/maker-shell.js): 잠금 · 남의 항목의 원본(+ 걸린 패치) · 견줄 원본 모델 · 물음 */
        isLocked, rawOf: editableRaw, baseModel, ask,
      };
      /* 함께 만드는 틀(10건 D3 결정 6 A — js/maker-templates.js): 틀은 작업실 설정이고 만들기는 작업본 고침 한 번(transact). 틀(작업실)보다 먼저 붙여
         작업실이 '＋ 더' · 넣기 메뉴 · 명령 찾기에 틀 줄을 붙이게(api.templates) — 편집 창의 '/' 목록 · 블록 메뉴 '틀로 저장…'은 틀 부품이 블록에 직접 덧붙임 */
      if (HT.makerTemplates) api.templates = HT.makerTemplates.mount(ctx, { ...api, get draft() { return draft; } });
      shell = HT.makerShell.mount(ctx, api);
      if (HT.makerKin) HT.makerKin.mount(ctx, { ...api, get draft() { return draft; }, openBase: (tab, flash) => openBase(tab, flash), applyDrop: (uids, drop) => shell.applyDrop(uids, drop) }); // 계보 입력(js/maker-kin.js — 머리 칩 고치기 · 계층 입력). 구분 · 민족 칩은 구조 나무의 놓아서 채우기와 같은 길(트랙 옮기기 물음)
      HT.makerDrag.mount(ctx, {
        ...api, get draft() { return draft; }, isLocked, rawOf: editableRaw, baseModel,
        createAt: async (track, a, b, range) => {
          const first = a.t <= b.t ? a : b, last = a.t <= b.t ? b : a;
          const kind = range ? 'period' : 'event', raw = { track, start: first.t, startAt: first.at, ...(range ? { end: last.t, endAt: last.at, name: '새 시대' } : { title: '새 사건' }) };
          let uid;
          if (await transact(d => { uid = d.id + '/' + D.addItem(d, kind, raw); return d; }, range ? '빈 곳에 시대 만들기' : '빈 곳에 사건 만들기')) {
            selectItems([uid]); await ctx.openEditorFor(uid);
            const input = document.querySelector('#editorForm [name="name"], #editorForm [name="title"]'); input?.focus(); input?.select();
          }
        },
      });
      /* 편집 창의 블록(10건 D3 결정 1~5 — js/maker-blocks.js): 줄 손잡이 · 블록 메뉴 · 줄 끌기 · 쓴 블록만 + 칩 · '/' 명령. 다른 나라로 옮기기는 작업본 고침 한 번(transact) */
      if (HT.makerBlocks) HT.makerBlocks.mount(ctx, { ...api, get draft() { return draft; }, isLocked, rawOf: editableRaw, baseModel });
      setInterval(() => { flushSoon(); takeSnapshot('10분 자동 저장', { changedOnly: true }); }, 10 * 60 * 1000);
      const typing = () => /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName) || document.activeElement.isContentEditable;
      for (const type of ['copy', 'cut', 'paste']) document.addEventListener(type, e => {
        if (e.defaultPrevented || typing() || !draft || shell.isStart() || document.querySelector('dialog[open]')) return;
        if (type === 'paste') pasteSelection(e);
        else if (type === 'copy') copySelection(selection(), e);
        else deleteSelection({ cut: true, event: e });
      });
      window.addEventListener('pagehide', flushSoon);
      $('#mkDrift').addEventListener('click', openDrift);
      // 창이 하나뿐인 환경(모바일)에서 '연표로'가 이 창을 연표 미리보기로 옮기기 전에: 편집 창에 저장하지 않은 고침이 있으면 '저장하고 이동 / 버리고 이동 / 취소'를 묻습니다
      HT.platform.beforeLeave = () => ctx.leaveEditor('이동');
      askDialog.addEventListener('click', e => {
        if (e.target === askDialog) return answer('cancel');
        const b = e.target.closest('button[value]');
        if (!b) return;
        e.preventDefault();
        answer(b.value);
      });
      askDialog.addEventListener('cancel', e => {
        e.preventDefault(); // Esc
        answer('cancel');
      });
      askDialog.addEventListener('close', () => !askDialog.open && answer(askDialog.returnValue)); // 닫힘 알림은 늦게 옵니다 — 그 사이 다음 물음이 떴으면 그것을 닫지 않게
      shell.bottomBody.addEventListener('click', e => {
        const h = e.target.closest('[data-history]');
        if (h) return historyGo(Number(h.dataset.history));
        const snapshot = e.target.closest('[data-snapshot]');
        if (snapshot) return restoreSnapshot(Number(snapshot.dataset.snapshot));
        if (e.target.closest('[data-snapshot-now]')) { flushSoon(); takeSnapshot('직접 남긴 시점').then(loadSnapshots); return; }
        const iss = e.target.closest('[data-issue]');
        if (iss && issues[Number(iss.dataset.issue)]) return gotoIssue(issues[Number(iss.dataset.issue)].x);
        const show = e.target.closest('[data-show]');
        if (show) {
          const x = state.model.byUid.get(show.dataset.show);
          if (!x) return;
          ctx.openDetail(x.uid);
          return timeline.focusOn(x);
        }
        const un = e.target.closest('[data-unpatch]');
        if (!un) return;
        D.unpatch(draft, un.dataset.unpatch);
        commit();
        ctx.refresh();
        ctx.syncEditor(null, { only: un.dataset.unpatch }); // 편집 창이 그 항목을 열고 있으면 걷어 낸 덮어쓰기 값을 들고 있지 않게
        renderBottom();
      });
      shell.packsBody.addEventListener('click', e => {
        const add = e.target.closest('[data-ref-add]');
        if (add) return openRefPicker(add);
        const row = e.target.closest('[data-ref]');
        const r = row && refRows.find(x => x.id === row.dataset.ref);
        if (!r) return;
        const rows = copyRows();
        const it = rows.find(x => x.id === r.id);
        if (e.target.closest('[data-ref-eye]')) it.show = !it.show;
        else if (e.target.closest('[data-ref-lock]')) it.locked = !it.locked;
        else if (e.target.closest('[data-ref-remove]')) rows.splice(rows.indexOf(it), 1);
        else return;
        setRefs(rows);
      });
      const P = shell.propsInfo;
      P.addEventListener('input', onInfoInput);
      P.addEventListener('change', e => {
        if (e.target.name === 'id') renameTo(e.target.value.trim());
        else if (e.target.name === 'category') {
          setOpt('category', e.target.value);
          commitSoon();
        }
      });
      P.addEventListener('keydown', onInfoKey);
      P.addEventListener('click', onInfoClick);
      P.addEventListener('pointerdown', e => {
        const h = e.target.closest('[data-hl-drag]');
        if (h) dragHighlight(h, e);
      });
      /* 붙여넣기 */
      pasteForm.addEventListener('input', analyzePasteUI);
      pasteForm.addEventListener('change', analyzePasteUI);
      $('#mkPasteHead').addEventListener('click', () => {
        const ta = pasteForm.elements.text;
        const head = kit.PASTE_KINDS[pasteKind()].head;
        if (!ta.value.startsWith(head)) ta.value = `${head}\n${ta.value.replace(/^\s+/, '')}`;
        ta.focus();
        ta.setSelectionRange(ta.value.length, ta.value.length);
        analyzePasteUI();
      });
      pasteForm.addEventListener('submit', async e => {
        if (!e.submitter || e.submitter.value !== 'add') return;
        e.preventDefault();
        if (await addPasted()) pasteDialog.close();
      });
      pasteDialog.addEventListener('click', e => {
        if (e.target === pasteDialog) pasteDialog.close();
      });
      /* Esc: 떠 있는 창에 초점이 있으면 그 창을, 편집 창에 초점이 있으면(또는 연표 위에서 — 상세가 열려 있지 않을 때) 편집 창을 닫습니다 (고침이 있으면 물음).
         상세 · 메뉴 · 자동 완성처럼 먼저 Esc를 받은 것이 있으면 그쪽이 이깁니다 */
      let detailWasOpen = false;
      document.addEventListener('keydown', e => e.key === 'Escape' && (detailWasOpen = !$('#detail').hidden), true);
      document.addEventListener('keydown', e => {
        if (e.key !== 'Escape' || e.defaultPrevented || document.querySelector('dialog[open]')) return;
        /* 키를 처음 받은 곳으로 판단합니다 — 지금의 초점이 아니라: 검색 칸의 Esc는 글을 비우고 초점을 빼 body로 보내는데,
           그것을 "연표 위에서 누른 Esc"로 보면 검색을 그만두려던 Esc가 편집 창을 닫습니다 */
        const a = e.target instanceof Element ? e.target : document.activeElement;
        const win = [baseWin].find(w => w.isOpen() && w.el.contains(a));
        if (win) {
          e.preventDefault();
          return win.close();
        }
        if (pane.hidden) return;
        const onBoard = !a || a === document.body || (a.closest && a.closest('#timeline'));
        if (pane.contains(a) || (onBoard && !detailWasOpen)) {
          e.preventDefault();
          ctx.leaveEditor();
        }
      });
      updateBar();
      if (!draft || (!D.hasWork(draft) && !installedPack())) shell.showStart(); // 고칠 DLC가 없거나, 든 것도 없고 반영한 적도 없는 빈 작업본(옛 메이커가 남긴 것 포함)이면 처음 화면부터
    }
    /** 다른 메이커 탭이 작업본을 고쳤을 때 다시 읽습니다 */
    function reloadDraft() {
      refsAll = kit.readRefs(HT.store.get(REFS_KEY, null)); // 다른 메이커 탭이 불러온 팩을 바꿨을 수도
      takeSnapshot('다른 창의 작업본을 불러오기 전');
      draft = D.load();
      history.reset(draft); selectedItems = [];
      goodPack = null;
      others = base = null;
      ctx.refresh();
      ctx.syncEditor(); // 열린 편집 창도 다른 탭이 고친 값으로 (손댄 칸은 그대로)
      if (shell && shell.propsMode() === 'info' && !shell.propsInfo.contains(document.activeElement)) renderInfo(); // 치는 중이 아니면 팩 정보도
    }
    /** 메뉴(⋯ · 우클릭)에 끼우는 줄 */
    const menuItems = KEYS => [
      { label: `⤴ 반영${changes.length ? ` (고친 것 ${changes.length})` : ''}`, key: KEYS.export, disabled: !draft, run: reflect },
      { label: '⬇ 팩 파일로 (.htpack)', disabled: !draft, run: exportFile },
      { label: '📦 팩 정보…', disabled: !draft, run: openInfo },
      { label: `바탕 자료 — ${Object.values(kit.BASE_TABLES).map(t => t.word).join(' · ')}`, disabled: !draft, run: () => openBase() },
      { label: '표 붙여넣기…', disabled: !draft, run: openPaste },
      { label: `검사${check.errors.length + check.warnings.length ? ` (${check.errors.length + check.warnings.length})` : ''}`, disabled: !draft, run: () => ready() && shell.openBottom('problems') },
      { label: '처음 화면…', run: () => shell.showStart() },
      { label: '연표로 ↗', run: toTimeline },
    ];

    return {
      ...editApi,
      start, buildModel, reloadDraft, menuItems,
      ready, isDraftId, isOwn, hasPatch, rawOf, hasOwn, pseudo,
      draftName: () => (draft ? draft.name : ''),
      saveItem, removeItem, revertItem, setDoc, setImages,
      saveView, removeView, // 집합 보기 (js/views-ui.js)
      viewRaw: id => arr(draft && draft.views).find(v => v && v.id === id) || null, // 작업본의 판 그대로 (고치기 폼이 설명 · 메모 · 보기 설정 · 이름 목록을 읽음)
      openWiki: key => ctx.openWiki(key), // 문서 창 열기 (판의 문서 view:id)
      pick, reflect, exportFile, exportLegacy, openDropped, toTimeline,
      /** 지도자 · 내각 칸의 ＋ 사람(5단계 과제 5): 작업본에 사람(인물)을 더하고 그 id를 돌려줌 — 열린 편집 창은 그대로(keepEditor) */
      createPerson: async raw => {
        if (!ready()) return null;
        let id = null;
        const ok = await transact(d => { id = D.addItem(d, 'figure', Object.assign({ importance: 2 }, raw)); return d; }, `사람 «${raw && raw.name ? raw.name : '?'}» 만들기`, { keepEditor: true });
        return ok ? id : null;
      },
      pane: paneApi, ask,
      openInfo, openBase, openPaste,
      openCheck: () => ready() && shell.openBottom('problems'),
      refRows: () => refRows,
      openPacks,
      isStart: () => !!shell && shell.isStart(),
      isLocked,
      unlock,
      hiddenPacks: () => new Set(refRows.filter(r => !r.show).map(r => r.id)),
      ownTrackIds: () => (draft ? arr(draft.tracks).map(t => t && t.id).filter(Boolean) : []),
      /* 검사용 (브라우저 콘솔 · 하네스) */
      get draft() {
        return draft;
      },
      get changes() {
        return changes;
      },
      get check() {
        return check;
      },
      setDraft,
    };
  };
})();

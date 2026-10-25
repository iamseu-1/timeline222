/* 역사 연표 — 메이커 편집 창의 블록 (dlc-maker.html에서만 읽힘 · 10건 4(가) · 5(나) — docs/설계-10건/4-5-메이커-블록과-묶음.md · 감독-선택.md D3 결정 1~5)
 *
 * 편집 창(#editorForm)의 폼을 '블록'으로 다시 묶습니다. 자료 형식은 그대로 — 읽고 쓰는 열쇠 · 채우기 · 읽기 함수는 core.js 그대로이고 감싸는 꼴만 바뀝니다
 * (폼의 칸을 옮겨 담을 뿐이라 HT.FORMS[종류].read가 읽는 값은 블록 전과 같음 — scripts/maker-blocks-check.mjs가 봄).
 *   결정 1 B  줄 손잡이 ⋮⋮ — 늘 보임 · 줄 안 첫 줄 맨 앞(대수 칸 앞). 줄 목록([data-cells] · [data-succ] · [data-parts])의 줄마다 첫 자식으로.
 *             줄이 flex-wrap이라 첫 줄에만 자리를 차지합니다(줄 왼쪽에 세로 칸을 내면 사람 · 이설 · ✕가 붙은 지도자 줄이 한 줄 늘어남 — 설계 1절 결정 1의 잰 값).
 *   결정 2 A  블록 메뉴 — 손잡이를 누르면 오른쪽 누름 메뉴(.ctx-menu)와 같은 꼴의 세로 메뉴: 복제 · 위로 · 아래로 · 다른 나라로 옮기기… · 종류 바꾸기 · 지우기.
 *             Shift+손잡이 = 여러 줄 함께 고르기 → 두 줄 맞바꾸기(기간은 그대로) · 기간만 맞바꾸기(같은 종류 두 줄) · 복제 · 다른 나라로 · 지우기.
 *   결정 3 C  끌기 — 메이커 안 끌기 한 꼴(HT.makerDrag.slot · js/maker-drag.js — 구조 나무 끌기와 같음): 빈 자리 + 빈 자리 안 미리 글.
 *             같은 목록 = 자리 옮기기 · 다른 목록 = 종류 바꾸기(지도자 ↔ 내각) · 연호로는 복사. 편집 창 여럿 사이는 첫 판에서 메뉴의 '다른 나라로 옮기기…'.
 *   결정 4 C  블록 폼 — 쓴 블록만 펼쳐 두고, 안 쓴 블록은 아래 칩(＋ 이름)으로 모두 늘어놓음. 블록 머리 = › · 이름 · 개수 · 한 줄 요약 · ＋.
 *             블록 = 폼의 접는 구역(details.adv) 하나씩 — 시대 폼의 '승계 · 지위 · 지도자 · 내각 · 연호 · 도읍' 한 덩이는 블록 여섯으로, 소속·예속 칸도 블록으로.
 *             이름(원어 등)은 블록으로 묶지 않습니다(이름 칸 바로 아래 명칭 목록 — D2 결정 6 A의 자리). 블록 차례는 프로그램이 정함(감독 확인거리 3).
 *             접은 블록은 작업실 설정(ht.maker.blocks — 파일에 안 들어감)으로 기억하고, 처음에는 쓴 블록이 펼쳐짐(예전에 적힌 구역이 열려 있던 것과 같게).
 *   결정 5 A  '/' 명령 — 글 칸 밖(손잡이 · 블록 머리 · 칩 · 단추에 초점)에서 '/' → 작은 펼침 목록(거름 칸 · ↑↓ · Enter · Esc). 글 칸 안의 '/'는 그대로 글자.
 *             있는 블록이면 '줄 더하기', 없으면 새 블록(칩을 누른 것과 같음).
 * 고침의 걸음: 폼 안의 고침(옮기기 · 복제 · 종류 바꾸기 · 맞바꾸기 · 지우기)은 다른 칸 고침과 같이 '저장하지 않은 고침'이 되고 저장 한 번이 되돌리기 한 걸음,
 * 두 항목에 걸치는 '다른 나라로 옮기기'는 작업본 고침 한 번(api.transact — 되돌리기 한 걸음 · 칸 문서도 따라감).
 * 다른 부품이 메뉴 · '/' 목록에 줄을 더하려면(함께 만드는 틀 · 작업 폴더 — 같은 판의 결정 6 · 7): HT.makerBlocks.extras.menu · .slash에 함수를 push.
 */
(function () {
  'use strict';
  const HT = window.HT;
  const esc = s => HT.escapeHtml(String(s ?? ''));
  const arr = v => (Array.isArray(v) ? v : []);
  const clone = x => JSON.parse(JSON.stringify(x));

  /* ---------- 줄 목록 ---------- */
  const LIST_SEL = '[data-cells], [data-succ], [data-parts]';
  const CELL_KINDS = new Set(['leaders', 'cabinets', 'eras', 'capitals', 'ranks', 'faiths']); // 종교(faiths — 6단계 D8 · 걸음 3)
  const KIND_WORD = { leaders: '지도자', cabinets: '내각', eras: '연호', capitals: '도읍', ranks: '지위', faiths: '종교', succ: '승계', parts: '소속' };
  /** 저장하면 시작 순으로 다시 놓이는 목록 (HT.sortCells — 칸 종류 표의 목록) */
  const SORTED = CELL_KINDS;
  const isRowEl = el => !!el && el.nodeType === 1 && (el.classList.contains('cell-row') || el.classList.contains('succ-row'));
  const rowsOf = list => [...list.children].filter(isRowEl);
  const listKind = list => (!list ? '' : list.dataset.cells || ('succ' in list.dataset ? 'succ' : 'parts' in list.dataset ? 'parts' : ''));
  const listOfRow = row => (row && row.parentElement && row.parentElement.matches(LIST_SEL) ? row.parentElement : null);
  const own = (row, cls) => {
    const el = row.querySelector(`:scope > .${cls}`);
    return el ? String(el.value || '').trim() : '';
  };
  const rowLabel = row => own(row, 'c-name') || own(row, 's-from') || own(row, 'c-temple') || own(row, 'c-title') || own(row, 'c-given');
  const rowYears = row => {
    const a = own(row, 'c-start');
    const b = own(row, 'c-end');
    return a && b ? `${a}–${b}` : a ? a : b ? `–${b}` : '';
  };
  const fire = form => form.dispatchEvent(new Event('input', { bubbles: true }));
  const isAddBtn = b => [...b.attributes].some(a => /^data-[a-z0-9-]+-add$/.test(a.name));
  const isDelBtn = b => [...b.attributes].some(a => /^data-[a-z0-9-]+-del$/.test(a.name));
  /** 줄 안의 줄이 아닌 곳의 ＋ (목록의 ＋ — 블록 머리 ＋ · 칩 · '/'가 같은 길로 줄을 더함) */
  const addBtnOf = box => [...box.querySelectorAll('button')].find(b => isAddBtn(b) && !b.disabled && !b.closest('summary, .cell-row, .succ-row, .alt-row, .phase-row, [data-cx]')) || null; // 블록 머리의 ＋(data-blk-add)는 빼고 — 목록 둘레의 ＋
  const delBtnOf = row => [...row.querySelectorAll('button')].find(b => isDelBtn(b) && b.closest('.cell-row, .succ-row') === row) || null;
  /** 줄 복제 — 칸의 값 · 고른 것 · 체크를 그대로 옮기고 id는 뗌 (js/form-keys.js의 Ctrl+D와 같은 꼴) */
  function cloneRow(row) {
    const copy = row.cloneNode(true);
    const from = [...row.querySelectorAll('input, select, textarea')];
    const to = [...copy.querySelectorAll('input, select, textarea')];
    from.forEach((f, i) => {
      const t = to[i];
      if (!t) return;
      if (f.type === 'checkbox' || f.type === 'radio') t.checked = f.checked;
      else t.value = f.value;
    });
    for (const x of [copy, ...copy.querySelectorAll('[id]')]) x.removeAttribute('id');
    for (const b of copy.querySelectorAll('[data-closing]')) {
      b.hidden = true;
      delete b.dataset.closing;
    }
    copy.classList.remove('is-picked', 'is-dragging');
    copy.style.overflow = '';
    return copy;
  }
  /** 줄 하나를 파일과 같은 꼴로 읽음 (core.js의 읽기 그대로 — 떼어 낸 사본으로). orig = 처음 채운 값(입력 칸의 기본값)으로 */
  function readRow(row, kind, orig = false) {
    const list = row.parentElement;
    const host = document.createElement('div');
    const box = document.createElement('div');
    for (const a of list.attributes) if (a.name.startsWith('data-')) box.setAttribute(a.name, a.value);
    box.append(orig ? row.cloneNode(true) : cloneRow(row));
    host.append(box);
    const problems = [];
    let item = null;
    if (CELL_KINDS.has(kind)) item = HT.readCellRows(host, kind, KIND_WORD[kind], problems)[0] || null;
    return { item, problems };
  }

  /* ---------- 종류 바꾸기 · 복사의 칸 표 (설계 2절 2 — 'HT.cellConvert' 제안을 메이커 쪽에 · 미리 글도 이 표에서) ---------- */
  const GROUP_KEYS = {
    name: ['name'],
    span: ['start', 'startAt', 'startUnknown', 'end', 'endAt', 'endUnknown'],
    house: ['house'],
    note: ['note'],
    alts: ['certainty', 'startRange', 'startRangeAt', 'endRange', 'endRangeAt', 'alternatives'],
    person: ['person'],
    names: ['names'],
    ordinal: ['ordinal', 'ordinalUnknown'],
    regnal: ['regnal'], // 이름 번호(6단계 D2) — 지도자 줄에만(내각 · 연호로 바꾸면 버림)
    temple: ['temple'],
    title: ['title'],
    given: ['given'],
    dynasty: ['dynasty'],
    rank: ['rank'],
    accession: ['accession'],
    parents: ['parents'],
    spouses: ['spouses'],
  };
  const GROUP_WORD = { name: '대표 이름', span: '기간', house: '가문', note: '메모', alts: '이설', person: '사람', names: '이름(원어 등)', ordinal: '대수', regnal: '이름 번호', temple: '묘호', title: '시호', given: '이름(휘)', dynasty: '왕조', rank: '지위', accession: '승계', parents: '부모', spouses: '배우자' };
  const KEEP_MOVE = ['name', 'span', 'house', 'note', 'alts', 'person', 'names'];
  const KEEP_ERA = ['name', 'span', 'note', 'names'];
  const CONVERT = {
    leaders: { cabinets: { mode: 'move', keep: KEEP_MOVE }, eras: { mode: 'copy', keep: KEEP_ERA } },
    cabinets: { leaders: { mode: 'move', keep: KEEP_MOVE }, eras: { mode: 'copy', keep: KEEP_ERA } },
  };
  const filled = v => v != null && v !== '' && v !== false && !(Array.isArray(v) && !v.length);
  const groupsIn = item => Object.keys(GROUP_KEYS).filter(g => !!item && GROUP_KEYS[g].some(k => filled(item[k])));
  /** 줄(읽은 꼴) → 다른 종류의 줄(읽은 꼴): 표의 칸만 */
  function convertItem(item, from, to) {
    const c = (CONVERT[from] || {})[to];
    if (!c) return null;
    const out = {};
    for (const g of c.keep) for (const k of GROUP_KEYS[g]) if (item && k in item) out[k] = clone(item[k]);
    return out;
  }
  /** 종류 바꾸기의 미리 글 (끌 때 빈 자리 안 · 메뉴와 같은 말) — 버리는 칸은 이 줄에 적힌 것만 */
  function convertText(item, from, to, copy) {
    const c = (CONVERT[from] || {})[to];
    if (!c) return '';
    const has = groupsIn(item);
    const kept = c.keep.filter(g => has.includes(g));
    const dropped = has.filter(g => !c.keep.includes(g));
    const asCopy = copy || c.mode === 'copy';
    const head = asCopy ? `놓으면 ${KIND_WORD[to]} 줄로 복사합니다` : `놓으면 ${KIND_WORD[to]} 줄로 바뀝니다`;
    const what = kept.length ? `${kept.map(g => GROUP_WORD[g]).join(' · ')}만 ${asCopy ? '옮겨 적' : '옮기'}고` : '적힌 칸 없이';
    const tail = dropped.length ? `${dropped.map(g => GROUP_WORD[g]).join(' · ')}${asCopy ? '은 옮기지 않습니다' : '는 버립니다'}` : asCopy ? `${KIND_WORD[from]} 줄은 그대로 둡니다` : '버리는 칸은 없습니다';
    return `${head} — ${what}, ${tail}${!asCopy ? ' · Ctrl을 누른 채 놓으면 복사' : ''}`;
  }

  /* ---------- 블록 표 (결정 4 C) ---------- */
  /** 시대 폼의 '승계 · 지위 · 지도자 · 내각 · 연호 · 도읍' 한 덩이와 소속 칸 → 블록 하나씩 (목록 자리로 알아봄) */
  const LIST_BLOCKS = [
    { id: 'parts', name: '소속·예속', list: '[data-parts]', group: '관계' },
    { id: 'succ', name: '승계', list: '[data-succ]', group: '관계' },
    { id: 'ranks', name: '지위 변천', list: '[data-cells="ranks"]', group: '칸 묶음' },
    { id: 'faiths', name: '종교', list: '[data-cells="faiths"]', group: '칸 묶음' }, // 6단계 D8 · 걸음 3
    { id: 'leaders', name: '지도자', list: '[data-cells="leaders"]', group: '칸 묶음' },
    { id: 'cabinets', name: '내각', list: '[data-cells="cabinets"]', group: '칸 묶음' },
    { id: 'eras', name: '연호', list: '[data-cells="eras"]', group: '칸 묶음' },
    { id: 'capitals', name: '도읍', list: '[data-cells="capitals"]', group: '칸 묶음' },
  ];
  /** 접는 구역(details.adv[data-adv]) → 블록 이름 · '/' 무리. 모르는 구역(뒤에 더해질 구역)은 요약 글의 ' — ' 앞을 이름으로 */
  const ADV = {
    northSouth: { name: '남북 위치', group: '규격' }, // D4의 독립 구역도 D3의 이름 있는 칩과 같은 분류로.
    phases: { name: '시기 구분', group: '칸 묶음' },
    kin: { name: '가족', group: '관계' },
    links: { name: '묶기', group: '관계' },
    dates: { name: '연대', group: '이름 · 글' },
    views: { name: '나라마다 다른 이름', group: '이름 · 글' },
    treaty: { name: '조약 규격', group: '규격' },
    lens: { name: '주제 · 법 · 선거', group: '규격' },
    wiki: { name: '문서', group: '이름 · 글' },
  };
  /** '/' 목록에서 아직 없는 블록 옆의 짧은 풀이 (있는 블록은 '있음 · 줄 더하기') */
  const TAG = { parts: '상위 정권 · 기간', succ: '이어받은 정권', ranks: '정권의 지위가 바뀐 차례', faiths: '국교 · 공식 신앙이 바뀐 차례', leaders: '대수 · 이름 · 기간', cabinets: '내각 이름과 기간', eras: '선포한 연호', capitals: '수도와 그 역할', phases: '학계가 나눈 시기', kin: '부모 · 배우자', links: '상위 사건 · 관련 인물', dates: '확실성 · 연대 폭 · 이설', views: '나라마다 다른 이름', treaty: '정식 명칭 · 당사국 · 조항', lens: '주제 · 법 · 선거', wiki: '나무위키 문법' };
  const SKIP_ADV = new Set(['names']); // 이름(원어 등) — 블록으로 묶지 않음 (이름 칸 아래 명칭 목록 자리)
  const ORDER = ['parts', 'succ', 'ranks', 'faiths', 'leaders', 'cabinets', 'eras', 'capitals', 'northSouth', 'phases', 'kin', 'links', 'dates', 'views', 'treaty', 'lens', 'wiki'];
  const GROUPS = ['칸 묶음', '관계', '이름 · 글', '규격', '틀', '그 밖']; // '틀' = 함께 만드는 틀(결정 6 — js/maker-templates.js가 extras.slash로 더함 · 판 d5-a의 무리)
  const KEY = 'ht.maker.blocks'; // 작업실 설정: { closed: [블록 열쇠 …] } — 사람이 접어 둔 블록
  const loadUi = () => {
    try {
      const v = HT.store.get(KEY, null);
      return { closed: new Set(arr(v && v.closed).filter(x => typeof x === 'string')) };
    } catch (e) {
      return { closed: new Set() };
    }
  };
  const ui = loadUi();
  const saveUi = () => {
    try {
      HT.store.set(KEY, { closed: [...ui.closed] });
    } catch (e) {
      /* 저장소가 막힌 곳 — 이번 창에서만 */
    }
  };

  const fieldsOf = form => form.querySelector('#editorFields') || form;
  const blocksOf = form => [...fieldsOf(form).querySelectorAll(':scope > .mk-blocks details.mk-blk')];
  const blockById = (form, id) => blocksOf(form).find(b => b.dataset.blk === id) || null;
  const blockList = b => b.querySelector(LIST_SEL);
  const headHTML = (name, hint, list) => `<b>${esc(name)}</b><span class="n"></span><span class="sum"></span>${list ? `<button type="button" class="mk-blk-add" data-blk-add aria-label="${esc(name)} 줄 더하기" title="${esc(name)} 줄 더하기">＋</button>` : ''}`;
  /** 폼을 블록으로 묶음 (한 번만 — 다시 부르면 아무것도 하지 않고 기존 블록을 돌려줌) */
  function build(form) {
    const fields = fieldsOf(form);
    const had = fields.querySelector(':scope > .mk-blocks');
    if (had) return had;
    const advs = [...fields.querySelectorAll(':scope > details.adv[data-adv]')].filter(d => !SKIP_ADV.has(d.dataset.adv));
    const parts = fields.querySelector(':scope > .field > [data-parts][data-relation]'); // 시대 폼의 소속·예속만 (기관 · 왕조의 '얹히는 · 다스린 정권'은 꼭 적는 칸이라 블록으로 묶지 않음)
    if (!advs.length && !parts) return null;
    const box = document.createElement('div');
    box.className = 'mk-blocks field-wide';
    box.dataset.blocks = '';
    fields.append(box); // 폼 끝에 — 기본 칸(이름 · 기간 · 트랙 … · 설명 · 태그 · 출처) 아래에 블록 줄, 그 아래 칩
    const made = [];
    const listBlock = (def, field, into = null) => {
      const d = document.createElement('details');
      d.className = `field-wide adv mk-blk${def.single ? '' : ' is-list'}`;
      d.dataset.adv = `blk-${def.id}`;
      d.dataset.blk = def.id;
      d.dataset.group = def.group;
      const cap = field.querySelector(':scope > span');
      const hint = cap ? cap.textContent.replace(/\s+/g, ' ').trim() : def.name;
      d.innerHTML = `<summary class="mk-blk-head" title="${esc(hint)}">${headHTML(def.name, hint, !def.single)}</summary><div class="adv-body mk-blk-body"></div>`;
      if (into) field.before(d);
      d.querySelector('.mk-blk-body').append(field);
      d.dataset.fillOpen = '';
      if (!into) made.push(d);
    };
    if (parts) listBlock(LIST_BLOCKS[0], parts.parentElement);
    for (const adv of advs) {
      if (adv.dataset.adv === 'cells') {
        /* 한 덩이를 목록마다 블록으로 — 블록 여섯은 그 구역 안 제자리에 두고, 구역은 늘 펼친 투명한 그릇(머리 없음)으로.
           그래서 구역(details[data-adv="cells"])을 찾아 다루던 길(채우기 · 줄 묶음 붙여넣기 …)은 그대로 그 안의 목록에 닿음 */
        for (const def of LIST_BLOCKS.slice(1)) {
          const host = adv.querySelector(def.list);
          const field = host && host.closest('.field');
          if (field && adv.contains(field)) listBlock(def, field, adv);
        }
        // D4가 같은 구역에 더한 낱칸도 쓴 블록/안 쓴 칩 규칙에 넣어 빈 목록 때문에 숨지 않게 합니다.
        const north = adv.querySelector('[name="northSouth"]');
        if (north) listBlock({ id: 'northSouth', name: '남북 위치', group: '규격', single: true }, north.closest('.field'), adv);
        adv.classList.add('mk-blk-group');
        adv.open = true;
        made.push(adv);
        continue;
      }
      const id = adv.dataset.adv;
      const sum = adv.querySelector(':scope > summary');
      const full = sum ? sum.textContent.replace(/\s+/g, ' ').trim() : id;
      const def = ADV[id] || { name: full.split(' — ')[0], group: '그 밖' };
      const name = id === 'dates' && /실재/.test(full) ? '연대 · 실재성' : def.name;
      adv.classList.add('mk-blk');
      adv.dataset.blk = id;
      adv.dataset.group = def.group;
      if (sum) {
        sum.classList.add('mk-blk-head');
        sum.title = full;
        sum.innerHTML = headHTML(name, full, false);
      }
      adv.dataset.fillOpen = adv.open ? '1' : '';
      made.push(adv);
    }
    const rank = b => {
      const i = ORDER.indexOf(b.classList.contains('mk-blk-group') ? 'succ' : b.dataset.blk);
      return i < 0 ? ORDER.length + made.indexOf(b) : i;
    };
    made.sort((a, b) => rank(a) - rank(b));
    box.append(...made);
    box.insertAdjacentHTML('beforeend', '<div class="mk-blk-chips" hidden></div>');
    return box;
  }
  const textFilled = b => [...b.querySelectorAll('input:not([type]), input[type="text"], input[type="search"], input[type="number"], input[type="url"], textarea')].some(f => String(f.value || '').trim());
  /** 블록 머리의 개수 · 한 줄 요약 · '쓴 블록'인지 */
  function describe(b) {
    const list = blockList(b);
    if (list) {
      const rows = rowsOf(list);
      const items = rows.map(r => [rowLabel(r), rowYears(r)].filter(Boolean).join(' ')).filter(Boolean);
      const sum = items.length > 3 ? `${items[0]} → ${items[items.length - 1]}` : items.join(' · ');
      return { n: rows.length, sum, used: rows.length > 0 };
    }
    const id = b.dataset.blk;
    if (id === 'northSouth') {
      const value = b.querySelector('[name="northSouth"]').value;
      return { n: '', sum: value === '' ? '' : `남북 위치 ${value}`, used: value !== '' };
    }
    if (id === 'phases') {
      const schemes = [...b.querySelectorAll('.phase-scheme')];
      const names = schemes.map(s => ((s.querySelector('.ps-name') || {}).value || '').trim() || [...s.querySelectorAll('.phase-row .c-name')].map(x => x.value.trim()).filter(Boolean).slice(0, 3).join(' · ')).filter(Boolean);
      return { n: schemes.length, sum: names.join(' · '), used: schemes.length > 0 };
    }
    if (id === 'wiki') {
      const ta = b.querySelector('textarea[name="wiki"]');
      const text = ta ? ta.value : '';
      const heads = [...text.matchAll(/^\s*(=+)\s*(.+?)\s*\1\s*$/gm)].map(m => m[2]);
      const first = text.trim().split('\n')[0] || '';
      return { n: heads.length || '', sum: heads.length ? heads.join(' · ') : first.slice(0, 60), used: !!text.trim() };
    }
    const bits = [];
    const opt = sel => {
      const el = b.querySelector(sel);
      return el && el.selectedOptions && el.selectedOptions[0] ? el.selectedOptions[0].textContent.split(' — ')[0].trim() : '';
    };
    if (id === 'dates') {
      const c = b.querySelector('[name="certainty"]');
      if (c && c.value && c.value !== 'accepted') bits.push(opt('[name="certainty"]'));
      const h = b.querySelector('[name="historicity"]');
      if (h && h.value) bits.push(opt('[name="historicity"]'));
      const alts = b.querySelectorAll('[data-alts] > .alt-row').length;
      if (alts) bits.push(`이설 ${alts}`);
      if ([...b.querySelectorAll('input[name^="range"], input[name^="endFrom"], input[name^="endTo"]')].some(f => (!f.type || f.type === 'text' || f.type === 'number') && f.value && f.value.trim())) bits.push('연대 폭');
      const deb = b.querySelector('[name="debate"]');
      if (deb && deb.value.trim()) bits.push('논쟁 메모');
    }
    const rows = [...b.querySelectorAll('*')].filter(el => [...el.classList].some(c => /-row$/.test(c)) && el.parentElement && [...el.parentElement.classList].some(c => /-rows$/.test(c)) && !el.parentElement.closest('.cell-row, .succ-row, .alt-row'));
    if (!bits.length) {
      const vals = [...b.querySelectorAll('input:not([type]), input[type="text"], textarea')].map(f => String(f.value || '').trim()).filter(Boolean);
      bits.push(...vals.slice(0, 3).map(v => (v.length > 24 ? `${v.slice(0, 24)}…` : v)));
    }
    return { n: rows.length || '', sum: bits.join(' · '), used: b.dataset.fillOpen === '1' || rows.length > 0 || textFilled(b) };
  }
  function paintHead(b, info = describe(b)) {
    const n = b.querySelector(':scope > summary .n');
    const s = b.querySelector(':scope > summary .sum');
    if (n && n.textContent !== String(info.n)) n.textContent = String(info.n);
    if (s && s.textContent !== info.sum) s.textContent = info.sum;
  }
  function paintChips(form) {
    const box = fieldsOf(form).querySelector(':scope > .mk-blocks');
    const chips = box && box.querySelector(':scope > .mk-blk-chips');
    if (!chips) return;
    const hidden = blocksOf(form).filter(b => b.hidden);
    chips.hidden = !hidden.length;
    const html = hidden.length ? `<span class="lbl"><span>블록 더하기</span><span><kbd class="mk-kbd">/</kbd> 로도 고릅니다</span></span>${hidden.map(b => `<button type="button" class="chip is-add mk-blk-chip" data-blk-chip="${esc(b.dataset.blk)}" title="${esc(b.querySelector(':scope > summary').title || '')}">＋ ${esc(b.querySelector(':scope > summary b').textContent)}</button>`).join('')}` : '';
    if (chips.innerHTML !== html) chips.innerHTML = html;
  }
  /** 채운 직후: 쓴 블록만 보이고(처음엔 펼침 — 사람이 접어 둔 블록은 접음), 안 쓴 블록은 칩으로 */
  function settle(form) {
    for (const g of fieldsOf(form).querySelectorAll(':scope > .mk-blocks > details.mk-blk-group')) g.open = true; // 그릇은 늘 펼침 (채우기가 접어도)
    for (const b of blocksOf(form)) {
      if (b.dataset.adv && b.dataset.adv.startsWith('blk-')) b.dataset.fillOpen = '';
      else b.dataset.fillOpen = b.open ? '1' : '';
      const info = describe(b);
      b.hidden = !info.used;
      delete b.dataset.shown;
      b.open = info.used && !ui.closed.has(b.dataset.blk);
      paintHead(b, info);
    }
    paintChips(form);
  }
  /** 블록을 드러내 펼침 (칩 · '/' · 끌어 놓기) — row: 목록이면 ＋로 줄 하나를 더함 */
  function reveal(form, b, { row = true, focus = true } = {}) {
    b.hidden = false;
    b.dataset.shown = '1';
    b.open = true;
    ui.closed.delete(b.dataset.blk);
    saveUi();
    paintChips(form);
    const list = blockList(b);
    const add = list && row ? addBtnOf(b) : null;
    if (add) add.click(); // 그 목록의 ＋와 같은 길 (새 줄의 첫 칸에 초점)
    else if (focus) {
      const f = [...b.querySelectorAll('input, select, textarea, button')].find(x => !x.closest('summary') && !x.disabled && x.getClientRects().length);
      if (f) f.focus();
    }
    paintHead(b);
  }

  /* ---------- 손잡이 (결정 1 B) ---------- */
  const GRIP = '<button type="button" class="mk-grip" aria-haspopup="menu" aria-expanded="false" aria-label="줄 손잡이 — 누르면 메뉴 · 끌면 옮기기 · Shift+누름은 여러 줄 고르기" title="누르면 메뉴 · 끌면 옮기기 · Shift+누름 = 여러 줄 고르기">⋮⋮</button>';
  function ensureGrips(form) {
    for (const list of fieldsOf(form).querySelectorAll(LIST_SEL)) for (const row of rowsOf(list)) if (!row.querySelector(':scope > .mk-grip')) row.insertAdjacentHTML('afterbegin', GRIP);
  }

  /* ---------- 떠 있는 목록 (블록 메뉴 · 나라 고르기 · '/' 상자 — 오른쪽 누름 메뉴 .ctx-menu와 같은 꼴) ---------- */
  let menuEl = null;
  let menu = null;
  function menuNode() {
    if (menuEl) return menuEl;
    menuEl = document.body.appendChild(Object.assign(document.createElement('div'), { className: 'ctx-menu mk-bmenu', hidden: true }));
    menuEl.setAttribute('role', 'menu');
    menuEl.addEventListener('keydown', onMenuKey);
    menuEl.addEventListener('click', e => {
      const b = e.target.closest('.ctx-item');
      if (!b || !menu || b.classList.contains('is-disabled')) return;
      runItem(Number(b.dataset.i), e);
    });
    menuEl.addEventListener('pointermove', e => {
      const b = e.target.closest('.ctx-item');
      if (!b || !menu || !menu.find || b.classList.contains('is-disabled')) return;
      setActive(Number(b.dataset.i));
    });
    menuEl.addEventListener('input', e => {
      if (!menu || !e.target.matches('.mk-find input')) return;
      menu.query = e.target.value;
      menu.active = -1;
      paintList();
    });
    document.addEventListener('pointerdown', e => menu && !menuEl.contains(e.target) && closeMenu(false), true);
    window.addEventListener('blur', () => closeMenu(false));
    return menuEl;
  }
  const entryHTML = (it, i) => {
    if (it.sep) return '<div class="ctx-sep"></div>';
    if (it.title) return `<div class="ctx-title">${esc(it.title)}</div>`;
    return `<button type="button" class="ctx-item${it.disabled ? ' is-disabled' : ''}${it.danger ? ' is-danger' : ''}${it.warn ? ' is-warn' : ''}" role="menuitem" data-i="${i}"${it.disabled ? ' aria-disabled="true"' : ''}>${it.dot ? `<span class="mk-dot" style="--c:${esc(it.dot)}" aria-hidden="true"></span>` : ''}<span class="ctx-label">${esc(it.label)}${it.isNew ? ' <span class="mk-new">새</span>' : ''}</span>${it.sub ? `<span class="mk-sub">${esc(it.sub)}</span>` : ''}${it.key ? `<span class="ctx-key">${esc(it.key)}</span>` : ''}</button>`;
  };
  function paintList() {
    const list = menu.list();
    menu.shown = list;
    const box = menuEl.querySelector('.mk-mlist');
    const runs = list.map((it, i) => (it.label != null && !it.disabled ? i : -1)).filter(i => i >= 0);
    box.innerHTML = list.length ? list.map(entryHTML).join('') : `<p class="mk-mnone">${esc(menu.none || '맞는 것이 없습니다')}</p>`;
    if (menu.find) setActive(menu.active >= 0 && runs.includes(menu.active) ? menu.active : runs[0] ?? -1);
  }
  function setActive(i) {
    menu.active = i;
    for (const b of menuEl.querySelectorAll('.ctx-item')) b.classList.toggle('is-on', Number(b.dataset.i) === i);
    const on = menuEl.querySelector('.ctx-item.is-on');
    if (on) on.scrollIntoView({ block: 'nearest' });
  }
  function openMenu(o) {
    const el = menuNode();
    if (o.ctx && o.ctx.cmd && o.ctx.cmd.hideMenu) o.ctx.cmd.hideMenu(); // 연표의 오른쪽 누름 메뉴는 닫음 — 떠 있는 목록은 하나만
    closeMenu(false);
    menu = Object.assign({ query: '', active: -1 }, o);
    el.classList.toggle('is-find', !!o.find);
    el.style.width = o.width ? `${o.width}px` : '';
    const lead = o.lead === '/' ? '<span class="mk-find-lead" aria-hidden="true">/</span>' : '<svg class="mk-find-lead" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>';
    el.innerHTML = `${o.find ? `<div class="mk-find">${lead}<input type="text" autocomplete="off" spellcheck="false" aria-label="${esc(o.find)}"><span class="hint">${esc(o.findHint || 'Enter 고르기 · Esc 닫기')}</span></div>` : ''}${o.title ? `<div class="ctx-title">${esc(o.title)}</div>` : ''}<div class="mk-mlist" role="none"></div>${o.foot ? `<div class="ctx-foot">${esc(o.foot)}</div>` : ''}`;
    el.hidden = false;
    paintList();
    if (o.opener) o.opener.setAttribute('aria-expanded', 'true');
    /* 자리: 여는 것의 아래(자리가 모자라면 위) — 화면 안으로 */
    el.style.left = '0px';
    el.style.top = '0px';
    const r = el.getBoundingClientRect();
    const a = o.anchor ? o.anchor.getBoundingClientRect() : { left: o.x, right: o.x, top: o.y, bottom: o.y };
    let y = a.bottom + 4;
    if (y + r.height > innerHeight - 8 && a.top - 4 - r.height >= 8) y = a.top - 4 - r.height;
    el.style.left = `${Math.max(4, Math.min(a.left, innerWidth - r.width - 4))}px`;
    el.style.top = `${Math.max(4, Math.min(y, innerHeight - r.height - 4))}px`;
    const first = o.find ? el.querySelector('.mk-find input') : el.querySelector('.ctx-item:not(.is-disabled)');
    if (first) first.focus({ preventScroll: true });
  }
  function closeMenu(focusBack) {
    if (!menu) return;
    const m = menu;
    menu = null;
    menuEl.hidden = true;
    menuEl.innerHTML = '';
    if (m.opener) {
      m.opener.setAttribute('aria-expanded', 'false');
      if (focusBack && m.opener.isConnected) m.opener.focus({ preventScroll: true });
    }
    if (m.onClose) m.onClose();
  }
  function runItem(i, ev) {
    const it = menu && menu.shown && menu.shown[i];
    if (!it || it.disabled || !it.run) return;
    const back = !it.keepFocus;
    closeMenu(back);
    it.run(ev || {});
  }
  function onMenuKey(e) {
    if (!menu) return;
    const items = [...menuEl.querySelectorAll('.ctx-item:not(.is-disabled)')];
    const k = e.key;
    if (k === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      return closeMenu(true);
    }
    if (k === 'Tab') return closeMenu(false);
    if (k === 'ArrowDown' || k === 'ArrowUp' || k === 'Home' || k === 'End') {
      e.preventDefault();
      e.stopPropagation();
      if (!items.length) return;
      if (menu.find) {
        const at = items.findIndex(b => b.classList.contains('is-on'));
        const n = k === 'Home' ? 0 : k === 'End' ? items.length - 1 : (at + (k === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
        return setActive(Number(items[n].dataset.i));
      }
      const at = items.indexOf(document.activeElement);
      const n = k === 'Home' ? 0 : k === 'End' ? items.length - 1 : (at + (k === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      return items[n].focus();
    }
    if (k === 'Enter' && menu.find && !e.isComposing && e.keyCode !== 229) {
      e.preventDefault();
      e.stopPropagation();
      if (menu.active >= 0) runItem(menu.active, e);
    }
  }

  /* ---------- 화면 붙이기 ---------- */
  function mount(ctx, api) {
    const form = document.getElementById('editorForm');
    if (!form || form.dataset.blocks) return null;
    form.dataset.blocks = '1';
    const fields = fieldsOf(form);
    const state = ctx.state;
    let picks = new Set();
    const pickedRows = () => [...picks].filter(r => r.isConnected && listOfRow(r));
    const clearPicks = () => {
      for (const r of picks) r.classList.remove('is-picked');
      picks = new Set();
    };

    /** 폼을 블록으로 (채울 때마다 — 같은 폼을 두 번 채우면 블록은 그대로 두고 보임만 다시) */
    function apply(f = form) {
      if (f !== form) return;
      build(form);
      settle(form);
      ensureGrips(form);
      clearPicks();
    }
    /* HT.FORMS[종류].fill을 감쌈: 채운 바로 뒤에 블록으로 묶어, 편집 창이 그다음에 하는 일(펼쳐 두던 구역 · 스크롤 · 초점 되돌리기)이 블록 위에서 일어나게 */
    function wrapForms() {
      for (const F of Object.values(HT.FORMS || {})) {
        if (!F || typeof F.fill !== 'function' || F.fill.__blocks) continue;
        const orig = F.fill;
        const fill = function (f, ...rest) {
          const out = orig.call(this, f, ...rest);
          if (f === form) apply(f);
          return out;
        };
        fill.__blocks = true;
        F.fill = fill;
      }
    }
    wrapForms();
    /* 감싸지 못한 폼(뒤에 더해진 종류)이나 줄을 더한 뒤: 손잡이 · 머리 글을 맞춤 (블록은 다음 일 차례에) */
    let queued = false;
    const tidy = () => {
      queued = false;
      if (!fields.querySelector(':scope > .mk-blocks') && fields.querySelector(':scope > details.adv[data-adv]')) apply(form);
      ensureGrips(form);
      for (const b of blocksOf(form)) paintHead(b);
      if (menu && menu.opener && !menu.opener.isConnected) closeMenu(false);
    };
    new MutationObserver(() => {
      if (!queued) {
        queued = true;
        queueMicrotask(tidy);
      }
    }).observe(fields, { childList: true, subtree: true });
    /* 숨은(안 쓴) 블록을 누군가 펼치면(편집 창이 저장 뒤 펼쳐 두던 구역을 다시 펼침 · 다른 부품 · 검사가 구역을 엶) 그 블록을 드러냄 —
       toggle 사건은 한 박자 늦게 오므로 open 속성을 지켜봄(같은 일 차례 안에서 곧장) */
    new MutationObserver(records => {
      let any = false;
      for (const r of records) {
        const b = r.target;
        if (!b.matches('details.mk-blk') || !b.open || !b.hidden) continue;
        b.hidden = false;
        b.dataset.shown = '1';
        any = true;
      }
      if (any) paintChips(form);
    }).observe(fields, { subtree: true, attributes: true, attributeFilter: ['open'] });
    let headRaf = 0;
    form.addEventListener('input', () => {
      if (headRaf) return;
      headRaf = requestAnimationFrame(() => {
        headRaf = 0;
        for (const b of blocksOf(form)) paintHead(b);
      });
    });

    /* ---------- 줄 다루기 (메뉴 · 끌기가 같은 함수를 부름) ---------- */
    const kindOf = row => listKind(listOfRow(row));
    function step(row, dir) {
      const list = listOfRow(row);
      const rows = rowsOf(list);
      const other = rows[rows.indexOf(row) + dir];
      if (!other) return false;
      if (dir < 0) list.insertBefore(other, row.nextSibling);
      else list.insertBefore(other, row);
      fire(form);
      return true;
    }
    function duplicate(rows) {
      let last = null;
      for (const row of rows) {
        const copy = cloneRow(row);
        row.after(copy);
        last = copy;
      }
      fire(form);
      return last;
    }
    function remove(rows) {
      const list = listOfRow(rows[0]);
      const at = list ? rowsOf(list).indexOf(rows[0]) : -1;
      for (const row of rows) {
        const del = delBtnOf(row);
        if (del) del.click(); // 그 줄의 ✕와 같은 길 (폼에 input도 그쪽이 쏨)
      }
      /* 초점: 그 자리의 다음 줄(없으면 앞 줄)의 손잡이 · 목록이 비면 ＋ — 초점이 body로 떨어져 글자가 연표 단축키로 새지 않게 */
      if (!list || !list.isConnected) return;
      const left = rowsOf(list);
      const near = left[at] || left[at - 1];
      const target = near ? near.querySelector(':scope > .mk-grip') : addBtnOf(list.closest('details.mk-blk') || list.parentElement);
      if (target) target.focus({ preventScroll: true });
    }
    /** 두 노드의 자리를 맞바꿈 */
    function swapNodes(a, b) {
      const mark = document.createComment('');
      a.replaceWith(mark);
      b.replaceWith(a);
      mark.replaceWith(b);
    }
    /** 두 줄의 기간(시작 · 끝 · 미정의 배치용 연도 · 그 줄의 이설 상자 — 확실성 · 연대 폭 · 이설)만 맞바꿈 */
    function swapSpan(a, b) {
      for (const cls of ['c-start', 'c-end']) {
        const x = a.querySelector(`:scope > .${cls}`);
        const y = b.querySelector(`:scope > .${cls}`);
        if (x && y) [x.value, y.value] = [y.value, x.value];
      }
      for (const k of ['startHint', 'endHint']) {
        const va = a.dataset[k];
        const vb = b.dataset[k];
        if (vb == null) delete a.dataset[k];
        else a.dataset[k] = vb;
        if (va == null) delete b.dataset[k];
        else b.dataset[k] = va;
      }
      const xa = a.querySelector(':scope > .cell-alts');
      const xb = b.querySelector(':scope > .cell-alts');
      if (xa && xb) {
        swapNodes(xa, xb);
        for (const row of [a, b]) {
          const box = row.querySelector(':scope > .cell-alts');
          const btn = row.querySelector(':scope > .row-end > [data-calt-toggle]');
          if (btn && box) {
            btn.setAttribute('aria-expanded', String(!box.hidden));
            btn.classList.toggle('is-open', !box.hidden);
          }
          if (HT.syncCellAlts) HT.syncCellAlts(row);
        }
      }
    }
    function swap(a, b, spanOnly) {
      const was = document.activeElement;
      if (!spanOnly) swapNodes(a, b); // 두 줄 맞바꾸기(기간은 그대로) = 자리를 바꾸고 기간만 되돌림
      swapSpan(a, b);
      fire(form);
      if (was && was.isConnected && document.activeElement !== was) was.focus({ preventScroll: true }); // 줄을 옮기며 잃은 초점을 그 손잡이에 되돌림
    }
    /** 종류 바꾸기(같은 폼 안): 줄을 읽어 표의 칸만 다른 목록의 새 줄로 · copy면 원래 줄은 둠. at = { anchor, where } (없으면 그 목록 끝) */
    function convert(rows, to, copy, at = null) {
      const target = fields.querySelector(`[data-cells="${to}"]`);
      if (!target) return HT.toast(`이 폼에는 ${KIND_WORD[to]} 목록이 없습니다.`, 'error');
      const made = [];
      let copied = false;
      for (const row of rows) {
        const from = kindOf(row);
        const read = readRow(row, from);
        if (read.problems.length) return HT.toast(`바꾸지 못했습니다 — ${read.problems[0]}`, 'error');
        const c = (CONVERT[from] || {})[to];
        if (!c) return HT.toast(`${KIND_WORD[from]} 줄은 ${KIND_WORD[to]} 줄로 바꿀 수 없습니다.`, 'error');
        const tmp = document.createElement('div');
        tmp.innerHTML = HT.cellRowHTML(to, HT.formCell(to, convertItem(read.item || {}, from, to)));
        const fresh = tmp.firstElementChild;
        if (at && at.anchor && isRowEl(at.anchor) && listOfRow(at.anchor) === target) at.where === 'before' ? at.anchor.before(fresh) : at.anchor.after(fresh);
        else target.append(fresh);
        if (at) at = { anchor: fresh, where: 'after' }; // 여러 줄이면 차례대로 그 뒤에
        made.push(fresh);
        if (c.mode === 'move' && !copy) row.remove();
        else copied = true;
      }
      const b = target.closest('details.mk-blk');
      if (b && (b.hidden || !b.open)) reveal(form, b, { row: false, focus: false });
      ensureGrips(form);
      fire(form);
      const g = made[0] && made[0].querySelector(':scope > .mk-grip');
      if (g) g.focus({ preventScroll: true });
      if (made[0]) made[0].scrollIntoView({ block: 'nearest' });
      const word = made.length > 1 ? `줄 ${made.length}개를` : `«${rowLabel(made[0]) || '이름 없음'}»을(를)`;
      HT.toast(`${word} ${KIND_WORD[to]} 줄로 ${copied ? '복사했습니다' : '바꿨습니다'} — 저장하면 반영됩니다.`, 'ok');
      return made;
    }

    /* ---------- 다른 나라로 옮기기 (두 항목에 걸침 — 작업본 고침 한 번 · 되돌리기 한 걸음) ---------- */
    const D = HT.draft;
    const num = v => (v == null || v === '' ? null : Number(v));
    const rowKey = (c, kind) => {
      const f = HT.formCell(kind, (HT.makerGrid && HT.makerGrid.objectRow ? HT.makerGrid.objectRow(c, kind) : c) || {}) || {};
      return JSON.stringify([kind === 'capitals' ? f.city ?? f.name ?? '' : f.name ?? '', num(f.start), num(f.end)]);
    };
    const listKey = (item, kind) => (kind === 'leaders' && !Array.isArray(item.leaders) && Array.isArray(item.reigns) ? 'reigns' : kind);
    /** 고칠 원본: 제 항목은 작업본의 그 자리, 남의 항목(잠김을 푼 불러온 팩)은 사본 → 끝에 바뀐 칸만 덮어쓰기로 (구조 나무 끌기와 같은 길) */
    function editable(draft, x) {
      const mine = D.isOwnUid(draft, x.uid) && D.findOwn(draft, x.uid.slice(draft.id.length + 1));
      if (mine) return { item: mine.item, done() {} };
      if (api.isLocked(x)) throw Error(`잠긴 팩 «${x.packName}»의 나라라 고칠 수 없습니다.`);
      const before = api.rawOf(x);
      const after = clone(before);
      return { item: after, done: () => HT.makerGrid.patchItem(draft, api.baseModel().byUid.get(x.uid) || x, before, after) };
    }
    /** 칸 문서(cell:나라:종류:이름@해)도 그 나라로 따라감 — copy면 복사 */
    function carryDocs(draft, fromUid, toUid, kind, cell, copy) {
      const c = HT.formCell(kind, (HT.makerGrid.objectRow ? HT.makerGrid.objectRow(cell, kind) : cell) || {}) || {};
      const name = kind === 'capitals' ? c.city || c.name : c.name;
      if (!name || !Number.isFinite(Number(c.start))) return;
      const want = { name, start: Number(c.start) };
      const base = HT.docKey.cell(fromUid, kind, want);
      const moves = [];
      for (const key of Object.keys(draft.documents || {})) {
        const abs = HT.docKey.absolute(key, draft.id);
        const p = HT.docKey.split(abs);
        if (p.base !== base) continue;
        moves.push([key, HT.docKey.relative(HT.docKey.join(HT.docKey.cell(toUid, kind, want), p.sub), draft.id), draft.documents[key]]);
      }
      for (const [key, to, text] of moves) {
        if (Object.hasOwn(draft.documents, to)) continue; // 같은 이름의 문서가 이미 있으면 그대로 둠
        if (!copy) delete draft.documents[key];
        draft.documents[to] = text;
      }
    }
    async function moveToPolity(rows, target, copy) {
      const srcUid = state.editing;
      const src = srcUid && (state.model.byUid.get(srcUid) || null);
      if (!src) return HT.toast('새 항목은 먼저 저장해야 다른 나라로 옮길 수 있습니다.', 'error');
      const picks0 = rows.map(row => ({ kind: kindOf(row), cur: readRow(row, kindOf(row)), orig: readRow(row, kindOf(row), true) }));
      const bad = picks0.find(p => p.cur.problems.length);
      if (bad) return HT.toast(`옮기지 못했습니다 — ${bad.cur.problems[0]}`, 'error');
      const word = picks0.length > 1 ? `줄 ${picks0.length}개` : `${KIND_WORD[picks0[0].kind]} 줄 «${(picks0[0].cur.item && (picks0[0].cur.item.name || picks0[0].cur.item.city)) || '이름 없음'}»`;
      const name = `${word}을(를) «${src.name}» → «${target.name}» ${copy ? '복사' : '옮김'}`;
      const ok = await api.transact(draft => {
        const a = editable(draft, src);
        const b = editable(draft, target);
        for (const p of picks0) {
          const from = (a.item[listKey(a.item, p.kind)] ||= []);
          let i = p.cur.item ? from.findIndex(c => rowKey(c, p.kind) === rowKey(p.cur.item, p.kind)) : -1;
          if (i < 0 && p.orig.item) i = from.findIndex(c => rowKey(c, p.kind) === rowKey(p.orig.item, p.kind)); // 편집 창의 고침을 버리고 옮긴 경우 — 저장돼 있던 줄
          const cell = i >= 0 ? clone(from[i]) : p.cur.item;
          if (!cell) continue;
          if (i >= 0 && !copy) from.splice(i, 1);
          if (!from.length) delete a.item[listKey(a.item, p.kind)];
          (b.item[listKey(b.item, p.kind)] ||= []).push(cell);
          carryDocs(draft, src.uid, target.uid, p.kind, cell, copy);
        }
        a.done();
        b.done();
        D.ensureRefs(draft, state.model);
        return draft;
      }, name);
      if (!ok) return false;
      if (state.model.byUid.has(srcUid)) await ctx.openEditorFor(srcUid); // 편집 창은 원래 나라 그대로 (옮긴 줄이 빠진 새 값으로)
      HT.toast(`${word}을(를) «${target.name}»(으)로 ${copy ? '복사했습니다' : '옮겼습니다'} — 되돌리기 한 번에 돌아옵니다.`, 'ok');
      return true;
    }
    const yearText = t => (Number.isFinite(t) ? HT.formatYear ? HT.formatYear(t) : String(Math.round(t)) : '');
    function pickPolity(rows, opener) {
      const srcUid = state.editing;
      if (!srcUid) return HT.toast('새 항목은 먼저 저장해야 다른 나라로 옮길 수 있습니다.', 'error');
      const spans = rows.map(r => readRow(r, kindOf(r)).item).filter(Boolean);
      const lo = Math.min(...spans.map(c => num(c.start)).filter(Number.isFinite));
      const hi = Math.max(...spans.map(c => num(c.end ?? c.start)).filter(Number.isFinite));
      const all = (state.model.periods || []).filter(x => x.itemKind === 'period' && x.uid !== srcUid && (api.isOwn(x) || !api.isLocked(x)));
      const mine = all.filter(x => api.isOwn(x)).sort((a, b) => String(a.name).localeCompare(String(b.name), 'ko'));
      const theirs = all.filter(x => !api.isOwn(x)).sort((a, b) => String(a.packName).localeCompare(String(b.packName), 'ko') || String(a.name).localeCompare(String(b.name), 'ko'));
      const entry = x => {
        const end = Number.isFinite(x.endY) ? x.endY : x.end;
        const out = (Number.isFinite(lo) && lo < x.start) || (Number.isFinite(hi) && Number.isFinite(end) && hi > end);
        const years = `${yearText(x.start)}–${Number.isFinite(end) ? yearText(end) : ''}`;
        return { label: x.name, dot: x.color || '', sub: `${api.isOwn(x) ? '' : `${x.packName} · `}${years}${out ? ' · 기간 밖' : ''}`, warn: out, run: ev => moveToPolity(rows, x, !!(ev && (ev.ctrlKey || ev.metaKey))), keepFocus: true };
      };
      const first = rows[0];
      openMenu({
        ctx,
        opener: opener || (first && first.querySelector(':scope > .mk-grip')),
        anchor: opener || (first && first.querySelector(':scope > .mk-grip')),
        width: 300,
        find: '나라 이름으로 거르기',
        findHint: 'Enter 옮기기 · Esc 닫기',
        title: `어느 나라로 — ${rows.length > 1 ? `줄 ${rows.length}개` : `${rowLabel(first) || '이름 없음'} ${rowYears(first)}`.trim()}`,
        foot: '이 DLC의 나라 · 잠김을 푼 불러온 팩의 나라(덮어쓰기로 옮김) · Ctrl을 누른 채 고르면 복사 · 기간 밖이어도 옮길 수 있음',
        none: '옮길 수 있는 나라가 없습니다 — 다른 나라를 만들거나 불러온 팩의 자물쇠를 푸세요',
        list: () => {
          const q = (menu && menu.query ? menu.query : '').trim();
          const hit = x => !q || String(x.name).includes(q) || HT.makerBlocks.initials(String(x.name)).includes(q);
          const a = mine.filter(hit).slice(0, 200).map(entry);
          const b = theirs.filter(hit).slice(0, 200).map(entry);
          return [...(a.length ? [{ title: '이 DLC' }, ...a] : []), ...(b.length ? [{ title: '불러온 팩 — 잠김을 푼 것 (덮어쓰기로)' }, ...b] : [])];
        },
      });
    }

    /* ---------- 블록 메뉴 (결정 2 A) ---------- */
    function rowMenu(row, grip) {
      const sel = pickedRows();
      const rows = sel.length > 1 && sel.includes(row) ? sel : [row];
      if (rows.length === 1) clearPicks();
      const kinds = [...new Set(rows.map(kindOf))];
      const kind = kinds[0];
      const allCells = rows.every(r => CELL_KINDS.has(kindOf(r)));
      const extra = HT.makerBlocks.extras.menu.flatMap(fn => {
        try {
          return arr(fn({ rows, kind, form, ctx, api }));
        } catch (e) {
          return [];
        }
      });
      let items;
      let title;
      let foot;
      if (rows.length === 1) {
        const list = rowsOf(listOfRow(row));
        const i = list.indexOf(row);
        const conv = Object.entries(CONVERT[kind] || {}).filter(([to]) => fields.querySelector(`[data-cells="${to}"]`));
        title = `${KIND_WORD[kind] || ''} 줄 — ${i + 1} · ${rowLabel(row) || '이름 없음'}`;
        foot = 'Shift+손잡이 = 여러 줄 함께 고르기 · 둘을 고르면 맞바꾸기';
        items = [
          { label: '복제', key: 'Ctrl+D', run: () => duplicate(rows) },
          { label: '위로 옮기기', key: 'Alt+↑', disabled: i <= 0, run: () => step(row, -1) },
          { label: '아래로 옮기기', key: 'Alt+↓', disabled: i >= list.length - 1, run: () => step(row, 1) },
          ...(allCells ? [{ sep: true }, { label: '다른 나라로 옮기기…', keepFocus: true, run: () => pickPolity(rows, grip) }] : []),
          ...(conv.length ? [{ sep: true }, { title: '종류 바꾸기' }, ...conv.map(([to, c]) => ({ label: `${KIND_WORD[to]} 줄로 ${c.mode === 'copy' ? '복사' : '바꾸기'}`, run: ev => convert(rows, to, c.mode === 'copy' || !!(ev && (ev.ctrlKey || ev.metaKey))) }))] : []),
          ...(extra.length ? [{ sep: true }, ...extra] : []),
          { sep: true },
          { label: '지우기', key: 'Ctrl+Shift+Del', danger: true, run: () => remove(rows) },
        ];
      } else {
        const same = kinds.length === 1;
        const names = rows.map(r => rowLabel(r) || '이름 없음');
        title = `${same ? `${KIND_WORD[kind]} 줄` : '줄'} ${rows.length}개 고름 — ${names.slice(0, 3).join(' · ')}${names.length > 3 ? ' …' : ''}`;
        foot = '맞바꾸기는 같은 종류의 두 줄일 때만';
        const two = rows.length === 2 && same && CELL_KINDS.has(kind);
        items = [
          ...(two ? [{ label: '두 줄 맞바꾸기 (기간은 그대로)', run: () => swap(rows[0], rows[1], false) }, { label: '기간만 맞바꾸기', run: () => swap(rows[0], rows[1], true) }, { sep: true }] : []),
          { label: '복제', key: 'Ctrl+D', run: () => duplicate(rows) },
          ...(allCells ? [{ label: '다른 나라로 옮기기…', keepFocus: true, run: () => pickPolity(rows, grip) }] : []),
          ...(extra.length ? [{ sep: true }, ...extra] : []),
          { sep: true },
          { label: '지우기', key: 'Ctrl+Shift+Del', danger: true, run: () => remove(rows) },
        ];
      }
      openMenu({ ctx, opener: grip, anchor: grip, title, foot, list: () => items });
    }

    /* ---------- '/' 명령 (결정 5 A) ---------- */
    function slashItems() {
      const blocks = blocksOf(form);
      const out = [];
      const groups = new Map(GROUPS.map(g => [g, []]));
      for (const b of blocks) {
        const shown = !b.hidden;
        const list = !!blockList(b);
        const name = b.querySelector(':scope > summary b').textContent;
        const tag = shown ? (list ? '있음 · 줄 더하기' : '있음') : b.dataset.blk === 'dates' && /실재/.test(name) ? '실재성 · 확실성 · 이설' : TAG[b.dataset.blk] || '';
        (groups.get(b.dataset.group) || groups.get('그 밖')).push({ label: name, sub: tag, run: () => reveal(form, b, { row: list }) });
      }
      const names = fields.querySelector('[data-names-field]');
      if (names)
        groups.get('이름 · 글').unshift({
          label: '이름(원어 등)',
          isNew: true,
          sub: '원어 · 로마자 · 옛 이름',
          run: () => {
            const d = names.closest('details');
            if (d) d.open = true;
            const add = names.querySelector('[data-name-add]');
            if (add) add.click();
            else names.querySelector('input') && names.querySelector('input').focus();
            names.scrollIntoView({ block: 'nearest' });
          },
        });
      for (const fn of HT.makerBlocks.extras.slash) {
        try {
          for (const it of arr(fn({ form, ctx, api }))) (groups.get(it.group) || groups.get('그 밖')).push(it);
        } catch (e) {
          /* 덧붙인 줄이 잘못돼도 목록은 그대로 */
        }
      }
      for (const [g, items] of groups) if (items.length) out.push({ title: g }, ...items);
      return out;
    }
    function openSlash(opener) {
      const all = slashItems();
      if (!all.length) return false;
      const leaders = !!fields.querySelector('[data-cells="leaders"]');
      openMenu({
        ctx,
        opener,
        anchor: opener,
        width: 300,
        find: '블록 이름으로 거르기',
        lead: '/',
        findHint: 'Enter 더하기 · Esc 닫기',
        foot: leaders ? "지도자 한 사람의 승계 관계 · 부모 · 배우자는 그 줄 끝 '사람' 단추에" : '',
        none: '맞는 블록이 없습니다',
        list: () => {
          const q = (menu && menu.query ? menu.query : '').replace(/^\//, '').trim();
          if (!q) return all;
          const out = [];
          let title = null;
          for (const it of all) {
            if (it.title) title = it;
            else if ([it.label, it.find].some(s => s && (String(s).includes(q) || HT.makerBlocks.initials(String(s)).includes(q)))) { // it.find = 이름에 없는 거름 낱말(틀 줄의 '틀')
              if (title && !out.includes(title)) out.push(title);
              out.push(it);
            }
          }
          return out;
        },
      });
      const input = menuEl.querySelector('.mk-find input');
      if (input) input.value = '';
      return true;
    }

    /* ---------- 사건 ---------- */
    form.addEventListener(
      'pointerdown',
      e => {
        const g = e.target.closest && e.target.closest('.mk-grip');
        if (g && e.shiftKey) e.preventDefault(); // Shift+누름 = 고르기 — 글 고르기 · 초점 옮김 없이
      },
      true
    );
    form.addEventListener('click', e => {
      const t = e.target;
      const grip = t.closest('.mk-grip');
      if (grip && form.contains(grip)) {
        e.preventDefault();
        const row = grip.closest('.cell-row, .succ-row');
        if (!row || !listOfRow(row)) return;
        if (e.shiftKey) {
          if (picks.has(row)) {
            picks.delete(row);
            row.classList.remove('is-picked');
          } else {
            picks.add(row);
            row.classList.add('is-picked');
          }
          return;
        }
        if (menu && menu.opener === grip) return closeMenu(true);
        return rowMenu(row, grip);
      }
      const add = t.closest('[data-blk-add]');
      if (add) {
        e.preventDefault();
        e.stopPropagation();
        const b = add.closest('details.mk-blk');
        if (b) reveal(form, b, { row: true });
        return;
      }
      const chip = t.closest('[data-blk-chip]');
      if (chip) {
        e.preventDefault();
        const b = blockById(form, chip.dataset.blkChip);
        if (b) reveal(form, b, { row: true });
        return;
      }
      const head = t.closest('summary.mk-blk-head');
      if (head && head.parentElement.matches('details.mk-blk')) {
        const b = head.parentElement;
        if (b.open) ui.closed.add(b.dataset.blk); // 누른 뒤 접힘 — 작업실 설정으로 기억
        else ui.closed.delete(b.dataset.blk);
        saveUi();
      }
    });
    form.addEventListener('keydown', e => {
      if (e.isComposing || e.keyCode === 229) return;
      if (e.key === 'Escape' && picks.size) {
        e.preventDefault();
        e.stopPropagation(); // 고른 줄만 풂 — 편집 창은 그대로
        clearPicks();
        return;
      }
    });
    /* '/'는 작업실의 명령 찾기(js/maker-shell.js — 문서의 잡는 단계)보다 먼저 받아야 하므로 창(window)의 잡는 단계에서: 편집 창의 글 칸 밖이면 '/' 상자,
       블록이 없는 폼이면 그대로 흘려 보내 명령 찾기가 열림 */
    window.addEventListener(
      'keydown',
      e => {
        if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey || e.isComposing || e.keyCode === 229 || e.defaultPrevented) return;
        const t = e.target;
        if (!t || t.nodeType !== 1 || !form.contains(t) || !t.closest('.ep-body')) return;
        if (t.matches('input, textarea, select, [contenteditable], [contenteditable] *')) return; // 글 칸 안의 '/'는 그대로 글자
        if (menu && menuEl && menuEl.contains(t)) return;
        if (openSlash(t)) {
          e.preventDefault();
          e.stopImmediatePropagation();
        }
      },
      true
    );

    /* ---------- 끌기 (결정 3 C — HT.makerDrag.slot) ---------- */
    const ids = new WeakMap();
    let idSeq = 0;
    const idOf = el => (el ? ids.get(el) || (ids.set(el, ++idSeq), idSeq) : 0);
    function hitAt(x, y, mods, p, at) {
      if (!at || !form.contains(at) || !at.closest('.ep-body')) return null;
      let list = null;
      let anchor = null;
      let where = 'append';
      let blk = null;
      const row = at.closest('.cell-row, .succ-row');
      const chip = at.closest('[data-blk-chip]');
      if (row && row !== p.row && listOfRow(row)) {
        list = listOfRow(row);
        const r = row.getBoundingClientRect();
        where = y < r.top + r.height / 2 ? 'before' : 'after';
        anchor = row;
        blk = row.closest('details.mk-blk');
      } else if (chip) {
        blk = blockById(form, chip.dataset.blkChip);
        list = blk && blockList(blk);
        anchor = chip.closest('.mk-blk-chips');
        where = 'before';
      } else if ((blk = at.closest('details.mk-blk'))) {
        list = blockList(blk);
        if (list) {
          anchor = blk.open ? list : blk;
          where = blk.open ? 'append' : 'after';
        }
      } else {
        const f = at.closest('.field');
        list = f && f.querySelector(LIST_SEL);
        anchor = list;
      }
      if (!list || !anchor) return null;
      const to = listKind(list);
      const again = m => hitAt(x, y, m, p, at);
      const key = `${idOf(list)}|${idOf(anchor)}|${where}`;
      const ring = list !== p.list ? blk || list.closest('.field') : null;
      const base = { key, list, to, anchor, where, ring, again, openKey: blk && !blk.open && !blk.hidden ? blk.dataset.blk : '', minHeight: p.height };
      if (to === p.kind) {
        if (list !== p.list) return Object.assign(base, { ok: false, reason: '같은 종류의 다른 목록에는 놓을 수 없음' });
        const start = own(p.row, 'c-start');
        return Object.assign(base, { ok: true, same: true, text: SORTED.has(to) ? `저장하면 시작 순${start ? `(${start})` : ''}으로 돌아갑니다 — 차례는 시작이 같거나 미정인 줄끼리만 남습니다` : '놓으면 이 자리로 옮깁니다' });
      }
      const c = (CONVERT[p.kind] || {})[to];
      if (!c) return Object.assign(base, { ok: false, ring: null, reason: `${KIND_WORD[p.kind] || '이'} 줄은 ${KIND_WORD[to] || '이'} 줄로 바꿀 수 없음` });
      if (p.read.problems.length) return Object.assign(base, { ok: false, ring: null, reason: `이 줄에 고칠 것이 있음 — ${p.read.problems[0]}` });
      return Object.assign(base, { ok: true, copy: c.mode === 'copy' || mods.ctrl, text: convertText(p.read.item, p.kind, to, mods.ctrl) });
    }
    const formDrag = HT.makerDrag.slot(form, {
      grab: t => {
        const g = t.closest && t.closest('.mk-grip');
        return g && form.contains(g) && listOfRow(g.parentElement) ? g : null;
      },
      payload: grip => {
        const row = grip.parentElement;
        const list = listOfRow(row);
        if (!list) return null;
        closeMenu(false);
        const kind = listKind(list);
        return { row, list, kind, height: row.getBoundingClientRect().height, read: CELL_KINDS.has(kind) ? readRow(row, kind) : { item: null, problems: [] } };
      },
      lifted: p => [p.row],
      ghost: p => ({ name: rowLabel(p.row) || '이름 없음', years: rowYears(p.row), kind: KIND_WORD[p.kind] || '' }),
      hit: hitAt,
      drop: (p, h) => {
        if (h.same) {
          if (h.anchor === p.list) p.list.append(p.row);
          else if (isRowEl(h.anchor)) h.where === 'before' ? h.anchor.before(p.row) : h.anchor.after(p.row);
          fire(form);
          const g = p.row.querySelector(':scope > .mk-grip');
          if (g) g.focus({ preventScroll: true });
          return;
        }
        const at = isRowEl(h.anchor) ? { anchor: h.anchor, where: h.where } : null;
        const b = h.list.closest('details.mk-blk');
        if (b && (b.hidden || !b.open)) reveal(form, b, { row: false, focus: false });
        convert([p.row], h.to, !!h.copy, at);
      },
      refuse: (p, h) => h && h.reason && HT.toast(`놓을 수 없습니다 — ${h.reason}`),
      scroller: () => form.querySelector('.ep-body'),
      hover: h => h.openKey || '',
      open: id => {
        const b = blockById(form, id);
        if (b) b.open = true;
      },
      idle: '줄 목록 위에 놓으세요 — 같은 목록이면 자리, 다른 목록이면 종류 바꾸기',
    });

    return { apply, openSlash, rowMenu, pickPolity, moveToPolity, convert, swap, duplicate, step, remove, reveal: b => reveal(form, b), drag: formDrag, closeMenu: () => closeMenu(false) };
  }

  /** 한글 초성 (거름 칸 — '/ㅈ' → 지도자 · 지위 변천) */
  const CHO = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  const initials = s => [...String(s)].map(ch => {
    const c = ch.charCodeAt(0) - 0xac00;
    return c >= 0 && c < 11172 ? CHO[Math.floor(c / 588)] : ch;
  }).join('');

  HT.makerBlocks = { mount, CONVERT, convertItem, convertText, readRow, initials, build, settle, extras: { menu: [], slash: [] } };
})();

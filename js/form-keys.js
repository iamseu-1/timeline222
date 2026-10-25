/* 역사 연표 — 입력 칸 길잡이 (HT.formKeys · 메이커 편집 창의 키보드)
 *
 * 메이커 편집 창(#editorForm)의 칸을 키보드로 옮겨 다닙니다 (docs/구상-연표-확장-10건.md 3-5 (가)). 가운데 표(js/maker-grid.js)와 같은 감각을 폼에도.
 *
 *   ↑ / ↓            줄 목록(지도자 · 연호 · 도읍 · 소속 · 승계 · 이설 … 줄) 안에서는 같은 열 — '시작'에서 ↓ = 아래 줄의 '시작'.
 *                    줄 목록 밖에서는 화면에 보이는 앞 / 뒤 글 칸. 목록의 첫 줄에서 ↑ · 끝 줄에서 ↓는 목록을 벗어나 그 앞 / 뒤 칸으로.
 *   Enter            줄 안이면 아래 줄의 같은 칸 — 마지막 줄이면 그 목록의 ＋로 새 줄을 만들고 그 칸으로
 *                    (마지막 줄이 텅 비었으면 새 줄을 또 만들지 않고 목록 뒤의 칸으로 — 빈 줄이 쌓이지 않게)
 *   Shift+Enter      줄 안이면 위 줄의 같은 칸
 *   Alt+↑ / ↓        줄 옮기기 (볼거리 목록의 선례 — 저장하면 칸은 예전처럼 시작 순으로 다시 놓입니다)
 *   Ctrl+D           줄 복제 (그 줄 바로 아래에)
 *   Ctrl+Shift+Delete  줄 지우기 (그 줄의 ✕와 같은 길 — 맥은 Cmd+Shift+Backspace도)
 *   Ctrl+S · Ctrl+Enter  저장 — 그대로 (js/viewer.js가 받음)
 *
 * 정한 것 (판단해 정하라던 곳):
 *   - 줄 밖 한 줄 칸의 Enter: 저장하지 않는 것은 그대로이고, 다음 글 칸으로 갑니다(Shift+Enter는 앞 칸). 줄 안의 Enter와 같은 '아래로' 감각이고,
 *     칸을 다 채운 뒤 손을 마우스로 옮기지 않아도 됩니다. 마지막 칸에서는 아무 일도 없습니다.
 *   - 고르기(select) · 숫자 칸(type=number) · 시각 칸: 화살표가 값을 바꾸는 칸이라 ↑↓ · Alt+↑↓를 가로채지 않습니다(고르기에서 Alt+↓는 목록 열기).
 *     ↑↓로 옮겨 다닐 때도 고르기 · 체크 상자에는 멈추지 않습니다 — 화살표 한 번에 기원전 · 기원후 같은 값이 바뀌는 사고를 막으려고. 고르기는 Tab으로.
 *   - 자동 완성 목록(datalist — 국성 · 가문 · 지위 · 정권 칸): 글을 치면 브라우저가 띄우는 목록은, 떠 있는 동안 ↑↓ · Enter를 브라우저가 먼저 가져가
 *     (크로미움 계열 — 엣지 · 데스크톱 앱) 페이지에 오지 않으므로 목록 고르기는 그대로입니다. 목록이 닫혀 있을 때의 ↓는 칸 옮기기라,
 *     빈 칸에서 ↓로 목록 전체를 펼치던 길은 쓰지 않습니다(글자를 치면 맞는 것이 뜸). (목록 창은 브라우저 쪽 창이라 검사용 머리 없는 크로미움에서는
 *     뜨지 않아 scripts/form-keys-check.mjs로는 확인하지 못했습니다 — 엣지에서 가문 칸에 글자를 치고 ↓ · Enter로 고르는지 눈으로 확인할 것)
 *   - 문서 칸의 [[ 자동 완성 상자(js/wiki.js): 열려 있으면 그 상자가 ↑↓ · Enter를 먼저 받고 막으므로(defaultPrevented) 손대지 않습니다.
 *   - 여러 줄 글 칸(textarea): 커서가 첫 줄(보이는 줄 — 길어서 접힌 줄도 셈)에서 ↑, 끝 줄에서 ↓일 때만 칸을 옮깁니다(노션 식). Enter는 줄바꿈 그대로.
 *   - 칸의 이설 상자(줄 안의 .cell-alts): 펼친 상자의 이설 줄은 제 목록(이설 줄끼리 같은 열)이고, 상자의 확실성 · 연대 폭 칸은 줄의 열이 아니라
 *     앞 / 뒤 칸으로 움직입니다. 접힌 상자 · 닫힌 접는 구역(details) · 숨은 칸 · 잠긴(disabled) 칸은 건너뜁니다.
 *     지도자 · 내각 · 연호 줄의 [사람] · [이름] 상자(.cell-xbox — 형식 3)도 같은 딸린 상자입니다: 사람 · 자리 이음 칸은 앞 / 뒤 칸으로,
 *     상자 안의 이름 줄 · 부모 줄 · 배우자 줄은 제 목록(.alt-rows — ＋ 이름 · 부모 · 배우자 추가가 그 목록의 ＋). 단체 폼의 있던 나라 · 앞선 단체 ·
 *     집권 기간 · 구성 나라 줄, 제도 폼의 칸 줄, 이름(원어 등) 줄은 머리 주석의 꼴('-row' 줄 · '-rows' 목록 · data-…-add / -del)을 따라 저절로 됩니다
 *     (scripts/form-keys-check.mjs가 상자 · 목록마다 봄).
 *   - 한글 조합 중(isComposing · keyCode 229)에는 아무것도 하지 않습니다. 큰 입력 창(js/fieldpop.js)이 열려 있으면 이 길잡이는 쉽니다.
 *   - 옮겨 간 칸이 편집 창의 보이는 곳 밖이면 --t-move 길이의 스프링(HT.motion · 되튐 없음)으로 스크롤합니다 — 움직임 줄이기에서는 토큰이 0이라 곧장.
 *   - 커서: 한 줄 칸은 끝에, 여러 줄 칸은 아래로 들어오면 맨 앞 · 위로 들어오면 맨 끝에 둡니다(글을 통째로 고르지 않음 — 치다가 덮어쓰지 않게).
 *
 * 줄 꼴은 이름으로 알아봅니다: 클래스가 '-row'로 끝나는 요소이고 그 부모의 클래스가 '-rows'로 끝나면 줄(.cell-row · .succ-row · .alt-row · .view-row …).
 * 목록의 ＋는 목록 둘레에서 data-…-add 단추를, 줄의 ✕는 줄 안의 data-…-del 단추를 찾아 누릅니다 — 그래서 새 줄 목록이 생겨도 이 꼴을 따르면 저절로 됩니다.
 * 줄 옮기기 · 복제는 ＋가 있는 목록(사람이 고치는 목록)에서만 합니다. 줄을 바꾼 뒤에는 폼에 input을 쏴 '저장하지 않은 고침' · 소속 줄 잠금 등이 따라옵니다.
 *
 * 부르는 쪽 없이 스스로 #editorForm에 붙습니다(연표에는 편집 창이 없어 아무 일도 없음). core.js 뒤에 읽고, 꼭 viewer.js보다 앞에 읽어
 * 편집 창의 Enter를 viewer.js의 '한 줄 칸 Enter 삼키기'보다 먼저 받습니다 — 그쪽이 먼저 막으면(defaultPrevented) 남이 받은 키로 보고 손대지 않으므로
 * 차례가 바뀌면 Enter 길이 듣지 않습니다(저장되지는 않음). scripts/form-keys-check.mjs가 이 차례와 서비스 워커 · 포장 목록을 봅니다.
 */
(() => {
  const HT = (window.HT = window.HT || {});
  /** 글 칸 — ↑↓ · Enter로 멈추는 곳 (숫자 칸은 Enter로만 지나가고 ↑↓는 그 칸의 값 바꾸기) */
  const STOP = ['input:not([type])', 'input[type="text"]', 'input[type="search"]', 'input[type="email"]', 'input[type="url"]', 'input[type="tel"]', 'input[type="password"]', 'input[type="number"]', 'textarea'].join(', ');
  /** 줄 안의 딸린 상자 — 그 안의 칸(제 줄이 따로 없는 것)은 줄의 열로 움직이지 않고 앞 / 뒤 칸으로. 새 상자는 여기에 push.
      .cell-xbox = 지도자 · 내각 · 연호 줄의 [사람] · [이름] 상자(형식 3 — 사람 · 자리 이음 칸은 앞 / 뒤 칸으로, 상자 안의 이름 줄 · 부모 줄 · 배우자 줄은 제 목록) */
  const SUB_BOXES = ['.cell-alts', '.cell-xbox'];
  const MARGIN = 24; // 스크롤해 보일 때 위아래로 남길 틈(px)

  const hasCls = (n, re) => !!n && !!n.classList && [...n.classList].some(c => re.test(c));
  /** 줄인지: '-row'로 끝나는 클래스 + 부모가 '-rows'로 끝나는 클래스 */
  const isRow = n => !!n && n.nodeType === 1 && hasCls(n, /-row$/) && hasCls(n.parentElement, /-rows$/);
  /** 칸이 든 가장 가까운 줄 (폼 밖으로는 나가지 않음) */
  function rowOf(el, stop = null) {
    for (let n = el && el.parentElement; n && n !== stop; n = n.parentElement) if (isRow(n)) return n;
    return null;
  }
  const rowsOf = list => [...list.children].filter(isRow);
  const inSub = (el, row) => {
    const sub = el.closest(SUB_BOXES.join(', '));
    return !!sub && row.contains(sub);
  };
  /** 칸이 줄의 열로 움직이는 줄 — 줄 안이되 그 줄의 딸린 상자 칸은 아님 */
  function cellRow(el, form) {
    const row = rowOf(el, form);
    return row && !inSub(el, row) ? row : null;
  }
  const isText = el => !!el && el.matches && el.matches(STOP) && el.type !== 'number';
  const isNumber = el => !!el && el.tagName === 'INPUT' && el.type === 'number';
  /** 화면에 보이는 칸인지 — 숨은 조상 · 닫히는 이설 상자 · 닫힌 접는 구역 · 잠긴 칸은 아님 */
  function visible(el) {
    if (!el || !el.isConnected || el.disabled || el.type === 'hidden') return false;
    if (el.closest('[hidden], [data-closing="1"], [inert]')) return false;
    for (let d = el.closest('details'); d; d = d.parentElement && d.parentElement.closest('details')) {
      const sum = el.closest('summary');
      if (!d.open && !(sum && sum.parentElement === d)) return false;
    }
    return el.getClientRects().length > 0;
  }
  /** 열 이름: 칸의 첫 클래스(c-start · s-from · alt-year …) — 없으면 name, 그것도 없으면 꼴 */
  const colKey = el => [...el.classList].find(c => !/^(is|has)-/.test(c)) || (el.name ? `@${el.name}` : `${el.tagName}:${el.type || ''}`);
  /** 줄이 제 열로 가진 글 칸들 (안쪽 줄 · 딸린 상자의 칸은 빼고) */
  const ownStops = row => [...row.querySelectorAll(STOP)].filter(f => rowOf(f) === row && !inSub(f, row));
  /** 그 줄의 같은 열 칸 (없거나 숨었으면 그 줄의 첫 칸) */
  function sameCol(row, key) {
    const own = ownStops(row).filter(visible);
    return own.find(f => colKey(f) === key) || own[0] || null;
  }
  const allStops = form => [...form.querySelectorAll(STOP)].filter(visible);
  /** node 뒤(안쪽 빼고)의 첫 글 칸 · node 앞의 마지막 글 칸 */
  function nextAfter(form, node) {
    return allStops(form).find(s => s !== node && !node.contains(s) && node.compareDocumentPosition(s) & Node.DOCUMENT_POSITION_FOLLOWING) || null;
  }
  function prevBefore(form, node) {
    const list = allStops(form).filter(s => s !== node && !node.contains(s) && node.compareDocumentPosition(s) & Node.DOCUMENT_POSITION_PRECEDING);
    return list[list.length - 1] || null;
  }
  /** 목록의 ＋ 단추: 목록의 부모 · 그 위 한 겹까지에서 data-…-add 단추(목록 안 · 다른 줄 안의 것은 빼고)를 — 목록 뒤의 것을 먼저.
      지금의 목록은 모두 부모 안에 ＋가 있고(줄 목록 뒤 · .toolbar 안), 더 멀리 찾으면 옆 목록의 ＋를 잘못 누를 수 있어 두 겹에서 멈춥니다 */
  const isAdd = b => [...b.attributes].some(a => /^data-[a-z0-9-]+-add$/.test(a.name));
  const isDel = b => [...b.attributes].some(a => /^data-[a-z0-9-]+-del$/.test(a.name));
  function addButtonOf(list, form) {
    let box = list.parentElement;
    for (let depth = 0; box && depth < 2 && form.contains(box); depth++, box = box.parentElement) {
      const found = [...box.querySelectorAll('button')].filter(b => isAdd(b) && !list.contains(b) && !b.disabled && !rowOf(b, box));
      if (found.length) return found.find(b => list.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) || found[0];
    }
    return null;
  }
  /** 줄의 ✕ (안쪽 줄의 ✕는 빼고) */
  const delButtonOf = row => [...row.querySelectorAll('button')].find(b => isDel(b) && rowOf(b) === row) || null;
  /** 줄이 텅 비었는지 — 글 칸이 모두 비었으면 (고르기 · 체크는 기본값이 있어 셈하지 않음) */
  const emptyRow = row => ownStops(row).every(f => !String(f.value || '').trim());
  const fire = form => form.dispatchEvent(new Event('input', { bubbles: true }));

  /* ---------- 여러 줄 글 칸: 커서가 첫 줄 / 끝 줄인지 (보이는 줄 — 칸 폭에서 접힌 줄도 셈) ---------- */
  const MIRROR = ['fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'fontVariant', 'fontStretch', 'fontFeatureSettings', 'fontKerning', 'lineHeight', 'letterSpacing', 'wordSpacing', 'textTransform', 'textIndent', 'tabSize', 'whiteSpace', 'wordBreak', 'overflowWrap', 'lineBreak', 'direction', 'textRendering'];
  /** 글 칸의 두 자리(a ≤ b)가 같은 보이는 줄인지 — 같은 글꼴 · 폭의 숨은 거울 상자에 두 표지를 넣어 높이를 견줍니다 */
  function sameLine(ta, a, b) {
    const cs = getComputedStyle(ta);
    const m = document.createElement('div');
    for (const k of MIRROR) m.style[k] = cs[k];
    const w = ta.clientWidth - (parseFloat(cs.paddingLeft) || 0) - (parseFloat(cs.paddingRight) || 0);
    Object.assign(m.style, { position: 'absolute', visibility: 'hidden', pointerEvents: 'none', left: '-10000px', top: '0', boxSizing: 'content-box', padding: '0', border: '0', margin: '0', height: 'auto', overflow: 'hidden', width: `${Math.max(1, w)}px` });
    if (!/pre/.test(m.style.whiteSpace)) m.style.whiteSpace = 'pre-wrap';
    const v = ta.value;
    const s1 = document.createElement('span');
    const s2 = document.createElement('span');
    m.append(v.slice(0, a), s1, v.slice(a, b), s2, v.slice(b));
    document.body.appendChild(m);
    const same = Math.abs(s1.offsetTop - s2.offsetTop) < 4;
    m.remove();
    return same;
  }
  /** 커서가 그 방향의 끝 줄에 있는지 (dir −1 = 첫 줄, +1 = 끝 줄). 글을 고른 채면 아님 */
  function caretOnEdge(ta, dir) {
    if (ta.selectionStart !== ta.selectionEnd) return false;
    const v = ta.value;
    const pos = ta.selectionStart;
    if (dir < 0) {
      if (pos === 0) return true;
      if (v.lastIndexOf('\n', pos - 1) !== -1) return false;
      return sameLine(ta, 0, pos);
    }
    if (pos === v.length) return true;
    if (v.indexOf('\n', pos) !== -1) return false;
    return sameLine(ta, pos, v.length);
  }

  /* ---------- 보이게 스크롤 (스프링 — 길이는 --t-move, 되튐 없음) ---------- */
  const glides = new WeakMap(); // 스크롤 상자 → { spring, raf, last }
  function scrollerOf(el) {
    for (let n = el.parentElement; n && n !== document.body; n = n.parentElement) {
      const oy = getComputedStyle(n).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && n.scrollHeight > n.clientHeight + 1) return n;
    }
    return null;
  }
  function glideTo(box, to) {
    const M = HT.motion;
    const dur = M && M.T ? M.T.move : 0;
    let g = glides.get(box);
    if (!dur || !M.Spring) {
      if (g) cancelAnimationFrame(g.raf);
      glides.delete(box);
      box.scrollTop = to; // 움직임 줄이기 — 토큰이 0이면 곧장
      return;
    }
    if (g && g.raf) g.spring.set(to); // 가는 중이면 지금 자리 · 지금 빠르기에서 새 목표로 이어 갑니다
    else {
      g = { spring: new M.Spring(box.scrollTop, { response: dur / 1000, restDelta: 0.5, restSpeed: 4 }).set(to), raf: 0, last: box.scrollTop };
      glides.set(box, g);
    }
    const step = () => {
      if (Math.abs(box.scrollTop - g.last) > 2) return (g.raf = 0); // 사람이 굴렸으면 그만
      const t = M.now();
      const done = g.spring.done(t);
      box.scrollTop = done ? g.spring.target : g.spring.value(t);
      g.last = box.scrollTop;
      g.raf = done ? 0 : requestAnimationFrame(step);
    };
    if (!g.raf) g.raf = requestAnimationFrame(step);
  }
  /** 칸이 스크롤 상자의 보이는 곳 밖이면 보이게 (위아래 틈 MARGIN) */
  function reveal(el) {
    const box = scrollerOf(el);
    if (!box) return;
    const r = el.getBoundingClientRect();
    const b = box.getBoundingClientRect();
    let delta = 0;
    if (r.top < b.top + MARGIN) delta = r.top - (b.top + MARGIN);
    else if (r.bottom > b.bottom - MARGIN) delta = Math.min(r.bottom - (b.bottom - MARGIN), r.top - (b.top + MARGIN)); // 칸이 상자보다 크면 위쪽을 맞춤
    if (Math.abs(delta) < 1) return;
    const g = glides.get(box);
    const from = g && g.raf ? g.spring.target : box.scrollTop;
    glideTo(box, Math.max(0, Math.min(box.scrollHeight - box.clientHeight, from + delta)));
  }

  /** 칸으로 초점을 옮깁니다 — 커서: 한 줄 칸은 끝, 여러 줄 칸은 앞으로(아래로) 들어오면 맨 앞 · 뒤로(위로) 들어오면 맨 끝 */
  function go(el, dir) {
    if (!el) return false;
    el.focus({ preventScroll: true });
    const n = el.tagName === 'TEXTAREA' && dir > 0 ? 0 : String(el.value || '').length;
    try {
      el.setSelectionRange(n, n);
    } catch (err) {
      /* 커서가 없는 칸 (숫자) */
    }
    reveal(el);
    return true;
  }

  /* ---------- 줄 다루기 ---------- */
  /** 줄 옮기기 — 옆 줄을 이 줄 너머로 옮겨(이 줄은 그대로 — 초점 · 한글 입력 상태가 끊기지 않게) */
  function moveRow(form, row, dir) {
    const rows = rowsOf(row.parentElement);
    const i = rows.indexOf(row);
    const other = rows[i + dir];
    if (!other) return false;
    if (dir < 0) row.parentElement.insertBefore(other, row.nextSibling);
    else row.parentElement.insertBefore(other, row);
    fire(form);
    return true;
  }
  /** 줄 복제 — 바로 아래에. 칸의 값 · 고른 것 · 체크를 그대로 옮기고, id는 떼고, 닫히던 이설 상자는 닫힌 채로 */
  function duplicateRow(form, row) {
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
    row.parentElement.insertBefore(copy, row.nextSibling);
    fire(form);
    return copy;
  }

  function onKey(form, e) {
    if (e.defaultPrevented || e.isComposing || e.keyCode === 229) return; // 자동 완성 상자 등이 먼저 받음 · 한글 조합 중
    if (HT.fieldPop && HT.fieldPop.isOpen()) return; // 큰 입력 창이 열려 있으면 쉼
    const el = e.target;
    if (!el || el.nodeType !== 1 || !form.contains(el)) return;
    const ctrl = e.ctrlKey || e.metaKey;
    const k = e.key;
    const letter = /^Key([A-Z])$/.exec(e.code || '');
    const isD = letter ? letter[1] === 'D' : /^d$/i.test(k); // 한글 자판(ㅇ)에서도 D
    const row = rowOf(el, form);
    const list = row && row.parentElement;
    const tag = el.tagName;

    /* 줄 다루기: Alt+↑↓ 옮기기 · Ctrl+D 복제 · Ctrl+Shift+Delete 지우기 — 사람이 고치는 목록(＋가 있는 목록)의 줄에서만 */
    if (row && e.altKey && !ctrl && !e.shiftKey && (k === 'ArrowUp' || k === 'ArrowDown')) {
      if (tag === 'SELECT' || !addButtonOf(list, form)) return; // 고르기의 Alt+↓는 목록 열기
      e.preventDefault();
      moveRow(form, row, k === 'ArrowUp' ? -1 : 1);
      if (document.activeElement !== el && visible(el)) el.focus({ preventScroll: true });
      reveal(el);
      return;
    }
    if (row && ctrl && !e.altKey && !e.shiftKey && isD) {
      if (!addButtonOf(list, form)) return;
      e.preventDefault(); // 브라우저의 즐겨찾기 넣기도 막음
      if (e.repeat) return; // 누르고 있어도 한 번만
      const copy = duplicateRow(form, row);
      const twin = el.matches(STOP) ? sameCol(copy, colKey(el)) : null;
      if (twin && cellRow(el, form) === row) go(twin, 1);
      else reveal(copy);
      return;
    }
    if (row && ctrl && e.shiftKey && !e.altKey && (k === 'Delete' || (e.metaKey && k === 'Backspace'))) {
      const del = delButtonOf(row);
      if (!del) return;
      e.preventDefault(); // 브라우저의 '인터넷 사용 기록 삭제' 창도 막음
      if (e.repeat) return;
      const rows = rowsOf(list);
      const i = rows.indexOf(row);
      const key = el.matches(STOP) ? colKey(el) : null;
      const add = addButtonOf(list, form);
      del.click(); // 그 목록의 ✕와 같은 길 (폼에 input도 그쪽이 쏨)
      if (row.isConnected) return; // 지우지 않았으면(막힌 줄) 그대로
      const left = rowsOf(list);
      const near = left[i] || left[i - 1];
      const target = near ? (key ? sameCol(near, key) : ownStops(near).find(visible)) : null;
      if (target) go(target, 1);
      else if (add && visible(add)) {
        add.focus({ preventScroll: true }); // 목록이 비면 ＋에 — 초점이 body로 떨어져 글자가 연표 단축키로 새지 않게
        reveal(add);
      } else go(prevBefore(form, list) || nextAfter(form, list), -1);
      return;
    }

    /* 칸 옮기기: ↑↓ (글 칸에서만 — 고르기 · 숫자 · 체크는 제 화살표) · Enter (한 줄 칸) */
    if (e.altKey || ctrl) return;
    const cRow = cellRow(el, form);
    if (k === 'ArrowUp' || k === 'ArrowDown') {
      if (e.shiftKey || !isText(el)) return;
      const dir = k === 'ArrowUp' ? -1 : 1;
      if (tag === 'TEXTAREA' && !caretOnEdge(el, dir)) return; // 여러 줄 칸은 첫 줄 / 끝 줄에서만
      let target = null;
      if (cRow) {
        const rows = rowsOf(cRow.parentElement);
        const near = rows[rows.indexOf(cRow) + dir];
        target = near ? sameCol(near, colKey(el)) : null;
        if (!near) target = dir > 0 ? nextAfter(form, cRow.parentElement) : prevBefore(form, cRow.parentElement); // 목록 끝 — 목록 밖으로
      } else target = dir > 0 ? nextAfter(form, el) : prevBefore(form, el);
      if (!target) return;
      e.preventDefault();
      go(target, dir);
      return;
    }
    if (k === 'Enter') {
      if (tag !== 'INPUT' || !(isText(el) || isNumber(el))) return; // 여러 줄 칸은 줄바꿈 · 고르기 · 체크 · 단추는 제 것
      e.preventDefault(); // 한 줄 칸의 Enter는 저장이 아닙니다 (viewer.js와 같은 약속)
      const dir = e.shiftKey ? -1 : 1;
      if (!cRow) return void go(dir > 0 ? nextAfter(form, el) : prevBefore(form, el), dir);
      const rows = rowsOf(cRow.parentElement);
      const near = rows[rows.indexOf(cRow) + dir];
      if (near) return void go(sameCol(near, colKey(el)), dir);
      if (dir < 0) return; // 첫 줄의 Shift+Enter — 그대로
      const box = cRow.parentElement;
      if (emptyRow(cRow)) return void go(nextAfter(form, box), 1); // 빈 마지막 줄 — 새 줄을 또 만들지 않고 목록 뒤로
      const add = addButtonOf(box, form);
      if (!add) return;
      const before = new Set(rowsOf(box));
      const key = colKey(el);
      const scroller = scrollerOf(box);
      const top = scroller ? scroller.scrollTop : 0;
      add.click(); // 그 목록의 ＋와 같은 길 (새 줄의 첫 칸에 초점이 갔다가 같은 열로 옮김)
      if (scroller) scroller.scrollTop = top; // ＋가 준 초점의 순간 스크롤은 되돌리고, 아래 go가 부드럽게 보여 줌
      const fresh = rowsOf(box).filter(r => !before.has(r));
      const made = fresh[fresh.length - 1];
      if (made) go(sameCol(made, key), 1);
    }
  }

  /** 폼에 길잡이를 붙입니다 (여러 번 불러도 한 번만) */
  function attach(form) {
    if (!form || form.dataset.formKeys) return false;
    form.dataset.formKeys = '1';
    form.addEventListener('keydown', e => onKey(form, e));
    return true;
  }
  /* 편집 창은 dlc-maker.html에 처음부터 있으므로(이 파일은 body 끝에서 읽힘) 곧장 붙입니다 — viewer.js가 폼에 Enter 삼키기를 붙이기 전에 붙어야
     한 줄 칸의 Enter를 이 길잡이가 먼저 받습니다(그쪽이 먼저 막으면 defaultPrevented라 손대지 않으므로). 아직 없으면 문서가 다 읽힌 뒤에 */
  const auto = () => attach(document.getElementById('editorForm'));
  if (!auto() && document.readyState === 'loading') document.addEventListener('DOMContentLoaded', auto);

  /** 단축키 목록(메이커 도움말의 '단축키' — js/maker-shell.js의 openKeys)에 보일 줄: [하는 일, 키] */
  const KEYS = [
    ['편집 창: 위 · 아래 칸 (줄 목록에서는 같은 열)', '↑ ↓'],
    ['편집 창: 아래 줄 · 위 줄의 같은 칸 (마지막 줄이면 새 줄)', 'Enter · Shift+Enter'],
    ['편집 창: 줄 옮기기', 'Alt+↑ ↓'],
    ['편집 창: 줄 복제', 'Ctrl+D'],
    ['편집 창: 줄 지우기', 'Ctrl+Shift+Delete'],
    ['편집 창: 저장', 'Ctrl+S · Ctrl+Enter'],
  ];

  /* ---------- 칸 줄의 배치용 연도 (2026-10-23 — "메이커로 못 바꾸는 곳이 없도록" ③) ----------
     줄(지도자 · 내각 · 연호 · 도읍 · 지위 · 시기 · 소속 · 활동 기록 · 있던 나라 · 구성 나라 · 집권 기간 · 제도 칸 · 이름 · 배우자)의 시작 · 끝 칸에 "미정"을 적으면
     그 옆에 숫자 칸(배치용 연도 — 미정인 칸을 연표에 놓을 해)이 생깁니다(항목의 '미정' 체크 옆 숫자 칸과 같은 뜻). 값은 줄의 data-start-hint · data-end-hint에 적혀
     읽기(core.js rowEdge · xRowEdge · readRankRows …)가 잇고, 파일에는 항목의 미정과 같은 꼴(startUnknown: true + start 숫자)로 남습니다. 미정을 지우면 숫자 칸도 사라집니다 */
  const HINT_EDGE = '.c-start, .c-end, .x-start, .x-end';
  const HINT_ROW = '.cell-row, .succ-row, .alt-row';
  const edgeKey = el => (el.classList.contains('c-end') || el.classList.contains('x-end') ? 'end' : 'start');
  function syncHint(input) {
    const row = input.closest(HINT_ROW);
    if (!row) return;
    const key = edgeKey(input);
    let hint = input.nextElementSibling;
    if (!(hint && hint.classList.contains('c-hint') && hint.dataset.hintFor === key)) hint = null;
    if (!HT.isUnknownText(input.value)) {
      if (hint) hint.remove();
      return;
    }
    if (!hint) {
      hint = document.createElement('input');
      hint.type = 'text';
      hint.inputMode = 'numeric';
      hint.autocomplete = 'off';
      hint.className = 'c-hint';
      hint.dataset.hintFor = key;
      hint.placeholder = '배치용 해';
      hint.title = `${key === 'start' ? '시작' : '끝'}이 미정인 칸을 연표에 놓을 해 — 연도나 날짜(기원전은 -57). 비우면 다른 쪽 끝 · 이웃 칸으로 짐작합니다`;
      hint.setAttribute('aria-label', '배치용 연도');
      input.insertAdjacentElement('afterend', hint);
    }
    const v = row.dataset[`${key}Hint`];
    if (document.activeElement !== hint) hint.value = v == null ? '' : String(v);
  }
  document.addEventListener('input', e => {
    const t = e.target;
    if (!(t instanceof HTMLInputElement)) return;
    if (t.matches(HINT_EDGE)) return syncHint(t);
    if (!t.classList.contains('c-hint')) return;
    const row = t.closest(HINT_ROW);
    if (!row) return;
    const key = t.dataset.hintFor;
    const text = t.value.trim();
    const d = text ? HT.readDate(text) : null;
    if (!text) {
      delete row.dataset[`${key}Hint`];
      t.removeAttribute('aria-invalid');
    } else if (d && isFinite(d.t)) {
      row.dataset[`${key}Hint`] = String(Math.floor(d.t + 1e-9));
      t.removeAttribute('aria-invalid');
    } else t.setAttribute('aria-invalid', 'true');
  });
  /* 줄이 새로 그려질 때(폼 채우기 · ＋ 줄 추가 · 바탕 자료의 이름 상자)마다 미정인 칸 옆에 숫자 칸을 둡니다 */
  new MutationObserver(list => {
    for (const m of list)
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue;
        if (n.matches(HINT_EDGE)) syncHint(n);
        n.querySelectorAll(HINT_EDGE).forEach(syncHint);
      }
  }).observe(document.documentElement, { childList: true, subtree: true });

  HT.formKeys = { STOP, SUB_BOXES, KEYS, attach, isRow, rowOf, colKey, caretOnEdge, reveal, visible, syncHint };
})();

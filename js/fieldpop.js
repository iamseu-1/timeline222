/* 역사 연표 — 큰 입력 창 (HT.fieldPop)
 *
 * 메이커의 긴 글 칸(설명 · 쟁점 · 문서 · 메모 …)을 화면 위에 떠 있는 큰 창에서 씁니다. 창과 원래 칸의 글은 늘 같습니다(비추기).
 *   여는 길: 긴 글 칸(textarea)의 이름표 줄에 있는 작은 [크게] 단추 · 초점 있는 칸에서 Alt+Enter
 *            (textarea와 허용 목록의 글 input — 설명 · 메모 · 출처 …, 날짜 · id · 검색 · 이름 칸은 아님)
 *   창: 제목 = 칸 이름 길 · 큰 글 칸 · 글자 수 · 닫기. 제목 줄을 끌어 옮기고 모서리를 끌어 크기를 바꿉니다(자리 · 크기는 기억).
 *       한 번에 하나 — 다른 칸에서 열면 같은 창이 그 칸으로. Esc · Alt+Enter는 이 창만 닫고, Ctrl+S는 원래 칸에 넘겨 그 폼이 저장합니다.
 *
 * 비추기 규칙 (한글 조합이 끊기거나 커서가 튀지 않게):
 *   (1) 창에 초점이 있는 동안은 창이 주인 — 원래 칸 → 창으로 옮기지 않습니다
 *   (2) 창 → 원래 칸: value를 쓰고 그 칸에서 input(bubbles)을 쏘되 ev.htMirror 표시를 달아, 이 창과 wiki.js의 편집기가 건너뜁니다. 닫을 때 change
 *   (3) 한글 조합 중인 칸과 값이 같을 때는 value를 대입하지 않습니다
 *   (4) 원래 칸 → 창은 사용자가 원래 칸에 직접 칠 때와 다시 묶을 때만
 * 다시 묶기는 좁게: 원래 칸이 다시 그려지면(편집 창이 저장한 뒤 같은 항목을 다시 채움) 같은 문맥(가까운 조상의 data-fp-ctx)에서
 *   name이 같은 칸, 줄 칸이면 "줄 순번 + 그 줄의 이름 · 시작 값"이 같은 줄의 같은 칸만 다시 찾습니다. 못 찾거나, 문맥이 바뀌었거나(다른 항목 · 다른 문서),
 *   칸이 닫혔으면(편집 창을 닫음 · 다른 DLC로 바꿈) 곧장 "원래 칸이 닫혔습니다" — 글은 복사할 수 있게 남기고 더는 어디에도 쓰지 않습니다(엉뚱한 칸을 덮어쓰지 않게).
 * 자리: <dialog> 안의 칸이면 창을 그 dialog 바로 아래(form 밖)에 붙이고(맨 위 층에 가려지지 않게), 아니면 body에. 단추는 모두 type="button".
 * 원래 칸이 한 줄 input이면: Enter = 닫기, 줄바꿈은 빈칸으로, maxlength를 물려받습니다.
 * 문서 칸(나무위키 편집기가 붙은 칸)이면 창의 글 칸에도 편집기(툴바 · [[ 자동 완성)를 새로 붙이고 닫을 때 뗍니다.
 * [↗ 새 창]: PC 브라우저에서만 창의 글 칸을 브라우저의 새 창으로 꺼냅니다(글 칸 하나 — 편집기 없음, 같은 비추기 규칙, 어느 쪽이 닫히든 정리).
 *
 * 부르는 쪽은 if (HT.fieldPop)로 가드합니다(새 판의 첫 오프라인 실행에서 이 파일이 아직 캐시에 없을 수 있음).
 * 연표(보기 전용)에는 고칠 칸이 없으므로 저절로 나타나지 않습니다. core.js · wiki.js · platform.js 뒤, viewer.js · maker.js 앞에 읽습니다.
 */
(() => {
  const HT = (window.HT = window.HT || {});
  const KEY = 'ht.fieldpop'; // 창의 자리 · 크기 (이 브라우저의 화면 설정)
  /** Alt+Enter로 여는 한 줄 input — 긴 글이 들어가는 칸만. 뒤에 생기는 칸(서명자 글 · 조항 본문 …)은 여기에 push하거나 칸에 data-fp를 답니다 (data-fp="off"는 빼기) */
  const INPUTS = ['input[data-fp]', 'input[name="source"]', 'input[name="note"]', 'input.c-note', 'input.s-note', 'input.view-desc'];
  INPUTS.push('input.p-sign'); // 조약 당사국 줄의 서명자 글 "이름(직함); 이름(직함)" (조항 본문은 글 칸이라 그대로 열림)
  const MIN_W = 360;
  const MIN_H = 240;
  /* 줄 칸의 "그 줄의 이름 · 시작 값" — 조약의 당사국 줄은 트랙 · 정권, 조항 줄은 번호 · 제목 (인물의 섬긴 기록 · 시기 · 지위 줄은 .s-from · .c-name · .c-start로 이미 잡힘) */
  const ROW_KEYS = '.c-name, .s-from, .view-track, .alt-year, .c-start, .p-track, .p-polity, .a-no, .a-title';
  const narrow = () => innerWidth <= 860;
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const num = v => (typeof v === 'number' && isFinite(v) ? Math.round(v) : null);
  /** 한 줄 칸으로 돌려보낼 글: 줄바꿈 → 빈칸 */
  const oneLine = s => String(s).replace(/\r\n?|\n/g, ' ');
  const cut = s => String(s || '').split(/\s[(—]/)[0].trim(); // "메모 (선택)" → "메모"
  const ownText = n => [...n.childNodes].filter(c => c.nodeType === 3).map(c => c.textContent).join('').trim(); // 이름표의 글만 (small · 단추 빼고)

  let win = null; // 창 요소 (처음 열 때 만듦)
  let ta = null; // 지금 쓰는 글 칸 — 이 화면의 창의 것, 또는 새 브라우저 창으로 꺼냈으면 그 창의 것
  let pane = null; // 지금 쓰는 창의 뿌리 (제목 · 글자 수 · 닫힘 알림을 여기서 찾음)
  let ext = null; // 꺼낸 새 브라우저 창 (window) — 없으면 null
  let extTimer = 0;
  let bar = null; // 문서 칸일 때의 문법 툴바
  let cur = null; // 지금 묶인 칸의 기록 — { orig, ctx, root, scope, name, row, single, start, synced, closed, … }
  let ui = null; // 기억한 자리 · 크기 { x, y, w, h }
  let trapped = false; // 모바일 뒤로가기를 걸어 두었는지
  let escAt = -1; // 이 창이 Esc를 받은 때 — 창이 대화상자 안에 있으면 그 대화상자가 함께 닫히지 않게
  let seq = 0; // [크게]를 끼운 글 칸에 주는 id의 차례 번호 (attach)

  /* ---------- 대상 칸 ---------- */
  function isTarget(el) {
    if (!el || el.nodeType !== 1 || el.disabled || el.readOnly) return false;
    if (el.getAttribute('data-fp') === 'off' || (win && win.contains(el))) return false;
    if (el.tagName === 'TEXTAREA') return true;
    return el.tagName === 'INPUT' && el.type === 'text' && el.matches(INPUTS.join(','));
  }
  /** 보이는 칸인지: 문서에 붙어 있고, 숨긴 조상이 없고, 대화상자 안이면 그 대화상자가 열려 있음 */
  const shown = x => {
    if (!x || !x.isConnected || x.closest('[hidden]')) return false;
    const d = x.closest('dialog');
    return !d || d.open;
  };
  /** 문맥: 가까운 조상의 data-fp-ctx — 편집 창은 항목을 새로 채울 때마다, 문서 편집기는 문서 키마다 바뀝니다 */
  const ctxOf = x => {
    const h = x.closest('[data-fp-ctx]');
    return h ? h.getAttribute('data-fp-ctx') : '';
  };
  /** 칸을 품은 창(편집 창 · 문서 창 · 대화상자) — 여기서 칸이 다시 그려지거나 닫히는 것을 지켜봅니다 */
  const scopeOf = x => x.closest('[data-fp-scope], dialog') || x.form || x.parentElement;
  const rowsOf = (box, cls) => [...box.children].filter(r => r.classList.contains(cls));
  const rowSig = row => [...row.querySelectorAll(ROW_KEYS)].map(x => x.value).join('');
  /** 줄 칸(지도자 · 도읍 · 승계 … 줄의 메모 같은)의 자리: 줄 묶음의 data-* · 줄 클래스 · 칸 클래스 · 줄 순번 · 그 줄의 이름과 시작 값 */
  function rowInfo(el) {
    const row = el.parentElement;
    const cls = row && [...row.classList].find(c => /-row$/.test(c));
    const box = cls && row.parentElement;
    const attr = box && [...box.attributes].find(a => a.name.startsWith('data-'));
    const field = el.classList[0];
    if (!attr || !field) return null;
    const sel = `[${attr.name}${attr.value ? `="${CSS.escape(attr.value)}"` : ''}]`;
    /* 같은 묶음이 폼에 여럿이면(시기 구분의 체계마다 data-phase-rows) 몇 번째 묶음인지도 — 다른 체계의 같은 순번 줄에 묶이지 않게 */
    const root = el.form || scopeOf(el);
    const bi = root ? [...root.querySelectorAll(sel)].indexOf(box) : 0;
    return { box: sel, bi: Math.max(0, bi), cls, field, idx: rowsOf(box, cls).indexOf(row), sig: rowSig(row) };
  }

  /** 창 제목: 칸 이름 길 — "사건 수정 › «제목» › 문서 (위키) › 본문" */
  function pathOf(el) {
    const parts = [];
    const scope = el.closest('[data-fp-scope], dialog');
    const h = scope && scope.querySelector('h2');
    if (h && h.textContent.trim()) parts.push(h.textContent.trim());
    const form = el.form;
    const nameEl = form && (form.elements.namedItem('title') || form.elements.namedItem('name'));
    if (nameEl && nameEl !== el && nameEl.tagName === 'INPUT' && nameEl.value.trim()) parts.push(`«${nameEl.value.trim()}»`);
    const labels = [];
    for (let n = el.parentElement; n && n !== scope && n !== form; n = n.parentElement) {
      if (n.tagName === 'DETAILS') {
        const sum = n.querySelector(':scope > summary');
        const s = sum ? cut(sum.textContent.split(' — ')[0]) : '';
        if (s && s.length <= 16) labels.unshift(s);
      } else if (n.classList.contains('field')) {
        const head = n.firstElementChild;
        if (head && head.tagName === 'SPAN' && !head.contains(el) && ownText(head)) labels.unshift(ownText(head));
      }
    }
    parts.push(...labels.slice(-2));
    const direct = el.parentElement && el.parentElement.classList.contains('field');
    const row = !el.getAttribute('name') && rowInfo(el);
    const own = cut(el.getAttribute('aria-label') || el.placeholder || el.title || '');
    if (row && row.idx >= 0) parts.push(`${row.idx + 1}번째 줄${own ? ` ${own}` : ''}`);
    else if (!direct && own) parts.push(own);
    return parts.join(' › ') || '글';
  }

  /* ---------- 창 ---------- */
  const CLOSED_HTML = '<div class="fp-closed" role="status" hidden><span></span><button type="button" class="btn btn-sm" data-fp-act="copy">복사</button></div>';
  /** "원래 칸이 닫혔습니다"의 글 — 사실만: 창의 글이 닫히기 전에 원래 칸에 다 들어갔는지 (저장했는지는 그 칸의 창에서 한 대로라 여기서 말하지 않음) */
  const closedText = synced =>
    synced
      ? '원래 칸이 닫혔습니다. 이 창의 글은 닫히기 전에 원래 칸에 모두 들어갔습니다 — 이제 이 창은 읽기만 됩니다.'
      : '원래 칸이 닫혔습니다. 이 창의 글 가운데 원래 칸에 들어가지 못한 것이 있으니, 필요하면 복사해 두세요.';
  /** 지금 쓰는 글 칸에 초점이 있는지 (새 브라우저 창이면 그 창이 앞에 있을 때만) */
  const focused = () => {
    if (!ta) return false;
    const d = ta.ownerDocument;
    return pane.contains(d.activeElement) && (d === document || d.hasFocus());
  };
  /** 글 칸 · 단추에 듣는 것을 붙입니다 — 이 화면의 창과 꺼낸 새 브라우저 창이 함께 씀 (지금 쓰는 글 칸이 아닌 것에서 온 것은 건너뜀) */
  function wire(t, root) {
    t.addEventListener('input', e => {
      if (e.htMirror || t !== ta) return;
      if (cur && !cur.closed) {
        if (cur.single && !e.isComposing && ta.value.includes('\n')) {
          const a = ta.selectionStart;
          const b = ta.selectionEnd;
          ta.value = oneLine(ta.value); // 같은 길이라 커서가 그 자리에 남습니다
          ta.setSelectionRange(a, b);
        }
        push();
      }
      count();
    });
    t.addEventListener('compositionstart', () => t === ta && cur && (cur.popComposing = true));
    t.addEventListener('compositionend', () => t === ta && cur && (cur.popComposing = false));
    /* 창에 들어올 때: 창을 떠나 있는 동안 원래 칸이 따로 바뀌었으면(단추가 글을 넣은 것 같은) 그것을 받아 옵니다 — 받아 오지 않으면 다음 글자가 그것을 지웁니다 */
    t.addEventListener('focus', () => {
      if (t !== ta || !cur || cur.closed) return;
      check();
      if (cur && !cur.closed && cur.orig.value !== cur.synced) pull();
    });
    root.addEventListener('keydown', e => {
      if (e.defaultPrevented || !root.contains(ta)) return; // [[ 자동 완성 같은 것이 먼저 받음
      const ctrl = e.ctrlKey || e.metaKey;
      if ((e.key === 'Escape' || (e.key === 'Enter' && e.altKey && !ctrl && t.ownerDocument !== document)) && !e.isComposing) {
        e.preventDefault();
        e.stopPropagation(); // 이 창만 닫습니다 (편집 창 · 상세는 그대로). 이 화면의 창의 Alt+Enter는 문서 전체의 단축키가 받음
        escAt = performance.now();
        return close();
      }
      if (e.target !== ta || !cur || cur.closed) return;
      if (ctrl && !e.altKey && (e.key === 's' || e.key === 'S' || e.key === 'Enter')) {
        e.preventDefault(); // 브라우저의 "페이지 저장"이 뜨지 않게
        e.stopPropagation();
        push();
        forward(e);
        return;
      }
      if (cur.single && e.key === 'Enter' && !ctrl && !e.altKey && !e.isComposing && e.keyCode !== 229) {
        e.preventDefault(); // 한 줄 칸: Enter = 닫기 (Shift+Enter도 줄을 바꾸지 않음)
        if (!e.shiftKey) close();
      }
    });
    root.addEventListener('click', e => {
      const b = e.target.closest('[data-fp-act]');
      if (!b || !root.contains(ta)) return;
      if (b.dataset.fpAct === 'close') close();
      else if (b.dataset.fpAct === 'copy') copy(b);
      else if (b.dataset.fpAct === 'out') popOut();
    });
  }
  function build() {
    if (win) return;
    win = document.createElement('section');
    win.className = 'fp-win';
    win.hidden = true;
    win.setAttribute('role', 'dialog');
    win.setAttribute('aria-label', '큰 입력 창');
    win.innerHTML = `
      <div class="mk-win-head fp-head" data-fp-drag title="제목 줄을 끌어 옮깁니다">
        <h2 class="fp-title"></h2>
        <button type="button" class="mk-btn" data-fp-act="out" hidden title="이 글 칸을 브라우저의 새 창으로 꺼냅니다 — 다른 모니터에 두고 쓸 수 있습니다 (문법 단추 · 자동 완성은 없음)">↗ 새 창</button>
        <button type="button" class="icon-btn" data-fp-act="close" aria-label="닫기" title="닫기 (Esc)">✕</button>
      </div>
      ${CLOSED_HTML}
      <div class="wiki-toolbar is-inline fp-bar" hidden></div>
      <textarea class="fp-text" spellcheck="false"></textarea>
      <div class="fp-foot"><span class="fp-count"></span><span class="fp-keys"></span><span class="spacer"></span><button type="button" class="btn btn-sm" data-fp-act="close">닫기</button></div>
      <div class="mk-win-corner fp-corner" data-fp-corner title="끌어서 크기 조절" aria-hidden="true"></div>`;
    ta = win.querySelector('.fp-text');
    bar = win.querySelector('.fp-bar');
    pane = win;
    document.body.appendChild(win);
    wire(ta, win);
    window.addEventListener('pagehide', () => ext && !ext.closed && ext.close()); // 이 화면이 닫히면 꺼낸 새 창도 함께
    /* 제목 줄을 끌어 옮기기 · 모서리를 끌어 크기 조절 — 포인터를 붙잡아 창 밖에서 손을 떼도 다른 곳이 눌린 것으로 처리되지 않게 */
    dragOn(win.querySelector('[data-fp-drag]'), () => {
      const r = win.getBoundingClientRect();
      return { x: r.left, y: r.top, w: r.width, h: r.height };
    }, (dx, dy, s) => ({ x: s.x + dx, y: s.y + dy, w: s.w, h: s.h }));
    dragOn(win.querySelector('[data-fp-corner]'), () => {
      const r = win.getBoundingClientRect();
      return { x: r.left, y: r.top, w: r.width, h: r.height };
    }, (dx, dy, s) => ({ x: s.x, y: s.y, w: s.w + dx, h: s.h + dy }));
    window.addEventListener('resize', () => !win.hidden && place());
  }
  function dragOn(handle, start, next) {
    handle.addEventListener('pointerdown', e => {
      if (e.button !== 0 || narrow() || e.target.closest('button, a, input, textarea, select')) return;
      const s = start();
      e.preventDefault(); // 끄는 동안 글이 골라지거나 초점이 창의 글 칸을 떠나지 않게
      try {
        handle.setPointerCapture(e.pointerId);
      } catch (err) {
        /* 시험용 합성 포인터는 붙잡을 수 없습니다 — 끌기는 그대로 */
      }
      const x0 = e.clientX;
      const y0 = e.clientY;
      let moved = false;
      const move = ev => {
        if (!moved && Math.hypot(ev.clientX - x0, ev.clientY - y0) < 3) return;
        moved = true;
        ui = fit(next(ev.clientX - x0, ev.clientY - y0, s));
        place();
      };
      const end = () => {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', end);
        handle.removeEventListener('pointercancel', end);
        if (moved && HT.store) HT.store.set(KEY, ui);
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', end);
      handle.addEventListener('pointercancel', end);
    });
  }
  /** 자리 · 크기를 화면 안으로 (제목 줄이 늘 잡을 수 있게 남음) */
  const fit = ({ x, y, w, h }) => {
    const W = clamp(w, MIN_W, Math.max(MIN_W, innerWidth - 16));
    const H = clamp(h, MIN_H, Math.max(MIN_H, innerHeight - 16));
    return { x: Math.round(clamp(x, 120 - W, innerWidth - 120)), y: Math.round(clamp(y, 0, Math.max(0, innerHeight - 48))), w: Math.round(W), h: Math.round(H) };
  };
  function rect() {
    if (!ui) {
      const s = HT.store ? HT.store.get(KEY, null) : null;
      ui = s && typeof s === 'object' && !Array.isArray(s) ? s : {};
    }
    const w = num(ui.w) || Math.min(760, innerWidth - 48);
    const h = num(ui.h) || Math.min(540, innerHeight - 120);
    return fit({ x: num(ui.x) ?? (innerWidth - w) / 2, y: num(ui.y) ?? Math.max(56, (innerHeight - h) / 2), w, h });
  }
  /** 좁은 화면(860px 이하)에서는 화면 전체를 덮는 시트 (css/maker.css) — 자리는 적지 않습니다 */
  function place() {
    if (narrow()) {
      win.style.left = win.style.top = win.style.width = win.style.height = '';
      return;
    }
    const r = rect();
    Object.assign(win.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
  }
  function show() {
    const was = !win.hidden;
    place();
    win.hidden = false;
    if (!was && HT.platform && HT.platform.mobile) {
      trapped = true;
      HT.platform.trapBack(() => {
        trapped = false; // 뒤로가기로 닫힘 — 기록을 한 번 더 되감지 않게
        close();
      });
    }
  }
  function hide() {
    if (!win || win.hidden) return;
    win.hidden = true;
    if (trapped) {
      trapped = false;
      HT.platform.releaseBack();
    }
    if (win.parentElement !== document.body) document.body.appendChild(win); // 대화상자 안에 붙였던 창은 제자리로
  }
  function setTitle(el) {
    const title = pathOf(el);
    const h = pane.querySelector('.fp-title');
    h.textContent = title;
    h.title = title;
    ta.setAttribute('aria-label', title);
    if (ext && ta.ownerDocument !== document) ta.ownerDocument.title = `${title} — 큰 입력 창`;
  }
  function count() {
    const n = ta.value.length;
    const max = ta.maxLength > 0 ? ta.maxLength : 0;
    pane.querySelector('.fp-count').textContent = max ? `${n.toLocaleString()} / ${max.toLocaleString()}자` : `${n.toLocaleString()}자`;
  }
  function setKeys() {
    const k = pane.querySelector('.fp-keys');
    k.textContent = cur && !cur.closed && cur.single ? '한 줄 칸 · Enter로 닫기' : 'Esc로 닫기';
    k.title = cur && !cur.closed && cur.single ? '한 줄 칸이라 줄바꿈은 빈칸이 됩니다. Esc로도 닫힙니다.' : '';
    const out = win.querySelector('[data-fp-act="out"]');
    out.hidden = !canOut() || !cur || cur.closed; // 새 창으로 꺼내기는 PC 브라우저에서만 (앱 · 모바일 · 설치형 웹앱은 창이 하나)
  }
  async function copy(btn) {
    const text = ta.value;
    const d = ta.ownerDocument;
    const toast = (m, t) => HT.toast && HT.toast(m, t);
    let ok = false;
    try {
      await d.defaultView.navigator.clipboard.writeText(text);
      ok = true;
    } catch (err) {
      ta.focus();
      ta.select();
      try {
        ok = d.execCommand('copy');
      } catch (e2) {
        ok = false;
      }
    }
    toast(ok ? '글을 복사했습니다.' : '복사하지 못했습니다 — 글이 골라져 있으니 Ctrl+C로 복사하세요.', ok ? 'ok' : 'error');
    if (ok && btn) {
      btn.textContent = '복사함'; // 새 창에서는 알림이 이 화면에 뜨므로 단추에도
      setTimeout(() => (btn.textContent = '복사'), 1500);
    }
  }

  /* ---------- 새 브라우저 창으로 꺼내기 (PC 브라우저에서만 — 글 칸 하나, 문법 단추 · 자동 완성은 없음) ----------
   * 비추기 규칙은 같습니다(그 창이 앞에 있고 글 칸에 초점이 있으면 그 창이 주인). 한 번에 하나 — 꺼내 둔 채 다른 칸을 열면 그 창이 그 칸으로.
   * 어느 쪽이 닫히든 정리: 새 창을 닫으면 묶음을 마치고(바뀌었으면 change), 이 화면이 닫히면 새 창도 닫힙니다. 원래 칸이 닫히면 새 창에도 "원래 칸이 닫혔습니다" */
  const canOut = () => !!(HT.platform && HT.platform.name === 'web' && !HT.platform.mobile);
  const token = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
  function extCSS() {
    const t = n => token(n) || 'initial';
    return `*{box-sizing:border-box}html,body{height:100%;margin:0}
body{background:${t('--surface')};color:${t('--text')};font:14px/1.5 ${t('--font')};letter-spacing:-.01em}
.fp-ext{display:flex;flex-direction:column;height:100%}
.fp-head{display:flex;align-items:center;gap:10px;min-width:0;padding:10px 12px 10px 16px;border-bottom:1px solid ${t('--line')}}
.fp-title{flex:1;min-width:0;margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:14.5px;font-weight:700}
.fp-closed{display:flex;align-items:center;gap:10px;margin:10px 14px 0;padding:8px 10px 8px 12px;border-radius:10px;background:color-mix(in srgb,${t('--warn')} 16%,transparent);font-size:13px;line-height:1.5}
.fp-closed[hidden]{display:none}.fp-closed span{flex:1;min-width:0}
.fp-text{flex:1;min-height:0;margin:10px 14px 0;padding:12px 14px;border:1px solid ${t('--line')};border-radius:9px;background:${t('--surface-2')};color:inherit;font-size:15px;line-height:1.7;resize:none;outline:none}
.fp-text:focus{background:${t('--surface')};border-color:color-mix(in srgb,${t('--accent')} 60%,transparent);box-shadow:0 0 0 3px color-mix(in srgb,${t('--accent')} 20%,transparent)}
.is-closed .fp-text{color:${t('--text-2')};background:${t('--surface-2')}}
.fp-foot{display:flex;align-items:center;gap:10px;min-width:0;padding:8px 14px 10px 18px;font-size:12px;color:${t('--text-3')};font-variant-numeric:tabular-nums}
.fp-foot .spacer{flex:1}.fp-keys{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
button{height:28px;padding:0 11px;border:0;border-radius:8px;background:${t('--surface-2')};color:${t('--text')};font:inherit;font-size:12.5px;font-weight:500;cursor:pointer}
button:hover{background:color-mix(in srgb,${t('--surface-2')} 88%,${t('--text')})}`;
  }
  function popOut() {
    if (!cur || cur.closed || !canOut() || ext) return;
    const r = win.getBoundingClientRect();
    const top = window.screenY + Math.max(0, window.outerHeight - window.innerHeight) + r.top;
    const w = window.open('', 'ht-fieldpop', `popup=yes,width=${Math.round(r.width)},height=${Math.round(r.height)},left=${Math.round(window.screenX + r.left)},top=${Math.round(top)}`);
    if (!w) {
      if (HT.toast) HT.toast('새 창을 열지 못했습니다 — 브라우저가 팝업을 막았는지 확인하세요.', 'error');
      return;
    }
    const d = w.document;
    d.documentElement.lang = 'ko';
    d.head.innerHTML = `<style>${extCSS()}</style>`;
    d.body.innerHTML = `<div class="fp-ext" role="dialog" aria-label="큰 입력 창"><div class="fp-head"><h1 class="fp-title"></h1></div>${CLOSED_HTML}<textarea class="fp-text"></textarea><div class="fp-foot"><span class="fp-count"></span><span class="fp-keys"></span><span class="spacer"></span><button type="button" data-fp-act="close">닫기</button></div></div>`;
    const root = d.body.firstElementChild; // 부를 때마다 새 요소 — 같은 이름의 창을 다시 써도 듣는 것이 겹치지 않게
    const t = root.querySelector('.fp-text');
    /* 이 화면의 창에서 넘김: 글 · 커서 · 칸의 성질을 옮기고, 문서 칸의 편집기는 떼고, 이 화면의 창은 숨김 */
    const a = ta.selectionStart;
    const b = ta.selectionEnd;
    t.value = ta.value;
    if (ta.maxLength > 0) t.maxLength = ta.maxLength;
    t.style.fontFamily = ta.style.fontFamily;
    t.style.whiteSpace = ta.style.whiteSpace;
    t.spellcheck = ta.spellcheck;
    if (cur.editor) {
      cur.editor.destroy();
      cur.editor = null;
      bar.hidden = true;
      bar.innerHTML = '';
    }
    hide();
    ext = w;
    ta = t;
    pane = root;
    wire(t, root);
    setTitle(cur.orig);
    count();
    setKeys();
    w.addEventListener('pagehide', gone);
    extTimer = setInterval(() => ext && ext.closed && gone(), 600); // 창을 닫은 알림이 오지 않는 경우를 위해
    w.focus();
    t.focus();
    t.setSelectionRange(a, b);
  }
  /** 새 창이 닫혔거나 닫을 때: 묶음을 마치고(바뀌었으면 change) 이 화면의 창으로 되돌려 둠(숨긴 채) */
  function gone() {
    if (!ext) return;
    clearInterval(extTimer);
    const w = ext;
    ext = null;
    const o = finish();
    ta = win.querySelector('.fp-text');
    pane = win;
    if (!w.closed) w.close();
    return o;
  }

  /* ---------- 묶기 · 비추기 ---------- */
  function fire(o, type) {
    const ev = new Event(type, { bubbles: true });
    ev.htMirror = true; // 창과 wiki.js의 편집기가 이 이벤트를 건너뜁니다 (규칙 2)
    o.dispatchEvent(ev);
  }
  /** 창 → 원래 칸 (규칙 2 · 3) */
  function push() {
    check(); // 원래 칸이 그대로인지 먼저 — 다시 그려졌으면 다시 묶거나, 닫혔으면 여기서 멈춤
    if (!cur || cur.closed) return;
    const o = cur.orig;
    const v = ta.value;
    if (o.value !== v && !cur.origComposing) {
      o.value = v;
      fire(o, 'input');
    }
    cur.synced = v;
    refreshRow();
  }
  /** Ctrl+S · Ctrl+Enter는 원래 칸에 넘깁니다 — 그 칸의 폼(편집 창 · 문서 편집기)이 제 단축키대로 저장합니다 */
  function forward(e) {
    if (!cur || cur.closed) return;
    cur.orig.dispatchEvent(new KeyboardEvent('keydown', { key: e.key, code: e.code, ctrlKey: e.ctrlKey, metaKey: e.metaKey, shiftKey: e.shiftKey, bubbles: true, cancelable: true }));
    /* 그 저장이 칸을 곧바로 닫았으면(문서 편집기는 저장하면 읽기 화면으로 돌아감) 창도 함께 닫습니다 — 창의 글은 방금 저장한 그대로이니 "원래 칸이 닫혔습니다"를 띄우지 않습니다.
       저장하지 못했으면 칸이 그대로 남고, 같은 항목을 다시 채웠으면 다시 찾아지므로 닫지 않습니다 */
    if (cur && !cur.closed && ta.value === cur.synced && !locate()) close();
  }
  /** 원래 칸 → 창 (규칙 3 · 4) */
  function pull() {
    const v = cur.orig.value;
    cur.synced = v;
    if (ta.value === v || cur.popComposing) return;
    ta.value = v;
    count();
  }
  /** 줄 순번과 그 줄의 이름 · 시작 값은 열 때 한 번이 아니라 글이 오갈 때마다 지금 화면에서 다시 셉니다 (위 줄을 지우거나 이름을 고쳐도 낡지 않게) */
  function refreshRow() {
    if (!cur || !cur.row || !cur.orig.isConnected) return;
    const r = rowInfo(cur.orig);
    if (r) cur.row = r;
  }
  const onOrigInput = e => {
    if (e.htMirror || !cur || cur.closed || e.target !== cur.orig) return;
    if (focused()) return; // 규칙 1: 창에 초점이 있는 동안은 창이 주인
    pull(); // 규칙 4: 원래 칸에 직접 친 글
  };
  const onOrigComp = e => cur && (cur.origComposing = e.type === 'compositionstart');
  const onRootInput = () => refreshRow();
  function hookOrig() {
    const o = cur.orig;
    o.addEventListener('input', onOrigInput);
    o.addEventListener('compositionstart', onOrigComp);
    o.addEventListener('compositionend', onOrigComp);
    cur.origComposing = false;
  }
  function unhookOrig() {
    const o = cur.orig;
    o.removeEventListener('input', onOrigInput);
    o.removeEventListener('compositionstart', onOrigComp);
    o.removeEventListener('compositionend', onOrigComp);
  }
  /** 칸을 품은 창이 다시 그려지거나 닫히는 것을 지켜봅니다 (그 창 안만 — 연표의 잦은 변화는 보지 않음) */
  function watch() {
    cur.mo = new MutationObserver(records => {
      if (!cur || cur.closed || records.every(r => win.contains(r.target))) return;
      check();
    });
    cur.mo.observe(cur.scope, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden', 'open', 'data-fp-ctx'] });
    cur.root.addEventListener('input', onRootInput);
    const d = win.parentElement;
    if (d && d.tagName === 'DIALOG') {
      cur.dialog = d;
      d.addEventListener('cancel', onCancel);
    }
  }
  /** 창이 대화상자 안에 있을 때 창에서 누른 Esc가 대화상자까지 닫지 않게 */
  const onCancel = e => {
    if (performance.now() - escAt < 80) e.preventDefault();
  };
  /** 묶음을 모두 풉니다 (창의 글은 그대로) */
  function unhook() {
    if (!cur) return;
    if (!cur.closed) unhookOrig();
    if (cur.mo) cur.mo.disconnect();
    cur.root.removeEventListener('input', onRootInput);
    if (cur.dialog) cur.dialog.removeEventListener('cancel', onCancel);
    if (cur.editor) cur.editor.destroy();
    cur.mo = cur.editor = cur.dialog = null;
    bar.hidden = true;
    bar.innerHTML = '';
  }
  /** 원래 칸을 찾습니다 — 그대로면 그 칸, 다시 그려졌으면 좁은 규칙으로 다시 찾은 칸, 못 찾거나 문맥이 바뀌었거나 닫혔으면 null */
  function locate() {
    const c = cur;
    const o = c.orig;
    if (o.isConnected) return shown(o) && ctxOf(o) === c.ctx ? o : null;
    if (!shown(c.root) || ctxOf(c.root) !== c.ctx) return null;
    let found = null;
    if (c.name) {
      const same = [...c.root.querySelectorAll(`[name="${CSS.escape(c.name)}"]`)].filter(x => x.tagName === c.tag);
      found = same.length === 1 ? same[0] : null;
    } else if (c.row) {
      const box = c.root.querySelectorAll(c.row.box)[c.row.bi || 0];
      const row = box ? rowsOf(box, c.row.cls)[c.row.idx] : null;
      found = row && rowSig(row) === c.row.sig ? row.querySelector(`:scope > .${CSS.escape(c.row.field)}`) : null;
    }
    return found && shown(found) && ctxOf(found) === c.ctx && isTarget(found) ? found : null;
  }
  /** 원래 칸이 그대로인지 봅니다: 다시 그려졌으면 다시 묶고, 못 찾으면 "원래 칸이 닫혔습니다" */
  function check() {
    if (!cur || cur.closed) return;
    const o = locate();
    if (!o) return detach();
    if (o === cur.orig) return;
    unhookOrig();
    cur.orig = o;
    hookOrig();
    /* 다시 묶을 때: 창에 초점이 있으면 창이 주인(저장하면서 다듬어진 끝 빈칸 같은 것이 치던 글을 흔들지 않게), 아니면 원래 칸의 글을 받아 옴 */
    if (focused()) {
      if (o.value !== ta.value) {
        o.value = ta.value;
        fire(o, 'input');
      }
      cur.synced = ta.value;
    } else pull();
    refreshRow();
    setTitle(o); // "사건 추가" → "사건 수정 › «제목»" 처럼 새 모습으로
  }
  /** 원래 칸과의 묶음을 끊고 "원래 칸이 닫혔습니다"로 — 글은 남겨 복사할 수 있게, 더는 어디에도 쓰지 않습니다. 부르는 쪽: 다른 DLC로 바꿀 때 강제로 */
  function detach() {
    if (!cur || cur.closed) return;
    const d = win.parentElement;
    if (d && d.tagName === 'DIALOG' && !d.open) return close(); // 대화상자가 닫혔으면 창도 함께 (다시 연 대화상자에 남지 않게)
    unhook();
    cur.closed = true;
    ta.readOnly = true;
    pane.querySelector('.fp-closed span').textContent = closedText(ta.value === cur.synced);
    pane.querySelector('.fp-closed').hidden = false;
    pane.classList.add('is-closed');
    setKeys();
  }
  /** 지금 칸과의 묶음을 마칩니다: 글이 바뀌었으면 원래 칸에 change. 돌려주는 값: 그 칸(닫혔으면 null) */
  function finish() {
    if (!cur) return null;
    const o = cur.closed ? null : locate();
    unhook();
    if (o && o.value !== cur.start) fire(o, 'change');
    cur = null;
    return o;
  }

  /** 칸을 큰 입력 창에서 엽니다. 이미 다른 칸에서 열려 있으면 같은 창이 이 칸으로 옮겨 옵니다 */
  function open(el) {
    if (!isTarget(el)) return false;
    build();
    if (ext && ext.closed) gone(); // 꺼낸 새 창이 닫혔는데 알림이 아직 오지 않음
    const outside = !!ext; // 새 창으로 꺼내 두었으면 그 창이 이 칸으로 옮겨 감
    if (cur && !cur.closed && cur.orig === el && (outside || !win.hidden)) {
      if (outside) ext.focus();
      ta.focus(); // 이미 이 칸의 창 — 그대로
      return true;
    }
    const hadFocus = el.ownerDocument.activeElement === el;
    const selA = hadFocus ? el.selectionStart : null;
    const selB = hadFocus ? el.selectionEnd : null;
    finish();
    const host = el.closest('dialog') || document.body; // 대화상자 안의 칸이면 그 대화상자 바로 아래(form 밖) — 맨 위 층에 가려지지 않게
    if (!outside && win.parentElement !== host) host.appendChild(win);
    cur = {
      orig: el,
      tag: el.tagName,
      single: el.tagName === 'INPUT',
      name: el.getAttribute('name') || '',
      ctx: ctxOf(el),
      scope: scopeOf(el),
      root: el.form || scopeOf(el),
      row: el.getAttribute('name') ? null : rowInfo(el),
      start: el.value,
      synced: el.value,
      closed: false,
      popComposing: false,
      origComposing: false,
    };
    ta.readOnly = false;
    ta.value = cur.single ? oneLine(el.value) : el.value;
    if (el.maxLength > 0) ta.maxLength = el.maxLength;
    else ta.removeAttribute('maxlength');
    const cs = getComputedStyle(el);
    ta.style.fontFamily = cs.fontFamily; // 문서 · 표 칸은 고정폭 글꼴 그대로
    ta.style.whiteSpace = cur.single ? 'pre-wrap' : cs.whiteSpace;
    ta.spellcheck = el.spellcheck;
    setTitle(el);
    pane.querySelector('.fp-closed').hidden = true;
    pane.classList.remove('is-closed');
    /* 문서 칸: 창의 글 칸에도 나무위키 편집기를 새로 (이름 목록은 원래 칸의 편집기가 남긴 옵션에서 — 저장은 Ctrl+S를 원래 칸에 넘겨서). 꺼낸 새 창에는 붙이지 않음 */
    const wk = el.htNamuOpts;
    if (wk && HT.namu && !outside) {
      bar.innerHTML = HT.namu.toolbarHTML({ compact: true });
      bar.hidden = false;
      cur.editor = HT.namu.editor(ta, { toolbar: bar, names: wk.names });
    }
    hookOrig();
    watch();
    setKeys();
    count();
    if (outside) ext.focus();
    else show();
    ta.focus({ preventScroll: true });
    const end = ta.value.length;
    ta.setSelectionRange(selA ?? end, selB ?? end);
    return true;
  }
  /** 창을 닫습니다 (글이 바뀌었으면 원래 칸에 change, 창에 초점이 있었으면 원래 칸으로 돌려줌) */
  function close() {
    if (!win) return;
    if (ext) {
      /* 꺼낸 새 창: 그 창을 닫고 이 화면의 원래 칸으로 */
      const o = gone();
      if (o) {
        window.focus();
        o.focus({ preventScroll: true });
      }
      return;
    }
    const hadFocus = win.contains(document.activeElement);
    const a = ta.selectionStart;
    const b = ta.selectionEnd;
    const o = finish();
    hide();
    if (o && hadFocus) {
      o.focus({ preventScroll: true });
      try {
        o.setSelectionRange(a, b);
      } catch (e) {
        /* 고를 수 없는 칸 */
      }
      if (o.scrollIntoView) o.scrollIntoView({ block: 'nearest' });
    }
  }

  /** 긴 글 칸(textarea)의 이름표 줄에 작은 [크게] 단추를 끼웁니다 — 폼을 채운 뒤 부르고, 여러 번 불러도 한 번만 (이름표 줄이 없는 칸은 Alt+Enter만)
   *  이름표(<label class="field">)에 for가 없으면 그 안의 첫 단추가 이름표의 칸이 되어, 이름표 글자를 누르면 [크게]가 눌리고 글 칸은 이름을 잃습니다 —
   *  그래서 글 칸에 id를 주고(없으면) 이름표의 for로 글 칸을 가리켜 둡니다(누르면 예전처럼 글 칸에 초점) */
  function attach(root) {
    if (!root || !root.querySelectorAll) return;
    for (const t of root.querySelectorAll('textarea')) {
      const field = t.parentElement;
      if (!field || !field.classList.contains('field') || !isTarget(t)) continue;
      const head = field.firstElementChild;
      if (!head || head.tagName !== 'SPAN' || head.querySelector(':scope > .fp-open')) continue;
      if (field.tagName === 'LABEL' && !field.htmlFor) {
        if (!t.id) {
          let id;
          do id = `fp-text-${++seq}`;
          while (document.getElementById(id));
          t.id = id;
        }
        field.htmlFor = t.id;
      }
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'fp-open';
      b.textContent = '크게';
      b.title = '크게 쓰기 — 큰 입력 창에서 씁니다 (Alt+Enter)';
      b.setAttribute('aria-label', `${ownText(head) || '글'} 크게 쓰기`);
      head.prepend(b);
    }
  }

  /* 여는 길: [크게] 단추 · Alt+Enter (다른 것보다 먼저 받아 위키 목록 이어쓰기 · 자동 완성의 Enter에 먹히지 않게) */
  document.addEventListener('click', e => {
    const b = e.target && e.target.closest && e.target.closest('.fp-open');
    if (!b) return;
    e.preventDefault();
    const field = b.closest('.field');
    const t = field && [...field.children].find(c => c.tagName === 'TEXTAREA');
    if (t) open(t);
  });
  document.addEventListener(
    'keydown',
    e => {
      if (e.key !== 'Enter' || !e.altKey || e.ctrlKey || e.metaKey || e.isComposing) return;
      if (win && !win.hidden && win.contains(e.target)) {
        e.preventDefault();
        e.stopPropagation();
        return close();
      }
      if (!isTarget(e.target)) return;
      e.preventDefault();
      e.stopPropagation();
      open(e.target);
    },
    true
  );
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => attach(document));
  else attach(document); // 페이지에 처음부터 있는 칸 (DLC 정보의 설명 같은)

  HT.fieldPop = {
    INPUTS,
    oneLine,
    attach,
    open,
    close,
    detach,
    check,
    isOpen: () => !!ext || (!!win && !win.hidden),
    /** 새 브라우저 창으로 꺼내 두었는지 */
    get outside() {
      return !!ext;
    },
    /** 지금 묶인 원래 칸 (닫혔거나 없으면 null) */
    get bound() {
      return cur && !cur.closed ? cur.orig : null;
    },
    /** "원래 칸이 닫혔습니다" 상태인지 */
    get closed() {
      return !!(cur && cur.closed);
    },
  };
})();

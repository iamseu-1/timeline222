/* 역사 연표 — 렌즈 고르기 (설계 docs/설계-10건/7-8-단체와-렌즈.md 결정 6 B — 감독 선택 2026-10-12).
 * 위 단추 줄(독)의 렌즈 단추(눈 기호 — 건의 8) + 차림표. 감독 덧붙임 "렌즈 종류도 dlc 조정 가능하게" — 차림표의 주제는 모델의 주제 사전(HT.lensThemes:
 * 내장 여덟 + DLC가 더한 주제, DLC가 바꾼 이름 · 색, DLC가 렌즈에서 숨긴 주제는 빠짐 — DLC-형식.md '주제 사전' 절).
 * 연표 화면(index.html)에서 js/viewer.js 다음에 읽혀 스스로 붙습니다 — viewer.js는 고치지 않고 공개 API(HT.viewer: 연표 · 상태)만 씁니다.
 *   · 단추: 기호만(눈 — 건의 8 감독 선택 '1. A · 가'). 켠 동안 반전 채움 + 오른쪽 위에 주제 색 점, 주제 이름은 풍선('렌즈 · 주제 (S)')과 차림표의 체크로만.
 *     끄기는 차림표의 '없음'과 Esc
 *   · 차림표: 없음(지도자 칸 그대로 · Esc) · 주제(색 점 · 이름 · 한마디 · 자료 없음) · 켠 렌즈의 갈래 견본(같은 색 = 나라 너머 같은 갈래) · 앞뒤로 넘기기(S · Shift+S)
 *   · 단축키: S 다음 렌즈 · Shift+S 앞 렌즈 · Esc는 한 번에 하나씩, 위에 떠 있는 것부터(차림표 → 상세 창 → 렌즈 끔 → 집중 모드 끔)
 *   · ⋯ 차림표(오른쪽 클릭 차림표도)에 '렌즈' 한 줄(눈 기호 · 켠 동안 체크) — 누르면 이 차림표
 *   · 보는 사람의 설정 ui.themeLens(바탕 5)에 기억 — 다음에 열어도 그 렌즈. 그 주제가 사라지거나(DLC를 끔) 숨으면 끄고 설정도 지움
 * 띠 위의 그림은 js/timeline.js(setThemeLens · _lensRow), 칸의 셈은 js/core.js(HT.lensCellsOf) */
(function () {
  'use strict';
  const HT = window.HT;
  const V = HT && HT.viewer;
  if (!V || !V.timeline || !V.state) return;
  const tl = V.timeline;
  const state = V.state;
  const esc = s => HT.escapeHtml(s == null ? '' : String(s));
  const K = HT.KEYS;
  const NONE_C = '#999999'; // '없음'(지도자 칸 그대로)의 점: 어느 주제의 색도 아닌 잉크 40%(흰 종이 위의 값 — HistoryArchive 통일)

  /* 단추: index.html의 #themeLensBtn (없으면 독의 ⋯ 앞에 만듦 — 다른 화면에서 읽혀도 스스로 붙게) */
  let btn = document.getElementById('themeLensBtn');
  if (!btn) {
    /* 메이커(작업실)에는 독이 없어 가운데 탭 줄(연표 · 표 · 문서)의 보는 범위 앞에 끼웁니다 — '집합 보기' 단추와 같은 자리(js/views-ui.js).
       만드는 사람이 주제 사전의 '렌즈에서 숨김' · 이름 · 색을 고친 결과를 미리보기에서 바로 보게(감독 덧붙임 "렌즈 종류도 dlc 조정 가능하게") */
    const actions = document.querySelector('.dock-actions');
    const bar = actions ? null : document.getElementById('mkCTabs');
    if (!actions && !bar) return;
    btn = document.createElement('button');
    btn.id = 'themeLensBtn';
    btn.type = 'button';
    btn.className = 'dock-btn lens-btn';
    btn.setAttribute('aria-haspopup', 'menu');
    btn.setAttribute('aria-expanded', 'false');
    if (actions) actions.insertBefore(btn, document.getElementById('menuBtn'));
    else {
      const range = document.getElementById('viewRange');
      bar.insertBefore(btn, range && range.parentNode === bar ? range : null);
    }
  }
  const menu = document.createElement('div');
  menu.id = 'themeLensMenu';
  menu.className = 'ctx-menu lens-menu';
  menu.setAttribute('role', 'menu');
  menu.setAttribute('aria-label', '렌즈');
  menu.hidden = true;
  document.body.appendChild(menu);

  const model = () => state.model;
  const themes = () => HT.lensThemes(model());
  const current = () => {
    const id = tl.themeLens && tl.themeLens.id;
    return id ? themes().find(t => t.id === id) || null : null;
  };
  const save = () => {
    try {
      HT.store.set(K.ui, state.ui);
    } catch (e) {
      /* 저장소를 쓸 수 없어도 렌즈는 켜짐 (다음에 열면 기억하지 못할 뿐) */
    }
  };

  /** 렌즈 켜고 끄기 (id ''면 끔) — 연표 · 단추 · 설정을 함께 */
  function setLens(id) {
    const t = id ? themes().find(x => x.id === id) || null : null;
    state.ui.themeLens = t ? t.id : '';
    save();
    tl.setThemeLens(t);
    paint();
    if (!menu.hidden) render();
  }

  /** 모델이 바뀐 뒤(DLC 켜고 끔 · 반영): 켠 렌즈의 주제가 아직 있고 숨지 않았는지 — 이름 · 색이 바뀌었으면 따라 고침.
      모델을 짓기 전(이 부품이 붙는 때 — 뷰어는 글꼴이 열린 뒤에 모델을 지음)에는 견주지 않고 기억을 그대로 둠: 주제 사전이 내장 여덟뿐이라
      DLC가 더한 주제로 켠 렌즈를 지워 버리므로. 모델이 생기면 연표의 tl-data가 다시 부름 */
  function sync() {
    const ready = !!model();
    const want = state.ui.themeLens || '';
    const t = want && ready ? themes().find(x => x.id === want) || null : null;
    if (want && ready && !t) {
      state.ui.themeLens = '';
      save();
    }
    tl.setThemeLens(t);
    paint();
    if (!menu.hidden) render();
  }

  function paint() {
    const t = current();
    btn.classList.toggle('is-on', !!t);
    if (t) btn.style.setProperty('--tc', t.color);
    else btn.style.removeProperty('--tc');
    if (!btn.querySelector('svg.ic') && HT.icon) btn.innerHTML = HT.icon('eye'); // 기호만 — 이름은 풍선에 (건의 8)
    btn.title = t ? `렌즈 · ${t.name} (S)` : '렌즈 (S)';
    btn.setAttribute('aria-label', t ? `렌즈 ${t.name} 켜짐 — 렌즈 차림표` : '렌즈 차림표');
    btn.setAttribute('aria-expanded', String(!menu.hidden));
  }

  /** 켠 렌즈의 갈래 견본: 제도 칸의 갈래(같은 색 = 나라 너머 같은 갈래) — 붕당을 단체로 그릴 때는 단체 색 · 지위로 대신한 체제는 없음 */
  function swatches(t) {
    const m = model();
    if (!m || !t) return null;
    const seen = new Map();
    for (const o of (m.institutionIndex && m.institutionIndex.byTheme.get(t.id)) || []) if (o.family && !seen.has(o.familyKey)) seen.set(o.familyKey, { name: o.family, color: o.color, start: o.start });
    if (seen.size) return { title: `${t.name}의 갈래`, tip: '같은 색은 나라 너머 같은 갈래', list: [...seen.values()].sort((a, b) => a.start - b.start) };
    if (t.id !== 'faction') return null;
    const gs = (m.groups || []).filter(g => g.type !== 'coalition' && g.type !== 'regime' && (g.powerSpans || []).length && (g.withinList || []).some(w => w.polity));
    return gs.length ? { title: `${t.name}의 단체`, tip: '칸 색은 집권한 단체의 색 · 두 색은 연정', list: gs.map(g => ({ name: g.name, color: g.color })) } : null;
  }

  function render() {
    const list = themes();
    const t = current();
    const m = model();
    const item = (id, name, color, hint, on, key, empty) =>
      `<button type="button" class="ctx-item lens-item${on ? ' is-checked' : ''}" role="menuitemradio" aria-checked="${on}" data-lens="${esc(id)}" style="--tc:${esc(color)}"><i class="dot" aria-hidden="true"></i><span class="ctx-label">${esc(name)}${hint ? `<small>${esc(hint)}</small>` : ''}${empty ? '<small class="lens-none">자료 없음</small>' : ''}</span>${key ? `<span class="ctx-key">${esc(key)}</span>` : ''}</button>`;
    const sw = swatches(t);
    const MAX = 12;
    menu.innerHTML =
      '<div class="ctx-title" title="지도자 칸 자리에 주제의 제도 칸">렌즈</div>' +
      item('', '없음', NONE_C, '', !t, 'Esc', false) +
      '<div class="ctx-sep"></div>' +
      list.map(x => item(x.id, x.name, x.color, HT.themeHint(x), !!t && t.id === x.id, '', !HT.lensHasData(m, x.id))).join('') +
      (sw
        ? `<div class="ctx-sep"></div><div class="ctx-title" title="${esc(sw.tip)}">${esc(sw.title)}</div><div class="lens-fam">${sw.list
            .slice(0, MAX)
            .map(f => `<span style="--fc:${esc(f.color)}">${esc(f.name)}</span>`)
            .join('')}${sw.list.length > MAX ? `<span class="is-more">외 ${sw.list.length - MAX}</span>` : ''}</div>`
        : '') +
      '<div class="ctx-sep"></div><button type="button" class="ctx-item" role="menuitem" data-lens-step="1"><span class="ctx-label">앞뒤로 넘기기</span><span class="ctx-key">S · Shift+S</span></button>';
  }

  function place() {
    const r = btn.getBoundingClientRect();
    menu.style.left = '0px';
    menu.style.top = '0px';
    const m = menu.getBoundingClientRect();
    menu.style.left = `${Math.round(Math.max(4, Math.min(r.left, innerWidth - m.width - 4)))}px`;
    menu.style.top = `${Math.round(Math.max(4, Math.min(r.bottom + 8, innerHeight - m.height - 4)))}px`;
  }

  function open() {
    const ctx = document.getElementById('ctxMenu');
    if (ctx) ctx.hidden = true; // ⋯ 차림표에서 왔으면 그것은 닫음 (차림표는 한 번에 하나)
    render();
    menu.hidden = false;
    place();
    paint();
    const first = menu.querySelector('.lens-item.is-checked') || menu.querySelector('.ctx-item');
    if (first) first.focus({ preventScroll: true });
  }
  function close(back = false) {
    if (menu.hidden) return;
    menu.hidden = true;
    paint();
    if (back) btn.focus({ preventScroll: true });
  }

  /** 앞뒤로 넘기기: 없음 → 주제들 → 없음 … (자료가 있는 주제가 하나라도 있으면 자료 없는 주제는 건너뜀) */
  function step(dir) {
    const m = model();
    const all = themes();
    const withData = all.filter(x => HT.lensHasData(m, x.id));
    const ring = [''].concat((withData.length ? withData : all).map(x => x.id));
    const now = tl.themeLens ? tl.themeLens.id : '';
    const i = Math.max(0, ring.indexOf(now));
    setLens(ring[(i + (dir < 0 ? ring.length - 1 : 1)) % ring.length]);
  }

  btn.addEventListener('click', () => {
    if (!menu.hidden) return close();
    open();
  });
  menu.addEventListener('click', e => {
    const b = e.target.closest('[data-lens], [data-lens-step]');
    if (!b) return;
    if (b.hasAttribute('data-lens-step')) return step(1);
    setLens(b.dataset.lens);
    close(true);
  });
  /* 차림표 안의 ↑ ↓ (지금 ⋯ 차림표처럼 단추 사이를 옮김) */
  menu.addEventListener('keydown', e => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    const items = [...menu.querySelectorAll('.ctx-item')];
    if (!items.length) return;
    e.preventDefault();
    const i = items.indexOf(document.activeElement);
    items[(i + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length].focus();
  });
  document.addEventListener('pointerdown', e => {
    if (!menu.hidden && !e.target.closest('#themeLensMenu, #themeLensBtn')) close();
  });
  window.addEventListener('blur', () => close());
  window.addEventListener('resize', () => !menu.hidden && place());

  /* 단축키 S · Shift+S — 뷰어의 단축키와 같은 조건(대화상자 · 글 칸 · 조합키에서는 쉼). S는 뷰어 단축키 표에 비어 있음 */
  document.addEventListener('keydown', e => {
    if (e.key !== 's' && e.key !== 'S') return;
    if (e.defaultPrevented || e.ctrlKey || e.metaKey || e.altKey) return;
    if (document.querySelector('dialog[open]')) return;
    const a = document.activeElement;
    if (a && (/INPUT|TEXTAREA|SELECT/.test(a.tagName) || a.isContentEditable)) return;
    if (a && a.closest && a.closest('#editPane, .mk-win, .fp-win, #mkProps, #mkStart')) return;
    e.preventDefault();
    step(e.shiftKey ? -1 : 1);
  });
  /* Esc의 차례(설계 결정 6): 렌즈 차림표 → (⋯ 차림표 · 노선도 · 묶음 카드 · 상세 창은 제 듣개가) → 렌즈 끔 → 집중 모드 끔.
     잡는 단계(capture)에서 먼저 들어, 렌즈를 끈 Esc가 집중 모드까지 끄지 않게 거기서 멈춥니다 */
  document.addEventListener(
    'keydown',
    e => {
      if (e.key !== 'Escape' || e.defaultPrevented) return;
      if (!menu.hidden) {
        e.preventDefault();
        e.stopImmediatePropagation();
        return close(true);
      }
      if (!tl.themeLens) return;
      if (document.querySelector('dialog[open]')) return;
      const a = document.activeElement;
      if (a && (/INPUT|TEXTAREA|SELECT/.test(a.tagName) || a.isContentEditable)) return;
      const ctx = document.getElementById('ctxMenu');
      if (ctx && !ctx.hidden) return;
      if (document.querySelector('.tl-metro:not([hidden]), .tl-card:not([hidden])')) return;
      if (state.selected) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      setLens('');
    },
    true
  );

  /* ⋯ 차림표 · 오른쪽 클릭 차림표에 '렌즈' 한 줄 — 차림표가 뜰 때마다 '필터' 줄(data-menu-id="filter") 다음에 끼움(뷰어의 차림표 목록은 고치지 않음).
     줄의 꼴은 뷰어의 차림표와 같음: 기호 칸(눈 · 켠 동안 체크) + 이름 + 단축키 */
  const ctxMenu = document.getElementById('ctxMenu');
  if (ctxMenu)
    new MutationObserver(() => {
      if (ctxMenu.hidden || ctxMenu.querySelector('[data-lens-open]')) return;
      const anchor = ctxMenu.querySelector('.ctx-item[data-menu-id="filter"]');
      if (!anchor) return;
      const t = current();
      const b = document.createElement('button');
      b.type = 'button';
      b.className = `ctx-item has-ic${t ? ' is-checked' : ''}`;
      b.setAttribute('role', 'menuitem');
      b.dataset.lensOpen = '';
      if (t) b.title = `렌즈 · ${t.name}`;
      b.innerHTML = `${HT.icon ? HT.icon(t ? 'check' : 'eye', 'ctx-ic') : ''}<span class="ctx-label">렌즈</span><span class="ctx-key">S</span>`;
      b.addEventListener('click', () => {
        ctxMenu.hidden = true;
        open();
      });
      anchor.after(b);
    }).observe(ctxMenu, { attributes: true, attributeFilter: ['hidden'], childList: true });

  tl.root.addEventListener('tl-data', sync);
  sync();
  HT.lensUI = { setLens, step, open, close, sync }; // 검사(scripts/lens-check.mjs)와 다른 부품이 쓸 수 있게
})();

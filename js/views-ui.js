/* 역사 연표 — 집합 보기 화면 (10건 6 — 설계 docs/설계-10건/6-모아-보기와-배치.md · 감독 선택 docs/설계-10건/감독-선택.md D4 결정 3 · 4 · 5)
   연표(index.html — 보기 전용)와 DLC 메이커(dlc-maker.html)가 함께 씁니다. js/viewer.js가 메이커 부품 다음에 HT.viewsUi.mount(ctx)로 붙입니다.
   · 독의 집합 보기 단추(겹친 판 기호만 — 건의 8 감독 선택 '1. A': 켠 동안 반전 채움, 판 이름은 풍선과 목록에) → 독 아래 목록(결정 4 B): 판마다 스위치 · 이름 · 나라 수 · 트랙 수 · DLC 표시. 연표는 DLC가 준 판을 켜고 끄기만 하고(판을 만들지 않음),
     메이커는 고치는 DLC(작업본)의 판에 고치기 · 지우기. 판이 하나도 없는 연표에서는 단추가 숨습니다(켜 둔 임시 판이 있으면 보임 — 끌 수 있게).
   · 시대 구분 상세의 '이 시대의 나라' 카드(결정 5 A): 같은 트랙 · 같은 기간에 있던 나라 칩(눌러 빼기 · 다시 넣기) · 같은 기간의 다른 트랙 나라 ·
     스위치 = 저장하지 않은 임시 판(끄면 사라짐 — 연표에서 판을 만들지 않는다는 결정 3과 맞음). 메이커는 '집합 보기로 저장'도.
   · 메이커의 '고른 나라' 막대(결정 3 '메이커에서만'): Ctrl+클릭으로 고른 나라 → 화면 아래 가운데 막대 → '집합 보기로 저장'(그 DLC의 views — 형식 3) ·
     '저장 없이 집합 보기' · ✕(고르기 풀기). 이름 칸은 비어 있거나 적은 값만(회색 예시 글 없음).
   판을 켜고 끄는 일 · 그리기는 연표(js/timeline.js setBoard)가 맡습니다. 켠 DLC 판은 보기 설정(ht.ui의 board — 이 브라우저에만)에 기억하고, 임시 판은 기억하지 않습니다.
   움직임은 토큰만(목록 · 막대가 떠오름 --t-in · 물러남 --t-out — css/viewer.css '집합 보기') */
(function () {
  'use strict';
  const HT = window.HT;
  const esc = HT.escapeHtml;
  const BUTTER = '#d7c18e'; // 판의 기본 색 (파스텔 열두 가지의 버터 — 설계 결정 2)
  const CHIP_MAX = 5; // 막대의 칩은 다섯까지, 넘으면 '+n'
  const icon = name => (HT.icon ? HT.icon(name) : ''); // 선 아이콘 한 벌 (js/viewer.js — 건의 8)

  HT.viewsUi = {
    mount(ctx) {
      const { state, K, timeline, maker } = ctx;
      const MAKE = !!maker;
      const save = () => HT.store.set(K.ui, state.ui);
      const model = () => state.model || { views: [], byUid: new Map(), tracks: [], periods: [] };
      const isPolity = x => !!x && HT.itemKindOf(x) === 'period';
      const pastel = c => HT.pastel(HT.isColor(c) ? c : BUTTER);
      const trackName = id => (model().trackMap && model().trackMap.get(id) ? model().trackMap.get(id).name : id);

      /* ---------- 판 ↔ 연표의 판 ---------- */
      /** 모델의 판(views) → 연표가 받는 판 { id(uid), name, color, members(uid), start?, end?, packName } */
      const boardOf = v => ({ id: v.uid, name: v.name, color: v.color, members: v.members.map(p => p.uid), start: v.start != null ? v.start : undefined, end: v.start != null ? v.endY : undefined, packName: v.packName });
      const viewByUid = uid => (model().views || []).find(v => v.uid === uid) || null;
      const same = (a, b) => !!a && !!b && a.id === b.id && a.name === b.name && a.color === b.color && a.start === b.start && a.end === b.end && a.members.join('|') === b.members.join('|');
      const current = () => timeline.boardOn();
      /** 판 켜기 (fly: 판의 기간으로 날아감 — 처음 화면에서 되살릴 때는 보던 범위 그대로) */
      function turnOn(board, { remember = true, fly = true } = {}) {
        if (remember) {
          state.ui.board = board.temp ? null : board.id;
          save();
        }
        timeline.setBoard(board, { fly });
      }
      function turnOff() {
        state.ui.board = null;
        save();
        timeline.setBoard(null);
      }

      /* ---------- 독 단추 · 목록 (결정 4 B) ---------- */
      let btn = document.getElementById('viewsBtn');
      if (!btn && MAKE) {
        /* 메이커에는 독이 없어 가운데 탭 줄(연표 · 표 · 문서)의 보는 범위 앞에 끼웁니다 */
        const bar = document.getElementById('mkCTabs');
        if (bar) {
          bar.insertAdjacentHTML('beforeend', `<button id="viewsBtn" class="dock-btn views-btn" type="button" aria-expanded="false" aria-controls="viewsPop" aria-label="집합 보기" title="집합 보기">${icon('layers')}</button>`);
          btn = document.getElementById('viewsBtn');
          const range = document.getElementById('viewRange');
          if (range && range.parentNode === bar) bar.insertBefore(btn, range);
        }
      }
      const pop = document.createElement('div');
      pop.id = 'viewsPop';
      pop.className = 'views-pop';
      pop.setAttribute('role', 'dialog');
      pop.setAttribute('aria-label', '집합 보기');
      pop.hidden = true;
      (document.querySelector('.app') || document.body).appendChild(pop);
      let editing = null; // 메이커의 고치기: { id, name, members: [uid], start, end }

      const countText = v => {
        const n = v.members.length;
        const tracks = new Set(v.members.map(p => p.track)).size;
        const miss = HT.readScopeRefs(v.memberRefs).length - n;
        return `나라 ${n} · 트랙 ${tracks}${miss > 0 ? ` · 찾지 못한 나라 ${miss}` : ''}`;
      };
      const ownView = v => MAKE && maker.isDraftId && maker.isDraftId(v.packId);
      function rowHTML(v) {
        const b = current();
        const on = !!b && b.id === v.uid;
        const own = ownView(v);
        const acts = own ? `<span class="vw-acts"><button type="button" class="linky" data-vw-edit="${esc(v.id)}">고치기</button><button type="button" class="linky is-danger" data-vw-del="${esc(v.id)}">지우기</button></span>` : '';
        return `<div class="vw-row${on ? ' is-on' : ''}" style="--c:${v.color}">
          <button type="button" class="scope-switch vw-switch${on ? ' is-on' : ''}" data-vw-toggle="${esc(v.uid)}" aria-pressed="${on}" aria-label="${esc(`집합 보기 ${v.name}`)}" style="--c:${v.color}" title="${esc(`${v.name} — ${on ? '끄기' : '켜기'}`)}"><i></i></button>
          <div class="vw-text"><b>${esc(v.name)}</b>${own ? '' : `<span class="vw-dlc" title="${esc(`DLC «${v.packName}»가 준 집합 보기`)}">${esc(v.packName)}</span>`}<small>${esc(countText(v))}</small></div>${acts}
        </div>`;
      }
      function tempHTML(b) {
        const tracks = new Set(b.members.map(uid => (model().byUid.get(uid) || {}).track).filter(Boolean)).size;
        return `<div class="vw-row is-on is-temp" style="--c:${b.color}">
          <button type="button" class="scope-switch vw-switch is-on" data-vw-off aria-pressed="true" aria-label="${esc(`집합 보기 ${b.name}`)}" style="--c:${b.color}" title="${esc(`${b.name} — 끄기 (저장하지 않은 판이라 사라짐)`)}"><i></i></button>
          <div class="vw-text"><b>${esc(b.name)}</b><span class="vw-dlc is-temp">저장하지 않은 판</span><small>나라 ${b.members.length} · 트랙 ${tracks}</small></div>
          ${MAKE ? '<span class="vw-acts"><button type="button" class="linky" data-vw-keep>집합 보기로 저장</button></span>' : ''}
        </div>`;
      }
      function editHTML() {
        const e = editing;
        const m = model();
        const items = e.members
          .map((uid, i) => {
            const p = m.byUid.get(uid);
            return `<li style="--c:${p ? p.color : '#a4b1b7'}"><span class="vw-dot"></span><b>${esc(p ? p.name : uid)}</b><small>${esc(p ? trackName(p.track) : '')}</small>
              <button type="button" class="icon-btn" data-vw-move="${i}:-1" aria-label="위로" ${i ? '' : 'disabled'}>↑</button><button type="button" class="icon-btn" data-vw-move="${i}:1" aria-label="아래로" ${i < e.members.length - 1 ? '' : 'disabled'}>↓</button><button type="button" class="icon-btn" data-vw-drop="${i}" aria-label="빼기">✕</button></li>`;
          })
          .join('');
        const picked = pickedToAdd();
        return `<form class="vw-edit" data-vw-form>
          <label><span>이름</span><input name="name" type="text" autocomplete="off" value="${esc(e.name)}"></label>
          <div class="vw-span"><label><span>기간 시작</span><input name="start" type="text" autocomplete="off" value="${esc(e.start)}"></label><label><span>끝</span><input name="end" type="text" autocomplete="off" value="${esc(e.end)}"></label></div>
          <p class="vw-note">기간을 적으면 켤 때 그 시기로 갑니다. 비우면 보던 시기 그대로 모으기만 합니다.</p>
          ${extraHTML(e, m)}
          <ol class="vw-members">${items}</ol>
          <button type="button" class="btn btn-sm" data-vw-addsel ${picked ? '' : 'disabled'} title="연표에서 Ctrl+클릭으로 고른 나라를 이 판 끝에 더합니다">${addSelText(picked)}</button>
          <div class="vw-edit-foot"><button type="submit" class="btn btn-sm btn-primary">저장</button><button type="button" class="btn btn-sm" data-vw-cancel>취소</button></div>
        </form>`;
      }
      /* 판의 나머지 칸(2026-10-23 — "메이커로 못 바꾸는 곳이 없도록" ④): 색 · 설명 · 메모 · 권하는 보기 설정(밀도 · 렌즈 · 표시 체크) · 이름 목록 · 문서.
         표시 체크는 열쇠마다 '그대로(적지 않음) · 켬 · 끔' 셋 — 적은 것만 settings.show에 듭니다(DLC-형식.md 'views') */
      const SHOW_WORDS = { dynasties: '왕조', leaders: '지도자', cabinets: '내각', eras: '연호', capitals: '도읍', ganji: '간지', epochs: '시대 구분', succession: '승계선', partOf: '소속선', spotEcho: '같은 시기를 타국에도', figures: '인물', phases: '시기 구분', ranks: '지위', houses: '가문', groups: '단체' };
      const showKeys = () => [...new Set(Object.keys(HT.SHOW_DEFAULTS).concat(Object.keys(SHOW_WORDS)))];
      function extraHTML(e, m) {
        const themes = (m.themes || []).filter(t => t && t.id && !t.hidden);
        const show = e.show || {};
        return `<div class="vw-extra">
          <div class="vw-span"><label><span>색</span><span class="vw-color-row"><button type="button" class="sw mk-sw" data-vw-color style="--c:${esc(e.color ? HT.pastel(e.color) : HT.autoColor(`view:${e.id || e.name}`))}" title="판 이름표 색 — 비우면 자동" aria-label="색 고르기"></button><small>${e.color ? esc(e.color) : '자동'}</small></span></label>
            <label><span>메모</span><input name="note" type="text" autocomplete="off" value="${esc(e.note || '')}"></label></div>
          <label><span>설명</span><textarea name="description" rows="2">${esc(e.description || '')}</textarea></label>
          <fieldset class="vw-settings"><legend>권하는 보기 설정 <small>(보는 사람이 바꾼 것이 늘 이김)</small></legend>
            <div class="vw-span"><label><span>밀도</span><select name="density"><option value="">그대로</option>${HT.VIEW_DENSITIES.map(d => `<option value="${d.id}"${String(e.density) === String(d.id) ? ' selected' : ''}>${esc(d.name)}</option>`).join('')}</select></label>
              <label><span>렌즈</span><select name="lens"><option value="">없음</option>${themes.map(t => `<option value="${esc(t.id)}"${e.lens === t.id ? ' selected' : ''}>${esc(t.name)}</option>`).join('')}${e.lens && !themes.some(t => t.id === e.lens) ? `<option value="${esc(e.lens)}" selected>${esc(e.lens)} (사전에 없음)</option>` : ''}</select></label></div>
            <div class="vw-show">${showKeys()
              .map(k => `<label><span>${esc(SHOW_WORDS[k] || k)}</span><select name="show:${esc(k)}"><option value="">그대로</option><option value="1"${show[k] === true ? ' selected' : ''}>켬</option><option value="0"${show[k] === false ? ' selected' : ''}>끔</option></select></label>`)
              .join('')}</div>
          </fieldset>
          <details class="vw-names"${(e.names || []).length ? ' open' : ''}><summary>이름(원어 등) ${(e.names || []).length || ''}</summary>
            <div class="alt-rows" data-vw-names>${HT.namesRowsHTML(e.names || [])}</div>
            <div class="toolbar"><button type="button" class="btn btn-sm" data-vw-name-add>＋ 이름 추가</button></div></details>
          ${e.id ? `<div class="toolbar"><button type="button" class="btn btn-sm" data-vw-doc="${esc(e.id)}">문서</button></div>` : ''}
        </div>`;
      }
      /** 고치는 판에 더할 수 있는 고른 나라 수 (이미 든 나라 빼고) */
      const pickedToAdd = () => (editing ? (maker.selection() || []).filter(uid => isPolity(model().byUid.get(uid)) && !editing.members.includes(uid)).length : 0);
      const addSelText = n => `＋ 고른 나라 더하기${n ? ` ${n}` : ''}`;
      function renderPop() {
        if (pop.hidden) return;
        if (editing) readForm(); // 다시 그려도 적던 글은 그대로
        const views = model().views || [];
        const b = current();
        const temp = b && b.temp ? tempHTML(b) : '';
        const empty = !views.length && !temp ? `<p class="vw-empty">${MAKE ? '아직 집합 보기가 없습니다. 연표에서 Ctrl+클릭으로 나라를 고르면 아래 가운데 막대에서 \'집합 보기로 저장\'을 누를 수 있습니다.' : '켠 DLC가 준 집합 보기가 없습니다.'}</p>` : '';
        pop.innerHTML = `<div class="vw-head" title="한 번에 하나 — 켜면 그 나라들의 줄이 맨 위로 모이고 나머지 트랙은 접힙니다"><b>집합 보기</b>${views.length ? `<small>${views.length}</small>` : ''}</div>
          ${editing ? editHTML() : `<div class="vw-rows">${temp}${views.map(rowHTML).join('')}</div>${empty}`}`;
      }
      function placePop() {
        if (!btn || pop.hidden) return;
        const r = btn.getBoundingClientRect();
        const bottom = Math.max(r.bottom, btn.closest('.dock')?.getBoundingClientRect().bottom || 0);
        const w = Math.min(440, innerWidth - 24);
        pop.style.width = `${w}px`;
        pop.style.left = `${Math.round(HT.clamp(r.left - 12, 12, innerWidth - w - 12))}px`;
        pop.style.top = `${Math.round(bottom + 10)}px`;
        pop.style.maxHeight = `${Math.max(160, innerHeight - bottom - 26)}px`;
      }
      function openList() {
        if (!btn) return;
        if (!pop.hidden) return placePop();
        pop.hidden = false;
        btn.setAttribute('aria-expanded', 'true');
        renderPop();
        placePop();
      }
      function closeList() {
        if (pop.hidden) return;
        pop.hidden = true;
        editing = null;
        if (btn) btn.setAttribute('aria-expanded', 'false');
      }
      function syncBtn() {
        if (!btn) return;
        const b = current();
        const views = model().views || [];
        btn.hidden = !MAKE && !views.length && !b;
        btn.classList.toggle('is-on', !!b);
        if (!btn.querySelector('svg.ic')) btn.innerHTML = icon('layers'); // 기호만 — 판 이름은 풍선과 목록에 (건의 8)
        btn.title = b ? `집합 보기 · ${b.name}` : '집합 보기';
        btn.setAttribute('aria-label', b ? `집합 보기 «${b.name}» 켜짐 — 눌러 목록 (끄기 · 다른 판)` : '집합 보기 — 멀리 떨어진 나라들을 한 판에 모아 견주기');
        if (btn.hidden) closeList();
      }
      if (btn)
        btn.addEventListener('click', () => {
          if (pop.hidden) openList();
          else closeList();
        });
      addEventListener('resize', placePop);
      document.addEventListener('pointerdown', e => {
        if (!pop.hidden && !pop.contains(e.target) && !(btn && btn.contains(e.target)) && !e.target.closest('[data-board-name]')) closeList();
      });
      /* Esc: 목록만 닫음 — 붙잡는 단계(capture)에서 먼저 받아 연표의 Esc(상세 창 닫기 · 고르기 풀기)로 번지지 않게 */
      document.addEventListener(
        'keydown',
        e => {
          if (e.key !== 'Escape' || pop.hidden) return;
          e.preventDefault();
          e.stopPropagation();
          closeList();
          if (btn) btn.focus({ preventScroll: true });
        },
        true
      );
      pop.addEventListener('click', async e => {
        const t = e.target;
        const tog = t.closest('[data-vw-toggle]');
        if (tog) {
          const b = current();
          const v = viewByUid(tog.dataset.vwToggle);
          if (b && b.id === tog.dataset.vwToggle) turnOff();
          else if (v && v.members.length) turnOn(boardOf(v));
          else if (v) HT.toast(`«${v.name}»의 구성 나라를 연표에서 찾지 못했습니다.`);
          return;
        }
        if (t.closest('[data-vw-off]')) return turnOff();
        if (!MAKE) return;
        if (t.closest('[data-vw-keep]')) {
          const b = current();
          if (b && b.temp) await saveNew(b.name, b.members, b);
          return;
        }
        const ed = t.closest('[data-vw-edit]');
        if (ed) return startEdit(ed.dataset.vwEdit);
        const del = t.closest('[data-vw-del]');
        if (del) return removeView(del.dataset.vwDel);
        if (!editing) return;
        const mv = t.closest('[data-vw-move]');
        if (mv) {
          const [i, d] = mv.dataset.vwMove.split(':').map(Number);
          const j = i + d;
          if (j < 0 || j >= editing.members.length) return;
          readForm();
          [editing.members[i], editing.members[j]] = [editing.members[j], editing.members[i]];
          return renderPop();
        }
        const drop = t.closest('[data-vw-drop]');
        if (drop) {
          readForm();
          editing.members.splice(Number(drop.dataset.vwDrop), 1);
          return renderPop();
        }
        if (t.closest('[data-vw-color]')) {
          /* 판 이름표 색 — 바탕 자료 표의 색 단추와 같은 고르기 상자. 비우면 자동 */
          const btn = t.closest('[data-vw-color]');
          const v = await HT.pickColor(btn, editing.color ? HT.pastel(editing.color) : '');
          if (v == null) return;
          readForm();
          editing.color = v || '';
          return renderPop();
        }
        if (t.closest('[data-vw-name-add]')) {
          readForm();
          const host = pop.querySelector('[data-vw-names]');
          if (host) host.insertAdjacentHTML('beforeend', HT.nameRowHTML());
          const last = host && host.lastElementChild && host.lastElementChild.querySelector('input');
          if (last) last.focus();
          return;
        }
        if (t.closest('[data-name-del]')) {
          readForm();
          t.closest('.name-row').remove();
          return;
        }
        const doc = t.closest('[data-vw-doc]');
        if (doc) {
          readForm();
          if (maker.openWiki) maker.openWiki(`view:${doc.dataset.vwDoc}`);
          return;
        }
        if (t.closest('[data-vw-addsel]')) {
          readForm();
          for (const uid of maker.selection() || []) if (isPolity(model().byUid.get(uid)) && !editing.members.includes(uid)) editing.members.push(uid);
          return renderPop();
        }
        if (t.closest('[data-vw-cancel]')) {
          editing = null;
          return renderPop();
        }
      });
      pop.addEventListener('submit', async e => {
        e.preventDefault();
        if (!editing) return;
        readForm();
        const span = readSpan(editing);
        if (!span) return;
        if (!editing.name.trim()) return HT.toast('집합 보기의 이름을 적어 주세요.');
        if (!editing.members.length) return HT.toast('구성 나라가 하나도 없습니다.');
        if (editing.nameProblems && editing.nameProblems.length) return HT.toast(`이름 목록: ${editing.nameProblems.join(' · ')}`);
        /* 나머지 칸: 보기 설정은 적은 것만(밀도 · 렌즈 · 표시 체크의 켬 · 끔) — 모두 비우면 settings가 빠짐 */
        const settings = {};
        if (editing.density !== '' && editing.density != null) settings.density = Number(editing.density);
        if (editing.lens) settings.lens = editing.lens;
        const show = Object.fromEntries(Object.entries(editing.show || {}).filter(([, v]) => v === true || v === false));
        if (Object.keys(show).length) settings.show = show;
        const extra = { color: editing.color || '', description: (editing.description || '').trim(), note: (editing.note || '').trim(), settings, names: editing.names || [] };
        const id = await maker.saveView(Object.assign({ name: editing.name.trim(), members: editing.members.slice() }, span, extra), editing.id);
        if (!id) return;
        HT.toast(`집합 보기 «${editing.name.trim()}»을(를) 고쳤습니다.`, 'ok');
        editing = null;
        renderPop();
      });
      function readForm() {
        const f = pop.querySelector('[data-vw-form]');
        if (!f || !editing) return;
        editing.name = f.elements.name.value;
        editing.start = f.elements.start.value;
        editing.end = f.elements.end.value;
        const el = f.elements;
        if (el.note) editing.note = el.note.value;
        if (el.description) editing.description = el.description.value;
        if (el.density) editing.density = el.density.value;
        if (el.lens) editing.lens = el.lens.value;
        editing.show = {};
        for (const k of showKeys()) {
          const s = el[`show:${k}`];
          if (s && s.value) editing.show[k] = s.value === '1';
        }
        const host = f.querySelector('[data-vw-names]');
        if (host) {
          const problems = [];
          editing.names = HT.readNameRows(host, problems);
          editing.nameProblems = problems;
        }
      }
      /** 기간 칸 두 개 → { start?, end?, startAt?, endAt? } (비우면 기간 없음). 읽지 못하면 알리고 null */
      function readSpan(e) {
        const s = String(e.start || '').trim();
        const t = String(e.end || '').trim();
        if (!s && !t) return {};
        if (!s) {
          HT.toast('끝만 적을 수는 없습니다 — 시작을 함께 적어 주세요.');
          return null;
        }
        const a = HT.readDate(s);
        const b = t ? HT.readDate(t) : null;
        if (!a || isNaN(a.t) || (t && (!b || isNaN(b.t)))) {
          HT.toast('기간을 읽지 못했습니다 — 해(예: 600, 기원전 57)나 날짜로 적어 주세요.');
          return null;
        }
        if (b && b.t < a.t) {
          HT.toast('끝이 시작보다 앞섭니다.');
          return null;
        }
        const o = { start: a.t };
        if (a.at) o.startAt = a.at;
        if (b) {
          o.end = b.t;
          if (b.at) o.endAt = b.at;
        }
        return o;
      }
      const yearText = (t, at) => (t == null ? '' : at || String(t));
      function startEdit(id) {
        const v = (model().views || []).find(x => x.id === id && ownView(x));
        if (!v) return;
        const raw = (maker.viewRaw && maker.viewRaw(id)) || {}; // 작업본의 판 그대로(설명 · 메모 · 보기 설정 · 이름 목록 · 색)
        const st = raw.settings && typeof raw.settings === 'object' ? raw.settings : {};
        editing = {
          id, name: v.name, members: v.members.map(p => p.uid), start: yearText(v.start, v.startAt), end: v.start != null && v.end != null ? yearText(v.end, v.endAt) : '',
          color: HT.isColor(raw.color) ? raw.color : '', description: raw.description || '', note: raw.note || '',
          density: st.density == null || st.density === '' ? '' : String((HT.VIEW_DENSITIES.find(d => d.id === st.density || d.name === st.density) || {}).id ?? ''), lens: typeof st.lens === 'string' ? st.lens : '',
          show: st.show && typeof st.show === 'object' ? Object.fromEntries(Object.entries(st.show).filter(([, x]) => x === true || x === false)) : {},
          names: Array.isArray(raw.names) ? raw.names.map(n => (typeof n === 'string' ? { text: n } : n)) : [],
        };
        renderPop();
        const f = pop.querySelector('[data-vw-form] input[name="name"]');
        if (f) f.focus();
      }
      async function removeView(id) {
        const v = (model().views || []).find(x => x.id === id && ownView(x));
        if (!v) return;
        if ((await maker.ask(`집합 보기 «${v.name}»을(를) 이 DLC에서 지웁니다. 나라 · 사건은 그대로입니다.`, { title: '집합 보기 지우기', yes: '지우기', no: '', danger: true })) !== 'yes') return;
        if (await maker.removeView(id)) HT.toast(`집합 보기 «${v.name}»을(를) 지웠습니다.`, 'ok');
      }
      /** 메이커: 새 판으로 저장(고른 나라 막대 · 임시 판 · 시대 구분 카드) — 저장하면 그 판을 켭니다 */
      async function saveNew(name, members, span = {}) {
        if (!MAKE) return null;
        const nm = String(name || '').trim();
        if (!nm) {
          HT.toast('집합 보기의 이름을 적어 주세요.');
          return null;
        }
        const list = members.filter(uid => isPolity(model().byUid.get(uid)));
        if (!list.length) {
          HT.toast('고른 나라가 없습니다 — 연표에서 Ctrl+클릭으로 나라를 고르세요.');
          return null;
        }
        const o = { name: nm, members: list };
        if (span.start != null && isFinite(span.start)) {
          o.start = span.start;
          if (span.startAt) o.startAt = span.startAt;
          if (span.ongoing) o.ongoing = true;
          else if (span.end != null && isFinite(span.end)) {
            o.end = span.end;
            if (span.endAt) o.endAt = span.endAt;
          }
        }
        const id = await maker.saveView(o);
        if (!id) return null;
        const v = (model().views || []).find(x => x.id === id && ownView(x));
        if (v && v.members.length) turnOn(boardOf(v), { fly: false });
        HT.toast(`집합 보기 «${nm}»을(를) 이 DLC에 저장했습니다 — 집합 보기 목록에서 켜고 끕니다.`, 'ok');
        return id;
      }

      /* ---------- 시대 구분 상세의 '이 시대의 나라' 카드 (결정 5 A) ---------- */
      const cards = new Map(); // 시대 구분 uid → { off: Set(뺀 나라 uid), wide: 다른 트랙 나라도 }
      const cardOf = uid => cards.get(uid) || (cards.set(uid, { off: new Set(), wide: false }), cards.get(uid));
      const tempId = x => `epoch:${x.uid}`;
      /** 연표 위에서 아래로의 차례(트랙 → 줄 — timeline.echoBands의 order). 판을 켠 동안은 판이 맨 위로 바뀌므로 판이 없을 때 잰 것을 씀 (칩이 켜고 끌 때마다 뒤섞이지 않게) */
      let orderMemo = null;
      const rowOrder = () => {
        if (!current() || !orderMemo) orderMemo = timeline.echoBands();
        return orderMemo;
      };
      /** 그 시대 구분에 있던 나라: 같은 트랙(공통 시대 구분이면 모든 트랙 · wide면 모든 트랙) · 기간이 겹침 · 나라(기관 · 문화 · 왕조 빼고) · 지금 거르기에 보이는 것.
          이어진 대범위가 있으면 그 구성 나라는 빼고(그 밖의 나라). 차례 = 연표의 줄 차례(트랙 → 줄 → 시작 해) */
      function candidates(x, wide) {
        const m = model();
        const s = x.start;
        const e = x.endY != null ? x.endY : x.start;
        const inScopes = new Set((x.scopes || []).flatMap(sc => (sc.members || []).map(p => p.uid)));
        const tOrder = new Map((m.tracks || []).map((t, i) => [t.id, i]));
        const ord = rowOrder();
        const at = p => (ord.has(p.uid) ? ord.get(p.uid).order : (tOrder.get(p.track) ?? 1e6) + 0.999);
        return (state.visible || [])
          .filter(p => isPolity(p) && (wide || !x.track || p.track === x.track) && p.start < e && (p.endY != null ? p.endY : p.start) > s && !inScopes.has(p.uid))
          .sort((a, b) => at(a) - at(b) || a.start - b.start);
      }
      function epochBoard(x) {
        const c = cardOf(x.uid);
        const members = candidates(x, c.wide)
          .filter(p => !c.off.has(p.uid))
          .map(p => p.uid);
        return { id: tempId(x), name: x.name, color: pastel(x.color), members, start: x.start, end: x.endY != null ? x.endY : x.start, temp: true, epoch: x.uid };
      }
      function epochCardHTML(x) {
        if (!x || x.kind !== 'epoch') return '';
        const c = cardOf(x.uid);
        const list = candidates(x, c.wide);
        if (!list.length) return '';
        const b = current();
        const on = !!b && b.id === tempId(x);
        const n = list.filter(p => !c.off.has(p.uid)).length;
        const scoped = (x.scopes || []).length > 0;
        const chips = list
          .map(p => {
            const off = c.off.has(p.uid);
            return `<button type="button" class="chip vw-chip${off ? ' is-off' : ''}" data-vw-pick="${esc(p.uid)}" aria-pressed="${!off}" style="--c:${p.color}" title="${esc(`${p.name} (${trackName(p.track)}) — ${off ? '눌러 다시 넣기' : '눌러 빼기'}`)}">${esc(p.name)}</button>`;
          })
          .join('');
        const wideBtn = `<button type="button" class="chip vw-wide" data-vw-wide="${esc(x.uid)}" aria-pressed="${c.wide}">${c.wide ? '－ 다른 트랙 나라 빼기' : '＋ 같은 기간의 다른 트랙 나라'}</button>`;
        const sw = `<button type="button" class="scope-switch${on ? ' is-on' : ''}" data-vw-epoch="${esc(x.uid)}" aria-pressed="${on}" style="--c:${pastel(x.color)}" title="켜면 이 시대의 기간으로 가서 고른 나라들을 맨 위 한 판에 모읍니다"><i></i><span>집합 보기</span><small>${on ? '켬' : '끔'}</small></button>`;
        const keep = MAKE ? `<button type="button" class="btn btn-sm" data-vw-epoch-save="${esc(x.uid)}" ${n ? '' : 'disabled'}>${icon('layers')}집합 보기로 저장</button>` : '';
        return `<section class="sub-box is-views" data-vw-card="${esc(x.uid)}">
          <h3 title="${esc(`${c.wide ? '같은 기간' : x.track ? '같은 트랙 · 같은 기간' : '같은 기간'}에 있던 나라 — 눌러 빼기 · 다시 넣기`)}">${scoped ? '그 밖의 나라' : '이 시대의 나라'} <small>${list.length}</small></h3>
          <div class="vw-chips">${chips}${x.track || c.wide ? wideBtn : ''}</div>
          <div class="vw-card-acts">${sw}${keep}</div>
          <p class="vw-note">${on ? '저장하지 않은 판입니다 — 끄면 사라지고 켜기 전 모습으로 돌아갑니다.' : '켜면 이 시대의 기간으로 가서 나라들을 맨 위 한 판에 모읍니다. 끄면 제자리로.'}</p>
        </section>`;
      }
      function rerenderCard() {
        const el = document.querySelector('[data-vw-card]');
        if (!el) return;
        const x = model().byUid && model().byUid.get(el.dataset.vwCard);
        const html = x ? epochCardHTML(x) : '';
        if (html) el.outerHTML = html;
        else el.remove();
      }
      /** 상세 창의 누름 (viewer.js의 detailEl click 맨 앞) — 맡았으면 true */
      function onDetailClick(e) {
        const t = e.target;
        const pick = t.closest('[data-vw-pick]');
        const wide = t.closest('[data-vw-wide]');
        const sw = t.closest('[data-vw-epoch]');
        const keep = t.closest('[data-vw-epoch-save]');
        if (!pick && !wide && !sw && !keep) return false;
        const card = t.closest('[data-vw-card]');
        const x = card && model().byUid.get(card.dataset.vwCard);
        if (!x) return true;
        const c = cardOf(x.uid);
        const b = current();
        const on = !!b && b.id === tempId(x);
        if (pick) {
          const uid = pick.dataset.vwPick;
          if (c.off.has(uid)) c.off.delete(uid);
          else c.off.add(uid);
        } else if (wide) c.wide = !c.wide;
        else if (sw) {
          if (on) turnOff();
          else {
            const nb = epochBoard(x);
            if (!nb.members.length) HT.toast('모을 나라가 없습니다 — 칩을 눌러 다시 넣으세요.');
            else turnOn(nb);
          }
          rerenderCard();
          return true;
        } else if (keep) {
          const nb = epochBoard(x);
          saveNew(x.name, nb.members, { start: x.start, startAt: x.startAt, end: x.end != null ? x.end : undefined, endAt: x.endAt, ongoing: !!x.ongoing }).then(rerenderCard);
          return true;
        }
        if (on) {
          const nb = epochBoard(x);
          if (nb.members.length) timeline.setBoard(nb, { fly: false }); // 켠 채 칩을 바꾸면 그 자리에서 다시 모음 (기간으로 다시 날아가지 않음)
          else turnOff();
        }
        rerenderCard();
        return true;
      }

      /* ---------- 메이커: 고른 나라 막대 (결정 3) ---------- */
      let bar = null;
      let multi = false; // 연표에서 Ctrl+클릭으로 고르기 시작했는가 (나라 하나만 골라도 막대를 띄움 — 나무에서 하나를 고른 것과 구별)
      let barName = '';
      if (MAKE) {
        bar = document.createElement('div');
        bar.className = 'vw-bar';
        bar.setAttribute('role', 'region');
        bar.setAttribute('aria-label', '고른 나라');
        bar.hidden = true;
        (document.getElementById('stage') || document.body).appendChild(bar);
        bar.addEventListener('input', e => {
          if (e.target.name === 'vwName') barName = e.target.value;
        });
        bar.addEventListener('keydown', e => {
          if (e.key === 'Enter' && e.target.name === 'vwName') {
            e.preventDefault();
            bar.querySelector('[data-vw-bar="save"]').click();
          }
          e.stopPropagation(); // 이름을 적는 동안 연표 단축키(F · Z …)가 끼어들지 않게
        });
        bar.addEventListener('click', async e => {
          const t = e.target;
          const chip = t.closest('[data-vw-unpick]');
          if (chip) return maker.toggleSelection(chip.dataset.vwUnpick);
          const act = t.closest('[data-vw-bar]');
          if (!act) return;
          const list = pickedPolities();
          if (act.dataset.vwBar === 'clear') return maker.clearSelection();
          if (act.dataset.vwBar === 'temp') {
            if (!list.length) return;
            const name = barName.trim() || `고른 나라 ${list.length}곳`;
            return turnOn({ id: 'pick:' + list.join('|'), name, color: pastel(BUTTER), members: list, temp: true }, { fly: false });
          }
          if (act.dataset.vwBar === 'save') {
            if (!barName.trim()) {
              HT.toast('집합 보기의 이름을 적어 주세요.');
              const input = bar.querySelector('input');
              if (input) input.focus();
              return;
            }
            const id = await saveNew(barName, list);
            if (id) {
              barName = '';
              maker.clearSelection();
            }
          }
        });
      }
      const pickedPolities = () => (MAKE ? (maker.selection() || []).filter(uid => isPolity(model().byUid.get(uid))) : []);
      let barSig = '';
      function renderBar() {
        if (!bar) return;
        const list = pickedPolities();
        const show = list.length >= 2 || (list.length >= 1 && multi);
        if (!show) {
          if (!bar.hidden) bar.hidden = true;
          barSig = '';
          return;
        }
        /* 고른 것이 그대로면 다시 짓지 않음 — 누르는 사이(누름 → 뗌)에 단추가 바뀌면 누름이 사라지므로 (메이커는 그리기마다 고름을 다시 칠함) */
        const sig = list.join('|');
        if (!bar.hidden && sig === barSig) return;
        barSig = sig;
        const m = model();
        const chips = list
          .slice(0, CHIP_MAX)
          .map(uid => {
            const p = m.byUid.get(uid);
            return `<button type="button" class="chip vw-chip" data-vw-unpick="${esc(uid)}" style="--c:${p.color}" title="${esc(`${p.name} (${trackName(p.track)}) — 눌러 빼기`)}">${esc(p.name)}</button>`;
          })
          .join('');
        const more = list.length > CHIP_MAX ? `<span class="vw-more" title="${esc(list.slice(CHIP_MAX).map(uid => m.byUid.get(uid).name).join(' · '))}">+${list.length - CHIP_MAX}</span>` : '';
        const focused = bar.contains(document.activeElement) && document.activeElement.name === 'vwName';
        bar.hidden = false;
        if (focused) {
          /* 이름을 적는 중이면 입력 칸은 그대로 두고 나머지만 */
          bar.querySelector('.vw-bar-title b').textContent = `고른 나라 ${list.length}`;
          bar.querySelector('.vw-bar-chips').innerHTML = chips + more;
          return;
        }
        bar.innerHTML = `<div class="vw-bar-title"><b>고른 나라 ${list.length}</b><small>Ctrl+클릭으로 더하고 빼기</small></div>
          <div class="vw-bar-chips">${chips}${more}</div>
          <label class="vw-bar-name"><span>이름</span><input name="vwName" type="text" autocomplete="off" aria-label="집합 보기 이름" value="${esc(barName)}"></label>
          <button type="button" class="btn btn-sm btn-primary" data-vw-bar="save">${icon('layers')}집합 보기로 저장</button>
          <button type="button" class="btn btn-sm" data-vw-bar="temp">저장 없이 집합 보기</button>
          <button type="button" class="icon-btn" data-vw-bar="clear" aria-label="고르기 풀기" title="고르기 풀기">✕</button>`;
      }

      /* ---------- 모델 · 연표가 바뀔 때 ---------- */
      let started = false;
      /** 모델을 새로 지은 뒤(viewer.js refresh 끝): 켠 판을 새 자료로 맞추고(판이 사라졌으면 끔 · 구성 나라가 바뀌었으면 다시 모음), 처음이면 기억한 판을 되살림 */
      function sync() {
        const b = current();
        if (!started) {
          started = true;
          const v = state.ui.board ? viewByUid(state.ui.board) : null;
          if (v && v.members.length) turnOn(boardOf(v), { remember: false, fly: false });
          else if (state.ui.board) {
            state.ui.board = null;
            save();
          }
        } else if (b && b.temp) {
          const m = model();
          const members = b.members.filter(uid => m.byUid.has(uid));
          if (!members.length) turnOff();
          else if (members.length !== b.members.length) timeline.setBoard(Object.assign({}, b, { members }), { fly: false });
        } else if (b) {
          const v = viewByUid(b.id);
          if (!v || !v.members.length) turnOff();
          else {
            const nb = boardOf(v);
            if (!same(nb, b)) timeline.setBoard(nb, { fly: false }); // DLC를 고쳤거나(메이커) 다시 읽었으면 새 구성으로 그 자리에서
          }
        }
        syncBtn();
        renderPop();
        renderBar();
      }
      /** 연표가 판을 켜고 껐을 때 (timeline opts.onBoard) */
      function onBoard() {
        syncBtn();
        renderPop();
        rerenderCard();
      }
      return {
        sync,
        onBoard,
        openList: () => (pop.hidden ? openList() : closeList()),
        closeList,
        epochCardHTML,
        onDetailClick,
        noteMulti: () => (multi = true),
        onSelection: uids => {
          if (!uids || !uids.length) multi = false;
          renderBar();
          /* 고치는 중이면 '고른 나라 더하기' 단추만 (메이커는 그리기마다 고름을 다시 칠하므로 목록을 다시 짓지 않음 — 적던 글 · 누르던 단추가 그대로) */
          const add = editing && pop.querySelector('[data-vw-addsel]');
          if (add) {
            const n = pickedToAdd();
            add.disabled = !n;
            add.textContent = addSelText(n);
          }
        },
      };
    },
  };
})();

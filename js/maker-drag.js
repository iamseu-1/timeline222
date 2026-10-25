/* DLC 메이커 — 날짜 이동 계산과 연표 위 편집 · 메이커 안 끌기 한 꼴(HT.makerDrag.slot — 빈 자리 + 빈 자리 안 미리 글, 구조 나무 · 편집 창 블록이 함께 쓰고 뒤에 세계표도). 보기 전용 연표에는 읽히지 않습니다. */
(function () {
  'use strict';
  const HT = window.HT, clone = x => JSON.parse(JSON.stringify(x)), arr = x => Array.isArray(x) ? x : [];
  function unitFor(span, finer = false) { const unit = span >= 2 ? 'year' : span >= 2 / 12 ? 'month' : 'day'; return finer ? unit === 'year' ? 'month' : 'day' : unit; }
  function snap(t, unit) {
    const p = HT.cal.at(t);
    if (unit === 'year') { let y = Math.round(t); if (y === 0) y = t < 0 ? -1 : 1; return { t: y, at: null }; }
    const r = HT.cal.build({ cal: 'civil', y: p.y, m: p.m, ...(unit === 'day' ? { d: p.d } : {}) });
    if (!r.ok) throw Error('이 날짜로 옮길 수 없습니다.');
    return { t: r.t, at: r.text };
  }
  function moveDate(raw, at, amount, unit = 'year') {
    if (raw == null || raw === '' || HT.isUnknownText(raw) || HT.isOngoingText(raw)) return { value: raw, at };
    const read = HT.readDate(raw, at); if (!read || !Number.isFinite(read.t)) return { value: raw, at };
    const parsed = read.at && HT.cal.parse(read.at), p = parsed?.ok ? parsed : HT.cal.at(read.t), cal = parsed?.cal || 'civil';
    if (unit === 'day') {
      const t = HT.cal.tOf(HT.cal.at(read.t).J + amount, HT.cal.at(read.t).frac), parts = HT.cal.partsIn(cal, HT.cal.at(t).J);
      const r = HT.cal.build({ cal, y: parts.y, m: parts.m, leap: parts.leap, d: parts.d, ...(p.h != null ? { h: p.h, mi: p.mi } : {}) });
      return { value: t, at: r.ok ? r.text : HT.cal.formatT(t) };
    }
    const index = HT.cal.toAstro(p.y) * 12 + ((p.m || 1) - 1) + (unit === 'year' ? amount * 12 : amount);
    const y = HT.cal.fromAstro(Math.floor(index / 12)), m = ((index % 12) + 12) % 12 + 1;
    if (!read.at && unit === 'year' && Number.isInteger(read.t)) return { value: y, at: null };
    const parts = { cal, y, m, leap: p.leap, ...(p.d != null ? { d: p.d } : {}), ...(p.h != null ? { h: p.h, mi: p.mi } : {}) };
    let r = HT.cal.build(parts);
    if (!r.ok && parts.leap) { delete parts.leap; r = HT.cal.build(parts); }
    for (let day = p.d || 1; !r.ok && day > 1; day--) { parts.d = day - 1; r = HT.cal.build(parts); }
    if (!r.ok) throw Error('달력의 범위를 벗어나 옮길 수 없습니다.');
    return { value: r.t, at: r.fine ? r.text : null };
  }
  function shiftItem(item, amount, unit = 'year') {
    if (!Number.isInteger(amount) || Math.abs(amount) > 1000000) throw Error('이동할 양은 백만 이하의 정수로 적으세요.');
    const result = clone(item);
    const dateKeys = ['start', 'end', 'birth', 'death', 'from', 'to', 'ratified', 'effective'];
    const cellKeys = new Set(['leaders', 'reigns', 'cabinets', 'eras', 'capitals', 'spans', 'ranks', 'faiths', 'power']); // 목록 꼴 칸 [이름, 시작, 끝, 메모]을 객체로 풀어 옮김 — 단체의 집권 칸(power) · 종교(faiths — 6단계 D8)도
    /* 사람 참조(형식 3 — 지도자 · 내각 칸의 사람 · 자리 이음의 앞 지도자 · 부모 · 배우자 · 단체의 구성원)의 start는 날짜가 아니라 같은 이름의 지도자 칸을 가르는 열쇠입니다.
       그래서 들어가 옮기지 않고, 옮기는 항목 자신의 칸을 가리키는 것(같은 나라 — 그 칸들이 함께 옮겨짐)만 같은 양을 옮깁니다(글 꼴 "나라:지도자@해"도 같게) */
    const s = v => (v == null ? '' : String(v).trim());
    const hasCells = ['leaders', 'reigns', 'cabinets'].some(k => Array.isArray(item && item[k]));
    const ownPolity = r => hasCells && !!r.polity && (r.polity === s(item.name) || r.polity === s(item.id)) && (!r.track || r.track === s(item.track));
    function personRef(v) {
      if (v && typeof v === 'object' && !Array.isArray(v)) {
        if (v.start == null || v.start === '' || !ownPolity({ polity: s(v.polity), track: s(v.track) })) return v;
        const d = moveDate(v.start, v.startAt, amount, unit);
        v.start = d.value;
        if (d.at) v.startAt = d.at; else delete v.startAt;
        return v;
      }
      if (typeof v === 'string') {
        const m = /^(\s*[^:@]+?\s*:\s*[^@]+?\s*@\s*)(.+?)(\s*)$/.exec(v);
        const r = m && HT.readPersonRef(v);
        if (!r || typeof r !== 'object' || r.start == null || !ownPolity(r)) return v;
        const d = moveDate(r.start, r.startAt, amount, unit);
        return m[1] + (d.at || String(d.value)) + m[3];
      }
      return v;
    }
    const PERSON_SLOTS = new Set(['person', 'who']);
    function walk(o, parentKey = '') {
      if (!o || typeof o !== 'object') return;
      if (Array.isArray(o)) {
        for (let i = 0; i < o.length; i++) {
          if (parentKey === 'people') o[i] = personRef(o[i]); // 단체의 구성원 — 사람 참조 목록
          else if (Array.isArray(o[i]) && cellKeys.has(parentKey)) { const x = HT.makerGrid.objectRow(o[i], parentKey); walk(x); o[i] = x; }
          else walk(o[i], parentKey);
        }
        return;
      }
      if (parentKey === 'accession' && o.from != null) o.from = personRef(o.from); // 자리 이음의 앞 지도자 — 날짜 칸 'from'이 아님
      for (const key of dateKeys) if (o[key] != null) {
        if (key === 'from' && (parentKey === 'accession' || parentKey === 'spans' || typeof o[key] === 'object')) continue; // 앞 지도자 · 제도 칸의 온 곳(나라) · 앞선 단체 목록은 날짜가 아님
        const d = moveDate(o[key], o[key + 'At'], amount, unit); o[key] = d.value;
        if (d.at) o[key + 'At'] = d.at; else delete o[key + 'At'];
      }
      for (const edge of ['start', 'end']) {
        if (o[edge + 'Hint'] != null) o[edge + 'Hint'] = moveDate(o[edge + 'Hint'], null, amount, unit).value;
        const key = edge + 'Range';
        if (Array.isArray(o[key])) { const ats = arr(o[key + 'At']); o[key] = o[key].map((v, i) => { const d = moveDate(v, ats[i], amount, unit); ats[i] = d.at; return d.value; }); if (ats.some(Boolean)) o[key + 'At'] = ats; else delete o[key + 'At']; }
      }
      for (const [k, v] of Object.entries(o)) {
        if (PERSON_SLOTS.has(k)) o[k] = personRef(v);
        else if (!dateKeys.includes(k) && !/At$|Range$/.test(k) && v && typeof v === 'object') walk(v, k);
      }
    }
    walk(result); return result;
  }
  function difference(a, b, unit) {
    const x = HT.cal.at(a), y = HT.cal.at(b);
    return unit === 'day' ? y.J - x.J : unit === 'month' ? (y.ay - x.ay) * 12 + y.m - x.m : y.ay - x.ay;
  }
  function setDate(x, key, d) { x[key] = d.t; if (d.at) x[key + 'At'] = d.at; else delete x[key + 'At']; delete x[key + 'Unknown']; delete x[key + 'Hint']; if (key === 'end') delete x.ongoing; }
  function changeItem(raw, change) {
    if (change.part === 'move') return shiftItem(raw, change.amount, change.unit);
    const x = clone(raw), d = change.date;
    if (change.part === 'seam') {
      const key = change.list === 'leaders' && !x.leaders && x.reigns ? 'reigns' : change.list, list = arr(x[key]);
      const nextIndex = change.nextIndex ?? change.index + 1;
      const left = HT.makerGrid.objectRow(list[change.index], change.list), right = HT.makerGrid.objectRow(list[nextIndex], change.list);
      if (!left || !right) throw Error('맞닿은 칸을 찾지 못했습니다.');
      const lo = HT.readDate(left.start, left.startAt), hi = HT.readDate(right.end ?? x.end, right.endAt || x.endAt);
      if (lo && Number.isFinite(lo.t) && d.t < lo.t || hi && Number.isFinite(hi.t) && d.t > hi.t) throw Error('이웃 칸의 범위를 넘을 수 없습니다.');
      setDate(left, 'end', d); setDate(right, 'start', d); list[change.index] = left; list[nextIndex] = right;
    } else {
      if (!['start', 'end'].includes(change.part)) throw Error('고칠 날짜를 찾지 못했습니다.');
      setDate(x, change.part, d);
      const a = HT.readDate(x.start, x.startAt), b = HT.readDate(x.end, x.endAt);
      if (a && b && Number.isFinite(a.t) && Number.isFinite(b.t) && b.t < a.t) throw Error('끝이 시작보다 앞설 수 없습니다.');
    }
    return x;
  }
  function applyItems(draft, uids, change, ctx, api) {
    const next = clone(draft); let changed = 0, skipped = 0;
    for (const uid of uids) {
      const model = ctx.state.model.byUid.get(uid), own = HT.draft.isOwnUid(draft, uid) && HT.draft.findOwn(next, uid.slice(draft.id.length + 1));
      if (!own && (!model || api.isLocked(model) || ['epoch', 'scope'].includes(model.itemKind))) { skipped++; continue; }
      const raw = own ? own.item : api.rawOf(model), item = changeItem(raw, change);
      if (!own) for (const [key, doc] of ctx.state.model.docs || []) if (key.startsWith('cell:' + uid + ':') && !Object.keys(next.documents).some(k => HT.docKey.absolute(k, next.id) === key)) next.documents[key] = doc.text;
      HT.makerGrid.moveCellDocuments(next, uid, raw, item, change);
      if (own) { for (const key of Object.keys(own.item)) delete own.item[key]; Object.assign(own.item, item); }
      else HT.makerGrid.patchItem(next, api.baseModel().byUid.get(uid) || model, raw, item);
      changed++;
    }
    return { draft: next, changed, skipped };
  }
  function mount(ctx, api) {
    const stage = ctx.$('#stage'), tl = ctx.timeline;
    let dragging = null, frame = 0;
    const layer = document.createElement('div'); layer.className = 'mk-drag-layer'; stage.append(layer);
    const esc = ctx.esc;
    const selected = () => api.selection().length ? api.selection() : ctx.state.selected ? [ctx.state.selected] : [];
    function paint() {
      frame = 0; if (dragging) return;
      const root = stage.getBoundingClientRect(), html = [];
      for (const uid of selected()) {
        const x = ctx.state.model.byUid.get(uid); if (!x || api.isLocked(x) || !HT.draft.isOwnUid(api.draft, uid) && ['epoch', 'scope'].includes(x.itemKind)) continue;
        const item = stage.querySelector(`.tl-band[data-uid="${CSS.escape(uid)}"], .tl-org[data-uid="${CSS.escape(uid)}"], .tl-under[data-uid="${CSS.escape(uid)}"], .tl-fig[data-uid="${CSS.escape(uid)}"], .tl-epoch[data-uid="${CSS.escape(uid)}"], .tl-dyn[data-uid="${CSS.escape(uid)}"]`) || stage.querySelector(`.tl-scope[data-uid="${CSS.escape(uid)}"] .tl-scope-span:not([hidden])`);
        if (!item || x.itemKind === 'event') continue;
        const box = item.getBoundingClientRect(); if (box.width < 24 || box.bottom < root.top || box.top > root.bottom) continue;
        for (const side of ['start', 'end']) {
          if (side === 'start' && x.start < tl.view.start || side === 'end' && (x.endY ?? x.end) > tl.view.end) continue;
          const px = side === 'start' ? box.left : box.right;
          if (px < root.left + tl.gutter || px > root.right - 2) continue;
          html.push(`<button type="button" class="mk-drag-handle" data-edit-uid="${esc(uid)}" data-edit-part="${side}" style="left:${px - root.left - (side === 'end' ? 7 : 0)}px;top:${Math.max(0, box.top - root.top + 2)}px;height:${Math.min(22, box.height - 4)}px" aria-label="${esc(x.name || x.title)} ${side === 'start' ? '시작' : '끝'} 날짜 끌기" title="${side === 'start' ? '시작' : '끝'} 날짜 끌기"></button>`);
        }
        if (selected().length === 1) for (const key of ['leaders', 'cabinets', 'eras', 'capitals']) {
          const cells = HT.cellsOf(x, key);
          const raw = api.rawOf(x), rows = arr(raw?.[key] || (key === 'leaders' ? raw?.reigns : null));
          const rawIndex = cell => rows.findIndex(c => { const o = HT.makerGrid.objectRow(c, key), name = o.name || o.as || o.city || o.temple || o.title || o.given; return [cell.name, cell.as, cell.city, cell.temple, cell.title, cell.given].includes(name) && (o.start == null || HT.readDate(o.start, o.startAt)?.t === cell.start); });
          for (let i = 0; i < cells.length - 1; i++) if (Number.isFinite(cells[i].end) && Math.abs(cells[i].end - cells[i + 1].start) < 1e-8) {
            const left = rawIndex(cells[i]), right = rawIndex(cells[i + 1]); if (left < 0 || right < 0 || left === right) continue;
            const k = HT.cellKind(key), node = item.querySelector(`[data-cell="${k.id}:${i}"]`) || stage.querySelector(`[data-uid="${CSS.escape(uid)}"][data-cell="${k.id}:${i}"]`); if (!node) continue;
            const b = node.getBoundingClientRect(); if (b.width < 20 || b.right > root.right || b.right < root.left + tl.gutter) continue;
            html.push(`<button type="button" class="mk-drag-seam" data-edit-uid="${esc(uid)}" data-edit-part="seam" data-edit-list="${key}" data-edit-index="${left}" data-edit-next="${right}" style="left:${b.right - root.left - 3}px;top:${b.top - root.top + 2}px;height:${Math.max(4, b.height - 4)}px" aria-label="${esc(k.name)} 칸 경계 끌기"></button>`);
          }
        }
      }
      layer.innerHTML = html.join('');
    }
    const schedule = () => { if (!frame) frame = requestAnimationFrame(paint); };
    new MutationObserver(records => { if (records.some(r => !layer.contains(r.target))) schedule(); }).observe(stage, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
    stage.addEventListener('scroll', schedule, true); window.addEventListener('resize', schedule);
    const body = tl.bodyEl;
    function finish(cancel) {
      if (!dragging) return; const d = dragging; dragging = null; layer.innerHTML = ''; schedule();
      if (cancel || !d.change) return;
      if (d.create) { api.createAt(d.track, d.start, d.change.date, Math.abs(d.lastX - d.x) > 5); return; }
      const unknown = ['start', 'end'].includes(d.part) && ctx.state.model.byUid.get(d.uid)?.[d.part + 'Unknown'];
      api.transact(raw => {
        const result = applyItems(raw, d.uids, d.change, ctx, api);
        if (result.skipped) HT.toast(`잠긴 항목 ${result.skipped}개는 옮기지 않았습니다.`);
        return result.draft;
      }, d.part === 'move' ? '고른 항목 날짜 옮기기' : d.part === 'seam' ? '이어진 칸 경계 끌기' : `${d.part === 'start' ? '시작' : '끝'} 날짜 끌기`, { snapshot: d.uids.length > 20 }).then(ok => { if (ok && unknown) HT.toast('미정이던 연대를 끌어 놓은 날짜로 정했습니다.', 'ok'); });
    }
    stage.addEventListener('pointerdown', e => {
      if (e.button !== 0 || !api.draft || e.target.closest('input,textarea,select') || ctx.$('#mkCenter') && !ctx.$('#mkCenter').hidden) return;
      const handle = e.target.closest('[data-edit-uid]'), hit = e.target.closest('[data-uid]'), uid = handle?.dataset.editUid || hit?.dataset.uid, item = uid && ctx.state.model.byUid.get(uid), picks = selected();
      const create = !hit && !handle && (e.ctrlKey || e.metaKey) && e.target.closest('.tl-lanes'), track = e.target.closest('[data-track]')?.dataset.track;
      const event = item?.itemKind === 'event' && picks.includes(uid) && e.target.closest('.tl-ev');
      if (!handle && !(e.altKey && picks.includes(uid)) && !event && !create) return;
      if (item && (api.isLocked(item) || !HT.draft.isOwnUid(api.draft, uid) && ['epoch', 'scope'].includes(item.itemKind))) return;
      if (create && !track) return;
      e.preventDefault(); e.stopImmediatePropagation();
      const unit = unitFor(tl.span(), e.shiftKey), at = snap(tl.yearAtClientX(e.clientX), unit), part = handle?.dataset.editPart || 'move';
      dragging = { id: e.pointerId, x: e.clientX, lastX: e.clientX, start: at, y: e.clientY, unit, part, uid, uids: part === 'move' ? picks : [uid], create, track, list: handle?.dataset.editList, index: Number(handle?.dataset.editIndex), nextIndex: Number(handle?.dataset.editNext), change: create ? { date: at } : null };
      dragging.boxes = create ? [] : dragging.uids.filter(u => !api.isLocked(ctx.state.model.byUid.get(u))).flatMap(u => {
        const node = stage.querySelector(`.tl-band[data-uid="${CSS.escape(u)}"],.tl-org[data-uid="${CSS.escape(u)}"],.tl-under[data-uid="${CSS.escape(u)}"],.tl-fig[data-uid="${CSS.escape(u)}"],.tl-epoch[data-uid="${CSS.escape(u)}"],.tl-dyn[data-uid="${CSS.escape(u)}"],.tl-ev[data-uid="${CSS.escape(u)}"]`) || (u === uid ? hit : null);
        if (!node) return []; const b = node.getBoundingClientRect(); return [{ left: b.left, top: b.top, width: b.width, height: b.height }];
      });
      stage.setPointerCapture(e.pointerId);
      layer.innerHTML = (dragging.boxes.length ? dragging.boxes : [null]).map(() => '<div class="mk-drag-ghost"></div>').join('') + '<div class="mk-drag-date"></div>';
    }, true);
    stage.addEventListener('pointermove', e => {
      const d = dragging; if (!d || e.pointerId !== d.id) return; e.preventDefault(); e.stopImmediatePropagation();
      const unit = unitFor(tl.span(), e.shiftKey), at = snap(tl.yearAtClientX(e.clientX), unit); d.lastX = e.clientX;
      d.change = d.part === 'move' && !d.create ? { part: 'move', amount: difference(snap(tl.yearAtClientX(d.x), unit).t, at.t, unit), unit } : { part: d.part, date: at, list: d.list, index: d.index, nextIndex: d.nextIndex };
      const r = stage.getBoundingClientRect(), tip = layer.querySelector('.mk-drag-date');
      layer.querySelectorAll('.mk-drag-ghost').forEach((ghost, i) => {
        const b = d.boxes[i], dx = e.clientX - d.x;
        const left = b ? b.left + (d.part === 'end' ? 0 : dx) : Math.min(d.x, e.clientX), width = b ? d.part === 'move' ? b.width : d.part === 'start' ? b.width - dx : b.width + dx : Math.abs(dx);
        ghost.style.cssText = `left:${left - r.left}px;top:${Math.max(0, (b?.top ?? d.y - 12) - r.top)}px;width:${Math.max(2, width)}px;height:${b?.height || 24}px`;
      });
      tip.style.cssText = `left:${Math.max(0, Math.min(r.width - 180, e.clientX - r.left + 12))}px;top:${Math.max(0, d.y - r.top - 42)}px`;
      tip.textContent = d.part === 'move' && !d.create ? `${d.change.amount > 0 ? '+' : ''}${d.change.amount}${unit === 'year' ? '년' : unit === 'month' ? '개월' : '일'}` : HT.formatDate(at.t, at.at);
    }, true);
    for (const type of ['pointerup', 'pointercancel']) stage.addEventListener(type, e => { if (!dragging) return; e.preventDefault(); e.stopImmediatePropagation(); if (stage.hasPointerCapture(e.pointerId)) stage.releasePointerCapture(e.pointerId); finish(type === 'pointercancel'); }, true);
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && dragging) { e.preventDefault(); e.stopImmediatePropagation(); finish(true); return; }
      if (!e.altKey || !['ArrowLeft', 'ArrowRight'].includes(e.key) || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable || document.querySelector('dialog[open]')) return;
      const picks = selected(); if (!picks.length) return;
      e.preventDefault(); e.stopImmediatePropagation();
      const unit = unitFor(tl.span()), amount = (e.key === 'ArrowRight' ? 1 : -1) * (e.shiftKey ? 10 : 1);
      api.transact(raw => applyItems(raw, picks, { part: 'move', amount, unit }, ctx, api).draft, `고른 항목 ${amount}${unit === 'year' ? '년' : unit === 'month' ? '개월' : '일'} 옮기기`, { snapshot: picks.length > 20 });
    }, true);
    schedule(); return { refresh: schedule };
  }

  /* ---------- 메이커 안 끌기 한 꼴 — 빈 자리 + 빈 자리 안 미리 글 (10건 D3 결정 3 C) ----------
   * 구조 나무 끌기(js/maker-shell.js — 이동 배정) · 편집 창 블록 줄 끌기(js/maker-blocks.js)가 함께 쓰고, 뒤에 세계표에서 끌어 부모 적기(D1-M2 —
   * docs/설계-10건/의 1-2 확정 설계 7-3)도 이 함수를 씁니다 — 메이커 안 끌기 꼴이 하나가 되도록 새 끌기는 여기에 o만 꾸며 붙입니다.
   *   꼴: 누른 채 5px 넘게 움직이면 시작 → 끄는 것(들)은 제자리에서 접혀 빠지고(--t-move) 손 밑에 작은 사본이 따라옴 →
   *       놓을 수 있는 곳 위면 그 자리에 점선 둥근 빈 자리가 열려 다른 줄이 비켜나고(--t-move · 되튐 없음 · 움직임 줄이기면 곧장), 사본은 빈 자리 안 위쪽에,
   *       미리 글("놓으면: …")은 빈 자리 안 아래쪽에 → 놓을 수 없는 곳이면 빈 자리 없이 손 밑 사본 아래에 까닭 글만 → 놓으면 빈 자리의 뜻대로.
   *       Esc · 포인터 취소 = 그만둠. 빈 자리 위에 손이 있는 동안은 그 빈 자리 그대로(열리며 밀린 줄 때문에 자리가 오락가락하지 않게).
   *       끝 가까이에서는 o.scroller()를 저절로 굴리고, 접힌 가지 위에 700ms 머물면 o.open(열쇠)(사람의 뜻을 기다리는 타이머라 HT.motion 시계가 아님).
   * HT.makerDrag.slot(root, o) → { refresh(), cancel(), active }
   *   o.grab(target, ev)        누른 곳 → 끌 손잡이(요소) · null(이 끌기의 일이 아님 — 누르기는 그대로)
   *   o.payload(grip, ev)       5px 넘게 움직였을 때 끌 것 (null = 끌 수 없음 — 그대로 누르기)
   *   o.lifted(p)               끄는 동안 접어 둘 요소들 — 다시 그려진 뒤(refresh)에도 다시 찾음
   *   o.ghost(p)                손 밑 사본의 글 { name, years?, kind? }
   *   o.hit(x, y, mods, p, at)  놓을 곳 → null(놓을 곳 밖 — o.idle 글) ·
   *                             { key, ok, text | reason, anchor, where: 'before' | 'after' | 'prepend' | 'append', indent?(px), minHeight?(px), mark?, markClass?, ring?, …놓을 때 쓰는 값 }
   *                             mods = { ctrl, alt, shift } · at = 그 자리의 요소(빈 자리는 빼고) · again?(mods) = 같은 자리에서 키만 바뀌었을 때의 hit
   *   o.drop(p, hit, mods, ev)  놓기(ok일 때만) · o.refuse?(p, hit) 놓을 수 없는 곳에서 놓았을 때
   *   o.scroller?() · o.hover?(hit) → 머물면 펼칠 열쇠('' = 없음) · o.open?(열쇠) · o.idle 놓을 곳 밖일 때 사본 아래 글 · o.start?(p) · o.end?(p) */
  let sharedGhost = null; // 손 밑 사본은 한 장 — 끌기는 한 번에 하나라 모든 slot()이 함께 씀
  function slot(root, o) {
    const esc = s => HT.escapeHtml(String(s ?? ''));
    const dur = () => (HT.motion && HT.motion.T && HT.motion.T.move > 0 ? HT.motion.T.move : 0);
    const curve = () => (HT.motion && HT.motion.C ? HT.motion.C.spring : 'ease');
    if (!sharedGhost) {
      sharedGhost = document.body.appendChild(Object.assign(document.createElement('div'), { className: 'mk-dnd-ghost', hidden: true }));
      sharedGhost.setAttribute('role', 'status');
    }
    const ghostEl = sharedGhost;
    let d = null, swallow = false;
    const chipHTML = g => `<span class="g" aria-hidden="true">⋮⋮</span><b>${esc(g && g.name)}</b>${g && g.years ? `<span class="y">${esc(g.years)}</span>` : ''}${g && g.kind ? `<span class="k">${esc(g.kind)}</span>` : ''}`;
    const modsOf = e => ({ ctrl: !!(e.ctrlKey || e.metaKey), alt: !!e.altKey, shift: !!e.shiftKey });
    /** 끄는 것을 제자리에서 접음 (instant = 다시 그려진 뒤 — 이미 빠져 있던 것이라 움직임 없이) */
    function lift(instant) {
      d.lifted = d.lifted.filter(l => l.el.isConnected);
      for (const el of (o.lifted ? o.lifted(d.p) : []).filter(el => el && el.isConnected)) {
        if (d.lifted.some(l => l.el === el)) continue;
        const cs = getComputedStyle(el);
        el.classList.add('is-dragging');
        el.style.overflow = 'hidden';
        const from = { height: `${el.getBoundingClientRect().height}px`, opacity: cs.opacity, paddingTop: cs.paddingTop, paddingBottom: cs.paddingBottom, marginTop: cs.marginTop, marginBottom: cs.marginBottom, borderTopWidth: cs.borderTopWidth, borderBottomWidth: cs.borderBottomWidth };
        const to = { height: '0px', opacity: 0, paddingTop: '0px', paddingBottom: '0px', marginTop: '0px', marginBottom: '0px', borderTopWidth: '0px', borderBottomWidth: '0px' };
        d.lifted.push({ el, anim: el.animate([from, to], { duration: instant ? 0 : dur(), easing: curve(), fill: 'forwards' }) });
      }
    }
    function unlift(x) {
      for (const l of x.lifted) {
        l.anim.cancel();
        l.el.style.overflow = '';
        l.el.classList.remove('is-dragging');
      }
      x.lifted = [];
    }
    function unmark(x) {
      const h = x && x.hit;
      if (!h) return;
      if (h.mark && h.markClass) h.mark.classList.remove(...h.markClass.split(' '));
      if (h.ring) h.ring.classList.remove('is-drop-into');
    }
    function mark(h) {
      if (!h) return;
      if (h.mark && h.markClass) h.mark.classList.add(...h.markClass.split(' '));
      if (h.ring && h.ok) h.ring.classList.add('is-drop-into');
    }
    function closeSlot(el, instant) {
      if (!el) return;
      if (instant || !dur() || !el.isConnected) return el.remove();
      el.classList.add('is-closing');
      const cs = getComputedStyle(el);
      const a = el.animate([{ height: `${el.offsetHeight}px`, minHeight: `${el.offsetHeight}px`, paddingTop: cs.paddingTop, paddingBottom: cs.paddingBottom, opacity: 1 }, { height: '0px', minHeight: '0px', paddingTop: '0px', paddingBottom: '0px', marginTop: '0px', marginBottom: '0px', borderTopWidth: '0px', borderBottomWidth: '0px', opacity: 0 }], { duration: dur(), easing: curve(), fill: 'forwards' });
      a.onfinish = () => el.remove();
    }
    function openSlot(h, instant) {
      const el = document.createElement('div');
      el.className = `mk-slot${h.slotClass ? ` ${h.slotClass}` : ''}`;
      el.setAttribute('aria-hidden', 'true');
      if (h.indent != null) el.style.marginLeft = `${h.indent}px`;
      el.innerHTML = `<div class="mk-dnd-chip">${chipHTML(o.ghost(d.p))}</div><p class="mk-slot-pre"><i>i</i><span></span></p>`;
      el.querySelector('.mk-slot-pre span').textContent = h.text || '';
      if (h.where === 'before') h.anchor.before(el);
      else if (h.where === 'prepend') h.anchor.prepend(el);
      else if (h.where === 'append') h.anchor.append(el);
      else h.anchor.after(el);
      if (h.minHeight) el.style.minHeight = `${Math.round(h.minHeight)}px`;
      if (!instant && dur()) {
        const cs = getComputedStyle(el);
        const full = `${el.offsetHeight}px`;
        el.animate([{ height: '0px', minHeight: '0px', paddingTop: '0px', paddingBottom: '0px', opacity: 0 }, { height: full, minHeight: full, paddingTop: cs.paddingTop, paddingBottom: cs.paddingBottom, opacity: 1 }], { duration: dur(), easing: curve() });
      }
      return el;
    }
    /** 놓을 곳을 보임 — 자리(열쇠)가 그대로면 빈 자리는 두고 글만 고침 */
    function show(h, instant = false) {
      const same = !!h && !!d.hit && h.key === d.hit.key && !!h.ok === !!d.hit.ok && !!d.slotEl === !!h.ok && (!d.slotEl || d.slotEl.isConnected);
      if (same) {
        if (h.mark !== d.hit.mark || h.markClass !== d.hit.markClass || h.ring !== d.hit.ring) {
          unmark(d);
          mark(h);
        }
        if (d.slotEl && (h.text || '') !== (d.hit.text || '')) d.slotEl.querySelector('.mk-slot-pre span').textContent = h.text || '';
        d.hit = h;
      } else {
        unmark(d);
        closeSlot(d.slotEl, instant);
        d.slotEl = null;
        d.hit = h;
        mark(h);
        if (h && h.ok && h.anchor && h.anchor.isConnected) d.slotEl = openSlot(h, instant);
      }
      const inSlot = !!d.slotEl;
      ghostEl.hidden = inSlot;
      if (!inSlot) {
        const html = `<div class="mk-dnd-chip">${chipHTML(o.ghost(d.p))}</div><p class="mk-dnd-why">${esc(!h ? o.idle || '여기에는 놓을 수 없음' : h.ok ? h.text : `놓을 수 없음 — ${h.reason || ''}`)}</p>`;
        if (html !== ghostEl._html) ghostEl.innerHTML = ghostEl._html = html;
        ghostEl.classList.toggle('is-no', !h || !h.ok);
        ghostEl.style.transform = `translate(${Math.round(Math.max(4, Math.min(d.x + 14, innerWidth - ghostEl.offsetWidth - 8)))}px, ${Math.round(Math.min(d.y + 18, innerHeight - ghostEl.offsetHeight - 4))}px)`;
      }
      const key = h && o.hover ? o.hover(h) || '' : '';
      if (key !== d.hoverKey) {
        clearTimeout(d.hoverT);
        d.hoverKey = key;
        if (key)
          d.hoverT = setTimeout(() => {
            if (!d || !d.started || d.hoverKey !== key) return;
            if (o.open) o.open(key);
            refresh();
          }, 700);
      }
    }
    function move(x, y, mods, instant = false) {
      Object.assign(d, { x, y, mods });
      let at = document.elementFromPoint(x, y);
      if (at && ghostEl.contains(at)) at = null;
      if (at && d.slotEl && d.slotEl.contains(at) && d.hit) return show((d.hit.again && d.hit.again(mods)) || d.hit, instant); // 빈 자리 위 — 그 자리 그대로 (키가 바뀌었으면 같은 자리의 뜻만 다시 — hit.again(mods))
      if (at && at.closest && at.closest('.mk-slot.is-closing')) return show(d.hit, instant); // 닫히는 빈 자리 위 — 곧 사라짐
      show(o.hit(x, y, mods, d.p, at), instant);
    }
    function scrollLoop() {
      if (!d || !d.started) return;
      const box = o.scroller && o.scroller();
      if (box && d.x != null) {
        const r = box.getBoundingClientRect();
        const edge = 28;
        const v = d.y < r.top + edge ? -Math.ceil((r.top + edge - d.y) / 3) : d.y > r.bottom - edge ? Math.ceil((d.y - r.bottom + edge) / 3) : 0;
        if (v && d.y >= r.top - 40 && d.y <= r.bottom + 40) {
          const top = box.scrollTop;
          box.scrollTop += v;
          if (box.scrollTop !== top) move(d.x, d.y, d.mods);
        }
      }
      d.raf = requestAnimationFrame(scrollLoop);
    }
    function finish(cancel, ev) {
      const x = d;
      d = null;
      if (!x || !x.started) return;
      clearTimeout(x.hoverT);
      cancelAnimationFrame(x.raf);
      const h = x.hit;
      unmark(x);
      unlift(x);
      if (x.slotEl) x.slotEl.remove();
      for (const el of document.querySelectorAll('.mk-slot.is-closing')) el.remove();
      ghostEl.hidden = true;
      document.body.classList.remove('mk-dnd-on');
      swallow = true;
      setTimeout(() => (swallow = false), 0);
      if (o.end) o.end(x.p);
      if (cancel) return;
      if (h && h.ok) o.drop(x.p, h, x.mods || {}, ev);
      else if (o.refuse) o.refuse(x.p, h, ev);
    }
    /** 다시 그려진 뒤(나무를 새로 그림 · 블록을 펼침): 끄는 것은 다시 접고, 빈 자리는 지금 손 자리에서 다시 셈 (움직임 없이) */
    function refresh() {
      if (!d || !d.started) return;
      lift(true);
      if (d.slotEl && !d.slotEl.isConnected) d.slotEl = null;
      unmark(d);
      d.hit = null;
      if (d.slotEl) {
        d.slotEl.remove();
        d.slotEl = null;
      }
      if (d.x != null) move(d.x, d.y, d.mods || {}, true);
    }
    root.addEventListener('pointerdown', e => {
      if (e.button !== 0 || d) return;
      const grip = o.grab(e.target, e);
      if (!grip) return;
      d = { id: e.pointerId, x0: e.clientX, y0: e.clientY, grip, started: false, lifted: [], hit: null, slotEl: null, hoverKey: '' };
    });
    window.addEventListener('pointermove', e => {
      if (!d || e.pointerId !== d.id) return;
      if (!d.started) {
        if (Math.hypot(e.clientX - d.x0, e.clientY - d.y0) < 5) return;
        const p = o.payload(d.grip, e);
        if (!p) {
          d = null;
          return;
        }
        d.p = p;
        d.started = true;
        try {
          root.setPointerCapture(e.pointerId); // 다른 곳(연표 등) 위로 지나가거나 거기서 놓아도 그쪽이 눌린 것으로 처리되지 않게 (놓을 곳은 좌표로 찾음)
        } catch (err) {
          /* 시험용 합성 포인터는 붙잡을 수 없습니다 — 끌기는 그대로 */
        }
        document.body.classList.add('mk-dnd-on');
        if (o.start) o.start(p);
        lift(false);
        d.raf = requestAnimationFrame(scrollLoop);
      }
      move(e.clientX, e.clientY, modsOf(e));
    });
    window.addEventListener('pointerup', e => {
      if (!d || e.pointerId !== d.id) return;
      if (!d.started) {
        d = null;
        return;
      }
      move(e.clientX, e.clientY, modsOf(e)); // 놓는 순간의 키(Ctrl 등)까지 — 자리는 지금 보이는 빈 자리 그대로
      finish(false, e);
    });
    window.addEventListener('pointercancel', e => {
      if (d && e.pointerId === d.id) finish(true, e);
    });
    document.addEventListener(
      'keydown',
      e => {
        if (!d || !d.started) return;
        if (e.key === 'Escape') {
          e.preventDefault();
          e.stopImmediatePropagation();
          finish(true, e);
        } else if (e.key === 'Control' || e.key === 'Meta' || e.key === 'Alt' || e.key === 'Shift') move(d.x, d.y, modsOf(e)); // 키만 눌러도 미리 글이 바뀜 (복사 · 옮기기)
      },
      true
    );
    document.addEventListener('keyup', e => d && d.started && /^(Control|Meta|Alt|Shift)$/.test(e.key) && move(d.x, d.y, modsOf(e)), true);
    window.addEventListener(
      'click',
      e => {
        if (!swallow) return;
        e.preventDefault();
        e.stopImmediatePropagation();
      },
      true
    ); // 끈 뒤 손을 뗄 때의 누르기는 누르기가 아님
    return {
      refresh,
      cancel: () => finish(true),
      get active() {
        return !!(d && d.started);
      },
    };
  }
  HT.makerDrag = { unitFor, snap, moveDate, shiftItem, difference, changeItem, applyItems, mount, slot };
})();

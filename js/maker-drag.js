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
      if (d.axis === 'y') { // 줄 위아래 옮기기 — 놓을 수 없는 곳에서 놓으면 까닭만 알림
        if (cancel) return;
        if (d.row) commitRow(d.row.site, d.row.plan);
        else if (d.rowReason) HT.toast(d.rowReason);
        return;
      }
      if (cancel || !d.change) return;
      if (d.create) { api.createAt(d.track, d.start, d.change.date, Math.abs(d.lastX - d.x) > 5); return; }
      const unknown = ['start', 'end'].includes(d.part) && ctx.state.model.byUid.get(d.uid)?.[d.part + 'Unknown'];
      api.transact(raw => {
        const result = applyItems(raw, d.uids, d.change, ctx, api);
        if (result.skipped) HT.toast(`잠긴 항목 ${result.skipped}개는 옮기지 않았습니다.`);
        return result.draft;
      }, d.part === 'move' ? '고른 항목 날짜 옮기기' : d.part === 'seam' ? '이어진 칸 경계 끌기' : `${d.part === 'start' ? '시작' : '끝'} 날짜 끌기`, { snapshot: d.uids.length > 20 }).then(ok => { if (ok && unknown) HT.toast('미정이던 연대를 끌어 놓은 날짜로 정했습니다.', 'ok'); });
    }
    /** 줄 위아래 옮기기 적용 — 되돌리기 한 걸음(api.transact) */
    function commitRow(site, plan) {
      api.transact(raw => applyRowMove(raw, plan, api), rowMoveName(site, plan)).then(ok => {
        if (ok && plan.switched) HT.toast(`«${site.g.name}»의 배열 기준을 '북 → 남'으로 바꾸고 남북 위치 ${plan.values.size}곳을 적었습니다.`, 'ok');
      });
    }
    /** 줄을 끄는 동안: 사본(.mk-drag-ghost)은 세로로만 따라오고, 놓을 수 있으면 놓을 자리에 점선(.mk-drag-row-line) · 풍선에 미리 글, 아니면 풍선에 까닭 글만 */
    function rowHover(d, e) {
      const r = stage.getBoundingClientRect(), site = d.site;
      const ghost = layer.querySelector('.mk-drag-ghost'), line = layer.querySelector('.mk-drag-row-line'), tip = layer.querySelector('.mk-drag-date');
      const trEl = site.ok ? stage.querySelector(`.tl-track[data-track="${CSS.escape(site.tr.id)}"]`) : null;
      const lane = n => (trEl ? trEl.querySelector(`.tl-lane[data-row="${n}"]`) : null);
      const rectOf = b => { const a = lane(b.first), z = lane(b.end - 1); if (!a || !z) return null; const x = a.getBoundingClientRect(), y = z.getBoundingClientRect(); return { top: x.top, bottom: y.bottom, left: x.left, right: x.right }; };
      if (!d.rowBox) {
        const own = site.ok ? rectOf(site.R) : null, b0 = d.boxes[0];
        let left = Infinity, right = -Infinity;
        if (site.ok) for (const p of site.tr.rowPeriods[site.R.r] || []) { const n = stage.querySelector(`.tl-band[data-uid="${CSS.escape(p.uid)}"]`); if (n) { const b = n.getBoundingClientRect(); left = Math.min(left, b.left); right = Math.max(right, b.right); } }
        if (!(right > left) && b0) { left = b0.left; right = b0.left + b0.width; }
        d.rowBox = own && right > left ? { left: Math.max(left, own.left), right: Math.min(right, own.right), top: own.top, height: own.bottom - own.top } : b0 ? { left: b0.left, right: b0.left + b0.width, top: b0.top, height: b0.height } : null;
      }
      const g = d.rowBox, dy = e.clientY - d.y;
      if (g) ghost.style.cssText = `left:${g.left - r.left}px;top:${g.top + dy - r.top}px;width:${Math.max(2, g.right - g.left)}px;height:${g.height}px`;
      const above = e.clientY - 42 >= tl.bodyEl.getBoundingClientRect().top + 44; // 연표 몸통 맨 위(붙어 있는 머리 단 · 표시) 가까이면 풍선을 손 아래로 — 글이 겹치지 않게
      tip.style.cssText = `left:${Math.max(0, Math.min(r.width - 420, e.clientX - r.left + 12))}px;top:${Math.max(0, e.clientY - r.top + (above ? -42 : 18))}px`;
      const say = (text, ok) => { tip.textContent = text; tip.classList.toggle('is-no', !ok); line.hidden = true; d.row = null; d.rowReason = ok ? '' : text; };
      if (!site.ok) return say(site.reason, false);
      const rects = new Map(site.blocks.map(b => [b, rectOf(b)]));
      const all = [...rects.values()].filter(Boolean);
      if (!all.length) return say('이 줄의 자리를 찾지 못했습니다.', false);
      const top = Math.min(...all.map(x => x.top)), bottom = Math.max(...all.map(x => x.bottom));
      if (e.clientY < top - 8 || e.clientY > bottom + 8) return say(`다른 민족 · 다른 트랙으로는 옮길 수 없습니다 — «${site.g.name}» 묶음 안에서만 옮깁니다.`, false);
      const others = site.blocks.filter(b => b !== site.R);
      const k = others.filter(b => { const x = rects.get(b); return x && (x.top + x.bottom) / 2 < e.clientY; }).length;
      if (!d.plans.has(k)) d.plans.set(k, rowMove(ctx, api, site, k));
      const plan = d.plans.get(k);
      if (plan.same) return say('놓으면: 제자리', true);
      if (!plan.ok) return say(plan.reason, false);
      const upper = others[k - 1], below = others[k], ra = upper && rects.get(upper), rb = below && rects.get(below);
      const y = ra && rb ? (ra.bottom + rb.top) / 2 : ra ? ra.bottom : rb ? rb.top : e.clientY;
      const ref = ra || rb || all[0];
      say(`놓으면: ${upper ? `«${rowNameOf(upper)}» 아래` : `«${rowNameOf(below)}» 위`} · 남북 위치 ${plan.value}${plan.switched ? ` · «${site.g.name}» 북 → 남` : ''}`, true);
      line.hidden = false;
      line.style.cssText = `left:${ref.left - r.left}px;width:${Math.max(2, ref.right - ref.left)}px;top:${y - r.top - 1}px`;
      d.row = { site, plan };
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
      /* 고른 나라 하나의 몸통 Alt+끌기는 처음 6px에서 세로가 더 크면 줄 위아래 옮기기(가로는 그대로) — 아래 rowHover */
      dragging.rowable = part === 'move' && !create && dragging.uids.length === 1 && !!item && HT.itemKindOf(item) === 'period' && item._row != null;
      stage.setPointerCapture(e.pointerId);
      layer.innerHTML = (dragging.boxes.length ? dragging.boxes : [null]).map(() => '<div class="mk-drag-ghost"></div>').join('') + '<div class="mk-drag-date"></div>';
    }, true);
    stage.addEventListener('pointermove', e => {
      const d = dragging; if (!d || e.pointerId !== d.id) return; e.preventDefault(); e.stopImmediatePropagation();
      if (d.part === 'move' && !d.create && !d.axis && Math.max(Math.abs(e.clientX - d.x), Math.abs(e.clientY - d.y)) >= 6) {
        d.axis = d.rowable && Math.abs(e.clientY - d.y) > Math.abs(e.clientX - d.x) ? 'y' : 'x';
        if (d.axis === 'y') {
          d.change = null; d.site = rowSite(ctx, d.uid); d.plans = new Map();
          layer.innerHTML = '<div class="mk-drag-ghost"></div><div class="mk-drag-row-line" hidden></div><div class="mk-drag-date is-row" role="status"></div>';
        }
      }
      if (d.axis === 'y') { rowHover(d, e); return; }
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
      if (e.altKey && !e.ctrlKey && !e.metaKey && ['ArrowUp', 'ArrowDown'].includes(e.key) && api.draft && (stage.contains(e.target) || e.target === document.body || e.target === document.documentElement) && !/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) && !e.target.isContentEditable && !document.querySelector('dialog[open]')) {
        /* Alt+↑/↓ = 고른 나라의 줄을 같은 민족 묶음 안에서 한 칸 위 · 아래로 (끌기와 같은 계획 · 연표에 글쇠가 있을 때만 — 구조 나무 · 편집 창 · 틀의 Alt+↑/↓는 그대로) */
        const picks = selected(), item = picks.length === 1 && ctx.state.model.byUid.get(picks[0]);
        if (!item || HT.itemKindOf(item) !== 'period' || item._row == null) return;
        e.preventDefault(); e.stopImmediatePropagation();
        const site = rowSite(ctx, picks[0]);
        if (!site.ok) { HT.toast(site.reason); return; }
        const k = site.blocks.indexOf(site.R) + (e.key === 'ArrowUp' ? -1 : 1);
        if (k < 0 || k >= site.blocks.length) { HT.toast(`«${site.g.name}» 묶음의 ${k < 0 ? '맨 위' : '맨 아래'} 줄입니다.`); return; }
        const plan = rowMove(ctx, api, site, k);
        if (plan.ok) commitRow(site, plan); else if (plan.reason) HT.toast(plan.reason);
        return;
      }
      if (!e.altKey || !['ArrowLeft', 'ArrowRight'].includes(e.key) || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable || document.querySelector('dialog[open]')) return;
      const picks = selected(); if (!picks.length) return;
      e.preventDefault(); e.stopImmediatePropagation();
      const unit = unitFor(tl.span()), amount = (e.key === 'ArrowRight' ? 1 : -1) * (e.shiftKey ? 10 : 1);
      api.transact(raw => applyItems(raw, picks, { part: 'move', amount, unit }, ctx, api).draft, `고른 항목 ${amount}${unit === 'year' ? '년' : unit === 'month' ? '개월' : '일'} 옮기기`, { snapshot: picks.length > 20 });
    }, true);
    schedule(); return { refresh: schedule };
  }

  /* ---------- 줄 위아래 옮기기 (0.1.1 · 감독 2026-10-26 "민족이랑 트랙 같으면 세로 중심으로 자유롭게 이동" · 감독 고름: 끌면 남북 값을 고침) ----------
   * 고른 나라 하나를 Alt+끌기로 세로로 더 크게 끌거나(처음 6px에서 가름 — 가로가 크면 지금처럼 날짜 옮기기) Alt+↑/↓로, 같은 트랙 · 같은 민족 묶음 안에서만 줄을 옮깁니다.
   * 가로(시간)는 움직이지 않습니다. 놓은 자리에 맞게 줄 머리 나라의 남북 위치(northSouth)를 적고 그 민족의 배열 기준(rowOrder)을 '북 → 남'으로 둡니다 —
   * 배치 규칙(js/timeline.js · 내보내기 · 엔진 거울)은 그대로이고 자료 값만 바꿉니다(DLC-형식.md '배열 기준').
   *   값: 바라는 차례에서 지금 값이 이미 맞는 줄은 그대로 두고(가장 긴 내림 차례 — 끈 줄은 가장 나중에 지킴), 나머지만 앞뒤 값 사이의 쉬운 수로.
   *       묶음의 가장 북쪽 값은 될 수 있으면 그대로(위 민족 안에서 묶음 자리가 바뀌지 않게) — 안 되면 묶음 안 줄을 모두 그 값부터 차례대로 다시 매김.
   *   기준이 '시작 연도'였으면: 지금 차례가 그대로 남게 값을 채운 뒤 끈 줄만 옮김 — 그 민족의 다른 트랙 묶음도 차례대로 채우고,
   *       기준을 물려받던 하위 민족에는 '시작 연도'를 적어 안 차례를 지킴.
   *   남의 팩 민족: 형식의 '같은 id의 민족' 규칙대로 내 DLC에 같은 id 민족 줄(배열 기준만)을 적음 — 앞 팩이 기준을 이미 적어 두었으면 막고 알림.
   *       남의 나라 값은 덮어쓰기(set.northSouth) · 잠긴 팩의 나라는 고치지 않음.
   *   적기 전에 바뀐 값으로 차례를 다시 셈해(order — js/timeline.js visit와 같은 정렬) 끈 줄만 옮겨지고 다른 줄 · 위 민족 안 묶음 자리가 그대로인지 보고, 아니면 놓지 않고 까닭을 알림. */
  const bandStartOf = p => (p.startRange ? p.startRange[0] : p.start);
  const rowNameOf = b => (b.kind === 'row' ? b.head.name : b.kind === 'group' ? b.g.name : '줄');
  /** 민족 묶음 하나(tr.groups의 칸 — 대범위 가지는 뺌) → 셈용 마디 { key, name, depth, first, end, g } · 뿌리는 key '' · depth -1 */
  const nodeOfGroup = (tr, g) => (g ? { key: g.key, name: g.name, depth: g.depth, first: g.first, end: g.first + g.count, g } : { key: '', name: '', depth: -1, first: 0, end: (tr.rowPeriods || []).length, g: null });
  /** 마디 안의 덩이(지금 화면 차례): 하위 민족 묶음('group') · 제 줄('row' — 머리 나라) · 그 밖(소속 줄 · 본국 아래 대범위 가지는 앞 덩이에 붙음) */
  function blocksOf(tr, node) {
    const groups = (tr.groups || []).filter(g => !g.scope), scopes = (tr.groups || []).filter(g => g.scope);
    const inScope = r => scopes.some(s => r >= s.first && r < s.first + s.count);
    const kids = groups.filter(c => c.depth === node.depth + 1 && c.first >= node.first && c.first < node.end);
    const out = [];
    for (let r = node.first; r < node.end; ) {
      const c = kids.find(k => k.first === r);
      if (c && c.count > 0) {
        out.push({ kind: 'group', g: c, key: c.key, first: r, end: r + c.count, start: groupStart(tr, c.key) });
        r += c.count;
        continue;
      }
      const head = (tr.rowPeriods[r] || [])[0];
      const direct = !!head && !tr.memberRows.has(r) && !tr.foldedRows.has(r) && !inScope(r) && (head.peopleId || '') === node.key;
      if (direct || !out.length) out.push({ kind: direct ? 'row' : 'other', r, head: direct ? head : null, first: r, end: r + 1, start: head ? bandStartOf(head) : 0 });
      else out[out.length - 1].end = r + 1;
      r++;
    }
    out.forEach((b, i) => (b.idx = i));
    return out;
  }
  /** 묶음의 시작 해 = 그 민족(과 하위 민족)에 든 그 트랙 나라 가운데 가장 이른 것 (js/timeline.js startOf — 바탕 문화 · 기관은 빼고, 숨긴 것도 셈) */
  function groupStart(tr, key) {
    let s = Infinity;
    for (const p of tr.periods || []) {
      if (p._under || p._overlay) continue;
      const hit = key === '__culture' ? p.polityKind === 'culture' && !(p.peoplePath || []).length : (p.peoplePath || []).some(pe => pe && pe.id === key);
      if (hit) s = Math.min(s, bandStartOf(p));
    }
    return s;
  }
  /** 덩이의 남북 값 (vals = 바꿀 값 Map(머리 나라 → 값)) — 줄은 머리 나라의 값, 묶음은 그 안 줄 값 가운데 가장 북쪽 (js/timeline.js mark1). 접힌 묶음은 그 안의 줄 머리(같은 트랙의 앞 나라가 없는 나라)로 */
  function valueOf(tr, b, vals) {
    if (b.kind === 'row') return vals && vals.has(b.head) ? vals.get(b.head) : HT.northOf(b.head);
    if (b.kind !== 'group') return null;
    let v = null;
    const up = x => { if (x != null && (v == null || x > v)) v = x; };
    if (b.g.folded) {
      for (const p of tr.rowPeriods[b.first] || []) if (!p._member && !(p.predecessors || []).some(e => e.from && e.from.track === p.track)) up(vals && vals.has(p) ? vals.get(p) : HT.northOf(p));
    } else for (const c of blocksOf(tr, nodeOfGroup(tr, b.g))) up(valueOf(tr, c, vals));
    return v;
  }
  /** 마디 안 차례 셈 — js/timeline.js visit와 같은 정렬: 시작 해(같으면 묶음 먼저 · 지금 차례) → '북 → 남'이면 값 큰 것이 위(값이 없는 것은 뒤 · 같으면 앞 차례 그대로) */
  function order(blocks, val, rule) {
    const base = blocks.slice().sort((a, b) => a.start - b.start || (a.kind === 'group' ? 0 : 1) - (b.kind === 'group' ? 0 : 1) || a.idx - b.idx);
    if (rule !== 'northSouth') return base;
    return base.map((b, i) => [b, i, val(b)]).sort((x, y) => (x[2] == null) - (y[2] == null) || (x[2] != null && y[2] != null ? y[2] - x[2] : 0) || x[1] - y[1]).map(x => x[0]);
  }
  const sameOrder = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  /** 바꿀 배열 기준(over)을 얹은 민족의 기준 — HT.rowOrderOf와 같은 물려받기 */
  function ruleOf(model, key, over) {
    for (let pe = model.peopleMap.get(key), k = 0; pe && k < 64; pe = pe.parentId ? model.peopleMap.get(pe.parentId) : null, k++) {
      const r = over.get(pe.id) || pe.rowOrder;
      if (r) return r;
    }
    return 'start';
  }
  /** k개의 값 — hi(incl이면 그 값도) 아래 · lo 위로 엄격히 내려가는 쉬운 수(소수 자리가 가장 적은 것). 끝이 없으면 1씩, 끝이 없는 쪽은 -90 ~ 90 안에서 */
  function spread(hi, incl, lo, k) {
    if (!k) return [];
    let H = Number.isFinite(hi) ? hi : null, L = Number.isFinite(lo) ? lo : null;
    if (H == null && L == null) { H = k; incl = true; }
    if (H == null) { H = Math.max(L + 1e-6, Math.min(90, L + k)); incl = true; }
    if (L == null) { L = H - k - (incl ? 0 : 1); if (L < -90 && H > -90) L = -90; }
    const step = (H - L) / (k + (incl ? 0 : 1));
    const raw = Array.from({ length: k }, (_, i) => H - step * (i + (incl ? 0 : 1)));
    for (let d = 0; d <= 8; d++) {
      const f = 10 ** d, r = raw.map(v => Math.round(v * f) / f);
      if (r.every((v, i) => (i ? v < r[i - 1] : incl ? v <= H : v < H) && v > L)) return r;
    }
    return raw;
  }
  /** 마디 하나의 값 맞추기: D(바라는 차례)가 '북 → 남' 정렬로 나오게 고칠 수 있는 줄(free)의 값 → Map(머리 나라 → 값) · 못 하면 null.
      keep = 지금 값이 맞는 줄은 그대로 둠(false면 고칠 수 있는 줄을 모두 다시 매김) · cap = 묶음의 가장 북쪽 값을 넘지 않음(맨 위가 그 값) */
  function solve(tr, D, R, free, keep, cap) {
    const V = D.map(b => valueOf(tr, b)), F = D.map(b => !free(b));
    let tail = D.findIndex((b, i) => F[i] && V[i] == null); // 값이 없고 고칠 수도 없는 덩이부터는 늘 아래 — 그대로 두고 셈으로만 판정
    if (tail < 0) tail = D.length;
    const M = V.reduce((m, v) => (v != null && (m == null || v > m) ? v : m), null);
    const cand = i => V[i] != null && (F[i] || keep);
    const wt = i => (F[i] ? 1e6 : D[i] === R ? 0.5 : 1);
    const fixedIn = (a, b) => { for (let t = a; t < b; t++) if (F[t]) return true; return false; };
    const freeIn = (a, b) => { for (let t = a; t < b; t++) if (!F[t]) return true; return false; };
    const pair = (j, i) => !fixedIn(j + 1, i) && (V[j] > V[i] || (V[j] === V[i] && F[j] && F[i] && !freeIn(j + 1, i)));
    const dp = [], from = [];
    for (let i = 0; i < tail; i++) {
      dp[i] = -Infinity;
      if (!cand(i)) continue;
      if (!fixedIn(0, i) && (!cap || M == null || i === 0 || V[i] < M)) { dp[i] = wt(i); from[i] = -1; }
      for (let j = 0; j < i; j++) if (dp[j] > -Infinity && pair(j, i) && dp[j] + wt(i) > dp[i]) { dp[i] = dp[j] + wt(i); from[i] = j; }
    }
    let best = fixedIn(0, tail) ? -Infinity : 0, end = -1;
    for (let i = 0; i < tail; i++) if (dp[i] > best && !fixedIn(i + 1, tail)) { best = dp[i]; end = i; }
    if (best === -Infinity) return null;
    const kept = new Set();
    for (let i = end; i >= 0; i = from[i]) kept.add(i);
    const out = new Map();
    const first = [...kept].sort((a, b) => a - b)[0];
    let hi = Infinity, incl = false, pend = [];
    if (M != null && (cap || first == null || M > V[first])) { hi = M; incl = true; }
    const flush = lo => { spread(hi, incl, lo, pend.length).forEach((v, t) => out.set(pend[t].head, v)); pend = []; };
    for (let i = 0; i < tail; i++) {
      if (kept.has(i)) { flush(V[i]); hi = V[i]; incl = false; }
      else if (!F[i]) pend.push(D[i]);
    }
    flush(-Infinity);
    for (const [h, v] of out) if (v === HT.northOf(h)) out.delete(h);
    return sameOrder(order(D, b => valueOf(tr, b, out), 'northSouth'), D) ? out : null;
  }
  /** 위 민족 묶음 차례가 그대로인지 — 마디의 가장 북쪽 값이 바뀌면 위로 올라가며 '북 → 남'인 마디마다 다시 셈. 바뀌면 그 위 민족 이름 */
  function checkUp(tr, node, vals, model, over) {
    const groups = (tr.groups || []).filter(g => !g.scope);
    const top = (n, v) => blocksOf(tr, n).reduce((m, b) => { const x = valueOf(tr, b, v); return x != null && (m == null || x > m) ? x : m; }, null);
    let cur = node, was = top(node, null), now = top(node, vals);
    while (was !== now && cur.depth > 0) {
      const pg = groups.find(g => g.depth === cur.depth - 1 && g.first <= cur.first && cur.first < g.first + g.count);
      if (!pg) return '';
      const parent = nodeOfGroup(tr, pg), blocks = blocksOf(tr, parent);
      if (ruleOf(model, parent.key, over) === 'northSouth' && !sameOrder(order(blocks, b => valueOf(tr, b, vals), 'northSouth'), blocks)) return parent.name;
      was = top(parent, null);
      now = top(parent, vals);
      cur = parent;
    }
    return '';
  }
  /** 고른 나라의 줄이 옮길 수 있는 줄인지 · 그 묶음 → { ok, reason, tr, g, node, blocks, R } */
  function rowSite(ctx, uid) {
    const tl = ctx.timeline, model = ctx.state.model, p = model && model.byUid.get(uid);
    const no = reason => ({ ok: false, reason });
    if (!p || HT.itemKindOf(p) !== 'period' || p._row == null || p._under || p._overlay) return no('연표의 나라 줄만 위아래로 옮길 수 있습니다.');
    const tr = (tl.tracks || []).find(t => t.id === p.track);
    if (!tr || !tr.rowPeriods || tr.folded) return no('접힌 트랙의 줄은 옮길 수 없습니다.');
    if (tr.board) return no('집합 보기에서는 줄을 옮길 수 없습니다.');
    const r = p._row;
    if (tr.foldedRows.has(r)) return no('접힌 민족 줄은 옮길 수 없습니다 — 펼친 뒤 옮겨 주세요.');
    if (tr.memberRows.has(r)) return no('소속 줄은 위 나라를 따라 놓여 옮길 수 없습니다.');
    if ((tr.groups || []).some(s => s.scope && r >= s.first && r < s.first + s.count)) return no('대범위 가지 안의 줄은 옮길 수 없습니다.');
    const head = (tr.rowPeriods[r] || [])[0];
    if (!head || !head.peopleId) return no('민족이 없는 줄은 옮길 수 없습니다 — 트랙 맨 위 단의 차례는 시작 해로 정해집니다.');
    const g = (tr.groups || []).find(x => !x.scope && x.key === head.peopleId && r >= x.first && r < x.first + x.count);
    if (!g) return no('이 줄의 민족 묶음을 찾지 못했습니다.');
    const node = nodeOfGroup(tr, g), blocks = blocksOf(tr, node), R = blocks.find(b => b.kind === 'row' && b.r === r);
    if (!R) return no('이 줄의 민족 묶음을 찾지 못했습니다.');
    if (blocks.length < 2) return no(`«${g.name}» 묶음에 옮길 다른 자리가 없습니다.`);
    return { ok: true, tr, g, node, blocks, R };
  }
  /** 옮기기 계획 — k = 끈 줄을 뺀 차례에서 놓을 자리(0 = 맨 위) → { ok, same, reason, values: Map(나라 → 값), peoples: [{ id, name, rowOrder }], switched } */
  function rowMove(ctx, api, site, k) {
    const model = ctx.state.model, draft = api.draft, no = reason => ({ ok: false, reason });
    const D = site.blocks.filter(b => b !== site.R);
    D.splice(Math.max(0, Math.min(D.length, k)), 0, site.R);
    if (sameOrder(D, site.blocks)) return { ok: false, same: true, reason: '' };
    const key = site.g.key, pe = model.peopleMap.get(key);
    if (!pe) return no('이 줄의 민족을 찾지 못했습니다.');
    const over = new Map(), peoples = [];
    const own = p => HT.draft.isOwnUid(draft, p.uid);
    const free = b => b.kind === 'row' && HT.itemKindOf(b.head) === 'period' && (own(b.head) ? !!HT.draft.findOwn(draft, b.head.uid.slice(draft.id.length + 1)) : !api.isLocked(b.head));
    const switched = ruleOf(model, key, over) !== 'northSouth';
    if (switched) {
      /* 기준을 먼저 적은 팩이 이깁니다(켠 차례 — 작업본이 맨 뒤): 앞 팩이 적어 두었으면 이 DLC로는 바꿀 수 없음 */
      const refs = new Set((api.refRows ? api.refRows() : []).filter(r => !r.missing).map(r => r.id));
      const packs = (ctx.state.packs || []).filter(pk => pk && pk.id !== draft.id && refs.has(pk.id));
      const first = packs.find(pk => (pk.peoples || []).some(x => x && x.id === key && HT.readRowOrder(x.rowOrder)));
      if (first) return no(`«${pe.name}»의 배열 기준은 불러온 팩 «${first.name}»이 '${HT.rowOrderName(HT.readRowOrder((first.peoples || []).find(x => x && x.id === key).rowOrder))}'(으)로 정해 두어 이 DLC에서 바꿀 수 없습니다.`);
      over.set(key, 'northSouth');
      peoples.push({ id: key, name: pe.name, rowOrder: 'northSouth' });
      /* 기준을 물려받던 하위 민족은 '시작 연도'로 끊어 안 차례를 그대로 (나라가 든 것만) */
      for (const cid of pe.children || []) {
        const c = model.peopleMap.get(cid);
        if (!c || c.rowOrder || !model.periods.some(p => (p.peoplePath || []).some(x => x && x.id === cid))) continue;
        over.set(cid, 'start');
        peoples.push({ id: cid, name: c.name, rowOrder: 'start' });
      }
    }
    const values = new Map();
    const fail = (tr, list) => {
      const locked = list.find(b => b.kind === 'row' && !free(b) && HT.itemKindOf(b.head) === 'period' && api.isLocked(b.head));
      if (locked) return `잠긴 팩의 나라 «${locked.head.name}»의 남북 위치를 고쳐야 해서 옮길 수 없습니다 — 불러온 팩의 자물쇠를 풀어 주세요.`;
      const none = list.find(b => !free(b) && valueOf(tr, b) == null);
      if (none) return `«${rowNameOf(none)}»에는 남북 위치를 적을 수 없어 늘 아래에 놓입니다 — 그 아래로는 옮길 수 없습니다.`;
      return '이 자리로는 옮길 수 없습니다 — 남북 위치가 같은 묶음 사이입니다.';
    };
    const place = (tr, node, list, R) => {
      /* 고르는 차례: 지금 값을 두고 가장 북쪽 값 안에서 → 지금 값을 두고(넘어도) → 모두 다시 매겨 가장 북쪽 값 안에서 → 모두 다시(넘어도). 위 민족 안 자리가 그대로인 첫 답 */
      let got = null, blocked = '';
      for (const [keep, cap] of [[true, true], [true, false], [false, true], [false, false]]) {
        const v = solve(tr, list, R, free, keep, cap);
        if (!v) continue;
        const up = checkUp(tr, node, v, model, over);
        if (!up) { got = v; break; }
        blocked = blocked || up;
      }
      if (!got) return no(blocked ? `이 자리로 옮기면 위 민족 «${blocked}» 안에서 «${node.name}» 묶음의 자리가 바뀌어 옮기지 않았습니다.` : fail(tr, list));
      for (const [h, v] of got) values.set(h, v);
      return null;
    };
    const bad = place(site.tr, site.node, D, site.R);
    if (bad) return bad;
    if (switched) {
      /* 같은 민족의 다른 트랙 묶음: 지금 차례가 그대로 남게 값을 채움 (접혀 차례를 볼 수 없으면 막음) */
      for (const tr of ctx.timeline.tracks || []) {
        if (tr === site.tr || !tr.rowPeriods || tr.board) continue;
        const has = (tr.periods || []).some(p => !p._under && !p._overlay && (p.peoplePath || []).some(x => x && x.id === key));
        if (!has) continue;
        const g = (tr.groups || []).find(x => !x.scope && x.key === key);
        if (!g || g.folded || tr.folded) return no(`«${tr.name}» 트랙의 «${pe.name}» 묶음이 접혀 있어 그 차례를 지킬 수 없습니다 — 펼친 뒤 다시 옮겨 주세요.`);
        const node = nodeOfGroup(tr, g), list = blocksOf(tr, node);
        if (list.length < 2) continue;
        const why = place(tr, node, list, null);
        if (why) return no(`«${tr.name}» 트랙의 «${pe.name}» 묶음 차례를 지킬 수 없습니다 — ${why.reason}`);
      }
    }
    return { ok: true, values, peoples, switched, value: values.has(site.R.head) ? values.get(site.R.head) : HT.northOf(site.R.head) };
  }
  /** 계획을 작업본에 — 제 나라는 northSouth를 바로, 남의 나라는 덮어쓰기(set.northSouth), 민족은 같은 id 줄의 배열 기준 */
  function applyRowMove(draft, plan, api) {
    const next = clone(draft);
    for (const [p, v] of plan.values) {
      if (HT.draft.isOwnUid(draft, p.uid)) {
        const hit = HT.draft.findOwn(next, p.uid.slice(draft.id.length + 1));
        if (!hit) throw Error(`«${p.name}»을(를) 작업본에서 찾지 못했습니다.`);
        hit.item.northSouth = v;
      } else {
        const raw = api.rawOf(p), item = clone(raw);
        item.northSouth = v;
        HT.makerGrid.patchItem(next, api.baseModel().byUid.get(p.uid) || p, raw, item);
      }
    }
    for (const w of plan.peoples) {
      next.peoples = Array.isArray(next.peoples) ? next.peoples : [];
      const hit = next.peoples.find(x => x && x.id === w.id);
      if (hit) hit.rowOrder = w.rowOrder;
      else next.peoples.push({ id: w.id, name: w.name, rowOrder: w.rowOrder });
    }
    return next;
  }
  const rowMoveName = (site, plan) => `«${site.R.head.name}» 줄 위아래 옮기기${plan.switched ? ` · «${site.g.name}» 북 → 남` : ''}`;

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
  HT.makerDrag = { unitFor, snap, moveDate, shiftItem, difference, changeItem, applyItems, mount, slot, rowSite, rowMove, applyRowMove, spread };
})();

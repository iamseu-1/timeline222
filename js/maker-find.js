/* DLC 메이커 — 명령 찾기·내 자료의 찾아 바꾸기·빈 칸 점검. */
(function () {
  'use strict';
  const HT = window.HT, clone = x => JSON.parse(JSON.stringify(x)), arr = x => Array.isArray(x) ? x : [];
  const fields = { name: '이름·제목', description: '설명', note: '메모', documents: '문서', source: '출처', cells: '칸 이름', all: '모두' };
  const allowed = new Set(['name', 'title', 'description', 'note', 'source', 'temple', 'given', 'as', 'city', 'label']);
  function expression(opts) {
    if (!opts.query) return null;
    if (opts.query.length > 200) throw Error('찾을 글은 200자까지 적어 주세요.');
    let pattern = opts.regex ? opts.query : opts.query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (opts.regex && /\([^)]*[+*][^)]*\)[+*{]/.test(pattern)) throw Error('겹친 반복은 사용할 수 없습니다. 반복을 줄여 주세요.');
    if (opts.word) pattern = `(?<![\\p{L}\\p{N}_])(?:${pattern})(?![\\p{L}\\p{N}_])`;
    try { return new RegExp(pattern, opts.case ? 'gu' : 'giu'); } catch (_) { throw Error('정규식의 괄호와 기호를 확인하세요.'); }
  }
  function entries(draft, scope = 'all') {
    const out = [];
    for (const list of Object.keys(HT.makerGrid.words).filter(k => k !== 'patches')) for (const [index, item] of arr(draft[list]).entries()) {
      const uid = draft.id + '/' + item.id, label = item.name || item.title || item.id;
      function walk(o, path, depth) {
        if (Array.isArray(o)) { o.forEach((x, i) => {
          if (Array.isArray(x) && typeof x[0] === 'string' && (scope === 'all' || scope === 'cells')) out.push({ path: [...path, i, 0], text: x[0], uid, list, index, label, field: '칸 이름' });
          else walk(x, [...path, i], depth + 1);
        }); return; }
        if (!o || typeof o !== 'object') return;
        for (const [key, v] of Object.entries(o)) {
          const matches = scope === 'all' || scope === 'name' && depth === 0 && ['name', 'title'].includes(key) || scope === 'cells' && depth > 0 && ['name', 'title', 'city', 'as', 'temple', 'given'].includes(key) || scope === key;
          if (typeof v === 'string' && allowed.has(key) && matches) out.push({ path: [...path, key], text: v, uid, list, index, label, key, root: depth === 0, field: depth ? '칸 ' + (fields[key] || '이름') : fields[key] || '이름' });
          else if (v && typeof v === 'object' && !['partOf', 'succeeds', 'successors', 'host', 'members', 'polities', 'service', 'treaty'].includes(key)) walk(v, [...path, key], depth + 1);
        }
      }
      walk(item, [list, index], 0);
    }
    if (scope === 'all' || scope === 'documents') for (const [key, text] of Object.entries(draft.documents || {})) {
      if (typeof text === 'string') out.push({ path: ['documents', key], text, uid: key.includes('/') ? key.split('//')[0] : draft.id + '/' + key.split('//')[0], doc: key, label: key, field: '문서' });
    }
    return out;
  }
  function find(draft, opts) {
    const re = expression(opts); if (!re) return [];
    const out = [];
    for (const e of entries(draft, opts.scope)) {
      re.lastIndex = 0;
      if (!re.test(e.text)) continue;
      re.lastIndex = 0;
      const after = e.text.replace(re, opts.regex ? String(opts.replacement ?? '') : () => String(opts.replacement ?? ''));
      out.push({ ...e, after });
    }
    return out;
  }
  function renameReferences(draft, list, before, after, packs = []) {
    if (!before.name || !after.name || before.name === after.name) return 0;
    const table = HT.makerKit.BASE_TABLES[list];
    if (table?.cols) return HT.makerKit.shadowOf(packs.filter(p => p.id !== draft.id), list, before.id) ? 0 : HT.makerKit.renameRefs(draft, table, 'name', before.name, after.name);
    if (list === 'epochs') return HT.makerKit.renameEpochRefs(draft, before, before.name, after.name);
    if (list === 'groups') return HT.makerKit.renameGroupRefs(draft, before, before.name, after.name);
    if (list !== 'periods') return 0;
    let n = 0;
    /* 같은 이름의 다른 나라(이 DLC 안) — 트랙 없이 이름만 적은 형식 3의 참조(다른 트랙으로도 찾아 가는 것)는 같은 이름의 나라가 없을 때만 따라 고칩니다 */
    const twins = arr(draft.periods).some(p => p && p.id !== before.id && p.name === before.name);
    /** 이름만 적은 참조가 이 나라를 가리키는지: 적은 쪽의 트랙이 같거나(옛 길) · loose면 같은 이름의 다른 나라가 없을 때도(형식 3 — 단체의 있던 나라 · 사람 참조 · 판 · 지도처럼 다른 트랙으로도 찾는 참조) */
    const plainHit = (track, loose) => !before.track || track === before.track || (loose && !twins);
    const map = (v, track, loose = false) => {
      if (typeof v === 'string') {
        if (v === `${before.track}:${before.name}`) { n++; return `${before.track}:${after.name}`; }
        if (plainHit(track, loose) && v === before.name) { n++; return after.name; }
        return v;
      }
      if (Array.isArray(v)) return v.map(x => map(x, track, loose));
      if (v && typeof v === 'object') {
        const ownTrack = v.track || track;
        for (const key of ['polity', 'name']) if (typeof v[key] === 'string') v[key] = map(v[key], ownTrack, loose && !v.track);
      }
      return v;
    };
    /** 사람 참조(형식 3 — 지도자 · 내각 칸 "나라:지도자@해" · { track?, polity, leader, start? }): 나라 자리만 바꿉니다(인물 이름 · id 글은 그대로) */
    const person = (v, track) => {
      if (typeof v === 'string') {
        const m = /^(\s*)([^:@]+?)(\s*:[\s\S]*)$/.exec(v);
        if (!m || m[2] !== before.name || !plainHit(track, true)) return v;
        n++;
        return m[1] + after.name + m[3];
      }
      if (v && typeof v === 'object' && !Array.isArray(v) && typeof v.polity === 'string' && v.polity === before.name && (v.track ? v.track === before.track : plainHit(track, true))) {
        v.polity = after.name;
        n++;
      }
      return v;
    };
    const kin = (rows, track) => { for (const q of arr(rows)) if (q && typeof q === 'object' && !Array.isArray(q) && q.who != null) q.who = person(q.who, track); };
    for (const key of HT.makerKit.itemLists()) for (const x of arr(draft[key])) {
      const track = x.track || '';
      for (const k of ['partOf', 'polity', 'polities', 'members', 'host', 'service', 'tracks', 'perspectives']) if (x[k] != null) x[k] = map(x[k], track);
      for (const k of ['succeeds', 'successors']) if (x[k] != null) {
        if (Array.isArray(x[k])) x[k] = x[k].map(v => { if (Array.isArray(v)) { v[0] = map(v[0], track); return v; } return map(v, track); });
        else x[k] = map(x[k], track);
      }
      if (x.treaty?.parties) x.treaty.parties = map(x.treaty.parties, track);
      /* 형식 3 — 단체의 있던 나라 · 구성원(사람 참조), 제도 칸의 온 곳(온 곳 객체의 name은 칸 이름이라 나라 자리만), 지도자 · 내각 칸 · 인물의 사람 참조 */
      if (key === 'groups') {
        if (x.within != null) x.within = map(x.within, track, true);
        if (Array.isArray(x.people)) x.people = x.people.map(v => person(v, track));
      }
      if (key === 'institutions') for (const sp of arr(x.spans)) {
        if (!sp || typeof sp !== 'object' || Array.isArray(sp) || sp.from == null) continue;
        if (typeof sp.from === 'string') sp.from = map(sp.from, track, true);
        else if (typeof sp.from === 'object' && typeof sp.from.polity === 'string') sp.from.polity = map(sp.from.polity, sp.from.track || track, !sp.from.track);
      }
      if (key === 'periods') for (const k of ['leaders', 'reigns', 'cabinets']) for (const c of arr(x[k])) {
        if (!c || typeof c !== 'object' || Array.isArray(c)) continue;
        if (c.person != null) c.person = person(c.person, track);
        if (c.accession && typeof c.accession === 'object' && c.accession.from != null) c.accession.from = person(c.accession.from, track);
        kin(c.parents, track);
        kin(c.spouses, track);
      }
      if (key === 'figures') { kin(x.parents, track); kin(x.spouses, track); }
    }
    /* 모아 보기 판의 구성 나라 · 지도 장면의 구역 주인(형식 3 F3 — 항목 목록 밖, 트랙이 없는 자리) */
    for (const v of arr(draft.views)) if (v && v.members != null) v.members = map(v.members, '', true);
    for (const m of arr(draft.maps)) for (const f of arr(m && m.frames)) {
      if (!f || !f.owners || typeof f.owners !== 'object' || Array.isArray(f.owners)) continue;
      for (const rid of Object.keys(f.owners)) if (f.owners[rid] != null) f.owners[rid] = map(f.owners[rid], '', true);
    }
    return n;
  }
  function replace(draft, opts, onlyPath = null, packs = []) {
    const next = clone(draft), matches = find(next, opts).filter(x => !onlyPath || JSON.stringify(x.path) === JSON.stringify(onlyPath)), renames = []; let changed = 0, refs = 0;
    for (const row of matches) {
      if (row.text === row.after) continue;
      if (row.root && ['name', 'title'].includes(row.key) && !row.after.trim()) throw Error('항목의 이름·제목을 비우는 바꾸기는 적용하지 않습니다.');
      let target = next; for (const key of row.path.slice(0, -1)) target = target[key];
      if (row.root && row.key === 'name') renames.push({ list: row.list, before: clone(target), after: { ...clone(target), name: row.after } });
      target[row.path.at(-1)] = row.after; changed++;
    }
    if (opts.refs !== false) for (const r of renames) {
      // 각 옛 이름은 변경 전 참조에서 찾습니다. 새 이름이 다른 옛 이름과 같아도 두 번 바꾸지 않습니다.
      const original = clone(draft), mapped = clone(draft);
      refs += renameReferences(mapped, r.list, r.before, r.after, packs);
      const transfer = (a, b, target) => {
        for (const key of Object.keys(b || {})) {
          if (b[key] && typeof b[key] === 'object' && a?.[key] && typeof a[key] === 'object' && target?.[key]) transfer(a[key], b[key], target[key]);
          else if (JSON.stringify(a?.[key]) !== JSON.stringify(b[key])) target[key] = b[key];
        }
      };
      transfer(original, mapped, next);
    }
    for (const before of arr(draft.periods)) { const after = arr(next.periods).find(p => p.id === before.id); if (after) HT.makerGrid.moveCellDocuments(next, draft.id + '/' + before.id, before, after); }
    return { draft: next, changed, refs };
  }
  const blankKinds = { description: '설명 없음', document: '문서 없음', source: '출처 없는 사건', leaders: '지도자 없는 시대', date: '연대 미정', color: '자동 색 시대', order: '트랙 순서 없음' };
  function blanks(draft) {
    const result = Object.fromEntries(Object.keys(blankKinds).map(k => [k, []]));
    const add = (k, list, x) => result[k].push({ uid: draft.id + '/' + x.id, list, name: x.name || x.title || x.id });
    for (const list of HT.makerKit.itemLists()) for (const x of arr(draft[list])) {
      if (!String(x.description || '').trim()) add('description', list, x);
      if (!(draft.documents?.[x.id] || draft.documents?.[draft.id + '/' + x.id])) add('document', list, x);
      if (list === 'events' && !String(x.source || '').trim()) add('source', list, x);
      if (list === 'periods' && !arr(x.leaders || x.reigns).length) add('leaders', list, x);
      if (x.startUnknown || x.endUnknown || HT.isUnknownText(x.start) || HT.isUnknownText(x.end) || x.start == null && x.birth == null || x.end == null && !x.ongoing && list === 'periods') add('date', list, x);
      if (list === 'periods' && !x.color) add('color', list, x);
    }
    for (const x of arr(draft.tracks)) if (x.order == null) add('order', 'tracks', x);
    return result;
  }
  function mount(ctx, api) {
    const esc = ctx.esc; let query = '', replacement = '', scope = 'all', sensitive = false, word = false, regex = false, refs = true;
    const disabled = new Set(arr(api.ui.findHidden)), blankLimits = {};
    const opts = () => ({ query, replacement, scope, case: sensitive, word, regex, refs });
    let panel = null;
    function openPalette() {
      if (document.querySelector('dialog[open]')) return;
      const box = document.createElement('dialog'); box.className = 'dlc-dialog mk-palette';
      box.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>명령·항목 찾기</h2><button class="icon-btn" data-close aria-label="닫기">✕</button></div><div class="dlg-body"><label>찾을 글<input data-palette-query aria-label="명령·항목·문서 찾기" autocomplete="off"></label><div data-palette-results role="listbox" aria-label="찾은 결과"></div></div></div>`;
      let results = [], chosen = 0, limits = {};
      const input = box.querySelector('input'), body = box.querySelector('[data-palette-results]');
      function paint() {
        const text = input.value.trim(), q = text.toLocaleLowerCase(); results = []; chosen = 0;
        const groups = [], commands = api.commands().filter(c => !c.sep && !c.soon && (!q || c.label.toLocaleLowerCase().includes(q) || (c.key || '').toLowerCase().includes(q))).map(c => ({ label: c.label, detail: c.key || '명령', run: c.run || (() => api.run(c.id)) }));
        groups.push(['명령', commands]);
        if (q) {
          const goDate = t => { api.timeline(); const span = ctx.timeline.span(); ctx.timeline.setView(t - span / 2, t + span / 2); };
          const d = HT.readDate(text), ganji = (text.match(/^([갑을병정무기경신임계][자축인묘진사오미신유술해])\s*년?$/) || [])[1];
          if (d && Number.isFinite(d.t)) groups.unshift(['날짜', [{ label: HT.formatDate(d.t, d.at) + '로 가기', detail: '', run: () => goDate(d.t) }]]);
          else if (ganji) {
            const center = (ctx.timeline.view.start + ctx.timeline.view.end) / 2, years = [];
            const min = Math.floor(ctx.timeline.extent.min) - 60, max = ctx.timeline.extent.max + 60;
            let first = null;
            for (let y = min; y <= min + 61; y++) if (y && HT.ganji(y) === ganji) { first = HT.cal.toAstro(y); break; }
            if (first != null) for (let a = first; HT.cal.fromAstro(a) <= max; a += 60) years.push(HT.cal.fromAstro(a));
            years.sort((a, b) => Math.abs(a - center) - Math.abs(b - center));
            groups.unshift(['날짜', years.map(y => ({ label: HT.formatYear(y) + '로 가기', detail: ganji + '년', run: () => goDate(y) }))]);
          }
          const own = [], other = [];
          for (const x of ctx.state.model.byUid.values()) if ([x.name, x.title, x.id, x.start, x.end, x.description].some(v => String(v || '').toLocaleLowerCase().includes(q))) {
            const row = { label: x.name || x.title || x.id, detail: x.packId === api.draft?.id ? '내 항목' : '불러온 팩', run: () => { api.timeline(); api.openItem(x.uid); ctx.timeline.focusOn(x); } };
            (x.packId === api.draft?.id ? own : other).push(row);
          }
          if (api.draft) for (const list of HT.makerKit.itemLists()) for (const x of arr(api.draft[list])) {
            const uid = api.draft.id + '/' + x.id;
            if (!ctx.state.model.byUid.has(uid) && [x.name, x.title, x.id, x.description].some(v => String(v || '').toLocaleLowerCase().includes(q))) own.push({ label: x.name || x.title || x.id, detail: '확인할 항목', run: () => api.openItem(uid) });
          }
          groups.push(['내 항목', own], ['불러온 팩 항목', other]);
          if (api.draft) {
            const base = [];
            for (const list of ['tracks', 'categories', 'peoples', 'rankDefs', 'houses']) for (const x of arr(api.draft[list])) if ([x.id, x.name].some(v => String(v || '').toLocaleLowerCase().includes(q))) base.push({ label: x.name || x.id, detail: HT.makerGrid.words[list], run: () => api.table(list) });
            groups.push(['바탕 자료', base]);
            groups.push(['문서', Object.entries(api.draft.documents || {}).filter(([key, text]) => (key + ' ' + text).toLocaleLowerCase().includes(q)).map(([key]) => ({ label: key, detail: '문서', run: () => ctx.openWiki(HT.docKey.absolute(key, api.draft.id)) }))]);
          }
        }
        body.innerHTML = groups.filter(([, xs]) => xs.length).map(([name, rows]) => {
          const shown = rows.slice(0, limits[name] || 8);
          return `<section><h3>${esc(name)} <small>${rows.length}</small></h3>${shown.map(row => { const index = results.push(row) - 1; return `<button type="button" role="option" data-result="${index}" class="${index === 0 ? 'is-current' : ''}"><span>${esc(row.label)}</span><small>${esc(row.detail)}</small></button>`; }).join('')}${rows.length > shown.length ? `<button type="button" data-more="${esc(name)}">더 보기</button>` : ''}</section>`;
        }).join('') || '<p>찾은 결과가 없습니다.</p>';
      }
      const use = index => { const row = results[index]; if (!row) return; box.close(); row.run(); };
      input.oninput = () => { limits = {}; paint(); }; input.onkeydown = e => { if (e.isComposing) return; if (e.key === 'Enter') { e.preventDefault(); use(chosen); } if (['ArrowDown', 'ArrowUp'].includes(e.key)) { e.preventDefault(); chosen = Math.max(0, Math.min(results.length - 1, chosen + (e.key === 'ArrowDown' ? 1 : -1))); for (const el of body.querySelectorAll('[data-result]')) el.classList.toggle('is-current', Number(el.dataset.result) === chosen); body.querySelector(`[data-result="${chosen}"]`)?.scrollIntoView({ block: 'nearest' }); } };
      box.onclick = e => { const row = e.target.closest('[data-result]'), more = e.target.closest('[data-more]'); if (row) use(Number(row.dataset.result)); if (more) { limits[more.dataset.more] = (limits[more.dataset.more] || 8) + 40; paint(); } if (e.target.closest('[data-close]')) box.close(); };
      box.onclose = () => box.remove(); document.body.append(box); box.showModal(); paint(); input.focus();
    }
    function previewText(text) {
      const re = expression(opts()), match = re?.exec(text), start = Math.max(0, (match?.index || 0) - 32), end = Math.min(text.length, start + 110);
      if (!match) return esc(text.slice(start, end));
      const a = match.index, b = Math.min(end, a + match[0].length);
      return (start ? '…' : '') + esc(text.slice(start, a)) + '<mark>' + esc(text.slice(a, b)) + '</mark>' + esc(text.slice(b, end)) + (end < text.length ? '…' : '');
    }
    function replacePanel(host) {
      if (panel !== host || !host.querySelector('[data-find-form]')) {
        panel = host;
        host.innerHTML = `<form data-find-form class="mk-find-form"><label>찾을 글<input name="query" aria-label="찾을 글"></label><label>바꿀 글<input name="replacement" aria-label="바꿀 글"></label><label>찾을 칸<select name="scope">${Object.entries(fields).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select></label><label><input type="checkbox" name="case">대소문자 구별</label><label><input type="checkbox" name="word">낱말 단위</label><label><input type="checkbox" name="regex">정규식</label><label><input type="checkbox" name="refs" checked>이름 참조도 바꾸기</label><button class="btn btn-sm" type="submit">찾기</button><button class="btn btn-sm" type="button" data-replace-all>모두 바꾸기</button></form><p data-find-status aria-live="polite"></p><ul class="mk-find-results"></ul>`;
        const form = host.querySelector('form');
        for (const [key, val] of Object.entries(opts())) if (form.elements[key]) { if (form.elements[key].type === 'checkbox') form.elements[key].checked = val; else form.elements[key].value = val; }
        form.onsubmit = e => { e.preventDefault(); read(); paint(); };
        const read = () => { query = form.elements.query.value; replacement = form.elements.replacement.value; scope = form.elements.scope.value; sensitive = form.elements.case.checked; word = form.elements.word.checked; regex = form.elements.regex.checked; refs = form.elements.refs.checked; };
        let rows = [];
        function paint() {
          try {
            rows = api.draft ? find(api.draft, opts()) : [];
            host.querySelector('[data-find-status]').textContent = `${rows.length}곳 찾음 · 내 DLC만 고칩니다.${rows.length > 300 ? ` 첫 300곳을 표시하며, 모두 바꾸기는 ${rows.length}곳에 적용합니다.` : ''}`;
            host.querySelector('.mk-find-results').innerHTML = rows.slice(0, 300).map((r, i) => `<li><button type="button" data-find-go="${i}">${esc(r.label)} · ${esc(r.field)}</button><span>${previewText(r.text)} → <b>${esc(r.after.slice(Math.max(0, (expression(opts())?.exec(r.text)?.index || 0) - 32), Math.max(0, (expression(opts())?.exec(r.text)?.index || 0) - 32) + 110))}</b></span><button type="button" class="btn btn-sm" data-replace-one="${i}">바꾸기</button></li>`).join('');
          } catch (error) { rows = []; host.querySelector('[data-find-status]').textContent = error.message; host.querySelector('.mk-find-results').innerHTML = ''; }
        }
        host.onclick = async e => {
          const one = e.target.closest('[data-replace-one]'), all = e.target.closest('[data-replace-all]'), go = e.target.closest('[data-find-go]');
          if (go) { const r = rows[Number(go.dataset.findGo)]; if (r.doc) ctx.openWiki(HT.docKey.absolute(r.doc, api.draft.id)); else if (HT.makerKit.BASE_TABLES[r.list]?.cols) api.table(r.list); else api.openItem(r.uid); }
          if (!one && !all) return;
          read(); const only = one && rows[Number(one.dataset.replaceOne)]?.path; if (one && !only) return;
          let result;
          const ok = await api.transact(d => { result = replace(d, opts(), only, ctx.state.packs); return result.draft; }, all ? '찾은 글 모두 바꾸기' : '찾은 글 한 곳 바꾸기', { snapshot: !!all });
          paint(); if (ok) host.querySelector('[data-find-status]').textContent = `${result.changed}곳 바꿈 · 이름 참조 ${result.refs}곳도 바꿈`;
        };
        paint();
      }
    }
    function blanksPanel(host) {
      const groups = api.draft ? blanks(api.draft) : {};
      host.innerHTML = `<p>오류와 별개인 할 일 목록입니다. 필요한 묶음만 켜 두세요.</p><div class="mk-find-form">${Object.entries(blankKinds).map(([key, name]) => `<label><input type="checkbox" data-blank-kind="${key}" ${disabled.has(key) ? '' : 'checked'}>${name} ${groups[key]?.length || 0}</label>`).join('')}</div>${Object.entries(groups).filter(([k]) => !disabled.has(k)).map(([k, rows]) => `<section><h3>${blankKinds[k]} · ${rows.length}</h3><div class="mk-blank-list">${rows.slice(0, blankLimits[k] || 300).map(r => `<button type="button" data-blank-uid="${esc(r.uid)}" data-blank-list="${r.list}">${esc(r.name)}</button>`).join('')}${rows.length > (blankLimits[k] || 300) ? `<button type="button" data-blank-more="${k}">더 보기</button>` : ''}</div></section>`).join('')}`;
      host.onchange = e => { if (e.target.dataset.blankKind) { e.target.checked ? disabled.delete(e.target.dataset.blankKind) : disabled.add(e.target.dataset.blankKind); api.ui.findHidden = [...disabled]; api.remember(); blanksPanel(host); } };
      host.onclick = e => { const more = e.target.closest('[data-blank-more]'); if (more) { const k = more.dataset.blankMore; blankLimits[k] = (blankLimits[k] || 300) + 300; blanksPanel(host); } const b = e.target.closest('[data-blank-uid]'); if (b) { if (b.dataset.blankList === 'tracks') api.table('tracks'); else api.openItem(b.dataset.blankUid); } };
    }
    return { openPalette, render(host, tab) { if (tab === 'replace') replacePanel(host); else if (tab === 'blanks') { panel = null; blanksPanel(host); } else panel = null; } };
  }
  HT.makerFind = { expression, entries, find, replace, renameReferences, blankKinds, blanks, mount };
})();

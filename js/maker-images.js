/* 역사 연표 — 메이커의 문서 그림 넣기 (10건 D3 결정 8 A · 16건 15번 — docs/설계-10건/4-5-메이커-블록과-묶음.md 결정 8 · 2절 6 · DLC-형식.md '문서 그림')
 *
 * 문서 편집기 도구 줄의 '그림' 단추('표' 옆 — js/wiki.js namu.toolbarHTML({ image: true })) → 파일 고름 → 긴 변 1600px로 줄여 고치는 DLC(작업본)의
 * 그림 사전(images — 형식 3)에 담고 커서 자리에 [[파일:이름]] 한 줄을 넣습니다. 미리 보기에 바로 보입니다(js/viewer.js의 imageResolver).
 * 글 칸에 그림 파일을 끌어다 놓거나 붙여넣어도 같은 길입니다(결정 8 B를 A의 지름길로 — 터치 화면에는 끌어다 놓기가 없어 단추가 먼저).
 * 편집기 아래 그림 띠: 이 문서의 그림(작은 그림 · 이름 · 크기 · 용량 — 누르면 커서 자리에 다시 넣기) · 팩의 그림 합과 한도 막대 · '그림 모음'
 * (이 팩의 그림 모두 — 넣기 · 설명 · 대체 글 · 출처 고치기 · 쓰지 않는 그림 지우기). 그림 한 장 넣기 · 모음에서 고치기 한 번이 되돌리기 한 걸음입니다(maker.setImages).
 *
 * js/viewer.js의 문서 창이 편집기를 처음 만들 때 HT.makerImages.mount(...)를 부릅니다. 연표(index.html)에는 이 파일이 없어 단추도 띠도 없습니다.
 */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const arr = v => (Array.isArray(v) ? v : []);
  /** 넣을 때 긴 변 — 표지와 같은 줄이기(1600). 한 장 한도(HT.PACK_LIMITS.docImage)를 넘으면 더 줄여 봅니다 */
  const MAX_SIDE = 1600;
  const SMALLER = [1200, 900];
  /** 이보다 큰 원본(data URL 글자 수)은 크기가 작아도 다시 담아 줄입니다(png 사진 같은 것) */
  const REENCODE = 300000;
  const readAsDataURL = file =>
    new Promise((ok, no) => {
      const r = new FileReader();
      r.onload = () => ok(String(r.result));
      r.onerror = () => no(r.error);
      r.readAsDataURL(file);
    });
  /** data URL의 실제 바이트 수(어림) */
  const bytesOf = src => Math.max(0, Math.round(((String(src).length - String(src).indexOf(',') - 1) * 3) / 4));
  const size = n => (n >= 1048576 ? `${(n / 1048576).toFixed(1)}MB` : `${Math.max(1, Math.round(n / 1024))}KB`);
  const isImageFile = f => !!f && /^image\//.test(f.type || '');
  /** 파일 이름 → 그림 이름: [[파일:…]] 문법을 깨는 글자(대괄호 · 세로줄 · 줄바꿈)는 빈칸으로, 확장자는 담은 꼴로 */
  const nameOf = (fileName, src) => {
    const base = String(fileName || '').replace(/\.[A-Za-z0-9]{1,5}$/, '').replace(/[[\]|\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80) || '그림';
    const ext = (String(src).match(/^data:image\/(png|jpeg|webp)/) || [])[1];
    return `${base}.${ext === 'jpeg' ? 'jpg' : ext || 'webp'}`;
  };
  /** 겹치지 않는 이름 — "이름 (2).webp" */
  const uniqueName = (list, name) => {
    const taken = new Set(list.map(g => String(g.name || '').toLowerCase()).concat(list.map(g => String(g.id || '').toLowerCase())));
    if (!taken.has(name.toLowerCase())) return name;
    const m = name.match(/^(.*?)(\.[a-z0-9]+)?$/i);
    let n = 2;
    while (taken.has(`${m[1]} (${n})${m[2] || ''}`.toLowerCase())) n++;
    return `${m[1]} (${n})${m[2] || ''}`;
  };
  /** 그림 사전에서 [[파일:…]]의 이름으로 — HT.docImageOf와 같은 차례(id → 이름 → 대소문자를 가리지 않은 이름) */
  const findIn = (list, ref) => {
    const r = String(ref || '').trim();
    return list.find(g => g.id === r) || list.find(g => g.name === r) || list.find(g => String(g.name || '').toLowerCase() === r.toLowerCase()) || null;
  };
  /** 작업본의 문서들이 그 그림을 몇 곳에서 쓰는지 (지우기를 막는 데 — 편집 중인 글도 셈) */
  const usesOf = (draft, g, editing, key) => {
    let n = 0;
    const docs = Object.entries((draft && draft.documents) || {}).filter(([k]) => !key || HT.docKey.absolute(k, draft.id) !== key).map(([, t]) => t); // 고치는 중인 문서는 저장한 글 대신 편집 중인 글로
    const texts = docs.concat(editing ? [editing] : []);
    for (const text of texts) if (HT.namu.files(text).some(f => findIn([g], f.name))) n++;
    return n;
  };

  // 문서 편집기와 구조 나무가 같은 모음을 쓴다. 열려 있는 편집기의 글은 저장 전이어도 사용 횟수에 넣는다.
  const sessions = new WeakMap(), galleries = new WeakMap();
  const editingOf = maker => {
    const session = sessions.get(maker);
    return session && session.host.isConnected && !session.host.closest('[hidden]') ? session : null;
  };
  function galleryOf(maker, esc) {
    if (galleries.has(maker)) return galleries.get(maker);
    const L = HT.PACK_LIMITS;
    const images = () => arr(maker.draft && maker.draft.images);
    const uses = g => {
      const active = editingOf(maker);
      return usesOf(maker.draft, g, active ? active.editor.textarea.value : '', active ? active.docKey() : '');
    };
    const dlg = document.createElement('dialog');
    dlg.className = 'mk-img-dlg';
    function open() {
      if (!maker.ready()) return;
      const active = editingOf(maker);
      const rows = images().map(g => {
        const n = uses(g);
        return `<div class="mk-img-row" data-img-row="${esc(g.id)}">
          <img src="${esc(g.src)}" alt="">
          <div class="mk-img-meta"><b>${esc(g.name || g.id)}</b><span data-img-size>${g.width && g.height ? `${g.width}×${g.height} · ` : ''}${size(bytesOf(g.src))} · ${n ? `문서 ${n}곳에서 씀` : '쓰지 않음'}</span>
            <label class="mk-img-key">이름<input data-k="name" value="${esc(g.name || '')}" maxlength="80" title="본문의 [[파일:이름]]이 가리키는 이름 — 바꾸면 이 팩 문서의 고리도 따라 바뀝니다"></label>
            <label class="mk-img-key">id<input data-k="id" value="${esc(g.id || '')}" maxlength="80" spellcheck="false" autocomplete="off" title="영문 id — 바꾸면 id로 적은 고리도 따라 바뀝니다"></label>
            <label>설명<input data-k="caption" value="${esc(g.caption || '')}" maxlength="${L.docImageText}"></label>
            <label>대체 글<input data-k="alt" value="${esc(g.alt || '')}" maxlength="${L.docImageText}"></label>
            <label>출처<input data-k="credit" value="${esc(g.credit || '')}" maxlength="${L.docImageText}"></label></div>
          <div class="mk-img-acts"><button type="button" class="btn btn-sm" data-img-put="${esc(g.name || g.id)}"${active ? '' : ' disabled title="문서 편집기를 열면 커서 자리에 그림을 넣을 수 있습니다"'}>넣기</button>
            <button type="button" class="btn btn-sm" data-img-swap title="다른 그림 파일로 바꿔 끼웁니다 — 이름 · 설명 · 문서의 고리는 그대로">바꿔 끼우기</button>
            <button type="button" class="btn btn-sm" data-img-del${n ? ` disabled title="문서 ${n}곳에서 쓰는 그림은 지울 수 없습니다 — 먼저 문서에서 [[파일:…]] 줄을 지우세요"` : ''}>지우기</button></div>
        </div>`;
      }).join('');
      dlg.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>그림 모음 — 이 팩의 문서 그림 ${images().length}장</h2><button type="button" class="icon-btn" data-close aria-label="닫기">✕</button></div>
        <div class="dlg-body mk-img-list">${active ? '' : '<p class="mk-imgs-none" data-img-no-editor>문서를 고쳐야 그림을 넣을 수 있습니다. 여기서는 그림 설명을 고치거나 쓰지 않는 그림을 지울 수 있습니다.</p>'}${rows || '<p class="mk-imgs-none">이 팩에는 아직 문서 그림이 없습니다. 문서 편집기의 [그림] 단추로 넣으세요.</p>'}</div>
        <div class="dlg-foot"><span class="spacer"></span><button type="button" class="btn" data-close>닫기</button>${rows ? '<button type="button" class="btn btn-primary" data-img-save>저장</button>' : ''}</div></div>`;
      if (!dlg.open) dlg.showModal();
    }
    /* 바꿔 끼우기(2026-10-23 — 전역 확대 ⑦): 저장 전까지 그림 id → { src, width, height }로 두었다가 저장할 때 함께 적음 */
    const swaps = new Map();
    /** 문서 본문의 [[파일:이름]] · [[이미지:…]] · [[file:…]] 고리에서 그 이름(또는 id)을 새 글로 — 바뀐 문서 수를 돌려줍니다 */
    const renameInDocs = (docs, from, to) => {
      if (!from || from === to) return 0;
      let n = 0;
      const re = new RegExp(`(\\[\\[\\s*(?:파일|이미지|file)\\s*:\\s*)${from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(\\s*(?:\\||\\]\\]))`, 'gi');
      for (const key of Object.keys(docs)) {
        const text = String(docs[key] || '');
        const out = text.replace(re, `$1${to}$2`);
        if (out !== text) {
          docs[key] = out;
          n++;
        }
      }
      return n;
    };
    function save() {
      const edits = new Map();
      for (const row of dlg.querySelectorAll('[data-img-row]')) {
        const o = { del: row.classList.contains('is-del') };
        for (const input of row.querySelectorAll('input[data-k]')) o[input.dataset.k] = input.value.trim();
        edits.set(row.dataset.imgRow, o);
      }
      // 모음이 열린 뒤 글이 바뀐 경우도 저장 직전에 다시 확인한다.
      if (images().some(g => (edits.get(g.id) || {}).del && uses(g))) {
        HT.toast('문서에서 쓰는 그림은 지울 수 없습니다. 먼저 문서에서 그림 줄을 지우세요.', 'error');
        return;
      }
      /* 이름 · id 바꾸기: 비울 수 없고(id는 영문 꼴), 남은 그림끼리 겹치면 안 됨 */
      const kept = images().filter(g => !(edits.get(g.id) || {}).del);
      const ids = new Set();
      const names = new Set();
      for (const g of kept) {
        const e = edits.get(g.id) || {};
        const id = e.id ?? g.id;
        const name = e.name ?? g.name;
        if (!id || !HT.ID_RE.test(id)) return HT.toast(`«${g.name || g.id}»의 id는 영문 · 숫자 · - _ .로 적어야 합니다.`, 'error');
        if (!name || /[[\]|\r\n]/.test(name)) return HT.toast(`«${g.name || g.id}»의 이름을 적어 주세요 — 대괄호 · 세로줄은 쓸 수 없습니다.`, 'error');
        if (ids.has(id) || names.has(name.toLowerCase())) return HT.toast(`그림의 id · 이름이 겹칩니다 — «${name}».`, 'error');
        ids.add(id);
        names.add(name.toLowerCase());
      }
      let changed = false;
      const renames = []; // [옛 글, 새 글] — 문서 고리 따라 고치기
      const next = kept.map(g => {
        const e = edits.get(g.id);
        const o = Object.assign({}, g);
        if (swaps.has(g.id)) {
          const s = swaps.get(g.id);
          delete o.width;
          delete o.height;
          Object.assign(o, s);
          changed = true;
        }
        if (!e) return o;
        for (const k of ['caption', 'alt', 'credit']) {
          if (e[k]) o[k] = e[k];
          else delete o[k];
          if ((o[k] || '') !== (g[k] || '')) changed = true;
        }
        for (const k of ['name', 'id']) {
          if (e[k] && e[k] !== (g[k] || '')) {
            renames.push([g[k] || '', e[k]]);
            o[k] = e[k];
            changed = true;
          }
        }
        return o;
      });
      if (next.length !== images().length) changed = true;
      dlg.close();
      if (!changed) return;
      const gone = images().length - next.length;
      let fixed = 0;
      const what = gone ? `문서 그림 ${gone}장 지움` : renames.length ? '문서 그림 이름 바꿈' : swaps.size ? '문서 그림 바꿔 끼움' : '문서 그림 설명 고침';
      const applyRenames = draft => {
        if (!renames.length || !draft.documents) return;
        for (const [from, to] of renames) fixed += renameInDocs(draft.documents, from, to);
      };
      if (maker.setImages(() => next, what, applyRenames)) {
        swaps.clear();
        if (fixed) HT.toast(`그림 이름을 바꿔 문서 ${fixed}곳의 고리도 따라 고쳤습니다.`, 'ok');
        const active = editingOf(maker);
        if (active) active.editor.textarea.dispatchEvent(new Event('input', { bubbles: true }));
        const session = sessions.get(maker);
        if (session) session.sync();
        HT.toast(gone ? `쓰지 않는 그림 ${gone}장을 지웠습니다.` : '그림 설명을 고쳤습니다.', 'ok');
      }
    }
    dlg.addEventListener('click', e => {
      if (e.target === dlg || e.target.closest('[data-close]')) return dlg.close();
      const put = e.target.closest('[data-img-put]');
      if (put) {
        const active = editingOf(maker);
        if (put.disabled || !active) return;
        dlg.close();
        active.editor.insertLine(`[[파일:${put.dataset.imgPut}]]`);
        return;
      }
      const del = e.target.closest('[data-img-del]');
      if (del) {
        if (del.disabled) return;
        const row = del.closest('[data-img-row]');
        row.classList.toggle('is-del');
        del.textContent = row.classList.contains('is-del') ? '지우지 않기' : '지우기';
        return;
      }
      const swap = e.target.closest('[data-img-swap]');
      if (swap) {
        /* 바꿔 끼우기: 새 파일을 같은 줄이기로 담아 두었다가 [저장]에서 적음 — 문서의 고리 · 이름 · 설명은 그대로 */
        const row = swap.closest('[data-img-row]');
        (async () => {
          const [file] = (await HT.pickFiles('image/png,image/jpeg,image/webp,image/gif,image/svg+xml,image/bmp')) || [];
          if (!file || !isImageFile(file)) return;
          try {
            const raw = await readAsDataURL(file);
            let fit = await HT.namu.fitImage(raw, MAX_SIDE, { force: raw.length > REENCODE || !/^data:image\/(png|jpeg|webp);base64,/.test(raw) });
            for (const side of SMALLER) if (fit.src.length > L.docImage) fit = await HT.namu.fitImage(raw, side, { force: true });
            if (fit.src.length > L.docImage) return HT.toast(`«${file.name}» 그림이 너무 큽니다 — 줄여도 한 장 한도(약 1.5MB)를 넘습니다.`, 'error');
            swaps.set(row.dataset.imgRow, fit.width && fit.height ? { src: fit.src, width: fit.width, height: fit.height } : { src: fit.src });
            row.classList.add('is-swapped');
            row.querySelector('img').src = fit.src;
            row.querySelector('[data-img-size]').textContent = `${fit.width && fit.height ? `${fit.width}×${fit.height} · ` : ''}${size(bytesOf(fit.src))} · 바꿔 끼울 그림 (저장하면 적힘)`;
          } catch (err) {
            HT.toast(`«${file.name}» 그림을 읽지 못했습니다 — ${(err && err.message) || err}`, 'error');
          }
        })();
        return;
      }
      if (e.target.closest('[data-img-save]')) save();
    });
    document.body.appendChild(dlg);
    const gallery = { open };
    galleries.set(maker, gallery);
    return gallery;
  }

  HT.makerImages = {
    /** 구조 나무에서도 문서 편집기의 그림 모음을 연다. 편집 중인 문서가 없으면 넣기는 비활성이다. */
    openGallery({ maker, esc }) { galleryOf(maker, esc).open(); },
    /** opts: { maker, editor(namu.editor의 답), host(#wikiEditor — 띠를 맨 아래에 붙임), esc, docKey() → 고치는 문서 열쇠 } → { pick, sync, addFiles, openGallery, destroy } */
    mount({ maker, editor, host, esc, docKey = () => '' }) {
      const ta = editor.textarea;
      const L = HT.PACK_LIMITS;
      const draft = () => maker.draft;
      const images = () => arr(draft() && draft().images);
      const strip = document.createElement('div');
      strip.className = 'mk-imgs';
      strip.setAttribute('aria-label', '문서 그림');
      host.appendChild(strip);

      /** 그림 파일들을 줄여 담고 커서 자리에 [[파일:이름]] 줄을 넣습니다. 그림이 없으면 false(끌어다 놓기 · 붙여넣기가 글로 처리하게) */
      async function addFiles(files) {
        const list = [...(files || [])].filter(isImageFile);
        if (!list.length) return false;
        if (!maker.ready()) return true;
        const names = [];
        let last = null;
        for (const file of list) {
          try {
            const raw = await readAsDataURL(file);
            let fit = await HT.namu.fitImage(raw, MAX_SIDE, { force: raw.length > REENCODE || !/^data:image\/(png|jpeg|webp);base64,/.test(raw) });
            for (const side of SMALLER) if (fit.src.length > L.docImage) fit = await HT.namu.fitImage(raw, side, { force: true });
            if (fit.src.length > L.docImage) {
              HT.toast(`«${file.name}» 그림이 너무 큽니다 — 줄여도 한 장 한도(약 1.5MB)를 넘습니다.`, 'error');
              continue;
            }
            const same = images().find(g => g.src === fit.src);
            if (same) {
              names.push(same.name || same.id); // 이미 담은 그림 — 다시 담지 않고 고리만
              continue;
            }
            const total = images().reduce((a, g) => a + String(g.src || '').length, 0);
            if (total + fit.src.length > L.docImageTotal) {
              HT.toast(`«${file.name}»을(를) 넣으면 이 팩의 그림 합이 한도(약 15MB — ${L.docImageTotal.toLocaleString('ko-KR')}자)를 넘습니다. 그림 모음에서 쓰지 않는 그림을 지우세요.`, 'error');
              continue;
            }
            const name = uniqueName(images(), nameOf(file.name, fit.src));
            let id = `img-${HT.hash(name)}`;
            while (images().some(g => g.id === id)) id = HT.uid('img');
            const img = { id, name, src: fit.src };
            if (fit.width && fit.height) Object.assign(img, { width: fit.width, height: fit.height });
            if (!maker.setImages(cur => cur.concat([img]), `문서 그림 넣기 «${name}»`)) continue;
            names.push(name);
            last = { img, fit };
          } catch (err) {
            HT.toast(`«${file.name}» 그림을 넣지 못했습니다 — ${(err && err.message) || err}`, 'error');
          }
        }
        if (names.length) editor.insertLine(names.map(n => `[[파일:${n}]]`).join('\n'));
        if (last) {
          const what = last.fit.width ? `${last.fit.width}×${last.fit.height} · ${size(bytesOf(last.img.src))}` : size(bytesOf(last.img.src));
          HT.toast(`${last.fit.keep ? '그림을 넣었습니다' : '그림을 줄여 넣었습니다'} — ${what}${names.length > 1 ? ` (모두 ${names.length}장)` : ''}`, 'ok');
        }
        sync();
        return true;
      }
      async function pick() {
        if (!maker.ready()) return;
        const files = await HT.pickFiles('image/png,image/jpeg,image/webp,image/gif,image/svg+xml,image/bmp', true);
        if (files && files.length) addFiles(files);
      }

      /** 띠를 다시 그립니다 — 미리 보기를 그릴 때마다(js/viewer.js) */
      function sync() {
        const all = images();
        const used = HT.namu.files(ta.value);
        const seen = new Set();
        const chips = [];
        for (const f of used) {
          if (!f.name || seen.has(f.name)) continue;
          seen.add(f.name);
          const g = findIn(all, f.name);
          chips.push(
            g
              ? `<button type="button" class="mk-img-chip" data-img-again="${esc(g.name || g.id)}" title="커서 자리에 이 그림을 한 번 더 넣기"><img src="${esc(g.src)}" alt=""><b>${esc(g.name || g.id)}</b><span>${g.width && g.height ? `${g.width}×${g.height} · ` : ''}${size(bytesOf(g.src))}</span></button>`
              : `<span class="mk-img-chip is-missing">그림 없음 — ${esc(f.name)}</span>`
          );
        }
        const total = all.reduce((a, g) => a + String(g.src || '').length, 0);
        const ratio = Math.min(1, total / L.docImageTotal);
        strip.innerHTML = `<div class="mk-imgs-doc">${chips.join('') || '<span class="mk-imgs-none">이 문서의 그림 없음</span>'}<span class="mk-imgs-count">· 이 팩의 그림 ${all.length}장</span></div>
          <span class="mk-imgs-total" title="data URL ${total.toLocaleString('ko-KR')}자 / ${L.docImageTotal.toLocaleString('ko-KR')}자">팩 그림 합 ${size(Math.round((total * 3) / 4))} / 15MB(${L.docImageTotal.toLocaleString('ko-KR')}자)</span>
          <span class="mk-imgs-bar${ratio > 0.9 ? ' is-full' : ''}" role="meter" aria-label="팩 그림 합" aria-valuemin="0" aria-valuemax="${L.docImageTotal}" aria-valuenow="${total}"><i style="width:${(ratio * 100).toFixed(1)}%"></i></span>
          <button type="button" class="btn btn-sm" data-img-gallery>그림 모음</button>`;
      }

      const session = { editor, host, docKey, sync };
      sessions.set(maker, session);
      const openGallery = () => galleryOf(maker, esc).open();

      const onStrip = e => {
        if (e.target.closest('[data-img-gallery]')) return openGallery();
        const again = e.target.closest('[data-img-again]');
        if (again) editor.insertLine(`[[파일:${again.dataset.imgAgain}]]`);
      };
      /* 글 칸 위의 그림 파일 끌기는 여기서 받고 위로 올려 보내지 않습니다 — 창 전체의 'DLC 파일 놓기'(js/viewer.js의 덮개 · .htpack만 엶)가
         그림을 DLC로 열려다 거절하지 않게. 그림이 아닌 파일(.htpack)은 그대로 창 전체의 길로 갑니다 */
      const hasImages = dt => !!dt && [...(dt.items || [])].some(i => i.kind === 'file' && /^image\//.test(i.type || ''));
      const onDragEnter = e => {
        if (!hasImages(e.dataTransfer)) return;
        e.preventDefault();
        e.stopPropagation();
        ta.classList.add('is-img-drop');
      };
      const onDragOver = e => {
        if (!hasImages(e.dataTransfer)) return;
        e.preventDefault();
        e.stopPropagation();
        e.dataTransfer.dropEffect = 'copy';
        ta.classList.add('is-img-drop');
      };
      const onDragLeave = e => {
        if (!hasImages(e.dataTransfer)) return;
        e.stopPropagation();
        ta.classList.remove('is-img-drop');
      };
      const onDrop = e => {
        ta.classList.remove('is-img-drop');
        const files = [...((e.dataTransfer && e.dataTransfer.files) || [])].filter(isImageFile);
        if (!files.length) return;
        e.preventDefault();
        e.stopPropagation();
        addFiles(files);
      };
      const onPaste = e => {
        const files = [...((e.clipboardData && e.clipboardData.files) || [])].filter(isImageFile);
        if (!files.length) return;
        e.preventDefault();
        addFiles(files);
      };
      strip.addEventListener('click', onStrip);
      ta.addEventListener('dragenter', onDragEnter);
      ta.addEventListener('dragover', onDragOver);
      ta.addEventListener('dragleave', onDragLeave);
      ta.addEventListener('drop', onDrop);
      ta.addEventListener('paste', onPaste);
      return {
        pick,
        sync,
        addFiles,
        openGallery,
        destroy() {
          strip.removeEventListener('click', onStrip);
          ta.removeEventListener('dragenter', onDragEnter);
          ta.removeEventListener('dragover', onDragOver);
          ta.removeEventListener('dragleave', onDragLeave);
          ta.removeEventListener('drop', onDrop);
          ta.removeEventListener('paste', onPaste);
          strip.remove();
          if (sessions.get(maker) === session) sessions.delete(maker);
        },
      };
    },
  };
})();

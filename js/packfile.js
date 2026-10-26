/* 역사 연표 — 전용 팩 파일(.htpack 2) · 공용 표지 도구
 * 메이커가 저장한 전용 압축 바이트만 읽습니다. JSON · ZIP은 외부 파일로 받지 않습니다.
 * SHA-256은 손상 검사이며 제작자 서명이나 외부 편집 방지 인증이 아닙니다.
 * 브라우저와 노드에서 함께 실행합니다. 내부 객체와 기존 저장된 작업본의 모양은 유지합니다.
 * 같은 포장(머리 52바이트 · deflate · 지문)의 종류 3은 '아카이브 배치'(.htlayout — 옛 메이커의 줄 배치 내보내기가 만들던
 * 가져오기 JSON 3판)입니다. 그 내보내기는 걷었습니다(2026-10-22 · 연표 앱이 .htpack을 바로 받음). 종류 3은 옛 파일을 알아보고
 * 알림을 띄우는 데 남겨 둡니다 — DLC가 아니므로 parse · read(DLC · 백업 받기)는 종류 3을 거절하고, parseLayout이 읽습니다
 * (buildLayout은 검사 scripts/check-htpack.mjs가 시험 파일을 만드는 데 씁니다). */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const MB = 1024 * 1024;
  const LIMITS = Object.freeze({ file: 64 * MB, total: 128 * MB });
  const MIME = 'application/x-htpack';
  const LAYOUT_MIME = 'application/x-htlayout';
  const MAGIC = new Uint8Array([72, 84, 80, 65, 67, 75, 13, 10]);
  const HEADER = 52, VERSION = 2;
  const LAYOUT = 3; // 머리 9번 자리(종류): 1 DLC · 2 전체 백업 · 3 아카이브 배치
  const enc = new TextEncoder();
  const dec = new TextDecoder('utf-8', { fatal: true });
  const fail = message => { throw Object.assign(new Error(message), { packError: true }); };
  const mb = n => `${Math.round(n / MB)}MB`;
  const isPack = b => b.length >= MAGIC.length && MAGIC.every((v, i) => b[i] === v);
  const concat = list => {
    const out = new Uint8Array(list.reduce((n, b) => n + b.length, 0));
    let offset = 0;
    for (const b of list) { out.set(b, offset); offset += b.length; }
    return out;
  };
  async function pipe(bytes, stream, max) {
    const reader = new Blob([bytes]).stream().pipeThrough(stream).getReader();
    const chunks = [];
    let n = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      n += value.length;
      if (n > max) {
        await reader.cancel().catch(() => {});
        fail(`팩을 풀면 허용 크기(${mb(max)})를 넘습니다.`);
      }
      chunks.push(value);
    }
    return concat(chunks);
  }
  async function digest(bytes) {
    if (!globalThis.crypto?.subtle) fail('파일 검사를 사용할 수 없습니다. 앱이나 보안 연결(HTTPS)에서 여세요.');
    return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  }
  function kindOf(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) fail('팩 내용이 올바르지 않습니다.');
    if (raw.format === 'history-timeline-dlc') return 1;
    if (raw.format === 'history-timeline-backup' && Array.isArray(raw.installed)) return 2;
    fail('역사 연표의 DLC나 백업이 아닙니다.');
  }
  /** 종류 3의 내용 — 가져오기 JSON 3판(docs/계약-아카이브-3단계.md 4절)인가. format 열쇠를 덧붙이지 않는다(노드 도구의 출력과 1바이트도 같아야 하므로) */
  const isLayout = raw =>
    !!raw && typeof raw === 'object' && !Array.isArray(raw) && Array.isArray(raw.packs) && raw.packs.length > 0 &&
    ['tracks', 'periods', 'cells', 'events', 'items', 'entities'].every(k => Array.isArray(raw[k]));
  /** 내부 자료 객체 → 전용 파일. 본문은 항상 압축하며, 표지와 문서도 함께 보관합니다. */
  async function build(raw) {
    const kind = kindOf(raw);
    return seal(kind, enc.encode(JSON.stringify(raw)));
  }
  /** 가져오기 JSON 3판 → 아카이브 배치 파일(.htlayout · 종류 3). 같은 머리 · 압축 · 지문 (제품은 부르지 않음 — 검사의 시험 파일용) */
  async function buildLayout(layout) {
    if (!isLayout(layout)) fail('아카이브 배치의 내용이 올바르지 않습니다.');
    return seal(LAYOUT, enc.encode(JSON.stringify(layout)));
  }
  /** 머리 52바이트 + 압축 본문 (종류 1 · 2 · 3 공용) */
  async function seal(kind, plain) {
    if (plain.length > LIMITS.total) fail(`팩 내용이 너무 큽니다 (${mb(LIMITS.total)}까지).`);
    if (typeof CompressionStream !== 'function') fail('이 브라우저는 팩 저장을 지원하지 않습니다. 최신 브라우저에서 여세요.');
    const body = await pipe(plain, new CompressionStream('deflate'), LIMITS.file - HEADER);
    const head = new Uint8Array(HEADER);
    head.set(MAGIC); head[8] = VERSION; head[9] = kind; head[10] = 1;
    const view = new DataView(head.buffer);
    view.setUint32(12, plain.length, true); view.setUint32(16, body.length, true);
    head.set(await digest(concat([head.subarray(0, 20), body])), 20);
    return concat([head, body]);
  }
  /** 확장자를 바꾸어도 JSON · ZIP이 전용 팩으로 통과하지 않습니다. 종류 3(아카이브 배치)은 DLC가 아니므로 받지 않습니다. */
  async function parse(input) {
    const { bytes, raw } = await unseal(input, [1, 2], {
      notPack: '전용 .htpack 파일이 아닙니다. JSON과 이전 ZIP 형식은 열 수 없습니다. DLC 메이커에서 새로 저장하세요.',
      otherKind: '아카이브 배치 파일(.htlayout)입니다 — DLC가 아니라 옛 메이커가 내보내던 줄 배치라 여기서는 열 수 없습니다. 메이커에서 .htpack으로 저장한 파일을 쓰세요.',
    });
    if (kindOf(raw) !== bytes[9]) fail('팩 종류와 내용이 맞지 않습니다.');
    /* 형식 4(리메이크 1단계 1a): 메이커가 형식 4로 저장하기(5단계) 전까지는 옛 꼴로 내려 받습니다 — 연표 설치본 · 메이커 작업본이 옛 꼴로 남게.
       core.js가 없는 곳(노드 검사의 packfile.js 단독)에서는 그대로 */
    if (HT.F4 && Number(raw.formatVersion) === HT.F4.VERSION) {
      const notes = ['형식 4 파일을 지금 형식으로 바꿔 읽었습니다(메이커에서 저장하면 다시 형식 4로 — 옛 형식은 파일 › 옛 형식으로 내보내기).'];
      return { raw: HT.F4.down(raw, m => notes.push(m)), kind: 'htpack', notes, raw4: raw }; // raw4 = 형식 4 원본 그대로(메이커가 저장 때 되돌릴 칸을 모으는 재료 — HT.F4.extrasOf · 5단계 과제 2) // 내림의 알림(뺀 직위 줄 · 모르는 종류 …)도 함께 — 연표는 설치 기록에, 메이커는 열 때 알림에
    }
    return { raw, kind: 'htpack', notes: [] };
  }
  /** 아카이브 배치 파일(.htlayout · 종류 3) → { layout, text } — text는 풀린 본문 그대로(노드 도구의 JSON과 같은 글) */
  async function parseLayout(input) {
    const { raw, text } = await unseal(input, [LAYOUT], {
      notPack: '아카이브 배치 파일(.htlayout)이 아닙니다.',
      otherKind: 'DLC · 백업 팩(.htpack)입니다 — 아카이브 배치 파일(.htlayout)이 아닙니다.',
    });
    if (!isLayout(raw)) fail('팩 종류와 내용이 맞지 않습니다.');
    return { layout: raw, text };
  }
  /** 머리 · 크기 · 지문을 검사하고 본문을 풀어 읽습니다 (kinds = 받는 종류 · 다른 종류의 전용 팩이면 otherKind 알림) */
  async function unseal(input, kinds, { notPack, otherKind }) {
    const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
    if (bytes.length > LIMITS.file) fail(`파일이 너무 큽니다 (${mb(LIMITS.file)}까지).`);
    if (!isPack(bytes)) fail(notPack);
    if (bytes.length < HEADER) fail('팩 파일의 머리 부분이 잘렸습니다.');
    if (bytes[8] !== VERSION) fail('지원하지 않는 팩 형식입니다. 메이커와 연표의 버전을 확인하세요.');
    if (!kinds.includes(bytes[9]) && [1, 2, LAYOUT].includes(bytes[9]) && bytes[10] === 1 && bytes[11] === 0) fail(otherKind);
    if (!kinds.includes(bytes[9]) || bytes[10] !== 1 || bytes[11] !== 0) fail('팩 파일의 머리 부분이 올바르지 않습니다.');
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const size = view.getUint32(12, true), packed = view.getUint32(16, true);
    if (!size || size > LIMITS.total) fail(`팩을 풀면 허용 크기(${mb(LIMITS.total)})를 넘거나 내용이 없습니다.`);
    if (!packed || packed !== bytes.length - HEADER) fail('팩 파일이 잘렸거나 불필요한 내용이 붙었습니다.');
    const body = bytes.subarray(HEADER);
    const sum = await digest(concat([bytes.subarray(0, 20), body]));
    if (!sum.every((v, i) => v === bytes[20 + i])) fail('팩 파일이 손상되었거나 바뀌었습니다. 원본을 다시 받거나 메이커에서 새로 저장하세요.');
    if (typeof DecompressionStream !== 'function') fail('이 브라우저는 팩 열기를 지원하지 않습니다. 최신 브라우저에서 여세요.');
    let plain;
    try { plain = await pipe(body, new DecompressionStream('deflate'), size); }
    catch (e) { if (e.packError) throw e; fail('팩 내용을 풀 수 없습니다. 파일이 손상되었습니다.'); }
    if (plain.length !== size) fail('팩 내용의 크기가 맞지 않습니다.');
    let raw, text;
    try { text = dec.decode(plain); raw = JSON.parse(text); }
    catch { fail('팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다.'); }
    return { bytes, raw, text };
  }
  async function read(file) {
    if (!file.name || !/\.htpack$/i.test(file.name)) fail('DLC 파일은 .htpack만 열 수 있습니다.');
    if (file.size > LIMITS.file) fail(`파일이 너무 큽니다 (${mb(LIMITS.file)}까지).`);
    return parse(new Uint8Array(await file.arrayBuffer()));
  }
  const fileName = pack => `${pack.id}-v${pack.version}.htpack`;
  /** 옛 아카이브 배치 파일 이름 — 작업본(고치는 DLC)의 id · 판 (지금 만드는 곳은 없음) */
  const layoutFileName = pack => `${pack.id}-v${pack.version}.htlayout`;

  /** 표지 그림을 가운데 16:9로 자르고 maxW×maxH 이하로 줄여 data URL로 (webp — 안 되는 브라우저면 jpeg, 품질 0.85). 캔버스가 없는 곳(노드)이면 그대로.
      top이면 세로로 자를 때 위에서부터(가로는 그대로 가운데) — 📷 지금 연표를 표지로(트랙 머리가 보이게). SVG(연표 그림)는 그림 내보내기처럼 흰 바탕을 먼저 칠함 */
  async function fitCover(src, maxW = 1600, maxH = 900, { top = false } = {}) {
    if (typeof Image === 'undefined' || typeof document === 'undefined' || typeof document.createElement !== 'function') return src;
    const img = await new Promise((res, rej) => {
      const i = new Image();
      i.onload = () => res(i);
      i.onerror = () => rej(Object.assign(new Error('표지 그림을 읽지 못했습니다.'), { packError: true }));
      i.src = src;
    });
    const W = img.naturalWidth;
    const H = img.naturalHeight;
    if (!W || !H) return src;
    let sw = W;
    let sh = H;
    if (W / H > 16 / 9) sw = Math.round((H * 16) / 9);
    else sh = Math.round((W * 9) / 16);
    const scale = Math.min(1, maxW / sw, maxH / sh);
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(sw * scale));
    c.height = Math.max(1, Math.round(sh * scale));
    const g = c.getContext('2d');
    g.imageSmoothingQuality = 'high';
    if (/^data:image\/svg/.test(src)) {
      g.fillStyle = '#ffffff';
      g.fillRect(0, 0, c.width, c.height);
    }
    g.drawImage(img, Math.round((W - sw) / 2), top ? 0 : Math.round((H - sh) / 2), sw, sh, 0, 0, c.width, c.height);
    const webp = c.toDataURL('image/webp', 0.85);
    return webp.startsWith('data:image/webp') ? webp : c.toDataURL('image/jpeg', 0.85);
  }

  /* ---------- 자동 표지 (docs/구상-메이커-팩.md 2-6) ---------- */
  const escAttr = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  /** 표지 그림이 없는 팩의 카드 그림(SVG 글): 시대를 시작 차례로 겹치지 않게 줄을 나눠(7줄까지) 가는 둥근 막대로, 세로 가운데.
      색은 적힌 색(파스텔로 맞춤)이나 트랙마다 정권 팔레트 차례. 시대가 없으면 옅은 줄무늬. 같은 팩이면 늘 같은 글 */
  HT.autoCover = (pack, W = 320, H = 180) => {
    const svg = inner => `<svg class="pk-auto" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${escAttr(pack.name || pack.id || '')}"><rect width="${W}" height="${H}" fill="#efe6d8"/>${inner}</svg>`;
    const num = v => (typeof v === 'number' && isFinite(v) ? v : null);
    const pers = (pack.periods || []).filter(x => x && num(x.start) != null).slice().sort((a, b) => a.start - b.start);
    if (!pers.length) return svg([0, 1, 2, 3, 4].map(i => `<rect x="${28 + i * 16}" y="${34 + i * 24}" width="${W - 56 - i * 32}" height="13" rx="6.5" fill="#cdbba3" opacity="${(0.95 - i * 0.16).toFixed(2)}"/>`).join(''));
    const endOf = x => num(x.end) ?? (x.ongoing ? Math.max(x.start + 60, HT.CURRENT_YEAR || x.start + 60) : x.start + 60);
    const lo = pers[0].start;
    const hi = Math.max(lo + 1, ...pers.map(endOf));
    const lanes = [];
    const placed = [];
    const nth = new Map();
    for (const x of pers) {
      let lane = lanes.findIndex(end => end <= x.start);
      if (lane < 0) {
        if (lanes.length >= 7) continue;
        lane = lanes.length;
        lanes.push(0);
      }
      lanes[lane] = endOf(x);
      const n = nth.get(x.track) || 0;
      nth.set(x.track, n + 1);
      placed.push({ x, lane, color: x.color ? HT.pastel(x.color) : HT.POLITY_PALETTE[n % HT.POLITY_PALETTE.length] });
    }
    const pad = 18;
    const rh = Math.min(26, (H - pad * 2) / Math.max(3, lanes.length));
    const top = (H - rh * lanes.length) / 2;
    const px = t => pad + ((t - lo) / (hi - lo)) * (W - pad * 2);
    return svg(placed.map(({ x, lane, color }) => `<rect x="${px(x.start).toFixed(1)}" y="${(top + lane * rh + rh * 0.14).toFixed(1)}" width="${Math.max(8, px(endOf(x)) - px(x.start)).toFixed(1)}" height="${(rh * 0.72).toFixed(1)}" rx="${(rh * 0.3).toFixed(1)}" fill="${escAttr(color)}"/>`).join(''));
  };

  /* ---------- DLC 카드 (연표의 DLC 관리 · 메이커의 처음 화면 · 팩 정보 미리보기가 함께 — docs/구상-메이커-팩.md 2-5 · 3-3 · 3-6) ---------- */
  const escHTML = s => HT.escapeHtml(s == null ? '' : s);
  const isBase = p => !!(p.builtin || p.overridesBuiltin);
  const catName = p => (isBase(p) ? '기본팩' : (HT.PACK_CATEGORIES.find(c => c.id === p.category) || {}).name || '');
  const coverHTML = p => `${p.cover ? `<img src="${escHTML(p.cover)}" alt="" loading="lazy">` : HT.autoCover(p)}${catName(p) ? `<span class="pk-cat${isBase(p) ? ' is-base' : ''}">${escHTML(catName(p))}</span>` : ''}`;
  const countsText = (src, keep) =>
    HT.USER_LISTS.map(({ list, kind }) => ({ list, word: HT.FORMS[kind].word, n: (src[list] || []).length }))
      .filter(x => x.n || keep.includes(x.list))
      .map(x => `${x.word} ${x.n}개`)
      .join(' · ');
  const contentsText = p =>
    [countsText(p, ['periods', 'events']), (p.patches || []).length ? `덮어쓰기 ${p.patches.length}개` : '', Object.keys(p.documents || {}).length ? `문서 ${Object.keys(p.documents).length}개` : ''].filter(Boolean).join(' · ');
  /** 카드 한 장 — sel 고른 카드 · toggle 켜기 스위치(true/false — 주지 않으면 스위치 없음) · off 꺼진 모양 · tag 이름 옆 딱지 · rel 관계 줄(HTML) · hint 읽어 주는 글의 '누르면 …' */
  function cardHTML(p, { sel = false, toggle = null, off = false, tag = '', rel = '', hint = '누르면 자세히' } = {}) {
    return `<div class="pk-card${off ? ' is-off' : ''}${sel ? ' is-sel' : ''}" data-pick-pack="${escHTML(p.id)}" tabindex="0" role="button" aria-pressed="${sel}" aria-label="${escHTML(p.name)} — ${escHTML(hint)}">
      <div class="pk-cover">${coverHTML(p)}</div>
      <div class="pk-body">
        <div class="pk-name"><b>${escHTML(p.name)}</b><span class="ver">v${escHTML(p.version)}</span>${tag ? `<span class="pack-tag">${escHTML(tag)}</span>` : ''}${
          toggle === null ? '' : `<label class="switch" title="${toggle ? '끄기' : '켜기'}"><input type="checkbox" data-toggle="${escHTML(p.id)}"${toggle ? ' checked' : ''} aria-label="${escHTML(p.name)} ${toggle ? '끄기' : '켜기'}"><i></i></label>`
        }</div>
        ${p.summary || p.description ? `<p class="pk-sum">${escHTML(p.summary || p.description)}</p>` : ''}
        ${(p.tags || []).length ? `<div class="pk-tags">${p.tags.map(t => `<span>${escHTML(t)}</span>`).join('')}</div>` : ''}
        <div class="pk-meta">${escHTML(contentsText(p))}</div>
        ${rel}
      </div>
    </div>`;
  }
  HT.packCard = { isBase, catName, coverHTML, contentsText, html: cardHTML };

  HT.packFile = { LIMITS, MIME, VERSION, HEADER, isPack, build, parse, read, fileName, fitCover, LAYOUT, LAYOUT_MIME, isLayout, buildLayout, parseLayout, layoutFileName };
})();

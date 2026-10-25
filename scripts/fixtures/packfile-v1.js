/* 검사 전용 보관본 — 이 파일은 제품에 배포하거나 제품에서 읽지 않습니다. */
/* 역사 연표 — 팩 파일(.htpack) (연표 · 메이커 공용 — docs/구상-메이커-팩.md 2절)
 * .htpack은 zip 파일 하나입니다: pack.json(팩 정보) + content/*.json(부분 파일) + images/(표지).
 * 이 파일이 맡는 것: zip 읽고 쓰기(CRC32 · deflate-raw 또는 압축 없이 · UTF-8 이름) · .htpack ↔ DLC JSON · 표지 줄이기 · 자동 표지.
 * 브라우저와 노드(scripts/dev-smoke.mjs) 모두에서 돕니다 — DOM은 표지 줄이기(캔버스)만 쓰고, 없으면 그대로 돌려줍니다.
 * platform.js 뒤, 팩 파일들 앞에 읽습니다 (index.html · dlc-maker.html) */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const MB = 1024 * 1024;
  const LIMITS = { file: 64 * MB, entry: 32 * MB, total: 128 * MB }; // total = 목차가 적은 풀린 크기의 합 (압축 폭탄 막기)
  const enc = new TextEncoder();
  const dec = new TextDecoder('utf-8');
  const mb = n => `${(n / MB).toFixed(n < 10 * MB ? 1 : 0)}MB`;
  /** 사람에게 보일 오류 — 설치 기록 · 알림에 message를 그대로 씁니다 */
  const fail = msg => {
    throw Object.assign(new Error(msg), { packError: true });
  };

  /* ---------- zip ---------- */
  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  const crc32 = bytes => {
    let c = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const concat = list => {
    const out = new Uint8Array(list.reduce((n, b) => n + b.length, 0));
    let o = 0;
    for (const b of list) {
      out.set(b, o);
      o += b.length;
    }
    return out;
  };
  const can = (Ctor, fmt) => {
    try {
      return typeof Ctor === 'function' && !!new Ctor(fmt);
    } catch (e) {
      return false;
    }
  };
  /** 흐름(스트림)을 통과시켜 바이트로 — max를 넘으면 멈추고 알림 (압축 폭탄 막기) */
  async function pipe(bytes, stream, max = Infinity, what = '') {
    const reader = new Blob([bytes]).stream().pipeThrough(stream).getReader();
    const chunks = [];
    let n = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      n += value.length;
      if (n > max) {
        await reader.cancel().catch(() => {});
        fail(`«${what}»이(가) 너무 큽니다 (${mb(max)}까지).`);
      }
      chunks.push(value);
    }
    return concat(chunks);
  }
  const dosTime = d => ((d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)) & 0xffff;
  const dosDate = d => (((Math.max(1980, d.getFullYear()) - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()) & 0xffff;
  const isZip = b => !!b && b.length >= 4 && b[0] === 0x50 && b[1] === 0x4b && b[2] === 3 && b[3] === 4;

  /** entries = [{ name, data }] → zip 바이트. 64바이트가 넘고 압축해서 줄어드는 것만 deflate, 나머지는 압축 없이 */
  async function writeZip(entries, { compress = true, date = new Date() } = {}) {
    const deflate = compress && can(typeof CompressionStream === 'function' ? CompressionStream : null, 'deflate-raw');
    const t = dosTime(date);
    const d = dosDate(date);
    const parts = [];
    const central = [];
    let offset = 0;
    for (const e of entries) {
      const name = enc.encode(e.name);
      const raw = typeof e.data === 'string' ? enc.encode(e.data) : e.data;
      const crc = crc32(raw);
      let body = raw;
      let method = 0;
      if (deflate && raw.length > 64) {
        const z = await pipe(raw, new CompressionStream('deflate-raw'));
        if (z.length < raw.length) {
          body = z;
          method = 8;
        }
      }
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, 0x0800, true); // 이름은 UTF-8
      local.setUint16(8, method, true);
      local.setUint16(10, t, true);
      local.setUint16(12, d, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, body.length, true);
      local.setUint32(22, raw.length, true);
      local.setUint16(26, name.length, true);
      parts.push(new Uint8Array(local.buffer), name, body);
      const cen = new DataView(new ArrayBuffer(46));
      cen.setUint32(0, 0x02014b50, true);
      cen.setUint16(4, 20, true);
      cen.setUint16(6, 20, true);
      cen.setUint16(8, 0x0800, true);
      cen.setUint16(10, method, true);
      cen.setUint16(12, t, true);
      cen.setUint16(14, d, true);
      cen.setUint32(16, crc, true);
      cen.setUint32(20, body.length, true);
      cen.setUint32(24, raw.length, true);
      cen.setUint16(28, name.length, true);
      cen.setUint32(42, offset, true);
      central.push(new Uint8Array(cen.buffer), name);
      offset += 30 + name.length + body.length;
    }
    const cenSize = central.reduce((n, b) => n + b.length, 0);
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(8, entries.length, true);
    end.setUint16(10, entries.length, true);
    end.setUint32(12, cenSize, true);
    end.setUint32(16, offset, true);
    return concat([...parts, ...central, new Uint8Array(end.buffer)]);
  }

  /** zip 바이트 → Map(이름 → 풀린 바이트). 폴더 항목은 건너뛰고, 이름의 \ 는 / 로. 목차(central directory)의 크기를 믿고 CRC로 확인합니다 */
  async function readZip(input, { maxFile = LIMITS.file, maxEntry = LIMITS.entry, maxTotal = LIMITS.total } = {}) {
    const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
    if (bytes.length > maxFile) fail(`파일이 너무 큽니다 (${mb(bytes.length)} — ${mb(maxFile)}까지).`);
    if (!isZip(bytes)) fail('압축(zip) 파일이 아닙니다.');
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let eocd = -1;
    for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 0xffff); i--) {
      if (view.getUint32(i, true) === 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) fail('압축 파일의 끝이 잘렸습니다.');
    if (view.getUint16(eocd + 4, true) || view.getUint16(eocd + 6, true)) fail('여러 조각으로 나뉜 압축 파일은 열 수 없습니다.');
    const count = view.getUint16(eocd + 10, true);
    const cdSize = view.getUint32(eocd + 12, true);
    const cdOff = view.getUint32(eocd + 16, true);
    if (count === 0xffff || cdOff === 0xffffffff) fail('아주 큰 압축 형식(zip64)은 열 수 없습니다.');
    if (cdOff + cdSize > eocd) fail('압축 파일의 목차가 깨졌습니다.');
    /* 목차를 먼저 다 읽어 검사합니다 — 한 자리를 겹쳐 가리키거나(같은 데이터를 수백 번 풀게 하는 압축 폭탄) 풀린 크기의 합이 한도를 넘으면 아무것도 풀기 전에 거절 */
    const entries = [];
    const seen = new Set();
    let total = 0;
    let p = cdOff;
    for (let k = 0; k < count; k++) {
      if (p + 46 > eocd || view.getUint32(p, true) !== 0x02014b50) fail('압축 파일의 목차가 깨졌습니다.');
      const flags = view.getUint16(p + 8, true);
      const method = view.getUint16(p + 10, true);
      const crc = view.getUint32(p + 16, true);
      const csize = view.getUint32(p + 20, true);
      const usize = view.getUint32(p + 24, true);
      const nlen = view.getUint16(p + 28, true);
      const xlen = view.getUint16(p + 30, true);
      const clen = view.getUint16(p + 32, true);
      const lho = view.getUint32(p + 42, true);
      const name = dec.decode(bytes.subarray(p + 46, p + 46 + nlen)).replace(/\\/g, '/');
      p += 46 + nlen + xlen + clen;
      if (flags & 1) fail('암호가 걸린 압축 파일은 열 수 없습니다.');
      if (name.endsWith('/')) continue;
      if (usize > maxEntry) fail(`«${name}»이(가) 너무 큽니다 (${mb(usize)} — ${mb(maxEntry)}까지).`);
      if (seen.has(lho)) fail('압축 파일의 목차가 한 자리를 겹쳐 가리킵니다 (깨졌거나 꾸민 파일).');
      seen.add(lho);
      total += usize;
      if (total > maxTotal) fail(`풀린 크기가 너무 큽니다 (${mb(maxTotal)}까지).`);
      entries.push({ flags, method, crc, csize, usize, lho, name });
    }
    const out = new Map();
    for (const { method, crc, csize, usize, lho, name } of entries) {
      if (lho + 30 > bytes.length || view.getUint32(lho, true) !== 0x04034b50) fail('압축 파일이 깨졌습니다.');
      const start = lho + 30 + view.getUint16(lho + 26, true) + view.getUint16(lho + 28, true);
      if (start + csize > bytes.length) fail('압축 파일의 끝이 잘렸습니다.');
      const body = bytes.subarray(start, start + csize);
      let data;
      if (method === 0) data = body;
      else if (method === 8) {
        if (!can(typeof DecompressionStream === 'function' ? DecompressionStream : null, 'deflate-raw')) fail('이 브라우저는 압축된 팩을 풀 수 없습니다 — 최신 브라우저에서 여세요.');
        data = await pipe(body, new DecompressionStream('deflate-raw'), maxEntry, name).catch(e => (e && e.packError ? Promise.reject(e) : fail(`«${name}»이(가) 깨졌습니다 (풀지 못함).`)));
      } else fail(`«${name}»의 압축 방식(${method})은 지원하지 않습니다.`);
      if (data.length !== usize || crc32(data) !== crc) fail(`«${name}»이(가) 깨졌습니다 (검사 값이 맞지 않음).`);
      out.set(name, data);
    }
    return out;
  }

  /* ---------- .htpack ↔ DLC JSON (docs/구상-메이커-팩.md 2-1) ---------- */
  /** 부분 파일: 목록 이름 → 파일. 여기 없는 최상위 열쇠(팩 정보 · 지도 영토 · 앞으로 생길 칸)는 모두 pack.json에 */
  const PARTS = [
    { file: 'content/base.json', lists: ['tracks', 'categories', 'peoples', 'rankDefs', 'houses'] },
    { file: 'content/history.json', lists: ['periods', 'dynasties', 'organs', 'cultures'] },
    { file: 'content/events.json', lists: ['events'] },
    { file: 'content/figures.json', lists: ['figures'] },
    { file: 'content/divisions.json', lists: ['epochs', 'scopes'] },
    { file: 'content/overrides.json', lists: ['patches'] },
  ];
  const DOCS_FILE = 'content/documents.json';
  const PART_LISTS = new Set(PARTS.flatMap(p => p.lists));
  const COVER_EXT = { png: 'png', jpeg: 'jpg', webp: 'webp' };
  const EXT_MIME = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp' };
  const toB64 = bytes => {
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  };
  const fromB64 = b64 => {
    const s = atob(b64);
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  };
  const pretty = x => `${JSON.stringify(x, null, 2)}\n`;
  const text = bytes => dec.decode(bytes).replace(/^﻿/, '');
  /** 맥(Finder)이 끼워 넣는 덧파일 — 읽지 않음 */
  const junk = name => /(^|\/)__MACOSX\//.test(name) || /(^|\/)\._/.test(name) || /(^|\/)\.DS_Store$/.test(name);

  /** DLC JSON(HT.packToJSON의 결과 — 표지는 data URL) → .htpack 바이트. 빈 목록은 넣지 않습니다(읽을 때 없는 목록 = 빈 목록) */
  async function build(pack, { compress = true } = {}) {
    let cover = null;
    const m = typeof pack.cover === 'string' && pack.cover.match(/^data:image\/(png|jpeg|webp);base64,(.+)$/);
    if (m) cover = { name: `images/cover.${COVER_EXT[m[1]]}`, data: fromB64(m[2]) };
    const head = {};
    for (const [k, v] of Object.entries(pack)) {
      if (PART_LISTS.has(k) || k === 'documents') continue;
      if (k === 'cover') {
        if (cover) head.cover = cover.name; // 팩 정보의 열쇠 차례를 지키려고 제자리에
        continue;
      }
      head[k] = v;
    }
    const files = [{ name: 'pack.json', data: pretty(head) }];
    for (const part of PARTS) {
      const body = {};
      for (const l of part.lists) if (Array.isArray(pack[l]) && pack[l].length) body[l] = pack[l];
      if (Object.keys(body).length) files.push({ name: part.file, data: pretty(body) });
    }
    if (pack.documents && typeof pack.documents === 'object' && Object.keys(pack.documents).length) files.push({ name: DOCS_FILE, data: pretty({ documents: pack.documents }) });
    if (cover) files.push(cover);
    return writeZip(files, { compress });
  }

  /** .htpack 바이트 → { raw: 옛 DLC JSON 모양(표지는 data URL), notes: 설치 기록에 적을 알림 }. content/ 안의 .json은 몇 개든 이름 차례로 합칩니다 */
  async function parse(bytes) {
    let files = await readZip(bytes);
    const notes = [];
    /* 폴더째 압축한 팩(윈도우 '압축(ZIP) 폴더' · 맥 Finder — 'mypack/pack.json' 꼴): 맨 위에 pack.json이 없고, 덧파일을 빼면 맨 위 폴더가 하나뿐이며
       그 안에 pack.json이 있으면 그 폴더 이름을 떼고 읽습니다 */
    if (!files.has('pack.json')) {
      const tops = new Set([...files.keys()].filter(n => !junk(n)).map(n => (n.includes('/') ? n.slice(0, n.indexOf('/') + 1) : '')));
      const [prefix] = tops;
      if (tops.size === 1 && prefix && files.has(`${prefix}pack.json`)) {
        const moved = new Map();
        for (const [n, d] of files) if (n.startsWith(prefix)) moved.set(n.slice(prefix.length), d);
        files = moved;
      }
    }
    if (!files.has('pack.json')) fail('팩 파일 안에 pack.json(팩 정보)이 없습니다.');
    let raw;
    try {
      raw = JSON.parse(text(files.get('pack.json')));
    } catch (e) {
      fail(`pack.json을 읽을 수 없습니다 — ${e.message}`);
    }
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) fail('pack.json이 객체({ … })가 아닙니다.');
    const parts = [...files.keys()].filter(n => /^content\/[^/]+\.json$/i.test(n) && !junk(n)).sort();
    for (const name of parts) {
      let part;
      try {
        part = JSON.parse(text(files.get(name)));
      } catch (e) {
        fail(`${name}을(를) 읽을 수 없습니다 — ${e.message}`);
      }
      if (!part || typeof part !== 'object' || Array.isArray(part)) fail(`${name}이(가) 객체({ … })가 아닙니다.`);
      for (const [k, v] of Object.entries(part)) {
        if (k === 'documents' && v && typeof v === 'object' && !Array.isArray(v)) raw.documents = Object.assign({}, raw.documents, v);
        else if (Array.isArray(v)) raw[k] = (Array.isArray(raw[k]) ? raw[k] : []).concat(v);
        else if (!(k in raw)) raw[k] = v;
      }
    }
    if (typeof raw.cover === 'string' && raw.cover && !raw.cover.startsWith('data:')) {
      const path = raw.cover.replace(/^\.?\//, '');
      const ext = ((path.match(/\.(\w+)$/) || [])[1] || '').toLowerCase();
      const img = files.get(path);
      if (img && EXT_MIME[ext]) raw.cover = `data:${EXT_MIME[ext]};base64,${toB64(img)}`;
      else {
        delete raw.cover;
        notes.push(`표지 «${path}»를 팩 안에서 찾지 못해 표지 없이 읽었습니다.`);
      }
    }
    return { raw, notes };
  }

  /** 파일 하나(File · Blob) → { raw, kind, notes }. 이름이 아니라 내용(첫 바이트)으로 팩 파일과 JSON을 가립니다 */
  async function read(file) {
    if (file.size > LIMITS.file) fail(`파일이 너무 큽니다 (${mb(file.size)} — ${mb(LIMITS.file)}까지).`);
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (isZip(bytes)) {
      const r = await parse(bytes);
      return { raw: r.raw, kind: 'htpack', notes: r.notes };
    }
    try {
      return { raw: JSON.parse(text(bytes)), kind: 'json', notes: [] };
    } catch (e) {
      fail(`JSON 파일을 읽을 수 없습니다 — ${e.message}`);
    }
  }

  const fileName = pack => `${pack.id}-v${pack.version}.htpack`;

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

  HT.packFile = { LIMITS, PARTS, crc32, writeZip, readZip, isZip, build, parse, read, fileName, fitCover };
})();

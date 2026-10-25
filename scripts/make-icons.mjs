// 앱 아이콘 만들기 (외부 라이브러리 없음)
// icons/app-1024.png 를 그리고, 거기서 192·512·maskable 아이콘을 만듭니다.
// 직접 그린 아이콘이 있으면 icons/app-1024.png 를 바꿔 넣고 `npm run icons` 를 다시 실행하세요.
import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync, inflateSync } from 'node:zlib';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = join(root, 'icons');
mkdirSync(dir, { recursive: true });

/* ---------- PNG 읽고 쓰기 (RGBA 8비트) ---------- */
const CRC = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});
const crc32 = buf => {
  let c = -1;
  for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
};
function encodePNG(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}
function decodePNG(buf) {
  let p = 8;
  let w = 0, h = 0, depth = 0, type = 0;
  const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p);
    const t = buf.toString('latin1', p + 4, p + 8);
    const d = buf.subarray(p + 8, p + 8 + len);
    if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); depth = d[8]; type = d[9]; }
    else if (t === 'IDAT') idat.push(d);
    p += 12 + len;
  }
  if (depth !== 8 || (type !== 6 && type !== 2)) throw new Error('icons/app-1024.png 는 8비트 RGB/RGBA PNG 여야 합니다');
  const bpp = type === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  const out = Buffer.alloc(w * h * 4);
  const prev = Buffer.alloc(stride);
  const cur = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    raw.copy(cur, 0, y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = cur[i];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const pp = a + b - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      cur[i] = v & 255;
    }
    for (let x = 0; x < w; x++) {
      out[(y * w + x) * 4] = cur[x * bpp]; out[(y * w + x) * 4 + 1] = cur[x * bpp + 1]; out[(y * w + x) * 4 + 2] = cur[x * bpp + 2];
      out[(y * w + x) * 4 + 3] = bpp === 4 ? cur[x * bpp + 3] : 255;
    }
    cur.copy(prev);
  }
  return { w, h, rgba: out };
}

/* ---------- 기본 아이콘 그리기: 종이 바탕 위에 연표 띠와 사건 점 ---------- */
const hex = s => [1, 3, 5].map(i => parseInt(s.slice(i, i + 2), 16));
function drawDefault(S = 1024) {
  const img = Buffer.alloc(S * S * 4);
  const bg = hex('#7a2e1f'), paper = hex('#f6e7c8');
  const bars = [
    { y: 0.30, x0: 0.14, x1: 0.62, c: hex('#f3c98b') },
    { y: 0.45, x0: 0.26, x1: 0.86, c: hex('#e7a97a') },
    { y: 0.60, x0: 0.14, x1: 0.50, c: hex('#f6e7c8') },
    { y: 0.60, x0: 0.56, x1: 0.86, c: hex('#f6e7c8') },
    { y: 0.75, x0: 0.34, x1: 0.72, c: hex('#f3c98b') },
  ];
  const dots = [[0.24, 0.30], [0.50, 0.30], [0.40, 0.45], [0.74, 0.45], [0.30, 0.60], [0.70, 0.60], [0.52, 0.75]];
  const barH = 0.075, r = barH / 2, dotR = 0.028;
  const put = (i, c, a = 1) => {
    img[i] = Math.round(img[i] * (1 - a) + c[0] * a);
    img[i + 1] = Math.round(img[i + 1] * (1 - a) + c[1] * a);
    img[i + 2] = Math.round(img[i + 2] * (1 - a) + c[2] * a);
    img[i + 3] = 255;
  };
  const sdRound = (px, py, x0, x1, y, rr) => {
    const cx = Math.min(Math.max(px, x0 + rr), x1 - rr);
    return Math.hypot(px - cx, py - y) - rr;
  };
  for (let y = 0; y < S; y++)
    for (let x = 0; x < S; x++) {
      const i = (y * S + x) * 4;
      put(i, bg);
      const px = (x + 0.5) / S, py = (y + 0.5) / S;
      for (const b of bars) {
        const d = sdRound(px, py, b.x0, b.x1, b.y, r);
        if (d < 0.002) put(i, b.c, Math.min(1, (0.002 - d) * S * 0.5));
      }
      for (const [dx, dy] of dots) {
        const d = Math.hypot(px - dx, py - dy) - dotR;
        if (d < 0.002) put(i, bg, Math.min(1, (0.002 - d) * S * 0.5));
        const d2 = Math.hypot(px - dx, py - dy) - dotR * 0.55;
        if (d2 < 0.002) put(i, paper, Math.min(1, (0.002 - d2) * S * 0.5));
      }
    }
  return { w: S, h: S, rgba: img };
}

/* ---------- 축소 (상자 평균) ---------- */
function resize(src, size) {
  const out = Buffer.alloc(size * size * 4);
  const f = src.w / size;
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const x0 = Math.floor(x * f), x1 = Math.max(x0 + 1, Math.floor((x + 1) * f));
      const y0 = Math.floor(y * f), y1 = Math.max(y0 + 1, Math.floor((y + 1) * f));
      const acc = [0, 0, 0, 0];
      let n = 0;
      for (let yy = y0; yy < y1; yy++)
        for (let xx = x0; xx < x1; xx++) {
          const i = (yy * src.w + xx) * 4;
          for (let k = 0; k < 4; k++) acc[k] += src.rgba[i + k];
          n++;
        }
      for (let k = 0; k < 4; k++) out[(y * size + x) * 4 + k] = Math.round(acc[k] / n);
    }
  return { w: size, h: size, rgba: out };
}

const base = join(dir, 'app-1024.png');
let master;
if (existsSync(base)) {
  master = decodePNG(readFileSync(base));
  if (master.w !== 1024 || master.h !== 1024) throw new Error('icons/app-1024.png 는 1024×1024 여야 합니다');
  console.log('icons/app-1024.png 를 사용합니다');
} else {
  master = drawDefault();
  writeFileSync(base, encodePNG(master.w, master.h, master.rgba));
  console.log('기본 아이콘을 그려 icons/app-1024.png 에 저장했습니다');
}
for (const s of [192, 512]) {
  const png = encodePNG(s, s, resize(master, s).rgba);
  writeFileSync(join(dir, `icon-${s}.png`), png);
  writeFileSync(join(dir, `icon-maskable-${s}.png`), png); // 내용이 가운데 70% 안에 있어 maskable로도 씁니다
}
console.log('icons/icon-192.png, icon-512.png, icon-maskable-*.png 생성');

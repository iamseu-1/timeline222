// 글끼리 겹침 찾기(축소 글자 겹침 조사 — 2026-10-25): remake4-shots.mjs --text로 찍은 <장면>.text.json(앱이 마지막 장면에 그린 글줄의 상자 ·
// scene/text_paragraph.dart TextProbe)을 읽어, 서로 다른 글줄의 잉크 상자가 겹치는 짝을 모두 적는다. 겹친 곳마다 그 장면 그림을 잘라 3배로 키우고
// 두 상자에 테(빨강 · 파랑)를 둘러 남긴다(새 패키지 없이 zlib로).
// 사용(작업 폴더에서):
//   node prototype/scripts/text-overlap.mjs <그림 폴더(태그 폴더)> [--only=<장면>,…] [--min=1] [--crops=<폴더>] [--json=<파일>]
// 상자는 글줄 상자(높이 = 글 크기 × 1.2)에서 위아래로 글 크기의 0.12씩 덜어 낸 잉크 언저리 · 그때의 자르기(clip)와 겹친 부분만 본다.
// 옅음이 0.15 밑인 글(사라지는 중)은 뺀다. 겹친 넓이가 가로 · 세로 모두 --min(px) 넘어야 겹침으로 친다.
// 글이 그 뒤에 그린 불투명한 판(붙은 머리 단 등)에 가려 화면에 없을 수 있다 — 잘린 그림으로 눈으로 확인한다.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const args = Object.fromEntries(process.argv.slice(2).map(a => { const m = a.match(/^--([^=]+)(?:=(.*))?$/); return m ? [m[1], m[2] ?? ''] : ['dir', a]; }));
if (!args.dir) { console.error('사용: node prototype/scripts/text-overlap.mjs <그림 폴더> [--only=…] [--min=1] [--crops=<폴더>] [--json=<파일>]'); process.exit(2); }
const dir = path.resolve(args.dir);
const only = (args.only || '').split(',').filter(Boolean);
const min = Number(args.min || 1);
const cropsDir = args.crops === undefined ? path.join(dir, '_겹침') : (args.crops ? path.resolve(args.crops) : '');

function decodePng(buf) {
  let pos = 8, width = 0, height = 0, type = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), kind = buf.toString('latin1', pos + 4, pos + 8), body = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === 'IHDR') { width = body.readUInt32BE(0); height = body.readUInt32BE(4); type = body[9]; }
    else if (kind === 'IDAT') idat.push(body);
    else if (kind === 'IEND') break;
    pos += 12 + len;
  }
  const bpp = type === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * bpp, out = Buffer.alloc(width * height * 4), prev = Buffer.alloc(stride), line = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = src[i];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      line[i] = v & 255;
    }
    for (let x = 0; x < width; x++) { const o = (y * width + x) * 4; out[o] = line[x * bpp]; out[o + 1] = line[x * bpp + 1]; out[o + 2] = line[x * bpp + 2]; out[o + 3] = 255; }
    line.copy(prev);
  }
  return { width, height, data: out };
}
const crcTable = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
const crc = buf => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (kind, body) => { const len = Buffer.alloc(4); len.writeUInt32BE(body.length); const kb = Buffer.from(kind, 'latin1'); const c = Buffer.alloc(4); c.writeUInt32BE(crc(Buffer.concat([kb, body]))); return Buffer.concat([len, kb, body, c]); };
function encodePng({ width, height, data }) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) { const o = (y * width + x) * 4, p = y * (width * 3 + 1) + 1 + x * 3; raw[p] = data[o]; raw[p + 1] = data[o + 1]; raw[p + 2] = data[o + 2]; }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
function crop(img, x0, y0, x1, y1, k, boxes) {
  x0 = Math.max(0, Math.floor(x0)); y0 = Math.max(0, Math.floor(y0)); x1 = Math.min(img.width, Math.ceil(x1)); y1 = Math.min(img.height, Math.ceil(y1));
  const w = (x1 - x0) * k, h = (y1 - y0) * k, data = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const s = ((y0 + Math.floor(y / k)) * img.width + x0 + Math.floor(x / k)) * 4; img.data.copy(data, (y * w + x) * 4, s, s + 4); }
  const colors = [[230, 30, 30], [30, 90, 230]];
  boxes.forEach((b, i) => {
    const [r, g, bl] = colors[i % 2];
    const bx0 = Math.round((b[0] - x0) * k) - 1, by0 = Math.round((b[1] - y0) * k) - 1, bx1 = Math.round((b[2] - x0) * k), by1 = Math.round((b[3] - y0) * k);
    const put = (x, y) => { if (x < 0 || y < 0 || x >= w || y >= h) return; const o = (y * w + x) * 4; data[o] = r; data[o + 1] = g; data[o + 2] = bl; };
    for (let x = bx0; x <= bx1; x++) { put(x, by0); put(x, by1); }
    for (let y = by0; y <= by1; y++) { put(bx0, y); put(bx1, y); }
  });
  return { width: w, height: h, data };
}

const files = fs.readdirSync(dir).filter(f => f.endsWith('.text.json')).filter(f => !only.length || only.includes(f.replace(/\.text\.json$/, ''))).sort();
const report = {};
let total = 0;
for (const f of files) {
  const id = f.replace(/\.text\.json$/, '');
  const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  const [ox, oy] = j.timeline;
  // [글, x0, y0, x1, y1, 자르기 x0, y0, x1, y1, 크기, 옅음] → 그림 좌표의 보이는 잉크 상자
  const boxes = [];
  j.boxes.forEach((b, i) => {
    const [s, x0, y0, x1, y1, c0, c1, c2, c3, size, alpha] = b;
    if (alpha < 0.15 || !String(s).trim()) return;
    const pad = size * 0.12;
    const l = Math.max(x0, c0), r = Math.min(x1, c2), t = Math.max(y0 + pad, c1), bt = Math.min(y1 - pad, c3);
    if (r - l < 1 || bt - t < 1) return;
    boxes.push({ i, s: String(s), size, box: [l + ox, t + oy, r + ox, bt + oy] });
  });
  const pairs = [];
  for (let a = 0; a < boxes.length; a++) for (let b = a + 1; b < boxes.length; b++) {
    const A = boxes[a].box, B = boxes[b].box;
    const w = Math.min(A[2], B[2]) - Math.max(A[0], B[0]), h = Math.min(A[3], B[3]) - Math.max(A[1], B[1]);
    if (w > min && h > min) pairs.push({ a: boxes[a], b: boxes[b], w: +w.toFixed(1), h: +h.toFixed(1) });
  }
  report[id] = pairs.map(p => ({ a: p.a.s, b: p.b.s, sizes: [p.a.size, p.b.size], at: p.a.box.map(v => Math.round(v)), with: p.b.box.map(v => Math.round(v)), w: p.w, h: p.h }));
  total += pairs.length;
  console.log(`${id}: 글 ${boxes.length} · 겹침 ${pairs.length}`);
  for (const p of pairs) console.log(`  "${p.a.s}"(${p.a.size}) ${p.a.box.map(Math.round).join(',')}  ↔  "${p.b.s}"(${p.b.size}) ${p.b.box.map(Math.round).join(',')}  · ${p.w}×${p.h}`);
  if (cropsDir && pairs.length && fs.existsSync(path.join(dir, `${id}.png`))) {
    fs.mkdirSync(cropsDir, { recursive: true });
    const img = decodePng(fs.readFileSync(path.join(dir, `${id}.png`)));
    pairs.forEach((p, n) => {
      const x0 = Math.min(p.a.box[0], p.b.box[0]) - 60, y0 = Math.min(p.a.box[1], p.b.box[1]) - 30, x1 = Math.max(p.a.box[2], p.b.box[2]) + 60, y1 = Math.max(p.a.box[3], p.b.box[3]) + 30;
      fs.writeFileSync(path.join(cropsDir, `${id}-${String(n + 1).padStart(2, '0')}.png`), encodePng(crop(img, x0, y0, x1, y1, 3, [p.a.box, p.b.box])));
    });
  }
}
if (args.json) fs.writeFileSync(path.resolve(args.json), JSON.stringify(report, null, 1) + '\n');
console.log(`모두: 장면 ${files.length} · 겹침 ${total}`);

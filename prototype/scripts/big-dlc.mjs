// 천만 재기의 가상 DLC 만들기(한 벌 P4 과제 11 · 걸음 1 — 11a): 사건 10만 · 100만의 가상 DLC를 `.htpack`으로 쓴다.
// 이름 · 글은 모두 지어낸 것이다(실제 역사 아님). 같은 인자면 언제 만들어도 같은 바이트다(난수 없음 — 고정 산술).
//
// 사용(작업 폴더에서):
//   node prototype/scripts/big-dlc.mjs --events=100000 --spread=even --out=<파일.htpack>
//   node prototype/scripts/big-dlc.mjs --events=1000000 --spread=one  --out=<파일.htpack>
//   --events   사건 수(기본 1000)
//   --spread   even = ① 트랙 50(--tracks)에 고르게 · one = ② 트랙 하나에 몰아서(기본 even)
//   --tracks   even의 트랙 수(기본 50 · one은 늘 1)
//   --bands    띠(줄) 전체 수(기본 1000) — even은 트랙마다 bands/tracks개, one은 그 하나에 전부. 두 모습이 줄 수는 같고 트랙 묶음만 다르게
//              (과제 7c의 `plans::big(50, 20, N)`과 같은 짝: 트랙 50 · 줄 1,000)
//   --id       DLC id(기본 big-<spread>-<사건 수 줄임>) · --name · --version(기본 1.0.0)
//   --track-prefix  트랙 id 앞머리(기본 <id>-t) — 같은 앞머리를 쓰는 DLC끼리는 같은 트랙에 얹힌다(기본은 제 트랙을 새로 만든다)
//   --format   1 · 3 = 옛 꼴(periods) · 4 = 형식 4(objects — 기본. `to-f4.mjs`가 올리는 꼴과 같다)
//   --seed     날짜 · 중요도를 흩는 씨앗(기본 20261022)
//   --part=<k>/<n>  전체 사건 수 --events를 n등분한 k째 몫만 쓴다(id 뒤에 -p<k> · 몫마다 제 띠 목록을 지닌 DLC. 트랙을 몫끼리 겹치려면 --track-prefix를 같게) — 아래 '크기 한계'
//   --out      .htpack(머리 52바이트 + deflate + 지문 — `js/packfile.js`의 build와 같은 바이트 꼴) 또는 .json(본문만)
//   --check    다 쓴 뒤 엔진 도구의 check-pack으로 읽어 본다(HT_ARCHIVE_TOOL 또는 prototype/engine/target/release/archive-tool)
// 한 줄 요약 JSON을 표준 출력에 찍는다({file, bytes, plain, events, tracks, bands, id, version, format, spread, ms}).
//
// 크기 한계: `.htpack` 하나는 풀린 본문 128MiB · 파일 64MiB까지다(웹 `packfile.js`의 LIMITS · 엔진 PACK_PLAIN_MAX와 같다). 사건 하나가 JSON으로 약 100바이트라
// 한 DLC는 120만 건 안팎이 끝이다 — 그보다 큰 세계(천만)는 DLC 여럿으로 나눈다(--part).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const args = process.argv.slice(2);
const opt = (name, fallback = '') => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const known = /^--(events|spread|tracks|bands|id|name|version|track-prefix|format|seed|out|part)=/;
const unknown = args.filter(a => a !== '--check' && !known.test(a));
const die = (msg, code = 2) => { console.error(`big-dlc: ${msg}`); process.exit(code); };
if (unknown.length) die(`모르는 인자: ${unknown.join(' ')}\n사용: node prototype/scripts/big-dlc.mjs --events=<N> [--spread=even|one] [--tracks=50] [--bands=1000] [--id=…] [--format=1|3|4] [--part=k/n] --out=<파일.htpack|.json> [--check]`);

const whole = Number(opt('events', '1000'));
const spread = opt('spread', 'even');
if (!Number.isInteger(whole) || whole < 1) die('--events는 1 이상의 정수여야 합니다.');
if (!['even', 'one'].includes(spread)) die('--spread는 even 또는 one입니다.');
const part = (() => {
  const text = opt('part');
  if (!text) return { k: 1, n: 1 };
  const m = /^(\d+)\/(\d+)$/.exec(text);
  if (!m || +m[1] < 1 || +m[1] > +m[2]) die('--part는 <k>/<n> 꼴이어야 합니다(1 ≤ k ≤ n).');
  return { k: +m[1], n: +m[2] };
})();
// 전체 사건 수를 n등분한 k째 몫(앞 몫부터 하나씩 더 맡는다).
const shareOf = (k) => Math.floor(whole / part.n) + (k <= whole % part.n ? 1 : 0);
const events = shareOf(part.k);
const firstEvent = Array.from({ length: part.k - 1 }, (_, i) => shareOf(i + 1)).reduce((a, b) => a + b, 0);
const tracks = spread === 'one' ? 1 : Number(opt('tracks', '50'));
const bandsTotal = Number(opt('bands', '1000'));
if (!Number.isInteger(tracks) || tracks < 1) die('--tracks는 1 이상의 정수여야 합니다.');
if (!Number.isInteger(bandsTotal) || bandsTotal < tracks) die('--bands는 트랙 수 이상의 정수여야 합니다.');
const bandsPer = Math.ceil(bandsTotal / tracks);
const format = Number(opt('format', '4'));
if (![1, 3, 4].includes(format)) die('--format은 1 · 3 · 4 가운데 하나입니다.');
const seed = Number(opt('seed', '20261022'));
const short = (n) => (n % 1_000_000 === 0 ? `${n / 1_000_000}m` : n % 1000 === 0 ? `${n / 1000}k` : String(n));
const baseId = opt('id') || `big-${spread}-${short(whole)}`;
const id = part.n > 1 ? `${baseId}-p${part.k}` : baseId;
const version = opt('version', '1.0.0');
const trackPrefix = opt('track-prefix') || `${id}-t`;
const name = opt('name') || `가상 대형 세계 ${id}`;
const out = opt('out');
if (!out) die('--out이 없습니다.');
if (!/\.(htpack|json)$/i.test(out)) die('--out은 .htpack 또는 .json이어야 합니다.');

// ---- 세계 만들기(고정 산술) ----

const YEAR_LO = -1500, YEAR_HI = 1990;
const pad = (n, w) => String(n).padStart(w, '0');
const mix = (a) => { // 32비트 흩뜨리기(난수 아님 — 같은 입력이면 같은 출력)
  let h = (a ^ seed) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0;
  return (h ^ (h >>> 16)) >>> 0;
};
const trackId = (t) => `${trackPrefix}${pad(t + 1, 2)}`;
const bandName = (t, b) => `가상 나라 ${pad(t + 1, 2)}-${pad(b + 1, 4)}`;
const bandSpan = (t, b) => { // 띠마다 조금씩 다른 긴 기간(모두 겹쳐 줄이 따로 선다)
  const h = mix(t * 7919 + b * 104729);
  return [YEAR_LO + (h % 12) * 20, YEAR_HI - ((h >>> 8) % 12) * 20];
};

const t0 = performance.now();
const trackRows = Array.from({ length: tracks }, (_, t) => ({ id: trackId(t), name: `가상 줄기 ${pad(t + 1, 2)}`, color: '#9dbea8', order: t + 1 }));
const bandRows = [];
for (let t = 0; t < tracks; t++) {
  for (let b = 0; b < bandsPer; b++) {
    const [start, end] = bandSpan(t, b);
    bandRows.push({ id: `${id}-b${pad(t + 1, 2)}-${pad(b + 1, 4)}`, track: trackId(t), name: bandName(t, b), start, end });
  }
}
// 사건: 트랙 → 띠 차례로 묶는다(내보내기가 줄 차례로 묶이는 것처럼). 번호 i는 전체 세계에서의 순번(--part로 나눠도 겹치지 않음).
const eventTexts = [];
{
  let i = 0;
  const total = tracks * bandsPer;
  for (let t = 0; t < tracks; t++) {
    for (let b = 0; b < bandsPer; b++) {
      const count = Math.floor(whole / total) + (t * bandsPer + b < whole % total ? 1 : 0);
      const [lo, hi] = bandSpan(t, b);
      for (let j = 0; j < count; j++, i++) {
        if (i < firstEvent || i >= firstEvent + events) continue;
        const h = mix(i * 2654435761);
        const start = lo + (h % (hi - lo + 1));
        const len = (h >>> 12) % 5 === 0 ? (h >>> 16) % 6 : 0;
        const e = { id: `e${i.toString(36)}`, track: trackId(t), title: `가상 사건 ${pad(i + 1, 7)}`, start };
        if (len) e.end = Math.min(hi, start + len);
        e.importance = 1 + ((h >>> 20) % 3);
        e.polity = bandName(t, b);
        eventTexts.push(JSON.stringify(e));
      }
    }
  }
}
const skeleton = {
  format: 'history-timeline-dlc', formatVersion: format, id, name, version, author: '가상 자료',
  description: '천만 재기용 가상 세계(한 벌 P4 과제 11). 모든 이름은 지어낸 것입니다.', requires: [],
  tracks: trackRows, categories: [], peoples: [], cultures: [], dynasties: [],
  ...(format === 4 ? {} : { epochs: [], periods: bandRows }),
  events: '@@EVENTS@@', patches: [], documents: {},
  ...(format === 4 ? { objects: bandRows } : {}),
};
const eventsText = `[${eventTexts.join(',')}]`;
const plain = Buffer.from(JSON.stringify(skeleton).replace('"@@EVENTS@@"', () => eventsText), 'utf8');
// 올바른 JSON인지 한 번 읽어 본다(100만 건도 몇 초 — 만들기는 한 번이면 된다).
if (JSON.parse(plain.toString('utf8')).events.length !== events) die('내부 오류: 사건 수가 맞지 않습니다.', 1);

// ---- 포장 ----

const PLAIN_MAX = 128 * 1024 * 1024, FILE_MAX = 64 * 1024 * 1024;
fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
let bytes;
if (/\.json$/i.test(out)) {
  bytes = plain;
  fs.writeFileSync(out, bytes);
} else {
  if (plain.length > PLAIN_MAX) die(`풀린 본문이 ${(plain.length / 1048576).toFixed(1)}MiB라 .htpack 한계(128MiB)를 넘습니다 — --part로 나누거나 --events를 줄이세요.`, 3);
  const body = zlib.deflateSync(plain);
  const header = Buffer.alloc(52);
  Buffer.from('HTPACK\r\n', 'latin1').copy(header, 0);
  header[8] = 2; header[9] = 1; header[10] = 1; header[11] = 0; // 규격 2 · 종류 1(DLC)
  header.writeUInt32LE(plain.length, 12);
  header.writeUInt32LE(body.length, 16);
  crypto.createHash('sha256').update(header.subarray(0, 20)).update(body).digest().copy(header, 20);
  bytes = Buffer.concat([header, body]);
  if (bytes.length > FILE_MAX) die(`파일이 ${(bytes.length / 1048576).toFixed(1)}MiB라 .htpack 한계(64MiB)를 넘습니다.`, 3);
  fs.writeFileSync(out, bytes);
}
const summary = { file: path.resolve(out), bytes: bytes.length, plain: plain.length, events, tracks, bands: bandRows.length, id, version, format, spread, ms: Math.round(performance.now() - t0) };

if (args.includes('--check')) {
  const names = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
  const tool = [process.env.HT_ARCHIVE_TOOL || '', ...names.map(n => path.join(prototype, 'engine', 'target', 'release', n))].find(f => f && fs.existsSync(f));
  if (!tool) die('--check: 엔진 도구(archive-tool)가 없습니다 — HT_ARCHIVE_TOOL 또는 cargo build --release.', 1);
  if (!/\.htpack$/i.test(out)) die('--check는 .htpack에만 씁니다.');
  const scratch = path.join(process.env.TMP || process.env.TEMP || '.', `big-dlc-check-${process.pid}.json`);
  const r = spawnSync(tool, ['check-pack', out, scratch], { encoding: 'utf8' });
  fs.rmSync(scratch, { force: true });
  if (r.status !== 0) die(`--check: 엔진이 읽지 못했습니다 — ${String(r.stderr || r.stdout).trim()}`, 1);
  summary.check = 'check-pack 통과';
}
console.log(JSON.stringify(summary));

// 옛 저장소 대조(리메이크 3단계 저장소 걸음 5 · 계획 과제 3의 검사 '옛 저장소 검사' · 계약 1-1): 진짜 판 3 저장소(배포본 0.0.4의 등불 연대기 '3' ·
// 동아시아 '3.1')를 **옛 엔진 도구**(배포본의 archive-tool — 스키마 4 전)와 **새 엔진 도구**(이 작업 폴더의 release archive-tool — 스키마 4)로 열어
// 같은 물음의 답을 견준다. 새 엔진은 옛 저장소의 새 열 · 표가 없을 뿐이라 빈 값(form 0 · sphereLines [])으로 답해야 하고, 그것만 빼면 답이 같아야 한다.
// 그리고 새 엔진이 지은 판 4 저장소를 옛 도구가 "다시 만들어야 합니다"로 거절하는지 본다(이 계획 전 엔진은 '4'를 거절한다 — 계약 1-1).
//
// 사용(작업 폴더에서 — 먼저 `cargo build --locked --release --bin archive-tool`):
//   node prototype/scripts/schema4-old-store-check.mjs [--old-tool=<옛 archive-tool>] [--new-tool=<새 archive-tool>] [--data=<배포본의 자료 폴더>]
//        [--stores=등불 연대기,동아시아] [--per-level=4] [--jobs=8] [--work=<임시 폴더>] [--keep]
//   --old-tool  옛 엔진(기본 C:/claude/HistoryTime/배포/HistoryTimeline-0.0.4/도구/prototype/archive-tool.exe — 읽기만, 저장소 사본에만 부른다)
//   --new-tool  새 엔진(기본 이 작업 폴더의 prototype/engine/target/release/archive-tool.exe)
//   --data      판 3 저장소가 든 자료 폴더(기본 옛 도구와 같은 배포본의 자료/ — `<자료>/<이름>/archive.db`를 임시 폴더에 **복사**해 쓴다 · 원본은 읽기만)
//   --per-level 단계마다 고를 가로 타일 수(자료가 놓인 열에서 고르게 · 기본 4) — 줄 묶음은 모두 · 보기는 기본과 변형 하나
//   --jobs      도구를 동시에 몇 개 부르나(기본 8)
//   --work      임시 폴더(기본 <TMP>/schema4-old-store-check — 처음에 비우고, 다 같으면 지운다 · 어긋나면 살펴보게 남긴다) · --keep 다 같아도 남김
// 견주는 것(저장소마다):
//   info(전부) · layout(새 답의 sphereLines가 []인지 보고 빼고) · legend_kinds · tile 바이트(단계 0 · 4 · 7 · 8 · 11 · 14 × 고른 열 × 모든 줄 묶음 × 보기 둘) ·
//   entity(표본 uid) · entities(모든 uid — 100개씩) · same_year(보는 범위를 고르게 + 띠 가운데 — 새 답 띠의 form이 0인지 보고 빼고) · search_year(같은 때)
// 다른 곳이 나오면: 배포본 0.0.4(main b722ae6)와 이 계획의 바탕(aeb788d) 사이의 엔진 바뀜은 배치(src/lay)뿐이라 읽기 쪽 바뀜이 아니다 —
// 그래도 의심되면 `git archive aeb788d prototype/engine`을 작업 폴더 밖에 풀어 따로 지은 도구를 --old-tool로 주어 다시 본다.
// 종료 코드: 0 = 모두 같음 · 옛 도구가 판 4를 거절 / 1 = 어긋남 · 거절 안 함 / 2 = 사용법 · 도구 · 저장소 없음.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const args = process.argv.slice(2);
const option = (name, fallback = '') => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const unknown = args.filter(a => a !== '--keep' && !/^--(old-tool|new-tool|data|stores|per-level|jobs|work)=/.test(a));
if (unknown.length) {
  console.error(`모르는 인자: ${unknown.join(' ')}\n사용: node prototype/scripts/schema4-old-store-check.mjs [--old-tool=…] [--new-tool=…] [--data=…] [--stores=등불 연대기,동아시아] [--per-level=4] [--jobs=8] [--work=…] [--keep]`);
  process.exit(2);
}
const RELEASE = 'C:/claude/HistoryTime/배포/HistoryTimeline-0.0.4';
const oldTool = path.resolve(option('old-tool', `${RELEASE}/도구/prototype/archive-tool.exe`));
const newTool = path.resolve(option('new-tool', path.join(prototype, 'engine', 'target', 'release', process.platform === 'win32' ? 'archive-tool.exe' : 'archive-tool')));
const data = path.resolve(option('data', `${RELEASE}/자료`));
const storeNames = option('stores', '등불 연대기,동아시아').split(',').filter(Boolean);
const perLevel = Math.max(1, Number(option('per-level', '4')) || 4);
const jobs = Math.max(1, Number(option('jobs', '8')) || 8);
const keep = args.includes('--keep');
const work = path.resolve(option('work') || path.join(process.env.TMP || process.env.TEMP || os.tmpdir(), 'schema4-old-store-check'));
for (const [what, file] of [['옛 도구', oldTool], ['새 도구', newTool]]) {
  if (!fs.existsSync(file)) { console.error(`${what}가 없습니다: ${file}${what === '새 도구' ? ' — 먼저 cargo build --locked --release --bin archive-tool' : ''}`); process.exit(2); }
}
for (const name of storeNames) {
  const db = path.join(data, name, 'archive.db');
  if (!fs.existsSync(db)) { console.error(`판 3 저장소가 없습니다: ${db}`); process.exit(2); }
}

const LEVELS = [0, 4, 7, 8, 11, 14];
const TILE_BUCKETS = 256, CHUNK_ROWS = 8;
/** levels.rs의 `tile_of`(통 너비 4^L분 · 타일 = 통 256개 · 내림). */
const tileOf = (minute, level) => Math.floor(Math.floor(minute / 4 ** level) / TILE_BUCKETS);
const NOW = '2026-10-15T12:00:00+09:00'; // 정답지와 같은 '오늘'(build-check.mjs)

// ---- 도구 ----

const tail = (text) => String(text || '').trim().split('\n').filter(l => !l.startsWith('    at ')).slice(-3).join('\n');
/** 도구를 비동기로 부른다 → { ok, out(글), err }. */
function run(tool, list) {
  return new Promise((resolve) => {
    execFile(tool, list, { encoding: 'utf8', maxBuffer: 1 << 30, windowsHide: true }, (error, stdout, stderr) => {
      resolve({ ok: !error, out: stdout, err: tail(stderr || error?.message) });
    });
  });
}
/** 동시에 `limit`개까지 돌리는 작업 줄. */
function pool(limit) {
  let running = 0;
  const waiting = [];
  const next = () => { while (running < limit && waiting.length) { running++; const { fn, resolve } = waiting.shift(); fn().then(resolve).finally(() => { running--; next(); }); } };
  return (fn) => new Promise((resolve) => { waiting.push({ fn, resolve }); next(); });
}
const queue = pool(jobs);
/** 두 JSON 값의 첫 다른 경로(살펴보기용). */
function firstDiff(a, b, at = '') {
  if (JSON.stringify(a) === JSON.stringify(b)) return null;
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = firstDiff(a[k], b[k], `${at}/${k}`);
      if (d) return d;
    }
  }
  return `${at || '/'}: 옛 ${JSON.stringify(a)?.slice(0, 120)} ≠ 새 ${JSON.stringify(b)?.slice(0, 120)}`;
}
const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
/** 고르게 n개(양 끝 포함). */
const spread = (list, n) => list.length <= n ? list : Array.from({ length: n }, (_, i) => list[Math.round(i * (list.length - 1) / (n - 1 || 1))]);

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
const problems = [];
const report = [];

/** 한 물음을 두 도구에 묻는다 → { old, new } 풀어 낸 JSON(실패면 그 글을 problems에). */
async function both(db, q, tag) {
  const [a, b] = await Promise.all([queue(() => run(oldTool, ['query', db, JSON.stringify(q)])), queue(() => run(newTool, ['query', db, JSON.stringify(q)]))]);
  if (!a.ok || !b.ok) {
    problems.push(`${tag} ${JSON.stringify(q)}: ${!a.ok ? `옛 도구 실패 ${a.err}` : ''} ${!b.ok ? `새 도구 실패 ${b.err}` : ''}`.trim());
    return null;
  }
  return { old: JSON.parse(a.out), new: JSON.parse(b.out) };
}
function same(tag, what, a, b) {
  const d = firstDiff(a, b);
  if (d) problems.push(`${tag} ${what}: ${d}`);
  return !d;
}

for (const name of storeNames) {
  const tag = `[${name}]`;
  const dir = path.join(work, name.replace(/[^\p{L}\p{N}-]+/gu, '-'));
  fs.mkdirSync(path.join(dir, 'tiles'), { recursive: true });
  const db = path.join(dir, 'archive.db');
  fs.copyFileSync(path.join(data, name, 'archive.db'), db);
  const before = sha(fs.readFileSync(db));
  const counts = { 타일: 0, 내용타일: 0, 항목: 0, 같은해: 0, 같은해띠: 0, 연도검색: 0 };

  // 저장소에서 바로 읽는 것(읽기 전용 — 판 · 줄 수 · 자료가 놓인 분 · 항목 uid).
  const sq = new DatabaseSync(db, { readOnly: true });
  const version = sq.prepare("SELECT value FROM meta WHERE key='schema'").get()?.value;
  const hasForm = sq.prepare("SELECT count(*) AS n FROM pragma_table_info('periods') WHERE name='form'").get().n > 0;
  const hasLines = sq.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name='sphere_lines'").get().n > 0;
  const rows = sq.prepare('SELECT count(*) AS n FROM rows').get().n;
  const minutes = [...new Set(['periods', 'cells', 'items'].flatMap(t => sq.prepare(`SELECT start,end FROM ${t}`).all().flatMap(r => [Number(r.start), Number(r.end)]))
    .concat(sq.prepare('SELECT start,end FROM events WHERE start IS NOT NULL AND end IS NOT NULL').all().flatMap(r => [Number(r.start), Number(r.end)])))].sort((a, b) => a - b);
  const bandMids = sq.prepare('SELECT start,end FROM periods ORDER BY id').all().map(r => Number(r.start) + Math.floor((Number(r.end) - Number(r.start)) / 2));
  const uids = sq.prepare('SELECT uid FROM entities ORDER BY uid').all().map(r => r.uid);
  const metaOf = (k) => Number(sq.prepare('SELECT value FROM meta WHERE key=?').get(k)?.value);
  const [min, max] = [metaOf('min'), metaOf('max')];
  sq.close();
  if (!['3', '3.1'].includes(version) || hasForm || hasLines) {
    problems.push(`${tag} 판 3 저장소가 아닙니다(판 ${version} · form 열 ${hasForm} · sphere_lines ${hasLines})`);
    continue;
  }

  // info · layout · legend_kinds
  const info = await both(db, { op: 'info' }, tag);
  if (info) same(tag, 'info', info.old, info.new);
  const layout = await both(db, { op: 'layout' }, tag);
  let variantKey = null;
  if (layout) {
    const lines = layout.new.sphereLines;
    if (JSON.stringify(lines) !== '[]') problems.push(`${tag} layout: 새 답의 sphereLines가 []가 아닙니다: ${JSON.stringify(lines)?.slice(0, 120)}`);
    if ('sphereLines' in layout.old) problems.push(`${tag} layout: 옛 답에 sphereLines가 있습니다`);
    delete layout.new.sphereLines;
    same(tag, 'layout', layout.old, layout.new);
    variantKey = layout.old.variants?.[0]?.key ?? null;
  }
  const legend = await both(db, { op: 'legend_kinds' }, tag);
  if (legend) same(tag, 'legend_kinds', legend.old, legend.new);
  const packs = (layout?.old.packs ?? []).map(p => p.id);

  // 타일 바이트 — 단계마다 자료가 놓인 열에서 고르게 · 모든 줄 묶음 · 보기 둘(기본 · 첫 변형).
  const chunks = Math.ceil(rows / CHUNK_ROWS);
  const views = [{}, ...(variantKey ? [{ variants: [variantKey] }] : [])];
  const tileJobs = [];
  let n = 0;
  for (const view of views) {
    for (const level of LEVELS) {
      const xs = spread([...new Set(minutes.map(m => tileOf(m, level)))].sort((a, b) => a - b), perLevel);
      for (const x of xs) {
        for (let chunk = 0; chunk < chunks; chunk++) {
          const q = { level, x, chunk, packs, ...view };
          const i = n++;
          const [fa, fb] = [path.join(dir, 'tiles', `old-${i}.bin`), path.join(dir, 'tiles', `new-${i}.bin`)];
          tileJobs.push((async () => {
            const [a, b] = await Promise.all([queue(() => run(oldTool, ['tile', db, JSON.stringify(q), fa])), queue(() => run(newTool, ['tile', db, JSON.stringify(q), fb]))]);
            if (!a.ok || !b.ok) { problems.push(`${tag} tile ${JSON.stringify(q)}: ${a.ok ? '' : `옛 ${a.err}`} ${b.ok ? '' : `새 ${b.err}`}`.trim()); return; }
            const [ba, bb] = [fs.readFileSync(fa), fs.readFileSync(fb)];
            if (!ba.equals(bb)) problems.push(`${tag} tile ${JSON.stringify(q)}: 바이트가 다릅니다(옛 ${ba.length} · 새 ${bb.length}바이트)`);
            else { fs.rmSync(fa); fs.rmSync(fb); }
            counts.타일++;
            // 도구가 찍는 요약({bytes, bands, cells, events, pills …}) — 빈 타일끼리만 같아서 지나가지 않게 내용이 든 타일을 센다.
            const told = JSON.parse(String(b.out).trim().split('\n').pop());
            if (told.bands + told.cells + told.events + told.pills > 0) counts.내용타일++;
          })());
        }
      }
    }
  }
  await Promise.all(tileJobs);

  // 항목 기록 — 표본 uid 하나씩(entity) · 모든 uid를 100개씩(entities).
  const entityJobs = spread(uids, 40).map(async (uid) => {
    const r = await both(db, { op: 'entity', uid }, tag);
    if (r) { same(tag, `entity ${uid}`, r.old, r.new); counts.항목++; }
  });
  for (let i = 0; i < uids.length; i += 100) {
    entityJobs.push((async () => {
      const r = await both(db, { op: 'entities', uids: uids.slice(i, i + 100) }, tag);
      if (r) same(tag, `entities ${i}~`, r.old, r.new);
    })());
  }
  await Promise.all(entityJobs);

  // same_year · search_year — 보는 범위를 고르게 24곳 + 띠 가운데(고르게 24곳).
  const times = [...new Set([...Array.from({ length: 24 }, (_, i) => min + Math.floor((max - min) * i / 23)), ...spread(bandMids, 24)])].sort((a, b) => a - b);
  await Promise.all(times.flatMap(at => [
    (async () => {
      const r = await both(db, { op: 'same_year', at, end: at }, tag);
      if (!r) return;
      for (const t of r.new.tracks ?? []) {
        for (const b of t.bands ?? []) {
          if (b.form !== 0) problems.push(`${tag} same_year ${at}: 띠 ${b.uid}의 form이 0이 아닙니다(${b.form})`);
          delete b.form;
          counts.같은해띠++;
        }
      }
      same(tag, `same_year ${at}`, r.old, r.new);
      counts.같은해++;
    })(),
    (async () => {
      const r = await both(db, { op: 'search_year', at, limit: 200 }, tag);
      if (r) { same(tag, `search_year ${at}`, r.old, r.new); counts.연도검색++; }
    })(),
  ]));
  if (!counts.내용타일 || !counts.같은해띠 || !packs.length) {
    problems.push(`${tag} 견준 것이 비었습니다(내용 든 타일 ${counts.내용타일} · same_year 띠 ${counts.같은해띠} · 자료집 ${packs.length})`);
  }
  const untouched = sha(fs.readFileSync(db)) === before;
  if (!untouched) problems.push(`${tag} 두 도구로 읽은 뒤 저장소 사본의 바이트가 바뀌었습니다`);
  report.push({ 저장소: name, 판: version, 줄: rows, 묶음: chunks, ...counts, 보기: views.length, 그대로: untouched });
}

// 새 엔진이 지은 판 4 저장소(형식 4 가상 팩 f4-office3 — form ≠ 0인 띠가 든다)를 옛 도구가 거절하는가. 판 글자만 '4.1'로 바꾼 사본도.
{
  const dir = path.join(work, 'v4');
  fs.mkdirSync(dir, { recursive: true });
  const v4 = path.join(dir, 'archive.db');
  const calendar = path.join(prototype, 'engine', 'tests', 'fixtures', 'lay', 'calendar-slice.json');
  const built = await run(newTool, ['build', v4, path.join(prototype, 'fixtures', 'oracle', 'f4-office3.json'), `--calendar=${calendar}`, '--calendar-narrow', `--now=${NOW}`]);
  if (!built.ok) {
    problems.push(`판 4 사본: 새 도구가 짓지 못했습니다 — ${built.err}`);
  } else {
    const sq = new DatabaseSync(v4, { readOnly: true });
    const version = sq.prepare("SELECT value FROM meta WHERE key='schema'").get()?.value;
    const forms = sq.prepare('SELECT count(*) AS n FROM periods WHERE form<>0').get().n;
    sq.close();
    if (version !== '4') problems.push(`판 4 사본: 새 도구가 적은 판이 '4'가 아닙니다(${version})`);
    const split = path.join(dir, 'split.db');
    fs.copyFileSync(v4, split);
    const w = new DatabaseSync(split);
    w.prepare("UPDATE meta SET value='4.1' WHERE key='schema'").run();
    w.close();
    const refused = [];
    for (const [label, file] of [['판 4', v4], ['판 4.1(글자만)', split]]) {
      for (const q of [{ op: 'info' }, { op: 'layout' }]) {
        const r = await run(oldTool, ['query', file, JSON.stringify(q)]);
        if (r.ok || !r.err.includes('다시 만들어야')) problems.push(`${label} ${q.op}: 옛 도구가 '다시 만들어야'로 거절하지 않았습니다 — ${r.ok ? '열림' : r.err}`);
        else refused.push(`${label} ${q.op}`);
      }
      const r = await run(newTool, ['query', file, '{"op":"info"}']);
      if (!r.ok) problems.push(`${label}: 새 도구가 열지 못했습니다 — ${r.err}`);
    }
    report.push({ 판4사본: 'f4-office3', 판: version, form띠: forms, 옛도구거절: refused.length });
  }
}

for (const r of report) console.log(JSON.stringify(r));
if (problems.length) {
  console.log(`어긋남 ${problems.length}건 — 임시 폴더를 남깁니다: ${work}`);
  for (const p of problems.slice(0, 40)) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`모두 같음 — 옛 도구 ${oldTool} · 새 도구 ${newTool}`);
if (!keep) fs.rmSync(work, { recursive: true, force: true });

// 옛 DLC 마지막 확인(한 벌 P4 과제 11 걸음 3 — 11a에서 앞당겨 만든 스크립트): 옛 DLC 묶음(옛 DLC의 약속 1)을 엔진 하나로 하나씩 넣고 빼며
// `archive-tool canon --queries`가 그 조합을 통째로 지은 것(archive-tool build)과 같은지, 그리고 이 계획 전의 앱으로 지은 저장소(옛 DLC의 약속 2)가 DLC 하나를 더 넣어도
// KoreanTimeLine을 지니는지 본다. 11a에서는 **옛 길을 걷기 전** 엔진으로 한 번 돌려 결과를 보고에 적는다 — 옛 길(앱 Node 갈래 · `도구/` · `DLC/` 폴더)을 걷은 뒤 다시 돌리는 것은 과제 11 뒤 걸음.
//
// 사용(작업 폴더에서):
//   node prototype/scripts/old-dlc-check.mjs [--only=walk,store] [--jobs=4] [--work=<폴더>] [--keep] [--tool=<archive-tool>] [--ktl=<KoreanTimeLine .htpack>] [--old-root=<배포 폴더의 자료>]
//   --only   walk = 묶음 걷기(아래) · store = 이 계획 전의 앱으로 지은 저장소 사본(기본 둘 다)
//   --walks  돌릴 걷기(each · stack · lantern · f4 · f4json — 기본은 lantern 빼고 모두). lantern(등불 연대기 저장소)은 canon이 한 저장소에 --queries 없이도 12분 넘고 --queries는 20분 · 3GB를 넘겨(11a에서 재어 죽임) 기본에서 뺐다 — 필요하면 --walks=lantern --jobs=1로 따로
//   --jobs   canon을 동시에 몇 개 돌리나(기본 4 — canon --queries는 작은 저장소도 수십 초 걸린다)
//   --work   임시 저장소를 둘 폴더(기본 <TMP>/old-dlc-check — 처음에 비우고 끝나면 지운다. 어긋나면 살펴보게 남긴다) · --keep 다 맞아도 남김
//   --ktl    KoreanTimeLine v1.0.5(감독의 실자료 — 읽기만, 작업 폴더에 **사본**으로 놓고 쓴다. 기본 HT_KTL(없으면 감독 PC의 옛 자리 — oracle/ktl.mjs) · 없으면 그 걸음을 건너뜀 · HT_REQUIRE_KTL=1이면 실패)
//   --old-root  배포 폴더의 자료(기본 D:/Timeline/배포/아카이브-리메이크2부-2026-10-15/자료 — 동아시아/archive.db가 KoreanTimeLine을 넣어 둔 이 계획 전의 저장소 · 읽기만, 사본으로 쓴다)
//   (환경 변수) HT_ARCHIVE_TOOL=<archive-tool 경로>
// 종료 코드: 0 = 돌린 걸음이 모두 같음 · 누락 · 중복 0 / 1 = 어긋남 · 거절이 있음 / 2 = 사용법 · 도구 없음.
//
// 묶음(옛 DLC의 약속 1 — fixtures/oracle/list.json의 짝과 같다):
//   ea      동아시아 기본팩 사본(형식 1 · fixtures/oracle/east-asia.json) · ea4 같은 팩의 형식 4 사본(f4/east-asia.htpack — 같은 id · 같은 판)
//   ktl     KoreanTimeLine v1.0.5(형식 3 · 감독의 실자료)
//   move · nest · dep · d7 · sphere   리메이크 시험 DLC 다섯(형식 3 · fixtures/oracle/*.htpack) · dep4 · nest4 그 형식 4 사본(f4/) · nestj 형식 4 JSON(nest-scene.f4.json)
//   lantern 등불 연대기(형식 3 · samples/sample-lantern.json)
// 걷기(걸음마다: 고쳐 쓴 저장소의 canon --queries = 그 조합을 통째로 지은 저장소의 canon · verify-tiles 120 누락 · 중복 0):
//   하나씩   동아시아 → +d → −d (d = ktl · move · nest · dep · d7 · sphere, 날 때마다 동아시아로 돌아옴)
//   쌓기     동아시아 → +ktl +move +nest −move +dep −ktl +d7 −nest +sphere −dep −d7 −sphere (한꺼번에 셋까지만 얹고 섞인 차례로 빼며 돈다 — 여섯을 한꺼번에 얹은 조합은 canon --queries가 한 저장소에 7GB를 넘겨(11a에서 재어 죽임) 뺐다)
//   등불     등불 연대기 → +d7 +sphere → −d7 −sphere (기본에서 뺌 — --walks=lantern일 때만. canon이 너무 무거워 **--queries 없이** 기본 canon(layout · 풀어 낸 타일)으로 견준다)
//   형식 4   동아시아 → +dep4 +nest4 → +ea4(기본팩을 같은 판의 형식 4 사본으로 바꿔 넣기) → −dep4 · 동아시아 → +nestj → −nestj
// 통째 지은 저장소는 늘 같은 '오늘'(2026-10-15T12:00:00+09:00)과 같은 달력 표(engine/tests/fixtures/lay/calendar-slice.json)로 `archive-tool build`한 것이다 —
// 넣고 빼는 저장소도 같은 판에서 시작해 저장소의 '오늘'(meta.now)을 쓰므로 같은 날이다.
//
// 이 계획 전의 저장소(store): 배포 폴더의 동아시아 저장소 사본(판 3 · 3.1 — KoreanTimeLine이 든 것이면 그것도 본다)을 연다 —
//   ① 엔진 `add-pack`으로 DLC 하나(dep-scene)를 더한다: 받으면 KoreanTimeLine이 남고 통째 짓기와 같아야 한다. 거절하면 그 글을 적고 저장소가 바이트까지 그대로인지 본다.
//   ② 지금 앱이 쓰는 길(add-dlc.mjs --apply — Node 배치 → apply-layout)로 같은 DLC를 더한다: KoreanTimeLine이 남는지(DLC 목록 · 트랙 · 띠 수).
//   ①② 모두 고쳐 쓴 뒤 meta.schema가 '4' · '4.1'인지 본다(리메이크 3단계 저장소 걸음 9 — 첫 모두 덮는 고쳐 쓰기가 스키마 4로 올린다 · 계약 1-1).
//   KoreanTimeLine이 없는 저장소(예: 배포본 0.0.4의 동아시아 — 기본팩 + dlc-20261023)는 그 단언만 글로 알리고 건너뛴다(나머지는 그대로 본다 · 끝 요약에 '약속 2를 보지 못함').
//   HT_REQUIRE_KTL=1이면 저장소가 없거나 KoreanTimeLine이 없을 때 건너뛰지 않고 실패한다(감독 PC · 공식 검사 — 약속 2가 소리 없이 빠지지 않게).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { useCalendarCopy } from './oracle/cal-copy.mjs';
import { ktlFile, requireKtl } from './oracle/ktl.mjs';

useCalendarCopy('old-dlc-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const root = path.resolve(prototype, '..');
const oracle = path.join(prototype, 'fixtures', 'oracle');
const args = process.argv.slice(2);
const option = (name, fallback = '') => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const unknown = args.filter(a => a !== '--keep' && !/^--(only|walks|jobs|work|tool|ktl|old-root)=/.test(a));
if (unknown.length) {
  console.error(`모르는 인자: ${unknown.join(' ')}\n사용: node prototype/scripts/old-dlc-check.mjs [--only=walk,store] [--jobs=4] [--work=<폴더>] [--keep]`);
  process.exit(2);
}
const keep = args.includes('--keep');
const only = new Set(option('only', 'walk,store').split(',').filter(Boolean));
const WALKS = ['each', 'stack', 'lantern', 'f4', 'f4json'];
const walks = new Set(option('walks', WALKS.filter(k => k !== 'lantern').join(',')).split(',').filter(Boolean)); // lantern은 기본에서 뺀다(아래 머리말)
for (const k of walks) if (!WALKS.includes(k)) { console.error(`모르는 걷기: ${k} (${WALKS.join(' · ')})`); process.exit(2); }
for (const k of only) if (!['walk', 'store'].includes(k)) { console.error(`모르는 부분: ${k} (walk · store)`); process.exit(2); }
const jobs = Math.max(1, Number(option('jobs', '4')) || 4);
const work = path.resolve(option('work') || path.join(process.env.TMP || process.env.TEMP || os.tmpdir(), 'old-dlc-check'));
const ktlSource = option('ktl', ktlFile());
if (requireKtl() && !fs.existsSync(ktlSource)) { console.error(`KTL이 없습니다(${ktlSource}) — HT_REQUIRE_KTL=1이라 건너뛰지 않습니다(자리는 --ktl 또는 HT_KTL)`); process.exit(1); }
const oldRoot = option('old-root', 'D:/Timeline/배포/아카이브-리메이크2부-2026-10-15/자료');
const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [option('tool'), process.env.HT_ARCHIVE_TOOL || '', ...[prototype, path.join(prototype, 'engine', 'target', 'release')].flatMap(dir => toolNames.map(n => path.join(dir, n)))]
  .find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) { console.error(`엔진 도구(${toolNames[0]})가 없습니다 — 먼저 cargo build --release --locked 또는 --tool=<경로>.`); process.exit(2); }

const NOW = '2026-10-15T12:00:00+09:00'; // 정답지와 같은 '오늘'(build-check.mjs)
const calendar = path.join(prototype, 'engine', 'tests', 'fixtures', 'lay', 'calendar-slice.json');

// ---- 도구 ----

const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const fileSha = (f) => sha(fs.readFileSync(f));
const tail = (text) => String(text || '').trim().split('\n').filter(l => !l.startsWith('    at ')).slice(-4).join('\n');
const ms = (t0) => Math.round(performance.now() - t0);
/** 엔진 도구를 동기로 부른다 → { ok, out, text, ms }. */
function engine(list) {
  const t0 = performance.now();
  const r = spawnSync(tool, list, { encoding: 'utf8', maxBuffer: 1 << 28 });
  return { ok: r.status === 0, out: r.stdout, text: tail(r.stderr || r.stdout), ms: ms(t0) };
}
const lastJson = (text) => JSON.parse(String(text).trim().split('\n').pop());
/** canon 출력을 비동기로 — SHA-256만 남긴다(출력은 수십 MB). 다를 때만 다시 풀어 견준다. */
function canonSha(db, light = false) {
  return new Promise((resolve) => {
    const child = spawn(tool, ['canon', db, ...(light ? [] : ['--queries'])], { stdio: ['ignore', 'pipe', 'pipe'] });
    const hash = crypto.createHash('sha256');
    let bytes = 0, err = '';
    child.stdout.on('data', (d) => { hash.update(d); bytes += d.length; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('close', (code) => resolve(code === 0 ? { ok: true, sha: hash.digest('hex'), bytes } : { ok: false, text: tail(err) }));
  });
}
function canonText(db, light = false) {
  const r = spawnSync(tool, ['canon', db, ...(light ? [] : ['--queries'])], { maxBuffer: 1 << 30 });
  return r.status === 0 ? r.stdout.toString('utf8') : null;
}
function verifyTiles(db) {
  const r = engine(['verify-tiles', db, '120']);
  if (!r.ok) return { ok: false, text: r.text };
  const v = lastJson(r.out);
  return { ok: v.누락_중복 === 0, text: `${v.타일}장 · 누락·중복 ${v.누락_중복}` };
}
/** 두 JSON 값의 첫 다른 경로(다를 때만 — 살펴보기용). */
function firstDiff(a, b, at = '') {
  if (JSON.stringify(a) === JSON.stringify(b)) return null;
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = firstDiff(a[k], b[k], `${at}/${k}`);
      if (d) return d;
    }
  }
  return `${at || '/'}: ${JSON.stringify(a)?.slice(0, 100)} ≠ ${JSON.stringify(b)?.slice(0, 100)}`;
}
/** 동시에 `jobs`개까지 돌리는 작업 줄. */
function pool(limit) {
  let running = 0;
  const waiting = [];
  const next = () => { while (running < limit && waiting.length) { running++; const { fn, resolve } = waiting.shift(); fn().then(resolve).finally(() => { running--; next(); }); } };
  return (fn) => new Promise((resolve) => { waiting.push({ fn, resolve }); next(); });
}
const queue = pool(jobs);

// ---- 묶음 ----

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'in'), { recursive: true });
/** 키 → 파일. 감독의 실자료(KoreanTimeLine)는 작업 폴더에 사본을 놓고 그 사본을 쓴다. */
const FILES = {
  ea: path.join(oracle, 'east-asia.json'), ea4: path.join(oracle, 'f4', 'east-asia.htpack'),
  move: path.join(oracle, 'move-scene.htpack'), nest: path.join(oracle, 'nest-scene.htpack'), dep: path.join(oracle, 'dep-scene.htpack'),
  d7: path.join(oracle, 'd7-test.htpack'), sphere: path.join(oracle, 'sphere-test.htpack'),
  dep4: path.join(oracle, 'f4', 'dep-scene.htpack'), nest4: path.join(oracle, 'f4', 'nest-scene.htpack'), nestj: path.join(oracle, 'nest-scene.f4.json'),
  lantern: path.join(root, 'samples', 'sample-lantern.json'),
};
let haveKtl = false;
if (fs.existsSync(ktlSource)) {
  FILES.ktl = path.join(work, 'in', path.basename(ktlSource));
  fs.copyFileSync(ktlSource, FILES.ktl);
  haveKtl = true;
}
/** DLC id(엔진 check-pack — 앱 · add-dlc와 같은 읽기). */
const idOf = new Map();
function dlcId(key) {
  if (idOf.has(key)) return idOf.get(key);
  let raw;
  if (/.json$/i.test(FILES[key])) { // .json은 본문 그대로(엔진이 add-pack · build에서 봉함)
    raw = JSON.parse(fs.readFileSync(FILES[key], 'utf8'));
  } else {
    const meta = path.join(work, 'in', `id-${key}.json`);
    const r = engine(['check-pack', FILES[key], meta]);
    if (!r.ok) throw new Error(`DLC 읽기 실패(${key} · ${FILES[key]}): ${r.text}`);
    raw = JSON.parse(fs.readFileSync(meta, 'utf8'));
    fs.rmSync(meta, { force: true });
  }
  idOf.set(key, String(raw.id));
  return String(raw.id);
}

// ---- 통째 짓기(기준) ----

const refCache = new Map(); // 조합 열쇠(키를 차례대로 이은 글) → { db, canon: Promise }
let refCount = 0;
function reference(combo, light = false) {
  const name = combo.join('+') + (light ? '|가벼움' : '');
  if (refCache.has(name)) return refCache.get(name);
  const db = path.join(work, `ref-${++refCount}.db`);
  const t0 = performance.now();
  const built = engine(['build', db, ...combo.map(k => FILES[k]), `--now=${NOW}`, `--calendar=${calendar}`, '--calendar-narrow']);
  if (!built.ok) throw new Error(`통째 짓기 실패(${name}): ${built.text}`);
  const entry = { db, name, buildMs: ms(t0), canon: queue(() => canonSha(db, light)) };
  refCache.set(name, entry);
  return entry;
}

// ---- 걷기 ----

const rows = []; // 요약 표의 줄(한 걸음에 하나)
let bad = 0, ran = 0;
const pending = []; // 비동기 견줌

/** 걸음 하나를 견주는 일을 줄 세운다(저장소는 이 시점의 사본). */
function judge({ walk, what, combo, snapshot, ms: took, answer, light }) {
  const ref = reference(combo, light);
  const row = { walk, what, combo: combo.join('+'), ms: took, scope: answer && answer.scope, rewrote: answer && `${answer.rewrote.length}/${answer.added.length}/${answer.removed.length}`, rowsAfter: answer && answer.rows_after };
  rows.push(row);
  pending.push((async () => {
    const [got, want] = await Promise.all([queue(() => canonSha(snapshot, light)), ref.canon]);
    const v = verifyTiles(snapshot);
    row.verify = v.ok ? '0' : `어긋남 — ${v.text}`;
    if (!got.ok || !want.ok) { row.same = false; row.why = `canon 실패 — ${(got.ok ? want : got).text}`; }
    else if (got.sha === want.sha) { row.same = true; }
    else {
      row.same = false;
      const [a, b] = [canonText(snapshot, light), canonText(ref.db, light)];
      row.why = a && b ? `첫 다른 곳 ${firstDiff(JSON.parse(b), JSON.parse(a))} (왼쪽 통째 · 오른쪽 넣고 뺀 것)` : 'canon 다시 풀기 실패';
      row.keep = snapshot;
    }
    row.ok = row.same && v.ok;
    if (!row.ok) bad++;
    if (row.ok && !keep) fs.rmSync(snapshot, { force: true });
  })());
}

/** 걷기 하나: 기본팩만 통째로 지은 저장소에서 시작해 `steps`('+키' · '-키')를 차례로 밟는다. 걸음마다 통째 짓기와 견준다. */
let walkCount = 0;
function walk(name, baseKey, steps, { light = false } = {}) {
  const dir = path.join(work, `walk-${++walkCount}`); // 폴더 이름은 ASCII 번호(걷기 이름이 한글이라 글자로 만들면 겹친다)
  fs.mkdirSync(dir, { recursive: true });
  const db = path.join(dir, 'archive.db');
  const start = reference([baseKey], light);
  fs.copyFileSync(start.db, db);
  let combo = [baseKey];
  let n = 0;
  for (const s of steps) {
    const sign = s[0], key = s.slice(1);
    if (!FILES[key]) { console.log(`건너뜀 ${name} ${s} — 파일이 없습니다`); continue; }
    const t0 = performance.now();
    let r;
    if (sign === '+') {
      r = engine(['add-pack', db, FILES[key]]);
      // 같은 id가 이미 있으면 그 자리에서 바꿔 넣는다(판이 같거나 높을 때) — 조합의 그 자리를 새 파일로.
      const at = combo.findIndex(k => dlcId(k) === dlcId(key));
      combo = at >= 0 ? combo.map((k, i) => (i === at ? key : k)) : [...combo, key];
    } else {
      r = engine(['remove-pack', db, dlcId(key)]);
      combo = combo.filter(k => k !== key);
    }
    ran++;
    if (!r.ok) {
      bad++;
      rows.push({ walk: name, what: `${s} → ${combo.join('+')}`, combo: combo.join('+'), ok: false, same: false, why: `엔진이 거절: ${r.text}`, verify: '—' });
      console.log(`실패 ${name} ${s} — ${r.text}`);
      return; // 이 걷기는 더 못 간다(저장소 상태를 모른다)
    }
    const answer = lastJson(r.out);
    const snapshot = path.join(dir, `step-${++n}.db`);
    fs.copyFileSync(db, snapshot);
    judge({ walk: name, what: `${s} → ${combo.join('+')}`, combo, snapshot, ms: ms(t0), answer, light });
  }
}

// ---- 이 계획 전의 저장소 ----

function oldStore() {
  const label = '이 계획 전의 저장소';
  const store = path.join(oldRoot, '동아시아', 'archive.db');
  if (!fs.existsSync(store)) {
    // HT_REQUIRE_KTL=1(감독 PC · 공식 검사)이면 옛 DLC의 약속 2(판을 올려도 사용자 DLC가 남음)가 소리 없이 빠지지 않게 실패로 센다.
    if (requireKtl()) {
      bad++;
      console.log(`실패 ${label} — 배포 폴더의 저장소가 없습니다: ${store} (HT_REQUIRE_KTL=1 — KoreanTimeLine이 든 판 3 · 3.1 저장소를 --old-root로 알려 주세요)`);
      return { skipped: false, ktl: false, checks: [{ what: '시작 저장소', ok: false, text: '저장소 없음' }] };
    }
    console.log(`건너뜀 ${label} — 배포 폴더의 저장소가 없습니다: ${store} (--old-root로 알려 주세요)`);
    return { skipped: true };
  }
  const dir = path.join(work, 'old-store');
  fs.mkdirSync(dir, { recursive: true });
  const outcome = { skipped: false, checks: [] };
  const fail = (what, text) => { outcome.checks.push({ what, ok: false, text }); bad++; console.log(`실패 ${label} — ${what}: ${text}`); };
  const pass = (what, text) => { outcome.checks.push({ what, ok: true, text }); console.log(`같음 ${label} — ${what}: ${text}`); };
  const infoOf = (db) => {
    const r = engine(['query', db, '{"op":"info"}']);
    const meta = (lastJson(r.out).data || lastJson(r.out)).meta || {};
    const j = (k) => { try { return JSON.parse(meta[k] || 'null') || {}; } catch { return {}; } };
    return { meta, keys: j('pack_keys'), info: j('pack_info'), events: j('pack_events'), periods: j('pack_periods'), tracks: j('pack_tracks'), count: Number(meta.count), now: meta.now, order: meta.pack_order };
  };
  const hasKtl = (i) => Object.values(i.keys).includes('KoreanTimeLine');
  const ktlNumber = (i) => Object.entries(i.keys).find(([, v]) => v === 'KoreanTimeLine')?.[0];
  const before = path.join(dir, 'before.db');
  fs.copyFileSync(store, before);
  const first = infoOf(before);
  const schemaOf = (i) => String(i.meta.schema ?? '');
  const stamp = `판(meta.schema) ${schemaOf(first) || '없음'} · DLC ${Object.values(first.keys).join(' · ')} · 사건 ${first.count} · 지은 날(meta.now) ${first.now ?? '없음'} · 차례(meta.pack_order) ${first.order ?? '없음'}`;
  console.log(`  ${label}: ${store}\n    사본 ${before} — ${stamp}`);
  if (!['3', '3.1'].includes(schemaOf(first))) console.log(`    알림: 시작 저장소의 판이 '3' · '3.1'이 아닙니다(${schemaOf(first) || '없음'}) — 아래 '판 4' 단언은 판을 올리는 길을 지나지 않습니다`);
  // KoreanTimeLine이 없는 저장소(배포본마다 든 DLC가 다르다 — 예: 0.0.4의 동아시아는 기본팩 + dlc-20261023)는 KoreanTimeLine이 남는지 보는 단언만
  // 건너뛴다 — DLC 넣기 · 판 4 · 통째 짓기와 같음 · 표본 대조는 그대로 보고, '받음'은 통과로 세되 글에 '건너뜀'을 적으며 끝 요약에
  // '약속 2를 진짜 자료로 보지 못함'을 따로 알린다. HT_REQUIRE_KTL=1이면 건너뛰지 않고 실패로 센다(감독 PC · 공식 검사 — KTL이 든 판 3 · 3.1 저장소로).
  outcome.ktl = hasKtl(first);
  if (!outcome.ktl) {
    if (requireKtl()) fail('시작 저장소', `KoreanTimeLine이 들어 있지 않습니다(HT_REQUIRE_KTL=1 — 옛 DLC의 약속 2를 진짜 자료로 보려면 KTL이 든 저장소를 --old-root로) — ${stamp}`);
    else console.log(`    알림: 이 저장소에는 KoreanTimeLine이 없습니다 — KoreanTimeLine이 남는지 보는 단언만 건너뜁니다(${stamp})`);
  }
  const ktlNo = outcome.ktl ? ktlNumber(first) : null;
  const ktlBefore = outcome.ktl ? { events: first.events[ktlNo] ?? 0, periods: first.periods[ktlNo] ?? 0, tracks: (first.tracks[ktlNo] || []).length } : null;
  /** 리메이크 3단계 저장소 걸음 9(계약 1-1 · 1절 '첫 apply가 만드는 것'): 판 3 · 3.1 저장소의 첫 모두 덮는 고쳐 쓰기(add_pack · 모두 덮는 apply)는
      periods.form · sphere_lines를 만들고 모든 트랙을 다시 써 판 4(열쇠와 자리가 갈린 판이면 4.1)로 적는다. */
  const checkSchema = (what, after) => {
    const s = schemaOf(after);
    (['4', '4.1'].includes(s) ? pass : fail)(`${what} — 판 4`, `meta.schema ${schemaOf(first) || '없음'} → ${s || '없음'}${['4', '4.1'].includes(s) ? '' : ' (4 · 4.1이어야 함)'}`);
  };
  const add = FILES.dep;

  // ① 엔진 add-pack
  const a = path.join(dir, 'engine.db');
  fs.copyFileSync(before, a);
  const shaBefore = fileSha(a);
  const r = engine(['add-pack', a, add]);
  if (!r.ok) {
    const same = fileSha(a) === shaBefore;
    fail('엔진 add-pack', `거절 — «${r.text}» (저장소 파일 SHA-256 ${same ? '그대로' : '**바뀜**'} · KoreanTimeLine은 ${same ? '남음(아무것도 안 바뀜) — 그러나 DLC는 들지 못함' : '?'})`);
  } else {
    const after = infoOf(a);
    const answer = lastJson(r.out);
    const took = `DLC ${Object.values(after.keys).join(' · ')} · 다시 쓴/든 트랙 ${answer.rewrote.length}/${answer.added.length} · 범위 ${answer.scope} · ${Math.round(answer.ms)}ms`;
    if (!outcome.ktl) pass('엔진 add-pack', `받음(KoreanTimeLine 없는 저장소 — 그 단언은 건너뜀) · ${took}`);
    else {
      const kept = hasKtl(after) && ((after.events[ktlNumber(after)] ?? 0) === ktlBefore.events) && ((after.periods[ktlNumber(after)] ?? 0) === ktlBefore.periods);
      if (!kept) fail('엔진 add-pack', `받았지만 KoreanTimeLine이 달라졌습니다 — 전 ${JSON.stringify(ktlBefore)} · 뒤 ${JSON.stringify({ events: after.events[ktlNumber(after)] ?? 0, periods: after.periods[ktlNumber(after)] ?? 0 })}`);
      else pass('엔진 add-pack', `받음 — KoreanTimeLine 남음(사건 ${ktlBefore.events} · 띠 ${ktlBefore.periods} · 트랙 ${ktlBefore.tracks}) · ${took}`);
    }
    checkSchema('엔진 add-pack', after);
    // 통째 지은 것과 견주려면 저장소 안의 원본을 꺼내 같은 날(저장소에 적힌 meta.now)로 짓는다.
    const dirOut = path.join(dir, 'originals');
    fs.mkdirSync(dirOut, { recursive: true });
    const outs = [];
    for (const [no, id] of Object.entries(after.keys)) {
      const f = path.join(dirOut, `${no}.htpack`);
      const o = engine(['pack-out', a, id, f]);
      if (o.ok) outs.push(f);
    }
    if (outs.length === Object.keys(after.keys).length) {
      const ref = path.join(dir, 'engine-ref.db');
      const built = engine(['build', ref, ...outs, `--now=${after.now}`, `--calendar=${calendar}`, '--calendar-narrow']);
      if (built.ok) {
        pending.push((async () => {
          const [x, y] = await Promise.all([queue(() => canonSha(a)), queue(() => canonSha(ref))]);
          const same = x.ok && y.ok && x.sha === y.sha;
          (same ? pass : fail)('엔진 add-pack 뒤 = 저장소 안 원본으로 통째 지은 것', same ? 'canon --queries 같음' : `canon 다름 또는 실패 ${x.text || y.text || ''}`);
        })());
      } else fail('엔진 add-pack 뒤 통째 짓기', built.text);
    }
  }

  // ② 지금 앱의 길(add-dlc.mjs --apply — Node 배치 → apply-layout)
  const b = path.join(dir, 'node', 'archive.db');
  fs.mkdirSync(path.dirname(b), { recursive: true });
  fs.copyFileSync(before, b);
  const t0 = performance.now();
  const n = spawnSync(process.execPath, [path.join(scripts, 'add-dlc.mjs'), b, '--apply', add], { encoding: 'utf8', env: { ...process.env, HT_ARCHIVE_TOOL: tool }, maxBuffer: 1 << 26 });
  if (n.status !== 0) {
    fail('지금 앱의 길(add-dlc --apply)', `실패(종료 ${n.status}): ${tail(n.stderr || n.stdout)}`);
  } else {
    const after = infoOf(b);
    if (!outcome.ktl) pass('지금 앱의 길(add-dlc --apply)', `받음(KoreanTimeLine 없는 저장소 — 그 단언은 건너뜀) · DLC ${Object.values(after.keys).join(' · ')} · 모두 ${ms(t0)}ms`);
    else {
      const no = ktlNumber(after);
      const kept = hasKtl(after) && (after.events[no] ?? 0) === ktlBefore.events && (after.periods[no] ?? 0) === ktlBefore.periods && (after.tracks[no] || []).length === ktlBefore.tracks;
      (kept ? pass : fail)('지금 앱의 길(add-dlc --apply)', `${kept ? `KoreanTimeLine 남음(사건 ${ktlBefore.events} · 띠 ${ktlBefore.periods} · 트랙 ${ktlBefore.tracks})` : `KoreanTimeLine이 달라짐 ${JSON.stringify(ktlBefore)} → ${JSON.stringify({ events: after.events[no] ?? 0, periods: after.periods[no] ?? 0, tracks: (after.tracks[no] || []).length })}`} · DLC ${Object.values(after.keys).join(' · ')} · 모두 ${ms(t0)}ms`);
    }
    checkSchema('지금 앱의 길(add-dlc --apply)', after);
    const v = verifyTiles(b);
    (v.ok ? pass : fail)('지금 앱의 길 — 표본 대조', v.text);
  }
  return outcome;
}

// ---- 돌리기 ----

const t00 = performance.now();
let storeOutcome = null;
try {
  if (only.has('walk')) {
    const each = ['ktl', 'move', 'nest', 'dep', 'd7', 'sphere'].filter(k => FILES[k]);
    if (walks.has('each')) for (const d of each) walk(`하나씩 ${d}`, 'ea', [`+${d}`, `-${d}`]);
    if (walks.has('stack')) walk('쌓기', 'ea', ['+ktl', '+move', '+nest', '-move', '+dep', '-ktl', '+d7', '-nest', '+sphere', '-dep', '-d7', '-sphere']);
    if (walks.has('lantern')) walk('등불(가벼운 canon)', 'lantern', ['+d7', '+sphere', '-d7', '-sphere'], { light: true });
    if (walks.has('f4')) walk('형식 4', 'ea', ['+dep4', '+nest4', '+ea4', '-dep4']);
    if (walks.has('f4json')) walk('형식 4 JSON', 'ea', ['+nestj', '-nestj']);
  }
  if (only.has('store')) storeOutcome = oldStore();
} catch (e) {
  console.error(`중단 — ${e.message}`);
  process.exit(1);
}
await Promise.all(pending);

// ---- 요약 ----

console.log('\n걷기(고쳐 쓴 저장소 = 그 조합을 통째로 지은 것?)');
console.log('| 걷기 | 걸음 | 같음 | 표본 누락·중복 | 다시 쓴/든/뺀 트랙 | 범위 | 줄 | ms |');
console.log('| --- | --- | --- | --- | --- | --- | ---: | ---: |');
for (const r of rows) console.log(`| ${r.walk} | ${r.what} | ${r.ok ? '같음' : '**다름**'} | ${r.verify ?? '—'} | ${r.rewrote ?? '—'} | ${r.scope ?? '—'} | ${r.rowsAfter ?? '—'} | ${r.ms ?? '—'} |`);
for (const r of rows.filter(x => !x.ok)) console.log(`  ✗ ${r.walk} ${r.what}: ${r.why || ''}`);
if (!haveKtl && only.has('walk')) console.log(`\n건너뛴 걸음: KoreanTimeLine 파일이 없어(${ktlSource}) ktl이 든 걸음은 돌리지 않았습니다.`);
if (storeOutcome && !storeOutcome.skipped && !storeOutcome.ktl && !requireKtl()) {
  console.log('\n건너뛴 단언: 시작 저장소에 KoreanTimeLine이 없어 옛 DLC의 약속 2(판 3 · 3.1 → 4로 올려도 사용자 DLC가 남음)를 진짜 자료로 보지 못했습니다'
    + ' — 감독 PC에서 KTL이 든 저장소로 HT_REQUIRE_KTL=1 node prototype/scripts/old-dlc-check.mjs --only=store --old-root=<자료 폴더>');
}
const total = rows.length + (storeOutcome && !storeOutcome.skipped ? storeOutcome.checks.length : 0);
console.log(`\n${total - bad}/${total} 같음 · ${ms(t00) / 1000}초 · 엔진 ${tool}`);
if (!total) { console.error('돌린 걸음이 없습니다'); process.exit(1); }
if (bad) {
  console.error(`${bad}건이 같지 않거나 거절되었습니다 — 살펴볼 폴더: ${work}`);
  process.exit(1);
}
if (!keep) fs.rmSync(work, { recursive: true, force: true });
const walkSaid = only.has('walk') ? '옛 DLC 묶음을 넣고 빼도 통째 짓기와 같습니다' : '';
const storeSaid = !storeOutcome || storeOutcome.skipped ? ''
  : storeOutcome.ktl ? '옛 저장소는 KoreanTimeLine을 지닌 채 받아 판 4로 적혔습니다' : '옛 저장소는 받아 판 4로 적혔습니다(KoreanTimeLine이 없는 저장소 — 그 단언은 건너뜀)';
console.log(`모두 같음 — ${[walkSaid, storeSaid].filter(Boolean).join(' · ')}.`);

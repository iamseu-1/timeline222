// Rust로 짓기 확인(한 벌 P3 과제 17 걸음 1 · 3): 같은 조합의 저장소를 두 길로 지어 같은지 본다.
//   ① Node 길 — 정답지와 같은 시각 · 시간대로 Node 내보내기(oracle/combo.mjs — export/base.mjs의 contextOf · runModules 그대로) → archive-tool import-layout
//   ② Rust 길 — archive-tool build(엔진이 배치하고 짓는다 · --now=<같은 시각> · --calendar=<전체 달력 표 — 판정 R36>)
//   두 저장소의 `archive-tool canon --queries`(번호 없이 적은 layout · 풀어 낸 타일 · 조회 · 수 세기)가 같고, 둘 다 `verify-tiles 120`이 누락 · 중복 0이며,
//   Rust 저장소의 meta가 지은 날(`meta.now` = 준 시각) 말고 Node 저장소와 같고 달력 표(`blobs`의 `calendar:table`)가 준 표 그대로여야 한다.
//   등불 연대기를 기본으로 한 자료(형식 3 · 형식 4 사본 · +d7+sphere)는 글이 많아 canon을 성긴 단계로(`--levels=8,11,14 --max-x=8` · 조회 없이 — `--full-canon`이면
//   모두 `--queries`). 그때 덜 보는 것: 촘촘한 단계(0 · 4 · 7)의 타일 · 가로 8열 너머 · 조회 목록(검색 · 이름 찾기 · 관점 이름 · 항목 기록 · 변형 보기의 답).
//   그 대신 저장소의 행을 직접 견준다: 항목 기록(uid · 갈래 · json 글) · 이름 표(갈래 · uid · 이름 · 덧말 · 기간 · 색 · 칸 참조 · 찾을 글) · 출처(제목 · 본문).
//   스키마 4(계약 1-1 · 리메이크 3단계)의 띠 `form`(uid · 기간과 함께)과 문화권 단위 줄 `sphere_lines`(번호 없이 · 넣은 차례)는 **모든 자료에서** 행으로 견준다
//   (canon이 아직 싣지 않는다 — 옛 저장소처럼 열 · 표가 없으면 빈 목록).
// 모듈 스물이 모두 Rust로 옮겨지기 전에는 ② Rust 길이 옮기지 않은 모듈의 이름을 담아 거절한다 — 그때는 실패(종료 1)로 끝나는 것이 맞다(걸음 1의 RED).
// Node 배치는 모든 자료를 Node 한 번으로 뽑는다(oracle/combo.mjs 일감 여럿 — 웹 코드를 한 번만 싣는다).
//
// 사용: node prototype/scripts/build-check.mjs [--only=<자료>,…] [--work=<폴더>] [--calendar=<표>] [--keep] [--full-canon]
//   --only       돌릴 자료(아래 목록의 이름 · 쉼표). 기본 모두.
//   --work       임시 저장소 · 배치를 둘 폴더(기본 <TMP>/build-check — 처음에 비우고, 다 같으면 끝에 지운다. 어긋나면 살펴보게 남긴다).
//   --calendar   달력 표(기본 prototype/results/calendar-cache.json — 없으면 warm-calendar.mjs로 기본 범위(−3500 ~ 2500년)를 떠서 만든다).
//                이 도구는 그 파일을 읽기만 한다 — Node 배치에는 사본(제 TMP의 임시 폴더)만 주어 Node가 표를 넓혀 쓰더라도 준 파일은 바이트 그대로다(판정 R64-1).
//   --keep       다 같아도 그 폴더를 남긴다.
//   --full-canon 등불 자료도 canon --queries(몇 시간 걸릴 수 있다).
//   (환경 변수) HT_ARCHIVE_TOOL=<archive-tool 경로>.
// 자료: 기준 셋(prototype/fixtures/oracle/list.json — 등불 · 동아시아 · +KoreanTimeLine(감독 PC에 파일이 있을 때) · 리메이크 시험 DLC · 합성 · 형식 4 사본)
//       + 가상 묶음(BUNDLES — 같은 DLC를 다른 차례로 · 등불 위에 시험 DLC).
//       list.json에서 `"calClip": true`로 표지한 자료(`synth-calclip` — 판정 R64-2)는 `--only`로 이름을 짚을 때만 돌린다(까닭은 아래 `sets`의 주석).
// 원본: 입력 .json은 본문 바이트 그대로 .htpack으로 싸서(엔진 legacy::seal_dlc와 같은 꼴) 두 길에 같은 파일을 준다.
// 종료 코드: 0 = 모두 같음 · 누락 · 중복 0 / 1 = 어긋남 · 거절 · 실패가 있음 / 2 = 사용법.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { listFile, missingNote } from './oracle/ktl.mjs';

/** 정답지와 같은 '오늘'과 시간대(oracle/one.mjs · tests/common/oracle.rs와 같은 값). */
const NOW = '2026-10-15T12:00:00+09:00';
const TZ = 'Asia/Seoul';
const TZ_MIN = 540;

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const root = path.resolve(prototype, '..');
const fixDir = path.join(prototype, 'fixtures', 'oracle');
const args = process.argv.slice(2);
const option = (name) => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : ''; };
const unknown = args.filter(a => a !== '--keep' && a !== '--full-canon' && !/^--(only|work|calendar)=/.test(a));
if (unknown.length) {
  console.error(`모르는 인자: ${unknown.join(' ')}\n사용: node prototype/scripts/build-check.mjs [--only=<자료>,…] [--work=<폴더>] [--calendar=<표>] [--keep] [--full-canon]`);
  process.exit(2);
}
const keep = args.includes('--keep');
const fullCanon = args.includes('--full-canon');
const calendar = path.resolve(option('calendar') || path.join(prototype, 'results', 'calendar-cache.json'));
/** 표의 years가 기본(−3500 ~ 2500 — `archive-tool build`가 받는 범위)을 덮는가. 읽지 못하면 거짓. */
const wide = (file) => { try { const [lo, hi] = JSON.parse(fs.readFileSync(file, 'utf8')).years || []; return lo <= -3500 && hi >= 2500; } catch { return false; } };
if (!fs.existsSync(calendar) || !wide(calendar)) {
  // 기본 자리의 캐시가 좁으면(Node 내보내기가 자료 해만큼 떠 둔 것 등) 기본 범위로 다시 뜬다. --calendar로 준 표는 덮어쓰지 않고 멈춘다.
  if (fs.existsSync(calendar) && option('calendar')) { console.error(`준 달력 표가 기본 범위(−3500 ~ 2500년)보다 좁습니다: ${calendar}`); process.exit(2); }
  console.log(`달력 표가 없거나 좁아 뜹니다(warm-calendar.mjs — 기본 범위): ${calendar}`);
  const r = spawnSync(process.execPath, [path.join(scripts, 'warm-calendar.mjs'), `--file=${calendar}`], { stdio: 'inherit' });
  if (r.status !== 0 || !fs.existsSync(calendar)) { console.error('달력 표를 뜨지 못했습니다'); process.exit(1); }
}
const calendarBytes = fs.readFileSync(calendar);
// 저장소를 읽는 데 node:sqlite(실험 기능 — 경고 한 줄을 끈다).
const realWarn = process.emitWarning;
process.emitWarning = (w, ...rest) => (String(w).includes('SQLite') ? undefined : realWarn.call(process, w, ...rest));
const { DatabaseSync } = await import('node:sqlite');
const work = path.resolve(option('work') || path.join(process.env.TMP || process.env.TEMP || os.tmpdir(), 'build-check'));

const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [process.env.HT_ARCHIVE_TOOL || '', ...[prototype, path.join(prototype, 'engine', 'target', 'release')].flatMap(dir => toolNames.map(n => path.join(dir, n)))]
  .find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) { console.error(`엔진 도구(${toolNames[0]})가 없습니다 — 먼저 cargo build --release --locked.`); process.exit(1); }

// ---- 자료 ----

const abs = (file) => (path.isAbsolute(file) ? file : path.join(fixDir, file));
/** 기준 셋: list.json의 자료(입력 파일 — Rust 검사 `tests/common/oracle.rs`의 inputs와 같은 해석: sample → file → 굳힌 <내장>.json). */
const listRaw = JSON.parse(fs.readFileSync(path.join(fixDir, 'list.json'), 'utf8'));
/** 판정 R64-2: `"calClip": true` 표지 자료 — 자료 해 ± 100년이 저장소 달력 표(−3500 ~ 2500년) 밖으로 나가, Rust가 표 밖을 생략한다(판정 R61 · 과제 calclip).
 *  `<이름>@f4`(형식 4 사본)는 `@f4`를 뗀 이름의 표지를 따른다. */
const clipNames = new Set(listRaw.filter(f => f.calClip === true).map(f => f.name));
const isCalClip = (name) => clipNames.has(name.replace(/@f4$/, ''));
const listed = listRaw.map(f => {
  const base = f.base.sample ? path.join(root, 'samples', `${f.base.sample}.json`) : f.base.file ? abs(f.base.file) : path.join(fixDir, `${f.base.builtin}.json`);
  return { name: f.name, files: [base, ...(f.extra || []).map(x => listFile(fixDir, x))], optional: !!f.optional, calClip: isCalClip(f.name) }; // 옛 KTL 자리는 HT_KTL로
});
/** 가상 묶음 — 같은 DLC를 다른 차례로(차례가 트랙 주인 · 같은 uid의 이김을 정한다) · 등불 위에 시험 DLC(동아시아 밖 기본 DLC). */
const BUNDLES = [
  { name: 'synth+patch2+patch', files: ['synth.json', 'synth-patch2.json', 'synth-patch.json'].map(abs) },
  { name: 'lantern+d7+sphere', files: [path.join(root, 'samples', 'sample-lantern.json'), abs('d7-test.htpack'), abs('sphere-test.htpack')] },
  { name: 'east-asia+nest+move', files: ['east-asia.json', 'nest-scene.htpack', 'move-scene.htpack'].map(abs) },
];
const only = new Set(option('only').split(',').filter(Boolean));
const all = [...listed, ...BUNDLES];
for (const k of only) if (!all.some(s => s.name === k)) { console.error(`모르는 자료: ${k} (있는 것: ${all.map(s => s.name).join(' · ')})`); process.exit(2); }
// 표지(calClip) 자료는 이름으로 짚지 않으면 뺀다 — 쉬운 쪽을 골랐다: Node는 모자란 표를 ICU로 다시 떠 표 밖까지 싣고 Rust는 표 밖을 생략하므로(`cal:` 기록의 json이
// 다르다 — 알려진 차이는 Rust 검사 `tests/common/oracle.rs`의 `cal_clip_known`이 지킨다) canon이 `/queries/entity/cal:*`에서 어긋나는 것이 맞고, `cal:` 기록만 거르면
// canon을 통째로 짜 맞춰야 한다. 이름을 짚으면(`--only=synth-calclip`) 그대로 돌려 본다(저장소 달력 표가 자료 범위를 덮는 `--calendar`를 주면 같다).
const sets = all.filter(s => (!only.size && !s.calClip) || only.has(s.name));
const skippedClip = only.size ? [] : all.filter(s => s.calClip);
for (const s of skippedClip) console.log(`건너뜀 ${s.name} — 달력 잘림 자료(list.json의 calClip): Rust는 표 밖을 생략해 \`cal:\` 기록이 Node와 다르다(판정 R61)`);

// ---- 도구 ----

const ms = (t0) => Math.round(performance.now() - t0);
const tail = (r) => String(r.stderr || r.stdout || r.error || '').trim().split('\n').filter(l => !l.startsWith('    at ')).slice(-6).join('\n');
const lastJson = (text) => JSON.parse(String(text).trim().split('\n').pop());
const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
/** 엔진 도구를 부른다 — { ok, out(글 또는 바이트), text(실패 까닭), ms }. */
function engine(list, { bytes = false } = {}) {
  const t0 = performance.now();
  const r = spawnSync(tool, list, { encoding: bytes ? null : 'utf8', maxBuffer: 1 << 30 });
  return { ok: r.status === 0, out: r.stdout, text: tail({ stderr: r.stderr && r.stderr.toString(), stdout: r.stdout && !bytes ? r.stdout : '', error: r.error }), ms: ms(t0) };
}
/** 본문 바이트 그대로 DLC 전용 팩(.htpack 규격 2 · 종류 1)으로 — 엔진 `legacy::seal_dlc`와 같은 꼴(머리 20 + 지문 32 + zlib 본문). */
function seal(plain) {
  const body = zlib.deflateSync(plain);
  const head = Buffer.alloc(20);
  Buffer.from('HTPACK\r\n', 'latin1').copy(head, 0);
  head.set([2, 1, 1, 0], 8);
  head.writeUInt32LE(plain.length, 12);
  head.writeUInt32LE(body.length, 16);
  const digest = crypto.createHash('sha256').update(head).update(body).digest();
  return Buffer.concat([head, digest, body]);
}
/** Node 통째 배치(정답지와 같은 시각 · 시간대) — 일감 전부를 oracle/combo.mjs 한 번으로. 답: { ok, text, ms: 일감마다 ms }.
 *  판정 R64-1: Node의 calendar 모듈(export/calendar.mjs `cachedTables`)은 자료 해 범위가 표 파일을 덮지 못하면 표를 **넓혀 그 파일을 갈아 쓴다** —
 *  그 파일이 Rust 길에 주는 `--calendar` 표(또는 공용 `prototype/results/calendar-cache.json`)면 검사 중에 그 바이트가 바뀐다. 그래서 Node에는
 *  준 표의 **임시 사본**(제 TMP — `HT_CALENDAR_CACHE`)만 쓰게 하고, 사본은 끝나면(실패해도) 지운다. 준 표 파일은 이 도구가 읽기만 한다. */
function nodeLayouts(jobs) {
  const list = path.join(work, 'jobs.json');
  fs.writeFileSync(list, JSON.stringify(jobs));
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'build-check-cal-'));
  try {
    const nodeCalendar = path.join(scratch, 'calendar-cache.json');
    fs.writeFileSync(nodeCalendar, calendarBytes);
    const r = spawnSync(process.execPath, [path.join(scripts, 'oracle', 'combo.mjs'), `--jobs=${list}`],
      { encoding: 'utf8', env: { ...process.env, TZ, HT_ORACLE_NOW: NOW, HT_ORACLE_TZ_MIN: String(TZ_MIN), HT_CALENDAR_CACHE: nodeCalendar }, maxBuffer: 1 << 26 });
    return { ok: r.status === 0, text: tail(r), ms: r.status === 0 ? lastJson(r.stdout).ms : [] };
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}
/** 저장소 행의 덧 견줌(번호 없이 · 정렬 — 고르는 칸 모두가 정렬 열쇠 · 문화권 단위 줄만은 넣은 차례 = 답의 차례).
 *  - 모든 자료: 스키마 4의 띠 form · 문화권 단위 줄(열 · 표가 없는 저장소는 빈 목록 — blobs 가림과 같은 꼴).
 *  - 성긴 canon 자료(`light`)만: 항목 기록 · 이름 표 · 출처 행. */
function storeRows(db, light) {
  const d = new DatabaseSync(db, { readOnly: true });
  try {
    const hasForm = d.prepare("SELECT 1 FROM pragma_table_info('periods') WHERE name='form'").get();
    const hasLines = d.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='sphere_lines'").get();
    const rows = {
      forms: hasForm ? d.prepare('SELECT uid,start,end,form FROM periods ORDER BY uid,start,end,form').all().map(r => [r.uid, r.start, r.end, r.form]) : [],
      sphereLines: hasLines ? d.prepare('SELECT pack,sphere,kind,start,end,name,uid,color,data FROM sphere_lines ORDER BY id').all()
        .map(r => [r.pack, r.sphere, r.kind, r.start, r.end, r.name, r.uid, r.color, r.data]) : [],
    };
    if (!light) return rows;
    return {
      ...rows,
      entities: d.prepare('SELECT uid,kind,json FROM entities ORDER BY uid').all().map(r => [r.uid, r.kind, r.json]),
      names: d.prepare('SELECT kind,uid,name,sub,start,end,color,cell_ref,hay FROM names ORDER BY kind,uid,name,start,end,sub,hay,color,cell_ref').all()
        .map(r => [r.kind, r.uid, r.name, r.sub, r.start, r.end, r.color, r.cell_ref, r.hay]),
      sources: d.prepare('SELECT title,body FROM sources ORDER BY title,body').all().map(r => [r.title, r.body]),
    };
  } finally { d.close(); }
}
/** 저장소의 meta(열쇠 → 글)와 달력 표(풀어 낸 바이트 · 없으면 null). */
function storeMeta(db) {
  const d = new DatabaseSync(db, { readOnly: true });
  try {
    const meta = Object.fromEntries(d.prepare('SELECT key,value FROM meta ORDER BY key').all().map(r => [r.key, r.value]));
    const hasBlobs = d.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='blobs'").get();
    const row = hasBlobs ? d.prepare("SELECT bytes FROM blobs WHERE key='calendar:table'").get() : null;
    return { meta, table: row ? zlib.inflateSync(Buffer.from(row.bytes)) : null };
  } finally { d.close(); }
}
function verifyTiles(db) {
  const r = engine(['verify-tiles', db, '120']);
  if (!r.ok) return { ok: false, text: r.text };
  const v = lastJson(r.out);
  return { ok: v.누락_중복 === 0, text: `${v.타일}장 · 누락·중복 ${v.누락_중복}` };
}
/** 두 canon 출력의 첫 다른 경로(다를 때만 — 살펴보기용). */
function firstDiff(a, b, at = '') {
  if (JSON.stringify(a) === JSON.stringify(b)) return null;
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = firstDiff(a[k], b[k], `${at}/${k}`);
      if (d) return d;
    }
  }
  return `${at || '/'}: ${JSON.stringify(a)?.slice(0, 120)} ≠ ${JSON.stringify(b)?.slice(0, 120)}`;
}

// ---- 돌리기 ----

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
console.log(`달력 표: ${calendar} · ${JSON.parse(calendarBytes.toString('utf8')).years?.join(' ~ ')}년 · 글 ${calendarBytes.length}바이트 · zlib ${zlib.deflateSync(calendarBytes).length}바이트`);
let bad = 0, ran = 0;
// 1) 자료마다 원본을 싸 두고 Node 일감을 모은다(.htpack은 그대로 · .json은 본문 바이트 그대로 싼다 — 두 길에 같은 파일).
const todo = [];
for (const set of sets) {
  const missing = set.files.filter(f => !fs.existsSync(f));
  if (missing.length) {
    if (set.optional) { const note = missingNote(set.name, missing); console.log(note.text); if (note.fail) bad++; continue; } // HT_REQUIRE_KTL=1이면 KTL이 없을 때 실패
    console.log(`실패 ${set.name} — 파일이 없습니다: ${missing.join(' · ')}`);
    bad++;
    continue;
  }
  const dir = path.join(work, set.name.replace(/[^\w.-]/g, '_'));
  fs.mkdirSync(dir, { recursive: true });
  const packs = set.files.map((f, i) => {
    if (/\.htpack$/i.test(f)) return f;
    const out = path.join(dir, `${i}-${path.basename(f, path.extname(f))}.htpack`);
    fs.writeFileSync(out, seal(fs.readFileSync(f)));
    return out;
  });
  todo.push({ set, dir, packs, layout: path.join(dir, 'node-layout.json') });
}
const t0 = performance.now();
const node = todo.length ? nodeLayouts(todo.map(t => ({ packs: t.packs, out: t.layout }))) : { ok: true, ms: [] };
if (!node.ok) { console.error(`Node 배치 실패: ${node.text}`); process.exit(1); }
console.log(`Node 배치 ${todo.length}개 — ${ms(t0)}ms(한 프로세스)`);
// 2) 자료마다 두 길로 짓고 견준다.
for (const [k, { set, dir, packs, layout }] of todo.entries()) {
  ran++;
  const [basePack, ...extras] = packs;
  const nodeDb = path.join(dir, 'node.db'), rustDb = path.join(dir, 'rust.db');
  const imported = engine(['import-layout', basePack, layout, nodeDb, ...extras]);
  if (!imported.ok) { console.log(`실패 ${set.name} — Node 길 짓기: ${imported.text}`); bad++; continue; }
  const built = engine(['build', rustDb, ...packs, `--now=${NOW}`, `--calendar=${calendar}`]);
  if (!built.ok) { console.log(`실패 ${set.name} — Rust 길: ${built.text}`); bad++; continue; }
  const light = !fullCanon && /^sample-lantern\.(json|htpack)$/i.test(path.basename(set.files[0])); // 등불 견본(형식 3 · 형식 4 사본)
  const canonArgs = light ? ['--levels=8,11,14', '--max-x=8'] : ['--queries'];
  const [a, b] = [rustDb, nodeDb].map(db => engine(['canon', db, ...canonArgs], { bytes: true }));
  if (!a.ok || !b.ok) { console.log(`실패 ${set.name} — canon: ${(a.ok ? b : a).text}`); bad++; continue; }
  const same = sha(a.out) === sha(b.out);
  const [va, vb] = [rustDb, nodeDb].map(verifyTiles);
  // meta: Rust 저장소의 지은 날 = 준 시각 · 나머지는 Node 저장소와 같음 · 달력 표는 준 표 그대로(Node 길에는 없음).
  const [ra, rb] = [rustDb, nodeDb].map(storeMeta);
  const metaBad = [];
  if (ra.meta.now !== NOW) metaBad.push(`meta.now ${ra.meta.now} ≠ ${NOW}`);
  // 규칙 판(meta.rules — 판정 R59 I-1 · R69-2): Rust 짓기만 '이 원본의 Rust 통째 배치'를 약속해 적고, 바깥 배치(Node → import-layout)는 적지 않는다(16b 뒤 —
  // 그 뒤 이 도구가 모든 자료에서 '다름'이던 것을 testinfra에서 맞춤). 그래서 Rust 쪽에 있고 · Node 쪽에 없음만 보고 견줌에서는 뺀다.
  if (!ra.meta.rules) metaBad.push('Rust 저장소에 meta.rules(규칙 판)가 없음');
  if (rb.meta.rules !== undefined) metaBad.push(`Node 길 저장소에 meta.rules가 있음(${rb.meta.rules}) — 바깥 배치는 규칙 판을 적지 않는다`);
  const strip = (m) => Object.fromEntries(Object.entries(m).filter(([key]) => key !== 'now' && key !== 'rules'));
  const metaDiff = firstDiff(strip(ra.meta), strip(rb.meta));
  if (metaDiff) metaBad.push(`meta ${metaDiff}`);
  if (!ra.table || !ra.table.equals(calendarBytes)) metaBad.push(ra.table ? '달력 표가 준 것과 다름' : '달력 표 없음');
  const [rowsA, rowsB] = [rustDb, nodeDb].map(db => storeRows(db, light));
  const rowsDiff = firstDiff(rowsA, rowsB);
  if (rowsDiff) metaBad.push(`행 ${rowsDiff}`);
  const f4 = `form≠0 띠 ${rowsA.forms.filter(r => r[3]).length} · 문화권 단위 줄 ${rowsA.sphereLines.length}`;
  const line = `Node ${node.ms[k] + imported.ms}ms · Rust ${built.ms}ms · canon ${light ? '성긴 단계 + 기록 · 이름 · 출처 행' : '--queries'} · ${f4} · 표본 Rust ${va.text} / Node ${vb.text}`;
  if (same && va.ok && vb.ok && !metaBad.length) { console.log(`같음 ${set.name} — ${line}`); continue; }
  bad++;
  const where = same ? '' : ` · 첫 다른 곳 ${firstDiff(JSON.parse(a.out.toString('utf8')), JSON.parse(b.out.toString('utf8')))}`;
  console.log(`다름 ${set.name} — canon ${same ? '같음' : '다름'}${where}${metaBad.length ? ` · ${metaBad.join(' · ')}` : ''} · ${line}`);
}
if (!ran) { console.error('돌린 자료가 없습니다'); process.exit(1); }
if (bad) {
  console.error(`${ran}개 가운데 ${bad}개가 같지 않거나 실패했습니다 — 살펴볼 폴더: ${work}`);
  process.exit(1);
}
if (!keep) fs.rmSync(work, { recursive: true, force: true });
console.log(`모두 같음 — ${ran}개 자료(Node 길 = Rust 길 · 누락 · 중복 0)`);

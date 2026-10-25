// 릴리즈 저장소 짓기 — 릴리즈(독립형 연표 앱 · HistoryArchive 연표 모듈의 seed)가 싣는 저장소를 한 번에 짓는다.
// 감독 지시(2026-10-12): "기능 다 총동원" → (2026-10-14) "나머지 견본 dlc 모두 지우기 · 견본 dlc는 하나로" — 견본은 이제
// 따로 세계 하나인 samples/sample-lantern.json(등불 연대기 — 아홉 불씨의 대륙)뿐이고, 그 한 벌이 연표의 기능을 모두 보여 준다.
//
// 사용: node prototype/scripts/build-showcase.mjs <출력 폴더> [--stores=showcase,lantern,east-asia] [--tool=<archive-tool>] [--exclude=<견본 이름>,…] [--strict]
//         [--calendar=<calendar-cache.json>] [--now=<ISO 시각 — 시간대를 적은 글>]
//   <출력 폴더>      새 폴더(또는 빈 폴더). 이미 지은 저장소는 덮어쓰지 않는다 — 다시 지을 때는 새 폴더를 준다.
//   --stores=…      지을 저장소(쉼표). 기본 = showcase + 따로 세계인 견본 전부(지금은 lantern). east-asia(기본팩만)는 달라고 할 때만
//                   (기본팩 위에 얹을 견본이 없는 지금은 showcase와 내용이 같다).
//   --tool=…        엔진 도구(archive-tool). 없으면 환경 변수 HT_ARCHIVE_TOOL → prototype/engine/target/release/archive-tool(.exe).
//                   먼저 `cargo build --locked --release --manifest-path prototype/engine/Cargo.toml`.
//   --exclude=…     이번에만 더 뺄 견본(파일 이름에서 'sample-'과 '.json'을 뗀 것 · 쉼표).
//   --strict        아래 규칙 4의 '짓기가 거절한 견본'을 빼지 않고 멈춘다(종료 코드 1).
//   --calendar=…    저장소마다 넣을 달력 표(warm-calendar.mjs가 뜬 calendar-cache.json — 전체 표 · 판정 R36). 없으면 <출력>/calendar-cache.json에
//                   warm-calendar.mjs --years=-3500,2500(달력 다섯)으로 이 Node가 떠서 쓴다(40초 남짓). 준 표가 그보다 좁거나 달력이 모자라면 알린다.
//                   목록(showcase.json)의 calendar.file은 출력 폴더에서 본 상대 자리다.
//   --now=…         저장소의 '오늘'(meta.now — 진행 중 정권의 끝 · 문서의 나이). `2026-10-22T12:00:00+09:00` 꼴(초까지 · 시간대를 꼭 적는다 — Z는 받지 않음 ·
//                   엔진 legacy::iso_time과 같은 꼴만 받는다).
//                   없으면 지금 시각을 +09:00(서울)으로 적는다. 한 번 돌림의 저장소는 모두 같은 '오늘'로 짓는다.
//
// 출력(저장소마다 폴더 하나 + 목록 하나):
//   <출력>/showcase/archive.db          동아시아: 동아시아 기본팩(packs/east-asia) 저장소 — 기본으로 여는 것(안드로이드 APK의 seed는 release.yml의
//                                      ANDROID_SEED가 고른 저장소 — 지금은 lantern(판타지 판) · showcase로 바꾸면 이것).
//                                      samples/에 기본팩 위에 얹는 견본(분류가 world가 아닌 것)이 생기면 그것을 모두 얹는다(지금은 없음).
//   <출력>/showcase/DLC/<견본>.htpack   (얹은 견본이 있을 때만) 얹은 견본 DLC의 원본(samples/<견본>.json을 메이커와 같은 저장기 js/packfile.js로 싼 것) —
//                                      짓기의 입력이고 저장소 안(packs.original)에도 품어진다. 꾸러미(bundle-app.mjs)가 앱의 DLC/ 폴더에 함께 둔다
//                                      (앱이 판 올림 뒤 DLC/ 폴더에서 다시 들이는 일(판정 R32)은 저장소에 이미 든 것을 건너뛴다). 기본팩은 두지 않는다.
//   <출력>/showcase/base.htpack         기본팩 원본(동아시아) — 저장소에도 품어져 있다. seed를 따로 짓는 쪽(HistoryArchive)과 꾸러미
//                                      (도구\prototype\results\compat\east-asia.htpack — 바탕이 아닌 자리에서 뺀 기본팩을 되살릴 때 고르는 파일)가 쓴다.
//   <출력>/lantern/archive.db           등불 연대기: 따로 세계 하나인 가상 견본(samples/sample-lantern.json) — 기본팩 없이 그것만으로.
//   <출력>/lantern/base.htpack          그 견본의 원본(.htpack) — 릴리즈가 견본 DLC 파일로 따로도 올린다(release.yml의 release 작업).
//   <출력>/east-asia/archive.db         (--stores에 넣었을 때) 동아시아 기본팩만.
//   <출력>/calendar-cache.json          (--calendar가 없을 때) 이번에 뜬 달력 표 — 저장소마다 통째로 들었다(blobs의 calendar:table).
//   <출력>/showcase.json                목록: 저장소마다 폴더 · 이름 · 바이트 · SHA-256 · 지은 시간 · 팩(번호 · id · 원래 id · 이름 · 판 · 분류 · 파일) ·
//                                      타일 검사 결과 · 짓기의 답, 달력 표(범위 · ICU · 바이트 · SHA-256) · '오늘', 그리고 뺀 견본과 까닭.
//                                      포장 스크립트(bundle-app.mjs · release/notes.mjs)가 이것을 읽는다.
//
// 쓰는 곳:
//   - 릴리즈(.github/workflows/release.yml의 showcase 작업): `node prototype/scripts/build-showcase.mjs "$RUNNER_TEMP/showcase"` → Windows 꾸러미
//     (bundle-app.mjs — 동아시아 · 등불 연대기 저장소)와 안드로이드 APK의 seed(ANDROID_SEED가 고른 저장소 — 지금은 등불 연대기), 견본 DLC 파일
//     (lantern/base.htpack)이 된다.
//   - HistoryArchive 연표 모듈의 seed: `<출력>/showcase/`의 archive.db(저장소) · base.htpack(기본팩 원본) · DLC/*.htpack(얹은 견본이 있으면 그 원본)과
//     `<출력>/showcase.json`(무엇이 들었는지)을 그대로 옮긴다 — 엔진이 같으면(prototype/engine) 그쪽에서 다시 지을 일이 없다.
//   - 손으로: 위 사용 줄 그대로. 한 번에 몇 분(얹은 견본이 있고 모두 얹은 조합이 거절되면 견본을 하나씩 얹어 보느라 더 길다).
//
// 견본을 고르는 규칙(목록을 적어 두지 않는다 — samples/에 새 견본이 들어오면 저절로 따라온다. 견본이 하나도 없어도 동아시아는 짓는다):
//   1) samples/*.json 가운데 DLC(format: history-timeline-dlc)만.
//   2) 분류가 'world'(따로 세계 하나 — 기본팩과 함께 켜는 것이 아니다)인 견본은 동아시아에 얹지 않고 제 저장소를 따로 짓는다(지금은 lantern).
//   3) 아래 EXCLUDE에 적은 것(뺄 것만 적는다 — 까닭과 함께)과 --exclude로 준 것은 뺀다.
//   4) 지금 연표의 읽기(HT.normalizePack)가 거절하는 것 · 함께 써야 하는 DLC(requires)가 기본팩도 다른 견본도 아닌 것은 까닭을 적고 뺀다.
//      엔진의 짓기(archive-tool build — Rust 배치의 점검)가 모두 얹은 조합을 거절하면, 먼저 기본팩만으로 지어 본다 — 그것도 거절이면 견본 탓이
//      아니므로('오늘' · 달력 표 범위 · 기본팩) 아무것도 빼지 않고 멈춘다. 기본팩은 되면 견본을 하나씩 기본팩 위에 얹어 지어 보고 혼자서도 거절되는
//      견본만 까닭(엔진의 글 — 'Error: "…"' 겉은 걷음)과 함께 빼고 다시 짓는다(--strict면 멈춘다). 뺀 견본은 목록(showcase.json의 skipped)과 출력에 남고,
//      GitHub Actions에서는 경고(::warning::)로도 보인다 — 조용히 빠지지 않게. 하나씩은 다 되는데 조합만 안 되면 멈춘다.
//   5) DLC id가 겹치면(기본팩 · 앞의 견본과) 사본의 id를 '<id>-2' …로 갈라 준다 — samples/의 원본 파일은 고치지 않는다.
//      (DLC 안의 항목 번호는 DLC id를 앞머리로 새로 매겨지므로 id만 바꾸면 된다 — 견본이 제 id를 본문에 적어 둔 곳은 바뀌지 않는다.)
//   얹는 차례는 DLC 파일 이름 차례(samples/의 이름 차례 — 짓기에 주는 차례가 곧 저장소의 DLC 차례 meta.pack_order).
//
// 짓는 길(한 벌 P3 과제 17 걸음 5 — 2026-10-22): 엔진이 배치하고 짓는다 — archive-tool build <새 저장소> <기본팩.htpack> <얹은 .htpack…>
// --now=<'오늘'> --calendar=<전체 달력 표>(① Rust 배치 lay::export ② 짓기 + meta.now + blobs의 calendar:table — 계약 4절 머리 · 1절) →
// 달력 표가 들었는지(archive-tool blob <저장소> calendar:table을 풀어 준 표와 바이트로 견줌 — 엔진은 표 없는 저장소의 DLC 넣고 빼기를 거절한다 · 판정 R36) →
// verify-tiles("누락_중복":0) → query info(meta.pack_info) · query layout(DLC 관리 카드 = packs)로 견본마다 카드가 생겼는지 본다. 하나라도 어긋나면 종료 코드 1.
// 예전 길(Node 내보내기 export-layout.mjs → archive-tool import-layout — 달력 표 없음)은 정답지로만 남았다: build-check.mjs가 같은 조합을 두 길로 지어 견준다.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const root = path.resolve(prototype, '..');

/** 동아시아(showcase)에 얹지 않을 것(파일 이름에서 'sample-'·'.json'을 뗀 것 → 까닭). 분류 'world'는 규칙 2가 따로 다루므로 여기 적지 않는다. */
const EXCLUDE = new Map([
  // 지금은 없다 — 기본팩 위에 얹을 수 없는 견본이 생기면 여기에 까닭과 함께 적는다.
]);
/** 저장소의 사람이 읽는 이름(배포 폴더 이름 · 바로 가기 이름으로도 쓴다 — 서로 달라야 한다). 없으면 견본의 name.
    showcase의 이름은 release/notes.mjs가 작은 판(목록 없이)에서 포터블의 '<이름>-열기.cmd'를 적을 때도 쓴다 — 바꾸면 거기도. */
const LABELS = { showcase: '동아시아', lantern: '등불 연대기', 'east-asia': '동아시아 기본팩' };
const BASE_PACK = 'east-asia';

const args = process.argv.slice(2);
const option = (name) => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : null; };
const outArg = args.find(a => !a.startsWith('--'));
if (!outArg) {
  console.error('사용: build-showcase.mjs <출력 폴더> [--stores=showcase,lantern,east-asia] [--tool=<archive-tool>] [--exclude=<견본>,…] [--strict] [--calendar=<calendar-cache.json>] [--now=<ISO 시각(+09:00 꼴)>]');
  process.exit(2);
}
const out = path.resolve(outArg);
const strict = args.includes('--strict');
// '오늘'(meta.now): 준 글 그대로(시간대가 지역 날짜를 정한다 — Z는 엔진이 거절) · 없으면 지금 시각을 +09:00(서울)으로. 모든 저장소가 같은 값.
const now = (option('now') || new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 19) + '+09:00').trim();
// 엔진의 읽기(legacy::iso_time)와 같은 꼴만 받는다 — 초까지 · 소수 초는 선택 · 시간대는 ±HH:MM(Z는 build가 거절). 여기서 막지 않으면
// 모든 짓기가 같은 까닭으로 거절되어 아래 4)가 견본 탓으로 잘못 볼 수 있다(그래서 4)는 기본팩만으로도 먼저 지어 본다).
{
  const m = now.match(/^(\d{4})-(\d\d)-(\d\d)[Tt ](\d\d):(\d\d):(\d\d)(\.\d+)?[+-](\d\d):(\d\d)$/);
  const [, , mo, d, h, mi, s] = (m || []).map(Number);
  if (!m || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) {
    console.error(`--now는 시간대를 적은 ISO 시각이어야 합니다(초까지 — 예: 2026-10-22T12:00:00+09:00 · Z는 받지 않음): ${now}`);
    process.exit(2);
  }
}
const warn = (message) => {
  console.warn(message);
  if (process.env.GITHUB_ACTIONS === 'true') console.log(`::warning title=릴리즈 저장소::${message.replace(/\r?\n/g, ' ')}`);
};
const extraExclude = new Set((option('exclude') || '').split(',').map(s => s.trim()).filter(Boolean));

// 엔진 도구: --tool → HT_ARCHIVE_TOOL → 빌드 폴더(이 운영체제의 이름 먼저).
const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [option('tool') || '', process.env.HT_ARCHIVE_TOOL || '', ...toolNames.map(n => path.join(prototype, 'engine', 'target', 'release', n))]
  .map(f => f && path.resolve(f)).find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) {
  console.error(`엔진 도구(${toolNames[0]})가 없습니다. cargo build --locked --release --manifest-path prototype/engine/Cargo.toml 를 먼저 돌리세요.`);
  process.exit(1);
}

const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const keyOf = (file) => path.basename(file, '.json').replace(/^sample-/, '');
const fail = (message) => { console.error(message); process.exit(1); };
/** 도구를 돌린다. 실패하면 까닭의 끝을 보이고 멈춘다(soft면 멈추지 않고 { error }를 돌려준다). */
function run(command, argv, { env, what, soft = false }) {
  const done = spawnSync(command, argv, { encoding: 'utf8', env: env || process.env, maxBuffer: 256 * 1024 * 1024 });
  if (done.status !== 0) {
    const text = (done.stderr || '') + (done.stdout || '') + (done.error ? String(done.error) : '');
    const tail = text.split('\n').filter(l => !l.startsWith('    at ')).slice(-15).join('\n');
    if (soft) return { error: plainError((tail.match(/AssertionError[^:]*: (.*)/) || [])[1] || tail.trim().split('\n').pop() || '알 수 없음') };
    fail(`${what} 실패:\n` + tail);
  }
  return soft ? { stdout: done.stdout || '' } : done.stdout || '';
}
/** 엔진 도구의 실패 글(`Error: "…"` — Rust가 오류를 디버그 꼴로 찍음)에서 겉을 걷어 사람이 읽는 글만. 꼴이 다르면 그대로. */
function plainError(text) {
  const m = String(text).trim().match(/^Error: "([\s\S]*)"$/);
  if (!m) return String(text).trim();
  return m[1].replace(/\\u\{([0-9a-fA-F]+)\}/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/\\(["'\\nrt0])/g, (_, c) => ({ n: '\n', r: '\r', t: '\t', 0: '\0' })[c] ?? c);
}
/** archive-tool query의 답(마지막 줄 JSON). */
function query(db, request) {
  const text = run(tool, ['query', db, JSON.stringify(request)], { what: `조회 ${request.op}` }).trim().split('\n').pop();
  const answer = JSON.parse(text);
  return answer.data || answer;
}

// 1) 지금 연표의 웹 코드를 화면 없이 올린다(내보내기 도구와 같은 흉내) — 견본 읽기 점검 · 전용 팩(.htpack) 싸기 · 기본팩 원본에 쓴다.
const base = await import('./export/base.mjs');
const HT = base.bootWeb();
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const packScripts = [...html.matchAll(/<script src="(packs\/[^"]+\.js)"/g)].map(m => m[1]).filter(f => f.startsWith(`packs/${BASE_PACK}/`));
if (!packScripts.length) fail(`index.html에 packs/${BASE_PACK}/ 의 스크립트가 없습니다.`);
for (const file of packScripts) base.runScript(file);
const builtins = HT.getBuiltinPacks();
if (builtins.length !== 1) fail(`내장 DLC가 하나여야 합니다(지금 ${builtins.length}개).`);
const baseRaw = builtins[0];
const baseId = String(baseRaw.id || '');

// 2) 견본 고르기(머리글의 규칙 1~5).
const samplesDir = path.join(root, 'samples');
const chosen = [], worlds = [], skipped = [];
const usedIds = new Set([baseId]);
for (const name of fs.readdirSync(samplesDir).filter(f => f.endsWith('.json')).sort()) {
  const key = keyOf(name);
  let raw;
  try { raw = JSON.parse(fs.readFileSync(path.join(samplesDir, name), 'utf8')); } catch (e) { skipped.push({ file: name, reason: `JSON을 읽을 수 없음: ${e.message}` }); continue; }
  if (!raw || raw.format !== 'history-timeline-dlc') { skipped.push({ file: name, reason: 'DLC가 아님(format)' }); continue; }
  if (raw.category === 'world') { worlds.push({ key, file: name, raw }); continue; }
  if (EXCLUDE.has(key)) { skipped.push({ file: name, reason: EXCLUDE.get(key) }); continue; }
  if (extraExclude.has(key)) { skipped.push({ file: name, reason: '--exclude로 뺌' }); continue; }
  const norm = HT.normalizePack(raw);
  if (!norm.pack) { skipped.push({ file: name, reason: `지금 연표가 읽지 못함: ${(norm.errors || []).map(e => e.msg).join(' · ').slice(0, 200)}` }); continue; }
  chosen.push({ key, file: name, raw });
}
// requires: 기본팩 또는 고른 견본(원래 id)이어야 한다 — 빠진 것이 생기면 다시 본다(그 견본을 빼면 그것을 요구하던 견본도 빠진다).
for (let changed = true; changed;) {
  changed = false;
  const have = new Set([baseId, ...chosen.map(c => String(c.raw.id || ''))]);
  for (const one of [...chosen]) {
    const missing = (Array.isArray(one.raw.requires) ? one.raw.requires : []).map(String).filter(id => id && !have.has(id));
    if (missing.length) {
      chosen.splice(chosen.indexOf(one), 1);
      skipped.push({ file: one.file, reason: `함께 써야 하는 DLC가 없음: ${missing.join(', ')}` });
      changed = true;
    }
  }
}
// id 가르기(사본에서만).
for (const one of chosen) {
  const sourceId = String(one.raw.id || one.key);
  let id = sourceId;
  for (let n = 2; usedIds.has(id); n++) id = `${sourceId}-${n}`;
  usedIds.add(id);
  one.sourceId = sourceId;
  one.id = id;
  if (id !== sourceId) {
    one.raw = Object.assign(structuredClone(one.raw), { id });
    console.log(`DLC id가 겹쳐 사본의 id를 바꿉니다: ${one.file} ${sourceId} → ${id}`);
  }
}

// 3) 지을 저장소.
const wanted = (option('stores') || ['showcase', ...worlds.map(w => w.key)].join(',')).split(',').map(s => s.trim()).filter(Boolean);
const plans = [];
for (const key of wanted) {
  if (key === 'showcase') plans.push({ key, base: { raw: baseRaw, pack: BASE_PACK }, extras: chosen });
  else if (key === BASE_PACK) plans.push({ key, base: { raw: baseRaw, pack: BASE_PACK }, extras: [] });
  else {
    const world = worlds.find(w => w.key === key);
    if (!world) fail(`모르는 저장소: ${key} (showcase · ${BASE_PACK} · ${worlds.map(w => w.key).join(' · ') || '따로 세계인 견본 없음'})`);
    plans.push({ key, base: { raw: world.raw, sample: path.basename(world.file, '.json') }, extras: [] });
  }
}
// 이름은 꾸러미의 폴더 이름(자료/<이름>/) · 바로 가기 이름이 되므로 겹치면 안 된다.
const labelOf = (plan) => LABELS[plan.key] || String(plan.base.raw.name || plan.key);
for (const plan of plans) {
  const twin = plans.find(other => other !== plan && labelOf(other) === labelOf(plan));
  if (twin) fail(`저장소 이름이 겹칩니다: ${plan.key} · ${twin.key} → '${labelOf(plan)}' (LABELS를 고치세요)`);
}
for (const plan of plans) {
  const dir = path.join(out, plan.key);
  if (fs.existsSync(path.join(dir, 'archive.db'))) fail(`이미 지은 저장소는 덮어쓰지 않습니다: ${path.join(dir, 'archive.db')} — 새 출력 폴더를 주세요.`);
}
if (fs.existsSync(path.join(out, 'showcase.json'))) fail(`이미 있는 목록은 덮어쓰지 않습니다: ${path.join(out, 'showcase.json')} — 새 출력 폴더를 주세요.`);
fs.mkdirSync(out, { recursive: true });

// 달력 표(판정 R36 — 저장소마다 전체 표를 통째로): 준 파일 그대로, 없으면 이 Node로 전체 범위를 떠서 <출력>/calendar-cache.json에.
/** 전체 표의 범위와 달력(warm-calendar.mjs 기본 · export/calendar.mjs의 wantedCalendars — 계약 1절). 준 표가 이보다 좁으면 알린다. */
const FULL_YEARS = [-3500, 2500], FULL_CALENDARS = ['dangi', 'chinese', 'islamic', 'umalqura', 'persian', 'hebrew', 'ethiopic', 'coptic', 'indian'];
let calendar = option('calendar') ? path.resolve(option('calendar')) : '';
if (calendar) {
  if (!fs.existsSync(calendar)) fail(`달력 표가 없습니다: ${calendar}`);
} else {
  calendar = path.join(out, 'calendar-cache.json');
  if (fs.existsSync(calendar)) fail(`이미 있는 달력 표는 덮어쓰지 않습니다: ${calendar} — 새 출력 폴더를 주거나 --calendar=로 그 파일을 주세요.`);
  console.log(`달력 표를 뜨는 중(warm-calendar.mjs — ${FULL_YEARS.join(' ~ ')}년)…`);
  console.log(run(process.execPath, [path.join(scripts, 'warm-calendar.mjs'), `--years=${FULL_YEARS.join(',')}`, `--file=${calendar}`], { what: '달력 표 뜨기' }).trim());
}
const calendarBytes = fs.readFileSync(calendar);
const calendarInfo = (() => {
  let body;
  try { body = JSON.parse(calendarBytes.toString('utf8')); } catch (e) { fail(`달력 표를 읽을 수 없습니다(${calendar}): ${e.message}`); }
  if (!body || !Array.isArray(body.years) || !body.tables) fail(`달력 표의 꼴이 아닙니다(years · tables — warm-calendar.mjs가 뜬 것을 주세요): ${calendar}`);
  // 목록에는 출력 폴더에서 본 상대 자리만 적는다(이 PC · CI의 절대 경로를 싣지 않게 — 출력 밖이면 '../…').
  return { file: path.relative(out, calendar).replace(/\\/g, '/'), years: body.years, icu: body.icu, calendars: Object.keys(body.tables), bytes: calendarBytes.length, sha256: sha256(calendarBytes) };
})();
{
  // 준 표가 전체 표보다 좁으면 알린다(그 저장소에서는 표 바깥 날짜를 쓰는 DLC를 넣지 못한다 — 판정 R36). 짓기는 그대로(자료가 범위 밖이면 엔진이 거절).
  const [lo, hi] = calendarInfo.years.map(Number);
  const lack = FULL_CALENDARS.filter(c => !calendarInfo.calendars.includes(c));
  if (!(lo <= FULL_YEARS[0] && hi >= FULL_YEARS[1]) || lack.length) {
    warn(`달력 표가 전체 표보다 좁습니다(${calendarInfo.years.join(' ~ ')}년${lack.length ? ` · 없는 달력 ${lack.join(' · ')}` : ''} — 전체는 ${FULL_YEARS.join(' ~ ')}년 · ${FULL_CALENDARS.join(' · ')}). `
      + '이 저장소에서는 그 바깥 날짜를 쓰는 DLC를 넣고 빼지 못합니다 — --calendar 없이 돌리면 전체 표를 뜹니다.');
  }
}
console.log(`달력 표: ${calendar} · ${calendarInfo.years.join(' ~ ')}년 · ${calendarInfo.calendars.join(' · ')} · 글 ${calendarBytes.length}바이트 · '오늘' ${now}`);
/** 지은 저장소에 그 달력 표가 들었는가(blobs의 calendar:table — 엔진 lay::calendar_of가 읽는 것)를 풀어 바이트로 견준다. 답: zlib 바이트 수. */
function calendarIn(db, label) {
  const file = path.join(path.dirname(db), `.calendar-table-${process.pid}.zlib`);
  try {
    run(tool, ['blob', db, 'calendar:table', file], { what: `[${label}] 달력 표 꺼내기(저장소에 표가 없음 — DLC 넣고 빼기가 막힘)` });
    const packed = fs.readFileSync(file);
    let plain;
    try { plain = zlib.inflateSync(packed); } catch (e) { fail(`[${label}] 저장소의 달력 표를 풀 수 없습니다: ${e.message}`); }
    if (!plain.equals(calendarBytes)) fail(`[${label}] 저장소의 달력 표가 준 표와 다릅니다(${plain.length} ≠ ${calendarBytes.length}바이트)`);
    return packed.length;
  } finally { fs.rmSync(file, { force: true }); }
}
console.log(chosen.length ? `동아시아 기본팩 위에 얹을 견본 ${chosen.length}벌: ${chosen.map(c => c.key).join(' · ')}` : '동아시아 기본팩 위에 얹을 견본 없음 — showcase는 기본팩만으로 짓는다.');
if (worlds.length) console.log(`따로 세계인 견본 ${worlds.length}벌(제 저장소): ${worlds.map(w => w.key).join(' · ')}`);
if (skipped.length) console.log(`뺀 견본: ${skipped.map(s => `${s.file}(${s.reason})`).join(' · ')}`);

// 4) 저장소마다: 원본 싸기 → 짓기(엔진이 배치하고 짓는다 · '오늘' · 달력 표) → 달력 표 확인 → 타일 검사 → 카드 확인.
const stores = [];
for (const plan of plans) {
  const started = Date.now();
  const dir = path.join(out, plan.key), dlcDir = path.join(dir, 'DLC');
  fs.mkdirSync(dir, { recursive: true });
  const basePack = path.join(dir, 'base.htpack');
  fs.writeFileSync(basePack, await HT.packFile.build(plan.base.raw));
  const extras = [];
  if (plan.extras.length) fs.mkdirSync(dlcDir, { recursive: true });
  for (const one of plan.extras) {
    const file = path.join(dlcDir, path.basename(one.file, '.json') + '.htpack');
    fs.writeFileSync(file, await HT.packFile.build(one.raw));
    extras.push({ ...one, htpack: file });
  }
  const db = path.join(dir, 'archive.db');
  // 짓기(archive-tool build — ① Rust 배치 ② 짓기). 거절이면 엔진이 저장소를 남기지 않지만, 혹시 남은 것은 다음 시도 전에 치운다.
  const buildWith = (list, target = db) => {
    fs.rmSync(target, { force: true });
    return run(tool, ['build', target, basePack, ...list.map(e => e.htpack), `--now=${now}`, `--calendar=${calendar}`], { what: `[${plan.key}] 저장소 짓기`, soft: true });
  };
  console.log(`[${plan.key}] 저장소를 짓는 중(엔진이 배치하고 짓는다)…`);
  let built = buildWith(extras);
  if (built.error && extras.length) {
    // 규칙 4: 조합이 거절되었다. 먼저 기본팩만으로 지어 본다 — 그것도 거절이면 견본 탓이 아니다('오늘' · 달력 표 범위 · 기본팩 · 도구):
    // 견본을 빼지 않고(DLC 사본도 지우지 않고) 멈춘다.
    const probe = path.join(dir, `probe-${process.pid}.db`);
    const bare = buildWith([], probe);
    fs.rmSync(probe, { force: true });
    if (bare.error) fail(`[${plan.key}] 기본팩만으로도 짓지 못했습니다 — 견본 탓이 아니어서 견본을 빼지 않고 멈춥니다: ${bare.error}`);
    // 하나씩 얹어 보고 혼자서도 거절되는 견본만 뺀다.
    console.log(`[${plan.key}] 모두 얹은 조합을 짓지 못했습니다(${built.error}) — 견본을 하나씩 얹어 봅니다…`);
    for (const one of [...extras]) {
      const alone = buildWith([one], probe);
      fs.rmSync(probe, { force: true });
      if (!alone.error) continue;
      const reason = `짓기가 거절함: ${alone.error}`;
      if (strict) fail(`[${plan.key}] ${one.file}: ${reason}`);
      warn(`[${plan.key}] 견본을 뺍니다 — ${one.file}: ${reason}`);
      skipped.push({ file: one.file, reason });
      extras.splice(extras.indexOf(one), 1);
      fs.rmSync(one.htpack, { force: true });
    }
    built = buildWith(extras);
    if (built.error) fail(`[${plan.key}] 견본마다는 지어지는데 모두 얹으면 거절됩니다: ${built.error}`);
  } else if (built.error) {
    fail(`[${plan.key}] 저장소 짓기 실패: ${built.error}`);
  }
  if (!fs.existsSync(db)) fail(`[${plan.key}] 짓기가 끝났는데 저장소가 없습니다: ${db}`);
  // 달력 표가 들었는지(없으면 앱에서 DLC를 넣고 뺄 수 없다 — 판정 R36).
  const tableBytes = calendarIn(db, plan.key);
  // 타일이 전수 조사와 맞는지(누락 · 중복 0).
  const verify = run(tool, ['verify-tiles', db, '600'], { what: `[${plan.key}] 타일 검사` }).trim();
  if (!/"누락_중복":0\b/.test(verify)) fail(`[${plan.key}] 타일 검사가 어긋났습니다: ${verify.slice(-400)}`);
  // DLC 관리 카드(layout.packs)와 meta.pack_info — 기본팩 1 + 얹은 견본마다 하나.
  const info = query(db, { op: 'info' });
  const meta = info.meta || {};
  const packInfo = typeof meta.pack_info === 'string' ? JSON.parse(meta.pack_info) : (meta.pack_info || {});
  const cards = query(db, { op: 'layout' }).packs || [];
  const expected = 1 + extras.length;
  if (cards.length !== expected || Object.keys(packInfo).length !== expected) {
    fail(`[${plan.key}] DLC 카드 수가 어긋났습니다: 카드 ${cards.length} · pack_info ${Object.keys(packInfo).length} · 기대 ${expected}`);
  }
  const keys = cards.map(c => c.key);
  const lost = [plan.base.raw.id, ...extras.map(e => e.id)].map(String).filter(id => !keys.includes(id));
  if (lost.length) fail(`[${plan.key}] 카드가 없는 DLC: ${lost.join(', ')}`);
  const bytes = fs.readFileSync(db);
  const seconds = Math.round((Date.now() - started) / 100) / 10;
  const byKey = new Map(extras.map(e => [e.id, e]));
  stores.push({
    key: plan.key,
    label: labelOf(plan),
    folder: plan.key,
    database: `${plan.key}/archive.db`,
    bytes: bytes.length,
    sha256: sha256(bytes),
    seconds,
    count: Number(meta.count || 0),
    base: { file: `${plan.key}/base.htpack`, id: String(plan.base.raw.id || ''), name: String(plan.base.raw.name || ''), source: plan.base.pack ? `packs/${plan.base.pack}` : `samples/${plan.base.sample}.json` },
    packs: cards.map(c => {
      const extra = byKey.get(c.key);
      return {
        number: c.id, id: c.key, name: c.name, version: c.version, category: c.category, events: c.events, original: c.original,
        ...(extra ? { sourceId: extra.sourceId, file: `${plan.key}/DLC/${path.basename(extra.htpack)}`, sample: `samples/${extra.file}` } : { base: true }),
      };
    }),
    verify: JSON.parse(verify.split('\n').pop()),
    now: meta.now || now,
    calendar: { bytes: tableBytes },
    built: (() => { try { return JSON.parse(built.stdout.trim().split('\n').pop()); } catch { return null; } })(),
  });
  console.log(`[${plan.key}] ${(bytes.length / 1048576).toFixed(1)}MiB · 사건 ${meta.count} · DLC 카드 ${cards.length}장 · 달력 표 ${tableBytes}바이트(zlib) · 타일 누락·중복 0 · ${seconds}초`);
}

// 5) 목록.
const version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version;
const listing = {
  kind: 'history-timeline-showcase',
  schema: 1,
  version,
  default: stores.some(s => s.key === 'showcase') ? 'showcase' : (stores[0] || {}).key,
  now,
  calendar: calendarInfo,
  stores,
  skipped,
};
fs.writeFileSync(path.join(out, 'showcase.json'), JSON.stringify(listing, null, 1) + '\n');
console.log(`목록: ${path.join(out, 'showcase.json')} · 저장소 ${stores.length}개 · 뺀 견본 ${skipped.length}벌`);

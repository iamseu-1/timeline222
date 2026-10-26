// ── 정답지 · 비교용으로만 남긴다(한 벌 P4 과제 11 · 판정 R41 · R49 — 2026-10-22) ──
// 앱은 이 도구를 부르지 않는다: 넣기 · 빼기 · 끄기 · 켜기 · 판 올림 뒤 다시 들이기 · 메이커 미리보기는 모두 엔진의 add_pack · remove_pack(계약 2-7-1)이고,
// 꾸러미(bundle-app.mjs · collect-app.mjs)는 이 도구 · Node.js · 배치 내보내기 · DLC-추가.cmd를 싣지 않는다. 시드 저장소는 build-showcase.mjs가 엔진
// (archive-tool build — 달력 표 있음)으로 짓는다. 이 도구의 다시 짓기(아래 3 ~ 5)는 Node 배치 → import-layout이라 **달력 표 없는 저장소**를 짓는다 —
// 그 저장소에서는 앱 · 엔진이 DLC를 넣고 빼지 못한다(code: calendar). 사용자 저장소에 쓰지 않는다.
// 남은 쓰임: apply-check.mjs(--apply — Node 배치로 고쳐 쓴 저장소가 통째 짓기와 같은지) · add-dlc-tomb-check.mjs(--layout-only · DLC/ 폴더의 묘비
// 규칙이 앱과 같은지). 아래 DLC/ 폴더 · 끈 목록(hidden.json) · 묘비(sync.json) 규칙은 그 비교를 위해 그대로 둔다 — 앱의 DLC/ 폴더(판정 R32 · R33)는
// 앱(ui/dlc_add.dart · ui/seed_carry.dart)이 지킨다. 아래 머리말의 '앱이 …' 글은 과제 11c 전(앱이 이 도구를 부르던 때)의 것이다.
//
// DLC 더하기(4단계의 첫 판 — 컴퓨터에서 파일로): 메이커가 내보낸 .htpack을 동아시아 기본팩 위에 얹어 저장소를 다시 짓고 제자리에 바꿔 넣는다.
// 새 앱의 줄 배치는 켠 DLC 전체를 두고 셈하므로(지금 연표와 같다) DLC를 더하거나 빼면 저장소를 통째로 다시 짓는다 — 그래서 '설치'가 아니라 '다시 짓기'다.
//
// 사용: node prototype/scripts/add-dlc.mjs <저장소 archive.db> [<파일.htpack> …] [--out=<새 저장소 경로>] [--remove=<DLC 글자 id>]
//   - 준 .htpack은 저장소 옆의 DLC/ 폴더에 복사해 둔다(그 폴더가 '얹은 DLC의 목록'이다). 같은 id는 판이 높은 것만 남긴다.
//   - .htpack을 하나도 주지 않으면 DLC/ 폴더의 것으로 다시 짓는다(빼고 싶은 DLC는 그 폴더에서 파일을 지우고 이 도구를 다시 돌리면 된다).
//   - `--remove=<DLC 글자 id>`: DLC/ 폴더에서 그 id의 파일을 지운 뒤 짓는다(앱의 DLC 관리 창 '삭제'가 쓴다).
//     기본팩(`east-asia-base`)도 뺄 수 있다 — 파일이 없으므로 DLC/hidden.json에 `baseRemoved`를 적는다. 되살리려면 기본팩의 .htpack
//     (도구/prototype/results/compat/east-asia.htpack)을 이 도구에 파일로 주면 된다.
//   - `--off=<id,id>` · `--on=<id,id>`: 끄기 · 켜기(2026-10-16 감독 건의 — "숨기면 연표에서 아예 나오지 않게"). 끈 DLC는 파일을 지우지 않고
//     **그 DLC를 빼고** 저장소를 다시 짓는다(배치 · 조회 · 그리기 어디에도 없게). 끈 목록과 그 카드(이름 · 판 · 트랙)는 DLC/hidden.json.
//     기본팩도 끌 수 있다(그때는 켠 DLC의 첫째가 기본 자리에 서서 짓는다). 다 끄면 짓지 않고 끈 목록만 적는다(앱이 연표를 비운다).
//   - `--prefer-given`: 같은 id면 판과 상관없이 **준 파일이 이긴다**(그 id의 다른 파일은 지운다) — 본 프로그램의 메이커 미리보기(`--preview-dlc`)가
//     서재의 임시 사본에서만 쓴다. 메이커의 작업본은 서재에 깔린 같은 DLC보다 판이 낮거나 같을 수 있다.
//   - `--out=<경로>`: 지은 저장소를 거기에 두고 **바꿔 넣지 않는다** — 열려 있는 저장소를 건드리지 않으므로 앱이 켜진 채로 뒤에서 돌릴 수 있다
//     (앱이 close → 바꿔 넣기 → open으로 잇는다 · ui/dlc_add.dart). 이 옵션이 없으면 옛 저장소를 archive.이전.db로 남기고 제자리에 바꿔 넣는다 —
//     그때는 앱이 저장소를 열어 두고 있으면 바꿔 넣지 못하므로 앱을 먼저 닫아야 한다(배포 폴더의 DLC-추가.cmd — 예비 길).
//   - 원본 없는 DLC(메이커의 아카이브 배치 .htlayout으로만 들어와 저장소에 .htpack이 없는 것 — 저장소의 `meta.pack_info`에 `original:false`)가 있는데
//     그 DLC의 파일이 DLC/ 폴더에 없으면 **다시 짓기를 거절한다**: 이 도구는 DLC/ 폴더의 파일로 짓기 때문에, 그대로 지으면 그 DLC가 조용히 사라진다
//     (설계 docs/설계-10건/A-아카이브-이음.md 5-4 다). 그 DLC의 .htpack을 이 도구에 파일로 주거나 DLC/ 폴더에 두면 된다. 그 DLC를 빼는 것(--remove)은 된다.
//   - `--apply`(계획 P4 과제 7a · 계약 2-7): 다시 짓지 않고 저장소를 **제자리에서 고쳐 쓴다**(임시 저장소 · 바꿔 넣기 없음 — 바뀐 트랙만 한 거래로).
//     이미 얹은 DLC의 원본은 저장소에서 꺼내 쓰고(`archive-tool pack-out` — 저장소의 원본이 하나뿐인 진실), 준 .htpack과 함께 배치를 셈한 뒤
//     `archive-tool apply-layout`으로 고쳐 쓴다. 저장소에 원본이 없는 DLC(위의 원본 없는 DLC)는 그때 한 번 DLC/ 폴더의 그 파일을 원본으로 저장소 안에 들이고,
//     폴더에도 없으면 "그 DLC 파일을 다시 골라 주세요"로 멈춘다. DLC/ 폴더는 옛 길(이 선택 없이 다시 짓기)이 쓰므로 준 파일 · 뺀 DLC를 옛 길과 같게 맞춰 두되,
//     **고쳐 쓰기가 끝난 뒤에만** 바꾼다(실패하면 저장소도 폴더도 그대로 · 고쳐 쓴 뒤 폴더만 덜 맞추면 종료 코드 3 — 다시 돌리면 맞춘다). 배치의 DLC 차례는 옛 길처럼 DLC/ 폴더의 파일 이름 차례다(내용은 저장소의 원본 —
//     폴더에 그 DLC의 파일이 없을 때만 `<id>-v<판>.htpack`이라는 이름으로 센다).
//     기본팩 끄기 · 빼기 · --prefer-given은 이 길이 다루지 않아 멈춘다(다시 짓기 — apply는 기본팩이 첫째라는 약속 · 계획 P4 과제 8 얹힌 몫 3).
//     끄기 · 켜기(--off · --on)와 끈 목록(DLC/hidden.json)은 `--layout-only`(앱)만 다룬다 — `--apply`는 끈 목록이 있는 저장소에서 멈춘다.
//     **앱이 그 저장소를 열어 두었으면 앱을 닫고 돌린다**(켜진 앱에서는 앱이 엔진의 {"op":"apply"}를 부른다 — 계획 P4 과제 8): 다른 프로세스가 고쳐 쓰면
//     앱의 읽기 연결은 새 행을 읽지만 메모리의 줄 열쇠 ↔ 자리 표와 화면의 배치는 옛것이라 엉뚱한 줄에 그려진다(옛 바꿔 넣기는 Windows의 파일 잠금이 막아 줬다).
//   - `--layout-only=<배치 JSON 경로>`: `--apply`와 같이 셈하되 배치 JSON만 그 경로에 쓰고 끝낸다 — 앱이 엔진의 {"op":"apply"}를 부를 때.
//     마지막 줄에 그 요청의 재료(JSON 한 줄)를 찍는다: `layout` · `originals` · `remove`(엔진에 줄 것 — `layout`이 null이면 엔진에 쓸 것이 없다:
//     끈 DLC를 지우기만 함) · `folder`(고쳐 쓰기가 **끝난 뒤** 앱이 맞출 DLC/ 폴더 — `copy`: [원본, 폴더 자리] · `drop`: 지울 파일 ·
//     `tomb`: drop 가운데 묘비 DLC(빼는 DLC · sync.json의 removed)의 파일 — 앱이 못 지웠을 때 '다음에 앱을 열 때 다시 지움'을 약속하는 것은 이것뿐) ·
//     `hidden`(끝난 뒤 앱이 DLC/hidden.json에 쓸 끈 목록 — 바뀌지 않으면 null). 저장소도 DLC/ 폴더도 끈 목록도 바꾸지 않는다(원본은 준 파일 자리 그대로).
//     끄기(`--off=<id>`)는 그 DLC를 저장소에서 빼되(`remove`) 폴더의 파일은 남기고 끈 목록에 카드와 함께 올린다 — 폴더에 그 DLC의 파일이 없으면
//     (다시 켤 원본이 없다) 멈춘다. 켜기(`--on=<id>`)는 폴더의 그 파일을 원본으로 준다. 끈 DLC를 빼면(`--remove`) 저장소는 그대로 두고 폴더 · 끈 목록만.
//     기본팩을 끄거나 뺀 저장소 · 끈 DLC가 아직 저장소에 남은 저장소(옛 길에서 다 끈 것)는 멈춘다(다시 짓기).
// 필요한 것: Node.js · 이 폴더 구조(prototype/scripts/export* · ../index.html · ../js · ../packs/east-asia) · 옆의 엔진 도구
//   (Windows는 archive-tool.exe, Linux는 확장자 없는 archive-tool — 환경 변수 HT_ARCHIVE_TOOL로 자리를 줄 수도 있다).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const args = process.argv.slice(2);
const option = (name) => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : ''; };
const outArg = option('out'), removeKey = option('remove'), preferGiven = args.includes('--prefer-given'), layoutOnly = option('layout-only');
const inPlace = args.includes('--apply') || Boolean(layoutOnly);
const listOf = (text) => text.split(',').map(s => s.trim()).filter(Boolean);
const offKeys = listOf(option('off')), onKeys = listOf(option('on'));
const BASE = 'east-asia-base';
const [dbArg, ...given] = args.filter(a => !a.startsWith('--'));
// 준 파일의 이름(작은 글자) — --prefer-given이 DLC/ 폴더 안에서 준 파일을 알아보고, --apply가 준 DLC(givenIds)를 가린다.
const givenNames = new Set(given.map(f => path.basename(path.resolve(f)).toLowerCase()));
/** --apply의 경고 — 도움말과 고쳐 쓰기 앞에 찍는다. */
const OPEN_APP = '앱이 이 저장소를 열어 두었으면 먼저 앱을 닫으세요(켜진 앱에서는 앱의 DLC 관리를 쓰세요) — 켜진 앱 밑에서 고쳐 쓰면 화면이 엉뚱한 줄에 그려집니다.';
if (!dbArg) {
  console.error(`사용: add-dlc.mjs <저장소 archive.db> [<파일.htpack> …] [--out=<새 저장소>] [--remove=<DLC 글자 id>] [--off=<id,id>] [--on=<id,id>] [--prefer-given] [--apply | --layout-only=<배치 JSON>]\n  --apply: ${OPEN_APP}`);
  process.exit(2);
}
if (inPlace && outArg) { console.error('--apply · --layout-only는 저장소를 제자리에서 고쳐 씁니다 — --out과 함께 쓰지 않습니다.'); process.exit(2); }
// --apply · --layout-only는 기본팩 끄기 · 켜기 · 빼기와 --prefer-given을 다루지 않는다(다시 짓기 — 계획 P4 과제 8 얹힌 몫 3).
// 끄기 · 켜기는 --layout-only(앱)만 — 끈 목록은 앱이 엔진의 고쳐 쓰기가 끝난 뒤 적는다.
if (inPlace && (preferGiven || removeKey === BASE || offKeys.includes(BASE) || onKeys.includes(BASE) || (!layoutOnly && (offKeys.length || onKeys.length)))) {
  console.error('--apply는 --off · --on과, --apply · --layout-only는 --prefer-given · 기본팩 끄기 · 켜기 · 빼기와 함께 쓰지 않습니다 — --apply 없이 다시 지어 주세요.');
  process.exit(2);
}
const db = path.resolve(dbArg);
// 막이(판정 R58 ⑤ Minor): 다시 짓기(--apply · --layout-only가 아닌 길)는 Node 배치 → import-layout이라 **달력 표 없는 저장소**를 짓는다 — 엔진이 지은
// 저장소(시드 · 꾸러미 · 사용자 저장소 — blobs에 calendar:table이 있음)를 그 길로 다시 지으면 표가 사라져 앱 · 엔진이 DLC를 넣고 빼지 못한다(code: calendar).
// 그런 저장소면 멈춘다 — 비교용으로 일부러 지을 때만 --allow-no-calendar.
if (!inPlace && !args.includes('--allow-no-calendar') && fs.existsSync(db)) {
  const warn = process.emitWarning;
  process.emitWarning = (w, ...rest) => (String(w).includes('SQLite') ? undefined : warn.call(process, w, ...rest));
  const { DatabaseSync } = await import('node:sqlite');
  const d = new DatabaseSync(db, { readOnly: true });
  let table = false;
  try { table = !!d.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='blobs'").get() && !!d.prepare("SELECT 1 FROM blobs WHERE key='calendar:table'").get(); } finally { d.close(); }
  if (table) {
    console.error(`달력 표가 든 저장소입니다(${db}) — 이 도구의 다시 짓기는 달력 표 없는 저장소를 지어 DLC 넣고 빼기가 막힙니다. 앱의 DLC 관리 · --apply를 쓰거나, 비교용이면 --allow-no-calendar.`);
    process.exit(2);
  }
}
const folder = path.dirname(db), dlcDir = path.join(folder, 'DLC');
// 엔진 도구: 이 운영체제의 이름을 먼저 찾는다(Windows는 .exe · 그 밖은 확장자 없음). 배포 폴더(prototype/)의 것 → 빌드 폴더의 것.
const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [process.env.HT_ARCHIVE_TOOL || '', ...[prototype, path.join(prototype, 'engine', 'target', 'release')].flatMap(dir => toolNames.map(n => path.join(dir, n)))]
  .find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) { console.error(`엔진 도구(${toolNames[0]})가 없습니다.`); process.exit(1); }
if (!inPlace) fs.mkdirSync(dlcDir, { recursive: true });

// 0) 끈 목록(DLC/hidden.json): {"version":1,"off":[글자 id…],"baseRemoved":bool,"cards":{글자 id: 카드}} — 카드는 끈 DLC를 DLC 관리 창에 그리는 값
//    (저장소에 없으므로). 끌 때 지금 저장소의 뼈대(`{"op":"layout"}`)에서 떠 둔다 — 켠 동안의 카드와 같은 값.
const statePath = path.join(dlcDir, 'hidden.json');
const state = (() => {
  try {
    const raw = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    return { version: 1, off: Array.isArray(raw.off) ? raw.off.map(String) : [], baseRemoved: raw.baseRemoved === true, cards: raw.cards && typeof raw.cards === 'object' ? raw.cards : {} };
  } catch { return { version: 1, off: [], baseRemoved: false, cards: {} }; }
})();
const off = new Set(state.off);
// 0') 폴더 기억(DLC/sync.json — 판정 R33): 앱이 저장소를 고쳐 쓴 직후 남기는 묘비 — removed = 뺀 DLC · off = 끈 DLC의 글자 id.
//     폴더 지우기나 끈 목록 쓰기가 실패해 파일이 남아도 그 DLC를 다시 얹지 않는다(준 파일 — 사용자가 다시 넣음 — 만 이긴다).
//     앱(ui/dlc_add.dart DlcFolderState · ui/seed_carry.dart DlcFolderSync)과 같은 규칙(8 검토): 지금 저장소에 든 id는 묘비를 보지 않는다(다시 넣었는데
//     묘비를 지우지 못한 것 — 그 DLC의 폴더 파일을 지우거나 얹지 않으면 다시 끌 원본 · 판 올림 뒤 다시 들일 원본이 사라진다). 없으면 묘비 없음,
//     **있는데 읽지 못하면 멈춘다**(빈 묘비로 보면 뺀 DLC가 되살아난다 — 앱은 그동안 폴더에서 다시 들이지 않는다).
const syncPath = path.join(dlcDir, 'sync.json');
const tomb = (() => {
  if (!fs.existsSync(syncPath)) return { removed: new Set(), off: new Set() };
  let raw;
  try { raw = JSON.parse(fs.readFileSync(syncPath, 'utf8')); } catch { raw = null; }
  const listOrNone = (v) => v === undefined || v === null || Array.isArray(v);
  if (!raw || typeof raw !== 'object' || Array.isArray(raw) || !listOrNone(raw.removed) || !listOrNone(raw.off)) {
    console.error(`DLC 폴더의 기억(${syncPath})을 읽지 못합니다 — 그대로 하면 뺀 DLC가 되살아날 수 있어 멈춥니다. 그 파일을 지우거나 고친 뒤 다시 해 주세요.`);
    process.exit(1);
  }
  const stored = new Set((packList() || []).map(p => p.id).filter(Boolean));
  const ids = (v) => new Set((Array.isArray(v) ? v.map(String) : []).filter(id => !stored.has(id)));
  return { removed: ids(raw.removed), off: ids(raw.off) };
})();
/** 읽은 그대로의 끈 목록(글) — --layout-only가 바뀌었을 때만 `hidden`을 낸다. */
const stateText = () => JSON.stringify({ off: [...off].sort(), baseRemoved: state.baseRemoved, cards: state.cards });
const stateBefore = stateText();
// 끈 DLC · 뺀 기본팩이 있는 저장소(DLC/hidden.json): 고쳐 쓰는 길은 저장소 첫 자료집이 기본팩이라고 본다 — 기본팩을 끄거나 뺀 저장소는 둘 다 멈춘다.
// 끈 DLC(기본팩 말고)는 --layout-only만 다룬다(끈 목록은 앱이 적는다) — --apply는 끈 목록이 있으면 멈춘다.
if (inPlace && (state.baseRemoved || off.has(BASE) || (!layoutOnly && off.size))) {
  console.error(`${state.baseRemoved || off.has(BASE) ? '기본팩을 끄거나 뺀' : '끈 DLC가 있는'} 저장소입니다(${statePath}) — ${layoutOnly ? '--layout-only' : '--apply'}는 다루지 않습니다. --apply 없이 다시 지어 주세요.`);
  process.exit(1);
}
// 기본팩의 원본 파일(results/compat/east-asia.htpack — 뺀 기본팩을 되살릴 때 '파일에서 더하기'로 고르는 것)이 없으면 지금 저장소에서 꺼내 둔다
// (기본팩 없이 지으면 내보내기가 그 파일을 만들지 않는다). 저장소에 기본팩이 없으면 그대로 둔다.
// --apply · --layout-only는 하지 않는다 — 그 길은 기본팩 빼기를 막아 두어 필요 없고, 저장소의 기본팩이 지금 packs/east-asia와 다르면 그 옛 기본팩이
// 이 파일로 남아 원본으로 넘어갈 수 있다.
const basePackFile = path.join(prototype, 'results', 'compat', 'east-asia.htpack');
if (!inPlace && !fs.existsSync(basePackFile) && fs.existsSync(db)) {
  fs.mkdirSync(path.dirname(basePackFile), { recursive: true });
  spawnSync(tool, ['pack-out', db, BASE, basePackFile], { encoding: 'utf8' });
}

// 1) 준 파일을 DLC/ 폴더로. 확장자가 .htpack이 아니면 거절한다(메이커의 '내보내기'가 만드는 파일만).
//    --apply · --layout-only는 지금 복사하지 않고 준 자리에서 읽는다 — 폴더는 고쳐 쓰기가 끝난 뒤에 맞춘다(실패하면 폴더도 그대로).
const givenIds = new Set(), givenSrc = new Map();
for (const one of given) {
  const src = path.resolve(one);
  if (!/\.htpack$/i.test(src)) { console.error(`DLC 파일(.htpack)이 아닙니다: ${src}`); process.exit(1); }
  if (!fs.existsSync(src)) { console.error(`파일이 없습니다: ${src}`); process.exit(1); }
  const name = path.basename(src), dst = path.join(dlcDir, name);
  if (inPlace) givenSrc.set(name, src);
  else if (path.resolve(dst) !== src) fs.copyFileSync(src, dst);
}

// 2) DLC/ 폴더의 파일을 읽어 id · 판을 알아내고, 같은 id는 판이 높은 것만 남긴다(낮은 것은 지운다).
const scratch = fs.mkdtempSync(path.join(fs.realpathSync(process.env.TEMP || process.env.TMP || os.tmpdir() || folder), 'ht-add-dlc-'));
// 어느 길로 끝나든(거절 · 실패 포함) 임시 폴더를 치운다 — 리눅스의 /tmp에 남지 않게.
process.on('exit', () => { try { fs.rmSync(scratch, { recursive: true, force: true }); } catch { /* 이미 없음 */ } });
// 판은 메이커가 "1.0.3"처럼 점으로 적는다 — 마디마다 수로 견준다(Number("1.1.0")은 NaN이라 늘 0이 되어 '뒤의 파일이 낮은 판'으로 잘못 지워졌다).
const versionOf = (v) => String(v ?? '').split('.').map(n => parseInt(n, 10) || 0);
const compareVersion = (a, b) => { for (let i = 0; i < Math.max(a.length, b.length); i++) { const d = (a[i] || 0) - (b[i] || 0); if (d) return d; } return 0; };
const byId = new Map();
let removed = false;
// 폴더에서 파일 하나를 빼는 일. 옛 길은 곧바로 지우고, --apply · --layout-only는 끝난 뒤로 미룬다(`later` — 지울 폴더 자리. 준 파일이면 아직 폴더에
// 없으니 같은 이름의 옛 파일만 지운다 — 옛 길에서는 복사가 그 파일을 덮은 뒤 지웠다). --layout-only는 그 목록을 앱에 넘긴다(`folder.drop`).
// `laterTomb` = 그 가운데 묘비 DLC(이번에 빼는 것 · 앞서 뺀 것)의 파일(`folder.tomb`) — 앱은 이것만 '못 지우면 다음에 앱을 열 때 다시 지움'으로 알린다.
const later = [], laterTomb = [];
const drop = (entry, { tomb: dead = false } = {}) => {
  if (!inPlace) { fs.rmSync(entry.file); return; }
  later.push(entry.dst);
  if (dead) laterTomb.push(entry.dst);
};
if (removeKey === BASE) {
  if (state.baseRemoved) { console.error('동아시아 기본팩은 이미 빠져 있습니다.'); process.exit(1); }
  console.log('동아시아 기본팩을 뺍니다.');
  state.baseRemoved = true;
  removed = true;
}
const inFolder = fs.existsSync(dlcDir) ? fs.readdirSync(dlcDir).filter(f => /\.htpack$/i.test(f)) : [];
for (const name of [...new Set([...inFolder, ...givenSrc.keys()])].sort()) {
  const dst = path.join(dlcDir, name), file = givenSrc.get(name) || dst, meta = path.join(scratch, name + '.json');
  const entry = { file, dst };
  const run = spawnSync(tool, ['check-pack', file, meta], { encoding: 'utf8' });
  if (run.status !== 0) {
    // --layout-only(앱): 저장소가 하나뿐인 진실이라 폴더의 깨진 파일 하나로 넣기 · 빼기를 다 막지 않는다 — 그 파일만 건너뛰고 알린다(과제 8 고침 1회차 ·
    // 판정 R32). 준 파일 · 옛 길(다시 짓기 — 폴더가 '얹은 DLC의 목록')은 예전처럼 멈춘다.
    if (layoutOnly && !givenSrc.has(name)) { console.log(`DLC 폴더의 파일을 읽을 수 없어 건너뜁니다(${name}): ${(run.stderr || run.stdout || '').trim().slice(-200)}`); continue; }
    console.error(`DLC 파일을 읽을 수 없습니다(${name}): ${(run.stderr || run.stdout || '').trim().slice(-200)}`);
    process.exit(1);
  }
  const raw = JSON.parse(fs.readFileSync(meta, 'utf8'));
  const id = String(raw.id || ''), version = versionOf(raw.version);
  if (!id) { console.error(`DLC에 id가 없습니다: ${name}`); process.exit(1); }
  if (givenNames.has(name.toLowerCase())) givenIds.add(id);
  // 묘비의 DLC(위 0')): 뺀 DLC의 남은 파일은 마저 지우고(--layout-only는 앱이 고쳐 쓴 뒤 — 못 지우면 다음에 앱을 열 때 다시), 끈 DLC의 파일은 얹지 않고 둔다.
  if (!givenNames.has(name.toLowerCase()) && id !== removeKey && tomb.removed.has(id)) {
    console.log(`뺀 DLC의 남은 파일을 지웁니다(다시 얹지 않음): ${name}`);
    if (inPlace) { later.push(dst); laterTomb.push(dst); }
    else { try { fs.rmSync(file); } catch { /* 다음에 앱을 열 때 다시 지운다 */ } }
    continue;
  }
  if (!givenNames.has(name.toLowerCase()) && tomb.off.has(id) && !off.has(id) && !onKeys.includes(id)) {
    console.log(`끈 DLC의 파일은 얹지 않습니다(DLC\\sync.json): ${name}`);
    continue;
  }
  // 기본팩의 파일: 뺀 기본팩을 되살린다(기본팩은 도구의 packs/에서 늘 새로 만드므로 파일은 지운다). 들어 있으면 건너뜀.
  if (id === BASE) {
    if (state.baseRemoved && removeKey !== BASE) { console.log(`동아시아 기본팩을 되살립니다: ${name}`); state.baseRemoved = false; off.delete(BASE); }
    else console.error(`동아시아 기본팩은 이미 들어 있습니다(건너뜀): ${name}`);
    drop(entry);
    continue;
  }
  if (removeKey && id === removeKey) { console.log(`DLC를 뺍니다: ${String(raw.name || id)}(${name})`); drop(entry, { tomb: true }); removed = true; continue; }
  const seen = byId.get(id);
  const isGiven = preferGiven && givenNames.has(name.toLowerCase());
  if (seen && preferGiven && seen.given !== isGiven) {
    // 준 파일이 판과 상관없이 이긴다(메이커 미리보기 — 서재의 임시 사본에서만)
    const lose = isGiven ? seen : entry;
    console.log(`같은 DLC의 다른 파일을 지웁니다(준 파일이 이김): ${path.basename(lose.dst)}`);
    drop(lose);
    if (!isGiven) continue;
  } else if (seen && compareVersion(seen.version, version) >= 0) { console.log(`같은 DLC의 낮은 판을 지웁니다: ${name}`); drop(entry); continue; }
  else if (seen) { console.log(`같은 DLC의 낮은 판을 지웁니다: ${path.basename(seen.dst)}`); drop(seen); }
  // `fileName` = 폴더에 남을 파일 이름 — 옛 길이 이 이름 차례로 DLC를 놓는다(배치의 DLC 차례).
  byId.set(id, { id, file, dst, fileName: name, version, name: String(raw.name || id), versionText: String(raw.version ?? ''), given: isGiven });
  // 끈 DLC를 다시 더하면(새 판 · 같은 파일) 켠다 — 더하기는 켠 채 들어오는 길이다.
  if (givenNames.has(name.toLowerCase()) && off.delete(id)) console.log(`꺼 두었던 DLC를 켭니다: ${String(raw.name || id)}`);
}
// --apply · --layout-only는 여기서 갈라진다(DLC/ 폴더는 위에서 옛 길과 같게 맞춰 두었다) — 끝나면 돌아오지 않는다.
if (inPlace) applyInPlace();
if (removeKey && !removed) {
  // 원본 없이 들어온 DLC는 DLC/ 폴더에 파일이 없다 — 저장소가 그 DLC를 원본 없이 품고 있으면 빼기(그 DLC 없이 다시 짓기)는 된다.
  if (!noOriginal().some(p => p.id === removeKey)) { console.error(`뺄 DLC가 없습니다: ${removeKey}`); process.exit(1); }
  console.log(`DLC를 뺍니다(원본 없이 들어온 것): ${removeKey}`);
}
// 2') 원본 없는 DLC를 지키기(5-4 다): 저장소가 원본 없이 품은 DLC 가운데 DLC/ 폴더에도 파일이 없는 것이 있으면 다시 짓지 않는다.
const lost = noOriginal().filter(p => p.id !== removeKey && !byId.has(p.id));
if (lost.length) {
  console.error(`원본이 없는 DLC가 있어 다시 지을 수 없습니다: ${lost.map(p => `«${p.id}»${p.version ? `(v${p.version})` : ''}`).join(' · ')} — 다시 지으면 그 DLC가 사라집니다. `
    + `그 DLC의 .htpack을 넣어 주세요(이 도구에 파일로 주거나 ${dlcDir}에 두세요).`);
  process.exit(1);
}
// 2'') 끄기 · 켜기 — 끌 수 있는 것은 기본팩(빼지 않았으면)과 DLC/ 폴더에 파일이 있는 DLC뿐이다(원본 없는 DLC는 끄면 다시 켤 길이 없다).
if (removeKey) { off.delete(removeKey); delete state.cards[removeKey]; }
const known = id => (id === BASE ? !state.baseRemoved : byId.has(id));
for (const id of onKeys) {
  if (!known(id)) { console.error(`켤 DLC가 없습니다: ${id}`); process.exit(1); }
  off.delete(id);
}
for (const id of offKeys) {
  if (!known(id)) {
    console.error(noOriginal().some(p => p.id === id) ? `원본이 없는 DLC는 끌 수 없습니다(다시 켤 때 원본이 필요합니다): ${id} — 그 DLC의 .htpack을 ${dlcDir}에 넣어 주세요.` : `끌 DLC가 없습니다: ${id}`);
    process.exit(1);
  }
  off.add(id);
}
// 사라진 것(지운 파일 · 뺀 기본팩)은 끈 목록에서도 지운다.
for (const id of [...off]) if (!known(id)) off.delete(id);
// 끈 DLC의 카드: 지금 저장소에 있으면(이번에 끄는 것) 그 뼈대에서 뜨고, 없으면 예전 카드를 그대로 둔다.
const storeCards = off.size ? cardsOfStore() : {};
for (const id of Object.keys(state.cards)) if (!off.has(id)) delete state.cards[id];
for (const id of off) {
  if (storeCards[id]) state.cards[id] = storeCards[id];
  else if (!state.cards[id]) {
    const e = byId.get(id);
    state.cards[id] = { name: e ? e.name : (id === BASE ? '동아시아사 기본팩' : id), version: e ? e.versionText : '', events: 0, periods: 0, tracks: [] };
  }
}
for (const id of onKeys) console.log(`DLC를 켭니다: ${byId.get(id)?.name || (id === BASE ? '동아시아사 기본팩' : id)}`);
for (const id of offKeys) console.log(`DLC를 끕니다: ${state.cards[id]?.name || id}`);
const withBase = !state.baseRemoved && !off.has(BASE);
const extras = [...byId.values()].filter(e => !off.has(e.id));
/** 끈 목록을 적는다(지은 저장소를 바꿔 넣기 직전 · 다 꺼서 짓지 않을 때) — 원자적으로(8 검토 — 앱의 writeFileAtomic과 같은 길: 임시 파일에 다 쓰고
    이름을 바꿔 덮는다 · 이름 바꾸기가 막히면 30ms씩 세 번 더). 도중에 멈춰도 반쯤 쓴 끈 목록이 남지 않는다. */
const saveState = () => writeAtomic(statePath, JSON.stringify({ version: 1, off: [...off].sort(), baseRemoved: state.baseRemoved, cards: state.cards }, null, 1) + '\n');
function writeAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}-${Date.now()}.tmp`;
  try {
    fs.writeFileSync(temp, text);
    for (let retry = 0; ; retry++) {
      try { fs.renameSync(temp, file); break; } catch (e) {
        if (retry >= 3) throw e;
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 30);
      }
    }
  } catch (e) {
    try { fs.rmSync(temp, { force: true }); } catch { /* 없음 */ }
    throw e;
  }
}
// 다 껐다(기본팩도 빠지거나 꺼짐 · 켠 DLC 없음): 지을 것이 없다 — 저장소는 그대로 두고 끈 목록만 적는다. 앱은 끈 목록을 읽어 연표를 비운다.
if (!withBase && !extras.length) {
  saveState();
  if (outArg) fs.rmSync(path.resolve(outArg), { force: true });
  console.log('켠 DLC가 없습니다 — 저장소는 그대로 두고 끈 목록만 적었습니다(연표가 빕니다).');
  process.exit(0);
}
console.log(extras.length ? `얹는 DLC ${extras.length}벌: ${extras.map(e => `${e.name}(v${e.versionText || '?'})`).join(' · ')}${withBase ? '' : ' — 기본팩 없이'}` : '얹는 DLC 없음 — 동아시아 기본팩만으로 짓습니다.');

/** 지금 저장소의 뼈대에서 뜬 DLC 카드(글자 id마다) — 앱의 DlcCardInfo와 같은 값(이름 · 판 · 분류 · 사건 · 시대 · 제 트랙(이름 · 색 · 줄 수) · 얹은 트랙). */
function cardsOfStore() {
  if (!fs.existsSync(db)) return {};
  const run = spawnSync(tool, ['query', db, '{"op":"layout"}'], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (run.status !== 0) return {};
  try {
    const answer = JSON.parse(run.stdout.trim().split('\n').pop());
    const data = answer.data || answer;
    const tracks = (data.tracks || []).filter(t => !String(t.key || '').startsWith('__board'));
    const out = {};
    for (const p of data.packs || []) {
      if (!p.key) continue;
      const own = tracks.filter(t => t.pack === p.id);
      const shared = tracks.filter(t => t.pack !== p.id && (p.touches || []).includes(t.id));
      out[p.key] = {
        name: String(p.name || p.key), version: String(p.version ?? ''), category: String(p.category ?? ''), events: Number(p.events) || 0, periods: Number(p.periods) || 0,
        tracks: own.map(t => ({ key: String(t.key || ''), name: String(t.name || ''), color: Number(t.color) || 0, rows: (t.rows || []).length })),
        shared: shared.map(t => ({ key: String(t.key || ''), name: String(t.name || ''), color: Number(t.color) || 0, owner: String((data.packs.find(x => x.id === t.pack) || {}).name || '') })),
      };
    }
    return out;
  } catch { return {}; }
}

/** 저장소가 원본 없이 품은 DLC — `{"op":"info"}`의 `meta.pack_info`({"<번호>":{id,version,category,original}})에서 `original`이 거짓인 것(기본팩은 뺀다 —
    이 도구가 기본팩을 늘 새로 만든다. 기본팩을 끄거나 뺀 저장소에서는 가장 작은 번호가 기본팩이 아니므로 글자 id로 가린다). 저장소가 없거나 · 읽지 못하거나 · 옛 저장소(pack_info 없음)면 빈 목록. 한 번만 읽는다. */
function noOriginal() {
  if (!noOriginal.list) noOriginal.list = (packList() || []).filter(p => p.id && p.id !== BASE && !p.original).map(p => ({ id: p.id, version: p.version }));
  return noOriginal.list;
}

/** 저장소의 DLC 목록 — `meta.pack_info`를 번호 차례로(첫째 = 기본팩) `{number, id, version, original}`. 저장소가 없거나 · 읽지 못하거나 ·
    옛 저장소(pack_info 없음)면 null. `original` 열쇠가 없는 칸(옛 노드 길 — 원본을 다 품었다)은 참으로 읽는다. 한 번만 읽는다. */
function packList() {
  if (packList.done) return packList.list;
  packList.done = true;
  packList.list = null;
  if (!fs.existsSync(db)) return null;
  const run = spawnSync(tool, ['query', db, '{"op":"info"}'], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (run.status !== 0) return null;
  try {
    const answer = JSON.parse(run.stdout.trim().split('\n').pop());
    const raw = (answer.meta || (answer.data && answer.data.meta) || {}).pack_info;
    const info = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!info || typeof info !== 'object') return null;
    const numbers = Object.keys(info).map(Number).filter(Number.isFinite).sort((a, b) => a - b);
    const off = v => v === false || v === 0 || v === '0' || v === 'false';
    packList.list = numbers.map(n => ({ number: n, ...(info[String(n)] || {}) }))
      .map(p => ({ number: p.number, id: String(p.id ?? ''), version: String(p.version ?? ''), original: !off(p.original) }));
  } catch { /* 읽지 못하면 막지 않는다(옛 도구 · 옛 저장소) */ }
  return packList.list;
}

/** `--apply` · `--layout-only`(계약 2-7): 저장소의 원본으로 배치를 셈해 제자리에서 고쳐 쓴다(또는 배치 JSON만 낸다). 돌아오지 않는다. */
function applyInPlace() {
  const started = Date.now();
  const stop = (why) => { console.error(why); process.exit(1); };
  if (!fs.existsSync(db)) stop(`저장소가 없습니다: ${db} — 처음에는 --apply 없이 지어 주세요.`);
  const held = packList();
  if (!held || !held.length) stop('저장소의 DLC 목록(meta.pack_info)을 읽지 못했습니다 — 옛 저장소는 --apply 없이 한 번 다시 지어 주세요.');
  const rest = held.slice(1);
  if (held.some(p => !p.id)) stop('저장소에 DLC id가 없는 자료집이 있어 조합을 대조할 수 없습니다 — --apply 없이 한 번 다시 지어 주세요.');
  if (held[0].id !== BASE) stop('저장소의 첫 자료집이 동아시아 기본팩이 아닙니다(기본팩을 끄거나 뺀 저장소) — --apply 없이 다시 지어 주세요.');
  const inStore = (id) => rest.some(p => p.id === id);
  // 끈 DLC는 저장소에 없어야 한다(끄면 그 DLC를 뺀다) — 옛 길에서 다 꺼서 짓지 않은 저장소처럼 남아 있으면 다시 지어야 한다(--layout-only만 끈 목록을 받는다).
  const stuck = [...off].filter(id => !offKeys.includes(id) && inStore(id));
  if (stuck.length) stop(`끈 DLC가 저장소에 남아 있습니다(${stuck.join(' · ')}) — --layout-only 없이 다시 지어 주세요.`);
  // 끄기: 저장소에 있고 폴더에 파일이 있어야 한다(다시 켤 때 그 파일이 원본이다 — 옛 길과 같은 지킴).
  for (const id of offKeys) {
    if (!inStore(id)) stop(off.has(id) ? `이미 꺼 둔 DLC입니다: ${id}` : `끌 DLC가 저장소에 없습니다: ${id}`);
    if (!byId.has(id)) stop(`원본 파일이 DLC 폴더에 없는 DLC는 끌 수 없습니다(다시 켤 때 원본이 필요합니다): ${id} — 그 DLC의 .htpack을 ${dlcDir}에 넣어 주세요.`);
  }
  // 켜기: 폴더의 그 파일을 원본으로 준다(이미 저장소에 있으면 할 일 없음).
  for (const id of onKeys) {
    if (inStore(id)) continue;
    if (!byId.has(id)) stop(`켤 DLC가 없습니다(DLC 폴더에 그 파일이 없습니다): ${id}`);
    givenIds.add(id);
  }
  // 앞선 --apply --remove가 저장소는 고쳐 쓰고 DLC 폴더만 덜 맞췄으면(종료 코드 3) 그 DLC는 저장소에는 없고 폴더에만 남는다 —
  // 그때는 고쳐 쓰기에 빼기를 넘기지 않고(저장소는 그대로) 폴더만 마저 맞춘다.
  // 폴더만 맞추는 이 완화는 --apply에만 — --layout-only는 폴더를 바꾸지 않으므로 저장소에 없는 DLC를 빼라는 요청은 거절한다(끈 DLC만 예외 — 아래).
  const removeInStore = Boolean(removeKey) && inStore(removeKey);
  const folderOnly = Boolean(removeKey) && !removeInStore && removed && !layoutOnly;
  // --layout-only로 끈 DLC를 뺀다: 저장소에는 없으니(끌 때 뺐다) 엔진에 쓸 것이 없다 — 폴더의 파일과 끈 목록만 앱이 맞춘다.
  const offOnly = Boolean(layoutOnly) && Boolean(removeKey) && !removeInStore && off.has(removeKey);
  if (removeKey && !removeInStore && !folderOnly && !offOnly) stop(`뺄 DLC가 저장소에 없습니다: ${removeKey}`);
  if (folderOnly) console.log(`저장소에는 그 DLC가 없어 DLC 폴더만 맞춥니다: ${removeKey}`);
  /** 끝난 뒤 앱이 맞출 DLC/ 폴더(옛 길과 같게 — 준 파일 들이기 · 낮은 판 · 뺀 DLC 지우기)와 끈 목록(바뀌었을 때만). */
  const folderPlan = () => ({ copy: [...byId.values()].filter(e => path.resolve(e.file) !== path.resolve(e.dst)).map(e => [e.file, e.dst]), drop: later, tomb: laterTomb });
  const hiddenPlan = () => {
    if (removeKey) { off.delete(removeKey); delete state.cards[removeKey]; }
    for (const id of onKeys) off.delete(id);
    const cards = offKeys.length ? cardsOfStore() : {};
    for (const id of offKeys) {
      off.add(id);
      const e = byId.get(id);
      state.cards[id] = cards[id] || { name: e ? e.name : id, version: e ? e.versionText : '', events: 0, periods: 0, tracks: [] };
    }
    for (const id of Object.keys(state.cards)) if (!off.has(id)) delete state.cards[id];
    return stateText() === stateBefore ? null : { version: 1, off: [...off].sort(), baseRemoved: state.baseRemoved, cards: state.cards };
  };
  if (offOnly) {
    console.log(`꺼 둔 DLC를 뺍니다(저장소는 그대로 — DLC 폴더 · 끈 목록만): ${removeKey}`);
    console.log(JSON.stringify({ layout: null, originals: [], remove: [], folder: folderPlan(), hidden: hiddenPlan() }));
    process.exit(0);
  }
  // 남길 DLC = 저장소의 DLC(뺄 것 · 끌 것 빼고) ∪ 준 파일의 DLC(켤 것 포함). 원본은 ① 준 파일(DLC/ 폴더에 들인 것 — 같은 id는 판이 높은 것) → ② 저장소의 원본 →
  // ③ 원본 없이 든 DLC면 DLC/ 폴더의 그 파일(처음 한 번 저장소 안으로 들인다 — 옛 DLC의 약속 2). 셋 다 없으면 멈춘다.
  const ids = [...new Set([...rest.map(p => p.id), ...givenIds])].filter(id => id !== removeKey && id !== held[0].id && !offKeys.includes(id));
  const extras = [], lost = [];
  for (const id of ids) {
    const inStore = rest.find(p => p.id === id), local = byId.get(id);
    // 차례 열쇠(`order`) = 옛 길이 쓰는 DLC/ 폴더의 파일 이름(고쳐 쓴 뒤 폴더에 남을 이름). 폴더에 그 DLC의 파일이 없을 때만 지어낸 이름.
    const order = local ? local.fileName : `${id}-v${(inStore && inStore.version) || '0'}.htpack`;
    if (givenIds.has(id) && local) { extras.push({ id, file: local.file, order, name: local.name, version: local.versionText, give: true }); continue; }
    if (inStore && inStore.original) {
      const file = path.join(scratch, `${id.replace(/[^\w.-]/g, '_')}-v${inStore.version || '0'}.htpack`);
      const out = spawnSync(tool, ['pack-out', db, id, file], { encoding: 'utf8' });
      if (out.status !== 0) stop(`저장소에서 «${id}»의 원본을 꺼내지 못했습니다: ${(out.stderr || out.stdout || '').trim().slice(-300)}`);
      extras.push({ id, file, order, name: id, version: inStore.version, give: false });
      continue;
    }
    if (local) { console.log(`원본 없이 든 DLC «${id}»를 DLC 폴더의 파일로 저장소 안에 들입니다: ${local.fileName}`); extras.push({ id, file: local.file, order, name: local.name, version: local.versionText, give: true }); continue; }
    lost.push(inStore ? `«${id}»${inStore.version ? `(v${inStore.version})` : ''}` : `«${id}»`);
  }
  if (lost.length) stop(`원본이 저장소에도 ${dlcDir}에도 없는 DLC가 있습니다: ${lost.join(' · ')} — 그 DLC 파일을 다시 골라 주세요(이 도구에 .htpack으로 주세요).`);
  // 배치의 DLC 차례는 옛 길과 같게 DLC/ 폴더의 파일 이름 차례로(옛 길은 `readdirSync().sort()` — 같은 비교). DLC 차례는 트랙의 주인 · 같은 uid의 이김을 정한다.
  extras.sort((a, b) => (a.order < b.order ? -1 : a.order > b.order ? 1 : 0));
  console.log(extras.length ? `얹는 DLC ${extras.length}벌: ${extras.map(e => `${e.name}(v${e.version || '?'}${e.give ? '' : ' · 저장소의 원본'})`).join(' · ')}` : '얹는 DLC 없음 — 동아시아 기본팩만으로 셈합니다.');
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
  const layoutName = `dlc-apply-${stamp}.json`;
  const env = { ...process.env, HT_EXPORT_PACK: 'east-asia', HT_EXPORT_NAME: layoutName, HT_EXPORT_EXTRA: extras.map(e => e.file).join(';') };
  console.log('배치를 셈하는 중…');
  const exp = spawnSync(process.execPath, [path.join(scripts, 'export-layout.mjs')], { encoding: 'utf8', env, maxBuffer: 64 * 1024 * 1024 });
  if (exp.status !== 0) stop('배치 내보내기 실패:\n' + (exp.stderr || exp.stdout || '').split('\n').filter(l => !l.startsWith('    at ')).slice(-12).join('\n'));
  const exported = Date.now();
  const compat = path.join(prototype, 'results', 'compat');
  const layout = path.join(compat, layoutName), basePack = path.join(compat, 'east-asia.htpack');
  // 원본으로 넘기는 것: 기본팩(배치를 셈한 그 파일 — 같으면 엔진이 그대로 둔다) · 준 파일 · DLC/ 폴더에서 들이는 것. 저장소에서 꺼낸 것은 넘기지 않는다(그대로).
  const originals = [basePack, ...extras.filter(e => e.give).map(e => e.file)];
  const remove = [...(removeInStore ? [removeKey] : []), ...offKeys];
  if (layoutOnly) {
    const out = path.resolve(layoutOnly);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.copyFileSync(layout, out);
    fs.rmSync(layout, { force: true });
    console.log(`배치를 냈습니다(${((exported - started) / 1000).toFixed(1)}초): ${out}`);
    console.log(JSON.stringify({ layout: out, originals, remove, folder: folderPlan(), hidden: hiddenPlan() }));
    process.exit(0);
  }
  console.log(OPEN_APP);
  console.log('저장소를 제자리에서 고쳐 쓰는 중…');
  const run = spawnSync(tool, ['apply-layout', db, layout, ...originals, ...remove.map(id => `--remove=${id}`)], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  fs.rmSync(layout, { force: true });
  if (run.status !== 0) stop(`고쳐 쓰지 못했습니다(저장소 · DLC 폴더는 그대로): ${(run.stderr || run.stdout || '').trim().slice(-400)}`);
  const answer = JSON.parse(run.stdout.trim().split('\n').pop());
  // 고쳐 쓰기가 끝났다 — 이제 DLC/ 폴더를 옛 길과 같게 맞춘다. 준 파일을 먼저 들이고 뺄 파일은 그 뒤에 지운다(도중에 멈춰도 폴더에서 DLC가 먼저 사라지지 않게).
  // 저장소는 이미 고쳐 썼으므로 여기서 실패하면 따로 알린다(종료 코드 3) — 같은 명령을 다시 돌리면 저장소는 그대로 두고 폴더만 마저 맞춘다.
  try {
    fs.mkdirSync(dlcDir, { recursive: true });
    for (const e of byId.values()) if (path.resolve(e.file) !== path.resolve(e.dst)) fs.copyFileSync(e.file, e.dst);
    for (const file of later) fs.rmSync(file, { force: true });
  } catch (e) {
    console.error(`저장소는 이미 고쳐 썼고 DLC 폴더만 덜 맞췄습니다 — 같은 명령을 다시 돌리면 맞춥니다(${dlcDir}): ${e.message}`);
    console.log(JSON.stringify(answer));
    process.exit(3);
  }
  const s = (ms) => (ms / 1000).toFixed(1);
  console.log(`끝. 저장소를 제자리에서 고쳐 썼습니다: ${db}`);
  console.log(`다시 쓴 트랙 ${answer.rewrote.length} · 새 트랙 ${answer.added.length} · 뺀 트랙 ${answer.removed.length} · 줄 ${answer.rows_before} → ${answer.rows_after}`
    + ` · 배치 셈 ${s(exported - started)}초 · 고쳐 쓰기 ${s(answer.ms)}초 · 모두 ${s(Date.now() - started)}초`);
  console.log(JSON.stringify(answer));
  process.exit(0);
}

// 3) 배치를 내보낸다(지금 연표의 셈 그대로) → 4) 엔진의 가져오기로 새 저장소를 짓는다.
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
const layoutName = `dlc-${stamp}.json`;
// 기본팩을 끄거나 뺐으면 켠 DLC의 첫째가 기본 자리에 선다(HT_EXPORT_PACK=- · 가져오기의 첫 원본도 그 파일).
const env = { ...process.env, HT_EXPORT_PACK: withBase ? 'east-asia' : '-', HT_EXPORT_NAME: layoutName, HT_EXPORT_EXTRA: extras.map(e => e.file).join(';') };
console.log('배치를 셈하는 중…');
const exp = spawnSync(process.execPath, [path.join(scripts, 'export-layout.mjs')], { encoding: 'utf8', env, maxBuffer: 64 * 1024 * 1024 });
if (exp.status !== 0) { console.error('배치 내보내기 실패:\n' + (exp.stderr || exp.stdout || '').split('\n').filter(l => !l.startsWith('    at ')).slice(-12).join('\n')); process.exit(1); }
const compat = path.join(prototype, 'results', 'compat');
const layout = path.join(compat, layoutName), basePack = path.join(compat, 'east-asia.htpack');
const fresh = path.join(scratch, 'archive.db');
console.log('저장소를 짓는 중…');
const sources = withBase ? [basePack, ...extras.map(e => e.file)] : extras.map(e => e.file);
const imp = spawnSync(tool, ['import-layout', sources[0], layout, fresh, ...sources.slice(1)], { encoding: 'utf8' });
if (imp.status !== 0) { console.error('저장소 짓기 실패: ' + (imp.stderr || imp.stdout || '').trim().slice(-400)); process.exit(1); }
const check = spawnSync(tool, ['verify-tiles', fresh, '120'], { encoding: 'utf8' });
if (check.status !== 0 || !/"누락_중복":0/.test(check.stdout)) { console.error('지은 저장소의 타일 검사가 어긋났습니다: ' + (check.stdout || check.stderr || '').trim().slice(-300)); process.exit(1); }

// 5) `--out`이면 지은 것을 거기에 두고 끝낸다 — 바꿔 넣기는 앱의 몫(열린 저장소를 건드리지 않는다).
if (outArg) {
  const out = path.resolve(outArg);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.copyFileSync(fresh, out);
  saveState();
  fs.rmSync(scratch, { recursive: true, force: true });
  fs.rmSync(layout, { force: true });
  console.log(`지었습니다: ${out}`);
  process.exit(0);
}
// 5') 제자리에 바꿔 넣는다. 앱이 열어 두고 있으면 실패한다 — 그때는 지은 것을 버리지 않고 옆에 둔다.
// 옛 백업은 새 백업이 무사히 만들어진 뒤에만 지운다(먼저 지우면, 바꿔 넣기가 실패했을 때 백업까지 잃는다 — 2026-09-22에 실제로 겪음).
const backup = path.join(folder, 'archive.이전.db'), older = path.join(folder, 'archive.이전.old');
try {
  if (fs.existsSync(db)) {
    fs.rmSync(older, { force: true });
    if (fs.existsSync(backup)) fs.renameSync(backup, older);
    try { fs.renameSync(db, backup); } catch (e) { if (fs.existsSync(older)) fs.renameSync(older, backup); throw e; }
  }
  fs.copyFileSync(fresh, db);
  fs.rmSync(older, { force: true });
  saveState();
} catch (e) {
  const aside = path.join(folder, 'archive.새로-지음.db');
  fs.copyFileSync(fresh, aside);
  if (!fs.existsSync(db) && fs.existsSync(backup)) fs.renameSync(backup, db);
  console.error(`저장소를 바꿔 넣지 못했습니다(앱이 열어 두고 있으면 앱을 닫고 다시 돌리세요): ${e.message}\n지은 저장소는 여기 두었습니다: ${aside}`);
  process.exit(1);
}
fs.rmSync(scratch, { recursive: true, force: true });
fs.rmSync(layout, { force: true });
console.log(`끝. 저장소를 다시 지었습니다: ${db}\n앱을 다시 열면 DLC 관리에 ${extras.length ? extras.map(e => e.name).join(' · ') + '이(가) ' : ''}보입니다. 옛 저장소: ${path.basename(backup)}`);

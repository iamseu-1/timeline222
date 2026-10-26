// add-dlc.mjs의 묘비(DLC/sync.json) 규칙이 앱(ui/dlc_add.dart DlcFolderState · ui/seed_carry.dart DlcFolderSync)과 같은지 진짜 도구로 본다(과제 8 검토).
//   1) sync.json이 있는데 읽지 못하면 멈춘다(종료 1 — 빈 묘비로 보면 뺀 DLC가 되살아난다) · 저장소 · 폴더 그대로.
//   2) 지금 저장소에 든 DLC의 묘비(removed · off)는 보지 않는다 — 그 DLC의 폴더 파일을 지우지도 건너뛰지도 않고, 끌 수도 있다.
//   3) 저장소에 없는 DLC의 removed 묘비 파일은 folder.drop과 folder.tomb에 · 빼는 DLC의 파일도 tomb에 · 같은 id 낮은 판(같은 판 겹침)은 drop에만.
//   4) 끈 목록(hidden.json)은 원자적으로 쓴다 — 다시 짓기 길에서 쓴 뒤 임시 파일(*.tmp)이 남지 않는다.
// 사용: node prototype/scripts/add-dlc-tomb-check.mjs [--keep]   (임시 폴더 <TMP>/add-dlc-tomb-check — 끝나면 지운다. 어긋나면 남긴다.)
//   (환경 변수) HT_ADD_DLC=<다른 add-dlc.mjs — 고치기 전 판과 견줄 때> · HT_ARCHIVE_TOOL=<archive-tool 경로>.
// 필요한 것: Node.js · 엔진 도구(archive-tool — prototype/engine/target/release/) · 고정 자료 fixtures/oracle/move-scene · nest-scene.htpack.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { useCalendarCopy } from './oracle/cal-copy.mjs';

useCalendarCopy('add-dlc-tomb-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const oracle = path.join(prototype, 'fixtures', 'oracle');
const keep = process.argv.includes('--keep');
const work = path.join(process.env.TMP || process.env.TEMP || os.tmpdir(), 'add-dlc-tomb-check');
const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [process.env.HT_ARCHIVE_TOOL || '', ...[prototype, path.join(prototype, 'engine', 'target', 'release')].flatMap(dir => toolNames.map(n => path.join(dir, n)))]
  .find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) { console.error(`엔진 도구(${toolNames[0]})가 없습니다 — 먼저 cargo build --release --locked.`); process.exit(1); }

const results = [];
const check = (ok, what, detail) => { results.push(ok); console.log(`${ok ? '맞음' : '어긋남'} — ${what}${ok || detail === undefined ? '' : `\n    ${JSON.stringify(detail)}`}`); };
const idOf = (file) => {
  const out = path.join(work, `check-${path.basename(file)}.json`);
  const r = spawnSync(tool, ['check-pack', file, out], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`check-pack 실패: ${file}`);
  return JSON.parse(fs.readFileSync(out, 'utf8')).id;
};
const db = path.join(work, 'archive.db'), dlc = path.join(work, 'DLC'), syncFile = path.join(dlc, 'sync.json');
/** add-dlc.mjs를 돌린다 — 종료 코드 · 표준 출력 · 오류 · 마지막 줄의 요청 재료(--layout-only). */
const addDlc = (...args) => {
  const r = spawnSync(process.execPath, [process.env.HT_ADD_DLC || path.join(scripts, 'add-dlc.mjs'), db, ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const last = String(r.stdout || '').trim().split('\n').pop() || '';
  let plan = null;
  try { plan = last.startsWith('{') ? JSON.parse(last) : null; } catch { /* 요청 재료 없음 */ }
  if (plan && plan.layout) fs.rmSync(plan.layout, { force: true });
  return { status: r.status, out: String(r.stdout || ''), err: String(r.stderr || ''), plan };
};
const layoutArg = () => `--layout-only=${path.join(work, 'layout.json')}`;
const writeSync = (value) => fs.writeFileSync(syncFile, typeof value === 'string' ? value : JSON.stringify({ version: 1, ...value }));
const same = (a, b) => JSON.stringify([...a].map(f => path.resolve(f)).sort()) === JSON.stringify([...b].map(f => path.resolve(f)).sort());

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
try {
  const move = path.join(oracle, 'move-scene.htpack'), nest = path.join(oracle, 'nest-scene.htpack');
  const moveId = idOf(move), nestId = idOf(nest);
  // 바탕: 동아시아 + move-scene을 다시 짓기 길로 짓는다(DLC/에 move-scene.htpack · hidden.json을 쓴다).
  console.log('바탕 저장소를 짓는 중(동아시아 + move-scene)…');
  const built = addDlc(move);
  if (built.status !== 0) throw new Error(`바탕 짓기 실패: ${(built.err || built.out).slice(-400)}`);
  const leftovers = fs.readdirSync(dlc).filter(n => n.endsWith('.tmp'));
  check(leftovers.length === 0 && fs.existsSync(path.join(dlc, 'hidden.json')), '4) 끈 목록은 원자적으로 — 쓴 뒤 임시 파일이 남지 않는다', leftovers);
  const moveFile = path.join(dlc, path.basename(move));

  // 1) 깨진 sync.json → 멈춤.
  writeSync('[1,');
  const dbBefore = fs.statSync(db).mtimeMs, filesBefore = fs.readdirSync(dlc).sort().join('|');
  const broken = addDlc(layoutArg());
  check(broken.status === 1 && /sync\.json/.test(broken.err) && /지우거나 고친/.test(broken.err), '1) 깨진 sync.json이면 멈춘다(종료 1 · 지우거나 고치면)', { 종료: broken.status, 오류: broken.err.slice(-300) });
  check(fs.statSync(db).mtimeMs === dbBefore && fs.readdirSync(dlc).sort().join('|') === filesBefore, '1) 저장소 · DLC 폴더 그대로');
  writeSync('{"version":1,"removed":"아님"}');
  const odd = addDlc(layoutArg());
  check(odd.status === 1 && /sync\.json/.test(odd.err), '1) 묘비 칸이 목록이 아닌 sync.json도 읽지 못한 것으로(앱의 DlcFolderState.read와 같음)', { 종료: odd.status, 오류: odd.err.slice(-300) });
  writeSync({ removed: null, skip: '아님' });
  const loose = addDlc(layoutArg());
  check(loose.status === 0, '1) 칸이 비었거나(null) 건너뛸 표만 꼴이 다르면 묘비 없음으로 읽는다(앱과 같음)', { 종료: loose.status, 오류: loose.err.slice(-300) });

  // 2) 저장소에 든 DLC의 묘비는 보지 않는다.
  writeSync({ removed: [moveId], off: [] });
  const keepStored = addDlc(layoutArg());
  check(keepStored.status === 0 && keepStored.plan && !keepStored.plan.folder.drop.some(f => path.resolve(f) === path.resolve(moveFile)),
    '2) 저장소에 든 DLC의 removed 묘비 — 그 폴더 파일을 지우지 않는다', { 종료: keepStored.status, drop: keepStored.plan?.folder?.drop, 오류: keepStored.err.slice(-300) });
  check(!/뺀 DLC의 남은 파일을 지웁니다/.test(keepStored.out), '2) "뺀 DLC의 남은 파일을 지웁니다"를 말하지 않는다');
  writeSync({ removed: [], off: [moveId] });
  const offStored = addDlc(layoutArg(), `--off=${moveId}`);
  check(offStored.status === 0 && offStored.plan && offStored.plan.remove.includes(moveId),
    '2) 저장소에 든 DLC의 off 묘비 — 그 파일을 건너뛰지 않아 끌 수 있다(다시 켤 원본)', { 종료: offStored.status, remove: offStored.plan?.remove, 오류: offStored.err.slice(-300) });

  // 3) 저장소에 없는 DLC의 묘비 파일 · 빼는 DLC의 파일은 tomb에 · 같은 판 겹침은 drop에만.
  const nestFile = path.join(dlc, path.basename(nest)), dupFile = path.join(dlc, 'move-scene-copy.htpack');
  fs.copyFileSync(nest, nestFile);
  fs.copyFileSync(move, dupFile);
  writeSync({ removed: [nestId], off: [] });
  const plain = addDlc(layoutArg());
  const p3 = plain.plan?.folder;
  check(plain.status === 0 && p3 && p3.tomb && same(p3.tomb, [nestFile]) && p3.drop.some(f => path.resolve(f) === path.resolve(nestFile)),
    '3) 저장소에 없는 DLC의 removed 묘비 파일은 drop과 tomb에', { 종료: plain.status, folder: p3, 오류: plain.err.slice(-300) });
  const dupDropped = p3 ? p3.drop.filter(f => [moveFile, dupFile].some(m => path.resolve(m) === path.resolve(f))) : [];
  check(dupDropped.length === 1 && !p3.tomb.some(f => path.resolve(f) === path.resolve(dupDropped[0])),
    '3) 같은 DLC의 겹친 파일(낮은 · 같은 판)은 drop에만 — tomb에 없다', { drop: p3?.drop, tomb: p3?.tomb });
  const removing = addDlc(layoutArg(), `--remove=${moveId}`);
  const p4 = removing.plan?.folder;
  check(removing.status === 0 && p4 && same(p4.tomb, [nestFile, moveFile, dupFile]) && same(p4.drop, [nestFile, moveFile, dupFile]),
    '3) 빼는 DLC의 파일(둘 다)과 묘비 파일이 tomb에', { 종료: removing.status, folder: p4, 오류: removing.err.slice(-300) });
} catch (e) {
  results.push(false);
  console.error(`검사를 끝까지 돌리지 못했습니다: ${e.message}`);
}
const bad = results.filter(ok => !ok).length;
console.log(`${bad ? `어긋남 ${bad}` : '모두 맞음'} · ${results.length}가지`);
if (!bad && !keep) fs.rmSync(work, { recursive: true, force: true });
else console.log(`작업 폴더를 남겼습니다: ${work}`);
process.exit(bad ? 1 : 0);

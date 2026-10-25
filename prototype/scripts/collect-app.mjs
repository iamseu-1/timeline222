// 감독에게 건네는 가벼운 산출물: 지금 빌드한 새 앱(Windows 실행본)과 동아시아 · 등불 연대기(견본) 저장소, (있으면) 안드로이드 설치 파일을
// 저장소 뿌리의 배포/<이름>/에 모은다(무시 폴더 — 원격 전송 · 게시는 하지 않는다). 측정 기록 · 1배 비교 · 가상 100만은 collect-release3.mjs의 몫.
// 사용: node prototype/scripts/collect-app.mjs <주 저장소 뿌리> <폴더 이름> --east-asia <저장소 폴더> --lantern <저장소 폴더>
//        [--note <안내에 넣을 한 줄>] [--apk results/android/archive-app.apk] [--apk-note <글>]
//        --east-asia · --lantern(꼭 줌): 저장소 폴더(그 안의 archive.db) · prototype/ 기준. 저장소는 build-showcase.mjs의 출력
//        (엔진 archive-tool build로 지어 달력 표가 든 것 — 표 없는 저장소에서는 앱이 DLC를 넣고 빼지 못한다 · 판정 R36)을 준다
//        (예: node prototype/scripts/build-showcase.mjs prototype/data/showcase1 뒤 --east-asia data/showcase1/showcase --lantern data/showcase1/lantern).
//        저장소가 없거나 달력 표(blobs의 calendar:table — archive-tool blob으로 확인)가 없으면 모으지 않고 멈춘다.
// 기본으로 여는 것은 동아시아 DLC다(감독 지시 2026-09-22: 보여 주는 것은 동아시아로). 견본은 등불 연대기 하나뿐이다(2026-10-14 — 옛 견본은 모두 지움).
// 도구/에는 엔진 도구(archive-tool.exe)와 동아시아 기본팩 원본만 담는다 — 앱이 DLC를 엔진으로 넣고 빼므로 Node.js · 지금 연표의 셈(js) · 배치 내보내기 ·
// add-dlc.mjs · DLC-추가.cmd는 담지 않는다(한 벌 P4 과제 11 · 판정 R49 — bundle-app.mjs와 같은 구성).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [mainRoot, name] = process.argv.slice(2);
const flag = (key, fallback) => { const i = process.argv.indexOf(key); return i >= 0 ? process.argv[i + 1] : fallback; };
const usage = '사용: collect-app.mjs <주 저장소 뿌리> <폴더 이름> --east-asia <저장소 폴더> --lantern <저장소 폴더> [--note …] [--apk …] [--apk-note …]';
if (!mainRoot || !name || !flag('--east-asia', '') || !flag('--lantern', '')) { console.error(usage); process.exit(2); }
const target = path.join(path.resolve(mainRoot), '배포', name);
if (fs.existsSync(target)) { console.error('이미 있는 산출물 폴더는 덮어쓰지 않습니다: ' + target); process.exit(1); }
const tool = path.join(prototype, 'engine', 'target', 'release', 'archive-tool.exe');
if (!fs.existsSync(tool)) { console.error('엔진 도구가 없습니다(dev.ps1 engine-build): ' + tool); process.exit(1); }
// 모으기 전에 저장소마다 있는지 · 달력 표가 들었는지 본다(표 없는 저장소는 앱이 DLC를 넣고 빼지 못한다 — 판정 R36).
const packs = [['동아시아', flag('--east-asia', '')], ['등불 연대기', flag('--lantern', '')]];
for (const [label, dir] of packs) {
  const db = path.resolve(prototype, dir, 'archive.db');
  if (!fs.existsSync(db)) { console.error(`${label} 저장소가 없습니다: ${db}`); process.exit(1); }
  const scratch = fs.mkdtempSync(path.join(process.env.TMP || process.env.TEMP || prototype, 'ht-collect-'));
  const table = path.join(scratch, 'calendar-table.zlib');
  const r = spawnSync(tool, ['blob', db, 'calendar:table', table], { encoding: 'utf8' });
  const ok = r.status === 0 && fs.existsSync(table) && fs.statSync(table).size >= 1024;
  fs.rmSync(scratch, { recursive: true, force: true });
  if (!ok) { console.error(`${label} 저장소에 달력 표(calendar:table)가 없습니다 — build-showcase.mjs(archive-tool build)로 지은 저장소를 주세요: ${db}`); process.exit(1); }
}

// fs.cpSync는 이 PC의 Node 24에서 한글이 든 경로를 만나면 말없이 죽는다 — 파일마다 직접 복사한다(collect-release3.mjs와 같은 까닭).
const copy = (from, to, skip = []) => {
  if (!fs.existsSync(from)) { console.error('없음(건너뜀): ' + from); return; }
  if (fs.statSync(from).isDirectory()) {
    if (skip.includes(path.basename(from))) return;
    fs.mkdirSync(to, { recursive: true });
    for (const one of fs.readdirSync(from)) copy(path.join(from, one), path.join(to, one), skip);
  } else {
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
  }
};

const release = path.join(prototype, 'app/build/windows/x64/runner/Release');
if (!fs.existsSync(path.join(release, 'archive_prototype.exe'))) { console.error('실행본이 없습니다. scripts/dev.ps1 app-build 를 먼저 돌리세요.'); process.exit(1); }
copy(release, path.join(target, 'Windows'), ['측정-결과']);
fs.writeFileSync(path.join(target, 'Windows', 'prototype.json'), JSON.stringify({ database: '../자료/동아시아/archive.db' }, null, 2) + '\n');
for (const [label, dir] of packs) {
  copy(path.resolve(prototype, dir, 'archive.db'), path.join(target, '자료', label, 'archive.db'));
  fs.mkdirSync(path.join(target, '자료', label, 'DLC'), { recursive: true }); // 앱의 DLC 폴더(넣은 DLC 파일 · 끈 목록 · 묘비)
  fs.writeFileSync(path.join(target, `${label}-열기.cmd`), `@echo off\r\nchcp 65001 >nul\r\nstart "" "%~dp0Windows\\archive_prototype.exe" --db="%~dp0자료\\${label}\\archive.db"\r\n`);
}
const apk = flag('--apk', '');
if (apk) copy(path.join(prototype, apk), path.join(target, 'Android', '아카이브-앱-시험판.apk'));

// 도구: 엔진 도구(앱이 시드 잇기의 원본 꺼내기 · 판 올림 뒤 DLC 폴더 다시 들이기에 쓴다 — ui/dlc_add.dart `DlcTools`가 찾는 자리)와
// 동아시아 기본팩 원본(바탕이 아닌 자리에서 뺀 기본팩을 되살릴 때 고르는 파일 — 앱의 기본팩 삭제 확인 글이 가리키는 자리 · 동아시아 저장소에서 꺼낸다).
const tools = path.join(target, '도구');
copy(tool, path.join(tools, 'prototype', 'archive-tool.exe'));
const eastAsia = path.join(target, '자료', '동아시아', 'archive.db'), basePack = path.join(tools, 'prototype', 'results', 'compat', 'east-asia.htpack');
if (fs.existsSync(tool) && fs.existsSync(eastAsia)) {
  fs.mkdirSync(path.dirname(basePack), { recursive: true });
  const r = spawnSync(tool, ['pack-out', eastAsia, 'east-asia-base', basePack], { encoding: 'utf8' });
  if (r.status !== 0) console.error(`동아시아 기본팩 원본을 꺼내지 못했습니다(도구\\prototype\\results\\compat\\east-asia.htpack 없음): ${(r.stderr || r.stdout || '').trim().slice(-300)}`);
}

const note = flag('--note', ''), apkNote = flag('--apk-note', '');
fs.writeFileSync(path.join(target, '사용-안내.md'), `# 별여울 아카이브(새 엔진) — ${name}

컴퓨터(Windows)용 보기 전용 앱입니다. 인터넷에 아무것도 보내지 않습니다.
${note ? `\n${note}\n` : ''}
## 열기

- \`동아시아-열기.cmd\` — 동아시아사 기본팩(실제 자료). 평소에 보실 것은 이것입니다.
- \`등불 연대기-열기.cmd\` — 등불 연대기(견본 — 지어낸 나라와 사람으로 연표의 기능을 모두 보여 주는 가상 세계 하나).
- \`Windows\\archive_prototype.exe\`를 바로 열어도 동아시아가 열립니다.

## 움직이기

- 끌기 = 이동 · 휠 = 기간 확대/축소 · Ctrl + 휠 = 돋보기 · 오른쪽 클릭 = 메뉴(DLC 관리 · 필터 · 조감 · 범례 · 표 보기 …)
- 누르면 오른쪽에 상세 창 · 다른 곳을 누르면 닫힘 · \`/\` 검색 · \`F\` 필터 · \`V\` 조감 · \`D\` DLC 관리 · \`Z\` 집중 모드

## DLC 더하기 · 빼기

1. DLC 메이커에서 늘 하던 대로 \`.htpack\`으로 저장합니다.
2. 앱의 DLC 관리(\`D\` · 오른쪽 클릭 메뉴)에서 **\`📂 파일에서 더하기…\`**를 누르고 그 파일을 고릅니다(여러 개도 됩니다). 앱은 그대로 쓸 수 있고, 앱이 저장소를 제자리에서 고쳐 쓰는 동안 창 위 칸과 알림 줄에 진행이 보입니다. 끝나면 새 DLC의 트랙이 제자리에서 자라나고 카드가 켜진 채 생깁니다 — 앱을 닫거나 다시 켜지 않습니다.
3. 빼기: DLC 관리에서 그 카드를 고르고 자세히의 **\`DLC 삭제\`**를 누릅니다. 저장소의 바탕(첫 DLC)은 뺄 수 없습니다(바탕이 아닌 자리의 동아시아 기본팩을 뺐다가 다시 넣으려면 \`도구\\prototype\\results\\compat\\east-asia.htpack\`을 더합니다).
4. 켜고 끄기도 스르륵 흐릅니다(켠 트랙은 0에서 자라나고 끈 트랙은 접힙니다). 끈 DLC는 저장소에서 빠져 날짜 칸 · 검색 · 필터 어디에도 남지 않습니다 — 끈 카드는 그대로 남아 다시 켤 수 있습니다.
- 같은 DLC를 고쳐 다시 저장했으면 다시 더하면 됩니다(판이 같거나 높은 것으로 바뀝니다 — 낮은 판은 받지 않습니다).
- 새 판을 받으면 옛 폴더 위에 덮어 놓지 말고 **새 폴더**에 둡니다(옛 저장소의 일지 파일이 새 저장소를 망칠 수 있습니다). 더해 둔 DLC는 옛 폴더의 \`자료\\<저장소>\\DLC\` 폴더를 통째로 새 폴더의 같은 자리에 옮기면 새 판의 앱이 열 때 다시 넣습니다.
- \`.htpack\` 파일을 앱 실행 파일 위에 끌어다 놓거나 연결 프로그램으로 열어도 앱이 뜬 뒤에 더합니다.
${apk ? `\n## 안드로이드(시험판)\n\n- \`Android\\아카이브-앱-시험판.apk\` — 휴대폰 시험판입니다(든 저장소는 그 APK를 지을 때 고른 시드 — 동아시아 또는 등불 연대기). 한 손가락 끌기 = 이동 · 두 손가락 벌리기 = 기간 확대 · 길게 누르기 = 메뉴 · 가로 화면 고정.\n${apkNote ? `- ${apkNote}\n` : ''}` : ''}`);
const size = (dir) => fs.readdirSync(dir, { withFileTypes: true }).reduce((sum, e) => sum + (e.isDirectory() ? size(path.join(dir, e.name)) : fs.statSync(path.join(dir, e.name)).size), 0);
console.log(`모음: ${target} · ${(size(target) / 1048576).toFixed(0)}MiB`);

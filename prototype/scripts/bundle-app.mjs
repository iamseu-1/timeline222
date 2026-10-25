// 독립형 연표 앱 꾸러미 짓기 — 릴리즈(GitHub Actions)의 Windows 포터블 zip과 설치 파일이 담는 폴더를 한 번에 모은다.
// collect-app.mjs(감독에게 건네는 배포/ 모음)와 같은 구성을 따르되, 출력 폴더 · 저장소 목록(build-showcase.mjs의 showcase.json) ·
// 엔진 도구의 자리를 인자로 받는다(CI에서 쓰려고).
//
// 사용: node prototype/scripts/bundle-app.mjs --out=<새 폴더> --showcase=<build-showcase.mjs의 출력 폴더>
//         --release=<Flutter Windows Release 폴더> --tool=<archive-tool(.exe)> [--version=<판>] [--exe=archive_prototype.exe]
//   --out       새 폴더(없거나 빈 폴더). 이미 무엇이 든 폴더는 덮어쓰지 않는다.
//   --showcase  build-showcase.mjs의 출력 폴더(showcase.json · <저장소>/archive.db · <저장소>/base.htpack · 얹은 견본이 있으면 showcase/DLC/*.htpack).
//   --release   prototype/app/build/windows/x64/runner/Release(실행 파일 · archive_engine.dll · data/ …). 실행 파일 이름은 --exe.
//   --tool      엔진 도구 — 도구/prototype/ 아래에 그 이름 그대로 둔다(앱의 ui/dlc_add.dart `DlcTools`가 찾는 자리).
//   --version   사용-안내.md의 머리에 적을 판(없으면 package.json의 version).
//
// 출력(--out 아래):
//   Windows/                       Release 폴더 그대로 + prototype.json(기본으로 여는 저장소 = 동아시아)
//   자료/<이름>/archive.db         showcase.json의 저장소마다(이름 = 목록의 label — 동아시아 · 등불 연대기 …). build-showcase.mjs가 엔진(archive-tool build)으로
//                                  지어 달력 표가 들었다 — 앱이 이 저장소에서 DLC를 넣고 뺀다(엔진은 표 없는 저장소를 거절 · 판정 R36).
//                                  저장소마다 앱의 DLC/ 폴더(넣은 DLC 파일 · 끈 목록 · 묘비 — 판 올림 뒤 다시 들이기 R32 · R33). 얹은 견본이 있으면 그 원본도.
//   자료/목록.json                 showcase.json 사본(무엇이 들었는지)
//   bundle.json                    포장 · 연기 검사 스크립트가 읽는 목록(판 · 실행 파일 · 저장소 이름과 자리 — 한글 이름을 ASCII 스크립트에 건네려고)
//   <이름>-열기.cmd                저장소마다 앱을 그 저장소로 연다(--db=…)
//   도구/prototype/archive-tool.exe 엔진 도구 — 앱이 시드 잇기의 원본 꺼내기 · 판 올림 뒤 DLC 폴더 다시 들이기(파일 읽기)에 쓴다. 넣고 빼기 자체는 앱 안의
//                                  자료 처리부(archive_engine.dll)가 한다 — Node.js · 지금 연표의 셈(js) · 배치 내보내기는 싣지 않는다(한 벌 P4 과제 11 · 판정 R49).
//   도구/prototype/results/compat/east-asia.htpack  동아시아 기본팩 원본 — 바탕이 아닌 자리에서 뺀 기본팩을 '파일에서 더하기'로 되살릴 때 고르는 파일
//                                  (앱의 기본팩 삭제 확인 글이 이 자리를 가리킨다). 설치는 새 판마다 이 폴더(results)를 지우고 새로 놓는다.
//   사용-안내.md
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const root = path.resolve(prototype, '..');
const args = process.argv.slice(2);
const option = (name, fallback = '') => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const fail = (message) => { console.error(message); process.exit(1); };
const outArg = option('out'), showcaseArg = option('showcase'), releaseArg = option('release'), toolArg = option('tool');
if (!outArg || !showcaseArg || !releaseArg || !toolArg) {
  fail('사용: bundle-app.mjs --out=<새 폴더> --showcase=<build-showcase 출력> --release=<Flutter Release 폴더> --tool=<archive-tool(.exe)> [--version=<판>] [--exe=archive_prototype.exe]');
}
if (option('node')) console.warn('--node는 더 쓰지 않습니다(꾸러미에 Node.js를 싣지 않음 — 앱이 DLC를 엔진으로 넣고 뺀다) — 건너뜁니다.');
const out = path.resolve(outArg), showcase = path.resolve(showcaseArg), release = path.resolve(releaseArg), tool = path.resolve(toolArg);
const exeName = option('exe', 'archive_prototype.exe');
const version = option('version') || JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version;
/** 사람에게 보이는 이름(설치 프로그램 · 시작 메뉴). 실행 파일 · 창 제목은 앱 코드의 것 그대로다(archive_prototype.exe · '별여울 아카이브 - 성능 시제품'). */
const TITLE = '역사 연표 독립형';
const BASE_ID = 'east-asia-base';
if (fs.existsSync(out) && fs.readdirSync(out).length) fail(`이미 무엇이 든 폴더는 덮어쓰지 않습니다: ${out}`);
if (!fs.existsSync(path.join(release, exeName))) fail(`실행 파일이 없습니다: ${path.join(release, exeName)} — flutter build windows --release를 먼저.`);
if (!fs.existsSync(path.join(release, 'archive_engine.dll')) && exeName.endsWith('.exe')) fail(`자료 처리부(archive_engine.dll)가 Release 폴더에 없습니다: ${release}`);
if (!fs.existsSync(tool)) fail(`엔진 도구가 없습니다: ${tool}`);
const listing = JSON.parse(fs.readFileSync(path.join(showcase, 'showcase.json'), 'utf8'));
if (listing.kind !== 'history-timeline-showcase' || !Array.isArray(listing.stores) || !listing.stores.length) fail(`견본 목록이 아닙니다: ${path.join(showcase, 'showcase.json')}`);

// fs.cpSync는 한글이 든 경로에서 말없이 죽은 적이 있다(collect-app.mjs 머리말) — 파일마다 직접 복사한다.
const copy = (from, to, skip = []) => {
  if (!fs.existsSync(from)) fail(`없음: ${from}`);
  if (fs.statSync(from).isDirectory()) {
    if (skip.includes(path.basename(from))) return;
    fs.mkdirSync(to, { recursive: true });
    for (const one of fs.readdirSync(from)) copy(path.join(from, one), path.join(to, one), skip);
  } else {
    if (skip.includes(path.basename(from))) return;
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
  }
};
// Windows의 배치 파일: CRLF · UTF-8(chcp 65001) — collect-app.mjs와 같은 꼴.
const writeCmd = (file, lines) => fs.writeFileSync(file, ['@echo off', 'chcp 65001 >nul', ...lines, ''].join('\r\n'));

fs.mkdirSync(out, { recursive: true });
// 1) 실행본.
copy(release, path.join(out, 'Windows'), ['측정-결과']);
const stores = listing.stores.map(s => ({ ...s, label: String(s.label || s.key) }));
const main = stores.find(s => s.key === listing.default) || stores[0];
fs.writeFileSync(path.join(out, 'Windows', 'prototype.json'), JSON.stringify({ database: `../자료/${main.label}/archive.db` }, null, 2) + '\n');

// 2) 저장소들 · 바로 열기.
for (const store of stores) {
  const from = path.join(showcase, store.key), to = path.join(out, '자료', store.label);
  copy(path.join(from, 'archive.db'), path.join(to, 'archive.db'));
  // 앱의 DLC 폴더(넣은 DLC 파일 · 끈 목록 · 묘비). 얹은 견본의 원본(.htpack)이 있으면 함께 — 저장소에 이미 들어 있어 앱이 다시 들이지 않는다.
  fs.mkdirSync(path.join(to, 'DLC'), { recursive: true });
  if (fs.existsSync(path.join(from, 'DLC'))) copy(path.join(from, 'DLC'), path.join(to, 'DLC'));
  writeCmd(path.join(out, `${store.label}-열기.cmd`), [`start "" "%~dp0Windows\\${exeName}" --db="%~dp0자료\\${store.label}\\archive.db"`]);
}
copy(path.join(showcase, 'showcase.json'), path.join(out, '자료', '목록.json'));
// 포장 · 연기 검사 스크립트(prototype/scripts/release/*.ps1 — 글자는 ASCII만)가 읽는 목록: 한글 이름은 여기(UTF-8 JSON)에서 읽는다.
fs.writeFileSync(path.join(out, 'bundle.json'), JSON.stringify({
  kind: 'history-timeline-bundle', schema: 1, version, title: TITLE, exe: exeName, default: main.label,
  stores: stores.map(s => ({ key: s.key, label: s.label, db: `자료/${s.label}/archive.db`, default: s.key === main.key, cards: s.packs.length, bytes: s.bytes })),
}, null, 1) + '\n');

// 3) 도구: 엔진 도구 하나와 동아시아 기본팩 원본(build-showcase.mjs가 싼 base.htpack — 기본팩을 바탕으로 지은 저장소의 것).
//    예전의 Node.js · 지금 연표의 셈(js) · 배치 내보내기 · add-dlc.mjs · DLC-추가.cmd(앱을 닫은 채로 Node로 다시 짓기 — 달력 표 없는 저장소를 지어
//    그 뒤 앱의 넣고 빼기가 막혔다)는 싣지 않는다(한 벌 P4 과제 11 · 판정 R49).
const tools = path.join(out, '도구');
copy(tool, path.join(tools, 'prototype', path.basename(tool)));
const baseStore = stores.find(s => s.base && s.base.id === BASE_ID && s.base.file && fs.existsSync(path.join(showcase, s.base.file)));
if (baseStore) copy(path.join(showcase, baseStore.base.file), path.join(tools, 'prototype', 'results', 'compat', 'east-asia.htpack'));
else console.warn(`동아시아 기본팩 원본(base.htpack — ${BASE_ID})이 견본 목록에 없어 도구\\prototype\\results\\compat\\east-asia.htpack을 두지 않습니다.`);

// 4) 사용 안내.
const cards = (store) => store.packs.filter(p => !p.base).map(p => p.name).join(' · ');
const skipped = (listing.skipped || []).filter(s => s.reason && !/^DLC가 아님/.test(s.reason));
const withExtras = stores.filter(s => s.packs.length > 1);
/** 열기 목록의 한 줄 풀이. */
const describe = (s) => {
  const extras = s.packs.length - 1;
  if (s.key === 'showcase') return extras
    ? `동아시아 기본팩 위에 견본 DLC ${extras}벌을 얹은 저장소입니다. DLC 관리(\`D\`)에 견본마다 카드가 있어 켜고 끄며 하나씩 볼 수 있습니다.`
    : '동아시아 기본팩(동아시아사 자료) 저장소입니다.';
  if (s.key === 'east-asia') return '동아시아 기본팩만.';
  return `${s.base.name}(견본): 지어낸 나라와 사람으로 연표의 기능을 모두 보여 주는 가상 세계 하나입니다(기본팩 없이 그것만으로).`;
};
fs.writeFileSync(path.join(out, '사용-안내.md'), `# 역사 연표 — 독립형 연표 앱 ${version} (시험판)

컴퓨터(Windows 10/11 x64)용 보기 전용 연표 앱입니다. 인터넷에 아무것도 보내지 않습니다. 코드 서명이 없어 처음 열 때 Windows가 경고할 수 있습니다(\`추가 정보 → 실행\`).

## 열기

${stores.map(s => `- \`${s.label}-열기.cmd\` — ${s.key === main.key ? '**기본** · ' : ''}${describe(s)}`).join('\n')}
- \`Windows\\${exeName}\`를 바로 열어도 ${main.label}이(가) 열립니다.

## 움직이기

- 끌기 = 이동 · 휠 = 기간 확대/축소 · Ctrl + 휠 = 돋보기 · 오른쪽 클릭 = 메뉴(DLC 관리 · 필터 · 조감 · 범례 · 표 보기 …)
- 누르면 오른쪽에 상세 창 · 다른 곳을 누르면 닫힘 · \`/\` 검색 · \`F\` 필터 · \`V\` 조감 · \`D\` DLC 관리 · \`Z\` 집중 모드

## DLC 더하기 · 빼기

1. DLC 메이커에서 \`.htpack\`으로 저장합니다.
2. 앱의 DLC 관리(\`D\`)에서 **\`📂 파일에서 더하기…\`**를 누르고 그 파일을 고릅니다(여러 개도 됩니다). 앱이 저장소를 제자리에서 고쳐 쓰는 동안에도 앱은 그대로 쓸 수 있습니다.
3. 빼기: DLC 관리에서 카드를 고르고 **\`DLC 삭제\`**. 저장소의 바탕(첫 DLC)은 뺄 수 없습니다. 바탕이 아닌 자리의 동아시아 기본팩을 뺐다가 다시 넣으려면 \`도구\\prototype\\results\\compat\\east-asia.htpack\`을 더합니다.
4. 켜고 끄기: 끈 DLC는 저장소에서 빠져 날짜 칸 · 검색 · 필터 어디에도 남지 않습니다. 원본은 저장소에 남아 다시 켤 수 있습니다.
- 설치 파일로 새 판을 덮어 설치하면 \`자료\`의 저장소도 새 판의 것으로 바뀝니다. 더해 둔 DLC의 파일은 \`DLC\` 폴더에 남고, 새 판의 앱을 열면 그 DLC를 저장소에 다시 넣습니다(뺀 DLC · 끈 DLC는 넣지 않습니다).
- 포터블(zip)의 새 판은 옛 폴더 위에 덮어 풀지 말고 **새 폴더**에 풉니다(옛 저장소의 일지 파일이 새 저장소를 망칠 수 있습니다). 더해 둔 DLC는 옛 폴더의 \`자료\\<저장소>\\DLC\` 폴더를 통째로 새 폴더의 같은 자리에 옮기면 새 판의 앱이 열 때 다시 넣습니다.
${withExtras.length ? `\n## 얹은 견본 DLC\n${withExtras.map(s => `\n- ${s.label}: ${cards(s)}`).join('')}\n` : ''}${skipped.length ? `\n이번 판에서 뺀 견본(지금의 아카이브 짓기가 받지 못함): ${skipped.map(s => `\`${s.file}\` — ${s.reason}`).join(' · ')}\n` : ''}`);

const size = (dir) => fs.readdirSync(dir, { withFileTypes: true }).reduce((sum, e) => sum + (e.isDirectory() ? size(path.join(dir, e.name)) : fs.statSync(path.join(dir, e.name)).size), 0);
console.log(`꾸러미: ${out} · ${(size(out) / 1048576).toFixed(0)}MiB · 저장소 ${stores.map(s => s.label).join(' · ')} · 기본 ${main.label}`);

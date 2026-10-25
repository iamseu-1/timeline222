// 3단계 산출물을 저장소 뿌리의 배포/아카이브-3단계-<날짜>/에 모은다(무시 폴더 — 원격 전송 · 게시는 하지 않는다).
// 사용: node prototype/scripts/collect-release3.mjs <주 저장소 뿌리> <날짜 YYYY-MM-DD> <보고서.md>
//        [--moonwake data/moonwake3h] [--large data/v3b-1m] [--compare results/compare3/<이름>] [--formal results/formal3] [--short results/measure3]
// 모으는 것: Windows 실행본 · 월흔해/가상 100만 저장소 · 1배 비교 그림 · 측정 기록 · 보고서와 대조표 · 사용 안내 · 산출물 지문.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [mainRoot, date, reportFile] = process.argv.slice(2);
const flag = (name, fallback) => { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : fallback; };
const moonwake = flag('--moonwake', 'data/moonwake3h'), large = flag('--large', 'data/v3b-1m');
const compareDir = flag('--compare', ''), formalDir = flag('--formal', 'results/formal3'), shortDir = flag('--short', 'results/measure3');
if (!mainRoot || !date || !reportFile) { console.error('사용: collect-release3.mjs <주 저장소 뿌리> <날짜> <보고서.md> [--moonwake …] [--large …] [--compare …] [--formal …]'); process.exit(2); }
const target = path.join(path.resolve(mainRoot), '배포', `아카이브-3단계-${date}`);
if (fs.existsSync(target)) { console.error('이미 있는 산출물 폴더는 덮어쓰지 않습니다: ' + target); process.exit(1); }

// fs.cpSync는 이 PC의 Node 24에서 한글이 든 경로를 만나면 아무 말 없이 죽는다(종료 코드 127) — 파일마다 직접 복사한다.
const copy = (from, to) => {
  if (!fs.existsSync(from)) { console.error('없음(건너뜀): ' + from); return; }
  if (fs.statSync(from).isDirectory()) {
    fs.mkdirSync(to, { recursive: true });
    for (const name of fs.readdirSync(from)) copy(path.join(from, name), path.join(to, name));
  } else {
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
  }
};
const release = path.join(prototype, 'app/build/windows/x64/runner/Release');
if (!fs.existsSync(path.join(release, 'archive_prototype.exe'))) { console.error('실행본이 없습니다. scripts/dev.ps1 app-build 를 먼저 돌리세요.'); process.exit(1); }
copy(release, path.join(target, 'Windows'));
// 실행본 폴더에 남은 측정 기록은 산출물이 아니다.
fs.rmSync(path.join(target, 'Windows', '측정-결과'), { recursive: true, force: true });
fs.writeFileSync(path.join(target, 'Windows', 'prototype.json'), JSON.stringify({ database: '../자료/월흔해/archive.db' }, null, 2) + '\n');
copy(path.join(prototype, moonwake, 'archive.db'), path.join(target, '자료', '월흔해', 'archive.db'));
copy(path.join(prototype, large, 'archive.db'), path.join(target, '자료', '가상-100만', 'archive.db'));

// 측정: 정식 결과와 짧은 측정(기록과 1배 그림만).
for (const [dir, label] of [[formalDir, '정식'], [shortDir, '짧게']]) {
  const from = path.join(prototype, dir);
  if (!fs.existsSync(from)) continue;
  for (const name of fs.readdirSync(from)) {
    const run = path.join(from, name);
    if (!fs.statSync(run).isDirectory()) { if (name.endsWith('.json')) copy(run, path.join(target, '측정', label, name)); continue; }
    for (const file of ['측정.json', '시작-장면.json', '화면-1배.png']) {
      if (fs.existsSync(path.join(run, file))) copy(path.join(run, file), path.join(target, '측정', label, name, file));
    }
  }
}
if (compareDir) copy(path.join(prototype, compareDir), path.join(target, '비교-그림', '지금-연표와-새-앱'));
// 층마다의 조각 비교(둘째 작업자들이 뜬 것 — 비교 그림만).
for (const name of fs.readdirSync(path.join(prototype, 'results')).filter(n => /^render-.*2$/.test(n))) {
  const from = path.join(prototype, 'results', name);
  for (const file of fs.readdirSync(from).filter(f => f.startsWith('비교') && f.endsWith('.png'))) copy(path.join(from, file), path.join(target, '비교-그림', '층별', name.replace(/^render-/, ''), file));
}
copy(path.resolve(reportFile), path.join(target, path.basename(reportFile)));
copy(path.join(prototype, '..', 'docs', '대조-아카이브-3단계-기능.md'), path.join(target, '대조-아카이브-3단계-기능.md'));

const cmd = db => `@echo off\r\nchcp 65001 >nul\r\n"%~dp0Windows\\archive_prototype.exe" --db="%~dp0자료\\${db}\\archive.db"\r\n`;
fs.writeFileSync(path.join(target, '월흔해-열기.cmd'), cmd('월흔해'));
fs.writeFileSync(path.join(target, '가상-100만-열기.cmd'), cmd('가상-100만'));
fs.writeFileSync(path.join(target, '사용-안내.md'), `# 별여울 아카이브 3단계 시제품 — 사용 안내 (${date})

컴퓨터(Windows) 전용 · 보기 전용 시제품입니다. 가상 자료만 들어 있고, 인터넷에 아무것도 보내지 않습니다.
지금 연표(웹)의 모습 · 기능 · 움직임을 새 엔진으로 옮긴 것입니다 — 무엇이 같고 무엇이 남았는지는 \`${path.basename(reportFile)}\`와 \`대조-아카이브-3단계-기능.md\`에 있습니다.

## 열기

- \`월흔해-열기.cmd\` — 지금 연표의 견본(월흔해). 지금 연표와 나란히 놓고 보기에 좋습니다.
- \`가상-100만-열기.cmd\` — 가상 사건 100만 건(자료집 8 · 줄 252). 처음 열 때 1~2초 걸립니다.

## 움직이기

- 끌기 = 옆 · 위아래로 이동(놓으면 조금 미끄러짐) · 휠 = 기간 확대/축소 · Ctrl + 휠 = 돋보기(50~300%)
- 키: \`+\` \`-\` 확대/축소 · \`←\` \`→\` 이동 · \`0\` 전체 보기 · \`/\` 검색 · \`Esc\` 닫기(검색 결과 → 시트 → 창 → 집중 모드 차례)
- 단축키: \`F\` 필터 · \`Y\` 같은 해 보기 · \`R\` 기간 재기 · \`L\` 범례 · \`T\` 표 보기 · \`P\` 이미지로 저장 · \`V\` 조감 · \`A\` 모든 트랙 접기/펴기 · \`D\` 자료집 · \`Z\` 집중 모드

## 누르기

- 사건(점 · 이름 · 막대 · 구슬) · 띠와 책갈피 탭 · 띠 안의 칸(지도자 · 내각 · 시기 · 지위 · 왕조 · 기관) · 인물 막대 · 속국 이름표 · 건국/멸망 네모 · 왼쪽의 줄 이름 → 오른쪽에 상세 창
- 개수 알약에 손을 올리면 그 묶음의 사건 카드(넓은 묶음은 누르면 그 구간 확대) · 왼쪽 칸의 트랙 이름 → 트랙 접기 · 민족 칸 → 민족 접기 · 민족 딱지 → 그 민족의 문서 · 날짜 칸의 \`연호\` · \`도읍\` → 나라별 줄 펼치기 · 날짜 칸의 달력 이름 → 보조 달력 고르기
- 띠의 \`▸ n\`(소속 펼치기) · 대범위 모아 보기 단추 → 줄이 옮겨 가며 펼쳐집니다(필터 시트의 대범위 칩 · 상세 창의 스위치 · 메뉴에서도 같은 값).
- 빈 곳을 누르면 상세 창이 닫힙니다(같은 해 보기가 열려 있으면 기준선이 그 자리로).
- 상세 창의 \`📄 문서\` · \`W\` → 문서(위키) 창. 칸 · 시기 · 지위 · 왕조 · 인물 창의 \`같은 시기를 타국에도\` → 같은 때 다른 나라의 사건 목록.
- 아래 검색 칸에 이름 · 연도(\`842\` · \`기원전 300\`) · 간지(\`갑오\`)를 치면 결과가 뜨고, 고르면 그리로 날아갑니다.
- 연표 위 오른쪽 클릭 · 알약 창의 \`⋯\` = 메뉴. \`☰ 필터\` 시트에서 트랙 · 분류 · 종류 · 중요도를 거르고 밀도 · 조감을 고릅니다.

## 아직 안 되는 것

- SVG 저장 · 도읍 노선도 카드 · 관점(나라마다 제 이름) · 움직임 계측 창 · 어두운 테마는 옮기지 않았습니다.
- 필터 시트의 날짜 칸 표시 체크 넷(간지 · 연호 · 도읍 · 시대 구분)은 아직 날짜 칸에 닿지 않습니다.
- 가상 100만 건에서 돋보기(Ctrl + 휠)로 50%까지 물러나면 장면을 놓칩니다(나머지 다섯 구간은 합격선 안 — 검증 보고서 5절 · 9절).

## 재 보기

- \`⋯\` 메뉴의 \`측정\` = 지금 보는 장면에서 여섯 구간을 10초씩 재고 결과를 보여 줍니다(약 1분 반). 재는 동안 창을 가리거나 줄이지 말고 기다려 주세요.

## 들어 있는 것

- \`Windows/\` 실행본 · \`자료/\` 저장소 둘 · \`비교-그림/\` 지금 연표와의 1배 비교(세 장면)와 층별 조각 비교 · \`측정/\` 구간 측정 기록
- \`${path.basename(reportFile)}\` 검증 보고서 · \`대조-아카이브-3단계-기능.md\` 기능 · 움직임 대조표 · \`산출물-지문.json\` 파일마다의 크기와 SHA-256
`);

// 산출물 지문
const prints = [];
const walk = dir => { for (const name of fs.readdirSync(dir).sort()) { const file = path.join(dir, name); if (fs.statSync(file).isDirectory()) walk(file); else prints.push(file); } };
walk(target);
// 큰 저장소(수백 MB)도 있으니 조각조각 읽어 지문을 뜬다.
const sha256 = file => {
  const hash = createHash('sha256'), fd = fs.openSync(file, 'r'), chunk = Buffer.allocUnsafe(1 << 22);
  for (let n; (n = fs.readSync(fd, chunk, 0, chunk.length, null)) > 0;) hash.update(chunk.subarray(0, n));
  fs.closeSync(fd);
  return hash.digest('hex');
};
const list = prints.map(file => ({ path: path.relative(target, file).replaceAll('\\', '/'), bytes: fs.statSync(file).size, sha256: sha256(file) }));
fs.writeFileSync(path.join(target, '산출물-지문.json'), JSON.stringify({ date, files: list.length, bytes: list.reduce((n, f) => n + f.bytes, 0), list }, null, 2) + '\n');
console.log(`모음: ${target} · 파일 ${list.length}개 · ${(list.reduce((n, f) => n + f.bytes, 0) / 1048576).toFixed(0)}MiB`);

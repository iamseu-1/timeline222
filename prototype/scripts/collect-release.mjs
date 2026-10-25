// 2단계 산출물을 저장소 뿌리의 배포/아카이브-2단계-<날짜>/에 모은다(무시 폴더 — 원격 전송 · 게시는 하지 않는다).
// 사용: node prototype/scripts/collect-release.mjs <주 저장소 뿌리> <날짜 YYYY-MM-DD> <보고서.md>
// 모으는 것: Windows 실행본 · 월흔해/100만 저장소(1,000만은 만드는 명령만) · 정식 측정과 관문 기록 · 비교 그림 · 보고서 · 사용 안내 · 산출물 지문.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [mainRoot, date, reportFile] = process.argv.slice(2);
if (!mainRoot || !date || !reportFile) { console.error('사용: collect-release.mjs <주 저장소 뿌리> <날짜> <보고서.md>'); process.exit(2); }
const target = path.join(path.resolve(mainRoot), '배포', `아카이브-2단계-${date}`);
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
fs.writeFileSync(path.join(target, 'Windows', 'prototype.json'), JSON.stringify({ database: '../자료/v2-1m/archive.db' }, null, 2) + '\n');
for (const name of ['moonwake2', 'v2-1m']) copy(path.join(prototype, 'data', name), path.join(target, '자료', name));

// 측정: 정식 결과와 관문 기록(그림은 빼고 기록만 — 1배 그림은 비교 그림 폴더에).
const results = path.join(prototype, 'results');
for (const name of fs.existsSync(path.join(results, 'formal')) ? fs.readdirSync(path.join(results, 'formal')) : []) {
  const from = path.join(results, 'formal', name);
  if (fs.statSync(from).isDirectory()) {
    for (const file of ['측정.json', '시작-장면.json', '화면-1배.png']) {
      if (fs.existsSync(path.join(from, file))) copy(path.join(from, file), path.join(target, '측정', '정식', name, file));
    }
  } else if (name.endsWith('.json')) {
    copy(from, path.join(target, '측정', '정식', name)); // 다시 열기 요약 등
  }
}
for (const file of ['라-글자.json', '마-규모.json']) copy(path.join(results, 'gates', file), path.join(target, '측정', '관문', file));
for (const file of ['bench-100k-b.json', 'bench-1m-b.json', 'bench-10m-b.json']) copy(path.join(results, 'gates', 'ma', file), path.join(target, '측정', '자료-처리부', file.replace('-b.json', '.json')));
copy(path.join(results, 'decode-bench.json'), path.join(target, '측정', '자료-처리부', '해독-비교.json'));
copy(path.join(results, 'compare'), path.join(target, '비교-그림', '지금-연표와-새-그리기'));
copy(path.join(results, 'gates', 'ra', '글자-방식-비교-1배.png'), path.join(target, '비교-그림', '글자-방식-비교-1배.png'));
copy(path.resolve(reportFile), path.join(target, path.basename(reportFile)));

const cmd = db => `@echo off\r\nchcp 65001 >nul\r\n"%~dp0Windows\\archive_prototype.exe" --db="%~dp0자료\\${db}\\archive.db"\r\n`;
fs.writeFileSync(path.join(target, '100만-열기.cmd'), cmd('v2-1m'));
fs.writeFileSync(path.join(target, '월흔해-열기.cmd'), cmd('moonwake2'));
fs.writeFileSync(path.join(target, '사용-안내.md'), `# 별여울 아카이브 2단계 시제품 — 사용 안내 (${date})

컴퓨터(Windows) 전용 · 보기 전용 시제품입니다. 가상 자료만 들어 있고, 인터넷에 아무것도 보내지 않습니다.

## 열기

- \`100만-열기.cmd\` — 가상 사건 100만 건(자료집 8 · 줄 252). 처음 열 때 1~2초 걸립니다.
- \`월흔해-열기.cmd\` — 지금 연표의 견본(월흔해)을 지금 연표와 같은 줄 배치로 옮긴 것.

## 움직이기

- 끌기 = 옆 · 위아래로 이동(놓으면 조금 미끄러집니다) · 휠 = 기간 확대/축소 · Ctrl + 휠(또는 트랙패드 집기) = 돋보기(50~300%, 100% 근처에서 붙음)
- 키: \`+\` \`-\` 확대/축소 · \`←\` \`→\` 이동 · \`Ctrl\` + \`+\` \`-\` \`0\` 돋보기 · \`Esc\` 멈춤
- 점 · 이름 · 막대를 누르면 오른쪽에 사건이, \`+개수\` 알약을 누르면 그 묶음의 목록이 열립니다. 맨 위 칸은 사건과 원문 검색.
- 오른쪽 아래 \`자료집\` 스위치로 자료집을 켜고 끕니다(줄이 바로 빠지고 아래 줄이 올라옵니다).

## 재 보기

- 맨 위 \`측정\` 단추 = 지금 보는 장면에서 여섯 구간(끌기 · 확대 · 돋보기 · 밀집 · 세로 · 자료집)을 10초씩 재고 결과를 보여 줍니다(약 1분 반).
  재는 동안 창을 가리거나 줄이지 말고 기다려 주세요. 기록은 \`Windows/측정-결과/<시각>/\`에 남습니다.
- 다른 컴퓨터(예: 갤럭시북3)에서도 이 폴더를 옮겨 같은 단추로 잴 수 있습니다 — 그 기기의 주사율로 따로 판정됩니다.
- 정식 측정(30초 × 3회 + 처음 1회)과 1,000만 건 자료 만들기는 저장소의 \`prototype/README.md\` '2단계' 절에 있습니다.
  1,000만 건(5.3GB)은 넣지 않았습니다: \`archive-tool generate2 data/v2-10m/archive.db 10000000 data/v2-10m/originals\` (이 PC에서 23분).

## 들어 있는 것

- \`Windows/\` 실행본 · \`자료/\` 저장소 둘 · \`측정/\` 정식 측정과 관문 기록 · \`비교-그림/\` 지금 연표와의 1배 비교 · 글자 방식 비교
- \`${path.basename(reportFile)}\` 검증 보고서 · \`산출물-지문.json\` 파일마다의 크기와 SHA-256
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

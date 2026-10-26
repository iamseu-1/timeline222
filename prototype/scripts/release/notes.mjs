// 릴리즈 글(GitHub Release의 본문) 짓기 — release 워크플로의 마지막 작업이 모은 파일을 보고, 든 것만 적는다.
// 사용: node prototype/scripts/release/notes.mjs --dir=<게시할 파일 폴더> --version=<판> --out=<글.md> [--sha=<커밋>] [--repo=<owner/name>]
//         [--scope=full|light] [--released=<게시된 태그,…>] [--showcase=<build-showcase의 showcase.json>] [--signature=<apksigner --print-certs 출력>]
// 파일 이름 규칙은 release.yml과 같다(ASCII): HistoryTimeline-<판>-windows-x64-setup.exe · …-portable.zip · HistoryTimeline-<판>-arm64.apk ·
// HistoryTimeline-Web-<판>-windows-x64(-setup).exe · HistoryTimelineMaker-<판>-windows-x64(-setup).exe · HistoryTimeline(Maker)-<판>-web.zip.
//   --scope      게시 범위(release.yml 머리글). light(기본) = APK · 포터블 zip · DLC 메이커 앱 셋 · SHA256SUMS만 올리는 작은 판 — 글도 짧게(변경 · 파일 · 알릴 것).
//                full = 모든 파일 — 든 저장소(동아시아 · 등불 연대기) · 설치 · 알릴 것을 모두 적는다. 어느 쪽이든 표에는 폴더에 실제로 있는 파일만 적는다.
//   --released   GitHub에 게시된 릴리즈의 태그(쉼표). '이번 판의 변경'은 이 가운데 이 판보다 낮은 가장 높은 판의 태그부터 HEAD까지의
//                커밋 제목(병합 · 문서만 고친 커밋은 뺌)을 몇 줄만 적는다. 없으면 git 태그(v*) 가운데서 고른다. git 기록이 없으면 그 절을 뺀다.
//   --apk-seed   안드로이드 APK에 넣은 저장소(release.yml의 env ANDROID_SEED — build-showcase.mjs의 저장소 이름). 기본 showcase(동아시아) ·
//                lantern이면 등불 연대기만 든 판타지 판으로 적는다.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
const option = (name, fallback = '') => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const dir = option('dir'), version = option('version'), out = option('out');
if (!dir || !version || !out) { console.error('사용: notes.mjs --dir=<폴더> --version=<판> --out=<글.md> [--sha=…] [--repo=…] [--showcase=…] [--signature=…]'); process.exit(2); }
const files = new Set(fs.readdirSync(dir));
const sha = option('sha'), repo = option('repo');
const v = version;
const full = option('scope', 'light') === 'full';
const apkSeed = option('apk-seed', 'showcase');
const fantasyApk = apkSeed === 'lantern';

let showcase = null;
try { if (full && option('showcase')) showcase = JSON.parse(fs.readFileSync(option('showcase'), 'utf8')); } catch (e) { console.warn(`견본 목록을 읽지 못했습니다: ${e.message}`); }
const main = showcase && (showcase.stores || []).find(s => s.key === 'showcase');
const others = showcase ? (showcase.stores || []).filter(s => s.key !== 'showcase') : [];
// 기본 저장소의 이름 — 작은 판은 목록(--showcase)을 받지 않으므로 build-showcase.mjs의 LABELS.showcase와 같은 이름을 적어 둔다.
const mainLabel = main ? main.label : '동아시아';
const shortcuts = [`\`역사 연표 독립형\`(${mainLabel})`, ...others.map(o => `\`역사 연표 독립형 - ${o.label}\``)].join('과 ');
const otherCmds = others.map(o => `\`${o.label}-열기.cmd\``).join(' · ');
// 포터블 새 판은 새 폴더에(판정 R58 — 앱이 저장소를 제자리에서 고쳐 쓰다 멈추면 남는 옛 일지(archive.db-journal)가 덮어 푼 새 저장소에 되감겨 망가뜨린다).
const PORTABLE_NEW_FOLDER = '- **포터블 새 판은 새 폴더에** 풉니다(옛 폴더 위에 덮어 풀지 않습니다). 더해 둔 DLC는 옛 폴더의 `자료\\<저장소>\\DLC` 폴더를 통째로 새 폴더의 같은 자리에 옮기면 새 판의 앱이 열 때 다시 넣습니다.';

const rows = [
  [`HistoryTimeline-${v}-windows-x64-setup.exe`, `**독립형 연표 앱** 설치 파일(Windows 10/11 x64) — 관리자 권한 없이 사용자 폴더(\`%LOCALAPPDATA%\\Programs\\HistoryTimeline-Standalone\`)에 설치합니다. 시작 메뉴에 ${shortcuts}이(가) 생깁니다.`],
  [`HistoryTimeline-${v}-windows-x64-portable.zip`, (full ? '같은 앱, 설치 없이' : '**독립형 연표 앱** Windows(10/11 x64) 포터블, 설치 없이') + ` — 압축을 **통째로** 푼 뒤 \`${mainLabel}-열기.cmd\`(또는 \`Windows\\archive_prototype.exe\`)를 엽니다${otherCmds ? `(견본은 ${otherCmds})` : ''}. \`사용-안내.md\`에 쓰는 법이 있습니다.`],
  [`HistoryTimeline-${v}-arm64.apk`, '**독립형 연표 앱** 안드로이드(arm64 휴대폰) — ' + (fantasyApk ? '**판타지 판**: 가상 세계 견본 「등불 연대기」 저장소만 들어 있습니다(동아시아 기본팩 없음).' : '동아시아 저장소가 들어 있습니다.') + ' 가로 화면 · 한 손가락 끌기 = 이동 · 두 손가락 = 확대 · 길게 누르기 = 메뉴.'],
  [`HistoryTimeline-Web-${v}-windows-x64-setup.exe`, '지금 연표(웹 연표를 감싼 Windows 프로그램 · Tauri) 설치 파일.'],
  [`HistoryTimeline-Web-${v}-windows-x64.exe`, '지금 연표 — 설치 없이 바로 여는 단일 실행 파일.'],
  [`HistoryTimelineMaker-${v}-windows-x64-setup.exe`, 'DLC 메이커(Windows 프로그램 · Tauri) 설치 파일.'],
  [`HistoryTimelineMaker-${v}-windows-x64.exe`, 'DLC 메이커 — 설치 없이 바로 여는 단일 실행 파일.'],
  [`HistoryTimelineMaker-${v}-arm64.apk`, '**DLC 메이커** 안드로이드(arm64 휴대폰 · Tauri) — 작업본은 휴대폰 안에 남고, 팩 파일로 내보내기는 기기의 저장 창으로 고른 곳에 씁니다. 디버그 키로 서명해 판마다 키가 달라, 새 판으로 바꿀 때는 지우고 다시 설치합니다 — **그 전에 작업본을 `.htpack`으로 내보내 두세요.**'],
  [`HistoryTimeline-${v}-web.zip`, '지금 연표의 웹 폴더(`dist/web` — PWA로 https 주소에 올리거나 `index.html`을 바로 엽니다).'],
  [`HistoryTimelineMaker-${v}-web.zip`, 'DLC 메이커의 웹 폴더(`dist/maker` — `dlc-maker.html`).'],
  [`HistoryTimeline-${v}-sample-lantern.htpack`, '**견본 DLC** 「등불 연대기 — 아홉 불씨의 대륙」(`.htpack`) — 지어낸 나라와 사람으로 연표의 기능을 모두 보여 주는 가상 세계 하나입니다. 독립형 앱의 Windows판에는 저장소로 이미 들어 있습니다. 지금 연표 · 위키 아카이브의 연표 모듈에서는 DLC 관리로 더하고, DLC 메이커에서 열면 어떻게 적었는지 봅니다.'],
  ['SHA256SUMS.txt', '위 파일들의 SHA-256(`sha256sum -c SHA256SUMS.txt`).'],
];
// 작은 판이 올리는 것(release.yml의 must와 같음 + SHA256SUMS). 빠졌다고 적는 것은 이 범위에서 올렸어야 할 파일뿐이다.
const LIGHT = new Set([`HistoryTimeline-${v}-windows-x64-portable.zip`, `HistoryTimeline-${v}-arm64.apk`, 'SHA256SUMS.txt']);
const present = rows.filter(([name]) => files.has(name));
const missing = rows.filter(([name]) => !files.has(name) && name !== 'SHA256SUMS.txt' && (full || LIGHT.has(name)));

// 이번 판의 변경: 지난 게시 판의 태그 → HEAD의 커밋 제목(새것부터). 병합 커밋과 문서(*.md · docs/)만 고친 커밋은 뺀다.
const SHOW = 5;
const git = (...argv) => execFileSync('git', argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
const parts = (tag) => tag.slice(1).split('.').map(Number);
const lower = (a, b) => { for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] < b[i]; return false; };
let changes = null;
try {
  const released = new Set(option('released').split(',').map(s => s.trim()).filter(Boolean));
  const mine = parts(`v${v}`);
  const tags = git('tag', '--list', 'v*', '--merged', 'HEAD').split('\n').map(s => s.trim())
    .filter(t => /^v\d+\.\d+\.\d+$/.test(t) && lower(parts(t), mine) && (!released.size || released.has(t)));
  const since = tags.reduce((best, t) => (!best || lower(parts(best), parts(t)) ? t : best), null);
  if (since) {
    const subjects = git('log', '--no-merges', '--format=%s', `${since}..HEAD`, '--', '.', ':(exclude,glob)**/*.md', ':(exclude)docs')
      .split('\n').map(s => s.trim()).filter(Boolean);
    changes = { since, subjects };
  } else {
    console.warn("지난 게시 판의 태그를 찾지 못해 '이번 판의 변경'을 적지 않습니다.");
  }
} catch (e) {
  console.warn(`git 기록을 읽지 못해 '이번 판의 변경'을 적지 않습니다: ${e.message.split('\n')[0]}`);
}

let signature = '';
try { if (option('signature')) signature = fs.readFileSync(option('signature'), 'utf8'); } catch { /* 없으면 적지 않음 */ }
const debugKey = /CN=Android Debug/i.test(signature);

const lines = [];
lines.push(`역사 연표 ${v}의 **시험판**입니다${sha ? ` — 커밋 \`${sha.slice(0, 12)}\`` : ''}에서 GitHub Actions가 지었습니다.`);
lines.push('');
if (full) lines.push('Rust 엔진과 Flutter로 지은 **독립형 연표 앱**(Windows · 안드로이드)과 DLC 메이커를 같은 커밋에서 지었습니다.');
else lines.push('작은 판이라 **독립형 연표 앱**의 안드로이드 APK · Windows 포터블 zip과 **DLC 메이커 앱**(Windows · 안드로이드)만 올렸습니다. 설치 파일 · 견본 DLC는 큰 판(x.0.0)에서 올립니다.');
// 0.0.4(작은 판 — 한 벌 P3 · P4 · 끝 문서 과제) · 0.1.0(작은 판 — 리메이크 3 · 4 · 6단계): 커밋 제목은 개발 말(검토 판정 번호 · 작업 갈래 이름)이
// 많아 싣지 않고, 아래 '이번 판에서 달라진 것'에 사용자 말로 적는다(모든 변경은 견줌 고리 하나로).
const CURATED = new Set(['0.0.4', '0.1.0']);
const curatedSince = CURATED.has(v) && changes ? changes.since : null;
if (CURATED.has(v)) changes = null;
if (changes) {
  lines.push('');
  lines.push(`## 이번 판의 변경(${changes.since} 뒤)`);
  lines.push('');
  if (!changes.subjects.length) lines.push('- 앱을 고친 커밋이 없습니다(문서만 바뀜).');
  for (const subject of changes.subjects.slice(0, SHOW)) lines.push(`- ${subject}`);
  const more = changes.subjects.length - SHOW;
  if (more > 0) lines.push(`- 그 밖에 ${more}건${repo && sha ? ` — [모든 변경](https://github.com/${repo}/compare/${changes.since}...${sha})` : ''}`);
}
// 0.0.4의 '이번 판에서 달라진 것'. 0.0.4는 프로그램만 지어 두고 게시하지 않아(태그 없음 — 인수인계 5-27) 0.1.0 글이 마지막 줄만 고쳐 다시 싣는다.
const NOTES_004 = [
  '- **DLC 넣기 · 빼기 · 끄기 · 켜기를 앱 안에서**: 독립형 연표 앱이 DLC 파일(메이커가 저장한 `.htpack` — 예전 형식도 그대로)을 직접 읽어 넣고 뺍니다. 다른 프로그램(Node.js)이 필요 없고, 저장소를 통째로 다시 짓지 않고 바뀐 나라 줄만 고쳐 씁니다. 끈 DLC는 연표에서 아예 빠지고(원본은 앱 안에 남아 다시 켜면 돌아옵니다), 지우면 원본까지 지웁니다. 넣다가 멈추거나 실패해도 연표는 넣기 전 그대로입니다.',
  '- **큰 DLC 넣기가 빨라졌습니다**: 바뀐 나라 줄만 다시 셈하고, 사건이 많을수록 몹시 느려지던 이름 찾기 표 고쳐 쓰기를 고쳤습니다. 다만 사건이 수만 개를 넘는 아주 큰 DLC는 아직 수십 초 걸릴 수 있습니다.',
  '- **휴대폰에서 DLC 넣기(시험 중)**: 안드로이드 앱에서도 DLC 관리 → `📂 파일에서 더하기…`로 휴대폰에 둔 `.htpack`을 골라 넣고(여럿을 한 번에), 끄고 켜고 지웁니다. 새 판 앱으로 바꿔도 넣어 둔 DLC를 새 판으로 옮기게 했습니다. 아직 실제 휴대폰에서 충분히 써 보지 않은 시험 기능이니, 문제가 있으면 알려 주세요. 판타지 판의 바탕인 등불 연대기는 끄면 화면에서만 가려집니다.',
  '- **넣지 못할 때 쉬운 말로**: 까닭과 할 일을 함께 알립니다 — 음력처럼 다른 달력의 날짜가 앱이 아는 범위(기원전 3500년 ~ 2500년) 밖 · 같은 항목이 두 나라 줄에 들어 있음 · 이미 든 것(꺼 둔 것 포함)보다 낮은 판 · 파일이 망가짐이면 메이커에서 고쳐 다시 저장한 파일을 고르라고 하고, 예전 메이커의 배치 파일(`.htlayout`)을 고르면 `.htpack`으로 저장해 넣으라고 알립니다.',
  '- **DLC 메이커**: 연표 앱이 `.htpack`을 직접 읽으므로 `아카이브용으로 내보내기`를 없앴습니다 — `파일 → 팩 파일로 내보내기 (.htpack)`로 저장한 파일을 넣으면 됩니다.',
  '- **Windows 설치본의 판 올림**: 설치 파일(큰 판에서 올림)로 새 판을 덮어 설치하면 예전 판이 남긴 DLC 다시 짓기 도구(Node.js · `DLC-추가.cmd` 등)를 지웁니다 — DLC는 앱의 DLC 관리에서 넣습니다.',
  '- **DLC 메이커가 형식 4로 저장합니다**(리메이크 5단계): 나라 · 도시 · 교단 · 사람 등을 「객체」 하나로 적고 그릇(폴더 · 상자 · 선반)으로 묶습니다. 직위 줄을 셋 이상 · 다른 객체의 직위 줄을 빌려 보기 · 남의 실권 · 사람 객체(칭호 묶음) · 문화권마다의 시대 구분과 해 세기 줄을 적고, 통째 붙여넣기와 검사 창도 새 칸을 압니다. 미리보기(서고)는 사람 띠 · 빌린 층 · 실권 밑줄 · 문화권 머리 단 밑 줄 · 상자와 선반을 그립니다.',
  '- **예전 앱과 주고받기**: 형식 1 · 2 · 3 파일은 그대로 열리고, `파일 → 옛 형식(3)으로 내보내기`는 빠지는 칸을 먼저 알려 줍니다. 연표 앱은 형식 4 파일을 넣을 수 있지만 사람 띠 · 빌린 직위 줄 · 문화권 줄은 아직 그리지 않습니다(다음 판).',
];
if (v === '0.1.0') {
  // 리메이크 3 · 4 · 6단계를 묶은 판(감독 2026-10-25 '판 0.1.0 = 3 · 4 · 6단계' · 10-26 '릴리즈 진행'). 앞서 게시한 판은 0.0.3이라
  // 0.0.4의 변경(NOTES_004)도 아래 둘째 절로 함께 싣는다. 근거: 인수인계 5-8 ~ 5-45 · git log v0.0.3..HEAD --first-parent.
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **판 0.1.0**: 리메이크 3 · 4 · 6단계(저장소 새 모양 · 연표 앱 새 그림 · 세계사 자료 칸)를 묶은 판입니다. 0.0.4는 프로그램만 지어 두고 게시하지 않아, 그 판의 변경도 아래 「0.0.4에서 달라진 것」으로 이 판에 함께 듭니다.');
  lines.push('- **형식 4를 연표 앱이 그립니다**: 문화권 머리 단 밑의 시대 구분 줄 · 주기 줄(이름 돌림 · 연호 눈금), 왕관이 여럿인 사람의 사람 띠(왕관마다 내려가는 실과 띠 윗변의 뿔 매듭 — 누르면 칭호 묶음을 보이는 사람 창), 빌려 본 지도자 · 내각 칸과 머리 줄의 출처 글, 셋째부터의 직위 줄, 실권 밑줄을 그립니다. 육십갑자는 머리 단의 주기 줄에만 나오고, 그 문화권을 접으면 날짜 칸의 간지 줄로 돌아옵니다.');
  lines.push('- **칸 그림**: 공동 통치 · 주장으로 겹친 지도자 칸은 두 단으로 나눠 그리고, 정통성(섭정 · 명목 · 주장 · 대립)을 칸 · 띠 머리 · 소속 구간의 무늬로 보입니다. 띠마다 제 칸 층 수만큼의 몸통 높이를 쓰고, 왕조 · 지위는 꼬리표 밑의 흰 사슬 단으로 그립니다. 꼬리표 끝 꼴이 객체 종류(나라 · 도시 · 교단 · 연맹 …)마다 다르고, 대립은 파선 테입니다.');
  lines.push('- **그릇 · 폴더**: 그릇(대범위)에 넷째 상태 **선반**이 생겼습니다 — 중요한 구성원만 제 줄에 두고 나머지는 폴더 발의 작은 꼬리표 줄과 `+n`으로 모으며, 누르면 펼칩니다. 그릇 차림표(오른쪽 클릭 · 휴대폰은 길게 누르기)는 펼침 · 선반 · 접음 · 풂 넷이고, 고른 상태는 다시 켜도 남습니다. 그릇 안의 그릇은 뚜껑 있는 상자로, 접으면 모따기 한 줄로 그립니다. 소속 펼치기도 폴더가 되어 상국 띠가 첫 줄에 서고 매다는 실과 가로대가 붙습니다. 동맹과 구성원 없는 나라는 납작한 뚜껑, 동군연합은 폴더 먹으로 그립니다.');
  lines.push('- **구분선 · 연도 세로줄**: 칸 층 사이에 흐린 가로 금이 생기고, 그림판의 가로 · 세로 구분선이 틈 없이 맞닿습니다. 연도 세로줄은 맨 아래 바탕에만 그어 띠 · 카드 · 폴더 위로 비치지 않고, 할거 같은 그릇 폴더 안에도 없습니다 — 그래서 띠의 옅은 칠을 반투명 대신 바탕과 섞은 불투명 색으로 칠합니다(옅은 띠 끝 밑의 바탕 문화 점무늬도 가려집니다). 접힌 민족 줄은 종이로 덮습니다.');
  lines.push('- **이어 주는 선**: 승계선이 앞 나라의 끝에서 나옵니다. 다른 띠 뒤로 지날 때는 그 띠의 테에 굴 문을 두어 선이 띠 밑으로 들어가고 나오는 자리를 보이고, 같은 줄의 승계는 사이 띠를 ⊓ 꼴로 넘습니다. 트랙을 건너는 부분 승계는 양쪽 끝의 짝 꼬리표(`→ ● 상대 이름`)로 그리고, 누르면 상대 띠로 날아갑니다.');
  lines.push('- **창 · 시트**: 필터 · 검색 결과 · 차림표 · 범례 · DLC 관리 · 단체 계보 · 문서 창을 서고 꼴(폴더 · 실에 꿴 꼬리표 목록 · 흰 종이)로 다시 그렸습니다. 승계표는 좁은 창(위에서 아래로 이름띠 · 실 · 열쇠표)과, 화면 아래에서 여는 넓은 창(가로로 이어짐 — 새로 생김) 둘입니다.');
  lines.push('- **저장소 새 모양(판 4)**: 앱에 든 저장소는 객체 종류 · 정통성 · 중요도 · 문화권 줄을 담는 새 모양입니다. 예전 판 앱에서 DLC를 넣어 지은 저장소도 그대로 열리고, 다음에 DLC를 넣거나 빼면 모든 트랙을 다시 셈해 새 모양으로 바뀝니다 — 그렇게 바뀐 저장소는 0.0.4까지의 앱이 열지 못합니다. 다른 DLC의 트랙에 얹는 형식 4 DLC를 넣으면 「배치와 저장소가 어긋나 고쳐 쓰지 못했습니다」로 거절되던 것(등불 연대기 저장소)을 고쳤습니다.');
  lines.push('- **세계사 자료 칸**: 날짜에 히브리력 · 에티오피아력 · 콥트력 · 사카력(인도 국정력) · 불기(타이)를 쓸 수 있고, 날짜 칸의 다른 달력 고르기에도 나옵니다. 그 전에 지은 저장소(달력 표 다섯)에 앞의 넷으로 날짜를 적은 DLC를 넣으면, 거절하지 않고 그 날짜를 쓴 항목만 빼고 넣은 뒤 알립니다. 기간을 정해 그릇을 옮겨 앉는 객체는 그릇 밖 기간을 따로 토막으로 그리고, 실권 정권이 명목상 섬긴 상대 띠에는 실권 밑줄을 긋습니다.');
  lines.push('- **DLC 메이커**: 통째 붙여넣기가 새 칸 채우기 프롬프트의 답(`#HT칸 2` — 객체 · 그릇 · 시대 · 섬김 · 구성원 · 주기 · 사람 · 종교 층)을 읽습니다(예전 `#HT칸 1` 답도 그대로). 지도자 줄의 이름 번호 · 종교 · 나라 승계 방식(혼인 · 상속 · 정복 · 선양 …) · 지도자 표기 낱말을 적는 칸이 생겼습니다 — 종교 · 승계 방식 · 표기 낱말은 파일에 남지만 연표에는 아직 그리지 않습니다. 검사 창이 끝이 비어 한 해짜리 점 띠로 그려질 객체를 알리고, 형식 4 파일을 열어 저장할 때마다 그릇 듦이 소속 줄로 한 벌씩 늘던 것을 고쳤습니다.');
  lines.push('- **메이커에서 알아 둘 것**: 미리보기(서고)는 지도자 두 단 · 띠마다 제 몸통 높이 · 직위 줄 더 층을 연표 앱과 같은 셈으로 그리지만, 흰 사슬 · 소속 폴더 · 정통성 무늬 · 짝 꼬리표처럼 이번 판 연표 앱의 새 그림은 아직 없습니다 — 모양은 `연표로 ↗`로 연표 앱에서 보세요.');
  // 메이커 점검 2026-10-25 (마) n2 · n3 · n14 · n15 · n29 — main 메이커(이 판)에는 칸의 정통성 · 그릇 듦의 기간을 적을 칸이 없다(js/maker-paste.js도 알리고 뺌).
  lines.push('- **이 판의 메이커로 아직 못 만드는 것**: 지도자 칸의 정통성(공동 · 섭정 · 명목 · 주장 · 대립)과 그릇에 든 기간을 적는 칸이 없습니다 — 통째 붙여넣기도 그 칸은 알리고 뺍니다. 그래서 위의 지도자 두 단 · 칸의 정통성 무늬 · 그릇을 옮겨 앉는 토막은 이 판의 메이커로 만들 수 없습니다(띠 머리의 무늬는 객체 폼의 `정통성`으로 적습니다). 그 칸을 적는 고친 메이커(10-25에 따로 지음)는 이 판에 들지 않았습니다 — 밖에서 만든 형식 4 파일을 이 판의 메이커로 열면 그 칸이 `연표로 ↗`에 넘어가지 않을 수 있고, 다시 저장하면 그릇 듦의 기간 · 정통성 같은 칸이 빠질 수 있습니다.');
  lines.push('- **그 밖에 고친 것**: 크게 줄여 볼 때(조감) 띠 안 이름과 알약 · 그릇 이름표가 겹치던 것, 긴 사건 막대가 다음 화면 조각으로 이어질 때 끝을 점으로 한 번 더 세워 띠 밖에 마름모 · 알약이 떠 보이던 것(0.0.1부터), 그릇 열쇠표가 상국 탭의 첫 글자를 덮던 것(이제 탭을 비키고, 좁은 띠에서는 구멍만 든 작은 열쇠표), 등불 연대기의 등불 왕국 부흥선이 하연 총관부 밑에서 끊겨 보이던 것(0.0.1부터), 같은 이름의 다른 사람에게 혈연 부모가 잘못 이어지던 것(같은 나라 지도자를 먼저 · 같은 이름이 여럿이면 생몰이 가까운 쪽)을 고쳤습니다.');
  if (curatedSince && repo && sha) lines.push(`- 모든 변경: [${curatedSince} 뒤](https://github.com/${repo}/compare/${curatedSince}...${sha})`);
  lines.push('');
  lines.push('## 0.0.4에서 달라진 것(게시하지 않은 판)');
  lines.push('');
  for (const line of NOTES_004.slice(0, -1)) lines.push(line);
  // 마지막 줄의 '연표 앱은 … 아직 그리지 않습니다(다음 판)'는 이 판(4단계)에서 그리게 되어 뺀다.
  lines.push('- **예전 앱과 주고받기**: 형식 1 · 2 · 3 파일은 그대로 열리고, `파일 → 옛 형식(3)으로 내보내기`는 빠지는 칸을 먼저 알려 줍니다.');
  // 0.0.3 뒤 · 0.0.4 판 올림 전에 main에 든 메이커 일(인수인계 5-8 · 5-13 ~ 5-16 · 5-23) — 0.0.4 글이 적지 않은 것.
  lines.push('- **DLC 메이커 — 문화권 · 고칠 수 있는 칸**: 문화권을 메이커에서 만듭니다(바탕 자료 「문화권」 탭 — 트랙의 문화권 고르기에 켠 DLC의 문화권도 나옴). 프로그램에 들어 있던 문화권은 지우고 자료로 옮겨, 동아시아는 기본팩이 · 가상 세계 일곱은 등불 연대기 견본이 제 문화권으로 듭니다(문화권이 없는 예전 등불 파일은 메이커에서 문화권을 만들어 다시 저장하세요). 지도 · 글꼴 · 영토 · 판 설정 · 그림 바꿔 끼우기 · 트랙 설명처럼 메이커로 고칠 길이 없던 칸을 모두 메이커에서 고칩니다. 미리보기를 연표 앱의 서고 모양(띠 높이 · 빈 줄 접기 · 문화권 머리 단 · 그릇 세 상태 · 승계선 끝의 구멍 · 칸 단과 흐림)으로 바꿨고, 통째 붙여넣기에 시대구분 · 대범위 층이 생겼습니다.');
}
if (v === '0.0.4') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  for (const line of NOTES_004) lines.push(line);
  if (curatedSince && repo && sha) lines.push(`- 모든 변경: [${curatedSince} 뒤](https://github.com/${repo}/compare/${curatedSince}...${sha})`);
}
if (v === '0.0.3') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **견본 등불 연대기 2.0.1**: 목록에 없는 가문 · 나라를 가리키던 곳을 메웠습니다 — 인물 활동 22곳이 제 나라에 이어져 활동 막대가 그려지고, 가문 물새씨 · 백탑 대단장가가 생기고, 개요 문서의 호반성 등좌 문장이 보입니다. 안드로이드 판타지 판과 Windows 포터블의 등불 연대기 모두 새 판입니다.');
  lines.push('- **판(집합 보기)의 선**: 판을 켜면 승계선 · 동군연합 이음줄이 엉뚱한 줄에 그어지던 것을 고쳤습니다. 판 안에서도 두 나라가 모두 판에 있으면 승계선이 그려지고, 등불 연대기에서 빠지던 시대 구분 판 넷(등불 왕국 시대 · 아홉 불씨 시대 · 설원 제국 시대 · 항로 시대)이 들어갑니다.');
}
if (v === '0.0.2') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **안드로이드 연표 앱 — 판타지 판**: 휴대폰 앱에는 이번 판부터 가상 세계 견본 「등불 연대기」만 들어 있습니다(동아시아 기본팩 없음). 0.0.1 위에 설치하면 앱이 든 저장소를 새것으로 바꿉니다.');
  lines.push('- **견본 등불 연대기 2.0.0**: 나라 · 트랙 7개, 사건 75개, 인물 65명, 그림 5장, 지도 1장으로 크게 늘었습니다. Windows 포터블의 `등불 연대기-열기.cmd`도 새 판입니다.');
  lines.push('- **가상 세계 문화권**: 등불 분지권 · 설령 빙원권 · 청림 수해권 · 적석 협곡권 · 백사 해협권 · 산호 열도권 · 서해 백탑권 — 연표의 문화권 머리 단으로 보이고, DLC 메이커의 트랙 표 `문화권`에서 고를 수 있습니다(실제 역사 문화권 뒤에 놓임).');
}
if (v === '0.0.1') {
  // 새 저장소의 첫 판(2026-10-16 감독 "HistoryTime 부터는 … 새로운 시작으로") — 옛 저장소 2.4.0 뒤의 변경을 묶는다.
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **새 저장소**: 이 저장소(HistoryTime)에서 판을 0.0.1부터 새로 셉니다 — 앞선 판은 2.4.0입니다. 안드로이드 **DLC 메이커** 앱은 판 번호가 내려가 예전 앱 위에 덮어 설치할 수 없습니다 — 휴대폰의 작업본을 `파일로` 내보내 둔 뒤 예전 앱을 지우고 새로 설치하세요.');
  lines.push('- **DLC 메이커**: 통째 붙여넣기에 지도자 말고 다른 인물(왕가 · 즉위하지 않은 왕통 · 활동 인물)을 넣는 `인물` 칸 블록이 생겼습니다. 편집 창 머리의 「계보」(또는 보기 메뉴)로 승계표 · 세계표를 열고, 세계표 창 안에서 자식 · 형제 · 배우자 · 부모를 바로 더합니다. 컴퓨터 메이커의 `연표로 ↗`는 이제 연표 앱을 띄워 고치던 작업본을 서재 위에 얹어 보여 줍니다(서재는 그대로 · 처음 한 번 연표 앱의 자리를 고름).');
  lines.push('- **DLC 끄기 · 빼기**: DLC를 끄면 연표에서 아예 빠지도록 서재를 다시 짓습니다(시대 · 검색 · 필터 · 렌즈에도 남지 않음 — 컴퓨터만). 동아시아 기본팩도 끄거나 뺄 수 있습니다.');
  lines.push('- **문서**: 문서 창을 연표 옆에 나란히 열고(머리의 단추로 넓게 ↔ 나란히), 본문 있는 문서를 갈래별 카드로 모은 문서 대문이 생겼습니다(맨 위 줄 서가 단추 · 고른 것 없이 `W`).');
  lines.push('- **상세 창**: 머리의 ← 단추로 앞에 보던 것으로 돌아갑니다. 소속 · 승계의 구분 칸(국가 · 부흥 · 간접 …)을 좁혀 이름이 넓게 보입니다.');
  lines.push('- **그 밖에**: 축소했을 때 숫자로 뭉친 사건 점이 띠 밖으로 나가던 것 · 겹친 사건 점의 테두리가 어긋나던 것을 고쳤습니다. 휴대폰 연표 앱은 켤 때부터 가로이고 왼쪽 칸이 좁아졌습니다(240 → 160).');
}
if (v === '2.4.0') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **DLC 메이커**: 트랙 표에 `문화권` 칸이 생겼습니다(비우면 동아시아). 새 형식(형식 4)의 DLC 파일도 열립니다 — 지금 형식으로 바꿔 읽고, 저장은 지금 형식으로 합니다. 메이커 안의 연표 미리보기는 아직 예전 모양입니다(아래 연표 앱의 새 모양과 다릅니다).');
  lines.push('- **연표 앱 새 모양(서고)**: 띠가 꼬리표 꼴이 됐습니다 — 맨 위 얇은 나라 색줄, 지도자 · 시기 같은 칸 뭉치, 늘 남는 흰 사건 칸. 바탕은 옅은 회색, 미상처럼 연한 것은 투명도 대신 연한 색으로, 불확실한 띠는 옅은 실선 테로 그립니다. 왼쪽 칸 · 날짜 칸 · 상세 창(큰 꼬리표 카드)도 새로 그렸고, 확대 단추는 도구줄 오른쪽으로 옮겼습니다.');
  lines.push('- **문화권 · 그릇**: 트랙 위에 문화권 머리 단이 생겨 문화권째 접고 폅니다. 대범위(그릇)는 폴더처럼 펼침 · 접힘 · 풀림 세 상태이고, 그릇 안을 오른쪽 클릭(휴대폰은 길게 누르기)해 바꿉니다. 그릇 안의 그릇도 겹쳐 그립니다.');
  lines.push('- **플래그**: 정권 · 단체 · 속국 · 할거의 펼치고 접기를 꼬리표마다 하나 있는 플래그에 모았습니다. 매단 속국 꼬리표는 처음에 접혀 있습니다.');
  lines.push('- **관계선**: 승계선 · 소속선을 띠 테의 빛깔로 또렷하게 그리고, 띠나 선에 올리면 색으로 강조합니다.');
  lines.push('- **Windows 글자**: 멈춘 화면의 글자를 ClearType으로 또렷하게 그립니다 — `⋯` 차림표의 `글자 › ClearType`에서 끌 수 있습니다. 포터블의 DLC 더하기도 빨라졌습니다(약 9초 → 1초 남짓).');
}
if (v === '2.3.0') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **확대 · 축소**: 날 단위로 크게 확대해도 버벅이지 않습니다(긴 관계선의 점선을 화면 밖까지 세던 것). 3년 남짓 확대하면 지도자 · 시기 칸의 이름이 사라지던 것, 축소하면 지도자 칸 줄이 토막 나 보이던 것을 고쳤습니다.');
  lines.push('- **띠**: 끝(시작)을 모르는 띠의 옅어지는 꼬리가 같은 줄의 다음(앞) 나라 띠를 덮지 않습니다. 아래로 내려 볼 때 왼쪽 칸의 민족 막대가 맨 위 줄로 비치던 것도 고쳤습니다.');
  lines.push('- **시대 구분 접기**: 날짜 칸의 시대 구분 줄을 공통 줄까지 모두 `시대 구분 n줄 ▸` 한 줄로 접습니다 — 시대 구분 줄의 왼쪽 이름을 누르세요(맨 처음 줄에 ▾).');
  lines.push('- **상세 창**: 다른 이름 · 실재성 · 소속 · 승계 같은 묶음을 머리글을 눌러 접고 펼 수 있고, 접은 묶음은 다른 나라를 열어도 접힌 채로 기억합니다. 다른 이름이 한 글자씩 세로로 서던 것을 고쳤고, 승계 · 소속 · 가문 구성원의 연도가 한 칸에 가지런히 맞습니다.');
  lines.push('- **가문 창의 다스린 기간**: 막대 밑에 나라의 기간만 적혀 가문의 기간처럼 읽히던 것을 고쳐, 그 가문이 실제로 자리에 있던 해를 나라마다 적습니다. 재상 · 섭정처럼 내각(실권)으로 나라를 쥔 가문도 옅은 칠과 `실권` 글로 나오고, 끝을 모르는 기간은 `~ 미정`으로 적습니다.');
  lines.push('- **견본 DLC**: 기능마다 따로 있던 견본을 모두 지우고, 한 세계로 엮은 대체역사 견본 「등불 연대기 — 아홉 불씨의 대륙」 하나로 바꿨습니다(포터블에는 `등불 연대기-열기.cmd`로 함께 들어 있습니다).');
}
if (v === '2.2.0') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **DLC 메이커 통째 붙여넣기 — 칸 블록**: 칸 채우기 답의 코드 블록 `#HT칸 1` … `#끝`(한 줄 = 한 층 `층 이름,자리,…`)을 붙여넣으면 시대의 모든 칸을 한 번에 채웁니다. 읽지 못한 줄은 블록의 줄 번호와 함께 알려 주고, 답이 끊겼으면 이어진 답의 블록까지 함께 붙여넣으면 됩니다. 예전 꼴(마크다운 절)의 답은 읽지 않으니 칸 채우기 프롬프트를 새 꼴로 다시 받으세요.');
  lines.push('- **다른 나라에도**: `이어받은나라` · `속했던나라` 층은 이 나라를 저장할 때 그 나라들의 승계 · 소속 칸에도 이 나라를 넣습니다(되돌리기 한 걸음 · 잠긴 팩은 미리 보기의 「자물쇠 풀기」). 답에 섞인 링크는 설명 · 메모에서 이름만, 출처는 주소까지 남깁니다.');
}
if (v === '2.1.0') {
  lines.push('');
  lines.push('## 이번 판에서 달라진 것');
  lines.push('');
  lines.push('- **동군연합 이음줄**: 같은 사람이 같은 때 두 나라의 지도자이면 겹친 기간의 가운데에서 두 지도자 칸을 꿰는 옅은 줄과 끝의 고리(올리면 짙게 · 풍선 글). 한쪽이 화면 밖이면 칸 이름 앞에 겹고리 표지 — 독립형 앱 · 지금 연표 · DLC 메이커 모두. DLC는 두 칸의 `person`만 같게 적으면 됩니다.');
}
if (v === '2.0.0') {
  // 큰 판(2026-10-14 감독 "dlc 메이커 앱 등 변경사항이랑 여기 고친 것들 메이저 업데이트로") — 1.2.3의 메이커 앱 · 건의 8건 + 1을 묶는다.
  lines.push('');
  lines.push('## 이번 큰 판에서 달라진 것');
  lines.push('');
  lines.push('- **DLC 메이커 앱**: Windows(단일 실행 파일 · 설치 파일)와 **안드로이드**(`HistoryTimelineMaker-…-arm64.apk`)로 판마다 늘 게시 · 칸 채우기 답을 **통째 붙여넣기**로 한 번에.');
  lines.push('- **도구줄 · 차림표**: 글자 대신 선 기호 · 단추와 차림표 글은 이름만(풀이는 풍선으로).');
  lines.push('- **상국 표기**: 속국 띠 뒤에 상국 빛깔의 뒤 장 + 관계가 끝나는 쪽의 상국 탭 · 상국 띠 아래 **매달린 속국 띠는 한 줄 13px(글 8px)** · 상국 띠의 `▾ 속국 n` 단추로 **접기**.');
  lines.push('- **세계표 · 승계표**: 점 단계(한눈에) · 이름 미상은 글자 없는 원 · 복위 화살표는 아래 · **한 사람의 창**(같은 사람의 자리를 모아 보기) · 같은 사람의 칸을 함께 테두리.');
  lines.push('- **날짜를 정확히 모르는 점 사건**: 범위 없이 점 하나로 — 그 해(달 · 날 · 세기 구간)의 **가운데**에 서고 확대해도 움직이지 않음. 같은 때 사건이 겹치면 메이커 사건 폼의 **자리**(`spot`)로 옮김.');
  lines.push('- 크게 줄일 때(조감 등) 옛 이름이 남던 잔상을 없앰 · 작은 판 릴리즈는 APK · 포터블 · 메이커 앱만.');
  lines.push('- **저장소**: 새 판의 앱에 든 저장소는 새 모양입니다. 예전 판에서 DLC를 더해 지은 저장소는 예전 모양(매달린 띠 23px · 날짜를 모르는 점은 구간 첫머리)으로 보이고, DLC를 한 번 더 더하거나 빼면 새로 지어집니다.');
}
if (v === '1.2.3') {
  lines.push('');
  lines.push('## 이번 판의 변경');
  lines.push('');
  lines.push('- DLC 메이커 **통째 붙여넣기**: 칸 채우기 답을 통째로 붙여넣으면(메이커에서 Ctrl+V · 시대 편집 창의 「통째 붙여넣기」) 기본 칸 · 지도자 · 연호 · 도읍 · 연대 · 문서까지 시대의 모든 칸을 한 번에 채웁니다.');
  lines.push('- DLC 메이커를 **안드로이드 앱**(`HistoryTimelineMaker-…-arm64.apk`)으로도 짓고, 메이커 Windows 앱과 함께 판마다 늘 게시합니다.');
}
lines.push('');
lines.push('## 무엇이 들었나');
lines.push('');
lines.push('| 파일 | 무엇 |');
lines.push('| --- | --- |');
for (const [name, what] of present) lines.push(`| \`${name}\` | ${what} |`);
if (missing.length) {
  lines.push('');
  lines.push(`이번 판에 없는 파일(그 빌드가 실패해 빠졌습니다 — 다음 판에서 다시 지어 올립니다): ${missing.map(([n]) => `\`${n}\``).join(' · ')}`);
}
if (!full) {
  // 작은 판: 설치 · 알릴 것을 두 줄로.
  lines.push('');
  lines.push('## 알려 둘 것');
  lines.push('');
  lines.push(`- **안드로이드 APK는 ${debugKey || !signature ? '디버그 키로' : '임시 키로'} 서명한 시험판입니다** — 알 수 없는 출처를 허용해 설치합니다. 정식 서명 키의 판이 나오면 지우고 새로 설치하세요.`);
  lines.push('- **Windows 포터블은 코드 서명이 없어** 처음 열 때 경고할 수 있습니다(`추가 정보` → `실행`). 받은 파일은 `SHA256SUMS.txt`로 확인합니다.');
  lines.push(PORTABLE_NEW_FOLDER);
}
if (full && main) {
  lines.push('');
  const extras = main.packs.filter(p => !p.base);
  lines.push('## 든 저장소');
  lines.push('');
  lines.push(`- **${main.label}** — 독립형 앱이 기본으로 여는 저장소(${fantasyApk ? 'Windows — 휴대폰 판타지 판은 등불 연대기' : 'Windows · 안드로이드'}): 동아시아 기본팩${extras.length ? ` 위에 **견본 DLC ${extras.length}벌**을 얹었습니다 — DLC 관리(\`D\`)에 견본마다 카드가 있어 켜고 끄며 하나씩 봅니다` : ''}.`);
  for (const p of extras) lines.push(`  - ${p.name}${p.sample ? ` (\`${p.sample}\`)` : ''}`);
  for (const s of others) lines.push(`- **${s.label}** — 「${s.base.name}」(견본 · 사건 ${s.count.toLocaleString('ko-KR')}개): 지어낸 나라와 사람으로 연표의 기능을 모두 보여 주는 가상 세계 하나 — 기본팩 없이 그것만으로. ${fantasyApk && s.key === 'lantern' ? '휴대폰 설치 파일(판타지 판)에는 이것만 들었습니다.' : `Windows판에만 들었습니다(휴대폰 설치 파일에는 ${fantasyApk ? '등불 연대기' : main.label}만).`}`);
  const skipped = (showcase.skipped || []).filter(s => !/^DLC가 아님/.test(s.reason || ''));
  if (skipped.length) {
    lines.push('');
    lines.push(`이번 판에서 뺀 견본(지금의 아카이브 짓기(엔진)가 받지 못함): ${skipped.map(s => `\`${s.file}\` — ${s.reason}`).join(' · ')}`);
  }
}
if (full) {
  lines.push('');
  lines.push('## 설치');
  lines.push('');
  lines.push('- **Windows**: 설치 파일을 열거나, 포터블 zip을 통째로 풀어 씁니다. 코드 서명이 없어 처음 열 때 Windows가 경고할 수 있습니다(`추가 정보` → `실행`).');
  lines.push(PORTABLE_NEW_FOLDER);
  lines.push('- **안드로이드**: APK를 휴대폰에 받아 엽니다(알 수 없는 출처 허용). 처음 실행할 때 든 저장소를 앱 폴더에 놓습니다.');
  lines.push('- DLC 더하기(독립형 앱 · Windows · 안드로이드): DLC 관리 → `📂 파일에서 더하기…`로 메이커가 저장한 `.htpack`을 고릅니다. 앱 안의 엔진이 직접 읽어 저장소를 제자리에서 고쳐 씁니다(Node.js 없음).');
  lines.push('');
  lines.push('## 알려 둘 것');
  lines.push('');
  lines.push('- **시험판**입니다. 독립형 앱의 창 제목 · 안드로이드 앱 이름은 아직 시제품 이름(`별여울 아카이브 - 성능 시제품` · `별여울 성능 시제품`)입니다.');
  lines.push(`- **안드로이드 APK는 ${debugKey || !signature ? '디버그 키로' : '임시 키로'} 서명했습니다**(앱의 build.gradle.kts 그대로 — 시험판). 정식 서명 키로 서명한 판이 나오면 그 위에 덮어 설치할 수 없으니 지우고 새로 설치하세요. Play 프로텍트가 경고할 수 있습니다.`);
  lines.push('- **Windows 파일은 코드 서명이 없습니다.** 받은 파일은 `SHA256SUMS.txt`로 확인할 수 있습니다.');
  lines.push('- 독립형 앱의 DLC 더하기 · 빼기는 연 저장소를 제자리에서 고쳐 씁니다 — 저장소의 바탕(첫 DLC)은 뺄 수 없습니다.');
  lines.push('- 독립형 앱의 설치 파일로 새 판을 덮어 설치하면 `자료` 폴더의 저장소도 새 판의 것으로 바뀝니다(더해 둔 DLC의 파일은 `DLC` 폴더에 남아 새 판의 앱을 열 때 저장소에 다시 넣습니다 — 뺀 DLC · 끈 DLC는 넣지 않습니다).');
}
if (signature) {
  lines.push('');
  lines.push('<details><summary>APK 서명 인증서</summary>');
  lines.push('');
  lines.push('```');
  lines.push(signature.trim().split('\n').filter(l => /Signer|DN|SHA-256|scheme/i.test(l)).slice(0, 12).join('\n'));
  lines.push('```');
  lines.push('</details>');
}
if (repo && sha) {
  lines.push('');
  lines.push(`만든 길: [.github/workflows/release.yml](https://github.com/${repo}/blob/${sha}/.github/workflows/release.yml) · 저장소: [prototype/scripts/build-showcase.mjs](https://github.com/${repo}/blob/${sha}/prototype/scripts/build-showcase.mjs)`);
}
fs.writeFileSync(out, lines.join('\n') + '\n');
console.log(`릴리즈 글: ${out} · ${full ? '전체' : '작은 판'} · 파일 ${present.length}개${missing.length ? ` · 빠진 것 ${missing.length}개` : ''}${changes ? ` · ${changes.since} 뒤 변경 ${changes.subjects.length}건` : ''}`);

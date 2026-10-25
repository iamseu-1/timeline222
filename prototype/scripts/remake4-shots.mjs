// 리메이크 4단계 기준 그림 틀(docs/계획-리메이크-4단계.md 과제 1 걸음 2): 걸음마다 '새 값이 없는 장면은 4단계 전 앱과 그림 바이트가 같다'를 보고,
// 새 값이 있는 장면은 메이커 서고 미리보기와 1배로 나란히 놓는다. 결과는 모두 prototype/results/remake4-shots/(git 밖)에.
// 사용(작업 폴더에서):
//   node prototype/scripts/remake4-shots.mjs --stores [--rebuild] [--release-data=<배포본 자료 폴더>]
//       저장소를 stores/<이름>/archive.db에 한 번 짓고 계속 쓴다 — archive-tool build(--now 고정 · 달력 표 prototype/results/calendar-cache.json) ·
//       판 3 둘은 배포본 0.0.4의 자료 폴더(읽기만)를 복사한다. 있는 저장소는 건너뛴다(--rebuild면 다시).
//   node prototype/scripts/remake4-shots.mjs --census
//       저장소마다 새 값의 수(띠 form≠0 · 문화권 단위 줄 kind 1 · 2 · 3 · 칸 종류 9 · 27비트 칸 · 구역 54 · 55 · 56 · x_titles 든 인물 ·
//       꼬리표 끝이 옛 짐작과 갈리는 띠 · 대립 띠 · 왕조 줄 · 지위 줄 · 선반 변형 kind 6 · 포개진 그릇 변형 · 칸 그림 갈래의 두 단 띠 · 직위 줄 더 띠 ·
//       줄어드는 층 줄 · 구역 57 · 58 · 띠 주장) → census.json · 표 · 걸음마다 '바이트 같아야 할 장면'.
//       앱이 읽는 그 저장소(SQLite)에서 바로 센다 — 내보내기 JSON을 다시 뽑지 않고, 판 3 저장소도 같은 길로.
//   node prototype/scripts/remake4-shots.mjs --tag=<이름> [--only=<장면>,…] [--app=<이름|실행본 경로>] [--paint-off=ink,tag,flaw,chain,folder,lid,cycle,legit,office,body,route,rows|all] [--paint-rows=a|b|c|off] [--paint-on=cross] [--overwrite]
//       장면마다 실제 앱을 띄워(--capture-only · 1920×1080 · --capture-script · --memory-dir=<결과 폴더 안>) shots/<이름>/<장면>.png.
//       문화권은 모두 펼친다 — 대본 걸음을 새로 만들지 않고 이미 있는 --capture-memory(기억 사본의 viewState.foldedSpheres = [])로.
//       장면에 fold: 'first'면 기억 사본에 viewState를 적지 않아 앱을 처음 열 때의 접힘(자료의 default — 없으면 첫 문화권 하나만 폄) 그대로.
//       장면에 script가 있으면 찍기 전에 그 대본 걸음(measure/verify_script.dart — 예: {do:'select', uid})을 돌리고, foldScopes가 있으면 그 그릇을 켠 채
//       접는다(그릇 안 오른쪽 클릭 '접음'과 같은 대본 명령 — 찍은 뒤 앱이 쓴 기억의 접힘 열쇠 `<트랙 id>|__scope:<uid>`(그 저장소의 변형 표에서)로 확인).
//       장면에 expandHosts가 있으면 그 상국(객체 id나 uid)을 펼친 채(속국 펼치기 변형 — 기억 사본의 viewState.expandedHosts에 그 띠 번호) 찍고, 찍은 뒤
//       대본 기록의 펼친 상국으로 정말 펼쳤는지 본다(아니면 실패).
//       장면에 ganji: true면 대본 맨 앞에 날짜 칸 간지 줄을 켜는 필터 걸음({do:'filters', json:{show:{ganji:true}}})을 두고 찍은 뒤 장면의 표시로 켜졌는지 본다 ·
//       foldSpheres가 있으면 그 문화권(id)만 접은 채(기억 사본의 viewState.foldedSpheres) 찍고 앱이 쓴 기억의 접힘으로 정말 접혔는지 본다(아니면 실패).
//       장면에 scopeStates({객체 id나 uid: 'open'|'shelf'|'closed'} — foldScopes를 넓힌 것 · 과제 7)가 있으면 적은 차례대로 대본 맨 앞에 같은 명령
//       scopeState <상태>를 두고, 찍은 뒤 대본 기록의 켠 그릇(openScopes) · 선반 기억(shelvedScopes) · 켠 변형 열쇠(variantKeys — 선반이면 shelf:<uid>)와
//       기억의 접힘 열쇠로 펼침 · 선반 · 접음을 본다(아니면 실패 — 선반 확인은 과제 7 걸음 4부터).
//       장면에 reopen(앞 장면 id — 과제 7 걸음 5)이 있으면 이 태그에서 먼저 찍은 그 장면의 기억 폴더(_run/<앞 장면>/memory)를 사본으로 받아 대본 없이
//       다시 열고, 그림이 앞 장면과 바이트 같은지 · 앱이 쓴 기억에 선반(viewState.shelvedScopes)과 그릇 켬(filters.scopes)이 남았는지 · 기억의
//       viewState가 다시 열며 바뀌지 않았는지(결함 ㉡ — 기억을 이을 때 덮어쓰기)를 본다(아니면 실패).
//       장면에 dlcAdd(넣을 .htpack — 과제 7 검토 고침)가 있으면 그릇 상태 뒤에 대본 dlc add · until idle을 두고, 찍은 뒤 그릇 상태 확인(DLC를 넣은 뒤의 기록)에 더해
//       저장소의 DLC 수(+ 넣은 수) · 앱이 쓴 기억의 선반(viewState.shelvedScopes)을 본다(아니면 실패 — DLC 넣고 빼기가 선반 기억을 옮기는 길).
//       --paint-off는 4단계 감독 고름 그림(먹 · 꼬리표 · 흠 · 사슬 · 폴더 · 뚜껑 · 주기)과 칸 그림 셋(정통성 · 직위 줄 더 · 몸통) · 이어 주는 선의 새 길(route) ·
//       칸 층 가로선(rows)을 끈 찍기
//       (앱 scene/paint/paint_pick.dart — 찍기 · 증명 전용)로, 정보(_실행본.json)에 적는다.
//       --paint-rows는 칸 층 사이 흐린 가로선의 꼴(감독 지적 2026-10-25 — 앱 scene/paint/floor_rules.dart · 감독 결정 b 기본 · a · c · off)을 고른 찍기로, 정보에 적는다.
//       --paint-on=cross는 기본이 끔인 1배 후보를 켠 찍기(이어 주는 선 걸음 5 — 굴 문 대신 건넘 토막)로, 같이 정보에 적는다.
//   node prototype/scripts/remake4-shots.mjs --tag=<이름> --compare=<태그> [--step=<걸음>] [--no-capture]
//       장면마다 바이트 같음/다름 표(다르면 다른 픽셀 수 · 범위). --step이면 census로 그 걸음까지 바뀌어도 되는 장면을 가르고(판 3 저장소는 늘 같아야 함),
//       나머지가 다르면 끝 코드 1. --step이 없으면 모든 장면이 같아야 한다.
//       걸음 10 ~ 16(감독 고름 차례) · 17(구분선 갈래) · 81 ~ 83(과제 8 갈래) · 91(이어 주는 선 갈래)은 **앞 걸음 태그와** 견주므로 그 걸음 하나의 몫만 본다(누적 아님). 옛 저장소도 바꾸는 걸음(old — 먹 · 사슬 · 폴더)은
//       판 3 저장소도 바뀌어도 되고, 그 걸음의 판정은 끈 찍기(`--tag=g1x-off --paint-off=<스위치> --compare=<앞 걸음 태그>` — 모든 장면 바이트 같음)로 한다.
//       과제 7(상자 · 선반)의 걸음 70 · 72 · 73 · 74도 앞 걸음 태그와 견준다(기준 = 바탕 실행본의 sc0 · 바뀌어도 되는 장면 = 장면 표시 box · shelf · reopen).
//       걸음 31 ~ 35(칸 그림 갈래 — 가지 remake-4-cells · 다른 그림 갈래와 번호가 겹치지 않게 31부터)도 같은 규칙(앞 걸음 태그와 · 끈 찍기 legit · office · body).
//       기준 태그에 없는 장면은 '새 장면'으로 적고 실패로 치지 않는다.
//   node prototype/scripts/remake4-shots.mjs --maker --tag=<이름> [--only=f4-crowns] [--app=<이름|실행본 경로>]
//       같은 작업본 · 범위로 scripts/maker-shoot.mjs(--fold-spheres=none · HT_PLAYWRIGHT_ROOT)를 찍어 side-by-side.mjs로 한 장에 나란히(maker/<이름>/).
//       형식 4 작업본은 메이커가 파일을 열 때처럼 옛 꼴로 내려(HT.F4.down + f4extras) maker/drafts/에 써서 준다(makerDraft).
//       장면의 그릇 상태(scopeStates · reopen이면 앞 장면의 것)는 미리보기 uid로 바꿔 선반은 --shelve · 펼침 · 접음은 --scope-states로 넘기고(과제 7 걸음 6),
//       미리보기가 정말 그 상태인지 maker-shoot가 보아 아니면 실패. --app을 주면 그 실행본으로 앱 그림도 먼저 이 태그에 찍는다(없으면 이 태그의 앱 그림을 씀).
//   node prototype/scripts/remake4-shots.mjs --window --tag=<이름> [--app=<이름|실행본 경로>] [--paint-off=…] [--paint-rows=…] [--paint-on=…] [--overwrite] [--compare=<태그>] [--no-capture]
//       사람 창 찍기(앞 차례 회귀 — 등불 저장소 · 대본 prototype/fixtures/remake4/window-script.json 여섯 장 + 화면-1배): window/<이름>/에 일곱 장.
//       기억은 찍기마다 기억 원본(prototype/fixtures/remake4/window-memory)의 사본을 --capture-memory로 넘긴다 — 원본을 바로 주면 앱이 끝 상태를 거기에
//       다시 써 다음 찍기의 처음이 달라진다. --compare면 두 태그의 일곱 장이 모두 바이트 같아야 통과(예: --window --tag=g16-off --compare=r1 --no-capture).
//   node prototype/scripts/remake4-shots.mjs --keep-app=<이름>   지금 지은 실행본 폴더를 app/<이름>/에 남김(뒤에 --app=<이름>으로 다시 찍기)
//   node prototype/scripts/remake4-shots.mjs --list              장면 표
//   덧 인자(축소 글자 겹침 조사 — 2026-10-25): --scene-file=<json>이면 장면 표 대신 그 파일의 장면 목록(SCENES와 같은 꼴 + size: '1280x800' — 창 크기 ·
//   없으면 1920×1080) · --shots=<폴더>면 찍은 그림을 results/remake4-shots/shots 대신 <폴더>/<태그>/에(저장소 · 실행본 자리는 그대로) ·
//   --text면 앱에 --capture-text=yes를 넘겨 마지막 장면에 그린 글줄의 상자를 <장면>.text.json으로 함께 남긴다(scripts/text-overlap.mjs가 읽음).
//   --lines면 앱에 --capture-lines=yes를 넘겨 마지막 장면의 선 감사(앱 scene/paint/links.dart LineAudit — 이어 주는 선 걸음 1)를 <장면>.lines.json으로 함께 남긴다.
// 실행본은 prototype/scripts/dev.ps1 app-build(-Junction <이름>)로 지은 release. 앱은 늘 --memory-dir=<결과 폴더 안>으로 띄운다(판정 R50).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const root = path.resolve(prototype, '..');
const results = path.join(prototype, 'results', 'remake4-shots');
const args = Object.fromEntries(process.argv.slice(2).map(a => { const m = a.match(/^--([^=]+)(?:=(.*))?$/); return m ? [m[1], m[2] ?? ''] : ['', a]; }));
const known = new Set(['scene-file', 'shots', 'text', 'lines', 'stores', 'rebuild', 'release-data', 'census', 'tag', 'only', 'app', 'paint-off', 'paint-rows', 'paint-on', 'overwrite', 'compare', 'step', 'no-capture', 'maker', 'keep-app', 'list', 'window']);
for (const k of Object.keys(args)) if (!known.has(k)) die(`모르는 인자 --${k} (${[...known].join(' · ')})`);

function die(msg) {
  console.error(`remake4-shots: ${msg}`);
  process.exit(2);
}

/** 저장소를 지을 때의 '오늘' — 정답지(layout-oracle.mjs)와 같은 시각 · 시간대(진행 중 정권의 끝이 지은 날에 묶이지 않게). */
const NOW = '2026-10-15T12:00:00+09:00';
/** 판 3 저장소 둘이 든 배포본 0.0.4의 자료 폴더(읽기만 — 사본으로 쓴다). */
const RELEASE_DATA = args['release-data'] || 'C:/claude/HistoryTime/배포/HistoryTimeline-0.0.4/자료';
const CALENDAR = path.join(prototype, 'results', 'calendar-cache.json');

/** 저장소: files = archive-tool build의 팩(작업 폴더 기준 — 정답지처럼 팩 하나씩) · copy = 배포본 자료 폴더의 이름 · draft = 메이커 미리보기의 작업본. */
const STORES = {
  lantern: { files: ['samples/sample-lantern.json'], draft: 'samples/sample-lantern.json', note: '견본 등불 연대기' },
  'east-asia': { files: ['prototype/fixtures/oracle/east-asia.json'], note: '기본팩 동아시아(정답지의 굳힌 사본)' },
  'f4-crowns': { files: ['prototype/fixtures/f4/f4-crowns.json'], draft: 'prototype/fixtures/f4/f4-crowns.json', note: '형식 4 가상 팩 — 왕관 여섯(장면 1)' },
  'f4-liege': { files: ['prototype/fixtures/f4/f4-liege.json'], draft: 'prototype/fixtures/f4/f4-liege.json', note: '형식 4 가상 팩 — 섬김 둘(장면 4)' },
  'f4-sphere': { files: ['prototype/fixtures/f4/f4-sphere.json'], draft: 'prototype/fixtures/f4/f4-sphere.json', note: '형식 4 가상 팩 — 문화권 시대 · 주기(장면 5)' },
  'f4-federation': { files: ['prototype/fixtures/f4/f4-federation.json'], draft: 'prototype/fixtures/f4/f4-federation.json', note: '형식 4 가상 팩 — 도시 · 교단 · 제후국(장면 2)' },
  'f4-office3': { files: ['prototype/fixtures/oracle/f4-office3.json'], draft: 'prototype/fixtures/oracle/f4-office3.json', note: 'f4-office + 직위 줄 더 · 빌림 · 제 안의 실권자(3단계 검사 자료)' },
  // f4-sphere 혼자는 줄이 적어 내려 볼 수 없다(--capture-scroll이 0으로 잘림) — 같은 문화권 id(ember-basin · frost-ridge)를 쓰는 등불에 얹어 키 큰 문화권에 시대 · 주기 줄을 둔다.
  'lantern-sphere': { files: ['samples/sample-lantern.json', 'prototype/fixtures/f4/f4-sphere.json'], note: '등불 + f4-sphere 얹음(키 큰 문화권의 시대 · 주기 줄 — 머리 단 고정)' },
  // 감독 고름 차례(걸음 10 ~ 16)에 더함 — 고르기 판 G6 · G5-9b 장면을 형식 4로 옮긴 시험 자료. f4check: 짓기 전에 형식 4 다리 · 정규화의 알림 · 경고 · 오류가 0인지 본다.
  'f4-choose': { files: ['prototype/fixtures/remake4/f4-choose.json'], draft: 'prototype/fixtures/remake4/f4-choose.json', f4check: true, note: '형식 4 시험 자료 — 감독 고름(꼬리표 끝 · 대립 · 흰 사슬 · 서고 흠)' },
  // 과제 8 갈래(가지 remake-4-folders — 차례 걸음 81 ~ 83)에 더함: 소속 펼치기의 폴더 · 그릇 노릇 객체의 꼴을 볼 시험 자료.
  'f4-folders': { files: ['prototype/fixtures/remake4/f4-folders.json'], draft: 'prototype/fixtures/remake4/f4-folders.json', f4check: true, note: '형식 4 시험 자료 — 과제 8(연방 · 포갠 제후국 · 동군연합 · 구성원 없는 나라 · 동맹 · 그릇 안의 소속)' },
  // 과제 7(상자 · 선반 — 그릇 그림 갈래 remake-4-scopes)에 더함 — 선반 갈래(remake-4-shelf)가 정답지 목록에 넣은 시험 자료 그대로(읽기만).
  // 선반 변형(kind 6 · 열쇠 shelf:<그릇 uid>)은 이 넷에 하나씩 생긴다(구성원이 shelfKeep 5를 넘는 그릇).
  'f4-federation-scope': { files: ['prototype/fixtures/oracle/f4-federation-scope.json'], draft: 'prototype/fixtures/oracle/f4-federation-scope.json', note: '형식 4 가상 팩 — 연방 구성원 열둘을 시대 그릇 하나(s-fed)로(선반 12 → 5줄)' },
  // 덧팩 둘은 메이커 작업본 하나에 담을 수 없어(미리보기는 작업본 하나만 띄움) 등불 작업본에 덧팩의 그릇(scopes)을 덧붙인 작업본을 준다(draftScopes —
  // 선반 셈 도구 remake4-shelf-calc.mjs의 lantern-flat · lantern-chain과 같은 길). 그래서 미리보기의 그릇 uid는 `lantern-chronicle/<그릇 id>`(엔진은 `<덧팩 id>/<그릇 id>`).
  'shelf-flat': { files: ['samples/sample-lantern.json', 'prototype/fixtures/oracle/shelf-flat.json'], draft: 'samples/sample-lantern.json', draftScopes: 'prototype/fixtures/oracle/shelf-flat.json', note: '등불 + 하연 그릇 하나(낱 사슬 일곱 — 선반 7 → 5줄)' },
  'shelf-chain': { files: ['samples/sample-lantern.json', 'prototype/fixtures/oracle/shelf-chain.json'], draft: 'samples/sample-lantern.json', draftScopes: 'prototype/fixtures/oracle/shelf-chain.json', note: '등불 + 하연 그릇 하나(승계 사슬 + 낱 사슬 넷 = 구성원 아홉 — 선반 3줄)' },
  'nest-f4': { files: ['prototype/fixtures/oracle/nest-scene.f4.json'], draft: 'prototype/fixtures/oracle/nest-scene.f4.json', note: '형식 4 포개짐 — 바깥 jp-era 안에 상자 sengoku(둘 다 default · 선반 jp-era 6 → 3줄)' },
  // 칸 그림 갈래(가지 remake-4-cells — 걸음 31 ~ 35)에 더함: 배치 갈래(remake-4-lay)의 시험 자료 둘(정답지 사본 — 가상 이름). f4check는 붙이지 않는다 —
  // f4-legit은 내보내기 알림 '지도자_두단' 넘침(다섯 겹 공동 — 4단까지)이, f4-office4는 다리 내림 알림 · 정규화 경고(기간 있는 그릇 · 모르는 정통성 '반쪽')가 일부러 있다.
  'f4-legit': { files: ['prototype/fixtures/oracle/f4-legit.json'], draft: 'prototype/fixtures/oracle/f4-legit.json', note: '형식 4 시험 자료 — 정통성 넷 가 다듬은 꼴(지도자 두 단 · 칸 · 소속 정통성) · 짧은 몸통 줄' },
  'f4-office4': { files: ['prototype/fixtures/oracle/f4-office4.json'], draft: 'prototype/fixtures/oracle/f4-office4.json', note: '형식 4 시험 자료 — 직위 줄 더의 줄 높이(G7) · 빌린 직위 줄 더 · 칸 · 소속 정통성' },
  'v3-lantern': { copy: '등불 연대기', note: '배포본 0.0.4의 판 3 저장소(옛 엔진이 지음)' },
  'v3-east-asia': { copy: '동아시아', note: '배포본 0.0.4의 판 3.1 저장소(옛 엔진이 지음)' },
};

/** 장면: 저장소 · 보는 해 범위(from ~ to) · 내려 보기(scroll — 배치 px, 그림을 뜨기 전 세로 자리) · 무엇을 보는가.
 *  script = 찍기 전 대본 걸음(measure/verify_script.dart) · foldScopes = 켠 채 접을 그릇(객체 id나 uid) · expandHosts = 펼칠 상국(객체 id나 uid — 속국 펼치기) ·
 *  flaw = 서고 흠 셋 고침(걸음 13)을 보는 장면 · ganji = 날짜 칸 간지 줄을 켠 장면(대본 맨 앞의 필터 걸음) · foldSpheres = 접을 문화권 id(나머지는 펼침) ·
 *  scopeStates = 둘 그릇 상태({객체 id나 uid: 'open'|'shelf'|'closed'} — 대본 맨 앞의 scopeState 명령) ·
 *  reopen = 앞 장면 id(그 장면이 남긴 기억 사본으로 대본 없이 다시 켬 — 과제 7 걸음 5) ·
 *  box · shelf · reopen = 과제 7의 걸음 72 · 73 · 74가 바꿔도 되는 장면. */
const BASE_SCENES = [
  { id: 'lantern-wide', store: 'lantern', from: -700, to: 1750, scroll: 0, note: '등불 넓은 범위(안개 시대 ~ 헌정 시대)' },
  { id: 'lantern-scope', store: 'lantern', from: 380, to: 820, scroll: 0, note: '등불 그릇(아홉 불씨 할거 · 청림 양분과 합류기)' },
  { id: 'lantern-down', store: 'lantern', from: 900, to: 1200, scroll: 1500, note: '등불 내려 봄(1031년 대격변 언저리 · 아래 문화권)' },
  // 걸음 5에 더함: lantern-down(1500)은 사람 띠 없는 청림 수해권 끝이라 머리 단 고정이 닿지 않는다 — 사람 띠 두 줄인 등불 분지권 안을 내려 본다.
  // 기준(before)은 4단계 전 실행본(--app=before)으로 따로 찍었다.
  { id: 'lantern-ember-down', store: 'lantern', from: 1100, to: 1450, scroll: 300, note: '등불 분지권 안 내려 봄(사람 띠 머리 단 고정 · 붙은 사람 띠의 실)' },
  { id: 'east-asia', store: 'east-asia', from: -300, to: 1950, scroll: 0, note: '동아시아 넓게' },
  { id: 'east-asia-down', store: 'east-asia', from: 1300, to: 1950, scroll: 900, note: '동아시아 내려 봄(조선 · 근대 언저리)' },
  { id: 'f4-crowns', store: 'f4-crowns', from: 1280, to: 1660, scroll: 0, note: '왕관 여섯 — 사람 띠 · 실 · 뿔 매듭' },
  { id: 'f4-liege', store: 'f4-liege', from: 990, to: 1420, scroll: 0, note: '섬김 둘(기간 있음) — 사람 띠' },
  { id: 'f4-sphere', store: 'f4-sphere', from: -20, to: 1420, scroll: 0, note: '문화권 시대 구분 · 주기 줄(위)' },
  { id: 'f4-sphere-near', store: 'f4-sphere', from: 280, to: 420, scroll: 0, note: '문화권 주기 줄 가까이(이름 돌림 해마다 칸 · 빙원력 눈금)' },
  { id: 'sphere-mix-down', store: 'lantern-sphere', from: 600, to: 1420, scroll: 400, note: '등불 + f4-sphere 내려 봄(키 큰 문화권 안 — 머리 단 고정)' },
  { id: 'f4-federation', store: 'f4-federation', from: 1140, to: 1660, scroll: 0, note: '도시 · 교단 · 제후국 — 그릇 · 꼬리표 끝 꼴' },
  { id: 'f4-office3', store: 'f4-office3', from: 380, to: 1120, scroll: 0, note: '직위 줄 더 · 빌린 층 · 실권 밑줄' },
  { id: 'v3-lantern', store: 'v3-lantern', from: -700, to: 1750, scroll: 0, note: '판 3 등불(옛 저장소 — 늘 바이트 같아야 함)' },
  // 내려 본 옛 저장소: 머리 단 고정(걸음 5)이 새 값 없는 저장소의 화면을 바꾸지 않는지 지킨다(전체 제약 '새 값이 없는 저장소의 화면은 1배 같다').
  { id: 'v3-lantern-down', store: 'v3-lantern', from: 900, to: 1200, scroll: 1500, note: '판 3 등불 내려 봄(옛 저장소 — 늘 바이트 같아야 함)' },
  { id: 'v3-east-asia', store: 'v3-east-asia', from: -300, to: 1950, scroll: 0, note: '판 3.1 동아시아(옛 저장소 — 늘 바이트 같아야 함)' },
  // 검토 지적(2026-10-25)에 더함: 위 장면은 모두 문화권을 다 펼쳐 찍어 '처음 접힘'(기억 없음 — 첫 문화권 하나만 폄)을 한 번도 보지 못했다.
  // 접힌 문화권(설령 빙원권)의 시대 구분이 공통 줄에 남는지 · 옛 저장소의 처음 접힘이 4단계 전과 같은지를 본다.
  { id: 'f4-sphere-fold', store: 'f4-sphere', from: -20, to: 1420, scroll: 0, fold: 'first', note: '처음 접힘 — 설령 빙원권이 접혀 그 시대(칸국기 · 제국기)는 공통 줄에' },
  { id: 'sphere-mix-fold', store: 'lantern-sphere', from: -700, to: 1750, scroll: 0, fold: 'first', note: '등불 + f4-sphere 처음 접힘(분지권만 펼침)' },
  { id: 'v3-lantern-fold', store: 'v3-lantern', from: -700, to: 1750, scroll: 0, fold: 'first', note: '판 3 등불 처음 접힘(옛 저장소 — 늘 바이트 같아야 함)' },
  // 감독 고름 차례(걸음 10 ~ 16)에 더함 — 고르기 판 G6 · G5-9b 장면(f4-choose 저장소). 흠 ①(그릇 둘째 줄의 매듭)은 f4-choose(남곡 할거 — 펼친 그릇의 둘째 ~ 넷째 줄)에서,
  // 흠 ②(고른 띠의 선택 테가 받침 카드를 가림)는 섬긴 띠(갈대 공국)를 고른 채, 흠 ③(접힌 폴더 몸통이 빔)은 구성원 넷의 그릇(남곡 할거)을 접은 채 본다.
  // 차례 걸음 13에서 흠 표시(flaw)를 이 셋으로 좁힘 — lantern-scope의 그릇(아홉 불씨 할거)은 풀림(열쇠표)이라 폴더가 없고, f4-federation · f4-federation-open의
  // 구성원은 속국 펼치기 줄(그릇이 아님)이라 매다는 실 · 가로대가 없다(g13 ↔ g12에서 셋 모두 바이트 같음 — 이제 같아야 함).
  { id: 'f4-choose', store: 'f4-choose', from: 1200, to: 1420, scroll: 0, flaw: true, note: '감독 고름 — 꼬리표 끝(군벌 · 회사 · 단체 · 교단 · 집단) · 대립 · 왕조 · 지위 · 그릇 둘째 줄' },
  { id: 'f4-choose-pick', store: 'f4-choose', from: 1200, to: 1420, scroll: 0, flaw: true, script: [{ do: 'select', uid: 'f4-choose/o-reed' }], note: '섬긴 띠(갈대 공국)를 고른 채 — 흠 ② 선택 테와 받침 카드' },
  { id: 'f4-choose-closed', store: 'f4-choose', from: 1200, to: 1420, scroll: 0, flaw: true, foldScopes: ['o-era'], note: '그릇(남곡 할거 · 구성원 넷)을 접은 채 — 흠 ③ 접힌 폴더 몸통' },
  // 차례 걸음 12에 더함: f4-federation 장면은 연방의 구성원 열둘(교단 둘 · 기사단 — form 종류가 옛 짐작과 갈리는 띠)이 속국 펼치기 변형(host)에 들어
  // 접힌 채라 화면에 없다. 상국(적석 제후 연방)을 펼친 채 찍는다(구성원 줄은 속국 펼치기라 그릇의 매듭 · 가로대는 없다 — 흠 장면 아님).
  { id: 'f4-federation-open', store: 'f4-federation', from: 1140, to: 1660, scroll: 0, expandHosts: ['o-fed'], note: '연방을 펼친 채 — 구성원 열둘(교단 둘 · 기사단 = 영토 밖 둥근 끝)' },
  // 과제 8 갈래(가지 remake-4-folders · 차례 걸음 81 ~ 83)에 더함. f4-folders(기본 — 소속이 모두 접힘)와 f4-folders-open(연방 · 동군연합 · 포갠 제후국 · 그릇 안 국가를
  // 펼친 채)은 소속 펼치기의 폴더(걸음 81) · 그릇 노릇 객체의 꼴(걸음 82)을, ganji 둘은 날짜 칸 간지 줄과 같은 주기를 펼친 문화권 머리 단(걸음 83 —
  // 감독 결정 2026-10-25 '육십갑자는 머리 단 주기 줄만')을 본다. f4-sphere의 맨 위 간지 설정(불씨해)과 등불 분지권의 주기 줄이 같은 이름 돌림이다.
  { id: 'f4-folders', store: 'f4-folders', from: 1100, to: 1500, scroll: 0, note: '과제 8 — 소속이 모두 접힘(연방 · 동군연합 · 구성원 없는 나라 · 동맹 · 켠 시대 그릇)' },
  // 포갠 제후국(검은솔 대공국 — 연방 안에서 다시 구성원 둘을 품음)은 펼칠 수 없다: 내보내기(export/variants.mjs)가 상국 변형을 기본 배치에 보이는 띠에만 지어
  // 접힌 연방 안의 대공국에는 변형이 없고, 그 구성원은 연방을 펼쳤을 때 대공국 밑 매단 이름표(솔뫼 백령 — 봉국)로만 오거나(솔강 자유시) 아예 오지 않는다(엔진 몫 — 갈래 보고).
  { id: 'f4-folders-open', store: 'f4-folders', from: 1100, to: 1500, scroll: 0, expandHosts: ['o-fed', 'o-union', 'o-rock'],
    note: '과제 8 — 연방 · 동군연합 · 그릇 안 국가의 소속을 펼친 채(포갠 제후국은 매단 이름표)' },
  { id: 'f4-sphere-ganji', store: 'f4-sphere', from: 280, to: 420, scroll: 0, ganji: true, note: '날짜 칸 간지(불씨해) 줄을 켬 — 같은 주기의 등불 분지권 머리 단을 펼친 채' },
  { id: 'f4-sphere-ganji-fold', store: 'f4-sphere', from: 280, to: 420, scroll: 0, ganji: true, foldSpheres: ['ember-basin'],
    note: '날짜 칸 간지(불씨해) 줄을 켬 — 등불 분지권을 접은 채(날짜 칸 줄이 돌아와야 함)' },
  // 과제 7(상자 · 선반 — 그릇 그림 갈래 remake-4-scopes 걸음 1)에 더함. scopeStates = 그릇마다 둘 상태(대본 맨 앞의 scopeState 명령 — 오른쪽 클릭과 같은 길).
  // box = 상자(걸음 2 — 안쪽 그릇 · 접힌 상자)가 바꿔도 되는 장면 · shelf = 선반(걸음 3 ~ 4)이 바꿔도 되는 장면 · reopen = 보기 기억 · 차림표(걸음 5)의 장면.
  // '-shelf' 장면은 앱이 선반 상태를 아는 걸음 4부터 찍는다(기준 sc0에는 없음 — 견줌에서 '새 장면').
  { id: 'nest-box', store: 'nest-f4', from: 1440, to: 1640, scroll: 0, box: true, scopeStates: { 'jp-era': 'open', sengoku: 'open' }, note: '포개짐 — 바깥 그릇(일본) 안에 펼친 상자(전국 시대)' },
  { id: 'nest-box-closed', store: 'nest-f4', from: 1440, to: 1640, scroll: 0, box: true, scopeStates: { 'jp-era': 'open', sengoku: 'closed' }, note: '포개짐 — 바깥 그릇(일본) 안에 접은 상자(전국 시대 — 한 줄)' },
  { id: 'fedscope-open', store: 'f4-federation-scope', from: 1140, to: 1660, scroll: 0, scopeStates: { 's-fed': 'open' }, note: '구성원 열둘의 시대 그릇(적석 연방 영지들)을 펼친 채' },
  { id: 'fedscope-shelf', store: 'f4-federation-scope', from: 1140, to: 1660, scroll: 0, shelf: true, scopeStates: { 's-fed': 'shelf' }, note: '같은 그릇을 선반으로(12 → 5줄 · 숨은 일곱은 발의 작은 꼬리표)' },
  { id: 'shelf-flat-open', store: 'shelf-flat', from: 380, to: 1120, scroll: 0, scopeStates: { 'shelf-flat': 'open' }, note: '등불 하연의 그릇(낱 사슬 일곱)을 펼친 채' },
  { id: 'shelf-flat-shelf', store: 'shelf-flat', from: 380, to: 1120, scroll: 0, shelf: true, scopeStates: { 'shelf-flat': 'shelf' }, note: '같은 그릇을 선반으로(7 → 5줄 · 숨음 검은물 의병 · 남강 임시정부)' },
  { id: 'shelf-chain-open', store: 'shelf-chain', from: 200, to: 1700, scroll: 0, scopeStates: { 'shelf-chain': 'open' }, note: '등불 하연의 그릇(승계 사슬 + 낱 사슬 넷 = 구성원 아홉)을 펼친 채' },
  { id: 'shelf-chain-shelf', store: 'shelf-chain', from: 200, to: 1700, scroll: 0, shelf: true, scopeStates: { 'shelf-chain': 'shelf' }, note: '같은 그릇을 선반으로(다시 지은 3줄 · 숨음 넷)' },
  { id: 'nest-shelf', store: 'nest-f4', from: 1300, to: 1650, scroll: 0, box: true, shelf: true, scopeStates: { 'jp-era': 'shelf' }, note: '포개짐 규칙 — 바깥 그릇(일본) 선반(6 → 3줄) · 안쪽 상자(전국 시대)는 default로 켬' },
  // 걸음 5(보기 기억 · 결함 ㉡ 고침)에 더함: reopen = 앞 장면(이 태그에서 먼저 찍은 것)을 찍으며 앱이 쓴 기억 폴더의 사본을 대본 없이 다시 열어 찍는다.
  // 원 장면과 그림 바이트 같음 · 앱이 쓴 기억의 viewState.shelvedScopes에 그 그릇 · 기억 filters에 그 그릇 켬(필터 기억이 그릇을 켜는 길 — 결함 ㉡가 나던 길을
  // 정말 지났는지) · 기억의 viewState가 다시 열며 바뀌지 않음을 본다. 원 장면보다 뒤에 둔다(--only로 골라도 이 표의 차례로 찍는다).
  { id: 'fedscope-shelf-reopen', store: 'f4-federation-scope', from: 1140, to: 1660, scroll: 0, shelf: true, reopen: 'fedscope-shelf', note: 'fedscope-shelf의 기억으로 다시 켬 — 선반이 남음(대본 없음)' },
  { id: 'nest-shelf-reopen', store: 'nest-f4', from: 1300, to: 1650, scroll: 0, box: true, shelf: true, reopen: 'nest-shelf', note: 'nest-shelf의 기억으로 다시 켬 — 바깥 그릇 선반 · 안쪽 상자 꺼짐이 남음(대본 없음)' },
  // 검토 고침(과제 7 — 2026-10-25)에 더함: dlcAdd = 그릇 상태를 둔 뒤 넣을 DLC 파일(작업 폴더 기준 · 대본 dlc add — DLC 창과 같은 길 · 일이 끝나기를 기다려 찍음).
  // DLC를 넣고 빼는 길(archive_app `_carryOver` → `_reloadStore`)이 선반 기억을 옮기는지 — 찍은 뒤 대본 기록의 선반 기억 · 켠 변형 열쇠(shelf:<uid>)와
  // 앱이 쓴 기억의 viewState.shelvedScopes · 저장소의 DLC 수(+1)를 본다(아니면 실패). 메이커 미리보기는 DLC를 넣지 못해 --maker에서 건너뛴다.
  { id: 'fedscope-shelf-dlc', store: 'f4-federation-scope', from: 1140, to: 1660, scroll: 0, shelf: true, scopeStates: { 's-fed': 'shelf' }, dlcAdd: ['prototype/fixtures/oracle/f4/f4-crowns.htpack'], note: 'fedscope-shelf에서 DLC(왕관 여섯)를 넣음 — 선반이 남음' },
  // 칸 그림 갈래(걸음 31 ~ 35)에 더함 — 배치 갈래의 시험 자료 f4-legit(문화권 셋 · 트랙 넷) · f4-office4. 해 범위와 내려 보기는 자료에서 골랐다.
  // f4-legit: 하연 · 설령(다듬기 판 lg2-ga 정통성 장면과 같은 해 — 하연 왕국 공동 · 섭정 / 남하연 조정 대립 / 설원 제국 명목 · 주장 · 내각 / 백사 공국 빙원 동맹 소속 명목 /
  // 붉은탑 망명 조정 띠 자체 주장). f4-legit-side: 곁 트랙(다섯 겹 공동 · 섭정이 겹침 · 맞닿은 주장 · 접힌 소속 버들 성시의 두 단 — 상국 버들 왕국을 펼침).
  // f4-legit-body: 몸통 트랙(짧은 몸통 줄 — 앞 지도자 + 지위 · 뒤 지도자 + 내각 + 직위 줄 더(솔 후왕국 재상) · 두 단 + 내각 · 기관이 한 띠에만).
  // f4-office4: 셋째 직위 줄(재상 · 서기) · 빌린 직위 줄 더(갈대 왕국 서기 ← 모래 서원) · 칸 · 소속 정통성.
  // 곁 · 몸통 트랙은 저장소 맨 아래라 내려 보기가 앱의 끝에서 잘린다(걸음 1 바탕에서 side 1000은 끝 가까이 · body 1700은 끝 — 둘 다 곁 · 몸통이 함께 보임).
  // 뒤 걸음이 줄 높이를 바꾸면 끝 자리도 따라 움직인다.
  { id: 'f4-legit', store: 'f4-legit', from: 1000, to: 1200, scroll: 0, note: '정통성 넷 가 다듬은 꼴 — 하연 · 설령(공동 두 단 · 섭정 · 명목 · 주장 · 대립 · 소속 명목 · 띠 주장)' },
  { id: 'f4-legit-side', store: 'f4-legit', from: 990, to: 1210, scroll: 1000, expandHosts: ['o-willow'], note: '곁 트랙 — 다섯 겹 공동 · 섭정 겹침 · 맞닿은 주장 · 접힌 소속(버들 성시)의 두 단' },
  { id: 'f4-legit-body', store: 'f4-legit', from: 990, to: 1190, scroll: 1700, note: '몸통 트랙 — 짧은 몸통 줄 · 솔 후왕국 직위 줄 더 · 두 단 + 내각' },
  { id: 'f4-office4', store: 'f4-office4', from: 440, to: 980, scroll: 0, note: '직위 줄 더 — 셋째 직위 줄 · 빌린 직위 줄 더 · 칸 · 소속 정통성' },
];

/** --scene-file이면 그 파일의 장면 목록(축소 조사 등 — 4단계 걸음 견줌의 장면 표는 그대로). */
const SCENES = args['scene-file'] ? JSON.parse(fs.readFileSync(path.resolve(args['scene-file']), 'utf8')) : BASE_SCENES;
/** 찍은 그림 폴더의 뿌리(태그 폴더가 이 밑에). */
const SHOTS = args.shots ? path.resolve(args.shots) : path.join(results, 'shots');

/** 4단계 이번 차례의 걸음마다 '바뀌어도 되는 장면'(누적 — 걸음 n까지의 것을 모두 합침). c = 그 장면 저장소의 census. 나머지 장면은 바이트 같아야 한다. */
const STEPS = [
  { step: 2, what: '문화권 머리 단 밑 시대 · 주기 줄', may: (c) => c.sphereLines[2] + c.sphereLines[3] > 0 },
  { step: 3, what: '사람 띠', may: (c) => c.sphereLines[1] > 0 },
  { step: 4, what: '실 · 뿔 매듭 · 사람 띠로 그린 사람의 이음줄 걷기', may: (c) => c.sphereLines[1] > 0 },
  // 머리 단 고정은 문화권 줄(갈래 1 · 2 · 3)이 있는 저장소의 내려 본 장면만 허용 — 새 값 없는 저장소(east-asia · 판 3)가 바뀌면 전체 제약에 걸리므로 걸음 5가 정해 알린다.
  { step: 5, what: '공통 줄의 같은 시대 구분 가림 · 머리 단 고정(문화권 줄이 있는 저장소의 내려 본 장면)', may: (c, s) => c.sphereLines[2] > 0 || (s.scroll > 0 && c.sphereLines[1] + c.sphereLines[2] + c.sphereLines[3] > 0) },
  { step: 6, what: '사람 창(누를 때만 — 멈춘 장면은 그대로)', may: () => false },
  { step: 7, what: '빌린 지도자 · 내각 층과 머리 줄 출처 글', may: (c) => c.style27 + c.items[54] > 0 },
  { step: 8, what: '실권 밑줄', may: (c) => c.items[56] > 0 },
  { step: 9, what: '선반 길 판단(그림 없음)', may: () => false },
  // 감독 고름 차례(차례 걸음 10 ~ 16 · 찍기 태그 g10 ~ g16): 앞 걸음 태그와 견주므로 걸음 하나의 몫만(누적 아님 — mayDiffer).
  // off = 이 걸음의 그림을 끄는 스위치(앱 --paint-off) · old = 새 값이 없는 옛 저장소(판 3 포함)도 바꾸는 걸음 — 그 판정은 끈 찍기의 바이트 같음.
  { step: 10, what: '준비 — 그림 스위치 · 찍기 틀 · 새 시험 자료와 장면(그림 없음)', may: () => false },
  { step: 11, what: '먹 여섯(G5 #8 먹 가 — 모든 장면)', off: 'ink', old: true, may: () => true },
  { step: 12, what: 'form 종류 갈래로 꼬리표 끝 · 대립 점선 테(G6 가 · 과제 2)', off: 'tag', may: (c) => c.tagEnd + c.rival > 0 },
  { step: 13, what: '서고 흠 셋 고침(G5 #8 흠 라 — 흠을 보는 장면)', off: 'flaw', may: (c, s) => !!s.flaw },
  { step: 14, what: '흰 사슬 쌓기(G5 #9 나 — 왕조 · 지위 줄이 있는 장면)', off: 'chain', old: true, may: (c) => c.dynasty + c.rank > 0 },
  { step: 15, what: '흰 사슬 그림 · 실 · 왼쪽 칸 사슬 이름(G5 #9 나)', off: 'chain', old: true, may: (c) => c.dynasty + c.rank > 0 },
  { step: 16, what: '칸 종류 9 되돌릴 자리 표시 · 넓은 검사(그림 없음)', may: () => false },
  // 감독 지적(2026-10-25 "등불왕국 명목기 부분에 가로선도 흐릿하게라도") — 가지 remake-4-rows. 칸이 있는 띠의 층 위아래에 먹 가로선(감독 결정 꼴 b 기본 · 가로 · 세로 구분선 맞닿음)이라 칸이 있는
  // 모든 장면(옛 저장소 포함)이 바뀐다. 판정은 끈 찍기(--paint-off=rows 또는 --paint-rows=off)가 앞 태그와 바이트 같음.
  { step: 17, what: '칸 층 사이 흐린 가로선 · 구분선 맞닿음(감독 지적 · 결정 2026-10-25 — 꼴 b 기본 · a · c)', off: 'rows', old: true, may: () => true },
  // 칸 그림 갈래(가지 remake-4-cells · 찍기 태그 c1 ~ c6 · 끈 찍기 c?-off): 배치 갈래가 실은 새 값(띠 sub · look 30 · 줄 fig_wide 21 ~ 30 · 칸 종류 1의 lane ·
  // 종류 9 · 구역 57 · 58)을 그림판이 읽는다. 감독 고름 차례와 같은 규칙 — 앞 걸음 태그와 견주고(그 걸음 하나의 몫) 끈 찍기가 앞 걸음과 모든 장면에서 바이트 같음.
  // 새 값이 없는 옛 저장소(판 3)는 어느 걸음에서도 바뀌면 안 된다(old 없음).
  { step: 31, what: '칸 그림 준비 — 스위치 셋 · 새 값 읽개 · sub 나르기 · 찍기 틀(그림 없음)', may: () => false },
  { step: 32, what: '두 단 지도자 층 — 쌓기 · 띠마다 제 단 · 조각 그림(두 단 띠가 있는 장면)', off: 'legit', may: (c) => c.lanes2 > 0 },
  { step: 33, what: '정통성 무늬 — 칸 · 띠 · 소속 구간(구역 57 · 58 · 띠 주장이 있는 장면)', off: 'legit', may: (c) => c.items[57] + c.items[58] + c.claim > 0 },
  { step: 34, what: 'G7 직위 줄 더 층 · 빌린 층 · 왼쪽 칸 줄 이름(직위 줄 더 띠가 있는 장면)', off: 'office', may: (c) => c.office + c.kind9 > 0 },
  { step: 35, what: '띠마다 제 몸통 높이 — 줄어드는 층(줄어드는 층 줄이 있는 장면)', off: 'body', may: (c) => c.shrink > 0 },
  // 과제 7(상자 · 선반 — 그릇 그림 갈래 remake-4-scopes): 다른 갈래와 번호가 부딪치지 않게 70번대 · 앞 걸음 태그와 견줌(감독 고름 차례와 같은 길).
  // 기준은 바탕 실행본의 태그 sc0. 72 = 과제 7 걸음 2 · 73 = 걸음 3(이 갈래의 걸음 3 ~ 4) · 74 = 이 갈래의 걸음 5.
  { step: 70, what: '준비 — 저장소 · 장면 꼴(scopeStates) · 기준 찍기(그림 없음)', may: () => false },
  { step: 72, what: '상자 — 안쪽 그릇(깊이 1 이상)의 펼친 상자 · 접힌 상자 한 줄(box 장면)', may: (c, s) => !!s.box },
  { step: 73, what: '선반 — 넷째 상태 · 엔진 선반 변형 · 폴더 발 작은 꼬리표 줄 19(shelf 장면)', may: (c, s) => !!s.shelf },
  { step: 74, what: '보기 기억 shelvedScopes · 차림표 · 다시 켜도 남음(reopen 장면)', may: (c, s) => !!s.reopen },
  { step: 75, what: '검토 고침 — 카드는 그 줄의 사건만 · 누름 번호 가름 · 필터 첫 값은 보기 조건에서 · DLC를 넣어도 선반(새 장면 하나 · 그림 없음)', may: () => false },
  // 과제 8 갈래(가지 remake-4-folders · 바탕 실행본 f0 · 찍기 태그 f0 ~): 번호를 80번대로 잡아 같은 때 도는 두 그림 갈래(remake-4-cells · remake-4-scopes)의 걸음 번호와
  // 겹치지 않게 함. 감독 고름 차례처럼 그 걸음 하나의 몫만(mayDiffer — PICK_FROM 뒤) · 판정은 끈 찍기(--paint-off=<스위치>)가 바탕(f0)과 바이트 같음.
  // 81: 옛 저장소의 소속 펼치기도 폴더가 되므로 old · 바뀌는 장면은 상국을 펼친 장면뿐(접힌 상국은 그대로).
  { step: 81, what: '소속 펼치기를 폴더로(과제 8 걸음 2 — 상국 띠가 첫 줄 · 매다는 실 · 가로대 · 그릇 안이면 상자 · 소속선 걷기)', off: 'folder', old: true, may: (c, s) => !!s.expandHosts?.length },
  // 82: 그릇 갈래 띠(나라 · 동군연합 · 동맹 — form 종류 15 ~ 17)가 있는 저장소. 펼친 상국 첫 줄의 제 꼬리표는 81의 폴더 위에 서므로 그 장면은 81의 몫과 함께 본다.
  { step: 82, what: '그릇 노릇 객체의 꼴(과제 8 걸음 1 — 첫 줄 제 꼬리표 · 동맹과 구성원 없는 그릇의 납작한 뚜껑 · 동군연합 폴더 먹)', off: 'lid', may: (c) => c.containerBands > 0 },
  // 83: 날짜 칸 간지 줄을 켠 장면에서 같은 주기의 문화권 주기 줄(갈래 3)이 있는 저장소만. 문화권을 접은 장면(foldSpheres — f4-sphere-ganji-fold는 같은 주기의
  // 등불 분지권을 접음)은 날짜 칸 줄이 돌아와 바탕과 바이트 같아야 한다('접으면 돌려놓는다'를 지킴 — 같은 주기의 문화권이 여럿인 자료가 생기면 다시 가름).
  { step: 83, what: '육십갑자는 머리 단 주기 줄만(같은 주기를 펼친 문화권 머리 단이 그리면 날짜 칸 간지 줄을 가림 — 감독 결정 2026-10-25)', off: 'cycle',
    may: (c, s) => !!s.ganji && !s.foldSpheres?.length && c.sphereLines[3] > 0 },
  // 이어 주는 선 갈래(가지 line-routing — 스위치 route · 1배 후보 cross는 --paint-on으로만): 다른 그림 갈래와 번호가 겹치지 않게 90번대 · 앞 걸음 태그와 견줌.
  // 옛 저장소(판 3 포함)의 승계선 · 소속선도 새 길로 그리므로 old · 바뀌는 장면은 관계선이 있는 장면 전부라 가르지 않음 — 판정은 끈 찍기(--paint-off=route)가 앞 태그와 바이트 같음.
  // 끄면 짝 꼬리표(구역 60) · 띠 위 조각의 바탕 섞기(합침 3a862e9) · 그릇 펼친 장면의 선대 · 후대 줄 바로잡음도 함께 꺼진다(4단계 마지막 합치기 검토 고침).
  { step: 91, what: '이어 주는 선의 새 길(앞 나라 끝에서 나오기 · 굴 문 · 이음매 눈금 · 같은 줄 ⊓ · 꼬리 내림 · 트랙 건넘 짝 꼬리표 — 명세 04 3-4 · 3-6 · 3-9)', off: 'route', old: true, may: () => true },
  // 과제 8 갈래의 끝 증명(차례 걸음 6 · 태그 f6): 걸음 81 ~ 83을 모두 담은 실행본으로 f0과 같은 장면 열여섯을 찍어 --step 없이 f0과 견주고
  // (다른 장면 = 위 셋의 may를 합친 일곱 · 나머지 아홉은 바이트 같음 — 계획 4단계 과제 8 걸음 1 덧글의 찍기 표), 끈 찍기
  // `--tag=f6-off --paint-off=folder,lid,cycle --compare=f0`이 열여섯 모두 바이트 같음을 본다.
];
/** 감독 고름 차례의 첫 걸음 — 이 걸음부터는 앞 걸음 태그와 견준다(누적하지 않음 — 과제 7의 70번대도). */
const PICK_FROM = 10;

const pick = (list, key = 'id') => {
  const only = (args.only || '').split(',').map(s => s.trim()).filter(Boolean);
  for (const n of only) if (!list.some(x => x[key] === n)) die(`모르는 장면 ${n} (${list.map(x => x[key]).join(' · ')})`);
  return list.filter(x => !only.length || only.includes(x[key]));
};
const storeDir = name => path.join(results, 'stores', name);
const storeDb = name => path.join(storeDir(name), 'archive.db');
const sha12 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 12);

/** 해 → 1970년 기준 분. compare-shots.mjs의 minute(y)와 같은 셈(내보내기 scripts/export/base.mjs와 같은 투영). */
function minute(y) {
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}

// ---- 저장소 ----

function tool() {
  const names = process.platform === 'win32' ? ['archive-tool.exe'] : ['archive-tool'];
  const found = [process.env.HT_ARCHIVE_TOOL || '', ...names.map(n => path.join(prototype, 'engine', 'target', 'release', n))].find(f => f && fs.existsSync(f));
  if (!found) die('엔진 도구(archive-tool)가 없습니다 — prototype/engine에서 cargo build --locked --release.');
  return found;
}

function buildStores() {
  if (!fs.existsSync(CALENDAR)) die(`달력 표가 없습니다: ${CALENDAR} — node prototype/scripts/warm-calendar.mjs로 뜨거나 main 작업 폴더의 같은 파일을 복사하세요.`);
  const exe = tool();
  const listFile = path.join(results, 'stores', '목록.json');
  const list = (() => { try { return JSON.parse(fs.readFileSync(listFile, 'utf8')); } catch { return {}; } })();
  for (const [name, s] of Object.entries(STORES)) {
    const db = storeDb(name);
    if (fs.existsSync(db) && !('rebuild' in args)) { console.log(`있음 ${name} — 그대로 씀(${path.relative(root, db)})`); continue; }
    fs.rmSync(storeDir(name), { recursive: true, force: true });
    fs.mkdirSync(storeDir(name), { recursive: true });
    const t0 = Date.now();
    if (s.copy) {
      const from = path.join(RELEASE_DATA, s.copy);
      if (!fs.existsSync(path.join(from, 'archive.db'))) die(`판 3 저장소가 없습니다: ${from}`);
      fs.cpSync(from, storeDir(name), { recursive: true }); // archive.db와 옆 DLC/(끈 DLC 목록 hidden.json이 화면을 바꿀 수 있어 함께)
      list[name] = { copy: from, sha: sha12(db), note: s.note };
    } else {
      const files = s.files.map(f => path.join(root, f));
      if (s.f4check) for (const f of s.files) f4Check(f);
      const r = spawnSync(exe, ['build', db, ...files, `--now=${NOW}`, `--calendar=${CALENDAR}`], { encoding: 'utf8', maxBuffer: 1 << 26 });
      if (r.status !== 0) die(`짓기 실패 ${name}: ${(r.stderr || r.stdout || r.error || '').toString().trim().split('\n').slice(-5).join('\n')}`);
      list[name] = { files: s.files, inputs: s.files.map(f => sha12(path.join(root, f))), now: NOW, tool: sha12(exe), sha: sha12(db), note: s.note };
    }
    console.log(`지음 ${name} — ${path.relative(root, db)} · ${(fs.statSync(db).size / 1048576).toFixed(1)}MB · ${((Date.now() - t0) / 1000).toFixed(1)}초`);
  }
  fs.writeFileSync(listFile, JSON.stringify(list, null, 1) + '\n');
}

/** 이 도구가 만든 형식 4 시험 자료(STORES의 f4check)를 짓기 전에 본다: 형식 4 파일이고, 다리(HT.F4.down)의 내림 알림 · 정규화(HT.normalizePack)의
 *  오류 · 경고가 모두 0(scripts/check-format4.mjs ⑨가 가상 팩에 보는 것과 같은 길 — 그쪽은 기대값과 견주고, 여기는 0이어야 함). */
function f4Check(rel) {
  const raw = JSON.parse(fs.readFileSync(path.join(root, rel), 'utf8'));
  const HT = core(), notes = [];
  if (Number(raw.formatVersion) !== HT.F4.VERSION) die(`${rel}: 형식 4 파일이 아닙니다(formatVersion ${raw.formatVersion})`);
  HT.F4.down(JSON.parse(JSON.stringify(raw)), m => notes.push(String(m)));
  const r = HT.normalizePack(raw);
  const bad = [...notes.map(m => `내림 알림: ${m}`), ...r.errors.map(e => `오류: ${e.msg}`), ...r.warnings.map(w => `경고: ${w.msg}`)];
  if (!r.pack || bad.length) die(`${rel}: 형식 4 검사 ${bad.length}건\n  ${bad.join('\n  ')}`);
  console.log(`형식 4 검사 ${rel} — 객체 ${raw.objects.length} · 알림 · 오류 · 경고 0`);
}

// ---- census ----

async function sqlite() {
  const realWarn = process.emitWarning; // node:sqlite(실험 기능)의 경고 한 줄을 끈다 — build-check.mjs와 같게
  process.emitWarning = (w, ...rest) => (String(w).includes('SQLite') ? undefined : realWarn.call(process, w, ...rest));
  return (await import('node:sqlite')).DatabaseSync;
}

/** 저장소 하나의 새 값 수. 옛 저장소(판 3)는 열 · 표가 없으면 0. */
function countStore(DatabaseSync, db) {
  const d = new DatabaseSync(db, { readOnly: true });
  try {
    const hasTable = t => !!d.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(t);
    const hasCol = (t, c) => !!d.prepare(`SELECT 1 FROM pragma_table_info('${t}') WHERE name=?`).get(c);
    const n = (sql, ...p) => Number(Object.values(d.prepare(sql).get(...p) || { n: 0 })[0] || 0);
    const by = (sql) => Object.fromEntries(d.prepare(sql).all().map(r => [Number(r.k), Number(r.n)]));
    const lines = hasTable('sphere_lines') ? by('SELECT kind k, count(*) n FROM sphere_lines GROUP BY kind') : {};
    const items = by('SELECT section k, count(*) n FROM items WHERE section BETWEEN 54 AND 58 GROUP BY section');
    const hasForm = hasCol('periods', 'form');
    /** 띠 조건 [where]에 드는 띠의 수(uid로 셈 — 변형 줄의 같은 띠를 두 번 세지 않게 · uid가 빈 옛 띠는 번호로). */
    const bands = where => n(`SELECT count(DISTINCT CASE WHEN uid<>'' THEN uid ELSE id END) FROM periods WHERE ${where}`);
    /** 칸 종류 [kind]의 칸이 든 띠의 수(uid로 셈 — 변형 줄의 같은 띠를 두 번 세지 않게 · uid가 빈 옛 띠는 번호로). */
    const bandsWith = kind => n(`SELECT count(DISTINCT CASE WHEN p.uid<>'' THEN p.uid ELSE p.id END) FROM cells c JOIN periods p ON p.id=c.period WHERE (c.kind & 255)=${kind}`);
    return {
      schema: d.prepare("SELECT value FROM meta WHERE key='schema'").get()?.value ?? '?',
      tracks: n('SELECT count(*) FROM tracks'),
      spheres: hasCol('tracks', 'sphere') ? n("SELECT count(DISTINCT sphere) FROM tracks WHERE sphere<>''") : 0,
      form: hasForm ? n('SELECT count(*) FROM periods WHERE form<>0') : 0,
      sphereLines: { 1: lines[1] || 0, 2: lines[2] || 0, 3: lines[3] || 0 },
      kind9: n('SELECT count(*) FROM cells WHERE (kind & 255)=9'),
      style27: n('SELECT count(*) FROM cells WHERE (kind & 255) IN (1,2,9) AND (style & 134217728)<>0'),
      items: { 54: items[54] || 0, 55: items[55] || 0, 56: items[56] || 0, 57: items[57] || 0, 58: items[58] || 0 },
      xTitles: n(`SELECT count(*) FROM entities WHERE kind='figure' AND json LIKE '%"x_titles"%'`),
      // 감독 고름 차례(걸음 12 · 14 · 15)의 몫:
      // 꼬리표 끝이 옛 짐작(look — paint/bands.dart TagLook)과 갈리는 띠 = form 종류가 교단 · 기사단 · 회사 · 직위(번호 9 ~ 12 · 비트 값 + 1 = 10 ~ 13 — 영토 밖 갈래인데
      // 옛 종류는 조직체라 모따기로 짐작함). 다른 종류는 옛 종류에서 HT.F4.typeOfKind로 되살린 것과 같은 갈래라 꼬리표 끝이 옛 짐작과 같다.
      tagEnd: hasForm ? n('SELECT count(*) FROM periods WHERE (form & 31) BETWEEN 10 AND 13') : 0,
      // 대립 띠 = form 10 ~ 12비트가 2(정통성 '대립' 번호 1 + 1).
      rival: hasForm ? n('SELECT count(*) FROM periods WHERE ((form >> 10) & 7)=2') : 0,
      // 왕조 줄 · 지위 줄 = 왕조 칸(종류 0) · 지위 칸(종류 5)이 든 띠(흰 사슬로 옮길 줄) — 옛 저장소에도 있다.
      dynasty: bandsWith(0),
      rank: bandsWith(5),
      // 과제 8 갈래(걸음 82)의 몫: 그릇 갈래 띠 = form 종류가 나라 · 동군연합 · 동맹(번호 15 ~ 17 · 비트 값 + 1 = 16 ~ 18 — 제 줄의 띠로 서는 그릇).
      containerBands: hasForm ? n('SELECT count(*) FROM periods WHERE (form & 31) BETWEEN 16 AND 18') : 0,
      // 과제 7(상자 · 선반)의 몫: 선반 변형(kind 6 · 열쇠 shelf:<그릇 uid>) 수 · 포개진 그릇 수(엔진이 layout 답에 싣는 within이 빈 목록이 아닌 그릇 변형).
      shelf: hasTable('variants') ? n('SELECT count(*) FROM variants WHERE kind=6') : 0,
      nested: nestedScopes(d, hasTable),
      // 칸 그림 갈래(걸음 31 ~ 35)의 몫 — 배치 갈래가 실은 새 비트(계약 1-1 덧붙임 · 판 3 저장소는 모두 0):
      // 두 단 띠 = 띠 sub 22 ~ 23(지도자 층 단 수 − 1) > 0 · 직위 줄 더 띠 = 띠 look 30 · 줄어드는 층 줄 = 줄 fig_wide 28 ~ 30 > 0(비트 3 ~ 5가 선 줄만) ·
      // 띠 주장 = form 10 ~ 12비트가 6(정통성 '주장' 번호 5 + 1). 구역 57 · 58은 위 items.
      lanes2: hasCol('periods', 'sub') ? bands('((sub >> 22) & 3) > 0') : 0,
      office: hasCol('periods', 'look') ? bands('((look >> 30) & 1) = 1') : 0,
      shrink: n('SELECT count(*) FROM rows WHERE ((fig_wide >> 3) & 7) <> 0 AND ((fig_wide >> 28) & 7) > 0'),
      claim: hasForm ? bands('((form >> 10) & 7) = 6') : 0,
    };
  } finally {
    d.close();
  }
}

/** 포개진 그릇 변형의 수 — 엔진(engine/src/variant.rs의 within 셈)과 같은 길: 그릇 변형(kind 2)마다 묶음 줄(variant_groups.rows)을 모아,
 *  같은 트랙에서 제 줄을 모두 품고 줄이 더 많은 다른 그릇 변형이 하나라도 있으면 포개진 것으로 센다(옛 저장소 — 표가 없으면 0). */
function nestedScopes(d, hasTable) {
  if (!hasTable('variants') || !hasTable('variant_groups')) return 0;
  const scopes = new Map();
  for (const r of d.prepare('SELECT v.id, v.track, g.rows FROM variants v JOIN variant_groups g ON g.variant=v.id WHERE v.kind=2 ORDER BY g.id').all()) {
    const s = scopes.get(r.id) || { track: Number(r.track), rows: new Set() };
    for (const row of (() => { try { return JSON.parse(r.rows); } catch { return []; } })()) s.rows.add(Number(row));
    scopes.set(r.id, s);
  }
  const list = [...scopes.entries()];
  return list.filter(([id, a]) => list.some(([id2, b]) => id2 !== id && b.track === a.track && b.rows.size > a.rows.size && [...a.rows].every(x => b.rows.has(x)))).length;
}

async function census({ quiet = false } = {}) {
  const DatabaseSync = await sqlite();
  const out = {};
  for (const name of Object.keys(STORES)) {
    if (!fs.existsSync(storeDb(name))) { if (!quiet) console.log(`없음 ${name} — 먼저 --stores`); continue; }
    out[name] = countStore(DatabaseSync, storeDb(name));
  }
  if (quiet) return out;
  const row = (cells) => '| ' + cells.join(' | ') + ' |';
  const head = ['저장소', '판', '트랙', '문화권', '띠 form≠0', '사람 띠(1)', '문화권 시대(2)', '주기 줄(3)', '칸 종류 9', '27비트 칸', '구역 54', '55', '56', 'x_titles 인물',
    '꼬리표 끝 갈림', '대립 띠', '왕조 줄', '지위 줄', '그릇 갈래 띠', '선반 변형', '포개진 그릇', '두 단 띠', '직위 줄 더 띠', '줄어드는 층 줄', '구역 57', '58', '띠 주장'];
  console.log(row(head));
  console.log(row(Array(head.length).fill('---')));
  for (const [name, c] of Object.entries(out)) {
    console.log(row([name, c.schema, c.tracks, c.spheres, c.form, c.sphereLines[1], c.sphereLines[2], c.sphereLines[3], c.kind9, c.style27, c.items[54], c.items[55], c.items[56], c.xTitles,
      c.tagEnd, c.rival, c.dynasty, c.rank, c.containerBands, c.shelf, c.nested, c.lanes2, c.office, c.shrink, c.items[57], c.items[58], c.claim]));
  }
  console.log('\n걸음마다 바뀌어도 되는 장면(걸음 2 ~ 9는 누적 · 4단계 전과 견줌 / 걸음 10 ~ 16 · 17(구분선) · 31 ~ 35(칸 그림) · 70 ~ 75(과제 7) · 81 ~ 83(과제 8) · 91(이어 주는 선)은 그 걸음만 · 앞 걸음 태그와 견줌 — 나머지는 바이트 같아야 함):');
  const plan = {};
  for (const st of STEPS) {
    const may = SCENES.filter(s => out[s.store] && mayDiffer(out[s.store], s, st.step)).map(s => s.id);
    const same = SCENES.filter(s => out[s.store] && !may.includes(s.id)).map(s => s.id);
    plan[st.step] = { what: st.what, may, same, ...(st.off ? { off: st.off } : null), ...(st.old ? { old: true } : null) };
    const proof = st.off ? ` · 끈 찍기 --paint-off=${st.off}는 모든 장면이 앞 걸음과 같아야 함${st.old ? '(옛 저장소도 바뀌는 걸음)' : ''}` : '';
    console.log(`  걸음 ${st.step}(${st.what}): 바뀌어도 됨 ${may.join(' · ') || '없음'} / 같아야 함 ${same.join(' · ') || '없음'}${proof}`);
  }
  fs.mkdirSync(results, { recursive: true });
  fs.writeFileSync(path.join(results, 'census.json'), JSON.stringify({ stores: out, steps: plan }, null, 1) + '\n');
  console.log(`저장: ${path.relative(root, path.join(results, 'census.json'))}`);
  return out;
}

/** 걸음 [step]까지(누적) 그 장면이 바뀌어도 되는가. 옛 저장소(판 3 · 3.1 — 새 값이 하나도 없음)는 어느 걸음에서도 바뀌면 안 된다.
 *  감독 고름 차례(걸음 10 ~)는 앞 걸음 태그와 견주므로 그 걸음 하나의 몫만 — 옛 저장소도 바꾸는 걸음(old)이면 판 3 저장소도 바뀌어도 된다. */
const mayDiffer = (c, scene, step) => {
  if (step >= PICK_FROM) {
    const st = STEPS.find(x => x.step === step);
    return !!st && (st.old || Number(c.schema) >= 4) && st.may(c, scene);
  }
  return Number(c.schema) >= 4 && STEPS.some(st => st.step <= step && st.may(c, scene));
};

// ---- 찍기 ----

function exePath() {
  const a = args.app || '';
  if (!a) return path.join(prototype, 'app', 'build', 'windows', 'x64', 'runner', 'Release', 'archive_prototype.exe');
  if (a.endsWith('.exe')) return path.resolve(a);
  return path.join(results, 'app', a, 'archive_prototype.exe');
}

function keepApp(name) {
  const from = path.dirname(exePath());
  const to = path.join(results, 'app', name);
  if (fs.existsSync(to)) die(`이미 있습니다(덮어쓰지 않음): ${to}`);
  if (!fs.existsSync(path.join(from, 'archive_prototype.exe'))) die(`실행본이 없습니다: ${from}`);
  fs.cpSync(from, to, { recursive: true });
  console.log(`실행본을 남김: ${path.relative(root, to)} · 앱 코드 ${sha12(path.join(to, 'data', 'app.so'))}`);
}

/** 감독 고름 그림의 스위치 낱말(앱 scene/paint/paint_pick.dart `PaintPick.names` — 합친 차례 · 과제 8 갈래의 폴더 · 뚜껑 · 주기는 걸음 81 ~ 83 ·
 *  칸 그림 갈래의 정통성 · 직위 줄 더 · 몸통은 걸음 32 ~ 35 · 이어 주는 선 갈래의 새 길(route)은 걸음 91 · 구분선 갈래의 칸 층 가로선은 걸음 17) · all. */
const PAINT_WORDS = ['ink', 'tag', 'flaw', 'chain', 'folder', 'lid', 'cycle', 'legit', 'office', 'body', 'route', 'rows'];

/** 칸 층 사이 가로선의 꼴(앱 `FloorRule` — `--paint-rows`). */
const ROW_RULES = ['a', 'b', 'c', 'off'];

/** `--paint-off`의 값 → 앱에 넘길 꼴(낱말 차례대로 · all이면 'all') · 없으면 ''. 모르는 낱말 · 빈 값은 멈춤(증명 찍기가 조용히 켠 채로 찍지 않게). */
function paintOffValue() {
  if (!('paint-off' in args)) return '';
  const words = String(args['paint-off']).split(',').map(w => w.trim().toLowerCase()).filter(Boolean);
  const unknown = words.filter(w => w !== 'all' && !PAINT_WORDS.includes(w));
  if (!words.length || unknown.length) die(`--paint-off=${PAINT_WORDS.join(',')}|all 가운데서 적으세요${unknown.length ? ` (모르는 낱말 ${unknown.join(' · ')})` : ''}`);
  return words.includes('all') ? 'all' : PAINT_WORDS.filter(w => words.includes(w)).join(',');
}

/** `--paint-rows`의 값(a · b · c · off) · 없으면 ''(앱 기본 b — 감독 결정 2026-10-25). 모르는 값 · 빈 값은 멈춤. */
function paintRowsValue() {
  if (!('paint-rows' in args)) return '';
  const v = String(args['paint-rows']).trim().toLowerCase();
  if (!ROW_RULES.includes(v)) die(`--paint-rows=${ROW_RULES.join('|')} 가운데 하나를 적으세요${v ? ` (모르는 값 ${v})` : ''}`);
  return v;
}

/** 1배 후보(앱 PaintPick.candidates — 기본 끔 · `--paint-on`으로만 켬): cross = 굴 문 대신 건넘 토막(이어 주는 선 걸음 5 · 명세 04 3-9). */
const PAINT_ON_WORDS = ['cross'];

/** `--paint-on`의 값 → 앱에 넘길 꼴(낱말 차례대로) · 없으면 ''. 모르는 낱말 · 빈 값은 멈춤. */
function paintOnValue() {
  if (!('paint-on' in args)) return '';
  const words = String(args['paint-on']).split(',').map(w => w.trim().toLowerCase()).filter(Boolean);
  const unknown = words.filter(w => !PAINT_ON_WORDS.includes(w));
  if (!words.length || unknown.length) die(`--paint-on=${PAINT_ON_WORDS.join(',')} 가운데서 적으세요${unknown.length ? ` (모르는 낱말 ${unknown.join(' · ')})` : ''}`);
  return PAINT_ON_WORDS.filter(w => words.includes(w)).join(',');
}

/** 장면의 접을 그릇(foldScopes — 객체 id나 uid) → 그 저장소의 변형(kind 2 `scope:<uid>`) · 트랙 · 가지 열쇠([{ uid, keys: ['<트랙 id>|__scope:<uid>'] }]).
 *  앱의 보기 상태 열쇠(scene/view_state.dart variantGroupKey)는 `<트랙 id>|<가지 key>`이고 트랙 id는 저장소의 tracks.id 그대로다. */
function scopeFolds(DatabaseSync, scene) {
  if (!scene.foldScopes?.length) return [];
  const d = new DatabaseSync(storeDb(scene.store), { readOnly: true });
  try {
    return scene.foldScopes.map(ref => {
      const v = d.prepare("SELECT id, uid, track FROM variants WHERE kind=2 AND (uid=? OR uid LIKE '%/' || ?)").all(ref, ref);
      if (v.length !== 1) die(`${scene.id}: 접을 그릇 "${ref}"를 저장소 ${scene.store}의 변형에서 ${v.length ? '하나로 가리지' : '찾지'} 못했습니다`);
      const groups = d.prepare('SELECT key FROM variant_groups WHERE variant=? ORDER BY id').all(v[0].id);
      if (!groups.length) die(`${scene.id}: 그릇 "${ref}"의 가지가 없습니다`);
      return { uid: v[0].uid, keys: groups.map(g => `${Number(v[0].track)}|${g.key}`) };
    });
  } finally {
    d.close();
  }
}

/** 그릇 상태의 낱말(앱 ScopeState의 이름 — 대본 명령 scopeState의 arg). 'shelf'는 앱이 선반 상태를 알게 되는 과제 7 걸음 3부터 뜻을 가진다. */
const SCOPE_STATES = ['open', 'shelf', 'closed'];

/** 장면의 그릇 상태(scopeStates — {객체 id나 uid: 'open'|'shelf'|'closed'}) → [{ ref, uid, state, keys }] — 적은 차례대로.
 *  펼침 · 접음은 그 저장소의 그릇 변형(kind 2 `scope:<uid>`)이 있어야 하고(keys = 그 가지의 접힘 열쇠 `<트랙 id>|<가지 key>` — scopeFolds와 같음),
 *  선반은 선반 변형(kind 6 `shelf:<uid>`)도 있어야 한다(구성원이 shelfKeep 5 이하인 그릇에는 생기지 않는다). */
function scopeStatesOf(DatabaseSync, scene) {
  const entries = Object.entries(scene.scopeStates || {});
  if (!entries.length) return [];
  const d = new DatabaseSync(storeDb(scene.store), { readOnly: true });
  try {
    return entries.map(([ref, state]) => {
      if (!SCOPE_STATES.includes(state)) die(`${scene.id}: 그릇 "${ref}"의 상태 "${state}"를 모릅니다(${SCOPE_STATES.join(' · ')})`);
      const v = d.prepare("SELECT id, uid, track FROM variants WHERE kind=2 AND (uid=? OR uid LIKE '%/' || ?)").all(ref, ref);
      if (v.length !== 1) die(`${scene.id}: 그릇 "${ref}"를 저장소 ${scene.store}의 변형에서 ${v.length ? '하나로 가리지' : '찾지'} 못했습니다`);
      if (state === 'shelf' && !d.prepare('SELECT 1 FROM variants WHERE kind=6 AND uid=?').get(v[0].uid)) die(`${scene.id}: 그릇 "${ref}"(${v[0].uid})에 선반 변형이 없습니다`);
      const keys = d.prepare('SELECT key FROM variant_groups WHERE variant=? ORDER BY id').all(v[0].id).map(g => `${Number(v[0].track)}|${g.key}`);
      return { ref, uid: v[0].uid, state, keys };
    });
  } finally {
    d.close();
  }
}

/** 장면의 펼칠 상국(expandHosts — 객체 id나 uid) → 그 저장소의 띠 번호(periods.id — 앱 보기 상태 expandedHosts의 값) 목록.
 *  그 띠가 상국인 속국 펼치기 변형(variants kind 1)이 있어야 한다. */
function hostBands(DatabaseSync, scene) {
  if (!scene.expandHosts?.length) return [];
  const d = new DatabaseSync(storeDb(scene.store), { readOnly: true });
  try {
    return scene.expandHosts.map(ref => {
      const b = d.prepare("SELECT id FROM periods WHERE uid=? OR uid LIKE '%/' || ?").all(ref, ref);
      if (b.length !== 1) die(`${scene.id}: 펼칠 상국 "${ref}"를 저장소 ${scene.store}의 띠에서 ${b.length ? '하나로 가리지' : '찾지'} 못했습니다`);
      const id = Number(b[0].id);
      if (!d.prepare('SELECT 1 FROM variants WHERE kind=1 AND band=?').get(id)) die(`${scene.id}: "${ref}"(띠 ${id})는 속국 펼치기 변형의 상국이 아닙니다`);
      return id;
    });
  } finally {
    d.close();
  }
}

/** 장면의 접을 문화권(foldSpheres — 문화권 id) → 그대로(차례대로 · 겹침 없이). 그 저장소의 트랙이 그 문화권에 들어 있어야 한다
 *  (앱은 모르는 문화권 id를 기억에서 버리므로 틀린 id면 조용히 모두 펼친 채 찍힘 — 미리 멈춤). 처음 접힘(fold: 'first')과는 함께 쓰지 않는다. */
function sphereFolds(DatabaseSync, scene) {
  if (!scene.foldSpheres?.length) return [];
  if (scene.fold === 'first') die(`${scene.id}: foldSpheres와 fold: 'first'는 함께 쓰지 않습니다`);
  const d = new DatabaseSync(storeDb(scene.store), { readOnly: true });
  try {
    for (const id of scene.foldSpheres) {
      if (!d.prepare('SELECT 1 FROM tracks WHERE sphere=?').get(id)) die(`${scene.id}: 접을 문화권 "${id}"가 저장소 ${scene.store}의 트랙에 없습니다`);
    }
  } finally {
    d.close();
  }
  return [...new Set(scene.foldSpheres)];
}

/** 날짜 칸 간지 줄을 켜는 대본 걸음(장면의 ganji — 필터의 표시 'ganji'). verify_script.dart의 'filters'가 지금 필터에 덮어 쓴다. */
const GANJI_ON = { do: 'filters', json: { show: { ganji: true } } };

async function capture(tag, scenes) {
  const exe = exePath();
  if (!fs.existsSync(exe)) die(`실행본이 없습니다: ${exe} — powershell -File prototype/scripts/dev.ps1 app-build -Junction <이름> -Flutter <flutter.bat>`);
  const paintOff = paintOffValue(), paintRows = paintRowsValue(), paintOn = paintOnValue(); // 틀린 스위치면 폴더를 만들기 전에 멈춤
  const folder = path.join(SHOTS, tag);
  fs.mkdirSync(folder, { recursive: true });
  const appSo = path.join(path.dirname(exe), 'data', 'app.so');
  const app = { exe, code: fs.existsSync(appSo) ? sha12(appSo) : '?', engine: sha12(path.join(path.dirname(exe), 'archive_engine.dll')), paintOff, ...(paintRows ? { paintRows } : null), ...(paintOn ? { paintOn } : null) };
  const infoFile = path.join(folder, '_실행본.json');
  const info = (() => { try { return JSON.parse(fs.readFileSync(infoFile, 'utf8')); } catch { return {}; } })();
  // 한 태그 안의 장면은 같은 실행본 · 같은 스위치로 찍어야 견줌이 뜻을 가진다 — 다르면 알림(덧찍기 · 다시 찍기에서 잘못 고른 실행본을 잡으려고).
  const others = Object.entries(info).filter(([id, x]) => !scenes.some(s => s.id === id) && (x.code !== app.code || x.engine !== app.engine || (x.paintOff || '') !== paintOff || (x.paintRows || '') !== paintRows || (x.paintOn || '') !== paintOn));
  if (others.length) console.log(`알림: 이 태그의 다른 장면 ${others.length}개(${others.map(([id]) => id).join(' · ')})는 다른 실행본이나 스위치로 찍었습니다 — 지금 앱 코드 ${app.code} · 엔진 ${app.engine} · 끔 '${paintOff}' · 가로선 '${paintRows}' · 켬 '${paintOn}'`);
  const DatabaseSync = scenes.some(s => s.foldScopes?.length || s.expandHosts?.length || s.foldSpheres?.length || Object.keys(s.scopeStates || {}).length || s.reopen || s.dlcAdd?.length) ? await sqlite() : null;
  const readJson = file => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; } };
  let bad = 0;
  for (const s of scenes) {
    const png = path.join(folder, `${s.id}.png`);
    if (fs.existsSync(png) && !('overwrite' in args)) { console.error(`${s.id}: 이미 찍음(덮어쓰지 않음 — --overwrite) ${path.relative(root, png)}`); bad++; continue; }
    if (!fs.existsSync(storeDb(s.store))) { console.error(`${s.id}: 저장소가 없습니다 — 먼저 --stores`); bad++; continue; }
    // 다시 켬(reopen — 과제 7 걸음 5): 앞 장면을 이 태그에서 찍으며 앱이 쓴 기억 폴더 — 그 사본을 이 장면의 기억으로 쓴다.
    const reopenFrom = s.reopen ? path.join(folder, '_run', s.reopen, 'memory') : null;
    const origin = s.reopen ? SCENES.find(x => x.id === s.reopen) : null;
    if (s.reopen && (!origin || !fs.existsSync(path.join(reopenFrom, 'ui-state.json')) || !fs.existsSync(path.join(folder, `${s.reopen}.png`)))) {
      console.error(`${s.id}: 앞 장면 ${s.reopen}의 그림 · 기억이 이 태그에 없습니다 — 함께 찍으세요(--only=${s.reopen},${s.id})`);
      bad++;
      continue;
    }
    const run = path.join(folder, '_run', s.id);
    fs.rmSync(run, { recursive: true, force: true });
    fs.mkdirSync(run, { recursive: true });
    // 저장소 사본(앱이 열며 쓰는 것이 있어도 지은 저장소는 그대로) — 옆 DLC/도
    const store = path.join(run, 'store');
    fs.cpSync(storeDir(s.store), store, { recursive: true });
    // 기억 사본: 모든 문화권 펼침(foldedSpheres 빈 목록 — fold: 'first'면 viewState를 적지 않아 처음 접힘 · foldSpheres면 그 문화권만 접음) ·
    // 보던 기간 = 장면의 범위(첫 화면부터 그 범위의 줄 높이로)
    const from = minute(s.from), to = minute(s.to);
    const memory = path.join(run, 'memory');
    fs.mkdirSync(memory, { recursive: true });
    // 펼칠 상국(expandHosts)은 기억 사본의 viewState.expandedHosts(띠 번호)로 — 그릇 켬과 달리 기억을 이을 때 덮어쓰이지 않는다(찍은 뒤 대본 기록으로 확인).
    const hosts = hostBands(DatabaseSync, s);
    const spheres = sphereFolds(DatabaseSync, s);
    const viewState = { ...(s.fold === 'first' ? {} : { foldedSpheres: spheres }), ...(hosts.length ? { expandedHosts: hosts } : {}) };
    // 다시 켬은 앞 장면의 기억 폴더를 통째로 받는다(앱이 그 장면에서 쓴 그대로 — 보던 기간 · 필터 · 보기 상태).
    if (reopenFrom) fs.cpSync(reopenFrom, memory, { recursive: true });
    else fs.writeFileSync(path.join(memory, 'ui-state.json'), JSON.stringify({ version: 1, view: { start: from, end: to }, parts: Object.keys(viewState).length ? { viewState } : {} }));
    const memoryBefore = reopenFrom ? readJson(path.join(memory, 'ui-state.json')) : null;
    // 접을 그릇(foldScopes): 기억 사본의 viewState.foldedGroups(`<트랙 id>|__scope:<uid>`)로 적어 두면 앱이 열 때 지워진다 — 앱 틀(archive_app.dart)이
    // 기억을 이을 때(glue.attachMemory) 필터의 그릇 켬 · 자료의 default 켜기가 보기 상태를 바꾸면 듣개 _onViewState가 **되살리기 전에** 지금 보기 상태를
    // 기억(parts.viewState)에 덮어써, _restoreViewState가 덮어쓴 값(접힘 없음)을 되살린다(2026-10-25 차례 걸음 10에서 확인 — 결함 ㉡).
    // 그래서 그릇 안 오른쪽 클릭의 '접음'과 같은 명령(Cmd.scopeState closed)을 대본 맨 앞에 두고, 찍은 뒤 앱이 쓴 기억의 접힘 열쇠로 정말 접혔는지 본다.
    // ㉡는 과제 7 걸음 5에서 고쳤다(scene/view_memory.dart — 되살리기 전에는 쓰지 않음 · 확인은 reopen 장면). 옛 실행본(sc0 기준)과 같은 길로 찍도록 대본 명령은 그대로 둔다.
    const folds = scopeFolds(DatabaseSync, s);
    // 그릇 상태(scopeStates — foldScopes를 펼침 · 선반 · 접음으로 넓힌 것): 같은 명령(Cmd.scopeState <상태>)을 적은 차례대로 대본 맨 앞에.
    const states = scopeStatesOf(DatabaseSync, s);
    // DLC 넣기(dlcAdd — 과제 7 검토 고침): 그릇 상태를 둔 뒤 넣고(대본 dlc add — 기다리지 않고 거는 명령이라 잠깐 둔 뒤 until idle로 일이 끝나기를 기다림).
    // 넣을 파일은 _run/<장면>/dlc-in/의 사본으로(앱이 원본을 건드리지 않게).
    const dlcFiles = (s.dlcAdd || []).map(f => {
      const to = path.join(run, 'dlc-in', path.basename(f));
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(path.join(root, f), to);
      return to;
    });
    const dlcSteps = dlcFiles.length ? [{ do: 'dlc', add: dlcFiles }, { do: 'wait', ms: 500 }, { do: 'until', what: 'idle', ms: 120000 }] : [];
    // 대본: (장면의 대본 걸음 —) 가라앉힌 뒤 한 장 · 그 뒤 측정기가 2초 더 기다려 '화면-1배.png'를 뜬다(둘이 같으면 그사이 그림이 멎어 있었다)
    const script = path.join(run, 'script.json');
    // 간지 줄 켬(ganji)은 대본 맨 앞 — 그 뒤 걸음(그릇 상태 · 그릇 접음 · DLC 넣기 · 장면의 대본)이 켠 날짜 칸 위에서 돈다.
    const steps = [...(s.ganji ? [GANJI_ON] : []), ...states.map(x => ({ do: 'command', name: 'scopeState', uid: x.uid, arg: x.state })),
      ...folds.map(f => ({ do: 'command', name: 'scopeState', uid: f.uid, arg: 'closed' })), ...dlcSteps, ...(s.script || [])];
    fs.writeFileSync(script, JSON.stringify([...steps, { do: 'wait', ms: 800 }, { do: 'shot', name: '대본' }]));
    const out = path.join(run, 'out');
    const pass = [`--db=${path.join(store, 'archive.db')}`, `--measure=${out}`, '--exit=yes', '--offline=yes', '--capture-only=yes', `--capture-size=${s.size || '1920x1080'}`,
      `--capture-script=${script}`, `--memory-dir=${path.join(run, 'memory-dir')}`, `--capture-memory=${memory}`, `--from=${from}`, `--to=${to}`, `--capture-scroll=${s.scroll || 0}`,
      ...(paintOff ? [`--paint-off=${paintOff}`] : []), ...(paintRows ? [`--paint-rows=${paintRows}`] : []), ...(paintOn ? [`--paint-on=${paintOn}`] : []),
      ...('text' in args ? ['--capture-text=yes'] : []), ...('lines' in args ? ['--capture-lines=yes'] : [])];
    const t0 = Date.now();
    const r = spawnSync(exe, pass, { cwd: path.dirname(exe), encoding: 'utf8', timeout: 180000 });
    fs.writeFileSync(path.join(run, '실행.log'), (r.stdout || '') + (r.stderr || '') + (r.error?.stack || ''));
    const failed = path.join(out, '측정-실패.txt');
    const shot = path.join(out, '화면-1배.png');
    if (r.error || r.status !== 0 || fs.existsSync(failed) || !fs.existsSync(shot)) {
      console.error(`${s.id}: 실제 앱 실행 실패(${r.error?.message || r.status}) — ${path.relative(root, run)}`);
      bad++;
      continue;
    }
    const log = JSON.parse(fs.readFileSync(path.join(out, '검증-기록.json'), 'utf8'));
    const start = JSON.parse(fs.readFileSync(path.join(out, '시작-장면.json'), 'utf8'));
    const errors = log.steps.filter(x => x.error).length, asks = log.ask_failures.length + (start.ask_failures?.length || 0);
    const shotState = log.steps.find(x => x.shot) || {};
    const still = fs.existsSync(path.join(out, '대본.png')) && fs.readFileSync(path.join(out, '대본.png')).equals(fs.readFileSync(shot));
    fs.copyFileSync(shot, png);
    if ('text' in args && fs.existsSync(path.join(out, '글-상자.json'))) fs.copyFileSync(path.join(out, '글-상자.json'), png.replace(/\.png$/, '.text.json'));
    if ('lines' in args && fs.existsSync(path.join(out, '선-감사.json'))) fs.copyFileSync(path.join(out, '선-감사.json'), png.replace(/\.png$/, '.lines.json'));
    // DLC를 넣은 장면: 사본 저장소의 DLC 수(지우기 전에 셈 — [지은 저장소, 찍은 뒤의 사본]).
    const packCount = db => { const d = new DatabaseSync(db, { readOnly: true }); try { return Number(d.prepare('SELECT count(*) n FROM packs').get().n); } finally { d.close(); } };
    const dlcPacks = dlcFiles.length ? [packCount(storeDb(s.store)), packCount(path.join(store, 'archive.db'))] : null;
    fs.rmSync(store, { recursive: true, force: true }); // 사본은 지움 — 기록 · 그림은 남김
    // 접을 그릇이 정말 켠 채 접혔는가 — 그 장면의 켠 그릇(openScopes)과 앱이 쓴 기억의 접힘(parts.viewState.foldedGroups). 아니면 흠 ③을 볼 수 없으므로 실패로 친다.
    const keptView = (() => { try { return JSON.parse(fs.readFileSync(path.join(memory, 'ui-state.json'), 'utf8')).parts?.viewState || {}; } catch { return {}; } })();
    const keptGroups = keptView.foldedGroups || [];
    const notFolded = folds.length > 0 && !folds.every(f => (shotState.openScopes || []).includes(f.uid) && f.keys.every(k => keptGroups.includes(k)));
    const notExpanded = hosts.length > 0 && !hosts.every(h => (shotState.expandedHosts || []).includes(h));
    // 간지 줄(ganji)은 그 장면의 날짜 칸 표시 넷(marks.axis — 간지 · 연호 · 도읍 · 시대 구분)의 첫째로 · 접을 문화권(foldSpheres)은 앱이 쓴 기억의 접힘과 같아야 한다.
    const ganjiOn = shotState.marks?.axis?.[0] === true;
    const keptSpheres = [...(keptView.foldedSpheres || [])].sort();
    const notGanji = !!s.ganji && !ganjiOn;
    const notSphereFolded = spheres.length > 0 && JSON.stringify(keptSpheres) !== JSON.stringify([...spheres].sort());
    // 그릇 상태가 정말 그리 되었는가 — 펼침 = 켜졌고(openScopes) 그 가지가 접히지 않음 · 접음 = 켜졌고 그 가지가 모두 접힘(foldScopes와 같음) ·
    // 선반(과제 7 걸음 4 — 대본 기록의 shelvedScopes · variantKeys) = 켜졌고 접히지 않았고 선반 기억에 들었고 엔진의 선반 변형 shelf:<uid>를 켰음.
    // 펼침은 선반 기억에 없어야 한다(선반 열이 없는 옛 실행본의 기록은 빈 목록으로 읽는다).
    const opened = shotState.openScopes || [], shelved = shotState.shelvedScopes || [], keysOn = shotState.variantKeys || [];
    const unfolded = x => opened.includes(x.uid) && !x.keys.some(k => keptGroups.includes(k));
    const stateMiss = states.filter(x => (x.state === 'open' && !(unfolded(x) && !shelved.includes(x.uid)))
      || (x.state === 'shelf' && !(unfolded(x) && shelved.includes(x.uid) && keysOn.includes(`shelf:${x.uid}`)))
      || (x.state === 'closed' && !(opened.includes(x.uid) && x.keys.every(k => keptGroups.includes(k)))));
    // 다시 켬(과제 7 걸음 5): 앞 장면이 선반에 둔 그릇마다 — 그림 바이트 같음 · 앱이 쓴 기억의 선반 · 필터 기억의 그릇 켬 · 다시 연 앱의 기록(선반 기억 ·
    // 엔진 선반 변형 shelf:<uid>) · 기억의 viewState가 다시 열며 바뀌지 않음(결함 ㉡이면 필터 기억의 그릇 켬이 되살리기 전에 viewState를 덮는다).
    const reopenUids = origin ? scopeStatesOf(DatabaseSync, origin).filter(x => x.state === 'shelf').map(x => x.uid) : [];
    const memoryAfter = s.reopen ? readJson(path.join(memory, 'ui-state.json')) : null;
    const reopenMiss = [];
    if (s.reopen) {
      if (!fs.readFileSync(path.join(folder, `${s.reopen}.png`)).equals(fs.readFileSync(png))) reopenMiss.push(`그림이 ${s.reopen}과 바이트 다름`);
      const kept = memoryAfter?.parts?.viewState?.shelvedScopes || [], on = memoryAfter?.parts?.filters?.scopes || {};
      if (!reopenUids.length) reopenMiss.push(`${s.reopen}에 선반 그릇이 없음`);
      for (const uid of reopenUids) {
        if (!kept.includes(uid)) reopenMiss.push(`기억 viewState.shelvedScopes에 ${uid} 없음`);
        if (on[uid] !== true) reopenMiss.push(`기억 filters.scopes에 ${uid} 켬 없음(필터 기억이 그릇을 켜는 길을 지나지 않음)`);
        if (!shelved.includes(uid) || !keysOn.includes(`shelf:${uid}`)) reopenMiss.push(`다시 연 앱이 ${uid}를 선반으로 열지 않음`);
      }
      if (JSON.stringify(memoryBefore?.parts?.viewState) !== JSON.stringify(memoryAfter?.parts?.viewState)) reopenMiss.push('기억의 viewState가 다시 열며 바뀜');
    }
    // DLC를 넣은 장면(검토 고침): 일이 끝났고 · 저장소에 넣은 만큼 DLC가 늘었고 · 앱이 쓴 기억에 선반이 남았는가(선반 기억 · 켠 변형 열쇠는 위 stateMiss가 본다 —
    // DLC를 넣은 뒤의 대본 기록이라 `_carryOver` → `_reloadStore`가 선반 기억을 옮겼는지가 거기서 갈린다).
    const dlcMiss = [];
    if (dlcFiles.length) {
      if (!log.steps.some(x => x.until === 'idle')) dlcMiss.push('DLC 일이 끝나기를 보지 못함');
      if (dlcPacks[1] !== dlcPacks[0] + dlcFiles.length) dlcMiss.push(`저장소의 DLC ${dlcPacks[0]} → ${dlcPacks[1]}(넣은 파일 ${dlcFiles.length})`);
      const kept = readJson(path.join(memory, 'ui-state.json'))?.parts?.viewState?.shelvedScopes || [];
      for (const x of states.filter(x => x.state === 'shelf')) if (!kept.includes(x.uid)) dlcMiss.push(`기억 viewState.shelvedScopes에 ${x.uid} 없음(DLC를 넣은 뒤)`);
    }
    info[s.id] = { ...app, store: s.store, from: s.from, to: s.to, scroll: s.scroll || 0, ...(s.size ? { size: s.size } : null), view: start.view, folded: shotState.foldedTracks,
      ...(steps.length ? { script: steps, selection: shotState.selection ?? null } : null),
      ...(folds.length || states.length ? { foldedGroups: keptGroups, openScopes: shotState.openScopes ?? null } : null),
      ...(states.length ? { scopeStates: states.map(x => ({ uid: x.uid, state: x.state })), shelvedScopes: shotState.shelvedScopes ?? null, variantKeys: shotState.variantKeys ?? null } : null),
      ...(hosts.length ? { expandedHosts: shotState.expandedHosts ?? null } : null),
      ...(s.ganji ? { ganji: ganjiOn } : null),
      ...(spheres.length ? { foldedSpheres: keptSpheres } : null),
      ...(s.reopen ? { reopen: { from: s.reopen, uids: reopenUids, shelvedScopes: shotState.shelvedScopes ?? null, variantKeys: shotState.variantKeys ?? null,
        memory: { shelvedScopes: memoryAfter?.parts?.viewState?.shelvedScopes ?? null, filtersScopes: memoryAfter?.parts?.filters?.scopes ?? null }, miss: reopenMiss } } : null),
      ...(dlcFiles.length ? { dlc: { add: s.dlcAdd, packs: dlcPacks, miss: dlcMiss } } : null),
      askFailures: asks, scriptErrors: errors, still };
    const warn = [asks && `실패한 조회 ${asks}`, errors && `대본 오류 ${errors}`, !still && '대본 그림과 1배 그림이 다름(그사이 그림이 움직임)',
      notFolded && `그릇이 켠 채 접히지 않음(openScopes ${JSON.stringify(shotState.openScopes || [])} · 접힘 ${JSON.stringify(keptGroups)})`,
      stateMiss.length && `그릇 상태가 되지 않음(${stateMiss.map(x => `${x.uid} ${x.state}`).join(' · ')} — openScopes ${JSON.stringify(opened)} · 접힘 ${JSON.stringify(keptGroups)}`
        + ` · shelvedScopes ${JSON.stringify(shelved)} · variantKeys ${JSON.stringify(keysOn)})`,
      notExpanded && `상국이 펼쳐지지 않음(expandedHosts ${JSON.stringify(shotState.expandedHosts || [])} · 바람 ${JSON.stringify(hosts)})`,
      notGanji && `날짜 칸 간지 줄이 켜지지 않음(marks.axis ${JSON.stringify(shotState.marks?.axis ?? null)})`,
      notSphereFolded && `문화권 접힘이 다름(기억 ${JSON.stringify(keptSpheres)} · 바람 ${JSON.stringify(spheres)})`,
      reopenMiss.length && `다시 켬 실패(${reopenMiss.join(' · ')})`, dlcMiss.length && `DLC 넣기 실패(${dlcMiss.join(' · ')})`, paintOff && `끔 ${paintOff}`,
      paintRows && `가로선 ${paintRows}`, paintOn && `켬 ${paintOn}`].filter(Boolean).join(' · ');
    const shelfOn = states.filter(x => x.state === 'shelf').length;
    const reopenNote = s.reopen && !reopenMiss.length ? ` · 다시 켬 확인(${s.reopen}과 바이트 같음 · 기억 선반 ${reopenUids.join(' · ')} · 필터 켬 · viewState 그대로)` : '';
    const dlcNote = dlcFiles.length && !dlcMiss.length ? ` · DLC 넣음 확인(저장소 DLC ${dlcPacks[0]} → ${dlcPacks[1]} · 넣은 뒤 기록 · 기억에 선반)` : '';
    console.log(`${s.id}: 찍음 ${path.relative(root, png)} · ${((Date.now() - t0) / 1000).toFixed(1)}초${states.length && !stateMiss.length ? ` · 그릇 상태 확인 ${states.length}${shelfOn ? `(선반 ${shelfOn} — ${keysOn.filter(k => k.startsWith('shelf:')).join(' · ')})` : ''}` : ''}${reopenNote}${dlcNote}${warn ? ' · ' + warn : ''}`);
    if (notFolded || notExpanded || notGanji || notSphereFolded || stateMiss.length || reopenMiss.length || dlcMiss.length) bad++;
    if (asks || errors) bad++;
  }
  fs.writeFileSync(infoFile, JSON.stringify(info, null, 1) + '\n');
  return bad;
}

// ---- 견주기 ----

/** PNG(8비트 · RGB/RGBA · 비월 없음 — Flutter가 뜨는 꼴)를 RGBA로 푼다. 다른 꼴이면 null. */
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) return null;
  let pos = 8, width = 0, height = 0, type = 0, depth = 0, interlace = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), kind = buf.toString('latin1', pos + 4, pos + 8), body = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === 'IHDR') { width = body.readUInt32BE(0); height = body.readUInt32BE(4); depth = body[8]; type = body[9]; interlace = body[12]; }
    else if (kind === 'IDAT') idat.push(body);
    else if (kind === 'IEND') break;
    pos += 12 + len;
  }
  const bpp = type === 6 ? 4 : type === 2 ? 3 : 0;
  if (!bpp || depth !== 8 || interlace) return null;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * bpp, out = Buffer.alloc(width * height * 4), prev = Buffer.alloc(stride), line = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = src[i];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      line[i] = v & 255;
    }
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      out[o] = line[x * bpp]; out[o + 1] = line[x * bpp + 1]; out[o + 2] = line[x * bpp + 2]; out[o + 3] = bpp === 4 ? line[x * bpp + 3] : 255;
    }
    line.copy(prev);
  }
  return { width, height, data: out };
}

/** 두 그림의 다른 픽셀 수와 범위(x0,y0,x1,y1). 크기가 다르면 size. */
function pixelDiff(a, b) {
  const A = decodePng(a), B = decodePng(b);
  if (!A || !B) return { note: '풀 수 없는 PNG 꼴' };
  if (A.width !== B.width || A.height !== B.height) return { size: [[A.width, A.height], [B.width, B.height]] };
  let n = 0, x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let i = 0; i < A.data.length; i += 4) {
    if (A.data.readUInt32BE(i) === B.data.readUInt32BE(i)) continue;
    n++;
    const p = i / 4, x = p % A.width, y = (p - x) / A.width;
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  return { pixels: n, box: n ? [x0, y0, x1, y1] : null };
}

async function compare(tag, other, scenes) {
  const step = args.step ? Number(args.step) : 0;
  if (args.step && !STEPS.some(s => s.step === step) && step !== 1) die(`모르는 걸음 ${args.step} (1 · ${STEPS.map(s => s.step).join(' · ')})`);
  const counts = step > 1 ? await census({ quiet: true }) : {};
  const rows = [];
  let bad = 0;
  for (const s of scenes) {
    const a = path.join(SHOTS, tag, `${s.id}.png`), b = path.join(SHOTS, other, `${s.id}.png`);
    const may = step > 1 && counts[s.store] ? mayDiffer(counts[s.store], s, step) : false;
    // 이 태그에는 있고 기준 태그에는 없는 장면(뒤 걸음에 더한 장면 — 예: 과제 7의 '-shelf' 장면은 기준 sc0에 없음)은 '새 장면' — 실패로 치지 않는다.
    if (fs.existsSync(a) && !fs.existsSync(b)) { rows.push({ id: s.id, state: '새 장면', may }); continue; }
    if (!fs.existsSync(a) || !fs.existsSync(b)) { rows.push({ id: s.id, state: '그림 없음', may }); bad++; continue; }
    const A = fs.readFileSync(a), B = fs.readFileSync(b);
    if (A.equals(B)) { rows.push({ id: s.id, state: '같음', may }); continue; }
    const d = pixelDiff(A, B);
    rows.push({ id: s.id, state: '다름', may, ...d });
    if (!may) bad++;
  }
  const st = STEPS.find(x => x.step === step);
  const scope = step >= PICK_FROM ? `걸음 ${step} 하나(앞 걸음 태그와 견줌)에서` : `걸음 ${step}까지`;
  console.log(`\n견줌: ${tag} ↔ ${other}${step > 1 ? ` · ${scope} 바뀌어도 되는 장면은 '허용'${st?.off ? ` · 이 걸음의 끈 찍기는 --paint-off=${st.off}로 모든 장면이 같아야 함` : ''}` : ' · 모든 장면이 같아야 함'}`);
  console.log('| 장면 | 바이트 | 다른 픽셀 | 범위(x0,y0,x1,y1) | 판정 |');
  console.log('| --- | --- | --- | --- | --- |');
  for (const r of rows) {
    const verdict = r.state === '같음' ? '통과' : r.state === '새 장면' ? '새 장면(견줄 기준 없음)' : r.state === '다름' && r.may ? '허용(새 값)' : '실패';
    console.log(`| ${r.id} | ${r.state} | ${r.pixels ?? (r.size ? '크기 다름' : r.note ?? '')} | ${r.box ? r.box.join(',') : ''} | ${verdict} |`);
  }
  const file = path.join(SHOTS, tag, `견줌-${other}${step > 1 ? `-걸음${step}` : ''}.json`);
  fs.writeFileSync(file, JSON.stringify({ tag, other, step, rows }, null, 1) + '\n');
  console.log(`${bad ? `실패 ${bad}` : '모두 통과'} · 저장: ${path.relative(root, file)}`);
  return bad;
}

// ---- 메이커 미리보기와 나란히 ----

/** 메이커의 핵심(js/calendar.js · js/core.js)을 따로 된 vm 문맥에 한 번 싣는다 — check-format4.mjs와 같은 껍데기(브라우저 없이 HT.F4만 쓴다). */
let coreHT = null;
function core() {
  if (coreHT) return coreHT;
  const noop = () => {};
  const el = () => ({ style: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false }, appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop,
    querySelector: () => null, querySelectorAll: () => [], getContext: () => ({ measureText: s => ({ width: String(s).length * 7 }), font: '' }) });
  const store = new Map();
  const g = {
    console, setTimeout, clearTimeout, setInterval, clearInterval, navigator: { userAgent: 'node' },
    document: { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop, removeEventListener: noop, getAnimations: () => [] },
    localStorage: { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) },
    matchMedia: () => ({ matches: false, addEventListener: noop, addListener: noop }),
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
  };
  g.window = g;
  g.requestAnimationFrame = cb => setTimeout(() => cb(Date.now()), 0);
  g.cancelAnimationFrame = id => clearTimeout(id);
  vm.createContext(g);
  for (const rel of ['js/calendar.js', 'js/core.js']) vm.runInContext(fs.readFileSync(path.join(root, rel), 'utf8'), g, { filename: rel });
  return (coreHT = g.HT);
}

/** 메이커에 넣을 작업본 파일. 형식 4 파일은 메이커가 파일을 열 때와 같게 옛 꼴로 내린 작업본(HT.F4.down + 객체마다의 형식 4 칸 f4extras · 내림 알림 f4notes —
 *  js/maker.js openFile)을 maker/drafts/<저장소>.json에 써서 준다. scripts/maker-shoot.mjs는 작업본을 브라우저 저장소에 그대로 넣으므로 형식 4 원본을 주면
 *  작업본 정리(HT.draft.clean)가 모르는 objects를 버려 미리보기가 빈다. 옛 꼴(판 1 ~ 3)은 그대로 준다. */
function makerDraft(store) {
  const file = path.join(root, STORES[store].draft);
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const out = path.join(results, 'maker', 'drafts', `${store}.json`);
  const write = draft => (fs.mkdirSync(path.dirname(out), { recursive: true }), fs.writeFileSync(out, JSON.stringify(draft, null, 1) + '\n'), out);
  // 덧팩의 그릇을 덧붙인 작업본(draftScopes — 옛 꼴 작업본에만 · 덧팩의 다른 값은 없음 — 선반 시험 자료는 그릇 하나뿐)
  if (STORES[store].draftScopes) {
    const dlc = JSON.parse(fs.readFileSync(path.join(root, STORES[store].draftScopes), 'utf8'));
    if (Number(raw.formatVersion) >= 4) die(`${store}: draftScopes는 옛 꼴 작업본에만 씁니다`);
    raw.scopes = (raw.scopes || []).concat(dlc.scopes || []);
    return write(raw);
  }
  if (!(Number(raw.formatVersion) >= 4)) return file;
  const HT = core(), notes = [];
  const draft = HT.F4.down(JSON.parse(JSON.stringify(raw)), m => notes.push(String(m)));
  draft.f4extras = HT.F4.extrasOf(raw);
  if (notes.length) draft.f4notes = notes;
  return write(draft);
}

/** 장면의 그릇 상태(scopeStates — 객체 id나 uid의 열쇠) → 메이커 미리보기의 uid(`<작업본 id>/<그릇 id>` — 미리보기 js/core.js가 짓는 꼴)와 상태.
 *  선반은 maker-shoot의 --shelve(미리보기 기억 ht.ui의 shelvedScopes · 켬)로 · 나머지(펼침 · 접음)는 --scope-states로 넘긴다(과제 7 걸음 6). */
function makerScopeArgs(scene, draftFile) {
  // 다시 켬(reopen) 장면은 대본이 없고 앞 장면의 기억을 받으므로 앞 장면의 그릇 상태로
  const entries = Object.entries(scene.scopeStates || (scene.reopen && SCENES.find(x => x.id === scene.reopen)?.scopeStates) || {});
  if (!entries.length) return [];
  const id = JSON.parse(fs.readFileSync(draftFile, 'utf8')).id;
  const uid = ref => `${id}/${ref.split('/').pop()}`;
  const shelf = entries.filter(([, st]) => st === 'shelf').map(([ref]) => uid(ref));
  const rest = entries.filter(([, st]) => st !== 'shelf').map(([ref, st]) => `${uid(ref)}:${st}`);
  return [...(shelf.length ? [`--shelve=${shelf.join(',')}`] : []), ...(rest.length ? [`--scope-states=${rest.join(',')}`] : [])];
}

function maker(tag, scenes) {
  if (!process.env.HT_PLAYWRIGHT_ROOT) console.log('알림: HT_PLAYWRIGHT_ROOT가 없습니다 — 저장소의 node_modules에서 playwright를 찾습니다.');
  const out = path.join(results, 'maker', tag);
  fs.mkdirSync(out, { recursive: true });
  let bad = 0;
  for (const s of scenes) {
    if (!STORES[s.store].draft) { console.log(`${s.id}: 메이커 작업본이 없는 저장소(${s.store}) — 건너뜀`); continue; }
    if (s.dlcAdd?.length) { console.log(`${s.id}: DLC를 넣는 장면 — 메이커 미리보기는 DLC를 넣지 못해 건너뜀`); continue; }
    const app = path.join(SHOTS, tag, `${s.id}.png`);
    if (!fs.existsSync(app)) { console.error(`${s.id}: 앱 그림이 없습니다 — 먼저 --tag=${tag}`); bad++; continue; }
    const draft = makerDraft(s.store);
    const shoot = spawnSync(process.execPath, [path.join(root, 'scripts', 'maker-shoot.mjs'), root, out, `--tag=${s.id}`, `--draft=${draft}`, `--from=${s.from}`, `--to=${s.to}`, `--fold-spheres=${s.fold === 'first' ? 'default' : 'none'}`,
      ...makerScopeArgs(s, draft)], { encoding: 'utf8', timeout: 180000 });
    process.stdout.write(shoot.stdout || '');
    if (shoot.status !== 0) { console.error(`${s.id}: 메이커 찍기 실패 ${(shoot.stderr || '').trim().split('\n').slice(-4).join('\n')}`); bad++; continue; }
    const pair = path.join(out, `${s.id}-나란히.png`);
    const side = spawnSync(process.execPath, [path.join(here, 'side-by-side.mjs'), '--a', app, '--b', path.join(out, `${s.id}-화면.png`), '--crop', '0,0,1920,1080',
      '--labels', `연표 앱(${tag}),메이커 서고 미리보기`, '--out', pair], { encoding: 'utf8', timeout: 120000 });
    if (side.status !== 0) { console.error(`${s.id}: 나란히 뜨기 실패 ${(side.stderr || '').trim().split('\n').slice(-4).join('\n')}`); bad++; continue; }
    console.log(`${s.id}: 나란히 ${path.relative(root, pair)}`);
  }
  return bad;
}

// ---- 사람 창 찍기(앞 차례 회귀) ----

/** 사람 창 찍기의 대본(누름 · 창 열림 여섯 장)과 기억 원본 — 저장소에 커밋한 시험 자료(검토 2026-10-25: 예전에는 결과 폴더 window/에만 있었다). */
const WINDOW = {
  store: 'lantern',
  script: path.join(prototype, 'fixtures', 'remake4', 'window-script.json'),
  memory: path.join(prototype, 'fixtures', 'remake4', 'window-memory'),
  note: '등불 1100 ~ 1450 · 사람 띠 머리 단 · 인물 창 · 왕관 칸 창 · 띠 밖 머리 단 접기',
};

/** 대본이 뜨는 그림 이름(대본의 shot 차례) + 측정기가 끝에 뜨는 '화면-1배'. */
const windowShots = () => [...JSON.parse(fs.readFileSync(WINDOW.script, 'utf8')).filter(s => s.do === 'shot').map(s => `${s.name}.png`), '화면-1배.png'];

/** 사람 창 찍기: 대본(window-script.json)으로 실제 앱을 띄워 window/<태그>/에 일곱 장. 기억은 찍기마다 기억 원본의 **사본**(window/<태그>/_기억-사본)을
 *  --capture-memory로 넘긴다 — 원본 폴더를 바로 주면 앱이 끝 상태를 그 폴더에 다시 써 다음 찍기의 처음이 달라진다(d4-app-capture.mjs로 겪은 함정).
 *  임시 자리는 --memory-dir=window/<태그>/_memory · 저장소도 사본(찍은 뒤 지움). */
function captureWindow(tag) {
  const exe = exePath();
  if (!fs.existsSync(exe)) die(`실행본이 없습니다: ${exe} — powershell -File prototype/scripts/dev.ps1 app-build -Junction <이름> -Flutter <flutter.bat>`);
  const paintOff = paintOffValue(), paintRows = paintRowsValue(), paintOn = paintOnValue();
  if (!fs.existsSync(storeDb(WINDOW.store))) die(`저장소가 없습니다(${WINDOW.store}) — 먼저 --stores`);
  const out = path.join(results, 'window', tag);
  if (fs.existsSync(out)) {
    if (!('overwrite' in args)) die(`이미 찍음(덮어쓰지 않음 — --overwrite): ${path.relative(root, out)}`);
    fs.rmSync(out, { recursive: true, force: true });
  }
  fs.mkdirSync(out, { recursive: true });
  const memory = path.join(out, '_기억-사본');
  fs.cpSync(WINDOW.memory, memory, { recursive: true });
  const store = path.join(out, '_store');
  fs.cpSync(storeDir(WINDOW.store), store, { recursive: true });
  const pass = [`--db=${path.join(store, 'archive.db')}`, `--measure=${out}`, '--exit=yes', '--offline=yes', '--capture-only=yes', '--capture-size=1920x1080',
    `--capture-script=${WINDOW.script}`, `--memory-dir=${path.join(out, '_memory')}`, `--capture-memory=${memory}`, ...(paintOff ? [`--paint-off=${paintOff}`] : []),
    ...(paintRows ? [`--paint-rows=${paintRows}`] : []), ...(paintOn ? [`--paint-on=${paintOn}`] : [])];
  const appSo = path.join(path.dirname(exe), 'data', 'app.so');
  const t0 = Date.now();
  const r = spawnSync(exe, pass, { cwd: path.dirname(exe), encoding: 'utf8', timeout: 300000 });
  fs.writeFileSync(path.join(out, '실행.log'), (r.stdout || '') + (r.stderr || '') + (r.error?.stack || ''));
  fs.rmSync(store, { recursive: true, force: true });
  fs.writeFileSync(path.join(out, '_실행.json'), JSON.stringify({ exe, code: fs.existsSync(appSo) ? sha12(appSo) : '?', engine: sha12(path.join(path.dirname(exe), 'archive_engine.dll')),
    paintOff, ...(paintRows ? { paintRows } : null), ...(paintOn ? { paintOn } : null), store: WINDOW.store, script: path.relative(root, WINDOW.script), memory: path.relative(root, WINDOW.memory), args: pass }, null, 1) + '\n');
  if (r.error || r.status !== 0 || fs.existsSync(path.join(out, '측정-실패.txt'))) {
    console.error(`사람 창 ${tag}: 실제 앱 실행 실패(${r.error?.message || r.status}) — ${path.relative(root, out)}`);
    return 1;
  }
  const log = JSON.parse(fs.readFileSync(path.join(out, '검증-기록.json'), 'utf8'));
  const errors = log.steps.filter(x => x.error).length, asks = log.ask_failures.length;
  const missing = windowShots().filter(n => !fs.existsSync(path.join(out, n)));
  const warn = [asks && `실패한 조회 ${asks}`, errors && `대본 오류 ${errors}`, missing.length && `그림 없음 ${missing.join(' · ')}`, paintOff && `끔 ${paintOff}`,
    paintRows && `가로선 ${paintRows}`, paintOn && `켬 ${paintOn}`].filter(Boolean).join(' · ');
  console.log(`사람 창 ${tag}: 찍음 ${path.relative(root, out)} · ${windowShots().length - missing.length}장 · ${((Date.now() - t0) / 1000).toFixed(1)}초${warn ? ' · ' + warn : ''}`);
  return asks || errors || missing.length ? 1 : 0;
}

/** 사람 창 찍기 두 태그의 일곱 장을 견준다 — 모두 바이트 같아야 통과(다르면 다른 픽셀 수 · 범위). */
function compareWindow(tag, other) {
  const rows = [];
  let bad = 0;
  for (const name of windowShots()) {
    const a = path.join(results, 'window', tag, name), b = path.join(results, 'window', other, name);
    if (!fs.existsSync(a) || !fs.existsSync(b)) { rows.push({ name, state: '그림 없음' }); bad++; continue; }
    const A = fs.readFileSync(a), B = fs.readFileSync(b);
    if (A.equals(B)) { rows.push({ name, state: '같음' }); continue; }
    rows.push({ name, state: '다름', ...pixelDiff(A, B) });
    bad++;
  }
  console.log(`\n사람 창 견줌: ${tag} ↔ ${other} · 모든 그림이 같아야 함`);
  console.log('| 그림 | 바이트 | 다른 픽셀 | 범위(x0,y0,x1,y1) |');
  console.log('| --- | --- | --- | --- |');
  for (const r of rows) console.log(`| ${r.name} | ${r.state} | ${r.pixels ?? (r.size ? '크기 다름' : r.note ?? '')} | ${r.box ? r.box.join(',') : ''} |`);
  const file = path.join(results, 'window', tag, `견줌-${other}.json`);
  if (fs.existsSync(path.dirname(file))) fs.writeFileSync(file, JSON.stringify({ tag, other, rows }, null, 1) + '\n');
  console.log(`${bad ? `다름 ${bad}` : '모두 같음'}${fs.existsSync(path.dirname(file)) ? ` · 저장: ${path.relative(root, file)}` : ''}`);
  return bad;
}

// ---- 차례 ----

let bad = 0;
if ('list' in args) {
  console.log('| 장면 | 저장소 | 해 범위 | 내려 보기(px) · 덧 | 무엇 |');
  console.log('| --- | --- | --- | --- | --- |');
  for (const s of SCENES) {
    const more = [s.fold === 'first' && '처음 접힘', s.script && `대본 ${s.script.map(x => x.do + (x.uid ? ' ' + x.uid : '')).join(' · ')}`, s.foldScopes && `그릇 접음 ${s.foldScopes.join(' · ')}`,
      s.expandHosts && `상국 펼침 ${s.expandHosts.join(' · ')}`, s.scopeStates && `그릇 ${Object.entries(s.scopeStates).map(([k, v]) => `${k} ${v}`).join(' · ')}`,
      s.flaw && '흠', s.box && '상자', s.shelf && '선반', s.reopen && `다시 켬(${s.reopen}의 기억)`,
      s.ganji && '간지 줄 켬', s.foldSpheres && `문화권 접음 ${s.foldSpheres.join(' · ')}`,
      s.dlcAdd && `DLC 넣음 ${s.dlcAdd.map(f => path.basename(f)).join(' · ')}`].filter(Boolean);
    console.log(`| ${s.id} | ${s.store} | ${s.from} ~ ${s.to} | ${s.scroll || 0}${more.length ? ' · ' + more.join(' · ') : ''} | ${s.note} |`);
  }
}
if ('keep-app' in args) keepApp(args['keep-app'] || die('--keep-app=<이름>'));
if ('stores' in args) buildStores();
if ('census' in args) await census();
const scenes = pick(SCENES);
if ('tag' in args && !args.tag) die('--tag=<이름>');
// 사람 창 찍기(--window): 장면 찍기 · 견주기 · 메이커와 따로 — 대본 하나로 일곱 장.
if ('window' in args) {
  if (!args.tag) die('--window는 --tag=<이름>과 함께');
  for (const k of ['maker', 'only', 'step']) if (k in args) die(`--window에는 --${k}를 쓰지 않습니다`);
  if ('paint-off' in args && 'no-capture' in args) die('--paint-off는 찍을 때만 씁니다');
  if ('paint-rows' in args && 'no-capture' in args) die('--paint-rows는 찍을 때만 씁니다');
  if ('paint-on' in args && 'no-capture' in args) die('--paint-on은 찍을 때만 씁니다');
  if (!('no-capture' in args)) bad += captureWindow(args.tag);
  if ('compare' in args) {
    if (!args.compare) die('--window --tag=<이름> --compare=<태그>');
    bad += compareWindow(args.tag, args.compare);
  }
  process.exit(bad ? 1 : 0);
}
// --tag면 찍는다 — 견주기만(--no-capture) · 메이커와 나란히(--maker — 그 태그의 앱 그림을 씀)는 찍지 않는다.
// 다만 --maker에 --app을 주면 그 실행본으로 앱도 먼저 찍는다(과제 7 걸음 6 — 한 줄로 앱 · 미리보기를 같은 태그에).
const shoots = args.tag && !('no-capture' in args) && (!('maker' in args) || 'app' in args);
if ('paint-off' in args && !shoots) die('--paint-off는 찍을 때(--tag)만 씁니다');
if ('paint-rows' in args && !shoots) die('--paint-rows는 찍을 때(--tag)만 씁니다');
if ('paint-on' in args && !shoots) die('--paint-on은 찍을 때(--tag)만 씁니다');
if (shoots) bad += await capture(args.tag, scenes);
if ('compare' in args) {
  if (!args.tag || !args.compare) die('--tag=<이름> --compare=<태그>');
  bad += await compare(args.tag, args.compare, scenes);
}
if ('maker' in args) {
  if (!args.tag) die('--maker는 --tag=<앱 그림의 태그>와 함께');
  bad += maker(args.tag, scenes);
}
if (!Object.keys(args).some(k => ['list', 'keep-app', 'stores', 'census', 'tag', 'compare', 'maker'].includes(k))) {
  console.log('할 일을 적으세요: --stores · --census · --tag=<이름> · --compare=<태그> · --maker · --window · --keep-app=<이름> · --list (머리말 참고)');
  process.exit(2);
}
process.exit(bad ? 1 : 0);

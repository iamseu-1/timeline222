# 별여울 아카이브 성능 시제품

> **2026-10-14 바뀜:** 월흔해(`samples/sample-moonwake.json`)를 비롯한 옛 견본은 감독 결정으로 모두 지웠고, 견본은 `samples/sample-lantern.json`(등불 연대기) 하나다. 아래 기록 속의 `sample-moonwake` · `moonwake*` 명령은 그때의 기록이다 — 지금 돌릴 때는 `export-layout.mjs`의 기본(등불 연대기 → `lantern-layout3.json` · `sample-lantern.htpack`)이나 `HT_EXPORT_PACK=east-asia`를 쓰고, 저장소는 `node scripts/build-showcase.mjs <새 폴더>`로 짓는다.

기존 연표·메이커를 그대로 둔 0·1단계 검사 앱이다. **Windows에서 실제 SQLite 저장소를 Rust로 조회하고 Flutter의 전용 그리기 화면에서 이동·확대·검색·선택·원문 열람을 연결한다. Android 설치 파일은 같은 처리부로 빌드하지만 실기기 통과는 별도다.**

기존 프로그램을 대체하거나 기존 자료 형식을 변경하지 않는다. 새 파일 규격을 만들지 않았으며 메이커 편집 기능도 이전하지 않았다. 자세한 차이는 `../docs/아카이브-기능과-움직임-대조표.md`에 있다.

## 실행 결과와 위치

완성된 실행 파일·자료·측정·화면·확인서는 주 저장소의 `배포/아카이브-시제품-2026-09-20/`에 모은다. Git 기록은 `codex/archive-prototype`, 실제 소스는 `.claude/worktrees/archive-prototype/prototype`에 있다. 주 작업본 합치기는 하지 않는다.

- Windows: 배포 폴더의 `Windows/archive_prototype.exe`. 실행 파일 곁 `prototype.json`은 별도 자료 폴더의 100만 사건 DB를 가리킨다.
- Android: 배포 폴더의 `Android/별여울-성능시제품-arm64.apk`. ARM64 시험용 서명, 앱 식별자 `local.archive.archive_prototype`. 처음 실행할 때 포함한 10만 사건과 가상 원문 3개를 앱 전용 폴더에 배치한다. S25의 100만 사건·전체 사용자 자료·20분 연속 사용 결과가 아니다.
- 기존 월흔해: 원본 `.htpack` 전체와 기존 정규화기의 패치 적용 후 사건 5,437개를 별도 DB에 보존한 읽기 투영이다. 정권 띠·관계·문서 전체를 표시한 새 연표가 아니다.

## 재현

고정 도구는 Flutter 3.47.5·Dart 3.13.4·Rust 1.94.1·Android NDK 28.2.13676358이다. `engine/Cargo.lock`과 `app/pubspec.lock`을 사용한다. Flutter SDK는 공식 배포의 SHA-256을 확인했다. 원래 시스템 PATH나 기존 프로젝트 설정은 바꾸지 않는다.

다음 명령은 이 폴더에서 실행한다. Python이 `py`로 설치되어 있지 않으면 인수인계에 적힌 Codex 제공 Python을 쓴다.

```powershell
cargo test --locked --release --manifest-path engine/Cargo.toml
cargo build --locked --release --manifest-path engine/Cargo.toml
engine/target/release/archive-tool.exe generate data/100k/archive.db 100000 fixtures
engine/target/release/archive-tool.exe generate data/1m/archive.db 1000000 fixtures
py -X utf8 scripts/prepare-seed.py
node scripts/compat-check.mjs
engine/target/release/archive-tool.exe import-legacy results/compat/sample-moonwake.htpack results/compat/moonwake-projection.json data/moonwake/archive.db
```

생성기와 가져오기 도구는 이미 있는 DB를 덮어쓰지 않는다. 다시 생성할 때는 새 검사 폴더를 지정한다. 원문 견본 세 개는 저장소에 포함되어 있어 PDF를 다시 만들 필요가 없다. 재생성은 `scripts/make-fixtures.py`이며 원본 역사 자료는 쓰지 않는다.

Flutter 준비는 `app`에서 `flutter pub get`으로 한다. 이 PC에서는 플러그인의 디렉터리 연결 권한 문제와 Android 도구의 한글 경로 문제가 있었다. Windows는 `%TEMP%/ht-archive-project`를 이 시제품 폴더에 연결해 그 경로에서 빌드했고, Android는 `scripts/build-android.ps1`로 새 영문 임시 폴더에 소스만 복사했다. Windows 플러그인 연결도 `scripts/build-windows.ps1`이 시제품 내부에만 만든다. SDK 준비 후 첫 의존성 받기에서 플러그인 연결 오류가 난 경우 이 스크립트로 연결을 만든 뒤 `flutter pub get --offline`을 한 번 실행한다.

```powershell
# app 폴더에서
dart analyze --fatal-infos lib test
flutter test --no-pub
# prototype 폴더에서
scripts/build-windows.ps1
scripts/build-android.ps1
```

1단계의 측정 스크립트 `measure.ps1`과 앱의 `--benchmark`는 2단계에서 `scripts/measure.mjs`와 `--measure`로 바뀌었다(아래 '2단계' 절). 1단계의 측정 결과는 `배포/아카이브-시제품-2026-09-20/`에 그대로 있다.

현재 PC에서는 한글 경로를 통과한 분석 서버가 중단되어 영문 연결 경로 `%TEMP%/ht-archive-project/app`에서 `dart analyze --fatal-infos lib test`로 확인했다. 일반 화면 시험과 Android 빌드 경로를 혼동하지 않는다.

자료 처리부만 비교하려면 `archive-tool bench <DB> <결과.json>`을 사용한다. 이는 조회와 결과 직렬화를 잰 것이며 화면 간격이나 실제 마우스 응답을 뜻하지 않는다. 운영체제 파일 캐시를 강제로 비우지 않는다.

## 2단계 작업 폴더(next-engine)에서의 재현 — 2026-09-21

2단계(규모와 병목 검증 · 컴퓨터 전용)는 가지 `next-engine`의 이 폴더를 넓혀 진행한다. 계획은 `../docs/계획-아카이브-2단계-구현.md`, 설계는 `../docs/설계-아카이브-2단계-규모와-병목-검증.md`.

- 빌드는 연결 폴더 `%TEMP%/ht-next-engine`(→ 이 폴더)에서 한다. `%TEMP%/ht-archive-project`는 1단계 작업 폴더를 가리키므로 그대로 둔다.
- 자주 쓰는 명령은 `scripts/dev.ps1`(ASCII 전용)로 감쌌다: `engine-test` · `engine-build` · `app-get` · `app-check` · `app-build`. 연결 폴더가 없으면 만들고, 다른 곳을 가리키면 멈춘다. `app-get`은 첫 의존성 받기가 플러그인 연결에서 멈추면 연결을 만든 뒤 `--offline`으로 마저 받는다. `app-get` · `app-build`는 빈 `app/assets/seed/`(목록 `[]`)를 만들어 Windows 빌드가 Android용 10만 자료 없이도 되게 한다.
- `flutter test` · 빌드 때 `pdfium_dart`의 빌드 훅이 고정된 PDFium 배포본(chromium/7811)을 `app/.dart_tool/`에 받는다. 1단계 작업 폴더에 받아 둔 것과 지문이 같다(`019b6ee6…`).
- 보호 자료 지문: `node scripts/fingerprint.mjs save|check <기록.json>` (`packs/`와 기존 `samples/*.json` 26개).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 engine-test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 engine-build
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 app-get
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 app-check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 app-build
```

### 2단계 자료

저장소의 모양은 스키마 "2"다(띠 · 칸 · 줄 · 자료집 · 단계별 요약 · 덮는 색인). 1단계의 저장소는 열리지 않는다 — 다시 만든다. 모두 무시 폴더 `data/`에 둔다.

```powershell
# 가상 자료(씨앗 고정: 자료집 8 · 트랙 56 · 줄 252 · 띠 26,494 · 칸 353,923). 10만 11초 · 100만 108초 · 1,000만 23분(5.3GB)
engine/target/release/archive-tool.exe generate2 data/v2-1m/archive.db 1000000 data/v2-1m/originals
# 지금 연표의 견본(월흔해)을 지금 연표와 똑같은 줄 배치로: 배치를 내보내고 → 가져온다
node scripts/export-layout.mjs
engine/target/release/archive-tool.exe import-layout results/compat/sample-moonwake.htpack results/compat/moonwake-layout.json data/moonwake2/archive.db
# 타일이 전수 조사와 맞는지(누락 · 중복 0) · 자료 처리부의 타일 시간 · 색인의 모양이 바뀌었을 때 색인만 다시
engine/target/release/archive-tool.exe verify-tiles data/v2-1m/archive.db 2000
engine/target/release/archive-tool.exe bench data/v2-1m/archive.db results/bench-1m.json
engine/target/release/archive-tool.exe reindex data/v2-1m/archive.db
```

### 2단계 측정

```powershell
# 정식: 여섯 구간 × (처음 1회 + 30초 × 3회). 자료 하나에 13분쯤. 결과 폴더는 새 이름으로(덮어쓰지 않는다)
node scripts/measure.mjs --db data/v2-1m/archive.db --out results/formal/1m --from -615373200 --to -457585200
# 짧게: 구간을 골라서, 처음 1회 없이
node scripts/measure.mjs --db data/v2-1m/archive.db --out results/try --sections 끌기,확대 --seconds 10 --repeats 1 --cold no
# 1배 그림만(장면 · 돋보기 배율을 골라서)
node scripts/measure.mjs --db data/moonwake2/archive.db --out results/shot --from -930949200 --to -852055200 --capture-only --capture-mag 1.5
```

- 구간: `끌기`(옆으로 끌기와 관성) · `확대`(80ms마다 휠 한 칸, 12칸씩 확대 · 축소) · `돋보기`(집기 입력으로 50 ↔ 300%) · `밀집`(같은 날 사건이 몰린 나흘 보기에서 끌기) · `세로`(위아래 끌기) · `자료집`(0.7초마다 켜고 끄기). 입력은 `app/lib/measure/scenarios.dart`의 순수 계산이라 늘 같다.
- 판정(`frame_stats.dart`): 한 장면의 예산 T = 1000 ÷ 주사율. 놓친 장면(만들기 > T · 칠하기 > T · 앞 장면과의 간격 > 1.5T) 1% 이하 · 2장 이상 연달아 놓침 없음 · 50ms 이상 멈춤 없음 · 만들기와 칠하기의 느린 1%가 각각 0.8T 이하. 놓친 장면은 까닭별로도 센다 — '간격'만 넘은 것은 일이 무거워서가 아니라 장면이 늦게 시작된 것이다(다른 프로그램 · 화면 합성기의 흔들림).
- 전체 판정(`report.dart`): 무효 구간이 있으면 `무효`(다시 잰다), 미달이 하나라도 있으면 `미달`. 무효 = 장면이 기대만큼 찍히지 않았거나(창이 가려짐) 재는 도중 밖에서 입력이 들어옴. 처음 1회(찬 상태)는 따로 적고 판정에 넣지 않는다.
- 재는 동안 연표는 측정기의 합성 입력(장치 번호 9071)만 받는다. 합성 입력은 Flutter의 입력 경로로 장면마다 한 번 넣는다 — `입력→반응`은 입력을 넣은 장면의 시작부터 칠하기 끝까지이고, 실물 입력 장치의 지연과 화면이 실제로 빛나는 시각은 들어 있지 않다.
- 기록: `측정.json`(환경 · 전원 · 자료 · 구간마다 만들기 · 칠하기 · 전체 · 간격 · 입력→반응 · 도형 · 글자 · 타일 왕복 · 상주 메모리의 분포, 빈 자리 · 메움 수, 놓친 장면의 단서 60개까지) · `시작-장면.json` · `화면-1배.png` · 도중에는 `진행.json`.
- 앱 안에서도 잴 수 있다: 맨 위의 `측정` 단추 = 지금 보는 장면에서 여섯 구간을 10초씩 재고 결과를 요약해 보여 준다(기록은 실행 파일 옆 `측정-결과/<시각>/`).
- 글자 방식은 `--text atlas`(기본, 그림판에 찍어 두고 한 번에) · `--text paragraph`(글줄 보관). 병목을 가르는 실험용 층 끄기는 `--hide bands,bandFill,bandEdge,cells,cellNames,tabs,events,fade`(정식 측정에는 쓰지 않는다).
- 전달 형식의 효과(같은 타일 · 17,113개 항목): 이진 타일 0.65MB를 푸는 데 0.31ms, 같은 내용의 JSON 1.55MB는 29.3ms(`app/test/decode_bench_test.dart` → `results/decode-bench.json`).

## 구현 경계

- SQLite는 읽기 전용으로 열고 페이지 캐시를 16MiB로 둔다. 일반 표시 요청은 1,800개 이하, 본문 검색과 묶음 목록은 50개씩 받는다. 실제 최대 전달 바이트는 결과에 기록한다.
- 화면은 일반 화면 부품 수십만 개를 만들지 않는다. 보이는 줄과 범위만 전용 그리기에서 처리한다. 글자 모양 보관은 512개로 제한한다.
- 넓게 볼 때는 사전 요약을 읽는다. 긴 기간은 겹치는 요약 칸마다 포함되며 칸의 수를 합해 고유 사건 수라고 하지 않는다. 전체 사건 수는 별도 값이다.
- 본문 검색은 사건 제목과 본문에 들어 있는 가상 원문 발췌를 대상으로 한다. PDF 전체 페이지의 색인과 OCR은 이후 단계다.
- 자료 조회는 별도 작업자에서 실행한다. 요청 중에는 최신 범위를 기억하고, 늦은 응답이 현재 화면 범위를 덮지 못하면 버린다. 화면 변환은 DB를 기다리지 않는다.
- 원문은 지문 이름의 별도 파일이다. 시작 때는 DB 목록만 읽는다. 원문 전체 지문 검사는 가져오기·명시적인 검사 때 실행한다. 파일을 열 때 앱의 자료 폴더 밖 경로는 거절한다.
- PDF는 로컬 파일을 직접 열고 페이지 그림 캐시 목표를 32MiB로 둔다. 이미지 캐시도 32MiB이며 검사 그림은 1600픽셀 폭으로 연다. 이 값은 프로세스 전체 메모리 상한이 아니다.
- 계측 실행은 Dart 네트워크 요청을 차단한다. 외부 서버 없이 검색·원문을 읽지만, 실제 PC 연결 해제·S25 비행기 모드 검증은 별도로 남긴다.
- 시작 시간 값은 **Dart 화면 상태가 만들어진 시점부터 자료 목록 준비까지**다. 프로세스 실행과 Flutter 초기화 전체를 포함한 시작 시간·OS 파일 캐시가 찬 첫 실행 시간으로 해석하지 않는다.

## 정식 교체까지 남은 것

기존 띠·관계·필터·지도자 칸·인물·중첩 문서·출력·메이커·되돌리기·파일 왕복·움직임 전체를 대조해야 한다. 현재 시제품의 오른쪽 안내 창은 선택이 없을 때도 열려 있다. 검색 이동도 기존의 멀리 가기 효과를 아직 쓰지 않는다.

1,000만 사건, 관계가 밀집한 장면, 다수 자료집·필터 조합, 원문 대량 검색·글자 인식, 기기 간 전체 사본 전달·중단 재개·충돌·백업 복원, 세 기기의 저장 공간과 실기기 검증을 통과해야 한다. 정지 중 지속되는 화면 시계의 비용·Android 발열도 2단계에서 줄이고 측정한다. 물리 화면에 표시되는 최종 시각과 실제 손 입력의 지연은 이번 합성 입력 측정과 구분한다.

## 3단계 작업 폴더에서의 재현 — 2026-09-21

3단계(지금 연표의 기능을 새 엔진으로 옮기기)는 같은 폴더(가지 `next-timeline`)에서 이어 간다. 계약은 `../docs/계약-아카이브-3단계.md`, 설계는 `../docs/설계-아카이브-3단계-연표-기능-이전.md`, 계획은 `../docs/계획-아카이브-3단계-구현.md`.

저장소의 모양은 스키마 **"3"**이다(2의 표에 트랙의 색과 단 · 줄의 새 값 · 민족 묶음 · 분류 · 날짜 칸 · 띠와 칸과 사건의 표현 값 · 일반 항목 `items` · 항목 기록 `entities` · 줄 이름 `row_labels`를 더했다). **2단계의 저장소는 열리지 않는다 — 다시 만든다.** 이진 타일도 **2판**(구역 표)이다. 3단계의 자료는 새 폴더 `data/v3-*` · `data/moonwake3`에 둔다(이미 있는 것은 덮어쓰지 않는다 — 새 이름을 준다).

```powershell
# 0) 자료 처리부
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 engine-test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 engine-build

# 1) 지금 연표의 배치를 JSON 3판으로 내보낸다 → results/compat/lantern-layout3.json · sample-lantern.htpack(견본 등불 연대기)
node scripts/export-layout.mjs

# 2) 견본을 스키마 3 저장소로 가져온다(원본 전용 팩은 그대로 보존)
engine/target/release/archive-tool.exe import-layout results/compat/sample-lantern.htpack results/compat/lantern-layout3.json data/lantern/archive.db

# 3) 가상 자료(씨앗 20260921 고정 · 자료집 8 · 트랙 56 · 줄 252 · 띠 26,494 · 칸 352,119 · 민족 묶음 140 · 분류 5 · 날짜 칸 96 · 일반 항목 1,295)
engine/target/release/archive-tool.exe generate2 data/v3-100k/archive.db 100000 fixtures   # 13초 · 139MB
engine/target/release/archive-tool.exe generate2 data/v3-1m/archive.db 1000000 fixtures    # 125초 · 780MB
# 1,000만은 3단계에서 만들지 않는다(2단계에서 이미 쟀다).

# 4) 타일이 전수 조사와 맞는지(누락 · 중복 0) · 자료 처리부의 타일 시간 · 타일 하나를 파일로
engine/target/release/archive-tool.exe verify-tiles data/v3-100k/archive.db 600
engine/target/release/archive-tool.exe bench data/v3-100k/archive.db results/bench-v3-100k.json
engine/target/release/archive-tool.exe tile data/v3-100k/archive.db '{\"level\":9,\"x\":0,\"chunk\":0,\"packs\":[1,2,3,4,5,6,7,8]}' app/test/fixtures/tile-100k-L9-x0-c0.bin

# 5) 조회 명령(3판): 뼈대 · 내용이 있는 줄 · 왼쪽 줄 이름 · 상세 창의 항목 기록
engine/target/release/archive-tool.exe query data/moonwake3/archive.db '{\"op\":\"layout\"}'
engine/target/release/archive-tool.exe query data/moonwake3/archive.db '{\"op\":\"rows_near\",\"near\":[-1540504800,-1245972960],\"far\":[-900000000,-800000000],\"fade\":525960,\"packs\":[1]}'
engine/target/release/archive-tool.exe query data/moonwake3/archive.db '{\"op\":\"row_labels\",\"rows\":[1],\"at\":-1500000000}'
engine/target/release/archive-tool.exe query data/moonwake3/archive.db '{\"op\":\"entity\",\"uid\":\"moonwake-chronicle/p-coast-0\"}'

# 6) 화면 쪽 검사
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 app-check
```

- 1) · 2)의 Node 내보내기 → `import-layout` 길은 이제 정답지 · 비교용이다 — 이 길로 지은 저장소에는 보조 달력 표가 없어 DLC 넣고 빼기가 `code: "calendar"`로 막힌다. 앱이 쓸 저장소는 아래 '한 벌 P3 · P4' 절의 `archive-tool build`로 짓는다.
- PowerShell 5.1은 native 명령에 넘기는 큰따옴표를 지운다 — 위처럼 `\"`로 감싼다.
- 고정 파일 `app/test/fixtures/tile-100k-L9-x0-c0.bin`은 4)의 `tile` 명령이 만든 것이다. 가상 자료의 규칙이나 타일 형식을 바꾸면 다시 떠서 `test/tile_test.dart`의 숫자를 고친다.
  지금 엔진의 타일과 바이트까지 같은지는 `test/engine_ffi_test.dart`의 첫 검사가 보는데, **`data/v3-100k`가 없는 곳(다른 작업 폴더 · CI)에서는 건너뛴다** — 타일에 실리는 것을 바꾼 커밋에서는 3)으로 저장소를 지어 둔 채 그 검사를 돌린다.
  (2026-10-13 다시 뜸: 알약의 분류 비율 열 `cats`(`56140a8` · 계약 5-1절)가 더해지기 전의 타일이 남아 있었다 — 19,144 → 19,176바이트 · 글 304 → 306개 · 알약 구역 4 → 5열. 다른 값은 그대로.)
- `data/v2-*` · `data/moonwake2`(2단계의 저장소)는 스키마 2라 열리지 않는다. 그대로 두고 새 폴더를 쓴다.
- 3단계 도중에 스키마가 두 번 더 넓어졌다(조회 명령의 `names` 표 · 거르개의 `tracks.key` · `items.ref_kind`). 그 전에 만든 저장소(`data/v3-100k` · `data/v3-1m` · `data/moonwake3b` …)는 `layout`에서 멈추니 새 도구로 다시 만든다(`data/v3b-1m` · `data/moonwake3f`).

### 3단계 — 내보내기 · 그림 뜨기 · 비교 · 측정

```powershell
# 내보내기의 환경 변수: 받는 쪽이 준비되지 않은 모듈을 빼고(HT_EXPORT_SKIP) · 여럿이 동시에 돌릴 때 서로 덮어쓰지 않게(HT_EXPORT_NAME)
$env:HT_EXPORT_SKIP='variants'; $env:HT_EXPORT_NAME='moonwake-layout3-main.json'; node scripts/export-layout.mjs

# 앱을 빌드하지 않고 장면을 1920×1080 그림과 자리 기록(json)으로 뜬다 — 지금 연표의 기준 그림(results/dom/*.png)과 같은 좌표
cd app; flutter test --no-pub test/render_scene_test.dart --dart-define=SCENE=밀집-세부 --dart-define=OUT=../results/render-내이름 --dart-define=DB=../data/moonwake3f/archive.db `
  [--dart-define=START=<해> --dart-define=END=<해> --dart-define=SCROLL=<px> --dart-define=NAME=<이름> --dart-define=DUMP=yes] `
  [--dart-define=DENSITY=-1|0|1|2 --dart-define=BIRD=a|b|c --dart-define=HIDE=leaders,cabinets --dart-define=FOLD_TRACKS=all|1,2 --dart-define=FOLD_PEOPLE=all|<열쇠;…>]
node scripts/side-by-side.mjs --a results/dom/밀집-세부.png --b results/render-내이름/밀집-세부.png --crop 240,612,620,120 --zoom 2 --out results/render-내이름/비교.png

# 지금 연표의 화면 덤프(자리 · 크기 · 색 · 글꼴)와 그 조회
node scripts/dump-dom.mjs --scene 밀집-세부 ; node scripts/dom-query.mjs results/dom/밀집-세부.json --class tl-band --items --limit 20

# 1배 나란히 비교(지금 연표 ↔ 새 앱 실행본 · 세 장면 · 조각별 차이 점수) — HT_PLAYWRIGHT_ROOT 필요, 재는 동안 새 앱의 창이 잠깐 뜬다
node scripts/compare-shots.mjs --db data/moonwake3f/archive.db --out results/compare3/<이름>

# 구간 측정(짧게 · 정식) — 창을 가리지 말 것
node scripts/measure.mjs --db data/v3b-1m/archive.db --out results/measure3/<이름> --seconds 10 --repeats 1 --cold no
node scripts/measure.mjs --db data/v3b-1m/archive.db --out results/formal3/1m
```

### 4단계 1걸음 — DLC를 앱 안에서 더하고 빼기(2026-09-22)

설계는 `../docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md`. 앱의 DLC 관리(`D`)에서 `📂 파일에서 더하기…` · 카드의 `DLC 삭제` · 켜고 끄기가 **앱이 켜진 채로** 돈다:
엔진이 저장소를 제자리에서 고쳐 쓰고(`{"op":"add_pack"}` · `{"op":"remove_pack"}` — 계약 2-7-1 · 휴대폰과 컴퓨터가 같다 · Node 없음) 뼈대를 다시 읽으면 줄이 옛 자리에서 새 자리로 흐른다.
앱이 받는 것은 DLC 파일(`.htpack` 형식 1 ~ 4 · `.json`)이다 — 예전 아카이브 배치 파일(`.htlayout`)은 받지 않고 '메이커에서 .htpack으로 저장해 넣어 주세요'만 알린다(계획 P4 과제 11c).
배포 폴더의 `도구/prototype/archive-tool`(collect-app.mjs가 꾸린다)이 있으면 판 올림 뒤 `DLC/` 폴더 다시 들이기(판정 R32)도 한다.

```powershell
# 도구를 손으로(앱과 같은 몸 — 엔진이 제자리에서 고쳐 씀 · 그 저장소를 연 앱은 먼저 닫는다: 다른 프로세스가 고쳐 쓰면 켜진 앱의 줄 자리 표가 낡는다)
engine/target/release/archive-tool.exe add-pack data/<저장소>/archive.db <파일.htpack> [<파일.htpack> …]
engine/target/release/archive-tool.exe remove-pack data/<저장소>/archive.db <DLC 글자 id> [--delete]   # --delete가 없으면 원본은 보관함에(끄기)
engine/target/release/archive-tool.exe query data/<저장소>/archive.db '{\"op\":\"kept_packs\"}'          # 보관함(꺼 둔 DLC)
# 앱을 파일과 함께 켜면 뜬 뒤에 더한다(연결 프로그램 · 검증의 손잡이). 파일 여럿은 ;로. 검사로 띄울 때는 늘 --memory-dir(판정 R50)
app/build/windows/x64/runner/Release/archive_prototype.exe --db=<저장소> --add-dlc=<파일.htpack> --memory-dir=<새 폴더>
```

- 같은 id의 DLC는 판(`"1.0.3"` — 점으로 나눈 마디를 수로 견줌)이 같거나 높을 때만 바꿔 넣는다(낮으면 거절 · 꺼 둔 DLC의 판과도 견줌). 저장소의 바탕(첫 DLC)은 뺄 수 없다 — 앱은 바탕을 화면에서만 켜고 끈다.
- 거절은 저장소를 그대로 두고 기계용 `code`(달력 표 문제 `calendar` · 날짜가 달력 범위 밖 `range` · 배치 못 함 `layout` · 파일이 망가짐 `broken` · 낮은 판 `version` · 같은 항목이 두 트랙 `dup_uid` · 원본 없음 `original` …)를 단다 — 앱은 그것으로 쉬운 말을 고른다(계약 2-7 · 2-7-1).
- 엔진의 넣고 빼기는 **달력 표가 든 저장소**에서만 된다(`archive-tool build`로 지은 것 — 아래 '한 벌 P3 · P4'). DLC 글자 id(`meta.pack_keys`)가 없는 아주 옛 저장소 · 달력 표가 없는 저장소(예전 Node 길로 지은 것)는 `code: "calendar"`로 거절한다 — 앱의 새 판 시드로 옮기거나 `build`로 다시 짓는다.
- **`node scripts/add-dlc.mjs`는 정답지 · 비교용으로만 남았다**(앱 · 꾸러미는 쓰지 않음 — `apply-check.mjs` · `add-dlc-tomb-check.mjs`가 씀). 그 도구의 다시 짓기 길(`--apply` · `--layout-only` 없이)은 Node 배치 → `import-layout`이라 **달력 표 없는 저장소**를 지어, 그 저장소에서는 앱이 DLC를 넣고 빼지 못한다 — 달력 표가 든 저장소에서는 멈추고(`--allow-no-calendar`로만 — 비교용), 사용자 저장소에는 쓰지 않는다.

### 3단계 — 실제 앱을 눌러 보며 점검하기(2026-09-22)

부품은 조회가 실패하면 그 묶음만 조용히 비우므로, 단위 검사 · 계약 검사가 모두 통과해도 **실제 앱에서만** 기능이 빌 수 있다(분을 소수 꼴로 보내 엔진이 거절하던 일). 기능을 '됐다'고 적기 전에 아래를 돌려 그림을 눈으로 보고 `실패한 조회 0건 · 기대 어긋남 0건`을 확인한다. 재는 동안 새 앱의 창이 장면마다 잠깐 뜬다(가리지 말 것).

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 app-build
node prototype/scripts/verify-app.mjs --out prototype/results/verify-app/<이름> [--db prototype/data/moonwake3h/archive.db] [--only 누르기,검색]
```

- 장면과 걸음은 `scripts/verify-app.mjs`의 `SCENES`(누르기 · 조명과 메아리 · 같은 해 보기 · 검색 · 필터와 밀도 · 대범위와 소속 · 문서와 도구 · 접기와 돋보기). 걸음의 뜻은 `app/lib/measure/verify_script.dart` 머리말(고르기 · 명령 · 슬롯 · 필터 · 검색 · 누름/오른쪽 누름/손 올리기 · 찍기).
- 한 장면만 손으로: `node prototype/scripts/measure.mjs --db <저장소> --out <새 폴더> --from <분> --to <분> --capture-only --capture-size 1920x1080 --capture-pick "<uid>[@칸 참조]" [--capture-echo yes]` 또는 `--capture-script <걸음.json>`. 결과의 `시작-장면.json`의 `ask_failures`(앱 틀의 `askFailures`)가 비어 있어야 한다.
- 계약 검사 `app/test/contract_real_engine_test.dart`는 진짜 DLL + 진짜 저장소로 돌고, 부품이 실제로 보내는 꼴(double)로도 묻는다.

## 한 벌 P3 · P4 — 엔진이 짓고, 엔진 하나로 넣고 빼기 (2026-10-22 ~ 23)

배치 셈(DLC 읽기 · 모델 · 줄 배정 · 내보내기 모듈 스물)을 엔진의 `lay`(Rust)로 줄 그대로 옮겼다. 저장소는 엔진이 짓고(배치도 엔진이 셈 · 달력 표를 저장소 안에), 앱의 DLC 넣기 · 빼기 · 끄기 · 켜기 · 판 올림 뒤 시드 잇기 · 메이커 미리보기는 엔진의 `add_pack` · `remove_pack` 하나다(Node 없음 · 휴대폰도). 계획 `../docs/계획-한벌-P3-Rust배치.md` · `../docs/계획-한벌-P4-원본-트랙별.md` · 계약 1절 · 2-7 · 2-7-1 · 인수인계 5-4.

```powershell
# 달력 표(−3500 ~ 2500년 · 보조 달력 다섯 — 이 Node의 ICU로) → results/calendar-cache.json(공용 표 — 검사 도구는 갈지 않고 제 임시 사본에 뜬다)
node scripts/warm-calendar.mjs
# 저장소 짓기: 엔진이 배치하고 짓는다(--calendar 필수 · 기본 범위보다 좁은 표는 거절 · '오늘'은 시간대를 적은 글 — Z는 거절 · 없으면 지금을 +09:00으로)
engine/target/release/archive-tool.exe build data/<새 폴더>/archive.db <기본팩.htpack|.json> [<얹는 DLC>…] --calendar=results/calendar-cache.json [--now=2026-10-22T12:00:00+09:00]
# 릴리즈 · 꾸러미의 저장소(동아시아 · 등불 연대기)를 한 번에 — 표가 없으면 그 자리에서 뜬다
node scripts/build-showcase.mjs <새 폴더> [--calendar=<표>] [--now=<시각>]
# 넣고 빼기(앱과 같은 몸 — 그 저장소를 연 앱은 닫고) · 원본 꺼내기 · DLC 파일 읽어 보기
engine/target/release/archive-tool.exe add-pack <저장소> <파일.htpack>… [--from-store=<다른 저장소> --ids=<id,…>]
engine/target/release/archive-tool.exe remove-pack <저장소> <DLC id> [--delete]
engine/target/release/archive-tool.exe pack-out <저장소> <DLC id> <꺼낼 파일.htpack>
engine/target/release/archive-tool.exe check-pack <파일.htpack> <풀어 쓸 파일.json>
# 정답지(Node 내보내기)와 견줌 — 엔진 검사 전에 정답지를 다시 뽑는다(머리의 rules · icu가 낡으면 엔진 검사가 멈춘다) · 두 길로 지어 같은지
node scripts/layout-oracle.mjs
node scripts/build-check.mjs --only=lantern,east-asia
```

- 앱을 띄우는 검사 · 그림 뜨기는 **늘 `--memory-dir=<폴더>`**(판정 R50 — 감독의 `%APPDATA%` 기억을 건드리지 않게): `scripts/measure.mjs`는 `<결과 폴더>/_memory`를 스스로 넘기고(`--capture-only`도), `d4-app-capture.mjs` · 연기 검사(`release/smoke-windows.ps1` A · B)도 그렇다. 앱을 손으로 띄워 시험할 때도 붙인다.
- `node scripts/add-dlc.mjs`는 정답지 · 비교용으로만 남았다(위 '4단계 1걸음'의 경고 — 그 도구의 다시 짓기는 달력 표 없는 저장소를 짓는다). 엔진 검사는 빠른 빌드(`$env:CARGO_PROFILE_RELEASE_LTO='false'; $env:CARGO_PROFILE_RELEASE_CODEGEN_UNITS='16'; $env:CARGO_PROFILE_RELEASE_INCREMENTAL='true'`)로, 공식 LTO는 합칠 때만.

## 휴대폰에서 DLC 넣기 — 감독이 실기기에서 해 볼 차례

**이 길은 에뮬레이터(x64)와 Windows 앱에서만 돌려 봤고 실제 휴대폰에서는 아직 한 번도 돌려 보지 않았다.** 아래 차례대로 해 보고 걸린 곳(알림 글 · 그림)을 알려 주시면 된다. 안드로이드 판은 판타지 판(바탕 = 등불 연대기 — `release.yml`의 `ANDROID_SEED`)이다.

1. **APK 깔기**: 이 묶음이 든 판의 `HistoryTimeline-<판>-arm64.apk`(릴리즈 · 또는 `scripts/build-android.ps1`로 지은 것)를 휴대폰에 옮겨 연다(알 수 없는 출처 허용). 처음 켜면 든 저장소(등불 연대기)를 앱 폴더에 놓는다.
2. **DLC 파일을 휴대폰에 두기**: 메이커가 저장한 `.htpack`(예전 형식 그대로 — 예: Windows 포터블의 `도구\prototype\results\compat\east-asia.htpack`(동아시아 기본팩 — 판타지 판에서는 보통 DLC로 든다)이나 KoreanTimeLine)을 USB · 클라우드로 휴대폰의 내려받기 폴더 등에 둔다.
3. **넣기**: 연표를 길게 눌러 여는 차림표 → `DLC 관리` → 위 칸의 `📂 파일에서 더하기…` → 시스템 고르기 창에서 파일을 고른다(여럿도 된다). 위 칸에 진행이 보이고, 끝나면 카드가 서고 연표에 그 DLC의 줄이 자라난다. 예전 배치 파일(`.htlayout`)을 고르면 알림만 뜬다.
4. **끄기 · 켜기 · 지우기**: 카드의 스위치로 끈다(연표 · 검색 · 날짜 칸에서 아예 빠짐 — 원본은 앱 안 보관함에) · 다시 켠다 · 카드를 골라 자세히의 `DLC 삭제`로 지운다(원본까지 · 꺼 둔 DLC도 지울 수 있음). 바탕(등불 연대기)은 화면에서만 켜고 끄며 지울 수 없다.
5. **거절 알림 보기**: 같은 DLC의 낮은 판 · 날짜가 범위 밖인 DLC 같은 것을 넣으면 쉬운 말의 까닭과 할 일이 위 칸에 뜨고 연표는 그대로여야 한다.
6. **판 올림 뒤 확인할 것**: DLC를 넣고(하나는 꺼 두고) 다음 판 APK를 **위에 덮어 설치**한 뒤 켠다 — 넣어 둔 DLC의 카드 · 줄이 그대로이고, 꺼 둔 DLC는 꺼진 채이고, 지운 DLC는 되살아나지 않아야 한다(앱이 켤 때 새 판의 기본 자료에 옮겨 넣는다 — 실패하면 옛 저장소를 그대로 두고 알린다). **덮어 설치가 '서명이 다름'으로 막히면 여기서 멈춘다** — 지우고 깔면 앱 안의 자료(넣은 DLC 포함)도 지워진다. 릴리즈 APK는 디버그 키로 서명해 판마다 키가 다를 수 있으니(확인 안 함), 이 확인은 같은 PC에서 지은 두 판으로 하는 편이 안전하다.

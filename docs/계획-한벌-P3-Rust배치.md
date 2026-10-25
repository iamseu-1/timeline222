# 한 벌 P3 — 셈 한 벌: 배치를 Rust로 구현 계획

> **에이전트 작업자에게:** 필요한 하위 방법 — `superpowers:subagent-driven-development`(권함) 또는 `superpowers:executing-plans`로 과제를 하나씩 해 나갑니다. 걸음은 체크 상자(`- [ ]`)로 표시합니다.

**목표:** 지금 Node가 하는 배치 셈(DLC 읽기 · 모델 짓기 · 줄 배정 · 내보내기 모듈 스물)을 엔진(Rust) 안으로 옮겨, Node 없이 저장소를 짓고(이 계획) 닿는 트랙만 다시 셈할 수 있게 한다(P4 C 걸음이 씀).

**짜임:** 웹 코드(`js/core.js` · `js/timeline.js` · `js/wiki.js` · `js/group-tree.js`)와 내보내기 모듈(`prototype/scripts/export/*.mjs`)을 **줄 그대로** 엔진의 새 모듈 `lay`로 옮긴다. 모델과 연표 상태(`tl`)는 **JS 값 그대로**(동적 값 `V` — 열쇠 차례 · 수 글 · UTF-16까지 JS와 같게)로 들고 다녀 옮긴 줄이 원본 줄과 하나씩 대응하고, 모듈 출력(`out`)은 처음부터 `serde_json::Value`로 쓴다. 맞음은 **지금 Node 내보내기를 정답지로** 세 이음매에서 기계로 잰다 — ① 정규화된 팩 JSON ② 준비 · 줄 배정 덤프 ③ 모듈 앞자리 k개까지의 출력(3판 배치 JSON). 모듈은 내보내기 차례(`MODULES`)대로 옮기고 진척을 k/20으로 잰다.

**쓰는 것:** Rust 2021 · serde_json(입출력) · flate2 · sha2 · regex 1.13.1(감독 허락 2026-10-16) · Node 24(정답지) · 지금 웹 코드(읽기만).

**설계:** `docs/설계-한벌-체제-목업판-ClearType.md` 3-3절(이 계획이 그 절을 구현합니다) · 4 · 5 · 6 · 7 · 9절. P4 계획 `docs/계획-한벌-P4-원본-트랙별.md`(과제 16 · 17이 그 인터페이스와 맞물림). 독립 점검 `Fable`(2026-10-15 — 반영함).

## 전체 제약

* 답 · 주석 · 문서는 한국어.
* **정답지는 고치지 않는다** — Node 내보내기 결과가 정답이다. 웹 코드 · 내보내기 모듈은 **읽기만**. 예외는 과제 4의 이식성 손질(목록에 적은 것만 · 그 차이를 적음).
* **줄 그대로 옮긴다** — JS 함수 하나 = Rust 함수 하나(이름은 snake_case로 같은 뜻 — `_layoutTrack` → `layout_track`), 절 차례도 같게. 옮긴 Rust 파일 머리말에 원본 파일 · 줄 범위 · SHA-256 앞 12자. 한 파일이 1,500줄을 넘으면 JS 절 경계로 나눈다.
* 같음의 기준: 열쇠를 정렬해 견주어 **차이 0**(수는 f64로 정확히 · 배열은 차례대로 · `json` 열쇠의 JSON 글은 풀어서 견주고, 과제 13 끝에는 바이트로도). '거의 같음'은 없다.
* **'오늘'과 시간대는 입력이다** — 진행 중 정권의 끝(`HT.CURRENT_YEAR` · `HT.NOW_T`)과 문서의 나이(`[age]` — `wiki.js`)가 **지역** 연 · 월 · 일에 달리고, `[date]`는 그 시각의 **UTC** 날짜(`toISOString` — 시간대와 무관)다(과제 3 · 12a 확인). 정답지는 `2026-10-15T12:00:00+09:00` · 시간대 `Asia/Seoul`로 고정해 뽑고(파일 머리에 적음), Rust는 `Opts.now_ms` · `tz_min`(540)으로 받는다. 저장소에는 지은 날을 `meta.now`로 굳힌다(P4가 씀).
* 정답지의 보이지 않는 입력도 같게: `HT.F4.split = true`(`base.mjs`의 `bootWeb`) · `buildModel(…, { groupBands: true })` · 글자 폭 흉내(UTF-16 길이 × 7).
* 새 크레이트는 넣지 않는다(계약 0절) — 열쇠 차례를 지키는 객체 · JSON 읽기/쓰기는 손으로 짠다. **정규식만 예외 — `regex` 1.13.1을 감독이 허락했다**(2026-10-16 "추천대로" · 정한 것 #8).
* 옆 세션: 리메이크의 남은 것(줄 높이 · 예속 칸)이 배치 규칙 파일을 더 바꿀 수 있다 — 시작 조건을 과제마다 적었다. 리메이크가 그 파일을 바꾸면 '그 JS 커밋 → 정답지 다시 뽑기 → 같은 차이만큼 Rust 고침'이 한 짝이다.
* 줄 끝 LF. 작업 폴더: 처음엔 옛 저장소 `D:/Timeline/.claude/worktrees/p34` · `p34-lay`(옛 master 188ce86에서 갈래)였고, 2026-10-21부터 새 작업본 `D:/HistoryTime`의 가지 `p34` · 통합 가지 `p34-lay`와 갈래마다의 `.claude/worktrees/p34-*`로 옮겨 이었다(과제 M · M2 — 옛 커밋은 이력 없이 파일만 옮김이라 아래 옛 커밋 이름은 옛 저장소의 것). 커밋은 `git -c user.name=timeline -c user.email=timeline@local -c core.autocrlf=false commit`, 글은 한국어로 제목 한 줄 + 바뀐 것 세 줄 안 + `— 검사:` 한 줄 + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
* 빌드 · 검사: `powershell -File prototype\scripts\dev.ps1 engine-test -Junction <연결 폴더 이름> -Flutter D:\flutter-sdk\flutter\bin\flutter.bat`(엔진 전부 — 연결 폴더는 `%TEMP%\<이름>` · 작업 폴더마다 따로) · 하나만 `cd $env:TEMP\<이름>\engine; cargo test --release --locked --test <이름>`. 검사용은 빠른 빌드(판정 R38 — `CARGO_PROFILE_RELEASE_LTO=false` · `CODEGEN_UNITS=16` · `INCREMENTAL=true`) · 공식 LTO는 합칠 때만. 정답지는 `node prototype/scripts/layout-oracle.mjs …`(작업 폴더에서 — 도구가 자료마다 시간대를 고정한 자식 프로세스를 띄움 · 정답지 머리의 `rules` · `icu`가 지금 원본 · 잘린 달력 표와 다르거나 정답지가 없으면 엔진 검사가 '정답지가 낡음'으로 멈춤 — 과제 testinfra · 공식 검사 전에 꼭 다시 뽑기).
* 검사는 바뀐 것에 맞는 것만. master 합치기 · 릴리즈는 따로 승인.

### 옮기는 규칙(과제 3 이후 모두가 따른다)

| 자바스크립트 | Rust(`lay::js`) | 함정 |
| --- | --- | --- |
| 모델 · 연표 상태(`tl`)의 값 | `V` — `Undef` · `Null` · `Bool` · `Num(f64)` · `Str` · `Arr` · `Obj` · `Map` · `Set`(배열 · 객체 · Map · Set은 `Rc<RefCell<…>>`) · 형 붙은 꺼내기 `v.num("k")` · `v.str("k")` · `v.arr("k")` · `v.obj("k")` | 객체 같음(`===`)은 `Rc::ptr_eq` · 같은 객체를 여럿이 나눠 가지는 곳(`contextOf`는 띠는 같은 객체, 트랙 · 사건은 사본)을 그대로 |
| 모듈 출력 `out` | `serde_json::Value`(열쇠 차례는 견주지 않음) | 항목 기록의 `json` 글만 `js::stringify`(JS 차례)로 |
| 객체 열쇠 차례 | `Obj`는 **정수 모양 열쇠(0 ~ 2³²−2)를 오름차순으로 먼저, 나머지는 넣은 차례** | `x_metro.alts` 같은 곳 · `Object.keys` 순회 |
| `JSON.parse` · `JSON.stringify` | `js::parse(&str) -> V` · `js::stringify(&V) -> String`(손으로) | undefined 열쇠는 빠짐 · NaN/Infinity → null · 수 글은 JS 꼴(`5`, `1e+21`, `5e-7`) |
| `String(n)` · 글 잇기의 수 | `js::num_str(f64)` | 늘 이 함수로 |
| `Math.round(v)` | `js::round(v) = (v + 0.5).floor()` | Rust `round()`는 −2.5 → −3 · 기원전 분에서 어긋남 |
| `Math.max/min(…)` | `js::max` · `js::min` | NaN이 하나라도 있으면 NaN · 빈 인자는 −Infinity/Infinity |
| `a \|\| b` · `a ?? b` · `!x` | `js::or` · `js::nullish` · `js::truthy` | 0 · −0 · NaN · 빈 글 · null · undefined · false가 거짓 |
| `Number(x)` · `parseInt` · `parseFloat` · `String(x)` | `js::to_num` · `js::parse_int` · `js::parse_float` · `js::to_str` | `Number('')=0` · `Number(null)=0` · `Number(undefined)=NaN` · `parseInt('12a')=12` |
| `x \| 0` · `x >>> 0` · `<<` | `js::to_i32` · `js::to_u32` | 2³¹ 넘는 값의 감김 |
| `s.length` · `slice` · `charCodeAt` · `[i]` · 글 비교 `<` | `js::Str`의 UTF-16 함수(`len16` · `slice16` · `code_at` · `cmp16`) | 확장 한자(𠀀 …)는 JS에서 2 — `chars().count()` 금지 |
| `arr.sort(cmp)` | `js::sort(&mut Vec<V>, cmp)`(안정 · 비교가 NaN이면 0) | 비교 없는 `sort()`는 UTF-16 글 차례 |
| `new Map` · `new Set` 순회 | `js::Map` · `js::Set`(넣은 차례 · 열쇠 같음은 SameValueZero) | `Map`의 열쇠가 객체면 `Rc` 같음 |
| 정규식 | `regex`(감독 허락 — 기능 최소: `std` · `perf` · `unicode-case`만) | JS `\s`는 `\uFEFF`와 유니코드 빈칸 전부 · JS `\w` `\d` `\b`는 ASCII(Rust 기본은 유니코드 — `(?-u:\w)`로) · JS `.`은 `\n` `\r` U+2028/2029에서 안 맞음(Rust는 `\n`만 — `[^\n\r\u2028\u2029]`로) · `i` 깃발의 유니코드 접기 · 되돌아보기 · 뒤참조 없음(그곳만 손으로). 정규식마다 표본 글 벡터(과제 3 · 12a) |
| `Date`(분 셈 `minute`) | `js::minute(y)` — 날짜 → 일수(서기 0년 없음 · year < 0 → year + 1) 공식 | Date 범위 밖은 NaN → null |
| `new Date()`의 지역 연 · 월 · 일 | `ctx.local_ymd()`(`now_ms` + `tz_min`) | 시간대가 바뀌면 다른 날 |
| 화살표 함수 · 콜백 | Rust 클로저(값 `V`가 아님) | `this` 대신 `&mut Ctx` |
| 다 쓴 모델 그래프 풀기(JS는 GC) | `Ctx`의 Drop만 — **모듈은 `js::release`를 부르지 않는다** | `release`는 닿는 그릇을 모두 비운다 — 모듈이 부르면 모델 · `ctx.shared` 같은 공유 그릇까지 비어 뒤 모듈이 틀어진다(갈래 C의 알림 · 과제 Y). 바꿔 끼운 값(REPLAY의 `Sub`)도 풀지 않고 버리기만 |
| JS라면 TypeError로 멈출 곳 | `Err`(또는 `model::util::fault` — 모듈은 제 몫 끝에서 `m::kit::fault_check`로 오류로) | 조용히 빈 값 · 0으로 이어 가지 않는다 — 정답지가 밟지 않는 길이라도 다른 답 대신 오류 |

## 계획에서 정한 것

| # | 물음(설계 9절 · 조사 · 점검) | 정함 | 까닭 |
| --- | --- | --- | --- |
| 1 | 옮길 크기 | 설계의 '6,400줄'은 모듈만이다. 실제는 **약 1만 4천 줄**: 읽기(형식 4 내림 335 + `normalizePack` 1,224 + 도움 함수 약 2,000) · 모델(`buildModel` 983 + `link*` 925 + 도움 약 300) · 줄 배정(`_layoutTrack` 548 + 둘레 약 600) · 날짜 칸 · 판(약 330) · 모듈(6,200 + `kin` 523) · `wiki.js` 783 · `group-tree.js` 634 | 조사(seogo-tag 4d42ed1 · 지금 master에 있음). 위험 절 |
| 2 | 값을 어떤 꼴로 옮기나 | **모델 · `tl`은 JS 값 그대로(동적 `V`) · 출력 `out`은 `serde_json::Value`** · 형 붙은 꺼내기 함수로 반복을 줄임 | 이음매 ②가 `tl` 안까지 덤프하므로 안쪽 짜임이 JS와 같아야 한다. 지금 자료는 작다(동아시아 + KTL: 트랙 5 · 줄 47 · 띠 136 · 사건 214 — Node 모듈 몫 0.2초). 형으로 바꿔 빠르게 하는 것은 천만 측정(P4 과제 11) 뒤 뜨거운 곳만 · 과제 16에서 메모리 정점도 잰다 |
| 3 | 정답지 이음매 | ① 정규화된 팩 = `JSON.stringify(HT.normalizePack(raw).pack)` ② 준비(줄 배정 전) · 줄 배정(뒤)의 `tl` 덤프 — 두 쪽이 같은 **덤프 규칙**(`seam`)으로 적음 · 두 번째 만남은 `{"$ref":"<uid>#<처음 경로>"}`(경로를 늘 붙여 사본 둘이 모호하지 않게) ③ 모듈 앞자리 k개만 돌린 `runModules` 출력 | 모델은 고리가 있어 JSON이 아니다. 앞자리만 돌려도 늦은 차례 · 모듈 사이 가져오기(상수 · 함수뿐) · REPLAY가 깨지지 않음을 점검이 확인 |
| 4 | **P3의 정확한 차례**(설계 9절) | 틀(1 ~ 3) → 정답지 손질(4) → 읽기(5a ~ 5c) → 모델(6) → 줄 배정(7) → 모듈을 `MODULES` 차례(`tracks` `axis` `bands` `strips` `events` `hangs` `figures` `rails` `links` `scopes` `labels` `minibars` `docs` `calendar` `entities` `power` `variants` `boards` `metro` `lens` — 과제 8 ~ 15) → 부분 셈(16) → Rust로 짓기(17) → 앱 다시 잇기(18) | 모듈 사이 의존(`bandOf` · `catNo` · `rails` 가져오기 · `docs` → `entities` · REPLAY → `variants` → `lens`)이 이 차례를 따른다. 앞자리 k 출력이 곧 진척 |
| 5 | **앱 `layout.dart`의 다시 잇기를 언제 걷나**(설계 9절) | **마지막 과제(18)** — Rust로 짓기(17) 뒤, 리메이크가 `scene/layout.dart`를 놓은 뒤. **보기 상태와 무관한 것만** 엔진 답으로(줄 깃발 비트 풀기 · 그릇 머리 · 발 · 매달림 수 · 그릇 부모 · 문화권 자리). **줄 쌓기(몇 px)는 Dart 한 곳에 남긴다** — 설계 3-3의 그 줄을 고치고 감독 확인(과제 18) | 쌓기는 접힘 · 밀도 · 조감 · 켠 단 · 렌즈에 따라 실시간으로 바뀐다. 엔진은 '어느 줄에 무엇'(줄 배정)만, 앱은 '몇 px'만 — 셈이 두 벌이 되지 않는다(점검 찬성) |
| 6 | 형식 4만 읽나(설계 2절 #5) | **정함(2026-10-16 감독 "추천대로"): 형식 1 ~ 4를 모두 받는다** — 휴대폰도 지금 메이커가 저장한 파일을 바로 넣는다. 형식 4는 `HT.F4.down`으로 옛 꼴로 내려 **옛 읽기기(`normalizePack`)를 그대로 탄다** — 그래서 Rust로 옮기는 읽기기가 곧 형식 1 ~ 3 읽기기다. 이 세션의 추천: 형식 1 ~ 4를 모두 받음(리메이크 5단계 전까지 메이커는 형식 3으로만 저장하므로, 아니면 휴대폰은 컴퓨터에서 바꿔 넣은 파일만 받음). 점검(Fable)은 반대: 감독이 정한 것을 다시 묻는 일 · 휴대폰에 옛 파일의 경고를 보여 줄 화면이 없음 → 입구에서 거절하고 `to-f4` 도구를 쓰자. 어느 쪽이든 코드는 같고 입구 한 줄만 다르다. 어느 쪽이든 **지금 메이커가 만든 DLC는 P3 · P4 뒤에도 넣어진다**(P4 계획 '옛 DLC의 약속') — 정답지 자료에 형식 1 · 3 · 4가 다 들어 있어 이 계획이 옛 형식 읽기를 정답지로 지킨다 | 감독 정함 |
| 7 | 달력 표(ICU가 엔진에 없음) | 꾸러미가 미리 뜬 표(`warm-calendar.mjs` · `calendar-cache.json`)를 **저장소 안 그림 표(`blobs` 열쇠 `calendar:table` · zlib)** 로 넣고 Rust가 `sliceTable`과 같은 규칙으로 잘라 쓴다. 짓기(과제 17)는 **모든 저장소에 전체 표를 통째로** 넣고(판정 R36 — 2026-10-22 고침: 처음 정한 '자료가 쓰는 해 ± 500년'은 휴대폰에서 '범위 밖 — 다시 짓기'를 부를 수 있어 버림 · 기본 −3500 ~ 2500년 · 달력 다섯 = zlib 뒤 약 27KB · `--calendar` 필수(기본보다 좁은 표는 거절 — 시험용 잘린 표만 `--calendar-narrow`) · 표 없는 저장소의 넣고 빼기는 `code: "calendar"`로 거절), **실제 보조 달력 날짜가 표 밖인 DLC는 Rust가 거절**(`code: "range"` — 판정 R62 · 보조 달력을 안 쓰는 DLC는 해가 표 밖이어도 받고 `calendar` 모듈이 겹치는 구간만 실음 — 과제 calclip · 판정 R61 · R64). 검사는 저장소 안의 잘린 표(`prototype/engine/tests/fixtures/lay/calendar-slice.json` — `calendar-slice.mjs`가 뜸)를 `Opts.calendar`로 넘긴다(git 밖 `calendar-cache.json`에 기대지 않음 — 판정 R18 · R24). | 넣고 빼기 때 따로 파일이 필요 없다 · 휴대폰도 같다 · Rust는 표를 넓힐 수 없다(점검) |
| 8 | 정규식(옮길 코드에 약 170곳 — `wiki.js` 86 · `core.js` 72 · 모듈 12) | **`regex` 1.13.1(이 PC 부품 저장소에 일가 — `regex-automata` · `regex-syntax` · `aho-corasick` · `memchr` — 가 있어 인터넷 없이 빌드)을 들인다 — 감독 허락(2026-10-16 "추천대로").** 조건: 뜻 차이 규칙(위 표) · 정규식마다 벡터 · 기능 최소(안드로이드 `.so` 크기를 적음). 처음 쓰는 과제가 `Cargo.toml`과 계약 0절에 예외로 적는다 | 계약 0절 '새 크레이트 없음'의 예외 — 감독 허락(점검 찬성) |
| 9 | ICU 정렬 · 수 글(`localeCompare` · `toLocaleString('ko-KR')`) | **JS 쪽을 먼저 손질**(과제 4 · 리메이크 세션에 알린 뒤) — 글 비교는 UTF-16 차례(`HT.cmp16`), 수 글은 손 함수(`HT.groupDigits`). 곳: `links.mjs:105` · `timeline.js:8523`(승계선) · `core.js:2120`(`coalitionsOf`) · `core.js:872`(`groups` 정렬) · `core.js:11947`(`capsOf` 도읍 — 정규화 길) · `docs.mjs:179 · 377` · `entities.mjs:1104`. 정답지가 달라지는 곳을 목록으로 남김 | Rust에 ICU 정렬이 없다. 한글 음절만이면 UTF-16 차례 = 가나다 차례 |
| 10 | REPLAY(`variants`가 변형마다 **모든 트랙**을 다시 배치) | 처음엔 그대로 옮겨 정답지를 맞추고(과제 14), 부분 셈(과제 16)에서 **그 변형의 트랙만** 다시 배치하게 줄인다 — 정답지로 같음을 지킨다. `variants.mjs`의 `restack` 자체 점검(이미 앱 식과 다름)은 Rust에서 **경고로만** | 변형은 트랙 하나에 딸린다. 줄이기 전에 맞춰야 차이를 좇을 수 있다 |
| 11 | 2판 굳은 자리(줄 기하 — 3판 앱은 안 씀) | 그대로 옮긴다(`_layoutTrack` 기하 약 140줄) | 정답지 차이 0을 지키는 편이 빼고 견주기를 고치는 것보다 싸다 |
| 12 | 부분 셈의 항목 기록 | `Scope::Tracks`에서도 **항목 기록(`entities` · `docs` · `calendar`의 기록)은 늘 전체**를 낸다 — P4는 uid · 지문으로 견주어 바뀐 것만 씀 | 찾을 글 · 사람 잇기 · 승계 글은 다른 트랙 · 다른 DLC의 모델에 기대 — 트랙만 돌리면 조용히 낡는다(점검) |

## 검토 초점

검사가 직접 겨누지 않으면 사용자를 가장 먼저 물 것 다섯(위에서부터). 줄마다 그것을 막는 검사를 그 코드의 과제에 넣었다.
1. **실행한 날 · PC의 시간대에 따라 진행 중 정권의 끝 · 문서의 나이가 달라져 Rust로 지은 저장소가 정답지와 어긋난다** → 과제 1(정답지 시각 · 시간대 고정 · 두 번 뽑아 같음) · 과제 3 벡터(`local_ymd`) · 과제 6 · 12a 정답지 대조.
2. **확장 한자(서로게이트 쌍)가 든 이름의 줄임 · 자르기 · 정렬이 JS와 달라진다** → 과제 3 벡터(UTF-16 길이 · 자르기 · 비교).
3. **기원전(음수) 연도의 분 셈 · 반올림이 1 어긋나 띠 끝이 하루 밀린다** → 과제 3 벡터(`minute` · `Math.round` 음수).
4. **비교가 같은(0) 항목 · NaN 비교의 정렬 차례가 바뀌어 줄 배정이 달라진다** → 과제 3 벡터(안정 정렬 · NaN 비교) · 과제 7 줄 배정 정답지.
5. **정수 모양 열쇠 객체의 차례 · JSON 수 글(5.0 → 5) · 정규식 뜻 차이로 항목 기록(json 글) · 문서가 달라진다** → 과제 3 · 12a 벡터 · 과제 13 항목 기록 정답지(풀어서 견줌 + 바이트 견줌 둘 다).

## 진행(2026-10-23 · 끝 문서 과제 — 장부 `D:/Timeline/.claude/worktrees/p34/.superpowers/sdd/계획-한벌-P3-Rust배치/progress.md`의 값)

아래 과제의 체크 상자는 이 표에 맞췄다. 걸음의 '— 검사:' 줄은 계획 때 적은 커밋 글의 틀이고, 실제로 잰 수는 이 표다(엔진 수는 그때의 엔진 검사 전부 통과 수 · 빠른 빌드(판정 R38 — 2026-10-22부터)는 적어 둠). '옛'은 옛 저장소 `D:/Timeline`의 커밋(이 저장소에는 옮김 커밋 M · M2로만 있음).

| 과제 | 끝 커밋 | 마지막 검사(장부) |
| --- | --- | --- |
| 1 정답지 틀 | 옛 29c84e3 | lay_same · 정답지 두 번 뽑아 바이트 같음 · serde_json `float_roundtrip` 회귀 검사 |
| 2 형식 4 같음 | 옛 4a99764 | f4-same-check(known 자료도 Rust가 제 정답지로 — 판정 R9) |
| 3 JS 값 층 | 옛 554684a | lay_js 벡터 전부(V8 반올림 — 판정 R10) |
| 4 정답지 손질 | 옛 89d4841 | oracle-diff 17벌 다른 곳 0 · maker-archive-check · 엔진 272 |
| 5a · 5b · S · 5c 읽기 | 옛 89febe0 · ef77d9d · fd5049f · 7d38f38 | 이음매 ① 팩 28 차이 0 · 벡터 1,136 · 엔진 278 |
| 6 모델 · 준비 | 옛 3d0e2c4 | prep 21자료 · 합성 자료 synth(R19) · 엔진 285 |
| 7 줄 배정 | 옛 0ec9281 | rows 21자료 · 갈래 표지 37 · 엔진 292 |
| M2 옮김 | 1b7bbdb | 52파일 블롭 그대로 · 엔진 344 · 무시 1 |
| 8-틀 | 3f69156 | 본보기 둘 · Node 흉내 504/504 · 엔진 373 · 무시 1 |
| 8 ~ 15 모듈(갈래 A ~ E) | 1750e70(합침) · E 덧붙임 b308fd9 | 엔진 408 · 무시 1 · `lay_out` 통째(앞자리 20/20 = Node 내보내기) |
| X 합성 자료 · Y 웹 함수 모으기 | 64ad115 · 8caae0f | 25자료 갈림 0 · 갈래 표지 98 · 엔진 418(빠른 빌드) · **공식 LTO 421 · 무시 1**(b71b5e8) |
| 16 부분 셈(16a · 16b) | 242ad86 · dccb84b · b50528e · 고침 d7818b4 · bc808b8 | 빠른 빌드 엔진 533 · 무시 7(d7818b4) · 고침 2회차는 고친 몫(lay_golden 2 · add_pack 관련 13 · lay_scope 10) · 공식 LTO 한 프로세스 `export(All)` 95 ~ 100ms |
| calclip 달력 표 밖 | 504e6ba · 4f08c11 | 빠른 빌드 엔진 475 · build-check 28자료 같음 |
| 17 Rust로 짓기 | 6cdd3df · 505f94c · f7422b4 · 시드 d3f1b24 · 3ba5e05 | build-check 24자료 Node 길 = Rust 길 · 누락 · 중복 0 · 1배 흔들림 범위 안에서 같음 |
| testinfra · fin(합친 가지) | 1059517 · b02c29e · e855c39 → p34-lay c3f9c3a | 빠른 빌드 엔진 537 · 무시 7(testinfra) · 합친 가지 0162003 엔진 535 · 무시 7 · fin은 고친 몫(add_pack 60 · 무시 5) |
| 18 앱 다시 잇기 | 2026-10-23 · 가지 `p3-18` | 끝(길 (가) — layout 읽기 답의 이름 붙은 칸 · 옛 길 = 새 길 검사 · 1배 전후 같음 · main 합치기는 감독 허락 뒤) |

남은 것: 없음 — 공식 검사(2026-10-23 · 인수인계 5-4)와 과제 18(5-17)까지 끝. 뒤는 릴리즈 · KTL 몫(인수인계 5-4) · 20만 판정(P4 과제 11).

---

## 지금 할 과제(새 파일만 — 리메이크와 겹치지 않음)

### 과제 1: 정답지 틀 — Node 뽑기 · 자료 목록 · Rust 견주기

**파일:**
* 만듦: `prototype/scripts/layout-oracle.mjs` · `prototype/scripts/oracle/seam.mjs`(덤프 규칙 — 과제 3의 벡터 도구도 가져다 씀) · `prototype/scripts/oracle/one.mjs`(자료 하나를 뽑는 자식 프로세스) · `prototype/fixtures/oracle/list.json` · `prototype/fixtures/oracle/*.htpack`(시험 DLC 다섯 — 아래) · `prototype/fixtures/oracle/nest-scene.f4.json` · `prototype/engine/src/lay/mod.rs` · `prototype/engine/src/lay/same.rs` · `prototype/engine/tests/lay_same.rs` · `prototype/engine/tests/common/oracle.rs`
* 고침: `prototype/engine/src/lib.rs`(`pub mod lay;` 한 줄) · `인수인계.md`(5절의 '한 벌 P3 · P4 진행' 절 — 없으면 만듦: P3가 옮기는(읽기만 하는) 웹 파일 `core.js` · `timeline.js` · `wiki.js` · `group-tree.js` · `export/*.mjs`와, 리메이크가 그 배치 규칙을 바꾸면 알려 달라는 부탁)

**인터페이스:**
* 만듦:
  * `node prototype/scripts/layout-oracle.mjs [--only=<자료>,…] [--seams=norm,prep,rows,out] [--upto=<모듈>]` → 자료마다 `one.mjs`를 **자식 프로세스로**(환경 `TZ=Asia/Seoul` · `HT_ORACLE_NOW`) 띄워 `prototype/results/oracle/<자료>/norm-<i>.json`(팩마다) · `prep.json` · `rows.json` · `upto-<모듈>.json`(앞자리 k — `--upto`가 없으면 스물 모두 = `upto-lens.json`)을 쓴다. 각 파일 머리(`$oracle` 열쇠)에 시각 · 시간대 · 원본 파일 SHA-256 앞 12자.
  * 덤프 규칙 `seam`(②에 씀 — 과제 3이 Rust로 같은 규칙을 짬): 깊이 우선 · 객체 열쇠는 JS 차례 · 함수 · undefined는 빠짐(배열 안이면 null) · NaN/±Infinity → null · `Map` → `{"$map":[[k, v],…]}` · `Set` → `{"$set":[…]}` · **이미 만난 객체 · 배열**은 `{"$ref":"<uid가 글이면 uid, 아니면 빈 글>#<처음 만난 경로>"}`(경로 = `tracks.0.periods.3` 꼴).
  * `list.json`: `[{"name":"…","base":{"sample":"sample-lantern"} | {"builtin":"east-asia"} | {"file":"…"},"extra":["…"],"optional":bool,"known":"…"}]`
  * Rust:
```rust
// lay/mod.rs
pub const MODULES: [&str; 20] = ["tracks","axis","bands","strips","events","hangs","figures","rails","links","scopes",
    "labels","minibars","docs","calendar","entities","power","variants","boards","metro","lens"];
pub struct PackIn { pub name: String, pub bytes: Vec<u8> }        // .htpack(형식 1~4) 또는 JSON 바이트 — 첫째가 기본 DLC
/// calendar: 달력 표 바이트(Store에 들지 않고 calendar_of가 돌려주기만 — Rc는 Send가 아님)
pub struct Opts { pub now_ms: f64, pub tz_min: i32, pub upto: Option<String>, pub scope: Scope, pub calendar: Option<std::rc::Rc<Vec<u8>>> }
pub enum Scope { All, Tracks(std::collections::BTreeSet<String>) }
// lay/same.rs
pub fn diff(a: &serde_json::Value, b: &serde_json::Value, limit: usize) -> Vec<String>; // "경로: 왼쪽 ≠ 오른쪽" 앞 limit개
// tests/common/oracle.rs
pub struct Fixture { pub name: String, pub inputs: Vec<std::path::PathBuf>, pub builtin: Option<String>, pub known: Option<String> }
pub fn fixtures() -> Vec<Fixture>;                       // 선택 자료(optional)가 없으면 빼고 알림 · known은 원본과 다르다는 표시일 뿐 — Rust는 그 자료도 제 정답지로 돌림(f4-same-check 전용)
pub fn oracle(f: &Fixture, file: &str) -> serde_json::Value; // 없으면 "먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs --only=<이름> …"로 실패
pub fn inputs(f: &Fixture) -> Vec<archive_engine::lay::PackIn>;
pub fn assert_same(f: &Fixture, what: &str, got: &serde_json::Value, want: &serde_json::Value);
pub fn opts(upto: Option<&str>) -> archive_engine::lay::Opts; // 정답지와 같은 시각 · 시간대(540)
pub fn only_keys(v: serde_json::Value, keys: &[&str]) -> serde_json::Value; // 최상위 열쇠 거르개(빈 목록 = 전부) — 과제 5a ~ 5c가 씀
```
* **견줄 자료(`list.json`)**: 기준 셋 — `lantern`(`samples/sample-lantern.json` · 형식 3) · `east-asia`(내장 — 과제 2가 `prototype/fixtures/oracle/east-asia.json`로 굳힘) · `east-asia+ktl`(`D:/Timeline/KoreanTimeLine-v1.0.5.htpack` · optional — 감독의 실자료라 저장소에 넣지 않음). 가상 묶음 — `east-asia+move` · `+nest` · `+dep` · `+d7` · `+sphere`(리메이크 시험 DLC — `D:/Timeline/.claude/research/stage2/`의 `remake/move-scene/move-scene.htpack` · `remake/nest/nest-scene.htpack` · `remake/floors/dep-scene/dep-scene.htpack` · `slice4/test-dlc/d7-test.htpack` · `sphere-e/data/sphere-test.htpack`를 `prototype/fixtures/oracle/`로 베낌 — 모두 2KB 안) · `nest-f4`(`nest-scene.json` — 저장소 안 유일한 형식 4 견본). 리메이크의 '이음 검사용 옛 파일 묶음'이 생기면 목록에 더한다.

- [x] **걸음 1: 실패하는 검사를 쓴다** — `tests/lay_same.rs`:
```rust
//! P3 정답지 견주기(lay::same): 열쇠 차례는 무시 · 배열은 차례대로 · 수는 값으로 정확히 · json 열쇠의 JSON 글은 풀어서.
use archive_engine::lay::same::diff;
use serde_json::json;

#[test]
fn key_order_is_ignored_but_array_order_is_not() {
    assert!(diff(&json!({"a":1,"b":[1,2]}), &json!({"b":[1,2],"a":1}), 5).is_empty());
    assert_eq!(diff(&json!({"b":[1,2]}), &json!({"b":[2,1]}), 5), vec!["b.0: 1 ≠ 2", "b.1: 2 ≠ 1"]);
}
#[test]
fn numbers_compare_by_value() {
    assert!(diff(&json!({"x":10}), &serde_json::from_str::<serde_json::Value>(r#"{"x":10.0}"#).unwrap(), 5).is_empty());
    assert_eq!(diff(&json!({"x":0.1}), &json!({"x":0.1000000001}), 5).len(), 1);
}
#[test]
fn json_text_under_json_key_is_parsed() {
    let a = json!({"entities":[{"uid":"u","json":"{\"a\":1,\"b\":2}"}]});
    let b = json!({"entities":[{"uid":"u","json":"{\"b\":2,\"a\":1}"}]});
    assert!(diff(&a, &b, 5).is_empty());
}
#[test]
fn missing_and_extra_keys_are_reported_with_path() {
    assert_eq!(diff(&json!({"t":[{"a":1}]}), &json!({"t":[{"a":1,"z":0}]}), 5), vec!["t.0.z: (없음) ≠ 0"]);
}
#[test]
fn limit_caps_the_report() {
    assert_eq!(diff(&json!([1,2,3,4]), &json!([5,6,7,8]), 2).len(), 2);
}
```
- [x] **걸음 2: 실패를 본다** — `cargo test --release --locked --test lay_same` → 컴파일 실패(`lay` 없음)
- [x] **걸음 3: `lay/mod.rs` · `lay/same.rs`를 쓴다** — `same::diff`: 둘 다 객체면 열쇠 합집합을 정렬해 차례로 · 배열은 길이가 다르면 `경로.length: n ≠ m`도 · 수는 `as_f64()`로 `==` · 열쇠 이름이 `json`이고 둘 다 `{`나 `[`로 시작하는 글이면 풀어서 · 열쇠 `$oracle`은 건너뜀 · 다른 종류면 `경로: <왼쪽 JSON> ≠ <오른쪽 JSON>`(값 글은 60자에서 자름).
- [x] **걸음 4: 통과를 본다** — `lay_same` 다섯 PASS
- [x] **걸음 5: 정답지 뽑기를 쓴다** — `one.mjs`(자식 프로세스 — 전역 스크립트를 한 번만 싣고 자료 하나만):
  * **`Date`를 흉내**: `globalThis.Date`를 감싸 인자 없는 `new Date()` · `Date.now()`만 `HT_ORACLE_NOW`의 시각, 나머지(인자 있는 생성 · 정적 함수)는 원래 것. `base.mjs`를 가져오기 **전에** 깐다(`core.js`가 실을 때 `new Date().getFullYear()`를 셈). 시간대는 부모가 준 `TZ=Asia/Seoul` — 시작할 때 `new Date(0).getTimezoneOffset() === -540`인지 확인하고 아니면 실패.
  * `base.mjs`의 `bootWeb` · `contextOf`(내장 팩은 `loadContext`처럼 `index.html`의 `packs/<이름>/` 스크립트를 돌려 `HT.getBuiltinPacks()[0]`).
  * `norm`: 팩마다 `JSON.stringify(HT.normalizePack(raw).pack)`(raw는 그때그때 새로 읽음 — `normalizePack`이 raw를 바꿀 수 있으므로).
  * `prep`: `HT.Timeline.prototype._layoutTrack`을 빈 함수로 바꾸고(`try … finally`로 되돌림) `contextOf` → `seam({tracks: tl.tracks, depth: tl.depth, cats: tl._cats, proxies: tl._proxies, cityUses: tl._cityUses, scopes: tl._scopes, model: ctx.model})`.
  * `rows`: `contextOf` 그대로 → 같은 덤프.
  * `out`: `--upto=<모듈>`이면 그 뒤 모듈을 `skip`에 넣어 `runModules`(앞자리마다 문맥을 새로 만듦 — 모듈이 `tl`을 바꾸므로) → `upto-<모듈>.json`.
  * 머리말에 쓰는 법 · 덤프 규칙 · 시각 · 시간대를 적는다.
- [x] **걸음 6: 시험 DLC를 들이고 정답지를 뽑아 본다** — 다섯 `.htpack` · `nest-scene.json`을 베끼고 `list.json`을 쓴 뒤 `node prototype/scripts/layout-oracle.mjs --seams=norm,prep,rows,out` → 자료마다 파일이 생김 · 같은 명령을 두 번 돌려 **바이트가 같은지**(SHA-256) 본다.
- [x] **걸음 7: 인수인계에 적는다**(위 '고침'의 절 · 다섯 줄 안).
- [x] **걸음 8: 커밋한다** — 제목 "한 벌 P3-1 정답지 틀 — 시각 · 시간대를 고정한 Node 뽑기 · 견줄 자료 · Rust 견주기", `— 검사: lay_same 5 · 정답지 두 번 뽑아 같음`

---

### 과제 2: 정규화된 형식 4 — 바꿔 넣기 도구 · 내장 팩을 파일로 · 같은 결과인지

**파일:**
* 만듦: `prototype/scripts/to-f4.mjs` · `prototype/scripts/f4-same-check.mjs` · `prototype/fixtures/oracle/east-asia.json` · `prototype/fixtures/oracle/f4/<자료>.htpack`
* 고침: `prototype/fixtures/oracle/list.json`(`@f4` 자료 · `east-asia`를 파일로)

**인터페이스:**
* `node prototype/scripts/to-f4.mjs <입력 .json | .htpack | builtin:<이름>> <출력 .htpack>` — `normalizePack` → `packToJSON` → `HT.F4.up` → 형식 4 JSON을 `HT.packFile.build`로 봉해 씀. `problems`를 표준 출력에. (옛 형식 파일을 컴퓨터에서 한 번 바꿔 넣는 도구 — 설계 2절 #5 · 3-4 끝.)
* `node prototype/scripts/f4-same-check.mjs` — `list.json`의 자료마다 ① 원본 그대로 ② 팩마다 `to-f4`로 바꾼 것으로 `runModules`(과제 1의 시각 · 시간대 · 자식 프로세스 · 모듈 스물)를 돌려 `lay::same`과 같은 규칙으로 견준다. 내장 팩은 ③ JSON으로 굳힌 것(`east-asia.json`)도 견준다. 다르면 경로 20개.

- [x] **걸음 1: 실패하는 확인을 먼저 돌린다** — `f4-same-check.mjs`를 먼저 쓰고 돌림 → `to-f4.mjs`가 없어 실패.
- [x] **걸음 2: `to-f4.mjs`를 쓰고 내장 팩을 굳힌다** — `east-asia.json` = `JSON.stringify(HT.getBuiltinPacks()[0])`(함수 · 순환이 있으면 실패로 알림).
- [x] **걸음 3: 확인을 돌린다** — 자료마다 ① = ② = ③이면 `list.json`에 `<자료>@f4`(팩을 `f4/`의 것으로)를 더한다. **다른 곳이 나오면 고치지 않는다**(`HT.F4.up` · `down`은 리메이크의 `core.js`): 경로 · 까닭을 이 계획 끝 '알게 된 것'에 적고 그 자료의 `@f4`를 `"known":"<까닭>"`로 표시하고, 리메이크 세션에 알린다(인수인계 절).
- [x] **걸음 4: 커밋한다** — 제목 "한 벌 P3-2 정규화된 형식 4 — 바꿔 넣기 도구 · 내장 팩을 파일로 · 같은 결과 확인", `— 검사: f4-same-check(자료 n · 같음 m · 다름 목록)`

---

### 과제 3: JS 값 층 — `lay/js.rs`(V · 열쇠 차례 · JSON · 수 글 · UTF-16 · 정렬 · 분 셈 · 지역 날짜 · 덤프)

**파일:**
* 만듦: `prototype/engine/src/lay/js.rs`(필요하면 `lay/js/` 아래로 나눔) · `prototype/scripts/js-vectors.mjs` · `prototype/engine/tests/fixtures/lay/js-vectors.json` · `prototype/engine/tests/lay_js.rs`

**인터페이스:**
* 만듦(이름은 '옮기는 규칙' 표 그대로): `V` · `Str`(`len16` · `slice16` · `code_at` · `cmp16` · `index_of16`) · `Arr` · `Obj`(`get` · `set` · `has` · `delete` · `keys` — JS 차례) · `Map` · `Set` · 형 붙은 꺼내기(`num` · `str` · `arr` · `obj` · `bool`) · `parse(&str) -> Result<V>` · `stringify(&V) -> String` · `num_str(f64) -> String` · `to_num` · `to_str` · `truthy` · `or` · `nullish` · `round` · `max` · `min` · `to_i32` · `to_u32` · `parse_int` · `parse_float` · `sort(&mut Vec<V>, impl FnMut(&V, &V) -> f64)` · `minute(f64) -> Option<i64>` · `local_ymd(now_ms: f64, tz_min: i32) -> (i32, u32, u32)` · `seam(&V) -> serde_json::Value`(과제 1의 덤프 규칙) · `to_json(&V) -> serde_json::Value` · `from_json(&serde_json::Value) -> V`

- [x] **걸음 1: 벡터를 뽑는 도구를 쓴다** — `js-vectors.mjs`(Node가 정답 · 시간대 `Asia/Seoul`):
  * `num`: `[0, -0, 1, -1, 0.1+0.2, 1e21, 1e-7, 5e-7, 123456789.125, 2**53+2, -2.5, 1/3, NaN, Infinity]` → `String(n)` · `JSON.stringify(n)`
  * `round`: `[-2.5, -2.4, -0.5, 0.5, 2.5, 1e15+0.5, -431287200.5]` → `Math.round`
  * `int`: `[2**31, 2**32+5, -1, 3.9, -3.9, NaN]` → `|0` · `>>>0`
  * `coerce`: `['', ' 12 ', '12a', '0x1f', null, undefined(글 'undefined'로 적음), true, '1e3']` → `Number` · `parseInt(_,10)` · `parseFloat`
  * `str`: `['임진왜란', '𠀀가', 'a𠀀b']` → `length` · `slice(1,3)` · `charCodeAt(1)` · 짝 비교(`<`)
  * `keys`: `JSON.stringify(JSON.parse('{"b":1,"2":0,"a":1,"10":2,"-1":3,"01":4}'))`
  * `sort`: 같은 값 열 개를 비교 `(a,b)=>a.k-b.k`로 · 비교가 NaN을 내는 경우 · 비교 없는 `sort()`(`['b','A','가','𠀀','a']`)
  * `minute`: `[-2500.5, -1, -0.5, 0, 1, 99.25, 1582.8, 1970, 2026.99, 300000]` → `base.mjs`의 `minute`
  * `local`: 시각 다섯(자정 앞뒤 · 해 바뀜) → 지역 `getFullYear` · `getMonth` · `getDate`
  * `json`: undefined 열쇠 · 배열 안 undefined · NaN · 중첩 · 정수 모양 열쇠가 든 객체의 `JSON.stringify`
  * `seam`: 고리가 있는 작은 객체 그래프(uid 있는 것 · 없는 것 · 같은 uid의 사본 둘 · Map · Set)의 덤프 — `oracle/seam.mjs`를 가져다 씀
  * `regex`(정한 것 #8 — 감독 허락 · Rust 검사는 과제 12a): `\s`에 `\uFEFF` · `\w`에 '가' · `.`에 `\r` · `i` 깃발 대소문자 — 뜻 차이 규칙의 표본
- [x] **걸음 2: 실패하는 검사를 쓴다** — `tests/lay_js.rs`: 벡터 파일을 읽어 갈래마다 Rust 함수의 답이 같다(수는 글로 견줌). 예:
```rust
#[test]
fn numbers_print_like_js() {
    for r in vectors()["num"].as_array().unwrap() {
        let n = decode_num(&r[0]); // "NaN" · "-0" · "Infinity"는 글로 적혀 있음
        assert_eq!(js::num_str(n), r[1].as_str().unwrap(), "{r}");
    }
}
```
- [x] **걸음 3: 실패를 본다 → 걸음 4: `js.rs`를 쓴다** — `num_str`는 `format!("{:e}", x)`(가장 짧은 되돌림 자릿수)에서 자릿수 · 지수를 뽑아 ECMAScript Number::toString 규칙(10⁻⁷ ≤ |x| < 10²¹이면 소수, 아니면 `1e+21` 꼴 · −0은 `"0"`)으로 다시 씀. `Obj`의 정수 모양 열쇠 = `"0"`이거나 `0`으로 시작하지 않는 십진 글로 값 ≤ 2³²−2.
- [x] **걸음 5: 통과를 본다** — `lay_js` 모두 PASS
- [x] **걸음 6: 커밋한다** — 제목 "한 벌 P3-3 JS 값 층 — 열쇠 차례 · 수 글 · UTF-16 · 정렬 · 분 셈 · 지역 날짜가 Node와 같다", `— 검사: lay_js(벡터 열한 갈래)`

**지금 할 과제의 끝의 모습:** 정답지를 언제든 같은 바이트로 뽑고, Rust가 그것과 견줄 틀 · 값 층이 서 있다. 형식 4로 바꾼 자료가 원본과 같은 배치를 내는지 안다. 웹 코드는 한 줄도 바뀌지 않았다.

---

## 시작 조건이 있는 과제

* **과제 4**: 리메이크 세션에 알리고(그 세션이 같은 웹 파일을 고치는 중이면 그 뒤로) 시작.
* **과제 5 ~ 7**: 지금 시작해도 된다 — 리메이크의 남은 둘(줄 높이 · 예속 칸)이 덜 닿는 곳. 과제마다 master에 맞추고 정답지를 새로 뽑은 뒤 시작한다.
* **과제 8 ~ 15(모듈)**: **시작 조건 찼음**(2026-10-16 감독 "리메이크 배치 규칙은 끝" — master `b89094e`에서 규칙 파일(`core.js` · `timeline.js` · `wiki.js` · `group-tree.js` · `export/*`)이 `829a44a` 뒤로 그대로 · 리메이크의 남은 것 가운데 줄 높이 · 움직임 · 1배 확인은 새 앱 쪽). 남은 예속 칸(명목 섬김) · 메이커 미리보기가 규칙 파일을 바꾸면 'JS 커밋 → 정답지 다시 뽑기 → 같은 차이만큼 Rust 고침' 한 짝으로 흡수한다.
* 아래 JS 줄 번호는 seogo-tag 4d42ed1 기준(지금 master에 같은 내용) — 시작할 때 함수 이름으로 다시 찾는다.

### 과제 4: 정답지 손질 — 옮길 수 있게(JS 쪽 · 목록에 적은 것만)

**파일:**
* 고침: `js/core.js`(`HT.cmp16` · `HT.groupDigits` 더함 · `coalitionsOf`(2120) · `groups` 정렬(872) · `capsOf` 도읍(11947)의 `localeCompare`) · `js/timeline.js`(승계선 `edges.sort` 8523) · `prototype/scripts/export/links.mjs:105` · `docs.mjs:179 · 377` · `entities.mjs:1104`(`toLocaleString('ko-KR')`) · **`js/group-tree.js:92`의 `localeCompare(…, 'ko')`**(계획 목록이 빠뜨린 정답지 경로 — 판정 R11로 같은 과제에서 `HT.cmp16`으로 · cmp16 벡터 8갈래)
* 만듦: `prototype/scripts/oracle-diff.mjs`(손질 전 · 뒤 정답지를 자료마다 견줘 다른 경로를 적음)

- [x] **걸음 1: 손질 전 정답지를 따로 둔다** — `layout-oracle.mjs` → `prototype/results/oracle-before/`
- [x] **걸음 2: 손질한다** — `HT.cmp16 = (a, b) => (a < b ? -1 : a > b ? 1 : 0)`(UTF-16 차례) · `HT.groupDigits = n => …`(정수부 세 자리마다 ',' — `toLocaleString('ko-KR')`과 정수에서 같음 · 소수는 기본 최대 소수 세 자리 반올림과 같게). 여덟 곳을 바꾼다.
- [x] **걸음 3: 차이를 본다** — `oracle-diff.mjs oracle-before oracle` → 자료마다 다른 경로. 그 목록을 커밋 글 · 인수인계에 적는다. 화면에서 보이는 차이(승계선 겹침 차례 · 도읍 차례)가 있으면 1배 그림 한 장을 감독 확인에 붙인다.
- [x] **걸음 4: 메이커 같음 확인** — `scripts/maker-archive-check.mjs`(메이커 일꾼도 같은 모듈을 씀) PASS.
- [x] **걸음 5: 커밋한다** — 제목 "한 벌 P3-4 정답지 손질 — 글 비교는 UTF-16 차례 · 수 글은 손 함수(ICU 없이 옮길 수 있게)", `— 검사: oracle-diff(다른 곳 n) · maker-archive-check`

### 과제 5a ~ 5c: 읽기 — 형식 4 내림 · `normalizePack`(이음매 ①)

**공통:**
* 만듦: `prototype/engine/src/lay/f4.rs`(`HT.F4`의 읽기 몫 — 공용 · `periodOf` · `organOf` · `groupOf` · `down` · `splitMoves`(`HT.F4.split = true`)) · `prototype/engine/src/lay/read/`(`normalizePack`과 그것이 부르는 `HT.read*` · `HT.normalize*` 도움) · `prototype/engine/src/lay/pack.rs`(`.htpack` 풀기 → `V` — 엔진의 `unseal`을 씀) · `prototype/engine/tests/lay_read.rs`
* 원본(seogo-tag 줄): `core.js` 3794 ~ 5017(`normalizePack`) · 5359 ~ 5825(`HT.F4` — 쓰기 몫 `up` · `objectOf` · `project`는 옮기지 않음) · 1 ~ 3793의 도움 함수(부르는 것만)
* 먹음: 과제 1 `PackIn` · `Opts` · 과제 3 `js`
* 만듦: `pub fn normalized(pack: &PackIn, opts: &Opts) -> Result<serde_json::Value>`(이음매 ①) · 안쪽 `fn normalize_pack(raw: V, ctx: &Ctx) -> Normalized { pack: V, errors: Vec<Note>, warnings: Vec<Note> }` · `fn f4_down(raw: V, warn: &mut dyn FnMut(String)) -> Result<V>` · 형식 입구(정한 것 #6의 답에 따라 4만 또는 1 ~ 4)
* 검사(`tests/lay_read.rs` — 과제마다 열쇠 거르개 `KEYS`를 넓힘):
```rust
mod common;
use archive_engine::lay;
use common::oracle::{assert_same, fixtures, inputs, opts, oracle};

/// 이음매 ①: 팩마다 정규화된 팩이 Node의 normalizePack과 같다 — KEYS의 최상위 열쇠만(과제 5a · 5b · 5c가 넓혀 감 · 끝에는 전부).
const KEYS: &[&str] = &[/* 과제마다 채움 */];
#[test]
fn normalized_packs_match_node() {
    for f in fixtures() {
        for (i, p) in inputs(&f).iter().enumerate() {
            let pick = |v: serde_json::Value| common::oracle::only_keys(v, KEYS);
            let got = pick(lay::normalized(p, &opts(None)).unwrap());
            assert_same(&f, &format!("norm-{i}"), &got, &pick(oracle(&f, &format!("norm-{i}.json"))));
        }
    }
}
```

* **5a — 머리 · 형식 4 내림 · 트랙 · 분류 · 민족 · 시대 구분 · 대범위 · 간지 · 모아 보기 판**: `KEYS` = `format` · `formatVersion` · `id` · `name` · … 머리 열쇠 · `tracks` · `categories` · `peoples` · `epochs` · `scopes` · `yearCycle` · `views`. 걸음: 검사(실패) → 옮김 → PASS → 커밋 "한 벌 P3-5a 읽기 ① 머리 · 형식 4 내림 · 트랙 · 분류 …", `— 검사: lay_read(5a 열쇠 · 자료 n)`.
* **5b — 띠 · 기관 · 왕조 · 문화 · 가문**: `+ periods`(지도자 · 도읍 · 칸 · 시기 · 지위 · 미정 · 이설 · 실재성 · 부분 승계) · `organs` · `dynasties` · `cultures` · `houses`. 커밋 "한 벌 P3-5b 읽기 ② 띠 · 기관 · 왕조 · 문화 · 가문".
* **5c — 사건 · 인물 · 이름 · 문서 · 단체 · 렌즈 재료**: `+ events` · `figures` · `names` · `surnames` · `places` · 사람 잇기 · 혈연 · 승계표 · 문서 · `images` · `groups` · `themes` · `institutions` · 나머지 → **거르개를 걷음(전부)**. 커밋 "한 벌 P3-5c 읽기 ③ 사건 · 인물 · 문서 · 단체 — normalizePack이 Node와 같다(이음매 ①)".

### 과제 6: 모델 · 준비 — `buildModel` · `link*` · `contextOf`의 준비(이음매 ② 앞)

**파일:**
* 만듦: `prototype/engine/src/lay/model.rs`(`buildModel` — `groupBands: true`) · `prototype/engine/src/lay/link.rs`(`linkHouses` · `polityFinder` · `linkFormat3` · `linkTreatySigners` · `linkPeople` · `linkOrder` · `linkDocImages`) · `prototype/engine/src/lay/ctx.rs`(`contextOf`의 준비 — 트랙 · 띠 · 사건 놓기(사건은 사본 · 띠는 같은 객체 — JS 그대로) · 인물 막대 · 도읍 쓰임 · `_setScopes` · `depProxies`(`depLook` · `depRel`) · 지역 날짜 `local_ymd`) · `prototype/engine/tests/lay_model.rs`
* 원본(seogo-tag 줄): `core.js` 7789 ~ 8771(`buildModel`) · 5326 ~ 5340 · 5882 ~ 6773 · 7709 ~ 7788(`link*`) · `prototype/scripts/export/base.mjs` 128 ~ 213(`contextOf`) · `timeline.js` 602 · 613 ~ 693 · 9084 ~ 9089

**인터페이스:**
* 먹음: 과제 5 `normalize_pack`
* 만듦: `pub fn prepared(packs: &[PackIn], opts: &Opts) -> Result<serde_json::Value>`(이음매 ② 앞 — `prep.json`과 같은 덤프) · 안쪽 `struct Ctx { packs: Vec<V>, model: V, tl: V, pack_of: …, track_pack: …, now_year: f64, now_t: f64, tz_min: i32 }` · `fn context_of(packs: &[PackIn], opts: &Opts, lay_tracks: bool) -> Result<Ctx>`

- [x] **걸음 1: 실패하는 검사를 쓴다** — `tests/lay_model.rs`: 자료마다 `lay::prepared(&inputs(&f), &opts(None))`가 `oracle(&f, "prep.json")`와 같다(`assert_same(&f, "prep", …)`).
- [x] **걸음 2: 실패를 본다 → 걸음 3: 옮긴다**(차례: `buildModel` 머리 · 팩 차례 · 분류 → `link*` → 띠 · 사건 · 인물 · 포개짐 · 문화권 차례 → `contextOf` 준비 → `depProxies`) **→ 걸음 4: PASS**
- [x] **걸음 5: 커밋한다** — 제목 "한 벌 P3-6 모델과 준비 — buildModel · link* · contextOf가 Node와 같다(이음매 ② 앞)", `— 검사: lay_model(자료 n)`

### 과제 7: 줄 배정 — `_layoutTrack`과 둘레(이음매 ② 뒤)

**파일:**
* 만듦: `prototype/engine/src/lay/track.rs`(`_layoutTrack` 단계 열여섯) · `prototype/engine/src/lay/rows.rs`(`chainRows` · `packChains` · `succRank` · `bandStart`/`bandEnd` · `G` 상수 · `_G` · `_hangsFolded` · `_precSpan` · `_placeAt` · `_extent` · `_dynOf` · `_figSpan` · `_foldedNow`) · `prototype/engine/src/lay/scope.rs`(`scopeOn` · `_scopeClaims` · `_scopeNodes` · `_scopeBranches` · `_scopePad`) · `prototype/engine/tests/lay_rows.rs`
* 원본(seogo-tag 줄): `timeline.js` 2822 ~ 3369(`_layoutTrack`) · 50 · 345 ~ 346 · 514 ~ 582 · 1757 · 1808 · 3706 ~ 3749 · 6807 · 7022 · 8850 · 9036 · 9091 ~ 9172. 글자 폭(`textWidth` · `inkBottom` · `altRowPlan`)이 이 길에서 불리는지 확인해 적는다 — 불리면 `Ctx.text_width = len16 × 7`.

**인터페이스:**
* 먹음: 과제 6 `Ctx` · `context_of`
* 만듦: `pub fn laid(packs: &[PackIn], opts: &Opts) -> Result<serde_json::Value>`(이음매 ② 뒤 — `rows.json`) · 안쪽 `fn layout_track(ctx: &mut Ctx, tr: &V)`

- [x] **걸음 1: 실패하는 검사를 쓴다** — `tests/lay_rows.rs`: 자료마다 `lay::laid(…)`가 `oracle(&f, "rows.json")`와 같다.
- [x] **걸음 2: 실패를 본다 → 걸음 3: 옮긴다**(단계 차례: 소속 · 숨김(그릇 claim · 고리 끊기) → 바탕 문화 → 민족 나무 · 정렬 · 깊이 → 북에서 남 → 그릇 가지 → 줄 만들기(울타리) → `rowPeriods` · 묶음 · 그릇 가지 → 가는 막대 단 → 밑깔림 → 기관 · 구역 탭 → 매단 이름표 줄 → 사건 줄 → 인물 줄 → 기하 → 줄 위치) **→ 걸음 4: PASS**
- [x] **걸음 5: 커밋한다** — 제목 "한 벌 P3-7 줄 배정 — _layoutTrack과 둘레가 Node와 같다(이음매 ② 뒤)", `— 검사: lay_rows(자료 n)`

### 과제 8 ~ 15: 모듈 — `MODULES` 차례로(이음매 ③)

**공통 꼴(과제 8 ~ 15가 모두 따른다):**
* 만듦: `prototype/engine/src/lay/m/<모듈>.rs`(JS 모듈 하나 = Rust 파일 하나 · `pub fn contribute(ctx: &mut Ctx, out: &mut serde_json::Value)` · 늦은 차례가 있으면 `pub fn contribute_late`) · 정답지 검사는 `prototype/engine/tests/lay_out.rs` 하나에 과제마다 검사 함수를 더함.
* 고침: `lay/mod.rs`의 `export`(모듈 목록 · 앞자리 `opts.upto`까지만 부름 · 늦은 차례 · 끝의 공통 점검 — `runModules` 그대로) · `pub const PORTED_PREFIX: usize`(옮긴 앞자리 수 — 과제 8-틀이 이름을 정함).
* 검사 함수(과제마다 그 모듈 이름으로 — 아래 표의 '앞자리' 모듈):
```rust
#[test]
fn upto_<모듈>_matches_node() {
    for f in fixtures() {
        let got = lay::export(&inputs(&f), &opts(Some("<모듈>"))).unwrap();
        assert_same(&f, "upto-<모듈>", &got, &oracle(&f, "upto-<모듈>.json"));
    }
}
```
* 걸음: ① master에 맞추고 정답지 `node prototype/scripts/layout-oracle.mjs --seams=out --upto=<모듈>` ② 검사 함수를 더해 실패를 봄 ③ 옮김(JS 모듈 파일 전부 · 그 모듈이 부르는 웹 함수) ④ PASS + 앞 과제 검사 전부 PASS ⑤ 커밋 — 제목 "한 벌 P3-<과제> 모듈 <이름들> — 앞자리 <k>/20이 Node와 같다", `— 검사: lay_out upto-<모듈>(자료 n)`.

| 과제 | 모듈(앞자리 k) | 함께 옮길 웹 함수 · 파일 | 원본 줄 수(약) |
| --- | --- | --- | --- |
| 8 | `tracks` · `axis` (2) | `_buildAxis`(`timeline.js` 4129 ~ 4320 — HTML 글 만들기는 빼고 정답지가 쓰는 셈만) · 문화권 차례(`core.js` 8739 둘레) | 630 |
| 9 | `bands` · `strips` (4) | — | 360 |
| 10 | `events` · `hangs` · `figures` · `rails` (8) | `rails`를 가져다 쓰는 함수(`events` · `figures` · `links`가 import) | 580 |
| 11 | `links` · `scopes` · `labels` · `minibars` (12) | `echoBands`(`timeline.js` 2440) | 590 |
| 12a | (벡터만) | `js/wiki.js` 전부(`lay/m/docs/wiki.rs` — docs 모듈만 부르므로 그 아래 · 과제 Y 확인) — 정규식마다 표본 글 벡터(`js-vectors.mjs`에 `wiki` 갈래) · 지역 날짜(나이 · `[date]`)는 `local_ymd` | 783 |
| 12b | `docs` · `calendar` (14) | 달력 표 자르기(`sliceTable` — `opts.calendar`의 표에서 · 표가 없으면 Err "달력 표 없음" · 자료 해 ± 100년이 표를 넘으면 겹치는 구간만 싣고 `note` — 과제 calclip(판정 R61)이 처음의 '범위 밖이면 Err'를 고침) | 630 |
| 13a | `entities` (15) — 띠 · 사건 · 칸 기록 | `entities.mjs`의 공통(`plain` · `x_` 풀이) · 띠 · 사건 · 칸 갈래. 검사는 `entities`를 그 갈래(kind)로 거름 | 700 |
| 13b | 〃 — 인물 · 가문 | 인물 · 가문 갈래 | 450 |
| 13c | 〃 — 승계 · 계보 | `prototype/scripts/export/kin.mjs`(`lay/m/entities/kin.rs` — entities만 부름 · 과제 Y 확인) | 520 |
| 13d | 〃 — 단체 · 제도 · 렌즈 · 문서 고리 → 전부 | `js/group-tree.js`(`lay/m/entities/group_tree.rs` — entities만 부름 · 과제 Y 확인) · 나머지 갈래. 끝에 거르개를 걷고 **`json` 글을 바이트로도** 견줌(검토 초점 5) | 980 |
| 14 | `power` · `variants` (17) | `variants`의 REPLAY(12모듈을 새 out으로 다시 돌림 · `relayout`은 모든 트랙 — 이 과제에서는 JS 그대로 · `restack` 자체 점검은 경고로만) | 620 |
| 15 | `boards` · `metro` · `lens` (20) | `_boardPlan` · `_boardVisit` · `_boardGroups` · `_boardBranch`(`timeline.js` 8872 ~ 9008) | 1,100 |

과제 12b의 달력: Rust는 늘 `opts.calendar`의 표만 쓴다 — 그 달력의 표가 없으면 거절하고, 자료 해 ± 100년이 표를 넘으면 겹치는 구간만 싣는다(과제 calclip · 판정 R61 — 처음 적은 '범위 밖이면 거절'을 고침 · 배치 거절은 실제 보조 달력 날짜가 표 밖일 때만 — 정한 것 #7 · 아래 '과제 calclip'). `opts.calendar`가 없을 때 git 밖 `prototype/results/calendar-cache.json`을 읽는 길은 없다. 검사는 커밋한 잘린 표(`prototype/engine/tests/fixtures/lay/calendar-slice.json` — `node prototype/scripts/calendar-slice.mjs`가 정답지 자료 · 읽기 벡터의 보조 달력 날짜 둘레와 calendar 모듈의 범위(자료 해 ± 100년 · 달력 다섯)를 뜸 · 선택 자료가 아닌 입력이 없으면 멈춤)를 `common::oracle::seam_opts`로 넘긴다(판정 R18 · 과제 8-틀 고침 R24 ①). Node 쪽(`calendar.mjs`)은 제 ICU로 뜨거나 넓은 표에서 자른다 — 잘린 표가 그 자름과 글자까지 같음은 `calendar-slice.mjs`가 뜰 때 견준다(`calendar-cache-check.mjs`와 같은 약속).

**과제 15의 끝:** `lay::export(…, upto: None)`이 자료 전부에서 Node 내보내기와 **차이 0**(설계 5절 P3의 첫 끝).

**넘길 몫(과제 7 — 2026-10-21 검토):**
* 과제 15 `boards`: `boards.mjs` `boardOne`(147 ~ 176줄)이 시대 구분마다 판을 세워 `_layoutTrack(btr)`을 부르고 영향받는 원래 트랙도 판이 선 채(`_boardTr` · `_boardOpen` · `_boardFolded`)로 다시 배치한 뒤 되돌린다 → `lay::track::layout_track`의 판 거절(`tr.board`)을 걷고 `_boardVisit` · `_boardGroups` · `_boardBranch` · 2942줄(판 트랙의 깊이) · 3343줄(묶음 틈의 `gp.from`)을 그 함수에 옮긴다. `_foldedNow`의 판 갈래(`lay::rows::folded_now`)의 첫 견줌도 `upto-boards`.
* 과제 15 `lens`: `lens.mjs` 102 ~ 119줄이 `themeLens`를 켜고 모든 트랙을 다시 배치한 뒤 되돌린다 → `HT.lensAny`(`lay::rows::lens_any` — 지도자 칸 자리)의 첫 견줌은 `upto-lens`.
* 과제 14 · 15: 같은 트랙을 다시 배치하는 멱등(이미 적힌 `_ps` 기억 · 열쇠 자리 · `_seamL` 다시 씀)의 첫 정답지 견줌은 REPLAY(`upto-variants`) · `upto-lens` · `upto-boards` — 과제 7은 '줄 배정을 마친 문맥에서 한 번 더 배치해도 `rows.json`과 같다'만 지킨다(`lay_rows::relayout_is_idempotent`).

**과제 8-틀(2026-10-21 · 판정 R20 · R21) — 모듈을 갈래 넷 ~ 다섯이 동시에 옮기는 틀.** 위 '공통 꼴'의 '앞자리 k개 출력이 Node와 같다'(`tests/lay_out.rs`에 과제마다 검사 함수)는 차례로만 할 수 있어 바꿨다:
* 정답지(`oracle/one.mjs`의 이음매 `mods` — 기본 다섯 이음매에 듦 · 있던 파일은 바이트 그대로): 문맥 하나에서 `contribute`를 `MODULES` 차례로 돌리며 모듈 k 뒤마다 **`pre-<k>.json`**(늦은 차례 전 out) · **`pre-<k>.shared.json`**(`ctx.shared`의 seam 덤프 — Map은 `$map` · Set은 `$set`) · 같은 자리의 사본에 앞자리 k개의 늦은 차례를 돌린 **`upto-<k>.json`**(스물 — `upto-tracks` · `upto-lens`가 `runModules`와 같음을 자체 점검 · `upto-lens`는 `out` 이음매의 것과 같은 바이트)을 찍고, 스물 모두 뒤 늦은 차례 하나마다 **`late-<모듈>.json`**(tracks · docs · power · metro — `late-metro` = `upto-lens`)을 찍는다. 자료 21개 · 약 16초 · 515MB(git 밖 · 있던 파일 포함).
* Rust(`lay/export.rs`): `lay::export(packs, opts)`(= `runModules` — 앞자리 `opts.upto`까지 contribute 전부 → 늦은 차례 → 공통 점검 · 옮기지 않은 모듈이 들면 거절) · **`lay::export_one(packs, opts, 모듈, seed_out, seed_shared) -> (out, shared 덤프)`**(문맥을 줄 배정까지 짓고 Node의 `pre-<k−1>`(+ `.shared`)을 심어 그 모듈의 `contribute` 하나만) · `lay::export_late(…)`(앞 `late-`를 심어 늦은 차례 하나만). `shared`는 모두 평범한 값(아래 표 — `$ref` 없음)이라 `shared_seed`가 되심고, `$ref`가 들면 거절한다.
* `lay/mod.rs`의 `MODULES`는 **모듈마다 한 줄**(`Module { name, ported, contribute, late }` — 모듈 파일 `lay/m/<이름>.rs`의 `PORTED` · 함수를 가리킴). 모듈 스물의 자리를 모두 미리 두었다(옮기지 않은 것은 `PORTED = false` · 거절만) — **갈래는 제 모듈 파일만 고친다**(`MODULES` · `m/mod.rs` · `tests/common/*` · `util.rs` · `rows.rs` · `scope.rs`는 손대지 않음 · 판 갈래의 `track.rs`는 갈래 E만). `PORTED_PREFIX`(옮긴 앞자리 수 — 모듈 파일의 `PORTED: bool`과 이름을 가름) · `ported_count()` · `module_index()`.
* 검사: 모듈마다 **`tests/lay_m_<모듈>.rs`**(이미 스물 모두 있음 — `common::modcheck::check_contribute(이름)` · 늦은 차례는 `check_late` · 옮기지 않았으면 정답지 파일이 있는지만 보고(풀지 않고) 건너뜀 · 정답지 자료 0이면 실패) · 통째 **`tests/lay_out.rs`**(`PORTED_PREFIX` 앞자리까지 `upto-<모듈>`과 차이 0 · 모두 옮겨지면 `upto-lens`). 둘 다 값(`same::diff` — 열쇠 차례 무시)에 더해 **`json` 열쇠의 글은 바이트로도**(`same::diff_json_text` — 고침 1회차 · 다르면 `entities.12.json(uid …)`과 처음 다른 바이트의 둘레). 하나만: `cargo test --release --locked --test lay_m_<모듈>`(dev.ps1에 더한 것 없음 — 이 한 줄이면 됨).
* 본보기: `tracks`(1/20 — 늦은 차례까지 · `lay/m/tracks.rs`)와 `minibars`(12/20 — 앞자리 11개의 Node 출력을 심는 길 · `lay/m/minibars.rs`)를 이 틀로 옮겨 PASS(자료 21개).
* 달력 표(고침 1회차 — R24 ①): `seam_opts`의 잘린 표(`tests/fixtures/lay/calendar-slice.json`)가 읽기 날짜 둘레에 더해 **`calendar` 모듈이 자료마다 자르는 범위(자료 해 ± 100년 · 달력 다섯 — `calendar-slice.mjs`가 `dataYears`를 옮겨 적어 셈)**까지 덮는다. 원문은 `lay::cal::Tables::raw(id)`(`{ intl, start, end, year0, months }`)로 — 갈래 C의 `calendar` 모듈이 `sliceTable`과 같은 규칙으로 자른다(`cal.rs`를 고치지 않고).
* 정답지의 자체 점검(고침 1회차): `mods` 이음매가 `upto-tracks` · `upto-lens` = `runModules`에 더해 **Node 흉내**(새 `contextOf`에 `pre-<k−1>`과 그 `.shared`를 심고 모듈 하나만 → `pre-<k>`와 바이트 같음 · 늦은 차례도)를 자료마다 돌린다 — Rust `export_one`의 전제('모듈 하나를 새 문맥에서 돌려도 같다')를 Node 쪽에서 먼저 지킨다. 이음매 `emul`(`--seams=…,emul` — 기본에 들지 않음 · 자료 21개에 약 1분 더).

**모듈 사이 의존(과제 8-틀 — 원본 `prototype/scripts/export/*.mjs`의 줄 번호 · 2026-10-21):** 모듈끼리의 고리는 ① `ctx.shared`(bands의 `bandOf`가 거의 전부) ② 앞 모듈이 실은 `out` 칸 ③ `rails.mjs` · `variants.mjs` · `kin.mjs`에서 가져오는 상수 · 함수 ④ 늦은 차례 넷의 차례(tracks → docs → power → metro — docs · metro가 같은 항목 기록 `json`을 차례로 고침) ⑤ REPLAY(variants · boards가 열두 모듈의 `contribute`를 새 out · 새 shared에 다시 부름)뿐이다. `shared`의 값은 모두 평범하다(`catNo` · `bandOf` · `railLevel` · `railRank`: 글 → 수 Map · `docsOf`: uid → `[{key, sub}]` · `cellDocsOf`: uid → `[글]` · `powerNominal`: 글 → 수 Set) — 모델 객체를 담는 shared는 없어 Node 덤프에서 그대로 심는다. 모듈이 `tl` · 모델 · 전역에 적는 것(모두 뒤 모듈이 읽지 않거나 되돌림 — 검토가 Node 흉내 504/504로 확인): `axis`의 `_buildAxis`(`tl.epochRows` · `eraRows` · `capRows` · 시대 구분의 `_lane`) · `variants`의 다시 배치(끝에 `relayout(tl, null)`로 되돌림) · `boards`(`tl.board` · `_boardTr` = null · `_boardUids` = null · `_boardOpen` = 빈 Set · `_boardFolded` = false로 되돌리고 원래 트랙을 다시 배치 · 되돌아왔는지 assert) · `lens`(`tl.themeLens` = 전 값(null)으로 되돌리고 다시 배치) · `docs`가 까는 전역 `HT.namu`(`js/wiki.js`) · `entities`가 쓰는 전역 `HT.groupTreeLayout`(`js/group-tree.js`) — 그래서 모듈 하나를 새 문맥에서 돌려도 Node의 같은 자리와 같다.

| k | 모듈(줄) | 쓰는 shared | 읽는 shared | 읽는 out 칸 | 가져오는 것 · 부르는 웹 함수(옮겨진 것은 ✓) | 늦은 차례 | REPLAY |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `tracks`(340) | `catNo`(146) | — | 늦은 차례만: `items`(279 · 288 — 구역 47 · 50) · `tracks[].rows`(281) · `periods`(297 · 311) · `cells`(299 · 329) · `events`(315) · `variants[].moves`(324) | `tl._scopePad`(208 ✓) · `tl._figSpan`(128 ✓) · `HT.datedAlts`(97 ✓) · `HT.sphereOf`(358 ✓ 이름 표 더함) | 있음(276) | 듦 |
| 2 | `axis`(72) | — | — | — | `tl._buildAxis`(15 — timeline.js 4129 ~ 4320 · `epochRows` · `eraRows` · `capRows`를 tl에 둠) · `ctx.trackIndex` · `ctx.packOf` | — | — |
| 3 | `bands`(103) | `bandOf`(33) | — | `periods.length`(82 — 순번) | `HT.historicityOf`(49) · `HT.kindFamily`(56) · `HT.POLITY_KINDS`(66) · `HT.historicityTag`(69) · `tl._hosted`(62 ✓) | — | 듦 |
| 4 | `strips`(234) | — | `bandOf`(80 — 필수) | `tracks[].rows[].organTop`(86 · 226) · `periods[bandOf]`(141 · 225) | `tl._dynOf`(156 ✓) · `HT.cellSpan`(40) · `HT.cellToNow`(41) · `HT.altDated`(69 ✓) · `HT.altFlipped` · `HT.altSpan`(69 · 70) · `HT.leaderLabel`(170 ✓ 기본 꼴) · `HT.datedAlts`(✓) | — | 듦 |
| 5 | `events`(105) | `catNo`(21 — 없을 때만) · **`railLevel` · `railRank`**(rails의 `railLevels`를 처음 불러 67 · 68) | `catNo`(19) · `bandOf`(41) | `categories`(20 — catNo 없을 때) | **rails.mjs** `railLevels` · `onRail` · `eventColor` · `eventUid`(5) · `tl._placeAt`(53 ✓) · `HT.atOf`(27 ✓) · `HT.cal.parse` · `HT.cal.formatT`(28 · 32 — 일부 ✓) · `HT.formatYear`(29) · `tr.eventByUid`(100) | — | 듦 |
| 6 | `hangs`(178) | — | `bandOf`(45 — 없으면 빈 Map) | — | `HT.altDated` · `altFlipped` · `altSpan`(27 · 28) · `HT.Timeline.depLook`(147 ✓) · `tr.overlays` · `underlays`(157 · 179) | — | 듦 |
| 7 | `figures`(122) | — | `bandOf`(73) | — | **rails.mjs** `lodOf`(5) · `HT.altFlipped` · `altDated` · `altSpan`(31 · 49 · 50) | — | 듦 |
| 8 | `rails`(128) | `railLevel` · `railRank`(67 · 68 — 이미 있으면 안 씀 38) | `railLevel` · `railRank`(74 · 75) | — | `HT.datedAlts`(23 · 30 ✓) — `lodOf` · `eventColor` · `eventUid` · `onRail` · `railSpan` · `railLevels`를 **내보냄**(events · figures · links가 씀) | — | 듦 |
| 9 | `links`(254) | — | `bandOf`(30) | — | **rails.mjs** `lodOf`(6) · `HT.historicityOf`(35) · `HT.cmp16`(108) · `HT.succAbsorbs`(124) · `HT.successionLabel`(129) · `HT.kindName`(158) · `HT.relationInfo`(261 ✓) · `HT.unionPairs`(241) · `HT.formatYear`(231) · `tl._hosted`(174) · `tl._data.scopes`(269) | — | 듦 |
| 10 | `scopes`(110) | — | — | — | `tl.scopeOn`(99 ✓) · `tr.scopeBranches`(40 ✓) · `model.periods`(25) | — | 듦 |
| 11 | `labels`(124) | — | `catNo`(73 — 없으면 빈 Map) | `rowLabels`를 만듦(74) | `HT.yearOf`(8) · `HT.glyphMissing` · `HT.GLYPH_BAND`(23 · 31) | — | 듦 |
| 12 | `minibars`(63) | — | — | — | — | — | 듦 |
| 13 | `docs`(384) | `docsOf` · `cellDocsOf`(384 · 385) | `docsOf` · `cellDocsOf`(늦은 차례 400) | 늦은 차례만: `entities`(403 — doc가 아닌 기록의 `json`) | **js/wiki.js**(21 — `HT.namu.links` · `files`) · `HT.docKey.*`(104 · 167) · `HT.formatRange`(96 · 153 — 일부 ✓) · `HT.cellToNow`(98) · `HT.cellKind` · `cellsOf`(✓) · `cellSpan`(134 ~ 142) · `HT.itemKindOf`(✓) · `kindName` · `itemWord`(151) · `HT.CELL_KINDS`(202) · `HT.cmp16`(179) · `HT.docImageOf`(338) · `atob`(46) · `ctx.trackPack` · `packOf` | 있음(399) | — |
| 14 | `calendar`(194) | — | — | — | `HT.cal.monthStartIn` · `partsIn`(68 · 70 — 일부 ✓) · `HT.cal.jdnCivil`(138) · `HT.cal.CALENDARS` · `supports`(122) · 표 파일 `calendar-cache.json`(Rust는 `opts.calendar`에서 `sliceTable` 105 · 표가 없으면 거절 · 표 밖 구간은 생략 — 과제 calclip) | — | — |
| 15 | `entities`(1,417) | — | — | `entities`(1320 — docs가 실은 `doc:` 기록의 `json.empty`) | **kin.mjs** `kinCollect`(17) · **js/group-tree.js** `HT.groupTreeLayout`(953) · 웹 함수 약 60(`HT.cellSpan` · `cellBounds`(✓) · `formatRange` · `formatWhen` · `kinOf` · `houseHead` · `houseSpans` · `readTreaty`(✓) · `readLaw` · `readElection` · `lineageOf` · `accessionLine` · `personOf` · `placeOf`(✓) · `namesHead` · `glyphMissing` · `groupDigits` · `splitArticles` …) | — | — |
| 16 | `power`(145) | `powerNominal`(63) | `bandOf`(59 — 없으면 빈손) · `powerNominal`(늦은 차례 142) | `cells`(67 — 지도자 칸의 자리 · 118 style 고침) · `periods[bandOf]`(80) · 늦은 차례: `cells`(145 — variant `theme:` · 비트 30) | `HT.groupStrip`(82 ✓ — 기억 없음) · `HT.coalitionsOf`(125) · `tl.show.groups`(58) | 있음(141) | 듦(끝) |
| 17 | `variants`(456) | (REPLAY의 `sub.shared`를 새로 — `bandOf`를 결과 번호로 바꿔 끼움 144 ~ 157) | `bandOf`(201 — assert) | `tracks[].rows`(198 · 240 · 266 · 273 — `figWide`도 견줌 → 늦은 차례 **전** 값이어야 함) · `periods`(199 · 332) · `events`(203) · `items`(206) · `cells`(212) · `rowLabels`(217 · 220) · `variants`를 만듦(224) | `importModule`(REPLAY 열둘 167 — tracks bands strips events hangs figures rails links scopes minibars labels power의 `contribute`) · `relayout`(124 ~ 130 — `tl.expandedHosts` · `expandedGroups` · `scopesOn` + `_layoutTrack` ✓) · `G` · `rowHeight` · `trackValuesOf`를 **내보냄**(boards · lens) | — | 주인 |
| 18 | `boards`(541) | (REPLAY의 `sub.shared.bandOf`를 기본 번호(hangs 앞) → 다시 돌린 번호(power 앞)로 128 · 130 · `sub.model.events`를 거름 125) | — | `tracks`(500 · 532) · `periods`(502 · 503) · `events`(504 · 505) · `cells`(513) · `items`(520) · `boards`를 만듦(577) | **variants.mjs** `G` · `rowHeight` · `trackValuesOf`(28) · `importModule`(REPLAY 494) · `tl.board` · `_boardPlan` · `_boardTr` · `_boardOpen` · `_boardFolded`(143 ~ 177 — timeline.js 8872 ~ 9008 · `layout_track`의 판 거절을 걷고 판 갈래를 옮김) · `tl._layoutTrack`(151 · 152 · 176) · `tl.echoBands`(78 — timeline.js 2440) · `HT.readScopeRefs`(68 ✓) · `HT.itemKindOf`(87 ✓) · `HT.pastel`(✓) · `isColor`(94) · `tl._scopePad`(113 ✓) | — | 주인 |
| 19 | `metro`(140) | — | — | 늦은 차례만: `entities`(120 — `period` 기록의 `json` — docs의 `x_docs` 뒤) | `tl._cityUses`(104 ✓) · `tr.periods`(107) · `HT.yearOf`(39) · `HT.formatWhen`(42 ✓) · `HT.cellToNow`(44) · `HT.formatDate`(47 ✓ 해만) · `HT.altText`(52) · `HT.formatRange`(92) | 있음(114 — `contribute`는 빈손 136) | — |
| 20 | `lens`(233) | — | `bandOf`(84 — assert) | `cells`(125 · 161 — 앞선 모듈 · 변형 판까지) · `periods[bandOf]`(146) · `events`(230) · `entities`의 `themes`(240 — entities 모듈) · `variants`(129 — 없으면 만듦) | **variants.mjs** `G`(37) · `tl.themeLens` + `_layoutTrack`(102 ~ 119 ✓ — `HT.lensAny` ✓의 첫 견줌) · `HT.lensCellsOf`(144) · `HT.leaderLabel`(169 ✓) · `HT.lensEventHit`(134) · `HT.lensHasData` · `themeHint`(213) · `model.institutionIndex`(73) | — | — |

**갈래 묶음(제안 — 다섯 · 같은 shared · 같은 가져오기 · 같은 웹 함수끼리 · 서로 기다리지 않게):**

| 갈래 | 모듈(앞자리) | 함께 옮길 웹 함수 · 파일 | 줄 수(약) | 먼저 끝나야 할 것 |
| --- | --- | --- | --- | --- |
| A 줄 · 날짜 칸 · 띠 · 칸 | `axis`(2) · `bands`(3) · `strips`(4) | `tl._buildAxis`(timeline.js 4129 ~ 4320 — 정답지가 쓰는 셈만) · `HT.historicityOf` · `kindFamily` · `historicityTag` · `cellSpan` · `cellToNow` · `altFlipped` · `altSpan` | 750 | 없음(Node 출력을 심음) |
| B 사건 · 인물 · 관계 · 그릇 · 줄 이름 | `rails`(8)를 먼저 → `events`(5) · `figures`(7) · `links`(9) · `hangs`(6) · `scopes`(10) · `labels`(11) | rails의 내보낸 함수 여섯 · `HT.cal.parse` · `formatT` · `formatYear` · `succAbsorbs` · `successionLabel` · `kindName` · `unionPairs` · `cmp16` · `yearOf` · `glyphMissing` | 1,270 | 없음(갈래 안에서 rails 먼저) |
| C 문서 · 달력 · 노선도 | `docs`(13) · `calendar`(14) · `metro`(19) | `js/wiki.js` 전부(`lay/m/docs/wiki.rs` — 정규식 벡터 · `[date]`는 UTC) · `HT.docKey.*` · `docImageOf` · `formatRange` · `altText` · `sliceTable` · `jdnCivil` | 1,700 | 없음(늦은 차례도 Node의 `late-`를 심음) |
| D 항목 기록 | `entities`(15) — 13a ~ 13d 차례로(갈래 kind 거르개 검사를 `lay_m_entities.rs`에 더하며) | `kin.mjs`(`lay/m/entities/kin.rs`) · `js/group-tree.js`(`lay/m/entities/group_tree.rs`) · 웹 함수 약 60 · 끝에 `json` 바이트 견줌 | 2,650 | 없음(가장 긺 — 먼저 시작) |
| E 단체 단 · 렌즈 · 변형 · 판 | `power`(16) · `lens`(20)를 먼저 → `variants`(17) · `boards`(18) | `HT.coalitionsOf` · `lensCellsOf` · `lensEventHit` · `lensHasData` · `themeHint` · `tl._boardPlan` · `_boardVisit` · `_boardGroups` · `_boardBranch` · `echoBands` · `layout_track`의 판 갈래 | 1,500 | `variants` · `boards`의 REPLAY는 **A · B가 끝난 뒤**(열두 모듈의 Rust `contribute` — tracks · minibars는 끝남 · power는 E 자신). power · lens는 기다림 없음 |

갈래가 겹쳐 옮기는 웹 함수(`HT.altSpan` · `altFlipped` A · B / `HT.cellSpan` · `cellToNow` A · C · D / `HT.formatRange` C · D · E / `HT.cmp16` B · C / `HT.historicityOf` A · B / `HT.kindName` B · C)는 각자 제 모듈 파일 안에 두고(JS 모듈도 `altEdges` · `lodOf` · `bandStart`를 제 파일에 복사해 둠), 합친 뒤 하나로 모으는 정리는 과제 16 앞에 한 번 — **과제 Y가 함**(웹 함수는 `lay/web/` · 모듈 사본의 도움 · 상수는 `lay/m/kit.rs` · 아래 '과제 Y' 절). 통째 검사(`lay_out`)의 앞자리는 A → B → C → D → E 차례로 늘지만, 합치는 차례는 무관하다(각 갈래가 제 파일만 고침).

### 과제 16: 부분 셈 — `Scope::Tracks` · 닿는 트랙 · REPLAY를 그 트랙만

> **앞 절반 16a(2026-10-22 · 가지 `p34-p16` · 판정 R38 — 감독 허락으로 둘로 나눔)**: 인터페이스 셋을 세웠다 — ① `Scope::Tracks(S)`의 첫 판: `lay::export`의 범위 갈래 = `patch::sub_plan(export(All), S)` 그대로(빠르게는 16b · 하나 다름: 배치에 없는 **판** 트랙 열쇠는 걸러 냄 — 판 셈 오류로 빠지는 판(합성 자료 `synth-lay`의 `ep-sd`)은 배치 없이 짐작할 수 없어서 · P4는 `Covers::Part`의 트랙을 S ∩ `allTracks`로 잡아야 함) ② `lay::touched`(`lay/touch.rs` — 그 DLC가 없는 조합 · 있는 조합의 모델을 준비까지 두 벌 짓고 모델 객체마다 내용 지문을 견줘 규칙 열 가지로 트랙을 모음 · P4 틈의 꼴 `touch::touched_scope(앞, 뒤)` · 조합의 열쇠 `touch::keys`) ③ `lay::RULES`(만드는 도구 `prototype/scripts/lay-rules.mjs` · 낡음은 `lay_scope`가 지킴). 검사 `tests/lay_scope.rs`: 범위 갈래 = sub_plan(자료 25 · 집합 89 · `allTracks` · 지문 · S 밖 가림 980개의 `hideAt` · `hideOwners` · 없는 판 열쇠만 거름) · touched 넓이(정답지 조합 · 장면 전부 합성 조합 · 판 바꿈 합성 · 시험 DLC — 조합 184, touched ⊇ 지문이 바뀐 트랙 ∪ 새 트랙 · ⊆ 새 조합 열쇠 + 빗나간 판 · 짐작한 열쇠 = 실제 + 빠진 판) · KTL 기대 집합 · RULES 낡음. **계획과 달라진 것**: 걸음 1의 KTL 기대 집합은 {제 트랙 · 승계 양 끝} = {koreaA, korea}가 아니라 다섯 모두 — 날짜 칸 이음 번호(`axis[].strip`)가 온 판 번호라 맨 앞에 서는 koreaA가 뒤 트랙 넷의 번호를 민다. 지문이 트랙 순번 · 온 판 번호를 그대로 품는 곳 둘(`axis[].strip` · 변형 `notes`의 '트랙 <순번>')이 touched를 넓힌다 — P4 지문에서 걸러 적으면 걷을 수 있다. 빼기의 합성에 '뒤에만 서는 트랙'(`keys(뒤)` − `keys(앞)`)을 더해야 한다(P4 약속에 더함). 걸음 5의 지금 값(빠른 빌드 · 다른 작업이 CPU를 다 쓰는 때): 동아시아 + KTL `export(All)` 569ms · `touched` 391ms · `export(Tracks(touched))` 552ms(touched 5/5 트랙 — 같은 값) · 힙 정점 19.7MB · 14.1MB · 19.7MB(한가할 때 잰 `export(All)`은 약 229ms · 준비 한 벌 56 ~ 71ms). 걸음 2 ~ 4의 REPLAY 좁히기 · 모듈마다 거르기, 걸음 5의 줄이기, 걸음 6은 **16b**(웹 함수 모으기 과제 Y 뒤).

> **뒤 절반 16b(2026-10-22 · 가지 `p34-p16` · 판정 R45 · R54 · R59 · R60 · R61)**: ① **부분 셈의 결론 — 답과 셈 모두 통째와 같다**: `Scope::Tracks(S)` = `sub_plan(export(All), S)`이고 S 밖 트랙을 건너뛰지 않는다. S 밖 트랙의 몫이 하위 배치에 남는 값에 들기 때문이다 — 온 판 `spheres`의 띠 수(변형의 새 띠까지 모든 띠) · 일반 항목의 띠 번호(온 판 띠 순번) · 트랙 0의 렌즈 변형이 가리는 모든 트랙의 지도자 칸(변형의 칸까지)과 렌즈 항목 기록의 사건 목록(변형의 새 사건까지) · 판이 서는가와 판 하나의 셈 오류로 빠지는가(`allTracks`) · 판 변형이 구성 트랙 밖 항목까지 가림 · 변형의 견줌(기본 항목의 느슨한 이름). 첫 시도(제 트랙이 S 밖인 변형 건너뛰기 — 렌즈 가림 조건까지)는 `lay_scope`가 등불의 `spheres` 띠 수로 잡아 걷었다. 재어 보니(동아시아 + KTL · 빠른 빌드 · CPU 100% · 아홉 번 가장 작은 값) 트랙마다의 모듈은 다 합쳐 약 25ms로 `entities` 63ms(항목 기록 — 늘 통째) · 준비 47ms · 닿는 트랙(`between`) 153ms보다 작다. 그래서 셈 자체를 줄였다: 변형은 **제 트랙만** 다시 배치(`track::layout_some` — 줄 배정은 트랙마다 제 정권만 읽는다 · 정답지 25 · 골든 같음) · 변형이 없으면 끝의 다시 배치를 하지 않음 · **닿는 트랙(`touch::touched_scope`)이 준비한 '뒤' 조합의 문맥을 곧이은 내보내기가 다시 씀**(`lay::export::keep_prepared` — 넣기 한 번의 준비 세 벌 → 두 벌 · `lay_scope::touched_scope_hands_its_prepared_context_to_export`). ② 지문 판 2(R45): 날짜 칸 이음 번호는 트랙 · 갈래 안 거리 · 변형 notes의 트랙 순번은 열쇠 · 하위 배치에 `stripFirst` · apply 'renumber' 걸음(덮는 꼴 셋 모두 · 실패 지점 — R59 I-2)이 다시 쓰지 않은 트랙의 번호를 옮김 → touched 규칙 9 · 10을 걷어 KTL 기대 집합은 걸음 1 그대로 {koreaA, korea}. ③ touched 구멍(R54): 트랙 객체의 집 = 제 id · 서거나 사라지는 판은 apply(Part)가 그 판의 구성 · 가림 트랙으로 넓힘 · 규칙 7로만 든 첫 트랙은 판을 끌지 않음. ④ 규칙 판(R61 · R59 I-1): `lay::rules()` = `lay <LAY_RULES_VERSION>`(손으로 올리는 판 번호 — 원본 바이트 지문을 걷음) + 골든(`tests/lay_golden.rs` — 정답지 자료 25의 Rust 통째 출력 해시가 바뀌면 판 번호를 올리라고 멈춤) · 트랙 · 온 판 지문과 `meta.rules`에 `patch::rules_mark`(지문 판 + lay 판) · `packs::held`가 다르면 모든 트랙(첫 넣기 한 번). 위 인터페이스의 `RULES`는 옮긴 원본의 낡음 검사만 한다. ⑤ P4 바꿔 끼우기: `RustLayouter.touched` = `touch::touched_scope` · `export` = `lay::export` · `Opts`는 `need_calendar`의 증표로만. ⑥ **걸음 5의 값(공식 설정 LTO)**: 한 프로세스 안(열 번 가운데값 · 세 번 되풀이 · 부하 8 ~ 48%) `export(All)` 95 ~ 100ms · `touched` 60 ~ 67ms · `export(Tracks(touched))` 101 ~ 133ms · touched_scope + 범위 내보내기(실제 틈의 차례) 130 ~ 143ms · 차가운 첫 `export(All)` 109 ~ 149ms · 힙 정점 10.6MB · 5.0MB · 10.6MB(차가운 첫 번 20.2MB — 정규식 · 달력 표 풀이가 남음). `archive-tool add-pack <동아시아 저장소> KoreanTimeLine` 열 번(프로세스마다 새로 — 매번 차가움 · 전체 달력 표 738KB) 가운데값 — 부하 약 60%: 334ms(벽시계 353 · 읽기 5 · 배치 110 · apply 110 · 닿는 트랙과 그 밖 110 · 최대 작업 집합 37MB) · 부하 85 ~ 100%: 450 ~ 464ms — 0.3초 예산을 넘는다(배치 몫은 닿는 트랙 + 범위 내보내기 ≈ 130ms · apply의 표본 타일 대조(verify)가 크다 — 한 번 잰 걸음: verify 87 · names 23 · entities 21 · insert 16 · choose 10ms). **예산 기준(판정 R69-6)**: P4 과제 9의 0.3초는 **앱 꼴 따뜻한 넣기의 벽시계**(같은 프로세스에서 넣기를 거듭하되 넣기마다 저장소의 달력 표를 다시 읽어 풂 · 차가운 첫 넣기는 따로 적음) — 판단은 공식 검사(걸음 7) 때 한가한 PC에서 `tests/add_pack.rs::timing_app_like_adds_for_ktl`(공식 설정 · `HT_CALENDAR_FULL`로 전체 표)로 재어 한다(위 값은 부하 속 · 판단 근거 아님 — 16b 검토 ② I2). 재는 틀의 한계(고침 2회차 — 바꾸지 않음 · 걸음 7에서 판단): 정규식 첫 짓기의 몫을 따로 재지 않고(차가운 첫 넣기에 섞임) 넣기마다 새 연결을 연다(앱은 열린 연결 하나). ⑦ 고침 1회차(판정 R69): 닿는 트랙의 실패도 거절 code로 · `meta.rules`는 짓기(`build_store`)와 실제 틈의 모두 덮는 넣고 빼기만 적고 바깥 배치(`apply` · 메이커 `.htlayout` · Node 배치를 채운 가져오기)는 지운다(다음 넣기 한 번 모두) · 골든은 판별 이력(`tests/lay_golden.rs` — 입력이 같은데 출력이 바뀌면 `LAY_RULES_VERSION`을 올려 이력 끝에 덧붙여야 통과 · 입력 지문으로 '입력 바뀜'은 표만 · 다른 시각 · 시간대 둘 · 지문 판 골든) · 짐작 열쇠가 배치에 없으면 모든 트랙으로 넓힘 · 넣고 빼기 끝에 푼 달력 표 · 준비 문맥을 비움 · 살아 있는 그릇 세기는 `oracle` 기능(검사만). ⑧ 고침 2회차(판정 R71): 골든의 입력 지문을 (DLC · 시각 · 시간대)와 달력 표 지문으로 가르고 출력을 배치 해시(`cal:` 기록 뺌) · 달력 기록 해시로 — 달력 표만 바뀐 커밋에서 보조 달력을 읽지 않은 자료(`lay::cal::take_aux_reads` 0 — 지금은 동아시아 계열 · 합성 대부분)의 배치가 바뀌면 판 올림 · `calendar-slice.json`을 다시 뜨는 커밋에는 엔진 고침을 섞지 않음 · 닿는 트랙 셈이 넘어지면(오류 · 패닉) 거절하지 않고 모든 트랙 · 넓힘은 답의 `widened`(missing · needs_whole · touched_failed).

**파일:**
* 고침(16a · 16b가 실제로 고친 것 — 위 16b 문단과 같게): `lay/mod.rs`(`Scope` · `rules()` · `clear_caches`) · `lay/export.rs`(`export`가 `opts.scope`를 따름 — 셈은 통째 · S의 하위 배치를 냄 · 배치에 없는 판 열쇠는 거름 · 짐작이 빗나가면 `MissingTracks` · 준비 문맥 다시 쓰기 `keep_prepared`) · `lay/m/variants.rs`(`relayout`을 그 변형의 트랙만 — REPLAY는 통째) · `lay/track.rs`(`layout_some`) · `lay/ctx.rs`(준비 + `lay_out`) · `lay/cal.rs`(달력 표를 한 번 풀어 나눔 · 보조 달력을 읽었나 `take_aux_reads`) · 틀 손질(과제 Y 검토 넘김 — `lay/m/kit.rs` · `lay/model/*` · `lay/read/cells.rs` · `lay/web/*` · `lay/js*` · 모듈 몇) · P4 쪽 `packs.rs`(실제 틈 바꿔 끼우기 · `meta.rules` · 넓힘 `widened`) · `patch.rs`(지문 판 2 — 번호 rekey · `renumber` 걸음 · `rules_mark` · `NeedsWhole`) · `legacy.rs`(짓기가 `meta.rules`를 적음) · 검사 `tests/add_pack.rs` · `apply.rs` · `build.rs` · `lay_out.rs` · `lay_rows.rs` · `lay_m_lens.rs`. **트랙 단위로 거르는 모듈은 없다**(16b 결론 — 위 16b 문단: S 밖 트랙의 몫이 하위 배치의 값에 든다 · 처음 적은 '거를 모듈' 목록 `tracks` ~ `lens`는 걷음)
* 만듦: `prototype/engine/src/lay/touch.rs` · `lay/rules.rs`(`LAY_RULES_VERSION`) · 층 손질로 나눈 `lay/model/kinds.rs` · `lay/read/alts.rs` · `prototype/scripts/lay-rules.mjs`(`lay::RULES`를 뜨는 도구) · 검사 `prototype/engine/tests/lay_scope.rs` · `lay_golden.rs`(판별 이력 골든) · `lay_frame.rs`(틀 손질의 단위 검사)

**인터페이스:**
* 먹음: 과제 15 `export` · P4 과제 4 `patch::sub_plan` · `patch::track_key`
* 만듦:
  * `Scope::Tracks(S)`의 출력 = `patch::sub_plan(export(Scope::All), S)` — 트랙 S의 것 + 온 판 + **항목 기록 전부**(정한 것 #12). 트랙 · 줄 번호는 S만의 순번.
  * `pub fn touched(new: &PackIn, all: &[PackIn], opts: &Opts) -> Result<BTreeSet<String>>` — 그 DLC가 닿는 트랙 열쇠: 제 트랙 · 항목을 얹는 남의 트랙 · 승계 · 소속의 양 끝 트랙(P4 `track_key`와 같은 열쇠).
  * 지문에 섞는 규칙 판: 처음에는 `pub const RULES: &str`(옮긴 원본 SHA-256 앞 12자를 이은 것)를 섞기로 했으나, **16b(판정 R61 I1)에서 `lay::rules()` = `lay <LAY_RULES_VERSION>`(배치 출력이 달라질 때만 손으로 올리는 판 번호 · 골든 검사가 올림을 지킴)으로 바꿨다** — P4는 `patch::rules_mark()`(지문 판 + 이것)를 트랙 · 온 판 지문과 `meta.rules`에 섞고, 저장소의 것이 다르면 다음 넣기에서 모든 트랙을 다시 쓴다(설계 3-4 '규칙 판'). `RULES`는 옮긴 원본의 낡음 검사(`lay_scope`)만 한다.

- [x] **걸음 1: 실패하는 검사를 쓴다** — `lay_scope.rs`: 자료마다 · 트랙 열쇠 집합 셋(하나 · 둘 · 셋 — 씨앗 고정 무작위)마다 `export(Scope::Tracks(S))` = `archive_engine::patch::sub_plan(&export(Scope::All), &S)` · `touched(KTL, 동아시아+KTL)` = KTL 원본에 적힌 트랙 · 얹는 트랙 · 승계 · 소속 양 끝(손으로 적은 기대 집합).
- [x] **걸음 2: 실패를 본다 → 걸음 3: 쓴다**(REPLAY 줄이기는 정답지 `upto-variants` · `upto-lens`가 그대로 PASS인지로 지킴) **→ 걸음 4: `lay_scope` · `lay_out` 전부 PASS**
- [x] **걸음 5: 시간 · 메모리를 잰다** — 동아시아 + KTL: `export(All)` · `export(Tracks(touched))`의 ms(release · 열 번 가운데값)와 메모리 정점. P4 과제 9의 0.3초 예산의 배치 몫.
- [x] **걸음 6: 커밋한다** — 제목 "한 벌 P3-16 부분 셈 — 닿는 트랙만 배치해도 전체의 그 몫과 같다", `— 검사: lay_scope · lay_out 전부 · 시간 <ms> · 메모리 <MB>`

### 과제 17: Rust로 짓기 — `archive-tool build` · 시드 · 달력 표 · 오늘을 저장소에

> **끝(2026-10-22):** 걸음 1 ~ 3은 갈래 1(가지 `p34-b` — `archive-tool build`(① `lay::export` → ② `legacy::build_store` · `--calendar` 필수 · 전체 표) · `lay::calendar_of` · `build-check.mjs`(Node 길 = `oracle/combo.mjs`) 24자료 GREEN · 고침 3회차 f7422b4에서 다시 돌려 같음), 걸음 4 · 5는 과제 seed(가지 `p34-seed` — `build-showcase.mjs`가 시드를 `archive-tool build`로 · 1배 전후 · 꾸러미 `도구/`에서 Node 걷기). 아래 걸음 줄에 적은 그대로.

**파일:**
* 고침: `src/main.rs`(`build <저장소> <팩…> --calendar=… [--now=…]`) · `src/legacy.rs`(P4 과제 1b의 `import_layout_value`와 공통 몸 `import_value_into` · 달력 표를 `blobs`의 `calendar:table`로 · `meta.now`) · `prototype/scripts/build-showcase.mjs`(시드 저장소를 `archive-tool build`로 · 달력 표는 `warm-calendar.mjs`가 뜬 전체 표를 그대로 넘김 — 판정 R36) · `docs/계약-아카이브-3단계.md`(4절 머리 — 배치 JSON은 이제 엔진 안에서 나온다 · Node 내보내기는 정답지)
* 만듦: `prototype/scripts/build-check.mjs`

**인터페이스:**
* 먹음: 과제 15 `export` · P4 과제 1b `canon_store` · `import_layout_value`
* 만듦: `archive-tool build <새 저장소> <기본 팩> [<얹는 팩>…] --calendar=<calendar-cache.json> [--now=<ISO 시각>]` · `lay::calendar_of(store) -> Result<Option<Rc<Vec<u8>>>>`(P4 과제 9가 씀).

- [x] **걸음 1: 실패하는 확인을 쓴다** — `build-check.mjs`: 기준 셋 + 가상 묶음마다 ① Node 길(`oracle/combo.mjs` → `import-layout` — 과제 1의 시각 · 시간대로) ② Rust 길(`archive-tool build --now=<같은 시각>`)로 저장소 둘을 지어 `archive-tool canon --queries`가 같다 · 둘 다 `verify-tiles 120` 누락 · 중복 0. Rust 길이 없어 실패를 본다.
- [x] **걸음 2: 쓴다 → 걸음 3: 확인 PASS** — 2026-10-22 고침 1회차(갈래 1 · p34-lay의 모듈 스물을 받은 `p34-b`): `build-check.mjs` 24자료(기준 셋 21 — KTL 형식 4 사본은 파일이 없어 건너뜀 + 가상 묶음 3) **모두 Node 길 = Rust 길** · 둘 다 누락 · 중복 0 · Rust 저장소의 `meta.now` · 달력 표(전체 표 −3500 ~ 2500년 · zlib 26,974바이트) · meta가 맞음. canon은 `--queries`, 등불 견본 자료(형식 3 · 형식 4 사본 · +d7+sphere)만 성긴 단계(조회 없이 — `--full-canon`이면 모두). Rust 길 짓기 시간은 Node 길(배치 + 가져오기)과 엇비슷(PC 꽉 찬 때 — 등불 4.7 ~ 10.3초 · 동아시아 계열 0.5 ~ 4.2초 · 합성 0.5 ~ 0.9초).
- [x] **걸음 4: 실제 앱 1배 전후** — 등불 연대기 · 동아시아 + KTL 시드를 두 길로 지어 앱을 열고 같은 장면(대본 `measure.mjs --capture-script` · 절대 경로) 1배 그림이 화소까지 같다(`compare-shots.mjs`). — 2026-10-22 가지 `p34-seed`: 동아시아 · 등불 · 동아시아 + KTL을 바탕 3dc69e6의 Node 길과 새 `build-showcase.mjs`(Rust)로 같은 날 지어 canon 같음(동아시아 · KTL `--queries` · 등불 성긴 단계). 같은 실행본 · 같은 대본(처음 · 1300 ~ 1700년 · 아래로 · DLC 관리 — 1920×1080)의 그림을 풀어 화소로 견줌(`compare-shots.mjs`는 웹 ↔ 앱 도구라 PNG를 푸는 손 도구로 — 자료마다 · 장면마다 모든 돌림끼리): **흔들림 범위 안에서 같음** — 동아시아는 모두 같고, 갈린 곳(KTL 1-처음 4화소 · KTL 4-DLC-관리 1화소 · 등불 ClearType 2화소 · 첫 Rust 돌림 한 번에서만 KTL 개수 알약 '4'가 두 장에서 통째로 빠짐 228화소)은 모두 같은 길의 돌림끼리도 갈린다. 갈린 곳 · 화소 수 · 저장소 · 실행본 SHA · 찍은 때는 sdd `seed-찍기/1배-견줌/견줌-기록.json`.
- [x] **걸음 5: 시드를 Rust로** — `build-showcase.mjs`의 시드 짓기(217 ~ 220 · 248줄)를 `archive-tool build --calendar=<전체 표>`로 바꾸고(달력 표는 시드보다 먼저 뜬다 — 지금은 `bundle-app.mjs` 116줄이 꾸러미 끝에서 뜸), Node 내보내기는 `build-check.mjs`의 정답지로만 남긴다(설계 5절 P3의 끝). 인수인계 절에 한 줄. — 2026-10-22 가지 `p34-seed`: `build-showcase.mjs`가 `build --now=<'오늘' — 없으면 지금을 +09:00으로 · 한 돌림의 저장소는 같은 값> --calendar=<표 — 없으면 그 자리에서 warm-calendar 기본 범위로 떠 <출력>/calendar-cache.json>`로 짓고, 저장소마다 표를 `archive-tool blob`으로 꺼내 준 표와 바이트로 견준다. 조합 거절 때 견본 하나씩 얹어 보기 · `--strict` · `verify-tiles 600` · 카드 확인은 그대로, `--keep`은 걷음(배치 JSON 없음). 꾸러미(`bundle-app.mjs`)는 저장소를 복사만 하고 표를 뜨지 않는다.
- [x] **걸음 6: 커밋한다** — 제목 "한 벌 P3-17 Rust로 짓기 — 시드 저장소를 엔진이 짓고 Node는 정답지로만", `— 검사: build-check(canon 같음 · 누락 0) · 실제 앱 1배 전후 같음`

### 과제 18: 앱의 다시 잇기 중 정적인 것을 엔진 답으로 — **리메이크가 `scene/layout.dart`를 놓은 뒤**

**시작 조건:** 과제 17이 끝났고, 리메이크 세션이 `scene/layout.dart`를 더 고치지 않는다고 확인했다(인수인계 · 그 세션에 물음).

**파일:**
* 고침: `src/layout.rs`(`{"op":"layout"}`의 줄에 이름 붙은 칸 — `fig_wide` 비트 풀이(`rail` · `organ` · `power` · `real` · `hang` · `raised` · `contained` · `cell_rows` · `dynasty` · `leader` · `cabinet` · `events`) · 그릇 `scope_head` · `scope_foot` · `scope_hang`(지금 앱 `_scopePadOf`가 `scope_pad` 하나를 다시 가름) · 그릇 부모 · 깊이) · `lay/m/tracks.rs`(값을 따로 실음 — 저장소 열 더함, 판 '3' 규칙) · `prototype/app/lib/scene/layout.dart`(`fromJson` 비트 풀기 · `_scopePadOf` · 포개짐 깊이의 `containsAll` 셈을 걷고 읽기만) · `docs/계약-아카이브-3단계.md` 3절 · `docs/설계-한벌-체제-목업판-ClearType.md` 3-3절(“앱 `layout.dart`가 다시 잇는 것 — 엔진의 답으로” 줄을 “보기 상태와 무관한 것만 · 줄 쌓기(px)는 앱 한 곳”으로)
* 검사: `prototype/app/test/layout_static_test.dart`(새로) · 이웃의 앱 검사 · 엔진 `tests/spheres.rs` 둘레

- [x] **걸음 1: 설계 고침을 감독에게 확인받는다** — 정한 것 #5를 한 장으로(아래 — 2026-10-23 감독 "길 (가)로 진행").
- [x] **걸음 2: 실패하는 검사를 쓴다** — 엔진 `tests/layout_static.rs`(줄 깃발 · 가름 · 변형 줄 · `within` · `sphere_at` — 옛 저장소 꼴까지) · 앱 `test/layout_static_test.dart`(진짜 자료 처리부 — 동아시아 + nest + sphere · 등불: 줄 165 · 변형 줄 262 · 그릇 7(포개짐 1) · 트랙 39에서 옛 셈 = 엔진 칸 · 새 칸을 지운 답과 그대로의 답으로 쌓은 줄의 자리 · 높이 · 그릇 깊이가 그릇을 켜고 끄며 같음).
- [x] **걸음 3 ~ 5: 실패 → 쓴다 → PASS** — 엔진 `layout.rs`(`add_row_flags` · `scope_split` · `sphere_at`) · `variant.rs`(변형 줄의 가름 · `within`) / 앱 `layout.dart`(`RowFlags` · `ScopeSplit` · `RowSpec.withFlags` · `ScopeOn.within` · `TrackInfo.sphereAt` · `_scopePadOf`는 px 되돌리기만). 정적 분석 0 · 엔진 검사 전부 · 앱 검사 전부(`correctness`의 굳은 줄 JSON에 새 칸 더함 · `SCRATCH_KINDS`에 `layout-static`).
- [x] **걸음 6: 실제 앱 1배 전후 같음** — main(b893633)의 앱과 p3-18의 앱을 같은 저장소 둘(동아시아 + nest + sphere · 등불)에서 같은 대본(그릇 넷 켠 처음 · 넷 끔 · 조감 · 모두 접음)으로 찍어 PNG 9장이 바이트까지 같음(`prototype/results/p3-18-1배/` — git 밖).
- [x] **걸음 7: 커밋한다** — 가지 `p3-18`(main 합치기는 감독 허락 뒤).

> **18 설계 한 장(걸음 1 · 2026-10-23 · 가지 `p3-18` · 감독 확인 "길 (가)로 진행")** — 정한 것 #5를 코드에 맞춰 적은 것. **한 가지 바꿈(구현하며)**: "새 칸이 없는 답은 받지 않는다"는 않고, 앱의 옛 셈을 `RowFlags.legacy` · `ScopeSplit.legacy` · 깊이 `containsAll` · 문화권 `indexWhere` **한 곳씩**에 남겨 칸이 없는 답(손으로 쓴 검사 답 100여 곳 · 옛 엔진)만 그 길로 읽는다 — 엔진 답에 칸이 있으면 읽기만 하고, `layout_static_test`가 옛 셈 = 엔진 칸을 굳힌다. 지금 앱 `scene/layout.dart`가 엔진 답을 받아 **다시 가르는 셈 넷**이 있고, 그 가운데 보기 상태와 무관한 것만 엔진 답으로 옮긴다.
>
> | 지금 앱이 다시 가르는 것 | 보기 상태 | 어디로 | 엔진 답의 새 칸 |
> | --- | --- | --- | --- |
> | ① `rows[].fig_wide` 한 정수의 비트 풀기(`fromJson` 487 ~ 504줄 — 인물 단 · 기간 막대 단 + 1 · 기관 · 집권 · 실권 · 매달린 줄 수(zones로 자름) · 솟음 · 그릇 줄 · 칸 층 표시 · 왕조 · 지도자 · 내각 · 사건 — 옛 저장소(비트 3 ~ 5가 0)의 예외 규칙까지) | 무관 | **엔진** | 줄마다 이름 붙은 칸 `fig_wide`(0 ~ 3 · 비트 0 ~ 2만) · `rail`(−1 = 옛 저장소) · `organ` · `power` · `real` · `hang` · `raised` · `contained` · `cell_rows` · `dynasty` · `leader` · `cabinet` · `events`(0/1) |
> | ② `rows[].scope_pad` · `variants[].rows[].scope_pad`의 px 값을 머리 수 · 발(0/1) · 매달린 머리로 **가르는** 것(`_scopePadOf` 앞 절반 — 머리 16 · 발 6 · 매달림 −4의 합을 되푸는 셈 · 갈라지지 않는 값은 그대로) | 무관 | **엔진** | 줄 · 변형 줄마다 `scope_head`(머리 수) · `scope_foot`(0/1) · `scope_hung`(매달린 머리 수) — 갈라지지 않는 값은 셋 다 없음(앱은 그때 지금처럼 `scope_pad` px를 그대로 씀) |
> | ②의 뒷 절반 — 그 수에 **보기의 자(폴더 21 · 7 / 조감 12 · 4 / 상자)를 곱해 px**로 | 조감 · 폴더 · 깊이에 달림 | 앱 | — |
> | ③ 켠 그릇의 **깊이**(`_scopesOn` 1308줄 — 같은 트랙의 다른 그릇이 제 줄을 모두 품는가를 `containsAll`로 n² 셈) | 켠 그릇 집합에 달림 | **반반** — 품는 관계는 정적이라 엔진이, 켠 것 세기는 앱 | 그릇 변형마다 `within`: 같은 트랙에서 제 줄을 모두 품고 더 큰 그릇 변형 id 목록(정적 · 포개짐) → 앱의 깊이 = 그 가운데 켠 것의 수 |
> | ④ 트랙 → 문화권 자리(`_sphereOfTrack` 573줄 — `spheres`에서 id 찾기) | 무관 | **엔진** | 트랙마다 `sphere_at`(spheres 목록 자리 · 밖이면 −1) |
> | 줄 쌓기 px 전부(`_stack` · 접힘 · 밀도 · 조감 · 켠 단 · 렌즈 · 이번 쌓기의 문화권 첫 트랙 `_sphereFirst`) | 달림 | 앱 한 곳(그대로) | — |
>
> * **길(가 — 추천)**: 엔진의 **읽기 답** `{"op":"layout"}`(`src/layout.rs` · 변형은 `variant.rs::variant_layout`)에서 저장소 값을 풀어 이름 붙은 칸을 **더해** 낸다. 저장소 열 · `archive-tool build` · 내보내기(`lay/m/tracks.rs`) · 정답지 · JS는 **그대로** — P3의 '정답지 = JS' 약속과 P4의 저장소 형식을 건드리지 않는다. 계획 원문의 "저장소 열 더함 · 판 '3' 규칙"은 하지 않는다(그 길은 JS 내보내기까지 같이 고치고 정답지 25벌을 다시 뽑아야 함). 옛 저장소(`fig_wide` 열 없음 · 비트 3 ~ 5가 0)는 엔진이 지금 앱과 같은 예외 규칙으로 푼다.
> * 앱은 새 칸을 **읽기만** 한다(`RowSpec` · `VariantRow` · `ScopeOn` · `_sphereOfTrack`). 옛 `fig_wide` 정수 · `scope_pad` px는 답에 남겨 두되(계약 3-3 · 6-5 그대로 — 검사 · 도구가 읽음) 앱은 더 풀지 않는다. 새 칸이 없는 답(옛 엔진)은 받지 않는다 — 앱과 엔진은 늘 함께 배포된다(계약 0절).
> * 검사(걸음 2): `test/layout_static_test.dart`(새) — 정답지 저장소 여럿(동아시아 · 등불 · 합성 · 변형 있는 것)에서 **옛 길**(지금 `fromJson`의 비트 풀기 · `_scopePadOf` 가름 · `containsAll` 깊이 · `indexWhere`)과 **새 길**(엔진 칸 읽기)의 `RowSpec` 모든 필드 · 변형 줄의 머리 · 발 · 그릇 깊이(켠 집합 몇 가지) · 문화권 자리가 모든 줄에서 같다. 엔진 쪽은 `tests/spheres.rs` 둘레에 layout 답의 새 칸 검사. 걸음 6은 실제 앱 1배 전후 같음(`measure.mjs --capture-only`).
> * 걷는 것: 앱의 비트 풀기 · `_scopePadOf`의 가르는 절반 · `containsAll` 깊이 셈 · `indexWhere`. 쌓기 식은 한 줄도 바꾸지 않는다.

---

## 위험(이 계획에서 더 본 것)

* **크기**: 약 1만 4천 줄을 옮긴다(정한 것 #1). 정답지 대조로 진척을 기계로 재고, 다 같아질 때까지 Node 길이 정답으로 남는다. 과제 13(`entities` 2,650줄 — 넷으로 나눔)이 가장 길다.
* **움직이는 과녁**: 리메이크의 남은 것(줄 높이 · 예속 칸)과 5 · 6단계(메이커 · 자료)도 배치 규칙을 건드릴 수 있다. 그때는 '바뀐 JS 커밋 → 그 모듈의 정답지 다시 뽑기 → 같은 차이만큼 Rust 고침'이 한 짝이다. 리메이크 세션에 'P3가 옮기는 파일' 목록을 인수인계로 알린다(과제 1 걸음 7).
* **동적 값의 빠르기 · 메모리**: 지금 자료에는 넉넉하나 천만 모델을 통째로 들면 넘친다 — 과제 16 · P4 과제 11이 재고, 넘치면 뜨거운 곳을 형으로 바꾸거나 부분 모델(다음 설계).
* **정규식**: `regex`가 허락되지 않으면 과제 5 · 12a가 길어진다(#8).
* **휴대폰의 '오늘'**: 기기에서 Rust가 배치하면 기기 시계 · 시간대에 달린다 — 저장소 `meta.now`를 쓰는 것으로 막는다(P4 정한 것 #9).

## 스스로 훑어본 것

* **설계 3-3의 낱낱:** 형식 4 읽기(과제 5a ~ 5c — 검사 · 참조 잇기 · 기본값은 `normalizePack`이 함) · 줄 배정(과제 7 — 그릇 · 포개짐 · 옮겨 앉기(`splitMoves` — 과제 5a) · 문화권(과제 6 · 8)) · 모듈 스물(과제 8 ~ 15) · 앱 다시 잇기(과제 18 — 정적인 것만 · 설계 고침 · 감독 확인) · 글자 폭 흉내(과제 7에서 호출 여부 확인 · `Ctx.text_width`) · 달력 표(과제 12b · 17 · 정한 것 #7 · 실제 보조 달력 날짜가 표 밖이면 거절 · calendar 모듈은 표 밖 구간을 생략 — 과제 calclip) · 정답지로 옮김(과제 1 · 이음매 셋) · 견줄 자료(기준 셋 + 가상 묶음 — 과제 1 · 2) · 모듈 하나씩(과제 8 ~ 15의 앞자리 k). 설계 6절 P3 검사: 정답지 대조(과제 5 ~ 16) · cargo test · verify-tiles · 실제 앱 1배 전후(과제 17 · 18).
* **점검(Fable) 반영:** 시간대 고정 · 자식 프로세스(과제 1) · `$ref`에 경로(정한 것 #3) · 모델만 동적 값 · 출력은 `serde_json`(#2) · `localeCompare` 두 곳 더(#9) · 정규식 뜻 차이 · 벡터(규칙 표 · 과제 3 · 12a) · 달력 표 범위 밖(#7 — 뒤에 과제 calclip이 '실제 보조 달력 날짜만'으로 좁힘) · 부분 셈의 항목 기록은 늘 전체(#12) · 과제 5 · 12 · 13 나눔 · 설계 3-3 고침 걸음(과제 18) · 정답지의 보이지 않는 입력(`F4.split` · `groupBands`) · 시작 조건을 '리메이크 배치 규칙 고정'으로.
* **이름 맞춤:** `lay::MODULES` · `PackIn` · `Opts`(`now_ms` · `tz_min` · `upto` · `scope` · `calendar`) · `Scope::{All, Tracks}` · `same::diff` · `normalized` · `prepared` · `laid` · `export` · `touched` · `RULES` · `calendar_of` · `Ctx` · `context_of` · `layout_track` · `js::*`(규칙 표) · 검사 도움 `fixtures` · `oracle` · `inputs` · `assert_same` · `opts` · `only_keys` — 과제 사이에 같은 이름. P4와 맞물리는 이름: `import_layout_value` · `canon_store`(P4 과제 1b) · `track_key` · `sub_plan`(P4 과제 4).
* **알고 남긴 것:** 옮기는 과제(5 ~ 15)는 원본 JS가 정답이라 계획에 줄마다 적지 않았다 — 원본 줄 범위 · 차례 · 이음매 검사로 맞음을 기계로 정한다. 형식 4 쓰기 몫(`up` · `project`)은 옮기지 않는다(메이커 · 바꿔 넣기 도구의 몫).

## 알게 된 것

(과제 2가 아래를 채움 · 과제 4가 이어서 채움 — 정답지 손질의 차이.)

### 과제 2 — 형식 4로 바꾼 자료의 다른 곳 (2026-10-15)

`node prototype/scripts/f4-same-check.mjs` — **지금(맞추기 과제 S · 견본 2.0.1부터): 자료 9 · 같음 8 · 알려진 차이 1(`east-asia+ktl` 2곳) · 다름 없음** — `lantern`은 ①=②가 되어 known을 걷었다(판정 R16). 아래 표 · 목록은 과제 2 때(견본 1.0.0)의 기록이다: 그때는 자료 9 · 같음 7 · 알려진 차이 2 · 다름(알려지지 않은 것) 없음. ① 원본 그대로 · ② 팩마다 `to-f4`로 바꾼 것 · ③ 내장 `east-asia`를 굳힌 `east-asia.json`을 모듈 스물(`upto-lens`)까지 돌려 `lay::same` 규칙으로 견줌.

| 자료 | ① = ② | ① = ③ |
| --- | --- | --- |
| `lantern` | **13곳 다름**(아래) | — |
| `east-asia` · `+move` · `+nest` · `+dep` · `+d7` · `+sphere` | 같음 | 같음 |
| `east-asia+ktl`(감독 PC의 선택 자료) | **2곳 다름**(아래) | 같음 |
| `nest-f4`(이미 형식 4인 입력) | 같음 | — |

다른 곳 전부(모두 `upto-lens`의 `entities` · `periods` — 줄 배정 · 띠 자리는 같고 항목 기록 · 띠 모양 비트만 다름):

| 자료 | 경로 | ① 원본 | ② 형식 4 | 까닭(`js/core.js` `HT.F4.project`) |
| --- | --- | --- | --- | --- |
| lantern | `entities.46.json.polityKind`(갈대 공국) | `"tributary"` | `"state"` | P2 종속 kind → 국가 + 관계 |
| lantern | `entities.46.json.x_find.hay` | `… 조공·책봉국 아랫물국` | `… 아랫물국` | P2(찾을 글에서 종류 글이 빠짐) |
| lantern | `entities.45.json.x_partOf.members.0.kind`(아랫물국) | `"조공·책봉국"` | `"국가"` | P2 |
| lantern | `periods.7.look`(갈대 공국) | 68683809 | 68681760 | P2(종류 번호 + 종속 계열 비트 `1<<11`이 국가 띠로) |
| lantern | `entities.62.json.hosts.0.nest` · `partOf.0.nest`(새물섬) | `true` | `null` · 없음 | P1 nest 최소화 |
| lantern | `entities.159.json.memberRefs.0 ~ 4`(아홉 불씨 할거) | `"윗물국"` … | `"p-upper"` … | P4 대범위 구성원을 이름 → 객체 id로 |
| lantern | `entities.160.json.memberRefs.0 ~ 1`(등불 부흥 운동) | `"검은물 의병"` … | `"p-blackwater"` … | P4 |
| east-asia+ktl | `entities.129.json.hosts.0.nest` · `partOf.0.nest` | `false` | `null` · 없음 | P1(`nest:false`는 기본값이라 빠짐) |

* **오류가 아니라 설계 3-8의 '옛 모습이 바뀌는 곳'이다.** `HT.F4`의 머리 주석이 "옛 → 4 → 옛은 `project(J)`와 같다"고 적은 그대로다. 확인: 옛 입력을 `project`한 JSON(`normalizePack` → `packToJSON` → `HT.F4.project`)으로 같은 길(`one.mjs --packs`)을 돌리면 `lantern`은 형식 4 길과 `$oracle` 머리만 빼고 **바이트까지 같고**, ktl은 `json` 글을 풀어 열쇠를 정렬하면 같다. 그래서 `HT.F4.up` · `down`은 **고치지 않았다**(리메이크의 `js/core.js`) — 알림은 `인수인계.md` 5-26절에 한 줄.
* **굳은 것(지금):** `list.json`의 `east-asia+ktl@f4`에만 `"known"`(까닭) · `"knownDiffs"`(2)가 있다 — `lantern@f4`의 것(13)은 견본 2.0.1에서 ①=②가 되어 걷었다(맞추기 과제 S · 판정 R16 · `f4/sample-lantern.htpack`을 2.0.1에서 다시 씀). `f4-same-check`는 곳 수가 기록과 같을 때만 '알려진 차이'로 통과하고 늘거나 줄거나 ①=②가 되면 실패한다. `known`은 `f4-same-check` 전용 표시('원본과 다르다')다 — Rust `fixtures()`는 `known` 자료도 건너뛰지 않고 제 정답지(`results/oracle/<그 이름>/`)로 돌린다. `HT.F4.down`의 종속 관계(P2 — 국가 + 관계) · 대범위 구성원 풀이(P4 — 객체 id)는 `lantern@f4`로 시험한다(판정 R9 — 2.0.1 f4에 상대가 있는 종속 관계 11 · 대범위 셋의 구성원 9 · 검사 `lay_oracle`의 `lantern_f4_is_a_rust_fixture_with_its_own_oracle`가 그 구조가 있음을 단언). 상대를 모르는 섬김(`of: '미상'`)의 종류 되살리기는 정답지 f4 어디에도 없어 읽기 벡터 `F4.down:unknown`(되살림 · 짝)으로 지킨다(`lay_read`가 갈래마다 1개 이상을 단언). 파일이 저장소에 없는 선택 자료(`east-asia+ktl@f4`)만 '없어서 건너뜀'.
* **열쇠 차례(바이트 견줌)에 걸린다.** `X@f4`의 정답지는 `X`의 정답지와 풀어서 같지만(일곱 자료 · 네 이음매) **바이트는 다르다** — 형식 4 `down`이 칸의 열쇠를 다시 쌓는다(예: 조선의 지도자 칸이 `start,end,ordinal` → `start,ordinal,end`). 바이트 견줌(과제 13)은 늘 **같은 이름의 정답지끼리**(`X`는 `X`, `X@f4`는 `X@f4`)만 한다.
* **바꾼 결과는 시각 · 시간대와 무관하다**(지금 자료에서): 아홉 입력을 시각 · 시간대 다섯 가지(실제 · 2026-10-15 서울 · 2031-03-04 로스앤젤레스 · 2099-12-31 UTC · 1999-01-01 오클랜드)로 바꿔 압축을 푼 글이 모두 같다. 다만 `normalizePack`은 영토 소유 기록의 '진행 중'을 `HT.CURRENT_YEAR + 1`로 굳힌다(`js/core.js` 4990줄) — 지금 자료에 영토가 없어 새지 않을 뿐, 영토가 든 DLC를 형식 4로 바꾸면 바꾼 해가 파일에 들어간다(과제 5의 읽기가 같은 줄을 옮길 때 알아 둘 것).
* **내장 팩 JSON:** `east-asia.json`(`freeze-builtin.mjs` — `JSON.stringify(HT.getBuiltinPacks()[0])`, 86,189바이트)은 함수 · 고리 · NaN이 없다(undefined 값 277개는 열쇠가 빠질 뿐). ① = ③. `list.json`의 `east-asia` 계열은 `{"builtin":"east-asia","file":"east-asia.json"}` — Node 정답지는 내장 팩에서(`builtin`이 앞), Rust · `f4-same-check`는 파일에서 읽는다.

### 과제 5a — 알려진 차이 (2026-10-16)

* **물려받은 이름 · `__proto__`(뜻 없는 자료에서만 갈림 — 정답지 · 벡터에 넣지 않음):** 웹의 낱말 표 찾기(`RELATION_WORDS[s]` — 5b의 `KIND_WORDS`도)는 `constructor` · `toString` · `__proto__` 같은 `Object.prototype`의 이름도 '찾음'으로 읽고, `Object.assign({}, o)`(형식 4 `omit` 등)는 `JSON.parse`가 만든 제 열쇠 `"__proto__"`를 프로토타입 바꾸기로 다뤄 잃는다. Rust(`lay::read::vocab` · `lay::read::assign_copy`)는 적힌 낱말만 찾고 `__proto__`도 보통 열쇠로 베낀다.

### 과제 5b — 알려진 차이 (2026-10-16)

* **물려받은 이름(5a와 같은 꼴 — 뜻 없는 자료에서만 갈림 · 벡터에서 뺌):** 5b가 옮긴 낱말 표 `HISTORICITY_WORDS` · `SUCCESSION_WORDS` · `DEGREE_WORDS` · `PART_WORDS` · `KIND_WORDS` · `ROLE_WORDS`도 웹은 `WORDS[s]`로 찾아 `constructor` 같은 글에서 함수를 돌려준다 — 실재성 · 도읍 역할은 웹이 알림 없이 칸에 함수를 넣어 JSON에서 빠지고(Rust는 '알 수 없음' 알림 · 역할 없음), 정권 종류는 웹이 함수의 글을 알림에 넣고, 승계 종류는 웹의 `type`이 JSON에서 빠진다(Rust는 `indirect`). Rust(`lay::read::vocab`)는 적힌 낱말만 찾는다. 자리 이음 · 혈연 · 이름 종류의 낱말(`vocab` — `hasOwnProperty`)과 `ROW_ORDER_WORDS`는 웹도 제 낱말만 찾아 차이가 없다.

### 과제 5c — 알려진 차이 (2026-10-21)

* **`__proto__` 열쇠(5a와 같은 꼴 — 뜻 없는 자료에서만 갈림 · 벡터에 넣지 않음):** 문서(`documents`)의 키 · 영토의 조각 지명 기록 · 소유 기록의 조각 id · 패치의 `set` 칸 이름으로 `"__proto__"`를 적으면 웹은 대입(`pack.documents[key] = v` · `names[id] = list`)이나 `Object.assign({}, p.set)`이 프로토타입 바꾸기가 되어 그 열쇠를 잃는다(패치는 알림도 없음). Rust(`lay::read::normalize`)는 보통 열쇠로 둔다(패치는 '패치할 수 없어 무시' 알림). 영토의 `t.generate`(내장 팩 전용 함수)는 JSON으로 오지 않아 옮기지 않았다.
* **`__proto__` 열쇠 — 지도 장면의 주인(덧붙임 · 같은 꼴):** 지도 장면의 `owners`에 구역 id `"__proto__"`를 적으면(그런 id의 구역이 있을 때) 웹은 `owners[rid] = …`(js/core.js 3717 · 3721줄)가 프로토타입 바꾸기라 그 주인을 잃고, Rust(`lay::read::info::read_maps` — `owners.set(&rid, …)`)는 보통 열쇠로 둔다.
* **이음매 ①에 달력 표:** 견본 등불 2.0.1(맞추기 과제 S)의 사건 하나가 "음력 125-08-15"라, `lay_read`의 이음매 ①은 커밋한 잘린 표 `prototype/engine/tests/fixtures/lay/calendar-slice.json`(`node prototype/scripts/calendar-slice.mjs`가 뜸)을 `common::oracle::seam_opts`로 `Opts.calendar`에 넘긴다(계획 정한 것 #7 — 5a 걱정 1을 앞당김 · 판정 R18로 git 밖 `calendar-cache.json`에 기대지 않게 됨).

### 과제 6 — 알려진 거절 (2026-10-21)

* **옮기지 않은 길은 거절한다(조용히 다른 답을 내지 않음):** ① ~~지도 장면의 '그해에 없던 나라' 알림이 날짜 글을 `HT.cal.describe`로 적어야 하면 거절~~ — **과제 Y가 걷음**: 모델도 모듈과 같은 `lay::web::when::format_range`(describe · figureRange까지 옮긴 판)를 부른다(검사 `lay_model::describe_in_model_warning_is_now_ported_and_released` — Node 글과 같음) ② 내 수정(`user`)은 내보내기가 넘기지 않아 옮기지 않았다 ③ 줄 배정(`lay_tracks`)은 과제 7이 열었다(아래 절) ④ ~~`HT.figureRange` 거절~~ — **과제 Y가 걷음**(검사 `lay_model::figure_range_is_now_ported`). JS라면 던졌을 곳(객체가 아닌 값에 칸 쓰기 · Map이 아닌 표)은 `model::util::fault`로 남겨 `build_model`이 오류로 끝낸다. 거절 · 오류 길에서도 지은 그래프는 `js::release`로 푼다.
* **합성 정답지 자료(판정 R19 · 과제 7 얹힌 몫 9):** `synth` · `synth+patch`(+ `@f4` — 패치 DLC 둘: `synth-patch` · 같은 대상을 다시 고치는 `synth-patch2`)가 다른 정답지 자료가 닿지 않던 모델 갈래(인물의 자동 활동 막대 · 사람 잇기의 찾기 실패 · 자동 성씨 · 대범위 기간 짐작 · 자동 주제 · 패치)를 밟는다 — `lay_model::synth_fixtures_reach_the_model_branches`가 표지를 **하위 꼴마다** 센다(AMBIGUOUS 칸 사람 · 부모 · 제도 알림 둘 · patchedBy 종류 다섯 · 숨김 종류 셋 · 날짜는 있고 시작이 없는 이설 · 규격을 버리고 계속 · patchedBy 이어짐 · 끝 없는 점 사건의 세기 시작 · 진행 중 · 인물 시작 · 끝 · 제도 빈 주제 목록).

### 과제 7 — 알려진 거절 · 정답지가 닿지 않는 갈래 (2026-10-21)

* **거절(과제 15가 걷음):** 집합 보기의 판 트랙(`tr.board` — `_boardPlan` · `_boardVisit` · `_boardGroups` · `_boardBranch` · 2942줄 판의 깊이 · 3343줄 `gp.from`)은 이제 옮긴 길이다(갈래 E · 과제 15). 판의 꼴이 JS라면 TypeError인 경우만 오류 — 줄 목록(`tr.board.rows`)이 배열이 아님(검사 `lay_rows::board_without_rows_is_an_error`) · `tl.board.members` · 판 줄의 `periods`가 배열이 아님 · 판의 `view`가 없음(과제 Y — `lay_rows::board_shape_faults_are_errors`). 아래의 옛 설명은 과제 7 때의 기록: `contextOf`(이음매 ②)는 판을 세우지 않지만 **`boards` 모듈(과제 15)이 세운다** — `boards.mjs` `boardOne`(147 ~ 176줄)이 시대 구분마다 판을 세워 `_layoutTrack(btr)`을 부르고 원래 트랙도 `_boardTr`가 선 채로 다시 배치하므로, 지금의 거절은 `upto-boards`에서 시대 구분이 있는 자료(정답지 21개 중 10개 — lantern · nest · synth 계열과 그 `@f4` · `synth`의 `ep-a` 포함)가 문다(과제 8-틀 재검토 — 동아시아 계열 11개는 판이 서지 않음) → 과제 15가 거절을 걷고 판 갈래를 이 함수에 옮긴다(아래 '과제 8 ~ 15'의 넘길 몫). 줄 배정도 점 사건의 날짜 글을 다시 읽으므로(`_precSpan`) 보조 달력 표가 모자라면 정규화 · 모델과 같은 말로 거절한다(정규화가 같은 글을 먼저 읽어 사실상 지키는 줄). JS라면 던졌을 곳(`model::util::fault`)은 줄 배정 · 준비 뒤에 오류로(고침 1회차).
* **이음매 ②(`contextOf`)의 보기 조건이라 `rows.json`이 닿지 않는 갈래(줄 그대로 옮김 · 이 과제에서는 견줌 없음):** 그릇 켬(`scopesOn`이 모두 false — `_scopeClaims` · `_scopeNodes` · `_scopeBranches` · `_scopePad` · 가지 줄 · `_scope`로 `_host`를 비움) · 소속 / 단체 펼침(`expandedHosts` · `expandedGroups` — `pushMembers` · `memberRows`) — **과제 14**(`variants.mjs` REPLAY 125 ~ 129줄이 변형마다 그것 하나만 켜고 다시 배치) · 렌즈(`themeLens` — `HT.lensAny`) · 판(`tr.board` · `_boardTr` — `_foldedNow`의 판 갈래) — **과제 15**(`lens.mjs` 102 ~ 119줄 · `boards.mjs` `boardOne`이 다시 배치) · 민족 접음(`foldedPeoples` — 접힌 줄 · `_laneRow` · `collect`) · 트랙 접음 · 조감(`_bird` — `G_BIRD`) · 밀도 · 표시 끔 · 매단 이름표 접음(`foldedHangs`) — 내보내기가 쓰지 않는 보기 상태(견줄 정답지 없음). 같은 트랙을 다시 배치해도 같은 답(멱등)은 `lay_rows::relayout_is_idempotent`가 지킨다.
* **합성 자료에 더한 줄(과제 7):** `synth.json`의 서녘 줄 — 바탕 문화 연쇄(문화 → 문화 → 나라) · 두 줄에 깔리는 바탕 문화 · 겹치는 구역 탭 둘(단 나눔) · 기관을 섬긴 인물(줄 없음) · 같은 해에 시작하는 나라 아홉(`chainRows`의 욕심 — 첫 줄만 · 부분 승계가 직접 승계보다 먼저 줄을 차지해 갈림). `lay_rows::fixtures_reach_the_layout_branches`가 내보내기가 닿는 갈래 표지를 센다.

### 과제 Y — 웹 함수 모으기 · JS가 던질 곳 (2026-10-22)

* **모은 자리:** 여러 모듈(과 읽기 · 모델)이 함께 부르는 웹 함수는 `lay/web/` — `cells.rs`(`HT.CELL_KINDS` · `cellKind` · `cellSpan` · `cellBound` · `cellRefOf` · `cellToNow`) · `alts.rs`(`HT.altSpan` · `altFlipSide` · `altFlipped` · 모듈 사본 `altEdges`) · `when.rs`(`cal.formatT` · `cal.describe` · `HT.formatDate` · `formatWhen` · `formatRange` · `figureRange` · `altText`) · `words.rs`(`HT.kindName` · `itemWord` · `historicityOf/Name/Tag` · 승계의 이름 · `relationName` · `cmp16` · 물려받은 이름) · `glyphs.rs`(`mergeRanges` · `GLYPH_BAND` · `GLYPH_WINDOW` · `inRanges` · `glyphMissing`). `HT.yearOf` · `HT.formatYear`는 `read::dates`의 하나(JS 값 그대로 — `y + 1e-9`의 글 잇기까지). 모듈 사본(JS 모듈도 파일마다 둔 것 — `lodOf` · `styleWith` · `cellStyle` · `ST` · `STRIP` · `minute` 꼴 · `some` · `idOf` …)은 `lay/m/kit.rs`, `G` 표는 `rows::G0` · `HANG_PITCH` 하나, 날 수 셈은 `js::days_from_civil` · `civil_from_days`, `[...s][0]`은 `Str::first_code_point`.
* **자리를 옮기지 않은 것(계획 글을 사실대로):** `js/wiki.js` → `lay/m/docs/wiki.rs`(docs만 부름) · `kin.mjs` → `lay/m/entities/kin.rs` · `js/group-tree.js` → `lay/m/entities/group_tree.rs`(둘 다 entities만 부름).
* **두 판이 갈리던 곳(버린 판 — 정답지 자료에서는 같은 값):** 날짜 글 — 모델의 `model::util::format_range`는 맞는 날짜 글 · 인물이면 거절했다(이제 같은 `web::when` — 과제 6 '알려진 거절' ① · ④가 걷힘) · `HT.yearOf` · `formatYear` — 수만 받던 판(`read::dates` · metro의 사본)은 글로 온 해에서 JS와 갈렸다 · `succAbsorbs` — 갈래 D의 판은 늘 수로 견줬다(둘 다 글이면 갈림) · `cellSpan` — 갈래 B의 판은 `ref`가 undefined면 칸 참조를 찾지 않았다 · `cal.describe`의 모르는 달력 — '' · 'undefined' 대신 잘못.
* **JS가 던질 곳 → 오류:** `model::util::fault`로 남기면 모듈 돌리기(`export::run_one` — 과제 16b ② 틀 손질)가 모듈마다 끝에서 `m::kit::fault_check`로 그 모듈의 오류로 낸다(모듈이 오류로 돌아가면 남긴 잘못은 거두고 그 오류 · docs는 날짜 글 몫 끝에서도 먼저 봄) — 사람 고리의 빈 사람 자리(부모 · 배우자 · 자식) · 목록 한 줄의 빈 상대(hostRow · memberRow · x_ruled · x_members) · 뼈대 아래 파가 가문 표에 없음 · 가문 members가 배열이 아님 · seq가 0 ~ n−1의 정수가 아님(JS는 던지지 않고 다른 뼈대 — 조용히 다른 답 대신 오류) · `cal.describe`의 모르는 달력 · power `foldedRows`가 Set · Map이 아님 · lens `byTheme`이 Map이 아님 · `model.events`가 순회되지 않음(`for … of` — 배열 · 글 · Map · Set은 돈다 · 16b) · 렌즈 자료 있음(`HT.lensHasData`)의 `periods` · `events`가 배열이 아닌 참값(`.some` — 16b 검토) · `cellBounds`가 Map이 아님. 판 갈래(track.rs)와 줄 이름 · 매단 이름표 · 관계선 · 인물(labels · hangs · links · figures — `foldedRows` · `hiddenRows` · `memberRows`가 Set · Map이 아님 — `kit::has_or_err`)은 곧바로 `Err` — `tl.board.members`가 순회되지 않음 · 계획이 서면 members가 배열이 아님(`v.members.filter` — 16b 검토) · 판 줄 `periods`가 배열이 아님 · 판 `view` 없음(boards가 그 판을 뺀다). `try … finally`(boards의 판 하나 · lens의 렌즈 켬 배치)는 `kit::try_finally` 하나 — 되돌림이 남긴 잘못 > try의 오류 > try가 Ok인데 남긴 잘못(되돌리기 전에 거둠 — 원래 까닭을 가리지 않게). 검사는 모델을 손으로 고쳐 길마다 하나(`lay_m_entities` · `lay_m_power` · `lay_m_lens` · `lay_rows` · `lay_wiki`) · 새로 받는 길의 단위 검사 `lay_frame`(for…of · has · cellBound · try_finally) · `export::run_one`의 단위 검사. 지도 장면 owners의 `readScopeRef` null은 JS · Rust 모두 `String(ref)`라 그대로.

### 과제 X — 합성 정답지 자료 덧붙임(판정 R28 · R29 · R25 — 2026-10-22)

* **자료 둘(가상 이름 · 선택 자료 아님 · `list.json`):** `synth-lay`(`synth-lay.json` — 트랙 다섯: 가람 · 바다 · 나루 · 나뉜 땅 · 옮김 땅) — 다섯 모듈 갈래 보고가 '정답지가 닿지 않는다'고 적은 날짜 칸 · 띠 · 칸 · 사건 · 매단 이름표 · 인물 · 관계선 · 줄 이름 · 노선도 · 문서 · 항목 기록 · 변형 · 집합 보기의 꼴, 그리고 판 하나가 오류로 빠지는 자연스러운 꼴(나뉜 땅 — 같은 해에 시작하는 아홉 나라 가운데 둘만 시대 구분 판에 들면 원래 트랙의 사슬이 욕심 → 훑기로 바뀌어 '기본 상태에 없던 줄'로 그 판이 빠짐) · 변형의 띠 이사 kind 1(옮김 땅 — 고침 1회차: 대범위에 든 숨은 소속이 같은 대범위의 앞 나라를 직접 승계하면 대범위를 켤 때 그 줄을 먼저 차지해 기본에서 이어지던 나라가 옮겨 감 · Node 자체 경고 '높이 계약 ≠ 연표'도 냄 — 그대로 둠). `synth-lens`(`synth-lens.json`) — 렌즈 grow 트랙(지도자 없는 트랙 ln에 institutions만 · rankSpans만 · within 단체 powerSpans만인 나라 셋 — 지도자 있는 트랙과 섞지 않으려고 따로)과 단체 단(짝 모르는 연정 · 연합 둘 · 시작 미정 집권 칸) · 렌즈 칸 비트(연대 폭 · 추정 · 시작 미정). `synth` · `synth+patch`는 그대로(그 위의 셈이 흔들리지 않게). 형식 4 사본 `synth-lay@f4` · `synth-lens@f4`(`f4-same-check --write`) — `synth-lay@f4`는 알려진 차이 11곳(올림의 P1 nest 최소화 · P2 종속 kind → 국가 + 관계 · P4 대범위 구성원 이름 → id — `list.json`의 known · knownDiffs). `lay_m_e_intact`의 변형 뒤 남는 열쇠 수: synth-lay 8 · synth-lens 5(@f4 같음).
* **정답지 이음매 둘 더(`oracle/one.mjs` · mods와 함께):** `notes.json`(`notes.집합보기.뺀판` — 판이 빠진 목록과 까닭 글) · `lens-on.json`(렌즈 켬 배치의 트랙마다 `leaderH` · `height` · `rowHs`). 둘 다 out에 실리지 않는 값이다.
* **검사 `tests/lay_reach.rs`:** 갈래마다 표지 수를 **Node 정답지 파일만** 읽어 세고 새 자료에서 ≥ 1을 단언한다 · 뺀판 목록 · 까닭 글과 렌즈 켬 줄 높이를 Rust와 견준다. 닿을 수 없다고 본 갈래(근거 줄)는 그 파일 머리말. `lay_m_lens::lens_relayout_restores_rows`의 grow는 이제 ≥ 1 단언.

### 과제 calclip — 알려진 차이 · 달력 표 밖은 생략(판정 R61 — 2026-10-22)

* **표 밖은 싣지 않는다(정한 것 #7 · 과제 12b의 '범위 밖이면 거절'을 고침):** 내보내기 `calendar` 모듈(`lay/m/calendar.rs`)은 자료 해 ± 100년 가운데 달력 표와 **겹치는 구간만** `cal:` 기록에 싣고 `note`에 '표 밖 생략 — …'을 적는다 · 겹치는 구간이 없으면 그 달력의 기록을 싣지 않는다(앱은 그 달력의 눈금을 비워 둔다 — `aux_calendar.dart`). 배치 거절은 실제 보조 달력 **날짜**가 표 밖일 때만(`lay::cal::Tables::missed` — "음력 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다" · 끝 문서 과제 전의 글은 "… — 컴퓨터에서 다시 짓기") · 그 달력의 표가 아예 없으면 그대로 "달력 표 없음". 까닭(끝 전체 검토 ② Critical C1): 저장소 표는 −3500 ~ 2500년(판정 R36)이라 보조 달력을 쓰지 않는 DLC도 자료 해가 −3400 ~ 2400년 밖이면 배치 전체가 거절됐고, 옛 Node 넣기 길은 걷혀 어디서도 넣을 수 없었다.
* **Node와 다른 점:** Node(`export/calendar.mjs`)는 모자란 범위를 ICU로 다시 떠 표 밖 구간까지 싣는다. Rust의 `cal:` 기록은 Node 표의 **이어진 한 토막**(첫날 · `year0` · 달 글 · `count` · `to`가 그 자리와 같음)이고 `note`에 '표 밖 생략'이 더 붙는다. 정답지 견줌(`tests/common/oracle.rs`의 `cal_clip_known` — `assert_same` · `assert_same_bytes`가 부름)은 이 차이를 **자료 `synth-calclip`(`CAL_CLIP_FIXTURES`)의 `entities` `cal:` 기록의 `json` 칸**에서만, 한 토막임을 확인한 뒤 같게 둔다(그 밖의 칸 · 자료는 차이 0 그대로 · 기록이 빠지거나 한 토막이 아니면 실패).
* **합성 자료 `synth-calclip`(가상 이름 · 선택 자료 아님 · `list.json`):** 양력만 · 기원전 8000 ~ 1500년 띠 하나 · 1800 ~ 9999년 띠 하나 · 사건 하나 — 자료 해 −8100 ~ 10099년(Node 정답지는 다섯 달력을 ICU로 225,093달(페르시아력 218,391달)씩 떠 `cal:` 기록이 약 2.2MB · 처음 뽑을 때 약 3분 — 그때 넓힌 표는 공용 `prototype/results/calendar-cache.json`이 아니라 도구마다의 임시 사본(과제 testinfra — 공용 표는 `warm-calendar.mjs`로만)). 전용 검사 `lay_m_calendar::calendar_clips_to_the_table_instead_of_refusing`은 검사 표를 다시 가운데만 남겨(달 ¼ ~ ½) 넘기고 다섯 달력 모두 잘림 · Node 표의 한 토막 · 나머지 차이 0을 단언한다(고치기 전에는 "달력 표 범위 밖"으로 거절됐다). 겹치지 않는 표는 `calendar_refuses_missing_table_and_skips_a_table_outside_the_data`(기록 없음 · 거절 없음).
* **`calendar-slice.mjs` · `build-check.mjs`(calclip 고침 1회차 — 판정 R64-2 · 4f08c11):** `list.json`의 `"calClip": true` 표지 자료(이 자료)는 `calendar-slice.mjs`가 뺀다(이 자료의 −8100 ~ 10099년이 검사 표 `calendar-slice.json`에 들어 표가 붓지 않게 — 다시 떠도 표 내용은 커밋본 그대로) · `build-check.mjs`는 `--only`로 이름을 짚을 때만 돌린다(Node는 표 밖까지 ICU로 싣고 Rust는 생략해 `cal:` 기록이 늘 다르므로). 정답지 견줌의 `CAL_CLIP_FIXTURES`도 이 표지에서 읽는다(`@f4` 뗌).

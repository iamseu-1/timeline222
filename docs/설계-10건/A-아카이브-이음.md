# 아카이브 이음 설계 — 형식 3의 새 자료를 새 앱(아카이브) 안의 연표까지 (작업판 A1 · A2 · A3의 바닥)

작성일: 2026-10-12. 클라우드 작업 상자(Linux) · 가지 `claude/compassionate-keller-5ip12l` · 기준 HEAD `90d0284`(w10/F3 → F2 → F1을 합친 판). 통합 작업자의 '잇기 a~e'가 아직 돌고 있어 `js/core.js` · `js/viewer.js`에 기록 전 변경이 있습니다.

근거는 두 조사입니다.
- ① 내보내기 · 엔진: 견본 여섯을 scratchpad 사본에서 지금 내보내기 모듈(`contextOf` · `runModules`)로 내보냈습니다. 리눅스 `archive-tool`로 `import-layout` · `verify-tiles`를 돌려 여섯 모두 누락 · 중복 0을 확인했고, 엔진 `cargo test --release` 133개가 통과했습니다.
- ② 새 앱: 코드를 읽기만 했습니다.

저장소의 코드는 고치지 않았습니다. 작업판 `docs/작업판-10건-통합.md` 2절의 줄 **A1 · A2**와 **A3의 바닥**을 다룹니다. 감독 결정은 아직 없습니다(7절 확인거리). 계약에 더할 글은 부록 가에 초안으로만 적었습니다.

## 0. 한눈에

**지금 상태**
- 새 앱의 상세 창에는 연표 모델이 없습니다. 엔진에서 항목 기록 하나(`{"op":"entity"}`)를 받아 그립니다. 웹 상세 창은 모델을 넘나들며 그 자리에서 값을 찾는데, 새 앱에서는 **내보내기가 넣을 때 한 번 풀어 `x_…`로 실어야** 합니다(계약 6-9 가의 약속). F1 · F2가 웹에 더한 것은 이 미리 푼 값이 없으면 새 앱에 보이지 않습니다.
- 지금 새 앱까지 오는 형식 3 자료는 **있던 항목(정권 · 사건 · 인물 · 가문)에 붙은 원문 칸뿐**입니다. 단체 · 제도 · 지명 · 성씨 · 주제 · 판 · 지도 · 글꼴은 기록이 없습니다. 계보 · 혈연은 풀어낸 값이 없습니다. 원어 · 옛 이름 · 로마자로는 찾히지 않습니다. 결함도 여섯 개 있습니다(2-2).

**고칠 곳 — 네 층**
- **내보내기**: `export/entities.mjs` · `docs.mjs` · `calendar.mjs` · `base.mjs`.
- **엔진**: 이름 표 · 검색 · 도읍 주인.
- **새 앱**: 있던 창의 새 줄 · 단체 · 제도 창 · 검색.
- **계약**.
- 메이커가 같은 모듈을 씁니다(B5). 그래서 내보내기를 고치면 `.htlayout`에도 같은 값이 저절로 실립니다.

**엔진 스키마 판은 올리지 않습니다(`'3'` 그대로).**
- 판이 다르면 엔진이 저장소를 거절합니다. 판을 올리면 감독의 휴대폰 · 배포 폴더의 저장소가 모두 열리지 않습니다.
- 더하는 것은 열 하나(`names.hay`)와 본문 색인의 덧줄뿐입니다. 옛 저장소는 그대로 열리고 예전처럼 답합니다.

**작업 나누기**
- **A1**은 파일이 겹치지 않는 **여덟 묶음**(A1-0 · a~g)으로 나눕니다(4절). A1-0 다음에 넷(a · b · c · f)이 나란히 돕니다.
- **A2**(메이커의 `.htlayout`을 Node 없이 가져오기)는 엔진에 두 가지를 더합니다. 하나는 종류 3 읽기이고, 하나는 `archive_call`의 잠금 밖에서 도는 호출 `archive_import`입니다. 앱의 DLC 더하기에는 갈래 하나를 둡니다.
  - 막는 것은 둘입니다. **조합 대조**(배치는 셈한 조합에서만 맞습니다)와 **원본 없음**(`.htlayout`에는 DLC 본문이 없습니다)입니다. 추천안은 5절에 있습니다.
- **A3**(띠 안 새 그림)의 바닥으로 지금 깔 수 있는 것은 **번호 예약 · 창 자료 · 엔진과 앱의 통과 검사**까지입니다. 줄 높이 · 판 변형 · 그림 바이트는 감독 선택(D1~D6)과 웹 배치가 먼저입니다(6절).

## 1. 목표 — 감독 지시

> "모두 아카이브 내에서 들어갈 연표 모듈로써 작동해야 하는 거 잊지 말고" (2026-10-12)

웹 연표에서만 되는 기능을 만들지 않습니다. 형식 3으로 더한 것은 **새 앱(아카이브) 안의 연표에서도 같은 것**이 되어야 끝난 것입니다. 이 문서에서 '같다'의 기준은 다섯입니다.

1. **상세 창** — F1 · F2가 `js/viewer.js`에 더한 줄이 새 앱 창에 **같은 글 · 같은 차례**로 섭니다. 글은 웹이 만든 글 그대로입니다(6-9 가의 약속 4). 해당하는 줄:
   - 원어 줄 · 자리 이음 · 사람 · 혈연 · 지명 · 성씨 배지
   - 주제 · 법 · 선거 딱지, 법 양식, 선거 표, 맺은 단체
   - 나라의 단체 칩 · 제도 칩, 단체 창, 제도 창
2. **검색** — 새 앱도 웹 `runSearch`가 찾는 것을 찾습니다(이름 목록의 원어 · 로마자 · 옛 이름, 도읍 지명의 원어, 단체 · 제도, 설명 · 태그). 결과 줄의 갈래 · 차례 · 고른 뒤의 움직임도 같습니다.
3. **자료 나르기** — F3(모아 보기 판 · 지도 · 글꼴)은 웹에도 아직 화면이 없습니다('자료만'). A1은 이것을 저장소까지 **잃지 않고 나르는** 데서 멈춥니다. 화면은 A3에서 웹과 함께 만듭니다.
4. **옛것 그대로** — 형식 3 열쇠가 없는 자료(동아시아 · 월흔해)는 타일 · `layout` 답 · 그림이 바이트까지 같습니다. 옛 저장소는 그대로 열리고, 새 줄만 비어 보입니다. 이때 옛 화면이 조용히 비지 않고 예전대로 그립니다(구역 46의 선례).
5. **메이커에서 바로** — 메이커가 낸 `.htlayout`을 앱이 Node 없이 받아 같은 저장소를 만듭니다(A2). 휴대폰에는 이 길밖에 없습니다.

지키는 원칙은 넷입니다.
1. **새 앱은 모델을 갖지 않습니다.** 넣을 때 한 번 풉니다.
2. **노드 도구와 메이커 일꾼은 같은 모듈 · 같은 글입니다**(B5 — `scripts/maker-archive-check.mjs`). 그래서 내보내기 모듈에 `node:` 가져오기를 쓰지 않습니다.
3. **스키마 판은 `'3'` 그대로입니다.** 열 · 표를 더하고 `pragma_table_info`로 있는지 봅니다. `names.cell_ref` · 변형 표 · `lens_names`가 같은 선례입니다.
4. **가져오기 JSON 3판의 겉 열쇠는 늘리지 않습니다.** 예외는 `packs[]`의 두 칸(`version` · `category`)과 `entities[].pack`의 명문화뿐입니다(이 둘은 엔진이 이미 읽거나 모르면 버립니다).
   - 새 값은 항목 기록 `json` 안의 `x_`로 싣습니다. 그러면 엔진이 가져오기(`legacy.rs`)를 고치지 않고도 넣을 때 읽습니다.
   - 이렇게 하는 까닭이 하나 더 있습니다. A1과 A2가 같은 Rust 파일을 만지지 않게 하려는 것입니다(4-3).

## 2. 지금 상태 — 무엇이 실리고 무엇이 빠지나

### 2-1. 실리는 길

- **내보내기**: `export/entities.mjs`의 `contribute`가 싣는 목록은 `periods` · `events` · `figures` · `epochs` · `scopes` · `houses`뿐입니다(HEAD 426~431줄).
  - 본문은 `plain()`이 만듭니다. `plain()`은 뿌리가 아닌 곳의 uid 객체를 `{"$ref","name"}`으로 접습니다.
  - 그래서 있던 항목에 붙은 새 칸은 원문 그대로 **저절로** 실립니다. 해당 칸은 `names`, 지도자 칸의 `person` · `accession` · `parents` · `spouses`, 인물의 `parents` · `spouses`, 사건의 `place` · `theme` · `themeRefs` · `law` · `election`, 가문의 `surnameId`입니다.
- **엔진**: `legacy.rs`의 `fill`은 항목 기록을 `b.entity(uid, pack_at(..), kind, json)`으로 해석 없이 넣습니다. 새 `kind`를 넣어도 스키마를 고칠 필요가 없습니다.
- **조회**: 상세 창은 `entity` · `entities`를 씁니다. 검색은 이름 표 `names`(`builder.rs`의 `build_names`)와 사건 본문 색인을 씁니다.
  - 이름 표는 기록의 `$.name`/`$.title` 하나와 칸 이름만 싣습니다. 맞추는 글은 `n.name||' '||n.sub`입니다.
  - 사건은 `e.title||' '||e.body`로 맞춥니다(`body` = 설명).
  - `SEARCH_KINDS`(`query.rs` 81줄)는 12갈래로 고정되어 있습니다.
- **앱**: `detail_shell.dart`의 `pickDetailKind`가 갈래를 고릅니다. 모르는 kind는 `item`으로 떨어집니다. `item`은 줄로 날아가고 연표를 흐리게 하며 고릅니다.

**견본별 실측** (모델에 있는 수 → 내보낸 항목 기록)

| 견본 | 모델 | 내보낸 항목 기록 |
| --- | --- | --- |
| `sample-names` | 지명 3 · 성씨 2 · 사람 4 | period 2 · dynasty 1 · event 2 · figure 1 · house 3 · cal 5 (지명 · 성씨 0, 문서 0) |
| `sample-lineage` | 사람 14 | 원문 칸만 있음. 자리 이음 · 혈연을 풀어낸 값 없음 |
| `sample-groups` | 단체 8 · 주제 8 | 단체 0 · doc 4 |
| `sample-lens` | 제도 11 · 주제 9 | 제도 0 |
| `sample-views` | 판 2 | 0 |
| `sample-map-image` | 지도 1 | 0 |

### 2-2. 확인된 결함

| # | 결함 | 실측 | 고칠 곳 | 묶음 |
| --- | --- | --- | --- | --- |
| 1 | **기록 없는 `$ref`**: 정권의 `groupLinks[].group` · `institutionList[]`, 사건의 `groupRefs[]`가 기록 없는 uid를 가리킴. 끝의 점검은 `x_` 값만 봄 | `entity sample-groups/gr-east` → "항목 기록이 없습니다" | 단체 · 제도 기록을 싣고 점검을 `$ref`까지 넓힘 | A1-a |
| 2 | **문서가 조용히 빠짐**: `docs.mjs`의 `baseInfo`(66줄)에 `surname` · `place` 갈래가 없어 null. `nameToBase`에 단체 · `[[단체:이름]]` 없음 | 견본의 `place:pl-bluecliff` · `surname:sn-sol` 문서가 0건 | `docs.mjs` | A1-a |
| 3 | **자료집 귀속이 틀림**(형식 3 전부터): `/`가 없는 uid(`house:` · `doc:` · `cal:`)는 기본 DLC로 붙음. 엔진은 이미 `en.pack`(순번)을 읽는데 내보내기가 싣지 않음 | 월흔해 + names: `house:h-names-*` 셋이 pack 1 → `packs:[2]`로 "솔바위 가문"을 찾으면 0건 | 모든 기록에 `pack` | A1-a |
| 4 | **도읍 칸의 주인이 틀림**: `build_names` 4-가의 `axis_owner`가 `name` · `as` · `city` · `label`을 모두 후보로 두고 첫 줄을 고름 | 갑 왕국의 `capital:0` "푸른 벼랑"이 을 공국으로 붙음(을 공국 `capital:0`의 `city`가 "푸른 벼랑"). F1이 "같은 도시는 같은 이름으로"를 권하므로 늘어남 | `$.name`을 먼저 맞추고, 같으면 트랙으로 가림 | A1-b |
| 5 | **검색이 모자람**: 로마자 · 옛 이름으로 0건. `kinds:["group"]`은 "모르는 갈래"로 실패. 설명 · 태그 · 트랙 이름으로 찾는 것도 웹과 다름(전부터) | "Gap" · "솔나라" 0건 | 찾을 글 · 새 갈래 | A1-a · b · e |
| 6 | **사람 잇기 기준이 웹과 다름**: `x_leaderFigures` · `x_leaders`가 이름만 같은 인물을 찾음. 웹 F1은 칸에 적은 `person`(`HT.personOf`)을 먼저 봄 | 웹과 다른 인물이 붙을 수 있음 | `crossRefs` | A1-a |

## 3. 열쇠마다 나르는 길

표에 쓰는 말:
- **그릇**: 항목 기록 `json`에 싣는 것(스키마 그대로). 열쇠 이름과 꼴은 부록 가-6(계약 초안 6-9 다)에 있습니다.
- 엔진 칸의 **스키마**: 표 · 열을 바꾸는지.
- **판**: `meta.schema`를 올리는지. 이 문서에서는 모두 "그대로"입니다.
- **옛 저장소**: 이 일 전에 지은 저장소가 어떻게 답하는지.

| 열쇠(형식 3) | 내보내기 — 모듈 · 싣는 값 | 가져오기 JSON 3판의 자리 | 엔진 — 스키마 · 옛 저장소 | 조회 | 새 앱 부품 | 묶음 |
| --- | --- | --- | --- | --- | --- | --- |
| **`names`** (시대 · 왕조 · 가문 · 성씨 · 인물 · 지도자 · 내각 · 연호 칸 · 지명 · 사건 — 잇기 b 뒤로 단체 · 제도 · 판 · 지도도) | `entities.mjs`. 기록에 `x_names{main,other}`(`HT.namesSplit` 차례 + 웹 `nameTag` 글). 정권에는 칸마다 `x_cellNames{"leader:3":…}`. 찾을 글은 `x_find`(맨 아래 줄) | `entities[].json` 안 | 이름 표에 열 `names.hay` 하나를 더함. 옛 저장소는 열이 없어 지금처럼 이름 · 곁글로만 맞춤 | `search` · `search_year` | 공용 원어 줄(FSI…PDI 격리 · 표준 꼬리표면 `locale`). 기본 · 칸 · 인물 · 가문 창에 둠 | a · b · c · d · e |
| **`surnames`** | 새 기록 `surname:<id>`(kind `surname` · `x_names` · `x_houses`). 가문에 `x_surname{uid,name,names}` | entities | 없음. 이름 표에 넣지 않음(웹도 성씨를 결과 줄로 내지 않음 — 가문 결과의 찾을 글에만 들어감) | `entity` | 가문 창의 성 배지 · `성 X — 원어` 줄 · 문서 창(`surname:` 바탕) | a · d |
| **`places`** · 사건 `place` · 도읍의 도시 | 새 기록 `place:<id>`(`x_names` · `x_path` · `x_children` · `x_uses`). 사건에 `x_place`. 정권에 `x_cellPlaces{"capital:0":…}`(웹처럼 원어나 위 구역이 있을 때만). 도읍 칸의 찾을 글에 지명 원어 | entities | 없음. 도읍 칸 주인을 고침(결함 4). 이름 표에는 넣지 않음 | `entity` | 사건 창 · 칸 창의 지명 줄 · 문서 창(`place:` 바탕) | a · b · d |
| **`person`** (지도자 · 내각 칸) | 정권 `x_persons{"leader:3":{figure,others,parents,spouses,children}}`. 인물 `x_person{ruled,parents,spouses,children}`. `x_leaderFigures` · `x_leaders`의 규칙을 `HT.personOf`로 바꿈(결함 6) | entities | 없음 | `entity` | 칸 창의 사람 줄 · 같은 사람의 다른 칸, 인물 창 | a · d |
| **`accession`** (자리 이음) | 정권 `x_lineage{"leader:3":{from,kin,how,…,restored,elsewhere}}` — `HT.lineageOf(model,p).rulers`를 칸 참조 열쇠로 편 것 | entities | 없음. 띠 위 이음매는 A3에서 칸 `style` 27~28 — 지금은 예약만 | `entity` | 칸 창의 자리 이음 줄. A3에서 계승표 창 | a · d |
| **`parents` · `spouses`** · 세계표 | 정권 `x_persons`와 인물 `x_person`의 혈연 줄. 가문 `x_family{nodes,edges}`(`HT.familyOf` — 노드는 차례 번호로) | entities | 없음 | `entity` | 칸 · 인물 창의 혈연 줄. A3에서 세계표 창 | a · d |
| **`groups`** | 새 기록 kind `group`(uid `<DLC id>/<id>` — 모델 uid 그대로, 본문 `plain` 약 1.2KB). 미리 푼 값: `x_type` · `x_within` · `x_members` · `x_power` · `x_from` · `x_into` · `x_people` · `x_event` · `x_warnings` · `x_find{sub,span,color,row}`. 정권에 `x_groupLinks`, 사건에 `x_groups` | entities | `SEARCH_KINDS`에 `group`. 이름 표 줄(곁글 · 기간 · 색, 그 나라의 줄을 빌림). 옛 저장소는 빈 결과 | `entity` · `search` | 새 `detail_group.dart`(`pick:false` · `lane:false`), 나라 · 사건 창의 칩, 검색 | a · b · c · d · e |
| **`institutions`** | 새 기록 kind `institution`. 미리 푼 값: `x_theme` · `x_polity` · `x_spans`(`HT.phaseRangeText` 글) · `x_same` · `x_warnings` · `x_find`. 정권에 `x_institutions`(주제 차례) | entities | `group`과 같은 길 | 같음 | 같은 파일의 제도 창, 나라 창의 칩 | a · b · c · d · e |
| **`themes`** (주제 사전) | 기록 하나 uid `themes`(kind `themes` · `{list:[{id,name,color,order,auto}]}`). `name` 칸이 없어 이름 표에 들지 않음 | entities | 없음 | `entity` | A3에서 렌즈 고르기 · 렌즈 차림표 | a |
| 사건 **`themeRefs` · `law` · `election`** | `themeRefs`는 본문 그대로(지금도 실림). `x_law` · `x_election`(웹 글로 푼 것). 이 일로 맺은 단체 `x_groups` | entities | 없음 | `entity` | 기본 창 `_badges`의 딱지 · 법 양식 · 선거 표 | a · d |
| **`views`** (모아 보기 판) | 기록 `view:<id>`(본문 + `x_members` · `x_span`). 나르기만 | entities | A1에서는 없음. 판 변형(`view:` 열쇠 · 트랙을 넘는 쌓기)은 `variants.track`이 하나뿐이고 `variant_rows.after`가 트랙 안 사슬이라 **새 표가 필요**함 → A3에서 D4 · 웹 배치 뒤 | `entity` | A1에서는 없음(A3) | a |
| **`maps`** | 기록 `map:<id>`: 그림 데이터 URL을 뺀 본문(그 자리에 `{"$bytes":n}`) + 장면의 주인 `x_scenes` | entities | A1에서는 없음. 그림은 A3에서 새 표(6절 바닥 6) | `entity` | A1에서는 없음(A3 — 지도 판) | a |
| **`fonts`** | 기록 `font:<id>`: `family` · `license` · `scripts` · `note`. `src`는 `{"$bytes":n}`으로 갈음 | entities | A1에서는 없음. 바이트는 A3에서 새 표 | `entity` | A1에서는 없음(A3 — 글꼴 팩) | a |
| 팩 정보 **`version` · `category`** (지도팩 `map` 포함) | `base.mjs` `runModules`의 `packs[]`에 두 칸 | **겉 열쇠** `packs[].version` · `category`. 모르는 열쇠는 무시하므로 옛 엔진도 그대로 | 새 메타 키 `meta.pack_info`(표 아님). `layout.packs[]`에 `version` · `category` · `original`. 옛 저장소는 빈 값 | `layout` | DLC 카드의 판 · 지도팩 표시 · A2의 조합 대조 | a · A2 |
| 모든 기록의 **`pack`** (결함 3) | `entities.mjs` · `docs.mjs` · `calendar.mjs`가 `pack`(배치의 `packs[]` 순번)을 실음 | `entities[].pack` — 엔진이 전부터 읽음(계약에 적기만) | 없음. 옛 저장소는 다시 지어야 바로잡힘 | `packs` 거르기 | 없음 | a |
| 문서 바탕 **`surname:` · `place:`** · **`[[단체:이름]]`** | `docs.mjs`: `baseInfo`에 두 갈래(곁글 `성씨 · 가문 n` · `지명 · 쓰인 곳 n`). `byName`에 단체(가문 다음, 이름이 겹치면 `단체:이름`). `nameToBase`가 `단체:`를 받음 | entities(`doc:` 기록) | 없음 | `entity` | `doc_window.dart` 그대로(연표로 데려가기가 `bus.select(uid)`라 단체 갈래가 생기면 이어짐) | a |
| **찾을 글** (모든 검색 대상) | 기록마다 `x_find.hay`(3-2의 규칙). 칸은 `x_find.cells{"leader:3":…}` | entities | 이름 표 `hay` = `x_find.hay` + 기록의 `$.description`. 사건은 본문 색인에 **덧줄**(rowid = −사건 번호 · 표는 그대로) | `search` | 없음(답의 꼴 그대로) | a · b |

### 3-1. 엔진이 바뀌는 것 — 모아 보면

| 바뀌는 것 | 파일 | 스키마 | 판 | 옛 저장소를 새 엔진이 열 때 |
| --- | --- | --- | --- | --- |
| `names`에 열 `hay TEXT NOT NULL DEFAULT ''` | `schema.rs` · `builder.rs` · `query.rs` | 열 하나 | `'3'` 그대로 | `pragma_table_info('names')`에 `hay`가 없으면 지금처럼 `name` · `sub`로만 맞춤 |
| 사건 본문 색인의 덧줄: rowid = −(사건 번호), 내용은 다른 이름 · 장소 · 태그 … 의 낱자 | `builder.rs` · `query.rs` | 없음(같은 FTS 표) | 그대로 | 덧줄이 없을 뿐 답은 같음. 옛 모양 `search`(`kinds` 없음)는 rowid가 음수라 사건에 이어지지 않으므로 덧줄을 보지 않음 |
| `build_names` 넷: ① 넣는 갈래를 **허용 목록**으로 ② 단체 · 제도 줄(줄 빌림) ③ 칸 · 도읍의 찾을 글 ④ 도읍 주인 고침 | `builder.rs` | 없음 | 그대로 | 다시 지어야 반영(이름 표는 넣을 때 한 번 편다 — 계약 2-3) |
| `SEARCH_KINDS`에 `group` · `institution`. 두 갈래와 가문은 넣은 차례(rowid)로 답함 | `query.rs` | 없음 | 그대로 | 빈 결과 |
| `meta.pack_info` · `layout.packs[]`의 세 칸 | `legacy.rs` · `layout.rs` (A2-a) | 메타 키 | 그대로 | 빈 값 |
| `.htlayout` 읽기 · `archive_import` | `lib.rs` · `legacy.rs` · `main.rs` (A2-a) | 없음 | 그대로 | — |

- 반대 방향(**새 저장소를 옛 엔진이 열 때** — 예: 새 저장소를 받은 옛 APK)도 됩니다. 옛 코드는 열 이름을 적어 읽으므로 `hay` 열과 덧줄을 모른 채 지나칩니다.
- **허용 목록**: `period · organ · culture · dynasty · figure · epoch · scope · house · group · institution · doc`(하위 문서만) + 칸 줄입니다.
  - 지금 이름 표에 드는 갈래와 같고, 단체 · 제도만 늘었습니다.
  - 이렇게 정해 두면 `themes · view · map · font · place · surname · cal`처럼 이름 칸이 있어도 웹이 결과로 내지 않는 기록이 검색을 더럽히지 않습니다.

### 3-2. 검색을 웹과 같게 — `x_find`의 규칙

웹의 찾을 글(`_hay`)은 이름만이 아닙니다. 설명 · 태그 · 날짜 글 · 트랙 이름 · 관점 · 민족 · 종류 · 소속 · 조약 글 · 실재성 · 이름 목록 · 장소가 들어갑니다(`js/viewer.js` `runSearch` — HEAD 476~546줄). 새 앱은 지금 이름 · 곁글과 제목 · 설명만 맞춥니다. 이 차이는 형식 3 전부터 있었습니다. `x_find`로 형식 3의 원어 · 옛 이름과 이 오래된 차이를 함께 메웁니다.

1. **같은 셈** — 웹 글을 옮겨 적지 않는 것이 좋습니다.
   - 추천: `runSearch` 안의 찾을 글 만들기를 `js/core.js`의 `HT.searchHay(model, x, kind)`로 떼어 냅니다(웹 몫 — 7절 확인거리 9). 웹과 내보내기가 같은 함수를 부르게 됩니다.
   - 그 전에는 A1-a가 같은 식을 `export/entities.mjs`에 옮기고, 웹 대조 검사(A1-f · g)로 어긋남을 잡습니다.
2. **이름 · 설명은 빼고 싣습니다.** 본문에 이미 있어 두 번 싣지 않으려는 것입니다. 엔진이 이름 표의 `hay`에 기록의 `$.description`을 이어 붙입니다. 사건은 제목 · 설명이 이미 본문 색인에 있습니다.
3. **칸**: 웹 `HT.CELL_KINDS`의 모든 종류가 대상입니다. 칸의 `temple · title · given · city · label · group · note · names`를 모으고, 도읍이면 `HT.placeOf`의 원어를 더해 `x_find.cells["capital:0"]`에 둡니다. 엔진은 칸 참조(`cell_ref`)로 짝짓습니다.
4. **단체 · 제도**: 네 값을 싣습니다.
   - `sub`: 결과 줄의 곁글 — 웹 결과 줄 글 그대로.
   - `span`: 분.
   - `color`.
   - `row`: 줄을 빌릴 정권 uid. 웹은 그 나라 줄로 데려가고 그 트랙을 끄면 숨깁니다. 앱의 거르개도 이 줄로 맞습니다.
5. **날짜 · 간지 검색**에는 단체 · 제도 · 가문을 넣지 않습니다. 웹도 `!dq && !ganji`일 때만 넣습니다.
6. **결과 차례**: 웹은 `간지 해 → 항목(시작 순) → 칸(시작 순) → 하위 문서 → 가문 → 단체 → 제도`이고, 뒤의 셋은 **모델 차례**입니다. 엔진은 그 갈래를 넣은 차례(rowid)로 주고, 앱은 시작 순으로 다시 줄 세우지 않습니다. 제도는 모델이 주제 차례로 두므로 시작 순으로 세우면 어긋납니다.
7. **검색 강조**: 단체 · 제도 · 가문은 강조에 넣지 않습니다(웹의 `hi` 묶음).

## 4. A1 — 작업 묶음 (파일이 겹치지 않게)

### 4-0. 차례

```
A1-0 계약 옮겨 적기(총괄) ─┬─ A1-a 내보내기 ─────────────────────────────────────────┐
                           ├─ A1-b 엔진(찾을 글 · 새 갈래 · 도읍 주인) ── A1-e 앱 검색 ─┤
                           ├─ A1-c 앱 공용 부품(1걸음) ── A1-c 단체 · 제도 창(2걸음) ───┤
                           │                           └─ A1-d 있던 창의 새 줄 ────────┤
                           └─ A1-f 웹 정답 뜨기 ────────────────────────────────────────┴─ A1-g 이음 검사 · 마무리(총괄)
```

**언제 시작하나**
- A1-0이 끝나면 a · b · c(1걸음) · f가 함께 시작합니다. 이 넷은 서로를 기다리지 않습니다.
  - a는 노드 출력으로 검사합니다.
  - b는 Rust 검사 안에서 손으로 쓴 배치 JSON을 씁니다.
  - c · d는 손으로 쓴 고정 자료를 씁니다.
  - f는 웹만 읽습니다.
- A1-d는 A1-c 1걸음(공용 부품 파일)이 기록된 뒤에 시작합니다.
- A1-e는 A1-b보다 **먼저 합치지 않습니다**. 앱이 `group`을 보내면 옛 엔진은 검색 전체를 "모르는 갈래"로 실패시킵니다.
- A1-g는 모두 들어온 뒤에 합니다.

### 4-1. 묶음 모두의 규칙

**제 파일**
- 묶음마다 **제 몫의 파일만** 고칩니다(4-3 표).
- 남의 파일을 고쳐야 하면 고치지 말고 보고에 적습니다.
- `git add` · `commit`은 총괄이 합니다(계약 0절).
- 계약 문서는 총괄(A1-0 · A1-g)만 고칩니다.

**글 · 자료**
- 한국어 · 줄 끝 LF · 가상 이름만 씁니다.
- 새 Rust 크레이트 · Dart 패키지는 넣지 않습니다.
- 내보내기 모듈에 `node:` 가져오기를 쓰지 않습니다. 메이커의 브라우저 일꾼에서도 돌기 때문입니다(B5).
- 만든 저장소 · 출력은 새 이름을 씁니다(`prototype/data/f3-*` · `results/compat/f3-*.json`).
- `packs/` · 기존 `samples/*.json`은 고치지 않습니다.

**통합 작업자와 순서**
- 통합 작업자의 **'잇기 e — 아카이브 내보내기 형식 3'**이 A1-a와 같은 파일(`export/entities.mjs` · `docs.mjs`)을 만집니다.
- A1-a는 잇기 e가 기록된 뒤에 시작합니다. 시작할 때 `git log -- prototype/scripts/export`로 이미 들어온 것을 3절 표와 대조하고, 빠진 것만 합니다.

**클라우드 명령**

| 무엇 | 명령 |
| --- | --- |
| Rust 전부 | `cd prototype/engine && cargo test --release` |
| Dart 검사 하나 | `cd prototype/app && PATH=/opt/flutter/bin:$PATH LD_LIBRARY_PATH=/home/user/timeline/prototype/engine/target/release flutter test --no-pub test/<파일>` |
| Dart 분석 | `PATH=/opt/flutter/bin:$PATH dart analyze --fatal-infos lib/<제 파일> test/<제 검사>` |
| 견본 내보내기 (A1-a 뒤) | `HT_EXPORT_SAMPLE=sample-groups HT_EXPORT_NAME=f3-groups.json node prototype/scripts/export-layout.mjs` |
| 가져오기 | `prototype/engine/target/release/archive-tool import-layout prototype/results/compat/sample-groups.htpack prototype/results/compat/f3-groups.json prototype/data/f3-groups/archive.db` |
| 타일 검사 | `archive-tool verify-tiles <저장소> 2000` |

- Dart 전체의 조사 때 기준은 통과 1,096 · 실패 0 · 건너뜀 100입니다.

### 4-2. 묶음별

#### A1-0 — 계약 옮겨 적기 (총괄 · 먼저)

- **맡는 파일**: `docs/계약-아카이브-3단계.md` · `docs/작업판-10건-통합.md`(진행 기록 한 줄).
- **할 일**:
  - 부록 가를 감독 답(7절 1 · 2 · 5 · 6)에 맞춰 계약에 옮깁니다. 들어갈 자리는 2-1 · 2-3 · 4절 · 6-9 · 6-9 가 · 6-9 나와, 새로 만드는 6-9 다 · 2-7 · 번호 예약 표입니다.
  - 열쇠 이름은 이 문서 3절 표와 한 글자도 다르지 않게 합니다.
- **검사**: 문서뿐입니다.
- **통과 기준**: 묶음들이 함께 읽을 하나의 판이 섭니다. 이 뒤로 열쇠를 바꾸려면 총괄을 거칩니다.

#### A1-a — 내보내기: 새 기록 · 미리 푼 값 · 찾을 글 · 귀속

**맡는 파일**
- `prototype/scripts/export/entities.mjs` · `export/docs.mjs` · `export/calendar.mjs` · `export/base.mjs`
- `prototype/scripts/export-layout.mjs`
- 새 `prototype/scripts/f3-export-check.mjs`
- 생성물 `prototype/app/test/fixtures/f3-*.json`. 이 이름 갈래는 A1-a만 씁니다.

**할 일**

1. **새 기록** — `contribute`의 `add` 고리에 다음을 더합니다(uid · kind는 부록 가-6).
   - `model.groups` · `institutions` · `places` · `surnames` · `views`
   - `maps`(그림 뺌) · `fonts`(바이트 뺌)
   - 주제 사전 기록 `themes` 하나
2. **귀속** — 모든 기록에 `pack`(배치의 `packs[]` 순번)을 싣습니다.
   - 모델 항목은 `ctx.packOf(x)`를 씁니다.
   - 사전 항목(지명 · 성씨)은 정의한 DLC, 저절로 생긴 것은 처음 쓰인 항목의 DLC입니다.
   - 가문 · 문서 · 보조 달력은 제 `packId`를 씁니다.
   - 엔진은 고치지 않습니다. 이미 `en.pack`을 읽습니다.
3. **미리 푼 값** — `crossRefs`에 부록 가-6의 `x_`를 더합니다.
   - 모델 함수를 그대로 부릅니다: `HT.namesSplit` · `HT.lineageOf` · `HT.familyOf` · `HT.personOf` · `HT.placeOf` · `HT.phaseRangeText`.
   - 단체의 구성원은 잇기 a가 통합한 사람 풀이를 씁니다.
   - 시간은 분, 글은 웹 글 그대로, 빈 값은 싣지 않습니다(6-9 가의 약속).
4. **사람 잇기 기준**: `x_leaderFigures` · `x_leaders`를 `HT.personOf`로 바꿉니다(결함 6). 바뀐 고리는 목록으로 보고합니다.
5. **찾을 글**: 3-2의 규칙대로 `x_find`를 싣습니다. `HT.searchHay`가 있으면 그것을 부르고, 없으면 같은 식을 옮겨 씁니다.
6. **점검을 넓힙니다** — 끝의 고리 점검을 `$ref`까지 넓힙니다(결함 1).
   - `$ref` · `x_`의 uid마다 기록이 있어야 하고, 없으면 내보내기를 멈춥니다.
   - 예외는 목록으로 두지 않습니다. 못 찾은 것은 웹처럼 `name`만 싣습니다(`missing:1`).
7. **문서** (`docs.mjs`):
   - `baseInfo`에 `surname` · `place` 갈래를 둡니다(웹 `baseInfo` 3002 · 3006줄과 같은 글).
   - `byName` · `nameToBase`에 단체와 `단체:` 접두를 둡니다(웹 3045 · 3110줄과 같은 차례).
   - 문서 기록에 `pack`을 싣습니다.
8. **팩 정보**: `base.mjs` `runModules`의 `packs[]`에 `version` · `category`를 더합니다. 노드와 메이커가 같은 코드를 지나므로 둘이 같은 글을 낸다는 성질은 그대로입니다.
9. **견본 손잡이**: `export-layout.mjs` · `base.mjs`의 `loadContext`에 `HT_EXPORT_SAMPLE=<samples 아래 이름>`을 더합니다. 원본 `.htpack`은 지금처럼 `HT.packFile.build`로 함께 만듭니다.
   - 견본을 월흔해 위에 얹을 때는 있는 `HT_EXPORT_EXTRA`를 그대로 씁니다.
10. **점검 도구** — 새 `f3-export-check.mjs`가 견본 여섯과 월흔해 + names를 내보냅니다. 그리고 다음을 냅니다.
    - 표: 모델 수 = 갈래별 기록 수.
    - 크기: 항목 기록 MB · 미리 푼 값 MB.
    - 귀속 대조.
    - 앱 고정 자료 `f3-<견본>.json`(검사가 쓸 기록 몇 개를 뽑은 것 — 지금 `people-*.json`과 같은 꼴).

**검사**
- `node prototype/scripts/export-layout.mjs`(월흔해)와 `HT_EXPORT_PACK=east-asia`의 출력을 이 일 **전 출력**과 견줍니다.
  - `entities`를 뺀 나머지(트랙 · 줄 · 띠 · 칸 · 사건 · 일반 항목 · 날짜 칸 · 변형)는 **바이트까지 같아야** 합니다.
  - `entities`는 갈래별로 늘어난 것과 바뀐 고리만 있어야 합니다.
- 견본 여섯 → `import-layout` → `verify-tiles 2000`.
- `node scripts/maker-archive-check.mjs`(노드 도구와 메이커 일꾼이 글자까지 같은지 — B5).
- `node scripts/dev-smoke.mjs`(웹이 그대로인지).

**통과 기준**
- 위 바이트 대조에서 차이 0.
- `verify-tiles` 누락 · 중복 0.
- 모델 수와 기록 수가 견본마다 같음.
- 매달린 고리 0. `entity sample-groups/gr-east`가 답함.
- 월흔해 + names 저장소에서 `packs:[2]`로 "솔바위 가문"이 찾힘.
- `maker-archive-check` 통과.
- 월흔해 항목 기록 크기와 가져오기 시간을 재어 보고함(지금 6.9MB · 계약 6-9 가). 두 배를 넘으면 멈추고 보고합니다.

#### A1-b — 엔진: 찾을 글 · 새 갈래 · 도읍 주인

**맡는 파일**: `prototype/engine/src/schema.rs` · `builder.rs` · `query.rs` · 새 `prototype/engine/tests/format3.rs`. `lib.rs` · `legacy.rs` · `main.rs` · `layout.rs`는 A2-a 몫이라 **만지지 않습니다**.

**할 일**

1. **`schema.rs`**: `names`에 `hay TEXT NOT NULL DEFAULT ''`를 더합니다. 판은 `'3'` 그대로입니다.
2. **`build_names`** (`builder.rs`):
   - ① 2) 단계를 허용 목록으로 바꿉니다(3-1).
   - ② 기록의 `x_find.hay` + `$.description`을 `hay`에 채웁니다.
   - ③ 띠 안 칸(3) 단계) · 날짜 칸(4) 단계)의 `hay`를 주인 기록의 `x_find.cells[cell_ref]`로 채웁니다.
   - ④ 단체 · 제도 줄을 만듭니다. 곁글 · 기간 · 색은 `x_find`에서 가져오고, 줄은 `x_find.row`의 띠 줄을 빌립니다(5) 단계와 같은 꼴).
   - ⑤ 4-가 도읍 주인을 고칩니다(결함 4). 같은 칸 참조 + `$.name`으로 먼저 맞추고, 여럿이면 칸의 트랙(`axis_cells.track` = 기록의 `track`)으로 가립니다. `as` · `city` · `label`은 그다음 후보입니다.
3. **사건 다른 이름**: 넣을 때 끝에서 사건 기록의 `x_find.hay`를 낱자로 만들어 본문 색인에 `rowid = −(사건 번호)`로 더합니다.
   - 공동 사건의 둘째 자리 `uid#1`은 밑동 기록을 씁니다(계약 2-1 '밑동 되짚기').
4. **`query.rs`**:
   - `SEARCH_KINDS`에 `group` · `institution`을 더합니다.
   - `search_wide`의 이름 조각은 `hay` 열이 있을 때만 `n.name||' '||n.sub||' '||n.hay`로 맞춥니다. 있는지는 `pragma_table_info`로 부를 때 봅니다. `names_ready`와 같은 꼴이며, 필드를 `lib.rs`의 `Store`에 두지 않습니다.
   - 사건 조각은 `e.id = abs(s.rowid)`로 잇고, 확인 조건에 그 기록의 `x_find.hay`를 더합니다(후보만 JSON에서 꺼냄). 한 사건은 한 번만 냅니다.
   - 단체 · 제도 · 가문은 rowid 차례로 냅니다.
   - `search_year`는 두 갈래를 받아도 빈 결과를 냅니다(웹과 같음).
5. **(선택 · A3 바닥 2)**: 칸 종류 8 · 구역 48 · 변형 kind 3 · 4가 가져오기 · 타일 · 거르개 · 변형을 그대로 지나가는지 보는 검사를 `format3.rs`에 둡니다.

**검사** — `cargo test --release` 전부(지금 133 + 새 것). `tests/format3.rs`는 손으로 쓴 배치 JSON으로 저장소를 짓습니다(`tests/import.rs`의 `htpack()` 꼴을 제 파일에 따로 둠). 볼 것:
- 로마자 · 옛 이름 · 도읍 지명 원어로 정권 · 칸 · 가문이 찾히고, 결과는 본 이름입니다.
- `kinds:["group"]`이 곁글 · 줄 · 기간과 함께 옵니다. 트랙을 끄면 숨습니다.
- 사건 다른 이름으로 찾히고 겹치지 않습니다.
- 옛 모양 `search`는 그대로입니다.
- 본 문서는 여전히 빠집니다.
- `themes` · `view` · `map` · `font` · `place` · `surname`은 이름 표에 들지 않습니다.
- 같은 도시를 쓴 두 정권에서 도읍 칸 주인이 맞습니다.
- **옛 저장소**(`hay` 열을 지운 사본)가 지금과 같은 답을 냅니다.

**통과 기준**
- Rust 전부 통과.
- 같은 JSON으로 이 일 전 · 후의 도구가 지은 저장소(월흔해 · 동아시아)에서 다음이 같습니다.
  - 같은 요청의 타일 바이트(`archive-tool tile` 표본 50)
  - `layout` 답
- `verify-tiles` 누락 · 중복 0.
- 바뀌는 것은 이름 표와 본문 색인의 덧줄뿐입니다.
- 검색 한 번이 동아시아에서 지금보다 두 배 넘게 느려지지 않습니다(`bench` 또는 검사 안에서 잼).

#### A1-c — 앱: 공용 부품 · 단체/제도 창

**맡는 파일**
- 새 `prototype/app/lib/ui/detail_format3.dart`
- 새 `lib/ui/detail_group.dart`
- `lib/ui/detail_shell.dart`
- `lib/ui/app_glue.dart`(등록 한 줄만)
- 새 `test/detail_format3_test.dart` · 새 `test/detail_group_test.dart`
- `test/detail_shell_test.dart` · `test/wiring_audit_test.dart`
- 새 고정 자료 `test/fixtures/group-*.json`

**할 일**

- **1걸음 — `detail_format3.dart`** (A1-d가 이 위에 섭니다. 먼저 기록합니다). 공용 부품 일곱:

  | 부품 | 하는 일 |
  | --- | --- |
  | `DetailNamesLine(Map? xNames)` | 원어 줄 — `main` 한 줄 + `other`. 이름마다 U+2068…U+2069로 감쌉니다(웹 `<bdi>`). 표준 꼬리표면 `TextSpan(locale:)`을 주고, `x-` 꼬리표는 locale을 주지 않습니다 |
  | `DetailPersonRing` | 사람 고리 하나. 칸이면 그 칸으로, 인물이면 인물 창으로, `missing` · `unknown`은 회색 글 |
  | `detailKinLines(Map)` | 부모 · 배우자 · 자식 줄 |
  | `DetailPlaceLine` | 지명 줄 |
  | `DetailLawBlock` | 법 양식 |
  | `DetailElectionTable` | 선거 결과 표 |
  | `DetailChipRow` | 단체 · 제도 칩 |

  - 웹 `namesHTML`(678줄) · `kinLinesHTML`(696줄) · `placeHTML`(736줄) · `lensBottomHTML`(1830줄)의 글 · 차례를 그대로 따릅니다.
  - 링크 줄은 `detail_people.dart`의 `_LinkyLine`과 같은 모양으로 새로 둡니다. 옮기지 않는 까닭은 그 파일이 A1-d 몫이기 때문입니다. 겹친 것은 A1-g가 정리 거리로 적습니다.
- **2걸음 — `detail_group.dart`**: `GroupDetail` · `InstitutionDetail` · `registerGroupDetail()`을 둡니다(웹 `groupDetailHTML` 1706줄 · `institutionDetailHTML` 1776줄의 차례).
  - 아래 단추 "이 시기로"는 `ctx.goTo(lo, hi, …)`로 그 나라 줄에 갑니다(웹 `focusOn`과 같음).
  - 창을 열어도 연표를 고르거나 흐리게 하지 않습니다.
- **`detail_shell.dart`**:
  - `detailKinds`에 `DetailKind('group', lane:false, pick:false)` · `DetailKind('institution', lane:false, pick:false)`을 더합니다.
  - `pickDetailKind`에 두 줄을 더합니다.
  - 지명 · 성씨 · 판 · 지도 갈래는 창이 없으므로 더하지 않습니다(웹도 없음).
- **`app_glue.dart`**: `registerDetailKinds()`에 `registerGroupDetail()` 한 줄을 더합니다.
- 이름 충돌을 피합니다. 앱의 `lens`는 이미 **관점**(`SceneMarks.lens` · `lens_titles.dart` · `ItemDetail._lens`)이므로, 새 '주제 보기'는 코드에서 `theme`라 부릅니다. 웹 F2의 결과 갈래 `type:'lens'`와 섞지 않습니다.

**검사**
- `detail_format3_test.dart`: 오른쪽에서 왼쪽 글의 격리 문자, `locale`, 빈 값이면 위젯 없음, 선거 표의 열 차례.
- `detail_group_test.dart`: 단체 창의 차례 · 칩 · 계보(`x_from` · `x_into`) · 확인할 것, 제도 창의 칸 목록 · 같은 갈래.
- `detail_shell_test.dart`: 새 갈래는 `pick` · `lane`이 거짓.
- `wiring_audit_test.dart`: 단체 창을 열면 `Look.band`가 null.

**통과 기준**: 위 검사와 Dart 전체에서 실패 0, 제 파일의 `dart analyze --fatal-infos` 이상 없음, 있던 창의 검사 결과가 그대로.

#### A1-d — 앱: 있던 창에 새 줄

**맡는 파일**
- `lib/ui/detail_item.dart` · `lib/ui/detail_cell.dart` · `lib/ui/detail_people.dart`
- `test/detail_item_test.dart` · `test/detail_cell_test.dart` · `test/detail_people_test.dart`
- 새 고정 자료 `test/fixtures/*-f3edge.json`

**할 일** — 넣는 자리는 웹 차례입니다.

| 창 | 넣는 것 · 자리 |
| --- | --- |
| `ItemDetail` | `_badges()`에 주제 · 법 · 선거 딱지(조약 배지 다음). `_nameNotes()` 다음에 원어 줄 · 지명 줄. `_treatyBottom()` 다음에 법 양식 · 선거 표 · 맺은 단체. `_scopes()` 다음 · `_dynasties()` 앞에 나라의 단체 · 제도 칩 |
| `_cellBody` | 칸 사실 줄 다음에 원어 줄. `_leaderFigure` 다음에 자리 이음 · 사람 · 같은 사람의 다른 칸 · 혈연. 그다음 도읍 지명. 같은 나라의 칸이면 `_goCell(ref)`(웹 `data-cell-nav`) |
| `FigureDetail` | `_akaLine()` 다음에 원어 줄. `_twins()` 다음에 다스린 칸 · 혈연(다스린 칸 가운데 `x_leaders`와 겹치는 것은 뺌 — 웹 `figurePersonHTML`) |
| `HouseDetail` | 배지에 성 `x_surname.name`. 제목 다음에 원어 줄과 `성 X — 원어` 줄 |

- 열쇠가 없는 옛 기록은 **지금 그림 그대로**입니다.

**검사**
- `detail_cell_test`: 자리 이음 네 꼴(관계 앎 · 관계 미상 · 앞 지도자 미상 · 다시 오름), 같은 사람의 다른 칸, 도읍 지명.
- `detail_item_test`: 딱지 · 법 · 선거 · 칩.
- `detail_people_test`: 인물 혈연 · 다스린 칸, 가문 성 배지 · 원어 줄.
- 있던 고정 자료(`people-*.json` · `entities-*.json` · `cells-*.json`)로 그린 창의 글이 바뀌지 않음.

**통과 기준**: A1-c와 같습니다.

#### A1-e — 앱: 검색

**맡는 파일**: `lib/ui/search.dart` · `lib/ui/search_parse.dart` · `test/search_ui_test.dart` · `test/search_parse_test.dart`.

**할 일**
- `search_parse.dart`: `kinds`의 낱말 검색 쪽(99줄)에만 `group` · `institution`을 더합니다. 날짜 · 간지 쪽에는 더하지 않습니다.
- `search.dart`:
  - `_order`(190줄)를 웹 차례로 맞춥니다: 가문 → 단체 → 제도, 같은 갈래 안은 엔진 차례.
  - `_publish`(198줄)는 셋을 강조에서 뺍니다.
  - `activate`(308줄)는 단체 · 제도를 고르면 `select(uid, kind)` + 빌린 줄과 기간으로 `goTo`합니다. 고리(ring)는 두지 않습니다.
  - `SearchHit.kind`의 주석을 고칩니다.

**검사**: 갈래 목록, 결과 차례(시작 순으로 다시 세우지 않음), 강조에서 빠짐, 고르면 창 + 이동, 옛 엔진의 "모르는 갈래" 실패를 알림 줄로 보이는지.

**통과 기준**: A1-c와 같습니다. 합치는 차례는 A1-b 뒤입니다.

#### A1-f — 웹 정답 뜨기 (독립)

**맡는 파일**: 새 `prototype/scripts/detail-truth.mjs` · 새 `prototype/app/test/fixtures/web-truth-f3.json`.

**할 일**
- `scripts/lens-groups-check.mjs`와 같은 길을 씁니다. 브라우저 저장소 `ht.packs.installed`에 견본 넷(names · lineage · groups · lens)을 넣고, `HT.viewer.openDetail(uid, {cell})`로 창을 엽니다.
- `#detail`의 덩어리마다 글을 차례대로 뜹니다: 제목 · 다른 이름 줄 · 기간 줄 · 묶음 제목 · 칩 · 목록 줄.
- 검색어 목록(본 이름 · 원어 · 로마자 · 옛 이름 · 도읍 지명 원어 · 단체 종류 · 제도 갈래 · 트랙 이름 · 태그)의 결과 줄(갈래 · 제목 · 곁글 · 차례)도 뜹니다.
- 크로미움으로 돌립니다: `HT_BROWSER=chromium HT_PLAYWRIGHT_ROOT=/opt/node-tools/node_modules/playwright/package.json`.
- 잇기가 `js/viewer.js`를 바꾸는 중이므로 A1-g 직전에 한 번 더 뜹니다.

**검사**: 두 번 돌려 같은 결과가 나옵니다. 창 30개 이상, 검색어 15개 이상을 담습니다.

**통과 기준**: 정답 파일이 결정적이고, 웹에 오류가 없습니다.

#### A1-g — 이음 검사 · 마무리 (총괄 · 마지막)

**맡는 파일**
- `test/contract_real_engine_test.dart`
- 새 `test/web_parity_f3_test.dart`
- 새 `test/a3_floor_test.dart`(A3 바닥 3)
- `docs/계약-아카이브-3단계.md`(실측 수) · `docs/대조-아카이브-3단계-기능.md`(기능-19~) · `prototype/README.md`

**할 일**
1. 견본 넷 → 내보내기 → `prototype/data/f3-*`를 짓고 `verify-tiles`를 돌립니다.
2. `contract_real_engine_test.dart`에 `../data/f3-*` 묶음을 더합니다. 저장소가 없으면 건너뜁니다. 볼 것:
   - 단체 기록의 `x_` 열쇠.
   - `kinds:['group']`의 곁글 · 줄.
   - 원어로 사건 · 칸 · 가문이 찾힘.
   - 단체 기록을 열 때 실패한 조회 0건.
3. `web_parity_f3_test.dart`: 실제 엔진 + 저장소로 그린 창의 글을 차례대로 모아 A1-f 정답과 견줍니다. 검색 결과 줄도 같습니다.
4. 옛것을 확인합니다.
   - `ea-cloud`(그리고 월흔해)를 새 도구로 다시 지어 타일 바이트가 같은지 봅니다.
   - `render_scene_test.dart --dart-define=DB=../data/ea-cloud/archive.db` 그림이 그대로인지 봅니다.
   - `maker-archive-check` · `dev-smoke`를 돌립니다.
5. 계약에 실측(항목 기록 MB · 가져오기 시간 · 이름 표 줄 수)을 적고, 대조표에 새 줄을 더합니다.

**통과 기준**
- Dart 전체 실패 0(건너뜀은 f3 저장소가 있어 줄어듦), Rust 전부 통과, `dart analyze --fatal-infos lib test` 이상 없음.
- 웹 대조 차이 0. 남는 것은 까닭을 적은 예외 목록으로 둡니다. 예외 후보는 기간 글의 `–`(엔진 `when_text`) ↔ `~`(웹 `HT.formatRange`)인데, 정확히 맞추려면 `x_find`에 기간 글을 싣습니다.
- 옛 저장소 바이트 · 그림이 같음.

### 4-3. 파일 겹침 점검표

| 파일 | 묶음 |
| --- | --- |
| `docs/계약-아카이브-3단계.md` · `docs/작업판-10건-통합.md` · `docs/대조-아카이브-3단계-기능.md` · `prototype/README.md` | A1-0 · A1-g (총괄 — 차례로) |
| `prototype/scripts/export/entities.mjs` · `docs.mjs` · `calendar.mjs` · `base.mjs` · `export-layout.mjs` · 새 `f3-export-check.mjs` · `app/test/fixtures/f3-*.json` | A1-a |
| `prototype/engine/src/schema.rs` · `builder.rs` · `query.rs` · 새 `tests/format3.rs` | A1-b |
| 새 `app/lib/ui/detail_format3.dart` · 새 `detail_group.dart` · `detail_shell.dart` · `app_glue.dart` · 새 `test/detail_format3_test.dart` · 새 `detail_group_test.dart` · `detail_shell_test.dart` · `wiring_audit_test.dart` · `fixtures/group-*.json` | A1-c |
| `app/lib/ui/detail_item.dart` · `detail_cell.dart` · `detail_people.dart` · 그 검사 셋 · `fixtures/*-f3edge.json` | A1-d |
| `app/lib/ui/search.dart` · `search_parse.dart` · `test/search_ui_test.dart` · `search_parse_test.dart` | A1-e |
| 새 `prototype/scripts/detail-truth.mjs` · `fixtures/web-truth-f3.json` | A1-f |
| `test/contract_real_engine_test.dart` · 새 `web_parity_f3_test.dart` · 새 `a3_floor_test.dart` | A1-g |
| `prototype/engine/src/lib.rs` · `legacy.rs` · `main.rs` · `layout.rs` · 새 `src/verify.rs` · 새 `tests/htlayout.rs` | A2-a |
| `app/lib/ui/dlc_add.dart` · 새 `dlc_layout_import.dart` · `dlc_manager.dart` · `prototype/scripts/add-dlc.mjs` · 새 `test/dlc_layout_test.dart` · `test/engine_ffi_test.dart` · `fixtures/tiny.htlayout` | A2-b |

- `archive_app.dart` · `scene/*` · `paint/*` · `js/` · `css/` · `DLC-형식.md` · `packs/` · `samples/`는 **이번 묶음 어디에도 없습니다**.
- `archive_app.dart`를 고쳐야 하면 총괄이 고칩니다. `js/`의 `HT.searchHay`를 떼는 일은 웹 몫(W0)입니다.

## 5. A2 — 메이커의 `.htlayout`을 Node 없이 바로 가져오기

### 5-1. 지금 (실측)

- 엔진 `check-pack`에 `.htlayout`을 주면 "전용 팩 확장자가 아닙니다"로 거절됩니다. 확장자만 `.htpack`으로 바꾸면 "지원하지 않는 전용 팩 머리"로 거절됩니다(`lib.rs`의 `read_htpack`이 머리 바이트 9가 `1`인 것만 받음).
- 압축(CompressionStream deflate ↔ Rust `ZlibDecoder`)과 지문(sha256)은 종류 1과 같습니다. 그래서 그대로 풀립니다. `unpack-layout.mjs`로 풀면 원래 JSON과 바이트까지 같습니다.
- 앱의 DLC 더하기(`dlc_add.dart`)는 Windows 전용입니다. `DlcTools.find`가 Windows가 아니면 null을 주고, 그 뒤 `node add-dlc.mjs`를 씁니다. 휴대폰에서는 더하기 단추가 서지 않습니다.
- `archive_call`은 `STORE` 뮤텍스를 호출이 끝날 때까지 잡고 있습니다. 앱 `engine.dart`는 엔진 하나를 한 isolate에서 한 줄로 돌립니다. 가져오기를 `archive_call` 안에 넣으면 몇 초 동안 타일과 조회가 멈춥니다.

### 5-2. 사용자가 보는 흐름

| 손짓 | 보이는 것 |
| --- | --- |
| DLC 관리 → `📂 파일에서 더하기…` → `.htlayout`을 고름(컴퓨터 · 휴대폰 모두) | 위 칸에 `더하는 중 — 배치를 넣는 중…`이 뜹니다. 연표는 그대로 쓸 수 있습니다. Node · 도구 폴더가 없어도 됩니다 |
| 다 지어짐 | 4단계 1걸음과 같은 길입니다: `_swapStore` → `_reloadStore` → 줄이 360ms 흐름. 카드가 생기고 판이 적힙니다. 원본이 없으면 카드에 `원본 없음`이 붙습니다 |
| 조합이 어긋남(5-3) | 까닭을 그대로 보입니다. 예: `지금 얹은 DLC «이름»이 이 배치에 없습니다 — 메이커에서 그 DLC도 함께 불러 내보내거나, 컴퓨터에서 다시 지어 주세요`. 저장소는 그대로입니다 |
| 파일이 깨짐 · 종류가 틀림 | `js/packfile.js`의 글 그대로 보입니다(예: `팩 종류와 내용이 맞지 않습니다.`) |

### 5-3. 조합 대조 — 배치는 셈한 조합에서만 맞습니다

`.htlayout`은 그 조합 **전체**의 배치입니다(트랙의 모든 항목을 한꺼번에 놓은 셈). 그래서 가져오기는 저장소를 **통째로 새로 짓습니다**(2걸음 — 트랙 단위로 끼워 넣기 — 전까지). 기호는 이렇게 씁니다.
- **C**: `.htlayout`의 `packs[]`(id · 판).
- **S**: 지금 저장소의 조합(`meta.pack_keys` + `meta.pack_info`).

받는 규칙:

1. `C[0].id`가 S의 기본팩 id와 다르면 거절합니다.
2. S에 있는데 C에 없는 DLC가 있으면 거절합니다. 새로 지으면 그 DLC가 사라지기 때문입니다.
3. 같은 id인데 판을 양쪽 모두 알고 그 판이 다르면 거절합니다. 예: `«이름»의 판이 다릅니다(저장소 v3 · 배치 v2)`.
4. 판을 모르면(A1-a 전에 메이커가 낸 `.htlayout`이거나, `pack_info`가 없는 옛 저장소) id로만 대조하고 받습니다. 대신 답의 `warnings`에 `판을 확인할 수 없습니다`를 싣습니다.
5. C에만 있는 DLC가 새로 더해지는 것입니다.

판은 A1-a가 `packs[].version`으로 실어 줍니다. 그래서 A2의 조합 대조는 A1-a 뒤에 완성됩니다.

### 5-4. 원본 — `.htlayout`에는 DLC 본문이 없습니다

원본이 비면 생기는 일이 둘입니다. 하나는 `packs.original`이 비는 것입니다. 다른 하나는 앱의 `DLC/` 폴더에 그 DLC의 `.htpack`이 없어서, 나중에 Node로 다시 지을 때(`add-dlc.mjs`가 `DLC/` 폴더로 짓습니다) 그 DLC가 **조용히 사라지는** 것입니다.

**추천 — 아래 세 가지를 함께 씁니다.**
- **(가′) 곁의 `.htpack`을 함께 받습니다.**
  - 같은 폴더에 같은 id · 판의 `.htpack`이 있거나 사용자가 함께 고르면, 그것을 원본으로 싣고 `DLC/`에 둡니다.
  - 메이커가 `.htlayout`과 `.htpack`을 함께 내게 하는 것은 웹 몫(W1)입니다.
- **(라) 옛 저장소의 원본을 옮겨 싣습니다.**
  - S에 이미 있던 DLC의 `packs.original` BLOB은 지금 저장소에서 그대로 옮깁니다. 그래서 원본이 없는 것은 새로 더한 DLC뿐입니다.
- **(다) 원본이 없으면 다시 짓기를 막습니다.**
  - `meta.pack_info`에 `original:false`를 적고, DLC 카드에 `원본 없음`을 붙입니다.
  - `add-dlc.mjs`는 `original:false`인데 `DLC/`에 파일이 없는 DLC가 있으면 다시 짓기를 거절합니다. 이때 까닭과 함께 "그 DLC의 .htpack을 넣어 주세요"를 알립니다.
- (나) 배치 JSON에 원본을 담는 안은 권하지 않습니다. 노드 출력과 같은 글이라는 성질이 깨지고, 기본팩 본문까지 실려 파일이 커지기 때문입니다.

### 5-5. 묶음 A2-a — 엔진

**맡는 파일**: `prototype/engine/src/lib.rs` · `legacy.rs` · `main.rs` · `layout.rs` · 새 `src/verify.rs` · 새 `tests/htlayout.rs`. 이 파일들은 A1-b와 겹치지 않으므로 A1과 나란히 갑니다.

**할 일**

1. **`lib.rs` — 공통 풀기와 종류 3 읽기**
   - `read_htpack`의 머리 · 크기 · 지문 · 풀기를 `unseal(bytes, kind)`로 뗍니다. `read_htpack`의 동작은 그대로 둡니다.
   - 새 `read_htlayout(path)`를 둡니다.
     - 받는 것: 확장자 `.htlayout`, 머리 `[8]=2 [9]=3 [10]=1 [11]=0`, 파일 64MB · 풀린 크기 128MB까지.
     - 내용 점검은 `js/packfile.js`의 `isLayout`과 같습니다(`packs`가 비지 않고, `tracks` · `periods` · `cells` · `events` · `items` · `entities`가 배열).
     - 오류 글은 `packfile.js`의 글 그대로입니다.
2. **`lib.rs` — FFI**
   - `#[no_mangle] archive_import(request) → *mut c_char`(JSON · `archive_free`로 놓음)를 둡니다. `STORE`를 잡지 않습니다(부록 가-3).
   - `check_only`면 짓지 않고 조합 대조 · 내용 점검만 합니다.
3. **`legacy.rs`**
   - `import_layout`이 배치 경로의 확장자로 JSON과 `.htlayout`을 가립니다.
   - `fill`은 기본팩 원본을 `Option`으로 받습니다. 원본이 없으면 `plan.packs`의 id · 이름으로 `b.pack(name, None)`을 만들고 `pack_keys`는 그대로 남깁니다.
   - 조합 대조(5-3)를 하고, 원본을 옮겨 싣습니다(5-4 라).
   - `meta.pack_info`(`{"<번호>":{"id","version","category","original"}}`)를 남깁니다.
4. **`layout.rs`**: `packs[]`에 `version` · `category` · `original`을 더합니다.
5. **`verify.rs`**: `main.rs`의 `verify_tiles`를 lib로 옮깁니다. FFI 가져오기가 지은 뒤 표본 120으로 검사하게 합니다(`add-dlc.mjs`의 `verify-tiles 120`과 같음).
6. **`main.rs`** — 명령을 셋 둡니다.
   - `import-layout <기본팩.htpack|-> <배치.json|.htlayout> <새 저장소> [원본…] [--from-store <옛 저장소>]`
   - `check-layout <.htlayout> [--from-store …]`
   - (선택) `pack-out <저장소> <DLC id> <.htpack>`: 원본 BLOB을 파일로 꺼냅니다. PC에서 다시 지을 때 씁니다.

**검사** — `tests/htlayout.rs`(종류 3 파일은 검사 안에서 `sha2` · `flate2`로 만듭니다). 볼 것:
- `.htlayout`으로 지은 저장소가 같은 JSON으로 지은 저장소와 다음이 모두 같습니다: 띠 · 사건 · 항목 기록 수 · `layout` 답 · 타일 바이트(표본).
- 종류가 틀리거나 · 지문이 깨지거나 · 잘리거나 · 배열이 빠진 파일은 거절합니다.
- 원본 없이 넣으면 `packs.original`이 NULL이고 `pack_keys` · `pack_info.original:false`가 남습니다.
- `--from-store`로 옛 원본이 옮겨집니다.
- 조합 대조 다섯 경우(5-3)가 맞게 갈립니다.
- `archive_import`가 도는 동안 다른 스레드의 `archive_call`이 기다리지 않습니다.

**통과 기준**
- Rust 전부 통과.
- `archive-tool import-layout`의 옛 꼴(`기본팩 배치.json 새 저장소`)은 그대로 돕니다(`add-dlc.mjs`가 씀).

### 5-6. 묶음 A2-b — 앱

**맡는 파일**
- `lib/ui/dlc_add.dart` · 새 `lib/ui/dlc_layout_import.dart` · `lib/ui/dlc_manager.dart`
- `prototype/scripts/add-dlc.mjs`
- 새 `test/dlc_layout_test.dart` · `test/engine_ffi_test.dart`
- 새 고정 자료 `test/fixtures/tiny.htlayout`(노드 `HT.packFile.buildLayout`으로 만든 작은 파일)

**할 일**
- **`dlc_add.dart`**
  - 파일 창 Filter(36줄)에 `*.htlayout`을 더합니다.
  - `DlcJob.run`이 머리 바이트 9로 가릅니다. `3`이면 Node 대신 `dlc_layout_import.dart`로 갑니다.
  - 이 갈래에는 `DlcTools.find`가 필요 없습니다. 그래서 Linux · Android에서도 섭니다. 다만 Android의 파일 고르기 창은 PC 몫(PC-1 3-2의 MethodChannel)입니다.
- **`dlc_layout_import.dart`**
  - `Isolate.run` 안에서 `DynamicLibrary.open`(같은 라이브러리 경로)을 열고, `archive_import`를 `--from-store=<지금 저장소>`와 함께 부릅니다.
  - 그다음은 `archive_app.dart`의 `_swapStore` · `_reloadStore`를 그대로 씁니다(고치지 않음).
- **`dlc_manager.dart`**: 카드에 판 · `원본 없음`을 붙입니다. `.htlayout`만 받을 수 있는 곳(도구가 없는 곳)에서도 더하기 단추를 세웁니다.
- **`add-dlc.mjs`**
  - Linux의 `archive-tool`(확장자 없음)도 찾게 합니다.
  - 원본 없는 DLC가 있는 저장소는 다시 짓기를 거절합니다(5-4 다).

**검사**
- `dlc_layout_test.dart`: 가짜 가져오기로 성공 → 바꿔 넣기 흐름, 조합 어긋남 · 깨진 파일의 알림 글.
- `engine_ffi_test.dart`: 진짜 `.so`로 `tiny.htlayout` → 저장소 → `open` → `layout`. 가져오기 중에도 엔진 isolate의 조회가 답합니다.

**통과 기준**: Dart 전체 실패 0 · 분석 이상 없음.

### 5-7. PC 몫 (지시서로 남김)

- Windows 실행본에서 `.htlayout` 더하기를 손으로 한 번 해 보고 그림으로 남깁니다.
- 휴대폰은 Kotlin 파일 고르기와 APK의 기본팩 `.htpack`이 필요합니다(PC-1 3-2 · 3-5). 이것들은 `10건-PC-1`에 그대로 둡니다.
- 이 설계로 PC-1 3-5의 "B5 본문에 조합(팩 id · 판)이 없으면 클라우드로" 항목은 A1-a(판 싣기)와 5-3으로 풀립니다.

## 6. 공용 칸 단(A3)의 바닥 — 지금 어디까지 깔 수 있나

감독 선택(D1 · D2 · D4 · D5 · D6)이 없어도 깔 수 있는 것과 없는 것을 나눕니다.

| # | 바닥 | 무엇 | 누가 | 결정 필요 |
| --- | --- | --- | --- | --- |
| 1 | **번호 예약** | 계약에 예약 표만 둡니다(부록 가-9). 칸 종류 8(공용 칸 단) · 칸 `style` 27~28(kind 1의 자리 이음 이음매 — D1 결정 3) · 27~29(kind 8의 단 갈래) · 구역 48(띠 위 원어 글 — D2 결정 2, 구역 46과 같은 '기본이면 읽지도 않음') · 날짜 칸 종류 5(지도 장면 — D6 결정 2) · 변형 kind 3 `view:` · 4 `theme:` | A1-0 | 아니오(번호만, 뜻은 A3에서) |
| 2 | **엔진 통과** | kind 8 칸 · 구역 48 · 변형 kind 3/4가 가져오기 · 타일 · 거르개 · 변형을 그대로 지나가고, 없는 저장소는 바이트 그대로인지 봅니다. `cells` · `items` · `variants`는 뜻을 모르고 나르므로 Rust는 고치지 않을 것으로 봅니다. 검사로 확인합니다 | A1-b(선택) | 아니오 |
| 3 | **앱 안전** | 지금 그리기가 kind 8 칸(`RowGeo.strip(8)` = (−1, 0))과 구역 48을 만나도 그리지 않고 오류가 없는지 봅니다 | A1-g | 아니오 |
| 4 | **창 자료** | `x_lineage`(계승표) · `x_family`(세계표) · 단체 `x_from` · `x_into` · `x_power`(단체 계보 창 · 집권 단의 칸 목록) · 제도 `x_spans`(렌즈 칸 목록) · 가문 `x_spots`(가문 조명 — 새 조회 없이 지금 창 조명 장치로). 이 창들은 기록만으로 그릴 수 있어 새 조회가 필요 없습니다 | A1-a | 아니오 |
| 5 | **주제** | 주제 사전 기록 `themes`(A1-a). 렌즈의 사건 강조용 새 조회 `theme_events{theme,lo,hi,packs,filter}` → 사건 번호는 **설계만** 합니다(D5 뒤). 규모가 크면 넣을 때 파생 표 `event_themes`(`lens_names` 선례 — 표가 없으면 훑기) | A1-a · A3 | 조회는 D5 뒤 |
| 6 | **그림 · 글꼴 바이트** | 일반 표 `blobs(key PRIMARY KEY, pack, mime, bytes BLOB)` + FFI `archive_blob(key, &len)`(`archive_tile`과 같은 꼴 — JSON에 MB를 싣지 않음) + 가져오기 JSON의 겉 열쇠 `blobs[]`(`legacy.rs` — A2-a 뒤). **설계만** 합니다 | A3 | D6 · D2 뒤 |
| 7 | **판 변형** | `variants.track`이 하나뿐이고 `variant_rows.after`가 트랙 안 사슬이라 트랙을 넘는 쌓기를 실을 자리가 없습니다. 웹 배치가 판을 아직 셈하지 않습니다(F3 '자료만' · ⓔ). 보는 사람 판(앱이 줄을 통째로 옮겨 쌓기)은 자료 없이 됩니다 | A3 | D4 + 웹 배치 |

**지금 깔 수 없는 것**
- **덧단의 줄 높이**(집권 · 실권 단 · 덧붙이는 렌즈 단): 웹 배치기가 먼저 셈해야 합니다(PC 지시서 ⓔ — 새 앱은 스스로 줄 높이를 셈하지 않음).
- **띠 위 원어 병기**: 글자 그림판 · 잇는 문자 문제가 있습니다(D2 확인거리 3).
- **렌즈 바꿔 끼움 · 덧붙임**: D5 결정 5입니다.
- **지도 판**: D6입니다.

공용 칸 단 자체는 이렇게 됩니다. 칸 종류 8, `cells` 표 그대로, 고른 렌즈 칸만 싣는 것은 변형 `theme:<id>`. 그리는 쪽은 `paint/strips.dart`의 지도자 칸 그리기를 일반화합니다. 이것은 A3의 첫 묶음이 PC-3(돋보기 성능)의 결론 위에서 합니다.

## 7. 감독 확인거리

| # | 묻는 것 | 고를 것 | 추천 |
| --- | --- | --- | --- |
| 1 | **검색을 웹의 찾을 글과 같게** 넓힐지 | 넓히면 설명 · 태그 · 트랙 이름으로도 찾습니다. 예: 트랙 이름으로 찾으면 그 트랙의 사건이 모두 나옵니다(웹과 같음). 지금 앱보다 결과가 늘어납니다 | 같게(감독 지시 — 같은 모듈) |
| 2 | **원어 · 옛 이름 · 로마자**로 사건 · 칸 · 가문 찾기 | 웹은 됩니다 | 같게 |
| 3 | **`.htlayout` 원본 정책** | (가′) 곁의 `.htpack`을 함께 받음 · (라) 옛 저장소에서 옮겨 실음 · (다) 원본 없으면 다시 짓기 거절 · (나) 배치에 원본을 담음 | (가′) + (라) + (다) |
| 4 | **`.htlayout` 조합 대조** | 5-3: C ⊇ S, 판이 같아야 함. 어긋나면 거절하고 "컴퓨터에서 다시 짓기"로(PC-1 7절 5와 같음) | 그대로 |
| 5 | **지도 그림 · 글꼴 바이트** | A1에서는 싣지 않고 기록에는 크기만. A3(지도 판 · 글꼴 팩)에서 새 표 `blobs`로 | 그대로 |
| 6 | **지명 · 성씨를 검색 결과**로 낼지 | 웹은 결과 줄로 내지 않습니다(가문 · 칸의 찾을 글에만 들어감) | 웹처럼 안 냄 |
| 7 | **잇기 e와 A1-a의 경계** | 잇기 e가 내보내기 형식 3을 어디까지 하는지 | 잇기 e는 '내보내기가 형식 3 자료에서 깨지지 않게'까지만 하고 나머지는 A1-a로. 이미 했으면 A1-a는 빠진 것만 |
| 8 | **`view:` · `map:` 문서** | 견본에 있지만 웹 `baseInfo`에도 갈래가 없어 웹도 못 엽니다 | 웹과 함께 나중에(A3) |
| 9 | **웹 몫 둘** — W0: `HT.searchHay`를 `js/core.js`로 뗌(찾을 글이 웹 · 내보내기에서 같은 함수). W1: 메이커가 `.htlayout`과 `.htpack`을 함께 냄 | `js/`를 고치므로 승인이 필요합니다 | 둘 다 함(W0은 A1-a 전에, W1은 A2와 함께) |
| 10 | **A3의 번호 예약**(6절 1) | 지금 계약에 예약만 둠 | 둠 |

## 8. 위험

**겹침 · 순서**
- **같은 파일**: 잇기 e(통합)와 A1-a가 `export/entities.mjs` · `docs.mjs`를 함께 만집니다. 순서를 지키지 않으면 덮어씁니다(4-1).
- **합치는 차례**: A1-e(앱이 `group`을 보냄)를 A1-b보다 먼저 합치면 검색 전체가 실패합니다. 같은 까닭으로 앱과 DLL은 늘 같이 배포합니다.

**크기 · 시간**
- F1을 합치면 월흔해에도 자동 지명 62 · 성씨 14 · 사람 1000이 생깁니다.
- `x_lineage` · `x_family` · `x_find`를 싣는 순간 항목 기록 크기(지금 6.9MB)와 가져오기 시간이 달라집니다.
- `x_find.hay`는 설명을 빼고 싣지만 트랙 이름 · 태그 · 날짜 글이 사건마다 붙습니다(동아시아 사건 5,468건 기준 1MB 안팎으로 봅니다).
- A1-a · A1-g가 재어 계약에 적습니다.

**검색**
- **결과가 늘어남**: 웹과 같게 하면 트랙 이름 · 태그로 찾을 때 결과가 많아집니다. 다시 지은 저장소에서만 그렇고 옛 저장소는 그대로입니다. 감독이 화면에서 달라진 것을 알아챌 수 있습니다(확인거리 1).
- **검색 속도**: 이름 표의 `instr`가 긴 `hay`를 훑습니다. 사건은 본문 색인이 후보를 좁힌 뒤에만 JSON을 꺼냅니다. A1-b가 재어 두 배를 넘으면 멈춥니다.

**식이 어긋남**
- **찾을 글의 식**: W0 전에는 `runSearch`의 식을 옮겨 적습니다. 웹이 식을 바꾸면 어긋납니다 → A1-f 정답 + A1-g 대조로 잡습니다.
- **사람 잇기 기준을 바꿈**(결함 6): 동아시아 · 월흔해의 `x_leaderFigures`가 달라질 수 있습니다. 이름이 같은 다른 사람이 갈리는 것이므로 옳은 쪽이지만, 바뀐 고리를 목록으로 남깁니다.

**화면**
- **오른쪽에서 왼쪽 글 · 가상 문자**: 검사 환경은 글꼴 셋뿐이라 아랍 · 가상 문자가 두부로 나옵니다. 글 비교는 글 단위로 하고, 그림은 F3 글꼴 설계 뒤에 봅니다.
- **이름 충돌**: 앱의 `lens`는 관점입니다. 새 주제 보기는 `theme`라 부릅니다.

**A2**
- `.htlayout`으로 넣은 저장소는 원본이 빠질 수 있습니다. (다)의 거절이 없으면 다음 Node 다시 짓기에서 DLC가 사라집니다.
- 판이 없는 옛 `.htlayout`은 조합의 판 어긋남을 알아낼 수 없습니다(경고만).

**옛 저장소**
- 감독의 휴대폰 · 배포 저장소는 새 줄이 비어 보입니다. 다시 지어 보내야 새 줄이 보입니다(PC-1 3-2의 '저장소 보내기').

## 9. 결정 기록 (제안 — 감독 승인 전)

| 날짜 | 결정(제안) | 근거 |
| --- | --- | --- |
| 2026-10-12 | 스키마 판 `'3'`을 올리지 않고 열 · 덧줄로만 넓힌다 | `Store::open`이 판이 다르면 거절한다 → 올리면 옛 저장소가 모두 열리지 않는다. `names.cell_ref` · 변형 · `lens_names`가 같은 선례 |
| 2026-10-12 | 새 값은 가져오기 JSON의 겉이 아니라 항목 기록 안의 `x_`(검색은 `x_find`)로 싣는다 | 가져오기(`legacy.rs`)를 고치지 않아 A2와 파일이 겹치지 않는다. `.htlayout`에도 저절로 실린다 |
| 2026-10-12 | 사건의 다른 이름은 새 열이 아니라 본문 색인 덧줄(rowid 음수)로 | 사건 표 · FTS 표의 모양이 그대로다. 옛 모양 `search`가 덧줄을 보지 않는다 |
| 2026-10-12 | 이름 표에 넣는 갈래를 허용 목록으로 | 형식 3의 새 기록(주제 · 판 · 지도 · 글꼴 · 지명 · 성씨)이 검색을 더럽히지 않게 |
| 2026-10-12 | `.htlayout` 가져오기는 `archive_call` 밖의 FFI `archive_import`로 · 앱은 `Isolate.run` | `STORE` 잠금이 호출 끝까지 잡혀 몇 초 동안 타일이 멈추는 것을 막는다. 휴대폰의 유일한 길 |
| 2026-10-12 | 지도 그림 · 글꼴 바이트는 A1에서 싣지 않는다 | `entity` 답이 MB 단위가 된다. A3에서 일반 표 `blobs` + 바이트 FFI로 |

---

## 부록 가. 계약 문서(`docs/계약-아카이브-3단계.md`)에 더할 절 — 초안

> 계약은 고치지 않았습니다. A1-0에서 총괄이 감독 답(7절)에 맞춰 옮깁니다. 아래 글은 계약의 말씨 그대로 씁니다.

### 가-1. 2-1 덧붙임 — 검색의 새 갈래와 찾을 글 (2026-10-?? · A1)

- **결과 한 줄의 `kind`**에 `group`(단체) · `institution`(제도)을 더한다.
  - `uid` = 기록의 uid · `sub` = 기록의 `x_find.sub` · `start`/`end` = `x_find.span` · `when` = 그 기간 글 · `color` = `x_find.color`.
  - `row` = `x_find.row`(정권 uid)의 띠가 놓인 줄(못 찾으면 null) · `track` = 그 줄의 트랙 이름 · `cell` · `id`는 null.
- **`kinds`에 쓸 수 있는 갈래**에 `group · institution`을 더한다. `search_year`는 두 갈래를 받아도 빈 결과다(지금 연표도 날짜 · 간지 검색에서는 단체 · 제도 · 가문을 찾지 않는다).
- **이름 표 `names`에 열 `hay`**(찾을 글 · 소문자)를 더한다. `build_names`가 채운다.
  - 기록 줄: 그 기록의 `x_find.hay` + ' ' + `$.description`.
  - 띠 안 칸 · 날짜 칸 줄: 주인 기록의 `x_find.cells[<칸 참조>]`.
  - 맞춤 규칙: 낱말마다 `instr(lower(name||' '||sub||' '||hay), 낱말) > 0`.
  - **`hay` 열이 없는 저장소는 지금 규칙(`name||' '||sub`) 그대로**다(`pragma_table_info`로 가린다 · `meta.schema`는 `'3'` 그대로).
- **이름 표에 넣는 갈래는 허용 목록**이다: `period · organ · culture · dynasty · figure · epoch · scope · house · group · institution · doc`(하위 문서만) + 칸 줄.
  - 그 밖의 기록(`cal · themes · place · surname · view · map · font`)은 이름이 있어도 넣지 않는다.
  - **가문 · 단체 · 제도는 넣은 차례**(= 내보낸 차례 = 모델 차례)로 답하고, 화면은 시작 순으로 다시 세우지 않는다.
- **단체 · 제도의 줄**은 `x_find.row`가 가리키는 정권의 띠 줄을 빌린다(5) 단계와 같은 꼴). 거르개가 그 줄의 트랙을 끄면 숨는다.
- **사건의 찾을 글**: 본문 색인 `search`에 사건마다 **덧줄** 하나를 더한다.
  - 덧줄의 `rowid`는 −(사건 번호)이고, 낱자는 `grams(그 사건 기록의 x_find.hay)`다. 공동 사건의 둘째 자리(`uid#1`)는 밑동 기록을 쓴다.
  - `kinds`를 준 `search`는 `abs(rowid)`로 사건에 잇고, 확인 조건에 그 기록의 `x_find.hay`를 더하며, 한 사건은 한 번만 낸다.
  - **`kinds`가 없는 옛 모양은 덧줄을 보지 않는다**(음수 rowid는 사건에 이어지지 않는다). 덧줄이 없는 저장소는 지금과 같은 답이다.
- **도읍 칸의 주인**(4-가)을 바로잡는다. 같은 칸 참조 + 기록의 `name`으로 먼저 맞추고, 여럿이면 칸의 트랙으로 가린다. `as` · `city` · `label`은 그다음 후보다.

### 가-2. 2-3 표에 더할 줄

| 명령 | 더한 것 |
| --- | --- |
| `search` · `search_year` | 가-1(갈래 `group` · `institution` · 이름 표 `hay` · 사건 덧줄) |
| `layout` | `packs[]`에 `version`(DLC 판 · 모르면 빈 글) · `category`(팩 분류 — `map` 지도팩 …) · `original`(원본 팩을 저장소에 품었으면 1). 가져오기가 남긴 `meta.pack_info`(`{"<번호>":{"id","version","category","original"}}`)에서 읽고, 옛 저장소는 빈 값 · 1이다 |

### 가-3. 2-7 (새) `archive_import` — 배치를 Node 없이 저장소로 (A2)

```c
char* archive_import(const char* request);   // 답은 archive_free로 놓는다. STORE를 잡지 않는다 — archive_call · archive_tile과 동시에 돈다
```

```jsonc
// 요청
{ "layout":"…/x.htlayout | …/x.json",   // 확장자로 가른다. .htlayout은 팩 파일 종류 3(DLC-형식.md '팩 파일')
  "out":"…/archive.새로-지음.db",        // 있으면 거절(덮어쓰지 않는다)
  "base":"…/기본팩.htpack",              // 선택 — 기본팩 원본. 없으면 원본 없이
  "originals":["…/dlc.htpack"],          // 선택 — 새 DLC의 원본(id · 판이 배치와 같아야)
  "from_store":"…/archive.db",           // 선택 — 지금 저장소. 주면 조합을 대조하고 그 저장소의 원본을 옮겨 싣는다
  "check_only":false }
// 답(archive_call과 같은 겉): {"ok":true,"data":{"packs":[{id,name,version,original}],"events":n,"entities":n,"ms":…,"verify":{"missing":0,"dup":0},"warnings":[…]}}
//                         또는 {"ok":false,"error":"<한국어 까닭>"}
```

- **조합 대조**(`from_store`를 주었을 때): 배치의 조합을 C, 저장소의 조합을 S라 한다.
  - `C[0].id` ≠ S의 기본팩이면 거절한다.
  - S의 DLC가 C에 없으면 거절한다.
  - 같은 id의 판을 양쪽이 알고 서로 다르면 거절한다.
  - 판을 모르면 id로만 대조하고 `warnings`에 싣는다.
  - 결과 저장소의 조합은 C다(통째로 다시 짓는다 — 트랙 단위 끼워 넣기는 4단계 2걸음).
- **오류 글**: 내용 점검은 `js/packfile.js`의 `isLayout`과 같고, 오류 글도 그 파일의 글 그대로다.
- **지은 뒤 검사**: `verify_tiles`(표본 120)를 돌리고, 누락 · 중복이 있으면 지은 파일을 지우고 실패한다.
- 도구: `archive-tool import-layout <기본팩.htpack|-> <배치.json|.htlayout> <새 저장소> [원본…] [--from-store <저장소>]` · `check-layout <.htlayout> [--from-store …]`. 옛 꼴은 그대로 돈다.

### 가-4. 4절 덧붙임 — 가져오기 JSON 3판

- `packs[]`에 `version`(DLC의 판 — 팩 정보의 `version` 그대로) · `category`(팩 분류)를 더한다. 가져오기가 `meta.pack_info`로 남긴다. 빠지면 빈 글이다.
- `entities[]`에 `pack`(이 배치의 `packs[]` 순번)을 적는다.
  - 가져오기는 전부터 `pack` → uid의 앞머리(`<DLC id>/…`) → 기본 DLC 차례로 귀속을 정했다.
  - **`/`가 없는 uid(`house:` · `doc:` · `cal:` · `place:` · `surname:` · `view:` · `map:` · `font:` · `themes`)는 `pack`이 있어야 제 DLC에 붙는다.**
- 배치를 **`.htlayout`(팩 파일 종류 3)으로도** 받는다(가-3). 본문은 이 절의 JSON과 글자까지 같다.

### 가-5. 6-9 덧붙임 — 항목 기록의 갈래

`kind`에 더한다. 지금 있는 것: `house` 가문 · `doc` 문서 · `cal` 보조 달력. 새로 더하는 것:

- **`group`** 단체 · **`institution`** 제도
- **`place`** 지명 · **`surname`** 성씨 · **`themes`** 주제 사전(하나)
- **`view`** 모아 보기 판 · **`map`** 지도 · **`font`** 글꼴

화면에 창이 있는 것은 `group` · `institution`뿐이다. 나머지는 문서 창의 바탕 · 다른 기록의 미리 푼 값 · 뒤의 화면(A3)이 읽는다.

### 가-6. 6-9 다 (새) — 형식 3의 기록과 미리 푼 값

6-9 가의 약속 다섯을 그대로 따른다: `x_` · 빈 것은 싣지 않는다 · 시간은 분 · 글은 지금 연표가 만든 글 그대로 · 가리키는 uid는 모두 제 기록이 있다. 이제 대조는 `$ref`까지 한다.

**새 기록**

| kind | uid | `pack` | 본문(`json`) |
| --- | --- | --- | --- |
| `group` | `<DLC id>/<id>`(모델 uid) | 그 DLC | 모델의 단체(`plain`) — 원문 칸(`within` · `power` · `from` · `people` · `members` · `event`) 그대로 |
| `institution` | `<DLC id>/<id>` | 그 DLC | 모델의 제도 |
| `place` | `place:<id>` | 정의한 DLC(저절로 생긴 지명은 처음 쓰인 항목의 DLC) | 사전 항목(`names` · `at` · `parent`) + `auto` |
| `surname` | `surname:<id>` | 같은 규칙 | 사전 항목 + `auto` |
| `themes` | `themes` | 기본(0) | `{"list":[{id,name,color,order,auto?}]}` — `name` 칸이 없다 |
| `view` | `view:<id>` | 그 DLC | 모델의 판(`settings` 포함) |
| `map` | `map:<id>` | 그 DLC | 모델의 지도. **그림 데이터 URL은 `{"$bytes":<글자 수>}`로 갈음**(바이트는 뒤에 `blobs` 표로) |
| `font` | `font:<id>` | 그 DLC | `family` · `license` · `scripts` · `note`. `src`는 `{"$bytes":n}` |

**공용 꼴**

- **이름 줄** `x_names` = `{main:[{text, lang?, tag}], other:[…]}`
  - `HT.namesSplit`의 두 묶음 · 차례 그대로다.
  - `tag`는 지금 연표 `nameTag`의 글(종류 이름 · 언어 이름 · 쓴 기간 · 메모를 ` · `로)이다.
  - `lang`은 꼬리표 그대로다. 화면은 표준 꼬리표면 글의 언어로 쓰고 `x-`로 시작하면 쓰지 않는다.
- **사람 고리** = `{name, uid?, ref?, polity?, missing?:1, unknown?:1}`
  - 인물이면 `uid` = 인물.
  - 칸이면 `uid` = 정권 · `ref` = `"leader:3"` · `polity` = 정권 이름.
  - 못 찾은 이름은 `missing:1`, '미상'은 `unknown:1`(이름 `미상`)이다.
- **혈연 줄** = 사람 고리 + `as?`(관계 글 — 지금 연표 글) · `certainty?`.
- **지명 줄** = `{name, uid?(place:…), up?:[위 구역 이름…], names?: 이름 줄}`.

**있던 기록에 더하는 것**

| 기록 | 열쇠 | 무엇 |
| --- | --- | --- |
| 이름 목록이 있는 모든 기록 | `x_names` | 이름 줄 |
| 모든 정권 | `x_cellNames` | `{"leader:3": 이름 줄, "era:2": …, "capital:0": …}` |
| 모든 정권 | `x_lineage` | **자리 이음** `{"leader:3":{from?:고리, fromAuto?:1, fromUnknown?:1, kin?, kinId?, kinUnknown?:1, how?, howId?, howUnknown?:1, note?, restored?:1, elsewhere?:[고리]}}`. `HT.lineageOf(model,p).rulers`를 칸 참조 열쇠로 편 것. `kin` · `how`는 이름 글, `kinId` · `howId`는 원래 값(계승표 선 갈래 — A3) |
| 모든 정권 | `x_persons` | **칸의 사람** `{"leader:3":{figure?:고리, others?:[고리], parents?:[혈연 줄], spouses?:[…], children?:[…]}}`. 내각 칸은 `cabinet:2` |
| 모든 정권 | `x_cellPlaces` | `{"capital:0": 지명 줄}`. 지금 연표처럼 원어나 위 구역이 있을 때만 |
| 모든 정권 | `x_groupLinks` | 나라의 **단체 칩** `[{uid,name,color,role:'within'\|'member',small?:1}]` |
| 모든 정권 | `x_institutions` | 나라의 **제도 칩** `[{uid,name,theme,themeName,family?,color,title?}]`. 주제 차례 |
| 모든 정권 | `x_leaderFigures` | **규칙을 바꾼다**: 사람 잇기(`HT.personOf`)로 이어진 인물. 칸에 적은 `person`이 이기고, 없으면 같은 이름 · 겹친 시기(지금 연표의 저절로 잇기)다 |
| figure | `x_person` | `{ruled?:[{uid,ref,name,label,when}], parents?, spouses?, children?}` |
| figure | `x_leaders` | `x_leaderFigures`의 거꾸로 — 같은 규칙 |
| event · treaty | `x_place` | 사건의 장소 — 지명 줄 |
| event · treaty | `x_law` | `{name, act?, actName?, articles?:[{no?,title?,text?}], note?}` |
| event · treaty | `x_election` | `{office?, results:[{who:고리 또는 글, votes?, seats?, won?:1}], note?}` |
| event · treaty | `x_groups` | **이 일로 맺은 단체** `[{uid,name,color,typeName}]` |
| event · treaty | (본문) | `themeRefs`는 본문 그대로 쓴다(`{ref,id,name,color,auto}` — 주제 딱지) |
| house | `x_surname` | `{uid?, name, names?: 이름 줄}` |
| house | `x_family` | **세계표** `{nodes:[{n,name,uid?,ref?,gen,member?:1,unknown?:1,missing?:1,ruled?:[{uid,ref,ordinal?,color}]}], edges:[{type:'parent'\|'spouse',from:n,to:n,as?,gen?,certainty?}]}`. `n`은 노드의 차례 번호다(모델의 `u:n` 열쇠는 매번 바뀌어 싣지 않는다) |
| house | `x_spots` | **가문 조명** `[{uid,start,end}]` — 그 가문이 자리에 있던 칸들의 기간을 정권마다 이은 것(분) |

**새 기록의 미리 푼 값**

| 기록 | 열쇠 | 무엇 |
| --- | --- | --- |
| group | `x_type` · `x_span` | 종류 이름(`typeName`) · 기간 `[lo,hi]` |
| group | `x_within` | **있던 나라** `[{uid,name,color,when?,span?}]` |
| group | `x_members` | **구성 나라**(연합) `[{uid,name,color,role?,when?,span?}]` |
| group | `x_power` | **집권 · 실권 칸** `[{name,when,span,note?,endAuto?:1}]` |
| group | `x_from` · `x_into` | **앞선 단체 · 뒤를 이은 단체** `[{uid?,name,how?,howName?}]` |
| group | `x_people` | **구성원** `[사람 고리 + role?]` |
| group | `x_event` · `x_warnings` | 맺은 사건 `{uid,title,when}` · 확인할 것 `[글]` |
| institution | `x_theme` · `x_polity` | `{id,name,color}` · `{uid,name,color}` |
| institution | `x_spans` | **칸** `[{name,when,span,note?,from?:{uid?,name},guess?:1}]`. `when`은 `HT.phaseRangeText` 글 |
| institution | `x_same` · `x_warnings` | 같은 주제 · 같은 갈래의 다른 나라 제도 `[{uid,name,polity,color}]` · 확인할 것 |
| place | `x_path` · `x_children` · `x_uses` | 위 구역 `[{uid,name}]` · 아래 구역 · 쓰인 곳 `[{role,uid,ref?,name,when}]` |
| surname | `x_houses` | 그 성의 가문 `[{uid,name,color}]` |
| view | `x_members` · `x_span` | 든 나라 `[{uid,name,color}]`(못 찾은 것은 `name`만) · 기간 |
| map | `x_scenes` | 장면마다 `{year, at, owners:{<구역 id>: 고리}}`(그림 없이) |

**찾을 글 `x_find`**(검색 대상 기록 모두 — 화면은 읽지 않는다)

`{hay, cells?, sub?, span?, color?, row?}`

| 칸 | 뜻 |
| --- | --- |
| `hay` | 지금 연표 `runSearch`가 그 항목에 만드는 찾을 글(소문자)에서 **이름 · 제목 · 설명을 뺀** 나머지. 엔진이 설명을 이어 붙이고, 사건의 제목 · 설명은 본문 색인에 이미 있다 |
| `cells` | `{"leader:3": 그 칸의 찾을 글}` — 칸 이름은 빼고, 도읍 칸은 지명 원어까지 |
| `sub` · `span` · `color` · `row` | 단체 · 제도의 결과 줄 곁글 · 기간 · 색 · 줄을 빌릴 정권 uid |

### 가-7. 6-9 나 덧붙임 — 문서

- **문서 바탕**에 `surname:<id>`(곁글 `성씨 · 가문 n`) · `place:<id>`(곁글 `지명 · 쓰인 곳 n`)를 더한다. 연표로 데려갈 uid는 없다.
- **이름 → 문서 표**에 단체를 가문 다음에 더한다. 이름이 겹치면 `단체:이름`이다. 고리 `[[단체:이름]]`은 곧바로 단체로 간다(지금 연표 `nameToBase` · 링크 제안과 같은 차례).
- 문서 기록에도 `pack`을 싣는다(가-4).
- `view:` · `map:` 바탕은 지금 연표에도 없어 아직 싣지 않는다.

### 가-8. 2-1의 '아직 없는 것'에 더할 줄

- `theme_events{theme,lo,hi,packs,filter}` → 사건 번호(렌즈의 사건 강조): A3에서 D5를 고른 뒤.
- `archive_blob(key,&len)`(지도 그림 · 글꼴 바이트): A3에서 D6 · D2를 고른 뒤.

### 가-9. 번호 예약 (A3 — 뜻은 감독 선택 뒤 A3가 정한다)

| 자리 | 예약 | 쓸 곳 |
| --- | --- | --- |
| 칸 `kind` | **8** | 공용 칸 단(집권 · 실권 · 렌즈 제도 칸) |
| 칸 `style` 27~28 (kind 1만) | 자리 이음 이음매 2비트(0 선 · 1 틈 · 2 빗금 · 3 점선) | D1 결정 3 |
| 칸 `style` 27~29 (kind 8만) | 단 갈래 | D5 결정 1 · 2 · 5 |
| 일반 구역 | **48** | 띠 위 원어 글(표기 설정이 기본이면 읽지도 않음 — 구역 46 선례) — D2 결정 2 |
| 날짜 칸 `kind` | **5** | 지도 장면 줄 — D6 결정 2 |
| 변형 `kind` | **3** `view:<id>` · **4** `theme:<id>` | 모아 보기 판(D4) · 렌즈 칸(D5) |

새 번호를 쓰기 전에 이 표에서 예약을 풀고 뜻을 적는다. 클라우드와 PC가 같은 번호를 두 번 쓰지 않게 하려는 것이다.

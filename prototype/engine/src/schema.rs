//! 스키마 4: 스키마 3의 표 · 열을 하나도 바꾸지 않고 형식 4의 뜻을 싣는 자리 둘을 더한다 — 띠의 새 열 `periods.form`(종류 · 관계 ·
//! 정통성 · 중요도 비트)과 새 표 [`SPHERE_LINES`](사람 띠 · 문화권 시대 구분 · 문화권 주기 줄). 약속은 `docs/계약-아카이브-3단계.md` 1-1절.
//! 스키마 3은 2의 표(사건 · 원문 · 검색 · 트랙 · 줄 · 띠 · 칸 · 시대 구분 · 단계별 요약)를 그대로 두고 3단계(연표 기능 이전)가 쓰는 열과 표를
//! 더한 것이다 — 트랙의 색과 단, 줄의 새 값, 민족 묶음, 분류, 날짜 칸, 띠 · 칸 · 사건의 표현 값, 그리고 "띠 · 칸 · 사건이 아닌 모든 그릴 것"의
//! 일반 통로 items와 상세 창이 읽는 entities(계약 1절). 옛 저장소(판 '3' · '3.1')는 새 열 · 표가 없을 뿐이라 그대로 열리고, 읽는 쪽이
//! `pragma_table_info` · `sqlite_master`로 가려 빈 값(form 0 · 빈 목록)으로 답한다(계약 1절의 가려 읽기).
use crate::Result;
use rusqlite::Connection;

/// 새로 짓는 저장소의 판(`meta.schema`) — 줄 열쇠 = 자리.
pub const VERSION: &str = "4";
/// 넣고 빼기(`patch::apply`)가 줄 열쇠(`rows.id`)와 자리(밖으로 보이는 0부터 빈틈없는 줄 번호)를 가른 저장소의 판 — 계약 1절 '3.1'의 스키마 4 짝.
pub const VERSION_SPLIT: &str = "4.1";
/// 이 엔진이 여는 판 — 스키마 3(옛 저장소 · 새 열 · 표는 가려 읽음)과 4. 그 밖의 판은 `Store::on`이 "다시 만들어야 합니다"로 거절한다
/// (스키마 4 전의 엔진은 '3' · '3.1'만 받아 '4' · '4.1'을 거절한다 — 새 뜻을 모르는 채 읽지 않게).
pub const OPENS: [&str; 4] = ["3", "3.1", "4", "4.1"];

/// 스키마 4의 문화권 단위 줄 표(계약 1-1 — `CREATE TABLE` 뒤의 글). 새로 짓는 저장소([`create`])와 옛 저장소를 메우는 `patch::apply`의
/// "delete"(`ensure_schema` — `CREATE TABLE IF NOT EXISTS`)가 이 하나를 쓴다([`P4_TABLES`]와 같은 길). 다른 표를 가리키지 않는다(REFERENCES 없음).
/// - kind: 1 사람 띠 · 2 문화권 시대 구분 · 3 문화권 주기 줄. sphere = 문화권의 글자 id(`tracks.sphere`와 같은 글).
/// - 1 사람 띠: 왕관(지도자 칸의 person이 한 사람으로 이어진 객체)이 둘 이상인 사람마다 하나. sphere = 왕관들의 문화권 가운데 차례가 가장 앞 ·
///   start · end = 왕관 칸의 가장 이른 시작 ~ 가장 늦은 끝 · uid = 인물 uid · data = 왕관 목록 `[{"uid": 띠 uid, "cell": 칸 순번}]`.
/// - 2 문화권 시대 구분: 트랙 없이 sphere를 적은 시대 구분(트랙을 함께 적은 것은 싣지 않음) · name = 시대 이름 · uid = 시대 구분 uid · color = 그 색.
///   모델이 아는 문화권(켠 DLC의 spheres)의 것 · 바른 기간(시작 ≤ 끝)만.
/// - 3 문화권 주기 줄: 켠 DLC 차례로 yearCycles의 문화권 줄, 문화권마다 첫 것 하나(문화권이 다르면 여럿) · 모델이 아는 문화권의 것 ·
///   설정이 바른 것(names 또는 era)만 · data = 주기 설정 JSON · start · end = 0.
/// - 차례(id)는 배치 차례 그대로 — 지금 내보내기는 모듈 차례대로 kind 2 · 3(`axis`) 다음 kind 1(`persons`).
///
/// `{"op":"layout"}`이 표 전부를 id 차례로 `sphereLines`에 답한다(수가 적어 타일로 나누지 않음). 넣고 빼기에서는 트랙이 아니라 온 판
/// (`track_prints`의 `*`)의 지문에 들고, 닿는 트랙만 고쳐 쓸 때도 늘 다시 셈한다. 이 표가 없는 옛 저장소는 빈 목록으로 답한다.
pub const SPHERE_LINES: &str = "sphere_lines(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL,sphere TEXT NOT NULL,kind INTEGER NOT NULL,\
start INTEGER NOT NULL,end INTEGER NOT NULL,name TEXT NOT NULL,uid TEXT NOT NULL DEFAULT '',color INTEGER NOT NULL DEFAULT 0,data TEXT NOT NULL DEFAULT '',\
CHECK(start<=end))";

/// P4(트랙별 다시 쓰기)가 더한 표 넷의 정의 — (표 이름, `CREATE TABLE` 뒤의 글). 새로 짓는 저장소([`create`] — 이 차례 그대로 `names` 뒤)와 옛 저장소를 메우는
/// `patch::apply`의 "delete"(`ensure_schema` — `CREATE TABLE IF NOT EXISTS`)가 이 하나를 쓴다(과제 A+ 넘김 "같은 규칙 두 곳" — 표 DDL이 글로 두 벌이었다).
/// - `event_hay`: 사건의 찾을 글(다른 이름 · 원어 · 옛 이름 · 장소 · 태그 · 트랙 이름 … — 항목 기록의 `x_find.hay`, 소문자). 본문 색인 `search`에는 이 글의
///   낱자가 덧줄(rowid = −사건 번호)로 들고, 넓힌 검색이 그 후보를 이 글로 확인한다(항목 기록의 큰 JSON을 후보마다 꺼내면 검색 한 번이 두 배 넘게 느려진다).
///   id = 사건 번호 · 찾을 글이 있는 사건만. 이 표가 없는 옛 저장소는 덧줄도 없다(조회가 sqlite_master로 가린다).
/// - `lens_names`: 관점(나라마다 제 이름 — 계약 2-6절)이 읽는 표. 항목 기록의 `perspectives`를 넣기가 끝날 때 한 번에 편다(builder의 build_lens_names).
///   track은 트랙의 **글자 id**(tracks.key와 같은 글)이고, name은 그 관점의 이름이다. 이 표가 없는 옛 저장소에서는 조회가 그때그때 항목 기록을 훑는다(답은 같고 느릴 뿐).
/// - `blobs`: 그림 바이트(문서 그림 — 형식 3 images · 10건 D3). key = `img:<DLC id>/<그림 id>`(문서 기록의 `images[이름].key`) · mime = image/png · jpeg · webp.
///   가져오기 JSON의 겉 열쇠 `blobs[]`({key, pack, mime, data(base64)})로 들어오고, 문서 창을 열 때만 `archive_blob`(바이트 그대로) · 조회 명령 blob(base64)으로
///   읽는다 — 타일 · 거르개와 무관. 이 표가 없는 옛 저장소에서는 그림이 '없음'으로 답한다(판 '3' 그대로). 저장소가 지어 넣는 `calendar:table`(달력 표 — zlib ·
///   자료집 0 · `lay::calendar_of` — 한 벌 P3 과제 17)도 여기 든다(배치의 그림이 아니라 넣고 빼기가 지우지 않는다).
/// - `track_prints`: 트랙 지문(계획 P4 과제 4 — `patch.rs`). DLC를 넣고 뺄 때(apply) 새 배치의 지문과 견주어 바뀐 트랙만 다시 쓴다.
///   key = 트랙 열쇠(`patch::track_key` — tracks.key, 비면 `n:<자료집 id>|<이름>`, 판 트랙은 `board:<열쇠>`) · 온 판 지문은 `*`.
///   print = 그 조각(번호를 열쇠 · uid · 내용으로 바꿔 적은 것)의 SHA-256 16진 글.
///   needs = JSON {uids: 가리키는 남의 트랙 띠 · 사건 uid 목록, rows: 줄을 가리키는 남의 트랙 열쇠 목록, own: 제 띠 · 사건 uid 목록, hides: 이 트랙의 변형이 칸 · 항목을
///   가리는 남의 트랙 열쇠 목록}(온 판은 빈 객체). 이 표가 없는 옛 저장소는 모든 트랙을 '지문 없음 → 다시 씀'으로 본다(sqlite_master로 가림 — 판 '3' 그대로).
pub const P4_TABLES: [(&str, &str); 4] = [
    ("event_hay", "event_hay(id INTEGER PRIMARY KEY,hay TEXT NOT NULL)"),
    ("lens_names", "lens_names(uid TEXT NOT NULL,track TEXT NOT NULL,name TEXT NOT NULL,pack INTEGER NOT NULL,PRIMARY KEY(uid,track)) WITHOUT ROWID"),
    ("blobs", "blobs(key TEXT PRIMARY KEY,pack INTEGER NOT NULL,mime TEXT NOT NULL,bytes BLOB NOT NULL)"),
    ("track_prints", "track_prints(key TEXT PRIMARY KEY,print TEXT NOT NULL,needs TEXT NOT NULL DEFAULT '{}')"),
];

pub fn create(db: &Connection) -> Result<()> {
    db.execute_batch("
      PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;
      -- meta `now` = 지은 날의 ISO 글 — '오늘'(진행 중 정권의 끝)의 기준(계획 P4 과제 5a). 배치 JSON의 `now`가 있으면 그 글 그대로,
      --   없으면 지은 시각(UTC · 초까지). 배치를 가져와 지은 저장소(legacy::fill_into)만 적는다 — 가상 자료 생성기처럼 `Builder`를 직접 쓰는
      --   길은 언제 지어도 같은 바이트여야 해서 적지 않는다. 이 키가 없는 저장소(옛 저장소 포함 · 판 '3' 그대로)는 읽는 쪽이 '모름'으로 본다.
      CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      CREATE TABLE sources(id INTEGER PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL);
      CREATE TABLE files(id INTEGER PRIMARY KEY,source INTEGER NOT NULL REFERENCES sources(id),kind TEXT NOT NULL,path TEXT NOT NULL,sha256 TEXT NOT NULL,bytes INTEGER NOT NULL);
      CREATE TABLE packs(id INTEGER PRIMARY KEY,name TEXT NOT NULL,original BLOB,sha256 TEXT);
      -- color: 0xRRGGBB. dynasty · leader · cabinet · organ: 그 단이 이 트랙에 있는가(0/1) — 지금 연표는 트랙 단위로 정한다.
      -- rail_levels: 기간 막대의 단 수(2~3).
      -- key: 트랙의 글자 id(`mw-coast` …) — 항목 기록(entities)의 `track`이 이 글자다. 없으면 빈 글자.
      -- sphere: 트랙이 든 문화권의 글자 id(`east-asia` … — 리메이크 조각 ②). 없으면 빈 글자(판 트랙 · 옛 배치).
      --   문화권의 이름 · 차례는 meta `spheres`(JSON 배열)에 있다. 이 열이 없는 옛 저장소는 layout 답에 빈 글자를 싣는다(판 '3' 그대로).
      CREATE TABLE tracks(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),ord INTEGER NOT NULL,name TEXT NOT NULL,
        color INTEGER NOT NULL DEFAULT 0,dynasty INTEGER NOT NULL DEFAULT 0,leader INTEGER NOT NULL DEFAULT 0,
        cabinet INTEGER NOT NULL DEFAULT 0,organ INTEGER NOT NULL DEFAULT 0,rail_levels INTEGER NOT NULL DEFAULT 2,
        key TEXT NOT NULL DEFAULT '',sphere TEXT NOT NULL DEFAULT '');
      -- rows.id = 전체 줄 번호(0부터 빈틈없이). 높이와 자리는 100% 배율 px, 자리는 줄 안 상대값이고 없으면 -1.
      -- 2의 굳은 자리 열(height · band_top … organ_top)은 '모두 켠 · 자동 밀도'의 값이고 대조 검사에 쓴다.
      -- 3의 열: kind 0 보통 · 1 소속 · 2 그 밖 · 3 접힌 민족 줄 / group_start 민족 묶음의 첫 줄 / scope_pad 대범위 테두리의 여백
      --   / phase 시기 구분 단의 수 / rank 지위 단 / cats 분류별 글줄의 분류 번호 목록 / fig 자동 밀도의 인물 단 수
      --   / fig_wide 넉넉하게 밀도의 인물 단 수(없으면 fig와 같다) / dep 예속 칸의 높이
      --   / zones 띠 아래 덧붙는 탭의 줄 수 / hem 바탕 문화의 이름 단.
      --   / variant 그 줄을 만드는 변형의 번호(0이면 기본 줄 — 변형 없이도 늘 있는 줄. 계약 3-2절).
      CREATE TABLE rows(id INTEGER PRIMARY KEY,track INTEGER NOT NULL REFERENCES tracks(id),ord INTEGER NOT NULL,height INTEGER NOT NULL,
        band_top INTEGER NOT NULL,band_h INTEGER NOT NULL,dyn_top INTEGER NOT NULL,lead_top INTEGER NOT NULL,cab_top INTEGER NOT NULL,
        text_top INTEGER NOT NULL,text_lines INTEGER NOT NULL,rail_top INTEGER NOT NULL,organ_top INTEGER NOT NULL,
        kind INTEGER NOT NULL DEFAULT 0,group_start INTEGER NOT NULL DEFAULT 0,scope_pad INTEGER NOT NULL DEFAULT 0,
        phase INTEGER NOT NULL DEFAULT 0,rank INTEGER NOT NULL DEFAULT 0,cats TEXT NOT NULL DEFAULT '[]',
        fig INTEGER NOT NULL DEFAULT 0,fig_wide INTEGER NOT NULL DEFAULT 0,dep INTEGER NOT NULL DEFAULT 0,
        zones INTEGER NOT NULL DEFAULT 0,hem INTEGER NOT NULL DEFAULT 0,variant INTEGER NOT NULL DEFAULT 0);
      -- 왼쪽 줄 이름 칸이 쓰는 후보 띠(계약 6-8절). 원소의 JSON을 통째로 보존한다 — 뜻은 그리는 쪽이 본다.
      CREATE TABLE row_labels(row INTEGER NOT NULL REFERENCES rows(id),start INTEGER NOT NULL,end INTEGER NOT NULL,period INTEGER NOT NULL,json TEXT NOT NULL);
      CREATE INDEX row_labels_at ON row_labels(row,start);
      -- first_row = 전체 줄 번호. kind: 0 민족 · 1 문화 · 2 대범위
      CREATE TABLE groups(id INTEGER PRIMARY KEY,track INTEGER NOT NULL REFERENCES tracks(id),depth INTEGER NOT NULL,first_row INTEGER NOT NULL,
        row_count INTEGER NOT NULL,name TEXT NOT NULL,color INTEGER NOT NULL,kind INTEGER NOT NULL);
      -- ord = 분류 번호(0부터). 사건의 look 아래 8비트가 이 번호를 가리킨다.
      CREATE TABLE categories(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),ord INTEGER NOT NULL,key TEXT NOT NULL,name TEXT NOT NULL,color INTEGER NOT NULL);
      -- kind: 1 시대 구분(track NULL = 공통 줄) · 2 연호 · 3 도읍 · 4 배도. lane: 그 줄 안의 단(겹치면 나눔).
      -- style: 1 시작 미정 | 2 끝 미정 | 4 임시 도읍(점선 칸) | 8 망명(기울임).
      -- strip: 같은 값끼리 이어진 긴 둥근 칸(연호 = 정권 · 도읍 = 정권의 갈래). seq: 그 정권의 목록에서의 순번.
      CREATE TABLE axis_cells(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),kind INTEGER NOT NULL,track INTEGER,lane INTEGER NOT NULL,
        start INTEGER NOT NULL,end INTEGER NOT NULL,name TEXT NOT NULL,color INTEGER NOT NULL,style INTEGER NOT NULL,strip INTEGER NOT NULL,seq INTEGER NOT NULL,CHECK(start<=end));
      CREATE TABLE epochs(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),start INTEGER NOT NULL,end INTEGER NOT NULL,color INTEGER NOT NULL,name TEXT NOT NULL,CHECK(start<=end));
      -- fuzzy: 1 시작 미정 | 2 끝 미정(옅은 끝). color: 0xRRGGBB. look · tag · sub의 뜻은 계약 6절(내보내기 담당이 채운다).
      -- form(스키마 4 · 계약 1-1 — 비트): 0 ~ 4 형식 4 종류 + 1(0 = 모름 — 옛 저장소 · 객체가 아닌 그림 띠: 바탕 문화 · 기관 · 왕조)
      --   · 5 ~ 9 관계(0 없음 · 1 조공 · 2 봉국 · 3 자치령 · 4 종속 · 5 보호 · 6 위성 · 7 괴뢰 · 8 위임 · 9 식민 · 10 점령 · 11 복속 · 12 기미 · 13 직할
      --   · 14 명목상 · 15 구성국 · 16 동군연합 · 17 공동 통치) · 10 ~ 12 정통성 + 1(0 = 비움 · 1 정통 · 2 대립 · 3 공동 · 4 섭정 · 5 명목 · 6 주장)
      --   · 13 ~ 15 중요도 + 1(0 = 비움 — 기간 길이로 짐작 · 1 ~ 4 = 중요도 0 ~ 3). 그림 갈래는 지금처럼 look이 정하고 form은 싣기만 한다.
      --   맨 끝 열이라 옛 저장소에 `ALTER TABLE … ADD COLUMN`으로 더해도 같은 꼴이다(patch의 OLDER_COLUMNS — 이 열이 없는 저장소는 0으로 읽는다).
      CREATE TABLE periods(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),row INTEGER NOT NULL REFERENCES rows(id),
        start INTEGER NOT NULL,end INTEGER NOT NULL,fuzzy INTEGER NOT NULL,color INTEGER NOT NULL,name TEXT NOT NULL,
        look INTEGER NOT NULL DEFAULT 0,tag TEXT NOT NULL DEFAULT '',sub INTEGER NOT NULL DEFAULT 0,uid TEXT NOT NULL DEFAULT '',
        variant INTEGER NOT NULL DEFAULT 0,form INTEGER NOT NULL DEFAULT 0,CHECK(start<=end));
      -- kind: 0 왕조 · 1 지도자 · 2 내각 · 3 기관 …(계약 6절). lane: 그 단 안의 자리. style · color의 뜻도 6절.
      CREATE TABLE cells(id INTEGER PRIMARY KEY,period INTEGER NOT NULL REFERENCES periods(id),kind INTEGER NOT NULL,
        start INTEGER NOT NULL,end INTEGER NOT NULL,name TEXT NOT NULL,
        lane INTEGER NOT NULL DEFAULT 0,style INTEGER NOT NULL DEFAULT 0,color INTEGER NOT NULL DEFAULT 0,
        variant INTEGER NOT NULL DEFAULT 0,CHECK(start<=end));
      -- lane = rows.id, importance 1~3. look(아래 8비트 = 분류 번호) · label(이름 옆 날짜 글) · rail(기간 막대의 단)의 뜻은 계약 6절.
      -- band = 그 사건이 든 띠의 id(없으면 0) — 지금 연표는 점 색 · 이름 가두기 · 묶기를 모두 제 띠 안에서 한다.
      -- ord = 트랙 안 사건 차례(0부터 — 배치에서 그 사건이 놓인 줄의 트랙의 사건 가운데 몇째인가). 타일 대표(중요도가 같을 때)와 `same_year`의 사건
      --   목록(트랙마다 · 창의 목록 — 계획 P4 판정 R67 · 계약 2-1)의 동률을 번호 대신 (사건 제 줄의 트랙 차례, ord)로 깬다(계획 P4 판정 R23 — 트랙을 고쳐 쓰면 같은 uid는 옛 번호 · 새 uid는 끝 번호라 번호 차례가
      --   배치 차례와 갈린다. 트랙 안 차례라 다시 쓰지 않은 트랙의 값은 낡지 않고, 트랙 차례는 열 때 `RowMap`이 안다). 배치의 사건이 트랙 차례로
      --   묶여 나오므로 새로 지은 저장소는 이 차례 = 번호 차례라 답이 예전과 같다. 예외(판정 R26): 내보내기는 변형에서만 있는 사건을 사건 목록 끝에
      --   붙이므로 그런 사건이 앞 트랙의 것이면 그 사건만 번호 차례가 (트랙 차례, ord) 차례와 갈린다 — 그 사건은 요약에 들지 않고 변형을 켠 촘촘한
      --   단계에서만 대표를 다툰다(`apply.rs`의 R26 검사가 정답지 자료에서 지킨다). 이 열이 없는 옛 저장소(판 '3')는 읽는 쪽이
      --   `pragma_table_info`로 가려 번호로 깬다.
      -- raw = 가져온 원소 JSON 그대로(읽는 곳 없음). 그 안의 `track` · `pack` 순번은 그 배치 안의 것이라 믿지 않는다 — DLC를 넣고 빼면(patch::apply) 하위 배치의
      --   순번이거나 옛 순번이다(계획 P4 과제 A+ 5). 트랙은 lane → rows.track.
      CREATE TABLE events(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),lane INTEGER NOT NULL REFERENCES rows(id),start INTEGER,end INTEGER,lo INTEGER,hi INTEGER,
        importance INTEGER NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,source INTEGER REFERENCES sources(id),raw TEXT,
        look INTEGER NOT NULL DEFAULT 0,label TEXT NOT NULL DEFAULT '',rail INTEGER NOT NULL DEFAULT 0,uid TEXT NOT NULL DEFAULT '',band INTEGER NOT NULL DEFAULT 0,variant INTEGER NOT NULL DEFAULT 0,
        ord INTEGER NOT NULL DEFAULT 0,
        CHECK(start IS NULL OR start<=end),CHECK(lo IS NULL OR lo<=hi),CHECK(importance BETWEEN 1 AND 3));
      -- 띠 · 칸 · 사건이 아닌 모든 그릴 것의 일반 통로. section(16 이상)마다 a~d · text2의 뜻은 계약 6절이 정한다.
      -- ref = 가리키는 띠 · 사건의 id(없으면 0). row~row2 = 걸친 줄 범위(전체 줄 번호).
      -- ref_kind = ref가 무엇인가(0 없음 · 1 띠 · 2 사건). 띠와 사건의 번호는 서로 다른 셈이라 번호만으로는 가릴 수 없다 —
      --   거르개가 '꺼진 띠에 딸린 것'과 '빠진 사건의 막대'를 가려내려고 넣을 때 적어 둔다(타일에는 싣지 않는다).
      CREATE TABLE items(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),section INTEGER NOT NULL,row INTEGER NOT NULL,row2 INTEGER NOT NULL,
        start INTEGER NOT NULL,end INTEGER NOT NULL,ref INTEGER NOT NULL,name TEXT NOT NULL,color INTEGER NOT NULL,
        a INTEGER NOT NULL,b INTEGER NOT NULL,c INTEGER NOT NULL,d INTEGER NOT NULL,text2 TEXT NOT NULL,
        ref_kind INTEGER NOT NULL DEFAULT 0,variant INTEGER NOT NULL DEFAULT 0,CHECK(start<=end),CHECK(row<=row2));
      -- 상세 창이 읽는 항목 기록(넣을 때 정규화한 것 그대로).
      -- ord = 넣은 차례(0부터 — 배치의 `entities` 배열에서의 차례). 이 표는 uid 차례로 놓여(WITHOUT ROWID) 차례가 남지 않으므로 따로 적는다 —
      --   가문 · 단체 · 제도의 이름 표 차례(builder의 ORDERED_KINDS)를 다시 펼 때 이 차례로 다시 모은다(계획 P4 과제 5a · 6).
      -- sum = json 글의 SHA-256 16진 글 앞 16자 — DLC를 넣고 뺄 때 항목 기록을 uid · 지문으로 견주어 지움 · 바꿈 · 넣음을 가른다(`patch::apply`의 entities 걸음 — 과제 5d).
      --   두 열이 없는 옛 저장소(판 '3' 그대로)는 읽는 쪽이 `pragma_table_info`로 가린다 — 없으면 '지문 없음 → 다시 씀'으로 본다.
      CREATE TABLE entities(uid TEXT PRIMARY KEY,pack INTEGER NOT NULL REFERENCES packs(id),kind TEXT NOT NULL,json TEXT NOT NULL,
        ord INTEGER NOT NULL DEFAULT 0,sum TEXT NOT NULL DEFAULT '') WITHOUT ROWID;
      -- 이름 검색(search에 kinds를 주었을 때)이 훑는 표. 넣기가 끝날 때 한 번에 펴 둔다(builder의 build_names).
      -- kind: 항목 기록의 종류(period · organ · culture · dynasty · figure · epoch · scope · house · group · institution · doc) 또는 cell(칸).
      --   넣는 갈래는 허용 목록이다 — 이름이 있어도 cal · themes · place · surname · view · map · font 기록은 넣지 않는다.
      -- cell: 띠 안 칸이면 계약 6-2의 단 번호, 날짜 칸이면 100 + 계약 6-3의 종류, 칸이 아니면 NULL.
      -- sub: 목록에 함께 적는 작은 글 — 정권 또는 트랙 이름과 칸 종류를 이은 것.
      -- row · start · end: 찾은 것을 바로 짚을 자리. 모르면 row -1 · start NULL이다.
      -- cell_ref: 상세 창이 그 칸을 여는 글자 참조(`leader:3` · `era:2` · `capital:0` — 항목 기록의 x_cellBounds와 같은 꼴).
      --   칸이 아니면 빈 글자다. 검색 결과의 `cell`이 이 값이고, 옛 정수는 `cell_kind`로 나간다.
      -- hay: 이름 · 곁글 말고 더 맞춰 볼 **찾을 글**(소문자 — 지금 연표 `runSearch`의 찾을 글에서 이름을 뺀 것).
      --   기록 줄은 그 기록의 `x_find.hay` + 설명, 칸 줄은 주인 기록의 `x_find.cells[칸 참조]`다(build_names가 채운다).
      --   이 열이 없는 옛 저장소는 이름 · 곁글로만 맞춘다(조회가 `pragma_table_info`로 가린다 — 판 '3'은 그대로).
      --   kind에는 단체(group) · 제도(institution)도 든다 — 줄은 `x_find.row`가 가리키는 정권의 띠 줄을 빌린다.
      CREATE TABLE names(id INTEGER PRIMARY KEY,pack INTEGER NOT NULL,kind TEXT NOT NULL,uid TEXT NOT NULL,name TEXT NOT NULL,
        sub TEXT NOT NULL,cell INTEGER,start INTEGER,end INTEGER,row INTEGER NOT NULL,color INTEGER NOT NULL,
        cell_ref TEXT NOT NULL DEFAULT '',hay TEXT NOT NULL DEFAULT '');
    ")?;
    // P4가 더한 표 넷 — 옛 저장소에는 `patch::apply`의 "delete"(`ensure_schema`)가 같은 글로 만든다([`P4_TABLES`] — 한 곳).
    for (_, ddl) in P4_TABLES {
        db.execute_batch(&format!("CREATE TABLE {ddl};"))?;
    }
    // 스키마 4의 문화권 단위 줄 — 옛 저장소에는 `patch::apply`의 "delete"(`ensure_schema`)가 같은 글로 만든다([`SPHERE_LINES`] — 한 곳).
    db.execute_batch(&format!("CREATE TABLE {SPHERE_LINES};"))?;
    db.execute_batch("
      CREATE VIRTUAL TABLE bounds USING rtree_i32(id,lo_day,hi_day,lane_min,lane_max);
      CREATE VIRTUAL TABLE span_bounds USING rtree_i32(id,lo_day,hi_day,lane_min,lane_max,lod_min,lod_max);
      CREATE VIRTUAL TABLE period_bounds USING rtree_i32(id,lo_day,hi_day,row_min,row_max,lod_min,lod_max);
      CREATE VIRTUAL TABLE cell_bounds USING rtree_i32(id,lo_day,hi_day,row_min,row_max,lod_min,lod_max);
      CREATE VIRTUAL TABLE item_bounds USING rtree_i32(id,lo_day,hi_day,row_min,row_max,lod_min,lod_max);
      CREATE VIRTUAL TABLE search USING fts5(terms,content='',detail=none,tokenize='ascii');
      -- reps: 대표 최대 4개 × (id u32 · 중요도 u8 · 채움 u8 · 제목 길이 u16 · 시작 i64 · look u32 · 딱지 길이 u16 · 채움 u16 · band u32 · 제목 · 딱지), 작은 끝
      -- 변형(variant) — 켤 수 있는 것 하나마다 '기본 상태와의 차이'(계약 3-2절 · 2-4절).
      -- kind: 1 소속 펼치기(band = 펼치는 상위 띠) · 2 대범위 모아 보기(uid = 대범위의 이름).
      CREATE TABLE variants(id INTEGER PRIMARY KEY,key TEXT NOT NULL UNIQUE,kind INTEGER NOT NULL,track INTEGER NOT NULL,
        band INTEGER NOT NULL DEFAULT 0,uid TEXT NOT NULL DEFAULT '',name TEXT NOT NULL DEFAULT '',notes TEXT NOT NULL DEFAULT '');
      -- 그 변형에서 줄을 쌓는 차례. after = 어느 줄 바로 아래인가(-1이면 트랙의 맨 위) · ord = 같은 자리에 여럿이면 차례.
      -- is_new = rows.variant가 이 변형인 줄(그 변형에서만 있는 줄). scope_pad · group_start는 기본 줄의 값을 덮는다.
      CREATE TABLE variant_rows(variant INTEGER NOT NULL,row INTEGER NOT NULL,after INTEGER NOT NULL,ord INTEGER NOT NULL,
        is_new INTEGER NOT NULL DEFAULT 0,scope_pad INTEGER NOT NULL DEFAULT 0,group_start INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(variant,row)) WITHOUT ROWID;
      -- 줄이 옮겨 쌓이는 것으로 설명되지 않는 이사. kind: 1 띠 · 2 사건. ref = 그 번호, row = 도착 줄.
      CREATE TABLE variant_moves(variant INTEGER NOT NULL,kind INTEGER NOT NULL,ref INTEGER NOT NULL,row INTEGER NOT NULL,
        PRIMARY KEY(variant,kind,ref)) WITHOUT ROWID;
      -- 그 변형이 켜지면 가려지는 기본 판(대신 variant를 단 '변형 판'이 나온다). kind: 3 칸 · 4 일반 항목.
      CREATE TABLE variant_hides(variant INTEGER NOT NULL,kind INTEGER NOT NULL,ref INTEGER NOT NULL,
        PRIMARY KEY(variant,kind,ref)) WITHOUT ROWID;
      -- 그 변형에서 생기는 왼쪽 칸의 묶음(대범위 칸). rows = 그 묶음에 드는 전체 줄 번호의 JSON 배열.
      CREATE TABLE variant_groups(id INTEGER PRIMARY KEY,variant INTEGER NOT NULL,key TEXT NOT NULL,depth INTEGER NOT NULL,
        name TEXT NOT NULL,color INTEGER NOT NULL,kind INTEGER NOT NULL,rows TEXT NOT NULL);
      CREATE INDEX variant_moves_to ON variant_moves(variant,row);
      -- cats: 그 통에 든 사건의 분류별 수 — (분류 번호 u8 · 개수 u32) 다섯 바이트씩, 분류 번호 오름차순, 작은 끝.
      --   분류가 없는 사건(look & 0xFF == 255)은 넣지 않는다. 개수 알약의 분류 비율 색줄이 대표 넷이 아니라
      --   통 전체의 비율을 따르게 하는 값이다(계약 5절의 구역 4 · 명세 02의 5.3).
      -- ords: 대표마다의 트랙 안 사건 차례(events.ord)를 u32 작은 끝으로 대표와 같은 차례로(계획 P4 판정 R24). 타일이 자료집 여럿의 요약을 한 통에
      --   합칠 때 동률을 사건 표를 찾아가지 않고 깬다. 이 열이 없거나 비어 있는(옛 저장소 · 그 위에 apply가 열을 더한 뒤의 옛 줄) 요약은 번호로 깬다.
      CREATE TABLE summaries(level INTEGER NOT NULL,lane INTEGER NOT NULL,bucket INTEGER NOT NULL,pack INTEGER NOT NULL,n INTEGER NOT NULL,reps BLOB NOT NULL,
        cats BLOB NOT NULL DEFAULT x'',ords BLOB NOT NULL DEFAULT x'',PRIMARY KEY(level,lane,bucket,pack)) WITHOUT ROWID;
    ")?;
    Ok(())
}

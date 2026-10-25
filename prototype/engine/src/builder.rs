//! 저장소를 새로 만드는 단 하나의 길. 가상 자료 생성기도 월흔해 가져오기도 여기를 거친다.
//! 무거운 일(색인 · 가늘기 등급 · 단계별 '대표 + 개수' 요약)은 넣을 때 한 번만 하고, 열람 쪽은 읽기만 한다.
//! 스키마 3의 새 표 · 새 열은 `docs/계약-아카이브-3단계.md` 1절, 스키마 4의 띠 `form` · 문화권 단위 줄 `sphere_lines`는 1-1절.
use crate::levels::{bucket_minutes, bucket_of, lod_of, LEVEL_MAX, PRE_MIN};
use crate::{grams, schema, Result, DAY};
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::rc::Rc;

/// 트랙 하나. 색은 0xRRGGBB, 단(왕조 · 지도자 · 내각 · 기관)은 트랙 단위로 있고 없다.
pub struct TrackIn<'a> {
    pub pack: i64,
    pub name: &'a str,
    pub color: u32,
    pub dynasty: i64,
    pub leader: i64,
    pub cabinet: i64,
    pub organ: i64,
    /// 기간 막대의 단 수(2~3).
    pub rail_levels: i64,
    /// 트랙의 글자 id(`mw-coast` …). 항목 기록의 `track`이 이 글자다 — 없으면 빈 글자.
    pub key: &'a str,
}

impl<'a> TrackIn<'a> {
    /// 2판과 같은 트랙(색 없음 · 모든 단 켬 · 막대 두 단).
    pub fn plain(pack: i64, name: &'a str) -> Self {
        Self { pack, name, color: 0, dynasty: 1, leader: 1, cabinet: 1, organ: 1, rail_levels: 2, key: "" }
    }
}

/// 줄 하나의 생김새. 100% 배율 px이고, 자리는 줄 안에서의 상대값이며 없으면 -1.
/// 2판의 굳은 자리 값이다 — '모두 켠 · 자동 밀도'에서 지금 연표가 셈한 자리이고, 화면 쪽 다시 쌓기의 대조 기준이 된다.
#[derive(Clone, Copy, Debug)]
pub struct RowGeo {
    /// 띠 위의 틈(책갈피 탭 자리)까지 품은 줄의 몫.
    pub height: i64,
    pub band_top: i64,
    pub band_h: i64,
    pub dyn_top: i64,
    pub lead_top: i64,
    pub cab_top: i64,
    pub text_top: i64,
    pub text_lines: i64,
    pub rail_top: i64,
    pub organ_top: i64,
}

/// 줄의 3판 값. 화면이 보기 조건에 맞춰 단을 다시 쌓을 때 쓴다(계약 1절 · 3절).
#[derive(Clone, Debug, Default)]
pub struct RowExtra {
    /// 0 보통 · 1 소속(상위 띠 아래 펼친 줄) · 2 그 밖(공통 줄) · 3 접힌 민족 줄
    pub kind: i64,
    /// 민족 묶음의 첫 줄(위 틈 +14)
    pub group_start: i64,
    /// 대범위 테두리의 머리 · 아래 여백(px)
    pub scope_pad: i64,
    /// 시기 구분 단의 수(0~3)
    pub phase: i64,
    /// 지위 단(0/1)
    pub rank: i64,
    /// 분류별 글줄: 분류 번호의 목록(둘 이상일 때만, 아니면 빈 목록)
    pub cats: Vec<i64>,
    /// 자동 밀도의 인물 단 수(0~2)
    pub fig: i64,
    /// 넉넉하게 밀도의 인물 단 수(0~3). 0이면 fig와 같다.
    pub fig_wide: i64,
    /// 예속 칸의 높이(px · 줄 수 × 13 − 1)
    pub dep: i64,
    /// 띠 아래 덧붙는 탭의 줄 수(구역 탭 + 속국 이름표)
    pub zones: i64,
    /// 바탕 문화의 이름 단(0/1)
    pub hem: i64,
    /// 그 줄을 만드는 변형의 번호(0이면 기본 줄 — 변형 없이도 늘 있는 줄).
    pub variant: i64,
}

/// 민족 · 문화 · 대범위 묶음. first_row는 전체 줄 번호.
pub struct GroupIn<'a> {
    pub track: i64,
    pub depth: i64,
    pub first_row: i64,
    pub row_count: i64,
    pub name: &'a str,
    pub color: u32,
    /// 0 민족 · 1 문화 · 2 대범위
    pub kind: i64,
}

/// 날짜 칸 하나. track이 None이면 공통 줄(시대 구분).
pub struct AxisCellIn<'a> {
    pub pack: i64,
    /// 1 시대 구분 · 2 연호 · 3 도읍 · 4 배도
    pub kind: i64,
    pub track: Option<i64>,
    pub lane: i64,
    pub start: i64,
    pub end: i64,
    pub name: &'a str,
    pub color: u32,
    /// 1 시작 미정 | 2 끝 미정 | 4 임시 도읍(점선 칸) | 8 망명(기울임)
    pub style: i64,
    /// 같은 값끼리 이어진 긴 둥근 칸
    pub strip: i64,
    pub seq: i64,
}

/// 띠 하나. look · tag · sub의 뜻은 계약 6절(내보내기 담당이 채운다).
pub struct PeriodIn<'a> {
    pub pack: i64,
    /// 전체 줄 번호.
    pub row: i64,
    pub start: i64,
    pub end: i64,
    /// 1 시작 미정 | 2 끝 미정
    pub fuzzy: i64,
    pub color: u32,
    pub name: &'a str,
    pub look: i64,
    pub tag: &'a str,
    pub sub: i64,
    /// 내보내기 쪽의 이름(상세 창 · 일반 항목이 가리킨다). 없으면 빈 글자.
    pub uid: &'a str,
    /// 그 변형에서만 그려지는 띠면 그 변형의 번호(0이면 기본).
    pub variant: i64,
    /// 형식 4의 뜻(스키마 4 · 계약 1-1 — 비트): 0 ~ 4 종류 + 1 · 5 ~ 9 관계 · 10 ~ 12 정통성 + 1 · 13 ~ 15 중요도 + 1. 0 = 모름
    /// (옛 배치 · 객체가 아닌 그림 띠). 그림 갈래는 `look`이 정하고 이 값은 싣기만 한다.
    pub form: i64,
}

/// 문화권 단위의 줄 하나(스키마 4 · 계약 1-1 — `sphere_lines` 표: 1 사람 띠 · 2 문화권 시대 구분 · 3 문화권 주기 줄).
/// 배치 JSON의 최상위 `sphereLines` 원소를 [`SphereLineIn::read`]로 읽어 [`put_sphere_lines`]가 넣는다.
pub struct SphereLineIn<'a> {
    /// 자료집 번호(저장소의 `packs.id` — 배치의 `pack` 순번이 아니다).
    pub pack: i64,
    /// 문화권의 글자 id(`tracks.sphere`와 같은 글).
    pub sphere: &'a str,
    pub kind: i64,
    /// 분(띠와 같은 단위). kind 3(주기 줄)은 둘 다 0이다.
    pub start: i64,
    pub end: i64,
    pub name: &'a str,
    pub uid: &'a str,
    pub color: u32,
    /// JSON 글(사람 띠의 왕관 목록 · 주기 설정) — 없으면 빈 글자.
    pub data: std::borrow::Cow<'a, str>,
}

impl<'a> SphereLineIn<'a> {
    /// 배치의 원소 하나를 읽는다 — 숫자는 띠와 같은 규칙(`legacy::int` — 빠지거나 null이면 0), `data`는 글이면 그대로 · 글이 아니면 JSON 글 · null이면 빈 글자.
    pub fn read(l: &'a serde_json::Value, pack: i64) -> Self {
        use crate::legacy::{int, text};
        let data = match &l["data"] {
            serde_json::Value::Null => std::borrow::Cow::Borrowed(""),
            serde_json::Value::String(s) => std::borrow::Cow::Borrowed(s.as_str()),
            other => std::borrow::Cow::Owned(other.to_string()),
        };
        Self { pack, sphere: text(l, "sphere"), kind: int(l, "kind"), start: int(l, "start"), end: int(l, "end"), name: text(l, "name"), uid: text(l, "uid"),
            color: int(l, "color") as u32, data }
    }
}

/// 문화권 단위의 줄(`sphereLines` — 배치 차례가 곧 `id` 차례)을 `sphere_lines` 표에 넣고 넣은 수를 돌려준다. 짓기(`legacy::fill_into` — [`Builder::sphere_lines`])와
/// 넣고 빼기의 온 판(`patch::apply`의 "globals")이 함께 쓴다. 자료집은 `pack_of(원소, uid)` — 띠 · 사건 · 항목 기록과 같은 규칙(`legacy::pack_slot`)을 부르는 쪽이 준다.
/// 뒤집힌 기간은 그 줄을 말하는 Err다. 넣는 범위로 `meta.min` · `max`를 넓히지 않는다 — kind 3은 start = end = 0(1970년)이라 넓히면 고대만 있는 자료의
/// 1배 화면(시간축의 끝)이 바뀐다. 사람 띠 · 문화권 시대는 띠 · 날짜 칸 안에 있어 넓힐 일도 없다.
pub fn put_sphere_lines(db: &Connection, lines: &[serde_json::Value], pack_of: impl Fn(&serde_json::Value, &str) -> i64) -> Result<usize> {
    let mut add = db.prepare_cached("INSERT INTO sphere_lines(pack,sphere,kind,start,end,name,uid,color,data) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)")?;
    for (at, l) in lines.iter().enumerate() {
        let line = SphereLineIn::read(l, pack_of(l, crate::legacy::text(l, "uid")));
        if line.start > line.end {
            return Err(format!("문화권 단위 줄 {at}번째(kind {} · 문화권 «{}» · «{}»)의 기간이 뒤집혔습니다({} > {})", line.kind, line.sphere, line.name, line.start, line.end).into());
        }
        add.execute(params![line.pack, line.sphere, line.kind, line.start, line.end, line.name, line.uid, line.color, line.data.as_ref()])?;
    }
    Ok(lines.len())
}

/// 띠 안의 칸 하나.
pub struct CellIn<'a> {
    /// 띠의 번호(`Builder::period`가 돌려준 값).
    pub period: i64,
    pub kind: i64,
    pub start: i64,
    pub end: i64,
    pub name: &'a str,
    pub lane: i64,
    pub style: i64,
    pub color: u32,
    /// 그 변형에서만 그려지는 칸이면 그 변형의 번호(0이면 기본).
    pub variant: i64,
}

#[derive(Default)]
pub struct EventIn<'a> {
    pub pack: i64,
    /// 전체 줄 번호(`Builder::row`가 돌려준 값).
    pub lane: i64,
    pub start: Option<i64>,
    pub end: Option<i64>,
    /// 이설 · 연대 폭까지 품은 범위. 비우면 start · end와 같다.
    pub lo: Option<i64>,
    pub hi: Option<i64>,
    pub importance: i64,
    pub title: &'a str,
    pub body: &'a str,
    pub source: Option<i64>,
    pub raw: Option<&'a str>,
    /// 아래 8비트가 분류 번호. 그 위의 뜻은 계약 6절.
    pub look: i64,
    /// 이름 옆 날짜 글.
    pub label: &'a str,
    /// 기간 막대의 단.
    pub rail: i64,
    pub uid: &'a str,
    /// 그 사건이 든 띠의 번호(없으면 0). 점 색 · 이름 가두기 · 묶기가 모두 이 띠 안에서 일어난다.
    pub band: i64,
    /// 그 변형에서만 그려지는 사건이면 그 변형의 번호(0이면 기본).
    pub variant: i64,
}

/// 띠 · 칸 · 사건이 아닌 모든 그릴 것. Rust는 뜻을 모른 채 저장 · 조회 · 타일에 싣기만 한다.
pub struct ItemIn<'a> {
    pub pack: i64,
    /// 16 이상.
    pub section: i64,
    /// 걸친 줄 범위(전체 줄 번호, 양 끝 포함).
    pub row: i64,
    pub row2: i64,
    pub start: i64,
    pub end: i64,
    /// 실리는 가장 성긴 단계. None이면 기간에서 셈한다.
    pub lod: Option<i64>,
    /// 가리키는 띠 · 사건의 번호(없으면 0).
    pub ref_id: i64,
    /// `ref_id`가 무엇인가 — 0 없음 · 1 띠 · 2 사건. 거르개가 '꺼진 띠에 딸린 것'을 가려낼 때 쓴다.
    pub ref_kind: i64,
    pub name: &'a str,
    pub color: u32,
    pub a: i64,
    pub b: i64,
    pub c: i64,
    pub d: i64,
    pub text2: &'a str,
    /// 그 변형에서만 그려지는 항목이면 그 변형의 번호(0이면 기본).
    pub variant: i64,
}

/// 대표 하나. 제목 · look · 딱지를 함께 들고 있어 타일이 성긴 단계에서 사건 표를 대표마다 다시 찾지 않는다
/// (100만 건에서 타일 하나에 0.45초가 들던 곳). 글자는 단계끼리 나눠 쓴다(Rc).
#[derive(Clone)]
struct Rep {
    importance: u8,
    id: u32,
    /// 트랙 안 사건 차례(`events.ord` — 판정 R23). 요약 칸은 한 줄(곧 한 트랙)의 것이라 트랙 차례는 늘 같고, 중요도가 같으면 이것이 작은 것이
    /// 앞선다(같으면 번호).
    ord: i64,
    start: i64,
    look: u32,
    band: u32,
    /// 시작 날짜의 정밀도(`rail`의 8~10비트) — 머리의 채움 바이트(5번째)에 실어 성긴 단계에서도 세기 괄호를 그린다(묶음 5 · 6번 · 옛 저장소는 0 = 해).
    prec: u8,
    title: Rc<str>,
    label: Rc<str>,
}

/// 요약 한 칸: 개수와 대표(중요도 큰 순, 같으면 트랙 안 차례(`ord`) 작은 순 · 그다음 번호) 최대 넷, 그리고 분류별 수.
#[derive(Clone, Default)]
struct Cell {
    n: u32,
    reps: Vec<Rep>,
    /// 분류 번호 → 그 통에 든 사건 수. 분류가 없는 사건(255)은 세지 않는다.
    cats: BTreeMap<u8, u32>,
}

/// 글자를 u16 길이 안으로 자른다(글자 경계에서).
fn clip_text(text: &str) -> &[u8] {
    let mut end = text.len().min(u16::MAX as usize);
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    &text.as_bytes()[..end]
}

impl Cell {
    fn offer(&mut self, rep: Rep) {
        let key = |r: &Rep| (std::cmp::Reverse(r.importance), r.ord, r.id);
        let at = self.reps.iter().position(|r| key(&rep) < key(r)).unwrap_or(self.reps.len());
        if at < 4 {
            self.reps.insert(at, rep);
            self.reps.truncate(4);
        }
    }

    fn absorb(&mut self, other: &Cell) {
        self.n += other.n;
        for rep in &other.reps {
            self.offer(rep.clone());
        }
        for (cat, count) in &other.cats {
            *self.cats.entry(*cat).or_default() += *count;
        }
    }

    /// 사건 하나를 분류별 수에 센다. 분류가 없는 사건(`look & 0xFF` = 255)은 세지 않는다.
    fn count_cat(&mut self, look: u32) {
        let cat = (look & 0xff) as u8;
        if cat != 255 {
            *self.cats.entry(cat).or_default() += 1;
        }
    }

    /// 분류별 수 = (분류 번호 u8 · 개수 u32) 다섯 바이트씩, 분류 번호 오름차순, 작은 끝.
    fn cats_blob(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.cats.len() * CAT_ENTRY);
        for (cat, count) in &self.cats {
            out.push(*cat);
            out.extend_from_slice(&count.to_le_bytes());
        }
        out
    }

    /// 대표마다의 트랙 안 차례(`events.ord`) = u32 하나씩, 대표와 같은 차례, 작은 끝(`summaries.ords` — 판정 R24). 타일이 자료집 여럿의
    /// 요약을 한 통에 합칠 때 동률을 사건 표를 찾아가지 않고 깨는 데 쓴다.
    fn ords_blob(&self) -> Vec<u8> {
        self.reps.iter().flat_map(|rep| (rep.ord.clamp(0, i64::from(u32::MAX)) as u32).to_le_bytes()).collect()
    }

    /// 대표 하나 = 번호 u32 · 중요도 u8 · 정밀도 u8(rail 8~10비트 — 예전의 채움 0) · 제목 길이 u16 · 시작 i64 · look u32 · 딱지 길이 u16 · 채움 u16 · band u32 · 제목 · 딱지(UTF-8), 작은 끝.
    fn blob(&self) -> Vec<u8> {
        let mut out = Vec::new();
        for rep in &self.reps {
            let (title, label) = (clip_text(&rep.title), clip_text(&rep.label));
            out.extend_from_slice(&rep.id.to_le_bytes());
            out.extend_from_slice(&[rep.importance, rep.prec & 7]);
            out.extend_from_slice(&(title.len() as u16).to_le_bytes());
            out.extend_from_slice(&rep.start.to_le_bytes());
            out.extend_from_slice(&rep.look.to_le_bytes());
            out.extend_from_slice(&(label.len() as u16).to_le_bytes());
            out.extend_from_slice(&0u16.to_le_bytes());
            out.extend_from_slice(&rep.band.to_le_bytes());
            out.extend_from_slice(title);
            out.extend_from_slice(label);
        }
        out
    }
}

/// 요약의 대표 하나가 차지하는 머리 바이트 수(제목 · 딱지는 그 뒤에 이어 붙는다).
pub const REP_HEAD: usize = 28;

/// 요약의 분류별 수 한 칸(분류 번호 u8 · 개수 u32).
pub const CAT_ENTRY: usize = 5;

/// 촘촘한 단계의 타일이 훑는 덮는 색인: 줄 · 시각 순으로 번호 · 중요도 · 자료집 · 제목 · look · 딱지 · 든 띠 · rail · 변형까지 담는다.
/// 값이 빠져 있으면 대표마다 사건 표(1,000만 건에서 5GB)의 흩어진 자리를 읽어야 한다.
/// rail은 시작 날짜의 정밀도(8~10비트 — 묶음 5)를 대표에 싣고, variant는 앱이 타일마다 붙이는 변형 조건(`AND variant=0` …)이 읽는다.
/// rail · variant 두 열은 거의 0이라 색인 한 줄에 머리 바이트 하나씩만 는다. 모양을 바꾸면 이미 만든 저장소는 `reindex`로 색인만 다시 만든다.
/// ord(트랙 안 사건 차례 — 판정 R23)는 대표의 동률을 깨는 값이라 촘촘한 단계의 조회가 함께 읽는다 — 0이 아니라 트랙의 사건 수까지 커지므로
/// 색인 한 줄에 몇 바이트(SQLite 정수는 값 크기만큼 · 1,000만 건 트랙이면 4바이트)가 는다.
pub const EVENTS_TIME_INDEX_SQL: &str = "CREATE INDEX events_time ON events(lane,start,id,importance,pack,title,look,label,band,rail,variant,ord)";

/// 조회 명령(계약 2절)이 기대는 색인. `events_band`는 '이 시기의 사건'(`events_in`)이, `cells_period`는 칸 목록(`cells_of`)이,
/// `periods_uid` · `events_uid`는 이름 → 번호(`id_of` · `ids_of`)가 쓴다.
/// 사건의 이름 색인만 부분 색인이다 — 가상 자료의 사건은 이름이 없어서 1,000만 줄을 헛되이 담게 된다.
/// 그래서 사건을 이름으로 찾는 쪽은 `uid<>''`를 함께 적는다(그래야 SQLite가 이 부분 색인을 쓴다).
/// `periods_row`는 트랙을 고쳐 쓸 때(`patch::apply`의 "delete") 줄을 지우면 외래 열쇠 확인이 띠 표를 훑지 않게 한다 — 이 색인이 없는
/// 옛 저장소에는 `apply`가 [`PERIODS_ROW_INDEX_SQL`]로 만든다.
pub const QUERY_INDEX_SQL: &str = "CREATE INDEX events_band ON events(band,start);\
    CREATE INDEX events_uid ON events(uid) WHERE uid<>'';\
    CREATE INDEX periods_uid ON periods(uid);\
    CREATE INDEX periods_row ON periods(row);\
    CREATE INDEX cells_period ON cells(period,kind,start,id);\
    CREATE INDEX names_kind ON names(kind);";

/// 옛 저장소에 `periods_row`가 없으면 만든다(`patch::apply` — 얹힌 몫 11).
pub const PERIODS_ROW_INDEX_SQL: &str = "CREATE INDEX IF NOT EXISTS periods_row ON periods(row)";

/// 이름 표에 넣는 항목 기록의 갈래 — **허용 목록**(계약 2-1). 이름 칸이 있어도 여기에 없는 기록
/// (`cal` · `themes` · `place` · `surname` · `view` · `map` · `font` …)은 넣지 않는다 — 지금 연표도 그것들을 결과 줄로 내지 않는다.
/// 사건 · 조약은 본문 색인이 맡는다. 가문 · 단체 · 제도는 [`ORDERED_KINDS`]가 따로 맡는다.
pub const NAME_KINDS: [&str; 8] = ["period", "organ", "culture", "dynasty", "figure", "epoch", "scope", "doc"];

/// 이름 미상의 사람을 뜻하는 이름 — 웹 `HT.isUnknownWho`(`/^(미상|미정|불명|모름|\?|unknown)$/i` · 앞뒤 빈칸 무시)와 같은 목록(소문자).
/// 계보 전용 인물(본문 `lineageOnly: true`)의 이름이 이 가운데 하나면 이름 미상의 사람(세계표의 빈 고리)이라 이름 표에 넣지 않는다
/// (D1 확정 설계 2-4 다 — 이름 찾기 · 검색에 넣지 않음). 기록 자체는 그대로 열린다(`entity`). 보통 인물(띠 인물)은 이름이 '미상'이어도 넣는다.
pub const UNKNOWN_WHO: [&str; 6] = ["미상", "미정", "불명", "모름", "?", "unknown"];

/// 위 이름의 앞뒤에서 지울 빈칸 — JS `String.prototype.trim`이 지우는 글자(SQLite `trim`의 둘째 인자 꼴).
/// 빈칸 · 탭 · 줄바꿈 · 줄 넘김 · 쪽 넘김 · 되돌림 · NBSP · 오검 빈칸 · U+2000~200A · 줄 · 문단 나눔 · 좁은 NBSP · 수학 빈칸 · 전각 빈칸 · BOM.
const UNKNOWN_TRIM: &str = "char(32,9,10,11,12,13,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288,65279)";

/// 이름 표에 **넣은 차례**(= 내보낸 차례 = 모델 차례)로 넣는 갈래 — 가문 · 단체 · 제도.
/// 지금 연표는 이 셋을 시작 순이 아니라 모델 차례로 결과 끝에 붙인다(제도는 모델이 주제 차례로 둔다).
/// 항목 기록 표는 uid 차례로 놓이므로(WITHOUT ROWID), 넣는 쪽이 받은 차례를 [`Builder::entity`]에서 적어 둔다.
pub const ORDERED_KINDS: [&str; 3] = ["house", "group", "institution"];

/// 찾을 글에 이름 · 설명 말고 더할 것 — 설명은 시대 구분 · 문서 · 칸에는 붙이지 않는다
/// (지금 연표 `runSearch`가 시대 구분은 이름 · 메모 · 트랙 이름만, 하위 문서는 제목만, 칸은 칸의 글만 본다).
fn hay_takes_description(kind: &str) -> bool {
    !matches!(kind, "cell" | "epoch" | "doc")
}

/// 찾을 글 하나를 소문자로 모은다(지금 연표의 `toLowerCase`와 같은 유니코드 소문자 — SQLite의 `lower()`는 ASCII만 바꾼다).
/// 이름 자체는 조회가 `lower(name||' '||sub)`로 맞추는데, 그 `lower()`가 바꾸지 못하는 글자(라틴 확장 · 그리스 · 키릴 대문자 …)가
/// 든 이름은 소문자로 한 번 더 실어 둔다 — 지금 연표처럼 소문자로 쳐도 찾히게.
fn hay_text(parts: &[Option<&str>], name: &str) -> String {
    let mut out: Vec<String> = parts.iter().flatten().map(|s| s.trim()).filter(|s| !s.is_empty()).map(str::to_lowercase).collect();
    let full = name.to_lowercase();
    if full != name.to_ascii_lowercase() {
        out.push(full);
    }
    out.join(" ")
}

/// 항목 기록 본문에서 **넣을 때 한 번** 읽어 두는 것 — 찾을 글(`x_find`) · 설명 · 트랙 · 연호/도읍 목록.
/// 나머지 열쇠는 serde가 건너뛴다(큰 기록을 값 나무로 펴지 않게). 값의 꼴이 다르면 그 값만 쓰지 않는다.
/// 넣기가 끝날 때(finalize) 항목 기록 표를 다시 읽고 JSON을 다시 풀면 월흔해에서만 수백 ms가 든다.
#[derive(serde::Deserialize, Default)]
struct Peek {
    #[serde(default)]
    description: serde_json::Value,
    #[serde(default)]
    x_find: PeekFind,
    #[serde(default)]
    track: serde_json::Value,
    #[serde(default)]
    eras: serde_json::Value,
    #[serde(default)]
    capitals: serde_json::Value,
}

#[derive(serde::Deserialize, Default)]
struct PeekFind {
    #[serde(default)]
    hay: serde_json::Value,
    #[serde(default)]
    cells: HashMap<String, serde_json::Value>,
}

impl Peek {
    /// 본문을 읽는다. 쓸 열쇠가 하나도 없는 기록(글자에 그 열쇠 이름이 없는 것)은 풀지 않고, 깨진 본문은 빈 값으로 둔다.
    fn read(json: &str) -> Self {
        if !["\"x_find\"", "\"description\"", "\"eras\"", "\"capitals\""].iter().any(|key| json.contains(key)) {
            return Self::default();
        }
        serde_json::from_str(json).unwrap_or_default()
    }
}

/// 한 기록의 찾을 글 재료(소문자로 바꾸기 전 그대로).
#[derive(Default)]
struct Found {
    hay: Option<String>,
    cells: HashMap<String, String>,
    description: Option<String>,
}

impl Found {
    fn of(peek: &Peek) -> Option<Self> {
        let found = Self {
            hay: peek.x_find.hay.as_str().map(str::to_owned),
            cells: peek.x_find.cells.iter().filter_map(|(k, v)| v.as_str().map(|t| (k.clone(), t.to_owned()))).collect(),
            description: peek.description.as_str().map(str::to_owned),
        };
        (found.hay.is_some() || !found.cells.is_empty() || found.description.is_some()).then_some(found)
    }
}

/// 날짜 칸(연호 · 도읍 · 배도)의 주인 후보 — (칸 참조, 이름, 맞은 칸의 차례 0 name · 1 as · 2 city · 3 label · 4 group).
/// 연호는 `era:<순번>`의 `name`, 도읍은 `capital:<순번>`의 다섯 칸(글이고 비지 않은 것만).
fn axis_candidates(peek: &Peek) -> Vec<(String, String, i64)> {
    let mut out = Vec::new();
    if let Some(eras) = peek.eras.as_array() {
        for (at, era) in eras.iter().enumerate() {
            if let Some(name) = era.get("name").and_then(serde_json::Value::as_str) {
                out.push((format!("era:{at}"), name.to_owned(), 0));
            }
        }
    }
    if let Some(capitals) = peek.capitals.as_array() {
        for (at, capital) in capitals.iter().enumerate() {
            for (prio, field) in ["name", "as", "city", "label", "group"].iter().enumerate() {
                if let Some(name) = capital.get(*field).and_then(serde_json::Value::as_str).filter(|n| !n.is_empty()) {
                    out.push((format!("capital:{at}"), name.to_owned(), prio as i64));
                }
            }
        }
    }
    out
}

/// 넣기 동안 모아 두는 것 — 이름 표 · 사건 덧줄을 펼 때 항목 기록 표를 다시 읽지 않게.
/// 이미 있는 저장소에서 이름 표를 다시 펼 때는 항목 기록 표에서 다시 모은다([`Gathered::from_store`] · [`rebuild_names`]).
#[derive(Default)]
struct Gathered {
    /// 가문 · 단체 · 제도 기록의 uid — 넣은 차례 그대로(이름 표가 이 차례로 답한다 · [`ORDERED_KINDS`]).
    ordered: Vec<String>,
    /// uid → 찾을 글 재료(있는 기록만). 같은 uid를 다시 넣으면 뒤엣것이 이긴다(항목 기록의 INSERT OR REPLACE와 같게).
    found: HashMap<String, Found>,
    /// uid → (기록의 `track`, 날짜 칸 주인 후보). 후보가 있는 기록만.
    owners: HashMap<String, (String, Vec<(String, String, i64)>)>,
    /// 이름(uid)이 있는 사건의 (번호, uid) — 사건의 덧줄을 펼 때 쓴다(본문 색인을 만들 때만 모은다).
    events: Vec<(i64, String)>,
}

impl Gathered {
    /// 저장소의 항목 기록에서 다시 모은다(계획 P4 과제 6) — 넣은 차례(`entities.ord` — [`EntityOrder`]의 규칙)대로(같으면 uid 차례).
    /// 표에는 uid마다 한 줄(뒤엣것)뿐이라 넣는 동안 모은 것(같은 uid는 뒤엣것의 찾을 글 · 처음 것의 가문 · 단체 · 제도 차례)과 같다.
    /// 사건(`events`)은 모으지 않는다 — 덧줄은 [`respread_event_hay`]가 사건마다 저장소의 기록으로 적는다.
    /// 넣은 차례 열이 없는 옛 저장소는 uid 차례다(`patch::apply`는 그 열을 먼저 만든다).
    fn from_store(db: &Connection) -> Result<Self> {
        let ord = db.prepare("SELECT 1 FROM pragma_table_info('entities') WHERE name='ord'")?.exists([])?;
        let mut got = Self::default();
        let mut stmt = db.prepare(&format!("SELECT uid,kind,json FROM entities ORDER BY {}", if ord { "ord,uid" } else { "uid" }))?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            let (uid, kind, json): (String, String, String) = (r.get(0)?, r.get(1)?, r.get(2)?);
            if ORDERED_KINDS.contains(&kind.as_str()) {
                got.ordered.push(uid.clone());
            }
            let peek = Peek::read(&json);
            if let Some(found) = Found::of(&peek) {
                got.found.insert(uid.clone(), found);
            }
            let candidates = axis_candidates(&peek);
            if !candidates.is_empty() {
                got.owners.insert(uid, (peek.track.as_str().unwrap_or("").to_owned(), candidates));
            }
        }
        Ok(got)
    }
}

/// 항목 기록의 넣은 차례(`entities.ord`)를 정하는 규칙(계획 P4 과제 6 얹힌 몫 1) — 같은 uid가 여러 번 들어오면 **처음 것**의 차례를 쓴다
/// (가문 · 단체 · 제도로 넣은 것이 있으면 그 가운데 처음 것). 짓기의 이름 표([`build_names`])가 가문 · 단체 · 제도를 처음 본 차례로 내므로,
/// 저장소의 차례로 다시 펴도([`rebuild_names`]) 같은 차례가 나온다. 본문 · 갈래 · 자료집은 뒤엣것이다(INSERT OR REPLACE).
/// 짓기([`Builder::entity_at`])와 `patch::apply`의 "entities"가 함께 쓴다. Node 내보내기는 겹친 uid를 거절하므로(`export/entities.mjs`)
/// 손으로 만든 배치에서만 생기는 경우다.
#[derive(Default)]
pub(crate) struct EntityOrder(HashMap<String, (i64, bool)>);

impl EntityOrder {
    /// `at`(배치에서의 자리)에 든 기록의 넣은 차례.
    pub(crate) fn place(&mut self, uid: &str, kind: &str, at: i64) -> i64 {
        let ordered = ORDERED_KINDS.contains(&kind);
        match self.0.get_mut(uid) {
            Some(slot) => {
                if ordered && !slot.1 {
                    *slot = (at, true);
                }
                slot.0
            }
            None => {
                self.0.insert(uid.to_owned(), (at, ordered));
                at
            }
        }
    }
}

/// SQL 값 → 글(글이 아니면 없음).
fn sql_text(v: rusqlite::types::Value) -> Option<String> {
    match v {
        rusqlite::types::Value::Text(s) => Some(s),
        _ => None,
    }
}

/// SQL 값 → 정수(소수는 반올림 · 그 밖은 없음).
fn sql_int(v: rusqlite::types::Value) -> Option<i64> {
    match v {
        rusqlite::types::Value::Integer(n) => Some(n),
        rusqlite::types::Value::Real(f) if f.is_finite() && f.abs() < 9.0e18 => Some(f.round() as i64),
        _ => None,
    }
}

/// 이름 검색이 훑는 표(`names`)를 넣기가 끝난 자료에서 한 번에 편다(계약 2절 · 스키마 1절).
/// 사건은 본문 색인(`search`)이 맡으므로 여기에 넣지 않는다. 색인을 만든 뒤에 부른다.
/// `got`은 넣는 동안 모아 둔 것이다(가문 · 단체 · 제도의 넣은 차례 · 찾을 글 재료 · 날짜 칸 주인 후보).
/// 넣는 SQL마다 차례(번호 · uid)를 밝혀 둔다 — 통계(ANALYZE)가 있는 저장소에서는 SQLite가 다른 색인(`cells_period` …)을 타 넣는 차례가 바뀌므로,
/// 이미 있는 저장소에서 다시 펴도([`rebuild_names`]) 짓기와 같은 번호 차례가 나오게(계획 P4 과제 6). 짓기의 차례는 예전과 같다(표 차례 그대로 훑었다).
fn build_names(db: &Connection, got: &Gathered) -> Result<i64> {
    let allowed = NAME_KINDS.iter().map(|k| format!("'{k}'")).collect::<Vec<_>>().join(",");
    db.execute_batch(&format!(
        "-- 1) 띠. 항목 기록이 있으면 그 종류(정권 · 기관 · 문화 …)로, 없으면 period로 적는다.
         INSERT INTO names(pack,kind,uid,name,sub,cell,start,end,row,color)
           SELECT p.pack,COALESCE(e.kind,'period'),p.uid,p.name,'',NULL,p.start,p.end,p.row,p.color
             FROM periods p LEFT JOIN entities e ON e.uid=p.uid AND p.uid<>'' WHERE p.name<>'' ORDER BY p.id;
         -- 2) 띠가 아닌 항목 기록(인물 · 왕조 · 기관 · 시대 구분 · 대범위 · 하위 문서). 넣는 갈래는 허용 목록이다(NAME_KINDS).
         --    문서 기록(kind 'doc')은 **하위 문서만** 찾는다 — 지금 연표가 그렇다. 항목의 본 문서(`$.sub`가 빈 글)는 빼고
         --    하위 문서(곁글이 있는 것)만 싣는다.
         --    곁글은 기록이 찾을 글에 실어 준 `x_find.sub`(글일 때만 — 계보 전용 인물의 '계보 전용 · ○○파', D1 확정 설계 8-1)이고, 없으면 빈 글이다.
         --    이름 미상의 계보 전용 인물(본문 `lineageOnly: true` + 이름이 UNKNOWN_WHO 꼴)은 넣지 않는다(설계 2-4 다).
         --    두 규칙 모두 그 칸이 없는 옛 배치에서는 아무것도 바꾸지 않는다.
         INSERT INTO names(pack,kind,uid,name,sub,cell,start,end,row,color)
           SELECT en.pack,en.kind,en.uid,COALESCE(json_extract(en.json,'$.name'),json_extract(en.json,'$.title')),
                  CASE WHEN json_type(en.json,'$.x_find.sub')='text' THEN json_extract(en.json,'$.x_find.sub') ELSE '' END,NULL,NULL,NULL,-1,0
             FROM entities en WHERE en.kind IN ({allowed})
               AND COALESCE(json_extract(en.json,'$.name'),json_extract(en.json,'$.title'),'')<>''
               AND NOT (en.kind='doc' AND COALESCE(json_extract(en.json,'$.sub'),'')='')
               AND NOT (en.kind='figure' AND COALESCE(json_type(en.json,'$.lineageOnly'),'')='true'
                        AND lower(trim(COALESCE(json_extract(en.json,'$.name'),''),{blank})) IN ({unknown}))
               AND NOT EXISTS(SELECT 1 FROM periods p WHERE p.uid=en.uid) ORDER BY en.uid;",
        blank = UNKNOWN_TRIM,
        unknown = UNKNOWN_WHO.iter().map(|k| format!("'{k}'")).collect::<Vec<_>>().join(",")
    ))?;
    // 2-나) 가문 · 단체 · 제도 — 넣은 차례 그대로(이름 표의 번호 차례가 곧 답의 차례다 — 계약 2-1).
    //   가문은 2)와 같은 값(곁글 '' · 줄 없음)이다. 단체 · 제도는 찾을 글 `x_find`의 곁글 · 기간 · 색을 싣고,
    //   줄은 `x_find.row`가 가리키는 정권의 첫 띠 줄을 빌린다(못 찾으면 줄 없음) — 그 트랙을 끄면 숨는다.
    {
        let mut get = db.prepare(
            "SELECT en.pack,en.kind,COALESCE(json_extract(en.json,'$.name'),json_extract(en.json,'$.title'),''),
                    json_extract(en.json,'$.x_find.sub'),json_extract(en.json,'$.x_find.span[0]'),json_extract(en.json,'$.x_find.span[1]'),
                    COALESCE(json_extract(en.json,'$.x_find.color'),json_extract(en.json,'$.color')),json_extract(en.json,'$.x_find.row')
               FROM entities en WHERE en.uid=?1 AND json_valid(en.json) AND NOT EXISTS(SELECT 1 FROM periods p WHERE p.uid=en.uid)",
        )?;
        let mut band = db.prepare("SELECT row,color FROM periods WHERE uid=?1 AND uid<>'' ORDER BY id LIMIT 1")?;
        let mut add = db.prepare("INSERT INTO names(pack,kind,uid,name,sub,cell,start,end,row,color) VALUES(?1,?2,?3,?4,?5,NULL,?6,?7,?8,?9)")?;
        let mut seen = std::collections::HashSet::new();
        for uid in &got.ordered {
            if !seen.insert(uid.as_str()) {
                continue;
            }
            // 미리 푼 값의 꼴이 어긋나도(수 자리에 글 · 소수 …) 넣기를 멈추지 않는다 — 읽을 수 있는 것만 쓴다.
            let found = get.query_row([uid], |r| {
                Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, sql_text(r.get(2)?).unwrap_or_default(), sql_text(r.get(3)?),
                    sql_int(r.get(4)?), sql_int(r.get(5)?), r.get::<_, rusqlite::types::Value>(6)?, sql_text(r.get(7)?)))
            });
            let (pack, kind, name, sub, start, end, color, host) = match found {
                Ok(v) => v,
                Err(rusqlite::Error::QueryReturnedNoRows) => continue,
                Err(e) => return Err(e.into()),
            };
            if name.is_empty() || !ORDERED_KINDS.contains(&kind.as_str()) {
                continue;
            }
            if kind == "house" {
                add.execute(params![pack, kind, uid, name, "", Option::<i64>::None, Option::<i64>::None, -1, 0])?;
                continue;
            }
            let (row, host_color) = match host.as_deref() {
                Some(polity) if !polity.is_empty() => band.query_row([polity], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?))).unwrap_or((-1, 0)),
                _ => (-1, 0),
            };
            let color = match color {
                rusqlite::types::Value::Integer(n) => n,
                rusqlite::types::Value::Text(css) if !css.trim().is_empty() => crate::query::css_color(&css),
                _ => host_color,
            };
            let sub = sub.filter(|s| !s.is_empty()).unwrap_or_else(|| if kind == "group" { "단체" } else { "제도" }.to_owned());
            // 기간은 한쪽만 있어도 받되, 뒤집혔으면 둘 다 버린다(때 글이 '미정'이 된다).
            let (start, end) = match (start, end) {
                (Some(a), Some(b)) if a > b => (None, None),
                (Some(a), None) => (Some(a), Some(a)),
                (None, Some(b)) => (Some(b), Some(b)),
                other => other,
            };
            add.execute(params![pack, kind, uid, name, sub, start, end, row, color])?;
        }
    }
    db.execute_batch(
        "-- 3) 띠 안의 지도자 · 내각 · 시기 구분 · 지위 칸(상세 창이 여는 넷). 칸 참조(`leader:3`)의 번호는
         --    내보내기가 **style의 15~26비트**에 실어 준 순번이다(계약 6-2의 '`style`에 함께 싣는 값').
         --    시기 칸의 이름에는 체계 이름이 탭으로 붙어 올 수 있어(style 32비트) 탭 뒤만 싣는다.
         INSERT INTO names(pack,kind,uid,name,sub,cell,start,end,row,color,cell_ref)
           SELECT p.pack,'cell',p.uid,
                  CASE WHEN (c.style&32)<>0 AND instr(c.name,char(9))>0 THEN substr(c.name,instr(c.name,char(9))+1) ELSE c.name END,
                  p.name||' '||(CASE c.kind WHEN 1 THEN '지도자' WHEN 2 THEN '내각' WHEN 4 THEN '시기 구분' ELSE '지위' END),
                  c.kind,c.start,c.end,p.row,
                  CASE WHEN c.color<>0 THEN c.color ELSE p.color END,
                  CASE WHEN ((c.style>>15)&4095)>0
                       THEN (CASE c.kind WHEN 1 THEN 'leader:' WHEN 2 THEN 'cabinet:' WHEN 4 THEN 'phase:' ELSE 'rank:' END)||(((c.style>>15)&4095)-1)
                       ELSE '' END
             FROM cells c JOIN periods p ON p.id=c.period WHERE c.kind IN (1,2,4,5) AND c.name<>'' ORDER BY c.id;",
    )?;
    // 4) 날짜 칸의 연호 · 도읍 · 배도(칸 번호는 100 + 날짜 칸 종류). 제 줄이 없으므로 row는 -1이다.
    //    칸 참조는 연호가 `era:<seq>`, 도읍 · 배도가 `capital:<seq>`다(계약 6-3).
    // 4-가) 날짜 칸(연호 · 도읍)의 주인 정권 — 내보내기가 axis에 uid를 싣지 않아 넣을 때 찾는다.
    //   항목 기록의 `eras` · `capitals` 목록을 펴서 **같은 순번의 같은 이름**을 후보로 둔다(칸 참조와 같은 번호라 어긋나지 않는다).
    //   칸에 적히는 이름은 자료에 따라 `name` · `as` · `city` · `label` 가운데 하나라 넷을 모두 후보로 두되(prio 0~3),
    //   배도 칸은 묶음 이름(`group` — 지금 연표의 배도 묶음 · 칸 참조는 그 묶음의 첫 도읍 순번)이라 그것도 후보다(prio 4).
    //   후보가 여럿이면(같은 도시를 같은 이름으로 쓴 두 정권 — 형식 3의 지명 사전이 권한다) 이 차례로 가린다:
    //     ① 칸의 트랙 = 기록의 `track`(트랙의 글자 id를 아는 배치에서만) ② 그 정권의 띠가 칸의 기간과 겹침
    //     ③ `name`으로 맞은 것 → `as` → `city` → `label` → `group` ④ uid 차례.
    //   (후보는 넣을 때 [`Builder::entity`]가 본문을 한 번 읽어 모아 둔 것이다 — 여기서 항목 기록의 JSON을 다시 풀지 않는다.)
    //   예전에는 후보 가운데 아무것이나 골라, 다른 정권의 `city`가 같은 도읍 칸이 그 정권에 붙었다(설계 A 2-2의 결함 4).
    //   못 찾은 칸은 빈 uid 그대로다(상세 창을 열 곳이 없다 — 그 칸은 날아가기만 한다).
    db.execute_batch("CREATE TEMP TABLE axis_owner(ref TEXT NOT NULL,name TEXT NOT NULL,uid TEXT NOT NULL,prio INTEGER NOT NULL,track TEXT NOT NULL);")?;
    {
        let mut add = db.prepare("INSERT INTO axis_owner(ref,name,uid,prio,track) VALUES(?1,?2,?3,?4,?5)")?;
        let mut uids: Vec<&String> = got.owners.keys().collect();
        uids.sort();
        for uid in uids {
            let (track, list) = &got.owners[uid];
            for (reference, name, prio) in list {
                add.execute(params![reference, name, uid, prio, track])?;
            }
        }
    }
    db.execute_batch(
        "CREATE INDEX temp.axis_owner_ref ON axis_owner(ref,name);
         CREATE INDEX temp.axis_owner_name ON axis_owner(name);
         -- 1차: 같은 칸 참조 + 같은 이름. 여럿이면 트랙 → 기간 → 맞은 칸 → uid 차례로 하나.
         --   (SQLite는 하위 조회의 ORDER BY에서 바깥 열을 읽지 못해, 가리는 차례를 '트랙 · 기간 · 맞은 칸 | uid' 글로 엮어 min()으로 고른다)
         INSERT INTO names(pack,kind,uid,name,sub,cell,start,end,row,color,cell_ref)
           SELECT a.pack,'cell',
                  COALESCE((SELECT substr(min((CASE WHEN COALESCE(t.key,'')<>'' AND o.track=t.key THEN 0 ELSE 1 END)
                                              ||(CASE WHEN EXISTS(SELECT 1 FROM periods p WHERE p.uid=o.uid AND p.start<=a.end AND p.end>=a.start) THEN 0 ELSE 1 END)
                                              ||o.prio||'|'||o.uid),5)
                              FROM axis_owner o
                             WHERE o.ref=(CASE a.kind WHEN 2 THEN 'era:' ELSE 'capital:' END)||a.seq AND o.name=a.name),''),
                  a.name,COALESCE(t.name||' ','')||(CASE a.kind WHEN 2 THEN '연호' WHEN 3 THEN '도읍' ELSE '배도' END),
                  100+a.kind,a.start,a.end,-1,a.color,(CASE a.kind WHEN 2 THEN 'era:' ELSE 'capital:' END)||a.seq
             FROM axis_cells a LEFT JOIN tracks t ON t.id=a.track WHERE a.kind IN (2,3,4) AND a.name<>'' ORDER BY a.id;
         -- 2차: 순번이 어긋난 칸(배도처럼 다른 셈의 번호를 쓰는 것)은 **이름이 온 자료에서 하나뿐일 때만** 주인을 정한다.
         UPDATE names SET uid=COALESCE((SELECT max(o.uid) FROM axis_owner o WHERE o.name=names.name AND o.ref LIKE 'capital:%'
                                         HAVING count(DISTINCT o.uid)=1),names.uid)
          WHERE names.kind='cell' AND names.uid='' AND names.cell_ref LIKE 'capital:%';
         DROP TABLE axis_owner;",
    )?;
    // 5) 제 줄이 없는 항목 기록에 자리를 빌려준다 — 인물은 활동 막대(구역 37)의 uid로, 왕조 · 기관 · 시대 구분 · 대범위는
    //    같은 이름의 칸 · 묶음으로. 검색 결과에서 바로 그 자리로 날아갈 수 있게 하려는 것이고, 못 찾으면 그대로 둔다.
    //    여럿이면 **자리**(밖으로 보이는 줄 — `RowMap`)가 가장 앞인 줄을 빌린다. 새로 지은 저장소는 열쇠 = 자리라 예전(가장 작은 줄 번호)과 같고,
    //    트랙을 고쳐 쓴 저장소(열쇠 ≠ 자리 — 계획 P4)에서 다시 펴도(`rebuild_names`) 통째 짓기와 같은 줄을 고른다(과제 6).
    //    `row_pos`와 맞물리지 않는 줄은 버린다 — 띠 · 사건 · 항목의 줄은 외래 열쇠(`rows`)라 늘 맞물리고, 외래 열쇠가 없는 `groups.first_row`도
    //    짓기가 그 트랙의 줄로 적는다(`fill_into` · `rekey_track`이 함께 옮긴다). 맞물리지 않는 first_row는 없는 줄을 가리키므로 빌려도 갈 곳이 없다.
    let homeless: i64 = db.query_row("SELECT count(*) FROM names WHERE row<0", [], |r| r.get(0))?;
    if homeless > 0 {
        db.execute_batch("CREATE TEMP TABLE row_pos(id INTEGER PRIMARY KEY,pos INTEGER NOT NULL UNIQUE);")?;
        {
            let map = crate::rowmap::RowMap::load(db)?;
            let mut add = db.prepare("INSERT INTO row_pos(id,pos) VALUES(?1,?2)")?;
            for b in map.blocks() {
                for i in 0..b.n {
                    add.execute([b.key0 + i, b.pos0 + i])?;
                }
            }
        }
        db.execute_batch(
            "CREATE TEMP TABLE borrowed AS
               SELECT substr(i.text2,1,instr(i.text2,'|')-1) AS uid,min(w.pos) AS pos,min(i.start) AS start,max(i.end) AS end,min(i.color) AS color
                 FROM items i JOIN row_pos w ON w.id=i.row WHERE i.section=37 AND instr(i.text2,'|')>1 GROUP BY 1;
             INSERT INTO borrowed
               SELECT n.uid,min(w.pos),min(c.start),max(c.end),min(CASE WHEN c.color<>0 THEN c.color ELSE p.color END)
                 FROM names n JOIN cells c ON c.name=n.name JOIN periods p ON p.id=c.period JOIN row_pos w ON w.id=p.row
                WHERE n.row<0 AND ((n.kind='dynasty' AND c.kind=0) OR (n.kind='organ' AND c.kind=3)) GROUP BY n.uid;
             -- 시대 구분은 공통 줄이라 줄 번호를 빌리지 않는다(기간과 색만).
             INSERT INTO borrowed
               SELECT n.uid,NULL,min(a.start),max(a.end),min(a.color) FROM names n JOIN axis_cells a ON a.name=n.name
                WHERE n.row<0 AND n.kind='epoch' AND a.kind=1 GROUP BY n.uid;
             INSERT INTO borrowed
               SELECT n.uid,min(w.pos),NULL,NULL,min(g.color) FROM names n JOIN groups g ON g.name=n.name JOIN row_pos w ON w.id=g.first_row
                WHERE n.row<0 AND n.kind='scope' AND g.kind=2 GROUP BY n.uid;
             CREATE INDEX temp.borrowed_uid ON borrowed(uid);
             UPDATE names SET
               row=COALESCE((SELECT (SELECT w.id FROM row_pos w WHERE w.pos=b.pos) FROM borrowed b WHERE b.uid=names.uid),names.row),
               start=COALESCE((SELECT b.start FROM borrowed b WHERE b.uid=names.uid),names.start),
               end=COALESCE((SELECT b.end FROM borrowed b WHERE b.uid=names.uid),names.end),
               color=COALESCE((SELECT b.color FROM borrowed b WHERE b.uid=names.uid),names.color)
             WHERE names.row<0 AND EXISTS(SELECT 1 FROM borrowed b WHERE b.uid=names.uid);
             DROP TABLE borrowed;
             DROP TABLE row_pos;",
        )?;
    }
    // 6) 찾을 글(`hay`). 기록 줄은 그 기록의 `x_find.hay` + 설명, 띠 안 칸 · 날짜 칸 줄은 주인 기록의 `x_find.cells[칸 참조]`
    //    (도읍 칸이면 내보내기가 지명의 원어까지 담아 준다). 내보내기가 `x_find`를 싣지 않은 배치에서는 설명만 남는다.
    //    소문자는 여기서 유니코드로 맞춘다(hay_text). 기록 본문은 uid마다 한 번만 푼다(한 정권에 칸이 많다).
    {
        let mut read = db.prepare("SELECT id,kind,name,uid,cell_ref FROM names ORDER BY id")?;
        // 훑는 동안 같은 표를 고치지 않도록 다 모은 뒤에 적는다.
        let mut filled: Vec<(i64, String)> = Vec::new();
        let mut rows = read.query([])?;
        while let Some(r) = rows.next()? {
            let (id, kind, name, uid, cell_ref): (i64, String, String, String, String) = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?);
            let rec = if uid.is_empty() { None } else { got.found.get(&uid) };
            let found = rec.and_then(|f| if kind == "cell" { f.cells.get(&cell_ref).map(String::as_str) } else { f.hay.as_deref() });
            let description = if hay_takes_description(&kind) { rec.and_then(|f| f.description.as_deref()) } else { None };
            let hay = hay_text(&[found, description], &name);
            if !hay.is_empty() {
                filled.push((id, hay));
            }
        }
        drop(rows);
        let mut write = db.prepare("UPDATE names SET hay=?2 WHERE id=?1")?;
        for (id, hay) in filled {
            write.execute(params![id, hay])?;
        }
    }
    Ok(db.query_row("SELECT count(*) FROM names", [], |r| r.get(0))?)
}

/// 사건의 다른 이름(원어 · 옛 이름 · 로마자 · 장소 · 태그 · 트랙 이름 …)을 본문 색인에 **덧줄**로 더한다(계약 2-1).
/// 덧줄의 rowid는 −(사건 번호)이고 낱자는 그 사건 기록의 `x_find.hay`다. 공동 사건의 둘째 자리(`uid#1`)처럼 제 기록이 없는
/// 사건은 밑동(`#` 앞)의 기록을 쓴다. 사건 표 · 본문 색인의 모양은 그대로다 — `kinds`가 없는 옛 모양 검색은 사건 번호(양수)로만
/// 잇기 때문에 덧줄을 보지 않는다. 같은 글(소문자)을 `event_hay`에도 적어 두어, 넓힌 검색이 후보를 확인할 때
/// 항목 기록의 큰 JSON을 꺼내지 않게 한다. 덧줄 수를 돌려준다.
fn add_event_hay(db: &Connection, got: &Gathered) -> Result<i64> {
    let mut added = 0;
    for (id, uid) in &got.events {
        let hay = event_hay(uid, |u| Ok(got.found.get(u).map(|f| f.hay.clone())))?;
        if put_hay(db, *id, hay)? {
            added += 1;
        }
    }
    Ok(added)
}

/// 사건 하나의 덧줄 — 짓기([`add_event_hay`])와 이미 있는 저장소의 다시 적기([`respread_event_hay`])가 함께 쓰는 규칙(과제 6 고침).
/// 제 기록에 찾을 글 재료(`Found`)가 있으면 그 기록의 `x_find.hay`(없으면 덧줄 없음 — 밑동으로 가지 않는다), 재료가 없으면 밑동(`uid#1`의 `uid`)
/// 기록의 것 — `entity` · `entities`의 밑동 되짚기와 같은 차례. 글은 소문자로. `hay_of(uid)`는 그 uid 기록에 재료가 있으면 `Some(그 hay)`, 없으면 None.
fn event_hay(uid: &str, mut hay_of: impl FnMut(&str) -> Result<Option<Option<String>>>) -> Result<Option<String>> {
    let hay = match hay_of(uid)? {
        Some(own) => own,
        None => match crate::query::uid_stem(uid) {
            Some(stem) => hay_of(stem)?.flatten(),
            None => None,
        },
    };
    Ok(hay.map(|h| h.to_lowercase()))
}

/// 덧줄 하나를 적는다 — 본문 색인의 덧줄(rowid −번호 · 글의 `grams`)과 `event_hay`(같은 글 — 지울 때 이 글의 낱자로 지운다). 낱자가 없으면 적지 않고 거짓.
fn put_hay(db: &Connection, id: i64, hay: Option<String>) -> Result<bool> {
    let Some(hay) = hay else { return Ok(false) };
    let terms = grams(&hay);
    if terms.is_empty() {
        return Ok(false);
    }
    db.prepare_cached("INSERT INTO search(rowid,terms) VALUES(?1,?2)")?.execute(params![-id, terms.join(" ")])?;
    db.prepare_cached("INSERT INTO event_hay(id,hay) VALUES(?1,?2)")?.execute(params![id, hay])?;
    Ok(true)
}

/// 저장소에 든 그 기록의 찾을 글 재료(기록이 없거나 쓸 것이 없으면 None) — 넣을 때 [`Builder::entity_at`]이 모으는 것과 같은 풀이(`Peek` · `Found`).
fn stored_found(db: &Connection, uid: &str) -> Result<Option<Found>> {
    let json: Option<String> = db.prepare_cached("SELECT json FROM entities WHERE uid=?1")?.query_row([uid], |r| r.get(0)).optional()?;
    Ok(json.and_then(|json| Found::of(&Peek::read(&json))))
}

/// 사건들의 덧줄(다른 이름 — [`add_event_hay`])을 **저장소의 항목 기록**으로 다시 적는다(계획 P4 과제 6 — `patch::apply`의 "names").
/// 사건마다 있던 덧줄은 넣을 때와 같은 낱자로 지우고(contentless 본문 색인은 넣은 낱자와 똑같아야 지워진다 — `event_hay.hay`가 그 글이다),
/// 짓기와 같은 규칙([`event_hay`] · [`put_hay`])으로 다시 넣는다 — 기록은 넣는 동안 모은 것이 아니라 저장소의 것을 읽는다.
/// 같은 사건을 다시 불러도 결과가 같다(이번에 넣은 사건 · 기록이 바뀐 사건을 함께 넘겨도 된다). 다시 쓰지 않은 트랙의 사건도 그 기록이 바뀌면
/// 넘긴다(얹힌 몫 4 — 기록이 다른 트랙 쪽인 공동 사건 `uid#1`도 맞다).
/// 본문 색인이 꺼진 저장소(`meta.search` 'off')는 덧줄이 없어 아무것도 하지 않는다. 넣은 덧줄 수를 돌려준다.
pub(crate) fn respread_event_hay(db: &Connection, events: &BTreeMap<i64, String>) -> Result<i64> {
    let search: Option<String> = db.query_row("SELECT value FROM meta WHERE key='search'", [], |r| r.get(0)).optional()?;
    if events.is_empty() || search.as_deref() == Some("off") {
        return Ok(0);
    }
    let mut old = db.prepare("SELECT hay FROM event_hay WHERE id=?1")?;
    let mut forget = db.prepare("INSERT INTO search(search,rowid,terms) VALUES('delete',?1,?2)")?;
    let mut drop_old = db.prepare("DELETE FROM event_hay WHERE id=?1")?;
    let mut added = 0;
    for (id, uid) in events {
        if let Some(text) = old.query_row([id], |r| r.get::<_, String>(0)).optional()? {
            let terms = grams(&text);
            if !terms.is_empty() {
                forget.execute(params![-id, terms.join(" ")])?;
            }
            drop_old.execute([id])?;
        }
        let hay = event_hay(uid, |u| Ok(stored_found(db, u)?.map(|f| f.hay)))?;
        if put_hay(db, *id, hay)? {
            added += 1;
        }
    }
    Ok(added)
}

/// 이름 표(`names`) · 관점 이름(`lens_names`)을 **이미 있는 저장소에서** 통째로 다시 편다(계획 P4 과제 6 · 정한 것 #5 — `patch::apply`의 "names").
/// 넣는 동안 모으던 것(가문 · 단체 · 제도의 넣은 차례 · 찾을 글 재료 · 날짜 칸 주인 후보)을 항목 기록 표에서 넣은 차례(`entities.ord`)대로 다시 모아
/// ([`Gathered::from_store`]) 짓기와 같은 [`build_names`] · [`build_lens_names`]로 편다 — 같은 내용이면 짓기가 편 것과 같다(빌리는 줄도 자리로 고른다).
/// 부르는 쪽의 거래 안에서 쓴다. `meta.now`에 기대는 값은 없다('오늘'을 모르는 저장소도 같다). (이름 표 줄 수, 관점 이름 줄 수)를 돌려준다 —
/// `meta.names` · `meta.lens_names`는 부르는 쪽이 적는다. 사건의 덧줄은 [`respread_event_hay`](바뀐 사건만).
pub fn rebuild_names(tx: &rusqlite::Transaction) -> Result<(i64, i64)> {
    let db: &Connection = tx;
    let got = Gathered::from_store(db)?;
    db.execute_batch("DELETE FROM names; DELETE FROM lens_names;")?;
    Ok((build_names(db, &got)?, build_lens_names(db)?))
}

/// 관점(나라마다 제 이름 — 계약 2-6절)의 이름을 항목 기록에서 펴는 조회.
/// 넣을 때 한 번 펴는 `build_lens_names`와, 그 표가 없는 옛 저장소를 그때그때 훑는 `query::lens_names`가 함께 쓴다.
///
/// 지금 연표의 `perspectives`는 `[{track, title, description, source}]`이고(`js/core.js:2694` · 이름은 **`title`**),
/// 트랙은 **글자 id**(`mw-delta` — `tracks.key`와 같은 글)다. 이름을 `name`으로 적은 자료도 받아 둔다.
/// 트랙이나 이름이 빈 관점은 싣지 않는다 — 답에도 실리지 않아야 하기 때문이다.
pub const LENS_NAMES_SQL: &str = "SELECT en.uid AS uid,json_extract(j.value,'$.track') AS track,\
    COALESCE(json_extract(j.value,'$.title'),json_extract(j.value,'$.name')) AS name,en.pack AS pack \
    FROM entities en, json_each(en.json,'$.perspectives') j \
    WHERE json_valid(en.json) AND json_type(en.json,'$.perspectives')='array' \
      AND COALESCE(json_extract(j.value,'$.track'),'')<>'' \
      AND COALESCE(json_extract(j.value,'$.title'),json_extract(j.value,'$.name'),'')<>''";

/// 관점의 이름 표(`lens_names`)를 넣기가 끝난 자료에서 한 번에 편다.
/// 한 항목의 같은 트랙에 관점이 둘이면 뒤엣것이 이긴다(지금 연표의 `find`는 앞엣것을 쓰지만, 자료가 그렇게 들어오는 일이 없다).
fn build_lens_names(db: &Connection) -> Result<i64> {
    db.execute_batch(&format!("INSERT OR REPLACE INTO lens_names(uid,track,name,pack) {LENS_NAMES_SQL};"))?;
    Ok(db.query_row("SELECT count(*) FROM lens_names", [], |r| r.get(0))?)
}

/// 덮는 색인(`events_time`)을 지우고 사건 표에 있는 열로 다시 짓는다 — [`reindex`]와 옛 저장소의 첫 `patch::apply`(얹힌 몫 11)가 쓴다.
/// 변형을 넣기 전에 만든 저장소(가상 100만 건 v3-1m · v3b-1m)의 사건 표에는 variant 열이 없다 — 그런 저장소에는 변형 조건도 붙지 않으므로
/// (`Store::has_variants` 거짓) 그 열만 빼고 만든다. 트랙 안 사건 차례(ord — 판정 R23)를 더하기 전에 만든 저장소에도 그 열이 없다 — 마찬가지.
pub(crate) fn rebuild_events_time(db: &Connection) -> Result<()> {
    let has = |column: &str| -> Result<bool> { Ok(db.prepare("SELECT 1 FROM pragma_table_info('events') WHERE name=?1")?.exists([column])?) };
    let mut sql = EVENTS_TIME_INDEX_SQL.to_owned();
    for column in ["variant", "ord"] {
        if !has(column)? {
            sql = sql.replace(&format!(",{column},"), ",").replace(&format!(",{column})"), ")");
        }
    }
    db.execute_batch("DROP INDEX IF EXISTS events_time")?;
    db.execute_batch(&sql)?;
    Ok(())
}

/// 이미 만든 저장소의 덮는 색인만 다시 만든다(색인의 모양이 바뀌었을 때 — 자료를 다시 생성하지 않아도 된다).
pub fn reindex(path: &Path) -> Result<()> {
    let db = Connection::open(path)?;
    rebuild_events_time(&db)?;
    db.execute_batch("ANALYZE")?;
    let integrity: String = db.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
    if integrity != "ok" {
        return Err(integrity.into());
    }
    Ok(())
}

/// 넣는 연결 — 새 저장소를 지을 때는 품고([`Builder::create`]), 이미 있는 저장소에 덧붙일 때는 부르는 쪽의 거래를 빌린다([`Builder::append`]).
enum Db<'a> {
    Own(Connection),
    Tx(&'a Connection),
}

impl std::ops::Deref for Db<'_> {
    type Target = Connection;
    fn deref(&self) -> &Connection {
        match self {
            Db::Own(db) => db,
            Db::Tx(db) => db,
        }
    }
}

/// 덧붙이기([`Builder::append`])가 넣은 것 — [`Builder::finish_append`]가 돌려준다. `patch::apply`가 메타의 수 세기 ·
/// 자료집별 수 · 보는 범위를 이것으로 더한다(1,000만에서 `count(*)`를 피함). 수는 모두 **이번에 넣은 것**만이다.
#[derive(Debug, Default)]
pub struct Appended {
    pub tracks: i64,
    pub rows: i64,
    pub periods: i64,
    pub cells: i64,
    pub events: i64,
    /// 날짜 없는 사건.
    pub unknown: i64,
    pub groups: i64,
    pub axis_cells: i64,
    pub items: i64,
    /// `entity`를 부른 수(같은 uid를 바꿔 적은 것도 센다 — 표의 줄 수는 부르는 쪽이 다시 센다).
    pub entities: i64,
    pub row_labels: i64,
    pub variants: i64,
    pub variant_rows: i64,
    pub variant_moves: i64,
    /// 자료집 번호 → 이번에 넣은 사건 · 띠 수, 이번에 넣은 띠 · 사건이 놓인 트랙.
    pub pack_events: BTreeMap<i64, i64>,
    pub pack_periods: BTreeMap<i64, i64>,
    pub pack_tracks: BTreeMap<i64, std::collections::BTreeSet<i64>>,
    /// 이번에 넣은 것이 덮는 범위(분). 아무것도 넓히지 않았으면 None.
    pub span: Option<(i64, i64)>,
    /// 이번에 넣은 이름(uid) 있는 사건의 (번호, uid) — 본문 색인이 켜진 저장소에서만 모은다. 그 덧줄(다른 이름)은 부르는 쪽(`patch::apply`의
    /// "names")이 항목 기록을 모두 맞춘 뒤 저장소의 기록으로 적는다([`respread_event_hay`] — 계획 P4 과제 6).
    pub named: Vec<(i64, String)>,
}

/// 저장소의 가장 큰 번호(없으면 줄은 −1 · 나머지는 0) — 덧붙이기([`Builder::append_after`])가 새 번호를 이 다음부터 준다.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Floors {
    pub rows: i64,
    pub periods: i64,
    pub events: i64,
    pub variants: i64,
}

impl Floors {
    pub fn read(db: &Connection) -> Result<Self> {
        let max = |sql: &str| -> Result<i64> { Ok(db.query_row(sql, [], |r| r.get(0))?) };
        Ok(Self {
            rows: max("SELECT COALESCE(MAX(id),-1) FROM rows")?,
            periods: max("SELECT COALESCE(MAX(id),0) FROM periods")?,
            events: max("SELECT COALESCE(MAX(id),0) FROM events")?,
            variants: max("SELECT COALESCE(MAX(id),0) FROM variants")?,
        })
    }
}

/// 번호를 밝혔으면 그것, 아니면 덧붙이기의 다음 번호(있으면 하나 올린다), 둘 다 없으면 None(SQLite가 매긴다).
fn take_id(given: Option<i64>, next: &mut Option<i64>) -> Option<i64> {
    given.or_else(|| next.as_mut().map(|n| {
        *n += 1;
        *n - 1
    }))
}

pub struct Builder<'a> {
    db: Db<'a>,
    search: bool,
    tracks: i64,
    /// 새 트랙의 `ord` 앞값 — 새 저장소는 0, 덧붙일 때는 저장소의 가장 큰 `ord` + 1(차례는 `patch::apply`의 "order"가 다시 적는다).
    track_ord0: i64,
    /// 다음 줄 열쇠. `row0`은 이 Builder가 넣는 첫 줄 열쇠 — 새 저장소는 0, 덧붙일 때는 저장소의 가장 큰 열쇠 + 1.
    /// 이 Builder가 넣는 줄은 `row0`부터 이어진다(트랙마다 이어진 덩이 — 계획 P4 정한 것 #1).
    rows: i64,
    row0: i64,
    row_ord: HashMap<i64, i64>,
    /// 이 Builder가 넣은 띠의 번호 → 줄 열쇠. 덧붙일 때는 번호가 1부터가 아니고(과제 5c부터는 옛 번호를 다시 쓰기도 한다) 셈으로 찾는다.
    period_rows: HashMap<i64, i64>,
    /// 덧붙일 때 이 Builder 밖의 줄 가운데 가리켜도 되는 열쇠 — 변형의 줄 · 이사 · 묶음이 하위 배치 밖 트랙의 줄을 가리킬 때([`Builder::outer_rows`]).
    outer_rows: std::collections::HashSet<i64>,
    /// 덧붙일 때 번호를 밝히지 않은 띠 · 사건 · 변형이 받을 다음 번호 — 지우기 전 가장 큰 번호 + 1부터([`Floors`] · 얹힌 몫 6).
    /// 새 저장소는 None(SQLite가 넣은 차례대로 매긴다).
    next_period: Option<i64>,
    next_event: Option<i64>,
    next_variant: Option<i64>,
    /// 트랙 번호 → 이 Builder가 그 트랙에 넣은 사건 수(`events.ord` = 트랙 안 차례 — 판정 R23).
    track_events: HashMap<i64, i64>,
    cells: i64,
    events: i64,
    groups: i64,
    categories: i64,
    axis_cells: i64,
    items: i64,
    entities: i64,
    row_labels: i64,
    variants: i64,
    variant_rows: i64,
    variant_moves: i64,
    /// 자료집별 사건 수 — 열 때마다 1,000만 행을 세지 않도록 메타에 적어 둔다.
    pack_events: std::collections::BTreeMap<i64, i64>,
    /// 자료집별 띠(나라 · 시대) 수와 그 자료집의 띠 · 사건이 놓인 트랙(제 트랙이 아닌 남의 트랙에 얹은 것도) — DLC 관리 카드의 '담긴 것'.
    /// 사건만 세면 나라 52개를 얹은 DLC가 "사건 0건 · 트랙 없음"으로 보인다(2026-09-22 감독의 실제 DLC).
    pack_periods: std::collections::BTreeMap<i64, i64>,
    pack_tracks: std::collections::BTreeMap<i64, std::collections::BTreeSet<i64>>,
    /// 이 Builder가 넣은 줄의 트랙 번호 — 자리 `줄 열쇠 − row0`(넣는 줄의 열쇠는 `row0`부터 차례로 난다).
    row_track: Vec<i64>,
    unknown: i64,
    min: i64,
    max: i64,
    /// PRE_MIN 단계의 (줄, 통, 자료집) → 칸. 더 성긴 단계는 finalize에서 네 칸씩 합쳐 만든다.
    summary: HashMap<(i64, i64, i64), Cell>,
    /// 넣는 동안 모아 두는 것(가문 · 단체 · 제도의 넣은 차례 · 찾을 글 재료 · 날짜 칸 주인 후보 · 이름 있는 사건).
    got: Gathered,
    /// 항목 기록의 넣은 차례 — 같은 uid를 다시 넣으면 처음 것의 차례([`EntityOrder`]).
    entity_ord: EntityOrder,
    /// 채우는 쪽(`legacy::fill_into`)이 넣는 동안 적어 둔 메타 — `finalize`가 `extra_meta` 앞에 함께 적는다(같은 열쇠는 뒤엣것).
    meta_extra: Vec<(String, String)>,
}

impl<'a> Builder<'a> {
    fn with_db(db: Db<'a>, search: bool, track_ord0: i64, row0: i64) -> Self {
        Self {
            db, search, tracks: 0, track_ord0, rows: row0, row0, row_ord: HashMap::new(), period_rows: HashMap::new(),
            outer_rows: Default::default(), next_period: None, next_event: None, next_variant: None, track_events: HashMap::new(), cells: 0, events: 0,
            groups: 0, categories: 0, axis_cells: 0, items: 0, entities: 0, row_labels: 0, variants: 0, variant_rows: 0, variant_moves: 0,
            pack_events: Default::default(), pack_periods: Default::default(), pack_tracks: Default::default(), row_track: Vec::new(), unknown: 0,
            min: i64::MAX, max: i64::MIN, summary: HashMap::new(), got: Gathered::default(), entity_ord: EntityOrder::default(), meta_extra: Vec::new(),
        }
    }

    /// 이미 있는 저장소는 덮어쓰지 않는다.
    pub fn create(path: &Path) -> Result<Self> {
        if path.exists() {
            return Err("기존 저장소는 덮어쓰지 않습니다".into());
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let db = Connection::open(path)?;
        schema::create(&db)?;
        db.execute_batch("BEGIN")?;
        Ok(Self::with_db(Db::Own(db), true, 0, 0))
    }

    /// 이미 있는 저장소에 **덧붙여** 짓는다(계획 P4 정한 것 #4 — `patch::apply`의 "insert"). 부르는 쪽의 거래(`write::write`) 안에서 쓰고,
    /// [`Builder::finish_append`]로 마친다(COMMIT · 색인 · 이름 표 · 메타는 부르는 쪽 몫).
    /// - 줄 열쇠는 저장소의 가장 큰 열쇠 + 1부터 이어서 · 트랙의 `ord`는 가장 큰 `ord` + 1부터(차례는 부르는 쪽이 다시 적는다) ·
    ///   띠 · 칸 · 사건 · 항목 · 변형의 번호는 가장 큰 번호 + 1부터(지우고 다시 넣을 때 바닥을 지우기 전 번호로 두려면 [`Builder::append_after`]).
    /// - 본문 색인(`search`)은 저장소의 `meta.search`를 따른다('off'면 넣지 않음).
    /// - 띠 · 사건 · 항목 · 줄 이름 · 묶음은 **이 Builder가 넣은 줄**에만 놓인다. 변형의 줄 · 이사 · 묶음은 [`Builder::outer_rows`]로 알린
    ///   바깥 줄도 가리킬 수 있다.
    pub fn append(tx: &'a rusqlite::Transaction) -> Result<Self> {
        let floors = Floors::read(tx)?;
        Self::append_after(tx, &floors)
    }

    /// [`Builder::append`]과 같되 새 번호를 `floors`(**지우기 전에** 읽어 둔 가장 큰 번호 — 얹힌 몫 6) 다음부터 준다: 줄 열쇠는
    /// `floors.rows + 1`부터 이어서, 번호를 밝히지 않은 띠 · 사건 · 변형은 `floors.<표> + 1`부터 차례로. 트랙을 지우고 다시 넣는
    /// `patch::apply`가 쓴다 — 지운 번호를 새 uid가 다시 받지 않게(같은 uid · 열쇠는 [`Builder::period_at`] · [`Builder::event_at`] ·
    /// [`Builder::variant_at`]에 옛 번호를 밝혀 넘긴다). 바닥이 지금 저장소의 가장 큰 번호보다 작으면 Err(번호가 부딪친다).
    pub fn append_after(tx: &'a rusqlite::Transaction, floors: &Floors) -> Result<Self> {
        let db: &'a Connection = tx;
        let now = Floors::read(db)?;
        if now.rows > floors.rows || now.periods > floors.periods || now.events > floors.events || now.variants > floors.variants {
            return Err(format!("덧붙일 번호의 바닥이 저장소의 가장 큰 번호보다 작습니다(바닥 {floors:?} · 지금 {now:?})").into());
        }
        let ord0: i64 = db.query_row("SELECT COALESCE(MAX(ord)+1,0) FROM tracks", [], |r| r.get(0))?;
        let search: Option<String> = db.query_row("SELECT value FROM meta WHERE key='search'", [], |r| r.get(0)).optional()?;
        let mut b = Self::with_db(Db::Tx(db), search.as_deref() != Some("off"), ord0, floors.rows + 1);
        b.next_period = Some(floors.periods + 1);
        b.next_event = Some(floors.events + 1);
        b.next_variant = Some(floors.variants + 1);
        Ok(b)
    }

    /// 덧붙일 때, 이 Builder 밖의 줄 가운데 변형이 가리켜도 되는 열쇠를 알린다(하위 배치 밖 트랙의 줄 — `legacy::fill_into`의 `outer_rows`).
    pub fn outer_rows(&mut self, keys: impl IntoIterator<Item = i64>) {
        self.outer_rows.extend(keys);
    }

    /// 덧붙일 때 저장소에 이미 있는 띠의 (자료집, 시작, 끝) — 하위 배치 밖 띠를 가리키는 항목 · 줄 이름이 통째 짓기와 같은 값을 얻게.
    pub fn stored_period(&self, id: i64) -> Result<Option<(i64, i64, i64)>> {
        Ok(self.db.prepare_cached("SELECT pack,start,end FROM periods WHERE id=?1")?.query_row([id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).optional()?)
    }

    /// 덧붙일 때 저장소에 이미 있는 사건의 자료집.
    pub fn stored_event_pack(&self, id: i64) -> Result<Option<i64>> {
        Ok(self.db.prepare_cached("SELECT pack FROM events WHERE id=?1")?.query_row([id], |r| r.get(0)).optional()?)
    }

    fn appending(&self) -> bool {
        matches!(self.db, Db::Tx(_))
    }

    /// 마칠 때(`finalize`) 적을 메타를 미리 적어 둔다. 같은 열쇠를 다시 적으면 뒤엣것으로 바꾼다.
    /// `fill_into`가 쓴다 — 채우는 일(`&mut Builder`)과 마치는 일(`finalize(self)`)이 다른 곳에서 일어나므로.
    /// (`finalize`는 시계를 보지 않는다 — 가상 자료 생성기처럼 언제 지어도 같은 바이트여야 하는 길이 있다.)
    pub fn add_meta(&mut self, key: &str, value: String) {
        match self.meta_extra.iter_mut().find(|(k, _)| k == key) {
            Some(slot) => slot.1 = value,
            None => self.meta_extra.push((key.to_owned(), value)),
        }
    }

    /// 아주 큰 시험 자료에서 본문 검색 색인을 빼고 만들 때만 쓴다(보고서에 밝힐 것).
    pub fn without_search(mut self) -> Self {
        self.search = false;
        self
    }

    pub fn pack(&mut self, name: &str, original: Option<&[u8]>) -> Result<i64> {
        let sha = original.map(|bytes| format!("{:x}", Sha256::digest(bytes)));
        self.db.prepare_cached("INSERT INTO packs(name,original,sha256) VALUES(?1,?2,?3)")?.execute(params![name, original, sha])?;
        Ok(self.db.last_insert_rowid())
    }

    /// 2판과 같은 트랙(색 없음 · 모든 단 켬).
    pub fn track(&mut self, pack: i64, name: &str) -> Result<i64> {
        self.track_full(&TrackIn::plain(pack, name))
    }

    pub fn track_full(&mut self, t: &TrackIn) -> Result<i64> {
        self.db.prepare_cached("INSERT INTO tracks(pack,ord,name,color,dynasty,leader,cabinet,organ,rail_levels,key) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)")?
            .execute(params![t.pack, self.track_ord0 + self.tracks, t.name, t.color, t.dynasty, t.leader, t.cabinet, t.organ, t.rail_levels, t.key])?;
        self.tracks += 1;
        Ok(self.db.last_insert_rowid())
    }

    /// 다시 쓰는 트랙(계획 P4 과제 5c — 덧붙일 때만): `tracks.id`를 그대로 두고 값만 새 배치의 것으로 바꿔 적는다. 차례(`ord`)는 부르는 쪽
    /// (`patch::apply`의 "order")이 다시 적는다. 문화권은 빈 글로 되돌린다 — 새 값은 [`Builder::track_sphere`]가 적는다(열이 없는 옛 저장소는 건너뜀).
    /// 새로 든 트랙 수(`Appended::tracks`)에는 세지 않는다. 그 트랙의 줄 · 띠 · 사건 …은 부르는 쪽이 먼저 지워 두었어야 한다.
    pub fn track_reuse(&mut self, id: i64, t: &TrackIn) -> Result<i64> {
        if !self.appending() {
            return Err("트랙을 다시 쓰는 것은 덧붙이는 Builder에서만 합니다".into());
        }
        let changed = self.db.prepare_cached("UPDATE tracks SET pack=?2,name=?3,color=?4,dynasty=?5,leader=?6,cabinet=?7,organ=?8,rail_levels=?9,key=?10 WHERE id=?1")?
            .execute(params![id, t.pack, t.name, t.color, t.dynasty, t.leader, t.cabinet, t.organ, t.rail_levels, t.key])?;
        if changed != 1 {
            return Err(format!("다시 쓸 트랙이 저장소에 없습니다: {id}").into());
        }
        if self.db.prepare_cached("SELECT 1 FROM pragma_table_info('tracks') WHERE name='sphere'")?.exists([])? {
            self.db.prepare_cached("UPDATE tracks SET sphere='' WHERE id=?1")?.execute([id])?;
        }
        Ok(id)
    }

    /// 트랙 지문(계획 P4 과제 4 — `patch::prints`가 셈한 것)을 `track_prints`에 적는다. 가져오기(`legacy::fill`)가 끝에서 부른다.
    pub fn track_prints(&mut self, prints: &crate::patch::Prints) -> Result<()> {
        crate::patch::save_prints(&self.db, prints)
    }

    /// 넣은 트랙의 문화권(글자 id — `east-asia` … · 리메이크 조각 ②). 빈 글자면 그대로 둔다(열의 기본값이 빈 글자).
    /// `TrackIn`에 칸을 더하지 않고 따로 적는다 — 트랙을 만드는 곳(가상 자료 · 검사)이 문화권을 몰라도 그대로이게.
    pub fn track_sphere(&mut self, track: i64, sphere: &str) -> Result<()> {
        if sphere.is_empty() {
            return Ok(());
        }
        let changed = self.db.prepare_cached("UPDATE tracks SET sphere=?2 WHERE id=?1")?.execute(params![track, sphere])?;
        if changed != 1 {
            return Err(format!("문화권을 적을 트랙이 없습니다: {track}").into());
        }
        Ok(())
    }

    /// 줄 열쇠(새 저장소는 전체 줄 번호 — 0부터)를 돌려준다. 줄은 트랙을 만든 순서 → 부른 순서로 쌓인다.
    pub fn row(&mut self, track: i64, geo: &RowGeo) -> Result<i64> {
        self.row_full(track, geo, &RowExtra::default())
    }

    pub fn row_full(&mut self, track: i64, geo: &RowGeo, more: &RowExtra) -> Result<i64> {
        let id = self.rows;
        let ord = self.row_ord.entry(track).or_insert(0);
        let cats = serde_json::to_string(&more.cats)?;
        self.db.prepare_cached("INSERT INTO rows(id,track,ord,height,band_top,band_h,dyn_top,lead_top,cab_top,text_top,text_lines,rail_top,organ_top,\
            kind,group_start,scope_pad,phase,rank,cats,fig,fig_wide,dep,zones,hem,variant) \
            VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25)")?
            .execute(params![id, track, *ord, geo.height, geo.band_top, geo.band_h, geo.dyn_top, geo.lead_top, geo.cab_top, geo.text_top, geo.text_lines, geo.rail_top, geo.organ_top,
                more.kind, more.group_start, more.scope_pad, more.phase, more.rank, cats, more.fig, more.fig_wide.max(more.fig), more.dep, more.zones, more.hem, more.variant])?;
        *ord += 1;
        self.rows += 1;
        self.row_track.push(track);
        Ok(id)
    }

    pub fn group(&mut self, g: &GroupIn) -> Result<i64> {
        self.db.prepare_cached("INSERT INTO groups(track,depth,first_row,row_count,name,color,kind) VALUES(?1,?2,?3,?4,?5,?6,?7)")?
            .execute(params![g.track, g.depth, g.first_row, g.row_count, g.name, g.color, g.kind])?;
        self.groups += 1;
        Ok(self.db.last_insert_rowid())
    }

    pub fn category(&mut self, pack: i64, ord: i64, key: &str, name: &str, color: u32) -> Result<i64> {
        self.db.prepare_cached("INSERT INTO categories(pack,ord,key,name,color) VALUES(?1,?2,?3,?4,?5)")?
            .execute(params![pack, ord, key, name, color])?;
        self.categories += 1;
        Ok(self.db.last_insert_rowid())
    }

    pub fn axis_cell(&mut self, a: &AxisCellIn) -> Result<i64> {
        if a.start > a.end {
            return Err("날짜 칸의 기간이 뒤집혔습니다".into());
        }
        self.db.prepare_cached("INSERT INTO axis_cells(pack,kind,track,lane,start,end,name,color,style,strip,seq) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)")?
            .execute(params![a.pack, a.kind, a.track, a.lane, a.start, a.end, a.name, a.color, a.style, a.strip, a.seq])?;
        self.axis_cells += 1;
        self.stretch(a.start, a.end);
        Ok(self.db.last_insert_rowid())
    }

    pub fn epoch(&mut self, pack: i64, start: i64, end: i64, color: u32, name: &str) -> Result<i64> {
        self.db.prepare_cached("INSERT INTO epochs(pack,start,end,color,name) VALUES(?1,?2,?3,?4,?5)")?.execute(params![pack, start, end, color, name])?;
        self.stretch(start, end);
        Ok(self.db.last_insert_rowid())
    }

    pub fn period(&mut self, pack: i64, row: i64, start: i64, end: i64, fuzzy: i64, color: u32, name: &str) -> Result<i64> {
        self.period_full(&PeriodIn { pack, row, start, end, fuzzy, color, name, look: 0, tag: "", sub: 0, uid: "", variant: 0, form: 0 })
    }

    /// 같은 줄에서 띠끼리 겹쳐도 거절하지 않는다 — 3단계에서는 바탕 문화처럼 겹쳐 깔리는 띠가 들어온다.
    pub fn period_full(&mut self, p: &PeriodIn) -> Result<i64> {
        self.period_at(p, None)
    }

    /// [`Builder::period_full`]에 번호를 밝혀 넘긴다 — 트랙을 다시 쓸 때 같은 uid의 띠가 옛 번호를 그대로 쓰게(계획 P4 과제 5c).
    /// None이면 덧붙일 때는 지우기 전 가장 큰 번호 다음([`Builder::append_after`]), 새 저장소는 SQLite가 넣은 차례대로 매긴다.
    pub fn period_at(&mut self, p: &PeriodIn, id: Option<i64>) -> Result<i64> {
        let track = self.own_row(p.row)?;
        let id = take_id(id, &mut self.next_period);
        self.db.prepare_cached("INSERT INTO periods(id,pack,row,start,end,fuzzy,color,name,look,tag,sub,uid,variant,form) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)")?
            .execute(params![id, p.pack, p.row, p.start, p.end, p.fuzzy, p.color, p.name, p.look, p.tag, p.sub, p.uid, p.variant, p.form])?;
        let id = self.db.last_insert_rowid();
        // 띠(정권)는 어느 단계에서도 추리지 않는다 — 지금 연표가 아무리 줄여도 모든 띠를 그리듯이(감독 2026-09-22: "최대한 줄여도 아예 사라지는 느낌 없애줘").
        // 예전의 lod_of(기간)는 최대로 줄인 단계에서 진(15년) · 대한제국(13년) 같은 짧은 띠를 타일에서 빼 버려 띠가 사라지고,
        // 그 띠의 사건 점은 띠의 범위를 몰라 숨겨지지 않은 채 띠 밖으로 튀어나왔다. 띠 수는 사건 수와 달리 작아(100만 건 자료에서 2만 6천) 성긴 타일이 감당한다.
        let lod = LEVEL_MAX as i64;
        self.db.prepare_cached("INSERT INTO period_bounds VALUES(?1,?2,?3,?4,?4,?5,?5)")?
            .execute(params![id, p.start.div_euclid(DAY), p.end.div_euclid(DAY), p.row, lod])?;
        self.period_rows.insert(id, p.row);
        // 새 저장소에서는 띠 번호가 넣은 차례 + 1이다(일반 항목의 띠 번호 칸 · 칸이 그렇게 가리킨다). 덧붙일 때는 번호가 이어서 난다.
        debug_assert!(self.appending() || self.period_rows.len() as i64 == id, "띠 번호가 넣은 차례와 어긋났습니다");
        *self.pack_periods.entry(p.pack).or_insert(0) += 1;
        self.pack_tracks.entry(p.pack).or_default().insert(track);
        self.stretch(p.start, p.end);
        Ok(id)
    }

    pub fn cell(&mut self, period: i64, kind: i64, start: i64, end: i64, name: &str) -> Result<i64> {
        self.cell_full(&CellIn { period, kind, start, end, name, lane: 0, style: 0, color: 0, variant: 0 })
    }

    /// 같은 단에서 칸끼리 겹쳐도 거절하지 않는다 — 여러 단의 기관 · 인물이 겹쳐 들어온다.
    pub fn cell_full(&mut self, c: &CellIn) -> Result<i64> {
        let row = *self.period_rows.get(&c.period).ok_or("칸이 가리키는 띠가 없습니다")?;
        self.db.prepare_cached("INSERT INTO cells(period,kind,start,end,name,lane,style,color,variant) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)")?
            .execute(params![c.period, c.kind, c.start, c.end, c.name, c.lane, c.style, c.color, c.variant])?;
        let id = self.db.last_insert_rowid();
        let lod = lod_of(c.end - c.start);
        self.db.prepare_cached("INSERT INTO cell_bounds VALUES(?1,?2,?3,?4,?4,?5,?5)")?
            .execute(params![id, c.start.div_euclid(DAY), c.end.div_euclid(DAY), row, lod])?;
        self.cells += 1;
        Ok(id)
    }

    pub fn item(&mut self, it: &ItemIn) -> Result<i64> {
        if it.section < 16 {
            return Err("일반 항목의 구역 번호는 16 이상입니다".into());
        }
        if it.row > it.row2 {
            return Err("일반 항목의 줄 범위가 뒤집혔습니다".into());
        }
        if it.start > it.end {
            return Err("일반 항목의 기간이 뒤집혔습니다".into());
        }
        self.own_row(it.row)?;
        self.own_row(it.row2)?;
        self.db.prepare_cached("INSERT INTO items(pack,section,row,row2,start,end,ref,name,color,a,b,c,d,text2,ref_kind,variant) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)")?
            .execute(params![it.pack, it.section, it.row, it.row2, it.start, it.end, it.ref_id, it.name, it.color, it.a, it.b, it.c, it.d, it.text2, it.ref_kind, it.variant])?;
        let id = self.db.last_insert_rowid();
        let lod = it.lod.unwrap_or_else(|| lod_of(it.end - it.start));
        self.db.prepare_cached("INSERT INTO item_bounds VALUES(?1,?2,?3,?4,?5,?6,?6)")?
            .execute(params![id, it.start.div_euclid(DAY), it.end.div_euclid(DAY), it.row, it.row2, lod])?;
        self.items += 1;
        // 변형의 '가리는 것'이 항목을 번호로 가리킨다 — 새 저장소에서는 번호가 실린 차례 + 1이어야 한다(내보내기가 그 차례로 적어 보낸다).
        // 덧붙일 때는 번호가 이어서 나고, 채우는 쪽(`legacy::fill_into`)이 넣은 번호의 목록으로 가리기를 푼다.
        debug_assert!(self.appending() || self.items == id, "일반 항목의 번호가 실린 차례와 어긋났습니다");
        self.stretch(it.start, it.end);
        Ok(id)
    }

    /// 왼쪽 줄 이름 칸이 쓰는 후보 띠 하나. 원소의 JSON은 그대로 보존한다(뜻은 그리는 쪽이 본다 — 계약 6-8절).
    pub fn row_label(&mut self, row: i64, start: i64, end: i64, period: i64, json: &str) -> Result<()> {
        self.own_row(row)?;
        self.db.prepare_cached("INSERT INTO row_labels(row,start,end,period,json) VALUES(?1,?2,?3,?4,?5)")?
            .execute(params![row, start, end, period, json])?;
        self.row_labels += 1;
        Ok(())
    }

    /// 변형 하나(계약 3-2절). 돌려주는 값이 변형 번호이고, 줄 · 이사 · 가리는 것 · 묶음이 이 번호를 가리킨다.
    pub fn variant(&mut self, key: &str, kind: i64, track: i64, band: i64, uid: &str, name: &str, notes: &str) -> Result<i64> {
        self.variant_at(None, key, kind, track, band, uid, name, notes)
    }

    /// [`Builder::variant`]에 번호를 밝혀 넘긴다 — 트랙을 다시 쓸 때 같은 열쇠의 변형이 옛 번호를 그대로 쓰게(얹힌 몫 2 · 판정 R16 가:
    /// 다시 쓰지 않은 트랙의 원소가 단 변형 번호가 맞게). None이면 [`Builder::period_at`]과 같은 규칙.
    #[allow(clippy::too_many_arguments)]
    pub fn variant_at(&mut self, id: Option<i64>, key: &str, kind: i64, track: i64, band: i64, uid: &str, name: &str, notes: &str) -> Result<i64> {
        let id = take_id(id, &mut self.next_variant);
        self.db.prepare_cached("INSERT INTO variants(id,key,kind,track,band,uid,name,notes) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)")?
            .execute(params![id, key, kind, track, band, uid, name, notes])?;
        self.variants += 1;
        Ok(self.db.last_insert_rowid())
    }

    /// 소속 펼치기 변형이 펼치는 상위 띠의 번호. 띠를 다 넣은 뒤에야 알 수 있어 따로 채운다.
    pub fn variant_band(&mut self, variant: i64, band: i64) -> Result<()> {
        self.db.prepare_cached("UPDATE variants SET band=?2 WHERE id=?1")?.execute(params![variant, band])?;
        Ok(())
    }

    /// 그 변형에서 줄을 쌓는 차례(와 덮어쓰는 값).
    pub fn variant_row(&mut self, variant: i64, row: i64, after: i64, ord: i64, is_new: bool, scope_pad: i64, group_start: i64) -> Result<()> {
        self.known_row(row)?;
        if after >= 0 {
            self.known_row(after)?;
        }
        self.db.prepare_cached("INSERT INTO variant_rows(variant,row,after,ord,is_new,scope_pad,group_start) VALUES(?1,?2,?3,?4,?5,?6,?7)")?
            .execute(params![variant, row, after, ord, i64::from(is_new), scope_pad, group_start])?;
        self.variant_rows += 1;
        Ok(())
    }

    /// 줄이 옮겨 쌓이는 것으로 설명되지 않는 이사(kind: 1 띠 · 2 사건).
    pub fn variant_move(&mut self, variant: i64, kind: i64, reference: i64, row: i64) -> Result<()> {
        self.known_row(row)?;
        self.db.prepare_cached("INSERT INTO variant_moves(variant,kind,ref,row) VALUES(?1,?2,?3,?4)")?
            .execute(params![variant, kind, reference, row])?;
        self.variant_moves += 1;
        Ok(())
    }

    /// 그 변형이 켜지면 가려지는 기본 판(kind: 3 칸 · 4 일반 항목).
    pub fn variant_hide(&mut self, variant: i64, kind: i64, reference: i64) -> Result<()> {
        self.db.prepare_cached("INSERT OR IGNORE INTO variant_hides(variant,kind,ref) VALUES(?1,?2,?3)")?
            .execute(params![variant, kind, reference])?;
        Ok(())
    }

    /// 그 변형에서 생기는 왼쪽 칸의 묶음. `rows`는 그 묶음에 드는 전체 줄 번호다.
    pub fn variant_group(&mut self, variant: i64, key: &str, depth: i64, name: &str, color: u32, kind: i64, rows: &[i64]) -> Result<()> {
        for row in rows {
            self.known_row(*row)?;
        }
        self.db.prepare_cached("INSERT INTO variant_groups(variant,key,depth,name,color,kind,rows) VALUES(?1,?2,?3,?4,?5,?6,?7)")?
            .execute(params![variant, key, depth, name, color, kind, serde_json::to_string(rows)?])?;
        Ok(())
    }

    /// 항목 기록 하나. `ord`는 넣은 차례(0부터 — 이 함수를 부른 차례), `sum`은 json 글의 SHA-256 앞 16자(16진)다.
    /// 같은 uid를 다시 넣으면 본문 · 갈래 · 자료집 · 지문은 뒤엣것으로 바꾸고 넣은 차례는 처음 것을 둔다([`EntityOrder`] — 계획 P4 과제 6).
    pub fn entity(&mut self, uid: &str, pack: i64, kind: &str, json: &str) -> Result<()> {
        self.entity_at(uid, pack, kind, json, self.entities)
    }

    /// [`Builder::entity`]에 넣은 차례(`ord` — 배치에서의 자리)를 밝혀 넘긴다. 같은 uid가 있으면 바꿔 적는다(차례는 [`EntityOrder`]).
    pub fn entity_at(&mut self, uid: &str, pack: i64, kind: &str, json: &str, ord: i64) -> Result<()> {
        let ord = self.entity_ord.place(uid, kind, ord);
        let sum = format!("{:x}", Sha256::digest(json.as_bytes()));
        self.db.prepare_cached("INSERT OR REPLACE INTO entities(uid,pack,kind,json,ord,sum) VALUES(?1,?2,?3,?4,?5,?6)")?
            .execute(params![uid, pack, kind, json, ord, &sum[..16]])?;
        self.entities += 1;
        if ORDERED_KINDS.contains(&kind) {
            self.got.ordered.push(uid.to_owned());
        }
        // 찾을 글 재료 · 날짜 칸 주인 후보는 여기서 한 번만 읽는다(같은 uid를 다시 넣으면 뒤엣것으로 바꾼다).
        let peek = Peek::read(json);
        match Found::of(&peek) {
            Some(found) => self.got.found.insert(uid.to_owned(), found),
            None => self.got.found.remove(uid),
        };
        let candidates = axis_candidates(&peek);
        if candidates.is_empty() {
            self.got.owners.remove(uid);
        } else {
            self.got.owners.insert(uid.to_owned(), (peek.track.as_str().unwrap_or("").to_owned(), candidates));
        }
        Ok(())
    }

    /// 그림 바이트 하나(문서 그림 — `blobs` 표). 같은 열쇠를 다시 넣으면 뒤엣것으로 바꾼다.
    pub fn blob(&mut self, key: &str, pack: i64, mime: &str, bytes: &[u8]) -> Result<()> {
        self.db.prepare_cached("INSERT OR REPLACE INTO blobs(key,pack,mime,bytes) VALUES(?1,?2,?3,?4)")?.execute(params![key, pack, mime, bytes])?;
        Ok(())
    }

    /// 문화권 단위의 줄(스키마 4 — `sphere_lines`)을 배치 차례대로 넣는다 — [`put_sphere_lines`]의 얇은 감쌈(시간 범위 `meta.min` · `max`를 넓히지 않음).
    pub fn sphere_lines(&mut self, lines: &[serde_json::Value], pack_of: impl Fn(&serde_json::Value, &str) -> i64) -> Result<usize> {
        put_sphere_lines(&self.db, lines, pack_of)
    }

    pub fn source(&mut self, title: &str, body: &str) -> Result<i64> {
        self.db.prepare_cached("INSERT INTO sources(title,body) VALUES(?1,?2)")?.execute(params![title, body])?;
        Ok(self.db.last_insert_rowid())
    }

    pub fn file(&mut self, source: i64, kind: &str, rel_path: &str, sha256: &str, bytes: i64) -> Result<()> {
        self.db.prepare_cached("INSERT INTO files(source,kind,path,sha256,bytes) VALUES(?1,?2,?3,?4,?5)")?.execute(params![source, kind, rel_path, sha256, bytes])?;
        Ok(())
    }

    pub fn event(&mut self, e: &EventIn) -> Result<i64> {
        self.event_at(e, None)
    }

    /// [`Builder::event`]에 번호를 밝혀 넘긴다(계획 P4 과제 5c — 같은 uid의 사건은 옛 번호로). None이면 [`Builder::period_at`]과 같은 규칙.
    /// `events.ord`에는 **트랙 안 차례**(그 사건이 놓인 줄의 트랙에 이 Builder가 넣은 차례 · 0부터 — 판정 R23)를 적는다. 한 트랙의 사건은 늘
    /// 한 Builder가 모두 넣으므로(덧붙일 때는 다시 쓰는 트랙을 통째로) 이것이 곧 배치에서 그 트랙의 사건 차례다.
    pub fn event_at(&mut self, e: &EventIn, id: Option<i64>) -> Result<i64> {
        let track = self.own_row(e.lane)?;
        if e.start.is_some() != e.end.is_some() {
            return Err("사건의 시작과 끝은 함께 있거나 함께 없어야 합니다".into());
        }
        let (lo, hi) = (e.lo.or(e.start), e.hi.or(e.end));
        let id = take_id(id, &mut self.next_event);
        let ord = {
            let n = self.track_events.entry(track).or_insert(0);
            *n += 1;
            *n - 1
        };
        self.db.prepare_cached("INSERT INTO events(id,pack,lane,start,end,lo,hi,importance,title,body,source,raw,look,label,rail,uid,band,variant,ord) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19)")?
            .execute(params![id, e.pack, e.lane, e.start, e.end, lo, hi, e.importance, e.title, e.body, e.source, e.raw, e.look, e.label, e.rail, e.uid, e.band, e.variant, ord])?;
        let id = self.db.last_insert_rowid();
        self.events += 1;
        *self.pack_events.entry(e.pack).or_insert(0) += 1;
        self.pack_tracks.entry(e.pack).or_default().insert(track);
        if self.search {
            self.db.prepare_cached("INSERT INTO search(rowid,terms) VALUES(?1,?2)")?.execute(params![id, grams(&format!("{} {}", e.title, e.body)).join(" ")])?;
            if !e.uid.is_empty() {
                self.got.events.push((id, e.uid.to_owned()));
            }
        }
        let (Some(start), Some(end), Some(lo), Some(hi)) = (e.start, e.end, lo, hi) else {
            self.unknown += 1;
            return Ok(id);
        };
        self.db.prepare_cached("INSERT INTO bounds VALUES(?1,?2,?3,?4,?4)")?.execute(params![id, lo.div_euclid(DAY), hi.div_euclid(DAY), e.lane])?;
        // 막대(기간 띠)로 그리는 것은 45.5일(L8의 통 하나) 이상인 사건뿐이다. 그보다 짧은 기간 사건은 시작 시각의 점으로만 나온다 —
        // 그 기간 한가운데로 확대하면 자취가 없다는 한계가 있다(2단계 검증 보고서 8절). 짧은 막대는 지금 연표의 기간 사건 표현을
        // 옮기는 묶음에서 다룬다.
        if end - start >= bucket_minutes(PRE_MIN) {
            let lod = lod_of(end - start);
            self.db.prepare_cached("INSERT INTO span_bounds VALUES(?1,?2,?3,?4,?4,?5,?5)")?
                .execute(params![id, start.div_euclid(DAY), end.div_euclid(DAY), e.lane, lod])?;
        }
        // 그 변형에서만 있는 사건은 미리 셈해 둔 요약에 넣지 않는다 — 요약은 변형을 모르고,
        // 변형이 켜지면 타일이 어차피 그 자리에서 다시 세기 때문이다(계약 2-4절).
        if e.variant != 0 {
            return Ok(id);
        }
        // 개수는 시작 시각의 통에 한 번만 센다 → 어느 단계에서든 합이 날짜 있는 사건 수와 같다.
        let rep = Rep {
            importance: e.importance as u8,
            id: u32::try_from(id).map_err(|_| "사건 번호가 요약의 한도를 넘었습니다")?,
            ord,
            start,
            look: e.look as u32,
            band: e.band as u32,
            prec: ((e.rail >> 8) & 7) as u8,
            title: Rc::from(e.title),
            label: Rc::from(e.label),
        };
        let cell = self.summary.entry((e.lane, bucket_of(start, PRE_MIN), e.pack)).or_default();
        cell.n += 1;
        cell.count_cat(e.look as u32);
        cell.offer(rep);
        self.stretch(lo, hi);
        Ok(id)
    }

    /// 넣는 동안 모은 PRE_MIN 단계의 칸에서 단계별 요약을 모두 쓴다(성긴 단계는 네 칸씩 합쳐). 요약의 열쇠는 (단계, 줄, 통, 자료집)이라
    /// 이 Builder가 넣은 줄의 것만 생긴다 — 덧붙일 때도 저장소의 다른 줄 요약과 부딪치지 않는다.
    fn write_summaries(&mut self) -> Result<()> {
        let mut level_cells = std::mem::take(&mut self.summary);
        for level in PRE_MIN..=LEVEL_MAX {
            let mut keys: Vec<_> = level_cells.keys().copied().collect();
            keys.sort_unstable();
            {
                let mut stmt = self.db.prepare_cached("INSERT INTO summaries(level,lane,bucket,pack,n,reps,cats,ords) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)")?;
                for key in &keys {
                    let cell = &level_cells[key];
                    stmt.execute(params![level as i64, key.0, key.1, key.2, cell.n, cell.blob(), cell.cats_blob(), cell.ords_blob()])?;
                }
            }
            // 위 단계의 통 하나 = 이 단계의 통 넷. 대표는 합쳐서 다시 앞 넷만 남긴다.
            let mut next: HashMap<(i64, i64, i64), Cell> = HashMap::with_capacity(level_cells.len() / 2 + 1);
            for (key, cell) in &level_cells {
                next.entry((key.0, key.1.div_euclid(4), key.2)).or_default().absorb(cell);
            }
            level_cells = next;
        }
        Ok(())
    }

    /// 덧붙이기를 마친다(계획 P4 과제 5b — `patch::apply`의 "summaries"): 이번에 넣은 줄의 단계별 요약을 쓴다. COMMIT · 색인 · 이름 표 ·
    /// 관점 이름 · 사건의 덧줄 · 메타는 부르는 쪽 몫이다(과제 6 — "names"가 저장소에서 이름 표를 다시 펴고, 이번에 넣은 사건(`Appended::named`)의
    /// 덧줄을 저장소의 기록으로 적는다). 넣은 수를 돌려준다.
    pub fn finish_append(mut self) -> Result<Appended> {
        if !self.appending() {
            return Err("새로 짓는 Builder는 finalize로 마칩니다".into());
        }
        self.write_summaries()?;
        Ok(Appended {
            tracks: self.tracks, rows: self.rows - self.row0, periods: self.period_rows.len() as i64, cells: self.cells, events: self.events,
            unknown: self.unknown, groups: self.groups, axis_cells: self.axis_cells, items: self.items, entities: self.entities,
            row_labels: self.row_labels, variants: self.variants, variant_rows: self.variant_rows, variant_moves: self.variant_moves,
            pack_events: std::mem::take(&mut self.pack_events), pack_periods: std::mem::take(&mut self.pack_periods),
            pack_tracks: std::mem::take(&mut self.pack_tracks), span: (self.min <= self.max).then_some((self.min, self.max)),
            named: std::mem::take(&mut self.got.events),
        })
    }

    /// 요약을 쓰고, 메타를 적고, 색인을 다듬고, 무결성을 확인한 뒤 닫는다.
    pub fn finalize(mut self, extra_meta: &[(&str, String)]) -> Result<()> {
        if self.appending() {
            return Err("덧붙인 Builder는 finish_append로 마칩니다".into());
        }
        self.write_summaries()?;
        let (min, max) = if self.min <= self.max { (self.min, self.max) } else { (0, DAY) };
        let periods = self.period_rows.len();
        let packs: i64 = self.db.query_row("SELECT count(*) FROM packs", [], |r| r.get(0))?;
        let mut meta = vec![
            ("schema", schema::VERSION.to_owned()), ("count", self.events.to_string()), ("unknown", self.unknown.to_string()),
            ("min", min.to_string()), ("max", max.to_string()), ("packs", packs.to_string()), ("tracks", self.tracks.to_string()),
            ("rows", self.rows.to_string()), ("periods", periods.to_string()), ("cells", self.cells.to_string()),
            ("groups", self.groups.to_string()), ("categories", self.categories.to_string()), ("axis_cells", self.axis_cells.to_string()),
            ("items", self.items.to_string()), ("entities", self.entities.to_string()), ("row_labels", self.row_labels.to_string()),
            ("variants", self.variants.to_string()), ("variant_rows", self.variant_rows.to_string()), ("variant_moves", self.variant_moves.to_string()),
            ("search", if self.search { "on" } else { "off" }.to_owned()),
            ("pack_events", serde_json::to_string(&self.pack_events.iter().map(|(k, v)| (k.to_string(), *v)).collect::<std::collections::BTreeMap<_, _>>())?),
            ("pack_periods", serde_json::to_string(&self.pack_periods.iter().map(|(k, v)| (k.to_string(), *v)).collect::<std::collections::BTreeMap<_, _>>())?),
            ("pack_tracks", serde_json::to_string(&self.pack_tracks.iter().map(|(k, v)| (k.to_string(), v.iter().copied().collect::<Vec<_>>())).collect::<std::collections::BTreeMap<_, _>>())?),
            ("calendar", "1970-01-01 UTC 기준 정수 분 · 양 끝 포함".to_owned()),
        ];
        let pending = std::mem::take(&mut self.meta_extra);
        meta.extend(pending.iter().map(|(k, v)| (k.as_str(), v.clone())));
        meta.extend(extra_meta.iter().map(|(k, v)| (*k, v.clone())));
        for (key, value) in meta {
            self.db.execute("INSERT INTO meta VALUES(?1,?2)", [key, &value])?;
        }
        // 그 자리에서 세는 단계(L < PRE_MIN)의 타일이 훑는 덮는 색인. 다 넣은 뒤에 한 번에 만드는 편이 빠르다.
        self.db.execute_batch(EVENTS_TIME_INDEX_SQL)?;
        // 조회 명령의 색인을 먼저 만들고(이름 표를 펴는 SQL이 그 색인을 탄다) 이름 표를 편다.
        self.db.execute_batch(QUERY_INDEX_SQL)?;
        let names = build_names(&self.db, &self.got)?;
        self.db.execute("INSERT INTO meta VALUES('names',?1)", [names.to_string()])?;
        let lens = build_lens_names(&self.db)?;
        self.db.execute("INSERT INTO meta VALUES('lens_names',?1)", [lens.to_string()])?;
        // 사건의 다른 이름은 본문 색인의 덧줄로(본문 색인을 뺀 큰 시험 자료에는 없다).
        if self.search {
            add_event_hay(&self.db, &self.got)?;
        }
        self.db.execute_batch("COMMIT")?;
        self.db.execute_batch("INSERT INTO search(search) VALUES('optimize'); ANALYZE;")?;
        let integrity: String = self.db.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
        if integrity != "ok" {
            return Err(integrity.into());
        }
        Ok(())
    }

    /// 이 Builder가 넣은 줄이면 그 트랙 번호(띠 · 사건 · 항목 · 줄 이름이 놓이는 줄). 새 저장소에서는 모든 줄이 그렇다.
    fn own_row(&self, row: i64) -> Result<i64> {
        usize::try_from(row - self.row0).ok().and_then(|at| self.row_track.get(at)).copied()
            .ok_or_else(|| {
                let why = if self.outer_rows.contains(&row) { "하위 배치 밖 트랙의 줄에는 띠 · 사건 · 항목을 놓을 수 없습니다" } else { "없는 줄 번호" };
                format!("{why}: {row}").into()
            })
    }

    /// 이 Builder가 넣은 줄이거나, 덧붙일 때 알린 바깥 줄([`Builder::outer_rows`] — 변형의 줄 · 이사 · 묶음이 가리키는 것).
    fn known_row(&self, row: i64) -> Result<()> {
        if (self.row0..self.rows).contains(&row) || self.outer_rows.contains(&row) { Ok(()) } else { Err(format!("없는 줄 번호: {row}").into()) }
    }

    fn stretch(&mut self, lo: i64, hi: i64) {
        self.min = self.min.min(lo);
        self.max = self.max.max(hi);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rep(importance: u8, id: u32) -> Rep {
        Rep { importance, id, ord: i64::from(id) - 1, start: id as i64, look: 0, band: 0, prec: 0, title: Rc::from("가상 사건"), label: Rc::from("") }
    }

    #[test]
    fn 대표는_중요도_큰_순_번호_작은_순으로_넷만_남는다() {
        let mut cell = Cell::default();
        for (importance, id) in [(1u8, 9u32), (3, 7), (2, 5), (3, 2), (1, 1), (2, 4)] {
            cell.n += 1;
            cell.offer(rep(importance, id));
        }
        let kept: Vec<(u8, u32)> = cell.reps.iter().map(|r| (r.importance, r.id)).collect();
        assert_eq!(kept, vec![(3, 2), (3, 7), (2, 4), (2, 5)]);
        assert_eq!(cell.n, 6);
    }

    #[test]
    fn 칸을_합치면_넣는_순서와_상관없이_같은_대표가_남는다() {
        let reps: Vec<Rep> = (1..=12u32).map(|id| rep((id % 3 + 1) as u8, id)).collect();
        let whole = reps.iter().fold(Cell::default(), |mut c, r| { c.n += 1; c.offer(r.clone()); c });
        let mut left = Cell::default();
        let mut right = Cell::default();
        for (i, r) in reps.iter().rev().enumerate() {
            let side = if i % 2 == 0 { &mut left } else { &mut right };
            side.n += 1;
            side.offer(r.clone());
        }
        left.absorb(&right);
        assert_eq!(left.n, whole.n);
        assert_eq!(left.blob(), whole.blob());
    }

    #[test]
    fn 대표_덩어리는_look과_딱지와_든_띠까지_품는다() {
        let mut cell = Cell::default();
        cell.n = 1;
        cell.offer(Rep { importance: 2, id: 7, ord: 6, start: -5, look: 0x0103, band: 42, title: Rc::from("별여울 기록"), label: Rc::from("12년"), prec: 0 }); // prec: 묶음 5에서 더한 칸(해 = 0) — 이 검사만 빠져 있어 cargo test가 멈췄음
        let blob = cell.blob();
        let title_len = u16::from_le_bytes(blob[6..8].try_into().unwrap()) as usize;
        let label_len = u16::from_le_bytes(blob[20..22].try_into().unwrap()) as usize;
        assert_eq!(blob.len(), REP_HEAD + title_len + label_len);
        assert_eq!(u32::from_le_bytes(blob[16..20].try_into().unwrap()), 0x0103);
        assert_eq!(u32::from_le_bytes(blob[24..28].try_into().unwrap()), 42);
        assert_eq!(std::str::from_utf8(&blob[REP_HEAD..REP_HEAD + title_len]).unwrap(), "별여울 기록");
        assert_eq!(std::str::from_utf8(&blob[REP_HEAD + title_len..]).unwrap(), "12년");
    }
}

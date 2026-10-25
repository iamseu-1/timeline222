//! 상세 창 · 검색 · 도구가 부르는 조회 명령(계약 `docs/계약-아카이브-3단계.md` 2절의 뒤쪽).
//! `uid_of` · `id_of` · `entities` · 넓힌 `search` · `search_year` · `events_in` · `same_year` ·
//! `table` · `table_csv` · `legend_kinds` · `cells_of`.
//!
//! 공통 약속
//! - 켠 자료집은 `packs`로 준다. 주지 않으면 저장소의 모든 자료집을 본다.
//! - 길어지는 답은 `after`(건너뛸 수) → `next`(다음에 줄 `after`) · `has_more`로 나눠 준다.
//! - 시간은 1970-01-01 UTC 기준 정수 분이고 범위는 양 끝을 포함한다(기원전은 음수).
//! - 줄은 밖으로 보이는 **자리**(0부터 빈틈없는 전체 줄 번호)로 받고 자리로 낸다. 저장소 안(표 · R-tree)은 줄 **열쇠**(`rows.id`)로
//!   말하므로 경계에서 바꾼다(계획 P4 · `rowmap`): 받은 자리는 `key` · 자리 범위는 `ranges_for`(범위마다 같은 SQL → 원래 차례로 다시
//!   늘어놓음), 내는 줄은 `pos` · `outward`. 줄끼리 잇는 SQL(`r.id=e.lane` …)과 거르개 · 변형의 줄 모음은 안의 말(열쇠) 그대로다.
//!   열쇠 = 자리 저장소(새로 지은 것)는 바꿀 것이 없어 예전 물음 · 예전 답 그대로다.
use crate::{span, Result, Store, DAY};
use rusqlite::types::Value as SqlValue;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::Write;
use std::path::Path;

/// 띠의 종류 이름 — 계약 6-1의 종류 번호(look 아래 5비트) 차례.
pub const BAND_KINDS: [&str; 23] = [
    "국가", "조공·책봉국", "봉국·제후국", "자치령", "군벌·할거 세력", "종속국", "보호국", "위성국", "괴뢰국", "위임·신탁 통치령",
    "식민지·속령", "점령지·군정", "연맹", "조직체", "시대 이름", "망명 정부", "부흥·저항 세력", "문화", "기관", "왕조",
    // 묶음 3 · 3번(2026-09-22): 시대마다의 특별한 형태 — 번호는 뒤에 이어 붙임(계약 6-1)
    "복속 세력·부용", "기미·번부·토사", "직할령·군현",
];
/// 띠의 종류마다의 한마디 — 지금 연표 `js/core.js`의 `HT.ALL_KINDS`(POLITY_KINDS + EXTRA_KINDS)에 적힌 글 그대로.
/// 차례는 `BAND_KINDS`와 같다(계약 6-1의 종류 번호 = `KIND_ORDER` + `EXTRA_KINDS`).
pub const BAND_KIND_HINTS: [&str; 23] = [
    "독립 국가·왕조 (기본값) — 보통 띠",
    "조공을 바치고 책봉을 받되 안은 스스로 다스린 나라 — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림",
    "상국이 봉한 제후의 나라 — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림",
    "본국 아래에서 스스로 다스리는 땅 — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림",
    "상징적 본국을 받들되 실제로는 따로 다스린 세력 — 옅은 띠, 상국 띠 아래에 점선 이름표로 매달림",
    "다른 나라에 종속된 정권 — 옅은 띠, 상국 띠 아래에 칠한 이름표로 매달림",
    "외교·군사를 상국에 맡긴 나라 — 옅은 띠, 상국 띠 아래에 칠한 이름표로 매달림",
    "형식은 독립국이나 상국의 뜻을 따르는 나라 — 옅은 띠, 상국 띠 아래에 칠한 이름표로 매달림",
    "다른 나라가 세워 움직이는 정권 — 옅은 띠, 상국 띠 안 맨 아래에 옅은 이름표로 들어감",
    "다른 나라가 맡아 다스리는 땅 — 옅은 띠, 상국 띠 안 맨 아래에 옅은 이름표로 들어감",
    "본국이 직접 다스리는 바깥 땅 — 옅은 띠, 상국 띠 안 맨 아래에 짙은 이름표로 들어감",
    "다른 나라 군대가 차지해 다스리는 땅 — 옅은 띠, 상국 띠 안 맨 아래에 빗금 이름표로 들어감",
    "여러 나라의 연합 — 속이 빈 겹줄 띠. 구성국은 \"소속\"으로 이 연맹을 가리킵니다",
    "국가가 아닌 독립 조직체 — 모서리가 각진 가는 띠",
    "왕조가 아닌 시대 이름을 띠로 놓을 때 — 테두리 없는 옅은 띠",
    "제 땅을 잃고 나라 밖에서 이어 간 정부 — 옅은 띠 · 딱지 \"망명\"",
    "멸망한 나라를 되살리려 하거나 지배에 맞선 세력 — 왼쪽에 깃대가 선 옅은 띠 · 딱지 \"세력\"",
    "국가 이전의 고고학 문화 — 승계국 줄 밑에 깔리는 바탕 띠",
    "주권 정권 안에 놓인 외세 기관·특수 구역 — 기관은 시대 띠 안 맨 아래의 기관 칸에, 구역은 시대 띠 아래로 내려오는 작은 탭으로 (둘 다 성긴 빗금 = 외세의 손길 · 속국 이름표는 민무늬)",
    "나라(국체)를 다스린 왕가 — 다스린 시대 띠 맨 위의 왕조 칸에 긴 둥근 칸으로. 나라와 왕조가 같으면 적지 않아도 됩니다",
    "나라가 아닌 변방의 복속 세력 · 부용(옥저 · 동예 · 부족 …) — 점선 테두리의 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림",
    "직함만 주고 현지 수장이 다스린 변경(기미주 · 토사 · 번부) — 옅은 띠, 상국 띠 아래에 빈 이름표로 매달림",
    "상국이 관리를 보내 직접 다스린 땅(군현 · 도호부 · 총관부) — 옅은 띠, 상국 띠 안 맨 아래에 짙은 이름표로 들어감",
];
/// 60갑자의 천간과 지지 — 화면 쪽 `app/lib/scene/ruler.dart`의 `ganjiOf`와 같은 차례.
const GANJI_STEMS: [&str; 10] = ["갑", "을", "병", "정", "무", "기", "경", "신", "임", "계"];
const GANJI_BRANCHES: [&str; 12] = ["자", "축", "인", "묘", "진", "사", "오", "미", "신", "유", "술", "해"];

/// 천문 해(0년이 있는 셈)의 간지.
pub fn ganji_of(year: i64) -> String {
    let at = (year - 4).rem_euclid(60);
    format!("{}{}", GANJI_STEMS[(at % 10) as usize], GANJI_BRANCHES[(at % 12) as usize])
}

/// css 색 글(`#a0bcc5` · `#abc`) → 0xRRGGBB. 읽지 못하면 지금 연표의 기본 회색이다.
pub fn css_color(text: &str) -> i64 {
    let body = text.trim().trim_start_matches('#');
    let full = match body.len() {
        3 => body.chars().flat_map(|c| [c, c]).collect::<String>(),
        6 => body.to_owned(),
        _ => return 0xa4_b1b7,
    };
    i64::from_str_radix(&full, 16).unwrap_or(0xa4_b1b7)
}

/// 띠 안 칸의 단 이름 — 계약 6-2의 `kind`.
pub const CELL_KINDS: [&str; 8] = ["왕조", "지도자", "내각", "기관", "시기 구분", "지위", "인물", "예속"];
/// 날짜 칸의 이름 — 계약 6-3의 `kind`. 조회 명령의 칸 번호는 100을 더한 값이다(띠 안 칸과 섞이지 않게).
pub const AXIS_KINDS: [&str; 5] = ["", "시대 구분", "연호", "도읍", "배도"];
/// 연대의 확실성 — 계약 6-1의 look 5~6비트.
pub const CERTAINTY: [&str; 4] = ["확실", "통설", "추정", "전승"];
/// 실재성 — 계약 6-1의 look 8~10비트.
pub const HISTORICITY: [&str; 5] = ["실재", "반전설", "전설", "실재 논쟁", "부정됨"];
/// 이름 검색에서 고를 수 있는 갈래. `cell`은 띠 안 칸과 날짜 칸을 함께 가리키고, `doc`은 하위 문서다.
/// `group`(단체) · `institution`(제도)은 형식 3의 기록이다 — 그 기록이 없는 저장소에서는 빈 결과이고,
/// 날짜 검색(`search_year`)에서는 늘 빈 결과다(지금 연표도 날짜 · 간지 검색에서는 단체 · 제도 · 가문을 찾지 않는다).
pub const SEARCH_KINDS: [&str; 14] = ["event", "treaty", "period", "organ", "culture", "dynasty", "figure", "epoch", "scope", "house", "cell", "doc", "group", "institution"];

/// 넓힌 검색 결과의 갈래 차례(찾을 글 `names.hay`가 있는 저장소에서만) — 지금 연표 `runSearch`의 차례 그대로:
/// 항목(사건 · 정권 · 인물 … — 시작 순) → 칸(시작 순) → 하위 문서 → 가문 → 단체 → 제도. 뒤의 셋은 넣은 차례(= 모델 차례)다.
const WIDE_ORDER: &str = "CASE k WHEN 'cell' THEN 1 WHEN 'doc' THEN 2 WHEN 'house' THEN 3 WHEN 'group' THEN 4 WHEN 'institution' THEN 5 ELSE 0 END,\
    CASE WHEN k IN ('house','group','institution') THEN ri ELSE 0 END,";

/// 사건의 찾을 글 — 넣을 때 적어 둔 `event_hay`에서(소문자). 넓힌 검색이 본문 색인의 후보에 대해서만 꺼낸다(계약 2-1).
const EVENT_HAY_SQL: &str = "COALESCE((SELECT h.hay FROM event_hay h WHERE h.id=e.id),'')";

/// `event_hay`가 없는 저장소에서 같은 값을 항목 기록에서 꺼내는 길(제 기록이 없으면 밑동 `uid#1`의 `uid`의 기록) — 느리다.
const EVENT_HAY_JSON_SQL: &str = "lower(COALESCE(\
    (SELECT CASE WHEN json_valid(x.json) THEN json_extract(x.json,'$.x_find.hay') END FROM entities x WHERE x.uid=e.uid),\
    (SELECT CASE WHEN json_valid(x.json) THEN json_extract(x.json,'$.x_find.hay') END FROM entities x \
      WHERE instr(e.uid,'#')>1 AND x.uid=substr(e.uid,1,instr(e.uid,'#')-1)),''))";

/// 같은 해 보기가 창에 담는 사건의 수(그보다 많으면 `count`만 참값이다).
const SAME_YEAR_EVENTS: i64 = 200;

/// 분 → 해(원형 그레고리력 · 0년 = 기원전 1년). Howard Hinnant의 `civil_from_days`에서 해만 남겼다.
pub fn year_of(minute: i64) -> i64 {
    let z = minute.div_euclid(DAY) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    if mp >= 10 { year + 1 } else { year }
}

/// 해 → 사람이 읽는 글. 0년은 기원전 1년이다.
pub fn year_text(year: i64) -> String {
    if year <= 0 { format!("기원전 {}년", 1 - year) } else { format!("{year}년") }
}

/// 검색 결과 · 표의 '때' 글. 사건은 내보내기가 실어 준 날짜 글(`events.label`)을 먼저 쓴다.
pub fn when_text(start: Option<i64>, end: Option<i64>, label: &str) -> String {
    if !label.is_empty() {
        return label.to_owned();
    }
    match (start, end) {
        (Some(from), Some(to)) => {
            let (a, b) = (year_of(from), year_of(to));
            if a == b { year_text(a) } else { format!("{}–{}", year_text(a), year_text(b)) }
        }
        (Some(from), None) => year_text(year_of(from)),
        _ => "미정".to_owned(),
    }
}

/// 날짜의 정밀도 — 사건의 `rail` 8~10비트(계약 6-6). 찾는 쪽은 이 한 글자로 갈 곳의 배율을 정한다.
pub fn prec_text(rail: i64) -> &'static str {
    // c · c2 · c3 = 세기 · 반세기 · 세기의 셋째(묶음 5 · 6번 — 내보내기 events.mjs의 PREC)
    ["y", "m", "d", "h", "min", "c", "c2", "c3"].get(((rail >> 8) & 7) as usize).copied().unwrap_or("y")
}

/// 검색 결과 한 줄에 함께 실리는 칸 이야기: 글자 참조(`leader:3`)와 옛 정수 종류.
#[derive(Default, Clone)]
pub struct CellRef<'a> {
    /// 계약 6-2의 단 번호(날짜 칸은 100 + 6-3의 종류). 칸이 아니면 None.
    pub kind: Option<i64>,
    /// 상세 창이 그 칸을 여는 글자 참조. 모르면 빈 글자.
    pub text: &'a str,
}

/// 검색 · 날짜 검색이 함께 쓰는 결과 한 줄. 줄 번호가 없는 것(왕조 · 날짜 칸 …)은 `row`가 null이다.
/// `cell`은 **글자 참조**(`leader:3` — 상세 창이 그 칸을 연다)이고, 옛 정수 종류는 `cell_kind`로 함께 간다.
#[allow(clippy::too_many_arguments)]
fn item(kind: &str, uid: &str, name: &str, sub: &str, cell: &CellRef, id: Option<i64>, start: Option<i64>, end: Option<i64>, row: i64, color: i64, label: &str, track: &str, prec: &str) -> Value {
    json!({"kind":kind,"uid":uid,"name":name,"sub":sub,
        "cell":if cell.text.is_empty() { Value::Null } else { Value::from(cell.text) },"cell_kind":cell.kind,
        "id":id,"when":when_text(start, end, label),
        "start":start,"end":end,"row":if row >= 0 { Value::from(row) } else { Value::Null },"color":color,"track":track,"prec":prec})
}

/// 띠 안 칸의 글자 참조(`leader:3`) — 상세 창이 그 칸을 연다.
/// 번호는 **`style`의 15~26비트**에 실려 온 순번 + 1이다(계약 6-2의 '`style`에 함께 싣는 값').
/// `lane`은 타일의 정렬 열쇠라 단 번호 말고는 아무것도 얹지 않는다 — 옛 자리(`lane >> 19`)에서 읽으면 늘 0이 나온다.
/// 상세 창이 여는 칸은 지도자 · 내각 · 시기 구분 · 지위뿐이라, 나머지 단은 빈 글자다.
pub fn strip_cell_ref(kind: i64, style: i64) -> String {
    let seq = ((style >> 15) & 0xfff) - 1;
    let head = match kind {
        1 => "leader",
        2 => "cabinet",
        4 => "phase",
        5 => "rank",
        _ => return String::new(),
    };
    if seq < 0 { String::new() } else { format!("{head}:{seq}") }
}

/// 날짜 칸의 글자 참조 — 연호는 `era:<seq>`, 도읍 · 배도는 `capital:<seq>`다(계약 6-3).
pub fn axis_cell_ref(kind: i64, seq: i64) -> String {
    match kind {
        2 => format!("era:{seq}"),
        3 | 4 => format!("capital:{seq}"),
        _ => String::new(),
    }
}

/// 띠 안 칸 · 날짜 칸의 곁글("〈정권 또는 트랙 이름〉 〈칸 종류〉").
fn cell_sub(owner: &str, cell: i64) -> String {
    let name = if cell >= 100 {
        AXIS_KINDS.get((cell - 100) as usize).copied().unwrap_or("날짜 칸")
    } else {
        CELL_KINDS.get(cell as usize).copied().unwrap_or("칸")
    };
    if owner.is_empty() { name.to_owned() } else { format!("{owner} {name}") }
}

fn num(q: &Value, key: &str) -> Result<i64> {
    q[key].as_i64().ok_or_else(|| format!("정수 입력 누락: {key}").into())
}

/// 한 쪽에 줄 수. 없으면 기본값, 1과 최대 사이로 자른다.
fn limit_of(q: &Value, fallback: i64, most: i64) -> Result<i64> {
    match &q["limit"] {
        Value::Null => Ok(fallback),
        v => Ok(v.as_i64().ok_or("한 번에 받을 수가 정수가 아닙니다")?.clamp(1, most)),
    }
}

/// 건너뛸 수. 음수는 거절한다.
fn after_of(q: &Value) -> Result<i64> {
    match &q["after"] {
        Value::Null => Ok(0),
        v => {
            let at = v.as_i64().ok_or("이어 받기 표(after)가 정수가 아닙니다")?;
            if at < 0 { Err("이어 받기 표(after)는 0 이상입니다".into()) } else { Ok(at) }
        }
    }
}

/// `limit + 1`개를 받아 두고 잘라, 남은 것이 있는지와 다음 `after`를 함께 돌려준다.
fn page(mut rows: Vec<Value>, after: i64, limit: i64) -> Value {
    let more = rows.len() as i64 > limit;
    rows.truncate(limit as usize);
    json!({"items":rows,"next":after + limit,"has_more":more})
}

/// 상세 창이 읽는 이름(`events` · `more`)을 한 쪽에 덧붙인다 — `items` · `has_more`는 그대로 둔다.
fn with_events(mut answer: Value) -> Value {
    answer["events"] = answer["items"].clone();
    answer["more"] = answer["has_more"].clone();
    answer
}

/// 이름의 **밑동** — 공동 사건의 둘째 자리 `uid#1`, 여러 줄에 깔린 바탕 문화 `uid#u3`처럼 `#` 뒤가 붙은 이름의 앞부분.
/// 항목 기록은 밑동 하나만 두므로, 그대로 찾지 못한 이름은 이 값으로 한 번 더 찾는다. `#`이 없으면 None이다.
pub fn uid_stem(uid: &str) -> Option<&str> {
    uid.split_once('#').map(|(stem, _)| stem).filter(|stem| !stem.is_empty())
}

/// 겹치거나 맞닿은 구간을 하나로 잇는다(지금 연표의 `HT.echoSpans`). 구간은 반열린 `[시작, 끝)`이다.
fn merge_spans(mut list: Vec<(i64, i64)>) -> Vec<(i64, i64)> {
    list.sort_unstable();
    let mut out: Vec<(i64, i64)> = Vec::with_capacity(list.len());
    for (start, end) in list {
        match out.last_mut() {
            // 구간은 반열린 `[start, end)`라 '맞닿음'은 앞 구간의 끝 그 분이다(`HT.echoSpans` 그대로).
            Some(last) if start <= last.1 => last.1 = last.1.max(end),
            _ => out.push((start, end)),
        }
    }
    out
}

/// 띠 하나의 메아리 구간(지금 연표의 `HT.echoBandSpans`): 메아리 기간에서 그 띠의 제 조명(`own`)을 빼고,
/// 띠가 있던 구간 `[lo, hi)`로 자른다. 모두 **반열린 구간**이라 빼면 `[a, s)`와 `[e, b)`가 된다.
fn band_echo_spans(spans: &[(i64, i64)], own: &[(i64, i64)], lo: i64, hi: i64) -> Vec<(i64, i64)> {
    let mut out: Vec<(i64, i64)> = spans.to_vec();
    for (start, end) in own {
        let mut next = Vec::with_capacity(out.len() + 1);
        for (a, b) in out {
            if *end <= a || *start >= b {
                next.push((a, b));
                continue;
            }
            if a < *start {
                next.push((a, *start));
            }
            if *end < b {
                next.push((*end, b));
            }
        }
        out = next;
    }
    out.into_iter().map(|(a, b)| (a.max(lo), b.min(hi))).filter(|(a, b)| a < b).collect()
}

/// 메아리를 셈하는 동안 들고 있는 사건 한 줄.
struct EchoCand {
    id: i64,
    /// 여러 자리에 놓인 사건을 하나로 묶는 열쇠(`uid#2` → `uid`).
    base: String,
    uid: String,
    title: String,
    start: Option<i64>,
    end: Option<i64>,
    importance: i64,
    look: i64,
    label: String,
    rail: i64,
    band: i64,
    lane: i64,
}

impl EchoCand {
    /// 창이 읽는 사건 한 줄. `shared`는 여러 자리에 놓인 사건(속 빈 점)이고, `color`는 그 사건이 그려지는 색(든 띠의 색)이다.
    fn row(&self, shared: bool, color: i64) -> Value {
        json!({"id":self.id,"uid":self.base,"place":self.uid,"title":self.title,
            "when":when_text(self.start, self.end, &self.label),"start":self.start,"end":self.end,
            "color":color,"treaty":self.look & TREATY != 0,"importance":self.importance,
            "prec":prec_text(self.rail),"shared":shared || self.look & SHARED != 0,"member":""})
    }
}

/// 메아리 목록의 한 줄 — 어느 자리를 보이고, 어느 사건 번호들이 그 줄에 딸렸는가.
/// `all`은 그 사건의 **모든 자리**(cands의 자리)이고 `함께 · 〈나라〉` 꼬리표를 짓는 데 쓴다.
struct EchoRow { at: usize, all: Vec<usize>, ids: Vec<i64>, others: usize, kids: i64, dropped: bool }

/// 여러 자리에 놓인 사건에서 그 자리의 순번 — 내보내기가 둘째 자리부터 `uid#1`로 적는다(첫 자리는 0).
/// `함께 · 〈나라〉`의 차례를 지금 연표의 `placements` 차례와 맞추는 데 쓴다.
fn place_index(uid: &str) -> i64 {
    uid.split_once('#').and_then(|(_, tail)| tail.parse().ok()).unwrap_or(0)
}

/// 사건의 `look` 16비트 — 조약(계약 6-6).
const TREATY: i64 = 1 << 16;
/// 사건의 `look` 17비트 — 공동 사건(여러 나라가 함께 겪음).
const SHARED: i64 = 1 << 17;
/// 사건의 `look` 18비트 — 공동 사건의 **다른 자리**(첫 자리가 아닌 placements).
const PAIR: i64 = 1 << 18;
/// 사건의 `look` 19비트 — 하위 사건.
const CHILD: i64 = 1 << 19;

/// CSV 한 칸: 늘 따옴표로 감싸고 따옴표는 겹쳐 쓴다(계약 7-4 · 명세 06의 ㈐ 21).
fn csv_field(out: &mut String, text: &str) {
    out.push('"');
    for ch in text.chars() {
        if ch == '"' {
            out.push('"');
        }
        out.push(ch);
    }
    out.push('"');
}

/// 글자 배열을 이어 붙인다(태그 …). 배열이 아니면 빈 글자.
fn join_text(value: &Value, glue: &str) -> String {
    value.as_array().map(|list| list.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(glue)).unwrap_or_default()
}

/// 다른 견해(이설) 목록을 한 칸에 적는 글 — 지금 연표의 `HT.altText`가 만드는 글에서 **딱지(label)만** 이어 붙인다.
/// 날짜까지 풀어 적으려면 모델의 통설 값이 있어야 해서, 여기서는 이름만 ' / '로 잇는다.
fn alt_text(value: &Value) -> String {
    let Some(list) = value.as_array() else { return String::new() };
    let parts: Vec<String> = list
        .iter()
        .filter_map(|a| {
            let label = a["label"].as_str().unwrap_or("");
            let note = a["note"].as_str().unwrap_or("");
            match (label.is_empty(), note.is_empty()) {
                (true, true) => None,
                (true, false) => Some(note.to_owned()),
                (false, true) => Some(label.to_owned()),
                (false, false) => Some(format!("{label} — {note}")),
            }
        })
        .collect();
    parts.join(" / ")
}

fn csv_line(fields: &[String]) -> String {
    let mut line = String::new();
    for (at, field) in fields.iter().enumerate() {
        if at > 0 {
            line.push(',');
        }
        csv_field(&mut line, field);
    }
    line.push_str("\r\n");
    line
}

impl Store {
    /// 켠 자료집 목록을 `json_each`에 넘길 글로. `packs`가 없으면 저장소의 모든 자료집이다.
    fn packs_json(&self, q: &Value) -> Result<String> {
        if let Some(list) = q["packs"].as_array() {
            let mut ids = Vec::with_capacity(list.len());
            for v in list {
                ids.push(v.as_i64().ok_or("자료집 번호가 정수가 아닙니다")?);
            }
            return Ok(serde_json::to_string(&ids)?);
        }
        let mut stmt = self.db.prepare("SELECT id FROM packs ORDER BY id")?;
        let ids: Vec<i64> = stmt.query_map([], |r| r.get(0))?.collect::<std::result::Result<_, _>>()?;
        Ok(serde_json::to_string(&ids)?)
    }

    /// 이름 검색용 표가 이 저장소에 있는가(스키마 3을 넓히기 전에 만든 저장소에는 없다).
    fn names_ready(&self) -> Result<bool> {
        Ok(self.db.query_row("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='names'", [], |r| r.get::<_, i64>(0))? > 0)
    }

    /// 이름 표에 찾을 글 열(`names.hay`)이 있는가 — 형식 3을 잇기 전에 만든 저장소에는 없다(판 '3'은 같다).
    /// 없으면 넓힌 검색은 예전 규칙(이름 · 곁글 · 제목 · 설명만, 예전 차례) 그대로 답한다. 부를 때마다 본다(`Store`에 두지 않는다).
    fn names_hay(&self) -> Result<bool> {
        Ok(self.db.prepare("SELECT 1 FROM pragma_table_info('names') WHERE name='hay'")?.exists([])?)
    }

    /// 사건의 찾을 글 표(`event_hay`)가 있는가 — `names.hay`와 함께 생긴다.
    fn event_hay_ready(&self) -> Result<bool> {
        Ok(self.db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='event_hay'")?.exists([])?)
    }

    /// 연표에서 누른 띠 · 사건의 번호 → 항목 기록의 열쇠.
    /// `kind`는 항목 기록에 적힌 종류(없으면 `period` · `event`)다.
    pub fn uid_of(&self, q: &Value) -> Result<Value> {
        let id = num(q, "id")?;
        let uid: String = match q["kind"].as_str().unwrap_or("") {
            "band" => self.db.query_row("SELECT uid FROM periods WHERE id=?1", [id], |r| r.get(0)).map_err(|_| "그 번호의 띠가 없습니다")?,
            "event" => self.db.query_row("SELECT uid FROM events WHERE id=?1", [id], |r| r.get(0)).map_err(|_| "그 번호의 사건이 없습니다")?,
            _ => return Err("kind는 band 또는 event입니다".into()),
        };
        if uid.is_empty() {
            return Err("그 항목에는 기록의 이름(uid)이 없습니다".into());
        }
        let kind: String = self.db.query_row("SELECT kind FROM entities WHERE uid=?1", [&uid], |r| r.get(0))
            .unwrap_or_else(|_| if q["kind"] == "band" { "period".to_owned() } else { "event".to_owned() });
        Ok(json!({"uid":uid,"kind":kind}))
    }

    /// 항목 기록의 열쇠 → 연표에서의 자리와 줄. 없는 이름은 모두 null(빈 결과)이다.
    pub fn id_of(&self, q: &Value) -> Result<Value> {
        let uid = q["uid"].as_str().ok_or("항목 이름 누락")?;
        let band: Option<(i64, i64, i64, i64)> = self.db
            .query_row("SELECT id,row,start,end FROM periods WHERE uid=?1 ORDER BY id LIMIT 1", [uid], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
            .ok();
        let event: Option<(i64, i64, Option<i64>, Option<i64>)> = self.db
            // uid<>''는 부분 색인(events_uid)을 타게 하는 조건이다 — 이름이 없는 사건은 애초에 찾을 것이 아니다.
            .query_row("SELECT id,lane,start,end FROM events WHERE uid=?1 AND uid<>'' ORDER BY id LIMIT 1", [uid], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
            .ok();
        // 줄은 열쇠로 읽었다 — 답은 자리(계획 P4).
        let (row, start, end) = match (&band, &event) {
            (Some(b), _) => (Some(self.rows.pos(b.1)), Some(b.2), Some(b.3)),
            (None, Some(e)) => (Some(self.rows.pos(e.1)), e.2, e.3),
            _ => (None, None, None),
        };
        Ok(json!({"band":band.map(|b| b.0),"event":event.map(|e| e.0),"row":row,"start":start,"end":end}))
    }

    /// 이름 묶음 → 연표에서의 번호와 자리. 검색 강조 · 기간 조명이 uid 묶음을 타일의 번호로 한 번에 바꿀 때 쓴다
    /// (`id_of`를 2000번 부르지 않게). 없는 이름은 빼고 입력 순서대로 준다.
    pub fn ids_of(&self, q: &Value) -> Result<Value> {
        let list = q["uids"].as_array().ok_or("항목 이름 목록(uids) 누락")?;
        if list.len() > 2000 {
            return Err("이름 묶음은 한 번에 2000개까지 묻습니다".into());
        }
        let mut wanted = Vec::with_capacity(list.len());
        for v in list {
            wanted.push(v.as_str().ok_or("항목 이름이 글자가 아닙니다")?.to_owned());
        }
        let names = serde_json::to_string(&wanted)?;
        // 같은 이름이 여럿이면 번호가 작은 것 하나만(바탕 문화의 둘째 줄부터는 `uid#u<줄 번호>`라 겹치지 않는다).
        // 줄은 열쇠로 읽었다 — 답은 자리(계획 P4).
        let gather = |sql: &str| -> Result<HashMap<String, Value>> {
            let mut stmt = self.db.prepare(sql)?;
            let mut rows = stmt.query([&names])?;
            let mut found: HashMap<String, Value> = HashMap::new();
            while let Some(r) = rows.next()? {
                let uid: String = r.get(0)?;
                found.entry(uid.clone()).or_insert_with(|| json!({"uid":uid,"id":r.get::<_,i64>(1).unwrap_or(0),"row":self.rows.pos(r.get::<_,i64>(2).unwrap_or(-1)),
                    "start":r.get::<_,Option<i64>>(3).unwrap_or(None),"end":r.get::<_,Option<i64>>(4).unwrap_or(None)}));
            }
            Ok(found)
        };
        let bands = gather("SELECT uid,id,row,start,end FROM periods WHERE uid IN (SELECT value FROM json_each(?1)) ORDER BY id")?;
        let events = gather("SELECT uid,id,lane,start,end FROM events WHERE uid IN (SELECT value FROM json_each(?1)) AND uid<>'' ORDER BY id")?;
        let pick = |found: &HashMap<String, Value>| -> Vec<Value> { wanted.iter().filter_map(|uid| found.get(uid).cloned()).collect() };
        Ok(json!({"bands":pick(&bands),"events":pick(&events)}))
    }

    /// 문서 대문(2026-10-16 감독 "문서 한번에 나란히 볼 수 있게 하는 대문"): 켠 자료집의 **본문이 있는** 문서를 한 번에.
    /// 하위 문서는 따로 싣지 않고 바탕 문서의 `subs`(수)로 — 대문에서 열면 문서 창의 칩으로 간다. 본문이 없는 문서(중간 단계 ·
    /// 고리의 목적지)도 뺀다. 문서 기록(`doc:<열쇠>`)은 내보내기가 이미 실어 두었으므로 저장소를 다시 짓지 않아도 된다.
    /// 갈래(`group`): 열쇠의 앞머리(track · people · category · house · cell · view · map · surname · place)가 먼저,
    /// 항목 문서는 그 항목 기록의 종류(period · organ …) · 사건이면 event · 모르면 item. `head`는 본문 앞 320자(문법 그대로 — 화면이 푼다).
    pub fn doc_list(&self, q: &Value) -> Result<Value> {
        const PREFIXES: [&str; 9] = ["track", "people", "category", "house", "cell", "view", "map", "surname", "place"];
        let packs = self.packs_json(q)?;
        let mut stmt = self.db.prepare(
            "SELECT d.json, coalesce((SELECT k.kind FROM entities k WHERE k.uid=json_extract(d.json,'$.uid') AND k.kind<>'doc'),\
             CASE WHEN EXISTS(SELECT 1 FROM events e WHERE e.uid<>'' AND e.uid=json_extract(d.json,'$.uid')) THEN 'event' END,'') \
             FROM entities d WHERE d.kind='doc' AND d.pack IN (SELECT value FROM json_each(?1)) ORDER BY d.uid",
        )?;
        let mut rows = stmt.query([packs])?;
        let mut items = Vec::new();
        while let Some(r) = rows.next()? {
            let text: String = r.get(0)?;
            let kind: String = r.get(1)?;
            let Ok(doc) = serde_json::from_str::<Value>(&text) else { continue };
            let body = doc["body"].as_str().unwrap_or("");
            if body.is_empty() || doc["empty"].as_i64() == Some(1) || doc.get("sub").is_some_and(|s| !s.is_null()) {
                continue;
            }
            let key = doc["key"].as_str().unwrap_or("");
            let head = key.split_once(':').map(|(h, _)| h).filter(|h| PREFIXES.contains(h));
            let group = match (head, kind.as_str()) {
                (Some(h), _) => h,
                (None, "") => "item",
                (None, k) => k,
            };
            let mut one = json!({"key":key,"title":doc["title"],"group":group,"head":body.chars().take(320).collect::<String>()});
            for name in ["meta", "uid", "span", "pack", "at"] {
                if !doc[name].is_null() {
                    one[name] = doc[name].clone();
                }
            }
            if let Some(n) = doc["subs"].as_array().map(Vec::len).filter(|n| *n > 0) {
                one["subs"] = json!(n);
            }
            items.push(one);
        }
        Ok(json!({"count":items.len(),"items":items}))
    }

    /// 목록 줄들을 한 번에(승계 상대 · 구성원 …). 없는 것은 빼고 입력 순서대로 돌려준다.
    pub fn entities_many(&self, q: &Value) -> Result<Value> {
        let list = q["uids"].as_array().ok_or("항목 이름 목록(uids) 누락")?;
        if list.len() > 100 {
            return Err("항목 기록은 한 번에 100개까지 묻습니다".into());
        }
        let mut wanted = Vec::with_capacity(list.len());
        for v in list {
            wanted.push(v.as_str().ok_or("항목 이름이 글자가 아닙니다")?.to_owned());
        }
        // 공동 사건의 둘째 자리(`…#1`)와 여러 줄에 깔린 바탕 문화(`…#u3`)는 제 기록이 없다 — 밑동(`#` 앞)도 함께 찾는다.
        let mut asked: Vec<String> = wanted.clone();
        asked.extend(wanted.iter().filter_map(|uid| uid_stem(uid).map(str::to_owned)));
        let mut found: HashMap<String, (String, String)> = HashMap::new();
        {
            let mut stmt = self.db.prepare("SELECT uid,kind,json FROM entities WHERE uid IN (SELECT value FROM json_each(?1))")?;
            let mut rows = stmt.query([serde_json::to_string(&asked)?])?;
            while let Some(r) = rows.next()? {
                found.insert(r.get(0)?, (r.get(1)?, r.get(2)?));
            }
        }
        let mut out = Vec::new();
        for uid in &wanted {
            let slot = found.get(uid).or_else(|| uid_stem(uid).and_then(|stem| found.get(stem)));
            if let Some((kind, json)) = slot {
                out.push(json!({"uid":uid,"kind":kind,"json":json}));
            }
        }
        Ok(Value::Array(out))
    }

    /// 넓힌 검색: 사건의 본문 색인 + 이름 표(항목 기록의 이름 · 띠 안 칸 · 날짜 칸).
    /// `kinds`가 없으면 2단계의 옛 모양(사건만)을 그대로 돌려준다 — 그 길은 `Store::search`다.
    pub fn search_wide(&self, q: &Value) -> Result<Value> {
        let text = q["text"].as_str().unwrap_or("");
        if text.chars().count() > 64 {
            return Err("검색어는 64자까지 입력하세요".into());
        }
        let limit = limit_of(q, 60, 200)?;
        let after = after_of(q)?;
        let mut kinds: Vec<String> = Vec::new();
        for v in q["kinds"].as_array().ok_or("찾을 갈래(kinds) 누락")? {
            let kind = v.as_str().ok_or("찾을 갈래가 글자가 아닙니다")?;
            if !SEARCH_KINDS.contains(&kind) {
                return Err(format!("모르는 갈래입니다: {kind} (쓸 수 있는 것: {})", SEARCH_KINDS.join(" · ")).into());
            }
            if !kinds.iter().any(|k| k == kind) {
                kinds.push(kind.to_owned());
            }
        }
        let words: Vec<String> = text.split_whitespace().map(str::to_lowercase).collect();
        let terms = crate::grams(&words.join(" ")).join(" AND ");
        if words.is_empty() || terms.is_empty() || kinds.is_empty() {
            return Ok(json!({"items":[],"next":after,"has_more":false}));
        }
        let packs = self.packs_json(q)?;
        let want_events = kinds.iter().any(|k| k == "event" || k == "treaty");
        let name_kinds: Vec<&String> = kinds.iter().filter(|k| *k != "event" && *k != "treaty").collect();
        if !name_kinds.is_empty() && !self.names_ready()? {
            return Err("이 저장소에는 이름 표(names)가 없습니다 — 3단계 도구로 다시 가져오세요".into());
        }
        let filter = self.filter_of(q)?;
        let (event_keep, row_keep, band_keep) = match &filter {
            Some(f) => (f.event_keep("e"), f.row_keep("n.row"), f.band_keep("np")),
            None => (String::new(), String::new(), String::new()),
        };
        // 이름 표의 줄은 띠(정권 · 문화 …)이거나 그 띠에서 자리를 빌린 것이다 — 꺼진 띠와 꺼진 줄은 찾지 않는다(명세 ㈐-14).
        let name_keep = if band_keep.is_empty() {
            row_keep
        } else {
            format!("{row_keep} AND NOT EXISTS(SELECT 1 FROM periods np WHERE np.uid=n.uid AND np.uid<>''{})", band_keep.replacen(" AND NOT ", " AND ", 1))
        };
        let cell_ref = if self.names_cell_ref { "n.cell_ref" } else { "''" };
        // 찾을 글(형식 3)이 있는 저장소인가. 없으면 아래 둘 다 예전 SQL · 예전 차례 그대로다(옛 저장소는 예전과 같은 답).
        let hay = self.names_hay()?;
        let mut args: Vec<SqlValue> = Vec::new();
        let mut parts: Vec<String> = Vec::new();
        if want_events && !hay {
            let conds: String = words.iter().map(|_| " AND instr(lower(e.title||' '||e.body),?)>0".to_owned()).collect();
            parts.push(format!(
                "SELECT 'event' AS k,e.uid AS u,e.title AS nm,'' AS sb,NULL AS cl,e.start AS st,e.end AS en,e.lane AS rw,COALESCE(p.color,0) AS co,e.label AS lb,e.id AS iv,t.name AS tn,'' AS cr,e.rail AS pr \
                 FROM search s JOIN events e ON e.id=s.rowid LEFT JOIN periods p ON p.id=e.band JOIN rows r ON r.id=e.lane JOIN tracks t ON t.id=r.track \
                 WHERE search MATCH ? AND e.pack IN (SELECT value FROM json_each(?)){conds}{event_keep}"
            ));
            args.push(terms.into());
            args.push(packs.clone().into());
            args.extend(words.iter().map(|w| SqlValue::from(w.clone())));
        } else if want_events {
            // 본문 색인에는 사건마다 제목 · 설명의 줄(rowid = 사건 번호)과 다른 이름의 덧줄(rowid = −사건 번호)이 있다.
            // 낱말 하나는 띄어쓰기가 없어 두 줄 가운데 한쪽에 통째로 들므로 **낱말마다** 따로 맞춰 사건 번호로 모은다
            // (낱말 둘이 제목과 덧줄에 갈라 들어도 찾힌다 — 지금 연표는 한 찾을 글에서 맞춘다). 한 사건은 한 번만 나온다.
            let narrow: String = words.iter().map(|_| " AND e.id IN (SELECT abs(rowid) FROM search WHERE search MATCH ?)".to_owned()).collect();
            let event_hay = if self.event_hay_ready()? { EVENT_HAY_SQL } else { EVENT_HAY_JSON_SQL };
            let conds: String = words.iter().map(|_| format!(" AND (instr(lower(e.title||' '||e.body),?)>0 OR instr({event_hay},?)>0)")).collect();
            parts.push(format!(
                "SELECT 'event' AS k,e.uid AS u,e.title AS nm,'' AS sb,NULL AS cl,e.start AS st,e.end AS en,e.lane AS rw,COALESCE(p.color,0) AS co,e.label AS lb,e.id AS iv,t.name AS tn,'' AS cr,e.rail AS pr,0 AS ri \
                 FROM events e LEFT JOIN periods p ON p.id=e.band JOIN rows r ON r.id=e.lane JOIN tracks t ON t.id=r.track \
                 WHERE e.pack IN (SELECT value FROM json_each(?)){narrow}{conds}{event_keep}"
            ));
            args.push(packs.clone().into());
            args.extend(words.iter().map(|w| SqlValue::from(crate::grams(w).join(" AND "))));
            for w in &words {
                args.push(w.clone().into());
                args.push(w.clone().into());
            }
        }
        if !name_kinds.is_empty() {
            let holes = name_kinds.iter().map(|_| "?").collect::<Vec<_>>().join(",");
            // 찾을 글은 이미 소문자다 — 이름 · 곁글만 lower()를 거친다(긴 글을 낱말마다 다시 바꾸지 않게).
            let (conds, more): (String, &str) = if hay {
                (words.iter().map(|_| " AND (instr(lower(n.name||' '||n.sub),?)>0 OR instr(n.hay,?)>0)".to_owned()).collect(), ",n.id AS ri")
            } else {
                (words.iter().map(|_| " AND instr(lower(n.name||' '||n.sub),?)>0".to_owned()).collect(), "")
            };
            parts.push(format!(
                "SELECT n.kind AS k,n.uid AS u,n.name AS nm,n.sub AS sb,n.cell AS cl,n.start AS st,n.end AS en,n.row AS rw,n.color AS co,'' AS lb,NULL AS iv,COALESCE(t.name,'') AS tn,{cell_ref} AS cr,0 AS pr{more} \
                 FROM names n LEFT JOIN rows r ON r.id=n.row LEFT JOIN tracks t ON t.id=r.track \
                 WHERE n.pack IN (SELECT value FROM json_each(?)) AND n.kind IN ({holes}){conds}{name_keep}"
            ));
            args.push(packs.into());
            args.extend(name_kinds.iter().map(|k| SqlValue::from((*k).clone())));
            for w in &words {
                args.push(w.clone().into());
                if hay {
                    args.push(w.clone().into());
                }
            }
        }
        let union = parts.join(" UNION ALL ");
        let count = |args: &[SqlValue]| -> Result<i64> {
            let mut stmt = self.db.prepare(&format!("SELECT count(*) FROM ({union})"))?;
            Ok(stmt.query_row(rusqlite::params_from_iter(args.iter()), |r| r.get(0))?)
        };
        // 통틀어 몇 건인가(`total`) — 찾는 쪽이 'n건 찾음 (앞의 60건만 표시)'을 적을 때 쓴다.
        // 옛 저장소는 예전처럼 따로 세고, 찾을 글이 있는 저장소는 한 번 훑으며 함께 센다(같은 조건을 두 번 맞추지 않게 —
        // 찾을 글로 후보가 늘어난 만큼 검색 한 번이 느려지지 않도록). 쪽이 비면(끝을 넘어 물으면) 그때만 따로 센다.
        let total_first = if hay { None } else { Some(count(&args)?) };
        let order = if hay { WIDE_ORDER } else { "" };
        let tally = if hay { ",count(*) OVER () AS tot" } else { ",0 AS tot" };
        let sql = format!("SELECT k,u,nm,sb,cl,st,en,rw,co,lb,iv,tn,cr,pr{tally} FROM ({union}) ORDER BY {order}(st IS NULL),st,k,nm,u,iv LIMIT ? OFFSET ?");
        let mut paged = args.clone();
        paged.push((limit + 1).into());
        paged.push(after.into());
        let mut seen_total: Option<i64> = None;
        let mut stmt = self.db.prepare(&sql)?;
        let rows = stmt.query_map(rusqlite::params_from_iter(paged), |r| {
            seen_total = Some(r.get(14)?);
            let (start, end): (Option<i64>, Option<i64>) = (r.get(5)?, r.get(6)?);
            let label: String = r.get(9)?;
            let cell_text: String = r.get(12)?;
            let cell = CellRef { kind: r.get(4)?, text: &cell_text };
            // 줄은 열쇠(사건의 `lane` · 이름 표의 `row`)로 읽었다 — 답은 자리(계획 P4). 줄이 없으면(−1) 그대로 −1 → null.
            Ok(item(&r.get::<_, String>(0)?, &r.get::<_, String>(1)?, &r.get::<_, String>(2)?, &r.get::<_, String>(3)?,
                &cell, r.get(10)?, start, end, self.rows.pos(r.get::<_, Option<i64>>(7)?.unwrap_or(-1)), r.get(8)?, &label, &r.get::<_, String>(11)?,
                prec_text(r.get(13)?)))
        })?.collect::<std::result::Result<Vec<_>, _>>()?;
        let total = match (total_first, seen_total) {
            (Some(total), _) => total,
            (None, Some(total)) => total,
            (None, None) if after == 0 => 0,
            (None, None) => count(&args)?,
        };
        let mut answer = page(rows, after, limit);
        answer["total"] = Value::from(total);
        Ok(answer)
    }

    /// 날짜 검색의 "그때에 걸친 항목": 정권 먼저 · 그다음 칸 · 그다음 가까운 사건.
    /// 보는 때는 `at`(찾는 쪽이 `t`로 불러도 받는다), 범위는 `end`까지이며 걸침은 `시작 ≤ end && 끝 ≥ at`이다.
    /// `kinds`를 주면 그 갈래만 모은다(넓힌 `search`와 같은 이름들).
    pub fn search_year(&self, q: &Value) -> Result<Value> {
        let at = q["at"].as_i64().or_else(|| q["t"].as_i64()).ok_or("정수 입력 누락: at")?;
        let until = q["end"].as_i64().unwrap_or(at);
        if until < at {
            return Err("걸침을 볼 범위가 뒤집혔습니다".into());
        }
        let limit = limit_of(q, 60, 200)?;
        let after = after_of(q)?;
        let packs = self.packs_json(q)?;
        let take = after + limit + 1;
        let kinds: Option<Vec<String>> = match q["kinds"].as_array() {
            None => None,
            Some(list) => {
                let mut chosen = Vec::with_capacity(list.len());
                for v in list {
                    let kind = v.as_str().ok_or("찾을 갈래가 글자가 아닙니다")?;
                    if !SEARCH_KINDS.contains(&kind) {
                        return Err(format!("모르는 갈래입니다: {kind} (쓸 수 있는 것: {})", SEARCH_KINDS.join(" · ")).into());
                    }
                    chosen.push(kind.to_owned());
                }
                Some(chosen)
            }
        };
        let wants = |kind: &str| kinds.as_ref().is_none_or(|list| list.iter().any(|k| k == kind));
        // 띠의 갈래는 항목 기록의 종류(정권 · 기관 · 문화 …)로 갈린다. 고른 갈래는 **SQL에서** 거른다 —
        // 받아 온 뒤에 거르면 limit 안에 남는 것이 하나도 없는 쪽(문화만 잡히는 때 같은)이 빈 답이 되어 버린다.
        let band_kinds: Option<String> = match &kinds {
            None => None,
            Some(list) => Some(serde_json::to_string(&list.iter().filter(|k| !matches!(k.as_str(), "event" | "treaty" | "cell" | "doc")).collect::<Vec<_>>())?),
        };
        let filter = self.filter_of(q)?;
        let (band_keep, cell_band_keep, event_keep) = match &filter {
            Some(f) => (f.band_keep("p"), f.band_keep("p"), f.event_keep("e")),
            None => (String::new(), String::new(), String::new()),
        };
        let mut out: Vec<Value> = Vec::new();
        if band_kinds.as_deref() != Some("[]") {
            let narrow = if band_kinds.is_some() { " AND COALESCE(e.kind,'period') IN (SELECT value FROM json_each(?5))" } else { "" };
            let sql = format!("SELECT p.uid,p.name,p.start,p.end,p.row,p.color,COALESCE(e.kind,'period'),t.name \
                FROM periods p LEFT JOIN entities e ON e.uid=p.uid JOIN rows w ON w.id=p.row JOIN tracks t ON t.id=w.track \
                WHERE p.start<=?1 AND p.end>=?2 AND p.pack IN (SELECT value FROM json_each(?3)){narrow}{band_keep} ORDER BY p.start,p.id LIMIT ?4");
            let mut args: Vec<SqlValue> = vec![until.into(), at.into(), packs.clone().into(), take.into()];
            if let Some(list) = &band_kinds {
                args.push(list.clone().into());
            }
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params_from_iter(args))?;
            while let Some(r) = rows.next()? {
                // 줄은 열쇠로 읽었다 — 답은 자리(아래 칸 · 사건도 같다).
                out.push(item(&r.get::<_, String>(6)?, &r.get::<_, String>(0)?, &r.get::<_, String>(1)?, "", &CellRef::default(), None,
                    Some(r.get(2)?), Some(r.get(3)?), self.rows.pos(r.get(4)?), r.get(5)?, "", &r.get::<_, String>(7)?, "y"));
            }
        }
        if wants("cell") && (out.len() as i64) < take {
            // 띠 안의 칸(지도자 · 내각 · 시기 …). 칸 참조의 번호는 style의 15비트 위에 실려 온다(계약 6-2).
            // 칸 종류 9(직위 줄 더 — 스키마 4 · 계약 1-1)는 3단계 동안 화면이 그리지 않는 칸이라 연도 검색에도 내지 않는다(전체 제약 '앱 화면 1배 ·
            // 새 값은 실리기만'). 4단계가 그 줄을 그릴 때 이 거르기를 걷는다.
            let sql = format!("SELECT p.uid,c.name,c.start,c.end,p.row,CASE WHEN c.color<>0 THEN c.color ELSE p.color END,c.kind,p.name,t.name,c.style \
                FROM cells c JOIN periods p ON p.id=c.period JOIN rows w ON w.id=p.row JOIN tracks t ON t.id=w.track \
                WHERE c.start<=?1 AND c.end>=?2 AND c.kind<>9 AND p.pack IN (SELECT value FROM json_each(?3)){cell_band_keep} ORDER BY c.start,c.kind,c.id LIMIT ?4");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params![until, at, packs, take])?;
            while let Some(r) = rows.next()? {
                let cell: i64 = r.get(6)?;
                let text = strip_cell_ref(cell, r.get(9)?);
                out.push(item("cell", &r.get::<_, String>(0)?, &r.get::<_, String>(1)?, &cell_sub(&r.get::<_, String>(7)?, cell), &CellRef { kind: Some(cell), text: &text }, None,
                    Some(r.get(2)?), Some(r.get(3)?), self.rows.pos(r.get(4)?), r.get(5)?, "", &r.get::<_, String>(8)?, "y"));
            }
        }
        if wants("cell") && (out.len() as i64) < take {
            // 날짜 칸(시대 구분 · 연호 · 도읍 · 배도). 제 줄이 없으므로 row는 null이다.
            let mut stmt = self.db.prepare("SELECT a.name,a.start,a.end,a.color,a.kind,COALESCE(t.name,''),a.seq \
                FROM axis_cells a LEFT JOIN tracks t ON t.id=a.track \
                WHERE a.start<=?1 AND a.end>=?2 AND a.pack IN (SELECT value FROM json_each(?3)) ORDER BY a.start,a.kind,a.id LIMIT ?4")?;
            let mut rows = stmt.query(rusqlite::params![until, at, packs, take])?;
            while let Some(r) = rows.next()? {
                let kind: i64 = r.get(4)?;
                let cell: i64 = 100 + kind;
                let track: String = r.get(5)?;
                let text = axis_cell_ref(kind, r.get(6)?);
                out.push(item("cell", "", &r.get::<_, String>(0)?, &cell_sub(&track, cell), &CellRef { kind: Some(cell), text: &text }, None,
                    Some(r.get(1)?), Some(r.get(2)?), -1, r.get(3)?, "", &track, "y"));
            }
        }
        if (wants("event") || wants("treaty")) && (out.len() as i64) < take {
            // 사건: 보는 때에서 가까운 순. 공간 색인으로 먼저 좁힌다.
            let sql = format!("SELECT e.uid,e.title,e.start,e.end,e.lane,COALESCE(p.color,0),e.label,e.id,t.name,e.rail \
                FROM bounds b JOIN events e ON e.id=b.id LEFT JOIN periods p ON p.id=e.band JOIN rows w ON w.id=e.lane JOIN tracks t ON t.id=w.track \
                WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND e.start<=?3 AND e.end>=?4 AND e.pack IN (SELECT value FROM json_each(?5)){event_keep} \
                ORDER BY abs(e.start-?6),e.importance DESC,e.id LIMIT ?7");
            let mut stmt = self.db.prepare(&sql)?;
            let day = |minute: i64| minute.div_euclid(DAY).clamp(i32::MIN as i64, i32::MAX as i64);
            let mut rows = stmt.query(rusqlite::params![day(until), day(at), until, at, packs, at, take])?;
            while let Some(r) = rows.next()? {
                let label: String = r.get(6)?;
                out.push(item("event", &r.get::<_, String>(0)?, &r.get::<_, String>(1)?, "", &CellRef::default(), Some(r.get(7)?),
                    Some(r.get(2)?), Some(r.get(3)?), self.rows.pos(r.get(4)?), r.get(5)?, &label, &r.get::<_, String>(8)?, prec_text(r.get(9)?)));
            }
        }
        let total = out.len() as i64;
        let rest = out.split_off((after as usize).min(out.len()));
        let mut answer = page(rest, after, limit);
        // 모은 것이 `take`(한 쪽 + 하나)에서 끊겼을 수 있어, 통틀어 몇 건인지는 '적어도 이만큼'이다.
        answer["total"] = Value::from(total);
        Ok(answer)
    }

    /// `band`가 가리키는 띠의 번호들. 정수면 그 하나, 글자면 그 uid의 띠 전부(같은 정권이 띠 조각 여럿일 수 있다).
    /// 글자인데 그 이름의 띠가 하나도 없으면 빈 목록이고, 부르는 쪽은 빈 결과로 답한다.
    fn bands_of(&self, value: &Value) -> Result<Option<Vec<i64>>> {
        match value {
            Value::Null => Ok(None),
            Value::String(uid) => {
                let mut stmt = self.db.prepare_cached("SELECT id FROM periods WHERE uid=?1 ORDER BY id")?;
                let ids: Vec<i64> = stmt.query_map([uid], |r| r.get(0))?.collect::<std::result::Result<_, _>>()?;
                Ok(Some(ids))
            }
            v => Ok(Some(vec![v.as_i64().ok_or("띠(band)는 번호 또는 정권 이름(uid)입니다")?])),
        }
    }

    /// 이 시기의 사건(중요도 큰 순 → 시작 순). 띠(`band` — 번호 또는 정권 uid)나 줄(`row` — 밖으로 보이는 자리) 하나를 준다.
    ///
    /// 답은 두 벌이다 — 2절의 `items`(먼저 정한 모양)와, 상세 창이 읽는 `events` · `more`.
    /// 같은 배열이고, 줄마다 `when`(때 글) · `color`(그려지는 색) · `treaty` · `prec`(날짜 정밀도) ·
    /// `member`(상국 띠 아래에 접혀 숨은 소속의 이름)를 함께 싣는다.
    ///
    /// **걸침은 달력 단위로 잰다**(`span::span_hit` — 지금 연표의 `HT.spanHit`): 연도만 적은 한 해짜리 사건은
    /// 그해 한가운데 한 점으로 보아, 경계 해의 사건이 앞뒤 두 칸의 목록에 모두 들지 않는다.
    ///
    /// **`[lo, hi)`는 반열린 구간이다**(계약 2-1절) — `hi`는 칸의 경계가 생긴 대로 **뒤 칸의 첫 분**이고,
    /// 화면은 `x_cellBounds`의 값을 그대로 보낸다. 양 끝 포함으로 재면 그 분에서 **시작하는** 기간 사건과
    /// 그 분에 놓인 점 사건이 앞뒤 두 칸에 모두 든다.
    pub fn events_in(&self, q: &Value) -> Result<Value> {
        let (lo, hi) = (num(q, "lo")?, num(q, "hi")?);
        if hi < lo {
            return Err("조회 범위 오류".into());
        }
        let limit = limit_of(q, 50, 200)?;
        let after = after_of(q)?;
        let packs = self.packs_json(q)?;
        // 변형에서만 서는 띠(숨은 속국)를 물으면 `events.band`로는 한 줄도 나오지 않는다 — 이사 기록을 거꾸로 읽어 채운다.
        let mut hidden: Vec<i64> = Vec::new();
        let cond = match (self.bands_of(&q["band"])?, q["row"].as_i64()) {
            (Some(bands), _) if bands.is_empty() => return Ok(with_events(page(Vec::new(), after, limit))),
            (Some(bands), _) => {
                hidden = self.variant_band_events(&bands)?;
                let own = if bands.len() == 1 { format!("e.band={}", bands[0]) } else { format!("e.band IN ({})", crate::variant::in_list(&bands)) };
                if hidden.is_empty() { own } else { format!("({own} OR e.id IN ({}))", crate::variant::in_list(&hidden)) }
            }
            // 줄은 자리로 받는다 — 저장소 안의 열쇠로 바꿔 찾는다(없는 자리는 −1이라 빈 결과 · 계획 P4).
            (None, Some(row)) => format!("e.lane={}", self.rows.key(row)),
            _ => return Err("띠(band — 번호 또는 정권 이름)나 줄 번호(row) 하나는 주어야 합니다".into()),
        };
        let mut keep = self.filter_of(q)?.map(|f| f.event_keep("e")).unwrap_or_default();
        // 변형: 켜지 않은 변형의 사건은 없는 것과 같다(계약 2-4절).
        let variants = self.variants_of(q)?;
        if let Some(v) = &variants {
            keep.push_str(&v.keep("e.variant"));
        }
        // 달력 단위로 재면 항목이 단위 하나만큼 밀릴 수 있어 SQL은 그만큼 넓게 긁고, 정확한 판정은 아래에서 한다.
        // 나눠 받기(`after`)도 판정을 지난 줄로 세야 해서 SQL의 LIMIT · OFFSET을 쓰지 않는다 — 필요한 만큼 읽고 멎는다.
        let sql = format!("SELECT e.id,e.uid,e.title,e.start,e.end,e.importance,e.look,e.label,e.rail,COALESCE(p.color,0),e.band FROM events e \
            LEFT JOIN periods p ON p.id=e.band \
            WHERE {cond} AND e.start<=?1 AND e.end>=?2 AND e.pack IN (SELECT value FROM json_each(?3)){keep} \
            ORDER BY e.importance DESC,e.start,e.id");
        let mut stmt = self.db.prepare(&sql)?;
        let mut got = stmt.query(rusqlite::params![hi.saturating_add(span::MAX_UNIT), lo.saturating_sub(span::MAX_UNIT), packs])?;
        let (mut rows, mut ids, mut skipped) = (Vec::new(), Vec::new(), 0i64);
        while let Some(r) = got.next()? {
            let (start, end): (Option<i64>, Option<i64>) = (r.get(3)?, r.get(4)?);
            let (look, rail): (i64, i64) = (r.get(6)?, r.get(8)?);
            if !span::span_hit(start, end, rail, lo, hi) {
                continue;
            }
            if skipped < after {
                skipped += 1;
                continue;
            }
            let (id, band): (i64, i64) = (r.get(0)?, r.get(10)?);
            let label: String = r.get(7)?;
            ids.push((id, band));
            rows.push(json!({"id":id,"uid":r.get::<_,String>(1)?,"title":r.get::<_,String>(2)?,"start":start,
                "end":end,"importance":r.get::<_,i64>(5)?,"look":look,"label":label.clone(),
                "when":when_text(start, end, &label),"color":r.get::<_,i64>(9)?,"treaty":look & TREATY != 0,"prec":prec_text(rail),
                "member":""}));
            if rows.len() as i64 > limit {
                break;
            }
        }
        // 상국 띠 아래에 접혀 숨은 소속의 이름(`소속 · 〈나라〉`). 속국 제 창에서는 붙이지 않는다
        // (지금 연표도 제 것으로 잡힌 자리가 조명의 정권이면 딱지가 빈 글자다 — `js/core.js:783`).
        let on: &[i64] = variants.as_ref().map_or(&[][..], |v| &v.on);
        let member = self.member_of(&ids.iter().map(|(id, _)| *id).collect::<Vec<_>>(), on)?;
        for (at, (id, band)) in ids.iter().enumerate() {
            if let Some((host, name)) = member.get(id) {
                if host == band && !hidden.contains(id) {
                    rows[at]["member"] = Value::from(name.as_str());
                }
            }
        }
        Ok(with_events(page(rows, after, limit)))
    }

    /// 상국 띠 아래에 접혀 숨은 소속의 이름 — 사건 번호 → (상국 띠 번호, 소속 이름).
    ///
    /// 저장소에는 '그 사건이 그려지는 띠'(= 상국)만 있고 그 사건이 실은 어느 속국의 것인지는 적혀 있지 않다.
    /// 그 관계는 **소속 펼치기 변형**(계약 2-4절)에 남아 있다: 그 변형을 켜면 사건이 속국의 줄로 이사하고,
    /// 그 줄에는 변형에서만 서는 속국의 띠가 있다. 그래서 `variant_moves`(kind 2)와 그 도착 줄의 변형 띠를 이으면
    /// '어느 속국의 사건인가'가 나온다. 이미 켜 둔 변형은 속국이 제 줄에 나와 있으므로 딱지를 붙이지 않는다
    /// (지금 연표의 `b.hidden` 조건 — `js/core.js:783`).
    ///
    /// **이사한 줄에 띠가 여럿일 수 있다**: 지금 연표는 한 상국 아래의 속국을 `chainRows`로 **시기가 겹치지 않게
    /// 한 줄에 몰아 넣으므로**(`js/timeline.js:2691`의 `pushMembers`), 줄만 보고 번호가 가장 작은 띠를 고르면
    /// 엉뚱한 속국의 이름이 붙는다. 그래서 **그 사건의 때를 품는 띠**를 먼저 고르고, 품는 것이 없을 때만 번호 순이다.
    fn member_of(&self, ids: &[i64], on: &[i64]) -> Result<HashMap<i64, (i64, String)>> {
        let mut out = HashMap::new();
        if !self.has_variants || ids.is_empty() {
            return Ok(out);
        }
        let skip = if on.is_empty() { String::new() } else { format!(" AND m.variant NOT IN ({})", crate::variant::in_list(on)) };
        let sql = format!("SELECT m.ref,v.band,p.name FROM variant_moves m JOIN variants v ON v.id=m.variant AND v.kind=1 \
            JOIN events e ON e.id=m.ref \
            JOIN periods p ON p.variant=m.variant AND p.row=m.row \
            WHERE m.kind=2 AND m.ref IN ({}){skip} \
            ORDER BY CASE WHEN p.start<=e.start AND p.end>=e.start THEN 0 ELSE 1 END,p.id", crate::variant::in_list(ids));
        let mut stmt = self.db.prepare(&sql)?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            let (event, host, name): (i64, i64, String) = (r.get(0)?, r.get(1)?, r.get(2)?);
            out.entry(event).or_insert((host, name));
        }
        Ok(out)
    }

    /// 변형에서만 서는 띠(`periods.variant<>0` — 상국 띠 아래에 접혀 숨은 속국)가 **제 것**으로 삼는 사건 번호.
    /// [`Self::member_of`]가 만든 짝을 거꾸로 읽은 것이다.
    ///
    /// 저장소의 `events.band`에는 **그려지는 띠**(= 상국)만 적혀 있어, 숨은 속국을 조명하면 제 것이 한 줄도 없었다.
    /// 지금 연표는 사건이 놓인 자리의 정권으로 보아 제 것으로 준다(`js/core.js:783`의 `P === s.uid` 가지 — 변형을
    /// 켰든 껐든 같다). 여기서는 그 변형이 그 띠의 줄로 보낸 사건(`variant_moves` kind 2) 가운데
    /// **그 띠의 구간에 시작이 든 것**을 그 띠의 것으로 센다(한 줄에 속국이 여럿일 수 있어 때를 함께 본다).
    fn variant_band_events(&self, bands: &[i64]) -> Result<Vec<i64>> {
        if !self.has_variants || bands.is_empty() {
            return Ok(Vec::new());
        }
        let sql = format!("SELECT m.ref FROM periods p \
            JOIN variant_moves m ON m.variant=p.variant AND m.row=p.row AND m.kind=2 \
            JOIN events e ON e.id=m.ref \
            WHERE p.id IN ({}) AND p.variant<>0 AND p.start<=e.start AND p.end>=e.start \
            ORDER BY m.ref", crate::variant::in_list(bands));
        let mut stmt = self.db.prepare(&sql)?;
        let ids: Vec<i64> = stmt.query_map([], |r| r.get(0))?.collect::<std::result::Result<_, _>>()?;
        Ok(ids)
    }

    /// 그 띠들이 변형에서만 서는 속국이면, 그것이 접혀 드는 **상국 띠**의 번호.
    ///
    /// 숨은 속국을 비추면 지금 연표는 그 조명을 **상국 띠의 제 조명**으로 적는다(`js/core.js:748`의 `bandKey` —
    /// 띠 열쇠가 `bandOf(uid).band`, 곧 상국이다). 그래야 그 구간에서 상국 제 사건이 메아리로 튀지 않는다.
    fn variant_band_hosts(&self, bands: &[i64]) -> Result<Vec<i64>> {
        if !self.has_variants || bands.is_empty() {
            return Ok(Vec::new());
        }
        let sql = format!("SELECT DISTINCT v.band FROM periods p JOIN variants v ON v.id=p.variant AND v.kind=1 \
            WHERE p.id IN ({}) AND p.variant<>0 AND v.band<>0", crate::variant::in_list(bands));
        let mut stmt = self.db.prepare(&sql)?;
        let ids: Vec<i64> = stmt.query_map([], |r| r.get(0))?.collect::<std::result::Result<_, _>>()?;
        Ok(ids)
    }

    /// 같은 시기 타국(메아리) — 명세 06의 3-4절 · 지금 연표의 `HT.echoEvents` · `HT.echoBandSpans`.
    ///
    /// 창이 연표에 켜는 조명(`spots`)을 받아 **제 것**(조명의 띠에서 그 구간에 걸친 사건)과 **메아리**(같은 시기의 다른 나라)를
    /// 한 번에 셈한다. 연표의 칠과 창의 목록이 같은 답을 써야 해서 자료 처리부에 하나만 둔다.
    ///
    /// 입력 `{"spots":[{"band":띠 번호 또는 "uid":정권 이름,"start":분,"end":분}],"echo"?:true,"limit"?:400,"packs"?,"filter"?,"variants"?}`.
    /// 조명 구간 `[start, end)`는 **반열린 구간**이다(계약 2-1절 · `HT.echoSpans` · `HT.echoBandSpans`와 같은 셈).
    /// 걸침은 지금 연표와 같은 **달력 단위**로 잰다(`span::span_hit` = `HT.spanHit` — 연도만 적은 한 해짜리 사건은
    /// 그해 한가운데 한 점).
    ///
    /// 지금 연표와 다른 곳(계약 2-5절에 같은 목록이 있다): ① 접힌 트랙 · 접힌 줄은 보기 상태라 `folded`가 늘 거짓이다.
    /// ② **소속 펼치기 변형을 켜 두면** 그 변형이 옮긴 사건이 속국뿐 아니라 상국 띠의 제 것으로도 센다 —
    /// 지금 연표는 켠 동안에는 속국 쪽만 준다(`js/core.js:783`의 `b.hidden` 가지).
    pub fn echo(&self, q: &Value) -> Result<Value> {
        let want_echo = match &q["echo"] {
            Value::Null => true,
            v => v.as_bool().ok_or("메아리 켬끔(echo)은 참 또는 거짓입니다")?,
        };
        let limit = limit_of(q, 400, 2000)?;
        let list = q["spots"].as_array().ok_or("조명 목록(spots)이 없습니다")?;
        if list.len() > 200 {
            return Err("조명은 한 번에 200개까지입니다".into());
        }
        // 조명 하나 = (그 띠들, 변형에서만 서는 띠가 제 것으로 삼는 사건 번호, 시작, 끝).
        let mut spots: Vec<(Vec<i64>, Vec<i64>, i64, i64)> = Vec::with_capacity(list.len());
        for s in list {
            let (start, end) = (num(s, "start")?, num(s, "end")?);
            if end < start {
                return Err("조명 구간이 뒤집혔습니다".into());
            }
            let bands = match self.bands_of(&s["band"])? {
                Some(bands) => bands,
                None => self.bands_of(&s["uid"])?.ok_or("조명에 띠 번호(band)나 정권 이름(uid)이 없습니다")?,
            };
            let hidden = self.variant_band_events(&bands)?;
            spots.push((bands, hidden, start, end));
        }
        if spots.is_empty() {
            return Ok(json!({"spans":[],"own":[],"ownUids":[],"echo":[],"echoIds":[],"groups":[],"count":0,"total":0}));
        }
        // 메아리 기간: 겹치거나 맞닿은 조명은 하나로(연표 맨 위의 가는 괄호도 이 구간이다).
        let spans = if want_echo { merge_spans(spots.iter().map(|s| (s.2, s.3)).collect()) } else { Vec::new() };
        let (lo, hi) = (spots.iter().map(|s| s.2).min().unwrap(), spots.iter().map(|s| s.3).max().unwrap());
        // 띠마다의 제 조명 — 메아리 구간에서 빼야 두 번 칠하지 않는다.
        // 숨은 속국의 조명은 **상국 띠의 제 조명**으로도 적는다(`js/core.js:748`의 `bandKey`) — 그래야 그 구간의
        // 상국 제 사건이 '같은 시기 타국'으로 튀지 않는다.
        let mut own_on_band: HashMap<i64, Vec<(i64, i64)>> = HashMap::new();
        for (bands, _, start, end) in &spots {
            let hosts = self.variant_band_hosts(bands)?;
            for band in bands.iter().chain(hosts.iter()) {
                own_on_band.entry(*band).or_default().push((*start, *end));
            }
        }

        let mut keep = self.filter_of(q)?.map(|f| f.event_keep("e")).unwrap_or_default();
        let variants = self.variants_of(q)?;
        if let Some(v) = &variants {
            keep.push_str(&v.keep("e.variant"));
        }
        let packs = self.packs_json(q)?;
        // 훑는 수의 천장: 조명 구간이 터무니없이 넓어도 자료 처리부가 멎지 않게. 중요한 것부터 담는다.
        let scan = (limit * 20).clamp(2_000, 20_000);
        // 걸침을 달력 단위로 재면 항목이 단위 하나만큼 밀릴 수 있어, 미리 거르는 범위를 그만큼 넓힌다(정확한 판정은 아래에서).
        let (wide_lo, wide_hi) = (lo.saturating_sub(span::MAX_UNIT), hi.saturating_add(span::MAX_UNIT));
        // 띠의 색은 살아남은 줄에만 필요하다 — 여기서 `periods`를 잇지 않는다(100만 건에서는 줄마다의 자리 찾기가 값의 거의 전부다).
        let sql = format!("SELECT e.id,e.uid,e.title,e.start,e.end,e.importance,e.look,e.label,e.rail,e.band,e.lane \
            FROM bounds b JOIN events e ON e.id=b.id \
            WHERE b.lo_day<=?2 AND b.hi_day>=?1 AND e.start<=?4 AND e.end>=?3 AND e.pack IN (SELECT value FROM json_each(?5)){keep} \
            ORDER BY e.importance DESC,e.start,e.id LIMIT ?6");
        let mut stmt = self.db.prepare(&sql)?;
        let mut rows = stmt.query(rusqlite::params![wide_lo.div_euclid(crate::DAY), wide_hi.div_euclid(crate::DAY), wide_lo, wide_hi, packs, scan])?;
        let mut cands: Vec<EchoCand> = Vec::new();
        while let Some(r) = rows.next()? {
            let uid: String = r.get(1)?;
            let base = uid.split('#').next().unwrap_or("").to_owned();
            cands.push(EchoCand {
                id: r.get(0)?, base, uid, title: r.get(2)?, start: r.get(3)?, end: r.get(4)?,
                importance: r.get(5)?, look: r.get(6)?, label: r.get(7)?, rail: r.get(8)?,
                band: r.get(9)?, lane: r.get(10)?,
            });
        }
        // 한 사건의 여러 자리(공동 사건)는 같은 열쇠로 묶는다 — 내보내기가 둘째 자리부터 `uid#n`으로 적는다.
        let mut places: HashMap<String, Vec<usize>> = HashMap::new();
        let mut order: Vec<String> = Vec::new();
        for (at, c) in cands.iter().enumerate() {
            let key = if c.base.is_empty() { format!("#{}", c.id) } else { c.base.clone() };
            if !places.contains_key(&key) {
                order.push(key.clone());
            }
            places.entry(key).or_default().push(at);
        }

        // 띠마다의 구간(메아리를 자를 때)과 색(줄의 색)은 한 번만 찾아 둔다.
        let band_span = self.band_spans(&cands)?;
        let color_of = |band: i64| band_span.get(&band).map_or(0, |b| b.2);
        let mut echo_of: HashMap<i64, Vec<(i64, i64)>> = HashMap::new();
        // 걸침은 지금 연표와 같은 달력 단위 셈이다(`HT.spanHit`) — 연도만 적은 사건은 그해 한가운데 한 점.
        let hit = |c: &EchoCand, a: i64, b: i64| span::span_hit(c.start, c.end, c.rail, a, b);

        let mut own: Vec<Value> = Vec::new();
        let mut own_uids: Vec<String> = Vec::new();
        let mut own_at: Vec<usize> = Vec::new();
        // 숨은 속국을 비춰 제 것이 된 사건 — 그 창에서는 `소속 · 〈나라〉` 딱지를 붙이지 않는다.
        let mut own_hidden: Vec<i64> = Vec::new();
        let mut echo_rows: Vec<EchoRow> = Vec::new();
        for key in &order {
            let at = &places[key];
            // 제 것: 사건이 놓인 띠가 조명의 띠이고(또는 조명이 그 사건을 데려가는 숨은 속국이고), 그 조명 구간에 걸린다.
            let mut mine = None;
            for i in at {
                let c = &cands[*i];
                if c.band == 0 {
                    continue;
                }
                for (bands, hidden, start, end) in &spots {
                    let by_hidden = hidden.contains(&c.id);
                    if (bands.contains(&c.band) || by_hidden) && hit(c, *start, *end) {
                        mine = Some(*i);
                        if by_hidden {
                            own_hidden.push(c.id);
                        }
                        break;
                    }
                }
                if mine.is_some() {
                    break;
                }
            }
            if let Some(i) = mine {
                let first = at.iter().copied().find(|j| cands[*j].look & PAIR == 0).unwrap_or(i);
                own.push(cands[first].row(at.len() > 1, color_of(cands[first].band)));
                own_uids.push(cands[first].base.clone());
                // 소속 딱지는 **걸린 자리**의 것이다 — 상국 띠 아래에 숨은 속국의 사건이면 그 속국의 이름이 붙는다.
                own_at.push(i);
                continue;
            }
            if !want_echo {
                continue;
            }
            // 메아리: 그 사건이 그려지는 띠의 [메아리 기간 − 그 띠의 제 조명]을 띠가 있던 구간으로 자른 것에 걸린다.
            let mut hits: Vec<usize> = Vec::new();
            for i in at {
                let c = &cands[*i];
                let ranges = if c.band == 0 {
                    spans.clone()
                } else {
                    echo_of.entry(c.band).or_insert_with(|| {
                        let (bs, be) = band_span.get(&c.band).map_or((i64::MIN, i64::MAX), |b| (b.0, b.1));
                        band_echo_spans(&spans, own_on_band.get(&c.band).map_or(&[][..], Vec::as_slice), bs, be)
                    }).clone()
                };
                if ranges.iter().any(|(a, b)| hit(c, *a, *b)) {
                    hits.push(*i);
                }
            }
            if hits.is_empty() {
                continue;
            }
            let main = hits.iter().copied().find(|j| cands[*j].look & PAIR == 0).unwrap_or(hits[0]);
            echo_rows.push(EchoRow { at: main, all: at.clone(), ids: at.iter().map(|i| cands[*i].id).collect(), others: at.len() - 1, kids: 0, dropped: false });
        }

        // 하위 사건: 부모가 같은 목록에 있으면 부모 줄의 `포함 n`으로 센다.
        self.merge_kids(&cands, &mut echo_rows)?;
        echo_rows.retain(|r| !r.dropped);
        let total = echo_rows.len() as i64;
        echo_rows.truncate(limit as usize);

        // 함께 겪은 다른 자리의 이름(`함께 · 〈나라〉`)과, 상국 띠 아래에 숨은 소속의 이름(`소속 · 〈나라〉`).
        let on: &[i64] = variants.as_ref().map_or(&[][..], |v| &v.on);
        let with_names = self.with_names(&cands, &echo_rows)?;
        let member = self.member_of(&own_at.iter().map(|i| cands[*i].id).collect::<Vec<_>>(), on)?;
        for (at, i) in own_at.iter().enumerate() {
            if let Some((host, name)) = member.get(&cands[*i].id) {
                if *host == cands[*i].band && !own_hidden.contains(&cands[*i].id) {
                    own[at]["member"] = Value::from(name.as_str());
                }
            }
        }

        // 묶음: 띠마다(띠가 없으면 트랙마다) 모아 연표 위에서 아래 차례로.
        let answer = self.echo_groups(&cands, &echo_rows, &band_span, &with_names)?;
        let echo_ids: Vec<i64> = echo_rows.iter().flat_map(|r| r.ids.clone()).collect();
        let echo_list: Vec<Value> = echo_rows
            .iter()
            .enumerate()
            .map(|(at, r)| {
                let mut row = cands[r.at].row(r.others > 0, color_of(cands[r.at].band));
                row["with"] = Value::from(with_names[at].clone());
                row
            })
            .collect();
        Ok(json!({"spans":spans.iter().map(|(a,b)| json!([a,b])).collect::<Vec<_>>(),
            "own":own,"ownUids":own_uids,"echo":echo_list,"echoIds":echo_ids,
            "groups":answer.0,"count":answer.1,"total":total}))
    }

    /// 메아리 줄마다의 `함께 · 〈나라〉` — 그 사건이 함께 놓인 **다른 자리**의 나라 이름을 자리 순서대로.
    /// 이름은 그 자리가 그려지는 띠의 이름이고, 띠가 없는 자리(그 밖 줄)는 그 트랙의 이름이다
    /// (지금 연표는 `pl.polityName || pl.track` — 띠가 없으면 트랙의 **글자 id**가 나오는데, 여기서는 사람이 읽는 이름을 쓴다).
    fn with_names(&self, cands: &[EchoCand], rows: &[EchoRow]) -> Result<Vec<Vec<String>>> {
        let mut out = vec![Vec::new(); rows.len()];
        let others: Vec<(usize, Vec<usize>)> = rows
            .iter()
            .enumerate()
            .filter_map(|(at, r)| {
                let mut list: Vec<usize> = r.all.iter().copied().filter(|i| *i != r.at).collect();
                list.sort_by_key(|i| (place_index(&cands[*i].uid), cands[*i].id));
                (!list.is_empty()).then_some((at, list))
            })
            .collect();
        if others.is_empty() {
            return Ok(out);
        }
        let mut ids: Vec<i64> = others.iter().flat_map(|(_, list)| list.iter().map(|i| cands[*i].band)).filter(|b| *b != 0).collect();
        ids.sort_unstable();
        ids.dedup();
        let mut band_name: HashMap<i64, String> = HashMap::new();
        if !ids.is_empty() {
            let sql = format!("SELECT id,name FROM periods WHERE id IN ({})", crate::variant::in_list(&ids));
            let mut stmt = self.db.prepare(&sql)?;
            let mut got = stmt.query([])?;
            while let Some(r) = got.next()? {
                band_name.insert(r.get(0)?, r.get(1)?);
            }
        }
        let mut lane_name: HashMap<i64, String> = HashMap::new();
        {
            let mut lanes: Vec<i64> = others.iter().flat_map(|(_, list)| list.iter().filter(|i| cands[**i].band == 0).map(|i| cands[*i].lane)).collect();
            lanes.sort_unstable();
            lanes.dedup();
            if !lanes.is_empty() {
                let sql = format!("SELECT r.id,t.name FROM rows r JOIN tracks t ON t.id=r.track WHERE r.id IN ({})", crate::variant::in_list(&lanes));
                let mut stmt = self.db.prepare(&sql)?;
                let mut got = stmt.query([])?;
                while let Some(r) = got.next()? {
                    lane_name.insert(r.get(0)?, r.get(1)?);
                }
            }
        }
        for (at, list) in others {
            out[at] = list
                .iter()
                .map(|i| {
                    let c = &cands[*i];
                    if c.band != 0 { band_name.get(&c.band).cloned() } else { lane_name.get(&c.lane).cloned() }.unwrap_or_default()
                })
                .filter(|name| !name.is_empty())
                .collect();
        }
        Ok(out)
    }

    /// 후보 사건이 든 띠들의 구간 `[시작, 끝]` — 메아리 구간을 그 띠가 있던 때로 자를 때 쓴다.
    /// 돌려주는 값: 띠 번호 → (시작, 끝, 색)
    fn band_spans(&self, cands: &[EchoCand]) -> Result<HashMap<i64, (i64, i64, i64)>> {
        let ids: Vec<i64> = {
            let mut set: Vec<i64> = cands.iter().map(|c| c.band).filter(|b| *b != 0).collect();
            set.sort_unstable();
            set.dedup();
            set
        };
        let mut out = HashMap::new();
        if ids.is_empty() {
            return Ok(out);
        }
        let sql = format!("SELECT id,start,end,color FROM periods WHERE id IN ({})", crate::variant::in_list(&ids));
        let mut stmt = self.db.prepare(&sql)?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            out.insert(r.get(0)?, (r.get(1)?, r.get(2)?, r.get(3)?));
        }
        Ok(out)
    }

    /// 하위 사건을 부모 줄의 `포함 n`으로 옮긴다(부모가 같은 목록에 있을 때만).
    fn merge_kids(&self, cands: &[EchoCand], rows: &mut [EchoRow]) -> Result<()> {
        let kids: Vec<i64> = rows.iter().filter(|r| cands[r.at].look & CHILD != 0).map(|r| cands[r.at].id).collect();
        if kids.is_empty() {
            return Ok(());
        }
        // 구역 32(하위 사건의 부모 기간)가 자식마다 하나씩 있고 `name`이 부모의 uid다(계약 6-7).
        let sql = format!("SELECT ref,name FROM items WHERE section=32 AND ref IN ({})", crate::variant::in_list(&kids));
        let mut parent_of: HashMap<i64, String> = HashMap::new();
        {
            let mut stmt = self.db.prepare(&sql)?;
            let mut got = stmt.query([])?;
            while let Some(r) = got.next()? {
                parent_of.insert(r.get(0)?, r.get(1)?);
            }
        }
        let mut at_of: HashMap<String, usize> = HashMap::new();
        for (at, r) in rows.iter().enumerate() {
            at_of.entry(cands[r.at].base.clone()).or_insert(at);
        }
        let moves: Vec<(usize, usize)> = rows.iter().enumerate()
            .filter_map(|(at, r)| parent_of.get(&cands[r.at].id).and_then(|uid| at_of.get(uid)).map(|parent| (at, *parent)))
            .filter(|(at, parent)| at != parent)
            .collect();
        for (at, parent) in moves {
            rows[parent].kids += 1;
            rows[at].dropped = true;
        }
        Ok(())
    }

    /// 메아리 줄을 나라별 묶음으로 모은다(연표 위에서 아래 차례). 돌려주는 값: (묶음 목록, 줄 수)
    fn echo_groups(&self, cands: &[EchoCand], rows: &[EchoRow], band_span: &HashMap<i64, (i64, i64, i64)>, with_names: &[Vec<String>]) -> Result<(Vec<Value>, i64)> {
        // 띠와 줄의 자리 · 이름
        let bands: Vec<i64> = {
            let mut set: Vec<i64> = rows.iter().map(|r| cands[r.at].band).filter(|b| *b != 0).collect();
            set.sort_unstable();
            set.dedup();
            set
        };
        let mut band_info: HashMap<i64, (String, String, i64, i64)> = HashMap::new(); // 띠 → (uid, 이름, 색, 줄)
        if !bands.is_empty() {
            let sql = format!("SELECT id,uid,name,color,row FROM periods WHERE id IN ({})", crate::variant::in_list(&bands));
            let mut stmt = self.db.prepare(&sql)?;
            let mut got = stmt.query([])?;
            while let Some(r) = got.next()? {
                band_info.insert(r.get(0)?, (r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?));
            }
        }
        let lanes: Vec<i64> = {
            let mut set: Vec<i64> = rows.iter().map(|r| cands[r.at].lane).collect();
            set.extend(band_info.values().map(|v| v.3));
            set.sort_unstable();
            set.dedup();
            set
        };
        let mut track_of: HashMap<i64, i64> = HashMap::new();
        if !lanes.is_empty() {
            let sql = format!("SELECT id,track FROM rows WHERE id IN ({})", crate::variant::in_list(&lanes));
            let mut stmt = self.db.prepare(&sql)?;
            let mut got = stmt.query([])?;
            while let Some(r) = got.next()? {
                track_of.insert(r.get(0)?, r.get(1)?);
            }
        }
        // 트랙 → (이름, 색, 마지막 줄의 자리). 트랙의 줄 열쇠는 이어진 덩이라 가장 큰 열쇠가 곧 마지막 자리다(계획 P4).
        let mut track_info: HashMap<i64, (String, i64, i64)> = HashMap::new();
        {
            let mut stmt = self.db.prepare("SELECT t.id,t.name,t.color,COALESCE(max(r.id),-1) FROM tracks t LEFT JOIN rows r ON r.track=t.id GROUP BY t.id")?;
            let mut got = stmt.query([])?;
            while let Some(r) = got.next()? {
                track_info.insert(r.get(0)?, (r.get(1)?, r.get(2)?, self.rows.pos(r.get(3)?)));
            }
        }
        // 묶음 모으기. 묶음의 차례는 연표 위에서 아래 — 띠는 그 줄의 **자리**, 띠 없는 사건은 그 트랙 마지막 자리 + 0.5(줄 열쇠는 안에서만 쓴다).
        let mut keys: Vec<String> = Vec::new();
        let mut groups: HashMap<String, (f64, Value, Vec<Value>)> = HashMap::new();
        for (seat, r) in rows.iter().enumerate() {
            let c = &cands[r.at];
            let (key, order, head) = if c.band != 0 {
                let (uid, name, color, row) = band_info.get(&c.band).cloned().unwrap_or_default();
                let track = track_of.get(&row).copied().unwrap_or(-1);
                let (track_name, _, _) = track_info.get(&track).cloned().unwrap_or_default();
                (format!("b:{}", c.band), self.rows.pos(row) as f64,
                 json!({"track":track,"track_name":track_name,"band":c.band,"uid":uid,"name":name,"color":color,"folded":false}))
            } else {
                let track = track_of.get(&c.lane).copied().unwrap_or(-1);
                let (track_name, color, last) = track_info.get(&track).cloned().unwrap_or_default();
                (format!("t:{track}"), last as f64 + 0.5,
                 json!({"track":track,"track_name":track_name.clone(),"band":0,"uid":"","name":track_name,"color":color,"folded":false}))
            };
            let slot = groups.entry(key.clone()).or_insert_with(|| {
                keys.push(key.clone());
                (order, head, Vec::new())
            });
            let own = band_span.get(&c.band).map_or(0, |b| b.2);
            let mut row = c.row(r.others > 0, own);
            row["kids"] = Value::from(r.kids);
            row["with"] = Value::from(with_names[seat].clone());
            if own == 0 {
                // 띠가 없는 사건(그 밖 줄)은 제 트랙의 색으로 그린다.
                row["color"] = slot.1["color"].clone();
            }
            slot.2.push(row);
        }
        keys.sort_by(|a, b| {
            let (x, y) = (&groups[a], &groups[b]);
            x.0.partial_cmp(&y.0).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.cmp(b))
        });
        let mut out = Vec::with_capacity(keys.len());
        let mut count = 0i64;
        for key in &keys {
            let (_, head, mut list) = groups.remove(key).unwrap();
            list.sort_by_key(|e| (e["start"].as_i64().unwrap_or(i64::MAX), -e["importance"].as_i64().unwrap_or(0)));
            count += list.len() as i64;
            let mut group = head;
            group["count"] = Value::from(list.len());
            group["events"] = Value::Array(list);
            out.push(group);
        }
        Ok((out, count))
    }

    /// 같은 해 보기: 그때에 걸친 띠 · 칸 · 사건을 트랙마다 모아 준다(사건은 트랙마다 12개 · 중요도 큰 순).
    ///
    /// 답은 두 벌이다 — 2절의 `tracks`(먼저 정한 모양)와, 도구 부품이 읽는 `eras` · `phases` · `figures` · `events`.
    /// 둘은 같은 자료를 달리 묶은 것이라 함께 실어도 어긋나지 않는다(명세 7-1의 창 차례가 곧 뒤쪽 묶음의 차례다).
    /// `window`(분)는 사건만 넓혀 보는 앞뒤 범위다.
    pub fn same_year(&self, q: &Value) -> Result<Value> {
        let at = q["at"].as_i64().or_else(|| q["t"].as_i64()).ok_or("정수 입력 누락: at")?;
        let until = q["end"].as_i64().unwrap_or(at);
        if until < at {
            return Err("같은 해 보기의 범위가 뒤집혔습니다".into());
        }
        let window = match &q["window"] {
            Value::Null => 0,
            v => {
                let n = v.as_f64().ok_or("앞뒤 범위(window)가 수가 아닙니다")? as i64;
                if n < 0 { return Err("앞뒤 범위(window)는 0 이상입니다".into()) } else { n }
            }
        };
        let (wide_lo, wide_hi) = (at.saturating_sub(window), until.saturating_add(window));
        let packs = self.packs_json(q)?;
        let filter = self.filter_of(q)?;
        let (band_keep, event_keep, row_keep) = match &filter {
            Some(f) => (f.band_keep("p"), f.event_keep("e"), f.row_keep("i.row")),
            None => (String::new(), String::new(), String::new()),
        };
        let min_importance = filter.as_ref().map_or(0, |f| f.filter.min_importance);
        let mut tracks: Vec<Value> = Vec::new();
        let mut at_track: HashMap<i64, usize> = HashMap::new();
        let mut track_head: Vec<(i64, String, i64)> = Vec::new();
        {
            let mut stmt = self.db.prepare("SELECT id,name,color FROM tracks WHERE pack IN (SELECT value FROM json_each(?1)) ORDER BY ord,id")?;
            let mut rows = stmt.query([&packs])?;
            while let Some(r) = rows.next()? {
                let id: i64 = r.get(0)?;
                at_track.insert(id, tracks.len());
                let (name, color): (String, i64) = (r.get(1)?, r.get(2)?);
                track_head.push((id, name.clone(), color));
                tracks.push(json!({"track":id,"name":name,"color":color,"bands":[],"cells":[],"events":[]}));
            }
        }
        // 트랙마다 '그때 각 나라는'(eras) · '그때의 시기 구분'(phases) · '그때 활동한 인물'(figures)을 따로 쌓는다.
        let mut eras: Vec<Value> = track_head.iter().map(|(id, name, color)| json!({"track":id,"name":name,"color":color,"periods":[]})).collect();
        let mut figures: Vec<Value> = track_head.iter().map(|(id, name, color)| json!({"track":id,"name":name,"color":color,"figures":[]})).collect();
        let mut phases: Vec<Value> = Vec::new();
        // 띠마다의 (트랙 자리, uid, 이름) — 시기 · 지위 칸을 그 띠에 붙일 때 쓴다.
        let mut band_at: HashMap<i64, (usize, String, String)> = HashMap::new();
        {
            // `form`(스키마 4 · 계약 1-1 — 형식 4의 종류 · 관계 · 정통성 · 중요도 비트)은 열이 없는 옛 저장소에서 0(모름).
            let form = if self.period_form { "p.form" } else { "0" };
            let sql = format!("SELECT r.track,p.id,p.uid,p.name,p.start,p.end,p.look,{form} FROM periods p JOIN rows r ON r.id=p.row \
                WHERE p.start<=?1 AND p.end>=?2 AND p.pack IN (SELECT value FROM json_each(?3)){band_keep} ORDER BY r.track,p.start,p.id");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params![until, at, packs])?;
            while let Some(r) = rows.next()? {
                if let Some(at_row) = at_track.get(&r.get::<_, i64>(0)?).copied() {
                    let (id, uid, name, look): (i64, String, String, i64) = (r.get(1)?, r.get(2)?, r.get(3)?, r.get(6)?);
                    tracks[at_row]["bands"].as_array_mut().unwrap().push(json!({"id":id,"uid":uid,"name":name,
                        "start":r.get::<_,i64>(4)?,"end":r.get::<_,i64>(5)?,"look":look,"form":r.get::<_,i64>(7)?}));
                    // 실재성(hs)은 look 8~10비트 — 전설 · 부정됨은 창에서 옅은 글씨가 된다(명세 7-1).
                    eras[at_row]["periods"].as_array_mut().unwrap().push(json!({"uid":uid,"name":name,"hs":(look >> 8) & 7,"rank":Value::Null}));
                    band_at.insert(id, (at_row, uid, name));
                }
            }
        }
        {
            // 띠 안 칸. 시기 구분(4)과 지위(5)는 창의 제 묶음으로도 간다 — 바뀐 해에는 **뒤 칸**만 남긴다(명세 7-1).
            let sql = format!("SELECT r.track,c.kind,c.name,c.start,c.end,c.period,c.lane,c.style FROM cells c JOIN periods p ON p.id=c.period JOIN rows r ON r.id=p.row \
                WHERE c.start<=?1 AND c.end>=?2 AND p.start<=?1 AND p.end>=?2 AND p.pack IN (SELECT value FROM json_each(?3)){band_keep} \
                ORDER BY r.track,c.kind,c.start,c.id");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params![until, at, packs])?;
            // (띠, 단, 줄) → phases 배열에서의 자리
            let mut phase_at: HashMap<(i64, i64), usize> = HashMap::new();
            while let Some(r) = rows.next()? {
                let Some(at_row) = at_track.get(&r.get::<_, i64>(0)?).copied() else { continue };
                let (kind, name, start, end): (i64, String, i64, i64) = (r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?);
                let (band, lane, style): (i64, i64, i64) = (r.get(5)?, r.get(6)?, r.get(7)?);
                tracks[at_row]["cells"].as_array_mut().unwrap().push(json!({"kind":kind,"name":name,"start":start,"end":end,"band":band}));
                let Some((_, uid, band_name)) = band_at.get(&band) else { continue };
                if kind == 5 {
                    // 지위: 여럿이면 나중 것 하나만(칸은 시작 순으로 오므로 덮어쓰면 된다).
                    if let Some(place) = eras[at_row]["periods"].as_array_mut().unwrap().iter_mut().find(|p| p["uid"] == uid.as_str()) {
                        place["rank"] = json!({"cell":strip_cell_ref(kind, style),"name":name,"level":(((style >> 8) & 7) - 1).clamp(0, 4)});
                    }
                } else if kind == 4 {
                    // 시기 구분: 체계가 둘 이상이면 이름 앞에 체계 이름이 탭으로 붙어 온다(계약 6-2의 style 32비트).
                    let (scheme, text) = match name.split_once('\t') {
                        Some((head, rest)) if style & 32 != 0 => (head.to_owned(), rest.to_owned()),
                        _ => (String::new(), name.clone()),
                    };
                    let slot = *phase_at.entry((band, lane)).or_insert_with(|| {
                        phases.push(json!({"track":track_head[at_row].0,"name":track_head[at_row].1,"color":track_head[at_row].2,"period":band_name,"cells":[]}));
                        phases.len() - 1
                    });
                    let list = phases[slot]["cells"].as_array_mut().unwrap();
                    let row = json!({"uid":uid,"cell":strip_cell_ref(kind, style),"name":text,"scheme":scheme,"when":when_text(Some(start), Some(end), "")});
                    // 바뀐 해에는 뒤 칸만 — 같은 단에서는 마지막 것을 남긴다.
                    list.clear();
                    list.push(row);
                }
            }
        }
        {
            // 그때 활동한 인물 — 인물 막대(구역 37)가 그때에 걸친 것. text2는 `인물uid|생분|몰분`이다(계약 6-7).
            // 역할은 그 인물의 항목 기록에서 꺼낸다(막대에는 담을 자리가 없다).
            let sql = format!("SELECT r.track,i.name,i.text2,i.start,i.end,i.b,\
                 COALESCE((SELECT json_extract(en.json,'$.role') FROM entities en WHERE en.uid=substr(i.text2,1,instr(i.text2,'|')-1)),'') \
                FROM items i JOIN rows r ON r.id=i.row \
                WHERE i.section=37 AND i.start<=?1 AND i.end>=?2 AND i.pack IN (SELECT value FROM json_each(?3)){row_keep} ORDER BY r.track,i.start,i.id");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params![until, at, packs])?;
            while let Some(r) = rows.next()? {
                let Some(at_row) = at_track.get(&r.get::<_, i64>(0)?).copied() else { continue };
                let b: i64 = r.get(5)?;
                if (b & 3) < min_importance {
                    continue;
                }
                let text2: String = r.get(2)?;
                let uid = text2.split('|').next().unwrap_or("").to_owned();
                let (start, end): (i64, i64) = (r.get(3)?, r.get(4)?);
                figures[at_row]["figures"].as_array_mut().unwrap().push(json!({"uid":uid,"name":r.get::<_,String>(1)?,"role":r.get::<_,String>(6).unwrap_or_default(),
                    "when":when_text(Some(start), Some(end), "")}));
            }
        }
        let mut count = 0i64;
        let mut event_rows: Vec<Value> = Vec::new();
        {
            let day = |minute: i64| minute.div_euclid(DAY).clamp(i32::MIN as i64, i32::MAX as i64);
            // 같은 때(트랙마다의 목록은 같은 중요도 · 같은 때)의 동률은 번호가 아니라 (사건 제 줄의 트랙 차례, 트랙 안 사건 차례 `events.ord`)로 깬다 —
            // 타일 대표와 같은 열쇠(판정 R23). 트랙을 고쳐 쓴 저장소(같은 uid는 옛 번호 · 새 uid는 끝 번호)에서도 통째 짓기와 같은 차례 · 같은 12개 ·
            // 같은 첫 쪽이 나온다(과제 perf — 11a의 old-dlc-check에서 임진왜란 ↔ 한산도 대첩이 갈렸다). 통째로 지은 저장소는 이 차례 = 번호 차례라
            // 답이 예전과 같다(`apply.rs`의 R26 검사). 트랙 차례는 `RowMap`과 같은 (tracks.ord, tracks.id). 그 열이 없는 옛 저장소(판 '3')는 번호로.
            let (in_track, across) = if self.event_ord { ("e.ord,e.id", "t.ord,t.id,e.ord,e.id") } else { ("e.id", "e.id") };
            let sql = format!("SELECT r.track,e.id,e.uid,e.title,e.start,e.end,e.importance,e.look,e.label,COALESCE(p.color,0),t.name \
                FROM bounds b JOIN events e ON e.id=b.id JOIN rows r ON r.id=e.lane JOIN tracks t ON t.id=r.track LEFT JOIN periods p ON p.id=e.band \
                WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND e.start<=?3 AND e.end>=?4 AND e.pack IN (SELECT value FROM json_each(?5)){event_keep} \
                ORDER BY r.track,e.importance DESC,e.start,{in_track}");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params![day(until), day(at), until, at, packs])?;
            while let Some(r) = rows.next()? {
                if let Some(at_row) = at_track.get(&r.get::<_, i64>(0)?) {
                    let list = tracks[*at_row]["events"].as_array_mut().unwrap();
                    if list.len() < 12 {
                        list.push(json!({"id":r.get::<_,i64>(1)?,"uid":r.get::<_,String>(2)?,"title":r.get::<_,String>(3)?,
                            "start":r.get::<_,i64>(4)?,"end":r.get::<_,i64>(5)?,"importance":r.get::<_,i64>(6)?}));
                    }
                }
            }
            // 창의 사건 목록은 앞뒤 범위(window)만큼 넓혀 시작 순으로 담는다.
            let sql = format!("SELECT e.id,e.uid,e.title,e.start,e.end,e.importance,e.look,e.label,COALESCE(p.color,0),t.name \
                FROM bounds b JOIN events e ON e.id=b.id JOIN rows r ON r.id=e.lane JOIN tracks t ON t.id=r.track LEFT JOIN periods p ON p.id=e.band \
                WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND e.start<=?3 AND e.end>=?4 AND e.pack IN (SELECT value FROM json_each(?5)){event_keep} \
                ORDER BY e.start,{across} LIMIT ?6");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query(rusqlite::params![day(wide_hi), day(wide_lo), wide_hi, wide_lo, packs, SAME_YEAR_EVENTS + 1])?;
            while let Some(r) = rows.next()? {
                count += 1;
                if event_rows.len() as i64 >= SAME_YEAR_EVENTS {
                    continue;
                }
                let look: i64 = r.get(6)?;
                event_rows.push(json!({"id":r.get::<_,i64>(0)?,"uid":r.get::<_,String>(1)?,"title":r.get::<_,String>(2)?,
                    "start":r.get::<_,i64>(3)?,"end":r.get::<_,i64>(4)?,"importance":r.get::<_,i64>(5)?,
                    "label":r.get::<_,String>(7)?,"color":r.get::<_,i64>(8)?,"track":r.get::<_,String>(9)?,"treaty":look & (1 << 16) != 0}));
            }
            if count > SAME_YEAR_EVENTS {
                // 한 쪽을 넘기면 정확한 수를 따로 센다(창 머리의 'n건').
                let sql = format!("SELECT count(*) FROM bounds b JOIN events e ON e.id=b.id \
                    WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND e.start<=?3 AND e.end>=?4 AND e.pack IN (SELECT value FROM json_each(?5)){event_keep}");
                count = self.db.query_row(&sql, rusqlite::params![day(wide_hi), day(wide_lo), wide_hi, wide_lo, packs], |r| r.get(0))?;
            }
        }
        // 그때 아무것도 없는 트랙은 빼고 준다.
        tracks.retain(|t| !t["bands"].as_array().unwrap().is_empty() || !t["cells"].as_array().unwrap().is_empty() || !t["events"].as_array().unwrap().is_empty());
        eras.retain(|g| !g["periods"].as_array().unwrap().is_empty());
        figures.retain(|g| !g["figures"].as_array().unwrap().is_empty());
        let figure_count: i64 = figures.iter().map(|g| g["figures"].as_array().unwrap().len() as i64).sum();
        Ok(json!({"at":at,"end":until,"window":window,"tracks":tracks,"eras":eras,"phases":phases,"figures":figures,
            "figureCount":figure_count,"events":event_rows,"count":count}))
    }

    /// 표 보기 · CSV가 함께 쓰는 줄 모으기(UNION만). 담기는 것은 사건 · 조약, 그리고 `with_periods`면 정권 · 인물 · 시대 구분 · 대범위다.
    fn table_union(&self, q: &Value, packs: &str) -> Result<(String, Vec<SqlValue>)> {
        let with_periods = q["with_periods"].as_bool().unwrap_or(false);
        let (lo, hi) = (q["lo"].as_i64(), q["hi"].as_i64());
        if let (Some(lo), Some(hi)) = (lo, hi) {
            if hi < lo {
                return Err("표의 범위가 뒤집혔습니다".into());
            }
        }
        let mut args: Vec<SqlValue> = Vec::new();
        let range = |column_start: &str, column_end: &str, args: &mut Vec<SqlValue>| -> String {
            let mut text = String::new();
            if let Some(hi) = hi {
                text.push_str(&format!(" AND {column_start}<=?"));
                args.push(hi.into());
            }
            if let Some(lo) = lo {
                text.push_str(&format!(" AND {column_end}>=?"));
                args.push(lo.into());
            }
            text
        };
        let filter = self.filter_of(q)?;
        let (event_keep, band_keep, row_keep) = match &filter {
            Some(f) => (f.event_keep("e"), f.band_keep("p"), f.row_keep("n.row")),
            None => (String::new(), String::new(), String::new()),
        };
        let mut parts = Vec::new();
        {
            args.push(packs.to_owned().into());
            let where_range = range("e.start", "e.end", &mut args);
            // 조약은 사건의 look 16비트다(계약 6-6) — 표의 '구분'이 사건과 갈린다.
            parts.push(format!(
                "SELECT (CASE WHEN e.look&65536 THEN 'treaty' ELSE 'event' END) AS k,e.uid AS u,e.title AS nm,e.start AS st,e.end AS en,t.id AS tk,t.name AS tn,e.importance AS im,e.look AS lk,\
                 0 AS fz,e.body AS bd,e.label AS lb,t.ord AS od,e.id AS iv,e.pack AS pk \
                 FROM events e JOIN rows r ON r.id=e.lane JOIN tracks t ON t.id=r.track \
                 WHERE e.pack IN (SELECT value FROM json_each(?)){where_range}{event_keep}"
            ));
        }
        if with_periods {
            args.push(packs.to_owned().into());
            let where_range = range("p.start", "p.end", &mut args);
            parts.push(format!(
                "SELECT 'period',p.uid,p.name,p.start,p.end,t.id,t.name,0,p.look,p.fuzzy,'','',t.ord,p.id,p.pack \
                 FROM periods p JOIN rows r ON r.id=p.row JOIN tracks t ON t.id=r.track \
                 WHERE p.pack IN (SELECT value FROM json_each(?)){where_range}{band_keep}"
            ));
            // 인물 · 시대 구분 · 대범위는 제 표가 없다 — 이름 표(names)가 이미 이름과 기간과 빌린 자리를 들고 있다.
            // 계보 전용 인물(D1 — 본문 `lineageOnly: true`, 활동 막대가 없어 이름 표의 기간이 비어 있음)은 표에 싣지 않는다:
            // 웹 표(viewer.js tableItems)가 띠 인물(visibleFigures)만 싣는 것과 같게. 기간이 빈 줄만 본문을 들여다보므로 옛 배치의 답은 그대로다.
            for kind in ["figure", "epoch", "scope"] {
                args.push(packs.to_owned().into());
                let where_range = range("n.start", "n.end", &mut args);
                let lineage_off = if kind == "figure" {
                    " AND (n.start IS NOT NULL OR NOT EXISTS(SELECT 1 FROM entities en WHERE en.uid=n.uid AND en.kind='figure' AND json_valid(en.json) AND json_type(en.json,'$.lineageOnly')='true'))"
                } else {
                    ""
                };
                parts.push(format!(
                    "SELECT '{kind}',n.uid,n.name,n.start,n.end,COALESCE(t.id,0),COALESCE(t.name,''),2,0,0,'','',COALESCE(t.ord,9999),n.id,n.pack \
                     FROM names n LEFT JOIN rows r ON r.id=n.row LEFT JOIN tracks t ON t.id=r.track \
                     WHERE n.kind='{kind}' AND n.pack IN (SELECT value FROM json_each(?)){where_range}{row_keep}{lineage_off}"
                ));
            }
        }
        Ok((parts.join(" UNION ALL "), args))
    }

    /// 표의 줄을 차례대로 읽는 SQL(열은 위 `table_union`이 고른 차례).
    fn table_page_sql(union: &str, paged: bool) -> String {
        let mut sql = format!("SELECT k,u,nm,st,en,tk,tn,im,lk,fz,bd,lb,pk FROM ({union}) ORDER BY (st IS NULL),st,od,k,iv");
        if paged {
            sql.push_str(" LIMIT ? OFFSET ?");
        }
        sql
    }

    /// 표 한 쪽. 차례는 시작 → 트랙 순서다. 첫 쪽에는 통틀어 몇 줄인지(`count`)를 함께 싣는다.
    pub fn table(&self, q: &Value) -> Result<Value> {
        let limit = limit_of(q, 200, 1000)?;
        let after = after_of(q)?;
        let packs = self.packs_json(q)?;
        let (union, mut args) = self.table_union(q, &packs)?;
        let sql = Self::table_page_sql(&union, true);
        let total = if after == 0 {
            Some(self.db.prepare(&format!("SELECT count(*) FROM ({union})"))?.query_row(rusqlite::params_from_iter(args.clone()), |r| r.get::<_, i64>(0))?)
        } else {
            None
        };
        args.push((limit + 1).into());
        args.push(after.into());
        let mut stmt = self.db.prepare(&sql)?;
        let rows = stmt.query_map(rusqlite::params_from_iter(args), |r| {
            let (start, end): (Option<i64>, Option<i64>) = (r.get(3)?, r.get(4)?);
            let label: String = r.get(11)?;
            Ok(json!({"kind":r.get::<_,String>(0)?,"uid":r.get::<_,String>(1)?,"name":r.get::<_,String>(2)?,
                "when":when_text(start, end, &label),"start":start,"end":end,
                "track":r.get::<_,i64>(5)?,"track_name":r.get::<_,String>(6)?,"importance":r.get::<_,i64>(7)?}))
        })?.collect::<std::result::Result<Vec<_>, _>>()?;
        let mut answer = page(rows, after, limit);
        if let Some(total) = total {
            answer["count"] = Value::from(total);
        }
        Ok(answer)
    }

    /// 표를 CSV 파일로 바로 쓴다(BOM + CRLF · 모든 칸을 따옴표로). 메모리에 다 올리지 않고 한 줄씩 흘려 쓴다.
    /// 저장소 폴더 밖이어도 되지만 이미 있는 파일은 덮어쓰지 않는다.
    pub fn table_csv(&self, q: &Value) -> Result<Value> {
        let text = q["path"].as_str().ok_or("내보낼 파일 경로(path) 누락")?;
        let path = Path::new(text);
        if path.extension().and_then(|s| s.to_str()).map(|s| s.eq_ignore_ascii_case("csv")) != Some(true) {
            return Err("표 내보내기는 .csv 파일에만 씁니다".into());
        }
        if path.exists() {
            return Err("이미 있는 파일은 덮어쓰지 않습니다".into());
        }
        let packs = self.packs_json(q)?;
        let (union, args) = self.table_union(q, &packs)?;
        let sql = Self::table_page_sql(&union, false);
        // '제공' 열은 자료집의 이름이다(지금 연표의 `x.packName`).
        let pack_names: HashMap<i64, String> = {
            let mut stmt = self.db.prepare("SELECT id,name FROM packs")?;
            let mut rows = stmt.query([])?;
            let mut map = HashMap::new();
            while let Some(r) = rows.next()? {
                map.insert(r.get(0)?, r.get(1)?);
            }
            map
        };
        let categories: HashMap<i64, String> = {
            let mut stmt = self.db.prepare("SELECT ord,name FROM categories ORDER BY ord,id")?;
            let mut rows = stmt.query([])?;
            let mut map = HashMap::new();
            while let Some(r) = rows.next()? {
                map.entry(r.get::<_, i64>(0)?).or_insert_with(|| r.get::<_, String>(1).unwrap_or_default());
            }
            map
        };
        let file = std::fs::OpenOptions::new().write(true).create_new(true).open(path)?;
        let mut out = std::io::BufWriter::new(file);
        out.write_all("\u{FEFF}".as_bytes())?;
        out.write_all(csv_line(&["시작", "끝", "구분", "트랙", "제목", "분류", "중요도", "확실성", "설명", "다른 견해", "쟁점", "태그", "출처", "제공", "실재성"]
            .map(str::to_owned)).as_bytes())?;
        // 다른 견해 · 쟁점 · 태그 · 출처는 항목 기록의 json에 있다(열로 펴 온 것이 아니라 여기서 꺼낸다).
        let mut extra = self.db.prepare("SELECT json FROM entities WHERE uid=?1")?;
        let mut stmt = self.db.prepare(&sql)?;
        let mut rows = stmt.query(rusqlite::params_from_iter(args))?;
        let mut count = 0i64;
        while let Some(r) = rows.next()? {
            let kind: String = r.get(0)?;
            let (start, end): (Option<i64>, Option<i64>) = (r.get(3)?, r.get(4)?);
            let (look, fuzzy): (i64, i64) = (r.get(8)?, r.get(9)?);
            let label: String = r.get(11)?;
            let event = kind == "event" || kind == "treaty";
            let band = kind == "period";
            // 시작 · 끝은 날짜 글 그대로 — 저장소에 원문 글이 있는 것은 사건의 label뿐이라 없으면 연도 글로 적는다.
            let from = if start.is_none() || (band && fuzzy & 1 != 0) { "미정".to_owned() } else if event && !label.is_empty() { label.clone() } else { year_text(year_of(start.unwrap())) };
            let to = match end {
                _ if band && fuzzy & 2 != 0 => "미정".to_owned(),
                Some(to) if Some(to) != start => year_text(year_of(to)),
                _ => String::new(),
            };
            // 구분: 사건 · 조약 · (정권이면) 6-1의 종류 이름 · 인물 · 시대 구분 · 대범위.
            let group = match kind.as_str() {
                "treaty" => "조약".to_owned(),
                "event" => "사건".to_owned(),
                "period" => BAND_KINDS.get((look & 0x1F) as usize).copied().unwrap_or("정권").to_owned(),
                "figure" => "인물".to_owned(),
                "epoch" => "시대 구분".to_owned(),
                "scope" => "대범위".to_owned(),
                other => other.to_owned(),
            };
            let category = if event { categories.get(&(look & 0xFF)).cloned().unwrap_or_default() } else { String::new() };
            let importance = if event { r.get::<_, i64>(7)?.to_string() } else { String::new() };
            let certainty = if event {
                if look & (1 << 21) != 0 { "전승" } else if look & (1 << 20) != 0 { "추정" } else { "확실" }
            } else if band {
                CERTAINTY[((look >> 5) & 3) as usize]
            } else {
                ""
            };
            let historic = if band { HISTORICITY.get(((look >> 8) & 7) as usize).copied().unwrap_or("").to_owned() } else { String::new() };
            let uid: String = r.get(1)?;
            let record: Option<Value> = extra.query_row([&uid], |x| x.get::<_, String>(0)).ok().and_then(|text| serde_json::from_str(&text).ok());
            let (alts, debate, tags, source) = match &record {
                Some(json) => (alt_text(&json["alternatives"]), json["debate"].as_str().unwrap_or("").to_owned(), join_text(&json["tags"], " "),
                    json["source"].as_str().unwrap_or("").to_owned()),
                None => (String::new(), String::new(), String::new(), String::new()),
            };
            let credit = pack_names.get(&r.get::<_, i64>(12)?).cloned().unwrap_or_default();
            out.write_all(csv_line(&[from, to, group, r.get::<_, String>(6)?, r.get::<_, String>(2)?, category, importance,
                certainty.to_owned(), r.get::<_, String>(10)?, alts, debate, tags, source, credit, historic]).as_bytes())?;
            count += 1;
        }
        out.flush()?;
        Ok(json!({"rows":count,"path":path.to_string_lossy()}))
    }

    /// 범례의 조건부 줄: 지금 자료에 쓰인 것의 있고 없음(계약 6절의 비트 표로 셈한다).
    pub fn legend_kinds(&self, q: &Value) -> Result<Value> {
        let packs = self.packs_json(q)?;
        let list = |sql: &str| -> Result<Vec<i64>> {
            let mut stmt = self.db.prepare(sql)?;
            let rows = stmt.query_map([&packs], |r| r.get(0))?.collect::<std::result::Result<Vec<i64>, _>>()?;
            Ok(rows)
        };
        let yes = |sql: &str| -> Result<bool> { Ok(self.db.query_row(sql, [&packs], |r| r.get::<_, i64>(0))? != 0) };
        let mine = "pack IN (SELECT value FROM json_each(?1))";
        // 칸 종류 9(직위 줄 더 — 스키마 4 · 계약 1-1)는 3단계 동안 화면이 그리지 않는 칸이라 범례 · 필터 시트의 조건부 줄을 세우지 않는다
        // (전체 제약 '앱 화면 1배 · 새 값은 실리기만' — 그 칸의 style 비트가 범례 줄을 켜지 않게). 4단계가 그 줄을 그릴 때 이 거르기를 걷는다.
        let cells_of = |cond: &str| format!("EXISTS(SELECT 1 FROM cells c JOIN periods p ON p.id=c.period WHERE c.kind<>9 AND {cond} AND p.{mine})");
        let kinds = list(&format!("SELECT DISTINCT look&31 FROM periods WHERE {mine} ORDER BY 1"))?;
        let historicity = list(&format!("SELECT DISTINCT (look>>8)&7 FROM periods WHERE {mine} ORDER BY 1"))?;
        let variant = yes(&format!("SELECT EXISTS(SELECT 1 FROM events WHERE rail&32 AND {mine}) OR {} OR EXISTS(SELECT 1 FROM items WHERE section=35 AND {mine})", cells_of("c.style&128")))?;
        let vague_cell = yes(&format!("SELECT {}", cells_of("c.style&24")))?;
        let treaty = yes(&format!("SELECT EXISTS(SELECT 1 FROM events WHERE look&65536 AND {mine})"))?;
        let figure = yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=37 AND {mine}) OR {}", cells_of("c.kind=6")))?;
        let dep_label = yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=16 AND {mine}) OR {}", cells_of("c.kind=7")))?;
        let scope = yes(&format!("SELECT EXISTS(SELECT 1 FROM groups g JOIN tracks t ON t.id=g.track WHERE g.kind=2 AND t.{mine}) OR EXISTS(SELECT 1 FROM periods WHERE look&262144 AND {mine})"))?;
        // 범례의 조건부 줄이 묻는 것들(부품의 `has{…}`). 근거는 계약 6절의 비트 표다.
        let has = json!({
            "range":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section IN (19,34) AND {mine}) OR EXISTS(SELECT 1 FROM events WHERE look&8388608 AND {mine}) OR {}", cells_of("c.style&64")))?,
            "unknown":yes(&format!("SELECT EXISTS(SELECT 1 FROM periods WHERE fuzzy<>0 AND {mine}) OR EXISTS(SELECT 1 FROM events WHERE look&4194304 AND {mine}) OR {}", cells_of("c.style&3")))?,
            "scope":scope,
            "hollow":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=25 AND {mine}) OR EXISTS(SELECT 1 FROM periods WHERE look&262144 AND {mine})"))?,
            "revival":yes(&format!("SELECT EXISTS(SELECT 1 FROM periods WHERE ((look&31)=16 OR look&4096) AND {mine})"))?,
            "partial":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=21 AND (a&3)=3 AND {mine})"))?,
            "join":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=21 AND a&128 AND {mine})"))?,
            "depOut":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=16 AND {mine})"))?,
            "depIn":yes(&format!("SELECT {}", cells_of("c.kind=7")))?,
            "figure":figure,
            "cellAlt":yes(&format!("SELECT {}", cells_of("c.style&128")))?,
            "cellFuzzy":vague_cell,
            "phase":yes(&format!("SELECT EXISTS(SELECT 1 FROM rows r JOIN tracks t ON t.id=r.track WHERE r.phase>0 AND t.{mine}) OR {}", cells_of("c.kind=4")))?,
            "rank":yes(&format!("SELECT EXISTS(SELECT 1 FROM rows r JOIN tracks t ON t.id=r.track WHERE r.rank>0 AND t.{mine}) OR {}", cells_of("c.kind=5")))?,
            "treaty":treaty,
            "cats":yes(&format!("SELECT EXISTS(SELECT 1 FROM rows r JOIN tracks t ON t.id=r.track WHERE r.cats<>'[]' AND t.{mine})"))?,
            "culture":yes(&format!("SELECT EXISTS(SELECT 1 FROM periods WHERE ((look&31)=17 OR look&16384) AND {mine})"))?,
            "zone":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=17 AND {mine})"))?,
            // 뒤 장의 탭(구역 47 — 속국 띠 위의 상국 탭, 묶음 3 · 1번)
            "hostTab":yes(&format!("SELECT EXISTS(SELECT 1 FROM items WHERE section=47 AND {mine})"))?
        });
        Ok(json!({
            // 2절의 옛 열쇠(그대로 둔다)
            "band_kinds":kinds,
            "band_kind_names":kinds.iter().map(|k| BAND_KINDS.get(*k as usize).copied().unwrap_or("")).collect::<Vec<_>>(),
            "certainty":list(&format!("SELECT DISTINCT (look>>5)&3 FROM periods WHERE {mine} ORDER BY 1"))?,
            "variant":variant,"vague_cell":vague_cell,"treaty":treaty,"figure":figure,"dep_label":dep_label,"scope":scope,
            // 범례 · 필터 시트가 읽는 모양. 차례는 지금 연표의 KIND_ORDER 그대로(종류 번호가 곧 그 차례다 — 계약 6-1).
            "kinds":kinds.iter().map(|k| {
                let at = *k as usize;
                json!({"id":k,"kind":k,"name":BAND_KINDS.get(at).copied().unwrap_or(""),"hint":BAND_KIND_HINTS.get(at).copied().unwrap_or(""),
                    "dep":(1..=11).contains(k) || (20..=22).contains(k)})
            }).collect::<Vec<_>>(),
            "historicity":historicity.iter().map(|h| json!({"id":h,"name":HISTORICITY.get(*h as usize).copied().unwrap_or("")})).collect::<Vec<_>>(),
            "historicity_ids":historicity,
            "categories":list(&format!("SELECT DISTINCT (look&255) FROM events WHERE (look&255)<255 AND {mine} ORDER BY 1"))?,
            "alt":variant,"fuzzy_cells":vague_cell,"treaties":treaty,"figures":figure,"dep_tags":dep_label,"scopes":scope,
            "has":has
        }))
    }

    /// 대범위 칩(모아 보기)의 목록. 거르기가 아니라 줄을 모으는 스위치라 거르개를 받지 않는다.
    /// 항목 기록(`entities`의 kind `scope`)에서 읽어 **트랙 차례 → 이름 차례**로 준다.
    pub fn scopes(&self, q: &Value) -> Result<Value> {
        let packs = self.packs_json(q)?;
        // 항목 기록의 `track`은 트랙의 글자 id(`mw-coast`)다 — layout의 `key`와 같은 값이다.
        let mut track_of: HashMap<String, (i64, i64)> = HashMap::new();
        {
            let mut stmt = self.db.prepare("SELECT id,ord,key FROM tracks ORDER BY ord,id")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let key: String = r.get(2)?;
                if !key.is_empty() {
                    track_of.insert(key, (r.get(0)?, r.get(1)?));
                }
            }
        }
        let mut found: Vec<(i64, String, Value)> = Vec::new();
        {
            let mut stmt = self.db.prepare("SELECT uid,json FROM entities WHERE kind='scope' AND pack IN (SELECT value FROM json_each(?1))")?;
            let mut rows = stmt.query([&packs])?;
            while let Some(r) = rows.next()? {
                let (uid, text): (String, String) = (r.get(0)?, r.get(1)?);
                let body: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
                let key = body["track"].as_str().unwrap_or("");
                let (track, ord) = track_of.get(key).copied().unwrap_or((0, i64::MAX));
                let name = body["name"].as_str().unwrap_or("").to_owned();
                let members = body["members"].as_array().map(Vec::len).or_else(|| body["x_members"].as_array().map(Vec::len)).unwrap_or(0);
                found.push((ord, name.clone(), json!({"uid":uid,"track":track,"name":name,"color":css_color(body["color"].as_str().unwrap_or("")),
                    "label":body["label"].as_str().unwrap_or(""),"members":members,"default":body["default"] == Value::Bool(true)})));
            }
        }
        found.sort_by(|a, b| (a.0, &a.1).cmp(&(b.0, &b.1)));
        Ok(json!({"scopes":found.into_iter().map(|(_, _, v)| v).collect::<Vec<_>>()}))
    }

    /// 간지 검색: 그 간지에 해당하는 해들을 **보는 시기 가운데에 가까운 순**으로(명세 ㈐-15).
    /// 순수한 셈이라 저장소를 읽지 않는다. 해는 모두 천문 해(0년이 있는 셈)이고, 60갑자의 차례는 화면 쪽 `ganjiOf`와 같다.
    pub fn ganji_years(&self, q: &Value) -> Result<Value> {
        let ganji = q["ganji"].as_str().ok_or("찾을 간지(ganji) 누락")?;
        if ganji.chars().count() != 2 {
            return Err("간지는 두 글자입니다".into());
        }
        let (lo, hi) = (num(q, "lo")?, num(q, "hi")?);
        if hi < lo {
            return Err("간지를 찾을 범위가 뒤집혔습니다".into());
        }
        let center = q["center"].as_i64().unwrap_or((lo + hi) / 2);
        let limit = limit_of(q, 60, 600)?;
        let (from, to) = (lo - 60, hi + 60);
        let mut first = None;
        for year in from..(from + 60).min(to + 1) {
            if ganji_of(year) == ganji {
                first = Some(year);
                break;
            }
        }
        let Some(first) = first else { return Ok(json!({"years":[]})) };
        let mut years: Vec<i64> = (0..).map(|n| first + n * 60).take_while(|y| *y <= to).collect();
        years.sort_by_key(|y| ((y - center).abs(), *y));
        years.truncate(limit as usize);
        Ok(json!({"years":years}))
    }

    /// 관점(나라마다 제 이름) — 계약 2-6절 · 명세 06의 8-15 · 지금 연표의 `titleFor`(`js/timeline.js:2550`).
    ///
    /// 입력 `{"lens":"local"|"<트랙 번호를 적은 글>","packs"?,"filter"?}`,
    /// 답 `{"events":{"<사건 번호>":"그 관점의 이름"},"bands":{"<띠 번호>":"이름"}}`.
    /// `local`이면 **그 항목이 놓인 트랙**의 관점 이름이고(여러 자리에 놓인 사건은 **그 자리의 트랙** 기준),
    /// 트랙 번호면 어느 자리든 그 트랙의 관점 이름이다. 관점 이름이 없는 항목은 답에 싣지 않는다.
    pub fn lens_names(&self, q: &Value) -> Result<Value> {
        let lens = match &q["lens"] {
            Value::String(text) => text.trim().to_owned(),
            Value::Number(n) => n.to_string(),
            Value::Null => return Err("관점(lens) 누락 — 'local' 또는 트랙 번호입니다".into()),
            _ => return Err("관점(lens)은 'local' 또는 트랙 번호를 적은 글입니다".into()),
        };
        let local = lens == "local";
        let wanted: i64 = if local {
            0
        } else {
            lens.parse().map_err(|_| format!("모르는 관점입니다: {lens} (쓸 수 있는 것: local · 트랙 번호)"))?
        };
        let empty = Ok(json!({"events":{},"bands":{}}));
        let packs = self.packs_json(q)?;

        // 1) 관점 이름 — 넣을 때 펴 둔 표가 있으면 그것을, 없는 옛 저장소는 그 자리에서 항목 기록을 훑는다(답은 같다).
        let mut track_of_key: HashMap<String, i64> = HashMap::new();
        {
            let mut stmt = self.db.prepare("SELECT id,key FROM tracks WHERE key<>''")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                track_of_key.insert(r.get(1)?, r.get(0)?);
            }
        }
        // uid(밑동) → (트랙 번호 → 그 관점의 이름)
        let mut views: HashMap<String, HashMap<i64, String>> = HashMap::new();
        {
            let sql = if self.has_lens_names {
                "SELECT uid,track,name FROM lens_names WHERE pack IN (SELECT value FROM json_each(?1))".to_owned()
            } else {
                format!("SELECT uid,track,name FROM ({}) WHERE pack IN (SELECT value FROM json_each(?1))", crate::builder::LENS_NAMES_SQL)
            };
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query([&packs])?;
            while let Some(r) = rows.next()? {
                let (uid, key, name): (String, String, String) = (r.get(0)?, r.get(1)?, r.get(2)?);
                // 저장소에 없는 트랙을 가리키는 관점은 부를 길이 없다(지금 연표에서도 그 탭이 서지 않는다).
                let Some(track) = track_of_key.get(&key) else { continue };
                views.entry(uid).or_default().insert(*track, name);
            }
        }
        if views.is_empty() {
            return empty;
        }
        // 고른 관점에 이름이 하나도 없으면(트랙 번호가 틀렸거나 그 나라의 이름이 없음) 빈 결과다 — 실패가 아니다.
        if !local && !views.values().any(|by_track| by_track.contains_key(&wanted)) {
            return empty;
        }

        // 2) 그 이름을 가진 사건 · 띠 찾기. 공동 사건의 둘째 자리부터는 `uid#1`이라 밑동으로 묶어 찾는다 —
        //    `'#'`(0x23)과 `'$'`(0x24) 사이의 글자열이 곧 '그 밑동의 다른 자리'이고, 이름 색인을 그대로 탄다.
        let bases: Vec<&str> = views.keys().map(String::as_str).collect();
        let list = serde_json::to_string(&bases)?;
        let filter = self.filter_of(q)?;
        let mut row_track: HashMap<i64, i64> = HashMap::new();
        {
            let mut stmt = self.db.prepare("SELECT id,track FROM rows")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                row_track.insert(r.get(0)?, r.get(1)?);
            }
        }
        let mut events = serde_json::Map::new();
        {
            let sql = "SELECT e.id,e.uid,e.lane,e.look,e.importance,e.band FROM json_each(?1) b JOIN events e ON e.uid=b.value \
                 WHERE e.uid<>'' AND e.pack IN (SELECT value FROM json_each(?2)) \
                 UNION ALL \
                 SELECT e.id,e.uid,e.lane,e.look,e.importance,e.band FROM json_each(?1) b JOIN events e ON e.uid>b.value||'#' AND e.uid<b.value||'$' \
                 WHERE e.uid<>'' AND e.pack IN (SELECT value FROM json_each(?2))";
            let mut stmt = self.db.prepare(sql)?;
            let mut rows = stmt.query([&list, &packs])?;
            while let Some(r) = rows.next()? {
                let (id, uid, row): (i64, String, i64) = (r.get(0)?, r.get(1)?, r.get(2)?);
                let (look, importance, band): (i64, i64, i64) = (r.get(3)?, r.get(4)?, r.get(5)?);
                if filter.as_ref().is_some_and(|f| f.event_off(row, look, importance, band)) {
                    continue;
                }
                let base = uid_stem(&uid).unwrap_or(&uid);
                let track = if local { row_track.get(&row).copied().unwrap_or(-1) } else { wanted };
                if let Some(name) = views.get(base).and_then(|by_track| by_track.get(&track)) {
                    events.insert(id.to_string(), Value::from(name.as_str()));
                }
            }
        }
        let mut bands = serde_json::Map::new();
        {
            let sql = "SELECT p.id,p.uid,p.row FROM json_each(?1) b JOIN periods p ON p.uid=b.value \
                 WHERE p.pack IN (SELECT value FROM json_each(?2)) \
                 UNION ALL \
                 SELECT p.id,p.uid,p.row FROM json_each(?1) b JOIN periods p ON p.uid>b.value||'#' AND p.uid<b.value||'$' \
                 WHERE p.pack IN (SELECT value FROM json_each(?2))";
            let mut stmt = self.db.prepare(sql)?;
            let mut rows = stmt.query([&list, &packs])?;
            while let Some(r) = rows.next()? {
                let (id, uid, row): (i64, String, i64) = (r.get(0)?, r.get(1)?, r.get(2)?);
                if filter.as_ref().is_some_and(|f| f.band_off(id)) {
                    continue;
                }
                let base = uid_stem(&uid).unwrap_or(&uid);
                let track = if local { row_track.get(&row).copied().unwrap_or(-1) } else { wanted };
                if let Some(name) = views.get(base).and_then(|by_track| by_track.get(&track)) {
                    bands.insert(id.to_string(), Value::from(name.as_str()));
                }
            }
        }
        Ok(json!({"events":events,"bands":bands}))
    }

    /// 묶음 카드가 쓰는 사건 목록(2단계의 `list`를 넓힌 것).
    /// 2판의 열에 `uid` · `color`(그 사건이 그려지는 색 — 타일의 사건과 같은 값) · `look` · `label`을 더했고,
    /// `"order":"start"`를 주면 시작 → 번호 차례로 주며 이어 받기는 `"after":[시작, 번호]`다(주지 않으면 옛 모양 그대로 번호 차례).
    /// 줄(`lane` ~ `lane + lanes − 1`과 답의 `lane`)은 밖으로 보이는 자리다(계획 P4).
    pub fn list_events(&self, q: &Value) -> Result<Value> {
        let (lo, hi) = (num(q, "lo")?, num(q, "hi")?);
        let (lane, lanes) = (num(q, "lane")?, num(q, "lanes")?);
        if hi < lo || lanes < 1 || lanes > 32 {
            return Err("조회 범위 오류".into());
        }
        let limit = limit_of(q, 50, crate::MAX_SHAPES)?;
        let by_start = match q["order"].as_str() {
            None | Some("id") => false,
            Some("start") => true,
            Some(other) => return Err(format!("모르는 차례입니다: {other} (쓸 수 있는 것: id · start)").into()),
        };
        // 이어 받기: 번호 차례면 정수 하나, 시작 차례면 [시작, 번호] 둘이다.
        let (after_start, after_id) = match (&q["after"], by_start) {
            (Value::Null, _) => (i64::MIN, 0),
            (v, false) => (i64::MIN, v.as_i64().ok_or("이어 받기 표(after)가 정수가 아닙니다")?),
            (Value::Array(pair), true) if pair.len() == 2 => (
                pair[0].as_i64().ok_or("이어 받기 표(after)의 시작이 정수가 아닙니다")?,
                pair[1].as_i64().ok_or("이어 받기 표(after)의 번호가 정수가 아닙니다")?,
            ),
            (v, true) => (i64::MIN, v.as_i64().ok_or("시작 차례의 이어 받기 표(after)는 [시작, 번호] 둘입니다")?),
        };
        let mut keep = self.filter_of(q)?.map(|f| f.event_keep("e")).unwrap_or_default();
        // 변형: 켜지 않은 변형의 사건은 빼고, 이사한 사건은 도착 줄(lane)로 적어 준다(계약 2-4절).
        let variants = self.variants_of(q)?;
        if let Some(v) = &variants {
            keep.push_str(&v.keep("e.variant"));
        }
        let packs = match q["packs"] {
            Value::Null => String::new(),
            _ => format!(" AND e.pack IN (SELECT value FROM json_each('{}'))", self.packs_json(q)?),
        };
        let (order, cursor) = if by_start {
            ("ORDER BY e.start,e.id", " AND (e.start>?7 OR (e.start=?7 AND e.id>?8))")
        } else {
            ("ORDER BY e.id", " AND e.id>?8")
        };
        let sql = format!(
            "SELECT e.id,e.lane,e.start,e.end,e.title,e.body,e.source,e.lo,e.hi,e.importance,e.pack,e.uid,COALESCE(p.color,0),e.look,e.label,e.band \
             FROM bounds b JOIN events e ON e.id=b.id LEFT JOIN periods p ON p.id=e.band \
             WHERE b.lo_day<=?2 AND b.hi_day>=?1 AND b.lane_min<=?4 AND b.lane_max>=?3 AND e.lo<=?6 AND e.hi>=?5{cursor}{packs}{keep} {order} LIMIT ?9"
        );
        let mut stmt = self.db.prepare(&sql)?;
        // 줄은 자리로 받는다 — 자리 범위를 열쇠 범위들(트랙마다 하나)로 나눠 범위마다 같은 SQL을 돌린다(계획 P4).
        // 열쇠 = 자리면 범위 하나 — 예전과 같은 물음이다.
        let ranges = self.rows.ranges_for(lane, lane + lanes - 1);
        let mut items = Vec::new();
        for (k0, k1) in &ranges {
            let mut rows = stmt.query(rusqlite::params![lo.div_euclid(DAY), hi.div_euclid(DAY), k0, k1, lo, hi, after_start, after_id, limit + 1])?;
            while let Some(r) = rows.next()? {
                let mut row = Store::event_row(r)?;
                row["uid"] = Value::from(r.get::<_, String>(11)?);
                row["color"] = Value::from(r.get::<_, i64>(12)?);
                row["look"] = Value::from(r.get::<_, i64>(13)?);
                row["label"] = Value::from(r.get::<_, String>(14)?);
                if let Some(v) = &variants {
                    // 이사한 사건은 도착 줄로 — 제 이사가 먼저이고, 없으면 든 띠의 이사를 따른다(계약 2-4절).
                    let (id, lane, band): (i64, i64, i64) = (r.get(0)?, r.get(1)?, r.get(15)?);
                    row["lane"] = Value::from(v.event_row(id, band, lane));
                }
                items.push(row);
            }
        }
        if ranges.len() > 1 {
            // 범위마다 앞에서 limit + 1개씩 받았다 — 합쳐 원래 차례(번호 또는 시작 → 번호)로 늘어놓고 다시 자른다.
            // 사건은 한 줄이라 범위 사이에 겹치지 않지만, 같은 번호는 하나만 남긴다.
            let number = |row: &Value| row["id"].as_i64().unwrap_or(0);
            if by_start {
                items.sort_by_key(|row| (row["start"].as_i64(), number(row)));
            } else {
                items.sort_by_key(number);
            }
            items.dedup_by_key(|row| number(row));
            items.truncate(limit as usize + 1);
        }
        // 줄(제자리든 이사한 도착 줄이든 열쇠)을 자리로.
        self.outward_lanes(&mut items);
        let more = items.len() as i64 > limit;
        items.truncate(limit as usize);
        let next = match items.last() {
            Some(last) if by_start => json!([last["start"], last["id"]]),
            Some(last) => last["id"].clone(),
            None => Value::Null,
        };
        Ok(json!({"next":next,"items":items,"has_more":more}))
    }

    /// 그 띠의 그 단에 든 칸 목록(시작 순). `kind`를 주지 않으면 모든 단을 준다.
    pub fn cells_of(&self, q: &Value) -> Result<Value> {
        let band = num(q, "band")?;
        let kind = match &q["kind"] {
            Value::Null => None,
            v => Some(v.as_i64().ok_or("칸의 단(kind)이 정수가 아닙니다")?),
        };
        if !self.db.query_row("SELECT count(*) FROM periods WHERE id=?1", [band], |r| r.get::<_, i64>(0)).map(|n| n > 0)? {
            return Err("그 번호의 띠가 없습니다".into());
        }
        let mut stmt = self.db.prepare("SELECT id,lane,start,end,name,style,color FROM cells WHERE period=?1 AND (?2 IS NULL OR kind=?2) ORDER BY start,kind,lane,id")?;
        let rows = stmt.query_map(rusqlite::params![band, kind], |r| {
            Ok(json!({"id":r.get::<_,i64>(0)?,"lane":r.get::<_,i64>(1)?,"start":r.get::<_,i64>(2)?,"end":r.get::<_,i64>(3)?,
                "name":r.get::<_,String>(4)?,"style":r.get::<_,i64>(5)?,"color":r.get::<_,i64>(6)?}))
        })?.collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(Value::Array(rows))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 분을_해로_바꾸는_길은_기원전에서도_맞는다() {
        assert_eq!(year_of(0), 1970);
        assert_eq!(year_of(-1), 1969);
        assert_eq!(year_of(-1_035_593_280), 1); // 0001-01-01 00:00 (719,162일 × 1,440분 앞)
        assert_eq!(year_of(-1_035_593_281), 0); // 그 한 분 앞은 0년 = 기원전 1년
        assert_eq!(year_text(0), "기원전 1년");
        assert_eq!(year_text(-959), "기원전 960년");
        assert_eq!(year_text(1970), "1970년");
    }

    #[test]
    fn 때_글은_날짜_글을_먼저_쓰고_없으면_연도로_적는다() {
        assert_eq!(when_text(Some(0), Some(0), "1592년 5월 23일"), "1592년 5월 23일");
        assert_eq!(when_text(Some(0), Some(0), ""), "1970년");
        assert_eq!(when_text(Some(-1_035_593_281), Some(0), ""), "기원전 1년–1970년");
        assert_eq!(when_text(None, None, ""), "미정");
    }

    #[test]
    fn 칸의_곁글은_띠_이름과_단_이름을_잇는다() {
        assert_eq!(cell_sub("별여울 한기국", 1), "별여울 한기국 지도자");
        assert_eq!(cell_sub("첫 트랙", 102), "첫 트랙 연호");
        assert_eq!(cell_sub("", 103), "도읍");
    }

    #[test]
    fn 내보내는_칸은_따옴표로_감싸고_따옴표는_겹쳐_쓴다() {
        assert_eq!(csv_line(&["가".to_owned(), "나\"다".to_owned()]), "\"가\",\"나\"\"다\"\r\n");
    }
}

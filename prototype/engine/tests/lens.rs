//! 관점(나라마다 제 이름) 조회 `lens_names`의 검사 — 계약 2-6절 · 명세 06의 8-15 · 지금 연표의 `titleFor`.
//!
//! 자료는 이 검사만 쓰는 작은 정답 저장소다(트랙 둘 · 띠 셋 · 사건 넷 · 관점을 가진 항목 기록 셋).
//! 월흔해 견본의 꼴을 그대로 본떴다 — 관점은 항목 기록의 `perspectives`에 `[{track, title, description}]`으로 들어 있고
//! `track`은 **트랙의 글자 id**(`tracks.key`와 같은 글)다.
use archive_engine::builder::{Builder, EventIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::{Result, Store, DAY};
use serde_json::{json, Value};
use std::path::PathBuf;

const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: -1, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

fn day(n: i64) -> i64 {
    n * DAY
}

/// 사건의 `look` 비트 — 공동 사건과 그 다른 자리(계약 6-6).
const SHARED: i64 = 1 << 17;
const PAIR: i64 = 1 << 18;

struct Fixture {
    path: PathBuf,
    /// 트랙 번호: 윗물(1) · 아랫물(2)
    north: i64,
    south: i64,
    /// 사건 번호: 함께 겪은 일의 첫 자리(윗물) · 둘째 자리(아랫물) · 관점이 없는 일 · 윗물만의 일
    war: i64,
    war_pair: i64,
    plain: i64,
    local_only: i64,
    /// 띠 번호: 관점을 가진 정권
    band: i64,
}

fn build(name: &str) -> Fixture {
    let path = std::env::temp_dir().join(format!("archive-lens-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    let plain_row = RowExtra::default();
    let north = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8_b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "mw-north" }).unwrap();
    let south = b.track_full(&TrackIn { pack, name: "아랫물", color: 0xa0_bcc5, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "mw-south" }).unwrap();
    let row0 = b.row_full(north, &GEO, &plain_row).unwrap();
    let row1 = b.row_full(south, &GEO, &plain_row).unwrap();
    let mut band_of = |row: i64, uid: &str, name: &str, color: u32| {
        b.period_full(&PeriodIn { pack, row, start: day(-100), end: day(400), fuzzy: 0, color, name, look: 0, tag: "", sub: 0, uid, variant: 0, form: 0 }).unwrap()
    };
    let water = band_of(row0, "band-water", "물빛나라", 0xa0_bcc5);
    let night = band_of(row1, "band-night", "밤여울", 0xd1_a9b9);
    let mut put = |uid: &str, lane: i64, band: i64, at: i64, look: i64, title: &str| {
        b.event(&EventIn { pack, lane, start: Some(day(at)), end: Some(day(at)), lo: None, hi: None, importance: 2, title,
            body: "검사 본문", source: None, raw: None, look, label: "", rail: 2 << 8, uid, band, variant: 0 }).unwrap()
    };
    // 두 나라가 함께 겪은 일 — 자리마다 제 이름이 있다.
    let war = put("e-war", row0, water, 10, SHARED, "검은소금 전쟁");
    let war_pair = put("e-war#1", row1, night, 10, SHARED | PAIR, "검은소금 전쟁");
    // 관점이 없는 사건(답에 싣지 않는다)과, 윗물의 관점만 적힌 사건.
    let plain = put("e-plain", row0, water, 20, 0, "이름이 하나뿐인 일");
    let local_only = put("e-north-only", row1, night, 30, 0, "윗물만 달리 부르는 일");
    b.entity("e-war", pack, "event", r#"{"uid":"e-war","title":"검은소금 전쟁",
        "perspectives":[{"track":"mw-north","title":"꿈 반환 전쟁","description":"윗물의 이름"},
                        {"track":"mw-south","title":"독립 저울 전쟁","description":"아랫물의 이름"}]}"#).unwrap();
    b.entity("e-plain", pack, "event", r#"{"uid":"e-plain","title":"이름이 하나뿐인 일"}"#).unwrap();
    // 저장소에 없는 트랙 · 빈 이름의 관점은 부를 길이 없어 답에 싣지 않는다.
    b.entity("e-north-only", pack, "event", r#"{"uid":"e-north-only","title":"윗물만 달리 부르는 일",
        "perspectives":[{"track":"mw-north","title":"잊힌 물길의 일"},{"track":"mw-없는트랙","title":"아무도 못 부르는 이름"},
                        {"track":"mw-south","description":"이름 없이 설명만"}]}"#).unwrap();
    // 띠(정권)에도 관점이 붙을 수 있다.
    b.entity("band-water", pack, "period", r#"{"uid":"band-water","name":"물빛나라",
        "perspectives":[{"track":"mw-south","title":"윗쪽 사람들"}]}"#).unwrap();
    b.finalize(&[("seed", "관점".to_owned())]).unwrap();
    Fixture { path, north, south, war, war_pair, plain, local_only, band: water }
}

fn ask(store: &Store, q: Value) -> Result<Value> {
    store.call(&q)
}

/// 답의 `events`에서 그 사건 번호의 이름(없으면 None).
fn name_of(answer: &Value, key: &str, id: i64) -> Option<String> {
    answer[key][id.to_string()].as_str().map(str::to_owned)
}

#[test]
fn 트랙을_고른_관점은_어느_자리에서나_그_나라의_이름을_쓴다() {
    let f = build("track");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"lens_names","lens":f.south.to_string()})).unwrap();
    // 공동 사건은 **두 자리 모두** 아랫물의 이름으로 바뀐다(지금 연표의 `titleFor`는 자리를 보지 않는다).
    assert_eq!(name_of(&answer, "events", f.war).as_deref(), Some("독립 저울 전쟁"));
    assert_eq!(name_of(&answer, "events", f.war_pair).as_deref(), Some("독립 저울 전쟁"));
    // 관점이 없는 항목 · 그 나라의 이름이 없는 항목은 싣지 않는다.
    assert_eq!(name_of(&answer, "events", f.plain), None);
    assert_eq!(name_of(&answer, "events", f.local_only), None, "아랫물 관점에는 이름이 없고 설명만 있다");
    // 띠의 관점도 함께 온다.
    assert_eq!(name_of(&answer, "bands", f.band).as_deref(), Some("윗쪽 사람들"));
}

#[test]
fn 나라마다_제_이름은_그_항목이_놓인_트랙의_이름이다() {
    let f = build("local");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"lens_names","lens":"local"})).unwrap();
    // 같은 사건이라도 **그 자리의 트랙**에 따라 이름이 갈린다.
    assert_eq!(name_of(&answer, "events", f.war).as_deref(), Some("꿈 반환 전쟁"), "첫 자리는 윗물의 줄에 있다");
    assert_eq!(name_of(&answer, "events", f.war_pair).as_deref(), Some("독립 저울 전쟁"), "둘째 자리는 아랫물의 줄에 있다");
    // 윗물의 관점만 적힌 사건은 아랫물의 줄에 놓여 있으므로 'local'에서는 바뀌지 않는다.
    assert_eq!(name_of(&answer, "events", f.local_only), None);
    // 띠는 아랫물의 관점만 있는데 아랫물의 줄에 있지 않으므로 바뀌지 않는다.
    assert_eq!(name_of(&answer, "bands", f.band), None);
}

#[test]
fn 윗물의_관점은_제_줄의_사건에_붙는다() {
    let f = build("north");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"lens_names","lens":f.north.to_string()})).unwrap();
    assert_eq!(name_of(&answer, "events", f.war).as_deref(), Some("꿈 반환 전쟁"));
    assert_eq!(name_of(&answer, "events", f.local_only).as_deref(), Some("잊힌 물길의 일"));
    assert_eq!(answer["bands"], json!({}), "윗물의 관점을 가진 띠는 없다");
}

#[test]
fn 이름이_하나도_없는_관점은_빈_결과다() {
    let f = build("empty");
    let store = Store::open(&f.path).unwrap();
    // 저장소에 없는 트랙 번호는 실패가 아니라 빈 결과다(찾을 것이 없을 뿐 — 계약 0절).
    let answer = ask(&store, json!({"op":"lens_names","lens":"99"})).unwrap();
    assert_eq!(answer, json!({"events":{},"bands":{}}));
    // 켠 자료집이 없으면 볼 것이 없다.
    let none = ask(&store, json!({"op":"lens_names","lens":"local","packs":[]})).unwrap();
    assert_eq!(none, json!({"events":{},"bands":{}}));
}

#[test]
fn 모르는_관점은_한국어_까닭으로_거절한다() {
    let f = build("bad");
    let store = Store::open(&f.path).unwrap();
    let fail = |q: Value| ask(&store, q).unwrap_err().to_string();
    assert!(fail(json!({"op":"lens_names"})).contains("관점(lens) 누락"));
    assert!(fail(json!({"op":"lens_names","lens":""})).contains("모르는 관점입니다"));
    assert!(fail(json!({"op":"lens_names","lens":"나라마다"})).contains("모르는 관점입니다"));
    assert!(fail(json!({"op":"lens_names","lens":["local"]})).contains("트랙 번호"));
}

#[test]
fn 거르개로_끈_것은_관점_이름에도_실리지_않는다() {
    let f = build("filter");
    let store = Store::open(&f.path).unwrap();
    // 아랫물 트랙을 끄면 그 줄의 자리(둘째 자리)와 그 줄의 띠가 빠진다.
    let answer = ask(&store, json!({"op":"lens_names","lens":f.south.to_string(),"filter":{"tracks_off":[f.south]}})).unwrap();
    assert_eq!(name_of(&answer, "events", f.war).as_deref(), Some("독립 저울 전쟁"), "윗물의 자리는 남는다");
    assert_eq!(name_of(&answer, "events", f.war_pair), None, "꺼진 트랙의 자리는 빠진다");
    // 중요도 문턱에도 걸린다(검사 자료의 사건은 모두 중요도 2다).
    let strict = ask(&store, json!({"op":"lens_names","lens":"local","filter":{"min_importance":3}})).unwrap();
    assert_eq!(strict["events"], json!({}));
}

/// 화면(Dart)은 수를 소수 꼴로도 보낸다 — 정수로 물은 것과 답이 같아야 한다(어제의 교훈).
#[test]
fn 수를_소수_꼴로_물어도_답이_같다() {
    let f = build("float");
    let store = Store::open(&f.path).unwrap();
    let whole = ask(&store, json!({"op":"lens_names","lens":"local","packs":[1],"filter":{"min_importance":2}})).unwrap();
    let float = ask(&store, json!({"op":"lens_names","lens":"local","packs":[1.0],"filter":{"min_importance":2.0}})).unwrap();
    assert_eq!(whole, float);
    // 트랙 번호를 수로 보내도(글이 아니라) 같은 답이다.
    let text = ask(&store, json!({"op":"lens_names","lens":f.south.to_string()})).unwrap();
    let number = ask(&store, json!({"op":"lens_names","lens":f.south as f64})).unwrap();
    assert_eq!(text, number);
}

/// 넣을 때 펴 둔 표(`lens_names`)가 없는 옛 저장소도 같은 답을 준다 — 그 자리에서 항목 기록을 훑는다.
#[test]
fn 이름_표가_없는_옛_저장소도_같은_답을_준다() {
    let f = build("legacy");
    {
        // 표를 지워 옛 저장소를 흉내 낸다(읽기 전용으로 열기 전에).
        let db = rusqlite::Connection::open(&f.path).unwrap();
        db.execute_batch("DROP TABLE lens_names;").unwrap();
    }
    let store = Store::open(&f.path).unwrap();
    assert!(!store.has_lens_names);
    let answer = ask(&store, json!({"op":"lens_names","lens":"local"})).unwrap();
    assert_eq!(name_of(&answer, "events", f.war).as_deref(), Some("꿈 반환 전쟁"));
    assert_eq!(name_of(&answer, "events", f.war_pair).as_deref(), Some("독립 저울 전쟁"));
}

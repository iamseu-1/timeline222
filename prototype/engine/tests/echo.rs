//! 같은 시기 타국(메아리) 조회와, 칸 상세가 부르는 '이 시기의 사건'(`events_in`)의 검사.
//! 명세 06의 3-4절 · 계약 2-1절. 자료는 이 검사만 쓰는 작은 정답 저장소다(띠 넷 · 사건 아홉).
use archive_engine::builder::{Builder, CellIn, EventIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::{Result, Store, DAY};
use serde_json::{json, Value};
use std::path::PathBuf;

const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: -1, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

/// 하루 = 1,440분. 검사의 시각은 모두 '몇째 날'로 적는다.
fn day(n: i64) -> i64 {
    n * DAY
}

/// 사건의 `rail` 8~10비트 = 날짜 정밀도(계약 6-6). 이 검사의 사건은 모두 **날짜까지 적은 것**으로 둔다 —
/// 걸침은 달력 단위로 재므로(계약 2-1절의 '걸침의 뜻' · `span::span_hit`), 연도만 적었다고 하면
/// `day(10)`의 사건이 '그해 한가운데'(7월 초)로 밀려 하루 단위로 잡은 조명에 걸리지 않는다.
/// 연도만 적은 사건의 경계 셈은 아래 `경계_해만_적은_사건은_…` 검사가 따로 본다.
const DAY_PREC: i64 = 2 << 8;

/// 사건의 `look` 비트(계약 6-6) — 조약 · 공동 · 다른 자리 · 하위.
const TREATY: i64 = 1 << 16;
const SHARED: i64 = 1 << 17;
const PAIR: i64 = 1 << 18;
const CHILD: i64 = 1 << 19;

struct Fixture {
    path: PathBuf,
    /// 띠 번호: 물빛나라(줄 0) · 돌기슭(줄 1) · 밤여울(줄 2)
    water: i64,
    stone: i64,
    night: i64,
}

/// 띠 넷 · 사건 아홉의 작은 저장소. 조명은 늘 '물빛나라의 0~100일'로 잡는다.
fn build(name: &str) -> Fixture {
    let path = std::env::temp_dir().join(format!("archive-echo-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    let plain = RowExtra::default();
    let north = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "north" }).unwrap();
    let south = b.track_full(&TrackIn { pack, name: "아랫물", color: 0xa0bcc5, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "south" }).unwrap();
    let row0 = b.row_full(north, &GEO, &plain).unwrap();
    let row1 = b.row_full(north, &GEO, &plain).unwrap();
    let row2 = b.row_full(south, &GEO, &plain).unwrap();
    // 트랙의 '그 밖' 줄 — 띠가 없는 사건이 앉는 곳.
    let row3 = b.row_full(south, &GEO, &RowExtra { kind: 2, ..RowExtra::default() }).unwrap();
    let band = |b: &mut Builder, row: i64, from: i64, to: i64, uid: &str, name: &str, color: u32| {
        b.period_full(&PeriodIn { pack, row, start: day(from), end: day(to) + DAY - 1, fuzzy: 0, color, name, look: 0, tag: "", sub: 0, uid, variant: 0, form: 0 }).unwrap()
    };
    let water = band(&mut b, row0, -100, 400, "band-water", "물빛나라", 0xa0bcc5);
    let stone = band(&mut b, row1, -100, 400, "band-stone", "돌기슭", 0x9dbea8);
    let night = band(&mut b, row2, -100, 400, "band-night", "밤여울", 0xd1a9b9);
    // 밤여울보다 늦게 선 나라 — 메아리 구간을 '띠가 있던 때'로 자르는지 본다.
    let late = band(&mut b, row2, 500, 900, "band-late", "늦바람", 0xb9a9d1);

    let mut put = |uid: &str, lane: i64, band: i64, from: i64, to: i64, look: i64, title: &str| {
        b.event(&EventIn { pack, lane, start: Some(day(from)), end: Some(day(to)), lo: None, hi: None, importance: 2, title,
            body: "검사 본문", source: None, raw: None, look, label: "", rail: DAY_PREC, uid, band, variant: 0 }).unwrap()
    };
    // 1 제 것(조명 안) · 2 제 띠이지만 조명 밖(메아리에서도 빠진다)
    put("e-own", row0, water, 10, 10, 0, "물빛 제 것");
    put("e-water-out", row0, water, 300, 300, 0, "물빛 조명 밖");
    // 3 메아리 · 4 메아리 기간 밖
    let echoed = put("e-stone", row1, stone, 20, 20, 0, "돌기슭 메아리");
    put("e-stone-far", row1, stone, 300, 300, 0, "돌기슭 먼 사건");
    // 5 하위 사건(부모가 3번) · 6 띠 없는 사건 · 7 조약
    let kid = put("e-stone-kid", row1, stone, 30, 30, CHILD, "돌기슭 하위");
    put("e-common", row3, 0, 40, 40, 0, "그 밖 줄의 사건");
    put("e-night", row2, night, 50, 50, TREATY, "밤여울 조약");
    // 8 늦바람은 조명 때에 아직 없던 나라다(띠 구간 밖이라 메아리가 아니다)
    put("e-late", row2, late, 600, 600, 0, "늦바람 뒷일");
    // 9 여러 자리에 놓인 공동 사건 — 첫 자리는 물빛(조명 밖), 둘째 자리는 밤여울(메아리 안)
    put("e-pair", row0, water, 310, 310, SHARED, "함께 겪은 일");
    put("e-pair#1", row2, night, 60, 60, SHARED | PAIR, "함께 겪은 일");
    // 구역 32: 하위 사건의 부모 기간(자식마다 하나 · name이 부모의 uid)
    b.item(&ItemIn { pack, section: 32, row: row1, row2: row1, start: day(20), end: day(20), lod: None, ref_id: kid, ref_kind: 2,
        name: "e-stone", color: 0x9dbea8, a: 1, b: 90, c: 80, d: 0, text2: "돌기슭 메아리", variant: 0 }).unwrap();
    assert!(echoed > 0);
    // 띠 안 칸 넷(지도자 · 내각 · 시기 구분 · 지위) — 칸 참조의 순번은 style의 15비트 위에 싣는다(계약 6-2).
    let seq = |n: i64| (n + 1) << 15;
    for (kind, style, name) in [(1i64, seq(3), "3대 가람"), (2, seq(1), "밤여울 내각"), (4, seq(2) | 32, "첫 체계\t다스림기"), (5, seq(0) | (3 << 8), "대공국")] {
        b.cell_full(&CellIn { period: night, kind, start: day(0), end: day(80), name, lane: 0, style, color: 0, variant: 0 }).unwrap();
    }
    // 공동 사건의 둘째 자리는 제 항목 기록이 없고 밑동의 기록을 함께 쓴다.
    b.entity("e-pair", pack, "event", r#"{"uid":"e-pair","title":"함께 겪은 일"}"#).unwrap();
    b.finalize(&[("seed", "메아리".to_owned())]).unwrap();
    Fixture { path, water, stone, night }
}

/// 경계 해 검사만 쓰는 작은 저장소 — 띠 하나에 **연도만 적은** 사건 셋(1970년 · 1971년 · 1970~1971년).
/// `day(0)` = 1970-01-01 · `day(365)` = 1971-01-01 · `day(730)` = 1972-01-01이다.
fn build_edge(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-echo-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    let track = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8_b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "north" }).unwrap();
    let row = b.row_full(track, &GEO, &RowExtra::default()).unwrap();
    let band = b.period_full(&PeriodIn { pack, row, start: day(-400), end: day(1200), fuzzy: 0, color: 0xa0_bcc5,
        name: "해넘이나라", look: 0, tag: "", sub: 0, uid: "band-edge", variant: 0, form: 0 }).unwrap();
    let mut put = |uid: &str, from: i64, to: i64, title: &str| {
        b.event(&EventIn { pack, lane: row, start: Some(day(from)), end: Some(day(to)), lo: None, hi: None, importance: 2, title,
            body: "검사 본문", source: None, raw: None, look: 0, label: "", rail: 0, uid, band, variant: 0 }).unwrap()
    };
    put("e-old", 0, 0, "묵은해의 일");
    put("e-new", 365, 365, "새해의 일");
    put("e-span", 0, 365, "두 해에 걸친 일");
    // 경계 분(1971-01-01 0시 = 뒤 칸의 첫 분)에 걸친 것들 — 한가운데 한 점으로 밀리지 않아 경계를 그대로 본다.
    // ① 그 분에서 **시작하는** 기간 사건(연도만 적었으나 끝이 다른 해라 기간으로 잰다).
    b.event(&EventIn { pack, lane: row, start: Some(day(365)), end: Some(day(730)), lo: None, hi: None, importance: 2,
        title: "경계에서 시작한 난리", body: "검사 본문", source: None, raw: None, look: 0, label: "", rail: 0, uid: "e-edge-span", band, variant: 0 }).unwrap();
    // ② 분까지 적어 그 분에 놓인 점 사건(rail 8~10비트 = 4).
    b.event(&EventIn { pack, lane: row, start: Some(day(365)), end: Some(day(365)), lo: None, hi: None, importance: 2,
        title: "경계 분의 일", body: "검사 본문", source: None, raw: None, look: 0, label: "", rail: 4 << 8, uid: "e-edge-point", band, variant: 0 }).unwrap();
    b.finalize(&[("seed", "경계 해".to_owned())]).unwrap();
    path
}

/// 소속 딱지 검사만 쓰는 작은 저장소 — 상국 띠 하나와, **소속 펼치기 변형에서만 서는** 속국 띠 **둘**.
/// 기본 상태에서 속국의 사건은 상국 띠 안에 그려지고(`events.band` = 상국), 변형을 켜면 속국의 줄로 이사한다.
///
/// 속국 둘은 시기가 겹치지 않아 **한 줄에 나란히 선다**(지금 연표의 `chainRows` — `js/timeline.js:2691`).
/// 줄만 보고 띠를 고르면 뒤 속국의 사건에도 앞 속국의 이름이 붙으므로, 때를 함께 보는지가 이 견본의 요점이다.
fn build_member(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-echo-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    let track = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8_b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "north" }).unwrap();
    let host_row = b.row_full(track, &GEO, &RowExtra::default()).unwrap();
    let variant = b.variant("host:band-host", 1, track, 0, "", "은륜 제국", "").unwrap();
    // 소속 줄(kind 1)은 그 변형에서만 선다.
    let member_row = b.row_full(track, &GEO, &RowExtra { kind: 1, variant, ..RowExtra::default() }).unwrap();
    let host = b.period_full(&PeriodIn { pack, row: host_row, start: day(-100), end: day(400), fuzzy: 0, color: 0xa0_bcc5,
        name: "은륜 제국", look: 0, tag: "", sub: 0, uid: "band-host", variant: 0, form: 0 }).unwrap();
    b.period_full(&PeriodIn { pack, row: member_row, start: day(-50), end: day(300), fuzzy: 0, color: 0x9d_bea8,
        name: "파도문 자치령", look: 5, tag: "", sub: 0, uid: "band-client", variant, form: 0 }).unwrap();
    // 앞 속국이 스러진 뒤 같은 줄을 이어받는 뒤 속국(번호가 더 크다).
    b.period_full(&PeriodIn { pack, row: member_row, start: day(310), end: day(400), fuzzy: 0, color: 0xb9_a9d1,
        name: "별목 상단", look: 5, tag: "", sub: 0, uid: "band-client2", variant, form: 0 }).unwrap();
    b.variant_band(variant, host).unwrap();
    b.variant_row(variant, member_row, host_row, 0, true, 0, 0).unwrap();
    let charter = b.event(&EventIn { pack, lane: host_row, start: Some(day(10)), end: Some(day(10)), lo: None, hi: None, importance: 2,
        title: "서약의 성립", body: "검사 본문", source: None, raw: None, look: 0, label: "", rail: DAY_PREC, uid: "e-charter", band: host, variant: 0 }).unwrap();
    b.event(&EventIn { pack, lane: host_row, start: Some(day(20)), end: Some(day(20)), lo: None, hi: None, importance: 2,
        title: "상국의 일", body: "검사 본문", source: None, raw: None, look: 0, label: "", rail: DAY_PREC, uid: "e-host", band: host, variant: 0 }).unwrap();
    let late = b.event(&EventIn { pack, lane: host_row, start: Some(day(350)), end: Some(day(350)), lo: None, hi: None, importance: 2,
        title: "뒤 속국의 일", body: "검사 본문", source: None, raw: None, look: 0, label: "", rail: DAY_PREC, uid: "e-late", band: host, variant: 0 }).unwrap();
    // 그 변형을 켜면 이 사건들이 속국의 줄로 간다 — 곧 '이 사건은 그때 그 줄에 선 속국의 것'이라는 뜻이다.
    b.variant_move(variant, 2, charter, member_row).unwrap();
    b.variant_move(variant, 2, late, member_row).unwrap();
    b.finalize(&[("seed", "소속".to_owned())]).unwrap();
    path
}

fn ask(store: &Store, q: Value) -> Result<Value> {
    store.call(&q)
}

fn titles(list: &Value) -> Vec<String> {
    list.as_array().map(|rows| rows.iter().map(|r| r["title"].as_str().unwrap_or("").to_owned()).collect()).unwrap_or_default()
}

/// 물빛나라의 0~100일을 비추는 조명 하나.
fn spot(uid: &str) -> Value {
    json!({"uid":uid,"start":day(0),"end":day(100)})
}

#[test]
fn 제_것은_조명의_띠에서_그_구간에_걸린_사건이다() {
    let f = build("own");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":true})).unwrap();
    assert_eq!(titles(&answer["own"]), vec!["물빛 제 것"]);
    assert_eq!(answer["ownUids"], json!(["e-own"]));
    // 같은 띠의 조명 밖 사건은 제 것도 메아리도 아니다(제 조명을 뺀 구간이 비어 있다).
    assert!(!titles(&answer["echo"]).contains(&"물빛 조명 밖".to_owned()));
    assert_eq!(answer["spans"], json!([[day(0), day(100)]]));
}

#[test]
fn 메아리는_같은_시기_다른_나라의_사건이다() {
    let f = build("echo");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":true})).unwrap();
    let names = titles(&answer["echo"]);
    assert!(names.contains(&"돌기슭 메아리".to_owned()), "{names:?}");
    assert!(names.contains(&"밤여울 조약".to_owned()), "{names:?}");
    assert!(names.contains(&"그 밖 줄의 사건".to_owned()), "{names:?}");
    // 메아리 기간 밖 · 띠가 아직 없던 때의 사건은 들지 않는다.
    assert!(!names.contains(&"돌기슭 먼 사건".to_owned()), "{names:?}");
    assert!(!names.contains(&"늦바람 뒷일".to_owned()), "{names:?}");
    // 묶음은 연표 위에서 아래로: 돌기슭(줄 1) → 밤여울(줄 2) → 아랫물의 그 밖 줄
    let groups = answer["groups"].as_array().unwrap();
    let keys: Vec<i64> = groups.iter().map(|g| g["band"].as_i64().unwrap()).collect();
    assert_eq!(keys, vec![f.stone, f.night, 0]);
    assert_eq!(groups[0]["name"], "돌기슭");
    assert_eq!(groups[0]["track_name"], "윗물");
    assert_eq!(groups[0]["uid"], "band-stone");
    assert_eq!(groups[0]["folded"], json!(false));
    // 띠가 없는 사건은 제 트랙의 묶음에 들고 트랙 이름을 쓴다.
    assert_eq!(groups[2]["name"], "아랫물");
    assert_eq!(answer["count"], json!(4));
}

#[test]
fn 메아리를_끄면_제_것만_센다() {
    let f = build("off");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":false})).unwrap();
    assert_eq!(titles(&answer["own"]), vec!["물빛 제 것"]);
    assert_eq!(answer["echo"], json!([]));
    assert_eq!(answer["spans"], json!([]));
    assert_eq!(answer["count"], json!(0));
}

#[test]
fn 하위_사건은_부모_줄의_포함_수로_센다() {
    let f = build("kids");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":true})).unwrap();
    let names = titles(&answer["echo"]);
    assert!(!names.contains(&"돌기슭 하위".to_owned()), "하위 사건은 제 줄로 나오지 않는다: {names:?}");
    let groups = answer["groups"].as_array().unwrap();
    let parent = groups[0]["events"].as_array().unwrap().iter().find(|e| e["title"] == "돌기슭 메아리").unwrap();
    assert_eq!(parent["kids"], json!(1));
}

#[test]
fn 여러_자리에_놓인_사건은_한_번만_나온다() {
    let f = build("pair");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":true})).unwrap();
    let hits: Vec<String> = titles(&answer["echo"]).into_iter().filter(|t| t == "함께 겪은 일").collect();
    assert_eq!(hits.len(), 1, "공동 사건은 한 줄만: {:?}", titles(&answer["echo"]));
    let row = answer["echo"].as_array().unwrap().iter().find(|e| e["title"] == "함께 겪은 일").unwrap();
    assert_eq!(row["uid"], "e-pair", "열쇠는 첫 자리의 이름이다");
    assert_eq!(row["shared"], json!(true));
    // 함께 겪은 다른 자리의 나라 이름(`함께 · 〈나라〉`) — 보이는 자리는 밤여울이므로 물빛나라가 꼬리표로 붙는다.
    assert_eq!(row["with"], json!(["물빛나라"]));
    let in_group = answer["groups"].as_array().unwrap().iter()
        .flat_map(|g| g["events"].as_array().unwrap().clone()).find(|e| e["title"] == "함께 겪은 일").unwrap();
    assert_eq!(in_group["with"], json!(["물빛나라"]), "묶음 안의 줄에도 같은 꼬리표가 붙는다");
    // 자리가 하나뿐인 사건에는 꼬리표가 없다.
    let alone = answer["echo"].as_array().unwrap().iter().find(|e| e["title"] == "밤여울 조약").unwrap();
    assert_eq!(alone["with"], json!([]));
    // 사건 번호는 두 자리를 모두 준다(연표가 점 하나하나를 흐리게 할 수 있도록).
    let ids = answer["echoIds"].as_array().unwrap().len();
    assert!(ids >= titles(&answer["echo"]).len(), "자리마다 번호가 실린다");
}

#[test]
fn 조명의_띠는_번호로도_이름으로도_준다() {
    let f = build("byid");
    let store = Store::open(&f.path).unwrap();
    let by_uid = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":true})).unwrap();
    let by_id = ask(&store, json!({"op":"echo","spots":[{"band":f.water,"start":day(0),"end":day(100)}],"echo":true})).unwrap();
    assert_eq!(by_uid, by_id);
}

#[test]
fn 겹치는_조명은_한_구간으로_합쳐진다() {
    let f = build("spans");
    let store = Store::open(&f.path).unwrap();
    // 구간은 반열린 `[시작, 끝)`이라 앞 칸의 끝이 곧 뒤 칸의 시작이다 — 그 둘이 '맞닿은' 것이다.
    let answer = ask(&store, json!({"op":"echo","echo":true,"spots":[
        {"uid":"band-water","start":day(0),"end":day(41)},
        {"uid":"band-water","start":day(41),"end":day(100)},
        {"uid":"band-stone","start":day(200),"end":day(220)}]})).unwrap();
    // 맞닿은 둘은 하나로, 떨어진 것은 따로.
    assert_eq!(answer["spans"], json!([[day(0), day(100)], [day(200), day(220)]]));
    // 한 분이라도 벌어지면 따로다.
    let gap = ask(&store, json!({"op":"echo","echo":true,"spots":[
        {"uid":"band-water","start":day(0),"end":day(41) - 1},
        {"uid":"band-water","start":day(41),"end":day(100)}]})).unwrap();
    assert_eq!(gap["spans"], json!([[day(0), day(41) - 1], [day(41), day(100)]]));
    assert!(f.water > 0);
}

#[test]
fn 메아리의_잘못된_입력은_한국어로_거절한다() {
    let f = build("bad");
    let store = Store::open(&f.path).unwrap();
    let fail = |q: Value| ask(&store, q).unwrap_err().to_string();
    assert!(fail(json!({"op":"echo"})).contains("조명 목록"));
    assert!(fail(json!({"op":"echo","spots":[{"uid":"band-water","start":day(10),"end":day(1)}]})).contains("뒤집혔"));
    assert!(fail(json!({"op":"echo","spots":[{"start":day(0),"end":day(10)}]})).contains("정권 이름"));
    assert!(fail(json!({"op":"echo","spots":[spot("band-water")],"echo":"예"})).contains("참 또는 거짓"));
    // 없는 이름은 실패가 아니다 — 그 조명이 가리키는 띠가 없을 뿐이라 제 것은 없고 그 기간은 그대로 메아리가 된다
    // (지금 연표도 띠를 못 찾은 조명의 기간을 메아리로 삼는다).
    let empty = ask(&store, json!({"op":"echo","spots":[spot("없는-이름")],"echo":true})).unwrap();
    assert_eq!(empty["own"], json!([]));
    assert_eq!(empty["spans"], json!([[day(0), day(100)]]));
    assert!(empty["count"].as_i64().unwrap() > 0);
}

#[test]
fn 이_시기의_사건은_정권_이름으로도_묻는다() {
    let f = build("eventsin");
    let store = Store::open(&f.path).unwrap();
    let by_uid = ask(&store, json!({"op":"events_in","band":"band-night","lo":day(0),"hi":day(100),"limit":10})).unwrap();
    let by_id = ask(&store, json!({"op":"events_in","band":f.night,"lo":day(0),"hi":day(100),"limit":10})).unwrap();
    assert_eq!(by_uid["items"], by_id["items"]);
    // 상세 창이 읽는 이름도 함께 실린다.
    assert_eq!(by_uid["events"], by_uid["items"]);
    assert_eq!(by_uid["more"], by_uid["has_more"]);
    let rows = by_uid["events"].as_array().unwrap();
    assert_eq!(rows.len(), 2, "밤여울의 조약과 공동 사건의 둘째 자리");
    let treaty = rows.iter().find(|r| r["title"] == "밤여울 조약").unwrap();
    assert_eq!(treaty["treaty"], json!(true));
    assert_eq!(treaty["prec"], "d");
    assert_eq!(treaty["color"], json!(0xd1a9b9));
    assert!(treaty["when"].as_str().unwrap().ends_with('년'), "{}", treaty["when"]);
}

// ── 걸침을 달력 단위로 재기(계약 2-1절의 '걸침의 뜻' · 지금 연표의 `HT.spanHit`) ───────────────────

#[test]
fn 경계_해만_적은_사건은_앞뒤_칸_가운데_한쪽에만_든다() {
    let path = build_edge("edge");
    let store = Store::open(&path).unwrap();
    let names = |lo: i64, hi: i64| -> Vec<String> {
        titles(&ask(&store, json!({"op":"events_in","band":"band-edge","lo":lo,"hi":hi,"limit":50})).unwrap()["items"])
    };
    // 앞 칸은 1970년이고 그 끝을 **다음 칸의 첫 분**(1971-01-01)까지 적어 보낸다 — 지금 연표의 칸 경계가 그렇다.
    // 옛 셈(`시작 ≤ 끝 && 끝 ≥ 시작`)이면 '새해의 일'이 앞뒤 두 칸에 모두 들었다.
    let first = names(day(0), day(365));
    assert!(first.contains(&"묵은해의 일".to_owned()), "{first:?}");
    assert!(!first.contains(&"새해의 일".to_owned()), "경계 해의 사건은 뒤 칸의 것이다: {first:?}");
    let second = names(day(365), day(730));
    assert!(second.contains(&"새해의 일".to_owned()), "{second:?}");
    assert!(!second.contains(&"묵은해의 일".to_owned()), "{second:?}");
}

/// 칸의 `hi`는 **뒤 칸의 첫 분**이다(반열린 구간 — 계약 2-1절). 한가운데 한 점으로 밀리지 않는 것들이
/// 그 경계에서 갈리는지 본다: 위의 `경계_해만_적은_…`는 연도만 적은 한 해짜리 사건이라 한가운데로 밀려
/// 한 분쯤 어긋나도 답이 같았다 — 이 검사가 그 구멍을 막는다.
#[test]
fn 경계_분에서_시작하는_것은_뒤_칸에만_든다() {
    let path = build_edge("edge-minute");
    let store = Store::open(&path).unwrap();
    let names = |lo: i64, hi: i64| -> Vec<String> {
        titles(&ask(&store, json!({"op":"events_in","band":"band-edge","lo":lo,"hi":hi,"limit":50})).unwrap()["items"])
    };
    // 앞 칸 [1970, 1971) · 뒤 칸 [1971, 1972) — 화면은 앞 칸의 hi로 1971-01-01을 그대로 보낸다.
    let first = names(day(0), day(365));
    let second = names(day(365), day(730));
    for title in ["경계에서 시작한 난리", "경계 분의 일"] {
        assert!(!first.contains(&title.to_owned()), "{title}은 앞 칸에 들지 않는다: {first:?}");
        assert!(second.contains(&title.to_owned()), "{title}은 뒤 칸의 것이다: {second:?}");
    }
    // 메아리의 '제 것'도 같은 셈이다.
    let lit = |start: i64, end: i64| -> Vec<String> {
        titles(&ask(&store, json!({"op":"echo","spots":[{"uid":"band-edge","start":start,"end":end}],"echo":false})).unwrap()["own"])
    };
    assert!(!lit(day(0), day(365)).contains(&"경계 분의 일".to_owned()));
    assert!(lit(day(365), day(730)).contains(&"경계 분의 일".to_owned()));
}

#[test]
fn 연도만_적은_기간_사건은_끝난_해의_남은_날까지_걸친다() {
    let path = build_edge("edge-span");
    let store = Store::open(&path).unwrap();
    let names = |lo: i64, hi: i64| -> Vec<String> {
        titles(&ask(&store, json!({"op":"events_in","band":"band-edge","lo":lo,"hi":hi,"limit":50})).unwrap()["items"])
    };
    // 1970~1971년의 사건은 1971년의 마지막 날까지 걸치고, 1972년에는 걸치지 않는다.
    assert!(names(day(0), day(365)).contains(&"두 해에 걸친 일".to_owned()));
    assert!(names(day(700), day(729)).contains(&"두 해에 걸친 일".to_owned()), "끝난 해의 남은 날에도 걸린다");
    let next = names(day(730), day(1095));
    assert!(!next.contains(&"두 해에 걸친 일".to_owned()), "그 다음 해에는 걸치지 않는다: {next:?}");
}

#[test]
fn 메아리도_같은_달력_단위로_잰다() {
    let path = build_edge("edge-echo");
    let store = Store::open(&path).unwrap();
    // 제 것(조명의 띠)도 같은 셈이다 — 1970년만 비추면 '새해의 일'은 들지 않는다.
    let answer = ask(&store, json!({"op":"echo","spots":[{"uid":"band-edge","start":day(0),"end":day(365)}],"echo":true})).unwrap();
    let own = titles(&answer["own"]);
    assert!(own.contains(&"묵은해의 일".to_owned()), "{own:?}");
    assert!(!own.contains(&"새해의 일".to_owned()), "{own:?}");
    assert!(own.contains(&"두 해에 걸친 일".to_owned()), "{own:?}");
}

// ── 상국 띠 아래에 접혀 숨은 소속(`소속 · 〈나라〉`) ───────────────────────────────────────────

#[test]
fn 상국_띠에_숨은_소속의_사건에는_소속_이름이_붙는다() {
    let path = build_member("member");
    let store = Store::open(&path).unwrap();
    let answer = ask(&store, json!({"op":"events_in","band":"band-host","lo":day(0),"hi":day(100),"limit":50})).unwrap();
    let rows = answer["events"].as_array().unwrap();
    let charter = rows.iter().find(|r| r["title"] == "서약의 성립").unwrap();
    assert_eq!(charter["member"], "파도문 자치령", "속국의 사건에는 그 속국의 이름이 붙는다");
    let host = rows.iter().find(|r| r["title"] == "상국의 일").unwrap();
    assert_eq!(host["member"], "", "상국 제 사건에는 붙지 않는다");
    // 메아리의 '제 것'에도 같은 딱지가 붙는다.
    let echo = ask(&store, json!({"op":"echo","spots":[{"uid":"band-host","start":day(0),"end":day(100)}],"echo":true})).unwrap();
    let own = echo["own"].as_array().unwrap().iter().find(|r| r["title"] == "서약의 성립").unwrap();
    assert_eq!(own["member"], "파도문 자치령");
}

/// 한 줄에 속국이 둘 서면 **그때 그 줄에 선 속국**의 이름이 붙는다 — 줄만 보고 번호가 가장 작은 띠를 고르면
/// 뒤 속국의 사건에도 앞 속국의 이름이 붙었다(지금 연표는 `chainRows`로 속국을 한 줄에 몰아 넣는다).
#[test]
fn 한_줄에_속국이_둘이면_그때의_속국_이름이_붙는다() {
    let path = build_member("member-two");
    let store = Store::open(&path).unwrap();
    let answer = ask(&store, json!({"op":"events_in","band":"band-host","lo":day(0),"hi":day(400),"limit":50})).unwrap();
    let rows = answer["events"].as_array().unwrap();
    let name = |title: &str| rows.iter().find(|r| r["title"] == title).unwrap()["member"].clone();
    assert_eq!(name("서약의 성립"), "파도문 자치령", "앞 속국의 때에 있던 사건");
    assert_eq!(name("뒤 속국의 일"), "별목 상단", "뒤 속국의 때에 있던 사건");
    assert_eq!(name("상국의 일"), "", "상국 제 사건에는 붙지 않는다");
}

/// 숨은 속국을 조명하면 제 것이 나온다 — 저장소의 `events.band`에는 상국만 적혀 있어 한 줄도 없던 자리다
/// (지금 연표는 사건이 놓인 자리의 정권으로 보아 제 것으로 준다 — `js/core.js:783`의 `P === s.uid`).
#[test]
fn 숨은_속국을_조명하면_그_속국의_사건이_제_것으로_나온다() {
    let path = build_member("member-hidden");
    let store = Store::open(&path).unwrap();
    // ① 칸 창의 '이 시기의 사건'.
    let answer = ask(&store, json!({"op":"events_in","band":"band-client","lo":day(0),"hi":day(100),"limit":50})).unwrap();
    let rows = answer["events"].as_array().unwrap();
    assert_eq!(titles(&answer["events"]), vec!["서약의 성립"], "속국 제 사건만: {rows:?}");
    assert_eq!(rows[0]["member"], "", "속국 제 창에서는 소속 딱지를 붙이지 않는다");
    // 상국의 사건은 속국의 것이 아니다.
    let host_time = ask(&store, json!({"op":"events_in","band":"band-client","lo":day(15),"hi":day(30),"limit":50})).unwrap();
    assert_eq!(host_time["events"], json!([]), "상국 제 사건은 속국 창에 들지 않는다");
    // ② 같은 줄의 뒤 속국은 제 때의 사건만 가져간다.
    let later = ask(&store, json!({"op":"events_in","band":"band-client2","lo":day(300),"hi":day(400),"limit":50})).unwrap();
    assert_eq!(titles(&later["events"]), vec!["뒤 속국의 일"]);
    // ③ 메아리의 '제 것'도 같다 — 변형을 켜 두었든 껐든.
    for variants in [json!([]), json!(["host:band-host"])] {
        let echo = ask(&store, json!({"op":"echo","spots":[{"uid":"band-client","start":day(0),"end":day(100)}],"echo":true,"variants":variants})).unwrap();
        assert_eq!(titles(&echo["own"]), vec!["서약의 성립"], "변형 {variants}");
        assert_eq!(echo["own"][0]["member"], "", "변형 {variants}");
        // 속국의 조명은 상국 띠의 제 조명이기도 하다 — 그 구간의 상국 제 사건은 '같은 시기 타국'이 아니다.
        assert_eq!(titles(&echo["echo"]), Vec::<String>::new(), "변형 {variants}");
    }
}

#[test]
fn 소속을_펼쳐_둔_동안에는_소속_딱지를_붙이지_않는다() {
    let path = build_member("member-on");
    let store = Store::open(&path).unwrap();
    // 변형을 켜면 속국이 제 줄에 나와 있으므로 '숨은 소속'이 아니다(지금 연표의 `b.hidden` 조건).
    let answer = ask(&store, json!({"op":"events_in","band":"band-host","lo":day(0),"hi":day(100),"limit":50,"variants":["host:band-host"]})).unwrap();
    let charter = answer["events"].as_array().unwrap().iter().find(|r| r["title"] == "서약의 성립").unwrap();
    assert_eq!(charter["member"], "");
}

// ── 전역 검사가 찾은 어긋남(docs/검사-전역-계약-2026-09-22.md의 1 · 4 · 7절) ─────────────────────

#[test]
fn 띠_안_칸의_참조_번호는_style에서_읽는다() {
    let f = build("cellref");
    let store = Store::open(&f.path).unwrap();
    // 이름 검색: 지도자 · 내각뿐 아니라 시기 구분 · 지위 칸도 이름 표에 있고, 칸 참조가 함께 온다.
    let want = [("3대 가람", "leader:3", "지도자"), ("밤여울 내각", "cabinet:1", "내각"), ("다스림기", "phase:2", "시기 구분"), ("대공국", "rank:0", "지위")];
    for (name, cell, sub) in want {
        let answer = ask(&store, json!({"op":"search","text":name,"kinds":["cell"],"limit":10})).unwrap();
        let rows = answer["items"].as_array().unwrap();
        let hit = rows.iter().find(|r| r["name"] == name).unwrap_or_else(|| panic!("{name}을 찾지 못했다: {rows:?}"));
        assert_eq!(hit["cell"], cell, "{name}");
        assert!(hit["sub"].as_str().unwrap().ends_with(sub), "{}", hit["sub"]);
    }
    // 같은 해 보기의 지위 · 시기 줄도 그 칸을 여는 참조를 들고 온다.
    let same = ask(&store, json!({"op":"same_year","at":day(10)})).unwrap();
    let rank = same["eras"].as_array().unwrap().iter()
        .flat_map(|e| e["periods"].as_array().unwrap().clone()).find(|p| p["uid"] == "band-night").unwrap();
    assert_eq!(rank["rank"]["cell"], "rank:0");
    let phase = same["phases"].as_array().unwrap()[0]["cells"].as_array().unwrap()[0].clone();
    assert_eq!(phase["cell"], "phase:2");
    assert_eq!(phase["name"], "다스림기");
    assert_eq!(phase["scheme"], "첫 체계");
}

#[test]
fn 여러_자리에_놓인_사건은_밑동의_항목_기록을_쓴다() {
    let f = build("stem");
    let store = Store::open(&f.path).unwrap();
    // 둘째 자리(`…#1`)에는 제 기록이 없지만 밑동의 기록으로 창이 열린다.
    let answer = ask(&store, json!({"op":"entity","uid":"e-pair#1"})).unwrap();
    assert_eq!(answer["uid"], "e-pair#1");
    assert_eq!(answer["kind"], "event");
    assert!(answer["json"].as_str().unwrap().contains("함께 겪은 일"));
    // 여럿을 한 번에 물을 때도 같다.
    let many = ask(&store, json!({"op":"entities","uids":["e-pair#1","e-pair"]})).unwrap();
    assert_eq!(many.as_array().unwrap().len(), 2);
    assert_eq!(many[0]["uid"], "e-pair#1");
}

#[test]
fn 없는_항목_기록은_한국어_까닭으로_거절한다() {
    let f = build("noentity");
    let store = Store::open(&f.path).unwrap();
    let err = ask(&store, json!({"op":"entity","uid":"없는-이름"})).unwrap_err().to_string();
    assert!(err.contains("항목 기록이 없습니다"), "{err}");
    assert!(err.contains("없는-이름"), "{err}");
    assert!(!err.contains("QueryReturnedNoRows"), "{err}");
    // 밑동도 없으면 마찬가지다.
    let err = ask(&store, json!({"op":"entity","uid":"없는-이름#1"})).unwrap_err().to_string();
    assert!(err.contains("항목 기록이 없습니다"), "{err}");
}

#[test]
fn 없는_정권_이름의_이_시기의_사건은_빈_결과다() {
    let f = build("eventsin-empty");
    let store = Store::open(&f.path).unwrap();
    let answer = ask(&store, json!({"op":"events_in","band":"없는-이름","lo":day(0),"hi":day(100)})).unwrap();
    assert_eq!(answer["items"], json!([]));
    assert_eq!(answer["events"], json!([]));
    assert_eq!(answer["more"], json!(false));
    // 띠도 줄도 주지 않으면 거절한다.
    let err = ask(&store, json!({"op":"events_in","lo":0,"hi":1})).unwrap_err().to_string();
    assert!(err.contains("정권 이름"), "{err}");
    assert!(f.stone > 0);
}

/// 화면(Dart)은 분을 소수 꼴(`-615360960.0`)로도 보낸다 — 정수로 물은 것과 답이 같아야 한다.
/// (정수만 받던 때에는 실제 앱에서만 '이 시기의 사건' · 같은 시기 타국 · 같은 해 보기가 비었다 — 검사는 정수로만 물었다.)
#[test]
fn 분을_소수_꼴로_물어도_답이_같다() {
    let f = build("float");
    let store = Store::open(&f.path).unwrap();
    let (lo, hi) = (day(0) as f64, day(100) as f64);
    let whole = ask(&store, json!({"op":"echo","spots":[spot("band-water")],"echo":true})).unwrap();
    let float = ask(&store, json!({"op":"echo","spots":[{"uid":"band-water","start":lo,"end":hi}],"echo":true,"limit":400.0})).unwrap();
    assert_eq!(whole, float);
    let whole = ask(&store, json!({"op":"events_in","band":"band-water","lo":day(0),"hi":day(100),"limit":200})).unwrap();
    let float = ask(&store, json!({"op":"events_in","band":"band-water","lo":lo,"hi":hi,"limit":200.0})).unwrap();
    assert_eq!(whole, float);
    let whole = ask(&store, json!({"op":"same_year","at":day(10),"end":day(20),"window":day(365)})).unwrap();
    let float = ask(&store, json!({"op":"same_year","at":day(10) as f64,"end":day(20) as f64,"window":day(365) as f64})).unwrap();
    assert_eq!(whole, float);
    // 소수부는 반올림한다(누른 자리 그대로의 분은 정수가 아니다).
    let near = ask(&store, json!({"op":"same_year","at":day(10) as f64 + 0.4,"end":day(20) as f64 - 0.4,"window":day(365)})).unwrap();
    assert_eq!(whole, near);
}

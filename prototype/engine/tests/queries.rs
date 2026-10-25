//! 상세 창 · 검색 · 도구가 부르는 조회 명령(계약 2절의 뒤쪽) 검사.
//! 명령마다 정상 · 빈 결과 · 잘못된 입력(까닭과 함께 실패) · 나눠 받기의 이어짐 · 켠 자료집 · 기원전 범위를 본다.
//! 작은 정답 자료를 `Builder`로 직접 짓는다(`tests/common/mod.rs`와 같은 방식이되, 이름과 표현 값을 명령마다 짚을 수 있게 골랐다).
use archive_engine::builder::{AxisCellIn, Builder, CellIn, EventIn, GroupIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::{Store, DAY};
use serde_json::{json, Value};
use std::path::PathBuf;

const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: 12, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-query-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    path
}

/// 원형 그레고리력의 날 수(1970-01-01 = 0). `query::year_of`의 되돌림이다.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// 기원전 n년의 첫 분(0년 = 기원전 1년).
fn bc(n: i64) -> i64 {
    days_from_civil(1 - n, 1, 1) * DAY
}
/// 기원전 n년의 마지막 분.
fn bc_end(n: i64) -> i64 {
    bc(n - 1) - 1
}
/// 기원후 n년의 첫 분 · 마지막 분.
fn ad(n: i64) -> i64 {
    days_from_civil(n, 1, 1) * DAY
}
fn ad_end(n: i64) -> i64 {
    ad(n + 1) - 1
}

/// 띠 넷(기원전 둘 · 기원후 하나 · 다른 자료집 하나) · 칸 · 날짜 칸 · 항목 기록 · 일반 항목 · 사건 스물여섯.
struct Fixture {
    band_a: i64,
    band_b: i64,
    band_c: i64,
    band_d: i64,
    event_1: i64,
}

/// 한기 나라의 형식 4 뜻(스키마 4 · 계약 1-1 비트): 0 ~ 4 종류 + 1(국가 0 → 1) · 10 ~ 12 정통성 + 1(정통 → 1) · 13 ~ 15 중요도 + 1(2 → 3). 다른 띠는 0(모름).
const HANKI_FORM: i64 = 1 | 1 << 10 | 3 << 13;

fn build(path: &PathBuf) -> Fixture {
    let mut b = Builder::create(path).unwrap();
    let p1 = b.pack("검사용 하나", None).unwrap();
    let p2 = b.pack("검사용 둘", None).unwrap();
    b.category(p1, 0, "govern", "다스림", 0x8f_7fb0).unwrap();
    b.category(p1, 1, "build", "지음", 0x6f_9a86).unwrap();
    let t1 = b.track_full(&TrackIn { pack: p1, name: "첫 트랙", color: 0xc8_b193, dynasty: 1, leader: 1, cabinet: 1, organ: 1, rail_levels: 2, key: "mw-first" }).unwrap();
    let t2 = b.track_full(&TrackIn { pack: p2, name: "둘째 트랙", color: 0x9d_bea8, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "mw-second" }).unwrap();
    let r0 = b.row_full(t1, &GEO, &RowExtra::default()).unwrap();
    let r1 = b.row_full(t1, &GEO, &RowExtra::default()).unwrap();
    let r2 = b.row_full(t2, &GEO, &RowExtra::default()).unwrap();
    let r3 = b.row_full(t2, &GEO, &RowExtra::default()).unwrap();
    b.group(&GroupIn { track: t1, depth: 0, first_row: r0, row_count: 2, name: "윗물 겨레", color: 0xbc_d8c1, kind: 0 }).unwrap();
    // look: 아래 5비트 종류 · 5~6비트 확실성 · 8~10비트 실재성 · 18비트 할거기 칠(대범위).
    let band_a = b.period_full(&PeriodIn { pack: p1, row: r0, start: bc(500), end: bc_end(401), fuzzy: 1, color: 0xa0_bcc5,
        name: "한기 나라", look: 1 << 5, tag: "나라", sub: 0, uid: "b-hankinara", variant: 0, form: HANKI_FORM }).unwrap();
    let band_b = b.period_full(&PeriodIn { pack: p1, row: r0, start: bc(400), end: bc_end(301), fuzzy: 0, color: 0xd1_a9b9,
        name: "나래 나라", look: 5 | (2 << 5) | (2 << 8), tag: "종속국", sub: 0, uid: "b-narae", variant: 0, form: 0 }).unwrap();
    let band_c = b.period_full(&PeriodIn { pack: p1, row: r1, start: ad(1), end: ad_end(100), fuzzy: 0, color: 0xbc_d8c1,
        name: "해솔 연맹", look: 12 | (1 << 18), tag: "연맹", sub: 0, uid: "b-haesol", variant: 0, form: 0 }).unwrap();
    let band_d = b.period_full(&PeriodIn { pack: p2, row: r2, start: bc(450), end: bc_end(351), fuzzy: 0, color: 0x9d_bea8,
        name: "별여울 나라", look: 0, tag: "", sub: 0, uid: "b-byeol", variant: 0, form: 0 }).unwrap();
    // 칸: 지도자 · 내각 · 왕조(같은 이름의 항목 기록이 자리를 빌려 간다) · 인물 · 예속 · 모호한 칸 · 이설이 있는 칸.
    b.cell(band_a, 1, bc(500), bc_end(451), "첫 가람왕").unwrap();
    b.cell_full(&CellIn { period: band_a, kind: 1, start: bc(450), end: bc_end(401), name: "둘째 나래왕", lane: 0, style: 4, color: 0, variant: 0 }).unwrap();
    b.cell(band_a, 2, bc(500), bc_end(451), "가람 내각").unwrap();
    b.cell(band_a, 0, bc(500), bc_end(401), "가람 왕조").unwrap();
    b.cell(band_a, 6, bc(480), bc_end(441), "아란 벼리").unwrap();
    b.cell_full(&CellIn { period: band_a, kind: 7, start: bc(470), end: bc_end(451), name: "해솔 속국", lane: 0, style: 1 << 11, color: 0, variant: 0 }).unwrap();
    b.cell_full(&CellIn { period: band_b, kind: 1, start: bc(400), end: bc_end(301), name: "셋째 별왕", lane: 0, style: 8, color: 0, variant: 0 }).unwrap();
    b.cell_full(&CellIn { period: band_c, kind: 1, start: ad(1), end: ad_end(100), name: "넷째 해솔왕", lane: 0, style: 128, color: 0, variant: 0 }).unwrap();
    b.cell(band_d, 1, bc(450), bc_end(351), "다섯째 별여울왕").unwrap();
    // 날짜 칸: 연호 · 도읍(트랙에 붙는다) · 공통 줄의 시대 구분.
    b.axis_cell(&AxisCellIn { pack: p1, kind: 2, track: Some(t1), lane: 0, start: bc(500), end: bc_end(401), name: "첫길 연호", color: 0xc8_b193, style: 0, strip: 1, seq: 0 }).unwrap();
    b.axis_cell(&AxisCellIn { pack: p1, kind: 3, track: Some(t1), lane: 0, start: bc(500), end: bc_end(301), name: "가람 도읍", color: 0xc8_b193, style: 0, strip: 2, seq: 0 }).unwrap();
    b.axis_cell(&AxisCellIn { pack: p1, kind: 1, track: None, lane: 0, start: bc(500), end: ad_end(100), name: "첫 시대", color: 0x9d_bea8, style: 0, strip: 0, seq: 0 }).unwrap();
    b.axis_cell(&AxisCellIn { pack: p2, kind: 2, track: Some(t2), lane: 0, start: bc(450), end: bc_end(351), name: "둘째 연호", color: 0x9d_bea8, style: 0, strip: 3, seq: 0 }).unwrap();
    b.epoch(p1, bc(500), ad_end(100), 0x9d_bea8, "첫 시대").unwrap();
    // 항목 기록: 띠에 붙는 것 · 제 줄이 없는 것(인물 · 왕조 · 시대 구분 · 가문) · 사건(이름 표에는 들어가지 않는다).
    b.entity("b-hankinara", p1, "period", r#"{"uid":"b-hankinara","name":"한기 나라"}"#).unwrap();
    b.entity("b-haesol", p1, "period", r#"{"uid":"b-haesol","name":"해솔 연맹"}"#).unwrap();
    b.entity("f-aran", p1, "figure", r#"{"uid":"f-aran","name":"아란 벼리"}"#).unwrap();
    b.entity("dyn-garam", p1, "dynasty", r#"{"uid":"dyn-garam","name":"가람 왕조"}"#).unwrap();
    b.entity("ep-first", p1, "epoch", r#"{"uid":"ep-first","name":"첫 시대"}"#).unwrap();
    b.entity("h-namu", p1, "house", r#"{"uid":"h-namu","name":"나무 가문"}"#).unwrap();
    b.entity("ev-1", p1, "treaty", r#"{"uid":"ev-1","title":"해솔 나루의 맹세"}"#).unwrap();
    // 일반 항목: 37 인물 막대(인물이 자리를 빌려 간다) · 16 속국 이름표 · 35 이설.
    b.item(&ItemIn { pack: p1, section: 37, row: r0, row2: r0, start: bc(480), end: bc_end(441), lod: None, ref_id: band_a, ref_kind: 1,
        name: "아란 벼리", color: 0xa0_bcc5, a: 0, b: 3, c: 0, d: 0, text2: "f-aran|-80000000000|-79000000000", variant: 0 }).unwrap();
    b.item(&ItemIn { pack: p1, section: 16, row: r0, row2: r0, start: bc(470), end: bc_end(451), lod: None, ref_id: band_a, ref_kind: 1,
        name: "해솔 속국", color: 0xbc_d8c1, a: 0, b: 1, c: 0, d: 0, text2: "b-haesol", variant: 0 }).unwrap();
    b.item(&ItemIn { pack: p1, section: 35, row: r1, row2: r1, start: ad(1), end: ad_end(3), lod: None, ref_id: 0, ref_kind: 0,
        name: "다른 견해", color: 0xbc_d8c1, a: 0, b: 1, c: 1, d: 0, text2: "", variant: 0 }).unwrap();
    let event_1;
    {
        let mut add = |uid: &str, title: &str, row: i64, band: i64, pack: i64, start: Option<i64>, end: Option<i64>, importance: i64, look: i64, rail: i64, label: &str| -> i64 {
            b.event(&EventIn { pack, lane: row, start, end, lo: None, hi: None, importance, title, body: "검사 본문", source: None, raw: None,
                look, label, rail, uid, band, variant: 0 }).unwrap()
        };
        // 조약(look 16비트) · 이설 있음(rail 5비트).
        event_1 = add("ev-1", "해솔 나루의 맹세", r1, band_c, p1, Some(ad(1)), Some(ad(1)), 3, 1 << 16, 32 | 4, "1년");
        add("ev-2", "해솔 나루의 다툼", r1, band_c, p1, Some(ad(20)), Some(ad(20)), 2, 1, 0, "20년");
        add("ev-3", "나래 벌의 약속", r0, band_b, p1, Some(bc(380)), Some(bc(380)), 1, 0, 0, "기원전 380년");
        // 추정 연대(look 20비트).
        add("ev-4", "한기 들의 첫 씨앗", r0, band_a, p1, Some(bc(480)), Some(bc(480)), 3, 1 << 20, 0, "기원전 480년");
        add("ev-5", "한기 들의 긴 가뭄", r0, band_a, p1, Some(bc(470)), Some(bc_end(461)), 2, 0, 0, "기원전 470년");
        for n in 0..4i64 {
            add(&format!("ev-{}", 6 + n), &format!("해솔 들의 작은 일 {}", n + 1), r1, band_c, p1, Some(ad(30 + n)), Some(ad(30 + n)), 1, 0, 0, &format!("{}년", 30 + n));
        }
        add("ev-10", "별여울 나루의 장", r2, band_d, p2, Some(bc(400)), Some(bc(400)), 2, 0, 0, "기원전 400년");
        add("ev-11", "때를 모르는 일", r0, 0, p1, None, None, 1, 0, 0, "");
        // 같은 해 보기의 '트랙마다 12개까지'를 보려고 한 해에 열넷을 몰아 둔다(다른 트랙 · 다른 자료집).
        for n in 0..14i64 {
            add(&format!("ev-many-{n}"), &format!("겹친 해의 일 {}", n + 1), r3, 0, p2, Some(ad(300)), Some(ad(300)), 1 + n % 3, 0, 0, "300년");
        }
    }
    b.finalize(&[("seed", "조회 검사".to_owned())]).unwrap();
    Fixture { band_a, band_b, band_c, band_d, event_1 }
}

/// 검사마다 저장소를 새로 짓고, 끝나면 지운다.
fn with_store(name: &str, body: impl FnOnce(&Store, &Fixture)) {
    let path = scratch(name);
    let fixture = build(&path);
    let store = Store::open(&path).unwrap();
    body(&store, &fixture);
    drop(store);
    let _ = std::fs::remove_file(&path);
}

fn call(store: &Store, q: Value) -> Value {
    store.call(&q).unwrap()
}

fn fails(store: &Store, q: Value) -> String {
    store.call(&q).map(|v| v.to_string()).unwrap_err().to_string()
}

fn names(items: &Value) -> Vec<String> {
    items.as_array().unwrap().iter().map(|v| v["name"].as_str().unwrap_or_default().to_owned()).collect()
}

#[test]
fn 번호와_이름을_서로_바꾼다() {
    with_store("uid", |s, f| {
        assert_eq!(call(s, json!({"op":"uid_of","kind":"band","id":f.band_a})), json!({"uid":"b-hankinara","kind":"period"}));
        // 항목 기록에 적힌 종류가 있으면 그것을 준다(조약 사건은 event가 아니라 treaty다).
        assert_eq!(call(s, json!({"op":"uid_of","kind":"event","id":f.event_1})), json!({"uid":"ev-1","kind":"treaty"}));
        assert!(fails(s, json!({"op":"uid_of","kind":"band","id":9999})).contains("띠가 없습니다"));
        assert!(fails(s, json!({"op":"uid_of","kind":"무엇","id":1})).contains("band 또는 event"));
        assert!(fails(s, json!({"op":"uid_of","kind":"band"})).contains("정수 입력 누락"));

        let back = call(s, json!({"op":"id_of","uid":"b-haesol"}));
        assert_eq!(back["band"], json!(f.band_c));
        assert_eq!(back["event"], Value::Null);
        assert_eq!(back["row"], json!(1));
        assert_eq!(back["start"].as_i64().unwrap(), ad(1));
        let event = call(s, json!({"op":"id_of","uid":"ev-1"}));
        assert_eq!(event["event"], json!(f.event_1));
        assert_eq!(event["row"], json!(1));
        // 빈 결과: 없는 이름은 모두 null이다.
        assert_eq!(call(s, json!({"op":"id_of","uid":"없는 이름"})), json!({"band":null,"event":null,"row":null,"start":null,"end":null}));
        assert!(fails(s, json!({"op":"id_of"})).contains("항목 이름 누락"));
    });
}

#[test]
fn 이름_묶음을_번호로_한_번에_바꾼다() {
    with_store("ids", |s, f| {
        let got = call(s, json!({"op":"ids_of","uids":["b-haesol","ev-1","없는 이름","b-hankinara"]}));
        assert_eq!(got["bands"].as_array().unwrap().len(), 2);
        // 입력 순서 그대로 · 없는 것은 뺀다.
        assert_eq!(got["bands"][0]["uid"], "b-haesol");
        assert_eq!(got["bands"][0]["id"], json!(f.band_c));
        assert_eq!(got["bands"][1]["uid"], "b-hankinara");
        assert_eq!(got["bands"][1]["row"], json!(0));
        assert_eq!(got["events"].as_array().unwrap().len(), 1);
        assert_eq!(got["events"][0]["id"], json!(f.event_1));
        // 빈 결과.
        assert_eq!(call(s, json!({"op":"ids_of","uids":[]})), json!({"bands":[],"events":[]}));
        let many: Vec<String> = (0..2001).map(|n| format!("u{n}")).collect();
        assert!(fails(s, json!({"op":"ids_of","uids":many})).contains("2000개까지"));
        assert!(fails(s, json!({"op":"ids_of"})).contains("목록(uids) 누락"));
        assert!(fails(s, json!({"op":"ids_of","uids":[7]})).contains("글자가 아닙니다"));
    });
}

#[test]
fn 항목_기록은_있는_것만_입력_순서로_준다() {
    with_store("entities", |s, _| {
        let got = call(s, json!({"op":"entities","uids":["f-aran","없는 이름","b-hankinara"]}));
        let list = got.as_array().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0]["uid"], "f-aran");
        assert_eq!(list[0]["kind"], "figure");
        assert!(list[0]["json"].as_str().unwrap().contains("아란 벼리"));
        assert_eq!(list[1]["uid"], "b-hankinara");
        assert_eq!(call(s, json!({"op":"entities","uids":["없음"]})), json!([]));
        let many: Vec<String> = (0..101).map(|n| format!("u{n}")).collect();
        assert!(fails(s, json!({"op":"entities","uids":many})).contains("100개까지"));
        assert!(fails(s, json!({"op":"entities"})).contains("목록(uids) 누락"));
    });
}

#[test]
fn 옛_검색은_그대로고_kinds를_주면_이름까지_찾는다() {
    with_store("search", |s, _| {
        // 옛 모양: 사건의 items(제목 · 줄 · 중요도 …)에 kind 열쇠가 없다.
        let old = call(s, json!({"op":"search","text":"해솔"}));
        assert!(old["items"].as_array().unwrap().len() >= 6);
        assert!(old["items"][0].get("title").is_some());
        assert!(old["items"][0].get("kind").is_none());
        // 새 모양: 갈래 · 이름 · 때 글을 함께 준다.
        let wide = call(s, json!({"op":"search","text":"해솔","kinds":["event"]}));
        assert!(wide["items"].as_array().unwrap().iter().all(|v| v["kind"] == "event"));
        assert!(wide["items"][0]["when"].as_str().unwrap().ends_with('년'));
        // 이름 표: 띠 · 칸 · 항목 기록.
        let band = call(s, json!({"op":"search","text":"해솔","kinds":["period"]}));
        assert_eq!(names(&band["items"]), vec!["해솔 연맹"]);
        assert_eq!(band["items"][0]["uid"], "b-haesol");
        assert_eq!(band["items"][0]["row"], json!(1));
        assert_eq!(band["items"][0]["track"], "첫 트랙");
        // 아직 자료가 없는 갈래(하위 문서)는 거절하지 않고 빈 결과를 준다.
        assert_eq!(call(s, json!({"op":"search","text":"해솔","kinds":["doc"]}))["items"], json!([]));
        let cells = call(s, json!({"op":"search","text":"가람","kinds":["cell"]}));
        let found = names(&cells["items"]);
        assert!(found.contains(&"첫 가람왕".to_owned()) && found.contains(&"가람 내각".to_owned()) && found.contains(&"가람 도읍".to_owned()), "{found:?}");
        let leader = cells["items"].as_array().unwrap().iter().find(|v| v["name"] == "첫 가람왕").unwrap();
        assert_eq!(leader["sub"], "한기 나라 지도자");
        assert_eq!(leader["cell_kind"], json!(1), "옛 정수 종류는 cell_kind로 간다");
        assert_eq!(leader["uid"], "b-hankinara");
        let capital = cells["items"].as_array().unwrap().iter().find(|v| v["name"] == "가람 도읍").unwrap();
        assert_eq!(capital["cell_kind"], json!(103), "날짜 칸의 번호는 100 + 종류");
        assert_eq!(capital["cell"], "capital:0", "상세 창이 여는 칸은 글자 참조다");
        assert_eq!(capital["row"], Value::Null, "날짜 칸은 제 줄이 없다");
        // 제 줄이 없는 항목 기록은 같은 이름의 칸 · 막대에서 자리를 빌린다.
        let figure = call(s, json!({"op":"search","text":"아란","kinds":["figure"]}));
        assert_eq!(names(&figure["items"]), vec!["아란 벼리"]);
        assert_eq!(figure["items"][0]["row"], json!(0));
        assert_eq!(figure["items"][0]["start"].as_i64().unwrap(), bc(480));
        let dynasty = call(s, json!({"op":"search","text":"가람 왕조","kinds":["dynasty"]}));
        assert_eq!(dynasty["items"][0]["uid"], "dyn-garam");
        assert_eq!(dynasty["items"][0]["start"].as_i64().unwrap(), bc(500));
        let house = call(s, json!({"op":"search","text":"나무","kinds":["house"]}));
        assert_eq!(house["items"][0]["when"], "미정");
        assert_eq!(house["items"][0]["row"], Value::Null);
        // 사건의 이름은 본문 색인이 맡으므로 이름 표에 겹쳐 들지 않는다.
        assert_eq!(call(s, json!({"op":"search","text":"맹세","kinds":["period","cell","figure"]}))["items"], json!([]));
        // 빈 결과 · 잘못된 입력.
        assert_eq!(call(s, json!({"op":"search","text":"없는말","kinds":["event","period"]}))["items"], json!([]));
        assert_eq!(call(s, json!({"op":"search","text":"  ","kinds":["event"]}))["items"], json!([]));
        assert!(fails(s, json!({"op":"search","text":"해솔","kinds":["없는갈래"]})).contains("모르는 갈래"));
        assert!(fails(s, json!({"op":"search","text":"해솔","kinds":"event"})).contains("kinds) 누락"));
        assert!(fails(s, json!({"op":"search","text":"해".repeat(65),"kinds":["event"]})).contains("64자까지"));
        assert!(fails(s, json!({"op":"search","text":"해솔","kinds":["event"],"after":-1})).contains("0 이상"));
        // 기원전 범위의 때 글.
        let old_band = call(s, json!({"op":"search","text":"한기","kinds":["period"]}));
        assert_eq!(old_band["items"][0]["when"], "기원전 500년–기원전 401년");
    });
}

#[test]
fn 검색은_나눠_받아도_빠짐없이_이어진다() {
    with_store("search-page", |s, _| {
        let whole = call(s, json!({"op":"search","text":"해솔","kinds":["event","period","cell"],"limit":200}));
        let all = names(&whole["items"]);
        assert!(all.len() > 4, "{all:?}");
        assert_eq!(whole["has_more"], json!(false));
        let mut joined: Vec<String> = Vec::new();
        let mut after = 0i64;
        loop {
            let page = call(s, json!({"op":"search","text":"해솔","kinds":["event","period","cell"],"limit":2,"after":after}));
            joined.extend(names(&page["items"]));
            if page["has_more"] != json!(true) {
                break;
            }
            after = page["next"].as_i64().unwrap();
        }
        assert_eq!(joined, all, "나눠 받은 것을 이으면 한 번에 받은 것과 같다");
        // 켠 자료집만 본다.
        assert_eq!(call(s, json!({"op":"search","text":"별여울","kinds":["period"],"packs":[1]}))["items"], json!([]));
        assert_eq!(names(&call(s, json!({"op":"search","text":"별여울","kinds":["period"],"packs":[2]}))["items"]), vec!["별여울 나라"]);
    });
}

#[test]
fn 그때에_걸친_것은_정권_먼저_칸_다음_가까운_사건이다() {
    with_store("search-year", |s, _| {
        let got = call(s, json!({"op":"search_year","at":bc(480),"limit":50}));
        let items = got["items"].as_array().unwrap();
        assert_eq!(items[0]["kind"], "period");
        assert_eq!(items[0]["name"], "한기 나라");
        assert_eq!(items[0]["when"], "기원전 500년–기원전 401년");
        let kinds: Vec<&str> = items.iter().map(|v| v["kind"].as_str().unwrap()).collect();
        let first_cell = kinds.iter().position(|k| *k == "cell").unwrap();
        let first_event = kinds.iter().position(|k| *k == "event").unwrap();
        assert!(first_cell < first_event, "칸이 사건보다 앞이다: {kinds:?}");
        assert!(kinds[..first_cell].iter().all(|k| *k != "event"));
        // 가장 가까운 사건이 먼저다(그해에 있는 ev-4).
        assert_eq!(items[first_event]["name"], "한기 들의 첫 씨앗");
        assert_eq!(items[0]["track"], "첫 트랙");
        // 찾는 쪽이 보는 때를 t로 불러도 같은 답이다(명세 06의 9절 ㈎와 같은 이름).
        assert_eq!(call(s, json!({"op":"search_year","t":bc(480),"limit":50}))["items"], got["items"]);
        // 갈래를 고르면 그것만 모은다.
        let only_events = call(s, json!({"op":"search_year","at":bc(480),"kinds":["event"],"limit":50}));
        assert!(only_events["items"].as_array().unwrap().iter().all(|v| v["kind"] == "event" || v["kind"] == "treaty"), "조약은 사건에서 갈라 적는다");
        let only_cells = call(s, json!({"op":"search_year","at":bc(480),"kinds":["cell"],"limit":50}));
        assert!(only_cells["items"].as_array().unwrap().iter().all(|v| v["kind"] == "cell"));
        // 고른 갈래가 앞쪽 띠에 하나도 없어도(문화만 걸리는 때처럼) 뒤의 것이 밀려나지 않는다 — 거르기는 SQL에서 한다.
        let narrow = call(s, json!({"op":"search_year","at":bc(480),"kinds":["figure","event"],"limit":2}));
        assert!(!narrow["items"].as_array().unwrap().is_empty(), "{:?}", narrow);
        assert_eq!(narrow["items"][0]["kind"], "event");
        assert_eq!(call(s, json!({"op":"search_year","at":bc(480),"kinds":["doc"]}))["items"], json!([]));
        assert!(fails(s, json!({"op":"search_year","at":bc(480),"kinds":["없는갈래"]})).contains("모르는 갈래"));
        // 빈 결과 · 잘못된 입력.
        assert_eq!(call(s, json!({"op":"search_year","at":ad(5000)}))["items"], json!([]));
        assert!(fails(s, json!({"op":"search_year","at":ad(10),"end":ad(1)})).contains("뒤집혔습니다"));
        assert!(fails(s, json!({"op":"search_year"})).contains("정수 입력 누락"));
        // 켠 자료집만.
        let mine = call(s, json!({"op":"search_year","at":bc(400),"packs":[2]}));
        assert!(names(&mine["items"]).iter().all(|n| n.contains("별여울") || n.contains("둘째")), "{:?}", names(&mine["items"]));
    });
}

#[test]
fn 이_시기의_사건은_중요도_큰_순이고_나눠_받을_수_있다() {
    with_store("events-in", |s, f| {
        let got = call(s, json!({"op":"events_in","band":f.band_c,"lo":ad(1),"hi":ad_end(100),"limit":50}));
        let items = got["items"].as_array().unwrap();
        assert_eq!(items.len(), 6);
        let importance: Vec<i64> = items.iter().map(|v| v["importance"].as_i64().unwrap()).collect();
        assert_eq!(importance, vec![3, 2, 1, 1, 1, 1]);
        assert_eq!(items[0]["uid"], "ev-1");
        assert_eq!(items[0]["label"], "1년");
        // 줄로 물어도 같은 답이다(그 줄의 사건이 모두 그 띠에 들어 있다).
        let by_row = call(s, json!({"op":"events_in","row":1,"lo":ad(1),"hi":ad_end(100),"limit":50}));
        assert_eq!(by_row["items"], got["items"]);
        // 나눠 받기.
        let first = call(s, json!({"op":"events_in","band":f.band_c,"lo":ad(1),"hi":ad_end(100),"limit":4}));
        assert_eq!(first["has_more"], json!(true));
        let next = call(s, json!({"op":"events_in","band":f.band_c,"lo":ad(1),"hi":ad_end(100),"limit":4,"after":first["next"].clone()}));
        assert_eq!(next["has_more"], json!(false));
        assert_eq!(first["items"].as_array().unwrap().len() + next["items"].as_array().unwrap().len(), 6);
        // 빈 결과 · 잘못된 입력 · 켠 자료집.
        assert_eq!(call(s, json!({"op":"events_in","band":f.band_c,"lo":ad(500),"hi":ad(600)}))["items"], json!([]));
        assert_eq!(call(s, json!({"op":"events_in","band":f.band_d,"lo":bc(450),"hi":bc_end(351),"packs":[1]}))["items"], json!([]));
        assert!(fails(s, json!({"op":"events_in","lo":0,"hi":1})).contains("하나는 주어야"));
        assert!(fails(s, json!({"op":"events_in","band":f.band_a,"lo":10,"hi":0})).contains("조회 범위 오류"));
        // 기원전 범위.
        let bc_side = call(s, json!({"op":"events_in","band":f.band_a,"lo":bc(500),"hi":bc_end(401)}));
        assert_eq!(bc_side["items"].as_array().unwrap().len(), 2);
        assert_eq!(bc_side["items"][0]["title"], "한기 들의 첫 씨앗");
        assert_eq!(bc_side["items"][0]["start"].as_i64().unwrap(), bc(480));
    });
}

#[test]
fn 같은_해_보기는_트랙마다_띠와_칸과_사건을_묶는다() {
    with_store("same-year", |s, _| {
        let got = call(s, json!({"op":"same_year","at":bc(450),"end":bc_end(450)}));
        let tracks = got["tracks"].as_array().unwrap();
        assert_eq!(tracks.len(), 2);
        assert_eq!(tracks[0]["name"], "첫 트랙");
        assert_eq!(tracks[0]["bands"][0]["uid"], "b-hankinara");
        let cells = tracks[0]["cells"].as_array().unwrap();
        assert!(cells.iter().any(|c| c["name"] == "둘째 나래왕" && c["kind"] == json!(1)), "{cells:?}");
        assert_eq!(tracks[1]["bands"][0]["uid"], "b-byeol");
        // 띠의 형식 4 뜻 form(스키마 4) — 지은 값 그대로 · 적지 않은 띠는 0.
        assert_eq!((tracks[0]["bands"][0]["form"].as_i64(), tracks[1]["bands"][0]["form"].as_i64()), (Some(HANKI_FORM), Some(0)));
        // 트랙마다 12개까지.
        let crowded = call(s, json!({"op":"same_year","at":ad(300),"end":ad_end(300)}));
        assert_eq!(crowded["tracks"].as_array().unwrap().len(), 1);
        assert_eq!(crowded["tracks"][0]["events"].as_array().unwrap().len(), 12);
        assert_eq!(crowded["tracks"][0]["events"][0]["importance"], json!(3));
        // 빈 결과 · 잘못된 입력 · 켠 자료집.
        assert_eq!(call(s, json!({"op":"same_year","at":ad(5000)}))["tracks"], json!([]));
        assert!(fails(s, json!({"op":"same_year","at":10,"end":0})).contains("뒤집혔습니다"));
        let only_first = call(s, json!({"op":"same_year","at":bc(450),"end":bc_end(450),"packs":[1]}));
        assert_eq!(only_first["tracks"].as_array().unwrap().len(), 1);
    });
}

/// 스키마 4 전의 옛 저장소(판 '3' — `periods.form` 열이 없음)도 같은 해 보기의 띠에 form을 싣되 0(모름)이다(계약 1-1 — 옛 저장소는 빈 값).
#[test]
fn 같은_해_보기의_form은_열이_없는_옛_저장소에서_0이다() {
    let path = scratch("same-year-old");
    build(&path);
    {
        let db = rusqlite::Connection::open(&path).unwrap();
        db.execute_batch("ALTER TABLE periods DROP COLUMN form; DROP TABLE sphere_lines; UPDATE meta SET value='3' WHERE key='schema';").unwrap();
    }
    let s = Store::open(&path).unwrap();
    assert!(!s.period_form);
    let got = call(&s, json!({"op":"same_year","at":bc(450),"end":bc_end(450)}));
    let bands: Vec<&Value> = got["tracks"].as_array().unwrap().iter().flat_map(|t| t["bands"].as_array().unwrap()).collect();
    assert!(!bands.is_empty() && bands.iter().all(|b| b["form"] == json!(0)), "{bands:?}");
    assert_eq!(bands[0]["uid"], "b-hankinara");
    drop(s);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn 표는_시작_순_트랙_순이고_정권을_함께_담을_수_있다() {
    with_store("table", |s, _| {
        let only_events = call(s, json!({"op":"table","limit":500}));
        assert!(only_events["items"].as_array().unwrap().iter().all(|v| v["kind"] == "event" || v["kind"] == "treaty"), "조약은 사건에서 갈라 적는다");
        let both = call(s, json!({"op":"table","with_periods":true,"limit":500}));
        let items = both["items"].as_array().unwrap();
        assert_eq!(items[0]["kind"], "period");
        assert_eq!(items[0]["name"], "한기 나라");
        assert_eq!(items[0]["track_name"], "첫 트랙");
        let starts: Vec<i64> = items.iter().filter_map(|v| v["start"].as_i64()).collect();
        assert!(starts.windows(2).all(|w| w[0] <= w[1]), "시작 순이다");
        // 날짜를 모르는 사건은 맨 뒤에 '미정'으로 선다.
        assert_eq!(items.last().unwrap()["name"], "때를 모르는 일");
        assert_eq!(items.last().unwrap()["when"], "미정");
        // 범위 · 나눠 받기 · 빈 결과 · 잘못된 입력.
        let ranged = call(s, json!({"op":"table","with_periods":true,"lo":ad(1),"hi":ad_end(100),"limit":500}));
        assert!(names(&ranged["items"]).contains(&"해솔 연맹".to_owned()));
        assert!(!names(&ranged["items"]).contains(&"한기 나라".to_owned()));
        let page = call(s, json!({"op":"table","with_periods":true,"limit":3}));
        assert_eq!(page["has_more"], json!(true));
        let next = call(s, json!({"op":"table","with_periods":true,"limit":3,"after":page["next"].clone()}));
        assert_eq!(next["items"][0], items[3]);
        assert_eq!(call(s, json!({"op":"table","lo":ad(3000),"hi":ad(3100)}))["items"], json!([]));
        assert!(fails(s, json!({"op":"table","lo":10,"hi":0})).contains("뒤집혔습니다"));
        assert!(fails(s, json!({"op":"table","limit":"많이"})).contains("정수가 아닙니다"));
    });
}

#[test]
fn 표를_내보낸_파일은_bom과_crlf로_쓰고_이미_있는_파일은_덮어쓰지_않는다() {
    with_store("csv", |s, _| {
        let path = std::env::temp_dir().join(format!("archive-query-{}-표.csv", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let text = path.to_string_lossy().to_string();
        let got = call(s, json!({"op":"table_csv","with_periods":true,"path":text}));
        assert!(got["rows"].as_i64().unwrap() > 20);
        let raw = std::fs::read(&path).unwrap();
        assert_eq!(&raw[..3], &[0xEF, 0xBB, 0xBF], "BOM으로 시작한다");
        let body = String::from_utf8(raw[3..].to_vec()).unwrap();
        let head = body.lines().next().unwrap();
        assert!(body.contains("\r\n"), "줄 끝은 CRLF다");
        assert_eq!(head.matches("\",\"").count(), 14, "열 열다섯: {head}");
        assert!(head.starts_with("\"시작\",\"끝\",\"구분\",\"트랙\",\"제목\""));
        // 날짜 글 그대로 · 정권의 종류와 확실성 · 실재성.
        assert!(body.contains("\"기원전 480년\""), "사건은 실어 온 날짜 글을 쓴다");
        assert!(body.contains("\"미정\",\"기원전 401년\",\"국가\""), "시작 미정인 띠");
        assert!(body.contains("\"종속국\""));
        assert!(body.contains("\"전설\""));
        assert!(body.contains("\"조약\""));
        // 다시 쓰면 거절 · .csv가 아니면 거절.
        assert!(fails(s, json!({"op":"table_csv","path":text})).contains("덮어쓰지 않습니다"));
        assert!(fails(s, json!({"op":"table_csv","path":text.replace(".csv", ".txt")})).contains(".csv 파일에만"));
        assert!(fails(s, json!({"op":"table_csv"})).contains("경로(path) 누락"));
        let _ = std::fs::remove_file(&path);
    });
}

#[test]
fn 범례는_지금_자료에_쓰인_것만_알린다() {
    with_store("legend", |s, _| {
        let got = call(s, json!({"op":"legend_kinds"}));
        assert_eq!(got["band_kinds"], json!([0, 5, 12]));
        assert_eq!(got["band_kind_names"], json!(["국가", "종속국", "연맹"]));
        assert_eq!(got["certainty"], json!([0, 1, 2]));
        assert_eq!(got["historicity_ids"], json!([0, 2]));
        assert_eq!(got["historicity"], json!([{"id":0,"name":"실재"},{"id":2,"name":"전설"}]), "필터 시트는 이름까지 읽는다");
        assert_eq!(got["treaty"], json!(true));
        assert_eq!(got["variant"], json!(true));
        assert_eq!(got["vague_cell"], json!(true));
        assert_eq!(got["figure"], json!(true));
        assert_eq!(got["dep_label"], json!(true));
        assert_eq!(got["scope"], json!(true));
        // 켠 자료집만 본다 — 둘째 자료집에는 표현 값이 없다.
        let plain = call(s, json!({"op":"legend_kinds","packs":[2]}));
        assert_eq!(plain["band_kinds"], json!([0]));
        assert_eq!(plain["certainty"], json!([0]));
        assert_eq!(plain["treaty"], json!(false));
        assert_eq!(plain["figure"], json!(false));
        assert_eq!(plain["scope"], json!(false));
        // 빈 결과: 아무 자료집도 켜지 않으면 아무것도 쓰이지 않았다.
        let none = call(s, json!({"op":"legend_kinds","packs":[]}));
        assert_eq!(none["band_kinds"], json!([]));
        assert_eq!(none["variant"], json!(false));
        assert!(fails(s, json!({"op":"legend_kinds","packs":["하나"]})).contains("자료집 번호"));
    });
}

#[test]
fn 칸_목록은_시작_순이고_없는_띠는_까닭과_함께_거절한다() {
    with_store("cells-of", |s, f| {
        let leaders = call(s, json!({"op":"cells_of","band":f.band_a,"kind":1}));
        assert_eq!(names(&leaders), vec!["첫 가람왕", "둘째 나래왕"]);
        assert_eq!(leaders[0]["start"].as_i64().unwrap(), bc(500));
        assert_eq!(leaders[1]["style"], json!(4), "앞 칸과 같은 무리");
        // 단을 주지 않으면 모든 단을 시작 순으로.
        let every = call(s, json!({"op":"cells_of","band":f.band_a}));
        assert_eq!(every.as_array().unwrap().len(), 6);
        // 빈 결과 · 잘못된 입력.
        assert_eq!(call(s, json!({"op":"cells_of","band":f.band_b,"kind":99})), json!([]));
        assert!(fails(s, json!({"op":"cells_of","band":9999,"kind":1})).contains("띠가 없습니다"));
        assert!(fails(s, json!({"op":"cells_of"})).contains("정수 입력 누락"));
        assert!(fails(s, json!({"op":"cells_of","band":f.band_a,"kind":"지도자"})).contains("정수가 아닙니다"));
    });
}

#[test]
fn 이름_표는_사건을_빼고_넣을_때_펴_둔다() {
    with_store("names", |s, _| {
        let rows: i64 = s.db.query_row("SELECT count(*) FROM names", [], |r| r.get(0)).unwrap();
        assert_eq!(s.info().unwrap()["meta"]["names"], json!(rows.to_string()));
        let kinds: Vec<String> = s.db.prepare("SELECT DISTINCT kind FROM names ORDER BY kind").unwrap()
            .query_map([], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap();
        assert_eq!(kinds, vec!["cell", "dynasty", "epoch", "figure", "house", "period"]);
        // 시대 구분은 공통 줄이라 줄을 빌리지 않고 기간만 빌린다.
        let epoch: (i64, Option<i64>) = s.db.query_row("SELECT row,start FROM names WHERE uid='ep-first'", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
        assert_eq!(epoch.0, -1);
        assert_eq!(epoch.1, Some(bc(500)));
    });
}

/// 칸 종류 9(직위 줄 더 — 스키마 4 · 계약 1-1)는 3단계 동안 화면이 그리지 않는다(전체 제약 '앱 화면 1배 · 새 값은 실리기만'). 그래서 범례 · 필터 시트(`legend_kinds`)와
/// 연도 검색(`search_year`)에도 보이지 않아야 한다 — 형식 4 가상 팩 `f4-office3`(셋째 직위 줄을 덧댄 것)로 지은 저장소의 답이, 종류 9 칸을 지운 같은 저장소의 답과 같다.
/// 4단계가 그 줄을 그릴 때 이 검사와 `query.rs`의 거르기를 함께 걷는다.
#[test]
fn 직위_줄_더_칸은_범례와_연도_검색에_보이지_않는다() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let (path, stripped) = (scratch("office3"), scratch("office3-stripped"));
    archive_engine::legacy::build_files_with(&path, &[root.join("../fixtures/oracle/f4-office3.json")], Some("2026-10-15T12:00:00+09:00"),
        Some(&root.join("tests/fixtures/lay/calendar-slice.json")), true).unwrap();
    std::fs::copy(&path, &stripped).unwrap();
    // 종류 9 칸의 때(시작 · 가운데 · 끝)에서 묻는다 — 지운 저장소에서도 같은 물음.
    let mut times: Vec<i64> = Vec::new();
    {
        let db = rusqlite::Connection::open(&stripped).unwrap();
        let mut stmt = db.prepare("SELECT start,end FROM cells WHERE kind=9 ORDER BY id").unwrap();
        let spans: Vec<(i64, i64)> = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
        assert!(!spans.is_empty(), "f4-office3에 칸 종류 9가 있어야 견줄 수 있다");
        for (start, end) in spans {
            times.extend([start, start + (end - start) / 2, end]);
        }
        drop(stmt);
        assert!(db.execute("DELETE FROM cells WHERE kind=9", []).unwrap() > 0);
    }
    {
        // 범례의 조건부 줄은 칸의 style 비트(이설 128 · 범위 64 · 모호 8 · 16 · 미정 1 · 2)로도 켜진다 — 종류 9 칸에 그 비트를 모두 달아도 줄이 서지 않아야 한다.
        let db = rusqlite::Connection::open(&path).unwrap();
        assert!(db.execute("UPDATE cells SET style=style|219 WHERE kind=9", []).unwrap() > 0);
    }
    let (s, t) = (Store::open(&path).unwrap(), Store::open(&stripped).unwrap());
    assert_eq!(call(&s, json!({"op":"legend_kinds"})), call(&t, json!({"op":"legend_kinds"})), "범례 · 필터 시트의 조건부 줄");
    for at in times {
        for q in [json!({"op":"search_year","at":at,"limit":200}), json!({"op":"search_year","at":at,"kinds":["cell"],"limit":200})] {
            let got = call(&s, q.clone());
            assert!(!got["items"].as_array().unwrap().is_empty(), "{q}: 그때에 걸친 것이 있어야 견줄 수 있다");
            assert_eq!(got, call(&t, q.clone()), "{q}");
        }
    }
    drop((s, t));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(&stripped);
}

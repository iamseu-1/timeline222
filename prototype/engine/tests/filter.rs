//! 거르개(트랙 · 분류 · 종류 · 실재성 · 중요도 문턱) 검사 — 계약 2절의 '거르개' 소절.
//! 거른 것이 **타일에서 빠지는지**(묶음 알약의 수 · 일반 항목 · 줄 접기까지)와,
//! 거르개가 없을 때의 답이 **바이트 단위로 그대로인지**를 본다.
use archive_engine::builder::{AxisCellIn, Builder, CellIn, EventIn, GroupIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::levels::{tile_of, PRE_MIN};
use archive_engine::tile::{build_tile, decode, Decoded, TileRequest};
use archive_engine::{Store, DAY};
use serde_json::{json, Value};
use std::path::PathBuf;

const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: -1, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-filter-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    path
}

/// 띠의 `look` 만들기 — 아래 5비트가 종류, 8~10비트가 실재성이다(계약 6-1).
fn look(kind: i64, historicity: i64) -> i64 {
    kind | (historicity << 8)
}

/// 검사용 저장소. 트랙 둘 · 줄 셋 · 띠 넷 · 칸 넷 · 사건 스물넷 · 일반 항목 넷.
///
/// | 줄 | 트랙 | 띠 | 종류 · 실재성 |
/// | --- | --- | --- | --- |
/// | 0 | 1 | 한기 나라(1) · 별여울 속국(2) | 0 국가 · 실재 / 5 종속국 · 실재 |
/// | 1 | 1 | 두 달의 궁정(3) | 0 국가 · 2 전설 |
/// | 2 | 2 | 해솔 나라(4) | 0 국가 · 실재 |
struct Fixture {
    band_state: i64,
    band_vassal: i64,
    band_legend: i64,
    band_other: i64,
}

fn build(path: &PathBuf) -> Fixture {
    let mut b = Builder::create(path).unwrap();
    let pack = b.pack("거르개 검사", None).unwrap();
    for (ord, (key, name)) in [("govern", "다스림"), ("build", "지음"), ("lore", "이야기")].iter().enumerate() {
        b.category(pack, ord as i64, key, name, 0x8f_7fb0).unwrap();
    }
    let t1 = b.track_full(&TrackIn { pack, name: "첫 트랙", color: 0xc8_b193, dynasty: 0, leader: 1, cabinet: 1, organ: 0, rail_levels: 2, key: "mw-first" }).unwrap();
    let t2 = b.track_full(&TrackIn { pack, name: "둘째 트랙", color: 0x9d_bea8, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "mw-second" }).unwrap();
    let r0 = b.row_full(t1, &GEO, &RowExtra { fig: 1, ..Default::default() }).unwrap();
    let r1 = b.row_full(t1, &GEO, &RowExtra { fig: 1, ..Default::default() }).unwrap();
    let r2 = b.row_full(t2, &GEO, &Default::default()).unwrap();
    b.group(&GroupIn { track: t1, depth: 0, first_row: r0, row_count: 2, name: "윗물 겨레", color: 0xbc_d8c1, kind: 0 }).unwrap();
    let (start, end) = (-400 * DAY, 400 * DAY);
    let band = |b: &mut Builder, row: i64, name: &str, uid: &str, kind: i64, historicity: i64| {
        b.period_full(&PeriodIn { pack, row, start, end, fuzzy: 0, color: 0xa0_bcc5, name, look: look(kind, historicity), tag: "", sub: 0, uid, variant: 0, form: 0 }).unwrap()
    };
    let band_state = band(&mut b, r0, "한기 나라", "b-state", 0, 0);
    let band_vassal = band(&mut b, r0, "별여울 속국", "b-vassal", 5, 0);
    let band_legend = band(&mut b, r1, "두 달의 궁정", "b-legend", 0, 2);
    let band_other = band(&mut b, r2, "해솔 나라", "b-other", 0, 0);
    for (id, name) in [(band_state, "첫 가람왕"), (band_vassal, "속국 지도자"), (band_legend, "전설의 왕"), (band_other, "해솔 지도자")] {
        // 칸 참조의 번호는 lane의 19비트 위에 실린다(계약 6-2) — 첫 칸이라 1(= 순번 0 + 1)이다.
        b.cell_full(&CellIn { period: id, kind: 1, start, end, name, lane: 1 << 19, style: 0, color: 0, variant: 0 }).unwrap();
    }
    b.axis_cell(&AxisCellIn { pack, kind: 2, track: Some(t1), lane: 0, start, end, name: "첫길 연호", color: 0xc8_b193, style: 0, strip: 1, seq: 0 }).unwrap();
    // 사건: 줄마다 여덟 개를 한 통 안에 몰아 둔다(알약이 서게). 분류와 중요도는 돌아가며 준다.
    // `rail`의 날짜 정밀도는 **날**(2 << 8)로 둔다 — 걸침을 달력 단위로 재므로(계약 2-1절), 연도만 적었다고 하면
    // 0~420분의 사건이 모두 '그해 한가운데'로 밀려 하루 폭으로 묻는 `events_in` 검사가 헛돈다.
    const DAY_PREC: i64 = 2 << 8;
    for (row, band) in [(r0, band_state), (r1, band_legend), (r2, band_other)] {
        for i in 0..8i64 {
            let at = i * 60;
            b.event(&EventIn {
                pack, lane: row, start: Some(at), end: Some(at), importance: 1 + i % 3, title: &format!("{row}줄 {i}번 사건"), body: "별여울 기록",
                look: i % 3, label: "", rail: DAY_PREC, uid: &format!("e-{row}-{i}"), band, ..Default::default()
            }).unwrap();
        }
    }
    // 속국 띠에 딸린 사건 하나 — 종류를 끄면 이 사건도 함께 빠진다(명세 6-3).
    b.event(&EventIn { pack, lane: r0, start: Some(500), end: Some(500), importance: 3, title: "속국의 일", body: "", look: 0, label: "", rail: DAY_PREC, uid: "e-vassal", band: band_vassal, ..Default::default() }).unwrap();
    // 일반 항목: 16 속국 이름표(속국 띠를 가리킴) · 33 기간 막대(사건을 가리킴) · 37 인물 막대(중요도 1과 3) · 17 구역 탭(둘째 트랙).
    b.item(&ItemIn { pack, section: 16, row: r0, row2: r0, start, end, lod: None, ref_id: band_vassal, ref_kind: 1, name: "별여울 속국", color: 0xa0_bcc5, a: 0, b: 1, c: 0, d: 0, text2: "b-vassal", variant: 0 }).unwrap();
    b.item(&ItemIn { pack, section: 33, row: r0, row2: r0, start: 0, end: 60, lod: Some(0), ref_id: 1, ref_kind: 2, name: "0줄 0번 사건", color: 0xa0_bcc5, a: 0, b: 0, c: 0, d: 0, text2: "", variant: 0 }).unwrap();
    b.item(&ItemIn { pack, section: 37, row: r0, row2: r0, start, end, lod: None, ref_id: band_state, ref_kind: 1, name: "아란 벼리", color: 0xa0_bcc5, a: 0, b: 1, c: 0, d: 0, text2: "f-1|-100|100", variant: 0 }).unwrap();
    b.item(&ItemIn { pack, section: 37, row: r0, row2: r0, start, end, lod: None, ref_id: band_state, ref_kind: 1, name: "해솔 벼리", color: 0xa0_bcc5, a: 1, b: 3, c: 0, d: 0, text2: "f-2|-100|100", variant: 0 }).unwrap();
    b.item(&ItemIn { pack, section: 17, row: r2, row2: r2, start, end, lod: None, ref_id: band_other, ref_kind: 1, name: "해솔 조계지", color: 0x9d_bea8, a: 0, b: 0, c: 0, d: 0, text2: "", variant: 0 }).unwrap();
    b.entity("b-state", pack, "period", r#"{"uid":"b-state","name":"한기 나라"}"#).unwrap();
    b.entity("b-vassal", pack, "period", r#"{"uid":"b-vassal","name":"별여울 속국"}"#).unwrap();
    b.finalize(&[]).unwrap();
    Fixture { band_state, band_vassal, band_legend, band_other }
}

fn with_store(name: &str, body: impl Fn(&Store, &Fixture)) {
    let path = scratch(name);
    let fixture = build(&path);
    let store = Store::open(&path).unwrap();
    body(&store, &fixture);
    drop(store);
    let _ = std::fs::remove_file(&path);
}

/// 그 단계 · 그 줄 묶음의 타일을 거르개와 함께 만든다.
fn tile_bytes(store: &Store, level: usize, chunk: i64, filter: Value) -> Vec<u8> {
    let req = TileRequest {
        level,
        x: tile_of(0, level),
        chunk,
        packs: vec![1],
        filter: store.filter_of(&filter).unwrap(),
        variants: None,
    };
    build_tile(store, &req).unwrap()
}

fn tile(store: &Store, level: usize, chunk: i64, filter: Value) -> Decoded {
    decode(&tile_bytes(store, level, chunk, filter)).unwrap()
}

/// 타일에 실린 띠의 이름들.
fn band_names(t: &Decoded) -> Vec<String> {
    t.bands.iter().map(|b| t.strings.get(b.name as usize).cloned().unwrap_or_default()).collect()
}

/// 타일에 실린 사건 대표 + 알약을 더한 수(그 줄 묶음의 '거른 뒤 사건 수').
fn counted(t: &Decoded) -> i64 {
    t.events.iter().filter(|e| e.bits & archive_engine::tile::COUNTED != 0).count() as i64 + t.pills.iter().map(|p| p.count as i64).sum::<i64>()
}

#[test]
fn 거르개가_없거나_비면_답은_바이트까지_그대로다() {
    with_store("plain", |s, _| {
        for level in [0usize, 4, PRE_MIN, 10] {
            let plain = build_tile(s, &TileRequest::plain(level, tile_of(0, level), 0, vec![1])).unwrap();
            assert_eq!(tile_bytes(s, level, 0, json!({})), plain, "단계 {level}: 거르개가 없는 요청");
            assert_eq!(tile_bytes(s, level, 0, json!({"filter":{}})), plain, "단계 {level}: 빈 거르개");
            assert_eq!(
                tile_bytes(s, level, 0, json!({"filter":{"tracks_off":[],"cats_off":[],"kinds_off":[],"hist_off":[],"min_importance":1}})),
                plain,
                "단계 {level}: 아무것도 끄지 않은 거르개"
            );
        }
        // 조회 명령도 같다.
        let plain = s.call(&json!({"op":"rows_near","near":[-DAY,DAY],"far":[300*DAY,400*DAY],"packs":[1]})).unwrap();
        assert_eq!(s.call(&json!({"op":"rows_near","near":[-DAY,DAY],"far":[300*DAY,400*DAY],"packs":[1],"filter":{}})).unwrap(), plain);
    });
}

#[test]
fn 트랙을_끄면_그_트랙의_줄이_통째로_빠진다() {
    with_store("track", |s, f| {
        let off = json!({"filter":{"tracks_off":[2]}});
        // 둘째 트랙의 줄 2는 줄 묶음 0에 함께 있다.
        let t = tile(s, 0, 0, off.clone());
        assert_eq!(band_names(&t), vec!["한기 나라", "별여울 속국", "두 달의 궁정"], "해솔 나라는 빠진다");
        assert!(t.cells.iter().all(|c| c.row != 2), "꺼진 줄의 칸도 빠진다");
        assert!(t.events.iter().all(|e| e.row != 2), "꺼진 줄의 사건도 빠진다");
        assert!(t.pills.iter().all(|p| p.row != 2), "꺼진 줄의 알약도 빠진다");
        assert!(t.section(17).is_empty(), "꺼진 트랙의 구역 탭(일반 항목)도 빠진다");
        assert!(!t.bands.iter().any(|b| b.id as i64 == f.band_other), "꺼진 트랙의 띠는 없다");
        // 첫 트랙은 그대로다.
        assert_eq!(counted(&tile(s, PRE_MIN, 0, off.clone())), 17, "8 + 8 + 속국의 일 하나");
    });
}

#[test]
fn 분류를_끄면_그_분류의_사건만_빠지고_알약이_다시_센다() {
    with_store("category", |s, _| {
        let all = tile(s, PRE_MIN, 0, json!({}));
        assert_eq!(counted(&all), 25, "8 × 3 + 속국의 일 하나");
        assert!(!all.pills.is_empty(), "한 통에 몰린 사건이라 알약이 선다");
        // 분류 1을 끄면 줄마다 두 건씩(i % 3 == 1인 1 · 4 · 7… 가운데 여덟 중 둘)이 빠진다.
        let off = tile(s, PRE_MIN, 0, json!({"filter":{"cats_off":[1]}}));
        assert_eq!(counted(&off), 25 - 3 * 3, "줄마다 세 건씩 빠진다");
        assert!(counted(&off) < counted(&all));
        // 대표로 뽑힌 사건 가운데 꺼진 분류가 없다.
        assert!(off.events.iter().all(|e| (e.look & 0xFF) != 1));
        // 띠와 칸은 그대로다.
        assert_eq!(band_names(&off).len(), 4);
    });
}

#[test]
fn 종류를_끄면_그_띠와_딸린_사건이_함께_빠진다() {
    with_store("kind", |s, f| {
        let off = tile(s, PRE_MIN, 0, json!({"filter":{"kinds_off":[5]}}));
        assert_eq!(band_names(&off), vec!["한기 나라", "두 달의 궁정", "해솔 나라"], "종속국 띠가 빠진다");
        assert!(off.cells.iter().all(|c| c.id != 2), "그 띠의 칸도 함께");
        assert_eq!(counted(&off), 24, "그 띠에 딸린 사건 하나가 빠진다");
        assert!(off.section(16).is_empty(), "그 띠를 가리키는 속국 이름표(구역 16)도 빠진다");
        // 한 줄에 함께 있던 다른 띠는 남는다.
        assert!(off.bands.iter().any(|b| b.id as i64 == f.band_state));
        assert!(!off.bands.iter().any(|b| b.id as i64 == f.band_vassal));
    });
}

#[test]
fn 실재성을_끄면_그_띠가_빠진다() {
    with_store("historicity", |s, f| {
        let off = tile(s, PRE_MIN, 0, json!({"filter":{"hist_off":[2]}}));
        assert!(!off.bands.iter().any(|b| b.id as i64 == f.band_legend), "전설의 띠가 빠진다");
        assert_eq!(band_names(&off), vec!["한기 나라", "별여울 속국", "해솔 나라"]);
        assert_eq!(counted(&off), 17, "그 띠에 딸린 여덟 건이 함께 빠진다");
        // 실재(0)를 함께 끄면 남는 띠가 없다.
        let none = tile(s, PRE_MIN, 0, json!({"filter":{"hist_off":[0,2]}}));
        assert!(none.bands.is_empty() && none.events.is_empty() && none.pills.is_empty());
    });
}

#[test]
fn 중요도_문턱은_사건과_인물_막대에_함께_걸린다() {
    with_store("importance", |s, _| {
        let off = tile(s, PRE_MIN, 0, json!({"filter":{"min_importance":3}}));
        assert!(off.events.iter().all(|e| e.bits & 3 == 3), "중요도 3만 남는다");
        // 줄마다 여덟 가운데 중요도 3은 둘(i % 3 == 2) + 속국의 일 하나.
        assert_eq!(counted(&off), 2 * 3 + 1);
        let figures = off.section(37);
        assert_eq!(figures.len(), 1, "중요도 1인 인물 막대는 빠진다");
        assert_eq!(off.strings.get(figures[0].name as usize).map(String::as_str), Some("해솔 벼리"));
        // 보통 이상(2)이면 중요도 1만 빠진다 — 줄마다 여덟 가운데 다섯이 남는다.
        let mid = tile(s, PRE_MIN, 0, json!({"filter":{"min_importance":2}}));
        assert_eq!(counted(&mid), 5 * 3 + 1);
    });
}

#[test]
fn 빠진_사건의_기간_막대도_함께_빠진다() {
    with_store("rail", |s, _| {
        // 구역 33은 1번 사건(0줄 0번 · 분류 0 · 중요도 1)을 가리킨다.
        assert_eq!(tile(s, 0, 0, json!({})).section(33).len(), 1);
        assert!(tile(s, 0, 0, json!({"filter":{"cats_off":[0]}})).section(33).is_empty(), "가리키는 사건이 빠지면 막대도 빠진다");
        assert!(tile(s, 0, 0, json!({"filter":{"min_importance":2}})).section(33).is_empty());
        assert_eq!(tile(s, 0, 0, json!({"filter":{"cats_off":[1]}})).section(33).len(), 1, "다른 분류를 껐으면 그대로다");
    });
}

#[test]
fn 거른_뒤_빈_줄은_가까운_쪽에도_먼_쪽에도_없다() {
    with_store("rows_near", |s, _| {
        let near = json!([-DAY, DAY]);
        let far = json!([300 * DAY, 400 * DAY]);
        let ask = |filter: Value| -> Value {
            s.call(&json!({"op":"rows_near","near":near,"far":far,"packs":[1],"filter":filter})).unwrap()
        };
        assert_eq!(ask(json!({}))["near"], json!([0, 1, 2]));
        assert_eq!(ask(json!({}))["far"], json!([0, 1, 2]), "띠가 걸쳐 있어 먼 쪽에도 줄이 있다");
        let off = ask(json!({"tracks_off":[2]}));
        assert_eq!(off["near"], json!([0, 1]), "꺼진 트랙의 줄 2가 빠진다");
        assert_eq!(off["far"], json!([0, 1]), "먼 쪽에서도 빠진다");
        // 실재성을 끄면 줄 1의 띠가 사라지고, 사건도 함께 빠져 그 줄이 통째로 접힌다.
        let legend_off = ask(json!({"hist_off":[2]}));
        assert_eq!(legend_off["near"], json!([0, 2]));
        assert_eq!(legend_off["far"], json!([0, 2]));
    });
}

#[test]
fn 줄_이름_후보도_거른_뒤의_자료로_정해진다() {
    with_store("row_labels", |s, _| {
        // 이 검사 자료에는 줄 이름 후보를 넣지 않았으므로 빈 목록이지만, 꺼진 줄은 물어도 빈 목록이어야 한다.
        let off = s.call(&json!({"op":"row_labels","rows":[0,1,2],"at":0,"filter":{"tracks_off":[2]}})).unwrap();
        assert_eq!(off["labels"][2]["items"], json!([]));
    });
}

#[test]
fn 조회_명령도_같은_거르개를_받는다() {
    with_store("queries", |s, f| {
        let filter = json!({"cats_off":[1],"min_importance":2});
        let found = s.call(&json!({"op":"events_in","band":f.band_state,"lo":-DAY,"hi":DAY,"limit":50,"filter":filter})).unwrap();
        let kept = found["items"].as_array().unwrap();
        assert!(!kept.is_empty(), "거르개를 걸어도 남는 사건이 있어야 한다(빈 목록은 아무것도 재지 않는다)");
        assert!(kept.iter().all(|e| e["importance"].as_i64().unwrap() >= 2 && (e["look"].as_i64().unwrap() & 0xFF) != 1));
        // 검색 · 표 · 같은 해 보기 · 묶음 카드도 받는다.
        let search = s.call(&json!({"op":"search","text":"별여울","kinds":["event"],"filter":{"min_importance":3}})).unwrap();
        assert!(search["items"].as_array().unwrap().iter().all(|e| e["kind"] == "event"));
        assert!(search["total"].as_i64().unwrap() >= 0);
        let table = s.call(&json!({"op":"table","limit":500,"filter":{"tracks_off":[2]}})).unwrap();
        assert!(table["items"].as_array().unwrap().iter().all(|r| r["track"] != json!(2)));
        assert!(table["count"].as_i64().unwrap() > 0, "첫 쪽에는 통틀어 몇 줄인지가 실린다");
        let year = s.call(&json!({"op":"same_year","at":0,"end":0,"window":0,"filter":{"hist_off":[2]}})).unwrap();
        assert!(year["eras"].as_array().unwrap().iter().all(|g| g["periods"].as_array().unwrap().iter().all(|p| p["uid"] != "b-legend")));
        let list = s.call(&json!({"op":"list","lo":-DAY,"hi":DAY,"lane":0,"lanes":1,"order":"start","filter":{"min_importance":3}})).unwrap();
        assert!(list["items"].as_array().unwrap().iter().all(|e| e["importance"] == json!(3)));
        assert!(list["items"][0]["uid"].is_string() && list["items"][0]["color"].is_number(), "묶음 카드가 읽을 열이 함께 온다");
        // 범례는 자료 전체를 본다 — 거르개를 주어도 답이 달라지지 않는다.
        let plain = s.call(&json!({"op":"legend_kinds"})).unwrap();
        assert_eq!(s.call(&json!({"op":"legend_kinds","filter":{"kinds_off":[5]}})).unwrap(), plain);
    });
}

#[test]
fn 잘못된_거르개는_까닭과_함께_실패한다() {
    with_store("bad", |s, _| {
        let fails = |q: Value| -> String { s.call(&q).map(|v| v.to_string()).unwrap_err().to_string() };
        assert!(fails(json!({"op":"rows_near","near":[0,1],"packs":[1],"filter":{"tracks_off":["첫 트랙"]}})).contains("정수가 아닌"));
        assert!(fails(json!({"op":"rows_near","near":[0,1],"packs":[1],"filter":{"cats_off":[-1]}})).contains("0 이상"));
        assert!(fails(json!({"op":"rows_near","near":[0,1],"packs":[1],"filter":{"min_importance":-3}})).contains("0 이상"));
        assert!(fails(json!({"op":"rows_near","near":[0,1],"packs":[1],"filter":{"min_importance":"셋"}})).contains("정수"));
        assert!(fails(json!({"op":"rows_near","near":[0,1],"packs":[1],"filter":[1,2]})).contains("열쇠 표"));
        assert!(fails(json!({"op":"rows_near","near":[0,1],"packs":[1],"filter":{"kinds_off":7}})).contains("목록"));
        // 타일도 같은 까닭으로 거절한다.
        assert!(s.filter_of(&json!({"filter":{"hist_off":[0.5]}})).is_err());
    });
}

#[test]
fn 대범위_칩과_간지_해는_거르기와_따로_논다() {
    with_store("scopes", |s, _| {
        assert_eq!(s.call(&json!({"op":"scopes"})).unwrap(), json!({"scopes":[]}), "대범위 기록이 없으면 빈 목록");
        let years = s.call(&json!({"op":"ganji_years","ganji":"갑자","center":2000,"lo":1900,"hi":2100,"limit":5})).unwrap();
        assert_eq!(years["years"], json!([1984, 2044, 1924, 2104, 1864]), "보는 시기 가운데에 가까운 순");
        assert!(s.call(&json!({"op":"ganji_years","ganji":"갑","lo":0,"hi":1})).is_err());
    });
}

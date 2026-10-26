//! 변형(variant) — 소속 펼치기와 대범위 모아 보기를 자료로 얹는 길(계약 2-4절 · 3-2절).
//! 확인하는 것: 변형을 주지 않으면 답이 예전과 같다 · 펼친 소속의 띠 · 칸 · 사건 · 일반 항목이 새 줄로 온다 ·
//! 이사한 띠가 **도착 줄의 묶음 타일**에 실린다 · `rows_near`가 떠난 줄을 비었다고 답한다 · 거르개와 함께 쓸 수 있다 ·
//! 잘못된 변형 이름은 까닭과 함께 실패한다.
//! 선반(kind 6 — 리메이크 4단계 선반 갈래 걸음 2): 숨는 띠(이사의 도착 줄 −1)와 그 칸 · 사건 · 기본 판 항목이 타일에 없고 켠 변형의 항목은 제자리 ·
//! 빠지는 줄(after −2 · ord −1)이 `rows_near`에서 비고 `layout`에 실린다 · 끄면 선반이 없는 저장소와 바이트까지 같다 · 줄 열쇠를 다시 매겨도
//! −1 · −2가 그대로다 · 배치 JSON(`import_layout_value`)과 지문 · 하위 배치(`patch`)가 이사 −1 · after −2 · kind 6을 그대로 나른다.
use archive_engine::builder::{Builder, CellIn, EventIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::legacy::import_layout_value;
use archive_engine::patch::{prints, sub_plan};
use archive_engine::tile::{build_tile, decode, Decoded, TileRequest, SEC_BAND};
use archive_engine::variant::{HIDDEN_ROW, SHELF_KIND};
use archive_engine::{Result, Store, DAY};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::path::PathBuf;

const YEAR: i64 = 365 * DAY;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-variants-{}-{name}", std::process::id())); // common::SCRATCH_KINDS의 꼴(끝난 검사의 것은 치움)
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn geo() -> RowGeo {
    RowGeo { height: 120, band_top: 19, band_h: 100, dyn_top: -1, lead_top: 23, cab_top: -1, text_top: 60, text_lines: 1, rail_top: 90, organ_top: -1 }
}

/// 검사용 저장소 하나.
///
/// 기본 줄 0~9(묶음 타일 0 = 0~7 · 1 = 8~15) · 변형 줄 10 · 11.
///   `host:h1`  줄 1의 상위 띠를 펼친다 — 새 줄 10 · 11에 속국 띠 둘(칸 · 일반 항목이 딸린다)이 서고,
///              줄 1에 적혀 있던 속국의 사건이 줄 10으로 **이사**한다.
///   `scope:s1` 줄 2의 띠가 줄 9로 **이사**한다(묶음 타일 0 → 1로 건너간다). 그 띠의 칸 · 사건 · 항목도 따라간다.
struct Fixture {
    path: PathBuf,
    _dir: PathBuf,
    host_band: i64,
    member_band: i64,
    moved_band: i64,
    moved_event: i64,
    stay_event: i64,
    base_item: i64,
}

fn build(name: &str) -> Result<Fixture> {
    let dir = scratch(name);
    let path = dir.join("archive.db");
    let mut b = Builder::create(&path)?;
    let pack = b.pack("변형 검사", None)?;
    let track = b.track_full(&TrackIn { pack, name: "별여울", color: 0xa0_bcc5, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "bv" })?;
    // 변형은 줄보다 먼저 만든다 — 줄의 `variant`가 이 번호를 가리킨다.
    let host = b.variant("host:h1", 1, track, 0, "", "은륜 제국", "")?;
    let scope = b.variant("scope:s1", 2, track, 0, "s1", "빈 왕좌의 할거", "")?;
    let mut rows = Vec::new();
    for _ in 0..10 {
        rows.push(b.row_full(track, &geo(), &RowExtra::default())?);
    }
    // 변형 줄 둘(소속 줄 kind 1).
    let member_rows: Vec<i64> = (0..2)
        .map(|_| b.row_full(track, &geo(), &RowExtra { kind: 1, variant: host, ..Default::default() }).unwrap())
        .collect();
    assert_eq!(member_rows, vec![10, 11]);

    let band = |b: &mut Builder, row: i64, uid: &str, from: i64, to: i64, variant: i64| -> Result<i64> {
        b.period_full(&PeriodIn { pack, row, start: from * YEAR, end: to * YEAR, fuzzy: 0, color: 0xa0_bcc5, name: uid, look: 0, tag: "", sub: 0, uid, variant, form: 0 })
    };
    let host_band = band(&mut b, 1, "h1", 0, 100, 0)?;
    let moved_band = band(&mut b, 2, "p-moves", 0, 100, 0)?;
    band(&mut b, 9, "p-nine", 0, 100, 0)?; // 도착 줄에 이미 있던 띠(이사해 온 띠와 나란히 실린다)
    let member_band = band(&mut b, 10, "m1", 0, 100, host)?;
    band(&mut b, 11, "m2", 0, 100, host)?;
    // 딸린 칸: 변형 띠의 칸은 그 변형에서만 나온다.
    b.cell_full(&CellIn { period: member_band, kind: 1, start: 0, end: 100 * YEAR, name: "첫 지도자", lane: 0, style: 0, color: 0, variant: host })?;
    b.cell_full(&CellIn { period: moved_band, kind: 1, start: 0, end: 100 * YEAR, name: "이사하는 띠의 지도자", lane: 0, style: 0, color: 0, variant: 0 })?;

    let event = |b: &mut Builder, lane: i64, uid: &str, at: i64, band: i64, variant: i64| -> Result<i64> {
        b.event(&EventIn { pack, lane, start: Some(at * YEAR), end: Some(at * YEAR), importance: 2, title: uid, uid, band, variant, ..Default::default() })
    };
    // 상위 띠의 줄에 적혀 있지만 실은 속국의 사건 — 펼치면 속국의 줄로 간다.
    let moved_event = event(&mut b, 1, "ev-member", 30, host_band, 0)?;
    let stay_event = event(&mut b, 1, "ev-host", 40, host_band, 0)?;
    event(&mut b, 2, "ev-moved-band", 50, moved_band, 0)?;
    event(&mut b, 10, "ev-member-only", 35, member_band, host)?;

    // 일반 항목: 기본 판 하나(변형에서 가려진다) · 그 변형 판 · 변형에서만 생기는 항목.
    let base_item = b.item(&ItemIn { pack, section: 20, row: 2, row2: 2, start: 0, end: 100 * YEAR, lod: None, ref_id: moved_band, ref_kind: 1,
        name: "네모", color: 0, a: 1, b: 0, c: 0, d: 0, text2: "", variant: 0 })?;
    b.item(&ItemIn { pack, section: 20, row: 9, row2: 9, start: 0, end: 100 * YEAR, lod: None, ref_id: moved_band, ref_kind: 1,
        name: "네모", color: 0, a: 2, b: 0, c: 0, d: 0, text2: "", variant: scope })?;
    b.variant_hide(scope, 4, base_item)?;
    b.item(&ItemIn { pack, section: 16, row: 10, row2: 10, start: 0, end: 100 * YEAR, lod: None, ref_id: member_band, ref_kind: 1,
        name: "속국 이름표", color: 0, a: 0, b: 1, c: 0, d: 0, text2: "m1", variant: host })?;
    // 소속선: 상국 줄(1)에서 소속 줄(10)까지 — 그 변형에서만 있다.
    b.item(&ItemIn { pack, section: 22, row: 1, row2: 10, start: 0, end: 100 * YEAR, lod: None, ref_id: member_band, ref_kind: 1,
        name: "소속선", color: 0, a: 0, b: 0, c: 0, d: 0, text2: "", variant: host })?;

    // 쌓는 차례: 새 줄 둘은 줄 1 바로 아래에, 줄 2는 그 뒤로 밀린다.
    b.variant_row(host, 10, 1, 0, true, 0, 0)?;
    b.variant_row(host, 11, 10, 0, true, 0, 0)?;
    b.variant_row(host, 2, 11, 0, false, 0, 0)?;
    // 대범위: 줄 2가 줄 8 아래로 옮겨 쌓이고 띠도 줄 9로 이사한다.
    b.variant_row(scope, 9, 8, 0, false, 16, 1)?;
    b.variant_move(scope, 1, moved_band, 9)?;
    b.variant_move(host, 2, moved_event, 10)?;
    b.variant_group(scope, "__scope:s1", 0, "빈 왕좌의 할거", 0xd4_a3_9b, 2, &[9])?;
    b.variant_band(host, host_band)?;
    b.finalize(&[])?;
    Ok(Fixture { path, _dir: dir, host_band, member_band, moved_band, moved_event, stay_event, base_item })
}

fn tile(store: &Store, chunk: i64, variants: &[&str]) -> Decoded {
    let q = json!({ "variants": variants });
    let req = TileRequest { level: 14, x: 0, chunk, packs: vec![1], filter: None, variants: store.variants_of(&q).unwrap() };
    decode(&build_tile(store, &req).unwrap()).unwrap()
}

fn bytes(store: &Store, chunk: i64, q: &Value) -> Vec<u8> {
    let req = TileRequest { level: 14, x: 0, chunk, packs: vec![1], filter: None, variants: store.variants_of(q).unwrap() };
    build_tile(store, &req).unwrap()
}

fn names(t: &Decoded, section: u32) -> Vec<(u32, String)> {
    t.section(section).iter().map(|i| (i.row, t.strings.get(i.name as usize).cloned().unwrap_or_default())).collect()
}

#[test]
fn 변형을_주지_않으면_답은_예전과_같다() {
    let f = build("plain").unwrap();
    let s = Store::open(&f.path).unwrap();
    // 변형 자료가 있어도, 켠 것이 없으면 변형 전용 줄 · 띠 · 사건 · 항목은 하나도 실리지 않는다.
    for chunk in 0..2 {
        assert_eq!(bytes(&s, chunk, &json!({})), bytes(&s, chunk, &json!({ "variants": [] })), "빈 목록은 열쇠가 없는 것과 같다");
    }
    let base = tile(&s, 1, &[]);
    assert!(base.bands.iter().all(|b| b.row < 10), "변형 줄의 띠는 기본 답에 없다");
    assert!(base.events.iter().all(|e| e.row < 10), "변형 줄의 사건은 기본 답에 없다");
    assert!(base.section(16).is_empty(), "변형에서만 생기는 이름표는 기본 답에 없다");
    let first = tile(&s, 0, &[]);
    assert_eq!(names(&first, 20), vec![(2, "네모".to_owned())], "가려지는 기본 판은 켜지 않으면 그대로 있다");
}

#[test]
fn 소속을_펼치면_속국의_띠와_칸과_사건과_항목이_새_줄로_온다() {
    let f = build("host").unwrap();
    let s = Store::open(&f.path).unwrap();
    let on = tile(&s, 1, &["host:h1"]);
    let rows: Vec<u32> = on.bands.iter().filter(|b| b.row >= 10).map(|b| b.row).collect();
    assert_eq!(rows, vec![10, 11], "속국 띠 둘이 새 줄에 선다");
    assert_eq!(on.cells.iter().filter(|c| c.row == 10).count(), 1, "속국 띠의 칸도 함께 온다");
    let on_ten: Vec<String> = on.events.iter().filter(|e| e.row == 10).map(|e| on.strings[e.name as usize].clone()).collect();
    assert!(on_ten.contains(&"ev-member-only".to_owned()), "그 변형에서만 있는 사건");
    assert!(on_ten.contains(&"ev-member".to_owned()), "상국 줄에 적혀 있던 속국의 사건이 이사한다");
    assert_eq!(names(&on, 16), vec![(10, "속국 이름표".to_owned())]);
    // 소속선은 상국 줄(1)에서 소속 줄(10)까지 걸쳐 두 묶음 타일에 모두 실린다.
    assert_eq!(tile(&s, 0, &["host:h1"]).section(22).len(), 1);
    assert_eq!(on.section(22).len(), 1);

    // 상국의 사건은 제자리에 남는다.
    let host_chunk = tile(&s, 0, &["host:h1"]);
    let stay: Vec<u32> = host_chunk.events.iter().filter(|e| e.id as i64 == f.stay_event).map(|e| e.row).collect();
    assert_eq!(stay, vec![1], "상국 제 사건은 이사하지 않는다");
    assert!(host_chunk.events.iter().all(|e| e.id as i64 != f.moved_event), "이사한 사건은 떠난 줄의 타일에 없다");
    assert!(f.host_band > 0 && f.member_band > 0);
}

#[test]
fn 이사한_띠는_도착_줄의_묶음_타일에_실린다() {
    let f = build("move").unwrap();
    let s = Store::open(&f.path).unwrap();
    let left = tile(&s, 0, &["scope:s1"]);
    assert!(left.bands.iter().all(|b| b.id as i64 != f.moved_band), "떠난 줄의 묶음 타일에는 없다");
    assert!(left.cells.is_empty(), "그 띠의 칸도 함께 떠난다");
    assert!(left.section(20).is_empty(), "가려진 기본 판(네모)도 없다");
    let right = tile(&s, 1, &["scope:s1"]);
    let moved: Vec<u32> = right.bands.iter().filter(|b| b.id as i64 == f.moved_band).map(|b| b.row).collect();
    assert_eq!(moved, vec![9], "도착 줄의 묶음 타일에 도착 줄 번호로 실린다");
    assert_eq!(right.bands.iter().filter(|b| b.row == 9).count(), 2, "원래 그 줄에 있던 띠와 나란히");
    assert!(right.bands.windows(2).all(|w| (w[0].row, w[0].x0) <= (w[1].row, w[1].x0)), "띠는 (줄, 시작) 차례를 지킨다");
    assert_eq!(right.cells.iter().filter(|c| c.row == 9).count(), 1, "칸도 도착 줄로");
    assert!(right.events.iter().any(|e| e.row == 9 && right.strings[e.name as usize] == "ev-moved-band"), "그 띠의 사건도 도착 줄로");
    // 가리는 것: 기본 판은 사라지고 변형 판(a = 2)이 대신 나온다.
    let squares: Vec<(u32, u32)> = right.section(20).iter().map(|i| (i.row, i.a)).collect();
    assert_eq!(squares, vec![(9, 2)]);
    assert!(f.base_item > 0);
}

#[test]
fn rows_near는_떠난_줄을_비었다고_답하고_도착_줄을_답한다() {
    let f = build("near").unwrap();
    let s = Store::open(&f.path).unwrap();
    let range = (0, 100 * YEAR);
    let plain = s.rows_near(range.0, range.1, 0, &[1], None, s.variants_of(&json!({})).unwrap().as_ref()).unwrap();
    assert_eq!(plain, vec![1, 2, 9], "변형이 없으면 기본 줄만");
    let scope = s.variants_of(&json!({"variants":["scope:s1"]})).unwrap();
    assert_eq!(s.rows_near(range.0, range.1, 0, &[1], None, scope.as_ref()).unwrap(), vec![1, 9], "떠난 줄 2는 비었다");
    let host = s.variants_of(&json!({"variants":["host:h1"]})).unwrap();
    assert_eq!(s.rows_near(range.0, range.1, 0, &[1], None, host.as_ref()).unwrap(), vec![1, 2, 9, 10, 11], "펼친 소속 줄이 더해진다");
}

#[test]
fn 줄_이름은_켠_변형의_줄에만_있다() {
    let f = build("labels").unwrap();
    let s = Store::open(&f.path).unwrap();
    let plain = s.row_labels(&[1, 10], None, s.variants_of(&json!({})).unwrap().as_ref()).unwrap();
    assert_eq!(plain["labels"][1]["items"].as_array().unwrap().len(), 0, "켜지 않은 변형의 줄은 이름이 없다");
    assert!(f.member_band > 0);
}

#[test]
fn 거르개와_함께_쓸_수_있다() {
    let f = build("filter").unwrap();
    let s = Store::open(&f.path).unwrap();
    // 중요도 문턱 3: 검사 자료의 사건은 모두 2라 모두 빠지고, 띠는 그대로 남는다.
    let q = json!({"variants":["host:h1"],"filter":{"min_importance":3}});
    let req = TileRequest { level: 14, x: 0, chunk: 1, packs: vec![1], filter: s.filter_of(&q).unwrap(), variants: s.variants_of(&q).unwrap() };
    let t = decode(&build_tile(&s, &req).unwrap()).unwrap();
    assert!(t.events.is_empty(), "거르개가 사건을 모두 걸렀다");
    assert_eq!(t.bands.iter().filter(|b| b.row >= 10).count(), 2, "변형의 띠는 그대로 온다");
    // 트랙을 끄면 변형의 줄도 함께 빠진다(그 줄도 이 트랙의 줄이다).
    let off = json!({"variants":["host:h1"],"filter":{"tracks_off":[1]}});
    let req = TileRequest { level: 14, x: 0, chunk: 1, packs: vec![1], filter: s.filter_of(&off).unwrap(), variants: s.variants_of(&off).unwrap() };
    let t = decode(&build_tile(&s, &req).unwrap()).unwrap();
    assert!(t.bands.is_empty() && t.events.is_empty(), "끈 트랙은 변형에서도 비어 있다");
    assert!(f.host_band > 0);
}

#[test]
fn 잘못된_변형은_까닭과_함께_실패한다() {
    let f = build("bad").unwrap();
    let s = Store::open(&f.path).unwrap();
    let err = s.variants_of(&json!({"variants":["host:없는것"]})).unwrap_err().to_string();
    assert!(err.contains("없는 변형"), "{err}");
    assert!(s.variants_of(&json!({"variants":[3]})).is_err(), "글이 아닌 열쇠");
    assert!(s.variants_of(&json!({"variants":""})).is_err(), "목록이 아닌 값");
    assert!(s.variants_of(&json!({"variants":[""]})).is_err(), "빈 열쇠");
    // 같은 열쇠를 두 번 주어도 한 번 켠 것과 같다.
    let twice = s.variants_of(&json!({"variants":["host:h1","host:h1"]})).unwrap().unwrap();
    assert_eq!(twice.on.len(), 1);
    assert!(f.moved_event > 0);
}

#[test]
fn layout이_변형의_목록과_쌓는_차례를_함께_준다() {
    let f = build("layout").unwrap();
    let s = Store::open(&f.path).unwrap();
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    let list = shape["variants"].as_array().unwrap();
    assert_eq!(list.len(), 2);
    assert_eq!(list[0]["key"], "host:h1");
    assert_eq!(list[0]["kind"], 1);
    assert_eq!(list[0]["band"].as_i64(), Some(f.host_band), "소속 펼치기는 상위 띠의 번호를 함께 준다");
    let rows: Vec<(i64, i64, i64)> = list[0]["rows"].as_array().unwrap().iter()
        .map(|r| (r["row"].as_i64().unwrap(), r["after"].as_i64().unwrap(), r["new"].as_i64().unwrap())).collect();
    assert_eq!(rows, vec![(2, 11, 0), (10, 1, 1), (11, 10, 1)]);
    assert_eq!(list[1]["groups"][0]["rows"], json!([9]), "대범위 가지의 줄 목록");
    // 줄의 `variant`는 그 줄을 만드는 변형의 번호다.
    let track_rows = shape["tracks"][0]["rows"].as_array().unwrap();
    assert_eq!(track_rows[10]["variant"].as_i64(), Some(1));
    assert_eq!(track_rows[0]["variant"].as_i64(), Some(0));
    assert_eq!(SEC_BAND, 1);
}

// ---------------------------------------------------------------- 선반(kind 6 — 리메이크 4단계 선반 갈래 걸음 2)

/// 선반 검사의 시간 단위(10년) — 단계 14 타일의 칸 추림(통의 1/8 ≈ 64년)에 걸리지 않게 칸을 넉넉히 길게.
const UNIT: i64 = 10 * YEAR;

/// 선반 검사 저장소. `with_shelf`가 거짓이면 선반 변형 · 그 줄 · 그 항목 · 쌓는 차례 · 이사만 없는 같은 저장소다(띠 · 칸 · 사건 · 기본 항목의 번호는 같다).
///
/// 기본 줄 0~9(묶음 타일 0 = 0~7 · 1 = 8~15) · 선반 줄 10. 트랙 하나(하연)의 그릇 구성원(기간은 [UNIT] — 10년 단위):
///   줄 0: k1                       줄 1: k2(0~40 · 남음) · h1(60~100 · 숨음)
///   줄 2: h2(숨음 — 줄이 비어 빠진다)
///   줄 3: k3a(0~40) · h3(45~55 · 숨음) · k3b(60~100) — 남는 둘은 다시 지은 새 줄 10으로 가고 줄 3은 빠진다
///   줄 4: k4(그릇 발 — 숨긴 구성원 꼬리표 셋 h1 · h2 · h3이 선다 · 구역 59)          줄 9: k9
/// `shelf:s-cup` 쌓는 차례: 줄 2 · 3은 after −2(ord −1 — 옮겨 간 판 줄 없음), 새 줄 10은 줄 1 아래, 줄 4는 줄 10 아래. 그릇 묶음 줄 0 · 1 · 10 · 4.
struct Shelf {
    path: PathBuf,
    dir: PathBuf,
    k1: i64,
    k2: i64,
    h1: i64,
    h2: i64,
    h3: i64,
    k3a: i64,
    k3b: i64,
    ev_h2: i64,
    ev_k3a: i64,
    /// 기본 판 이름표(h1을 가리킴 — 선반을 켜면 함께 숨는다).
    item_h1: i64,
    /// 기본 판 두 줄 관계선(줄 0 ~ 2 · h2를 가리킴 — 함께 숨는다. 고치기 전에는 한쪽 끝이 −1 줄이 되어 `u32`로 넘쳤다).
    item_link: i64,
    /// 기본 판 이름표(k3a를 가리킴 — 줄 10으로 따라간다).
    item_k3a: i64,
    /// 선반 변형의 항목(숨긴 구성원 꼬리표 — h1을 가리킨 채 제자리 · 그릇 안 차례 a 5). 선반이 없는 저장소는 0.
    tag: i64,
    /// 숨긴 구성원 꼬리표 셋의 번호(h1 · h2 · h3 차례 — a 5 · 6 · 7). 선반이 없는 저장소는 빈 목록.
    tags: Vec<i64>,
}

fn build_shelf(name: &str, with_shelf: bool) -> Result<Shelf> {
    let dir = scratch(name);
    let path = dir.join("archive.db");
    let mut b = Builder::create(&path)?;
    let pack = b.pack("선반 검사", None)?;
    let track = b.track_full(&TrackIn { pack, name: "하연", color: 0xa0_bcc5, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "hy" })?;
    let shelf = if with_shelf { b.variant("shelf:s-cup", SHELF_KIND, track, 0, "s-cup", "등불 그릇", "")? } else { 0 };
    for _ in 0..10 {
        b.row_full(track, &geo(), &RowExtra::default())?;
    }
    if with_shelf {
        assert_eq!(b.row_full(track, &geo(), &RowExtra { variant: shelf, ..Default::default() })?, 10, "다시 지은 줄은 선반에서만 있다");
    }
    let band = |b: &mut Builder, row: i64, uid: &str, from: i64, to: i64| -> Result<i64> {
        b.period_full(&PeriodIn { pack, row, start: from * UNIT, end: to * UNIT, fuzzy: 0, color: 0xa0_bcc5, name: uid, look: 0, tag: "", sub: 0, uid, variant: 0, form: 0 })
    };
    let k1 = band(&mut b, 0, "k1", 0, 100)?;
    let k2 = band(&mut b, 1, "k2", 0, 40)?;
    let h1 = band(&mut b, 1, "h1", 60, 100)?;
    let h2 = band(&mut b, 2, "h2", 0, 100)?;
    let k3a = band(&mut b, 3, "k3a", 0, 40)?;
    let h3 = band(&mut b, 3, "h3", 45, 55)?;
    let k3b = band(&mut b, 3, "k3b", 60, 100)?;
    band(&mut b, 4, "k4", 0, 100)?;
    band(&mut b, 9, "k9", 0, 100)?;
    let cell = |b: &mut Builder, period: i64, from: i64, to: i64, name: &str| -> Result<i64> {
        b.cell_full(&CellIn { period, kind: 1, start: from * UNIT, end: to * UNIT, name, lane: 0, style: 0, color: 0, variant: 0 })
    };
    cell(&mut b, h1, 60, 100, "숨는 나라의 지도자")?;
    cell(&mut b, k3a, 0, 40, "옮기는 나라의 지도자")?;
    let event = |b: &mut Builder, lane: i64, uid: &str, at: i64, band: i64| -> Result<i64> {
        b.event(&EventIn { pack, lane, start: Some(at * UNIT), end: Some(at * UNIT), importance: 2, title: uid, uid, band, variant: 0, ..Default::default() })
    };
    event(&mut b, 0, "ev-k1", 10, k1)?;
    let ev_h2 = event(&mut b, 2, "ev-h2", 50, h2)?;
    let ev_k3a = event(&mut b, 3, "ev-k3a", 20, k3a)?;
    let item = |b: &mut Builder, section: i64, rows: (i64, i64), from: i64, to: i64, ref_id: i64, name: &str, variant: i64| -> Result<i64> {
        b.item(&ItemIn { pack, section, row: rows.0, row2: rows.1, start: from * UNIT, end: to * UNIT, lod: None, ref_id, ref_kind: 1,
            name, color: 0, a: 0, b: 0, c: 0, d: 0, text2: "", variant })
    };
    let item_h1 = item(&mut b, 16, (1, 1), 60, 100, h1, "숨는 이름표", 0)?;
    let item_link = item(&mut b, 22, (0, 2), 0, 100, h2, "숨는 관계선", 0)?;
    let item_k3a = item(&mut b, 16, (3, 3), 0, 40, k3a, "옮기는 이름표", 0)?;
    b.row_label(1, 0, 40 * UNIT, k2, r#"{"name":"k2"}"#)?;
    b.row_label(1, 60 * UNIT, 100 * UNIT, h1, r#"{"name":"h1"}"#)?;
    let mut tags = Vec::new();
    if with_shelf {
        // 선반 항목(숨긴 구성원 꼬리표 — 구역 59 · 계약 6-10절)은 기본 항목 뒤에 넣는다 — 선반이 없는 저장소와 기본 항목의 번호가 같게.
        // 넣는 차례를 그릇 안 차례(a)와 어긋나게(h3 · h1 · h2) — `layout`의 `shelf`가 번호가 아니라 a 차례로 고르는지 본다.
        let tag = |b: &mut Builder, band: i64, uid: &str, from: i64, to: i64, a: i64| -> Result<i64> {
            b.item(&ItemIn { pack, section: 59, row: 4, row2: 4, start: from * UNIT, end: to * UNIT, lod: Some(14), ref_id: band, ref_kind: 1,
                name: uid, color: 0xc8_a070, a, b: 3, c: 0, d: 0, text2: uid, variant: shelf })
        };
        let t3 = tag(&mut b, h3, "h3", 45, 55, 7)?;
        let t1 = tag(&mut b, h1, "h1", 60, 100, 5)?;
        let t2 = tag(&mut b, h2, "h2", 0, 100, 6)?;
        tags = vec![t1, t2, t3];
        // 그 변형의 그릇 묶음(가지의 줄 — 쌓는 차례대로 · 끝 줄 4가 폴더 발). `layout`은 꼬리표를 이 줄 범위에서 찾는다.
        b.variant_group(shelf, "__scope:s-cup", 0, "등불 그릇", 0xa0_bcc5, 2, &[0, 1, 10, 4])?;
        b.variant_row(shelf, 2, -2, -1, false, 0, 0)?;
        b.variant_row(shelf, 3, -2, -1, false, 0, 0)?;
        b.variant_row(shelf, 10, 1, 0, true, 0, 0)?;
        b.variant_row(shelf, 4, 10, 0, false, 0, 0)?;
        for hidden in [h1, h2, h3] {
            b.variant_move(shelf, 1, hidden, HIDDEN_ROW)?;
        }
        // 숨은 띠의 사건은 내보내기가 제 이사 −1로도 싣는다(선반 갈래 검토 고침 — 예전엔 공통 줄로의 이사가 실려 띠의 −1보다 먼저 읽혔다)
        b.variant_move(shelf, 2, ev_h2, HIDDEN_ROW)?;
        b.variant_move(shelf, 1, k3a, 10)?;
        b.variant_move(shelf, 1, k3b, 10)?;
    }
    b.finalize(&[])?;
    let tag = tags.first().copied().unwrap_or(0);
    Ok(Shelf { path, dir, k1, k2, h1, h2, h3, k3a, k3b, ev_h2, ev_k3a, item_h1, item_link, item_k3a, tag, tags })
}

/// 띠 번호의 모음.
fn band_ids(t: &Decoded) -> BTreeSet<i64> {
    t.bands.iter().map(|b| b.id as i64).collect()
}

/// 그 구역 항목의 (번호, 줄, 끝 줄).
fn items_of(t: &Decoded, section: u32) -> Vec<(i64, u32, u32)> {
    t.section(section).iter().map(|i| (i.id as i64, i.row, i.row2)).collect()
}

const SHELF: &str = "shelf:s-cup";

#[test]
fn 선반을_켜면_숨은_띠와_딸린_것이_타일에_없고_선반의_꼬리표는_제자리다() {
    let f = build_shelf("shelf-on", true).unwrap();
    let s = Store::open(&f.path).unwrap();
    let off = tile(&s, 0, &[]);
    let on = tile(&s, 0, &[SHELF]);
    for hidden in [f.h1, f.h2, f.h3] {
        assert!(band_ids(&off).contains(&hidden), "끄면 그대로 있다");
        assert!(!band_ids(&on).contains(&hidden), "켜면 숨는다");
    }
    assert!(band_ids(&on).contains(&f.k1) && band_ids(&on).contains(&f.k2), "남는 구성원은 제 줄에");
    assert!(!band_ids(&on).contains(&f.k3a) && !band_ids(&on).contains(&f.k3b), "다시 지은 줄(10)로 떠났다");
    assert_eq!(off.cells.len(), 2);
    assert!(on.cells.is_empty(), "숨은 띠의 칸은 숨고, 옮긴 띠의 칸은 도착 줄의 묶음 타일로 간다");
    let events = |t: &Decoded| -> Vec<i64> { t.events.iter().map(|e| e.id as i64).collect() };
    assert!(events(&off).contains(&f.ev_h2));
    assert!(!events(&on).contains(&f.ev_h2), "숨은 띠의 사건도 숨는다");
    assert!(!events(&on).contains(&f.ev_k3a), "옮긴 띠의 사건은 도착 줄로");
    // 일반 항목: 숨은 띠를 가리키는 기본 판(한 줄 이름표 · 두 줄 관계선)은 빠지고, 선반의 항목(꼬리표)은 숨은 띠를 가리킨 채 제자리.
    assert_eq!(items_of(&off, 16), vec![(f.item_h1, 1, 1), (f.item_k3a, 3, 3)]);
    assert_eq!(items_of(&off, 22), vec![(f.item_link, 0, 2)]);
    assert!(off.section(59).is_empty(), "끄면 선반의 항목은 없다");
    assert!(items_of(&on, 16).is_empty(), "숨은 띠의 이름표는 빠지고 옮긴 띠의 이름표는 도착 줄로");
    assert!(on.section(22).is_empty(), "두 줄 관계선도 빠진다(−1 줄로 늘어나 넘치지 않는다)");
    // 꼬리표 셋은 가지 끝 줄 4에 시작 차례로(타일의 일반 구역 정렬 — 줄 · 시작 · 번호): h2(0) · h3(45) · h1(60).
    let (t1, t2, t3) = (f.tags[0], f.tags[1], f.tags[2]);
    assert_eq!(items_of(&on, 59), vec![(t2, 4, 4), (t3, 4, 4), (t1, 4, 4)]);
    assert_eq!(f.tag, t1);
    let refs: Vec<i64> = on.section(59).iter().map(|i| i.reference as i64).collect();
    assert_eq!(refs, vec![f.h2, f.h3, f.h1], "꼬리표는 숨은 띠를 가리킨다");
    for section in &on.sections {
        assert!(section.items.iter().all(|i| i.row < 16 && i.row2 < 16), "넘친 줄 번호가 없다");
    }
    // 다시 지은 줄 10 — 도착 줄의 묶음 타일에 실린다.
    let right = tile(&s, 1, &[SHELF]);
    let moved: Vec<(i64, u32)> = right.bands.iter().filter(|b| b.row == 10).map(|b| (b.id as i64, b.row)).collect();
    assert_eq!(moved, vec![(f.k3a, 10), (f.k3b, 10)]);
    assert!(band_ids(&right).is_disjoint(&[f.h1, f.h2, f.h3].into()), "숨은 띠는 어느 묶음에도 없다");
    assert_eq!(right.cells.iter().filter(|c| c.row == 10).count(), 1, "옮긴 띠의 칸");
    assert!(right.events.iter().any(|e| e.id as i64 == f.ev_k3a && e.row == 10), "옮긴 띠의 사건");
    assert_eq!(items_of(&right, 16), vec![(f.item_k3a, 10, 10)], "옮긴 띠의 이름표");
    assert!(tile(&s, 1, &[]).bands.iter().all(|b| b.row < 10), "끄면 선반 줄은 비어 있다");
}

#[test]
fn 선반을_끄면_선반이_없는_저장소와_답이_바이트까지_같다() {
    let with = build_shelf("shelf-with", true).unwrap();
    let without = build_shelf("shelf-without", false).unwrap();
    let (a, b) = (Store::open(&with.path).unwrap(), Store::open(&without.path).unwrap());
    for chunk in 0..2 {
        for q in [json!({}), json!({ "variants": [] })] {
            assert_eq!(bytes(&a, chunk, &q), bytes(&b, chunk, &q), "묶음 {chunk} · {q}");
        }
    }
    let near = |s: &Store| s.rows_near(0, 100 * UNIT, 0, &[1], None, s.variants_of(&json!({})).unwrap().as_ref()).unwrap();
    assert_eq!(near(&a), near(&b));
    assert_eq!(near(&a), vec![0, 1, 2, 3, 4, 9]);
    let labels = |s: &Store| s.row_labels(&[1, 2, 3], None, s.variants_of(&json!({})).unwrap().as_ref()).unwrap();
    assert_eq!(labels(&a), labels(&b));
    assert_eq!(labels(&a)["labels"][0]["items"], json!([{"name":"k2"}, {"name":"h1"}]), "끄면 숨는 띠도 이름 후보");
    assert!(without.tag == 0 && with.tag > 0);
}

#[test]
fn rows_near는_선반의_빠진_줄과_숨은_띠만_있는_줄을_비었다고_답한다() {
    let f = build_shelf("shelf-near", true).unwrap();
    let s = Store::open(&f.path).unwrap();
    let on = s.variants_of(&json!({ "variants": [SHELF] })).unwrap();
    let plain = s.variants_of(&json!({})).unwrap();
    assert_eq!(s.rows_near(0, 100 * UNIT, 0, &[1], None, on.as_ref()).unwrap(), vec![0, 1, 4, 9, 10],
        "빠진 줄 2 · 3은 비었고 다시 지은 줄 10이 더해진다 — 숨은 것의 −1은 답에 없다");
    // 70~80: 줄 1에는 숨는 h1만 걸친다.
    assert_eq!(s.rows_near(70 * UNIT, 80 * UNIT, 0, &[1], None, plain.as_ref()).unwrap(), vec![0, 1, 2, 3, 4, 9]);
    assert_eq!(s.rows_near(70 * UNIT, 80 * UNIT, 0, &[1], None, on.as_ref()).unwrap(), vec![0, 4, 9, 10]);
    // 50(ev-h2의 때): 줄 2는 h2와 그 사건이 모두 숨어 빈다.
    assert!(!s.rows_near(50 * UNIT, 50 * UNIT, 0, &[1], None, on.as_ref()).unwrap().contains(&2));
    assert!(f.ev_h2 > 0);
}

/// 묶음 카드의 사건 목록(`{"op":"list"}` — 앱 `ui/cards.dart`와 같은 꼴)을 자리 [lane] 한 줄로 묻고 (uid, 답의 줄)을 받은 차례(번호)대로.
fn listed(s: &Store, lane: i64, hi: i64, variants: &[&str]) -> Vec<(String, i64)> {
    let answer = s.call(&json!({"op":"list","lo":0,"hi":hi,"lane":lane,"lanes":1,"after":0,"variants":variants})).unwrap();
    answer["items"].as_array().unwrap().iter().map(|x| (x["uid"].as_str().unwrap().to_owned(), x["lane"].as_i64().unwrap())).collect()
}

fn pairs_of(list: &[(&str, i64)]) -> Vec<(String, i64)> {
    list.iter().map(|(uid, lane)| ((*uid).to_owned(), *lane)).collect()
}

#[test]
fn list는_이사해_들어온_사건을_도착_줄에서_싣고_떠난_사건은_도착_줄로_적어_준다() {
    // 검토 고침(리메이크 4단계 그림 갈래 과제 7): 예전에는 원래 줄로만 골라 도착 줄(새 줄 · 이사한 줄)의 카드가 비었다 — 타일의 reach와 같은 길.
    let f = build("list").unwrap();
    let s = Store::open(&f.path).unwrap();
    let hi = 100 * YEAR;
    // 끄면 기본 줄 그대로 — 변형에서만 있는 사건은 없다.
    assert_eq!(listed(&s, 1, hi, &[]), pairs_of(&[("ev-member", 1), ("ev-host", 1)]));
    assert!(listed(&s, 10, hi, &[]).is_empty());
    // 소속 펼치기 — 제 이사(kind 2): 상국 줄 1에 적힌 속국의 사건이 새 줄 10의 카드에 온다(그 변형에서만 있는 사건과 함께).
    assert_eq!(listed(&s, 10, hi, &["host:h1"]), pairs_of(&[("ev-member", 10), ("ev-member-only", 10)]));
    // 떠난 줄 1에서는 원래 줄로 걸려 도착 줄 10으로 적힌 채 온다(빼면 나눠 받기가 흔들려 받는 쪽이 뺀다 — 계약 2-4절).
    assert_eq!(listed(&s, 1, hi, &["host:h1"]), pairs_of(&[("ev-member", 10), ("ev-host", 1)]));
    // 대범위 — 띠 이사(kind 1): 줄 2의 띠가 줄 9로 가면 그 띠의 사건도 줄 9의 카드에.
    assert_eq!(listed(&s, 9, hi, &["scope:s1"]), pairs_of(&[("ev-moved-band", 9)]));
    assert_eq!(listed(&s, 2, hi, &["scope:s1"]), pairs_of(&[("ev-moved-band", 9)]));
    assert!(listed(&s, 9, hi, &[]).is_empty(), "끄면 줄 9에는 사건이 없다");
    assert!(f.moved_event > 0 && f.stay_event > 0);
}

#[test]
fn list는_선반의_다시_지은_줄에_옮긴_띠의_사건을_싣고_숨은_띠의_사건은_줄_음수_1로_준다() {
    let f = build_shelf("shelf-list-events", true).unwrap();
    let s = Store::open(&f.path).unwrap();
    let hi = 100 * UNIT;
    // 다시 지은 줄 10: 옮긴 띠(k3a · k3b)의 사건 — 원래 줄 3은 빠지는 줄이다.
    assert_eq!(listed(&s, 10, hi, &[SHELF]), pairs_of(&[("ev-k3a", 10)]));
    assert!(listed(&s, 10, hi, &[]).is_empty(), "끄면 다시 지은 줄은 비어 있다");
    assert_eq!(listed(&s, 3, hi, &[SHELF]), pairs_of(&[("ev-k3a", 10)]), "빠지는 줄 3: 떠난 사건은 도착 줄로 적힌 채");
    assert_eq!(listed(&s, 2, hi, &[SHELF]), pairs_of(&[("ev-h2", HIDDEN_ROW)]), "숨은 띠의 사건은 줄 −1(받는 쪽이 뺀다)");
    assert_eq!(listed(&s, 0, hi, &[SHELF]), pairs_of(&[("ev-k1", 0)]), "남는 구성원은 제 줄 그대로");
    assert!(f.ev_k3a > 0 && f.ev_h2 > 0);
}

#[test]
fn layout은_선반_변형과_빠지는_줄을_주고_줄_이름은_숨은_띠를_뺀다() {
    let f = build_shelf("shelf-layout", true).unwrap();
    let s = Store::open(&f.path).unwrap();
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    let list = shape["variants"].as_array().unwrap();
    assert_eq!(list.len(), 1);
    let v = &list[0];
    assert_eq!((v["key"].as_str(), v["kind"].as_i64(), v["uid"].as_str()), (Some(SHELF), Some(SHELF_KIND), Some("s-cup")));
    assert!(v.get("within").is_none(), "포개짐(within)은 그릇 변형(kind 2)에만");
    let rows: Vec<(i64, i64, i64, i64)> = v["rows"].as_array().unwrap().iter()
        .map(|r| (r["row"].as_i64().unwrap(), r["after"].as_i64().unwrap(), r["ord"].as_i64().unwrap(), r["new"].as_i64().unwrap())).collect();
    assert_eq!(rows, vec![(2, -2, -1, 0), (3, -2, -1, 0), (4, 10, 0, 0), (10, 1, 0, 1)], "빠지는 줄은 after −2 · ord −1");
    assert_eq!(shape["tracks"][0]["rows"][10]["variant"].as_i64(), v["id"].as_i64(), "다시 지은 줄은 선반에서만 있다");
    // 줄 이름: 켠 선반이 숨긴 띠는 이름 후보가 아니다.
    let on = s.variants_of(&json!({ "variants": [SHELF] })).unwrap();
    let labels = s.row_labels(&[1], None, on.as_ref()).unwrap();
    assert_eq!(labels["labels"][0]["items"], json!([{"name":"k2"}]));
    assert!(f.k2 > 0);
}

/// 선반 변형의 숨긴 구성원 목록(걸음 4 — 계약 2-4절 `shelf`): 그 변형의 구역 59 꼬리표를 그릇 안 차례(a)로.
fn shelf_want() -> Value {
    json!([
        {"uid":"h1","name":"h1","color":0xc8_a070,"start":60 * UNIT,"end":100 * UNIT,"ord":5},
        {"uid":"h2","name":"h2","color":0xc8_a070,"start":0,"end":100 * UNIT,"ord":6},
        {"uid":"h3","name":"h3","color":0xc8_a070,"start":45 * UNIT,"end":55 * UNIT,"ord":7},
    ])
}

#[test]
fn layout은_선반_변형에만_숨긴_구성원_목록을_그릇_안_차례로_싣는다() {
    let f = build_shelf("shelf-list", true).unwrap();
    let s = Store::open(&f.path).unwrap();
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    let v = &shape["variants"][0];
    assert_eq!(v["kind"].as_i64(), Some(SHELF_KIND));
    assert_eq!(v["shelf"], shelf_want(), "넣은 차례(h3 · h1 · h2)가 아니라 a 차례 — uid는 text2 · 끝은 분");
    assert_eq!(f.tags.len(), 3);
    // 다른 갈래(소속 펼치기 · 그릇)에는 `shelf`가 없다 — 선반이 없는 저장소의 답은 예전 그대로.
    let plain = build("shelf-list-plain").unwrap();
    let p = Store::open(&plain.path).unwrap();
    let list = p.call(&json!({"op":"layout"})).unwrap()["variants"].as_array().unwrap().clone();
    assert_eq!(list.len(), 2);
    assert!(list.iter().all(|v| v.get("shelf").is_none()), "shelf는 kind 6에만");
    // 그 변형의 묶음 줄 범위 밖에 놓인 59 항목 · 다른 구역 · 다른 변형의 항목은 들지 않는다 — 묶음이 없는 선반 변형은 빈 목록.
    let bare = scratch("shelf-list-bare").join("archive.db");
    {
        let mut b = Builder::create(&bare).unwrap();
        let pack = b.pack("선반 검사", None).unwrap();
        let track = b.track_full(&TrackIn { pack, name: "하연", color: 0xa0_bcc5, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "hy" }).unwrap();
        let shelf = b.variant("shelf:bare", SHELF_KIND, track, 0, "bare", "묶음 없는 그릇", "").unwrap();
        b.row_full(track, &geo(), &RowExtra::default()).unwrap();
        let band = b.period_full(&PeriodIn { pack, row: 0, start: 0, end: 10 * UNIT, fuzzy: 0, color: 0, name: "x", look: 0, tag: "", sub: 0, uid: "x", variant: 0, form: 0 }).unwrap();
        b.item(&ItemIn { pack, section: 59, row: 0, row2: 0, start: 0, end: 10 * UNIT, lod: None, ref_id: band, ref_kind: 1,
            name: "x", color: 0, a: 5, b: 1, c: 0, d: 0, text2: "x", variant: shelf }).unwrap();
        b.finalize(&[]).unwrap();
    }
    let bare = Store::open(&bare).unwrap();
    assert_eq!(bare.call(&json!({"op":"layout"})).unwrap()["variants"][0]["shelf"], json!([]));
}

#[test]
fn 줄_열쇠를_다시_매겨도_선반의_음수_값은_그대로고_답은_같다() {
    let f = build_shelf("shelf-rekey", true).unwrap();
    let split = f.dir.join("split.db");
    std::fs::copy(&f.path, &split).unwrap();
    {
        let mut db = rusqlite::Connection::open(&split).unwrap();
        db.execute_batch("PRAGMA foreign_keys=ON").unwrap();
        let tx = db.transaction().unwrap();
        tx.execute_batch("PRAGMA defer_foreign_keys=ON").unwrap();
        let next: i64 = tx.query_row("SELECT MAX(id)+1 FROM rows", [], |r| r.get(0)).unwrap();
        archive_engine::rowmap::rekey_track(&tx, 1, next + 3).unwrap();
        tx.execute("UPDATE meta SET value=?1 WHERE key='schema'", [archive_engine::schema::VERSION_SPLIT]).unwrap();
        tx.commit().unwrap();
    }
    let (a, b) = (Store::open(&f.path).unwrap(), Store::open(&split).unwrap());
    assert!(a.rows.is_identity() && !b.rows.is_identity());
    let hidden = |kind: i64| -> Vec<i64> {
        b.db.prepare("SELECT ref FROM variant_moves WHERE row=-1 AND kind=?1 ORDER BY ref").unwrap()
            .query_map([kind], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect()
    };
    assert_eq!(hidden(1), vec![f.h1, f.h2, f.h3], "숨는 이사의 −1은 다시 매기지 않는다");
    assert_eq!(hidden(2), vec![f.ev_h2], "숨는 사건의 −1도");
    let dropped: i64 = b.db.query_row("SELECT count(*) FROM variant_rows WHERE after=-2 AND ord=-1", [], |r| r.get(0)).unwrap();
    assert_eq!(dropped, 2, "빠지는 줄의 after −2 · ord −1도 그대로");
    for chunk in 0..2 {
        let q = json!({ "variants": [SHELF] });
        assert_eq!(bytes(&a, chunk, &q), bytes(&b, chunk, &q), "열쇠 ≠ 자리여도 같은 타일(묶음 {chunk})");
    }
    let on = |s: &Store| s.rows_near(0, 100 * UNIT, 0, &[1], None, s.variants_of(&json!({ "variants": [SHELF] })).unwrap().as_ref()).unwrap();
    assert_eq!(on(&a), on(&b));
    let layout = |s: &Store| s.call(&json!({"op":"layout"})).unwrap()["variants"].clone();
    assert_eq!(layout(&a), layout(&b), "layout의 쌓는 차례는 자리로 나간다 — −1 · −2는 그대로");
    assert_eq!(layout(&b)[0]["shelf"], shelf_want(), "숨긴 구성원 목록도 같다(꼬리표를 열쇠로 다시 매긴 줄 범위에서 찾음)");
    // 정규화(번호 없이 적은 답 — 변형마다 켠 보기의 타일 · 조회까지)도 같다. 선반 변형 · 빠지는 줄이 그대로 실린다.
    let o = CanonOpts { levels: vec![12, 14], max_x: 4, queries: true };
    let (x, y) = (canon_store(&f.path, &o).unwrap(), canon_store(&split, &o).unwrap());
    assert!(x == y, "열쇠 ≠ 자리여도 정규화한 답이 같다");
    let v = &x["layout"]["variants"][0];
    assert_eq!((v["key"].as_str(), v["kind"].as_i64(), v["rows"][0]["after"].as_i64(), v["rows"][0]["ord"].as_i64()), (Some(SHELF), Some(SHELF_KIND), Some(-2), Some(-1)));
    assert_eq!(v["shelf"], shelf_want(), "정규화에도 숨긴 구성원 목록이 그대로 실린다");
    assert!(f.k3a > 0 && f.k3b > 0);
}

/// 규격 2 전용 팩(머리 20바이트 + 지문 32바이트 + zlib 본문) — `tests/import.rs`와 같은 꼴.
fn htpack(raw: &Value) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    use std::io::Write;
    let plain = serde_json::to_vec(raw).unwrap();
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(&plain).unwrap();
    let body = encoder.finish().unwrap();
    let mut head = b"HTPACK\r\n".to_vec();
    head.extend_from_slice(&[2, 1, 1, 0]);
    head.extend_from_slice(&(plain.len() as u32).to_le_bytes());
    head.extend_from_slice(&(body.len() as u32).to_le_bytes());
    let mut hash = Sha256::new();
    hash.update(&head);
    hash.update(&body);
    [head, hash.finalize().to_vec(), body].concat()
}

fn shelf_pack() -> Vec<(String, Vec<u8>)> {
    vec![(String::new(), htpack(&json!({"format":"history-timeline-dlc","name":"선반 검사"})))]
}

/// 배치 JSON 3판의 줄 하나(`variant`가 있으면 그 변형에서만 있는 줄).
fn plan_row(variant: &str) -> Value {
    let mut r = json!({"height":120,"bandTop":19,"bandH":100,"dynTop":-1,"leadTop":23,"cabTop":-1,"textTop":60,"lines":1,"railTop":90,"organTop":-1});
    if !variant.is_empty() {
        r["variant"] = json!(variant);
    }
    r
}

/// 선반 변형 하나를 실은 배치(트랙 둘 — 하연 `ha` · 윗물 `hb`). 하연 줄 1의 h는 숨고(이사 −1) 줄 2의 k는 다시 지은 줄 4로 가며,
/// 둘이 떠난 줄 1 · 2는 빠진다(after −2 — `to` 없음). `hidden_track`은 숨는 이사의 트랙 칸 — 줄을 가리키지 않으므로 무엇을 적어도 같은 뜻이어야 한다.
fn shelf_plan(hidden_track: i64) -> Value {
    let y = |n: i64| n * YEAR;
    json!({
        "name": "선반 검사",
        "tracks": [
            {"name":"하연","key":"ha","rows":[plan_row(""), plan_row(""), plan_row(""), plan_row(""), plan_row("shelf:c")]},
            {"name":"윗물","key":"hb","rows":[plan_row("")]}
        ],
        "periods": [
            {"uid":"a","track":0,"row":0,"start":0,"end":y(100),"name":"등불 왕국"},
            {"uid":"h","track":0,"row":1,"start":0,"end":y(100),"name":"숨는 나라"},
            {"uid":"k","track":0,"row":2,"start":0,"end":y(100),"name":"옮기는 나라"},
            {"uid":"f","track":0,"row":3,"start":0,"end":y(100),"name":"그릇 발 나라"},
            {"uid":"b","track":1,"row":0,"start":0,"end":y(100),"name":"윗물국"}
        ],
        "events": [{"uid":"e-h","track":0,"row":1,"start":y(10),"end":y(10),"importance":2,"title":"숨는 나라의 일","body":"","band":"h"}],
        "items": [{"section":59,"track":0,"row":3,"start":0,"end":y(100),"ref":"h","name":"숨긴 구성원","variant":"shelf:c"}],
        "variants": [{"key":"shelf:c","kind":SHELF_KIND,"track":0,"band":"","uid":"c","name":"등불 그릇","notes":"",
            "rows":[{"track":0,"row":1,"after":-2},{"track":0,"row":2,"after":-2},{"track":0,"row":4,"after":0,"new":1},{"track":0,"row":3,"after":4}],
            "moves":[{"kind":1,"ref":"h","track":hidden_track,"row":HIDDEN_ROW},{"kind":1,"ref":"k","track":0,"row":4}],
            "groups":[],"hides":[]}]
    })
}

/// 저장소 표의 정수 열 둘을 차례대로.
fn pairs(s: &Store, sql: &str) -> Vec<(i64, i64)> {
    s.db.prepare(sql).unwrap().query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(|r| r.unwrap()).collect()
}

#[test]
fn 가져온_배치의_숨는_이사와_빠지는_줄과_선반_갈래가_저장소에_그대로_든다() {
    let dir = scratch("shelf-import");
    let target = dir.join("out").join("archive.db");
    let counts = import_layout_value(&shelf_plan(0), &shelf_pack(), &target).unwrap();
    assert_eq!((counts["variants"].as_i64(), counts["variant_rows"].as_i64(), counts["variant_moves"].as_i64()), (Some(1), Some(4), Some(2)));
    let s = Store::open(&target).unwrap();
    let id = |uid: &str| -> i64 { s.db.query_row("SELECT id FROM periods WHERE uid=?1", [uid], |r| r.get(0)).unwrap() };
    let kind: (i64, String) = s.db.query_row("SELECT kind,uid FROM variants WHERE key='shelf:c'", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    assert_eq!(kind, (SHELF_KIND, "c".to_owned()));
    assert_eq!(pairs(&s, "SELECT ref,row FROM variant_moves ORDER BY ref"), vec![(id("h"), HIDDEN_ROW), (id("k"), 4)], "숨는 이사는 −1 그대로");
    let rows: Vec<(i64, i64, i64, i64)> = s.db.prepare("SELECT row,after,ord,is_new FROM variant_rows ORDER BY row").unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).unwrap().map(|r| r.unwrap()).collect();
    assert_eq!(rows, vec![(1, -2, -1, 0), (2, -2, -1, 0), (3, 4, 0, 0), (4, 0, 0, 1)], "빠지는 줄은 after −2 · ord −1(`to` 없음)");
    // 밖으로: layout의 변형 · 쌓는 차례와 타일.
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    let v = &shape["variants"][0];
    assert_eq!((v["key"].as_str(), v["kind"].as_i64()), (Some("shelf:c"), Some(SHELF_KIND)));
    let dropped: Vec<i64> = v["rows"].as_array().unwrap().iter().filter(|r| r["after"] == -2 && r["ord"] == -1).filter_map(|r| r["row"].as_i64()).collect();
    assert_eq!(dropped, vec![1, 2]);
    let on = tile(&s, 0, &["shelf:c"]);
    assert!(!band_ids(&on).contains(&id("h")), "숨은 띠");
    assert!(on.bands.iter().any(|b| b.id as i64 == id("k") && b.row == 4), "다시 지은 줄로 옮긴 띠");
    assert!(on.events.iter().all(|e| on.strings[e.name as usize] != "숨는 나라의 일"), "숨은 띠의 사건");
    let tags: Vec<(u32, i64)> = on.section(59).iter().map(|i| (i.row, i.reference as i64)).collect();
    assert_eq!(tags, vec![(3, id("h"))], "선반의 꼬리표는 숨은 띠를 가리킨 채 제자리");
    assert!(tile(&s, 0, &[]).section(59).is_empty());
}

#[test]
fn 지문과_하위_배치는_숨는_이사를_줄을_가리키는_것으로_세지_않는다() {
    // 숨는 이사의 트랙 칸에 남의 트랙(hb)을 적은 꼴 — 가리키는 줄이 없으므로 hb에 기대지 않아야 한다.
    let plan = shelf_plan(1);
    let whole = prints(&plan).unwrap();
    assert!(whole.tracks["ha"].row_targets.is_empty(), "숨는 이사는 남의 트랙 줄을 가리키지 않는다");
    let keys: BTreeSet<String> = ["ha".to_owned()].into();
    let sub = sub_plan(&plan, &keys).unwrap();
    let v = &sub["variants"][0];
    assert!(v.get("outer").is_none(), "밖으로 옮길 원소가 없다 — 숨는 이사는 하위 배치 안 목록에 남는다");
    assert_eq!(v["moves"].as_array().unwrap().len(), 2);
    assert_eq!((v["moves"][0]["track"].as_str(), v["moves"][0]["row"].as_i64()), (Some("hb"), Some(HIDDEN_ROW)));
    assert_eq!(prints(&sub).unwrap().tracks["ha"].print, whole.tracks["ha"].print, "하위 배치의 지문은 통째 배치의 같은 트랙 지문과 같다");
    // 하위 배치를 통째로 지어도 숨는 이사는 −1로 든다(트랙 칸이 열쇠 글이어도 줄을 찾지 않는다).
    let dir = scratch("shelf-sub");
    let target = dir.join("archive.db");
    import_layout_value(&sub, &shelf_pack(), &target).unwrap();
    let s = Store::open(&target).unwrap();
    let rows: Vec<i64> = pairs(&s, "SELECT row,ref FROM variant_moves ORDER BY row").into_iter().map(|p| p.0).collect();
    assert_eq!(rows, vec![HIDDEN_ROW, 4]);
    // 통째 배치도 같다.
    let full = dir.join("full.db");
    import_layout_value(&plan, &shelf_pack(), &full).unwrap();
    let s = Store::open(&full).unwrap();
    assert_eq!(pairs(&s, "SELECT row,kind FROM variant_moves ORDER BY row"), vec![(HIDDEN_ROW, 1), (4, 1)]);
}

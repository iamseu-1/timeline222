//! 변형(variant) — 소속 펼치기와 대범위 모아 보기를 자료로 얹는 길(계약 2-4절 · 3-2절).
//! 확인하는 것: 변형을 주지 않으면 답이 예전과 같다 · 펼친 소속의 띠 · 칸 · 사건 · 일반 항목이 새 줄로 온다 ·
//! 이사한 띠가 **도착 줄의 묶음 타일**에 실린다 · `rows_near`가 떠난 줄을 비었다고 답한다 · 거르개와 함께 쓸 수 있다 ·
//! 잘못된 변형 이름은 까닭과 함께 실패한다.
use archive_engine::builder::{Builder, CellIn, EventIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::tile::{build_tile, decode, Decoded, TileRequest, SEC_BAND};
use archive_engine::{Result, Store, DAY};
use serde_json::{json, Value};
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

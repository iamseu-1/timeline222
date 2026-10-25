//! 한 벌 P3-18 — 앱이 엔진 답을 받아 다시 가르던 **정적인 셈**을 엔진의 `{"op":"layout"}` 답이 이름 붙은 칸으로 싣는다(계획 P3 과제 18 · 설계 한 장의 길 가).
//! 확인하는 것: 줄 깃발 비트 풀기(옛 저장소의 예외 규칙까지) · 그릇 여백의 머리 · 발 · 매달림 수(갈라지지 않는 값은 −1 셋) ·
//! 변형 줄의 같은 칸 · 그릇 변형의 포개짐 `within` · 트랙의 문화권 자리 `sphere_at`. 원래 값(`fig_wide` · `scope_pad`)은 그대로 남는다.
//! 이름은 모두 가상이다.
use archive_engine::builder::{Builder, RowExtra, RowGeo, TrackIn};
use archive_engine::{Result, Store};
use serde_json::{json, Value};
use std::path::PathBuf;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-layout-static-{}-{name}", std::process::id())); // common::SCRATCH_KINDS의 꼴
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn geo() -> RowGeo {
    RowGeo { height: 60, band_top: 10, band_h: 40, dyn_top: -1, lead_top: -1, cab_top: -1, text_top: 20, text_lines: 1, rail_top: -1, organ_top: -1 }
}

/// 줄 하나의 값(`fig_wide` · `zones` · `scope_pad`)만 다른 줄.
fn row(fig_wide: i64, zones: i64, scope_pad: i64) -> RowExtra {
    RowExtra { fig_wide, zones, scope_pad, ..Default::default() }
}

/// 비트를 모은 `fig_wide`(계약 3-3): 인물 단 · 기간 막대 단 + 1 · 기관 · 집권 · 실권 · 매달린 줄 수 · 솟음 · 그릇 줄 · 칸 셋 · 표시 · 사건.
fn packed(levels: i64, rail: i64, organ: bool, power: bool, real: bool, hang: i64, raised: bool, contained: bool, dynasty: bool, leader: bool, cabinet: bool, carried: bool, events: bool) -> i64 {
    let bit = |on: bool, at: u32| if on { 1 << at } else { 0 };
    levels | ((rail + 1) << 3) | bit(organ, 6) | bit(power, 7) | bit(real, 8) | (hang << 9) | bit(raised, 14) | bit(contained, 15)
        | bit(dynasty, 16) | bit(leader, 17) | bit(cabinet, 18) | bit(carried, 19) | bit(events, 20)
}

struct Fixture {
    path: PathBuf,
    _dir: PathBuf,
    s1: i64,
    s2: i64,
    s3: i64,
    s4: i64,
    host: i64,
}

/// 트랙 셋(물결 땅 — 문화권 둘째 · 너른 들 — 문화권 없음 · 바람 언덕 — 모르는 문화권) · 줄 열 · 그릇 변형 넷 · 소속 변형 하나.
fn build(name: &str) -> Result<Fixture> {
    let dir = scratch(name);
    let path = dir.join("archive.db");
    let mut b = Builder::create(&path)?;
    let pack = b.pack("정적 칸 검사", None)?;
    let river = b.track_full(&TrackIn { pack, name: "물결 땅", color: 0xa0_bcc5, dynasty: 1, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "ls-river" })?;
    let grass = b.track_full(&TrackIn { pack, name: "너른 들", color: 0x9d_bea8, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "ls-grass" })?;
    let wind = b.track_full(&TrackIn { pack, name: "바람 언덕", color: 0xc2_7a45, dynasty: 0, leader: 0, cabinet: 0, organ: 0, rail_levels: 3, key: "ls-wind" })?;
    b.track_sphere(river, "east-river")?;
    b.track_sphere(wind, "nowhere")?;
    b.add_meta("spheres", json!([{"id":"grass-sea","name":"풀바다 문화권","order":1,"count":0,"default":false},
        {"id":"east-river","name":"물가 문화권","order":2,"count":1,"default":true}]).to_string());
    // 변형은 줄보다 먼저(줄의 `variant`가 가리킨다) — 여기서는 모두 기본 줄이라 차례만 지킨다.
    let s1 = b.variant("scope:s1", 2, river, 0, "s1", "작은 그릇", "")?;
    let s2 = b.variant("scope:s2", 2, river, 0, "s2", "큰 그릇", "")?;
    let s3 = b.variant("scope:s3", 2, river, 0, "s3", "옆 그릇", "")?;
    let s4 = b.variant("scope:s4", 2, grass, 0, "s4", "다른 트랙의 그릇", "")?;
    let host = b.variant("host:h1", 1, river, 0, "", "은륜 제국", "")?;
    // 물결 땅의 줄 여섯 — 줄 값이 하나씩 다르다.
    let river_rows = [
        row(2, 0, 0),                                                                                        // 0: 옛 저장소 꼴(비트 3 ~ 5가 0) — 인물 단만
        row(packed(3, 2, true, true, true, 5, true, true, true, false, true, true, false), 2, 16),          // 1: 모두 켬 · 매달린 줄 5는 zones 2로 잘림 · 사건 없음 · 머리 하나
        row(packed(1, 0, false, false, false, 0, false, false, false, true, false, true, true), 0, 22),     // 2: 막대 0단 실림 · 지도자 칸 · 사건 있음 · 머리 하나 + 발
        row(packed(0, 1, false, false, false, 3, false, false, false, false, false, false, false), 3, -4),  // 3: 표시 없음(사건 참) · 매달림 3 · 매달린 머리
        row(1, 0, 7),                                                                                        // 4: 갈라지지 않는 여백 7
        row(0, 0, 38),                                                                                       // 5: 머리 둘 + 발
    ];
    for r in &river_rows {
        b.row_full(river, &geo(), r)?;
    }
    for pad in [6, 2, 32, 10] {
        b.row_full(grass, &geo(), &row(0, 0, pad))?; // 6 ~ 9: 발만 · 매달린 머리 + 발 · 머리 둘 · 갈라지지 않음(10)
    }
    b.row_full(wind, &geo(), &row(0, 0, 0))?; // 10
    // 그릇 변형의 묶음 줄: s1 ⊂ s2 · s3 ⊂ s2 · s1 ∥ s3 · s4는 다른 트랙(줄 수는 s2와 같아도 품지 않는다).
    b.variant_group(s1, "s1:a", 0, "작은 그릇", 0xa0_bcc5, 2, &[0, 1])?;
    b.variant_group(s2, "s2:a", 0, "큰 그릇", 0xa0_bcc5, 2, &[0, 1])?;
    b.variant_group(s2, "s2:b", 0, "큰 그릇 둘째", 0xa0_bcc5, 2, &[2, 3])?;
    b.variant_group(s3, "s3:a", 0, "옆 그릇", 0xa0_bcc5, 2, &[2, 3])?;
    b.variant_group(s4, "s4:a", 0, "다른 트랙의 그릇", 0x9d_bea8, 2, &[6, 7, 8, 9])?;
    b.variant_row(s2, 0, -1, 0, false, 22, 1)?; // 변형이 덮어쓰는 여백: 머리 하나 + 발
    b.variant_row(s2, 2, 1, 1, false, 7, 0)?; // 갈라지지 않는 값
    b.finalize(&[])?;
    Ok(Fixture { path, _dir: dir, s1, s2, s3, s4, host })
}

fn rows_of(layout: &Value, track: usize) -> &Vec<Value> {
    layout["tracks"][track]["rows"].as_array().unwrap()
}

fn flags(r: &Value) -> Vec<i64> {
    let g = |k: &str| r[k].as_i64().unwrap_or_else(|| panic!("줄 답에 {k}가 없습니다: {r}"));
    // 차례: 인물 단 · 막대 단 · 기관 · 집권 · 실권 · 매달림 · 솟음 · 그릇 줄 · 표시 · 왕조 · 지도자 · 내각 · 사건
    ["fig_wide_levels", "rail", "organ", "power", "real", "hang", "raised", "contained", "cell_rows", "dynasty", "leader", "cabinet", "events"].iter().map(|k| g(k)).collect()
}

fn split(r: &Value) -> Option<(i64, i64, i64)> {
    match (r.get("scope_head"), r.get("scope_foot"), r.get("scope_hung")) {
        (Some(h), Some(f), Some(u)) => Some((h.as_i64().unwrap(), f.as_i64().unwrap(), u.as_i64().unwrap())).filter(|t| *t != (-1, -1, -1)),
        other => panic!("머리 · 발 · 매달림은 셋이 늘 함께 있어야 합니다: {other:?}"),
    }
}

#[test]
fn row_flags_are_unpacked_like_the_app_did() {
    let f = build("flags").unwrap();
    let s = Store::open(&f.path).unwrap();
    let layout = s.layout().unwrap();
    let rows = rows_of(&layout, 0);
    assert_eq!(rows.len(), 6);
    // 원래 정수는 그대로 남는다(계약 3-3 · 6-5).
    assert_eq!(rows[0]["fig_wide"], json!(2));
    assert_eq!(rows[1]["fig_wide"], json!(packed(3, 2, true, true, true, 5, true, true, true, false, true, true, false)));
    // 0: 옛 저장소 꼴 — 인물 단은 정수 그대로, 막대 단 −1, 나머지 0, 사건은 참(표시 없음).
    assert_eq!(flags(&rows[0]), vec![2, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
    // 1: 모두 켬 — 매달린 줄 5는 zones 2로 잘리고, 표시가 섰는데 사건 비트가 없어 사건 0.
    assert_eq!(flags(&rows[1]), vec![3, 2, 1, 1, 1, 2, 1, 1, 1, 1, 0, 1, 0]);
    // 2: 막대 0단이 '실린' 줄(비트 3 ~ 5 = 1) — 지도자 칸 · 표시 · 사건.
    assert_eq!(flags(&rows[2]), vec![1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1]);
    // 3: 표시 없음이라 사건은 참 · 매달림 3(zones 3 안).
    assert_eq!(flags(&rows[3]), vec![0, 1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 1]);
    // 다른 트랙에도 같은 칸이 있다.
    assert_eq!(flags(&rows_of(&layout, 2)[0]), vec![0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
}

#[test]
fn scope_pad_is_split_into_head_foot_and_hung() {
    let f = build("split").unwrap();
    let s = Store::open(&f.path).unwrap();
    let layout = s.layout().unwrap();
    let river = rows_of(&layout, 0);
    let grass = rows_of(&layout, 1);
    // (머리 수 · 발 · 매달린 머리) — 앱 `_scopePadOf`의 가름 그대로: 발 6을 먼저 떼어 보고, 머리 16의 배수 · 매달린 머리 −4.
    assert_eq!(split(&river[0]), Some((0, 0, 0)), "0은 셋 다 0");
    assert_eq!(split(&river[1]), Some((1, 0, 0)), "16 = 머리 하나");
    assert_eq!(split(&river[2]), Some((1, 1, 0)), "22 = 머리 하나 + 발");
    assert_eq!(split(&river[3]), Some((0, 0, 1)), "−4 = 매달린 머리");
    assert_eq!(split(&river[4]), None, "7은 갈라지지 않는다 — −1 셋");
    assert_eq!(split(&river[5]), Some((2, 1, 0)), "38 = 머리 둘 + 발");
    assert_eq!(split(&grass[0]), Some((0, 1, 0)), "6 = 발만");
    assert_eq!(split(&grass[1]), Some((0, 1, 1)), "2 = 매달린 머리 + 발");
    assert_eq!(split(&grass[2]), Some((2, 0, 0)), "32 = 머리 둘");
    assert_eq!(split(&grass[3]), None, "10은 갈라지지 않는다");
    for r in river.iter().chain(grass) {
        assert!(r.get("scope_pad").is_some(), "원래 px 값은 그대로 남는다");
    }
}

#[test]
fn variant_rows_carry_the_same_split_and_scopes_tell_what_contains_them() {
    let f = build("variants").unwrap();
    let s = Store::open(&f.path).unwrap();
    let layout = s.layout().unwrap();
    let variants = layout["variants"].as_array().unwrap();
    let by_id = |id: i64| variants.iter().find(|v| v["id"] == json!(id)).unwrap_or_else(|| panic!("변형 {id}"));
    let s2 = by_id(f.s2);
    let rows = s2["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(split(&rows[0]), Some((1, 1, 0)), "변형 줄의 22 = 머리 하나 + 발");
    assert_eq!(split(&rows[1]), None, "변형 줄의 7은 갈라지지 않는다");
    assert_eq!(rows[0]["scope_pad"], json!(22), "원래 값은 그대로");
    // 포개짐: 제 줄을 모두 품고 더 큰 그릇만, 같은 트랙에서만.
    assert_eq!(by_id(f.s1)["within"], json!([f.s2]));
    assert_eq!(by_id(f.s3)["within"], json!([f.s2]));
    assert_eq!(by_id(f.s2)["within"], json!([]));
    assert_eq!(by_id(f.s4)["within"], json!([]), "다른 트랙의 그릇은 품지 않는다");
    assert!(by_id(f.host).get("within").is_none(), "그릇이 아닌 변형에는 within이 없다");
}

#[test]
fn tracks_know_their_sphere_position() {
    let f = build("spheres").unwrap();
    let s = Store::open(&f.path).unwrap();
    let layout = s.layout().unwrap();
    let tracks = layout["tracks"].as_array().unwrap();
    assert_eq!(tracks[0]["sphere_at"], json!(1), "물결 땅은 spheres 목록의 둘째");
    assert_eq!(tracks[1]["sphere_at"], json!(-1), "문화권 없는 트랙");
    assert_eq!(tracks[2]["sphere_at"], json!(-1), "모르는 문화권 id");
    assert_eq!(layout["spheres"].as_array().unwrap().len(), 2);
}

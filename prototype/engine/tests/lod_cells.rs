//! 성긴 단계의 칸 추림(계약 5절)과 개수 알약의 분류 비율 열 `cats`.
//!
//! 추림의 규칙은 띠 안의 칸 층(`app/lib/scene/paint/strips.dart`)에서 읽었다. 층은
//! ① `p.r - p.l < minW`인 칸을 건너뛰고 앞 칸을 늘려 빈틈을 메우며, ② 띠 상자가 좁아 `hi - lo < 1`이면 그 띠의 칸을 하나도 그리지 않는다.
//! 화면은 통 하나가 16~64px(경계에서 8% 버팀)이 되는 단계를 고르므로, **한 단계가 쓰이는 동안 통은 최대 69.12px**이다 —
//! 그 가장 확대한 쪽에서도 그려지지 않는 것만 빼야 그림이 바뀌지 않는다.
use archive_engine::builder::{Builder, CellIn, EventIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::levels::{bucket_minutes, cell_min_span, host_min_span, lod_of, tile_of, BUCKET_MAX_PX};
use archive_engine::tile::{build_tile, decode, Decoded, TileRequest};
use archive_engine::Store;
use serde_json::json;
use std::path::PathBuf;

const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: -1, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-lod-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    path
}

// ── 1. 문턱을 셈하는 식 ──────────────────────────────────────────────────────────────────────

#[test]
fn 추림_문턱은_가장_확대한_쪽에서_재어_보수적이다() {
    for level in 0..=14usize {
        let bucket = bucket_minutes(level) as f64;
        // 문턱보다 한 분 짧은 것은 가장 확대해도 그 px에 못 미친다.
        let cell = cell_min_span(level);
        assert!((cell - 1) as f64 * BUCKET_MAX_PX / bucket < 1.0, "단계 {level}: 칸 문턱 {cell}");
        let host = host_min_span(level);
        assert!((host - 1) as f64 * BUCKET_MAX_PX / bucket < 9.0, "단계 {level}: 띠 문턱 {host}");
        assert!(cell >= 1 && host >= cell);
    }
}

#[test]
fn 칸_문턱은_이미_lod가_거르는_것보다_너그럽다() {
    // `lod_of`가 L단계에 싣는 가장 짧은 칸은 `통/8`이고, 추림 문턱은 `통/69.12`다 —
    // 그래서 **칸 문턱만으로는 하나도 빠지지 않는다**(층이 가장 확대했을 때 그리는 칸을 지우지 않는다는 뜻).
    // 단계 0~2는 통이 1 · 4 · 16분이라 '통/8'이 0이 되어 견줄 것이 없다.
    for level in 3..=14usize {
        let shortest = bucket_minutes(level) / 8;
        assert_eq!(lod_of(shortest), level as i64, "단계 {level}");
        assert!(shortest >= cell_min_span(level), "단계 {level}: 가장 짧은 칸 {shortest} · 문턱 {}", cell_min_span(level));
    }
}

// ── 2. 타일에서 빠지는 것 ────────────────────────────────────────────────────────────────────

/// 좁은 띠 하나와 넉넉한 띠 하나, 띠마다 제 기간을 채우는 지도자 칸 하나.
fn build_bands(path: &PathBuf) -> (i64, i64, i64, i64) {
    let mut b = Builder::create(path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    let track = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "north" }).unwrap();
    let row = b.row_full(track, &GEO, &RowExtra::default()).unwrap();
    // 단계 8의 통은 65,536분이다. 좁은 띠는 8,300분 — `lod_of`는 8단계에 싣지만(통/8 = 8,192) 띠 상자가 9px이 안 된다.
    let narrow = b.period_full(&PeriodIn { pack, row, start: 0, end: 8_299, fuzzy: 0, color: 0xa0bcc5, name: "좁은 띠", look: 0, tag: "", sub: 0, uid: "band-narrow", variant: 0, form: 0 }).unwrap();
    let wide = b.period_full(&PeriodIn { pack, row, start: 100_000, end: 300_000, fuzzy: 0, color: 0x9dbea8, name: "넉넉한 띠", look: 0, tag: "", sub: 0, uid: "band-wide", variant: 0, form: 0 }).unwrap();
    let mut cells = Vec::new();
    for (band, start, end) in [(narrow, 0, 8_299), (wide, 100_000, 300_000)] {
        cells.push(b.cell_full(&CellIn { period: band, kind: 1, start, end, name: "1대 가람", lane: 0, style: 0, color: 0, variant: 0 }).unwrap());
    }
    b.finalize(&[("seed", "추림".to_owned())]).unwrap();
    (narrow, wide, cells[0], cells[1])
}

fn tile_at(store: &Store, level: usize, minute: i64) -> Decoded {
    let req = TileRequest::plain(level, tile_of(minute, level), 0, vec![1]);
    decode(&build_tile(store, &req).unwrap()).unwrap()
}

#[test]
fn 띠가_좁아_칸을_하나도_그릴_수_없으면_그_칸은_타일에서_빠진다() {
    let path = scratch("bands");
    let (narrow, wide, narrow_cell, wide_cell) = build_bands(&path);
    let store = Store::open(&path).unwrap();
    // 단계 8: 좁은 띠는 가장 확대해도 8.75px이라 칸을 그릴 자리가 없다(9px 문턱).
    assert!(host_min_span(8) > 8_300 && host_min_span(8) <= 8_600, "띠 문턱 {}", host_min_span(8));
    let coarse = tile_at(&store, 8, 0);
    assert!(coarse.bands.iter().any(|b| b.id == narrow as u32), "띠 자체는 그대로 실린다");
    assert!(!coarse.cells.iter().any(|c| c.id == narrow_cell as u32), "좁은 띠의 칸은 빠진다");
    // 단계 7: 같은 띠가 35px이라 칸이 그대로 실린다 — 가는 단계는 예전과 같다.
    let fine = tile_at(&store, 7, 0);
    assert!(fine.cells.iter().any(|c| c.id == narrow_cell as u32), "가는 단계에서는 그대로");
    // 넉넉한 띠의 칸은 그 띠가 실리는 어느 단계에서도 빠지지 않는다.
    for level in 0..=lod_of(200_000) as usize {
        let t = tile_at(&store, level, 200_000);
        assert!(t.bands.iter().any(|b| b.id == wide as u32), "단계 {level}: 넉넉한 띠");
        assert!(t.cells.iter().any(|c| c.id == wide_cell as u32), "단계 {level}: 넉넉한 띠의 칸이 빠졌다");
    }
}

// ── 3. 개수 알약의 분류 비율 ─────────────────────────────────────────────────────────────────

/// 같은 날에 몰린 사건 열넷 — 분류 0이 열, 1이 셋, 분류 없음이 하나.
fn build_pills(path: &PathBuf) -> i64 {
    let mut b = Builder::create(path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    for (ord, (key, name, color)) in [("govern", "다스림", 0x8f7fb0u32), ("build", "지음", 0x6f9a86)].iter().enumerate() {
        b.category(pack, ord as i64, key, name, *color).unwrap();
    }
    let track = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "north" }).unwrap();
    let row = b.row_full(track, &GEO, &RowExtra::default()).unwrap();
    for i in 0..14i64 {
        // 분류 번호는 look의 아래 8비트다. 255는 '분류 없음'이라 비율에 넣지 않는다.
        let cat = if i < 10 { 0 } else if i < 13 { 1 } else { 255 };
        b.event(&EventIn { pack, lane: row, start: Some(i), end: Some(i), lo: None, hi: None, importance: 1,
            title: "가상 사건", body: "검사 본문", source: None, raw: None, look: cat, label: "", rail: 0, uid: "", band: 0, variant: 0 }).unwrap();
    }
    b.finalize(&[("seed", "알약".to_owned())]).unwrap();
    row
}

fn cats_of(t: &Decoded) -> Vec<String> {
    t.pills.iter().map(|p| t.strings.get(p.cats as usize).cloned().unwrap_or_default()).collect()
}

#[test]
fn 알약은_통_전체의_분류별_수를_싣는다() {
    let path = scratch("pills");
    build_pills(&path);
    let store = Store::open(&path).unwrap();
    // 미리 셈해 둔 요약을 읽는 단계(8 이상)와 그 자리에서 다시 세는 단계(8 미만)가 같은 답을 준다.
    for level in [9usize, 8, 7, 4] {
        let t = tile_at(&store, level, 0);
        assert_eq!(t.pills.len(), 1, "단계 {level}");
        assert_eq!(cats_of(&t), vec!["0:10,1:3".to_owned()], "단계 {level}");
        // 알약에 적히는 수는 대표 넷을 뺀 나머지이고, 분류별 수는 통 전체를 센 값이다.
        assert_eq!(t.pills[0].count, 10);
    }
}

#[test]
fn 거르개를_걸면_분류_비율도_거른_뒤의_수다() {
    let path = scratch("pills-filter");
    build_pills(&path);
    let store = Store::open(&path).unwrap();
    let filter = store.filter_of(&json!({"filter":{"cats_off":[1]}})).unwrap();
    let req = TileRequest { level: 9, x: 0, chunk: 0, packs: vec![1], filter, variants: None };
    let t = decode(&build_tile(&store, &req).unwrap()).unwrap();
    assert_eq!(cats_of(&t), vec!["0:10".to_owned()]);
}

#[test]
fn 알약의_열이_늘어도_옛_열의_자리는_그대로다() {
    let path = scratch("pills-columns");
    build_pills(&path);
    let store = Store::open(&path).unwrap();
    let bytes = build_tile(&store, &TileRequest::plain(9, 0, 0, vec![1])).unwrap();
    let t = decode(&bytes).unwrap();
    // 다시 부호화해도 같은 바이트여야 한다(구역 표의 열 수까지).
    assert_eq!(archive_engine::tile::encode(&t), bytes);
    assert_eq!(archive_engine::tile::PILL_COLUMNS, 5);
    assert_eq!(t.pills[0].row, 0);
    // 실을 분류 비율이 하나도 없으면 그 열을 싣지 않는다 — 옛 저장소의 타일은 2판과 바이트까지 같다.
    let mut bare = decode(&bytes).unwrap();
    for p in &mut bare.pills {
        p.cats = u32::MAX;
    }
    assert!(archive_engine::tile::encode(&bare).len() < bytes.len());
}

// ── 4. 시험용 손잡이 `ARCHIVE_CELL_LOD`(계약 5-3절) ───────────────────────────────────────────
//
// 값은 판이 서는 동안 한 번만 읽으므로, 검사가 같은 판 안에서 두 값을 견줄 수 없다 —
// 그래서 **진짜 도구(`archive-tool`)를 다른 환경 변수로 두 번 띄워** 실제로 만들어진 타일을 맞댄다.

/// 단계 8(통 65,536분)에 칸 둘: 통/8짜리(기본 8에서만 실린다)와 통/4짜리(나눗수 4에서도 실린다).
fn build_knob(path: &PathBuf) -> (i64, i64) {
    let mut b = Builder::create(path).unwrap();
    let pack = b.pack("검사용 자료집", None).unwrap();
    let track = b.track_full(&TrackIn { pack, name: "윗물", color: 0xc8b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "north" }).unwrap();
    let row = b.row_full(track, &GEO, &RowExtra::default()).unwrap();
    let band = b.period_full(&PeriodIn { pack, row, start: 0, end: 200_000, fuzzy: 0, color: 0xa0bcc5, name: "넉넉한 띠", look: 0, tag: "", sub: 0, uid: "band-knob", variant: 0, form: 0 }).unwrap();
    let bucket = bucket_minutes(8);
    let short = b.cell_full(&CellIn { period: band, kind: 1, start: 0, end: bucket / 8, name: "짧은 칸", lane: 0, style: 0, color: 0, variant: 0 }).unwrap();
    let long = b.cell_full(&CellIn { period: band, kind: 1, start: 100_000, end: 100_000 + bucket / 4, name: "긴 칸", lane: 0, style: 0, color: 0, variant: 0 }).unwrap();
    b.finalize(&[("seed", "손잡이".to_owned())]).unwrap();
    (short, long)
}

/// `archive-tool tile`을 한 번 띄워 만들어진 타일 바이트를 돌려준다. `knob`이 있으면 그 값으로 환경 변수를 둔다.
fn tile_by_tool(db: &PathBuf, out: &PathBuf, knob: Option<&str>) -> Vec<u8> {
    let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_archive-tool"));
    command.args([
        "tile",
        db.to_str().unwrap(),
        &json!({"level":8,"x":tile_of(0, 8),"chunk":0,"packs":[1]}).to_string(),
        out.to_str().unwrap(),
    ]);
    match knob {
        Some(value) => command.env("ARCHIVE_CELL_LOD", value),
        None => command.env_remove("ARCHIVE_CELL_LOD"),
    };
    let done = command.output().expect("archive-tool을 띄우지 못했다");
    assert!(done.status.success(), "archive-tool 실패: {}", String::from_utf8_lossy(&done.stderr));
    std::fs::read(out).unwrap()
}

#[test]
fn 손잡이를_두지_않은_타일은_바이트까지_예전과_같다() {
    let path = scratch("knob-default");
    let (short, long) = build_knob(&path);
    let store = Store::open(&path).unwrap();
    let mine = build_tile(&store, &TileRequest::plain(8, tile_of(0, 8), 0, vec![1])).unwrap();
    let out = std::env::temp_dir().join(format!("archive-lod-{}-knob-default.bin", std::process::id()));
    assert_eq!(tile_by_tool(&path, &out, None), mine, "손잡이가 없으면 도구가 만든 타일도 같은 바이트다");
    let t = decode(&mine).unwrap();
    assert_eq!(t.cell_lod, 0, "기본 8이면 머리의 예약 낱말에 아무것도 찍지 않는다");
    let ids: Vec<u32> = t.cells.iter().map(|c| c.id).collect();
    assert!(ids.contains(&(short as u32)) && ids.contains(&(long as u32)), "기본에서는 칸 둘이 모두 실린다: {ids:?}");
    let _ = std::fs::remove_file(&out);
}

#[test]
fn 나눗수를_줄이면_성긴_단계의_짧은_칸이_실제로_빠진다() {
    let path = scratch("knob-four");
    let (short, long) = build_knob(&path);
    let out = std::env::temp_dir().join(format!("archive-lod-{}-knob-four.bin", std::process::id()));
    let bytes = tile_by_tool(&path, &out, Some("4"));
    let t = decode(&bytes).unwrap();
    let ids: Vec<u32> = t.cells.iter().map(|c| c.id).collect();
    assert!(!ids.contains(&(short as u32)), "통/8짜리 칸은 나눗수 4에서 빠진다: {ids:?}");
    assert!(ids.contains(&(long as u32)), "통/4짜리 칸은 그대로 실린다: {ids:?}");
    // 그 타일은 기본 판과 다른 자료라 머리에 나눗수가 찍힌다(받아 둔 타일과 섞이면 여기서 드러난다).
    assert_eq!(t.cell_lod, 4);
    // 띠는 칸의 손잡이에 걸리지 않는다 — 바뀌는 것은 띠 안의 칸뿐이다.
    assert_eq!(t.bands.len(), 1);
    let _ = std::fs::remove_file(&out);
}

#[test]
fn 읽을_수_없는_손잡이는_기본값으로_둔다() {
    let path = scratch("knob-bad");
    build_knob(&path);
    let store = Store::open(&path).unwrap();
    let mine = build_tile(&store, &TileRequest::plain(8, tile_of(0, 8), 0, vec![1])).unwrap();
    let out = std::env::temp_dir().join(format!("archive-lod-{}-knob-bad.bin", std::process::id()));
    assert_eq!(tile_by_tool(&path, &out, Some("여덟")), mine, "글자는 기본 8로 읽는다");
    assert_eq!(tile_by_tool(&path, &out, Some("0")), tile_by_tool(&path, &out, Some("1")), "0은 1로 자른다");
    let _ = std::fs::remove_file(&out);
}

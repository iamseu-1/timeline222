//! 타일: 어느 단계에서 모아도 사건이 빠지거나 두 번 세어지지 않아야 하고, 경계에 걸친 띠는 잘린 쪽이 표시되어야 한다.
//! 2판은 구역 표를 둔다 — 모르는 구역 · 모자란 열이 와도 읽기가 깨지지 않아야 한다(계약 5절).
mod common;
use archive_engine::builder::{Builder, EventIn, ItemIn, RowGeo, TrackIn};
use archive_engine::levels::{bucket_of, tile_of, tile_range, LEVEL_MAX};
use archive_engine::tile::{build_tile, decode, encode, Decoded, TileRequest, BAND_COLUMNS, BAR, CELL_COLUMNS, CLIP_LEFT, CLIP_RIGHT, COUNTED,
    EVENT_CLIP_LEFT, EVENT_CLIP_RIGHT, EVENT_COLUMNS, FUZZY_END, FUZZY_START, HEADER, ITEM_COLUMNS, MAGIC, PILL_COLUMNS, SECTION_ENTRY_WORDS, VERSION};
use archive_engine::{Store, DAY};
use common::{build, scratch, Sample};
use std::collections::{BTreeMap, BTreeSet};

fn tile(store: &Store, level: usize, x: i64, packs: &[i64]) -> Decoded {
    decode(&build_tile(store, &TileRequest { level, x, chunk: 0, packs: packs.to_vec(), filter: None, variants: None }).unwrap()).unwrap()
}

/// 사건이 있을 수 있는 모든 타일을 모은다(긴 기간 900일까지 넉넉히).
fn sweep(store: &Store, level: usize, packs: &[i64]) -> Vec<Decoded> {
    (tile_of(-460 * DAY, level)..=tile_of(1360 * DAY, level)).map(|x| tile(store, level, x, packs)).collect()
}

fn counted(tiles: &[Decoded]) -> i64 {
    tiles.iter().map(|t| t.events.iter().filter(|e| e.bits & COUNTED != 0).count() as i64 + t.pills.iter().map(|p| p.count as i64).sum::<i64>()).sum()
}

/// 머리와 구역 표를 손으로 읽는다(화면 쪽 읽기와 같은 산수인지 보려고).
fn table_of(bytes: &[u8]) -> Vec<(u32, u32, u32, u32)> {
    let word = |at: usize| u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap());
    (0..word(40) as usize).map(|i| {
        let at = HEADER + i * SECTION_ENTRY_WORDS * 4;
        (word(at), word(at + 4), word(at + 8), word(at + 12))
    }).collect()
}

#[test]
fn 어느_단계에서_모아도_개수의_합이_날짜_있는_사건_수와_같고_대표에_중복이_없다() {
    let path = scratch("tiles-sum");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    let dated = samples.iter().filter(|e| e.start.is_some()).count() as i64;
    for level in 0..=LEVEL_MAX {
        let tiles = sweep(&s, level, &[1, 2]);
        assert_eq!(counted(&tiles), dated, "단계 {level}");
        let mut seen = BTreeSet::new();
        for e in tiles.iter().flat_map(|t| &t.events).filter(|e| e.bits & COUNTED != 0) {
            assert!(seen.insert(e.id), "단계 {level}: 대표 {}번이 두 번", e.id);
        }
    }
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 통마다_대표는_중요도_큰_순_번호_작은_순의_앞_넷이다() {
    let path = scratch("tiles-reps");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    for level in [0usize, 3, 7, 8, 9, 12] {
        let mut wanted: BTreeMap<(i64, i64), Vec<(i64, i64)>> = BTreeMap::new();
        for e in samples.iter().filter(|e| e.start.is_some()) {
            wanted.entry((e.lane, bucket_of(e.start.unwrap(), level))).or_default().push((-e.importance, e.id));
        }
        let mut actual: BTreeMap<(i64, i64), Vec<(i64, i64)>> = BTreeMap::new();
        let mut rest: BTreeMap<(i64, i64), i64> = BTreeMap::new();
        for t in sweep(&s, level, &[1, 2]) {
            for e in t.events.iter().filter(|e| e.bits & COUNTED != 0) {
                let sample: &Sample = &samples[(e.id - 1) as usize];
                actual.entry((e.row as i64, bucket_of(sample.start.unwrap(), level))).or_default().push((-((e.bits & 3) as i64), e.id as i64));
            }
            for p in &t.pills {
                *rest.entry((p.row as i64, bucket_of(t.origin + p.x0 as i64, level))).or_default() += p.count as i64;
            }
        }
        for (key, list) in wanted.iter_mut() {
            list.sort();
            let mut got = actual.remove(key).unwrap_or_default();
            got.sort();
            assert_eq!(got, list[..list.len().min(4)].to_vec(), "단계 {level} 줄 {} 통 {}", key.0, key.1);
            assert_eq!(rest.remove(key).unwrap_or(0), (list.len() as i64 - 4).max(0), "단계 {level}의 나머지 개수");
        }
        assert!(actual.is_empty() && rest.is_empty(), "단계 {level}: 없어야 할 칸");
    }
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 자료집을_끄면_그_자료집의_사건과_띠와_칸이_빠진다() {
    let path = scratch("tiles-packs");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    let only_first = samples.iter().filter(|e| e.start.is_some() && e.pack == 1).count() as i64;
    for level in [2usize, 8, 11] {
        let tiles = sweep(&s, level, &[1]);
        assert_eq!(counted(&tiles), only_first, "단계 {level}");
        for e in tiles.iter().flat_map(|t| &t.events) {
            assert_eq!(samples[(e.id - 1) as usize].pack, 1);
        }
    }
    // 첫 자료집의 띠는 0~3줄에만 있다.
    let t = tile(&s, 8, 0, &[1]);
    assert!(!t.bands.is_empty() && t.bands.iter().all(|b| b.row < 4));
    assert!(!t.cells.is_empty() && t.cells.iter().all(|c| c.row < 4));
    assert!(tile(&s, 8, 0, &[]).bands.is_empty(), "아무 자료집도 켜지 않으면 빈 타일");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 경계를_가로지르는_띠는_양쪽_타일에_잘린_표시와_함께_하나씩_있다() {
    let path = scratch("tiles-clip");
    build(&path);
    let s = Store::open(&path).unwrap();
    let (left, right) = (tile(&s, 8, -1, &[1, 2]), tile(&s, 8, 0, &[1, 2]));
    assert_eq!((left.level, left.x, left.chunk), (8, -1, 0));
    assert_eq!((left.origin, left.span), (tile_range(8, -1).0, 16_777_216));
    let name = "별여울 0줄 2번 띠";
    let l: Vec<_> = left.bands.iter().filter(|b| left.strings[b.name as usize] == name).collect();
    let r: Vec<_> = right.bands.iter().filter(|b| right.strings[b.name as usize] == name).collect();
    assert_eq!((l.len(), r.len()), (1, 1));
    assert_eq!(l[0].flags & (CLIP_LEFT | CLIP_RIGHT), CLIP_RIGHT);
    assert_eq!(r[0].flags & (CLIP_LEFT | CLIP_RIGHT), CLIP_LEFT);
    assert_eq!(l[0].x1, left.span as f32, "잘린 오른쪽 끝은 타일의 끝");
    assert_eq!(r[0].x0, 0.0);
    assert_eq!(l[0].x0, (left.span - 99 * DAY) as f32);
    assert_eq!(r[0].x1, (201 * DAY) as f32, "끝은 양 끝 포함이라 그리는 오른쪽 끝은 다음 분");
    assert_eq!(l[0].id, r[0].id);
    assert_eq!(l[0].color, 0xa0bcc5 + 1);
    // 3판의 값도 양쪽에 같이 온다.
    assert_eq!((l[0].look, l[0].sub), (0x21, 0));
    assert_eq!(left.strings[l[0].tag as usize], "전해 오는 이야기");
    assert_eq!((r[0].look, right.strings[r[0].tag as usize].as_str()), (0x21, "전해 오는 이야기"));
    // 안쪽의 띠는 한 번만, 잘림 없이. 첫 줄의 첫 띠는 시작 미정, 끝 띠는 끝 미정.
    let first: Vec<_> = left.bands.iter().filter(|b| left.strings[b.name as usize] == "별여울 0줄 1번 띠").collect();
    assert_eq!(first.len(), 1);
    assert_eq!(first[0].flags, FUZZY_START);
    assert!(!right.bands.iter().any(|b| right.strings[b.name as usize] == "별여울 0줄 1번 띠"));
    let last: Vec<_> = right.bands.iter().filter(|b| right.strings[b.name as usize] == "별여울 0줄 3번 띠").collect();
    assert_eq!(last[0].flags, FUZZY_END);
    assert_eq!(last[0].sub, 3);
    // 칸도 같은 규칙: 가운데 띠의 첫 지도자 칸(−99일 ~ 중간)은 경계를 가로지른다.
    assert!(left.cells.iter().any(|c| c.flags & CLIP_RIGHT != 0) && right.cells.iter().any(|c| c.flags & CLIP_LEFT != 0));
    assert!(left.cells.iter().all(|c| c.kind == 1 || c.kind == 2));
    let cabinet = left.cells.iter().find(|c| c.kind == 2).unwrap();
    assert_eq!((cabinet.lane, cabinet.style, cabinet.color), (1, 4, 0xd1a9b9), "칸의 단 · 모양 · 제 색");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 긴_기간_사건은_볼_만큼_긴_단계에서만_막대로_나온다() {
    let path = scratch("tiles-bars");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    // 900일짜리(11의 배수)는 가늘기 등급 11: 단계 8~11에서는 막대, 12부터는 점이나 알약 속.
    for level in [8usize, 11] {
        let bars: BTreeSet<u32> = sweep(&s, level, &[1, 2]).iter().flat_map(|t| t.events.iter().filter(|e| e.bits & BAR != 0).map(|e| e.id)).collect();
        let wanted: BTreeSet<u32> = samples.iter().filter(|e| e.start.is_some() && e.id % 11 == 0).map(|e| e.id as u32).collect();
        assert_eq!(bars, wanted, "단계 {level}");
    }
    assert!(sweep(&s, 12, &[1, 2]).iter().all(|t| t.events.iter().all(|e| e.bits & BAR == 0)));
    // 막대가 타일 둘에 걸치면 시작 통이 있는 쪽에서만 센다.
    let tiles = sweep(&s, 9, &[1, 2]);
    for id in tiles.iter().flat_map(|t| &t.events).filter(|e| e.bits & BAR != 0).map(|e| e.id).collect::<BTreeSet<_>>() {
        let pieces: Vec<_> = tiles.iter().flat_map(|t| &t.events).filter(|e| e.id == id).collect();
        assert!(pieces.iter().filter(|e| e.bits & COUNTED != 0).count() <= 1, "{id}번 막대를 두 번 셈");
        assert!(pieces.len() == 1 || pieces.iter().any(|e| e.bits & (EVENT_CLIP_LEFT | EVENT_CLIP_RIGHT) != 0));
        // 막대는 기간 막대의 단과 든 띠를 함께 싣는다.
        assert!(pieces.iter().all(|e| e.rail == (id as i64 % 2) as u32));
        assert!(pieces.iter().all(|e| e.band == samples[(id - 1) as usize].band as u32), "{id}번 막대가 든 띠");
    }
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 빈_타일과_잘못된_요청() {
    let path = scratch("tiles-empty");
    build(&path);
    let s = Store::open(&path).unwrap();
    let far = build_tile(&s, &TileRequest { level: 3, x: 9_000_000, chunk: 0, packs: vec![1, 2], filter: None, variants: None }).unwrap();
    assert_eq!(far.len(), 76, "머리 72바이트 + 빈 글자표의 끝 표지 4바이트");
    let empty = decode(&far).unwrap();
    assert!(empty.bands.is_empty() && empty.events.is_empty() && empty.pills.is_empty() && empty.strings.is_empty() && empty.sections.is_empty());
    assert!(table_of(&far).is_empty(), "빈 타일에는 구역이 하나도 없다");
    assert_eq!(build_tile(&s, &TileRequest { level: 3, x: 0, chunk: 40, packs: vec![1, 2], filter: None, variants: None }).unwrap().len(), 76, "줄이 없는 묶음도 빈 타일");
    assert!(build_tile(&s, &TileRequest { level: 15, x: 0, chunk: 0, packs: vec![1], filter: None, variants: None }).is_err());
    assert!(build_tile(&s, &TileRequest { level: 3, x: 0, chunk: -1, packs: vec![1], filter: None, variants: None }).is_err());
    assert!(decode(&far[..40]).is_err(), "잘린 바이트");
    let mut broken = far.clone();
    broken[0] ^= 1;
    assert!(decode(&broken).is_err(), "틀린 표지");
    let mut old = far.clone();
    old[4] = 1;
    assert!(decode(&old).is_err(), "1판 타일은 거절한다");
    // 모든 배열은 4바이트 원소: 길이가 4의 배수.
    assert_eq!(build_tile(&s, &TileRequest { level: 8, x: 0, chunk: 0, packs: vec![1, 2], filter: None, variants: None }).unwrap().len() % 4, 0);
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 구역_표는_종류와_열_수와_자리를_적고_자리마다_그_구역의_자료가_있다() {
    let path = scratch("tiles-sections");
    build(&path);
    let s = Store::open(&path).unwrap();
    let bytes = build_tile(&s, &TileRequest { level: 8, x: 0, chunk: 0, packs: vec![1, 2], filter: None, variants: None }).unwrap();
    assert_eq!(u32::from_le_bytes(bytes[0..4].try_into().unwrap()), MAGIC);
    assert_eq!(u16::from_le_bytes(bytes[4..6].try_into().unwrap()), VERSION);
    let table = table_of(&bytes);
    // 띠 · 칸 · 사건 · 알약 · 일반 구역 16 · 17. 구역 번호는 오름차순.
    assert_eq!(table.iter().map(|r| r.0).collect::<Vec<_>>(), vec![1, 2, 3, 4, 16, 17]);
    assert_eq!(table.iter().map(|r| r.2).collect::<Vec<_>>(), vec![BAND_COLUMNS, CELL_COLUMNS, EVENT_COLUMNS, PILL_COLUMNS, ITEM_COLUMNS, ITEM_COLUMNS]);
    // 자리는 구역 표 바로 뒤에서 차례로 이어진다.
    let mut at = (HEADER / 4 + SECTION_ENTRY_WORDS * table.len()) as u32;
    for (_, count, columns, offset) in &table {
        assert_eq!(*offset, at, "구역 자리");
        at += count * columns;
    }
    let t = decode(&bytes).unwrap();
    assert_eq!(t.section(16).len(), table[4].1 as usize);
    assert_eq!(t.section(99).len(), 0, "없는 구역은 빈 구역");
    // 일반 구역의 값은 넣은 그대로 실려 온다.
    let tag = &t.section(16)[0];
    assert_eq!((tag.row, tag.row2, tag.reference, tag.color, tag.a), (0, 0, 2, 0xa0bcc5, 1));
    assert_eq!(t.strings[tag.name as usize], "별여울 속국");
    assert_eq!(t.strings[tag.text2 as usize], "곁글");
    let link = &t.section(17)[0];
    assert_eq!((link.row, link.row2, link.reference, link.a, link.b), (0, 3, 1, 1, 2));
    assert_eq!(link.name, u32::MAX, "이름이 없으면 글자표를 가리키지 않는다");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

/// 손으로 짠 타일: 구역 표(종류 · 항목 수 · 열 수)와 자료를 마음대로 둔다.
fn raw_tile(sections: &[(u32, u32, u32, Vec<u32>)], strings: &[&str]) -> Vec<u8> {
    let text_bytes: usize = strings.iter().map(|s| s.len()).sum();
    let mut out = Vec::new();
    out.extend_from_slice(&MAGIC.to_le_bytes());
    out.extend_from_slice(&VERSION.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out.extend_from_slice(&8i32.to_le_bytes());
    out.extend_from_slice(&0i32.to_le_bytes());
    for v in [0i64, 0, 16_777_216] {
        out.extend_from_slice(&v.to_le_bytes());
    }
    for n in [sections.len(), strings.len(), text_bytes, 0, 0, 0, 0, 0] {
        out.extend_from_slice(&(n as u32).to_le_bytes());
    }
    let mut at = HEADER / 4 + SECTION_ENTRY_WORDS * sections.len();
    for (kind, count, columns, words) in sections {
        for v in [*kind, *count, *columns, at as u32] {
            out.extend_from_slice(&v.to_le_bytes());
        }
        at += words.len();
    }
    for (_, _, _, words) in sections {
        for w in words {
            out.extend_from_slice(&w.to_le_bytes());
        }
    }
    let mut offset = 0u32;
    for s in strings {
        out.extend_from_slice(&offset.to_le_bytes());
        offset += s.len() as u32;
    }
    out.extend_from_slice(&offset.to_le_bytes());
    for s in strings {
        out.extend_from_slice(s.as_bytes());
    }
    out.resize(out.len().div_ceil(4) * 4, 0);
    out
}

#[test]
fn 모르는_구역은_건너뛰고_모자란_열은_0으로_읽는다() {
    // 1판처럼 열이 일곱뿐인 띠 구역 · 아직 뜻을 모르는 구역 7 · 알약.
    let band7: Vec<u32> = vec![
        0f32.to_bits(), 10f32.to_bits(), // x0
        100f32.to_bits(), 200f32.to_bits(), // x1
        1, 2, // id
        0xa0bcc5, 0x9dbea8, // color
        0, u32::MAX, // name
        3, 4, // row
        CLIP_LEFT, 0, // flags
    ];
    let unknown: Vec<u32> = vec![1, 2, 3, 4, 5, 6];
    let pills: Vec<u32> = vec![0f32.to_bits(), 64f32.to_bits(), 7, 3];
    let bytes = raw_tile(&[(1, 2, 7, band7), (7, 2, 3, unknown), (4, 1, 4, pills)], &["별여울 띠"]);
    let t = decode(&bytes).unwrap();
    assert_eq!(t.bands.len(), 2);
    assert_eq!((t.bands[0].x0, t.bands[0].x1, t.bands[0].id, t.bands[0].row, t.bands[0].flags), (0.0, 100.0, 1, 3, CLIP_LEFT));
    assert_eq!((t.bands[0].look, t.bands[0].tag, t.bands[0].sub), (0, 0, 0), "없는 열은 0");
    assert_eq!(t.strings[t.bands[0].name as usize], "별여울 띠");
    assert_eq!(t.bands[1].name, u32::MAX);
    assert_eq!(t.pills.len(), 1);
    assert_eq!((t.pills[0].count, t.pills[0].row), (7, 3), "모르는 구역 뒤의 구역도 제자리에서 읽힌다");
    // 모르는 구역은 열이 셋뿐이라도 자리만 건너뛰면 된다(뜻은 화면이 정한다).
    assert_eq!(t.sections.iter().map(|s| s.kind).collect::<Vec<_>>(), vec![7]);
    // 열 열 개를 적어 놓고 자료는 둘뿐인 구역 — 타일 밖을 가리키므로 거절한다.
    let bad = raw_tile(&[(1, 9_999, 10, vec![0, 0])], &[]);
    assert!(decode(&bad).is_err(), "타일 밖을 가리키는 구역은 거절한다");
    // 사건 구역의 열이 아홉뿐(band가 없는 옛 타일)이어도 읽힌다.
    let events9: Vec<u32> = vec![0f32.to_bits(), 0f32.to_bits(), 5, u32::MAX, 2, COUNTED | 1, 0x0103, u32::MAX, 0];
    let old = decode(&raw_tile(&[(3, 1, 9, events9)], &[])).unwrap();
    assert_eq!((old.events[0].id, old.events[0].look, old.events[0].band), (5, 0x0103, 0));
}

#[test]
fn 일반_구역은_타일_범위로_잘리고_걸친_줄_묶음마다_실린다() {
    let path = scratch("tiles-items");
    let geo = RowGeo { height: 40, band_top: 0, band_h: 40, dyn_top: -1, lead_top: -1, cab_top: -1, text_top: 0, text_lines: 1, rail_top: -1, organ_top: -1 };
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용", None).unwrap();
    let track = b.track_full(&TrackIn::plain(pack, "한 트랙")).unwrap();
    for _ in 0..16 {
        b.row(track, &geo).unwrap();
    }
    // 줄 6~9에 걸치고 0분(타일 경계)을 가로지르는 관계선.
    b.item(&ItemIn { pack, section: 17, row: 6, row2: 9, start: -100 * DAY, end: 200 * DAY, lod: None, ref_id: 0, ref_kind: 0,
        name: "긴 관계선", color: 0x8a8f96, a: 1, b: 2, c: 3, d: 4, text2: "", variant: 0 }).unwrap();
    // 성긴 단계에서는 빠지는 작은 항목.
    b.item(&ItemIn { pack, section: 16, row: 0, row2: 0, start: 0, end: 10, lod: Some(2), ref_id: 0, ref_kind: 0,
        name: "작은 이름표", color: 0, a: 0, b: 0, c: 0, d: 0, text2: "", variant: 0 }).unwrap();
    b.finalize(&[]).unwrap();
    let s = Store::open(&path).unwrap();
    let chunk = |level: usize, x: i64, chunk: i64| decode(&build_tile(&s, &TileRequest { level, x, chunk, packs: vec![pack], filter: None, variants: None }).unwrap()).unwrap();
    let (left, right) = (chunk(8, -1, 0), chunk(8, 0, 0));
    assert_eq!(left.section(17).len(), 1);
    assert_eq!(left.section(17)[0].flags, CLIP_RIGHT);
    assert_eq!(left.section(17)[0].x0, (left.span - 100 * DAY) as f32);
    assert_eq!(left.section(17)[0].x1, left.span as f32);
    assert_eq!(right.section(17)[0].flags, CLIP_LEFT);
    assert_eq!((right.section(17)[0].x0, right.section(17)[0].x1), (0.0, (200 * DAY + 1) as f32));
    assert_eq!((right.section(17)[0].row, right.section(17)[0].row2), (6, 9));
    // 줄 8~15의 묶음에도 같은 항목이 한 번씩 실린다.
    assert_eq!(chunk(8, 0, 1).section(17).len(), 1);
    assert!(chunk(8, 0, 2).section(17).is_empty(), "걸치지 않은 묶음에는 없다");
    // 가늘기 등급: 단계 2까지만 실린다.
    assert_eq!(chunk(2, 0, 0).section(16).len(), 1);
    assert!(chunk(3, 0, 0).section(16).is_empty(), "너무 성긴 단계에서는 빠진다");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 화면이_부르는_연결부는_같은_바이트를_돌려주고_실패하면_까닭을_남긴다() {
    use archive_engine::{archive_call, archive_free, archive_free_bytes, archive_tile};
    use std::ffi::{CStr, CString};
    let path = scratch("tiles-ffi");
    build(&path);
    let call = |text: String| -> serde_json::Value {
        let request = CString::new(text).unwrap();
        unsafe {
            let answer = archive_call(request.as_ptr());
            let value = serde_json::from_slice(CStr::from_ptr(answer).to_bytes()).unwrap();
            archive_free(answer);
            value
        }
    };
    assert_eq!(call(serde_json::json!({"op":"open","path":path.to_str().unwrap()}).to_string())["ok"], true);
    let direct = build_tile(&Store::open(&path).unwrap(), &TileRequest { level: 8, x: 0, chunk: 0, packs: vec![1, 2], filter: None, variants: None }).unwrap();
    let request = CString::new(r#"{"level":8,"x":0,"chunk":0,"packs":[1,2]}"#).unwrap();
    let mut len = 0usize;
    let bytes = unsafe {
        let ptr = archive_tile(request.as_ptr(), &mut len);
        assert!(!ptr.is_null());
        let copy = std::slice::from_raw_parts(ptr, len).to_vec();
        archive_free_bytes(ptr, len);
        copy
    };
    assert_eq!(bytes, direct);
    let bad = CString::new(r#"{"level":99,"x":0,"chunk":0,"packs":[1]}"#).unwrap();
    let mut bad_len = 7usize;
    assert!(unsafe { archive_tile(bad.as_ptr(), &mut bad_len) }.is_null());
    assert_eq!(bad_len, 0);
    let why = call(r#"{"op":"last_error"}"#.to_owned());
    assert!(why["data"]["error"].as_str().unwrap().contains("범위 밖"), "{why}");
    // 3판의 조회 명령도 연결부를 통해 온다.
    let near = call(serde_json::json!({"op":"rows_near","near":[-500*DAY,600*DAY],"fade":0,"packs":[1,2]}).to_string());
    assert_eq!(near["data"]["near"], serde_json::json!([0, 1, 2, 3, 4, 5, 6, 7]));
    assert_eq!(call(r#"{"op":"entity","uid":"band-0-0"}"#.to_owned())["data"]["kind"], "period");
    // 저장소를 놓으면(close) 그 뒤의 조회 · 타일은 까닭과 함께 실패하고, 다시 열면(open) 예전처럼 온다 — DLC를 바꿔 넣는 길.
    assert_eq!(call(r#"{"op":"close"}"#.to_owned())["data"]["closed"], true);
    assert_eq!(call(r#"{"op":"close"}"#.to_owned())["data"]["closed"], false, "이미 놓았으면 거짓");
    let shut = call(r#"{"op":"entity","uid":"band-0-0"}"#.to_owned());
    assert_eq!(shut["ok"], false);
    assert!(shut["error"].as_str().unwrap().contains("열리지 않았습니다"), "{shut}");
    let mut shut_len = 3usize;
    assert!(unsafe { archive_tile(request.as_ptr(), &mut shut_len) }.is_null());
    assert_eq!(shut_len, 0);
    assert_eq!(call(serde_json::json!({"op":"open","path":path.to_str().unwrap()}).to_string())["ok"], true);
    assert_eq!(call(r#"{"op":"entity","uid":"band-0-0"}"#.to_owned())["data"]["kind"], "period");
}

#[test]
fn 대표의_제목은_미리_만든_단계와_그_자리에서_세는_단계에서_똑같이_온다() {
    let path = scratch("tiles-titles");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    for level in [2usize, 7, 8, 13] {
        let tiles = sweep(&s, level, &[1, 2]);
        let mut seen = 0;
        for (t, e) in tiles.iter().flat_map(|t| t.events.iter().map(move |e| (t, e))) {
            let wanted = if e.id == 1 { "해솔별 星河" } else if e.id == 2 { "해 다른 글 솔별" } else { "가상 사건" };
            assert_eq!(t.strings[e.name as usize], wanted, "단계 {level} · {}번", e.id);
            // look과 이름 옆 날짜 글도 두 길에서 똑같이 온다.
            assert_eq!(e.look, (e.id % 3) as u32, "단계 {level} · {}번의 look", e.id);
            let label = if e.label == u32::MAX { String::new() } else { t.strings[e.label as usize].clone() };
            assert_eq!(label, if e.id % 4 == 0 { format!("{}년", e.id) } else { String::new() }, "단계 {level} · {}번의 딱지", e.id);
            assert_eq!(e.band, samples[(e.id - 1) as usize].band as u32, "단계 {level} · {}번이 든 띠", e.id);
            seen += 1;
        }
        assert!(seen > 0);
        // 성긴 단계에서는 중요도 1인 1 · 2번이 대표에서 밀려난다. 세부 단계에서는 제 제목으로 보인다.
        if level <= 8 {
            assert!(tiles.iter().any(|t| t.events.iter().any(|e| e.id == 1)) && tiles.iter().any(|t| t.events.iter().any(|e| e.id == 2)), "단계 {level}");
        }
    }
    // 그 자리에서 세는 단계는 (줄, 시작)을 덮는 색인만 훑는다 — 같은 날 몰린 사건마다 사건 표를 찾아가지 않게.
    let plan: String = s.db.query_row("EXPLAIN QUERY PLAN SELECT id,start,importance FROM events WHERE lane=1 AND start BETWEEN 0 AND 9 AND pack IN (1,2)", [], |r| r.get(3)).unwrap();
    assert!(plan.contains("COVERING INDEX events_time"), "{plan}");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 같은_요청은_언제나_같은_바이트를_돌려준다() {
    let path = scratch("tiles-same");
    // 제목이 모두 다른 사건 40개를 서로 다른 통에 둔다 — 글자표에 들어가는 순서가 흔들리면 바이트가 달라진다.
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용", None).unwrap();
    let track = b.track(pack, "한 트랙").unwrap();
    let row = b.row(track, &common::GEO).unwrap();
    for i in 0..40i64 {
        let at = Some(i * 300 * DAY);
        b.event(&EventIn { pack, lane: row, start: at, end: at, importance: 1, title: &format!("별여울 기록 {i}"), label: "12년", ..Default::default() }).unwrap();
        b.item(&ItemIn { pack, section: 16 + (i % 3), row, row2: row, start: i * 300 * DAY, end: i * 300 * DAY + 10 * DAY, lod: None, ref_id: 0, ref_kind: 0,
            name: &format!("이름표 {i}"), color: 0, a: i, b: 0, c: 0, d: 0, text2: "", variant: 0 }).unwrap();
    }
    b.finalize(&[]).unwrap();
    let s = Store::open(&path).unwrap();
    for level in [3usize, 9, 12] {
        let req = TileRequest { level, x: 0, chunk: 0, packs: vec![pack], filter: None, variants: None };
        let first = build_tile(&s, &req).unwrap();
        for _ in 0..5 {
            assert_eq!(build_tile(&s, &req).unwrap(), first, "단계 {level}: 글자표의 순서까지 같아야 화면의 보관과 고정 파일이 흔들리지 않는다");
        }
        // 풀었다가 다시 부호화해도 같은 바이트다(구역 표의 자리까지).
        assert_eq!(encode(&decode(&first).unwrap()), first, "단계 {level}: 되풀이 부호화");
    }
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 촘촘한_단계의_사건은_제목까지_덮는_색인만_훑어_얻는다() {
    // 대표마다 사건 표를 찾아가면 1,000만 건(5GB)에서 흩어진 자리를 읽느라 촘촘한 단계의 타일 하나에 44~67ms가 걸렸다.
    let path = scratch("tiles-covering");
    build(&path);
    let s = Store::open(&path).unwrap();
    // 앱(FFI)은 타일마다 변형을 풀어 넘긴다 — 변형 표가 있는 저장소면 아무것도 켜지 않아도 `AND variant=0`이 붙는다.
    // 그 조각까지 붙인 조회가 실제로 도는 조회다(맨 조회만 보면 variant가 색인 밖이어도 통과해 버린다).
    let plain = s.variants_of(&serde_json::json!({})).unwrap().expect("새로 만든 저장소에는 변형 표가 있다");
    let one_on = archive_engine::variant::Variants { on: vec![1], ..Default::default() };
    for keep in [String::new(), plain.keep("variant"), one_on.keep("variant")] {
        let sql = format!("{}{keep}", archive_engine::tile::FINE_EVENTS_SQL);
        let plan: Vec<String> = s.db.prepare(&format!("EXPLAIN QUERY PLAN {sql}")).unwrap()
            .query_map(rusqlite::params![0, 0, 1, "[1]"], |r| r.get::<_, String>(3)).unwrap().map(|r| r.unwrap()).collect();
        let events: Vec<&String> = plan.iter().filter(|line| line.contains("events")).collect();
        assert!(!events.is_empty(), "{plan:?}");
        assert!(events.iter().all(|line| line.contains("COVERING INDEX events_time")), "사건 표를 찾아가지 않아야 한다({keep:?}): {plan:?}");
    }
    // rail은 시작 날짜의 정밀도(8~10비트)를 대표에 싣는 데 쓴다(묶음 5 · 세기로 적은 연대).
    for column in ["title", "look", "label", "band", "rail"] {
        assert!(archive_engine::tile::FINE_EVENTS_SQL.contains(column), "{column}도 같은 조회에서 온다");
    }
    drop(s);
    std::fs::remove_file(path).unwrap();
}

/// 촘촘한 단계의 사건 조회가 받는 계획(사건 표에 닿는 줄만). `keep`은 변형 조각(앱이 붙이는 것)이다.
fn fine_plan(path: &std::path::Path, keep: &str) -> Vec<String> {
    let db = rusqlite::Connection::open(path).unwrap();
    let sql = format!("EXPLAIN QUERY PLAN {}{keep}", archive_engine::tile::FINE_EVENTS_SQL);
    let plan: Vec<String> = db.prepare(&sql).unwrap()
        .query_map(rusqlite::params![0, 0, 1, "[1]"], |r| r.get::<_, String>(3)).unwrap().map(|r| r.unwrap()).collect();
    plan.into_iter().filter(|line| line.contains("events")).collect()
}

#[test]
fn 이미_만든_저장소는_색인만_다시_만들면_같은_바이트를_색인에서만_읽는다() {
    // 덮는 색인의 모양이 바뀌면(rail · variant가 빠져 있던 옛 모양) 이미 만든 저장소는 `reindex`로 색인만 다시 만든다 — 자료는 그대로다.
    let path = scratch("tiles-reindex");
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용", None).unwrap();
    let track = b.track(pack, "한 트랙").unwrap();
    let row = b.row(track, &common::GEO).unwrap();
    for i in 0..30i64 {
        let at = Some(i * 40 * DAY);
        // rail의 8~10비트 = 시작 날짜의 정밀도(0이면 해) — 촘촘한 단계의 대표가 제목과 함께 싣는다.
        b.event(&EventIn { pack, lane: row, start: at, end: at, importance: 1 + i % 3, title: &format!("별여울 기록 {i}"), label: "12년",
            rail: (i % 4) << 8, ..Default::default() }).unwrap();
    }
    b.finalize(&[]).unwrap();
    // 앱과 같은 길: 변형을 풀어(켠 것 없음) 넘긴다.
    let dense = |path: &std::path::Path| -> Vec<Vec<u8>> {
        let s = Store::open(path).unwrap();
        let mut out = Vec::new();
        for level in [3usize, 6] {
            for x in tile_of(0, level)..=tile_of(1200 * DAY, level) {
                let req = TileRequest { level, x, chunk: 0, packs: vec![pack], filter: None, variants: s.variants_of(&serde_json::json!({})).unwrap() };
                out.push(build_tile(&s, &req).unwrap());
            }
        }
        out
    };
    let keep = " AND variant=0";
    let fresh = dense(&path);
    let precs: BTreeSet<u32> = fresh.iter().flat_map(|t| decode(t).unwrap().events).map(|e| (e.rail >> 8) & 7).collect();
    assert_eq!(precs, BTreeSet::from([0, 1, 2, 3]), "정밀도가 대표에 실려 나온다");

    // 옛 모양의 색인으로 되돌리면 사건 표를 찾아간다(이 검사가 겨누는 상황).
    rusqlite::Connection::open(&path).unwrap().execute_batch(
        "DROP INDEX events_time; CREATE INDEX events_time ON events(lane,start,id,importance,pack,title,look,label,band)").unwrap();
    assert!(fine_plan(&path, keep).iter().all(|line| !line.contains("COVERING")), "옛 모양의 색인은 덮지 못한다");
    assert_eq!(dense(&path), fresh, "옛 색인에서도 바이트는 같다(느릴 뿐)");
    archive_engine::builder::reindex(&path).unwrap();
    for plan in [fine_plan(&path, ""), fine_plan(&path, keep)] {
        assert!(!plan.is_empty() && plan.iter().all(|line| line.contains("COVERING INDEX events_time")), "{plan:?}");
    }
    assert_eq!(dense(&path), fresh, "색인만 다시 만들어도 바이트는 같다");

    // 변형을 넣기 전에 만든 저장소(가상 100만 건 등)에는 사건 표의 variant 열이 없다 — 그 열만 빼고 다시 만든다.
    rusqlite::Connection::open(&path).unwrap().execute_batch("DROP INDEX events_time; ALTER TABLE events DROP COLUMN variant").unwrap();
    archive_engine::builder::reindex(&path).unwrap();
    let made: String = rusqlite::Connection::open(&path).unwrap()
        .query_row("SELECT sql FROM sqlite_master WHERE name='events_time'", [], |r| r.get(0)).unwrap();
    assert!(made.contains("rail") && !made.contains("variant"), "{made}");
    let plan = fine_plan(&path, "");
    assert!(!plan.is_empty() && plan.iter().all(|line| line.contains("COVERING INDEX events_time")), "{plan:?}");
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 알려진_한계_45일보다_짧은_기간_사건은_시작_시각의_점으로만_나온다() {
    // 막대 목록에는 45.5일(L8의 통 하나) 이상인 사건만 든다. 그보다 짧은 기간 사건은 그 기간 한가운데로 확대하면 자취가 없다 —
    // 2단계의 알려진 한계다(검증 보고서 8절, 전체 검토의 중요 2번). 짧은 막대를 넣으려면 막대가 이름을 못 담을 때 점과 이름을 함께 두는
    // 규칙까지 정해야 해서, 기간 사건의 표현을 옮기는 묶음에서 다룬다. 이 검사는 그때 일부러 고치라고 지금의 동작을 못 박아 둔다.
    let path = scratch("tiles-short-bars");
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("검사용", None).unwrap();
    let track = b.track(pack, "한 트랙").unwrap();
    let row = b.row(track, &common::GEO).unwrap();
    let (start, end) = (100 * DAY, 110 * DAY);
    b.event(&EventIn { pack, lane: row, start: Some(start), end: Some(end), importance: 2, title: "별여울 열흘 공사", ..Default::default() }).unwrap();
    b.finalize(&[]).unwrap();
    let s = Store::open(&path).unwrap();
    // 단계 3: 타일 하나가 11.4일 → 열흘짜리 사건이 타일 둘에 걸친다.
    let level = 3usize;
    let first = tile_of(start, level);
    assert!(tile_of(end, level) > first);
    let head = tile(&s, level, first, &[pack]);
    assert_eq!(head.events.len(), 1);
    assert!(head.events[0].bits & BAR == 0 && head.events[0].bits & COUNTED != 0, "시작이 든 타일에는 점으로 나오고 개수에 든다");
    let middle = tile(&s, level, first + 1, &[pack]);
    assert!(middle.events.is_empty(), "기간 한가운데의 타일에는 자취가 없다(알려진 한계)");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

/// 스키마 4(리메이크 3단계 · 계약 1-1 · 5절): 띠 구역의 **열 10 = `form`**(형식 4의 종류 · 관계 · 정통성 · 중요도 비트). 알약의 `cats`처럼
/// form ≠ 0인 띠가 하나라도 든 타일에만 열하나 열로 싣고(`BAND_FORM_COLUMNS`), 해독기는 그 값을 띠마다 준다. form이 모두 0인 타일은 2판 그대로 열 열이고,
/// form을 모두 0으로 지운 같은 저장소 · form 열이 아예 없는 옛 저장소(판 '3')의 같은 타일과 바이트까지 같다 — 머리의 판(2)은 그대로다.
#[test]
fn 띠의_form은_0이_아닌_띠가_든_타일에만_열_10으로_실리고_나머지는_바이트_그대로다() {
    use archive_engine::tile::{band_columns, BAND_FORM_COLUMNS};
    let path = scratch("tiles-form");
    build(&path);
    // 지금 짓기는 form을 모두 0으로 적는다 — 그 판을 둘 떠 둔다(0으로 지운 것 · form 열과 sphere_lines 표를 걷은 옛 판 '3').
    let (zeroed, older) = (scratch("tiles-form-zero"), scratch("tiles-form-old"));
    std::fs::copy(&path, &zeroed).unwrap();
    std::fs::copy(&path, &older).unwrap();
    {
        let db = rusqlite::Connection::open(&older).unwrap();
        db.execute_batch("ALTER TABLE periods DROP COLUMN form; DROP TABLE sphere_lines; UPDATE meta SET value='3' WHERE key='schema';").unwrap();
    }
    // 띠 둘에만 form을 단다 — 줄 0의 첫 띠(국가 · 정통 · 중요도 2)와 줄 5의 가운데 띠(도시 · 봉국 — 0분 타일 경계를 가로지른다).
    let forms: [(&str, u32); 2] = [("band-0-0", 1 | 1 << 10 | 3 << 13), ("band-5-1", 4 | 2 << 5)];
    let mut want: BTreeMap<u32, u32> = BTreeMap::new();
    {
        let db = rusqlite::Connection::open(&path).unwrap();
        for (uid, form) in forms {
            assert_eq!(db.execute("UPDATE periods SET form=?2 WHERE uid=?1", rusqlite::params![uid, form]).unwrap(), 1, "{uid}");
            want.insert(db.query_row("SELECT id FROM periods WHERE uid=?1", [uid], |r| r.get(0)).unwrap(), form);
        }
    }
    let (s, z, o) = (Store::open(&path).unwrap(), Store::open(&zeroed).unwrap(), Store::open(&older).unwrap());
    assert!(s.period_form && z.period_form && !o.period_form, "옛 판은 form 열이 없다");
    let (mut wide, mut narrow) = (0, 0);
    for level in [3usize, 8, 11] {
        for x in tile_of(-460 * DAY, level)..=tile_of(1360 * DAY, level) {
            let req = TileRequest { level, x, chunk: 0, packs: vec![1, 2], filter: None, variants: None };
            let (bytes, plain, old) = (build_tile(&s, &req).unwrap(), build_tile(&z, &req).unwrap(), build_tile(&o, &req).unwrap());
            assert_eq!(plain, old, "단계 {level} 타일 {x}: form이 모두 0인 저장소와 form 열이 없는 옛 저장소의 타일은 바이트가 같다");
            let t = decode(&bytes).unwrap();
            if t.bands.is_empty() {
                assert_eq!(bytes, plain, "단계 {level} 타일 {x}: 띠가 없는 타일");
                continue;
            }
            for b in &t.bands {
                assert_eq!(b.form, want.get(&b.id).copied().unwrap_or(0), "단계 {level} 타일 {x}: 띠 {}의 form", b.id);
            }
            let carried = t.bands.iter().any(|b| b.form != 0);
            let band_row = table_of(&bytes).into_iter().find(|r| r.0 == 1).unwrap();
            assert_eq!(band_row.2, if carried { BAND_FORM_COLUMNS } else { BAND_COLUMNS }, "단계 {level} 타일 {x}: 띠 구역의 열 수");
            assert_eq!(band_columns(&t.bands), band_row.2);
            assert_eq!(table_of(&plain).into_iter().find(|r| r.0 == 1).unwrap().2, BAND_COLUMNS, "form이 모두 0이면 열 열");
            assert!(decode(&plain).unwrap().bands.iter().all(|b| b.form == 0), "열 10이 없는 타일의 form은 0");
            if carried {
                wide += 1;
                assert_ne!(bytes, plain, "단계 {level} 타일 {x}: form 열이 실렸다");
                // 열 10만 더해졌을 뿐 나머지 값은 같다.
                let mut back = decode(&bytes).unwrap();
                back.bands.iter_mut().for_each(|b| b.form = 0);
                assert_eq!(encode(&back), plain, "단계 {level} 타일 {x}: form만 지우면 0으로 지운 저장소의 바이트");
            } else {
                narrow += 1;
                assert_eq!(bytes, plain, "단계 {level} 타일 {x}: form ≠ 0인 띠가 없는 타일은 바이트까지 같다");
            }
            // 풀었다가 다시 부호화해도 같은 바이트(열 10의 자리까지).
            assert_eq!(encode(&t), bytes, "단계 {level} 타일 {x}: 되풀이 부호화");
            assert_eq!(u16::from_le_bytes(bytes[4..6].try_into().unwrap()), VERSION, "타일 머리의 판은 그대로");
        }
    }
    assert!(wide > 0 && narrow > 0, "form 열이 실린 타일({wide})과 안 실린 타일({narrow})을 다 보았어야 한다");
    drop((s, z, o));
    for p in [path, zeroed, older] {
        std::fs::remove_file(p).unwrap();
    }
}

//! 줄 열쇠와 자리(계획 P4 과제 1a · 1c · 2): 트랙마다 줄 열쇠를 끝 번호 뒤로 옮겨도(열쇠 ≠ 자리) 밖으로 보이는 답이 그대로인가.
mod common;
use archive_engine::rowmap::{rekey_track, RowMap};
use std::path::{Path, PathBuf};

/// 저장소를 복사하고, 트랙을 거꾸로 차례로 끝 번호 + 3으로 옮긴다 — 모든 트랙의 열쇠가 자리와 갈린다.
pub fn scrambled(src: &Path, name: &str) -> PathBuf {
    let dst = common::scratch(name);
    std::fs::copy(src, &dst).unwrap();
    let mut db = rusqlite::Connection::open(&dst).unwrap();
    db.execute_batch("PRAGMA foreign_keys=ON").unwrap();
    let tx = db.transaction().unwrap();
    tx.execute_batch("PRAGMA defer_foreign_keys=ON").unwrap();
    let tracks: Vec<i64> = tx.prepare("SELECT DISTINCT track FROM rows ORDER BY track DESC").unwrap()
        .query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
    for t in tracks {
        let next: i64 = tx.query_row("SELECT MAX(id)+1 FROM rows", [], |r| r.get(0)).unwrap();
        rekey_track(&tx, t, next + 3).unwrap();
    }
    tx.execute("UPDATE meta SET value='4.1' WHERE key='schema'", []).unwrap();
    tx.commit().unwrap();
    dst
}

#[test]
fn fresh_store_is_identity() {
    let path = common::scratch("rk-fresh");
    common::build(&path); // 트랙 둘 · 줄 넷씩(tests/common/mod.rs:23 — 수를 확인해 맞춤)
    let map = RowMap::load(&rusqlite::Connection::open(&path).unwrap()).unwrap();
    assert!(map.is_identity());
    assert_eq!(map.total(), 8);
    assert_eq!(map.key_ranges(2, 6), vec![(2, 3), (4, 6)]); // 트랙 경계에서 둘로
}

#[test]
fn rekey_keeps_children_consistent() {
    let path = common::scratch("rk-cons");
    common::build(&path);
    let other = scrambled(&path, "rk-cons-s");
    let db = rusqlite::Connection::open(&other).unwrap();
    let map = RowMap::load(&db).unwrap();
    assert!(!map.is_identity());
    assert_eq!(map.total(), 8);
    for p in 0..8 { assert_eq!(map.pos(map.key(p)), p); }
    let bad: i64 = db.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| r.get(0)).unwrap();
    assert_eq!(bad, 0);
    // 자식 열이 모두 새 덩이 안을 가리킨다(옛 열쇠 0~7을 가리키는 것이 없다).
    for (t, c) in [("periods", "row"), ("events", "lane"), ("items", "row"), ("items", "row2"), ("row_labels", "row"), ("summaries", "lane"), ("names", "row")] {
        let stale: i64 = db.query_row(&format!("SELECT count(*) FROM {t} WHERE {c} BETWEEN 0 AND 7"), [], |r| r.get(0)).unwrap();
        assert_eq!(stale, 0, "{t}.{c}");
    }
}

// ---- 아래는 과제 1a가 더한 검사: 옮긴 뒤에도 자리마다 내용이 같고, R-tree · 변형 · 겹친 이동 · 오류 길이 맞는가 ----

use archive_engine::Store;
use rusqlite::Connection;
use serde_json::json;

/// 저장소를 복사해 주어진 (트랙, 새 첫 열쇠)를 차례로 옮기고 판을 '4.1'(스키마 4의 열쇠 ≠ 자리)로 적는다.
fn rekeyed(src: &Path, name: &str, moves: &[(i64, i64)]) -> PathBuf {
    let dst = common::scratch(name);
    std::fs::copy(src, &dst).unwrap();
    let mut db = Connection::open(&dst).unwrap();
    db.execute_batch("PRAGMA foreign_keys=ON").unwrap();
    let tx = db.transaction().unwrap();
    tx.execute_batch("PRAGMA defer_foreign_keys=ON").unwrap();
    for (track, key0) in moves {
        rekey_track(&tx, *track, *key0).unwrap();
    }
    tx.execute("UPDATE meta SET value='4.1' WHERE key='schema'", []).unwrap();
    tx.commit().unwrap();
    dst
}

fn count(db: &Connection, sql: &str) -> i64 {
    db.query_row(sql, [], |r| r.get(0)).unwrap()
}

/// 자리 p마다, 그 줄을 가리키는 값의 수(표 · 열). 열쇠를 갈라도 자리별 수가 같아야 한다.
fn per_pos(db: &Connection, map: &RowMap, table: &str, column: &str) -> Vec<i64> {
    (0..map.total()).map(|p| count(db, &format!("SELECT count(*) FROM {table} WHERE {column}={}", map.key(p)))).collect()
}

fn summary_per_pos(db: &Connection, map: &RowMap) -> Vec<i64> {
    (0..map.total()).map(|p| count(db, &format!("SELECT COALESCE(SUM(n),0) FROM summaries WHERE lane={}", map.key(p)))).collect()
}

#[test]
fn rekey_preserves_content_by_position() {
    let path = common::scratch("rk-same");
    common::build(&path);
    let before = Connection::open(&path).unwrap();
    let before_map = RowMap::load(&before).unwrap();
    let other = scrambled(&path, "rk-same-s");
    let after = Connection::open(&other).unwrap();
    let after_map = RowMap::load(&after).unwrap();
    for (table, column) in [("periods", "row"), ("events", "lane"), ("items", "row"), ("items", "row2"), ("row_labels", "row"), ("names", "row"), ("groups", "first_row")] {
        let was = per_pos(&before, &before_map, table, column);
        assert_eq!(per_pos(&after, &after_map, table, column), was, "{table}.{column}");
        assert!(was.iter().sum::<i64>() > 0, "{table}.{column}는 검사 자료에서 비어 있지 않아야 한다");
    }
    let sums = summary_per_pos(&before, &before_map);
    assert!(sums.iter().sum::<i64>() > 0);
    assert_eq!(summary_per_pos(&after, &after_map), sums);
    // 줄 자체의 값(트랙 · 줄 안 차례 · 높이)도 자리마다 같다.
    for p in 0..8 {
        let line = |db: &Connection, map: &RowMap| -> (i64, i64, i64) {
            db.query_row("SELECT track,ord,height FROM rows WHERE id=?1", [map.key(p)], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap()
        };
        assert_eq!(line(&after, &after_map), line(&before, &before_map), "자리 {p}");
    }
    // 트랙 차례(자리 차례)는 그대로다 — 열쇠는 거꾸로 놓였어도.
    let order = |m: &RowMap| m.blocks().iter().map(|b| b.track).collect::<Vec<_>>();
    assert_eq!(order(&after_map), order(&before_map));
    assert!(after_map.blocks()[0].key0 > after_map.blocks()[1].key0, "트랙 1의 열쇠가 트랙 2의 뒤에 놓였다");
}

#[test]
fn rekey_moves_rtrees_with_their_tables() {
    const TREES: [&str; 5] = ["bounds", "span_bounds", "period_bounds", "cell_bounds", "item_bounds"];
    let path = common::scratch("rk-rtree");
    common::build(&path);
    let before = Connection::open(&path).unwrap();
    let totals: Vec<i64> = TREES.iter().map(|t| count(&before, &format!("SELECT count(*) FROM {t}"))).collect();
    let other = scrambled(&path, "rk-rtree-s");
    let db = Connection::open(&other).unwrap();
    for (i, t) in TREES.iter().enumerate() {
        assert!(totals[i] > 0, "{t}는 검사 자료에서 비어 있지 않아야 한다");
        assert_eq!(count(&db, &format!("SELECT count(*) FROM {t}")), totals[i], "{t}의 항목 수");
    }
    // R-tree의 줄 칸이 표의 열과 한 줄도 다르지 않다.
    assert_eq!(count(&db, "SELECT count(*) FROM events e JOIN bounds b ON b.id=e.id WHERE b.lane_min<>e.lane OR b.lane_max<>e.lane"), 0);
    assert_eq!(count(&db, "SELECT count(*) FROM events e JOIN span_bounds b ON b.id=e.id WHERE b.lane_min<>e.lane OR b.lane_max<>e.lane"), 0);
    assert_eq!(count(&db, "SELECT count(*) FROM periods p JOIN period_bounds b ON b.id=p.id WHERE b.row_min<>p.row OR b.row_max<>p.row"), 0);
    assert_eq!(count(&db, "SELECT count(*) FROM cells c JOIN periods p ON p.id=c.period JOIN cell_bounds b ON b.id=c.id WHERE b.row_min<>p.row OR b.row_max<>p.row"), 0);
    assert_eq!(count(&db, "SELECT count(*) FROM items i JOIN item_bounds b ON b.id=i.id WHERE b.row_min<>i.row OR b.row_max<>i.row2"), 0);
    // 옛 번호(0~7) 칸에는 아무것도 없고, 덩이마다 줄 범위로 물으면(조회가 하는 방식) 전체가 나눠 나온다.
    for t in ["bounds", "span_bounds"] {
        assert_eq!(count(&db, &format!("SELECT count(*) FROM {t} WHERE lane_max<=7")), 0, "{t}에 옛 열쇠가 남았다");
    }
    for t in ["period_bounds", "cell_bounds", "item_bounds"] {
        assert_eq!(count(&db, &format!("SELECT count(*) FROM {t} WHERE row_max<=7")), 0, "{t}에 옛 열쇠가 남았다");
    }
    let map = RowMap::load(&db).unwrap();
    let per_block: i64 = map.blocks().iter().map(|b| count(&db, &format!("SELECT count(*) FROM bounds WHERE lane_min>={} AND lane_max<={}", b.key0, b.key0 + b.n - 1))).sum();
    assert_eq!(per_block, totals[0], "덩이마다 물은 R-tree 항목의 합이 전체와 같다");
}

#[test]
fn rekey_overlapping_move_and_errors() {
    let path = common::scratch("rk-edge");
    common::build(&path);
    let before = Connection::open(&path).unwrap();
    let before_map = RowMap::load(&before).unwrap();
    let was = per_pos(&before, &before_map, "events", "lane");

    // 옛 덩이(4~7)와 겹치는 이동: 5~8로. 한 걸음에 하면 열쇠가 부딪친다 — 빈 자리를 거쳐 두 걸음으로 해낸다.
    let moved = rekeyed(&path, "rk-edge-a", &[(2, 5)]);
    let db = Connection::open(&moved).unwrap();
    let map = RowMap::load(&db).unwrap();
    assert_eq!((map.blocks()[1].key0, map.blocks()[1].n), (5, 4));
    assert_eq!(map.key(4), 5);
    assert_eq!(map.pos(8), 7);
    assert_eq!(map.pos(4), -1, "비워진 열쇠는 모르는 열쇠");
    assert_eq!(per_pos(&db, &map, "events", "lane"), was);
    assert_eq!(count(&db, "SELECT count(*) FROM pragma_foreign_key_check"), 0);

    // 같은 자리로는 아무것도 하지 않는다.
    let same = rekeyed(&path, "rk-edge-b", &[(2, 4), (1, 0)]);
    assert!(RowMap::load(&Connection::open(&same).unwrap()).unwrap().is_identity());

    // 오류: 다른 트랙의 줄이 있는 범위 · 음수 · 32비트 밖 · 없는 트랙. 어느 것이든 아무것도 쓰기 전에 거절한다.
    let copy = common::scratch("rk-edge-c");
    std::fs::copy(&path, &copy).unwrap();
    let mut conn = Connection::open(&copy).unwrap();
    let tx = conn.transaction().unwrap();
    assert!(rekey_track(&tx, 1, 2).is_err(), "트랙 1을 2~5로 — 트랙 2의 줄 4 · 5가 있다");
    assert!(rekey_track(&tx, 1, -1).is_err());
    assert!(rekey_track(&tx, 1, i64::from(i32::MAX)).is_err());
    assert!(rekey_track(&tx, 99, 20).is_err());
    assert_eq!(count(&tx, "SELECT count(*) FROM rows WHERE id BETWEEN 0 AND 7"), 8, "거절한 뒤에도 줄은 그대로");
    assert_eq!(per_pos(&tx, &before_map, "events", "lane"), was);
}

#[test]
fn outward_turns_keys_into_positions() {
    let path = common::scratch("rk-out");
    common::build(&path);
    let other = scrambled(&path, "rk-out-s");
    let map = RowMap::load(&Connection::open(&other).unwrap()).unwrap();
    let key = |p: i64| map.key(p);
    let mut doc = json!({
        "row": key(5), "none": key(5), "gone": -1, "unknown": 999,
        "rows": [key(0), key(7), -1],
        "items": [{"lane": key(6), "name": "가", "ids": [key(1)]}, {"lane": key(2), "other": key(3)}],
        "deep": {"row": {"row": key(4)}}, "text": "row"
    });
    map.outward(&mut doc, &["row", "rows", "lane"]);
    assert_eq!(doc, json!({
        "row": 5, "none": key(5), "gone": -1, "unknown": 999,
        "rows": [0, 7, -1],
        "items": [{"lane": 6, "name": "가", "ids": [key(1)]}, {"lane": 2, "other": key(3)}],
        "deep": {"row": {"row": 4}}, "text": "row"
    }), "이름이 든 열만 자리로 · 음수 · 모르는 값 · 다른 이름은 그대로");
    // 열쇠 = 자리면 아무것도 하지 않는다.
    let fresh = RowMap::load(&Connection::open(&path).unwrap()).unwrap();
    let mut same = json!({"row": 5, "rows": [1, 2]});
    fresh.outward(&mut same, &["row", "rows"]);
    assert_eq!(same, json!({"row": 5, "rows": [1, 2]}));
}

#[test]
fn store_opens_split_keys() {
    let path = common::scratch("rk-open");
    common::build(&path);
    let fresh = Store::open(&path).unwrap();
    assert!(fresh.rows.is_identity());
    assert_eq!(fresh.rows.total(), 8);
    let busy: i64 = fresh.db.query_row("PRAGMA busy_timeout", [], |r| r.get(0)).unwrap();
    assert_eq!(busy, 5000, "읽기 연결은 쓰는 쪽의 COMMIT을 5초까지 기다린다");
    // 열쇠와 자리가 갈린 저장소('4.1')도 열린다.
    let other = scrambled(&path, "rk-open-s");
    let split = Store::open(&other).unwrap();
    assert!(!split.rows.is_identity());
    assert_eq!(split.rows.total(), 8);
    // 모르는 판은 거절한다.
    let odd = rekeyed(&path, "rk-open-odd", &[]);
    Connection::open(&odd).unwrap().execute("UPDATE meta SET value='5' WHERE key='schema'", []).unwrap();
    assert!(Store::open(&odd).is_err());
    // 스키마 4 전의 엔진이 적은 판('3' · '3.1')은 그대로 열린다(계약 1-1 — 새 열 · 표는 가려 읽는다).
    for old in ["3", "3.1"] {
        Connection::open(&odd).unwrap().execute("UPDATE meta SET value=?1 WHERE key='schema'", [old]).unwrap();
        assert!(Store::open(&odd).is_ok(), "판 {old}");
    }
}

#[test]
fn rekey_moves_variant_references() {
    use archive_engine::builder::{Builder, RowExtra, TrackIn};
    let path = common::scratch("rk-var");
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("변형 검사", None).unwrap();
    let mut tracks = Vec::new();
    for name in ["가", "나"] {
        tracks.push(b.track_full(&TrackIn { pack, name, color: 0, dynasty: 0, leader: 0, cabinet: 0, organ: 0, rail_levels: 2, key: "" }).unwrap());
    }
    for t in &tracks {
        for _ in 0..4 {
            b.row_full(*t, &common::GEO, &RowExtra::default()).unwrap();
        }
    }
    let v = b.variant("view:t", 3, tracks[0], 0, "", "", "").unwrap();
    // (줄, after, ord): after = −2이면 ord는 판 줄의 열쇠, 아니면 같은 자리의 차례(수가 같아도 줄이 아니다).
    for (row, after, ord) in [(0, -1, 0), (1, 0, 1), (2, -2, 5), (3, -2, -1), (5, -2, 2), (6, 5, 2)] {
        b.variant_row(v, row, after, ord, false, 0, 0).unwrap();
    }
    b.variant_move(v, 1, 10, 1).unwrap();
    b.variant_move(v, 2, 11, 6).unwrap();
    b.variant_group(v, "k", 0, "묶음", 0xff0000, 0, &[4, 5, 6]).unwrap();
    b.variant_group(v, "k2", 0, "다른 묶음", 0x00ff00, 0, &[0, 1, 2]).unwrap();
    b.finalize(&[]).unwrap();

    let out = rekeyed(&path, "rk-var-s", &[(1, 20), (2, 40)]);
    let db = Connection::open(&out).unwrap();
    let rows: Vec<(i64, i64, i64)> = db.prepare("SELECT row,after,ord FROM variant_rows ORDER BY row").unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap().map(|r| r.unwrap()).collect();
    assert_eq!(rows, vec![(20, -1, 0), (21, 20, 1), (22, -2, 41), (23, -2, -1), (41, -2, 22), (42, 41, 2)]);
    let moves: Vec<(i64, i64, i64)> = db.prepare("SELECT kind,ref,row FROM variant_moves ORDER BY ref").unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap().map(|r| r.unwrap()).collect();
    assert_eq!(moves, vec![(1, 10, 21), (2, 11, 42)]);
    let groups: Vec<(String, String)> = db.prepare("SELECT key,rows FROM variant_groups ORDER BY id").unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(|r| r.unwrap()).collect();
    assert_eq!(groups, vec![("k".to_owned(), "[40,41,42]".to_owned()), ("k2".to_owned(), "[20,21,22]".to_owned())]);
    assert_eq!(count(&db, "SELECT count(*) FROM pragma_foreign_key_check"), 0);
}

// ---- 아래는 과제 1c가 더한 검사: 타일 · layout 답 · 변형 · rows_near의 경계에서 열쇠를 자리로 바꿨는가 ----

use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::legacy::import_layout_value;
use archive_engine::levels::{tile_of, CHUNK_ROWS};
use archive_engine::tile::{build_tile, TileRequest};
use archive_engine::{filter::Filtered, variant::Variants};

/// 브리프의 `all()`(단계 0 ~ 14 · `max_x` 64)은 canon 하나에 약 29초라 판정 R11대로 단계를 고루 줄인다 — 그 자리에서 세는
/// 촘촘한 단계(0 · 4 · 7)와 요약을 읽는 단계(8 · 11 · 14). canon은 자료가 놓인 열을 모두 뜨므로(1b 고침) 단계마다 빠지는 사건이 없다.
fn all() -> CanonOpts {
    CanonOpts { levels: vec![0, 4, 7, 8, 11, 14], max_x: 64, queries: false }
}

/// 작은 배치 장면 a · b · c(트랙 넷 · 변형 셋 — 소속 펼치기 · 대범위 이사 · 판)를 지은 저장소.
fn plan_store(name: &str) -> PathBuf {
    let path = common::scratch(name);
    import_layout_value(&common::plans::plan(&["a", "b", "c"]), &common::plans::packs_of(&["a", "b", "c"]), &path).unwrap();
    path
}

#[test]
fn scrambled_keys_answer_the_same_layout_and_tiles() {
    let path = common::scratch("rk-built");
    common::build(&path);
    let other = scrambled(&path, "rk-built-s");
    assert_eq!(canon_store(&path, &all()).unwrap(), canon_store(&other, &all()).unwrap());
}

#[test]
fn scrambled_keys_keep_variants_groups_and_labels() {
    let path = plan_store("rk-plan");
    let other = scrambled(&path, "rk-plan-s");
    assert_eq!(canon_store(&path, &all()).unwrap(), canon_store(&other, &all()).unwrap());
}

/// 자료가 놓인 분(띠 · 칸 · 사건 · 일반 항목의 시작 · 끝) — canon과 같은 꼴로 가로 타일을 고른다.
fn content_minutes(store: &Store) -> Vec<i64> {
    let mut out = Vec::new();
    for sql in ["SELECT start,end FROM periods", "SELECT start,end FROM cells", "SELECT start,end FROM events WHERE start IS NOT NULL AND end IS NOT NULL",
        "SELECT start,end FROM items"] {
        let mut stmt = store.db.prepare(sql).unwrap();
        let mut rows = stmt.query([]).unwrap();
        while let Some(r) = rows.next().unwrap() {
            out.push(r.get::<_, i64>(0).unwrap());
            out.push(r.get::<_, i64>(1).unwrap());
        }
    }
    out.sort_unstable();
    out.dedup();
    out
}

/// 열쇠만 옮긴 저장소(띠 · 사건 · 항목 번호와 내용은 그대로)는 밖으로 내는 것이 **바이트까지** 같다 — 범위마다 모은 행을
/// 원래 `ORDER BY`의 차례(줄은 자리)로 다시 늘어놓았는가(규칙 다). layout 답 · 타일(보기마다 — 변형 하나씩 · 거르개) ·
/// `rows_near`(넓게 · 촘촘한 갈래 · 페이드) · 표본 타일 대조(`verify_store` — 전수 조사도 자리의 묶음으로 센다).
#[test]
fn scrambled_keys_give_the_same_bytes() {
    let path = plan_store("rk-bytes");
    let other = scrambled(&path, "rk-bytes-s");
    let (one, two) = (Store::open(&path).unwrap(), Store::open(&other).unwrap());
    assert!(one.rows.is_identity() && !two.rows.is_identity());
    assert_eq!(one.layout().unwrap(), two.layout().unwrap(), "layout 답");
    let packs: Vec<i64> = one.db.prepare("SELECT id FROM packs ORDER BY id").unwrap().query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
    let keys: Vec<String> = one.db.prepare("SELECT key FROM variants ORDER BY key").unwrap().query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
    assert_eq!(keys.len(), 3);
    let first_track: i64 = one.db.query_row("SELECT id FROM tracks ORDER BY ord LIMIT 1", [], |r| r.get(0)).unwrap();
    let mut views = vec![json!({})];
    views.extend(keys.iter().map(|k| json!({ "variants": [k] })));
    views.push(json!({"filter":{"tracks_off":[first_track],"min_importance":2}}));
    views.push(json!({"variants":["scope:c/sc-1"],"filter":{"tracks_off":[first_track]}}));
    let meta = |key: &str| -> i64 { one.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0)).unwrap().parse().unwrap() };
    let (min, max) = (meta("min"), meta("max"));
    let minutes = content_minutes(&one);
    let chunks = (one.rows.total() + CHUNK_ROWS - 1) / CHUNK_ROWS;
    assert!(chunks >= 2, "줄 묶음이 둘 이상이어야 트랙 경계에 걸친 묶음이 생긴다");
    let mut tiles = 0;
    for q in &views {
        let (f1, f2) = (one.filter_of(q).unwrap(), two.filter_of(q).unwrap());
        let (v1, v2) = (one.variants_of(q).unwrap(), two.variants_of(q).unwrap());
        let span = max - min;
        for i in 0..24 {
            let lo = min + span * i / 24;
            for (width, fade) in [(span, 0), (span / 9, 0), (30 * 1440, 0), (1440, 365 * 1440)] {
                let a = one.rows_near(lo, lo + width, fade, &packs, f1.as_ref(), v1.as_ref()).unwrap();
                let b = two.rows_near(lo, lo + width, fade, &packs, f2.as_ref(), v2.as_ref()).unwrap();
                assert_eq!(a, b, "rows_near {q} [{lo}, +{width}] 페이드 {fade}");
            }
        }
        for level in [0usize, 4, 7, 8, 11, 14] {
            let mut xs: std::collections::BTreeSet<i64> = minutes.iter().map(|m| tile_of(*m, level)).collect();
            xs.insert(tile_of(min, level));
            xs.insert(tile_of(max, level));
            for x in xs {
                for chunk in 0..chunks {
                    let ask = |s: &Store, f: Option<Filtered>, v: Option<Variants>| build_tile(s, &TileRequest { level, x, chunk, packs: packs.clone(), filter: f, variants: v }).unwrap();
                    let a = ask(&one, one.filter_of(q).unwrap(), v1.clone());
                    assert_eq!(a, ask(&two, two.filter_of(q).unwrap(), v2.clone()), "타일 {q} 단계 {level} x {x} 묶음 {chunk}");
                    tiles += 1;
                }
            }
        }
    }
    assert!(tiles > 1000, "견준 타일 {tiles}개");
    let check = archive_engine::verify::verify_store(&two, 120).unwrap();
    assert!(check.ok(), "표본 타일 대조: {:?}", check.first);
}

/// 변형의 줄 쌓기(`ORDER BY variant,ord,row`)는 열쇠 차례로 고른 것이라, 자리로 바꾼 뒤 다시 늘어놓아야 열쇠 = 자리 저장소와 같다 —
/// 같은 `ord`인 두 트랙의 줄 · 판 줄을 가리키는 `ord`(after = −2) · 판 줄을 가리키는 `after` · 트랙을 넘는 묶음의 `rows`.
#[test]
fn scrambled_keys_keep_variant_row_order() {
    use archive_engine::builder::{Builder, RowExtra, TrackIn};
    let path = common::scratch("rk-vorder");
    let mut b = Builder::create(&path).unwrap();
    let pack = b.pack("변형 차례", None).unwrap();
    let mut tracks = Vec::new();
    for name in ["가", "나", "판"] {
        tracks.push(b.track_full(&TrackIn { pack, name, color: 0, dynasty: 0, leader: 0, cabinet: 0, organ: 0, rail_levels: 2, key: "" }).unwrap());
    }
    for t in &tracks {
        for _ in 0..3 {
            b.row_full(*t, &common::GEO, &RowExtra::default()).unwrap(); // 가 0 ~ 2 · 나 3 ~ 5 · 판 6 ~ 8
        }
    }
    let v = b.variant("view:t", 3, tracks[2], 0, "", "", "").unwrap();
    // (줄, after, ord): 판 줄 둘 · 같은 ord 0인 가 · 나의 줄 · 판 줄(7 · 6)을 ord로 가리키며 빠지는 줄.
    for (row, after, ord) in [(6, -1, 0), (7, 6, 0), (0, -1, 0), (3, -1, 0), (1, -2, 7), (4, -2, 6)] {
        b.variant_row(v, row, after, ord, false, 0, 0).unwrap();
    }
    b.variant_group(v, "g", 0, "트랙을 넘는 묶음", 0, 0, &[1, 4, 7]).unwrap();
    b.finalize(&[]).unwrap();
    let other = scrambled(&path, "rk-vorder-s"); // 열쇠: 판 12 ~ 14 · 나 18 ~ 20 · 가 24 ~ 26 — 자리와 거꾸로
    let (one, two) = (Store::open(&path).unwrap(), Store::open(&other).unwrap());
    assert!(!two.rows.is_identity());
    let (a, b) = (one.layout().unwrap(), two.layout().unwrap());
    let order = |v: &serde_json::Value| -> Vec<(i64, i64, i64)> {
        v["variants"][0]["rows"].as_array().unwrap().iter().map(|r| (r["row"].as_i64().unwrap(), r["after"].as_i64().unwrap(), r["ord"].as_i64().unwrap())).collect()
    };
    assert_eq!(order(&a), vec![(0, -1, 0), (3, -1, 0), (6, -1, 0), (7, 6, 0), (4, -2, 6), (1, -2, 7)]);
    assert_eq!(order(&b), order(&a), "자리로 바꾼 뒤의 차례");
    assert_eq!(b["variants"][0]["groups"][0]["rows"], json!([1, 4, 7]));
    assert_eq!(a, b, "layout 답 전체");
}

// ---- 아래는 과제 2가 더한 검사: 조회 명령이 받는 줄 · 내는 줄을 경계에서 자리로 바꿨는가 ----

#[test]
fn scrambled_keys_answer_the_same_queries() {
    let path = common::scratch("rk-q");
    import_layout_value(&common::plans::plan(&["a", "b", "c"]), &common::plans::packs_of(&["a", "b", "c"]), &path).unwrap();
    let other = scrambled(&path, "rk-q-s");
    let o = CanonOpts { levels: vec![0, 7, 8, 14], max_x: 16, queries: true };
    assert_eq!(canon_store(&path, &o).unwrap()["queries"], canon_store(&other, &o).unwrap()["queries"]);
}

fn ids_of(s: &Store, sql: &str) -> Vec<i64> {
    s.db.prepare(sql).unwrap().query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect()
}

fn texts_of(s: &Store, sql: &str) -> Vec<String> {
    s.db.prepare(sql).unwrap().query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect()
}

/// 물음에 보기(변형 · 거르개)를 얹는다.
fn viewed(mut q: serde_json::Value, view: &serde_json::Value) -> serde_json::Value {
    for (k, v) in view.as_object().unwrap() {
        q[k] = v.clone();
    }
    q
}

/// 보기: 기본 · 변형 하나씩 · 첫 트랙을 끈 거르개 · 중요도 · 분류 거르개 · 변형 + 마지막 트랙을 끈 거르개.
fn query_views(s: &Store) -> Vec<serde_json::Value> {
    let tracks = ids_of(s, "SELECT id FROM tracks ORDER BY ord,id");
    let keys = texts_of(s, "SELECT key FROM variants ORDER BY key");
    let mut views = vec![json!({})];
    views.extend(keys.iter().map(|k| json!({ "variants": [k] })));
    views.push(json!({"filter":{"tracks_off":[tracks[0]]}}));
    views.push(json!({"filter":{"min_importance":2,"cats_off":[1]}}));
    views.push(json!({"variants":[keys[0]],"filter":{"tracks_off":[tracks[tracks.len() - 1]]}}));
    views
}

/// 줄을 받거나 내는 조회 명령의 물음들(`list`의 이어 받기 · `range`는 검사에서 따로) — 모든 자리 · 모든 띠 · 모든 사건 · 낱말.
fn query_requests(s: &Store) -> Vec<serde_json::Value> {
    let meta = |key: &str| -> i64 { s.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0)).unwrap().parse().unwrap() };
    let (min, max) = (meta("min"), meta("max"));
    let span = max - min;
    let total = s.rows.total();
    let packs = ids_of(s, "SELECT id FROM packs ORDER BY id");
    let bands = ids_of(s, "SELECT id FROM periods ORDER BY id");
    let band_uids = texts_of(s, "SELECT DISTINCT uid FROM periods WHERE uid<>'' ORDER BY uid");
    let mut out = Vec::new();
    for view in &query_views(s) {
        for k in 0..8 {
            let lo = min + span * k / 8;
            for (width, fade) in [(span, 0), (span / 7, 0), (1440, 365 * 1440)] {
                out.push(viewed(json!({"op":"rows_near","near":[lo, lo + width],"far":[lo - width, lo + 2 * width],"fade":fade,"packs":packs}), view));
            }
        }
        out.push(viewed(json!({"op":"row_labels","rows":(-1..=total).collect::<Vec<_>>()}), view));
        for row in -1..=total {
            out.push(viewed(json!({"op":"events_in","row":row,"lo":min,"hi":max + 1,"limit":200}), view));
            out.push(viewed(json!({"op":"events_in","row":row,"lo":min,"hi":max + 1,"limit":5,"after":3}), view));
        }
        for b in &bands {
            out.push(viewed(json!({"op":"events_in","band":b,"lo":min,"hi":max + 1,"limit":200}), view));
            let (start, end): (i64, i64) = s.db.query_row("SELECT start,end FROM periods WHERE id=?1", [b], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
            out.push(viewed(json!({"op":"echo","spots":[{"band":b,"start":start,"end":end}]}), view));
        }
        for uid in &band_uids {
            out.push(viewed(json!({"op":"echo","spots":[{"uid":uid,"start":min,"end":max}],"limit":50}), view));
        }
        out.push(viewed(json!({"op":"echo","spots":[{"band":bands[0],"start":min,"end":min + span / 3},{"band":bands[bands.len() / 2],"start":min + span / 4,"end":max}]}), view));
        for k in 0..6 {
            let at = min + span * k / 6;
            out.push(viewed(json!({"op":"same_year","at":at,"window":0}), view));
            out.push(viewed(json!({"op":"same_year","at":at,"end":at + span / 20,"window":5 * 525_600}), view));
            out.push(viewed(json!({"op":"search_year","at":at,"end":at + span / 20,"limit":200}), view));
        }
        for word in ["가람", "나라", "사건", "일", "임금", "모임", "늦은", "1"] {
            out.push(viewed(json!({"op":"search","text":word}), view));
            out.push(viewed(json!({"op":"search","text":word,"after":40}), view));
            out.push(viewed(json!({"op":"search","text":word,"kinds":archive_engine::query::SEARCH_KINDS,"limit":200}), view));
            out.push(viewed(json!({"op":"search","text":word,"kinds":["event","period","cell"],"limit":4,"after":2}), view));
        }
        out.push(viewed(json!({"op":"table","with_periods":true,"limit":1000}), view));
        out.push(viewed(json!({"op":"lens_names","lens":"local"}), view));
    }
    for id in ids_of(s, "SELECT id FROM events ORDER BY id") {
        out.push(json!({"op":"event","id":id}));
        out.push(json!({"op":"uid_of","kind":"event","id":id}));
    }
    for b in &bands {
        out.push(json!({"op":"uid_of","kind":"band","id":b}));
        out.push(json!({"op":"cells_of","band":b}));
    }
    let mut uids = texts_of(s, "SELECT uid FROM periods WHERE uid<>'' UNION SELECT uid FROM events WHERE uid<>'' ORDER BY 1");
    uids.push("없는/이름".to_owned());
    for uid in &uids {
        out.push(json!({"op":"id_of","uid":uid}));
    }
    out.push(json!({"op":"ids_of","uids":uids}));
    out.push(json!({"op":"scopes"}));
    out
}

fn answer(s: &Store, q: &serde_json::Value) -> String {
    s.call(q).map(|v| v.to_string()).unwrap_or_else(|e| format!("실패: {e}"))
}

/// 조회 명령마다 답이 **바이트까지** 같은가 — 열쇠만 옮겨 번호 · 내용이 같으므로 같아야 한다. 받는 줄(`row` · `lane` · `rows`)은
/// 자리로 읽고, 내는 줄은 자리로 내며, 범위마다 모은 답은 원래 차례(줄은 자리)로 다시 늘어놓았는가(규칙 가 ~ 다).
/// `list`는 이어 받기를 끝까지 따라가고, `range`(옛 줄 범위 조회)는 모든 자리 · 너비에서 견준다.
#[test]
fn scrambled_keys_give_the_same_query_bytes() {
    let path = plan_store("rk-qb");
    let other = scrambled(&path, "rk-qb-s");
    let (one, two) = (Store::open(&path).unwrap(), Store::open(&other).unwrap());
    assert!(one.rows.is_identity() && !two.rows.is_identity());
    let requests = query_requests(&one);
    for q in &requests {
        assert_eq!(answer(&one, q), answer(&two, q), "{q}");
    }
    assert!(requests.len() > 1000, "물음 {}개", requests.len());
    let total = one.rows.total();
    let meta =|key: &str| -> i64 { one.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0)).unwrap().parse().unwrap() };
    let (lo, hi) = (meta("min"), meta("max"));
    let views = query_views(&one);
    let mut pages = 0;
    for view in [&views[0], &views[1], &views[views.len() - 3]] {
        for lane in 0..total {
            for lanes in [1, 3, 8, 32] {
                for order in ["id", "start"] {
                    let mut after = serde_json::Value::Null;
                    loop {
                        let q = viewed(json!({"op":"list","lo":lo,"hi":hi,"lane":lane,"lanes":lanes,"order":order,"limit":25,"after":after}), view);
                        let a = one.call(&q).unwrap();
                        assert_eq!(a, two.call(&q).unwrap(), "{q}");
                        pages += 1;
                        if a["has_more"] != true {
                            break;
                        }
                        after = a["next"].clone();
                    }
                }
            }
        }
    }
    assert!(pages > 500, "목록 쪽 {pages}개");
    for lane in -1..=total {
        for lanes in [1, 3, 8, 32] {
            for (after, limit) in [(0, 1801), (40, 6)] {
                let ask = |s: &Store| s.range(lo, hi, lane, lanes, after, limit).map(|v| json!(v)).map_err(|e| e.to_string());
                assert_eq!(ask(&one), ask(&two), "range 줄 {lane} 너비 {lanes} 다음 {after}");
            }
        }
    }
}

/// 이름에 번호를 싣는 열쇠(`id` · `band` · `event` · `track` · `pack` · `source` · `echoIds`)에 정수가 남았는가.
/// 줄 이름 칸의 후보(`row_labels`의 `items`)는 배치 파일에 적힌 글을 그대로 싣는 내용이라 보지 않는다 — 그 안의 `track`은
/// 배치의 트랙 순번(저장소 번호가 아니다)이다.
fn numbers_in_queries(v: &serde_json::Value, at: &str, out: &mut Vec<String>) {
    const NUMBERED: [&str; 7] = ["id", "band", "event", "track", "pack", "source", "echoIds"];
    match v {
        serde_json::Value::Object(map) => {
            for (k, child) in map {
                if k == "items" && at.starts_with("queries.row_labels.") {
                    continue;
                }
                let numbered = child.is_i64() || child.as_array().is_some_and(|l| l.iter().any(serde_json::Value::is_i64));
                if NUMBERED.contains(&k.as_str()) && numbered {
                    out.push(format!("{at}.{k} = {child}"));
                }
                numbers_in_queries(child, &format!("{at}.{k}"), out);
            }
        }
        serde_json::Value::Array(list) => list.iter().enumerate().for_each(|(i, child)| numbers_in_queries(child, &format!("{at}[{i}]"), out)),
        _ => {}
    }
}

/// 조회 목록이 번호를 하나도 흘리지 않고(사건 · 띠 · 트랙 · 자료집 → uid · 열쇠 · 글자 id), 비어서 같은 것이 아닌가.
#[test]
fn canon_queries_leak_no_numbers() {
    let path = plan_store("rk-qn");
    let canon = canon_store(&path, &CanonOpts { levels: vec![], max_x: 0, queries: true }).unwrap();
    let q = &canon["queries"];
    let mut found = Vec::new();
    numbers_in_queries(q, "queries", &mut found);
    assert!(found.is_empty(), "번호가 남았습니다: {:?}", &found[..found.len().min(8)]);
    // 이어 받기 표: 옛 검색(사건만 — 줄에 갈래 `kind`가 없다)은 사건 uid, 목록은 [시작, 사건 uid]. 낱말은 저장소 내용에서 고른다(과제 5d 얹힌 몫 8).
    let search = q["search"].as_object().unwrap();
    let plain: Vec<&String> = search.keys().filter(|w| search[*w]["items"].as_array().unwrap().iter().all(|i| i.get("kind").is_none())).collect();
    assert_eq!(plain.len(), 3, "옛 검색 낱말: {:?}", search.keys().collect::<Vec<_>>());
    for word in plain {
        assert!(!search[word]["items"].as_array().unwrap().is_empty(), "{word}: 빈 답");
        assert!(search[word]["next"].is_string() || search[word]["next"].is_null(), "{word}: {}", search[word]["next"]);
    }
    let first = &q["list"]["기본"][0];
    assert!(first["next"][1].is_string(), "목록의 이어 받기: {}", first["next"]);
    assert_eq!(first["has_more"], true, "목록이 둘째 쪽까지 이어진다");
    assert!(q["list"]["기본"][1]["items"].as_array().is_some_and(|l| !l.is_empty()));
    // 빈 답으로 같은 것이 아니다 — 명령마다 무언가 담겼다.
    let names = ["rows_near", "row_labels", "events_in", "same_year", "echo", "search", "variant_views", "search_words", "search_plain", "list", "event",
        "id_of", "uid_of", "ids_of", "cells_of", "scopes", "entity", "range", "verify_store", "info"];
    assert_eq!(q.as_object().unwrap().keys().cloned().collect::<std::collections::BTreeSet<_>>(), names.iter().map(|s| s.to_string()).collect());
    // 고른 낱말의 수(과제 6 얹힌 몫 5) — 옛 검색 셋 · 거르개 하나 · 넓힌 검색 둘(옛 검색 낱말과 겹치지 않는다 — 아래 `search`가 다섯 열쇠).
    assert_eq!(q["search_words"], json!({"plain":3,"filtered":true,"wide":2}));
    assert_eq!(q["event"].as_object().unwrap().len(), 3);
    assert_eq!(q["echo"].as_object().unwrap().len(), 3);
    assert_eq!(q["cells_of"].as_object().unwrap().len(), 3);
    assert_eq!(q["search"].as_object().unwrap().len(), 5);
    let db = Connection::open(&path).unwrap();
    assert_eq!(q["entity"].as_object().unwrap().len() as i64, count(&db, "SELECT count(*) FROM entities"));
    assert_eq!(q["row_labels"]["기본"]["labels"].as_array().unwrap().len() as i64, count(&db, "SELECT count(*) FROM rows"));
    assert_eq!(q["events_in"]["tracks"].as_object().unwrap().keys().cloned().collect::<Vec<_>>(), vec!["__board:view:a1", "ta", "tb", "tc"]);
    assert!(q["events_in"]["tracks"]["ta"][0]["items"].as_array().unwrap().len() > 100, "ta 첫 줄의 사건");
    assert!(search.values().any(|v| v["items"].as_array().unwrap().iter().any(|i| i["kind"] == "cell")), "넓힌 검색이 칸 이름을 찾는다");
    // 변형을 하나씩 켠 보기마다 띠 · 사건 · 낱말로 묻는 답이 같은 꼴로 실린다.
    let views = q["variant_views"].as_object().unwrap();
    assert_eq!(views.keys().cloned().collect::<Vec<_>>(), vec!["host:a/ta-host", "scope:c/sc-1", "view:a1"]);
    for (key, v) in views {
        assert_eq!(v.as_object().unwrap().keys().cloned().collect::<Vec<_>>(), vec!["echo", "events_in_bands", "same_year", "search"], "{key}");
        assert_eq!(v["search"].as_object().unwrap().len(), 5, "{key}");
    }
    assert!(q["search_plain"]["items"].as_array().is_some_and(|l| !l.is_empty()));
    assert!(q["range"].as_array().unwrap().iter().all(|l| !l.as_array().unwrap().is_empty()));
    assert_eq!(q["verify_store"], json!({"missing":0,"dup":0}));
    assert_eq!(q["info"]["pack_events"].as_object().unwrap().keys().cloned().collect::<Vec<_>>(), vec!["a", "b", "c"]);
    assert!(q["same_year"].as_object().unwrap().values().all(|v| !v["tracks"].as_array().unwrap().is_empty()));
}

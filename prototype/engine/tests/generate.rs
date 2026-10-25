//! 가상 자료 생성기 2: 규칙과 씨앗이 고정이라 언제 만들어도 같은 자료가 나와야 한다.
use archive_engine::generate::generate;
use archive_engine::Store;
use rusqlite::types::ValueRef;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-generate-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("fixtures")
}

/// 표의 내용을 기본 키 순서로 훑어 만든 지문.
fn fingerprint(store: &Store) -> String {
    let mut hash = Sha256::new();
    for sql in [
        "SELECT * FROM packs ORDER BY id", "SELECT * FROM tracks ORDER BY id", "SELECT * FROM rows ORDER BY id", "SELECT * FROM epochs ORDER BY id",
        "SELECT * FROM periods ORDER BY id", "SELECT * FROM cells ORDER BY id", "SELECT * FROM events ORDER BY id",
        "SELECT * FROM summaries ORDER BY level,lane,bucket,pack", "SELECT * FROM span_bounds ORDER BY id", "SELECT key,value FROM meta WHERE key NOT IN ('made_ms') ORDER BY key",
    ] {
        let mut stmt = store.db.prepare(sql).unwrap();
        let columns = stmt.column_count();
        let mut rows = stmt.query([]).unwrap();
        while let Some(row) = rows.next().unwrap() {
            for i in 0..columns {
                match row.get_ref(i).unwrap() {
                    ValueRef::Null => hash.update([0]),
                    ValueRef::Integer(v) => hash.update(v.to_le_bytes()),
                    ValueRef::Real(v) => hash.update(v.to_le_bytes()),
                    ValueRef::Text(v) | ValueRef::Blob(v) => { hash.update((v.len() as u64).to_le_bytes()); hash.update(v) }
                }
            }
        }
    }
    format!("{:x}", hash.finalize())
}

#[test]
fn 두_번_만들어도_같은_자료가_나오고_기존_저장소는_덮어쓰지_않는다() {
    let (a, b) = (scratch("same-a"), scratch("same-b"));
    generate(&a.join("archive.db"), 2000, &fixtures(), true).unwrap();
    generate(&b.join("archive.db"), 2000, &fixtures(), true).unwrap();
    let (sa, sb) = (Store::open(&a.join("archive.db")).unwrap(), Store::open(&b.join("archive.db")).unwrap());
    assert_eq!(fingerprint(&sa), fingerprint(&sb));
    assert_eq!(sa.verify_files().unwrap()["files"], 3);
    drop((sa, sb));
    assert!(generate(&a.join("archive.db"), 2000, &fixtures(), true).is_err());
    std::fs::remove_dir_all(a).unwrap();
    std::fs::remove_dir_all(b).unwrap();
}

#[test]
fn 섞어_넣은_특수한_사건의_수가_규칙과_같다() {
    let dir = scratch("counts");
    let report = generate(&dir.join("archive.db"), 2000, &fixtures(), true).unwrap();
    let s = Store::open(&dir.join("archive.db")).unwrap();
    let count = |sql: &str| -> i64 { s.db.query_row(sql, [], |r| r.get(0)).unwrap() };
    assert_eq!(count("SELECT count(*) FROM events"), 2000);
    assert_eq!(count("SELECT count(*) FROM events WHERE start IS NULL"), 1); // 1009의 배수
    assert_eq!(count("SELECT count(*) FROM events WHERE importance=3"), 20); // 97의 배수
    assert_eq!(count("SELECT count(*) FROM events WHERE importance=2"), 283); // 7의 배수 가운데 97의 배수가 아닌 것
    assert_eq!(count("SELECT count(*) FROM events WHERE end-start=200000*1440"), 2); // 997의 배수
    assert_eq!(count("SELECT count(*) FROM events WHERE start/1440=18500"), 200); // 10의 배수는 같은 날
    assert_eq!(count("SELECT count(*) FROM events WHERE lo<start"), 19); // 101의 배수는 이설 폭 (날짜 미정 1009는 101의 배수가 아님)
    assert_eq!(count("SELECT count(*) FROM events WHERE pack=8"), 250);
    assert_eq!(count("SELECT count(*) FROM tracks WHERE pack=8"), 0, "덧붙임 기록집은 제 트랙이 없다");
    assert_eq!(count("SELECT count(*) FROM packs"), 8);
    assert_eq!(count("SELECT count(*) FROM tracks"), 56);
    assert_eq!(count("SELECT count(*) FROM epochs"), 12);
    let rows = count("SELECT count(*) FROM rows");
    assert_eq!(rows, 252);
    assert_eq!(count("SELECT count(*) FROM events WHERE lane<0 OR lane>=252"), 0);
    assert_eq!(report["rows"], 252);
    assert_eq!(report["events"], 2000);
    assert!(report["periods"].as_i64().unwrap() > 20_000, "띠 수만 개: {}", report["periods"]);
    assert!(report["cells"].as_i64().unwrap() > 200_000, "칸 수십만 개: {}", report["cells"]);
    assert_eq!(s.info().unwrap()["meta"]["seed"], json!("20260921"));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 같은_줄의_띠는_겹치지_않고_칸은_제_띠_안에_있다() {
    let dir = scratch("bands");
    generate(&dir.join("archive.db"), 100, &fixtures(), true).unwrap();
    let s = Store::open(&dir.join("archive.db")).unwrap();
    let count = |sql: &str| -> i64 { s.db.query_row(sql, [], |r| r.get(0)).unwrap() };
    assert_eq!(count("SELECT count(*) FROM periods a JOIN periods b ON a.row=b.row AND a.id<b.id AND a.start<=b.end AND b.start<=a.end"), 0);
    assert_eq!(count("SELECT count(*) FROM cells c JOIN periods p ON p.id=c.period WHERE c.start<p.start OR c.end>p.end"), 0);
    assert_eq!(count("SELECT count(*) FROM cells a JOIN cells b ON a.period=b.period AND a.kind=b.kind AND a.id<b.id AND a.start<=b.end AND b.start<=a.end"), 0, "같은 단의 칸끼리 겹치지 않는다");
    assert!(count("SELECT count(*) FROM periods WHERE fuzzy<>0") > 100);
    assert!(count("SELECT count(*) FROM cells WHERE kind=0") > 1000 && count("SELECT count(*) FROM cells WHERE kind=3") > 1000);
    // 왕조 단이 없는 줄에는 왕조 칸이 없다.
    assert_eq!(count("SELECT count(*) FROM cells c JOIN periods p ON p.id=c.period JOIN rows r ON r.id=p.row WHERE c.kind=0 AND r.dyn_top<0"), 0);
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

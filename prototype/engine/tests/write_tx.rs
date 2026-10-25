//! 쓰기 거래(계획 P4 과제 3): 같은 파일에 쓰기 연결을 따로 열어 한 거래로 쓰고, 실패하면 파일이 그대로이며,
//! 쓰는 동안 앱의 조회 · 타일은 옛 답을 곧바로 받고, `STORE` 잠금은 COMMIT 바로 앞에서만 쥐어 COMMIT 뒤 저장소를 다시 연다.
//! 전역 저장소(`archive_call` · `STORE`)를 만지는 검사는 서로 밟지 않게 `serial()`로 줄 세운다.
mod common;
use archive_engine::rowmap::rekey_track;
use archive_engine::write::{fail_point, set_fail_point, write, write_with};
use archive_engine::{archive_call, archive_free, archive_free_bytes, archive_tile, with_store_write, Store, DAY};
use rusqlite::{Connection, OpenFlags, OptionalExtension, TransactionBehavior};
use serde_json::{json, Value};
use std::cell::{Cell, RefCell};
use std::ffi::{CStr, CString};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

static GLOBAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    GLOBAL.lock().unwrap_or_else(|e| e.into_inner())
}

/// `archive_call`에 JSON 한 줄을 보내고 답 JSON을 받는다.
fn call(request: Value) -> Value {
    let text = CString::new(request.to_string()).unwrap();
    unsafe {
        let answer = archive_call(text.as_ptr());
        let value = serde_json::from_slice(CStr::from_ptr(answer).to_bytes()).unwrap();
        archive_free(answer);
        value
    }
}

/// `archive_tile`이 주는 타일 바이트(실패하면 None).
fn tile() -> Option<Vec<u8>> {
    let request = CString::new(r#"{"level":8,"x":0,"chunk":0,"packs":[1,2]}"#).unwrap();
    let mut len = 0usize;
    unsafe {
        let ptr = archive_tile(request.as_ptr(), &mut len);
        if ptr.is_null() {
            return None;
        }
        let copy = std::slice::from_raw_parts(ptr, len).to_vec();
        archive_free_bytes(ptr, len);
        Some(copy)
    }
}

/// 조회 한 번: 줄 8개 전체의 사건 목록(자리로 말한다). 답의 `data`만 — 겉의 `db_ms`는 부를 때마다 다르다.
fn list() -> Value {
    let answer = call(json!({"op":"list","lo":-1000 * DAY,"hi":1000 * DAY,"lane":0,"lanes":8,"limit":1000}));
    assert_eq!(answer["ok"], true, "{answer}");
    answer["data"].clone()
}

fn open(path: &Path) -> Value {
    let answer = call(json!({"op":"open","path":path.to_str().unwrap()}));
    assert_eq!(answer["ok"], true, "{answer}");
    answer
}

/// 다른 스레드에서 돌려 제때 끝나는지 본다 — 잠금이 풀리지 않았다면 멈추는 대신 실패한다.
fn within<T: Send + 'static>(limit: Duration, f: impl FnOnce() -> T + Send + 'static) -> T {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(f());
    });
    rx.recv_timeout(limit).expect("제때 끝나지 않았다 — 잠금이 풀리지 않았을 수 있다")
}

fn meta_of(path: &Path, key: &str) -> Option<String> {
    Connection::open(path).unwrap().query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get(0)).optional().unwrap()
}

fn put_probe(tx: &rusqlite::Transaction, value: &str) -> archive_engine::Result<()> {
    tx.execute("INSERT OR REPLACE INTO meta(key,value) VALUES('probe',?1)", [value])?;
    Ok(())
}

#[test]
fn 빈_걸음의_쓰기는_commit되고_다시_연_저장소에서_보인다() {
    let path = common::scratch("wtx-commit");
    common::build(&path);
    assert_eq!(meta_of(&path, "probe"), None);
    // 걸음 → COMMIT 앞(before_commit) → COMMIT 차례다. COMMIT 앞에서는 다른 연결에 아직 옛 저장소로 보인다.
    let order = RefCell::new(Vec::new());
    let (out, held) = write_with(
        &path,
        |tx| {
            order.borrow_mut().push("step");
            put_probe(tx, "1")?;
            Ok(41)
        },
        || {
            order.borrow_mut().push("before_commit");
            meta_of(&path, "probe").is_none()
        },
    )
    .unwrap();
    assert_eq!(out, 41, "걸음이 낸 값은 그대로 돌아온다");
    assert!(held, "before_commit은 COMMIT 앞에서 불렸다(그때 다른 연결은 쓴 것을 못 본다) — 돌려준 것은 그대로 온다");
    assert_eq!(*order.borrow(), ["step", "before_commit"]);
    // 다시 연 저장소에서 보인다.
    assert_eq!(Store::open(&path).unwrap().info().unwrap()["meta"]["probe"], "1");
    // before_commit 없는 짧은 길 — 같은 자리를 덮는다.
    let again = write(&path, |tx| {
        put_probe(tx, "2")?;
        Ok("끝")
    })
    .unwrap();
    assert_eq!(again, "끝");
    assert_eq!(meta_of(&path, "probe").as_deref(), Some("2"));
    // 없는 파일은 만들지 않는다.
    let none = common::scratch("wtx-none");
    assert!(write(&none, |_| Ok(())).is_err());
    assert!(!none.exists(), "쓰기 연결은 저장소를 새로 만들지 않는다");
}

#[test]
fn 걸음_도중_실패하면_거래를_되돌려_파일_지문이_그대로다() {
    let _g = serial();
    let path = common::scratch("wtx-fail");
    common::build(&path);
    let before = common::sha256_file(&path);
    let journal = path.with_extension("db-journal");
    let called = Cell::new(false);
    // 실제로 쓴 뒤에 실패 지점에서 멈춘다.
    set_fail_point(Some("mid"));
    let result = write_with(
        &path,
        |tx| {
            tx.execute("UPDATE events SET title='바뀐 제목' WHERE id<=100", [])?;
            put_probe(tx, "x")?;
            fail_point("mid")?;
            put_probe(tx, "y")?;
            Ok(())
        },
        || called.set(true),
    );
    let why = result.err().expect("실패 지점에서 멈춰야 한다").to_string();
    assert!(why.contains("mid"), "{why}");
    assert!(!called.get(), "실패하면 before_commit(잠금)까지 가지 않는다");
    assert_eq!(common::sha256_file(&path), before, "실패하면 파일이 쓰기 전과 같다");
    assert!(!journal.exists(), "되돌린 뒤 저널이 남지 않는다");
    assert_eq!(meta_of(&path, "probe"), None);
    // 이름이 다른 실패 지점은 걸리지 않는다 — 그대로 COMMIT되어 파일이 바뀐다.
    set_fail_point(Some("other"));
    write(&path, |tx| {
        fail_point("mid")?;
        put_probe(tx, "ok")
    })
    .unwrap();
    set_fail_point(None);
    assert_ne!(common::sha256_file(&path), before);
    assert_eq!(meta_of(&path, "probe").as_deref(), Some("ok"));
    // 실패 지점은 지우면 걸리지 않는다.
    fail_point("mid").unwrap();

    // 열린 저장소에 쓰는 길(with_store_write)도 같다 — 파일은 그대로 · 저장소는 열린 채 · 잠금은 풀려 있다.
    let path = common::scratch("wtx-fail-open");
    common::build(&path);
    open(&path);
    let before = common::sha256_file(&path);
    let list_before = list();
    set_fail_point(Some("mid"));
    let result = with_store_write(|tx| {
        tx.execute("UPDATE events SET title='바뀐 제목' WHERE id<=100", [])?;
        fail_point("mid")?;
        Ok(())
    });
    set_fail_point(None);
    assert!(result.err().expect("실패해야 한다").to_string().contains("mid"));
    assert_eq!(common::sha256_file(&path), before);
    let answer = within(Duration::from_secs(2), || call(json!({"op":"info"})));
    assert_eq!(answer["ok"], true, "{answer}");
    assert_eq!(list(), list_before, "실패한 쓰기 뒤에도 같은 답");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[test]
fn 외래_열쇠를_어긴_쓰기는_commit이_거르고_파일이_그대로다() {
    let _g = serial();
    const VIOLATE: &str = "INSERT INTO events(pack,lane,importance,title,body) VALUES(1,9999,1,'떠 있는 사건','본문')";
    let path = common::scratch("wtx-fk");
    common::build(&path);
    let before = common::sha256_file(&path);
    let called = Cell::new(false);
    let lock = Mutex::new(());
    // ① 없는 줄(9999)을 가리키는 사건 — 문장은 지나가고(위반은 COMMIT까지 미뤄진다) COMMIT이 거른다. 저장소 전체를 훑는 확인은 없다.
    //    before_commit은 COMMIT 바로 앞이라 불렸고, COMMIT이 실패해도 그 잠금은 Err와 함께 놓였다.
    let result = write_with(
        &path,
        |tx| {
            tx.execute(VIOLATE, [])?;
            Ok(())
        },
        || {
            called.set(true);
            lock.lock().unwrap()
        },
    );
    let why = result.err().expect("외래 열쇠를 어기면 Err여야 한다").to_string();
    assert!(why.contains("FOREIGN KEY"), "COMMIT이 외래 열쇠 위반으로 되돌렸다고 알려 준다: {why}");
    assert!(called.get(), "COMMIT 바로 앞(before_commit)까지는 갔다");
    assert!(lock.try_lock().is_ok(), "COMMIT이 실패해도 before_commit이 쥔 것은 놓였다");
    assert_eq!(common::sha256_file(&path), before, "되돌렸으므로 파일이 그대로다");
    // ② 걸음이 직접 미뤄 달라고 해도(rekey 같은 길) 같다.
    let result = write(&path, |tx| {
        tx.execute_batch("PRAGMA defer_foreign_keys=ON")?;
        tx.execute(VIOLATE, [])?;
        Ok(())
    });
    assert!(result.is_err());
    assert_eq!(common::sha256_file(&path), before);
    // ③ 열린 저장소에 쓰는 길도 같다 — Err · 파일 그대로 · 저장소는 열린 채 · 잠금은 풀려 있다.
    let open_path = common::scratch("wtx-fk-open");
    common::build(&open_path);
    open(&open_path);
    let open_before = common::sha256_file(&open_path);
    let list_before = list();
    let result = with_store_write(|tx| {
        tx.execute(VIOLATE, [])?;
        Ok(())
    });
    assert!(result.err().expect("외래 열쇠를 어기면 Err여야 한다").to_string().contains("FOREIGN KEY"));
    assert_eq!(common::sha256_file(&open_path), open_before);
    let answer = within(Duration::from_secs(2), || call(json!({"op":"info"})));
    assert_eq!(answer["ok"], true, "{answer}");
    assert_eq!(list(), list_before);
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
    // ④ 같은 거래 안에서 위반을 풀면(미룬 위반이 COMMIT 때 없다) COMMIT된다.
    write(&path, |tx| {
        tx.execute(VIOLATE, [])?;
        tx.execute("DELETE FROM events WHERE lane=9999", [])?;
        Ok(())
    })
    .unwrap();
    // 파일은 멀쩡히 다시 열린다 — 어긋남도 없다.
    let db = Connection::open(&path).unwrap();
    let bad: i64 = db.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| r.get(0)).unwrap();
    assert_eq!(bad, 0);
    assert_eq!(db.query_row("SELECT count(*) FROM events", [], |r| r.get::<_, i64>(0)).unwrap(), 513);
    assert!(Store::open(&path).is_ok());
}

#[test]
fn 쓰는_동안_다른_스레드는_옛_답을_곧바로_받고_끝난_뒤에는_새_답을_받는다() {
    let _g = serial();
    let path = common::scratch("wtx-live");
    common::build(&path);
    // 0. 열린 저장소가 없으면 Err — 걸음은 돌지 않는다.
    call(json!({"op":"close"}));
    let ran = Cell::new(false);
    let none = with_store_write(|_| {
        ran.set(true);
        Ok(())
    });
    assert!(none.err().expect("열린 저장소가 없으면 Err").to_string().contains("열리지 않았습니다"));
    assert!(!ran.get());
    // 1. 연다. 아직 probe가 없고, 타일 · 목록의 옛 답을 받아 둔다.
    open(&path);
    assert_eq!(call(json!({"op":"info"}))["data"]["meta"]["probe"], Value::Null);
    let tile_before = tile().expect("타일");
    let list_before = list();
    assert!(!list_before["items"].as_array().unwrap().is_empty());

    // 2. 다른 스레드가 600ms 걸려 쓴다(meta에 probe · 사건 제목을 바꾼다). 그동안 이쪽이 묻는다 — 옛 답이 곧바로 와야 한다.
    let (started_tx, started_rx) = mpsc::channel();
    let writer = std::thread::spawn(move || {
        with_store_write(|tx| {
            put_probe(tx, "new")?;
            tx.execute("UPDATE events SET title='바뀐 제목' WHERE id<=300", [])?;
            started_tx.send(()).unwrap();
            std::thread::sleep(Duration::from_millis(600));
            Ok(7)
        })
    });
    started_rx.recv_timeout(Duration::from_secs(5)).expect("쓰기가 시작되지 않았다");
    let started = Instant::now();
    let during = call(json!({"op":"info"}));
    let info_took = started.elapsed();
    assert!(info_took < Duration::from_millis(300), "info가 쓰기에 막혔다: {info_took:?}");
    assert_eq!(during["ok"], true, "{during}");
    assert_eq!(during["data"]["meta"]["probe"], Value::Null, "쓰는 동안은 옛 답이다");
    let started = Instant::now();
    let tile_during = tile().expect("쓰는 동안에도 타일이 나온다");
    let tile_took = started.elapsed();
    assert!(tile_took < Duration::from_millis(300), "타일이 쓰기에 막혔다: {tile_took:?}");
    assert_eq!(tile_during, tile_before, "쓰는 동안 타일은 옛 답이다");
    let started = Instant::now();
    assert_eq!(list(), list_before, "쓰는 동안 조회는 옛 답이다");
    assert!(started.elapsed() < Duration::from_millis(300));
    eprintln!("쓰기 600ms 동안 info {info_took:?} · 타일 {tile_took:?} · 목록 {:?}", started.elapsed());
    assert!(!writer.is_finished(), "묻는 동안에도 쓰기는 아직 진행 중이었다(재는 틀이 맞다)");

    // 3. 끝난 뒤에는 새 답이다 — 쓴 값이 보이고, 타일 · 목록도 새 것이다.
    assert_eq!(writer.join().unwrap().unwrap(), 7);
    let after = call(json!({"op":"info"}));
    assert_eq!(after["data"]["meta"]["probe"], "new");
    assert_ne!(tile().expect("타일"), tile_before, "끝난 뒤에는 새 타일이다");
    assert_ne!(list(), list_before, "끝난 뒤에는 새 목록이다");
    assert_eq!(meta_of(&path, "probe").as_deref(), Some("new"));

    // 3.5. 쓰기가 COMMIT과 다시 열기를 되풀이하는 동안 읽는 쪽이 한 번도 실패하지 않는다(COMMIT의 배타 잠금이 읽기에 'database is locked'로 새지 않는다).
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    let reader = std::thread::spawn(move || {
        let mut rounds = 0;
        while !flag.load(Ordering::SeqCst) {
            let answer = call(json!({"op":"info"}));
            assert_eq!(answer["ok"], true, "{answer}");
            assert_eq!(list()["items"].as_array().unwrap().len(), 503 /* 날짜 있는 사건 */);
            assert!(tile().is_some(), "타일이 실패했다");
            rounds += 1;
        }
        rounds
    });
    for round in 0..20 {
        with_store_write(|tx| {
            put_probe(tx, &round.to_string())?;
            std::thread::sleep(Duration::from_millis(15));
            Ok(())
        })
        .unwrap();
    }
    stop.store(true, Ordering::SeqCst);
    let rounds = reader.join().unwrap();
    assert!(rounds >= 5, "읽는 쪽이 쓰기 사이에 {rounds}번만 돌았다");
    assert_eq!(call(json!({"op":"info"}))["data"]["meta"]["probe"], "19");
    eprintln!("쓰기 20번 동안 읽기 {rounds}바퀴 — 실패 0");

    // 4. COMMIT 뒤에 저장소(RowMap)를 다시 연다 — 줄 열쇠를 모두 갈라 놓아도(열쇠 ≠ 자리) 자리로 말하는 답이 그대로여야 한다.
    //    다시 열지 않았다면 옛 RowMap(열쇠 = 자리)이 새 열쇠 칸을 못 찾아 목록이 빈다.
    let list_same = list();
    let layout_same = call(json!({"op":"layout"}))["data"].clone();
    with_store_write(|tx| -> archive_engine::Result<()> {
        tx.execute_batch("PRAGMA defer_foreign_keys=ON")?;
        let tracks: Vec<i64> = tx.prepare("SELECT DISTINCT track FROM rows ORDER BY track DESC")?.query_map([], |r| r.get(0))?.collect::<Result<_, _>>()?;
        for track in tracks {
            let next: i64 = tx.query_row("SELECT MAX(id)+1 FROM rows", [], |r| r.get(0))?;
            rekey_track(tx, track, next + 3)?;
        }
        tx.execute("UPDATE meta SET value='4.1' WHERE key='schema'", [])?;
        Ok(())
    })
    .unwrap();
    assert_eq!(call(json!({"op":"info"}))["data"]["meta"]["schema"], "4.1");
    assert_eq!(list(), list_same, "열쇠가 갈려도 조회의 줄은 자리다 — 저장소를 다시 열었다");
    assert_eq!(call(json!({"op":"layout"}))["data"], layout_same);
    assert!(tile().is_some());
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[test]
fn 쓰다_죽어_남은_일지는_저장소를_열_때_되돌려_열린다() {
    let _g = serial();
    let path = common::scratch("wtx-hot");
    common::build(&path);
    let before = common::sha256_file(&path);
    // 캐시를 1쪽으로 줄인 쓰기 연결 — 거래 도중 캐시가 넘쳐 옛 쪽을 일지(`-journal`)에 적고 디스크 파일을 미리 고쳐 쓴다(배타 잠금).
    let mut db = Connection::open(&path).unwrap();
    db.execute_batch("PRAGMA cache_size=1; PRAGMA foreign_keys=ON").unwrap();
    let tx = db.transaction_with_behavior(TransactionBehavior::Immediate).unwrap();
    tx.execute("UPDATE events SET body=body||'—늘린 본문—', title=title||'x'", []).unwrap();
    // 이 순간의 디스크를 다른 이름으로 복사 = 프로세스가 여기서 죽은 뒤 남는 파일 둘(저장소 + 일지). 복사본은 둘(Store::open용 · 열기 명령용).
    let copy_dead = |name: &str| {
        let dead = common::scratch(name);
        let journal = format!("{}-journal", dead.display());
        let _ = std::fs::remove_file(&journal);
        std::fs::copy(&path, &dead).unwrap();
        std::fs::copy(format!("{}-journal", path.display()), &journal).expect("캐시가 넘쳐 일지가 생겼어야 한다");
        (dead, journal)
    };
    let (dead, dead_journal) = copy_dead("wtx-hot-dead");
    let (dead2, dead2_journal) = copy_dead("wtx-hot-dead2");
    assert_ne!(common::sha256_file(&dead), before, "복사본은 쓰다 만 디스크여야 한다(캐시가 넘쳐 파일이 이미 고쳐졌다)");
    // 원본 거래는 되돌려 끝낸다.
    tx.rollback().unwrap();
    drop(db);
    assert_eq!(common::sha256_file(&path), before);

    // 전제: 읽기 전용 연결은 이 일지를 되돌리지 못해 읽기에서 실패한다(SQLITE_READONLY_ROLLBACK).
    let reader = Connection::open_with_flags(&dead, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let why = reader.query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get::<_, i64>(0)).expect_err("읽기 전용으로는 되돌릴 수 없다");
    drop(reader);
    assert!(matches!(&why, rusqlite::Error::SqliteFailure(e, _) if e.extended_code == 776), "{why:?}");
    // 저장소를 여는 길(Store::open · archive_call open)은 스스로 되돌려 연다 — 열리지 않는 저장소가 남지 않는다.
    let store = Store::open(&dead).expect("남은 일지를 되돌리고 열려야 한다");
    assert!(!Path::new(&dead_journal).exists(), "되돌린 뒤 일지는 지워진다");
    assert_eq!(store.db.query_row("SELECT count(*) FROM events", [], |r| r.get::<_, i64>(0)).unwrap(), 513);
    drop(store);
    assert_eq!(common::sha256_file(&dead), before, "되돌린 파일은 쓰기 전과 같다");
    // 앱의 열기 명령도 마찬가지다.
    call(json!({"op":"close"}));
    assert_eq!(open(&dead2)["data"]["meta"]["schema"], archive_engine::schema::VERSION);
    assert!(!Path::new(&dead2_journal).exists());
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
    assert_eq!(common::sha256_file(&dead2), before);
}

/// 저장소의 줄 열쇠를 모두 갈라 놓는다(열쇠 ≠ 자리 — '4.1'). 다시 열지 않은 `Store`의 옛 `RowMap`(열쇠 = 자리)은 새 열쇠 칸을 못 찾는다.
fn rekey_all(tx: &rusqlite::Transaction) -> archive_engine::Result<()> {
    tx.execute_batch("PRAGMA defer_foreign_keys=ON")?;
    let tracks: Vec<i64> = tx.prepare("SELECT DISTINCT track FROM rows ORDER BY track DESC")?.query_map([], |r| r.get(0))?.collect::<Result<_, _>>()?;
    for track in tracks {
        let next: i64 = tx.query_row("SELECT MAX(id)+1 FROM rows", [], |r| r.get(0))?;
        rekey_track(tx, track, next + 3)?;
    }
    tx.execute("UPDATE meta SET value='4.1' WHERE key='schema'", [])?;
    Ok(())
}

#[test]
fn 열린_저장소에_두_쓰기가_겹치면_프로세스_안에서_하나씩_돈다() {
    // 과제 7a 얹힌 몫 1: 두 apply가 같은 저장소에 겹쳐 오면 하나씩. SQLite의 기다림(busy_timeout 5초)만으로는 앞의 쓰기가 5초 넘게 걸리면
    // 뒤의 쓰기가 'database is locked'로 실패한다 — 프로세스 전역 쓰기 잠금 앞에서 기다려야 한다. 앞의 쓰기는 7초를 쥔다
    // (Windows의 잠 단위(15.6ms) 때문에 SQLite의 5초 기다림이 실제로는 5.6초 남짓까지 늘어난다 — 넉넉히 넘긴다).
    let _g = serial();
    let path = common::scratch("wtx-two");
    common::build(&path);
    open(&path);
    let (started_tx, started_rx) = mpsc::channel();
    let first = std::thread::spawn(move || {
        with_store_write(|tx| {
            put_probe(tx, "first")?;
            started_tx.send(()).unwrap();
            std::thread::sleep(Duration::from_millis(7000));
            Ok(Instant::now())
        })
    });
    started_rx.recv_timeout(Duration::from_secs(5)).expect("첫 쓰기가 시작되지 않았다");
    let second = with_store_write(|tx| {
        let begun = Instant::now();
        put_probe(tx, "second")?;
        Ok(begun)
    });
    let first_done = first.join().unwrap().expect("첫 쓰기");
    let second_begun = second.expect("둘째 쓰기는 기다렸다가 돈다");
    assert!(second_begun >= first_done, "둘째 쓰기의 걸음은 첫 쓰기가 끝난 뒤에 돈다");
    assert_eq!(call(json!({"op":"info"}))["data"]["meta"]["probe"], "second");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[cfg(windows)]
#[test]
fn 쓰는_동안_같은_파일을_다른_글자로_다시_열어도_commit_뒤에_다시_연다() {
    // 과제 7a 얹힌 몫 3: 같은 파일인지 경로 글자로 견주지 않는다 — 쓰는 동안 앱이 같은 파일을 다른 글자(이름의 대소문자 — Windows는 가리지 않는다)로
    // 다시 열었으면 그 저장소의 RowMap은 COMMIT 전 것이다. COMMIT 뒤에는 열려 있는 저장소를 늘 다시 열어야 자리로 말하는 답이 맞다.
    let _g = serial();
    let path = common::scratch("wtx-spelling");
    common::build(&path);
    open(&path);
    let list_same = list();
    let other = path.with_file_name(path.file_name().unwrap().to_string_lossy().to_uppercase());
    assert_ne!(other, path, "장면: 글자가 다른 경로");
    with_store_write(|tx| {
        open(&other);
        rekey_all(tx)
    })
    .unwrap();
    assert_eq!(call(json!({"op":"info"}))["data"]["meta"]["schema"], "4.1");
    assert_eq!(list(), list_same, "COMMIT 뒤 다시 연 RowMap으로 자리를 낸다");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[test]
fn commit_뒤_다시_열지_못하면_저장소를_닫고_그렇다고_따로_알린다() {
    // 과제 7a 얹힌 몫 4: COMMIT은 끝났는데(파일이 바뀜) 다시 열기가 실패하면 저장소는 닫힌 채 남는다 — 그 Err는 '실패 = 저장소 그대로'와 다른 갈래
    // (`ReopenFailed`)로 알린다. 다시 열기를 막는 것: 이 엔진이 모르는 판으로 적은 저장소.
    let _g = serial();
    let path = common::scratch("wtx-reopen");
    common::build(&path);
    open(&path);
    let err = with_store_write(|tx| {
        tx.execute("UPDATE meta SET value='9' WHERE key='schema'", [])?;
        Ok(())
    })
    .expect_err("다시 열지 못하면 Err");
    assert!(err.downcast_ref::<archive_engine::ReopenFailed>().is_some(), "다른 갈래의 Err여야 한다: {err}");
    assert!(err.to_string().contains("바뀌었") && err.to_string().contains("다시 열지 못"), "{err}");
    assert_eq!(meta_of(&path, "schema").as_deref(), Some("9"), "COMMIT은 끝났다");
    let answer = call(json!({"op":"info"}));
    assert!(answer["error"].as_str().unwrap().contains("열리지 않았습니다"), "저장소는 닫혔다: {answer}");
    // 앞의 실패와 다른 '실패 = 저장소 그대로'는 그 갈래가 아니다.
    open_fresh_and_fail_plainly();
}

#[test]
fn commit_뒤_다시_열다_패닉해도_다시_열기_실패로_알리고_잠금은_멀쩡하다() {
    // 고침 1회차 Minor 1: 다시 열기에서 패닉하면 바깥 catch_unwind가 "내부 오류"만 내고(`committed` 없음) STORE 잠금이 오염된 채 남았다 —
    // 다시 열기를 따로 감싸 `ReopenFailed`로 바꾼다. 패닉은 실패 주입("reopen-panic")으로 일으킨다.
    let _g = serial();
    let path = common::scratch("wtx-reopen-panic");
    common::build(&path);
    open(&path);
    set_fail_point(Some("reopen-panic"));
    let got = std::panic::catch_unwind(|| with_store_write(|tx| put_probe(tx, "panic")));
    set_fail_point(None);
    let err = got.expect("패닉이 with_store_write 밖으로 새지 않는다").expect_err("다시 열기 실패");
    assert!(err.downcast_ref::<archive_engine::ReopenFailed>().is_some(), "{err}");
    assert_eq!(meta_of(&path, "probe").as_deref(), Some("panic"), "COMMIT은 끝났다");
    let answer = call(json!({"op":"info"}));
    assert!(answer["error"].as_str().unwrap().contains("열리지 않았습니다"), "잠금은 오염되지 않고 저장소만 닫혔다: {answer}");
    open(&path);
    assert_eq!(call(json!({"op":"info"}))["data"]["meta"]["probe"], "panic");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

/// 걸음이 실패한 쓰기의 Err는 `ReopenFailed`가 아니다(저장소 그대로).
fn open_fresh_and_fail_plainly() {
    let path = common::scratch("wtx-reopen-plain");
    common::build(&path);
    open(&path);
    let err = with_store_write(|_| -> archive_engine::Result<()> { Err("걸음 실패".into()) }).expect_err("Err");
    assert!(err.downcast_ref::<archive_engine::ReopenFailed>().is_none(), "{err}");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[test]
fn 열쇠가_갈린_저장소에서_진짜_apply가_도는_동안에도_타일은_옛_답을_곧바로_받는다() {
    // A 걸음 검토 검사 빈틈 9: '4.1' 저장소(열쇠 ≠ 자리)에 진짜 apply(지우기 · 덧붙이기 · relink · 이름 표 · 표본 대조 — 큰 거래)가 도는 동안 다른 스레드의
    // `archive_tile` · 조회가 막히지 않고 옛 답을 받는다(지금까지는 rekey 흉내로만 쟀다). 거래가 끝나기 직전에 멈춰 세운 채 묻는다 — 때에 기대지 않는다.
    use archive_engine::patch::{apply, ApplyIn, Covers};
    use common::plans::{packs_of, plan};
    let _g = serial();
    let path = common::scratch("wtx-real-apply");
    archive_engine::legacy::import_layout_value(&plan(&["a", "c"]), &packs_of(&["a", "c"]), &path).unwrap();
    // 색만 바꿔 ta를 다시 쓴다 — ta의 줄이 끝 번호 뒤 새 덩이로 가 열쇠 ≠ 자리('4.1').
    let (p, o) = (plan(&["a@2", "c"]), packs_of(&["a@2", "c"]));
    write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
    assert_eq!(meta_of(&path, "schema").as_deref(), Some("4.1"), "장면: 열쇠가 갈린 저장소");
    open(&path);
    let request = CString::new(r#"{"level":8,"x":0,"chunk":0,"packs":[1,2]}"#).unwrap();
    let tile_at = || -> Option<Vec<u8>> {
        let mut len = 0usize;
        unsafe {
            let ptr = archive_tile(request.as_ptr(), &mut len);
            if ptr.is_null() {
                return None;
            }
            let copy = std::slice::from_raw_parts(ptr, len).to_vec();
            archive_free_bytes(ptr, len);
            Some(copy)
        }
    };
    let (tile_before, layout_before) = (tile_at().expect("타일"), call(json!({"op":"layout"}))["data"].clone());
    let (ready_tx, ready_rx) = mpsc::channel();
    let (go_tx, go_rx) = mpsc::channel::<()>();
    let writer = std::thread::spawn(move || {
        with_store_write(|tx| {
            // b를 더한다(ta에 줄 · 사건을 얹고 tb가 새로 든다 — 지우기 · 덧붙이기 · relink · 이름 표 · 표본 대조가 모두 돈다).
            let (p, o) = (plan(&["a@2", "b", "c"]), packs_of(&["a@2", "b", "c"]));
            let r = apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })?;
            ready_tx.send(()).unwrap();
            go_rx.recv_timeout(Duration::from_secs(30)).ok();
            Ok(r)
        })
    });
    ready_rx.recv_timeout(Duration::from_secs(120)).expect("apply가 끝나지 않았다");
    let started = Instant::now();
    let during = tile_at().expect("쓰는 동안에도 타일이 나온다");
    let layout_during = call(json!({"op":"layout"}))["data"].clone();
    let took = started.elapsed();
    assert!(took < Duration::from_millis(500), "타일 · 조회가 쓰기에 막혔다: {took:?}");
    assert_eq!(during, tile_before, "쓰는 동안 타일은 옛 답");
    assert_eq!(layout_during, layout_before, "쓰는 동안 layout은 옛 답");
    assert!(!writer.is_finished(), "묻는 동안 쓰기 거래는 아직 열려 있었다(재는 틀이 맞다)");
    go_tx.send(()).unwrap();
    let r = writer.join().unwrap().expect("apply");
    assert_eq!(r.added, vec!["tb".to_string()]);
    let layout_after = call(json!({"op":"layout"}))["data"].clone();
    assert_ne!(layout_after, layout_before, "끝난 뒤에는 새 답(tb가 듦)");
    assert!(layout_after.to_string().contains("\"tb\""), "새 layout에 tb");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[test]
fn pack_refusals_carry_code_and_detail_and_the_path_must_match() {
    // 고침 2회차(판정 R59 M-1 · M-4 · R61): 앱이 부르는 add_pack이 배치에서 넘어지면 일반 실패가 아니라 거절(`code`) — 저장소의 달력 표에 그 달력이
    // 없으면 `code` calendar와 쉬운 글 · 원래 글(lay의 '… 표 없음 — …')은 `detail`. 쓰기 요청의 `path`가 열린 저장소와 다르면 쓰지 않고 거절.
    let _g = serial();
    let _t = common::clock("pack_refusals_carry_code_and_detail_and_the_path_must_match");
    let root = common::node::repo_root();
    let fix = root.join("prototype").join("fixtures").join("oracle");
    let seal = |name: &str| -> (String, Vec<u8>) {
        let bytes = archive_engine::legacy::seal_dlc(&std::fs::read(fix.join(name)).unwrap());
        (archive_engine::htpack_raw(&bytes).unwrap()["id"].as_str().unwrap().to_owned(), bytes)
    };
    let (synth, patch) = (seal("synth.json"), seal("synth-patch.json"));
    let inputs = vec![archive_engine::lay::PackIn { name: "synth.htpack".into(), bytes: synth.1.clone() }];
    let opts = archive_engine::lay::Opts { now_ms: common::oracle::ORACLE_NOW_MS, tz_min: 540, upto: None, scope: archive_engine::lay::Scope::All,
        calendar: Some(common::oracle::calendar_slice()) };
    let plan = archive_engine::lay::export(&inputs, &opts).unwrap();
    let path = common::scratch("wtx-nocal");
    // 달력 이름표는 있으나 달력이 하나도 없는 표 — 합성 세계의 음력 날짜를 읽을 수 없다.
    archive_engine::legacy::build_store(&plan, &[synth], &path, common::oracle::ORACLE_NOW, br#"{"v":1,"years":[-3500,2500],"tables":{}}"#).unwrap();
    let file = std::env::temp_dir().join(format!("archive-correct-{}-wtx-patch.htpack", std::process::id()));
    std::fs::write(&file, &patch.1).unwrap();
    let before = common::sha256_file(&path);
    open(&path);
    let answer = call(json!({"op":"add_pack","files":[file.to_str().unwrap()]}));
    assert_eq!((answer["ok"].clone(), answer["code"].clone()), (json!(false), json!("calendar")), "{answer}");
    let error = answer["error"].as_str().unwrap();
    assert!(error.contains("달력 표에") && !error.contains("컴퓨터에서"), "{answer}");
    assert!(answer["detail"].as_str().is_some_and(|d| d.contains("표 없음")), "자세히 보기에 원래 글: {answer}");
    // 열린 저장소가 아닌 path — 쓰지 않는다. 거절은 `code` path · 쉬운 글(경로 없이) · 두 경로는 `detail`(appfix 검토 덧붙임).
    for request in [json!({"op":"add_pack","files":[file.to_str().unwrap()],"path":"D:/없는/저장소.db"}),
        json!({"op":"remove_pack","id":"synth-patch","path":"D:/없는/저장소.db"}), json!({"op":"apply","layout":"D:/없는/배치.json","path":"D:/없는/저장소.db"})] {
        let answer = call(request);
        assert_eq!((answer["ok"].clone(), answer["code"].clone()), (json!(false), json!("path")), "{answer}");
        let error = answer["error"].as_str().unwrap();
        assert!(error.contains("열린 저장소") && !error.contains("없는/저장소") && !error.contains(':'), "쉬운 글 — 경로 없이: {answer}");
        assert!(answer["detail"].as_str().is_some_and(|d| d.contains("D:/없는/저장소.db") && d.contains("wtx-nocal")), "자세히 보기에 두 경로: {answer}");
    }
    // 고침 3회차: 견줌은 쓰기 차례를 잡은 뒤 쓸 파일을 정한 자리에서도 — 다르면 걸음을 돌지 않는다.
    let ran = std::cell::Cell::new(false);
    let err = archive_engine::with_store_write_at(Some("D:/없는/저장소.db"), |_| { ran.set(true); Ok(()) }).unwrap_err();
    assert!(err.downcast_ref::<archive_engine::patch::Refusal>().is_some_and(|r| r.code == "path") && !ran.get(), "{err}");
    // 같은 저장소(글자가 달라도 같은 파일)면 path를 받아 들어간다(여기서는 같은 달력 거절까지).
    let same = path.to_str().unwrap().replace('\\', "/");
    let answer = call(json!({"op":"add_pack","files":[file.to_str().unwrap()],"path":same}));
    assert_eq!(answer["code"], "calendar", "{answer}");
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
    assert_eq!(common::sha256_file(&path), before, "거절하면 저장소 그대로");
}

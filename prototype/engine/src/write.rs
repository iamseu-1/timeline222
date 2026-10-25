//! 쓰기 거래(계획 P4 과제 3) — DLC를 넣고 뺄 때 엔진이 저장소 파일을 바꿔 넣지 않고 제자리에서 한 거래로 고쳐 쓴다.
//!
//! 같은 파일에 쓰기 연결을 **따로** 열어 `BEGIN IMMEDIATE`로 쓴다. 앱이 열어 둔 읽기 연결(`Store`)은 그대로 옛 답을 낸다 —
//! 저널 방식이 DELETE라 쓰는 쪽의 예약 잠금(RESERVED)은 읽기를 막지 않고, 읽기를 막는 배타 잠금(EXCLUSIVE)은 COMMIT 순간에만 잡힌다.
//! 그러려면 쓰는 쪽이 COMMIT 전에 캐시 넘침으로 일찍 쓰지 않아야 하므로 `cache_size`를 넉넉히 준다.
//!
//! 실패하면(걸음이 Err · 외래 열쇠 어긋남 · COMMIT 실패) 거래를 되돌려 파일은 쓰기 전 그대로다. 외래 열쇠는 저장소 전체를 훑어 확인하지 않는다 —
//! 거래 안에서 `defer_foreign_keys=ON`으로 미뤄 두면 SQLite가 **이 거래가 만든 위반만** 세어 두었다가 COMMIT에서 거른다(거래가 만진 양에 비례).
//! `with_store_write`(lib.rs)가 [`write_with`]의 `before_commit`에서 `STORE` 잠금을 쥐게 한다 — 잠금은 COMMIT 순간만이다.
use crate::Result;
use rusqlite::{Connection, OpenFlags, Transaction, TransactionBehavior};
use std::cell::Cell;
use std::path::Path;

/// 쓰기 연결의 쪽 캐시(KiB 단위 음수 = 64MiB). 이보다 큰 거래는 캐시가 넘쳐 COMMIT 전에 EXCLUSIVE를 잡고 읽기를 막는다.
const WRITE_CACHE_KIB: i64 = 65536;
/// 다른 쓰기(또는 COMMIT 순간의 읽기)에 부딪쳤을 때 기다리는 시간.
const BUSY_MS: u32 = 5000;

thread_local! {
    static FAIL: Cell<Option<&'static str>> = const { Cell::new(None) };
}

/// 검사용 실패 지점을 건다(`None`이면 끈다). **스레드마다** 따로다 — cargo가 한 파일의 검사를 여러 스레드로 돌려도 섞이지 않는다.
/// 이름은 쓰는 걸음의 이름(`patch.rs`의 걸음 이름)이고, 그 걸음 안의 [`fail_point`]가 걸린다.
pub fn set_fail_point(name: Option<&'static str>) {
    FAIL.with(|f| f.set(name));
}

/// 걸음 안에서 부른다 — 이 이름이 걸려 있으면 Err(주입한 실패), 아니면 Ok.
pub fn fail_point(name: &str) -> Result<()> {
    if FAIL.with(|f| f.get()) == Some(name) {
        return Err(format!("실패 주입: {name}").into());
    }
    Ok(())
}

/// 같은 파일에 쓰기 연결을 따로 열어(`foreign_keys=ON` · 큰 `cache_size`) `BEGIN IMMEDIATE` → `defer_foreign_keys=ON` → `step` →
/// `before_commit()` → COMMIT. 외래 열쇠 위반은 문장에서가 아니라 **COMMIT이 거른다**: 위반이 남으면 COMMIT이 SQLITE_CONSTRAINT로 실패하고
/// 거래는 되돌려진다(저장소 전체를 훑는 확인은 없다 — 위반을 세는 값은 거래가 만진 만큼만 움직인다).
///
/// - `step`이 Err면 되돌리고 그 Err를 돌려준다(파일은 그대로 · `before_commit`은 불리지 않는다).
/// - `before_commit`이 돌려준 것(예: `STORE` 잠금)은 COMMIT 뒤 그대로 돌려준다 — 잠금을 COMMIT이 끝날 때까지 쥐고 있게 하려는 길이다.
///   COMMIT이 실패하면(외래 열쇠 위반 · 디스크 오류) 거래를 되돌리고 그것도 놓은 채 Err를 돌려준다(잠금이 새지 않는다).
/// - 없는 파일은 만들지 않는다(쓰기 연결은 새 저장소를 짓지 못한다).
pub fn write_with<T, G>(path: &Path, step: impl FnOnce(&Transaction) -> Result<T>, before_commit: impl FnOnce() -> G) -> Result<(T, G)> {
    let mut db = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX)?;
    db.execute_batch(&format!("PRAGMA foreign_keys=ON; PRAGMA cache_size=-{WRITE_CACHE_KIB}; PRAGMA busy_timeout={BUSY_MS};"))?;
    // 거래를 COMMIT하지 못하고 벗어나면(Err · 패닉 · COMMIT 실패) `Transaction`이 떨어지며 되돌린다 — 그 전에 파일에 닿은 것이 없다(캐시가 넘치지 않는 한).
    let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
    // 외래 열쇠 위반을 COMMIT까지 미룬다(거래가 끝나면 저절로 꺼진다) — 위반이 남은 채로는 COMMIT이 되지 않는다.
    tx.execute_batch("PRAGMA defer_foreign_keys=ON")?;
    let out = step(&tx)?;
    let held = before_commit();
    tx.commit().map_err(|e| format!("COMMIT에 실패해 되돌렸습니다: {e}"))?;
    Ok((out, held))
}

/// [`write_with`]에서 `before_commit` 없이.
pub fn write<T>(path: &Path, step: impl FnOnce(&Transaction) -> Result<T>) -> Result<T> {
    write_with(path, step, || ()).map(|(out, ())| out)
}

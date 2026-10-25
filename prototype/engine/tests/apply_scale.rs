//! 시간(계획 P4 과제 7c — 손으로 돌림): apply의 쓰기 시간이 저장소 크기가 아니라 **바뀐 트랙 크기에만** 비례하는가.
//!
//! `$env:TMP='D:\tmp-p34'; cargo test --release --locked --test apply_scale -- --ignored --nocapture`
//! (100만 저장소는 수백 MB — 임시 폴더를 넉넉한 드라이브로 돌려 돌린다. 끝나면 이 검사가 만든 저장소를 지운다.)
//!
//! 장면: `plans::big(50, 20, N)`(트랙 50 · 줄 1,000 · 줄마다 띠 하나 · 사건 N을 줄마다 고루)을 N = 10만 · 100만으로 통째 짓는다. 가운데 트랙
//! `big-t25`는 두 저장소에서 **같은 크기**(줄마다 100건 · 사건 2,000 — 10만 장면의 트랙 하나 몫)로 맞춰 둔다 — 100만 장면의 다른 트랙은 2만 건씩이다.
//! 사건은 진짜 내보내기처럼 트랙 · 줄 차례로 묶여 있다(`plans::big`).
//! 그 트랙에 줄 하나 · 사건 10(하나는 보는 범위 밖 2200년)을 더한 덮는 트랙만의 배치(`Covers::Tracks({big-t25})` — 메이커 `.htlayout`의 꼴)를
//! `apply`한다. **단언: 100만의 ms < 10만의 ms × 1.5 + 50**(세 번 재어 가운데 값 · `ApplyReport.ms` — 거래 안의 쓰기 · COMMIT은 따로 찍음).
//!
//! 함께 재어 찍는 것(단언하지 않음 — 보고에 적는다):
//! - 걸음별 ms(`ApplyReport.steps`) — 항목 기록 견줌("entities") · 이름 표 다시 펴기("names") · 표본 대조("verify")의 몫.
//! - 되돌리기(줄 · 사건을 다시 뺌 — 보는 범위 끝값을 지운 것만 가져 "range"가 남은 것에서 다시 잼).
//! - 자연 크기 트랙 `big-t26`(N/50건 — 바뀐 트랙도 함께 커짐).
//! - 배치 전부(`Covers::All` — 지금 A 길 · `add-dlc.mjs --apply`가 주는 꼴): 같은 바뀜을 조합 전부의 배치로 · 그 배치 JSON 읽기.
//! - DLC 넣기 · 빼기(`Covers::All` — 자료집 행을 지울 때 외래 열쇠가 자식 표를 훑는 몫이 "delete"에 든다).
//! - 쓰는 동안 읽기(다른 연결에서 옛 줄 범위 조회를 되풀이 — 가장 긴 기다림 · 바쁨 실패).
//! - 이 계획 전에 지은 저장소의 첫 apply(`common::strip_new_columns` 흉내 — 모든 트랙을 한 번 다시 쓰고 덮는 색인을 다시 짓는다) · 덮는 색인 다시 짓기만.
//! - `events.ord` 열의 크기(레코드 형식으로 센 바이트 — 표 줄 하나 · 덮는 색인 줄 하나마다 형식 머리 1바이트 + 값 0 ~ 8바이트).
//! - COMMIT 뒤 저장소 다시 열기(`Store::open` — 줄 열쇠 ↔ 자리 표).
mod common;
use archive_engine::legacy::import_layout_value;
use archive_engine::patch::{apply, sub_plan, ApplyIn, ApplyReport, Covers};
use archive_engine::write::write;
use common::plans::{big, htpack, packs_of, yr};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

/// 장면의 크기.
const TRACKS: usize = 50;
const ROWS: usize = 20;
/// 두 저장소에서 같은 크기로 맞추는 가운데 트랙 · 그 사건 수(10만 장면의 트랙 하나 몫).
const SAME: usize = 25;
const SAME_EVENTS: usize = 2_000;
/// 자연 크기로 두는 이웃 트랙.
const NATURAL: usize = 26;
/// 같은 측정을 몇 번 해 가운데 값을 쓰는가.
const RUNS: usize = 3;

fn ms_since(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1000.0
}

fn median(mut v: Vec<f64>) -> f64 {
    assert!(!v.is_empty());
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = v.len();
    if n % 2 == 1 { v[n / 2] } else { (v[n / 2 - 1] + v[n / 2]) / 2.0 }
}

fn file_mb(path: &Path) -> f64 {
    std::fs::metadata(path).map(|m| m.len() as f64 / 1_048_576.0).unwrap_or(0.0)
}

/// apply 한 번의 잰 값: 거래 안(`ApplyReport.ms`) · COMMIT까지 · 걸음별.
#[derive(Clone)]
struct Run {
    apply_ms: f64,
    total_ms: f64,
    steps: Vec<(&'static str, f64)>,
    report: ApplyReport,
}

fn run_apply(path: &Path, plan: &Value, originals: &[(String, Vec<u8>)], covers: Covers, remove: &[String]) -> Run {
    let t = Instant::now();
    let report = write(path, |tx| apply(tx, &ApplyIn { plan, originals, covers, remove })).unwrap_or_else(|e| panic!("apply: {e}"));
    let total_ms = ms_since(t);
    Run { apply_ms: report.ms, total_ms, steps: report.steps.clone(), report }
}

/// 여러 번의 걸음별 가운데 값(걸음 차례대로).
fn step_medians(runs: &[Run]) -> Vec<(&'static str, f64)> {
    let names: Vec<&'static str> = runs[0].steps.iter().map(|(n, _)| *n).collect();
    names.iter().map(|name| {
        (*name, median(runs.iter().map(|r| r.steps.iter().find(|(n, _)| n == name).map_or(0.0, |s| s.1)).collect()))
    }).collect()
}

fn steps_text(steps: &[(&'static str, f64)]) -> String {
    steps.iter().map(|(n, ms)| format!("{n} {ms:.1}")).collect::<Vec<_>>().join(" · ")
}

/// 여러 번의 요약(가운데 값): 거래 안 ms · COMMIT까지 ms · 낱낱의 값.
#[derive(Clone)]
struct Summary {
    apply_ms: f64,
    total_ms: f64,
    each: Vec<f64>,
    steps: Vec<(&'static str, f64)>,
    rewrote: usize,
}

fn summarize(runs: &[Run]) -> Summary {
    Summary {
        apply_ms: median(runs.iter().map(|r| r.apply_ms).collect()),
        total_ms: median(runs.iter().map(|r| r.total_ms).collect()),
        each: runs.iter().map(|r| r.apply_ms).collect(),
        steps: step_medians(runs),
        rewrote: runs[0].report.rewrote.len() + runs[0].report.added.len(),
    }
}

fn line(label: &str, s: &Summary) {
    let each: Vec<String> = s.each.iter().map(|v| format!("{v:.1}")).collect();
    println!("  {label}: 거래 안 {:.1}ms(낱낱 {}) · COMMIT까지 {:.1}ms · 다시 쓴/든 트랙 {}", s.apply_ms, each.join(" / "), s.total_ms, s.rewrote);
    println!("    걸음별(가운데 값) {}", steps_text(&s.steps));
}

/// 다른 연결에서 되풀이한 읽기의 잰 값.
#[derive(Default, Debug, Clone)]
struct Reads {
    n: usize,
    max_ms: f64,
    over_50ms: usize,
    busy: usize,
}

/// `f`(쓰기)가 도는 동안 다른 스레드가 같은 저장소를 읽기 전용으로 열어(앱의 `Store`) 트랙 0의 줄 범위 조회(1500년 한 해 · 줄 8)를 되풀이한다.
/// 쓰는 쪽이 캐시를 넘쳐 COMMIT 전에 배타 잠금을 잡으면 읽기가 기다린다(`busy_timeout` 5초 — 넘으면 바쁨 실패).
fn reading_while<T>(path: &Path, f: impl FnOnce() -> T) -> (T, Reads) {
    let stop = Arc::new(AtomicBool::new(false));
    let ready = Arc::new(AtomicBool::new(false));
    let (p, s, r) = (path.to_owned(), stop.clone(), ready.clone());
    let handle = std::thread::spawn(move || {
        let store = archive_engine::Store::open(&p).unwrap();
        let mut out = Reads::default();
        let (lo, hi) = (yr(1500), yr(1501));
        while !s.load(Ordering::SeqCst) {
            let t = Instant::now();
            if store.range(lo, hi, 0, 8, 0, 50).is_err() {
                out.busy += 1;
            }
            let ms = ms_since(t);
            out.n += 1;
            out.max_ms = out.max_ms.max(ms);
            out.over_50ms += usize::from(ms > 50.0);
            r.store(true, Ordering::SeqCst);
            std::thread::sleep(std::time::Duration::from_millis(2));
        }
        out
    });
    while !ready.load(Ordering::SeqCst) {
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    let got = f();
    stop.store(true, Ordering::SeqCst);
    (got, handle.join().unwrap())
}

fn reads_text(r: &Reads) -> String {
    format!("읽기 {}번 · 가장 긴 {:.1}ms · 50ms 넘음 {} · 바쁨 실패 {}", r.n, r.max_ms, r.over_50ms, r.busy)
}

/// 가운데 트랙을 `SAME_EVENTS`건으로 맞춘 큰 배치.
/// 줄마다 사건을 `SAME_EVENTS / ROWS`건까지만 남긴다(줄마다 같은 꼴 — 100만 장면에서도 10만 장면의 그 트랙과 같다).
fn scene(events: usize) -> Value {
    let mut plan = big(TRACKS, ROWS, events);
    let mut per_row = vec![0usize; ROWS];
    plan["events"].as_array_mut().unwrap().retain(|e| {
        if e["track"] != SAME {
            return true;
        }
        let row = e["row"].as_u64().unwrap() as usize;
        per_row[row] += 1;
        per_row[row] <= SAME_EVENTS / ROWS
    });
    assert!(per_row.iter().all(|n| *n >= SAME_EVENTS / ROWS), "가운데 트랙의 줄마다 사건이 {}건보다 적습니다", SAME_EVENTS / ROWS);
    plan
}

/// 트랙 하나에 줄 하나 · 사건 10을 더한다(그 배치에서의 트랙 순번 `at`). 사건 하나는 보는 범위(1000 ~ 1900년) 밖 2200년.
fn grow(plan: &mut Value, at: usize, tag: &str) {
    let row = plan["tracks"][at]["rows"][0].clone();
    plan["tracks"][at]["rows"].as_array_mut().unwrap().push(row);
    let events = plan["events"].as_array_mut().unwrap();
    for k in 0..10i64 {
        let start = if k == 9 { yr(2200) } else { yr(1500) + k * 1440 };
        events.push(json!({"uid":format!("big/x-{tag}-{k}"),"track":at,"row":ROWS,"start":start,"title":format!("더한 사건 {k}")}));
    }
}

/// [`grow`]를 되돌린다.
fn shrink(plan: &mut Value, at: usize, tag: &str) {
    plan["tracks"][at]["rows"].as_array_mut().unwrap().pop();
    let prefix = format!("big/x-{tag}-");
    plan["events"].as_array_mut().unwrap().retain(|e| !e["uid"].as_str().unwrap_or("").starts_with(&prefix));
}

/// 덮는 트랙 하나(`big-t<at>`)를 `RUNS`번 넣고 되돌린다 — 넣기(줄 · 사건 더함)와 되돌리기를 따로 요약한다.
fn covered_track(path: &Path, plan: &Value, at: usize, o: &[(String, Vec<u8>)]) -> (Summary, Summary) {
    let key = format!("big-t{at}");
    let keys: BTreeSet<String> = [key.clone()].into_iter().collect();
    let base = sub_plan(plan, &keys).unwrap();
    let mut grown = base.clone();
    grow(&mut grown, 0, &key);
    let covers = Covers::Tracks(keys);
    let (mut adds, mut backs) = (Vec::new(), Vec::new());
    for _ in 0..RUNS {
        let a = run_apply(path, &grown, o, covers.clone(), &[]);
        assert_eq!(a.report.rewrote, vec![key.clone()], "{key}만 다시 써야 합니다");
        adds.push(a);
        let b = run_apply(path, &base, o, covers.clone(), &[]);
        assert_eq!(b.report.rewrote, vec![key.clone()]);
        backs.push(b);
    }
    (summarize(&adds), summarize(&backs))
}

/// 한 크기의 잰 값.
struct Scale {
    events: usize,
    build_ms: f64,
    store_mb: f64,
    same_add: Summary,
    same_back: Summary,
    natural_add: Summary,
    natural_back: Summary,
    whole_add: Summary,
    whole_back: Summary,
    parse_ms: f64,
    plan_mb: f64,
    dlc_add: Summary,
    dlc_remove: Summary,
    reads_covered: Reads,
    reads_whole: Reads,
    reopen_ms: f64,
    old_first: Option<(Run, Reads, f64)>,
    reindex_ms: f64,
    ord_bytes: (f64, i64),
}

/// DLC 하나(트랙 하나 · 줄 둘 · 사건 100)를 더한 배치와 그 원본.
fn with_dlc(plan: &Value) -> (Value, (String, Vec<u8>)) {
    let mut p = plan.clone();
    p["packs"].as_array_mut().unwrap().push(json!({"id":"extra","name":"덧 장면","version":"1.0.0","category":""}));
    let rows = vec![p["tracks"][0]["rows"][0].clone(); 2];
    let at = p["tracks"].as_array().unwrap().len();
    p["tracks"].as_array_mut().unwrap().push(json!({"key":"extra-t0","name":"덧 트랙","color":0xa0bcc5,"dynasty":0,"leader":1,"cabinet":0,"organ":0,
        "railLevels":2,"pack":1,"rows":rows,"groups":[]}));
    p["periods"].as_array_mut().unwrap().push(json!({"uid":"extra/p0","track":at,"row":0,"start":yr(1200),"end":yr(1300),"fuzzy":0,"color":0x9dbea8,
        "name":"덧 나라","look":0,"tag":"","sub":0}));
    let events = p["events"].as_array_mut().unwrap();
    for k in 0..100i64 {
        events.push(json!({"uid":format!("extra/e{k}"),"track":at,"row":k % 2,"start":yr(1200) + k * 1440,"title":format!("덧 사건 {k}")}));
    }
    let original = htpack(&json!({"format":"history-timeline-dlc","id":"extra","name":"덧 장면","version":"1.0.0"}));
    (p, ("extra".to_owned(), original))
}

fn measure(events: usize, old_store: bool) -> Scale {
    println!("\n== 사건 {events} — 트랙 {TRACKS} · 줄 {} · 가운데 트랙 big-t{SAME} {SAME_EVENTS}건 · 이웃 big-t{NATURAL} {}건", TRACKS * ROWS, events / (TRACKS * ROWS) * ROWS);
    let mut plan = scene(events);
    let o = packs_of(&["big"]);
    let path = common::scratch(&format!("scale-{events}"));
    let t = Instant::now();
    import_layout_value(&plan, &o, &path).unwrap();
    let build_ms = ms_since(t);
    let store_mb = file_mb(&path);
    println!("  통째 짓기 {:.1}초 · 저장소 {store_mb:.0}MB", build_ms / 1000.0);

    // 1) 덮는 트랙만 — 같은 크기의 트랙(단언) · 자연 크기의 트랙.
    let (same_add, same_back) = covered_track(&path, &plan, SAME, &o);
    line(&format!("덮는 트랙만 big-t{SAME}(같은 크기) 넣기"), &same_add);
    line(&format!("덮는 트랙만 big-t{SAME}(같은 크기) 되돌리기"), &same_back);
    let (natural_add, natural_back) = covered_track(&path, &plan, NATURAL, &o);
    line(&format!("덮는 트랙만 big-t{NATURAL}(자연 크기) 넣기"), &natural_add);
    line(&format!("덮는 트랙만 big-t{NATURAL}(자연 크기) 되돌리기"), &natural_back);

    // 쓰는 동안 읽기(덮는 트랙만 — 한 번 더 넣고 되돌림).
    let reads_covered = {
        let keys: BTreeSet<String> = [format!("big-t{SAME}")].into_iter().collect();
        let base = sub_plan(&plan, &keys).unwrap();
        let mut grown = base.clone();
        grow(&mut grown, 0, "read");
        let (_, r) = reading_while(&path, || run_apply(&path, &grown, &o, Covers::Tracks(keys.clone()), &[]));
        run_apply(&path, &base, &o, Covers::Tracks(keys), &[]);
        r
    };
    println!("  쓰는 동안 읽기(덮는 트랙만): {}", reads_text(&reads_covered));

    // 2) 배치 전부(Covers::All — A 길): 같은 바뀜 · 그 배치 JSON 읽기.
    let bytes = serde_json::to_vec(&plan).unwrap();
    let plan_mb = bytes.len() as f64 / 1_048_576.0;
    let t = Instant::now();
    let parsed: Value = serde_json::from_slice(&bytes).unwrap();
    let parse_ms = ms_since(t);
    drop(parsed);
    drop(bytes);
    println!("  배치 JSON {plan_mb:.0}MB 읽기 {parse_ms:.0}ms");
    let (mut adds, mut backs) = (Vec::new(), Vec::new());
    let mut reads_whole = Reads::default();
    for i in 0..RUNS {
        grow(&mut plan, SAME, "whole");
        let a = if i == 0 {
            let (a, r) = reading_while(&path, || run_apply(&path, &plan, &o, Covers::All, &[]));
            reads_whole = r;
            a
        } else {
            run_apply(&path, &plan, &o, Covers::All, &[])
        };
        assert_eq!(a.report.rewrote, vec![format!("big-t{SAME}")]);
        adds.push(a);
        shrink(&mut plan, SAME, "whole");
        backs.push(run_apply(&path, &plan, &o, Covers::All, &[]));
    }
    let (whole_add, whole_back) = (summarize(&adds), summarize(&backs));
    line("배치 전부(Covers::All) 넣기", &whole_add);
    line("배치 전부(Covers::All) 되돌리기", &whole_back);
    println!("  쓰는 동안 읽기(배치 전부): {}", reads_text(&reads_whole));

    // 3) DLC 넣기 · 빼기.
    let (dlc_plan, extra) = with_dlc(&plan);
    let with_extra: Vec<(String, Vec<u8>)> = o.iter().cloned().chain([extra]).collect();
    let (mut adds, mut removes) = (Vec::new(), Vec::new());
    for _ in 0..RUNS {
        let a = run_apply(&path, &dlc_plan, &with_extra, Covers::All, &[]);
        assert_eq!(a.report.added, vec!["extra-t0".to_owned()]);
        adds.push(a);
        let r = run_apply(&path, &plan, &o, Covers::All, &["extra".to_owned()]);
        assert_eq!(r.report.removed, vec!["extra-t0".to_owned()]);
        removes.push(r);
    }
    drop(dlc_plan);
    let (dlc_add, dlc_remove) = (summarize(&adds), summarize(&removes));
    line("DLC 넣기(트랙 하나 · 사건 100)", &dlc_add);
    line("DLC 빼기", &dlc_remove);

    // 4) COMMIT 뒤 다시 열기(앱 `{"op":"apply"}`의 몫).
    let reopen_ms = median((0..RUNS).map(|_| {
        let t = Instant::now();
        drop(archive_engine::Store::open(&path).unwrap());
        ms_since(t)
    }).collect());
    println!("  저장소 다시 열기 {reopen_ms:.1}ms");

    // 5) 이 계획 전에 지은 저장소의 첫 apply · 덮는 색인 다시 짓기만 · events.ord의 크기.
    let (mut old_first, mut reindex_ms) = (None, 0.0);
    if old_store {
        let old = common::scratch(&format!("scale-{events}-old"));
        std::fs::copy(&path, &old).unwrap();
        let t = Instant::now();
        common::strip_new_columns(&old);
        let strip_ms = ms_since(t);
        let (run, reads) = reading_while(&old, || run_apply(&old, &plan, &o, Covers::All, &[]));
        assert_eq!(run.report.rewrote.len(), TRACKS, "옛 저장소의 첫 apply는 모든 트랙을 한 번 다시 씁니다");
        println!("  옛 저장소 흉내(열 · 표 · 색인 지우고 다시 잼 {:.1}초) → 첫 apply: 거래 안 {:.1}ms · COMMIT까지 {:.1}ms · 저장소 {:.0}MB",
            strip_ms / 1000.0, run.apply_ms, run.total_ms, file_mb(&old));
        println!("    걸음별 {}", steps_text(&run.steps));
        println!("    쓰는 동안 읽기: {}", reads_text(&reads));
        let again = run_apply(&old, &plan, &o, Covers::All, &[]);
        assert!(again.report.rewrote.is_empty(), "첫 apply 뒤에는 바뀐 트랙만");
        println!("    그 뒤 같은 배치: 거래 안 {:.1}ms", again.apply_ms);
        old_first = Some((run, reads, strip_ms));
        let _ = std::fs::remove_file(&old);

        // 덮는 색인만 다시 짓기(첫 apply의 "delete" 안에 드는 몫) — 사본에서.
        let copy = common::scratch(&format!("scale-{events}-index"));
        std::fs::copy(&path, &copy).unwrap();
        {
            let db = rusqlite::Connection::open(&copy).unwrap();
            let t = Instant::now();
            db.execute_batch(&format!("BEGIN; DROP INDEX events_time; {}; COMMIT;", archive_engine::builder::EVENTS_TIME_INDEX_SQL)).unwrap();
            reindex_ms = ms_since(t);
        }
        println!("  덮는 색인(events_time) 다시 짓기만 {reindex_ms:.0}ms");
        let _ = std::fs::remove_file(&copy);
    }
    // events.ord의 크기: 레코드 형식(파일 형식 4)으로 센다 — 값 0 · 1은 0바이트, 그 밖은 1 · 2 · 3 · 4 · 6 · 8바이트, 그리고 형식 머리 1바이트.
    // 표 줄과 덮는 색인(events_time — ord가 끝 열) 줄에 한 번씩 든다. 파일 크기로 견주면 쪽 채움이 달라 차가 흔들린다(10만 +0.2MB · 100만 −0.5MB).
    let ord_bytes: (f64, i64) = {
        let db = rusqlite::Connection::open(&path).unwrap();
        let (sum, top): (i64, i64) = db.query_row("SELECT sum(1 + CASE WHEN ord IN (0,1) THEN 0 WHEN ord BETWEEN -128 AND 127 THEN 1 \
            WHEN ord BETWEEN -32768 AND 32767 THEN 2 WHEN ord BETWEEN -8388608 AND 8388607 THEN 3 WHEN ord BETWEEN -2147483648 AND 2147483647 THEN 4 \
            WHEN ord BETWEEN -140737488355328 AND 140737488355327 THEN 6 ELSE 8 END),max(ord) FROM events", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
        (2.0 * sum as f64, top)
    };
    println!("  events.ord: {:.1}MB(사건 하나에 {:.2}바이트 · 가장 큰 값 {})", ord_bytes.0 / 1_048_576.0, ord_bytes.0 / events as f64, ord_bytes.1);
    let _ = std::fs::remove_file(&path);
    Scale { events, build_ms, store_mb, same_add, same_back, natural_add, natural_back, whole_add, whole_back, parse_ms, plan_mb, dlc_add, dlc_remove,
        reads_covered, reads_whole, reopen_ms, old_first, reindex_ms, ord_bytes }
}

fn step_of(s: &Summary, name: &str) -> f64 {
    s.steps.iter().find(|(n, _)| *n == name).map_or(0.0, |x| x.1)
}

#[test]
#[ignore = "손으로 돌림 — 100만 저장소를 짓는다(수 분 · 수백 MB)"]
fn apply_write_time_follows_the_changed_track_not_the_store() {
    // 크기는 `HT_APPLY_SCALE=<작은>,<큰>`으로 바꿀 수 있다(검사를 고칠 때 빨리 돌려 보는 길 — 작은 쪽은 10만 이상이어야 가운데 트랙이 2,000건).
    let sizes: Vec<usize> = std::env::var("HT_APPLY_SCALE").ok().map(|s| s.split(',').map(|n| n.trim().parse().unwrap()).collect())
        .unwrap_or_else(|| vec![100_000, 1_000_000]);
    assert_eq!(sizes.len(), 2, "HT_APPLY_SCALE은 두 수입니다");
    // `HT_APPLY_SCALE_QUICK`가 있으면 옛 저장소의 첫 apply(100만에서 몇 분)를 건너뛴다.
    let old = std::env::var("HT_APPLY_SCALE_QUICK").is_err();
    let small = measure(sizes[0], old);
    let large = measure(sizes[1], old);
    println!("\n== 요약(가운데 값 ms — 10만 → 100만)");
    let pair = |label: &str, a: &Summary, b: &Summary| {
        println!("  {label}: {:.1} → {:.1}(×{:.2}) · COMMIT까지 {:.1} → {:.1}", a.apply_ms, b.apply_ms, b.apply_ms / a.apply_ms, a.total_ms, b.total_ms);
    };
    pair(&format!("덮는 트랙만 big-t{SAME} 넣기(단언)"), &small.same_add, &large.same_add);
    pair(&format!("덮는 트랙만 big-t{SAME} 되돌리기"), &small.same_back, &large.same_back);
    pair(&format!("덮는 트랙만 big-t{NATURAL} 넣기(트랙도 10배)"), &small.natural_add, &large.natural_add);
    pair(&format!("덮는 트랙만 big-t{NATURAL} 되돌리기"), &small.natural_back, &large.natural_back);
    pair("배치 전부 넣기", &small.whole_add, &large.whole_add);
    pair("배치 전부 되돌리기", &small.whole_back, &large.whole_back);
    pair("DLC 넣기", &small.dlc_add, &large.dlc_add);
    pair("DLC 빼기", &small.dlc_remove, &large.dlc_remove);
    let names: Vec<&'static str> = small.same_add.steps.iter().map(|(n, _)| *n).collect();
    let table: BTreeMap<&str, (f64, f64)> = names.iter().map(|n| (*n, (step_of(&small.same_add, n), step_of(&large.same_add, n)))).collect();
    println!("  걸음별(덮는 트랙만 넣기): {}", names.iter().map(|n| format!("{n} {:.1}→{:.1}", table[n].0, table[n].1)).collect::<Vec<_>>().join(" · "));
    println!("  통째 짓기 {:.1}초 → {:.1}초 · 저장소 {:.0} → {:.0}MB · 배치 JSON {:.0} → {:.0}MB 읽기 {:.0} → {:.0}ms · 다시 열기 {:.1} → {:.1}ms",
        small.build_ms / 1000.0, large.build_ms / 1000.0, small.store_mb, large.store_mb, small.plan_mb, large.plan_mb, small.parse_ms, large.parse_ms,
        small.reopen_ms, large.reopen_ms);
    println!("  쓰는 동안 읽기 — 덮는 트랙만: {} → {} · 배치 전부: {} → {}", reads_text(&small.reads_covered), reads_text(&large.reads_covered),
        reads_text(&small.reads_whole), reads_text(&large.reads_whole));
    for s in [&small, &large] {
        if let Some((run, reads, strip)) = &s.old_first {
            println!("  옛 저장소 첫 apply({}): {:.1}ms · COMMIT까지 {:.1}ms · 흉내 {:.1}초 · 덮는 색인만 {:.0}ms · {}", s.events, run.apply_ms, run.total_ms,
                strip / 1000.0, s.reindex_ms, reads_text(reads));
        }
        println!("  events.ord({}): {:.1}MB(사건 하나에 {:.2}바이트 · 가장 큰 값 {})", s.events, s.ord_bytes.0 / 1_048_576.0, s.ord_bytes.0 / s.events as f64,
            s.ord_bytes.1);
    }
    let limit = small.same_add.apply_ms * 1.5 + 50.0;
    assert!(large.same_add.apply_ms < limit, "100만 저장소의 apply {:.1}ms가 10만의 {:.1}ms × 1.5 + 50 = {limit:.1}ms를 넘습니다 — 쓰기가 저장소 크기에 비례합니다",
        large.same_add.apply_ms, small.same_add.apply_ms);
}

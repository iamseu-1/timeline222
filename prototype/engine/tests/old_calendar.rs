//! 옛 저장소(달력 표 다섯)에 DLC 넣기 — 감독 결정 2026-10-25: 리메이크 6단계(D10)에 달력 넷(히브리력 · 에티오피아력 · 콥트력 · 사카력 — `lay::cal::LATER`)의
//! 표를 더한 뒤 새 엔진이 달력 아홉 표를 모두 요구해, 그 전에 지은 저장소(표 다섯 — 3단계 시드 · 배포본 0.0.4)에는 보조 달력을 쓰지 않는 DLC도 '달력 표 없음'
//! (`code` calendar)으로 넣을 수 없었다. 이제 표에 없는 나중 달력은 건너뛴다: 넣기는 성공하고, 그 달력의 `cal:` 기록(날짜 칸의 그 달력 줄)만 없고, 받은 DLC가
//! 그 달력으로 날짜를 적었을 때만 답의 `notes`에 알림 한 줄(`packs::calendar_notes`) — 그 날짜를 쓴 항목은 읽지 못한 날짜로 빠진다. 저장소의 달력 표는 그대로.
//! 표 묶음은 검사의 잘린 표(`calendar-slice.json` — 아홉)에서 넷을 뺀 것(옛 저장소의 표와 같은 꼴 · 꼴 번호 1).
mod common;
use archive_engine::lay::{self, Opts, PackIn, Scope};
use archive_engine::legacy::{build_store, iso_at, seal_dlc};
use archive_engine::packs::{add_pack, AddOrder, PackReport, RustLayouter};
use archive_engine::write::write;
use common::oracle::{calendar_slice, ORACLE_NOW_MS};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::rc::Rc;

const TZ: i32 = 540;

/// 처음 다섯(음력 · 중국 음력 · 이슬람력 · 움 알쿠라 · 페르시아력)의 `cal:` 기록.
const FIVE: [&str; 5] = ["cal:chinese", "cal:dangi", "cal:islamic", "cal:persian", "cal:umalqura"];

/// 검사의 잘린 달력 표에서 나중 달력 넷을 뺀 표 묶음(옛 저장소의 표 — 꼴 번호 1 · 달력 다섯).
fn five_tables() -> Vec<u8> {
    let mut doc: Value = serde_json::from_slice(&calendar_slice()).expect("calendar-slice.json");
    let tables = doc["tables"].as_object_mut().expect("tables");
    for id in lay::cal::LATER {
        assert!(tables.remove(id).is_some(), "잘린 표에 {id}가 있어야 합니다(달력 아홉)");
    }
    assert_eq!(tables.len(), 5, "남은 표는 처음 다섯");
    doc["v"] = json!(1);
    serde_json::to_vec(&doc).unwrap()
}

/// 기본 DLC(합성 세계 `synth` — 보조 달력 날짜 없음)만 든 저장소를 그 달력 표로 통째로 짓는다(배치도 그 표로 — 옛 저장소에서는 옛 엔진이 다섯으로 배치했다).
fn store(table: &[u8], tag: &str) -> PathBuf {
    let base = std::fs::read(common::node::repo_root().join("prototype").join("fixtures").join("oracle").join("synth.json")).unwrap();
    let base = seal_dlc(&base);
    let key = archive_engine::htpack_raw(&base).unwrap()["id"].as_str().unwrap().to_owned();
    let opts = Opts { now_ms: ORACLE_NOW_MS, tz_min: TZ, upto: None, scope: Scope::All, calendar: Some(Rc::new(table.to_vec())) };
    let plan = lay::export(&[PackIn { name: format!("{key}.htpack"), bytes: base.clone() }], &opts)
        .unwrap_or_else(|e| panic!("{tag}: 기본 DLC 배치 — 표에 없는 나중 달력은 건너뛰어야 합니다: {e}"));
    let path = common::scratch(tag);
    build_store(&plan, &[(key, base)], &path, &iso_at(ORACLE_NOW_MS, TZ), table).unwrap_or_else(|e| panic!("{tag}: 통째 짓기 — {e}"));
    path
}

/// 시험 DLC 하나(트랙 하나 · 띠 하나 · 사건 여럿)를 봉인해 임시 파일로.
fn dlc(id: &str, name: &str, events: Value) -> PathBuf {
    let body = json!({
        "format": "history-timeline-dlc", "formatVersion": 3, "id": id, "name": name, "version": "1.0.0", "author": "검사 자료",
        "description": "옛 저장소(달력 표 다섯) 넣기 시험 — 모든 이름은 지어낸 것입니다.", "requires": [],
        "tracks": [{ "id": format!("{id}-t"), "name": format!("{name} 나라"), "order": 90 }],
        "periods": [{ "id": "p1", "track": format!("{id}-t"), "name": format!("{name} 왕국"), "start": 1500, "end": 1700 }],
        "events": events,
    });
    let dir = std::env::temp_dir().join(format!("archive-correct-{}-oldcal", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join(format!("{id}.htpack"));
    std::fs::write(&file, seal_dlc(&serde_json::to_vec(&body).unwrap())).unwrap();
    file
}

fn add(path: &Path, file: &Path) -> archive_engine::Result<PackReport> {
    write(path, |tx| add_pack(tx, &AddOrder { files: vec![file.to_path_buf()], ..AddOrder::default() }, &RustLayouter))
}

fn column(path: &Path, sql: &str) -> Vec<String> {
    let db = rusqlite::Connection::open(path).unwrap();
    let mut stmt = db.prepare(sql).unwrap();
    stmt.query_map([], |r| r.get::<_, String>(0)).unwrap().map(Result::unwrap).collect()
}

fn calendar_blob(path: &Path) -> Vec<u8> {
    rusqlite::Connection::open(path).unwrap().query_row("SELECT bytes FROM blobs WHERE key='calendar:table'", [], |r| r.get(0)).unwrap()
}

fn cal_records(path: &Path) -> Vec<String> { column(path, "SELECT uid FROM entities WHERE kind='cal' ORDER BY uid") }

fn events_of(path: &Path, id: &str) -> Vec<String> { column(path, &format!("SELECT uid FROM events WHERE uid LIKE '{id}/%' ORDER BY uid")) }

/// 옛 달력만 쓰는 DLC(양력 · 음력 — 표가 있음 · 불기 — 표 없이 산수): 성공 · 알림 없음 · 사건 셋 다 · `cal:` 기록은 처음 다섯 · 저장소의 표 그대로.
/// 새 달력을 쓰는 DLC(히브리력 · 에티오피아력): 성공 · 알림 한 줄(그 DLC · 그 두 달력 이름 · 형식 4 알림과 섞이지 않음) · 그 날짜의 사건만 빠짐 · `cal:` 기록은
/// 처음 다섯(그 달력 줄 없음) · 표 그대로. 견줌: 같은 DLC를 새 저장소(표 아홉)에 넣으면 알림 없이 사건 셋 다 · `cal:` 기록 아홉.
#[test]
fn old_store_skips_later_calendars_and_notes_only_dlcs_that_use_them() {
    let five = five_tables();
    let old = store(&five, "oldcal-five");
    assert_eq!(cal_records(&old), FIVE, "옛 저장소의 배치: 처음 다섯만 싣는다(넷은 건너뜀)");
    let blob = calendar_blob(&old);

    let plain = dlc("cal-plain", "달력 시험 옛 달력", json!([
        { "id": "e1", "track": "cal-plain-t", "title": "양력 사건", "start": "1592-05-23" },
        { "id": "e2", "track": "cal-plain-t", "title": "음력 사건", "start": "음력 1600-03-01" },
        { "id": "e3", "track": "cal-plain-t", "title": "불기 사건", "start": "불기 2150-01-01" },
    ]));
    let r = add(&old, &plain).unwrap_or_else(|e| panic!("새 달력을 쓰지 않는 DLC는 옛 저장소에 들어가야 합니다: {e}"));
    assert!(r.notes.is_empty(), "새 달력을 쓰지 않으면 알림 없음: {:?}", r.notes);
    assert_eq!(events_of(&old, "cal-plain"), ["cal-plain/e1", "cal-plain/e2", "cal-plain/e3"]);
    assert_eq!(cal_records(&old), FIVE, "넣은 뒤에도 처음 다섯");
    assert_eq!(calendar_blob(&old), blob, "저장소의 달력 표는 건드리지 않는다");

    let uses = || dlc("cal-new", "달력 시험 새 달력", json!([
        { "id": "e1", "track": "cal-new-t", "title": "양력 사건", "start": "1592-05-23" },
        { "id": "e2", "track": "cal-new-t", "title": "히브리력 사건", "start": "히브리력 5400-08-15" },
        { "id": "e3", "track": "cal-new-t", "title": "에티오피아력 사건", "start": "에티오피아력 1600-01-01" },
    ]));
    let r = add(&old, &uses()).unwrap_or_else(|e| panic!("새 달력을 쓰는 DLC도 옛 저장소에 들어가야 합니다(그 달력만 건너뜀): {e}"));
    assert_eq!(r.notes.len(), 1, "알림 한 줄: {:?}", r.notes);
    let note = &r.notes[0];
    assert!(note.starts_with("«달력 시험 새 달력»: 이 저장소의 달력 표에 히브리력 · 에티오피아력이 없어 ") && !note.contains("형식 4"), "{note}");
    assert_eq!(events_of(&old, "cal-new"), ["cal-new/e1"], "그 달력으로 적은 날짜의 사건만 빠진다");
    assert_eq!(events_of(&old, "cal-plain").len(), 3, "앞서 넣은 DLC는 그대로");
    assert_eq!(cal_records(&old), FIVE, "그 달력 줄(cal: 기록)은 없다");
    assert_eq!(calendar_blob(&old), blob, "저장소의 달력 표는 건드리지 않는다");

    // 견줌 — 새 저장소(표 아홉): 같은 DLC가 알림 없이 다 들고 `cal:` 기록은 아홉.
    let new = store(&calendar_slice(), "oldcal-nine");
    let r = add(&new, &uses()).unwrap();
    assert!(r.notes.is_empty(), "새 저장소에는 알림 없음: {:?}", r.notes);
    assert_eq!(events_of(&new, "cal-new"), ["cal-new/e1", "cal-new/e2", "cal-new/e3"]);
    let mut nine: Vec<String> = FIVE.iter().map(|s| (*s).to_owned()).chain(lay::cal::LATER.iter().map(|id| format!("cal:{id}"))).collect();
    nine.sort();
    assert_eq!(cal_records(&new), nine);
}

/// 건너뛰기는 표 묶음이 있고 나중 달력만 없을 때뿐 — 처음 다섯 가운데 하나가 없는 표(깨진 표)는 예전처럼 배치를 거절한다('달력 표 없음' — 넣기는 `code` calendar).
#[test]
fn a_missing_first_five_table_still_refuses() {
    let mut doc: Value = serde_json::from_slice(&five_tables()).unwrap();
    doc["tables"].as_object_mut().unwrap().remove("persian");
    let opts = Opts { now_ms: ORACLE_NOW_MS, tz_min: TZ, upto: None, scope: Scope::All, calendar: Some(Rc::new(serde_json::to_vec(&doc).unwrap())) };
    let base = seal_dlc(&std::fs::read(common::node::repo_root().join("prototype").join("fixtures").join("oracle").join("synth.json")).unwrap());
    let e = lay::export(&[PackIn { name: "synth.htpack".into(), bytes: base }], &opts).expect_err("페르시아력 표가 없으면 거절").to_string();
    assert!(e.contains("달력 표 없음") && e.contains("페르시아력"), "{e}");
}

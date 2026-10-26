//! 여러 검사가 함께 쓰는 작은 정답 자료: 자료집 2 · 트랙 2 · 줄 8 · 띠 24 · 칸 72 · 사건 513,
//! 그리고 스키마 3의 새 것(분류 3 · 민족 묶음 2 · 날짜 칸 3 · 일반 항목 3 · 항목 기록 2).
#![allow(dead_code)]
use archive_engine::builder::{AxisCellIn, Builder, CellIn, EventIn, GroupIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use archive_engine::DAY;
use std::path::{Path, PathBuf};

pub mod modcheck;
pub mod node;
pub mod oracle;
pub mod plans;
pub mod same;

/// 검사 하나의 걸린 시간을 끝에(실패해도) 찍는다 — `let _t = common::clock("이름");`(고침 2회차 — 검사별 시간 표의 근거). PC가 다른 일로 바쁘면 그만큼 는다.
pub struct Clock(&'static str, std::time::Instant);

impl Drop for Clock {
    fn drop(&mut self) {
        eprintln!("검사 시간 {}: {:.1}초", self.0, self.1.elapsed().as_secs_f64());
    }
}

pub fn clock(name: &'static str) -> Clock {
    Clock(name, std::time::Instant::now())
}

/// 띠의 기간(일, 양 끝 포함).
pub const BANDS: [(i64, i64); 3] = [(-500, -100), (-99, 200), (201, 600)];
pub const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: -1, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

/// 검사마다 다른 임시 저장소 경로. 남아 있던 파일은 검사 시작 때만 지운다.
/// 처음 부를 때 한 번, 끝난 검사 프로세스가 임시 폴더에 남긴 오래된 검사 저장소 · 폴더(`archive-<갈래>-<pid>-…`)를 치운다([`sweep_stale`]).
/// 큰 검사는 임시 폴더를 채우므로(C:가 차면 'database or disk is full'로 넘어진다) `$env:TMP`를 넉넉한 드라이브로 돌려 돌린다(dev.ps1 머리말).
pub fn scratch(name: &str) -> PathBuf {
    sweep_stale();
    let path = std::env::temp_dir().join(format!("archive-correct-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    path
}

/// 검사들이 임시 폴더에 쓰는 이름의 갈래(`archive-<갈래>-<pid>-…` — 각 검사 파일의 `temp_dir().join(…)`).
/// 새 갈래를 쓰는 검사를 더하면 여기에도 — tests/correctness.rs의 `scratch_kinds_cover_every_test`가 검사 파일의 임시 이름 머리를 훑어 지킨다(판정 R58 ⑤ Minor: doclist · variants가 빠져 쌓였다).
pub const SCRATCH_KINDS: [&str; 20] = ["correct", "blobs", "boards", "doclist", "echo", "filter", "format3", "generate", "htlayout", "import", "kin", "layout-static", "lens", "lod",
    "names", "query", "schema4", "spheres", "variants", "year-cycle"];

/// 끝난 검사 프로세스가 남긴 검사 저장소 · 폴더를 한 번 치운다(과제 7c 얹힌 몫 9 — 같은 pid의 같은 이름만 지우던 탓에 `archive-correct-*` 등이 수천 개 ·
/// 수 GB 쌓였다). 이름의 pid가 지금 돌지 않고 · 이 프로세스가 아니며 · 10분 넘게 손대지 않은 것만 지운다(다른 갈래가 같은 때 돌리는 검사의 것은 남는다 —
/// 열려 있는 저장소는 어차피 지워지지 않는다). 도는 프로세스 목록을 읽지 못하면 아무것도 지우지 않는다.
fn sweep_stale() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let Some(alive) = running_pids() else { return };
        let me = std::process::id();
        let Ok(list) = std::fs::read_dir(std::env::temp_dir()) else { return };
        for entry in list.flatten() {
            let Some(pid) = scratch_pid(&entry.file_name().to_string_lossy()) else { continue };
            if pid == me || alive.contains(&pid) {
                continue;
            }
            let idle = entry.metadata().and_then(|m| m.modified()).ok().and_then(|t| t.elapsed().ok());
            if idle.is_none_or(|age| age < std::time::Duration::from_secs(600)) {
                continue;
            }
            let path = entry.path();
            let _ = if path.is_dir() { std::fs::remove_dir_all(&path) } else { std::fs::remove_file(&path) };
        }
    });
}

/// `archive-<갈래>-<pid>-…`의 pid(갈래는 [`SCRATCH_KINDS`]) — 검사가 만든 이름이 아니면 None.
fn scratch_pid(name: &str) -> Option<u32> {
    let rest = name.strip_prefix("archive-")?;
    let kind = SCRATCH_KINDS.iter().find(|k| rest.strip_prefix(**k).is_some_and(|r| r.starts_with('-')))?;
    let digits = rest[kind.len() + 1..].split('-').next()?;
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    digits.parse().ok()
}

/// 지금 도는 프로세스 번호들(Windows `tasklist` · 그 밖은 `/proc`). 읽지 못하면 None.
fn running_pids() -> Option<std::collections::HashSet<u32>> {
    if cfg!(windows) {
        let out = std::process::Command::new("tasklist").args(["/FO", "CSV", "/NH"]).output().ok().filter(|o| o.status.success())?;
        // 줄마다 "이름","pid",… — 둘째 칸.
        let pids: std::collections::HashSet<u32> = String::from_utf8_lossy(&out.stdout).lines()
            .filter_map(|line| line.split("\",\"").nth(1).and_then(|p| p.trim_matches('"').parse().ok())).collect();
        (!pids.is_empty()).then_some(pids)
    } else {
        let pids: std::collections::HashSet<u32> = std::fs::read_dir("/proc").ok()?.flatten()
            .filter_map(|e| e.file_name().to_str().and_then(|s| s.parse().ok())).collect();
        (!pids.is_empty()).then_some(pids)
    }
}

/// 파일 하나의 SHA-256(소문자 16진 글) — '실패하면 저장소 파일이 쓰기 전과 같다'를 비트 단위로 재는 데 쓴다.
pub fn sha256_file(path: &Path) -> String {
    use sha2::{Digest, Sha256};
    use std::io::Read;
    let mut file = std::fs::File::open(path).unwrap();
    let (mut hash, mut buf) = (Sha256::new(), [0u8; 65536]);
    loop {
        let n = file.read(&mut buf).unwrap();
        if n == 0 {
            break;
        }
        hash.update(&buf[..n]);
    }
    format!("{:x}", hash.finalize())
}

/// meta의 정수 값 하나(계획 P4 과제 5d — 보는 범위 `min` · `max`를 따로 단언한다).
pub fn meta_i64(path: &Path, key: &str) -> i64 {
    let db = rusqlite::Connection::open(path).unwrap();
    let text: String = db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get(0)).unwrap_or_else(|e| panic!("meta.{key}: {e}"));
    text.parse().unwrap_or_else(|e| panic!("meta.{key} = {text}: {e}"))
}

/// 저장소의 트랙 수.
pub fn track_count(path: &Path) -> usize {
    let db = rusqlite::Connection::open(path).unwrap();
    db.query_row("SELECT count(*) FROM tracks", [], |r| r.get::<_, i64>(0)).unwrap() as usize
}

/// 이 계획(P4) 전에 지은 저장소를 흉내 낸다(옛 DLC의 약속 2 · 과제 5d 얹힌 몫 11 · 13 · 과제 6 얹힌 몫 5): 트랙 지문 표(`track_prints`) ·
/// 그림 바이트 표(`blobs` — 문서 그림 전의 저장소) · 항목 기록의 넣은 차례 · 지문 열(`entities.ord` · `sum`) · `meta.now` · 사건의 트랙 안 차례(`events.ord`) ·
/// 요약의 트랙 안 차례(`summaries.ords`) · 띠의 줄 색인(`periods_row`)을 지우고, 덮는 색인(`events_time`)을 `ord` 없이 다시 짓는다
/// (`builder::reindex` — 열이 없으면 빼고 짓는다). 이 계획 전의 저장소는 스키마 4(리메이크 3단계) 전이기도 하므로 끝에 [`strip_schema4`]로 띠 `form` 열 ·
/// 문화권 단위 줄 표를 걷고 판을 '3'(열쇠 ≠ 자리인 '4.1' 저장소면 '3.1')으로 적는다 — 부르는 검사가 판 4로 오르는 길까지 지난다.
/// 스키마 4의 열 · 표는 남겨야 하는 검사(지문 표만 없는 꼴 — 실제로는 없는 저장소로 지킴 하나를 따로 볼 때)는 [`strip_p4_columns`].
pub fn strip_new_columns(path: &Path) {
    strip_p4_columns(path);
    let split = rusqlite::Connection::open(path).unwrap()
        .query_row("SELECT value FROM meta WHERE key='schema'", [], |r| r.get::<_, String>(0)).unwrap() == "4.1";
    strip_schema4(path, if split { "3.1" } else { "3" });
}

/// [`strip_new_columns`]에서 스키마 4를 걷는 몫만 뺀 것 — 이 계획(P4)이 더한 표 · 열 · 색인만 지운다(판 · 띠 `form` · 문화권 단위 줄은 그대로).
pub fn strip_p4_columns(path: &Path) {
    {
        let db = rusqlite::Connection::open(path).unwrap();
        db.execute_batch(
            "DROP TABLE track_prints;
             DROP TABLE blobs;
             ALTER TABLE entities DROP COLUMN ord;
             ALTER TABLE entities DROP COLUMN sum;
             DELETE FROM meta WHERE key='now';
             DROP INDEX periods_row;
             DROP INDEX events_time;
             ALTER TABLE events DROP COLUMN ord;
             ALTER TABLE summaries DROP COLUMN ords;",
        ).unwrap();
    }
    archive_engine::builder::reindex(path).unwrap();
}

/// 이 계획(리메이크 3단계 · 스키마 4) 전의 엔진이 지은 판 3 저장소를 흉내 낸다(계약 1-1 — 옛 저장소는 새 열 · 표가 없을 뿐이다):
/// 띠의 형식 4 뜻 열(`periods.form`)과 문화권 단위 줄 표(`sphere_lines`)를 걷고 판(`meta.schema`)을 `version`('3' · 열쇠 ≠ 자리면 '3.1')으로 적는다.
/// SQLite는 색인이 품은 열을 지우지 못하므로 `form`을 품은 색인이 있으면 먼저 지운다(지금 짓기에는 없다 — 뒤에 생겨도 이 흉내가 깨지지 않게).
/// 나머지 표 · 열 · meta는 그대로라, 같은 배치의 저장소에서 form을 0으로 · 줄을 비운 것과 답이 같아야 한다(`tests/schema4.rs`).
pub fn strip_schema4(path: &Path, version: &str) {
    let db = rusqlite::Connection::open(path).unwrap();
    let indexes: Vec<String> = {
        let mut stmt = db.prepare("SELECT DISTINCT l.name FROM pragma_index_list('periods') AS l, pragma_index_info(l.name) AS i \
            WHERE l.origin='c' AND i.name='form'").unwrap();
        let out = stmt.query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
        out
    };
    for name in indexes {
        db.execute_batch(&format!("DROP INDEX \"{name}\"")).unwrap();
    }
    db.execute_batch("ALTER TABLE periods DROP COLUMN form; DROP TABLE sphere_lines;").unwrap();
    assert_eq!(db.execute("UPDATE meta SET value=?1 WHERE key='schema'", [version]).unwrap(), 1, "meta.schema가 없습니다");
}

/// 저장소의 트랙을 거꾸로 차례로 끝 번호 + 3으로 옮겨(`rowmap::rekey_track` — `tests/rowkeys.rs`의 `scrambled`와 같은 옮김) 모든 트랙의 줄 열쇠를 자리와
/// 가르고 판을 '4.1'(`schema::VERSION_SPLIT`)로 적는다(제자리). 뒤에 [`strip_schema4`]('3.1')를 부르면 열쇠 ≠ 자리인 판 3 저장소가 된다.
pub fn split_keys(path: &Path) {
    let mut db = rusqlite::Connection::open(path).unwrap();
    db.execute_batch("PRAGMA foreign_keys=ON").unwrap();
    let tx = db.transaction().unwrap();
    tx.execute_batch("PRAGMA defer_foreign_keys=ON").unwrap();
    let tracks: Vec<i64> = tx.prepare("SELECT DISTINCT track FROM rows ORDER BY track DESC").unwrap()
        .query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    for t in tracks {
        let next: i64 = tx.query_row("SELECT MAX(id)+1 FROM rows", [], |r| r.get(0)).unwrap();
        archive_engine::rowmap::rekey_track(&tx, t, next + 3).unwrap();
    }
    tx.execute("UPDATE meta SET value=?1 WHERE key='schema'", [archive_engine::schema::VERSION_SPLIT]).unwrap();
    tx.commit().unwrap();
}

/// 저장소 표의 열 이름이 있는가 · 색인의 SQL(없으면 빈 글).
pub fn has_column(path: &Path, table: &str, column: &str) -> bool {
    let db = rusqlite::Connection::open(path).unwrap();
    let found = db.prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name=?1")).unwrap().exists([column]).unwrap();
    found
}

pub fn index_sql(path: &Path, name: &str) -> String {
    let db = rusqlite::Connection::open(path).unwrap();
    db.query_row("SELECT COALESCE(sql,'') FROM sqlite_master WHERE type IN ('index','table') AND name=?1", [name], |r| r.get(0)).unwrap_or_default()
}

/// uid · 열쇠 → 번호(계획 P4 과제 5c — 다시 쓴 뒤에도 같은 uid의 띠 · 사건 · 같은 열쇠의 변형이 옛 번호를 쓰는지 잰다).
/// 열쇠는 갈래를 앞에 붙인다(`띠 a/ta-1` · `사건 a/e0` · `변형 host:a/ta-host`). 이름 없는 띠 · 사건은 싣지 않는다.
pub fn uid_ids(path: &Path) -> std::collections::BTreeMap<String, i64> {
    let db = rusqlite::Connection::open(path).unwrap();
    let mut out = std::collections::BTreeMap::new();
    for (tag, sql) in [("띠", "SELECT uid,id FROM periods WHERE uid<>''"), ("사건", "SELECT uid,id FROM events WHERE uid<>''"), ("변형", "SELECT key,id FROM variants")] {
        let mut stmt = db.prepare(sql).unwrap();
        for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))).unwrap() {
            let (uid, id) = row.unwrap();
            assert!(out.insert(format!("{tag} {uid}"), id).is_none(), "{tag} {uid}이 둘입니다");
        }
    }
    out
}

#[derive(Clone)]
pub struct Sample { pub id: i64, pub pack: i64, pub lane: i64, pub start: Option<i64>, pub end: Option<i64>, pub lo: Option<i64>, pub hi: Option<i64>, pub importance: i64, pub band: i64 }

/// 513개 정답 사건: 자료집 2 · 줄 8 · 기원전(음수 분) · 긴 기간(11의 배수) · 이설 폭(7의 배수) · 날짜 미정(50의 배수).
pub fn build(path: &PathBuf) -> Vec<Sample> {
    let mut b = Builder::create(path).unwrap();
    // (줄, 시작, 끝, 띠 번호) — 사건이 든 띠(events.band)를 찾는 데 쓴다.
    let mut row_bands: Vec<(i64, i64, i64, i64)> = Vec::new();
    let packs = [b.pack("검사용 하나", None).unwrap(), b.pack("검사용 둘", None).unwrap()];
    for (ord, (key, name, color)) in [("govern", "다스림", 0x8f7fb0u32), ("build", "지음", 0x6f9a86), ("lore", "이야기", 0x9a6f8a)].iter().enumerate() {
        b.category(packs[0], ord as i64, key, name, *color).unwrap();
    }
    for (index, pack) in packs.iter().enumerate() {
        let track = b.track_full(&TrackIn {
            pack: *pack, name: if index == 0 { "첫 트랙" } else { "둘째 트랙" }, color: 0xc8b193 + index as u32,
            dynasty: i64::from(index == 0), leader: 1, cabinet: 1, organ: 1, rail_levels: 2 + index as i64, key: "",
        }).unwrap();
        let first = 4 * index as i64;
        for r in 0..4i64 {
            // 줄 하나는 3판의 새 단(탭 · 바탕 문화 이름 · 분류별 글줄)을 켠다.
            let more = if r == 1 {
                RowExtra { kind: 1, group_start: 0, scope_pad: 6, phase: 1, rank: 1, cats: vec![0, 2], fig: 2, fig_wide: 3, dep: 25, zones: 1, hem: 1 , variant: 0}
            } else {
                RowExtra { group_start: i64::from(r == 0), ..Default::default() }
            };
            let row = b.row_full(track, &GEO, &more).unwrap();
            // 줄마다 띠 셋: 가운데 띠는 0분(타일 경계)을 가로지른다. 첫 줄의 첫 띠는 시작 미정, 끝 띠는 끝 미정.
            for (i, (from, to)) in BANDS.iter().enumerate() {
                let fuzzy = if row == 0 && i == 0 { 1 } else if row == 0 && i == 2 { 2 } else { 0 };
                let (start, end) = (from * DAY, to * DAY + DAY - 1);
                let band = b.period_full(&PeriodIn {
                    pack: *pack, row, start, end, fuzzy, color: 0xa0bcc5 + i as u32, name: &format!("별여울 {row}줄 {}번 띠", i + 1),
                    look: if i == 1 { 0x21 } else { 0 }, tag: if i == 1 { "전해 오는 이야기" } else { "" }, sub: if i == 2 { 3 } else { 0 },
                    uid: &format!("band-{row}-{i}"), variant: 0, form: 0,
                }).unwrap();
                let half = start + (end - start) / 2;
                b.cell(band, 1, start, half, &format!("{}대 가람", i + 1)).unwrap();
                b.cell(band, 1, half + 1, end, &format!("{}대 나래", i + 2)).unwrap();
                b.cell_full(&CellIn { period: band, kind: 2, start, end: start + (end - start) / 3, name: "해솔 내각", lane: 1, style: 4, color: 0xd1a9b9, variant: 0 }).unwrap();
                // 왼쪽 줄 이름 칸의 후보(계약 6-8절): 원소의 JSON을 그대로 보존한다.
                b.row_label(row, start, end, band, &format!(r#"{{"period":"band-{row}-{i}","row":{row},"kind":0,"name":"별여울 {row}줄 {}번 띠"}}"#, i + 1)).unwrap();
                row_bands.push((row, start, end, band));
            }
        }
        b.group(&GroupIn { track, depth: 0, first_row: first, row_count: 4, name: "윗물 겨레", color: 0xbcd8c1, kind: 0 }).unwrap();
        // 날짜 칸: 트랙마다 연호 하나. 공통 줄(트랙 없음)은 아래에 하나 더 둔다.
        b.axis_cell(&AxisCellIn { pack: *pack, kind: 2, track: Some(track), lane: 0, start: -500 * DAY, end: 200 * DAY, name: "첫길 연호", color: 0xc8b193, style: 1, strip: 7, seq: 0 }).unwrap();
    }
    b.axis_cell(&AxisCellIn { pack: packs[0], kind: 1, track: None, lane: 0, start: -500 * DAY, end: 600 * DAY + DAY - 1, name: "첫 시대", color: 0x9dbea8, style: 0, strip: 0, seq: 0 }).unwrap();
    b.epoch(packs[0], -500 * DAY, 600 * DAY + DAY - 1, 0xc8b193, "첫 시대").unwrap();
    // 일반 항목: 16 속국 이름표(타일 경계를 가로지른다) · 17 관계선(줄 0~3에 걸친다).
    b.item(&ItemIn { pack: packs[0], section: 16, row: 0, row2: 0, start: -99 * DAY, end: 200 * DAY + DAY - 1, lod: None, ref_id: 2, ref_kind: 1,
        name: "별여울 속국", color: 0xa0bcc5, a: 1, b: 0, c: 0, d: 0, text2: "곁글", variant: 0 }).unwrap();
    b.item(&ItemIn { pack: packs[0], section: 16, row: 2, row2: 2, start: 201 * DAY, end: 600 * DAY, lod: None, ref_id: 0, ref_kind: 0,
        name: "해솔 속국", color: 0x9dbea8, a: 2, b: 0, c: 0, d: 0, text2: "", variant: 0 }).unwrap();
    b.item(&ItemIn { pack: packs[0], section: 17, row: 0, row2: 3, start: 0, end: 0, lod: Some(12), ref_id: 1, ref_kind: 1,
        name: "", color: 0x8a8f96, a: 1, b: 2, c: 0, d: 0, text2: "", variant: 0 }).unwrap();
    b.entity("band-0-0", packs[0], "period", r#"{"uid":"band-0-0","name":"별여울 0줄 1번 띠"}"#).unwrap();
    b.entity("event-1", packs[0], "event", r#"{"uid":"event-1","title":"해솔별 星河"}"#).unwrap();
    let mut samples = Vec::new();
    for id in 1..=513i64 {
        let start = (id * 97 % 900 - 450) * DAY + (id % 60);
        let end = start + if id % 11 == 0 { 900 * DAY } else { id % 5 };
        let spread = if id % 7 == 0 { 50 * DAY } else { 0 };
        let dated = id % 50 != 0;
        let title = if id == 1 { "해솔별 星河" } else if id == 2 { "해 다른 글 솔별" } else { "가상 사건" };
        let mut sample = Sample {
            id,
            pack: packs[(id % 2) as usize],
            lane: id % 8,
            start: dated.then_some(start),
            end: dated.then_some(end),
            lo: dated.then_some(start - spread),
            hi: dated.then_some(end + spread),
            importance: 1 + i64::from(id % 3 == 0) + i64::from(id % 9 == 0),
            band: 0,
        };
        let label = if id % 4 == 0 { format!("{id}년") } else { String::new() };
        // 그 사건이 든 띠: 같은 줄에서 시작 시각을 품은 띠(없으면 0).
        let band = sample.start.and_then(|at| row_bands.iter().find(|(row, from, to, _)| *row == sample.lane && *from <= at && at <= *to).map(|b| b.3)).unwrap_or(0);
        sample.band = band;
        let given = b.event(&EventIn {
            pack: sample.pack, lane: sample.lane, start: sample.start, end: sample.end, lo: sample.lo, hi: sample.hi,
            importance: sample.importance, title, body: "검사 본문", source: None, raw: None,
            look: id % 3, label: &label, rail: id % 2, uid: "", band, variant: 0,
        }).unwrap();
        assert_eq!(given, id, "사건 번호는 넣은 순서대로 1부터");
        samples.push(sample);
    }
    b.finalize(&[("seed", "검사".to_owned())]).unwrap();
    samples
}

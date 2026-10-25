//! 한 벌 P3 과제 17 — Rust로 짓기(`archive-tool build`)의 틀. 짓기는 두 단이다: ① 팩 읽기 · `lay::export(Scope::All)`(배치) ② 그 배치 값으로 저장소 짓기
//! (`legacy::build_store` — 가져오기와 같은 짓기 + 지은 날 `meta.now` + 달력 표 `blobs`의 `calendar:table`).
//! - ②는 지금 정답지의 Node 통째 배치(`prototype/results/oracle/<자료>/upto-lens.json` — 모듈 스물 뒤 = Node 내보내기)로 잰다: 같은 배치를 지금 길(`import-layout` =
//!   `import_layout_value`)로 지은 저장소와 `canon --queries`가 같고 · meta는 지은 날만 다르고 · `lay::calendar_of`가 넣은 표(판정 R18의 잘린 표)를 그대로 돌려준다.
//! - ①(모듈 스물이 다 옮겨짐 — 2026-10-22 `p34-lay`)은 정답지 Node 내보내기와 차이 0(값 · json 글 바이트)이고, 명령의 몸(① → ②)으로 지은 저장소가
//!   정답지 배치로 지은 저장소와 같다(아래 `stage_one_…` — 옮기지 않은 모듈이 생기면 그 이름을 담아 거절하는지로 바뀐다). 달력 표 없이는 짓지 않는다(판정 R36).
//!   두 길 전체의 견줌은 `node prototype/scripts/build-check.mjs`(과제 17 걸음 1 · 3).
mod common;
use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::lay::{self, MODULES};
use archive_engine::legacy::{build_files, build_files_with, build_layout, build_store, import_layout_value, iso_at, iso_time, seal_dlc};
use common::oracle::{calendar_slice, fixtures, inputs, oracle, Fixture, ORACLE_NOW, ORACLE_NOW_MS, ORACLE_TZ_MIN};
use serde_json::Value;
use common::same::meta;
use std::path::Path;

/// 정답지 자료의 원본 — (글자 id, .htpack 바이트)를 입력 차례대로. `.json` 입력은 본문 바이트 그대로 싼다(`seal_dlc` — `archive-tool build`와 같은 길).
fn originals(f: &Fixture) -> Vec<(String, Vec<u8>)> {
    inputs(f).into_iter().map(|p| {
        let bytes = if p.name.to_ascii_lowercase().ends_with(".htpack") { p.bytes } else { seal_dlc(&p.bytes) };
        let raw = archive_engine::htpack_raw(&bytes).unwrap_or_else(|e| panic!("{}: {} — {e}", f.name, p.name));
        (raw["id"].as_str().unwrap_or_default().to_owned(), bytes)
    }).collect()
}

/// 정답지의 통째 배치(머리 `$oracle`을 뗀 것).
fn node_plan(f: &Fixture) -> Value {
    let mut v = oracle(f, "upto-lens.json");
    v.as_object_mut().unwrap().remove("$oracle");
    v
}

#[test]
fn iso_time_reads_the_clock_and_the_zone() {
    let _t = common::clock("iso_time_reads_the_clock_and_the_zone");
    assert_eq!(iso_time(ORACLE_NOW), Some((ORACLE_NOW_MS, ORACLE_TZ_MIN)));
    assert_eq!(iso_time("2026-10-15T03:00:00Z"), Some((ORACLE_NOW_MS, 540)), "Z는 시간대를 모르는 글 — 서울로 본다");
    assert_eq!(iso_time("2026-10-14T22:00:00-05:00"), Some((ORACLE_NOW_MS, -300)));
    assert_eq!(iso_time("2026-10-15T12:00:00.250+09:00"), Some((ORACLE_NOW_MS + 250.0, 540)));
    assert_eq!(iso_time("1969-12-31T23:59:59Z"), Some((-1000.0, 540)), "1970년 앞");
    for bad in ["", "2026-10-15", "2026-10-15T12:00:00", "2026-13-15T12:00:00Z", "2026-10-15T12:00:00+0900", "2026-10-15T12:00:00+09:00x", "2026-1a-15T12:00:00Z"] {
        assert_eq!(iso_time(bad), None, "{bad:?}");
    }
    for (ms, tz) in [(ORACLE_NOW_MS, 540), (ORACLE_NOW_MS + 172_800_000.0, 540), (0.0, -300), (-62_135_596_800_000.0, 0)] {
        let text = iso_at(ms, tz);
        assert_eq!(iso_time(&text), Some((ms, tz)), "{text}");
    }
    assert_eq!(iso_at(ORACLE_NOW_MS, 540), ORACLE_NOW);
}

/// 과제 17 ②: 같은 Node 배치를 지금 길(import-layout)과 짓기 ②로 지어 canon(조회 포함)이 같다 · meta는 지은 날만 다르다(짓기 ②는 준 글 그대로) ·
/// 달력 표는 짓기 ②의 저장소에만 있고 `calendar_of`가 넣은 바이트를 그대로 돌려준다. 자료마다 `#[test]` 하나(고침 2회차 — 나란히 · 자료별 시간).
/// canon은 `archive-tool canon --queries`(단계 0 · 4 · 7 · 8 · 11 · 14 · 조회 목록)와 같은 것 — 등불 견본만 글이 많아(한 짝에 수십 분) 성긴 단계 · 조회 없이 견준다
/// (그 대신 meta 전부 · 아래 표 대조는 같다 — 짓기 ②는 가져오기와 같은 `fill_into`라 다른 자료가 조회까지 본다).
fn stage_two(name: &str) {
    // 건너뛰는 것은 KTL(감독 실자료 — 감독 PC에만)뿐 — 나머지 자료가 없으면 실패(조용히 지나가지 않게 · 고침 3회차).
    let Some(f) = fixtures().into_iter().find(|f| f.name == name) else {
        assert!(name.contains("ktl"), "{name}: 정답지 자료가 없습니다");
        eprintln!("{name} 건너뜀 — KTL 자료 파일이 없습니다(감독 PC에만)");
        return;
    };
    let table = calendar_slice();
    let opts = if f.name == "lantern" {
        CanonOpts { levels: vec![8, 11, 14], max_x: 8, queries: false }
    } else {
        CanonOpts { levels: vec![0, 4, 7, 8, 11, 14], max_x: 32, queries: true }
    };
    let (plan, packs) = (node_plan(&f), originals(&f));
    let tag = f.name.replace(['@', '+'], "_");
    let (node, rust) = (common::scratch(&format!("bd-node-{tag}")), common::scratch(&format!("bd-rust-{tag}")));
    import_layout_value(&plan, &packs, &node).unwrap_or_else(|e| panic!("{}: 지금 길 — {e}", f.name));
    let counts = build_store(&plan, &packs, &rust, ORACLE_NOW, &table).unwrap_or_else(|e| panic!("{}: 짓기 ② — {e}", f.name));
    assert!(counts["events"].as_u64().is_some(), "{}: 수 세기 {counts}", f.name);
    assert!(canon_store(&rust, &opts).unwrap() == canon_store(&node, &opts).unwrap(), "{}: canon이 지금 길과 다릅니다", f.name);
    let rows = |p: &Path, sql: &str| -> Vec<(String, Option<String>)> {
        let db = rusqlite::Connection::open(p).unwrap();
        let mut stmt = db.prepare(sql).unwrap();
        let out = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
        out
    };
    let tables = "SELECT name,sql FROM sqlite_master ORDER BY name";
    assert_eq!(rows(&rust, tables), rows(&node, tables), "{}: 표 · 색인", f.name);
    let counts = "SELECT 'events',CAST(count(*) AS TEXT) FROM events UNION ALL SELECT 'periods',CAST(count(*) AS TEXT) FROM periods \
        UNION ALL SELECT 'items',CAST(count(*) AS TEXT) FROM items UNION ALL SELECT 'entities',CAST(count(*) AS TEXT) FROM entities \
        UNION ALL SELECT 'names',CAST(count(*) AS TEXT) FROM names UNION ALL SELECT 'summaries',CAST(count(*) AS TEXT) FROM summaries \
        UNION ALL SELECT 'sphere_lines',CAST(count(*) AS TEXT) FROM sphere_lines UNION ALL SELECT 'form',CAST(coalesce(sum(form<>0),0) AS TEXT) FROM periods";
    assert_eq!(rows(&rust, counts), rows(&node, counts), "{}: 표마다 수", f.name);
    // 스키마 4(계약 1-1): 배치의 문화권 단위 줄 · form ≠ 0인 띠(판 띠까지)가 그대로 든다 — 두 길이 함께 빠뜨려도 같아 보이지 않게.
    let lines = plan["sphereLines"].as_array().map_or(0, Vec::len);
    let forms = plan["periods"].as_array().into_iter().chain(plan["boards"]["periods"].as_array()).flatten()
        .filter(|p| p["form"].as_i64().unwrap_or(0) != 0).count();
    let got: std::collections::HashMap<String, Option<String>> = rows(&rust, counts).into_iter().collect();
    assert_eq!((got["sphere_lines"].clone(), got["form"].clone()), (Some(lines.to_string()), Some(forms.to_string())), "{}: 문화권 단위 줄 · form", f.name);
    let (mut a, mut b) = (meta(&rust), meta(&node));
    assert_eq!(a.remove("now").as_deref(), Some(ORACLE_NOW), "{}: 지은 날은 준 글 그대로", f.name);
    b.remove("now");
    // 규칙 판(판정 R69-2): 짓기 ②만 적는다 — 가져오기(바깥 배치)는 적지 않는다.
    assert_eq!(a.remove("rules"), Some(archive_engine::patch::rules_mark()), "{}: 짓기는 규칙 판을 적는다", f.name);
    assert_eq!(b.remove("rules"), None, "{}: 가져오기는 규칙 판을 적지 않는다", f.name);
    assert_eq!(a, b, "{}: meta(지은 날 · 규칙 판 말고)", f.name);
    let db = rusqlite::Connection::open(&rust).unwrap();
    assert_eq!(lay::calendar_of(&db).unwrap().as_deref(), Some(&*table), "{}: 넣은 달력 표를 그대로", f.name);
    let pack: i64 = db.query_row("SELECT pack FROM blobs WHERE key=?1", [lay::CALENDAR_BLOB], |r| r.get(0)).unwrap();
    assert_eq!(pack, 0, "{}: 달력 표는 어느 DLC에도 딸리지 않는다", f.name);
    assert_eq!(lay::calendar_of(&rusqlite::Connection::open(&node).unwrap()).unwrap(), None, "{}: 지금 길에는 표가 없다", f.name);
    eprintln!("짓기 ② — 지금 길과 같음: {}", f.name);
}

#[test] fn stage_two_lantern() { let _t = common::clock("stage_two_lantern"); stage_two("lantern") }
#[test] fn stage_two_east_asia_dep() { let _t = common::clock("stage_two_east_asia_dep"); stage_two("east-asia+dep") }
#[test] fn stage_two_east_asia_ktl() { let _t = common::clock("stage_two_east_asia_ktl"); stage_two("east-asia+ktl") }
#[test] fn stage_two_synth_patch() { let _t = common::clock("stage_two_synth_patch"); stage_two("synth+patch") }
#[test] fn stage_two_nest_f4_at_f4() { let _t = common::clock("stage_two_nest_f4_at_f4"); stage_two("nest-f4@f4") }

#[test]
fn a_store_without_the_table_answers_none() {
    let _t = common::clock("a_store_without_the_table_answers_none");
    // 표 없는 저장소(그림 표가 없는 옛 저장소 · Node 길의 가져오기로 지은 것) → None(오류 아님). 깨진 표 → 오류.
    let f = fixtures().into_iter().find(|f| f.name == "synth+patch").expect("synth+patch");
    let path = common::scratch("bd-none");
    import_layout_value(&node_plan(&f), &originals(&f), &path).unwrap();
    let db = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(lay::calendar_of(&db).unwrap(), None);
    db.execute("INSERT INTO blobs(key,pack,mime,bytes) VALUES(?1,0,'application/zlib',x'00ff')", [lay::CALENDAR_BLOB]).unwrap();
    assert!(lay::calendar_of(&db).unwrap_err().to_string().contains("달력 표를 풀지 못했습니다"));
    db.execute_batch("DROP TABLE blobs").unwrap();
    assert_eq!(lay::calendar_of(&db).unwrap(), None);
}

/// 그 자료의 입력을 파일로(`archive-tool build`가 받는 꼴) — (파일들, 폴더).
fn input_files(f: &Fixture, tag: &str) -> (Vec<std::path::PathBuf>, std::path::PathBuf) {
    let dir = std::env::temp_dir().join(format!("archive-correct-{}-bd-{tag}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let files = inputs(f).into_iter().map(|p| {
        let file = dir.join(&p.name);
        std::fs::write(&file, &p.bytes).unwrap();
        file
    }).collect();
    (files, dir)
}

#[test]
fn the_command_needs_the_table_and_a_zone() {
    let _t = common::clock("the_command_needs_the_table_and_a_zone");
    // 판정 R36: 달력 표는 모든 저장소에 — `--calendar`가 없으면 배치(①) 앞에서 쉬운 글로 거절. `--now`의 `Z`(UTC)도 거절(시간대가 지은 날의 지역 날짜를 정한다).
    let fixtures = fixtures();
    let f = fixtures.iter().find(|f| f.name == "synth+patch").expect("synth+patch");
    let (files, dir) = input_files(f, "needs");
    let table = dir.join("calendar.json");
    std::fs::write(&table, &*calendar_slice()).unwrap();
    let target = dir.join("built.db");
    let err = build_files(&target, &files, Some(ORACLE_NOW), None).unwrap_err().to_string();
    assert!(err.contains("달력 표가 없습니다") && err.contains("--calendar="), "{err}");
    let err = build_files_with(&target, &files, Some("2026-10-15T03:00:00Z"), Some(&table), true).unwrap_err().to_string();
    assert!(err.contains("시간대를 적어 주세요") && err.contains("Z(UTC)"), "{err}");
    let err = build_files_with(&target, &[], Some(ORACLE_NOW), Some(&table), true).unwrap_err().to_string();
    assert_eq!(err, "지을 DLC가 없습니다");
    // 판정 R36(고침 2회차): 기본(−3500 ~ 2500년)보다 좁은 표는 거절 — 검사의 잘린 표(years 없음)도. 시험용 선택(`--calendar-narrow`)이면 받는다.
    let err = build_files(&target, &files, Some(ORACLE_NOW), Some(&table)).unwrap_err().to_string();
    assert!(err.contains("기본 범위") && err.contains("--calendar-narrow"), "{err}");
    let narrow = dir.join("narrow.json");
    std::fs::write(&narrow, br#"{"v":1,"years":[-2500,2500],"tables":{}}"#).unwrap();
    let err = build_files(&target, &files, Some(ORACLE_NOW), Some(&narrow)).unwrap_err().to_string();
    assert!(err.contains("기본 범위") && err.contains("-2500"), "{err}");
    assert!(!target.exists(), "거절하면 저장소를 남기지 않는다");
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn a_layout_without_track_prints_is_not_built_as_a_seed() {
    let _t = common::clock("a_layout_without_track_prints_is_not_built_as_a_seed");
    // 고침 2회차(R59 M-6): 트랙 지문을 낼 수 없는 배치(트랙 열쇠가 겹침)는 시드 짓기(②)가 거절한다 — 가져오기 길은 예전처럼 지문 없이 짓는다(첫 apply가 거절).
    use common::plans::{packs_of, plan};
    let mut p = plan(&["a"]);
    let copy = p["tracks"][0].clone();
    p["tracks"].as_array_mut().unwrap().push(copy);
    let target = common::scratch("bd-noprints");
    let err = build_store(&p, &packs_of(&["a"]), &target, ORACLE_NOW, &calendar_slice()).unwrap_err().to_string();
    assert!(err.contains("트랙 지문을 낼 수 없어"), "{err}");
    assert!(!target.exists(), "거절하면 저장소를 남기지 않는다");
}

#[test]
fn a_zone_other_than_seoul_builds_like_node() {
    // 고침 2회차(검토 ①): 서울 밖 시간대로 지은 날 — 2026-12-31T22:00:00-05:00(그곳은 아직 2026년)은 서울(+09:00 — 이미 2027년 1월 1일)과 '올해'가 다르다.
    // Rust 짓기 ①(`build_layout` — 시간대 −300분)이 같은 시각 · 시간대로 돌린 Node 내보내기(`oracle/combo.mjs` · TZ=America/New_York)와 차이 0이고,
    // 같은 순간을 서울로 셈한 배치와는 다르다(진행 중 정권의 끝 · 지역 날짜가 시간대에 달린다).
    let _t = common::clock("a_zone_other_than_seoul_builds_like_node");
    let fixtures = fixtures();
    let f = fixtures.iter().find(|f| f.name == "synth+patch").expect("synth+patch");
    let now = "2026-12-31T22:00:00-05:00";
    let (ms, tz) = iso_time(now).unwrap();
    assert_eq!(tz, -300);
    let (files, dir) = input_files(f, "zone");
    let out = dir.join("node.json");
    let jobs = dir.join("jobs.json");
    std::fs::write(&jobs, serde_json::to_vec(&serde_json::json!([{"packs": files, "out": out}])).unwrap()).unwrap();
    let root = common::node::repo_root();
    let run = std::process::Command::new("node").arg(root.join("prototype").join("scripts").join("oracle").join("combo.mjs"))
        .arg(format!("--jobs={}", jobs.display())).env("TZ", "America/New_York").env("HT_ORACLE_NOW", now).env("HT_ORACLE_TZ_MIN", "-300")
        .env("HT_CALENDAR_CACHE", common::node::calendar_copy()) // 공용 달력 표를 갈지 않게(판정 R64 넘김)
        .current_dir(&root).output().expect("node");
    assert!(run.status.success(), "Node 배치 실패: {}", String::from_utf8_lossy(&run.stderr));
    let want: Value = serde_json::from_slice(&std::fs::read(&out).unwrap()).unwrap();
    let got = build_layout(&inputs(f), ms, tz, Some(calendar_slice())).unwrap();
    common::oracle::assert_same(f, "뉴욕 시간대 짓기 ①", &got, &want);
    let seoul = build_layout(&inputs(f), ms, ORACLE_TZ_MIN, Some(calendar_slice())).unwrap();
    assert!(seoul != got, "같은 순간이라도 서울(이미 2027년)과 뉴욕(아직 2026년)의 배치는 달라야 함");
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn stage_one_matches_node_and_builds_the_same_store() {
    let _t = common::clock("stage_one_matches_node_and_builds_the_same_store");
    // 과제 17 ①: 모듈이 다 오면 ①의 배치가 Node 내보내기와 차이 0(값 · json 글 바이트 — `tests/lay_out.rs`와 같은 견줌)이고, 명령의 몸(`build_files` — ① → ②)으로
    // 지은 저장소가 정답지 배치를 ②로 지은 저장소와 canon(조회 포함) · meta · 달력 표까지 같다. 옮기지 않은 모듈이 있으면 그 이름을 담아 거절하고 저장소를 만들지 않는다.
    let fixtures = fixtures();
    let f = fixtures.iter().find(|f| f.name == "synth+patch").expect("synth+patch");
    let got = build_layout(&inputs(f), ORACLE_NOW_MS, ORACLE_TZ_MIN, Some(calendar_slice()));
    let (files, dir) = input_files(f, "one");
    let table = dir.join("calendar.json");
    std::fs::write(&table, &*calendar_slice()).unwrap();
    let target = dir.join("built.db");
    match MODULES.iter().find(|m| !m.ported) {
        Some(first) => {
            let err = got.err().expect("옮기지 않은 모듈이 있으면 거절해야 합니다").to_string();
            assert!(err.contains(&format!("옮기지 않은 모듈: {}", first.name)), "{err}");
            let err = build_files_with(&target, &files, Some(ORACLE_NOW), Some(&table), true).unwrap_err().to_string();
            assert!(err.contains(&format!("옮기지 않은 모듈: {}", first.name)), "{err}");
            assert!(!target.exists(), "거절하면 저장소를 남기지 않는다");
        }
        None => {
            let plan = got.unwrap_or_else(|e| panic!("모듈이 다 왔는데 거절: {e}"));
            let want = node_plan(f);
            common::oracle::assert_same(f, "짓기 ①", &plan, &want);
            common::oracle::assert_same_bytes(f, "짓기 ①", &plan, &want);
            let counts = build_files_with(&target, &files, Some(ORACLE_NOW), Some(&table), true).unwrap_or_else(|e| panic!("짓기 ① → ②: {e}"));
            assert_eq!(counts["now"], ORACLE_NOW);
            let oracle_store = common::scratch("bd-one-oracle");
            build_store(&want, &originals(f), &oracle_store, ORACLE_NOW, &calendar_slice()).unwrap();
            let opts = CanonOpts { levels: vec![0, 4, 7, 8, 11, 14], max_x: 32, queries: true };
            assert!(canon_store(&target, &opts).unwrap() == canon_store(&oracle_store, &opts).unwrap(), "① → ②가 정답지 배치로 지은 저장소와 canon이 다릅니다");
            assert_eq!(meta(&target), meta(&oracle_store), "meta(지은 날 포함 — 같은 --now)");
            let db = rusqlite::Connection::open(&target).unwrap();
            assert_eq!(lay::calendar_of(&db).unwrap().as_deref(), Some(&*calendar_slice()), "명령이 넣은 달력 표");
        }
    }
    std::fs::remove_dir_all(&dir).unwrap();
}

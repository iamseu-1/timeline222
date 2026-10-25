//! 작은 정답 자료를 Builder로 넣고, 저장소가 돌려주는 값을 전수 계산과 견준다. 빠르더라도 빠진 사건이 있으면 실패다.
mod common;
use archive_engine::builder::{Builder, EventIn, PeriodIn, RowGeo, TrackIn, REP_HEAD};
use archive_engine::levels::{bucket_minutes, bucket_of, lod_of, LEVEL_MAX, PRE_MIN};
use archive_engine::{Store, DAY};
use common::{build, scratch};
use rusqlite::{params, Connection};
use serde_json::json;
use std::collections::BTreeMap;

#[test]
fn 범위_검색_목록은_전수_계산과_같고_저장소는_읽기_전용이다() {
    let path = scratch("range");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    for k in 0..120i64 {
        let lo = (k * 41 - 500) * DAY;
        let hi = lo + 5 * DAY;
        let actual: Vec<i64> = s.range(lo, hi, k % 8, 1, 0, 1800).unwrap().iter().map(|v| v["id"].as_i64().unwrap()).collect();
        let wanted: Vec<i64> = samples.iter().filter(|e| e.lane == k % 8 && e.lo.is_some_and(|v| v <= hi) && e.hi.is_some_and(|v| v >= lo)).map(|e| e.id).collect();
        assert_eq!(actual, wanted, "범위 {k}");
    }
    for query in ["해솔", "솔별", "星河", "해솔별 星河"] {
        let r = s.search(query, 0).unwrap();
        assert_eq!(r["items"].as_array().unwrap().len(), if query == "솔별" { 2 } else { 1 });
        assert_eq!(r["items"][0]["id"], 1);
    }
    assert!(s.search("' OR 1=1 --", 0).unwrap()["items"].as_array().unwrap().is_empty());
    let first = s.call(&json!({"op":"list","lo":-1000*DAY,"hi":2000*DAY,"lane":0,"lanes":8})).unwrap();
    assert_eq!(first["items"].as_array().unwrap().len(), 50);
    assert_eq!(first["has_more"], true);
    let second = s.call(&json!({"op":"list","lo":-1000*DAY,"hi":2000*DAY,"lane":0,"lanes":8,"after":first["next"]})).unwrap();
    assert_ne!(first["items"][49]["id"], second["items"][0]["id"]);
    let one = s.call(&json!({"op":"event","id":9})).unwrap();
    assert_eq!(one["importance"], 3);
    assert_eq!(one["pack"], 2);
    assert!(s.db.execute("DELETE FROM events", []).is_err());
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 요약은_사건을_시작_통에_한_번만_세고_대표는_중요도_순_앞_넷이다() {
    let path = scratch("summary");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    let dated = samples.iter().filter(|e| e.start.is_some()).count() as i64;
    for level in PRE_MIN..=LEVEL_MAX {
        // 전수 계산: (줄, 통, 자료집)마다 (중요도 큰 순, 번호 작은 순).
        let mut wanted: BTreeMap<(i64, i64, i64), Vec<(i64, i64, i64)>> = BTreeMap::new();
        for e in samples.iter().filter(|e| e.start.is_some()) {
            wanted.entry((e.lane, bucket_of(e.start.unwrap(), level), e.pack)).or_default().push((-e.importance, e.id, e.start.unwrap()));
        }
        let mut stmt = s.db.prepare("SELECT lane,bucket,pack,n,reps FROM summaries WHERE level=?1 ORDER BY lane,bucket,pack").unwrap();
        let rows: Vec<(i64, i64, i64, i64, Vec<u8>)> = stmt.query_map([level as i64], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).unwrap().map(|r| r.unwrap()).collect();
        assert_eq!(rows.len(), wanted.len(), "단계 {level}의 요약 칸 수");
        assert_eq!(rows.iter().map(|r| r.3).sum::<i64>(), dated, "단계 {level}의 개수 합 = 날짜 있는 사건 수");
        for (lane, bucket, pack, n, reps) in rows {
            let list = wanted.get_mut(&(lane, bucket, pack)).unwrap_or_else(|| panic!("없어야 할 칸: 단계 {level} 줄 {lane} 통 {bucket}"));
            list.sort();
            assert_eq!(n as usize, list.len());
            // 대표 하나 = 번호 u32 · 중요도 u8 · 채움 u8 · 제목 길이 u16 · 시작 i64 · look u32 · 딱지 길이 u16 · 채움 u16 · 제목 · 딱지.
            // 타일이 성긴 단계에서 사건 표를 다시 찾지 않게 요약이 글자까지 품는다.
            let mut at = 0;
            for want in list.iter().take(4) {
                let slot = &reps[at..];
                let id = u32::from_le_bytes(slot[0..4].try_into().unwrap()) as i64;
                assert_eq!(id, want.1, "대표 번호");
                assert_eq!(slot[4] as i64, -want.0, "대표 중요도");
                assert_eq!(i64::from_le_bytes(slot[8..16].try_into().unwrap()), want.2, "대표 시작");
                assert_eq!(u32::from_le_bytes(slot[16..20].try_into().unwrap()) as i64, id % 3, "대표 look");
                assert_eq!(u32::from_le_bytes(slot[24..28].try_into().unwrap()) as i64, samples[(id - 1) as usize].band, "대표가 든 띠");
                let title_len = u16::from_le_bytes(slot[6..8].try_into().unwrap()) as usize;
                let label_len = u16::from_le_bytes(slot[20..22].try_into().unwrap()) as usize;
                let title = std::str::from_utf8(&slot[REP_HEAD..REP_HEAD + title_len]).unwrap();
                assert_eq!(title, if id == 1 { "해솔별 星河" } else if id == 2 { "해 다른 글 솔별" } else { "가상 사건" }, "대표 제목");
                let label = std::str::from_utf8(&slot[REP_HEAD + title_len..REP_HEAD + title_len + label_len]).unwrap();
                assert_eq!(label, if id % 4 == 0 { format!("{id}년") } else { String::new() }, "대표 딱지");
                at += REP_HEAD + title_len + label_len;
            }
            assert_eq!(at, reps.len(), "대표는 넷까지만");
        }
    }
    let below: i64 = s.db.query_row("SELECT count(*) FROM summaries WHERE level<?1", [PRE_MIN as i64], |r| r.get(0)).unwrap();
    assert_eq!(below, 0, "미리 만드는 요약은 PRE_MIN 단계부터");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 긴_기간_색인에는_45일_넘는_사건만_있고_가늘기_등급이_맞다() {
    let path = scratch("spans");
    let samples = build(&path);
    let s = Store::open(&path).unwrap();
    let actual: Vec<(i64, i64, i64)> = {
        let mut stmt = s.db.prepare("SELECT id,lod_min,lod_max FROM span_bounds ORDER BY id").unwrap();
        let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap().map(|r| r.unwrap()).collect();
        rows
    };
    let wanted: Vec<(i64, i64, i64)> = samples.iter()
        .filter(|e| e.start.is_some() && e.end.unwrap() - e.start.unwrap() >= bucket_minutes(PRE_MIN))
        .map(|e| { let lod = lod_of(e.end.unwrap() - e.start.unwrap()); (e.id, lod, lod) })
        .collect();
    assert!(!wanted.is_empty());
    assert_eq!(actual, wanted);
    let meta = s.info().unwrap();
    assert_eq!(meta["meta"]["schema"], archive_engine::schema::VERSION);
    assert_eq!(meta["meta"]["count"], "513");
    assert_eq!(meta["meta"]["unknown"], "10");
    assert_eq!(meta["meta"]["rows"], "8");
    assert_eq!(meta["meta"]["groups"], "2");
    assert_eq!(meta["meta"]["categories"], "3");
    assert_eq!(meta["meta"]["axis_cells"], "3");
    assert_eq!(meta["meta"]["items"], "3");
    assert_eq!(meta["meta"]["entities"], "2");
    assert_eq!(meta["meta"]["row_labels"], "24");
    assert_eq!(meta["meta"]["seed"], "검사");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 이미_있는_저장소와_옛_스키마는_거절한다() {
    let path = scratch("reject");
    build(&path);
    assert!(Builder::create(&path).is_err(), "이미 있는 저장소는 덮어쓰지 않는다");
    std::fs::remove_file(&path).unwrap();
    // 옛 시제품 판(1 · 2)과 이 엔진이 모르는 앞선 판(5 — 스키마 4 전의 엔진이 4를 거절하듯)은 열지 않는다.
    for old in ["1", "2", "5"] {
        let db = Connection::open(&path).unwrap();
        db.execute_batch("CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);").unwrap();
        db.execute("INSERT INTO meta VALUES('schema',?1)", params![old]).unwrap();
        drop(db);
        let error = Store::open(&path).err().unwrap_or_else(|| panic!("스키마 {old}은 열리지 않아야 한다")).to_string();
        assert!(error.contains("다시 만들어야"), "{error}");
        std::fs::remove_file(&path).unwrap();
    }
}

#[test]
fn 스키마_3의_새_열은_layout_3판으로_돌아온다() {
    let path = scratch("layout3");
    build(&path);
    let s = Store::open(&path).unwrap();
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    let tracks = shape["tracks"].as_array().unwrap();
    assert_eq!(tracks.len(), 2);
    assert_eq!((tracks[0]["color"].as_i64(), tracks[0]["dynasty"].as_i64(), tracks[0]["rail_levels"].as_i64()), (Some(0xc8b193), Some(1), Some(2)));
    assert_eq!((tracks[1]["color"].as_i64(), tracks[1]["dynasty"].as_i64(), tracks[1]["rail_levels"].as_i64()), (Some(0xc8b194), Some(0), Some(3)));
    assert_eq!(tracks[0]["groups"], json!([{"depth":0,"first":0,"count":4,"name":"윗물 겨레","color":0xbcd8c1,"kind":0}]));
    assert_eq!(tracks[1]["groups"][0]["first"], 4, "묶음의 첫 줄은 전체 줄 번호");
    // 문화권(리메이크 조각 ②)을 적지 않은 트랙은 빈 글자, 문화권 목록이 없으면 빈 목록.
    assert_eq!((tracks[0]["sphere"].as_str(), tracks[1]["sphere"].as_str(), &shape["spheres"]), (Some(""), Some(""), &json!([])));
    // 2판의 굳은 자리 열은 그대로 오고, 3판의 값이 곁에 붙는다.
    let rows = tracks[0]["rows"].as_array().unwrap();
    // 한 벌 P3-18의 이름 붙은 칸(줄 깃발 · 그릇 여백의 가름)도 곁에 붙는다 — 값 0의 줄은 모두 0 · 막대 단 −1 · 사건 1.
    assert_eq!(rows[0], json!({"id":0,"height":126,"band_top":19,"band_h":107,"dyn_top":-1,"lead_top":23,"cab_top":46,"text_top":66,"text_lines":2,"rail_top":108,"organ_top":-1,
        "kind":0,"group_start":1,"scope_pad":0,"phase":0,"rank":0,"cats":[],"fig":0,"fig_wide":0,"dep":0,"zones":0,"hem":0,"variant":0,
        "fig_wide_levels":0,"rail":-1,"organ":0,"power":0,"real":0,"hang":0,"raised":0,"contained":0,"cell_rows":0,"dynasty":0,"leader":0,"cabinet":0,"events":1,
        "scope_head":0,"scope_foot":0,"scope_hung":0}));
    assert_eq!(rows[1]["kind"], 1);
    assert_eq!(rows[1]["cats"], json!([0, 2]));
    assert_eq!((rows[1]["phase"].as_i64(), rows[1]["rank"].as_i64(), rows[1]["fig"].as_i64(), rows[1]["fig_wide"].as_i64(), rows[1]["dep"].as_i64()), (Some(1), Some(1), Some(2), Some(3), Some(25)));
    assert_eq!((rows[1]["zones"].as_i64(), rows[1]["hem"].as_i64(), rows[1]["scope_pad"].as_i64()), (Some(1), Some(1), Some(6)));
    assert_eq!(shape["categories"], json!([{"id":1,"key":"govern","name":"다스림","color":0x8f7fb0},
        {"id":2,"key":"build","name":"지음","color":0x6f9a86},{"id":3,"key":"lore","name":"이야기","color":0x9a6f8a}]));
    // 날짜 칸은 시작 순. 공통 줄은 트랙 0.
    let axis = shape["axis"].as_array().unwrap();
    assert_eq!(axis.len(), 3);
    assert_eq!(axis[0], json!([2, 1, 0, -500 * DAY, 200 * DAY, "첫길 연호", 0xc8b193, 1, 7, 0]));
    assert!(axis.iter().any(|a| a[0] == 1 && a[1] == 0), "공통 줄의 시대 구분은 트랙 0");
    assert_eq!(shape["epochs"][0]["name"], "첫 시대");
    // 문화권 단위 줄(스키마 4 · 계약 1-1 `sphere_lines`) — 이 자료는 표가 비어 빈 목록이다. 표가 없는 옛 저장소(판 '3')도 빈 목록(`spheres`와 같은 꼴).
    assert_eq!(shape["sphereLines"], json!([]), "빈 표");
    drop(s);
    {
        let db = Connection::open(&path).unwrap();
        db.execute_batch("DROP TABLE sphere_lines; UPDATE meta SET value='3' WHERE key='schema';").unwrap();
    }
    let old = Store::open(&path).unwrap();
    assert!(!old.has_sphere_lines);
    assert_eq!(old.call(&json!({"op":"layout"})).unwrap()["sphereLines"], json!([]), "표가 없는 옛 저장소");
    drop(old);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 항목_기록은_넣은_글자_그대로_돌아오고_없는_이름은_거절한다() {
    let path = scratch("entity");
    build(&path);
    let s = Store::open(&path).unwrap();
    let one = s.call(&json!({"op":"entity","uid":"band-0-0"})).unwrap();
    assert_eq!(one["kind"], "period");
    assert_eq!(one["json"], r#"{"uid":"band-0-0","name":"별여울 0줄 1번 띠"}"#);
    assert!(s.call(&json!({"op":"entity","uid":"없는 이름"})).is_err());
    assert!(s.call(&json!({"op":"entity"})).is_err());
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn 줄_이름_후보는_줄마다_시작_순으로_온다() {
    let path = scratch("row-labels");
    build(&path);
    let s = Store::open(&path).unwrap();
    let answer = s.call(&json!({"op":"row_labels","rows":[0,5,99],"at":0})).unwrap();
    let labels = answer["labels"].as_array().unwrap();
    assert_eq!(labels.len(), 3);
    assert_eq!(labels[0]["row"], 0);
    let items = labels[0]["items"].as_array().unwrap();
    assert_eq!(items.len(), 3, "줄 0의 띠 셋");
    assert_eq!(items.iter().map(|v| v["period"].as_str().unwrap()).collect::<Vec<_>>(), vec!["band-0-0", "band-0-1", "band-0-2"]);
    assert_eq!(items[0]["name"], "별여울 0줄 1번 띠", "원소의 JSON을 통째로 보존한다");
    assert_eq!(labels[1]["row"], 5);
    assert_eq!(labels[1]["items"].as_array().unwrap().len(), 3);
    assert_eq!(labels[2]["items"], json!([]), "없는 줄은 빈 목록");
    assert!(s.call(&json!({"op":"row_labels"})).is_err());
    drop(s);
    std::fs::remove_file(path).unwrap();
}

/// rows_near 전용의 작은 자료: 줄마다 한 가지만 둔다 — 띠만 · 사건만 · 긴 기간만 · 빈 줄 · 미정 끝의 띠 · 끈 자료집.
fn near_store(path: &std::path::Path) {
    let geo = RowGeo { height: 40, band_top: 0, band_h: 40, dyn_top: -1, lead_top: -1, cab_top: -1, text_top: 0, text_lines: 1, rail_top: -1, organ_top: -1 };
    let mut b = Builder::create(path).unwrap();
    let packs = [b.pack("켠 기록집", None).unwrap(), b.pack("끈 기록집", None).unwrap()];
    let track = b.track_full(&TrackIn::plain(packs[0], "첫 트랙")).unwrap();
    for _ in 0..6 {
        b.row(track, &geo).unwrap();
    }
    let other = b.track_full(&TrackIn::plain(packs[1], "끈 트랙")).unwrap();
    b.row(other, &geo).unwrap();
    // 0: 띠만(기원전 −400~−300일)
    b.period(packs[0], 0, -400 * DAY, -300 * DAY, 0, 0xa0bcc5, "별여울 띠").unwrap();
    // 1: 점 사건만
    b.event(&EventIn { pack: packs[0], lane: 1, start: Some(-350 * DAY), end: Some(-350 * DAY), importance: 1, title: "별여울 기록", ..Default::default() }).unwrap();
    // 2: 긴 기간 사건만(−500 ~ 500일)
    b.event(&EventIn { pack: packs[0], lane: 2, start: Some(-500 * DAY), end: Some(500 * DAY), importance: 2, title: "긴 공사", ..Default::default() }).unwrap();
    // 3: 빈 줄
    // 4: 끝 미정의 띠(−900~−800일) — fade만큼 넓히면 범위에 닿는다
    b.period_full(&PeriodIn { pack: packs[0], row: 4, start: -900 * DAY, end: -800 * DAY, fuzzy: 2, color: 0xa0bcc5, name: "옅은 끝", look: 0, tag: "", sub: 0, uid: "", variant: 0, form: 0 }).unwrap();
    // 5: 켜지 않은 자료집의 사건
    b.event(&EventIn { pack: packs[1], lane: 5, start: Some(-350 * DAY), end: Some(-350 * DAY), importance: 1, title: "끈 기록", ..Default::default() }).unwrap();
    b.finalize(&[]).unwrap();
}

#[test]
fn rows_near는_띠_사건_긴_기간을_모으고_끈_자료집은_뺀다() {
    let path = scratch("rows-near");
    near_store(&path);
    let s = Store::open(&path).unwrap();
    // 기원전(음수 분)의 좁은 범위: 0(띠) · 1(점) · 2(긴 기간). 빈 줄 3과 끈 자료집의 5는 없다.
    assert_eq!(s.rows_near(-360 * DAY, -340 * DAY, 0, &[1], None, None).unwrap(), vec![0, 1, 2]);
    // fade를 넉넉히 주면 끝 미정의 띠(줄 4)까지 닿는다.
    assert_eq!(s.rows_near(-360 * DAY, -340 * DAY, 500 * DAY, &[1], None, None).unwrap(), vec![0, 1, 2, 4]);
    // 띠만 있는 곳
    assert_eq!(s.rows_near(-390 * DAY, -380 * DAY, 0, &[1], None, None).unwrap(), vec![0, 2]);
    // 긴 기간만 닿는 곳
    assert_eq!(s.rows_near(400 * DAY, 450 * DAY, 0, &[1], None, None).unwrap(), vec![2]);
    // 아무것도 없는 곳
    assert!(s.rows_near(5_000 * DAY, 5_100 * DAY, 0, &[1], None, None).unwrap().is_empty());
    // 끈 자료집만 켜면 그 줄만
    assert_eq!(s.rows_near(-360 * DAY, -340 * DAY, 0, &[2], None, None).unwrap(), vec![5]);
    assert!(s.rows_near(-360 * DAY, -340 * DAY, 0, &[], None, None).unwrap().is_empty(), "켠 자료집이 없으면 빈 답");
    // 넓은 범위는 미리 만든 요약을, 좁은 범위는 덮는 색인을 쓴다 — 답은 같아야 한다.
    let wide = s.rows_near(-3_000 * DAY, 3_000 * DAY, 0, &[1, 2], None, None).unwrap();
    assert_eq!(wide, vec![0, 1, 2, 4, 5]);
    let answer = s.call(&json!({"op":"rows_near","near":[-360*DAY,-340*DAY],"far":[400*DAY,450*DAY],"fade":0,"packs":[1]})).unwrap();
    assert_eq!(answer, json!({"near":[0,1,2],"far":[2]}));
    assert_eq!(s.call(&json!({"op":"rows_near","near":[-360*DAY,-340*DAY],"packs":[1]})).unwrap(), json!({"near":[0,1,2],"far":[]}));
    assert!(s.call(&json!({"op":"rows_near","near":[1],"packs":[1]})).is_err());
    assert!(s.rows_near(10, 0, 0, &[1], None, None).is_err(), "뒤집힌 범위");
    drop(s);
    std::fs::remove_file(path).unwrap();
}

/// 검사 파일이 임시 폴더에 쓰는 이름(임시 폴더에 format!으로 붙이는 머리)이 모두 `archive-<갈래>-` 꼴이고 갈래가 `common::SCRATCH_KINDS`에 있다 —
/// 끝난 검사가 남긴 것을 `sweep_stale`이 치우려면 그래야 한다(판정 R58 ⑤ Minor: `archive-doclist-` · `ht-variants-`가 빠져 쌓였다).
#[test]
fn scratch_kinds_cover_every_test() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    let mut files: Vec<std::path::PathBuf> = std::fs::read_dir(&dir).unwrap().flatten().map(|e| e.path()).collect();
    files.extend(std::fs::read_dir(dir.join("common")).unwrap().flatten().map(|e| e.path()));
    let mut seen = 0;
    for file in files.iter().filter(|p| p.extension().is_some_and(|e| e == "rs")) {
        let text = std::fs::read_to_string(file).unwrap();
        const HEAD: &str = "temp_dir().join(format!(\"";
        for (at, _) in text.match_indices(HEAD) {
            let rest = &text[at + HEAD.len()..];
            let prefix = &rest[..rest.find('{').unwrap_or(0)];
            let kind = prefix.strip_prefix("archive-").and_then(|k| k.strip_suffix('-'));
            assert!(kind.is_some_and(|k| common::SCRATCH_KINDS.contains(&k)),
                "{}: 임시 이름 머리 '{prefix}'가 archive-<SCRATCH_KINDS의 갈래>-<pid>… 꼴이 아닙니다(끝난 검사의 것이 치워지지 않음)", file.display());
            seen += 1;
        }
    }
    assert!(seen >= 20, "임시 이름을 너무 적게 찾았습니다({seen}) — 찾는 꼴이 낡았는지 보세요");
}

//! 과제 8-틀 — 모듈 `calendar`(15/21)만 Node와 견준다(`common::modcheck` — `pre-docs`를 심고 · 달력 표는 `seam_opts`의 잘린 표에서). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 그리고 표가 없으면 거절하는가(계획 정한 것 #7 — Rust는 표를 넓힐 수 없다 · 과제 12b · 갈래 C), 표가 자료 범위를 다 덮지 못하면 거절하지 않고 겹치는 구간만 싣는가
//! (판정 R61 · 과제 calclip — Node와 다른 점은 알려진 차이 `common::oracle::cal_clip_known`).
mod common;
use archive_engine::lay;
use serde_json::{json, Value};

#[test]
fn calendar_contribute_matches_node() { common::modcheck::check_contribute("calendar"); }

/// 달력 표가 없으면 "달력 표 없음"으로 거절한다(조용히 다른 표를 내지 않음). 표가 자료의 해 범위(± 100년)와 **겹치지 않으면** 거절하지 않고 그 달력의 `cal:` 기록을 싣지 않는다
/// (판정 R61 — 처음에는 "달력 표 범위 밖"으로 거절했다). 자료는 보조 달력 날짜가 없는 `synth`(정규화 · 모델은 표 없이도 지어진다 — 표는 calendar 모듈에서만 쓰인다).
#[test]
fn calendar_refuses_missing_table_and_skips_a_table_outside_the_data() {
    let f = common::oracle::fixtures().into_iter().find(|f| f.name == "synth").expect("정답지 자료 synth");
    let seed = common::oracle::oracle(&f, "pre-docs.json");
    let seed_shared = common::oracle::oracle(&f, "pre-docs.shared.json");
    let mut o = common::oracle::opts(Some("calendar"));
    let e = lay::export_one(&common::oracle::inputs(&f), &o, "calendar", Some(seed.clone()), Some(&seed_shared)).expect_err("표 없이 지어지면 안 된다").to_string();
    assert!(e.contains("달력 표 없음"), "표 없음의 거절 글: {e}");
    // 달력 다섯 모두 한 달(서기 1858년 무렵)만 — synth의 범위(−50 ~ 1050년 둘레)와 겹치지 않는다
    let one = |intl: &str| json!({ "intl": intl, "start": 2400000, "year0": 1858, "months": "C1" });
    let table = json!({ "v": 1, "icu": "", "years": [1858, 1858], "tables": {
        "dangi": one("dangi"), "chinese": one("chinese"), "islamic": one("islamic-civil"), "umalqura": one("islamic-umalqura"), "persian": one("persian") } });
    o.calendar = Some(std::rc::Rc::new(serde_json::to_vec(&table).unwrap()));
    let (got, _) = lay::export_one(&common::oracle::inputs(&f), &o, "calendar", Some(seed.clone()), Some(&seed_shared))
        .unwrap_or_else(|e| panic!("겹치지 않는 표로 거절하면 안 된다: {e}"));
    let entities = got["entities"].as_array().expect("entities");
    assert_eq!(entities.iter().filter(|e| e["kind"] == "cal").count(), 0, "겹치는 구간이 없으면 cal: 기록을 싣지 않는다");
    assert_eq!(entities.len(), seed["entities"].as_array().expect("심은 entities").len(), "다른 기록은 그대로");
}

/// 검사의 잘린 달력 표(`calendar-slice.json`)에서 달력마다 달 [a, b)만 남긴 표 묶음 — `pick(각 달의 첫날)`이 (a, b)를 정한다(표 파일을 다시 뽑아도 '자료 범위를 덮지 못하는' 꼴을 지으려고
/// 표를 이렇게 다시 자른다). 남긴 표의 첫날 · 해는 앞 달들을 걸어 센다(달 1 · 윤달 아님마다 한 살 · 음력은 0년을 건너뜀).
fn kept_tables(pick: &dyn Fn(&[f64]) -> (usize, usize)) -> serde_json::Map<String, Value> {
    let slice: Value = serde_json::from_slice(&common::oracle::calendar_slice()).expect("calendar-slice.json");
    let mut tables = serde_json::Map::new();
    for (id, t) in slice["tables"].as_object().expect("tables") {
        let lunar = lay::cal::cal_of(id).expect("달력 id").lunar;
        let m = t["months"].as_str().expect("months");
        let n = m.len() / 2;
        let len_at = |k: usize| f64::from(m.as_bytes()[k * 2 + 1]) - 48.0 + 29.0;
        let mut starts = Vec::with_capacity(n);
        let mut at = t["start"].as_f64().expect("start");
        for k in 0..n { starts.push(at); at += len_at(k); }
        let (a, b) = pick(&starts);
        assert!(a < b && b <= n, "{id}: 남길 달 [{a}, {b})가 표(달 {n}개) 안이 아닙니다");
        let mut year = t["year0"].as_f64().expect("year0");
        for k in 1..=a { if m.as_bytes()[k * 2] == b'C' { year = if lunar && year == -1.0 { 1.0 } else { year + 1.0 }; } } // 달 1 · 윤달 아님마다 한 살(음력은 0년을 건너뜀)
        tables.insert(id.clone(), json!({ "intl": t["intl"], "start": starts[a], "year0": year, "months": &m[a * 2..b * 2] }));
    }
    tables
}

/// 판정 R61(Critical C1): 보조 달력을 쓰지 않는 DLC(합성 자료 `synth-calclip` — 양력만 · 기원전 8000년 띠 · 끝 9999년)의 자료 해 ± 100년이 달력 표 밖으로 나가도
/// 배치를 거절하지 않고, 달력 다섯 모두 **표와 겹치는 구간만** 싣는다(`note`에 '표 밖 생략') — 그 표는 Node(ICU로 다시 뜸) 표의 이어진 한 토막이고 나머지는 Node와 같다.
/// 표는 검사의 잘린 표(`calendar-slice.json`)를 다시 가운데만 남겨(달 ¼ ~ ½ — 표 파일을 다시 뽑아도 '표가 자료 범위를 덮지 못하는' 꼴이 남게) 넘긴다.
#[test]
fn calendar_clips_to_the_table_instead_of_refusing() {
    let f = common::oracle::fixtures().into_iter().find(|f| f.name == "synth-calclip").expect("정답지 자료 synth-calclip");
    assert!(f.cal_clip, "synth-calclip은 list.json에서 calClip 표지가 붙어 있어야 한다(판정 R64-2)");
    let seed = common::oracle::oracle(&f, "pre-docs.json");
    let seed_shared = common::oracle::oracle(&f, "pre-docs.shared.json");
    let want = common::oracle::oracle(&f, "pre-calendar.json");
    let tables = kept_tables(&|starts| (starts.len() / 4, starts.len() / 2));
    let mut o = common::oracle::seam_opts(Some("calendar"));
    o.calendar = Some(std::rc::Rc::new(serde_json::to_vec(&json!({ "v": 1, "icu": "", "tables": tables })).unwrap()));
    let (got, _) = lay::export_one(&common::oracle::inputs(&f), &o, "calendar", Some(seed), Some(&seed_shared))
        .unwrap_or_else(|e| panic!("표 밖 자료 해로 배치를 거절하면 안 된다(판정 R61): {e}"));
    let (_, clipped) = common::oracle::cal_clip_known(&f, &got, &want);
    assert_eq!(clipped, 5, "달력 다섯 모두 표와 겹치는 구간만 실어야 한다");
    // 자료 범위가 표의 양쪽 밖까지 가므로 겹치는 구간 = 남긴 표 통째 — 실은 표가 넘긴 표와 같다(첫날 · 해 · 달 글).
    for e in got["entities"].as_array().expect("entities").iter().filter(|e| e["kind"] == "cal") {
        let body: Value = serde_json::from_str(e["json"].as_str().expect("json 글")).expect("json");
        let t = &tables[body["cal"].as_str().expect("cal")];
        let same_num = |a: &Value, b: &Value| a.as_f64().is_some() && a.as_f64() == b.as_f64();
        assert!(same_num(&body["from"], &t["start"]) && same_num(&body["year0"], &t["year0"]) && body["months"] == t["months"], "{}: 겹치는 구간이 넘긴 표와 다릅니다", e["uid"]);
    }
    common::oracle::assert_same(&f, "pre-calendar(가운데만 남긴 표)", &got, &want);
    common::oracle::assert_same_bytes(&f, "pre-calendar(가운데만 남긴 표)", &got, &want);
}

/// 판정 R64 · M1: **한쪽만** 잘리는 꼴 — 표의 앞 달들을 서기 500년 무렵부터로 줄이면(뒤는 2127년까지 그대로) 앞 구간(자료 해 −50년 ~ 서기 500년 앞)만 표 밖이다.
/// 그때 실은 표는 첫날 = 남은 표의 첫날 · 해 = 남은 표의 `year0` · 끝 = Node의 끝(`to`) · 달 글 = 남은 표의 앞토막이고, `note`는 '표 밖 생략 — 자료 범위 …'로 시작한다
/// (`calendar.rs`의 `clipped = lo > from_j || hi < to_j`가 `&&`이면 앞만 잘린 이 꼴을 놓친다). 자료는 표지 없는 `synth`(−50 ~ 1050년 둘레)라 알려진 차이의 확인은 `cal_clip_swap`을 직접 부른다.
#[test]
fn calendar_clips_only_the_front_when_the_table_still_reaches_the_data_end() {
    let f = common::oracle::fixtures().into_iter().find(|f| f.name == "synth").expect("정답지 자료 synth");
    assert!(!f.cal_clip, "synth는 달력 잘림 표지가 없는 자료여야 한다");
    let seed = common::oracle::oracle(&f, "pre-docs.json");
    let seed_shared = common::oracle::oracle(&f, "pre-docs.shared.json");
    let want = common::oracle::oracle(&f, "pre-calendar.json");
    let cut = lay::cal::jdn_civil(500.0, 1.0, 1.0);
    let tables = kept_tables(&|starts| (starts.iter().position(|&s| s >= cut).expect("표가 서기 500년 뒤까지 간다"), starts.len()));
    let mut o = common::oracle::seam_opts(Some("calendar"));
    o.calendar = Some(std::rc::Rc::new(serde_json::to_vec(&json!({ "v": 1, "icu": "", "tables": tables })).unwrap()));
    let (got, _) = lay::export_one(&common::oracle::inputs(&f), &o, "calendar", Some(seed), Some(&seed_shared))
        .unwrap_or_else(|e| panic!("앞만 잘린 표로 배치를 거절하면 안 된다: {e}"));
    let body = |e: &Value| -> Value { serde_json::from_str(e["json"].as_str().expect("json 글")).expect("json") };
    let num = |v: &Value| v.as_f64().expect("수");
    let nodes = want["entities"].as_array().expect("Node entities");
    let mut seen = 0;
    for e in got["entities"].as_array().expect("entities").iter().filter(|e| e["kind"] == "cal") {
        let g = body(e);
        let table = &tables[g["cal"].as_str().expect("cal")];
        let w = body(nodes.iter().find(|n| n["uid"] == e["uid"]).expect("Node의 같은 기록"));
        assert!(num(&g["from"]) == num(&table["start"]) && num(&g["year0"]) == num(&table["year0"]), "{}: 첫날 · 해는 남은 표의 것이어야 한다(Rust {} · {} / 표 {} · {})", e["uid"], g["from"], g["year0"], table["start"], table["year0"]);
        assert!(num(&g["to"]) == num(&w["to"]), "{}: 뒤는 잘리지 않았으니 끝은 Node와 같아야 한다(Rust {} · Node {})", e["uid"], g["to"], w["to"]);
        assert!(num(&w["from"]) < num(&g["from"]), "{}: Node 표는 더 앞에서 시작한다(앞이 잘렸다)", e["uid"]);
        let (gm, tm) = (g["months"].as_str().expect("months"), table["months"].as_str().expect("months"));
        assert!(tm.starts_with(gm) && w["months"].as_str().expect("months").ends_with(gm), "{}: 달 글은 남은 표의 앞토막이자 Node 표의 끝토막이어야 한다", e["uid"]);
        assert!(g["note"].as_str().is_some_and(|s| s.starts_with("표 밖 생략 — 자료 범위 ")), "{}: 앞만 잘려도 note가 '표 밖 생략'으로 시작해야 한다 — {}", e["uid"], g["note"]);
        seen += 1;
    }
    assert_eq!(seen, 5, "달력 다섯");
    let (swapped, clipped) = common::oracle::cal_clip_swap(&f.name, &got, &want);
    assert_eq!(clipped, 5, "달력 다섯 모두 알려진 차이(Node 표의 이어진 한 토막)로 확인돼야 한다");
    let swapped = swapped.expect("바꾼 사본");
    common::oracle::assert_same(&f, "pre-calendar(앞만 잘린 표)", &swapped, &want);
    common::oracle::assert_same_bytes(&f, "pre-calendar(앞만 잘린 표)", &swapped, &want);
}

/// 판정 R64-2(검토 M4): 달력 잘림 표지는 이름 목록이 아니라 `list.json`에서 읽는다 — 표지가 붙은 자료만 알려진 차이를 받고, `<이름>@f4`는 `@f4`를 뗀 이름을 따른다.
#[test]
fn the_clip_mark_comes_from_the_list_and_is_not_given_to_other_fixtures() {
    let all = common::oracle::fixtures();
    let marked: Vec<&str> = all.iter().filter(|f| f.cal_clip).map(|f| f.name.as_str()).collect();
    assert_eq!(marked, ["synth-calclip"], "list.json의 calClip 표지가 붙은 자료");
    for (name, want) in [("synth-calclip", true), ("synth-calclip@f4", true), ("synth", false), ("synth@f4", false), ("synth-calclip2", false), ("x-synth-calclip", false)] {
        assert_eq!(common::oracle::is_cal_clip(&["synth-calclip"], name), want, "{name}");
    }
    assert!(!common::oracle::is_cal_clip(&[], "synth-calclip"), "표지가 없으면 이름이 같아도 알려진 차이가 아니다");
    // 표지 없는 자료는 `cal:` 기록의 json이 달라도 알려진 차이로 덮지 않는다(그 차이는 assert_same이 잡는다)
    let rec = |text: &str| json!({ "entities": [{ "uid": "cal:dangi", "kind": "cal", "json": text, "pack": 0 }] });
    let plain = all.iter().find(|f| !f.cal_clip).expect("표지 없는 자료");
    assert_eq!(common::oracle::cal_clip_known(plain, &rec("{\"a\":1}"), &rec("{\"a\":2}")), (None, 0));
}

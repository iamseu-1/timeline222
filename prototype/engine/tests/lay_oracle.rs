//! P3 정답지 도구(tests/common/oracle.rs)가 진짜 정답지 파일과 맞물려 도는지 보는 검사: 목록 · 시각 · 시간대 · 입력 바이트 · 견주기.
//! 정답지(`node prototype/scripts/layout-oracle.mjs`)를 아직 뽑지 않았으면 '먼저 뽑으세요'로 실패한다(판정 R58 ⑤ Minor — 예전엔 알리고 지나갔다).
mod common;
use common::oracle::{assert_same, fixtures, inputs, only_keys, opts, oracle, results_dir, ORACLE_NOW, ORACLE_NOW_MS, ORACLE_TZ_MIN};
use serde_json::json;

/// 정답지 폴더가 있어야 한다 — 없으면 멈춘다(조용히 건너뛰지 않음).
fn extracted() -> bool {
    assert!(results_dir().is_dir(), "정답지 폴더 {}가 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs", results_dir().display());
    true
}

#[test]
fn fixed_instant_matches_the_oracle_constants() {
    // 2026-10-15T12:00:00+09:00 = 2026-10-15T03:00:00Z. 1970-01-01부터 20,741일 + 3시간.
    assert_eq!(ORACLE_NOW, "2026-10-15T12:00:00+09:00");
    assert_eq!(ORACLE_NOW_MS, (20_741.0 * 24.0 + 3.0) * 3_600_000.0);
    let o = opts(Some("docs"));
    assert_eq!((o.now_ms, o.tz_min, o.upto.as_deref()), (ORACLE_NOW_MS, ORACLE_TZ_MIN, Some("docs")));
}

#[test]
fn fixtures_load_with_their_inputs_and_oracle_headers() {
    let all = fixtures();
    assert!(all.iter().any(|f| f.name == "lantern") && all.iter().any(|f| f.name == "nest-f4"), "기본 자료가 목록에 없습니다");
    for f in &all {
        let packs = inputs(f);
        assert!(!packs.is_empty() && packs.iter().all(|p| !p.bytes.is_empty()), "{}: 입력이 비었습니다", f.name);
        if !extracted() { continue; }
        // oracle()이 머리의 시각 · 시간대를 확인한다. 팩마다 norm-<i>.json이 있다.
        for i in 0..packs.len() { assert!(oracle(f, &format!("norm-{i}.json")).is_object(), "{}: norm-{i}", f.name); }
        let rows = oracle(f, "rows.json");
        assert!(rows["tracks"].as_array().is_some_and(|t| !t.is_empty()) && rows["model"].is_object(), "{}: rows.json의 짜임", f.name);
        assert!(oracle(f, "upto-lens.json")["tracks"][0]["rows"].is_array(), "{}: upto-lens.json의 짜임", f.name);
    }
}

#[test]
fn assert_same_accepts_the_oracle_and_reports_a_changed_copy() {
    if !extracted() { return; }
    let f = fixtures().into_iter().find(|f| f.name == "lantern").expect("lantern");
    let want = oracle(&f, "upto-lens.json");
    assert_same(&f, "자기 자신", &want.clone(), &want);
    let mut bent = want.clone();
    bent["tracks"][0]["rows"][0] = json!({"바뀜": true});
    let caught = std::panic::catch_unwind(|| assert_same(&f, "바뀐 사본", &bent, &want));
    let message = *caught.expect_err("바뀐 사본을 못 잡았습니다").downcast::<String>().expect("메시지");
    assert!(message.contains("tracks.0.rows.0") && message.contains("lantern"), "{message}");
    // 거르개: 빈 목록은 전부 · 열쇠를 주면 그 열쇠만(머리 `$oracle`도 빠진다).
    assert_eq!(only_keys(want.clone(), &[]), want);
    let kept = only_keys(want.clone(), &["name", "packs"]);
    assert_eq!(kept.as_object().unwrap().keys().cloned().collect::<Vec<_>>(), vec!["name", "packs"]);
}

#[test]
fn lantern_f4_is_a_rust_fixture_with_its_own_oracle() {
    // 판정 R9 · R16: lantern@f4는 HT.F4.down의 종속 관계(P2 — 국가 + 관계)와 대범위 구성원(P4 — 객체 id)을 지닌 형식 4 자료라 Rust 검사 자료에 든다.
    // 견본 2.0.1부터는 원본 lantern과 같은 배치(f4-same-check ①=②)라 known을 걷었다. `known`은 f4-same-check 전용 표시('원본과 다르다')일 뿐 —
    // Rust는 known 자료도 건너뛰지 않고 제 정답지(results/oracle/<그 이름>/)로 돌린다(fixtures()).
    let all = fixtures();
    let f = all.iter().find(|f| f.name == "lantern@f4").expect("lantern@f4가 목록에 없습니다 — 형식 4 내림(HT.F4.down)을 지키는 자료입니다");
    let packs = inputs(f);
    assert!(packs.len() == 1 && packs[0].name == "sample-lantern.htpack" && !packs[0].bytes.is_empty(), "lantern@f4의 입력은 형식 4 파일 하나여야 합니다");
    if !extracted() { return; }
    // 제 정답지: 머리의 자료 이름 · 원본 이름이 형식 4 파일의 것이다(원본 lantern의 정답지 — samples/sample-lantern.json — 를 읽지 않는다).
    let norm = oracle(f, "norm-0.json");
    assert_eq!(norm["$oracle"]["fixture"], "lantern@f4");
    assert_eq!(norm["$oracle"]["sources"][0]["name"], "sample-lantern.htpack", "lantern@f4가 원본 lantern의 정답지를 읽고 있습니다");
    // R9의 뜻이 남았는가: 내린 팩에 상대가 있는 종속 관계(partOf의 relation)와 대범위 구성원이 있다.
    const DEPENDENT: [&str; 10] = ["tributary", "dominion", "vassal", "protectorate", "satellite", "puppet", "mandate", "colony", "occupied", "frontier"];
    let rows_of = |v: &serde_json::Value| -> Vec<serde_json::Value> { v.as_array().cloned().unwrap_or_else(|| if v.is_null() { vec![] } else { vec![v.clone()] }) };
    let dependent = norm["periods"].as_array().into_iter().flatten()
        .flat_map(|p| rows_of(&p["partOf"]))
        .filter(|x| x["relation"].as_str().is_some_and(|r| DEPENDENT.contains(&r)))
        .count();
    let members: usize = norm["scopes"].as_array().into_iter().flatten().map(|s| rows_of(&s["members"]).len()).sum();
    assert!(dependent > 0 && members > 0, "lantern@f4에 종속 관계({dependent}) · 대범위 구성원({members})이 없습니다 — HT.F4.down의 그 풀이를 지킬 자료가 사라졌습니다(판정 R9)");
    assert_eq!(oracle(f, "upto-lens.json")["$oracle"]["fixture"], "lantern@f4");
    assert!(oracle(f, "rows.json")["model"].is_object(), "lantern@f4의 rows 정답지");
    // 파일이 저장소에 없는 선택 자료(east-asia+ktl@f4)는 알려진 차이와 상관없이 '없어서 건너뜀' — fixtures()가 멈추지 않고 돌아왔다는 것이 곧 그 확인이다.
}

#[test]
fn oracle_rejects_inputs_that_changed_since_extraction() {
    // 머리 `sources`(입력의 이름 · SHA-256 앞 12자)가 지금 입력과 다르면 정답지를 믿을 수 없다 — 시험 DLC를 고치고 다시 뽑지 않은 경우를 흉내 낸다.
    if !extracted() { return; }
    let mut f = fixtures().into_iter().find(|f| f.name == "lantern").expect("lantern");
    assert_eq!(common::oracle::expected_sources(&f).len(), 1);
    let _ = oracle(&f, "norm-0.json"); // 그대로면 통과
    let other = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("fixtures").join("oracle").join("nest-scene.f4.json");
    f.oracle_base = common::oracle::OracleBase::File(other); // 다른 파일(이름 · 지문이 다름)
    let caught = std::panic::catch_unwind(|| oracle(&f, "norm-0.json"));
    let message = *caught.expect_err("바뀐 입력을 못 잡았습니다").downcast::<String>().expect("메시지");
    assert!(message.contains("원본 지문"), "{message}");
}

#[test]
fn oracle_rejects_heads_from_other_web_code_or_icu() {
    // 판정 R58 ⑤-4: 정답지는 git 밖이라 웹 코드 · 내보내기 모듈을 고친 뒤 다시 뽑지 않으면 낡은 정답지로도 초록이었다 — 머리의 `rules`(원본 지문) ·
    // `icu`(뽑은 Node의 ICU)가 지금 값(`js_rules` · 잘린 달력 표의 icu)과 다르거나 없으면 멈춘다.
    extracted();
    let f = fixtures().into_iter().find(|f| f.name == "lantern").expect("lantern");
    let path = results_dir().join(&f.name).join("norm-0.json");
    let head = oracle(&f, "norm-0.json")["$oracle"].clone(); // 그대로면 통과
    assert_eq!(head["rules"], common::oracle::js_rules().as_str());
    assert_eq!(head["icu"], common::oracle::slice_icu().as_str());
    for (key, bad) in [("rules", Some("calendar.js:000000000000")), ("rules", None), ("icu", Some("0.0")), ("icu", None)] {
        let mut h = head.clone();
        match bad { Some(text) => h[key] = json!(text), None => { h.as_object_mut().unwrap().remove(key); } }
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| common::oracle::check_head(&f, &path, &h)));
        let message = *caught.expect_err(&format!("머리의 {key}가 {bad:?}인데 통과했습니다")).downcast::<String>().expect("메시지");
        assert!(message.contains("정답지가 낡음"), "{message}");
    }
}

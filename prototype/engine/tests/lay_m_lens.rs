//! 과제 8-틀 — 모듈 `lens`(21/21)만 Node와 견준다(`common::modcheck` — `pre-metro`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 E(과제 15): 렌즈는 `themeLens`를 켜고 모든 트랙을 다시 배치해 자체 점검한 뒤 `themeLens = null`로 되돌려 다시 배치한다(lens.mjs 100 ~ 121줄) —
//! 되돌린 뒤의 연표 상태가 줄 배정 정답지(`rows.json`)와 값 · 덤프 글 바이트까지 같은지도 본다(렌즈 길이 tl에 남기는 것이 없음).
mod common;
use archive_engine::lay::model::util::list;
use archive_engine::lay::{self, ctx, js};
use common::oracle::{assert_same, fixtures, inputs, oracle, oracle_body, oracle_js, seam_opts};

#[test]
fn lens_contribute_matches_node() { common::modcheck::check_contribute("lens"); }

/// 렌즈 켬 배치 뒤 되돌린 연표 상태 = `rows.json`(값 · 바이트) · `themeLens`는 null로 남음(Node와 같음). 렌즈 켬 배치가 실제로 돈 자료(주제가 있고 `HT.lensAny`인 정권이 든 트랙이 있음)를 센다.
#[test]
fn lens_relayout_restores_rows() {
    let o = seam_opts(Some("lens"));
    let (mut seen, mut relaid, mut grow) = (0, Vec::new(), 0usize);
    for f in fixtures() {
        let mut c = ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        c.shared = lay::export::shared_seed(&oracle(&f, "pre-metro.shared.json")).expect("shared 심기");
        let mut out = oracle(&f, "pre-metro.json");
        if let Some(m) = out.as_object_mut() { m.remove("$oracle"); }
        let has_themes = !list(&c.model.get("themes")).is_empty();
        let lens_track = |tr: &js::V| list(&tr.get("periods")).iter().any(lay::rows::lens_any);
        let ran = has_themes && list(&c.tl.get("tracks")).iter().any(lens_track);
        // 렌즈 켬 배치가 '일을 하는' 트랙(렌즈 전 지도자 자리가 없다가 렌즈로 생김 — lens.mjs의 grow · 줄마다 +25) — `!before.leader && trackHas`
        if has_themes { grow += list(&c.tl.get("tracks")).iter().filter(|tr| !(js::to_num(&tr.get("geo").get("leaderH")) > 0.0) && lens_track(tr)).count(); }
        lay::m::lens::contribute(&mut c, &mut out).unwrap_or_else(|e| panic!("자료 {} · 렌즈: {e}", f.name));
        if ran {
            relaid.push(f.name.clone());
            assert!(c.tl.get("themeLens").is_null(), "자료 {}: 렌즈 켬 배치 뒤 themeLens가 null로 돌아오지 않았습니다", f.name);
        }
        let want = oracle_js(&f, "rows.json");
        assert_same(&f, "rows(렌즈 뒤)", &ctx::dump(&c), &js::to_json(&want));
        js::release(&want);
        assert!(ctx::dump_text(&c) == oracle_body(&f, "rows.json"), "자료 {} · rows(렌즈 뒤): 값은 같은데 덤프 글이 다릅니다", f.name);
        seen += 1;
    }
    assert!(seen > 0 && !relaid.is_empty(), "렌즈 켬 배치가 돈 자료가 없습니다 — 정답지 자료를 확인하세요");
    // 합성 자료 synth-lens(과제 X · 판정 R25)의 트랙 ln — 지도자가 하나도 없고 institutions만 · rankSpans만 · within 단체 powerSpans만인 나라 셋 — 이 렌즈 켬 배치(②)에 일을 시킨다.
    assert!(grow >= 1, "렌즈 켬으로 지도자 자리가 새로 생기는 트랙(grow)이 없습니다 — 합성 자료 synth-lens의 트랙 ln을 확인하세요");
    eprintln!("렌즈 뒤 연표 상태 = rows.json: 자료 {seen}개(렌즈 켬 배치가 돈 자료 {}개 — {}) · 렌즈 켬으로 지도자 자리가 새로 생기는 트랙(grow) {grow}개", relaid.len(), relaid.join(" · "));
}

/// `shared.bandOf`가 없으면 Node의 assert처럼 오류(조용히 빈손이 아님).
#[test]
fn lens_without_band_of_is_an_error() {
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "lantern").unwrap_or(&list[0]);
    let mut c = ctx::context_of(&inputs(f), &seam_opts(Some("lens")), true).expect("문맥");
    let mut out = oracle(f, "pre-metro.json");
    let e = lay::m::lens::contribute(&mut c, &mut out).expect_err("bandOf 없이는 오류");
    assert!(e.to_string().contains("띠 모듈(bands)이 먼저"), "{e}");
}

/// 과제 Y(갈래 E '조용히 이어 가는 길'): `institutionIndex.byTheme`이 Map이 아니면(JS `.get`에서 TypeError) · `model.events`가 배열이 아닌 참값이면
/// (JS `for … of`에서 TypeError) lens가 오류를 돌려준다(정답지 자료는 이 길을 밟지 않는다 — 모델을 손으로 고침). 오류 뒤에 잘못이 남지 않는다.
#[test]
fn lens_shape_faults_are_errors() {
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "lantern").expect("자료 lantern");
    let run = |poison: &dyn Fn(&js::V)| -> String {
        let mut c = ctx::context_of(&inputs(f), &seam_opts(Some("lens")), true).expect("문맥");
        c.shared = lay::export::shared_seed(&oracle(f, "pre-metro.shared.json")).expect("shared 심기");
        c.notes = js::Obj::new();
        let mut out = oracle(f, "pre-metro.json");
        out.as_object_mut().expect("out").remove("$oracle");
        poison(&c.model);
        let e = lay::m::lens::contribute(&mut c, &mut out).expect_err("오류여야 합니다").to_string();
        assert!(lay::model::util::take_fault().is_none(), "오류 뒤에 잘못이 남았습니다");
        e
    };
    let e = run(&|model| { if let js::V::Obj(ii) = model.get("institutionIndex") { ii.set("byTheme", js::Obj::new()); } else { panic!("institutionIndex가 없습니다") } });
    assert!(e.contains("lens 모듈") && e.contains("byTheme"), "{e}");
    let e = run(&|model| { model.as_obj().expect("모델").set("events", js::Obj::new()); });
    assert!(e.contains("lens 모듈") && e.contains("model.events가 순회되지 않습니다"), "{e}"); // 보통 객체는 JS for…of에서 TypeError(배열 · 글 · Map · Set은 돈다 — 16b)
    // Set은 사건 훑기(for…of)를 지나지만 차림표의 자료 있음(`HT.lensHasData` — `(m.events || []).some`)에서 JS는 TypeError(16b 틀 손질 검토).
    let e = run(&|model| {
        let set = js::Set::new();
        for x in lay::model::util::list(&model.get("events")) { set.add(x); }
        model.as_obj().expect("모델").set("events", js::V::Set(set));
    });
    assert!(e.contains("lens 모듈") && e.contains("m.events가 배열이 아닙니다"), "{e}");
}

/// `HT.lensHasData` — `(m.periods || []).some(…) || (m.events || []).some(…)`: 거짓 값은 빈 목록 · 참인데 배열이 아니면(글 · Map · Set · 객체) 잘못(JS라면 TypeError)을
/// 남기고 거짓. 앞(periods)이 참이면 뒤(events)는 보지 않는다(JS의 `||`).
#[test]
fn lens_has_data_faults_on_non_arrays() {
    use archive_engine::lay::m::lens::lens_has_data;
    use archive_engine::lay::model::util::take_fault;
    let model = |periods: js::V, events: js::V| { let m = js::Obj::new(); m.set("periods", periods); m.set("events", events); js::V::Obj(m) };
    let law = js::V::from("law");
    let ev = js::Obj::new();
    ev.set("law", true);
    let arr = |l: Vec<js::V>| js::V::Arr(js::Arr::new(l));
    // 배열 · 거짓 값은 그대로.
    assert!(lens_has_data(&model(arr(vec![]), arr(vec![js::V::Obj(ev.clone())])), &law));
    assert!(!lens_has_data(&model(js::V::Null, js::V::Undef), &law));
    assert!(take_fault().is_none());
    // 참인데 배열이 아님 → 잘못.
    let set = js::Set::new();
    set.add(js::V::Obj(ev.clone()));
    for (name, bad) in [("Set", js::V::Set(set)), ("Map", js::V::Map(js::Map::new())), ("글", js::V::from("x")), ("객체", js::V::Obj(js::Obj::new()))] {
        assert!(!lens_has_data(&model(arr(vec![]), bad.clone()), &law), "{name}");
        assert!(take_fault().is_some_and(|f| f.contains("m.events")), "{name}: events 잘못");
        assert!(!lens_has_data(&model(bad, arr(vec![])), &law), "{name}");
        assert!(take_fault().is_some_and(|f| f.contains("m.periods")), "{name}: periods 잘못");
    }
}

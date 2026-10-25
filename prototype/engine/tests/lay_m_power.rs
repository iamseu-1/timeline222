//! 과제 8-틀 — 모듈 `power`(17/21)만 Node와 견준다(`common::modcheck` — `pre-entities`를 심고 · shared `powerNominal`까지 · 늦은 차례는 `late-docs`를 심고 `late-power`와). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
mod common;

#[test]
fn power_contribute_matches_node() { common::modcheck::check_contribute("power"); }

#[test]
fn power_late_matches_node() { common::modcheck::check_late("power"); }

/// 과제 Y(갈래 E '조용히 이어 가는 길'): 트랙의 `foldedRows`가 Set(· Map)이 아니면 JS는 `tr.foldedRows.has`에서 TypeError — power가 오류를 돌려준다
/// (정답지 자료는 이 길을 밟지 않는다 — 줄 배정이 늘 Set을 둔다. 문맥을 손으로 고침). 오류 뒤에 잘못이 남지 않는다.
#[test]
fn folded_rows_not_a_set_is_an_error() {
    use archive_engine::lay::{self, ctx, js};
    use common::oracle::{fixtures, inputs, oracle, seam_opts};
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "lantern").expect("자료 lantern");
    let mut c = ctx::context_of(&inputs(f), &seam_opts(Some("power")), true).expect("문맥");
    c.shared = lay::export::shared_seed(&oracle(f, "pre-entities.shared.json")).expect("shared 심기");
    c.notes = js::Obj::new();
    let mut out = oracle(f, "pre-entities.json");
    out.as_object_mut().expect("out").remove("$oracle");
    for tr in lay::model::util::list(&c.tl.get("tracks")) { tr.as_obj().expect("트랙").set("foldedRows", js::Obj::new()); }
    let e = lay::m::power::contribute(&mut c, &mut out).expect_err("오류여야 합니다").to_string();
    assert!(e.contains("power 모듈") && e.contains("foldedRows가 Set이 아닙니다"), "{e}");
    assert!(lay::model::util::take_fault().is_none(), "오류 뒤에 잘못이 남았습니다");
}

/// 리메이크 3단계 거울 검토: 실권 줄의 끝이 Date 범위(약 ±27만 년) 밖이면 JS `minute`이 NaN을 돌려 `?? 띠 끝`으로 넘어가지 않고 `!(e >= s)`로 빠진다
/// (Node로 확인 — f4-office3의 두 실권 줄 끝을 300000으로: 구역 56 0개 · 알림 실권밑줄 0). 예전 Rust는 띠 끝으로 잘라 실었다.
#[test]
fn power_line_past_the_date_range_is_left_out() {
    use archive_engine::lay;
    use common::oracle::fixtures;
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "f4-office3").expect("자료 f4-office3");
    let mut raw: serde_json::Value = serde_json::from_slice(&std::fs::read(&f.inputs[0]).expect("자료 파일")).expect("JSON");
    for o in raw["objects"].as_array_mut().expect("objects") {
        if o["id"] == "o-khan" || o["id"] == "o-emp" { o["power"][0]["end"] = serde_json::json!(300000); }
    }
    let packs = [lay::PackIn { name: "f4-office3.json".into(), bytes: raw.to_string().into_bytes() }];
    let (out, notes) = lay::export::export_with_notes(&packs, &common::oracle::seam_opts(None)).expect("내보내기");
    let lines = out["items"].as_array().expect("items").iter().filter(|i| i["section"] == 56).count();
    assert_eq!(lines, 0, "구역 56이 남았습니다");
    assert_eq!(notes["단체단"]["실권밑줄"], serde_json::json!(0), "{}", notes["단체단"]);
}

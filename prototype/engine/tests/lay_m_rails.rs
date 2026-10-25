//! 과제 8-틀 — 모듈 `rails`(9/21)만 Node와 견준다(`common::modcheck` — `pre-persons`를 심고 · shared `railLevel` · `railRank`는 events가 쓴 것을 심음). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 B 덧붙임: 심은 shared에서 `railLevel` · `railRank`를 빼고 돌리면 rails가 [`rail_levels`]를 **스스로** 셈한다 — 그 덤프가 Node의 `pre-rails.shared.json`과
//! 값으로도, 그 열쇠의 글 조각 바이트로도 같아야 한다(뒤 모듈 · REPLAY가 Rust의 셈을 그대로 읽으므로).
mod common;

use archive_engine::lay::{self, js};
use common::oracle::{assert_same, fixtures, inputs, oracle, results_dir, seam_opts};
use serde_json::Value;

#[test]
fn rails_contribute_matches_node() { common::modcheck::check_contribute("rails"); }

/// 정답지 글에서 맨 위 열쇠 `key`의 값 글 조각(바이트 그대로).
fn slice_of<'a>(text: &'a str, key: &str) -> &'a str {
    let pat = format!("\"{key}\":");
    let at = text.find(&pat).unwrap_or_else(|| panic!("정답지에 {key}가 없습니다")) + pat.len();
    let mut it = serde_json::Deserializer::from_str(&text[at..]).into_iter::<Value>();
    it.next().expect("값이 있어야 함").expect("JSON 값");
    &text[at..at + it.byte_offset()]
}

#[test]
fn rails_own_rail_levels_match_node_bytes() {
    let o = seam_opts(Some("rails"));
    let mut n = 0;
    for f in fixtures() {
        let seed_out = oracle(&f, "pre-persons.json");
        let mut seed_shared = oracle(&f, "pre-persons.shared.json");
        let obj = seed_shared.as_object_mut().expect("shared는 객체");
        assert!(obj.remove("railLevel").is_some() && obj.remove("railRank").is_some(), "자료 {}: pre-persons.shared에 railLevel · railRank가 있어야 합니다(events가 씀)", f.name);
        let (got, got_shared) = lay::export_one(&inputs(&f), &o, "rails", Some(seed_out), Some(&seed_shared)).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        assert_same(&f, "pre-rails(railLevels를 스스로 셈)", &got, &oracle(&f, "pre-rails.json"));
        assert_same(&f, "pre-rails.shared(railLevels를 스스로 셈)", &got_shared, &oracle(&f, "pre-rails.shared.json"));
        let text = std::fs::read_to_string(results_dir().join(&f.name).join("pre-rails.shared.json")).expect("정답지 글");
        for key in ["railLevel", "railRank"] {
            let mine = js::seam_text(&js::from_json(&got_shared[key]));
            assert!(mine == slice_of(&text, key), "자료 {} · {key}: 덤프 글이 Node와 바이트로 다릅니다", f.name);
        }
        n += 1;
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다");
    eprintln!("rails가 스스로 셈한 railLevel · railRank: 자료 {n}개 Node와 값 · 바이트까지 같음");
}

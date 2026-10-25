//! 과제 8-틀 — 모듈 `events`(5/21)만 Node와 견준다(`common::modcheck` — `pre-strips`를 심고 · shared `railLevel` · `railRank`까지). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 B 덧붙임: events가 처음 셈해 둔 shared `railLevel` · `railRank`(rails.mjs의 `railLevels`)의 덤프 글이 Node의 `pre-events.shared.json`의 그 열쇠 글과 바이트까지 같은지.
mod common;

use archive_engine::lay::{self, js};
use common::oracle::{fixtures, inputs, oracle, results_dir, seam_opts};
use serde_json::Value;

#[test]
fn events_contribute_matches_node() { common::modcheck::check_contribute("events"); }

/// 정답지 글에서 맨 위 열쇠 `key`의 값 글 조각(바이트 그대로).
fn slice_of<'a>(text: &'a str, key: &str) -> &'a str {
    let pat = format!("\"{key}\":");
    let at = text.find(&pat).unwrap_or_else(|| panic!("정답지에 {key}가 없습니다")) + pat.len();
    let mut it = serde_json::Deserializer::from_str(&text[at..]).into_iter::<Value>();
    it.next().expect("값이 있어야 함").expect("JSON 값");
    &text[at..at + it.byte_offset()]
}

#[test]
fn events_rail_levels_match_node_bytes() {
    let o = seam_opts(Some("events"));
    let mut n = 0;
    for f in fixtures() {
        let seed_out = oracle(&f, "pre-strips.json");
        let seed_shared = oracle(&f, "pre-strips.shared.json");
        let (_, got_shared) = lay::export_one(&inputs(&f), &o, "events", Some(seed_out), Some(&seed_shared)).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        let text = std::fs::read_to_string(results_dir().join(&f.name).join("pre-events.shared.json")).expect("정답지 글");
        for key in ["railLevel", "railRank"] {
            let mine = js::seam_text(&js::from_json(&got_shared[key]));
            assert!(mine == slice_of(&text, key), "자료 {} · {key}: 덤프 글이 Node와 바이트로 다릅니다", f.name);
        }
        n += 1;
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다");
    eprintln!("events가 셈한 railLevel · railRank: 자료 {n}개 Node와 바이트까지 같음");
}

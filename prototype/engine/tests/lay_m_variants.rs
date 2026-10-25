//! 과제 8-틀 — 모듈 `variants`(18/21)만 Node와 견준다(`common::modcheck` — `pre-power`를 심고. REPLAY가 열두 모듈의 Rust `contribute`를 부르므로 그 열둘이 먼저 옮겨져야 통과한다). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
mod common;

#[test]
fn variants_contribute_matches_node() { common::modcheck::check_contribute("variants"); }

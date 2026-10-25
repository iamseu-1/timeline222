//! 과제 8-틀 — 모듈 `figures`(7/21)만 Node와 견준다(`common::modcheck` — `pre-hangs`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
mod common;

#[test]
fn figures_contribute_matches_node() { common::modcheck::check_contribute("figures"); }

//! 과제 8-틀 — 모듈 `hangs`(6/21)만 Node와 견준다(`common::modcheck` — `pre-events`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
mod common;

#[test]
fn hangs_contribute_matches_node() { common::modcheck::check_contribute("hangs"); }

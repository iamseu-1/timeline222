//! 과제 8-틀 — 모듈 `labels`(12/21)만 Node와 견준다(`common::modcheck` — `pre-scopes`를 심고 · shared `catNo`를 심음). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
mod common;

#[test]
fn labels_contribute_matches_node() { common::modcheck::check_contribute("labels"); }

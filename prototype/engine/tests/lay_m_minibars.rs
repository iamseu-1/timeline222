//! 과제 8-틀 — 모듈 `minibars`(13/21)만 Node와 견준다(`common::modcheck` — 앞자리 11개의 `pre-labels`(+ `.shared`)를 심고 이 모듈만 — 심는 길의 본보기). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`.
mod common;

#[test]
fn minibars_contribute_matches_node() { common::modcheck::check_contribute("minibars"); }

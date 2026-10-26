//! 과제 8-틀 — 모듈 `tracks`(1/21)만 Node와 견준다(`common::modcheck` — 첫 모듈이라 빈 out에서 · 늦은 차례는 `pre-lens`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`.
mod common;

#[test]
fn tracks_contribute_matches_node() { common::modcheck::check_contribute("tracks"); }

#[test]
fn tracks_late_matches_node() { common::modcheck::check_late("tracks"); }

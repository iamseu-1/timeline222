//! 과제 8-틀 — 모듈 `metro`(20/21)만 Node와 견준다(`common::modcheck` — `contribute`는 빈손 · 늦은 차례는 `late-power`를 심고 `late-metro`(= `upto-lens`)와). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
mod common;

#[test]
fn metro_contribute_matches_node() { common::modcheck::check_contribute("metro"); }

#[test]
fn metro_late_matches_node() { common::modcheck::check_late("metro"); }

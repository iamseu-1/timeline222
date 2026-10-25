//! 과제 8-틀 — 모듈 `axis`(2/21)만 Node와 견준다(`common::modcheck` — `pre-tracks`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 A(과제 8): 값 견줌에 더해 **바이트**도 — 열쇠를 정렬한 JSON 글(serde — 열쇠 차례는 계획 정한 것 #2로 견주지 않음)이 Node 출력의 같은 글과 같아야 한다
//! (수의 꼴: Node `5`를 Rust가 `5.0`으로 내면 값은 같아도 여기서 걸린다).
mod common;

use archive_engine::lay;
use common::oracle::{fixtures, inputs, oracle, seam_opts};
use serde_json::Value;

#[test]
fn axis_contribute_matches_node() { common::modcheck::check_contribute("axis"); }

/// 정답지 머리(`$oracle`)를 뗀 본문.
fn body(mut v: Value) -> Value { if let Some(o) = v.as_object_mut() { o.remove("$oracle"); } v }

#[test]
fn axis_contribute_bytes_match_node() {
    let o = seam_opts(Some("axis"));
    let mut n = 0;
    for f in fixtures() {
        let (got, got_shared) = lay::export_one(&inputs(&f), &o, "axis", Some(oracle(&f, "pre-tracks.json")), Some(&oracle(&f, "pre-tracks.shared.json")))
            .unwrap_or_else(|e| panic!("자료 {} · 모듈 axis: {e}", f.name));
        let (want, want_shared) = (body(oracle(&f, "pre-axis.json")), body(oracle(&f, "pre-axis.shared.json")));
        assert!(serde_json::to_string(&got).unwrap() == serde_json::to_string(&want).unwrap(), "자료 {} · pre-axis: 정렬한 JSON 글이 Node와 다릅니다", f.name);
        assert!(serde_json::to_string(&got_shared).unwrap() == serde_json::to_string(&want_shared).unwrap(), "자료 {} · pre-axis.shared: 정렬한 JSON 글이 Node와 다릅니다", f.name);
        n += 1;
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다");
    eprintln!("모듈 axis: 자료 {n}개 정렬한 JSON 글(바이트)까지 Node와 같음");
}

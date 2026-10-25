//! 과제 8-틀 — 모듈 `bands`(3/21)만 Node와 견준다(`common::modcheck` — `pre-axis`를 심고 · shared `bandOf`까지). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 A(과제 9): 값 견줌에 더해 **바이트**도 — out은 열쇠를 정렬한 JSON 글(serde — 열쇠 차례는 계획 정한 것 #2로 견주지 않음)이 Node의 같은 글과,
//! shared(이 모듈이 `bandOf`를 만든다 — 뒤 모듈 대부분이 읽음)는 **덤프 글 그대로**(JS 열쇠 차례 · `$map` 차례 · 수 글) `pre-bands.shared.json`의 본문과 같아야 한다.
mod common;

use archive_engine::lay::{self, js};
use common::oracle::{fixtures, inputs, oracle, oracle_body, seam_opts};
use serde_json::Value;

#[test]
fn bands_contribute_matches_node() { common::modcheck::check_contribute("bands"); }

/// 정답지 머리(`$oracle`)를 뗀 본문.
fn body(mut v: Value) -> Value { if let Some(o) = v.as_object_mut() { o.remove("$oracle"); } v }

#[test]
fn bands_contribute_bytes_match_node() {
    let o = seam_opts(Some("bands"));
    let mut n = 0;
    for f in fixtures() {
        // lay::export_one과 같은 길(문맥 · 심기 · 이 모듈 하나)을 손으로 — shared를 JS 차례 그대로의 덤프 글로 보려고
        let mut ctx = lay::ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        ctx.shared = lay::export::shared_seed(&oracle(&f, "pre-axis.shared.json")).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        ctx.notes = js::Obj::new();
        let mut out = body(oracle(&f, "pre-axis.json"));
        lay::m::bands::contribute(&mut ctx, &mut out).unwrap_or_else(|e| panic!("자료 {} · 모듈 bands: {e}", f.name));
        let want = body(oracle(&f, "pre-bands.json"));
        assert!(serde_json::to_string(&out).unwrap() == serde_json::to_string(&want).unwrap(), "자료 {} · pre-bands: 정렬한 JSON 글이 Node와 다릅니다", f.name);
        let got_shared = js::seam_text(&js::V::Obj(ctx.shared.clone()));
        let want_shared = oracle_body(&f, "pre-bands.shared.json");
        assert!(got_shared == want_shared, "자료 {} · pre-bands.shared: 덤프 글이 Node와 다릅니다\n  Rust: {}…\n  Node: {}…", f.name,
            got_shared.chars().take(200).collect::<String>(), want_shared.chars().take(200).collect::<String>());
        n += 1;
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다");
    eprintln!("모듈 bands: 자료 {n}개 out(정렬한 JSON 글) · shared(덤프 글 그대로)까지 Node와 바이트가 같음");
}

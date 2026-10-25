//! 과제 8-틀 — 모듈 `docs`(14/21)만 Node와 견준다(`common::modcheck` — `pre-minibars`를 심고 · shared `docsOf` · `cellDocsOf`까지 · 늦은 차례는 `late-tracks`를 심고 `late-docs`와). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 그리고 외톨이 서로게이트가 든 문서 글을 거절하는가(정규식이 `&str`에서 돌아 그 글을 JS와 같게 다룰 수 없다 — 갈래 C 고침 1회차).
mod common;

#[test]
fn docs_contribute_matches_node() { common::modcheck::check_contribute("docs"); }

#[test]
fn docs_late_matches_node() { common::modcheck::check_late("docs"); }

/// 정답지 자료 `synth`의 팩 글 끝에 시대 `p-a`의 문서 하나(`"a\ud800b"` — JSON 이스케이프의 외톨이 서로게이트)를 더해 지은 자료(검사 안에서만 — 자료 파일은 그대로)로
/// docs 모듈을 돌리면 "외톨이 서로게이트가 든 문서 글"로 거절한다(U+FFFD로 바꿔 조용히 다른 기록을 내지 않음). 같은 자리의 보통 글은 지어진다.
#[test]
fn docs_refuses_lone_surrogate_text() {
    use archive_engine::lay;
    let f = common::oracle::fixtures().into_iter().find(|f| f.name == "synth").expect("정답지 자료 synth");
    let seed = common::oracle::oracle(&f, "pre-minibars.json");
    let seed_shared = common::oracle::oracle(&f, "pre-minibars.shared.json");
    let o = common::oracle::seam_opts(Some("docs"));
    let with_doc = |doc: &str| {
        let mut packs = common::oracle::inputs(&f);
        let text = String::from_utf8(packs[0].bytes.clone()).expect("synth.json은 UTF-8");
        let end = text.rfind('}').expect("synth.json의 맨 위 객체");
        packs[0].bytes = format!("{},\"documents\":{{\"p-a\":\"{doc}\"}}}}{}", &text[..end], &text[end + 1..]).into_bytes();
        packs
    };
    let (out, _) = lay::export_one(&with_doc("a b"), &o, "docs", Some(seed.clone()), Some(&seed_shared)).expect("보통 글의 문서는 지어진다");
    assert!(out["entities"].as_array().expect("entities").iter().any(|e| e["uid"] == "doc:synth-world/p-a"), "더한 문서의 기록이 없다");
    // 짝 맞는 서로게이트(확장 한자 '𠀀' — JSON 이스케이프 \ud840\udc00)는 외톨이가 아니다 — 거절하지 않고 글 그대로 싣는다(과제 Y — 갈래 C 재검토 Minor)
    let (out, _) = lay::export_one(&with_doc(r"a\ud840\udc00b"), &o, "docs", Some(seed.clone()), Some(&seed_shared)).expect("짝 맞는 서로게이트가 든 글은 지어진다");
    let rec = out["entities"].as_array().expect("entities").iter().find(|e| e["uid"] == "doc:synth-world/p-a").expect("더한 문서의 기록이 없다");
    assert!(rec["json"].as_str().unwrap_or("").contains('\u{20000}'), "문서 기록에 확장 한자가 그대로 있어야 합니다: {}", rec["json"]);
    let e = lay::export_one(&with_doc(r"a\ud800b"), &o, "docs", Some(seed), Some(&seed_shared)).expect_err("외톨이 서로게이트가 든 글이 지어지면 안 된다").to_string();
    assert!(e.contains("외톨이 서로게이트가 든 문서 글"), "거절 글: {e}");
}

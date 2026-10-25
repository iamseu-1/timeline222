//! 리메이크 3단계 — 모듈 `persons`(8/21 · 사람 띠)만 Node와 견준다(`common::modcheck` — `pre-figures`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`.
//! 그리고 사람 띠와 문화권 시대 · 주기 줄이 함께 든 조합의 `sphereLines` 차례(계약 1-1 · 2절 — 배치 차례 그대로).
mod common;
use archive_engine::lay::{self, PackIn};
use serde_json::Value;

#[test]
fn persons_contribute_matches_node() { common::modcheck::check_contribute("persons"); }

/// 계약 1-1 · 2절(2026-10-25 과제 9 검토): `sphereLines`의 앞뒤 차례는 배치 차례 그대로이고, 지금 내보내기는 모듈 차례대로 문화권 시대 구분(kind 2) ·
/// 주기 줄(kind 3 — 둘 다 `axis` · 2번째 모듈) 다음 사람 띠(kind 1 — `persons` · 8번째 모듈)다. 정답지 자료는 한 갈래만 든 것(`f4-sphere` 2 · 3 ·
/// `f4-crowns` 1)뿐이라, 형식 4 가상 팩 둘을 함께 켠 조합을 Rust 거울과 Node(정답지와 같은 길 `oracle/combo.mjs`)로 통째 배치해 차례를 못 박는다 —
/// 주기 줄은 문화권마다 첫 것 하나라 둘(`ember-basin` · `frost-ridge`)이다.
#[test]
fn sphere_lines_keep_the_module_order_when_both_kinds_are_on() {
    let dir = common::node::repo_root().join("prototype").join("fixtures").join("f4");
    let pack = |id: &str| PackIn {
        name: format!("{id}.json"),
        bytes: std::fs::read(dir.join(format!("{id}.json"))).unwrap_or_else(|e| panic!("{id}.json을 읽지 못했습니다: {e}")),
    };
    let packs = vec![pack("f4-sphere"), pack("f4-crowns")];
    let o = common::oracle::seam_opts(None);
    let rust = lay::export(&packs, &o).unwrap_or_else(|e| panic!("Rust 배치: {e}"));
    let node = common::node::NodeLayouter::new("sphere-order", common::node::Touch::All).full(&packs, o.now_ms, o.tz_min);
    let kinds = |v: &Value| -> Vec<i64> { v["sphereLines"].as_array().map_or_else(Vec::new, |l| l.iter().map(|x| x["kind"].as_i64().unwrap()).collect()) };
    let k = kinds(&rust);
    assert_eq!(k, vec![2, 2, 2, 2, 3, 3, 1], "문화권 시대(2) · 주기 줄(3 — 문화권마다 하나) 다음 사람 띠(1)");
    let cycles: Vec<&str> = rust["sphereLines"].as_array().unwrap().iter().filter(|l| l["kind"] == 3).map(|l| l["sphere"].as_str().unwrap()).collect();
    assert_eq!(cycles, vec!["ember-basin", "frost-ridge"], "주기 줄은 켠 DLC 차례로 문화권마다 첫 것 하나");
    assert_eq!(rust["sphereLines"], node["sphereLines"], "Rust 거울 = Node(차례 · 값)");
}

//! 과제 8-틀 — 모듈 `strips`(4/21)만 Node와 견준다(`common::modcheck` — `pre-bands`를 심고). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 A(과제 9): 값 견줌에 더해 **바이트**도 — 열쇠를 정렬한 JSON 글(serde — 열쇠 차례는 계획 정한 것 #2로 견주지 않음)이 Node 출력의 같은 글과 같아야 한다.
//! (shared는 이 모듈이 읽기만 한다 — 심은 덤프가 serde 차례로 되심겨 맨 위 열쇠 차례가 바뀌므로 덤프 글 그대로는 견주지 않고 정렬한 글로.)
mod common;

use archive_engine::lay;
use common::oracle::{fixtures, inputs, oracle, seam_opts};
use serde_json::Value;

#[test]
fn strips_contribute_matches_node() { common::modcheck::check_contribute("strips"); }

/// 정답지 머리(`$oracle`)를 뗀 본문.
fn body(mut v: Value) -> Value { if let Some(o) = v.as_object_mut() { o.remove("$oracle"); } v }

#[test]
fn strips_contribute_bytes_match_node() {
    let o = seam_opts(Some("strips"));
    let mut n = 0;
    for f in fixtures() {
        let (got, got_shared) = lay::export_one(&inputs(&f), &o, "strips", Some(oracle(&f, "pre-bands.json")), Some(&oracle(&f, "pre-bands.shared.json")))
            .unwrap_or_else(|e| panic!("자료 {} · 모듈 strips: {e}", f.name));
        let (want, want_shared) = (body(oracle(&f, "pre-strips.json")), body(oracle(&f, "pre-strips.shared.json")));
        assert!(serde_json::to_string(&got).unwrap() == serde_json::to_string(&want).unwrap(), "자료 {} · pre-strips: 정렬한 JSON 글이 Node와 다릅니다", f.name);
        assert!(serde_json::to_string(&got_shared).unwrap() == serde_json::to_string(&want_shared).unwrap(), "자료 {} · pre-strips.shared: 정렬한 JSON 글이 Node와 다릅니다", f.name);
        n += 1;
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다");
    eprintln!("모듈 strips: 자료 {n}개 정렬한 JSON 글(바이트)까지 Node와 같음");
}

/// strips는 bands의 `shared.bandOf`가 없으면 JS처럼 멈춘다(`ctx.shared.bandOf.get` — TypeError) — 조용히 빈 칸을 내지 않는다.
#[test]
fn strips_without_band_of_is_an_error() {
    let f = fixtures().into_iter().next().expect("정답지 자료");
    let o = seam_opts(Some("strips"));
    let err = lay::export_one(&inputs(&f), &o, "strips", Some(oracle(&f, "pre-bands.json")), Some(&oracle(&f, "pre-axis.shared.json")));
    let err = err.err().expect("bandOf 없이 돌았습니다").to_string();
    assert!(err.contains("bandOf"), "오류 글에 까닭(bandOf)이 없습니다: {err}"); // 과제 Y — 갈래 A 검토 Minor: 다른 까닭의 오류로 통과하지 않게
}

/// 리메이크 3단계 거울 검토: 빌림 출처의 칸 목록이 배열이 아니면(형식 3 패치가 인물의 leaders · cabinets를 수로 바꿈 — 정규화를 지나 모델에 남음)
/// JS는 `cells.forEach`에서 TypeError로 내보내기가 멈춘다(Node로 확인 — 2026-10-24). Rust도 오류로(예전엔 칸 없이 지나갔다).
#[test]
fn borrowed_cells_not_a_list_is_an_error() {
    let raw = serde_json::json!({
        "format": "history-timeline-dlc", "formatVersion": 3, "id": "pk", "name": "팩", "tracks": [{ "id": "tr", "name": "트랙" }],
        "periods": [{ "id": "p0", "name": "앞나라", "track": "tr", "start": 50, "end": 100 },
                    { "id": "p1", "name": "나라", "track": "tr", "start": 100, "end": 200, "offices": [{ "name": "x", "from": "pk/fg" }] }],
        "figures": [{ "id": "fg", "name": "사람", "track": "tr", "start": 120, "end": 180 }],
        "events": [{ "id": "ev", "title": "일", "track": "tr", "start": 130 }],
        "patches": [{ "target": "pk/fg", "set": { "leaders": 7, "cabinets": 7 } }],
    });
    let packs = [lay::PackIn { name: "pk.json".into(), bytes: raw.to_string().into_bytes() }];
    let err = lay::export(&packs, &seam_opts(None)).expect_err("JS처럼 오류여야 합니다").to_string();
    assert!(err.contains("배열이 아닙니다"), "{err}");
}

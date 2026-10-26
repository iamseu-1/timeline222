//! 규칙 판(판정 R61 I1) — P4 지문과 저장소의 `meta.rules`에 섞는 **Rust 배치의 판 번호** [`LAY_RULES_VERSION`].
//! 배치 출력(정답지 자료의 Rust 통째 출력)이 달라질 때만 손으로 올린다. 올림을 잊지 않게 골든 검사(`tests/lay_golden.rs`)가 정답지 자료 전부의
//! Rust 통째 출력 해시를 커밋한 값과 견준다 — 다르면 '출력이 바뀌었다: LAY_RULES_VERSION을 올리고 골든을 새로'로 멈춘다.
//! 옮긴 JS 원본의 지문 `lay::RULES`는 낡음 검사(`tests/lay_scope.rs`)만 하고 지문에는 섞지 않는다.
//! (판정 R46 Minor의 첫 판은 `src/lay` 원본 바이트를 지문에 섞었다 — 주석 · 서식 · 검사 도움만 고쳐도 모든 저장소가 엔진을 올린 뒤 첫 넣기에 모든 트랙을
//! 다시 썼고 원본이 실행본에 실렸다.)

/// Rust 배치의 판 번호 — 배치 출력이 달라질 때만 올린다(골든 검사가 지킨다).
pub const LAY_RULES_VERSION: u32 = 11;

/// 규칙 판 글 — P4가 트랙 · 온 판 지문과 `meta.rules`에 섞는다(`patch::rules_mark`).
pub fn rules() -> String {
    format!("lay {LAY_RULES_VERSION}")
}

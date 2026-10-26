//! 내보내기 모듈 스물하나(`prototype/scripts/export/<이름>.mjs` → `lay/m/<이름>.rs` — JS 모듈 하나 = Rust 파일 하나 · 한 벌 P3 과제 8 ~ 15).
//! 차례 · 옮김 여부는 [`crate::lay::MODULES`](모듈마다 한 줄). 모듈마다 `pub const PORTED: bool` · `pub fn contribute(ctx, out)`(· `contribute_late`)가 있고,
//! 아직 옮기지 않은 모듈은 `PORTED = false`에 거절(`lay::export::unported`)만 둔 자리다 — 갈래는 제 모듈 파일만 고친다(이 목록 · `MODULES` 표는 손대지 않음).
//! 검사는 모듈마다 `tests/lay_m_<이름>.rs`(Node의 `pre-<앞 모듈>`을 심고 그 모듈 하나만 돌려 `pre-<이름>`과 견줌 — `lay::export_one`) · 통째는 `tests/lay_out.rs`.
pub mod axis;
pub mod bands;
pub mod boards;
pub mod calendar;
pub mod docs;
pub mod entities;
pub mod events;
pub mod figures;
pub mod hangs;
/// 모듈들이 함께 쓰는 작은 도움 · 상수(JS 모듈마다 사본이던 `lodOf` · `styleWith` · `cellStyle` · `ST` · `some` … — 과제 Y가 하나로).
pub mod kit;
pub mod labels;
pub mod lens;
pub mod links;
pub mod metro;
pub mod minibars;
/// 사람 띠(리메이크 3단계 · 계약 1-1 초안 — `sphere_lines` kind 1 · axis의 문화권 줄도 같은 표에 [`persons::push_line`]으로).
pub mod persons;
pub mod power;
pub mod rails;
pub mod scopes;
pub mod strips;
pub mod tracks;
pub mod variants;

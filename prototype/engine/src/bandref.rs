//! 일반 항목(items)의 `a` ~ `d` 가운데 **띠 번호**를 싣는 칸 — 같음의 눈(`canon`) · 트랙 지문(계획 P4 과제 4) · 덧붙여 넣기(과제 5c)가 함께 쓴다.
//! 띠 번호는 내보내기가 '`periods` 배열에서의 자리 + 1'로 적은 값이고, 새로 지은 저장소에서는 곧 `periods.id`다(가져오기가 적힌 차례대로 넣는다).
//! 트랙을 고쳐 써서 띠 번호가 통째 짓기와 달라질 수 있으므로, 이 칸은 수가 아니라 **띠 uid를 가리키는 값**으로 다뤄야 한다. 0은 '띠 없음'.
//!
//! 출처(2026-10-16 훑음):
//! - 내보내기 `prototype/scripts/export/hangs.mjs`의 `idOf`(= `bandOf` 순번 + 1) — 구역 16 · 44 · 45 · 47의 `d`.
//! - 내보내기 `prototype/scripts/export/links.mjs`의 `idOf` — 구역 21 · 22 · 49 · 52의 `b`.
//! - 계약 `docs/계약-아카이브-3단계.md` 6-4(구역 16의 `d` · 44 · 45 · 47의 표) · 6-10(관계선의 표 · '띠의 id를 `b`에 싣는 법').
//! - 판(`boards.mjs`)은 다시 돌린 매달린 이름표 · 관계선의 띠 번호를 **기본 배치의 번호**로 맞춰 싣고, 변형(`variants.mjs`)도 같은 모듈을 다시 돌린다 — 칸은 같다.
//! - 띠 번호를 싣지 않는 것(같은 구역 번호를 쓰지만): `minibars.mjs`의 구역 45(가는 막대 — `d` = 0) · `power.mjs`의 구역 47(연합 탭 `a` = 7 — `d` = 0) ·
//!   구역 16의 세로 끈(`b` = 4 — `d` = 품은 칸의 줄 + 1). `strips.mjs`(41 ~ 43 · 46)의 '순번 + 1'은 칸 순번이고, `power` · `lens` · `figures` · `rails` ·
//!   `scopes` · `events` · `bands`는 `a` ~ `d`에 띠 번호를 싣지 않는다.
//!
//! | 구역 | 칸 | 조건 | 가리키는 띠 | 낸 곳 |
//! | --- | --- | --- | --- | --- |
//! | 16 | d | b ≠ 4 | 속국 띠 | hangs 속국 이름표 |
//! | 44 | d | — | 속국 띠 | hangs 이름표의 모호한 연대 |
//! | 45 | d | — | 속국 띠 | hangs 이름표의 이설 경계(minibars의 가는 막대는 `d` = 0이라 '띠 없음'과 같다) |
//! | 47 | d | a ≠ 7 | 상국 띠 | hangs 뒤 장의 탭 |
//! | 21 | b | — | 후대 띠 | links 승계선 |
//! | 22 | b | — | 상국 띠 | links 소속선 |
//! | 49 | b | — | 짝 띠 | links 동군연합 이음줄의 끝 |
//! | 52 | b | — | 짝 토막 | links 옮겨 앉기의 끝 |

/// 칸 번호(`a` ~ `d`).
pub const A: usize = 0;
pub const B: usize = 1;
pub const C: usize = 2;
pub const D: usize = 3;

/// 구역 16의 `b` = 4 — 밖 ↔ 안을 옮긴 속국의 세로 끈(그때 `d`는 품은 칸의 줄 + 1).
const HANG_LINK: i64 = 4;
/// 구역 47의 `a` = 7 — 연합의 겹 탭(`power.mjs` — `d`는 0).
const COALITION_LOOK: i64 = 7;

/// 그 항목에서 띠 번호를 싣는 칸들(`A` ~ `D`). 값이 0이면 '띠 없음'이다.
pub fn band_fields(section: i64, a: i64, b: i64, c: i64, d: i64) -> Vec<usize> {
    // c · d는 지금 조건에 쓰이지 않는다 — 칸 값으로 가리는 조건이 더 생기면 쓴다.
    let _ = (c, d);
    match section {
        16 if b != HANG_LINK => vec![D],
        44 | 45 => vec![D],
        47 if a != COALITION_LOOK => vec![D],
        21 | 22 | 49 | 52 => vec![B],
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 띠_번호_칸은_구역과_조건으로_정해진다() {
        assert_eq!(band_fields(16, 0, 1, 0, 9), vec![D]);
        assert_eq!(band_fields(16, 0, HANG_LINK, 8, 3), Vec::<usize>::new(), "세로 끈의 d는 줄 + 1");
        assert_eq!(band_fields(44, 0, 0, 0, 9), vec![D]);
        assert_eq!(band_fields(45, 1, 2, 0, 0), vec![D], "가는 막대의 d = 0은 '띠 없음'");
        assert_eq!(band_fields(47, 3, 0, 0, 9), vec![D]);
        assert_eq!(band_fields(47, COALITION_LOOK, 0, 0, 0), Vec::<usize>::new(), "연합 탭");
        for s in [21, 22, 49, 52] {
            assert_eq!(band_fields(s, 0, 9, 0, 0), vec![B]);
        }
        for s in [17, 18, 19, 20, 23, 32, 41, 43, 46, 60] {
            assert!(band_fields(s, 1, 2, 3, 4).is_empty(), "구역 {s}");
        }
    }
}

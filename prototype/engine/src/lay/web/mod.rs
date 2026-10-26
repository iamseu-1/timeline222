//! 웹 함수 모음 — 여러 내보내기 모듈(과 읽기 · 모델)이 함께 부르는 `js/core.js` · `js/calendar.js`의 함수를 한 곳에 둔다(한 벌 P3 과제 Y — '웹 함수 모으기' · 판정 R22).
//! 모듈 갈래 다섯이 동시에 옮기며 저마다 제 모듈 파일 안에 겹쳐 옮겼던 것을 하나로 모았다 — 줄 그대로(JS 함수 하나 = Rust 함수 하나). 한 모듈만 부르는 웹 함수는
//! 그 모듈 곁에 그대로 둔다(예: `m/entities/web.rs`). 두 판이 있던 함수는 어느 판을 남겼는지 · 버린 판이 어떤 입력에서 달랐는지를 각 함수의 문서 주석에 적었다.
//! - [`cells`] — 칸의 종류 · 구간 · 경계 · 참조(`HT.CELL_KINDS` · `HT.cellKind` · `HT.cellSpan` · `HT.cellBound` · `HT.cellRefOf` · `HT.cellToNow`)
//! - [`alts`] — 이설(`HT.altSpan` · `altFlipSide` · `HT.altFlipped`)과 이설 경계(`altEdges` — strips · hangs · figures 모듈의 같은 사본)
//! - [`when`] — 날짜 글(`cal.formatT` · `cal.describe` · `HT.formatDate` · `HT.formatWhen` · `HT.formatRange` · `HT.figureRange` · `HT.altText`)
//! - [`words`] — 낱말 · 이름(`HT.kindName` · `HT.itemWord` · `HT.historicityOf` · `HT.historicityTag` · 승계의 이름 · `HT.relationName` · `HT.cmp16`) · 물려받은 이름
//! - [`glyphs`] — 글자 범위(`mergeRanges` · `HT.GLYPH_BAND` · `HT.GLYPH_WINDOW` · `inRanges` · `HT.glyphMissing`)
//!
//! 해(`HT.yearOf` · `HT.formatYear`)는 과제 5a의 자리 `read::dates`에 하나(JS 값 그대로 받는 꼴 — `y + 1e-9`의 `+`까지).
pub mod alts;
pub mod cells;
pub mod glyphs;
pub mod when;
pub mod words;

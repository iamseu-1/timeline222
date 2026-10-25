//! JS 값 층 — 웹 코드(약 1만 4천 줄)를 줄 그대로 옮기려고 JS 값의 뜻을 Rust에서 똑같이 낸다(한 벌 P3 과제 3).
//! 옮기는 규칙(계획 `계획-한벌-P3-Rust배치.md` 머리의 표)이 이 모듈의 뜻이다 — 뒤 과제(읽기 · 모델 · 줄 배정 · 모듈)가 모두 이 위에 선다.
//!
//! - 값: [`V`](`Undef` · `Null` · `Bool` · `Num(f64)` · `Str` · `Arr` · `Obj` · `Map` · `Set`). 배열 · 객체 · Map · Set은 `Rc<RefCell<…>>`라
//!   같은 객체를 여럿이 나눠 가지고(`===`은 [`strict_eq`] — Rc 같음), 고리도 된다.
//! - 객체 열쇠 차례: 정수 모양 열쇠(0 ~ 2³²−2)를 오름차순으로 먼저, 나머지는 넣은 차례(`Object.keys` · `JSON.stringify`와 같다).
//! - 글: [`Str`] — 보이는 뜻은 UTF-16 코드 단위의 열(`len16` · `slice16` · `code_at` · `cmp16` · `index_of16` · `trim` — 과제 5a가 더함). 확장 한자는 2.
//! - JSON: [`parse`](재귀 없이 — 깊이에 한계가 없다) · [`stringify`] · 수 글 [`num_str`](`5` · `1e+21` · `5e-7`).
//! - 셈의 뜻: [`round`](`Math.round`) · [`max`] · [`min`] · [`to_i32`] · [`to_u32`] · [`truthy`] · [`or`] · [`nullish`] · [`to_num`] · [`to_str`] ·
//!   [`parse_int`] · [`parse_float`] · [`add`](`+`) · [`sort`](V8의 TimSort 그대로 — 비교가 NaN이면 0 · undefined는 끝으로).
//! - 날짜: [`minute`](`prototype/scripts/export/base.mjs`의 `minute`) · [`local_ymd`](지역 연 · 월 · 일 — 시각과 시간대는 입력) · 날 수 ↔ 연월일
//!   [`days_from_civil`] · [`civil_from_days`](`Date`의 MakeDay 셈 — 문서의 나이 · `[date]`).
//! - 정답지 다리: [`seam`] · [`seam_text`](`prototype/scripts/oracle/seam.mjs`의 덤프 규칙) · [`to_json`] · [`from_json`](`serde_json::Value`).
//! - 모델 그래프(과제 6): 열거되지 않는 속성 [`Obj::define_hidden`] · [`Obj::hidden`] · 고리 풀기 [`release`](반복 — 깊이 · 고리에 상관없이) ·
//!   살아 있는 그릇 수 `live_containers`(새는지 셈 — 검사 비계라 `oracle` 기능에서만 · 판정 R69-7) · 사본을 정렬해 되쓰기 [`Arr::sort_js`].
//!
//! 옮긴 원본(SHA-256 앞 12자 — 저장소의 LF 바이트):
//! - `prototype/scripts/export/base.mjs` 49 ~ 55줄 `minute` — 13ed7b3eef3e (→ `js/date.rs`)
//! - `prototype/scripts/oracle/seam.mjs` 14 ~ 62줄 `seam` — 5e7f7f6c2d84 (→ `js/json.rs`)
//! - V8 `third_party/v8/builtins/array-sort.tq`의 TimSort(`Array.prototype.sort`) — 비교 부르는 차례까지 같게(→ `js/sort.rs`).
//!   정답은 Node 24(V8 13)의 결과를 벡터로 굳힌 것(`prototype/engine/tests/fixtures/lay/js-vectors.json` — 비교 부름 수 · 차례 체크섬까지).
//!
//! 벡터: `node prototype/scripts/js-vectors.mjs`(시간대 Asia/Seoul) → `tests/lay_js.rs`가 견준다.

mod date;
mod json;
mod num;
mod sort;
mod text;
mod value;

pub use date::{civil_from_days, days_from_civil, local_ymd, minute};
pub use json::{from_json, parse, seam, seam_text, stringify, to_json};
pub use num::{add, is_space, max, min, num_str, nullish, or, parse_float, parse_int, round, to_i32, to_num, to_str, to_u32, truthy};
pub use sort::{sort, sort_by, sort_default};
pub use text::{Str, Units};
pub use value::{for_of, release, strict_eq, type_of, Arr, Key, Map, Obj, Set, V};
#[cfg(feature = "oracle")]
pub use value::live_containers;

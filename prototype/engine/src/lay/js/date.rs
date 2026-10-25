//! 날짜의 JS 뜻: [`minute`](해 → 정수 분 — `prototype/scripts/export/base.mjs` 49 ~ 55줄, SHA-256 13ed7b3eef3e) · [`local_ymd`](지역 연 · 월 · 일).
//! `Date`는 쓰지 않고 규격의 공식(DayFromYear · TimeClip)으로 같은 값을 낸다 — 서기 0년이 없는 연도(−1 다음이 1)를 천문 연도로 옮기는 것까지 `minute`과 같다.
use super::num::round;

const MS_PER_DAY: f64 = 86_400_000.0;
/// `Date`가 담는 시각의 끝(±8.64 × 10¹⁵ 밀리초 — 규격 TimeClip).
const TIME_CLIP: f64 = 8.64e15;

/// 규격 DayFromYear(y) — 1970-01-01부터 y년 1월 1일까지의 날 수(천문 연도 · 그레고리력 연장).
fn day_from_year(y: i64) -> i64 {
    365 * (y - 1970) + (y - 1969).div_euclid(4) - (y - 1901).div_euclid(100) + (y - 1601).div_euclid(400)
}
/// `d = new Date(0); d.setUTCFullYear(year, 0, 1); d.setUTCHours(0, 0, 0, 0); d.getTime()` — Date 범위 밖이면 NaN.
fn year_start(year: f64) -> f64 {
    if !year.is_finite() || year.abs() > 1e6 { return f64::NAN; } // 1e6년은 이미 범위 밖(±27만 년)
    let t = day_from_year(year as i64) as f64 * MS_PER_DAY;
    if t.abs() > TIME_CLIP { f64::NAN } else { t }
}

/// 해(실수) → 정수 분 — 그 해의 양 끝 날짜 사이를 비례로(`base.mjs`의 `minute`).
/// ```js
/// export function minute(y) {
///   if (!Number.isFinite(y)) return null;
///   const year = Math.floor(y), a = new Date(0), b = new Date(0);
///   a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
///   b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
///   return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
/// }
/// ```
/// JS는 수가 아닌 해에 null, Date 범위 밖(약 ±27만 년)에 NaN을 내는데 둘 다 JSON에서 null이라 여기서는 None 하나로.
pub fn minute(y: f64) -> Option<i64> {
    if !y.is_finite() { return None; }
    let year = y.floor();
    let a = year_start(if year < 0.0 { year + 1.0 } else { year });
    let b = year_start(if year == -1.0 { 1.0 } else if year < 0.0 { year + 2.0 } else { year + 1.0 });
    let m = round((a + (b - a) * (y - year)) / 60000.0);
    if m.is_nan() { None } else { Some(m as i64) }
}

/// (연, 월 1 ~ 12, 일) → 1970-01-01부터의 날 수 — 그레고리력 연장(H. Hinnant의 days_from_civil — JS `Date`의 MakeDay와 같은 셈).
/// (과제 Y — `m/docs/wiki.rs`의 나이 셈에 있던 같은 몸을 여기 하나로.)
pub fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}
/// 1970-01-01부터의 날 수 → (연, 월 1 ~ 12, 일) — 그레고리력 연장(H. Hinnant의 civil_from_days). (과제 Y — `wiki.rs`의 같은 몸을 여기 하나로.)
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

/// `new Date()`의 지역 연 · 월 · 일(`getFullYear()` · `getMonth() + 1` · `getDate()`) — 월은 1 ~ 12.
/// '오늘'(`now_ms` — 1970-01-01T00:00:00Z부터의 밀리초)과 시간대(`tz_min` — UTC보다 앞선 분, 서울 540)는 입력이다
/// (진행 중 정권의 끝 · 문서의 나이가 여기에 달린다 — 정답지는 2026-10-15T12:00:00+09:00 · 540).
/// 시간대는 고정 오프셋으로 본다(서울은 1988년 뒤로 일광 절약이 없다).
pub fn local_ymd(now_ms: f64, tz_min: i32) -> (i32, u32, u32) {
    let local = now_ms + f64::from(tz_min) * 60_000.0;
    let (y, m, d) = civil_from_days((local / MS_PER_DAY).floor() as i64);
    (y as i32, m as u32, d as u32)
}

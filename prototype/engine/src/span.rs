//! 달력 단위로 재는 걸침 — 지금 연표의 `HT.spanHit` · `HT.spanMeets`(`js/core.js:696~714`)를 분 좌표로 옮긴 것.
//!
//! 왜 따로 두는가: 칸의 경계는 이웃 칸과 겹치지 않게 정해지는데(앞 칸의 끝 = 뒤 칸의 시작),
//! **연도만 적은 한 해짜리 사건**을 `시작 ≤ 끝 && 끝 ≥ 시작`으로 재면 경계 해의 사건이 앞뒤 두 칸에 모두 든다.
//! 지금 연표는 그런 항목을 **그 달력 단위의 한가운데 한 점**으로 보아 한쪽에만 넣는다 — 칸 상세의 '이 시기의 사건'과
//! 같은 시기 타국(메아리)이 연표의 칠과 같은 답을 쓰려면 이 셈이 같아야 한다.
//!
//! 규칙(`HT.spanHit`):
//! 1. 시작이 덮는 단위 `S = [s0, s1)`를 날짜 정밀도(사건의 `rail` 8~10비트 — 계약 6-6)로 낸다.
//! 2. 끝이 없거나 끝의 단위가 `S`와 같으면(연도만 적은 사건 · 점 사건) **`S`의 한가운데 한 점**으로 본다.
//! 3. 아니면 `[s0, max(s0, e1))` — 끝이 덮는 단위의 **끝까지**가 그 항목의 구간이다.
//!
//! 이 파일의 범위는 모두 **반열린 구간 `[lo, hi)` — `hi`는 바깥**이다. 칸의 경계가 본디 그렇게 생겼고
//! (앞 칸의 `hi` = 뒤 칸의 `lo` = **뒤 칸의 첫 분**), `events_in` · `echo`도 화면이 보내는 그 값을 그대로 받는다
//! (계약 2-1절). 양 끝 포함으로 재면 `hi`에서 **시작하는** 기간 사건과 `hi`에 놓인 점 사건이 앞뒤 두 칸에 모두 든다.
use crate::DAY;

/// 가장 긴 달력 단위(윤년 한 해)의 분. SQL로 미리 거를 때 양쪽으로 이만큼 넓혀야
/// '단위의 한가운데'로 밀려난 항목을 놓치지 않는다.
pub const MAX_UNIT: i64 = 366 * DAY;

/// 원형 그레고리력의 날 수(1970-01-01 = 0). Howard Hinnant의 `days_from_civil`.
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// 날 수 → (해, 달, 날). Howard Hinnant의 `civil_from_days`.
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// 그 분이 든 달력 단위 `[처음, 다음 단위의 처음)`. `prec`는 사건의 `rail` 8~10비트다
/// (0 해 · 1 달 · 2 날 · 3 시 · 4 분). 분까지 적은 것은 단위가 없어 `None`(한 점)이다.
///
/// 화면 쪽 `app/lib/scene/label_batch.dart`의 `_precSpan`과 같은 셈이다 — **적힌 값이 아니라
/// 그 값이 든 단위**를 낸다(잘 적힌 자료에서는 둘이 같고, 어긋난 자료에서도 답이 흔들리지 않는다).
pub fn prec_span(minute: i64, prec: i64) -> Option<(i64, i64)> {
    let day = minute.div_euclid(DAY);
    let (year, month, _) = civil_from_days(day);
    match prec {
        0 => Some((days_from_civil(year, 1, 1) * DAY, days_from_civil(year + 1, 1, 1) * DAY)),
        1 => {
            let (next_year, next_month) = if month == 12 { (year + 1, 1) } else { (year, month + 1) };
            Some((days_from_civil(year, month, 1) * DAY, days_from_civil(next_year, next_month, 1) * DAY))
        }
        2 => Some((day * DAY, (day + 1) * DAY)),
        3 => {
            let hour = minute.div_euclid(60);
            Some((hour * 60, hour * 60 + 60))
        }
        _ => None,
    }
}

/// 구간 `[a, b)`가 `[lo, hi)`에 걸치는가 — 지금 연표의 `HT.spanMeets` 그대로.
/// 폭 0인 쪽은 닫힌 한 점으로 본다. **값은 모두 두 배로 적은 좌표**라 단위의 한가운데(0.5분)도 반올림 없이 잰다.
fn span_meets2(a: i64, b: i64, lo: i64, hi: i64) -> bool {
    if b <= a {
        return if hi > lo { lo <= a && a < hi } else { a == lo };
    }
    if hi <= lo {
        return a <= lo && lo < b;
    }
    a < hi && lo < b
}

/// 사건 하나가 `[lo, hi)`(**`hi`는 바깥** · 분)에 걸치는가 — `HT.spanHit`.
/// `rail`은 사건의 `rail` 열이고 8~10비트만 쓴다. 날짜를 모르는 사건은 늘 거짓이다.
/// `lo == hi`는 빈 구간이 아니라 **그 분 한 점**이다(`HT.spanMeets`의 폭 0 가지 그대로).
pub fn span_hit(start: Option<i64>, end: Option<i64>, rail: i64, lo: i64, hi: i64) -> bool {
    let Some(start) = start else { return false };
    let prec = (rail >> 8) & 7;
    let s = prec_span(start, prec).unwrap_or((start, start));
    // 끝이 없으면 시작과 같은 단위로 본다(js의 `E === null` 가지와 같은 답).
    let e = end.map(|t| prec_span(t, prec).unwrap_or((t, t))).unwrap_or(s);
    let (a, b) = if e == s {
        // 한 단위뿐인 항목은 그 단위의 한가운데 한 점 — 경계 해의 사건이 앞뒤 두 칸에 모두 들지 않게.
        let middle = s.0 + s.1;
        (middle, middle)
    } else {
        (2 * s.0, 2 * s.0.max(e.1))
    };
    span_meets2(a, b, 2 * lo, 2 * hi)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 기원후 n년의 첫 분.
    fn ad(n: i64) -> i64 {
        days_from_civil(n, 1, 1) * DAY
    }

    #[test]
    fn 날짜_산수는_서로의_되돌림이다() {
        for (y, m, d) in [(1970, 1, 1), (1, 1, 1), (-500, 12, 31), (2000, 2, 29), (827, 5, 12)] {
            assert_eq!(civil_from_days(days_from_civil(y, m, d)), (y, m, d), "{y}-{m}-{d}");
        }
        assert_eq!(days_from_civil(1970, 1, 1), 0);
    }

    #[test]
    fn 정밀도가_덮는_단위는_해_달_날_시다() {
        let at = days_from_civil(827, 5, 12) * DAY + 3 * 60 + 20;
        assert_eq!(prec_span(at, 0), Some((ad(827), ad(828))));
        assert_eq!(prec_span(at, 1), Some((days_from_civil(827, 5, 1) * DAY, days_from_civil(827, 6, 1) * DAY)));
        assert_eq!(prec_span(at, 2), Some((days_from_civil(827, 5, 12) * DAY, days_from_civil(827, 5, 13) * DAY)));
        assert_eq!(prec_span(at, 3), Some((days_from_civil(827, 5, 12) * DAY + 180, days_from_civil(827, 5, 12) * DAY + 240)));
        assert_eq!(prec_span(at, 4), None, "분까지 적은 것은 단위가 없다");
        // 12월은 다음 해 1월로 넘어간다.
        assert_eq!(prec_span(days_from_civil(827, 12, 3) * DAY, 1), Some((days_from_civil(827, 12, 1) * DAY, ad(828))));
    }

    #[test]
    fn 연도만_적은_사건은_그해_한가운데_한_점이다() {
        // 앞 칸 [800, 900) · 뒤 칸 [900, 1000)에서 900년 사건은 뒤 칸의 것이다.
        let at = ad(900);
        assert!(!span_hit(Some(at), Some(at), 0, ad(800), ad(900)), "앞 칸에는 들지 않는다");
        assert!(span_hit(Some(at), Some(at), 0, ad(900), ad(1000)), "뒤 칸의 것이다");
        // 그해의 첫 분 · 마지막 분만 덮는 구간에는 들지 않는다(한가운데가 아니므로).
        assert!(!span_hit(Some(at), Some(at), 0, ad(900), ad(900)));
        assert!(!span_hit(Some(at), Some(at), 0, ad(901) - 1, ad(901) - 1));
        // 그해 한가운데의 분에는 든다.
        let middle = (ad(900) + ad(901)) / 2;
        assert!(span_hit(Some(at), Some(at), 0, middle, middle));
    }

    #[test]
    fn 기간_사건은_끝이_덮는_단위의_끝까지다() {
        // 820~827년(연도만) → [820년 첫 분, 828년 첫 분)
        let (from, to) = (ad(820), ad(827));
        assert!(span_hit(Some(from), Some(to), 0, ad(827), ad(828)), "끝난 해에도 걸친다");
        assert!(!span_hit(Some(from), Some(to), 0, ad(828), ad(829)), "그 다음 해에는 걸치지 않는다");
        assert!(span_hit(Some(from), Some(to), 0, ad(820), ad(820)), "시작한 해의 첫 분에도 걸친다");
        assert!(!span_hit(Some(from), Some(to), 0, ad(819), ad(820)), "시작 앞 해에는 걸치지 않는다");
    }

    #[test]
    fn 날짜까지_적은_사건은_그날을_기준으로_잰다() {
        let at = days_from_civil(827, 5, 12) * DAY;
        // 날 정밀도의 한 점은 그날 한가운데(720분)다.
        assert!(span_hit(Some(at), Some(at), 2 << 8, at, at + 721));
        assert!(!span_hit(Some(at), Some(at), 2 << 8, at, at + 720), "hi는 바깥이다");
        assert!(span_hit(Some(at), Some(at), 2 << 8, at + 720, at + 720));
        assert!(!span_hit(Some(at), Some(at), 2 << 8, at + 721, at + 1000));
    }

    #[test]
    fn 분까지_적은_사건은_적힌_그대로_한_점이다() {
        let at = days_from_civil(827, 5, 12) * DAY + 200;
        assert!(span_hit(Some(at), Some(at), 4 << 8, at, at));
        assert!(!span_hit(Some(at), Some(at), 4 << 8, at + 1, at + 2));
        assert!(!span_hit(Some(at), Some(at), 4 << 8, at - 2, at - 1));
    }

    /// 칸의 경계 분(앞 칸의 `hi` = 뒤 칸의 `lo`)에서 시작하는 것들 — 양 끝 포함으로 재면 앞 칸에도 들었다.
    #[test]
    fn 경계_분에서_시작하는_것은_뒤_칸의_것이다() {
        let edge = ad(900);
        // ① 경계 해에 시작하는 기간 사건(한가운데 한 점이 아니라 [시작, 끝이 덮는 단위의 끝) 그대로 재는 쪽).
        let (from, to) = (edge, ad(910));
        assert!(!span_hit(Some(from), Some(to), 0, ad(800), edge), "앞 칸에는 들지 않는다");
        assert!(span_hit(Some(from), Some(to), 0, edge, ad(1000)), "뒤 칸의 것이다");
        // ② 분까지 적어 경계 분에 놓인 점 사건.
        assert!(!span_hit(Some(edge), Some(edge), 4 << 8, ad(800), edge), "앞 칸에는 들지 않는다");
        assert!(span_hit(Some(edge), Some(edge), 4 << 8, edge, ad(1000)), "뒤 칸의 것이다");
        // ③ 날까지 적어 경계 날에 시작하는 기간 사건.
        let next_day = edge + DAY;
        assert!(!span_hit(Some(edge), Some(next_day), 2 << 8, ad(800), edge), "앞 칸에는 들지 않는다");
        assert!(span_hit(Some(edge), Some(next_day), 2 << 8, edge, ad(1000)), "뒤 칸의 것이다");
    }

    #[test]
    fn 날짜를_모르는_사건은_어디에도_걸치지_않는다() {
        assert!(!span_hit(None, None, 0, ad(800), ad(900)));
    }

    #[test]
    fn 넓혀_거를_때의_여유는_가장_긴_단위보다_길다() {
        for year in [1900, 2000, 1, -500] {
            assert!(ad(year + 1) - ad(year) <= MAX_UNIT, "{year}년");
        }
    }
}

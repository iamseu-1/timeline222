//! `js/core.js` 3216 ~ 3359줄 — 날짜 칸(해 좌표 · 날짜 글 짝 칸)의 공용 함수와 정규화의 머리 도움 — 한 벌 P3 과제 5a · 5c(`PATCHABLE`).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 3216 ~ 3218줄 `HT.DATE_KEYS` · 3220 ~ 3223줄 `HT.NOW_T`(→ `read::Ctx::now_t`)
//! - 3225 ~ 3233줄 `HT.yearOf` · `HT.formatYear`
//! - 3239 ~ 3244줄 `atFits`
//! - 3257 ~ 3264줄 `HT.endBound`
//! - 3301 ~ 3323줄 `HT.parseYear` · `HT.readDate` · `HT.isOngoingText`
//! - 3333 ~ 3338줄 `ID_RE` · `str` · `arr` · `toYear` · `dateIn`
//! - (5c) 3342 ~ 3359줄 `PATCHABLE`(패치로 바꿀 수 있는 칸 — 3343 ~ 3358줄의 push까지 한 목록)
//!   (2026-10-24 맞춤 · 리메이크 6단계 걸음 2 · `core.js` `b2e6b19490bf`) 3662줄 `PATCHABLE.push('faiths')`(종교 — D8)
//!
//! 여기 없는 것(읽기가 부르지 않음): `HT.atOf` · `HT.endIn`(→ `model::util`) · `HT.formatDate` · `HT.formatWhen` · `HT.formatRange` · `HT.figureRange`(→ `lay::web::when`) ·
//! `HT.figureLife` · `HT.shiftDate`(옮기지 않음 — 부르는 곳 없음).
use super::Ctx;
use crate::lay::cal;
use crate::lay::js::{self, Str, V};

/// `HT.DATE_KEYS`(시작 · 끝 + 3217줄의 생몰).
pub const DATE_KEYS: [&str; 4] = ["start", "end", "birth", "death"];

/// `HT.yearOf(y)` — 해 좌표가 속한 해(1592.9 → 1592). 비어 있는 0년 자리는 1년으로(`y !== 0`이라 null도 1년).
/// JS 값 그대로 받는다 — `Math.floor(y + 1e-9)`의 `+`까지(글이면 잇기: `'1592' + 1e-9` = `'15921e-9'`).
///
/// 하나로 모은 판(과제 Y): 갈래 B(events의 `year_of_v` · `format_year_v`) · 갈래 D(entities의 같은 둘)가 옮긴 'JS 값 그대로'의 판. 버린 판 — 이 자리에 있던 과제 5a의
/// '수만 받는' 판(부르는 쪽이 `Number(y)`로 바꿔 넘김)과 갈래 C(metro)의 사본(`Number(y) + 1e-9`)은 **글로 온 해**에서 JS와 갈렸다(수에서는 같음).
/// 수로 부르던 곳은 [`year_of_t`] · [`format_year_t`]로 그대로 수를 넘긴다(뜻 그대로).
pub fn year_of(y: &V) -> f64 {
    let n = js::to_num(&js::add(y, &V::Num(1e-9))).floor();
    if n == 0.0 && !matches!(y, V::Num(x) if *x == 0.0) { 1.0 } else { n }
}
/// [`year_of`]를 수로 부르는 짧은 꼴.
pub fn year_of_t(y: f64) -> f64 { year_of(&V::Num(y)) }
/// `HT.formatYear(y)` — "기원전 108년" · "1592년"(비었거나 `isFinite`(전역 — 글이면 수로 바꿔 봄)가 거짓이면 ''). JS 값 그대로 받는다([`year_of`]).
pub fn format_year(y: &V) -> String {
    if y.is_nullish() || !js::to_num(y).is_finite() { return String::new(); }
    let n = year_of(y);
    if n < 0.0 { format!("기원전 {}년", js::num_str(-n)) } else { format!("{}년", js::num_str(n)) }
}
/// [`format_year`]를 수로 부르는 짧은 꼴.
pub fn format_year_t(y: f64) -> String { format_year(&V::Num(y)) }

/// `atFits(at, t)` — 짝 칸의 날짜 글이 값과 맞을 때만 쓴다(값만 고치고 글을 못 지운 경우엔 값이 이김).
pub fn at_fits(ctx: &Ctx, at: &V, t: &V) -> bool {
    let V::Str(text) = at else { return false };
    if text.trim().is_empty() { return false; }
    let V::Num(t) = t else { return true };
    let Some(r) = cal::parse(&ctx.cal, at) else { return false };
    r.ok && ((r.t - t).abs() < 1e-6 || r.last.is_some_and(|last| (last - t).abs() < 1e-6)) // 세기로 적은 끝은 구간의 마지막 해에 놓임
}

/// `HT.endBound(end, endAt)` — 연도만 적은 끝(정수 · 날짜 글 없음)이 실제로 뜻하는 마지막 순간: 그해 끝. 세기로 적은 끝("3세기 말")은 그 구간의 끝까지.
/// 값은 JS 값 그대로 받고 돌려준다(원본처럼 — 비었으면 그대로, 수가 아닌 끝은 그해 끝으로 올리지 않고 그대로: 글 `'1600'`은 `'1600'`).
pub fn end_bound(ctx: &Ctx, end: &V, end_at: &V) -> V {
    if end.is_nullish() { return end.clone(); }
    if js::truthy(end_at) {
        if let Some(r) = cal::parse(&ctx.cal, end_at) {
            if r.ok {
                if let (Some(span), Some(last)) = (r.span, r.last) {
                    let e = js::to_num(end); // r.t - end · r.last - end — 수로 바뀜
                    if (r.t - e).abs() < 1e-6 || (last - e).abs() < 1e-6 { return V::Num(span.1 - 1e-9); }
                }
            }
        }
    }
    match end {
        V::Num(n) if n.is_finite() && *n == n.trunc() && !js::truthy(end_at) => V::Num(n + 1.0 - 1e-9),
        _ => end.clone(),
    }
}
/// [`end_bound`]를 수로 부르는 짧은 꼴 — 끝이 늘 수인 곳(날짜 칸을 읽어 얻은 `t`)에서.
pub fn end_bound_t(ctx: &Ctx, end: f64, end_at: &V) -> f64 { js::to_num(&end_bound(ctx, &V::Num(end), end_at)) }

/// `HT.parseYear(input)` — 연도 · 날짜 글이나 수를 해 좌표로. 실패하면 NaN.
pub fn parse_year(ctx: &Ctx, input: &V) -> f64 {
    if let V::Num(x) = input { return if x.is_finite() { *x } else { f64::NAN }; }
    match cal::parse(&ctx.cal, input) { Some(r) if r.ok => r.t, _ => f64::NAN }
}

/// `HT.readDate`의 답 `{ t, at, prec, cal }` · 못 읽으면 `{ t: NaN, at: null, error }`.
#[derive(Debug, Clone)]
pub struct DateR { pub t: f64, pub at: Option<Str>, pub prec: &'static str, pub cal: &'static str, pub error: Option<Str> }

/// `HT.readDate(v, atRaw)` — 날짜 칸 하나를 읽는다 → None(빈 값) · `{ t, at, prec, cal }` · `{ t: NaN, error }`.
/// at = 연도만 적은 서력이 아니면 표준 날짜 글. 짝 칸 글(atRaw)은 값이 비었거나 값과 맞을 때만 쓴다.
pub fn read_date(ctx: &Ctx, v: &V, at_raw: &V) -> Option<DateR> {
    let mut src = v.clone();
    if let V::Str(at) = at_raw {
        if !at.trim().is_empty() {
            if v.is_nullish() || super::is_empty_str(v) { src = at_raw.clone(); }
            else if matches!(v, V::Num(_)) && at_fits(ctx, at_raw, v) { src = at_raw.clone(); }
        }
    }
    if src.is_nullish() || super::is_empty_str(&src) { return None; }
    if matches!(src, V::Str(_)) && (is_unknown_text(&src) || is_ongoing_text(&src)) {
        return Some(DateR { t: f64::NAN, at: None, prec: "", cal: "", error: Some(Str::from("날짜가 아닙니다.")) });
    }
    let r = cal::parse(&ctx.cal, &src)?;
    if !r.ok { return Some(DateR { t: f64::NAN, at: None, prec: "", cal: "", error: Some(r.error) }); }
    Some(DateR { t: r.t, at: if r.fine && r.prec != "x" { Some(r.text) } else { None }, prec: r.prec, cal: r.cal, error: None })
}

/// JS `String(s ?? '').trim()`.
fn text_of(v: &V) -> Str { js::to_str(&js::nullish(v.clone(), V::from(""))).trim() }

/// `HT.isOngoingText(s)` — `/^(현재|진행\s*중|present|now|ongoing)$/i`. `i`는 ASCII 글자만 접는다(JS의 `u` 없는 `i` — U+017F(긴 s)는 's'가 아님).
pub fn is_ongoing_text(v: &V) -> bool {
    let t = text_of(v);
    let Some(s) = t.exact() else { return false };
    if s == "현재" || ["present", "now", "ongoing"].iter().any(|w| s.eq_ignore_ascii_case(w)) { return true; }
    s.strip_prefix("진행").and_then(|rest| rest.strip_suffix('중')).is_some_and(|mid| mid.chars().all(js::is_space))
}
/// `HT.isUnknownText(s)`(1449줄 — 칸 절에 있으나 날짜 칸과 함께 쓰여 여기 둔다) — `/^(미정|불명|모름|\?|unknown|tbd)$/i`.
pub fn is_unknown_text(v: &V) -> bool {
    let t = text_of(v);
    let Some(s) = t.exact() else { return false };
    matches!(s, "미정" | "불명" | "모름" | "?") || s.eq_ignore_ascii_case("unknown") || s.eq_ignore_ascii_case("tbd")
}

/// `ID_RE.test(s)` — `/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/`.
pub fn id_ok(s: &Str) -> bool {
    let Some(t) = s.exact() else { return false };
    let b = t.as_bytes();
    !b.is_empty() && b.len() <= 64 && b[0].is_ascii_alphanumeric() && b[1..].iter().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'.' | b'-'))
}
/// `str(v)` — `v == null ? '' : String(v).trim()`.
pub fn str_of(v: &V) -> Str { if v.is_nullish() { Str::default() } else { js::to_str(v).trim() } }
/// `arr(v)` — 배열이면 그 원소들(그때의 사본), 아니면 빈 목록.
pub fn arr(v: &V) -> Vec<V> { if let V::Arr(a) = v { a.to_vec() } else { Vec::new() } }
/// `toYear(v)` — `v === '' || v == null ? null : HT.parseYear(v)`.
pub fn to_year(ctx: &Ctx, v: &V) -> Option<f64> { if v.is_nullish() || super::is_empty_str(v) { None } else { Some(parse_year(ctx, v)) } }
/// `dateIn(x, key)` — 날짜 칸 → { t, at }(빈 값 null, 못 읽으면 t: NaN).
pub fn date_in(ctx: &Ctx, x: &V, key: &str) -> Option<DateR> {
    if !js::truthy(x) { return None; }
    read_date(ctx, &x.get(key), &x.get(&format!("{key}At")))
}

/// `PATCHABLE`(5c) — 패치로 바꿀 수 있는 칸(DLC 읽기와 작업본의 패치 만들기가 함께 봄). 3342줄의 목록에 3343 ~ 3358줄이 차례로 더한 것
/// (날짜 칸 `HT.DATE_KEYS`의 값 · 날짜 글 짝 칸 가운데 없던 것은 3344줄이 `birth` · `birthAt` · `death` · `deathAt` 차례로 더함).
pub const PATCHABLE: [&str; 77] = [
    "track", "title", "name", "start", "startAt", "end", "endAt", "startRangeAt", "endRangeAt", "ongoing", "startUnknown", "endUnknown", "category", "importance", "date",
    "description", "tags", "source", "certainty", "startRange", "endRange", "alternatives", "debate", "color", "polity", "parent", "polities", "tracks", "perspectives", "reigns",
    "eras", "leaders", "cabinets", "people", "succeeds", "kind", "partOf", "wiki", "host", "successors", "note", "scale", "house", "capitals",
    "aka", "role", "service", "figures",
    "birth", "birthAt", "death", "deathAt",
    "phases", "ranks", "treaty", "historicity", "historicityNote",
    "theme", "law", "election", "type", "within", "from", "power", "members", "event", "family", "spans",
    "names", "place", "parents", "spouses", "spot", "lineageOnly", "order", "northSouth",
    "faiths", // 종교(리메이크 6단계 D8 — 지위 변천처럼 패치에서도 다시 정리)
];
/// `PATCHABLE.includes(k)`.
pub fn patchable(k: &str) -> bool { PATCHABLE.contains(&k) }

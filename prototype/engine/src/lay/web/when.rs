//! 날짜 글 — 원본 줄 그대로:
//! - `js/calendar.js` — SHA-256 앞 12자 `422dff41a313`: 457줄 `yearText` · 468줄 `clock` · 470 ~ 483줄 `cal.formatT` → [`format_t`] · 484 ~ 496줄 `cal.describe` → [`describe`]
//!   (정규식 `/^(기원전 )?\d+년 /` → `^(기원전 )?[0-9]+년 ` — `withCivil`은 늘 참: 부르는 곳이 선택을 주지 않음)
//! - `js/core.js` — `9c786cf58566`: 3249 ~ 3255줄 `HT.formatDate` → [`format_date`] · 3268 ~ 3286줄 `HT.formatWhen` · `HT.formatRange` · `HT.figureRange` ·
//!   1666 ~ 1680줄 `HT.altWhen`(인물이 아닌 갈래) · `HT.altText` → [`alt_text`](`HT.altSpan`은 [`super::alts`] · `HT.formatYear`는 `read::dates`)
//!
//! 모은 판(과제 Y): 갈래 C의 `docs/when.rs`(docs가 하위 모듈로 · metro가 `#[path]`로 같은 파일을 한 번 더 실어 두 벌로 컴파일되던 것)를 여기 하나로.
//! 버린 판과의 차이:
//! - `model::util::format_range`(과제 6): 맞는 날짜 글이 있으면 `cal.describe` 대신 '옮기지 않은 갈래'로 거절했고 인물(`HT.figureRange`)도 거절했다 — 이제 모델의
//!   지도 장면 알림('그해에 없던 나라')도 이 [`format_range`]를 부른다(정답지 자료는 그 거절에 닿지 않았다 — 과제 6 '알려진 거절' ① · ④가 걷힘).
//! - 갈래 D(`entities/web.rs`)의 판: 몸이 같고 `describe`가 모르는 달력에서 'undefined'를 적었다(C는 '') — 둘 다 JS의 TypeError(`c.name`)와 다른 길이라 그 길은
//!   이제 잘못([`crate::lay::model::util::fault`] — 모듈 틀이 그 모듈의 오류로)으로 둔다. 같은 해 줄임은 D가 손으로, C가 정규식으로 했다(같은 뜻).
//! - 갈래 B(`events`)의 `formatT` · `yearText` · `clock`: 몸이 같다(`clock`이 분을 `f64`로 받았을 뿐).
//! - `HT.formatYear`(`format_date`가 부름): C는 해를 수로 바꿔 `read::dates::format_year`(수만 받던 판)에 넘겼다 — 글로 온 해에서 JS(`y + 1e-9`가 글 잇기)와 갈렸다.
//!   이제 JS 값 그대로 받는 하나(`read::dates::format_year`)에 그대로 넘긴다(모델의 해는 늘 수라 정답지에서는 같음).
use crate::lay::cal;
use crate::lay::js::{self, V};
use crate::lay::model::util::{alt_dated, fault};
use crate::lay::read::{dates, Ctx as RCtx};
use regex::Regex;
use serde_json::Value;
use std::sync::OnceLock;

/// 464줄 `/^(기원전 )?\d+년 /` — 같은 해면 서력 글의 해를 줄인다.
fn re_civ_year() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"^(기원전 )?[0-9]+년 ").expect("describe 정규식"))
}

/// 428줄 `yearText(y)` — "기원전 108년" · "1592년".
fn year_text(y: f64) -> String { if y < 0.0 { format!("기원전 {}년", js::num_str(-y)) } else { format!("{}년", js::num_str(y)) } }
/// 439줄 `clock(h, mi)` — "13시" · "13시 5분"(분이 거짓(없음 · 0 · NaN)이면 시만).
fn clock(h: f64, mi: Option<f64>) -> String {
    match mi { Some(m) if m != 0.0 && !m.is_nan() => format!("{}시 {}분", js::num_str(h), js::num_str(m)), _ => format!("{}시", js::num_str(h)) }
}
/// 441 ~ 454줄 `cal.formatT(t, prec)` — 해 좌표 → 서력 날짜 글(prec: 'y' · 'm' · 'd' · 'x' · 'h' · 'min' — 그 밖은 'h'처럼 시까지).
/// 시는 `Math.min(23, …)`으로 자른다 — 자정 직전(분이 1440으로 반올림)에도 "24시"가 되지 않는다(분은 `mins - h * 60` = 60).
pub fn format_t(t: f64, prec: &str) -> String {
    if !t.is_finite() { return String::new(); }
    let a = cal::at(t);
    if prec == "y" { return year_text(a.y); }
    let mut s = format!("{} {}월", year_text(a.y), js::num_str(a.m));
    if prec == "m" { return s; }
    s += &format!(" {}일", js::num_str(a.d));
    if prec == "d" || prec == "x" { return s; }
    let mins = js::round(a.frac * 1440.0);
    let h = js::min(&[23.0, (mins / 60.0).floor()]);
    let mi = if prec == "min" { mins - h * 60.0 } else { 0.0 };
    format!("{s} {}", clock(h, Some(mi)))
}
/// 455 ~ 467줄 `cal.describe(r)` — 읽은 날짜 → 사람이 읽는 글(다른 달력이면 "음력 1592년 4월 13일 (양력 5월 23일)"처럼 서력을 곁들임).
/// 달력 표에 없는 달력(`CAL.get(r.cal)`이 undefined)은 JS라면 `c.name`에서 TypeError — 잘못을 남긴다(읽기가 만든 결과는 늘 아는 달력이라 닿지 않음).
pub fn describe(r: &cal::Parsed) -> String {
    if !r.ok { return String::new(); }
    if r.prec == "x" { return format_t(r.t, "d"); }
    if r.span.is_some() { return r.text.as_str().into_owned(); } // 세기로 적은 연대는 적은 대로 ("3세기 중반")
    let mut own = String::new();
    if r.cal != "civil" {
        match cal::cal_of(r.cal) {
            Some(c) => own = format!("{} ", c.name),
            None => { fault(format!("cal.describe: 모르는 달력 '{}'(JS라면 c.name에서 TypeError)", r.cal)); return String::new(); }
        }
    }
    own += &year_text(r.y);
    if let Some(m) = r.m { own += &format!(" {}{}월", if r.leap { "윤" } else { "" }, js::num_str(m)); }
    if let Some(d) = r.d { own += &format!(" {}일", js::num_str(d)); }
    if let Some(h) = r.h { own += &format!(" {}", clock(h, r.mi)); }
    if r.cal == "civil" { return own; }
    let coarse = r.prec == "y" || r.prec == "m";
    let mut civ = format_t(r.t, if coarse { "d" } else { r.prec });
    if cal::at(r.t).y == r.y { civ = re_civ_year().replace(&civ, "").into_owned(); } // 같은 해면 해를 줄여서
    format!("{own} (양력 {civ}{})", if coarse { "부터" } else { "" })
}

/// 3249 ~ 3255줄 `HT.formatDate(t, at)` — 날짜 글이 값과 맞으면 그 글을 읽어 [`describe`], 아니면 `HT.formatYear(t)`.
pub fn format_date(rc: &RCtx, t: &V, at: &V) -> String {
    if js::truthy(at) && dates::at_fits(rc, at, t) {
        if let Some(r) = cal::parse(&rc.cal, at) { if r.ok { return describe(&r); } }
    }
    dates::format_year(t)
}
/// 3268줄 `HT.formatWhen(x, key)` — 항목 한쪽 끝의 날짜.
pub fn format_when(rc: &RCtx, x: &V, key: &str) -> String { format_date(rc, &x.get(key), &x.get(&format!("{key}At"))) }
/// 3269 ~ 3276줄 `HT.formatRange(item)` — "시작 ~ 끝" · 진행 중 "~ 현재" · 미정 "~ 미정" · 인물은 [`figure_range`].
pub fn format_range(rc: &RCtx, item: &V) -> String {
    if matches!(item.get("kind"), V::Str(k) if k == "figure") { return figure_range(rc, item); }
    let s = if item.bool("startUnknown") { "미정".to_string() } else { format_when(rc, item, "start") };
    if item.bool("ongoing") { return format!("{s} ~ 현재"); }
    if item.bool("endUnknown") { return format!("{s} ~ 미정"); }
    if item.get("end").is_nullish() || js::strict_eq(&item.get("end"), &item.get("start")) { return s; }
    format!("{s} ~ {}", format_when(rc, item, "end"))
}
/// 3279 ~ 3286줄 `HT.figureRange(f)` — 모델의 인물: 활동 시기(짐작한 끝 `endY`까지).
pub fn figure_range(rc: &RCtx, f: &V) -> String {
    let s = if f.bool("startUnknown") { "미정".to_string() } else { format_date(rc, &f.get("start"), &f.get("startAt")) };
    if f.bool("ongoing") { return format!("{s} ~ 현재"); }
    if f.bool("endUnknown") { return format!("{s} ~ 미정"); }
    if f.get("endY").is_nullish() || js::strict_eq(&f.get("endY"), &f.get("start")) { return s; }
    format!("{s} ~ {}", format_date(rc, &f.get("endY"), &f.get("endYAt")))
}
/// 1666 ~ 1680줄 `HT.altText(a, base)`(인물이 아닌 갈래 — `HT.altWhen`의 `formatRange(HT.altSpan(a, base))`) — "350년 ~ 412년: 근거" · 날짜가 없는 견해는 `a.label` 그대로.
pub fn alt_text(rc: &RCtx, a: &V, base: &V) -> V {
    let when = if alt_dated(a) { format_range(rc, &V::Obj(super::alts::alt_span(a, base, &super::alts::KEYS))) } else { String::new() };
    if when.is_empty() { a.get("label") } else { V::from(format!("{when}: {}", js::to_str(&a.get("label")))) }
}

/// 벡터 검사(`tests/lay_wiki.rs`)의 다리 — 이 파일의 정규식 id.
pub const PROBES: [&str; 1] = ["describe.year"];
/// 정규식 하나를 원본이 쓰는 꼴(바꿔 넣은 글)로. 모르는 id면 None.
pub fn probe(id: &str, text: &str) -> Option<Value> {
    match id { "describe.year" => Some(Value::from(re_civ_year().replace(text, "").into_owned())), _ => None }
}

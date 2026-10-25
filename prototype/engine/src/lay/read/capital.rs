//! `js/core.js` 461 ~ 594줄 가운데 읽기가 쓰는 것 — 도읍 칸 읽기 · 지도자 대수 매기기 — 한 벌 P3 과제 5b.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 461 ~ 502줄 `HT.normalizeCapital`(도읍 역할 낱말 `HT.capitalRole`은 `read::vocab`)
//! - 578 ~ 594줄 `HT.numberLeaders`
//! - (2026-10-24 맞춤 · 리메이크 6단계 걸음 2 · `core.js` `b2e6b19490bf`) 623 ~ 646줄 `HT.LEADER_WORDS`의 열쇠(`LEADER_WORD_KEYS`) · `HT.readLeaderLabels`(지도자 표기 낱말 — D3) · `HT.readRegnal`(이름 번호 — D2) ·
//!   666 ~ 682줄 `HT.numberLeaders`(이름 번호를 적은 줄은 빈 대수를 매기지 않음 — 아래 옛 줄 번호는 그 앞 판의 것)
//!
//! 옮기지 않은 것(모델 · 화면 — 쓰는 과제가 옮김): `HT.resolveCapitals` · `HT.LEADER_LABELS` · `HT.leaderLabel` · `HT.leaderFull` · `HT.CELL_KINDS` · `HT.cellKind` · `HT.cellsOf`.
//! 6단계 걸음 2의 화면 도우미(`HT.leaderFacts` · `HT.leaderWords` · `HT.leaderModes` · `HT.useLeaderLabels` — 내보내기가 부르지 않음)도 옮기지 않았다(기본 표기 `HT.leaderLabel`은 `model::util`).
use super::cells::{self, Edge, Warn};
use super::{dates, vocab, Ctx};
use crate::lay::js::{self, Obj, V};

/// 날짜 칸의 날짜 글(없으면 null — `HT.endBound`의 둘째 값).
fn at_v(d: &dates::DateR) -> V { d.at.clone().map_or(V::Null, V::Str) }

/// `HT.normalizeCapital(raw, warn)` — 도읍 항목 하나를 깨끗한 꼴로: `[도시, 시작, 끝, 역할|메모]` · `{ city(또는 name), start, end, role(한국어도), as, label, group, event, note }`.
/// 도시나 시작이 없으면 None. 시작 · 끝에 "미정"도 된다(칸의 미정 — `HT.readCellEdge`). 확실성 · 연대 폭 · 이설도 다른 칸과 같은 읽기(`HT.readUncertain` — warn을 주면 뺀 것을 알림).
pub fn normalize_capital(ctx: &Ctx, raw: &V, mut warn: Warn<'_>) -> Option<Obj> {
    let c = match raw {
        V::Arr(a) => {
            let o = Obj::new();
            o.set("city", a.get(0));
            o.set("start", a.get(1));
            o.set("end", a.get(2));
            o.set("extra", a.get(3));
            V::Obj(o)
        }
        v if js::truthy(v) && super::is_object(v) => v.clone(),
        _ => V::Obj(Obj::new()),
    };
    let s = dates::str_of;
    let city = s(&js::nullish(c.get("city"), c.get("name")));
    let sd = cells::read_cell_edge(ctx, &c, "start");
    let sd = sd?;
    if city.is_empty() { return None; }
    if let Edge::Date(d) = &sd { if d.t.is_nan() { return None; } }
    let o = Obj::new();
    o.set("city", city.clone());
    match &sd {
        Edge::Unknown(t) => {
            if let Some(t) = t { o.set("start", *t); }
            o.set("startUnknown", true);
        }
        Edge::Date(d) => {
            o.set("start", d.t);
            if js::truthy(&at_v(d)) { o.set("startAt", at_v(d)); }
        }
    }
    let ed = cells::read_cell_edge(ctx, &c, "end");
    // 시작이 미정이고 그 배치용 연도가 적은 끝보다 뒤면 배치용 연도를 버린다(적은 끝은 사실 — 지위 변천 · 시기 · 섬긴 기록과 같은 규칙)
    if o.bool("startUnknown") && !o.get("start").is_nullish() {
        if let Some(Edge::Date(d)) = &ed {
            if !d.t.is_nan() && dates::end_bound_t(ctx, d.t, &at_v(d)) < o.num("start") { o.delete("start"); }
        }
    }
    let start = if o.get("start").is_nullish() { f64::NEG_INFINITY } else { o.num("start") };
    match &ed {
        Some(Edge::Unknown(t)) => {
            if let Some(t) = t { if *t >= start { o.set("end", *t); } }
            o.set("endUnknown", true);
        }
        Some(Edge::Date(d)) if !d.t.is_nan() && dates::end_bound_t(ctx, d.t, &at_v(d)) >= start => {
            o.set("end", d.t);
            if js::truthy(&at_v(d)) { o.set("endAt", at_v(d)); }
        }
        _ => {}
    }
    let role = { let r = vocab::capital_role(&c.get("role")); if r.is_empty() { vocab::capital_role(&c.get("extra")) } else { r } };
    if !role.is_empty() && role != "main" { o.set("role", role); }
    let as_name = s(&c.get("as"));
    if !as_name.is_empty() && as_name != city { o.set("as", as_name); }
    for k in ["label", "group", "event"] {
        let t = s(&c.get(k));
        if !t.is_empty() { o.set(k, t); }
    }
    let extra = c.get("extra");
    let note = { let n = s(&c.get("note")); if !n.is_empty() { n } else if !extra.is_nullish() && vocab::capital_role(&extra).is_empty() { s(&extra) } else { Default::default() } };
    if !note.is_empty() { o.set("note", note); }
    let has_warn = warn.is_some();
    let mut say = |m: String| { if let Some(w) = warn.as_mut() { w(format!("도읍 \"{city}\" — {m}")); } };
    let unc = cells::read_uncertain(ctx, &c, "cell", if has_warn { Some(&mut say) } else { None }, o.get("start").as_num(), o.get("end").as_num(), None);
    for (k, v) in unc.entries() { o.set(&k, v); }
    Some(o)
}

/// `LEADER_WORD_KEYS`(리메이크 6단계 D3) — 지도자 표기 낱말의 열쇠: 묘호 · 시호 · 이름 자리(`HT.LEADER_WORDS`의 열쇠).
pub const LEADER_WORD_KEYS: [&str; 3] = ["temple", "title", "given"];
/// `HT.readLeaderLabels(v, warn)`(6단계 D3) — 지도자 표기 낱말 `{ temple?, title?, given? }`(빈 칸은 뺌 · 하나도 없으면 None).
/// 객체가 아니거나(배열 포함) 모르는 칸은 알리고 뺀다.
pub fn read_leader_labels(v: &V, warn: &mut dyn FnMut(String)) -> Option<Obj> {
    if v.is_nullish() || super::is_empty_str(v) { return None; }
    if !super::is_plain(v) {
        warn("지도자 표기 낱말(leaderLabels)은 { \"temple\", \"title\", \"given\" } 꼴이어야 해서 무시했습니다.".into());
        return None;
    }
    let o = Obj::new();
    for k in LEADER_WORD_KEYS {
        let s = dates::str_of(&v.get(k));
        if !s.is_empty() { o.set(k, s); }
    }
    let extra: Vec<String> = v.as_obj().map(|x| x.keys()).unwrap_or_default().into_iter()
        .filter(|k| !LEADER_WORD_KEYS.iter().any(|w| k.as_str() == *w))
        .map(|k| format!("\"{k}\"")).collect();
    if !extra.is_empty() { warn(format!("지도자 표기 낱말(leaderLabels)의 {}은(는) 모르는 칸이라 뺐습니다(temple · title · given).", extra.join(" · "))); }
    if o.keys().is_empty() { None } else { Some(o) }
}
/// `HT.readRegnal(v)`(6단계 D2) — 이름 번호: 양의 정수(수 · 수 글) → Some(수), 비었으면 None(null), 그 밖은 Some(NaN)(부르는 곳이 알리고 뺀다).
pub fn read_regnal(v: &V) -> Option<f64> {
    if v.is_nullish() || matches!(v, V::Str(s) if s.trim().is_empty()) { return None; }
    let n = if matches!(v, V::Num(_) | V::Str(_)) { js::to_num(v) } else { f64::NAN };
    Some(if n.is_finite() && n.fract() == 0.0 && n > 0.0 { n } else { f64::NAN })
}
/// `HT.numberLeaders(list)` — 대수가 빠진 지도자에게 앞 지도자에 이어 번호를 매긴다. 대수 미상(ordinalUnknown)인 지도자는 번호 없이 두고,
/// 그 뒤의 빈 대수는 다음 대수를 적은 지도자가 나올 때까지 잇지 않는다(그 칸들도 미상). 목록의 칸(객체)을 그 자리에서 고친다.
/// 이름 번호(regnal)를 하나라도 적은 지도자 줄은 빈 대수를 매기지 않는다(6단계 D2 — 적은 대수는 그대로).
pub fn number_leaders(list: &[V]) {
    let named = list.iter().any(|c| js::truthy(c) && !c.get("regnal").is_nullish());
    let mut n = 0.0;
    let mut lost = false;
    for c in list {
        let Some(o) = c.as_obj() else { continue };
        if o.bool("ordinalUnknown") {
            o.delete("ordinal"); // 파일에 "ordinal": null이 남지 않게
            lost = true;
        } else if !o.get("ordinal").is_nullish() {
            n = o.num("ordinal");
            lost = false;
        } else if named {
            continue;
        } else if lost {
            o.set("ordinalUnknown", true);
        } else {
            n += 1.0;
            o.set("ordinal", n);
        }
    }
}

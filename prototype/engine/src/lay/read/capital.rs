//! `js/core.js` 461 ~ 594줄 가운데 읽기가 쓰는 것 — 도읍 칸 읽기 · 지도자 대수 매기기 — 한 벌 P3 과제 5b.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 461 ~ 502줄 `HT.normalizeCapital`(도읍 역할 낱말 `HT.capitalRole`은 `read::vocab`)
//! - 578 ~ 594줄 `HT.numberLeaders`
//!
//! 옮기지 않은 것(모델 · 화면 — 쓰는 과제가 옮김): `HT.resolveCapitals` · `HT.LEADER_LABELS` · `HT.leaderLabel` · `HT.leaderFull` · `HT.CELL_KINDS` · `HT.cellKind` · `HT.cellsOf`.
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

/// `HT.numberLeaders(list)` — 대수가 빠진 지도자에게 앞 지도자에 이어 번호를 매긴다. 대수 미상(ordinalUnknown)인 지도자는 번호 없이 두고,
/// 그 뒤의 빈 대수는 다음 대수를 적은 지도자가 나올 때까지 잇지 않는다(그 칸들도 미상). 목록의 칸(객체)을 그 자리에서 고친다.
pub fn number_leaders(list: &[V]) {
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
        } else if lost {
            o.set("ordinalUnknown", true);
        } else {
            n += 1.0;
            o.set("ordinal", n);
        }
    }
}

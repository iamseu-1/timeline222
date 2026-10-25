//! 모델이 칸 목록을 다듬는 `HT.*` 함수 — 칸의 미정 자리 · 도읍 · 시기 구분 · 지위 사전과 지위 구간 · 주제 사전 · 갈래 색 · 단체 색.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 509 ~ 555줄 `HT.resolveCapitals`
//! - 971 ~ 1017줄 `HT.cellStartGuess` · `HT.cellStartCap` · `HT.cellsFileForm` · `HT.placeCells`
//! - 1141 ~ 1180줄 `HT.resolvePhases`
//! - 1197 ~ 1210줄 `HT.RANKS` · 1251 ~ 1265줄 `HT.mergeRankDefs` · `HT.findRank` · 1331 ~ 1375줄 `HT.resolveRanks`
//! - 1917 ~ 1926줄 `HT.THEMES` · 1967 ~ 1990줄 `HT.mergeThemes` · `HT.findTheme` · 2007 ~ 2028줄 `HT.familyColors` · 2123 ~ 2159줄 `HT.groupColors`
//!
//! 읽기 함수(`HT.normalizeCapital` · `HT.sortCells` · `HT.readPhases` · `HT.readRanks`)는 `lay::read`의 것을 부른다.
use super::util::{arr, auto_color, cmp_str, copy, eq, index_of, is, lt, n, nn, or, pastel, s, sub, tv, unc_of, at_of, list, le};
use crate::lay::js::{self, Map, Obj, Set, Str, V};
use crate::lay::read::{capital, cells as rcells, vocab, Ctx};

// ── 칸의 미정 ──

/// `HT.cellStartGuess(prev, cap, polityStart)` — 시작이 미정인 칸의 자리: 앞 칸의 적힌 끝 → 앞 칸의 시작과 cap 사이 가운데 → 정권의 시작(cap을 넘지 않는 첫 값).
pub fn cell_start_guess(prev: &V, cap: &V, polity_start: &V) -> V {
    let pe = if tv(prev) && !prev.get("end").is_nullish() && !prev.bool("endAuto") { prev.get("end") } else { V::Null };
    let capn = n(cap);
    let mid = if tv(prev) && prev.get("end").is_nullish() && !prev.get("start").is_nullish() && capn.is_finite() && lt(&prev.get("start"), cap) {
        V::Num(js::round((n(&prev.get("start")) + capn) / 2.0))
    } else { V::Null };
    for v in [pe, mid, polity_start.clone()] {
        if !v.is_nullish() && n(&v).is_finite() && le(&v, cap) { return v; }
    }
    if capn.is_finite() { cap.clone() } else { polity_start.clone() }
}
/// `HT.cellStartCap(c, after, p)` — 시작이 미정인 칸이 넘지 않을 자리: 이 칸의 끝 → 뒤 칸 가운데 자리를 아는 첫 칸의 시작(시작도 미정이면 끝) → 정권의 끝.
pub fn cell_start_cap(c: &V, after: &[V], p: &V) -> V {
    if !c.get("end").is_nullish() { return c.get("end"); }
    let found = after.iter().find(|m| tv(m) && n(&nn(nn(m.get("start"), m.get("end")), V::Num(f64::NAN))).is_finite());
    match found {
        Some(m) => nn(m.get("start"), m.get("end")),
        None => nn(nn(p.get("endY"), p.get("end")), V::Num(f64::INFINITY)),
    }
}
/// `HT.cellsFileForm(list)` — 짐작한 자리(startAuto · endAuto가 붙은 start · end)를 뺀 사본 목록. 짐작한 칸이 없으면 목록 그대로.
pub fn cells_file_form(items: &[V]) -> Vec<V> {
    if !items.iter().any(|c| tv(c) && (c.bool("startAuto") || c.bool("endAuto"))) { return items.to_vec(); }
    items.iter().map(|c| {
        let o = copy(c);
        for k in ["start", "end"] {
            let auto = format!("{k}Auto");
            if !o.bool(&auto) { continue; }
            o.delete(k);
            o.delete(&auto);
        }
        V::Obj(o)
    }).collect()
}
/// `HT.placeCells(list, p)` — 이어지는 칸 목록에서 미정인 쪽의 자리를 잡는다(시작 = `cellStartGuess`, 끝 = 다음 칸의 시작). 미정인 칸이 없으면 목록 그대로(같은 값).
pub fn place_cells(list_v: &V, p: &V) -> V {
    let V::Arr(a) = list_v else { return list_v.clone() };
    let items = a.to_vec();
    if !items.iter().any(|c| tv(c) && (c.bool("startUnknown") || c.bool("endUnknown"))) { return list_v.clone(); }
    let out: Vec<V> = cells_file_form(&items).iter().map(|c| V::Obj(copy(c))).collect();
    for i in 0..out.len() {
        let c = &out[i];
        if !c.bool("startUnknown") || !c.get("start").is_nullish() { continue; }
        let prev = if i > 0 { out[i - 1].clone() } else { V::Undef };
        let cap = cell_start_cap(c, &out[i + 1..], p);
        let start = cell_start_guess(&prev, &cap, &p.get("start"));
        let o = super::util::ob(c);
        o.set("start", start);
        o.set("startAuto", true);
    }
    let sorted = rcells::sort_cells(out);
    for i in 0..sorted.len() {
        let c = &sorted[i];
        if !c.bool("endUnknown") || (!c.get("end").is_nullish() && !c.bool("endAuto")) { continue; }
        let o = super::util::ob(c);
        o.delete("end");
        o.delete("endAuto");
        if let Some(next) = sorted.get(i + 1) {
            if !next.get("start").is_nullish() && lt(&c.get("start"), &next.get("start")) {
                o.set("end", next.get("start"));
                o.set("endAuto", true);
            }
        }
    }
    arr(sorted)
}

// ── 도읍 ──

/// `HT.resolveCapitals(p)` — 모델의 도읍 목록: 깨끗한 꼴로(`HT.normalizeCapital`) · 역할을 채우고 · 끝을 비운 정도 · 공동 · 망명 · 임시는 다음 정도(또는 망명)의 시작까지
/// (없으면 정권 끝) · 배도는 정권 끝까지. 시작이 미정인 칸의 자리도 잡는다(짐작은 startAuto).
pub fn resolve_capitals(rc: &Ctx, p: &V) -> Vec<V> {
    let keep = |c: &V, made: Option<Obj>| -> Option<Obj> {
        let made = made?;
        if let V::Obj(_) = c {
            if tv(&c.get("placeId")) {
                made.set("placeId", c.get("placeId"));
                if tv(&c.get("docName")) { made.set("docName", c.get("docName")); }
            }
        }
        Some(made)
    };
    let mut items: Vec<V> = Vec::new();
    for c in list(&p.get("capitals")) {
        let Some(o) = keep(&c, capital::normalize_capital(rc, &c, None)) else { continue };
        o.set("role", or(o.get("role"), s("main")));
        items.push(V::Obj(o));
    }
    let mut items = rcells::sort_cells(items);
    let is_seat = |c: &V| is(&c.get("role"), "main") || is(&c.get("role"), "exile");
    if items.iter().any(|c| c.get("start").is_nullish()) {
        let mut prev_seat: Option<V> = None;
        for i in 0..items.len() {
            let c = items[i].clone();
            let seat = is_seat(&c);
            if c.get("start").is_nullish() {
                let secondary = is(&c.get("role"), "secondary");
                let cap = if secondary { nn(c.get("end"), V::Num(f64::INFINITY)) } else {
                    let after: Vec<V> = items[i + 1..].iter().filter(|x| is_seat(x)).cloned().collect();
                    cell_start_cap(&c, &after, p)
                };
                let prev = match (&prev_seat, secondary) {
                    (_, true) | (None, _) => V::Null,
                    (Some(ps), false) => if seat { ps.clone() } else { let o = Obj::new(); o.set("start", ps.get("start")); V::Obj(o) },
                };
                let o = super::util::ob(&c);
                o.set("start", cell_start_guess(&prev, &cap, &p.get("start")));
                o.set("startAuto", true);
            }
            if seat { prev_seat = Some(c); }
        }
        js::sort_by(&mut items, |a, b| sub(&a.get("start"), &b.get("start")));
    }
    let seats: Vec<V> = items.iter().filter(|c| is_seat(c)).cloned().collect();
    let last = nn(nn(p.get("endY"), p.get("end")), p.get("start"));
    let last_at = at_of(rc, p, "end");
    items.iter().map(|c| {
        let mut e = c.get("end");
        let mut at = at_of(rc, c, "end");
        let mut next: Option<V> = None;
        if e.is_nullish() {
            if is(&c.get("role"), "secondary") { e = last.clone(); at = last_at.clone(); }
            else {
                next = seats.iter().find(|m| !eq(m, c) && lt(&c.get("start"), &m.get("start"))).cloned();
                match &next { Some(m) => { e = m.get("start"); at = at_of(rc, m, "start"); } None => { e = last.clone(); at = last_at.clone(); } }
            }
        }
        let o = super::util::ob(c);
        o.set("name", or(c.get("as"), c.get("city")));
        o.set("endY", js::max(&[n(&c.get("start")), n(&e)]));
        o.set("endYAt", if le(&c.get("start"), &e) { at } else { at_of(rc, c, "start") });
        if let Some(m) = &next {
            o.set("endYNext", true);
            if m.bool("startAuto") { o.set("endYAuto", true); }
        }
        c.clone()
    }).collect()
}

// ── 시기 구분 ──

/// 시기 경계 하나(`{ t, at }`) — `p1`은 정권의 끝(`P1`)인가(`b === P1`).
#[derive(Clone)]
struct Edge { t: V, at: V, p1: bool }
/// `HT.resolvePhases(p)` — 시기의 빈 경계를 채운 사본 `[{ scheme, note, si, spans }]`(없으면 None).
pub fn resolve_phases(rc: &Ctx, p: &V) -> Option<V> {
    let phases = rcells::read_phases(rc, &if tv(p) { p.get("phases") } else { V::Undef });
    if phases.list.is_empty() { return None; }
    let p0 = Edge { t: p.get("start"), at: at_of(rc, p, "start"), p1: false };
    let p1 = Edge { t: nn(nn(p.get("endY"), p.get("end")), p.get("start")), at: if p.bool("ongoing") { V::Null } else { at_of(rc, p, "end") }, p1: true };
    let own = |sp: &V, k: &str| -> Option<Edge> {
        if tv(sp) && !sp.get(k).is_nullish() { Some(Edge { t: sp.get(k), at: or(sp.get(&format!("{k}At")), V::Null), p1: false }) } else { None }
    };
    let mut ci = 0.0;
    let mut out = Vec::new();
    for (si, g) in phases.list.iter().enumerate() {
        let spans_in = list(&g.get("spans"));
        let len = spans_in.len();
        let mut st: Vec<Option<Edge>> = (0..len).map(|i| own(&spans_in[i], "start").or_else(|| if i == 0 { Some(p0.clone()) } else { own(&spans_in[i - 1], "end") })).collect();
        let mut en: Vec<Option<Edge>> = (0..len).map(|i| own(&spans_in[i], "end").or_else(|| if i == len - 1 { Some(p1.clone()) } else { own(&spans_in[i + 1], "start") })).collect();
        let mut guess: Vec<usize> = Vec::new();
        let mut i = 1;
        while i < len {
            if st[i].is_some() { i += 1; continue; }
            let mut j = i;
            while j + 1 < len && st[j + 1].is_none() { j += 1; }
            let l = n(&st[i - 1].as_ref().expect("앞 시기의 시작").t);
            let r = js::max(&[l, n(&en[j].as_ref().expect("뒤 경계").t)]);
            for m in i..=j {
                let t = l + ((r - l) * (m - i + 1) as f64) / (j - i + 2) as f64;
                let e = Edge { t: V::Num(t), at: V::Null, p1: false };
                st[m] = Some(e.clone());
                en[m - 1] = Some(e);
                guess.push(m - 1);
                guess.push(m);
            }
            i = j + 1;
        }
        let spans: Vec<V> = spans_in.iter().enumerate().map(|(i, sp)| {
            let a = st[i].clone().expect("시작");
            let e = en[i].clone().expect("끝");
            let b = if lt(&e.t, &a.t) { a.clone() } else { e };
            let scheme = or(g.get("scheme"), s(""));
            let o = Obj::new();
            o.set("name", sp.get("name"));
            o.set("note", or(sp.get("note"), s("")));
            o.set("scheme", scheme.clone());
            o.set("si", si as f64);
            o.set("ii", i as f64);
            o.set("ci", ci);
            ci += 1.0;
            o.set("start", a.t.clone());
            o.set("startAt", or(a.at.clone(), V::Undef));
            o.set("end", b.t.clone());
            o.set("endAt", or(b.at.clone(), V::Undef));
            o.set("startAuto", sp.get("start").is_nullish());
            o.set("endAuto", sp.get("end").is_nullish());
            o.set("startUnknown", sp.bool("startUnknown"));
            o.set("endUnknown", sp.bool("endUnknown"));
            o.set("guess", guess.contains(&i));
            o.set("endPolity", sp.get("end").is_nullish() && b.p1);
            o.set("docName", if tv(&g.get("scheme")) { V::from(format!("{} · {}", super::util::t(&g.get("scheme")), super::util::t(&sp.get("name")))) } else { sp.get("name") });
            for (k, v) in unc_of(sp).entries() { o.set(&k, v); }
            V::Obj(o)
        }).collect();
        let o = Obj::new();
        o.set("scheme", or(g.get("scheme"), s("")));
        o.set("note", or(g.get("note"), s("")));
        o.set("si", si as f64);
        o.set("spans", arr(spans));
        out.push(V::Obj(o));
    }
    Some(arr(out))
}

// ── 지위 ──

/// `HT.RANKS` — 내장 지위 사전(id · 이름 · 서열 · 별칭).
const RANKS: [(&str, &str, Option<f64>, &[&str]); 12] = [
    ("emperor", "황제", Some(8.0), &[]), ("king", "왕", Some(7.0), &["국왕"]), ("grand-duke", "대공", Some(6.0), &[]), ("duke", "공", Some(5.0), &["공작"]),
    ("marquis", "후", Some(4.0), &["후작"]), ("count", "백", Some(3.0), &["백작"]), ("viscount", "자", Some(2.0), &["자작"]), ("baron", "남", Some(1.0), &["남작"]),
    ("president", "대통령", None, &[]), ("premier", "총리", None, &[]), ("chairman", "주석", None, &[]), ("regent", "섭정", None, &[]),
];
/// `HT.mergeRankDefs(packs)` — 켠 DLC들의 사전(먼저 정의가 이김 · id로만 합침) → 맨 끝에 내장 사전이 빈 자리만. 항목마다 짙기 단계(level).
pub fn merge_rank_defs(packs: &[V]) -> Vec<V> {
    let by_id = Map::new();
    for pack in packs {
        let defs = if tv(pack) { pack.get("rankDefs") } else { V::Undef };
        for d in list(&defs) {
            if tv(&d) && tv(&d.get("id")) && !by_id.has(&d.get("id")) {
                let o = copy(&d);
                o.set("packId", pack.get("id"));
                by_id.set(d.get("id"), o);
            }
        }
    }
    for (id, name, tier, aliases) in RANKS {
        if by_id.has(&s(id)) { continue; }
        let o = Obj::new();
        o.set("id", id);
        o.set("name", name);
        if let Some(tier) = tier { o.set("tier", tier); }
        if !aliases.is_empty() { o.set("aliases", arr(aliases.iter().map(|a| s(a)).collect())); }
        o.set("builtin", true);
        by_id.set(s(id), o);
    }
    let items = by_id.values();
    let tier_set = Set::new();
    for d in &items { let t = d.get("tier"); if !t.is_nullish() { tier_set.add(t); } }
    let mut tiers = tier_set.values();
    js::sort(&mut tiers, sub);
    for d in &items {
        let t = d.get("tier");
        let level = if t.is_nullish() { 0.0 } else if tiers.len() < 2 { 4.0 } else { js::round((index_of(&tiers, &t) * 3.0) / (tiers.len() - 1) as f64) + 1.0 };
        super::util::ob(d).set("level", level);
    }
    items
}
/// `HT.findRank(defs, ref)` — id → 이름 → 별칭(없으면 null).
pub fn find_rank(defs: &[V], r: &V) -> V {
    let text = js::to_str(&nn(r.clone(), s(""))).trim();
    if text.is_empty() { return V::Null; }
    let x = V::Str(text);
    defs.iter().find(|d| eq(&d.get("id"), &x))
        .or_else(|| defs.iter().find(|d| eq(&d.get("name"), &x)))
        .or_else(|| defs.iter().find(|d| list(&d.get("aliases")).iter().any(|a| eq(a, &x))))
        .cloned().unwrap_or(V::Null)
}
/// `HT.resolveRanks(p, defs)` — 지위 구간(끝을 채운 사본)과, 지위를 적지 않은 지도자에게 시작한 해의 지위를 채운 지도자 목록 → `(spans, leaders?)`(지위가 없으면 None).
pub fn resolve_ranks(rc: &Ctx, p: &V, defs: &[V]) -> Option<(Vec<V>, Option<Vec<V>>)> {
    if !tv(p) { return None; }
    let mut raw: Vec<V> = rcells::read_ranks(rc, &p.get("ranks")).list;
    let derived = raw.is_empty();
    if derived {
        let mut by_start: Vec<V> = list(&p.get("leaders")).into_iter().filter(|c| tv(c) && !c.get("start").is_nullish() && n(&c.get("start")).is_finite()).collect();
        js::sort(&mut by_start, |a, b| sub(&a.get("start"), &b.get("start")));
        raw = Vec::new();
        for c in &by_start {
            let r = js::to_str(&nn(c.get("rank"), s(""))).trim();
            if !r.is_empty() && (raw.is_empty() || !eq(&raw[raw.len() - 1].get("name"), &V::Str(r.clone()))) {
                let o = Obj::new();
                o.set("name", r);
                o.set("start", c.get("start"));
                o.set("startAt", or(at_of(rc, c, "start"), V::Undef));
                raw.push(V::Obj(o));
            }
        }
    }
    if raw.is_empty() { return None; }
    if !derived && raw.iter().any(|c| c.bool("startUnknown") || c.bool("endUnknown")) {
        let first: Vec<V> = raw.iter().enumerate().map(|(i, c)| {
            if i == 0 && c.get("start").is_nullish() && !c.bool("startUnknown") {
                let o = copy(c);
                o.set("start", p.get("start"));
                o.set("p0", true);
                V::Obj(o)
            } else { c.clone() }
        }).collect();
        raw = list(&place_cells(&arr(first), p));
    }
    let p0 = Edge { t: p.get("start"), at: at_of(rc, p, "start"), p1: false };
    let p1 = Edge { t: nn(nn(p.get("endY"), p.get("end")), p.get("start")), at: if p.bool("ongoing") { V::Null } else { at_of(rc, p, "end") }, p1: true };
    let spans: Vec<V> = raw.iter().enumerate().map(|(i, c)| {
        let next = raw.get(i + 1);
        let a = if !c.get("start").is_nullish() && !c.bool("p0") { Edge { t: c.get("start"), at: or(c.get("startAt"), V::Null), p1: false } } else { p0.clone() };
        let mut b = if !derived && !c.get("end").is_nullish() { Edge { t: c.get("end"), at: or(c.get("endAt"), V::Null), p1: false } }
            else if let Some(nx) = next { Edge { t: nx.get("start"), at: or(nx.get("startAt"), V::Null), p1: false } }
            else { p1.clone() };
        if lt(&b.t, &a.t) { b = a.clone(); }
        let def = find_rank(defs, &c.get("name"));
        let o = Obj::new();
        o.set("name", c.get("name"));
        o.set("note", or(c.get("note"), s("")));
        o.set("i", i as f64);
        o.set("start", a.t.clone());
        o.set("startAt", or(a.at.clone(), V::Undef));
        o.set("end", b.t.clone());
        o.set("endAt", or(b.at.clone(), V::Undef));
        o.set("startAuto", c.get("start").is_nullish() || c.bool("p0") || c.bool("startAuto"));
        o.set("endAuto", derived || c.get("end").is_nullish() || c.bool("endAuto"));
        o.set("derived", derived);
        o.set("endPolity", (derived || c.get("end").is_nullish()) && b.p1);
        o.set("def", def.clone());
        o.set("id", if tv(&def) { def.get("id") } else { s("") });
        o.set("tier", if tv(&def) && !def.get("tier").is_nullish() { def.get("tier") } else { V::Null });
        o.set("level", if tv(&def) { or(def.get("level"), V::Num(0.0)) } else { V::Num(0.0) });
        if c.bool("startUnknown") { o.set("startUnknown", true); }
        if c.bool("endUnknown") { o.set("endUnknown", true); }
        for (k, v) in unc_of(c).entries() { o.set(&k, v); }
        V::Obj(o)
    }).collect();
    let at = |t: &V| -> Option<V> {
        spans.iter().find(|sp| le(&sp.get("start"), t) && lt(t, &sp.get("end"))).or_else(|| spans.iter().find(|sp| le(&sp.get("start"), t) && le(t, &sp.get("end")))).cloned()
    };
    let mut touched = false;
    let leaders: Vec<V> = list(&p.get("leaders")).into_iter().map(|c| {
        if !tv(&c) || tv(&c.get("rank")) || c.get("start").is_nullish() { return c; }
        let Some(sp) = at(&c.get("start")) else { return c };
        touched = true;
        let o = copy(&c);
        o.set("rankAuto", sp.get("name"));
        V::Obj(o)
    }).collect();
    Some((spans, if touched { Some(leaders) } else { None }))
}

// ── 주제 · 갈래 색 · 단체 색 ──

/// `HT.THEMES` — 내장 주제 사전(id · 이름 · 색).
pub const THEMES: [(&str, &str, &str); 8] = [
    ("system", "체제", "#abb3c9"), ("faction", "붕당", "#d4a39b"), ("law", "법률", "#bba395"), ("election", "선거제도", "#a0bcc5"),
    ("ideology", "이념", "#bbacc8"), ("military", "군사제도", "#b6c398"), ("tax", "조세제도", "#d7c18e"), ("selection", "선발제도", "#9dbea8"),
];
/// `HT.mergeThemes(packs)` — 켠 DLC들의 주제 사전(먼저 정의가 이김 · id로만 합침) + 내장 뼈대가 빈 자리만. 차례는 내장 뼈대 → DLC만의 주제. 숨김은 따로 모음.
pub fn merge_themes(packs: &[V]) -> Vec<V> {
    let by_id = Map::new();
    let hidden = Map::new();
    for pack in packs {
        let defs = if tv(pack) { pack.get("themes") } else { V::Undef };
        for d in list(&defs) {
            if !tv(&d) || !tv(&d.get("id")) { continue; }
            if tv(&d.get("hidden")) && !hidden.has(&d.get("id")) { hidden.set(d.get("id"), or(pack.get("name"), pack.get("id"))); }
            if tv(&d.get("name")) && !by_id.has(&d.get("id")) {
                let o = copy(&d);
                o.set("packId", pack.get("id"));
                o.set("packName", pack.get("name"));
                by_id.set(d.get("id"), o);
            }
        }
    }
    let mut out: Vec<V> = THEMES.iter().map(|(id, name, color)| {
        let got = by_id.get(&s(id));
        if tv(&got) { got } else {
            let o = Obj::new();
            o.set("id", *id);
            o.set("name", *name);
            o.set("color", *color);
            o.set("builtin", true);
            V::Obj(o)
        }
    }).collect();
    for d in by_id.values() { if !THEMES.iter().any(|(id, _, _)| is(&d.get("id"), id)) { out.push(d); } }
    for d in &out {
        let o = super::util::ob(d);
        o.delete("hidden");
        if hidden.has(&d.get("id")) {
            o.set("hidden", true);
            o.set("hiddenBy", hidden.get(&d.get("id")));
        }
    }
    out
}
/// `HT.findTheme(defs, ref)` — id → 이름 → 내장 뼈대의 이름(같은 id로 덮어 이름을 바꾼 주제도 내장 이름으로 가리킬 수 있게). 없으면 None.
pub fn find_theme(defs: &[V], r: &V) -> Option<V> {
    let text = js::to_str(&nn(r.clone(), s(""))).trim();
    if text.is_empty() { return None; }
    let x = V::Str(text.clone());
    let builtin = THEMES.iter().find(|(_, name, _)| text == *name);
    defs.iter().find(|d| eq(&d.get("id"), &x))
        .or_else(|| defs.iter().find(|d| eq(&d.get("name"), &x)))
        .or_else(|| builtin.and_then(|(id, _, _)| defs.iter().find(|d| is(&d.get("id"), id))))
        .cloned()
}
/// `HT.familyColors(list)` — 같은 주제의 갈래를 이름 차례로 놓고, 해시로 고른 팔레트 자리가 앞 갈래에 쓰였으면 다음 자리로 — 제도의 color를 고쳐 쓴다.
pub fn family_colors(items: &[V]) {
    let pal = vocab::PALETTE;
    let by_theme = Map::new();
    for o in items {
        if !tv(o) || !tv(&o.get("familyKey")) { continue; }
        let key = js::to_str(&o.get("familyKey"));
        let bar = key.index_of16(&Str::from("|"), 0.0);
        let tname = key.slice16(0.0, bar);
        let tv_ = V::Str(tname.clone());
        if !by_theme.has(&tv_) { by_theme.set(tv_.clone(), Set::new()); }
        if let V::Set(set) = by_theme.get(&tv_) { set.add(key.slice16((tname.len16() + 1) as f64, f64::INFINITY)); }
    }
    let out = Map::new();
    for (tk, fams) in by_theme.entries() {
        let V::Set(fams) = fams else { continue };
        let used = Set::new();
        let mut names = fams.values();
        js::sort(&mut names, cmp_str);
        for f in names {
            let key = format!("{}|{}", super::util::t(&tk), super::util::t(&f));
            let color = auto_color(&V::from(format!("family:{key}")));
            let mut k = pal.iter().position(|c| is(&color, c)).map_or(-1.0, |i| i as f64);
            let mut step = 0;
            while step < pal.len() && used.has(&V::Num(k)) { k = (k + 1.0) % pal.len() as f64; step += 1; }
            used.add(V::Num(k));
            out.set(V::from(key), pastel(&s(pal[k as usize])));
        }
    }
    for o in items {
        if tv(o) && tv(&o.get("familyKey")) && out.has(&o.get("familyKey")) { super::util::ob(o).set("color", out.get(&o.get("familyKey"))); }
    }
}
/// `HT.groupColors(groups)` — 나라마다 그 나라에 있던 단체를 이름 차례로 놓고, 적은 색이 먼저 자리를 차지한 뒤 자동 색이 겹치면 다음 자리로.
/// 같은 나라에서 같은 때 함께 집권한 단체의 색이 그래도 같으면 뒤 단체에 경고.
pub fn group_colors(groups_list: &[V]) {
    let pal = vocab::PALETTE;
    let pal_p: Vec<V> = pal.iter().map(|c| pastel(&s(c))).collect();
    let by_polity = Map::new();
    for g in groups_list {
        for w in list(&g.get("withinList")) {
            if !tv(&w.get("polityUid")) || is(&g.get("type"), "coalition") { continue; }
            if !by_polity.has(&w.get("polityUid")) { by_polity.set(w.get("polityUid"), Set::new()); }
            if let V::Set(set) = by_polity.get(&w.get("polityUid")) { set.add(g.clone()); }
        }
    }
    let key = |g: &V| V::Str(js::to_str(&or(g.get("name"), s(""))));
    let done = Set::new();
    for set in by_polity.values() {
        let V::Set(set) = set else { continue };
        let mut items = set.values();
        js::sort(&mut items, |a, b| {
            let (ka, kb) = (key(a), key(b));
            if lt(&ka, &kb) { -1.0 } else if lt(&kb, &ka) { 1.0 } else if lt(&a.get("uid"), &b.get("uid")) { -1.0 } else if lt(&b.get("uid"), &a.get("uid")) { 1.0 } else { 0.0 }
        });
        let used = Set::new();
        for g in &items { if !g.bool("colorAuto") || done.has(g) { used.add(V::Num(index_of(&pal_p, &g.get("color")))); } }
        for g in &items {
            if !g.bool("colorAuto") || done.has(g) { continue; }
            let color = auto_color(&V::from(format!("group:{}", super::util::t(&g.get("uid")))));
            let mut k = pal.iter().position(|c| is(&color, c)).map_or(-1.0, |i| i as f64);
            let mut step = 0;
            while step < pal.len() && used.has(&V::Num(k)) { k = (k + 1.0) % pal.len() as f64; step += 1; }
            used.add(V::Num(k));
            super::util::ob(g).set("color", pal_p[k as usize].clone());
            done.add(g.clone());
        }
        // 함께 집권한 단체(같은 때 집권 칸)의 색이 같음
        let mut spans: Vec<(V, V, V)> = Vec::new();
        for g in &items {
            for c in list(&g.get("powerSpans")) { if lt(&c.get("start"), &c.get("end")) { spans.push((g.clone(), c.get("start"), c.get("end"))); } }
        }
        let warned = Set::new();
        for i in 0..spans.len() {
            for j in 0..spans.len() {
                let (a, a0, a1) = &spans[i];
                let (b, b0, b1) = &spans[j];
                if eq(a, b) || !eq(&a.get("color"), &b.get("color")) || !(lt(a0, b1) && lt(b0, a1)) || lt(&key(b), &key(a)) || warned.has(b) { continue; }
                warned.add(b.clone());
                let bo = super::util::ob(b);
                let mut w = bo.get("warnings");
                if !tv(&w) { w = arr(Vec::new()); bo.set("warnings", w.clone()); }
                if let V::Arr(wl) = w {
                    wl.push(format!("같은 나라에서 같은 때 함께 집권한 단체 \"{}\"와(과) 색이 같아 띠에서 갈리지 않습니다 — 둘 중 하나의 색을 바꿔 주세요.", super::util::t(&a.get("name"))));
                }
            }
        }
    }
}

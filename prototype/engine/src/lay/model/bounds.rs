//! 칸의 경계 — 이웃 칸끼리 상호배타(경계 해는 뒤 칸의 것). `HT.buildModel`이 맨 끝에 정권마다 `p.cellBounds`(열거되지 않는 속성 — `Obj::define_hidden`)로 둔다.
//! 칸 조명 · 그 시기의 사건 · 같은 시기의 지도자 · 줄 이름표의 그때 지도자 · 같은 해 보기가 이 값을 본다(`HT.cellSpan`의 lo · hi — 모듈 과제가 옮긴다).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 613 ~ 636줄 `HT.CELL_KINDS`의 목록 열쇠 · `items`(시기 = `p.phaseSchemes`의 칸 · 지위 = `p.rankSpans`) · `HT.cellKind` · `HT.cellsOf` → [`cells_of`]
//! - 640 ~ 650줄 `rawCellSpan` → [`raw_cell_span`]
//! - 692 ~ 708줄 `unitOf` · `unitsMeet` → [`unit_of`] · [`units_meet`](정밀도 구간은 `lay::cal::prec_span`)
//! - 714 ~ 747줄 `HT.chainBounds` → [`chain_bounds`]
//! - 749 ~ 781줄 `HT.cellChains` → [`cell_chains`]
//! - 783 ~ 793줄 `HT.cellBounds` → [`cell_bounds`]
//! - 8824줄(`HT.buildModel`의 끝) `Object.defineProperty(p, 'cellBounds', …)` → `model/parts.rs`
use super::util::{at_of, eq, is, list, lt, n, tv};
use crate::lay::cal;
use crate::lay::js::{self, Arr, Map, V};
use crate::lay::read::{dates, Ctx};

/// 칸 하나만 보고 정한 구간 `{ start, startAt, end, endAt, hi, exact }`(덧붙인 '뒤 칸'은 `virtual`).
#[derive(Clone)]
pub struct Sp { pub start: V, pub start_at: V, pub end: V, pub end_at: V, pub hi: V, pub exact: bool, pub virt: bool }

/// `HT.cellsOf(p, kind)` — 그 정권의 그 종류 칸들(순번이 곧 칸 참조의 번호). 시기 · 지위는 모델 전용 목록(`items`).
pub fn cells_of(p: &V, kind: &str) -> Vec<V> {
    if !tv(p) { return Vec::new(); }
    let l = match kind {
        "leader" | "leaders" => p.get("leaders"),
        "cabinet" | "cabinets" => p.get("cabinets"),
        "era" | "eras" => p.get("eras"),
        "capital" | "capitals" => p.get("capitals"),
        "phase" | "phases" => {
            let ps = p.get("phaseSchemes");
            if tv(&ps) { V::Arr(Arr::new(list(&ps).iter().flat_map(|g| list(&g.get("spans"))).collect())) } else { V::Arr(Arr::default()) }
        }
        "rank" | "ranks" => js::or(p.get("rankSpans"), V::Arr(Arr::default())),
        _ => V::Null,
    };
    list(&l)
}
/// `rawCellSpan(c, p)` — 칸 하나만 보고 정한 구간. hi = 그 칸이 품는 마지막 순간(연도만 적은 끝은 그해 끝까지 — 다음 칸의 시작에서 끌어낸 끝은 그 순간 그대로: exact).
pub fn raw_cell_span(rc: &Ctx, c: &V, p: &V) -> Sp {
    let (end, end_at) = if !c.get("end").is_nullish() { (c.get("end"), c.get("endAt")) }
        else if !c.get("endY").is_nullish() { (c.get("endY"), c.get("endYAt")) }
        else { (p.get("endY"), at_of(rc, p, "end")) };
    let exact = (c.get("end").is_nullish() && tv(&c.get("endYNext"))) || (tv(&c.get("endAuto")) && !tv(&c.get("endPolity")));
    let hi = if exact { end.clone() } else { dates::end_bound(rc, &end, &end_at) };
    Sp { start: c.get("start"), start_at: c.get("startAt"), end, end_at, hi, exact, virt: false }
}
/// `unitOf(t, at, exact)` — 적힌 값이 덮는 단위 [처음, 끝): 날짜 글이 값과 맞으면 그 자세함, 없으면 정수는 그해, 소수는 그 한 점. exact면 한 점.
pub fn unit_of(rc: &Ctx, t: &V, at: &V, exact: bool) -> Option<(f64, f64)> {
    if t.is_nullish() || !n(t).is_finite() { return None; }
    let tn = n(t);
    if exact { return Some((tn, tn)); }
    let input = if tv(at) && dates::at_fits(rc, at, t) { at.clone() } else { t.clone() };
    let r = cal::parse(&rc.cal, &input);
    let sp = r.as_ref().and_then(|r| cal::prec_span(&rc.cal, r));
    match sp { Some((a, b)) if b > a => Some((a, b)), _ => Some((tn, tn)) }
}
/// `unitsMeet(U, V)` — 두 단위가 겹치는가(한 점 단위는 닫힌 한 점).
pub fn units_meet(u: (f64, f64), v: (f64, f64)) -> bool {
    let pu = u.0 == u.1;
    let pv = v.0 == v.1;
    if pu && pv { return u.0 == v.0; }
    if pu { return v.0 <= u.0 && u.0 < v.1; }
    if pv { return u.0 <= v.0 && v.0 < u.1; }
    u.0 < v.1 && v.0 < u.1
}
/// 칸 하나의 경계 `{ lo, hi, prev, next }`(같은 차례의 번호).
#[derive(Clone, Debug)]
pub struct Bound { pub lo: f64, pub hi: f64, pub prev: Vec<usize>, pub next: Vec<usize> }
/// `HT.chainBounds(list)` — 칸 무리 하나의 경계(규칙 ㉠ ~ ㉣ — 원본 주석).
pub fn chain_bounds(rc: &Ctx, items: &[Sp]) -> Vec<Bound> {
    let count = items.len();
    let mut out: Vec<Bound> = items.iter().map(|s| Bound { lo: n(&s.start), hi: js::max(&[n(&s.start), n(&s.hi)]), prev: Vec::new(), next: Vec::new() }).collect();
    let us: Vec<Option<(f64, f64)>> = items.iter().map(|s| if s.virt { None } else { unit_of(rc, &s.end, &s.end_at, s.exact) }).collect();
    let vs: Vec<Option<(f64, f64)>> = items.iter().map(|s| unit_of(rc, &s.start, &s.start_at, false)).collect();
    let mut found: Vec<(usize, usize, f64)> = Vec::new();
    for i in 0..count {
        for j in 0..count {
            let (Some(u), Some(v)) = (us[i], vs[j]) else { continue };
            if i == j { continue; }
            let m = if units_meet(u, v) { js::max(&[u.0, v.0]) }
                else if u.1 > u.0 && u.1 - u.0 < 0.5 && (u.1 - v.0).abs() < 1e-7 { v.0 }
                else { continue };
            if m < n(&items[i].start) || m > out[j].hi { continue; }
            found.push((i, j, m));
        }
    }
    let seen: std::collections::HashSet<usize> = found.iter().map(|(i, j, _)| i * count + j).collect();
    let first = |i: usize, j: usize| { let (a, b) = (n(&items[i].start), n(&items[j].start)); a < b || (a == b && i < j) };
    let pairs: Vec<(usize, usize, f64)> = found.iter().copied().filter(|(i, j, _)| !seen.contains(&(j * count + i)) || first(*i, *j)).collect();
    for &(i, j, m) in &pairs {
        out[j].lo = js::max(&[out[j].lo, m]);
        out[j].prev.push(i);
        out[i].next.push(j);
    }
    let mut cut = vec![f64::INFINITY; count];
    for &(i, j, m) in &pairs { cut[i] = js::min(&[cut[i], out[j].lo, js::max(&[out[i].hi, m])]); }
    for (i, b) in out.iter_mut().enumerate() {
        if cut[i] < f64::INFINITY { b.hi = cut[i]; }
        if b.hi < b.lo { b.hi = b.lo; }
    }
    out
}
/// 무리의 칸 하나 — 칸 참조(덧붙인 '뒤 칸'은 없음) · 끝을 자른 후대 나라(나라 경계의 '뒤 칸'이면).
#[derive(Clone)]
pub struct Item { pub r#ref: Option<String>, pub c: V, pub to: V, pub sp: Sp }
/// `HT.cellChains(p)` — 정권 p의 서로 이어받는 칸 무리: 지도자 · 내각 · 연호는 목록마다, 도읍은 정도 · 망명 · 임시끼리(다시 시작하는 정도를 덧붙임),
/// 시기는 체계마다, 지위는 하나. 후대가 이 나라가 끝나는 단위에 시작하면 그 시작을 무리마다 '뒤 칸'으로 덧붙인다(나라 경계).
pub fn cell_chains(rc: &Ctx, p: &V) -> Vec<Vec<Item>> {
    let mut out: Vec<Vec<Item>> = Vec::new();
    let items = |kind: &str, keep: &dyn Fn(&V) -> bool| -> Vec<Item> {
        cells_of(p, kind).into_iter().enumerate()
            .filter(|(_, c)| tv(c) && !c.get("start").is_nullish() && n(&c.get("start")).is_finite() && keep(c))
            .map(|(i, c)| { let sp = raw_cell_span(rc, &c, p); Item { r#ref: Some(format!("{kind}:{i}")), c, to: V::Undef, sp } })
            .collect()
    };
    let all = |_: &V| true;
    let end_u = if tv(&p.get("endUnknown")) || tv(&p.get("endRange")) || tv(&p.get("ongoing")) { None } else { unit_of(rc, &p.get("endY"), &at_of(rc, p, "end"), false) };
    let seats: Vec<Item> = match end_u {
        None => Vec::new(),
        Some(eu) => list(&js::or(p.get("successors"), V::Arr(Arr::default()))).iter()
            .map(|e| if tv(e) { e.get("to") } else { e.clone() })
            .filter(|q| tv(q) && !eq(q, p) && !tv(&q.get("startUnknown")) && !tv(&q.get("startRange")) && !q.get("start").is_nullish() && n(&q.get("start")).is_finite()
                && unit_of(rc, &q.get("start"), &at_of(rc, q, "start"), false).is_some_and(|v| units_meet(eu, v)))
            .map(|q| Item { r#ref: None, c: V::Null, to: q.clone(), sp: Sp { start: q.get("start"), start_at: at_of(rc, &q, "start"), end: q.get("start"), end_at: V::Undef, hi: q.get("start"), exact: false, virt: true } })
            .collect(),
    };
    let mut push = |g: Vec<Item>| {
        if g.len() > 1 || (!g.is_empty() && !seats.is_empty()) {
            let mut g = g;
            if !seats.is_empty() { g.extend(seats.iter().cloned()); }
            out.push(g);
        }
    };
    for k in ["leader", "cabinet", "era"] { push(items(k, &all)); }
    // 도읍: 정도 · 망명 · 임시끼리. 임시 도읍의 끝에서 정도가 다시 이어지면 그 자리에 '다시 시작하는 정도'를 덧붙인다(참조 없음)
    let role_of = |c: &V| js::or(c.get("role"), V::from("main"));
    let mut caps = items("capital", &|c: &V| { let r = role_of(c); is(&r, "main") || is(&r, "exile") || is(&r, "temporary") });
    // caps.filter(...)는 덧붙이기 전의 사본 · caps.find(...)는 덧붙인 것까지 본다(x !== t — 같은 자리인가로)
    let temps: Vec<usize> = (0..caps.len()).filter(|&i| is(&caps[i].c.get("role"), "temporary") && !caps[i].sp.exact).collect();
    for ti in temps {
        let e = caps[ti].sp.end.clone();
        let tmp_end_at = caps[ti].sp.end_at.clone();
        let seat = caps.iter().enumerate().find(|(i, x)| *i != ti && !is(&x.c.get("role"), "temporary") && lt(&x.c.get("start"), &e) && lt(&e, &x.sp.end)).map(|(_, x)| x.clone());
        if let Some(seat) = seat {
            let mut sp = seat.sp.clone();
            sp.start = e;
            sp.start_at = tmp_end_at;
            sp.virt = true;
            caps.push(Item { r#ref: None, c: seat.c.clone(), to: V::Undef, sp });
        }
    }
    push(caps);
    let phases = items("phase", &all);
    let mut sis: Vec<V> = Vec::new();
    for x in &phases { let si = x.c.get("si"); if !sis.iter().any(|y| eq(y, &si)) { sis.push(si); } }
    for si in sis { push(phases.iter().filter(|x| eq(&x.c.get("si"), &si)).cloned().collect()); }
    push(items("rank", &all));
    out
}
/// `HT.cellBounds(p)` — Map(칸 참조 → { lo, hi, prev: [칸 참조], next: [칸 참조], succ: [끝을 자른 후대 정권] }). 이어받는 칸이 없는 칸은 넣지 않는다.
pub fn cell_bounds(rc: &Ctx, p: &V) -> Map {
    let map = Map::new();
    for g in cell_chains(rc, p) {
        let sps: Vec<Sp> = g.iter().map(|x| x.sp.clone()).collect();
        let b = chain_bounds(rc, &sps);
        for (k, x) in g.iter().enumerate() {
            let Some(r) = &x.r#ref else { continue };
            let refs = |ix: &[usize]| -> V { V::Arr(Arr::new(ix.iter().filter_map(|&j| g[j].r#ref.clone().map(V::from)).collect())) };
            let succ = V::Arr(Arr::new(b[k].next.iter().map(|&j| g[j].to.clone()).filter(tv).collect()));
            map.set(V::from(r.clone()), o! { "lo" => b[k].lo, "hi" => b[k].hi, "prev" => refs(&b[k].prev), "next" => refs(&b[k].next), "succ" => succ });
        }
    }
    map
}

//! 단체 계보 창의 배치 셈 — `js/group-tree.js`(SHA-256 앞 12자 `a7e15f1b80f3`) 36 ~ 189줄(화면과 무관한 셈: `spanKind` · `KIND_WORD` · `HOW_KIND` · `EPS` · `powerSegs` · `countText` ·
//! `HT.groupTreeLayout`)을 줄 그대로(한 벌 P3 과제 13d). 모듈 `entities`의 `groupWindowRefs`가 부른다(판정 R24 — 제 모듈 아래 · 계획의 자리 `lay/group_tree.rs`는 웹 함수 모으기 과제 때).
//! 옮기지 않은 것(화면 — 내보내기가 부르지 않음): 191줄부터의 창(`HT.groupTree.mount` · 그리기 · 글 폭 재기 · 범례).
//! 정렬의 글 비교는 `HT.cmp16`(과제 4 덧붙임 · 판정 R11 — UTF-16 차례).
use crate::lay::js::{self, Map, Set, V};
use crate::lay::model::util::{eq, is, list, n, or, s, tv};
use crate::lay::rows::power_span_kind;

/// `EPS`.
const EPS: f64 = 1e-6;

/// 집권 덩이 `{ a, b, kind }`(kind: power · coal · real).
#[derive(Clone, Debug)]
pub struct Seg { pub a: f64, pub b: f64, pub kind: &'static str }
/// `spanKind(c)` — 집권 칸의 종류(`HT.powerSpanKind(c.name)`).
fn span_kind(c: &V) -> &'static str { power_span_kind(&c.get("name")) }
/// `KIND_WORD`.
fn kind_word(k: &str) -> &'static str { match k { "power" => "집권", "coal" => "연정", _ => "실권" } }

/// `powerSegs(g, other)` — 단체의 집권 덩이: 있던 기간으로 자르고, 다른 단체의 집권(실권 빼고 — other: [시작, 끝] 목록)과 겹친 집권은 연정으로, 맞닿은 같은 종류는 한 덩이로.
fn power_segs(g: &V, other: &[(f64, f64)]) -> Vec<Seg> {
    let lo = n(&g.get("start"));
    let hi = n(&g.get("endY"));
    let mut out: Vec<Seg> = Vec::new();
    for c in list(&g.get("powerSpans")) {
        let a = js::max(&[n(&c.get("start")), lo]);
        let b = js::min(&[n(&c.get("end")), hi]);
        if !(b > a) { continue; }
        let kind = span_kind(&c);
        if kind != "power" || other.is_empty() { out.push(Seg { a, b, kind }); continue; }
        let mut cuts = vec![a, b];
        for &(x, y) in other {
            if x > a && x < b { cuts.push(x); }
            if y > a && y < b { cuts.push(y); }
        }
        // [...new Set(cuts)].sort((p, q) => p - q)
        let mut pts: Vec<f64> = Vec::new();
        for x in cuts { if !pts.iter().any(|p| *p == x || (p.is_nan() && x.is_nan())) { pts.push(x); } }
        js::sort_by(&mut pts, |p, q| p - q);
        for i in 0..pts.len().saturating_sub(1) {
            let m = (pts[i] + pts[i + 1]) / 2.0;
            out.push(Seg { a: pts[i], b: pts[i + 1], kind: if other.iter().any(|&(x, y)| x <= m && m <= y) { "coal" } else { "power" } });
        }
    }
    js::sort_by(&mut out, |p, q| { let d = p.a - q.a; if d != 0.0 && !d.is_nan() { d } else { p.b - q.b } });
    let mut merged: Vec<Seg> = Vec::new();
    for sg in out {
        match merged.last_mut() {
            Some(l) if l.kind == sg.kind && sg.a <= l.b + EPS => l.b = js::max(&[l.b, sg.b]),
            _ => merged.push(sg.clone()),
        }
    }
    merged
}
/// `countText(segs)` — '집권 n번 · 연정 m번 · 실권 k번'(덩이 수 — 맞닿은 같은 종류는 한 번).
fn count_text(segs: &[Seg]) -> String {
    ["power", "coal", "real"].iter().map(|k| (*k, segs.iter().filter(|x| x.kind == *k).count())).filter(|(_, c)| *c > 0).map(|(k, c)| format!("{} {c}번", kind_word(k))).collect::<Vec<_>>().join(" · ")
}

/// 나무의 단체 하나 `{ g, row, segs, count, inEdges }`(inEdges는 그 단체로 들어오는 이음의 번호).
pub struct Node { pub g: V, pub row: usize, pub segs: Vec<Seg>, pub count: String, pub in_edges: Vec<usize> }
/// 이음 하나 `{ from, to, how, note, i, same, kind, ev }`.
pub struct Edge { pub from: V, pub to: V, pub how: V, pub note: V, pub i: usize, pub same: bool, pub kind: &'static str, pub ev: V }
/// `HT.groupTreeLayout`의 답 `{ nodes, edges, rows, polity, start, end }`.
pub struct Lay { pub nodes: Vec<Node>, pub edges: Vec<Edge>, pub rows: usize, pub polity: V, pub start: f64, pub end: f64 }

/// `HT.groupTreeLayout(model, { polityUid, groupUid })` — 나무 배치: polityUid — 그 나라에 있던 단체를 모음 · groupUid — 그 단체(와 닿는 단체)를 꼭 넣음.
pub fn group_tree_layout(model: &V, polity_uid: &V, group_uid: &V) -> Lay {
    let all = if tv(model) { list(&model.get("groups")) } else { Vec::new() };
    let in_polity = |g: &V| list(&g.get("withinList")).iter().any(|w| tv(&w.get("polityUid")) && js::strict_eq(&w.get("polityUid"), polity_uid));
    // ① 모으기
    let set = Set::new();
    let mut stack: Vec<V> = all.iter().filter(|g| (tv(polity_uid) && in_polity(g)) || (tv(group_uid) && js::strict_eq(&g.get("uid"), group_uid))).cloned().collect();
    while let Some(g) = stack.pop() {
        if !tv(&g) || set.has(&g) { continue; }
        set.add(g.clone());
        for f in list(&g.get("fromList")) { if tv(&f.get("group")) { stack.push(f.get("group")); } }
        for f in list(&g.get("intoList")) { if tv(&f.get("group")) { stack.push(f.get("group")); } }
    }
    let mut lst = set.values();
    js::sort_by(&mut lst, |a, b| {
        let d = n(&a.get("start")) - n(&b.get("start"));
        if d != 0.0 && !d.is_nan() { return d; }
        let d = n(&b.get("endY")) - n(&a.get("endY"));
        if d != 0.0 && !d.is_nan() { return d; }
        match js::to_str(&a.get("name")).cmp16(&js::to_str(&b.get("name"))) { std::cmp::Ordering::Less => -1.0, std::cmp::Ordering::Greater => 1.0, _ => 0.0 }
    });
    let pos = |g: &V| lst.iter().position(|x| eq(x, g)).expect("모인 단체");
    let mut edges: Vec<Edge> = Vec::new();
    let mut parents_of: Vec<Vec<usize>> = vec![Vec::new(); lst.len()];
    let merge_of = Map::new(); // 앞선 단체 → 그 단체가 합쳐 든 단체의 차례(+1)
    for (gi, g) in lst.iter().enumerate() {
        for (i, f) in list(&g.get("fromList")).iter().enumerate() {
            let fg = f.get("group");
            if !tv(&fg) || !set.has(&fg) || eq(&fg, g) || parents_of[gi].iter().any(|&e| eq(&edges[e].from, &fg)) { continue; }
            edges.push(Edge { from: fg, to: g.clone(), how: or(f.get("how"), s("")), note: or(f.get("note"), s("")), i, same: false, kind: "", ev: V::Null });
            parents_of[gi].push(edges.len() - 1);
        }
    }
    for gi in 0..lst.len() {
        if parents_of[gi].len() > 1 { for &e in &parents_of[gi] { if !merge_of.has(&edges[e].from) { merge_of.set(edges[e].from.clone(), (gi + 1) as f64); } } }
    }
    let merge_key = |g: &V| -> f64 { n(&or(merge_of.get(g), V::Num(0.0))) };
    /* 한 번 순회: primary(아이 → 그 아이를 매단 이음) */
    struct Placed { row_of: Vec<Option<usize>>, order: Vec<Option<usize>>, rows: usize, cont: Vec<Option<usize>> }
    let place = |primary: &[Option<usize>]| -> Placed {
        let mut kids: Vec<Vec<usize>> = vec![Vec::new(); lst.len()];
        for gi in 0..lst.len() { if let Some(e) = primary[gi] { kids[pos(&edges[e].from)].push(e); } }
        /* 이름 바꿈으로 이어 쓰기: 부모가 끝난 뒤에 시작한(겹치지 않는) 이름 바꿈 아이 하나 — 가장 먼저 시작한 것 */
        let mut cont: Vec<Option<usize>> = vec![None; lst.len()];
        for (gi, g) in lst.iter().enumerate() {
            let mut c: Vec<usize> = kids[gi].iter().copied().filter(|&e| is(&edges[e].how, "rename") && n(&edges[e].to.get("start")) >= n(&g.get("endY")) - EPS).collect();
            js::sort_by(&mut c, |&a, &b| n(&edges[a].to.get("start")) - n(&edges[b].to.get("start")));
            cont[gi] = c.first().copied();
        }
        let mut st = Placed { row_of: vec![None; lst.len()], order: vec![None; lst.len()], rows: 0, cont: cont.clone() };
        let mut nn_ = 0usize;
        fn visit(gi: usize, row: usize, st: &mut Placed, nn_: &mut usize, lst: &[V], edges: &[Edge], kids: &[Vec<usize>], cont: &[Option<usize>], pos: &dyn Fn(&V) -> usize, merge_key: &dyn Fn(&V) -> f64) {
            if st.row_of[gi].is_some() { return; }
            let mut lane = vec![gi];
            st.row_of[gi] = Some(row);
            st.order[gi] = Some(*nn_);
            *nn_ += 1;
            let mut c = cont[gi];
            while let Some(e) = c {
                let to = pos(&edges[e].to);
                if st.row_of[to].is_some() { break; }
                st.row_of[to] = Some(row);
                st.order[to] = Some(*nn_);
                *nn_ += 1;
                lane.push(to);
                c = cont[to];
            }
            let mut ch: Vec<usize> = lane.iter().flat_map(|&m| kids[m].iter().copied().filter(move |&e| cont[m] != Some(e))).collect();
            /* 이음선이 내려오는 x가 큰 아이를 부모 가까이(위)에 — 같은 x면 합쳐질 단체의 앞선 단체들을 붙여 뒤에, 그다음 시작 차례 */
            let vx = |e: usize| { let (f, t) = (&edges[e].from, &edges[e].to); if n(&t.get("start")) >= n(&f.get("endY")) - EPS { n(&f.get("endY")) } else { n(&t.get("start")) } };
            js::sort_by(&mut ch, |&a, &b| {
                let (ta, tb) = (&edges[a].to, &edges[b].to);
                for d in [vx(b) - vx(a), merge_key(ta) - merge_key(tb), n(&ta.get("start")) - n(&tb.get("start")), n(&tb.get("endY")) - n(&ta.get("endY"))] { if d != 0.0 && !d.is_nan() { return d; } }
                pos(ta) as f64 - pos(tb) as f64
            });
            for e in ch {
                let to = pos(&edges[e].to);
                if st.row_of[to].is_none() { let r = st.rows; st.rows += 1; visit(to, r, st, nn_, lst, edges, kids, cont, pos, merge_key); }
            }
        }
        for gi in 0..lst.len() { if primary[gi].is_none() { let r = st.rows; st.rows += 1; visit(gi, r, &mut st, &mut nn_, &lst, &edges, &kids, &cont, &pos, &merge_key); } }
        for gi in 0..lst.len() { if st.row_of[gi].is_none() { let r = st.rows; st.rows += 1; visit(gi, r, &mut st, &mut nn_, &lst, &edges, &kids, &cont, &pos, &merge_key); } } // 고리 — 남은 것 가운데 먼저 시작한 단체부터
        st
    };
    let primary: Vec<Option<usize>> = (0..lst.len()).map(|gi| parents_of[gi].first().copied()).collect();
    let first = place(&primary);
    let primary: Vec<Option<usize>> = (0..lst.len()).map(|gi| {
        let ps = &parents_of[gi];
        if ps.len() < 2 { ps.first().copied() } else {
            let ord = |e: usize| first.order[pos(&edges[e].from)].map_or(f64::NAN, |o| o as f64);
            Some(ps.iter().copied().fold(ps[0], |a, e| if ord(e) > ord(a) { e } else { a }))
        }
    }).collect();
    let second = place(&primary);
    /* 같은 나라에 있던 단체끼리(연정 셈): 나라마다 그 나라에 있던 단체들의 집권 칸(실권 빼고)을 한 번 모아 둠 */
    let mut by_polity: Vec<(V, Vec<(f64, f64, usize)>)> = Vec::new();
    let mut pols_of: Vec<Vec<V>> = Vec::new();
    for (gi, g) in lst.iter().enumerate() {
        let pols = Set::new();
        for w in list(&g.get("withinList")) { let u = w.get("polityUid"); if tv(&u) { pols.add(u); } }
        let pols = pols.values();
        for u in &pols {
            let k = match by_polity.iter().position(|(x, _)| js::strict_eq(x, u)) { Some(k) => k, None => { by_polity.push((u.clone(), Vec::new())); by_polity.len() - 1 } };
            for c in list(&g.get("powerSpans")) {
                if span_kind(&c) != "real" && n(&c.get("end")) > n(&c.get("start")) { by_polity[k].1.push((n(&c.get("start")), n(&c.get("end")), gi)); }
            }
        }
        pols_of.push(pols);
    }
    let nodes: Vec<Node> = lst.iter().enumerate().map(|(gi, g)| {
        let mut other: Vec<(f64, f64)> = Vec::new();
        let mut seen: Vec<(usize, usize)> = Vec::new(); // (나라 자리, 칸 자리) — 같은 배열 원소(sp)는 한 번
        for u in &pols_of[gi] {
            let k = by_polity.iter().position(|(x, _)| js::strict_eq(x, u)).expect("나라");
            for (j, sp) in by_polity[k].1.iter().enumerate() {
                if sp.2 == gi || seen.contains(&(k, j)) { continue; }
                seen.push((k, j));
                other.push((sp.0, sp.1));
            }
        }
        let segs = power_segs(g, &other);
        let count = count_text(&segs);
        Node { g: g.clone(), row: second.row_of[gi].expect("줄"), segs, count, in_edges: parents_of[gi].clone() }
    }).collect();
    for ei in 0..edges.len() {
        let to = pos(&edges[ei].to);
        let from = pos(&edges[ei].from);
        let merge = parents_of[to].len() > 1;
        edges[ei].same = second.cont[from] == Some(ei);
        let how = edges[ei].how.clone();
        edges[ei].kind = if merge { "merge" } else {
            match js::to_str(&how).as_str().as_ref() { "split" => "split", "merge" => "merge", "rename" => "rename", "unknown" => "unknown", _ => if tv(&how) { "split" } else { "blank" } }
        };
        if edges[ei].kind == "split" && !tv(&how) { edges[ei].kind = "blank"; }
        edges[ei].ev = or(edges[ei].to.get("eventItem"), V::Null);
    }
    let p = if tv(polity_uid) && tv(&model.get("byUid")) { or(model.get("byUid").as_map().map_or(V::Undef, |m| m.get(polity_uid)), V::Null) } else { V::Null };
    let start = if lst.is_empty() { 0.0 } else { js::min(&lst.iter().map(|g| n(&g.get("start"))).collect::<Vec<_>>()) };
    let end = if lst.is_empty() { 0.0 } else { js::max(&lst.iter().map(|g| n(&g.get("endY"))).collect::<Vec<_>>()) };
    Lay { nodes, edges, rows: second.rows, polity: p, start, end }
}

//! `entities.mjs` 100 ~ 442줄 `crossRefs(ctx, kin, docBodies)` — 상세 창이 모델을 넘나들며 찾던 것을 미리 푼다 → 미리 푼 값의 표(uid → `{ x_… }`).
//! 승계 상대 · 소속 상대 · 대범위 목록 · 지도자 칸 ↔ 같은 이름의 인물 · 사건 수 · 왕조 창 · 사건 · 조약 · 인물 · 시대 구분 · 대범위 · 가문 → 끝에 `format3Refs` · `groupWindowRefs`.
use super::kin::KinOut;
use super::web::{cell_span, format_range, format_when, format_year, kind_name, map_get, map_has, relation_name, span_meets, succ_absorbs, succ_degree_name, succ_part_name, va, CELL_KIND_IDS};
use super::{brief, mm, span_of, Cx, MEMBER_FIGURES};
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::bounds::cells_of;
use crate::lay::model::util::{eq, fault, is, le, leader_label, list, lt, n, or, s, t, tv};
use crate::lay::read::{treaty, vocab};

/// 새 객체(열쇠 차례대로).
macro_rules! obj { ($($k:expr => $v:expr),* $(,)?) => {{ let o = Obj::new(); $( o.set($k, $v); )* o }}; }
pub(super) use obj;

/// `crossRefs(ctx, kin, docBodies)` — 결과는 `cx.ex`에 쌓인다.
pub(super) fn cross_refs(cx: &mut Cx, kin: Option<&KinOut>, doc_bodies: &Set) {
    let model = cx.model.clone();
    let w = &cx.w;
    let tt = cx.t();
    let ex = &cx.ex;
    let periods = list(&model.get("periods"));
    let figures = list(&model.get("figures"));
    let by_uid = model.get("byUid");

    /* ---------- 승계 상대(양쪽 · 종류 · 세기 · 합류 해) — js/viewer.js:822 successionHTML ---------- */
    let edge_of = |e: &V, other: &V| -> V {
        let o = brief(w, other, &[("type", or(e.get("type"), s("indirect")))]);
        let V::Obj(ob) = &o else { return V::Null };
        if is(&e.get("type"), "partial") {
            let d = if e.get("degree").is_nullish() { V::Num(vocab::SUCC_DEGREE_DEFAULT) } else { e.get("degree") };
            ob.set("degree", d.clone()); // 정도(1 약 · 2 중 · 3 강)
            ob.set("degreeName", succ_degree_name(&d));
            let parts = or(e.get("parts"), va(Vec::new()));
            if tv(&parts.get("length")) { ob.set("parts", va(list(&e.get("parts")).iter().map(succ_part_name).collect())); } // 이어진 것(지배층 · 백성 …)
        }
        if succ_absorbs(&e.get("from"), &e.get("to")) {
            ob.set("join", format_year(&e.get("from").get("endY"))); // 흡수(합류) — 이름 뒤 옅은 글 '· n년 합류'
            ob.set("joinAt", mm(&e.get("from").get("endY")));
        }
        if tv(&e.get("note")) { ob.set("note", e.get("note")); }
        o
    };

    /* ---------- 소속 상대(양쪽 · 관계 · 기간) — js/viewer.js:847 partOfHTML ---------- */
    let host_row = |x: &V, h: &V| -> V {
        let host = h.get("host");
        // JS `brief(HT, h.host, { kind: HT.kindName(h.host.polityKind) })` — 상국이 없으면(null · undefined) 인자를 셈하다 TypeError(과제 Y)
        if host.is_nullish() { fault(format!("소속 상대(hostRow) — {}의 상국이 없습니다(JS라면 h.host.polityKind에서 TypeError)", t(&x.get("uid")))); return V::Null; }
        let o = brief(w, &host, &[("kind", s(kind_name(&host.get("polityKind"))))]);
        let V::Obj(ob) = &o else { return V::Null };
        let given = !h.get("start").is_nullish() || !h.get("end").is_nullish() || tv(&h.get("startUnknown")) || tv(&h.get("endUnknown"));
        let when = if given {
            let a = if tv(&h.get("startUnknown")) { "미정".to_string() } else if !h.get("start").is_nullish() { tt.when_text(&h.get("start"), &h.get("startAt")) } else { format_when(w.rc, x, "start") };
            let b = if tv(&h.get("endUnknown")) { "미정".to_string() } else if !h.get("end").is_nullish() { tt.when_text(&h.get("end"), &h.get("endAt")) } else { tt.end_when(x) };
            format!("{a} ~ {b}")
        } else { "전 기간".to_string() };
        ob.set("when", when);
        ob.set("span", span_of(&if h.get("start").is_nullish() { x.get("start") } else { h.get("start") }, &if h.get("end").is_nullish() { x.get("endY") } else { h.get("end") }));
        if tv(&h.get("relation")) { ob.set("rel", relation_name(&h.get("relation"))); }
        if tv(&h.get("note")) { ob.set("note", h.get("note")); }
        if tv(&host.get("peopleId")) { ob.set("peopleId", host.get("peopleId")); ob.set("people", or(host.get("peopleName"), s(""))); } // 상위 띠 아래 놓인 나라의 민족 한마디
        o
    };
    let member_row = |x: &V, p: &V| -> V {
        // JS `brief(HT, p, { kind: HT.kindName(p.polityKind) })` — 구성원이 없으면(null · undefined) TypeError(과제 Y)
        if p.is_nullish() { fault(format!("소속 상대(memberRow) — {}의 구성원이 비었습니다(JS라면 p.polityKind에서 TypeError)", t(&x.get("uid")))); return V::Null; }
        let o = brief(w, p, &[("kind", s(kind_name(&p.get("polityKind"))))]);
        let V::Obj(ob) = &o else { return V::Null };
        let rels = Set::new();
        for h in list(&p.get("hosts")) { if eq(&h.get("host"), x) { let r = h.get("relation"); if tv(&r) { rels.add(r); } } }
        let rels = rels.values();
        if !rels.is_empty() { ob.set("rels", va(rels.iter().map(|r| s(relation_name(r))).collect())); }
        if is(&p.get("polityKind"), "overlay") { ob.set("organ", 1.0); } // 위에 놓인 기관 — 딸린 정권과 따로 묶는다
        o
    };

    /* ---------- 대범위 목록(칩 · 모아 보기 스위치) — js/viewer.js:1006 scopeListHTML ---------- */
    let scope_row = |sc: &V| -> V {
        let o = obj! { "uid" => sc.get("uid"), "name" => or(sc.get("name"), s("")), "color" => or(sc.get("color"), s("")) };
        if tv(&sc.get("label")) { o.set("label", sc.get("label")); }
        let host = sc.get("host");
        if tv(&host) { o.set("host", obj! { "uid" => host.get("uid"), "name" => host.get("name"), "after" => if tv(&sc.get("afterHost")) { 1.0 } else { 0.0 } }); }
        V::Obj(o)
    };

    /* ---------- 지도자 칸 ↔ 같은 이름의 인물 — js/viewer.js figureOfLeader · leadersOfFigure ---------- */
    let mut leader_figure: Vec<(V, Vec<(String, V)>)> = Vec::new(); // 정권 uid → { 'leader:3': 인물 }
    let figure_leaders = Map::new(); // 인물 uid → [{ p, c, i }]
    for p in &periods {
        let leaders = list(&p.get("leaders"));
        if leaders.is_empty() || figures.is_empty() { continue; }
        for (i, c) in leaders.iter().enumerate() {
            let f = figure_of_leader(&figures, p, c);
            if !tv(&f) { continue; }
            let k = match leader_figure.iter().position(|(u, _)| js::strict_eq(u, &p.get("uid"))) { Some(k) => k, None => { leader_figure.push((p.get("uid"), Vec::new())); leader_figure.len() - 1 } };
            let r = format!("leader:{i}");
            match leader_figure[k].1.iter_mut().find(|x| x.0 == r) { Some(x) => x.1 = f.clone(), None => leader_figure[k].1.push((r, f.clone())) }
            if !figure_leaders.has(&f.get("uid")) { figure_leaders.set(f.get("uid"), va(Vec::new())); }
            if let V::Arr(l) = figure_leaders.get(&f.get("uid")) { l.push(va(vec![p.clone(), c.clone(), V::Num(i as f64)])); }
        }
    }

    /* ---------- 정권마다 '이 나라의 사건 수'와 기간 (공동 사건은 그 나라 줄에 그려지는 자리까지 센다) ---------- */
    let ev_stat = Map::new();
    for e in list(&model.get("events")) {
        let pl = e.get("placements");
        let places = if tv(&pl) && tv(&pl.get("length")) { list(&pl) } else { vec![V::Obj(obj! { "polityUid" => e.get("polityUid") })] };
        let uids = Set::new();
        for x in &places { let u = x.get("polityUid"); if tv(&u) { uids.add(u); } }
        for uid in uids.values() {
            if !ev_stat.has(&uid) { ev_stat.set(uid.clone(), va(vec![V::Num(0.0), V::Num(f64::INFINITY), V::Num(f64::NEG_INFINITY)])); }
            let V::Arr(st) = ev_stat.get(&uid) else { continue };
            st.set(0, n(&st.get(0)) + 1.0);
            st.set(1, js::min(&[n(&st.get(1)), js::to_num(&e.get("start"))]));
            st.set(2, js::max(&[n(&st.get(2)), js::to_num(&if e.get("endY").is_nullish() { e.get("start") } else { e.get("endY") })]));
        }
    }

    /* ---------- 왕조: 본가 · 분가는 왕조 이름으로만 이어져 있어 모델 전체를 훑어야 찾을 수 있다 — js/viewer.js:914~916 ---------- */
    let dyns: Vec<V> = periods.iter().filter(|q| is(&q.get("polityKind"), "dynasty")).cloned().collect();
    let dyn_by = Map::new();
    for d in &dyns {
        if !dyn_by.has(&d.get("name")) { dyn_by.set(d.get("name"), d.clone()); }
        if tv(&d.get("id")) && !dyn_by.has(&d.get("id")) { dyn_by.set(d.get("id"), d.clone()); }
    }

    /* ========== 정권 · 기관 · 문화 · 왕조 ========== */
    for x in &periods {
        /* 칸마다의 경계 [lo, hi) — 이웃 칸을 봐야 정해지는 값이라 넣을 때 확정한다(HT.cellBounds · HT.cellSpan). */
        let bounds = Obj::new();
        for k in CELL_KIND_IDS {
            for (i, c) in cells_of(x, k).iter().enumerate() {
                if !tv(c) || !matches!(c.get("start"), V::Num(v) if v.is_finite()) { continue; }
                let r = format!("{k}:{i}");
                let sp = cell_span(w.rc, c, x, &s(&r));
                let b = span_of(&sp.get("lo"), &sp.get("hi"));
                if tv(&b) { bounds.set(r.as_str(), b); }
            }
        }
        ex.put(x, "x_cellBounds", V::Obj(bounds));

        let st = ev_stat.get(&x.get("uid"));
        if tv(&st) { ex.put(x, "x_eventStat", V::Obj(obj! { "count" => st.get(&0.0), "span" => span_of(&st.get(&1.0), &st.get(&2.0)) })); }

        // 이 정권을 섬긴 인물(정권 상세의 '인물' 목록) — $ref에는 없는 역할 · 직함 · 기간 글까지
        ex.put(x, "x_served", va(list(&x.get("servedBy")).iter().map(|r| {
            let (f, sv) = (r.get("figure"), r.get("service"));
            let o = obj! { "uid" => f.get("uid"), "name" => or(f.get("name"), s("")), "color" => or(f.get("color"), s("")), "when" => tt.service_when(&f, &sv) };
            if tv(&f.get("role")) { o.set("role", f.get("role")); }
            if tv(&sv.get("office")) && !js::strict_eq(&sv.get("office"), &f.get("role")) { o.set("office", sv.get("office")); }
            o.set("span", span_of(&sv.get("start"), &sv.get("endY")));
            V::Obj(o)
        }).collect()));

        ex.put(x, "x_scopes", va(list(&x.get("scopes")).iter().map(scope_row).collect()));
        ex.put(x, "x_hostedScopes", va(list(&x.get("hostedScopes")).iter().map(scope_row).collect()));

        if let Some((_, lf)) = leader_figure.iter().find(|(u, _)| js::strict_eq(u, &x.get("uid"))) {
            let o = Obj::new();
            for (r, f) in lf { o.set(r.as_str(), obj! { "uid" => f.get("uid"), "name" => or(f.get("name"), s("")), "role" => or(f.get("role"), s("")) }); }
            ex.put(x, "x_leaderFigures", V::Obj(o));
        }

        if is(&x.get("polityKind"), "dynasty") {
            /* 왕조 창: 다스린 나라 · 가문(본가 · 분가) · 그 왕조의 지도자 · 다스린 띠마다의 조명 — js/viewer.js:905~932 */
            struct Pt { t: V, text: String }
            let mut ruled: Vec<(V, Pt, Pt)> = Vec::new();
            for h in list(&x.get("hosts")) {
                let host = h.get("host");
                // JS `h.host.start` — 상국이 null · undefined면 TypeError(과제 Y)
                if host.is_nullish() { fault(format!("다스린 나라(x_ruled) — {}의 상국이 없습니다(JS라면 h.host.start에서 TypeError)", t(&x.get("uid")))); }
                let a0 = if !h.get("start").is_nullish() { Pt { t: h.get("start"), text: if tv(&h.get("startUnknown")) { "미정".into() } else { tt.when_text(&h.get("start"), &h.get("startAt")) } } }
                    else { Pt { t: x.get("start"), text: if tv(&h.get("startUnknown")) { "미정".into() } else { format_when(w.rc, x, "start") } } };
                let a1 = Pt { t: host.get("start"), text: format_when(w.rc, &host, "start") };
                let b0 = if !h.get("end").is_nullish() { Pt { t: h.get("end"), text: if tv(&h.get("endUnknown")) { "미정".into() } else { tt.when_text(&h.get("end"), &h.get("endAt")) } } }
                    else { Pt { t: x.get("endY"), text: if tv(&h.get("endUnknown")) { "미정".into() } else { tt.end_when(x) } } };
                let b1 = Pt { t: host.get("endY"), text: tt.end_when(&host) };
                let a = if lt(&a0.t, &a1.t) { a1 } else { a0 }; // 늦은 시작 · 이른 끝
                let b = if lt(&b1.t, &b0.t) { b1 } else { b0 };
                if le(&a.t, &b.t) { ruled.push((h, a, b)); }
            }
            ex.put(x, "x_ruled", va(ruled.iter().map(|(h, a, b)| {
                let host = h.get("host");
                // JS: 상국이 null · undefined면 `h.host.polityKind`에서, 그 밖의 거짓이면 `brief`가 null이라 `o.when =`에서 TypeError(과제 Y)
                if !tv(&host) { fault(format!("다스린 나라(x_ruled) — {}의 상국이 없습니다(JS라면 TypeError)", t(&x.get("uid")))); }
                let o = brief(w, &host, &[("kind", s(kind_name(&host.get("polityKind"))))]);
                if let V::Obj(ob) = &o {
                    ob.set("when", format!("{} ~ {}", a.text, b.text));
                    ob.set("span", span_of(&a.t, &b.t));
                    if tv(&h.get("note")) { ob.set("note", h.get("note")); }
                }
                o
            }).collect()));
            let mut rulers: Vec<(V, V, usize)> = Vec::new();
            for (h, _, _) in &ruled {
                let host = h.get("host");
                for (i, c) in list(&host.get("leaders")).into_iter().enumerate() {
                    if !js::strict_eq(&or(c.get("dynasty"), c.get("dynastyAuto")), &x.get("name")) { continue; }
                    rulers.push((host.clone(), c, i));
                }
            }
            js::sort_by(&mut rulers, |a, b| n(&a.1.get("start")) - n(&b.1.get("start")));
            ex.put(x, "x_rulers", va(rulers.iter().map(|(host, c, i)| V::Obj(obj! {
                "uid" => host.get("uid"), "name" => or(host.get("name"), s("")), "ref" => format!("leader:{i}"), "label" => leader_label(c), "when" => tt.cell_when(c, false, host), "at" => mm(&c.get("start")),
            })).collect()));
            let main = if tv(&x.get("house")) { dyn_by.get(&x.get("house")) } else { V::Null };
            if tv(&main) && !eq(&main, x) { ex.put(x, "x_houseMain", brief(w, &main, &[])); }
            ex.put(x, "x_branches", va(dyns.iter().filter(|q| !eq(q, x) && tv(&q.get("house")) && (js::strict_eq(&q.get("house"), &x.get("name")) || js::strict_eq(&q.get("house"), &x.get("id")))).map(|q| brief(w, q, &[])).collect()));
            // 다스린 띠마다의 기간 조명(창을 열 때 그대로 쓰는 값)
            let mut spots: Vec<V> = Vec::new();
            for h in list(&x.get("hosts")) {
                let host = h.get("host");
                for d in list(&host.get("dynasties")) {
                    if eq(&d.get("dynasty"), x) && !spots.iter().any(|sp| js::strict_eq(&sp.get("uid"), &host.get("uid")) && js::strict_eq(&sp.get("start"), &mm(&d.get("start")))) {
                        spots.push(V::Obj(obj! { "uid" => host.get("uid"), "start" => mm(&d.get("start")), "end" => mm(&d.get("end")) }));
                    }
                }
            }
            ex.put(x, "x_spots", va(spots));
        } else {
            /* 정권 · 기관 · 문화: 승계 · 소속 · 다스린 왕조 */
            let pre: Vec<V> = list(&x.get("predecessors")).iter().map(|e| edge_of(e, &e.get("from"))).filter(tv).collect();
            let post: Vec<V> = list(&x.get("successors")).iter().map(|e| edge_of(e, &e.get("to"))).filter(tv).collect();
            if !pre.is_empty() || !post.is_empty() {
                let o = Obj::new();
                if !pre.is_empty() { o.set("pre", va(pre)); }
                if !post.is_empty() { o.set("post", va(post)); }
                ex.put(x, "x_succ", V::Obj(o));
            }
            let hosts: Vec<V> = list(&x.get("hosts")).iter().map(|h| host_row(x, h)).filter(tv).collect();
            let members: Vec<V> = list(&x.get("members")).iter().map(|p| member_row(x, p)).filter(tv).collect();
            if !hosts.is_empty() || !members.is_empty() {
                let o = Obj::new();
                if !hosts.is_empty() { o.set("hosts", va(hosts)); }
                if !members.is_empty() { o.set("members", va(members)); }
                ex.put(x, "x_partOf", V::Obj(o));
            }
            ex.put(x, "x_dynasties", va(list(&x.get("dynasties")).iter().filter_map(|d| {
                let o = brief(w, &d.get("dynasty"), &[]);
                let V::Obj(ob) = &o else { return None };
                ob.set("when", format!("{} ~ {}", tt.when_text(&d.get("start"), &V::Undef), tt.end_text(&d.get("end"))));
                ob.set("span", span_of(&d.get("start"), &d.get("end")));
                if tv(&d.get("note")) { ob.set("note", d.get("note")); }
                Some(o)
            }).collect()));
        }
    }

    /* ========== 사건 · 조약 ========== */
    for e in list(&model.get("events")) {
        ex.put(&e, "x_children", va(list(&e.get("children")).iter().map(|c| V::Obj(obj! {
            "uid" => c.get("uid"), "title" => or(c.get("title"), s("")), "when" => format_range(w.rc, c), "span" => span_of(&c.get("start"), &c.get("endY")),
        })).collect()));
        if tv(&e.get("parentUid")) { ex.put(&e, "x_parent", V::Obj(obj! { "uid" => e.get("parentUid"), "title" => or(e.get("parentTitle"), s("")) })); }
        ex.put(&e, "x_figures", va(list(&e.get("figureRefs")).iter().map(|r| {
            let f = if tv(&r.get("uid")) { map_get(&by_uid, &r.get("uid")) } else { V::Null };
            let o = obj! { "name" => or(r.get("name"), s("")) };
            if tv(&f) { o.set("uid", f.get("uid")); o.set("role", or(f.get("role"), s(""))); o.set("color", or(f.get("color"), s(""))); } // 못 찾은 이름은 uid 없이 — 회색 칩
            V::Obj(o)
        }).collect()));
        let refs = or(e.get("treatyRefs"), V::Null);
        if tv(&refs) {
            /* 당사국 · 서명자: 풀어낸 기록에 uid가 있어 $ref로 접히면 편 · 역할 · 서명자가 모두 사라진다 — 통째로 다시 싣는다(js/viewer.js:1790) */
            ex.put(&e, "x_parties", va(list(&refs.get("parties")).iter().map(|r| {
                let o = obj! { "name" => or(r.get("name"), s("")) };
                if tv(&r.get("uid")) { o.set("uid", r.get("uid")); o.set("color", or(r.get("color"), s(""))); }
                if tv(&r.get("polity")) && tv(&r.get("uid")) && !tv(&r.get("byName")) { o.set("wrote", r.get("polity")); } // 적은 이름을 찾지 못해 그 해의 그 나라로 놓은 당사국
                if tv(&r.get("role")) { o.set("role", r.get("role")); }
                if !r.get("side").is_nullish() { o.set("side", r.get("side")); }
                let sg = or(r.get("signatories"), va(Vec::new()));
                if tv(&sg.get("length")) {
                    o.set("signers", va(list(&r.get("signatories")).iter().map(|x| {
                        let q = obj! { "name" => or(x.get("name"), s("")) };
                        if tv(&x.get("title")) { q.set("title", x.get("title")); }
                        if tv(&x.get("figureUid")) { q.set("uid", x.get("figureUid")); } // 같은 이름의 인물 — 누르면 인물 창
                        V::Obj(q)
                    }).collect()));
                }
                V::Obj(o)
            }).collect()));
        }
        let back = or(e.get("treatyBackRefs"), V::Null);
        let mut related: Vec<V> = Vec::new();
        let mut row = |tag: &str, uid: &V, fallback: &V| {
            let q = if tv(uid) { map_get(&by_uid, uid) } else { V::Null };
            if tv(&q) { related.push(V::Obj(obj! { "tag" => tag, "uid" => q.get("uid"), "title" => or(or(q.get("title"), q.get("name")), s("")), "when" => format_range(w.rc, &q) })); }
            else if tv(fallback) { related.push(V::Obj(obj! { "tag" => tag, "name" => fallback.clone() })); } // 연표에서 찾지 못한 사건 — 누를 수 없는 줄
        };
        let tr = if tv(&e.get("treaty")) { Some(treaty::read_treaty(w.rc, &e.get("treaty"), &mut |_| {}).map_or(V::Obj(Obj::new()), V::Obj)) } else { None };
        let refs_get = |k: &str| if tv(&refs) { refs.get(k) } else { refs.clone() };
        if let Some(tr) = &tr {
            if tv(&tr.get("concludes")) { row("끝낸 전쟁", &refs_get("concludes"), &tr.get("concludes")); }
            if tv(&tr.get("supersedes")) { row("대체한 옛 조약", &refs_get("supersedes"), &tr.get("supersedes")); }
        }
        let back_get = |k: &str| if tv(&back) { or(back.get(k), va(Vec::new())) } else { va(Vec::new()) };
        for uid in list(&back_get("supersededBy")) { row("대체한 새 조약", &uid, &V::Undef); }
        for uid in list(&back_get("concludedBy")) { row("끝낸 조약", &uid, &V::Undef); }
        ex.put(&e, "x_related", va(related));
    }

    /* ========== 인물 ========== */
    for f in &figures {
        ex.put(f, "x_services", va(list(&f.get("services")).iter().map(|sv| {
            let o = obj! { "name" => or(sv.get("polityName"), s("")), "when" => tt.service_when(f, sv), "span" => span_of(&sv.get("start"), &sv.get("endY")) };
            if tv(&sv.get("polityUid")) { o.set("uid", sv.get("polityUid")); }
            if tv(&sv.get("office")) { o.set("office", sv.get("office")); }
            let pol = sv.get("polity");
            if tv(&pol) && !js::strict_eq(&pol.get("track"), &f.get("track")) { // 다른 트랙 표시
                let tr = map_get(&model.get("trackMap"), &pol.get("track"));
                o.set("track", or(if tv(&tr) { tr.get("name") } else { V::Undef }, pol.get("track")));
            }
            if tv(&sv.get("note")) { o.set("note", sv.get("note")); }
            if tv(&sv.get("auto")) { o.set("auto", 1.0); } // 활동 시기로 짐작한 자리
            if !tv(&pol) { o.set("missing", 1.0); } // 연표에서 찾지 못한 정권
            V::Obj(o)
        }).collect()));
        let signed: Vec<V> = list(&f.get("signedTreaties")).into_iter().filter(|r| map_has(&by_uid, &r.get("event").get("uid"))).collect();
        ex.put(f, "x_signed", va(signed.iter().map(|r| {
            let (e, party, signer) = (r.get("event"), r.get("party"), r.get("signer"));
            let o = obj! { "uid" => e.get("uid"), "title" => or(e.get("title"), s("")), "when" => format_range(w.rc, &e), "color" => or(or(e.get("polityColor"), e.get("color")), s("")), "party" => or(party.get("name"), s("")) };
            if tv(&signer.get("title")) { o.set("role", signer.get("title")); }
            V::Obj(o)
        }).collect()));
        let mut evs: Vec<V> = list(&f.get("events")).into_iter().filter(|e| !signed.iter().any(|r| eq(&r.get("event"), e))).collect(); // 서명한 조약은 아래 목록에만
        js::sort(&mut evs, |a, b| n(&a.get("start")) - n(&b.get("start")));
        ex.put(f, "x_events", va(evs.iter().map(|e| {
            let o = obj! { "uid" => e.get("uid"), "title" => or(e.get("title"), s("")), "when" => format_range(w.rc, e), "color" => or(or(e.get("polityColor"), e.get("color")), s("")) };
            if tv(&e.get("treaty")) { o.set("treaty", 1.0); }
            V::Obj(o)
        }).collect()));
        ex.put(f, "x_leaders", va(list(&or(figure_leaders.get(&f.get("uid")), va(Vec::new()))).iter().map(|l| {
            let (p, c, i) = (l.get(&0.0), l.get(&1.0), l.get(&2.0));
            V::Obj(obj! { "uid" => p.get("uid"), "name" => or(p.get("name"), s("")), "ref" => format!("leader:{}", t(&i)), "label" => leader_label(&c) })
        }).collect()));
        /* 같은 시기의 지도자: 섬긴 정권마다, 활동 기록의 기간 [시작, 끝)과 지도자 칸이 품는 구간 [lo, hi)가 겹치는 지도자(js/viewer.js:1287~1298) */
        let mut rulers: Vec<(V, V, usize)> = Vec::new();
        let seen = Set::new();
        for sv in list(&f.get("services")) {
            let pol = sv.get("polity");
            if !tv(&pol) { continue; }
            for (i, c) in list(&pol.get("leaders")).into_iter().enumerate() {
                let key = V::from(format!("{}:{i}", t(&pol.get("uid"))));
                let sp = cell_span(w.rc, &c, &pol, &s(&format!("leader:{i}")));
                if seen.has(&key) || !span_meets(n(&sv.get("start")), n(&sv.get("endY")), n(&sp.get("lo")), n(&sp.get("hi"))) { continue; }
                seen.add(key);
                rulers.push((pol.clone(), c, i));
            }
        }
        js::sort_by(&mut rulers, |a, b| n(&a.1.get("start")) - n(&b.1.get("start")));
        ex.put(f, "x_rulers", va(rulers.iter().map(|(p, c, i)| V::Obj(obj! {
            "uid" => p.get("uid"), "name" => or(p.get("name"), s("")), "ref" => format!("leader:{i}"), "label" => leader_label(c), "when" => tt.cell_when(c, false, p),
        })).collect()));
        ex.put(f, "x_spots", va(list(&f.get("services")).iter().filter(|sv| tv(&sv.get("shown")) && tv(&sv.get("polityUid"))).map(|sv| V::Obj(obj! {
            "uid" => sv.get("polityUid"), "start" => mm(&sv.get("start")), "end" => mm(&sv.get("endY")),
        })).collect()));
    }

    /* ========== 시대 구분 · 대범위 ========== */
    for ep in list(&model.get("epochs")) { ex.put(&ep, "x_scopes", va(list(&ep.get("scopes")).iter().map(scope_row).collect())); }
    for sc in list(&model.get("scopes")) {
        ex.put(&sc, "x_members", va(list(&sc.get("members")).iter().map(|m| {
            // JS: 구성원이 null · undefined면 `m.peopleName`에서, 그 밖의 거짓이면 트랙이 다를 때 `o.other =`(null)에서 TypeError(과제 Y)
            if m.is_nullish() || (!tv(m) && !js::strict_eq(&m.get("track"), &sc.get("track"))) {
                fault(format!("대범위 구성원(x_members) — {}의 구성원이 비었습니다(JS라면 TypeError)", t(&sc.get("uid"))));
            }
            let o = brief(w, m, &[("kind", or(m.get("peopleName"), s(kind_name(&m.get("polityKind")))))]);
            if let V::Obj(ob) = &o { if !js::strict_eq(&m.get("track"), &sc.get("track")) { ob.set("other", 1.0); } } // 다른 트랙 — 모이지 않는다
            o
        }).collect()));
    }

    /* ========== 가문(제 항목이 없어 새 기록으로) ========== */
    let house_map = model.get("houseMap");
    for h in list(&model.get("houses")) {
        let hh = |id: &V| map_get(&house_map, id);
        let chip = |q: &V| -> V { if tv(q) { V::Obj(obj! { "uid" => q.get("uid"), "name" => or(q.get("name"), s("")), "color" => or(q.get("color"), s("")) }) } else { V::Null } };
        ex.put(&h, "x_path", va(list(&h.get("path")).iter().map(hh).filter(tv).map(|q| chip(&q)).collect())); // 본가에서 이 가문까지
        ex.put(&h, "x_branches", va(list(&h.get("children")).iter().map(hh).filter(tv).map(|q| chip(&q)).collect())); // 갈라져 나간 분가
        // JS `h.members.filter(…)` — 배열이 아니면(없음 · 다른 꼴) TypeError(과제 Y — 모델은 늘 배열을 둠)
        if !matches!(h.get("members"), V::Arr(_)) { fault(format!("가문 {}의 members가 배열이 아닙니다(JS라면 h.members.filter에서 TypeError)", t(&h.get("uid")))); }
        let members = list(&h.get("members"));
        ex.put(&h, "x_nations", va(members.iter().filter(|mb| is(&mb.get("role"), "period")).map(|mb| chip(&mb.get("item"))).filter(tv).collect())); // 국성으로 삼은 나라
        /* 구성원 상한(확정 설계 8-1 · D1-E 이음새 기록 ④): 지도자 · 내각 · 왕조는 모두, 띠 인물은 처음 MEMBER_FIGURES명 + x_memberCount(띠 인물 전체 수). */
        let figs: Vec<V> = members.iter().filter(|mb| is(&mb.get("role"), "figure")).cloned().collect();
        let over: Option<Vec<V>> = if figs.len() > MEMBER_FIGURES { Some(figs[MEMBER_FIGURES..].to_vec()) } else { None };
        if over.is_some() { ex.put(&h, "x_memberCount", V::Num(figs.len() as f64)); }
        ex.put(&h, "x_members", va(members.iter().filter(|mb| !is(&mb.get("role"), "period") && !over.as_ref().is_some_and(|o| o.iter().any(|x| eq(x, mb)))).map(|mb| {
            let it = mb.get("item");
            let role = mb.get("role");
            /* 구성원은 나라별로 묶는다: 지도자 · 내각은 그 나라, 왕조는 처음 다스린 나라, 인물은 섬긴 나라(js/viewer.js:1552) */
            let nation = if is(&role, "leader") || is(&role, "cabinet") { it.clone() }
                else if is(&role, "dynasty") { let h0 = list(&it.get("hosts")).first().cloned().unwrap_or(V::Undef); if tv(&h0) { h0.get("host") } else { V::Undef } }
                else { or(if tv(&it.get("polityUid")) { map_get(&by_uid, &it.get("polityUid")) } else { it.get("polityUid") }, V::Null) };
            let o = obj! { "role" => role.clone(), "uid" => it.get("uid"), "name" => or(or(it.get("name"), it.get("title")), s("")) };
            let cell = mb.get("cell");
            if tv(&cell) {
                o.set("ref", or(mb.get("ref"), s("")));
                o.set("name", if is(&role, "leader") { leader_label(&cell) } else { or(cell.get("name"), s("")) });
                o.set("when", tt.cell_when(&cell, false, &it));
                o.set("at", mm(&cell.get("start")));
                o.set("of", or(it.get("name"), s(""))); // 그 칸이 든 정권의 이름
            } else {
                o.set("when", format_range(w.rc, &it));
            }
            if tv(&mb.get("auto")) { o.set("auto", 1.0); } // 적지 않아 왕조 · 국성으로 짐작한 가문
            if tv(&nation) { o.set("nation", nation.get("uid")); o.set("nationName", or(nation.get("name"), s(""))); }
            V::Obj(o)
        }).collect()));
    }

    super::format3::format3_refs(cx, kin, doc_bodies);
    super::window::group_window_refs(cx); // 단체 계보 창 · 법의 내력 · 의석 막대(D5 결정 4 · 7 — 새 앱 몫)
}

/// `figureOfLeader(p, c)` — 지도자 칸 ↔ 같은 이름의 인물(이름 규칙 — 칸의 사람 잇기는 x_persons · x_person이 맡는다).
pub(super) fn figure_of_leader(figures: &[V], p: &V, c: &V) -> V {
    if figures.is_empty() { return V::Null; }
    let names: Vec<V> = [c.get("name"), c.get("temple"), c.get("title"), c.get("given")].into_iter().filter(tv).collect();
    let end = if c.get("end").is_nullish() { p.get("endY") } else { c.get("end") };
    let includes = |x: &V| names.iter().any(|y| js::strict_eq(x, y) || (x.as_num().is_some_and(f64::is_nan) && y.as_num().is_some_and(f64::is_nan)));
    figures.iter().find(|q| {
        // [q.name].concat(q.aka || [])
        let mut cand = vec![q.get("name")];
        match or(q.get("aka"), va(Vec::new())) { V::Arr(a) => cand.extend(a.to_vec()), other => cand.push(other) }
        cand.iter().any(includes) && le(&q.get("spanMin"), &end) && le(&c.get("start"), &js::add(&q.get("spanMax"), &V::Num(1.0)))
            && (js::strict_eq(&q.get("track"), &p.get("track")) || list(&q.get("services")).iter().any(|sv| eq(&sv.get("polity"), p)))
    }).cloned().unwrap_or(V::Null)
}

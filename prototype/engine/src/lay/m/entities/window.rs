//! `entities.mjs` 951 ~ 1199줄 `groupWindowRefs(ctx, put)` — 단체 계보 창 · 법의 내력 · 의석 막대(설계 D5 결정 4 A · 7 A의 새 앱 몫).
//! 웹은 창을 열 때 모델에서 센다(js/group-tree.js HT.groupTreeLayout · js/viewer.js lawVoteIndex · lawTopHTML · electionTopHTML · lensBottomHTML) — 같은 셈을 여기서 한 번 돌려 x_로 싣는다.
use super::cross::obj;
use super::group_tree::{group_tree_layout, Lay};
use super::web::{format_axis_year, format_range, to_fixed1, format_when, group_digits, law_act_name, map_get, map_has, phase_range_text, va};
use super::{mm, Cx};
use crate::lay::cal;
use crate::lay::js::{self, Obj, V};
use crate::lay::model::util::{at_of, auto_color, eq, is, list, n, or, s, t, tv};
use crate::lay::read::{groups, treaty, vocab};

/// `has(o, k, v)`.
fn has(o: &Obj, k: &str, v: V) -> Obj {
    let empty = v.is_nullish() || matches!(&v, V::Str(x) if x.is_empty()) || matches!(&v, V::Arr(a) if a.is_empty());
    if !empty { o.set(k, v); }
    o.clone()
}
/// `groupWindowRefs(ctx, put)`.
pub(super) fn group_window_refs(cx: &mut Cx) {
    let model = cx.model.clone();
    let groups_l = list(&model.get("groups"));
    let events = list(&model.get("events"));
    if groups_l.is_empty() && !events.iter().any(|e| tv(&e.get("law")) || tv(&e.get("election"))) { return; }
    let w = &cx.w;
    let ex = &cx.ex;
    let by_uid = model.get("byUid");
    const EPS: f64 = 1e-6;
    let yr = |v: &V| format_axis_year(v);

    /* ---------- 단체 계보 나무 ---------- */
    let seg_no = |k: &str| -> f64 { match k { "power" => 0.0, "coal" => 1.0, _ => 2.0 } };
    let word = |k: &str| -> &'static str { match k { "split" => "갈라짐", "merge" => "합쳐짐", "rename" => "이름 바꿈", "unknown" => "방식 미상", _ => "방식을 적지 않음" } };
    /* 고른 단체의 조명(웹 spotsOf): 있던 나라 띠마다 집권 덩이(없으면 있던 기간) */
    let spots_of = |g: &V, nd: &super::group_tree::Node| -> V {
        let mut out: Vec<V> = Vec::new();
        for wr in list(&g.get("withinList")) {
            if !tv(&wr.get("polityUid")) || !map_has(&by_uid, &wr.get("polityUid")) { continue; }
            let lo = if wr.get("start").is_nullish() { n(&g.get("start")) } else { n(&wr.get("start")) };
            let hi = if wr.get("end").is_nullish() { n(&g.get("endY")) } else { n(&wr.get("end")) };
            let segs: Vec<(f64, f64)> = if nd.segs.is_empty() { vec![(n(&g.get("start")), n(&g.get("endY")))] } else { nd.segs.iter().map(|x| (x.a, x.b)).collect() };
            for (sa, sb) in segs {
                let a = js::max(&[sa, lo]);
                let b = js::min(&[sb, hi]);
                if b > a { out.push(V::Obj(obj! { "uid" => wr.get("polityUid"), "start" => mm(&V::Num(a)), "end" => mm(&V::Num(b)) })); }
            }
        }
        va(out)
    };
    let tree_of = |lay: &Lay| -> V {
        let o = Obj::new();
        if tv(&lay.polity) && map_has(&by_uid, &lay.polity.get("uid")) { o.set("polity", obj! { "uid" => lay.polity.get("uid"), "name" => or(lay.polity.get("name"), s("")), "color" => or(lay.polity.get("color"), s("")) }); }
        let (ms, me) = (mm(&V::Num(lay.start)), mm(&V::Num(lay.end)));
        o.set("span", va(vec![ms.clone(), V::Num(js::max(&[n(&ms), n(&me)]))]));
        o.set("rows", lay.rows as f64);
        o.set("nodes", va(lay.nodes.iter().map(|nd| {
            let g = &nd.g;
            let (gs, ge) = (mm(&g.get("start")), mm(&g.get("endY")));
            let q = obj! {
                "uid" => g.get("uid"), "name" => or(g.get("name"), s("")), "color" => or(g.get("color"), s("")), "row" => nd.row as f64,
                "span" => va(vec![gs.clone(), V::Num(js::max(&[n(&gs), n(&ge)]))]), "when" => format_range(w.rc, g), "range" => format!("{}–{}", yr(&g.get("start")), yr(&g.get("endY"))),
            };
            has(&q, "type", g.get("typeName"));
            has(&q, "count", s(&nd.count));
            has(&q, "segs", va(nd.segs.iter().map(|sg| va(vec![mm(&V::Num(sg.a)), mm(&V::Num(sg.b)), V::Num(seg_no(sg.kind))])).collect()));
            has(&q, "spots", spots_of(g, nd));
            V::Obj(q)
        }).collect()));
        let idx = |g: &V| -> V { lay.nodes.iter().position(|nd| eq(&nd.g, g)).map_or(V::Undef, |i| V::Num(i as f64)) };
        has(&o, "edges", va(lay.edges.iter().map(|e| {
            let q = obj! { "from" => idx(&e.from), "to" => idx(&e.to), "kind" => e.kind };
            if e.same { q.set("same", 1.0); }
            if n(&e.to.get("start")) >= n(&e.from.get("endY")) - EPS { q.set("after", 1.0); }
            if tv(&e.ev) && map_has(&by_uid, &e.ev.get("uid")) { q.set("ev", e.ev.get("uid")); }
            let note = if tv(&e.note) { format!(" · {}", t(&e.note)) } else { String::new() };
            q.set("tip", format!("{} — {} → {} · {}{note}{}", word(e.kind), t(&e.from.get("name")), t(&e.to.get("name")), yr(&e.to.get("start")), if tv(&q.get("ev")) { " · 누르면 그 사건" } else { "" }));
            V::Obj(q)
        }).collect()));
        V::Obj(o)
    };
    let sig = |lay: &Lay| -> String { lay.nodes.iter().map(|nd| { let u = nd.g.get("uid"); if u.is_nullish() { String::new() } else { t(&u) } }).collect::<Vec<_>>().join("\n") };
    let mut polity_tree: Vec<(V, String)> = Vec::new(); // 나라 uid → 그 나라 나무의 단체 목록(같은 나무인지 견줄 서명)
    for p in list(&model.get("periods")) {
        if !is(&p.get("kind"), "period") || !list(&p.get("groupLinks")).iter().any(|l| is(&l.get("role"), "within")) { continue; }
        let lay = group_tree_layout(&model, &p.get("uid"), &V::Null);
        if lay.nodes.is_empty() { continue; }
        ex.put(&p, "x_groupTree", tree_of(&lay));
        let sg = sig(&lay);
        match polity_tree.iter_mut().find(|(u, _)| js::strict_eq(u, &p.get("uid"))) { Some(x) => x.1 = sg, None => polity_tree.push((p.get("uid"), sg)) }
    }
    for g in &groups_l {
        // 웹 단체 창의 '단체 계보' 단추가 서는 때: 나라를 찾은 있던 나라 · 앞선 단체 · 뒤를 이은 단체 가운데 하나라도
        if !(list(&g.get("withinList")).iter().any(|r| tv(&r.get("polityUid"))) || !list(&g.get("fromList")).is_empty() || !list(&g.get("intoList")).is_empty()) { continue; }
        let lay = group_tree_layout(&model, &or(g.get("polityUid"), V::Null), &g.get("uid"));
        if lay.nodes.is_empty() { continue; }
        let same = tv(&g.get("polityUid")) && polity_tree.iter().find(|(u, _)| js::strict_eq(u, &g.get("polityUid"))).is_some_and(|(_, sg)| *sg == sig(&lay));
        if same { ex.put(g, "x_treeAt", g.get("polityUid")); } else { ex.put(g, "x_groupTree", tree_of(&lay)); }
    }

    /* ---------- 법의 내력 · 의석 막대 (웹 lawVoteIndex — 같은 나라(못 찾으면 같은 트랙) · 같은 법 이름, 날짜 차례 · 같은 때면 제정 → 개정 → 폐지) ---------- */
    let act_no = |a: &V| -> f64 { if is(a, "enact") { 0.0 } else if is(a, "amend") { 1.0 } else if is(a, "repeal") { 2.0 } else { 1.0 } };
    let key_of = |e: &V| -> String { if tv(&e.get("polityUid")) { t(&e.get("polityUid")) } else { format!("track:{}", t(&e.get("track"))) } };
    let mut laws: Vec<(String, Vec<(V, Obj)>)> = Vec::new();
    let mut votes: Vec<(String, Vec<(V, Obj)>)> = Vec::new();
    let push_to = |map: &mut Vec<(String, Vec<(V, Obj)>)>, k: String, v: (V, Obj)| match map.iter_mut().find(|x| x.0 == k) { Some(x) => x.1.push(v), None => map.push((k, vec![v])) };
    for e in &events {
        let law = if tv(&e.get("law")) { groups::read_law(&e.get("law"), &mut |_| {}) } else { None };
        if let Some(l) = law { if tv(&l.get("name")) { push_to(&mut laws, format!("{}|{}", key_of(e), t(&l.get("name"))), (e.clone(), l)); } }
        let el = if tv(&e.get("election")) { groups::read_election(&e.get("election"), &mut |_| {}) } else { None };
        if let Some(el) = el { push_to(&mut votes, key_of(e), (e.clone(), el)); }
    }
    for (_, l) in laws.iter_mut() { js::sort_by(l, |a, b| { let d = n(&a.0.get("start")) - n(&b.0.get("start")); if d != 0.0 && !d.is_nan() { d } else { act_no(&a.1.get("act")) - act_no(&b.1.get("act")) } }); }
    for (_, l) in votes.iter_mut() { js::sort_by(l, |a, b| n(&a.0.get("start")) - n(&b.0.get("start"))); }
    /* 날짜 글의 자세함 'y' · 'm' · 'd' · 'h'(웹 precOf) */
    let prec_of = |x: &V| -> &'static str {
        let at = at_of(w.rc, x, "start");
        let r = if tv(&at) { cal::parse(&w.rc.cal, &at) } else { None };
        match r { Some(r) if r.ok && r.prec != "x" => if r.prec == "min" { "h" } else { r.prec }, _ => "y" }
    };
    /* 두 때 사이의 간격 글(웹 gapText) */
    let gap_text = |a: f64, a_at: &V, b: f64, b_at: &V| -> String {
        let d = b - a;
        if !(d > 1e-6) { return String::new(); }
        let pa = prec_of(&V::Obj(obj! { "start" => a, "startAt" => a_at.clone() }));
        let pb = prec_of(&V::Obj(obj! { "start" => b, "startAt" => b_at.clone() }));
        let fine = |p: &str| p == "d" || p == "h";
        if fine(pa) && fine(pb) {
            let days = js::round(d * 365.2425);
            if days < 62.0 { return format!("{}일 뒤", js::num_str(days)); }
            if days < 730.0 { return format!("{}개월 뒤", js::num_str(js::round(days / 30.44))); }
        } else if pa != "y" && pb != "y" {
            let mo = js::round(d * 12.0);
            if mo < 24.0 { return if mo != 0.0 { format!("{}개월 뒤", js::num_str(mo)) } else { String::new() }; }
        }
        let y = js::round(d);
        if y >= 1.0 { format!("{}년 뒤", js::num_str(y)) } else { "같은 해".into() }
    };
    /* 사건의 자유 날짜 글이 연대와 다르면 '원문 표기'로 남길 글(웹 dateNoteOf) */
    let date_note_of = |x: &V| -> String {
        let text = js::to_str(&or(x.get("date"), s(""))).trim();
        if text.is_empty() { return String::new(); }
        let r = cal::parse(&w.rc.cal, &V::Str(text.clone()));
        match r { Some(r) if r.ok && (r.t - n(&x.get("start"))).abs() < 1e-6 => String::new(), _ => text.as_str().into_owned() }
    };
    /* 그 나라에서 그해에 쓰던 제도 칸(웹 institutionAt) */
    let institution_at = |e: &V, theme: &str, tt: &V| -> Option<(V, V)> {
        if !tv(&e.get("polityUid")) || !tv(&model.get("institutionIndex")) { return None; }
        let bp = model.get("institutionIndex").get("byPolity");
        for inst in list(&or(map_get(&bp, &e.get("polityUid")), va(Vec::new()))) {
            if !is(&inst.get("themeId"), theme) { continue; }
            let sp = list(&inst.get("spanList")).into_iter().find(|sv| n(&sv.get("start")) <= n(tt) && (n(tt) < n(&sv.get("end")) || (js::strict_eq(&sv.get("end"), &inst.get("endY")) && n(tt) <= n(&sv.get("end")))));
            if let Some(sp) = sp { return Some((inst, sp)); }
        }
        None
    };
    let rel = |tag: &str, uid: V, text: V, when: String| -> V { V::Obj(has(&obj! { "tag" => tag, "uid" => uid, "text" => or(text, s("")) }, "when", s(&when))) };
    let num = |v: &V| -> String { if v.is_nullish() { "—".into() } else { group_digits(&V::Num(js::to_num(v))) } };
    let pal: Vec<&str> = vocab::PALETTE.to_vec();
    for x in &events {
        if !is(&x.get("kind"), "event") { continue; }
        let law = if tv(&x.get("law")) { groups::read_law(&x.get("law"), &mut |_| {}) } else { None };
        if let Some(law) = &law {
            let own: Vec<(V, Obj)>;
            let lst: Option<&Vec<(V, Obj)>> = if tv(&law.get("name")) {
                let k = format!("{}|{}", key_of(x), t(&law.get("name")));
                match laws.iter().find(|(kk, _)| *kk == k) { Some((_, l)) => Some(l), None => { own = vec![(x.clone(), law.clone())]; Some(&own) } }
            } else { None };
            let i: i64 = lst.map_or(-1, |l| l.iter().position(|r| eq(&r.0, x)).map_or(-1, |i| i as i64));
            if let Some(l) = lst {
                if !tv(&x.get("treaty")) {
                    // 법의 내력 — 기본 기간 줄 자리(조약은 조약의 날짜 진행 표가 그 자리)
                    let p = if tv(&x.get("polityUid")) { map_get(&by_uid, &x.get("polityUid")) } else { V::Null };
                    struct Row { word: String, t: Option<f64>, at: V, text: String, e: V, here: bool, note: String }
                    let mut rows: Vec<Row> = l.iter().map(|(e, ll)| Row {
                        word: if tv(&ll.get("act")) { law_act_name(&ll.get("act")).to_string() } else { "기록".into() },
                        t: if tv(&e.get("startUnknown")) || e.get("start").is_nullish() { None } else { Some(n(&e.get("start"))) }, at: e.get("startAt"),
                        text: if tv(&e.get("startUnknown")) { "미정".into() } else { format_when(w.rc, e, "start") }, e: e.clone(), here: eq(e, x), note: String::new(),
                    }).collect();
                    let last = l.last();
                    if last.is_none_or(|(_, ll)| !is(&ll.get("act"), "repeal")) {
                        let ended = tv(&p) && !tv(&p.get("ongoing")) && !p.get("endY").is_nullish() && n(&p.get("endY")) < w.current_year;
                        rows.push(Row { word: "폐지".into(), t: None, at: V::Undef, text: "기록 없음".into(), e: V::Undef, here: false, note: if ended { "— 나라가 끝날 때까지 쓴 것으로 봄".into() } else { "— 지금도 쓰는 것으로 봄".into() } });
                    }
                    let outl: Vec<V> = rows.iter().enumerate().map(|(k, r)| {
                        let prev = if k > 0 { rows.get(k - 1) } else { None };
                        let o = obj! { "word" => r.word.as_str(), "when" => r.text.as_str() };
                        if r.here {
                            o.set("here", 1.0);
                            if let Some(tt) = r.t { o.set("at", mm(&V::Num(tt))); }
                        } else if tv(&r.e) { o.set("uid", r.e.get("uid")); o.set("title", or(r.e.get("title"), s(""))); }
                        has(&o, "note", s(&r.note));
                        let gap = match (prev, r.t) { (Some(pv), Some(rt)) if pv.t.is_some() => gap_text(pv.t.expect("때"), &pv.at, rt, &r.at), _ => String::new() };
                        has(&o, "gap", s(&gap));
                        V::Obj(o)
                    }).collect();
                    ex.put(x, "x_lawHistory", V::Obj(has(&obj! { "n" => l.len() as f64, "rows" => va(outl) }, "orig", s(&date_note_of(x)))));
                }
            }
            ex.put(x, "x_lawArts", va(list(&law.get("articles")).iter().map(|a| {
                let sp = treaty::split_articles(a).into_iter().next().map_or_else(|| obj! { "no" => "", "title" => "", "text" => a.clone() }, |o| o);
                V::Obj(has(&has(&has(&Obj::new(), "no", sp.get("no")), "title", sp.get("title")), "text", sp.get("text")))
            }).collect()));
            let mut related: Vec<V> = Vec::new();
            if let Some((inst, sp)) = institution_at(x, "law", &x.get("start")) {
                if map_has(&by_uid, &inst.get("uid")) { related.push(rel("그때의 법률", inst.get("uid"), sp.get("name"), phase_range_text(w, &sp, &inst.get("polityItem")))); }
            }
            let prev = match lst { Some(l) if i > 0 => Some(l[(i - 1) as usize].0.clone()), _ => None };
            if let Some(pv) = prev { related.push(rel("앞 고침", pv.get("uid"), pv.get("title"), format_range(w.rc, &pv))); }
            ex.put(x, "x_lawRelated", va(related));
        }
        let el = if tv(&x.get("election")) { groups::read_election(&x.get("election"), &mut |_| {}) } else { None };
        if let Some(el) = el {
            // 결과의 모임마다: 단체 이름과 같으면 그 단체(이 나라에 있던 단체를 먼저), 아니면 팔레트 색(한 선거 안에서 겹치지 않게 다음 색으로) — 웹 voteRowsOf
            let mut used: Vec<String> = Vec::new();
            struct VRow { who: V, votes: V, seats: V, won: V, group: V, color: V }
            let rows: Vec<VRow> = list(&el.get("results")).iter().map(|r| {
                let same: Vec<V> = groups_l.iter().filter(|g| js::strict_eq(&g.get("name"), &r.get("who"))).cloned().collect();
                let g = same.iter().find(|q| list(&q.get("withinList")).into_iter().chain(list(&q.get("memberList"))).any(|wr| tv(&wr.get("polityUid")) && js::strict_eq(&wr.get("polityUid"), &x.get("polityUid")))).cloned()
                    .or_else(|| same.first().cloned()).unwrap_or(V::Null);
                let mut color = if tv(&g) { g.get("color") } else { auto_color(&s(&format!("party:{}", t(&r.get("who"))))) };
                if !tv(&g) {
                    let k = pal.iter().position(|c| is(&color, c)).map_or(-1i64, |k| k as i64);
                    let mut nn_ = 0;
                    while used.iter().any(|u| is(&color, u)) && nn_ < pal.len() {
                        color = s(pal[((k + nn_ as i64 + 1).rem_euclid(pal.len() as i64)) as usize]);
                        nn_ += 1;
                    }
                }
                used.push(t(&color));
                VRow { who: r.get("who"), votes: r.get("votes"), seats: r.get("seats"), won: r.get("won"), group: if tv(&g) && map_has(&by_uid, &g.get("uid")) { g } else { V::Null }, color }
            }).collect();
            let has_votes = rows.iter().any(|r| !r.votes.is_nullish());
            let has_seats = rows.iter().any(|r| !r.seats.is_nullish());
            let by = if has_seats { "seats" } else if has_votes { "votes" } else { "" };
            let pick = |r: &VRow| -> V { match by { "seats" => r.seats.clone(), "votes" => r.votes.clone(), _ => V::Undef } };
            let total: f64 = if by.is_empty() { 0.0 } else { rows.iter().fold(0.0, |acc, r| acc + n(&or(pick(r), V::Num(0.0)))) };
            let part = |r: &VRow| -> String {
                if by == "seats" { format!("{} {}석", t(&r.who), num(&r.seats)) }
                else { format!("{} {}표 · {}%", t(&r.who), num(&r.votes), to_fixed1((100.0 * n(&or(r.votes.clone(), V::Num(0.0)))) / total)) }
            };
            let o = obj! { "by" => by, "total" => total, "rows" => va(rows.iter().map(|r| {
                let q = obj! { "who" => r.who.clone(), "color" => r.color.clone() };
                if tv(&r.group) { q.set("uid", r.group.get("uid")); }
                if !r.votes.is_nullish() { q.set("votes", r.votes.clone()); }
                if !r.seats.is_nullish() { q.set("seats", r.seats.clone()); }
                if tv(&r.won) { q.set("won", 1.0); }
                if total > 0.0 && tv(&pick(r)) { q.set("part", part(r)); }
                V::Obj(q)
            }).collect()) };
            if total > 0.0 {
                let top = rows.iter().skip(1).fold(&rows[0], |a, r| if n(&or(pick(r), V::Num(0.0))) > n(&or(pick(a), V::Num(0.0))) { r } else { a });
                if by == "seats" {
                    let half = (total / 2.0).floor() + 1.0;
                    o.set("cap", if n(&top.seats) >= half { format!("과반 {}석 — {} {}석", num(&V::Num(half)), t(&top.who), num(&top.seats)) } else { format!("과반 {}석 — 넘은 모임 없음 · 가장 많은 {} {}석", num(&V::Num(half)), t(&top.who), num(&top.seats)) });
                } else {
                    o.set("cap", format!("가장 많은 표 — {} {}%", t(&top.who), to_fixed1((100.0 * n(&or(top.votes.clone(), V::Num(0.0)))) / total)));
                }
            }
            if rows.iter().any(|r| tv(&r.group)) { o.set("linked", 1.0); }
            ex.put(x, "x_vote", V::Obj(o)); // 결과를 적지 않은 선거도 싣는다(rows 빈 목록)
            let mut related: Vec<V> = Vec::new();
            if let Some((inst, sp)) = institution_at(x, "election", &x.get("start")) {
                if map_has(&by_uid, &inst.get("uid")) { related.push(rel("그때의 선거 방식", inst.get("uid"), sp.get("name"), phase_range_text(w, &sp, &inst.get("polityItem")))); }
            }
            let k = key_of(x);
            let empty = Vec::new();
            let lst = votes.iter().find(|(kk, _)| *kk == k).map_or(&empty, |(_, l)| l);
            let i = lst.iter().position(|r| eq(&r.0, x)).map_or(-1i64, |i| i as i64);
            let office = |r: &(V, Obj)| -> String { let of = r.1.get("office"); if tv(&of) && !js::strict_eq(&of, &el.get("office")) { format!(" · {}", t(&of)) } else { String::new() } };
            if i > 0 { let pv = &lst[(i - 1) as usize]; related.push(rel("앞 선거", pv.0.get("uid"), s(&format!("{}{}", t(&pv.0.get("title")), office(pv))), format_range(w.rc, &pv.0))); }
            if i >= 0 && (i as usize) + 1 < lst.len() { let nx = &lst[(i + 1) as usize]; related.push(rel("다음 선거", nx.0.get("uid"), s(&format!("{}{}", t(&nx.0.get("title")), office(nx))), format_range(w.rc, &nx.0))); }
            ex.put(x, "x_voteRelated", va(related));
        }
    }
}

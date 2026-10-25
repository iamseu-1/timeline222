//! `HT.buildModel`의 뒤 절(`js/core.js` 8033 ~ 8826줄 — SHA-256 앞 12자 `9c786cf58566`): 목록을 만든 뒤부터 모델 객체 · `link*` · 칸의 경계까지, JS 절 차례 그대로.
//! 머리(팩 차례 · 패치 · 단체의 띠)는 `lay::model`.
use super::cells::{family_colors, find_theme, group_colors, merge_rank_defs, merge_themes, place_cells, resolve_capitals, resolve_phases, resolve_ranks};
use super::util::{arr, assign_obj, at_of, auto_color, copy, end_in, eq, has, is, item_kind_of, kind_of, le, list, lt, n, nn, ob, or, or_cmp, pastel, s, sub, t, tv, unc_of};
use super::Build;
use crate::lay::js::{self, Arr, Map, Obj, Set, Str, V};
use crate::lay::read::{self, capital, cells as rcells, dates, groups as rgroups, misc, names, treaty, vocab, Ctx as RCtx};

/// `(m.get(k) || [])` — 지도의 목록(배열) 값.
fn list_at(m: &Map, k: &V) -> Vec<V> { list(&m.get(k)) }
/// `pushTo(m, k, v)` — 지도의 목록에 더한다(없으면 만듦).
fn push_to(m: &Map, k: &V, v: V) {
    if !m.has(k) { m.set(k.clone(), Arr::default()); }
    if let V::Arr(a) = m.get(k) { a.push(v); }
}
/// `(x.k || (x.k = [])).push(v)`.
fn push_list(x: &V, k: &str, v: V) {
    let o = ob(x);
    let cur = o.get(k);
    let a = if let V::Arr(a) = cur.clone() { if tv(&cur) { a } else { Arr::default() } } else { Arr::default() };
    if !tv(&cur) { o.set(k, a.clone()); }
    a.push(v);
}
/// `s.includes(sub)`(글 — `String(x)`로 바꿔).
fn includes(s: &V, part: &V) -> bool { js::to_str(s).index_of16(&js::to_str(part), 0.0) >= 0.0 }
/// `ref.includes('/') ? ref : `${packId}/${ref}``.
fn want_of(r: &V, pack_id: &V) -> V { if includes(r, &s("/")) { r.clone() } else { V::from(format!("{}/{}", t(pack_id), t(r))) } }
/// 객체 리터럴의 `{ ...x }`에서 몇 열쇠를 뺀 사본(`({ a, b, ...rest }) => rest`).
fn without(x: &V, keys: &[&str]) -> Obj { let o = copy(x); for k in keys { o.delete(*k); } o }

/// 8101 ~ 8838줄. 머리가 채운 `b`를 받아 모델을 지어 돌려준다.
pub(super) fn rest(b: Build, rc: &RCtx, packs: &[V]) -> crate::Result<V> {
    let Build { tracks, categories, peoples, period_map, event_map, figure_map, group_map, inst_map, epochs, docs, spheres, sphere_map, sphere_warnings, .. } = &b;
    let periods = Arr::new(period_map.values());
    let events = Arr::new(event_map.values());
    // 내가 만든 항목(HT.USER_LISTS)은 user가 없어 없다.
    let figures = Arr::new(figure_map.values());
    // 조약 = treaty 칸이 있는 사건 — 시대 쪽에 든 treaty는 버림
    for p in periods.to_vec() { let o = ob(&p); if o.has("treaty") { o.delete("treaty"); } }
    for e in events.to_vec() { ob(&e).set("itemKind", if tv(&e.get("treaty")) { "treaty" } else { "event" }); }
    events.sort_js(|a, c| sub(&a.get("start"), &c.get("start")));

    for x in periods.to_vec().into_iter().chain(events.to_vec()) {
        if !tracks.has(&x.get("track")) { b.add_track(&V::Obj(o! { "id" => x.get("track"), "name" => x.get("track") })); }
    }
    for e in events.to_vec() {
        let cid = or(e.get("category"), s("etc"));
        if !categories.has(&cid) { b.add_cat(&V::Obj(o! { "id" => cid.clone(), "name" => if is(&cid, "etc") { s("기타") } else { cid.clone() }, "color" => "#a4b1b7" })); }
        let eo = ob(&e);
        eo.set("category", cid.clone());
        eo.set("color", categories.get(&cid).get("color"));
    }

    // 정권 띠: 트랙별로 색을 배정(파스텔로 맞춤)
    let pbt = Map::new();
    for p in periods.to_vec() { push_to(&pbt, &p.get("track"), p); }
    for l in pbt.values() {
        let V::Arr(l) = l else { continue };
        l.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("endY"), &c.get("endY"))));
        for (i, p) in l.to_vec().iter().enumerate() {
            let po = ob(p);
            if !tv(&p.get("color")) { po.set("colorAuto", true); }
            po.set("color", pastel(&or(p.get("color"), s(super::util::POLITY_PALETTE[i % super::util::POLITY_PALETTE.len()]))));
        }
    }
    let same = |track: &V| list_at(&pbt, track);

    // 민족 연결: people에 적힌 id · 이름을 찾고, 없으면 그 이름으로 만든다
    for p in periods.to_vec() {
        let po = ob(&p);
        po.set("polityKind", kind_of(&p));
        let r = if tv(&p.get("people")) { js::to_str(&p.get("people")).trim() } else { Str::default() };
        if r.is_empty() { po.set("peopleId", V::Null); continue; }
        let rv = V::Str(r.clone());
        let find = || { let g = peoples.get(&rv); if tv(&g) { Some(g) } else { peoples.values().into_iter().find(|x| eq(&x.get("name"), &rv)) } };
        let pe = match find() {
            Some(pe) => pe,
            None => {
                let id = V::from(format!("auto-{}", misc::hash(&r)));
                b.add_people(&V::Obj(o! { "id" => id.clone(), "name" => rv.clone(), "auto" => true }));
                peoples.get(&id)
            }
        };
        po.set("peopleId", pe.get("id"));
        po.set("peopleName", pe.get("name"));
        po.set("peopleColor", pe.get("color"));
    }
    // 민족 계층: parent를 따라 뿌리까지의 경로(순환은 끊음)
    let find_people = |r: &V| -> V { let g = peoples.get(r); if tv(&g) { g } else { peoples.values().into_iter().find(|x| eq(&x.get("name"), r)).unwrap_or(V::Null) } };
    for pe in peoples.values() {
        let parent = if tv(&pe.get("parent")) { find_people(&pe.get("parent")) } else { V::Null };
        ob(&pe).set("parentId", if tv(&parent) && !eq(&parent, &pe) { parent.get("id") } else { V::Null });
    }
    for pe in peoples.values() {
        let mut path: Vec<V> = Vec::new();
        let seen = Set::new();
        let mut cur = pe.clone();
        while tv(&cur) && !seen.has(&cur.get("id")) {
            seen.add(cur.get("id"));
            path.insert(0, cur.clone());
            cur = if tv(&cur.get("parentId")) { peoples.get(&cur.get("parentId")) } else { V::Null };
        }
        let o = ob(&pe);
        o.set("path", arr(path.iter().map(|x| x.get("id")).collect()));
        o.set("depth", path.len() as f64 - 1.0);
    }
    for pe in peoples.values() {
        let kids: Vec<V> = peoples.values().into_iter().filter(|x| eq(&x.get("parentId"), &pe.get("id"))).map(|x| x.get("id")).collect();
        ob(&pe).set("children", arr(kids));
    }
    for p in periods.to_vec() {
        let pe = if tv(&p.get("peopleId")) { peoples.get(&p.get("peopleId")) } else { V::Null };
        ob(&p).set("peoplePath", if tv(&pe) { arr(list(&pe.get("path")).iter().map(|id| peoples.get(id)).collect()) } else { arr(Vec::new()) });
    }

    // 소속(partOf): 연맹의 구성국 · 종속국의 종주국 · 조직체가 속한 나라(같은 트랙 우선)
    for p in periods.to_vec() {
        let po = ob(&p);
        po.set("members", arr(Vec::new()));
        po.set("hosts", arr(Vec::new()));
        po.set("dynasties", arr(Vec::new()));
    }
    let all_p = periods.to_vec();
    for p in &all_p {
        let po = ob(p);
        let refs = rcells::read_part_of(rc, &p.get("partOf"), is(&item_kind_of(p), "period"), None);
        let parallel = is(&p.get("polityKind"), "dynasty") || is(&p.get("polityKind"), "overlay");
        let chosen = if parallel { refs } else { list(&place_cells(&arr(refs), p)) };
        for r in chosen {
            let pol = r.get("polity");
            let host = same(&p.get("track")).into_iter().find(|q| !eq(q, p) && (eq(&q.get("name"), &pol) || eq(&q.get("id"), &pol) || eq(&q.get("uid"), &pol)))
                .or_else(|| all_p.iter().find(|q| !eq(q, p) && (eq(&q.get("name"), &pol) || eq(&q.get("uid"), &pol) || (eq(&q.get("packId"), &p.get("packId")) && eq(&q.get("id"), &pol)))).cloned());
            let Some(host) = host else { continue };
            if list(&host.get("hosts")).iter().any(|h| eq(&h.get("host"), p)) { continue; } // 서로 소속은 끊음
            let h = o! {
                "host" => host.clone(), "start" => nn(r.get("start"), V::Null), "end" => nn(r.get("end"), V::Null), "note" => or(r.get("note"), s("")),
                "relation" => or(r.get("relation"), s("")), "nest" => nn(r.get("nest"), V::Null),
            };
            if r.bool("startUnknown") { h.set("startUnknown", true); }
            if r.bool("endUnknown") { h.set("endUnknown", true); }
            assign_obj(&h, &unc_of(&r));
            push_list(p, "hosts", V::Obj(h));
            let members = list(&host.get("members"));
            if !is(&p.get("polityKind"), "dynasty") && !has(&members, p) { push_list(&host, "members", p.clone()); }
        }
        if let V::Arr(hs) = po.get("hosts") { hs.sort_js(|a, c| n(&nn(a.get("start"), p.get("start"))) - n(&nn(c.get("start"), p.get("start")))); }
        let hosts = list(&po.get("hosts"));
        let single = hosts.len() == 1 && {
            let h0 = &hosts[0];
            let rel = h0.get("relation");
            h0.get("start").is_nullish() && h0.get("end").is_nullish() && !h0.bool("startUnknown") && !h0.bool("endUnknown")
                && (matches!(h0.get("nest"), V::Bool(true)) || (h0.get("nest").is_nullish() && (!tv(&rel) || is(&rel, "member"))))
                && (!tv(&rel) || eq(&h0.get("host").get("track"), &p.get("track")))
        };
        po.set("singleHost", single);
        po.set("partOfUid", if hosts.is_empty() { V::Undef } else { hosts[0].get("host").get("uid") });
        po.set("partOfName", if hosts.is_empty() { V::Undef } else { hosts[0].get("host").get("name") });
    }
    for p in &all_p { if let V::Arr(m) = p.get("members") { m.sort_js(|a, c| sub(&a.get("start"), &c.get("start"))); } }
    // 칸의 미정: 이어지는 칸 목록(지도자 · 내각 · 연호)에서 미정인 쪽의 자리
    for p in &all_p {
        for k in ["leaders", "cabinets", "eras"] {
            let v = p.get(k);
            if tv(&v) && tv(&v.get("length")) { ob(p).set(k, place_cells(&v, p)); }
        }
    }
    // 왕조: 다스린 정권마다 왕조 구간(host.dynasties) · 왕조를 적지 않은 지도자는 시작한 해의 왕조로
    for d in &all_p {
        if !is(&d.get("polityKind"), "dynasty") { continue; }
        for h in list(&d.get("hosts")) {
            let host = h.get("host");
            let st = js::max(&[n(&nn(h.get("start"), d.get("start"))), n(&host.get("start"))]);
            let en = js::min(&[n(&nn(h.get("end"), d.get("endY"))), n(&host.get("endY"))]);
            if en < st { continue; }
            let o = o! { "dynasty" => d.clone(), "start" => st, "end" => en, "note" => or(h.get("note"), s("")) };
            assign_obj(&o, &unc_of(&h));
            push_list(&host, "dynasties", V::Obj(o));
        }
    }
    for p in &all_p {
        let dyn_list = list(&p.get("dynasties"));
        if dyn_list.is_empty() { continue; }
        if let V::Arr(ds) = p.get("dynasties") { ds.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("end"), &c.get("end")))); }
        let ds = list(&p.get("dynasties"));
        let leaders = p.get("leaders");
        if !tv(&leaders) || !tv(&leaders.get("length")) { continue; }
        let mapped: Vec<V> = list(&leaders).into_iter().map(|c| {
            if tv(&c.get("dynasty")) {
                let cd = c.get("dynasty");
                let hit = ds.iter().find(|x| { let dy = x.get("dynasty"); eq(&dy.get("name"), &cd) || eq(&dy.get("id"), &cd) || eq(&dy.get("uid"), &cd) });
                return match hit {
                    Some(r) if !eq(&r.get("dynasty").get("name"), &cd) => { let o = copy(&c); o.set("dynasty", r.get("dynasty").get("name")); V::Obj(o) }
                    _ => c,
                };
            }
            let cs = c.get("start");
            let hit = ds.iter().find(|x| le(&x.get("start"), &cs) && lt(&cs, &x.get("end"))).or_else(|| ds.iter().find(|x| le(&x.get("start"), &cs) && le(&cs, &x.get("end"))));
            match hit { Some(h) => { let o = copy(&c); o.set("dynastyAuto", h.get("dynasty").get("name")); V::Obj(o) } None => c }
        }).collect();
        ob(p).set("leaders", arr(mapped));
    }
    // 지명 사전: 도읍의 도시를 지명의 id로 적었으면 모델의 사본에서는 그 지명의 이름으로
    {
        let ids = Map::new();
        for pack in packs { for pl in list(&pack.get("places")) { if !ids.has(&pl.get("id")) { ids.set(pl.get("id"), pl); } } }
        let names_set = Set::new();
        for pl in ids.values() { names_set.add(pl.get("name")); }
        let by_id = |c: &V| -> V {
            let made = capital::normalize_capital(rc, c, None);
            let Some(nm) = made else { return c.clone() };
            let city = nm.get("city");
            let pl = if !names_set.has(&city) { ids.get(&city) } else { V::Null };
            if !tv(&pl) { return c.clone(); }
            nm.set("city", pl.get("name"));
            nm.set("placeId", pl.get("id"));
            if !tv(&nm.get("as")) { nm.set("docName", city); }
            V::Obj(nm)
        };
        if !ids.is_empty() {
            for p in &all_p {
                let caps = p.get("capitals");
                if tv(&caps) && tv(&caps.get("length")) { ob(p).set("capitals", arr(list(&caps).iter().map(&by_id).collect())); }
            }
        }
    }
    // 도읍: 역할 · 끝 · 표시 이름
    for p in &all_p {
        let caps = p.get("capitals");
        if tv(&caps) && tv(&caps.get("length")) { ob(p).set("capitals", arr(resolve_capitals(rc, p))); }
    }
    // 시기 구분(학계): 빈 경계를 채운 모델 전용 사본
    for p in &all_p {
        let ph = if tv(&p.get("phases")) && is(&item_kind_of(p), "period") { resolve_phases(rc, p) } else { None };
        if let Some(ph) = ph { ob(p).set("phaseSchemes", ph); }
    }
    // 지위: 켠 DLC들의 사전 + 내장 사전, 정권마다 지위 구간(rankSpans)과 지도자의 짐작한 지위(rankAuto)
    let rank_defs = Arr::new(merge_rank_defs(packs));
    let rank_list = rank_defs.to_vec();
    for p in &all_p {
        if !(is(&item_kind_of(p), "period") && (tv(&p.get("ranks")) || tv(&p.get("leaders")))) { continue; }
        let Some((spans, leaders)) = resolve_ranks(rc, p, &rank_list) else { continue };
        ob(p).set("rankSpans", arr(spans));
        if let Some(l) = leaders { ob(p).set("leaders", arr(l)); }
    }
    // 사건의 소속 정권을 해로 짐작(기관 · 왕조 · 단체의 띠는 고르지 않음). 직접 적으면 그대로
    let aside = |p: &V| is(&p.get("polityKind"), "overlay") || is(&p.get("polityKind"), "dynasty");
    let all_e = events.to_vec();
    for e in &all_e {
        let l = same(&e.get("track"));
        let mut target: Option<V> = None;
        if tv(&e.get("polity")) {
            let pol = e.get("polity");
            let want = want_of(&pol, &e.get("packId"));
            target = l.iter().find(|p| eq(&p.get("uid"), &want) || eq(&p.get("id"), &pol) || eq(&p.get("name"), &pol)).cloned();
        }
        if target.is_none() {
            let es = e.get("start");
            let hit: Vec<V> = l.iter().filter(|p| !aside(p) && !tv(&p.get("groupUid")) && le(&p.get("start"), &es) && le(&es, &end_in(rc, p))).cloned().collect();
            if hit.len() == 1 { target = Some(hit[0].clone()); }
            else if hit.len() > 1 {
                let title = or(e.get("title"), s(""));
                let score = |p: &V| -> f64 {
                    (if includes(&title, &p.get("name")) { 100.0 } else { 0.0 })
                        + (if lt(&p.get("start"), &es) && lt(&es, &p.get("endY")) { 10.0 } else { 0.0 })
                        + (if dates::year_of_t(n(&es)) == dates::year_of_t(n(&p.get("endY"))) { 5.0 } else { 0.0 })
                };
                let mut acc = hit[0].clone();
                for c in &hit[1..] {
                    let d = score(c) - score(&acc);
                    acc = if d != 0.0 { if d > 0.0 { c.clone() } else { acc } } else if sub(&c.get("endY"), &c.get("start")) < sub(&acc.get("endY"), &acc.get("start")) { c.clone() } else { acc };
                }
                target = Some(acc);
            }
        }
        let eo = ob(e);
        eo.set("polityUid", target.as_ref().map_or(V::Null, |x| x.get("uid")));
        eo.set("polityName", target.as_ref().map_or(V::Null, |x| x.get("name")));
        eo.set("polityColor", target.as_ref().map_or(V::Null, |x| x.get("color")));
    }

    // 승계 관계: 이름 · id로 적힌 선대 정권을 찾아 연결(같은 트랙 우선)
    for p in &all_p {
        let po = ob(p);
        if is(&p.get("polityKind"), "culture") {
            if let V::Arr(sx) = p.get("successors") { if sx.to_vec().iter().all(|x| matches!(x, V::Str(_))) { po.set("successorNames", V::Arr(sx)); } }
        }
        po.set("successors", arr(Vec::new()));
        po.set("predecessors", arr(Vec::new()));
    }
    for p in &all_p {
        for link in list(&p.get("succeeds")) {
            let from_ref = link.get("from");
            let from = same(&p.get("track")).into_iter().find(|q| !eq(q, p) && (eq(&q.get("name"), &from_ref) || eq(&q.get("id"), &from_ref) || eq(&q.get("uid"), &from_ref)))
                .or_else(|| all_p.iter().find(|q| !eq(q, p) && (eq(&q.get("name"), &from_ref) || eq(&q.get("uid"), &from_ref))).cloned());
            let Some(from) = from else { continue };
            if list(&p.get("predecessors")).iter().any(|e| eq(&e.get("from"), &from)) { continue; }
            let edge = o! { "from" => from.clone(), "to" => p.clone(), "type" => link.get("type"), "note" => or(link.get("note"), s("")) };
            if is(&link.get("type"), "partial") {
                edge.set("degree", vocab::succ_degree(&link.get("degree")).filter(|d| *d != 0.0).unwrap_or(vocab::SUCC_DEGREE_DEFAULT));
                edge.set("parts", arr(list(&or(link.get("parts"), arr(Vec::new())))));
            }
            push_list(p, "predecessors", V::Obj(edge.clone()));
            push_list(&from, "successors", V::Obj(edge));
        }
    }
    // 문화 쪽에서 적은 승계국 — 그 국가 줄 밑에 바탕 띠로
    for c in &all_p {
        if !is(&c.get("polityKind"), "culture") || !tv(&c.get("successorNames")) { continue; }
        for r in list(&c.get("successorNames")) {
            let to = same(&c.get("track")).into_iter().find(|q| !eq(q, c) && (eq(&q.get("name"), &r) || eq(&q.get("id"), &r) || eq(&q.get("uid"), &r)))
                .or_else(|| all_p.iter().find(|q| !eq(q, c) && (eq(&q.get("name"), &r) || eq(&q.get("uid"), &r))).cloned());
            let Some(to) = to else { continue };
            if list(&to.get("predecessors")).iter().any(|e| eq(&e.get("from"), c)) { continue; }
            let edge = V::Obj(o! { "from" => c.clone(), "to" => to.clone(), "type" => "indirect", "note" => "" });
            push_list(&to, "predecessors", edge.clone());
            push_list(c, "successors", edge);
        }
    }

    // 부모 · 자식 사건(큰 전쟁 안의 전투 등)
    let event_by_uid = Map::new();
    for e in &all_e { event_by_uid.set(e.get("uid"), e.clone()); }
    let find_event = |r: &V, pack_id: &V| -> Option<V> {
        let want = want_of(r, pack_id);
        let g = event_by_uid.get(&want);
        if tv(&g) { return Some(g); }
        all_e.iter().find(|x| eq(&x.get("packId"), pack_id) && eq(&x.get("title"), r)).or_else(|| all_e.iter().find(|x| eq(&x.get("title"), r))).cloned()
    };
    for e in &all_e {
        if !tv(&e.get("parent")) { continue; }
        let Some(parent) = find_event(&e.get("parent"), &e.get("packId")) else { continue };
        if eq(&parent, e) { continue; }
        let eo = ob(e);
        eo.set("parentUid", parent.get("uid"));
        eo.set("parentTitle", parent.get("title"));
        if !tv(&e.get("polity")) {
            eo.set("polityUid", parent.get("polityUid"));
            eo.set("polityName", parent.get("polityName"));
            eo.set("polityColor", parent.get("polityColor"));
        }
        push_list(&parent, "children", e.clone());
    }
    for e in &all_e { if let V::Arr(ch) = e.get("children") { if tv(&e.get("children")) { ch.sort_js(|a, c| sub(&a.get("start"), &c.get("start"))); } } }

    // 공동 사건 — 같은 사건을 여러 정권 · 나라 줄에 함께 찍는다
    let find_polity = |track_id: &V, r: &V, year: &V, prefer_big: bool| -> Option<V> {
        let l = same(track_id);
        if tv(r) { if let Some(p) = l.iter().find(|x| eq(&x.get("name"), r) || eq(&x.get("id"), r) || eq(&x.get("uid"), r)) { return Some(p.clone()); } }
        let hit: Vec<V> = l.iter().filter(|p| !aside(p) && !tv(&p.get("groupUid")) && le(&p.get("start"), year) && le(year, &end_in(rc, p))).cloned().collect();
        let mut it = hit.into_iter();
        let mut acc = it.next()?;
        for c in it {
            let (bl, al) = (sub(&c.get("endY"), &c.get("start")), sub(&acc.get("endY"), &acc.get("start")));
            acc = if prefer_big { if bl > al { c } else { acc } } else if bl < al { c } else { acc };
        }
        Some(acc)
    };
    let all_tracks = || tracks.values();
    // 조약의 당사국 { track?, polity } → 연표의 정권(찾은 것은 모델 전용 칸 treatyRefs에만)
    let treaty_parties = |e: &V| -> Vec<(Option<V>, Obj)> {
        let parties = treaty::read_treaty(rc, &V::Obj(o! { "parties" => e.get("treaty").get("parties") }), &mut |_| {}).map_or(V::Undef, |r| r.get("parties"));
        list(&or(parties, arr(Vec::new()))).into_iter().map(|pt| {
            let r = or(pt.get("polity"), s(""));
            let tid = or(pt.get("track"), s(""));
            let is_it = |q: &V| !is(&q.get("polityKind"), "dynasty") && (eq(&q.get("name"), &r) || eq(&q.get("id"), &r) || eq(&q.get("uid"), &r));
            let mut p: Option<V> = if tv(&r) {
                same(&or(tid.clone(), e.get("track"))).into_iter().find(|q| is_it(q)).or_else(|| if tv(&tid) { None } else { all_p.iter().find(|q| is_it(q)).cloned() })
            } else { None };
            let by_name = p.is_some();
            if p.is_none() {
                let tr = if tv(&tid) { let g = tracks.get(&tid); if tv(&g) { Some(g) } else { None } } else { all_tracks().into_iter().find(|x| eq(&x.get("id"), &r) || eq(&x.get("name"), &r)) };
                if let Some(tr) = tr { p = find_polity(&tr.get("id"), &V::Null, &e.get("start"), !eq(&tr.get("id"), &e.get("track"))); }
            }
            let pv = p.clone().unwrap_or(V::Null);
            let name = if p.is_some() { pv.get("name") } else { or(or(r.clone(), { let g = tracks.get(&tid); if tv(&g) { g.get("name") } else { V::Undef } }), tid.clone()) };
            let o = o! {
                "p" => pv.clone(), "track" => if p.is_some() { pv.get("track") } else { or(tid.clone(), e.get("track")) }, "polity" => r.clone(),
                "uid" => if p.is_some() { pv.get("uid") } else { V::Null }, "name" => name, "color" => if p.is_some() { pv.get("color") } else { V::Null },
                "byName" => by_name, "side" => nn(pt.get("side"), V::Null), "role" => or(pt.get("role"), s("")),
                "signatories" => arr(treaty::read_signers(&pt.get("signatories"))),
            };
            (p, o)
        }).collect()
    };
    // 조약의 제 자리(첫 자리)도 당사국 가운데서
    for e in &all_e {
        if !tv(&e.get("treaty")) || tv(&e.get("polity")) { continue; }
        let own = treaty_parties(e).into_iter().find(|(p, x)| p.is_some() && eq(&x.get("track"), &e.get("track")));
        if let Some((_, x)) = own {
            let eo = ob(e);
            eo.set("polityUid", x.get("uid"));
            eo.set("polityName", x.get("name"));
            eo.set("polityColor", x.get("color"));
        }
    }
    for e in &all_e {
        let places: std::cell::RefCell<Vec<V>> = std::cell::RefCell::new(vec![V::Obj(o! { "track" => e.get("track"), "polityUid" => e.get("polityUid"), "polityName" => e.get("polityName"), "polityColor" => e.get("polityColor") })]);
        let add = |track_id: &V, p: &Option<V>| {
            let uid = p.as_ref().map_or(V::Null, |x| x.get("uid"));
            if places.borrow().iter().any(|x| eq(&x.get("track"), track_id) && eq(&x.get("polityUid"), &uid)) { return; }
            let pv = p.clone().unwrap_or(V::Null);
            places.borrow_mut().push(V::Obj(o! {
                "track" => track_id.clone(), "polityUid" => uid, "polityName" => if p.is_some() { pv.get("name") } else { V::Null }, "polityColor" => if p.is_some() { pv.get("color") } else { V::Null },
            }));
        };
        for r in list(&e.get("polities")) { add(&e.get("track"), &find_polity(&e.get("track"), &r, &e.get("start"), false)); }
        for tr in list(&e.get("tracks")) {
            let parts = read::split_units(&js::to_str(&tr), &[0x3A]);
            let tid = V::Str(parts[0].clone());
            let r = parts.get(1).map_or(V::Undef, |x| V::Str(x.clone()));
            if eq(&tid, &e.get("track")) || !tracks.has(&tid) { continue; }
            add(&tid, &find_polity(&tid, &r, &e.get("start"), true));
        }
        let eo = ob(e);
        if tv(&e.get("treaty")) {
            let refs: Vec<V> = treaty_parties(e).into_iter().map(|(p, x)| {
                if let Some(p) = &p { add(&p.get("track"), &Some(p.clone())); }
                V::Obj(without(&V::Obj(x), &["p"]))
            }).collect();
            eo.set("treatyRefs", o! { "parties" => arr(refs) });
        }
        let pl = places.into_inner();
        let shared = pl.len() > 1;
        eo.set("placements", arr(pl.clone()));
        eo.set("shared", shared);
        if shared {
            let with: Vec<V> = pl[1..].iter().map(|p| { let tg = tracks.get(&p.get("track")); or(or(p.get("polityName"), if tv(&tg) { tg.get("name") } else { V::Undef }), p.get("track")) }).collect();
            eo.set("sharedWith", arr(with));
        }
    }
    // 조약의 관련: 끝낸 전쟁(concludes) · 대체한 조약(supersedes) — 거꾸로 가리키는 것은 가리켜진 사건의 treatyBackRefs에
    for e in &all_e {
        let refs = e.get("treatyRefs");
        if !tv(&refs) { continue; }
        for (key, back) in [("concludes", "concludedBy"), ("supersedes", "supersededBy")] {
            let tk = e.get("treaty").get(key);
            let r = if tv(&tk) { V::Str(js::to_str(&tk)) } else { s("") };
            let hit = if tv(&r) { find_event(&r, &e.get("packId")) } else { None };
            let val = match &hit { Some(h) if !eq(h, e) => h.get("uid"), _ => V::Null };
            ob(&refs).set(key, val.clone());
            if !tv(&val) { continue; }
            let h = hit.expect("찾은 사건");
            let mut bk = h.get("treatyBackRefs");
            if !tv(&bk) { bk = V::Obj(o! { "concludedBy" => arr(Vec::new()), "supersededBy" => arr(Vec::new()) }); ob(&h).set("treatyBackRefs", bk.clone()); }
            if let V::Arr(l) = bk.get(back) { l.push(e.get("uid")); }
        }
    }

    // 인물 — 시기와 섬긴 정권을 푼다
    for p in &all_p { ob(p).set("servedBy", arr(Vec::new())); }
    let lineage = Arr::default();
    {
        let mut keep = Vec::new();
        for f in figures.to_vec() { if matches!(f.get("lineageOnly"), V::Bool(true)) { lineage.push(f); } else { keep.push(f); } }
        if !lineage.is_empty() { *figures.borrow_mut() = keep; }
        for f in lineage.to_vec() {
            let fo = ob(&f);
            let ts: Vec<f64> = ["birth", "start", "end", "death"].iter().filter_map(|k| f.get(*k).as_num()).filter(|x| x.is_finite()).collect();
            fo.set("spanMin", if ts.is_empty() { V::Null } else { V::Num(js::min(&ts)) });
            fo.set("spanMax", if ts.is_empty() { V::Null } else { V::Num(js::max(&ts)) });
            fo.set("certainty", "accepted");
            fo.set("events", arr(Vec::new()));
            fo.set("services", arr(Vec::new()));
            // f.polityUid = f.polityName = f.polityColor = null — 오른쪽부터 쓴다
            fo.set("polityColor", V::Null);
            fo.set("polityName", V::Null);
            fo.set("polityUid", V::Null);
            let tg = tracks.get(&f.get("track"));
            fo.set("color", or(if tv(&tg) { tg.get("color") } else { V::Undef }, s("#a4b1b7")));
        }
    }
    let figure_polity = |track_id: &V, r: &V, year: &V| -> Option<V> {
        let l: Vec<V> = same(track_id).into_iter().filter(|p| !is(&p.get("polityKind"), "dynasty")).collect();
        if let Some(p) = l.iter().find(|p| eq(&p.get("uid"), r) || eq(&p.get("id"), r)) { return Some(p.clone()); }
        let named: Vec<V> = l.iter().filter(|p| eq(&p.get("name"), r)).cloned().collect();
        if !year.is_nullish() { if let Some(p) = named.iter().find(|p| le(&p.get("start"), year) && le(year, &end_in(rc, p))) { return Some(p.clone()); } }
        named.first().cloned()
    };
    /// `{ t, at }`(`pt(t, at)` — t가 없으면 None).
    #[derive(Clone)]
    struct Pt { t: V, at: V }
    let pt = |tt: V, at: V| -> Option<Pt> { if tt.is_nullish() { None } else { Some(Pt { t: tt, at: or(at, V::Undef) }) } };
    let min_of = |l: Vec<Pt>| -> Option<Pt> { let mut it = l.into_iter(); let mut a = it.next()?; for c in it { if lt(&c.t, &a.t) { a = c; } } Some(a) };
    let max_of = |l: Vec<Pt>| -> Option<Pt> { let mut it = l.into_iter(); let mut a = it.next()?; for c in it { if lt(&a.t, &c.t) { a = c; } } Some(a) };
    for f in figures.to_vec() {
        let fo = ob(&f);
        let raw = if let V::Arr(a) = f.get("service") { a.to_vec() } else { Vec::new() };
        let from = pt(f.get("start"), at_of(rc, &f, "start"))
            .or_else(|| min_of(raw.iter().filter_map(|sv| pt(nn(sv.get("start"), sv.get("end")), if !sv.get("start").is_nullish() { sv.get("startAt") } else { sv.get("endAt") })).collect()))
            .or_else(|| pt(f.get("birth"), f.get("birthAt"))).or_else(|| pt(f.get("end"), f.get("endAt"))).or_else(|| pt(f.get("death"), f.get("deathAt")));
        let Some(from) = from else { continue };
        fo.set("startAuto", f.get("start").is_nullish());
        fo.set("start", from.t.clone());
        fo.set("startAt", from.at.clone());
        let to0 = if f.bool("ongoing") { pt(V::Num(js::max(&[rc.now_t, n(&f.get("start"))])), V::Undef) } else { pt(f.get("end"), at_of(rc, &f, "end")) };
        fo.set("endAuto", to0.is_none());
        let to = to0.or_else(|| max_of(raw.iter().filter_map(|sv| pt(nn(sv.get("end"), sv.get("start")), if !sv.get("end").is_nullish() { sv.get("endAt") } else { sv.get("startAt") })).collect()))
            .or_else(|| pt(f.get("death"), f.get("deathAt"))).unwrap_or_else(|| from.clone());
        let fs = f.get("start");
        fo.set("endY", if lt(&to.t, &fs) { V::Num(js::max(&[n(&fs), n(&dates::end_bound(rc, &to.t, &to.at))])) } else { to.t.clone() });
        fo.set("endYAt", to.at.clone());
        fo.set("certainty", "accepted");
        fo.set("spanMin", js::min(&[n(&fs), n(&nn(f.get("birth"), fs.clone()))]));
        fo.set("spanMax", js::max(&[n(&f.get("endY")), n(&nn(f.get("death"), f.get("endY")))]));
        fo.set("events", arr(Vec::new()));
        let services: Vec<V> = raw.iter().map(|sv| {
            let a = nn(sv.get("start"), f.get("start"));
            let bb = nn(sv.get("end"), f.get("endY"));
            let track_id = or(sv.get("track"), f.get("track"));
            let p = figure_polity(&track_id, &sv.get("polity"), &V::Num((n(&a) + n(&bb)) / 2.0));
            let pv = p.clone().unwrap_or(V::Null);
            let o = o! {
                "polity" => pv.clone(), "polityUid" => if p.is_some() { pv.get("uid") } else { V::Null }, "polityName" => if p.is_some() { pv.get("name") } else { sv.get("polity") },
                "track" => if p.is_some() { pv.get("track") } else { track_id.clone() }, "color" => if p.is_some() { pv.get("color") } else { V::Null },
                "office" => or(sv.get("office"), s("")), "note" => or(sv.get("note"), s("")), "given" => !sv.get("start").is_nullish() || !sv.get("end").is_nullish(),
                "from" => a.clone(), "fromAt" => if !sv.get("start").is_nullish() { sv.get("startAt") } else { f.get("startAt") },
                "to" => bb.clone(), "toAt" => if !sv.get("end").is_nullish() { sv.get("endAt") } else { f.get("endYAt") }, "auto" => false,
            };
            if sv.bool("startUnknown") || (sv.get("start").is_nullish() && f.bool("startUnknown")) { o.set("fromUnknown", true); }
            if sv.bool("endUnknown") || (sv.get("end").is_nullish() && f.bool("endUnknown")) { o.set("toUnknown", true); }
            assign_obj(&o, &unc_of(sv));
            o.set("start", if p.is_some() { V::Num(js::max(&[n(&a), n(&pv.get("start"))])) } else { a.clone() });
            o.set("endY", if p.is_some() { V::Num(js::min(&[n(&bb), n(&pv.get("endY"))])) } else { bb.clone() });
            o.set("shown", p.is_some() && le(&o.get("start"), &o.get("endY")));
            V::Obj(o)
        }).collect();
        let services = Arr::new(services);
        fo.set("services", services.clone());
        if raw.is_empty() {
            let mid = V::Num((n(&f.get("start")) + n(&f.get("endY"))) / 2.0);
            if let Some(p) = find_polity(&f.get("track"), &V::Null, &mid, false) {
                let o = o! {
                    "polity" => p.clone(), "polityUid" => p.get("uid"), "polityName" => p.get("name"), "track" => p.get("track"), "color" => p.get("color"), "office" => "", "note" => "",
                    "given" => false, "from" => f.get("start"), "fromAt" => f.get("startAt"), "to" => f.get("endY"), "toAt" => f.get("endYAt"), "auto" => true,
                    "start" => js::max(&[n(&f.get("start")), n(&p.get("start"))]), "endY" => js::min(&[n(&f.get("endY")), n(&p.get("endY"))]), "shown" => true,
                };
                if f.bool("startUnknown") { o.set("fromUnknown", true); }
                if f.bool("endUnknown") { o.set("toUnknown", true); }
                services.push(o);
            }
        }
        for sv in services.to_vec() { if tv(&sv.get("polity")) { push_list(&sv.get("polity"), "servedBy", V::Obj(o! { "figure" => f.clone(), "service" => sv.clone() })); } }
        let first = services.to_vec().into_iter().find(|sv| tv(&sv.get("polity")));
        fo.set("polityUid", first.as_ref().map_or(V::Null, |x| x.get("polityUid")));
        fo.set("polityName", first.as_ref().map_or(V::Null, |x| x.get("polityName")));
        fo.set("polityColor", first.as_ref().map_or(V::Null, |x| x.get("color")));
        let tg = tracks.get(&f.get("track"));
        fo.set("color", or(or(f.get("polityColor"), if tv(&tg) { tg.get("color") } else { V::Undef }), s("#a4b1b7")));
    }
    figures.borrow_mut().retain(|f| !f.get("endY").is_nullish());
    figures.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("endY"), &c.get("endY"))));
    for p in &all_p {
        if let V::Arr(l) = p.get("servedBy") {
            l.sort_js(|a, c| or_cmp(sub(&a.get("service").get("start"), &c.get("service").get("start")),
                || n(&or(c.get("figure").get("importance"), V::Num(2.0))) - n(&or(a.get("figure").get("importance"), V::Num(2.0)))));
        }
    }
    // 사건의 관련 인물(events[].figures) → 모델 전용 figureRefs · 인물 쪽에는 events
    let fig_all: Vec<V> = figures.to_vec().into_iter().chain(lineage.to_vec()).collect();
    let fig_index: std::cell::RefCell<Option<Map>> = std::cell::RefCell::new(None);
    let find_figure = |r: &V, e: &V| -> Option<V> {
        if fig_index.borrow().is_none() {
            let m = Map::new();
            let add = |nm: &V, k: usize| {
                if !tv(nm) { return; }
                match m.get(nm) {
                    V::Arr(l) => { if !eq(&l.get(l.len() - 1), &V::Num(k as f64)) { l.push(V::Num(k as f64)); } }
                    _ => m.set(nm.clone(), Arr::new(vec![V::Num(k as f64)])),
                }
            };
            for (k, f) in fig_all.iter().enumerate() {
                add(&f.get("uid"), k);
                add(&f.get("name"), k);
                if tv(&f.get("aka")) { for nm in list(&f.get("aka")) { add(&nm, k); } }
            }
            *fig_index.borrow_mut() = Some(m);
        }
        let ix = fig_index.borrow().clone().expect("색인");
        let want = want_of(r, &e.get("packId"));
        let ks = Set::new();
        for k in list_at(&ix, &want).into_iter().chain(list_at(&ix, r)) { ks.add(k); }
        let mut ks = ks.values();
        js::sort(&mut ks, sub);
        let hit: Vec<V> = ks.iter().map(|k| fig_all[n(k) as usize].clone())
            .filter(|f| eq(&f.get("uid"), &want) || eq(&f.get("name"), r) || has(&list(&f.get("aka")), r)).collect();
        if hit.len() < 2 { return hit.first().cloned(); }
        let score = |f: &V| -> f64 {
            (if eq(&f.get("uid"), &want) { 100.0 } else { 0.0 }) + (if eq(&f.get("track"), &e.get("track")) { 10.0 } else { 0.0 })
                + (if le(&f.get("spanMin"), &e.get("start")) && n(&e.get("start")) <= n(&f.get("spanMax")) + 1.0 { 5.0 } else { 0.0 })
        };
        let mut acc = hit[0].clone();
        for c in &hit[1..] { if score(c) > score(&acc) { acc = c.clone(); } }
        Some(acc)
    };
    for e in &all_e {
        let V::Arr(fl) = e.get("figures") else { continue };
        if fl.is_empty() { continue; }
        let refs: Vec<V> = fl.to_vec().iter().map(|name| {
            let nm = V::Str(js::to_str(name));
            let f = find_figure(&nm, e);
            if let Some(f) = &f { if !has(&list(&f.get("events")), e) { push_list(f, "events", e.clone()); } }
            V::Obj(o! { "name" => nm, "uid" => f.map_or(V::Null, |f| f.get("uid")) })
        }).collect();
        ob(e).set("figureRefs", arr(refs));
    }

    let by_uid = Map::new();
    for x in all_p.iter().chain(all_e.iter()).cloned().chain(epochs.to_vec()) { by_uid.set(x.get("uid"), x); }
    for x in figures.to_vec() { by_uid.set(x.get("uid"), x); }
    for x in lineage.to_vec() { by_uid.set(x.get("uid"), x); }
    for e in epochs.to_vec() {
        let tr = if tv(&e.get("track")) { tracks.get(&e.get("track")) } else { V::Null };
        ob(&e).set("trackName", if tv(&tr) { tr.get("name") } else { s("") });
    }

    // 대범위: 구성 정권 · 상징적 본국 · 시대 구분을 모델 항목으로 풀고, 정권 쪽에 역참조
    let scopes = Arr::default();
    {
        let polity_in = |r: &rcells::ScopeRef, track_id: &V, pack_id: &V| -> V {
            let tk = match &r.track { Some(x) if !x.is_empty() => V::Str(x.clone()), _ => track_id.clone() };
            let pol = V::Str(r.polity.clone());
            let ok = |q: &V| is(&q.get("itemKind"), "period");
            same(&tk).into_iter().find(|q| ok(q) && (eq(&q.get("name"), &pol) || eq(&q.get("id"), &pol) || eq(&q.get("uid"), &pol)))
                .or_else(|| all_p.iter().find(|q| ok(q) && (eq(&q.get("uid"), &pol) || (r.track.as_ref().is_none_or(|x| x.is_empty()) && eq(&q.get("packId"), pack_id) && eq(&q.get("id"), &pol)))).cloned())
                .unwrap_or(V::Null)
        };
        let eps = epochs.to_vec();
        let epoch_of = |r: &V, track_id: &V, pack_id: &V| -> V {
            eps.iter().find(|e| eq(&e.get("packId"), pack_id) && (eq(&e.get("id"), r) || eq(&e.get("name"), r)) && (!tv(&e.get("track")) || eq(&e.get("track"), track_id)))
                .or_else(|| eps.iter().find(|e| eq(&e.get("uid"), r)))
                .or_else(|| eps.iter().find(|e| eq(&e.get("name"), r) && eq(&e.get("track"), track_id)))
                .or_else(|| eps.iter().find(|e| eq(&e.get("name"), r))).cloned().unwrap_or(V::Null)
        };
        for pack in packs {
            for raw in list(&pack.get("scopes")) {
                let warnings = Arr::default();
                let ep = if tv(&raw.get("epoch")) { epoch_of(&raw.get("epoch"), &raw.get("track"), &pack.get("id")) } else { V::Null };
                if tv(&raw.get("epoch")) && !tv(&ep) { warnings.push(format!("시대 구분 \"{}\"을(를) 찾지 못했습니다.", t(&raw.get("epoch")))); }
                let host_ref = rcells::read_scope_ref(&raw.get("host"));
                let host = host_ref.as_ref().map_or(V::Null, |r| polity_in(r, &raw.get("track"), &pack.get("id")));
                if host_ref.is_some() && !tv(&host) { warnings.push(format!("상징적 본국 \"{}\"을(를) 연표에서 찾지 못했습니다.", host_ref.as_ref().expect("참조").polity)); }
                else if tv(&host) && !eq(&host.get("track"), &raw.get("track")) { warnings.push(format!("상징적 본국 \"{}\"이(가) 다른 트랙에 있어 그 줄 아래에 모이지 않습니다.", t(&host.get("name")))); }
                let mut members: Vec<V> = Vec::new();
                for r in rcells::read_scope_refs(&raw.get("members")) {
                    let m = polity_in(&r, &raw.get("track"), &pack.get("id"));
                    if !tv(&m) { warnings.push(format!("구성 정권 \"{}\"을(를) 연표에서 찾지 못했습니다.", r.polity)); }
                    else if eq(&m, &host) { warnings.push(format!("상징적 본국 \"{}\"이(가) 구성 정권에도 들어 있습니다 — 본국은 모이지 않습니다.", t(&m.get("name")))); }
                    else if !has(&members, &m) {
                        if !eq(&m.get("track"), &raw.get("track")) { warnings.push(format!("구성 정권 \"{}\"은(는) 다른 트랙에 있어 모이지 않습니다 — 구성 정권은 같은 트랙 안에서만 모입니다.", t(&m.get("name")))); }
                        members.push(m);
                    }
                }
                js::sort(&mut members, |a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("endY"), &c.get("endY"))));
                let members_a = Arr::new(members.clone());
                let o = copy(&raw);
                assign_obj(&o, &o! {
                    "kind" => "scope", "itemKind" => "scope", "uid" => format!("{}/{}", t(&pack.get("id")), t(&raw.get("id"))), "packId" => pack.get("id"), "packName" => pack.get("name"),
                    "memberRefs" => raw.get("members"), "members" => members_a, "hostRef" => nn(raw.get("host"), V::Null), "host" => host.clone(),
                    "epochRef" => nn(raw.get("epoch"), V::Null), "epoch" => ep.clone(), "warnings" => warnings, "default" => matches!(raw.get("default"), V::Bool(true)),
                });
                if !tv(&o.get("name")) { assign_obj(&o, &o! { "name" => if tv(&ep) { ep.get("name") } else { s("대범위") }, "nameAuto" => true }); }
                if raw.get("start").is_nullish() {
                    let own: Vec<V> = members.iter().filter(|m| eq(&m.get("track"), &raw.get("track"))).cloned().collect();
                    let l = if !own.is_empty() { own } else { members.clone() };
                    if tv(&ep) { assign_obj(&o, &o! { "start" => ep.get("start"), "startAt" => ep.get("startAt"), "end" => ep.get("end"), "endAt" => ep.get("endAt"), "ongoing" => ep.get("ongoing"), "rangeFrom" => "epoch" }); }
                    else if !l.is_empty() {
                        let st: Vec<f64> = l.iter().map(|m| n(&m.get("start"))).collect();
                        let en: Vec<f64> = l.iter().map(|m| n(&m.get("endY"))).collect();
                        assign_obj(&o, &o! { "start" => js::min(&st), "end" => js::max(&en), "rangeFrom" => "members" });
                    } else { continue; }
                    // o.startAuto = o.endAuto = true — 오른쪽부터 쓴다
                    o.set("endAuto", true);
                    o.set("startAuto", true);
                }
                o.set("endY", if o.bool("ongoing") { V::Num(js::max(&[rc.now_t, n(&o.get("start"))])) } else { nn(o.get("end"), o.get("start")) });
                if !misc::is_color(&raw.get("color")) { o.set("colorAuto", true); }
                let uid_v = o.get("uid");
                o.set("color", pastel(&if misc::is_color(&raw.get("color")) { raw.get("color") } else if tv(&ep) { ep.get("color") } else { auto_color(&V::from(format!("scope:{}", t(&uid_v)))) }));
                let tg = tracks.get(&o.get("track"));
                o.set("trackName", if tracks.has(&o.get("track")) { tg.get("name") } else { o.get("track") });
                o.set("afterHost", tv(&host) && n(&o.get("start")) >= n(&host.get("endY")) - 1e-9);
                let ov = V::Obj(o.clone());
                for m in &members { push_list(m, "scopes", ov.clone()); }
                if tv(&host) { push_list(&host, "hostedScopes", ov.clone()); }
                if tv(&ep) { push_list(&ep, "scopes", ov.clone()); }
                scopes.push(ov.clone());
                by_uid.set(uid_v, ov);
            }
        }
        scopes.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("endY"), &c.get("endY"))));
        // 포개짐: 부모 그릇 → parent · depth(바깥 0) · children. 고리는 끊고 알림. 그릇 안 이름표 시대 → epoch.scope · scope.labels
        let scope_ref = |r: &V, pack_id: &V, track_id: &V| -> V {
            let all = scopes.to_vec();
            all.iter().find(|x| eq(&x.get("packId"), pack_id) && eq(&x.get("track"), track_id) && (eq(&x.get("id"), r) || eq(&x.get("name"), r)))
                .or_else(|| all.iter().find(|x| eq(&x.get("uid"), r))).cloned().unwrap_or(V::Null)
        };
        for sc in scopes.to_vec() {
            if !tv(&sc.get("within")) { continue; }
            let p = scope_ref(&sc.get("within"), &sc.get("packId"), &sc.get("track"));
            if !tv(&p) { if let V::Arr(w) = sc.get("warnings") { w.push(format!("부모 그릇 \"{}\"을(를) 같은 트랙에서 찾지 못했습니다.", t(&sc.get("within")))); } }
            else { ob(&sc).set("parent", p); }
        }
        for sc in scopes.to_vec() {
            let seen = Set::new();
            seen.add(sc.clone());
            let mut depth = 0.0;
            let mut p = sc.get("parent");
            while tv(&p) {
                if seen.has(&p) {
                    if let V::Arr(w) = sc.get("warnings") { w.push("부모 그릇이 고리를 이뤄 바깥 그릇으로 둡니다."); }
                    ob(&sc).delete("parent");
                    depth = 0.0;
                    break;
                }
                seen.add(p.clone());
                depth += 1.0;
                p = p.get("parent");
            }
            ob(&sc).set("depth", depth);
        }
        for sc in scopes.to_vec() { if tv(&sc.get("parent")) { push_list(&sc.get("parent"), "children", sc.clone()); } }
        for e in epochs.to_vec() {
            if !tv(&e.get("within")) { continue; }
            let w = e.get("within");
            let mut sc = scope_ref(&w, &e.get("packId"), &e.get("track"));
            if !tv(&sc) { sc = scopes.to_vec().into_iter().find(|x| eq(&x.get("packId"), &e.get("packId")) && (eq(&x.get("id"), &w) || eq(&x.get("name"), &w))).unwrap_or(V::Null); }
            if !tv(&sc) { continue; }
            ob(&e).set("scope", sc.clone());
            push_list(&sc, "labels", e.clone());
        }
        for sc in scopes.to_vec() {
            if tv(&sc.get("wiki")) && !docs.has(&sc.get("uid")) { docs.set(sc.get("uid"), o! { "text" => sc.get("wiki"), "packId" => sc.get("packId"), "packName" => sc.get("packName") }); }
        }
    }

    // 단체 · 렌즈의 재료: 주제 사전 · 제도 · 단체 · 사건의 주제 꼬리표
    let themes = Arr::new(merge_themes(packs).into_iter().enumerate().map(|(i, d)| {
        let o = copy(&d);
        o.set("order", i as f64);
        o.set("color", pastel(&or(d.get("color"), auto_color(&V::from(format!("theme:{}", t(&d.get("id"))))))));
        V::Obj(o)
    }).collect());
    let theme_map = Map::new();
    for d in themes.to_vec() { theme_map.set(d.get("id"), d); }
    let theme_of = |r: &V| -> Option<V> {
        if let Some(hit) = find_theme(&themes.to_vec(), r) { return Some(hit); }
        let st = js::to_str(&nn(r.clone(), s(""))).trim();
        if st.is_empty() { return None; }
        let id = V::from(format!("theme-{}", misc::hash(&st)));
        if !theme_map.has(&id) {
            let o = o! { "id" => id.clone(), "name" => st, "auto" => true, "order" => themes.len() as f64, "color" => pastel(&auto_color(&V::from(format!("theme:{}", t(&id))))) };
            themes.push(o.clone());
            theme_map.set(id.clone(), o);
        }
        Some(theme_map.get(&id))
    };
    // 나라 찾기 { track?, polity } — 정권 띠만: 적은 트랙(비우면 그 항목의 트랙)에서, 트랙을 적지 않았으면 모든 트랙에서도. 같은 이름이 여럿이면 그때(t) 있던 것
    let polity_by_ref = |r: &V, def_track: &V, pack_id: &V, tt: &V| -> V {
        if !tv(r) || !tv(&r.get("polity")) { return V::Null; }
        let pol = r.get("polity");
        let ok = |q: &V| is(&q.get("itemKind"), "period") && !tv(&q.get("groupUid"));
        let pick_at = |l: Vec<V>| -> V {
            let first = l.first().cloned().unwrap_or(V::Undef);
            let chosen = if l.len() < 2 || tt.is_nullish() || !n(tt).is_finite() { first } else { l.iter().find(|q| le(&q.get("start"), tt) && le(tt, &end_in(rc, q))).cloned().unwrap_or(first) };
            or(chosen, V::Null)
        };
        let here: Vec<V> = same(&or(r.get("track"), def_track.clone())).into_iter().filter(|q| ok(q) && (eq(&q.get("name"), &pol) || eq(&q.get("id"), &pol) || eq(&q.get("uid"), &pol))).collect();
        if !here.is_empty() || tv(&r.get("track")) { return pick_at(here); }
        pick_at(all_p.iter().filter(|q| ok(q) && (eq(&q.get("uid"), &pol) || (eq(&q.get("packId"), pack_id) && eq(&q.get("id"), &pol)) || eq(&q.get("name"), &pol))).cloned().collect())
    };
    let ref_text = |r: &V| -> String { if tv(&r.get("track")) { format!("{}:{}", t(&r.get("track")), t(&r.get("polity"))) } else { t(&r.get("polity")) } };
    // 제도 칸
    let institutions = Arr::default();
    let ix_theme = Map::new();
    let ix_polity = Map::new();
    let ix_family = Map::new();
    let institution_index = o! { "byTheme" => ix_theme.clone(), "byPolity" => ix_polity.clone(), "byFamily" => ix_family.clone() };
    for raw in inst_map.values() {
        let warnings = Arr::default();
        let th = theme_of(&raw.get("theme"));
        if let Some(th) = &th { if tv(&th.get("auto")) { warnings.push(format!("주제 \"{}\"이(가) 주제 사전에 없습니다 — 그 이름으로 주제를 만들어 묶었습니다.", t(&th.get("name")))); } }
        let known: Vec<f64> = list(&raw.get("spans")).iter().flat_map(|sp| [sp.get("start"), sp.get("end")]).filter(|v| !v.is_nullish() && n(v).is_finite()).map(|v| n(&v)).collect();
        let p = polity_by_ref(&V::Obj(o! { "track" => raw.get("track"), "polity" => raw.get("polity") }), &or(raw.get("track"), s("")), &raw.get("packId"),
            &if known.is_empty() { V::Null } else { V::Num(js::min(&known)) });
        if !tv(&p) { warnings.push(format!("나라 \"{}\"을(를) 연표에서 찾지 못했습니다{}.", ref_text(&raw), if known.is_empty() { "" } else { " — 적힌 칸의 연대로만 자리를 잡았습니다" })); }
        let host = if tv(&p) { p.clone() } else if !known.is_empty() { V::Obj(o! { "start" => js::min(&known), "endY" => js::max(&known) }) } else { V::Null };
        if !tv(&host) { continue; }
        let spans_in: Vec<V> = list(&raw.get("spans")).iter().map(|sp| V::Obj(without(sp, &["from"]))).collect();
        let req = V::Obj(o! {
            "start" => host.get("start"), "startAt" => at_of(rc, &host, "start"), "end" => host.get("end"), "endAt" => at_of(rc, &host, "end"), "endY" => host.get("endY"),
            "ongoing" => host.get("ongoing"), "phases" => arr(vec![V::Obj(o! { "spans" => arr(spans_in) })]),
        });
        let res = resolve_phases(rc, &req);
        let res_spans = res.map_or(Vec::new(), |r| list(&r.get(&0.0).get("spans")));
        let raw_spans = raw.get("spans");
        let span_list: Vec<V> = res_spans.iter().map(|sp| {
            let rs = raw_spans.get(&n(&sp.get("ii")));
            let f = or(if tv(&rs) { rs.get("from") } else { V::Undef }, V::Null);
            let fp = if tv(&f) { polity_by_ref(&f, &if tv(&p) { p.get("track") } else { or(raw.get("track"), s("")) }, &raw.get("packId"), &sp.get("start")) } else { V::Null };
            if tv(&f) && !tv(&fp) { warnings.push(format!("칸 \"{}\"의 온 곳 \"{}\"을(를) 연표에서 찾지 못했습니다.", t(&sp.get("name")), ref_text(&f))); }
            let o = copy(sp);
            o.set("from", f);
            o.set("fromItem", fp);
            V::Obj(o)
        }).collect();
        if span_list.is_empty() { continue; }
        let fam_key = if tv(&raw.get("family")) { V::from(format!("{}|{}", th.as_ref().map_or(String::new(), |x| t(&x.get("id"))), t(&raw.get("family")))) } else { s("") };
        let thv = th.clone().unwrap_or(V::Null);
        let o = copy(&raw);
        let st: Vec<f64> = span_list.iter().map(|sp| n(&sp.get("start"))).collect();
        let en: Vec<f64> = span_list.iter().map(|sp| n(&sp.get("end"))).collect();
        assign_obj(&o, &o! {
            "themeId" => if th.is_some() { thv.get("id") } else { s("") }, "themeName" => if th.is_some() { thv.get("name") } else { raw.get("theme") },
            "themeColor" => if th.is_some() { thv.get("color") } else { s("#a4b1b7") },
            "polityItem" => p.clone(), "polityUid" => if tv(&p) { p.get("uid") } else { V::Null }, "polityName" => if tv(&p) { p.get("name") } else { raw.get("polity") },
            "polityColor" => if tv(&p) { p.get("color") } else { V::Null }, "track" => if tv(&p) { p.get("track") } else { or(raw.get("track"), s("")) }, "trackAuto" => !tv(&raw.get("track")),
            "name" => format!("{} · {}", t(&if tv(&p) { p.get("name") } else { raw.get("polity") }), t(&if th.is_some() { thv.get("name") } else { raw.get("theme") })), "nameAuto" => true,
            "spanList" => arr(span_list.clone()), "start" => js::min(&st), "endY" => js::max(&en), "startAuto" => true, "endAuto" => true,
            "certainty" => "accepted", "familyKey" => fam_key.clone(), "warnings" => warnings,
            "color" => pastel(&if tv(&fam_key) { auto_color(&V::from(format!("family:{}", t(&fam_key)))) } else if th.is_some() { thv.get("color") } else { s("#a4b1b7") }),
        });
        o.set("end", o.get("endY"));
        o.set("spanMin", o.get("start"));
        o.set("spanMax", o.get("endY"));
        let ov = V::Obj(o.clone());
        institutions.push(ov.clone());
        by_uid.set(o.get("uid"), ov.clone());
        if tv(&o.get("themeId")) { push_to(&ix_theme, &o.get("themeId"), ov.clone()); }
        if tv(&p) {
            push_to(&ix_polity, &p.get("uid"), ov.clone());
            push_list(&p, "institutionList", ov.clone());
        }
        if tv(&fam_key) { push_to(&ix_family, &fam_key, ov); }
    }
    let theme_order = |x: &V| -> f64 { let d = theme_map.get(&x.get("themeId")); n(&nn(if tv(&d) { d.get("order") } else { V::Undef }, V::Num(99.0))) };
    institutions.sort_js(|a, c| or_cmp(theme_order(a) - theme_order(c), || sub(&a.get("start"), &c.get("start"))));
    family_colors(&institutions.to_vec());
    for p in &all_p { if let V::Arr(l) = p.get("institutionList") { if tv(&p.get("institutionList")) { l.sort_js(|a, c| or_cmp(theme_order(a) - theme_order(c), || sub(&a.get("start"), &c.get("start")))); } } }
    for o in institutions.to_vec() {
        let oo = ob(&o);
        oo.set("sameFamily", if tv(&o.get("familyKey")) { arr(list_at(&ix_family, &o.get("familyKey")).into_iter().filter(|q| !eq(q, &o)).collect()) } else { arr(Vec::new()) });
        let peers: Vec<V> = if tv(&o.get("polityUid")) { list_at(&ix_polity, &o.get("polityUid")).into_iter().filter(|q| !eq(q, &o) && eq(&q.get("themeId"), &o.get("themeId"))).collect() } else { Vec::new() };
        for q in peers {
            let ql = list(&q.get("spanList"));
            let hit = list(&o.get("spanList")).into_iter().find(|a| ql.iter().any(|bq| lt(&a.get("start"), &bq.get("end")) && lt(&bq.get("start"), &a.get("end"))));
            if let Some(hit) = hit {
                let other = if !eq(&q.get("packId"), &o.get("packId")) { format!("({})", t(&q.get("packName"))) } else { String::new() };
                if let V::Arr(w) = o.get("warnings") { w.push(format!("같은 나라 · 같은 주제의 제도 \"{}\"{other}와(과) 칸 \"{}\"의 기간이 겹칩니다.", t(&q.get("name")), t(&hit.get("name")))); }
            }
        }
    }
    // 단체
    let groups = Arr::new(group_map.values());
    let group_by_ref = |r: &V, me: &V| -> V {
        let st = js::to_str(&nn(r.clone(), s(""))).trim();
        if st.is_empty() { return V::Null; }
        let sv = V::Str(st);
        let want = want_of(&sv, &me.get("packId"));
        let all = groups.to_vec();
        all.iter().find(|g| !eq(g, me) && eq(&g.get("uid"), &want))
            .or_else(|| all.iter().find(|g| !eq(g, me) && eq(&g.get("packId"), &me.get("packId")) && eq(&g.get("name"), &sv)))
            .or_else(|| all.iter().find(|g| !eq(g, me) && (eq(&g.get("name"), &sv) || eq(&g.get("id"), &sv)))).cloned().unwrap_or(V::Null)
    };
    let figure_by_ref = |r: &V, g: &V| -> V {
        let st = js::to_str(&nn(r.clone(), s(""))).trim();
        let sv = V::Str(st.clone());
        let want = want_of(&sv, &g.get("packId"));
        let hit: Vec<V> = figures.to_vec().into_iter().filter(|f| eq(&f.get("uid"), &want) || eq(&f.get("name"), &sv) || has(&list(&f.get("aka")), &sv)).collect();
        if hit.len() < 2 { return hit.first().cloned().unwrap_or(V::Null); }
        let score = |f: &V| -> f64 {
            (if eq(&f.get("uid"), &want) { 100.0 } else { 0.0 }) + (if eq(&f.get("track"), &g.get("track")) { 10.0 } else { 0.0 })
                + (if le(&f.get("spanMin"), &g.get("endY")) && n(&g.get("start")) <= n(&f.get("spanMax")) + 1.0 { 5.0 } else { 0.0 })
        };
        let best = js::max(&hit.iter().map(score).collect::<Vec<_>>());
        let top: Vec<V> = hit.iter().filter(|f| score(f) == best).cloned().collect();
        if top.len() == 1 { return top[0].clone(); }
        if let V::Arr(w) = g.get("warnings") { w.push(format!("구성원 \"{st}\"은(는) 같은 이름의 인물이 여럿이라 고를 수 없습니다 — 인물 id로 적습니다.")); }
        V::Bool(false)
    };
    let rows_of = |g: &V, v: &V, role: bool, word: &str| -> Vec<V> {
        rgroups::read_polity_rows(rc, v, role, &mut |_| {}, "").into_iter().map(|r| {
            let p = polity_by_ref(&r, &g.get("track"), &g.get("packId"), &nn(r.get("start"), g.get("start")));
            if !tv(&p) { if let V::Arr(w) = g.get("warnings") { w.push(format!("{word} \"{}\"을(를) 연표에서 찾지 못했습니다.", ref_text(&r))); } }
            let o = o! {
                "polity" => p.clone(), "polityUid" => if tv(&p) { p.get("uid") } else { V::Null }, "name" => if tv(&p) { p.get("name") } else { r.get("polity") },
                "track" => if tv(&p) { p.get("track") } else { or(r.get("track"), g.get("track")) }, "color" => if tv(&p) { p.get("color") } else { V::Null },
                "start" => nn(r.get("start"), g.get("start")), "end" => nn(r.get("end"), g.get("endY")), "given" => !r.get("start").is_nullish() || !r.get("end").is_nullish(),
                "role" => or(r.get("role"), s("")), "note" => or(r.get("note"), s("")),
            };
            if r.bool("startUnknown") || (r.get("start").is_nullish() && g.bool("startUnknown")) { o.set("startUnknown", true); }
            if r.bool("endUnknown") || (r.get("end").is_nullish() && g.bool("endUnknown")) { o.set("endUnknown", true); }
            V::Obj(o)
        }).collect()
    };
    for g in groups.to_vec() {
        let go = ob(&g);
        go.set("warnings", arr(Vec::new()));
        go.set("typeName", if tv(&g.get("type")) { V::Str(super::util::group_type_name(&g.get("type"))) } else { s("") });
        go.set("withinList", arr(rows_of(&g, &g.get("within"), false, "있던 나라")));
        go.set("memberList", arr(rows_of(&g, &g.get("members"), true, "구성 나라")));
        if is(&g.get("type"), "coalition") && rgroups::read_polity_rows(rc, &g.get("members"), false, &mut |_| {}, "").len() >= 2
            && list(&g.get("memberList")).iter().filter(|m| tv(&m.get("polity"))).count() < 2 {
            if let V::Arr(w) = g.get("warnings") { w.push("연합인데 연표에서 찾은 구성 나라가 하나뿐입니다."); }
        }
        let pw = list(&g.get("withinList")).into_iter().find(|w| tv(&w.get("polity"))).or_else(|| list(&g.get("memberList")).into_iter().find(|m| tv(&m.get("polity"))));
        let p = or(pw.map_or(V::Undef, |x| x.get("polity")), V::Null);
        go.set("polityUid", if tv(&p) { p.get("uid") } else { V::Null });
        go.set("polityName", if tv(&p) { p.get("name") } else { V::Null });
        go.set("polityColor", if tv(&p) { p.get("color") } else { V::Null });
        // 집권 기간: 연호와 같은 칸 — 미정은 이어지는 칸의 규칙, 비운 끝은 다음 칸의 시작(없으면 단체의 끝)까지
        let power = if let V::Arr(a) = g.get("power") { V::Arr(a) } else { arr(Vec::new()) };
        let cells = rcells::sort_cells(list(&place_cells(&power, &g)));
        let power_spans: Vec<V> = cells.iter().enumerate().map(|(i, c)| {
            let next = cells.get(i + 1);
            let auto = c.get("end").is_nullish();
            let follows = next.is_some_and(|nx| !nx.get("start").is_nullish() && lt(&c.get("start"), &nx.get("start")));
            let end = if !auto { c.get("end") } else if follows { next.expect("다음 칸").get("start") } else { g.get("endY") };
            let o = copy(c);
            o.set("i", i as f64);
            o.set("end", end);
            o.set("endAt", if auto { if follows { next.expect("다음 칸").get("startAt") } else { at_of(rc, &g, "end") } } else { c.get("endAt") });
            o.set("endAuto", auto || c.bool("endAuto"));
            o.set("endPolity", auto && !follows);
            V::Obj(o)
        }).collect();
        go.set("powerSpans", arr(power_spans));
        let people_list: Vec<V> = list(&if let V::Arr(a) = g.get("people") { V::Arr(a) } else { arr(Vec::new()) }).into_iter().map(|r| {
            let f = if matches!(r, V::Str(_)) { figure_by_ref(&r, &g) } else { V::Null };
            let o = o! { "name" => names::person_ref_text(&r), "ref" => r.clone(), "uid" => if tv(&f) { f.get("uid") } else { V::Null }, "figure" => or(f.clone(), V::Null) };
            if matches!(f, V::Bool(false)) { o.set("ambiguous", true); }
            V::Obj(o)
        }).collect();
        go.set("peopleList", arr(people_list));
        let ev = if tv(&g.get("event")) { find_event(&V::Str(js::to_str(&g.get("event"))), &g.get("packId")).unwrap_or(V::Null) } else { V::Null };
        go.set("eventItem", ev.clone());
        if tv(&g.get("event")) && !tv(&ev) { if let V::Arr(w) = g.get("warnings") { w.push(format!("맺은 사건 \"{}\"을(를) 연표에서 찾지 못했습니다.", t(&g.get("event")))); } }
        if tv(&ev) { push_list(&ev, "groupRefs", g.clone()); }
        if !misc::is_color(&g.get("color")) { go.set("colorAuto", true); }
        go.set("color", pastel(&if misc::is_color(&g.get("color")) { g.get("color") } else { auto_color(&V::from(format!("group:{}", t(&g.get("uid"))))) }));
        let tg = tracks.get(&g.get("track"));
        go.set("trackName", if tracks.has(&g.get("track")) { tg.get("name") } else { g.get("track") });
        for w in list(&g.get("withinList")) { if tv(&w.get("polity")) { push_list(&w.get("polity"), "groupLinks", V::Obj(o! { "group" => g.clone(), "role" => "within" })); } }
        for m in list(&g.get("memberList")) {
            let pp = m.get("polity");
            if tv(&pp) && !list(&pp.get("groupLinks")).iter().any(|l| eq(&l.get("group"), &g)) { push_list(&pp, "groupLinks", V::Obj(o! { "group" => g.clone(), "role" => "member" })); }
        }
    }
    group_colors(&groups.to_vec());
    for g in groups.to_vec() {
        let from = if let V::Arr(a) = g.get("from") { a.to_vec() } else { Vec::new() };
        let fl: Vec<V> = from.iter().map(|f| {
            let src = group_by_ref(&f.get("group"), &g);
            if !tv(&src) { if let V::Arr(w) = g.get("warnings") { w.push(format!("앞선 단체 \"{}\"을(를) 찾지 못했습니다.", t(&f.get("group")))); } }
            else { push_list(&src, "intoList", V::Obj(o! { "group" => g.clone(), "how" => or(f.get("how"), s("")), "note" => or(f.get("note"), s("")) })); }
            V::Obj(o! { "group" => src.clone(), "name" => if tv(&src) { src.get("name") } else { f.get("group") }, "how" => or(f.get("how"), s("")), "note" => or(f.get("note"), s("")) })
        }).collect();
        ob(&g).set("fromList", arr(fl));
    }
    groups.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("endY"), &c.get("endY"))));
    for g in groups.to_vec() { by_uid.set(g.get("uid"), g); }
    for p in &all_p { if let V::Arr(l) = p.get("groupLinks") { if tv(&p.get("groupLinks")) { l.sort_js(|a, c| sub(&a.get("group").get("start"), &c.get("group").get("start"))); } } }
    // 사건의 주제 꼬리표 → 주제
    let theme_events = Map::new();
    for e in &all_e {
        let l = rgroups::read_theme_list(&e.get("theme"));
        if l.is_empty() { continue; }
        let refs: Vec<V> = l.iter().map(|r| {
            let rv = V::Str(r.clone());
            let th = theme_of(&rv).expect("빈 꼬리표는 없다");
            push_to(&theme_events, &th.get("id"), e.clone());
            V::Obj(o! { "ref" => rv, "id" => th.get("id"), "name" => th.get("name"), "color" => th.get("color"), "auto" => tv(&th.get("auto")) })
        }).collect();
        ob(e).set("themeRefs", arr(refs));
    }
    let doc_of = |x: &V| -> Obj { o! { "text" => x.get("wiki"), "packId" => x.get("packId"), "packName" => x.get("packName") } };
    for x in groups.to_vec().into_iter().chain(institutions.to_vec()) { if tv(&x.get("wiki")) && !docs.has(&x.get("uid")) { docs.set(x.get("uid"), doc_of(&x)); } }
    // 문서 색인: 항목의 wiki 칸 → 바탕 문서(DLC의 documents가 먼저)
    for x in all_p.iter().chain(all_e.iter()).cloned().chain(epochs.to_vec()) { if tv(&x.get("wiki")) && !docs.has(&x.get("uid")) { docs.set(x.get("uid"), doc_of(&x)); } }
    for x in figures.to_vec().into_iter().chain(lineage.to_vec()) { if tv(&x.get("wiki")) && !docs.has(&x.get("uid")) { docs.set(x.get("uid"), doc_of(&x)); } }
    for pe in peoples.values() {
        let k = V::from(format!("people:{}", t(&pe.get("id"))));
        if tv(&pe.get("wiki")) && !docs.has(&k) { docs.set(k, o! { "text" => pe.get("wiki"), "packId" => "", "packName" => "" }); }
    }
    for tr in tracks.values() {
        let k = V::from(format!("track:{}", t(&tr.get("id"))));
        if tv(&tr.get("wiki")) && !docs.has(&k) { docs.set(k, o! { "text" => tr.get("wiki"), "packId" => "", "packName" => "" }); }
    }
    for (key, d) in docs.entries() {
        let ks = js::to_str(&key);
        if ks.index_of16(&Str::from("//"), 0.0) >= 0.0 { continue; }
        let text = ks.as_str();
        let g = by_uid.get(&key);
        let x = if tv(&g) { g } else if let Some(id) = text.strip_prefix("people:") { peoples.get(&s(id)) } else if let Some(id) = text.strip_prefix("track:") { tracks.get(&s(id)) } else { V::Null };
        if tv(&x) { ob(&x).set("wiki", d.get("text")); }
    }

    // 모델 — 트랙 차례: 문화권의 차례(켠 DLC의 spheres · 없는 트랙은 맨 뒤 — core.js f90a60d102ce 8830 ~ 8834줄) → order → 넣은 차례
    let mut track_list = tracks.values();
    js::sort(&mut track_list, |a, c| {
        let (x, y) = (super::util::sphere_order(sphere_map, &a.get("sphere")), super::util::sphere_order(sphere_map, &c.get("sphere")));
        or_cmp(if x == y { 0.0 } else if x < y { -1.0 } else { 1.0 }, || or_cmp(sub(&a.get("order"), &c.get("order")), || sub(&a.get("seq"), &c.get("seq"))))
    });
    let mut people_list = peoples.values();
    js::sort(&mut people_list, |a, c| or_cmp(sub(&a.get("order"), &c.get("order")), || sub(&a.get("seq"), &c.get("seq"))));
    epochs.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || sub(&a.get("endY"), &c.get("endY"))));
    let model = o! {
        "tracks" => arr(track_list), "categories" => arr(categories.values()), "peoples" => arr(people_list), "epochs" => epochs.clone(), "scopes" => scopes,
        "periods" => periods.clone(), "events" => events.clone(), "figures" => figures, "lineageFigures" => lineage, "byUid" => by_uid, "docs" => docs.clone(),
        "trackMap" => tracks.clone(), "spheres" => spheres.clone(), "sphereMap" => sphere_map.clone(), "sphereWarnings" => sphere_warnings.clone(), "categoryMap" => categories.clone(), "peopleMap" => peoples.clone(), "rankDefs" => rank_defs, "themes" => themes,
        "themeMap" => theme_map, "themeEvents" => theme_events, "groups" => groups, "institutions" => institutions, "institutionIndex" => institution_index,
    };
    let mv = V::Obj(model);
    crate::lay::link::link_houses(rc, &mv, packs);
    crate::lay::link::link_treaty_signers(&mv);
    crate::lay::link::link_people(rc, &mv, packs);
    crate::lay::link::link_format3(rc, &mv, packs); // 실패하는 길이 없다(16b — 죽은 Err 길을 걷음)
    crate::lay::link::link_order(&mv, packs);
    crate::lay::link::link_doc_images(&mv, packs);
    // 칸의 경계(HT.cellBounds): 칸 목록이 더 바뀌지 않는 맨 끝에서 — 열거되지 않는 속성이라 사본 · 내보내기 · 덤프에 섞이지 않는다
    for p in periods.to_vec() { if is(&p.get("kind"), "period") { ob(&p).define_hidden("cellBounds", super::bounds::cell_bounds(rc, &p)); } }
    // JS라면 던졌을 곳(객체가 아닌 값에 칸 쓰기 · Map이 아닌 표)에 닿았으면 오류 — 지은 그래프는 풀고
    if let Some(msg) = super::util::take_fault() { js::release(&mv); return Err(format!("모델을 짓지 못했습니다 — {msg}(JS라면 TypeError)").into()); }
    Ok(mv)
}

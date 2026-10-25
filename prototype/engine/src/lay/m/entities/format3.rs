//! `entities.mjs` 444 ~ 949줄 `format3Refs(ctx, T, put, figureOfLeader, kin, docBodies)` — 형식 3의 미리 푼 값(설계 A 부록 가-6 · 계약 초안 6-9 다).
//! 글은 js/viewer.js가 만드는 글 그대로: namesHTML · personLink · kinLinesHTML · cellPersonHTML · figurePersonHTML · placeHTML · groupDetailHTML · institutionDetailHTML · periodLensHTML …
use super::cross::{figure_of_leader, obj};
use super::kin::KinOut;
use super::people::{self, house_eras, house_head, house_spans, house_under, kin_of, kin_of_person, lineage_of, person_of, polity_head, Chip};
use super::web::{certainty_name, format_range, glyph_missing, group_how_name, lang_name, law_act_name, map_get, map_has, name_kind_name, names_head, names_split, parent_role_name, phase_range_text, va, CELL_KIND_IDS};
use super::{mm, span_of, Cx};
use crate::lay::js::{self, Map, Obj, Set, Str, V};
use crate::lay::link::place_of;
use crate::lay::model::bounds::cells_of;
use crate::lay::model::util::{eq, fault, is, item_kind_of, leader_label, list, n, or, s, scope_ref_text, t, tv};
use crate::lay::read::{cells, groups};

/// `has(o, k, v)` — 빈 값(null · undefined · '' · 빈 배열)이 아니면 싣는다.
fn has(o: &Obj, k: &str, v: V) -> Obj {
    let empty = v.is_nullish() || matches!(&v, V::Str(x) if x.is_empty()) || matches!(&v, V::Arr(a) if a.is_empty());
    if !empty { o.set(k, v); }
    o.clone()
}

/// `format3Refs(…)` — 결과는 `cx.ex`에 쌓인다.
pub(super) fn format3_refs(cx: &mut Cx, kin: Option<&KinOut>, doc_bodies: &Set) {
    let model = cx.model.clone();
    let by_uid = model.get("byUid");
    let house_map = model.get("houseMap");
    let surname_map = if tv(&model.get("surnameMap")) { model.get("surnameMap") } else { V::Map(Map::new()) };
    let place_map = if tv(&model.get("placeMap")) { model.get("placeMap") } else { V::Map(Map::new()) };
    let track_name = |id: &V| -> V {
        let tr = map_get(&model.get("trackMap"), id);
        or(or(if tv(&tr) { tr.get("name") } else { V::Undef }, id.clone()), s(""))
    };
    let figures = list(&model.get("figures"));

    /* ---------- 계보(D1): 뼈대 자리 · 머리 칩 · 조명 구간 ---------- */
    /* 지도자 칸의 뼈대 자리 [뿌리 뼈대 uid, 한 벌 번호] — HT.kinOf가 먼저, 없으면 뼈대의 칸 표. 실린 뼈대가 아니면 null */
    let kin_at_of = |kc: &mut people::KinCache, p: &V, r: &str, i: usize| -> V {
        let Some(k) = kin else { return V::Null };
        if let Some((key, at)) = kin_of(kc, &model, p, i) {
            if k.roots.contains(&key) { return va(vec![s(&key), V::Num(f64::from(at))]); }
        }
        match k.cell_at.get(&Str::from(format!("{}|{r}", t(&p.get("uid"))))) { Some((key, at)) => va(vec![s(key), V::Num(f64::from(*at))]), None => V::Null }
    };
    /* 머리 칩 → [{ role, text, title?, uid?, doc?, auto?: 1 }] — field(메이커가 고칠 칸)는 뺀다. */
    let head_chips = |l: Vec<Chip>| -> V {
        va(l.into_iter().filter(|c| tv(&c.text)).map(|c| {
            let o = obj! { "role" => c.role, "text" => js::to_str(&c.text) };
            if tv(&c.title) { o.set("title", js::to_str(&c.title)); }
            let u = if tv(&c.uid) { js::to_str(&c.uid) } else { Str::default() };
            let ut = u.as_str().into_owned();
            let house_ok = tv(&house_map) && map_has(&house_map, &s(ut.strip_prefix("house:").unwrap_or(&ut))) && ut.starts_with("house:");
            let surname_ok = ut.starts_with("surname:") && map_has(&surname_map, &V::Str(u.slice16(8.0, f64::INFINITY)));
            if !ut.is_empty() && (map_has(&by_uid, &V::Str(u.clone())) || house_ok || surname_ok) { o.set("uid", u.clone()); }
            else if !ut.is_empty() && doc_bodies.has(&V::Str(u.clone())) { o.set("doc", u.clone()); }
            if c.auto { o.set("auto", 1.0); }
            V::Obj(o)
        }).collect())
    };
    /* 해 좌표의 구간 [{ uid, start, end }] → 정수 분(계약 4절) */
    let spots_min = |l: &[people::HSpan]| -> V {
        va(l.iter().filter_map(|q| {
            let sp = span_of(&V::Num(q.start), &V::Num(q.end));
            if tv(&sp) && tv(&q.uid) { Some(V::Obj(obj! { "uid" => q.uid.clone(), "start" => sp.get(&0.0), "end" => sp.get(&1.0) })) } else { None }
        }).collect())
    };
    /* 가문과 아래 파 모두의 id(자기 포함) — HT.houseUnder */
    let under_of = |id: &V| -> Vec<V> { house_under(&model, id) }; // Array.from(HT.houseUnder(model, id) || [id]) — 빈 배열도 참이라 그대로

    let mut kc = std::mem::take(&mut cx.kc);
    let tt = super::T { w: &cx.w };
    let w = &cx.w;
    let ex = &cx.ex;

    /* ---------- 이름 줄 x_names — namesHTML: main(원어 · 로마자 · 종류 없는 이름) · other(그 밖의 이름), 이름마다 nameTag 글 ---------- */
    let name_tag = |nm: &V| -> String {
        [if tv(&nm.get("kind")) { name_kind_name(&nm.get("kind")).as_str().into_owned() } else { String::new() },
         if tv(&nm.get("lang")) { lang_name(&nm.get("lang")).as_str().into_owned() } else { String::new() },
         tt.side_span(nm),
         if tv(&nm.get("note")) { t(&nm.get("note")) } else { String::new() }]
            .into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(" · ")
    };
    let name_row = |nm: &V| -> V {
        let o = obj! { "text" => nm.get("text") };
        if tv(&nm.get("lang")) { o.set("lang", nm.get("lang")); }
        let tag = name_tag(nm);
        if !tag.is_empty() { o.set("tag", tag); }
        V::Obj(o)
    };
    let names_line = |l: &V| -> V {
        if !matches!(l, V::Arr(a) if !a.is_empty()) { return V::Null; }
        let (main, other) = names_split(l);
        if main.is_empty() && other.is_empty() { return V::Null; }
        let o = Obj::new();
        if !main.is_empty() { o.set("main", va(main.iter().map(name_row).collect())); }
        if !other.is_empty() { o.set("other", va(other.iter().map(name_row).collect())); }
        V::Obj(o)
    };
    let all_lists = ["periods", "events", "figures", "lineageFigures", "houses", "groups", "institutions", "places", "surnames", "views", "maps"];
    for k in all_lists { for x in list(&model.get(k)) { ex.put(&x, "x_names", names_line(&x.get("names"))); } }

    /* ---------- 사람 고리 — personLink(n, here): 같은 나라의 칸 → 인물 → 다른 나라의 첫 칸 → 글(미상 · 못 찾은 이름) ---------- */
    let ring = |nd: &V, here: &V| -> V {
        if !tv(nd) { return V::Null; }
        if tv(&nd.get("unknown")) { return V::Obj(obj! { "name" => "미상", "unknown" => 1.0 }); }
        let same = if tv(here) { list(&nd.get("cells")).into_iter().find(|q| eq(&q.get("p"), here) && is(&q.get("kind"), "leader")) } else { None };
        if let Some(sm) = same { return V::Obj(obj! { "name" => nd.get("name"), "uid" => here.get("uid"), "ref" => sm.get("ref"), "polity" => or(here.get("name"), s("")) }); }
        let fg = nd.get("figure");
        if tv(&fg) && map_has(&by_uid, &fg.get("uid")) { return V::Obj(obj! { "name" => nd.get("name"), "uid" => fg.get("uid") }); }
        let c = list(&nd.get("cells")).first().cloned().unwrap_or(V::Undef);
        if tv(&c) { return V::Obj(obj! { "name" => nd.get("name"), "uid" => c.get("p").get("uid"), "ref" => c.get("ref"), "polity" => or(c.get("p").get("name"), s("")) }); }
        if tv(&nd.get("missing")) { V::Obj(obj! { "name" => nd.get("name"), "missing" => 1.0 }) } else { V::Obj(obj! { "name" => nd.get("name") }) }
    };
    /* 부모 줄의 관계 글 — kinRoleText(부 · 모 · 'n대 조상' · 없으면 '부모') */
    let kin_role_text = |e: &V| -> String {
        if is(&e.get("as"), "ancestor") { format!("{}조상", if tv(&e.get("gen")) { format!("{}대 ", t(&e.get("gen"))) } else { String::new() }) }
        else if tv(&e.get("as")) { parent_role_name(&e.get("as")).as_str().into_owned() } else { "부모".into() }
    };
    /* 혈연 줄들(kinLinesHTML) · 속한 단체(personGroupsHTML) — 사람 자리 n을 here(지금 보는 나라)에서 본 것 */
    // JS라면 TypeError(과제 Y): 줄의 사람 자리(node)가 없으면 `ring`이 null — 부모 줄은 `Object.assign(null, …)`에서, 배우자 · 자식 줄은 `has(null, k, v)`가
    // 빈 값이 아닌 v를 적을 때(`o[k] = v`) 멈춘다. 모델은 늘 사람 자리를 둔다 — 잘못으로 남겨 모듈 끝에서 오류로.
    let null_ring = |nd: &V, which: &str| fault(format!("사람 고리(kinLinesHTML) — {}의 {which} 줄에 사람 자리가 없습니다(JS라면 TypeError)", t(&nd.get("name"))));
    let kin_lines = |nd: &V, here: &V| -> Obj {
        let o = Obj::new();
        has(&o, "parents", va(list(&nd.get("parents")).iter().map(|e| {
            let r = ring(&e.get("node"), here);
            if r.is_null() { null_ring(nd, "부모"); }
            if let V::Obj(ro) = &r {
                ro.set("as", kin_role_text(e));
                if tv(&e.get("certainty")) { ro.set("certainty", or(s(certainty_name(&e.get("certainty"))), e.get("certainty"))); }
                if tv(&e.get("note")) { ro.set("note", e.get("note")); }
            }
            r
        }).collect()));
        has(&o, "spouses", va(list(&nd.get("spouses")).iter().map(|e| {
            let r = ring(&e.get("node"), here);
            let when = tt.side_span(e);
            if r.is_null() && !when.is_empty() { null_ring(nd, "배우자"); }
            if let V::Obj(ro) = &r { has(ro, "when", s(&when)); }
            r
        }).collect()));
        has(&o, "children", va(list(&nd.get("children")).iter().map(|e| {
            let r = ring(&e.get("node"), here);
            let r#as = if is(&e.get("as"), "ancestor") { Str::from(format!("{} 후손", if tv(&e.get("gen")) { format!("{}대", t(&e.get("gen"))) } else { String::new() })).trim().as_str().into_owned() }
                else if js::to_str(&or(e.get("as"), s(""))).as_str().starts_with("adoptive-") { "양자".into() } else { String::new() };
            if r.is_null() && !r#as.is_empty() { null_ring(nd, "자식"); }
            if let V::Obj(ro) = &r { has(ro, "as", s(&r#as)); }
            r
        }).collect()));
        has(&o, "groups", va(list(&nd.get("groups")).iter().map(|g| V::Obj(obj! { "uid" => g.get("uid"), "name" => or(g.get("name"), s("")) })).collect()));
        o
    };

    /* ---------- 상세 창 머리 x_nameHead (10건 3 · 감독 결정 D2-1 A · 4 B — HT.namesHead의 셋 그대로) ---------- */
    let head_item = |nm: &V| -> V {
        let o = obj! { "text" => nm.get("text") };
        if tv(&nm.get("lang")) { o.set("lang", nm.get("lang")); o.set("langName", lang_name(&nm.get("lang"))); }
        if tv(&nm.get("kind")) { o.set("kind", name_kind_name(&nm.get("kind"))); }
        let when = tt.side_span(nm);
        if !when.is_empty() { o.set("when", when); }
        if tv(&nm.get("note")) { o.set("note", nm.get("note")); }
        let mw = glyph_missing(&nm.get("text"), super::web::glyph_window());
        if !mw.is_empty() { o.set("mw", va(mw.into_iter().map(|c| V::Num(f64::from(c))).collect())); }
        V::Obj(o)
    };
    let head_of = |l: &V| -> V {
        if !matches!(l, V::Arr(a) if !a.is_empty()) { return V::Null; }
        let (first, second, rest) = names_head(l);
        if first.is_none() && second.is_none() && rest.is_empty() { return V::Null; }
        let o = Obj::new();
        if let Some(f) = &first { o.set("first", head_item(f)); }
        if let Some(f) = &second { o.set("second", head_item(f)); }
        if !rest.is_empty() { o.set("rest", va(rest.iter().map(head_item).collect())); }
        V::Obj(o)
    };
    for k in all_lists { for x in list(&model.get(k)) { ex.put(&x, "x_nameHead", head_of(&x.get("names"))); } }
    // 가문 창의 성 한 줄의 재료. x_surname(F1 꼴)은 그대로 둔다
    for h in list(&model.get("houses")) {
        let sn = if tv(&h.get("surnameId")) { map_get(&surname_map, &h.get("surnameId")) } else { V::Null };
        if tv(&sn) { ex.put(&h, "x_surnameHead", head_of(&sn.get("names"))); }
    }

    /* ---------- 지명 줄 — placeHTML(ref, lead): 이름 · 위 구역(가까운 것부터) · 원어 ---------- */
    let place_line = |pl: &V| -> V {
        if !tv(pl) { return V::Null; }
        let o = obj! { "name" => pl.get("name"), "uid" => pl.get("uid") };
        let path = list(&pl.get("path"));
        let up: Vec<V> = path[..path.len().saturating_sub(1)].iter().rev().map(|id| { let q = map_get(&place_map, id); if tv(&q) { q.get("name") } else { V::Undef } }).filter(tv).collect();
        has(&o, "up", va(up));
        let nm = names_line(&pl.get("names"));
        if tv(&nm) { o.set("names", nm); }
        let head = head_of(&pl.get("names")); // 딸린 한 줄(웹 namesLineHTML)의 재료 · 갈래 D2
        if tv(&head) { o.set("head", head); }
        V::Obj(o)
    };

    /* ========== 정권: 칸의 이름 줄 · 자리 이음 · 칸의 사람 · 도읍의 지명 · 단체 · 제도 칩 ========== */
    for x in list(&model.get("periods")) {
        let cell_names = Obj::new();
        let cell_heads = Obj::new(); // 칸 창의 머리(x_nameHead와 같은 꼴 — 갈래 D2)
        for k in CELL_KIND_IDS {
            for (i, c) in cells_of(&x, k).iter().enumerate() {
                let line = if tv(c) { names_line(&c.get("names")) } else { V::Null };
                if tv(&line) { cell_names.set(format!("{k}:{i}").as_str(), line); }
                let head = if tv(c) { head_of(&c.get("names")) } else { V::Null };
                if tv(&head) { cell_heads.set(format!("{k}:{i}").as_str(), head); }
            }
        }
        ex.put(&x, "x_cellNames", V::Obj(cell_names));
        ex.put(&x, "x_cellNameHead", V::Obj(cell_heads));
        if !is(&item_kind_of(&x), "period") { continue; }

        // 자리 이음(HT.lineageOf — 지도자를 칸 참조 열쇠로). 화면은 칸에 accession을 적었을 때만 줄을 세운다.
        let lin = lineage_of(&model, &x);
        let lineage = Obj::new();
        for r in lin.iter().flatten() {
            let a = &r.accession;
            let o = Obj::new();
            if tv(&a.from) && !a.from_unknown { o.set("from", ring(&a.from, &x)); }
            if a.from_auto && tv(&a.from) { o.set("fromAuto", 1.0); }
            if a.from_unknown { o.set("fromUnknown", 1.0); }
            if tv(&a.kin) { o.set("kin", a.kin_name.clone()); o.set("kinId", a.kin.clone()); }
            if a.kin_unknown { o.set("kinUnknown", 1.0); }
            if tv(&a.how) { o.set("how", a.how_name.clone()); o.set("howId", a.how.clone()); }
            if a.how_unknown { o.set("howUnknown", 1.0); }
            if tv(&a.note) { o.set("note", a.note.clone()); }
            if r.restored { o.set("restored", 1.0); }
            let pname = if tv(&r.person) { r.person.get("name") } else { s("") };
            has(&o, "elsewhere", va(r.elsewhere.iter().map(|q| V::Obj(obj! { "name" => pname.clone(), "uid" => q.uid.clone(), "ref" => q.r#ref.clone(), "polity" => or(q.name.clone(), s("")) })).collect()));
            /* 승계표(D1): 선 갈래 line(0~5) · 이음매 글 seam(웹 글 그대로) · 뼈대 자리 kinAt [뿌리 뼈대 uid, 한 벌 앞 차례 번호] */
            o.set("line", f64::from(js::to_i32(people::accession_line(a))));
            has(&o, "seam", s(&people::accession_seam(r)));
            let at = kin_at_of(&mut kc,&x, &r.r#ref, r.i);
            if tv(&at) { o.set("kinAt", at); }
            if !o.is_empty() { lineage.set(r.r#ref.as_str(), o); }
        }
        ex.put(&x, "x_lineage", V::Obj(lineage));
        // 승계표 머리 칩(3-2 — 구분 › 민족 › 국가 이름 · 꼬리표): 지도자가 있는 나라만.
        if !list(&x.get("leaders")).is_empty() { ex.put(&x, "x_head", head_chips(polity_head(&model, &x))); }

        // 칸의 사람(지도자 · 사람을 적은 내각 — cellPersonHTML): 사람 · 같은 사람의 다른 칸 · 혈연 · 속한 단체
        let persons = Obj::new();
        for (kind, l) in [("leader", list(&x.get("leaders"))), ("cabinet", list(&x.get("cabinets")))] {
            for (i, c) in l.iter().enumerate() {
                let r = format!("{kind}:{i}");
                let nd = person_of(&model, &x, Some(&r));
                if !tv(&nd) { continue; }
                let o = Obj::new();
                // 내각 칸의 '사람:' 줄은 이름이 같은 인물과 다를 때만 선다(웹 n.figure !== figureOfLeader)
                let fg = nd.get("figure");
                if tv(&fg) && map_has(&by_uid, &fg.get("uid")) && (kind == "leader" || !eq(&fg, &figure_of_leader(&figures, &x, c))) {
                    o.set("figure", has(&obj! { "uid" => fg.get("uid"), "name" => or(fg.get("name"), s("")) }, "role", fg.get("role")));
                }
                has(&o, "others", va(list(&nd.get("cells")).iter().filter(|q| !(eq(&q.get("p"), &x) && is(&q.get("ref"), &r))).map(|q| V::Obj(obj! {
                    "name" => nd.get("name"), "uid" => q.get("p").get("uid"), "ref" => q.get("ref"), "polity" => or(q.get("p").get("name"), s("")), "when" => tt.cell_when(&q.get("c"), false, &q.get("p")),
                })).collect()));
                for (k, v) in kin_lines(&nd, &x).entries() { o.set(&k, v); }
                if !o.is_empty() { persons.set(r.as_str(), o); }
            }
        }
        ex.put(&x, "x_persons", V::Obj(persons));

        // 도읍의 지명 줄 — 원어나 위 구역이 있을 때만(placeHTML(c.city, '지명'))
        let cell_places = Obj::new();
        for (i, c) in list(&x.get("capitals")).iter().enumerate() {
            let pl = if tv(c) { place_of(&model, &c.get("city")) } else { V::Null };
            if tv(&pl) && (tv(&or(pl.get("names"), va(Vec::new())).get("length")) || tv(&pl.get("parentId"))) { cell_places.set(format!("capital:{i}").as_str(), place_line(&pl)); }
        }
        ex.put(&x, "x_cellPlaces", V::Obj(cell_places));

        // 나라의 단체 · 제도 칩(periodLensHTML — x.kind === 'period'만)
        if is(&x.get("kind"), "period") {
            ex.put(&x, "x_groupLinks", va(list(&x.get("groupLinks")).iter().map(|l| {
                let g = l.get("group");
                V::Obj(has(&obj! { "uid" => g.get("uid"), "name" => or(g.get("name"), s("")), "color" => or(g.get("color"), s("")), "role" => l.get("role") }, "typeName", g.get("typeName")))
            }).collect()));
            ex.put(&x, "x_institutions", va(list(&x.get("institutionList")).iter().map(|i| {
                let o = obj! { "uid" => i.get("uid"), "name" => or(i.get("name"), s("")), "theme" => or(i.get("themeId"), s("")), "themeName" => or(i.get("themeName"), s("")) };
                has(&o, "family", i.get("family"));
                o.set("color", or(i.get("color"), s("")));
                let spans = list(&i.get("spanList")).iter().map(|sp| { let nm = sp.get("name"); if nm.is_nullish() { String::new() } else { t(&nm) } }).collect::<Vec<_>>().join(" → ");
                has(&o, "title", s(&format!("{} — {spans}", t(&i.get("themeName")))));
                V::Obj(o)
            }).collect()));
        }
    }

    /* ========== 인물: 다스린 칸 · 혈연 · 속한 단체(figurePersonHTML) ========== */
    for f in &figures {
        let nd = person_of(&model, f, None);
        if !tv(&nd) { continue; }
        let o = Obj::new();
        has(&o, "ruled", va(list(&nd.get("cells")).iter().filter(|q| is(&q.get("kind"), "leader")).map(|q| V::Obj(obj! {
            "uid" => q.get("p").get("uid"), "ref" => q.get("ref"), "name" => or(q.get("p").get("name"), s("")), "label" => leader_label(&q.get("c")), "when" => tt.cell_when(&q.get("c"), false, &q.get("p")),
        })).collect()));
        for (k, v) in kin_lines(&nd, &V::Null).entries() { o.set(&k, v); }
        ex.put(f, "x_person", V::Obj(o));
    }

    /* ========== 사건: 장소 · 법 · 선거 · 이 일로 맺은 단체(x.kind === 'event') ========== */
    for e in list(&model.get("events")) {
        if !is(&e.get("kind"), "event") { continue; }
        if tv(&e.get("place")) { ex.put(&e, "x_place", place_line(&place_of(&model, &e.get("place")))); }
        let law = if tv(&e.get("law")) { groups::read_law(&e.get("law"), &mut |_| {}) } else { None };
        if let Some(law) = law {
            let o = Obj::new();
            has(&o, "name", law.get("name"));
            if tv(&law.get("act")) { o.set("act", law.get("act")); o.set("actName", law_act_name(&law.get("act"))); }
            has(&o, "articles", law.get("articles"));
            has(&o, "note", law.get("note"));
            ex.put(&e, "x_law", V::Obj(o));
        }
        let el = if tv(&e.get("election")) { groups::read_election(&e.get("election"), &mut |_| {}) } else { None };
        if let Some(el) = el {
            let o = Obj::new();
            has(&o, "office", el.get("office"));
            o.set("results", va(list(&el.get("results")).iter().map(|r| {
                let q = obj! { "who" => r.get("who") };
                if !r.get("votes").is_nullish() { q.set("votes", r.get("votes")); }
                if !r.get("seats").is_nullish() { q.set("seats", r.get("seats")); }
                if tv(&r.get("won")) { q.set("won", 1.0); }
                V::Obj(q)
            }).collect()));
            has(&o, "note", el.get("note"));
            ex.put(&e, "x_election", V::Obj(o));
        }
        ex.put(&e, "x_groups", va(list(&e.get("groupRefs")).iter().map(|g| V::Obj(has(&obj! { "uid" => g.get("uid"), "name" => or(g.get("name"), s("")), "color" => or(g.get("color"), s("")) }, "typeName", g.get("typeName")))).collect()));
    }

    /* ========== 가문: 성 · 세계표 · 가문 조명 ========== */
    /* 계보 전용 인물의 가문(사람 자리의 가문 — 적은 것 → 파조 → 물려받기)별 수 — 웹 viewer.js kinFigureHouse와 같은 규칙 */
    let lineage_by_house = Map::new();
    for f in list(&model.get("lineageFigures")) {
        let nd = person_of(&model, &f, None);
        let hid = or(or(if tv(&nd) { nd.get("houseId") } else { V::Undef }, f.get("houseId")), s(""));
        if tv(&hid) { lineage_by_house.set(hid.clone(), n(&or(lineage_by_house.get(&hid), V::Num(0.0))) + 1.0); }
    }
    for h in list(&model.get("houses")) {
        let sn = if tv(&h.get("surnameId")) { map_get(&surname_map, &h.get("surnameId")) } else { V::Null };
        if tv(&sn) { ex.put(&h, "x_surname", V::Obj(has(&obj! { "uid" => sn.get("uid"), "name" => sn.get("name") }, "names", names_line(&sn.get("names"))))); }
        /* 세계표(D1): x_kin(열 꼴 뼈대 기록을 가리킴) · x_head(머리 칩 — 짐작은 auto) · x_under(아래 파까지의 가문 id — 파가 있을 때만) · x_eras(다스린 기간 막대) */
        let hk = kin.map_or(V::Undef, |k| k.house_kin.get(&h.get("id")));
        if tv(&hk) {
            // lineage = 계보 전용 인물 수(아래 파 포함 — 0이면 뺌)
            let nl: f64 = under_of(&h.get("id")).iter().map(|id| n(&or(lineage_by_house.get(id), V::Num(0.0)))).sum();
            if nl != 0.0 { let o = js::Obj::new(); if let V::Obj(src) = &hk { for (k, v) in src.entries() { o.set(&k, v); } } o.set("lineage", nl); ex.put(&h, "x_kin", V::Obj(o)); }
            else { ex.put(&h, "x_kin", hk); }
        }
        ex.put(&h, "x_head", head_chips(house_head(&model, &h)));
        let under = under_of(&h.get("id"));
        if under.len() > 1 { ex.put(&h, "x_under", va(under.clone())); }
        ex.put(&h, "x_eras", va(house_eras(&model, &h.get("id")).iter().map(|r| {
            // r.polity는 없음 — r.uid로 byUid
            let p = if tv(&r.uid) { map_get(&by_uid, &r.uid) } else { V::Null };
            let o = obj! {
                "uid" => or(or(r.uid.clone(), if tv(&p) { p.get("uid") } else { p.clone() }), s("")),
                "name" => or(or(r.name.clone(), if tv(&p) { p.get("name") } else { p.clone() }), s("")),
                "color" => or(or(r.color.clone(), if tv(&p) { p.get("color") } else { p.clone() }), s("")),
            };
            let sp = span_of(&V::Num(r.span.0), &V::Num(r.span.1));
            if tv(&sp) { o.set("span", sp); }
            o.set("cells", va(r.cells.iter().map(|c| span_of(&V::Num(c.0), &V::Num(c.1))).filter(tv).collect()));
            // 내각(실권) 자리에 있던 구간(감독 건의 2026-10-14 5번) — 있을 때만
            let real: Vec<V> = r.real.iter().map(|c| span_of(&V::Num(c.0), &V::Num(c.1))).filter(tv).collect();
            if !real.is_empty() { o.set("real", va(real)); }
            // 끝이 열린 구간의 차례(글로는 '~ 미정') — 있을 때만
            if !r.open_cells.is_empty() { o.set("openCells", va(r.open_cells.iter().map(|&i| V::Num(i as f64)).collect())); }
            if !r.open_real.is_empty() { o.set("openReal", va(r.open_real.iter().map(|&i| V::Num(i as f64)).collect())); }
            V::Obj(o)
        }).collect()));
        // 가문 조명: 아래 파까지(10절 12번) — HT.houseSpans(맞닿은 칸 잇기 · 칸 없는 나라는 국성 기간)
        ex.put(&h, "x_spots", spots_min(&house_spans(&model, &under, true)));
    }

    /* ========== 단체 — groupDetailHTML ========== */
    let row_when = |r: &V| -> String { if tv(&r.get("given")) || tv(&r.get("startUnknown")) || tv(&r.get("endUnknown")) { tt.span_text(r) } else { String::new() } };
    let polity_row = |r: &V| -> Obj {
        let o = obj! { "name" => or(r.get("name"), s("")) };
        if tv(&r.get("polityUid")) && map_has(&by_uid, &r.get("polityUid")) { o.set("uid", r.get("polityUid")); o.set("color", or(r.get("color"), s(""))); }
        o
    };
    for g in list(&model.get("groups")) {
        ex.put(&g, "x_type", g.get("typeName"));
        ex.put(&g, "x_span", span_of(&g.get("start"), &g.get("endY")));
        ex.put(&g, "x_within", va(list(&g.get("withinList")).iter().map(|r| {
            let o = has(&polity_row(r), "when", s(&row_when(r)));
            let sp = span_of(&r.get("start"), &r.get("end"));
            if tv(&sp) { o.set("span", sp); }
            V::Obj(o)
        }).collect()));
        ex.put(&g, "x_members", va(list(&g.get("memberList")).iter().map(|r| {
            let o = polity_row(r);
            has(&o, "role", r.get("role"));
            if !js::strict_eq(&r.get("track"), &g.get("track")) { has(&o, "track", track_name(&r.get("track"))); }
            has(&o, "when", s(&row_when(r)));
            has(&o, "note", r.get("note"));
            let sp = span_of(&r.get("start"), &r.get("end"));
            if tv(&sp) { o.set("span", sp); }
            V::Obj(o)
        }).collect()));
        ex.put(&g, "x_power", va(list(&g.get("powerSpans")).iter().map(|c| {
            let o = obj! { "name" => or(c.get("name"), s("")), "when" => tt.cell_when(c, false, &g) };
            let sp = span_of(&c.get("start"), &c.get("end"));
            if tv(&sp) { o.set("span", sp); }
            has(&o, "note", c.get("note"));
            if tv(&c.get("endAuto")) { o.set("endAuto", 1.0); }
            if tv(&c.get("endUnknown")) { o.set("endUnknown", 1.0); }
            V::Obj(o)
        }).collect()));
        let how = |f: &V| -> Obj {
            let o = Obj::new();
            if tv(&f.get("how")) { o.set("how", f.get("how")); o.set("howName", group_how_name(&f.get("how"))); }
            has(&o, "note", f.get("note"))
        };
        let assign = |a: Obj, b: Obj| -> V { for (k, v) in b.entries() { a.set(&k, v); } V::Obj(a) };
        ex.put(&g, "x_from", va(list(&g.get("fromList")).iter().map(|f| {
            let gg = f.get("group");
            let base = if tv(&gg) { obj! { "uid" => gg.get("uid"), "name" => or(gg.get("name"), s("")) } } else { obj! { "name" => or(f.get("name"), s("")), "missing" => 1.0 } };
            assign(base, how(f))
        }).collect()));
        ex.put(&g, "x_into", va(list(&g.get("intoList")).iter().map(|f| { let gg = f.get("group"); assign(obj! { "uid" => gg.get("uid"), "name" => or(gg.get("name"), s("")) }, how(f)) }).collect()));
        // 구성원 칩(memberChipHTML): 인물 → 인물 창 · 인물 없는 사람 자리의 첫 칸 → 그 칸 · 못 찾은 이름은 누를 수 없는 칩
        ex.put(&g, "x_people", va(list(&g.get("peopleList")).iter().map(|p| {
            let fg = p.get("figure");
            if tv(&p.get("uid")) && tv(&fg) { return V::Obj(has(&has(&obj! { "name" => or(fg.get("name"), s("")), "uid" => p.get("uid") }, "role", fg.get("role")), "color", fg.get("color"))); }
            let c = if tv(&p.get("person")) { list(&p.get("person").get("cells")).first().cloned().unwrap_or(V::Undef) } else { V::Undef };
            if tv(&c) { return V::Obj(has(&obj! { "name" => or(p.get("person").get("name"), s("")), "uid" => c.get("p").get("uid"), "ref" => c.get("ref"), "polity" => or(c.get("p").get("name"), s("")) }, "color", c.get("p").get("color"))); }
            V::Obj(obj! { "name" => or(p.get("name"), s("")), "missing" => 1.0 })
        }).collect()));
        let ei = g.get("eventItem");
        if tv(&ei) { ex.put(&g, "x_event", V::Obj(obj! { "uid" => ei.get("uid"), "title" => or(ei.get("title"), s("")), "when" => format_range(w.rc, &ei) })); }
        ex.put(&g, "x_warnings", va(list(&g.get("warnings"))));
    }

    /* ========== 제도 — institutionDetailHTML ========== */
    for it in list(&model.get("institutions")) {
        let p = or(it.get("polityItem"), V::Null);
        ex.put(&it, "x_theme", V::Obj(has(&obj! { "id" => or(it.get("themeId"), s("")), "name" => or(it.get("themeName"), s("")) }, "color", it.get("themeColor"))));
        ex.put(&it, "x_polity", V::Obj(if tv(&p) && map_has(&by_uid, &p.get("uid")) { obj! { "uid" => p.get("uid"), "name" => or(p.get("name"), s("")), "color" => or(p.get("color"), s("")) } } else { obj! { "name" => or(it.get("polityName"), s("")) } }));
        ex.put(&it, "x_spans", va(list(&it.get("spanList")).iter().map(|sp| {
            let o = obj! { "name" => or(sp.get("name"), s("")), "when" => phase_range_text(w, sp, &p) };
            let ss = span_of(&sp.get("start"), &sp.get("end"));
            if tv(&ss) { o.set("span", ss); }
            has(&o, "note", sp.get("note"));
            let from = sp.get("from");
            if tv(&from) {
                let f = obj! { "polity" => or(from.get("polity"), s("")) };
                has(&f, "name", from.get("name"));
                let fi = sp.get("fromItem");
                if tv(&fi) && map_has(&by_uid, &fi.get("uid")) { f.set("uid", fi.get("uid")); f.set("color", or(fi.get("color"), s(""))); }
                o.set("from", f);
            }
            if tv(&sp.get("guess")) { o.set("guess", 1.0); }
            V::Obj(o)
        }).collect()));
        ex.put(&it, "x_same", va(list(&it.get("sameFamily")).iter().map(|q| V::Obj(obj! {
            "uid" => q.get("uid"), "name" => or(q.get("name"), s("")), "polity" => or(q.get("polityName"), s("")), "color" => or(q.get("color"), s("")),
            "when" => tt.span_text(&V::Obj(obj! { "start" => q.get("start"), "end" => q.get("endY") })),
        })).collect()));
        ex.put(&it, "x_warnings", va(list(&it.get("warnings"))));
    }

    /* ========== 지명 · 성씨 ========== */
    for pl in list(&model.get("places")) {
        let path = list(&pl.get("path"));
        let upto = &path[..path.len().saturating_sub(1)];
        let chip = |q: &V| V::Obj(obj! { "uid" => q.get("uid"), "name" => q.get("name") });
        ex.put(&pl, "x_path", va(upto.iter().map(|id| map_get(&place_map, id)).filter(tv).map(|q| chip(&q)).collect()));
        ex.put(&pl, "x_children", va(list(&pl.get("children")).iter().map(|id| map_get(&place_map, id)).filter(tv).map(|q| chip(&q)).collect()));
        ex.put(&pl, "x_uses", va(list(&pl.get("uses")).iter().filter_map(|u| {
            if is(&u.get("role"), "map") {
                let m = if tv(&model.get("mapMap")) { map_get(&model.get("mapMap"), &u.get("mapId")) } else { V::Undef };
                return Some(V::Obj(if tv(&m) { obj! { "role" => "map", "uid" => m.get("uid"), "name" => or(m.get("name"), m.get("id")) } } else { obj! { "role" => "map", "name" => or(u.get("mapId"), s("")), "missing" => 1.0 } }));
            }
            let it = u.get("item");
            if !tv(&it) || !map_has(&by_uid, &it.get("uid")) { return None; }
            let o = obj! { "role" => u.get("role"), "uid" => it.get("uid") };
            if tv(&u.get("ref")) { o.set("ref", u.get("ref")); }
            o.set("name", or(or(it.get("title"), it.get("name")), s("")));
            let cell = if tv(&u.get("ref")) {
                // HT.cellsOf(it, ref.split(':')[0])[Number(ref.split(':')[1])]
                let rf = t(&u.get("ref"));
                let parts: Vec<&str> = rf.split(':').collect();
                let idx = match parts.get(1) { Some(i) => js::to_num(&s(i)), None => f64::NAN };
                if idx >= 0.0 && idx == idx.trunc() { cells_of(&it, parts[0]).get(idx as usize).cloned().unwrap_or(V::Undef) } else { V::Undef }
            } else { V::Null };
            o.set("when", if tv(&cell) { tt.cell_when(&cell, cell.get("end").is_nullish(), &it) } else { format_range(w.rc, &it) });
            Some(V::Obj(o))
        }).collect()));
    }
    for sn in list(&model.get("surnames")) {
        ex.put(&sn, "x_houses", va(list(&sn.get("houses")).iter().map(|id| map_get(&house_map, id)).filter(tv).map(|h| V::Obj(obj! {
            "uid" => h.get("uid"), "name" => or(h.get("name"), s("")), "color" => or(h.get("color"), s("")),
        })).collect()));
        // 성씨 조명(결정 7 A): 그 성의 모든 가문(과 아래 파)의 구간 — 같은 칠
        let hs = list(&sn.get("houses"));
        if !hs.is_empty() {
            let ids = Set::new();
            for id in &hs { for u in under_of(id) { ids.add(u); } }
            ex.put(&sn, "x_spots", spots_min(&house_spans(&model, &ids.values(), true)));
        }
    }

    /* ========== 계보 전용 인물(D1 — model.lineageFigures): 뼈대 자리 x_kin ========== */
    for f in list(&model.get("lineageFigures")) {
        // 그 사람이 구성원으로 든 뼈대 — HT.kinOfPerson(웹)이 먼저, 없으면 뼈대들의 안정 열쇠에서
        let Some(k) = kin else { continue };
        let pkey = format!("f:{}", t(&f.get("uid")));
        let w_ = kin_of_person(&mut kc,&model, &pkey);
        let at: Option<(String, f64, Option<String>)> = match w_ {
            Some((key, at)) if k.roots.contains(&key) => { let ch = k.chunk_at(&key, at as i64); Some((key, at as f64, ch)) }
            _ => k.person_at.get(&Str::from(pkey.as_str())).map(|p| (p.key.clone(), p.at as f64, p.chunk.clone())),
        };
        if let Some((key, at, chunk)) = at { ex.put(&f, "x_kin", V::Obj(has(&obj! { "key" => key, "at" => at }, "chunk", chunk.map_or(V::Undef, V::from)))); }
    }

    /* ========== 모아 보기 판 · 지도 — 나르기만(화면은 A3) ========== */
    for v in list(&model.get("views")) {
        let mut outl: Vec<V> = Vec::new();
        let seen = Set::new();
        let members = list(&v.get("members"));
        for rf in cells::read_scope_refs(&v.get("memberRefs")) {
            let m = members.iter().find(|p| (is(&p.get("name"), &rf.polity.as_str()) || is(&p.get("id"), &rf.polity.as_str()) || is(&p.get("uid"), &rf.polity.as_str()))
                && (rf.track.as_ref().is_none_or(|tr| tr.is_empty()) || rf.track.as_ref().is_some_and(|tr| is(&p.get("track"), &tr.as_str()))));
            let key = match m { Some(m) => m.get("uid"), None => V::from(format!("?{}", scope_ref_text(&rf))) };
            if seen.has(&key) { continue; }
            seen.add(key);
            outl.push(match m { Some(m) => V::Obj(obj! { "uid" => m.get("uid"), "name" => or(m.get("name"), s("")), "color" => or(m.get("color"), s("")) }), None => V::Obj(obj! { "name" => scope_ref_text(&rf), "missing" => 1.0 }) });
        }
        for m in &members {
            if !seen.has(&m.get("uid")) {
                seen.add(m.get("uid"));
                outl.push(V::Obj(obj! { "uid" => m.get("uid"), "name" => or(m.get("name"), s("")), "color" => or(m.get("color"), s("")) }));
            }
        }
        ex.put(&v, "x_members", va(outl));
        if !v.get("start").is_nullish() { ex.put(&v, "x_span", span_of(&v.get("start"), &v.get("endY"))); }
    }
    for m in list(&model.get("maps")) {
        ex.put(&m, "x_scenes", va(list(&m.get("scenes")).iter().map(|sc| {
            let owners = Obj::new();
            let items = or(sc.get("items"), V::Obj(Obj::new()));
            if let V::Obj(ow) = or(sc.get("owners"), V::Obj(Obj::new())) {
                for (rid, rf) in ow.entries() {
                    let it = items.get(&rid);
                    let val = if tv(&it) && map_has(&by_uid, &it.get("uid")) { obj! { "uid" => it.get("uid"), "name" => or(it.get("name"), s("")), "color" => or(it.get("color"), s("")) } } else {
                        let text = cells::read_scope_ref(&rf).map_or(Str::default(), |r| scope_ref_text(&r));
                        obj! { "name" => if !text.is_empty() { V::Str(text) } else { V::Str(js::to_str(&crate::lay::model::util::nn(rf.clone(), s("")))) }, "missing" => 1.0 }
                    };
                    owners.set(&rid, val);
                }
            }
            let o = obj! { "year" => sc.get("year"), "at" => mm(&sc.get("year")) };
            if tv(&sc.get("yearAt")) { o.set("yearAt", sc.get("yearAt")); }
            o.set("owners", owners);
            has(&o, "note", sc.get("note"));
            V::Obj(o)
        }).collect()));
    }
    cx.kc = kc;
}

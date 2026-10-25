//! `linkPeople(model, packs)` — 지명 · 성씨 · 사람 · 계보(형식 버전 3)를 줄 그대로(`js/core.js` 6254 ~ 6827줄 — SHA-256 앞 12자 `9c786cf58566`).
//! ① 지명(model.places · placeMap · placeByName) ② 성씨(model.surnames · surnameMap) ③ 사람(model.persons · personIndex — 칸 · 인물 · 이름 열쇠를 하나로 묶음 ·
//! 혈연 · 가문 · 뼈대 열쇠 · 고리 알림) ④ 자리 이음(accessionFrom) · 알림(peopleWarnings). 원문 칸은 고쳐 쓰지 않는다.
//! 사람 자리(`nodes`)는 JS 객체 그대로(모델에 든다 — 이음매 ②가 덤프), 가문의 파조 자리 `h.founderNode`는 열거되지 않는 속성.
//! (2026-10-25 kin-resolve `357e5a3` 합침 · `core.js` `6774cd6ebf9f`) 7197 ~ 7235줄 `resolve` — 찾은 인물보다 같은 나라의 같은 이름 지도자가 먼저(그 인물이 이 나라를
//! 섬긴 적도 이 나라가 있던 때 산 적도 없을 때) · 같은 이름 지도자가 여럿이면 생몰(칸 기간) `lo` · `hi`와 가까운 때[시작 − 80, 끝] 다스린 지도자만(`near`) ·
//! 7270 · 7271 · 7541줄 혈연 · 앞 지도자 찾기 맥락의 `lo` · `hi`. 구성원 찾기(`memberNode`)는 예전 세 갈래 그대로.
//! (2026-10-25 remake-int2 합침 · `core.js` `e7c6715650cc`) 6단계 옮겨 앉기(remake-6-code)가 앞에 39줄 들어 `resolve`는 7236 ~ 7274줄 · 맥락은 7309 · 7310 · 7580줄(뜻은 그대로).
use super::push_list;
use crate::lay::js::{self, Arr, Map, Obj, Set, Str, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, assign_obj, copy, eq, has, is, item_kind_of, kin_name, le, leader_label, list, lt, n, nn, ob, or, s, sub, t, tv};
use crate::lay::read::{misc, names, Ctx as RCtx};
use std::cell::Cell;

/// 찾기의 맥락(`ctx` — { packId, track, start, polity?, lo?, hi?, item?, label? }). `lo` · `hi`는 혈연 · 앞 지도자 찾기만(생몰 · 칸 기간 — 없으면 `V::Undef`).
#[derive(Clone)]
struct Cx { pack_id: V, track: V, start: V, polity: V, lo: V, hi: V, item: V, label: String }
/// `findFigure`의 답: 없음 · 여럿이라 고를 수 없음(AMBIGUOUS) · 인물.
enum Fig { None, Ambiguous, One(V) }
/// `findCellRef`의 답 `{ p, i, kind, c }`.
struct Hit { p: V, i: usize, kind: &'static str }

/// 수 값이 x인가.
fn is_num(v: &V, x: f64) -> bool { matches!(v, V::Num(y) if *y == x) }
/// `String(v ?? '').trim()`.
fn tt(v: &V) -> Str { js::to_str(&nn(v.clone(), s(""))).trim() }
fn starts(k: &Str, pre: &str) -> bool { k.as_str().starts_with(pre) }

/// `linkPeople(model, packs)`.
pub fn link_people(rc: &RCtx, model: &V, packs: &[V]) {
    let mo = ob(model);
    let periods = list(&model.get("periods"));
    let events = list(&model.get("events"));
    let docs = crate::lay::model::util::mp(&model.get("docs"), "model.docs");
    let figures: Vec<V> = list(&model.get("figures")).into_iter().chain(list(&model.get("lineageFigures"))).collect();
    let warnings = Arr::default();
    let warn_at = |x: &V, msg: String| {
        let has_x = tv(x);
        let list_word = if !has_x { s("") } else if is(&x.get("kind"), "figure") { s("figures") } else if is(&x.get("kind"), "event") { s("events") } else {
            s(match item_kind_of(x) { V::Str(k) => match k.as_str().as_ref() { "organ" => "organs", "culture" => "cultures", "dynasty" => "dynasties", _ => "periods" }, _ => "periods" })
        };
        warnings.push(o! { "msg" => msg, "packId" => if has_x { or(x.get("packId"), s("")) } else { s("") }, "list" => list_word, "id" => if has_x { x.get("id") } else { s("") } });
    };

    // ① 지명
    let places = Map::new();
    let place_by_name = Map::new();
    let pseq = Cell::new(0.0);
    let add_place = |x: &V, auto: bool| -> V {
        let id = x.get("id");
        if places.has(&id) { return places.get(&id); }
        let sq = pseq.get();
        pseq.set(sq + 1.0);
        let nm = x.get("names");
        let at = x.get("at");
        let o = o! {
            "id" => id.clone(), "uid" => format!("place:{}", t(&id)), "itemKind" => "place", "name" => or(x.get("name"), id.clone()),
            "names" => if matches!(nm, V::Arr(_)) { nm } else { arr(Vec::new()) }, "at" => if matches!(at, V::Arr(_)) { at } else { V::Null },
            "parent" => or(x.get("parent"), s("")), "note" => or(x.get("note"), s("")), "description" => or(x.get("description"), s("")), "wiki" => or(x.get("wiki"), s("")),
            "packId" => or(x.get("packId"), s("")), "packName" => or(x.get("packName"), s("")), "auto" => auto, "seq" => sq, "uses" => arr(Vec::new()),
        };
        places.set(id, o.clone());
        if !place_by_name.has(&o.get("name")) { place_by_name.set(o.get("name"), o.clone()); }
        V::Obj(o)
    };
    for pack in packs {
        for x in list(&pack.get("places")) {
            let nmv = or(x.get("name"), x.get("id"));
            let twin = if !places.has(&x.get("id")) { place_by_name.get(&nmv) } else { V::Bool(false) };
            if tv(&twin) && eq(&twin.get("packId"), &pack.get("id")) {
                warnings.push(o! { "msg" => format!("지명 사전에 이름 \"{}\"이(가) 둘 있습니다({} · {}) — 이름으로 적은 곳은 앞의 지명에 붙습니다. 뒤의 지명은 id로 적습니다.", t(&nmv), t(&twin.get("id")), t(&x.get("id"))),
                    "packId" => pack.get("id"), "list" => "places", "id" => x.get("id") });
            }
            let o = o! { "packId" => pack.get("id"), "packName" => pack.get("name") };
            assign_obj(&o, &copy(&x));
            add_place(&V::Obj(o), false);
        }
    }
    let find_place = |r: &V| -> V {
        let k = tt(r);
        if k.is_empty() { return V::Null; }
        let kv = V::Str(k);
        let g = places.get(&kv);
        if tv(&g) { return g; }
        let g = place_by_name.get(&kv);
        if tv(&g) { g } else { V::Null }
    };
    let ensure_place = |r: &V| -> V {
        let k = tt(r);
        if k.is_empty() { return V::Null; }
        let f = find_place(r);
        if tv(&f) { f } else { add_place(&V::Obj(o! { "id" => format!("pl-{}", misc::hash(&k)), "name" => k }), true) }
    };
    for p in &periods {
        if !is(&item_kind_of(p), "period") { continue; }
        for (i, c) in list(&p.get("capitals")).iter().enumerate() {
            let by_id = if tv(&c.get("placeId")) { places.get(&c.get("placeId")) } else { V::Undef };
            let pl = if tv(&by_id) { by_id } else { ensure_place(&c.get("city")) };
            if tv(&pl) {
                push_list(&pl, "uses", V::Obj(o! { "role" => "capital", "item" => p.clone(), "ref" => format!("capital:{i}"), "start" => c.get("start"),
                    "end" => nn(nn(c.get("endY"), c.get("end")), c.get("start")), "as" => or(c.get("as"), s("")) }));
            }
        }
    }
    for e in &events {
        let pl = ensure_place(&e.get("place"));
        if tv(&pl) { push_list(&pl, "uses", V::Obj(o! { "role" => "event", "item" => e.clone(), "start" => e.get("start"), "end" => e.get("endY") })); }
        let tp = if tv(&e.get("treaty")) { ensure_place(&e.get("treaty").get("place")) } else { V::Null };
        if tv(&tp) { push_list(&tp, "uses", V::Obj(o! { "role" => "treaty", "item" => e.clone(), "start" => e.get("start"), "end" => e.get("endY") })); }
    }
    // 지도의 지명 글 목록(maps[].places): 같은 찾기로 지명 사전에 — 쓰인 곳의 맨 앞에(role 'map' · item 없음)
    for pack in packs {
        for m in list(&pack.get("maps")) {
            for r in list(&m.get("places")) {
                let pl = ensure_place(&r);
                if tv(&pl) && !list(&pl.get("uses")).iter().any(|u| is(&u.get("role"), "map") && eq(&u.get("mapId"), &m.get("id"))) {
                    push_list(&pl, "uses", V::Obj(o! { "role" => "map", "item" => V::Null, "mapId" => m.get("id"), "start" => -9_007_199_254_740_991.0 }));
                }
            }
        }
    }
    for pl in places.values() {
        let up = if tv(&pl.get("parent")) { ensure_place(&pl.get("parent")) } else { V::Null };
        ob(&pl).set("parentId", if tv(&up) && !eq(&up, &pl) { up.get("id") } else { V::Null });
    }
    for pl in places.values() {
        let mut path: Vec<V> = Vec::new();
        let seen = Set::new();
        let mut cur = pl.clone();
        while tv(&cur) && !seen.has(&cur.get("id")) {
            seen.add(cur.get("id"));
            path.insert(0, cur.get("id"));
            cur = if tv(&cur.get("parentId")) { places.get(&cur.get("parentId")) } else { V::Null };
        }
        ob(&pl).set("path", arr(path));
        ob(&pl).set("children", arr(Vec::new()));
    }
    for pl in places.values() {
        if tv(&pl.get("parentId")) && !eq(&places.get(&pl.get("parentId")), &pl) { push_list(&places.get(&pl.get("parentId")), "children", pl.get("id")); }
    }
    for pl in places.values() { if let V::Arr(u) = pl.get("uses") { u.sort_js(|a, c| sub(&a.get("start"), &c.get("start"))); } }
    // ② 성씨
    let surnames = Map::new();
    let surname_by_name = Map::new();
    let add_surname = |x: &V, auto: bool| -> V {
        let id = x.get("id");
        if surnames.has(&id) { return surnames.get(&id); }
        let nm = x.get("names");
        let o = o! {
            "id" => id.clone(), "uid" => format!("surname:{}", t(&id)), "itemKind" => "surname", "name" => or(x.get("name"), id.clone()),
            "names" => if matches!(nm, V::Arr(_)) { nm } else { arr(Vec::new()) }, "description" => or(x.get("description"), s("")), "wiki" => or(x.get("wiki"), s("")),
            "packId" => or(x.get("packId"), s("")), "packName" => or(x.get("packName"), s("")), "auto" => auto, "houses" => arr(Vec::new()),
        };
        surnames.set(id, o.clone());
        if !surname_by_name.has(&o.get("name")) { surname_by_name.set(o.get("name"), o.clone()); }
        V::Obj(o)
    };
    for pack in packs {
        for x in list(&pack.get("surnames")) {
            let o = o! { "packId" => pack.get("id"), "packName" => pack.get("name") };
            assign_obj(&o, &copy(&x));
            add_surname(&V::Obj(o), false);
        }
    }
    for h in list(&model.get("houses")) {
        let r = tt(&h.get("surname"));
        if r.is_empty() { continue; }
        let rv = V::Str(r.clone());
        let g = surnames.get(&rv);
        let sn = if tv(&g) { g } else { let g = surname_by_name.get(&rv); if tv(&g) { g } else { add_surname(&V::Obj(o! { "id" => format!("sn-{}", misc::hash(&r)), "name" => rv.clone() }), true) } };
        ob(&h).set("surnameId", sn.get("id"));
        push_list(&sn, "houses", h.get("id"));
    }
    // 문서: 사전의 wiki → "place:id" · "surname:id"(DLC의 documents · 내 글이 먼저)
    for x in places.values().into_iter().chain(surnames.values()) {
        if tv(&x.get("wiki")) && !docs.has(&x.get("uid")) { docs.set(x.get("uid"), o! { "text" => x.get("wiki"), "packId" => x.get("packId"), "packName" => x.get("packName") }); }
        let d = docs.get(&x.get("uid"));
        if tv(&d) { ob(&x).set("wiki", d.get("text")); }
    }
    mo.set("places", arr(places.values()));
    mo.set("placeMap", places.clone());
    mo.set("placeByName", place_by_name.clone());
    mo.set("surnames", arr(surnames.values()));
    mo.set("surnameMap", surnames.clone());

    // ③ 사람 — 열쇠: 인물 "f:uid" · 칸 "c:정권 uid|leader:3" · 이름 "n:글" · 미상 "u:n". 같은 사람의 열쇠는 하나로(뿌리 — 인물이 있으면 인물)
    let up = Map::new();
    let root = |k: &Str| -> Str {
        let mut r = k.clone();
        loop {
            let nx = up.get(&V::Str(r.clone()));
            match nx { V::Str(x) if x != r => r = x, _ => break }
        }
        // 길 줄이기: 지나온 열쇠를 모두 뿌리에 바로 잇는다
        let mut k2 = k.clone();
        let mut nx = up.get(&V::Str(k2.clone()));
        while k2 != r && !matches!(&nx, V::Str(x) if *x == r) {
            up.set(V::Str(k2.clone()), V::Str(r.clone()));
            let V::Str(next) = nx else { break };
            k2 = next;
            nx = up.get(&V::Str(k2.clone()));
        }
        r
    };
    let join = |a: &Str, b: &Str| {
        let ra = root(a);
        let rb = root(b);
        if ra == rb { return; }
        if starts(&ra, "f:") && !starts(&rb, "f:") { up.set(V::Str(rb), V::Str(ra)); } else { up.set(V::Str(ra), V::Str(rb)); }
    };
    let fig_by_uid = Map::new();
    for f in &figures { fig_by_uid.set(f.get("uid"), f.clone()); }
    let fig_by_id = Map::new();
    for f in &figures { if !fig_by_id.has(&f.get("id")) { fig_by_id.set(f.get("id"), f.clone()); } }
    let unknown_figure = |f: &V| matches!(f.get("lineageOnly"), V::Bool(true)) && names::is_unknown_who(&f.get("name"));
    let fig_by_name = Map::new();
    let by_name_add = |nm: &V, f: &V| {
        if !tv(nm) { return; }
        match fig_by_name.get(nm) { V::Arr(l) => l.push(f.clone()), _ => fig_by_name.set(nm.clone(), Arr::new(vec![f.clone()])) }
    };
    for f in &figures {
        if unknown_figure(f) { continue; }
        by_name_add(&f.get("name"), f);
        if tv(&f.get("aka")) { for nm in list(&f.get("aka")) { by_name_add(&nm, f); } }
        if tv(&f.get("names")) { for x in list(&f.get("names")) { by_name_add(&x.get("text"), f); } }
    }
    // 날짜가 없는 사람(계보 전용 — spanMin null)은 어느 시기와도 겹치지 않는다
    let overlaps = |f: &V, a: &V, b: &V| -> bool {
        !f.get("spanMin").is_nullish() && !f.get("spanMax").is_nullish() && super::super::model::util::le(&f.get("spanMin"), b) && n(a) <= n(&f.get("spanMax")) + 1.0
    };
    let ambiguous_msg = |st: &Str| format!("\"{st}\"은(는) 같은 이름의 인물이 여럿이라 고를 수 없습니다 — 인물 id로 적습니다.");
    let find_figure = |r: &V, cx: &Cx| -> Fig {
        let k = tt(r);
        if k.is_empty() { return Fig::None; }
        let kv = V::Str(k.clone());
        let want = if k.index_of16(&Str::from("/"), 0.0) >= 0.0 { kv.clone() } else { V::from(format!("{}/{k}", t(&cx.pack_id))) };
        let by_id = fig_by_uid.get(&want);
        if tv(&by_id) { return Fig::One(by_id); }
        let by_id = fig_by_id.get(&kv);
        if tv(&by_id) { return Fig::One(by_id); }
        let hit_set = Set::new();
        for f in list(&fig_by_name.get(&kv)) { hit_set.add(f); }
        let hit = hit_set.values();
        if hit.len() < 2 { return hit.first().cloned().map_or(Fig::None, Fig::One); }
        let score = |f: &V| -> f64 { (if eq(&f.get("track"), &cx.track) { 10.0 } else { 0.0 }) + (if !cx.start.is_nullish() && overlaps(f, &cx.start, &cx.start) { 5.0 } else { 0.0 }) };
        let best = js::max(&hit.iter().map(score).collect::<Vec<_>>());
        let top: Vec<V> = hit.iter().filter(|f| score(f) == best).cloned().collect();
        if top.len() == 1 { Fig::One(top[0].clone()) } else { Fig::Ambiguous }
    };
    let cell_key = |p: &V, r: &str| -> Str { Str::from(format!("c:{}|{r}", t(&p.get("uid")))) };
    let leader_names = |c: &V| -> Vec<V> { ["name", "temple", "title", "given"].iter().map(|k| c.get(*k)).filter(tv).collect() };
    let polities_in = |name: &V, track: &V| -> Vec<V> {
        let ok = |q: &V| is(&q.get("itemKind"), "period") && (eq(&q.get("name"), name) || eq(&q.get("id"), name) || eq(&q.get("uid"), name));
        let same: Vec<V> = periods.iter().filter(|q| eq(&q.get("track"), track) && ok(q)).cloned().collect();
        if !same.is_empty() { same } else { periods.iter().filter(|q| ok(q)).cloned().collect() }
    };
    // 지도자 칸 참조 { track?, polity, leader, start? } → { p, i, kind, c } — 시작 해를 적었으면 그해에 시작한 칸, 아니면 첫 칸
    let find_cell_ref = |r: &V, cx: &Cx| -> Option<Hit> {
        for p in polities_in(&r.get("polity"), &or(r.get("track"), cx.track.clone())) {
            for (kind, l) in [("leader", list(&p.get("leaders"))), ("cabinet", list(&p.get("cabinets")))] {
                let cands: Vec<(usize, V)> = l.into_iter().enumerate().filter(|(_, c)| {
                    let nms = if kind == "leader" { leader_names(c) } else { vec![c.get("name")] };
                    has(&nms, &r.get("leader"))
                }).collect();
                if cands.is_empty() { continue; }
                if r.get("start").is_nullish() { return Some(Hit { p: p.clone(), i: cands[0].0, kind }); }
                let rs = n(&r.get("start"));
                let y = (rs + 1e-9).floor();
                if let Some((i, _)) = cands.iter().find(|(_, c)| (n(&c.get("start")) + 1e-9).floor() == y) { return Some(Hit { p: p.clone(), i: *i, kind }); }
                let mut acc = &cands[0];
                for b in &cands[1..] { if (n(&b.1.get("start")) - rs).abs() < (n(&acc.1.get("start")) - rs).abs() { acc = b; } }
                return Some(Hit { p: p.clone(), i: acc.0, kind });
            }
        }
        None
    };
    // 모든 지도자 칸 · 사람을 적은 내각 칸
    let mut cells: Vec<V> = Vec::new();
    for p in &periods {
        if !is(&item_kind_of(p), "period") { continue; }
        for (i, c) in list(&p.get("leaders")).iter().enumerate() { cells.push(V::Obj(o! { "p" => p.clone(), "kind" => "leader", "i" => i as f64, "ref" => format!("leader:{i}"), "c" => c.clone() })); }
        for (i, c) in list(&p.get("cabinets")).iter().enumerate() {
            if tv(&c.get("person")) { cells.push(V::Obj(o! { "p" => p.clone(), "kind" => "cabinet", "i" => i as f64, "ref" => format!("cabinet:{i}"), "c" => c.clone() })); }
        }
    }
    let x_key = |x: &V| cell_key(&x.get("p"), &t(&x.get("ref")));
    let fk = |f: &V| -> Str { Str::from(format!("f:{}", t(&f.get("uid")))) };
    for f in &figures { up.set(V::Str(fk(f)), V::Str(fk(f))); }
    let named = Set::new();
    for x in &cells {
        let k = x_key(x);
        if !up.has(&V::Str(k.clone())) { up.set(V::Str(k.clone()), V::Str(k.clone())); }
        let (p, c) = (x.get("p"), x.get("c"));
        let cx = Cx { pack_id: p.get("packId"), track: p.get("track"), start: c.get("start"), polity: V::Undef, lo: V::Undef, hi: V::Undef, item: V::Undef, label: String::new() };
        let r = c.get("person");
        let who_word = if is(&x.get("kind"), "leader") { "지도자" } else { "내각" };
        if tv(&r) && js::type_of(&r) == "object" {
            let hit = find_cell_ref(&r, &cx);
            // JS: hit && !(hit.p === x.p && hit.ref === x.ref) — 찾은 것에는 ref가 없어(undefined) 늘 참
            if let Some(h) = hit { join(&k, &cell_key(&h.p, &format!("{}:{}", h.kind, h.i))); }
            else { warn_at(&p, format!("{} {who_word} \"{}\"의 사람 \"{}\"을(를) 찾지 못했습니다.", t(&p.get("name")), t(&c.get("name")), names::person_ref_text(&r))); }
        } else if tv(&r) {
            let f = find_figure(&r, &cx);
            if matches!(f, Fig::Ambiguous) { warn_at(&p, format!("{} {who_word} \"{}\"의 사람 {}", t(&p.get("name")), t(&c.get("name")), ambiguous_msg(&tt(&r)))); }
            match f {
                Fig::One(f) => join(&k, &fk(&f)),
                _ => {
                    named.add(V::Str(tt(&r)));
                    join(&k, &Str::from(format!("n:{}", tt(&r))));
                }
            }
        } else if is(&x.get("kind"), "leader") {
            // 적지 않았으면 같은 이름의 인물과 저절로(계보 전용 인물은 저절로 잇지 않음)
            let end = nn(c.get("end"), p.get("endY"));
            let f = leader_names(&c).iter().flat_map(|nm| list(&fig_by_name.get(nm))).find(|f| {
                !matches!(f.get("lineageOnly"), V::Bool(true)) && overlaps(f, &c.get("start"), &end)
                    && (eq(&f.get("track"), &p.get("track")) || list(&f.get("services")).iter().any(|sv| eq(&sv.get("polity"), &p)))
            });
            if let Some(f) = f { join(&k, &fk(&f)); }
        }
    }
    let useq = Cell::new(0.0);
    let nodes = Map::new();
    let node_of = |key: &Str| -> V {
        let r = root(key);
        let rv = V::Str(r.clone());
        let g = nodes.get(&rv);
        if tv(&g) { return g; }
        let nd = o! {
            "key" => rv.clone(), "name" => "", "figure" => V::Null, "figures" => arr(Vec::new()), "cells" => arr(Vec::new()), "parents" => arr(Vec::new()),
            "spouses" => arr(Vec::new()), "children" => arr(Vec::new()), "groups" => arr(Vec::new()), "houseId" => V::Null, "unknown" => starts(&r, "u:"), "missing" => false,
        };
        nodes.set(rv, nd.clone());
        V::Obj(nd)
    };
    for f in &figures {
        let nd = node_of(&fk(f));
        push_list(&nd, "figures", f.clone());
        if !tv(&nd.get("figure")) { ob(&nd).set("figure", f.clone()); }
        if unknown_figure(f) { ob(&nd).set("unknown", true); }
    }
    for x in &cells { push_list(&node_of(&x_key(x)), "cells", x.clone()); }
    for nm in named.values() { node_of(&Str::from(format!("n:{}", t(&nm)))); }
    // 이름으로 가리킨 사람(who · from): 인물 → 칸의 person 이름 → 지도자 칸의 이름(같은 나라 → 같은 트랙 → 모두에서 하나뿐일 때) → 못 찾으면 그 이름의 자리(missing)
    let leader_by_name = Map::new();
    for x in &cells {
        if !is(&x.get("kind"), "leader") { continue; }
        for nm in leader_names(&x.get("c")) {
            match leader_by_name.get(&nm) { V::Arr(l) => l.push(x.clone()), _ => leader_by_name.set(nm, Arr::new(vec![x.clone()])) }
        }
    }
    let one = |l: &[V]| -> bool { let set = Set::new(); for x in l { set.add(V::Str(root(&x_key(x)))); } set.len() == 1 };
    // 같은 나라 → 같은 트랙 → 모두. `near`(resolve만 — 구성원 찾기는 이 셋뿐)면 그 뒤에 같은 트랙 · 모두의 가까운 때 지도자:
    // 같은 이름의 지도자가 여럿이면(고려 현종 · 조선 현종) 이 사람의 생몰(지도자 칸이면 그 칸의 기간)과 가까운 때 다스린 지도자만 — 칸의 기간이 [시작 − 80, 끝]에 걸침
    let pick_leader = |ls: &[V], cx: &Cx, near: bool| -> Option<V> {
        let by_polity: Vec<V> = ls.iter().filter(|x| eq(&x.get("p"), &cx.polity)).cloned().collect();
        let by_track: Vec<V> = ls.iter().filter(|x| eq(&x.get("p").get("track"), &cx.track)).cloned().collect();
        let close = |l: &[V]| -> Vec<V> {
            if cx.lo.is_nullish() { return Vec::new(); }
            l.iter().filter(|x| {
                let c = x.get("c");
                let cs = c.get("start");
                !cs.is_nullish() && le(&cs, &cx.hi) && le(&V::Num(n(&cx.lo) - 80.0), &nn(c.get("end"), nn(x.get("p").get("endY"), cs.clone())))
            }).cloned().collect()
        };
        let mut tries = vec![by_polity, by_track.clone(), ls.to_vec()];
        if near { tries.push(close(&by_track)); tries.push(close(ls)); }
        tries.into_iter().find(|l| !l.is_empty() && one(l)).map(|l| l[0].clone())
    };
    let resolve = |r: &V, cx: &Cx, what: &str| -> V {
        if tv(r) && js::type_of(r) == "object" {
            if let Some(h) = find_cell_ref(r, cx) { return node_of(&cell_key(&h.p, &format!("{}:{}", h.kind, h.i))); }
            warn_at(&cx.item, format!("{}의 {what} \"{}\"을(를) 찾지 못했습니다.", cx.label, names::person_ref_text(r)));
            let nd = node_of(&Str::from(format!("n:{}", names::person_ref_text(r))));
            ob(&nd).set("missing", true);
            return nd;
        }
        let st = tt(r);
        if st.is_empty() { return V::Null; }
        let found = find_figure(&V::Str(st.clone()), cx);
        if matches!(found, Fig::Ambiguous) {
            warn_at(&cx.item, format!("{}의 {what} {}", cx.label, ambiguous_msg(&st)));
            let nd = node_of(&Str::from(format!("n:{st}")));
            if !named.has(&V::Str(st.clone())) { ob(&nd).set("missing", true); }
            return nd;
        }
        let ls = list(&leader_by_name.get(&V::Str(st.clone())));
        if let Fig::One(f) = found {
            // 같은 나라 지도자가 다른 시대의 같은 이름 인물보다 먼저(고려 충렬왕의 부모 '원종' — 조선 추존 원종 인물이 아니라 고려 원종):
            // 찾은 인물이 그 지도자와 같은 사람이 아니고, 이 나라를 섬긴 적도 이 나라가 있던 때 살았던 적도 없으면 이 나라의 지도자
            let own: Vec<V> = if tv(&cx.polity) { ls.iter().filter(|x| eq(&x.get("p"), &cx.polity)).cloned().collect() } else { Vec::new() };
            let (pa, pb) = if tv(&cx.polity) { (cx.polity.get("start"), cx.polity.get("endY")) } else { (cx.polity.clone(), cx.polity.clone()) }; // ctx.polity && ctx.polity.start
            let fits = list(&f.get("services")).iter().any(|v| eq(&v.get("polity"), &cx.polity)) || overlaps(&f, &pa, &pb);
            if !own.is_empty() && one(&own) && root(&x_key(&own[0])) != root(&fk(&f)) && !fits { return node_of(&x_key(&own[0])); }
            return node_of(&fk(&f));
        }
        if named.has(&V::Str(st.clone())) { return node_of(&Str::from(format!("n:{st}"))); }
        if let Some(x) = pick_leader(&ls, cx, true) { return node_of(&x_key(&x)); }
        if ls.len() > 1 { warn_at(&cx.item, format!("{}의 {what} \"{st}\"은(는) 같은 이름의 지도자가 여럿이라 고를 수 없습니다 — \"나라:지도자@시작 해\"로 적습니다.", cx.label)); }
        else { warn_at(&cx.item, format!("{}의 {what} \"{st}\"을(를) 찾지 못했습니다 — 인물이나 지도자 칸의 이름으로 적습니다(그 이름의 자리를 만들어 둡니다).", cx.label)); }
        let nd = node_of(&Str::from(format!("n:{st}")));
        ob(&nd).set("missing", true);
        nd
    };
    let unknown_node = || -> V { let k = useq.get(); useq.set(k + 1.0); node_of(&Str::from(format!("u:{}", js::num_str(k)))) };
    // 단체의 구성원: 같은 찾기로 사람 자리에 — 글로 적은 이름을 못 찾으면 자리를 만들지 않고 글로만(경고 없음)
    let member_node = |r: &V, cx: &Cx| -> V {
        if tv(r) && js::type_of(r) == "object" {
            return find_cell_ref(r, cx).map_or(V::Null, |h| node_of(&cell_key(&h.p, &format!("{}:{}", h.kind, h.i))));
        }
        let st = tt(r);
        if st.is_empty() { return V::Null; }
        match find_figure(&V::Str(st.clone()), cx) {
            Fig::Ambiguous => return V::Null,
            Fig::One(f) => return node_of(&fk(&f)),
            Fig::None => {}
        }
        if named.has(&V::Str(st.clone())) { return node_of(&Str::from(format!("n:{st}"))); }
        let ls = list(&leader_by_name.get(&V::Str(st)));
        pick_leader(&ls, cx, false).map_or(V::Null, |x| node_of(&x_key(&x)))
    };
    for g in list(&model.get("groups")) {
        let within = list(&g.get("withinList")).into_iter().find(|w| tv(&w.get("polity")));
        let cx = Cx { pack_id: g.get("packId"), track: g.get("track"), start: g.get("start"), polity: or(within.map_or(V::Undef, |w| w.get("polity")), V::Null), lo: V::Undef, hi: V::Undef, item: V::Undef, label: String::new() };
        for row in list(&g.get("peopleList")) {
            let nd = if tv(&row.get("figure")) { node_of(&fk(&row.get("figure"))) } else if tv(&row.get("ambiguous")) { V::Null } else { member_node(&row.get("ref"), &cx) };
            if !tv(&nd) {
                let rf = row.get("ref");
                if tv(&rf) && js::type_of(&rf) == "object" { push_list(&g, "warnings", V::from(format!("구성원 \"{}\"을(를) 연표의 지도자 칸에서 찾지 못했습니다 — \"나라:지도자@시작 해\"로 적습니다.", t(&row.get("name"))))); }
                continue;
            }
            let ro = ob(&row);
            ro.set("person", nd.clone());
            if !tv(&row.get("figure")) && tv(&nd.get("figure")) {
                ro.set("figure", nd.get("figure"));
                ro.set("uid", nd.get("figure").get("uid"));
            }
            if !has(&list(&nd.get("groups")), &g) { push_list(&nd, "groups", g.clone()); }
        }
    }
    // 혈연: 인물의 parents · spouses와 지도자 칸의 parents · spouses — 같은 사람의 것은 한데 모은다
    let mut sources: Vec<(V, V, Cx)> = Vec::new();
    for f in &figures {
        if list(&f.get("parents")).is_empty() && list(&f.get("spouses")).is_empty() { continue; }
        // lo · hi: 생몰(활동) — 같은 이름의 지도자가 여럿일 때 고르는 근거(resolve의 near)
        let lo = f.get("spanMin");
        sources.push((node_of(&fk(f)), f.clone(), Cx { pack_id: f.get("packId"), track: f.get("track"), start: f.get("start"), polity: V::Undef, lo: lo.clone(), hi: nn(f.get("spanMax"), lo), item: f.clone(), label: format!("인물 \"{}\"", t(&f.get("name"))) }));
    }
    for x in &cells {
        let (p, c) = (x.get("p"), x.get("c"));
        if list(&c.get("parents")).is_empty() && list(&c.get("spouses")).is_empty() { continue; }
        let hi = nn(c.get("end"), nn(p.get("endY"), c.get("start")));
        sources.push((node_of(&x_key(x)), c.clone(), Cx { pack_id: p.get("packId"), track: p.get("track"), start: c.get("start"), polity: p.clone(), lo: c.get("start"), hi, item: p.clone(), label: format!("{} 지도자 \"{}\"", t(&p.get("name")), t(&c.get("name"))) }));
    }
    for (node, x, cx) in &sources {
        for q in list(&x.get("parents")) {
            let who = if tv(&q.get("whoUnknown")) { unknown_node() } else { resolve(&q.get("who"), cx, "부모") };
            if !tv(&who) { continue; }
            if eq(&who, node) { warn_at(&cx.item, format!("{}의 부모가 자기 자신입니다 — 뺐습니다.", cx.label)); continue; }
            let q_as = or(q.get("as"), s(""));
            if !tv(&who.get("unknown")) && list(&node.get("parents")).iter().any(|e| eq(&e.get("node"), &who) && eq(&or(e.get("as"), s("")), &q_as)) { continue; }
            let e = o! { "node" => who.clone(), "as" => q_as.clone(), "gen" => or(q.get("gen"), V::Null), "certainty" => or(q.get("certainty"), s("")), "note" => or(q.get("note"), s("")) };
            push_list(node, "parents", V::Obj(e.clone()));
            push_list(&who, "children", V::Obj(o! { "node" => node.clone(), "as" => e.get("as"), "gen" => e.get("gen"), "certainty" => e.get("certainty") }));
        }
        for q in list(&x.get("spouses")) {
            let who = if tv(&q.get("whoUnknown")) { unknown_node() } else { resolve(&q.get("who"), cx, "배우자") };
            if !tv(&who) || eq(&who, node) || (!tv(&who.get("unknown")) && list(&node.get("spouses")).iter().any(|e| eq(&e.get("node"), &who))) { continue; }
            let span = |o: &Obj| {
                o.set("start", nn(q.get("start"), V::Null));
                o.set("startAt", or(q.get("startAt"), V::Null));
                o.set("startUnknown", tv(&q.get("startUnknown")));
                o.set("end", nn(q.get("end"), V::Null));
                o.set("endAt", or(q.get("endAt"), V::Null));
                o.set("endUnknown", tv(&q.get("endUnknown")));
                o.set("note", or(q.get("note"), s("")));
            };
            let a = o! { "node" => who.clone() };
            span(&a);
            push_list(node, "spouses", V::Obj(a));
            let b = o! { "node" => node.clone() };
            span(&b);
            push_list(&who, "spouses", V::Obj(b));
        }
    }
    // 이름: 인물이 있으면 인물, 없으면 첫 칸
    for nd in nodes.values() {
        let c0 = list(&nd.get("cells")).first().cloned();
        let name = if tv(&nd.get("figure")) { nd.get("figure").get("name") }
            else if let Some(c0) = &c0 { leader_label(&c0.get("c")) }
            else if tv(&nd.get("unknown")) { s("미상") }
            else { V::Str(js::to_str(&nd.get("key")).slice16(2.0, f64::INFINITY)) };
        ob(&nd).set("name", name);
        if let V::Arr(cl) = nd.get("cells") { cl.sort_js(|a, c| sub(&a.get("c").get("start"), &c.get("c").get("start"))); }
    }
    // 가문: 사람 자리의 가문(houseId)과 정한 길(houseHow — 'written' · 'founder' · 'inherit' · 'auto')
    let hm = model.get("houseMap"); // JS: model.houseMap || new Map()
    let house_map = if tv(&hm) { crate::lay::model::util::mp(&hm, "model.houseMap") } else { Map::new() };
    let node_list = nodes.values();
    for (k, nd) in node_list.iter().enumerate() {
        let o = ob(nd);
        o.set("seq", k as f64);
        o.set("houseId", V::Null);
        o.set("houseHow", V::Null);
    }
    // 사람 자리를 쥐는 표는 JS처럼 객체로 찾는다(Map · Set — 번호를 매긴 뒤에 생긴 자리도 다른 자리와 겹치지 않게)
    // 시조 · 파조: 가문의 founder 글을 사람 자리로(경고 없는 찾기) — 못 찾으면 글로만
    let founder_of = Map::new();
    for h in house_map.values() {
        let r = if tv(&h.get("founder")) { names::read_person_ref(rc, &h.get("founder")) } else { V::Null };
        let home = list(&h.get("members")).into_iter().find(|m| is(&m.get("role"), "period")).map_or(V::Null, |m| or(m.get("item"), V::Null));
        let nd = if tv(&r) {
            member_node(&r, &Cx { pack_id: h.get("packId"), track: or(h.get("track"), if tv(&home) { home.get("track") } else { s("") }), start: V::Null, polity: home.clone(), lo: V::Undef, hi: V::Undef, item: V::Undef, label: String::new() })
        } else { V::Null };
        ob(&h).define_hidden("founderNode", or(nd.clone(), V::Null));
        if !tv(&nd) || (list(&nd.get("parents")).is_empty() && list(&nd.get("children")).is_empty()) { continue; }
        let cur = founder_of.get(&nd);
        if !tv(&cur) || lt(&cur.get("depth"), &h.get("depth")) { founder_of.set(nd.clone(), h.clone()); }
    }
    const INHERIT: [&str; 5] = ["adoptive-father", "father", "birth-father", "", "ancestor"];
    let heir_parents = |nd: &V| -> Vec<V> {
        let ps = list(&nd.get("parents"));
        let plain = ps.iter().filter(|e| is(&or(e.get("as"), s("")), "")).count();
        let mut out = Vec::new();
        for want in INHERIT { for e in &ps { if is(&or(e.get("as"), s("")), want) && (!want.is_empty() || plain == 1) { out.push(e.get("node")); } } }
        out
    };
    // 부모부터(위상 차례로 한 번 — 고리는 가장 앞 사람에서 끊음)
    let mut order: Vec<V> = Vec::new();
    {
        let total = node_list.len();
        let indeg = Map::new();
        for nd in &node_list { indeg.set(nd.clone(), list(&nd.get("parents")).len() as f64); }
        let done = Set::new();
        let mut queue: Vec<V> = Vec::new();
        for nd in &node_list { if n(&indeg.get(nd)) == 0.0 { queue.push(nd.clone()); } }
        let (mut head, mut scan) = (0usize, 0usize);
        while order.len() < total {
            if head >= queue.len() {
                while done.has(&node_list[scan]) { scan += 1; }
                queue.push(node_list[scan].clone());
            }
            let nd = queue[head].clone();
            head += 1;
            if done.has(&nd) { continue; }
            done.add(nd.clone());
            order.push(nd.clone());
            for c in list(&nd.get("children")) {
                let cn = c.get("node");
                if done.has(&cn) || !indeg.has(&cn) { continue; } // 번호 밖의 자리는 셈하지 않는다(JS: Int32Array에 없는 자리)
                let left = n(&indeg.get(&cn)) - 1.0;
                indeg.set(cn.clone(), left);
                if left == 0.0 { queue.push(cn); }
            }
        }
    }
    for nd in &order {
        let o = ob(nd);
        let cl = list(&nd.get("cells"));
        let hc = cl.iter().find(|x| tv(&x.get("c").get("houseId")) && !tv(&x.get("c").get("houseAuto")));
        let fig = nd.get("figure");
        let written = or(if tv(&fig) { fig.get("houseId") } else { fig.clone() }, hc.map_or(V::Null, |x| x.get("c").get("houseId")));
        let fh = Some(founder_of.get(nd)).filter(tv);
        if let Some(fh) = fh.as_ref().filter(|fh| !tv(&written) || list(&fh.get("path")).iter().any(|x| eq(x, &written))) {
            o.set("houseId", fh.get("id"));
            o.set("houseHow", "founder");
        } else if tv(&written) {
            o.set("houseId", written.clone());
            o.set("houseHow", "written");
        } else if let Some(heir) = heir_parents(nd).into_iter().find(|q| tv(&q.get("houseId"))) {
            o.set("houseId", heir.get("houseId"));
            o.set("houseHow", "inherit");
        } else if let Some(ac) = cl.iter().find(|x| tv(&x.get("c").get("houseId"))) {
            o.set("houseId", ac.get("c").get("houseId"));
            o.set("houseHow", "auto");
        }
        // 뼈대 열쇠(kinKey): 가문이 있으면 그 뿌리 가문 'kin:<id>', 없으면 지도자면 첫 칸의 나라, 아니면 물려받는 부모의 것(없으면 '')
        let h = if tv(&nd.get("houseId")) { house_map.get(&nd.get("houseId")) } else { V::Null };
        if tv(&h) {
            let root_id = { let p0 = if tv(&h.get("path")) { h.get("path").get(&0.0) } else { V::Undef }; or(p0, h.get("id")) };
            o.set("kinKey", format!("kin:{}", t(&root_id)));
        } else if let Some(lc) = cl.iter().find(|x| is(&x.get("kind"), "leader")) {
            o.set("kinKey", format!("kin:polity:{}", t(&lc.get("p").get("uid"))));
        } else {
            let heir = heir_parents(nd).into_iter().find(|q| tv(&q.get("kinKey")));
            o.set("kinKey", heir.map_or(s(""), |h| h.get("kinKey")));
        }
    }
    // 가문의 사람 수 · 계보 전용 인물 수 — h.kinCount = h.lineageCount = 0(오른쪽부터 쓴다)
    for h in house_map.values() { let o = ob(&h); o.set("lineageCount", 0.0); o.set("kinCount", 0.0); }
    for nd in &node_list {
        let h = if tv(&nd.get("houseId")) { house_map.get(&nd.get("houseId")) } else { V::Null };
        if !tv(&h) { continue; }
        let o = ob(&h);
        o.set("kinCount", n(&h.get("kinCount")) + 1.0);
        let fig = nd.get("figure");
        if tv(&fig) && matches!(fig.get("lineageOnly"), V::Bool(true)) { o.set("lineageCount", n(&h.get("lineageCount")) + 1.0); }
    }
    // 가문 머리 값의 짐작: 구분(trackAuto) · 민족(peopleAuto) · 본관 · 성의 물려받음(seatFrom · surnameFrom)
    {
        let persons_of = Map::new();
        for nd in &node_list {
            if !tv(&nd.get("houseId")) { continue; }
            match persons_of.get(&nd.get("houseId")) { V::Arr(l) => l.push(nd.clone()), _ => persons_of.set(nd.get("houseId"), Arr::new(vec![nd.clone()])) }
        }
        /// 표 하나(값 · 수 · 가장 이른 때).
        #[derive(Clone)]
        struct Tal { v: V, n: f64, t: V }
        let tally = |rows: Vec<(V, V)>| -> Option<(V, f64)> {
            let mut m: Vec<Tal> = Vec::new();
            for (v, tm) in rows {
                if !tv(&v) { continue; }
                match m.iter_mut().find(|c| eq(&c.v, &v)) {
                    None => m.push(Tal { v, n: 1.0, t: tm }),
                    Some(c) => { c.n += 1.0; if lt(&tm, &c.t) { c.t = tm; } }
                }
            }
            js::sort_by(&mut m, |a, b| { let d = b.n - a.n; if d != 0.0 { d } else { sub(&a.t, &b.t) } });
            m.first().map(|a| (a.v.clone(), (m.len() - 1) as f64))
        };
        let mut by_depth = house_map.values();
        js::sort(&mut by_depth, |a, c| { let d = sub(&a.get("depth"), &c.get("depth")); if d != 0.0 && !d.is_nan() { d } else { sub(&a.get("seq"), &c.get("seq")) } });
        for h in &by_depth {
            let mems = list(&h.get("members"));
            let nations: Vec<V> = mems.iter().filter(|m| is(&m.get("role"), "period")).map(|m| m.get("item")).collect();
            let ruled: Vec<V> = mems.iter().filter(|m| is(&m.get("role"), "leader")).map(|m| m.get("item")).collect();
            let parent = if tv(&h.get("parentId")) { house_map.get(&h.get("parentId")) } else { V::Null };
            let mut tr: Option<(V, f64)>;
            let mut from: &str;
            let mut pe: Option<(V, f64)> = None;
            let mut pe_from: &str = "";
            if !nations.is_empty() {
                tr = tally(nations.iter().map(|p| (p.get("track"), p.get("start"))).collect());
                pe = tally(nations.iter().map(|p| (p.get("people"), p.get("start"))).collect());
                from = "period";
                pe_from = "period";
            } else if !ruled.is_empty() {
                tr = tally(ruled.iter().map(|p| (p.get("track"), p.get("start"))).collect());
                pe = tally(ruled.iter().map(|p| (p.get("people"), p.get("start"))).collect());
                from = "leader";
                pe_from = "leader";
            } else {
                let ps = list(&persons_of.get(&h.get("id")));
                tr = tally(ps.iter().map(|nd| {
                    let fig = nd.get("figure");
                    let c0 = list(&nd.get("cells")).first().cloned();
                    (if tv(&fig) { fig.get("track") } else if let Some(c0) = c0 { c0.get("p").get("track") } else { s("") }, nd.get("seq"))
                }).collect());
                from = if tr.is_some() { "person" } else { "" };
            }
            if tr.is_none() && tv(&parent) {
                let v = or(parent.get("track"), parent.get("trackAuto"));
                tr = if tv(&v) { Some((v, 0.0)) } else { None };
                from = if tr.is_some() { "parent" } else { "" };
            }
            if pe.is_none() && tv(&parent) && (tv(&parent.get("people")) || tv(&parent.get("peopleAuto"))) {
                pe = Some((or(parent.get("people"), parent.get("peopleAuto")), 0.0));
                pe_from = "parent";
            }
            let o = ob(h);
            let track_auto = if !tv(&h.get("track")) && tr.is_some() { tr.clone().expect("짐작").0 } else { s("") };
            o.set("trackAuto", track_auto.clone());
            o.set("trackFrom", if tv(&track_auto) { s(from) } else { s("") });
            o.set("trackMore", if tv(&track_auto) { tr.as_ref().expect("짐작").1 } else { 0.0 });
            let people_auto = if !tv(&h.get("people")) && pe.is_some() { pe.clone().expect("짐작").0 } else { s("") };
            o.set("peopleAuto", people_auto.clone());
            o.set("peopleFrom", if tv(&people_auto) { s(pe_from) } else { s("") });
            o.set("seatFrom", "");
            o.set("surnameFrom", "");
            let path = if tv(&h.get("path")) { list(&h.get("path")) } else { vec![h.get("id")] };
            let upto = path.len().saturating_sub(1);
            for id in path[..upto].iter().rev() {
                let a = house_map.get(id);
                if !tv(&a) { continue; }
                if !tv(&h.get("seat")) && !tv(&h.get("seatFrom")) && tv(&a.get("seat")) { o.set("seatFrom", a.get("id")); }
                if !tv(&h.get("surname")) && !tv(&h.get("surnameFrom")) && tv(&a.get("surname")) { o.set("surnameFrom", a.get("id")); }
            }
        }
    }
    // 부모 고리(누가 자기 조상) — 한 번씩 알림(손수 쌓는 더미)
    {
        let state = Map::new(); // 사람 자리 → 1(도는 중) · 2(끝남)
        for first in nodes.values() {
            if state.has(&first) { continue; }
            state.set(first.clone(), 1.0);
            let mut stack: Vec<(V, usize)> = vec![(first.clone(), 0)];
            while let Some(top) = stack.last_mut() {
                let nd = top.0.clone();
                let ps = list(&nd.get("parents"));
                if top.1 >= ps.len() { state.set(nd.clone(), 2.0); stack.pop(); continue; }
                let e = ps[top.1].clone();
                top.1 += 1;
                let en = e.get("node");
                let st = state.get(&en);
                if is_num(&st, 1.0) {
                    let fig = nd.get("figure");
                    let src = if tv(&fig) { fig } else { list(&nd.get("cells")).first().map_or(V::Undef, |c| c.get("p")) };
                    if tv(&src) { warn_at(&src, format!("{}의 부모 · 조상을 따라가면 다시 {}(으)로 돌아옵니다 — 혈연이 고리를 이룹니다.", t(&nd.get("name")), t(&nd.get("name")))); }
                } else if st.is_undef() {
                    state.set(en.clone(), 1.0);
                    stack.push((en, 0));
                }
            }
        }
    }
    let index = Map::new();
    for k in up.keys() {
        let V::Str(k) = k else { continue };
        let nd = nodes.get(&V::Str(root(&k)));
        if tv(&nd) { index.set(V::Str(k), nd); }
    }
    for nd in nodes.values() { index.set(nd.get("key"), nd); }
    // ④ 자리 이음: 적은 from을 풀고(accessionFrom), 관계(kin)를 혈연과 견준다. from을 비우면 바로 앞 칸의 사람
    let accession_from = Map::new();
    const BIO: [&str; 7] = ["", "father", "mother", "birth-father", "birth-mother", "adoptive-father", "adoptive-mother"];
    let known_parents = |nd: &V| -> Vec<V> {
        if !tv(nd) { return Vec::new(); }
        list(&nd.get("parents")).into_iter().filter(|e| { let en = e.get("node"); !tv(&en.get("unknown")) && !tv(&en.get("missing")) && BIO.iter().any(|b| is(&or(e.get("as"), s("")), b)) }).collect()
    };
    let kin_check = |kin: &V, cur: &V, pred: &V| -> &'static str {
        let cp = known_parents(cur);
        let pp = known_parents(pred);
        let k = match kin { V::Str(x) => x.as_str().into_owned(), _ => String::new() };
        match k.as_str() {
            "son" | "daughter" => if !cp.is_empty() && !cp.iter().any(|e| eq(&e.get("node"), pred)) { "부모에 앞 지도자가 없습니다" } else { "" },
            "adopted" => if !cp.is_empty() && !cp.iter().any(|e| eq(&e.get("node"), pred) && js::to_str(&e.get("as")).as_str().starts_with("adoptive-")) { "양부 · 양모에 앞 지도자가 없습니다" } else { "" },
            "grandson" | "granddaughter" | "maternal-grandson" => {
                if !cp.is_empty() && cp.iter().all(|e| !known_parents(&e.get("node")).is_empty()) && !cp.iter().any(|e| known_parents(&e.get("node")).iter().any(|g| eq(&g.get("node"), pred))) { "조부모에 앞 지도자가 없습니다" } else { "" }
            }
            "younger-brother" | "elder-brother" | "sister" => if !cp.is_empty() && !pp.is_empty() && !cp.iter().any(|e| pp.iter().any(|g| eq(&g.get("node"), &e.get("node")))) { "앞 지도자와 같은 부모가 없습니다" } else { "" },
            "nephew" => {
                if !cp.is_empty() && !pp.is_empty() && cp.iter().all(|e| !known_parents(&e.get("node")).is_empty())
                    && !cp.iter().any(|e| known_parents(&e.get("node")).iter().any(|g| pp.iter().any(|h| eq(&h.get("node"), &g.get("node"))))) { "부모가 앞 지도자의 형제가 아닙니다" } else { "" }
            }
            "father" | "mother" => if !pp.is_empty() && !pp.iter().any(|e| eq(&e.get("node"), cur)) { "앞 지도자의 부모에 이 사람이 없습니다" } else { "" },
            "spouse" => { let sp = list(&pred.get("spouses")); if !sp.is_empty() && !sp.iter().any(|e| eq(&e.get("node"), cur)) { "앞 지도자의 배우자에 이 사람이 없습니다" } else { "" } }
            "self" => if !eq(cur, pred) { "앞 지도자와 다른 사람입니다" } else { "" },
            "unrelated" => if cp.iter().any(|e| eq(&e.get("node"), pred)) || pp.iter().any(|e| eq(&e.get("node"), cur)) { "혈연에는 부모 · 자식으로 적혀 있습니다" } else { "" },
            _ => "",
        }
    };
    for p in &periods {
        if !is(&item_kind_of(p), "period") || !list(&p.get("leaders")).iter().any(|c| tv(&c.get("accession"))) { continue; }
        for (i, c) in list(&p.get("leaders")).iter().enumerate() {
            let a = c.get("accession");
            if !tv(&a) { continue; }
            let label = format!("{} 지도자 \"{}\"", t(&p.get("name")), t(&c.get("name")));
            let cur = or(index.get(&V::Str(cell_key(p, &format!("leader:{i}")))), V::Null);
            let mut pred = V::Null;
            if tv(&a.get("from")) {
                let hi = nn(c.get("end"), nn(p.get("endY"), c.get("start")));
                pred = resolve(&a.get("from"), &Cx { pack_id: p.get("packId"), track: p.get("track"), start: c.get("start"), polity: p.clone(), lo: c.get("start"), hi, item: p.clone(), label: label.clone() }, "앞 지도자");
                if tv(&pred) { accession_from.set(V::Str(cell_key(p, &format!("leader:{i}"))), pred.clone()); }
            } else if !tv(&a.get("fromUnknown")) && i > 0 {
                pred = or(index.get(&V::Str(cell_key(p, &format!("leader:{}", i - 1)))), V::Null);
            }
            let kin = a.get("kin");
            if tv(&kin) && tv(&pred) && tv(&cur) && !tv(&pred.get("unknown")) {
                let why = kin_check(&kin, &cur, &pred);
                if !why.is_empty() { warn_at(p, format!("{label}: 자리 이음의 관계는 '{}'인데 혈연과 어긋납니다 — {why}.", kin_name(&kin))); }
            }
            if tv(&kin) && !is(&kin, "self") && tv(&cur) && eq(&pred, &cur) {
                warn_at(p, format!("{label}: 앞 지도자가 같은 사람인데 관계가 '{}'입니다 — 다시 올랐으면 관계를 '본인'으로 적습니다.", kin_name(&kin)));
            }
        }
    }
    mo.set("persons", arr(nodes.values()));
    mo.set("personIndex", index);
    mo.set("accessionFrom", accession_from);
    mo.set("peopleWarnings", warnings);
}

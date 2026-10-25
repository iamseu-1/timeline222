//! 모델 잇기 — `HT.buildModel`의 끝에서 부르는 `link*`(가문 · 조약 서명자 · 지명 · 성씨 · 사람 · 계보 · 판 · 지도 · 글꼴 · 간지 · 배열 기준 · 문서 그림)를 줄 그대로 옮긴다(한 벌 P3 과제 6).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 5381 ~ 5395줄 `linkDocImages` → [`link_doc_images`]
//! - 5937 ~ 6041줄 `linkHouses` → [`link_houses`]
//! - 6050 ~ 6073줄 `polityFinder` → [`polity_finder`] · 6076 ~ 6100줄 `mapScenesOf` → [`map_scenes_of`]
//! - 6137 ~ 6216줄 `linkFormat3` → [`link_format3`](6831 ~ 6834줄의 `HT.placeOf`는 [`place_of`])
//! - 6222 ~ 6241줄 `linkTreatySigners` → [`link_treaty_signers`]
//! - 6254 ~ 6827줄 `linkPeople` → `link/people.rs`의 [`link_people`]
//! - 7758 ~ 7761줄 `HT.rowOrderOf` · 7764 ~ 7841줄 `linkOrder` → [`link_order`](남북 값 `p.north`는 열거되지 않는 속성 — `Obj::define_hidden`)
use crate::lay::js::{self, Arr, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, assign_obj, auto_color, copy, eq, is, item_kind_of, list, n, nn, ob, or, pastel, s, scope_ref_text, sub, t, tv, or_cmp, font_format};
use crate::lay::read::{self, cells as rcells, dates, misc, Ctx as RCtx};

mod people;
pub use people::link_people;

/// `(x.k || (x.k = [])).push(v)`.
pub(crate) fn push_list(x: &V, k: &str, v: V) {
    let o = ob(x);
    let cur = o.get(k);
    let a = match &cur { V::Arr(a) => a.clone(), _ => { let a = Arr::default(); o.set(k, a.clone()); a } };
    a.push(v);
}

/// `linkDocImages(model, packs)` — 모델의 그림 사전(model.imageMap — 팩 id → { byId, byName, list }).
pub fn link_doc_images(model: &V, packs: &[V]) {
    let image_map = Map::new();
    ob(model).set("imageMap", image_map.clone());
    for pack in packs {
        let imgs = if tv(pack) { pack.get("images") } else { V::Undef };
        let V::Arr(imgs) = imgs else { continue };
        if imgs.is_empty() { continue; }
        let by_id = Map::new();
        let by_name = Map::new();
        for g in imgs.to_vec() {
            let o = copy(&g);
            o.set("packId", pack.get("id"));
            o.set("packName", pack.get("name"));
            o.set("uid", format!("img:{}/{}", t(&pack.get("id")), t(&g.get("id"))));
            by_id.set(g.get("id"), o.clone());
            let lower = V::from(js::to_str(&g.get("name")).as_str().to_lowercase());
            for k in [g.get("name"), lower] { if !by_name.has(&k) { by_name.set(k, o.clone()); } }
        }
        image_map.set(pack.get("id"), o! { "byId" => by_id.clone(), "byName" => by_name, "list" => arr(by_id.values()) });
    }
}

/// `linkHouses(model, packs)` — 가문 사전 · 국성 · 지도자/내각(/인물)의 가문 → model.houses · houseMap(원문 house는 그대로, 풀어낸 것은 houseId · houseName · houseColor).
pub fn link_houses(_rc: &RCtx, model: &V, packs: &[V]) {
    let houses = Map::new();
    let by_name = Map::new();
    let seq = std::cell::Cell::new(0.0);
    let add = |h: &V, auto: bool| -> V {
        let id = h.get("id");
        if houses.has(&id) { return houses.get(&id); }
        let sq = seq.get();
        seq.set(sq + 1.0);
        let names = h.get("names");
        let tags = h.get("tags");
        let o = o! {
            "id" => id.clone(), "uid" => format!("house:{}", t(&id)), "itemKind" => "house", "name" => or(h.get("name"), id.clone()),
            "surname" => or(h.get("surname"), s("")), "seat" => or(h.get("seat"), s("")), "parent" => or(h.get("parent"), s("")), "founder" => or(h.get("founder"), s("")),
            "color" => pastel(&or(h.get("color"), auto_color(&V::from(format!("house:{}", t(&id)))))), "description" => or(h.get("description"), s("")), "wiki" => or(h.get("wiki"), s("")),
            "names" => if matches!(names, V::Arr(_)) { names } else { arr(Vec::new()) },
            "track" => or(h.get("track"), s("")), "people" => or(h.get("people"), s("")), "tags" => if matches!(tags, V::Arr(_)) { tags } else { arr(Vec::new()) },
            "packId" => or(h.get("packId"), s("")), "packName" => or(h.get("packName"), s("")), "auto" => auto, "seq" => sq, "members" => arr(Vec::new()),
        };
        houses.set(id, o.clone());
        if !by_name.has(&o.get("name")) { by_name.set(o.get("name"), o.clone()); }
        V::Obj(o)
    };
    for pack in packs {
        for h in list(&pack.get("houses")) {
            let x = o! { "packId" => pack.get("id"), "packName" => pack.get("name") };
            assign_obj(&x, &copy(&h));
            add(&V::Obj(x), false);
        }
    }
    let find = |r: &V| -> V {
        let r = js::to_str(&nn(r.clone(), s(""))).trim();
        if r.is_empty() { return V::Null; }
        let rv = V::Str(r);
        let g = houses.get(&rv);
        if tv(&g) { return g; }
        let g = by_name.get(&rv);
        if tv(&g) { g } else { V::Null }
    };
    let ensure = |r: &V| -> V {
        let r = js::to_str(&nn(r.clone(), s(""))).trim();
        if r.is_empty() { return V::Null; }
        let f = find(&V::Str(r.clone()));
        if tv(&f) { f } else { add(&V::Obj(o! { "id" => format!("h-{}", misc::hash(&r)), "name" => r }), true) }
    };
    let put = |x: &V, h: &V| { let o = ob(x); o.set("houseId", h.get("id")); o.set("houseName", h.get("name")); o.set("houseColor", h.get("color")); };
    let periods = list(&model.get("periods"));
    // ① 왕조: 사전에 있으면 그 가문, 없으면 본가 왕조 이름인지 보고(그렇다면 가문으로 만들지 않음) 아니면 새 가문
    let dyns: Vec<V> = periods.iter().filter(|p| is(&p.get("polityKind"), "dynasty")).cloned().collect();
    for d in &dyns {
        if !tv(&d.get("house")) { continue; }
        let dh = d.get("house");
        let mut h = find(&dh);
        if !tv(&h) { h = if dyns.iter().any(|q| !eq(q, d) && (eq(&q.get("name"), &dh) || eq(&q.get("id"), &dh) || eq(&q.get("uid"), &dh))) { V::Null } else { ensure(&dh) }; }
        if tv(&h) { put(d, &h); }
    }
    // ② 국성
    for p in &periods { if is(&item_kind_of(p), "period") && tv(&p.get("house")) { put(p, &ensure(&p.get("house"))); } }
    // ③ 지도자 · 내각 — 칸 목록은 복사해서 단다
    for p in &periods {
        let leaders = p.get("leaders");
        if tv(&leaders) && tv(&leaders.get("length")) {
            let mapped: Vec<V> = list(&leaders).into_iter().map(|c| {
                let mut h = if tv(&c.get("house")) { ensure(&c.get("house")) } else { V::Null };
                let auto = !tv(&h);
                if !tv(&h) {
                    let dn = or(c.get("dynasty"), c.get("dynastyAuto"));
                    let d = if tv(&dn) { list(&p.get("dynasties")).into_iter().find(|x| eq(&x.get("dynasty").get("name"), &dn)) } else { None };
                    let from_d = d.map(|d| d.get("dynasty").get("houseId")).filter(tv).map(|id| houses.get(&id)).filter(tv);
                    h = from_d.or_else(|| if tv(&p.get("houseId")) { Some(houses.get(&p.get("houseId"))).filter(tv) } else { None }).unwrap_or(V::Null);
                }
                if !tv(&h) { return c; }
                let o = copy(&c);
                if auto { o.set("houseAuto", true); }
                let ov = V::Obj(o);
                put(&ov, &h);
                ov
            }).collect();
            ob(p).set("leaders", arr(mapped));
        }
        let cabinets = p.get("cabinets");
        if tv(&cabinets) && tv(&cabinets.get("length")) && list(&cabinets).iter().any(|c| tv(&c.get("house"))) {
            let mapped: Vec<V> = list(&cabinets).into_iter().map(|c| {
                if !tv(&c.get("house")) { return c; }
                let ov = V::Obj(copy(&c));
                put(&ov, &ensure(&c.get("house")));
                ov
            }).collect();
            ob(p).set("cabinets", arr(mapped));
        }
    }
    // ④ 구성원
    let member = |id: &V, m: Obj| push_list(&houses.get(id), "members", V::Obj(m));
    for p in &periods {
        let kind = item_kind_of(p);
        if tv(&p.get("houseId")) && (is(&kind, "period") || is(&kind, "dynasty")) { member(&p.get("houseId"), o! { "role" => kind.clone(), "item" => p.clone(), "start" => p.get("start"), "end" => p.get("endY") }); }
        for (i, c) in list(&p.get("leaders")).iter().enumerate() {
            if tv(&c.get("houseId")) {
                member(&c.get("houseId"), o! { "role" => "leader", "item" => p.clone(), "cell" => c.clone(), "ref" => format!("leader:{i}"), "start" => c.get("start"), "end" => nn(c.get("end"), p.get("endY")), "auto" => tv(&c.get("houseAuto")) });
            }
        }
        for (i, c) in list(&p.get("cabinets")).iter().enumerate() {
            if tv(&c.get("houseId")) {
                member(&c.get("houseId"), o! { "role" => "cabinet", "item" => p.clone(), "cell" => c.clone(), "ref" => format!("cabinet:{i}"), "start" => c.get("start"), "end" => nn(c.get("end"), p.get("endY")) });
            }
        }
    }
    for f in list(&model.get("figures")) {
        let h = if tv(&f.get("houseId")) { houses.get(&f.get("houseId")) } else if tv(&f.get("house")) { ensure(&f.get("house")) } else { V::Null };
        if !tv(&h) { continue; }
        put(&f, &h);
        member(&h.get("id"), o! { "role" => "figure", "item" => f.clone(), "start" => f.get("start"), "end" => nn(nn(f.get("endY"), f.get("end")), f.get("start")) });
    }
    for f in list(&model.get("lineageFigures")) {
        let h = if tv(&f.get("houseId")) { houses.get(&f.get("houseId")) } else if tv(&f.get("house")) { ensure(&f.get("house")) } else { V::Null };
        if tv(&h) { put(&f, &h); }
    }
    let role_order = |r: &V| -> f64 { match r { V::Str(x) => match x.as_str().as_ref() { "period" => 0.0, "dynasty" => 1.0, "leader" => 2.0, "cabinet" => 3.0, "figure" => 4.0, _ => f64::NAN }, _ => f64::NAN } };
    for h in houses.values() {
        if let V::Arr(m) = h.get("members") { m.sort_js(|a, c| or_cmp(sub(&a.get("start"), &c.get("start")), || role_order(&a.get("role")) - role_order(&c.get("role")))); }
    }
    // ⑤ 본가 → 분가(적은 본가가 사전에 없으면 그 이름으로 만든다 · 돌고 도는 것은 끊음)
    for h in houses.values() {
        let parent = if tv(&h.get("parent")) { ensure(&h.get("parent")) } else { V::Null };
        ob(&h).set("parentId", if tv(&parent) && !eq(&parent, &h) { parent.get("id") } else { V::Null });
    }
    for h in houses.values() {
        let mut path: Vec<V> = Vec::new();
        let seen = Set::new();
        let mut cur = h.clone();
        while tv(&cur) && !seen.has(&cur.get("id")) {
            seen.add(cur.get("id"));
            path.insert(0, cur.get("id"));
            cur = if tv(&cur.get("parentId")) { houses.get(&cur.get("parentId")) } else { V::Null };
        }
        let o = ob(&h);
        o.set("path", arr(path.clone()));
        o.set("depth", path.len() as f64 - 1.0);
    }
    // 분가 목록: 본가 id → 분가들(가문 차례 그대로)
    let kids = Map::new();
    for x in houses.values() {
        if tv(&x.get("parentId")) && !eq(&x.get("parentId"), &x.get("id")) {
            if !kids.has(&x.get("parentId")) { kids.set(x.get("parentId"), Arr::default()); }
            if let V::Arr(l) = kids.get(&x.get("parentId")) { l.push(x.get("id")); }
        }
    }
    for h in houses.values() { let k = kids.get(&h.get("id")); ob(&h).set("children", if tv(&k) { k } else { arr(Vec::new()) }); }
    // ⑥ 문서: houses[].wiki → "house:id"(내 글 · DLC의 documents가 먼저)
    let docs = super::model::util::mp(&model.get("docs"), "model.docs");
    for h in houses.values() { if tv(&h.get("wiki")) && !docs.has(&h.get("uid")) { docs.set(h.get("uid"), o! { "text" => h.get("wiki"), "packId" => h.get("packId"), "packName" => h.get("packName") }); } }
    for h in houses.values() {
        let d = docs.get(&h.get("uid"));
        if !tv(&d) { continue; }
        ob(&h).set("wiki", d.get("text"));
        if tv(&d.get("user")) { ob(&h).set("wikiUser", true); }
    }
    ob(model).set("houses", arr(houses.values()));
    ob(model).set("houseMap", houses);
}

/// `polityFinder(model)`의 답 `{ item, tracks }`.
pub(crate) struct Found { pub item: V, pub tracks: Vec<V> }
/// `polityFinder(model)` — 나라 참조({ track?, polity }) → 모델의 나라. 트랙을 적으면 그 트랙에서, 아니면 uid · 같은 DLC의 id · 이름 순으로
/// (이름은 같은 DLC의 나라 먼저, year를 주면 그해에 있던 나라 먼저). tracks = 같은 이름이 걸친 트랙들.
pub(crate) fn polity_finder(model: &V) -> impl Fn(&rcells::ScopeRef, &V, &V) -> Found {
    let items: Vec<V> = list(&model.get("periods")).into_iter().filter(|p| is(&item_kind_of(p), "period")).collect();
    let by_name = Map::new();
    for p in &items {
        if !by_name.has(&p.get("name")) { by_name.set(p.get("name"), Arr::default()); }
        if let V::Arr(l) = by_name.get(&p.get("name")) { l.push(p.clone()); }
    }
    let pick = |cands: Vec<V>, pack_id: &V, year: &V| -> Found {
        if cands.is_empty() { return Found { item: V::Null, tracks: Vec::new() }; }
        let own: Vec<V> = cands.iter().filter(|q| eq(&q.get("packId"), pack_id)).cloned().collect();
        let mut pool = if !own.is_empty() { own } else { cands };
        if !year.is_nullish() {
            let y = n(year);
            let live: Vec<V> = pool.iter().filter(|q| y >= n(&q.get("start")) - 1e-9 && y < n(&nn(q.get("endY"), q.get("start"))) + 1.0).cloned().collect();
            if !live.is_empty() { pool = live; }
        }
        let tracks = Set::new();
        for q in &pool { tracks.add(q.get("track")); }
        Found { item: pool[0].clone(), tracks: tracks.values() }
    };
    move |r: &rcells::ScopeRef, pack_id: &V, year: &V| -> Found {
        let pol = V::Str(r.polity.clone());
        if let Some(tr) = r.track.as_ref().filter(|x| !x.is_empty()) {
            let tv_ = V::Str(tr.clone());
            return pick(items.iter().filter(|q| eq(&q.get("track"), &tv_) && (eq(&q.get("name"), &pol) || eq(&q.get("id"), &pol) || eq(&q.get("uid"), &pol))).cloned().collect(), pack_id, year);
        }
        let exact = items.iter().find(|q| eq(&q.get("uid"), &pol)).or_else(|| items.iter().find(|q| eq(&q.get("packId"), pack_id) && eq(&q.get("id"), &pol)));
        if let Some(x) = exact { return Found { item: x.clone(), tracks: vec![x.get("track")] }; }
        pick(list(&by_name.get(&pol)), pack_id, year)
    }
}

/// `mapScenesOf(map)` — 장면(열쇠 해)마다 그때까지 이어받은 주인(owners · items)과 그때의 그림. 해 순.
pub(crate) fn map_scenes_of(map: &V) -> Vec<V> {
    let mut scenes = Vec::new();
    let mut owners = Obj::new();
    let mut items = Obj::new();
    let mut image = or(map.get("image"), V::Null);
    let mut frames: Vec<V> = read::dates::arr(&map.get("frames")).into_iter().filter(|f| tv(f) && js::type_of(f) == "object" && matches!(f.get("year"), V::Num(y) if y.is_finite())).collect();
    js::sort(&mut frames, |a, c| sub(&a.get("year"), &c.get("year")));
    for (index, f) in frames.iter().enumerate() {
        owners = copy(&V::Obj(owners));
        items = copy(&V::Obj(items));
        let fo = or(f.get("owners"), V::Obj(Obj::new()));
        if let V::Obj(fo) = fo {
            for (rid, r) in fo.entries() {
                if r.is_nullish() { owners.delete(&rid); items.delete(&rid); }
                else {
                    owners.set(&rid, r);
                    if tv(&f.get("ownerItems")) { items.set(&rid, or(f.get("ownerItems").get(&rid), V::Null)); }
                }
            }
        }
        if tv(&f.get("image")) { image = f.get("image"); }
        scenes.push(V::Obj(o! {
            "index" => index as f64, "year" => f.get("year"), "yearAt" => or(f.get("yearAt"), V::Null), "frame" => f.clone(), "owners" => owners.clone(),
            "items" => items.clone(), "image" => image.clone(), "note" => or(f.get("note"), s("")),
        }));
    }
    scenes
}

/// `HT.placeOf(model, ref)` — 지명 참조(이름이나 id) → 모델의 지명(없으면 null).
pub(crate) fn place_of(model: &V, r: &V) -> V {
    let text = js::to_str(&nn(r.clone(), s(""))).trim();
    if text.is_empty() || !tv(&model.get("placeMap")) { return V::Null; }
    let rv = V::Str(text);
    let g = model.get("placeMap").as_map().map_or(V::Undef, |m| m.get(&rv));
    if tv(&g) { return g; }
    let g = model.get("placeByName").as_map().map_or(V::Undef, |m| m.get(&rv));
    if tv(&g) { g } else { V::Null }
}

/// `linkFormat3(model, packs)` — 형식 3: 모아 보기 판 · 지도 · 글꼴 → model.views · viewMap · maps · mapMap · fonts · fontMap(구성 나라 · 장면의 주인을 나라로).
/// 실패하는 길은 없다(16b 넘겨받은 틀 손질 — 예전의 `Result`는 늘 `Ok`였다: 날짜 글 갈래는 과제 Y가 옮겨 닫힘).
pub fn link_format3(rc: &RCtx, model: &V, packs: &[V]) {
    let mo = ob(model);
    let (views, view_map, maps, map_map, fonts, font_map) = (Arr::default(), Map::new(), Arr::default(), Map::new(), Arr::default(), Map::new());
    mo.set("views", views.clone());
    mo.set("viewMap", view_map.clone());
    mo.set("maps", maps.clone());
    mo.set("mapMap", map_map.clone());
    mo.set("fonts", fonts.clone());
    mo.set("fontMap", font_map.clone());
    if !packs.iter().any(|p| tv(p) && (tv(&p.get("views")) || tv(&p.get("maps")) || tv(&p.get("fonts")))) { return; }
    let find = polity_finder(model);
    let track_map = model.get("trackMap");
    let track_name = |id: &V| -> V { let g = super::model::util::mp(&track_map, "model.trackMap").get(id); or(if tv(&g) { g.get("name") } else { V::Undef }, id.clone()) };
    let resolve = |r: &rcells::ScopeRef, pack_id: &V, year: &V, warnings: &Arr, what: &str| -> V {
        let f = find(r, pack_id, year);
        if !tv(&f.item) { warnings.push(format!("{what} \"{}\"을(를) 연표에서 찾지 못했습니다.", scope_ref_text(r))); }
        else if f.tracks.len() > 1 {
            let names: Vec<String> = f.tracks.iter().map(|x| t(&track_name(x))).collect();
            warnings.push(format!("{what} \"{}\" — 이름이 같은 나라가 여러 트랙({})에 있어 {}의 것을 골랐습니다. \"트랙:이름\"으로 적으면 하나로 정해집니다.",
                r.polity, names.join(" · "), t(&track_name(&f.item.get("track")))));
        }
        f.item
    };
    let docs_v = model.get("docs");
    let put_doc = |o: &Obj| {
        let docs = super::model::util::mp(&docs_v, "model.docs");
        if tv(&o.get("wiki")) && !docs.has(&o.get("uid")) { docs.set(o.get("uid"), o! { "text" => o.get("wiki"), "packId" => o.get("packId"), "packName" => o.get("packName") }); }
        let d = docs.get(&o.get("uid"));
        if tv(&d) {
            o.set("wiki", d.get("text"));
            if tv(&d.get("user")) { o.set("wikiUser", true); }
        }
    };
    let once = |by_id: &Map, raw: &V, pack: &V, word: &str| -> bool {
        let prev = by_id.get(&raw.get("id"));
        if tv(&prev) {
            if let V::Arr(w) = prev.get("warnings") { w.push(format!("DLC «{}»에도 같은 id({})의 {word}이(가) 있어 그쪽은 쓰지 않았습니다.", t(&pack.get("name")), t(&raw.get("id")))); }
        }
        !tv(&prev)
    };
    for pack in packs {
        for raw in list(&pack.get("views")) {
            if !once(&view_map, &raw, pack, "모아 보기 판") { continue; }
            let warnings = Arr::default();
            let mut members: Vec<V> = Vec::new();
            for r in rcells::read_scope_refs(&raw.get("members")) {
                let m = resolve(&r, &pack.get("id"), &V::Null, &warnings, "구성 나라");
                if tv(&m) && !members.iter().any(|x| eq(x, &m)) { members.push(m); }
            }
            let o = copy(&raw);
            assign_obj(&o, &o! { "kind" => "view", "itemKind" => "view", "uid" => format!("view:{}", t(&raw.get("id"))), "packId" => pack.get("id"), "packName" => pack.get("name"),
                "memberRefs" => raw.get("members"), "members" => arr(members.clone()), "warnings" => warnings });
            let tr = Set::new();
            for p in &members { tr.add(p.get("track")); }
            o.set("tracks", arr(tr.values()));
            if !raw.get("start").is_nullish() { o.set("endY", if raw.bool("ongoing") { V::Num(js::max(&[rc.now_t, n(&raw.get("start"))])) } else { nn(raw.get("end"), raw.get("start")) }); }
            if !misc::is_color(&raw.get("color")) { o.set("colorAuto", true); }
            o.set("color", pastel(&if misc::is_color(&raw.get("color")) { raw.get("color") } else { auto_color(&o.get("uid")) }));
            put_doc(&o);
            view_map.set(raw.get("id"), o.clone());
            views.push(o);
        }
        for raw in list(&pack.get("maps")) {
            if !once(&map_map, &raw, pack, "지도") { continue; }
            let warnings = Arr::default();
            let mut frames = Vec::new();
            for f in read::dates::arr(&raw.get("frames")) {
                if !tv(&f.get("owners")) { frames.push(V::Obj(copy(&f))); continue; }
                let owner_items = Obj::new();
                if let V::Obj(ow) = f.get("owners") {
                    for (rid, r) in ow.entries() {
                        let sr = if r.is_nullish() { None } else { rcells::read_scope_ref(&r) };
                        let year_text = if tv(&f.get("yearAt")) { t(&f.get("yearAt")) } else { js::num_str(dates::year_of_t(n(&f.get("year")))) };
                        let what = format!("{year_text}년 장면의 구역 \"{rid}\" 주인");
                        let item = match &sr { Some(r) => resolve(r, &pack.get("id"), &f.get("year"), &warnings, &what), None => V::Null };
                        if tv(&item) {
                            let y = n(&f.get("year"));
                            if !(y >= n(&item.get("start")) - 1e-9 && y < n(&nn(item.get("endY"), item.get("start"))) + 1.0) {
                                warnings.push(format!("{what} \"{}\"은(는) 그해에 연표에 없던 나라입니다 ({}).", t(&item.get("name")), crate::lay::web::when::format_range(rc, &item)));
                            }
                        }
                        owner_items.set(&rid, or(item, V::Null));
                    }
                }
                let o = copy(&f);
                o.set("ownerItems", owner_items);
                frames.push(V::Obj(o));
            }
            let o = copy(&raw);
            assign_obj(&o, &o! { "kind" => "map", "itemKind" => "map", "uid" => format!("map:{}", t(&raw.get("id"))), "packId" => pack.get("id"), "packName" => pack.get("name"),
                "frames" => arr(frames), "warnings" => warnings });
            o.set("placeItems", arr(read::dates::arr(&raw.get("places")).iter().map(|r| place_of(model, r)).collect()));
            let region_map = Map::new();
            for r in read::dates::arr(&raw.get("regions")) { region_map.set(r.get("id"), r); }
            o.set("regionMap", region_map);
            o.set("scenes", arr(map_scenes_of(&V::Obj(o.clone()))));
            put_doc(&o);
            map_map.set(raw.get("id"), o.clone());
            maps.push(o);
        }
        for raw in list(&pack.get("fonts")) {
            if !once(&font_map, &raw, pack, "글꼴") { continue; }
            let o = copy(&raw);
            assign_obj(&o, &o! { "itemKind" => "font", "uid" => format!("font:{}", t(&raw.get("id"))), "packId" => pack.get("id"), "packName" => pack.get("name"),
                "format" => font_format(&raw.get("src")), "warnings" => arr(Vec::new()) });
            font_map.set(raw.get("id"), o.clone());
            fonts.push(o);
        }
    }
}

/// `linkTreatySigners(model)` — 조약의 서명자 ↔ 같은 이름의 인물(서명자 사본에 figureUid · 인물 쪽에 signedTreaties — 체결 순).
pub fn link_treaty_signers(model: &V) {
    let figures = match model.get("figures") { V::Arr(a) => a.to_vec(), _ => return };
    if figures.is_empty() { return; }
    let by_name = Map::new();
    for f in &figures {
        let mut names = vec![f.get("name")];
        for k in ["aka", "aliases", "names"] { if let V::Arr(a) = f.get(k) { names.extend(a.to_vec()); } }
        for nm in names {
            let key = V::Str(js::to_str(&nm).trim());
            if tv(&nm) && !by_name.has(&key) { by_name.set(key, f.clone()); }
        }
    }
    for e in list(&model.get("events")) {
        let refs = e.get("treatyRefs");
        if !tv(&refs) { continue; }
        for pt in list(&refs.get("parties")) {
            for sg in list(&pt.get("signatories")) {
                let f = by_name.get(&sg.get("name"));
                if !tv(&f) || !tv(&f.get("uid")) { continue; }
                ob(&sg).set("figureUid", f.get("uid"));
                if !tv(&f.get("signedTreaties")) { ob(&f).set("signedTreaties", arr(Vec::new())); }
                let l = list(&f.get("signedTreaties"));
                if !l.iter().any(|r| eq(&r.get("event"), &e)) { push_list(&f, "signedTreaties", V::Obj(o! { "event" => e.clone(), "party" => pt.clone(), "signer" => sg.clone() })); }
            }
        }
    }
    for f in &figures { if let V::Arr(l) = f.get("signedTreaties") { l.sort_js(|a, c| sub(&a.get("event").get("start"), &c.get("event").get("start"))); } }
}

/// `HT.rowOrderOf(pe, peopleMap)` — 민족(과 상위 민족)의 배열 기준(없으면 'start').
pub(crate) fn row_order_of(pe: &V, people_map: &V) -> V {
    let mut cur = pe.clone();
    let mut k = 0;
    while tv(&cur) && k < 64 {
        if tv(&cur.get("rowOrder")) { return cur.get("rowOrder"); }
        cur = if tv(&cur.get("parentId")) && tv(people_map) { people_map.as_map().map_or(V::Undef, |m| m.get(&cur.get("parentId"))) } else { V::Null };
        k += 1;
    }
    s("start")
}

/// `linkOrder(model, packs)` — 형식 3: 간지 설정 · 민족의 배열 기준 · 나라의 남북 값(`p.north` — 열거되지 않는 속성) → model.yearCycle · orderWarnings.
pub fn link_order(model: &V, packs: &[V]) {
    let mo = ob(model);
    // ① 간지 설정: 켠 DLC 가운데 yearCycle을 적은 첫 DLC의 것
    mo.set("yearCycle", V::Null);
    for pack in packs {
        let yc = pack.get("yearCycle");
        if yc.is_nullish() { continue; }
        let o = if matches!(yc, V::Bool(false)) { o! { "off" => true } } else { ob(&js::parse(&js::stringify(&yc)).expect("JSON 사본")) };
        o.set("packId", pack.get("id"));
        o.set("packName", pack.get("name"));
        mo.set("yearCycle", o);
        break;
    }
    // ② 민족의 배열 기준: 먼저 켠 DLC의 정의에 없으면 뒤 DLC가 같은 id로 적은 것
    let people_map = model.get("peopleMap");
    let pm = || super::model::util::mp(&people_map, "model.peopleMap");
    for pack in packs {
        for x in list(&pack.get("peoples")) {
            let pe = if tv(&x) && tv(&x.get("rowOrder")) { pm().get(&x.get("id")) } else { V::Null };
            if tv(&pe) && !tv(&pe.get("rowOrder")) { ob(&pe).set("rowOrder", x.get("rowOrder")); }
        }
    }
    // ③ 나라의 남북 값
    let warnings = Arr::default();
    let pack_by_id = Map::new();
    for p in packs { pack_by_id.set(p.get("id"), p.clone()); }
    let crs_memo = Map::new();
    let crs_of = |pl: &V| -> (V, bool) {
        let memo = crs_memo.get(&pl.get("id"));
        if let V::Arr(m) = &memo { return (m.get(0), matches!(m.get(1), V::Bool(true))); }
        let pk = pack_by_id.get(&pl.get("packId"));
        let maps: Vec<V> = list(&if tv(&pk) { pk.get("maps") } else { V::Undef }).into_iter().filter(|m| tv(m) && js::type_of(m) == "object").collect();
        let mut r = (s("lonlat"), false);
        if !maps.is_empty() {
            let hit = maps.iter().find(|m| list(&m.get("places")).iter().any(|r| eq(r, &pl.get("id")) || eq(r, &pl.get("name"))));
            if let Some(hit) = hit { r = (or(hit.get("crs"), s("image")), false); }
            else {
                let kinds = Set::new();
                for m in &maps { kinds.add(or(m.get("crs"), s("image"))); }
                let kinds = kinds.values();
                r = if kinds.len() == 1 { (kinds[0].clone(), false) } else { (s("lonlat"), true) };
            }
        }
        crs_memo.set(pl.get("id"), arr(vec![r.0.clone(), V::Bool(r.1)]));
        r
    };
    let place_map = model.get("placeMap");
    let place_by_name = model.get("placeByName");
    let place_of_ref = |r: &V| -> V {
        if !tv(r) || !tv(&place_map) { return V::Null; }
        let g = place_map.as_map().map_or(V::Undef, |m| m.get(r));
        if tv(&g) { return g; }
        let g = if tv(&place_by_name) { place_by_name.as_map().map_or(V::Undef, |m| m.get(r)) } else { V::Undef };
        if tv(&g) { g } else { V::Null }
    };
    let first_seat = |p: &V| -> V {
        let mut best: Option<(V, f64)> = None;
        for c in list(&p.get("capitals")) {
            if !tv(&c) || (tv(&c.get("role")) && !is(&c.get("role"), "main")) { continue; }
            let st = match c.get("start") { V::Num(x) if x.is_finite() => x, _ => f64::INFINITY };
            if best.as_ref().is_none_or(|b| st < b.1) { best = Some((c, st)); }
        }
        best.map_or(V::Null, |b| b.0)
    };
    let rule_of = Map::new();
    let rule_for = |pe: &V| -> V {
        if !tv(pe) { return s("start"); }
        if !rule_of.has(&pe.get("id")) { rule_of.set(pe.get("id"), row_order_of(pe, &people_map)); }
        rule_of.get(&pe.get("id"))
    };
    for p in list(&model.get("periods")) {
        if !is(&p.get("kind"), "period") { continue; }
        let mut v: Option<f64> = None;
        let mut seat = V::Null;
        let mut mixed = false;
        if let V::Num(ns) = p.get("northSouth") { if ns.is_finite() { v = Some(ns); } }
        if v.is_none() && !matches!(p.get("northSouth"), V::Num(x) if x.is_finite()) {
            seat = first_seat(&p);
            let pl = if tv(&seat) {
                let byid = if tv(&seat.get("placeId")) && tv(&place_map) { place_map.as_map().map_or(V::Undef, |m| m.get(&seat.get("placeId"))) } else { V::Undef };
                if tv(&byid) { byid } else { place_of_ref(&seat.get("city")) }
            } else { V::Null };
            if tv(&pl) {
                if let V::Arr(at) = pl.get("at") {
                    if at.len() == 2 && matches!(at.get(1), V::Num(x) if x.is_finite()) {
                        let (crs, mx) = crs_of(&pl);
                        let y = n(&at.get(1));
                        v = Some(if is(&crs, "image") { -y } else { y });
                        mixed = mx;
                    }
                }
            }
        }
        if let Some(v) = v { ob(&p).define_hidden("north", v); }
        // ④ 기준이 '북 → 남'인 민족에 든 나라만
        let pe = if tv(&p.get("peopleId")) { pm().get(&p.get("peopleId")) } else { V::Null };
        if !tv(&pe) || !is(&rule_for(&pe), "northSouth") { continue; }
        let kind_word = match item_kind_of(&p) { V::Str(k) => match k.as_str().as_ref() { "period" => "periods", "organ" => "organs", "culture" => "cultures", "dynasty" => "dynasties", _ => "periods" }, _ => "periods" };
        let at = o! { "packId" => or(p.get("packId"), s("")), "list" => kind_word, "id" => p.get("id") };
        if mixed {
            let w = o! { "msg" => format!("{}: 첫 정도 «{}»의 지명 좌표를 경위도(둘째 값 = 위도)로 보았습니다 — 그 지명을 실은 지도가 없고 이 지명 사전의 DLC 지도들은 좌표 방식이 섞여 있습니다. 지명을 지도의 지명 목록(places)에 넣거나 남북 위치를 직접 적으세요.", t(&p.get("name")), t(&seat.get("city"))) };
            assign_obj(&w, &at);
            warnings.push(w);
        }
        let pk = p.get("polityKind");
        let head = !p.bool("singleHost") && !is(&pk, "dynasty") && !is(&pk, "overlay") && !list(&p.get("predecessors")).iter().any(|e| tv(&e.get("from")) && eq(&e.get("from").get("track"), &p.get("track")));
        if v.is_none() && head {
            let w = o! { "msg" => format!("{}: 남북 위치 없음 — 민족 «{}»의 배열 기준이 '북 → 남'인데 남북 위치도, 지명 좌표가 있는 첫 정도도 없어 같은 묶음의 값이 있는 줄들 뒤에 놓입니다.", t(&p.get("name")), t(&pe.get("name"))) };
            assign_obj(&w, &at);
            warnings.push(w);
        }
    }
    mo.set("orderWarnings", warnings);
}

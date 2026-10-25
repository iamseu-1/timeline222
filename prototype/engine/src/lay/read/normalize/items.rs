//! `HT.normalizePack` 안의 사건 · 인물 · 단체 · 제도 — 4553 ~ 4779줄(과제 5c).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 4553 ~ 4618줄 사건([`read_events`] — 조약 · 법 · 선거 규격 · 주제 꼬리표 · 자리 · 관련 인물 · 장소 · 이름 목록)
//! - 4620 ~ 4709줄 인물([`read_figures`] — 생몰 · 활동 시기 · 미정 · 섬긴 기록 · 계보 전용 · 형제 순서 · 사람 잇기)
//! - 4711 ~ 4754줄 단체([`read_groups`] — 있던 나라 · 앞선 단체 · 집권 · 구성원 · 구성 나라)
//! - 4756 ~ 4779줄 제도([`read_institutions`] — 제도 칸)
//! 사건의 tags `str(e.tags).split(',')`은 코드 단위로(`read::split_units`).
use super::cell_lists::{figure_date_word, name_list};
use super::{apply_range, floor_text, list_of, Norm};
use crate::lay::js::{self, Obj, Str, V};
use crate::lay::read::{self as read, cells, dates, groups, misc, names, treaty};

/// 4553 ~ 4618줄 — 사건 목록.
pub(super) fn read_events(n: &mut Norm, pack: &Obj, raw: &V) {
    let ctx = n.ctx;
    let s = dates::str_of;
    for (i, e) in dates::arr(&raw.get("events")).iter().enumerate() {
        if !js::truthy(e) || !read::is_object(e) { n.err(format!("사건 #{}: 형식이 올바르지 않습니다.", i + 1), "events", Some(i)); continue; }
        let title = s(&js::nullish(e.get("title"), e.get("name")));
        let label = format!("사건 #{}{}", i + 1, if title.is_empty() { String::new() } else { format!(" \"{title}\"") });
        if title.is_empty() { n.err(format!("{label}: 제목이 비어 있습니다."), "events", Some(i)); continue; }
        let track = s(&e.get("track"));
        if !n.check_track(&track, &label, "events", i) { continue; }
        let Some(r) = n.read_range(e, &label, "events", i) else { continue };
        let seed = read::cat(&[&track, &floor_text(r.start), &title]);
        let o = Obj::new();
        o.set("id", n.take_id(e, "e-", &seed, &label, "events", i));
        o.set("track", track);
        o.set("title", title);
        apply_range(&o, &r);
        let category = s(&e.get("category"));
        if !category.is_empty() {
            if !n.cat_ids.contains(&category) { n.warn(format!("{label}: 분류 \"{category}\"이(가) 정의되어 있지 않습니다."), "events", Some(i)); }
            o.set("category", category);
        }
        let imp = e.get("importance");
        let mut importance = js::to_num(&js::nullish(imp.clone(), V::Num(2.0)));
        if ![1.0, 2.0, 3.0].contains(&importance) {
            if !read::is_empty_str(&imp) && !imp.is_nullish() { n.warn(format!("{label}: 중요도는 1~3이어야 해서 2로 바꿨습니다."), "events", Some(i)); }
            importance = 2.0;
        }
        o.set("importance", importance);
        // 자리(spot): 날짜를 정확히 모르는 점 사건이 그 구간 안에서 놓일 자리 0(처음) ~ 1(끝) — 비우면 가운데(0.5)
        let spot = e.get("spot");
        if read::given(&spot) {
            match misc::read_spot(&spot) {
                None => n.warn(format!("{label}: 자리(spot)는 0~1이어야 해서 뺐습니다 — 0 처음 · 0.5 가운데 · 1 끝."), "events", Some(i)),
                Some(v) => o.set("spot", v),
            }
        }
        let polity = s(&e.get("polity"));
        if !polity.is_empty() { o.set("polity", polity); }
        let views: Vec<V> = dates::arr(&e.get("perspectives"))
            .iter()
            .filter(|v| js::truthy(v) && js::type_of(v) == "object")
            .map(|v| ["track", "title", "description", "source"].map(|k| (k, s(&v.get(k)))))
            .filter(|v| !v[0].1.is_empty() && (!v[1].1.is_empty() || !v[2].1.is_empty()))
            .map(|v| { let q = Obj::new(); for (k, t) in v { if !t.is_empty() { q.set(k, t); } } V::Obj(q) })
            .collect();
        if !views.is_empty() { o.set("perspectives", read::arr_of(views)); }
        let parent = s(&e.get("parent"));
        if !parent.is_empty() { o.set("parent", parent); }
        for k in ["polities", "tracks"] {
            let list: Vec<V> = dates::arr(&e.get(k)).iter().map(s).filter(|t| !t.is_empty()).map(V::Str).collect();
            if !list.is_empty() { o.set(k, read::arr_of(list)); }
        }
        for (k, v) in n.read_uncertainty(e, &label, "events", i, r.start).entries() { o.set(&k, v); }
        for k in ["date", "description"] {
            let t = s(&e.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !s(&e.get("wiki")).is_empty() { o.set("wiki", js::to_str(&e.get("wiki"))); }
        let tags_in: Vec<V> = match e.get("tags") { V::Arr(a) => a.to_vec(), x => read::split_units(&s(&x), &[0x2C]).into_iter().map(V::Str).collect() };
        let tags: Vec<V> = tags_in.iter().map(s).filter(|t| !t.is_empty()).map(V::Str).collect();
        if !tags.is_empty() { o.set("tags", read::arr_of(tags)); }
        let source = s(&e.get("source"));
        if !source.is_empty() { o.set("source", source); }
        let related = name_list(&e.get("figures")); // 관련 인물(이름 · id)
        if !related.is_empty() { o.set("figures", read::arr_of(related.into_iter().map(V::Str).collect())); }
        // 조약 규격: 이 칸이 있으면 조약이다(체결 = start, 실효 = end) — 비어 있으면 보통 사건
        let mut msgs = Vec::new();
        let tr = treaty::read_treaty(ctx, &e.get("treaty"), &mut |m| msgs.push(m));
        n.warn_all(msgs, &format!("{label}: "), "events", i);
        if let Some(t) = tr { o.set("treaty", t); }
        // 형식 버전 3: 주제 꼬리표 · 법 규격 · 선거 규격(조약 규격처럼 — 비어 있으면 칸이 없음)
        let themes = groups::read_theme_list(&e.get("theme"));
        if !themes.is_empty() { o.set("theme", read::arr_of(themes.into_iter().map(V::Str).collect())); }
        let mut msgs = Vec::new();
        let law = groups::read_law(&e.get("law"), &mut |m| msgs.push(m));
        n.warn_all(msgs, &format!("{label}: "), "events", i);
        if let Some(l) = law { o.set("law", l); }
        let mut msgs = Vec::new();
        let election = groups::read_election(&e.get("election"), &mut |m| msgs.push(m));
        n.warn_all(msgs, &format!("{label}: "), "events", i);
        if let Some(x) = election { o.set("election", x); }
        // 형식 버전 3: 장소(지명 사전의 이름이나 id) · 제목의 다른 이름(이름 목록)
        let place = s(&e.get("place"));
        if !place.is_empty() { o.set("place", place); }
        n.put_names(&o, &e.get("names"), &label, "events", i);
        list_of(pack, "events").push(V::Obj(o));
    }
}

/// 4620 ~ 4709줄 — 인물 목록(인물이 있는 DLC에만 `pack.figures`가 생긴다). 날짜는 생몰 · 활동 · 섬긴 기간 가운데 하나 이상이면 된다(시작이 선택 사항이라 `readRange`를 쓰지 않음).
pub(super) fn read_figures(n: &mut Norm, pack: &Obj, raw: &V) {
    let ctx = n.ctx;
    let s = dates::str_of;
    let mut figures: Vec<V> = Vec::new();
    'figures: for (i, f) in dates::arr(&raw.get("figures")).iter().enumerate() {
        if !js::truthy(f) || !read::is_object(f) { n.err(format!("인물 #{}: 형식이 올바르지 않습니다.", i + 1), "figures", Some(i)); continue; }
        let name = s(&js::nullish(f.get("name"), f.get("title")));
        let label = format!("인물 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "figures", Some(i)); continue; }
        let track = s(&f.get("track"));
        if !n.check_track(&track, &label, "figures", i) { continue; }
        let ongoing = matches!(f.get("ongoing"), V::Bool(true)) || dates::is_ongoing_text(&f.get("end"));
        // 활동 시기의 미정(칸의 미정과 같은 말): "미정" 글 · startUnknown(+ 숫자) · startHint → 미정 + (있으면) 배치용 연도
        let mut unk: [Option<Option<f64>>; 2] = [None, None]; // start · end — Some(배치용 연도)
        for (j, k) in ["start", "end"].iter().enumerate() {
            let d = if *k == "end" && ongoing { None } else { cells::read_cell_edge(ctx, f, k) };
            if let Some(cells::Edge::Unknown(t)) = d { unk[j] = Some(t); }
        }
        let unk_of = |k: &str| if k == "start" { Some(0) } else if k == "end" { Some(1) } else { None };
        let mut dates_of: Vec<(&str, dates::DateR)> = Vec::new(); // birth · death · start · end 차례
        for k in ["birth", "death", "start", "end"] {
            let skip = (k == "end" && ongoing) || unk_of(k).is_some_and(|j| unk[j].is_some());
            let d = if skip { None } else { dates::date_in(ctx, f, k) };
            if let Some(d) = d {
                if d.t.is_nan() {
                    let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" {e}"));
                    n.err(format!("{label}: {} 날짜가 올바르지 않습니다.{why}", figure_date_word(k)), "figures", Some(i));
                    continue 'figures;
                }
                dates_of.push((k, d));
            }
        }
        let got = |k: &str| dates_of.iter().find(|(x, _)| *x == k).map(|(_, d)| d.clone());
        let t_of = |k: &str| got(k).map(|d| d.t);
        let at_of = |k: &str| got(k).and_then(|d| d.at).map_or(V::Null, V::Str);
        if let (Some(b), Some(d)) = (t_of("birth"), t_of("death")) {
            if dates::end_bound_t(ctx, d, &at_of("death")) < b { n.err(format!("{label}: 사망이 출생보다 앞섭니다."), "figures", Some(i)); continue; }
        }
        if let (Some(st), Some(en)) = (t_of("start"), t_of("end")) {
            if dates::end_bound_t(ctx, en, &at_of("end")) < st { n.err(format!("{label}: 활동의 끝이 시작보다 앞섭니다."), "figures", Some(i)); continue; }
        }
        // 미정인 쪽의 배치용 연도가 다른 쪽과 거꾸로면 그 배치용 연도만 버린다(미정은 그대로 — 자리는 모델이 짐작)
        let s_hint = match unk[0] { Some(t) => t, None => t_of("start") };
        let e_hint = match unk[1] { Some(t) => t, None => t_of("end") };
        if unk[0].is_some() || unk[1].is_some() {
            if let (Some(sh), Some(eh)) = (s_hint, e_hint) {
                if dates::end_bound_t(ctx, eh, &at_of("end")) < sh {
                    let end_side = unk[1].is_some();
                    n.warn(format!("{label}: 활동의 {}이 미정인데 배치용 연도가 {} 그 배치용 연도를 버렸습니다.", if end_side { "끝" } else { "시작" }, if end_side { "시작보다 앞서" } else { "끝보다 뒤라" }), "figures", Some(i));
                    unk[if end_side { 1 } else { 0 }] = Some(None);
                }
            }
        }
        let service = n.read_service(&f.get("service"), &label, "figures", i);
        // 계보 전용 인물(lineageOnly — 형식 버전 3): 띠의 인물 단에 놓지 않는 사람. 날짜가 하나도 없어도 받고, 중요도를 쓰지 않는다
        let lo = f.get("lineageOnly");
        let lineage_only = matches!(lo, V::Bool(true));
        if !lo.is_nullish() && !matches!(lo, V::Bool(_)) && !read::is_empty_str(&lo) {
            n.warn(format!("{label}: 계보 전용(lineageOnly)은 true · false로 적습니다 — \"{}\"은(는) 무시했습니다.", s(&lo)), "figures", Some(i));
        }
        if !lineage_only && dates_of.is_empty() && !unk.iter().any(|t| matches!(t, Some(Some(_)))) && !service.iter().any(|x| !x.get("start").is_nullish() || !x.get("end").is_nullish()) {
            n.err(format!("{label}: 날짜가 하나도 없습니다. 생몰(birth · death) · 활동 시기(start · end) · 활동 기록의 기간 가운데 하나는 적어 주세요."), "figures", Some(i));
            continue;
        }
        // 자동 id의 씨앗은 트랙 + 이름(+ 생년) — 계보 전용 인물은 첫 부모 글도 씨앗에 넣는다
        let seed_tail = if lineage_only {
            let first = names::read_parents(ctx, &f.get("parents"), &mut |_| {}).into_iter().next();
            let who = match first { None => Str::default(), Some(p) => if js::truthy(&p.get("whoUnknown")) { Str::from("미상") } else { names::person_ref_text(&p.get("who")) } };
            read::cat(&[&Str::from("|"), &who])
        } else { Str::default() };
        let birth = t_of("birth").map_or(Str::default(), floor_text);
        let seed = read::cat(&[&track, &Str::from("|"), &name, &Str::from("|"), &birth, &seed_tail]);
        let o = Obj::new();
        o.set("id", n.take_id(f, "f-", &seed, &label, "figures", i));
        o.set("track", track);
        o.set("name", name.clone());
        if lineage_only { o.set("lineageOnly", true); }
        let order = f.get("order");
        if !read::is_empty_str(&order) && !order.is_nullish() {
            let num = js::to_num(&order);
            if num.is_finite() && num == num.trunc() { o.set("order", num); } // 형제 순서(작을수록 앞)
            else { n.warn(format!("{label}: 형제 순서(order)는 정수로 적습니다 — \"{}\"은(는) 뺐습니다.", s(&order)), "figures", Some(i)); }
        }
        let aka: Vec<V> = name_list(&f.get("aka")).into_iter().filter(|a| *a != name).map(V::Str).collect();
        if !aka.is_empty() { o.set("aka", read::arr_of(aka)); }
        let role = s(&f.get("role"));
        if !role.is_empty() { o.set("role", role); }
        for k in ["birth", "death", "start", "end"] {
            if let Some(j) = unk_of(k) {
                if let Some(t) = unk[j] {
                    if let Some(t) = t { o.set(k, t); } // 배치용 연도(시대 · 칸의 미정과 같은 꼴: startUnknown + start 숫자)
                    o.set(&format!("{k}Unknown"), true);
                    continue;
                }
            }
            let Some(d) = got(k) else { continue };
            o.set(k, d.t);
            if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
        }
        if ongoing { o.set("ongoing", true); }
        let has_service = !service.is_empty();
        if has_service { o.set("service", read::arr_of(service)); }
        if lineage_only && has_service { n.warn(format!("{label}: 계보 전용 인물의 활동 기록은 연표에 그리지 않습니다 — 띠에 그리려면 계보 전용을 끕니다."), "figures", Some(i)); }
        let house = s(&f.get("house"));
        if !house.is_empty() { o.set("house", house); } // 가문의 이름 · id — 가문 사전과 잇는 것은 모델의 몫
        let imp = f.get("importance");
        if lineage_only {
            if !read::is_empty_str(&imp) && !imp.is_nullish() { n.warn(format!("{label}: 계보 전용 인물은 중요도를 쓰지 않아 뺐습니다."), "figures", Some(i)); }
        } else {
            let mut importance = js::to_num(&js::nullish(imp.clone(), V::Num(2.0)));
            if ![1.0, 2.0, 3.0].contains(&importance) {
                if !read::is_empty_str(&imp) && !imp.is_nullish() { n.warn(format!("{label}: 중요도는 1~3이어야 해서 2로 바꿨습니다."), "figures", Some(i)); }
                importance = 2.0;
            }
            o.set("importance", importance);
        }
        let description = s(&f.get("description"));
        if !description.is_empty() { o.set("description", description); }
        let tags = name_list(&f.get("tags"));
        if !tags.is_empty() { o.set("tags", read::arr_of(tags.into_iter().map(V::Str).collect())); }
        let source = s(&f.get("source"));
        if !source.is_empty() { o.set("source", source); }
        if !s(&f.get("wiki")).is_empty() { o.set("wiki", js::to_str(&f.get("wiki"))); }
        // 다른 견해만 — 생몰 · 활동 시기 가운데 적은 쪽만(통설 값 = 지금까지 만든 o)
        let mut msgs = Vec::new();
        let base = V::Obj(o.clone());
        let unc = cells::read_uncertain(ctx, f, "figure", Some(&mut |m: String| msgs.push(m)), None, None, Some(&base));
        n.warn_all(msgs, &format!("{label}: "), "figures", i);
        for (k, v) in unc.entries() { o.set(&k, v); }
        n.put_names(&o, &f.get("names"), &label, "figures", i); // 이름 목록(형식 버전 3 — aka는 그대로)
        n.put_lineage(&o, f, &label, "figures", i, false, false, true); // 부모 · 배우자(형식 버전 3)
        figures.push(V::Obj(o));
    }
    if !figures.is_empty() { pack.set("figures", read::arr_of(figures)); }
}

/// 4711 ~ 4754줄 — 단체 목록(형식 버전 3: 붕당 · 정당 · 정권(실권 집단) · 세력 · 연합). name · track · start 필수 — 기간은 시대 · 기관과 같은 읽기.
/// 목록이 비면 파일에 적지 않는다.
pub(super) fn read_groups(n: &mut Norm, pack: &Obj, raw: &V) {
    let ctx = n.ctx;
    let s = dates::str_of;
    let mut list: Vec<V> = Vec::new();
    for (i, g) in dates::arr(&raw.get("groups")).iter().enumerate() {
        if !js::truthy(g) || !read::is_plain(g) { n.err(format!("단체 #{}: 형식이 올바르지 않습니다.", i + 1), "groups", Some(i)); continue; }
        let name = s(&g.get("name"));
        let label = format!("단체 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "groups", Some(i)); continue; }
        let track = s(&g.get("track"));
        if !n.check_track(&track, &label, "groups", i) { continue; }
        let Some(r) = n.read_range(g, &label, "groups", i) else { continue };
        let seed = read::cat(&[&track, &floor_text(r.start), &name]);
        let o = Obj::new();
        let id = n.take_id(g, "gr-", &seed, &label, "groups", i);
        o.set("id", id.clone());
        o.set("track", track);
        o.set("name", name.clone());
        let ty = groups::group_type(&g.get("type"));
        if !ty.is_empty() { o.set("type", ty.clone()); }
        else if !s(&g.get("type")).is_empty() { o.set("type", s(&g.get("type"))); } // 표에 없는 종류는 자유 글 그대로
        apply_range(&o, &r);
        let mut msgs = Vec::new();
        let within = groups::read_polity_rows(ctx, &g.get("within"), false, &mut |m| msgs.push(m), "있던 나라");
        n.warn_all(msgs, &format!("{label}: 있던 나라 "), "groups", i);
        if !within.is_empty() { o.set("within", groups::compact_polity_rows(within)); }
        let mut msgs = Vec::new();
        let from_all = groups::read_group_from(&g.get("from"), &mut |m| msgs.push(m));
        n.warn_all(msgs, &format!("{label}: "), "groups", i);
        let mut from = Vec::new();
        for x in from_all {
            let grp = x.get("group");
            if !js::strict_eq(&grp, &V::Str(name.clone())) && !js::strict_eq(&grp, &V::Str(id.clone())) { from.push(x); continue; }
            n.warn(format!("{label}: 앞선 단체에 자기 자신을 적어 뺐습니다."), "groups", Some(i));
        }
        if !from.is_empty() { o.set("from", read::arr_of(from)); }
        let power = n.read_cells(&g.get("power"), &label, "groups", i, "집권");
        if !power.is_empty() { o.set("power", read::arr_of(power)); }
        let mut msgs = Vec::new();
        let people = names::read_group_people(ctx, &g.get("people"), &mut |m| msgs.push(m)); // 구성원 — 사람 참조(풀이는 모델의 사람 잇기)
        n.warn_all(msgs, &format!("{label}: "), "groups", i);
        if !people.is_empty() { o.set("people", read::arr_of(people)); }
        let mut msgs = Vec::new();
        let members = groups::read_polity_rows(ctx, &g.get("members"), true, &mut |m| msgs.push(m), "구성 나라");
        n.warn_all(msgs, &format!("{label}: 구성 나라 "), "groups", i);
        let count = members.len();
        if !members.is_empty() { o.set("members", read::arr_of(members)); }
        if ty == "coalition" && count < 2 {
            n.warn(format!("{label}: 연합인데 구성 나라가 {}입니다 — 연합의 구성 나라(members)를 둘 이상 적어 주세요.", if count > 0 { "하나뿐" } else { "없" }), "groups", Some(i));
        }
        let event = s(&g.get("event"));
        if !event.is_empty() { o.set("event", event); } // 맺은 사건(사건의 제목이나 id)
        n.put_names(&o, &g.get("names"), &label, "groups", i); // 이름 목록(원어 · 옛 이름 · 약칭)
        for (k, v) in n.read_uncertainty(g, &label, "groups", i, r.start).entries() { o.set(&k, v); }
        if misc::is_color(&g.get("color")) { o.set("color", g.get("color")); }
        for k in ["description", "note"] {
            let t = s(&g.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !s(&g.get("wiki")).is_empty() { o.set("wiki", js::to_str(&g.get("wiki"))); }
        list.push(V::Obj(o));
    }
    if !list.is_empty() { pack.set("groups", read::arr_of(list)); }
}

/// 4756 ~ 4779줄 — 제도 목록(형식 버전 3 — 렌즈의 재료): 나라마다 주제마다 이어지는 칸 목록. theme · polity · spans 필수. 나라 · 주제를 찾는 것은 모델.
pub(super) fn read_institutions(n: &mut Norm, pack: &Obj, raw: &V) {
    let ctx = n.ctx;
    let s = dates::str_of;
    let mut list: Vec<V> = Vec::new();
    for (i, x) in dates::arr(&raw.get("institutions")).iter().enumerate() {
        if !js::truthy(x) || !read::is_plain(x) { n.err(format!("제도 #{}: 형식이 올바르지 않습니다.", i + 1), "institutions", Some(i)); continue; }
        let theme = match x.get("theme") { V::Arr(a) => s(&a.get(0)), t => s(&t) };
        let rf = groups::read_inst_polity(&x.get("polity"), &x.get("track"));
        let shown: Vec<Str> = [rf.as_ref().map(|r| r.str("polity").unwrap_or_default()).unwrap_or_default(), theme.clone()].into_iter().filter(|t| !t.is_empty()).collect();
        let label = format!("제도 #{}{}", i + 1, if !theme.is_empty() || rf.is_some() { format!(" \"{}\"", Str::join(&shown, " · ")) } else { String::new() });
        if theme.is_empty() { n.err(format!("{label}: 주제(theme)가 비어 있습니다."), "institutions", Some(i)); continue; }
        let Some(rf) = rf else { n.err(format!("{label}: 나라(polity)가 비어 있습니다."), "institutions", Some(i)); continue; };
        let sp = groups::read_inst_spans(ctx, &x.get("spans"));
        for msg in sp.problems.iter().chain(sp.warnings.iter()) { n.warn(format!("{label}: {msg}"), "institutions", Some(i)); }
        if sp.list.is_empty() { n.err(format!("{label}: 제도 칸(spans)이 하나도 없습니다."), "institutions", Some(i)); continue; }
        let rtrack = rf.str("track").unwrap_or_default();
        let rpolity = rf.str("polity").unwrap_or_default();
        let seed = read::cat(&[&rtrack, &Str::from("|"), &rpolity, &Str::from("|"), &theme]);
        let o = Obj::new();
        o.set("id", n.take_id(x, "in-", &seed, &label, "institutions", i));
        o.set("theme", theme);
        if !rtrack.is_empty() { o.set("track", rtrack); }
        o.set("polity", rpolity);
        let family = s(&x.get("family"));
        if !family.is_empty() { o.set("family", family); }
        o.set("spans", read::arr_of(sp.list));
        n.put_names(&o, &x.get("names"), &label, "institutions", i); // 이름 목록(제도의 원어 · 다른 이름)
        let description = s(&x.get("description"));
        if !description.is_empty() { o.set("description", description); }
        if !s(&x.get("wiki")).is_empty() { o.set("wiki", js::to_str(&x.get("wiki"))); }
        list.push(V::Obj(o));
    }
    if !list.is_empty() { pack.set("institutions", read::arr_of(list)); }
}

//! 모듈 `entities`가 부르는 웹 함수 가운데 사람 자리 · 자리 이음 · 계보 뼈대 · 머리 칩 · 가문 조명(`js/core.js` 6829 ~ 7760줄의 절) — 줄 그대로.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 6829줄 `HT.personOf` · 6831 ~ 6834줄 `HT.placeOf`(→ `lay::link::place_of`) · 6836줄 `personRuled`
//! - 6867 ~ 6891줄 `HT.lineageOf`
//! - 6987 ~ 6995줄 `KIN_TREE_ORDER` · `kinTreeRank` · `KIN_PATERNAL` · `kinEdgeCode` · 6998 ~ 7003줄 `kinCache` · `kinStore`(모델마다의 기억 — [`KinCache`]) ·
//!   7007 ~ 7032줄 `kinGroupsGen` · `runGen` · `kinGroups`(나눠 짓기의 양보 `yield`는 답에 닿지 않아 빼고 끝까지 돈다) · 7033 ~ 7041줄 `kinYear` · `kinSub`
//! - 7050 ~ 7057줄 `HT.kinSkeleton` · 7096 ~ 7357줄 `kinBuild`(→ [`kin_build`] — 단계 ① ~ ⑥) · 7359 ~ 7375줄 `HT.kinOf` · `HT.kinOfPerson`
//! - 7498줄 `polityOf` · 7569 ~ 7593줄 `HT.accessionLine` · `HT.accessionSeam` · 7594 ~ 7621줄 `peopleOf` · `trackChip` · `peopleChip` · `tagChips` · `clean` · 7622 ~ 7626줄 `HT.polityHead`
//! - 7627 ~ 7656줄 `houseOf` · `seatSurname` · `TRACK_FROM` · `HT.houseHead` · 7658 ~ 7673줄 `HT.houseUnder` · 7682 ~ 7722줄 `HT.houseSpans` · 7727 ~ 7746줄 `HT.houseEras`
//!
//! 옮기지 않은 것(내보내기가 부르지 않음 — 화면 · 메이커): `HT.kinSkeletonAsync`(같은 뼈대를 나눠 지음) · `HT.kinDefaultOpen` · `HT.kinLayout` · `HT.successionRows` · `HT.familyOf` · `HT.unionPairs`.
//! 뼈대는 JS의 형 붙은 배열(Int32Array) 그대로 정수 열([`Skel`])로 둔다 — `kin.mjs`의 `recordOf`가 이 꼴만 받는다(`kin.rs` 머리말).
use super::web::{accession_how_name, format_axis_year, map_get, map_has};
use crate::lay::js::{self, Map, Str, V};
use crate::lay::model::util::{eq, fault, is, item_kind_of, kin_name, leader_label, list, n, nn, or, s, t, tv};
use std::collections::HashMap;
use std::rc::Rc;

// ── 사람 자리 ──

/// `HT.personOf(model, x, ref)` — 칸(정권 · 칸 참조 'leader:3')이나 인물의 사람 자리(없으면 null).
pub fn person_of(model: &V, x: &V, r: Option<&str>) -> V {
    if !tv(model) || !tv(&model.get("personIndex")) || !tv(x) { return V::Null; }
    let key = match r { Some(r) => format!("c:{}|{r}", t(&x.get("uid"))), None => format!("f:{}", t(&x.get("uid"))) };
    let v = map_get(&model.get("personIndex"), &V::from(key));
    if tv(&v) { v } else { V::Null }
}
/// `personRuled(n)`의 한 줄 `{ polity, uid, name, ref, i, ordinal, color, start }`.
pub struct Ruled { pub polity: V, pub uid: V, pub name: V, pub r#ref: V, pub i: V, pub ordinal: V, pub color: V, pub start: V }
/// `personRuled(n)` — 사람 자리가 다스린 칸들(지도자 칸만).
pub fn person_ruled(nd: &V) -> Vec<Ruled> {
    if !tv(nd) { return Vec::new(); }
    list(&nd.get("cells")).into_iter().filter(|x| is(&x.get("kind"), "leader")).map(|x| {
        let p = x.get("p");
        Ruled { uid: p.get("uid"), name: p.get("name"), r#ref: x.get("ref"), i: x.get("i"), ordinal: nn(x.get("c").get("ordinal"), V::Null), color: p.get("color"), start: x.get("c").get("start"), polity: p }
    }).collect()
}

// ── 자리 이음 ──

/// `HT.lineageOf`의 `accession`.
pub struct Acc { pub kin: V, pub kin_name: Str, pub kin_unknown: bool, pub how: V, pub how_name: Str, pub how_unknown: bool, pub from: V, pub from_ruler: f64, pub from_auto: bool, pub from_unknown: bool, pub note: V }
/// `HT.lineageOf`의 `rulers[i]`.
pub struct Ruler { pub i: usize, pub r#ref: String, pub cell: V, pub name: V, pub start: V, pub end: V, pub ordinal: V, pub person: V, pub restored: bool, pub elsewhere: Vec<Ruled>, pub accession: Acc }
/// `HT.lineageOf(model, polity)` — 한 나라의 자리 이음 표 자료(정권 객체로 부름). 없으면 None.
pub fn lineage_of(model: &V, p: &V) -> Option<Vec<Ruler>> {
    if !tv(model) || !tv(&model.get("personIndex")) { return None; }
    if !tv(p) || !is(&p.get("kind"), "period") { return None; }
    let leaders = list(&p.get("leaders"));
    let people: Vec<V> = (0..leaders.len()).map(|i| person_of(model, p, Some(&format!("leader:{i}")))).collect();
    let rulers = leaders.iter().enumerate().map(|(i, c)| {
        let person = people[i].clone();
        let a = or(c.get("accession"), V::Obj(js::Obj::new()));
        let explicit = or(map_get(&model.get("accessionFrom"), &V::from(format!("c:{}|leader:{i}", t(&p.get("uid"))))), V::Null);
        let from = if tv(&a.get("fromUnknown")) { V::Null } else { or(explicit.clone(), if i > 0 { people[i - 1].clone() } else { V::Null }) };
        let from_ruler = if tv(&from) {
            if tv(&explicit) { people.iter().enumerate().position(|(j, q)| j < i && eq(q, &from)).map_or(-1.0, |j| j as f64) } else { i as f64 - 1.0 }
        } else { -1.0 };
        let kin = or(a.get("kin"), s(""));
        let how = or(a.get("how"), s(""));
        Ruler {
            i, r#ref: format!("leader:{i}"), cell: c.clone(), name: leader_label(c), start: c.get("start"), end: nn(c.get("end"), V::Null), ordinal: nn(c.get("ordinal"), V::Null),
            restored: tv(&person) && people[..i].iter().any(|q| eq(q, &person)),
            elsewhere: person_ruled(&person).into_iter().filter(|r| !eq(&r.polity, p)).collect(),
            accession: Acc {
                kin_name: if tv(&a.get("kin")) { kin_name(&a.get("kin")) } else { Str::default() }, kin, kin_unknown: tv(&a.get("kinUnknown")),
                how_name: if tv(&a.get("how")) { accession_how_name(&a.get("how")) } else { Str::default() }, how, how_unknown: tv(&a.get("howUnknown")),
                from, from_ruler, from_auto: !tv(&a.get("from")) && !tv(&a.get("fromUnknown")) && i > 0, from_unknown: tv(&a.get("fromUnknown")), note: or(a.get("note"), s("")),
            },
            person,
        }
    }).collect();
    Some(rulers)
}
/// `HT.accessionLine(acc)` — 승계 선 갈래: 1 찬탈 · 정변 · 정복 · 2 관계나 방식 미상 · 3 선양 · 4 복위 · 5 그 밖의 적은 값 · 0 모두 비움.
pub fn accession_line(a: &Acc) -> f64 {
    if ["usurpation", "coup", "conquest"].iter().any(|k| is(&a.how, k)) { return 1.0; }
    if a.kin_unknown || a.how_unknown { return 2.0; }
    if is(&a.how, "abdication") { return 3.0; }
    if is(&a.how, "restoration") { return 4.0; }
    if tv(&a.kin) || tv(&a.how) { return 5.0; }
    0.0
}
/// `HT.accessionSeam(model, ruler)` — 이음매 글('전임자 ○○의 동생 · 찬탈' …). 관계 · 방식을 모두 비웠으면 ''.
pub fn accession_seam(r: &Ruler) -> String {
    let a = &r.accession;
    let kin: String = if a.kin_unknown { "관계 미상".into() } else if tv(&a.kin) { if a.kin_name.is_empty() { kin_name(&a.kin).as_str().into_owned() } else { a.kin_name.as_str().into_owned() } } else { String::new() };
    let how: String = if a.how_unknown { "방식 미상".into() } else if tv(&a.how) { if a.how_name.is_empty() { accession_how_name(&a.how).as_str().into_owned() } else { a.how_name.as_str().into_owned() } } else { String::new() };
    if kin.is_empty() && how.is_empty() { return String::new(); }
    let mut who = String::new();
    if a.from_unknown { who = "전임자 미상".into(); }
    else if tv(&a.from) && !a.from_auto { who = format!("전임자 {}", t(&or(a.from.get("name"), s("미상")))); }
    let head = if !who.is_empty() && !kin.is_empty() && !a.kin_unknown && !a.from_unknown { format!("{who}의 {kin}") } else { [who, kin].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(" · ") };
    [head, how].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(" · ")
}

// ── 머리 칩 ──

/// 머리 칩 하나 `{ role, text, title?, uid?, field, auto? }`(undefined는 V::Undef — `clean`이 지우는 열쇠). field는 메이커 몫이라 내보내기가 읽지 않는다.
pub struct Chip { pub role: &'static str, pub text: V, pub title: V, pub uid: V, pub auto: bool }
/// `peopleOf(model, ref)`의 답 `{ people, name, chain }`.
struct PeopleRef { people: V, name: V, chain: V }
/// `peopleOf(model, ref)` — 민족 참조(이름 · id) → 모델의 민족과 위 단계 사슬(대명제 › … › 민족).
fn people_of(model: &V, r: &V) -> Option<PeopleRef> {
    let rr = js::to_str(&nn(r.clone(), s(""))).trim();
    if rr.is_empty() || !tv(model) || !tv(&model.get("peopleMap")) { return None; }
    let key = V::Str(rr.clone());
    let find = |name: &V| -> V {
        let hit = map_get(&model.get("peopleMap"), name);
        if tv(&hit) { return hit; }
        list(&model.get("peoples")).into_iter().find(|x| eq(&x.get("name"), name)).unwrap_or(V::Null)
    };
    let pe = find(&key);
    if !tv(&pe) { return Some(PeopleRef { people: V::Null, name: key.clone(), chain: key }); }
    let mut chain: Vec<String> = Vec::new();
    let mut seen: Vec<V> = Vec::new();
    let mut cur = pe.clone();
    while tv(&cur) && !seen.iter().any(|x| js::strict_eq(x, &cur.get("id")) || (x.as_num().is_some_and(f64::is_nan) && cur.get("id").as_num().is_some_and(f64::is_nan))) {
        seen.push(cur.get("id"));
        let nm = cur.get("name");
        chain.insert(0, if nm.is_nullish() { String::new() } else { t(&nm) }); // Array.join은 null · undefined를 ''로
        cur = if tv(&cur.get("parent")) { find(&cur.get("parent")) } else { V::Null };
    }
    Some(PeopleRef { name: pe.get("name"), people: pe, chain: V::from(chain.join(" › ")) })
}
/// `trackChip(model, id, extra)`.
fn track_chip(model: &V, id: &V, auto: bool, title: V) -> Chip {
    let tr = map_get(&model.get("trackMap"), id);
    let tr = if tv(&model.get("trackMap")) && tv(&tr) { tr } else { V::Null };
    Chip { role: "track", text: if tv(&tr) { tr.get("name") } else { id.clone() }, uid: V::from(format!("track:{}", t(id))), title, auto }
}
/// `peopleChip(model, ref, extra)` — 민족이 없으면 None.
fn people_chip(model: &V, r: &V, auto: bool) -> Option<Chip> {
    let pe = people_of(model, r)?;
    let uid = if tv(&pe.people) { V::from(format!("people:{}", t(&pe.people.get("id")))) } else { V::Undef };
    let title = if !js::strict_eq(&pe.chain, &pe.name) { pe.chain.clone() } else { V::Undef };
    Some(Chip { role: "people", text: pe.name, uid, title, auto })
}
/// `tagChips(tags)`.
fn tag_chips(tags: &V) -> Vec<Chip> {
    list(tags).into_iter().filter(tv).map(|x| Chip { role: "tag", text: V::Str(js::to_str(&x)), title: V::Undef, uid: V::Undef, auto: false }).collect()
}
/// `polityOf(model, polity)` — 객체면 그것, 아니면 `model.byUid`에서.
fn polity_of(model: &V, polity: &V) -> V {
    if matches!(polity, V::Obj(_)) { return polity.clone(); }
    if tv(model) && tv(&model.get("byUid")) { or(map_get(&model.get("byUid"), polity), V::Null) } else { V::Null }
}
/// `HT.polityHead(model, polity)` — 승계표 머리 칩: [구분] › [민족] › [국가 이름] · [꼬리표] …
pub fn polity_head(model: &V, polity: &V) -> Vec<Chip> {
    let p = polity_of(model, polity);
    if !tv(&p) { return Vec::new(); }
    let mut out = Vec::new();
    if tv(&p.get("track")) { out.push(track_chip(model, &p.get("track"), false, V::Undef)); }
    if tv(&p.get("people")) { if let Some(c) = people_chip(model, &p.get("people"), false) { out.push(c); } }
    out.push(Chip { role: "name", text: p.get("name"), uid: p.get("uid"), title: V::Undef, auto: false });
    out.extend(tag_chips(&p.get("tags")));
    out
}
/// `houseOf(model, ref)` — 객체면 그것, 아니면 id · 'house:id' · 이름으로.
fn house_of(model: &V, r: &V) -> V {
    if !tv(model) || !tv(&model.get("houseMap")) { return V::Null; }
    if tv(r) && matches!(r, V::Obj(_)) { return r.clone(); }
    let text = js::to_str(&nn(r.clone(), s(""))).trim();
    let text = if text.as_str().starts_with("house:") { text.slice16(6.0, f64::INFINITY) } else { text };
    let key = V::Str(text);
    let hit = map_get(&model.get("houseMap"), &key);
    if tv(&hit) { return hit; }
    list(&model.get("houses")).into_iter().find(|h| eq(&h.get("name"), &key)).unwrap_or(V::Null)
}
/// `seatSurname(model, h)`의 답 `{ text, uid, field, inherited }`.
struct SeatSurname { text: V, uid: V, inherited: bool }
/// `seatSurname(model, h)` — 가문의 '본관 성씨' 글과 칩(본가 길에서 처음 만나는 seat · surname).
fn seat_surname(model: &V, h: &V) -> Option<SeatSurname> {
    let hm = model.get("houseMap");
    let sh = if tv(&h.get("surname")) { h.clone() } else if tv(&h.get("surnameFrom")) { map_get(&hm, &h.get("surnameFrom")) } else { V::Null };
    if !tv(&sh) { return None; }
    let sn = if tv(&sh.get("surnameId")) && tv(&model.get("surnameMap")) { map_get(&model.get("surnameMap"), &sh.get("surnameId")) } else { V::Null };
    let surname = if tv(&sn) { sn.get("name") } else { sh.get("surname") };
    let seat_house = if tv(&h.get("seat")) { h.clone() } else if tv(&h.get("seatFrom")) { map_get(&hm, &h.get("seatFrom")) } else { V::Null };
    let seat = if tv(&seat_house) { seat_house.get("seat") } else { s("") };
    Some(SeatSurname {
        text: if tv(&seat) { V::from(format!("{} {}씨", t(&seat), t(&surname))) } else { surname },
        uid: if tv(&sn) { sn.get("uid") } else { V::Undef },
        inherited: !eq(&sh, h) || (tv(&seat_house) && !eq(&seat_house, h)),
    })
}
/// `TRACK_FROM`.
fn track_from(k: &V) -> &'static str {
    [("period", "국성으로 삼은 나라에서"), ("leader", "지도자 칸이 든 나라에서"), ("person", "구성원에서"), ("parent", "본가에서")].iter().find(|(id, _)| is(k, id)).map_or("본가에서", |x| x.1)
}
/// `HT.houseHead(model, house)` — 세계표 머리 칩: [구분] › [민족] › [본관 성씨] › [이름] · [꼬리표] … — 짐작한 칩은 auto.
pub fn house_head(model: &V, house: &V) -> Vec<Chip> {
    let h = house_of(model, house);
    if !tv(&h) { return Vec::new(); }
    let more = if tv(&h.get("trackMore")) { format!(" · +{}", t(&h.get("trackMore"))) } else { String::new() };
    let tr = if tv(&h.get("track")) { Some(track_chip(model, &h.get("track"), false, V::Undef)) }
        else if tv(&h.get("trackAuto")) { Some(track_chip(model, &h.get("trackAuto"), true, V::from(format!("짐작 — {}{more}", track_from(&h.get("trackFrom")))))) }
        else { None };
    let mut pe = if tv(&h.get("people")) { people_chip(model, &h.get("people"), false) } else if tv(&h.get("peopleAuto")) { people_chip(model, &h.get("peopleAuto"), true) } else { None };
    if let Some(c) = pe.as_mut() {
        if c.auto { c.title = V::from(format!("짐작 — {}{}", track_from(&h.get("peopleFrom")), if tv(&c.title) { format!(" ({})", t(&c.title)) } else { String::new() })); }
    }
    let ss = seat_surname(model, &h);
    let seat_chip = ss.as_ref().map(|ss| Chip { role: "surname", text: ss.text.clone(), uid: ss.uid.clone(), title: if ss.inherited { s("본가의 본관 성씨") } else { V::Undef }, auto: false });
    let name_chip = if ss.as_ref().is_none_or(|ss| !js::strict_eq(&ss.text, &h.get("name"))) { Some(Chip { role: "name", text: h.get("name"), uid: h.get("uid"), title: V::Undef, auto: false }) } else { None };
    let mut out: Vec<Chip> = [tr, pe, seat_chip, name_chip].into_iter().flatten().collect();
    out.extend(tag_chips(&h.get("tags")));
    out
}

// ── 가문 ──

/// `HT.houseUnder(model, id)` — 그 가문과 아래 파 모두의 id(자기 먼저 · 가문 나무 앞 차례).
pub fn house_under(model: &V, id: &V) -> Vec<V> {
    let h = house_of(model, id);
    if !tv(&h) { return Vec::new(); }
    let mut out: Vec<V> = Vec::new();
    let mut stack = vec![h.get("id")];
    while let Some(k) = stack.pop() {
        if out.iter().any(|x| js::strict_eq(x, &k)) { continue; }
        out.push(k.clone());
        let x = map_get(&model.get("houseMap"), &k);
        let ch = if tv(&x) { list(&x.get("children")) } else { Vec::new() };
        for c in ch.into_iter().rev() { stack.push(c); }
    }
    out
}
/// `HT.houseSpans`의 구간 하나 `{ uid, start, end, open?, real? }`.
#[derive(Clone)]
pub struct HSpan { pub uid: V, pub start: f64, pub end: f64, pub open: bool, pub real: bool }
/// `HT.houseSpans(model, ids, opts)` — 가문 조명 구간(해 단위 · 시작 순): 칸의 가문이 ids에 든 지도자 칸의 기간(맞닿은 칸은 하나로) · 지도자 칸이 없는 나라는 국성이 ids에 들면 나라 기간 ·
/// 내각(실권) 칸은 따로 `real`. `branches`면 ids마다 아래 파까지.
pub fn house_spans(model: &V, ids: &[V], branches: bool) -> Vec<HSpan> {
    if !tv(model) || !tv(&model.get("houseMap")) { return Vec::new(); }
    let want = js::Set::new();
    for r in ids {
        let h = house_of(model, r);
        if !tv(&h) { continue; }
        let under = if branches { house_under(model, &h.get("id")) } else { vec![h.get("id")] };
        for id in under { want.add(id); }
    }
    if want.is_empty() { return Vec::new(); }
    let mut out: Vec<HSpan> = Vec::new();
    let runs = |out: &mut Vec<HSpan>, p: &V, l: &[V], real: bool| {
        let mut cur: Option<usize> = None;
        for (i, c) in l.iter().enumerate() {
            if !(tv(&c.get("houseId")) && want.has(&c.get("houseId"))) || c.get("start").is_nullish() { cur = None; continue; }
            let next = l.get(i + 1);
            let follows = next.is_some_and(|x| tv(x) && !x.get("start").is_nullish() && n(&x.get("start")) > n(&c.get("start")));
            let cs = n(&c.get("start"));
            let fallback = if follows { n(&next.expect("뒤 칸").get("start")) } else { n(&nn(p.get("endY"), c.get("start"))) };
            let end = js::max(&[cs, if c.get("end").is_nullish() { fallback } else { n(&c.get("end")) }]);
            let open = c.get("end").is_nullish() && (tv(&c.get("endUnknown")) || (!follows && !tv(&p.get("ongoing"))));
            match cur {
                Some(k) if out[k].end >= cs - 1e-9 => {
                    if end >= out[k].end { out[k].open = open; }
                    out[k].end = js::max(&[out[k].end, end]);
                }
                _ => { out.push(HSpan { uid: p.get("uid"), start: cs, end, open, real }); cur = Some(out.len() - 1); }
            }
        }
    };
    for p in list(&model.get("periods")) {
        if !is(&item_kind_of(&p), "period") { continue; }
        let l = list(&p.get("leaders"));
        if l.is_empty() {
            if tv(&p.get("houseId")) && want.has(&p.get("houseId")) {
                let st = n(&p.get("start"));
                out.push(HSpan { uid: p.get("uid"), start: st, end: js::max(&[st, n(&nn(p.get("endY"), p.get("start")))]), open: false, real: false });
            }
        } else { runs(&mut out, &p, &l, false); }
        let mut cab = list(&p.get("cabinets"));
        js::sort(&mut cab, |a, b| n(&nn(a.get("start"), V::Num(0.0))) - n(&nn(b.get("start"), V::Num(0.0))));
        runs(&mut out, &p, &cab, true);
    }
    js::sort_by(&mut out, |a, b| { let d = a.start - b.start; if d != 0.0 && !d.is_nan() { d } else { cmp_v(&a.uid, &b.uid) } });
    out
}
/// `(a < b ? -1 : a > b ? 1 : 0)` — 글이면 UTF-16 차례.
pub fn cmp_v(a: &V, b: &V) -> f64 { crate::lay::model::util::cmp_str(a, b) }
/// `HT.houseEras`의 한 줄 `{ uid, name, color, span, cells, real, openCells?, openReal? }`.
#[derive(Clone)]
pub struct Era { pub uid: V, pub name: V, pub color: V, pub span: (f64, f64), pub cells: Vec<(f64, f64)>, pub real: Vec<(f64, f64)>, pub open_cells: Vec<usize>, pub open_real: Vec<usize> }
/// `HT.houseEras(model, id)` — 다스린 기간 막대: 그 가문(과 아래 파)이 다스린 나라마다 한 줄(나라 시작 순).
pub fn house_eras(model: &V, id: &V) -> Vec<Era> {
    let h = house_of(model, id);
    if !tv(&h) { return Vec::new(); }
    let ids = house_under(model, &h.get("id"));
    let want = js::Set::new();
    for x in &ids { want.add(x.clone()); }
    let spans = house_spans(model, &ids, false);
    let mut rows: Vec<Era> = Vec::new();
    for p in list(&model.get("periods")) {
        if !is(&item_kind_of(&p), "period") { continue; }
        let mine: Vec<&HSpan> = spans.iter().filter(|x| js::strict_eq(&x.uid, &p.get("uid"))).collect();
        if mine.is_empty() && !(tv(&p.get("houseId")) && want.has(&p.get("houseId"))) { continue; }
        let lead: Vec<&HSpan> = mine.iter().copied().filter(|x| !x.real).collect();
        let real: Vec<&HSpan> = mine.iter().copied().filter(|x| x.real).collect();
        let st = n(&p.get("start"));
        let open_of = |l: &[&HSpan]| -> Vec<usize> { l.iter().enumerate().filter(|(_, x)| x.open).map(|(i, _)| i).collect() };
        let row = Era {
            uid: p.get("uid"), name: p.get("name"), color: p.get("color"), span: (st, js::max(&[st, n(&nn(p.get("endY"), p.get("start")))])),
            cells: lead.iter().map(|x| (x.start, x.end)).collect(), real: real.iter().map(|x| (x.start, x.end)).collect(),
            open_cells: open_of(&lead), open_real: open_of(&real),
        };
        // rows.set(p.uid, row) — 같은 uid면 자리는 그대로 값만 바뀜
        match rows.iter().position(|r| js::strict_eq(&r.uid, &p.get("uid"))) { Some(k) => rows[k] = row, None => rows.push(row) }
    }
    js::sort_by(&mut rows, |a, b| { let d = a.span.0 - b.span.0; if d != 0.0 && !d.is_nan() { d } else { cmp_v(&a.uid, &b.uid) } });
    rows
}

// ── 계보 뼈대 ──

/// `KIN_TREE_ORDER` · `kinTreeRank(as)` — 나무 부모 차례(표에 없는 자유 글은 맨 뒤).
fn kin_tree_rank(r#as: &V) -> usize {
    const ORDER: [&str; 8] = ["birth-father", "father", "", "adoptive-father", "ancestor", "adoptive-mother", "birth-mother", "mother"];
    let k = or(r#as.clone(), s(""));
    ORDER.iter().position(|x| is(&k, x)).unwrap_or(ORDER.len())
}
/// `KIN_PATERNAL.has(as || '')`.
fn kin_paternal(r#as: &V) -> bool {
    let k = or(r#as.clone(), s(""));
    ["birth-father", "father", "", "adoptive-father", "ancestor"].iter().any(|x| is(&k, x))
}
/// `kinEdgeCode(e)` — 0 실선 · 1 양부 · 양모 · 2 후손 · 추정 · 전승이면 + 4.
fn kin_edge_code(e: &V) -> i32 {
    let a = or(e.get("as"), s(""));
    let adoptive = js::to_str(&a).as_str().starts_with("adoptive-");
    (if adoptive { 1 } else if is(&e.get("as"), "ancestor") { 2 } else { 0 }) + if is(&e.get("certainty"), "estimated") || is(&e.get("certainty"), "legend") { 4 } else { 0 }
}
/// `kinYear(y)` — 빈 값 · 무한은 '', 아니면 `HT.formatAxisYear`.
fn kin_year(y: &V) -> String { if y.is_nullish() || !js::to_num(y).is_finite() { String::new() } else { format_axis_year(y) } }
/// `kinSub(n)` — 사람의 짧은 곁글: 지도자면 '3대 · 1418~1450', 아니면 생몰 '1402~', 둘 다 없으면 직함.
fn kin_sub(nd: &V) -> V {
    if let Some(lc) = list(&nd.get("cells")).into_iter().find(|x| is(&x.get("kind"), "leader")) {
        let c = lc.get("c");
        let ord = if c.get("ordinal").is_nullish() { String::new() } else { format!("{}대 · ", t(&c.get("ordinal"))) };
        return V::from(format!("{ord}{}~{}", kin_year(&c.get("start")), kin_year(&c.get("end"))));
    }
    let f = nd.get("figure");
    if tv(&f) && (!f.get("birth").is_nullish() || !f.get("death").is_nullish()) { return V::from(format!("{}~{}", kin_year(&f.get("birth")), kin_year(&f.get("death")))); }
    if tv(&f) && tv(&f.get("role")) { f.get("role") } else { s("") }
}

/// 뼈대의 파 하나 `{ uid, name, color, at, up }`.
#[derive(Clone)]
pub struct Branch { pub uid: V, pub name: V, pub color: V, pub at: i32, pub up: i32 }
/// 계보 뼈대(`HT.kinSkeleton`의 값) — 정수 열은 JS의 Int32Array(쓸 때 `ToInt32`). `color2`는 두 나라 지도자가 없으면 빈 열. `people` · `index`는 열거되지 않는 덧칸.
pub struct Skel {
    pub uid: String, pub n: usize, pub gens: i32,
    pub par: Vec<i32>, pub size: Vec<i32>, pub gen: Vec<i32>, pub bits: Vec<i32>, pub edge: Vec<i32>, pub branch: Vec<i32>, pub color: Vec<i32>, pub color2: Vec<i32>,
    pub name: Vec<V>, pub sub: Vec<V>, pub key: Vec<V>, pub extra: Vec<i32>, pub colors: Vec<V>, pub branches: Vec<Branch>,
    pub cells: Vec<(Str, i32)>, pub warnings: Vec<String>, pub people: Vec<V>, index: HashMap<Str, usize>,
}
impl Skel {
    /// `skel.index.get(key)`(안정 열쇠 → 번호 — 같은 열쇠면 뒤의 것).
    pub fn index_of(&self, key: &V) -> Option<usize> { if let V::Str(k) = key { self.index.get(k).copied() } else { None } }
    /// `skel.cells[key]`.
    pub fn cell(&self, key: &str) -> Option<i32> { self.cells.iter().find(|(k, _)| k == key).map(|x| x.1) }
}
/// `kinStore(model)` — 모델마다 한 번 짓고 두는 기억(`groups` · `skel`).
#[derive(Default)]
pub struct KinCache { groups: Option<HashMap<Str, Vec<V>>>, skel: HashMap<String, Option<Rc<Skel>>> }
/// `kinGroups(model)` — 사람 자리를 뼈대 열쇠(kinKey)로 묶음(사람 차례).
fn kin_groups<'a>(cache: &'a mut KinCache, model: &V) -> &'a HashMap<Str, Vec<V>> {
    cache.groups.get_or_insert_with(|| {
        let mut g: HashMap<Str, Vec<V>> = HashMap::new();
        for nd in list(&model.get("persons")) {
            let k = nd.get("kinKey");
            if tv(&k) { g.entry(js::to_str(&k)).or_default().push(nd.clone()); }
        }
        g
    })
}
/// `HT.kinSkeleton(model, key)` — 'kin:<뿌리 가문 id>' | 'kin:polity:<정권 uid>' → 뼈대(없으면 None). 모델마다 기억한다.
pub fn kin_skeleton(cache: &mut KinCache, model: &V, key: &str) -> Option<Rc<Skel>> {
    if !tv(model) || !tv(&model.get("persons")) { return None; }
    if let Some(s) = cache.skel.get(key) { return s.clone(); }
    let sk = kin_build(cache, model, key).map(Rc::new);
    cache.skel.insert(key.to_string(), sk.clone());
    sk
}
/// `/^kin:polity:(.+)$/` · `/^kin:(.+)$/`의 (.+) — 비지 않고 줄 끝 글자가 없어야 한다(JS `.`).
fn tail_of<'a>(key: &'a str, head: &str) -> Option<&'a str> {
    key.strip_prefix(head).filter(|r| !r.is_empty() && !r.chars().any(|c| matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}')))
}
/// `kinBuild(model, key)` — 뼈대 짓기(① 노드 ② 위상 차례 · 나무 부모 ③ 차례 열쇠 ④ 앞 차례 ⑤ 파 ⑥ 비트 · 파 · 색 · 글 · 안정 열쇠 · 칸 · 덧선).
fn kin_build(cache: &mut KinCache, model: &V, key: &str) -> Option<Skel> {
    let pm = tail_of(key, "kin:polity:");
    let hm = if pm.is_some() { None } else { tail_of(key, "kin:") };
    let root = match hm { Some(id) if tv(&model.get("houseMap")) => or(map_get(&model.get("houseMap"), &s(id)), V::Null), _ => V::Null };
    let members: Vec<V> = kin_groups(cache, model).get(&Str::from(key)).cloned().unwrap_or_default();
    if !tv(&root) && !(pm.is_some() && !members.is_empty()) { return None; }
    /* ① 노드(번호 = 구성원 → 부계의 빈 고리 → 가문 밖 잎 차례) */
    let mut lst: Vec<V> = members.clone();
    let persons = list(&model.get("persons"));
    // 사람 자리의 모델 차례(seq) → 노드 번호. seq는 모델이 늘 0 ~ n−1의 정수로 둔다 — 아니면(JS `loc[undefined]`는 Int32Array 밖의 속성에 적고 읽어 다른 뼈대가 된다)
    // 조용히 다른 답을 내지 않게 잘못으로(과제 Y — 갈래 D 걱정 1 ⑥). 끝의 덧칸 하나는 그런 seq가 닿는 자리(뼈대는 버린다).
    let mut loc: Vec<i32> = vec![-1; persons.len() + 1];
    let bad_seq = std::cell::Cell::new(false);
    let seq = |nd: &V| -> usize {
        match nd.get("seq") { V::Num(x) if x >= 0.0 && x.fract() == 0.0 && (x as usize) < persons.len() => x as usize, _ => { bad_seq.set(true); persons.len() } }
    };
    for (k, nd) in lst.iter().enumerate() { loc[seq(nd)] = k as i32; }
    let m = lst.len();
    for k in 0..m {
        for e in list(&lst[k].get("parents")) {
            let nd = e.get("node");
            if loc[seq(&nd)] < 0 && tv(&nd.get("unknown")) && kin_paternal(&e.get("as")) { loc[seq(&nd)] = lst.len() as i32; lst.push(nd); }
        }
    }
    let u = lst.len();
    for k in 0..m {
        for c in list(&lst[k].get("children")) {
            let nd = c.get("node");
            if loc[seq(&nd)] < 0 { loc[seq(&nd)] = lst.len() as i32; lst.push(nd); }
        }
    }
    let nn_ = lst.len();
    let role_of = |k: usize| if k < m { 1 } else if k < u { 2 } else { 3 };
    /* ② 위상 차례 — 나무 부모(차례가 가장 앞)와 덧선. 고리를 만드는 선은 버리고 경고 */
    let mut warnings: Vec<String> = Vec::new();
    let mut indeg = vec![0i32; nn_];
    for k in 0..nn_ { for e in list(&lst[k].get("parents")) { if loc[seq(&e.get("node"))] >= 0 { indeg[k] += 1; } } }
    let mut done = vec![false; nn_];
    let mut tree = vec![-1i32; nn_];
    let mut tree_edge: Vec<V> = vec![V::Null; nn_];
    let mut ex_local: Vec<i32> = Vec::new();
    let mut queue: Vec<usize> = Vec::with_capacity(nn_);
    for (k, d) in indeg.iter().enumerate() { if *d == 0 { queue.push(k); } }
    let (mut head, mut scan, mut count) = (0usize, 0usize, 0usize);
    while count < nn_ {
        if head >= queue.len() {
            while done[scan] { scan += 1; }
            queue.push(scan);
        }
        let k = queue[head];
        head += 1;
        if done[k] { continue; }
        done[k] = true;
        count += 1;
        let nd = lst[k].clone();
        let (mut best, mut best_p, mut best_r) = (V::Null, -1i32, 99usize);
        let parents = list(&nd.get("parents"));
        for e in &parents {
            let p = loc[seq(&e.get("node"))];
            if p < 0 { continue; }
            if !done[p as usize] || p as usize == k {
                warnings.push(format!("{}의 부모 {}: 혈연이 고리를 이뤄 이 선을 끊었습니다.", t(&nd.get("name")), t(&e.get("node").get("name"))));
                continue;
            }
            let r = kin_tree_rank(&e.get("as"));
            if r < best_r { best_r = r; best = e.clone(); best_p = p; }
        }
        if tv(&best) {
            tree[k] = best_p;
            tree_edge[k] = best.clone();
            for e in &parents {
                if eq(e, &best) { continue; }
                let p = loc[seq(&e.get("node"))];
                if p < 0 || !done[p as usize] || p as usize == k { continue; }
                ex_local.extend([p, k as i32, kin_edge_code(e), js::to_i32(n(&or(e.get("gen"), V::Num(1.0))))]);
            }
        }
        for c in list(&nd.get("children")) {
            let q = loc[seq(&c.get("node"))];
            if q >= 0 && !done[q as usize] {
                indeg[q as usize] -= 1;
                if indeg[q as usize] == 0 { queue.push(q as usize); }
            }
        }
    }
    /* ③ 차례 열쇠 (order, 생년, 첫 칸 시작, 모델 차례) — 없는 값은 맨 뒤 */
    let mut k_order = vec![f64::INFINITY; nn_];
    let mut k_birth = vec![f64::INFINITY; nn_];
    let mut k_cell = vec![f64::INFINITY; nn_];
    let mut k_seq = vec![f64::INFINITY; nn_];
    for k in 0..nn_ {
        let nd = &lst[k];
        let f = nd.get("figure");
        let c0 = list(&nd.get("cells")).first().cloned().unwrap_or(V::Undef);
        k_order[k] = match f.get("order") { V::Num(x) if tv(&f) && x.is_finite() && x == x.trunc() => x, _ => f64::INFINITY };
        k_birth[k] = if tv(&f) && !f.get("birth").is_nullish() && js::to_num(&f.get("birth")).is_finite() { js::to_num(&f.get("birth")) } else { f64::INFINITY };
        k_cell[k] = if tv(&c0) && !c0.get("c").get("start").is_nullish() && js::to_num(&c0.get("c").get("start")).is_finite() { js::to_num(&c0.get("c").get("start")) } else { f64::INFINITY };
        k_seq[k] = js::to_num(&nn(nd.get("seq"), V::Num(f64::INFINITY)));
    }
    /* 두 값이 모두 Infinity면 빼기가 NaN — 거짓이라 다음 열쇠로 */
    let pick = |d: f64| d != 0.0 && !d.is_nan();
    let cmp = |a: usize, b: usize| -> f64 {
        for d in [k_order[a] - k_order[b], k_birth[a] - k_birth[b], k_cell[a] - k_cell[b], k_seq[a] - k_seq[b]] { if pick(d) { return d; } }
        a as f64 - b as f64
    };
    /* 자식 목록(CSR): 조각 g = 나무 부모 + 1(뿌리는 0번 조각) */
    let mut kid = vec![0usize; nn_ + 2];
    for k in 0..nn_ { kid[(tree[k] + 2) as usize] += 1; }
    for g in 1..=nn_ + 1 { kid[g] += kid[g - 1]; }
    let mut fill = kid.clone();
    let mut kid_arr = vec![0usize; nn_];
    for k in 0..nn_ { let g = (tree[k] + 1) as usize; kid_arr[fill[g]] = k; fill[g] += 1; }
    for g in 0..=nn_ {
        if kid[g + 1] - kid[g] > 1 {
            // 비교가 전순서(마지막 열쇠가 번호)라 어느 정렬로도 같은 차례
            kid_arr[kid[g]..kid[g + 1]].sort_by(|&a, &b| cmp(a, b).partial_cmp(&0.0).expect("비교"));
        }
    }
    /* ④ 앞 차례 */
    let mut ord: Vec<usize> = Vec::with_capacity(nn_);
    let mut stack: Vec<usize> = Vec::with_capacity(nn_);
    for j in (kid[0]..kid[1]).rev() { stack.push(kid_arr[j]); }
    while let Some(k) = stack.pop() {
        ord.push(k);
        for j in (kid[k + 1]..kid[k + 2]).rev() { stack.push(kid_arr[j]); }
    }
    let mut pre = vec![0i32; nn_];
    for (i, &k) in ord.iter().enumerate() { pre[k] = i as i32; }
    let (mut par, mut size, mut gen, mut bits, mut edge, mut branch, mut color, mut color2) =
        (vec![0i32; nn_], vec![1i32; nn_], vec![0i32; nn_], vec![0i32; nn_], vec![0i32; nn_], vec![0i32; nn_], vec![0i32; nn_], vec![0i32; nn_]);
    let mut name: Vec<V> = vec![V::Undef; nn_];
    let mut sub: Vec<V> = vec![V::Undef; nn_];
    let mut skey: Vec<V> = vec![V::Undef; nn_];
    let mut people: Vec<V> = vec![V::Undef; nn_];
    for i in 0..ord.len() {
        let k = ord[i];
        par[i] = if tree[k] < 0 { -1 } else { pre[tree[k] as usize] };
        let e = &tree_edge[k];
        gen[i] = if par[i] < 0 { 0 } else {
            let step = if is(&e.get("as"), "ancestor") { n(&or(e.get("gen"), V::Num(1.0))) } else { 1.0 };
            js::to_i32(f64::from(gen[par[i] as usize]) + step)
        };
        edge[i] = if tv(e) { kin_edge_code(e) } else { 0 };
        people[i] = lst[k].clone();
    }
    for i in (1..nn_).rev() { if par[i] >= 0 { let p = par[i] as usize; size[p] += size[i]; } }
    /* ⑤ 파(가문 나무 — 뿌리 가문이 0번) */
    let mut branches: Vec<Branch> = Vec::new();
    let branch_at = Map::new();
    let founders = Map::new();
    if tv(&root) {
        for (b, id) in house_under(model, &root.get("id")).into_iter().enumerate() {
            let h = map_get(&model.get("houseMap"), &id);
            // JS `h.uid` — 아래 파의 id가 가문 표에 없으면(undefined) TypeError(과제 Y — 갈래 D 걱정 1 ③)
            if h.is_nullish() { fault(format!("계보 뼈대 {key} — 아래 파 {}가 가문 표에 없습니다(JS라면 h.uid에서 TypeError)", t(&id))); return None; }
            branch_at.set(id.clone(), b as f64);
            let pid = h.get("parentId");
            branches.push(Branch { uid: h.get("uid"), name: h.get("name"), color: h.get("color"), at: -1, up: if tv(&pid) && branch_at.has(&pid) { js::to_i32(n(&branch_at.get(&pid))) } else { -1 } });
            let fnode = h.get("founderNode");
            if b > 0 && tv(&fnode) { founders.set(fnode, b as f64); }
        }
    }
    /* ⑥ 비트 · 파 · 색 · 글 · 안정 열쇠 · 칸 */
    let mut colors: Vec<V> = vec![s("")];
    let color_at = Map::new();
    color_at.set(s(""), 0.0);
    let color_idx = |c: &V, colors: &mut Vec<V>| -> i32 {
        let sv = or(c.clone(), s(""));
        let v = color_at.get(&sv);
        if v.is_undef() { let at = colors.len(); color_at.set(sv.clone(), at as f64); colors.push(sv); at as i32 } else { js::to_i32(n(&v)) }
    };
    let mut cell_list: Vec<(Str, i32)> = Vec::new();
    let mut two = false;
    let root_founder = if tv(&root) { root.get("founderNode") } else { V::Null };
    for i in 0..ord.len() {
        let nd = people[i].clone();
        let r = role_of(ord[i]);
        let mut b = 0i32;
        if r == 1 { b |= 1; }
        if tv(&nd.get("unknown")) { b |= 2; }
        if tv(&nd.get("missing")) { b |= 4; }
        let fb = founders.get(&nd);
        if !fb.is_undef() {
            b |= 16;
            let fi = n(&fb) as usize;
            if branches[fi].at < 0 { branches[fi].at = i as i32; }
        }
        if js::strict_eq(&root_founder, &nd) && !branches.is_empty() && branches[0].at < 0 { branches[0].at = i as i32; } // 뿌리 가문의 시조 자리
        let fg = nd.get("figure");
        if tv(&fg) && matches!(fg.get("lineageOnly"), V::Bool(true)) { b |= 64; }
        let (mut p0, mut p1) = (V::Null, V::Null);
        for x in list(&nd.get("cells")) {
            if !is(&x.get("kind"), "leader") { continue; }
            if !tv(&p0) { p0 = x.get("p"); } else if !tv(&p1) && !eq(&x.get("p"), &p0) { p1 = x.get("p"); }
            cell_list.push((Str::from(format!("{}|{}", t(&x.get("p").get("uid")), t(&x.get("ref")))), i as i32));
        }
        if tv(&p0) {
            b |= 32;
            color[i] = color_idx(&p0.get("color"), &mut colors);
            if tv(&p1) {
                b |= 256;
                two = true;
                color2[i] = color_idx(&p1.get("color"), &mut colors);
            }
        }
        bits[i] = b;
        branch[i] = if !tv(&root) { -1 }
            else if r == 1 && tv(&nd.get("houseId")) && branch_at.has(&nd.get("houseId")) { js::to_i32(n(&branch_at.get(&nd.get("houseId")))) }
            else if par[i] >= 0 { branch[par[i] as usize] } else { 0 };
        name[i] = if tv(&nd.get("unknown")) { s("미상") } else { nd.get("name") };
        sub[i] = if tv(&nd.get("unknown")) { s("") } else { kin_sub(&nd) };
        skey[i] = nd.get("key");
    }
    /* 빈 고리(u:…)는 '<자식 열쇠>^<그 자식의 부모 줄 번호>' */
    for i in 0..ord.len() {
        let nd = &people[i];
        let k = js::to_str(&nd.get("key"));
        if k.code_at(0.0) != 117.0 || k.code_at(1.0) != 58.0 { continue; } // 'u:'
        let ch = list(&nd.get("children"));
        let c = ch.first().map_or(V::Undef, |x| if tv(x) { x.get("node") } else { x.clone() });
        skey[i] = if tv(&c) {
            let at = list(&c.get("parents")).iter().position(|e| eq(&e.get("node"), nd)).map_or(-1.0, |j| j as f64);
            V::from(format!("{}^{}", t(&c.get("key")), js::num_str(at)))
        } else { nd.get("key") };
    }
    /* 덧선 — 앞 차례 번호로 · (to, from, 갈래, gen) 오름 · 옆구리 비트 */
    let mut quads: Vec<[i32; 4]> = ex_local.chunks(4).map(|q| [pre[q[0] as usize], pre[q[1] as usize], q[2], q[3]]).collect();
    quads.sort_by(|a, b| (a[1], a[0], a[2], a[3]).cmp(&(b[1], b[0], b[2], b[3])));
    let mut extra: Vec<i32> = Vec::with_capacity(quads.len() * 4);
    for q in &quads { extra.extend(q); bits[q[1] as usize] |= 8; }
    let gens = gen.iter().fold(0, |g, &x| if x + 1 > g { x + 1 } else { g });
    // cellList.sort((a, b) => a[1] - b[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    js::sort_by(&mut cell_list, |a, b| { let d = f64::from(a.1 - b.1); if d != 0.0 { d } else { match a.0.cmp16(&b.0) { std::cmp::Ordering::Less => -1.0, std::cmp::Ordering::Greater => 1.0, _ => 0.0 } } });
    // cells = {} — 같은 열쇠는 뒤의 값으로(자리는 처음)
    let mut cells: Vec<(Str, i32)> = Vec::new();
    for (k, v) in cell_list { match cells.iter_mut().find(|x| x.0 == k) { Some(x) => x.1 = v, None => cells.push((k, v)) } }
    let mut index = HashMap::new();
    for (i, k) in skey.iter().enumerate() { index.insert(js::to_str(k), i); } // new Map(skey.map((s, i) => [s, i])) — 같은 열쇠는 뒤의 것
    if bad_seq.get() { fault(format!("계보 뼈대 {key} — 모델 차례(seq)가 0 ~ {}의 정수가 아닌 사람 자리가 있습니다", persons.len() as i64 - 1)); return None; }
    Some(Skel {
        uid: key.to_string(), n: nn_, gens, par, size, gen, bits, edge, branch, color, color2: if two { color2 } else { Vec::new() },
        name, sub, key: skey, extra, colors, branches, cells, warnings, people, index,
    })
}
/// `HT.kinOf(model, polity, i)` — 정권의 지도자 칸 i → (뼈대 열쇠, 그 사람의 앞 차례 번호)(없으면 None).
pub fn kin_of(cache: &mut KinCache, model: &V, p: &V, i: usize) -> Option<(String, i32)> {
    if !tv(p) { return None; }
    let nd = person_of(model, p, Some(&format!("leader:{i}")));
    if !tv(&nd) || !tv(&nd.get("kinKey")) { return None; }
    let sk = kin_skeleton(cache, model, &t(&nd.get("kinKey")))?;
    let at = sk.cell(&format!("{}|leader:{i}", t(&p.get("uid"))))?;
    Some((sk.uid.clone(), at))
}
/// `HT.kinOfPerson(model, person)` — 사람 자리 열쇠('f:…') → (뼈대 열쇠, 번호) — 그 사람이 구성원으로 든 뼈대(없으면 None).
pub fn kin_of_person(cache: &mut KinCache, model: &V, person: &str) -> Option<(String, usize)> {
    let nd = if tv(&model.get("personIndex")) { map_get(&model.get("personIndex"), &s(person)) } else { V::Null };
    if !tv(&nd) || !tv(&nd.get("kinKey")) { return None; }
    let sk = kin_skeleton(cache, model, &t(&nd.get("kinKey")))?;
    let at = sk.index_of(&nd.get("key"))?;
    Some((sk.uid.clone(), at))
}
/// 모델 Map의 has(값).
pub fn has_in(m: &V, k: &V) -> bool { map_has(m, k) }

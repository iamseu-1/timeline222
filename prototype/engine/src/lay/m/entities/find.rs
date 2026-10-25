//! `entities.mjs` 1201 ~ 1311줄 — 찾을 글 `x_find`(js/viewer.js runSearch의 찾을 글을 그대로 옮긴 것 — `findOf`) · `spanOfMinutes` · `dropBytes`.
//! hay: 소문자 · 이름 · 제목 · 설명은 뺀다. cells: 칸 참조 → 그 칸의 찾을 글. sub · span · color · row: 단체 · 제도의 결과 줄 곁글 · 기간(분) · 색 · 줄을 빌릴 정권 uid.
use super::web::{historicity_name, historicity_of, kind_name, map_get, names_text, signers_text, treaty_type_name, CELL_KIND_IDS};
use super::Cx;
use crate::lay::js::{self, Map, Obj, Str, V};
use crate::lay::link::place_of;
use crate::lay::model::bounds::cells_of;
use crate::lay::model::util::{is, list, or, s, t, tv};
use crate::lay::read::treaty;

/// `join(parts)` — 칸을 ' '로 잇고 빈칸 덩이를 하나로 줄여 다듬은 뒤 소문자로(`parts.map(str).join(' ').replace(/\s+/g, ' ').trim().toLowerCase()`).
fn join(parts: &[V]) -> String {
    let joined: Vec<Str> = parts.iter().map(|v| if v.is_nullish() { Str::default() } else { js::to_str(v) }).collect();
    let all = Str::join(&joined, " ");
    // /\s+/g → ' ' (JS 빈칸 — 줄 끝 · U+FEFF 포함)
    let u = all.to_units();
    let mut out: Vec<u16> = Vec::with_capacity(u.len());
    let mut in_space = false;
    for &c in &u {
        let space = char::from_u32(u32::from(c)).is_some_and(js::is_space);
        if space { if !in_space { out.push(0x20); } in_space = true; } else { out.push(c); in_space = false; }
    }
    let squeezed = Str::from_units(&out).trim();
    to_lower(&squeezed)
}
/// JS `toLowerCase()` — 유니코드 소문자(로캘 없이). 외톨이 서로게이트는 그대로.
fn to_lower(text: &Str) -> String {
    match text.exact() {
        Some(x) => lower_js(x),
        None => text.as_str().into_owned(), // 외톨이 서로게이트가 든 글(정답지 자료에 없음)
    }
}
/// `String.prototype.toLowerCase` — Rust `to_lowercase`는 그리스 대문자 시그마(Σ)의 끝 꼴 규칙까지 JS와 같다(둘 다 유니코드 SpecialCasing의 Final_Sigma).
fn lower_js(x: &str) -> String { x.to_lowercase() }

/// `findOf(ctx)` — 항목 uid → 찾을 글 `{ hay, cells?, sub?, span?, color?, row? }`(Map).
pub(super) fn find_of(cx: &Cx) -> Map {
    let model = &cx.model;
    let found = Map::new();
    let track_name = |id: &V| -> V {
        let tr = map_get(&model.get("trackMap"), id);
        let tr = if tv(&tr) { tr } else { V::Obj({ let o = Obj::new(); o.set("name", id.clone()); o }) };
        or(tr.get("name"), s(""))
    };
    let names = |l: &V| -> V { s(&names_text(l)) };
    let treaty_hay = |x: &V| -> String {
        let tr = if tv(x) && tv(&x.get("treaty")) { treaty::read_treaty(cx.w.rc, &x.get("treaty"), &mut |_| {}).map_or(V::Obj(Obj::new()), V::Obj) } else { V::Null };
        if !tv(&tr) { return String::new(); }
        let refs = { let r = x.get("treatyRefs"); if tv(&r) { or(r.get("parties"), js::Arr::default().into()) } else { js::Arr::default().into() } };
        let mut parts: Vec<V> = vec![s("조약"), s(treaty_type_name(&tr.get("type"))), tr.get("formal"), tr.get("place"), s(&list(&tr.get("languages")).iter().map(|v| if v.is_nullish() { String::new() } else { t(v) }).collect::<Vec<_>>().join(" "))];
        parts.extend(list(&tr.get("parties")).iter().map(|p| s(&format!("{} {} {}", t(&or(p.get("polity"), s(""))), t(&or(p.get("role"), s(""))), signers_text(&p.get("signatories"))))));
        parts.extend(list(&refs).iter().map(|r| r.get("name")));
        parts.extend(list(&tr.get("articles")).iter().map(|a| s(&format!("{} {}", t(&or(a.get("no"), s(""))), t(&or(a.get("title"), s("")))))));
        parts.into_iter().filter(tv).map(|v| t(&v)).collect::<Vec<_>>().join(" ")
    };
    let put = |x: &V, o: Obj| {
        for k in o.keys() {
            let v = o.get(&k);
            let empty = v.is_nullish() || matches!(&v, V::Str(t) if t.is_empty()) || matches!(&v, V::Obj(q) if q.is_empty()) || matches!(&v, V::Map(_) | V::Set(_));
            if empty { o.delete(&k); }
        }
        if !o.is_empty() { found.set(x.get("uid"), o); }
    };
    /* 시대 · 사건(state.visible): 이름 · 설명 · 태그 · 날짜 · 트랙 · 관점 · 민족 · 종류 · 소속 · 조약 · 실재성 · 이름 목록 · 장소 */
    let item = |x: &V| -> Vec<V> {
        let hist = historicity_of(x);
        vec![
            s(&list(&x.get("tags")).iter().map(|v| if v.is_nullish() { String::new() } else { t(v) }).collect::<Vec<_>>().join(" ")), x.get("date"), track_name(&x.get("track")),
            s(&list(&x.get("perspectives")).iter().map(|v| format!("{} {}", t(&or(v.get("title"), s(""))), t(&or(v.get("description"), s(""))))).collect::<Vec<_>>().join(" ")),
            or(or(x.get("peopleName"), x.get("people")), s("")),
            if tv(&x.get("polityKind")) && !is(&x.get("polityKind"), "state") { s(kind_name(&x.get("polityKind"))) } else { s("") },
            or(x.get("partOfName"), s("")),
            s(&treaty_hay(x)),
            if !hist.is_empty() { s(historicity_name(&V::Str(hist))) } else { s("") }, or(x.get("historicityNote"), s("")),
            names(&x.get("names")), or(x.get("place"), s("")),
        ]
    };
    for x in list(&model.get("periods")) {
        let o = Obj::new();
        o.set("hay", join(&item(&x)));
        // 칸(HT.CELL_KINDS의 모든 종류 — x.kind === 'period'만): 이름 · 묘호 · 시호 · 이름 · 도시 · 시기 이름 · 묶음 · 메모 · 이름 목록 · 도읍의 지명 원어
        if is(&x.get("kind"), "period") {
            let cells = Obj::new();
            for k in CELL_KIND_IDS {
                for (i, c) in cells_of(&x, k).iter().enumerate() {
                    if !tv(c) { continue; }
                    let place = if k == "capital" { let pl = place_of(model, &c.get("city")); names(&if tv(&pl) { pl.get("names") } else { V::Undef }) } else { s("") };
                    let hay = join(&[c.get("name"), c.get("temple"), c.get("title"), c.get("given"), c.get("city"), c.get("label"), c.get("group"), c.get("note"), names(&c.get("names")), place]);
                    if !hay.is_empty() { cells.set(format!("{k}:{i}").as_str(), hay); }
                }
            }
            o.set("cells", cells);
        }
        put(&x, o);
    }
    for e in list(&model.get("events")) { let o = Obj::new(); o.set("hay", join(&item(&e))); put(&e, o); }
    let joined = |l: &V| s(&list(l).iter().map(|v| if v.is_nullish() { String::new() } else { t(v) }).collect::<Vec<_>>().join(" "));
    /* 인물: 다른 이름 · 역할 · 가문 · 태그 · 트랙 · 섬긴 정권(이름 · 직함 · 메모) · 이름 목록 */
    for f in list(&model.get("figures")) {
        let svc = list(&f.get("services")).iter().map(|sv| format!("{} {} {}", t(&or(sv.get("polityName"), s(""))), t(&or(sv.get("office"), s(""))), t(&or(sv.get("note"), s(""))))).collect::<Vec<_>>().join(" ");
        let o = Obj::new();
        o.set("hay", join(&[joined(&f.get("aka")), f.get("role"), f.get("house"), joined(&f.get("tags")), track_name(&f.get("track")), s(&svc), names(&f.get("names"))]));
        put(&f, o);
    }
    /* 계보 전용 인물(D1): 같은 찾을 글(활동 기록은 뺌) · 결과 줄 곁글 '계보 전용 · <가문 · 파 이름>'(가문이 없으면 '계보 전용') */
    for f in list(&model.get("lineageFigures")) {
        let nd = super::people::person_of(model, &f, None);
        let hid = or(or(if tv(&nd) { nd.get("houseId") } else { V::Undef }, f.get("houseId")), s(""));
        let h = if tv(&hid) && tv(&model.get("houseMap")) { map_get(&model.get("houseMap"), &hid) } else { V::Undef };
        let o = Obj::new();
        o.set("hay", join(&[joined(&f.get("aka")), f.get("role"), f.get("house"), joined(&f.get("tags")), track_name(&f.get("track")), names(&f.get("names"))]));
        o.set("sub", if tv(&h) { format!("계보 전용 · {}", t(&or(h.get("name"), h.get("id")))) } else { "계보 전용".to_string() });
        put(&f, o);
    }
    /* 시대 구분: 메모 · 트랙 이름 */
    for ep in list(&model.get("epochs")) { let o = Obj::new(); o.set("hay", join(&[ep.get("note"), ep.get("trackName")])); put(&ep, o); }
    /* 대범위: 표시 이름 · 메모 · 트랙 이름 · '대범위' · 구성 정권 이름 */
    for sc in list(&model.get("scopes")) {
        let o = Obj::new();
        let members = list(&sc.get("members")).iter().map(|m| { let nm = m.get("name"); if nm.is_nullish() { String::new() } else { t(&nm) } }).collect::<Vec<_>>().join(" ");
        o.set("hay", join(&[sc.get("label"), sc.get("note"), sc.get("trackName"), s("대범위"), s(&members)]));
        put(&sc, o);
    }
    /* 가문: 성 · 본관 · 시조 · 이름 목록 · 성씨 사전의 이름 목록 */
    for h in list(&model.get("houses")) {
        let sn = if tv(&model.get("surnameMap")) { map_get(&model.get("surnameMap"), &h.get("surnameId")) } else { V::Undef };
        let o = Obj::new();
        o.set("hay", join(&[h.get("surname"), h.get("seat"), h.get("founder"), names(&h.get("names")), names(&if tv(&sn) { sn.get("names") } else { V::Undef })]));
        put(&h, o);
    }
    /* 단체: 종류 · '단체' · 메모 · 있던 나라 · 구성 나라 · 구성원 · 이름 목록 / 결과 줄 곁글 '단체 · 종류' */
    for g in list(&model.get("groups")) {
        let rows: Vec<V> = list(&g.get("withinList")).into_iter().chain(list(&g.get("memberList"))).collect();
        let row_names = rows.iter().map(|r| { let nm = r.get("name"); if nm.is_nullish() { String::new() } else { t(&nm) } }).collect::<Vec<_>>().join(" ");
        let people = list(&g.get("peopleList")).iter().map(|r| format!("{} {}", t(&r.get("name")), if tv(&r.get("person")) { t(&r.get("person").get("name")) } else { String::new() })).collect::<Vec<_>>().join(" ");
        let o = Obj::new();
        o.set("hay", join(&[g.get("typeName"), s("단체"), g.get("note"), s(&row_names), s(&people), names(&g.get("names"))]));
        o.set("sub", format!("단체{}", if tv(&g.get("typeName")) { format!(" · {}", t(&g.get("typeName"))) } else { String::new() }));
        o.set("span", span_of_minutes(&g.get("start"), &g.get("endY")));
        o.set("color", or(g.get("color"), s("")));
        o.set("row", or(g.get("polityUid"), s("")));
        put(&g, o);
    }
    /* 제도: '제도' · 갈래 · 칸 이름 · 칸 메모 · 이름 목록 · 주제의 이름 목록 / 결과 줄 곁글 '제도 · 갈래' */
    for it in list(&model.get("institutions")) {
        let spans = list(&it.get("spanList")).iter().map(|sp| format!("{} {}", t(&sp.get("name")), t(&or(sp.get("note"), s(""))))).collect::<Vec<_>>().join(" ");
        let th = if tv(&model.get("themeMap")) { map_get(&model.get("themeMap"), &it.get("themeId")) } else { V::Undef };
        let o = Obj::new();
        o.set("hay", join(&[s("제도"), it.get("family"), s(&spans), names(&it.get("names")), names(&if tv(&th) { th.get("names") } else { V::Undef })]));
        o.set("sub", format!("제도{}", if tv(&it.get("family")) { format!(" · {}", t(&it.get("family"))) } else { String::new() }));
        o.set("span", span_of_minutes(&it.get("start"), &it.get("endY")));
        o.set("color", or(it.get("color"), s("")));
        o.set("row", or(it.get("polityUid"), s("")));
        put(&it, o);
    }
    found
}

/// `spanOfMinutes(a, b)` — 구간 [a, b] → [분, 분](뒤집히면 앞쪽으로 맞춤). 시작이 없으면 null.
pub(super) fn span_of_minutes(a: &V, b: &V) -> V { super::span_of(a, b) }

/// `dropBytes(v)` — 그림 · 글꼴의 바이트(데이터 URL)는 싣지 않고 크기만 `{"$bytes": 글자 수}`(제자리에서 바꾼다).
pub(super) fn drop_bytes(v: V) -> V {
    match &v {
        V::Str(x) => {
            let u = x.to_units();
            let data = u.len() >= 5 && u[..5].iter().zip("data:".encode_utf16()).all(|(a, b)| *a < 128 && (*a as u8).to_ascii_lowercase() as u16 == b);
            if data { let o = Obj::new(); o.set("$bytes", x.len16() as f64); V::Obj(o) } else { v }
        }
        V::Arr(a) => crate::lay::m::entities::web::va(a.to_vec().into_iter().map(drop_bytes).collect()),
        V::Obj(o) => { for k in o.keys() { let x = o.get(&k); o.set(&k, drop_bytes(x)); } v }
        _ => v,
    }
}

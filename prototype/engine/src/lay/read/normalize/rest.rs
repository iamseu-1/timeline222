//! `HT.normalizePack` 안의 문서 · 영토 — 4969 ~ 5064줄(과제 5c).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 4969 ~ 4981줄 문서(`{ "문서 키": "본문" }` — 키 꼴은 `HT.docKey.valid` · `read::docs::doc_key_valid`)
//! - 4983 ~ 5064줄 영토(지도 — 단위 · 조각 지명 기록 · 지도 전용 정권 · 소유 기록). '진행 중'의 끝은 `HT.CURRENT_YEAR + 1`(→ `Ctx::current_year` — 얹힌 몫 5c-6).
//!   id 검사 `/["'\\/]/`는 손으로(`bad_id_char`). `t.generate`(내장 팩 전용 함수 — JSON으로는 오지 않음)는 옮기지 않는다.
use super::Norm;
use crate::lay::js::{self, Obj, Str, V};
use crate::lay::read::{self as read, dates, docs, misc, vocab};

/// 4969 ~ 4981줄 — 문서: 키(다듬은 글)가 비지 않고 본문이 빈칸뿐이 아닌 글만. 키 꼴이 틀리면 알리고 뺀다(같은 키로 다듬어지면 뒤의 본문이 그 자리에).
pub(super) fn read_documents(n: &mut Norm, pack: &Obj, raw: &V) {
    let V::Obj(docs_in) = raw.get("documents") else { return };
    let out = pack.obj("documents").expect("pack.documents");
    for (k, v) in docs_in.entries() {
        let key = k.trim();
        let V::Str(body) = &v else { continue };
        if key.is_empty() || body.trim().is_empty() { continue; }
        if !docs::doc_key_valid(&key) {
            n.warn(format!("문서 \"{key}\": 키 형식이 올바르지 않아 무시했습니다."), "documents", None);
            continue;
        }
        out.set(&key, v.clone());
    }
}

/// `/["'\\/]/.test(id)` — 따옴표 · 작은따옴표 · 역슬래시 · '/'가 들었나.
fn bad_id_char(id: &Str) -> bool { id.units().any(|c| matches!(c, 0x22 | 0x27 | 0x5C | 0x2F)) }
/// `typeof v === 'number' ? v : HT.parseYear(v)`(수는 그대로 — 무한도).
fn year_or_parse(n: &Norm, v: &V) -> f64 { if let V::Num(x) = v { *x } else { dates::parse_year(n.ctx, v) } }

/// 4983 ~ 5064줄 — 영토(지도): `{ basemap, polities: [지도 전용 정권], ownership: { 조각id: [[시작, 끝, 정권, 상태?, 상대?], …] } }`.
/// 정권은 "트랙:이름"(연표의 시대)이나 polities의 id로 적는다. 자세한 해석은 `js/map.js`의 `HT.resolveTerritory`(모델 몫).
pub(super) fn read_territory(n: &mut Norm, pack: &Obj, raw: &V) {
    let t = raw.get("territory");
    if !matches!(t, V::Obj(_)) { return; }
    let s = dates::str_of;
    let o = Obj::new();
    o.set("basemap", { let b = s(&t.get("basemap")); if b.is_empty() { Str::from("east-asia-v3") } else { b } });
    o.set("polities", read::arr_of(Vec::new()));
    o.set("ownership", Obj::new());
    // (t.generate — 내장 팩 전용 함수 · JSON으로는 나가지 않음: JSON에서 읽은 팩에는 없다)
    let over = s(&t.get("generateOver"));
    if !over.is_empty() { o.set("generateOver", over); } // 규칙을 돌릴 단위 팩 id
    let unit_packs = dates::arr(&t.get("unitPacks"));
    if !unit_packs.is_empty() { o.set("unitPacks", read::arr_of(unit_packs.iter().map(s).filter(|x| !x.is_empty()).map(V::Str).collect())); } // 함께 불러올 단위 팩
    // DLC 안에 직접 적은 단위(원자 조각 묶음): { id, name, level, parent, start, end, cells: [조각 id], source, confidence }
    let mut units: Vec<V> = Vec::new();
    for (i, u) in dates::arr(&t.get("units")).iter().enumerate() {
        let id = s(&read::and(u, "id"));
        if id.is_empty() || bad_id_char(&id) { n.err(format!("단위 #{}: id가 비었거나 올바르지 않습니다.", i + 1), "territory", Some(i)); continue; }
        let cells: Vec<V> = dates::arr(&u.get("cells")).iter().map(s).filter(|x| !x.is_empty()).map(V::Str).collect();
        let q = Obj::new();
        q.set("id", id.clone());
        q.set("name", { let nm = s(&u.get("name")); if nm.is_empty() { id.clone() } else { nm } });
        if cells.is_empty() { n.warn(format!("단위 \"{id}\": 조각 목록이 비어 있어 무시했습니다."), "territory", Some(i)); continue; }
        q.set("cells", read::arr_of(cells));
        for k in ["level", "parent", "parentName", "source", "confidence", "description"] {
            let x = s(&u.get(k));
            if !x.is_empty() { q.set(k, x); }
        }
        for k in ["start", "end"] {
            let v = u.get(k);
            if v.is_nullish() || read::is_empty_str(&v) { continue; }
            if k == "end" && dates::is_ongoing_text(&v) { continue; }
            let y = year_or_parse(n, &v);
            if !y.is_nan() { q.set(k, y); }
        }
        units.push(V::Obj(q));
    }
    let has_units = !units.is_empty();
    if has_units { o.set("units", read::arr_of(units)); }
    // 조각 지명 기록: { 조각id: [[시작, 끝, 이름, 상위], …] } — 같은 조각의 내장 기록을 통째로 덮어씀
    let names = Obj::new();
    let mut n_names = 0;
    let names_in = t.get("names");
    let entries = if js::truthy(&names_in) && js::type_of(&names_in) == "object" { read::assign_copy(&names_in).entries() } else { Vec::new() };
    for (id, rows) in entries {
        let mut list: Vec<(f64, V)> = Vec::new();
        for (i, r) in dates::arr(&rows).iter().enumerate() {
            let ok = matches!(r, V::Arr(a) if a.len() >= 3);
            if !ok { n.warn(format!("지명 기록 \"{id}\" #{}: [시작, 끝, 이름, 상위] 꼴이 아닙니다.", i + 1), "territory", None); continue; }
            let st = year_or_parse(n, &r.get(&0.0));
            let e1 = r.get(&1.0);
            let en = if e1.is_nullish() || read::is_empty_str(&e1) || dates::is_ongoing_text(&e1) { 9999.0 } else { year_or_parse(n, &e1) };
            if st.is_nan() || en.is_nan() || s(&r.get(&2.0)).is_empty() { n.warn(format!("지명 기록 \"{id}\" #{}: 연도나 이름을 읽을 수 없습니다.", i + 1), "territory", None); continue; }
            list.push((st, read::arr_of(vec![V::Num(st), V::Num(en), V::Str(s(&r.get(&2.0))), V::Str(s(&r.get(&3.0)))])));
        }
        js::sort_by(&mut list, |a, b| a.0 - b.0);
        if !list.is_empty() {
            n_names += list.len();
            names.set(&id, read::arr_of(list.into_iter().map(|x| x.1).collect()));
        }
    }
    if n_names > 0 { o.set("names", names); }
    // 지도 전용 정권
    let mut pol_ids: Vec<Str> = Vec::new();
    let polities = o.arr("polities").expect("territory.polities");
    for (i, p) in dates::arr(&t.get("polities")).iter().enumerate() {
        let id = s(&read::and(p, "id"));
        let pn = read::and(p, "name");
        let label = format!("지도 정권 #{}{}", i + 1, if js::truthy(&pn) { format!(" \"{}\"", js::to_str(&pn)) } else { String::new() });
        if id.is_empty() || bad_id_char(&id) { n.err(format!("{label}: id가 비었거나 올바르지 않습니다 (따옴표·역슬래시·/ 는 쓸 수 없음)."), "territory", Some(i)); continue; }
        if pol_ids.contains(&id) { n.warn(format!("{label}: id \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "territory", Some(i)); continue; }
        pol_ids.push(id.clone());
        let q = Obj::new();
        q.set("id", id.clone());
        q.set("name", { let nm = s(&p.get("name")); if nm.is_empty() { id } else { nm } });
        if misc::is_color(&p.get("color")) { q.set("color", p.get("color")); }
        for k in ["track", "period"] {
            let x = s(&p.get(k));
            if !x.is_empty() { q.set(k, x); }
        }
        let kind = s(&p.get("kind"));
        if !kind.is_empty() && vocab::POLITY_KINDS.iter().any(|k| kind == k.id) { q.set("kind", kind); }
        for k in ["start", "end"] {
            let v = p.get(k);
            if v.is_nullish() || read::is_empty_str(&v) { continue; }
            if k == "end" && dates::is_ongoing_text(&v) { continue; }
            let y = year_or_parse(n, &v);
            if y.is_nan() { n.warn(format!("{label}: {k} 연도를 읽을 수 없어 무시했습니다."), "territory", Some(i)); }
            else { q.set(k, y); }
        }
        let description = s(&p.get("description"));
        if !description.is_empty() { q.set("description", description); }
        polities.push(V::Obj(q));
    }
    // 소유 기록
    let own_in = t.get("ownership");
    let own = if js::truthy(&own_in) && js::type_of(&own_in) == "object" { read::assign_copy(&own_in).entries() } else { Vec::new() };
    let (mut bad, mut overlaps) = (0, 0);
    let now_next = n.ctx.current_year + 1.0;
    let yr = |v: &V| if v.is_nullish() || read::is_empty_str(v) || dates::is_ongoing_text(v) { now_next } else { year_or_parse(n, v) };
    let ownership = o.obj("ownership").expect("territory.ownership");
    for (cell_id, rows) in own {
        let mut list: Vec<(f64, V)> = Vec::new();
        for r in dates::arr(&rows) {
            let row: Option<Vec<V>> = match &r {
                V::Arr(a) => Some(a.to_vec().into_iter().take(5).collect()),
                x if js::truthy(x) && js::type_of(x) == "object" => Some(["start", "end", "polity", "status", "by"].iter().map(|k| x.get(*k)).collect()),
                _ => None,
            };
            let at = |row: &[V], k: usize| row.get(k).cloned().unwrap_or_default();
            let Some(row) = row.filter(|row| {
                let (a, b) = (yr(&at(row, 0)), yr(&at(row, 1)));
                !s(&at(row, 2)).is_empty() && !a.is_nan() && !b.is_nan() && a < b
            }) else { bad += 1; continue; };
            let mut out = vec![V::Num(yr(&at(&row, 0))), V::Num(yr(&at(&row, 1))), V::Str(s(&at(&row, 2)))];
            let status = s(&at(&row, 3));
            if !status.is_empty() {
                out.push(V::Str(status));
                let by = s(&at(&row, 4));
                if !by.is_empty() { out.push(V::Str(by)); }
            }
            list.push((yr(&at(&row, 0)), read::arr_of(out)));
        }
        js::sort_by(&mut list, |a, b| a.0 - b.0);
        for k in 1..list.len() {
            if list[k].0 < list[k - 1].1.get(&1.0).as_num().unwrap_or(f64::NAN) { overlaps += 1; }
        }
        if !list.is_empty() { ownership.set(&cell_id, read::arr_of(list.into_iter().map(|x| x.1).collect())); }
    }
    if bad > 0 { n.warn(format!("영토: 읽을 수 없는 소유 기록 {bad}개를 무시했습니다."), "territory", None); }
    if overlaps > 0 { n.warn(format!("영토: 같은 조각에서 기간이 겹치는 소유 기록이 {overlaps}곳 있습니다. 뒤의 기록이 앞의 것을 덮습니다."), "territory", None); }
    if !polities.is_empty() || !ownership.is_empty() || has_units { pack.set("territory", o); }
}

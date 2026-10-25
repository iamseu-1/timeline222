//! `js/core.js` 944 ~ 1724줄 가운데 읽기가 쓰는 것 — 칸의 미정 · 칸 차례 · 시기 구분 · 지위 · 소속 줄 · 대범위 참조 · 이설 · 확실성 · 낱말 표 읽기 — 한 벌 P3 과제 5a · 5b.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! (2026-10-24 맞춤 · 리메이크 3단계 과제 1 · `core.js` `7c75434e37fa`) 1425줄 소속 줄의 으뜸(main — 형식 4 within.main)
//! - 944 ~ 952줄 `HT.readCellEdge`
//! - (5b) 955 ~ 966줄 `HT.sortCells`
//! - (5b) 1035 ~ 1137줄 `HT.readPhases`(안의 `where` · `groupOf` · `readSpan` — 칸 꼴 배열 `[이름, 시작, 끝, 메모]`은 `cell_of_tuple`)
//! - (5b) 1216 ~ 1249줄 `HT.readRankDefs` · 1270 ~ 1327줄 `HT.readRanks`(1197줄 내장 사전 `HT.RANKS`는 모델이 합칠 때 — 과제 6)
//! - (5b) 1393 ~ 1426줄 `HT.readPartOf`
//! - 1428줄 `HT.compactPartOf`
//! - 1432 ~ 1444줄 `HT.readScopeRef` · `HT.readScopeRefs` · `HT.compactScopeRef`
//! - (1449줄 `HT.isUnknownText`는 `read::dates`에 — 날짜 칸과 함께 쓰임)
//! - (5b) 1451줄 `HT.isUnknownOrdinal`(정규식은 `unknown_word` — 2504줄 `HT.isUnknownWho`와 같은 정규식)
//! - 1485 ~ 1545줄 `ALT_DATE_KEYS` · `ALT_WORDS` · `HT.readAlternatives`
//! - 1553 ~ 1567줄 `HT.centuryRanges`
//! - 1568 ~ 1617줄 `HT.readUncertain`
//! - 1638 ~ 1655줄 `altFlipSide` · `FIG_WORDS` · `altFlipText`
//! - 1718 ~ 1724줄 `vocab`(낱말 표 → id)
//! - (2026-10-24 맞춤 · 리메이크 6단계 걸음 2 · `core.js` `b2e6b19490bf`) 420 ~ 443줄 `HT.readSpheres`의 지도자 표기 낱말(438 ~ 439줄 — [`capital::read_leader_labels`](super::capital::read_leader_labels)) ·
//!   1398 ~ 1462줄 `readSpanList`(`HT.readRanks`의 몸을 지위 변천 · 종교가 함께 씀 — 글의 낱말만 [`SpanWords`]) · `RANK_WORDS` · `FAITH_WORDS` · `HT.readRanks` · `HT.readFaiths`(종교 — D8)
//!
//! 옮기지 않은 것(뒤 과제 — 조약 · 단체 · 제도 칸 읽기는 과제 5c가 `read::treaty` · `read::groups`로): 모델 몫(`HT.cellStartGuess` · `HT.cellStartCap` · `HT.cellsFileForm` · `HT.placeCells` · `HT.resolvePhases` ·
//! `HT.mergeRankDefs` · `HT.findRank` · `HT.resolveRanks` — 과제 6), `HT.altSpan` · `HT.altFlipped` · 쓰기 도움(화면).
use super::{dates, vocab, Ctx};
use crate::lay::cal;
use crate::lay::js::{self, Obj, Str, V};

/// `HT.readCellEdge`의 답: 미정(`{ unknown: true, t: 배치용 연도 | null }`) 또는 날짜 칸(`HT.readDate`의 답).
#[derive(Debug, Clone)]
pub enum Edge { Unknown(Option<f64>), Date(dates::DateR) }

/// `HT.readCellEdge(c, key)` — 칸의 시작 · 끝 하나: "미정"(글 · `…Unknown: true`)이면 배치용 연도(`…Hint`, 아니면 적은 값)와 함께 미정, 아니면 날짜 읽기.
pub fn read_cell_edge(ctx: &Ctx, c: &V, key: &str) -> Option<Edge> {
    if !js::truthy(c) { return None; }
    let raw = c.get(key);
    if matches!(c.get(&format!("{key}Unknown")), V::Bool(true)) || dates::is_unknown_text(&raw) {
        let auto = js::truthy(&c.get(&format!("{key}Auto"))) || dates::is_unknown_text(&raw);
        let hint = [c.get(&format!("{key}Hint")), if auto { V::Null } else { raw.clone() }]
            .iter()
            .map(|v| if v.is_nullish() || super::is_empty_str(v) { f64::NAN } else { dates::parse_year(ctx, v) })
            .find(|v| !v.is_nan());
        return Some(Edge::Unknown(hint));
    }
    dates::read_date(ctx, &raw, &c.get(&format!("{key}At"))).map(Edge::Date)
}

/// `HT.sortCells(list)` — 칸 목록을 시작 순으로: 시작을 모르면 끝으로(그해에 끝나는 칸이라 같은 해에 시작하는 칸보다 앞에), 둘 다 모르면 적힌 차례에서 앞 칸 바로 뒤에
/// (같으면 적힌 차례 그대로). 비교 `a.k - b.k || a.byEnd - b.byEnd || a.i - b.i`의 `||`는 0 · NaN이면 다음으로(−Infinity끼리의 뺄셈은 NaN) — 정렬은 V8 TimSort(`js::sort_by`).
pub fn sort_cells(list: Vec<V>) -> Vec<V> {
    let mut last = f64::NEG_INFINITY;
    let mut rows: Vec<(V, f64, f64, f64)> = list
        .into_iter()
        .enumerate()
        .map(|(i, c)| {
            let k = js::nullish(c.get("start"), c.get("end"));
            let ok = !k.is_nullish() && js::to_num(&k).is_finite();
            if ok { last = js::to_num(&k); }
            let by_end = if ok && c.get("start").is_nullish() { 0.0 } else { 1.0 };
            (c, if ok { js::to_num(&k) } else { last }, by_end, i as f64)
        })
        .collect();
    js::sort_by(&mut rows, |a, b| {
        let d = a.1 - b.1;
        if d != 0.0 && !d.is_nan() { return d; }
        let d = a.2 - b.2;
        if d != 0.0 { return d; }
        a.3 - b.3
    });
    rows.into_iter().map(|r| r.0).collect()
}

/// 칸 꼴 배열 `[이름, 시작, 끝, 메모]`을 객체로(시기 · 지위 변천 · 정권의 칸 목록이 같은 꼴).
pub fn cell_of_tuple(a: &js::Arr) -> V {
    let o = Obj::new();
    o.set("name", a.get(0));
    o.set("start", a.get(1));
    o.set("end", a.get(2));
    o.set("note", a.get(3));
    V::Obj(o)
}

/// `HT.readPhases`의 답 `{ list, problems, warnings }`.
#[derive(Debug, Default)]
pub struct Phases { pub list: Vec<V>, pub problems: Vec<String>, pub warnings: Vec<String> }

/// `where(name)` — 알림 글의 머리.
fn phase_where(name: &Str) -> String { if name.is_empty() { "시기 구분".into() } else { format!("시기 구분 \"{name}\"") } }
/// `readSpan(c, scheme)`(`HT.readPhases` 안) — 시기 하나: `[이름, 시작, 끝, 메모]` · `{ name, start, end, note }` → 정리한 시기(뺄 것이면 None — problems에 까닭).
fn read_phase_span(ctx: &Ctx, c: &V, scheme: &Str, problems: &mut Vec<String>, warnings: &mut Vec<String>) -> Option<Obj> {
    let w = phase_where(scheme);
    let x = match c {
        V::Arr(a) => cell_of_tuple(a),
        v if js::truthy(v) && super::is_object(v) => v.clone(),
        _ => {
            problems.push(format!("{w}: 꼴이 올바르지 않은 시기를 뺐습니다."));
            return None;
        }
    };
    let name = dates::str_of(&js::nullish(x.get("name"), x.get("title")));
    if name.is_empty() {
        problems.push(format!("{w}: 이름이 없는 시기를 뺐습니다."));
        return None;
    }
    let o = Obj::new();
    o.set("name", name.clone());
    for k in ["start", "end"] {
        // 미정: 칸의 미정(HT.readCellEdge)과 같은 규칙 — 배치용 연도가 있으면 그 자리에, 없으면 비운 것과 같은 자리. 글에는 늘 '미정'
        match read_cell_edge(ctx, &x, k) {
            Some(Edge::Unknown(t)) => {
                o.set(&format!("{k}Unknown"), true);
                if let Some(t) = t { o.set(k, t); }
            }
            Some(Edge::Date(d)) if d.t.is_nan() => {
                let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" ({e})"));
                problems.push(format!("{w}: 시기 \"{name}\"의 {}을 읽을 수 없어 그 시기를 뺐습니다.{why}", if k == "start" { "시작" } else { "끝" }));
                return None;
            }
            Some(Edge::Date(d)) => {
                o.set(k, d.t);
                if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
            }
            None => {}
        }
    }
    if !o.get("start").is_nullish() && !o.get("end").is_nullish() && dates::end_bound_t(ctx, o.num("end"), &o.get("endAt")) < o.num("start") {
        // 시작만 미정이면(시작은 배치용 연도뿐) 그 배치용 연도를 버리고 적은 끝은 남긴다 — 지위 변천 · 섬긴 기록 · 인물 활동 시기와 같은 규칙
        if o.bool("startUnknown") && !o.bool("endUnknown") {
            warnings.push(format!("{w}: 시기 \"{name}\"의 끝이 시작보다 앞서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로)."));
            o.delete("start");
        } else {
            warnings.push(format!("{w}: 시기 \"{name}\"의 끝이 시작보다 앞서 끝을 비웠습니다(다음 시기까지로 봄)."));
            o.delete("end");
            o.delete("endAt");
        }
    }
    let note = dates::str_of(&x.get("note"));
    if !note.is_empty() { o.set("note", note); }
    let (start, end) = (o.get("start").as_num(), o.get("end").as_num());
    let unc = read_uncertain(ctx, &x, "cell", Some(&mut |m: String| warnings.push(format!("{w}: 시기 \"{name}\" — {m}"))), start, end, None);
    for (k, v) in unc.entries() { o.set(&k, v); }
    Some(o)
}
/// `HT.readPhases(v)` — 시기 구분 원문 → 정리한 체계 목록 `[{ scheme?, note?, spans }]` · 뺀 것의 글 · 참고할 것의 글(겹침 · 거꾸로 된 끝 …).
/// 납작한 꼴 `[{ name, start, end, scheme }]`도 받아 체계별로(처음 나온 차례대로) 묶는다.
pub fn read_phases(ctx: &Ctx, v: &V) -> Phases {
    let s = dates::str_of;
    let mut problems = Vec::new();
    let mut warnings = Vec::new();
    // groups: (scheme, note, spans) — 처음 나온 차례
    let mut groups: Vec<(Str, Str, Vec<V>)> = Vec::new();
    let group_of = |groups: &mut Vec<(Str, Str, Vec<V>)>, name: &Str, note: &Str| -> usize {
        let at = match groups.iter().position(|g| g.0 == *name) {
            Some(at) => at,
            None => { groups.push((name.clone(), Str::default(), Vec::new())); groups.len() - 1 }
        };
        if !note.is_empty() && groups[at].1.is_empty() { groups[at].1 = note.clone(); }
        at
    };
    if !v.is_nullish() && !super::is_empty_str(v) && js::type_of(v) != "object" { problems.push("시기 구분은 목록이어야 해서 무시했습니다.".to_string()); }
    let list = match v { V::Arr(a) => a.to_vec(), x if js::truthy(x) && super::is_object(x) => vec![x.clone()], _ => Vec::new() };
    let mut seen: Vec<Str> = Vec::new();
    for x in &list {
        if js::truthy(x) && super::is_plain(x) && matches!(x.get("spans"), V::Arr(_)) {
            let name = s(&x.get("scheme"));
            if seen.contains(&name) { warnings.push(format!("{}: 같은 이름의 체계가 둘이라 하나로 합쳤습니다.", phase_where(&name))); }
            else { seen.push(name.clone()); }
            let at = group_of(&mut groups, &name, &s(&x.get("note")));
            for c in dates::arr(&x.get("spans")) {
                if let Some(sp) = read_phase_span(ctx, &c, &name, &mut problems, &mut warnings) { groups[at].2.push(V::Obj(sp)); }
            }
        } else {
            let name = if js::truthy(x) && super::is_plain(x) { s(&x.get("scheme")) } else { Str::default() };
            if let Some(sp) = read_phase_span(ctx, x, &name, &mut problems, &mut warnings) {
                let at = group_of(&mut groups, &name, &Str::default());
                groups[at].2.push(V::Obj(sp));
            }
        }
    }
    let mut out = Vec::new();
    for (scheme, note, spans) in groups {
        if spans.is_empty() {
            problems.push(format!("{}: 시기가 하나도 없어 뺐습니다.", phase_where(&scheme)));
            continue;
        }
        // 차례: 적힌 시작 순으로. 시작을 비운 시기는 바로 앞에 적힌 시기 뒤에 그대로(첫 시기면 맨 앞)
        let mut key = f64::NEG_INFINITY;
        let mut rows: Vec<(V, f64, f64)> = spans
            .into_iter()
            .enumerate()
            .map(|(i, sp)| {
                let st = sp.get("start");
                if !st.is_nullish() { key = js::to_num(&st); }
                (sp, key, i as f64)
            })
            .collect();
        js::sort_by(&mut rows, |a, b| {
            let d = if a.1 == b.1 { 0.0 } else { a.1 - b.1 };
            if d != 0.0 && !d.is_nan() { d } else { a.2 - b.2 }
        });
        let spans: Vec<V> = rows.into_iter().map(|r| r.0).collect();
        let w = phase_where(&scheme);
        for pair in spans.windows(2) {
            let (a, b) = (&pair[0], &pair[1]);
            let (a_start, a_end, b_start) = (a.get("start"), a.get("end"), b.get("start"));
            let (an, bn) = (js::to_str(&a.get("name")), js::to_str(&b.get("name")));
            if (!a_end.is_nullish() && !b_start.is_nullish() && js::to_num(&a_end) > js::to_num(&b_start)) || (!a_start.is_nullish() && js::strict_eq(&a_start, &b_start)) {
                warnings.push(format!("{w}: 시기 \"{an}\"와(과) \"{bn}\"이(가) 겹칩니다."));
            }
            if a_end.is_nullish() && b_start.is_nullish() { warnings.push(format!("{w}: 시기 \"{an}\"의 끝도 \"{bn}\"의 시작도 비어 있어, 그 경계는 앞뒤 사이를 고르게 나눠 그립니다.")); }
        }
        let o = Obj::new();
        if !scheme.is_empty() { o.set("scheme", scheme); }
        if !note.is_empty() { o.set("note", note); }
        o.set("spans", super::arr_of(spans));
        out.push(V::Obj(o));
    }
    if out.len() > 1 && out.iter().any(|g| !js::truthy(&g.get("scheme"))) {
        warnings.push("시기 구분: 체계가 둘 이상이면 체계마다 이름을 적어 주세요 (이름 없는 체계는 이름표 없이 그립니다).".to_string());
    }
    Phases { list: out, problems, warnings }
}

/// `HT.readRankDefs`의 답 `{ list, problems, at }` — `at[k]`는 `problems[k]`가 가리키는 줄의 차례(목록 전체의 것이면 None — JS의 undefined).
#[derive(Debug, Default)]
pub struct RankDefs { pub list: Vec<V>, pub problems: Vec<String>, pub at: Vec<Option<usize>> }
/// `HT.readRankDefs(v)` — 지위 사전 원문 → `{ list, problems, at }`. id가 없으면 이름으로 만들고, 같은 id가 또 나오면 뒤의 것을 뺀다.
pub fn read_rank_defs(v: &V) -> RankDefs {
    let s = dates::str_of;
    let mut r = RankDefs::default();
    let bad = |r: &mut RankDefs, i: Option<usize>, msg: String| { r.problems.push(msg); r.at.push(i); };
    if !v.is_nullish() && !super::is_empty_str(v) && !matches!(v, V::Arr(_)) { bad(&mut r, None, "지위 사전(rankDefs)은 목록이어야 해서 무시했습니다.".into()); }
    for (i, d) in dates::arr(v).iter().enumerate() {
        if !js::truthy(d) || !super::is_plain(d) { bad(&mut r, Some(i), format!("지위 사전 #{}: 형식이 올바르지 않아 뺐습니다.", i + 1)); continue; }
        let name = s(&d.get("name"));
        if name.is_empty() { bad(&mut r, Some(i), format!("지위 사전 #{}: 이름이 없어 뺐습니다.", i + 1)); continue; }
        let mut id = s(&d.get("id"));
        if !id.is_empty() && !dates::id_ok(&id) {
            bad(&mut r, Some(i), format!("지위 사전 \"{name}\": id \"{id}\"가 올바르지 않아 새로 만들었습니다."));
            id = Str::default();
        }
        if id.is_empty() { id = super::cat(&[&Str::from("rank-"), &super::misc::hash(&name)]); }
        if r.list.iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) { bad(&mut r, Some(i), format!("지위 사전 \"{name}\": id \"{id}\"가 중복되어 뺐습니다.")); continue; }
        let o = Obj::new();
        o.set("id", id);
        o.set("name", name.clone());
        let tier = d.get("tier");
        if !super::is_empty_str(&tier) && !tier.is_nullish() {
            let t = js::to_num(&tier);
            if t.is_finite() { o.set("tier", t); }
            else { bad(&mut r, Some(i), format!("지위 사전 \"{name}\": 서열 \"{}\"을(를) 읽을 수 없어 서열 밖으로 둡니다.", s(&tier))); }
        }
        let raw_aliases: Vec<V> = match d.get("aliases") { V::Arr(a) => a.to_vec(), x => super::split_units(&s(&x), &[0x2C]).into_iter().map(V::Str).collect() };
        let mut aliases: Vec<Str> = Vec::new();
        for a in raw_aliases.iter().map(s) { if !a.is_empty() && a != name && !aliases.contains(&a) { aliases.push(a); } }
        if !aliases.is_empty() { o.set("aliases", super::arr_of(aliases.into_iter().map(V::Str).collect())); }
        let description = s(&d.get("description"));
        if !description.is_empty() { o.set("description", description); }
        r.list.push(V::Obj(o));
    }
    r
}

/// `HT.readSpheres`의 답 `{ list, problems, at }` — [`RankDefs`]와 같은 꼴(`at[k]`는 `problems[k]`가 가리키는 줄의 차례 · 목록 전체의 것이면 None).
#[derive(Debug, Default)]
pub struct Spheres { pub list: Vec<V>, pub problems: Vec<String>, pub at: Vec<Option<usize>> }
/// `HT.readSpheres(v)`(`js/core.js` `f90a60d102ce` 388 ~ 410줄 — 2026-10-23 문화권 사전) — DLC 최상위 `spheres` → `{ list: [{ id, name, order?, description? }], problems, at }`.
/// id가 없거나 틀린 줄 · 겹친 id는 빼고 알린다. 이름을 비우면 id.
pub fn read_spheres(v: &V) -> Spheres {
    let s = dates::str_of;
    let mut r = Spheres::default();
    let bad = |r: &mut Spheres, i: Option<usize>, msg: String| { r.problems.push(msg); r.at.push(i); };
    if !v.is_nullish() && !super::is_empty_str(v) && !matches!(v, V::Arr(_)) { bad(&mut r, None, "문화권 사전(spheres)은 목록이어야 해서 무시했습니다.".into()); }
    for (i, d) in dates::arr(v).iter().enumerate() {
        if !js::truthy(d) || !super::is_plain(d) { bad(&mut r, Some(i), format!("문화권 #{}: 형식이 올바르지 않습니다.", i + 1)); continue; }
        let id = s(&d.get("id"));
        let name = s(&d.get("name"));
        if !dates::id_ok(&id) {
            let label = if name.is_empty() { String::new() } else { format!(" \"{name}\"") };
            bad(&mut r, Some(i), format!("문화권 #{}{label}: id가 비었거나 올바르지 않습니다(영문 · 숫자 · - _ .).", i + 1));
            continue;
        }
        if r.list.iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) { bad(&mut r, Some(i), format!("문화권 \"{id}\"가 중복되어 뒤의 것을 무시했습니다.")); continue; }
        let o = Obj::new();
        o.set("id", id.clone());
        o.set("name", if name.is_empty() { id.clone() } else { name });
        let order = d.get("order");
        if !super::is_empty_str(&order) && !order.is_nullish() && js::to_num(&order).is_finite() { o.set("order", js::to_num(&order)); }
        let description = s(&d.get("description"));
        if !description.is_empty() { o.set("description", description); }
        // 지도자 표기 낱말(리메이크 6단계 D3 — 팩의 것보다 이김 · 못 읽는 칸은 이 줄의 알림으로)
        let mut msgs = Vec::new();
        let words = super::capital::read_leader_labels(&d.get("leaderLabels"), &mut |m| msgs.push(m));
        for m in msgs { bad(&mut r, Some(i), format!("문화권 \"{id}\": {m}")); }
        if let Some(w) = words { o.set("leaderLabels", w); }
        r.list.push(V::Obj(o));
    }
    r
}

/// `readSpanList`의 글 낱말(6단계 D8에서 나눔): list = 목록의 이름 · one = 칸 하나의 이름 · alias = name 대신 읽는 열쇠.
pub struct SpanWords { pub list: &'static str, pub one: &'static str, pub alias: &'static str }
/// `RANK_WORDS` — 지위 변천.
pub const RANK_WORDS: SpanWords = SpanWords { list: "지위 변천", one: "지위", alias: "rank" };
/// `FAITH_WORDS` — 종교(6단계 D8).
pub const FAITH_WORDS: SpanWords = SpanWords { list: "종교 변천", one: "종교", alias: "faith" };

/// `HT.readRanks`의 답 `{ list, problems, warnings }`.
#[derive(Debug, Default)]
pub struct Ranks { pub list: Vec<V>, pub problems: Vec<String>, pub warnings: Vec<String> }
/// `HT.readRanks(v)` — 지위 변천 원문 → `{ list: [{ name, start?, startAt?, startUnknown?, end?, endAt?, endUnknown?, note? }], problems, warnings }`.
/// 시작을 비울 수 있는 것은 적은 차례로 첫 칸뿐(정권 시작부터). 시작 · 끝에 "미정"도 된다(칸의 미정). 몸은 [`read_span_list`].
pub fn read_ranks(ctx: &Ctx, v: &V) -> Ranks { read_span_list(ctx, v, &RANK_WORDS) }
/// `HT.readFaiths(v)`(리메이크 6단계 D8) — 종교 원문 → 지위 변천과 같은 꼴 · 같은 규칙(읽을 때만 name 대신 faith도 받음).
pub fn read_faiths(ctx: &Ctx, v: &V) -> Ranks { read_span_list(ctx, v, &FAITH_WORDS) }
/// `readSpanList(v, W)` — 지위 변천 · 종교의 칸 목록 읽기(6단계 D8에서 나눔 · 글의 낱말만 [`SpanWords`]).
pub fn read_span_list(ctx: &Ctx, v: &V, w: &SpanWords) -> Ranks {
    let s = dates::str_of;
    let mut problems = Vec::new();
    let mut warnings = Vec::new();
    let mut out: Vec<V> = Vec::new();
    if !v.is_nullish() && !super::is_empty_str(v) && !matches!(v, V::Arr(_)) { problems.push(format!("{}은 목록이어야 해서 무시했습니다.", w.list)); }
    'cells: for (i, raw) in dates::arr(v).iter().enumerate() {
        let x = match raw {
            V::Arr(a) => cell_of_tuple(a),
            V::Str(_) => { let o = Obj::new(); o.set("name", raw.clone()); V::Obj(o) }
            r if js::truthy(r) && super::is_object(r) => r.clone(),
            _ => { problems.push(format!("{} {}번째 칸: 꼴이 올바르지 않아 뺐습니다.", w.list, i + 1)); continue; }
        };
        let name = s(&js::nullish(x.get("name"), x.get(w.alias)));
        if name.is_empty() { problems.push(format!("{} {}번째 칸: {} 이름이 없어 뺐습니다.", w.list, i + 1, w.one)); continue; }
        let o = Obj::new();
        o.set("name", name.clone());
        for k in ["start", "end"] {
            match read_cell_edge(ctx, &x, k) { // 칸의 미정: "미정" 글 · startUnknown · startHint → 미정 + (있으면) 배치용 연도
                Some(Edge::Unknown(t)) => {
                    if let Some(t) = t { o.set(k, t); }
                    o.set(&format!("{k}Unknown"), true);
                }
                Some(Edge::Date(d)) if d.t.is_nan() => {
                    let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" ({e})"));
                    problems.push(format!("{} \"{name}\"의 {}을 읽을 수 없어 그 칸을 뺐습니다.{why}", w.one, if k == "start" { "시작" } else { "끝" }));
                    continue 'cells;
                }
                Some(Edge::Date(d)) => {
                    o.set(k, d.t);
                    if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
                }
                None => {}
            }
        }
        if o.get("start").is_nullish() && !o.bool("startUnknown") && !out.is_empty() {
            problems.push(format!("{} \"{name}\": 시작이 없어 뺐습니다 (시작을 비울 수 있는 것은 첫 칸뿐 — 정권 시작부터, 모르면 \"미정\").", w.one));
            continue;
        }
        if !o.get("start").is_nullish() && !o.get("end").is_nullish() && dates::end_bound_t(ctx, o.num("end"), &o.get("endAt")) < o.num("start") {
            // 거꾸로면 짐작인 쪽을 버린다: 시작만 미정이면 시작의 배치용 연도(적은 끝은 사실이라 남김), 아니면 끝
            if o.bool("startUnknown") && !o.bool("endUnknown") {
                warnings.push(format!("{} \"{name}\"의 끝이 시작보다 앞서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로, 자리는 앞 {}에 맞춤).", w.one, w.one));
                o.delete("start");
            } else {
                warnings.push(format!("{} \"{name}\"의 끝이 시작보다 앞서 끝을 비웠습니다({}).", w.one, if o.bool("endUnknown") { "미정인 끝의 배치용 연도를 버림".to_string() } else { format!("다음 {}까지로 봄", w.one) }));
                o.delete("end");
                o.delete("endAt");
            }
        }
        if o.bool("startUnknown") && o.bool("endUnknown") && o.get("start").is_nullish() && o.get("end").is_nullish() {
            warnings.push(format!("{} \"{name}\"은(는) 시작과 끝이 모두 미정이고 배치용 연도가 없어, 앞뒤 {}나 정권의 기간에 맞춰 놓습니다.", w.one, w.one));
        }
        let note = s(&x.get("note"));
        if !note.is_empty() { o.set("note", note); }
        let (start, end) = (o.get("start").as_num(), o.get("end").as_num());
        let unc = read_uncertain(ctx, &x, "cell", Some(&mut |m: String| warnings.push(format!("{} \"{name}\" — {m}", w.one))), start, end, None);
        for (k, v) in unc.entries() { o.set(&k, v); }
        out.push(V::Obj(o));
    }
    // 차례: 다른 이어지는 칸과 같은 HT.sortCells. 시작을 비운 첫 칸(정권 시작부터)만 맨 앞 그대로
    let list = if !out.is_empty() && out[0].get("start").is_nullish() && !out[0].bool("startUnknown") {
        let mut l = vec![out[0].clone()];
        l.extend(sort_cells(out[1..].to_vec()));
        l
    } else {
        sort_cells(out)
    };
    for pair in list.windows(2) {
        let (a, b) = (&pair[0], &pair[1]);
        let (a_start, a_end, b_start, b_end) = (a.get("start"), a.get("end"), b.get("start"), b.get("end"));
        let say = || format!("{} \"{}\"와(과) \"{}\"의 기간이 겹칩니다.", w.one, js::to_str(&a.get("name")), js::to_str(&b.get("name")));
        if b_start.is_nullish() {
            // 시작이 미정이고 배치용 연도가 없는 칸은 앞 칸에 이어 놓는다 — 겹치는 것은 적은 끝이 앞 칸의 끝보다 앞서(앞 칸의 시작보다는 뒤) 앞 칸 안에서 끝날 때뿐
            if !b_end.is_nullish() && !a_end.is_nullish() && js::to_num(&a_end) > js::to_num(&b_end) && !(!a_start.is_nullish() && js::to_num(&b_end) <= js::to_num(&a_start)) { warnings.push(say()); }
            continue;
        }
        if (!a_end.is_nullish() && js::to_num(&a_end) > js::to_num(&b_start)) || js::strict_eq(&a_start, &b_start) { warnings.push(say()); }
    }
    Ranks { list, problems, warnings }
}

/// `HT.readPartOf(v, opts)` — 소속(예속): 글 하나 또는 `[{ polity, start, end, note }]` 여럿. `relation`(시대의 partOf에서만 참)이면 소속 관계(id나 한국어 — 모르는 말은 버림)와
/// 놓는 자리(nest: true · false)를 함께 받는다. 기간의 시작 · 끝에 "미정"도 된다. 정권이 빈 줄은 뺀다(그 줄의 확실성 알림은 웹처럼 빼기 전에 낸다).
pub fn read_part_of(ctx: &Ctx, v: &V, relation: bool, mut warn: Warn<'_>) -> Vec<V> {
    let list = match v { V::Arr(a) => a.to_vec(), x if x.is_nullish() || super::is_empty_str(x) => Vec::new(), x => vec![x.clone()] };
    let mut out = Vec::new();
    for x in &list {
        if let V::Str(t) = x {
            let polity = t.trim();
            if !polity.is_empty() { let o = Obj::new(); o.set("polity", polity); out.push(V::Obj(o)); }
            continue;
        }
        if !js::truthy(x) || !super::is_object(x) { continue; }
        let o = Obj::new();
        let polity = js::to_str(&js::nullish(js::nullish(js::nullish(x.get("polity"), x.get("to")), x.get("name")), V::from(""))).trim();
        o.set("polity", polity.clone());
        if relation {
            let rel = vocab::relation_id(&x.get("relation"));
            if !rel.is_empty() { o.set("relation", rel); }
            if let V::Bool(b) = x.get("nest") { o.set("nest", b); }
            if matches!(x.get("main"), V::Bool(true)) { o.set("main", true); } // 으뜸 그릇(형식 4 within.main — 5단계 과제 3): 여러 그릇에 들 때 나무 · 서고의 기준
        }
        let s = read_cell_edge(ctx, x, "start");
        let e = read_cell_edge(ctx, x, "end");
        for (k, edge) in [("start", s), ("end", e)] {
            match edge {
                Some(Edge::Unknown(t)) => {
                    if let Some(t) = t { o.set(k, t); }
                    o.set(&format!("{k}Unknown"), true);
                }
                Some(Edge::Date(d)) if !d.t.is_nan() => {
                    o.set(k, d.t);
                    if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
                }
                _ => {}
            }
        }
        let note = x.get("note");
        if js::truthy(&note) && !js::to_str(&note).trim().is_empty() { o.set("note", js::to_str(&note).trim()); }
        let has_warn = warn.is_some();
        let mut say = |m: String| { if let Some(w) = warn.as_mut() { w(format!("\"{polity}\" — {m}")); } };
        let unc = read_uncertain(ctx, x, "cell", if has_warn { Some(&mut say) } else { None }, o.get("start").as_num(), o.get("end").as_num(), None);
        for (k, v) in unc.entries() { o.set(&k, v); }
        if !polity.is_empty() { out.push(V::Obj(o)); }
    }
    out
}

/// `HT.compactPartOf(list)` — 항목 하나뿐이고 기간 · 메모가 없으면(열쇠가 polity 하나) 글로 줄인다.
pub fn compact_part_of(list: Vec<V>) -> V {
    if list.len() == 1 {
        if let V::Obj(o) = &list[0] {
            if o.len() == 1 { return o.get("polity"); }
        }
    }
    super::arr_of(list)
}

/// 대범위가 가리키는 정권 하나 `{ track?, polity }`.
#[derive(Debug, Clone, PartialEq)]
pub struct ScopeRef { pub track: Option<Str>, pub polity: Str }

/// `/^([A-Za-z0-9_.-]+):(.+)$/` — (트랙, 나머지). 트랙 글자가 아닌 첫 글자가 ':'이어야 하고, 나머지는 비지 않고 줄 끝이 없어야 한다(JS `.`).
fn track_colon(s: &Str) -> Option<(Str, Str)> {
    let u = s.to_units();
    let p = u.iter().position(|&c| !(c < 128 && ((c as u8).is_ascii_alphanumeric() || matches!(c as u8, b'_' | b'.' | b'-'))))?;
    if p == 0 || u[p] != u16::from(b':') { return None; }
    let rest = &u[p + 1..];
    if rest.is_empty() || rest.iter().any(|&c| matches!(c, 0x0A | 0x0D | 0x2028 | 0x2029)) { return None; }
    Some((Str::from_units(&u[..p]), Str::from_units(rest)))
}
/// `HT.readScopeRef(x)` — "이름" · "트랙:이름" 글 · `{ track, polity }`(또는 `name`) 객체 → 참조(정권이 비면 None).
pub fn read_scope_ref(x: &V) -> Option<ScopeRef> {
    if let V::Str(t) = x {
        let s = t.trim();
        if s.is_empty() { return None; }
        if let Some((track, rest)) = track_colon(&s) {
            let polity = rest.trim();
            if !polity.is_empty() { return Some(ScopeRef { track: Some(track), polity }); }
        }
        return Some(ScopeRef { track: None, polity: s });
    }
    if !js::truthy(x) || !super::is_object(x) { return None; }
    let polity = js::to_str(&js::nullish(js::nullish(x.get("polity"), x.get("name")), V::from(""))).trim();
    let track = js::to_str(&js::nullish(x.get("track"), V::from(""))).trim();
    if polity.is_empty() { return None; }
    Some(ScopeRef { track: if track.is_empty() { None } else { Some(track) }, polity })
}
/// `HT.readScopeRefs(v)` — 목록(하나만 적은 것도) → 읽힌 참조들.
pub fn read_scope_refs(v: &V) -> Vec<ScopeRef> {
    let list = match v { V::Arr(a) => a.to_vec(), x if x.is_nullish() || super::is_empty_str(x) => Vec::new(), x => vec![x.clone()] };
    list.iter().filter_map(read_scope_ref).collect()
}
/// `HT.compactScopeRef(r)` — `r.track ? { track: r.track, polity: r.polity } : r.polity`. 참조 객체 `r`의 두 칸을 JS 값 그대로 받는다
/// (형식 4 내림은 객체의 `track` · `id || name`을 그대로 넘긴다 — 글이 아닐 수도 있다). 읽은 참조([`ScopeRef`])는 [`ScopeRef::compact`]로.
pub fn compact_scope_ref(track: &V, polity: &V) -> V {
    if js::truthy(track) {
        let o = Obj::new();
        o.set("track", track.clone());
        o.set("polity", polity.clone());
        V::Obj(o)
    } else {
        polity.clone()
    }
}
impl ScopeRef {
    /// [`compact_scope_ref`]에 이 참조의 두 칸을 넘긴다.
    pub fn compact(&self) -> V { compact_scope_ref(&self.track.clone().map_or(V::Undef, V::Str), &V::Str(self.polity.clone())) }
}

/// `/^(미상|미정|불명|모름|\?|unknown)$/i`(지도자 대수 · 사람의 "미상" — 1451 · 2504줄이 같은 정규식) — 손으로: 글 전체가 낱말 하나.
/// `i`는 ASCII 글자만 접는다(JS의 `u` 없는 `i` — KELVIN SIGN 'K'는 'k'가 아님).
pub fn unknown_word(s: &Str) -> bool {
    let Some(t) = s.exact() else { return false };
    matches!(t, "미상" | "미정" | "불명" | "모름" | "?") || t.eq_ignore_ascii_case("unknown")
}
/// `HT.isUnknownOrdinal(v)` — 지도자의 대수를 모름: "미상"(모름 · 불명 · ? · unknown)을 적거나 ordinalUnknown: true.
pub fn is_unknown_ordinal(v: &V) -> bool { matches!(v, V::Bool(true)) || unknown_word(&dates::str_of(v)) }

/// `ALT_DATE_KEYS[mode] || ALT_DATE_KEYS.item`.
fn alt_date_keys(mode: &str) -> &'static [&'static str] {
    if mode == "figure" { &["start", "end", "birth", "death"] } else { &["start", "end"] }
}
/// `ALT_WORDS`.
fn alt_word(k: &str) -> &'static str { match k { "start" => "시작", "end" => "끝", "birth" => "출생", "death" => "사망", _ => "" } }
/// `FIG_WORDS`(인물 — 시작 · 끝은 활동 시작 · 활동 끝).
fn fig_word(k: &str) -> &'static str { match k { "start" => "활동 시작", "end" => "활동 끝", other => alt_word(other) } }

/// 알림 받는 곳(없으면 조용히 — JS의 `warn = null`).
pub type Warn<'a> = Option<&'a mut dyn FnMut(String)>;
fn say(warn: &mut Warn<'_>, m: String) { if let Some(w) = warn.as_mut() { w(m); } }

/// 이설이 적은 날짜(열쇠 → 읽은 날짜).
type Dated = Vec<(&'static str, dates::DateR)>;
fn got<'a>(d: &'a Dated, k: &str) -> Option<&'a dates::DateR> { d.iter().find(|(x, _)| *x == k).map(|(_, r)| r) }

/// `HT.readAlternatives(list, { mode, warn, base })` — 이설 목록 읽기 → `[{ start?, label, startAt?, end?, endAt?, ongoing?, birth? … , source?, note? }]`.
/// mode = 'item' | 'cell' | 'figure'. base(칸 · 인물) = 이 항목에 적힌 통설 값 — 한쪽만 적은 이설의 빈 쪽을 채우면 앞뒤가 뒤집히는 이설은 뺀다.
pub fn read_alternatives(ctx: &Ctx, list: &V, mode: &str, mut warn: Warn<'_>, base: Option<&V>) -> Vec<V> {
    let keys = alt_date_keys(mode);
    let mut out = Vec::new();
    let items = if let V::Arr(a) = list { a.to_vec() } else { Vec::new() };
    for (n, a) in items.iter().enumerate() {
        if !js::truthy(a) || !super::is_plain(a) { continue; }
        let tag = format!("이설 #{}", n + 1);
        let ongoing = matches!(a.get("ongoing"), V::Bool(true)) || dates::is_ongoing_text(&a.get("end"));
        let mut d: Dated = Vec::new();
        let mut bad: Option<&'static str> = None;
        for &k in keys {
            if k == "end" && ongoing { continue; }
            let Some(r) = dates::read_date(ctx, &a.get(k), &a.get(&format!("{k}At"))) else { continue };
            if r.t.is_nan() { bad = bad.or(Some(k)); } else { d.push((k, r)); }
        }
        let (label, source, note) = (dates::str_of(&a.get("label")), dates::str_of(&a.get("source")), dates::str_of(&a.get("note")));
        let dated = bad.is_some() || ongoing || keys.iter().any(|k| got(&d, k).is_some());
        if !dated {
            if label.is_empty() && source.is_empty() && note.is_empty() { say(&mut warn, format!("{tag}에 날짜도 근거도 없어 뺐습니다.")); continue; }
        } else if mode == "item" {
            // 항목: 시작이 있어야 한다(사건의 이설 막대 · 시대 띠의 고리가 시작을 씀). 읽을 수 없는 끝은 비운다
            if got(&d, "start").is_none() {
                say(&mut warn, if bad == Some("start") || !(got(&d, "end").is_some() || ongoing) { format!("{tag}의 연도를 읽을 수 없어 뺐습니다.") }
                    else { format!("{tag}에 시작이 없어 뺐습니다(항목의 이설은 시작부터 적습니다 — 근거만 적으려면 날짜를 모두 비웁니다).") });
                continue;
            }
            if bad == Some("end") { say(&mut warn, format!("{tag}의 끝을 읽을 수 없어 비웠습니다.")); }
        } else {
            // 칸 · 인물: 적은 쪽만 — 읽을 수 없는 날짜가 있으면 통째로 뺀다(빈 쪽이 통설 값으로 채워져 뜻이 바뀌지 않게)
            if let Some(b) = bad { say(&mut warn, format!("{tag}의 {}을 읽을 수 없어 뺐습니다.", alt_word(b))); continue; }
            let mut flipped = false;
            for (x, y) in [("start", "end"), ("birth", "death")] {
                if let (Some(dx), Some(dy)) = (got(&d, x), got(&d, y)) {
                    if dates::end_bound_t(ctx, dy.t, &opt_str(&dy.at)) < dx.t {
                        say(&mut warn, format!("{tag}의 {}이 {}보다 앞서 뺐습니다.", alt_word(y), alt_word(x)));
                        flipped = true;
                        break;
                    }
                }
            }
            if flipped { continue; }
            let flip = match base { Some(b) if js::truthy(b) => alt_flip_side(ctx, &d, ongoing, b, keys), _ => None };
            if let Some(f) = flip {
                say(&mut warn, format!("{tag}{}", alt_flip_text(f, if mode == "figure" { "이 인물" } else { "이 칸" })));
                continue;
            }
        }
        // 열쇠 차례는 예전 사건 · 시대의 꼴 그대로(start · label · startAt · end · endAt · ongoing · source · note)
        let o = Obj::new();
        if let Some(s) = got(&d, "start") { o.set("start", s.t); }
        o.set("label", if label.is_empty() { Str::from("다른 견해") } else { label });
        if let Some(at) = got(&d, "start").and_then(|s| s.at.clone()) { o.set("startAt", at); }
        if let Some(e) = got(&d, "end") {
            if mode != "item" || !js::strict_eq(&V::Num(e.t), &o.get("start")) {
                o.set("end", e.t); // 칸 · 인물은 시작과 같은 끝도 남긴다(비우면 통설의 끝으로 채워지므로)
                if let Some(at) = &e.at { o.set("endAt", at.clone()); }
            }
        }
        if ongoing { o.set("ongoing", true); }
        for k in ["birth", "death"] {
            let Some(r) = got(&d, k) else { continue };
            o.set(k, r.t);
            if let Some(at) = &r.at { o.set(&format!("{k}At"), at.clone()); }
        }
        if !source.is_empty() { o.set("source", source); }
        if !note.is_empty() { o.set("note", note); }
        out.push(V::Obj(o));
    }
    out
}
fn opt_str(s: &Option<Str>) -> V { s.clone().map_or(V::Null, V::Str) }

/// `HT.centuryRanges`의 입력 — 시작 · 끝(과 날짜 글)이 풀린 것.
pub struct Spans { pub start: Option<f64>, pub start_at: Option<Str>, pub end: Option<f64>, pub end_at: Option<Str>, pub start_range: bool, pub end_range: bool }
/// `HT.centuryRanges(x, spanned)` — 세기로 적은 시작 · 끝 → 연대 폭. 기간이 있는 것은 그 세기 구간이 곧 연대 폭이라
/// 적지 않은 연대 폭을 채우고 끝을 구간의 마지막 해로 옮긴다. 고칠 칸만 `{ startRange?, endRange?, end? }`.
pub fn century_ranges(ctx: &Ctx, x: &Spans, spanned: bool) -> Obj {
    let out = Obj::new();
    if !spanned { return out; }
    for key in ["start", "end"] {
        let (has_range, at, v) = if key == "start" { (x.start_range, &x.start_at, x.start) } else { (x.end_range, &x.end_at, x.end) };
        if has_range { continue; }
        let r = match at { Some(t) if !t.is_empty() => cal::parse(&ctx.cal, &V::Str(t.clone())), _ => None };
        let Some(r) = r else { continue };
        let (Some(span), Some(last)) = (r.span, r.last) else { continue };
        if !r.ok { continue; }
        if let Some(v) = v { if (v - r.t).abs() > 1e-6 && (v - last).abs() > 1e-6 { continue; } } // 날짜 글이 값과 맞지 않으면 건너뜀
        o_set_pair(&out, &format!("{key}Range"), span.0, last);
        if key == "end" { out.set("end", last); }
    }
    out
}
fn o_set_pair(o: &Obj, k: &str, a: f64, b: f64) { o.set(k, super::arr_of(vec![V::Num(a), V::Num(b)])); }

/// `HT.readUncertain(x, { mode, warn, start, end, base })` — 확실성 · 연대 폭 · 이설(· 쟁점) 읽기 — 항목과 칸이 같은 함수.
/// mode: 'item'(사건 · 시대 … — 옛 legendary · 쟁점도) · 'cell'(칸 — 통설은 적지 않음, 끝도 끝 연대 폭과 견줌) · 'figure' · 'epoch'(이설만).
/// → 적힌 것만 담은 `{ certainty?, startRange?, startRangeAt?, endRange?, endRangeAt?, (end?), alternatives?, debate? }`.
pub fn read_uncertain(ctx: &Ctx, x: &V, mode: &str, mut warn: Warn<'_>, start: Option<f64>, end: Option<f64>, base: Option<&V>) -> Obj {
    let out = Obj::new();
    if !js::truthy(x) || !super::is_plain(x) { return out; }
    if mode == "item" || mode == "cell" {
        let c = dates::str_of(&x.get("certainty"));
        if !c.is_empty() && vocab::CERTAINTY.iter().any(|(id, _)| c == *id) {
            if mode != "cell" || c != "accepted" { out.set("certainty", c); } // 칸의 통설은 기본값이라 적지 않는다
        } else if !c.is_empty() { say(&mut warn, format!("확실성 \"{c}\"을(를) 알 수 없어 무시했습니다.")); }
        else if mode == "item" && js::truthy(&x.get("legendary")) { out.set("certainty", "legend"); }
        for key in ["startRange", "endRange"] {
            let v = x.get(key);
            if v.is_nullish() || super::is_empty_str(&v) { continue; }
            let pair_in = match &v { V::Arr(a) if a.len() == 2 => a.to_vec(), _ => { say(&mut warn, format!("{key}는 [이른 연도, 늦은 연도] 형식이어야 합니다.")); continue; } };
            let atv = match x.get(&format!("{key}At")) { V::Arr(a) => a.to_vec(), _ => Vec::new() };
            let at = |i: usize| atv.get(i).cloned().unwrap_or_default();
            let da = dates::read_date(ctx, &pair_in[0], &at(0));
            let db = dates::read_date(ctx, &pair_in[1], &at(1));
            let (Some(da), Some(db)) = (da, db) else { say(&mut warn, format!("{key}의 연도를 읽을 수 없습니다.")); continue; };
            if da.t.is_nan() || db.t.is_nan() { say(&mut warn, format!("{key}의 연도를 읽을 수 없습니다.")); continue; }
            let pair = if da.t <= db.t { [(da.t, da.at), (db.t, db.at)] } else { [(db.t, db.at), (da.t, da.at)] };
            o_set_pair(&out, key, pair[0].0, pair[1].0);
            if pair.iter().any(|q| q.1.as_ref().is_some_and(|s| !s.is_empty())) {
                out.set(&format!("{key}At"), super::arr_of(pair.iter().map(|q| q.1.clone().filter(|s| !s.is_empty()).map_or(V::Null, V::Str)).collect()));
            }
        }
        let range = |k: &str| out.arr(k).map(|a| (a.get(0).as_num().unwrap_or(f64::NAN), a.get(1).as_num().unwrap_or(f64::NAN)));
        if let (Some((lo, hi)), Some(s)) = (range("startRange"), start) {
            if s < lo || s > hi { say(&mut warn, format!("대표 연대가 연대 폭({}~{}) 밖에 있습니다.", dates::format_year_t(lo), dates::format_year_t(hi))); }
        }
        if mode == "cell" {
            if let (Some((lo, hi)), Some(e)) = (range("endRange"), end) {
                if e < lo || e > hi { say(&mut warn, format!("끝이 끝 연대 폭({}~{}) 밖에 있습니다.", dates::format_year_t(lo), dates::format_year_t(hi))); }
            }
        }
    }
    // 세기로 적은 시작 · 끝 — 기간이 있는 것은 그 세기 구간이 곧 연대 폭
    if mode == "item" || mode == "cell" {
        let spanned = mode == "cell" || super::given(&x.get("end")) || matches!(x.get("ongoing"), V::Bool(true));
        let ds = dates::read_date(ctx, &x.get("start"), &x.get("startAt"));
        let de = dates::read_date(ctx, &x.get("end"), &x.get("endAt"));
        let spans = Spans {
            start: ds.as_ref().map(|d| d.t), start_at: ds.as_ref().and_then(|d| d.at.clone()),
            end: de.as_ref().map(|d| d.t), end_at: de.as_ref().and_then(|d| d.at.clone()),
            start_range: out.has("startRange"), end_range: out.has("endRange"),
        };
        for (k, v) in century_ranges(ctx, &spans, spanned).entries() { out.set(&k, v); }
    }
    let unk = |k: &str| dates::is_unknown_text(&x.get(k)) || matches!(x.get(&format!("{k}Unknown")), V::Bool(true));
    let cell_base;
    let alt_base = match mode {
        "cell" => match base {
            Some(b) if js::truthy(b) => Some(b),
            _ => {
                let o = Obj::new();
                o.set("start", start.map_or(V::Null, V::Num));
                o.set("end", end.map_or(V::Null, V::Num));
                o.set("startUnknown", unk("start"));
                o.set("endUnknown", unk("end"));
                cell_base = V::Obj(o);
                Some(&cell_base)
            }
        },
        "figure" => base,
        _ => None,
    };
    let alts = read_alternatives(ctx, &x.get("alternatives"), if mode == "epoch" { "item" } else { mode }, warn, alt_base);
    if !alts.is_empty() { out.set("alternatives", super::arr_of(alts)); }
    if mode == "item" {
        let debate = dates::str_of(&x.get("debate"));
        if !debate.is_empty() { out.set("debate", debate); }
    }
    out
}

/// 뒤집힌 짝 — 이설이 적은 쪽 · 통설로 채운 쪽.
#[derive(Debug, Clone, Copy)]
pub struct Flip { pub own: &'static str, pub other: &'static str }
/// `altFlipSide(d, ongoing, base, keys)` — 한쪽만 적은 이설의 빈 쪽을 통설 값으로 채우면 앞뒤가 뒤집히는가. 통설이 미정인 쪽으로 채우는 짝은 견주지 않는다.
/// 몸은 [`super::alts::alt_flip_side`] 하나(과제 Y가 모음 · 16b가 읽기 층으로 옮김): 읽은 날짜 칸 `d`를 JS의 `{ 칸: { t, at } }`로 넘긴다.
/// 통설 값(base[x] · base[y])은 JS 값 그대로 — 원본처럼 `HT.endBound`에 그대로 넘기고(글 '1600'은 그해 끝으로 올리지 않음) `isFinite` · `<`로 견준다.
fn alt_flip_side(ctx: &Ctx, d: &Dated, ongoing: bool, base: &V, keys: &[&str]) -> Option<Flip> {
    let o = Obj::new();
    for (k, r) in d {
        let x = Obj::new();
        x.set("t", r.t);
        x.set("at", opt_str(&r.at));
        o.set(*k, x);
    }
    super::alts::alt_flip_side(ctx, &o, ongoing, base, keys).map(|(own, other)| Flip { own, other })
}
/// `altFlipText(f, who)` — 뒤집혀 뺀 까닭의 글(인물은 활동 시작 · 활동 끝).
fn alt_flip_text(f: Flip, who: &str) -> String {
    let w = |k: &str| if who == "이 인물" { fig_word(k) } else { alt_word(k) };
    format!("의 {}이 {who}의 {}보다 {} 뺐습니다(비운 {}은 {who}의 연대로 채웁니다).", w(f.own), w(f.other), if f.own == "start" || f.own == "birth" { "늦어" } else { "앞서" }, w(f.other))
}

/// `vocab(list, words)(v)` — 표의 id · 이름이나 낱말(빈칸을 뺀 글 · 제 낱말만) → id(모르면 '').
pub fn vocab(list: &[(&str, &str)], words: &[(&str, &str)], v: &V) -> Str {
    let s = js::to_str(&js::nullish(v.clone(), V::from(""))).trim();
    if s.is_empty() { return Str::default(); }
    if let Some((id, _)) = list.iter().find(|(id, name)| s == *id || s == *name) { return Str::from(*id); }
    let k: String = s.as_str().chars().filter(|c| !js::is_space(*c)).collect(); // s.replace(/\s+/g, '')
    words.iter().find(|(w, _)| *w == k).map_or(Str::default(), |(_, id)| Str::from(*id))
}

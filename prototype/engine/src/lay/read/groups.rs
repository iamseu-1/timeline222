//! `js/core.js` 1880 ~ 2426줄 가운데 읽기가 쓰는 것 — 단체 · 주제 사전 · 제도 칸 · 사건의 주제 · 법 · 선거 — 한 벌 P3 과제 5c.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 1886 ~ 1903줄 `HT.GROUP_TYPES` · `HT.GROUP_HOWS` · `HT.LAW_ACTS` · 1905 ~ 1907줄 `GROUP_TYPE_WORDS` · `GROUP_HOW_WORDS` · `LAW_ACT_WORDS` ·
//!   1909 ~ 1911줄 `HT.groupType` · `HT.groupHow` · `HT.lawAct`(= `vocab(…)` — `read::cells::vocab`)
//! - 1928 ~ 1963줄 `HT.readThemeDefs`
//! - 1992줄 `HT.readThemeList`(쉼표 가름 `/[,，]/`은 코드 단위로 — `read::split_units`)
//! - 2218 ~ 2235줄 `HT.readLaw`(`/\r?\n/` 가름 · `/\r/g` 지우기는 손으로 — `read::split_crlf` · `read::drop_units`)
//! - 2237 ~ 2271줄 `HT.readElection`(`/[,，\s]/g` 지우기 · `/^(true|예|네|당선|이김|승리)$/i`는 손으로 — `won_word`)
//! - 2275 ~ 2326줄 `HT.readPolityRows` · 2328줄 `HT.compactPolityRows` · 2330 ~ 2351줄 `HT.readGroupFrom` · 2353 ~ 2359줄 `HT.readInstPolity` ·
//!   2363 ~ 2426줄 `HT.readInstSpans`
//!
//! 옮기지 않은 것(뒤 과제 — 모델 · 화면): `HT.THEMES`(내장 주제 뼈대 — 모델의 `HT.mergeThemes`가 씀) · `HT.mergeThemes` · `HT.findTheme` · 렌즈(1994 ~ 2216줄) ·
//! 보일 이름(`HT.groupTypeName` …).
use super::{cells, dates, misc, names, Ctx};
use crate::lay::js::{self, Obj, Str, V};

/// `HT.GROUP_TYPES`(단체 종류 — id, 이름).
pub const GROUP_TYPES: [(&str, &str); 5] = [("faction", "붕당·파벌"), ("party", "정당"), ("regime", "정권·실권 집단"), ("bloc", "세력"), ("coalition", "연합·동맹")];
/// `HT.GROUP_HOWS`(앞선 단체에서 이어진 방식).
pub const GROUP_HOWS: [(&str, &str); 4] = [("split", "갈라짐"), ("merge", "합쳐짐"), ("rename", "이름 바꿈"), ("unknown", "미상")];
/// `HT.LAW_ACTS`(법의 고침 종류).
pub const LAW_ACTS: [(&str, &str); 3] = [("enact", "제정"), ("amend", "개정"), ("repeal", "폐지")];
/// `GROUP_TYPE_WORDS`.
const GROUP_TYPE_WORDS: [(&str, &str); 12] = [
    ("붕당", "faction"), ("파벌", "faction"), ("당파", "faction"), ("정당", "party"), ("정권", "regime"), ("실권", "regime"), ("실권집단", "regime"), ("세력", "bloc"),
    ("연합", "coalition"), ("동맹", "coalition"), ("연합세력", "coalition"), ("연맹", "coalition"),
];
/// `GROUP_HOW_WORDS`.
const GROUP_HOW_WORDS: [(&str, &str); 16] = [
    ("분열", "split"), ("분당", "split"), ("갈라져나옴", "split"), ("갈라섬", "split"), ("합류", "merge"), ("통합", "merge"), ("합당", "merge"), ("합침", "merge"),
    ("이름바꿈", "rename"), ("개칭", "rename"), ("개명", "rename"), ("바뀐이름", "rename"), ("방식미상", "unknown"), ("모름", "unknown"), ("불명", "unknown"), ("?", "unknown"),
];
/// `LAW_ACT_WORDS`.
const LAW_ACT_WORDS: [(&str, &str); 8] = [
    ("공포", "enact"), ("반포", "enact"), ("신설", "enact"), ("수정", "amend"), ("개편", "amend"), ("폐기", "repeal"), ("철폐", "repeal"), ("혁파", "repeal"),
];
/// `HT.groupType(v)` — 단체 종류: id나 한국어 → id(모르면 '').
pub fn group_type(v: &V) -> Str { cells::vocab(&GROUP_TYPES, &GROUP_TYPE_WORDS, v) }
/// `HT.groupHow(v)` — 이어진 방식: id나 한국어 → id(모르면 '').
pub fn group_how(v: &V) -> Str { cells::vocab(&GROUP_HOWS, &GROUP_HOW_WORDS, v) }
/// `HT.lawAct(v)` — 법의 고침 종류: id나 한국어 → id(모르면 '').
pub fn law_act(v: &V) -> Str { cells::vocab(&LAW_ACTS, &LAW_ACT_WORDS, v) }

/// `HT.readThemeDefs`의 답 `{ list, problems, at }` — `at[k]`는 `problems[k]`가 가리키는 줄의 차례(목록 전체의 것이면 None — JS의 undefined).
#[derive(Debug, Default)]
pub struct ThemeDefs { pub list: Vec<V>, pub problems: Vec<String>, pub at: Vec<Option<usize>> }
/// `HT.readThemeDefs(v)` — 주제 사전 원문 → `{ list, problems, at }`(지위 사전 `HT.readRankDefs`와 같은 꼴): id가 없으면 이름으로 만들고(theme-…),
/// 같은 id가 또 나오면 뒤의 것을 뺀다. 이름 없이 `{ id, hidden: true }`만 적은 줄(내장 · 다른 DLC의 주제를 숨기기만)도 받는다.
pub fn read_theme_defs(ctx: &Ctx, v: &V) -> ThemeDefs {
    let s = dates::str_of;
    let mut r = ThemeDefs::default();
    let bad = |r: &mut ThemeDefs, i: Option<usize>, msg: String| { r.problems.push(msg); r.at.push(i); };
    if !v.is_nullish() && !super::is_empty_str(v) && !matches!(v, V::Arr(_)) { bad(&mut r, None, "주제 사전(themes)은 목록이어야 해서 무시했습니다.".into()); }
    for (i, d) in dates::arr(v).iter().enumerate() {
        if !js::truthy(d) || !super::is_plain(d) { bad(&mut r, Some(i), format!("주제 사전 #{}: 형식이 올바르지 않아 뺐습니다.", i + 1)); continue; }
        let name = s(&d.get("name"));
        // 렌즈에서 숨김(hidden: true): 이름 없이 { id, hidden: true }만 적은 줄도 받는다 — 내장 · 다른 DLC의 주제를 숨기기만 하는 줄
        let hide = matches!(d.get("hidden"), V::Bool(true));
        if name.is_empty() && !(hide && !s(&d.get("id")).is_empty()) { bad(&mut r, Some(i), format!("주제 사전 #{}: 이름이 없어 뺐습니다.", i + 1)); continue; }
        let mut id = s(&d.get("id"));
        if !id.is_empty() && !dates::id_ok(&id) {
            if name.is_empty() { bad(&mut r, Some(i), format!("주제 사전 #{}: id \"{id}\"가 올바르지 않아 뺐습니다 (이름 없이 숨김만 적은 줄).", i + 1)); continue; }
            bad(&mut r, Some(i), format!("주제 사전 \"{name}\": id \"{id}\"가 올바르지 않아 새로 만들었습니다."));
            id = Str::default();
        }
        if id.is_empty() { id = super::cat(&[&Str::from("theme-"), &misc::hash(&name)]); }
        if r.list.iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) {
            bad(&mut r, Some(i), format!("주제 사전 \"{}\": id \"{id}\"가 중복되어 뺐습니다.", if name.is_empty() { &id } else { &name }));
            continue;
        }
        let o = Obj::new();
        o.set("id", id);
        if !name.is_empty() { o.set("name", name.clone()); }
        if hide { o.set("hidden", true); }
        if name.is_empty() { r.list.push(V::Obj(o)); continue; } // 숨김만 적은 줄 — 색 · 설명 · 이름 목록은 이름이 있는 정의(내장 · 다른 DLC)의 것
        if misc::is_color(&d.get("color")) { o.set("color", d.get("color")); }
        for k in ["kind", "description"] {
            let t = s(&d.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        let mut msgs = Vec::new();
        let list = names::read_names(ctx, &d.get("names"), &mut |m| msgs.push(m)); // 이름 목록(주제의 원어 · 다른 이름 — 형식 3 F1과 같은 읽기)
        for m in msgs { bad(&mut r, Some(i), format!("주제 사전 \"{name}\": {m}")); }
        if !list.is_empty() { o.set("names", super::arr_of(list)); }
        r.list.push(V::Obj(o));
    }
    r
}

/// `HT.readThemeList(v)` — 사건의 주제 꼬리표: 목록 · 글 하나(쉼표로 여럿) → 빈 것 · 겹친 것을 뺀 목록(객체 · 배열 원소는 빈 것으로 봄).
pub fn read_theme_list(v: &V) -> Vec<Str> {
    let items: Vec<V> = match v {
        V::Arr(a) => a.to_vec(),
        x if x.is_nullish() => Vec::new(),
        x => super::split_units(&js::to_str(x), &[0x2C, 0xFF0C]).into_iter().map(V::Str).collect(),
    };
    let mut out: Vec<Str> = Vec::new();
    for x in &items {
        let t = if x.is_nullish() || js::type_of(x) == "object" { Str::default() } else { js::to_str(x).trim() };
        if !t.is_empty() && !out.contains(&t) { out.push(t); }
    }
    out
}

/// `HT.readLaw(raw, warn)` — 법 규격 `{ name?, act?, articles?: [글], note? }` → 적은 칸만(없으면 None — 보통 사건). 조항은 글 목록(여러 줄 글 하나도 줄마다 나눔).
pub fn read_law(raw: &V, warn: &mut dyn FnMut(String)) -> Option<Obj> {
    if !js::truthy(raw) || !super::is_plain(raw) { return None; }
    let s = dates::str_of;
    let o = Obj::new();
    let name = s(&raw.get("name"));
    if !name.is_empty() { o.set("name", name); }
    let act = raw.get("act");
    if !s(&act).is_empty() {
        let a = law_act(&act);
        if !a.is_empty() { o.set("act", a); } else { warn(format!("법의 고침 종류 \"{}\"을(를) 알 수 없어 뺐습니다 (제정 · 개정 · 폐지).", s(&act))); }
    }
    let arts_in: Vec<V> = match raw.get("articles") {
        V::Arr(a) => a.to_vec(),
        V::Str(t) => super::split_crlf(&t).into_iter().map(V::Str).collect(),
        _ => Vec::new(),
    };
    let arts: Vec<V> = arts_in
        .iter()
        .map(|a| match a {
            V::Str(_) | V::Num(_) => js::to_str(a),
            x if js::truthy(x) && js::type_of(x) == "object" => {
                let parts: Vec<Str> = ["no", "title", "text"].iter().map(|k| s(&x.get(*k))).filter(|t| !t.is_empty()).collect();
                Str::join(&parts, " ")
            }
            _ => Str::default(),
        })
        .map(|t| super::drop_units(&t, &[0x0D]).trim())
        .filter(|t| !t.is_empty())
        .map(V::Str)
        .collect();
    if !arts.is_empty() { o.set("articles", super::arr_of(arts)); }
    let note = s(&raw.get("note"));
    if !note.is_empty() { o.set("note", note); }
    if o.is_empty() { None } else { Some(o) }
}

/// `/^(true|예|네|당선|이김|승리)$/i`(선거 결과의 당선) — 손으로: 글 전체가 낱말 하나(`i`는 ASCII 글자만 접음 — 'true'만 닿음).
fn won_word(t: &Str) -> bool {
    let Some(s) = t.exact() else { return false };
    s.eq_ignore_ascii_case("true") || matches!(s, "예" | "네" | "당선" | "이김" | "승리")
}
/// `HT.readElection(raw, warn)` — 선거 규격 `{ office?, results?: [{ who, votes?, seats?, won? }], note? }` → 적은 칸만(없으면 None).
/// 득표 · 의석은 수(쉼표 섞인 글도), won은 참이면 당선.
pub fn read_election(raw: &V, warn: &mut dyn FnMut(String)) -> Option<Obj> {
    if !js::truthy(raw) || !super::is_plain(raw) { return None; }
    let s = dates::str_of;
    // num(v): 비면 None · 읽지 못하거나 음수면 Some(NaN) — `Number(String(v).replace(/[,，\s]/g, ''))`
    let num = |v: &V| -> Option<f64> {
        if v.is_nullish() || super::is_empty_str(v) { return None; }
        let t = js::to_str(v);
        let kept: Vec<u16> = t.units().filter(|&c| c != 0x2C && c != 0xFF0C && !char::from_u32(u32::from(c)).is_some_and(js::is_space)).collect();
        let n = js::to_num(&V::Str(Str::from_units(&kept)));
        Some(if n.is_finite() && n >= 0.0 { n } else { f64::NAN })
    };
    let o = Obj::new();
    let office = s(&raw.get("office"));
    if !office.is_empty() { o.set("office", office); }
    let rows: Vec<V> = match raw.get("results") { V::Arr(a) => a.to_vec(), x if js::truthy(&x) && js::type_of(&x) == "object" => vec![x], _ => Vec::new() };
    let mut results = Vec::new();
    for (i, r) in rows.iter().enumerate() {
        let x = match r {
            V::Str(_) => { let x = Obj::new(); x.set("who", r.clone()); V::Obj(x) }
            V::Arr(a) => {
                let x = Obj::new();
                x.set("who", a.get(0));
                x.set("votes", a.get(1));
                x.set("seats", a.get(2));
                x.set("won", a.get(3));
                V::Obj(x)
            }
            r if js::truthy(r) && js::type_of(r) == "object" => r.clone(),
            _ => continue,
        };
        let who = s(&js::nullish(x.get("who"), x.get("name")));
        if who.is_empty() {
            if ["votes", "seats"].iter().any(|k| !s(&x.get(*k)).is_empty()) || matches!(x.get("won"), V::Bool(true)) { warn(format!("선거 결과 #{}: 누구(who)가 없어 뺐습니다.", i + 1)); }
            continue;
        }
        let q = Obj::new();
        q.set("who", who.clone());
        for (k, word) in [("votes", "득표"), ("seats", "의석")] {
            match num(&x.get(k)) {
                None => {}
                Some(n) if n.is_nan() => warn(format!("선거 결과 \"{who}\"의 {word} \"{}\"을(를) 읽을 수 없어 뺐습니다.", s(&x.get(k)))),
                Some(n) => q.set(k, n),
            }
        }
        if matches!(x.get("won"), V::Bool(true)) || won_word(&s(&x.get("won"))) { q.set("won", true); }
        results.push(V::Obj(q));
    }
    if !results.is_empty() { o.set("results", super::arr_of(results)); }
    let note = s(&raw.get("note"));
    if !note.is_empty() { o.set("note", note); }
    if o.is_empty() { None } else { Some(o) }
}

/// `HT.readScopeRef(x)`의 답을 JS 객체로(`{ track?, polity }`).
fn scope_ref_obj(r: &cells::ScopeRef) -> V {
    let o = Obj::new();
    if let Some(t) = &r.track { o.set("track", t.clone()); }
    o.set("polity", r.polity.clone());
    V::Obj(o)
}
/// `HT.readPolityRows(v, { role, warn, what })` — 단체가 있던 나라(within) · 연합의 구성 나라(members)의 줄: 이름(또는 id) 글 · "트랙:이름" 글 ·
/// `{ track?, polity, start?, end?, role?, note? }` → `[{ track?, polity, start?(+At · Unknown), end?(+At · Unknown), role?, note? }]`. 기간에 "미정"도 된다(칸의 미정).
/// role(연합 안에서의 자리)은 `role`일 때만. 트랙은 여기서 검사하지 않는다(다른 DLC · 기본팩의 트랙일 수 있음).
pub fn read_polity_rows(ctx: &Ctx, v: &V, role: bool, warn: &mut dyn FnMut(String), what: &str) -> Vec<V> {
    let s = dates::str_of;
    let mut out = Vec::new();
    for (i, x) in super::listed(v).iter().enumerate() {
        let r = match x {
            V::Str(_) => cells::read_scope_ref(x).map(|r| scope_ref_obj(&r)),
            x if js::truthy(x) && super::is_plain(x) => Some(x.clone()),
            _ => None,
        };
        let Some(r) = r else {
            if super::given(x) { warn(format!("{what} #{}: 꼴이 올바르지 않아 뺐습니다.", i + 1)); }
            continue;
        };
        let mut track = s(&r.get("track"));
        let mut polity = s(&js::nullish(r.get("polity"), r.get("name")));
        if track.is_empty() && !polity.is_empty() {
            // 트랙 칸을 비운 채 "트랙:이름"을 적었으면 둘로 나눈다(대범위 · 조약 당사국과 같은 규칙)
            if let Some(cells::ScopeRef { track: Some(t), polity: p }) = cells::read_scope_ref(&V::Str(polity.clone())) { track = t; polity = p; }
        }
        if polity.is_empty() {
            warn(format!("{what} #{}: 나라가 비어 있어 뺐습니다.", i + 1));
            continue;
        }
        let o = Obj::new();
        if !track.is_empty() { o.set("track", track); }
        o.set("polity", polity.clone());
        for k in ["start", "end"] {
            match cells::read_cell_edge(ctx, &r, k) {
                None => {}
                Some(cells::Edge::Unknown(t)) => {
                    if let Some(t) = t { o.set(k, t); }
                    o.set(&format!("{k}Unknown"), true);
                }
                Some(cells::Edge::Date(d)) if d.t.is_nan() => {
                    let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" {e}"));
                    warn(format!("{what} \"{polity}\"의 {}을 읽을 수 없어 비웠습니다.{why}", if k == "start" { "시작" } else { "끝" }));
                }
                Some(cells::Edge::Date(d)) => {
                    o.set(k, d.t);
                    if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
                }
            }
        }
        if !o.get("start").is_nullish() && !o.get("end").is_nullish() && dates::end_bound_t(ctx, o.num("end"), &o.get("endAt")) < o.num("start") {
            // 거꾸로면 짐작인 쪽을 버린다(활동 기록과 같은 규칙): 시작만 미정이면 시작의 배치용 연도, 아니면 끝
            if o.bool("startUnknown") && !o.bool("endUnknown") { o.delete("start"); }
            else { o.delete("end"); o.delete("endAt"); }
            warn(format!("{what} \"{polity}\"의 끝이 시작보다 앞서 {} 버렸습니다.", if o.get("start").is_nullish() { "시작의 배치용 연도를" } else { "끝을" }));
        }
        if role {
            let t = s(&r.get("role"));
            if !t.is_empty() { o.set("role", t); }
        }
        let note = s(&r.get("note"));
        if !note.is_empty() { o.set("note", note); }
        out.push(V::Obj(o));
    }
    out
}
/// `HT.compactPolityRows(list)` — 줄이 하나뿐이고 이름만 있으면 글 하나로 줄여 적는다(소속 `HT.compactPartOf`와 같은 규칙).
pub fn compact_polity_rows(list: Vec<V>) -> V { cells::compact_part_of(list) }

/// `HT.readGroupFrom(v, warn)` — 단체의 앞선 단체(from): 글(단체 이름 · id) · `{ group, how?, note? }` → `[{ group, how?, note? }]` — 같은 단체를 두 번 적으면 첫 줄만.
pub fn read_group_from(v: &V, warn: &mut dyn FnMut(String)) -> Vec<V> {
    let s = dates::str_of;
    let mut out: Vec<Obj> = Vec::new();
    for (i, x) in super::listed(v).iter().enumerate() {
        let r = match x {
            V::Str(_) => { let r = Obj::new(); r.set("group", x.clone()); Some(V::Obj(r)) }
            x if js::truthy(x) && super::is_plain(x) => Some(x.clone()),
            _ => None,
        };
        let group = r.as_ref().map_or(Str::default(), |r| s(&js::nullish(r.get("group"), r.get("name"))));
        let Some(r) = r.filter(|_| !group.is_empty()) else {
            if super::given(x) { warn(format!("앞선 단체 #{}: 단체가 비어 있어 뺐습니다.", i + 1)); }
            continue;
        };
        if out.iter().any(|y| js::strict_eq(&y.get("group"), &V::Str(group.clone()))) {
            warn(format!("앞선 단체 \"{group}\"이(가) 두 번 적혀 있어 첫 줄만 씁니다."));
            continue;
        }
        let o = Obj::new();
        o.set("group", group.clone());
        let how = r.get("how");
        if !s(&how).is_empty() {
            let h = group_how(&how);
            if !h.is_empty() { o.set("how", h); }
            else { warn(format!("앞선 단체 \"{group}\": 이어진 방식 \"{}\"을(를) 알 수 없어 뺐습니다 (갈라짐 · 합쳐짐 · 이름 바꿈).", s(&how))); }
        }
        let note = s(&r.get("note"));
        if !note.is_empty() { o.set("note", note); }
        out.push(o);
    }
    out.into_iter().map(V::Obj).collect()
}

/// `HT.readInstPolity(polity, track)` — 제도 칸의 나라: 글(이름 · id · "트랙:이름") · `{ track, polity }` + 제도의 track → `{ track?, polity }`(없으면 None).
/// 객체에 적은 트랙이 제도의 track보다 먼저.
pub fn read_inst_polity(polity: &V, track: &V) -> Option<Obj> {
    let s = dates::str_of;
    let (rt, rp) = match polity {
        V::Str(_) => cells::read_scope_ref(polity).map(|r| (r.track.unwrap_or_default(), r.polity))?,
        x if js::truthy(x) && super::is_plain(x) => (s(&x.get("track")), s(&js::nullish(x.get("polity"), x.get("name")))),
        _ => return None,
    };
    if rp.is_empty() { return None; }
    let t = if !rt.trim().is_empty() { rt.trim() } else { s(track) };
    let o = Obj::new();
    if !t.is_empty() { o.set("track", t); }
    o.set("polity", rp);
    Some(o)
}

/// `HT.readInstSpans`의 답 `{ list, problems, warnings }`.
#[derive(Debug, Default)]
pub struct InstSpans { pub list: Vec<V>, pub problems: Vec<String>, pub warnings: Vec<String> }
/// `HT.readInstSpans(v)` — 제도 칸(spans) 원문 → `{ list, problems: 뺀 것의 글, warnings: 참고할 것의 글 }`. 칸은 연호와 같은 꼴 `[이름, 시작, 끝, 메모]` ·
/// `{ name, start, end, note, from? }`. 비운 시작 · 끝은 시기 구분과 같은 규칙(자리는 모델이). 시작 · 끝에 "미정"도 된다(칸의 미정).
/// from = 다른 나라의 제도에서 옴(전파): `{ track?, polity, name? }` 또는 "나라" · "트랙:나라" 글.
pub fn read_inst_spans(ctx: &Ctx, v: &V) -> InstSpans {
    let s = dates::str_of;
    let mut problems = Vec::new();
    let mut warnings = Vec::new();
    let mut out: Vec<V> = Vec::new();
    if !v.is_nullish() && !super::is_empty_str(v) && !matches!(v, V::Arr(_)) { problems.push("제도 칸(spans)은 목록이어야 해서 무시했습니다.".to_string()); }
    'cells: for (i, c) in dates::arr(v).iter().enumerate() {
        let x = match c {
            V::Arr(a) => cells::cell_of_tuple(a),
            V::Str(_) => { let o = Obj::new(); o.set("name", c.clone()); V::Obj(o) }
            c if js::truthy(c) && js::type_of(c) == "object" => c.clone(),
            _ => { problems.push(format!("제도 칸 {}번째: 꼴이 올바르지 않아 뺐습니다.", i + 1)); continue; }
        };
        let name = s(&js::nullish(x.get("name"), x.get("title")));
        if name.is_empty() { problems.push(format!("제도 칸 {}번째: 이름이 없어 뺐습니다.", i + 1)); continue; }
        let o = Obj::new();
        o.set("name", name.clone());
        for k in ["start", "end"] {
            match cells::read_cell_edge(ctx, &x, k) {
                Some(cells::Edge::Unknown(t)) => {
                    if let Some(t) = t { o.set(k, t); }
                    o.set(&format!("{k}Unknown"), true);
                }
                Some(cells::Edge::Date(d)) if d.t.is_nan() => {
                    let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" ({e})"));
                    problems.push(format!("제도 칸 \"{name}\"의 {}을 읽을 수 없어 그 칸을 뺐습니다.{why}", if k == "start" { "시작" } else { "끝" }));
                    continue 'cells;
                }
                Some(cells::Edge::Date(d)) => {
                    o.set(k, d.t);
                    if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
                }
                None => {}
            }
        }
        let mut end_dropped = false;
        if !o.get("start").is_nullish() && !o.get("end").is_nullish() && dates::end_bound_t(ctx, o.num("end"), &o.get("endAt")) < o.num("start") {
            if o.bool("startUnknown") && !o.bool("endUnknown") {
                warnings.push(format!("제도 칸 \"{name}\"의 끝이 시작보다 앞서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로)."));
                o.delete("start");
            } else {
                warnings.push(format!("제도 칸 \"{name}\"의 끝이 시작보다 앞서 끝을 비웠습니다(다음 칸까지로 봄)."));
                o.delete("end");
                o.delete("endAt");
                end_dropped = true; // 아래 연대 폭 읽기가 세기 글의 끝("3세기 말")을 되살리지 않게 — 알림과 파일이 같게
            }
        }
        let note = s(&x.get("note"));
        if !note.is_empty() { o.set("note", note); }
        let from = x.get("from");
        if !from.is_nullish() && !super::is_empty_str(&from) {
            let arg = if super::is_plain(&from) {
                let a = Obj::new();
                a.set("track", from.get("track"));
                a.set("polity", from.get("polity"));
                V::Obj(a)
            } else { from.clone() };
            match read_inst_polity(&arg, &V::from("")) {
                None => warnings.push(format!("제도 칸 \"{name}\": 온 곳(from)에 나라가 없어 뺐습니다.")),
                Some(f) => {
                    if js::truthy(&from) && js::type_of(&from) == "object" {
                        let fname = s(&from.get("name"));
                        if !fname.is_empty() { f.set("name", fname); }
                    }
                    o.set("from", f);
                }
            }
        }
        let (start, end) = (o.get("start").as_num(), o.get("end").as_num());
        let unc = cells::read_uncertain(ctx, &x, "cell", Some(&mut |m: String| warnings.push(format!("제도 칸 \"{name}\" — {m}"))), start, end, None); // 확실성 · 연대 폭 · 이설
        if end_dropped { for k in ["end", "endAt", "endRange", "endRangeAt"] { unc.delete(k); } }
        for (k, v) in unc.entries() { o.set(&k, v); }
        out.push(V::Obj(o));
    }
    // 차례: 적힌 시작 순으로(시작을 비운 칸은 바로 앞에 적힌 칸 뒤에 그대로 — 시기 구분과 같음) · 겹치면 알림
    let mut key = f64::NEG_INFINITY;
    let mut rows: Vec<(V, f64, f64)> = out
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
    let list: Vec<V> = rows.into_iter().map(|r| r.0).collect();
    for pair in list.windows(2) {
        let (a, b) = (&pair[0], &pair[1]);
        let (a_start, a_end, b_start) = (a.get("start"), a.get("end"), b.get("start"));
        if (!a_end.is_nullish() && !b_start.is_nullish() && js::to_num(&a_end) > js::to_num(&b_start)) || (!a_start.is_nullish() && js::strict_eq(&a_start, &b_start)) {
            warnings.push(format!("제도 칸 \"{}\"와(과) \"{}\"이(가) 겹칩니다.", js::to_str(&a.get("name")), js::to_str(&b.get("name"))));
        }
    }
    InstSpans { list, problems, warnings }
}

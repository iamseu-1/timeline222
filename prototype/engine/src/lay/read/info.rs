//! `js/core.js` 3360 ~ 3841줄 — 팩 정보의 새 칸 · 모아 보기 판 · 지도 · 글꼴 읽기 — 한 벌 P3 과제 5a · 5c(지도 · 글꼴).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 3360 ~ 3361줄 `DAY_RE` · `COVER_RE`(손으로 — 아래 함수의 주석)
//! - 3364 ~ 3440줄 `HT.readPackInfo`
//! - 3448줄 `HT.VIEW_DENSITIES`
//! - 3452 ~ 3468줄 `ownId`
//! - 3471 ~ 3500줄 `readSpan`
//! - 3503 ~ 3534줄 `HT.readViewSettings`(표시 열쇠는 102 ~ 108줄 `HT.SHOW_DEFAULTS`의 열쇠)
//! - 3538 ~ 3563줄 `HT.readViews`
//! - (5c) 3450줄 `HT.MAP_CRS` · 3565 ~ 3571줄 `readMapImage` · 3575 ~ 3601줄 `readShape` · 3610 ~ 3759줄 `HT.readMaps`(`/^none$/i`는 손으로)
//! - (5c) 3761 ~ 3774줄 `FONT_RE`(손으로 — `font_parts`) · `B64` · `fontHead` · `FONT_HEADS` · 3777 ~ 3836줄 `HT.readFonts`(`/^[A-Za-z]{4}$/`는 손으로 · 글자 범위는
//!   `read::names::parse_range` · `range_text`)
//!
//! 옮기지 않은 것: `FONT_FORMATS` · `HT.fontFormat`(화면 — CSS의 format() 이름).
use super::{cells, dates, misc, names, vocab, Ctx};
use crate::lay::js::{self, Obj, Str, V};
use std::collections::HashSet;

/// `DAY_RE.test(s)` — `/^\d{4}-\d{2}-\d{2}$/`.
fn day_ok(s: &Str) -> bool {
    let Some(t) = s.exact() else { return false };
    let b = t.as_bytes();
    b.len() == 10 && b[4] == b'-' && b[7] == b'-' && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}
/// `COVER_RE.test(s)` — `/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/`: 머리 · base64 글자 하나 이상 · '='는 끝에 둘까지.
pub(super) fn cover_ok(s: &Str) -> bool {
    let Some(t) = s.exact() else { return false };
    let Some(rest) = ["data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,"].iter().find_map(|h| t.strip_prefix(h)) else { return false };
    let body = rest.trim_end_matches('=');
    rest.len() - body.len() <= 2 && !body.is_empty() && body.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/')
}

/// `HT.readPackInfo(raw, warn, selfId)` — 팩 정보의 새 칸(분류 · 태그 · 짧은 소개 · 볼거리 · 표지 · 관계 · 판 기록 · 만든 날 · 반영한 날)을 읽어 **적은 것만** 돌려준다.
/// 고친 것은 `warn`으로 알린다. selfId = 이 팩의 id(자기를 가리키는 관계는 버림).
pub fn read_pack_info(raw: &V, warn: &mut dyn FnMut(String), self_id: &Str) -> Obj {
    let l = &vocab::PACK_LIMITS;
    let info = Obj::new();
    let cut = |s: Str, n: usize, what: &str, warn: &mut dyn FnMut(String)| -> Str {
        if s.len16() <= n { return s; }
        warn(format!("{what}이(가) {n}자를 넘어 뒤를 잘랐습니다."));
        s.slice16(0.0, n as f64)
    };
    let category = raw.get("category");
    if super::given(&category) {
        let c = dates::str_of(&category);
        if vocab::PACK_CATEGORIES.iter().any(|x| c == *x) { info.set("category", c); } else { warn(format!("알 수 없는 분류 «{c}» — 분류 없이 읽습니다.")); }
    }
    let tags_raw = raw.get("tags");
    if !tags_raw.is_nullish() {
        let mut tags: Vec<Str> = Vec::new();
        let cut_all: Vec<Str> = dates::arr(&tags_raw).iter().map(|t| cut(dates::str_of(t), l.tag_len, "태그", warn)).collect();
        for t in cut_all { if !t.is_empty() && !tags.contains(&t) { tags.push(t); } }
        if tags.len() > l.tags { warn(format!("태그는 {0}개까지 — 앞의 {0}개만 남겼습니다.", l.tags)); }
        if !tags.is_empty() { info.set("tags", super::arr_of(tags.into_iter().take(l.tags).map(V::Str).collect())); }
    }
    let summary = dates::str_of(&raw.get("summary"));
    if !summary.is_empty() { info.set("summary", cut(summary, l.summary, "짧은 소개", warn)); }
    let highlights = raw.get("highlights");
    if !highlights.is_nullish() {
        let hs: Vec<Str> = dates::arr(&highlights).iter().map(|h| cut(dates::str_of(h), l.highlight_len, "볼거리 한 줄", warn)).filter(|h| !h.is_empty()).collect();
        if hs.len() > l.highlights { warn(format!("볼거리는 {0}줄까지 — 앞의 {0}줄만 남겼습니다.", l.highlights)); }
        if !hs.is_empty() { info.set("highlights", super::arr_of(hs.into_iter().take(l.highlights).map(V::Str).collect())); }
    }
    let cover = raw.get("cover");
    if super::given(&cover) {
        let c = if let V::Str(s) = &cover { s.trim() } else { Str::default() };
        if c.len16() > l.cover { warn("표지 그림이 너무 커서(1.5MB 넘음) 뺐습니다.".into()); }
        else if !cover_ok(&c) { warn("표지가 그림(png · jpeg · webp)이 아니어서 뺐습니다.".into()); }
        else { info.set("cover", c); }
    }
    let relations = raw.get("relations");
    if !relations.is_nullish() {
        let mut seen: HashSet<String> = HashSet::new();
        let mut rel = Vec::new();
        for r in dates::arr(&relations) {
            let kind = dates::str_of(&super::and(&r, "type"));
            let id = dates::str_of(&super::and(&r, "id"));
            if !vocab::PACK_RELATIONS.iter().any(|x| kind == *x) {
                warn(format!("관계 종류 «{kind}»를 몰라 그 줄을 뺐습니다."));
                continue;
            }
            if !dates::id_ok(&id) || id == *self_id {
                warn(format!("관계의 팩 id «{id}»가 올바르지 않아 그 줄을 뺐습니다."));
                continue;
            }
            let key = format!("{kind}|{id}");
            if seen.contains(&key) { continue; }
            seen.insert(key);
            let name = dates::str_of(&r.get("name")).slice16(0.0, 80.0);
            let o = Obj::new();
            o.set("type", kind);
            o.set("id", id);
            if !name.is_empty() { o.set("name", name); }
            rel.push(V::Obj(o));
        }
        if !rel.is_empty() { info.set("relations", super::arr_of(rel)); }
    }
    let changelog = raw.get("changelog");
    if !changelog.is_nullish() {
        let mut log = Vec::new();
        for e in dates::arr(&changelog) {
            let version = dates::str_of(&super::and(&e, "version"));
            if version.is_empty() {
                warn("판 기록에서 판 번호가 없는 줄을 뺐습니다.".into());
                continue;
            }
            let x = Obj::new();
            x.set("version", version.clone());
            let date = dates::str_of(&e.get("date"));
            if day_ok(&date) { x.set("date", date); } else if !date.is_empty() { warn(format!("판 기록 v{version}의 날짜 «{date}»를 읽지 못해 뺐습니다.")); }
            let note = dates::str_of(&e.get("note"));
            if !note.is_empty() { x.set("note", cut(note, l.note_len, "판 기록 한 줄", warn)); }
            log.push(V::Obj(x));
        }
        if log.len() > l.changelog { warn(format!("판 기록은 {0}줄까지 — 새것 {0}줄만 남겼습니다.", l.changelog)); }
        if !log.is_empty() { log.truncate(l.changelog); info.set("changelog", super::arr_of(log)); }
    }
    for (k, what) in [("created", "처음 만든 날"), ("updated", "마지막 반영한 날")] {
        let d = dates::str_of(&raw.get(k));
        if day_ok(&d) { info.set(k, d); } else if !d.is_empty() { warn(format!("{what} «{d}»를 읽지 못해 뺐습니다.")); }
    }
    info
}

/// `HT.VIEW_DENSITIES` — 연표의 밀도 고르기와 같은 값(id, 이름).
const VIEW_DENSITIES: [(f64, &str); 4] = [(-1.0, "넉넉하게"), (0.0, "자동"), (1.0, "빽빽하게"), (2.0, "조감")];
/// `HT.SHOW_DEFAULTS`의 열쇠(102 ~ 108줄 — 보기 설정의 표시 열쇠로 받는 이름).
const SHOW_KEYS: [&str; 15] = ["dynasties", "leaders", "cabinets", "eras", "capitals", "ganji", "epochs", "succession", "partOf", "spotEcho", "figures", "phases", "ranks", "houses", "groups"];

/// `ownId(raw, seed, used, say)` — 형식 3 목록의 id: 적은 id(영문 id 꼴)나 seed — 같은 목록 안에서 겹치면 "-2"를 붙인다(적은 id였으면 알림).
fn own_id(raw: &V, seed: Str, used: &mut HashSet<Str>, say: &mut dyn FnMut(String)) -> Str {
    let mut id = dates::str_of(raw);
    if !id.is_empty() && !dates::id_ok(&id) {
        say(format!("id \"{id}\"가 올바르지 않아 새로 만들었습니다."));
        id = Str::default();
    }
    let wrote = !id.is_empty();
    if id.is_empty() { id = seed; }
    if used.contains(&id) {
        let mut n = 2;
        while used.contains(&Str::from(format!("{id}-{n}"))) { n += 1; }
        if wrote { say(format!("id \"{id}\"가 겹쳐 \"{id}-{n}\"(으)로 바꿨습니다.")); }
        id = Str::from(format!("{id}-{n}"));
    }
    used.insert(id.clone());
    id
}

/// `readSpan(x, say, endOnly)` — 기간 `{ start, startAt?, end?, endAt?, ongoing? }` — 판(시작이 있어야 끝도 씀 · 끝은 그해까지)과 구역(endOnly: 끝만 적어도 됨 · [시작, 끝)).
/// "미정"은 받지 않는다. 못 읽은 것은 say로 알리고 기간(또는 끝)을 비운다 — 적은 것이 하나도 없으면 None.
fn read_span(ctx: &Ctx, x: &V, say: &mut dyn FnMut(String), end_only: bool) -> Option<Obj> {
    let has = |k: &str| super::given(&x.get(k));
    let o = Obj::new();
    if has("start") {
        match dates::read_date(ctx, &x.get("start"), &x.get("startAt")) {
            Some(s) if !s.t.is_nan() => {
                o.set("start", s.t);
                if let Some(at) = s.at { o.set("startAt", at); }
            }
            _ => {
                say(format!("시작 «{}»을(를) 읽지 못해 기간을 무시했습니다.", dates::str_of(&x.get("start"))));
                return None;
            }
        }
    } else if !end_only {
        if has("end") || matches!(x.get("ongoing"), V::Bool(true)) { say("시작 없이 끝만 적어 기간을 무시했습니다.".into()); }
        return None;
    }
    if matches!(x.get("ongoing"), V::Bool(true)) || dates::is_ongoing_text(&x.get("end")) {
        if !end_only { o.set("ongoing", true); } // 구역은 끝을 비우면 지금까지
    } else if has("end") {
        match dates::read_date(ctx, &x.get("end"), &x.get("endAt")) {
            Some(e) if !e.t.is_nan() => {
                let start = o.get("start");
                let before = match start.as_num() {
                    Some(s) => if end_only { e.t <= s } else { dates::end_bound_t(ctx, e.t, &e.at.clone().map_or(V::Null, V::Str)) < s },
                    None => false,
                };
                if before {
                    say("끝이 시작보다 앞서 기간을 무시했습니다.".into());
                    return None;
                }
                o.set("end", e.t);
                if let Some(at) = e.at { o.set("endAt", at); }
            }
            _ => say(format!("끝 «{}»을(를) 읽지 못해 끝을 비웠습니다.", dates::str_of(&x.get("end")))),
        }
    }
    if o.is_empty() { None } else { Some(o) }
}

/// `HT.readViewSettings(raw, say)` — 모아 보기 판의 보기 설정 `{ density?, lens?, show?: { 표시 열쇠: 참거짓 } }`. 모르는 열쇠 · 값은 say로 알리고 버린다. 남은 것이 없으면 None.
pub fn read_view_settings(raw: &V, say: &mut dyn FnMut(String)) -> Option<Obj> {
    if raw.is_nullish() || super::is_empty_str(raw) { return None; }
    if !super::is_plain(raw) {
        say("보기 설정(settings)이 { … } 꼴이 아니어서 뺐습니다.".into());
        return None;
    }
    let o = Obj::new();
    let entries = if let V::Obj(m) = raw { m.entries() } else { Vec::new() };
    for (k, v) in entries {
        if k == "density" {
            let text = dates::str_of(&v);
            let n = match &v { V::Num(x) => *x, _ => if int_text(&text) { js::to_num(&V::Str(text.clone())) } else { f64::NAN } };
            let d = VIEW_DENSITIES.iter().find(|(id, _)| *id == n).or_else(|| VIEW_DENSITIES.iter().find(|(_, name)| text == *name));
            match d {
                Some((id, _)) => o.set("density", *id),
                None => say(format!("보기 설정의 밀도 «{text}»를 몰라 뺐습니다. ({})", VIEW_DENSITIES.iter().map(|(id, name)| format!("{} {name}", js::num_str(*id))).collect::<Vec<_>>().join(" · "))),
            }
        } else if k == "lens" {
            let text = dates::str_of(&v);
            if matches!(v, V::Str(_)) && !text.is_empty() { o.set("lens", text); }
            else if super::given(&v) { say("보기 설정의 렌즈(lens)는 주제 id 글이어야 해서 뺐습니다.".into()); }
        } else if k == "show" {
            if !js::truthy(&v) || !super::is_plain(&v) {
                say("보기 설정의 표시(show)가 { 열쇠: 참거짓 } 꼴이 아니어서 뺐습니다.".into());
                continue;
            }
            let show = Obj::new();
            let pairs = if let V::Obj(m) = &v { m.entries() } else { Vec::new() };
            for (s, b) in pairs {
                if !SHOW_KEYS.iter().any(|x| s == *x) { say(format!("보기 설정의 표시 «{s}»를 몰라 뺐습니다.")); }
                else if !matches!(b, V::Bool(_)) { say(format!("보기 설정의 표시 «{s}»는 참(true) · 거짓(false)만 받아 뺐습니다.")); }
                else { show.set(&s, b); }
            }
            if !show.is_empty() { o.set("show", show); }
        } else {
            say(format!("보기 설정의 열쇠 «{k}»를 몰라 뺐습니다. (밀도 density · 렌즈 lens · 표시 show만 받습니다)"));
        }
    }
    if o.is_empty() { None } else { Some(o) }
}
/// `/^-?\d+$/.test(s)`.
fn int_text(s: &Str) -> bool {
    let Some(t) = s.exact() else { return false };
    let digits = t.strip_prefix('-').unwrap_or(t);
    !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())
}

/// 형식 3 목록 읽기(`HT.readViews` · `HT.readMaps` · `HT.readFonts`)의 알림 통로 `report.err(msg, i)` · `report.warn(msg, i)`.
pub trait Report {
    fn err(&mut self, msg: String, i: usize);
    fn warn(&mut self, msg: String, i: usize);
}

/// `HT.readViews(list, report)` — 모아 보기 판 `[{ id?, name, members, start?, end?, settings?, color?, description?, note?, wiki? }]`.
/// 대범위와 달리 트랙이 없고, 구성 나라는 적은 차례 그대로 둔다. 구성 나라를 연표에서 찾는 것은 모델이.
pub fn read_views(ctx: &Ctx, list: &V, report: &mut dyn Report) -> Vec<V> {
    let mut out = Vec::new();
    let mut ids: HashSet<Str> = HashSet::new();
    for (i, v) in dates::arr(list).iter().enumerate() {
        if !js::truthy(v) || !super::is_plain(v) { report.err(format!("모아 보기 판 #{}: 형식이 올바르지 않습니다.", i + 1), i); continue; }
        let name = dates::str_of(&v.get("name"));
        let label = format!("모아 보기 판 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { report.err(format!("{label}: 이름이 비어 있습니다."), i); continue; }
        let mut refs: Vec<cells::ScopeRef> = Vec::new();
        for r in cells::read_scope_refs(&v.get("members")) {
            let key = |q: &cells::ScopeRef| q.track.clone().unwrap_or_default();
            if !refs.iter().any(|q| q.polity == r.polity && key(q) == key(&r)) { refs.push(r); }
        }
        if refs.is_empty() { report.err(format!("{label}: 구성 나라(members)가 없습니다."), i); continue; }
        let mut say = |msg: String| report.warn(format!("{label}: {msg}"), i);
        let seed = super::cat(&[&Str::from("v-"), &super::misc::hash(&name)]);
        let o = Obj::new();
        o.set("id", own_id(&v.get("id"), seed, &mut ids, &mut say));
        o.set("name", name.clone());
        o.set("members", super::arr_of(refs.iter().map(cells::ScopeRef::compact).collect()));
        if let Some(span) = read_span(ctx, v, &mut say, false) { super::assign_into(&o, &V::Obj(span)); }
        if let Some(settings) = read_view_settings(&v.get("settings"), &mut say) { o.set("settings", settings); }
        let names = names::read_names(ctx, &v.get("names"), &mut say); // 이름 목록(판의 원어 · 다른 이름 — 형식 3 F1과 같은 읽기)
        if !names.is_empty() { o.set("names", super::arr_of(names)); }
        if super::misc::is_color(&v.get("color")) { o.set("color", v.get("color")); }
        for k in ["description", "note"] {
            let t = dates::str_of(&v.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !dates::str_of(&v.get("wiki")).is_empty() { o.set("wiki", js::to_str(&v.get("wiki"))); }
        out.push(V::Obj(o));
    }
    out
}

// ── 지도(3450 · 3564 ~ 3759줄 — 5c) ──

/// `HT.MAP_CRS`의 id(그림 좌표 · 경위도).
const MAP_CRS: [&str; 2] = ["image", "lonlat"];

/// `readMapImage(v, what, say)` — 지도의 그림(바탕 · 장면): 표지와 같은 꼴 · 같은 한도(`HT.PACK_LIMITS.mapImage`). 그림이 아니거나 크면 say로 알리고 None.
fn read_map_image(v: &V, what: &str, say: &mut dyn FnMut(String)) -> Option<Str> {
    let l = &vocab::PACK_LIMITS;
    let c = match v { V::Str(s) => s.trim(), _ => Str::default() };
    if c.len16() > l.map_image { say(format!("{what}이 너무 커서(data URL {}자 넘음) 뺐습니다.", l.map_image)); }
    else if !cover_ok(&c) { say(format!("{what}이 그림(png · jpeg · webp의 data URL)이 아니어서 뺐습니다.")); }
    else { return Some(c); }
    None
}

/// `readShape(shape, crs, size, say)` — 구역의 모양: 고리 하나 `[[x, y], …]` 또는 여러 고리 `[[[x, y], …], …]` — 적은 꼴 그대로 돌려준다.
/// 꼭짓점은 두 수(경위도면 경도 ±180 · 위도 ±90 안), 고리마다 꼭짓점 셋 이상(닫힌 고리는 처음 = 끝을 하나로 셈). 잘못된 꼭짓점이 든 고리는 통째로 뺀다.
/// 그림 밖으로 나간 꼭짓점은 알리기만 한다. 쓸 고리가 없으면 None.
fn read_shape(shape: &V, crs: &Str, size: Option<(f64, f64)>, say: &mut dyn FnMut(String)) -> Option<V> {
    let rings_in = match shape { V::Arr(a) if !a.is_empty() => a.to_vec(), _ => { say("모양(shape)이 비었거나 목록이 아닙니다.".into()); return None; } };
    let multi = matches!(&rings_in[0], V::Arr(a) if matches!(a.get(0), V::Arr(_)));
    let rings = if multi { rings_in } else { vec![shape.clone()] };
    let point = |p: &V| -> Option<(f64, f64)> {
        let V::Arr(a) = p else { return None };
        if a.len() != 2 { return None; }
        match (a.get(0), a.get(1)) { (V::Num(x), V::Num(y)) if x.is_finite() && y.is_finite() => Some((x, y)), _ => None }
    };
    let mut good: Vec<V> = Vec::new();
    let mut outside = false;
    for (k, ring) in rings.iter().enumerate() {
        let what = if multi { format!("고리 #{}", k + 1) } else { "모양".to_string() };
        let V::Arr(ra) = ring else { say(format!("{what}이 목록이 아니어서 뺐습니다.")); continue; };
        let pts = ra.to_vec();
        if let Some(bad) = pts.iter().position(|p| point(p).is_none()) {
            say(format!("{what}의 {}번째 꼭짓점이 [x, y] 두 수가 아니어서 {} 뺐습니다.", bad + 1, if multi { "그 고리를" } else { "모양을" }));
            continue;
        }
        let xy: Vec<(f64, f64)> = pts.iter().filter_map(point).collect();
        if crs == "lonlat" {
            if let Some(off) = xy.iter().position(|p| p.0.abs() > 180.0 || p.1.abs() > 90.0) {
                say(format!("{what}의 {}번째 꼭짓점이 경위도 범위(경도 ±180 · 위도 ±90)를 벗어나 {} 뺐습니다.", off + 1, if multi { "그 고리를" } else { "모양을" }));
                continue;
            }
        }
        let closed = xy.len() > 1 && xy[0].0 == xy[xy.len() - 1].0 && xy[0].1 == xy[xy.len() - 1].1;
        let n = xy.len() - usize::from(closed);
        if n < 3 { say(format!("{what}의 꼭짓점이 {n}개뿐이라 뺐습니다 (셋 이상이어야 함).")); continue; }
        if let Some((w, h)) = size { if xy.iter().any(|p| p.0 < 0.0 || p.1 < 0.0 || p.0 > w || p.1 > h) { outside = true; } }
        good.push(super::arr_of(xy.iter().map(|p| super::arr_of(vec![V::Num(p.0), V::Num(p.1)])).collect()));
    }
    if outside {
        let (w, h) = size.unwrap_or_default();
        say(format!("그림({}×{}) 밖으로 나간 꼭짓점이 있습니다 — 그림 밖은 그리지 않습니다.", js::num_str(w), js::num_str(h)));
    }
    if good.is_empty() { return None; }
    Some(if multi { super::arr_of(good) } else { good.swap_remove(0) })
}

/// `HT.readMaps(list, report)` — 지도 1단계(그림 바탕 + 장면): `[{ id?, name, crs?, image?, size?, levels?, regions?, frames?, places?, description?, note?, source?, wiki? }]`.
/// 지도의 꼴(이름 · 좌표 방식 · 그림 좌표의 크기)이 틀리면 오류로 그 지도만 빼고, 그 안의 층위 · 구역 · 장면 · 지명이 틀리면 경고하고 그것만 뺀다.
/// 장면은 해 순으로 정리하고(같은 해는 적은 차례 — 뒤의 것을 뺌), 구역의 위 구역(parent)은 모두 읽은 뒤에 확인한다(못 찾음 · 고리 · 층위 차례).
pub fn read_maps(ctx: &Ctx, list: &V, report: &mut dyn Report) -> Vec<V> {
    let s = dates::str_of;
    let mut out = Vec::new();
    let mut ids: HashSet<Str> = HashSet::new();
    for (i, m) in dates::arr(list).iter().enumerate() {
        if !js::truthy(m) || !super::is_plain(m) { report.err(format!("지도 #{}: 형식이 올바르지 않습니다.", i + 1), i); continue; }
        let name = s(&m.get("name"));
        let label = format!("지도 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { report.err(format!("{label}: 이름이 비어 있습니다."), i); continue; }
        let crs = { let c = s(&m.get("crs")); if c.is_empty() { Str::from("image") } else { c } };
        if !MAP_CRS.iter().any(|c| crs == *c) { report.err(format!("{label}: 좌표 방식(crs) «{crs}»를 모릅니다. (image 그림 좌표 · lonlat 경위도)"), i); continue; }
        let mut size: Option<(f64, f64)> = None;
        if crs == "image" {
            let sz = m.get("size");
            let pair = match &sz { V::Arr(a) if a.len() == 2 => match (a.get(0), a.get(1)) { (V::Num(w), V::Num(h)) if w.is_finite() && w > 0.0 && h.is_finite() && h > 0.0 => Some((w, h)), _ => None }, _ => None };
            let Some(pair) = pair else {
                report.err(format!("{label}: 그림 좌표(crs: image)의 지도에는 크기(size: [너비, 높이] — 0보다 큰 두 수)가 필요합니다."), i);
                continue;
            };
            size = Some(pair);
        } else if super::given(&m.get("size")) { report.warn(format!("{label}: 경위도 지도에는 크기(size)를 쓰지 않아 뺐습니다."), i); }
        let mut say = |msg: String| report.warn(format!("{label}: {msg}"), i);
        let o = Obj::new();
        o.set("id", own_id(&m.get("id"), super::cat(&[&Str::from("m-"), &misc::hash(&name)]), &mut ids, &mut say));
        o.set("name", name.clone());
        o.set("crs", crs.clone());
        if let Some((w, h)) = size { o.set("size", super::arr_of(vec![V::Num(w), V::Num(h)])); }
        let image = m.get("image");
        if super::given(&image) {
            if crs == "lonlat" { say("경위도 지도의 바탕 그림은 자리를 맞출 칸이 아직 없어(2단계) 뺐습니다.".into()); }
            else if let Some(img) = read_map_image(&image, "바탕 그림", &mut say) { o.set("image", img); }
        }
        // 행정 층위
        let levels_raw = m.get("levels");
        if !levels_raw.is_nullish() && !matches!(levels_raw, V::Arr(_)) { say("행정 층위(levels)는 목록이어야 해서 뺐습니다.".into()); }
        let mut levels: Vec<(Str, Str)> = Vec::new();
        for (k, l) in dates::arr(&levels_raw).iter().enumerate() {
            let x = match l { V::Str(_) => { let x = Obj::new(); x.set("id", l.clone()); V::Obj(x) } l if js::truthy(l) && super::is_plain(l) => l.clone(), _ => V::Obj(Obj::new()) };
            let id = { let a = s(&x.get("id")); if a.is_empty() { s(&x.get("name")) } else { a } };
            if id.is_empty() { say(format!("행정 층위 #{}: id가 비어 있어 뺐습니다.", k + 1)); continue; }
            if levels.iter().any(|q| q.0 == id) { say(format!("행정 층위 \"{id}\"가 겹쳐 뒤의 것을 뺐습니다.")); continue; }
            let shown = s(&x.get("name"));
            levels.push((id.clone(), if shown.is_empty() { id } else { shown }));
        }
        if !levels.is_empty() {
            o.set("levels", super::arr_of(levels.iter().map(|(id, nm)| { let q = Obj::new(); q.set("id", id.clone()); q.set("name", nm.clone()); V::Obj(q) }).collect()));
        }
        let level_at = |id: &V| levels.iter().position(|q| matches!(id, V::Str(t) if *t == q.0)).map_or(-1.0, |p| p as f64);
        // 구역
        let regions_raw = m.get("regions");
        if !regions_raw.is_nullish() && !matches!(regions_raw, V::Arr(_)) { say("구역(regions)은 목록이어야 해서 뺐습니다.".into()); }
        let mut regions: Vec<Obj> = Vec::new();
        for (k, r) in dates::arr(&regions_raw).iter().enumerate() {
            if !js::truthy(r) || !super::is_plain(r) { say(format!("구역 #{}: 형식이 올바르지 않아 뺐습니다.", k + 1)); continue; }
            let id = s(&r.get("id"));
            let rl = format!("구역 #{}{}", k + 1, if id.is_empty() { String::new() } else { format!(" \"{id}\"") });
            let mut rsay = |msg: String| say(format!("{rl}: {msg}"));
            if id.is_empty() { rsay("id가 비어 있어 뺐습니다.".into()); continue; }
            if regions.iter().any(|q| js::strict_eq(&q.get("id"), &V::Str(id.clone()))) { rsay("id가 겹쳐 뒤의 것을 뺐습니다.".into()); continue; }
            let Some(shape) = read_shape(&r.get("shape"), &crs, size, &mut rsay) else { rsay("쓸 수 있는 모양이 없어 구역을 뺐습니다.".into()); continue; };
            let q = Obj::new();
            q.set("id", id.clone());
            q.set("name", { let n = s(&r.get("name")); if n.is_empty() { id.clone() } else { n } });
            let lv = s(&r.get("level"));
            if !lv.is_empty() && level_at(&V::Str(lv.clone())) >= 0.0 { q.set("level", lv); }
            else if !lv.is_empty() { rsay(format!("행정 층위 «{lv}»가 이 지도의 levels에 없어 뺐습니다.")); }
            let parent = s(&r.get("parent"));
            if !parent.is_empty() { q.set("parent", parent); } // 모두 읽은 뒤에 확인
            if let Some(span) = read_span(ctx, r, &mut rsay, true) { super::assign_into(&q, &V::Obj(span)); }
            q.set("shape", shape);
            let list = names::read_names(ctx, &r.get("names"), &mut rsay); // 이름 목록(구역의 원어 · 옛 이름 — 형식 3 F1과 같은 읽기)
            if !list.is_empty() { q.set("names", super::arr_of(list)); }
            let note = s(&r.get("note"));
            if !note.is_empty() { q.set("note", note); }
            regions.push(q);
        }
        let region_of = |id: &V| regions.iter().find(|q| js::strict_eq(&q.get("id"), id)).cloned();
        for q in &regions {
            let parent = q.get("parent");
            if !js::truthy(&parent) { continue; }
            let Some(p) = region_of(&parent).filter(|p| !p.ptr_eq(q)) else {
                say(format!("구역 \"{}\": 위 구역(parent) «{}»를 이 지도에서 찾지 못해 뺐습니다.", js::to_str(&q.get("id")), js::to_str(&parent)));
                q.delete("parent");
                continue;
            };
            let mut seen: Vec<V> = Vec::new();
            let mut looped = false;
            let mut cur = Some(p.clone());
            while let Some(c) = cur {
                let cid = c.get("id");
                if seen.iter().any(|x| js::strict_eq(x, &cid)) { break; }
                if c.ptr_eq(q) { looped = true; break; }
                seen.push(cid);
                let cp = c.get("parent");
                cur = if js::truthy(&cp) { region_of(&cp) } else { None };
            }
            if looped {
                say(format!("구역 \"{}\": 위 구역을 따라가면 제자리로 돌아와 위 구역(parent)을 뺐습니다.", js::to_str(&q.get("id"))));
                q.delete("parent");
            } else if js::truthy(&q.get("level")) && js::truthy(&p.get("level")) && level_at(&p.get("level")) >= level_at(&q.get("level")) {
                say(format!("구역 \"{}\": 위 구역 \"{}\"의 층위({})가 이 구역의 층위({})보다 위가 아닙니다.",
                    js::to_str(&q.get("id")), js::to_str(&p.get("id")), js::to_str(&p.get("level")), js::to_str(&q.get("level"))));
            }
        }
        if !regions.is_empty() { o.set("regions", super::arr_of(regions.iter().cloned().map(V::Obj).collect())); }
        // 장면(열쇠 해)
        let frames_raw = m.get("frames");
        if !frames_raw.is_nullish() && !matches!(frames_raw, V::Arr(_)) { say("장면(frames)은 목록이어야 해서 뺐습니다.".into()); }
        let mut frames: Vec<Obj> = Vec::new();
        for (k, f) in dates::arr(&frames_raw).iter().enumerate() {
            if !js::truthy(f) || !super::is_plain(f) { say(format!("장면 #{}: 형식이 올바르지 않아 뺐습니다.", k + 1)); continue; }
            let year = f.get("year");
            let d = if year.is_nullish() || super::is_empty_str(&year) { None } else { dates::read_date(ctx, &year, &f.get("yearAt")) };
            let Some(d) = d.filter(|d| !d.t.is_nan()) else { say(format!("장면 #{}: 해(year)가 없거나 읽을 수 없어 뺐습니다.", k + 1)); continue; };
            let fl = format!("장면 #{}({})", k + 1, s(&year));
            let q = Obj::new();
            q.set("year", d.t);
            if let Some(at) = d.at.filter(|a| !a.is_empty()) { q.set("yearAt", at); }
            let owners_raw = f.get("owners");
            if !owners_raw.is_nullish() {
                match &owners_raw {
                    V::Obj(own) => {
                        let owners = Obj::new();
                        for (rid, rf) in own.entries() {
                            if region_of(&V::Str(rid.clone())).is_none() { say(format!("{fl}: 구역 «{rid}»가 이 지도에 없어 그 주인을 뺐습니다.")); continue; }
                            if rf.is_nullish() || super::is_empty_str(&rf) || matches!(&rf, V::Str(t) if t.trim().exact().is_some_and(|x| x.eq_ignore_ascii_case("none"))) {
                                owners.set(&rid, V::Null); // 주인 없음(앞 장면에서 이어받은 주인을 지움)
                                continue;
                            }
                            match cells::read_scope_ref(&rf) {
                                Some(r) => owners.set(&rid, r.compact()),
                                None => say(format!("{fl}: 구역 «{rid}»의 주인을 읽지 못해 뺐습니다.")),
                            }
                        }
                        if !owners.is_empty() { q.set("owners", owners); }
                    }
                    _ => say(format!("{fl}: 주인(owners)이 {{ 구역 id: 나라 }} 꼴이 아니어서 뺐습니다.")),
                }
            }
            let image = f.get("image");
            if super::given(&image) {
                if crs == "lonlat" { say(format!("{fl}: 경위도 지도의 장면 그림은 자리를 맞출 칸이 아직 없어(2단계) 뺐습니다.")); }
                else if let Some(img) = read_map_image(&image, &format!("{fl}의 그림"), &mut say) { q.set("image", img); }
            }
            let note = s(&f.get("note"));
            if !note.is_empty() { q.set("note", note); }
            frames.push(q);
        }
        js::sort_by(&mut frames, |a, b| a.num("year") - b.num("year")); // 같은 해는 적은 차례 그대로(안정 정렬) — 뒤의 것을 뺀다
        let mut kept: Vec<Obj> = Vec::new();
        for f in frames {
            if kept.last().is_some_and(|k| (k.num("year") - f.num("year")).abs() < 1e-9) {
                let at = f.get("yearAt");
                let shown = if js::truthy(&at) { js::to_str(&at) } else { Str::from(js::num_str(dates::year_of_t(f.num("year")))) };
                say(format!("장면: 같은 해({shown})의 장면이 둘이라 뒤의 것을 뺐습니다."));
            } else { kept.push(f); }
        }
        if !kept.is_empty() { o.set("frames", super::arr_of(kept.into_iter().map(V::Obj).collect())); }
        // 지명(글로만 — 지명 사전은 이름 · 지명 갈래의 몫)
        let places_raw = m.get("places");
        if !places_raw.is_nullish() {
            if !matches!(places_raw, V::Arr(_)) { say("지명(places)은 목록이어야 해서 뺐습니다.".into()); }
            let mut places: Vec<Str> = Vec::new();
            for p in dates::arr(&places_raw) {
                let t = s(&if js::truthy(&p) && js::type_of(&p) == "object" { js::nullish(p.get("id"), p.get("name")) } else { p.clone() });
                if !t.is_empty() && !places.contains(&t) { places.push(t); }
            }
            if !places.is_empty() { o.set("places", super::arr_of(places.into_iter().map(V::Str).collect())); }
        }
        for k in ["description", "note", "source"] {
            let t = s(&m.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !s(&m.get("wiki")).is_empty() { o.set("wiki", js::to_str(&m.get("wiki"))); }
        out.push(V::Obj(o));
    }
    out
}

// ── 글꼴(3760 ~ 3836줄 — 5c) ──

/// `FONT_RE` — `/^data:font\/(woff2|woff|ttf|otf);base64,([A-Za-z0-9+/]+={0,2})$/`을 손으로 → (형식, m[2] — base64 몸) · 안 맞으면 None.
fn font_parts(src: &Str) -> Option<(&'static str, String)> {
    let t = src.exact()?;
    let rest = t.strip_prefix("data:font/")?;
    let (fmt, body) = ["woff2", "woff", "ttf", "otf"].into_iter().find_map(|f| rest.strip_prefix(f).and_then(|r| r.strip_prefix(";base64,")).map(|b| (f, b)))?;
    let core = body.trim_end_matches('=');
    if body.len() - core.len() > 2 || core.is_empty() || !core.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/') { return None; }
    Some((fmt, body.to_string()))
}
/// `B64`.
const B64: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
/// `fontHead(b64)` — base64 앞 8자를 풀어 머리 4바이트(아니면 None — JS의 '').
fn font_head(b64: &str) -> Option<[u8; 4]> {
    let n: Vec<i64> = b64.bytes().take(8).map(|c| B64.iter().position(|&x| x == c).map_or(-1, |p| p as i64)).collect();
    if n.len() < 8 || n.iter().any(|&v| v < 0) { return None; }
    let mut out = Vec::with_capacity(6);
    for k in [0, 4] {
        let v = (n[k] << 18) | (n[k + 1] << 12) | (n[k + 2] << 6) | n[k + 3];
        out.extend([(v >> 16) & 255, (v >> 8) & 255, v & 255].map(|x| x as u8));
    }
    Some([out[0], out[1], out[2], out[3]])
}
/// `FONT_HEADS[형식]` — 그 글꼴 파일의 머리로 받는 4바이트.
fn font_heads(fmt: &str) -> &'static [[u8; 4]] {
    const TT: [u8; 4] = [0, 1, 0, 0];
    const WOFF2: [[u8; 4]; 1] = [*b"wOF2"];
    const WOFF: [[u8; 4]; 1] = [*b"wOFF"];
    const TTF: [[u8; 4]; 3] = [TT, *b"true", *b"OTTO"];
    const OTF: [[u8; 4]; 3] = [*b"OTTO", TT, *b"true"];
    match fmt { "woff2" => &WOFF2, "woff" => &WOFF, "ttf" => &TTF, _ => &OTF }
}
/// `HT.readFonts(list, report)` — 글꼴 `[{ id, family, src, license, scripts?, ranges?, note? }]` — id · 이름(family) · 파일(src) · 라이선스(license)가 없거나 틀리면
/// 오류로 그 글꼴만 뺀다. 한도(`HT.PACK_LIMITS`): 하나에 data URL font자 · 한 DLC에 fonts개 · 모두 합쳐 fontTotal자. scripts = 문자 꼬리표(ISO 15924의 네 글자).
pub fn read_fonts(list: &V, report: &mut dyn Report) -> Vec<V> {
    let l = &vocab::PACK_LIMITS;
    let s = dates::str_of;
    let mut out: Vec<Obj> = Vec::new();
    let mut total = 0usize;
    for (i, f) in dates::arr(list).iter().enumerate() {
        if !js::truthy(f) || !super::is_plain(f) { report.err(format!("글꼴 #{}: 형식이 올바르지 않습니다.", i + 1), i); continue; }
        let id = s(&f.get("id"));
        let family = s(&f.get("family"));
        let shown = if family.is_empty() { id.clone() } else { family.clone() };
        let label = format!("글꼴 #{}{}", i + 1, if shown.is_empty() { String::new() } else { format!(" \"{shown}\"") });
        if !dates::id_ok(&id) { report.err(format!("{label}: id가 비었거나 올바르지 않습니다."), i); continue; }
        if out.iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) { report.warn(format!("{label}: id \"{id}\"가 겹쳐 뒤의 것을 무시했습니다."), i); continue; }
        if family.is_empty() { report.err(format!("{label}: 글꼴 이름(family)이 비어 있습니다."), i); continue; }
        let license = s(&f.get("license"));
        if license.is_empty() { report.err(format!("{label}: 라이선스(license)가 비어 있어 이 글꼴을 뺐습니다. (글꼴은 쓸 수 있는 조건을 적어야 담을 수 있습니다)"), i); continue; }
        let src = match f.get("src") { V::Str(t) => t.trim(), _ => Str::default() };
        if src.is_empty() { report.err(format!("{label}: 글꼴 파일(src)이 비어 있습니다."), i); continue; }
        if src.len16() > l.font { report.err(format!("{label}: 글꼴 파일이 너무 커서(data URL {}자 넘음) 뺐습니다.", l.font), i); continue; }
        let Some((fmt, body)) = font_parts(&src) else { report.err(format!("{label}: 글꼴 파일(src)이 data:font/woff2 · woff · ttf · otf의 base64 꼴이 아닙니다."), i); continue; };
        if !font_head(&body).is_some_and(|h| font_heads(fmt).contains(&h)) { report.err(format!("{label}: 글꼴 파일의 내용이 {fmt} 글꼴이 아닙니다."), i); continue; }
        if out.len() >= l.fonts { report.warn(format!("{label}: 글꼴은 한 DLC에 {}개까지라 뺐습니다.", l.fonts), i); continue; }
        if total + src.len16() > l.font_total { report.err(format!("{label}: 글꼴을 모두 합친 크기가 한도(data URL {}자)를 넘어 뺐습니다.", l.font_total), i); continue; }
        total += src.len16();
        let o = Obj::new();
        o.set("id", id);
        o.set("family", family);
        o.set("src", src);
        o.set("license", license);
        // 문자 꼬리표(배열이나 쉼표로 이은 글) — 네 글자 꼴만, 첫 글자 대문자 · 나머지 소문자로
        let scripts = f.get("scripts");
        if !scripts.is_nullish() && !super::is_empty_str(&scripts) {
            let items: Vec<V> = match &scripts { V::Arr(a) => a.to_vec(), x => super::split_units(&js::to_str(x), &[0x2C]).into_iter().map(V::Str).collect() };
            let mut tags: Vec<Str> = Vec::new();
            for t in &items {
                let st = s(t);
                if st.is_empty() { continue; }
                let Some(word) = st.exact().filter(|w| w.len() == 4 && w.bytes().all(|b| b.is_ascii_alphabetic())).map(str::to_string) else {
                    report.warn(format!("{label}: 문자 꼬리표 «{st}»는 네 글자 꼴(ISO 15924)이 아니어서 뺐습니다."), i);
                    continue;
                };
                let tag = Str::from(format!("{}{}", word[..1].to_ascii_uppercase(), word[1..].to_ascii_lowercase()));
                if !tags.contains(&tag) { tags.push(tag); }
            }
            if !tags.is_empty() { o.set("scripts", super::arr_of(tags.into_iter().map(V::Str).collect())); }
        }
        // 덮는 글자 범위: "U+F1A00-F1A0B" 꼴의 목록(배열이나 쉼표로 이은 글) — 꼴이 틀린 범위는 경고하고 뺀다
        let ranges = f.get("ranges");
        if !ranges.is_nullish() && !super::is_empty_str(&ranges) {
            let items: Vec<V> = match &ranges { V::Arr(a) => a.to_vec(), x => super::split_units(&js::to_str(x), &[0x2C]).into_iter().map(V::Str).collect() };
            let mut rs: Vec<Str> = Vec::new();
            for t in &items {
                let st = s(t);
                if st.is_empty() { continue; }
                let Some(r) = names::parse_range(&V::Str(st.clone())) else {
                    report.warn(format!("{label}: 글자 범위 «{st}»는 U+4E00-9FFF 꼴이 아니어서 뺐습니다."), i);
                    continue;
                };
                let text = Str::from(names::range_text(r));
                if !rs.contains(&text) { rs.push(text); }
            }
            if !rs.is_empty() { o.set("ranges", super::arr_of(rs.into_iter().map(V::Str).collect())); }
        }
        let note = s(&f.get("note"));
        if !note.is_empty() { o.set("note", note); }
        out.push(o);
    }
    out.into_iter().map(V::Obj).collect()
}

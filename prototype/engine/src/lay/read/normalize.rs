//! `HT.normalizePack(raw)` — DLC 원본 객체를 검사하고 깨끗한 꼴로 바꾼다(이음매 ①) — 한 벌 P3 과제 5a ~ 5c.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트) · 3849 ~ 5072줄 `HT.normalizePack`
//! (2026-10-24 맞춤 · 리메이크 3단계 과제 1 · `core.js` `7c75434e37fa`) 4448 ~ 4455줄 시대 구분의 문화권(sphere — 트랙 우선 알림) · 4530 ~ 4534줄 문화권별 주기 줄(yearCycles — [`misc::read_year_cycles`])
//! (2026-10-24 맞춤 · `core.js` `f90a60d102ce`) 3945 ~ 3948줄 문화권 사전(`HT.readSpheres` — [`cells::read_spheres`]) · 3960 ~ 3965줄 트랙의 문화권(올바른 id면 둠) · 5095줄 빈 DLC 알림의 문화권 사전
//! 한 파일이 1,500줄을 넘지 않게 JS 절 경계로 나눴다(과제 5c 머리 — 동작 그대로). 흐름(원본 차례)은 이 파일의 [`normalize_pack`]이 쥐고, 절마다의 몫은 아래 파일에:
//! - 이 파일 — 머리 · 트랙 · 분류 · 민족 · 지위 사전 · 가문 · 주제 · 성씨 · 지명 사전 · 시대 구분 · 대범위 · 형식 3 목록(판 · 지도 · 글꼴) · 간지 · 문서 그림 · 끝,
//!   정규화 안의 함수 `err` · `warn` · `putNames` · `putLineage` · `takeId` · `readRange` · `applyRange` · `checkTrack`
//! - [`cell_lists`] — 4128 ~ 4284줄 정규화 안의 칸 읽기(`readCells` · `readCapitals` · `readSuccList` · `warnPartOfUnknown` · `readUncertainty` · `readNames` · `readService`)
//! - [`bands`] — 4381 ~ 4551줄 기관 · 문화 · 왕조(`readOrgan` · `readCulture` · `readDynasty` · `checkPartOf`)와 시대 · 기관 · 문화 · 왕조 목록
//! - [`items`] — 4553 ~ 4779줄 사건 · 인물 · 단체 · 제도 · [`patches`] — 4781 ~ 4967줄 패치 · [`rest`] — 4969 ~ 5064줄 문서 · 영토
//!
//! 과제 5a가 옮긴 몫(원본 차례 그대로):
//! - 3850 ~ 3896줄 머리: 알림 통로(`err` · `warn`) · 최상위 검사 · 형식 4 내림(`HT.F4.down`) · 형식 확인 · `pack`의 머리 칸과 `HT.readPackInfo` · id · 이름 검사
//! - 3924 ~ 3940줄 트랙 · 3942 ~ 3949줄 분류 · 3951 ~ 3968줄 민족
//! - 4053 ~ 4127줄 `itemIds` · `takeId` · `readRange` · `applyRange` · `checkTrack`(정규화 안의 함수 — 이 파일의 [`Norm`] 메서드 · `applyRange`는 함수)
//! - 4286 ~ 4306줄 시대 구분 · 4308 ~ 4355줄 대범위
//! - 4357 ~ 4366줄 형식 3 목록(모아 보기 판 — 지도 · 글꼴은 5c) · 4367 ~ 4371줄 간지 설정
//! - 5066 ~ 5071줄 끝: 빈 DLC 알림 · 치명적 오류면 `pack: null`
//!
//! 과제 5b가 옮긴 몫(원본 차례 그대로):
//! - 3898 ~ 3922줄 `putNames` · `putLineage`(5a 보고는 5c 몫으로 적었으나 가문 · 칸 · 왕조 · 시대가 부르므로 5b가 옮김 — [`Norm`] 메서드)
//! - 3970 ~ 3973줄 지위 사전 · 3975 ~ 3999줄 가문
//! - 4128 ~ 4230줄 칸 읽기([`cell_lists`]) · 4381 ~ 4551줄 기관 · 문화 · 왕조 · 시대([`bands`])
//!
//! 과제 5c가 옮긴 몫(원본 차례 그대로 — 이것으로 `normalizePack` 전부):
//! - 4001 ~ 4051줄 주제 사전(`HT.readThemeDefs` — `read::groups`) · 성씨 사전 · 지명 사전(`HT.readCoords` — `read::names`)
//! - 4234 ~ 4284줄 `FIGURE_DATE_WORDS` · `readService`([`cell_lists`])
//! - 4358줄 형식 3 목록의 둘째 · 셋째(지도 `HT.readMaps` · 글꼴 `HT.readFonts` — `read::info`) · 4372 ~ 4379줄 문서 그림(`HT.readImages` — `read::docs`)
//! - 4553 ~ 4779줄 사건 · 인물 · 단체 · 제도([`items`]) · 4781 ~ 4967줄 패치([`patches`]) · 4969 ~ 5064줄 문서 · 영토([`rest`])
use super::{cells, dates, docs, groups, info, misc, names, vocab, Ctx, Note};
use crate::lay::f4;
use crate::lay::js::{self, Obj, Str, V};
use std::collections::HashSet;

mod bands;
mod cell_lists;
mod items;
mod patches;
mod rest;

use cell_lists::name_list;

/// `HT.normalizePack`의 답 `{ pack, errors, warnings }` — 치명적 오류(kind 'info')가 있으면 `pack`은 None(JS의 null).
#[derive(Debug)]
pub struct Normalized { pub pack: Option<V>, pub errors: Vec<Note>, pub warnings: Vec<Note> }

/// 정규화 하나의 상태 — 원본의 `normalizePack` 안 지역 변수(`errors` · `warnings` · `trackIds` · `catIds` · `itemIds`)와 그 안의 함수들.
struct Norm<'c> {
    ctx: &'c Ctx,
    errors: Vec<Note>,
    warnings: Vec<Note>,
    track_ids: HashSet<Str>,
    cat_ids: HashSet<Str>,
    item_ids: HashSet<Str>,
}

/// `readRange`의 답 `{ start, end, ongoing, startUnknown, endUnknown, startAt, endAt }`.
#[derive(Debug, Clone)]
struct Range { start: f64, end: Option<f64>, ongoing: bool, start_unknown: bool, end_unknown: bool, start_at: Option<Str>, end_at: Option<Str> }

fn note(msg: String, kind: &str, index: Option<usize>) -> Note { Note { msg, kind: kind.to_string(), index: index.map(|i| i as f64) } }

impl<'c> Norm<'c> {
    /// `err(msg, kind = 'info', index)`.
    fn err(&mut self, msg: String, kind: &str, index: Option<usize>) { self.errors.push(note(msg, kind, index)); }
    /// `warn(msg, kind = 'info', index)`.
    fn warn(&mut self, msg: String, kind: &str, index: Option<usize>) { self.warnings.push(note(msg, kind, index)); }

    /// 모아 둔 알림 글에 앞말을 붙여 넘긴다 — JS의 `m => warn(`${앞말}${m}`, kind, i)`(알림 차례는 모은 차례 그대로).
    fn warn_all(&mut self, msgs: Vec<String>, prefix: &str, kind: &str, i: usize) {
        for m in msgs { self.warn(format!("{prefix}{m}"), kind, Some(i)); }
    }

    /// `putNames(o, v, label, kind, i)`(3899줄 — 과제 5b가 옮김: 가문 · 칸 · 왕조 · 시대가 부름) — 이름 목록(`HT.readNames`)을 적은 것이 있을 때만 o에 둔다.
    fn put_names(&mut self, o: &Obj, v: &V, label: &str, kind: &str, i: usize) {
        let mut msgs = Vec::new();
        let list = names::read_names(self.ctx, v, &mut |m| msgs.push(m));
        self.warn_all(msgs, &format!("{label}: "), kind, i);
        if !list.is_empty() { o.set("names", super::arr_of(list)); }
    }
    /// `putLineage(o, x, label, kind, i, { person, accession, kin })`(3904줄 — 과제 5b가 옮김: 지도자 · 내각 칸이 부름) — 사람(person) · 자리 이음(accession) · 부모 · 배우자.
    #[allow(clippy::too_many_arguments)]
    fn put_lineage(&mut self, o: &Obj, x: &V, label: &str, kind: &str, i: usize, person: bool, accession: bool, kin: bool) {
        let ctx = self.ctx;
        let mut msgs: Vec<String> = Vec::new();
        {
            let mut w = |m: String| msgs.push(m);
            let who = x.get("person");
            if person && names::is_unknown_who(&who) {
                w(format!("사람(person) \"{}\"은(는) 적지 않은 것과 같아 뺐습니다 — 이 칸 자체가 한 사람입니다(이름 모를 사람끼리 한 사람으로 묶이지 않게).", js::to_str(&who).trim()));
            } else if person && super::given(&who) {
                let r = names::read_person_ref(ctx, &who);
                if js::truthy(&r) { o.set("person", r); }
                else { w("사람(person)을 읽을 수 없어 뺐습니다 — 인물 id · 이름이나 \"나라:지도자@시작 해\"로 적습니다.".into()); }
            }
            if accession {
                if let Some(a) = names::read_accession(ctx, &x.get("accession"), &mut w) { o.set("accession", a); }
            }
            if kin {
                let ps = names::read_parents(ctx, &x.get("parents"), &mut w);
                if !ps.is_empty() { o.set("parents", super::arr_of(ps)); }
                let sp = names::read_spouses(ctx, &x.get("spouses"), &mut w);
                if !sp.is_empty() { o.set("spouses", super::arr_of(sp)); }
            }
        }
        self.warn_all(msgs, &format!("{label}: "), kind, i);
    }

    /// `takeId(x, prefix, seed, label, kind, i)` — 적은 id(올바르지 않으면 알리고 새로) 또는 prefix + 씨앗의 해시. 겹치면 "-2" …
    fn take_id(&mut self, x: &V, prefix: &str, seed: &Str, label: &str, kind: &str, i: usize) -> Str {
        let mut id = dates::str_of(&x.get("id"));
        if !id.is_empty() && !dates::id_ok(&id) {
            self.warn(format!("{label}: id \"{id}\"가 올바르지 않아 새로 만들었습니다."), kind, Some(i));
            id = Str::default();
        }
        if id.is_empty() { id = super::cat(&[&Str::from(prefix), &misc::hash(seed)]); }
        if self.item_ids.contains(&id) {
            let mut n = 2;
            while self.item_ids.contains(&Str::from(format!("{id}-{n}"))) { n += 1; }
            if !dates::str_of(&x.get("id")).is_empty() { self.warn(format!("{label}: id \"{id}\"가 중복되어 \"{id}-{n}\"(으)로 바꿨습니다."), kind, Some(i)); }
            id = Str::from(format!("{id}-{n}"));
        }
        self.item_ids.insert(id.clone());
        id
    }

    /// `readRange(x, label, kind, i)` — 시작 · 끝 연도. "미정"이면 배치용 연도(startHint/endHint, 또는 startUnknown:true와 함께 적은 숫자)로 자리를 잡는다.
    fn read_range(&mut self, x: &V, label: &str, kind: &str, i: usize) -> Option<Range> {
        let ctx = self.ctx;
        let ongoing = matches!(x.get("ongoing"), V::Bool(true)) || dates::is_ongoing_text(&x.get("end"));
        let start_unknown = matches!(x.get("startUnknown"), V::Bool(true)) || dates::is_unknown_text(&x.get("start"));
        let end_unknown = !ongoing && (matches!(x.get("endUnknown"), V::Bool(true)) || dates::is_unknown_text(&x.get("end")));
        let hint_of = |v: &V, raw: &V| -> Option<f64> {
            if let Some(h) = dates::to_year(ctx, v) { if !h.is_nan() { return Some(h); } }
            let r = if dates::is_unknown_text(raw) { None } else { dates::to_year(ctx, raw) };
            r.filter(|r| !r.is_nan())
        };
        let sd = if start_unknown { None } else { dates::date_in(ctx, x, "start") };
        let mut start = sd.as_ref().map(|d| d.t);
        let mut start_at = sd.as_ref().and_then(|d| d.at.clone());
        if !start_unknown && start.is_none_or(f64::is_nan) {
            let why = match sd.as_ref().and_then(|d| d.error.clone()) { Some(e) => format!(" {e}"), None => " (모르면 \"미정\"이라고 적으세요)".into() };
            self.err(format!("{label}: 시작 연도가 없거나 올바르지 않습니다.{why}"), kind, Some(i));
            return None;
        }
        let ed = if ongoing || end_unknown { None } else { dates::date_in(ctx, x, "end") };
        let mut end = ed.as_ref().map(|d| d.t);
        let mut end_at = ed.as_ref().and_then(|d| d.at.clone());
        if end.is_some_and(f64::is_nan) {
            let why = ed.as_ref().and_then(|d| d.error.clone()).map_or(String::new(), |e| format!(" {e}"));
            self.err(format!("{label}: 끝 연도가 올바르지 않습니다.{why}"), kind, Some(i));
            return None;
        }
        let start_hint = if start_unknown { hint_of(&x.get("startHint"), &x.get("start")) } else { None };
        let end_hint = if end_unknown { hint_of(&x.get("endHint"), &x.get("end")) } else { None };
        if start_unknown { start = start_hint.or(end); }
        let Some(start) = start else {
            self.err(format!("{label}: 시작 연도가 미정이면 끝 연도나 배치용 연도(startHint)가 필요합니다."), kind, Some(i));
            return None;
        };
        if end_unknown { end = end_hint.or(Some(start)); }
        if let Some(e) = end {
            if dates::end_bound_t(ctx, e, &end_at.clone().map_or(V::Null, V::Str)) < start {
                self.err(format!("{label}: 끝 연도가 시작 연도보다 앞섭니다."), kind, Some(i));
                return None;
            }
        }
        // 같은 때에 끝나면 한 시점 — 시작이 미정이면 끝은 적은 사실이라 그대로
        if end == Some(start) && !end_unknown && !start_unknown { end = None; end_at = None; }
        if start_unknown { start_at = None; }
        if end_unknown { end_at = None; }
        Some(Range { start, end, ongoing, start_unknown, end_unknown, start_at, end_at })
    }

    /// `checkTrack(track, label, kind, i)` — 이 DLC의 트랙인가(아니면 오류).
    fn check_track(&mut self, track: &Str, label: &str, kind: &str, i: usize) -> bool {
        if self.track_ids.contains(track) { return true; }
        self.err(if track.is_empty() { format!("{label}: 트랙이 지정되지 않았습니다.") } else { format!("{label}: 트랙 \"{track}\"이(가) 이 DLC의 트랙 목록에 없습니다.") }, kind, Some(i));
        false
    }
}

/// `applyRange(o, r)`.
fn apply_range(o: &Obj, r: &Range) {
    o.set("start", r.start);
    if let Some(at) = r.start_at.clone().filter(|s| !s.is_empty()) { o.set("startAt", at); }
    if let Some(end) = r.end {
        o.set("end", end);
        if let Some(at) = r.end_at.clone().filter(|s| !s.is_empty()) { o.set("endAt", at); }
    }
    if r.ongoing { o.set("ongoing", true); }
    if r.start_unknown { o.set("startUnknown", true); }
    if r.end_unknown { o.set("endUnknown", true); }
}

/// 수 `Math.floor(t + 1e-9)`의 글(씨앗 잇기 — `String(n)`).
fn floor_text(t: f64) -> Str { Str::from(js::num_str((t + 1e-9).floor())) }

/// 형식 3 목록 읽기(`HT.readViews` · `HT.readMaps` · `HT.readFonts` · `HT.readImages`)의 알림 통로 — `report.err(msg, i)` → `err(msg, key, i)`.
struct To<'a, 'c> { n: &'a mut Norm<'c>, key: &'a str }
impl info::Report for To<'_, '_> {
    fn err(&mut self, msg: String, i: usize) { self.n.err(msg, self.key, Some(i)); }
    fn warn(&mut self, msg: String, i: usize) { self.n.warn(msg, self.key, Some(i)); }
}

/// `pack[k]`(정규화한 팩의 목록 — `pack.periods.push(o)`처럼 미리 만든 빈 목록에 넣는다).
fn list_of(pack: &Obj, k: &str) -> js::Arr { pack.arr(k).expect("pack의 목록") }

/// `HT.normalizePack(raw)` — DLC 원본 객체를 검사하고 깨끗한 꼴로 바꾼다. errors: 고쳐야 하는 문제(kind 'info'이면 치명적 → pack None) ·
/// warnings: 자동으로 보정했거나 참고할 문제. 오류가 있는 개별 항목은 결과 pack에서 빠진다.
pub fn normalize_pack(ctx: &Ctx, raw: V) -> Normalized {
    let mut n = Norm { ctx, errors: Vec::new(), warnings: Vec::new(), track_ids: HashSet::new(), cat_ids: HashSet::new(), item_ids: HashSet::new() };
    let done = |n: Norm, pack: Option<V>| Normalized { pack, errors: n.errors, warnings: n.warnings };

    if !js::truthy(&raw) || !super::is_plain(&raw) {
        n.err("DLC 파일의 최상위가 객체({ ... })가 아닙니다.".into(), "info", None);
        return done(n, None);
    }
    let mut raw = raw;
    // 형식 4(리메이크 1단계 1a — 설계 3-8): 지금 화면이 읽는 옛 꼴로 내려 읽는다. 저장은 5단계 전까지 옛 형식
    if js::to_num(&raw.get("formatVersion")) == f4::VERSION {
        let mut notes = Vec::new();
        let down = f4::down(ctx, &raw, &mut |m| notes.push(m));
        for m in notes { n.warn(m, "info", None); }
        match down {
            Ok(v) => raw = v,
            Err(e) => {
                n.err(format!("형식 4 파일을 읽지 못했습니다 — {e}"), "info", None);
                return done(n, None);
            }
        }
    }
    if !matches!(raw.get("format"), V::Str(s) if s == vocab::FORMAT) { n.err(format!("\"format\" 값이 \"{}\"이어야 합니다. 이 프로그램용 DLC 파일이 맞는지 확인하세요.", vocab::FORMAT), "info", None); }
    if js::to_num(&raw.get("formatVersion")) > vocab::FORMAT_VERSION {
        n.warn(format!("더 새로운 형식 버전({})으로 만들어진 파일입니다. 일부 정보가 무시될 수 있습니다.", js::to_str(&raw.get("formatVersion"))), "info", None);
    }

    let pack = Obj::new();
    pack.set("format", vocab::FORMAT);
    pack.set("formatVersion", vocab::FORMAT_VERSION);
    let id = dates::str_of(&raw.get("id"));
    pack.set("id", id.clone());
    pack.set("name", dates::str_of(&raw.get("name")));
    pack.set("version", js::or(V::Str(dates::str_of(&raw.get("version"))), V::from("1.0.0")));
    pack.set("author", dates::str_of(&raw.get("author")));
    pack.set("description", dates::str_of(&raw.get("description")));
    pack.set("requires", super::arr_of(dates::arr(&raw.get("requires")).iter().map(dates::str_of).filter(|s| !s.is_empty()).map(V::Str).collect()));
    {
        let mut msgs = Vec::new();
        let info = info::read_pack_info(&raw, &mut |m| msgs.push(m), &id); // 팩 정보의 새 칸 — 적은 것만(docs/구상-메이커-팩.md 2-2)
        for m in msgs { n.warn(m, "info", None); }
        for (k, v) in info.entries() { pack.set(&k, v); }
    }
    for k in ["tracks", "categories", "peoples", "epochs", "periods", "organs", "cultures", "dynasties", "events", "patches"] { pack.set(k, super::arr_of(Vec::new())); }
    pack.set("documents", Obj::new());
    let list = |k: &str| list_of(&pack, k);
    if !dates::id_ok(&id) { n.err("DLC \"id\"는 영문·숫자·- _ . 만 쓸 수 있고 비어 있으면 안 됩니다.".into(), "info", None); }
    else if id == vocab::USER_PACK_ID { n.err(format!("\"{id}\"는 프로그램이 쓰는 예약어라서 DLC id로 쓸 수 없습니다."), "info", None); }
    if pack.str("name").is_none_or(|s| s.is_empty()) { n.err("DLC 이름(\"name\")이 비어 있습니다.".into(), "info", None); }

    // (putNames · putLineage — 형식 버전 3의 칸 읽기(이름 목록 · 사람 잇기): 위 Norm의 메서드 · 과제 5b가 옮김)

    // 문화권 사전(spheres — core.js f90a60d102ce 3945 ~ 3948줄 · 2026-10-23) — 있을 때만 열쇠가 생긴다(옛 파일은 그대로). 트랙의 sphere가 가리킨다 — 이 DLC의 것 · 다른 켠 DLC의 것
    {
        let spheres = cells::read_spheres(&raw.get("spheres"));
        for (k, msg) in spheres.problems.iter().enumerate() { n.warn(msg.clone(), "spheres", spheres.at[k]); }
        if !spheres.list.is_empty() { pack.set("spheres", super::arr_of(spheres.list)); }
    }

    // 트랙
    for (i, t) in dates::arr(&raw.get("tracks")).iter().enumerate() {
        let id = dates::str_of(&super::and(t, "id"));
        if !dates::id_ok(&id) { n.err(format!("트랙 #{}: id가 비었거나 올바르지 않습니다.", i + 1), "tracks", Some(i)); continue; }
        if n.track_ids.contains(&id) { n.warn(format!("트랙 \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "tracks", Some(i)); continue; }
        n.track_ids.insert(id.clone());
        let o = Obj::new();
        o.set("id", id.clone());
        let name = dates::str_of(&t.get("name"));
        o.set("name", if name.is_empty() { id.clone() } else { name });
        o.set("color", if misc::is_color(&t.get("color")) { t.get("color") } else { V::from(misc::auto_color(&V::Str(id.clone()))) });
        let order = t.get("order");
        if !super::is_empty_str(&order) && !order.is_nullish() && js::to_num(&order).is_finite() { o.set("order", js::to_num(&order)); }
        let description = dates::str_of(&t.get("description"));
        if !description.is_empty() { o.set("description", description); }
        if !dates::str_of(&t.get("wiki")).is_empty() { o.set("wiki", js::to_str(&t.get("wiki"))); }
        // 문화권(조각 ② · core.js f90a60d102ce 3960 ~ 3965줄): 이 DLC나 다른 켠 DLC(기본팩 등)의 spheres에 만든 id — 올바른 id면 그대로 둔다.
        // 모델이 켠 DLC 가운데 만든 곳을 못 찾으면 문화권 없이 놓고 알린다(모델의 sphereWarnings)
        let sphere = dates::str_of(&t.get("sphere"));
        if !sphere.is_empty() {
            if dates::id_ok(&sphere) { o.set("sphere", sphere); }
            else { n.warn(format!("트랙 \"{id}\"의 문화권 \"{sphere}\"은(는) id가 올바르지 않아 뺐습니다."), "tracks", Some(i)); }
        }
        list("tracks").push(V::Obj(o));
    }

    // 분류
    n.cat_ids = vocab::DEFAULT_CATEGORIES.iter().map(|c| Str::from(*c)).collect();
    for (i, c) in dates::arr(&raw.get("categories")).iter().enumerate() {
        let id = dates::str_of(&super::and(c, "id"));
        if !dates::id_ok(&id) { n.err(format!("분류 #{}: id가 비었거나 올바르지 않습니다.", i + 1), "categories", Some(i)); continue; }
        if list("categories").to_vec().iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) {
            n.warn(format!("분류 \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "categories", Some(i));
            continue;
        }
        n.cat_ids.insert(id.clone());
        let o = Obj::new();
        o.set("id", id.clone());
        let name = dates::str_of(&c.get("name"));
        o.set("name", if name.is_empty() { id.clone() } else { name });
        o.set("color", if misc::is_color(&c.get("color")) { c.get("color") } else { V::from(misc::auto_color(&V::Str(id))) });
        list("categories").push(V::Obj(o));
    }

    // 민족 — 시대를 묶는 단위. 시대의 people에 이름이나 id로 적는다
    for (i, p) in dates::arr(&raw.get("peoples")).iter().enumerate() {
        let id = dates::str_of(&super::and(p, "id"));
        let name = dates::str_of(&super::and(p, "name"));
        if !dates::id_ok(&id) {
            n.err(format!("민족 #{}{}: id가 비었거나 올바르지 않습니다.", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") }), "peoples", Some(i));
            continue;
        }
        if list("peoples").to_vec().iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) {
            n.warn(format!("민족 \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "peoples", Some(i));
            continue;
        }
        let o = Obj::new();
        o.set("id", id.clone());
        o.set("name", if name.is_empty() { id.clone() } else { name.clone() });
        let parent = dates::str_of(&p.get("parent"));
        if !parent.is_empty() { o.set("parent", parent); } // 상위 민족(대명제)의 id나 이름 — 단계는 얼마든지
        if misc::is_color(&p.get("color")) { o.set("color", p.get("color")); }
        let description = dates::str_of(&p.get("description"));
        if !description.is_empty() { o.set("description", description); }
        if !dates::str_of(&p.get("wiki")).is_empty() { o.set("wiki", js::to_str(&p.get("wiki"))); }
        let order = p.get("order");
        if !super::is_empty_str(&order) && !order.is_nullish() && js::to_num(&order).is_finite() { o.set("order", js::to_num(&order)); }
        // 배열 기준(형식 버전 3 — HT.readRowOrder): 'start'(지금 규칙)도 적은 대로 둔다(상위 민족의 기준을 물려받지 않게 끊는 값)
        match misc::read_row_order(&p.get("rowOrder")) {
            Some(ro) if !ro.is_empty() => o.set("rowOrder", ro),
            Some(_) => {}
            None => n.warn(format!("민족 \"{}\": 배열 기준(rowOrder) \"{}\"을(를) 몰라 뺐습니다 — \"start\"(시작 연도) · \"northSouth\"(북 → 남).",
                if name.is_empty() { id.clone() } else { name }, dates::str_of(&p.get("rowOrder"))), "peoples", Some(i)),
        }
        list("peoples").push(V::Obj(o));
    }

    // 지위 사전(rankDefs) — 있을 때만 칸이 생긴다(옛 파일은 그대로)
    {
        let rank_defs = cells::read_rank_defs(&raw.get("rankDefs"));
        for (k, msg) in rank_defs.problems.iter().enumerate() { n.warn(msg.clone(), "rankDefs", rank_defs.at[k]); }
        if !rank_defs.list.is_empty() { pack.set("rankDefs", super::arr_of(rank_defs.list)); }
    }

    // 가문 — 국성 · 왕가 · 집안. 시대(= 국성) · 지도자 · 내각 · 왕조 · 인물의 house에 이 이름이나 id를 적는다(등록하지 않은 이름을 적어도 된다 — 모델이 그 이름으로 만든다).
    // id를 비우면 이름으로 만들고, parent(본가)를 적으면 본가 → 분가 나무가 된다. 가문이 하나도 없으면 houses 열쇠를 만들지 않는다(옛 파일이 예전 그대로 나가게)
    let mut houses: Vec<V> = Vec::new();
    for (i, h) in dates::arr(&raw.get("houses")).iter().enumerate() {
        if !js::truthy(h) || !super::is_object(h) { n.err(format!("가문 #{}: 형식이 올바르지 않습니다.", i + 1), "houses", Some(i)); continue; }
        let name = dates::str_of(&h.get("name"));
        let mut id = dates::str_of(&h.get("id"));
        let label = format!("가문 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if id.is_empty() && name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "houses", Some(i)); continue; }
        if !id.is_empty() && !dates::id_ok(&id) { n.err(format!("{label}: id가 올바르지 않습니다."), "houses", Some(i)); continue; }
        if id.is_empty() { id = super::cat(&[&Str::from("h-"), &misc::hash(&name)]); }
        if houses.iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) { n.warn(format!("가문 \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "houses", Some(i)); continue; }
        let o = Obj::new();
        o.set("id", id.clone());
        o.set("name", if name.is_empty() { id } else { name });
        for k in ["surname", "seat", "parent", "founder"] { // 성 · 본관 · 본가(가문의 id나 이름) · 시조
            let t = dates::str_of(&h.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        // 세계표 머리의 구분(트랙 id) · 민족(이름 · id) · 꼬리표(형식 버전 3): 트랙은 다른 DLC의 것일 수 있어 검사하지 않고, 비우면 모델이 짐작한다(파일에 적지 않음)
        for k in ["track", "people"] {
            let t = dates::str_of(&h.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        let htags = name_list(&h.get("tags")); // 사건의 tags와 같은 읽기(배열 · 쉼표 글)
        if !htags.is_empty() { o.set("tags", super::arr_of(htags.into_iter().map(V::Str).collect())); }
        if misc::is_color(&h.get("color")) { o.set("color", h.get("color")); }
        let description = dates::str_of(&h.get("description"));
        if !description.is_empty() { o.set("description", description); }
        if !dates::str_of(&h.get("wiki")).is_empty() { o.set("wiki", js::to_str(&h.get("wiki"))); }
        n.put_names(&o, &h.get("names"), &label, "houses", i); // 이름 목록 (형식 버전 3)
        houses.push(V::Obj(o));
    }
    if !houses.is_empty() { pack.set("houses", super::arr_of(houses)); }

    // 주제 사전(themes — 형식 버전 3): 있을 때만 칸이 생긴다(지위 사전과 같은 읽기 · 옛 파일은 그대로)
    {
        let theme_defs = groups::read_theme_defs(ctx, &raw.get("themes"));
        for (k, msg) in theme_defs.problems.iter().enumerate() { n.warn(msg.clone(), "themes", theme_defs.at[k]); }
        if !theme_defs.list.is_empty() { pack.set("themes", super::arr_of(theme_defs.list)); }
    }
    // 성씨 사전(형식 버전 3 — 3-2 성씨 층): 가문의 surname(성)이 이 이름이나 id로 이어진다. 사전에 없는 성도 된다(모델이 가문들의 성에서 저절로 모음).
    // 원어를 달고 싶을 때만 적는다. id를 비우면 이름으로 만들고(sn-…), 목록이 비면 열쇠를 만들지 않는다(옛 파일 그대로)
    let mut surnames: Vec<V> = Vec::new();
    for (i, x) in dates::arr(&raw.get("surnames")).iter().enumerate() {
        if !js::truthy(x) || !super::is_object(x) { n.err(format!("성씨 #{}: 형식이 올바르지 않습니다.", i + 1), "surnames", Some(i)); continue; }
        let name = dates::str_of(&x.get("name"));
        let label = format!("성씨 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "surnames", Some(i)); continue; }
        let mut id = dates::str_of(&x.get("id"));
        if !id.is_empty() && !dates::id_ok(&id) { n.err(format!("{label}: id가 올바르지 않습니다."), "surnames", Some(i)); continue; }
        if id.is_empty() { id = super::cat(&[&Str::from("sn-"), &misc::hash(&name)]); }
        if surnames.iter().any(|q| js::strict_eq(&q.get("id"), &V::Str(id.clone()))) { n.warn(format!("성씨 \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "surnames", Some(i)); continue; }
        let o = Obj::new();
        o.set("id", id);
        o.set("name", name);
        n.put_names(&o, &x.get("names"), &label, "surnames", i);
        let description = dates::str_of(&x.get("description"));
        if !description.is_empty() { o.set("description", description); }
        if !dates::str_of(&x.get("wiki")).is_empty() { o.set("wiki", js::to_str(&x.get("wiki"))); }
        surnames.push(V::Obj(o));
    }
    if !surnames.is_empty() { pack.set("surnames", super::arr_of(surnames)); }
    // 지명 사전(형식 버전 3 — 바탕 3): 도읍의 city · 사건의 place가 이 이름이나 id로 가리킨다. 사전에 없는 이름도 된다.
    // at = 좌표 [x, y] · parent = 위 구역 지명(이름이나 id). id를 비우면 이름으로 만든다(pl-…)
    let mut places: Vec<V> = Vec::new();
    for (i, x) in dates::arr(&raw.get("places")).iter().enumerate() {
        if !js::truthy(x) || !super::is_object(x) { n.err(format!("지명 #{}: 형식이 올바르지 않습니다.", i + 1), "places", Some(i)); continue; }
        let name = dates::str_of(&x.get("name"));
        let label = format!("지명 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "places", Some(i)); continue; }
        let mut id = dates::str_of(&x.get("id"));
        if !id.is_empty() && !dates::id_ok(&id) { n.err(format!("{label}: id가 올바르지 않습니다."), "places", Some(i)); continue; }
        if id.is_empty() { id = super::cat(&[&Str::from("pl-"), &misc::hash(&name)]); }
        if places.iter().any(|q| js::strict_eq(&q.get("id"), &V::Str(id.clone()))) { n.warn(format!("지명 \"{id}\"가 중복되어 뒤의 것을 무시했습니다."), "places", Some(i)); continue; }
        let o = Obj::new();
        o.set("id", id.clone());
        o.set("name", name.clone());
        n.put_names(&o, &x.get("names"), &label, "places", i);
        if super::given(&x.get("at")) {
            match names::read_coords(&x.get("at")) {
                Some(at) => o.set("at", super::arr_of(at.into_iter().map(V::Num).collect())),
                None => n.warn(format!("{label}: 좌표(at)는 [x, y] 두 수로 적습니다 — 뺐습니다."), "places", Some(i)),
            }
        }
        let parent = dates::str_of(&x.get("parent"));
        if !parent.is_empty() {
            if parent == name || parent == id { n.warn(format!("{label}: 위 구역(parent)이 자기 자신이라 뺐습니다."), "places", Some(i)); }
            else { o.set("parent", parent); }
        }
        for k in ["note", "description"] {
            let t = dates::str_of(&x.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !dates::str_of(&x.get("wiki")).is_empty() { o.set("wiki", js::to_str(&x.get("wiki"))); }
        places.push(V::Obj(o));
    }
    if !places.is_empty() { pack.set("places", super::arr_of(places)); }

    // (itemIds · takeId · readRange · applyRange · checkTrack — 위 Norm의 메서드)
    // (readCells · readCapitals · readSuccList · warnPartOfUnknown · readUncertainty · readNames(쉼표 목록 name_list) · readService — cell_lists.rs)

    // 시대 구분(선사 · 고대 · 중세 …): 맨 위 날짜 칸에 색 띠로. track을 적으면 그 나라 줄에, 비우면 공통 줄에
    for (i, e) in dates::arr(&raw.get("epochs")).iter().enumerate() {
        if !js::truthy(e) || !super::is_object(e) { n.err(format!("시대 구분 #{}: 형식이 올바르지 않습니다.", i + 1), "epochs", Some(i)); continue; }
        let name = dates::str_of(&e.get("name"));
        let label = format!("시대 구분 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "epochs", Some(i)); continue; }
        let track = dates::str_of(&e.get("track"));
        if !track.is_empty() && !n.check_track(&track, &label, "epochs", i) { continue; }
        let Some(r) = n.read_range(e, &label, "epochs", i) else { continue };
        let seed = super::cat(&[&track, &floor_text(r.start), &name]);
        let o = Obj::new();
        o.set("id", n.take_id(e, "ep-", &seed, &label, "epochs", i));
        o.set("name", name);
        apply_range(&o, &r);
        if !track.is_empty() { o.set("track", track.clone()); }
        // 형식 4 더하기 — 시대 구분의 문화권(sphere · 5단계 과제 6): 그 문화권 머리 단 밑 시대 줄에. 트랙과 양자택일 — 둘 다 적으면 트랙이 우선하고 알림
        {
            let sp = dates::str_of(&e.get("sphere"));
            if !sp.is_empty() {
                if !dates::id_ok(&sp) { n.warn(format!("{label}: 문화권 id \"{sp}\"이(가) 올바르지 않아 뺐습니다."), "epochs", Some(i)); }
                else {
                    o.set("sphere", sp);
                    if !track.is_empty() { n.warn(format!("{label}: 트랙과 문화권을 함께 적어 트랙이 우선합니다 — 문화권 줄에 두려면 트랙을 비우세요."), "epochs", Some(i)); }
                }
            }
        }
        if misc::is_color(&e.get("color")) { o.set("color", e.get("color")); }
        for k in ["note", "description"] {
            let t = dates::str_of(&e.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !dates::str_of(&e.get("wiki")).is_empty() { o.set("wiki", js::to_str(&e.get("wiki"))); }
        let within = dates::str_of(&e.get("within"));
        if !within.is_empty() { o.set("within", within); } // 든 그릇(대범위 id · 이름 — 리메이크 2부 포개짐)
        let mut msgs = Vec::new();
        let unc = cells::read_uncertain(ctx, e, "epoch", Some(&mut |m: String| msgs.push(m)), None, None, None); // 다른 견해만
        for m in msgs { n.warn(format!("{label}: {m}"), "epochs", Some(i)); }
        for (k, v) in unc.entries() { o.set(&k, v); }
        list("epochs").push(V::Obj(o));
    }

    // 대범위(docs/구상-체제-확장.md 7 · 8-4 바): 여러 민족 묶음에 흩어진 정권들을 한 집합으로 묶어, 켜면 한 가지로 모여 보이는 단위.
    // track · members 필수, name은 epoch이 없을 때 필수. 기간은 선택 — 비우면 시대 구분에서, 그것도 없으면 구성 정권의 범위에서(모델). host = 상징적 본국.
    let mut scopes: Vec<V> = Vec::new();
    for (i, s) in dates::arr(&raw.get("scopes")).iter().enumerate() {
        if !js::truthy(s) || !super::is_object(s) { n.err(format!("대범위 #{}: 형식이 올바르지 않습니다.", i + 1), "scopes", Some(i)); continue; }
        let name = dates::str_of(&s.get("name"));
        let epoch = dates::str_of(&s.get("epoch"));
        let shown = if name.is_empty() { epoch.clone() } else { name.clone() };
        let label = format!("대범위 #{}{}", i + 1, if shown.is_empty() { String::new() } else { format!(" \"{shown}\"") });
        if name.is_empty() && epoch.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다. (시대 구분(epoch)을 적으면 그 이름을 물려받습니다)"), "scopes", Some(i)); continue; }
        let track = dates::str_of(&s.get("track"));
        if !n.check_track(&track, &label, "scopes", i) { continue; }
        let mut refs: Vec<cells::ScopeRef> = Vec::new();
        let in_track = |q: &cells::ScopeRef| q.track.clone().filter(|t| !t.is_empty()).unwrap_or_else(|| track.clone());
        for r in cells::read_scope_refs(&s.get("members")) {
            if !refs.iter().any(|q| q.polity == r.polity && in_track(q) == in_track(&r)) { refs.push(r); }
        }
        if refs.is_empty() { n.err(format!("{label}: 구성 정권(members)이 없습니다."), "scopes", Some(i)); continue; }
        let has_start = super::given(&s.get("start"));
        let mut r = None;
        if has_start {
            r = n.read_range(s, &label, "scopes", i);
            if r.is_none() { continue; }
        } else if super::given(&s.get("end")) || matches!(s.get("ongoing"), V::Bool(true)) {
            n.warn(format!("{label}: 시작 없이 끝만 적어 기간을 무시했습니다. (비우면 시대 구분이나 구성 정권의 기간을 씁니다)"), "scopes", Some(i));
        }
        let tail = r.as_ref().map_or(Str::default(), |r| floor_text(r.start));
        let seed = super::cat(&[&track, &shown, &tail]);
        let o = Obj::new();
        o.set("id", n.take_id(s, "s-", &seed, &label, "scopes", i));
        o.set("track", track.clone());
        if !name.is_empty() { o.set("name", name.clone()); }
        let short = dates::str_of(&s.get("label"));
        if !short.is_empty() { o.set("label", short); }
        if let Some(r) = &r { apply_range(&o, r); }
        o.set("members", super::arr_of(refs.iter().map(cells::ScopeRef::compact).collect()));
        if !epoch.is_empty() { o.set("epoch", epoch); }
        // 부모 그릇(리메이크 2부 · 설계 3-3 포개짐 — 같은 트랙의 대범위 id · 이름)
        let within = dates::str_of(&s.get("within"));
        if !within.is_empty() {
            if within == dates::str_of(&s.get("id")) || within == name { n.warn(format!("{label}: 부모 그릇(within)이 자기 자신이라 뺐습니다."), "scopes", Some(i)); }
            else { o.set("within", within); }
        }
        if let Some(host) = cells::read_scope_ref(&s.get("host")) {
            o.set("host", host.compact());
            if refs.iter().any(|q| q.polity == host.polity && in_track(q) == in_track(&host)) {
                n.warn(format!("{label}: 상징적 본국 \"{}\"이(가) 구성 정권에도 들어 있습니다. 본국은 모이지 않습니다.", host.polity), "scopes", Some(i));
            }
        }
        let other: Vec<&cells::ScopeRef> = refs.iter().filter(|q| q.track.as_ref().is_some_and(|t| !t.is_empty() && *t != track)).collect();
        if !other.is_empty() {
            let names: Vec<String> = other.iter().map(|q| format!("{}:{}", q.track.clone().unwrap_or_default(), q.polity)).collect();
            n.warn(format!("{label}: 다른 트랙의 정권({})은 모이지 않습니다. 구성 정권은 같은 트랙 안에서만 모입니다.", names.join(", ")), "scopes", Some(i));
        }
        if misc::is_color(&s.get("color")) { o.set("color", s.get("color")); }
        if matches!(s.get("default"), V::Bool(true)) { o.set("default", true); } // 처음부터 켬(끔이 기본이라 false는 적지 않음)
        for k in ["description", "note"] {
            let t = dates::str_of(&s.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !dates::str_of(&s.get("wiki")).is_empty() { o.set("wiki", js::to_str(&s.get("wiki"))); }
        scopes.push(V::Obj(o));
    }
    if !scopes.is_empty() { pack.set("scopes", super::arr_of(scopes)); }

    // 형식 3 — 모아 보기 판 · 지도(1단계) · 글꼴(HT.readViews · HT.readMaps · HT.readFonts). 목록이 비면 열쇠를 만들지 않는다
    for (key, what) in [("views", "모아 보기 판(views)"), ("maps", "지도(maps)"), ("fonts", "글꼴(fonts)")] {
        let value = raw.get(key);
        if value.is_nullish() { continue; }
        if !matches!(value, V::Arr(_)) {
            n.warn(format!("{what}은 목록이어야 해서 무시했습니다."), key, None);
            continue;
        }
        let mut to = To { n: &mut n, key };
        let list = match key { "views" => info::read_views(ctx, &value, &mut to), "maps" => info::read_maps(ctx, &value, &mut to), _ => info::read_fonts(&value, &mut to) };
        if !list.is_empty() { pack.set(key, super::arr_of(list)); }
    }
    // 형식 3 — 간지 설정(HT.readYearCycle): false(간지 줄 기본 끔) · { names, start, label }. 적지 않으면 열쇠를 만들지 않는다(육십갑자 — 옛 파일 그대로)
    {
        let mut msgs = Vec::new();
        let yc = misc::read_year_cycle(ctx, &raw.get("yearCycle"), &mut |m| msgs.push(m));
        for m in msgs { n.warn(m, "yearCycle", None); }
        if !yc.is_undef() { pack.set("yearCycle", yc); }
    }
    // 형식 4 더하기 — 문화권별 주기 줄(yearCycles · HT.readYearCycles · 5단계 과제 6): 다리가 그대로 실어 오는 것을 정규화가 지킨다. 목록이 비면 열쇠를 만들지 않는다
    if !raw.get("yearCycles").is_nullish() {
        let mut msgs: Vec<(String, Option<usize>)> = Vec::new();
        let ycs = misc::read_year_cycles(ctx, &raw.get("yearCycles"), &mut |m, at| msgs.push((m, at)));
        for (m, at) in msgs { n.warn(m, "yearCycles", at); }
        if !ycs.is_empty() { pack.set("yearCycles", super::arr_of(ycs)); }
    }

    // 형식 3 — 문서 그림(images — docs::read_images · DLC-형식.md의 '문서 그림'). 목록이 비면 열쇠를 만들지 않는다
    let images = raw.get("images");
    if !images.is_nullish() {
        if !matches!(images, V::Arr(_)) { n.warn("문서 그림(images)은 목록이어야 해서 무시했습니다.".into(), "images", None); }
        else {
            let list = docs::read_images(&images, &mut To { n: &mut n, key: "images" });
            if !list.is_empty() { pack.set("images", super::arr_of(list)); }
        }
    }

    bands::read_bands(&mut n, &pack, &raw); // 4381 ~ 4551줄 — 기관 · 문화 · 왕조 · 시대

    items::read_events(&mut n, &pack, &raw); // 4553 ~ 4618줄 — 사건
    items::read_figures(&mut n, &pack, &raw); // 4620 ~ 4709줄 — 인물
    items::read_groups(&mut n, &pack, &raw); // 4711 ~ 4754줄 — 단체
    items::read_institutions(&mut n, &pack, &raw); // 4756 ~ 4779줄 — 제도
    patches::read_patches(&mut n, &pack, &raw); // 4781 ~ 4967줄 — 패치
    rest::read_documents(&mut n, &pack, &raw); // 4969 ~ 4981줄 — 문서
    rest::read_territory(&mut n, &pack, &raw); // 4983 ~ 5064줄 — 영토

    let len = |k: &str| pack.arr(k).map_or(0, |a| a.len());
    let has = |k: &str| js::truthy(&pack.get(k));
    if len("periods") == 0 && len("events") == 0 && len("organs") == 0 && len("cultures") == 0 && len("dynasties") == 0 && len("patches") == 0 && !has("territory")
        && pack.obj("documents").is_none_or(|d| d.is_empty()) && len("epochs") == 0 && !has("figures") && len("houses") == 0 && len("scopes") == 0
        && !has("groups") && !has("institutions") && !has("surnames") && !has("places")
    {
        // 성씨 · 지명 사전만 담은 DLC도 빈 DLC가 아님(형식 3)
        n.warn("시대·사건·기관·문화·왕조·가문·인물·대범위·단체·제도·패치·문서·영토가 하나도 없습니다.".into(), "info", None);
    }
    let last_is_empty = |n: &Norm| n.warnings.last().is_some_and(|w| w.msg.contains("하나도 없습니다"));
    if (has("rankDefs") || has("spheres")) && last_is_empty(&n) { n.warnings.pop(); } // 지위 사전 · 문화권 사전만 담은 DLC는 빈 DLC가 아니다
    if (has("views") || has("maps") || has("fonts") || has("themes")) && last_is_empty(&n) { n.warnings.pop(); } // 형식 3: 모아 보기 판 · 지도 · 글꼴 · 주제 사전만 담은 DLC도
    let fatal = n.errors.iter().any(|x| x.kind == "info");
    done(n, if fatal { None } else { Some(V::Obj(pack)) })
}

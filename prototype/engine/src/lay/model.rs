//! 모델 — `js/core.js`의 `HT.buildModel(packs, user, opts)`를 줄 그대로 옮긴다(한 벌 P3 과제 6). 내보내기와 같게 `user = null` · `opts.groupBands = true`만 쓴다.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - (2026-10-24 맞춤 · `core.js` `f90a60d102ce`) 7872 ~ 7891줄 문화권 사전(`HT.mergeSpheres` · `sphereWarnings` — [`Build::new`]) · `addTrack`의 문화권(사전에 있는 것만) · 8830 ~ 8848줄 트랙 차례 · 모델의 `spheres` · `sphereMap` · `sphereWarnings`
//! - 7844 ~ 8826줄 `HT.buildModel` — JS 함수 하나가 길어(983줄) 절 경계로 나눈 함수들이 같은 차례로 잇는다:
//!   - [`Build`] 7844 ~ 7902줄(머리 — `addTrack` · `addCat` · `addPeople` · `derive` · `deco` · `decoFigure` · `decoInst` · `HT.organAsPeriod` · `cultureAsPeriod` · `dynastyAsPeriod`)
//!   - [`build_model`] 7903 ~ 8032줄(팩 차례 · 패치 · 기관/왕조의 소속 · 단체의 띠) → `model/parts.rs`가 이어 8033 ~ 8826줄(목록 · 조약 칸 · 사건 차례 · 트랙 · 분류 · 띠 색 · 민족 ·
//!     민족 계층 · 소속 · 칸의 미정 · 왕조 · 지명 · 도읍 · 시기 · 지위 · 사건의 정권 · 승계 · 부모 사건 · 공동 사건 · 조약 · 인물 · 대범위 · 제도 · 단체 · 주제 · 문서 · 모델 · `link*` · 칸의 경계)
//! - 도움 함수: [`util`](색 · 낱말 · 이설 · 날짜 · 문서 키) · [`cells`](칸의 미정 · 도읍 · 시기 · 지위 · 주제 · 갈래 색 · 단체 색) · [`bounds`](칸의 경계 `HT.cellBounds` — 열거되지 않는 속성)
//!
//! 값은 JS 값 그대로(`V` — 옮기는 규칙 표의 첫 줄): 모델의 띠 · 사건 · 인물 · 사람 자리가 서로 가리키는 그래프를 `Rc` 같음까지 JS와 같게 짓는다
//! (이음매 ② `prep.json`의 덤프가 처음 만난 경로 · `$ref`로 그 나눠 가짐을 견준다). `user`(옛 내 수정)는 내보내기가 넘기지 않아 옮기지 않았다(`HT.USER_LISTS`의 내 항목 · 숨김 · 고침 · 내 문서).
use crate::lay::js::{self, Arr, Map, Obj, V};
use crate::lay::read::{self, Ctx as RCtx};
use std::cell::Cell;

/// `{ k: v, … }` — 열쇠 차례대로 새 객체.
macro_rules! o {
    () => { $crate::lay::js::Obj::new() };
    ($($k:expr => $v:expr),+ $(,)?) => {{ let o = $crate::lay::js::Obj::new(); $( o.set($k, $v); )+ o }};
}
pub(crate) use o;

pub mod bounds;
pub mod kinds;
pub mod cells;
mod parts;
pub mod util;

use util::{arr, assign_obj, auto_color, certainty_of, copy, dated_alts, eq, is, kind_of, list, lt, n, nn, ob, or, pastel, s, t, tv};

/// `const EPOCH_PALETTE`(시대 구분의 자동 색).
const EPOCH_PALETTE: [&str; 8] = ["#c8b193", "#a0bcc5", "#b6c398", "#bbacc8", "#dab195", "#9dbea8", "#abb3c9", "#d1a9b9"];

/// `buildModel`의 지역 값(절마다 나눈 함수가 함께 쓴다). 지도 · 목록은 JS 값 그대로(넣은 차례 · 같음).
pub(crate) struct Build<'a> {
    pub rc: &'a RCtx,
    pub tracks: Map,
    pub categories: Map,
    seq: Cell<f64>,
    pub peoples: Map,
    pseq: Cell<f64>,
    pub period_map: Map,
    pub event_map: Map,
    pub figure_map: Map,
    pub group_map: Map,
    pub inst_map: Map,
    pub epochs: Arr,
    pub docs: Map,
    /// 문화권 사전(`HT.mergeSpheres` — 켠 DLC들의 spheres · 차례대로)과 그 표(id → 같은 객체) · 만든 곳이 없는 문화권을 적은 트랙의 알림(모델의 `spheres` · `sphereMap` · `sphereWarnings`).
    pub spheres: Arr,
    pub sphere_map: Map,
    pub sphere_warnings: Arr,
}

impl<'a> Build<'a> {
    fn new(rc: &'a RCtx, packs: &[V]) -> Self {
        /* 문화권 사전(core.js f90a60d102ce 7873 ~ 7880줄 — 켠 DLC들의 spheres · 프로그램에 든 문화권은 없음): 트랙의 sphere를 풀기 전에 세운다.
           만든 곳이 없는 문화권 id를 적은 트랙 — 문화권 없이 놓고 알린다 [{ msg, packId, list: 'tracks', id }] (메이커의 검사 창 — orderWarnings와 같은 길) */
        let spheres = util::merge_spheres(packs);
        let sphere_map = Map::new();
        for x in &spheres { sphere_map.set(x.get("id"), x.clone()); }
        let sphere_warnings = Arr::default();
        for pack in packs {
            if !tv(pack) { continue; }
            for tr in list(&pack.get("tracks")) {
                let sp = if tv(&tr) { tr.get("sphere") } else { V::Undef };
                if tv(&sp) && !sphere_map.has(&sp) {
                    let msg = format!("트랙 \"{}\"의 문화권 \"{}\"을(를) 켠 DLC 가운데 만든 곳이 없어 문화권 없이 놓습니다 — 바탕 자료의 「문화권」에서 만들거나 다른 문화권을 고르세요.", t(&or(tr.get("name"), tr.get("id"))), t(&sp));
                    sphere_warnings.push(o! { "msg" => msg, "packId" => pack.get("id"), "list" => "tracks", "id" => tr.get("id") });
                }
            }
        }
        Build {
            rc, tracks: Map::new(), categories: Map::new(), seq: Cell::new(0.0), peoples: Map::new(), pseq: Cell::new(0.0),
            period_map: Map::new(), event_map: Map::new(), figure_map: Map::new(), group_map: Map::new(), inst_map: Map::new(), epochs: Arr::default(), docs: Map::new(),
            spheres: Arr::new(spheres), sphere_map, sphere_warnings,
        }
    }
    /// `addTrack(t)` — 문화권: 먼저 놓인 DLC가 적은 것(사전에 있는 것만) → 뒤 DLC가 적은 것 → 없음(빈 글). sphereSet = 사전에 있는 문화권을 DLC가 적었는가.
    pub fn add_track(&self, tr: &V) {
        let id = tr.get("id");
        if !self.tracks.has(&id) {
            let seq = self.seq.get();
            self.seq.set(seq + 1.0);
            let o = o! {
                "id" => id.clone(), "name" => or(tr.get("name"), id.clone()), "color" => pastel(&or(tr.get("color"), auto_color(&id))),
                "order" => nn(tr.get("order"), V::Num(1000.0 + seq)), "seq" => seq, "description" => or(tr.get("description"), s("")),
                "wiki" => or(tr.get("wiki"), s("")), "sphere" => if util::is_sphere(&self.sphere_map, &tr.get("sphere")) { tr.get("sphere") } else { s("") },
                "sphereSet" => util::is_sphere(&self.sphere_map, &tr.get("sphere")),
            };
            self.tracks.set(id, o);
        } else {
            let cur = self.tracks.get(&id);
            let c = ob(&cur);
            if !tv(&cur.get("wiki")) && tv(&tr.get("wiki")) { c.set("wiki", tr.get("wiki")); }
            if !tv(&cur.get("description")) && tv(&tr.get("description")) { c.set("description", tr.get("description")); }
            if !tv(&cur.get("sphereSet")) && util::is_sphere(&self.sphere_map, &tr.get("sphere")) {
                c.set("sphere", tr.get("sphere"));
                c.set("sphereSet", true);
            }
        }
    }
    /// `addCat(c)`.
    pub fn add_cat(&self, c: &V) {
        let id = c.get("id");
        if !self.categories.has(&id) {
            self.categories.set(id.clone(), o! { "id" => id.clone(), "name" => or(c.get("name"), id.clone()), "color" => pastel(&or(c.get("color"), auto_color(&id))) });
        }
    }
    /// `addPeople(p)` — 민족: id로 병합.
    pub fn add_people(&self, p: &V) {
        let id = p.get("id");
        if self.peoples.has(&id) { return; }
        let seq = self.pseq.get();
        self.pseq.set(seq + 1.0);
        self.peoples.set(id.clone(), o! {
            "id" => id.clone(), "name" => or(p.get("name"), id.clone()), "parent" => or(p.get("parent"), s("")),
            "color" => pastel(&or(p.get("color"), auto_color(&V::from(format!("people:{}", t(&id)))))),
            "description" => or(p.get("description"), s("")), "wiki" => or(p.get("wiki"), s("")), "order" => nn(p.get("order"), V::Num(1000.0 + seq)),
            "seq" => seq, "auto" => tv(&p.get("auto")),
        });
    }
    /// `derive(x)` — 파생 값: 끝 연도(endY) · 확실성 · 이설 · 연대 폭까지 포함한 전체 범위(spanMin · spanMax). x를 고쳐 돌려준다.
    pub fn derive(&self, x: Obj) -> Obj {
        let xv = V::Obj(x.clone());
        let alts = dated_alts(&xv);
        let now = self.rc.now_t;
        let alt_end = |a: &V| -> f64 { if a.bool("ongoing") { now } else { n(&nn(a.get("end"), a.get("start"))) } };
        let e0 = nn(x.get("end"), x.get("start"));
        let start = x.get("start");
        let end_y = if x.bool("ongoing") { V::Num(js::max(&[now, n(&start)])) }
            else if lt(&e0, &start) { V::Num(js::max(&[n(&start), n(&read::dates::end_bound(self.rc, &x.get("end"), &util::at_of(self.rc, &xv, "end")))])) }
            else { e0 };
        x.set("endY", end_y.clone());
        x.set("certainty", certainty_of(&xv));
        let sr = x.get("startRange");
        let mut lo = vec![n(&start), if tv(&sr) { n(&sr.get(&0.0)) } else { n(&start) }];
        lo.extend(alts.iter().map(|a| n(&a.get("start"))));
        x.set("spanMin", js::min(&lo));
        let er = x.get("endRange");
        let mut hi = vec![n(&end_y), if tv(&er) { n(&er.get(&1.0)) } else { n(&end_y) }];
        hi.extend(alts.iter().map(alt_end));
        x.set("spanMax", js::max(&hi));
        x
    }
    /// `deco(x, pack, kind, extra)` = `derive(Object.assign({}, x, extra, { kind, uid: "<팩 id>/<id>", packId, packName }))`.
    pub fn deco(&self, x: &V, pack: &V, kind: &str, extra: &Obj) -> Obj {
        let o = copy(x);
        assign_obj(&o, extra);
        o.set("kind", kind);
        o.set("uid", format!("{}/{}", t(&pack.get("id")), t(&x.get("id"))));
        o.set("packId", pack.get("id"));
        o.set("packName", pack.get("name"));
        self.derive(o)
    }
    /// `decoFigure(f, pack, extra)` — 인물은 시작이 없을 수 있어 derive를 거치지 않는다(시기는 아래 '인물' 절에서).
    fn deco_figure(&self, f: &V, pack: &V) -> Obj {
        let o = copy(f);
        o.set("kind", "figure");
        o.set("itemKind", "figure");
        o.set("uid", format!("{}/{}", t(&pack.get("id")), t(&f.get("id"))));
        o.set("packId", pack.get("id"));
        o.set("packName", pack.get("name"));
        o
    }
    /// `decoInst(x, pack)` — 제도 칸은 칸에서 기간이 나오므로 derive를 거치지 않는다.
    fn deco_inst(&self, x: &V, pack: &V) -> Obj {
        let o = copy(x);
        o.set("kind", "institution");
        o.set("itemKind", "institution");
        o.set("uid", format!("{}/{}", t(&pack.get("id")), t(&x.get("id"))));
        o.set("packId", pack.get("id"));
        o.set("packName", pack.get("name"));
        o
    }
}

/// `HT.organAsPeriod(g)` = `Object.assign({}, g, { kind: 'overlay', partOf: g.host })`.
fn organ_as_period(g: &V) -> V { let o = copy(g); o.set("kind", "overlay"); o.set("partOf", g.get("host")); V::Obj(o) }
/// `HT.cultureAsPeriod(c)` = `Object.assign({}, c, { kind: 'culture' })`.
fn culture_as_period(c: &V) -> V { let o = copy(c); o.set("kind", "culture"); V::Obj(o) }
/// `HT.dynastyAsPeriod(d)` = `Object.assign({}, d, { kind: 'dynasty', partOf: d.polities })`.
fn dynasty_as_period(d: &V) -> V { let o = copy(d); o.set("kind", "dynasty"); o.set("partOf", d.get("polities")); V::Obj(o) }

/// `HT.buildModel(packs, null, { groupBands })` — 정규화한 팩들(첫째가 기본 DLC, 나머지는 켠 차례)로 병합 모델을 짓는다.
/// 옮기지 않은 갈래에 닿으면(모델의 알림 글이 날짜 글을 `HT.cal.describe`로 적는 곳) · JS라면 던졌을 곳(객체가 아닌 값에 쓰기 — `util::fault`)이면 오류 —
/// 오류로 끝나도 지은 그래프는 풀고 돌아간다(`js::release`).
pub fn build_model(rc: &RCtx, packs: &[V], group_bands: bool) -> crate::Result<V> {
    util::take_fault(); // 앞 짓기의 잘못이 남지 않게
    let b = Build::new(rc, packs);
    for (id, name, color) in util::DEFAULT_CATEGORY_DEFS { b.add_cat(&V::Obj(o! { "id" => id, "name" => name, "color" => color })); }
    let mut patches: Vec<(V, V)> = Vec::new();
    for pack in packs {
        for tr in list(&pack.get("tracks")) { b.add_track(&tr); }
        for c in list(&pack.get("categories")) { b.add_cat(&c); }
        for p in list(&pack.get("peoples")) { b.add_people(&p); }
        for (i, e) in list(&pack.get("epochs")).iter().enumerate() {
            let o = copy(e);
            o.set("kind", "epoch");
            o.set("itemKind", "epoch");
            o.set("uid", format!("{}/{}", t(&pack.get("id")), t(&e.get("id"))));
            o.set("packId", pack.get("id"));
            o.set("packName", pack.get("name"));
            o.set("endY", if e.bool("ongoing") { V::Num(js::max(&[rc.now_t, n(&e.get("start"))])) } else { nn(e.get("end"), e.get("start")) });
            let k = (b.epochs.len() + i) % EPOCH_PALETTE.len();
            o.set("color", pastel(&or(e.get("color"), s(EPOCH_PALETTE[k]))));
            b.epochs.push(o);
        }
        let key = |x: &V| V::from(format!("{}/{}", t(&pack.get("id")), t(&x.get("id"))));
        for p in list(&pack.get("periods")) { b.period_map.set(key(&p), b.deco(&p, pack, "period", &o! { "polityKind" => kind_of(&p), "itemKind" => "period" })); }
        for g in list(&pack.get("organs")) { b.period_map.set(key(&g), b.deco(&organ_as_period(&g), pack, "period", &o! { "polityKind" => "overlay", "itemKind" => "organ" })); }
        for c in list(&pack.get("cultures")) { b.period_map.set(key(&c), b.deco(&culture_as_period(&c), pack, "period", &o! { "polityKind" => "culture", "itemKind" => "culture" })); }
        for d in list(&pack.get("dynasties")) { b.period_map.set(key(&d), b.deco(&dynasty_as_period(&d), pack, "period", &o! { "polityKind" => "dynasty", "itemKind" => "dynasty" })); }
        for e in list(&pack.get("events")) { b.event_map.set(key(&e), b.deco(&e, pack, "event", &o! { "itemKind" => "event" })); }
        for f in list(&pack.get("figures")) { b.figure_map.set(key(&f), b.deco_figure(&f, pack)); }
        for g in list(&pack.get("groups")) { b.group_map.set(key(&g), b.deco(&g, pack, "group", &o! { "itemKind" => "group" })); }
        for x in list(&pack.get("institutions")) { b.inst_map.set(key(&x), b.deco_inst(&x, pack)); }
        for patch in list(&pack.get("patches")) { patches.push((patch, pack.clone())); }
        if let V::Obj(docs) = or(pack.get("documents"), V::Obj(Obj::new())) {
            for (k, text) in docs.entries() {
                b.docs.set(V::Str(util::doc_key_absolute(&k, &pack.get("id"))), o! { "text" => text, "packId" => pack.get("id"), "packName" => pack.get("name") });
            }
        }
    }

    // 다른 DLC의 사건 · 시대를 고치는 패치
    for (patch, pack) in &patches { apply_patch(&b, patch, pack); }

    // 기관의 얹히는 정권(host)은 그리기에서 소속(partOf)으로 — 패치 · 수정으로 host가 바뀌었을 때도 맞춘다
    for p in b.period_map.values() {
        let po = ob(&p);
        if is(&p.get("itemKind"), "organ") && !p.get("host").is_nullish() { po.set("partOf", p.get("host")); }
        if is(&p.get("itemKind"), "dynasty") && !p.get("polities").is_nullish() { po.set("partOf", p.get("polities")); }
    }
    if group_bands { group_bands_into(&b); }
    parts::rest(b, rc, packs)
}

/// 패치 하나(7924 ~ 7965줄): 대상(사건 → 시대 → 인물 → 단체 → 제도)을 숨기거나 고친다.
fn apply_patch(b: &Build, patch: &V, pack: &V) {
    let target = patch.get("target");
    let maps = [(&b.event_map, 0), (&b.period_map, 1), (&b.figure_map, 2), (&b.group_map, 3), (&b.inst_map, 4)];
    let Some((map, which)) = maps.iter().find(|(m, _)| m.has(&target)).map(|(m, w)| ((*m).clone(), *w)) else { return };
    let (is_event, is_period, is_figure, is_inst) = (which == 0, which == 1, which == 2, which == 4);
    if tv(&patch.get("hide")) { map.delete(&target); return; }
    let item = map.get(&target);
    let before = Obj::new();
    let set_v = or(patch.get("set"), V::Obj(Obj::new()));
    if let V::Obj(so) = &set_v { for k in so.keys() { before.set(&k, item.get(&k)); } }
    let set = copy(&patch.get("set"));
    if !is_figure {
        if let V::Arr(alts) = set.get("alternatives") {
            let kept: Vec<V> = alts.to_vec().into_iter().filter(|a| !a.get("start").is_nullish() || !util::alt_dated(a)).map(|a| {
                let o = copy(&a);
                for k in ["birth", "birthAt", "death", "deathAt"] { o.delete(k); }
                V::Obj(o)
            }).collect();
            set.set("alternatives", arr(kept));
        }
    }
    if set.has("kind") {
        set.set("polityKind", kind_of(&V::Obj(o! { "kind" => set.get("kind") })));
        before.set("polityKind", item.get("polityKind"));
        set.delete("kind");
        before.delete("kind");
    }
    if !is_event && set.has("treaty") {
        set.delete("treaty");
        before.delete("treaty");
        if set.is_empty() { return; }
    }
    let mut dropped = false;
    for k in ["law", "election", "theme"] {
        if !set.has(k) || is_event || (k == "theme" && is_inst) { continue; }
        set.delete(k);
        before.delete(k);
        dropped = true;
    }
    if dropped && set.is_empty() { return; }
    if is_inst { if let V::Arr(th) = set.get("theme") { set.set("theme", or(th.get(0), item.get("theme"))); } }
    let merged = copy(&item);
    assign_obj(&merged, &set);
    merged.set("id", item.get("id"));
    merged.set("uid", item.get("uid"));
    merged.set("kind", item.get("kind"));
    let mut by = list(&or(item.get("patchedBy"), arr(Vec::new())));
    by.push(V::Obj(o! { "id" => pack.get("id"), "name" => pack.get("name"), "note" => or(patch.get("note"), s("")), "before" => before }));
    merged.set("patchedBy", arr(by));
    if !is_figure && (set.has("start") || set.has("end")) {
        let mv = V::Obj(merged.clone());
        let spanned = is_period || !merged.get("end").is_nullish() || matches!(merged.get("ongoing"), V::Bool(true));
        let str_at = |k: &str| match merged.get(k) { V::Str(x) if !x.is_empty() => Some(x), _ => None };
        let num = |k: &str| merged.get(k).as_num();
        let spans = read::cells::Spans { start: num("start"), start_at: str_at("startAt"), end: num("end"), end_at: str_at("endAt"),
            start_range: tv(&mv.get("startRange")), end_range: tv(&mv.get("endRange")) };
        assign_obj(&merged, &read::cells::century_ranges(b.rc, &spans, spanned));
    }
    let done = if is_figure || is_inst { merged } else { b.derive(merged) };
    map.set(target, done);
}

/// 단체의 띠(8001 ~ 8040줄 · `opts.groupBands`): 단체를 기관과 같은 틀로 periods에도 올린다 — 있던 나라 줄마다 한 토막(그 나라에 접혀 듦).
fn group_bands_into(b: &Build) {
    for g in b.group_map.values() {
        if !tv(&g.get("track")) || g.get("start").is_nullish() || is(&g.get("type"), "coalition") { continue; }
        let rows = read::groups::read_polity_rows(b.rc, &g.get("within"), false, &mut |_| {}, "");
        if rows.is_empty() { continue; }
        let regime = is(&g.get("type"), "regime");
        let base = o! { "name" => g.get("name"), "track" => g.get("track"), "color" => g.get("color"), "description" => g.get("description"), "wiki" => g.get("wiki") };
        for k in ["names", "historicity"] { if !g.get(k).is_nullish() { base.set(k, g.get(k)); } }
        let put = |id: &str, extra: &Obj, part_of: V| {
            let uid = format!("{}~{id}", t(&g.get("uid")));
            let o = copy(&V::Obj(base.clone()));
            assign_obj(&o, extra);
            o.set("id", format!("{}~{id}", t(&g.get("id"))));
            o.set("partOf", part_of);
            o.set("kind", "period");
            o.set("itemKind", "period");
            o.set("polityKind", if regime { "warlord" } else { "movement" });
            o.set("uid", uid.clone());
            o.set("packId", g.get("packId"));
            o.set("packName", g.get("packName"));
            o.set("groupUid", g.get("uid"));
            b.period_map.set(V::from(uid), b.derive(o));
        };
        let span = Obj::new();
        for k in ["start", "end", "ongoing", "startUnknown", "endUnknown", "startRange", "endRange", "startAt", "endAt"] { if !g.get(k).is_nullish() { span.set(k, g.get(k)); } }
        let dated = rows.len() > 1 || rows.iter().any(|r| !r.get("start").is_nullish() || !r.get("end").is_nullish());
        let kind_name = util::group_type_name(&g.get("type"));
        let first = kind_name.as_str().split('·').next().unwrap_or("").to_string();
        base.set("groupKind", first);
        if !dated {
            let all = b.group_map.values();
            let of_group = |r: &V| -> Option<V> {
                all.iter().find(|x| !eq(x, &g) && (eq(&x.get("uid"), r) || (eq(&x.get("packId"), &g.get("packId")) && (eq(&x.get("id"), r) || eq(&x.get("name"), r))))).cloned()
                    .or_else(|| all.iter().find(|x| !eq(x, &g) && eq(&x.get("name"), r)).cloned())
            };
            let from = if let V::Arr(a) = g.get("from") { a.to_vec() } else { Vec::new() };
            let succ: Vec<V> = from.iter().filter_map(|f| of_group(&f.get("group"))).map(|src| V::Obj(o! { "from" => format!("{}~band", t(&src.get("uid"))), "type" => "direct" })).collect();
            base.set("succeeds", arr(succ));
        }
        for (i, r) in rows.iter().enumerate() {
            let seg = if dated {
                let o = copy(&V::Obj(span.clone()));
                if !r.get("start").is_nullish() { assign_obj(&o, &o! { "start" => r.get("start"), "startUnknown" => V::Undef, "startRange" => V::Undef, "startAt" => V::Undef }); }
                if !r.get("end").is_nullish() { assign_obj(&o, &o! { "end" => r.get("end"), "ongoing" => V::Undef, "endUnknown" => V::Undef, "endRange" => V::Undef, "endAt" => V::Undef }); }
                o
            } else { span.clone() };
            if !seg.get("end").is_nullish() && lt(&seg.get("end"), &seg.get("start")) { continue; }
            let part_of = arr(vec![V::Obj(o! { "polity" => r.get("polity"), "track" => r.get("track"), "nest" => true })]);
            put(&if dated { format!("seg{i}") } else { "band".to_string() }, &seg, part_of);
        }
    }
}


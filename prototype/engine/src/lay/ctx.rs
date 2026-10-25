//! 배치 문맥 — `prototype/scripts/export/base.mjs`의 `contextOf`(정규화 → 모델 → 연표 상태 `tl`의 준비 → 줄 배정)를 줄 그대로 옮긴다(한 벌 P3 과제 6 — 이음매 ② 앞).
//!
//! 옮긴 원본:
//! - `prototype/scripts/export/base.mjs` 136 ~ 221줄 `contextOf` — SHA-256 앞 12자 `13ed7b3eef3e`(저장소의 LF 바이트) → [`context_of`]
//! - `js/timeline.js` 602 · 613 ~ 620줄 `depRel` · `depLook` · 646 ~ 692줄 `depProxies` · 9088 ~ 9092줄 `_setScopes` — SHA-256 앞 12자 `8a3b02f5bf7f` → [`dep_look`] · [`dep_proxies`] · [`set_scopes`]
//!
//! 연표 상태 `tl`은 JS의 `Object.create(HT.Timeline.prototype)` + `Object.assign`의 열쇠 그대로(화면 흉내 `axisEl`만 뺌 — 배치 셈이 쓰지 않음). 생성자를 건너뛰고 배치가 읽는 상태만 채운다.
//! 줄 배정(`_layoutTrack` — 과제 7)은 `lay_tracks`가 참일 때 트랙마다 [`crate::lay::track::layout_track`]으로(이음매 ② 뒤 — [`laid`]).
use crate::lay::js::{self, Arr, Map, Obj, Set, V};
use crate::lay::model::util::{arr, copy, is, list, lt, n, nn, ob, or, relation_info, relation_of_kind, s, sub, tv};
use crate::lay::model::{self, o};
use crate::lay::read;
use crate::lay::{Opts, PackIn};

/// 배치 문맥(`contextOf`의 답) — 모듈 · 줄 배정이 읽는다.
/// - `packs`: 정규화한 팩(첫째가 기본 DLC) · `raws`: 원본(정규화가 고칠 수 있는 그대로 — `raw`는 그 첫째)
/// - `model`: `HT.buildModel(packs, null, { groupBands: true })` · `tl`: 연표 상태
/// - `pack_index`: 팩 id → 순번 · `track_pack`: 트랙 id → 그 트랙을 처음 말한 팩의 순번(`packOf`는 [`Ctx::pack_of`])
/// - `now_year` · `now_t`: `HT.CURRENT_YEAR` · `HT.NOW_T` · `tz_min`: 시간대(분) · `read`: 읽기 문맥(달력 표 — 줄 배정 · 모듈이 날짜를 다시 읽는다)
/// - `track_index`: 트랙 id → `tl.tracks`의 순번(`contextOf`의 `trackIndex`)
/// - `shared` · `notes`: 모듈끼리 나눠 쓰는 값 · 모듈이 남기는 집계(`runModules`가 빈 객체로 시작 — `ctx.shared` · `ctx.notes`). 과제 8-틀: `shared`의 값은 모두
///   평범한 값(글 → 수의 Map · 글 → Set · 글 → 배열)이라 정답지(`pre-<모듈>.shared.json` — seam 규칙)에서 심을 수 있다(`lay::export::shared_seed`).
pub struct Ctx {
    pub packs: Vec<V>,
    pub raws: Vec<V>,
    pub model: V,
    pub tl: V,
    pub pack_index: Map,
    pub track_pack: Map,
    pub track_index: Map,
    pub now_year: f64,
    pub now_t: f64,
    pub tz_min: i32,
    pub read: read::Ctx,
    pub shared: Obj,
    pub notes: Obj,
}

impl Ctx {
    /// `packOf(x)` — 항목이 어느 DLC에서 왔는가(순번 · 기본 DLC = 0): packId → uid의 앞머리(`<DLC id>/…`) → 0.
    pub fn pack_of(&self, x: &V) -> f64 {
        if !tv(x) { return 0.0; }
        let pid = x.get("packId");
        if tv(&pid) && self.pack_index.has(&pid) { return n(&self.pack_index.get(&pid)); }
        if let V::Str(uid) = x.get("uid") {
            let text = uid.as_str();
            if let Some((head, _)) = text.split_once('/') {
                let h = s(head);
                if self.pack_index.has(&h) { return n(&self.pack_index.get(&h)); }
            }
        }
        0.0
    }
    /// 다 쓴 문맥을 푼다(버리는 것과 같다 — [`Drop`]이 푼다).
    pub fn release(self) {}
}

/// 문맥을 버리면 모델 · 연표 상태의 고리(`Rc<RefCell>`)를 반복으로 비운다(얹힌 몫 1 · `js::release` — 고침 1회차: 오류 길 · 잊고 버린 길에서도).
impl Drop for Ctx {
    fn drop(&mut self) {
        js::release(&self.tl);
        js::release(&self.model);
        for v in self.packs.iter().chain(self.raws.iter()) { js::release(v); }
        js::release(&V::Map(self.pack_index.clone()));
        js::release(&V::Map(self.track_pack.clone()));
        js::release(&V::Map(self.track_index.clone()));
        js::release(&V::Obj(self.shared.clone()));
        js::release(&V::Obj(self.notes.clone()));
    }
}

/// 오류로 일찍 돌아갈 때 쥔 값들을 푸는 덮개(`context_of`가 문맥을 다 짓기 전).
struct Hold(Vec<V>);
impl Drop for Hold {
    fn drop(&mut self) { for v in &self.0 { js::release(v); } }
}

/// `depRel(h)` · `depLook(p, h)` — 소속 한 구간의 모습: 적힌 관계(없으면 종류에서 빌림)의 자율성으로 매달림(out) · 품음(in)과 탭 모양.
/// → `{ rel, look, side }`.
pub fn dep_look(p: &V, h: &V) -> Obj {
    let rel = or(or(h.get("relation"), relation_of_kind(&p.get("polityKind"))), s(""));
    let info = if tv(&rel) { relation_info(&rel) } else { None };
    let (look, side) = match info {
        None | Some((_, true)) | Some((None, _)) => ("plain", "out"),
        Some((Some(autonomy), false)) => {
            if is(&rel, "nominal") { ("nominal", "out") }
            else if is(&rel, "occupied") { ("occupied", "in") }
            else if autonomy >= 3.0 { ("loose", "out") }
            else if autonomy == 2.0 { ("firm", "out") }
            else if autonomy == 1.0 { ("held", "in") }
            else { ("owned", "in") }
        }
    };
    o! { "rel" => rel, "look" => look, "side" => side }
}

/// `depProxies(periods)` — 상국 띠마다 품을 속국 이름표: Map(상국 uid → { items: [{ p, segs: [{ h, a, b, rel, look, side }], out, inn, outLane, inLane }], outLanes, inLanes }).
/// 상국과 속국이 모두 그려질 때만(트랙이 달라도) · 접힌 소속(singleHost)은 예속이 아닌 소속이면 빼고 · 단체의 띠는 달지 않는다. 줄은 상국마다 밖 · 안을 따로 나눈다.
pub fn dep_proxies(periods: &[V]) -> Map {
    let present = Set::new();
    for p in periods { present.add(p.get("uid")); }
    let by_host = Map::new();
    let drawn = |q: &V| tv(q) && !is(&q.get("polityKind"), "overlay") && !is(&q.get("polityKind"), "dynasty") && !is(&q.get("polityKind"), "culture");
    for p in periods {
        let hosts = p.get("hosts");
        if !tv(&hosts) || !tv(&hosts.get("length")) || !drawn(p) { continue; }
        if tv(&p.get("groupUid")) { continue; }
        for h in list(&hosts) {
            let host = h.get("host");
            if !tv(&host) || !present.has(&host.get("uid")) || !drawn(&host) { continue; }
            let a = nn(h.get("start"), p.get("start"));
            let b = nn(h.get("end"), p.get("endY"));
            if !lt(&a, &b) { continue; }
            let look = dep_look(p, &h);
            if p.bool("singleHost") && is(&look.get("look"), "plain") { continue; }
            let huid = host.get("uid");
            if !by_host.has(&huid) { by_host.set(huid.clone(), Map::new()); }
            let V::Map(m) = by_host.get(&huid) else { continue };
            if !m.has(&p.get("uid")) { m.set(p.get("uid"), o! { "p" => p.clone(), "segs" => arr(Vec::new()) }); }
            let seg = o! { "h" => h.clone(), "a" => a, "b" => b };
            for (k, x) in look.entries() { seg.set(&k, x); }
            if let V::Arr(segs) = m.get(&p.get("uid")).get("segs") { segs.push(seg); }
        }
    }
    let out = Map::new();
    for (uid, m) in by_host.entries() {
        let V::Map(m) = m else { continue };
        let items = m.values();
        for it in &items {
            if let V::Arr(segs) = it.get("segs") { segs.sort_js(|x, y| sub(&x.get("a"), &y.get("a"))); }
            for (key, side) in [("out", "out"), ("inn", "in")] {
                let ss: Vec<V> = list(&it.get("segs")).into_iter().filter(|sg| is(&sg.get("side"), side)).collect();
                let v = if ss.is_empty() { V::Null } else {
                    let lo = js::min(&ss.iter().map(|sg| n(&sg.get("a"))).collect::<Vec<_>>());
                    let hi = js::max(&ss.iter().map(|sg| n(&sg.get("b"))).collect::<Vec<_>>());
                    arr(vec![V::Num(lo), V::Num(hi)])
                };
                ob(it).set(key, v);
            }
        }
        let lanes = |key: &str, lane_key: &str| -> f64 {
            let mut ends: Vec<f64> = Vec::new();
            let moved = |x: &V| -> f64 { if tv(&x.get("out")) && tv(&x.get("inn")) { 0.0 } else { 1.0 } };
            let mut pick: Vec<V> = items.iter().filter(|x| tv(&x.get(key))).cloned().collect();
            js::sort(&mut pick, |x, y| {
                let d = moved(x) - moved(y);
                if d != 0.0 { return d; }
                let d = n(&x.get(key).get(&0.0)) - n(&y.get(key).get(&0.0));
                if d != 0.0 && !d.is_nan() { return d; }
                n(&y.get(key).get(&1.0)) - n(&x.get(key).get(&1.0))
            });
            for it in &pick {
                let r = it.get(key);
                let k = match ends.iter().position(|e| *e <= n(&r.get(&0.0))) { Some(k) => k, None => { ends.push(0.0); ends.len() - 1 } };
                ends[k] = n(&r.get(&1.0));
                ob(it).set(lane_key, k as f64);
            }
            ends.len() as f64
        };
        let out_lanes = lanes("out", "outLane");
        let in_lanes = lanes("inn", "inLane");
        out.set(uid, o! { "items" => arr(items.clone()), "outLanes" => out_lanes, "inLanes" => in_lanes });
    }
    out
}

/// `tl._setScopes(list)` — 대범위 목록과, 본국별 할거 구간(본국이 끝나기 전의 대범위 — `_hosted`: 본국 uid → 대범위들).
pub fn set_scopes(tl: &Obj, scopes: &V) {
    let items = list(&or(scopes.clone(), arr(Vec::new())));
    tl.set("scopes", if tv(scopes) { scopes.clone() } else { arr(Vec::new()) });
    let hosted = Map::new();
    for sc in &items {
        let host = sc.get("host");
        if tv(&host) && !tv(&sc.get("afterHost")) {
            let mut cur = list(&hosted.get(&host.get("uid")));
            cur.push(sc.clone());
            hosted.set(host.get("uid"), arr(cur));
        }
    }
    tl.set("_hosted", hosted);
}

/// `contextOf(HT, raws, labels)` — 원본 DLC 목록(첫째가 기본, 나머지는 켠 차례)을 정규화해 모델을 짓고, 연표 상태를 준비한다(`lay_tracks`면 줄 배정까지 — 과제 7).
/// 읽지 못한 DLC · 같은 id의 DLC 둘 · 보조 달력 표 없음/범위 밖 · 옮기지 않은 갈래는 오류.
pub fn context_of(packs_in: &[PackIn], opts: &Opts, lay_tracks: bool) -> crate::Result<Ctx> {
    let mut ctx = prepare(packs_in, opts)?;
    if lay_tracks { crate::lay::track::layout_all(&mut ctx)?; }
    set_depth(&ctx);
    Ok(ctx)
}

/// 준비만 한 문맥(`context_of(…, false)`)에 줄 배정을 마친다 — 그 뒤의 문맥은 `context_of(…, true)`와 같다(과제 16b: 닿는 트랙을 셈하며 준비한 문맥을
/// 내보내기가 다시 쓴다 — `lay::export`).
pub fn lay_out(ctx: &mut Ctx) -> crate::Result<()> {
    crate::lay::track::layout_all(ctx)?;
    set_depth(ctx);
    Ok(())
}

/// `tl.depth` — 트랙들의 깊이(줄 배정 전이면 1) 가운데 가장 큰 것(1 이상).
fn set_depth(ctx: &Ctx) {
    let tracks = list(&ctx.tl.get("tracks"));
    let depth = js::max(&std::iter::once(1.0).chain(tracks.iter().map(|tr| n(&or(tr.get("depth"), V::Num(1.0))))).collect::<Vec<_>>());
    ob(&ctx.tl).set("depth", depth);
}

/// [`context_of`]의 준비 몫(줄 배정 · 연표 깊이 전).
fn prepare(packs_in: &[PackIn], opts: &Opts) -> crate::Result<Ctx> {
    let rc = read::Ctx::new(opts)?;
    let mut raws = Vec::new();
    let mut packs = Vec::new();
    let mut hold = Hold(Vec::new()); // 오류로 돌아가면 여기 든 것을 푼다
    for (i, pin) in packs_in.iter().enumerate() {
        let mut notes = Vec::new();
        let raw = crate::lay::pack::raw_of(&rc, pin, &mut notes)?;
        let norm = read::normalize_pack(&rc, raw.clone());
        hold.0.push(raw.clone());
        if let Some(p) = &norm.pack { hold.0.push(p.clone()); }
        if let Some(name) = rc.cal.missed_of() { return Err(format!("{}: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다", pin.name).into()); }
        if let Some(name) = rc.cal.absent_of() { return Err(format!("{}: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다", pin.name).into()); }
        let Some(pack) = norm.pack else {
            let who = if i == 0 { "기본".to_string() } else { pin.name.clone() };
            return Err(format!("DLC를 읽을 수 없습니다({who}): {}", norm.errors.iter().map(|e| e.msg.as_str()).collect::<Vec<_>>().join(" · ")).into());
        };
        raws.push(raw);
        packs.push(pack);
    }
    let ids = Set::new();
    for p in &packs {
        if ids.has(&p.get("id")) { return Err(format!("같은 id의 DLC가 둘입니다: {}", js::to_str(&p.get("id"))).into()); }
        ids.add(p.get("id"));
    }
    let model = model::build_model(&rc, &packs, true)?;
    hold.0.push(model.clone());
    // 모델도 날짜 글을 다시 읽는다(칸의 경계 · 날짜 글 맞춤) — 보조 달력 표가 모자라면 정규화와 같은 거절
    if let Some(name) = rc.cal.missed_of() { return Err(format!("모델: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다").into()); }
    if let Some(name) = rc.cal.absent_of() { return Err(format!("모델: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다").into()); }
    // 항목이 어느 DLC에서 왔는가: packId → uid의 앞머리 → 트랙은 그 트랙을 처음 말한 DLC
    let pack_index = Map::new();
    for (i, p) in packs.iter().enumerate() { pack_index.set(p.get("id"), i as f64); }
    let track_pack = Map::new();
    for (i, p) in packs.iter().enumerate() {
        for tr in list(&p.get("tracks")) { if tv(&tr) && tv(&tr.get("id")) && !track_pack.has(&tr.get("id")) { track_pack.set(tr.get("id"), i as f64); } }
    }

    // 생성자를 건너뛰고 배치가 읽는 상태만 기본값으로(js/timeline.js의 constructor와 같은 값)
    let tl = o! {
        "show" => o! { "leaders" => true, "cabinets" => true, "eras" => true, "capitals" => true, "ganji" => true, "succession" => true, "partOf" => true, "epochs" => true, "groups" => true },
        "folded" => Set::new(), "foldedPeoples" => Set::new(), "foldedEras" => Set::new(), "expandedHosts" => Set::new(), "expandedGroups" => Set::new(), "foldedHangs" => Set::new(),
        "scopesOn" => Obj::new(), "axisOpen" => { let st = Set::new(); st.add(s("eras")); st.add(s("capitals")); st }, "openCapSec" => Set::new(), "altCal" => "", "_calOpen" => false,
        "opts" => Obj::new(), "density" => 0.0, "_bird" => V::Null, "_lod" => Map::new(), "gutter" => 196.0, "depth" => 1.0, "hiLayout" => V::Null, "highlight" => V::Null,
        "selected" => V::Null, "packRows" => true,
    };
    // setData의 준비 구간
    tl.set("_data", o! {
        "tracks" => model.get("tracks"), "periods" => model.get("periods"), "events" => model.get("events"), "epochs" => model.get("epochs"),
        "categories" => model.get("categories"), "scopes" => model.get("scopes"), "figures" => or(model.get("figures"), arr(Vec::new())),
    });
    set_scopes(&tl, &model.get("scopes"));
    // 기본 배치는 모든 그릇을 풀어 둔다(자료의 default도)
    let scopes_on = Obj::new();
    for sc in list(&or(model.get("scopes"), arr(Vec::new()))) { scopes_on.set(&js::to_str(&sc.get("uid")), false); }
    tl.set("scopesOn", scopes_on);
    let cats = Map::new();
    let cat_list = { let c = list(&model.get("categories")); if !c.is_empty() { c } else {
        crate::lay::model::util::DEFAULT_CATEGORY_DEFS.iter().map(|(id, name, color)| V::Obj(o! { "id" => *id, "name" => *name, "color" => *color })).collect()
    } };
    for (i, c) in cat_list.iter().enumerate() { cats.set(c.get("id"), o! { "name" => c.get("name"), "color" => c.get("color"), "i" => i as f64 }); }
    for e in list(&model.get("events")) {
        let id = or(e.get("category"), s("etc"));
        if !cats.has(&id) { cats.set(id.clone(), o! { "name" => id.clone(), "color" => or(e.get("color"), s("#a4b1b7")), "i" => 1000.0 + cats.len() as f64 }); }
    }
    tl.set("_cats", cats);
    tl.set("epochs", or(model.get("epochs"), arr(Vec::new())));
    let by_id = Map::new();
    let tracks: Vec<V> = list(&model.get("tracks")).iter().map(|tr| {
        let o = copy(tr);
        o.set("periods", arr(Vec::new()));
        o.set("events", arr(Vec::new()));
        o.set("figures", arr(Vec::new()));
        by_id.set(tr.get("id"), o.clone());
        V::Obj(o)
    }).collect();
    tl.set("tracks", arr(tracks.clone()));
    let city_uses = Map::new();
    let periods = list(&model.get("periods"));
    for p in &periods {
        for c in list(&p.get("capitals")) {
            let city = c.get("city");
            if !city_uses.has(&city) { city_uses.set(city.clone(), Arr::default()); }
            if let V::Arr(l) = city_uses.get(&city) { l.push(o! { "p" => p.clone(), "c" => c.clone() }); }
        }
    }
    tl.set("_cityUses", city_uses);
    let dyn_uids = Set::new();
    for p in &periods {
        if is(&p.get("polityKind"), "dynasty") { dyn_uids.add(p.get("uid")); }
        else if by_id.has(&p.get("track")) { if let V::Arr(l) = by_id.get(&p.get("track")).get("periods") { l.push(p.clone()); } }
    }
    tl.set("_dynUids", dyn_uids);
    // 인물의 활동 막대: 섬긴 정권마다 하나, 그 정권의 트랙에
    for f in list(&tl.get("_data").get("figures")) {
        for (i, sv) in list(&f.get("services")).iter().enumerate() {
            let tr = if tv(&sv.get("shown")) && tv(&sv.get("polity")) { by_id.get(&sv.get("polity").get("track")) } else { V::Null };
            if tv(&tr) {
                if let V::Arr(l) = tr.get("figures") { l.push(o! { "f" => f.clone(), "s" => sv.clone(), "i" => i as f64, "row" => V::Null, "lvl" => -1.0, "band" => V::Null }); }
            }
        }
    }
    tl.set("_proxies", dep_proxies(&periods));
    for e in list(&model.get("events")) {
        let pl = e.get("placements");
        let places = if tv(&pl) && tv(&pl.get("length")) { list(&pl) } else { vec![V::Obj(o! { "track" => e.get("track"), "polityUid" => e.get("polityUid") })] };
        for (i, place) in places.iter().enumerate() {
            let tr = by_id.get(&place.get("track"));
            if !tv(&tr) { continue; }
            let o = copy(&e);
            o.set("_place", place.clone());
            o.set("_sec", i > 0);
            o.set("_pi", i as f64);
            if let V::Arr(l) = tr.get("events") { l.push(o); }
        }
    }
    hold.0.clear(); // 이제 문맥이 쥔다(버리면 Drop이 푼다)
    let track_index = Map::new();
    for (i, tr) in tracks.iter().enumerate() { track_index.set(tr.get("id"), i as f64); }
    let ctx = Ctx {
        raws, packs, model, tl: V::Obj(tl.clone()), pack_index, track_pack, track_index,
        now_year: rc.current_year, now_t: rc.now_t, tz_min: opts.tz_min, read: rc, shared: Obj::new(), notes: Obj::new(),
    };
    // 준비 구간도 JS라면 던졌을 곳(객체가 아닌 값에 칸 쓰기)을 남기면 오류(모델은 build_model이 이미 봄)
    if let Some(msg) = crate::lay::model::util::take_fault() { return Err(format!("연표 상태를 준비하지 못했습니다 — {msg}(JS라면 TypeError)").into()); }
    // 줄 배정(과제 7): 트랙마다 _layoutTrack — 잘못 · 보조 달력 표 거절은 layout_all이 본다(context_of · lay_out)
    Ok(ctx)
}

/// 문맥의 이음매 ② 덤프(값) — `prep.json` · `rows.json`과 같은 뿌리(다시 배치한 문맥을 견줄 때 — `lay_rows::relayout_is_idempotent`).
pub fn dump(ctx: &Ctx) -> serde_json::Value {
    let root = seam_root(ctx); // 뿌리만 새 객체 — 그래프는 문맥이 쥐므로 풀지 않는다(버리면 뿌리만 사라짐)
    js::seam(&root)
}
/// [`dump`]의 덤프 글.
pub fn dump_text(ctx: &Ctx) -> String { js::seam_text(&seam_root(ctx)) }

/// 이음매 ② 앞의 덤프 뿌리 — `prep.json`의 `{ tracks, depth, cats, proxies, cityUses, scopes, model }`(`scopes`는 `tl._scopes` — 연표 상태에 없어 빠진다).
fn seam_root(ctx: &Ctx) -> V {
    let tl = &ctx.tl;
    V::Obj(o! {
        "tracks" => tl.get("tracks"), "depth" => tl.get("depth"), "cats" => tl.get("_cats"), "proxies" => tl.get("_proxies"),
        "cityUses" => tl.get("_cityUses"), "scopes" => tl.get("_scopes"), "model" => ctx.model.clone(),
    })
}

/// 이음매 ② 앞(줄 배정 전 — `prep.json`과 같은 덤프 · `oracle/seam.mjs`의 규칙): 정규화 → 모델 → 연표 상태의 준비. 끝나면 문맥을 푼다(`js::release`).
pub fn prepared(packs: &[PackIn], opts: &Opts) -> crate::Result<serde_json::Value> {
    let ctx = context_of(packs, opts, false)?;
    let root = seam_root(&ctx);
    let out = js::seam(&root);
    js::release(&root);
    ctx.release();
    Ok(out)
}

/// [`prepared`]의 덤프 글(정답지 글과 바이트까지 견줄 때 — 머리 `$oracle`이 없는 본문).
pub fn prepared_text(packs: &[PackIn], opts: &Opts) -> crate::Result<String> {
    let ctx = context_of(packs, opts, false)?;
    let root = seam_root(&ctx);
    let out = js::seam_text(&root);
    js::release(&root);
    ctx.release();
    Ok(out)
}

/// 이음매 ② 뒤(줄 배정 뒤 — `rows.json`과 같은 덤프 · 과제 7): 정규화 → 모델 → 연표 상태의 준비 → 트랙마다 `_layoutTrack` → 연표 깊이. 끝나면 문맥을 푼다.
pub fn laid(packs: &[PackIn], opts: &Opts) -> crate::Result<serde_json::Value> {
    let ctx = context_of(packs, opts, true)?;
    let root = seam_root(&ctx);
    let out = js::seam(&root);
    js::release(&root);
    ctx.release();
    Ok(out)
}

/// [`laid`]의 덤프 글(정답지 `rows.json` 본문과 바이트까지 견줄 때).
pub fn laid_text(packs: &[PackIn], opts: &Opts) -> crate::Result<String> {
    let ctx = context_of(packs, opts, true)?;
    let root = seam_root(&ctx);
    let out = js::seam_text(&root);
    js::release(&root);
    ctx.release();
    Ok(out)
}

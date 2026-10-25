//! 내보내기 모듈 `entities`(15/20) — `prototype/scripts/export/entities.mjs`(1 ~ 1508줄 · SHA-256 앞 12자 `02d5c3a469ca` — 2026-10-24 리메이크 3단계 과제 5: 1322 ~ 1337줄 인물의 칭호 묶음 `x_titles` → `titles_of`)를 줄 그대로 옮긴다(한 벌 P3 과제 13a ~ 13d).
//! 상세 창이 읽는 항목 기록(계약 1절의 entities · 4절 · 6-9절): 모델의 정권 · 사건 · 인물 · 시대 구분 · 대범위 · 기관 · 문화 · 왕조 · 가문 · 단체 · 제도 · 지명 · 성씨 · 주제 사전 ·
//! 모아 보기 판 · 지도 · 글꼴 · 계보 뼈대를 `{ uid, kind, json, pack }`으로. `json` 글은 [`js::stringify`](JS 열쇠 차례 — 바이트까지 Node와 같게 · 판정 R24-c).
//!
//! JS 절 경계로 나눈 파일(1,500줄 규칙):
//! - 이 파일: 1 ~ 98줄(머리 · `plain` · `M` · `spanOf` · `some` · `textOf` · `brief`) · 1313 ~ 1492줄(`contribute` — 자료집 귀속 · 기록 싣기 · 끝의 점검)
//! - `entities/cross.rs`: 100 ~ 442줄 `crossRefs`(띠 · 사건 · 인물 · 시대 구분 · 대범위 · 가문의 미리 푼 값)
//! - `entities/format3.rs`: 444 ~ 949줄 `format3Refs`(형식 3의 미리 푼 값 — 이름 줄 · 사람 고리 · 자리 이음 · 머리 칩 · 지명 · 단체 · 제도 · 판 · 지도)
//! - `entities/window.rs`: 951 ~ 1199줄 `groupWindowRefs`(단체 계보 창 · 법의 내력 · 의석 막대)
//! - `entities/find.rs`: 1201 ~ 1311줄 `findOf` · `spanOfMinutes` · `dropBytes`
//! - 웹 함수: `entities/web.rs`(날짜 글 · 낱말 · 칸 · 이름 목록 · 글자 범위) · `entities/people.rs`(사람 자리 · 자리 이음 · 계보 뼈대 · 머리 칩 · 가문)
//! - 가져오는 것: `entities/kin.rs`(`kin.mjs` 전부) · `entities/group_tree.rs`(`js/group-tree.js`의 배치 셈 `HT.groupTreeLayout`) — 판정 R24로 공통 파일에 mod 줄을 더하지 않게 제 모듈 아래
//!
//! 읽는 out: `entities`(docs가 실은 `doc:` 기록의 `json.empty` — 머리 칩의 문서 고리). 쓰는 shared 없음. 모델 · `tl`을 고치지 않는다(계보 뼈대의 기억은 이 모듈 안).
//! 다 쓴 값은 풀지(`js::release`) 않는다 — 기록 · 미리 푼 값은 고리 없는 나무이고, 모델 객체를 담은 그릇을 풀면 뒤 모듈이 쓸 모델이 비기 때문.
use crate::lay::ctx::Ctx;
use crate::lay::export::jv;
use crate::lay::js::{self, Map, Obj, Set, Str, V};
use crate::lay::model::util::{eq, item_kind_of, list, n, or, s, tv};
use serde_json::{json, Value};

mod cross;
mod find;
mod format3;
pub mod group_tree;
pub mod kin;
pub mod people;
pub mod web;
mod window;

use web::{format_date, format_range, format_t, format_when, W};

/// 옮겼는가 — `lay::MODULES`가 읽는다(13d — 13a ~ 13c는 `tests/lay_m_entities.rs`의 갈래 거르개 검사로 덩이마다 견줌).
pub const PORTED: bool = true;

/// 더 깊이 파고들지 않는다(자료가 깊어도 상세 창이 읽는 만큼은 이 안에 든다).
const DEPTH: usize = 14;
/// 가문 창 구성원 목록에 싣는 띠 인물 수(넘으면 x_memberCount — 나머지는 세계표에서).
const MEMBER_FIGURES: usize = 200;

/// `isPersonNode(v)` — 사람 자리(모델의 personIndex 노드)인가: uid가 없고 부모 · 자식 · 칸으로 서로를 가리킨다.
fn is_person_node(v: &V) -> bool {
    matches!(v.get("key"), V::Str(_)) && matches!(v.get("cells"), V::Arr(_)) && matches!(v.get("parents"), V::Arr(_)) && matches!(v.get("children"), V::Arr(_))
}

/// `plain(root, refs)` — 모델 항목 하나를 상세 창이 읽을 수 있는 꼴로. 뿌리만 통째로 풀고, 안쪽의 다른 항목(uid가 있는 것)은 `{ $ref, name }`으로 남긴다.
/// refs를 주면 만든 $ref의 uid를 모은다(끝의 점검). '_'로 시작하는 배치용 값 · 함수(V에는 없음) · Map · Set · 순환은 뺀다.
pub fn plain(root: &V, refs: Option<&Set>) -> V {
    fn walk(v: &V, depth: usize, at_root: bool, stack: &Set, refs: Option<&Set>) -> V {
        match v {
            V::Undef | V::Null => V::Null,
            V::Num(x) => if x.is_finite() { v.clone() } else { V::Null },
            V::Str(_) | V::Bool(_) => v.clone(),
            V::Arr(a) => if depth >= DEPTH { web::va(Vec::new()) } else { web::va(a.to_vec().iter().map(|x| walk(x, depth + 1, false, stack, refs)).collect()) },
            V::Map(_) | V::Set(_) => V::Null,
            V::Obj(o) => {
                if !at_root {
                    if let V::Str(u) = v.get("uid") {
                        if !u.is_empty() {
                            if let Some(r) = refs { r.add(V::Str(u.clone())); }
                            let out = Obj::new();
                            out.set("$ref", u);
                            out.set("name", or(or(v.get("name"), v.get("title")), s("")));
                            return V::Obj(out);
                        }
                    }
                    if is_person_node(v) { let out = Obj::new(); out.set("name", or(v.get("name"), s(""))); return V::Obj(out); } // 사람 자리 — 풀어 둔 값은 x_people · x_persons · x_person에
                }
                if stack.has(v) || depth >= DEPTH { return V::Null; } // 순환 · 너무 깊은 곳
                stack.add(v.clone());
                let out = Obj::new();
                for (k, val) in o.entries() {
                    if k.as_str().starts_with('_') { continue; } // 배치용 값(_row · _place · _dep …)은 자료가 아니다
                    if val.is_undef() { continue; }
                    out.set(&k, walk(&val, depth + 1, false, stack, refs));
                }
                stack.delete(v);
                V::Obj(out)
            }
        }
    }
    walk(root, 0, true, &Set::new(), refs)
}

/// `M(t)` — 해 좌표 → 정수 분(빈 값 · 수가 아니면 null · Date 범위 밖이면 NaN — JSON에서 null).
pub fn mm(t: &V) -> V {
    match t { V::Num(x) if x.is_finite() => V::Num(js::minute(*x).map_or(f64::NAN, |m| m as f64)), _ => V::Null }
}
/// `spanOf(a, b)` — 구간 [a, b] → [분, 분](뒤집히면 앞쪽으로 맞춤). 시작이 없으면 null.
pub fn span_of(a: &V, b: &V) -> V {
    let lo = mm(a);
    if lo.is_null() { return V::Null; }
    let hi = mm(b);
    let hv = if hi.is_null() { lo.clone() } else { V::Num(js::max(&[n(&lo), n(&hi)])) };
    web::va(vec![lo, hv])
}
/// `some(v)` — 빈 것(없음 · 빈 배열 · 빈 객체)은 null.
pub fn some(v: V) -> V {
    match &v {
        V::Undef | V::Null => V::Null,
        V::Arr(a) if a.is_empty() => V::Null,
        V::Obj(o) if o.is_empty() => V::Null,
        V::Map(_) | V::Set(_) => V::Null, // Object.keys(Map) = []
        _ => v,
    }
}

/// `textOf(HT)` — 지금 연표의 날짜 글(js/viewer.js 40 ~ 74줄)을 그대로.
pub struct T<'a> { pub w: &'a W<'a> }
impl T<'_> {
    /// `whenText(t, at)`.
    pub fn when_text(&self, t: &V, at: &V) -> String {
        let V::Num(x) = t else { return String::new() };
        if !x.is_finite() { return String::new(); }
        if (tv(at) && crate::lay::read::dates::at_fits(self.w.rc, at, t)) || *x == x.trunc() { return format_date(self.w.rc, t, at); }
        format_t(*x, "d")
    }
    /// `endText(t)`.
    pub fn end_text(&self, t: &V) -> String { if (n(t) - self.w.now_t).abs() < 1e-9 { "현재".into() } else { self.when_text(t, &V::Undef) } }
    /// `endWhen(x)`.
    pub fn end_when(&self, x: &V) -> String {
        if tv(&x.get("ongoing")) { "현재".into() } else { format_when(self.w.rc, x, if x.get("end").is_nullish() { "start" } else { "end" }) }
    }
    /// `cellWhen(c, useEndY, p)` — 칸의 기간 글.
    pub fn cell_when(&self, c: &V, use_end_y: bool, p: &V) -> String {
        let o = Obj::new();
        o.set("start", c.get("start"));
        o.set("startAt", c.get("startAt"));
        o.set("end", if use_end_y { c.get("endY") } else { c.get("end") });
        o.set("endAt", if use_end_y { c.get("endYAt") } else { c.get("endAt") });
        o.set("startUnknown", c.get("startUnknown"));
        o.set("endUnknown", or(c.get("endUnknown"), if use_end_y { c.get("endYAuto") } else { V::Bool(false) }));
        o.set("ongoing", web::cell_to_now(c, p));
        format_range(self.w.rc, &V::Obj(o))
    }
    /// `serviceWhen(f, s)` — 활동 기록 한 줄의 기간 글.
    pub fn service_when(&self, f: &V, sv: &V) -> String {
        let a = if tv(&sv.get("fromUnknown")) { "미정".into() } else { self.when_text(&sv.get("from"), &sv.get("fromAt")) };
        let b = if tv(&f.get("ongoing")) && eq(&sv.get("to"), &f.get("endY")) { "현재".into() } else if tv(&sv.get("toUnknown")) { "미정".into() } else { self.when_text(&sv.get("to"), &sv.get("toAt")) };
        format!("{a} ~ {b}")
    }
    /// `sideSpan(s)` — 시작 · 끝을 적은 것의 글(아무것도 없으면 '').
    pub fn side_span(&self, sv: &V) -> String {
        let (st, en) = (sv.get("start"), sv.get("end"));
        if !(!st.is_nullish() || !en.is_nullish() || tv(&sv.get("startUnknown")) || tv(&sv.get("endUnknown"))) { return String::new(); }
        let a = if tv(&sv.get("startUnknown")) { "미정".into() } else if !st.is_nullish() { self.when_text(&st, &sv.get("startAt")) } else { String::new() };
        let b = if tv(&sv.get("endUnknown")) { "미정".into() } else if !en.is_nullish() { self.when_text(&en, &sv.get("endAt")) } else { String::new() };
        Str::from(format!("{a} ~ {b}")).trim().as_str().into_owned()
    }
    /// `spanText(r)` — 기간 글(단체의 있던 나라 · 제도의 같은 갈래).
    pub fn span_text(&self, r: &V) -> String {
        let o = Obj::new();
        for k in ["start", "startAt", "end", "endAt", "startUnknown", "endUnknown"] { o.set(k, r.get(k)); }
        format_range(self.w.rc, &V::Obj(o))
    }
}

/// `brief(HT, p, extra)` — 목록 한 줄에 쓰는 가장 작은 꼴 `{ uid, name, color, when, …extra }`(p가 거짓이면 null).
pub fn brief(w: &W, p: &V, extra: &[(&str, V)]) -> V {
    if !tv(p) { return V::Null; }
    let o = Obj::new();
    o.set("uid", p.get("uid"));
    o.set("name", or(or(p.get("name"), p.get("title")), s("")));
    o.set("color", or(p.get("color"), s("")));
    o.set("when", format_range(w.rc, p));
    for (k, v) in extra { o.set(*k, v.clone()); }
    V::Obj(o)
}

/// 미리 푼 값의 표(uid → `{ x_… }` — JS Map)와 넣기(`put`).
pub struct Ex { pub map: Map }
impl Ex {
    /// `put(x, key, value)` — 빈 것은 싣지 않는다 · x에 uid가 없으면 싣지 않는다.
    pub fn put(&self, x: &V, key: &str, value: V) {
        let v = some(value);
        if v.is_nullish() || !tv(x) || !tv(&x.get("uid")) { return; }
        let uid = x.get("uid");
        let o = match self.map.get(&uid) { V::Obj(o) => o, _ => { let o = Obj::new(); self.map.set(uid, o.clone()); o } };
        o.set(key, v);
    }
    /// `ex.get(uid)`.
    pub fn get(&self, uid: &V) -> Option<Obj> { if let V::Obj(o) = self.map.get(uid) { Some(o) } else { None } }
}

/// 이 모듈이 함께 쓰는 문맥(모델 · 웹 전역 · 미리 푼 값 · 계보 뼈대의 기억).
pub struct Cx<'a> { pub model: V, pub w: W<'a>, pub ex: Ex, pub kc: people::KinCache }
impl Cx<'_> {
    /// `textOf(HT)`.
    pub fn t(&self) -> T<'_> { T { w: &self.w } }
}

/// 기록을 싣는 동안의 셈(1323 ~ 1327줄의 `kinds` · `bytes` · `xBytes` · `findBytes` · `refs`)과 실을 기록.
#[derive(Default)]
struct Load { pushed: Vec<Value>, kinds: Vec<(String, f64)>, bytes: usize, x_bytes: usize, find_bytes: usize, refs: Vec<(V, Set)> }
impl Load {
    /// `push(uid, kind, body, pack)`.
    fn push(&mut self, uid: &V, kind: &str, body: &V, pack: f64) {
        let text = js::stringify(body);
        self.bytes += Str::from(text.as_str()).len16();
        match self.kinds.iter_mut().find(|x| x.0 == kind) { Some(x) => x.1 += 1.0, None => self.kinds.push((kind.to_string(), 1.0)) }
        self.pushed.push(json!({ "uid": js::to_json(uid), "kind": kind, "json": text, "pack": jv(pack) }));
    }
}

/// `autoPack(x, users)` — packId가 없는(저절로 생긴) 사전 항목: 그것을 쓴 항목 가운데 켠 차례로 가장 앞선 DLC(고리는 0으로 막음).
fn auto_pack(ctx: &Ctx, memo: &Map, x: &V, users: &dyn Fn() -> Vec<V>) -> f64 {
    if tv(&x.get("packId")) { return ctx.pack_of(x); }
    if memo.has(&x.get("uid")) { return n(&memo.get(&x.get("uid"))); }
    memo.set(x.get("uid"), 0.0);
    let mut best = f64::INFINITY;
    for u in users() { if !u.is_nullish() && n(&u) < best { best = n(&u); } }
    let v = if best.is_finite() { best } else { 0.0 };
    memo.set(x.get("uid"), v);
    v
}
/// `placePack(pl)`.
fn place_pack(ctx: &Ctx, memo: &Map, model: &V, pl: &V) -> f64 {
    auto_pack(ctx, memo, pl, &|| {
        let mut out: Vec<V> = list(&pl.get("uses")).iter().map(|u| {
            let mp = if tv(&u.get("mapId")) && tv(&model.get("mapMap")) { web::map_get(&model.get("mapMap"), &u.get("mapId")) } else { V::Undef };
            if tv(&u.get("item")) { V::Num(ctx.pack_of(&u.get("item"))) } else if tv(&mp) { V::Num(ctx.pack_of(&mp)) } else { V::Null }
        }).collect();
        out.extend(list(&pl.get("children")).iter().map(|id| { let c = web::map_get(&model.get("placeMap"), id); if tv(&c) { V::Num(place_pack(ctx, memo, model, &c)) } else { V::Null } }));
        out
    })
}
/// `housePack(h)`.
fn house_pack(ctx: &Ctx, memo: &Map, h: &V) -> f64 {
    auto_pack(ctx, memo, h, &|| list(&h.get("members")).iter().map(|mb| if tv(&mb.get("item")) { V::Num(ctx.pack_of(&mb.get("item"))) } else { V::Null }).collect())
}
/// `surnamePack(sn)`.
fn surname_pack(ctx: &Ctx, memo: &Map, model: &V, sn: &V) -> f64 {
    auto_pack(ctx, memo, sn, &|| list(&sn.get("houses")).iter().map(|id| { let h = web::map_get(&model.get("houseMap"), id); if tv(&h) { V::Num(house_pack(ctx, memo, &h)) } else { V::Null } }).collect())
}

/// 리메이크 3단계(계약 1-1 초안 — entities.mjs 1322 ~ 1337줄): 인물의 칭호 묶음 `x_titles` — 사람 창이 그대로 그림(`HT.personTitles`와 같은 칸 · 같은 차례).
/// `[{ uid: 객체 띠 uid, cell: 칸 순번, office: '지도자' | '내각', name: 객체 이름, start · end: 분, rank: 지위 }]`(시작 차례 — 없으면 0으로 봄) · 칭호가 없으면 싣지 않음.
/// 덧붙이는 자리는 cross_refs가 만든 미리 푼 값의 뒤(`extra.get(fu).x_titles = titles` — 그 인물의 것이 없으면 새로).
fn titles_of(ctx: &Ctx, model: &V, ex: &Ex) {
    use crate::lay::model::util::{arr, is, nn};
    for nd in list(&or(model.get("persons"), arr(Vec::new()))) {
        // `n && n.figure && n.figure.uid`
        let fig = if tv(&nd) { nd.get("figure") } else { nd.clone() };
        let fu = if tv(&fig) { fig.get("uid") } else { fig };
        if !tv(&fu) { continue; }
        let mut titles: Vec<V> = list(&or(nd.get("cells"), arr(Vec::new()))).into_iter()
            .filter(|q| tv(q) && tv(&q.get("p")) && tv(&q.get("c")) && (is(&q.get("kind"), "leader") || is(&q.get("kind"), "cabinet")))
            .map(|q| {
                let (p, c) = (q.get("p"), q.get("c"));
                let sp = crate::lay::web::cells::cell_span(&ctx.read, &c, &p, &q.get("ref"));
                V::Obj(crate::lay::model::o! {
                    "uid" => p.get("uid"), "cell" => q.get("i"), "office" => if is(&q.get("kind"), "leader") { "지도자" } else { "내각" },
                    "name" => or(or(p.get("name"), p.get("id")), s("")), "start" => mm(&sp.get("start")),
                    "end" => mm(&nn(sp.get("end"), p.get("endY"))), "rank" => or(c.get("rank"), s("")),
                })
            })
            .collect();
        js::sort(&mut titles, |a, b| n(&nn(a.get("start"), V::Num(0.0))) - n(&nn(b.get("start"), V::Num(0.0))));
        if titles.is_empty() { continue; }
        if !ex.map.has(&fu) { ex.map.set(fu.clone(), Obj::new()); }
        if let V::Obj(o) = ex.map.get(&fu) { o.set("x_titles", arr(titles)); }
    }
}

/// `contribute(ctx, out)` — 항목 기록을 `out.entities`에 싣는다(1313 ~ 1492줄).
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> { contribute_limit(ctx, out, kin::KIN_LIMIT) }

#[doc(hidden)]
/// [`contribute`]를 뼈대 덩어리 상한 `limit`로(`kinCollect(model, HT, { limit })` — 웹 내보내기는 늘 기본 상한 5만). 검사가 작은 상한으로 덩어리 길 ·
/// 끝의 점검(꼬투리 빼기 `totalOf` · `chunk`)을 밟으려고 연다 — 정답지 자료에는 마디 5만을 넘는 뼈대가 없다.
pub fn contribute_limit(ctx: &mut Ctx, out: &mut Value, limit: usize) -> crate::Result<()> {
    let model = ctx.model.clone();
    let ctx: &Ctx = ctx;
    let mut cx = Cx { model: model.clone(), w: W { rc: &ctx.read, now_t: ctx.now_t, current_year: ctx.now_year }, ex: Ex { map: Map::new() }, kc: people::KinCache::default() };
    // 계보 뼈대(D1 — export/kin.mjs): 미리 푼 값(x_kin · x_lineage의 kinAt)이 이것을 가리킨다.
    let mut kin = kin::kin_collect(&mut cx.kc, &model, limit);
    if let Some(k) = kin.as_mut() { k.roots = k.records.iter().filter(|r| r.uid == r.root_uid).map(|r| r.uid.clone()).collect(); }
    // 본문이 있는 문서의 열쇠(머리 칩의 구분 · 민족 → 문서 창) — 문서 모듈(docs)이 먼저 실었다
    let doc_bodies = Set::new();
    for e in out["entities"].as_array().into_iter().flatten() {
        let uid = e["uid"].as_str().unwrap_or("");
        if e["kind"] == "doc" && uid.starts_with("doc:") {
            let body = js::parse(e["json"].as_str().unwrap_or("null"))?;
            if !tv(&body.get("empty")) { doc_bodies.add(V::from(&uid[4..])); }
        }
    }
    cross::cross_refs(&mut cx, kin.as_ref(), &doc_bodies);
    titles_of(ctx, &model, &cx.ex);
    let finds = find::find_of(&cx);
    super::kit::fault_check("entities")?; // JS라면 미리 푼 값을 짓다 TypeError로 멈췄을 곳(과제 Y — 사람 고리 · 목록 한 줄 · 가문 · 뼈대)
    let mut ld = Load::default();
    let memo = Map::new();
    let pack_for = |x: &V, kind: &str| -> f64 {
        match kind { "place" => place_pack(ctx, &memo, &model, x), "surname" => surname_pack(ctx, &memo, &model, x), "house" => house_pack(ctx, &memo, x), _ => ctx.pack_of(x) }
    };
    let add = |ld: &mut Load, x: &V, strip: Option<&dyn Fn(V) -> V>| {
        if !matches!(if tv(x) { x.get("uid") } else { V::Undef }, V::Str(ref u) if !u.is_empty()) { return; }
        let kind = js::to_str(&or(or(x.get("itemKind"), item_kind_of(x)), s("period"))).as_str().into_owned();
        let mine = Set::new();
        let mut body = plain(x, Some(&mine));
        if let Some(f) = strip { body = f(body); }
        ld.refs.push((x.get("uid"), mine));
        if let Some(more) = cx.ex.get(&x.get("uid")) {
            ld.x_bytes += Str::from(js::stringify(&V::Obj(more.clone()))).len16();
            if let V::Obj(b) = &body { for (k, v) in more.entries() { b.set(&k, v); } } // 미리 푼 값은 뒤에(지금의 값은 그대로)
        }
        let find = finds.get(&x.get("uid"));
        if tv(&find) {
            ld.find_bytes += Str::from(js::stringify(&find)).len16();
            if let V::Obj(b) = &body { b.set("x_find", find); }
        }
        let pack = pack_for(x, &kind);
        ld.push(&x.get("uid"), &kind, &body, pack);
    };
    for k in ["periods", "events", "figures"] { for x in list(&model.get(k)) { add(&mut ld, &x, None); } } // 정권 · 기관 · 문화 · 왕조가 같은 틀(itemKind로 갈린다)
    // 계보 전용 인물(D1): 갈래는 인물(figure)이고 본문은 활동 칸(활동 기록 · 중요도)을 뺀 것 — 띠에 그리지 않는다
    let strip_lineage = |b: V| { if let V::Obj(o) = &b { for k in ["services", "service", "importance"] { o.delete(k); } } b };
    for f in list(&model.get("lineageFigures")) { add(&mut ld, &f, Some(&strip_lineage)); }
    // 시대 구분 · 대범위 · 가문(uid 'house:<id>') · 단체 · 제도(모델 차례 그대로) · 지명('place:<id>') · 성씨('surname:<id>')
    for k in ["epochs", "scopes", "houses", "groups", "institutions", "places", "surnames"] { for x in list(&model.get(k)) { add(&mut ld, &x, None); } }
    let themes = list(&model.get("themes"));
    if !themes.is_empty() {
        // 주제 사전 하나 — `name` 칸이 없어 이름 표에 들지 않는다
        let l: Vec<V> = themes.iter().map(|th| {
            let o = Obj::new();
            o.set("id", th.get("id"));
            o.set("name", or(th.get("name"), s("")));
            o.set("color", or(th.get("color"), s("")));
            o.set("order", th.get("order"));
            if tv(&th.get("auto")) { o.set("auto", 1.0); }
            if let V::Arr(a) = th.get("names") { if !a.is_empty() { o.set("names", plain(&th.get("names"), None)); } }
            V::Obj(o)
        }).collect();
        let body = Obj::new();
        body.set("list", web::va(l));
        ld.push(&s("themes"), "themes", &V::Obj(body), 0.0);
    }
    for x in list(&model.get("views")) { add(&mut ld, &x, None); } // 모아 보기 판 — 나르기만
    // 지도: 장면(scenes)은 x_scenes로 풀어 싣고 본문에서는 뺀다(틀 frames와 같은 것을 두 번 싣지 않게). 그림 데이터 URL은 크기만.
    let strip_map = |b: V| { if let V::Obj(o) = &b { o.delete("scenes"); o.delete("regionMap"); } find::drop_bytes(b) };
    for m in list(&model.get("maps")) { add(&mut ld, &m, Some(&strip_map)); }
    let strip_font = |b: V| find::drop_bytes(b);
    for f in list(&model.get("fonts")) { add(&mut ld, &f, Some(&strip_font)); } // 글꼴: src(데이터 URL)는 크기만
    // 계보 뼈대 기록(갈래 kin — 열 꼴 JSON). 귀속은 뿌리 가문의 DLC(가문이 없는 지도자의 뼈대는 그 정권의 DLC).
    let mut kin_bytes = 0usize;
    for r in kin.as_ref().map(|k| k.records.as_slice()).unwrap_or(&[]) {
        let hm = model.get("houseMap");
        let by_uid = model.get("byUid");
        let pack = match (&r.house_id, &r.polity_uid) {
            (Some(h), _) if tv(h) && tv(&web::map_get(&hm, h)) => house_pack(ctx, &memo, &web::map_get(&hm, h)),
            (_, Some(u)) if tv(&web::map_get(&by_uid, &s(u))) => ctx.pack_of(&web::map_get(&by_uid, &s(u))),
            _ => 0.0,
        };
        let before = ld.bytes;
        ld.push(&s(&r.uid), "kin", &r.body.to_v(), pack);
        kin_bytes += ld.bytes - before;
    }
    let pushed = std::mem::take(&mut ld.pushed);
    crate::lay::export::arr_mut(out, "entities").extend(pushed);
    let (links, ref_links) = check(out, &cx, kin.as_ref(), &finds, &ld.refs)?;
    let mb = |b: usize| js::round(b as f64 / 1_048_576.0 * 100.0) / 100.0;
    let note = Obj::new();
    note.set("크기MB", mb(ld.bytes));
    note.set("미리푼값MB", mb(ld.x_bytes));
    note.set("찾을글MB", mb(ld.find_bytes));
    note.set("이은고리", links);
    note.set("본문고리", ref_links);
    for (k, v) in &ld.kinds { note.set(k.as_str(), *v); }
    ctx.notes.set("항목기록", note);
    if let Some(k) = &kin {
        let o = Obj::new();
        o.set("기록MB", mb(kin_bytes));
        for (kk, v) in k.notes.entries() { o.set(&kk, v); }
        ctx.notes.set("계보", o);
    }
    super::kit::fault_check("entities")?;
    // 보조 달력 표가 모자라 날짜 글을 읽지 못했으면 조용히 다른 글을 내지 않는다(계획 정한 것 #7)
    if let Some(name) = ctx.read.cal.missed_of() { return Err(format!("항목 기록: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다").into()); }
    if let Some(name) = ctx.read.cal.absent_of() { return Err(format!("항목 기록: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다").into()); }
    Ok(())
}

/// `totalOf(key)`(1458 ~ 1472줄) — 나눈 뼈대는 꼬투리 아래까지 센 한 벌 마디 수(덩어리마다 n을 더하고 꼬투리 하나마다 1을 빼며 그 덩어리로 내려감).
/// `recs`는 `kinRec`(기록 uid → 본문). 덩어리 기록이 없으면 오류(Node의 throw 글 그대로). 검사가 덩어리 길을 견주려고 연다.
#[doc(hidden)]
pub fn kin_total(recs: &std::collections::HashMap<&str, &kin::Rec>, key: &str) -> crate::Result<i64> {
    fn walk(uid: &str, recs: &std::collections::HashMap<&str, &kin::Rec>, n: &mut i64) -> crate::Result<()> {
        let b = recs.get(uid).ok_or_else(|| format!("뼈대 덩어리 기록이 없습니다: {uid}"))?;
        *n += b.n as i64;
        for (_, st) in &b.stubs { *n -= 1; walk(&st.key, recs, n)?; }
        Ok(())
    }
    let mut n = 0;
    walk(key, recs, &mut n)?;
    Ok(n)
}

/// 끝의 점검(1420 ~ 1488줄): uid가 겹치지 않고 · 가리키는 uid는 모두 제 기록이 있고 · 경계 · 기간이 뒤집히지 않고 · 계보 뼈대의 고리가 모두 있다(Node의 throw 글 그대로).
/// 돌려주는 값: (이은 고리 수 · 본문 고리 수 — 집계).
fn check(out: &Value, cx: &Cx, kin: Option<&kin::KinOut>, finds: &Map, refs: &[(V, Set)]) -> crate::Result<(f64, f64)> {
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    for e in out["entities"].as_array().into_iter().flatten() {
        let uid = e["uid"].as_str().unwrap_or("").to_string();
        if seen.contains(&uid) { return Err(format!("항목 기록의 uid가 겹칩니다: {uid}").into()); }
        seen.insert(uid);
    }
    let has = |u: &Str| seen.contains(u.as_str().as_ref());
    let mut links = 0.0;
    /* 가리키는 uid는 모두 제 기록이 있어야 한다 — 미리 푼 값(x_)의 uid · 본문의 $ref · 찾을 글의 빌린 줄(x_find.row). 경계는 [lo, hi]가 뒤집히지 않아야 한다. */
    fn walk(v: &V, uid: &str, has: &dyn Fn(&Str) -> bool, links: &mut f64) -> crate::Result<()> {
        if let V::Arr(a) = v { for q in a.to_vec() { walk(&q, uid, has, links)?; } return Ok(()); }
        if !matches!(v, V::Obj(_)) { return Ok(()); }
        if let V::Str(u) = v.get("uid") {
            if !u.is_empty() {
                *links += 1.0;
                if !has(&u) { return Err(format!("미리 푼 값이 없는 기록을 가리킵니다: {uid} → {u}").into()); }
            }
        }
        if let V::Str(nat) = v.get("nation") { if !nat.is_empty() && !has(&nat) { return Err(format!("구성원의 나라 기록이 없습니다: {uid} → {nat}").into()); } }
        if let V::Obj(o) = v { for (_, x) in o.entries() { walk(&x, uid, has, links)?; } }
        Ok(())
    }
    for (uid, more) in cx.ex.map.entries() {
        let uid = js::to_str(&uid).as_str().into_owned();
        let V::Obj(more) = more else { continue };
        for (k, v) in more.entries() {
            if k == "x_cellBounds" {
                if let V::Obj(b) = &v { for (r, x) in b.entries() { if !(n(&x.get(&0.0)) <= n(&x.get(&1.0))) { return Err(format!("칸의 경계가 뒤집혔습니다: {uid} {r} {}", js::to_str(&x)).into()); } } }
            } else { walk(&v, &uid, &has, &mut links)?; }
        }
    }
    for (uid, find) in finds.entries() {
        let row = find.get("row");
        if tv(&row) && !has(&js::to_str(&row)) { return Err(format!("찾을 글의 빌린 줄이 없는 기록을 가리킵니다: {} → {}", js::to_str(&uid), js::to_str(&row)).into()); }
        let sp = find.get("span");
        if tv(&sp) && !(n(&sp.get(&0.0)) <= n(&sp.get(&1.0))) { return Err(format!("찾을 글의 기간이 뒤집혔습니다: {}", js::to_str(&uid)).into()); }
    }
    let mut ref_links = 0.0;
    for (uid, mine) in refs {
        for to in mine.values() {
            ref_links += 1.0;
            if !has(&js::to_str(&to)) { return Err(format!("본문의 $ref가 없는 기록을 가리킵니다: {} → {}", js::to_str(uid), js::to_str(&to)).into()); }
        }
    }
    /* 계보(D1): x_kin · x_lineage의 kinAt이 가리키는 뼈대 기록, 뼈대 기록의 꼬투리 · 위 덩어리 · 파 표의 가문이 모두 있어야 한다. 번호는 한 벌 안. */
    if let Some(k) = kin {
        let kin_rec: std::collections::HashMap<&str, &kin::Rec> = k.records.iter().map(|r| (r.uid.as_str(), &r.body)).collect();
        let point_at = |uid: &str, key: &Str, at: &V, chunk: &V| -> crate::Result<()> {
            let key = key.as_str();
            if !kin_rec.contains_key(key.as_ref()) { return Err(format!("뼈대 기록이 없는 곳을 가리킵니다: {uid} → {key}").into()); }
            if !at.is_nullish() {
                let ok = matches!(at, V::Num(a) if *a == a.trunc() && *a >= 0.0 && *a < kin_total(&kin_rec, &key)? as f64);
                if !ok { return Err(format!("뼈대 번호가 범위 밖입니다: {uid} → {key} {}", js::to_str(at)).into()); }
            }
            if !chunk.is_nullish() && !kin_rec.contains_key(js::to_str(chunk).as_str().as_ref()) { return Err(format!("뼈대 덩어리 기록이 없습니다: {uid} → {}", js::to_str(chunk)).into()); }
            Ok(())
        };
        for (uid, more) in cx.ex.map.entries() {
            let uid = js::to_str(&uid).as_str().into_owned();
            let V::Obj(more) = more else { continue };
            let xk = more.get("x_kin");
            if tv(&xk) { point_at(&uid, &js::to_str(&xk.get("key")), &xk.get("at"), &xk.get("chunk"))?; }
            if let V::Obj(lin) = more.get("x_lineage") {
                for (r, l) in lin.entries() {
                    let ka = l.get("kinAt");
                    if tv(&ka) { point_at(&format!("{uid} {r}"), &js::to_str(&ka.get(&0.0)), &ka.get(&1.0), &V::Null)?; }
                }
            }
        }
        for r in &k.records {
            let (uid, b) = (r.uid.as_str(), &r.body);
            for br in &b.branches { if !br.uid.is_empty() && !has(&br.uid) { return Err(format!("뼈대의 파 표가 없는 가문을 가리킵니다: {uid} → {}", br.uid).into()); } }
            for (_, st) in &b.stubs { if !kin_rec.contains_key(st.key.as_str()) { return Err(format!("꼬투리가 없는 덩어리를 가리킵니다: {uid} → {}", st.key).into()); } }
            if let Some(root) = &b.root { if !kin_rec.contains_key(root.up.as_str()) { return Err(format!("덩어리의 위 기록이 없습니다: {uid} → {}", root.up).into()); } }
            if b.par.len() != b.n || b.key.len() != b.n { return Err(format!("뼈대 열의 길이가 n과 다릅니다: {uid}").into()); }
        }
    }
    Ok((links, ref_links))
}

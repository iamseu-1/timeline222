//! 내보내기 모듈 `persons` — 사람 띠(리메이크 3단계 · 계약 1-1 초안 · 설계 3-11 ① — 세계사 장면 1): 왕관(지도자 칸의 person 이음)이 둘 이상의 객체에 있는
//! 사람마다 문화권 단위의 표 `sphere_lines`에 kind 1 한 줄. 사람 띠는 트랙의 줄이 아니라 문화권 머리 단 자리에 서므로 줄 · 타일에 들지 않는다.
//! `out.sphereLines`만 쓰고 다른 값은 건드리지 않는다 — 왕관이 둘 이상인 사람이 없으면 아무것도 싣지 않고 열쇠도 만들지 않는다(옛 출력 그대로).
//!
//! 옮긴 원본:
//! - `prototype/scripts/export/persons.mjs` 1 ~ 33줄 — SHA-256 앞 12자 `ba97541280bb`(저장소의 LF 바이트) → [`LINE_PERSON`] … · [`push_line`] · [`contribute`]
//! - `js/core.js` 7306 ~ 7329줄 `HT.personBands`(메이커 서고 미리보기 `HT.f4Preview`와 같은 셈) → [`person_bands`]
//!
//! 부르는 웹 함수(이미 옮긴 것): `HT.cellSpan`(→ [`crate::lay::web::cells::cell_span`]) · `HT.sphereOrder`(→ 모델의 `sphereMap`을 받는 [`sphere_order`]).
//! 쓰는 · 읽는 shared 없음. axis(문화권 시대 · 주기 줄)도 [`push_line`]으로 같은 표에 싣는다.
use super::kit::minute_js;
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, jsv, jv};
use crate::lay::js::{self, Map, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, eq, is, list, or, s, sphere_order, tv};
use crate::lay::read;
use crate::lay::web::cells::cell_span;
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// `sphere_lines`의 kind(persons.mjs 10줄 `LINE` — 계약 1-1 초안): 1 사람 띠 · 2 문화권 시대 구분 · 3 문화권 주기 줄.
pub const LINE_PERSON: f64 = 1.0;
pub const LINE_EPOCH: f64 = 2.0;
pub const LINE_CYCLE: f64 = 3.0;

/// `pushLine(out, line)`(persons.mjs 13 ~ 16줄) — `out.sphereLines`에 한 줄. 열쇠는 처음 실을 때 만든다(옛 출력에 빈 열쇠가 생기지 않게).
pub fn push_line(out: &mut Value, line: Value) { arr_mut(out, "sphereLines").push(line); }

/// `typeof v === 'number' && Number.isFinite(v) ? v : null`.
fn num(v: &V) -> Option<f64> { match v { V::Num(x) if x.is_finite() => Some(*x), _ => None } }

/// `HT.personBands(model)`(core.js 7306 ~ 7329줄) — 왕관이 둘 이상의 객체에 있는 사람마다
/// `{ name, start, end(그 칸들의 가장 이른 시작 ~ 가장 늦은 끝), crowns: [{ uid, i }], figure(인물 uid · 없으면 ''), sphere(왕관 트랙들의 문화권 가운데 차례가 가장 앞 · 없으면 '') }`.
pub fn person_bands(rc: &read::Ctx, model: &V) -> Vec<V> {
    let mut out = Vec::new();
    if !tv(model) { return out; }
    let sphere_map = match model.get("sphereMap") { V::Map(m) => m, _ => Map::new() };
    let track_sphere = Map::new();
    for t in list(&or(model.get("tracks"), arr(Vec::new()))) { track_sphere.set(t.get("id"), or(t.get("sphere"), s(""))); }
    for nd in list(&or(model.get("persons"), arr(Vec::new()))) {
        let cells: Vec<V> = (if tv(&nd) && tv(&nd.get("cells")) { list(&nd.get("cells")) } else { Vec::new() })
            .into_iter().filter(|q| tv(q) && is(&q.get("kind"), "leader") && tv(&q.get("p")) && tv(&q.get("c"))).collect();
        let uids = Set::new();
        for q in &cells { uids.add(q.get("p").get("uid")); }
        if uids.len() < 2 { continue; }
        let (mut a, mut b) = (f64::INFINITY, f64::NEG_INFINITY);
        for q in &cells {
            let sp = cell_span(rc, &q.get("c"), &q.get("p"), &q.get("ref"));
            if let Some(x) = num(&sp.get("start")) { a = js::min(&[a, x]); }
            let e = num(&sp.get("end")).or_else(|| num(&q.get("p").get("endY")));
            if let Some(e) = e { b = js::max(&[b, e]); }
        }
        if !a.is_finite() || !b.is_finite() || b <= a { continue; }
        let mut sphere = s("");
        for q in &cells {
            let sp = or(track_sphere.get(&q.get("p").get("track")), s(""));
            if tv(&sp) && (!tv(&sphere) || sphere_order(&sphere_map, &sp) < sphere_order(&sphere_map, &sphere)) { sphere = sp; }
        }
        let crowns: Vec<V> = cells.iter().map(|q| V::Obj(o! { "uid" => q.get("p").get("uid"), "i" => q.get("i") })).collect();
        let fig = nd.get("figure");
        let figure = or(if tv(&fig) { fig.get("uid") } else { fig }, s(""));
        out.push(V::Obj(o! { "name" => or(nd.get("name"), s("")), "start" => a, "end" => b, "crowns" => arr(crowns), "figure" => figure, "sphere" => sphere }));
    }
    out
}

/// `contribute(ctx, out)`(persons.mjs 18 ~ 33줄) — 사람 띠마다 `sphere_lines` kind 1: sphere · start · end(분) · name = 사람 이름 · uid = 인물 uid · color 0 ·
/// data = 왕관 목록 JSON `[{"uid": 객체 띠 uid, "cell": 지도자 칸 순번}]` · pack = 인물이 든 DLC.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let bands = person_bands(&ctx.read, &ctx.model);
    let figures = ctx.model.get("figures");
    let mut count = 0.0;
    for b in &bands {
        // `start == null || end == null || end < start` — Date 범위 밖(NaN)은 견줌이 거짓이라 실리고 JSON에서 null(JS와 같음)
        let (Some(start), Some(end)) = (minute_js(&b.get("start")), minute_js(&b.get("end"))) else { continue };
        if end < start { continue; }
        let figure = b.get("figure");
        // `b.figure && model.figures ? model.figures.find(f => f.uid === b.figure) : null`
        let fig = if tv(&figure) && tv(&figures) { list(&figures).into_iter().find(|f| eq(&f.get("uid"), &figure)).unwrap_or(V::Undef) } else { V::Null };
        let crowns: Vec<V> = list(&b.get("crowns")).iter().map(|c| V::Obj(o! { "uid" => c.get("uid"), "cell" => c.get("i") })).collect();
        push_line(out, json!({
            "kind": jv(LINE_PERSON), "sphere": jsv(&or(b.get("sphere"), s(""))), "start": jv(start), "end": jv(end), "name": jsv(&or(b.get("name"), s(""))),
            "uid": jsv(&or(figure.clone(), s(""))), "color": 0, "data": js::stringify(&arr(crowns)), "pack": jv(ctx.pack_of(&fig)),
        }));
        count += 1.0;
    }
    ctx.notes.set("사람띠", count);
    Ok(())
}

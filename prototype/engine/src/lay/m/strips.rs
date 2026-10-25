//! 내보내기 모듈 `strips` — 띠 안의 모든 단의 칸: 왕조 · 지도자 · 내각 · 기관 · 시기 구분 · 지위 · 예속(안). 한 벌 P3 과제 9(갈래 A) — 줄 그대로 옮긴다.
//! 단의 종류 번호와 lane · style · color의 뜻은 계약 6절. 화면에 달린 값(잘림 · 조명 · 이름이 몇 글자나 드는가)은 싣지 않는다.
//! 칸에 딸린 것(모호한 구간 · 이설 경계 · 가문 · 가리키는 항목 · 지도자 표기)은 일반 항목 구역 40 ~ 43 · 46으로 나간다(계약 6-2 끝).
//!
//! 옮긴 원본:
//! - `prototype/scripts/export/strips.mjs` 1 ~ 325줄 — SHA-256 앞 12자 `52ff0a767306`(저장소의 LF 바이트) → [`SECTION_ZONE`] … · [`contribute`]
//!   (2026-10-24 맞춤 · 리메이크 3단계 과제 3 ~ 6 · 계약 1-1 초안 — 줄 번호는 지금 지문의 것) 16 ~ 40줄 구역 54 · 55 · 칸 종류 9 · 빌린 칸 27비트 · `fromOf` · `officeCells`(→ [`SECTION_BORROW`] · [`SECTION_OFFICE_NAME`] · [`KIND_OFFICE`] · [`ST_BORROW`] · `from_of` · `office_cells`) · 203줄 지도자 · 내각 칸의 빌림 비트 · 209 ~ 237줄 빌린 줄의 머리 글과 직위 줄 더
//!   (2026-10-25 맞춤 · 4단계 배치 갈래 걸음 5 · 계약 1-1 덧붙임 · 감독 결정 LEGIT 가) 4 · 6줄 · 16 ~ 17줄 `SECTION.legit`(→ [`SECTION_LEGIT`]) · 107줄 알림 `칸정통성` ·
//!   162 ~ 168줄 `marks`의 구역 57 — 칸의 정통성(지도자 · 내각 · 직위 줄 더의 칸만 · `statusNoOf` = [`super::bands::status_no_of`])
//!   (2026-10-25 맞춤 · 4단계 배치 갈래 둘째 · 계약 1-1 덧붙임 — 줄 번호는 지금 지문 `52ff0a767306`의 것) 5줄 머리 · 110줄 알림 `지도자_두단` · 197 ~ 221줄 지도자 칸의 lane =
//!   `tl._leaderLanes(p).lane[i]`(→ [`crate::lay::rows::leader_lanes`]) · 단마다의 이음(prevKey) · 324줄 알림
//!   (`styleWith` · `lodOf` · `cellStyle` · `cellBaseOf` · `dynCellOf` · `altEdges` · `marks` · `put` → 같은 이름의 snake_case — `altEdges`는 [`crate::lay::web::alts`]의 하나 ·
//!   `styleWith` · `lodOf` · `cellStyle` · `STRIP` · `ST`는 power · lens와 함께 쓰는 [`super::kit`]의 하나 — 과제 Y)
//!
//! 부르는 웹 함수(과제 Y가 [`crate::lay::web`]에 모음 — 처음 옮긴 판은 이 파일의 것): `HT.cellSpan` · `HT.cellToNow`(→ `web::cells`) · `HT.altSpan` · `HT.altFlipped`
//! (→ `web::alts`) · `HT.datedAlts` · `HT.leaderLabel`(기본 꼴 — `model::util`) · `tl._dynOf`(→ `rows::dyn_of`).
//! 읽는 shared: `bandOf`(bands가 만듦 — 없으면 JS도 TypeError: 오류). 읽는 out: `periods[bandOf]`(띠의 구간 · 줄) · `tracks[].rows[].organTop`(기관 단이 있는 줄).
use super::bands::status_no_of;
use super::kit::{cell_style, lod_of, nth_of, st, strip, style_with, SECTION_ITEM};
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, jn, jsv, jv, minute_num, minute_v};
use crate::lay::js::{self, Arr, Map, Obj, Str, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, copy, dated_alts, eq, index_of, is, leader_label, list, n, nn, or, or_cmp, s, sub, t, tv};
use crate::lay::read;
use crate::lay::rows::{dyn_of, leader_lanes};
use crate::lay::web::alts::{alt_edges, alts_of};
use crate::lay::web::cells::{cell_span, cell_to_now};
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// `DEP_LOOK[look] || 0`(strips.mjs 12줄 — 모양은 늘 `ctx::dep_look`이 고른 이름).
fn dep_look_no(look: &V) -> f64 {
    match look { V::Str(x) if x == "held" => 1.0, V::Str(x) if x == "owned" => 2.0, V::Str(x) if x == "occupied" => 3.0, _ => 0.0 }
}

/// 내가 쓰는 일반 항목 구역(40 ~ 43 · 46 — 계약 6-2 끝 · 43은 power · lens도 쓰는 [`SECTION_ITEM`]).
pub const SECTION_ZONE: f64 = 40.0;
pub const SECTION_ALT: f64 = 41.0;
pub const SECTION_HOUSE: f64 = 42.0;
pub const SECTION_LEADER_NAME: f64 = 46.0;
/// 리메이크 3단계(계약 1-1 초안 — strips.mjs 14 ~ 15줄 `SECTION.borrow` · `SECTION.officeName`): 빌린 직위 줄의 머리 글 · 직위 줄 더의 이름.
pub const SECTION_BORROW: f64 = 54.0;
pub const SECTION_OFFICE_NAME: f64 = 55.0;
/// 칸의 정통성(strips.mjs 17줄 `SECTION.legit` — 4단계 배치 갈래 · 계약 1-1 덧붙임): 지도자 · 내각 · 직위 줄 더의 칸에 status가 있으면 하나(`c` 순번 + 1 · `d` 정통성 번호 + 1).
pub const SECTION_LEGIT: f64 = 57.0;
/// 직위 줄 더(셋째 직위 줄부터)의 칸 종류 9(strips.mjs 17줄 `KIND_OFFICE` — 8은 공용 칸 단이 씀).
pub const KIND_OFFICE: f64 = 9.0;
/// 빌린 직위 줄의 칸 style 27비트(strips.mjs 18줄 `ST_BORROW` — 칸 종류 1 · 2 · 9에서만: 종류 8의 27 ~ 29는 단 갈래).
pub const ST_BORROW: i32 = 1 << 27;

// ── strips.mjs ──

/// `fromOf`의 답 — 출처(모델 정권 · 못 찾으면 null) · 직위 이름 · 머리 글("출처 이름/직위").
struct FromOf { src: V, office: Str, text: String }

/// `fromOf(model, p, ref)`(strips.mjs 22 ~ 30줄) — 빌림의 출처 "객체 id" · "객체 id/직위 이름"(형식 4 더하기 — offices[].from).
/// 온 uid(`model.byUid` — 통째가 uid면 / 로 자르지 않음) → 같은 DLC의 id → 이름 차례(HT.f4Preview의 fromText와 같은 뜻 — 첫 / 앞이 객체).
fn from_of(model: &V, p: &V, r: &V) -> FromOf {
    let text = js::to_str(&nn(r.clone(), s(""))).trim();
    let whole = match model.get("byUid") { V::Map(m) => m.get(&V::Str(text.clone())), _ => V::Undef };
    let cut = if tv(&whole) { -1.0 } else { text.index_of16(&Str::from("/"), 0.0) };
    let key = if cut >= 0.0 { text.slice16(0.0, cut).trim() } else { text.clone() };
    let office = if cut >= 0.0 { text.slice16(cut + 1.0, f64::INFINITY).trim() } else { Str::from("") };
    let src = if tv(&whole) { whole } else {
        let periods = list(&model.get("periods"));
        let (pk, kv) = (p.get("packId"), V::Str(key.clone()));
        periods.iter().find(|q| eq(&q.get("packId"), &pk) && eq(&q.get("id"), &kv))
            .or_else(|| periods.iter().find(|q| eq(&q.get("packId"), &pk) && eq(&q.get("name"), &kv)))
            .cloned().unwrap_or(V::Null)
    };
    let head = if tv(&src) { t(&src.get("name")) } else { key.as_str().into_owned() };
    let text = if office.is_empty() { head } else { format!("{head}/{}", office.as_str()) };
    FromOf { src, office, text }
}

/// `(x || []).forEach` · `.find`에 넣는 목록 — 거짓 같은 값은 빈 목록, 배열이면 그 원소, 참 같은 비배열은 JS라면 TypeError(오류 — 거울 검토가 찾음:
/// 형식 3 패치가 인물 · 사건의 leaders · cabinets를 배열 아닌 값으로 바꾸면 정규화를 지나 모델에 남는다).
fn js_list(v: &V, what: &str) -> crate::Result<Vec<V>> {
    if !tv(v) { return Ok(Vec::new()); }
    match v { V::Arr(_) => Ok(list(v)), _ => Err(format!("strips: {what}이(가) 배열이 아닙니다(JS라면 TypeError)").into()) }
}

/// `officeCells(src, office)`(strips.mjs 32 ~ 38줄) — 출처의 직위 줄 칸: 이름이 비거나 지도자면 지도자 칸, 내각이면 내각 칸, 그 밖은 출처의 직위 줄 더에서 같은 이름.
fn office_cells(src: &V, office: &Str) -> crate::Result<Vec<V>> {
    if !tv(src) { return Ok(Vec::new()); }
    if office.is_empty() || &*office.as_str() == "지도자" { return js_list(&src.get("leaders"), "빌림 출처의 leaders"); }
    if &*office.as_str() == "내각" { return js_list(&src.get("cabinets"), "빌림 출처의 cabinets"); }
    let want = V::Str(office.clone());
    match js_list(&src.get("offices"), "빌림 출처의 offices")?.into_iter().find(|o| tv(o) && eq(&o.get("name"), &want)) {
        Some(f) => js_list(&f.get("cells"), "빌림 출처 직위 줄의 cells"),
        None => Ok(Vec::new()),
    }
}

/// `cellBaseOf(HT, c, p, ref)`(strips.mjs 38 ~ 42줄) — 칸의 통설 구간(유령 구분선이 견주는 값 — js/timeline.js의 cellBaseOf와 같은 식). 이설이 없으면 null.
fn cell_base_of(rc: &read::Ctx, c: &V, p: &V, r: String) -> V {
    if !(tv(c) && c.bool("alternatives") && c.get("alternatives").bool("length")) { return V::Null; }
    let sp = cell_span(rc, c, p, &V::from(r));
    V::Obj(o! {
        "start" => sp.get("start"), "startAt" => c.get("startAt"), "end" => sp.get("end"), "endAt" => sp.get("endAt"), "startUnknown" => c.get("startUnknown"),
        "endUnknown" => c.bool("endUnknown") || (c.get("end").is_nullish() && c.bool("endYAuto")), "ongoing" => cell_to_now(c, p),
    })
}

/// `dynCellOf(HT, d, y)`(strips.mjs 45 ~ 59줄) — 왕조 칸의 이설: 다스린 구간의 것에 왕조 항목 자신의 이설을 더한다(js/timeline.js의 dynCellOf와 같은 식).
fn dyn_cell_of(d: &V, y: &V) -> V {
    let alts = dated_alts(y);
    if alts.is_empty() { return d.clone(); }
    let at_s = (n(&d.get("start")) - n(&y.get("start"))).abs() < 1e-9;
    let at_e = !y.bool("ongoing") && (n(&d.get("end")) - n(&y.get("endY"))).abs() < 1e-9;
    if !at_s && !at_e { return d.clone(); }
    let mut l: Vec<V> = if tv(d) { list(&or(d.get("alternatives"), arr(Vec::new()))) } else { Vec::new() };
    for a in &alts {
        let x = Obj::new();
        if at_s { x.set("start", a.get("start")); x.set("startAt", a.get("startAt")); }
        if at_e && !a.get("end").is_nullish() { x.set("end", a.get("end")); x.set("endAt", a.get("endAt")); }
        if !x.get("start").is_nullish() || !x.get("end").is_nullish() { x.set("label", a.get("label")); l.push(V::Obj(x)); }
    }
    let out = copy(d);
    out.set("alternatives", arr(l));
    V::Obj(out)
}

/// `o[k]`(수 열쇠 · 글 열쇠 — JS 속성 열쇠는 `String(k)`).
fn at(o: &V, k: &V) -> V { match k { V::Num(x) => o.get(x), other => o.get(t(other).as_str()) } }

/// 칸에 딸린 항목의 집계(`extra`).
#[derive(Default)]
struct Extra { zone: f64, alt: f64, house: f64, item: f64, leader_name: f64, borrow: f64, office_more: f64, office_cells: f64, legit: f64 }

/// `put`의 `opt`(strips.mjs 144줄 `o = opt || {}`) — 없는 칸은 undefined(V::Undef).
#[derive(Default)]
struct Opt { alt: bool, seq: V, cell: V, base: V, now: V, house: V, item: V }

/// 트랙 하나를 도는 동안의 자리(`marks` · `put`이 닫아 쓰는 것).
struct Run<'a> { rc: &'a read::Ctx, track: usize, band_of: Map, extra: Extra }

impl Run<'_> {
    /// `marks(p, kind, lane, start, end, seq, c, base, now, house, item)`(strips.mjs 91 ~ 137줄) — 칸에 딸린 항목(구역 40 ~ 43 · 46).
    /// 자리는 칸의 구간이 아니라 제 구간이고, 단계(lod)는 그 칸과 같다(칸이 보이는 배율에서 함께 나온다). a = 칸의 종류 · b = 칸의 단 · ref = 그 칸이 든 띠의 uid.
    #[allow(clippy::too_many_arguments)]
    fn marks(&mut self, out: &mut Value, p: &V, kind: f64, lane: f64, start: f64, end: f64, seq: &V, c: &V, base: &V, now: &V, house: &V, item: &V) {
        let row = p.get("_row");
        let mut seed = json!({
            "section": 0, "track": self.track, "start": jv(start), "end": jv(end), "lod": jv(lod_of(end - start)), "ref": jsv(&p.get("uid")),
            "name": "", "color": 0, "a": jv(kind), "b": jv(lane), "c": 0, "d": 0, "text2": "",
        });
        // `row: p._row` — undefined면 JSON에서 열쇠가 빠진다
        if !row.is_undef() { seed["row"] = jsv(&row); seed["row2"] = jsv(&row); }
        let with = |fields: Value| -> Value {
            let mut x = seed.clone();
            if let (Some(o), Some(f)) = (x.as_object_mut(), fields.as_object()) { for (k, v) in f { o.insert(k.clone(), v.clone()); } }
            x
        };
        let nth = nth_of(seq);
        if tv(c) {
            // 구역 40 — 모호한 구간(연대 폭). 무늬는 전승이면 빗금, 그 밖(추정 · 통설 · 확실)이면 세로 줄(zoneKindOf).
            let look = if is(&c.get("certainty"), "legend") { 1 } else { 0 };
            for (side, range) in [c.get("startRange"), c.get("endRange")].into_iter().enumerate() {
                if !tv(&range) { continue; }
                let (r0, r1) = (range.get(&0.0), range.get(&1.0));
                let a = minute_v(&r0);
                let b = js::max(&[minute_num(&r0), minute_num(&r1)]); // `Math.max(a, minute(range[1]))` — null은 0
                arr_mut(out, "items").push(with(json!({ "section": jv(SECTION_ZONE), "start": a, "end": jv(b), "c": look, "d": side })));
                self.extra.zone += 1.0;
            }
            // 구역 41 — 이설이 말하는 경계(유령 구분선). start가 선의 자리이고 end는 칸의 끝이다(단계 셈과 타일 고르기에만).
            if tv(base) {
                for (y, side) in alt_edges(self.rc, &alts_of(c), base, now) {
                    let Some(at_) = minute_v(&y).as_i64() else { continue };
                    let at_ = at_ as f64;
                    arr_mut(out, "items").push(with(json!({ "section": jv(SECTION_ALT), "start": jv(at_), "end": jv(js::max(&[at_, end])), "c": if side == 'e' { 1 } else { 0 }, "d": jv(nth) })));
                    self.extra.alt += 1.0;
                }
            }
        }
        // 구역 42 — 이 칸의 가문(가문 강조 is-house). 칸의 style에는 가문의 이름을 담을 자리가 없어 일반 항목으로 싣는다.
        if tv(house) && house.bool("houseId") {
            arr_mut(out, "items").push(with(json!({ "section": jv(SECTION_HOUSE), "name": jsv(&or(house.get("houseName"), s(""))), "color": color(&house.get("houseColor"), 0), "c": jv(nth), "text2": jsv(&house.get("houseId")) })));
            self.extra.house += 1.0;
        }
        // 구역 43 — 이 칸이 가리키는 항목의 uid(왕조 · 기관 · 예속 안 칸). 누르면 열 상세 창을 찾는 값이다.
        if tv(item) && item.bool("uid") {
            arr_mut(out, "items").push(with(json!({ "section": jv(SECTION_ITEM), "name": jsv(&or(item.get("name"), s(""))), "color": color(&item.get("color"), 0), "c": jv(nth), "text2": jsv(&item.get("uid")) })));
            self.extra.item += 1.0;
        }
        // 구역 46 — 지도자 칸의 다른 표기(묘호 · 시호 · 이름 · 대수). 필터 시트의 '지도자 표기'와 '대수'가 쓴다.
        // 칸의 이름은 기본 표기(HT.leaderLabel(c, 'auto', false)) 하나뿐이라, 표기를 바꿀 글을 따로 싣는다.
        // `name` = 묘호 · `text2` = "시호\t이름"(항목의 글 밭이 둘뿐이라 탭으로 잇는다) · `c` = 그 칸의 순번 + 1 · `d` = 대수 + 1(0 = 대수 없음).
        if kind == strip::LEADER && tv(c) && (c.bool("temple") || c.bool("title") || c.bool("given") || !c.get("ordinal").is_nullish()) {
            let ordinal = c.get("ordinal");
            arr_mut(out, "items").push(with(json!({
                "section": jv(SECTION_LEADER_NAME),
                "name": jsv(&or(c.get("temple"), s(""))),
                "c": jv(nth),
                "d": if ordinal.is_nullish() { json!(0) } else { jsv(&js::add(&ordinal, &V::Num(1.0))) },
                "text2": format!("{}\t{}", t(&or(c.get("title"), s(""))), t(&or(c.get("given"), s("")))),
            })));
            self.extra.leader_name += 1.0;
        }
        // 구역 57 — 칸의 정통성(strips.mjs 162 ~ 168줄 · 4단계 배치 갈래 · 계약 1-1 덧붙임 · 감독 결정 LEGIT 가): 지도자 · 내각 · 직위 줄 더의 칸만(예속 안 칸의 c는 소속 줄이라 뺀다 — 그것은 구역 58).
        // `c` = 그 칸의 순번 + 1 · `d` = 정통성 번호 + 1(띠의 form 10 ~ 12와 같은 차례). status를 적지 않은 칸은 싣지 않는다.
        let legit = if (kind == strip::LEADER || kind == strip::CABINET || kind == KIND_OFFICE) && tv(c) { status_no_of(&c.get("status")) } else { 0 };
        if legit != 0 {
            arr_mut(out, "items").push(with(json!({ "section": jv(SECTION_LEGIT), "c": jv(nth), "d": legit })));
            self.extra.legit += 1.0;
        }
    }

    /// `put(p, kind, lane, s, e, name, style, col, opt)`(strips.mjs 139 ~ 148줄) — 칸 하나를 그 띠의 구간으로 잘라 싣고 딸린 항목을 단다. 실었으면 참.
    #[allow(clippy::too_many_arguments)]
    fn put(&mut self, out: &mut Value, p: &V, kind: f64, lane: f64, s_: &Value, e_: &Value, name: &V, style: i32, col: u32, o: Opt) -> crate::Result<bool> {
        let (Some(sv), Some(ev)) = (s_.as_i64(), e_.as_i64()) else { return Ok(false) };
        if !tv(name) { return Ok(false); }
        let (sv, ev) = (sv as f64, ev as f64);
        let (bs, be) = band_span(out, &self.band_of, &p.get("uid"))?;
        let start = js::max(&[sv, bs]);
        let end = js::max(&[start, js::min(&[ev, be])]);
        if sv > be || ev < bs { return Ok(false); }
        arr_mut(out, "cells").push(json!({
            "period": jsv(&p.get("uid")), "kind": jv(kind), "lane": jv(lane), "start": jv(start), "end": jv(end), "name": jsv(name),
            "style": style_with(style, o.alt, &o.seq), "color": if col != 0 { col } else { 0 },
        }));
        self.marks(out, p, kind, lane, start, end, &o.seq, &o.cell, &o.base, &o.now, &o.house, &o.item);
        Ok(true)
    }
}

/// `out.periods[bandOf.get(uid)]`의 (start, end) — 띠가 없으면 JS는 TypeError(오류로).
fn band_span(out: &Value, band_of: &Map, uid: &V) -> crate::Result<(f64, f64)> {
    let ix = band_of.get(uid);
    let band = match ix { V::Num(i) if i >= 0.0 && i.fract() == 0.0 => out["periods"].get(i as usize), _ => None };
    match band {
        Some(b) if b.is_object() => Ok((jn(&b["start"]), jn(&b["end"]))),
        _ => Err(format!("strips: 띠 {}의 out.periods 자리가 없습니다(JS라면 TypeError)", t(uid)).into()),
    }
}

/// `contribute(ctx, out)` — 트랙마다 띠 안의 단의 칸(왕조 · 지도자 · 내각 · 시기 · 지위 · 예속 안)과 기관 칸을 `out.cells`에, 딸린 것을 일반 항목으로 싣는다.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let band_of = match ctx.shared.get("bandOf") { V::Map(m) => m, _ => return Err("strips: ctx.shared.bandOf가 없습니다 — bands가 먼저 돌아야 합니다(JS라면 TypeError)".into()) };
    let (mut c_dyn, mut c_leader, mut c_cabinet, mut c_organ, mut c_phase, mut c_rank, mut c_dep) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    let (mut sk_no_host, mut sk_no_lane) = (0.0, 0.0);
    let mut extra = Extra::default();
    let (mut tier_bands, mut tier_cells, mut tier_over) = (0.0, 0.0, 0.0); // 지도자 두 단(4단계 배치 갈래 둘째): 두 단 이상인 띠 · 단 1 이상에 실은 지도자 칸 · 4단을 넘은 칸

    for (track_index, tr) in list(&tl.get("tracks")).iter().enumerate() {
        // `const trackRows = out.tracks[trackIndex].rows` — 트랙마다 먼저 읽는다(그 트랙이 out에 없으면 JS는 여기서 TypeError)
        if !out["tracks"].get(track_index).is_some_and(Value::is_object) {
            return Err(format!("strips: out.tracks[{track_index}]가 없습니다 — tracks가 먼저 돌아야 합니다(JS라면 TypeError)").into());
        }
        let mut run = Run { rc: &ctx.read, track: track_index, band_of: band_of.clone(), extra: std::mem::take(&mut extra) };
        let geo0 = tr.get("geo");
        let geo_of = |r: &V| or(at(&tr.get("geos"), r), tr.get("geo"));
        let periods = list(&tr.get("periods"));

        for p in &periods {
            if p.bool("_overlay") || !band_of.has(&p.get("uid")) { continue; }
            let geo = geo_of(&p.get("_row"));

            /* 왕조: 이 띠를 다스린 왕조마다 긴 둥근 칸 하나(_dynCells — 이어 붙이지 않고 왕조가 바뀌면 끊김), 제 색으로 */
            if geo0.bool("dynastyH") {
                for (i, d) in dyn_of(&tl, p).iter().enumerate() {
                    let y = d.get("dynasty");
                    let cell = dyn_cell_of(d, &y);
                    let opt = Opt {
                        seq: V::Num(i as f64), cell, base: V::Obj(o! { "start" => d.get("start"), "end" => d.get("end") }), now: p.get("endY"), house: y.clone(),
                        item: V::Obj(o! { "uid" => y.get("uid"), "name" => y.get("name"), "color" => y.get("color") }), ..Opt::default()
                    };
                    if run.put(out, p, strip::DYNASTY, 0.0, &minute_v(&d.get("start")), &minute_v(&d.get("end")), &or(y.get("name"), s("")), cell_style(d), color(&y.get("color"), 0), opt)? { c_dyn += 1.0; }
                }
            }
            /* 지도자 · 내각: 같은 왕조에서 이어지는 칸은 하나의 긴 둥근 칸(_cells의 layoutStrip 무리 열쇠 = 왕조).
               번갈아 짙기(is-alt)는 보이는 차례가 아니라 **원래 목록의 번호**로 정한다(명세 5-3의 6번) — lane 비트 18에 싣는다.
               지도자 칸의 lane = 그 칸의 단(4단계 배치 갈래 둘째 · 계약 1-1 덧붙임 — [`leader_lanes`] = tl._leaderLanes: 공동 · 주장 칸이 겹친 띠만 0 위 · 1 아래 …, 그 밖은 0 그대로).
               내각은 0 그대로다. 이음(joinL)은 같은 단의 바로 앞 칸으로 센다(단마다 prevKey). 칸에 딸린 구역 40 ~ 42 · 46 · 57의 b(marks의 seed)도 이 단을 따른다 */
            for (kind, l, h, rf) in [(strip::LEADER, p.get("leaders"), geo0.get("leaderH"), "leader"), (strip::CABINET, p.get("cabinets"), geo0.get("cabinetH"), "cabinet")] {
                if !tv(&h) || !tv(&l) || !l.bool("length") { continue; }
                let lanes = if kind == strip::LEADER { Some(leader_lanes(p)) } else { None };
                if let Some(ll) = lanes.as_ref().filter(|ll| ll.n > 1) {
                    tier_bands += 1.0;
                    tier_over += ll.over as f64;
                }
                let mut prev_key: Vec<Option<V>> = Vec::new(); // 단마다 바로 앞 칸의 무리 열쇠
                for (i, c) in list(&l).iter().enumerate() {
                    let lane = lanes.as_ref().map_or(0, |ll| ll.lane[i]);
                    let key = or(or(c.get("dynasty"), c.get("dynastyAuto")), s(""));
                    let name = if kind == strip::LEADER { leader_label(c) } else { c.get("name") };
                    let borrowed = tv(&(if kind == strip::LEADER { p.get("leadersFrom") } else { p.get("cabinetsFrom") }));
                    let joined = prev_key.get(lane).and_then(Option::as_ref).is_some_and(|pk| !pk.is_undef() && eq(pk, &key));
                    let style = cell_style(c) | (if joined { st::JOIN_L } else { 0 }) | (if borrowed { ST_BORROW } else { 0 });
                    let opt = Opt { alt: i % 2 == 1, seq: V::Num(i as f64), cell: c.clone(), base: cell_base_of(&ctx.read, c, p, format!("{rf}:{i}")), now: p.get("endY"), house: c.clone(), ..Opt::default() };
                    if run.put(out, p, kind, lane as f64, &minute_v(&c.get("start")), &minute_v(&nn(c.get("end"), p.get("endY"))), &name, style, 0, opt)? {
                        if kind == strip::LEADER { c_leader += 1.0; } else { c_cabinet += 1.0; }
                        if lane > 0 { tier_cells += 1.0; }
                    }
                    if prev_key.len() <= lane { prev_key.resize(lane + 1, None); }
                    prev_key[lane] = Some(key);
                }
            }
            /* 리메이크 3단계(계약 1-1 초안 — strips.mjs 200 ~ 228줄) — 빌린 직위 줄의 머리 글(구역 54)과 직위 줄 더(칸 종류 9 · 줄 이름 구역 55).
               칸 층 셈 · 줄 높이에는 넣지 않는다(4단계가 그릴 때 정함) — 있는 값은 그대로다. */
            {
                let band = match band_of.get(&p.get("uid")) { V::Num(i) if i >= 0.0 && i.fract() == 0.0 => out["periods"].get(i as usize).cloned(), _ => None };
                let Some(band) = band.filter(Value::is_object) else { return Err(format!("strips: 띠 {}의 out.periods 자리가 없습니다(JS라면 TypeError)", t(&p.get("uid"))).into()) };
                let head = |out: &mut Value, section: f64, a: f64, b: f64, name: Value, text2: Value| {
                    arr_mut(out, "items").push(json!({
                        "section": jv(section), "track": track_index, "row": band["row"].clone(), "row2": band["row"].clone(), "start": band["start"].clone(), "end": band["end"].clone(),
                        "lod": -1, "ref": jsv(&p.get("uid")), "name": name, "color": 0, "a": jv(a), "b": jv(b), "c": 0, "d": 0, "text2": text2,
                    }));
                };
                let src_uid = |f: &FromOf| if tv(&f.src) { jsv(&f.src.get("uid")) } else { json!("") };
                for (kind, v) in [(strip::LEADER, p.get("leadersFrom")), (strip::CABINET, p.get("cabinetsFrom"))] {
                    if !tv(&v) || !tv(&v.get("from")) { continue; }
                    let f = from_of(&ctx.model, p, &v.get("from"));
                    head(out, SECTION_BORROW, kind, 0.0, json!(f.text), src_uid(&f));
                    run.extra.borrow += 1.0;
                }
                for (lane, o_) in js_list(&p.get("offices"), "정권의 offices")?.iter().enumerate() {
                    // `if (!o || typeof o !== 'object') return` — 배열 · Map도 객체(이름 · 칸이 없어 빈 줄이 됨)
                    if !tv(o_) || matches!(o_, V::Bool(_) | V::Num(_) | V::Str(_)) { continue; }
                    let from = o_.get("from");
                    let f = if tv(&from) { Some(from_of(&ctx.model, p, &from)) } else { None };
                    let cells = match &f { Some(f) => office_cells(&f.src, &f.office)?, None => js_list(&o_.get("cells"), "직위 줄의 cells")? };
                    // `o.name || (f && f.office) || ''`
                    let nm = o_.get("name");
                    let name = if tv(&nm) { jsv(&nm) } else { match &f { Some(f) if !f.office.is_empty() => json!(f.office.as_str()), _ => json!("") } };
                    head(out, SECTION_OFFICE_NAME, KIND_OFFICE, lane as f64, name, json!(""));
                    run.extra.office_more += 1.0;
                    if let Some(f) = &f {
                        head(out, SECTION_BORROW, KIND_OFFICE, lane as f64, json!(f.text), src_uid(f));
                        run.extra.borrow += 1.0;
                    }
                    for (i, c) in cells.iter().enumerate() {
                        // `HT.leaderLabel(c, 'auto', false) || c.name || ''` — 칸이 null · undefined면 JS는 `c.name`에서 TypeError
                        if c.is_nullish() { return Err(format!("strips: 직위 줄 {}의 칸 {i}이(가) 비었습니다(JS라면 TypeError)", t(&o_.get("name"))).into()); }
                        let label = leader_label(c);
                        let name = if tv(&label) { label } else { or(c.get("name"), s("")) };
                        let style = cell_style(c) | (if f.is_some() { ST_BORROW } else { 0 });
                        let opt = Opt { alt: i % 2 == 1, seq: V::Num(i as f64), cell: c.clone(), base: V::Null, now: p.get("endY"), house: c.clone(), ..Opt::default() };
                        if run.put(out, p, KIND_OFFICE, lane as f64, &minute_v(&c.get("start")), &minute_v(&nn(c.get("end"), p.get("endY"))), &name, style, 0, opt)? { run.extra.office_cells += 1.0; }
                    }
                }
            }
            /* 시기 구분(학계): 체계마다 얇은 한 줄(lane) — 체계가 둘 이상이면 이름 앞에 체계 이름을 탭 문자로 붙여 둔다(계약 6절) */
            let schemes = p.get("phaseSchemes");
            if geo.bool("phaseH") && tv(&schemes) {
                let all = list(&schemes);
                let multi = n(&schemes.get("length")) > 1.0;
                // `slice(0, Math.round(geo.phaseH / 15) || 3)`
                let k = { let r = js::round(n(&geo.get("phaseH")) / 15.0); if r == 0.0 || r.is_nan() { 3.0 } else { r } };
                let len = all.len() as f64;
                let upto = if k < 0.0 { js::max(&[len + k, 0.0]) } else { js::min(&[k, len]) } as usize;
                for (lane, sc) in all[..upto].iter().enumerate() {
                    let mut first = true;
                    for c in list(&sc.get("spans")) {
                        let tagged = multi && sc.bool("scheme");
                        let name = if tagged { V::from(format!("{}\t{}", t(&sc.get("scheme")), t(&c.get("name")))) } else { c.get("name") };
                        let style = cell_style(&c) | (if tagged { st::TAGGED } else { 0 }) | (if first { 0 } else { st::JOIN_L });
                        let opt = Opt { seq: c.get("ci"), cell: c.clone(), base: cell_base_of(&ctx.read, &c, p, format!("phase:{}", t(&c.get("ci")))), now: p.get("endY"), ..Opt::default() };
                        if run.put(out, p, strip::PHASE, lane as f64, &minute_v(&c.get("start")), &minute_v(&c.get("end")), &name, style, 0, opt)? { c_phase += 1.0; }
                        first = false;
                    }
                }
            }
            /* 지위: 서열이 높을수록 나라 색이 짙게 — 짙기는 그리는 쪽이 단계로 섞으므로 단계만 싣는다(계약 6절) */
            let rank_spans = p.get("rankSpans");
            if geo.bool("rankH") && tv(&rank_spans) {
                let mut first = true;
                for c in list(&rank_spans) {
                    let level = js::to_i32(js::min(&[7.0, n(&js::add(&or(c.get("level"), V::Num(0.0)), &V::Num(1.0)))]));
                    let style = cell_style(&c) | (if first { 0 } else { st::JOIN_L }) | (level << st::RANK);
                    let opt = Opt { seq: c.get("i"), cell: c.clone(), base: cell_base_of(&ctx.read, &c, p, format!("rank:{}", t(&c.get("i")))), now: p.get("endY"), ..Opt::default() };
                    if run.put(out, p, strip::RANK, 0.0, &minute_v(&c.get("start")), &minute_v(&c.get("end")), &or(c.get("name"), s("")), style, 0, opt)? { c_rank += 1.0; }
                    first = false;
                }
            }
            /* 예속(안) 칸: 상국 띠 안 맨 아래 — 상국이 다스린 속국(괴뢰 · 위임 · 식민 · 점령)의 이름표. lane 0이 띠 아랫변에 가장 가깝다 */
            let dep = p.get("_dep");
            if geo.bool("depH") && tv(&dep) && dep.bool("inLanes") {
                for it in list(&dep.get("items")) {
                    if !it.bool("inn") { continue; }
                    let mut first = true;
                    let ip = it.get("p");
                    for sg in list(&it.get("segs")).into_iter().filter(|x| is(&x.get("side"), "in")) {
                        let h = sg.get("h");
                        let style = cell_style(&h) | (if first { 0 } else { st::JOIN_L }) | (js::to_i32(js::min(&[7.0, dep_look_no(&sg.get("look"))])) << st::DEP);
                        let opt = Opt {
                            seq: V::Num(index_of(&list(&or(ip.get("hosts"), arr(Vec::new()))), &h)), cell: h.clone(),
                            base: V::Obj(o! { "start" => sg.get("a"), "end" => sg.get("b"), "startUnknown" => h.get("startUnknown"), "endUnknown" => h.get("endUnknown") }),
                            now: ip.get("endY"), item: V::Obj(o! { "uid" => ip.get("uid"), "name" => ip.get("name"), "color" => ip.get("color") }), ..Opt::default()
                        };
                        let lane = n(&or(it.get("inLane"), V::Num(0.0)));
                        if run.put(out, p, strip::DEP, lane, &minute_v(&sg.get("a")), &minute_v(&sg.get("b")), &or(ip.get("name"), s("")), style, color(&ip.get("color"), 0xa4b1b7), opt)? { c_dep += 1.0; }
                        first = false;
                    }
                }
            }
        }

        /* 기관(얹히는 조직 — 구역 탭은 hangs.mjs의 몫): 제 줄 없이 주인 띠의 기관 단에. 겹치면 단(lane)을 나눈다 — 2단계처럼 빼지 않는다 */
        let organ_lanes = Map::new(); // 주인 띠 uid → 단마다의 마지막 끝
        let organ_seq = Map::new(); // 주인 띠 uid → 그 띠에 실은 기관 칸의 수(칸 참조 'organ:n'의 번호 — 상세 창이 구역 43의 uid로 연다)
        let mut organs: Vec<V> = periods.iter().filter(|q| q.bool("_overlay") && !is(&q.get("scale"), "zone")).cloned().collect();
        js::sort(&mut organs, |a, b| or_cmp(sub(&a.get("start"), &b.get("start")), || sub(&a.get("endY"), &b.get("endY"))));
        for p in &organs {
            for h in list(&or(p.get("hosts"), arr(Vec::new()))) {
                let huid = h.get("host").get("uid");
                let mut host = periods.iter().find(|q| eq(&q.get("uid"), &huid)).cloned().unwrap_or(V::Null);
                while tv(&host) && host.bool("_hidden") { host = host.get("_host"); }
                if !tv(&host) || !band_of.has(&host.get("uid")) { sk_no_host += 1.0; continue; }
                let (bs, be) = band_span(out, &band_of, &host.get("uid"))?;
                let band_row = jn(&out["periods"][n(&band_of.get(&host.get("uid"))) as usize]["row"]);
                let row_v = out["tracks"].get(track_index).and_then(|tv_| tv_["rows"].get(band_row as usize));
                let Some(row_v) = row_v else { return Err(format!("strips: 트랙 {track_index}의 줄 {}이 out.tracks에 없습니다(JS라면 TypeError)", js::num_str(band_row)).into()) };
                if jn(&row_v["organTop"]) < 0.0 { sk_no_lane += 1.0; continue; }
                let s_ = js::max(&[minute_num(&V::Num(js::max(&[n(&p.get("start")), n(&nn(h.get("start"), V::Num(f64::NEG_INFINITY)))]))), bs]);
                let e_ = js::min(&[minute_num(&V::Num(js::min(&[n(&p.get("endY")), n(&nn(h.get("end"), V::Num(f64::INFINITY)))]))), be]);
                if e_ < s_ { continue; }
                let ends = match organ_lanes.get(&host.get("uid")) { V::Arr(a) => a, _ => Arr::default() };
                let found = ends.to_vec().iter().position(|end| n(end) < s_);
                let lane = match found { Some(i) => i, None => { ends.push(f64::NEG_INFINITY); ends.len() - 1 } };
                ends.set(lane, e_);
                organ_lanes.set(host.get("uid"), ends);
                let seq = or(organ_seq.get(&host.get("uid")), V::Num(0.0));
                organ_seq.set(host.get("uid"), js::add(&seq, &V::Num(1.0)));
                arr_mut(out, "cells").push(json!({
                    "period": jsv(&host.get("uid")), "kind": jv(strip::ORGAN), "lane": lane, "start": jv(s_), "end": jv(e_), "name": jsv(&or(p.get("name"), s(""))),
                    "style": style_with(cell_style(p), false, &seq), "color": color(&p.get("color"), 0xa4b1b7),
                }));
                // 기관 칸은 제 항목의 이설만 그린다(모호한 구간은 그리지 않는다 — 지금 연표의 oc가 alternatives만 담는다).
                let alts = dated_alts(p);
                let cell = if alts.is_empty() { V::Null } else { V::Obj(o! { "alternatives" => arr(alts) }) };
                let base = V::Obj(o! {
                    "start" => p.get("start"), "startAt" => p.get("startAt"), "end" => p.get("endY"), "endAt" => p.get("endAt"),
                    "startUnknown" => p.get("startUnknown"), "endUnknown" => p.get("endUnknown"), "ongoing" => p.get("ongoing"),
                });
                let item = V::Obj(o! { "uid" => p.get("uid"), "name" => p.get("name"), "color" => p.get("color") });
                run.marks(out, &host, strip::ORGAN, lane as f64, s_, e_, &seq, &cell, &base, &p.get("endY"), &V::Null, &item);
                c_organ += 1.0;
            }
        }
        extra = run.extra;
    }
    ctx.notes.set("칸", o! { "왕조" => c_dyn, "지도자" => c_leader, "내각" => c_cabinet, "기관" => c_organ, "시기" => c_phase, "지위" => c_rank, "예속안" => c_dep });
    ctx.notes.set("칸에_딸린_것", o! { "모호한구간" => extra.zone, "이설경계" => extra.alt, "가문" => extra.house, "가리키는항목" => extra.item, "지도자표기" => extra.leader_name,
        "빌린줄" => extra.borrow, "직위줄더" => extra.office_more, "직위줄더칸" => extra.office_cells, "칸정통성" => extra.legit });
    ctx.notes.set("칸에서_뺀_것", o! { "기관_주인없음" => sk_no_host, "기관_단없음" => sk_no_lane });
    ctx.notes.set("지도자_두단", o! { "띠" => tier_bands, "칸" => tier_cells, "넘침" => tier_over });
    Ok(())
}

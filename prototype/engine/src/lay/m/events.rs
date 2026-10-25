//! 내보내기 모듈 `events` — `prototype/scripts/export/events.mjs`(1 ~ 118줄 · SHA-256 앞 12자 `13bdbbb6874f` — 저장소의 LF 바이트)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 5).
//! 사건. 2단계의 값에서 출발한다 — 분류 · 모양 · 확실성 · 글줄 · 이름 옆 날짜 글 · 기간 막대의 단(계약 4 · 6절의 look · label · rail)은 이 모듈이 더한다.
//!
//! `rails.mjs`의 `railLevels` · `onRail` · `eventColor` · `eventUid`(→ [`super::rails`])를 가져오고 `shared.catNo` · `bandOf`를 읽으며 `shared.railLevel` · `railRank`를 **처음 쓴다**
//! (catNo가 없으면 `out.categories`에서 만든다). 부르는 웹 함수: `tl._placeAt`(→ [`place_at`]) · `HT.atOf`(→ [`at_of`]) · `HT.cal.parse`(→ [`cal::parse`]) · `HT.datedAlts`(있음) ·
//! `HT.formatYear`(→ `read::dates::format_year`) · `cal.formatT`(→ [`crate::lay::web::when::format_t`]) — 과제 Y가 모음: 처음엔 이 파일에 `HT.yearOf` · `HT.formatYear`의
//! 'JS 값 그대로' 판(이제 `read::dates`의 하나)과 `yearText` · `clock` · `cal.formatT`가 있었다.
//!
//! JS라면 던졌을 곳(사건의 줄이 없음 · 사건 수가 모델과 다름 — Node의 assert · `catNo` · `bandOf` · `eventByUid`가 Map이 아님)은 오류로 돌려준다.
use super::kit::minute_val;
use super::rails::{event_color, event_uid, on_rail, push_item, rail_levels, shl};
use crate::lay::cal;
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_len, arr_mut, color as rgb, js_text, jsv};
use crate::lay::js::{self, Map, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, at_of, dated_alts, eq, index_of, le, list, lt, n, nn, or, t, tv};
use crate::lay::read::dates::format_year;
use crate::lay::rows::place_at;
use crate::lay::web::when::format_t;
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// look의 비트 자리 (계약 6절의 표와 같다).
struct Look { cat: u32, lane: u32, treaty: u32, shared: u32, pair: u32, child: u32, estimated: u32, legend: u32, unknown: u32, fuzzy: u32, kids: u32 }
const LOOK: Look = Look { cat: 0, lane: 8, treaty: 16, shared: 17, pair: 18, child: 19, estimated: 20, legend: 21, unknown: 22, fuzzy: 23, kids: 24 };
/// rail의 비트 자리.
struct Rail { level: u32, ranged: u32, fuzz_s: u32, fuzz_e: u32, alt: u32, alt_end: u32, effect: u32, prec: u32 }
const RAIL: Rail = Rail { level: 0, ranged: 2, fuzz_s: 3, fuzz_e: 4, alt: 5, alt_end: 6, effect: 7, prec: 8 };
/// 날짜 정밀도 — 적은 만큼만(연도만 적은 사건에 없는 날짜를 지어내지 않는다). c · c2 · c3 = 세기 · 반세기 · 세기의 셋째(묶음 5 · 6번) — rail 8~10비트(3비트) 안.
fn prec_no(p: &str) -> Option<f64> {
    Some(match p { "y" => 0.0, "m" => 1.0, "d" => 2.0, "x" => 2.0, "h" => 3.0, "min" => 4.0, "c" => 5.0, "c2" => 6.0, "c3" => 7.0, _ => return None })
}
const PREC_Y: f64 = 0.0;
const PREC_D: f64 = 2.0;
const PREC_C: f64 = 5.0;
/// 하위 사건이 펼쳐지는 문턱(_drawTrack): 부모의 폭 90px 이상 · 한 번 펼쳐지면 8% 더 좁아져야 다시 접힌다.
const WIDE: f64 = 90.0;
const WIDE_GAP: f64 = 80.0; // 0.08을 천분율로

// ── events.mjs ──

/// 사건의 분류 번호 = out.categories의 순번. 앞선 모듈(tracks.mjs)이 채워 둔 ctx.shared.catNo를 그대로 쓰고, 없으면 지금 연표의 분류 차례로 채운다.
fn cat_index(ctx: &mut Ctx, out: &mut Value) -> crate::Result<Map> {
    let have = ctx.shared.get("catNo");
    if tv(&have) {
        return match have { V::Map(m) => Ok(m), other => Err(format!("shared.catNo가 Map이 아닙니다({}) — JS라면 .has에서 멈춤", js::type_of(&other)).into()) };
    }
    if arr_len(out, "categories") == 0 {
        let V::Map(cats) = ctx.tl.get("_cats") else { return Err("tl._cats가 Map이 아닙니다 — JS라면 .entries()에서 멈춤".into()) };
        let mut entries = cats.entries();
        js::sort_by(&mut entries, |a, b| n(&a.1.get("i")) - n(&b.1.get("i")));
        for (id, c) in entries {
            arr_mut(out, "categories").push(json!({ "key": jsv(&id), "name": jsv(&or(c.get("name"), id.clone())), "color": rgb(&c.get("color"), 0xa4b1b7) }));
        }
    }
    let m = Map::new();
    for (i, c) in out["categories"].as_array().map(Vec::as_slice).unwrap_or(&[]).iter().enumerate() {
        m.set(c.get("key").map_or(V::Undef, js::from_json), i as f64);
    }
    ctx.shared.set("catNo", m.clone());
    Ok(m)
}

/// 이름 옆 날짜 글 — _labelDate를 화면 없이 그대로: 적은 정밀도만큼의 온 글(해 눈금 · 같은 해 보기에서 줄이는 것은 그리는 쪽이 한다. 계약 6절).
fn label_of(ctx: &Ctx, e: &V) -> (V, f64) {
    let at = at_of(&ctx.read, e, "start");
    let r = if tv(&at) { cal::parse(&ctx.read.cal, &at) } else { None };
    let r = match r { Some(r) if r.ok && r.prec != "y" => r, _ => return (V::from(format_year(&e.get("start"))), PREC_Y) };
    if r.span.is_some() { return (V::Str(r.text.clone()), prec_no(r.prec).unwrap_or(PREC_C)); } // 세기로 적은 연대는 적은 글 그대로
    let prec = if r.prec == "m" { "m" } else if r.prec == "d" { "d" } else { r.prec };
    (V::from(format_t(r.t, prec)), prec_no(prec).unwrap_or(PREC_D))
}

/// `contribute(ctx, out)` — 사건마다 `out.events` 한 줄과, 하위 사건이면 구역 32.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let period_by_uid = Map::new();
    for p in list(&ctx.model.get("periods")) { period_by_uid.set(p.get("uid"), p.clone()); }
    let (tl, model) = (ctx.tl.clone(), ctx.model.clone());
    let cats = cat_index(ctx, out)?;
    let levels = rail_levels(ctx)?;
    let band_uid_of = |ctx: &Ctx, e: &V| -> crate::Result<V> {
        let place = e.get("_place");
        let uid = if tv(&place) { place.get("polityUid") } else { e.get("polityUid") };
        let mut p = if !uid.is_nullish() { period_by_uid.get(&uid) } else { V::Null };
        while tv(&p) && p.bool("_hidden") { p = p.get("_host"); }
        if !tv(&p) { return Ok(V::from("")); }
        let band_of = ctx.shared.get("bandOf");
        if !tv(&band_of) { return Ok(V::from("")); }
        let V::Map(bo) = band_of else { return Err("shared.bandOf가 Map이 아닙니다 — JS라면 .has에서 멈춤".into()) };
        Ok(if bo.has(&p.get("uid")) { p.get("uid") } else { V::from("") })
    };
    let (mut c_bundle, mut c_child, mut c_free, mut c_lane) = (0.0, 0.0, 0.0, 0.0);
    let mut shelved = 0usize; // 줄 null = 선반 변형이 숨긴 띠의 사건(지금 연표 `_layoutTrack` 3 — 내보내기 선반 변형의 다시 셈에서만) — 싣지 않는다(variants가 이사 −1로)
    for (track_index, tr) in list(&tl.get("tracks")).iter().enumerate() {
        for e in list(&tr.get("events")) {
            if e.get("_row").is_null() { if !t(&event_uid(&e)).contains('#') { shelved += 1; } continue; }
            let er = e.get("_row");
            let row = if er.is_nullish() || lt(&er, &V::Num(0.0)) { tr.get("commonRow") } else { er };
            if !(le(&V::Num(0.0), &row) && lt(&row, &tr.get("rows"))) { return Err(format!("사건의 줄이 없습니다: {}", t(&e.get("title"))).into()); }
            // 날짜를 정확히 모르는 점 사건은 그 구간 가운데(또는 사건의 자리 spot)에 하나로 선다 — 연표의 _placeAt과 같은 해를 시작 분으로 싣는다
            // (2026-10-14 감독 결정 · 날짜 글과 정밀도는 label · rail이 따로 나르고, 놓인 자리는 늘 그 구간 안이라 같은 해 보기 · 칸의 목록은 그대로).
            let end_or_start = nn(e.get("endY"), e.get("start"));
            let place = if lt(&e.get("start"), &end_or_start) { e.get("start") } else { place_at(ctx, &e) };
            let (start, end) = (minute_val(&place), minute_val(&end_or_start));
            let uid = event_uid(&e);
            let cert = or(e.get("certainty"), V::from("accepted"));
            let fuzzy = e.bool("startRange") || e.bool("endRange"); // 연대 폭이 있으면 화면이 확실성 딱지를 끄고 빗금 구간으로 말한다
            let rc = tr.get("rowCats");
            let row_cats = or(if tv(&rc) { rc.get(&n(&row)) } else { rc }, V::Null);
            let category = or(e.get("category"), V::from("etc"));
            let lane = if tv(&row_cats) { index_of(&list(&row_cats), &category) } else { -1.0 };
            if tv(&row_cats) { if lane >= 0.0 { c_lane += 1.0 } else { c_free += 1.0 } }
            let children = e.get("children");
            let kids = if tv(&children) && tv(&children.get("length")) { n(&children.get("length")) } else { 0.0 };
            let (label_text, label_prec) = label_of(ctx, &e);
            let alts = dated_alts(&e);
            let alt_end = alts.iter().any(|a| {
                let ae = a.get("end");
                !ae.is_nullish() && n(&ae).is_finite() && !a.bool("ongoing") && (n(&ae) - n(&nn(e.get("end"), e.get("endY")))).abs() > 1e-9
            });
            let treaty = e.get("treaty");
            let eff = if tv(&treaty) { treaty.get("effective") } else { treaty.clone() };
            let one = |b: bool| -> f64 { if b { 1.0 } else { 0.0 } };

            let look = shl(if cats.has(&category) { n(&cats.get(&category)) } else { 255.0 }, LOOK.cat)
                | shl(if lane >= 0.0 && lane < 255.0 { lane } else { 255.0 }, LOOK.lane)
                | shl(one(tv(&treaty)), LOOK.treaty)
                | shl(one(e.bool("shared")), LOOK.shared)
                | shl(one(e.bool("_sec")), LOOK.pair)
                | shl(one(e.bool("parentUid")), LOOK.child)
                | shl(one(!fuzzy && eq(&cert, &V::from("estimated"))), LOOK.estimated)
                | shl(one(!fuzzy && eq(&cert, &V::from("legend"))), LOOK.legend)
                | shl(one(e.bool("startUnknown") || e.bool("endUnknown")), LOOK.unknown)
                | shl(one(fuzzy), LOOK.fuzzy)
                | shl(js::min(&[255.0, kids]), LOOK.kids);
            let rail = shl(n(&nn(levels.get(&uid), V::Num(0.0))), RAIL.level)
                | shl(one(on_rail(&e)), RAIL.ranged)
                | shl(one(e.bool("startRange")), RAIL.fuzz_s)
                | shl(one(e.bool("endRange")), RAIL.fuzz_e)
                | shl(one(!alts.is_empty()), RAIL.alt)
                | shl(one(alt_end), RAIL.alt_end)
                | shl(one(!eff.is_nullish() && n(&eff).is_finite() && (n(&eff) - n(&e.get("start"))).abs() > 1e-6), RAIL.effect)
                | shl(label_prec, RAIL.prec);

            let end_v = if start.is_nullish() { V::Null } else { V::Num(js::max(&[n(&nn(end.clone(), start.clone())), n(&start)])) };
            let band = band_uid_of(&*ctx, &e)?;
            let ev = o! {
                "uid" => uid.clone(), "track" => track_index as f64, "row" => row.clone(), "start" => start.clone(), "end" => end_v,
                "importance" => js::min(&[3.0, js::max(&[1.0, n(&or(e.get("importance"), V::Num(1.0)))])]),
                "title" => nn(nn(e.get("title"), e.get("name")), V::from("")), "body" => nn(e.get("description"), V::from("")),
                "look" => f64::from(look as u32), "label" => label_text, "rail" => f64::from(rail as u32),
                // 사건이 든 띠(정권)의 uid — 점의 색(정권 색) · 점과 이름을 띠 안에 가두기 · '묶음은 같은 띠 안에서만'에 쓴다. 띠가 없으면(그 밖 줄) ''.
                "band" => band,
            };
            arr_mut(out, "events").push(js::to_json(&V::Obj(ev)));

            // 구역 32 · 하위 사건: 평소에는 숨고 부모가 화면에서 넓어지면 펼쳐진다. 자리(start · end)는 **부모의 기간**이라
            // 그리는 쪽이 x1 − x0 ≥ 90px인지만 보면 되고, 단계(lod −1)도 부모의 기간에서 셈해 부모가 가늘 때는 실리지 않는다.
            if e.bool("parentUid") {
                let pu = e.get("parentUid");
                let by_uid = tr.get("eventByUid");
                let V::Map(by_uid) = by_uid else { return Err("tr.eventByUid가 Map이 아닙니다 — JS라면 .get에서 멈춤".into()) };
                let mut parent = by_uid.get(&pu);
                if !tv(&parent) { parent = list(&or(model.get("events"), arr(Vec::new()))).into_iter().find(|q| eq(&q.get("uid"), &pu)).unwrap_or(V::Undef); }
                if tv(&parent) {
                    let ps = minute_val(&parent.get("start"));
                    let pe = js::max(&[n(&ps), n(&minute_val(&nn(parent.get("endY"), parent.get("start"))))]);
                    push_item(out, &o! {
                        "section" => 32.0, "track" => track_index as f64, "row" => row.clone(), "row2" => row.clone(), "start" => ps, "end" => pe, "lod" => -1.0,
                        "ref" => uid.clone(), "name" => parent.get("uid"), "color" => f64::from(rgb(&event_color(&parent), 0xa4b1b7)),
                        "a" => js::min(&[255.0, n(&or(parent.get("children"), arr(Vec::new())).get("length"))]), "b" => WIDE, "c" => WIDE_GAP, "d" => 0.0, "text2" => or(parent.get("title"), V::from("")),
                    });
                    c_child += 1.0;
                }
            }
            if kids != 0.0 && !kids.is_nan() { c_bundle += 1.0; }
        }
    }
    let plain = out["events"].as_array().map_or(0, |l| l.iter().filter(|e| !js_text(&e["uid"]).contains('#')).count());
    let model_n = n(&model.get("events").get("length"));
    if (plain + shelved) as f64 != model_n { return Err(format!("사건 수가 모델과 다릅니다: {} ≠ {}", plain + shelved, js::num_str(model_n)).into()); }
    ctx.notes.set("사건", o! { "묶음사건" => c_bundle, "하위사건" => c_child, "자유배치" => c_free, "분류별글줄" => c_lane });
    Ok(())
}

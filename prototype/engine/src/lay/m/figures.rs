//! 내보내기 모듈 `figures` — `prototype/scripts/export/figures.mjs`(1 ~ 132줄 · SHA-256 앞 12자 `cd6b411d137c` — 저장소의 LF 바이트)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 7).
//! 인물의 활동 막대(계약 4절의 items · 6절의 구역 37 · 38 · 39). 줄(row)과 단(lvl)은 이미 자료로 정해져 있다(_layoutTrack이 tr.figures에 적어 둔 것).
//!
//! `rails.mjs`의 `lodOf`(→ [`lod_of`])를 가져오고 `shared.bandOf`를 읽는다(없으면 빈 Map). 모듈의 `bandStart` · `bandEnd`는 `lay::rows`의 것(timeline.js와 같은 식).
//! 부르는 웹 함수: `HT.altFlipped`(→ [`crate::lay::web::alts`] — 과제 Y가 모음 · 처음 옮긴 판은 이 파일에 있었다) · 모듈의 `altEdges`도 그 파일의 하나(strips · hangs와 같은 몸).
use super::kit::{has_or_err, lod_of, minute_val};
use super::rails::{assign, push_item, shl};
use crate::lay::web::alts::{alt_edges, alt_flipped};
use crate::lay::ctx::Ctx;
use crate::lay::export::color as rgb;
use crate::lay::js::{self, Map, Obj, V};
use crate::lay::model::o;
use crate::lay::model::util::{eq, has, list, lt, n, or, t, tv};
use crate::lay::read::Ctx as ReadCtx;
use crate::lay::rows::{band_end, band_start, items};
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

pub struct Section { pub bar: f64, pub group: f64, pub alt: f64 }
pub const SECTION: Section = Section { bar: 37.0, group: 38.0, alt: 39.0 };

// ── figures.mjs ──

/// 활동 막대의 양 끝이 미정인지 — 막대의 그 끝이 섬긴 구간의 진짜 끝일 때만(띠의 기간에서 잘린 끝은 미정이 아니다. _figUnk와 같다).
fn unknown_ends(s: &V, host: &V) -> (bool, bool) {
    (
        s.bool("fromUnknown") && (js::max(&[n(&s.get("start")), n(&band_start(host))]) - n(&s.get("from"))).abs() < 1e-9,
        s.bool("toUnknown") && (js::min(&[n(&s.get("endY")), n(&band_end(host))]) - n(&s.get("to"))).abs() < 1e-9,
    )
}

/// 인물의 생몰 · 활동 시기(js/timeline.js의 figBaseOf). 앞뒤가 뒤집힌 이설을 가리는 데 쓴다.
fn fig_base(f: &V) -> V {
    V::Obj(o! {
        "birth" => f.get("birth"), "birthAt" => f.get("birthAt"), "death" => f.get("death"), "deathAt" => f.get("deathAt"), "start" => f.get("start"), "startAt" => f.get("startAt"),
        "end" => f.get("endY"), "endAt" => f.get("endYAt"), "ongoing" => f.get("ongoing"), "startUnknown" => f.get("startUnknown"), "endUnknown" => f.get("endUnknown"),
    })
}
const FIG_KEYS: [&str; 4] = ["start", "end", "birth", "death"];

/// 활동 막대 하나가 품는 이설(js/timeline.js의 figBarCell): 섬긴 기록 줄의 이설에, 이 막대의 끝이 곧 활동의 끝일 때만 인물의 활동 시작 · 끝 이설을 더한다.
fn bar_alternatives(rc: &ReadCtx, f: &V, s: &V) -> Vec<V> {
    let mut out = items(&if tv(s) { s.get("alternatives") } else { s.clone() });
    let at_s = (n(&s.get("from")) - n(&f.get("start"))).abs() < 1e-9;
    let at_e = (n(&s.get("to")) - n(&f.get("endY"))).abs() < 1e-9;
    for a in items(&f.get("alternatives")) {
        if alt_flipped(rc, &a, &fig_base(f), &FIG_KEYS) { continue; }
        let o = Obj::new();
        if at_s && !a.get("start").is_nullish() { o.set("start", a.get("start")); o.set("startAt", a.get("startAt")); }
        if at_e && matches!(a.get("ongoing"), V::Bool(true)) { o.set("ongoing", true); }
        else if at_e && !a.get("end").is_nullish() { o.set("end", a.get("end")); o.set("endAt", a.get("endAt")); }
        if !o.is_empty() { o.set("label", a.get("label")); out.push(V::Obj(o)); }
    }
    out
}

/// 인물의 생몰 이설이 말하는 해(수명선 위의 작은 빈 고리 `.lnalt`) — 앞뒤가 뒤집힌 이설과 실제 생몰과 같은 해는 뺀다.
fn life_edges(rc: &ReadCtx, f: &V) -> Vec<V> {
    let mut out: Vec<V> = Vec::new();
    for a in items(&f.get("alternatives")) {
        if alt_flipped(rc, &a, &fig_base(f), &FIG_KEYS) { continue; }
        for y in [a.get("birth"), a.get("death")] {
            if y.is_nullish() || !n(&y).is_finite() || eq(&y, &f.get("birth")) || eq(&y, &f.get("death")) || has(&out, &y) { continue; }
            out.push(y);
        }
    }
    out
}

/// `contribute(ctx, out)` — 인물의 활동 막대(구역 37) · 이설 경계와 생몰 이설(39) · 띠마다의 인물 단 묶음(38).
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let band_of = { let b = ctx.shared.get("bandOf"); if tv(&b) { b } else { V::Map(Map::new()) } };
    let has_band = |uid: &V| -> crate::Result<bool> { match &band_of { V::Map(m) => Ok(m.has(uid)), _ => Err("shared.bandOf가 Map이 아닙니다 — JS라면 .has에서 멈춤".into()) } };
    let rc = &ctx.read;
    let (mut c_bar, mut c_group, mut c_over, mut c_life, mut c_edge, mut c_life_alt) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    for (track, tr) in list(&tl.get("tracks")).iter().enumerate() {
        let track = track as f64;
        let groups = Map::new(); // 띠 uid → 그 띠에 그려지는 막대들
        for x in items(&tr.get("figures")) {
            if lt(&x.get("lvl"), &V::Num(0.0)) || x.get("row").is_nullish() || !x.bool("band") { c_over += 1.0; continue; }
            let hidden = tr.get("hiddenRows");
            if tv(&hidden) && has_or_err(&hidden, &x.get("row"), "tr.hiddenRows")? { c_over += 1.0; continue; }
            let (f, s, band) = (x.get("f"), x.get("s"), x.get("band"));
            let start = minute_val(&s.get("start"));
            let end = js::max(&[n(&start), n(&minute_val(&s.get("endY")))]);
            if start.is_nullish() { continue; }
            // 1년이 안 되는 활동도 화면에서는 적어도 3px으로 그린다 — 그 1년의 폭으로 단계를 매겨 성긴 단계에서 사라지지 않게(_figSpan).
            let (s0, s1) = if n(&s.get("endY")) - n(&s.get("start")) >= 1.0 { (s.get("start"), s.get("endY")) } else {
                let mid = n(&js::add(&s.get("start"), &s.get("endY"))) / 2.0;
                (V::Num(mid - 0.5), V::Num(mid + 0.5))
            };
            let lod = lod_of(js::max(&[0.0, n(&minute_val(&s1)) - n(&minute_val(&s0))]));
            let unk = unknown_ends(&s, &band);
            let alts = n(&or(f.get("alternatives"), crate::lay::model::util::arr(Vec::new())).get("length")) + n(&or(s.get("alternatives"), crate::lay::model::util::arr(Vec::new())).get("length"));
            let has_life = !f.get("birth").is_nullish() || !f.get("death").is_nullish();
            let life = if has_life {
                let part = |k: &str| if f.get(k).is_nullish() { String::new() } else { t(&minute_val(&f.get(k))) };
                format!("{}|{}", part("birth"), part("death"))
            } else { "|".to_string() };
            if has_life { c_life += 1.0; }
            let color = f64::from(rgb(&or(s.get("color"), band.get("color")), 0xa4b1b7));
            let b = shl(js::min(&[3.0, js::max(&[1.0, n(&or(f.get("importance"), V::Num(2.0)))])]), 0)
                | if unk.0 { 4 } else { 0 } | if unk.1 { 8 } else { 0 } | if alts != 0.0 && !alts.is_nan() { 16 } else { 0 } | if f.bool("houseId") { 32 } else { 0 };
            push_item(out, &o! {
                "section" => SECTION.bar, "track" => track, "row" => x.get("row"), "row2" => x.get("row"), "start" => start.clone(), "end" => end, "lod" => lod,
                "ref" => band.get("uid"), "name" => or(f.get("name"), V::from("")), "color" => color,
                "a" => x.get("lvl"),
                "b" => f64::from(b),
                "c" => or(x.get("i"), V::Num(0.0)),
                "d" => 0.0,
                // 가문 강조(emphasis.look.house)가 견줄 값이라 가문의 id를 넷째 칸에 싣는다(계약 6-7 · 가문이 없으면 빈칸).
                "text2" => format!("{}|{life}|{}", t(&f.get("uid")), t(&or(f.get("houseId"), V::from("")))),
            });
            c_bar += 1.0;

            // 구역 39 · 활동 기록의 이설: 유령 구분선(막대 안)과 생몰 이설의 빈 고리(수명선 위). start가 표식의 자리이고 end는 막대의 끝이다(단계 셈과 타일 고르기에만).
            let seed = o! {
                "section" => SECTION.alt, "track" => track, "row" => x.get("row"), "row2" => x.get("row"), "start" => start.clone(), "end" => end, "lod" => lod, "ref" => band.get("uid"), "name" => "", "color" => color,
                "a" => x.get("lvl"), "b" => 0.0, "c" => or(x.get("i"), V::Num(0.0)), "d" => 0.0, "text2" => f.get("uid"),
            };
            let base = V::Obj(o! { "start" => s.get("from"), "startAt" => s.get("fromAt"), "end" => s.get("to"), "endAt" => s.get("toAt"), "startUnknown" => s.get("fromUnknown"), "endUnknown" => s.get("toUnknown") });
            for (y, side) in alt_edges(rc, &bar_alternatives(rc, &f, &s), &base, &f.get("endY")) {
                let at = minute_val(&y);
                if at.is_nullish() || !n(&at).is_finite() { continue; }
                push_item(out, &assign(&seed, o! { "start" => at.clone(), "end" => js::max(&[n(&at), end]), "b" => if side == 'e' { 1.0 } else { 0.0 } }));
                c_edge += 1.0;
            }
            for y in life_edges(rc, &f) {
                let at = minute_val(&y);
                if at.is_nullish() || !n(&at).is_finite() { continue; }
                push_item(out, &assign(&seed, o! { "start" => at.clone(), "end" => js::max(&[n(&at), end]), "b" => 4.0 }));
                c_life_alt += 1.0;
            }
            if !groups.has(&band.get("uid")) { groups.set(band.get("uid"), o! { "band" => band.clone(), "row" => x.get("row"), "n" => 0.0 }); }
            let g = groups.get(&band.get("uid"));
            if let V::Obj(g) = g { g.set("n", g.num("n") + 1.0); }
        }
        // 구역 38 · 인물 단 묶음: 막대가 빽빽하면(보이는 막대의 평균 폭 6px 미만) 단 전체를 '인물 n명' 한 칸으로 바꾼다.
        for g in groups.values() {
            let (band, row, count) = (g.get("band"), g.get("row"), g.get("n"));
            let start = minute_val(&band_start(&band));
            let end = js::max(&[n(&start), n(&minute_val(&band_end(&band)))]);
            push_item(out, &o! {
                "section" => SECTION.group, "track" => track, "row" => row.clone(), "row2" => row, "start" => start, "end" => end, "lod" => -1.0,
                "ref" => if has_band(&band.get("uid"))? { band.get("uid") } else { V::from("") }, "name" => or(band.get("name"), V::from("")), "color" => f64::from(rgb(&band.get("color"), 0xa4b1b7)),
                "a" => count, "b" => 6.0, "c" => 80.0, "d" => 0.0, "text2" => band.get("uid"),
            });
            c_group += 1.0;
        }
    }
    ctx.notes.set("인물", o! { "막대" => c_bar, "묶음" => c_group, "넘친인물" => c_over, "생몰있음" => c_life, "이설경계" => c_edge, "생몰이설" => c_life_alt });
    Ok(())
}

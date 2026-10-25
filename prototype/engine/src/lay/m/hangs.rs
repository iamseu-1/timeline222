//! 내보내기 모듈 `hangs` — `prototype/scripts/export/hangs.mjs`(1 ~ 193줄 · SHA-256 앞 12자 `bb8167868fcf` — 저장소의 LF 바이트)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 6).
//! 띠 밖에 덧붙는 것 → 일반 항목(items): 16 속국 이름표(매달린 탭 · 세로 끈) · 17 구역 탭 · 18 바탕 문화의 아래 이름 단 · 44 이름표의 모호한 연대 · 45 이설 경계 ·
//! 47 뒤 장의 탭(속국 띠 위, 그 나라가 섬긴 상국의 탭) · 48 상국 띠의 속국 접기 단추. 구역 번호와 a~d · text2의 뜻은 계약 6절.
//!
//! 읽는 shared: `bandOf`(없으면 빈 Map — 띠 번호 = 순번 + 1을 구역 16 · 44 · 45 · 47의 d에). 모듈의 `bandStart` · `bandEnd`는 `lay::rows`의 것 · `lodOf`는 [`super::kit::lod_of`](모듈 사본들과 몸이 같은 하나 — 과제 Y).
//! 모듈의 `altEdges` 사본은 strips · figures의 것과 몸이 같아 [`crate::lay::web::alts::alt_edges`] 하나를 부른다(과제 Y).
//! 부르는 웹 함수: `HT.altDated` · `HT.altFlipped` · `HT.altSpan`(→ `web::alts`) · `HT.Timeline.depLook`(→ [`dep_look`]).
use super::kit::{band_id, has_or_err, lod_of, minute_val};
use super::rails::push_item;
use crate::lay::web::alts::{alt_edges, alts_of};
use crate::lay::ctx::{dep_look, Ctx};
use crate::lay::export::color;
use crate::lay::js::{self, Map, Obj, V};
use crate::lay::model::o;
use crate::lay::model::util::{assign_obj, eq, is, le, list, lt, n, nn, or, t, tv};
use crate::lay::rows::{band_end, band_start, items};
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

struct Sec { hang: f64, zone: f64, hem: f64, vague: f64, alt: f64, host_tab: f64, hang_btn: f64 }
const SEC: Sec = Sec { hang: 16.0, zone: 17.0, hem: 18.0, vague: 44.0, alt: 45.0, host_tab: 47.0, hang_btn: 48.0 };
/// 뒤 장의 탭의 모습(a) — 지금 연표의 depLook 그대로(상국 띠의 이름표와 같은 자) · 모르면 3.
fn host_look(look: &V) -> f64 {
    match look.as_str().and_then(|s| s.exact().map(str::to_owned)).as_deref() {
        Some("loose") => 0.0, Some("firm") => 1.0, Some("nominal") => 2.0, Some("plain") => 3.0, Some("held") => 4.0, Some("owned") => 5.0, Some("occupied") => 6.0, _ => 3.0,
    }
}
/// 매달린 이름표의 모습(b) — 지금 연표의 depLook · 모르면 3.
fn hang_look(look: &V) -> f64 {
    match look.as_str().and_then(|s| s.exact().map(str::to_owned)).as_deref() { Some("loose") => 0.0, Some("firm") => 1.0, Some("nominal") => 2.0, Some("plain") => 3.0, _ => 3.0 }
}
const HANG_LINK: f64 = 4.0; // b = 4 — 밖 ↔ 안을 옮긴 속국의 세로 끈
/// 매달린 이름표의 style(c).
struct Cs { unk_s: i32, unk_e: i32, join_l: i32, in_side: i32, vague_est: i32, vague_leg: i32, has_range: i32 }
const C: Cs = Cs { unk_s: 1, unk_e: 2, join_l: 4, in_side: 8, vague_est: 16, vague_leg: 32, has_range: 64 };


/// `contribute(ctx, out)`.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let band_of = { let b = ctx.shared.get("bandOf"); if tv(&b) { b } else { V::Map(Map::new()) } }; // 띠의 uid → out.periods의 순번(bands.mjs) — 띠 번호는 순번 + 1
    let id_of = |uid: &V| band_id(&band_of, uid);
    let rc = &ctx.read;
    let mut counts = [0.0f64; 8]; // 속국이름표 · 세로끈 · 구역탭 · 바탕문화이름 · 모호한연대 · 이설경계 · 뒤장탭 · 속국접기단추
    let item = |out: &mut Value, extra: Obj| {
        let base = o! { "section" => 0.0, "track" => 0.0, "row" => 0.0, "row2" => 0.0, "start" => 0.0, "end" => 0.0, "lod" => -1.0, "ref" => "", "name" => "", "color" => 0.0, "a" => 0.0, "b" => 0.0, "c" => 0.0, "d" => 0.0, "text2" => "" };
        assign_obj(&base, &extra);
        push_item(out, &base);
    };

    for (track, tr) in list(&tl.get("tracks")).iter().enumerate() {
        let track = track as f64;
        let folded_rows = tr.get("foldedRows");
        let folded_has = |r: &V| -> crate::Result<bool> { has_or_err(&folded_rows, r, "tr.foldedRows") };
        let drawn = |p: &V| -> crate::Result<bool> {
            let row = p.get("_row");
            Ok(!p.bool("_folded") && !p.bool("_hidden") && !p.bool("_under") && !p.bool("_overlay") && !row.is_nullish() && le(&V::Num(0.0), &row) && lt(&row, &tr.get("rows")) && !folded_has(&row)?)
        };
        let periods = list(&tr.get("periods"));

        /* 속국 이름표: 상국 띠 아래에 매달린 탭(스스로 다스린 관계 — 빈 · 칠한 · 점선 · 파선) */
        for p in &periods {
            if !drawn(p)? || !p.bool("_dep") || !p.get("_dep").bool("outLanes") { continue; }
            let row = p.get("_row");
            for it in list(&p.get("_dep").get("items")) {
                if !it.bool("out") { continue; }
                let lane = or(it.get("outLane"), V::Num(0.0));
                let ip = it.get("p");
                let mut prev = V::Null;
                for s in list(&it.get("segs")) {
                    if !is(&s.get("side"), "out") { prev = s; continue; }
                    let (start, end) = (minute_val(&s.get("a")), minute_val(&s.get("b")));
                    if start.is_nullish() || end.is_nullish() || lt(&end, &start) { prev = s; continue; }
                    /* 모호한 연대(디테일 건의 4 · altRowPlan의 zones): 연대 폭을 적었으면 그 구간만(구역 44),
                       폭 없이 확실성만 적었으면 그 조각 전체가 무늬다. 무늬는 전승이면 빗금, 그 밖(추정 · 통설)이면 세로 줄(zoneKindOf). */
                    let h = s.get("h");
                    let ranges: Vec<V> = [h.get("startRange"), h.get("endRange")].into_iter().filter(tv).collect();
                    let legend = is(&h.get("certainty"), "legend");
                    let vague = if ranges.is_empty() && (legend || is(&h.get("certainty"), "estimated")) { if legend { C.vague_leg } else { C.vague_est } } else { 0 };
                    let style = (if h.bool("startUnknown") { C.unk_s } else { 0 }) | (if h.bool("endUnknown") { C.unk_e } else { 0 })
                        | (if tv(&prev) && is(&prev.get("side"), "out") { C.join_l } else { 0 }) | vague | (if ranges.is_empty() { 0 } else { C.has_range });
                    item(out, o! {
                        "section" => SEC.hang, "track" => track, "row" => row.clone(), "row2" => row.clone(), "start" => start.clone(), "end" => end.clone(), "ref" => p.get("uid"), "name" => or(ip.get("name"), V::from("")),
                        "color" => f64::from(color(&ip.get("color"), 0xa4b1b7)), "a" => lane.clone(), "b" => hang_look(&s.get("look")), "c" => f64::from(style), "d" => id_of(&ip.get("uid"))?, "text2" => ip.get("uid"),
                    });
                    counts[0] += 1.0;
                    for (side, rg) in [(0.0, h.get("startRange")), (1.0, h.get("endRange"))] {
                        if !tv(&rg) { continue; }
                        let a = minute_val(&rg.get(&0.0));
                        let b = js::max(&[n(&a), n(&minute_val(&rg.get(&1.0)))]);
                        if a.is_nullish() { continue; }
                        item(out, o! {
                            "section" => SEC.vague, "track" => track, "row" => row.clone(), "row2" => row.clone(), "start" => a, "end" => b, "lod" => lod_of(n(&end) - n(&start)), "ref" => p.get("uid"),
                            "color" => f64::from(color(&ip.get("color"), 0xa4b1b7)), "a" => lane.clone(), "b" => if legend { 1.0 } else { 0.0 }, "c" => side, "d" => id_of(&ip.get("uid"))?, "text2" => ip.get("uid"),
                        });
                        counts[4] += 1.0;
                    }
                    /* 구역 45 — 이설이 말하는 경계(유령 구분선). start가 선의 자리이고 end는 그 조각의 끝이다(단계 셈과 타일 고르기에만). */
                    let base = V::Obj(o! { "start" => s.get("a"), "end" => s.get("b"), "startUnknown" => h.get("startUnknown"), "endUnknown" => h.get("endUnknown") });
                    for (y, side) in alt_edges(rc, &alts_of(&h), &base, &ip.get("endY")) {
                        let at = minute_val(&y);
                        if at.is_nullish() { continue; }
                        item(out, o! {
                            "section" => SEC.alt, "track" => track, "row" => row.clone(), "row2" => row.clone(), "start" => at.clone(), "end" => js::max(&[n(&at), n(&end)]), "lod" => lod_of(n(&end) - n(&start)), "ref" => p.get("uid"),
                            "color" => f64::from(color(&ip.get("color"), 0xa4b1b7)), "a" => lane.clone(), "b" => if side == 'e' { 1.0 } else { 0.0 }, "c" => 0.0, "d" => id_of(&ip.get("uid"))?, "text2" => ip.get("uid"),
                        });
                        counts[5] += 1.0;
                    }
                    prev = s;
                }
                /* 밖 ↔ 안으로 옮긴 때: 이어진 두 구간의 경계에 세로 끈 하나(매달린 탭의 가운데 ↔ 품은 칸의 가운데).
                   끈은 뒤 조각의 시작에 그린다 — 기간은 뒤 조각의 것(단계 셈이 그 조각과 같게) */
                if it.bool("out") && it.bool("inn") {
                    let segs = list(&it.get("segs"));
                    for k in 1..segs.len() {
                        let (a, b) = (&segs[k - 1], &segs[k]);
                        if eq(&a.get("side"), &b.get("side")) || (n(&a.get("b")) - n(&b.get("a"))).abs() > 1e-9 { continue; }
                        let (start, end) = (minute_val(&b.get("a")), minute_val(&b.get("b")));
                        if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
                        item(out, o! {
                            "section" => SEC.hang, "track" => track, "row" => row.clone(), "row2" => row.clone(), "start" => start, "end" => end, "ref" => p.get("uid"), "name" => "", "color" => f64::from(color(&ip.get("color"), 0xa4b1b7)),
                            "a" => lane.clone(), "b" => HANG_LINK, "c" => if is(&b.get("side"), "in") { f64::from(C.in_side) } else { 0.0 }, "d" => js::add(&or(it.get("inLane"), V::Num(0.0)), &V::Num(1.0)), "text2" => ip.get("uid"),
                        });
                        counts[1] += 1.0;
                    }
                }
            }
        }

        /* 상국 띠의 속국 접기 단추(구역 48 — 건의 8의 나 · 감독 2026-10-14 "종주국 띠에 접기 하나"): 매달린 이름표가 있는 상국 띠마다 하나 — 지금 연표의 .tl-hangbtn '▾ 속국 n'.
           구간 = 상국 띠(연대 폭의 바깥 끝까지) · a = 매달린 속국 수(그 상국 아래 밖에 매달린 속국 — 조각 수가 아니라 나라 수). 자리(첫 글줄 · 소속 단추 · 네모 뒤)와
           접힘 상태(그 상국의 매달린 줄을 덧붙는 높이에서 뺌)는 그리는 쪽의 몫이다. 내보내기는 아무것도 접지 않은 상태라 모두 펼침 */
        for p in &periods {
            if !drawn(p)? || !p.bool("_dep") || !p.get("_dep").bool("outLanes") { continue; }
            let (start, end) = (minute_val(&band_start(p)), minute_val(&band_end(p)));
            if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
            item(out, o! {
                "section" => SEC.hang_btn, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => start, "end" => end, "lod" => -1.0, "ref" => p.get("uid"), "name" => "", "color" => f64::from(color(&p.get("color"), 0xa4b1b7)),
                "a" => list(&p.get("_dep").get("items")).iter().filter(|it| it.bool("out")).count() as f64, "b" => 0.0, "c" => 0.0, "d" => 0.0, "text2" => "",
            });
            counts[7] += 1.0;
        }

        /* 뒤 장 · 상국 탭(구역 47 — 묶음 3 · 1번 L, 2026-09-22 → 건의 8의 2번 C, 2026-10-14): 제 줄에 선 속국의 띠 뒤에 그 나라가 섬긴 상국 빛깔의 뒤 장(관계 구간 · 위로 5px),
           그 평평한 윗변의 관계가 끝나는 쪽에 상국 탭. 자리는 그리는 쪽이 장면마다 정한다 — 여기에는 소속 한 건마다 그 구간과 상국 · 모습만 싣는다.
           상국은 띠로 그려지는 정권일 때만(왕조 · 기관 · 문화는 뺌), 상위 띠 아래에 접힌 소속(singleHost)은 없다 */
        for p in &periods {
            if !drawn(p)? || !p.bool("hosts") || !tv(&p.get("hosts").get("length")) || p.bool("singleHost") { continue; }
            for (k, h) in list(&p.get("hosts")).iter().enumerate() {
                let q = h.get("host");
                if !tv(&q) || is(&q.get("polityKind"), "overlay") || is(&q.get("polityKind"), "dynasty") || is(&q.get("polityKind"), "culture") { continue; }
                // 구간 = 섬긴 관계의 시작 ~ 끝(적지 않았으면 속국 띠의 시작 · 끝). 상국이 서기 전 · 없어진 뒤로는 나가지 않는다
                let s = js::max(&[n(&nn(h.get("start"), p.get("start"))), n(&nn(q.get("start"), V::Num(f64::NEG_INFINITY)))]);
                let e = js::min(&[n(&nn(h.get("end"), p.get("endY"))), n(&nn(q.get("endY"), V::Num(f64::INFINITY)))]);
                if !(e > s) { continue; }
                let (start, end) = (minute_val(&V::Num(s)), minute_val(&V::Num(e)));
                if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
                let look = dep_look(p, h).get("look");
                item(out, o! {
                    "section" => SEC.host_tab, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => start, "end" => end, "ref" => p.get("uid"), "name" => or(q.get("name"), V::from("")),
                    "color" => f64::from(color(&q.get("color"), 0xa4b1b7)), "a" => host_look(&look), "b" => k as f64, "c" => 0.0, "d" => id_of(&q.get("uid"))?, "text2" => q.get("uid"),
                });
                counts[6] += 1.0;
            }
        }

        /* 구역 탭(조계지 · 조차지): 얹히는 시대 띠 아래로 살짝 내려오는 작은 탭 — 매달린 이름표 줄 뒤에 이어 센다 */
        for p in items(&tr.get("overlays")) {
            if !is(&p.get("scale"), "zone") { continue; }
            for h in items(&p.get("hosts")) {
                let hu = h.get("host").get("uid");
                let mut host = periods.iter().find(|q| eq(&q.get("uid"), &hu)).cloned().unwrap_or(V::Null);
                while tv(&host) && host.bool("_hidden") { host = host.get("_host"); }
                if !tv(&host) || host.get("_row").is_nullish() || folded_has(&host.get("_row"))? { continue; }
                // 지금 연표(timeline.js:6701~6706)와 같은 구간 — 연대 폭이 있으면 그 바깥 끝까지
                let s = js::max(&[n(&band_start(&p)), n(&nn(h.get("start"), V::Num(f64::NEG_INFINITY))), n(&band_start(&host))]);
                let e = js::min(&[n(&band_end(&p)), n(&nn(h.get("end"), V::Num(f64::INFINITY))), n(&band_end(&host))]);
                if e <= s { continue; }
                let (start, end) = (minute_val(&V::Num(s)), minute_val(&V::Num(e)));
                if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
                let row = host.get("_row");
                let V::Map(lanes) = tr.get("hangRowLanes") else { return Err("tr.hangRowLanes가 Map이 아닙니다 — JS라면 .get에서 멈춤".into()) };
                let zl = p.get("_zoneLane");
                if zl.is_nullish() { return Err(format!("구역 {}에 _zoneLane이 없습니다 — JS라면 p._zoneLane[…]에서 멈춤", t(&p.get("name"))).into()); }
                item(out, o! {
                    "section" => SEC.zone, "track" => track, "row" => row.clone(), "row2" => row.clone(), "start" => start, "end" => end, "ref" => host.get("uid"), "name" => or(p.get("name"), V::from("")),
                    "color" => f64::from(color(&p.get("color"), 0xa4b1b7)), "a" => js::add(&or(lanes.get(&row), V::Num(0.0)), &nn(zl.get(&js::to_str(&hu)), V::Num(0.0))), "text2" => p.get("uid"),
                });
                counts[2] += 1.0;
            }
        }

        /* 바탕 문화의 아래 이름 단(hem): 깔린 첫 줄의 띠 밑에 '이름 + 문화' — 띠 자체는 bands.mjs가 싣는다 */
        for p in items(&tr.get("underlays")) {
            let rows = items(&p.get("_underRows"));
            if rows.is_empty() { continue; }
            // 바탕 문화의 좌우는 띠와 같다 — 연대 폭이 있으면 그 바깥 끝까지(지금 연표의 .tl-under도 bandStart · bandEnd)
            let (start, end) = (minute_val(&band_start(&p)), minute_val(&band_end(&p)));
            if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
            item(out, o! {
                "section" => SEC.hem, "track" => track, "row" => rows[0].clone(), "row2" => rows[0].clone(), "start" => start, "end" => end, "ref" => p.get("uid"), "name" => or(p.get("name"), V::from("")),
                "color" => f64::from(color(&p.get("color"), 0xa4b1b7)), "a" => 0.0, "b" => 0.0, "c" => rows.len() as f64, "d" => 0.0, "text2" => "문화",
            });
            counts[3] += 1.0;
        }
    }
    let names = ["속국이름표", "세로끈", "구역탭", "바탕문화이름", "모호한연대", "이설경계", "뒤장탭", "속국접기단추"];
    let c = Obj::new();
    for (k, v) in names.iter().zip(counts) { c.set(*k, v); }
    ctx.notes.set("덧붙는_것", c);
    Ok(())
}

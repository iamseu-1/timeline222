//! 내보내기 모듈 `rails` — `prototype/scripts/export/rails.mjs`(1 ~ 140줄 · SHA-256 앞 12자 `abc4adab11ed` — 저장소의 LF 바이트)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 8).
//! 기간 사건의 그림 — 기간 막대 · 연대 폭 · 이설 · 조약 발효 눈금(계약 4절의 items · 6절의 구역 33 ~ 36). 단(lvl)은 화면이 아니라 자료(해)로만 정한다.
//!
//! 내보내는 함수 다섯(events · figures · links가 가져다 쓴다): [`event_color`] · [`event_uid`] · [`on_rail`] · [`rail_span`] · [`rail_levels`] — `lodOf`는 모듈마다의 사본이 몸이 같아
//! [`super::kit::lod_of`] 하나(과제 Y).
//! 쓰는 shared: `railLevel` · `railRank`(이미 있으면 그대로 — 차례상 events가 먼저 [`rail_levels`]를 불러 채운다). 읽는 out 칸 없음.
//! 부르는 웹 함수(이미 옮긴 것): `HT.datedAlts`(→ [`dated_alts`]). tl · shared는 부를 때마다 ctx에서 읽는다(REPLAY가 바꿔 끼운 것을 그대로 — 모듈 안에 기억하지 않음).
//!
//! 갈래 B의 모듈이 함께 쓰는 작은 도움(옮긴 함수가 아님): [`assign`](`Object.assign({}, base, extra)`) · [`push_item`] · [`shl`] · [`bit`] — base.mjs의 `minute`(값 그대로 null/수)은
//! [`super::kit::minute_val`](과제 Y — power · lens의 꼴과 하나로).
//! JS라면 던졌을 곳(`tr.geo`가 없음 · `levels[-1]` · `ranks.get`이 Map이 아님)은 오류로 돌려준다(조용히 다른 답을 내지 않음).
use super::kit::{lod_of, minute_val};
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color as rgb};
use crate::lay::js::{self, Map, Obj, V};
use crate::lay::model::o;
use crate::lay::model::util::{assign_obj, copy, dated_alts, le, list, lt, n, nn, or, or_cmp, sub, t, tv};
use crate::lay::rows::items;
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 내가 쓰는 일반 구역 번호(32 ~ 47 가운데). 32는 events.mjs(하위 사건)가 쓴다.
pub struct Section { pub rail: f64, pub fuzz: f64, pub alt: f64, pub effect: f64 }
pub const SECTION: Section = Section { rail: 33.0, fuzz: 34.0, alt: 35.0, effect: 36.0 };

// ── 갈래 B의 작은 도움 ──

/// `Object.assign({}, base, extra)`.
pub fn assign(base: &Obj, extra: Obj) -> Obj {
    let out = copy(&V::Obj(base.clone()));
    assign_obj(&out, &extra);
    out
}
/// `out.items.push(o)` — JS 객체를 JSON 값으로(`JSON.stringify`의 뜻: undefined 칸은 빠지고 NaN은 null). `out.items`가 없으면 만든다.
pub fn push_item(out: &mut Value, o: &Obj) { arr_mut(out, "items").push(js::to_json(&V::Obj(o.clone()))); }
/// JS `x << k`(32비트로 감김).
pub fn shl(x: f64, k: u32) -> i32 { js::to_i32(x).wrapping_shl(k) }
/// `(x ? b : 0)` — 참이면 `b`.
pub fn bit(x: &V, b: i32) -> i32 { if tv(x) { b } else { 0 } }

// ── rails.mjs ──

/// 사건의 색 — 그려지는 자리(placements)의 정권 색이 먼저(_drawTrack과 같다).
pub fn event_color(e: &V) -> V {
    let place = e.get("_place");
    let first = if tv(&place) { place.get("polityColor") } else { place };
    or(or(or(first, e.get("polityColor")), e.get("color")), V::from("#a4b1b7"))
}

/// 한 사건의 열쇠(공동 사건의 둘째 자리부터는 #1 · #2 … — events.mjs의 uid와 같다).
pub fn event_uid(e: &V) -> V {
    let pi = e.get("_pi");
    let tail = if tv(&pi) { V::from(format!("#{}", t(&pi))) } else { V::from("") };
    js::add(&e.get("uid"), &tail)
}

/// 이 사건이 기간 막대 칸을 쓰는가. 화면은 폭(픽셀)으로 따지지만(ranged || fuzzy || alts) 자료로는 같은 것을 해로 따진다(_layoutTrack의 railLevels 셈과 같다).
pub fn on_rail(e: &V) -> bool {
    lt(&e.get("start"), &e.get("endY")) || e.bool("startRange") || e.bool("endRange") || !dated_alts(e).is_empty()
}

/// 사건이 기간 막대 칸에서 차지하는 해 범위 [lo, hi] — 통설 · 연대 폭 · 이설을 모두 품는다(_layoutTrack의 segs와 같다).
pub fn rail_span(e: &V) -> (f64, f64) {
    let mut ys: Vec<V> = vec![e.get("start"), e.get("endY")];
    if e.bool("startRange") { ys.extend(list(&e.get("startRange"))); }
    if e.bool("endRange") { ys.extend(list(&e.get("endRange"))); }
    for a in dated_alts(e) { ys.push(a.get("start")); ys.push(nn(a.get("end"), a.get("start"))); }
    let nums: Vec<f64> = ys.iter().map(n).collect();
    (js::min(&nums), js::max(&nums))
}

/// 사건의 열쇠 → 기간 막대의 단. 줄마다 빈 단을 찾고(없으면 가장 적게 겹치는 단 — 화면의 pickLevel과 같은 규칙), 단 수는 그 트랙의 railLevels.
/// 함께 **그 줄에서 단을 고르는 차례**(`ctx.shared.railRank`)도 적어 둔다 — 화면은 배율마다 단을 다시 고르는데(js/timeline.js의 pickLevel),
/// 그때 이 차례대로 돌려야 지금 연표와 같은 단이 나온다(중요한 것 먼저 · 같으면 이른 것 먼저). 화면 쪽은 `d`의 8비트 위에서 이 차례를 읽는다.
pub fn rail_levels(ctx: &mut Ctx) -> crate::Result<Map> {
    let have = ctx.shared.get("railLevel");
    if tv(&have) {
        return match have { V::Map(m) => Ok(m), other => Err(format!("shared.railLevel이 Map이 아닙니다({}) — JS라면 .get에서 멈춤", js::type_of(&other)).into()) };
    }
    let tl = ctx.tl.clone();
    let map = Map::new();
    let rank = Map::new();
    for tr in list(&tl.get("tracks")) {
        let geo = tr.get("geo");
        if geo.is_nullish() { return Err(format!("트랙 {}에 geo가 없습니다 — JS라면 tr.geo.railLevels에서 멈춤", t(&tr.get("id"))).into()); }
        let max = js::max(&[1.0, js::min(&[3.0, n(&or(geo.get("railLevels"), V::Num(2.0)))])]);
        let len = if max.is_nan() { 0 } else { max.trunc() as usize }; // Array.from({ length }) — ToLength
        for row in items(&tr.get("eventsByRow")) {
            let mut levels: Vec<Vec<(f64, f64)>> = vec![Vec::new(); len];
            let mut order: Vec<(V, (f64, f64))> = list(&row).into_iter().filter(on_rail).map(|e| { let span = rail_span(&e); (e, span) }).collect();
            // 화면이 사건을 놓는 차례와 같게: 중요한 것 먼저 · 같으면 이른 것 먼저(_placeRow의 order — 고름 · 강조는 그때그때라 빼고).
            js::sort_by(&mut order, |a, b| {
                let imp = |e: &V| n(&or(e.get("importance"), V::Num(2.0)));
                or_cmp(imp(&b.0) - imp(&a.0), || or_cmp(sub(&a.0.get("start"), &b.0.get("start")), || if lt(&a.0.get("uid"), &b.0.get("uid")) { -1.0 } else { 1.0 }))
            });
            for (i, (e, _)) in order.iter().enumerate() { rank.set(event_uid(e), i as f64); }
            for (e, (l, r)) in &order {
                let (l, r) = (*l, *r);
                let mut lvl: i64 = levels.iter().position(|used| !used.iter().any(|&(a, b)| a < r && l < b)).map_or(-1, |i| i as i64);
                if lvl < 0 {
                    let mut best = f64::INFINITY;
                    for (i, used) in levels.iter().enumerate() {
                        let over = used.iter().fold(0.0, |s, &(a, b)| s + js::max(&[0.0, js::min(&[b, r]) - js::max(&[a, l])]));
                        if over < best { best = over; lvl = i as i64; }
                    }
                }
                if lvl < 0 { return Err(format!("기간 막대의 단을 고르지 못했습니다: {} — JS라면 levels[-1].push에서 멈춤", t(&e.get("title"))).into()); }
                levels[lvl as usize].push((l, r));
                map.set(event_uid(e), lvl as f64);
            }
        }
    }
    ctx.shared.set("railLevel", map.clone());
    ctx.shared.set("railRank", rank);
    Ok(map)
}

/// `contribute(ctx, out)` — 사건마다 구역 33(기간 막대) · 34(연대 폭) · 35(이설) · 36(조약 발효 눈금).
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let levels = rail_levels(ctx)?;
    let ranks = ctx.shared.get("railRank");
    let (mut c_bar, mut c_fuzz, mut c_alt, mut c_eff, mut c_short) = (0.0, 0.0, 0.0, 0.0, 0.0);
    const DAY: f64 = 1440.0;
    for (track, tr) in list(&tl.get("tracks")).iter().enumerate() {
        for e in list(&tr.get("events")) {
            if !on_rail(&e) { continue; }
            let er = e.get("_row");
            let row = if er.is_nullish() || lt(&er, &V::Num(0.0)) { tr.get("commonRow") } else { er };
            if row.is_nullish() || lt(&row, &V::Num(0.0)) || le(&tr.get("rows"), &row) { continue; }
            let uid = event_uid(&e);
            let lvl = nn(levels.get(&uid), V::Num(0.0));
            let color = rgb(&event_color(&e), 0xa4b1b7);
            let alts = dated_alts(&e);
            // 이 사건의 그림이 통틀어 차지하는 폭 — 곁들임(빗금 · 이설 세로바 · 발효 눈금)은 막대와 같은 단계까지 실린다.
            let (lo, hi) = rail_span(&e);
            let whole = js::max(&[0.0, n(&minute_val(&V::Num(hi))) - n(&minute_val(&V::Num(lo)))]);
            let near = lod_of(whole);
            // 화면이 단을 다시 고를 때 쓰는 값(계약 6-7): b의 5~6비트 = 중요도 · d의 8비트 위 = 그 줄에서의 차례 + 1.
            let imp_bits = shl(js::min(&[3.0, js::max(&[1.0, n(&or(e.get("importance"), V::Num(2.0)))])]), 5);
            let rank_of = match &ranks { V::Map(m) => m.get(&uid), other => return Err(format!("shared.railRank가 Map이 아닙니다({}) — JS라면 ranks.get에서 멈춤", js::type_of(other)).into()) };
            let rank_bits = shl(n(&js::add(&nn(rank_of, V::Num(0.0)), &V::Num(1.0))), 8);
            let base = o! { "section" => 0.0, "track" => track as f64, "row" => row.clone(), "row2" => row.clone(), "start" => 0.0, "end" => 0.0, "lod" => near, "ref" => uid.clone(), "name" => "", "color" => f64::from(color), "a" => lvl.clone(), "b" => f64::from(imp_bits), "c" => 0.0, "d" => f64::from(rank_bits), "text2" => "" };
            let ranged = lt(&e.get("start"), &e.get("endY"));

            // 구역 33 · 기간 막대: 가는 선 + 양 끝 세로바. 기간이 아무리 짧아도 모두 싣는다(화면은 최소 3px으로 그린다).
            if ranged {
                let start = minute_val(&e.get("start"));
                let end = js::max(&[n(&start), n(&minute_val(&e.get("endY")))]);
                if end - n(&start) < 45.5 * DAY { c_short += 1.0; }
                let b = imp_bits | bit(&e.get("_sec"), 1) | bit(&e.get("treaty"), 2) | bit(&e.get("startRange"), 4) | bit(&e.get("endRange"), 8) | if alts.is_empty() { 0 } else { 16 };
                push_item(out, &assign(&base, o! {
                    "section" => SECTION.rail, "start" => start, "end" => end, "lod" => -1.0, "name" => or(e.get("title"), V::from("")),
                    "b" => f64::from(b),
                    "c" => f64::from(bit(&e.get("startUnknown"), 1) | bit(&e.get("endUnknown"), 2)),
                    "d" => f64::from(rank_bits | js::min(&[255.0, alts.len() as f64]) as i32),
                }));
                c_bar += 1.0;
            }

            // 구역 34 · 연대 폭: 기간 사건이면 빗금 구간, 끝 연도 없는 점 사건이면 점선 실의 양 끝 눈금.
            for (j, range) in [e.get("startRange"), e.get("endRange")].iter().enumerate() {
                if !tv(range) { continue; }
                let start = minute_val(&range.get(&0.0));
                let end = js::max(&[n(&start), n(&minute_val(&range.get(&1.0)))]);
                push_item(out, &assign(&base, o! { "section" => SECTION.fuzz, "start" => start, "end" => end, "b" => f64::from(imp_bits | j as i32), "c" => if ranged { 1.0 } else { 0.0 } }));
                c_fuzz += 1.0;
            }

            // 구역 35 · 이설: 점선 세로바(시작) + 통설과 이어 주는 점선. 끝이 통설과 다른 이설은 끝에도 같은 세로바.
            for (j, a) in alts.iter().enumerate() {
                let a_end = a.get("end");
                let end_fin = !a_end.is_nullish() && n(&a_end).is_finite(); // a.end != null && isFinite(a.end)
                let end_y = if end_fin { a_end.clone() } else { a.get("start") };
                let start = minute_val(&a.get("start"));
                let end = js::max(&[n(&start), n(&minute_val(&end_y))]);
                let differs = end_fin && !a.bool("ongoing") && (n(&a_end) - n(&nn(e.get("end"), e.get("endY")))).abs() > 1e-9;
                let b = imp_bits | (if end_fin { 1 } else { 0 }) | (if differs { 2 } else { 0 }) | bit(&a.get("ongoing"), 4) | (if ranged { 8 } else { 0 });
                push_item(out, &assign(&base, o! { "section" => SECTION.alt, "start" => start, "end" => end, "name" => or(a.get("label"), V::from("")), "b" => f64::from(b), "c" => j as f64 }));
                c_alt += 1.0;
            }

            // 구역 36 · 조약의 발효 눈금: x0 = 눈금 자리 · x1 = 기간 막대의 끝(단계 셈에만 — 막대와 함께 실리게).
            let treaty = e.get("treaty");
            let eff = if tv(&treaty) { treaty.get("effective") } else { treaty };
            if !eff.is_nullish() && n(&eff).is_finite() && (n(&eff) - n(&e.get("start"))).abs() > 1e-6 {
                let at = minute_val(&eff);
                let me = minute_val(&e.get("endY"));
                push_item(out, &assign(&base, o! {
                    "section" => SECTION.effect, "start" => js::min(&[n(&at), n(&me)]), "end" => js::max(&[n(&at), n(&me)]),
                    "b" => f64::from(imp_bits | if le(&at, &me) { 0 } else { 1 }), "c" => 0.0,
                }));
                c_eff += 1.0;
            }
        }
    }
    ctx.notes.set("기간막대", o! { "기간막대" => c_bar, "연대폭" => c_fuzz, "이설" => c_alt, "발효" => c_eff, "짧은막대" => c_short });
    Ok(())
}

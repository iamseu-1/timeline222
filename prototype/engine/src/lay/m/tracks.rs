//! 내보내기 모듈 `tracks` — `prototype/scripts/export/tracks.mjs`(1 ~ 362줄 · SHA-256 앞 12자 `59c98e6aa912`)를 줄 그대로 옮긴다(한 벌 P3 과제 8-틀의 본보기 · 계획 과제 8).
//! 트랙 · 줄 · 민족 묶음 · 분류 · 공통 시대 구분. 2단계의 값(모두 켠 · 자동 밀도의 굳은 자리)에서 출발해 3단계의 새 값(계약 1 · 3 · 4절)을 더한다.
//! 자체 점검: 계약 3절의 식으로 줄을 다시 쌓은 결과가 지금 연표의 _layoutTrack이 낸 값과 1px도 다르지 않아야 한다(다르면 오류 — Node의 assert).
//!
//! 부르는 웹 함수(이미 옮긴 것): `tl._scopePad`(→ [`scope_pad`]) · `tl._figSpan`(→ [`fig_span`]) · `HT.datedAlts`(→ [`dated_alts`]) · `HT.sphereOf`(→ 모델의 `sphereMap` — 2026-10-24 · `tracks.mjs` `fa754953ed78` 347 ~ 362줄: 프로그램에 든 문화권이 없어져 사전은 켠 DLC의 `spheres`뿐).
//! 쓰는 shared: `catNo`(여기서 만듦 — events · labels가 읽음). 읽는 out(늦은 차례): `items`(구역 47 · 50) · `cells` · `periods` · `events` · `variants` · `tracks`.
use super::kit::has_or_err;
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, ji, jn, js_text, jsv, jv};
use crate::lay::js::{self, Map, Set, V};
use crate::lay::model::util::{dated_alts, list, n, nn, or, or_cmp, tv};
use crate::lay::rows::{fig_span, items, G0 as G, HANG_PITCH};
use crate::lay::scope::scope_pad;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 계약 3절의 상수 `G`(tracks.mjs의 G — js/timeline.js의 G와 같은 값 · 매달린 이름표 한 줄 `G.hang`은 timeline.js의 `HANG.pitch`)는 줄 배정의
/// [`G0`] · [`HANG_PITCH`] 하나를 쓴다(과제 Y — tracks · variants · rows가 저마다 두던 표 셋을 하나로. 값이 다르면 아래 자체 점검이 알려 준다).
/// `on` = 트랙 단위로 있고 없는 단 { dynasty, leader, cabinet, organ }(1 · 0).
struct On { dynasty: f64, leader: f64, cabinet: f64, organ: f64 }
/// `n` = 줄 단위 수 { lines, phase, rank, power, real, fig, dep, railLevels }.
struct Nn { lines: f64, phase: f64, rank: f64, power: f64, real: f64, fig: f64, dep: f64, rail_levels: f64 }
/// `stackBand`의 답(`figH`는 JS도 돌려주기만 하고 읽지 않는다).
#[allow(dead_code)]
struct Stack { dynasty_top: f64, phase_top: f64, rank_top: f64, power_top: f64, real_top: f64, leader_top: f64, cabinet_top: f64, text_top: f64, rail_top: f64, fig_top: f64, fig_h: f64, dep_top: f64, organ_top: f64, row_h: f64 }

/// 계약 3절의 '띠 안' 그대로 위에서부터 쌓는다.
/// power · real = 단체 단(설계 7-8 결정 1 A 집권 · 2 A 실권 — 지위 단 아래 · 지도자 칸 위의 줄 단위 덧단 13 + 2, 위 = 집권 · 아래 = 실권) — 없으면 예전 식 그대로
fn stack_band(on: &On, n: &Nn) -> Stack {
    let mut y = G.inset;
    let dynasty_top = y;
    if on.dynasty != 0.0 { y += G.dynasty + G.slot_gap; }
    let phase_top = y;
    y += n.phase * (G.phase + G.phase_gap);
    let rank_top = y;
    if n.rank != 0.0 { y += G.rank + G.rank_gap; }
    let power_top = y;
    if n.power != 0.0 { y += G.power + G.power_gap; }
    let real_top = y;
    if n.real != 0.0 { y += G.power + G.power_gap; }
    let leader_top = y;
    if on.leader != 0.0 { y += G.leader + G.slot_gap; }
    let cabinet_top = y;
    if on.cabinet != 0.0 { y += G.cabinet + G.slot_gap; }
    let text_top = y;
    y += n.lines * G.line;
    let rail_top = y;
    let rail_h = n.rail_levels * G.rail_pitch;
    y += rail_h;
    let fig_top = y + G.slot_gap;
    let fig_h = if n.fig != 0.0 { n.fig * G.figure + (n.fig - 1.0) * G.fig_gap } else { 0.0 };
    let dep_top = if fig_h != 0.0 { fig_top + fig_h + G.slot_gap } else { y + G.slot_gap };
    let organ_top = dep_top + if n.dep != 0.0 { n.dep + G.slot_gap } else { 0.0 };
    let row_h = (if on.organ != 0.0 { organ_top + G.organ } else if n.dep != 0.0 { dep_top + n.dep } else if fig_h != 0.0 { fig_top + fig_h } else { rail_top + rail_h }) + G.inset;
    Stack { dynasty_top, phase_top, rank_top, power_top, real_top, leader_top, cabinet_top, text_top, rail_top, fig_top, fig_h, dep_top, organ_top, row_h }
}

/// 줄 단위 트랙 값(계약 3절 끝 · 6-5절)을 `figWide` 한 정수에 담는 꼴(`packRowValues` — 비트의 뜻은 원본 50 ~ 74줄 주석).
/// 비트 0~2 넉넉하게의 인물 단 수(0~3) · 비트 3~5 그 줄의 기간 막대 단 수 + 1 · 비트 6 기관 칸 · 7 · 8 집권 · 실권 단 · 9~13 매달린 속국 이름표 줄 수(0~31).
pub fn pack_row_values(fig_wide: f64, rail: f64, organ: bool, power: bool, real: bool, hang: f64) -> i64 {
    let i = |x: f64| i64::from(js::to_i32(x));
    (i(fig_wide) & 7) | (((i(rail + 1.0)) & 7) << 3) | (i64::from(organ) << 6) | (i64::from(power) << 7) | (i64::from(real) << 8) | ((i(js::min(&[hang, 31.0])) & 31) << 9)
}

/// 그 줄에 기관 칸이 있는가 — 기관(구역이 아닌 얹힌 정권)이 얹히는 **모든** 상위 줄(지금 연표 _layoutTrack 2-2와 같은 길).
fn organ_rows_of(tr: &V) -> crate::Result<Set> {
    let in_track = Map::new();
    for p in list(&tr.get("periods")) { in_track.set(p.get("uid"), p.clone()); }
    let rows = Set::new();
    let folded = tr.get("foldedRows");
    for p in list(&tr.get("periods")) {
        if !p.bool("_overlay") || p.get("scale").as_str().is_some_and(|s| s == "zone") { continue; }
        for h in items(&p.get("hosts")) {
            let mut host = in_track.get(&h.get("host").get("uid"));
            while tv(&host) && host.bool("_hidden") { host = host.get("_host"); }
            if tv(&host) && !host.get("_row").is_nullish() && !has_or_err(&folded, &host.get("_row"), "tr.foldedRows")? { rows.add(host.get("_row")); }
        }
    }
    Ok(rows)
}

/// 줄마다의 기간 막대 단 수(0~3) — 지금 연표 _layoutTrack 4)의 railLevels 셈을 줄 하나씩 따로 한 것.
fn rail_rows_of(tr: &V) -> Vec<f64> {
    items(&tr.get("eventsByRow")).iter().map(|row| {
        let mut segs: Vec<(f64, f64)> = items(row).into_iter()
            .filter(|e| !tv(&e.get("parentUid")) && (n(&e.get("endY")) - n(&e.get("start")) > 0.0 || tv(&e.get("startRange")) || tv(&e.get("endRange")) || !dated_alts(e).is_empty()))
            .map(|e| {
                let mut ys = vec![n(&e.get("start")), n(&e.get("endY"))];
                if tv(&e.get("startRange")) { ys.extend(list(&e.get("startRange")).iter().map(n)); }
                if tv(&e.get("endRange")) { ys.extend(list(&e.get("endRange")).iter().map(n)); }
                for a in dated_alts(&e) { ys.push(n(&a.get("start"))); ys.push(n(&nn(a.get("end"), a.get("start")))); }
                (js::min(&ys), js::max(&ys))
            }).collect();
        js::sort_by(&mut segs, |a, b| a.0 - b.0);
        let mut ends: Vec<f64> = Vec::new();
        for (s, e) in segs {
            match ends.iter().position(|end| *end < s) { Some(i) => ends[i] = e, None => ends.push(e) }
        }
        js::min(&[3.0, ends.len() as f64])
    }).collect()
}

/// 인물 단의 단 수를 줄마다 — 지금 연표의 _layoutTrack 4)와 같은 규칙(중요도 높은 순 → 시작 순, 최대 figMax단).
/// tr.figures의 lvl은 건드리지 않는다(자동 밀도의 값은 _layoutTrack이 이미 적어 두었다).
fn fig_levels_of(tr: &V, fig_max: usize) -> Vec<f64> {
    let mut rows: Vec<f64> = vec![0.0; items(&tr.get("rowPeriods")).len()];
    if fig_max == 0 { return rows; }
    let by_row = Map::new();
    for x in items(&tr.get("figures")) {
        let r = x.get("row");
        if r.is_nullish() { continue; }
        let mut cur = list(&by_row.get(&r));
        cur.push(x);
        by_row.set(r, crate::lay::model::util::arr(cur));
    }
    for (r, lst) in by_row.entries() {
        let mut levels: Vec<Vec<(f64, f64)>> = (0..fig_max).map(|_| Vec::new()).collect();
        let lvl_of = Map::new();
        let mut sorted = list(&lst);
        js::sort(&mut sorted, |a, b| or_cmp(n(&or(b.get("f").get("importance"), V::Num(2.0))) - n(&or(a.get("f").get("importance"), V::Num(2.0))),
            || or_cmp(n(&a.get("s").get("start")) - n(&b.get("s").get("start")), || n(&a.get("s").get("endY")) - n(&b.get("s").get("endY")))));
        for x in &sorted {
            let (lo, hi) = fig_span(&x.get("s"));
            let free = |l: usize| !levels[l].iter().any(|&(a, b)| a < hi && lo < b);
            let want = lvl_of.get(&x.get("f").get("uid"));
            let l: i64 = if !want.is_nullish() && free(n(&want) as usize) { n(&want) as i64 } else { (0..fig_max).find(|&i| free(i)).map_or(-1, |i| i as i64) };
            if l < 0 { continue; }
            levels[l as usize].push((lo, hi));
            lvl_of.set(x.get("f").get("uid"), l as f64);
            let ri = n(&r);
            if ri >= 0.0 && (ri as usize) < rows.len() { rows[ri as usize] = js::max(&[rows[ri as usize], (l + 1) as f64]); }
        }
    }
    rows
}

/// JS `x || ''`의 JSON 값.
fn or_empty(v: V) -> Value { jsv(&or(v, V::from(""))) }
/// 수 값 배열의 r째(`tr.rowTop[r]`).
fn at(v: &V, r: f64) -> f64 { n(&v.get(&r)) }
/// `tr.<what>.has(r)`(수) — Set · Map이면 그 답, 아니면 JS가 `.has`에서 멈추는 곳이라 오류(`kit::has_or_err` — 16b 검토 ③ Minor 1).
fn has_num(set: &V, r: f64, what: &str) -> crate::Result<bool> { has_or_err(set, &V::Num(r), what) }
/// `Map.get(r) || 0`(수).
fn map_num(map: &V, r: f64) -> f64 { let x = map.as_map().map_or(V::Undef, |m| m.get(&V::Num(r))); if tv(&x) { n(&x) } else { 0.0 } }

/// `contribute(ctx, out)` — 분류 · 공통 시대 구분 · 트랙마다 줄 · 묶음(자체 점검: 계약 3절의 식으로 다시 쌓기).
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let model = ctx.model.clone();

    /* 분류: tl._cats의 순번(i) 차례대로 — 이 배열에서의 자리가 곧 '분류 번호'다(계약 4절). */
    let mut cats: Vec<(V, V)> = tl.get("_cats").as_map().map(Map::entries).unwrap_or_default();
    js::sort_by(&mut cats, |a, b| n(&a.1.get("i")) - n(&b.1.get("i")));
    let cat_no = Map::new();
    ctx.shared.set("catNo", cat_no.clone());
    for (k, (id, c)) in cats.iter().enumerate() {
        cat_no.set(id.clone(), k as f64);
        arr_mut(out, "categories").push(json!({ "key": jsv(id), "name": jsv(&or(c.get("name"), id.clone())), "color": color(&c.get("color"), 0xa4b1b7) }));
    }
    ctx.notes.set("분류_번호가_순번과_다름", cats.iter().enumerate().filter(|(k, (_, c))| n(&c.get("i")) != *k as f64).count() as f64);

    for e in items(&model.get("epochs")) {
        let start = crate::lay::export::minute_or_nan(&e.get("start"));
        let end = crate::lay::export::minute_or_nan(&nn(nn(e.get("endY"), e.get("end")), e.get("start")));
        if !tv(&e.get("track")) && !start.is_nan() && !end.is_nan() && end >= start {
            arr_mut(out, "epochs").push(json!({ "start": jv(start), "end": jv(end), "color": color(&e.get("color"), 0xc8b193), "name": or_empty(e.get("name")) }));
        }
    }

    let mut diffs: Vec<String> = Vec::new(); // 계약 3절의 식과 지금 연표가 다른 곳
    let mut note = |where_: String, want: f64, got: f64| { if (want - got).abs() > 0.001 { diffs.push(format!("{where_}: 계약 {} ≠ 연표 {}", js::num_str(want), js::num_str(got))); } };

    for tr in list(&tl.get("tracks")) {
        let geo0 = tr.get("geo");
        let on = On {
            dynasty: f64::from(n(&geo0.get("dynastyH")) > 0.0), leader: f64::from(n(&geo0.get("leaderH")) > 0.0),
            cabinet: f64::from(n(&geo0.get("cabinetH")) > 0.0), organ: f64::from(n(&geo0.get("organH")) > 0.0),
        };
        let rail_levels = n(&geo0.get("railLevels"));
        let tr_id = js_text(&jsv(&tr.get("id")));
        // 집합 보기의 판 트랙(tr.board)은 원래 트랙이 바뀌는 곳(원래 트랙 칩 — gp.from)만 묶음 틈 — 지금 연표의 _layoutTrack 4) · 5)와 같다(js/timeline.js 'groupStart').
        // 판 트랙이 아니면 지금과 같다(기본 상태의 내보내기에는 판 트랙이 없다 — 1바이트도 달라지지 않는다).
        let group_start = Set::new();
        let groups = items(&tr.get("groups"));
        for gp in groups.iter().filter(|gp| !tv(&tr.get("board")) || tv(&gp.get("from"))) { group_start.add(gp.get("first")); }
        let fig_wide_rows = fig_levels_of(&tr, 3); // 넉넉하게(3단)에서의 인물 단 수
        /* 줄 단위 트랙 값(계약 3절 끝): 민족을 접거나 소속을 펼치면 지금 연표는 트랙 값(기관 칸 · 기간 막대 단 수)을 다시 셈한다.
           저장소에 '모두 편' 값 하나만 두면 접힌 민족 줄에서 띠가 23px 높아진다(실측 9.3) — 줄마다의 값을 함께 실어,
           화면이 '보이는 줄들의 최댓값'으로 다시 셈하게 한다. */
        let organ_rows = organ_rows_of(&tr)?;
        let rail_rows = rail_rows_of(&tr);
        let rows_n = n(&tr.get("rows"));
        let folded_rows = tr.get("foldedRows");
        {
            let mut live: Vec<f64> = Vec::new();
            for r in (0..rows_n as i64).map(|r| r as f64) {
                if !has_num(&folded_rows, r, "tr.foldedRows")? { live.push(r); }
            }
            let mut xs = vec![2.0];
            xs.extend(live.iter().map(|&r| rail_rows.get(r as usize).copied().filter(|x| *x != 0.0).unwrap_or(0.0)));
            note(format!("{tr_id} 기간 막대 단 수"), js::max(&xs), rail_levels);
            note(format!("{tr_id} 기관 칸"), f64::from(live.iter().any(|&r| organ_rows.has(&V::Num(r)))), on.organ);
        }

        let mut rows: Vec<Value> = Vec::new();
        let mut y = G.pad; // 계약 3절로 다시 쌓아 보는 세로 자리
        let (row_top, row_gap, row_hs, row_cut) = (tr.get("rowTop"), tr.get("rowGap"), tr.get("rowHs"), tr.get("rowCut"));
        let (member_rows, under_row_set, hang_lanes, zone_lanes) = (tr.get("memberRows"), tr.get("underRowSet"), tr.get("hangRowLanes"), tr.get("zoneRowLanes"));
        let common_row = n(&tr.get("commonRow"));
        let mut r = 0.0;
        while r < rows_n {
            let geo = { let g = tr.get("geos").get(&r); if tv(&g) { g } else { geo0.clone() } };
            let slot_top = if r == 0.0 { 0.0 } else { at(&row_top, r) - at(&row_gap, r) };
            let slot_end = if r == rows_n - 1.0 { n(&tr.get("height")) } else { at(&row_top, r + 1.0) - at(&row_gap, r + 1.0) };
            let band_top = js::round(at(&row_top, r) - slot_top);
            let at_ = |top: f64, h: f64| -> f64 { if h > 0.0 { js::round(band_top + top) } else { -1.0 } };
            let folded = has_num(&folded_rows, r, "tr.foldedRows")?;
            let member = has_num(&member_rows, r, "tr.memberRows")?;
            let common = r == common_row;
            let row_cats = { let rc = tr.get("rowCats"); if tv(&rc) { let c = rc.get(&r); if tv(&c) { Some(c) } else { None } } else { None } };
            let nn_ = Nn {
                lines: n(&geo.get("lines")),
                phase: js::round(n(&or(geo.get("phaseH"), V::Num(0.0))) / (G.phase + G.phase_gap)),
                rank: f64::from(tv(&geo.get("rankH"))),
                power: f64::from(tv(&geo.get("powerH"))),
                real: f64::from(tv(&geo.get("realH"))),
                fig: n(&or(geo.get("figLevels"), V::Num(0.0))),
                dep: n(&or(geo.get("depH"), V::Num(0.0))),
                rail_levels,
            };
            let hl = if folded { 0.0 } else { map_num(&hang_lanes, r) }; // 매달린 속국 이름표 줄(한 줄 13)
            let zl = map_num(&zone_lanes, r); // 구역 탭 줄(한 줄 20 + 3)
            let zones = zl + map_num(&hang_lanes, r);
            let hem = f64::from(has_num(&under_row_set, r, "tr.underRowSet")?);
            let sp = scope_pad(&tl, &tr, r, r - 1.0);

            /* --- 자체 점검: 계약 3절의 식으로 다시 쌓기 --- */
            let s = stack_band(&on, &nn_);
            let where_ = format!("{tr_id}#{}", js::num_str(r));
            if !folded {
                note(format!("{where_} 왕조 단 위"), s.dynasty_top, n(&geo.get("dynastyTop")));
                note(format!("{where_} 시기 단 위"), s.phase_top, n(&geo.get("phaseTop")));
                note(format!("{where_} 지위 단 위"), s.rank_top, n(&geo.get("rankTop")));
                if nn_.power != 0.0 { note(format!("{where_} 집권 단 위"), s.power_top, n(&geo.get("powerTop"))); }
                if nn_.real != 0.0 { note(format!("{where_} 실권 단 위"), s.real_top, n(&geo.get("realTop"))); }
                note(format!("{where_} 지도자 단 위"), s.leader_top, n(&geo.get("leaderTop")));
                note(format!("{where_} 내각 단 위"), s.cabinet_top, n(&geo.get("cabinetTop")));
                note(format!("{where_} 글줄 위"), s.text_top, n(&geo.get("textTop")));
                note(format!("{where_} 기간 막대 위"), s.rail_top, n(&geo.get("railTop")));
                note(format!("{where_} 인물 단 위"), s.fig_top, n(&geo.get("figTop")));
                note(format!("{where_} 예속 칸 위"), s.dep_top, n(&geo.get("depTop")));
                note(format!("{where_} 기관 단 위"), s.organ_top, n(&geo.get("organTop")));
                note(format!("{where_} 띠 높이"), s.row_h, n(&geo.get("rowH")));
            }
            let cut = if folded { 0.0 } else { (if hl + zl != 0.0 { hl * HANG_PITCH + zl * (G.zone_tab + G.zone_gap) + 3.0 } else { 0.0 }) + if hem != 0.0 { G.hem } else { 0.0 } };
            note(format!("{where_} 줄 밑에 덧붙은 높이"), cut, at(&row_cut, r));
            let h = if folded { G.folded_group } else { s.row_h + cut };
            note(format!("{where_} 줄 높이"), h, at(&row_hs, r));
            let tab = if folded || common { 0.0 } else { G.tab };
            let crosses = group_start.has(&V::Num(r));
            let gap = (if r == 0.0 { 0.0 } else if member && !crosses { G.member_gap } else { G.gap + if crosses { G.group_gap } else { 0.0 } }) + tab + sp;
            note(format!("{where_} 줄 위의 틈"), gap, at(&row_gap, r));
            y += gap;
            note(format!("{where_} 줄의 위 자리"), y, at(&row_top, r));
            y += h;

            let fig_wide_r = if folded { 0.0 } else { fig_wide_rows.get(r as usize).copied().filter(|x| *x != 0.0).unwrap_or(0.0) };
            let rail_r = if folded { 0.0 } else { rail_rows.get(r as usize).copied().filter(|x| *x != 0.0).unwrap_or(0.0) };
            rows.push(json!({
                "height": jv(js::round(slot_end - slot_top)), "bandTop": jv(band_top), "bandH": jv(js::round(n(&geo.get("rowH")))),
                "dynTop": jv(at_(n(&geo.get("dynastyTop")), n(&geo.get("dynastyH")))), "leadTop": jv(at_(n(&geo.get("leaderTop")), n(&geo.get("leaderH")))), "cabTop": jv(at_(n(&geo.get("cabinetTop")), n(&geo.get("cabinetH")))),
                "textTop": jv(js::round(band_top + n(&geo.get("textTop")))), "lines": jsv(&geo.get("lines")), "railTop": jv(js::round(band_top + n(&geo.get("railTop")))), "organTop": jv(at_(n(&geo.get("organTop")), n(&geo.get("organH")))),
                "kind": if folded { 3 } else if common { 2 } else if member { 1 } else { 0 },
                "groupStart": i32::from(crosses), "scopePad": jv(js::round(sp)), "phase": jv(nn_.phase), "rank": jv(nn_.rank),
                "cats": row_cats.as_ref().map_or_else(Vec::new, |rc| list(rc).iter().map(|id| if cat_no.has(id) { jsv(&cat_no.get(id)) } else { jv(0.0) }).collect::<Vec<_>>()),
                "fig": jv(nn_.fig), "dep": jv(if nn_.dep != 0.0 { js::round((nn_.dep + G.slot_gap) / (G.dep + G.slot_gap)) * 13.0 - 1.0 } else { 0.0 }), "zones": jv(zones), "hem": jv(hem), // dep 저장 형식은 옛 12px + 틈 1 그대로; 화면만 새 기하로 환산
                // 넉넉하게의 인물 단 수와 줄 단위 트랙 값을 한 정수에 담는다(packRowValues의 주석 · 계약 6-5절).
                "figWide": pack_row_values(js::max(&[fig_wide_r, nn_.fig]), rail_r, !folded && organ_rows.has(&V::Num(r)), !folded && nn_.power != 0.0, !folded && nn_.real != 0.0, hl),
            }));
            r += 1.0;
        }
        note(format!("{tr_id} 트랙 높이"), js::max(&[y + G.pad, G.folded]), n(&tr.get("height")));

        let groups_out: Vec<Value> = groups.iter().map(|gp| json!({
            "depth": jsv(&gp.get("depth")), "first": jsv(&gp.get("first")), "count": jsv(&gp.get("count")), "name": or_empty(gp.get("name")),
            "color": color(&gp.get("color"), 0xa4b1b7), "kind": if tv(&gp.get("scope")) { 2 } else if tv(&gp.get("culture")) { 1 } else { 0 },
        })).collect();
        arr_mut(out, "tracks").push(json!({
            // key = 트랙의 글자 id(`mw-coast`). 항목 기록(entities)의 `track`이 이 글자라, 대범위 칩이 제 트랙을 찾는다(계약 4절).
            "key": jsv(&tr.get("id")), "name": jsv(&or(tr.get("name"), tr.get("id"))), "color": color(&tr.get("color"), 0xc27a45),
            "dynasty": jv(on.dynasty), "leader": jv(on.leader), "cabinet": jv(on.cabinet), "organ": jv(on.organ), "railLevels": jv(rail_levels),
            "rows": rows, "groups": groups_out,
            // 이 트랙을 처음 말한 DLC의 순번(여러 DLC가 같은 트랙에 얹을 수 있다 — 지금 연표의 addTrack).
            "pack": jsv(&nn(ctx.track_pack.get(&tr.get("id")), V::Num(0.0))),
            // 문화권(리메이크 조각 ② — 켠 DLC의 spheres에 만든 id · 적지 않은 트랙은 빈 글 = 문화권 없음 · 2026-10-23부터 프로그램에 든 문화권은 없음). 모델이 트랙을 문화권 차례로 이미 세워 두었다.
            "sphere": or_empty(tr.get("sphere")),
        }));
    }
    if !diffs.is_empty() {
        return Err(format!("계약 3절의 줄 쌓기와 지금 연표가 다릅니다({}곳):\n  {}", diffs.len(), diffs.iter().take(12).cloned().collect::<Vec<_>>().join("\n  ")).into());
    }
    let total: usize = out["tracks"].as_array().map_or(0, |t| t.iter().map(|x| crate::lay::export::arr_len(x, "rows")).sum());
    ctx.notes.set("줄_쌓기_대조", crate::lay::model::o! { "맞음" => total as f64, "다름" => 0.0 });
    Ok(())
}

/// 늦은 차례(모든 모듈이 항목을 실은 뒤): 구역 47(받침 카드 + 상국 탭 · 연합의 겹 탭)을 실은 줄에 `figWide` 비트 14(위로 솟는 것)를,
/// 구역 50(풀린 그릇의 열쇠표)을 실은 줄에 비트 15(그릇의 줄)를 켠다. 비트 3~5(기간 막대 + 1)가 0인 줄은 옛 저장소로 읽히므로(layout.dart) 켜지 않는다.
pub fn contribute_late(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    spheres_late(ctx, out);
    /// `out.tracks[it.track] && out.tracks[it.track].rows[it.row]`의 자리(없으면 None).
    fn rec_at(out: &Value, it: &Value) -> Option<(usize, usize)> {
        let (t, r) = (jn(&it["track"]), jn(&it["row"]));
        if !(t >= 0.0 && r >= 0.0 && t.fract() == 0.0 && r.fract() == 0.0) { return None; }
        let (t, r) = (t as usize, r as usize);
        out["tracks"].get(t).and_then(|tr| tr["rows"].get(r)).map(|_| (t, r))
    }
    let item_rows = |out: &Value, section: f64| -> Vec<(usize, usize)> { out["items"].as_array().map(|l| l.iter().filter(|it| jn(&it["section"]) == section).filter_map(|it| rec_at(out, it)).collect()).unwrap_or_default() };
    let mut n_ = 0.0;
    for (t, r) in item_rows(out, 47.0) {
        let rec = &mut out["tracks"][t]["rows"][r];
        let fw = ji(&rec["figWide"]);
        if (fw >> 3) & 7 == 0 || fw & (1 << 14) != 0 { continue; }
        rec["figWide"] = jv((fw | (1 << 14)) as f64);
        n_ += 1.0;
    }
    ctx.notes.set("솟는_줄", n_);
    let mut m_ = 0.0;
    for (t, r) in item_rows(out, 50.0) {
        let rec = &mut out["tracks"][t]["rows"][r];
        let fw = ji(&rec["figWide"]);
        if (fw >> 3) & 7 == 0 || fw & (1 << 15) != 0 { continue; }
        rec["figWide"] = jv((fw | (1 << 15)) as f64);
        m_ += 1.0;
    }
    ctx.notes.set("그릇_줄", m_);
    // 비트 16~19: 줄마다 왕조 · 지도자 · 내각 칸이 있는가(위 주석) — 칸이 매인 띠의 줄로 센다.
    let periods: Vec<Value> = out["periods"].as_array().cloned().unwrap_or_default();
    let mut at_: HashMap<String, usize> = HashMap::new(); // new Map(out.periods.map(p => [p.uid, p])) — 같은 uid면 뒤의 것
    for (i, p) in periods.iter().enumerate() { at_.insert(js_text(&p["uid"]), i); }
    let key_of = |p: &Value| format!("{}|{}", js::num_str(jn(&p["track"])), js::num_str(jn(&p["row"])));
    let mut bits: HashMap<String, i64> = HashMap::new();
    for cell in out["cells"].as_array().into_iter().flatten() {
        let kind = jn(&cell["kind"]);
        if !(kind >= 0.0 && kind <= 2.0) { continue; }
        let Some(&pi) = at_.get(&js_text(&cell["period"])) else { continue };
        let key = key_of(&periods[pi]);
        *bits.entry(key).or_insert(0) |= 1 << (16 + kind as i64);
    }
    /* 비트 20 · 띠 look 비트 19 · 20(리메이크 2부 · 감독 결정 '두 장 ㄴ' — 얇은 이름 색줄 + 몸통 띠(칸 뭉치 + 흰 사건 칸)):
       줄에 사건이 있는가(사건 칸을 둘지 — 변형이 옮긴 사건 · 변형에만 있는 사건도) · 띠에 사건 · 칸이 있는가(몸통 띠를 어디까지 그릴지).
       띠를 적지 않은 사건은 같은 줄에서 그 해를 덮는 띠의 것으로 센다. */
    let (mut ev_rows, mut ev_bands, mut cell_bands): (HashSet<String>, HashSet<String>, HashSet<String>) = (HashSet::new(), HashSet::new(), HashSet::new());
    let mut by_row: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, p) in periods.iter().enumerate() { by_row.entry(key_of(p)).or_default().push(i); }
    for e in out["events"].as_array().into_iter().flatten() {
        let key = key_of(e);
        ev_rows.insert(key.clone());
        let band = js_text(&e["band"]);
        if !band.is_empty() && at_.contains_key(&band) { ev_bands.insert(band); }
        else if let Some(pi) = by_row.get(&key).and_then(|l| l.iter().find(|&&i| jn(&periods[i]["start"]) <= jn(&e["start"]) && jn(&e["start"]) <= jn(&periods[i]["end"]))) {
            ev_bands.insert(js_text(&periods[*pi]["uid"]));
        }
    }
    for v in out["variants"].as_array().into_iter().flatten() {
        for mv in v["moves"].as_array().into_iter().flatten() { if jn(&mv["kind"]) == 2.0 { ev_rows.insert(key_of(mv)); } }
    }
    /* 띠 look 비트 21~29: 그 띠가 가진 칸 층(왕조 · 시기 · 지위 · 집권 · 실권 · 지도자 · 내각 · 예속 · 기관) — 몸통 띠를 제 마지막 칸 층까지만 두고
       사건 칸을 그 바로 밑에 붙인다(한 줄에 이은 띠들이 칸 층을 나눠 써도 제 몸통은 제 것만 — 고려 = 색줄 + 무신 정권 단 + 사건 칸). 렌즈 칸(종류 8의 단 0 · 1)은 지도자 · 지위 자리 */
    let floor = |kind: f64| -> Option<i64> { match kind as i64 { 0 => Some(21), 4 => Some(22), 5 => Some(23), 1 => Some(26), 2 => Some(27), 7 => Some(28), 3 => Some(29), _ => None }.filter(|_| kind.fract() == 0.0) };
    let lens_floor = |lane: f64| -> Option<i64> { match lane as i64 { 2 => Some(24), 3 => Some(25), 0 => Some(26), 1 => Some(23), _ => None }.filter(|_| lane.fract() == 0.0) };
    let mut floors: HashMap<String, i64> = HashMap::new();
    for cell in out["cells"].as_array().into_iter().flatten() {
        let period = js_text(&cell["period"]);
        cell_bands.insert(period.clone());
        let bit = if jn(&cell["kind"]) == 8.0 { lens_floor(jn(&cell["lane"])) } else { floor(jn(&cell["kind"])) };
        if let Some(bit) = bit { *floors.entry(period).or_insert(0) |= 1 << bit; }
    }
    for p in out["periods"].as_array_mut().into_iter().flatten() {
        let uid = js_text(&p["uid"]);
        let look = { let l = &p["look"]; if l.is_null() { 0 } else { ji(l) } };
        p["look"] = jv((look | if ev_bands.contains(&uid) { 1 << 19 } else { 0 } | if cell_bands.contains(&uid) { 1 << 20 } else { 0 } | floors.get(&uid).copied().unwrap_or(0)) as f64);
    }
    let mut k_ = 0.0;
    let tracks_n = out["tracks"].as_array().map_or(0, Vec::len);
    for ti in 0..tracks_n {
        let rows_n = out["tracks"][ti]["rows"].as_array().map_or(0, Vec::len);
        for ri in 0..rows_n {
            let rec = &mut out["tracks"][ti]["rows"][ri];
            if rec.is_null() { continue; }
            let fw = ji(&rec["figWide"]);
            if (fw >> 3) & 7 == 0 { continue; }
            let key = format!("{ti}|{ri}");
            rec["figWide"] = jv((fw | bits.get(&key).copied().unwrap_or(0) | (1 << 19) | if ev_rows.contains(&key) { 1 << 20 } else { 0 }) as f64);
            k_ += 1.0;
        }
    }
    ctx.notes.set("칸_줄값", k_);
    ctx.notes.set("두장_몸통", crate::lay::model::o! { "사건줄" => ev_rows.len() as f64, "사건띠" => ev_bands.len() as f64, "칸띠" => cell_bands.len() as f64 });
    Ok(())
}

/// 최상위 `spheres`(리메이크 조각 ②): 쓰인 문화권만 차례대로 `{ id, name, order, count, default }` — count = 그 문화권 트랙에 실린 띠 수(머리 단의 수),
/// default = 처음 펼칠 문화권(첫 DLC — 기본팩이 처음 말한 트랙의 문화권 · 없으면 첫 문화권 — 설계 4-6 #1 A). 문화권이 없는 트랙(판 트랙)은 세지 않는다.
fn spheres_late(ctx: &mut Ctx, out: &mut Value) {
    let tracks: Vec<Value> = out["tracks"].as_array().cloned().unwrap_or_default();
    let sphere_of = |t: &Value| -> Option<String> { match &t["sphere"] { Value::String(s) if !s.is_empty() => Some(s.clone()), _ => None } };
    let mut order: Vec<String> = Vec::new(); // Map의 넣은 차례
    let mut count: HashMap<String, f64> = HashMap::new();
    for t in &tracks { if let Some(s) = sphere_of(t) { if !count.contains_key(&s) { order.push(s.clone()); } count.insert(s, 0.0); } }
    if count.is_empty() { return; }
    for p in out["periods"].as_array().into_iter().flatten() {
        let ti = jn(&p["track"]);
        if ti >= 0.0 && ti.fract() == 0.0 { if let Some(s) = tracks.get(ti as usize).and_then(sphere_of) { if let Some(c) = count.get_mut(&s) { *c += 1.0; } } }
    }
    let first = tracks.iter().find(|t| sphere_of(t).is_some() && jn(&t["pack"]) == 0.0).or_else(|| tracks.iter().find(|t| sphere_of(t).is_some()));
    let first_sphere = first.and_then(sphere_of).unwrap_or_default();
    // HT.sphereOf(id) — 모델의 사전(트랙의 sphere는 모델이 사전에 있는 것만 남겨 모두 찾힌다)
    let map = match ctx.model.get("sphereMap") { V::Map(m) => m, _ => Map::new() };
    let mut spheres: Vec<V> = order.iter().map(|id| map.get(&V::from(id.as_str()))).filter(tv).collect();
    js::sort_by(&mut spheres, |a, b| n(&a.get("order")) - n(&b.get("order")));
    let list: Vec<Value> = spheres.iter().map(|x| {
        let id = js_text(&jsv(&x.get("id")));
        let mut o = json!({ "id": jsv(&x.get("id")), "name": jsv(&x.get("name")), "order": jsv(&x.get("order")) });
        if let Some(c) = count.get(&id) { o["count"] = jv(*c); }
        o["default"] = Value::Bool(id == first_sphere);
        o
    }).collect();
    ctx.notes.set("문화권", list.iter().map(|x| format!("{} {}{}", js_text(&x["name"]), js_text(&x["count"]), if x["default"] == true { " (처음 펼침)" } else { "" })).collect::<Vec<_>>().join(" · "));
    out["spheres"] = Value::Array(list);
}

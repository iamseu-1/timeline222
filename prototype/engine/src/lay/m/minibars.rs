//! 내보내기 모듈 `minibars` — `prototype/scripts/export/minibars.mjs`(1 ~ 69줄 · SHA-256 앞 12자 `d42f01da6da0`)를 줄 그대로 옮긴다(한 벌 P3 과제 8-틀의 둘째 본보기 — 앞자리 11개의
//! Node 출력을 심고 이 모듈 하나만 돌리는 길 · 계획 과제 11).
//! 접힌 트랙 · 접힌 민족 줄의 '가는 막대'(`.tl-mini-bar`)가 쓸 단(위아래 줄)을 띠마다 미리 정해 싣는다. 규칙은 지금 연표의 `_layoutTrack`의 `assignLanes` 그대로.
//! 싣는 곳은 일반 항목 구역 45: `{ref: 띠의 uid, row, start, end, a: laneAll, b: laneRow, color}`. 읽는 shared · out 없음(`tl.tracks`만).
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, jv, minute_num, minute_v};
use crate::lay::js::{self, Map, Set, V};
use crate::lay::model::util::{list, n, or, tv};
use crate::lay::rows::{band_end, band_start, by_start, items};
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 내가 쓰는 일반 항목 구역.
pub const SECTION_MINI: f64 = 45.0;

/// 지금 연표의 assignLanes(2755) 그대로: 목록에 단 번호를 매겨 Map으로 돌려준다.
pub fn assign_lanes(list_: &[V], lanes: usize) -> Map {
    let mut ends: Vec<f64> = Vec::new();
    let out = Map::new();
    let mut sorted = list_.to_vec();
    js::sort(&mut sorted, by_start);
    for p in &sorted {
        let bs = n(&band_start(p));
        let mut lane = ends.iter().position(|end| *end <= bs).map_or(-1i64, |i| i as i64);
        if lane < 0 {
            lane = if ends.len() >= lanes { let m = js::min(&ends); ends.iter().position(|e| *e == m).map_or(-1, |i| i as i64) } else { ends.push(f64::NEG_INFINITY); (ends.len() - 1) as i64 };
        }
        // `ends.indexOf(Math.min(...ends))`가 −1(끝이 NaN)이면 JS는 `ends[-1]`에 적고 다시 읽지 않는다 — 칸에는 적지 않고 단만 −1로 둔다.
        if lane >= 0 { let k = lane as usize; ends[k] = js::max(&[ends[k], n(&band_end(p))]); }
        out.set(p.get("uid"), lane as f64);
    }
    out
}

/// `contribute(ctx, out)` — 트랙마다 띠의 두 단(접힌 트랙용 · 접힌 민족 줄용)을 구역 45로.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let (mut n_bars, mut lane_all, mut lane_row) = (0.0, [0.0; 3], [0.0; 3]);
    for (track, tr) in list(&tl.get("tracks")).iter().enumerate() {
        let shown: Vec<V> = items(&tr.get("periods")).into_iter().filter(|p| !p.bool("_hidden") && !p.bool("_overlay") && !p.bool("_under")).collect();
        let all = assign_lanes(&shown, 3);
        // 접힌 민족 줄: 묶음을 접으면 그 묶음의 줄들이 하나로 합쳐진다 — 묶음마다 제 정권을 모아 한 번 셈한다.
        // 묶음에 들지 않는 줄은 제 줄만으로(그 줄 하나가 접힐 일은 없지만 값이 비지 않게).
        let row = Map::new();
        let done = Set::new();
        let row_periods = tr.get("rowPeriods");
        for gp in items(&tr.get("groups")) {
            let mut l: Vec<V> = Vec::new();
            let (first, count) = (n(&gp.get("first")), n(&gp.get("count")));
            let mut r = first;
            while r < first + count {
                for p in items(&row_periods.get(&r)) { if !p.bool("_hidden") { l.push(p); } }
                done.add(V::Num(r));
                r += 1.0;
            }
            for (uid, lane) in assign_lanes(&l, 3).entries() { row.set(uid, lane); }
        }
        let rows_n = items(&row_periods).len();
        for r in 0..rows_n {
            let rf = r as f64;
            if done.has(&V::Num(rf)) { continue; }
            let l: Vec<V> = items(&row_periods.get(&rf)).into_iter().filter(|p| !p.bool("_hidden")).collect();
            for (uid, lane) in assign_lanes(&l, 3).entries() { row.set(uid, lane); }
        }
        for p in &shown {
            if p.get("_row").is_nullish() { continue; }
            let a = { let x = all.get(&p.get("uid")); if tv(&x) { n(&x) } else { 0.0 } };
            let b = if row.has(&p.get("uid")) { n(&row.get(&p.get("uid"))) } else { 0.0 };
            let s = minute_v(&band_start(p));
            let e = js::max(&[minute_num(&band_start(p)), minute_num(&band_end(p))]);
            arr_mut(out, "items").push(json!({
                "section": SECTION_MINI, "track": track, "row": jv(n(&p.get("_row"))), "row2": jv(n(&p.get("_row"))), "start": s, "end": jv(e), "lod": -1,
                "ref": crate::lay::export::jsv(&p.get("uid")), "name": crate::lay::export::jsv(&or(p.get("name"), V::from(""))), "color": color(&p.get("color"), 0xa4b1b7), "a": jv(a), "b": jv(b), "c": 0, "d": 0, "text2": "",
            }));
            n_bars += 1.0;
            if (0.0..3.0).contains(&a) { lane_all[a as usize] += 1.0; }
            if (0.0..3.0).contains(&b) { lane_row[b as usize] += 1.0; }
        }
    }
    ctx.notes.set("가는막대", crate::lay::model::o! { "막대" => n_bars, "트랙단" => crate::lay::model::util::arr(lane_all.iter().map(|x| V::Num(*x)).collect()), "줄단" => crate::lay::model::util::arr(lane_row.iter().map(|x| V::Num(*x)).collect()) });
    Ok(())
}

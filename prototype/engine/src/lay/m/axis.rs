//! 내보내기 모듈 `axis` — 맨 위 날짜 칸(계약 1절 axis_cells · 4절 axis): 시대 구분 · 연호 · 도읍 · 배도. 한 벌 P3 과제 8(갈래 A) — 줄 그대로 옮긴다.
//!
//! 옮긴 원본:
//! - `prototype/scripts/export/axis.mjs` 1 ~ 110줄 — SHA-256 앞 12자 `883f2b87af64`(저장소의 LF 바이트) → [`contribute`] · [`has_variant`]
//!   (2026-10-24 맞춤 · 리메이크 3단계 과제 3 ~ 6 · 계약 1-1 초안) 82 ~ 109줄 문화권 시대 구분 · 주기 줄(`sphere_lines` kind 2 · 3 — [`super::persons::push_line`]) → `sphere_lines`
//! - `js/timeline.js` 4129 ~ 4319줄 `_buildAxis` · 8870 ~ 8872줄 `_axisTracks` · 89줄 `EPOCH_FOLD` — SHA-256 앞 12자 `8a3b02f5bf7f` → [`build_axis`] · [`axis_tracks`]
//!   (화면 글(HTML 줄 · 모서리 단추 · 간지 줄 이름 · 보조 달력 고르개)은 빼고 **정답지가 쓰는 셈만** — `tl.epochRows` · `eraRows` · `capRows` · `groupRows`와
//!   시대 구분 항목의 `_lane`을 적는다. 보조 달력 줄(`HT.cal.supports(this.altCal)`)은 화면 글뿐이라 뺐다 — `altCal`은 내보내기에서 늘 빈 글.)
//!
//! 부르는 웹 함수(이미 옮긴 것): `HT.atOf`(→ `model::util::at_of`) · `HT.altDated`(→ `model::util::alt_dated` — axis.mjs 10줄이 제 파일에 복사해 둔 것과 같은 식) ·
//! `HT.cellToNow`(연호 칸의 `toNow` → [`crate::lay::web::cells::cell_to_now`] — 과제 Y가 모음 · 처음 옮긴 판은 이 파일에 있었다).
//! 쓰는 · 읽는 shared 없음. 읽는 out 없음(`out.axis`에 싣고 정렬). `tl`에 적는 것(`epochRows` · `eraRows` · `capRows` · `groupRows` · 시대 구분의 `_lane`)은
//! 뒤 모듈이 읽지 않는다(계획 '모듈 사이 의존' 표).
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, jn, jsv, jv, minute_v};
use crate::lay::js::{self, Map, V};
use crate::lay::model::o;
use crate::lay::model::util::{alt_dated, arr, at_of, copy, eq, index_of, is, le, list, lt, n, nn, or, or_cmp, s, sub, t, tv};
use crate::lay::web::cells::cell_to_now;
use super::kit::minute_js;
use super::persons::{push_line, LINE_CYCLE, LINE_EPOCH};
use crate::lay::model::util::is_sphere;
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 날짜 칸 묶음 기억(`axisOpen`)의 열쇠: 있으면 나라별 시대 구분 줄을 한 줄로 접음(timeline.js 89줄 `EPOCH_FOLD`).
const EPOCH_FOLD: &str = "epochFold";

/// 칸 종류 번호(axis.mjs 5줄 `KIND`).
const KIND_EPOCH: f64 = 1.0;
const KIND_ERA: f64 = 2.0;
const KIND_CAPITAL: f64 = 3.0;
const KIND_SECONDARY: f64 = 4.0;
/// 칸의 모습(계약 6-3절 — axis.mjs 7줄 `ST`): 1 시작 미정 · 2 끝 미정 · 4 임시 도읍 · 8 망명 · 16 공동 정도 · 32 이설 있음.
const ST_UNK_S: i64 = 1;
const ST_UNK_E: i64 = 2;
const ST_TEMPORARY: i64 = 4;
const ST_EXILE: i64 = 8;
const ST_CO: i64 = 16;
const ST_VARIANT: i64 = 32;

// ── js/timeline.js `_buildAxis` ──

/// `this._axisTracks()`(timeline.js 8870줄) — 판 트랙이 아닌 트랙.
pub fn axis_tracks(tl: &V) -> Vec<V> { list(&tl.get("tracks")).into_iter().filter(|tr| !tr.bool("board")).collect() }

/// 객체 값에 칸을 쓴다(`x.k = v` — 날짜 칸의 항목은 늘 객체).
fn put(x: &V, k: &str, v: impl Into<V>) { if let V::Obj(o) = x { o.set(k, v); } }

/// `packLanes(list)`(4133 ~ 4142줄) — 시대 구분을 겹치지 않게 갈래에 놓고 항목에 `_lane`을 적는다. 갈래 수(1 이상).
fn pack_lanes(items: &[V]) -> f64 {
    let mut ends: Vec<V> = Vec::new();
    for e in items {
        let start = e.get("start");
        let lane = ends.iter().position(|end| le(end, &start)).unwrap_or(ends.len());
        if lane == ends.len() { ends.push(e.get("endY")); } else { ends[lane] = e.get("endY"); }
        put(e, "_lane", lane as f64);
    }
    js::max(&[1.0, ends.len() as f64])
}

/// `packSpans(list)`(4198 ~ 4208줄) — 정권별 묶음을 시작 · 끝 차례로 정렬하고(제자리) 겹치지 않게 갈래(`lane`)에 놓는다. 갈래 수.
fn pack_spans(items: &mut Vec<V>) -> f64 {
    js::sort(items, |a, b| or_cmp(sub(&a.get("s"), &b.get("s")), || sub(&a.get("e"), &b.get("e"))));
    let mut ends: Vec<V> = Vec::new();
    for po in items.iter() {
        let s_ = po.get("s");
        let lane = ends.iter().position(|end| le(end, &s_)).unwrap_or(ends.len());
        if lane == ends.len() { ends.push(po.get("e")); } else { ends[lane] = po.get("e"); }
        put(po, "lane", lane as f64);
    }
    ends.len() as f64
}

/// `Math.min(...xs)` · `Math.max(...xs)`의 인자(수로 — undefined는 NaN · null은 0).
fn nums(xs: &[V]) -> Vec<f64> { xs.iter().map(n).collect() }

/// `tl._buildAxis()`(timeline.js 4129 ~ 4319줄)의 셈 — 화면 글 없이 `tl.epochRows` · `eraRows` · `capRows` · `groupRows`와 시대 구분의 `_lane`을 채운다.
/// 내보내기의 연표 상태(`contextOf`)는 `show.*`가 모두 켜졌고 `axisOpen`에 연호 · 도읍이 있어(펼침) 묶음 아래 나라별 줄이 선다 —
/// 시대 접기(`epochFold`) · 연호 접기(`foldedEras`) · 배도 펼침(`openCapSec`)은 비어 있지만 그 갈래도 줄 그대로 옮겼다.
pub fn build_axis(ctx: &Ctx) {
    let tl = &ctx.tl;
    let show = tl.get("show");
    let axis_open = tl.get("axisOpen");
    let open_has = |key: &str| axis_open.as_set().is_some_and(|st| st.has(&s(key)));

    /* 시대 구분 띠: 공통(트랙 없음) 줄은 연도 바로 아래, 나라별 줄은 그 나라 연호 줄 옆에 */
    let epoch_rows = js::Arr::default();
    put(tl, "epochRows", epoch_rows.clone());
    /* 시대 접기: 공통 줄까지 모든 시대 구분 줄을 한 줄로 접는다(접힘 기억은 axisOpen의 'epochFold' — 있으면 접힘) */
    let mut epoch_all: Vec<V> = Vec::new();
    if show.bool("epochs") {
        let epochs = list(&tl.get("epochs"));
        let mut common: Vec<V> = epochs.iter().filter(|e| !e.bool("track")).cloned().collect();
        js::sort(&mut common, |a, b| sub(&a.get("start"), &b.get("start")));
        if !common.is_empty() { epoch_all.push(V::Obj(o! { "track" => V::Null, "epochs" => arr(common) })); }
        for tr in list(&tl.get("tracks")) {
            let mut l: Vec<V> = epochs.iter().filter(|e| eq(&e.get("track"), &tr.get("id"))).cloned().collect();
            js::sort(&mut l, |a, b| sub(&a.get("start"), &b.get("start")));
            if !l.is_empty() { epoch_all.push(V::Obj(o! { "track" => tr.clone(), "epochs" => arr(l) })); }
        }
    }
    let epoch_folded = !epoch_all.is_empty() && open_has(EPOCH_FOLD);
    let mut epoch_group: Option<V> = None; // 접힌 시대 구분 줄 — 막대는 _draw의 '접힌 연호·도읍 묶음'이 그림
    let epoch_all_v = arr(epoch_all.clone());
    let epoch_fold_row = |group: &mut Option<V>| {
        *group = Some(V::Obj(o! { "key" => "epochs", "list" => epoch_all_v.clone(), "open" => false, "epochs" => true }));
        // (화면 글: '시대 구분 n줄 ▸' 줄)
    };
    /* 펼친 줄(화면 글은 뺌): 갈래를 놓고 줄 하나 */
    let epoch_row = |d: &V| {
        let track = d.get("track");
        let l = d.get("epochs");
        let lanes = pack_lanes(&list(&l));
        epoch_rows.push(o! { "track" => track, "epochs" => l, "lanes" => lanes });
    };
    let epoch_common = epoch_all.iter().find(|d| !d.bool("track")).cloned();
    if let Some(common) = &epoch_common {
        if epoch_folded { epoch_fold_row(&mut epoch_group); } else { epoch_row(common); }
    }
    // (간지 줄 · 보조 달력 줄 — 화면 글뿐)
    /* 나라별 시대 구분 줄(간지 · 보조 달력 아래) — 접혀 있으면 공통 줄이 없을 때만 여기에 접힌 줄 하나 */
    let epoch_by_track: Vec<V> = epoch_all.iter().filter(|d| d.bool("track")).cloned().collect();
    if !epoch_folded { for d in &epoch_by_track { epoch_row(d); } }
    else if epoch_common.is_none() { epoch_fold_row(&mut epoch_group); }

    /* 연호 · 도읍: 큰 묶음 줄 하나(누르면 펼침) 아래에 나라별 줄 */
    let era_rows = js::Arr::default();
    let cap_rows = js::Arr::default();
    put(tl, "eraRows", era_rows.clone());
    put(tl, "capRows", cap_rows.clone());
    let group_rows = js::Arr::new(epoch_group.into_iter().collect()); // 접은 시대 구분 줄도 같은 묶음 막대로
    put(tl, "groupRows", group_rows.clone());

    // 정권별 묶음을 겹치지 않게 갈래(레인)에 배정 — 명·청처럼 같은 시기에 두 정권이 있으면 두 갈래(pack_spans)
    let mut era_data: Vec<V> = Vec::new();
    if show.bool("eras") {
        for tr in axis_tracks(tl) {
            let mut polities: Vec<V> = Vec::new();
            for p in list(&or(tr.get("axisPeriods"), tr.get("periods"))) {
                if !tv(&p.get("eras")) || !tv(&p.get("eras").get("length")) { continue; }
                // ci = 그 정권의 연호 목록에서의 순번(칸 참조 'era:ci')
                let eras: Vec<V> = list(&p.get("eras")).iter().enumerate().map(|(ci, c)| {
                    let x = copy(c);
                    x.set("end", nn(c.get("end"), p.get("endY")));
                    x.set("endAt", if !c.get("end").is_nullish() { at_of(&ctx.read, c, "end") } else { at_of(&ctx.read, &p, "end") });
                    x.set("toNow", cell_to_now(c, &p));
                    x.set("polity", p.get("name"));
                    x.set("color", p.get("color"));
                    x.set("uid", p.get("uid"));
                    x.set("ci", ci as f64);
                    x.set("pol", p.clone());
                    V::Obj(x)
                }).collect();
                let lo = js::min(&nums(&eras.iter().map(|c| c.get("start")).collect::<Vec<_>>()));
                let hi = js::max(&nums(&eras.iter().map(|c| c.get("end")).collect::<Vec<_>>()));
                polities.push(V::Obj(o! { "eras" => arr(eras), "s" => lo, "e" => hi }));
            }
            if polities.is_empty() { continue; }
            let lanes = pack_spans(&mut polities);
            for po in &polities { for c in list(&po.get("eras")) { put(&c, "lane", po.get("lane")); } }
            let mut eras: Vec<V> = polities.iter().flat_map(|po| list(&po.get("eras"))).collect();
            js::sort(&mut eras, |a, b| sub(&a.get("start"), &b.get("start")));
            let spans: Vec<V> = polities.iter().map(|po| arr(vec![po.get("s"), po.get("e")])).collect();
            era_data.push(V::Obj(o! { "track" => tr.clone(), "eras" => arr(eras), "lanes" => lanes, "spans" => arr(spans) }));
        }
    }

    let mut cap_data: Vec<V> = Vec::new();
    if !matches!(show.get("capitals"), V::Bool(false)) {
        for tr in axis_tracks(tl) {
            let mut entries: Vec<V> = Vec::new();
            let mut sec: Vec<V> = Vec::new();
            for p in list(&or(tr.get("axisPeriods"), tr.get("periods"))) {
                let caps = list(&or(p.get("capitals"), arr(Vec::new())));
                if caps.is_empty() { continue; }
                /* 정도·공동·망명·임시: 임시 도읍 기간은 그때의 정도 칸을 비우고 그 자리에(개경 | 강화 | 개경).
                   그래도 겹치는 칸(공동 정도)은 같은 정권의 다음 갈래로 */
                let seg = |c: &V, s_: V, e_: V| V::Obj(o! { "c" => c.clone(), "s" => s_, "e" => e_ });
                let temps: Vec<V> = caps.iter().filter(|c| is(&c.get("role"), "temporary")).cloned().collect();
                let mut segs: Vec<V> = caps.iter().filter(|c| !is(&c.get("role"), "secondary") && !is(&c.get("role"), "temporary"))
                    .map(|c| seg(c, c.get("start"), c.get("endY"))).collect();
                for tm in &temps {
                    let mut next: Vec<V> = Vec::new();
                    for g in &segs {
                        // `g.e <= t.start || g.s >= t.endY`
                        if le(&g.get("e"), &tm.get("start")) || le(&tm.get("endY"), &g.get("s")) {
                            next.push(g.clone());
                            continue;
                        }
                        if lt(&g.get("s"), &tm.get("start")) { next.push(seg(&g.get("c"), g.get("s"), tm.get("start"))); }
                        if lt(&tm.get("endY"), &g.get("e")) { next.push(seg(&g.get("c"), tm.get("endY"), g.get("e"))); }
                    }
                    segs = next;
                }
                segs.extend(temps.iter().map(|c| seg(c, c.get("start"), c.get("endY"))));
                js::sort(&mut segs, |a, b| or_cmp(sub(&a.get("s"), &b.get("s")), || sub(&a.get("e"), &b.get("e"))));
                let mut subs: Vec<Vec<V>> = Vec::new();
                for g in &segs {
                    // `list[list.length - 1].e <= g.s + 1e-6`
                    let bound = js::add(&g.get("s"), &V::Num(1e-6));
                    let k = match subs.iter().position(|l| le(&l[l.len() - 1].get("e"), &bound)) { Some(k) => k, None => { subs.push(Vec::new()); subs.len() - 1 } };
                    subs[k].push(g.clone());
                }
                for (k, l) in subs.into_iter().enumerate() {
                    let s0 = l[0].get("s");
                    let e_max = js::max(&nums(&l.iter().map(|g| g.get("e")).collect::<Vec<_>>()));
                    entries.push(V::Obj(o! { "p" => p.clone(), "key" => format!("{}|{k}", t(&p.get("uid"))), "segs" => arr(l), "s" => s0, "e" => e_max }));
                }
                // 배도: 같은 묶음(group — 5경·5소경)은 한 칸으로
                let groups = Map::new();
                for c in caps.iter().filter(|c| is(&c.get("role"), "secondary")) {
                    let key = or(c.get("group"), V::from(format!("{}@{}", t(&c.get("city")), t(&c.get("start")))));
                    let gr = groups.get(&key);
                    if tv(&gr) {
                        put(&gr, "start", js::min(&[n(&gr.get("start")), n(&c.get("start"))]));
                        put(&gr, "endY", js::max(&[n(&gr.get("endY")), n(&c.get("endY"))]));
                        if let V::Arr(m) = gr.get("members") { m.push(c.clone()); }
                    } else {
                        groups.set(key, o! {
                            "p" => p.clone(), "name" => or(c.get("group"), c.get("name")), "city" => if tv(&c.get("group")) { s("") } else { c.get("city") },
                            "start" => c.get("start"), "endY" => c.get("endY"), "members" => arr(vec![c.clone()]),
                        });
                    }
                }
                sec.extend(groups.values());
            }
            if entries.is_empty() && sec.is_empty() { continue; }
            let lanes = js::max(&[1.0, pack_spans(&mut entries)]);
            js::sort(&mut sec, |a, b| or_cmp(sub(&a.get("start"), &b.get("start")), || sub(&a.get("endY"), &b.get("endY"))));
            let mut sec_ends: Vec<V> = Vec::new();
            for gr in &sec {
                let start = gr.get("start");
                let lane = sec_ends.iter().position(|end| le(end, &start)).unwrap_or(sec_ends.len());
                if lane == sec_ends.len() { sec_ends.push(gr.get("endY")); } else { sec_ends[lane] = gr.get("endY"); }
                put(gr, "lane", lane as f64);
            }
            let spans: Vec<V> = entries.iter().map(|en| arr(vec![en.get("s"), en.get("e")]))
                .chain(sec.iter().map(|gr| arr(vec![gr.get("start"), gr.get("endY")]))).collect();
            cap_data.push(V::Obj(o! { "track" => tr.clone(), "entries" => arr(entries), "lanes" => lanes, "sec" => arr(sec), "secLanes" => sec_ends.len() as f64, "spans" => arr(spans) }));
        }
    }
    // `group(key, name, list)` — 묶음 줄 하나(화면 글은 뺌): 펼쳐 있으면 참.
    let group = |key: &str, l: &[V]| -> bool {
        if l.is_empty() { return false; }
        let open = open_has(key);
        group_rows.push(o! { "key" => key, "list" => arr(l.to_vec()), "open" => open });
        open
    };
    let folded_eras = tl.get("foldedEras");
    if group("eras", &era_data) {
        for d in &era_data {
            let (tr, eras, lanes) = (d.get("track"), d.get("eras"), d.get("lanes"));
            let folded = n(&lanes) > 1.0 && folded_eras.as_set().is_some_and(|st| st.has(&tr.get("id")));
            era_rows.push(o! { "track" => tr, "eras" => eras, "lanes" => lanes, "folded" => folded });
        }
    }
    let open_cap_sec = tl.get("openCapSec");
    if group("capitals", &cap_data) {
        for d in &cap_data {
            let sec_open = n(&d.get("secLanes")) > 0.0 && open_cap_sec.as_set().is_some_and(|st| st.has(&d.get("track").get("id")));
            put(d, "secOpen", sec_open);
            cap_rows.push(d.clone());
        }
    }
    // (axisEl.innerHTML · --gutter — 화면 글뿐)
}

// ── axis.mjs ──

/// 그 칸에 연대를 말하는 다른 견해(이설)가 있는가(axis.mjs 11줄 `hasVariant` — `HT.altDated`는 10줄의 복사본과 같은 식).
pub fn has_variant(c: &V) -> bool { tv(c) && list(&or(c.get("alternatives"), arr(Vec::new()))).iter().any(alt_dated) }

/// axis.mjs 19 ~ 23줄의 `push` — 분이 둘 다 있고 뒤집히지 않았으면 칸 하나를 싣는다.
#[allow(clippy::too_many_arguments)]
fn push_cell(axis: &mut Vec<Value>, kind: f64, track: f64, lane: &V, s_: &V, e_: &V, name: &V, col: u32, style: i64, strip_no: f64, seq: &V, pack: f64) {
    let (start, end) = (minute_v(s_), minute_v(e_));
    let (Some(a), Some(b)) = (start.as_i64(), end.as_i64()) else { return };
    if b < a { return; }
    axis.push(json!({
        "kind": jv(kind), "track": jv(track), "lane": jsv(&or(lane.clone(), V::Num(0.0))), "start": a, "end": b, "name": jsv(&or(name.clone(), s(""))),
        "color": col, "style": style, "strip": jv(strip_no), "seq": jsv(seq), "pack": jv(pack),
    }));
}

/// `Math.abs(a - b) < 1e-9`(수로).
fn near(a: &V, b: &V) -> bool { (n(a) - n(b)).abs() < 1e-9 }

/// `contribute(ctx, out)` — `tl._buildAxis()`의 줄 · 단 · 갈래를 그대로 날짜 칸(`out.axis`)으로 싣고 정렬한다.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let track_index = ctx.track_index.clone();
    build_axis(ctx); // epochRows · eraRows · capRows를 채운다(연호 · 도읍 묶음은 axisOpen으로 펼쳐 둔 상태)

    let mut strip = 0.0; // 같은 값끼리 이어진 긴 둥근 칸의 번호(0 = 이음 없음)
    let (mut seen_epoch, mut seen_era, mut seen_capital, mut seen_secondary) = (0.0, 0.0, 0.0, 0.0);
    let axis = arr_mut(out, "axis");

    /* 시대 구분: 공통 줄(track −1)과 나라별 줄. 이어 붙지 않으므로 strip 0 */
    for row in list(&or(tl.get("epochRows"), arr(Vec::new()))) {
        let track = if tv(&row.get("track")) { n(&nn(track_index.get(&row.get("track").get("id")), V::Num(-1.0))) } else { -1.0 };
        for (i, e) in list(&row.get("epochs")).iter().enumerate() {
            if tv(&e.get("scope")) { continue; } // 그릇 안 이름표 시대(리메이크 2부 · 설계 3-3)는 날짜 칸이 아니라 그 그릇 윗변의 둘째 탭(scopes.mjs 구역 53)
            push_cell(axis, KIND_EPOCH, track, &or(e.get("_lane"), V::Num(0.0)), &e.get("start"), &e.get("endY"), &e.get("name"), color(&e.get("color"), 0xc8b193),
                if has_variant(e) { ST_VARIANT } else { 0 }, 0.0, &V::Num(i as f64), ctx.pack_of(e));
            seen_epoch += 1.0;
        }
    }

    /* 연호: 한 정권의 연호는 틈 없이 이어진 하나의 긴 둥근 칸 — strip은 정권마다 */
    for row in list(&or(tl.get("eraRows"), arr(Vec::new()))) {
        let track = n(&nn(track_index.get(&row.get("track").get("id")), V::Num(-1.0)));
        let strip_of = Map::new();
        for c in list(&row.get("eras")) {
            if !strip_of.has(&c.get("uid")) { strip += 1.0; strip_of.set(c.get("uid"), strip); }
            let style = (if c.bool("startUnknown") { ST_UNK_S } else { 0 }) | (if c.bool("endUnknown") { ST_UNK_E } else { 0 }) | (if has_variant(&c) { ST_VARIANT } else { 0 });
            push_cell(axis, KIND_ERA, track, &c.get("lane"), &c.get("start"), &c.get("end"), &c.get("name"), color(&c.get("color"), 0xa4b1b7), style,
                n(&strip_of.get(&c.get("uid"))), &c.get("ci"), ctx.pack_of(&or(c.get("p"), c.clone())));
            seen_era += 1.0;
        }
    }

    /* 도읍: 정권의 갈래(en.key)마다 하나의 긴 둥근 칸 — 임시 도읍에 갈린 조각은 같은 strip 안의 칸들.
       칸의 미정은 조각의 끝이 그 도읍의 진짜 시작 · 끝일 때만(지금 연표의 segUnk와 같은 규칙) */
    for row in list(&or(tl.get("capRows"), arr(Vec::new()))) {
        let track = n(&nn(track_index.get(&row.get("track").get("id")), V::Num(-1.0)));
        for en in list(&row.get("entries")) {
            strip += 1.0;
            let no = strip;
            let ep = en.get("p");
            let caps = list(&ep.get("capitals"));
            for g in list(&en.get("segs")) {
                let c = g.get("c");
                let seq = index_of(&caps, &c);
                let (gs, ge) = (g.get("s"), g.get("e"));
                let style = (if c.bool("startUnknown") && near(&gs, &c.get("start")) { ST_UNK_S } else { 0 })
                    | (if (c.bool("endUnknown") || c.bool("endYAuto")) && near(&ge, &c.get("endY")) { ST_UNK_E } else { 0 })
                    | (if is(&c.get("role"), "temporary") { ST_TEMPORARY } else { 0 }) | (if is(&c.get("role"), "exile") { ST_EXILE } else { 0 }) | (if is(&c.get("role"), "co") { ST_CO } else { 0 })
                    // 이설 표식은 그 도읍의 진짜 시작 · 끝이 든 조각에만(지금 연표의 `own` — 한 경계에 선 하나)
                    | (if has_variant(&c) && (near(&gs, &c.get("start")) || near(&ge, &c.get("endY"))) { ST_VARIANT } else { 0 });
                push_cell(axis, KIND_CAPITAL, track, &en.get("lane"), &gs, &ge, &or(c.get("label"), c.get("name")), color(&ep.get("color"), 0xa4b1b7), style, no, &V::Num(seq), ctx.pack_of(&ep));
                seen_capital += 1.0;
            }
        }
        /* 배도(별도 · 5경 · 소경): 묶음 하나가 칸 하나 — 도읍 줄 아래의 제 갈래(lane) */
        for gr in list(&or(row.get("sec"), arr(Vec::new()))) {
            let gp = gr.get("p");
            let members = list(&gr.get("members"));
            let seq = index_of(&list(&gp.get("capitals")), &members.first().cloned().unwrap_or_default());
            let style = (if members.iter().any(|c| c.bool("startUnknown") && eq(&c.get("start"), &gr.get("start"))) { ST_UNK_S } else { 0 })
                | (if members.iter().any(|c| c.bool("endUnknown") && eq(&c.get("endY"), &gr.get("endY"))) { ST_UNK_E } else { 0 })
                | (if members.iter().any(has_variant) { ST_VARIANT } else { 0 });
            strip += 1.0; // `++strip`는 push를 부르기 전에 센다(칸이 실리지 않아도)
            push_cell(axis, KIND_SECONDARY, track, &gr.get("lane"), &gr.get("start"), &gr.get("endY"), &gr.get("name"), color(&gp.get("color"), 0xa4b1b7), style, strip, &V::Num(seq), ctx.pack_of(&gp));
            seen_secondary += 1.0;
        }
    }

    js::sort_by(axis, |a, b| or_cmp(jn(&a["start"]) - jn(&b["start"]), || or_cmp(jn(&a["kind"]) - jn(&b["kind"]),
        || or_cmp(jn(&a["track"]) - jn(&b["track"]), || or_cmp(jn(&a["lane"]) - jn(&b["lane"]), || jn(&a["seq"]) - jn(&b["seq"]))))));
    ctx.notes.set("날짜_칸", o! { "시대구분" => seen_epoch, "연호" => seen_era, "도읍" => seen_capital, "배도" => seen_secondary });
    sphere_lines(ctx, out);
    Ok(())
}

/// 리메이크 3단계(계약 1-1 초안 · 설계 3-11 ⑤ — 세계사 장면 5 · axis.mjs 82 ~ 109줄): 문화권 단위의 줄을 `sphere_lines`에.
/// kind 2 = 문화권 시대 구분 — 트랙 없이 sphere를 적은 시대 구분(트랙을 함께 적은 것은 트랙 우선이라 싣지 않음). 날짜 칸(공통 줄)에도 지금처럼 그대로 있다.
/// kind 3 = 문화권 주기 줄 — 켠 DLC 차례로 yearCycles의 문화권 줄, 문화권마다 첫 것 하나(HT.f4Preview와 같음) · start · end = 0 ·
/// data = {names, start, label} 또는 {era, from, step, label}. 모델이 모르는 문화권(`HT.isSphere` — 모델의 sphereMap)의 것은 싣지 않는다.
fn sphere_lines(ctx: &mut Ctx, out: &mut Value) {
    let sphere_map = match ctx.model.get("sphereMap") { V::Map(m) => m, _ => Map::new() };
    let known = |id: &V| tv(id) && is_sphere(&sphere_map, id);
    // `Number(x) || 0` — NaN · 0 · −0은 0
    let or0 = |x: f64| if x == 0.0 || x.is_nan() { 0.0 } else { x };
    let (mut epochs, mut cycles) = (0.0, 0.0);
    for e in list(&or(ctx.model.get("epochs"), arr(Vec::new()))) {
        if !tv(&e) || !tv(&e.get("sphere")) || tv(&e.get("track")) || !known(&e.get("sphere")) { continue; }
        // `start == null || end == null || end < start` — Date 범위 밖(NaN)은 실리고 JSON에서 null(JS와 같음)
        let (Some(start), Some(end)) = (minute_js(&e.get("start")), minute_js(&nn(e.get("end"), e.get("endY")))) else { continue };
        if end < start { continue; }
        push_line(out, json!({
            "kind": jv(LINE_EPOCH), "sphere": jsv(&e.get("sphere")), "start": jv(start), "end": jv(end), "name": jsv(&or(e.get("name"), s(""))),
            "uid": jsv(&or(e.get("uid"), s(""))), "color": color(&e.get("color"), 0), "data": "", "pack": jv(ctx.pack_of(&e)),
        }));
        epochs += 1.0;
    }
    let took = js::Set::new();
    for (i, p) in ctx.packs.iter().enumerate() {
        let yc = p.get("yearCycles");
        if !matches!(yc, V::Arr(_)) { continue; }
        for c in list(&yc) {
            if !tv(&c) || !tv(&c.get("sphere")) || took.has(&c.get("sphere")) || !known(&c.get("sphere")) { continue; }
            let names = c.get("names");
            let data = if matches!(names, V::Arr(_)) && !list(&names).is_empty() {
                let names: Vec<V> = list(&names).iter().map(|x| V::Str(js::to_str(x))).collect();
                V::Obj(o! { "names" => arr(names), "start" => or0(js::to_num(&c.get("start"))), "label" => or(c.get("label"), s("")) })
            } else if tv(&c.get("era")) {
                let era = V::Str(js::to_str(&c.get("era")));
                V::Obj(o! { "era" => era.clone(), "from" => or0(js::to_num(&c.get("from"))), "step" => js::max(&[1.0, { let x = or0(js::to_num(&c.get("step"))); if x == 0.0 { 1.0 } else { x } }]), "label" => or(c.get("label"), era) })
            } else { continue };
            took.add(c.get("sphere"));
            push_line(out, json!({
                "kind": jv(LINE_CYCLE), "sphere": jsv(&c.get("sphere")), "start": 0, "end": 0, "name": jsv(&data.get("label")), "uid": "", "color": 0,
                "data": js::stringify(&data), "pack": i,
            }));
            cycles += 1.0;
        }
    }
    if epochs != 0.0 || cycles != 0.0 { ctx.notes.set("문화권_줄", o! { "시대구분" => epochs, "주기" => cycles }); }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_to_now_follows_core_js() {
        let p = V::Obj(o! { "ongoing" => true });
        assert!(cell_to_now(&V::Obj(o! { "start" => 1.0 }), &p));
        assert!(!cell_to_now(&V::Obj(o! { "start" => 1.0, "end" => 5.0 }), &p));
        assert!(cell_to_now(&V::Obj(o! { "end" => 5.0, "endPolity" => true }), &p));
        assert!(!cell_to_now(&V::Obj(o! { "endYNext" => true }), &p));
        assert!(!cell_to_now(&V::Obj(o! { "endUnknown" => true, "endPolity" => true }), &p));
        assert!(!cell_to_now(&V::Obj(o! { "start" => 1.0 }), &V::Obj(o! { "ongoing" => false })));
    }

    #[test]
    fn pack_lanes_matches_find_index() {
        let e = |a: f64, b: f64| V::Obj(o! { "start" => a, "endY" => b });
        let l = vec![e(0.0, 10.0), e(5.0, 12.0), e(10.0, 20.0), e(11.0, 13.0)];
        assert_eq!(pack_lanes(&l), 3.0); // 넷째(11 ~ 13)는 앞 갈래 둘 다 끝나지 않아(20 · 12 > 11) 셋째 갈래
        assert_eq!(l.iter().map(|x| n(&x.get("_lane"))).collect::<Vec<_>>(), vec![0.0, 1.0, 0.0, 2.0]);
        assert_eq!(pack_lanes(&[]), 1.0);
    }
}

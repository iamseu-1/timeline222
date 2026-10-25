//! 내보내기 모듈 `lens` — `prototype/scripts/export/lens.mjs`(1 ~ 247줄 · SHA-256 앞 12자 `51c3b6c4e201`)를 줄 그대로 옮긴다(한 벌 P3 과제 15 · 갈래 E).
//! 렌즈(주제 보기)의 새 앱 몫 — 렌즈 칸을 미리 셈해 변형 kind 4 `theme:<주제 id>`로 싣는다: ① 렌즈마다 칸 종류 8 + 구역 43 + 가림(`hides`) ·
//! ② 렌즈 켬 줄 배치(`themeLens`를 켜고 모든 트랙을 다시 배치해 자체 점검한 뒤 `themeLens = null`로 되돌려 다시 배치 — 줄 배정의 렌즈 길 `HT.lensAny` ·
//! 지도자 자리의 첫 견줌) · ③ 항목 기록 `themes`의 `x_lens`(`js::parse` → 열쇠 더함 → `js::stringify` — 넣은 차례 그대로). 앞선 것은 고치지 않고 뒤에 덧붙이기만 한다.
//! 읽는 shared: `bandOf`(없으면 오류 — Node의 assert). 읽는 out: `cells` · `periods` · `events` · `entities`(themes 기록) · `variants`(없으면 만듦).
//!
//! 함께 옮긴 웹 함수(`js/core.js` — SHA-256 앞 12자 `9c786cf58566`): 2001 ~ 2003줄 `HT.THEME_HINTS` · `HT.themeHint` → [`theme_hint`] ·
//! 2178 ~ 2186줄 `lensInstCells` → [`lens_inst_cells`] · 2189 ~ 2202줄 `HT.lensCellsOf` → [`lens_cells_of`](정권마다의 기억 `lensMemo`는 두지 않음 — 답이 같고 이 모듈은
//! 칸을 읽기만 한다) · 2206줄 `HT.lensEventHit` → [`lens_event_hit`] · 2208줄 `HT.lensHasData` → [`lens_has_data`]. 이미 옮긴 것: `HT.lensAny`([`lens_any`]) ·
//! `groupSpanCells`([`group_span_cells`] — 붕당 렌즈의 칸) · `HT.leaderLabel`(기본 꼴 — [`leader_label`]) · `variants.mjs`의 `G`(같은 값 — [`G0`]).
//! 모듈의 `styleWith` · `cellStyle` · `lodOf` · `ST` · `STRIP` 사본과 도움은 strips · power와 몸이 같아 [`super::kit`]의 하나를 부른다(과제 Y).
//! 알려진 차이(뜻 없는 자료에서만 — 과제 5a와 같은 꼴): 웹의 `HT.THEME_HINTS[t.id]`는 `constructor` 같은 `Object.prototype` 이름에서 함수를 돌려주어 `hint`가 JSON에서 빠지고,
//! Rust는 적힌 여덟 낱말만 찾는다(주제 id가 그런 이름일 때만 갈림).
use super::kit::{cell_style, finite_or, jis, jtruthy, lod_of, minute_of, st, strip, style_with, BAND_SHIFT, KIND_COMMON, SECTION_ITEM};
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, jn, jsv, jv, text_or_empty};
use crate::lay::m::kit::{band_at, band_or_err};
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, eq, fault, is, leader_label, list, n, nn, ob, or, or_cmp, s, sub, tv};
use crate::lay::rows::{group_span_cells, items, lens_any, G0};
use crate::lay::track::layout_all;
use serde_json::{json, Value};
use std::collections::HashMap;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 변형 번호(계약 부록 가-9의 예약): 4 렌즈. variants.mjs의 1 소속 펼치기 · 2 대범위와 같은 표에 든다.
pub const VARIANT_KIND_THEME: f64 = 4.0;
/// 공용 칸 단(칸 종류 8 — [`KIND_COMMON`])의 단 갈래(style 27~29) — `LENS_BAND = { inst: 1, group: 2, rank: 3, leader: 4 }`.
pub const LENS_BAND_INST: i32 = 1;
pub const LENS_BAND_GROUP: i32 = 2;
pub const LENS_BAND_RANK: i32 = 3;
/// 지도자(4)는 power도 읽어(렌즈가 내린 지도자 칸의 명목 비트) `kit`에 둔다(16b 검토 ③ Minor 8 — power ↔ lens 층을 끊음).
pub use super::kit::LENS_BAND_LEADER;
/// `LENS_LANE = { leader: 0, rank: 1, power: 2 }`.
pub const LENS_LANE_LEADER: f64 = 0.0;
pub const LENS_LANE_RANK: f64 = 1.0;
pub const LENS_LANE_POWER: f64 = 2.0;
/// 계약 3절의 지도자 칸 높이 + 틈(렌즈 켬 배치에서 지도자 자리가 새로 생긴 줄이 늘어나는 만큼 — `G`는 [`crate::lay::rows::G0`] 하나).
const LEADER_SLOT: f64 = G0.leader + G0.slot_gap;

// ── 웹 함수(js/core.js) ──

/// `HT.THEME_HINTS` — 내장 주제의 한마디.
const THEME_HINTS: [(&str, &str); 8] = [
    ("system", "나라의 짜임"), ("faction", "집권한 단체"), ("law", "법 · 법전"), ("election", "뽑는 방법"),
    ("ideology", "기준 이념"), ("military", "병제"), ("tax", "세금 거두는 법"), ("selection", "관리 뽑는 법"),
];
/// `HT.themeHint(t)` — 렌즈 차림표의 한마디 설명: 주제의 갈래(kind — DLC가 적음) → 내장 주제의 한마디(없으면 '').
pub fn theme_hint(t: &V) -> V {
    if !tv(t) { return s(""); }
    let kind = t.get("kind");
    if tv(&kind) { return kind; }
    let id = js::to_str(&t.get("id"));
    match THEME_HINTS.iter().find(|(k, _)| id == *k) { Some((_, h)) => s(h), None => s("") }
}
/// `lensInstCells(list)` — 제도 렌즈의 칸: 그 나라 · 그 주제의 제도들(갈래마다 나눠 적은 제도도)의 칸을 날짜 차례로 — 칸마다 그 제도의 uid · 갈래 · 갈래 색.
pub fn lens_inst_cells(l: &[V]) -> Vec<V> {
    let mut out: Vec<V> = Vec::new();
    for o in l {
        for sp in items(&o.get("spanList")) {
            out.push(V::Obj(o! {
                "name" => sp.get("name"), "start" => sp.get("start"), "end" => sp.get("end"), "startUnknown" => sp.bool("startUnknown"), "endUnknown" => sp.bool("endUnknown"),
                "guess" => sp.bool("guess"), "note" => or(sp.get("note"), s("")), "color" => o.get("color"), "fam" => or(o.get("family"), s("")), "famKey" => or(o.get("familyKey"), s("")),
                "uid" => o.get("uid"), "item" => o.clone(), "ii" => sp.get("ii"),
            }));
        }
    }
    js::sort(&mut out, |a, b| or_cmp(sub(&a.get("start"), &b.get("start")), || sub(&a.get("end"), &b.get("end"))));
    out
}
/// `HT.lensCellsOf(p, id)` — 정권 p의 렌즈 칸 → `{ src, cells }`: src 'inst' 제도 칸 · 'group' 붕당의 집권 칸 · 'rank' 체제를 대신하는 지위 변천(cells = p.rankSpans 그대로) · '' 자료 없음.
pub fn lens_cells_of(p: &V, id: &V) -> Obj {
    if !tv(p) || !tv(id) { return o! { "src" => "", "cells" => arr(Vec::new()) }; }
    let inst: Vec<V> = items(&p.get("institutionList")).into_iter().filter(|o| eq(&o.get("themeId"), id)).collect();
    let gc = if is(id, "faction") { group_span_cells(p, "power") } else { Vec::new() };
    if !gc.is_empty() { return o! { "src" => "group", "cells" => arr(gc) }; }
    if !inst.is_empty() { return o! { "src" => "inst", "cells" => arr(lens_inst_cells(&inst)) }; }
    let rs = p.get("rankSpans");
    if is(id, "system") && tv(&rs) && tv(&rs.get("length")) { return o! { "src" => "rank", "cells" => rs }; }
    o! { "src" => "", "cells" => arr(Vec::new()) }
}
/// `HT.lensEventHit(e, id)` — 사건이 그 렌즈의 주제인지: 주제 꼬리표 + 법률 렌즈는 법 규격이 있는 사건, 선거제도 렌즈는 선거 규격이 있는 사건도.
pub fn lens_event_hit(e: &V, id: &V) -> bool {
    tv(e) && tv(id) && (items(&e.get("themeRefs")).iter().any(|r| eq(&r.get("id"), id)) || (is(id, "law") && e.bool("law")) || (is(id, "election") && e.bool("election")))
}
/// `HT.lensHasData(m, id)` — 그 렌즈로 그릴 자료가 모델에 하나라도 있는지(차림표의 '자료 없음' 표시).
/// `(m.periods || []).some(…) || (m.events || []).some(…)` — 참인데 배열이 아니면(글 · Map · Set · 객체) JS는 `.some`에서 TypeError: 잘못으로 남긴다
/// (16b 틀 손질 검토 — 모듈의 사건 훑기는 for…of라 Map · Set도 받으므로 여기서 조용히 '자료 없음'이 되지 않게).
pub fn lens_has_data(m: &V, id: &V) -> bool {
    tv(m) && tv(id) && (some_of(&m.get("periods"), "m.periods", |p| !is(&lens_cells_of(p, id).get("src"), "")) || some_of(&m.get("events"), "m.events", |e| lens_event_hit(e, id)))
}
/// `(x || []).some(f)` — 거짓 값이면 빈 목록, 배열이면 그 원소, 그 밖이면 잘못(JS라면 `.some`에서 TypeError)을 남기고 거짓.
fn some_of(x: &V, what: &str, f: impl Fn(&V) -> bool) -> bool {
    match x {
        _ if !tv(x) => false,
        V::Arr(_) => items(x).iter().any(f),
        other => { fault(format!("{what}가 배열이 아닙니다({} — JS라면 .some에서 TypeError)", js::type_of(other))); false }
    }
}

// ── 모듈 ──

/// `swatchesOf(model, t)` — 렌즈 차림표의 갈래 견본(js/lens-ui.js의 swatches 그대로) — `{ t 제목, l [[이름, 0xRRGGBB]] }` 또는 null.
fn swatches_of(model: &V, t: &V) -> V {
    let seen = Map::new();
    let ii = model.get("institutionIndex");
    // JS `model.institutionIndex.byTheme.get(t.id)` — byTheme이 Map이 아니면 TypeError: 잘못으로 남긴다(과제 Y — 갈래 E '조용히 이어 가는 길')
    let by_theme = if tv(&ii) { match ii.get("byTheme") { V::Map(m) => m.get(&t.get("id")), other => { fault(format!("institutionIndex.byTheme이 Map이 아닙니다({} — JS라면 .get에서 TypeError)", js::type_of(&other))); V::Undef } } } else { V::Undef };
    for o in items(&by_theme) {
        if tv(&o.get("family")) && !seen.has(&o.get("familyKey")) { seen.set(o.get("familyKey"), o! { "name" => o.get("family"), "color" => o.get("color"), "start" => o.get("start") }); }
    }
    if !seen.is_empty() {
        let mut vals = seen.values();
        js::sort(&mut vals, |a, b| sub(&a.get("start"), &b.get("start")));
        let l: Vec<V> = vals.iter().map(|f| arr(vec![f.get("name"), V::Num(f64::from(color(&f.get("color"), 0xa4b1b7)))])).collect();
        return V::Obj(o! { "t" => format!("{}의 갈래 — 같은 색은 나라 너머 같은 갈래", js::to_str(&t.get("name")).as_str()).as_str(), "l" => arr(l) });
    }
    if !is(&t.get("id"), "faction") { return V::Null; }
    let gs: Vec<V> = items(&model.get("groups")).into_iter().filter(|g| {
        !is(&g.get("type"), "coalition") && !is(&g.get("type"), "regime") && !items(&g.get("powerSpans")).is_empty() && items(&g.get("withinList")).iter().any(|w| tv(&w.get("polity")))
    }).collect();
    if gs.is_empty() { return V::Null; }
    let l: Vec<V> = gs.iter().map(|g| arr(vec![g.get("name"), V::Num(f64::from(color(&g.get("color"), 0xa4b1b7)))])).collect();
    V::Obj(o! { "t" => format!("{} — 칸 색은 집권한 단체의 색 · 두 색은 연정", js::to_str(&t.get("name")).as_str()).as_str(), "l" => arr(l) })
}

/// 렌즈 켬 배치의 자체 점검(lens.mjs 106 ~ 116줄 — `try` 안): 지도자 자리 있음이 기대와 같고, 자리가 새로 생긴 트랙만 줄마다 `LEADER_SLOT`만큼 는다.
fn check_lens_layout(ctx: &mut Ctx, before: &[(bool, Vec<V>)], track_has: &[bool]) -> crate::Result<()> {
    layout_all(ctx)?;
    for (i, tr) in list(&ctx.tl.get("tracks")).iter().enumerate() {
        let (b_leader, b_row_hs) = (&before[i].0, &before[i].1);
        let want = *b_leader || track_has[i];
        let now = n(&tr.get("geo").get("leaderH")) > 0.0;
        if now != want {
            return Err(format!("렌즈 켬 배치: 트랙 {}의 지도자 자리가 {now}(기대 {want})", js::to_str(&tr.get("id")).as_str()).into());
        }
        // 지도자 자리가 새로 생긴 트랙만 줄마다 LEADER_SLOT(현재 22 + 3)만큼 늘고(접힌 줄 · 그 밖 줄은 0 그대로), 나머지 트랙은 1px도 그대로다.
        let grow = !*b_leader && track_has[i];
        for (r, h) in items(&tr.get("rowHs")).iter().enumerate() {
            let old = b_row_hs.get(r).cloned().unwrap_or_default();
            let ok = if grow { js::strict_eq(h, &old) || js::strict_eq(h, &js::add(&old, &V::Num(LEADER_SLOT))) } else { js::strict_eq(h, &old) };
            if !ok {
                return Err(format!("렌즈 켬 배치: 트랙 {} 줄 {r}의 높이 {} → {}", js::to_str(&tr.get("id")).as_str(), js::to_str(&old).as_str(), js::to_str(h).as_str()).into());
            }
        }
    }
    Ok(())
}

/// `contribute(ctx, out)` — ② 렌즈 켬 줄 배치 대조 → ① 렌즈마다 변형 하나 → ③ 항목 기록 themes에 `x_lens`.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let model = ctx.model.clone();
    let band_of = ctx.shared.get("bandOf");
    if !tv(&band_of) { return Err("렌즈: 띠 모듈(bands)이 먼저 돌아야 합니다".into()); }
    let Some(band_of) = band_of.as_map().cloned() else { return Err("렌즈: shared.bandOf가 Map이 아닙니다(JS라면 TypeError)".into()) };
    let cell_notes = o! { "제도" => 0.0, "단체" => 0.0, "연정" => 0.0, "지위대신" => 0.0, "내린지도자" => 0.0 };
    let notes = o! { "렌즈" => 0.0, "칸" => cell_notes.clone(), "가림" => 0.0, "딸린항목" => 0.0, "자리트랙" => 0.0, "사건" => 0.0 };
    let add_note = |o: &Obj, k: &str, x: f64| o.set(k, n(&o.get(k)) + x);
    let themes = items(&model.get("themes"));
    if themes.is_empty() {
        ctx.notes.set("렌즈", notes);
        return Ok(());
    }

    // ── ② 렌즈 켬 줄 배치: 지도자 자리가 있는 트랙(HT.lensAny인 정권이 있는 트랙) — 줄 배정(_layoutTrack)을 렌즈 켬으로 한 번 더 돌려 대조한다 ──
    let tracks = list(&tl.get("tracks"));
    let track_has: Vec<bool> = tracks.iter().map(|tr| items(&tr.get("periods")).iter().any(lens_any)).collect();
    let slot: Vec<V> = tracks.iter().zip(&track_has).filter(|(_, h)| **h).map(|(tr, _)| tr.get("id")).collect();
    notes.set("자리트랙", slot.len() as f64);
    if !slot.is_empty() {
        let before: Vec<(bool, Vec<V>)> = tracks.iter().map(|tr| (n(&tr.get("geo").get("leaderH")) > 0.0, list(&tr.get("rowHs")))).collect();
        let tlo = ob(&tl);
        let was = tl.get("themeLens");
        tlo.set("themeLens", o! { "id" => "*", "name" => "*", "color" => "#a4b1b7" }); // 렌즈 켬 배치는 themeLens가 있는지만 본다(설계 10-3)
        let tried = check_lens_layout(ctx, &before, &track_has);
        // 렌즈 켬 배치가 남긴 잘못 — JS라면 try 안에서 이미 던졌을 것: 되돌린 배치의 잘못과 가르려고 먼저 거둔다(boards의 `board_one`과 같은 꼴 — 16b 틀 손질 검토)
        let pending = crate::lay::model::util::take_fault();
        // finally: 되돌리고 다시 배치(되돌림 = null — 처음에 없던 열쇠도 null로 남는다 · Node와 같음). 되돌린 배치가 실패하면 그 오류가 앞의 것을 덮는다(JS finally).
        tlo.set("themeLens", or(was, V::Null));
        layout_all(ctx)?;
        super::kit::try_finally(tried, pending, crate::lay::model::util::take_fault(), "렌즈 켬 배치", "렌즈 켬 배치: 되돌린 배치")?;
    }

    // ── ① 렌즈마다 변형 하나: 칸 종류 8 + 구역 43 + 가림 ──
    let mut cells_of_band: HashMap<String, Vec<usize>> = HashMap::new(); // 띠 uid → 그 띠의 칸 자리(앞선 모듈이 실은 것 — 변형 판까지)
    for (i, c) in out["cells"].as_array().into_iter().flatten().enumerate() {
        if let Value::String(pd) = &c["period"] { cells_of_band.entry(pd.clone()).or_default().push(i); }
    }
    if !jtruthy(&out["variants"]) { out["variants"] = json!([]); }
    let lens_of = Map::new(); // 주제 id → x_lens.themes의 칸
    let ev_hit = Map::new(); // 주제 id → 그 주제의 사건 uid(모델)
    for t in &themes { ev_hit.set(t.get("id"), Set::new()); }
    // JS `for (const e of model.events || [])` — 거짓이면 빈 것 · 배열 · 글 · Map · Set은 JS가 돈다(js::for_of — 16b 넘겨받은 틀 손질) · 그 밖의 참값은 TypeError(잘못으로)
    let events = model.get("events");
    let event_list = if !tv(&events) { Vec::new() } else { js::for_of(&events).unwrap_or_else(|| { fault(format!("model.events가 순회되지 않습니다({})", js::type_of(&events))); Vec::new() }) };
    for e in event_list {
        for t in &themes {
            if lens_event_hit(&e, &t.get("id")) { if let V::Set(hit) = ev_hit.get(&t.get("id")) { hit.add(e.get("uid")); } }
        }
    }

    for t in &themes {
        let key = format!("theme:{}", js::to_str(&t.get("id")).as_str());
        let mut v_cells: Vec<Value> = Vec::new();
        let mut v_items: Vec<Value> = Vec::new();
        let mut hides: Vec<Value> = Vec::new();
        let count = o! { "제도" => 0.0, "단체" => 0.0, "연정" => 0.0, "지위대신" => 0.0, "내린지도자" => 0.0 };
        for (track_index, tr) in list(&tl.get("tracks")).iter().enumerate() {
            for p in items(&tr.get("periods")) {
                if p.bool("_overlay") || !band_of.has(&p.get("uid")) { continue; }
                let lc = lens_cells_of(&p, &t.get("id"));
                let src = lc.get("src");
                if !tv(&src) { continue; } // 자료 없는 나라: 지도자 칸이 그대로 남는다(앱이 .4로)
                // `out.periods[bandOf.get(p.uid)]` — 범위 밖이면 undefined(그 띠를 읽는 put에서 JS는 TypeError → band_or_err)
                let band_v = band_at(out, &band_of.get(&p.get("uid")));
                let geo = { let g = match p.get("_row") { V::Num(r) if r >= 0.0 && r.fract() == 0.0 => tr.get("geos").get(&r), _ => V::Undef }; or(g, tr.get("geo")) };
                let uid = p.get("uid");
                // 칸 하나를 띠 안으로 잘라 싣는다(strips.mjs의 put과 같은 자르기). 실었으면 그 칸의 (start, end).
                let mut put = |v_cells: &mut Vec<Value>, lane: f64, sv: Option<f64>, ev: Option<f64>, name: &V, style: i32, col: u32| -> crate::Result<Option<(f64, f64)>> {
                    let (Some(sv), Some(ev)) = (sv, ev) else { return Ok(None) };
                    if !tv(name) { return Ok(None); }
                    let band = band_or_err(&band_v, &p)?;
                    if sv > jn(&band["end"]) || ev < jn(&band["start"]) { return Ok(None); }
                    let start = js::max(&[sv, jn(&band["start"])]);
                    let end = js::max(&[start, js::min(&[ev, jn(&band["end"])])]);
                    v_cells.push(json!({ "period": jsv(&uid), "kind": jv(KIND_COMMON), "lane": jv(lane), "start": jv(start), "end": jv(end), "name": jsv(name), "style": style, "color": col, "variant": key }));
                    Ok(Some((start, end)))
                };
                // 가림: 이 나라의 지도자 칸(지위로 대신하면 지위 칸도 · 붕당의 맞바꿈이면 집권 단 칸도) — 앞선 모듈이 실은 것 전부(변형 판 포함)
                let swap_power = is(&src, "group") && tv(&geo.get("powerH"));
                if let V::Str(u) = &uid {
                    for &at in cells_of_band.get(u.as_str().as_ref()).map(Vec::as_slice).unwrap_or(&[]) {
                        let c = &out["cells"][at];
                        let k = &c["kind"];
                        if jis(k, strip::LEADER) || (is(&src, "rank") && jis(k, strip::RANK)) || (swap_power && jis(k, KIND_COMMON) && jis(&c["lane"], LENS_LANE_POWER)) {
                            hides.push(json!({ "kind": 3, "at": at }));
                        }
                    }
                }
                // 가린 지도자 칸을 덧단 자리(단 lane)에 작게(갈래 4 — 지도자 칸의 무리 · 번갈아 짙기 · 순번 그대로).
                type Put<'a> = dyn FnMut(&mut Vec<Value>, f64, Option<f64>, Option<f64>, &V, i32, u32) -> crate::Result<Option<(f64, f64)>> + 'a;
                let down_leaders = |v_cells: &mut Vec<Value>, put: &mut Put<'_>, lane: f64| -> crate::Result<()> {
                    let mut prev_key: Option<V> = None;
                    for (i, c) in list(&p.get("leaders")).iter().enumerate() {
                        let k = or(or(c.get("dynasty"), c.get("dynastyAuto")), s(""));
                        let join = prev_key.as_ref().is_some_and(|pk| eq(pk, &k));
                        let style = style_with(cell_style(c) | (if join { st::JOIN_L } else { 0 }), i % 2 == 1, &V::Num(i as f64)) | LENS_BAND_LEADER.wrapping_shl(BAND_SHIFT);
                        if put(v_cells, lane, minute_of(&c.get("start")), minute_of(&nn(c.get("end"), p.get("endY"))), &leader_label(c), style, 0)?.is_some() { add_note(&count, "내린지도자", 1.0); }
                        prev_key = Some(k);
                    }
                    Ok(())
                };
                let has_leaders = tv(&p.get("leaders")) && tv(&p.get("leaders").get("length"));
                if is(&src, "rank") {
                    // 체제를 지위 변천으로 대신: 지위 칸을 지도자 자리에(갈래 3 — 지위 칸의 서열 · 이음 · 미정 그대로, 순번은 지위 칸 참조 rank:i)
                    let mut first = true;
                    for c in list(&p.get("rankSpans")) {
                        let lvl = js::to_i32(js::min(&[7.0, js::to_num(&js::add(&or(c.get("level"), V::Num(0.0)), &V::Num(1.0)))])).wrapping_shl(st::RANK);
                        let style = style_with(cell_style(&c) | (if first { 0 } else { st::JOIN_L }) | lvl, false, &c.get("i")) | LENS_BAND_RANK.wrapping_shl(BAND_SHIFT);
                        if put(&mut v_cells, LENS_LANE_LEADER, minute_of(&c.get("start")), minute_of(&c.get("end")), &or(c.get("name"), s("")), style, 0)?.is_some() { add_note(&count, "지위대신", 1.0); }
                        first = false;
                    }
                    // 그 줄에 지위 단이 있으면 지도자 칸을 지위 단 자리로
                    if tv(&geo.get("rankH")) && has_leaders { down_leaders(&mut v_cells, &mut put, LENS_LANE_RANK)?; }
                    continue;
                }
                // 붕당의 맞바꿈: 그 줄에 집권 단이 있으면 지도자 칸을 집권 단 자리로(웹은 표시 체크 '지도자'를 끈 동안 비우고, 앱은 그때 갈래 4를 그리지 않는다)
                if swap_power && has_leaders { down_leaders(&mut v_cells, &mut put, LENS_LANE_POWER)?; }
                // 제도 칸 · 붕당의 단체 칸(= 집권 단의 칸 — 지도자 자리 · 날짜 차례 한 줄 · 이어지면 긴 둥근 칸)
                let group = is(&src, "group");
                for (j, c) in list(&lc.get("cells")).iter().enumerate() {
                    if !tv(&c.get("name")) { continue; }
                    let two = group && n(&or(c.get("n"), V::Num(1.0))) > 1.0;
                    let sv = minute_of(&finite_or(c.get("start"), p.get("start")));
                    let ev = minute_of(&finite_or(c.get("end"), p.get("endY")));
                    let bits = (if c.bool("startUnknown") { st::UNK_S } else { 0 }) | (if c.bool("endUnknown") { st::UNK_E } else { 0 }) | (if j > 0 { st::JOIN_L } else { 0 }) | (if group { st::TAGGED } else { 0 });
                    let style = style_with(bits, false, &V::Num(j as f64)) | (if group { LENS_BAND_GROUP } else { LENS_BAND_INST }).wrapping_shl(BAND_SHIFT);
                    let name = if group {
                        let short = { let x = c.get("short"); if tv(&x) { js::to_str(&x) } else { js::to_str(&c.get("name")).first_code_point() } };
                        V::from(format!("{}\t{}", short.as_str(), js::to_str(&c.get("name")).as_str()).as_str())
                    } else { c.get("name") };
                    let Some((cs, ce)) = put(&mut v_cells, LENS_LANE_LEADER, sv, ev, &name, style, color(&c.get("color"), 0xa4b1b7))? else { continue };
                    let band = band_or_err(&band_v, &p)?; // 실었으면 띠가 있다
                    if !group { add_note(&count, "제도", 1.0); }
                    else if two || c.bool("solo") { add_note(&count, "연정", 1.0); }
                    else { add_note(&count, "단체", 1.0); }
                    // 색 점(웹의 `.gd`): 연정은 함께 집권한 단체 전부의 색, 짝을 모르는 연정은 제 색 하나, 한 단체의 집권은 없음.
                    let dots: Vec<V> = if !group { Vec::new() } else if c.bool("solo") { vec![c.get("color")] } else if two { items(&c.get("colors")) } else { Vec::new() };
                    let dot_text = if dots.is_empty() { String::new() } else { format!("\t{}", dots.iter().map(|x| format!("{:06x}", color(x, 0xa4b1b7))).collect::<Vec<_>>().join(",")) };
                    v_items.push(json!({
                        "section": jv(SECTION_ITEM), "track": track_index, "row": band["row"].clone(), "row2": band["row"].clone(), "start": jv(cs), "end": jv(ce), "lod": jv(lod_of(ce - cs)),
                        "ref": jsv(&uid), "name": if group { json!("") } else { jsv(&or(c.get("fam"), s(""))) },
                        "color": if two && tv(&c.get("color2")) { color(&c.get("color2"), 0) } else { 0 }, "a": jv(KIND_COMMON), "b": jv(LENS_LANE_LEADER),
                        "c": jv(js::min(&[4095.0, j as f64 + 1.0])), "d": if group && c.bool("solo") { 1 } else { 0 },
                        "text2": format!("{}{dot_text}", text_or_empty(&c.get("uid"))), "variant": key,
                    }));
                }
            }
        }
        let entry = o! { "id" => t.get("id"), "hint" => theme_hint(t), "has" => if lens_has_data(&model, &t.get("id")) { 1.0 } else { 0.0 } };
        if t.bool("hidden") { entry.set("hidden", 1.0); }
        if !v_cells.is_empty() {
            let (ni, nh) = (v_items.len(), hides.len());
            arr_mut(out, "cells").extend(v_cells);
            arr_mut(out, "items").extend(v_items);
            arr_mut(out, "variants").push(json!({
                "key": key, "kind": jv(VARIANT_KIND_THEME), "track": 0, "band": "", "uid": jsv(&t.get("id")), "name": jsv(&or(t.get("name"), t.get("id"))),
                "rows": [], "moves": [], "groups": [], "hides": hides, "notes": "",
            }));
            entry.set("v", 1.0);
            add_note(&notes, "렌즈", 1.0);
            add_note(&notes, "가림", nh as f64);
            add_note(&notes, "딸린항목", ni as f64);
            for (k, x) in count.entries() { add_note(&cell_notes, k.as_str().as_ref(), n(&x)); }
        }
        let sw = swatches_of(&model, t);
        if tv(&sw) { entry.set("sw", sw); }
        let hit = ev_hit.get(&t.get("id"));
        if let Some(hit) = hit.as_set().filter(|h| !h.is_empty()) {
            // 타일의 사건은 자리마다 uid가 다르다(공동 사건의 다른 자리는 `#n` — rails.mjs의 eventUid). 그 자리들을 모두 싣는다.
            let mut ev: Vec<V> = Vec::new();
            for e in out["events"].as_array().into_iter().flatten() {
                let Value::String(u) = &e["uid"] else { return Err("렌즈: 사건의 uid가 글이 아닙니다(JS라면 TypeError)".into()) };
                let head = u.split('#').next().unwrap_or("");
                if hit.has(&V::from(head)) { ev.push(V::from(u.as_str())); }
            }
            add_note(&notes, "사건", ev.len() as f64);
            entry.set("ev", arr(ev));
        }
        lens_of.set(t.get("id"), entry);
    }

    // ── ③ 항목 기록 themes에 x_lens — 렌즈로 말할 것이 있을 때만(없으면 기록 바이트 그대로) ──
    let entries: Vec<V> = themes.iter().map(|t| lens_of.get(&t.get("id"))).collect();
    let worth = !slot.is_empty()
        || entries.iter().any(|x| x.bool("has") || x.bool("hidden") || x.bool("v") || x.bool("sw") || x.bool("ev"))
        || themes.iter().any(|t| t.bool("kind"));
    if worth {
        let rec = arr_mut(out, "entities").iter_mut().find(|e| e["uid"] == "themes" && e["kind"] == "themes");
        let Some(rec) = rec else { return Err("렌즈: 항목 기록 themes가 없습니다(entities 모듈이 먼저 돌아야 합니다)".into()) };
        let text = match &rec["json"] { Value::String(t) => t.clone(), other => js::to_str(&js::from_json(other)).as_str().into_owned() };
        let body = js::parse(&text)?;
        ob(&body).set("x_lens", o! { "slot" => arr(slot), "themes" => arr(entries) });
        rec["json"] = Value::String(js::stringify(&body));
    }
    ctx.notes.set("렌즈", notes);
    super::kit::fault_check("lens")
}

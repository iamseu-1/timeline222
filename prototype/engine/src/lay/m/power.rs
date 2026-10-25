//! 내보내기 모듈 `power` — `prototype/scripts/export/power.mjs`(1 ~ 203줄 · SHA-256 앞 12자 `d4c25103d5ef`)를 줄 그대로 옮긴다(한 벌 P3 과제 14 · 갈래 E).
//! (2026-10-24 맞춤 · 리메이크 3단계 과제 3 ~ 6 · 계약 1-1 초안) 41 ~ 42줄 · 60 ~ 105줄 실권 밑줄(구역 56 — 남의 실권 `over` · 제 안의 실권자 ·
//! 리메이크 6단계의 실권 정권 섬김(partOf 명목상 — over 없이)) → [`SECTION_POWER_LINE`] · `power_lines`(표시 체크 '단체' 앞에서 부름).
//! 단체 단(집권 · 실권) · 명목 지도자 · 연합의 겹 탭 — 웹 연표가 그리는 것(`_layoutTrack` 단체 덧단 · `_groupRows` · `_groupCells` · `_cells`의 is-nominal ·
//! `_coalTabPlan`의 재료)을 자료로 푼다: `shared.bandOf`를 읽고 `out.cells`(종류 8 · 단 2 · 3)와 구역 43 · 47 항목을 더하며, 지도자 칸(종류 1)의 `style`에
//! 명목 비트 29를 켜고 `shared.powerNominal`(띠 uid → 명목 지도자 칸의 순번 Set)을 쓴다. 늦은 차례는 렌즈가 내린 지도자 칸(종류 8 · 단 갈래 4 · `theme:` 변형)에 비트 30.
//!
//! 함께 옮긴 웹 함수: `js/core.js` 2160 ~ 2177줄 `HT.coalitionsOf`(SHA-256 앞 12자 `9c786cf58566` — 정권마다의 기억 `coalMemo`는 두지 않음: 답이 같고
//! 이 모듈은 목록을 읽기만 한다) → [`coalitions_of`]. `HT.groupStrip`은 이미 옮긴 [`group_strip`](기억 없음 — 이 모듈은 칸 목록 · 명목 Set을 읽기만 하고,
//! 명목 Set은 띠마다 하나라 shared 덤프에 같은 객체가 두 번 들지 않는다). base.mjs의 `minute` · `color`는 [`minute_of`] · [`crate::lay::export::color`].
//! 모듈의 `styleWith` · `lodOf` · `ST` · `STRIP` 사본과 도움(`finite_or` · `[...name][0]` · JSON 참거짓 · 엄격 같음)은 lens · strips와 몸이 같아 [`super::kit`]의 하나를 부른다(과제 Y).
use super::kit::{finite_or, jis, jtruthy, lod_of, minute_js, minute_of, st, strip, style_with, BAND_SHIFT, KIND_COMMON, SECTION_ITEM};
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, ji, jn, jsv, jv, text_or_empty};
use crate::lay::js::{self, Map, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{eq, fault, is, le, list, lt, n, or, or_cmp, s, tv};
use crate::lay::rows::{group_strip, items};
use serde_json::{json, Value};
use std::collections::HashMap;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 단체 단의 단 · 단 갈래(style 27~29 — 칸 종류는 공용 칸 단 8 [`KIND_COMMON`]). 렌즈(lens.mjs)의 단 0 · 1 · 갈래 1~4 다음을 쓴다.
/// `POWER_LANE` — 집권 단 2 · 실권 단 3.
pub const POWER_LANE_POWER: f64 = 2.0;
pub const POWER_LANE_REAL: f64 = 3.0;
/// `POWER_BAND` — 한 단체의 집권 5 · 연정 6 · 실권 7.
pub const POWER_BAND_SINGLE: i32 = 5;
pub const POWER_BAND_COALITION: i32 = 6;
pub const POWER_BAND_REAL: i32 = 7;
/// 지도자 칸(종류 1)의 명목 비트(style 29) · 렌즈가 단 2로 내린 지도자 칸(종류 8 · 단 갈래 4)의 명목 비트(style 30).
pub const NOMINAL_BIT: i32 = 1 << 29;
pub const NOMINAL_BIT_LOWERED: i32 = 1 << 30;
const LENS_LOWERED_LEADER: i64 = super::kit::LENS_BAND_LEADER as i64;
/// 구역 47(뒤 장의 탭)의 모습 7 = 연합의 겹 탭(0~6은 상국 탭 — hangs.mjs).
pub const SECTION_HOST_TAB: f64 = 47.0;
pub const COALITION_LOOK: f64 = 7.0;
/// 실권 밑줄(power.mjs 41 ~ 42줄 `SECTION_POWER_LINE` — 리메이크 3단계 · 계약 1-1 초안).
pub const SECTION_POWER_LINE: f64 = 56.0;

/// `hex6(c)` — `color(c, 0xa4b1b7).toString(16).padStart(6, '0')`.
fn hex6(c: &V) -> String { format!("{:06x}", color(c, 0xa4b1b7)) }
/// `out.periods[i]` · 띠를 읽는 자리 — 몸은 `kit`(16b 층 손질: power ↔ lens가 서로 가리키지 않게 — lens도 kit에서 가져간다).
pub use super::kit::{band_at, band_or_err};

/// `HT.coalitionsOf(p)` — 나라 p가 구성 나라인 연합(type coalition)의 가담 기간 목록 `[{ group, start, end, role, note }]` — 시작 · 끝 · 이름(UTF-16) 차례.
/// 가담 기간 = 구성 나라 줄의 시작 · 끝(비우면 연합의 기간).
pub fn coalitions_of(p: &V) -> Vec<V> {
    if !tv(p) || !(tv(&p.get("groupLinks")) && tv(&p.get("groupLinks").get("length"))) { return Vec::new(); }
    let mut out: Vec<V> = Vec::new();
    let seen = Set::new();
    for l in items(&p.get("groupLinks")) {
        let g = l.get("group");
        if !tv(&g) || !is(&g.get("type"), "coalition") || seen.has(&g) { continue; }
        seen.add(g.clone());
        for m in items(&g.get("memberList")) {
            if eq(&m.get("polity"), p) || (tv(&m.get("polityUid")) && eq(&m.get("polityUid"), &p.get("uid"))) {
                out.push(V::Obj(o! { "group" => g.clone(), "start" => m.get("start"), "end" => m.get("end"), "role" => or(m.get("role"), s("")), "note" => or(m.get("note"), s("")) }));
            }
        }
    }
    js::sort(&mut out, |a, b| {
        or_cmp(n(&a.get("start")) - n(&b.get("start")), || {
            or_cmp(n(&a.get("end")) - n(&b.get("end")), || match js::to_str(&a.get("group").get("name")).cmp16(&js::to_str(&b.get("group").get("name"))) {
                std::cmp::Ordering::Less => -1.0,
                std::cmp::Ordering::Equal => 0.0,
                std::cmp::Ordering::Greater => 1.0,
            })
        })
    });
    out
}

/// 리메이크 3단계(계약 1-1 초안 — power.mjs 60 ~ 105줄) — 실권 밑줄(구역 56): 객체의 `power[].over`(형식 4 더하기 — 쥔 쪽에만 적고 over가 빼앗긴 객체)마다
/// 빼앗긴 쪽 띠에 항목 하나 · 구간은 그 띠 안으로 자름 · 이름 · 색 = 쥔 쪽(5단계 과제 12 — 감독 결정 장면 3) · text2 = 쥔 쪽 uid.
/// over 없이 이름만인 줄 = 제 안의 실권자(세도 가문 · 권신)는 제 띠에 · a 1 · 이름 = 그 줄의 이름 · 색 0 · text2 ''.
/// 표시 체크 단체와 상관없이 싣는다(객체의 실권이지 단체의 칸이 아님). 상대를 못 찾거나 띠가 없으면 뺀다. `shared.bandOf`가 없으면 아무것도 하지 않는다.
/// 리메이크 6단계(설계 3-4 · 같은 일을 두 쪽에 적지 않음): 실권 정권(종류 regime)이 섬김(`hosts`의 관계 nominal)으로 가리키는 상대에는 over 없이도 over 줄과 같은 꼴로 —
/// 구간은 섬김 기간(비우면 실권 정권의 기간). 같은 상대를 over로 적은 줄이 있으면 그 줄만(`overs`).
fn power_lines(ctx: &Ctx, out: &mut Value, notes: &js::Obj) -> crate::Result<()> {
    let band_of = match ctx.shared.get("bandOf") { V::Map(m) => m, other if !tv(&other) => return Ok(()), _ => return Err("power: shared.bandOf가 Map이 아닙니다(JS라면 TypeError)".into()) };
    let periods = list(&ctx.model.get("periods"));
    let by_uid = ctx.model.get("byUid");
    let mut count = 0.0;
    // `Math.max(band.start, minute(x) ?? band.start)` · `Math.min(band.end, minute(x) ?? band.end)` — 띠 안으로 자른 (s, e)
    let clip = |band: &Value, a: &V, b: &V| -> (f64, f64) {
        let (bs, be) = (jn(&band["start"]), jn(&band["end"]));
        // `minute`이 null이면 띠 끝 · Date 범위 밖이면 NaN(→ 아래 `!(e >= s)`로 뺌)
        (js::max(&[bs, minute_js(a).unwrap_or(bs)]), js::min(&[be, minute_js(b).unwrap_or(be)]))
    };
    for p in &periods {
        let power = p.get("power");
        let mut overs: Vec<V> = Vec::new(); // over로 적은 상대(아래 섬김 밑줄이 같은 상대에 겹치지 않게 — JS의 Set)
        for w in if matches!(power, V::Arr(_)) { list(&power) } else { Vec::new() } {
            if !tv(&w) { continue; }
            if !tv(&w.get("over")) {
                if !tv(&w.get("name")) || !band_of.has(&p.get("uid")) { continue; }
                let band = band_at(out, &band_of.get(&p.get("uid")));
                let band = band_or_err(&band, p)?.clone();
                let (s_, e_) = clip(&band, &crate::lay::model::util::nn(w.get("start"), p.get("start")), &crate::lay::model::util::nn(w.get("end"), p.get("endY")));
                if !matches!(e_.partial_cmp(&s_), Some(std::cmp::Ordering::Greater | std::cmp::Ordering::Equal)) { continue; } // `!(e >= s)`
                arr_mut(out, "items").push(json!({
                    "section": jv(SECTION_POWER_LINE), "track": band["track"].clone(), "row": band["row"].clone(), "row2": band["row"].clone(), "start": jv(s_), "end": jv(e_),
                    "lod": jv(lod_of(e_ - s_)), "ref": jsv(&p.get("uid")), "name": jsv(&w.get("name")), "color": 0, "a": 1, "b": 0, "c": 0, "d": 0, "text2": "",
                }));
                count += 1.0;
                continue;
            }
            let key = V::Str(js::to_str(&w.get("over")).trim());
            let pk = p.get("packId");
            let mut target = match &by_uid { V::Map(m) => m.get(&key), _ => V::Undef };
            if !tv(&target) { target = periods.iter().find(|q| eq(&q.get("packId"), &pk) && eq(&q.get("id"), &key)).cloned().unwrap_or(V::Undef); }
            if !tv(&target) { target = periods.iter().find(|q| eq(&q.get("packId"), &pk) && eq(&q.get("name"), &key)).cloned().unwrap_or(V::Undef); }
            if !tv(&target) || eq(&target, p) { continue; }
            if !overs.iter().any(|x| eq(x, &target)) { overs.push(target.clone()); }
            if !band_of.has(&target.get("uid")) { continue; }
            let band = band_at(out, &band_of.get(&target.get("uid")));
            let band = band_or_err(&band, &target)?.clone();
            let (s_, e_) = clip(&band, &crate::lay::model::util::nn(w.get("start"), target.get("start")), &crate::lay::model::util::nn(w.get("end"), target.get("endY")));
            if !matches!(e_.partial_cmp(&s_), Some(std::cmp::Ordering::Greater | std::cmp::Ordering::Equal)) { continue; } // `!(e >= s)`
            arr_mut(out, "items").push(json!({
                "section": jv(SECTION_POWER_LINE), "track": band["track"].clone(), "row": band["row"].clone(), "row2": band["row"].clone(), "start": jv(s_), "end": jv(e_),
                "lod": jv(lod_of(e_ - s_)), "ref": jsv(&target.get("uid")), "name": jsv(&or(p.get("name"), s(""))), "color": color(&p.get("color"), 0),
                "a": 0, "b": 0, "c": 0, "d": 0, "text2": jsv(&p.get("uid")),
            }));
            count += 1.0;
        }
        if !is(&p.get("type"), "regime") { continue; }
        for h in list(&p.get("hosts")) {
            let target = if tv(&h) { h.get("host") } else { V::Undef };
            if !tv(&target) || !is(&h.get("relation"), "nominal") || eq(&target, p) || overs.iter().any(|x| eq(x, &target)) || !band_of.has(&target.get("uid")) { continue; }
            let band = band_at(out, &band_of.get(&target.get("uid")));
            let band = band_or_err(&band, &target)?.clone();
            let (s_, e_) = clip(&band, &crate::lay::model::util::nn(h.get("start"), p.get("start")), &crate::lay::model::util::nn(h.get("end"), p.get("endY")));
            if !matches!(e_.partial_cmp(&s_), Some(std::cmp::Ordering::Greater | std::cmp::Ordering::Equal)) { continue; } // `!(e >= s)`
            arr_mut(out, "items").push(json!({
                "section": jv(SECTION_POWER_LINE), "track": band["track"].clone(), "row": band["row"].clone(), "row2": band["row"].clone(), "start": jv(s_), "end": jv(e_),
                "lod": jv(lod_of(e_ - s_)), "ref": jsv(&target.get("uid")), "name": jsv(&or(p.get("name"), s(""))), "color": color(&p.get("color"), 0),
                "a": 0, "b": 0, "c": 0, "d": 0, "text2": jsv(&p.get("uid")),
            }));
            count += 1.0;
        }
    }
    notes.set("실권밑줄", count);
    Ok(())
}

/// `contribute(ctx, out)` — 트랙마다 띠의 ② 단체 칸 · ③ 명목 지도자 · ④ 연합의 겹 탭. 표시 '단체'(`tl.show.groups`)가 꺼졌거나 `shared.bandOf`가 없으면 빈손.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let notes = o! { "집권칸" => 0.0, "연정칸" => 0.0, "실권칸" => 0.0, "딸린항목" => 0.0, "명목" => 0.0, "연합탭" => 0.0 };
    ctx.notes.set("단체단", notes.clone());
    let bump = |k: &str| notes.set(k, n(&notes.get(k)) + 1.0);
    power_lines(ctx, out, &notes)?;
    let show = tl.get("show");
    if !tv(&show) || !show.bool("groups") { return Ok(()); }
    let band_of = ctx.shared.get("bandOf");
    if !tv(&band_of) { return Ok(()); }
    let Some(band_of) = band_of.as_map().cloned() else { return Err("단체 단: shared.bandOf가 Map이 아닙니다(JS라면 TypeError)".into()) };

    // 명목 지도자 칸의 순번 — 띠 uid → Set(늦은 차례가 렌즈의 내린 지도자 칸에 같은 표시를 켠다). 변형 판을 다시 돌릴 때(variants.mjs)는 새 shared라 덮지 않는다.
    let nominal_of = Map::new();
    ctx.shared.set("powerNominal", nominal_of.clone());

    // 지도자 칸(종류 1)의 자리 — 띠 uid → 순번 → out.cells의 자리(명목 비트를 켤 칸을 찾는다). strips.mjs가 이미 실었다.
    // (JS의 Map 열쇠는 `c.period` 그대로 — 띠 uid(글)로만 찾으므로 글 열쇠만 둔다)
    let mut leader_at: HashMap<String, HashMap<i64, usize>> = HashMap::new();
    for (i, c) in out["cells"].as_array().into_iter().flatten().enumerate() {
        if !jis(&c["kind"], strip::LEADER) || jtruthy(&c["variant"]) { continue; }
        let seq = ((ji(&c["style"]) >> 15) & 0xfff) - 1;
        if seq < 0 { continue; }
        let Value::String(period) = &c["period"] else { continue };
        leader_at.entry(period.clone()).or_default().insert(seq, i);
    }

    for (track_index, tr) in list(&tl.get("tracks")).iter().enumerate() {
        // 연합의 겹 탭이 붙는 띠 — hangs.mjs의 뒤 장의 탭과 같은 조건(그려지는 띠 · 접힌 민족 줄 밖)
        let drawn = |p: &V| {
            let row = p.get("_row");
            !p.bool("_folded") && !p.bool("_hidden") && !p.bool("_under") && !p.bool("_overlay") && !row.is_nullish() && le(&V::Num(0.0), &row) && lt(&row, &tr.get("rows"))
                && !folded_has(&tr.get("foldedRows"), &row, &tr.get("id"))
        };
        for p in items(&tr.get("periods")) {
            if p.bool("_overlay") || !band_of.has(&p.get("uid")) { continue; }
            // `out.periods[bandOf.get(p.uid)]` — 범위 밖이면 undefined(그 띠를 읽는 곳에서 JS는 TypeError → band_or_err)
            let band_v = band_at(out, &band_of.get(&p.get("uid")));
            let geo = { let g = match p.get("_row") { V::Num(r) if r >= 0.0 && r.fract() == 0.0 => tr.get("geos").get(&r), _ => V::Undef }; or(g, tr.get("geo")) };
            let strip = group_strip(&p);

            // ② 단체 칸 — 그 줄에 그 단이 있을 때만(웹 _groupRows: gr.powerH · gr.realH)
            for (lane, cells, h) in [(POWER_LANE_POWER, strip.get("power"), geo.get("powerH")), (POWER_LANE_REAL, strip.get("real"), geo.get("realH"))] {
                let cells = list(&cells);
                if !tv(&h) || cells.is_empty() { continue; }
                for (j, c) in cells.iter().enumerate() {
                    if !tv(&c.get("name")) { continue; }
                    let s0 = minute_of(&finite_or(c.get("start"), p.get("start")));
                    let e0 = minute_of(&finite_or(c.get("end"), p.get("endY")));
                    let (Some(s0), Some(e0)) = (s0, e0) else { continue };
                    let band = band_or_err(&band_v, &p)?;
                    if s0 > jn(&band["end"]) || e0 < jn(&band["start"]) { continue; }
                    let start = js::max(&[s0, jn(&band["start"])]);
                    let end = js::max(&[start, js::min(&[e0, jn(&band["end"])])]);
                    let two = n(&or(c.get("n"), V::Num(1.0))) > 1.0;
                    let kind = if c.bool("real") { POWER_BAND_REAL } else if two || c.bool("solo") { POWER_BAND_COALITION } else { POWER_BAND_SINGLE };
                    let bits = (if c.bool("startUnknown") { st::UNK_S } else { 0 }) | (if c.bool("endUnknown") { st::UNK_E } else { 0 }) | (if j > 0 { st::JOIN_L } else { 0 }) | st::TAGGED;
                    let style = style_with(bits, false, &V::Num(j as f64)) | kind.wrapping_shl(BAND_SHIFT);
                    let short = { let x = c.get("short"); if tv(&x) { js::to_str(&x) } else { js::to_str(&c.get("name")).first_code_point() } };
                    let name = format!("{}\t{}", short.as_str(), js::to_str(&c.get("name")).as_str());
                    arr_mut(out, "cells").push(json!({
                        "period": jsv(&p.get("uid")), "kind": jv(KIND_COMMON), "lane": jv(lane), "start": jv(start), "end": jv(end), "name": name, "style": style,
                        "color": color(&c.get("color"), 0xa4b1b7),
                    }));
                    if c.bool("real") { bump("실권칸"); }
                    else if kind == POWER_BAND_COALITION { bump("연정칸"); }
                    else { bump("집권칸"); }
                    // 색 점(웹의 `.gd`): 연정은 함께 집권한 단체 전부의 색, 짝을 모르는 연정은 제 색 하나, 한 단체는 없음.
                    let dots: Vec<V> = if c.bool("solo") { vec![c.get("color")] } else if two { items(&c.get("colors")) } else { Vec::new() };
                    let dot_text = if dots.is_empty() { String::new() } else { format!("\t{}", dots.iter().map(hex6).collect::<Vec<_>>().join(",")) };
                    arr_mut(out, "items").push(json!({
                        "section": jv(SECTION_ITEM), "track": track_index, "row": band["row"].clone(), "row2": band["row"].clone(), "start": jv(start), "end": jv(end),
                        "lod": jv(lod_of(end - start)), "ref": jsv(&p.get("uid")), "name": "", "color": if two && tv(&c.get("color2")) { color(&c.get("color2"), 0) } else { 0 },
                        "a": jv(KIND_COMMON), "b": jv(lane), "c": jv(js::min(&[4095.0, j as f64 + 1.0])), "d": if c.bool("solo") { 1 } else { 0 },
                        "text2": format!("{}{dot_text}", text_or_empty(&c.get("uid"))),
                    }));
                    bump("딸린항목");
                }
            }

            // ③ 명목 지도자 — 웹 _cells의 is-nominal(실권 칸들과 제 기간의 절반 이상 겹침 · HT.groupStrip의 nominal)
            let nominal = strip.get("nominal").as_set().cloned().unwrap_or_default();
            if !nominal.is_empty() { nominal_of.set(p.get("uid"), nominal.clone()); }
            let at = match p.get("uid") { V::Str(uid) if !nominal.is_empty() => leader_at.get(uid.as_str().as_ref()), _ => None };
            if let Some(at) = at {
                for i in nominal.values() {
                    let Some(&k) = (match i { V::Num(i) if i.fract() == 0.0 => at.get(&(i as i64)), _ => None }) else { continue };
                    let cell = &mut arr_mut(out, "cells")[k];
                    cell["style"] = Value::from(js::to_i32(jn(&cell["style"])) | NOMINAL_BIT);
                    bump("명목");
                }
            }

            // ④ 연합의 겹 탭 — 구성 나라 띠마다 가담 한 건에 항목 하나(자리는 그리는 쪽)
            if !drawn(&p) { continue; }
            for (k, c) in coalitions_of(&p).iter().enumerate() {
                if !lt(&c.get("start"), &c.get("end")) { continue; }
                let (Some(start), Some(end)) = (minute_of(&c.get("start")), minute_of(&c.get("end"))) else { continue };
                if end < start { continue; }
                let g = c.get("group");
                arr_mut(out, "items").push(json!({
                    "section": jv(SECTION_HOST_TAB), "track": track_index, "row": jsv(&p.get("_row")), "row2": jsv(&p.get("_row")), "start": jv(start), "end": jv(end), "lod": -1,
                    "ref": jsv(&p.get("uid")), "name": jsv(&or(g.get("name"), s(""))), "color": color(&g.get("color"), 0xa4b1b7), "a": jv(COALITION_LOOK), "b": k, "c": 0, "d": 0,
                    "text2": jsv(&or(g.get("uid"), s(""))),
                }));
                bump("연합탭");
            }
        }
    }
    super::kit::fault_check("power")
}
/// `tr.foldedRows.has(row)` — JS는 Set(또는 `has`가 있는 Map)이 아니면 TypeError: 잘못으로 남긴다(과제 Y — 갈래 E '조용히 이어 가는 길'. 줄 배정이 늘 Set을 둔다).
fn folded_has(folded: &V, row: &V, track: &V) -> bool {
    match super::kit::has_of(folded, row) {
        Some(b) => b,
        None => { fault(format!("트랙 {}의 foldedRows가 Set이 아닙니다(JS라면 tr.foldedRows.has에서 TypeError)", js::to_str(track).as_str())); false }
    }
}

/// 늦은 차례: 붕당 렌즈(export/lens.mjs — MODULES 맨 끝)가 집권 단 자리(단 2)로 내린 지도자 칸(종류 8 · 단 갈래 4)에도 명목 표시(비트 30)를 켠다.
/// 렌즈 칸의 순번(비트 15~26)은 지도자 칸의 순번 그대로라 ③과 같은 Set으로 찾는다. 렌즈 모듈을 건너뛰었거나 렌즈 칸이 없으면 아무것도 하지 않는다.
pub fn contribute_late(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let nominal_of = ctx.shared.get("powerNominal");
    if !tv(&nominal_of) { return Ok(()); }
    let Some(nominal_of) = nominal_of.as_map().cloned() else { return Err("단체 단(늦은 차례): shared.powerNominal이 Map이 아닙니다(JS라면 TypeError)".into()) };
    if nominal_of.is_empty() { return Ok(()); }
    let mut count = 0.0;
    for c in arr_mut(out, "cells").iter_mut() {
        // `/^theme:/.test(c.variant || '')` — 변형 열쇠는 늘 글이다(글이 아니면 맞지 않는 것으로 봄)
        let theme = matches!(&c["variant"], Value::String(v) if v.starts_with("theme:"));
        if !jis(&c["kind"], KIND_COMMON) || !jis(&c["lane"], POWER_LANE_POWER) || !theme { continue; }
        let style = ji(&c["style"]);
        if ((style >> BAND_SHIFT) & 7) != LENS_LOWERED_LEADER { continue; }
        let seq = ((style >> 15) & 0xfff) - 1;
        let set = match &c["period"] { Value::String(uid) => nominal_of.get(&V::from(uid.as_str())), _ => V::Undef };
        if seq < 0 || !tv(&set) || !set.as_set().is_some_and(|st| st.has(&V::Num(seq as f64))) { continue; }
        c["style"] = Value::from(js::to_u32(f64::from(js::to_i32(jn(&c["style"])) | NOMINAL_BIT_LOWERED)));
        count += 1.0;
    }
    let notes = ctx.notes.get("단체단");
    if let Some(o) = notes.as_obj() { o.set("렌즈명목", count); }
    Ok(())
}

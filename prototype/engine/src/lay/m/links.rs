//! 내보내기 모듈 `links` — `prototype/scripts/export/links.mjs`(1 ~ 311줄 · SHA-256 앞 12자 `d469d56900df` — 저장소의 LF 바이트 · 가지 line-routing 걸음 3의 판)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 9).
//! 관계선 — 건국 · 멸망 네모(20) · 승계선(21) · 소속선(22) · 할거기 칠(25) · 소속 단추(26) · 할거 모아 보기 단추(27) · 동군연합 이음줄의 끝(49) · 단체 펼치기(51) · 옮겨 앉기의 끝(52) ·
//! 트랙을 건너는 승계의 짝 꼬리표(60 — 2026-10-25 감독 결정 (2) · JS 255 ~ 287줄 → 이 파일 끝의 같은 절 · 다른 항목의 차례가 바뀌지 않게 모듈 맨 끝).
//! 지금 연표의 `_squares` · `chainRows` · `_linkPlan` · `_hollowHTML` · `_scopeBtnsHTML`이 쓰는 값 가운데 **화면 px과 무관한 것만** 싣는다(값의 뜻은 계약 6-10절).
//! 판(집합 보기) 규칙: 승계선의 '같은 트랙' = 선대가 지금 이 트랙에 놓였는가(`placed.has(q)`) · 이음줄 · 옮겨 앉기 끝의 트랙 = 그 나라가 놓인 트랙(`placedIn`) ·
//! 트랙 번호 = 지금 `tl.tracks`의 차례 · 승계선 정렬은 `HT.cmp16`. 놓이지 않은 정권의 트랙을 물으면(`placedIn.get(p).id` — JS라면 던짐) 오류.
//!
//! `rails.mjs`의 `lodOf`(→ [`lod_of`])를 가져오고 `shared.bandOf`를 읽는다(없으면 빈 Map — 띠 번호 = 순번 + 1을 구역 21 · 22 · 49 · 52 · 60의 b에).
//! 부르는 웹 함수: `tl._hosted`(`lay::ctx::set_scopes`가 둔 Map) · `tl._data.scopes` · `HT.formatYear`(→ `read::dates::format_year`) ·
//! `HT.cmp16` · `HT.historicityOf` · `HT.succAbsorbs` · `HT.successionLabel` · `HT.relationName` · `HT.kindName`(→ [`crate::lay::web::words`]) · `HT.cellSpan`(→ `web::cells`)
//! — 과제 Y가 모음(처음 옮긴 판은 이 파일에 있었다). 이 모듈만 부르는 것 — `js/core.js`(SHA-256 앞 12자 `9c786cf58566`):
//! - 6841 ~ 6860줄 `HT.unionPairs` → [`union_pairs`](모델마다 한 번 셈해 `model._unionPairs`에 둠 — JS와 같게)
use super::kit::{band_id, has_or_err, lod_of, minute_val};
use super::rails::push_item;
use crate::lay::ctx::Ctx;
use crate::lay::export::color;
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, assign_obj, eq, is, le, list, lt, n, nn, or, t, tv};
use crate::lay::read::{dates::format_year, Ctx as ReadCtx};
use crate::lay::rows::{band_end, band_start, items, join};
use crate::lay::web::cells::cell_span;
use crate::lay::web::words::{cmp16, historicity_of, kind_name, relation_name, succ_absorbs, succession_label};
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 내가 쓰는 구역 번호(계약 6-10절)
pub struct Section { pub square: f64, pub link: f64, pub part: f64, pub scope: f64, pub scope_span: f64, pub hollow: f64, pub mem_btn: f64, pub scope_btn: f64, pub union: f64, pub groups_btn: f64, pub r#move: f64, pub cross: f64 }
pub const SECTION: Section = Section { square: 20.0, link: 21.0, part: 22.0, scope: 23.0, scope_span: 24.0, hollow: 25.0, mem_btn: 26.0, scope_btn: 27.0, union: 49.0, groups_btn: 51.0, r#move: 52.0, cross: 60.0 };

/// 승계 종류 번호 — 모르는 종류는 간접으로 본다(지금 연표의 succKind)
fn succ_no(ty: &V) -> Option<i32> {
    match ty.as_str().and_then(|s| s.exact().map(str::to_owned)).as_deref() { Some("direct") => Some(0), Some("indirect") => Some(1), Some("revival") => Some(2), Some("partial") => Some(3), _ => None }
}
const SUCC_INDIRECT: i32 = 1;
const SUCC_PARTIAL: i32 = 3;

/// 구역 20 · 네모의 a 비트
struct Sq { unk_s: i32, unk_e: i32, ongoing: i32, seam_l: i32, seam_r: i32, range_s: i32, range_e: i32, refuted: i32, wide_l: i32, wide_r: i32 }
const SQ: Sq = Sq { unk_s: 1, unk_e: 2, ongoing: 4, seam_l: 8, seam_r: 16, range_s: 32, range_e: 64, refuted: 128, wide_l: 256, wide_r: 512 };
/// 직접이 아닌 승계(간접 · 부흥 · 부분)의 이음매 — 네모가 더 비켜 앉아(6px) 점선 다리가 보인다(묶음 5 · 7번 · 지금 연표의 seamWide와 같은 판정). q = 앞 띠, p = 뒤 띠
fn seam_wide(q: &V, p: &V) -> bool {
    if !(tv(q) && tv(p)) { return false; }
    let edge = items(&p.get("predecessors")).into_iter().find(|e| eq(&e.get("from"), q));
    let ty = or(edge.map_or(V::Undef, |e| e.get("type")), V::from("indirect"));
    !is(&ty, "direct")
}
/// 구역 21 · 승계선의 a 비트
struct Lk { down: i32, q_first: i32, seam: i32, absorb: i32, bundled: i32, unk_q: i32, unk_p: i32, range_q: i32, range_p: i32, refuted: i32 }
const LK: Lk = Lk { down: 1 << 4, q_first: 1 << 5, seam: 1 << 6, absorb: 1 << 7, bundled: 1 << 8, unk_q: 1 << 9, unk_p: 1 << 10, range_q: 1 << 11, range_p: 1 << 12, refuted: 1 << 13 };

const U32: f64 = 4_294_967_280.0; // 0xfffffff0
fn clamp_u32(v: f64) -> f64 { if !v.is_finite() || v <= 0.0 { 0.0 } else { js::min(&[U32, js::round(v)]) } }

// ── 웹 함수(js/core.js) ──

/// `HT.unionPairs(model)` — 같은 사람이 **같은 때 두 나라의 지도자**인 겹침마다 하나(동군연합 — 건의 8의 6-다):
/// 칸의 person 참조로 묶인 지도자 칸끼리, 연표에 그려진 구간이 겹치는 두 나라의 짝. → `[{ key, name, s, e, mid, a: { p, i, ref }, b: { p, i, ref } }]`(모델마다 한 번 셈해 둔다).
pub fn union_pairs(rc: &ReadCtx, model: &V) -> crate::Result<Vec<V>> {
    if !tv(model) || !model.bool("personIndex") { return Ok(Vec::new()); }
    let cached = model.get("_unionPairs");
    if tv(&cached) { return Ok(list(&cached)); }
    let mut out: Vec<V> = Vec::new();
    let nodes = Set::new();
    match model.get("personIndex") {
        V::Map(ix) => { for nd in ix.values() { nodes.add(nd); } }
        _ => return Err("model.personIndex가 Map이 아닙니다 — JS라면 .values()에서 멈춤".into()),
    }
    for nd in nodes.values() {
        let cells: Vec<V> = items(&if tv(&nd) { nd.get("cells") } else { nd.clone() }).into_iter().filter(|q| is(&q.get("kind"), "leader") && q.bool("p") && q.bool("c")).collect();
        for x in 0..cells.len() {
            for y in x + 1..cells.len() {
                let (mut a, mut b) = (cells[x].clone(), cells[y].clone());
                if eq(&a.get("p"), &b.get("p")) { continue; }
                let sa = V::Obj(cell_span(rc, &a.get("c"), &a.get("p"), &a.get("ref")));
                let sb = V::Obj(cell_span(rc, &b.get("c"), &b.get("p"), &b.get("ref")));
                let s = js::max(&[n(&sa.get("start")), n(&sb.get("start"))]);
                let e = js::min(&[n(&nn(sa.get("end"), a.get("p").get("endY"))), n(&nn(sb.get("end"), b.get("p").get("endY")))]);
                if !(e > s) { continue; }
                if lt(&b.get("p").get("uid"), &a.get("p").get("uid")) { std::mem::swap(&mut a, &mut b); }
                let key = format!("{}|{}|{}|{}", t(&a.get("p").get("uid")), t(&a.get("ref")), t(&b.get("p").get("uid")), t(&b.get("ref")));
                out.push(V::Obj(o! {
                    "key" => key, "name" => or(nd.get("name"), V::from("")), "s" => s, "e" => e, "mid" => (s + e) / 2.0,
                    "a" => o! { "p" => a.get("p"), "i" => a.get("i"), "ref" => a.get("ref") }, "b" => o! { "p" => b.get("p"), "i" => b.get("i"), "ref" => b.get("ref") },
                }));
            }
        }
    }
    if let V::Obj(m) = model { m.set("_unionPairs", arr(out.clone())); }
    Ok(out)
}

// ── links.mjs ──

/// `contribute(ctx, out)`.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let band_of = { let b = ctx.shared.get("bandOf"); if tv(&b) { b } else { V::Map(Map::new()) } }; // 띠의 uid → out.periods의 순번 (bands.mjs) — 띠 번호는 그 순번 + 1(가져오기가 넣는 차례)
    let id_of = |uid: &V| band_id(&band_of, uid);
    let rc = &ctx.read;
    let counts = Obj::new();
    for k in ["네모", "승계선", "소속선", "할거기칠", "소속단추", "대범위단추", "동군연합끝"] { counts.set(k, 0.0); }
    let skipped = o! { "승계_트랙밖" => 0.0, "승계_숨은띠" => 0.0, "소속_상국없음" => 0.0 };
    let bump = |o: &Obj, k: &str| o.set(k, n(&or(o.get(k), V::Num(0.0))) + 1.0);
    let item = |out: &mut Value, extra: Obj| {
        let base = o! { "section" => 0.0, "track" => 0.0, "row" => 0.0, "row2" => 0.0, "start" => 0.0, "end" => 0.0, "lod" => -1.0, "ref" => "", "name" => "", "color" => 0.0, "a" => 0.0, "b" => 0.0, "c" => 0.0, "d" => 0.0, "text2" => "" };
        assign_obj(&base, &extra);
        push_item(out, &base);
    };
    let refuted = |p: &V| historicity_of(p) == "refuted";
    let minute = minute_val;

    for (track, tr) in list(&tl.get("tracks")).iter().enumerate() {
        let track = track as f64;
        let hidden_rows = tr.get("hiddenRows");
        let hidden = |row: &V| -> crate::Result<bool> {
            if !tv(&hidden_rows) { return Ok(false); }
            has_or_err(&hidden_rows, row, "tr.hiddenRows")
        };
        /* 지금 연표가 네모 · 선을 그리는 띠(= _drawLinks의 거름) */
        let drawn = |p: &V| -> crate::Result<bool> {
            let row = p.get("_row");
            Ok(!p.bool("_folded") && !p.bool("_hidden") && !p.bool("_under") && !p.bool("_overlay") && !row.is_nullish() && le(&V::Num(0.0), &row) && lt(&row, &tr.get("rows")) && !hidden(&row)?)
        };
        let periods = list(&tr.get("periods"));

        /* ── 구역 20 · 건국 · 멸망 네모 ─────────────────────────────────────────────
           띠마다 하나로 싣는다. start · end = 띠의 바깥 끝(연대 폭을 품은 해). 확정 해는 b · c의 '안쪽 여백'으로 되돌린다. */
        for p in &periods {
            if !drawn(p)? { continue; }
            let (s, e) = (minute(&band_start(p)), minute(&band_end(p)));
            if s.is_nullish() || e.is_nullish() || lt(&e, &s) { continue; }
            let seam_of = |k: &str| { let x = p.get(k); if tv(&x) && eq(&x.get("_row"), &p.get("_row")) { x } else { V::Null } };
            let (seam_l, seam_r) = (seam_of("_seamL"), seam_of("_seamR"));
            let a = (if p.bool("startUnknown") { SQ.unk_s } else { 0 }) | (if p.bool("endUnknown") { SQ.unk_e } else { 0 }) | (if p.bool("ongoing") { SQ.ongoing } else { 0 })
                | (if tv(&seam_l) { SQ.seam_l | if seam_wide(&seam_l, p) { SQ.wide_l } else { 0 } } else { 0 }) | (if tv(&seam_r) { SQ.seam_r | if seam_wide(p, &seam_r) { SQ.wide_r } else { 0 } } else { 0 })
                | (if p.bool("startRange") { SQ.range_s } else { 0 }) | (if p.bool("endRange") { SQ.range_e } else { 0 }) | (if refuted(p) { SQ.refuted } else { 0 });
            // 왼쪽 칸 b: 이음매면 앞 띠와의 틈(분), 연대 폭이면 바깥 끝 ↔ 확정 해의 거리(분)
            let b = if tv(&seam_l) { clamp_u32(n(&s) - n(&minute(&band_end(&seam_l)))) } else if p.bool("startRange") { clamp_u32(n(&minute(&p.get("start"))) - n(&s)) } else { 0.0 };
            let c = if tv(&seam_r) { clamp_u32(n(&minute(&band_start(&seam_r))) - n(&e)) } else if p.bool("endRange") { clamp_u32(n(&e) - n(&minute(&p.get("endY")))) } else { 0.0 };
            item(out, o! { "section" => SECTION.square, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => s, "end" => e, "lod" => -1.0, "ref" => p.get("uid"), "name" => or(p.get("name"), V::from("")), "color" => f64::from(color(&p.get("color"), 0xa4b1b7)), "a" => f64::from(a), "b" => b, "c" => c });
            bump(&counts, "네모");
        }

        /* ── 구역 26 · 소속 펼치기 단추 '▸ n' (띠 안 첫 글줄) ─────────────────────── */
        for p in &periods {
            if !drawn(p)? { continue; }
            // 켠 대범위로 떠난 정권은 세지 않는다 — _drawTrack의 nMem과 같은 셈
            let cnt = items(&p.get("members")).iter().filter(|m| eq(&m.get("track"), &tr.get("id")) && m.bool("singleHost") && !m.bool("groupUid") && !is(&m.get("polityKind"), "overlay") && !(m.bool("_scope") && !eq(&m.get("_host"), p))).count();
            if cnt == 0 { continue; }
            let (s, e) = (minute(&band_start(p)), minute(&band_end(p)));
            if s.is_nullish() || e.is_nullish() || lt(&e, &s) { continue; }
            item(out, o! { "section" => SECTION.mem_btn, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => s, "end" => e, "lod" => -1.0, "ref" => p.get("uid"), "name" => or(p.get("name"), V::from("")), "color" => f64::from(color(&p.get("color"), 0xa4b1b7)), "a" => cnt as f64 });
            bump(&counts, "소속단추");
        }

        /* ── 구역 51 · 단체 펼치기(리메이크 조각 ④ · 설계 4-6 #7 C — 든 나라 띠의 플래그 창 '단체 n') ──────────────
           그 나라에 접혀 든 단체의 띠가 있는 나라마다 하나. a = 단체 수(토막이 아니라 단체),
           text2 = 플래그 창의 목록 — 단체마다 'uid␟이름␟#색'(␟ = U+001F)을 ␞(U+001E)로 이어 붙임(단체의 처음 차례). 펼치면 변형 `groups:<나라 uid>`. */
        for p in &periods {
            if !drawn(p)? { continue; }
            let groups = Map::new();
            for m in items(&p.get("members")) { if eq(&m.get("track"), &tr.get("id")) && m.bool("singleHost") && m.bool("groupUid") && !groups.has(&m.get("groupUid")) { groups.set(m.get("groupUid"), m.clone()); } }
            if groups.is_empty() { continue; }
            let (s, e) = (minute(&band_start(p)), minute(&band_end(p)));
            if s.is_nullish() || e.is_nullish() || lt(&e, &s) { continue; }
            let mut gl = groups.values();
            js::sort(&mut gl, |a, b| n(&a.get("start")) - n(&b.get("start")));
            let parts: Vec<V> = gl.iter().map(|m| V::Str(join(&[m.get("groupUid"), or(m.get("name"), V::from("")), or(m.get("color"), V::from(""))], "\u{1f}"))).collect();
            let text = join(&parts, "\u{1e}");
            item(out, o! { "section" => SECTION.groups_btn, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => s, "end" => e, "lod" => -1.0, "ref" => p.get("uid"), "name" => or(p.get("name"), V::from("")), "color" => f64::from(color(&p.get("color"), 0xa4b1b7)), "a" => groups.len() as f64, "text2" => text });
            bump(&counts, "단체단추");
        }

        /* ── 구역 21 · 승계선 ────────────────────────────────────────────────────
           고를 쌍과 차례는 _linkPlan 그대로(선대 uid → |Δ줄|). 세로 통로 번호 k는 '모두 켠 상태'의 기준값이다. */
        let mut edges: Vec<(V, V, V)> = Vec::new(); // (edge, q, p)
        // '같은 트랙'은 선대가 지금 이 트랙에 놓였는가로 본다(자료의 track이 아니라) — 판을 켜면 구성 나라는 판 트랙(__board)으로 옮겨 간다.
        let placed = Set::new();
        for p in &periods { placed.add(p.clone()); }
        for p in &periods {
            if p.bool("_folded") || p.bool("_hidden") || p.bool("_overlay") { continue; }
            for edge in items(&p.get("predecessors")) {
                let q = edge.get("from");
                if !tv(&q) { continue; }
                if !placed.has(&q) { bump(&skipped, "승계_트랙밖"); continue; }
                if q.get("_row").is_nullish() || p.get("_row").is_nullish() || q.bool("_folded") || q.bool("_hidden") || q.bool("_under") || q.bool("_overlay") || hidden(&q.get("_row"))? || hidden(&p.get("_row"))? { bump(&skipped, "승계_숨은띠"); continue; }
                edges.push((edge, q, p.clone()));
            }
        }
        js::sort_by(&mut edges, |x, y| {
            let c = cmp16(&x.1.get("uid"), &y.1.get("uid"));
            if c != 0.0 && !c.is_nan() { return c; }
            (n(&x.2.get("_row")) - n(&x.1.get("_row"))).abs() - (n(&y.2.get("_row")) - n(&y.1.get("_row"))).abs()
        });
        let bundled = bundled_edges(&tl, tr);
        let out_idx = Map::new();
        for (edge, q, p) in &edges {
            let ty = succ_no(&edge.get("type")).unwrap_or(SUCC_INDIRECT);
            let mut k = V::Num(0.0);
            if !eq(&q.get("_row"), &p.get("_row")) {
                k = or(out_idx.get(&q.get("uid")), V::Num(0.0));
                out_idx.set(q.get("uid"), js::add(&k, &V::Num(1.0))); // 부분 승계도 한 칸(가는 한 줄 · js/timeline.js _linkPlan과 같은 증분)
            }
            let (qe, pf) = (minute(&band_end(q)), minute(&band_start(p)));
            if qe.is_nullish() || pf.is_nullish() { continue; }
            let deg = edge.get("degree");
            let degree = if ty == SUCC_PARTIAL { if matches!(deg, V::Num(x) if x == 1.0 || x == 3.0) { js::to_i32(n(&deg)) } else { 2 } } else { 0 };
            let a = ty | (degree << 2)
                | (if lt(&q.get("_row"), &p.get("_row")) { LK.down } else { 0 }) | (if le(&band_end(q), &band_start(p)) { LK.q_first } else { 0 })
                | (if eq(&p.get("_seamL"), q) && eq(&q.get("_row"), &p.get("_row")) { LK.seam } else { 0 }) | (if succ_absorbs(q, p) { LK.absorb } else { 0 })
                | (if bundled.has(edge) { LK.bundled } else { 0 })
                | (if q.bool("endUnknown") { LK.unk_q } else { 0 }) | (if p.bool("startUnknown") { LK.unk_p } else { 0 })
                | (if q.bool("endRange") { LK.range_q } else { 0 }) | (if p.bool("startRange") { LK.range_p } else { 0 })
                | (if refuted(q) || refuted(p) { LK.refuted } else { 0 });
            let note = edge.get("note");
            let tip = format!("{} → {} · {}{}", t(&q.get("name")), t(&p.get("name")), succession_label(edge), if tv(&note) { format!(" · {}", t(&note)) } else { String::new() });
            // 실리는 단계는 두 띠 가운데 짧은 쪽이 보이는 단계(명세 8-1절) — 두 끝이 다 보이지 않는 배율에서는 선도 없다.
            let span = js::min(&[n(&minute(&band_end(q))) - n(&minute(&band_start(q))), n(&minute(&band_end(p))) - n(&minute(&band_start(p)))]);
            item(out, o! {
                "section" => SECTION.link, "track" => track, "row" => js::min(&[n(&q.get("_row")), n(&p.get("_row"))]), "row2" => js::max(&[n(&q.get("_row")), n(&p.get("_row"))]),
                "start" => js::min(&[n(&qe), n(&pf)]), "end" => js::max(&[n(&qe), n(&pf)]), "lod" => lod_of(span),
                "ref" => q.get("uid"), "name" => tip, "color" => f64::from(color(&q.get("color"), 0xa4b1b7)), "a" => f64::from(a), "b" => id_of(&p.get("uid"))?, "c" => js::round(n(&k) * 10.0), "d" => 0.0, "text2" => p.get("uid"),
            });
            bump(&counts, "승계선");
        }

        /* ── 구역 22 · 소속선 ────────────────────────────────────────────────────
           상위 띠 아래에 펼쳐진 소속(singleHost)만. 같은 상국 아래 관계만 바뀌어 이어지는 구간은 선 하나로 묶는다 — 넣을 때는 **시각이 꼭 같은 것만** 묶는다. */
        for p in &periods {
            if !p.bool("hosts") || !tv(&p.get("hosts").get("length")) || p.bool("_folded") || p.bool("_hidden") || p.bool("_overlay") || p.get("_row").is_nullish() || !p.bool("singleHost") || p.bool("groupUid") { continue; } // 단체의 띠(조각 ④)는 소속선 없음
            let hosts = list(&p.get("hosts"));
            let any_rel = hosts.iter().any(|h| h.bool("relation"));
            let joined = |x: &V, y: &V| any_rel && eq(&x.get("host").get("uid"), &y.get("host").get("uid")) && eq(&nn(x.get("end"), p.get("endY")), &nn(y.get("start"), p.get("start")));
            for j in 0..hosts.len() {
                let h = &hosts[j];
                if j > 0 && joined(&hosts[j - 1], h) { continue; }
                let mut last = h.clone();
                let mut rels: Vec<V> = vec![rel_name(h)];
                let mut tt = j + 1;
                while tt < hosts.len() && joined(&hosts[tt - 1], &hosts[tt]) { last = hosts[tt].clone(); rels.push(rel_name(&last)); tt += 1; }
                let hu = h.get("host").get("uid");
                let host = periods.iter().find(|o| eq(&o.get("uid"), &hu)).cloned();
                let skip = match &host { None => true, Some(host) => host.bool("_folded") || host.bool("_hidden") || host.get("_row").is_nullish() || eq(&host.get("_row"), &p.get("_row")) || hidden(&p.get("_row"))? || hidden(&host.get("_row"))? };
                if skip { bump(&skipped, "소속_상국없음"); continue; }
                let host = host.expect("위에서 봄");
                let (s, e) = (minute(&nn(h.get("start"), p.get("start"))), minute(&nn(last.get("end"), p.get("endY"))));
                if s.is_nullish() || e.is_nullish() || lt(&e, &s) { continue; }
                let truthy: Vec<V> = rels.into_iter().filter(tv).collect();
                let kept: Vec<V> = truthy.iter().enumerate().filter(|(i, x)| *i == 0 || !eq(x, &truthy[i - 1])).map(|(_, x)| x.clone()).collect();
                let rel = join(&kept, " → ");
                let kind = kind_name(&p.get("polityKind"));
                let tip = format!("{} — {} 소속 ({kind}{})", t(&p.get("name")), t(&host.get("name")), if !rel.is_empty() && rel != kind { format!(" · 소속 관계: {rel}") } else { String::new() });
                let lanes = tr.get("hangRowLanes");
                let c = if tv(&lanes) { match &lanes { V::Map(m) => or(m.get(&host.get("_row")), V::Num(0.0)), _ => return Err("tr.hangRowLanes가 Map이 아닙니다 — JS라면 .get에서 멈춤".into()) } } else { V::Num(0.0) };
                item(out, o! {
                    "section" => SECTION.part, "track" => track, "row" => js::min(&[n(&p.get("_row")), n(&host.get("_row"))]), "row2" => js::max(&[n(&p.get("_row")), n(&host.get("_row"))]), "start" => s, "end" => e, "lod" => -1.0,
                    "ref" => p.get("uid"), "name" => tip, "color" => f64::from(color(&host.get("color"), 0xa4b1b7)),
                    "a" => f64::from((if lt(&host.get("_row"), &p.get("_row")) { 1 } else { 0 }) | (if refuted(p) || refuted(&host) { 2 } else { 0 })),
                    "b" => id_of(&host.get("uid"))?, "c" => c, "d" => 0.0, "text2" => rel,
                });
                bump(&counts, "소속선");
            }
        }

        /* ── 구역 25 · 할거기 칠 · 구역 27 · '▸ 〈성격〉 n' 단추 ───────────────────
           상징적 본국(대범위의 host이고 s.afterHost가 아닌 것)의 띠에 대범위를 꺼 두어도 보이는 둘. */
        for p in &periods {
            if !drawn(p)? { continue; }
            let hosted = tl.get("_hosted");
            let l = if tv(&hosted) { match &hosted { V::Map(m) => m.get(&p.get("uid")), _ => return Err("tl._hosted가 Map이 아닙니다 — JS라면 .get에서 멈춤".into()) } } else { hosted };
            if !tv(&l) { continue; }
            for s in list(&l) {
                let a0 = js::max(&[n(&s.get("start")), n(&band_start(p))]);
                let b0 = js::min(&[n(&s.get("endY")), n(&band_end(p))]);
                if !(b0 > a0) { continue; }
                let (start, end) = (minute(&V::Num(a0)), minute(&V::Num(b0)));
                if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
                item(out, o! {
                    "section" => SECTION.hollow, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => start.clone(), "end" => end.clone(), "lod" => -1.0,
                    "ref" => p.get("uid"), "name" => or(s.get("name"), V::from("")), "color" => f64::from(color(&s.get("color"), 0xa4b1b7)), "a" => 0.0, "b" => 0.0, "c" => 0.0, "d" => 0.0, "text2" => or(s.get("label"), V::from("할거")),
                });
                bump(&counts, "할거기칠");
                let cnt = items(&s.get("members")).iter().filter(|m| periods.iter().any(|x| eq(x, m))).count();
                if cnt == 0 { continue; }
                item(out, o! {
                    "section" => SECTION.scope_btn, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => start, "end" => end, "lod" => -1.0,
                    "ref" => p.get("uid"), "name" => or(s.get("label"), V::from("대범위")), "color" => f64::from(color(&s.get("color"), 0xa4b1b7)), "a" => cnt as f64, "b" => 0.0, "c" => 0.0, "d" => 0.0, "text2" => s.get("uid"),
                });
                bump(&counts, "대범위단추");
            }
        }
    }

    /* ── 구역 49 · 동군연합 이음줄의 끝(건의 8의 6-다 · 2026-10-14) · 구역 52 · 옮겨 앉기의 끝 ───────────────────
       a = 이 끝의 지도자 칸 순번(leader:a) · b = 짝 띠의 번호 · c = 짝의 지도자 칸 순번 · name = 풍선 글. 엔진은 뜻을 모른 채 나른다(새 칸 없음). */
    // 트랙 번호는 지금 tl.tracks의 차례(승계선 · 소속선의 tl.tracks.forEach 순번과 같게) — 판을 다시 돌릴 때(boards.mjs replay)는 ctx.trackIndex(전체 차례)와 다르다.
    let tracks = list(&tl.get("tracks"));
    let track_index = Map::new();
    for (i, tt) in tracks.iter().enumerate() { track_index.set(tt.get("id"), i as f64); }
    // 끝의 트랙은 그 나라가 지금 놓인 트랙이다(자료의 track이 아니라 — 판을 켜면 판 트랙) · 웹 _planUnions의 trackOf(tr.periods에 드는가)와 같은 규칙.
    let placed_in = Map::new();
    for tt in &tracks { for p in list(&tt.get("periods")) { placed_in.set(p, tt.clone()); } }
    let placed_index = |p: &V| -> crate::Result<V> {
        let tt = placed_in.get(p);
        if tt.is_nullish() { return Err(format!("놓이지 않은 정권의 트랙을 물었습니다: {} — JS라면 placedIn.get(p).id에서 멈춤", t(&p.get("name"))).into()); }
        Ok(nn(track_index.get(&tt.get("id")), V::Num(0.0)))
    };
    let drawable = |p: &V| -> crate::Result<bool> {
        let tt = if tv(p) { placed_in.get(p) } else { p.clone() };
        if !tv(&tt) { return Ok(false); }
        let row = p.get("_row");
        if p.bool("_folded") || p.bool("_hidden") || p.bool("_under") || p.bool("_overlay") || row.is_nullish() || !le(&V::Num(0.0), &row) || !lt(&row, &tt.get("rows")) { return Ok(false); }
        let hr = tt.get("hiddenRows");
        if tv(&hr) && has_or_err(&hr, &row, "tr.hiddenRows")? { return Ok(false); }
        Ok(!has_or_err(&tt.get("foldedRows"), &row, "tr.foldedRows")?)
    };
    /* ── 구역 52 · 옮겨 앉기의 끝(리메이크 2부 · 결정 #3 A) ───────────────────
       다리(core.js splitMoves — HT.F4.split)가 나눈 토막('<원 id>.mv<경계 해>')의 짝(앞 → 뒤)마다 끝 둘(구역 49와 같은 꼴): row = 그 토막의 줄 · ref = 그 토막 ·
       start = 옮긴 해 · end = 옮긴 해 + 두 토막 가운데 짧은 길이(단계 셈) · a = 0 앞 끝 / 1 뒤 끝 · b = 짝 토막의 번호 · name = 풍선 글 · text2 = 짝 열쇠(뒤 토막 uid). */
    {
        let model_periods = items(&ctx.model.get("periods"));
        for p in &model_periods {
            let Some((cut_base, cut_at)) = cut_of(p) else { continue };
            let q = model_periods.iter().find(|x| {
                !eq(x, p) && eq(&x.get("packId"), &p.get("packId")) && eq(&x.get("track"), &p.get("track"))
                    && (is(&x.get("id"), &cut_base) || t(&nn(x.get("id"), V::from(""))).starts_with(&format!("{cut_base}.mv")))
                    && !x.get("endY").is_nullish() && (n(&x.get("endY")) - cut_at).abs() < 1e-9
            }).cloned();
            let Some(q) = q else { continue };
            if !drawable(&q)? || !drawable(p)? { continue; }
            let at = minute(&V::Num(cut_at));
            let len = js::min(&[n(&q.get("endY")) - n(&q.get("start")), n(&nn(p.get("endY"), V::Num(cut_at))) - cut_at]);
            let until = minute(&V::Num(cut_at + js::max(&[len, 1e-3])));
            if at.is_nullish() || until.is_nullish() { continue; }
            let tip = format!("{} — 옮겨 앉음 · {}", t(&or(p.get("name"), V::from(""))), format_year(&V::Num(cut_at)));
            for (me, other, a) in [(&q, p, 0.0), (p, &q, 1.0)] {
                item(out, o! {
                    "section" => SECTION.r#move, "track" => placed_index(me)?, "row" => me.get("_row"), "row2" => me.get("_row"), "start" => at.clone(), "end" => n(&at) + js::max(&[1.0, n(&until) - n(&at)]), "lod" => -1.0,
                    "ref" => me.get("uid"), "name" => tip.clone(), "color" => f64::from(color(&me.get("color"), 0xa4b1b7)), "a" => a, "b" => id_of(&other.get("uid"))?, "c" => 0.0, "d" => 0.0, "text2" => p.get("uid"),
                });
            }
            counts.set("옮겨앉기끝", n(&or(counts.get("옮겨앉기끝"), V::Num(0.0))) + 2.0);
        }
    }
    for u in union_pairs(rc, &ctx.model)? {
        let (ua, ub) = (u.get("a"), u.get("b"));
        if !drawable(&ua.get("p"))? || !drawable(&ub.get("p"))? { continue; }
        let (at, s0, e0) = (minute(&u.get("mid")), minute(&u.get("s")), minute(&u.get("e")));
        if at.is_nullish() || s0.is_nullish() || e0.is_nullish() { continue; }
        let tip = format!("동군연합 · {} — {} · {} · {} ~ {}", t(&u.get("name")), t(&ua.get("p").get("name")), t(&ub.get("p").get("name")), format_year(&u.get("s")), format_year(&u.get("e")));
        for (me, other) in [(&ua, &ub), (&ub, &ua)] {
            item(out, o! {
                "section" => SECTION.union, "track" => placed_index(&me.get("p"))?, "row" => me.get("p").get("_row"), "row2" => me.get("p").get("_row"), "start" => at.clone(), "end" => n(&at) + js::max(&[1.0, n(&e0) - n(&s0)]), "lod" => -1.0,
                "ref" => me.get("p").get("uid"), "name" => tip.clone(), "color" => 0.0, "a" => me.get("i"), "b" => id_of(&other.get("p").get("uid"))?, "c" => other.get("i"), "d" => 0.0, "text2" => u.get("key"),
            });
            bump(&counts, "동군연합끝");
        }
    }

    /* ── 구역 60 · 트랙을 건너는 승계의 짝 꼬리표(2026-10-25 감독 결정 (2) · 가지 line-routing — 명세 04 3-1 · 8-3) ───────────────────
       구역 21이 '승계_트랙밖'으로 버리는 쌍(선대가 이 트랙에 놓이지 않음)마다 끝 둘(구역 49 · 52와 같은 꼴): 앞 끝 = 선대 q가 놓인 트랙 · 줄 · bandEnd,
       뒤 끝 = 후대 p의 트랙 · 줄 · bandStart. end = start + 두 띠 가운데 짧은 길이(적어도 1분 — 구역 52와 같게) · lod = 그 길이의 단계(구역 21과 같은 셈) ·
       ref = 이 끝의 띠 · name · color = 상대 이름 · 색 · a = 0 앞 끝 / 1 뒤 끝 · b = 상대 띠의 번호 · c = 승계 종류(0 ~ 3) · text2 = 상대 띠의 uid.
       거름은 구역 21과 같은 뜻(선대의 숨은 줄은 선대가 놓인 트랙의 것)이고, 선대가 어느 트랙에도 놓이지 않았으면 없음 · 대범위 부흥선으로 묶이는 쌍은 뺌.
       다른 항목의 차례가 바뀌지 않게 이 모듈의 맨 끝에 싣는다. */
    for (track, tr) in tracks.iter().enumerate() {
        let track = track as f64;
        let periods = list(&tr.get("periods"));
        let placed = Set::new();
        for p in &periods { placed.add(p.clone()); }
        let bundled = bundled_edges(&tl, tr);
        let hidden_in = |tt: &V, row: &V| -> crate::Result<bool> {
            let hr = tt.get("hiddenRows");
            if !tv(&hr) { return Ok(false); }
            has_or_err(&hr, row, "tr.hiddenRows")
        };
        for p in &periods {
            if p.bool("_folded") || p.bool("_hidden") || p.bool("_overlay") { continue; }
            for edge in items(&p.get("predecessors")) {
                let q = edge.get("from");
                if !tv(&q) || placed.has(&q) || bundled.has(&edge) { continue; }
                let qt = placed_in.get(&q);
                if !tv(&qt) { continue; }
                if q.get("_row").is_nullish() || p.get("_row").is_nullish() || q.bool("_folded") || q.bool("_hidden") || q.bool("_under") || q.bool("_overlay") || hidden_in(&qt, &q.get("_row"))? || hidden_in(tr, &p.get("_row"))? { continue; }
                let (qe, pf) = (minute(&band_end(&q)), minute(&band_start(p)));
                if qe.is_nullish() || pf.is_nullish() { continue; }
                let ty = succ_no(&edge.get("type")).unwrap_or(SUCC_INDIRECT);
                let span = js::min(&[n(&minute(&band_end(&q))) - n(&minute(&band_start(&q))), n(&minute(&band_end(p))) - n(&minute(&band_start(p)))]);
                for (me, other, at, a, tk) in [(&q, p, &qe, 0.0, placed_index(&q)?), (p, &q, &pf, 1.0, V::Num(track))] {
                    item(out, o! {
                        "section" => SECTION.cross, "track" => tk, "row" => me.get("_row"), "row2" => me.get("_row"), "start" => at.clone(), "end" => n(at) + js::max(&[1.0, span]), "lod" => lod_of(span),
                        "ref" => me.get("uid"), "name" => or(other.get("name"), V::from("")), "color" => f64::from(color(&other.get("color"), 0xa4b1b7)), "a" => a, "b" => id_of(&other.get("uid"))?, "c" => f64::from(ty), "d" => 0.0, "text2" => other.get("uid"),
                    });
                }
                counts.set("트랙건넘끝", n(&or(counts.get("트랙건넘끝"), V::Num(0.0))) + 2.0);
            }
        }
    }

    ctx.notes.set("관계선", counts);
    ctx.notes.set("관계선에서_뺀_것", skipped);
    Ok(())
}

/// `cutOf(p)` — `/^(.*)\.mv(-?\d+(?:\.\d+)?)$/.exec(String(p.id ?? ''))` → (원 id, 경계 해). 손으로: 줄 끝 글자(`.`이 맞지 않는 \n \r U+2028 U+2029)가 없고,
/// 가장 오른쪽의 '.mv' 뒤가 `-?\d+(\.\d+)?`(ASCII 숫자)로 끝까지 맞으면(욕심 많은 `(.*)` — 맞는 자리 가운데 가장 오른쪽).
fn cut_of(p: &V) -> Option<(String, f64)> {
    let id = t(&nn(p.get("id"), V::from("")));
    if id.chars().any(|c| matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}')) { return None; }
    let num_ok = |s: &str| -> bool {
        let s = s.strip_prefix('-').unwrap_or(s);
        let (whole, frac) = match s.split_once('.') { Some((w, f)) => (w, Some(f)), None => (s, None) };
        !whole.is_empty() && whole.bytes().all(|b| b.is_ascii_digit()) && frac.map_or(true, |f| !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit()))
    };
    // `.mv`는 저와 겹치지 않으므로 모든 자리를 찾아 오른쪽부터 본다.
    let at: Vec<usize> = id.match_indices(".mv").map(|(i, _)| i).collect();
    for &i in at.iter().rev() {
        let rest = &id[i + 3..];
        if num_ok(rest) { return Some((id[..i].to_string(), js::to_num(&V::from(rest)))); }
    }
    None
}

/// 소속 한 구간의 관계 이름(지금 연표의 depRel)
fn rel_name(h: &V) -> V {
    if !tv(h) || !h.bool("relation") { return V::from(""); }
    V::from(relation_name(&h.get("relation")))
}

/// 대범위 부흥선으로 묶이는 승계 한 건들(_scopeBranches의 tr._bundled) — 대범위를 켰을 때만 실제로 묶이지만,
/// 자료로는 '본국이 끝난 뒤 생긴 대범위(afterHost)의 구성 정권이 본국을 부흥으로 가리키는 것'으로 정해진다.
fn bundled_edges(tl: &V, tr: &V) -> Set {
    let set = Set::new();
    let data = tl.get("_data");
    for s in items(&if tv(&data) { data.get("scopes") } else { data }) {
        if !s.bool("afterHost") || !s.bool("host") { continue; }
        for m in items(&s.get("members")) {
            if !tv(&m) || !eq(&m.get("track"), &tr.get("id")) { continue; }
            for e in items(&m.get("predecessors")) { if is(&e.get("type"), "revival") && eq(&e.get("from"), &s.get("host")) { set.add(e); } }
        }
    }
    set
}

//! 내보내기 모듈 `boards` — `prototype/scripts/export/boards.mjs`(1 ~ 578줄 · SHA-256 앞 12자 `d285b8d53915`)를 줄 그대로 옮긴다(한 벌 P3 과제 15 · 갈래 E).
//! 집합 보기 — 판마다 '판을 켠 배치'를 미리 셈해 변형 kind 3(`view:<id>` · 시대 구분의 임시 판 `view:epoch:<uid>`)으로 새 겉 열쇠 `boards`에 싣는다:
//! `tl.board`를 걸고 `_boardPlan`(→ [`board_plan`]) → 판 트랙 · 원래 트랙을 다시 배치(→ [`layout_track`]의 판 갈래) → REPLAY 열두 모듈을 판 트랙과 원래 트랙에만
//! 다시 돌려(`sub` — 사건을 거른 얕은 사본 모델 · [`Sub`]) 기본 상태와 견준다. 판 하나의 오류는 잡아서 `notes.뺀판`에 적고 그 판을 뺀다(JS 그대로).
//! 판마다 되돌림(판정 R24 3): `tl.tracks` = 처음 목록의 사본 · 트랙마다 `periods` · `events` · `figures` · `axisPeriods` 지움 · `tl.board = null` · `_boardTr = null` ·
//! `_boardUids = null` · `_boardOpen = 빈 Set` · `_boardFolded = false` · 영향받은 트랙 다시 배치. 다 돌린 뒤 연표가 기본 배치로 돌아왔는지 본다(어긋나면 오류 — Node의 assert).
//!
//! 함께 옮긴 웹 함수: `js/timeline.js` 2440 ~ 2453줄 `echoBands`(SHA-256 앞 12자 `8a3b02f5bf7f` — `order`만 읽으므로 그 값을 셈) → [`echo_bands`].
//! `_boardPlan` · `_boardVisit` · `_boardGroups` · `_boardBranch`(8876 ~ 9008줄)는 줄 배정 쪽 [`crate::lay::track`]. 이미 옮긴 것: `HT.readScopeRefs` · `HT.isColor` · `HT.pastel` ·
//! `HT.itemKindOf` · `tl._scopePad` · variants.mjs의 `G` · `rowHeight` · `trackValuesOf`(→ [`super::variants`]).
//! 칸 · 그릴 것의 견줌 열쇠는 boards.mjs 그대로 빈 글로 잇는다(variants.mjs는 U+0001 — 원본이 다름).
use super::kit::jtruthy;
use super::variants::{jassign, jkey, jpart, jstr, jstrict, len_of, num_or0, row_height, row_key_of, track_values_of, Sub, G, REPLAY};
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color, jn, jsv, jv};
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, copy, eq, is, item_kind_of, list, n, ob, or, pastel, s, t, take_fault, tv};
use crate::lay::read::cells::read_scope_refs;
use crate::lay::read::misc::is_color;
use crate::lay::rows::{band_end, band_start, items};
use crate::lay::scope::scope_pad;
use crate::lay::track::{board_plan, layout_track};
use serde_json::{json, Value};
use std::collections::HashMap;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 변형 번호(계약 부록 가-9의 예약): 3 집합 보기.
pub const BOARD_KIND: f64 = 3.0;
/// 지금 연표의 판 트랙 id(js/timeline.js의 BOARD_ID).
const BOARD_ID: &str = crate::lay::track::BOARD_ID;
/// 판의 기본 색 — 파스텔 열두 가지의 버터(js/views-ui.js의 BUTTER).
const BUTTER: &str = "#d7c18e";

/// 칸 · 그릴 것을 견주는 열쇠(boards.mjs — 빈 글로 이음). 칸은 (띠 · 종류 · 기간 · 이름)이 같으면 같은 칸이고 단 · 모양 · 색이 달라지면 변형 판이다.
fn cell_key_of(c: &Value) -> String { ["period", "kind", "start", "end", "name"].iter().map(|k| jpart(c.get(*k))).collect() }
fn cell_same_of(c: &Value) -> String { ["lane", "style", "color"].iter().map(|k| jpart(c.get(*k))).collect() }
/// `sig(it, row, row2)` — 그릴 것의 모습 전체(줄은 엔진 번호 공간으로 옮겨 적은 뒤).
fn sig(it: &Value, row: f64, row2: f64) -> String {
    let mut s_ = jpart(it.get("section"));
    s_.push_str(&js::num_str(row));
    s_.push_str(&js::num_str(row2));
    for k in ["start", "end", "lod", "ref", "name", "color", "a", "b", "c", "d", "text2"] { s_.push_str(&jpart(it.get(k))); }
    s_
}

/// 판 하나(`boardsOf`의 칸).
struct Board { key: String, uid: V, name: V, color: V, members: Vec<V>, start: V, end: V, temp: bool, pack: f64, record: Obj }

/// `tl.echoBands()` — 정권마다 그 정권이 연표에 그려지는 띠의 `order`(연표 위에서 아래로의 차례 = 트랙 번호 + (줄 + 1) / (줄 수 + 2)) — 이 모듈은 `order`만 읽는다.
pub fn echo_bands(tl: &V) -> Map {
    let out = Map::new();
    for (ti, tr) in items(&tl.get("tracks")).iter().enumerate() {
        let rows = n(&or(tr.get("rows"), V::Num(0.0))) + 2.0;
        for p in items(&tr.get("periods")) {
            let mut q = p.clone();
            while tv(&q) && q.bool("_hidden") { q = q.get("_host"); }
            if !tv(&q) { q = p.clone(); }
            let row = q.get("_row");
            // `tr.foldedRows && tr.foldedRows.has(row)` — Set · Map이면 그 답, 참인데 그 밖이면 JS는 `.has`에서 TypeError: 잘못으로 남긴다(`kit::has_of` — 16b 검토 ③ Minor 1).
            let folded_rows = tr.get("foldedRows");
            let folded = tr.bool("folded") || q.bool("_folded") || (!row.is_nullish() && tv(&folded_rows) && super::kit::has_of(&folded_rows, &row).unwrap_or_else(|| {
                crate::lay::model::util::fault(format!("트랙 {}의 foldedRows가 Set · Map이 아닙니다(JS라면 .has에서 TypeError)", t(&tr.get("id"))));
                false
            }));
            let drawn = !folded && !row.is_nullish() && !q.bool("_under") && !q.bool("_overlay");
            let order = ti as f64 + (n(&js::nullish(row, V::Num(rows - 2.0))) + 1.0) / rows;
            out.set(p.get("uid"), o! {
                "band" => q.get("uid"), "start" => band_start(&q), "end" => band_end(&q), "order" => order, "drawn" => drawn, "folded" => folded, "hidden" => !eq(&q, &p),
                "name" => q.get("name"), "color" => q.get("color"), "track" => tr.get("id"),
            });
        }
    }
    out
}

/// `boardsOf(ctx)` — 판 목록: ① DLC가 준 판 ② 시대 구분마다 기본 후보 그대로의 임시 판(웹 views-ui.js의 boardOf · candidates · epochBoard와 같은 값).
fn boards_of(ctx: &Ctx) -> Vec<Board> {
    let (model, tl) = (&ctx.model, &ctx.tl);
    let mut out: Vec<Board> = Vec::new();
    let mut keys: std::collections::HashSet<String> = std::collections::HashSet::new();
    let model_tracks = items(&model.get("tracks"));
    let track_name = |id: &V| -> V { match model_tracks.iter().find(|x| eq(&x.get("id"), id)) { Some(tr) => or(tr.get("name"), id.clone()), None => id.clone() } };
    let member_rows = |l: &[V]| -> V {
        arr(l.iter().map(|p| V::Obj(o! {
            "uid" => p.get("uid"), "name" => or(p.get("name"), s("")), "color" => or(p.get("color"), s("")), "track" => or(p.get("track"), s("")), "trackName" => track_name(&p.get("track")),
        })).collect())
    };
    let track_count = |l: &[V]| { let st = Set::new(); for p in l { st.add(p.get("track")); } st.len() as f64 };
    for v in items(&model.get("views")) {
        let members: Vec<V> = items(&v.get("members")).into_iter().filter(tv).collect();
        if members.is_empty() { continue; } // 구성 나라를 하나도 찾지 못한 판은 켤 수 없다
        let key = t(&v.get("uid")); // `view:<id>`
        if keys.contains(&key) { continue; }
        keys.insert(key.clone());
        let missing = js::max(&[0.0, read_scope_refs(&v.get("memberRefs")).len() as f64 - members.len() as f64]);
        let start = v.get("start");
        let ok_start = !start.is_nullish() && matches!(start, V::Num(x) if x.is_finite());
        let end_y = v.get("endY");
        out.push(Board {
            key, uid: v.get("uid"), name: or(v.get("name"), s("")), color: or(v.get("color"), s(BUTTER)), members: members.iter().map(|p| p.get("uid")).collect(),
            start: if ok_start { start.clone() } else { V::Undef },
            end: if !start.is_nullish() && matches!(end_y, V::Num(x) if x.is_finite()) { end_y } else { V::Undef },
            temp: false, pack: ctx.pack_of(&v),
            record: o! { "view" => v.get("uid"), "packName" => or(v.get("packName"), s("")), "members" => member_rows(&members), "tracks" => track_count(&members), "missing" => missing },
        });
    }
    // 시대 구분의 카드: 같은 트랙(공통 시대 구분이면 모든 트랙) · 기간이 겹치는 나라(기관 · 문화 · 왕조 빼고) · 이어진 대범위의 구성 나라는 빼고.
    // 차례 = 연표의 줄 차례(echoBands의 order — 판을 켜기 전에 잰 것) → 시작 해.
    let ord = echo_bands(tl);
    let t_order = Map::new();
    for (i, tr) in model_tracks.iter().enumerate() { t_order.set(tr.get("id"), i as f64); }
    let at = |p: &V| -> f64 {
        if ord.has(&p.get("uid")) { n(&ord.get(&p.get("uid")).get("order")) } else { n(&js::nullish(t_order.get(&p.get("track")), V::Num(1e6))) + 0.999 }
    };
    for x in items(&model.get("epochs")) {
        let st = x.get("start");
        let en = if !x.get("endY").is_nullish() { x.get("endY") } else { x.get("start") };
        let (V::Num(sv), V::Num(ev)) = (&st, &en) else { continue };
        if !sv.is_finite() || !ev.is_finite() { continue; }
        let in_scopes = Set::new();
        for sc in items(&x.get("scopes")) { for p in items(&sc.get("members")) { in_scopes.add(p.get("uid")); } }
        let mut l: Vec<V> = items(&model.get("periods")).into_iter().filter(|p| {
            let pe = if !p.get("endY").is_nullish() { p.get("endY") } else { p.get("start") };
            is(&item_kind_of(p), "period") && (!tv(&x.get("track")) || eq(&p.get("track"), &x.get("track"))) && crate::lay::model::util::lt(&p.get("start"), &en)
                && crate::lay::model::util::lt(&st, &pe) && !in_scopes.has(&p.get("uid"))
        }).collect();
        js::sort(&mut l, |a, b| { let d = at(a) - at(b); if d != 0.0 && !d.is_nan() { d } else { n(&a.get("start")) - n(&b.get("start")) } });
        if l.is_empty() { continue; } // 웹도 후보가 없으면 카드를 두지 않는다
        let key = format!("view:epoch:{}", t(&x.get("uid")));
        if keys.contains(&key) { continue; }
        keys.insert(key.clone());
        let col = x.get("color");
        out.push(Board {
            key, uid: x.get("uid"), name: or(x.get("name"), s("")), color: pastel(&if is_color(&col) { col } else { s(BUTTER) }), members: l.iter().map(|p| p.get("uid")).collect(),
            start: st.clone(), end: en.clone(), temp: true, pack: ctx.pack_of(&x),
            record: o! {
                "epoch" => x.get("uid"), "epochTrack" => or(x.get("track"), s("")), "scoped" => if items(&x.get("scopes")).is_empty() { 0.0 } else { 1.0 },
                "packName" => or(x.get("packName"), s("")), "members" => member_rows(&l), "tracks" => track_count(&l), "missing" => 0.0,
            },
        });
    }
    out
}

/// 트랙 하나의 지금 배치(`snapTrack`) — 줄 자리 · 묶음 틈 · 대범위 여백.
struct SnapT { id: V, rows: usize, height: V, keys: Vec<String>, row_top: Vec<V>, scope_pad: Vec<f64>, group_start: Vec<f64> }
fn snap_track(tl: &V, tr: &V) -> SnapT {
    let rows = len_of(&tr.get("rows"));
    let board = tv(&tr.get("board"));
    let groups: Vec<V> = items(&tr.get("groups")).into_iter().filter(|gp| !board || gp.bool("from")).collect();
    SnapT {
        id: tr.get("id"), rows, height: tr.get("height"),
        keys: (0..rows).map(|r| row_key_of(tr, r as f64)).collect(),
        row_top: list(&tr.get("rowTop")),
        scope_pad: (0..rows).map(|r| js::round(scope_pad(tl, tr, r as f64, r as f64 - 1.0))).collect(),
        group_start: (0..rows).map(|r| if groups.iter().any(|gp| js::strict_eq(&gp.get("first"), &V::Num(r as f64))) { 1.0 } else { 0.0 }).collect(),
    }
}
/// `JSON.stringify([t.keys, t.rowTop, t.height])`(돌아왔는지 견줄 글).
fn snap_sig(t_: &SnapT) -> String {
    js::stringify(&arr(vec![arr(t_.keys.iter().map(|k| V::from(k.as_str())).collect()), arr(t_.row_top.clone()), t_.height.clone()]))
}

/// 판 전체의 셈 자리(`env`).
struct Env {
    track_at: Map, base: Vec<SnapT>, next_track: f64, base_band: Map, band_at: HashMap<String, (f64, f64)>, event_at: HashMap<String, (f64, f64)>,
    event_band: HashMap<String, V>, board_rows: Vec<f64>, base_first: Vec<f64>, base_total: f64, out_tracks: f64, cell_at: HashMap<String, Vec<usize>>,
    owner_of: Map, by_track: Vec<(f64, Vec<usize>)>,
}
impl Env {
    /// `env.firstRow(t)` — 엔진의 전체 줄 번호의 트랙 시작(옛 트랙의 줄 뒤에 판 트랙의 줄이 판 차례로).
    fn first_row(&self, t_: f64) -> f64 {
        if t_ < self.out_tracks { return self.base_first.get(t_ as usize).copied().unwrap_or(f64::NAN); }
        let k = (t_ - self.out_tracks).max(0.0) as usize;
        self.base_total + self.board_rows.iter().take(k).sum::<f64>()
    }
    /// `env.itemsOf(touched)` — 닿은 트랙들(넣은 차례)의 기본 항목 자리.
    fn items_of(&self, touched: &[f64]) -> Vec<usize> { touched.iter().flat_map(|t_| self.by_track.iter().find(|(k, _)| k == t_).map(|(_, l)| l.clone()).unwrap_or_default()).collect() }
    /// `env.itemsOutside(touched)` — 닿지 않은 트랙의 기본 항목 자리.
    fn items_outside(&self, touched: &[f64]) -> Vec<usize> { self.by_track.iter().filter(|(k, _)| !touched.contains(k)).flat_map(|(_, l)| l.clone()).collect() }
}

/// `replay(ctx, mods, baseBand, trackIds)` — 판을 켠 배치에서 REPLAY 모듈을 판 트랙 · 원래 트랙에만 다시 돌린다. 띠 번호는 기본 배치의 번호로(hangs 앞) ·
/// power 앞에서는 다시 돌린 out.periods의 순번으로. 사건 모듈의 '내보낸 사건 수 = 모델의 사건 수' 점검 때문에 다시 돌리는 트랙에 첫 자리가 있는 사건만 든 모델(얕은 사본)을 건넨다.
fn replay(ctx: &mut Ctx, base_band: &Map, track_ids: &Set) -> crate::Result<Value> {
    let mut out = json!({ "categories": [], "tracks": [], "epochs": [], "axis": [], "periods": [], "cells": [], "events": [], "items": [], "entities": [], "rowLabels": [] });
    let name = ctx.raws.first().map(|r| r.get("name")).unwrap_or(V::Undef);
    if !name.is_undef() { out["name"] = jsv(&name); }
    let first_track = |e: &V| { let pl = e.get("placements"); if tv(&pl) && tv(&pl.get("length")) { pl.get(&0.0).get("track") } else { e.get("track") } };
    let model = copy(&ctx.model);
    model.set("events", arr(items(&ctx.model.get("events")).into_iter().filter(|e| track_ids.has(&first_track(e))).collect()));
    let mut sub = Sub::new(ctx, Some(V::Obj(model)));
    for (mod_name, contribute) in REPLAY {
        let c = sub.ctx();
        if mod_name == "hangs" { c.shared.set("bandOf", base_band.clone()); }
        // 단체 단은 다시 돌린 out.periods의 기간 · 줄을 읽는다. 관계선용 기본 띠 번호를 넘기면 판의 다른 나라를 읽는다.
        if mod_name == "power" {
            let m = Map::new();
            for (i, p) in out["periods"].as_array().into_iter().flatten().enumerate() { m.set(jkey(p.get("uid")), i as f64); }
            c.shared.set("bandOf", m);
        }
        // 그 모듈이 오류로 돌아가면 남긴 잘못도 거둔다(finally의 '되돌린 배치' 글이 원래 까닭을 가리지 않게 — 16b 넘겨받은 틀 손질)
        if let Err(e) = contribute(c, &mut out) { let _ = take_fault(); return Err(e); }
        // JS라면 그 모듈에서 던졌을 곳(model::util::fault): 그 판의 오류로(→ 뺀판) — finally의 '되돌린 배치'로 미루지 않는다
        if let Some(msg) = take_fault() { return Err(format!("집합 보기 REPLAY의 {mod_name} 모듈 — {msg}(JS라면 TypeError)").into()); }
    }
    sub.finish();
    Ok(out)
}

/// 판 하나의 결과(`{ track, entry, cells, items, labels, entity, warn, note, gone }`).
struct Got { track: Value, entry: Value, cells: Vec<Value>, items: Vec<Value>, labels: Vec<Value>, entity: Value, warn: Vec<String>, note: Vec<String>, gone: usize }

/// `boardOne(ctx, mods, b, env)` — 지금 연표에 판을 걸고 다시 배치해 기본 상태와의 차이를 낸다. 판 트랙이 서지 않으면 None. 끝에(오류 길에서도) 판을 걷고 되돌린다.
fn board_one(ctx: &mut Ctx, b: &Board, env: &Env, out: &Value) -> crate::Result<Option<Got>> {
    let tl = ctx.tl.clone();
    let tlo = ob(&tl);
    let order0 = list(&tl.get("tracks"));
    let keep: Vec<(V, V, V, V)> = order0.iter().map(|tr| (tr.clone(), tr.get("periods"), tr.get("events"), tr.get("figures"))).collect();
    let mut affected: Vec<V> = Vec::new();
    tlo.set("board", o! {
        "id" => b.key.as_str(), "name" => b.name.clone(), "color" => b.color.clone(), "members" => arr(b.members.clone()), "start" => b.start.clone(), "end" => b.end.clone(), "temp" => b.temp,
    });
    let open = Set::new();
    for tr in &order0 { open.add(tr.get("id")); }
    tlo.set("_boardOpen", open); // 판을 켠 동안 나머지 트랙은 접히지만 — 접힘은 앱의 보기 상태라 여기서는 모두 편 채로 셈한다
    tlo.set("_boardFolded", false);
    let tried = board_try(ctx, b, env, out, &order0, &mut affected);
    // 판을 켠 동안 남은 잘못 — JS라면 try 안에서 이미 던졌을 것: 되돌림의 잘못과 가르려고 먼저 거둔다(16b 넘겨받은 틀 손질 — '되돌린 배치' 글이 원래 까닭을 가리지 않게)
    let pending = take_fault();
    // finally: 판을 걷고 되돌린다(판정 R24 3)
    tlo.set("tracks", arr(order0.clone()));
    for (tr, periods, events, figures) in &keep {
        let tro = ob(tr);
        tro.set("periods", periods.clone());
        tro.set("events", events.clone());
        tro.set("figures", figures.clone());
        tro.delete("axisPeriods");
    }
    tlo.set("board", V::Null);
    tlo.set("_boardTr", V::Null);
    tlo.set("_boardUids", V::Null);
    tlo.set("_boardOpen", Set::new());
    tlo.set("_boardFolded", false);
    for tr in &affected { layout_track(ctx, tr)?; } // 옮겨 갔던 정권의 배치 값(_row · _hidden · _seamL …)을 기본 상태로
    // JS finally: 되돌림이 던지면 그것이 앞의 것을 덮고, 아니면 try의 것(오류 · 던졌을 잘못)이 나간다(lens와 같은 몸 — `kit::try_finally`).
    super::kit::try_finally(tried, pending, take_fault(), "집합 보기: 판을 켠 배치", "집합 보기: 되돌린 배치")
}
/// `boardOne`의 `try` 몸.
fn board_try(ctx: &mut Ctx, b: &Board, env: &Env, out: &Value, order0: &[V], affected: &mut Vec<V>) -> crate::Result<Option<Got>> {
    let tl = ctx.tl.clone();
    let tlo = ob(&tl);
    board_plan(ctx)?;
    let btr = tl.get("_boardTr");
    if !tv(&btr) { return Ok(None); }
    *affected = order0.iter().filter(|tr| tv(&tr.get("axisPeriods"))).cloned().collect();
    layout_track(ctx, &btr)?;
    for tr in affected.iter() { layout_track(ctx, tr)?; }
    if let Some(msg) = take_fault() { return Err(format!("집합 보기: 판을 켠 배치 — {msg}(JS라면 TypeError)").into()); }
    let live: Vec<V> = std::iter::once(btr.clone()).chain(affected.iter().cloned()).collect();
    let all = tl.get("tracks");
    tlo.set("tracks", arr(live.clone()));
    let track_ids = Set::new();
    for tr in affected.iter() { track_ids.add(tr.get("id")); }
    let vout = replay(ctx, &env.base_band, &track_ids);
    tlo.set("tracks", all); // finally
    let vout = vout?;
    let got: Vec<SnapT> = live.iter().map(|tr| snap_track(&tl, tr)).collect();
    diff(b, env, out, &btr, affected, &got, &vout).map(Some)
}

/// `diff(ctx, b, env, btr, affected, got, vout)` — 판을 켠 배치(vout · 찍어 둔 자리 got)와 기본 상태(env)의 차이 → 판 트랙 하나 · 변형 하나 · 그 변형에서만 있는 것.
#[allow(clippy::too_many_arguments)]
fn diff(b: &Board, env: &Env, out: &Value, btr: &V, affected: &[V], got: &[SnapT], vout: &Value) -> crate::Result<Got> {
    let mut warn: Vec<String> = Vec::new(); // 어긋남 — 앱이 웹과 다르게 그린다
    let mut note: Vec<String> = Vec::new(); // 알림 — 판을 켜면 접히는 원래 트랙을 펼 때만 보이는 차이(트랙 단위 단)
    let mut slot_changed: Vec<f64> = Vec::new();
    let board_index = env.next_track; // 판 트랙의 번호(옛 트랙 · 앞선 판 트랙 뒤)
    // 다시 돌린 배치의 트랙 순번 → 엔진의 트랙 번호(판 트랙은 boardIndex)
    let track_of = |j: f64| -> crate::Result<f64> {
        if j == 0.0 { return Ok(board_index); }
        let tr = if j >= 1.0 && j.fract() == 0.0 { affected.get(j as usize - 1) } else { None };
        let Some(tr) = tr else { return Err(format!("{}: 다시 돌린 배치의 트랙 {}이 없습니다(JS라면 TypeError)", b.key, js::num_str(j)).into()) };
        Ok(n(&env.track_at.get(&tr.get("id"))))
    };

    // ── 줄 맞추기: 원래 트랙은 내용으로 기본 줄과 짝짓고, 판 트랙의 줄은 모두 새 줄이다 ──
    let mut row_map: Vec<HashMap<i64, f64>> = got.iter().map(|_| HashMap::new()).collect();
    for r in 0..got[0].keys.len() { row_map[0].insert(r as i64, r as f64); }
    let mut board_row_by_key: HashMap<&str, usize> = HashMap::new();
    for (r, k) in got[0].keys.iter().enumerate() { board_row_by_key.entry(k.as_str()).or_insert(r); }
    let mut gone: Vec<(f64, usize, f64)> = Vec::new(); // [트랙 번호, 줄, 옮겨 간 판 줄(없으면 −1)]
    for j in 1..got.len() {
        let a = track_of(j as f64)?;
        let base = &env.base[a as usize];
        let mut by_key: HashMap<&str, usize> = HashMap::new();
        for (r, k) in base.keys.iter().enumerate() { by_key.entry(k.as_str()).or_insert(r); }
        let mut used: Vec<usize> = Vec::new();
        for (r, k) in got[j].keys.iter().enumerate() {
            let at = by_key.get(k.as_str()).copied().filter(|x| !used.contains(x));
            let Some(at) = at else { return Err(format!("원래 트랙 {}에 기본 상태에 없던 줄이 생겼습니다({k}) — 판의 차이로 실을 수 없습니다", t(&base.id)).into()) };
            used.push(at);
            row_map[j].insert(r as i64, at as f64);
        }
        for r in 0..base.rows {
            if used.contains(&r) { continue; }
            gone.push((a, r, board_row_by_key.get(base.keys[r].as_str()).map_or(-1.0, |x| *x as f64)));
        }
    }
    let row_of = |j: &Value, r: &Value| -> crate::Result<f64> {
        let m = j.as_f64().filter(|x| *x >= 0.0 && x.fract() == 0.0).and_then(|x| row_map.get(x as usize));
        let Some(m) = m else { return Err(format!("{}: 다시 돌린 배치의 트랙 {}이 없습니다(JS라면 TypeError)", b.key, jstr(Some(j))).into()) };
        match r.as_f64().filter(|x| x.fract() == 0.0).and_then(|x| m.get(&(x as i64))) {
            Some(row) => Ok(*row),
            None => Err(format!("{}: 다시 돌린 배치의 줄 {}#{}을 옮길 곳이 없습니다", b.key, jstr(Some(j)), jstr(Some(r))).into()),
        }
    };

    // ── 판 트랙(새 트랙)과 그 줄 ──
    let Some(vt) = vout["tracks"].get(0).filter(|x| !x.is_null()) else { return Err(format!("{}: 다시 돌린 배치에 판 트랙이 없습니다(JS라면 TypeError — vt.name)", b.key).into()) };
    let Some(vt_rows) = vt["rows"].as_array().cloned() else { return Err(format!("{}: 판 트랙의 줄 목록이 없습니다(JS라면 TypeError — vt.rows.map)", b.key).into()) };
    let mut track = serde_json::Map::new();
    track.insert("key".into(), json!(format!("{BOARD_ID}:{}", b.key)));
    for k in ["name", "color", "dynasty", "leader", "cabinet", "organ", "railLevels"] { if let Some(x) = vt.get(k) { track.insert(k.into(), x.clone()); } }
    track.insert("rows".into(), Value::Array(vt_rows.iter().map(|r| jassign(r, &[("variant", json!(b.key))])).collect()));
    track.insert("groups".into(), json!([]));
    track.insert("pack".into(), jv(b.pack));
    let track = Value::Object(track);
    let mut entry = json!({ "key": b.key, "kind": jv(BOARD_KIND), "track": jv(board_index), "band": "", "uid": jsv(&b.uid), "name": jsv(&b.name), "notes": "", "rows": [], "moves": [], "hides": [], "groups": [] });
    for r in 0..vt_rows.len() {
        arr_mut(&mut entry, "rows").push(json!({
            "track": jv(board_index), "row": r, "after": if r == 0 { -1 } else { r as i64 - 1 }, "ord": 0, "new": 1,
            "scopePad": jv(js::round(got[0].scope_pad.get(r).copied().unwrap_or(f64::NAN))), "groupStart": jv(got[0].group_start.get(r).copied().unwrap_or(f64::NAN)),
        }));
    }

    // ── 원래 트랙: 사라진 줄(after −2 · to = 옮겨 간 판 줄)과 남은 줄의 새 차례 · 덮어쓰는 값 ──
    for &(a, row, to) in &gone {
        let mut o_ = json!({ "track": jv(a), "row": row, "after": -2, "ord": 0, "new": 0, "scopePad": 0, "groupStart": 0 });
        if to >= 0.0 { o_["toTrack"] = jv(board_index); o_["to"] = jv(to); }
        arr_mut(&mut entry, "rows").push(o_);
    }
    for j in 1..got.len() {
        let a = track_of(j as f64)?;
        let (base, tg) = (&env.base[a as usize], &got[j]);
        let order: Vec<f64> = (0..tg.rows).map(|r| row_map[j].get(&(r as i64)).copied().unwrap_or(f64::NAN)).collect();
        for r in 0..tg.rows {
            let row = order[r];
            let after = if r == 0 { -1.0 } else { order[r - 1] };
            let base_after = if row == 0.0 { -1.0 } else { row - 1.0 };
            let ri = row as usize;
            let pad_changed = base.scope_pad.get(ri).copied() != tg.scope_pad.get(r).copied();
            let group_changed = base.group_start.get(ri).copied() != tg.group_start.get(r).copied();
            // 줄의 생김새(글줄 · 단 …)는 변형이 덮어쓸 수 없다 — 달라지면 알린다(글줄 수 lines는 앱이 남은 줄 수로 다시 셈하므로 견주지 않는다).
            let rec = &vout["tracks"][j]["rows"][r];
            let old = &out["tracks"][a as usize]["rows"][ri];
            for k in ["bandH", "kind", "phase", "rank", "fig", "dep", "zones", "hem"] {
                if !jstrict(rec.get(k), old.get(k)) {
                    let line = format!("트랙 {} 줄 {}의 {k}가 {} → {}로 달라졌으나 싣지 않았습니다", js::num_str(a), js::num_str(row), jstr(old.get(k)), jstr(rec.get(k)));
                    if k == "bandH" { note.push(line); } else { warn.push(line); }
                }
            }
            if after != base_after || pad_changed || group_changed {
                arr_mut(&mut entry, "rows").push(json!({
                    "track": jv(a), "row": jv(row), "after": jv(after), "ord": 0, "new": 0,
                    "scopePad": jv(js::round(tg.scope_pad.get(r).copied().unwrap_or(f64::NAN))), "groupStart": jv(tg.group_start.get(r).copied().unwrap_or(f64::NAN)),
                }));
            }
        }
        // 트랙 단위 단(왕조 · 지도자 · 내각)은 트랙 하나의 값이라 변형이 바꿀 수 없다 — 원래 트랙을 판을 켠 채 펴면 기본 값으로 그린다(알림)
        let (vt2, ot) = (&vout["tracks"][j], &out["tracks"][a as usize]);
        for k in ["dynasty", "leader", "cabinet"] {
            if jstrict(vt2.get(k), ot.get(k)) { continue; }
            note.push(format!("트랙 {}의 {k} 단 {} → {}(판을 켠 채 그 트랙을 펴면 기본 값)", js::num_str(a), jstr(ot.get(k)), jstr(vt2.get(k))));
            slot_changed.push(a);
        }
    }
    {
        let mut seen: HashMap<String, f64> = HashMap::new();
        for r in arr_mut(&mut entry, "rows").iter_mut() {
            if r["after"].as_f64() == Some(-2.0) { continue; }
            let k = format!("{}#{}", jstr(r.get("track")), jstr(r.get("after")));
            let ord = seen.get(&k).copied().unwrap_or(0.0);
            r["ord"] = jv(ord);
            seen.insert(k, ord + 1.0);
        }
    }

    // ── 이사: 띠가 판 줄로 — 엔진은 칸 · 사건 · 그릴 것을 가리키는 띠를 따라 옮긴다 ──
    let g_ = |t_: f64, r: f64| env.first_row(t_) + r; // 엔진의 전체 줄 번호
    let mut band_dest: Vec<(String, f64)> = Vec::new(); // 옮긴 띠 → 전체 줄 번호(넣은 차례)
    let seen_bands = Set::new();
    for p in vout["periods"].as_array().into_iter().flatten() {
        seen_bands.add(jkey(p.get("uid")));
        let uid = jpart(p.get("uid"));
        let Some(&(w0, w1)) = env.band_at.get(&uid) else { warn.push(format!("기본 상태에 없던 띠가 생겼습니다: {}", jstr(p.get("name")))); continue };
        let now = (track_of(jn(&p["track"]))?, row_of(&p["track"], &p["row"])?);
        if now.0 == w0 && now.1 == w1 { continue; }
        arr_mut(&mut entry, "moves").push(json!({ "kind": 1, "ref": p["uid"].clone(), "track": jv(now.0), "row": jv(now.1) }));
        let d = g_(now.0, now.1);
        match band_dest.iter_mut().find(|(k, _)| *k == uid) { Some(x) => x.1 = d, None => band_dest.push((uid, d)) }
    }
    let band_dest_of = |uid: &str| band_dest.iter().find(|(k, _)| k == uid).map(|(_, d)| *d);
    let mut event_dest: Vec<(String, f64)> = Vec::new(); // 사건 → 엔진이 그리는 전체 줄(제 이사 → 든 띠의 이사 → 제자리)
    let mut followed = 0.0;
    for e in vout["events"].as_array().into_iter().flatten() {
        let uid = jpart(e.get("uid"));
        let Some(&(w0, w1)) = env.event_at.get(&uid) else { warn.push(format!("기본 상태에 없던 사건이 생겼습니다: {}", jstr(e.get("title")))); continue };
        let (t_, r) = (track_of(jn(&e["track"]))?, row_of(&e["track"], &e["row"])?);
        let now = g_(t_, r);
        let band = env.event_band.get(&uid).filter(|x| tv(x)).map_or_else(String::new, t);
        let engine = band_dest_of(&band).unwrap_or_else(|| g_(w0, w1));
        let mut set_dest = |d: f64| match event_dest.iter_mut().find(|(k, _)| *k == uid) { Some(x) => x.1 = d, None => event_dest.push((uid.clone(), d)) };
        if engine == now {
            if now != g_(w0, w1) { set_dest(now); followed += 1.0; }
            continue;
        }
        arr_mut(&mut entry, "moves").push(json!({ "kind": 2, "ref": e["uid"].clone(), "track": jv(t_), "row": jv(r) }));
        set_dest(now);
    }
    let mut touched: Vec<f64> = vec![board_index];
    for tr in affected { let x = n(&env.track_at.get(&tr.get("id"))); if !touched.contains(&x) { touched.push(x); } }
    for p in out["periods"].as_array().into_iter().flatten() {
        if !jtruthy(&p["variant"]) && p["track"].as_f64().is_some_and(|x| touched.contains(&x)) && !seen_bands.has(&jkey(p.get("uid"))) { warn.push(format!("판을 켜면 사라지는 띠: {}", jstr(p.get("name")))); }
    }

    // ── 칸: 띠를 따라간다. 단 · 모양 · 색이 달라진 칸만 변형 판(기본 판을 가림) ──
    let mut cells: Vec<Value> = Vec::new();
    for c in vout["cells"].as_array().into_iter().flatten() {
        match env.cell_at.get(&cell_key_of(c)) {
            Some(at) if at.len() == 1 => {
                if cell_same_of(&out["cells"][at[0]]) != cell_same_of(c) {
                    cells.push(jassign(c, &[("variant", json!(b.key))]));
                    arr_mut(&mut entry, "hides").push(json!({ "kind": 3, "at": at[0] }));
                }
                continue;
            }
            Some(_) => continue, // 이름이 같은 칸이 여럿 — 가릴 수 없어 그대로 둔다
            None => cells.push(jassign(c, &[("variant", json!(b.key))])),
        }
    }

    // ── 그릴 것: 기본 항목을 엔진이 옮겨 그릴 자리를 흉내 내어 판을 켠 배치의 항목과 값까지 같으면 그대로 둔다 ──
    let dests: Vec<f64> = band_dest.iter().map(|x| x.1).chain(event_dest.iter().map(|x| x.1)).collect();
    let engine_rows = |it: &Value| -> (f64, f64) {
        let (tr_, row, row2) = (jn(&it["track"]), jn(&it["row"]), jn(&it["row2"]));
        let (row, row2) = (g_(tr_, row), g_(tr_, row2));
        let rf = jpart(it.get("ref"));
        let to = if env.band_at.contains_key(&rf) { band_dest_of(&rf) } else { event_dest.iter().find(|(k, _)| *k == rf).map(|x| x.1) };
        let Some(to) = to else { return (row, row2) };
        if row == row2 { return (to, to); }
        let other = if dests.contains(&row) || row2 == to { row } else { row2 };
        (js::min(&[to, other]), js::max(&[to, other]))
    };
    let mut pool: Vec<(String, Vec<usize>)> = Vec::new(); // 엔진이 그릴 모습 전체 → 기본 항목의 자리 목록(넣은 차례)
    for at in env.items_of(&touched) {
        let it = &out["items"][at];
        let (row, row2) = engine_rows(it);
        let k = sig(it, row, row2);
        match pool.iter_mut().find(|(x, _)| *x == k) { Some(x) => x.1.push(at), None => pool.push((k, vec![at])) }
    }
    let mut items_v: Vec<Value> = Vec::new();
    for it in vout["items"].as_array().into_iter().flatten() {
        let pair = (|| -> crate::Result<(f64, f64)> { Ok((row_of(&it["track"], &it["row"])?, row_of(&it["track"], &it["row2"])?)) })();
        let (row, row2) = match pair {
            Ok(x) => x,
            Err(e) => {
                let what = if jtruthy(&it["name"]) { jstr(it.get("name")) } else if jtruthy(&it["ref"]) { jstr(it.get("ref")) } else { String::new() };
                return Err(format!("{e} — 그릴 것 구역 {} · {what}", jstr(it.get("section"))).into()); // 어느 모듈의 무엇이 줄을 벗어났는지
            }
        };
        let t_ = track_of(jn(&it["track"]))?;
        let (lo, hi) = (js::min(&[row, row2]), js::max(&[row, row2]));
        let k = sig(it, g_(t_, lo), g_(t_, hi));
        if let Some((_, l)) = pool.iter_mut().find(|(x, _)| *x == k) {
            if l.pop().is_some() { continue; } // 엔진이 그대로(또는 띠를 따라 옮겨) 그리는 기본 항목
        }
        items_v.push(jassign(it, &[("track", jv(t_)), ("row", jv(lo)), ("row2", jv(hi)), ("variant", json!(b.key))]));
    }
    for (_, l) in &pool { for at in l { arr_mut(&mut entry, "hides").push(json!({ "kind": 4, "at": at })); } }
    // 다시 돌리지 않은 트랙의 항목이 옮겨 간 띠 · 사건을 가리키면 엔진이 그 끝을 판으로 끌고 간다 — 가리고 제자리 그대로의 판으로 다시 싣는다
    for at in env.items_outside(&touched) {
        let it = &out["items"][at];
        let (row, row2) = engine_rows(it);
        let tr_ = jn(&it["track"]);
        if row == g_(tr_, jn(&it["row"])) && row2 == g_(tr_, jn(&it["row2"])) { continue; }
        arr_mut(&mut entry, "hides").push(json!({ "kind": 4, "at": at }));
        items_v.push(jassign(it, &[("variant", json!(b.key))]));
        note.push(format!("다른 트랙의 항목이 판으로 옮긴 것을 가리켜 제자리 판으로 다시 실었습니다: 구역 {}", jstr(it.get("section"))));
    }
    let _ = followed; // env.followed — 집계일 뿐(내보내지 않음)

    // ── 줄 이름: 판 줄의 것만 ──
    let mut labels: Vec<Value> = Vec::new();
    for l in vout["rowLabels"].as_array().into_iter().flatten() {
        if l["track"].as_f64() != Some(0.0) { continue; }
        labels.push(jassign(l, &[("track", jv(board_index)), ("variant", json!(b.key))]));
    }

    // ── 왼쪽 칸: 원래 트랙 칩(kind 3 · 첫 단) · 제 민족 칩(kind 0 · 문화는 1 · 둘째 단) — 판 트랙의 묶음 그대로 ──
    for gp in items(&btr.get("groups")) {
        if !tv(&gp.get("count")) { continue; }
        let (first, count) = (n(&gp.get("first")), n(&gp.get("count")));
        let mut rows = Vec::new();
        let mut r = first;
        while r < first + count { rows.push(jv(r)); r += 1.0; }
        let from = gp.bool("from");
        let key = if from { format!("__from:{}#{}", t(&gp.get("track")), t(&gp.get("first"))) } else { format!("__bp:{}#{}", t(&gp.get("key")), t(&gp.get("first"))) };
        arr_mut(&mut entry, "groups").push(json!({
            "track": jv(board_index), "key": key, "depth": jsv(&gp.get("depth")), "name": jsv(&or(gp.get("name"), s(""))), "color": color(&gp.get("color"), 0xa4b1b7),
            "kind": if from { 3 } else if gp.bool("culture") { 1 } else { 0 }, "rows": rows,
        }));
    }

    // ── 자체 점검: 기본 줄 + 이 변형의 차이로 앱과 같은 식으로 다시 쌓으면 지금 연표의 자리인가(경고로만 — 글은 entry.notes로) ──
    let mut checks: Vec<(usize, f64, &Value)> = vec![(0, board_index, &track)];
    for j in 1..got.len() { let a = track_of(j as f64)?; if !slot_changed.contains(&a) { checks.push((j, a, &out["tracks"][a as usize])); } }
    for (j, a, rec) in checks {
        let (top, height) = restack(a, rec, &entry);
        let tg = &got[j];
        for r in 0..tg.rows {
            let row = row_map[j].get(&(r as i64)).copied();
            let want = row.and_then(|x| top.iter().find(|(k, _)| *k as f64 == x).map(|(_, y)| *y));
            let have = tg.row_top.get(r).cloned().unwrap_or_default();
            if want.is_none_or(|w| (w - n(&have)).abs() > 0.001) {
                warn.push(format!("트랙 {} 줄 {}의 자리: 계약 {} ≠ 연표 {}", js::num_str(a), row.map_or_else(|| "undefined".to_string(), js::num_str),
                    want.map_or_else(|| "undefined".to_string(), js::num_str), t(&have)));
            }
        }
        if (height - n(&tg.height)).abs() > 0.001 { warn.push(format!("트랙 {}의 높이: 계약 {} ≠ 연표 {}", js::num_str(a), js::num_str(height), t(&tg.height))); }
    }
    if !warn.is_empty() || !note.is_empty() { entry["notes"] = json!(warn.iter().chain(note.iter()).take(6).cloned().collect::<Vec<_>>().join(" · ")); }

    // ── 판 기록(앱의 목록 · 시대 구분 카드) — json 글은 JS 차례 그대로(js::stringify) ──
    let present: Vec<&V> = b.members.iter().filter(|uid| env.owner_of.has(uid)).collect();
    let present_tracks = Set::new();
    for uid in &present { present_tracks.add(env.owner_of.get(uid)); }
    let label = { let bb = btr.get("board"); if tv(&bb) { or(bb.get("label"), s("")) } else { s("") } };
    let record = o! {
        "key" => b.key.as_str(), "name" => b.name.clone(), "color" => b.color.clone(), "temp" => if b.temp { 1.0 } else { 0.0 }, "label" => label,
        "present" => present.len() as f64, "presentTracks" => present_tracks.len() as f64,
    };
    if !b.start.is_nullish() { record.set("start", b.start.clone()); record.set("end", if !b.end.is_nullish() { b.end.clone() } else { b.start.clone() }); }
    for (k, x) in b.record.entries() { record.set(&k, x); }
    let entity = json!({ "uid": format!("board:{}", b.key), "kind": "board", "pack": jv(b.pack), "json": js::stringify(&V::Obj(record)) });
    Ok(Got { track, entry, cells, items: items_v, labels, entity, warn, note, gone: gone.len() })
}

/// `restack(trackIndex, record, entry)` — 기본 줄 + 판 변형의 차이로 트랙 하나를 다시 쌓는다(앱의 `_build` · `_orderOf`와 같은 차례): 사라진 줄(after −2)은 빼고,
/// 숨은 줄을 건너서도 묶음 경계(+14)는 남는다(건넌 줄 가운데 groupStart가 있으면). 다른 변형의 줄은 켜지 않았다.
fn restack(track_index: f64, record: &Value, entry: &Value) -> (Vec<(usize, f64)>, f64) {
    let rows: Vec<Value> = record["rows"].as_array().cloned().unwrap_or_default();
    let own: Vec<&Value> = entry["rows"].as_array().into_iter().flatten().filter(|r| r["track"].as_f64() == Some(track_index)).collect();
    let over = |r: usize| own.iter().rev().find(|x| x["row"].as_f64() == Some(r as f64)).copied(); // new Map(own) — 같은 줄이면 뒤의 것
    let gone_rows: Vec<usize> = own.iter().filter(|r| r["after"].as_f64() == Some(-2.0)).filter_map(|r| r["row"].as_f64().map(|x| x as usize)).collect();
    let key = entry["key"].clone();
    let live: Vec<usize> = (0..rows.len()).filter(|r| !gone_rows.contains(r) && (!jtruthy(&rows[*r]["variant"]) || rows[*r]["variant"] == key)).collect();
    let anchor = |r: usize| -> f64 { match over(r) { Some(x) => jn(&x["after"]), None => if r == 0 { -1.0 } else { r as f64 - 1.0 } } };
    let mut next: Vec<(f64, Vec<usize>)> = Vec::new();
    for &r in &live {
        let a = anchor(r);
        match next.iter_mut().find(|(k, _)| *k == a) { Some((_, kids)) => kids.push(r), None => next.push((a, vec![r])) }
    }
    let ord_of = |x: usize| over(x).map_or(0.0, |o_| num_or0(&o_["ord"]));
    for (_, kids) in next.iter_mut() { js::sort_by(kids, |x, y| { let d = ord_of(*x) - ord_of(*y); if d != 0.0 && !d.is_nan() { d } else { *x as f64 - *y as f64 } }); }
    let kids_of = |a: f64| next.iter().find(|(k, _)| *k == a).map(|(_, l)| l.clone()).unwrap_or_default();
    let mut order: Vec<usize> = Vec::new();
    let mut seen: Vec<usize> = Vec::new();
    let mut stack: Vec<usize> = kids_of(-1.0).into_iter().rev().collect();
    while let Some(r) = stack.pop() {
        if seen.contains(&r) { continue; }
        seen.push(r);
        order.push(r);
        let kids = kids_of(r as f64);
        for i in (0..kids.len()).rev() { stack.push(kids[i]); }
    }
    for &r in &live { if !seen.contains(&r) { order.push(r); } }
    let track = record; // 트랙 단위 단(왕조 · 지도자 · 내각)은 트랙 기록의 값 · 막대 단 수와 기관 칸은 보이는 줄들로(trackValuesOf)
    let on = track_values_of(track, &rows, &live);
    // 글줄 수: 앱(_bandOf)처럼 남은 줄 수로 — 분류별 글줄이 둘 이상이면 그 수, 아니면 자동 밀도의 문턱(6줄 이하면 2).
    let lines_of = |spec: &Value| -> f64 {
        let cats = spec["cats"].as_array().map_or(0, Vec::len);
        if jtruthy(&spec["cats"]) && cats >= 2 { cats as f64 } else if live.len() <= 6 { 2.0 } else { 1.0 }
    };
    let mut top: Vec<(usize, f64)> = Vec::new();
    let mut y = G.pad;
    let mut last: i64 = -1;
    for &r in &order {
        let spec = &rows[r];
        let o_ = over(r);
        let pad = match o_ { Some(x) => jn(&x["scopePad"]), None => num_or0(&spec["scopePad"]) };
        let mut crosses = o_.is_some_and(|x| jtruthy(&x["groupStart"]));
        let mut k = if last < 0 { 0 } else { last + 1 };
        while k <= r as i64 {
            if rows.get(k as usize).is_some_and(|x| jtruthy(&x["groupStart"])) && !gone_rows.contains(&(k as usize)) { crosses = true; }
            k += 1;
        }
        let kind = spec["kind"].as_f64();
        let tab = if kind == Some(3.0) || kind == Some(2.0) { 0.0 } else { G.tab };
        let gap = (if last < 0 { 0.0 } else if kind == Some(1.0) && !crosses { G.member_gap } else { G.gap + if crosses { G.group_gap } else { 0.0 } }) + tab + pad;
        y += gap;
        match top.iter_mut().find(|(x, _)| *x == r) { Some(x) => x.1 = y, None => top.push((r, y)) }
        let spec2 = if kind == Some(3.0) { spec.clone() } else { jassign(spec, &[("lines", jv(lines_of(spec)))]) };
        y += row_height(track, &spec2, on);
        last = r as i64;
    }
    (top, js::max(&[y + G.pad, G.folded]))
}

/// `contribute(ctx, out)` — 판마다 `boardOne` → 결과를 새 겉 열쇠 `boards`로(판이 없으면 열쇠도 없음) → 연표가 기본 배치로 돌아왔는지 확인.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let boards = boards_of(ctx);
    let notes = o! { "판" => 0.0, "임시판" => 0.0, "새줄" => 0.0, "사라진줄" => 0.0, "이사" => 0.0, "새칸" => 0.0, "새항목" => 0.0, "가림" => 0.0, "새줄이름" => 0.0, "묶음" => 0.0,
        "뺀판" => js::Arr::default(), "어긋남" => js::Arr::default(), "알림" => js::Arr::default() };
    ctx.notes.set("집합보기", notes.clone());
    if boards.is_empty() { return Ok(()); } // 판이 없으면 겉 열쇠도 없다 — 내보낸 글이 1바이트도 달라지지 않는다
    let add = |k: &str, x: f64| notes.set(k, n(&notes.get(k)) + x);
    let push = |k: &str, line: String| if let V::Arr(l) = notes.get(k) { l.push(line); };

    let tracks = list(&tl.get("tracks"));
    let track_at = Map::new();
    for (i, tr) in tracks.iter().enumerate() { track_at.set(tr.get("id"), i as f64); }
    let base_band = Map::new();
    for (i, p) in out["periods"].as_array().into_iter().flatten().enumerate() { base_band.set(jkey(p.get("uid")), i as f64); }
    let (mut band_at, mut event_at, mut event_band) = (HashMap::new(), HashMap::new(), HashMap::new());
    for p in out["periods"].as_array().into_iter().flatten().filter(|p| !jtruthy(&p["variant"])) { band_at.insert(jpart(p.get("uid")), (jn(&p["track"]), jn(&p["row"]))); }
    for e in out["events"].as_array().into_iter().flatten().filter(|e| !jtruthy(&e["variant"])) {
        event_at.insert(jpart(e.get("uid")), (jn(&e["track"]), jn(&e["row"])));
        event_band.insert(jpart(e.get("uid")), if jtruthy(&e["band"]) { jkey(e.get("band")) } else { s("") });
    }
    let mut cell_at: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, c) in out["cells"].as_array().into_iter().flatten().enumerate() { if !jtruthy(&c["variant"]) { cell_at.entry(cell_key_of(c)).or_default().push(i); } }
    let mut by_track: Vec<(f64, Vec<usize>)> = Vec::new();
    for (i, it) in out["items"].as_array().into_iter().flatten().enumerate() {
        if jtruthy(&it["variant"]) { continue; }
        let k = jn(&it["track"]);
        match by_track.iter_mut().find(|(x, _)| *x == k) { Some(x) => x.1.push(i), None => by_track.push((k, vec![i])) }
    }
    let owner_of = Map::new();
    for tr in &tracks { for p in items(&tr.get("periods")) { owner_of.set(p.get("uid"), tr.get("id")); } }
    // 엔진의 전체 줄 번호: 가져오기는 옛 트랙의 줄(그 트랙의 변형 줄까지)을 트랙 차례로 넣고, 그 뒤에 판 트랙의 줄을 판 차례로 넣는다(legacy.rs)
    let mut base_first = Vec::new();
    let mut total = 0.0;
    for tr in out["tracks"].as_array().into_iter().flatten() { base_first.push(total); total += tr["rows"].as_array().map_or(0, Vec::len) as f64; }
    let mut env = Env {
        track_at, base: tracks.iter().map(|tr| snap_track(&tl, tr)).collect(), next_track: out["tracks"].as_array().map_or(0, Vec::len) as f64, base_band, band_at, event_at, event_band,
        board_rows: Vec::new(), base_first, base_total: total, out_tracks: out["tracks"].as_array().map_or(0, Vec::len) as f64, cell_at, owner_of, by_track,
    };
    let before: Vec<String> = env.base.iter().map(snap_sig).collect();

    let mut result = json!({ "tracks": [], "variants": [], "cells": [], "items": [], "rowLabels": [], "entities": [] });
    for b in &boards {
        let got = match board_one(ctx, b, &env, out) {
            Ok(x) => x,
            Err(err) => { push("뺀판", format!("{}: {}", b.key, err.to_string().split('\n').next().unwrap_or(""))); continue; }
        };
        let Some(got) = got else { push("뺀판", format!("{}: 구성 나라가 연표에 없음", b.key)); continue };
        env.next_track += 1.0;
        env.board_rows.push(arr_len_v(&got.track["rows"]));
        add("새줄", arr_len_v(&got.track["rows"]));
        add("사라진줄", got.gone as f64);
        add("이사", arr_len_v(&got.entry["moves"]));
        add("새칸", got.cells.len() as f64);
        add("새항목", got.items.len() as f64);
        add("가림", arr_len_v(&got.entry["hides"]));
        add("새줄이름", got.labels.len() as f64);
        add("묶음", arr_len_v(&got.entry["groups"]));
        if b.temp { add("임시판", 1.0); } else { add("판", 1.0); }
        if let Some(w) = got.warn.first() { push("어긋남", format!("{}: {}곳 — {w}", b.key, got.warn.len())); }
        if let Some(w) = got.note.first() { push("알림", format!("{}: {}곳 — {w}", b.key, got.note.len())); }
        arr_mut(&mut result, "tracks").push(got.track);
        arr_mut(&mut result, "variants").push(got.entry);
        arr_mut(&mut result, "cells").extend(got.cells);
        arr_mut(&mut result, "items").extend(got.items);
        arr_mut(&mut result, "rowLabels").extend(got.labels);
        arr_mut(&mut result, "entities").push(got.entity);
    }
    // 다 돌린 뒤 연표가 기본 상태로 돌아왔는가(뒤 모듈 · 다음 내보내기가 같은 배치를 읽게)
    let after: Vec<String> = list(&tl.get("tracks")).iter().map(|tr| snap_sig(&snap_track(&tl, tr))).collect();
    if after.join("\n") != before.join("\n") { return Err("집합 보기를 다 돌린 뒤 연표가 기본 배치로 돌아오지 않았습니다".into()); }
    if result["variants"].as_array().is_some_and(|l| !l.is_empty()) { out["boards"] = result; }
    Ok(())
}

/// JSON 배열의 길이(없으면 0).
fn arr_len_v(v: &Value) -> f64 { v.as_array().map_or(0, Vec::len) as f64 }

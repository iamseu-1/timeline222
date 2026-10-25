//! 내보내기 모듈 `variants` — `prototype/scripts/export/variants.mjs`(1 ~ 557줄 · SHA-256 앞 12자 `628bbd44a3fa`)를 줄 그대로 옮긴다(한 벌 P3 과제 14 · 갈래 E).
//! 변형(소속 펼치기 `host:` · 단체 펼치기 `groups:` · 대범위 모아 보기 `scope:` · 선반 `shelf:`)마다 **그것 하나만 켠** 상태로 줄 배정(`_layoutTrack` — 그 변형의 트랙만 · [`layout_some`])을 다시 돌리고,
//! REPLAY 열두 모듈(`tracks` `bands` `strips` `events` `hangs` `figures` `rails` `links` `scopes` `minibars` `labels` `power`)의 `contribute`를 새 out · 새 shared에 다시 불러
//! 기본 상태와 견준 차이(새 줄 · 쌓는 차례 · 이사 · 새로 그릴 것 · 묶음)를 `out.variants`로 싣는다. 변형마다 그 트랙을 기본 상태로 되돌려 다시 배치한다.
//! 부분 셈(`Scope::Tracks(S)`)에서도 변형은 모두 셈한다(과제 16b — 제 트랙이 S 밖인 변형도 온 판 값에 든다: 새 띠는 `spheres`의 띠 수 · 띠 순번에, 새 사건은
//! 렌즈 항목 기록의 사건 목록에, 새 칸은 렌즈 변형의 가림에 — `lay::export` 머리글).
//!
//! - REPLAY의 `sub` 문맥(`Object.assign({}, ctx, { shared: {}, notes: {} })`)은 [`Sub`] — `ctx.shared` · `ctx.notes`(boards는 `ctx.model`도)를 잠시 바꿔 끼우고
//!   **Drop에서 늘 되돌린다**(오류 길에서도). 바꿔 끼웠던 값은 풀지(`js::release`) 않고 버리기만 한다(모델 객체를 가리킬 수 있어 — 풀면 진짜 모델의 칸까지 비움).
//! - 띠 번호(새 작업본 main의 고침 — 원본 132 ~ 162줄): REPLAY가 hangs 앞에서 `bandOf`를 **결과의 번호**(기본 띠는 기본 순번 · 새 띠는 `nextAt`부터)로 바꿔 끼우고,
//!   power 앞에서 다시 돌린 번호로 되돌린다.
//! - `restack` 자체 점검(계획 정한 것 #10)은 JS 그대로 **경고로만** — 그 글이 `entry.notes`로 실리므로 글까지 같게 옮겼다(오류로 만들지 않음).
//! - 선반(`shelf:<그릇 uid>` · 갈래 6 — 리메이크 4단계 선반 갈래 걸음 3 · 감독 결정 2026-10-25 '선반 = 엔진 변형 길'): scope 변형을 셈한 배치에서 그 그릇이 차지한
//!   구성원이 [`crate::lay::track::SHELF_KEEP`]을 넘으면([`shelf_split`]) 이 모듈 목록 끝에 붙여 이 모듈의 변형 뒤에 셈한다(렌즈 변형 kind 4는 뒤의 lens 모듈이
//!   붙이므로 렌즈가 있는 자료에서는 선반 수만큼 번호가 밀린다). 그 그릇만 켜고 `shelvedScopes = {uid}`로 다시 배치 —
//!   숨는 띠는 이사 −1(snapshot의 `_hidden`), 그 띠의 사건도 이사 −1(배치기가 줄 null로 둔 것 — 공통 줄을 새로 만들지 않음 · [`crate::lay::track`] 3),
//!   바탕 문화의 조각은 승계국을 따라 새 줄 또는 −1로 이사(snapshot의 `under_row` — 선반에만), 변형에 없는 기본 줄은 빠지는 줄(after −2 · ord −1 · new 0 —
//!   차례 매김 · restack에서 뺌), 다시 셈에 짝이 없는 기본 항목(느슨한 이름을 수로 셈)은 가림(kind 4). 다른 갈래의 출력은 예전과 바이트 같다.
//! - [`G`] · [`row_height`] · [`track_values_of`] · [`Sub`] · JSON 값의 JS 뜻 도움(`jstr` · `jpart` · `jstrict` · `jsame` · `jassign`)은 boards · lens가 가져다 쓴다.
use super::kit::jtruthy;
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_len, arr_mut, color, ji, jn, jsv, jv};
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{eq, is, list, n, ob, or, s, t, take_fault, tv};
use crate::lay::rows::{items, HANG_PITCH};
use crate::lay::scope::scope_pad;
use crate::lay::track::{layout_some, shelf_split};
use crate::lay::Contribute;
use serde_json::{json, Value};
use std::collections::HashMap;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 변형 상태에서 다시 돌릴 모듈 — 줄 · 띠 · 그릴 것을 만드는 것만(날짜 칸과 항목 기록은 보기 상태와 무관하다).
/// `minibars`가 든 까닭: 가는 막대의 '접힌 민족 줄용 단'(구역 45의 `b`)은 묶음마다 셈하는데 대범위를 켜면 묶음이 달라진다.
/// 'power': 소속을 펼쳐야 그려지는 띠의 단체 칸 · 겹 탭도 변형 판으로 싣는다(단체 자료가 없으면 빈손).
pub const REPLAY: [(&str, Contribute); 12] = [
    ("tracks", super::tracks::contribute), ("bands", super::bands::contribute), ("strips", super::strips::contribute), ("events", super::events::contribute),
    ("hangs", super::hangs::contribute), ("figures", super::figures::contribute), ("rails", super::rails::contribute), ("links", super::links::contribute),
    ("scopes", super::scopes::contribute), ("minibars", super::minibars::contribute), ("labels", super::labels::contribute), ("power", super::power::contribute),
];

/// `G` — 계약 3절의 상수(variants.mjs의 G — tracks.mjs · js/timeline.js와 같은 값 · `G.hang`은 `HANG.pitch`). boards.mjs(집합 보기)도 같은 값 · 같은 식으로 자체 점검한다.
/// 과제 Y: 줄 배정의 [`crate::lay::rows::G0`] · [`HANG_PITCH`] 하나를 다시 내보낸다(처음 옮긴 판은 이 파일의 `Gv` 표 — 값이 같았다).
pub use crate::lay::rows::G0 as G;

/// `VARIANT_KIND` — 1 소속 펼치기 · 2 대범위 모아 보기 · 5 단체 펼치기 · 6 선반(리메이크 4단계 — 그 그릇의 scope 변형을 대신함)(3 집합 보기 · 4 렌즈는 다른 모듈).
fn variant_kind(kind: &str) -> f64 { match kind { "host" => 1.0, "scope" => 2.0, "shelf" => 6.0, _ => 5.0 } }

// ── JSON 값의 JS 뜻(out은 serde_json::Value) ──

/// `String(x)` — 템플릿 글의 `${x}`(없는 칸은 'undefined').
pub fn jstr(v: Option<&Value>) -> String {
    match v {
        None => "undefined".into(),
        Some(Value::Null) => "null".into(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(Value::Number(x)) => js::num_str(x.as_f64().unwrap_or(f64::NAN)),
        Some(Value::String(t)) => t.clone(),
        Some(Value::Array(l)) => l.iter().map(|x| jpart(Some(x))).collect::<Vec<_>>().join(","),
        Some(Value::Object(_)) => "[object Object]".into(),
    }
}
/// `Array.prototype.join`의 한 칸 — null · undefined는 빈 글, 나머지는 `String(x)`.
pub fn jpart(v: Option<&Value>) -> String { match v { None | Some(Value::Null) => String::new(), other => jstr(other) } }
/// `[o.a, o.b, …].join(sep)`(칸은 객체의 열쇠).
pub fn jjoin(o: &Value, keys: &[&str], sep: &str) -> String { keys.iter().map(|k| jpart(o.get(*k))).collect::<Vec<_>>().join(sep) }
/// `a === b`(JSON 값 — 없는 칸은 undefined · 배열 · 객체는 늘 다름).
pub fn jstrict(a: Option<&Value>, b: Option<&Value>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(Value::Null), Some(Value::Null)) => true,
        (Some(Value::Bool(x)), Some(Value::Bool(y))) => x == y,
        (Some(Value::Number(x)), Some(Value::Number(y))) => x.as_f64() == y.as_f64(),
        (Some(Value::String(x)), Some(Value::String(y))) => x == y,
        _ => false,
    }
}
/// `JSON.stringify(a) === JSON.stringify(b)` — 같은 코드가 같은 열쇠 차례로 지은 값끼리라 구조로 견준다(수는 값으로 · undefined끼리는 같음).
pub fn jsame(a: Option<&Value>, b: Option<&Value>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(Value::Number(x)), Some(Value::Number(y))) => x.as_f64() == y.as_f64(),
        (Some(Value::Array(x)), Some(Value::Array(y))) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| jsame(Some(p), Some(q))),
        (Some(Value::Object(x)), Some(Value::Object(y))) => x.len() == y.len() && x.iter().all(|(k, p)| jsame(Some(p), y.get(k))),
        (Some(x), Some(y)) => x == y,
        _ => false,
    }
}
/// `Object.assign({}, x, { …덮을 칸 })`(JSON 객체).
pub fn jassign(x: &Value, over: &[(&str, Value)]) -> Value {
    let mut o = x.as_object().cloned().unwrap_or_default();
    for (k, v) in over { o.insert((*k).to_string(), v.clone()); }
    Value::Object(o)
}
/// JSON 값 → JS 값(Map 열쇠 · 견줌에 — 없는 칸은 undefined).
pub fn jkey(v: Option<&Value>) -> V { match v { None => V::Undef, Some(x) => js::from_json(x) } }
/// `x || 0`(JSON 값의 수).
pub fn num_or0(v: &Value) -> f64 { if jtruthy(v) { jn(v) } else { 0.0 } }

// ── REPLAY의 sub 문맥 ──

/// REPLAY의 `sub`(`Object.assign({}, ctx, { shared: {}, notes: {} })` — boards는 `model`도 사건을 거른 얕은 사본으로): 만들 때 ctx의 shared · notes(· model)를
/// 새 것으로 바꿔 끼우고, [`Sub::finish`] 또는 **Drop**(오류로 일찍 돌아가는 길)에서 되돌린다. 바꿔 끼웠던 값은 풀지 않고 버리기만 한다.
pub struct Sub<'a> { ctx: &'a mut Ctx, shared: Option<Obj>, notes: Option<Obj>, model: Option<V> }
impl<'a> Sub<'a> {
    /// `sub`를 연다 — `model`이 있으면 그 값(얕은 사본)으로 바꿔 끼운다.
    pub fn new(ctx: &'a mut Ctx, model: Option<V>) -> Sub<'a> {
        let shared = std::mem::replace(&mut ctx.shared, Obj::new());
        let notes = std::mem::replace(&mut ctx.notes, Obj::new());
        let model = model.map(|m| std::mem::replace(&mut ctx.model, m));
        Sub { ctx, shared: Some(shared), notes: Some(notes), model }
    }
    /// sub 문맥의 ctx.
    pub fn ctx(&mut self) -> &mut Ctx { &mut *self.ctx }
    /// 되돌리고 sub의 notes(`{ out, notes: sub.notes }`의 notes)를 돌려준다.
    pub fn finish(mut self) -> Obj { self.restore().unwrap_or_default() }
    fn restore(&mut self) -> Option<Obj> {
        let shared = self.shared.take()?;
        let _sub_shared = std::mem::replace(&mut self.ctx.shared, shared);
        let notes = self.notes.take().map(|o| std::mem::replace(&mut self.ctx.notes, o));
        if let Some(m) = self.model.take() { let _copy = std::mem::replace(&mut self.ctx.model, m); }
        notes
    }
}
impl Drop for Sub<'_> {
    fn drop(&mut self) { let _ = self.restore(); }
}

// ── 계약 3절의 쌓기(자체 점검) ──

/// `rowHeight(track, spec, on)` — 줄 하나의 높이(계약 3절의 '띠 안' — tracks.mjs의 stackBand와 같은 식). `on`은 보이는 줄들로 다시 셈한 트랙 값 `(railLevels, organ)`.
pub fn row_height(track: &Value, spec: &Value, on: (f64, bool)) -> f64 {
    if spec["kind"].as_f64() == Some(3.0) { return G.folded_group; }
    let nz = |x: f64| x != 0.0 && !x.is_nan();
    let mut y = G.inset;
    if jtruthy(&track["dynasty"]) { y += G.dynasty + G.slot_gap; }
    y += num_or0(&spec["phase"]) * (G.phase + G.phase_gap);
    if jtruthy(&spec["rank"]) { y += G.rank + G.rank_gap; }
    // 단체 단(집권 · 실권 — tracks.mjs의 packRowValues 비트 7 · 8): 그 줄에 있으면 20 + 3씩
    if (ji(&spec["figWide"]) >> 7) & 1 != 0 { y += G.power + G.power_gap; }
    if (ji(&spec["figWide"]) >> 8) & 1 != 0 { y += G.power + G.power_gap; }
    if jtruthy(&track["leader"]) { y += G.leader + G.slot_gap; }
    if jtruthy(&track["cabinet"]) { y += G.cabinet + G.slot_gap; }
    y += num_or0(&spec["lines"]) * G.line;
    y += (if nz(on.0) { on.0 } else { 2.0 }) * G.rail_pitch;
    let fig_top = y + G.slot_gap;
    let fig = jn(&spec["fig"]);
    let fig_h = if jtruthy(&spec["fig"]) { fig * G.figure + (fig - 1.0) * G.fig_gap } else { 0.0 };
    let dep_top = if nz(fig_h) { fig_top + fig_h + G.slot_gap } else { y + G.slot_gap };
    // dep는 저장된 옛 높이(n*13-1)다. 옛 저장소와 같은 열을 유지하고 화면 높이만 환산한다.
    let dep = if jtruthy(&spec["dep"]) { js::round((jn(&spec["dep"]) + 1.0) / 13.0) * (G.dep + G.slot_gap) - G.slot_gap } else { 0.0 };
    let organ_top = dep_top + if nz(dep) { dep + G.slot_gap } else { 0.0 };
    let row_h = (if on.1 { organ_top + G.organ } else if nz(dep) { dep_top + dep } else if nz(fig_h) { fig_top + fig_h } else { y }) + G.inset;
    // 덧붙는 높이: 매달린 속국 이름표 줄(figWide 비트 9~13) × 13 + 나머지 구역 탭 줄 × 23 + 3
    let hl = f64::from((js::to_i32(num_or0(&spec["figWide"])) >> 9) & 31);
    let zl = js::max(&[0.0, num_or0(&spec["zones"]) - hl]);
    let cut = (if nz(hl + zl) { hl * HANG_PITCH + zl * (G.zone_tab + G.zone_gap) + 3.0 } else { 0.0 }) + if jtruthy(&spec["hem"]) { G.hem } else { 0.0 };
    row_h + cut
}

/// `trackValuesOf(track, rows, live)` — 줄 단위 트랙 값(계약 3절 끝)을 보이는 줄들의 최댓값으로 → `(railLevels, organ)`(화면 쪽 `_syncTrackValues`와 같은 길).
pub fn track_values_of(track: &Value, rows: &[Value], live: &[usize]) -> (f64, bool) {
    let (mut rail_levels, mut organ, mut known) = (2.0, false, false);
    for &r in live {
        let packed = rows.get(r).map_or(0, |x| ji(&x["figWide"]));
        let rail = ((packed >> 3) & 7) as f64 - 1.0;
        if !(rail >= 0.0) || rows[r]["kind"].as_f64() == Some(3.0) { continue; }
        known = true;
        if rail > rail_levels { rail_levels = rail; }
        if (packed & 64) != 0 { organ = true; }
    }
    if known { (rail_levels, organ) } else { (if jtruthy(&track["railLevels"]) { jn(&track["railLevels"]) } else { 2.0 }, jtruthy(&track["organ"])) }
}

// ── 찍어 두기 · 다시 배치 ──

/// 트랙 하나의 지금 배치(`snapshot`의 한 칸).
struct Snap {
    rows: usize, height: V, keys: Vec<String>, row_top: Vec<V>, scope_pad: Vec<f64>, group_start: Vec<f64>,
    groups: Vec<Obj>, band_row: Vec<(V, V)>, event_row: Vec<(String, V)>, under_row: Vec<(V, V)>,
}
/// `rowKeyOf(tr, r)` — 줄의 '내용' 열쇠(그 줄에 놓인 띠의 uid를 이은 글 — 빈 줄은 공통 줄뿐).
pub fn row_key_of(tr: &V, r: f64) -> String {
    let joined = items(&tr.get("rowPeriods").get(&r)).iter().map(|p| { let u = p.get("uid"); if u.is_nullish() { String::new() } else { t(&u) } }).collect::<Vec<_>>().join("+");
    if !joined.is_empty() { joined } else if js::strict_eq(&V::Num(r), &tr.get("commonRow")) { "#공통".into() } else { format!("#빈{}", js::num_str(r)) }
}
/// `eventKeyOf(e)` — rails.mjs의 eventUid와 같은 식(공동 사건의 다른 자리는 `#n`).
fn event_key_of(e: &V) -> String { format!("{}{}", t(&e.get("uid")), if tv(&e.get("_pi")) { format!("#{}", t(&e.get("_pi"))) } else { String::new() }) }
/// `Array.from({ length: x }, …)`의 길이.
pub fn len_of(x: &V) -> usize { let k = n(x); if k.is_finite() && k > 0.0 { k as usize } else { 0 } }
/// `snapshot(tl)` — 지금 연표의 배치 상태(줄의 자리 · 묶음 · 띠와 사건의 줄).
fn snapshot(tl: &V) -> Vec<Snap> {
    list(&tl.get("tracks")).iter().map(|tr| {
        let rows = len_of(&tr.get("rows"));
        let groups = items(&tr.get("groups"));
        Snap {
            rows, height: tr.get("height"),
            keys: (0..rows).map(|r| row_key_of(tr, r as f64)).collect(),
            row_top: list(&tr.get("rowTop")),
            scope_pad: (0..rows).map(|r| js::round(scope_pad(tl, tr, r as f64, r as f64 - 1.0))).collect(),
            group_start: (0..rows).map(|r| if groups.iter().any(|g| js::strict_eq(&g.get("first"), &V::Num(r as f64))) { 1.0 } else { 0.0 }).collect(),
            groups: groups.iter().map(|g| o! {
                "key" => g.get("key"), "name" => or(g.get("name"), s("")), "color" => g.get("color"), "depth" => g.get("depth"), "first" => g.get("first"), "count" => g.get("count"),
                "scope" => or(g.get("scope"), V::Null), "culture" => g.bool("culture"),
            }).collect(),
            band_row: map_of(items(&tr.get("periods")).iter().filter(|p| !p.bool("_overlay") && !p.bool("_under"))
                .map(|p| (p.get("uid"), if p.bool("_hidden") { V::Num(-1.0) } else { p.get("_row") })), |a: &V, b: &V| js::strict_eq(a, b)),
            // 사건의 줄 null = 선반 변형이 숨긴 띠의 사건(지금 연표 `_layoutTrack` 3) → −1(숨음)
            event_row: map_of(items(&tr.get("events")).iter().map(|e| {
                let r = e.get("_row");
                (event_key_of(e), if r.is_null() { V::Num(-1.0) } else if r.is_nullish() || n(&r) < 0.0 { tr.get("commonRow") } else { r })
            }), |a: &String, b: &String| a == b),
            // 바탕 문화의 조각(bands.mjs와 같은 셈 — 첫 줄은 띠 uid · 둘째 줄부터 uid#u<줄>) → 줄. 선반 변형의 이사에만 쓴다
            under_row: map_of(items(&tr.get("periods")).iter().filter(|p| p.bool("_under") && !p.bool("_overlay") && !p.bool("_hidden"))
                .flat_map(|p| items(&p.get("_underRows")).into_iter().enumerate()
                    .map(|(k, r)| (if k == 0 { p.get("uid") } else { V::from(format!("{}#u{}", t(&p.get("uid")), t(&r))) }, r)).collect::<Vec<_>>()),
                |a: &V, b: &V| js::strict_eq(a, b)),
        }
    }).collect()
}

/// `new Map(pairs)`의 차례 — 같은 열쇠가 다시 오면 **첫 자리에 뒤 값 하나**(JS Map의 set). 열쇠 같음은 `same`(uid 글이라 SameValueZero = 같은 글).
fn map_of<K, I: Iterator<Item = (K, V)>>(pairs: I, same: impl Fn(&K, &K) -> bool) -> Vec<(K, V)> {
    let mut out: Vec<(K, V)> = Vec::new();
    for (k, x) in pairs {
        match out.iter_mut().find(|(y, _)| same(y, &k)) { Some(slot) => slot.1 = x, None => out.push((k, x)) }
    }
    out
}

/// `relayout(tl, variant)` — 변형 하나(없으면 기본 상태)를 켠 상태로 줄 배정을 다시 돌린다. JS는 모든 트랙을 다시 배치하지만 변형이 닿는 것은
/// 제 트랙(`track` — 펼친 상위 · 접혀 든 단체 · 켠 그릇이 모두 그 트랙의 것이고 줄 배정은 트랙마다 제 정권만 읽는다 — [`layout_some`])뿐이라 그 트랙만
/// 다시 배치한다(과제 16b — 같은 답 · `tests/lay_out.rs`가 정답지로 지킴). 다른 트랙은 기본 배치 그대로다.
fn relayout(ctx: &mut Ctx, variant: Option<(&str, &V)>, track: &V) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let tlo = ob(&tl);
    let one = |want: &str| { let st = Set::new(); if let Some((k, uid)) = variant { if k == want { st.add(uid.clone()); } } st };
    tlo.set("expandedHosts", one("host"));
    tlo.set("expandedGroups", one("groups"));
    // 그 그릇 하나만 켬 — 나머지는 자료의 default와 상관없이 풂(기본 배치와 같게). 선반도 그 그릇을 켠 배치다
    let on = Obj::new();
    for sc in items(&tl.get("scopes")) {
        let lit = variant.is_some_and(|(k, uid)| (k == "scope" || k == "shelf") && js::strict_eq(uid, &sc.get("uid")));
        on.set(&t(&sc.get("uid")), lit);
    }
    tlo.set("scopesOn", on);
    // 선반: 그 그릇만 선반 상태(줄 배정이 상위 SHELF_KEEP 밖 구성원을 숨김) — 그 밖(기본 되돌림 포함)은 빈 집합
    tlo.set("shelvedScopes", one("shelf"));
    layout_some(ctx, std::slice::from_ref(track))
}

/// `replay(ctx, mods, baseUids, baseBand, nextAt)` — REPLAY 모듈을 새 그릇에 다시 돌린다(모듈끼리 나눠 쓰는 값도 새로 — 기본 상태의 것을 덮지 않는다).
/// 띠 번호는 결과의 번호로: hangs 앞에서 `bandOf`를 바꿔 끼우고(기본 띠는 기본 순번 · 새 띠는 `next_at`부터 · 조각은 첫 조각의 번호) power 앞에서 되돌린다.
fn replay(ctx: &mut Ctx, base_uids: &Set, base_band: &Map, next_at: f64) -> crate::Result<Value> {
    let mut out = json!({ "categories": [], "tracks": [], "epochs": [], "axis": [], "periods": [], "cells": [], "events": [], "items": [], "entities": [], "rowLabels": [] });
    let name = ctx.raws.first().map(|r| r.get("name")).unwrap_or(V::Undef);
    if !name.is_undef() { out["name"] = jsv(&name); }
    let mut sub = Sub::new(ctx, None);
    let mut replayed = V::Undef;
    for (mod_name, contribute) in REPLAY {
        let c = sub.ctx();
        if mod_name == "hangs" {
            replayed = c.shared.get("bandOf");
            let fin = Map::new();
            let mut next = next_at;
            for p in out["periods"].as_array().into_iter().flatten() {
                let uid = jkey(p.get("uid"));
                if base_uids.has(&uid) {
                    if !fin.has(&uid) { fin.set(uid.clone(), base_band.get(&uid)); }
                    continue;
                }
                if !fin.has(&uid) { fin.set(uid, next); } // 새 띠의 조각은 모두 차례대로 붙는다 — 번호는 첫 조각의 것
                next += 1.0;
            }
            c.shared.set("bandOf", fin);
        }
        if mod_name == "power" && tv(&replayed) { c.shared.set("bandOf", replayed.clone()); }
        // 그 모듈이 오류로 돌아가면 남긴 잘못도 거둔다(뒤의 줄 배정 · 되돌림이 묵은 잘못을 제 글로 가리지 않게 — 16b 넘겨받은 틀 손질)
        if let Err(e) = contribute(c, &mut out) { let _ = take_fault(); return Err(e); }
        // JS라면 그 모듈에서 던졌을 곳(객체가 아닌 값에 칸 쓰기 — model::util::fault): 다음 줄 배정까지 미루지 않고 그 모듈의 오류로
        if let Some(msg) = take_fault() { return Err(format!("변형 REPLAY의 {mod_name} 모듈 — {msg}(JS라면 TypeError)").into()); }
    }
    sub.finish();
    Ok(out)
}

/// 변형 하나(`{ key, kind, uid, track, name }` — 수 `members`는 싣지 않으므로 뺌).
#[derive(Clone)]
struct Variant { key: String, kind: &'static str, uid: V, track: f64, name: V }

/// `contribute(ctx, out)` — 변형마다 다시 배치 → REPLAY → 기본 상태와의 차이를 `out.variants`로 → 기본 상태로 되돌림.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let model = ctx.model.clone();
    let track_index = ctx.track_index.clone();

    // 변형 목록 — 소속 펼치기는 단추가 생기는 상위 정권마다(명세 5-2의 셈 그대로), 단체 펼치기는 접혀 든 단체의 띠가 있는 나라마다, 대범위는 자료에 적힌 것마다.
    let mut variants: Vec<Variant> = Vec::new();
    let tracks = list(&tl.get("tracks"));
    let shown = |p: &V| !(p.bool("_hidden") || p.bool("_overlay") || p.bool("_under") || p.get("_row").is_nullish());
    for (at, tr) in tracks.iter().enumerate() {
        for p in items(&tr.get("periods")) {
            if !shown(&p) { continue; }
            let k = items(&p.get("members")).iter().filter(|m| {
                eq(&m.get("track"), &tr.get("id")) && m.bool("singleHost") && !m.bool("groupUid") && !is(&m.get("polityKind"), "overlay") && !(m.bool("_scope") && !eq(&m.get("_host"), &p))
            }).count();
            if k > 0 { variants.push(Variant { key: format!("host:{}", t(&p.get("uid"))), kind: "host", uid: p.get("uid"), track: at as f64, name: or(p.get("name"), s("")) }); }
        }
    }
    for (at, tr) in tracks.iter().enumerate() {
        for p in items(&tr.get("periods")) {
            if !shown(&p) { continue; }
            let groups = Set::new();
            for m in items(&p.get("members")) { if eq(&m.get("track"), &tr.get("id")) && m.bool("singleHost") && m.bool("groupUid") { groups.add(m.get("groupUid")); } }
            if !groups.is_empty() { variants.push(Variant { key: format!("groups:{}", t(&p.get("uid"))), kind: "groups", uid: p.get("uid"), track: at as f64, name: or(p.get("name"), s("")) }); }
        }
    }
    for sc in items(&model.get("scopes")) {
        let at = if track_index.has(&sc.get("track")) { n(&track_index.get(&sc.get("track"))) } else { -1.0 };
        if at < 0.0 { continue; }
        variants.push(Variant { key: format!("scope:{}", t(&sc.get("uid"))), kind: "scope", uid: sc.get("uid"), track: at, name: or(sc.get("name"), s("")) });
    }

    let base = snapshot(&tl);
    // 기본 상태에 있던 묶음의 이름 — 그 변형에서만 생기는 묶음(대범위 가지)을 가린다
    let base_group_keys: Vec<Set> = base.iter().map(|b| { let st = Set::new(); for g in &b.groups { st.add(g.get("key")); } st }).collect();
    let base_rows: Vec<f64> = out["tracks"].as_array().map(|l| l.iter().map(|x| arr_len(x, "rows") as f64).collect()).unwrap_or_default();
    let base_band_uids = Set::new();
    for p in out["periods"].as_array().into_iter().flatten() { base_band_uids.add(jkey(p.get("uid"))); }
    // 기본 띠의 순번(bands.mjs가 채운 것) — 변형의 띠 번호를 이 번호 공간으로 맞춘다(replay)
    let base_band = ctx.shared.get("bandOf");
    if !tv(&base_band) { return Err("변형: 띠 모듈(bands)이 먼저 돌아야 합니다".into()); }
    let Some(base_band) = base_band.as_map().cloned() else { return Err("변형: shared.bandOf가 Map이 아닙니다(JS라면 TypeError)".into()) };
    let base_event_uids = Set::new();
    for e in out["events"].as_array().into_iter().flatten() { base_event_uids.add(jkey(e.get("uid"))); }
    // 느슨한 이름 → 기본 항목의 자리(여럿이면 가리지 않고 새 항목으로 본다) — 칸 사이는 U+0001
    let item_key_of = |it: &Value| jjoin(it, &["section", "ref", "name", "start", "end", "text2"], "\u{1}");
    let item_same_of = |it: &Value| jjoin(it, &["a", "b", "c", "d"], "\u{1}");
    let cell_key_of = |c: &Value| jjoin(c, &["period", "kind", "start", "end", "name"], "\u{1}");
    let cell_same_of = |c: &Value| jjoin(c, &["lane", "style", "color"], "\u{1}");
    let mut base_item_at: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, it) in out["items"].as_array().into_iter().flatten().enumerate() { base_item_at.entry(item_key_of(it)).or_default().push(i); }
    let mut base_cell_at: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, c) in out["cells"].as_array().into_iter().flatten().enumerate() { base_cell_at.entry(cell_key_of(c)).or_default().push(i); }
    // 기본 줄 이름의 자리(트랙 · 줄 · 띠) — 민족 딱지가 변형마다 달라지는 곳에 덧글을 얹으려고(같은 열쇠면 뒤의 것)
    let mut base_label_at: HashMap<String, usize> = HashMap::new();
    for (i, l) in out["rowLabels"].as_array().into_iter().flatten().enumerate() {
        if l["kind"].as_f64() == Some(0.0) { base_label_at.insert(format!("{}#{}#{}", jstr(l.get("track")), jstr(l.get("row")), jstr(l.get("period"))), i); }
    }

    out["variants"] = json!([]);
    let notes = o! { "변형" => variants.len() as f64, "선반" => 0.0, "새줄" => 0.0, "쌓는차례" => 0.0, "이사" => 0.0, "새띠" => 0.0, "새사건" => 0.0, "새항목" => 0.0, "변형판" => 0.0,
        "새칸" => 0.0, "새줄이름" => 0.0, "새묶음" => 0.0, "민족딱지" => 0.0, "빠지는줄" => 0.0, "가림" => 0.0, "줄단위트랙값" => js::Arr::default(), "어긋남" => js::Arr::default() };
    let bump = |k: &str| notes.set(k, n(&notes.get(k)) + 1.0);

    // 목록 끝에 선반 변형이 붙으므로(아래 scope 갈래) 순번으로 돈다 — 붙은 것도 돈다
    let mut vi = 0;
    while vi < variants.len() {
        let v = variants[vi].clone();
        vi += 1;
        let shelf = v.kind == "shelf";
        let own = tracks.get(v.track as usize).cloned().ok_or_else(|| format!("변형 {}: 트랙 {}이 없습니다", v.key, js::num_str(v.track)))?;
        relayout(ctx, Some((v.kind, &v.uid)), &own)?;
        let got = snapshot(&tl);
        // 선반 변형의 후보: 이 그릇만 켠 배치에서 그 그릇이 차지한 구성원(줄 배정의 선반 셈과 같은 거르기)이 SHELF_KEEP을 넘으면 목록 끝에 붙인다
        if v.kind == "scope" {
            let members: Vec<V> = items(&own.get("periods")).into_iter().filter(|p| {
                let sc = p.get("_scope");
                tv(&sc) && js::strict_eq(&sc.get("uid"), &v.uid) && !p.bool("_hidden") && !p.bool("_under") && !p.bool("_overlay")
            }).collect();
            if !shelf_split(&members).1.is_empty() {
                variants.push(Variant { key: format!("shelf:{}", t(&v.uid)), kind: "shelf", uid: v.uid.clone(), track: v.track, name: v.name.clone() });
                bump("선반");
            }
        }
        let next_at = arr_len(out, "periods") as f64;
        let vout = replay(ctx, &base_band_uids, &base_band, next_at)?;
        let mut entry = json!({
            "key": v.key, "kind": jv(variant_kind(v.kind)), "track": jv(v.track), "band": if v.kind == "host" || v.kind == "groups" { jsv(&v.uid) } else { json!("") },
            "uid": if v.kind == "scope" || shelf { jsv(&v.uid) } else { json!("") }, "name": jsv(&v.name), "rows": [], "moves": [], "groups": [], "hides": [], "notes": "",
        });
        let mut warn: Vec<String> = Vec::new();

        // ── 줄 맞추기: 변형의 줄 → 기본 줄(내용이 같은 줄). 못 찾으면 새 줄이다 ──
        let row_map: Vec<Map> = tracks.iter().map(|_| Map::new()).collect(); // 변형 줄 번호 → 엔진 줄 번호(트랙 안)
        for (at, tg) in got.iter().enumerate() {
            let b = &base[at];
            let mut by_key: HashMap<&str, usize> = HashMap::new();
            for (r, k) in b.keys.iter().enumerate() { by_key.entry(k.as_str()).or_insert(r); }
            let mut next = arr_len(&out["tracks"][at], "rows") as f64; // 새 줄은 그 트랙의 줄 목록 뒤에(앞선 변형이 더한 줄 뒤에)
            let mut used: Vec<usize> = Vec::new();
            for (r, k) in tg.keys.iter().enumerate() {
                match by_key.get(k.as_str()).copied().filter(|r2| !used.contains(r2)) {
                    Some(r2) => { used.push(r2); row_map[at].set(r as f64, r2 as f64); }
                    None => { row_map[at].set(r as f64, next); next += 1.0; }
                }
            }
        }

        // ── 새 줄 · 쌓는 차례 ──
        for (at, tg) in got.iter().enumerate() {
            let b = &base[at];
            let order: Vec<f64> = (0..tg.rows).map(|r| n(&row_map[at].get(&V::Num(r as f64)))).collect();
            for r in 0..order.len() {
                let row = order[r];
                let fresh = row >= base_rows[at];
                let after = if r == 0 { -1.0 } else { order[r - 1] };
                let base_after = if fresh { None } else if row == 0.0 { Some(-1.0) } else { Some(row - 1.0) };
                let ri = row as usize;
                let pad_changed = !fresh && b.scope_pad.get(ri).copied() != tg.scope_pad.get(r).copied();
                let group_changed = !fresh && b.group_start.get(ri).copied() != tg.group_start.get(r).copied();
                if fresh {
                    // 그 변형에서만 있는 줄: tracks.mjs가 변형 상태로 만든 줄 기록을 그대로 싣는다
                    let record = jassign(&vout["tracks"][at]["rows"][r], &[("variant", json!(v.key))]);
                    let slot = arr_mut(&mut out["tracks"][at], "rows");
                    if slot.len() as f64 != row { return Err(format!("새 줄의 자리가 어긋났습니다: {} 트랙 {at} 줄 {}", v.key, js::num_str(row)).into()); }
                    slot.push(record);
                    bump("새줄");
                } else if !pad_changed && !group_changed {
                    // 값이 그대로인 기본 줄은 차례가 바뀌었을 때만 싣는다 — 생김새가 달라졌으면 알린다(height는 견주지 않음 · figWide는 줄 단위 트랙 값도 함께 봄)
                    let rec = &vout["tracks"][at]["rows"][r];
                    let old = &out["tracks"][at]["rows"][ri];
                    for k in ["bandH", "lines", "kind", "phase", "rank", "fig", "dep", "zones", "hem", "figWide"] {
                        if !jstrict(rec.get(k), old.get(k)) { warn.push(format!("트랙 {at} 줄 {}의 {k}가 {} → {}로 달라졌으나 싣지 않았습니다", js::num_str(row), jstr(old.get(k)), jstr(rec.get(k)))); }
                    }
                    if !jstrict(rec.get("figWide"), old.get("figWide")) {
                        let (o_, n_) = (ji(&old["figWide"]), ji(&rec["figWide"]));
                        let line = format!("{}: 트랙 {at} 줄 {} — 막대 {} → {} · 기관 {} → {}", v.key, js::num_str(row), ((o_ >> 3) & 7) - 1, ((n_ >> 3) & 7) - 1, (o_ & 64) != 0, (n_ & 64) != 0);
                        if let V::Arr(l) = notes.get("줄단위트랙값") { l.push(line); }
                    }
                    if !jsame(rec.get("cats"), old.get("cats")) { warn.push(format!("트랙 {at} 줄 {}의 분류별 글줄이 달라졌으나 싣지 않았습니다", js::num_str(row))); }
                }
                if Some(after) != base_after || pad_changed || group_changed {
                    arr_mut(&mut entry, "rows").push(json!({
                        "track": at, "row": jv(row), "after": jv(after), "ord": 0, "new": if fresh { 1 } else { 0 },
                        "scopePad": jv(js::round(tg.scope_pad.get(r).copied().unwrap_or(f64::NAN))), "groupStart": jv(tg.group_start.get(r).copied().unwrap_or(f64::NAN)),
                    }));
                    if !fresh { bump("쌓는차례"); }
                }
            }
            // 선반: 변형에 없는 기본 줄은 빠지는 줄 — after −2 · ord −1(옮겨 간 판 줄이 없음) · new 0. 그 밖의 갈래는 예전 그대로(싣지 않음)
            if shelf {
                let kept = row_map[at].values();
                for row in 0..b.rows {
                    if kept.iter().any(|x| js::strict_eq(x, &V::Num(row as f64))) { continue; }
                    arr_mut(&mut entry, "rows").push(json!({ "track": at, "row": row, "after": -2, "ord": -1, "new": 0, "scopePad": 0, "groupStart": 0 }));
                    bump("빠지는줄");
                }
            }
            if !js::strict_eq(&tg.height, &b.height) && tg.keys.is_empty() { warn.push(format!("트랙 {at}의 높이만 달라졌습니다")); }
        }
        // 같은 자리에 여럿이면 차례를 매긴다(빠지는 줄은 쌓지 않으므로 세지 않음)
        {
            let mut seen: HashMap<String, f64> = HashMap::new();
            for r in arr_mut(&mut entry, "rows").iter_mut() {
                if r["after"].as_f64() == Some(-2.0) { continue; }
                let key = format!("{}#{}", jstr(r.get("track")), jstr(r.get("after")));
                let ord = seen.get(&key).copied().unwrap_or(0.0);
                r["ord"] = jv(ord);
                seen.insert(key, ord + 1.0);
            }
        }

        // ── 이사: 줄이 옮겨 쌓인 것으로 설명되지 않는 띠 · 사건 ──
        for (at, tg) in got.iter().enumerate() {
            let b = &base[at];
            for (uid, r) in &tg.band_row {
                if !base_band_uids.has(uid) { continue; } // 새 띠는 아래에서 통째로 싣는다
                let was = b.band_row.iter().rev().find(|(k, _)| js::strict_eq(k, uid)).map_or(V::Undef, |(_, x)| x.clone());
                let now = if js::to_num(r) < 0.0 { V::Num(-1.0) } else { row_map[at].get(r) };
                if was.is_undef() || js::strict_eq(&now, &was) { continue; }
                arr_mut(&mut entry, "moves").push(json!({ "kind": 1, "ref": jsv(uid), "row": jsv(&now), "track": at }));
                bump("이사");
            }
            // 선반: 바탕 문화의 기본 조각마다 변형에 같은 조각이 있으면 그 줄로, 없으면 −1로(변형에만 있는 조각은 새 띠로). 그 밖의 갈래는 싣지 않는다(출력 그대로)
            if shelf {
                for (uid, was) in &b.under_row {
                    if !base_band_uids.has(uid) { continue; }
                    let r = tg.under_row.iter().rev().find(|(k, _)| js::strict_eq(k, uid)).map_or(V::Undef, |(_, x)| x.clone());
                    let now = if r.is_nullish() { V::Num(-1.0) } else { row_map[at].get(&r) };
                    if js::strict_eq(&now, was) { continue; }
                    arr_mut(&mut entry, "moves").push(json!({ "kind": 1, "ref": jsv(uid), "row": jsv(&now), "track": at }));
                    bump("이사");
                }
            }
            for (key, r) in &tg.event_row {
                if !base_event_uids.has(&V::from(key.as_str())) { continue; }
                let was = b.event_row.iter().rev().find(|(k, _)| k == key).map_or(V::Undef, |(_, x)| x.clone());
                let now = if js::to_num(r) < 0.0 { V::Num(-1.0) } else { row_map[at].get(r) };
                if was.is_undef() || js::strict_eq(&now, &was) { continue; }
                arr_mut(&mut entry, "moves").push(json!({ "kind": 2, "ref": key, "row": jsv(&now), "track": at }));
                bump("이사");
            }
        }

        // ── 그 변형에서만 생기는 것 ──
        let row_of = |at: &Value, r: &Value| -> crate::Result<f64> {
            let m = at.as_f64().filter(|x| *x >= 0.0 && x.fract() == 0.0).and_then(|x| row_map.get(x as usize));
            let Some(m) = m else { return Err(format!("{}: 트랙 {}의 줄 목록이 없습니다(JS라면 TypeError)", v.key, jstr(Some(at))).into()) };
            let row = m.get(&jkey(Some(r)));
            if row.is_nullish() { return Err(format!("{}: 트랙 {}의 줄 {}을 옮길 곳이 없습니다", v.key, jstr(Some(at)), jstr(Some(r))).into()); }
            Ok(n(&row))
        };
        let fresh_band = Set::new();
        for p in vout["periods"].as_array().into_iter().flatten() {
            let uid = jkey(p.get("uid"));
            if base_band_uids.has(&uid) { continue; }
            let row = row_of(&p["track"], &p["row"])?;
            arr_mut(out, "periods").push(jassign(p, &[("row", jv(row)), ("variant", json!(v.key))]));
            fresh_band.add(uid);
            bump("새띠");
        }
        for c in vout["cells"].as_array().into_iter().flatten() {
            match base_cell_at.get(&cell_key_of(c)) {
                Some(at) if at.len() == 1 => {
                    if cell_same_of(&out["cells"][at[0]]) != cell_same_of(c) {
                        arr_mut(out, "cells").push(jassign(c, &[("variant", json!(v.key))]));
                        arr_mut(&mut entry, "hides").push(json!({ "kind": 3, "at": at[0] }));
                        bump("새칸");
                    }
                    continue;
                }
                Some(_) => continue,
                None => {}
            }
            if !fresh_band.has(&jkey(c.get("period"))) { warn.push(format!("기본에 없던 칸이 기본 띠({})에 붙었습니다: {}", jstr(c.get("period")), jstr(c.get("name")))); continue; }
            arr_mut(out, "cells").push(jassign(c, &[("variant", json!(v.key))]));
            bump("새칸");
        }
        for e in vout["events"].as_array().into_iter().flatten() {
            if base_event_uids.has(&jkey(e.get("uid"))) { continue; }
            let row = row_of(&e["track"], &e["row"])?;
            arr_mut(out, "events").push(jassign(e, &[("row", jv(row)), ("variant", json!(v.key))]));
            bump("새사건");
        }
        for it in vout["items"].as_array().into_iter().flatten() {
            // 두 끝을 따로 옮기면 차례가 뒤집힐 수 있다 — 옮긴 뒤 위 · 아래를 다시 고른다(계약: row ≤ row2)
            let (r1, r2) = (row_of(&it["track"], &it["row"])?, row_of(&it["track"], &it["row2"])?);
            let (row, row2) = (js::min(&[r1, r2]), js::max(&[r1, r2]));
            match base_item_at.get(&item_key_of(it)) {
                Some(at) if at.len() == 1 => {
                    let old = &out["items"][at[0]];
                    if item_same_of(old) == item_same_of(it) && old["row"].as_f64() == Some(row) && old["row2"].as_f64() == Some(row2) { continue; } // 그대로다
                    arr_mut(out, "items").push(jassign(it, &[("row", jv(row)), ("row2", jv(row2)), ("variant", json!(v.key))]));
                    arr_mut(&mut entry, "hides").push(json!({ "kind": 4, "at": at[0] })); // 이 변형에서는 기본 판을 가린다
                    bump("변형판");
                    continue;
                }
                Some(_) => continue, // 느슨한 이름이 여럿이라 어느 것을 가릴지 가릴 수 없다 — 그대로 둔다
                None => {}
            }
            arr_mut(out, "items").push(jassign(it, &[("row", jv(row)), ("row2", jv(row2)), ("variant", json!(v.key))]));
            bump("새항목");
        }
        // 선반: 기본 항목 가운데 변형 다시 셈에 짝이 없는 것은 가린다(kind 4) — 느슨한 이름을 수로 세어 다시 셈에 하나도 없으면 그 이름의 기본 항목을 모두
        // (하나라도 있으면 어느 것이 짝인지 가릴 수 없어 그대로). 자리는 오름차순(JS의 Map 차례로 모은 뒤 정렬 — 차례에 기대지 않음)
        if shelf {
            let mut left: HashMap<String, usize> = HashMap::new();
            for it in vout["items"].as_array().into_iter().flatten() { *left.entry(item_key_of(it)).or_default() += 1; }
            let mut gone: Vec<usize> = Vec::new();
            for (k, at) in &base_item_at {
                if left.get(k).is_some_and(|c| *c > 0) { continue; }
                gone.extend(at.iter().copied());
            }
            gone.sort_unstable();
            for at in gone {
                arr_mut(&mut entry, "hides").push(json!({ "kind": 4, "at": at }));
                bump("가림");
            }
        }
        for l in vout["rowLabels"].as_array().into_iter().flatten() {
            let row = row_of(&l["track"], &l["row"])?;
            let lt_ = l["track"].as_f64().filter(|x| *x >= 0.0 && x.fract() == 0.0).map_or(usize::MAX, |x| x as usize);
            if base_rows.get(lt_).is_some_and(|b| row >= *b) {
                arr_mut(out, "rowLabels").push(jassign(l, &[("row", jv(row)), ("variant", json!(v.key))]));
                bump("새줄이름");
                continue;
            }
            // 그 변형에서만 생기는 묶음(대범위 가지)의 접힘용 후보: 가지의 첫 줄이 기본 줄이면 위의 갈래로 들지 않는다
            if l["kind"].as_f64() == Some(2.0) && jtruthy(&l["group"]) && !base_group_keys.get(lt_).is_some_and(|k| k.has(&jkey(l.get("group")))) {
                arr_mut(out, "rowLabels").push(jassign(l, &[("row", jv(row)), ("variant", json!(v.key))]));
                bump("새줄이름");
                continue;
            }
            // 기본 줄의 민족 딱지가 달라지면 그 줄의 이름 글 안에 chipOn(변형 열쇠 → 딱지 · 없어지면 null)으로 얹는다
            if l["kind"].as_f64() != Some(0.0) { continue; }
            let Some(&old_at) = base_label_at.get(&format!("{}#{}#{}", jstr(l.get("track")), js::num_str(row), jstr(l.get("period")))) else { continue };
            let now = if jtruthy(&l["chip"]) { l["chip"].clone() } else { Value::Null };
            let old = &mut arr_mut(out, "rowLabels")[old_at];
            let was = if jtruthy(&old["chip"]) { old["chip"].clone() } else { Value::Null };
            if jsame(Some(&now), Some(&was)) { continue; }
            if !jtruthy(&old["chipOn"]) { old["chipOn"] = json!({}); }
            if let Some(m) = old["chipOn"].as_object_mut() { m.insert(v.key.clone(), now); }
            bump("민족딱지");
        }

        // ── 왼쪽 칸의 새 묶음(대범위 칸) ──
        for (at, tg) in got.iter().enumerate() {
            let had = &base_group_keys[at];
            for g in &tg.groups {
                if had.has(&g.get("key")) { continue; }
                let mut rows = Vec::new();
                let (first, count) = (n(&g.get("first")), n(&g.get("count")));
                let mut r = first;
                while r < first + count { rows.push(jv(row_of(&json!(at), &jv(r))?)); r += 1.0; }
                let kind = if tv(&g.get("scope")) { 2 } else if g.bool("culture") { 1 } else { 0 };
                arr_mut(&mut entry, "groups").push(json!({
                    "track": at, "key": jsv(&g.get("key")), "depth": jsv(&g.get("depth")), "name": jsv(&g.get("name")), "color": color(&g.get("color"), 0xa4b1b7), "kind": kind, "rows": rows,
                }));
                bump("새묶음");
            }
        }

        // ── 자체 점검: 기본 줄 + 이 변형의 차이로 다시 쌓으면 지금 연표와 같은 자리인가(경고로만 — 계획 정한 것 #10 · 글은 entry.notes로 실림) ──
        let stacked = restack(out, &entry, &base_rows);
        for (at, tg) in got.iter().enumerate() {
            let Some((top, height)) = stacked.get(at) else { continue };
            for r in 0..tg.rows {
                let row = row_map[at].get(&V::Num(r as f64));
                let want = top.iter().find(|(k, _)| js::strict_eq(&V::Num(*k as f64), &row)).map(|(_, y)| *y);
                let have = tg.row_top.get(r).cloned().unwrap_or_default();
                // `Math.abs((want ?? NaN) - have) > 0.001` — NaN이면 경고하지 않는다(JS 그대로)
                if (want.unwrap_or(f64::NAN) - n(&have)).abs() > 0.001 {
                    warn.push(format!("트랙 {at} 줄 {}의 자리: 계약 {} ≠ 연표 {}", t(&row), want.map_or_else(|| "undefined".to_string(), js::num_str), t(&have)));
                }
            }
            if (height - n(&tg.height)).abs() > 0.001 { warn.push(format!("트랙 {at}의 높이: 계약 {} ≠ 연표 {}", js::num_str(*height), t(&tg.height))); }
        }

        if !warn.is_empty() {
            entry["notes"] = json!(warn.iter().take(6).cloned().collect::<Vec<_>>().join(" · "));
            if let V::Arr(l) = notes.get("어긋남") { l.push(format!("{}: {}곳 — {}", v.key, warn.len(), warn[0])); }
        }
        arr_mut(out, "variants").push(entry);
        // 기본 상태로 되돌린다(JS는 다음 변형 · 끝의 relayout이 모든 트랙을 다시 배치 — 바뀐 것은 이 트랙뿐이다). 변형이 없으면 배치를 건드리지 않는다.
        relayout(ctx, None, &own)?;
    }
    ctx.notes.set("변형", notes);
    Ok(())
}

/// `restack(out, entry, base, baseRows)` — 기본 줄 + 한 변형의 차이로 줄을 다시 쌓아 본다(계약 3절의 식 · 화면 쪽 layout.dart와 같은 차례).
/// 돌려주는 값: 트랙마다 (줄 → 위 자리, 높이).
fn restack(out: &Value, entry: &Value, base_rows: &[f64]) -> Vec<(Vec<(usize, f64)>, f64)> {
    let own_all: Vec<&Value> = entry["rows"].as_array().map(|l| l.iter().collect()).unwrap_or_default();
    out["tracks"].as_array().map(Vec::as_slice).unwrap_or(&[]).iter().enumerate().map(|(at, track)| {
        let rows: Vec<Value> = track["rows"].as_array().cloned().unwrap_or_default();
        let own: Vec<&Value> = own_all.iter().copied().filter(|r| r["track"].as_f64() == Some(at as f64)).collect();
        let br = base_rows.get(at).copied().unwrap_or(f64::NAN);
        // 빠지는 줄(선반 — after −2)은 쌓지 않는다 — 트랙 값(track_values_of)도 산 줄로만
        let gone: Vec<f64> = own.iter().filter(|r| r["after"].as_f64() == Some(-2.0)).map(|r| jn(&r["row"])).collect();
        let belongs = |r: usize| !gone.contains(&(r as f64)) && ((r as f64) < br || own.iter().any(|x| x["row"].as_f64() == Some(r as f64) && jtruthy(&x["new"])));
        // afterOf · padOf · startOf(같은 줄이면 뒤의 것) · ord는 own.find(첫 것)
        let last_own = |r: usize| own.iter().rev().find(|x| x["row"].as_f64() == Some(r as f64)).copied();
        let live: Vec<usize> = (0..rows.len()).filter(|r| belongs(*r)).collect();
        let anchor = |r: usize| -> f64 { match last_own(r) { Some(x) => jn(&x["after"]), None => if r == 0 { -1.0 } else { r as f64 - 1.0 } } };
        let mut next: Vec<(f64, Vec<usize>)> = Vec::new();
        for &r in &live {
            let a = anchor(r);
            match next.iter_mut().find(|(k, _)| *k == a) { Some((_, kids)) => kids.push(r), None => next.push((a, vec![r])) }
        }
        let ord_of = |x: usize| own.iter().find(|o| o["row"].as_f64() == Some(x as f64)).map_or(0.0, |o| num_or0(&o["ord"]));
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
        for &r in &live { if !seen.contains(&r) { order.push(r); } } // 닿지 못한 줄(고리)은 뒤에
        let mut top: Vec<(usize, f64)> = Vec::new();
        let on = track_values_of(track, &rows, &live); // 그 변형에서 보이는 줄들로 다시 셈한 트랙 값
        let mut y = G.pad;
        let mut first = true;
        for &r in &order {
            let spec = &rows[r];
            let o_ = last_own(r);
            let pad = match o_ { Some(x) => jn(&x["scopePad"]), None => num_or0(&spec["scopePad"]) };
            let crosses = match o_ { Some(x) => jtruthy(&x["groupStart"]), None => jtruthy(&spec["groupStart"]) };
            let kind = spec["kind"].as_f64();
            let tab = if kind == Some(3.0) || kind == Some(2.0) { 0.0 } else { G.tab };
            let gap = (if first { 0.0 } else if kind == Some(1.0) && !crosses { G.member_gap } else { G.gap + if crosses { G.group_gap } else { 0.0 } }) + tab + pad;
            y += gap;
            match top.iter_mut().find(|(k, _)| *k == r) { Some(x) => x.1 = y, None => top.push((r, y)) }
            y += row_height(track, spec, on);
            first = false;
        }
        (top, js::max(&[y + G.pad, G.folded]))
    }).collect()
}

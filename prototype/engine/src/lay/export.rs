//! 내보내기 틀(한 벌 P3 과제 8-틀) — `prototype/scripts/export/base.mjs`의 `runModules`(226 ~ 265줄 · SHA-256 앞 12자 `13ed7b3eef3e`)를 줄 그대로:
//! 빈 `out` · `packInfo` · 간지 설정 → 모듈을 [`crate::lay::MODULES`] 차례로 `contribute` → 늦은 차례(`contributeLate`) → 공통 점검.
//!
//! 그리고 모듈 **하나만** 따로 돌리는 길([`export_one`] · [`export_late`]) — 갈래 4 ~ 5가 모듈 스물을 동시에 옮기며 제 모듈만 Node와 견주려고:
//! 문맥을 줄 배정(`laid`)까지 짓고, `out`을 Node의 앞자리 (k−1) 출력(`pre-<k−1>.json`)으로, 모듈끼리 나눠 쓰는 값(`ctx.shared`)을 그 덤프(`pre-<k−1>.shared.json`)로
//! 심은 뒤 모듈 k의 `contribute` 하나만 돌린다. 그 결과가 Node의 `pre-<k>`(+ `.shared`)와 같으면 그 모듈은 옮겨진 것이다(정답지 뽑기: `oracle/one.mjs`의 `mods` 이음매).
//! `shared`의 값은 모두 평범한 값(글 → 수의 Map · 글 → Set · 글 → 배열 — 모델 객체 `$ref` 없음 · 계획의 '모듈 사이 의존' 표)이라 Node 덤프에서 그대로 심는다([`shared_seed`]).
//!
//! 모듈 출력 `out`은 `serde_json::Value`(계획 정한 것 #2 — 열쇠 차례는 견주지 않음). 수는 [`jv`]로(정수 꼴이면 정수 — JSON 글이 Node와 같게).
use crate::lay::ctx::{self, Ctx};
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::util::{or, tv};
use crate::lay::{Opts, PackIn, MODULES};
use serde_json::{json, Value};

/// 아직 옮기지 않은 모듈을 부르면 이 오류(조용히 다른 답을 내지 않음).
pub fn unported(name: &str) -> Box<dyn std::error::Error + Send + Sync> { format!("옮기지 않은 모듈: {name}(prototype/scripts/export/{name}.mjs)").into() }

// ── `out` · 값 도움(모듈이 함께 쓴다) ──

/// JS 수 → JSON 값: 정수 꼴이면 정수(`JSON.stringify(5.0)` = `5`), 유한하지 않으면 null(`JSON.stringify(NaN)` = `null`).
pub fn jv(x: f64) -> Value {
    if !x.is_finite() { return Value::Null; }
    if x.fract() == 0.0 && x.abs() < 9.007_199_254_740_992e15 { return Value::from(x as i64); }
    Value::from(x)
}
/// `minute(v)`(base.mjs — 해가 수가 아니면 null) → JSON 값(null 또는 정수 분).
pub fn minute_v(v: &V) -> Value {
    match v { V::Num(x) => js::minute(*x).map_or(Value::Null, Value::from), _ => Value::Null }
}
/// `minute(v)`(base.mjs)의 수(null이면 NaN — `Math.max(null, …)`처럼 셈에 넣을 때는 [`minute_num`]).
pub fn minute_or_nan(v: &V) -> f64 {
    match v { V::Num(x) => js::minute(*x).map_or(f64::NAN, |m| m as f64), _ => f64::NAN }
}
/// `minute(v)`를 JS가 산술에 넣은 값 — null은 0(`Math.max(null, x)` = `Math.max(0, x)`).
pub fn minute_num(v: &V) -> f64 {
    match v { V::Num(x) => js::minute(*x).map_or(0.0, |m| m as f64), _ => 0.0 }
}
/// `color(text, fallback)`(base.mjs 56줄) — `/^#[0-9a-f]{6}$/i`면 16진 수, 아니면 fallback.
pub fn color(text: &V, fallback: u32) -> u32 {
    let V::Str(s) = text else { return fallback };
    let Some(t) = s.exact() else { return fallback };
    let b = t.as_bytes();
    if b.len() == 7 && b[0] == b'#' && b[1..].iter().all(u8::is_ascii_hexdigit) { u32::from_str_radix(&t[1..], 16).unwrap_or(fallback) } else { fallback }
}
/// JS 값의 글(`x || ''`) — 글이면 그대로, 거짓이면 빈 글, 그 밖은 `String(x)`.
pub fn text_or_empty(v: &V) -> String { if tv(v) { js::to_str(v).as_str().into_owned() } else { String::new() } }
/// JS 값 → JSON 값(`JSON.parse(JSON.stringify(v))` — 모듈이 모델의 값을 그대로 실을 때).
pub fn jsv(v: &V) -> Value { js::to_json(v) }
/// `out[key]`의 배열(없으면 빈 배열을 만든다 — `out.rowLabels = []`처럼).
pub fn arr_mut<'a>(out: &'a mut Value, key: &str) -> &'a mut Vec<Value> {
    let o = out.as_object_mut().expect("out은 객체");
    if !o.get(key).is_some_and(Value::is_array) { o.insert(key.to_string(), Value::Array(Vec::new())); }
    o.get_mut(key).and_then(Value::as_array_mut).expect("배열")
}
/// `out[key] || []`의 길이.
pub fn arr_len(out: &Value, key: &str) -> usize { out[key].as_array().map_or(0, Vec::len) }
/// JSON 값의 수(JS `Number(x)` — 없으면 NaN · null은 0 · 참거짓은 1 · 0).
pub fn jn(v: &Value) -> f64 {
    match v { Value::Number(x) => x.as_f64().unwrap_or(f64::NAN), Value::Null => 0.0, Value::Bool(b) => f64::from(*b), Value::String(s) => js::to_num(&V::from(s.as_str())), _ => f64::NAN }
}
/// JSON 값의 정수(JS `| 0`꼴의 비트 셈에 — 수가 아니면 0).
pub fn ji(v: &Value) -> i64 { let x = jn(v); if x.is_finite() { js::to_i32(x) as i64 } else { 0 } }
/// JSON 값의 글(`x || ''`).
pub fn js_text(v: &Value) -> String {
    match v { Value::String(s) => s.clone(), Value::Null => String::new(), Value::Bool(false) => String::new(), other => other.to_string() }
}

// ── runModules의 앞부분 ──

/// `runModules` 231 ~ 244줄 — 빈 `out`(이름 · 자료집 목록 · 빈 목록 아홉 · 간지 설정).
pub fn initial_out(ctx: &Ctx) -> Value {
    let pack_info = |p: &V| -> Value {
        let mut o = serde_json::Map::new();
        o.insert("id".into(), jsv(&p.get("id")));
        o.insert("name".into(), jsv(&or(p.get("name"), p.get("id"))));
        // JS `String.prototype.trim`(`js::Str::trim` — BOM · U+0085 따위가 Rust `str::trim`과 다르다 · 판정 R61 M4).
        for key in ["version", "category"] {
            if let V::Str(v) = p.get(key) {
                let t = v.trim();
                if !t.is_empty() { o.insert(key.into(), jsv(&V::Str(t))); }
            }
        }
        Value::Object(o)
    };
    let raw_name = ctx.raws.first().map(|r| r.get("name")).unwrap_or(V::Undef);
    let mut out = json!({
        "name": jsv(&raw_name), "packs": ctx.packs.iter().map(pack_info).collect::<Vec<_>>(),
        "categories": [], "tracks": [], "epochs": [], "axis": [], "periods": [], "cells": [], "events": [], "items": [], "entities": [],
    });
    // JS: `name: ctx.raw.name` — undefined면 열쇠가 빠진다(JSON.stringify).
    if raw_name.is_undef() { out.as_object_mut().expect("객체").remove("name"); }
    // D4 간지 설정: 처음 고른 순환과 DLC 차례의 후보를 함께 싣는다.
    let yc = ctx.model.get("yearCycle");
    if tv(&yc) {
        out["yearCycle"] = jsv(&yc);
        let cycles: Vec<Value> = ctx.packs.iter().filter(|p| !p.get("yearCycle").is_nullish()).map(|p| {
            let base = if matches!(p.get("yearCycle"), V::Bool(false)) { json!({ "off": true }) } else { jsv(&p.get("yearCycle")) };
            let mut o = base.as_object().cloned().unwrap_or_default();
            o.insert("packId".into(), jsv(&p.get("id")));
            o.insert("packName".into(), jsv(&p.get("name")));
            Value::Object(o)
        }).collect();
        out["yearCycles"] = Value::Array(cycles);
    }
    out
}

/// `runModules` 257 ~ 263줄 — 공통 점검: 줄 · 띠 · 칸 · 사건 · 일반 항목이 가리키는 곳이 있어야 한다(걸리면 오류 — Node의 assert 글 그대로).
/// JS의 비교 뜻 그대로(고침 1회차 — 너그럽지 않게): 열쇠가 없으면(undefined) 비교가 거짓 · `rowsOf[p.track]`은 정수 순번이 아니면 undefined(거짓) · `Set.has`는 글만.
pub fn common_checks(out: &Value) -> crate::Result<()> {
    /// JS 관계 비교(`<` · `<=`)에 넣은 값: 없음(undefined) → NaN(늘 거짓) · null → 0 · 참거짓 → 1 · 0 · 글 → `Number(글)` · 수 → 그대로 · 그 밖(객체 · 배열) → NaN.
    fn rel(v: Option<&Value>) -> f64 {
        match v { None => f64::NAN, Some(Value::Number(x)) => x.as_f64().unwrap_or(f64::NAN), Some(Value::Null) => 0.0, Some(Value::Bool(b)) => f64::from(*b),
            Some(Value::String(s)) => js::to_num(&V::from(s.as_str())), Some(_) => f64::NAN }
    }
    let rows_of: Vec<f64> = out["tracks"].as_array().map(|t| t.iter().map(|x| arr_len(x, "rows") as f64).collect()).unwrap_or_default();
    let tracks = rows_of.len() as f64;
    // `rowsOf[p.track]` — JS 배열의 칸 찾기: 열쇠는 `String(p.track)`(ToPropertyKey)이고 정수 모양의 글(`String(ToUint32(k)) === k`)만 배열 자리다 —
    // 수 1 · 1.0 · −0(→ '0') · 글 '1'은 찾고, null('null') · true('true') · '00' · '1.0' · 소수 · 음수 · 범위 밖은 undefined(→ 비교 거짓 — 16b: 예전엔 null · true · '00'을 수로 바꿔 찾았다).
    let rows_at = |v: Option<&Value>| -> f64 {
        let Some(v) = v else { return f64::NAN };
        // 빠른 길: 0 이상의 정수(JSON 정수)는 곧 배열 자리 — 거의 모든 원소가 이 꼴이다(JS 값 · 글로 바꿔 견주는 셈을 건너뜀 · 범위 밖은 undefined).
        if let Some(i) = v.as_u64() { return usize::try_from(i).ok().and_then(|i| rows_of.get(i)).copied().unwrap_or(f64::NAN); }
        let key = js::to_str(&js::from_json(v)).as_str().into_owned();
        match key.parse::<u32>() { Ok(i) if i.to_string() == key && (i as usize) < rows_of.len() => rows_of[i as usize], _ => f64::NAN }
    };
    let text = |v: Option<&Value>| -> String { v.map(js_text).unwrap_or_default() };
    let period_uids: std::collections::HashSet<&str> = out["periods"].as_array().map(|l| l.iter().filter_map(|p| p.get("uid").and_then(Value::as_str)).collect()).unwrap_or_default();
    for p in out["periods"].as_array().into_iter().flatten() {
        let (t, r) = (rel(p.get("track")), rel(p.get("row")));
        if !(t < tracks && r < rows_at(p.get("track")) && rel(p.get("start")) <= rel(p.get("end"))) { return Err(format!("띠의 자리 오류: {}", text(p.get("name"))).into()); }
    }
    for c in out["cells"].as_array().into_iter().flatten() {
        let has = c.get("period").and_then(Value::as_str).is_some_and(|u| period_uids.contains(u)); // Set.has — 글만 같을 수 있다
        if !(has && rel(c.get("start")) <= rel(c.get("end"))) { return Err(format!("칸이 가리키는 띠가 없거나 기간이 뒤집혔습니다: {}", text(c.get("name"))).into()); }
    }
    for e in out["events"].as_array().into_iter().flatten() {
        let (t, r) = (rel(e.get("track")), rel(e.get("row")));
        if !(t < tracks && r < rows_at(e.get("track"))) { return Err(format!("사건의 줄이 없습니다: {}", text(e.get("title"))).into()); }
    }
    for it in out["items"].as_array().into_iter().flatten() {
        let (t, r, r2) = (rel(it.get("track")), rel(it.get("row")), rel(it.get("row2")));
        if !(rel(it.get("section")) >= 16.0 && t < tracks && r <= r2 && r2 < rows_at(it.get("track")) && rel(it.get("start")) <= rel(it.get("end"))) {
            return Err(format!("일반 항목의 자리 오류: 구역 {} {}", text(it.get("section")), text(it.get("name"))).into());
        }
    }
    Ok(())
}

// ── shared의 덤프 · 심기 ──

/// `ctx.shared`의 덤프(정답지 `pre-<모듈>.shared.json`과 같은 규칙 — `seam`).
pub fn shared_dump(ctx: &Ctx) -> Value { js::seam(&V::Obj(ctx.shared.clone())) }

/// 정답지의 `shared` 덤프(seam 규칙 — `{"$map":[[k,v],…]}` · `{"$set":[…]}`)를 JS 값으로 되심는다. 모델 객체를 가리키는 `$ref`가 있으면 오류 —
/// 그런 shared는 심을 수 없으니 그 모듈과 그것을 쓰는 모듈을 한 갈래로 옮긴다(지금의 모듈 스물에는 없다).
/// **함정(고침 1회차):** 덤프는 `serde_json::Value`를 거치므로 보통 객체(`docsOf` · `cellDocsOf` — uid → 목록)의 열쇠는 **정렬된 차례**로 되심긴다(Map · Set은 `$map` · `$set`이라 넣은 차례 그대로).
/// 지금 그 둘을 읽는 곳(docs의 늦은 차례 — uid로 찾기만)은 차례를 보지 않아 무해하지만, 그 객체를 차례대로 도는 모듈이 생기면 Node와 갈린다 — 그때는 그 shared를 `$map`으로 덤프하게 바꾼다.
pub fn shared_seed(v: &Value) -> crate::Result<Obj> {
    let root = unseam(v)?;
    match root { V::Obj(o) => Ok(o), other => { js::release(&other); Err("shared 덤프의 맨 위는 객체여야 합니다".into()) } }
}
fn unseam(v: &Value) -> crate::Result<V> {
    Ok(match v {
        Value::Null => V::Null,
        Value::Bool(b) => V::Bool(*b),
        Value::Number(x) => V::Num(x.as_f64().unwrap_or(f64::NAN)),
        Value::String(s) => V::from(s.as_str()),
        Value::Array(l) => { let mut items = Vec::with_capacity(l.len()); for x in l { items.push(unseam(x)?); } V::Arr(js::Arr::new(items)) }
        Value::Object(o) => {
            if let Some(Value::Array(pairs)) = o.get("$map") {
                let m = Map::new();
                for pair in pairs {
                    let Some([k, x]) = pair.as_array().map(Vec::as_slice) else { return Err("$map의 칸은 [열쇠, 값]이어야 합니다".into()) };
                    m.set(unseam(k)?, unseam(x)?);
                }
                return Ok(V::Map(m));
            }
            if let Some(Value::Array(items)) = o.get("$set") {
                let st = Set::new();
                for x in items { st.add(unseam(x)?); }
                return Ok(V::Set(st));
            }
            if o.contains_key("$ref") { return Err(format!("shared 덤프에 모델 객체 참조가 있습니다({}) — 심을 수 없는 shared", o["$ref"]).into()); }
            let out = Obj::new();
            for (k, x) in o { if k == "$oracle" { continue; } out.set(k.as_str(), unseam(x)?); }
            V::Obj(out)
        }
    })
}

// ── 돌리기 ──

/// 모듈 하나를 돌리고 그 모듈이 남긴 잘못(`model::util::fault` — JS라면 TypeError로 멈췄을 곳)을 본다(16b 넘겨받은 틀 손질 — 모듈마다 fault 보기):
/// 오류로 돌아가면 남긴 잘못은 거두고 그 오류를, 아니면 남긴 잘못을 그 모듈의 오류로(뒤 모듈 · 줄 배정이 묵은 잘못을 제 글로 내지 않게).
/// 문맥의 꼴(`C`)은 가리지 않는다 — 검사가 문맥 없이 이 규칙만 잰다(아래 `tests`).
fn run_one<C>(name: &str, f: impl FnOnce(&mut C, &mut Value) -> crate::Result<()>, ctx: &mut C, out: &mut Value) -> crate::Result<()> {
    if let Err(e) = f(ctx, out) {
        let _ = crate::lay::model::util::take_fault();
        return Err(e);
    }
    crate::lay::m::kit::fault_check(name)
}

#[cfg(test)]
mod tests {
    use super::run_one;
    use crate::lay::model::util::{fault, take_fault};
    use serde_json::Value;

    /// 16b 틀 손질 검토: 모듈이 오류로 돌아가면 남긴 잘못은 거두고 그 오류가 나간다 · Ok인데 잘못을 남기면 그 모듈의 오류 · 둘 다 아니면 Ok.
    #[test]
    fn run_one_takes_the_fault_left_by_a_module() {
        let mut out = Value::Null;
        let e = run_one("가", |_: &mut (), _| { fault("묵은 잘못".into()); Err("모듈 오류".into()) }, &mut (), &mut out).unwrap_err().to_string();
        assert_eq!(e, "모듈 오류");
        assert!(take_fault().is_none(), "오류 뒤에 잘못이 남았습니다");
        let e = run_one("나", |_: &mut (), _| { fault("던졌을 곳".into()); Ok(()) }, &mut (), &mut out).unwrap_err().to_string();
        assert!(e.contains("나 모듈") && e.contains("던졌을 곳"), "{e}");
        assert!(take_fault().is_none());
        run_one("다", |_: &mut (), _| Ok(()), &mut (), &mut out).unwrap();
    }
}

/// 모듈 이름 → `MODULES`의 자리(모르면 오류).
fn module_at(name: &str) -> crate::Result<usize> { crate::lay::module_index(name).ok_or_else(|| format!("모르는 모듈: {name}").into()) }

/// `runModules(ctx, { skip })` — 문맥을 줄 배정까지 짓고 모듈을 앞자리(`opts.upto`까지 · None이면 스물 모두) 차례로 돌린다: `contribute` 전부 → 늦은 차례 전부 → 공통 점검.
/// 앞자리에 옮기지 않은 모듈이 들면 오류(`unported`). 정답지 `upto-<모듈>.json`과 견준다(`tests/lay_out.rs`).
///
/// 범위(`opts.scope`): `Scope::All`은 위 그대로. `Scope::Tracks(S)`는 **하위 배치** = `patch::sub_plan(export(All), S)`
/// (트랙 S의 것 + 온 판 + 항목 기록 전부 · 겉 `allTracks` · 변형의 `outer` — 계획 정한 것 #12 · P4 과제 9의 `Covers::Part`가 받는 꼴 · `tests/lay_scope.rs`가 지킴).
/// 하나 다름: **배치에 없는 판 트랙 열쇠**(`board:…`)는 걸러 낸다 — 닿는 트랙(`lay::touch`)은 판 트랙의 있고 없음을 배치 없이 짐작하는데 `boards.mjs`가 판 하나의 셈 오류로
/// 그 판을 빼는 길은 배치 없이는 모른다(합성 자료 `synth-lay`의 `view:epoch:synth-lay/ep-sd`). 그 밖의 없는 열쇠는 [`MissingTracks`] 오류 — 부르는 쪽
/// (`packs::relayout`)이 거절하지 않고 모든 트랙으로 넓혀 다시 배치한다(판정 R69-4 · 답의 `widened`).
///
/// 셈은 통째와 같다(과제 16b의 결론 — 계획 과제 16): S 밖 트랙의 몫도 하위 배치에 남는 값에 든다 — 온 판의 띠 수(`spheres` — 변형의 새 띠까지 모든 띠) ·
/// 띠 순번(`bandOf` — 일반 항목의 띠 번호) · 렌즈 변형(트랙 0)의 가림(모든 트랙의 지도자 칸 — 변형의 칸까지)과 렌즈 항목 기록의 사건 목록(변형의 새 사건까지) ·
/// 판(판이 서는가 · 판 하나의 셈 오류로 빠지는가가 `allTracks`에 실리고 판 변형은 구성 트랙 밖의 항목도 가린다) · 변형의 견줌(기본 항목의 느슨한 이름). 그래서 S 밖을
/// 건너뛰면 하위 배치가 달라진다(첫 시도 — 제 트랙이 S 밖인 변형 건너뛰기 — 가 `tests/lay_scope.rs`에서 등불 자료의 `spheres` 띠 수로 걸렸다). 대신 셈 자체를 줄였다:
/// 변형은 제 트랙만 다시 배치하고(`m::variants`) · 닿는 트랙이 준비한 '뒤' 조합의 문맥을 다시 쓴다([`keep_prepared`]).
pub fn export(packs: &[PackIn], opts: &Opts) -> crate::Result<Value> {
    Ok(export_with_notes(packs, opts)?.0)
}

/// [`export`]와 같은 배치 + 모듈이 남긴 집계 · 뺀 것의 기록(`ctx.notes` — 판의 `뺀판` · `어긋남` 따위 · JSON 값)(판정 R61 M3 — 예전엔 Rust 길에서 버렸다).
/// 짓기의 요약(`legacy::build_files`)이 싣는다. 범위 갈래(`Scope::Tracks`)의 기록은 통째 셈의 것이다.
pub fn export_with_notes(packs: &[PackIn], opts: &Opts) -> crate::Result<(Value, Value)> {
    let k = match &opts.upto { Some(name) => module_at(name)? + 1, None => MODULES.len() };
    let scope = match &opts.scope { crate::lay::Scope::Tracks(s) => Some(s), crate::lay::Scope::All => None };
    let mut ctx = match take_prepared(packs, opts) {
        Some(mut c) => { ctx::lay_out(&mut c)?; c }
        None => ctx::context_of(packs, opts, true)?,
    };
    ctx.shared = Obj::new(); // 모듈끼리 나눠 쓰는 것(예: 띠의 uid → out.periods의 순번)
    ctx.notes = Obj::new(); // 모듈이 남기는 집계 · 뺀 것의 기록
    let mut out = initial_out(&ctx);
    for m in &MODULES[..k] {
        if !m.ported { return Err(unported(m.name)); }
        run_one(m.name, m.contribute, &mut ctx, &mut out)?;
    }
    // 늦은 차례: 모든 모듈이 제 몫을 실은 뒤에 한 번 더 — 남이 실은 항목 기록에 값을 얹는 모듈이 쓴다(docs의 x_docs · x_cellDocs).
    for m in &MODULES[..k] {
        if let Some(late) = m.late { run_one(m.name, late, &mut ctx, &mut out)?; }
    }
    common_checks(&out)?;
    let notes = js::to_json(&V::Obj(ctx.notes.clone()));
    drop(ctx);
    let Some(s) = scope else { return Ok((out, notes)) };
    let n = out["tracks"].as_array().map_or(0, Vec::len) + out["boards"]["tracks"].as_array().map_or(0, Vec::len);
    let have: std::collections::BTreeSet<String> = (0..n).map(|i| crate::patch::track_key(&out, i)).collect();
    let missing: Vec<String> = s.iter().filter(|k| !k.starts_with("board:") && !have.contains(*k)).cloned().collect();
    if !missing.is_empty() {
        return Err(Box::new(MissingTracks(missing)));
    }
    let kept: std::collections::BTreeSet<String> = s.iter().filter(|k| have.contains(*k)).cloned().collect();
    Ok((crate::patch::sub_plan(&out, &kept)?, notes))
}

/// 범위(`Scope::Tracks(S)`)의 S에 이 배치에 없는 트랙 열쇠(판이 아닌 것)가 들었다 — 부르는 쪽(`packs::relayout`)은 거절하지 않고 모든 트랙으로 넓힌다(판정 R69-4).
#[derive(Debug)]
pub struct MissingTracks(pub Vec<String>);
impl std::fmt::Display for MissingTracks {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, "배치에 없는 트랙입니다: {}", self.0.join(" · ")) }
}
impl std::error::Error for MissingTracks {}

thread_local! {
    /// 준비해 둔 문맥 한 벌(줄 배정 전) — 닿는 트랙(`lay::touch::touched_scope`)이 '뒤' 조합을 준비해 견준 뒤 남긴다. 곧이어 같은 조합 · 같은 날 · 시간대 ·
    /// 달력 표로 내보내면([`export_with_notes`]) 다시 준비하지 않고 이것에 줄 배정을 마쳐 쓴다(과제 16b — DLC 넣기 한 번의 준비를 세 벌에서 두 벌로). 한 번 꺼내면 비고,
    /// 조합이 다르면 버린다. 준비는 입력만으로 정해지므로(같은 입력 → 같은 문맥) 답은 새로 준비한 것과 같다(`tests/lay_scope.rs`).
    static PREPARED: std::cell::RefCell<Option<Prepared>> = const { std::cell::RefCell::new(None) };
}

/// [`PREPARED`]의 한 벌 — 입력(DLC · 오늘 · 시간대 · 달력 표)과 그 준비.
struct Prepared { packs: Vec<PackIn>, now_ms: f64, tz_min: i32, calendar: Option<std::rc::Rc<Vec<u8>>>, ctx: Ctx }

/// 준비한 문맥(`ctx::context_of(packs, opts, false)`의 답)을 바로 뒤의 내보내기에 남긴다(앞에 남은 것은 버린다).
pub fn keep_prepared(packs: &[PackIn], opts: &Opts, ctx: Ctx) {
    let kept = Prepared { packs: packs.to_vec(), now_ms: opts.now_ms, tz_min: opts.tz_min, calendar: opts.calendar.clone(), ctx };
    let old = PREPARED.with(|c| c.borrow_mut().replace(kept));
    drop(old);
}

/// 준비해 둔 문맥을 버린다(`lay::clear_caches` — 넣고 빼기 끝 · 판정 R69-5).
pub fn clear_prepared() {
    let old = PREPARED.with(|c| c.borrow_mut().take());
    drop(old);
}

/// 준비해 둔 문맥이 남아 있는가(검사가 남기고 꺼내는 차례를 본다).
pub fn prepared_held() -> bool {
    PREPARED.with(|c| c.borrow().is_some())
}

/// 남긴 문맥이 이 입력의 것이면 꺼낸다(아니면 버린다).
fn take_prepared(packs: &[PackIn], opts: &Opts) -> Option<Ctx> {
    let p = PREPARED.with(|c| c.borrow_mut().take())?;
    let same_calendar = match (&p.calendar, &opts.calendar) {
        (None, None) => true,
        (Some(a), Some(b)) => std::rc::Rc::ptr_eq(a, b) || a == b,
        _ => false,
    };
    let same = p.now_ms.to_bits() == opts.now_ms.to_bits() && p.tz_min == opts.tz_min && same_calendar && p.packs.len() == packs.len()
        && p.packs.iter().zip(packs).all(|(a, b)| a.name == b.name && a.bytes == b.bytes);
    same.then_some(p.ctx)
}

/// 모듈 하나의 `contribute`만(과제 8-틀): 문맥을 줄 배정까지 짓고 `out`을 `seed_out`(Node의 `pre-<k−1>` — 첫 모듈이면 None = 빈 out)으로,
/// `ctx.shared`를 `seed_shared`(그 `.shared` 덤프 — None이면 빈 객체)로 심은 뒤 그 모듈만 돌린다. 돌려주는 값: (`out`, `shared`의 덤프) — Node의 `pre-<k>` · `pre-<k>.shared`와 견준다.
/// 옮기지 않은 모듈이면 오류.
pub fn export_one(packs: &[PackIn], opts: &Opts, module: &str, seed_out: Option<Value>, seed_shared: Option<&Value>) -> crate::Result<(Value, Value)> {
    let m = &MODULES[module_at(module)?];
    if !m.ported { return Err(unported(m.name)); }
    let mut ctx = ctx::context_of(packs, opts, true)?;
    ctx.shared = match seed_shared { Some(v) => shared_seed(v)?, None => Obj::new() };
    ctx.notes = Obj::new();
    let mut out = match seed_out { Some(v) => strip_oracle(v), None => initial_out(&ctx) };
    run_one(m.name, m.contribute, &mut ctx, &mut out)?;
    let shared = shared_dump(&ctx);
    Ok((out, shared))
}

/// 모듈 하나의 늦은 차례(`contributeLate`)만: `out`을 `seed_out`(앞 늦은 차례의 `late-<모듈>` — 처음은 `pre-lens`)으로, `shared`를 스물 모두 돈 덤프(`pre-lens.shared`)로 심고
/// 그 모듈의 늦은 차례만 돌린다. 늦은 차례가 없는 모듈 · 옮기지 않은 모듈이면 오류.
pub fn export_late(packs: &[PackIn], opts: &Opts, module: &str, seed_out: Value, seed_shared: Option<&Value>) -> crate::Result<Value> {
    let m = &MODULES[module_at(module)?];
    if !m.ported { return Err(unported(m.name)); }
    let Some(late) = m.late else { return Err(format!("{module}에는 늦은 차례(contributeLate)가 없습니다").into()) };
    let mut ctx = ctx::context_of(packs, opts, true)?;
    ctx.shared = match seed_shared { Some(v) => shared_seed(v)?, None => Obj::new() };
    ctx.notes = Obj::new();
    let mut out = strip_oracle(seed_out);
    run_one(m.name, late, &mut ctx, &mut out)?;
    Ok(out)
}

/// 정답지 파일의 머리 `$oracle`을 뗀다(심은 out에 남지 않게).
fn strip_oracle(mut v: Value) -> Value {
    if let Some(o) = v.as_object_mut() { o.remove("$oracle"); }
    v
}

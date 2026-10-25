//! P3 과제 3 — JS 값 층(`lay::js`)이 Node와 같은 답을 내는지 벡터로 견준다.
//! 벡터: `tests/fixtures/lay/js-vectors.json`(`node prototype/scripts/js-vectors.mjs`가 시간대 Asia/Seoul로 뽑음 — Node가 정답).
//! 갈래 열하나(num · round · int · coerce · str · keys · sort · minute · local · json · seam)마다 검사 하나(`cmp16`은 과제 4가 더한 열셋째 갈래 —
//! 웹의 `HT.cmp16`이 UTF-16 코드 단위 차례임을 지킨다), 그리고 벡터 밖의 짜임 검사
//! (읽기 깊이 상한 512 · 쓰기 깊이 1,000 · 객체 열쇠 차례 · Map 열쇠 같음 · serde 다리). `regex` 갈래는 뽑기만 했다(Rust 쪽은 과제 12a).
//! 값을 적는 '짓기 꼴'은 `js-vectors.mjs` 머리말 — 아래 `build`가 그 Rust 짝이다.
use archive_engine::lay::js::{self, Arr, Map, Obj, Set, Str, V};
use archive_engine::lay::same::diff;
use serde_json::Value;
use std::cmp::Ordering;
use std::collections::HashMap;
use std::path::Path;
use std::sync::OnceLock;

fn vectors() -> &'static Value {
    static VECTORS: OnceLock<Value> = OnceLock::new();
    VECTORS.get_or_init(|| {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("lay").join("js-vectors.json");
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e} — node prototype/scripts/js-vectors.mjs", path.display()));
        serde_json::from_str(&text).expect("js-vectors.json은 JSON이어야 합니다")
    })
}
fn group(name: &str) -> &'static Vec<Value> {
    vectors()[name].as_array().unwrap_or_else(|| panic!("벡터 갈래 {name}이(가) 없습니다"))
}

/// 수 하나 — "NaN" · "Infinity" · "-Infinity" · "-0"은 글로 적혀 있다.
fn num(v: &Value) -> f64 {
    match v {
        Value::Number(n) => n.as_f64().unwrap(),
        Value::String(s) => match s.as_str() {
            "NaN" => f64::NAN,
            "Infinity" => f64::INFINITY,
            "-Infinity" => f64::NEG_INFINITY,
            "-0" => -0.0,
            _ => panic!("수 글이 아닙니다: {s}"),
        },
        _ => panic!("수가 아닙니다: {v}"),
    }
}
/// 비트까지 같음(NaN끼리는 같다고 본다 — JS는 NaN의 비트를 드러내지 않는다).
fn same_num(a: f64, b: f64) -> bool { (a.is_nan() && b.is_nan()) || a.to_bits() == b.to_bits() }

/// 짓기 꼴 → V(`js-vectors.mjs`의 `build`와 같은 뜻).
fn build(e: &Value, ids: &mut HashMap<String, V>) -> V {
    match e {
        Value::Null => V::Null,
        Value::Bool(b) => V::Bool(*b),
        Value::Number(_) => V::Num(num(e)),
        Value::String(s) => V::from(s.as_str()),
        Value::Array(items) => {
            let arr = Arr::new(Vec::new());
            for x in items { let v = build(x, ids); arr.push(v); }
            V::Arr(arr)
        }
        Value::Object(o) => {
            let keep = |v: V, ids: &mut HashMap<String, V>| { if let Some(id) = o.get("$id").and_then(Value::as_str) { ids.insert(id.to_string(), v.clone()); } v };
            if o.contains_key("$u") { return V::Undef; }
            if let Some(n) = o.get("$num") { return V::Num(num(n)); }
            if let Some(u) = o.get("$s16") {
                let units: Vec<u16> = u.as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u16).collect();
                return V::Str(Str::from_units(&units));
            }
            if let Some(name) = o.get("$see") { return ids.get(name.as_str().unwrap()).unwrap_or_else(|| panic!("앞에 없는 $see {name}")).clone(); }
            if let Some(pairs) = o.get("$o") {
                let obj = Obj::new();
                keep(V::Obj(obj.clone()), ids);
                for p in pairs.as_array().unwrap() { let v = build(&p[1], ids); obj.set(p[0].as_str().unwrap(), v); }
                return V::Obj(obj);
            }
            if let Some(items) = o.get("$a") {
                let arr = Arr::new(Vec::new());
                keep(V::Arr(arr.clone()), ids);
                for x in items.as_array().unwrap() { let v = build(x, ids); arr.push(v); }
                return V::Arr(arr);
            }
            if let Some(pairs) = o.get("$map") {
                let map = Map::new();
                keep(V::Map(map.clone()), ids);
                for p in pairs.as_array().unwrap() { let (k, v) = (build(&p[0], ids), build(&p[1], ids)); map.set(k, v); }
                return V::Map(map);
            }
            if let Some(items) = o.get("$set") {
                let set = Set::new();
                keep(V::Set(set.clone()), ids);
                for x in items.as_array().unwrap() { let v = build(x, ids); set.add(v); }
                return V::Set(set);
            }
            panic!("짓기 꼴이 아닙니다: {e}")
        }
    }
}
fn built(e: &Value) -> V { build(e, &mut HashMap::new()) }

/// 원시 V → 짓기 꼴(견주기용 — 수는 정수면 정수, -0 · NaN · ±Infinity는 글).
fn enc(v: &V) -> Value {
    match v {
        V::Undef => serde_json::json!({"$u": 0}),
        V::Null => Value::Null,
        V::Bool(b) => Value::Bool(*b),
        V::Num(x) => {
            if x.is_nan() { serde_json::json!({"$num": "NaN"}) }
            else if x.is_infinite() { serde_json::json!({"$num": if *x > 0.0 { "Infinity" } else { "-Infinity" }}) }
            else if *x == 0.0 && x.is_sign_negative() { serde_json::json!({"$num": "-0"}) }
            else { serde_json::Number::from_f64(*x).map(Value::Number).unwrap() }
        }
        V::Str(s) => match s.exact() {
            Some(text) => Value::String(text.to_string()),
            None => serde_json::json!({"$s16": s.to_units()}),
        },
        other => panic!("원시 값이 아닙니다: {other:?}"),
    }
}
/// 짓기 꼴 둘이 같은가(수는 값으로 — `lay::same::diff`).
fn assert_same(got: &Value, want: &Value, what: &str) {
    let d = diff(got, want, 5);
    assert!(d.is_empty(), "{what}: {}", d.join(" · "));
}
/// JS의 SameValue(같은 수 · 같은 글 · 같은 객체).
fn same_value(a: &V, b: &V) -> bool {
    match (a, b) { (V::Num(x), V::Num(y)) => same_num(*x, *y), _ => js::strict_eq(a, b) }
}

#[test]
fn numbers_print_like_js() {
    for r in group("num") {
        let n = num(&r[0]);
        assert_eq!(js::num_str(n), r[1].as_str().unwrap(), "String({r})");
        assert_eq!(js::stringify(&V::Num(n)), r[2].as_str().unwrap(), "JSON.stringify({r})");
        // serde 다리(to_json → 글 → from_json)도 비트까지 — JSON.stringify처럼 -0은 0, 수가 아니면 null이 된다.
        let text = serde_json::to_string(&js::to_json(&V::Num(n))).unwrap();
        let back = js::from_json(&serde_json::from_str(&text).unwrap());
        if n.is_finite() {
            let want = if n == 0.0 { 0.0 } else { n };
            assert!(matches!(back, V::Num(x) if x.to_bits() == want.to_bits()), "to_json/from_json {r}: {text}");
        } else {
            assert!(matches!(back, V::Null), "to_json({r})는 null");
        }
    }
}

#[test]
fn math_round_like_js() {
    for r in group("round") {
        let got = js::round(num(&r[0]));
        assert!(same_num(got, num(&r[1])), "Math.round({}) = {} 인데 {got:?}", r[0], r[1]);
    }
    assert!(same_num(js::max(&[]), f64::NEG_INFINITY) && same_num(js::min(&[]), f64::INFINITY), "빈 Math.max/min");
    assert!(js::max(&[1.0, f64::NAN, 3.0]).is_nan() && js::min(&[f64::NAN, 1.0]).is_nan(), "NaN이 있으면 NaN");
    assert!(same_num(js::max(&[-0.0, 0.0]), 0.0) && same_num(js::min(&[0.0, -0.0]), -0.0), "±0의 큰 쪽은 +0 · 작은 쪽은 -0");
    assert_eq!(js::max(&[1.0, 5.0, 3.0]), 5.0);
}

#[test]
fn int_conversions_wrap_like_js() {
    for r in group("int") {
        let x = num(&r[0]);
        assert_eq!(js::to_i32(x) as i64, r[1].as_i64().unwrap(), "{} | 0", r[0]);
        assert_eq!(js::to_u32(x) as u64, r[2].as_u64().unwrap(), "{} >>> 0", r[0]);
    }
}

#[test]
fn coercions_like_js() {
    let b = V::from("b");
    for r in group("coerce") {
        let x = built(&r[0]);
        assert!(same_num(js::to_num(&x), num(&r[1])), "Number({}) = {} 인데 {:?}", r[0], r[1], js::to_num(&x));
        assert!(same_num(js::parse_int(&x, 10), num(&r[2])), "parseInt({}, 10) = {} 인데 {:?}", r[0], r[2], js::parse_int(&x, 10));
        assert!(same_num(js::parse_int(&x, 0), num(&r[3])), "parseInt({}) = {} 인데 {:?}", r[0], r[3], js::parse_int(&x, 0));
        assert!(same_num(js::parse_float(&x), num(&r[4])), "parseFloat({}) = {} 인데 {:?}", r[0], r[4], js::parse_float(&x));
        assert_same(&enc(&V::Str(js::to_str(&x))), &r[5], &format!("String({})", r[0]));
        let truthy = r[6].as_bool().unwrap();
        assert_eq!(js::truthy(&x), truthy, "Boolean({})", r[0]);
        assert_eq!(x.is_nullish(), r[7].as_bool().unwrap(), "{} == null", r[0]);
        assert!(same_value(&js::or(x.clone(), b.clone()), if truthy { &x } else { &b }), "{} || 'b'", r[0]);
        assert!(same_value(&js::nullish(x.clone(), b.clone()), if x.is_nullish() { &b } else { &x }), "{} ?? 'b'", r[0]);
    }
}

#[test]
fn strings_count_utf16_like_js() {
    let str_of = |e: &Value| match built(e) { V::Str(s) => s, other => panic!("글이 아닙니다: {other:?}") };
    for r in vectors()["str"]["one"].as_array().unwrap() {
        let s = str_of(&r["s"]);
        let what = r["s"].to_string();
        assert_eq!(s.len16() as u64, r["length"].as_u64().unwrap(), "{what}.length");
        assert!(same_num(s.code_at(1.0), num(&r["code1"])), "{what}.charCodeAt(1)");
        assert_same(&s.at16(2.0).map_or_else(|| enc(&V::Undef), |c| enc(&V::Str(c))), &r["at2"], &format!("{what}[2]"));
        for x in r["slices"].as_array().unwrap() {
            let want: Vec<u16> = x[2].as_array().unwrap().iter().map(|u| u.as_u64().unwrap() as u16).collect();
            assert_eq!(s.slice16(num(&x[0]), num(&x[1])).to_units(), want, "{what}.slice({}, {})", x[0], x[1]);
        }
        for x in r["indexOf"].as_array().unwrap() {
            let needle = str_of(&x[0]);
            assert!(same_num(s.index_of16(&needle, num(&x[1])), num(&x[2])), "{what}.indexOf({}, {}) = {}", x[0], x[1], x[2]);
        }
    }
    for r in vectors()["str"]["less"].as_array().unwrap() {
        let (a, b) = (str_of(&r[0]), str_of(&r[1]));
        assert_eq!(a.cmp16(&b) == Ordering::Less, r[2].as_bool().unwrap(), "{} < {}", r[0], r[1]);
    }
}

/// P3 과제 4 — `HT.cmp16`(글 비교의 UTF-16 코드 단위 차례). 웹이 ICU `localeCompare` 대신 쓰게 된 비교이고, 정답지가 지나지 않는 곳
/// (core.js 셋 · timeline.js 승계선)의 유일한 그물이라 갈리기 쉬운 쌍을 갈래별로 모았다. 갈래마다 개수 하한을 단언한다(빈 갈래 통과 금지).
#[test]
fn cmp16_is_utf16_code_unit_order() {
    // (갈래, 행 수 하한, 'UTF-16 차례와 코드 포인트 차례가 갈리는 행 수' 하한)
    const FLOORS: [(&str, usize, usize); 8] = [
        ("case", 20, 0), ("korea", 16, 0), ("script", 28, 2), ("punct", 24, 0), ("nfd", 14, 0), ("empty", 12, 0), ("prefix", 20, 0), ("astral", 44, 22),
    ];
    let branches = vectors()["cmp16"].as_object().expect("cmp16 갈래가 없습니다 — node prototype/scripts/js-vectors.mjs");
    let mut names: Vec<&str> = branches.keys().map(String::as_str).collect();
    names.sort_unstable();
    let mut want: Vec<&str> = FLOORS.iter().map(|f| f.0).collect();
    want.sort_unstable();
    assert_eq!(names, want, "cmp16 안의 갈래가 하한 표와 다르다 — 새 갈래는 하한을 먼저 적는다");
    let sign = |o: Ordering| match o { Ordering::Less => -1, Ordering::Equal => 0, Ordering::Greater => 1 };
    let str_of = |e: &Value| match built(e) { V::Str(s) => s, other => panic!("글이 아닙니다: {other:?}") };
    let (mut total, mut lone_total) = (0, 0);
    for (name, min_rows, min_cp_differs) in FLOORS {
        let rows = branches[name].as_array().unwrap_or_else(|| panic!("cmp16.{name}이(가) 배열이 아니다"));
        assert!(rows.len() >= min_rows, "cmp16.{name}: 행 {}개 — {min_rows}개 이상이어야 한다", rows.len());
        let (mut less, mut greater, mut cp_differs, mut lone) = (0, 0, 0, 0);
        for r in rows {
            let (a, b) = (str_of(&r[0]), str_of(&r[1]));
            let want = r[2].as_i64().unwrap();
            assert_eq!(sign(a.cmp16(&b)), want, "cmp16.{name}: {} vs {}", r[0], r[1]);
            assert_eq!(sign(b.cmp16(&a)), -want, "cmp16.{name}: 거꾸로 {} vs {}", r[1], r[0]);
            if want < 0 { less += 1 } else if want > 0 { greater += 1 }
            if want != r[3].as_i64().unwrap() { cp_differs += 1 }
            // 외톨이 서로게이트가 든 글은 짓기 꼴 `$s16` — 소스에 날 글자로 적으면 U+FFFD로 바뀌어 이 행이 사라진다(그래서 하한을 단언한다)
            if r[0].get("$s16").is_some() || r[1].get("$s16").is_some() { lone += 1 }
            assert_eq!(sign(a.to_units().cmp(&b.to_units())), want, "cmp16.{name}: 코드 단위 열 {} vs {}", r[0], r[1]);
            // 벡터 자체를 Rust 표준 글로도 확인 — 외톨이 서로게이트가 없는 쌍은 UTF-16 코드 단위 열 비교 = want, 바이트(코드 포인트) 비교 = r[3]
            if let (Some(x), Some(y)) = (a.exact(), b.exact()) {
                assert_eq!(sign(x.encode_utf16().cmp(y.encode_utf16())), want, "cmp16.{name}: 표준 UTF-16 {} vs {}", r[0], r[1]);
                assert_eq!(sign(x.cmp(y)), r[3].as_i64().unwrap(), "cmp16.{name}: 코드 포인트 차례 {} vs {}", r[0], r[1]);
            }
        }
        assert!(less > 0 && greater > 0, "cmp16.{name}: 앞이 작은 쌍 {less} · 큰 쌍 {greater} — 둘 다 있어야 한다");
        assert!(cp_differs >= min_cp_differs, "cmp16.{name}: 코드 포인트 차례와 갈리는 행 {cp_differs}개 — {min_cp_differs}개 이상이어야 한다(UTF-8 바이트 비교로 짜도 통과하면 안 된다)");
        if name == "astral" { assert!(lone >= 8, "cmp16.astral: 외톨이 서로게이트 행 {lone}개 — 8개 이상이어야 한다"); }
        total += rows.len();
        lone_total += lone;
    }
    assert!(total >= 185, "cmp16 행 {total}개 — 185개 이상이어야 한다");
    assert!(lone_total >= 12, "cmp16 안의 외톨이 서로게이트(`$s16`) 행 {lone_total}개 — 12개 이상이어야 한다");
}

#[test]
fn object_keys_keep_js_order() {
    for r in group("keys") {
        let v = js::parse(r[0].as_str().unwrap()).unwrap();
        assert_eq!(js::stringify(&v), r[1].as_str().unwrap(), "{}", r[0]);
    }
}

#[test]
fn sort_is_v8_timsort() {
    for c in group("sort") {
        let name = c["name"].as_str().unwrap();
        match c["cmp"].as_str().unwrap() {
            cmp @ ("sub" | "weird") => {
                let mut items: Vec<V> = c["keys"].as_array().unwrap().iter().enumerate().map(|(id, k)| {
                    let o = Obj::new();
                    o.set("id", V::from(id as f64));
                    o.set("k", if k.is_null() { V::Undef } else { V::Num(num(k)) });
                    V::Obj(o)
                }).collect();
                let (mut calls, mut sum) = (0u64, 0u64);
                js::sort(&mut items, |a, b| {
                    let (ia, ib) = (a.num("id"), b.num("id"));
                    calls += 1;
                    sum = (sum * 31 + ia as u64 * 4096 + ib as u64) % 1_000_000_007;
                    if cmp == "sub" { a.num("k") - b.num("k") } else { ((ia * 7.0 + ib * 11.0) % 5.0) - 2.0 }
                });
                let got: Vec<u64> = items.iter().map(|o| o.num("id") as u64).collect();
                let want: Vec<u64> = c["out"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap()).collect();
                assert_eq!(got, want, "{name}: 차례");
                assert_eq!((calls, sum), (c["calls"].as_u64().unwrap(), c["sum"].as_u64().unwrap()), "{name}: 비교 부름 수 · 차례 체크섬");
            }
            cmp @ ("num" | "none") => {
                let mut items: Vec<V> = c["input"].as_array().unwrap().iter().map(built).collect();
                if cmp == "num" { js::sort(&mut items, |a, b| js::to_num(a) - js::to_num(b)); } else { js::sort_default(&mut items); }
                let got = Value::Array(items.iter().map(enc).collect());
                assert_same(&got, &c["out"], name);
            }
            other => panic!("모르는 비교 {other}"),
        }
    }
}

#[test]
fn minute_matches_base_mjs() {
    for r in group("minute") {
        let y = num(&r[0]);
        let want = if r[1].is_null() || r[1] == "NaN" { None } else { Some(r[1].as_i64().unwrap()) };
        assert_eq!(js::minute(y), want, "minute({})", r[0]);
    }
}

#[test]
fn local_date_follows_offset() {
    for r in group("local") {
        assert_eq!(r[4].as_i64().unwrap(), -540, "벡터는 Asia/Seoul(오프셋 -540)에서 뽑아야 합니다");
        let want = (r[1].as_i64().unwrap() as i32, r[2].as_u64().unwrap() as u32 + 1, r[3].as_u64().unwrap() as u32);
        assert_eq!(js::local_ymd(num(&r[0]), 540), want, "{}", r[0]);
    }
}

#[test]
fn json_text_like_js() {
    let json = &vectors()["json"];
    for r in json["stringify"].as_array().unwrap() {
        let want = r[1].as_str().unwrap();
        assert_eq!(js::stringify(&built(&r[0])), want, "JSON.stringify({})", r[0]);
        assert_eq!(js::stringify(&js::parse(want).unwrap()), want, "다시 읽어 쓰기 {want}");
    }
    for r in json["parse"].as_array().unwrap() {
        let text = r[0].as_str().unwrap();
        let got = js::parse(text);
        assert_eq!(got.is_ok(), r[1].as_bool().unwrap(), "JSON.parse({text:?})의 됨/안 됨");
        if let Ok(v) = got { assert_eq!(js::stringify(&v), r[2].as_str().unwrap(), "JSON.stringify(JSON.parse({text:?}))"); }
    }
}

#[test]
fn seam_matches_oracle_rule() {
    for r in group("seam") {
        let name = r[0].as_str().unwrap();
        let v = built(&r[1]);
        let want = r[2].as_str().unwrap();
        assert_eq!(js::seam_text(&v), want, "{name}: 덤프 글");
        assert_same(&js::seam(&v), &serde_json::from_str(want).unwrap(), name);
    }
}

/// 정답지 JSON은 113겹까지 간다(`lantern/prep.json`). 읽기는 512겹(`lay/js/json.rs`의 `MAX_DEPTH`)까지 읽고, 넘으면 쉬운 글로 Err —
/// 수만 · 백만 겹 `[[[[…`도 쌓기(스택)를 넘치지 않고 Err(판정 R61 · M1: 상한이 없을 때는 읽힌 뒤 쓰기 · 덤프 · drop의 재귀가 프로세스를 죽였다).
/// 쓰기 · 덤프 · serde 다리 · drop은 재귀하지만 깊이 1,000(상한의 두 배 남짓 — 손으로 지은 값)에서도 죽지 않는다.
#[test]
fn deep_nesting_does_not_overflow() {
    const MAX: usize = 512; // lay/js/json.rs의 MAX_DEPTH
    let arr = |d: usize| format!("{}{}", "[".repeat(d), "]".repeat(d));
    let obj = |d: usize| format!("{}1{}", "{\"a\":".repeat(d), "}".repeat(d));
    for text in [arr(MAX), obj(MAX)] {
        let v = js::parse(&text).unwrap();
        assert_eq!(js::stringify(&v), text);
        assert_eq!(js::seam_text(&v), text);
        assert_eq!(js::stringify(&js::from_json(&js::to_json(&v))), text);
    }
    // 한 겹 더 · 수만 겹 · 맨 안의 빈 그릇 · 닫히지 않은 백만 겹 — 모두 그 겹에 닿는 자리에서 Err.
    // 글은 다른 JSON 읽기 오류처럼 중립이다("JSON.parse: … (바이트 N)" — 판정 R64 · M3). 쉬운 글은 팩을 읽는 곳(`lay/pack.rs`)이 씌운다 — 아래 검사.
    let empty_inside = format!("{}{{}}{}", "[".repeat(MAX), "]".repeat(MAX));
    for text in [arr(MAX + 1), obj(MAX + 1), arr(100_000), obj(100_000), empty_inside, "[".repeat(1_000_000)] {
        let e = js::parse(&text).expect_err("상한을 넘는 겹침은 Err").to_string();
        assert!(e.starts_with("JSON.parse: ") && e.contains("겹침이 512겹을 넘습니다") && e.contains("(바이트 "), "{e}");
        assert!(!e.contains("팩 내용") && !e.contains("파일이 손상"), "json 층의 글에 팩 쪽 쉬운 글이 섞였습니다: {e}");
    }
    // 쓰기 · 덤프 · 다리 · drop은 상한 밖 깊이 1,000에서도(parse는 이렇게 깊은 값을 내지 않는다 — 여유를 본다)
    const DEEP: usize = 1000;
    let mut v = V::Arr(Arr::new(Vec::new()));
    for _ in 1..DEEP { v = V::Arr(Arr::new(vec![v])); }
    let text = arr(DEEP);
    assert_eq!(js::stringify(&v), text);
    assert_eq!(js::seam_text(&v), text);
    assert_eq!(js::stringify(&js::from_json(&js::to_json(&v))), text);
}

/// 판정 R64 · M3: 깊이 상한의 쉬운 글('팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다')은 팩을 읽는 곳(`lay/pack.rs`)이 씌우되 json 층의 까닭을 버리지 않는다.
/// 형식 팩(`.htpack`)은 쉬운 글 + 까닭, JSON 파일은 '… JSON이 아닙니다 — 까닭'(`pack.rs` 38줄 — 그대로). 512겹까지는 팩이 읽힌다(그 뒤의 거절은 팩 종류 — 읽기는 통과).
#[test]
fn deep_pack_is_refused_in_plain_words_with_the_reason() {
    use archive_engine::lay::{self, Opts, PackIn, Scope};
    let opts = Opts { now_ms: 0.0, tz_min: 540, upto: None, scope: Scope::All, calendar: None };
    let deep = |d: usize| format!("{}{}", "[".repeat(d), "]".repeat(d));
    let refused = |name: &str, bytes: Vec<u8>| lay::normalized(&PackIn { name: name.into(), bytes }, &opts).expect_err("읽을 수 없는 팩은 거절").to_string();
    // 513겹 — 형식 팩: 쉬운 글 + 중립 까닭
    let e = refused("deep.htpack", archive_engine::legacy::seal_dlc(deep(513).as_bytes()));
    assert!(e.starts_with("deep.htpack: 팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다"), "쉬운 글: {e}");
    assert!(e.contains("JSON.parse: 겹침이 512겹을 넘습니다"), "까닭을 버리면 안 된다: {e}");
    assert_eq!(e.matches("파일이 손상되었습니다").count(), 1, "쉬운 글이 두 겹으로 겹치면 안 된다: {e}");
    // 513겹 — JSON 파일: pack.rs 38줄의 글에 까닭이 그대로(쉬운 글이 한 겹도 없다)
    let e = refused("deep.json", deep(513).into_bytes());
    assert!(e.starts_with("deep.json: JSON이 아닙니다 — JSON.parse: 겹침이 512겹을 넘습니다"), "{e}");
    assert!(!e.contains("파일이 손상"), "{e}");
    // 512겹은 읽혀서 팩 종류 검사까지 간다(깊이 때문이 아니다)
    let e = refused("ok.htpack", archive_engine::legacy::seal_dlc(deep(512).as_bytes()));
    assert!(!e.contains("겹침") && !e.contains("JSON.parse"), "512겹은 읽혀야 한다: {e}");
}

/// 객체: 정수 모양 열쇠가 먼저(오름차순), 나머지는 넣은 차례 · 지우고 다시 넣으면 끝으로 · 있는 열쇠에 쓰면 자리 그대로.
#[test]
fn object_order_after_set_and_delete() {
    let o = Obj::new();
    for k in ["b", "2", "a", "10", "c"] { o.set(k, V::from(1.0)); }
    assert!(o.delete("b"));
    assert!(!o.delete("b"));
    o.set("b", V::from(2.0));
    o.set("a", V::from(3.0));
    o.set("0", V::Null);
    let keys: Vec<String> = o.keys().iter().map(|k| k.to_string()).collect();
    assert_eq!(keys, ["0", "2", "10", "a", "c", "b"]);
    assert!(o.has("10") && !o.has("1") && o.get("zz").is_undef());
    assert_eq!(o.num("a"), 3.0);
    assert!(o.num("zz").is_nan() && o.str("a").is_none() && !o.bool("zz") && o.bool("a"));
    // 큰 객체(찾기 색인을 쓰는 크기)도 같은 뜻
    let big = Obj::new();
    for i in 0..200 { big.set(&format!("k{i}"), V::from(i as f64)); }
    for i in (0..200).step_by(3) { big.delete(&format!("k{i}")); }
    big.set("k0", V::from(-1.0));
    let keys: Vec<String> = big.keys().iter().map(|k| k.to_string()).collect();
    assert_eq!(keys.len(), 200 - 67 + 1);
    assert_eq!(keys.last().unwrap(), "k0");
    assert_eq!(big.num("k5"), 5.0);
    assert!(big.get("k3").is_undef());
    // 같은 객체를 여럿이 나눠 가진다(===은 Rc 같음)
    let shared = V::Obj(Obj::new());
    let holder = Obj::new();
    holder.set("x", shared.clone());
    holder.set("y", shared.clone());
    assert!(js::strict_eq(&holder.get("x"), &holder.get("y")));
    assert!(!js::strict_eq(&V::Obj(Obj::new()), &V::Obj(Obj::new())));
}

/// Map · Set: 넣은 차례 · 열쇠 같음은 SameValueZero(NaN끼리 같음 · +0과 -0 같음 · 객체는 Rc 같음).
#[test]
fn map_and_set_use_same_value_zero() {
    let m = Map::new();
    let (a, b) = (V::Obj(Obj::new()), V::Obj(Obj::new()));
    m.set(a.clone(), V::from(1.0));
    m.set(b.clone(), V::from(2.0));
    m.set(V::Num(f64::NAN), V::from(3.0));
    m.set(V::Num(-0.0), V::from(4.0));
    m.set(V::Num(0.0), V::from(5.0));
    m.set(V::from("1"), V::from(6.0));
    m.set(V::from(1.0), V::from(7.0));
    assert_eq!(m.len(), 6);
    assert_eq!(m.get(&a).as_num(), Some(1.0));
    assert_eq!(m.get(&V::Num(f64::NAN)).as_num(), Some(3.0));
    assert_eq!(m.get(&V::Num(0.0)).as_num(), Some(5.0));
    assert!(same_num(m.keys()[3].as_num().unwrap(), 0.0), "Map은 -0 열쇠를 +0으로 둔다");
    assert!(m.delete(&b) && !m.has(&b) && m.len() == 5);
    m.set(b.clone(), V::from(8.0));
    assert!(js::strict_eq(&m.keys()[5], &b), "지우고 다시 넣으면 끝으로");
    let s = Set::new();
    for v in [V::from(1.0), V::from(1.0), V::Num(f64::NAN), V::Num(f64::NAN), V::from("1"), a.clone(), a.clone(), V::Undef] { s.add(v); }
    assert_eq!(s.len(), 5);
    assert!(s.has(&V::Num(f64::NAN)) && s.has(&a) && !s.has(&b) && s.has(&V::Undef));
}

/// serde 다리: to_json은 JSON.stringify의 뜻(undefined 열쇠 빠짐 · 배열 안 undefined는 null · Map/Set은 {}), from_json은 그 반대.
#[test]
fn serde_bridge_follows_json_stringify() {
    let v = js::parse(r#"{"b":[1,2.5,"x",null,true],"a":{"9":0,"1":1}}"#).unwrap();
    let o = v.as_obj().unwrap();
    o.set("u", V::Undef);
    o.set("m", V::Map(Map::new()));
    v.arr("b").unwrap().push(V::Undef);
    let j = js::to_json(&v);
    assert_eq!(j, serde_json::json!({"b":[1,2.5,"x",null,true,null],"a":{"1":1,"9":0},"m":{}}));
    assert_eq!(js::stringify(&js::from_json(&j)), r#"{"a":{"1":1,"9":0},"b":[1,2.5,"x",null,true,null],"m":{}}"#);
}

/// 과제 6 고침 1회차 — 열거되지 않는 속성(`Object.defineProperty(o, k, { enumerable: false, writable: true, configurable: true })`): 읽기 · `in`은 보이고
/// 열쇠 차례 · JSON · `Object.assign` 사본에서는 빠지며, 쓰면 열거되지 않은 채 값만 바뀌고, 같은 이름의 보통 열쇠를 숨김으로 바꾸고, 지우면 사라진다 — Node 벡터와 같다.
#[test]
fn hidden_properties_follow_define_property() {
    let rows = group("hidden");
    assert!(rows.len() >= 7, "hidden 벡터가 모자랍니다");
    for r in rows {
        let v = js::parse(r[0].as_str().unwrap()).unwrap();
        let o = v.as_obj().unwrap();
        for op in r[1].as_array().unwrap() {
            let k = op[0].as_str().unwrap();
            let key = op[1].as_str().unwrap();
            match k {
                "def" => o.define_hidden(key, js::from_json(&op[2])),
                "set" => o.set(key, js::from_json(&op[2])),
                "del" => { o.delete(key); }
                other => panic!("모르는 할 일 {other}"),
            }
        }
        let want = &r[3];
        let keys: Vec<String> = o.keys().iter().map(|k| k.to_string()).collect();
        let want_keys: Vec<String> = want["keys"].as_array().unwrap().iter().map(|k| k.as_str().unwrap().to_string()).collect();
        assert_eq!(keys, want_keys, "{}: 열쇠", r[0]);
        assert_eq!(js::stringify(&v), want["json"].as_str().unwrap(), "{}: JSON", r[0]);
        assert_eq!(js::stringify(&V::Obj(archive_engine::lay::read::assign_copy(&v))), want["assign"].as_str().unwrap(), "{}: Object.assign 사본", r[0]);
        for (i, k) in r[2].as_array().unwrap().iter().enumerate() {
            let k = k.as_str().unwrap();
            let got = o.get(k);
            let shown = if got.is_undef() { "undefined".to_string() } else { js::stringify(&got) };
            assert_eq!(shown, want["get"][i].as_str().unwrap(), "{}: o[{k}]", r[0]);
            assert_eq!(o.has(k), want["has"][i].as_bool().unwrap(), "{}: {k} in o", r[0]);
        }
    }
    // 덤프(seam)도 숨은 속성을 적지 않는다 · 풀기는 숨은 속성 속까지 비운다
    let o = Obj::new();
    o.set("a", 1.0);
    let inner = Obj::new();
    inner.set("back", V::Obj(o.clone()));
    o.define_hidden("h", V::Obj(inner.clone()));
    assert_eq!(js::seam_text(&V::Obj(o.clone())), r#"{"a":1}"#);
    js::release(&V::Obj(o.clone()));
    assert!(inner.is_empty() && o.hidden("h").is_undef(), "풀기가 숨은 속성을 비우지 않았습니다");
}

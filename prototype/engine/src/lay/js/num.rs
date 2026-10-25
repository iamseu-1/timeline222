//! 수와 바꾸기의 JS 뜻: 수 글(`String(n)`) · `Number` · `String` · `parseInt` · `parseFloat` · 참거짓 · `||` · `??` · `+` ·
//! `Math.round` · `Math.max/min` · `| 0` · `>>> 0`. 모두 ECMAScript 규격(그리고 그것을 따르는 V8)의 뜻 그대로.
use super::text::Str;
use super::value::V;

/// JS의 빈칸(StrWhiteSpaceChar — `trim` · `Number` · `parseInt` · `parseFloat`가 버리는 글자): WhiteSpace(Zs 전부 · `﻿` 포함)와 줄 끝.
pub fn is_space(c: char) -> bool {
    matches!(c, '\u{9}' | '\u{a}' | '\u{b}' | '\u{c}' | '\u{d}' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200a}'
        | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}' | '\u{feff}')
}

/// JS `String(n)`(Number::toString, 기수 10) — 가장 짧게 되돌아오는 자릿수를 규격의 꼴로: 10⁻⁶ 이상 10²¹ 미만은 소수(`5` · `0.000001`),
/// 그 밖은 지수(`1e+21` · `5e-7` · `1.5e+300`). −0은 `"0"`. 자릿수는 Rust `{:e}`(가장 짧고 가장 가까운 자릿수 — V8과 같다)에서 뽑는다.
pub fn num_str(x: f64) -> String {
    if x.is_nan() { return "NaN".into(); }
    if x == 0.0 { return "0".into(); }
    if x.is_infinite() { return if x > 0.0 { "Infinity" } else { "-Infinity" }.into(); }
    if x < 0.0 { return format!("-{}", num_str(-x)); }
    let sci = format!("{x:e}");
    let (mant, exp) = sci.split_once('e').expect("{:e}에는 e가 있다");
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    let k = digits.len() as i32;
    let n = exp.parse::<i32>().expect("{:e}의 지수") + 1; // 소수점 자리: 값 = 0.digits × 10ⁿ
    if k <= n && n <= 21 {
        let mut s = digits;
        s.extend(std::iter::repeat('0').take((n - k) as usize));
        s
    } else if 0 < n && n <= 21 {
        format!("{}.{}", &digits[..n as usize], &digits[n as usize..])
    } else if -6 < n && n <= 0 {
        format!("0.{}{}", "0".repeat((-n) as usize), digits)
    } else {
        let e = n - 1;
        let sign = if e >= 0 { '+' } else { '-' };
        if k == 1 { format!("{digits}e{sign}{}", e.abs()) } else { format!("{}.{}e{sign}{}", &digits[..1], &digits[1..], e.abs()) }
    }
}

/// 기수 글자의 값(0 ~ 35) — 아니면 255.
fn digit(c: u8) -> u8 {
    match c {
        b'0'..=b'9' => c - b'0',
        b'a'..=b'z' => c - b'a' + 10,
        b'A'..=b'Z' => c - b'A' + 10,
        _ => 255,
    }
}
/// 기수 `r`의 자릿수 글(모두 맞는 글자)을 수로 — 128비트에 들면 정확히 올림, 넘으면 차례로 곱해 더한다(근사 — 쓰이는 곳 없음).
fn radix_value(digits: &[u8], r: u32) -> f64 {
    let mut exact: Option<u128> = Some(0);
    for &c in digits {
        exact = exact.and_then(|v| v.checked_mul(u128::from(r))).and_then(|v| v.checked_add(u128::from(digit(c))));
    }
    match exact {
        Some(v) => v as f64,
        None => digits.iter().fold(0.0, |v, &c| v * f64::from(r) + f64::from(digit(c))),
    }
}
/// 십진 글(StrDecimalLiteral — 부호 · 정수 · 소수 · 지수, Infinity는 뺌)으로 읽을 수 있는 가장 긴 앞자리의 바이트 수. 없으면 0.
fn decimal_prefix(t: &str) -> usize {
    let b = t.as_bytes();
    let digits_from = |mut i: usize| { let s = i; while i < b.len() && b[i].is_ascii_digit() { i += 1; } i - s };
    let mut i = usize::from(matches!(b.first(), Some(b'+' | b'-')));
    let whole = digits_from(i);
    i += whole;
    let mut frac = 0;
    if b.get(i) == Some(&b'.') {
        frac = digits_from(i + 1);
        if whole == 0 && frac == 0 { return 0; }
        i += 1 + frac;
    }
    if whole == 0 && frac == 0 { return 0; }
    if matches!(b.get(i), Some(b'e' | b'E')) {
        let mut j = i + 1;
        if matches!(b.get(j), Some(b'+' | b'-')) { j += 1; }
        let exp = digits_from(j);
        if exp > 0 { i = j + exp; }
    }
    i
}
/// 규격의 StringToNumber(`Number('…')`).
fn string_to_number(s: &str) -> f64 {
    let t = s.trim_matches(is_space);
    if t.is_empty() { return 0.0; }
    let b = t.as_bytes();
    if b.len() >= 2 && b[0] == b'0' {
        let r = match b[1] { b'x' | b'X' => 16, b'o' | b'O' => 8, b'b' | b'B' => 2, _ => 0 };
        if r != 0 {
            let body = &b[2..];
            if body.is_empty() || body.iter().any(|&c| u32::from(digit(c)) >= r) { return f64::NAN; }
            return radix_value(body, r);
        }
    }
    match t {
        "Infinity" | "+Infinity" => return f64::INFINITY,
        "-Infinity" => return f64::NEG_INFINITY,
        _ => {}
    }
    if decimal_prefix(t) == t.len() { t.parse::<f64>().unwrap_or(f64::NAN) } else { f64::NAN }
}

/// JS `Number(v)`(ToNumber): undefined → NaN · null → 0 · 참거짓 → 1/0 · 글은 규격의 글 읽기(빈 글 · 빈칸만 → 0, `0x` · `0o` · `0b`,
/// `Infinity`, 그 밖에 맞지 않으면 NaN) · 배열은 글로 바꾼 뒤(`[5]` → 5 · `[]` → 0) · 객체 · Map · Set → NaN.
pub fn to_num(v: &V) -> f64 {
    match v {
        V::Undef => f64::NAN,
        V::Null => 0.0,
        V::Bool(b) => f64::from(u8::from(*b)),
        V::Num(x) => *x,
        V::Str(s) => string_to_number(&s.as_str()),
        V::Arr(_) => string_to_number(&to_str(v).as_str()),
        V::Obj(_) | V::Map(_) | V::Set(_) => f64::NAN,
    }
}

/// JS `String(v)`(ToString): 수는 [`num_str`] · 배열은 `join(',')`(undefined · null은 빈 글 · 고리는 빈 글 — V8과 같다) ·
/// 객체 `[object Object]` · Map `[object Map]` · Set `[object Set]`.
pub fn to_str(v: &V) -> Str {
    let mut stack = Vec::new();
    str_of(v, &mut stack)
}
fn str_of(v: &V, stack: &mut Vec<usize>) -> Str {
    match v {
        V::Undef => Str::from("undefined"),
        V::Null => Str::from("null"),
        V::Bool(b) => Str::from(if *b { "true" } else { "false" }),
        V::Num(x) => Str::from(num_str(*x)),
        V::Str(s) => s.clone(),
        V::Arr(a) => {
            let id = super::value::ref_id(v).unwrap().1;
            if stack.contains(&id) { return Str::from(""); }
            stack.push(id);
            let items = a.to_vec();
            let mut parts = Vec::with_capacity(items.len());
            for x in &items { parts.push(if x.is_nullish() { Str::from("") } else { str_of(x, stack) }); }
            stack.pop();
            Str::join(&parts, ",")
        }
        V::Obj(_) => Str::from("[object Object]"),
        V::Map(_) => Str::from("[object Map]"),
        V::Set(_) => Str::from("[object Set]"),
    }
}

/// JS 참거짓(`!!v`): 0 · −0 · NaN · 빈 글 · null · undefined · false가 거짓.
pub fn truthy(v: &V) -> bool {
    match v {
        V::Undef | V::Null => false,
        V::Bool(b) => *b,
        V::Num(x) => *x != 0.0 && !x.is_nan(),
        V::Str(s) => !s.is_empty(),
        V::Arr(_) | V::Obj(_) | V::Map(_) | V::Set(_) => true,
    }
}
/// JS `a || b`(둘 다 이미 셈한 값 — 오른쪽을 아껴야 하면 `if truthy(&a)`로 직접).
pub fn or(a: V, b: V) -> V { if truthy(&a) { a } else { b } }
/// JS `a ?? b`.
pub fn nullish(a: V, b: V) -> V { if a.is_nullish() { b } else { a } }

/// JS `a + b`: 둘을 원시 값으로(배열은 글, 객체 · Map · Set은 `[object …]`) 바꾼 뒤 하나라도 글이면 잇고, 아니면 수로 더한다.
pub fn add(a: &V, b: &V) -> V {
    let prim = |v: &V| match v { V::Arr(_) | V::Obj(_) | V::Map(_) | V::Set(_) => V::Str(to_str(v)), other => other.clone() };
    let (pa, pb) = (prim(a), prim(b));
    if matches!(pa, V::Str(_)) || matches!(pb, V::Str(_)) { V::Str(to_str(&pa).concat(&to_str(&pb))) } else { V::Num(to_num(&pa) + to_num(&pb)) }
}

/// JS `Math.round(x)` — 가까운 정수, 꼭 가운데면 +∞ 쪽(−2.5 → −2). V8의 셈(올림한 값에서 0.5를 빼 견줌) 그대로라
/// 0.49999999999999994 → 0 · −0.3 → −0도 같다(`(x + 0.5).floor()`는 앞의 것에서 1이 된다).
pub fn round(x: f64) -> f64 {
    if !x.is_finite() || x == 0.0 { return x; }
    let up = x.ceil();
    if up - 0.5 <= x { up } else { up - 1.0 }
}
/// JS `Math.max(...xs)` — 빈 인자는 −Infinity · NaN이 하나라도 있으면 NaN · +0이 −0보다 크다.
pub fn max(xs: &[f64]) -> f64 {
    let mut m = f64::NEG_INFINITY;
    for &x in xs {
        if x.is_nan() { return f64::NAN; }
        if x > m || (x == 0.0 && m == 0.0 && m.is_sign_negative()) { m = x; }
    }
    m
}
/// JS `Math.min(...xs)` — 빈 인자는 Infinity · NaN이 하나라도 있으면 NaN · −0이 +0보다 작다.
pub fn min(xs: &[f64]) -> f64 {
    let mut m = f64::INFINITY;
    for &x in xs {
        if x.is_nan() { return f64::NAN; }
        if x < m || (x == 0.0 && m == 0.0 && x.is_sign_negative()) { m = x; }
    }
    m
}

/// 2³²로 나눈 나머지(0 이상) — NaN · ±Infinity는 0.
fn modulo32(x: f64) -> f64 { if x.is_finite() { x.trunc().rem_euclid(4_294_967_296.0) } else { 0.0 } }
/// JS `x | 0`(ToInt32) — 2³¹을 넘으면 감긴다.
pub fn to_i32(x: f64) -> i32 { modulo32(x) as u32 as i32 }
/// JS `x >>> 0`(ToUint32).
pub fn to_u32(x: f64) -> u32 { modulo32(x) as u32 }

/// JS `parseInt(v, radix)` — `radix` 0은 생략(10, `0x`면 16). 앞 빈칸 · 부호를 건너 맞는 자릿수까지만 읽는다(`'12a'` → 12 · 없으면 NaN).
/// 기수 10은 자릿수 글을 그대로 올림(V8과 같이 정확), 그 밖은 128비트에 들면 정확.
pub fn parse_int(v: &V, radix: i32) -> f64 {
    let s = to_str(v);
    let text = s.as_str();
    let mut t = text.trim_start_matches(is_space);
    let mut sign = 1.0;
    if let Some(rest) = t.strip_prefix('-') { sign = -1.0; t = rest; } else if let Some(rest) = t.strip_prefix('+') { t = rest; }
    let (mut r, mut strip) = (radix, true);
    if r != 0 {
        if !(2..=36).contains(&r) { return f64::NAN; }
        if r != 16 { strip = false; }
    } else {
        r = 10;
    }
    if strip { if let Some(rest) = t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")) { t = rest; r = 16; } }
    let r = r as u32;
    let end = t.bytes().position(|c| u32::from(digit(c)) >= r).unwrap_or(t.len());
    if end == 0 { return f64::NAN; }
    let digits = &t[..end];
    sign * if r == 10 { digits.parse::<f64>().unwrap_or(f64::NAN) } else { radix_value(digits.as_bytes(), r) }
}

/// JS `parseFloat(v)` — 앞 빈칸을 건너 십진 글로 읽을 수 있는 가장 긴 앞자리(`'1e3x'` → 1000 · `'1e'` → 1 · `'-0'` → −0 · 없으면 NaN).
pub fn parse_float(v: &V) -> f64 {
    let s = to_str(v);
    let text = s.as_str();
    let t = text.trim_start_matches(is_space);
    for (lit, val) in [("Infinity", f64::INFINITY), ("+Infinity", f64::INFINITY), ("-Infinity", f64::NEG_INFINITY)] {
        if t.starts_with(lit) { return val; }
    }
    match decimal_prefix(t) { 0 => f64::NAN, n => t[..n].parse::<f64>().unwrap_or(f64::NAN) }
}

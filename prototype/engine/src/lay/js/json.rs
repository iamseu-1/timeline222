//! JSON의 JS 뜻: [`parse`](`JSON.parse`) · [`stringify`](`JSON.stringify`) · 정답지 덤프 [`seam`] · [`seam_text`] · serde 다리 [`to_json`] · [`from_json`].
//! - `parse`는 재귀하지 않는다(그릇 쌓기를 힙에). 글의 `\uD800` 같은 외톨이 서로게이트도 그대로 담는다. 겹침은 [`MAX_DEPTH`](512)겹까지 — 넘으면 다른 읽기 오류처럼 중립인 글
//!   (`JSON.parse: 겹침이 512겹을 넘습니다 (바이트 N)` — 쉬운 글은 `lay/pack.rs`가 씌운다 · 판정 R64 · M3)로 Err
//!   (판정 R61 · 끝 전체 검토 ② M1: 상한이 없으면 수만 겹 `[[[[…`도 읽혀 뒤의 재귀(쓰기 · 덤프 · 다리 · drop)가 쌓기를 넘쳐 프로세스가 죽었다 — `catch_unwind`로도 못 잡음).
//! - `stringify` · 덤프 · 다리는 재귀한다. 깊은 V를 버릴 때(drop)도 재귀한다. `parse`가 낸 값은 512겹을 넘지 않으므로 모두 안전하다 — 정답지 파일의 가장 깊은 겹침은
//!   113(`lantern/prep.json` · 2026-10-22 잼)이고, 깊이 1,000을 검사로 지킨다(`tests/lay_js.rs` — 최적화 없는 빌드의 2MB 쌓기에서도 든다.
//!   2026-10-15에 2MB 쌓기에서 넘친 깊이: release 덤프 4,000 · 다리 1만, debug 다리 2,000).
//! - 덤프 규칙은 `prototype/scripts/oracle/seam.mjs` 14 ~ 62줄(SHA-256 5e7f7f6c2d84) 그대로: 같은 그래프를 같은 차례(깊이 우선 · JS 열쇠 차례)로
//!   돌아, 두 번째 만난 그릇은 `{"$ref":"<uid가 글이면 uid, 아니면 빈 글>#<처음 만난 경로>"}`.
use super::num::num_str;
use super::text::Str;
use super::value::{ref_id, Arr, Map, Obj, Set, V};
use serde_json::Value;
use std::collections::HashMap;
use std::fmt::Write as _;
use std::rc::Rc;

// ── JSON.parse ──

struct Reader<'a> { text: &'a str, b: &'a [u8], i: usize }

impl Reader<'_> {
    fn err(&self, what: &str) -> Box<dyn std::error::Error + Send + Sync> { format!("JSON.parse: {what} (바이트 {})", self.i).into() }
    /// JSON의 빈칸은 넷뿐(탭 · 줄 바꿈 · 캐리지 리턴 · 띄어쓰기).
    fn ws(&mut self) { while matches!(self.b.get(self.i), Some(b' ' | b'\t' | b'\n' | b'\r')) { self.i += 1; } }
    fn eat(&mut self, c: u8) -> bool { if self.b.get(self.i) == Some(&c) { self.i += 1; true } else { false } }
    fn lit(&mut self, word: &str) -> crate::Result<()> {
        if self.text[self.i..].starts_with(word) { self.i += word.len(); Ok(()) } else { Err(self.err("값이 와야 합니다")) }
    }
    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?` — 값은 Rust의 올바른 올림(JS와 같다).
    fn number(&mut self) -> crate::Result<f64> {
        let start = self.i;
        let digits = |r: &mut Self| { let s = r.i; while r.b.get(r.i).is_some_and(u8::is_ascii_digit) { r.i += 1; } r.i - s };
        self.eat(b'-');
        match self.b.get(self.i) {
            Some(b'0') => self.i += 1,
            Some(b'1'..=b'9') => { digits(self); }
            _ => return Err(self.err("수가 잘못됐습니다")),
        }
        if self.eat(b'.') && digits(self) == 0 { return Err(self.err("소수점 뒤에 숫자가 없습니다")); }
        if matches!(self.b.get(self.i), Some(b'e' | b'E')) {
            self.i += 1;
            if matches!(self.b.get(self.i), Some(b'+' | b'-')) { self.i += 1; }
            if digits(self) == 0 { return Err(self.err("지수에 숫자가 없습니다")); }
        }
        Ok(self.text[start..self.i].parse::<f64>().expect("문법을 확인한 수 글"))
    }
    fn hex4(&mut self) -> crate::Result<u16> {
        let h = self.text.get(self.i..self.i + 4).filter(|h| h.bytes().all(|c| c.is_ascii_hexdigit())).ok_or_else(|| self.err("\\u 뒤에 16진 넷이 와야 합니다"))?;
        self.i += 4;
        Ok(u16::from_str_radix(h, 16).expect("16진 넷"))
    }
    /// 따옴표 글 — 빠른 길(이스케이프 없음)은 그대로 자르고, 아니면 UTF-16 단위로 모은다(외톨이 서로게이트를 지키려고).
    fn string(&mut self) -> crate::Result<Str> {
        self.i += 1; // 여는 따옴표
        let start = self.i;
        while let Some(&c) = self.b.get(self.i) {
            match c {
                b'"' => { let s = Str::from(&self.text[start..self.i]); self.i += 1; return Ok(s); }
                b'\\' => break,
                0..=0x1f => return Err(self.err("글 안에 제어 글자가 있습니다")),
                _ => self.i += 1,
            }
        }
        let mut units: Vec<u16> = self.text[start..self.i].encode_utf16().collect();
        loop {
            let Some(&c) = self.b.get(self.i) else { return Err(self.err("글이 닫히지 않았습니다")) };
            match c {
                b'"' => { self.i += 1; return Ok(Str::from_units(&units)); }
                b'\\' => {
                    self.i += 1;
                    let e = self.b.get(self.i).copied().ok_or_else(|| self.err("이스케이프가 끊겼습니다"))?;
                    self.i += 1;
                    let unit = match e {
                        b'"' => 0x22, b'\\' => 0x5c, b'/' => 0x2f, b'b' => 0x08, b'f' => 0x0c, b'n' => 0x0a, b'r' => 0x0d, b't' => 0x09,
                        b'u' => self.hex4()?,
                        _ => { self.i -= 1; return Err(self.err("모르는 이스케이프")); }
                    };
                    units.push(unit);
                }
                0..=0x1f => return Err(self.err("글 안에 제어 글자가 있습니다")),
                _ => {
                    let ch = self.text[self.i..].chars().next().expect("글자 경계");
                    let mut buf = [0u16; 2];
                    units.extend_from_slice(ch.encode_utf16(&mut buf));
                    self.i += ch.len_utf8();
                }
            }
        }
    }
    /// 객체 열쇠(`"…"` 그리고 `:`). 열쇠는 `Rc<str>` — 외톨이 서로게이트는 U+FFFD로(열쇠에는 나오지 않는다).
    fn key(&mut self) -> crate::Result<Rc<str>> {
        if self.b.get(self.i) != Some(&b'"') { return Err(self.err("열쇠 글이 와야 합니다")); }
        let k = self.string()?.to_rc();
        self.ws();
        if !self.eat(b':') { return Err(self.err("열쇠 뒤에 ':'가 와야 합니다")); }
        Ok(k)
    }
}

/// 읽는 중인 그릇.
enum Frame { Arr(Vec<V>), Obj(Obj, Rc<str>) }

/// [`parse`]가 받는 겹침(객체 · 배열)의 상한 — 정답지 파일은 113겹까지(머리말). 넘으면 [`parse`]가 Err.
pub const MAX_DEPTH: usize = 512;

/// JS `JSON.parse(text)` — 맞지 않는 글이면 Err(JS의 SyntaxError). 같은 열쇠가 두 번이면 뒤 값 · 처음 자리(JS와 같다).
/// 재귀하지 않으므로 읽는 동안 쌓기가 넘치지 않고, 겹침이 [`MAX_DEPTH`]를 넘으면 그 자리에서 Err(뒤의 재귀가 안전한 깊이만 내보낸다 — 머리말).
/// Err 때 버려지는 반쯤 읽은 그릇들은 `stack`(힙의 Vec)에 나란히 있어 drop도 얕다.
pub fn parse(text: &str) -> crate::Result<V> {
    let mut r = Reader { text, b: text.as_bytes(), i: 0 };
    let mut stack: Vec<Frame> = Vec::new();
    'value: loop {
        r.ws();
        if matches!(r.b.get(r.i), Some(b'{' | b'[')) && stack.len() >= MAX_DEPTH {
            return Err(r.err(&format!("겹침이 {MAX_DEPTH}겹을 넘습니다"))); // 다른 읽기 오류처럼 중립 — 쉬운 글은 팩을 읽는 곳(`lay/pack.rs`)이 씌운다(판정 R64 · M3)
        }
        let mut v = match r.b.get(r.i) {
            Some(b'{') => {
                r.i += 1;
                r.ws();
                if r.eat(b'}') { V::Obj(Obj::new()) } else { let k = r.key()?; stack.push(Frame::Obj(Obj::new(), k)); continue 'value; }
            }
            Some(b'[') => {
                r.i += 1;
                r.ws();
                if r.eat(b']') { V::Arr(Arr::new(Vec::new())) } else { stack.push(Frame::Arr(Vec::new())); continue 'value; }
            }
            Some(b'"') => V::Str(r.string()?),
            Some(b't') => { r.lit("true")?; V::Bool(true) }
            Some(b'f') => { r.lit("false")?; V::Bool(false) }
            Some(b'n') => { r.lit("null")?; V::Null }
            Some(b'-' | b'0'..=b'9') => V::Num(r.number()?),
            _ => return Err(r.err("값이 와야 합니다")),
        };
        // 다 읽은 값을 위 그릇에 넣는다 — 그릇이 닫히면 그 그릇이 다시 '다 읽은 값'이 된다.
        loop {
            r.ws();
            match stack.last_mut() {
                None => return if r.i == r.b.len() { Ok(v) } else { Err(r.err("값 뒤에 글이 더 있습니다")) },
                Some(Frame::Arr(items)) => {
                    items.push(v);
                    if r.eat(b',') { continue 'value; }
                    if !r.eat(b']') { return Err(r.err("배열에 ',' 또는 ']'가 와야 합니다")); }
                    let Some(Frame::Arr(items)) = stack.pop() else { unreachable!() };
                    v = V::Arr(Arr::new(items));
                }
                Some(Frame::Obj(obj, key)) => {
                    obj.set(&*key, v);
                    if r.eat(b',') { r.ws(); *key = r.key()?; continue 'value; }
                    if !r.eat(b'}') { return Err(r.err("객체에 ',' 또는 '}'가 와야 합니다")); }
                    let Some(Frame::Obj(obj, _)) = stack.pop() else { unreachable!() };
                    v = V::Obj(obj);
                }
            }
        }
    }
}

// ── JSON.stringify ──

/// JSON 글의 따옴표 글(QuoteJSONString): `"` `\` `\b` `\f` `\n` `\r` `\t`, 그 밖의 제어 글자와 외톨이 서로게이트는 `\u` + 소문자 16진 넷. 나머지는 그대로.
fn quote(s: &Str, out: &mut String) {
    fn one(c: char, out: &mut String) {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => { let _ = write!(out, "\\u{:04x}", c as u32); }
            c => out.push(c),
        }
    }
    out.push('"');
    match s.exact() {
        Some(t) => t.chars().for_each(|c| one(c, out)),
        None => {
            for r in char::decode_utf16(s.units()) {
                match r { Ok(c) => one(c, out), Err(e) => { let _ = write!(out, "\\u{:04x}", e.unpaired_surrogate()); } }
            }
        }
    }
    out.push('"');
}

/// 고리 지킴 — 이미 쓰는 중인 그릇을 다시 만나면 JS는 TypeError를 던진다. 옮긴 코드에서는 잘못이므로 멈춘다.
fn enter(v: &V, stack: &mut Vec<usize>, who: &str) {
    let id = ref_id(v).expect("그릇").1;
    assert!(!stack.contains(&id), "{who}: 고리가 있는 값입니다(JS는 TypeError)");
    stack.push(id);
}

/// 값을 쓴다 — 빠지는 값(undefined)이면 false.
fn write_json(v: &V, out: &mut String, stack: &mut Vec<usize>) -> bool {
    match v {
        V::Undef => return false,
        V::Null => out.push_str("null"),
        V::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        V::Num(x) => if x.is_finite() { out.push_str(&num_str(*x)) } else { out.push_str("null") },
        V::Str(s) => quote(s, out),
        V::Arr(a) => {
            enter(v, stack, "JSON.stringify");
            out.push('[');
            for (i, x) in a.borrow().iter().enumerate() {
                if i > 0 { out.push(','); }
                if !write_json(x, out, stack) { out.push_str("null"); }
            }
            out.push(']');
            stack.pop();
        }
        V::Obj(o) => {
            enter(v, stack, "JSON.stringify");
            out.push('{');
            let mut first = true;
            o.each(|k, x| {
                let mark = out.len();
                if !first { out.push(','); }
                quote(&Str::from(k), out);
                out.push(':');
                if write_json(x, out, stack) { first = false; } else { out.truncate(mark); }
            });
            out.push('}');
            stack.pop();
        }
        V::Map(_) | V::Set(_) => out.push_str("{}"), // 제 속성이 없는 객체
    }
    true
}

/// JS `JSON.stringify(v)`(바꾸개 · 들여쓰기 없음): undefined 열쇠는 빠지고 배열 안 undefined는 null · NaN/±Infinity → null ·
/// 수 글은 [`num_str`] · 열쇠는 JS 차례 · Map/Set은 `{}`.
/// 맨 위가 undefined면 JS는 글이 아니라 undefined를 돌려준다 — 여기서는 멈춘다(부르기 전에 거른다). 고리도 멈춘다(JS는 TypeError).
pub fn stringify(v: &V) -> String {
    let mut out = String::new();
    let wrote = write_json(v, &mut out, &mut Vec::new());
    assert!(wrote, "JSON.stringify(undefined)는 글이 아닙니다(JS는 undefined) — 부르기 전에 거르세요");
    out
}

// ── serde 다리 ──

/// 수 하나를 serde 수로 — JSON.stringify와 같은 값(−0 → 0 · NaN/±Infinity → null). 정수면 정수 꼴(`5`), 아니면 f64(비트 그대로).
fn num_json(x: f64) -> Value {
    if !x.is_finite() { Value::Null }
    else if x == x.trunc() && x.abs() < 9_223_372_036_854_775_808.0 { Value::from(x as i64) }
    else { Value::from(x) }
}
fn json_of(v: &V, stack: &mut Vec<usize>) -> Option<Value> {
    Some(match v {
        V::Undef => return None,
        V::Null => Value::Null,
        V::Bool(b) => Value::Bool(*b),
        V::Num(x) => num_json(*x),
        V::Str(s) => Value::String(s.as_str().into_owned()),
        V::Arr(a) => {
            enter(v, stack, "to_json");
            let mut items = Vec::with_capacity(a.len());
            for x in a.borrow().iter() { items.push(json_of(x, stack).unwrap_or(Value::Null)); }
            stack.pop();
            Value::Array(items)
        }
        V::Obj(o) => {
            enter(v, stack, "to_json");
            let mut map = serde_json::Map::new();
            o.each(|k, x| { if let Some(j) = json_of(x, stack) { map.insert(k.to_string(), j); } });
            stack.pop();
            Value::Object(map)
        }
        V::Map(_) | V::Set(_) => Value::Object(serde_json::Map::new()),
    })
}
/// V → `serde_json::Value`(모듈 출력 `out`의 꼴) — `JSON.parse(JSON.stringify(v))`와 같은 값. 맨 위 undefined는 null.
/// serde 객체는 열쇠를 정렬해 담으므로 JS 열쇠 차례는 남지 않는다(견주기는 열쇠 차례를 보지 않는다 — 차례가 뜻인 글은 [`stringify`]로).
/// 외톨이 서로게이트가 든 글은 U+FFFD로 바뀐다(serde 글은 UTF-8).
pub fn to_json(v: &V) -> Value { json_of(v, &mut Vec::new()).unwrap_or(Value::Null) }

/// `serde_json::Value` → V(새 그릇들). 수는 비트 그대로(`float_roundtrip`으로 읽은 값), 객체 열쇠는 serde 차례(정렬)로 넣는다.
pub fn from_json(j: &Value) -> V {
    match j {
        Value::Null => V::Null,
        Value::Bool(b) => V::Bool(*b),
        Value::Number(n) => V::Num(n.as_f64().expect("serde 수는 f64로 읽힌다")),
        Value::String(s) => V::from(s.as_str()),
        Value::Array(items) => {
            let mut out = Vec::with_capacity(items.len());
            for x in items { out.push(from_json(x)); }
            V::Arr(Arr::new(out))
        }
        Value::Object(map) => {
            let o = Obj::new();
            for (k, x) in map { o.set(k.as_str(), from_json(x)); }
            V::Obj(o)
        }
    }
}

// ── 덤프(seam) ──

fn at(path: &str, seg: &str) -> String { if path.is_empty() { seg.to_string() } else { format!("{path}.{seg}") } }

/// 덤프 중에 이미 만난 그릇 → 처음 만난 경로.
type Seen = HashMap<(u8, usize), String>;

/// 덤프 규칙으로 고리 없는 새 값(나무)을 짓는다 — 빠지는 값(undefined)이면 None. 나무를 `stringify`하면 seam.mjs의 글과 바이트까지 같다.
/// 그릇마다 작은 함수로 나눠 한 층의 쌓기 몫을 줄였다(최적화 없는 빌드에서도 깊이 1,000이 2MB 쌓기에 든다).
fn dump(v: &V, path: &str, seen: &mut Seen) -> Option<V> {
    let id = match v {
        V::Undef => return None,
        V::Num(x) => return Some(if x.is_finite() { V::Num(*x) } else { V::Null }),
        V::Null | V::Bool(_) | V::Str(_) => return Some(v.clone()),
        _ => ref_id(v).expect("그릇"),
    };
    if let Some(first) = seen.get(&id) { return Some(dump_ref(v, first)); }
    seen.insert(id, path.to_string());
    Some(match v {
        V::Arr(a) => dump_arr(a, path, seen),
        V::Map(m) => dump_map(m, path, seen),
        V::Set(s) => dump_set(s, path, seen),
        V::Obj(o) => dump_obj(o, path, seen),
        _ => unreachable!("원시 값은 위에서 돌려줬다"),
    })
}
/// 두 번째 만남: `{"$ref":"<uid가 글이면 uid, 아니면 빈 글>#<처음 만난 경로>"}`.
fn dump_ref(v: &V, first: &str) -> V {
    let uid = match v { V::Obj(o) => o.str("uid").unwrap_or_default(), _ => Str::default() };
    let r = Obj::new();
    r.set("$ref", V::Str(uid.concat(&Str::from(format!("#{first}")))));
    V::Obj(r)
}
fn dump_arr(a: &Arr, path: &str, seen: &mut Seen) -> V {
    let items = a.to_vec();
    let mut out = Vec::with_capacity(items.len());
    for (i, x) in items.iter().enumerate() { out.push(dump(x, &at(path, &i.to_string()), seen).unwrap_or(V::Null)); }
    V::Arr(Arr::new(out))
}
/// Map은 `{"$map":[[열쇠, 값],…]}` — 칸의 경로는 `<경로>.$map.<순번>.0`(열쇠) · `.1`(값).
fn dump_map(m: &Map, path: &str, seen: &mut Seen) -> V {
    let base = at(path, "$map");
    let mut rows = Vec::new();
    for (i, (k, x)) in m.entries().iter().enumerate() {
        let p = at(&base, &i.to_string());
        let kk = dump(k, &at(&p, "0"), seen).unwrap_or(V::Null);
        let xx = dump(x, &at(&p, "1"), seen).unwrap_or(V::Null);
        rows.push(V::Arr(Arr::new(vec![kk, xx])));
    }
    let o = Obj::new();
    o.set("$map", V::Arr(Arr::new(rows)));
    V::Obj(o)
}
/// Set은 `{"$set":[…]}` — 칸의 경로는 `<경로>.$set.<순번>`.
fn dump_set(s: &Set, path: &str, seen: &mut Seen) -> V {
    let base = at(path, "$set");
    let mut items = Vec::new();
    for (i, x) in s.values().iter().enumerate() { items.push(dump(x, &at(&base, &i.to_string()), seen).unwrap_or(V::Null)); }
    let o = Obj::new();
    o.set("$set", V::Arr(Arr::new(items)));
    V::Obj(o)
}
/// 객체는 JS 열쇠 차례로 · undefined 값은 빠진다.
fn dump_obj(o: &Obj, path: &str, seen: &mut Seen) -> V {
    let out = Obj::new();
    for (k, x) in o.entries() {
        if let Some(d) = dump(&x, &at(path, &k.as_str()), seen) { out.set(&k, d); }
    }
    V::Obj(out)
}

/// 정답지의 덤프 규칙(`seam.mjs`의 `seam`)으로 적은 글 — Node가 낸 정답지 글과 바이트까지 같다.
pub fn seam_text(v: &V) -> String {
    match dump(v, "", &mut HashMap::new()) { Some(tree) => stringify(&tree), None => "null".into() }
}
/// 덤프 규칙으로 적은 값(정답지 `prep.json` · `rows.json`과 `lay::same::diff`로 견준다).
pub fn seam(v: &V) -> Value {
    match dump(v, "", &mut HashMap::new()) { Some(tree) => to_json(&tree), None => Value::Null }
}

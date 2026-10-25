//! JS 글 [`Str`] — 보이는 뜻은 JS와 같은 UTF-16 코드 단위의 열이다(`length` · `slice` · `charCodeAt` · `[i]` · `indexOf` · `<`).
//! 속은 거의 늘 UTF-8(`Rc<str>` — `&str`로 거저 빌려 줌)이고, 외톨이 서로게이트가 든 글(`'𠀀'.slice(1)`처럼 쌍이 갈린 것)만
//! UTF-16(`Rc<[u16]>`)으로 둔다. 같은 글은 늘 같은 꼴(외톨이가 없으면 UTF-8)이라 같음 · 해시는 꼴끼리만 견주면 된다.
use super::value::Key;
use std::borrow::Cow;
use std::cmp::Ordering;
use std::fmt;
use std::hash::{Hash, Hasher};
use std::rc::Rc;

/// JS 글 하나. 복사는 Rc 하나 늘리기.
#[derive(Clone)]
pub struct Str(Rep);

#[derive(Clone)]
enum Rep {
    /// 외톨이 서로게이트가 없는 글(거의 모두).
    U8(Rc<str>),
    /// 외톨이 서로게이트가 하나라도 있는 글.
    U16(Rc<[u16]>),
}

/// 글의 UTF-16 코드 단위를 차례로.
pub enum Units<'a> {
    U8(std::str::EncodeUtf16<'a>),
    U16(std::iter::Copied<std::slice::Iter<'a, u16>>),
}
impl Iterator for Units<'_> {
    type Item = u16;
    fn next(&mut self) -> Option<u16> {
        match self { Units::U8(i) => i.next(), Units::U16(i) => i.next() }
    }
}

/// JS `slice`의 자리 셈: ToIntegerOrInfinity(NaN → 0 · 소수는 버림) → 음수는 끝에서 셈 → 0 ~ len으로 자름.
fn rel_index(x: f64, len: usize) -> usize {
    let n = len as f64;
    let i = if x.is_nan() { 0.0 } else { x.trunc() };
    (if i < 0.0 { (n + i).max(0.0) } else { i.min(n) }) as usize
}

impl Str {
    /// UTF-16 코드 단위로 만든다 — 외톨이 서로게이트가 없으면 UTF-8 꼴로.
    pub fn from_units(units: &[u16]) -> Str {
        match String::from_utf16(units) {
            Ok(text) => Str(Rep::U8(Rc::from(text))),
            Err(_) => Str(Rep::U16(Rc::from(units))),
        }
    }
    /// UTF-16 코드 단위를 차례로.
    pub fn units(&self) -> Units<'_> {
        match &self.0 { Rep::U8(s) => Units::U8(s.encode_utf16()), Rep::U16(u) => Units::U16(u.iter().copied()) }
    }
    pub fn to_units(&self) -> Vec<u16> { self.units().collect() }
    /// 외톨이 서로게이트가 없으면 그 `&str`(거저 빌림). 있으면 None.
    pub fn exact(&self) -> Option<&str> {
        match &self.0 { Rep::U8(s) => Some(s), Rep::U16(_) => None }
    }
    /// `&str`로 — 외톨이 서로게이트는 U+FFFD로 바꾼다(그런 글만 새로 만듦). 뜻을 지켜야 하는 셈은 UTF-16 함수로.
    pub fn as_str(&self) -> Cow<'_, str> {
        match &self.0 { Rep::U8(s) => Cow::Borrowed(s), Rep::U16(u) => Cow::Owned(String::from_utf16_lossy(u)) }
    }
    /// 객체 열쇠로 쓸 `Rc<str>` — UTF-8 꼴이면 Rc를 나눠 가진다.
    pub fn to_rc(&self) -> Rc<str> {
        match &self.0 { Rep::U8(s) => s.clone(), Rep::U16(u) => Rc::from(String::from_utf16_lossy(u)) }
    }
    /// JS `s.length` — UTF-16 코드 단위 수(확장 한자는 2).
    pub fn len16(&self) -> usize {
        match &self.0 {
            Rep::U8(s) => if s.is_ascii() { s.len() } else { s.encode_utf16().count() },
            Rep::U16(u) => u.len(),
        }
    }
    pub fn is_empty(&self) -> bool {
        match &self.0 { Rep::U8(s) => s.is_empty(), Rep::U16(u) => u.is_empty() }
    }
    /// JS `s.charCodeAt(i)` — 범위 밖이면 NaN.
    pub fn code_at(&self, i: f64) -> f64 {
        let i = if i.is_nan() { 0.0 } else { i.trunc() };
        if i < 0.0 || i >= self.len16() as f64 { return f64::NAN; }
        self.units().nth(i as usize).map_or(f64::NAN, f64::from)
    }
    /// JS `s[i]` — 정수 자리(0 ~ length−1)면 코드 단위 하나의 글, 아니면 None(undefined).
    pub fn at16(&self, i: f64) -> Option<Str> {
        if i.fract() != 0.0 || i < 0.0 || !i.is_finite() || i >= self.len16() as f64 { return None; }
        self.units().nth(i as usize).map(|u| Str::from_units(&[u]))
    }
    /// JS `s.slice(start, end)` — 끝을 주지 않는 `s.slice(a)`는 `slice16(a, f64::INFINITY)`.
    pub fn slice16(&self, start: f64, end: f64) -> Str {
        let len = self.len16();
        let (from, to) = (rel_index(start, len), rel_index(end, len));
        if from >= to { return Str::from(""); }
        if let Rep::U8(s) = &self.0 {
            if s.is_ascii() { return Str::from(&s[from..to]); }
        }
        let units = self.to_units();
        Str::from_units(&units[from..to])
    }
    /// JS `s.indexOf(needle, from)` — 없으면 −1. 코드 단위로 찾으므로 외톨이 서로게이트로 쌍의 반쪽도 찾는다(JS와 같다).
    pub fn index_of16(&self, needle: &Str, from: f64) -> f64 {
        let hay = self.to_units();
        let pin = needle.to_units();
        let start = rel_index(from.max(0.0), hay.len()); // 음수 자리는 0(slice와 달리 끝에서 세지 않는다)
        if pin.is_empty() { return start as f64; }
        if pin.len() > hay.len() { return -1.0; }
        (start..=hay.len() - pin.len()).find(|&i| hay[i..i + pin.len()] == pin[..]).map_or(-1.0, |i| i as f64)
    }
    /// JS 글 비교(`<` · 비교 없는 `sort()`) — UTF-16 코드 단위 차례(코드 포인트 차례와 다르다: '𠀀' < 'ｚ').
    pub fn cmp16(&self, other: &Str) -> Ordering {
        if let (Rep::U8(a), Rep::U8(b)) = (&self.0, &other.0) {
            if a.is_ascii() && b.is_ascii() { return a.as_bytes().cmp(b.as_bytes()); }
        }
        self.units().cmp(other.units())
    }
    /// `[...s][0] || ''` — 글의 첫 코드 포인트(확장 한자는 코드 단위 둘 · 외톨이 서로게이트는 그 하나).
    /// (과제 Y — 줄 배정 `groupSpanCells`의 짧은 이름 · power · lens 모듈의 짧은 이름이 저마다 두던 같은 몸을 하나로.)
    pub fn first_code_point(&self) -> Str {
        let u = self.to_units();
        match u.first() {
            None => Str::default(),
            Some(&h) if (0xD800..0xDC00).contains(&h) && u.get(1).is_some_and(|l| (0xDC00..0xE000).contains(l)) => Str::from_units(&u[..2]),
            Some(_) => Str::from_units(&u[..1]),
        }
    }
    /// JS `a + b`(글 잇기) — 반쪽 둘이 만나면 쌍으로 붙는다.
    pub fn concat(&self, other: &Str) -> Str {
        match (&self.0, &other.0) {
            (Rep::U8(a), Rep::U8(b)) => {
                let mut s = String::with_capacity(a.len() + b.len());
                s.push_str(a);
                s.push_str(b);
                Str::from(s)
            }
            _ => {
                let mut u = self.to_units();
                u.extend(other.units());
                Str::from_units(&u)
            }
        }
    }
    /// JS `s.trim()` — 앞뒤의 JS 빈칸([`is_space`](super::is_space): Zs 전부 · 줄 끝 · `\u{FEFF}`)을 버린다. 외톨이 서로게이트는 빈칸이 아니다.
    pub fn trim(&self) -> Str {
        match &self.0 {
            Rep::U8(s) => {
                let t = s.trim_matches(super::is_space);
                if t.len() == s.len() { self.clone() } else { Str::from(t) }
            }
            Rep::U16(u) => {
                let space = |c: &u16| char::from_u32(u32::from(*c)).is_some_and(super::is_space);
                let from = u.iter().position(|c| !space(c)).unwrap_or(u.len());
                let to = u.iter().rposition(|c| !space(c)).map_or(from, |i| i + 1);
                Str::from_units(&u[from..to])
            }
        }
    }
    /// 여럿을 `sep`으로 잇는다(JS `Array.prototype.join`의 글 몫).
    pub fn join(parts: &[Str], sep: &str) -> Str {
        if let Some(all) = parts.iter().map(Str::exact).collect::<Option<Vec<&str>>>() { return Str::from(all.join(sep)); }
        let sep: Vec<u16> = sep.encode_utf16().collect();
        let mut u = Vec::new();
        for (i, p) in parts.iter().enumerate() {
            if i > 0 { u.extend_from_slice(&sep); }
            u.extend(p.units());
        }
        Str::from_units(&u)
    }
    /// 같은 글 덩이를 나눠 가지나(복사 없이 넘겼는지 보는 데만).
    pub fn ptr_eq(&self, other: &Str) -> bool {
        match (&self.0, &other.0) {
            (Rep::U8(a), Rep::U8(b)) => Rc::ptr_eq(a, b),
            (Rep::U16(a), Rep::U16(b)) => Rc::ptr_eq(a, b),
            _ => false,
        }
    }
}

impl Default for Str { fn default() -> Str { Str::from("") } }
impl From<&str> for Str { fn from(s: &str) -> Str { Str(Rep::U8(Rc::from(s))) } }
impl From<String> for Str { fn from(s: String) -> Str { Str(Rep::U8(Rc::from(s))) } }
impl From<Rc<str>> for Str { fn from(s: Rc<str>) -> Str { Str(Rep::U8(s)) } }
impl From<&String> for Str { fn from(s: &String) -> Str { Str::from(s.as_str()) } }

impl PartialEq for Str {
    fn eq(&self, other: &Str) -> bool {
        match (&self.0, &other.0) {
            (Rep::U8(a), Rep::U8(b)) => a == b,
            (Rep::U16(a), Rep::U16(b)) => a == b,
            _ => false, // 같은 글은 늘 같은 꼴
        }
    }
}
impl Eq for Str {}
impl PartialEq<str> for Str { fn eq(&self, other: &str) -> bool { self.exact() == Some(other) } }
impl PartialEq<&str> for Str { fn eq(&self, other: &&str) -> bool { self.exact() == Some(*other) } }
impl Hash for Str {
    fn hash<H: Hasher>(&self, h: &mut H) {
        match &self.0 { Rep::U8(s) => s.hash(h), Rep::U16(u) => u.hash(h) }
    }
}
impl PartialOrd for Str { fn partial_cmp(&self, other: &Str) -> Option<Ordering> { Some(self.cmp16(other)) } }
impl Ord for Str { fn cmp(&self, other: &Str) -> Ordering { self.cmp16(other) } }
impl fmt::Display for Str {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str(&self.as_str()) }
}
impl fmt::Debug for Str {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.0 { Rep::U8(s) => write!(f, "{s:?}"), Rep::U16(u) => write!(f, "utf16{u:x?}") }
    }
}

impl Key for Str {
    fn with_key<R>(&self, f: impl FnOnce(&str) -> R) -> R {
        match &self.0 { Rep::U8(s) => f(s), Rep::U16(_) => f(&self.as_str()) }
    }
    fn to_key(&self) -> Rc<str> { self.to_rc() }
}

//! JS 값 [`V`]와 그릇들(`Arr` · `Obj` · `Map` · `Set`). 그릇은 `Rc<RefCell<…>>` — 복사는 같은 객체를 하나 더 가리키기(JS의 대입과 같다).
//! - `Obj`: 정수 모양 열쇠(0 ~ 2³²−2의 표준 십진 글)는 오름차순으로 먼저, 나머지는 넣은 차례. 지우고 다시 넣으면 끝으로, 있는 열쇠에 쓰면 자리 그대로.
//! - `Map` · `Set`: 넣은 차례 · 열쇠 같음은 SameValueZero(NaN끼리 같음 · +0과 −0 같음 · 객체는 Rc 같음). −0 열쇠는 +0으로 둔다(JS와 같다).
//! - 배열의 구멍은 따로 두지 않고 `Undef`로 둔다(읽으면 같은 undefined · JSON에서도 같은 null).
use super::num::{num_str, to_num, truthy};
use super::text::Str;
use std::cell::{Ref, RefCell, RefMut};
use std::collections::HashMap;
use std::fmt;
use std::rc::Rc;

/// JS 값 하나.
#[derive(Clone, Default)]
pub enum V {
    #[default]
    Undef,
    Null,
    Bool(bool),
    Num(f64),
    Str(Str),
    Arr(Arr),
    Obj(Obj),
    Map(Map),
    Set(Set),
}

/// 객체 열쇠가 될 수 있는 것: `&str` · `String` · `Str` · `Rc<str>` · `f64`(JS `o[3]`처럼 수 글로 바뀜).
pub trait Key {
    /// 열쇠 글을 빌려 `f`에 준다.
    fn with_key<R>(&self, f: impl FnOnce(&str) -> R) -> R;
    /// 열쇠 글을 갖는다(새 열쇠를 넣을 때).
    fn to_key(&self) -> Rc<str>;
}
impl Key for str {
    fn with_key<R>(&self, f: impl FnOnce(&str) -> R) -> R { f(self) }
    fn to_key(&self) -> Rc<str> { Rc::from(self) }
}
impl Key for String {
    fn with_key<R>(&self, f: impl FnOnce(&str) -> R) -> R { f(self) }
    fn to_key(&self) -> Rc<str> { Rc::from(self.as_str()) }
}
impl Key for Rc<str> {
    fn with_key<R>(&self, f: impl FnOnce(&str) -> R) -> R { f(self) }
    fn to_key(&self) -> Rc<str> { self.clone() }
}
impl Key for f64 {
    fn with_key<R>(&self, f: impl FnOnce(&str) -> R) -> R { f(&num_str(*self)) }
    fn to_key(&self) -> Rc<str> { Rc::from(num_str(*self)) }
}

/// 정수 모양 열쇠(배열 자리 — "0" 또는 0으로 시작하지 않는 십진 글로 값 ≤ 2³²−2)면 그 값.
pub(crate) fn index_key(k: &str) -> Option<u32> {
    let b = k.as_bytes();
    if b.is_empty() || b.len() > 10 || !b.iter().all(u8::is_ascii_digit) || (b[0] == b'0' && b.len() > 1) { return None; }
    let n: u64 = k.parse().ok()?;
    if n <= 4_294_967_294 { Some(n as u32) } else { None }
}

// ── V ──

impl V {
    /// JS `v[k]` — 객체의 속성, 배열의 `length` · 자리, 글의 `length` · 자리. 그 밖은 undefined.
    pub fn get<K: Key + ?Sized>(&self, k: &K) -> V {
        match self {
            V::Obj(o) => o.get(k),
            V::Arr(a) => k.with_key(|s| {
                if s == "length" { V::Num(a.len() as f64) } else { index_key(s).map_or(V::Undef, |i| a.get(i as usize)) }
            }),
            V::Str(t) => k.with_key(|s| {
                if s == "length" { V::Num(t.len16() as f64) } else { index_key(s).and_then(|i| t.at16(i as f64)).map_or(V::Undef, V::Str) }
            }),
            _ => V::Undef,
        }
    }
    /// `Number(v[k])` — 산술(`-` `*` `/` `<`)에 쓰는 뜻(undefined → NaN · null → 0). `+`는 글이면 잇기이므로 [`add`](super::add).
    pub fn num<K: Key + ?Sized>(&self, k: &K) -> f64 { to_num(&self.get(k)) }
    /// `v[k]`가 글이면 그 글.
    pub fn str<K: Key + ?Sized>(&self, k: &K) -> Option<Str> { if let V::Str(s) = self.get(k) { Some(s) } else { None } }
    /// `v[k]`가 배열이면 그 배열.
    pub fn arr<K: Key + ?Sized>(&self, k: &K) -> Option<Arr> { if let V::Arr(a) = self.get(k) { Some(a) } else { None } }
    /// `v[k]`가 객체면 그 객체.
    pub fn obj<K: Key + ?Sized>(&self, k: &K) -> Option<Obj> { if let V::Obj(o) = self.get(k) { Some(o) } else { None } }
    /// `!!v[k]` — `if (v.k)`의 뜻.
    pub fn bool<K: Key + ?Sized>(&self, k: &K) -> bool { truthy(&self.get(k)) }

    pub fn as_num(&self) -> Option<f64> { if let V::Num(x) = self { Some(*x) } else { None } }
    pub fn as_bool(&self) -> Option<bool> { if let V::Bool(b) = self { Some(*b) } else { None } }
    pub fn as_str(&self) -> Option<&Str> { if let V::Str(s) = self { Some(s) } else { None } }
    pub fn as_arr(&self) -> Option<&Arr> { if let V::Arr(a) = self { Some(a) } else { None } }
    pub fn as_obj(&self) -> Option<&Obj> { if let V::Obj(o) = self { Some(o) } else { None } }
    pub fn as_map(&self) -> Option<&Map> { if let V::Map(m) = self { Some(m) } else { None } }
    pub fn as_set(&self) -> Option<&Set> { if let V::Set(s) = self { Some(s) } else { None } }
    pub fn is_undef(&self) -> bool { matches!(self, V::Undef) }
    pub fn is_null(&self) -> bool { matches!(self, V::Null) }
    /// `v == null`(undefined 또는 null).
    pub fn is_nullish(&self) -> bool { matches!(self, V::Undef | V::Null) }
}

impl From<f64> for V { fn from(x: f64) -> V { V::Num(x) } }
impl From<i32> for V { fn from(x: i32) -> V { V::Num(f64::from(x)) } }
impl From<u32> for V { fn from(x: u32) -> V { V::Num(f64::from(x)) } }
impl From<i64> for V { fn from(x: i64) -> V { V::Num(x as f64) } }
impl From<usize> for V { fn from(x: usize) -> V { V::Num(x as f64) } }
impl From<bool> for V { fn from(b: bool) -> V { V::Bool(b) } }
impl From<&str> for V { fn from(s: &str) -> V { V::Str(Str::from(s)) } }
impl From<String> for V { fn from(s: String) -> V { V::Str(Str::from(s)) } }
impl From<Str> for V { fn from(s: Str) -> V { V::Str(s) } }
impl From<Arr> for V { fn from(a: Arr) -> V { V::Arr(a) } }
impl From<Obj> for V { fn from(o: Obj) -> V { V::Obj(o) } }
impl From<Map> for V { fn from(m: Map) -> V { V::Map(m) } }
impl From<Set> for V { fn from(s: Set) -> V { V::Set(s) } }

/// 덤프 규칙(`seam_text`)으로 보인다 — 고리가 있어도 끝난다.
impl fmt::Debug for V {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str(&super::json::seam_text(self)) }
}

/// JS `a === b`: 수는 값(NaN ≠ NaN · +0 = −0) · 글은 내용 · 그릇은 같은 객체(Rc 같음).
pub fn strict_eq(a: &V, b: &V) -> bool {
    match (a, b) {
        (V::Undef, V::Undef) | (V::Null, V::Null) => true,
        (V::Bool(x), V::Bool(y)) => x == y,
        (V::Num(x), V::Num(y)) => x == y,
        (V::Str(x), V::Str(y)) => x == y,
        (V::Arr(x), V::Arr(y)) => x.ptr_eq(y),
        (V::Obj(x), V::Obj(y)) => x.ptr_eq(y),
        (V::Map(x), V::Map(y)) => x.ptr_eq(y),
        (V::Set(x), V::Set(y)) => x.ptr_eq(y),
        _ => false,
    }
}

/// JS `typeof v`.
pub fn type_of(v: &V) -> &'static str {
    match v {
        V::Undef => "undefined",
        V::Bool(_) => "boolean",
        V::Num(_) => "number",
        V::Str(_) => "string",
        V::Null | V::Arr(_) | V::Obj(_) | V::Map(_) | V::Set(_) => "object",
    }
}

/// 그릇의 같음 표지(덤프의 '이미 만남' · Map 열쇠) — 종류와 Rc 자리.
pub(crate) fn ref_id(v: &V) -> Option<(u8, usize)> {
    match v {
        V::Arr(a) => Some((0, Rc::as_ptr(&a.0) as *const () as usize)),
        V::Obj(o) => Some((1, Rc::as_ptr(&o.0) as *const () as usize)),
        V::Map(m) => Some((2, Rc::as_ptr(&m.0) as *const () as usize)),
        V::Set(s) => Some((3, Rc::as_ptr(&s.0) as *const () as usize)),
        _ => None,
    }
}

// ── Arr ──

/// JS 배열.
#[derive(Clone, Default)]
pub struct Arr(Rc<RefCell<Vec<V>>>);

impl Arr {
    pub fn new(items: Vec<V>) -> Arr { Arr(Rc::new(RefCell::new(items))) }
    pub fn len(&self) -> usize { self.0.borrow().len() }
    pub fn is_empty(&self) -> bool { self.0.borrow().is_empty() }
    /// `a[i]` — 범위 밖이면 undefined.
    pub fn get(&self, i: usize) -> V { self.0.borrow().get(i).cloned().unwrap_or_default() }
    /// `a[i] = v` — 길이를 넘으면 사이를 undefined(구멍)로 채운다.
    pub fn set(&self, i: usize, v: impl Into<V>) {
        let mut items = self.0.borrow_mut();
        if i >= items.len() { items.resize(i + 1, V::Undef); }
        items[i] = v.into();
    }
    pub fn push(&self, v: impl Into<V>) { self.0.borrow_mut().push(v.into()); }
    pub fn borrow(&self) -> Ref<'_, Vec<V>> { self.0.borrow() }
    pub fn borrow_mut(&self) -> RefMut<'_, Vec<V>> { self.0.borrow_mut() }
    /// 원소의 사본 목록(원소가 그릇이면 같은 그릇을 가리킨다 — `slice()`의 뜻).
    pub fn to_vec(&self) -> Vec<V> { self.0.borrow().clone() }
    pub fn ptr_eq(&self, other: &Arr) -> bool { Rc::ptr_eq(&self.0, &other.0) }
}

// ── Obj ──

/// JS 객체(평범한 객체만 — 프로토타입 · 접근자 · 기호 열쇠 없음).
#[derive(Clone, Default)]
pub struct Obj(Rc<RefCell<ObjData>>);

/// 이름 열쇠가 이만큼을 넘으면 찾기 색인을 만든다.
const INDEX_AT: usize = 12;

struct ObjData {
    /// 정수 모양 열쇠 — 오름차순.
    ints: Vec<(u32, V)>,
    /// 나머지 열쇠 — 넣은 차례(None은 지운 자리).
    named: Vec<Option<(Rc<str>, V)>>,
    /// 이름 열쇠 → `named` 자리(이름 열쇠가 많아지면 만든다).
    index: Option<HashMap<Rc<str>, usize>>,
    /// `named`의 지운 자리 수.
    holes: usize,
    /// 열거되지 않는 속성(JS `Object.defineProperty(o, k, { enumerable: false, … })` — 과제 6: `p.cellBounds` · `p.north` · `h.founderNode`).
    /// `Object.keys` · `Object.assign` · `JSON.stringify` · 덤프에 들지 않는다 — [`Obj::define_hidden`] · [`Obj::hidden`]으로만.
    hidden: Vec<(Rc<str>, V)>,
}

#[cfg(feature = "oracle")]
thread_local! {
    /// 살아 있는 객체 · Map · Set 그릇 수(과제 6 — [`super::release`]가 고리를 다 풀었는지 셀 길). 배열은 세지 않는다(고리는 늘 객체를 지난다).
    /// 검사 비계라 제품(`oracle` 기능 없음)에서는 세지 않는다 — 그릇을 짓고 버릴 때마다 스레드 칸을 건드리는 핫패스(판정 R69-7).
    static LIVE: std::cell::Cell<i64> = const { std::cell::Cell::new(0) };
}
#[cfg(feature = "oracle")]
#[inline]
fn live_add(n: i64) { LIVE.with(|c| c.set(c.get() + n)); }
#[cfg(not(feature = "oracle"))]
#[inline(always)]
fn live_add(_: i64) {}
/// 이 스레드에 살아 있는 객체 · Map · Set 그릇 수 — 버린 뒤 늘어 있으면 어딘가 고리가 남아 새는 것(`oracle` 기능 — 검사만 켠다).
#[cfg(feature = "oracle")]
pub fn live_containers() -> i64 { LIVE.with(std::cell::Cell::get) }

impl Default for ObjData {
    fn default() -> Self {
        live_add(1);
        ObjData { ints: Vec::new(), named: Vec::new(), index: None, holes: 0, hidden: Vec::new() }
    }
}
impl Drop for ObjData { fn drop(&mut self) { live_add(-1); } }

impl ObjData {
    fn find(&self, k: &str) -> Option<usize> {
        match &self.index {
            Some(ix) => ix.get(k).copied(),
            None => self.named.iter().position(|e| matches!(e, Some((key, _)) if &**key == k)),
        }
    }
    /// 열거되지 않는 속성의 자리.
    fn hidden_at(&self, k: &str) -> Option<usize> { self.hidden.iter().position(|e| &*e.0 == k) }
    /// `o[k]` — 보통 열쇠가 없으면 열거되지 않는 속성(JS는 둘 다 읽힌다).
    fn get(&self, k: &str) -> Option<&V> {
        let own = match index_key(k) {
            Some(i) => self.ints.binary_search_by_key(&i, |e| e.0).ok().map(|at| &self.ints[at].1),
            None => self.find(k).and_then(|at| self.named[at].as_ref().map(|e| &e.1)),
        };
        own.or_else(|| self.hidden_at(k).map(|at| &self.hidden[at].1))
    }
    /// `o[k] = v` — 열거되지 않는 속성이 있으면 그 값을 바꾼다(JS: 쓸 수 있는 속성은 열거되지 않은 채).
    fn set(&mut self, k: &str, make_key: impl FnOnce() -> Rc<str>, v: V) {
        if let Some(i) = index_key(k) {
            match self.ints.binary_search_by_key(&i, |e| e.0) {
                Ok(at) => self.ints[at].1 = v,
                Err(at) => match self.hidden_at(k) { Some(h) => self.hidden[h].1 = v, None => self.ints.insert(at, (i, v)) },
            }
            return;
        }
        if let Some(at) = self.find(k) {
            if let Some(e) = self.named[at].as_mut() { e.1 = v; }
            return;
        }
        if let Some(h) = self.hidden_at(k) { self.hidden[h].1 = v; return; }
        let key = make_key();
        if let Some(ix) = &mut self.index { ix.insert(key.clone(), self.named.len()); }
        self.named.push(Some((key, v)));
        if self.index.is_none() && self.named.len() - self.holes > INDEX_AT { self.reindex(); }
    }
    /// `delete o[k]` — 열거되지 않는 속성도 지운다(설정 가능한 속성).
    fn delete(&mut self, k: &str) -> bool {
        if let Some(i) = index_key(k) {
            return match self.ints.binary_search_by_key(&i, |e| e.0) { Ok(at) => { self.ints.remove(at); true } Err(_) => self.delete_hidden(k) };
        }
        let Some(at) = self.find(k) else { return self.delete_hidden(k) };
        self.named[at] = None;
        self.holes += 1;
        if let Some(ix) = &mut self.index { ix.remove(k); }
        if self.holes > 8 && self.holes * 2 > self.named.len() {
            self.named.retain(Option::is_some);
            self.holes = 0;
            if self.index.is_some() { self.reindex(); }
        }
        true
    }
    fn delete_hidden(&mut self, k: &str) -> bool {
        match self.hidden_at(k) { Some(h) => { self.hidden.remove(h); true } None => false }
    }
    fn reindex(&mut self) {
        let mut ix = HashMap::with_capacity(self.named.len());
        for (at, e) in self.named.iter().enumerate() {
            if let Some((key, _)) = e { ix.insert(key.clone(), at); }
        }
        self.index = Some(ix);
    }
    fn len(&self) -> usize { self.ints.len() + self.named.len() - self.holes }
    /// 열쇠 차례(JS `Object.keys`)대로 열쇠 글 · 값을 준다.
    fn each(&self, mut f: impl FnMut(&str, &V)) {
        for (i, v) in &self.ints { f(&i.to_string(), v); }
        for (k, v) in self.named.iter().flatten() { f(k, v); }
    }
}

impl Obj {
    pub fn new() -> Obj { Obj::default() }
    /// `o[k]` — 없으면 undefined.
    pub fn get<K: Key + ?Sized>(&self, k: &K) -> V {
        k.with_key(|s| self.0.borrow().get(s).cloned().unwrap_or_default())
    }
    /// `o[k] = v`.
    pub fn set<K: Key + ?Sized>(&self, k: &K, v: impl Into<V>) {
        let v = v.into();
        k.with_key(|s| self.0.borrow_mut().set(s, || k.to_key(), v));
    }
    /// `k in o`(값이 undefined여도 열쇠가 있으면 참).
    pub fn has<K: Key + ?Sized>(&self, k: &K) -> bool { k.with_key(|s| self.0.borrow().get(s).is_some()) }
    /// `delete o[k]` — 열쇠가 있었는지(JS의 delete는 늘 true를 돌려주지만 그 값을 쓰는 곳이 없어 더 쓸모 있는 뜻으로).
    pub fn delete<K: Key + ?Sized>(&self, k: &K) -> bool { k.with_key(|s| self.0.borrow_mut().delete(s)) }
    /// `Object.keys(o)` — 정수 모양 열쇠가 먼저(오름차순), 나머지는 넣은 차례.
    pub fn keys(&self) -> Vec<Str> {
        let d = self.0.borrow();
        let mut out = Vec::with_capacity(d.len());
        for (i, _) in &d.ints { out.push(Str::from(i.to_string())); }
        for (k, _) in d.named.iter().flatten() { out.push(Str::from(k.clone())); }
        out
    }
    /// `Object.values(o)`.
    pub fn values(&self) -> Vec<V> {
        let d = self.0.borrow();
        d.ints.iter().map(|e| e.1.clone()).chain(d.named.iter().flatten().map(|e| e.1.clone())).collect()
    }
    /// `Object.entries(o)`.
    pub fn entries(&self) -> Vec<(Str, V)> {
        let d = self.0.borrow();
        let mut out = Vec::with_capacity(d.len());
        for (i, v) in &d.ints { out.push((Str::from(i.to_string()), v.clone())); }
        for (k, v) in d.named.iter().flatten() { out.push((Str::from(k.clone()), v.clone())); }
        out
    }
    /// 열쇠 차례대로 빌려 본다(복사 없이 — 안에서 이 객체를 고치면 RefCell이 멈춘다).
    pub fn each(&self, f: impl FnMut(&str, &V)) { self.0.borrow().each(f) }
    /// `Object.defineProperty(o, k, { value: v, enumerable: false, writable: true, configurable: true })` — 열거되지 않는 속성(열쇠 차례 · 사본 · JSON · 덤프에 들지 않음).
    /// 같은 이름의 보통 열쇠가 있으면 그것을 숨김으로 바꾼다(JS는 그 자리에서 열거되지 않게 — 열쇠 차례 · 사본에서 빠짐).
    pub fn define_hidden<K: Key + ?Sized>(&self, k: &K, v: impl Into<V>) {
        let v = v.into();
        k.with_key(|s| {
            let mut d = self.0.borrow_mut();
            if let Some(h) = d.hidden_at(s) { d.hidden[h].1 = v; return; }
            let had = match index_key(s) {
                Some(i) => d.ints.binary_search_by_key(&i, |e| e.0).is_ok(),
                None => d.find(s).is_some(),
            };
            if had { d.delete(s); }
            d.hidden.push((k.to_key(), v));
        });
    }
    /// 열거되지 않는 속성만의 값(없으면 undefined — 보통 열쇠는 보지 않음. `get`은 둘 다 본다).
    pub fn hidden<K: Key + ?Sized>(&self, k: &K) -> V {
        k.with_key(|s| self.0.borrow().hidden.iter().find(|e| &*e.0 == s).map(|e| e.1.clone()).unwrap_or_default())
    }
    /// 속을 모두 비우고 값들을 돌려준다(`release` 몫).
    fn drain(&self) -> Vec<V> {
        let mut d = self.0.borrow_mut();
        let mut out: Vec<V> = std::mem::take(&mut d.ints).into_iter().map(|e| e.1).collect();
        out.extend(std::mem::take(&mut d.named).into_iter().flatten().map(|e| e.1));
        out.extend(std::mem::take(&mut d.hidden).into_iter().map(|e| e.1));
        d.index = None;
        d.holes = 0;
        out
    }
    pub fn len(&self) -> usize { self.0.borrow().len() }
    pub fn is_empty(&self) -> bool { self.len() == 0 }
    pub fn ptr_eq(&self, other: &Obj) -> bool { Rc::ptr_eq(&self.0, &other.0) }

    /// `Number(o[k])`(→ [`V::num`]).
    pub fn num<K: Key + ?Sized>(&self, k: &K) -> f64 { to_num(&self.get(k)) }
    pub fn str<K: Key + ?Sized>(&self, k: &K) -> Option<Str> { if let V::Str(s) = self.get(k) { Some(s) } else { None } }
    pub fn arr<K: Key + ?Sized>(&self, k: &K) -> Option<Arr> { if let V::Arr(a) = self.get(k) { Some(a) } else { None } }
    pub fn obj<K: Key + ?Sized>(&self, k: &K) -> Option<Obj> { if let V::Obj(o) = self.get(k) { Some(o) } else { None } }
    pub fn bool<K: Key + ?Sized>(&self, k: &K) -> bool { truthy(&self.get(k)) }
}

// ── Map · Set ──

/// SameValueZero로 같은 열쇠는 같은 표지.
#[derive(PartialEq, Eq, Hash)]
enum MKey {
    Undef,
    Null,
    Bool(bool),
    Num(u64),
    Str(Str),
    /// 그릇 종류와 Rc 자리 — 표가 열쇠 V를 쥐고 있는 동안만 쓰므로(지우면 색인에서도 뺌) 다른 그릇과 자리가 겹치지 않는다.
    Ref(u8, usize),
}

fn mkey(v: &V) -> MKey {
    match v {
        V::Undef => MKey::Undef,
        V::Null => MKey::Null,
        V::Bool(b) => MKey::Bool(*b),
        V::Num(x) => MKey::Num(if x.is_nan() { f64::NAN.to_bits() } else if *x == 0.0 { 0 } else { x.to_bits() }),
        V::Str(s) => MKey::Str(s.clone()),
        other => { let (t, p) = ref_id(other).unwrap(); MKey::Ref(t, p) }
    }
}
/// Map · Set은 −0 열쇠를 +0으로 둔다.
fn norm(v: V) -> V { if let V::Num(x) = v { if x == 0.0 { return V::Num(0.0); } } v }

/// 넣은 차례를 지키는 표(지운 자리는 None — 많아지면 당겨 붙인다).
struct Table<T> { rows: Vec<Option<(V, T)>>, index: HashMap<MKey, usize>, holes: usize }
impl<T: Clone> Default for Table<T> { fn default() -> Self { live_add(1); Table { rows: Vec::new(), index: HashMap::new(), holes: 0 } } }
impl<T> Drop for Table<T> { fn drop(&mut self) { live_add(-1); } }
impl<T: Clone> Table<T> {
    fn get(&self, k: &V) -> Option<&T> { self.index.get(&mkey(k)).and_then(|&at| self.rows[at].as_ref().map(|r| &r.1)) }
    fn set(&mut self, k: V, v: T) {
        let k = norm(k);
        let id = mkey(&k);
        if let Some(&at) = self.index.get(&id) {
            if let Some(r) = self.rows[at].as_mut() { r.1 = v; }
            return;
        }
        self.index.insert(id, self.rows.len());
        self.rows.push(Some((k, v)));
    }
    fn delete(&mut self, k: &V) -> bool {
        let Some(at) = self.index.remove(&mkey(k)) else { return false };
        self.rows[at] = None;
        self.holes += 1;
        if self.holes > 8 && self.holes * 2 > self.rows.len() {
            self.rows.retain(Option::is_some);
            self.holes = 0;
            self.index = self.rows.iter().enumerate().map(|(at, r)| (mkey(&r.as_ref().unwrap().0), at)).collect();
        }
        true
    }
    fn clear(&mut self) { *self = Table::default(); }
    fn len(&self) -> usize { self.rows.len() - self.holes }
    fn rows(&self) -> impl Iterator<Item = &(V, T)> { self.rows.iter().flatten() }
}

/// JS `Map`. 순회 함수(`keys` · `values` · `entries`)는 그 때의 사본을 준다(JS의 살아 있는 반복자와 달리 도는 중에 고쳐도 사본은 그대로).
#[derive(Clone, Default)]
pub struct Map(Rc<RefCell<Table<V>>>);

impl Map {
    pub fn new() -> Map { Map::default() }
    /// `m.get(k)` — 없으면 undefined.
    pub fn get(&self, k: &V) -> V { self.0.borrow().get(k).cloned().unwrap_or_default() }
    pub fn set(&self, k: impl Into<V>, v: impl Into<V>) { self.0.borrow_mut().set(k.into(), v.into()); }
    pub fn has(&self, k: &V) -> bool { self.0.borrow().get(k).is_some() }
    pub fn delete(&self, k: &V) -> bool { self.0.borrow_mut().delete(k) }
    pub fn clear(&self) { self.0.borrow_mut().clear(); }
    /// `m.size`.
    pub fn len(&self) -> usize { self.0.borrow().len() }
    pub fn is_empty(&self) -> bool { self.len() == 0 }
    pub fn keys(&self) -> Vec<V> { self.0.borrow().rows().map(|r| r.0.clone()).collect() }
    pub fn values(&self) -> Vec<V> { self.0.borrow().rows().map(|r| r.1.clone()).collect() }
    pub fn entries(&self) -> Vec<(V, V)> { self.0.borrow().rows().cloned().collect() }
    pub fn ptr_eq(&self, other: &Map) -> bool { Rc::ptr_eq(&self.0, &other.0) }
}

/// JS `Set`. `values`는 그 때의 사본.
#[derive(Clone, Default)]
pub struct Set(Rc<RefCell<Table<()>>>);

impl Set {
    pub fn new() -> Set { Set::default() }
    pub fn add(&self, v: impl Into<V>) { self.0.borrow_mut().set(v.into(), ()); }
    pub fn has(&self, v: &V) -> bool { self.0.borrow().get(v).is_some() }
    pub fn delete(&self, v: &V) -> bool { self.0.borrow_mut().delete(v) }
    pub fn clear(&self) { self.0.borrow_mut().clear(); }
    /// `s.size`.
    pub fn len(&self) -> usize { self.0.borrow().len() }
    pub fn is_empty(&self) -> bool { self.len() == 0 }
    pub fn values(&self) -> Vec<V> { self.0.borrow().rows().map(|r| r.0.clone()).collect() }
    pub fn ptr_eq(&self, other: &Set) -> bool { Rc::ptr_eq(&self.0, &other.0) }
}

// ── 풀기(과제 6 — 얹힌 몫 1) ──

impl Map {
    /// 속을 모두 비우고 열쇠 · 값을 돌려준다(`release` 몫).
    fn drain(&self) -> Vec<V> {
        let mut t = self.0.borrow_mut();
        t.index.clear();
        t.holes = 0;
        std::mem::take(&mut t.rows).into_iter().flatten().flat_map(|(k, v)| [k, v]).collect()
    }
}
impl Set {
    /// 속을 모두 비우고 원소를 돌려준다(`release` 몫).
    fn drain(&self) -> Vec<V> {
        let mut t = self.0.borrow_mut();
        t.index.clear();
        t.holes = 0;
        std::mem::take(&mut t.rows).into_iter().flatten().map(|(k, ())| k).collect()
    }
}
impl Arr {
    /// JS `a.sort(cmp)` — V8처럼 사본을 정렬해 되쓴다(비교가 같은 배열을 읽어도 빌림이 겹치지 않음 · 얹힌 몫 6). 비교의 뜻은 [`super::sort`].
    pub fn sort_js(&self, cmp: impl FnMut(&V, &V) -> f64) {
        let mut items = self.to_vec();
        super::sort::sort(&mut items, cmp);
        *self.0.borrow_mut() = items;
    }
}

/// JS `for (const x of v)`가 도는 것 — 배열은 원소 · 글은 코드 포인트(짝 맞는 서로게이트는 하나 · 외톨이는 그대로 하나) · Map은 `[열쇠, 값]` 배열 · Set은 원소.
/// 그 밖(undefined · null · 수 · 참거짓 · 보통 객체)은 순회되지 않아 JS는 TypeError — None(16b 넘겨받은 틀 손질: 배열만 받던 곳이 JS보다 넓게 거절하지 않게).
pub fn for_of(v: &V) -> Option<Vec<V>> {
    match v {
        V::Arr(a) => Some(a.to_vec()),
        V::Str(s) => {
            let units = s.to_units();
            let mut out = Vec::new();
            let mut i = 0;
            while i < units.len() {
                let pair = (0xD800..0xDC00).contains(&units[i]) && units.get(i + 1).is_some_and(|u| (0xDC00..0xE000).contains(u));
                let n = if pair { 2 } else { 1 };
                out.push(V::Str(Str::from_units(&units[i..i + n])));
                i += n;
            }
            Some(out)
        }
        V::Map(m) => Some(m.entries().into_iter().map(|(k, x)| V::Arr(Arr::new(vec![k, x]))).collect()),
        V::Set(s) => Some(s.values()),
        _ => None,
    }
}

/// 값 그래프를 반복으로 비운다 — `Rc<RefCell>` 고리(모델 · 연표 상태의 띠 ↔ 소속 ↔ 사람 …)는 버려도 풀리지 않고, 깊은 값의 drop은 재귀라서.
/// 닿는 그릇(배열 · 객체 · Map · Set — 열거되지 않는 속성까지)을 모두 비우므로, 이 그래프를 나눠 가진 다른 값도 비게 된다(다 쓴 뒤에만 부른다).
pub fn release(root: &V) {
    let mut work: Vec<V> = vec![root.clone()];
    while let Some(v) = work.pop() {
        let inner = match &v {
            V::Arr(a) => std::mem::take(&mut *a.0.borrow_mut()),
            V::Obj(o) => o.drain(),
            V::Map(m) => m.drain(),
            V::Set(s) => s.drain(),
            _ => continue,
        };
        work.extend(inner.into_iter().filter(|x| matches!(x, V::Arr(_) | V::Obj(_) | V::Map(_) | V::Set(_))));
    }
}

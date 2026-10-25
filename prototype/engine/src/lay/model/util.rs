//! 모델이 부르는 `HT.*` 도움 함수 가운데 읽기(`lay::read`)에 없던 것과, JS 식 하나의 뜻을 내는 작은 도움(옮긴 함수가 아님).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 120 ~ 129줄 `HT.DEFAULT_CATEGORIES` · `HT.POLITY_PALETTE`(→ [`DEFAULT_CATEGORY_DEFS`] · [`POLITY_PALETTE`])
//! - 131 ~ 168줄 `hex6` · `hexToRgb` · `rgbToHsl` · `hslToHex` · `HT.pastel`(값을 기억하는 `pastelCache`는 답이 같아 두지 않음)
//! - 178 ~ 182줄 `HT.certaintyOf`
//! - (2026-10-24 · `core.js` `f90a60d102ce`) 379 ~ 386줄 `HT.sphereOf` · `HT.isSphere` · `HT.sphereOrder`(→ [`is_sphere`] · [`sphere_order`] — 마지막 모델의 사전 대신 모델의 `sphereMap`을 받음) ·
//!   412 ~ 421줄 `HT.mergeSpheres`(→ [`merge_spheres`]). 옛 내장 표 `HT.SPHERES` · `HT.FANTASY_SPHERES`는 웹 코드에서 없어져 걷었다.
//! - 407 ~ 423줄 `HT.RELATIONS`의 자율성 · `hollow` · `HT.relationInfo` · `HT.relationOfKind`
//! - 432 ~ 443줄 `HT.kindOf` · `HT.itemKindOf`
//! - 567 ~ 577줄 `HT.leaderLabel`(기본 이름 꼴만 — 모델 · 사람 잇기가 쓰는 꼴)
//! - 1446줄 `HT.scopeRefText` · 1468 ~ 1474줄 `HT.UNC_KEYS` · `HT.uncOf` · 1478줄 `HT.altDated` · 1484줄 `HT.datedAlts`
//! - 1725줄 `vocabName` · 1913줄 `HT.groupTypeName` · 2500줄 `HT.kinName`
//! - 3247줄 `HT.atOf` · 3266줄 `HT.endIn`
//! - 3762줄 `FONT_FORMATS` · 3838 ~ 3841줄 `HT.fontFormat`
//! - 5081 ~ 5105줄 `HT.DOC_PREFIXES` · `docPrefixRe` · `cellKeyRe('head')` · 5108 ~ 5112줄 `HT.docKey.split` · `join` · 5127 ~ 5136줄 `HT.docKey.absolute`(→ [`doc_key_absolute`] — 정규식은 손으로)
//!
//! (과제 Y) 여기 있던 `HT.formatDate` · `HT.formatRange`(날짜 글을 `HT.cal.describe`로 적어야 하거나 인물이면 거절하던 판)는 걷었다 — 모델의 지도 장면 알림도
//! 모듈과 같은 [`crate::lay::web::when::format_range`](describe · figureRange까지 옮긴 판)를 부른다.
use crate::lay::js::{self, Arr, Obj, Str, V};
use crate::lay::read::{self, dates, groups, names, vocab, Ctx};
use std::cmp::Ordering;

// ── JS 식의 뜻(옮기는 규칙 표) ──

/// `!!v` · `Number(v)` · `a ?? b` · `a || b` · 배열 원소 사본 · JS `a < b` — 읽기 층(`read::alts`)의 하나를 다시 내보낸다(16b 검토 ③ Minor 8 — 같은 몸을 두 층에 두지 않게).
pub use crate::lay::read::alts::{list, lt, n, nn, or, tv};

/// 글 값.
pub fn s(x: &str) -> V { V::from(x) }
/// `a === b`.
pub fn eq(a: &V, b: &V) -> bool { js::strict_eq(a, b) }
/// `v === '글'`.
pub fn is(v: &V, text: &str) -> bool { matches!(v, V::Str(x) if x == text) }
/// 템플릿 글의 `${v}`(`String(v)`).
pub fn t(v: &V) -> String { js::to_str(v).as_str().into_owned() }
/// JS `a <= b`(원시 값): 둘 다 글이면 UTF-16 차례, 아니면 수(NaN이면 거짓).
pub fn le(a: &V, b: &V) -> bool {
    match (a, b) { (V::Str(x), V::Str(y)) => x.cmp16(y) != Ordering::Greater, _ => n(a) <= n(b) }
}
/// 새 배열 값.
pub fn arr(items: Vec<V>) -> V { V::Arr(Arr::new(items)) }
/// `Object.assign({}, v)`.
pub fn copy(v: &V) -> Obj { read::assign_copy(v) }
/// `Object.assign(target, v)`(v가 null · undefined면 건너뜀).
pub fn assign(target: &Obj, v: &V) { read::assign_into(target, v) }
/// `Object.assign(target, o)`(객체 하나).
pub fn assign_obj(target: &Obj, o: &Obj) { for (k, x) in o.entries() { target.set(&k, x); } }
/// 객체 값의 `Obj`. 객체가 아니면 JS(엄격 모드)라면 칸을 쓸 때 TypeError로 멈출 곳 — 잘못([`fault`])을 남기고 버릴 빈 객체를 돌려준다
/// (짓기를 마친 뒤 `build_model`이 잘못을 보고 오류로 끝낸다 — 조용히 쓰기가 사라지지 않게).
pub fn ob(v: &V) -> Obj {
    if let V::Obj(o) = v { return o.clone(); }
    fault(format!("객체가 아닌 값({})에 칸을 쓰려 했습니다", js::type_of(v)));
    Obj::new()
}
/// Map 값의 `Map`. Map이 아니면(JS라면 `.get` · `.has`에서 TypeError) 잘못을 남기고 빈 Map을 돌려준다.
pub fn mp(v: &V, what: &str) -> js::Map {
    if let V::Map(m) = v { return m.clone(); }
    fault(format!("{what}이(가) Map이 아닙니다({})", js::type_of(v)));
    js::Map::new()
}
thread_local! {
    /// 모델을 짓는 동안 처음 생긴 잘못(JS라면 던졌을 곳) — `build_model`이 끝에서 보고 오류로 바꾼다.
    static FAULT: std::cell::RefCell<Option<String>> = const { std::cell::RefCell::new(None) };
}
/// 잘못을 남긴다(처음 것만).
pub fn fault(msg: String) { FAULT.with(|f| { let mut f = f.borrow_mut(); if f.is_none() { *f = Some(msg); } }); }
/// 남은 잘못을 꺼낸다(비운다).
pub fn take_fault() -> Option<String> { FAULT.with(|f| f.borrow_mut().take()) }
/// `list.includes(x)`(=== — NaN은 SameValueZero지만 모델 목록에는 수가 없다).
pub fn has(list: &[V], x: &V) -> bool { list.iter().any(|y| eq(y, x)) }
/// `list.indexOf(x)`.
pub fn index_of(list: &[V], x: &V) -> f64 { list.iter().position(|y| eq(y, x)).map_or(-1.0, |i| i as f64) }
/// 정렬 비교의 `a - b`(수).
pub fn sub(a: &V, b: &V) -> f64 { n(a) - n(b) }
/// 비교 `||` 사슬: 앞이 0(또는 NaN)이 아니면 그것.
pub fn or_cmp(a: f64, b: impl FnOnce() -> f64) -> f64 { if a != 0.0 && !a.is_nan() { a } else { b() } }
/// JS 글 견줌 비교 `(a < b ? -1 : a > b ? 1 : 0)`.
pub fn cmp_str(a: &V, b: &V) -> f64 { if lt(a, b) { -1.0 } else if lt(b, a) { 1.0 } else { 0.0 } }

// ── 색 ──

/// `HT.DEFAULT_CATEGORIES`(id · 이름 · 색).
pub const DEFAULT_CATEGORY_DEFS: [(&str, &str, &str); 5] = [
    ("politics", "정치", "#abb3c9"), ("war", "전쟁", "#d4a39b"), ("diplomacy", "외교·교류", "#9dbea8"), ("society", "사회·경제", "#d7c18e"), ("culture", "문화·사상", "#bbacc8"),
];
/// `HT.POLITY_PALETTE` — 한 트랙 안에서 차례로 배정하는 띠 색.
pub const POLITY_PALETTE: [&str; 10] = ["#c8b193", "#9dbea8", "#abb3c9", "#bbacc8", "#dab195", "#b6c398", "#a0bcc5", "#a4b1b7", "#bba395", "#d1a9b9"];

fn rgb_to_hsl(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let max = js::max(&[r, g, b]);
    let min = js::min(&[r, g, b]);
    let l = (max + min) / 2.0;
    if max == min { return (0.0, 0.0, l); }
    let d = max - min;
    let s = if l > 0.5 { d / (2.0 - max - min) } else { d / (max + min) };
    let h = if max == r { (g - b) / d + if g < b { 6.0 } else { 0.0 } } else if max == g { (b - r) / d + 2.0 } else { (r - g) / d + 4.0 };
    (h / 6.0, s, l)
}
fn hsl_to_hex(h: f64, s: f64, l: f64) -> String {
    let f = |mut t: f64| -> f64 {
        if t < 0.0 { t += 1.0; }
        if t > 1.0 { t -= 1.0; }
        let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
        let p = 2.0 * l - q;
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t; }
        if t < 1.0 / 2.0 { return q; }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0; }
        p
    };
    let rgb = if s == 0.0 { [l, l, l] } else { [f(h + 1.0 / 3.0), f(h), f(h - 1.0 / 3.0)] };
    let mut out = String::from("#");
    for v in rgb { out.push_str(&format!("{:02x}", js::round(v * 255.0) as i64)); }
    out
}
/// `HT.pastel(c)` — 어떤 색이든 따스한 파스텔 범위(채도 14 ~ 46% · 밝기 66 ~ 74%)로. 글이 아니거나 `#rgb` · `#rrggbb`가 아니면 그대로.
pub fn pastel(c: &V) -> V {
    let V::Str(text) = c else { return c.clone() };
    let Some(raw) = text.exact() else { return c.clone() };
    let ok = raw.strip_prefix('#').is_some_and(|h| (h.len() == 3 || h.len() == 6) && h.bytes().all(|b| b.is_ascii_hexdigit()));
    if !ok { return c.clone(); }
    let key = raw.to_ascii_lowercase();
    if vocab::PALETTE.contains(&key.as_str()) { return V::from(key); }
    let hex: String = if key.len() == 4 { key[1..].chars().flat_map(|h| [h, h]).collect() } else { key[1..].to_string() };
    let ch = |i: usize| f64::from(u8::from_str_radix(&hex[i..i + 2], 16).expect("16진")) / 255.0;
    let (h, s, l) = rgb_to_hsl(ch(0), ch(2), ch(4));
    let out = if s < 0.06 { hsl_to_hex(h, 0.08, js::min(&[0.72, js::max(&[0.62, l])])) }
        else { hsl_to_hex(h, js::min(&[0.46, js::max(&[0.14, s * 0.6])]), js::min(&[0.74, js::max(&[0.66, l])])) };
    V::from(out)
}
/// `HT.autoColor(key)`(값).
pub fn auto_color(key: &V) -> V { V::from(read::misc::auto_color(key)) }

// ── 낱말 · 종류 ──

/// `HT.certaintyOf(x)` — 적힌 확실성(아는 id면) · 옛 칸 legendary면 'legend' · 아니면 'accepted'.
pub fn certainty_of(x: &V) -> V {
    let c = if tv(x) { x.get("certainty") } else { x.clone() };
    if vocab::CERTAINTY.iter().any(|(id, _)| is(&c, id)) { return c; }
    s(if tv(x) && x.bool("legendary") { "legend" } else { "accepted" })
}
/// `HT.mergeSpheres(packs)`(`core.js` `f90a60d102ce` 412 ~ 421줄 — 2026-10-23): 모델의 문화권 사전 — 켠 DLC들의 `spheres`를 차례대로, 같은 id는 먼저 놓인 DLC가 이긴다.
/// 차례는 적은 order, 비우면 1000부터 놓인 차례. 결과는 차례대로 `[{ id, name, order, packId, description? }]`(프로그램에 든 문화권은 없다).
pub fn merge_spheres(packs: &[V]) -> Vec<V> {
    let by_id = js::Map::new();
    let mut k = 0.0;
    for pack in packs {
        if !tv(pack) { continue; }
        for d in list(&pack.get("spheres")) {
            let id = if tv(&d) { d.get("id") } else { V::Undef };
            if !tv(&id) || by_id.has(&id) { continue; }
            let order = if d.get("order").is_nullish() { k += 1.0; V::Num(1000.0 + k - 1.0) } else { d.get("order") };
            let o = Obj::new();
            o.set("id", id.clone());
            o.set("name", or(d.get("name"), id.clone()));
            o.set("order", order);
            o.set("packId", pack.get("id"));
            if tv(&d.get("description")) { o.set("description", d.get("description")); }
            by_id.set(id, V::Obj(o));
        }
    }
    let mut out = by_id.values();
    js::sort(&mut out, |a, b| n(&a.get("order")) - n(&b.get("order")));
    out
}
/// `HT.isSphere(id)` — 모델의 사전(`sphereMap`)에 있는 문화권 id인가(`!!id && SPHERE_MAP.has(id)`).
pub fn is_sphere(map: &js::Map, id: &V) -> bool { tv(id) && map.has(id) }
/// `HT.sphereOrder(id)` — 문화권의 차례 값. 문화권이 없는 트랙(빈 글 · 사전에 없음)은 모든 문화권 뒤(Infinity).
pub fn sphere_order(map: &js::Map, id: &V) -> f64 {
    if !tv(id) { return f64::INFINITY; }
    let s = map.get(id);
    if tv(&s) { n(&s.get("order")) } else { f64::INFINITY }
}
/// `HT.relationInfo(id)`의 (자율성, hollow) — 종속 갈래 종류(군벌 빼고)는 그 종류의 자율성, '명목상'은 3, 구성국 · 동군연합은 hollow. 모르면 None.
pub fn relation_info(id: &V) -> Option<(Option<f64>, bool)> {
    let V::Str(x) = id else { return None };
    let r = vocab::RELATIONS.iter().find(|r| x == r.id)?;
    Some(match r.id {
        "nominal" => (Some(3.0), false),
        "member" | "union" => (None, true),
        k => (vocab::POLITY_KINDS.iter().find(|p| p.id == k).and_then(|p| p.autonomy).map(f64::from), false),
    })
}
/// `HT.relationOfKind(kind)` — 군벌은 '명목상', 종속 갈래 종류는 그 종류, 그 밖은 ''.
pub fn relation_of_kind(kind: &V) -> V {
    if is(kind, "warlord") { return s("nominal"); }
    match kind { V::Str(k) if vocab::kind_family(&k.as_str()) == "dependent" => kind.clone(), _ => s("") }
}
/// `HT.kindOf(x)` — `x.polityKind || x.kind`가 아는 종류(`HT.ALL_KINDS`)면 그것, 아니면 'state'.
pub fn kind_of(x: &V) -> V {
    let c = if tv(x) { or(x.get("polityKind"), x.get("kind")) } else { x.clone() };
    match &c { V::Str(k) if vocab::is_any_kind(&k.as_str()) => c, _ => s("state") }
}
/// `HT.itemKindOf(x)` — `x.itemKind`(적혀 있으면) · 아니면 kind · polityKind로 'event' · 'epoch' · 'organ' · 'culture' · 'dynasty' · 'period'.
pub fn item_kind_of(x: &V) -> V {
    let k = x.get("itemKind");
    if tv(&k) { return k; }
    let kind = x.get("kind");
    let pk = x.get("polityKind");
    s(if is(&kind, "event") { "event" } else if is(&kind, "epoch") { "epoch" } else if is(&pk, "overlay") { "organ" } else if is(&pk, "culture") { "culture" } else if is(&pk, "dynasty") { "dynasty" } else { "period" })
}
/// `vocabName(list)(id)` — 표에 있는 id면 그 이름, 아니면 ''.
fn vocab_name(table: &[(&str, &str)], id: &V) -> Str {
    Str::from(table.iter().find(|(k, _)| is(id, k)).map_or("", |(_, name)| name))
}
/// `HT.groupTypeName(t)` — 표에 있는 id면 이름, 자유 글이면 그 글(`String(t ?? '')`).
pub fn group_type_name(t: &V) -> Str {
    let name = vocab_name(&groups::GROUP_TYPES, t);
    if !name.is_empty() { name } else { js::to_str(&nn(t.clone(), s(""))) }
}
/// `HT.kinName(id)` — 자리 이음 관계의 이름(모르면 그 글).
pub fn kin_name(id: &V) -> Str {
    let name = vocab_name(&names::KIN_TYPES, id);
    if !name.is_empty() { name } else { js::to_str(&nn(id.clone(), s(""))) }
}
/// `HT.leaderLabel(c)`(기본 꼴 'auto' · 대수 없이) — `c.name || c.temple || c.title || c.given || ''`.
pub fn leader_label(c: &V) -> V {
    or(or(or(or(c.get("name"), c.get("temple")), c.get("title")), c.get("given")), s(""))
}
/// `HT.scopeRefText(r)` — "이름" 또는 "트랙:이름".
pub fn scope_ref_text(r: &read::cells::ScopeRef) -> Str {
    match &r.track { Some(tr) if !tr.is_empty() => Str::from(format!("{tr}:{}", r.polity)), _ => r.polity.clone() }
}
/// `HT.fontFormat(src)` — `data:font/(woff2|woff|ttf|otf);`의 CSS format() 이름(모르면 '').
pub fn font_format(src: &V) -> Str {
    const FORMATS: [(&str, &str); 4] = [("woff2", "woff2"), ("woff", "woff"), ("ttf", "truetype"), ("otf", "opentype")];
    let V::Str(x) = src else { return Str::default() };
    let text = x.as_str();
    let Some(rest) = text.strip_prefix("data:font/") else { return Str::default() };
    for (k, name) in FORMATS { if rest.strip_prefix(k).is_some_and(|r| r.starts_with(';')) { return Str::from(name); } }
    Str::default()
}

// ── 이설 · 날짜 ──

/// `HT.UNC_KEYS`.
pub const UNC_KEYS: [&str; 6] = ["certainty", "startRange", "startRangeAt", "endRange", "endRangeAt", "alternatives"];
/// `HT.uncOf(x)` — 적힌 확실성 · 연대 폭 · 이설만 담은 사본(값은 같은 것을 가리킴).
pub fn unc_of(x: &V) -> Obj {
    let o = Obj::new();
    if tv(x) { for k in UNC_KEYS { let v = x.get(k); if !v.is_nullish() { o.set(k, v); } } }
    o
}
/// `HT.altDated(a)` — 날짜가 적힌 이설인가(몸은 읽기 층 `read::alts` — 16b 층 손질).
pub use crate::lay::read::alts::alt_dated;
/// `HT.datedAlts(x)` — 시작이 있는 이설만.
pub fn dated_alts(x: &V) -> Vec<V> {
    let l = if tv(x) { x.get("alternatives") } else { V::Undef };
    list(&l).into_iter().filter(|a| tv(a) && !a.get("start").is_nullish() && n(&a.get("start")).is_finite()).collect()
}
/// `HT.atOf(x, key)` — key 칸의 날짜 글(없거나 값과 안 맞으면 null).
pub fn at_of(rc: &Ctx, x: &V, key: &str) -> V {
    if !tv(x) { return V::Null; }
    let at = x.get(&format!("{key}At"));
    if dates::at_fits(rc, &at, &x.get(key)) { at } else { V::Null }
}
/// `HT.endIn(p)` — 항목이 품는 마지막 순간(진행 중이면 오늘 · 연도만 적은 끝은 그해 끝까지).
pub fn end_in(rc: &Ctx, p: &V) -> V {
    if p.bool("ongoing") { p.get("endY") } else { dates::end_bound(rc, &p.get("endY"), &at_of(rc, p, "end")) }
}

// ── 문서 키 ──

/// `HT.DOC_PREFIXES`(차례 그대로 — 정규식 `^(people|track|…):(.+)$`).
const DOC_PREFIXES: [&str; 8] = ["people", "track", "category", "house", "view", "map", "surname", "place"];
fn line_end(c: u16) -> bool { matches!(c, 0x0A | 0x0D | 0x2028 | 0x2029) }
fn starts(u: &[u16], word: &str) -> bool { let w: Vec<u16> = word.encode_utf16().collect(); u.len() >= w.len() && u[..w.len()] == w[..] }
/// `docPrefixRe().test(base)` — 손으로: 접두어 + ':' + 비지 않고 줄 끝이 없는 나머지.
fn doc_prefixed(u: &[u16]) -> bool {
    if u.iter().any(|&c| line_end(c)) { return false; }
    DOC_PREFIXES.iter().any(|p| starts(u, p) && u.get(p.len()) == Some(&0x3A) && u.len() > p.len() + 1)
}
/// `base.match(cellKeyRe('head'))` — `^cell:(.+?):(leaders|…):(.+)$`(첫 덩이는 가장 짧게) → (uid, 종류, 나머지).
fn cell_key_head(u: &[u16]) -> Option<(Str, Str, Str)> {
    if !starts(u, "cell:") || u.iter().any(|&c| line_end(c)) { return None; }
    let body = &u[5..];
    for i in 1..body.len() {
        if body[i] != 0x3A { continue; }
        let after = &body[i + 1..];
        // 문서를 다는 칸 종류의 목록 열쇠(`HT.CELL_KINDS`에서 `doc !== false` — 지도자 · 내각 · 연호 · 도읍 · 시기, 지위는 뺌 — `model::kinds` 하나)
        for kind in super::kinds::CELL_KINDS.iter().filter(|k| k.doc).map(|k| k.list) {
            if starts(after, kind) && after.get(kind.len()) == Some(&0x3A) && after.len() > kind.len() + 1 {
                return Some((Str::from_units(&body[..i]), Str::from(kind), Str::from_units(&after[kind.len() + 1..])));
            }
        }
    }
    None
}
/// `HT.docKey.absolute(key, packId)` — DLC 안의 상대 키("korea-p1" · "cell:korea-p1:…")를 "DLC id/…" 절대 키로(하위 문서 "//이름"은 그대로).
pub fn doc_key_absolute(key: &Str, pack_id: &V) -> Str {
    let (base, sub) = read::docs::doc_key_split(key);
    let abs = |b: &Str| -> Str { if b.index_of16(&Str::from("/"), 0.0) >= 0.0 { b.clone() } else { Str::from(format!("{}/{b}", t(pack_id))) } };
    let u = base.to_units();
    let out = if doc_prefixed(&u) { base.clone() }
        else if let Some((uid, kind, rest)) = cell_key_head(&u) { Str::from(format!("cell:{}:{kind}:{rest}", abs(&uid))) }
        else { abs(&base) };
    if sub.is_empty() { out } else { Str::from(format!("{out}//{sub}")) }
}

//! 이설 — `js/core.js`(SHA-256 앞 12자 `9c786cf58566`)를 줄 그대로(과제 Y가 `web::alts`에 모은 몸을 16b 층 손질로 읽기 층에 둠):
//! - 1478줄 `HT.altDated` → [`alt_dated`] · 1621 ~ 1634줄 `HT.altSpan` → [`alt_span`] · 1638 ~ 1652줄 `altFlipSide` → [`alt_flip_side`] · 1658 ~ 1664줄 `HT.altFlipped` → [`alt_flipped`]
//!   (`HT.endBound`는 `read::dates::end_bound`)
//! - 이설 경계 `altEdges`(→ [`alt_edges`]) — `js/timeline.js`의 altEdges를 내보내기 모듈 셋(`strips.mjs` · `hangs.mjs` · `figures.mjs`)이 저마다 베껴 둔 같은 몸 ·
//!   칸에서 목록을 꺼내는 [`alts_of`](`(c && c.alternatives) || []`).
//!
//! 읽기(`read::cells`의 `altFlipSide`)가 부르므로 읽기 층에 둔다 — 예전엔 `read::cells` → `web::alts` → `model::util`로 층이 거꾸로 섰다. 이 파일은 `js` 층과
//! `read::dates`만 쓴다(JS 뜻의 작은 도움은 아래에 — `model::util`의 같은 이름과 같은 뜻). `web::alts`는 다시 내보내기만 · `model::util::alt_dated`도 이것.
//! 동작은 그대로(옮기기만 — lay 검사 같은 결과).
use super::dates::end_bound;
use super::Ctx;
use crate::lay::js::{self, Obj, V};
use std::cmp::Ordering;

/// 이설의 기본 열쇠(`keys = ['start', 'end']`).
pub const KEYS: [&str; 2] = ["start", "end"];

// ── JS 뜻의 작은 도움 — 하나만 둔다: 모델 층(`model::util`)은 이것을 다시 내보낸다(읽기 층이 모델 층을 부르지 않게 · 16b 검토 ③ Minor 8 — 예전엔 같은 몸 여섯을 베꼈다) ──
/// `!!v`.
pub fn tv(v: &V) -> bool { js::truthy(v) }
/// `Number(v)`.
pub fn n(v: &V) -> f64 { js::to_num(v) }
/// `a ?? b`.
pub fn nn(a: V, b: V) -> V { js::nullish(a, b) }
/// `a || b`.
pub fn or(a: V, b: V) -> V { js::or(a, b) }
/// 배열이면 그 원소의 사본, 아니면 빈 것.
pub fn list(v: &V) -> Vec<V> { if let V::Arr(a) = v { a.to_vec() } else { Vec::new() } }
/// JS `a < b`(원시 값): 둘 다 글이면 UTF-16 차례, 아니면 수(NaN이면 거짓).
pub fn lt(a: &V, b: &V) -> bool {
    match (a, b) { (V::Str(x), V::Str(y)) => x.cmp16(y) == Ordering::Less, _ => n(a) < n(b) }
}

/// `HT.altDated(a)` — 날짜가 적힌 이설인가.
pub fn alt_dated(a: &V) -> bool {
    tv(a) && (!a.get("start").is_nullish() || !a.get("end").is_nullish() || matches!(a.get("ongoing"), V::Bool(true)) || !a.get("birth").is_nullish() || !a.get("death").is_nullish())
}

/// `HT.altSpan(a, base, keys)`(1621 ~ 1634줄) — 이설의 채운 구간: 이설이 비운 쪽은 통설 값(base의 그 칸).
/// → `{ own: { 칸: 이설이 적었나 }, start, startAt, end, endAt, (startUnknown · endUnknown), ongoing }`.
pub fn alt_span(a: &V, base: &V, keys: &[&str]) -> Obj {
    let own_o = Obj::new();
    let o = Obj::new();
    o.set("own", own_o.clone());
    for &k in keys {
        let own = !a.get(k).is_nullish() || (k == "end" && matches!(a.get("ongoing"), V::Bool(true)));
        own_o.set(k, own);
        let src = if own { a } else { base };
        o.set(k, nn(src.get(k), V::Null));
        let at_key = format!("{k}At");
        let at = src.get(at_key.as_str());
        o.set(at_key.as_str(), if tv(&at) { at } else { V::Undef });
        let unk = format!("{k}Unknown");
        if (k == "start" || k == "end") && !own && base.bool(unk.as_str()) { o.set(unk.as_str(), true); }
    }
    let ongoing = matches!(a.get("ongoing"), V::Bool(true)) || (!own_o.bool("end") && base.bool("ongoing"));
    o.set("ongoing", ongoing);
    if ongoing { o.set("endAt", V::Undef); o.set("end", V::Undef); } // `o.end = o.endAt = undefined`(오른쪽부터)
    o
}

/// `altFlipSide(d, ongoing, base, keys)`(1638 ~ 1652줄) — 한쪽만 적은 이설의 빈 쪽을 통설 값으로 채우면 앞뒤가 뒤집히는가 → (이설이 적은 쪽, 통설로 채운 쪽).
/// `d`는 이설이 적은 날짜 칸 `{ 칸: { t, at } }`. 통설이 미정인 쪽(startUnknown …)으로 채우는 짝은 견주지 않는다.
pub fn alt_flip_side(rc: &Ctx, d: &Obj, ongoing: bool, base: &V, keys: &[&str]) -> Option<(&'static str, &'static str)> {
    for (x, y) in [("start", "end"), ("birth", "death")] {
        if !keys.contains(&x) { continue; }
        let own_x = d.bool(x);
        let own_y = d.bool(y) || (y == "end" && ongoing);
        if own_x == own_y { continue; } // 둘 다 적었으면(위에서 따로 봄) · 둘 다 비웠으면 견줄 것 없음
        if y == "end" && (ongoing || (!d.bool(y) && base.bool("ongoing"))) { continue; } // 현재까지 — 끝이 없음
        if base.bool(format!("{}Unknown", if own_x { y } else { x }).as_str()) { continue; } // 채우는 쪽이 미정
        let bx = if d.bool(x) { d.get(x).get("t") } else { base.get(x) };
        let by = if d.bool(y) { let dy = d.get(y); end_bound(rc, &dy.get("t"), &dy.get("at")) }
            else if base.get(y).is_nullish() { V::Null } else { end_bound(rc, &base.get(y), &base.get(format!("{y}At").as_str())) };
        if bx.is_nullish() || by.is_nullish() || !n(&bx).is_finite() || !n(&by).is_finite() { continue; }
        if lt(&by, &bx) { return Some(if own_x { (x, y) } else { (y, x) }); }
    }
    None
}

/// `HT.altFlipped(a, base, keys)`(1658 ~ 1664줄) — 읽은 이설 a를 통설 구간 base로 채우면 앞뒤가 뒤집히는가(뒤집힌 이설은 연표에 그리지 않는다).
pub fn alt_flipped(rc: &Ctx, a: &V, base: &V, keys: &[&str]) -> bool {
    if !alt_dated(a) { return false; }
    let d = Obj::new();
    for &k in keys {
        let v = a.get(k);
        if !v.is_nullish() && n(&v).is_finite() {
            let cell = Obj::new();
            cell.set("t", v);
            cell.set("at", or(a.get(format!("{k}At").as_str()), V::Null));
            d.set(k, cell);
        }
    }
    for (x, y) in [("start", "end"), ("birth", "death")] {
        let (dx, dy) = (d.get(x), d.get(y));
        if tv(&dx) && tv(&dy) && lt(&end_bound(rc, &dy.get("t"), &dy.get("at")), &dx.get("t")) { return true; }
    }
    alt_flip_side(rc, &d, matches!(a.get("ongoing"), V::Bool(true)), &or(base.clone(), V::Obj(Obj::new())), keys).is_some()
}

/// `(c && c.alternatives) || []` — 칸(항목)의 이설 목록(strips · hangs의 `altEdges`가 칸을 받을 때).
pub fn alts_of(c: &V) -> Vec<V> { list(&or(if tv(c) { c.get("alternatives") } else { c.clone() }, V::Arr(Default::default()))) }

/// `altEdges(HT, list, base, now)` — 이설이 말하는 경계 해 [(y, side)] — js/timeline.js의 altEdges 그대로(통설과 같은 해 · 뒤집힌 이설은 뺀다). side는 's' · 'e'.
/// 칸을 받는 사본(strips · hangs)은 [`alts_of`]로 목록을 꺼내 부른다.
pub fn alt_edges(rc: &Ctx, alts: &[V], base: &V, now: &V) -> Vec<(V, char)> {
    let mut out: Vec<(V, char)> = Vec::new();
    let push = |out: &mut Vec<(V, char)>, y: V, side: char| {
        if y.is_nullish() || !n(&y).is_finite() || out.iter().any(|q| (n(&q.0) - n(&y)).abs() < 1e-9) { return; }
        out.push((y, side));
    };
    for a in alts {
        if !alt_dated(a) || alt_flipped(rc, a, base, &KEYS) { continue; }
        let f = alt_span(a, base, &KEYS);
        let own = f.get("own");
        let fs = f.get("start");
        if own.bool("start") && !fs.is_nullish() && !base.get("start").is_nullish() && (n(&fs) - n(&base.get("start"))).abs() > 1e-9 { push(&mut out, fs, 's'); }
        let e = if f.bool("ongoing") { now.clone() } else { f.get("end") };
        if own.bool("end") && !e.is_nullish() && !base.get("end").is_nullish() && (n(&e) - n(&base.get("end"))).abs() > 1e-9 { push(&mut out, e, 'e'); }
    }
    out
}

//! 낱말 · 이름 — `js/core.js`(SHA-256 앞 12자 `9c786cf58566`)를 줄 그대로:
//! - 24줄 `HT.cmp16` → [`cmp16`]
//! - 188 ~ 194줄 `HT.HISTORICITY`(이름 · 딱지) · 203 ~ 206줄 `HT.historicityOf` → [`historicity_of`] · `HT.historicityName` → [`historicity_name`] · 208줄 `HT.historicityTag` →
//!   [`historicity_tag`](실재성 글 읽기 `HT.historicity`는 `read::vocab::historicity`)
//! - 244줄 `HT.successionName` · 246 ~ 260줄 `HT.SUCC_DEGREES` · `HT.succDegreeName` · 261 ~ 274줄 `HT.SUCC_PARTS`의 이름 · `HT.succPartName` · 306 ~ 310줄 `HT.succAbsorbs` ·
//!   312 ~ 317줄 `HT.successionLabel`
//! - 421줄 `HT.relationName` · 425 ~ 436줄 `HT.EXTRA_KINDS`의 이름 · `HT.kindName` · 438 ~ 444 · 11561줄 `HT.ITEM_WORDS`(단체 · 제도는 파일 끝 근처에서 더해짐) · `HT.itemWord`
//! - JS의 `obj[이름]`이 `Object.prototype`의 이름을 '있음'으로 읽는 뜻 → [`inherited`](docs · metro 모듈이 함께 씀)
//!
//! 모은 판(과제 Y)과 버린 판의 차이:
//! - `succAbsorbs`: 갈래 B(links)의 판 — JS `bs(p) < be(q) && be(p) > be(q)`를 관계 비교 뜻 그대로(둘 다 글이면 UTF-16 차례 — `model::util::lt`). 갈래 D(entities)의 판은
//!   늘 수로 바꿔 견줬다(두 값이 모두 글일 때만 갈림 — 모델의 해는 늘 수).
//! - `relationName`: JS처럼 모르면 ''(갈래 B는 `Option`으로 돌려 부르는 쪽이 ''로 바꿨다 — 같은 글).
//! - `kindName`: 갈래 C(docs)는 `String`을, B · D는 `&'static str`를 돌려줬다(같은 글) → `&'static str` 하나.
//! - `cmp16`: 갈래 C(docs)는 Rust 글(`&str`)을 받았다 — 같은 UTF-16 차례.
use crate::lay::js::{Str, V};
use crate::lay::model::util::{cmp_str, is, item_kind_of, lt, or, s, t, tv};
use crate::lay::read::vocab;
use crate::lay::rows::{band_end, band_start, items, join};

/// `HT.cmp16(a, b)`(24줄) — UTF-16 코드 단위 차례(`a < b ? -1 : a > b ? 1 : 0`).
pub fn cmp16(a: &V, b: &V) -> f64 { cmp_str(a, b) }

/// `Object.prototype`의 이름 — JS의 `obj[이름]`(제 열쇠가 없을 때)이 물려받은 값(함수 · 프로토타입)을 돌려주는 이름.
pub fn inherited(name: &str) -> bool {
    matches!(name, "constructor" | "__defineGetter__" | "__defineSetter__" | "hasOwnProperty" | "__lookupGetter__" | "__lookupSetter__" | "isPrototypeOf"
        | "propertyIsEnumerable" | "toString" | "valueOf" | "__proto__" | "toLocaleString")
}

// ── 실재성 ──

/// `HT.HISTORICITY`의 (id, 이름, 딱지 `tag` — 책갈피 탭의 작은 딱지 · 상세 배지 글) — 188 ~ 194줄 차례.
const HISTORICITY: [(&str, &str, &str); 5] = [
    ("attested", "실재", ""), ("semi", "반전설", "반전설"), ("legendary", "전설", "전설"), ("disputed", "실재 논쟁", "논쟁"), ("refuted", "부정됨", "부정"),
];
/// `HT.historicityOf(x)`(203 ~ 206줄) — 항목의 실재성 id. 실재(비움 · attested)면 ''.
pub fn historicity_of(x: &V) -> Str {
    let h = vocab::historicity(&if tv(x) { x.get("historicity") } else { x.clone() });
    if h == "attested" { Str::default() } else { h }
}
/// `HT.historicityName(id)`(207줄) — `id || 'attested'`의 이름(모르면 '실재').
pub fn historicity_name(id: &V) -> &'static str {
    let k = or(id.clone(), s("attested"));
    HISTORICITY.iter().find(|(h, _, _)| is(&k, h)).map_or(HISTORICITY[0].1, |x| x.1)
}
/// `HT.historicityTag(id)`(208줄) — 실재성의 딱지(모르면 '').
pub fn historicity_tag(id: &str) -> &'static str { HISTORICITY.iter().find(|(k, _, _)| *k == id).map_or("", |x| x.2) }

// ── 승계 ──

/// `HT.successionName(id)`(244줄) — 모르면 간접 승계(`HT.SUCCESSION[1]`).
pub fn succession_name(id: &V) -> &'static str {
    match id.as_str().and_then(|s| s.exact().map(str::to_owned)).as_deref() { Some("direct") => "직접 승계", Some("revival") => "부흥", Some("partial") => "부분 승계", _ => "간접 승계" }
}
/// `HT.succDegreeName(d)`(260줄) — 1 약 · 2 중 · 3 강(`===`라 수만), 아니면 '중'.
pub fn succ_degree_name(d: &V) -> &'static str {
    match d { V::Num(x) if *x == 1.0 => "약", V::Num(x) if *x == 3.0 => "강", _ => "중" }
}
/// `HT.SUCC_PARTS`의 (id, 이름).
const SUCC_PART_NAMES: [(&str, &str); 5] = [("elite", "지배층"), ("people", "백성"), ("land", "영역"), ("institutions", "제도"), ("culture", "문화")];
/// `HT.succPartName(id)`(274줄) — 모르면 그 값 그대로.
pub fn succ_part_name(id: &V) -> V { SUCC_PART_NAMES.iter().find(|(k, _)| is(id, k)).map_or(id.clone(), |x| s(x.1)) }
/// `HT.succAbsorbs(q, p)`(306 ~ 310줄) — 흡수(합류): 후대 p가 선대 q의 끝보다 먼저 있었고 q가 끝난 뒤에도 이어짐(띠의 바깥 끝 — `bandStart` · `bandEnd`로 봄).
pub fn succ_absorbs(q: &V, p: &V) -> bool {
    tv(q) && tv(p) && lt(&band_start(p), &band_end(q)) && lt(&band_end(q), &band_end(p))
}
/// `HT.successionLabel(e)`(312 ~ 317줄) — '부분 승계 · 정도 중 · 지배층 · 백성'(부분이 아니면 종류 이름만).
pub fn succession_label(e: &V) -> Str {
    let ty = or(if tv(e) { e.get("type") } else { e.clone() }, V::from("indirect"));
    if !is(&ty, "partial") { return Str::from(succession_name(&ty)); }
    let mut parts: Vec<V> = vec![V::from(succession_name(&ty)), V::from(format!("정도 {}", succ_degree_name(&or(e.get("degree"), V::Num(vocab::SUCC_DEGREE_DEFAULT)))))];
    parts.extend(items(&e.get("parts")).iter().map(succ_part_name));
    join(&parts, " · ")
}

// ── 관계 · 종류 ──

/// `HT.relationName(id)`(421줄) — `(HT.relationInfo(id) || { name: '' }).name`(모르면 '').
pub fn relation_name(id: &V) -> &'static str { vocab::RELATIONS.iter().find(|r| is(id, r.id)).map_or("", |r| r.name) }
/// `HT.EXTRA_KINDS`의 (id, 이름).
const EXTRA_KIND_NAMES: [(&str, &str); 3] = [("culture", "문화"), ("overlay", "기관"), ("dynasty", "왕조")];
/// `HT.kindName(id)`(436줄) — `HT.ALL_KINDS`(정권 종류 + 문화 · 기관 · 왕조)의 이름(모르면 `HT.POLITY_KINDS[0]` — 국가).
pub fn kind_name(id: &V) -> &'static str {
    if let Some(k) = vocab::POLITY_KINDS.iter().find(|k| is(id, k.id)) { return k.name; }
    if let Some((_, name)) = EXTRA_KIND_NAMES.iter().find(|(k, _)| is(id, k)) { return name; }
    vocab::POLITY_KINDS[0].name
}
/// `HT.itemWord(x)` — `HT.ITEM_WORDS[HT.itemKindOf(x)] || '항목'`(438 ~ 444줄 + 11561줄의 단체 · 제도).
pub fn item_word(x: &V) -> &'static str {
    match t(&item_kind_of(x)).as_str() {
        "period" => "시대", "event" => "사건", "organ" => "기관", "culture" => "문화", "dynasty" => "왕조", "epoch" => "시대 구분", "people" => "민족", "track" => "트랙",
        "category" => "분류", "cell" => "칸", "figure" => "인물", "house" => "가문", "treaty" => "조약", "scope" => "대범위", "group" => "단체", "institution" => "제도",
        _ => "항목",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lay::model::o;

    /// (갈래 A bands의 단위 검사를 옮겨 옴)
    #[test]
    fn historicity_follows_core_js() {
        let x = |h: &str| V::Obj(o! { "historicity" => h });
        assert_eq!(historicity_of(&x("attested")).as_str(), "");
        assert_eq!(historicity_of(&x("반전설")).as_str(), "semi");
        assert_eq!(historicity_tag("semi"), "반전설");
        assert_eq!(historicity_tag("disputed"), "논쟁");
        assert_eq!(historicity_tag("attested"), "");
        assert_eq!(historicity_name(&V::Null), "실재");
        assert_eq!(historicity_name(&V::from("refuted")), "부정됨");
    }
}

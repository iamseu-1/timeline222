//! 모듈 `entities`가 부르는 웹 함수(`HT.*` · `HT.cal.*`) 가운데 이미 옮겨진 것(`lay::read` · `lay::model::util` · `lay::model::bounds` · `lay::rows` · `lay::link`)에 없던 것 —
//! 줄 그대로(JS 함수 하나 = Rust 함수 하나). 사람 자리 · 계보 · 가문의 웹 함수는 `people.rs`.
//! 다른 모듈도 부르는 웹 함수(`HT.cellSpan` · `HT.cellToNow` · `HT.kindName` · `HT.historicityOf` · 승계의 이름 · `HT.relationName` · 글자 범위 …)는 과제 Y가
//! [`crate::lay::web`]에 모았다 — 이 파일은 그것을 다시 내보내기만 한다(entities의 다른 파일이 `super::web::…`로 부르게). 처음 옮긴 판은 이 파일에 있었다.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 27 ~ 66줄 `HT.groupDigits`(→ [`group_digits`] — 벡터 `js-vectors.json`의 `entities.groupDigits`) · 113 ~ 117줄 `HT.PASTEL`(→ `read::vocab::PALETTE` — 같은 차례)
//! - 183줄 `HT.certaintyName`
//! - 810줄 `HT.spanMeets`
//! - 1182 ~ 1185줄 `HT.phaseRangeText`
//! - 1730줄 `HT.treatyTypeName` · 1750줄 `HT.signersText` · 1914 ~ 1915줄 `HT.groupHowName` · `HT.lawActName`
//! - 2499 ~ 2515줄 `HT.nameKindName` · `HT.accessionHowName` · `HT.parentRoleName` · `LANG_NAMES` · `HT.langName`
//! - 2571 ~ 2577줄 `HT.namesSplit` · `HT.namesText` · 2751 ~ 2756줄 `HT.namesHead`
//! - 3236 ~ 3237줄 `HT.formatAxisYear`(`HT.yearOf`는 `read::dates::year_of` — JS 값 그대로 받는 하나)
//! (날짜 글 `HT.formatDate` · `formatWhen` · `formatRange` · `figureRange` · `cal.formatT` · `cal.describe`는 [`crate::lay::web::when`] — 처음 옮긴 판은 이 파일에 있었다.)
//!
//! 뜻 차이(알고 둠): `LANG_NAMES[t]`(물려받은 이름 — 'constructor' · 'toString' 같은 꼬리표에서 웹은 함수를 찾는다)는 적힌 꼬리표만 찾는다(과제 5a의 '물려받은 이름'과 같은 꼴).
use crate::lay::js::{self, Arr, Map, Str, V};
use crate::lay::model::util::{eq, is, list, nn, or, s, t, tv};
use crate::lay::read::{self, dates, groups, names, treaty, vocab};

// ── 모은 웹 함수(과제 Y — `lay::web`)를 다시 내보냄 ──
pub use crate::lay::web::cells::{cell_span, cell_to_now, CELL_KIND_IDS};
pub use crate::lay::web::glyphs::{glyph_missing, glyph_window};
pub use crate::lay::web::words::{historicity_name, historicity_of, kind_name, relation_name, succ_absorbs, succ_degree_name, succ_part_name};
pub use crate::lay::web::when::{format_date, format_range, format_t, format_when};
pub use crate::lay::read::dates::format_year;

/// 웹 함수가 읽는 전역(`HT.cal`의 표 · `HT.NOW_T` · `HT.CURRENT_YEAR`).
pub struct W<'a> { pub rc: &'a read::Ctx, pub now_t: f64, pub current_year: f64 }

// ── 수 글 ──

/// `HT.groupDigits(n)`(27 ~ 66줄) — `Number(n).toLocaleString('ko-KR')`과 같은 글: 정수부 세 자리마다 ',' · 소수는 최대 세 자리까지 반올림(짧은 10진 글 위에서 5 이상이면 올림 · 끝 0은 뺌) ·
/// 음수 '-' · -0은 '-0' · NaN은 'NaN' · 무한대는 '∞'.
pub fn group_digits(v: &V) -> String {
    let x = js::to_num(v);
    if x.is_nan() { return "NaN".into(); }
    let neg = x < 0.0 || (x == 0.0 && x.is_sign_negative());
    if x.is_infinite() { return if neg { "-∞".into() } else { "∞".into() }; }
    // Math.abs(x).toExponential() — 짧게 되돌릴 수 있는 유효숫자(JS 수 글과 같은 자릿수)
    let e = format!("{:e}", x.abs());
    let (m, ex) = e.split_once('e').expect("지수 꼴");
    let mut digits: Vec<u8> = m.bytes().filter(|b| *b != b'.').map(|b| b - b'0').collect();
    let mut point: i64 = ex.parse::<i64>().expect("지수") + 1; // 정수부 자릿수(0 이하면 소수점 바로 뒤에 0이 -point개)
    let keep = point + 3; // 남길 유효숫자 개수(소수 셋째 자리까지)
    if digits.len() as i64 > keep {
        if keep < 0 {
            digits = vec![0];
            point = 1;
        } else {
            let k = keep as usize;
            let up = digits[k] >= 5;
            digits.truncate(k);
            if up {
                let mut i = digits.len() as i64 - 1;
                while i >= 0 && digits[i as usize] == 9 { digits[i as usize] = 0; i -= 1; }
                if i >= 0 { digits[i as usize] += 1; } else { digits.insert(0, 1); point += 1; }
            }
        }
    }
    let joined: String = digits.iter().map(|d| char::from(b'0' + d)).collect();
    let (int, frac) = if point <= 0 {
        ("0".to_string(), "0".repeat((-point) as usize) + &joined)
    } else {
        let p = point as usize;
        let s = joined.clone() + &"0".repeat(p.saturating_sub(digits.len()));
        (s[..p].to_string(), s[p..].to_string())
    };
    let frac = frac.trim_end_matches('0');
    // int.replace(/\B(?=(\d{3})+$)/g, ',')
    let mut grouped = String::new();
    for (i, c) in int.chars().enumerate() {
        if i > 0 && (int.len() - i) % 3 == 0 { grouped.push(','); }
        grouped.push(c);
    }
    format!("{}{grouped}{}", if neg { "-" } else { "" }, if frac.is_empty() { String::new() } else { format!(".{frac}") })
}

/// `num.toFixed(1)` — 소수 첫째 자리(JS Number.prototype.toFixed — 정확한 10진 값에서 반올림, 반은 위로).
pub fn to_fixed1(x: f64) -> String {
    if !x.is_finite() { return js::num_str(x); }
    if x.abs() >= 1e21 { return js::num_str(x); }
    // toFixed: n = 정수 n이 n / 10 - x를 0에 가장 가깝게(둘이면 큰 n). f64의 정확한 10진 값으로 견줘야 해서 Rust의 정확한 반올림 서식으로(반은 짝이 아니라 큰 쪽).
    let neg = x < 0.0;
    let ax = x.abs();
    let exact = format!("{:.60}", ax); // f64는 유한 10진 전개 — 60자리면 반올림 판정에 넉넉
    let (ip, fp) = exact.split_once('.').expect("소수점");
    let mut digits: Vec<u8> = ip.bytes().map(|b| b - b'0').collect();
    digits.push(fp.as_bytes()[0] - b'0');
    let rest = &fp[1..];
    let up = rest.as_bytes()[0] >= b'5'; // 다음 자리가 5 이상이면 올림(정확히 반이어도 큰 쪽 — toFixed의 'larger n')
    if up {
        let mut i = digits.len() as i64 - 1;
        while i >= 0 && digits[i as usize] == 9 { digits[i as usize] = 0; i -= 1; }
        if i >= 0 { digits[i as usize] += 1; } else { digits.insert(0, 1); }
    }
    let l = digits.len();
    let int: String = digits[..l - 1].iter().map(|d| char::from(b'0' + d)).collect();
    let int = if int.is_empty() { "0".to_string() } else { int };
    let out = format!("{int}.{}", digits[l - 1]);
    if neg && out != "0.0" { format!("-{out}") } else if neg { "-0.0".to_string() } else { out }
}


// ── 낱말 ──

/// `HT.certaintyName(id)` — 모르면 ''.
pub fn certainty_name(id: &V) -> &'static str { vocab::CERTAINTY.iter().find(|(k, _)| is(id, k)).map_or("", |x| x.1) }
/// `vocabName(list)(id)` — 표의 이름(모르면 '').
fn vocab_name(list: &[(&str, &'static str)], id: &V) -> &'static str { list.iter().find(|(k, _)| is(id, k)).map_or("", |x| x.1) }
/// `vocabName(list)(id) || String(id ?? '')`.
fn vocab_or_text(list: &[(&str, &'static str)], id: &V) -> Str {
    let name = vocab_name(list, id);
    if name.is_empty() { js::to_str(&nn(id.clone(), s(""))) } else { Str::from(name) }
}
/// `HT.treatyTypeName(id)`.
pub fn treaty_type_name(id: &V) -> &'static str { vocab_name(&treaty::TREATY_TYPES, id) }
/// `HT.groupHowName(id)`.
pub fn group_how_name(id: &V) -> &'static str { vocab_name(&groups::GROUP_HOWS, id) }
/// `HT.lawActName(id)`.
pub fn law_act_name(id: &V) -> &'static str { vocab_name(&groups::LAW_ACTS, id) }
/// `HT.nameKindName(id)`.
pub fn name_kind_name(id: &V) -> Str { vocab_or_text(&names::NAME_KINDS, id) }
/// `HT.accessionHowName(id)`.
pub fn accession_how_name(id: &V) -> Str { vocab_or_text(&names::ACCESSION_HOWS, id) }
/// `HT.parentRoleName(id)`.
pub fn parent_role_name(id: &V) -> Str { vocab_or_text(&names::PARENT_ROLES, id) }
/// `HT.signersText(v)` — 서명자 목록 → "이름(직함); 이름(직함)".
pub fn signers_text(v: &V) -> String {
    treaty::read_signers(v).iter().map(|x| { let title = x.get("title"); if tv(&title) { format!("{}({})", t(&x.get("name")), t(&title)) } else { t(&x.get("name")) } }).collect::<Vec<_>>().join("; ")
}

/// `LANG_NAMES`(2508줄).
const LANG_NAMES: [(&str, &str); 24] = [
    ("ko", "한국어"), ("ja", "일본어"), ("zh", "중국어"), ("zh-Hant", "중국어 번체"), ("zh-Hans", "중국어 간체"), ("lzh", "한문"), ("en", "영어"), ("fr", "프랑스어"), ("de", "독일어"),
    ("la", "라틴어"), ("el", "그리스어"), ("grc", "고대 그리스어"), ("ar", "아랍어"), ("he", "히브리어"), ("fa", "페르시아어"), ("ru", "러시아어"), ("mn", "몽골어"), ("vi", "베트남어"),
    ("bo", "티베트어"), ("sa", "산스크리트어"), ("tr", "튀르키예어"), ("ko-Latn", "한국어 로마자"), ("ja-Latn", "일본어 로마자"), ("zh-Latn", "중국어 로마자"),
];
fn lang_of(k: &str) -> Option<&'static str> { LANG_NAMES.iter().find(|(id, _)| *id == k).map(|x| x.1) }
/// `HT.langName(tag)` — 언어 꼬리표의 이름(표에 없으면 앞 조각의 이름 + 꼬리표 · 가상 언어 x-는 꼬리표 그대로).
pub fn lang_name(tag: &V) -> Str {
    let tt = js::to_str(&nn(tag.clone(), s(""))).trim();
    if tt.is_empty() { return Str::default(); }
    let text = tt.as_str();
    if let Some(name) = lang_of(&text) { return Str::from(name); }
    let head = text.split('-').next().unwrap_or("");
    if head.eq_ignore_ascii_case("x") { return tt; }
    match lang_of(head) { Some(name) => Str::from(format!("{name} ({text})")), None => tt }
}

// ── 이름 목록 · 글자 범위 ──

/// `HT.namesSplit(list)` — (main = 원어 · 로마자 · 종류 없는 이름, other = 나머지).
pub fn names_split(l: &V) -> (Vec<V>, Vec<V>) {
    let all: Vec<V> = list(l).into_iter().filter(|x| tv(x) && tv(&x.get("text"))).collect();
    let main: Vec<V> = all.iter().filter(|x| { let k = x.get("kind"); !tv(&k) || is(&k, "native") || is(&k, "roman") }).cloned().collect();
    let other = all.iter().filter(|x| !main.iter().any(|y| eq(x, y))).cloned().collect();
    (main, other)
}
/// `HT.namesText(list)` — 이름 글을 빈칸으로 이은 것.
pub fn names_text(l: &V) -> String {
    list(l).iter().map(|x| if tv(x) { or(x.get("text"), s("")) } else { s("") }).filter(tv).map(|x| t(&x)).collect::<Vec<_>>().join(" ")
}
/// `HT.namesHead(list)` — (first = 첫 원어, second = 첫 로마자(없으면 현지음 → 한자음), rest = 나머지).
pub fn names_head(l: &V) -> (Option<V>, Option<V>, Vec<V>) {
    let all: Vec<V> = list(l).into_iter().filter(|x| tv(x) && tv(&x.get("text"))).collect();
    let find = |k: &str| all.iter().find(|x| is(&x.get("kind"), k)).cloned();
    let first = find("native");
    let second = find("roman").or_else(|| find("local")).or_else(|| find("sino"));
    let rest = all.iter().filter(|x| !first.as_ref().is_some_and(|f| eq(x, f)) && !second.as_ref().is_some_and(|f| eq(x, f))).cloned().collect();
    (first, second, rest)
}

/// `HT.spanMeets(a, b, lo, hi)` — 구간 [a, b)가 [lo, hi)에 걸치는가(폭 0인 쪽은 한 점).
pub fn span_meets(a: f64, b: f64, lo: f64, hi: f64) -> bool {
    if !(b > a) { return if hi > lo { lo <= a && a < hi } else { a == lo }; }
    if !(hi > lo) { return a <= lo && lo < b; }
    a < hi && lo < b
}

// ── 날짜 글 ──

/// `HT.formatAxisYear(y)` — "기원전 108" · "1592"(빈 값은 'NaN' — JS 그대로).
pub fn format_axis_year(y: &V) -> String {
    let k = dates::year_of(y);
    if k < 0.0 { format!("기원전 {}", js::num_str(-k)) } else { js::num_str(k) }
}
/// `HT.phaseRangeText(c, p)` — 시기 하나의 기간 글(진행 중인 정권의 끝까지 가는 시기는 끝이 '현재').
pub fn phase_range_text(w: &W, c: &V, p: &V) -> String {
    let side = |k: &str| -> String {
        if tv(&c.get(&format!("{k}Unknown"))) { "미정".into() }
        else if k == "end" && cell_to_now(c, p) { "현재".into() }
        else { format_date(w.rc, &c.get(k), &c.get(&format!("{k}At"))) }
    };
    format!("{} ~ {}", side("start"), side("end"))
}

// ── 작은 값 도움 ──

/// 새 배열 값(V).
pub fn va(items: Vec<V>) -> V { V::Arr(Arr::new(items)) }
/// Map 값의 `get`(Map이 아니면 undefined).
pub fn map_get(m: &V, k: &V) -> V { m.as_map().map_or(V::Undef, |m| m.get(k)) }
/// Map 값의 `has`.
pub fn map_has(m: &V, k: &V) -> bool { m.as_map().is_some_and(|m| m.has(k)) }
/// `model.X || new Map()`의 Map.
pub fn map_or_new(m: &V) -> Map { if let V::Map(x) = m { x.clone() } else { Map::new() } }

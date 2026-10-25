//! `js/core.js` 2436 ~ 2931줄 가운데 이름 목록 · 글자 범위 · 사람 잇기 · 좌표 읽기와 그것이 부르는 것 — 한 벌 P3 과제 5a(모아 보기 판의 `names`) · 5b(정권 · 칸의 사람 잇기) ·
//! 5c(글꼴의 글자 범위 · 단체의 구성원 · 지명의 좌표).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 2436 ~ 2443줄 `HT.NAME_KINDS` · 2489줄 `NAME_KIND_WORDS` · 2494줄 `HT.nameKind`(= `vocab(…)` — `read::cells::vocab`)
//! - (5b) 2444 ~ 2488줄 `HT.KIN_TYPES` · `HT.ACCESSION_HOWS` · `HT.PARENT_ROLES` · 2490 ~ 2492줄 `KIN_WORDS` · `HOW_WORDS` · `PARENT_WORDS` ·
//!   2495 ~ 2497줄 `HT.kinId` · `HT.accessionHow` · `HT.parentRole`
//! - (5b) 2504줄 `HT.isUnknownWho`(정규식은 `read::cells::unknown_word` — 1451줄과 같은 정규식)
//! - 2506줄 `HT.isLangTag`
//! - 2521 ~ 2569줄 `HT.readNames`
//! - (5c) 2676 ~ 2687줄 `HT.parseRange`(정규식은 손으로) · `HT.rangeText`(2579줄 '원어 표기 · 글자 범위 표 · 글꼴 팩' 절 — 글꼴 읽기 `read::info::read_fonts`가 부름)
//! - (5b) 2778 ~ 2805줄 `HT.readPersonRef`(정규식 `/^([^:@]+?)\s*:\s*([^@]+?)\s*(?:@\s*(.+))?$/`은 손으로 — `person_cell_text`) · 2807줄 `HT.personRefText`
//! - (5b) 2833 ~ 2854줄 `HT.readAccession` · 2856 ~ 2862줄 `readWho` · 2867 ~ 2892줄 `HT.readParents` · 2894 ~ 2924줄 `HT.readSpouses`
//! - (5c) 2810 ~ 2827줄 `HT.readGroupPeople`(쉼표 가름 `/[,，]/`은 코드 단위로) · 2926 ~ 2931줄 `HT.readCoords`(`/[,，\s]+/` 가름은 손으로)
//!
//! 옮기지 않은 것: `HT.langName` · `HT.namesSplit` · `HT.namesText` · `HT.namesHead` · `HT.bandOrig` · `HT.namesUi`(화면) · 글자 범위 표(`HT.GLYPH_BAND` … `HT.glyphTables` — 화면) ·
//! 보일 이름(`HT.kinName` …).
use super::{cells, dates, vocab, Ctx};
use crate::lay::js::{self, Obj, Str, V};

/// `HT.NAME_KINDS`(id, 이름).
pub const NAME_KINDS: [(&str, &str); 6] = [("native", "원어"), ("roman", "로마자"), ("sino", "한자음"), ("local", "현지음"), ("former", "옛 이름"), ("short", "약칭")];
/// `NAME_KIND_WORDS`.
const NAME_KIND_WORDS: [(&str, &str); 15] = [
    ("원문", "native"), ("원명", "native"), ("원어명", "native"), ("로마자표기", "roman"), ("라틴문자", "roman"), ("한자", "sino"), ("한자표기", "sino"), ("현지", "local"),
    ("현지어", "local"), ("옛이름", "former"), ("구명", "former"), ("옛국호", "former"), ("줄임말", "short"), ("줄임", "short"), ("약자", "short"),
];
/// `HT.KIN_TYPES`(자리 이음의 kin — 이 사람이 앞 지도자의 무엇인가).
pub const KIN_TYPES: [(&str, &str); 33] = [
    ("son", "아들"), ("daughter", "딸"), ("grandson", "손자"), ("granddaughter", "손녀"), ("younger-brother", "동생"), ("elder-brother", "형"), ("sister", "누이"), ("nephew", "조카"),
    ("uncle", "숙부"), ("cousin", "사촌"), ("son-in-law", "사위"), ("adopted", "양자"), ("maternal-grandson", "외손"), ("spouse", "배우자"), ("father", "아버지"), ("mother", "어머니"),
    ("collateral", "방계"), ("unrelated", "무관"), ("self", "본인"),
    // 세계사 확장(2026-10-23 · docs/점검-세계사-확장-전수조사.md 2-6) — js/core.js HT.KIN_TYPES와 같은 차례
    ("great-grandson", "증손"), ("great-granddaughter", "증손녀"), ("stepson", "의붓아들"), ("stepdaughter", "의붓딸"), ("half-brother", "이복형제"), ("half-sister", "이복누이"),
    ("wife-brother", "처남"), ("sister-husband", "매부"), ("father-in-law", "장인"), ("daughter-in-law", "며느리"), ("paternal-aunt", "고모"), ("maternal-aunt", "이모"),
    ("maternal-uncle", "외삼촌"), ("sororal-nephew", "외조카"),
];
/// `HT.ACCESSION_HOWS`(자리 이음의 how — 오른 방식).
pub const ACCESSION_HOWS: [(&str, &str); 18] = [
    ("hereditary", "세습"), ("abdication", "선양"), ("usurpation", "찬탈"), ("acclamation", "추대"), ("election", "선출"), ("conquest", "정복"), ("restoration", "복위"),
    ("regency", "섭정 뒤 오름"), ("coup", "정변"), ("investiture", "책봉"),
    // 세계사 확장(2026-10-23) — 혼인 · 임명 · 상속(세습과 가름) · 분할 상속 · 매입 · 윤번 · 공동 임명 · 제비
    ("marriage", "혼인"), ("appointment", "임명"), ("inheritance", "상속"), ("partition", "분할 상속"), ("purchase", "매입"), ("rotation", "윤번"), ("co-option", "공동 임명"), ("lot", "제비"),
];
/// `HT.PARENT_ROLES`(혈연의 as — 이 사람에게 who가 무엇인가).
pub const PARENT_ROLES: [(&str, &str); 7] = [
    ("father", "부"), ("mother", "모"), ("adoptive-father", "양부"), ("adoptive-mother", "양모"), ("birth-father", "생부"), ("birth-mother", "생모"), ("ancestor", "후손"),
];
/// `KIN_WORDS`.
const KIN_WORDS: [(&str, &str); 60] = [
    ("왕자", "son"), ("장남", "son"), ("차남", "son"), ("아드님", "son"), ("공주", "daughter"), ("손", "grandson"), ("아우", "younger-brother"), ("남동생", "younger-brother"),
    ("형님", "elder-brother"), ("오빠", "elder-brother"), ("누나", "sister"), ("언니", "sister"), ("여동생", "sister"), ("누이동생", "sister"), ("삼촌", "uncle"),
    ("작은아버지", "uncle"), ("큰아버지", "uncle"), ("종형제", "cousin"), ("부마", "son-in-law"), ("양아들", "adopted"), ("양녀", "adopted"), ("외손자", "maternal-grandson"),
    ("외손녀", "maternal-grandson"), ("아내", "spouse"), ("남편", "spouse"), ("왕비", "spouse"), ("부인", "spouse"), ("부왕", "father"), ("아비", "father"), ("모후", "mother"),
    ("어미", "mother"), ("먼친척", "collateral"), ("종친", "collateral"), ("남남", "unrelated"), ("혈연없음", "unrelated"), ("같은사람", "self"),
    // 세계사 확장(2026-10-23) — 생질은 누이의 아들이라 외조카로(예전엔 조카)
    ("증손자", "great-grandson"), ("증손녀", "great-granddaughter"), ("의붓자식", "stepson"), ("계자", "stepson"), ("의붓딸", "stepdaughter"), ("이복동생", "half-brother"),
    ("이복형", "half-brother"), ("배다른형제", "half-brother"), ("이복누이", "half-sister"), ("이복여동생", "half-sister"), ("처남", "wife-brother"), ("매제", "sister-husband"),
    ("형부", "sister-husband"), ("제부", "sister-husband"), ("장인어른", "father-in-law"), ("빙부", "father-in-law"), ("자부", "daughter-in-law"), ("고모님", "paternal-aunt"),
    ("이모님", "maternal-aunt"), ("외숙", "maternal-uncle"), ("외숙부", "maternal-uncle"), ("생질", "sororal-nephew"), ("생질녀", "sororal-nephew"), ("외조카딸", "sororal-nephew"),
];
/// `HOW_WORDS`.
const HOW_WORDS: [(&str, &str); 35] = [
    ("물려받음", "hereditary"), ("양위", "abdication"), ("선위", "abdication"), ("왕위찬탈", "usurpation"), ("옹립", "acclamation"), ("선거", "election"),
    ("침공", "conquest"), ("다시오름", "restoration"), ("섭정", "regency"), ("섭정뒤", "regency"), ("반정", "coup"), ("쿠데타", "coup"), ("봉작", "investiture"),
    // 세계사 확장(2026-10-23) — '상속'은 이제 제 id(inheritance)이고 세습의 다른 말이 아니다
    ("결혼", "marriage"), ("혼인상속", "marriage"), ("아내의권리", "marriage"), ("임명됨", "appointment"), ("지명", "appointment"), ("파견", "appointment"), ("서임", "appointment"),
    ("상속받음", "inheritance"), ("유산상속", "inheritance"), ("분할", "partition"), ("분봉", "partition"), ("구입", "purchase"), ("사들임", "purchase"), ("순번", "rotation"),
    ("돌아가며", "rotation"), ("타니스트리", "rotation"), ("측면승계", "rotation"), ("공동황제", "co-option"), ("공동통치자지명", "co-option"), ("생전대관", "co-option"), ("추첨", "lot"), ("제비뽑기", "lot"),
];
/// `PARENT_WORDS`.
const PARENT_WORDS: [(&str, &str); 13] = [
    ("아버지", "father"), ("부친", "father"), ("어머니", "mother"), ("모친", "mother"), ("양아버지", "adoptive-father"), ("양어머니", "adoptive-mother"), ("친부", "birth-father"),
    ("친아버지", "birth-father"), ("친모", "birth-mother"), ("친어머니", "birth-mother"), ("조상", "ancestor"), ("선조", "ancestor"), ("몇대손", "ancestor"),
];
/// `HT.nameKind(v)` — 이름의 종류: id나 한국어 → id(모르면 '').
pub fn name_kind(v: &V) -> Str { cells::vocab(&NAME_KINDS, &NAME_KIND_WORDS, v) }
/// `HT.kinId(v)` — 자리 이음의 관계: id나 한국어 → id(모르면 '').
pub fn kin_id(v: &V) -> Str { cells::vocab(&KIN_TYPES, &KIN_WORDS, v) }
/// `HT.accessionHow(v)` — 오른 방식: id나 한국어 → id(모르면 '').
pub fn accession_how(v: &V) -> Str { cells::vocab(&ACCESSION_HOWS, &HOW_WORDS, v) }
/// `HT.parentRole(v)` — 혈연의 as: id나 한국어 → id(모르면 '').
pub fn parent_role(v: &V) -> Str { cells::vocab(&PARENT_ROLES, &PARENT_WORDS, v) }
/// `HT.isUnknownWho(v)` — "미상"(모름 · 불명 · ? · 미정)인 글인가(비움과 구별해 …Unknown: true로 남긴다).
pub fn is_unknown_who(v: &V) -> bool { if let V::Str(s) = v { cells::unknown_word(&s.trim()) } else { false } }

/// `HT.isLangTag(s)` — `/^(?:[a-z]{2,8}(?:-[a-z0-9]{1,8})*|x(?:-[a-z0-9]{1,8})+)$/i`(글만). `i`는 ASCII 글자만 접는다.
/// '-'로 나눈 조각이 모두 비지 않아야 하고, 첫 조각이 글자 2 ~ 8자(뒤 조각은 글자 · 숫자 1 ~ 8자)이거나 'x' 뒤에 조각이 하나 이상.
pub fn is_lang_tag(s: &V) -> bool {
    let V::Str(t) = s else { return false };
    let t = t.trim();
    let Some(text) = t.exact() else { return false };
    let segs: Vec<&str> = text.split('-').collect();
    let alnum = |g: &str| (1..=8).contains(&g.len()) && g.bytes().all(|b| b.is_ascii_alphanumeric());
    let tail_ok = segs[1..].iter().all(|g| alnum(g));
    let first = segs[0];
    let lang = (2..=8).contains(&first.len()) && first.bytes().all(|b| b.is_ascii_alphabetic()) && tail_ok;
    let private = first.eq_ignore_ascii_case("x") && segs.len() > 1 && tail_ok;
    lang || private
}

/// `HT.readNames(v, warn)` — 이름 목록 원문 → 깨끗한 목록 `[{ text, lang?, kind?, start?(+At · Unknown), end?(+At · Unknown), note? }]`(적은 칸만).
/// 글 하나는 `{ text }`로, text가 빈 줄은 뺀다. 꼴에 맞지 않는 언어 꼬리표는 알리고 적은 그대로 둔다. 읽을 수 없는 기간은 그쪽만 비우고,
/// 끝이 시작보다 앞서면 끝을 비운다. 같은 글 · 언어 · 종류 · 시작의 줄이 또 나오면 뺀다.
pub fn read_names(ctx: &Ctx, v: &V, warn: &mut dyn FnMut(String)) -> Vec<V> {
    let list = match v { V::Arr(a) => a.to_vec(), x if x.is_nullish() || super::is_empty_str(x) => Vec::new(), x => vec![x.clone()] };
    let mut out: Vec<V> = Vec::new();
    for (i, raw) in list.iter().enumerate() {
        let x = match raw {
            V::Str(_) => { let o = Obj::new(); o.set("text", raw.clone()); V::Obj(o) }
            r if js::truthy(r) && super::is_plain(r) => r.clone(),
            _ => V::Null,
        };
        let text = if x.is_null() { Str::default() } else { dates::str_of(&js::nullish(x.get("text"), x.get("name"))) };
        if text.is_empty() {
            if super::given(raw) { warn(format!("이름 목록 #{}: 글(text)이 비어 있어 뺐습니다.", i + 1)); }
            continue;
        }
        let o = Obj::new();
        o.set("text", text.clone());
        let lang = dates::str_of(&x.get("lang"));
        if !lang.is_empty() {
            o.set("lang", lang.clone());
            if !is_lang_tag(&V::Str(lang.clone())) { warn(format!("이름 \"{text}\": 언어 꼬리표 \"{lang}\"이(가) 꼴에 맞지 않습니다(ko · zh-Hant · x-… 꼴) — 적은 그대로 둡니다.")); }
        }
        let kind = dates::str_of(&x.get("kind"));
        if !kind.is_empty() {
            let id = name_kind(&V::Str(kind.clone()));
            o.set("kind", if id.is_empty() { kind } else { id });
        }
        for k in ["start", "end"] {
            let Some(d) = cells::read_cell_edge(ctx, &x, k) else { continue };
            match d {
                cells::Edge::Unknown(t) => {
                    if let Some(t) = t { o.set(k, t); }
                    o.set(&format!("{k}Unknown"), true);
                }
                cells::Edge::Date(d) => {
                    if d.t.is_nan() {
                        let err = d.error.as_ref().map_or(String::new(), |e| format!(" {e}"));
                        warn(format!("이름 \"{text}\": {} 때를 읽을 수 없어 비웠습니다.{err}", if k == "start" { "쓰기 시작한" } else { "그친" }));
                        continue;
                    }
                    o.set(k, d.t);
                    if let Some(at) = d.at { o.set(&format!("{k}At"), at); }
                }
            }
        }
        let (start, end) = (o.get("start"), o.get("end"));
        if !start.is_nullish() && !end.is_nullish() && dates::end_bound_t(ctx, js::to_num(&end), &o.get("endAt")) < js::to_num(&start) {
            warn(format!("이름 \"{text}\": 그친 때가 쓰기 시작한 때보다 앞서 그친 때를 비웠습니다."));
            o.delete("end");
            o.delete("endAt");
        }
        let note = dates::str_of(&x.get("note"));
        if !note.is_empty() { o.set("note", note); }
        let same = |y: &V| {
            let or_empty = |v: V| js::or(v, V::from(""));
            js::strict_eq(&y.get("text"), &o.get("text"))
                && js::strict_eq(&or_empty(y.get("lang")), &or_empty(o.get("lang")))
                && js::strict_eq(&or_empty(y.get("kind")), &or_empty(o.get("kind")))
                && js::strict_eq(&y.get("start"), &o.get("start"))
        };
        if out.iter().any(same) {
            warn(format!("이름 \"{text}\"이(가) 두 번 적혀 있어 뒤의 것을 뺐습니다."));
            continue;
        }
        out.push(V::Obj(o));
    }
    out
}

// ── 글자 범위(2676 ~ 2687줄 — 5c: 글꼴의 ranges) ──

/// `HT.parseRange(s)` — 글자 범위 글 → (처음, 끝): "U+F1A00-F1A0B" · "U+4E00"(대소문자 무관 · 끝 포함 · 끝 쪽의 U+는 빼도 됨). 꼴이 틀리면 None.
/// 정규식 `/^\s*U\+([0-9A-F]{1,6})\s*(?:[-–~]\s*(?:U\+)?([0-9A-F]{1,6}))?\s*$/i`을 손으로: 16진 자리는 1 ~ 6자이고 그 뒤가 16진 글자가 아니어야 한다
/// (탐욕 `{1,6}`이 물러나도 다음 글자가 16진이라 뒤가 맞지 않으므로). 가운데 가름(`-` · U+2013 · `~`)이 있으면 뒤 몫이 꼭 맞아야 한다. `i`는 ASCII 글자만 접는다.
pub fn parse_range(s: &V) -> Option<(u32, u32)> {
    let u = js::to_str(&js::nullish(s.clone(), V::from(""))).to_units();
    let n = u.len();
    let ws = |c: u16| char::from_u32(u32::from(c)).is_some_and(js::is_space);
    let skip_ws = |mut p: usize| { while p < n && ws(u[p]) { p += 1; } p };
    let hex = |c: u16| c < 128 && (c as u8).is_ascii_hexdigit();
    let u_plus = |p: usize| p + 1 < n && (u[p] == 0x55 || u[p] == 0x75) && u[p + 1] == 0x2B; // U+ · u+
    let hex_run = |p: usize| -> Option<(usize, u32)> {
        let mut q = p;
        while q < n && hex(u[q]) { q += 1; }
        if q == p || q - p > 6 { return None; }
        let text: String = u[p..q].iter().map(|&c| c as u8 as char).collect();
        Some((q, u32::from_str_radix(&text, 16).ok()?))
    };
    let p = skip_ws(0);
    if !u_plus(p) { return None; }
    let (p, lo) = hex_run(p + 2)?;
    let mut p = skip_ws(p);
    let mut hi = lo;
    if p < n && matches!(u[p], 0x2D | 0x2013 | 0x7E) {
        let mut q = skip_ws(p + 1);
        if u_plus(q) && q + 2 < n && hex(u[q + 2]) { q += 2; }
        let (q, h) = hex_run(q)?;
        hi = h;
        p = skip_ws(q);
    }
    if p != n { return None; }
    if lo <= hi && hi <= 0x10FFFF { Some((lo, hi)) } else { None }
}
/// `HT.rangeText(r)` — (처음, 끝) → "U+F1A00-F1A0B"(하나면 "U+4E00") — 16진 대문자 · 적어도 네 자리.
pub fn range_text(r: (u32, u32)) -> String {
    if r.0 == r.1 { format!("U+{:04X}", r.0) } else { format!("U+{:04X}-{:04X}", r.0, r.1) }
}

// ── 사람 잇기(2778 ~ 2924줄 — 5b) ──

/// JS 빈칸(`\s`) 코드 단위인가 — JS의 빈칸은 모두 BMP 글자라 코드 단위 하나로 본다(서로게이트는 빈칸이 아님).
fn ws_unit(c: u16) -> bool { char::from_u32(u32::from(c)).is_some_and(js::is_space) }
/// JS `.`이 맞지 않는 줄 끝(`\n` `\r` U+2028 U+2029).
fn line_end_unit(c: u16) -> bool { matches!(c, 0x0A | 0x0D | 0x2028 | 0x2029) }
/// `/^([^:@]+?)\s*:\s*([^@]+?)\s*(?:@\s*(.+))?$/`(`HT.readPersonRef`의 "나라:지도자@시작 해")을 코드 단위로 손으로 옮긴 것 → (m[1], m[2], m[3]) · 안 맞으면 None.
/// 되돌아보기의 뜻을 갈래마다 풀었다(벡터 `personRef:*`가 갈래마다 맞은 표본을 지킨다):
/// - m[1]: 처음 나온 ':' · '@' 가운데 ':'가 먼저여야 하고(그 앞은 `[^:@]`), 게으른 `+?`라 그 앞 글에서 끝 빈칸을 뺀 것(적어도 한 글자).
/// - '@'가 없으면: ':' 뒤 앞 빈칸을 넘긴 곳부터 끝 빈칸을 뺀 곳까지가 m[2](비면 탐욕 `\s*`가 한 글자 물러나 빈칸 하나가 m[2]) · m[3]은 없음.
/// - '@'가 있으면(뒤의 첫 '@'): m[2]는 그 앞까지(위와 같은 규칙 — ':' 바로 뒤가 '@'면 안 맞음), '@' 뒤 빈칸을 넘긴 나머지가 m[3](`.+` — 줄 끝이 있으면 안 맞음 ·
///   빈칸만 남으면 탐욕 `\s*`가 물러나 마지막 한 글자).
/// (`pub`은 벡터 검사가 정규식 그 자체를 — 다듬지 않은 글로 — 견주려고.)
#[doc(hidden)]
pub fn person_cell_text(t: &Str) -> Option<(Str, Str, Option<Str>)> {
    let u = t.to_units();
    let n = u.len();
    let (colon, at) = (u16::from(b':'), u16::from(b'@'));
    let p = u.iter().position(|&c| c == colon || c == at)?;
    if u[p] != colon || p == 0 { return None; }
    let mut e1 = p;
    while e1 > 0 && ws_unit(u[e1 - 1]) { e1 -= 1; }
    let g1 = Str::from_units(&u[..e1.max(1)]);
    let r0 = p + 1;
    let q = u[r0..].iter().position(|&c| c == at).map(|x| x + r0);
    let lim = q.unwrap_or(n); // m[2]가 넘지 못하는 자리
    let mut s0 = r0;
    while s0 < lim && ws_unit(u[s0]) { s0 += 1; }
    let g2 = if s0 < lim {
        let mut e2 = lim;
        while e2 > s0 && ws_unit(u[e2 - 1]) { e2 -= 1; }
        Str::from_units(&u[s0..e2])
    } else if lim > r0 {
        Str::from_units(&u[lim - 1..lim]) // 앞 빈칸뿐 — 탐욕 \s*가 한 글자 물러남
    } else {
        return None; // m[2]가 빔
    };
    let Some(q) = q else { return Some((g1, g2, None)) };
    let mut s3 = q + 1;
    while s3 < n && ws_unit(u[s3]) { s3 += 1; }
    let k = if s3 < n { s3 } else if n > q + 1 { n - 1 } else { return None };
    if u[k..].iter().any(|&c| line_end_unit(c)) { return None; }
    Some((g1, g2, Some(Str::from_units(&u[k..]))))
}
/// `cellRef(x)`(`HT.readPersonRef` 안) — 지도자 칸 `{ track?, polity, leader, start?(+At) }`(나라 · 지도자가 비면 undefined).
fn person_cell_ref(ctx: &Ctx, x: &V) -> V {
    let s = dates::str_of;
    let polity = s(&x.get("polity"));
    let leader = s(&js::nullish(x.get("leader"), x.get("name")));
    if polity.is_empty() || leader.is_empty() { return V::Undef; }
    let o = Obj::new();
    let track = s(&x.get("track"));
    if !track.is_empty() { o.set("track", track); }
    o.set("polity", polity);
    o.set("leader", leader);
    let start = x.get("start");
    let d = if start.is_nullish() || super::is_empty_str(&start) { None } else { dates::read_date(ctx, &start, &x.get("startAt")) };
    if let Some(d) = d {
        if !d.t.is_nan() {
            o.set("start", d.t);
            if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set("startAt", at); }
        }
    }
    V::Obj(o)
}
/// `HT.readPersonRef(v)` — 사람 참조 원문 → 글(인물 id · 이름 — 다듬은 글) · 지도자 칸 `{ track?, polity, leader, start?(+At) }` · null(비움) · undefined(읽지 못함).
/// 글 "나라:지도자@시작 해"는 객체로 바꾼다("@해"는 없어도 됨).
pub fn read_person_ref(ctx: &Ctx, v: &V) -> V {
    if v.is_nullish() || super::is_empty_str(v) { return V::Null; }
    match v {
        V::Num(n) => V::from(js::num_str(*n)),
        V::Str(s) => {
            let t = s.trim();
            if t.is_empty() { return V::Null; }
            match person_cell_text(&t) {
                Some((polity, leader, start)) => {
                    let x = Obj::new();
                    x.set("polity", polity);
                    x.set("leader", leader);
                    x.set("start", start.map_or(V::Undef, V::Str));
                    person_cell_ref(ctx, &V::Obj(x))
                }
                None => V::Str(t),
            }
        }
        x if super::is_plain(x) && (!x.get("polity").is_nullish() || !x.get("leader").is_nullish()) => person_cell_ref(ctx, x),
        _ => V::Undef,
    }
}
/// `HT.personRefText(r)` — 사람 참조 → 한 칸 글: 글은 그대로, 지도자 칸은 "나라:지도자@시작 해".
pub fn person_ref_text(r: &V) -> Str {
    if !js::truthy(r) { return Str::default(); }
    if let V::Str(s) = r { return s.clone(); }
    let at = if r.get("start").is_nullish() { String::new() } else { format!("@{}", js::to_str(&js::or(r.get("startAt"), r.get("start")))) };
    Str::from(format!("{}:{}{at}", js::to_str(&r.get("polity")), js::to_str(&r.get("leader"))))
}
/// `HT.readGroupPeople(v, warn)`(5c) — 단체의 구성원: 쉼표로 이은 글 하나 · 목록 → 사람 참조 목록(`HT.readPersonRef`). 같은 사람을 두 번 적으면 첫 줄만,
/// 읽지 못한 것은 warn으로 알리고 뺀다(이름 모를 사람 — "미상" — 도 뺀다). 쉼표 가름 `/[,，]/`은 코드 단위로.
pub fn read_group_people(ctx: &Ctx, v: &V, warn: &mut dyn FnMut(String)) -> Vec<V> {
    let items: Vec<V> = match v {
        V::Arr(a) => a.to_vec(),
        x if x.is_nullish() || super::is_empty_str(x) => Vec::new(),
        V::Str(s) => super::split_units(s, &[0x2C, 0xFF0C]).into_iter().map(V::Str).collect(),
        x => vec![x.clone()],
    };
    let mut out: Vec<V> = Vec::new();
    for x in &items {
        if is_unknown_who(x) {
            warn(format!("구성원 \"{}\"은(는) 뺐습니다 — 이름 모를 사람은 구성원으로 적지 않습니다(서로 다른 사람이 한 사람으로 묶이지 않게).", js::to_str(x).trim()));
            continue;
        }
        let r = read_person_ref(ctx, x);
        if r.is_null() { continue; }
        if r.is_undef() {
            let shown = if js::type_of(x) == "object" { js::stringify(x) } else { format!("\"{}\"", js::to_str(x)) };
            warn(format!("구성원 {shown}을(를) 읽을 수 없어 뺐습니다 (인물의 이름 · id나 지도자 칸 \"나라:지도자@시작 해\")."));
            continue;
        }
        let text = person_ref_text(&r);
        if !out.iter().any(|q| person_ref_text(q) == text) { out.push(r); }
    }
    out
}
/// `HT.readAccession(raw, warn)` — 자리 이음 원문 → `{ kin?, kinUnknown?, how?, howUnknown?, from?, fromUnknown?, note? }`(적은 칸만) · None(적은 것이 없음).
/// kin · how는 표의 낱말이면 id로, 아니면 적은 글 그대로. 글 "미상" 하나만 적으면 관계 · 방식이 모두 미상.
pub fn read_accession(ctx: &Ctx, raw: &V, warn: &mut dyn FnMut(String)) -> Option<Obj> {
    let s = dates::str_of;
    if raw.is_nullish() || super::is_empty_str(raw) { return None; }
    if is_unknown_who(raw) {
        let o = Obj::new();
        o.set("kinUnknown", true);
        o.set("howUnknown", true);
        return Some(o);
    }
    if !super::is_plain(raw) {
        warn(format!("자리 이음는 {{ \"kin\": …, \"how\": …, \"from\": …, \"note\": … }} 꼴로 적습니다 — \"{}\"은(는) 무시했습니다.", s(raw)));
        return None;
    }
    let o = Obj::new();
    let readers: [(&str, fn(&V) -> Str); 2] = [("kin", kin_id), ("how", accession_how)];
    for (k, read) in readers {
        let x = raw.get(k);
        if matches!(raw.get(&format!("{k}Unknown")), V::Bool(true)) || is_unknown_who(&x) { o.set(&format!("{k}Unknown"), true); }
        else if !s(&x).is_empty() { let id = read(&x); o.set(k, if id.is_empty() { s(&x) } else { id }); }
    }
    let from = raw.get("from");
    if matches!(raw.get("fromUnknown"), V::Bool(true)) || is_unknown_who(&from) { o.set("fromUnknown", true); }
    else if super::given(&from) {
        let r = read_person_ref(ctx, &from);
        if js::truthy(&r) { o.set("from", r); }
        else { warn("자리 이음의 앞 지도자(from)을 읽을 수 없어 뺐습니다 — 인물 id · 이름이나 \"나라:지도자@시작 해\"로 적습니다.".into()); }
    }
    let note = s(&raw.get("note"));
    if !note.is_empty() { o.set("note", note); }
    if o.is_empty() { None } else { Some(o) }
}
/// `readWho(x, warn, what)` — 혈연의 사람 칸: "미상"이면 `{ whoUnknown: true }`, 아니면 `{ who }` — 읽지 못하면 None.
fn read_who(ctx: &Ctx, x: &V, warn: &mut dyn FnMut(String), what: &str) -> Option<Obj> {
    let o = Obj::new();
    if matches!(x.get("whoUnknown"), V::Bool(true)) || is_unknown_who(&x.get("who")) {
        o.set("whoUnknown", true);
        return Some(o);
    }
    let r = read_person_ref(ctx, &js::nullish(x.get("who"), x.get("name")));
    if js::truthy(&r) {
        o.set("who", r);
        return Some(o);
    }
    warn(format!("{what} 가운데 사람(who)이 없거나 읽을 수 없는 줄을 뺐습니다 — 모르면 \"미상\"이라고 적습니다."));
    None
}
/// 혈연 목록의 한 줄(글은 `{ who }`) — 객체가 아니면 None.
fn kin_row(raw: &V) -> Option<V> {
    match raw {
        V::Str(_) => { let o = Obj::new(); o.set("who", raw.clone()); Some(V::Obj(o)) }
        r if js::truthy(r) && super::is_plain(r) => Some(r.clone()),
        _ => None,
    }
}
/// 목록(하나만 적은 것도 — 비면 빈 목록).
fn list_of(v: &V) -> Vec<V> { match v { V::Arr(a) => a.to_vec(), x if x.is_nullish() || super::is_empty_str(x) => Vec::new(), x => vec![x.clone()] } }
/// 알림 글의 사람 이름(`HT.personRefText(o.who) || '미상'`).
fn who_text(o: &Obj) -> Str { let t = person_ref_text(&o.get("who")); if t.is_empty() { Str::from("미상") } else { t } }
/// `HT.readParents(v, warn)` — 부모 · 조상 원문 → `[{ who | whoUnknown, as?, gen?, certainty?, note? }]`.
/// as는 표의 낱말이면 id, 아니면 적은 글. gen(몇 대손)은 후손(ancestor)일 때만 — 1 이상의 수(반올림). certainty는 확실성 등급(통설은 적지 않음 — 이름으로도 읽음).
pub fn read_parents(ctx: &Ctx, v: &V, warn: &mut dyn FnMut(String)) -> Vec<V> {
    let s = dates::str_of;
    let mut out = Vec::new();
    for raw in list_of(v) {
        let Some(x) = kin_row(&raw) else { continue };
        let Some(w) = read_who(ctx, &x, warn, "부모") else { continue };
        let o = super::assign_copy(&V::Obj(w));
        let as_word = s(&x.get("as"));
        if !as_word.is_empty() { let id = parent_role(&x.get("as")); o.set("as", if id.is_empty() { as_word } else { id }); }
        let gen = x.get("gen");
        if !gen.is_nullish() && !super::is_empty_str(&gen) {
            let g = js::to_num(&gen);
            if !js::strict_eq(&o.get("as"), &V::from("ancestor")) { warn(format!("부모 \"{}\": 몇 대손(gen)은 후손(ancestor)일 때만 적습니다 — 뺐습니다.", who_text(&o))); }
            else if !g.is_finite() || g < 1.0 { warn(format!("부모 \"{}\": 몇 대손(gen)은 1 이상의 수로 적습니다 — \"{}\"을(를) 뺐습니다.", who_text(&o), s(&gen))); }
            else { o.set("gen", js::round(g)); }
        }
        let certainty = s(&x.get("certainty"));
        if !certainty.is_empty() {
            match vocab::CERTAINTY.iter().find(|(id, name)| certainty == *id || certainty == *name) {
                None => warn(format!("부모 \"{}\": 확실성 \"{certainty}\"을(를) 알 수 없어 뺐습니다.", who_text(&o))),
                Some((id, _)) if *id != "accepted" => o.set("certainty", *id),
                Some(_) => {}
            }
        }
        let note = s(&x.get("note"));
        if !note.is_empty() { o.set("note", note); }
        out.push(V::Obj(o));
    }
    out
}
/// `HT.readSpouses(v, warn)` — 배우자 원문 → `[{ who | whoUnknown, start?(+At · Unknown), end?(+At · Unknown), note? }]` — 기간은 칸과 같은 읽기("미정"도).
pub fn read_spouses(ctx: &Ctx, v: &V, warn: &mut dyn FnMut(String)) -> Vec<V> {
    let s = dates::str_of;
    let mut out = Vec::new();
    for raw in list_of(v) {
        let Some(x) = kin_row(&raw) else { continue };
        let Some(w) = read_who(ctx, &x, warn, "배우자") else { continue };
        let o = super::assign_copy(&V::Obj(w));
        for k in ["start", "end"] {
            match cells::read_cell_edge(ctx, &x, k) {
                None => continue,
                Some(cells::Edge::Unknown(t)) => {
                    if let Some(t) = t { o.set(k, t); }
                    o.set(&format!("{k}Unknown"), true);
                }
                Some(cells::Edge::Date(d)) if d.t.is_nan() => {
                    let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" {e}"));
                    warn(format!("배우자 \"{}\": {} 날짜를 읽을 수 없어 비웠습니다.{why}", who_text(&o), if k == "start" { "시작" } else { "끝" }));
                }
                Some(cells::Edge::Date(d)) => {
                    o.set(k, d.t);
                    if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
                }
            }
        }
        if !o.get("start").is_nullish() && !o.get("end").is_nullish() && dates::end_bound_t(ctx, o.num("end"), &o.get("endAt")) < o.num("start") {
            warn(format!("배우자 \"{}\": 끝이 시작보다 앞서 끝을 비웠습니다.", who_text(&o)));
            o.delete("end");
            o.delete("endAt");
        }
        let note = s(&x.get("note"));
        if !note.is_empty() { o.set("note", note); }
        out.push(V::Obj(o));
    }
    out
}

// ── 좌표(2926 ~ 2931줄 — 5c: 지명의 at) ──

/// `HT.readCoords(v)` — 좌표 [x, y]: 두 수(글로 적은 수도 · 글 하나면 `/[,，\s]+/`로 나눠 빈 조각을 버림). 아니면 None.
pub fn read_coords(v: &V) -> Option<Vec<f64>> {
    let a: Vec<V> = match v {
        V::Arr(a) => a.to_vec(),
        V::Str(s) => {
            let sep = |c: u16| c == 0x2C || c == 0xFF0C || char::from_u32(u32::from(c)).is_some_and(js::is_space);
            s.to_units().split(|&c| sep(c)).filter(|p| !p.is_empty()).map(|p| V::Str(Str::from_units(p))).collect()
        }
        _ => return None,
    };
    if a.len() != 2 { return None; }
    let n: Vec<f64> = a.iter().map(|x| if super::is_empty_str(x) || x.is_nullish() { f64::NAN } else { js::to_num(x) }).collect();
    if n.iter().all(|x| x.is_finite()) { Some(n) } else { None }
}

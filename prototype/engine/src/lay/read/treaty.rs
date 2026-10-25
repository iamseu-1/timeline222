//! `js/core.js` 1681 ~ 1878줄 — 조약 규격 읽기(사건의 `treaty` 묶음 칸) — 한 벌 P3 과제 5c.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 1685 ~ 1713줄 `HT.TREATY_TYPES` · `HT.TREATY_END_REASONS` · `HT.ARTICLE_TAGS` · 1715 ~ 1717줄 `TREATY_WORDS` · `TREATY_END_WORDS` · `ARTICLE_WORDS` ·
//!   1727 ~ 1729줄 `HT.treatyType` · `HT.treatyEndReason` · `HT.articleTag`(= `vocab(…)` — 1718줄 `vocab`은 `read::cells::vocab`)
//! - 1735 ~ 1748줄 `HT.readSigners`(가름 `/[;；\n]/`은 코드 단위로 · 정규식 `/^(.+?)\s*[(（]\s*([^()（）]*?)\s*[)）]$/`은 손으로 — `signer_parts`)
//! - 1765줄 `ARTICLE_HEAD`(손으로 — `article_head`) · 1767 ~ 1780줄 `splitArticle`(제목 정규식은 손으로 — `article_title`) · 1782 ~ 1789줄 `HT.splitArticles`
//! - 1796 ~ 1878줄 `HT.readTreaty`(`/^(true|예|네|불평등)$/i` · 당사국의 `/^[^:]+:.+$/` · `split(/:(.*)/)`은 손으로)
//!
//! 옮기지 않은 것(화면): 보일 이름(`HT.treatyTypeName` …) · `HT.signersText` · `HT.keepListText`.
//! 정규식의 `\s`는 JS 빈칸(`js::is_space` — 모두 BMP 글자라 코드 단위 하나), JS `.`이 맞지 않는 줄 끝은 `\n` `\r` U+2028 U+2029.
use super::{cells, dates, Ctx};
use crate::lay::js::{self, Obj, Str, V};

/// `HT.TREATY_TYPES`(조약 종류 — id, 이름).
pub const TREATY_TYPES: [(&str, &str); 11] = [
    ("peace", "강화"), ("armistice", "휴전"), ("alliance", "동맹"), ("nonaggression", "불가침"), ("trade", "통상"), ("border", "국경"), ("cession", "할양·병합"),
    ("protectorate", "보호"), ("investiture", "책봉·조공"), ("marriage", "혼인"), ("other", "기타"),
];
/// `HT.TREATY_END_REASONS`(조약이 끝난 까닭).
pub const TREATY_END_REASONS: [(&str, &str); 5] = [("expired", "기한 만료"), ("abrogated", "폐기"), ("superseded", "새 조약으로 대체"), ("fulfilled", "이행 완료"), ("annulled", "무효")];
/// `HT.ARTICLE_TAGS`(조항 분류).
pub const ARTICLE_TAGS: [(&str, &str); 7] = [
    ("territory", "영토"), ("indemnity", "배상"), ("trade", "통상"), ("extraterritorial", "치외법권"), ("military", "군사"), ("recognition", "승인"), ("other", "기타"),
];
/// `TREATY_WORDS`.
const TREATY_WORDS: [(&str, &str); 18] = [
    ("평화", "peace"), ("강화조약", "peace"), ("정전", "armistice"), ("휴전협정", "armistice"), ("동맹조약", "alliance"), ("불가침조약", "nonaggression"), ("수호", "trade"),
    ("무역", "trade"), ("통상조약", "trade"), ("경계", "border"), ("국경조약", "border"), ("할양", "cession"), ("병합", "cession"), ("합병", "cession"),
    ("보호조약", "protectorate"), ("책봉", "investiture"), ("조공", "investiture"), ("혼인동맹", "marriage"),
];
/// `TREATY_END_WORDS`.
const TREATY_END_WORDS: [(&str, &str); 7] = [
    ("만료", "expired"), ("기한만료", "expired"), ("파기", "abrogated"), ("대체", "superseded"), ("이행", "fulfilled"), ("이행완료", "fulfilled"), ("무효화", "annulled"),
];
/// `ARTICLE_WORDS`.
const ARTICLE_WORDS: [(&str, &str); 7] = [
    ("할양", "territory"), ("배상금", "indemnity"), ("무역", "trade"), ("영사재판권", "extraterritorial"), ("군대", "military"), ("주둔", "military"), ("인정", "recognition"),
];
/// `HT.treatyType(v)` — 조약 종류: id나 한국어 → id(모르면 '').
pub fn treaty_type(v: &V) -> Str { cells::vocab(&TREATY_TYPES, &TREATY_WORDS, v) }
/// `HT.treatyEndReason(v)` — 끝난 까닭: id나 한국어 → id(모르면 '').
pub fn treaty_end_reason(v: &V) -> Str { cells::vocab(&TREATY_END_REASONS, &TREATY_END_WORDS, v) }
/// `HT.articleTag(v)` — 조항 분류: id나 한국어 → id(모르면 '').
pub fn article_tag(v: &V) -> Str { cells::vocab(&ARTICLE_TAGS, &ARTICLE_WORDS, v) }

/// JS 빈칸(`\s`) 코드 단위인가.
fn ws(c: u16) -> bool { char::from_u32(u32::from(c)).is_some_and(js::is_space) }
/// JS `.`이 맞지 않는 줄 끝(`\n` `\r` U+2028 U+2029).
fn line_end(c: u16) -> bool { matches!(c, 0x0A | 0x0D | 0x2028 | 0x2029) }
/// 앞뒤의 JS 빈칸을 버린 코드 단위(`String.prototype.trim`).
fn trim_units(u: &[u16]) -> Str { Str::from_units(u).trim() }
const OPEN_PAREN: [u16; 2] = [0x28, 0xFF08]; // ( （
const CLOSE_PAREN: [u16; 2] = [0x29, 0xFF09]; // ) ）

/// `/^(.+?)\s*[(（]\s*([^()（）]*?)\s*[)）]$/`(서명자 글 "이름(직함)" — 다듬은 글에 씀)을 손으로 → (m[1], m[2]) · 안 맞으면 None.
/// - 끝 글자가 닫는 괄호여야 하고, 그 앞의 마지막 괄호 글자(네 가지 가운데)가 여는 괄호여야 한다(그 사이 m[2]의 자리에는 괄호가 없어야 하므로 — 그 자리는 하나뿐).
/// - m[1]은 게으른 `.+?`: 여는 괄호 앞 빈칸을 뺀 앞 글(적어도 한 글자 · 줄 끝이 들면 안 맞음). m[2]는 괄호 사이에서 앞뒤 빈칸을 뺀 글(빈칸뿐이면 빈 글).
/// 부르는 쪽이 둘 다 다시 다듬으므로(`m[1].trim()` · `m[2].trim()`) 다듬은 글을 돌려준다.
fn signer_parts(t: &Str) -> Option<(Str, Str)> {
    let u = t.to_units();
    let n = u.len();
    if n < 2 || !CLOSE_PAREN.contains(&u[n - 1]) { return None; }
    let q = (0..n - 1).rev().find(|&k| OPEN_PAREN.contains(&u[k]) || CLOSE_PAREN.contains(&u[k]))?;
    if !OPEN_PAREN.contains(&u[q]) || q == 0 { return None; }
    let mut p = q;
    while p > 1 && ws(u[p - 1]) { p -= 1; }
    if u[..p].iter().any(|&c| line_end(c)) { return None; }
    Some((trim_units(&u[..p]), trim_units(&u[q + 1..n - 1])))
}
/// `HT.readSigners(v)` — 서명자: 목록 `[{ name, title }]` 또는 한 칸 글 "이름(직함); 이름(직함)" → 늘 목록 꼴 `[{ name, title? }]`.
pub fn read_signers(v: &V) -> Vec<V> {
    let list: Vec<V> = match v {
        V::Arr(a) => a.to_vec(),
        V::Str(s) => super::split_units(s, &[0x3B, 0xFF1B, 0x0A]).into_iter().map(V::Str).collect(),
        x if js::truthy(x) && js::type_of(x) == "object" => vec![x.clone()],
        _ => Vec::new(),
    };
    let text = |v: V| js::to_str(&js::nullish(v, V::from(""))).trim();
    let mut out = Vec::new();
    for x in &list {
        let (name, title) = match x {
            V::Str(s) => {
                let t = s.trim();
                match signer_parts(&t) { Some(m) => m, None => (t, Str::default()) }
            }
            x if js::truthy(x) && js::type_of(x) == "object" => (text(x.get("name")), text(x.get("title"))),
            _ => continue,
        };
        if name.is_empty() { continue; }
        let o = Obj::new();
        o.set("name", name);
        if !title.is_empty() { o.set("title", title); }
        out.push(V::Obj(o));
    }
    out
}

/// `[조관항]`.
const ARTICLE_UNIT: [u16; 3] = [0xC870, 0xAD00, 0xD56D];
/// `ARTICLE_HEAD` — `/^\s*(제\s*\d+\s*[조관항]|article\s+\d+|art\.\s*\d+)\s*[.:：]?\s*/i`(조항 번호로 시작하는 줄)을 손으로 → (맞은 길이 m[0], m[1]) · 안 맞으면 None.
/// 갈래마다 되돌아보기가 없다(앞 빈칸 뒤의 첫 글자가 '제' · 'a'로 갈리고, 숫자 · 빈칸은 다음 칸과 겹치지 않음). `i`는 ASCII 글자만 접는다('article' · 'art').
fn article_head(u: &[u16]) -> Option<(usize, Vec<u16>)> {
    let n = u.len();
    let skip_ws = |mut p: usize| { while p < n && ws(u[p]) { p += 1; } p };
    let digits = |p: usize| { let mut q = p; while q < n && (0x30..=0x39).contains(&u[q]) { q += 1; } if q > p { Some(q) } else { None } };
    let word_ci = |p: usize, w: &str| p + w.len() <= n && w.bytes().enumerate().all(|(k, b)| u[p + k] < 128 && (u[p + k] as u8).eq_ignore_ascii_case(&b));
    let g0 = skip_ws(0);
    let alt1 = || -> Option<usize> {
        if g0 >= n || u[g0] != 0xC81C { return None; } // 제
        let q = digits(skip_ws(g0 + 1))?;
        let q = skip_ws(q);
        if q < n && ARTICLE_UNIT.contains(&u[q]) { Some(q + 1) } else { None }
    };
    let alt2 = || -> Option<usize> {
        if !word_ci(g0, "article") { return None; }
        let p = g0 + 7;
        let q = skip_ws(p);
        if q == p { return None; } // \s+
        digits(q)
    };
    let alt3 = || -> Option<usize> {
        if !word_ci(g0, "art") || g0 + 3 >= n || u[g0 + 3] != 0x2E { return None; } // art.
        digits(skip_ws(g0 + 4))
    };
    let g1 = alt1().or_else(alt2).or_else(alt3)?;
    let mut e = skip_ws(g1);
    if e < n && matches!(u[e], 0x2E | 0x3A | 0xFF1A) { e += 1; } // [.:：]?
    let e = skip_ws(e);
    Some((e, u[g0..g1].to_vec()))
}
/// `[(（【[]` · `[)）】\]]`(조항 제목의 괄호).
const TITLE_OPEN: [u16; 4] = [0x28, 0xFF08, 0x3010, 0x5B];
const TITLE_CLOSE: [u16; 4] = [0x29, 0xFF09, 0x3011, 0x5D];
/// `/^[(（【[]\s*([^)）】\]\n]{1,60}?)\s*[)）】\]]\s*/`(번호 바로 뒤의 괄호 제목)을 손으로 → (맞은 길이 m[0], m[1]) · 안 맞으면 None.
/// 되돌아보기: 앞 `\s*`는 탐욕(가장 많이부터), 제목은 게으름(1자부터 60자까지 — 닫는 괄호 · `\n`은 못 담음), 제목 뒤는 빈칸을 넘긴 첫 글자가 닫는 괄호면 맞음.
/// 앞 빈칸 바로 뒤가 닫는 괄호면 앞 `\s*`가 한 글자씩 물러나 빈칸이 제목이 된다(예: "(  )" → 제목 " ").
fn article_title(u: &[u16]) -> Option<(usize, Vec<u16>)> {
    let n = u.len();
    if n == 0 || !TITLE_OPEN.contains(&u[0]) { return None; }
    let skip_ws = |mut p: usize| { while p < n && ws(u[p]) { p += 1; } p };
    let lead = skip_ws(1) - 1;
    for c in (0..=lead).rev() {
        let g = 1 + c;
        for k in 1..=60 {
            let at = g + k - 1;
            if at >= n || TITLE_CLOSE.contains(&u[at]) || u[at] == 0x0A { break; }
            let j = skip_ws(g + k);
            if j < n && TITLE_CLOSE.contains(&u[j]) { return Some((skip_ws(j + 1), u[g..g + k].to_vec())); }
        }
    }
    None
}
/// 코드 단위에서 `\r`을 모두 지운다(`replace(/\r/g, '')`).
fn no_cr(u: &[u16]) -> Vec<u16> { u.iter().copied().filter(|&c| c != 0x0D).collect() }
/// `\s+`마다 `with`로 바꾼다(`replace(/\s+/g, with)`).
fn collapse_ws(u: &[u16], with: &[u16]) -> Vec<u16> {
    let mut out = Vec::with_capacity(u.len());
    let mut in_ws = false;
    for &c in u {
        if ws(c) { if !in_ws { out.extend_from_slice(with); } in_ws = true; } else { out.push(c); in_ws = false; }
    }
    out
}
/// `splitArticle(s)` — 조항 글 하나 → `{ no, title, text }`: 머리의 번호를 떼고, 번호 바로 뒤의 괄호 글("(목적)" · "【목적】")은 제목으로.
fn split_article(s: &V) -> Obj {
    let t = Str::from_units(&no_cr(&js::to_str(&js::nullish(s.clone(), V::from(""))).to_units())).trim();
    let u = t.to_units();
    let o = Obj::new();
    let Some((m0, m1)) = article_head(&u) else {
        o.set("no", "");
        o.set("title", "");
        o.set("text", t);
        return o;
    };
    let art = m1.len() >= 3 && m1[..3].iter().zip(b"art").all(|(&c, &b)| c < 128 && (c as u8).eq_ignore_ascii_case(&b)); // /^\s*art/i.test(m[1])
    let no = Str::from_units(&if art { collapse_ws(&m1, &[0x20]) } else { collapse_ws(&m1, &[]) });
    let mut rest = u[m0..].to_vec();
    let mut title = Str::default();
    if let Some((len, g)) = article_title(&rest) {
        title = trim_units(&g);
        rest = rest[len..].to_vec();
    }
    o.set("no", no);
    o.set("title", title);
    o.set("text", trim_units(&rest));
    o
}
/// `HT.splitArticles(text)` — 조약문 통째 → 조항 목록: 조항 번호로 시작하는 줄마다 새 조항(첫 번호 앞의 글은 번호 없는 조항 하나 — 전문).
pub fn split_articles(text: &V) -> Vec<Obj> {
    let all = no_cr(&js::to_str(&js::nullish(text.clone(), V::from(""))).to_units());
    let mut blocks: Vec<Vec<Vec<u16>>> = Vec::new();
    for line in all.split(|&c| c == 0x0A) {
        if article_head(line).is_some() || blocks.is_empty() { blocks.push(vec![line.to_vec()]); }
        else if let Some(b) = blocks.last_mut() { b.push(line.to_vec()); }
    }
    blocks
        .into_iter()
        .map(|b| split_article(&V::Str(Str::from_units(&b.join(&0x0A)))))
        .filter(|a| ["no", "title", "text"].iter().any(|k| js::truthy(&a.get(*k))))
        .collect()
}

/// `/^(true|예|네|불평등)$/i` — 손으로(`i`는 ASCII 글자만 접음 — 'true'만 닿음).
fn unequal_word(t: &Str) -> bool {
    let Some(s) = t.exact() else { return false };
    s.eq_ignore_ascii_case("true") || matches!(s, "예" | "네" | "불평등")
}
/// `/^[^:]+:.+$/.test(s)` 뒤 `s.split(/:(.*)/)` — 첫 ':'가 맨 앞이 아니고 그 뒤가 비지 않으며 줄 끝이 없으면 (앞, 뒤). `[^:]`은 줄 끝도 받는다.
fn track_and_name(s: &Str) -> Option<(Str, Str)> {
    let u = s.to_units();
    let p = u.iter().position(|&c| c == 0x3A)?;
    let rest = &u[p + 1..];
    if p == 0 || rest.is_empty() || rest.iter().any(|&c| line_end(c)) { return None; }
    Some((Str::from_units(&u[..p]), Str::from_units(rest)))
}
/// `HT.readTreaty(raw, warn)` — 조약 규격을 깨끗한 꼴로 → None(적은 것이 없음) · `{ formal, type, unequal, ratified(+At), effective(+At), endReason, place, languages,
/// parties: [{ track?, polity, side?, role?, signatories }], articles: [{ no, title, tag, text }], concludes, supersedes }` — 적은 칸만.
/// 당사국의 트랙은 여기서 검사하지 않는다(다른 DLC · 기본팩의 트랙일 수 있음). warn(글)은 버린 값을 알린다.
pub fn read_treaty(ctx: &Ctx, raw: &V, warn: &mut dyn FnMut(String)) -> Option<Obj> {
    if !js::truthy(raw) || !super::is_plain(raw) { return None; }
    let s = dates::str_of;
    let o = Obj::new();
    let formal = s(&raw.get("formal"));
    if !formal.is_empty() { o.set("formal", formal); }
    if !s(&raw.get("type")).is_empty() {
        let t = treaty_type(&raw.get("type"));
        if !t.is_empty() { o.set("type", t); } else { warn(format!("조약 종류 \"{}\"을(를) 알 수 없어 뺐습니다.", s(&raw.get("type")))); }
    }
    if matches!(raw.get("unequal"), V::Bool(true)) || unequal_word(&s(&raw.get("unequal"))) { o.set("unequal", true); }
    for (k, word) in [("ratified", "비준"), ("effective", "발효")] {
        let Some(d) = dates::read_date(ctx, &raw.get(k), &raw.get(&format!("{k}At"))) else { continue };
        if d.t.is_nan() {
            let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" {e}"));
            warn(format!("조약의 {word} 날짜를 읽을 수 없어 뺐습니다.{why}"));
            continue;
        }
        o.set(k, d.t);
        if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
    }
    if !s(&raw.get("endReason")).is_empty() {
        let r = treaty_end_reason(&raw.get("endReason"));
        if !r.is_empty() { o.set("endReason", r); } else { warn(format!("조약이 끝난 까닭 \"{}\"을(를) 알 수 없어 뺐습니다.", s(&raw.get("endReason")))); }
    }
    let place = s(&raw.get("place"));
    if !place.is_empty() { o.set("place", place); }
    let langs_in: Vec<V> = match raw.get("languages") { V::Arr(a) => a.to_vec(), x => super::split_units(&s(&x), &[0x2C, 0xFF0C, 0x3001]).into_iter().map(V::Str).collect() };
    let langs: Vec<V> = langs_in.iter().map(s).filter(|t| !t.is_empty()).map(V::Str).collect();
    if !langs.is_empty() { o.set("languages", super::arr_of(langs)); }
    let parties_in: Vec<V> = match raw.get("parties") { V::Arr(a) => a.to_vec(), x if js::truthy(&x) => vec![x], _ => Vec::new() };
    let mut parties = Vec::new();
    for (i, p) in parties_in.iter().enumerate() {
        let (mut track, mut polity) = (Str::default(), Str::default());
        let is_obj = js::truthy(p) && js::type_of(p) == "object";
        if let V::Str(_) = p { polity = s(p); }
        else if is_obj {
            track = s(&p.get("track"));
            polity = s(&js::nullish(p.get("polity"), p.get("name")));
        }
        if track.is_empty() {
            if let Some((a, b)) = track_and_name(&polity) { track = a.trim(); polity = b.trim(); } // "트랙:이름"
        }
        if track.is_empty() && polity.is_empty() {
            if super::given(p) { warn(format!("조약의 당사국 #{}: 정권이 비어 있어 뺐습니다.", i + 1)); }
            continue;
        }
        let q = Obj::new();
        if !track.is_empty() { q.set("track", track); }
        if !polity.is_empty() { q.set("polity", polity); }
        if is_obj {
            let side = p.get("side");
            if !super::is_empty_str(&side) && !side.is_nullish() {
                let n = js::to_num(&side);
                if n.is_finite() && n > 0.0 { q.set("side", js::round(n)); }
                else { warn(format!("조약의 당사국 #{}: 편(side)은 1 · 2처럼 수로 적습니다 — \"{}\"을(를) 뺐습니다.", i + 1, s(&side))); }
            }
            let role = s(&p.get("role"));
            if !role.is_empty() { q.set("role", role); }
            let sig = read_signers(&p.get("signatories"));
            if !sig.is_empty() { q.set("signatories", super::arr_of(sig)); }
        }
        parties.push(V::Obj(q));
    }
    if !parties.is_empty() { o.set("parties", super::arr_of(parties)); }
    let articles_in: Vec<V> = match raw.get("articles") {
        V::Arr(a) => a.to_vec(),
        V::Str(t) => split_articles(&V::Str(t)).into_iter().map(V::Obj).collect(),
        _ => Vec::new(),
    };
    let mut articles = Vec::new();
    for (i, a) in articles_in.iter().enumerate() {
        let x = match a {
            V::Str(_) => V::Obj(split_article(a)),
            a if js::truthy(a) && js::type_of(a) == "object" => a.clone(),
            _ => continue,
        };
        let q = Obj::new();
        for k in ["no", "title"] {
            let t = s(&x.get(k));
            if !t.is_empty() { q.set(k, t); }
        }
        if !s(&x.get("tag")).is_empty() {
            let t = article_tag(&x.get("tag"));
            if !t.is_empty() { q.set("tag", t); } else { warn(format!("조약의 조항 #{}: 분류 \"{}\"을(를) 알 수 없어 뺐습니다.", i + 1, s(&x.get("tag")))); }
        }
        let text = Str::from_units(&no_cr(&js::to_str(&js::nullish(x.get("text"), V::from(""))).to_units())).trim();
        if !text.is_empty() { q.set("text", text); }
        if !q.is_empty() { articles.push(V::Obj(q)); }
    }
    if !articles.is_empty() { o.set("articles", super::arr_of(articles)); }
    for k in ["concludes", "supersedes"] {
        let t = s(&raw.get(k));
        if !t.is_empty() { o.set(k, t); }
    }
    if o.is_empty() { None } else { Some(o) }
}

//! `js/wiki.js`(`HT.namu` — 나무위키 문법의 문서 렌더러)를 줄 그대로 옮긴다 — 한 벌 P3 과제 12a(갈래 C). docs 모듈이 `links` · `files`를 쓴다.
//! 자리: 공통 `lay/mod.rs`를 고치지 않게 docs 모듈 아래(판정 R24-c). 계획의 `lay/wiki.rs` 자리로는 '웹 함수 모으기' 과제(과제 16 앞) 때 옮긴다.
//!
//! 옮긴 원본: `js/wiki.js` — SHA-256 앞 12자 `fb6c22f7437a`(저장소의 LF 바이트)
//! - 10 ~ 31줄 `esc`(노드에서는 `js/core.js` 3060 ~ 3061줄 `HT.escapeHtml` — 같은 정규식 · `9c786cf58566`) · `safeStyle` · `safeColor` · `slug` · `matchEnd` → [`esc`] · [`safe_style`] · [`safe_color`] · [`slug`] · [`match_end`]
//! - 40 ~ 76줄 `FILE_RE` · `namu.FIGURE` · `namu.fileSpec` · `namu.files` · `namu.figureHTML` → [`FIGURE`] · [`file_spec`] · [`files`] · [`figure_html`]
//! - 106 ~ 442줄 `namu.render`(`keep` · `restore` · `inline` · `inlineNoFoot` · `braceInline` · `extractBlocks` · `table` · `block` · `list` · 목차 번호 · 각주) → [`render`]
//! - 445 ~ 453줄 `namu.links` → [`links`] · 456 ~ 477줄 `namu.HELP` · `namu.SHORTCUTS` → [`HELP`] · [`SHORTCUTS`] · 493 ~ 499줄 `SNIP` · 502 ~ 511줄 `TOOLBAR` · `namu.toolbarHTML` → [`toolbar_html`]
//!
//! 옮기지 않은 것(화면 · 캔버스 — 배치 셈이 닿지 않음): 79 ~ 104줄 `namu.fitImage`(캔버스로 그림 줄이기) · 478 ~ 488줄 `namu.showHelp`(대화상자) ·
//! 500 ~ 501줄 `LINE_KINDS` · `PLACEHOLDER`와 513 ~ 771줄 `namu.editor`(글 칸 편집기 — 그 안의 정규식 포함) · 773 ~ 782줄 `namu.attach`.
//!
//! 정규식(계획 머리의 옮기는 규칙 · 정한 것 #8): JS `\s` → `{WS}`(JS 빈칸 목록) · `\S` → `{NWS}` · `\d` → `[0-9]` · `\w` → `[A-Za-z0-9_]` · `.` → `{DOT}`(줄 끝 넷을 뺀 글자) ·
//! `[\s\S]` → `(?s:.)` · `i` 깃발은 ASCII 글자 덩이만 `(?i-u:…)`(JS의 유니코드 아닌 `i`는 ASCII 글자를 `ſ` · `K`(켈빈) 같은 비ASCII 글자와 접지 않는다 — 여기 정규식의
//! 비ASCII 글자는 한글뿐이라 접을 것이 없다) · `\b` → `(?-u:\b)`(ASCII 낱말 경계). 앞보기 `(?!-)`(172줄 `--취소--`)와 뒤참조 `\2\1`(339줄 제목)은 regex에 없어
//! 손으로([`dash`] · [`heading`] — 되짚기 차례 그대로 · `--취소--`는 JS처럼 UTF-16 코드 단위로).
//! 글은 Rust `&str`(외톨이 서로게이트 없음)로 받는다 — docs 모듈은 외톨이 서로게이트가 든 문서 글을 거절한다. 렌더의 표 줄 자르기(`slice(2, -2)`)가 서로게이트 짝을
//! 가르면 JS는 외톨이 서로게이트를, 여기서는 U+FFFD를 낸다(닿지 않는 갈래 — 보고에 적음).
//! 벡터: `node prototype/scripts/js-vectors.mjs`의 `wiki` 갈래(정규식마다 표본 · 함수 · 렌더 · 견본 문서) → `tests/lay_wiki.rs`.
use crate::lay::js::{self, civil_from_days, days_from_civil, Obj, Str, V};
use crate::lay::model::util::tv;
use regex::{Captures, NoExpand, Regex};
use serde_json::{json, Value};
use std::sync::OnceLock;

// ── 정규식 ──

/// JS 빈칸 목록(`\s` — `js::is_space`와 같은 글자들)의 대괄호 속.
const SP: &str = r"\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}";

/// 패턴의 `{WS}` · `{NWS}` · `{SP}` · `{DOT}`를 JS 뜻의 글자 묶음으로 바꿔 짓는다.
fn build(pattern: &str) -> Regex {
    let full = pattern.replace("{WS}", &format!("[{SP}]")).replace("{NWS}", &format!("[^{SP}]")).replace("{SP}", SP).replace("{DOT}", r"[^\n\r\x{2028}\x{2029}]");
    Regex::new(&full).unwrap_or_else(|e| panic!("위키 정규식 {pattern}: {e}"))
}
macro_rules! regexes {
    ($( #[doc = $doc:literal] $name:ident = $pat:expr; )*) => {
        $( #[doc = $doc] fn $name() -> &'static Regex { static R: OnceLock<Regex> = OnceLock::new(); R.get_or_init(|| build($pat)) } )*
    };
}
regexes! {
    /// 10줄 `/[&<>"']/g`(core.js 3061줄 `HT.escapeHtml`도 같다).
    re_esc = r#"[&<>"']"#;
    /// 13줄 `/url\s*\(|expression|javascript:|@import|behavior\s*:/gi`.
    re_style_bad = r"(?i-u:url){WS}*\(|(?i-u:expression)|(?i-u:javascript):|@(?i-u:import)|(?i-u:behavior){WS}*:";
    /// 13줄 `/[^\w\s#%.,:;()\-'"!]/g`.
    re_style_keep = r#"[^A-Za-z0-9_{SP}#%.,:;()\-'"!]"#;
    /// 14줄 `/^#[0-9a-f]{3,8}$/i`.
    re_color_hex = r"^#(?i-u:[0-9a-f]){3,8}$";
    /// 14줄 `/^[a-z]{3,20}$/i`.
    re_color_name = r"^(?i-u:[a-z]){3,20}$";
    /// 40줄 `FILE_RE = /\[\[((?:파일|이미지|file)\s*:[^\]]*?)\]\]/gi`.
    re_file = r"\[\[((?:파일|이미지|(?i-u:file)){WS}*:[^\]]*?)\]\]";
    /// 46줄 `/^(파일|이미지|file)\s*:\s*/i`.
    re_file_head = r"^(파일|이미지|(?i-u:file)){WS}*:{WS}*";
    /// 48줄 `/^(width|align)\s*=\s*(.+)$/i`.
    re_file_opt = r"^((?i-u:width|align)){WS}*={WS}*({DOT}+)$";
    /// 51줄 `/^\d{1,4}(px|%)?$/`.
    re_file_width = r"^[0-9]{1,4}(px|%)?$";
    /// 51줄 `/%$/`.
    re_file_pct = r"%$";
    /// 52줄 `/^(left|center|right)$/`.
    re_file_align = r"^(left|center|right)$";
    /// 117줄 `/\x01(\d+)\x01/g`.
    re_restore = r"\x01([0-9]+)\x01";
    /// 123줄 `/\{\{\{([\s\S]*?)\}\}\}/g`.
    re_brace = r"\{\{\{((?s:.)*?)\}\}\}";
    /// 132줄 `/^(\S*)\s?([\s\S]*)$/`.
    re_fn_inner = r"^({NWS}*){WS}?((?s:.)*)$";
    /// 137줄 `/<[^>]+>/g`.
    re_tag = r"<[^>]+>";
    /// 150 · 343줄 `/\[\[([^\]|]+?)(?:\|([^\]]*?))?\]\]/g`.
    re_link = r"\[\[([^\]|]+?)(?:\|([^\]]*?))?\]\]";
    /// 152줄 `/^인물\s*:\s*/`.
    re_link_figure = r"^인물{WS}*:{WS}*";
    /// 153줄 `/^(분류|category):/i`.
    re_link_cat = r"^(분류|(?i-u:category)):";
    /// 157줄 `/^(파일|이미지|file):/i`.
    re_link_file = r"^(파일|이미지|(?i-u:file)):";
    /// 158줄 `/^https?:\/\//i`.
    re_link_http = r"^(?i-u:https?)://";
    /// 158줄 `/^\/\//`.
    re_link_proto = r"^//";
    /// 169줄 `/&#39;&#39;&#39;([\s\S]+?)&#39;&#39;&#39;/g`.
    re_bold = r"&#39;&#39;&#39;((?s:.)+?)&#39;&#39;&#39;";
    /// 170줄 `/&#39;&#39;([\s\S]+?)&#39;&#39;/g`.
    re_italic = r"&#39;&#39;((?s:.)+?)&#39;&#39;";
    /// 171줄 `/~~([^~\n]+?)~~/g`.
    re_strike = r"~~([^~\n]+?)~~";
    /// 173줄 `/__([^_\n]+?)__/g`.
    re_under = r"__([^_\n]+?)__";
    /// 174줄 `/\^\^([^^\n]+?)\^\^/g`.
    re_sup = r"\^\^([^\^\n]+?)\^\^";
    /// 175줄 `/,,([^,\n]+?),,/g`.
    re_sub = r",,([^,\n]+?),,";
    /// 176줄 `/\[br\]/gi`.
    re_br = r"\[(?i-u:br)\]";
    /// 177줄 `/\[(?:date|datetime)\]/gi`.
    re_date = r"\[(?i-u:date|datetime)\]";
    /// 178줄 `/\[age\((\d{4})-(\d{1,2})-(\d{1,2})\)\]/gi`.
    re_age = r"\[(?i-u:age)\(([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})\)\]";
    /// 185줄 `/\[(?:include|youtube|nicovideo|kakaotv|vimeo|navertv|ruby)\([^\]]*\)\]/gi`.
    re_macro = r"\[(?i-u:include|youtube|nicovideo|kakaotv|vimeo|navertv|ruby)\([^\]]*\)\]";
    /// 186줄 `/\[(?:목차|tableofcontents)\]/gi`.
    re_toc = r"\[(?:목차|(?i-u:tableofcontents))\]";
    /// 187줄 `/\[(?:각주|footnote)\]/gi`.
    re_foot = r"\[(?:각주|(?i-u:footnote))\]";
    /// 193 · 231줄 `/^([+-])(\d)\s([\s\S]*)$/`.
    re_size = r"^([+-])([0-9]){WS}((?s:.)*)$";
    /// 194줄 `/^#([0-9a-fA-F]{3,8}|[a-zA-Z]{3,20})(?:,#[0-9a-fA-F]{3,8})?\s([\s\S]*)$/`.
    re_color = r"^#([0-9a-fA-F]{3,8}|[a-zA-Z]{3,20})(?:,#[0-9a-fA-F]{3,8})?{WS}((?s:.)*)$";
    /// 195줄 `/^[0-9a-fA-F]{3,8}$/`.
    re_color_ishex = r"^[0-9a-fA-F]{3,8}$";
    /// 218줄 `/^#!(folding|wiki|syntax|html)\b([^\n]*)\n?([\s\S]*)$/`.
    re_block_head = r"^#!(folding|wiki|syntax|html)(?-u:\b)([^\n]*)\n?((?s:.)*)$";
    /// 226줄 `/style="([^"]*)"/`.
    re_box_style = r#"style="([^"]*)""#;
    /// 266줄 `/^<([^<>\n]*)>/`.
    re_cell_opt = r"^<([^<>\n]*)>";
    /// 270줄 `/^-(\d+)$/`.
    re_cell_colspan = r"^-([0-9]+)$";
    /// 271줄 `/^\|(\d+)$/`.
    re_cell_rowspan = r"^\|([0-9]+)$";
    /// 272줄 `/^(?:\^\||v\|)(\d+)$/`.
    re_cell_rowspan2 = r"^(?:\^\||v\|)([0-9]+)$";
    /// 276줄 `/^bgcolor=(.+)$/i`.
    re_cell_bgcolor = r"^(?i-u:bgcolor)=({DOT}+)$";
    /// 277줄 `/^color=(.+)$/i`.
    re_cell_color = r"^(?i-u:color)=({DOT}+)$";
    /// 278줄 `/^width=(\d+%?|\d+px)$/i`.
    re_cell_width = r"^(?i-u:width)=([0-9]+%?|[0-9]+(?i-u:px))$";
    /// 279줄 `/^height=(\d+%?|\d+px)$/i`.
    re_cell_height = r"^(?i-u:height)=([0-9]+%?|[0-9]+(?i-u:px))$";
    /// 280줄 `/^rowbgcolor=(.+)$/i`.
    re_cell_rowbgcolor = r"^(?i-u:rowbgcolor)=({DOT}+)$";
    /// 281줄 `/^rowcolor=(.+)$/i`.
    re_cell_rowcolor = r"^(?i-u:rowcolor)=({DOT}+)$";
    /// 282줄 `/^table\s*bgcolor=(.+)$/i`.
    re_cell_table_bgcolor = r"^(?i-u:table){WS}*(?i-u:bgcolor)=({DOT}+)$";
    /// 283줄 `/^table\s*bordercolor=(.+)$/i`.
    re_cell_table_bordercolor = r"^(?i-u:table){WS}*(?i-u:bordercolor)=({DOT}+)$";
    /// 284줄 `/^table\s*width=(\d+%?|\d+px)$/i`.
    re_cell_table_width = r"^(?i-u:table){WS}*(?i-u:width)=([0-9]+%?|[0-9]+(?i-u:px))$";
    /// 285줄 `/^table\s*align=(left|center|right)$/i`.
    re_cell_table_align = r"^(?i-u:table){WS}*(?i-u:align)=((?i-u:left|center|right))$";
    /// 286줄 `/^(nopad|table)/i`.
    re_cell_skip = r"^((?i-u:nopad|table))";
    /// 295줄 `/^\s/`.
    re_cell_lead = r"^{WS}";
    /// 296줄 `/\s$/`.
    re_cell_trail = r"{WS}$";
    /// 300 · 411 · 510줄 `/\n/g`.
    re_nl = r"\n";
    /// 309줄 `/\r\n?/g`.
    re_crlf = r"\r\n?";
    /// 324줄 `/^\s*\x01\d+\x01\s*$/`.
    re_block_ph = r"^{WS}*\x01[0-9]+\x01{WS}*$";
    /// 329줄 `/^\s*\[(각주|footnote)\]\s*$/i`.
    re_block_foot = r"^{WS}*\[(각주|(?i-u:footnote))\]{WS}*$";
    /// 334줄 `/^\s*\[(목차|tableofcontents)\]\s*$/i`.
    re_block_toc = r"^{WS}*\[(목차|(?i-u:tableofcontents))\]{WS}*$";
    /// 347줄 `/^-{4,9}\s*$/`.
    re_hr = r"^-{4,9}{WS}*$";
    /// 352 · 355줄 `/^\s*\|\|/`.
    re_table_line = r"^{WS}*\|\|";
    /// 360 · 363줄 `/^>/`.
    re_quote = r"^>";
    /// 363줄 `/^>\s?/`.
    re_quote_head = r"^>{WS}?";
    /// 368 · 371줄 `/^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?(.*)$/`.
    re_list = r"^( +)(\*|1\.(?:#[0-9]+)?|a\.|A\.|i\.|I\.){WS}?({DOT}*)$";
    /// 375줄 `/^ {2,}\S/`.
    re_list_more = r"^ {2,}{NWS}";
    /// 375줄 `/^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?/`.
    re_list_head = r"^( +)(\*|1\.(?:#[0-9]+)?|a\.|A\.|i\.|I\.){WS}?";
    /// 381줄 `/\[\[(?:파일|이미지|file)\s*:/i`.
    re_image_line = r"\[\[(?:파일|이미지|(?i-u:file)){WS}*:";
    /// 407줄 `/#(\d+)/`.
    re_list_start = r"#([0-9]+)";
    /// 433줄 `/<span class="wk-hnum" data-toc="(\d+)"><\/span>/g`.
    re_hnum = r#"<span class="wk-hnum" data-toc="([0-9]+)"></span>"#;
    /// 438줄 `/\x02TOC\x02/g`.
    re_toc_ph = r"\x02TOC\x02";
    /// 438줄 `/\x02FOOT\x02/g`.
    re_foot_ph = r"\x02FOOT\x02";
    /// 447줄 `/\[\[([^\]|]+?)(?:\|[^\]]*?)?\]\]/g`.
    re_links = r"\[\[([^\]|]+?)(?:\|[^\]]*?)?\]\]";
    /// 449줄 `/^(분류|파일|이미지|category|file|https?:)/i`.
    re_links_skip = r"^(분류|파일|이미지|(?i-u:category|file|https?:))";
}

/// 169 ~ 176 · 300줄의 바꿔 넣는 글(JS `$1` = regex `${1}`). 벡터 검사([`probe`])와 렌더가 같은 글을 쓴다.
const T_BOLD: &str = "<b>${1}</b>";
const T_ITALIC: &str = "<i>${1}</i>";
const T_STRIKE: &str = "<s>${1}</s>";
const T_UNDER: &str = "<u>${1}</u>";
const T_SUP: &str = "<sup>${1}</sup>";
const T_SUB: &str = "<sub>${1}</sub>";
const T_BR: &str = "<br>";
const T_TOC: &str = "\u{2}TOC\u{2}";
const T_FOOT: &str = "\u{2}FOOT\u{2}";

// ── JS 뜻의 작은 도움 ──

/// JS `trim()`(빈칸 · 줄 끝을 양쪽에서).
fn trim(s: &str) -> &str { s.trim_matches(js::is_space) }
/// JS `trimEnd()`.
fn trim_end(s: &str) -> &str { s.trim_end_matches(js::is_space) }
/// 전역 정규식의 `.replace(re, (m, …) => …)` — 맞음마다 콜백의 글로(바꿔 넣는 글의 `$` 풀이 없음).
fn replace_with(re: &Regex, s: &str, mut f: impl FnMut(&Captures<'_>) -> String) -> String {
    let mut out = String::with_capacity(s.len());
    let mut last = 0;
    for c in re.captures_iter(s) {
        let m = c.get(0).expect("통째");
        out.push_str(&s[last..m.start()]);
        out.push_str(&f(&c));
        last = m.end();
    }
    out.push_str(&s[last..]);
    out
}
/// 맞은 무리의 글(참여하지 않았으면 None).
fn grp<'t>(c: &Captures<'t>, k: usize) -> Option<&'t str> { c.get(k).map(|m| m.as_str()) }
/// JS `a || b`.
fn or(a: V, b: V) -> V { js::or(a, b) }

/// 10줄 `esc(s)` — `String(s ?? '')`의 `& < > " '`를 HTML 개체로.
pub fn esc(s: &str) -> String {
    replace_with(re_esc(), s, |c| match &c[0] { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", _ => "&#39;" }.to_string())
}
/// `esc(v)`의 JS 값 꼴 — null · undefined는 빈 글, 그 밖은 `String(v)`.
pub fn esc_v(v: &V) -> String { if v.is_nullish() { String::new() } else { esc(&js::to_str(v).as_str()) } }

/// 13줄 `safeStyle(s)` — `String(s || '')`에서 위험한 말을 지우고 허락한 글자만 남겨 300자(UTF-16)까지.
pub fn safe_style(s: Option<&str>) -> String {
    let s = s.unwrap_or("");
    let a = re_style_bad().replace_all(s, "");
    let b = re_style_keep().replace_all(&a, "");
    Str::from(b.as_ref()).slice16(0.0, 300.0).as_str().into_owned()
}
/// 14줄 `safeColor(c)` — `#16진 3 ~ 8자` 또는 `영문 3 ~ 20자`면 그 글, 아니면 빈 글.
pub fn safe_color(c: &str) -> &str { if re_color_hex().is_match(c) || re_color_name().is_match(c) { c } else { "" } }
/// 15줄 `slug(s, i)` — 제목의 자리 이름 `wk-h<i>`.
pub fn slug(i: usize) -> String { format!("wk-h{i}") }

/// 18 ~ 31줄 `matchEnd(text, from, open, close)` — `from`의 여는 글에서 짝이 맞는 닫는 글 뒤의 자리(바이트 — 여는 · 닫는 글이 ASCII라 코드 단위 셈과 같은 곳). 없으면 None(JS −1).
pub fn match_end(text: &str, from: usize, open: &str, close: &str) -> Option<usize> {
    let (b, o, c) = (text.as_bytes(), open.as_bytes(), close.as_bytes());
    let mut depth = 0i64;
    let mut i = from;
    while i < b.len() {
        if b[i..].starts_with(o) {
            depth += 1;
            i += o.len() - 1;
        } else if b[i..].starts_with(c) {
            depth -= 1;
            i += c.len() - 1;
            if depth == 0 { return Some(i + 1); }
        }
        i += 1;
    }
    None
}

// ── 문서 그림(33 ~ 76줄) ──

/// 42줄 `namu.FIGURE` — 그림 기본 폭 · 띄울 때 글에 남기는 가장 작은 폭 · 띄우는 본문의 가장 작은 폭(새 앱의 `DocUi.figure*`와 같은 값).
pub const FIGURE: [(&str, u32); 4] = [("width", 340), ("gap", 24), ("minText", 280), ("narrow", 600)];

/// `[[파일:이름|width=…|align=…]]`의 속 → `{ name, width: '' | 'Npx' | 'N%', align: '' | 'left' | 'center' | 'right' }`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileSpec { pub name: String, pub width: String, pub align: String }

/// 44 ~ 55줄 `namu.fileSpec(inner)`.
pub fn file_spec(inner: &str) -> FileSpec {
    let parts: Vec<&str> = inner.split('|').collect();
    let mut o = FileSpec { name: trim(&re_file_head().replace(parts[0], "")).to_string(), width: String::new(), align: String::new() };
    for p in &parts[1..] {
        let Some(m) = re_file_opt().captures(trim(p)) else { continue };
        let v = trim(&m[2]).to_lowercase();
        let key = m[1].to_ascii_lowercase();
        let n = js::parse_int(&V::from(v.as_str()), 10);
        if key == "width" && re_file_width().is_match(&v) && n > 0.0 {
            o.width = if re_file_pct().is_match(&v) { format!("{}%", js::num_str(js::min(&[100.0, n]))) } else { format!("{}px", js::num_str(n)) };
        } else if key == "align" && re_file_align().is_match(&v) {
            o.align = v;
        }
    }
    o
}
/// 57 ~ 64줄 `namu.files(src)` — 본문의 그림 고리 목록(적힌 차례 · 같은 그림을 두 번 적으면 두 번).
pub fn files(src: &str) -> Vec<FileSpec> { re_file().captures_iter(src).map(|c| file_spec(&c[1])).collect() }

/// 66 ~ 76줄 `namu.figureHTML(spec, g)` — 그림 한 장의 HTML(g = 그림 사전의 그림 · 없으면 '그림 없음' 자리).
pub fn figure_html(spec: &FileSpec, g: &V) -> String {
    let pos = match spec.align.as_str() { "center" => "is-center", "left" => "is-left", _ => "is-right" };
    if !tv(g) || !tv(&g.get("src")) {
        return format!(r#"<figure class="wk-fig is-missing" data-wiki-img-missing="{0}"><span class="wk-fig-none">그림 없음 — {0}</span></figure>"#, esc(&spec.name));
    }
    let mut vars = Vec::new();
    if !spec.width.is_empty() { vars.push(format!("--fig-w:{}", spec.width)); }
    if tv(&g.get("width")) { vars.push(format!("--fig-nat:{}px", js::to_str(&g.get("width")))); }
    let caption = or(g.get("caption"), V::from(""));
    let credit = g.get("credit");
    let cap = if tv(&caption) || tv(&credit) {
        let cr = if tv(&credit) { format!(r#"<span class="wk-fig-credit">{}{}</span>"#, if tv(&caption) { " · " } else { "" }, esc_v(&credit)) } else { String::new() };
        format!("<figcaption>{}{cr}</figcaption>", esc_v(&caption))
    } else { String::new() };
    let size = if tv(&g.get("width")) && tv(&g.get("height")) { format!(r#" width="{}" height="{}""#, js::to_str(&g.get("width")), js::to_str(&g.get("height"))) } else { String::new() };
    let name = V::from(spec.name.as_str());
    let style = if vars.is_empty() { String::new() } else { format!(r#" style="{}""#, vars.join(";")) };
    format!(
        r#"<figure class="wk-fig {pos}"{style} data-wiki-img="{}"><button type="button" class="wk-fig-img" data-wiki-zoom title="누르면 크게"><img src="{}" alt="{}"{size} decoding="async"></button>{cap}</figure>"#,
        esc_v(&or(or(g.get("uid"), g.get("id")), name.clone())),
        esc_v(&g.get("src")),
        esc_v(&or(or(or(g.get("alt"), caption), g.get("name")), name)),
    )
}

// ── 렌더(106 ~ 442줄) ──

/// 고리 함수(`opts.link` — 이름 → `{ uid, missing, empty, title }` 꼴의 JS 값 · 거짓이면 `{}`로).
pub type LinkFn<'a> = &'a dyn Fn(&str) -> V;
/// 그림 함수(`opts.image` — 그림 이름 → 그림 사전의 그림 · 없으면 null).
pub type ImageFn<'a> = &'a dyn Fn(&str) -> V;

/// `namu.render(src, opts)`의 선택: 고리 · 그림 함수와 '오늘'(`now_ms` · `tz_min` — `[date]`는 UTC 날짜 · `[age(…)]`는 지역 날짜).
pub struct RenderOpts<'a> { pub link: Option<LinkFn<'a>>, pub image: Option<ImageFn<'a>>, pub now_ms: f64, pub tz_min: i32 }

/// 목차 한 줄 `{ level, id, text, lv, num }`(JS의 열쇠 차례).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Toc { pub level: usize, pub id: String, pub text: String, pub lv: usize, pub num: String }

/// `namu.render`의 답 `{ html, toc, categories }`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rendered { pub html: String, pub toc: Vec<Toc>, pub categories: Vec<String> }

impl Rendered {
    /// JS의 `{ html, toc, categories }` 값(열쇠 차례 그대로 — `js::stringify`가 `JSON.stringify`와 같은 글을 낸다).
    pub fn to_js(&self) -> V {
        let toc: Vec<V> = self.toc.iter().map(|h| {
            let o = Obj::new();
            o.set("level", V::from(h.level));
            o.set("id", V::from(h.id.as_str()));
            o.set("text", V::from(h.text.as_str()));
            o.set("lv", V::from(h.lv));
            o.set("num", V::from(h.num.as_str()));
            V::Obj(o)
        }).collect();
        let o = Obj::new();
        o.set("html", V::from(self.html.as_str()));
        o.set("toc", V::Arr(js::Arr::new(toc)));
        o.set("categories", V::Arr(js::Arr::new(self.categories.iter().map(|c| V::from(c.as_str())).collect())));
        V::Obj(o)
    }
}

/// 각주 `{ id, label, html }`.
struct Foot { id: usize, label: String, html: String }

/// 렌더 하나의 상태(JS `namu.render` 안의 `foot` · `toc` · `categories` · `blocks`와 선택).
struct Ren<'a> {
    link: Option<LinkFn<'a>>,
    image: Option<ImageFn<'a>>,
    now_ms: f64,
    tz_min: i32,
    foot: Vec<Foot>,
    toc: Vec<Toc>,
    categories: Vec<String>,
    blocks: Vec<String>,
}

/// 172줄 `.replace(/(^|[^-])--([^-\n][^\n]*?[^-\n]|[^-\n])--(?!-)/g, '$1<s>$2</s>')` — 앞보기 `(?!-)`가 regex에 없어 손으로.
/// JS처럼 UTF-16 코드 단위로 자리마다 되짚기 차례(무리 1: `^` → `[^-]` · 무리 2: 긴 꼴(가운데를 짧은 것부터) → 한 글자 꼴)대로 찾는다.
pub fn dash(s: &str) -> String {
    let u: Vec<u16> = s.encode_utf16().collect();
    let mut out: Vec<u16> = Vec::with_capacity(u.len() + 16);
    let (mut last, mut i) = (0usize, 0usize);
    while i <= u.len() {
        match dash_at(&u, i) {
            Some((g1, g2, end)) => {
                out.extend_from_slice(&u[last..i]);
                out.extend_from_slice(&u[g1.0..g1.1]);
                out.extend("<s>".encode_utf16());
                out.extend_from_slice(&u[g2.0..g2.1]);
                out.extend("</s>".encode_utf16());
                last = end;
                i = end;
            }
            None => i += 1,
        }
    }
    out.extend_from_slice(&u[last..]);
    String::from_utf16_lossy(&out)
}
/// [`dash`]의 한 자리 `i`에서의 맞음 → (무리 1, 무리 2, 끝).
fn dash_at(u: &[u16], i: usize) -> Option<((usize, usize), (usize, usize), usize)> {
    const D: u16 = 0x2D;
    const NL: u16 = 0x0A;
    let at = |k: usize| u.get(k).copied();
    let close = |k: usize| at(k) == Some(D) && at(k + 1) == Some(D) && at(k + 2) != Some(D); // `--(?!-)`
    let mut g1s = Vec::with_capacity(2);
    if i == 0 { g1s.push((i, i)); }
    if i < u.len() && u[i] != D { g1s.push((i, i + 1)); }
    for g1 in g1s {
        if !(at(g1.1) == Some(D) && at(g1.1 + 1) == Some(D)) { continue; }
        let p = g1.1 + 2;
        let first_ok = matches!(at(p), Some(c) if c != D && c != NL);
        if first_ok {
            // 긴 꼴 `[^-\n][^\n]*?[^-\n]` — 가운데(p+1 .. k)를 빈 것부터 늘리며 끝 글자 u[k]를 본다
            let mut k = p + 1;
            while k < u.len() {
                if u[k] != D && u[k] != NL && close(k + 1) { return Some((g1, (p, k + 1), k + 3)); }
                if u[k] == NL { break; }
                k += 1;
            }
            // 한 글자 꼴 `[^-\n]`
            if close(p + 1) { return Some((g1, (p, p + 1), p + 3)); }
        }
    }
    None
}

/// 339줄 `line.match(/^(={1,6})(#?) (.+?) \2\1\s*$/)` → (무리 1, 무리 2, 무리 3). 뒤참조 `\2\1`이 regex에 없어 손으로 —
/// 되짚기 차례 그대로(무리 1은 긴 것부터 · 무리 2는 `#`부터 · 무리 3은 짧은 것부터 · `.`은 줄 끝 넷을 뺀 글자).
pub fn heading(line: &str) -> Option<(&str, &str, &str)> {
    let b = line.as_bytes();
    let run = b.iter().take_while(|&&c| c == b'=').count();
    for n in (1..=run.min(6)).rev() {
        let hashes: &[usize] = if b.get(n) == Some(&b'#') { &[1, 0] } else { &[0] };
        for &h in hashes {
            if b.get(n + h) != Some(&b' ') { continue; }
            let start = n + h + 1;
            let close = format!(" {}{}", &line[n..n + h], &line[..n]);
            for (off, c) in line[start..].char_indices() {
                if matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}') { break; }
                let e = start + off + c.len_utf8();
                if line[e..].starts_with(&close) && line[e + close.len()..].chars().all(js::is_space) {
                    return Some((&line[..n], &line[n..n + h], &line[start..e]));
                }
            }
        }
    }
    None
}

/// `new Date(y, m0, d)`(지역)의 날 수 — 달 · 날 넘침을 MakeDay처럼 풀고, 0 ~ 99년은 1900년대로(`Date` 생성자의 뜻 — 달 넘침보다 먼저: `0099-13-01`은 2000-01-01).
/// 판정 R61(끝 전체 검토 ② M5 '0 ~ 99년이 JS와 다름') 확인: 이 셈과 [`Ren::age`]는 처음부터 1900을 더했다 — 해 0 ~ 130 · 달 0 ~ 99 · 날 0 ~ 99를 시각 넷에서
/// 진짜 `Date`(Asia/Seoul)와 맞춰 본 524만 갈래가 모두 같았고(2026-10-22), 벡터 `js-vectors.mjs` wiki 렌더의 `나이 0 ~ 99년` 줄(경계 0 · 99 · 100 · 달 넘침 · 모자람 · 없는 윤날)이 지킨다.
fn make_day(y: i64, m0: i64, d: i64) -> i64 {
    let yr = if (0..=99).contains(&y) { 1900 + y } else { y };
    days_from_civil(yr + m0.div_euclid(12), m0.rem_euclid(12) + 1, 1) + d - 1
}

impl Ren<'_> {
    /// 113 ~ 116줄 `keep(html)` — 자리표시자 `\x01<n>\x01`.
    fn keep(&mut self, html: String) -> String {
        self.blocks.push(html);
        format!("\u{1}{}\u{1}", self.blocks.len() - 1)
    }
    /// 117줄 `restore(html)` — 자리표시자를 그 HTML로(`blocks[Number(i)]` — 없는 자리는 `undefined`).
    fn restore(&self, html: &str) -> String {
        replace_with(re_restore(), html, |c| {
            let i: f64 = c[1].parse().unwrap_or(f64::NAN);
            if i < self.blocks.len() as f64 { self.blocks[i as usize].clone() } else { "undefined".into() }
        })
    }
    /// 177줄 `new Date().toISOString().slice(0, 10)` — UTC 날짜(시간대와 무관).
    fn iso_date(&self) -> String {
        let (y, m, d) = js::local_ymd(self.now_ms, 0);
        let ys = if (0..=9999).contains(&y) { format!("{y:04}") } else if y < 0 { format!("-{:06}", -i64::from(y)) } else { format!("+{y:06}") };
        Str::from(format!("{ys}-{m:02}-{d:02}")).slice16(0.0, 10.0).as_str().into_owned()
    }
    /// 178 ~ 184줄 `[age(y-m-d)]` — 지역 날짜로 만 나이(오늘이 올해 생일 0시 앞이면 하나 덜).
    fn age(&self, y: &str, mo: &str, d: &str) -> String {
        let num = |t: &str| t.parse::<i64>().expect("숫자만 맞음");
        let (by, bm, bd) = civil_from_days(make_day(num(y), num(mo) - 1, num(d)));
        let (ny, _, _) = js::local_ymd(self.now_ms, self.tz_min);
        let ny = i64::from(ny);
        let mut age = ny - by;
        let today = ((self.now_ms + f64::from(self.tz_min) * 60_000.0) / 86_400_000.0).floor() as i64;
        if today < days_from_civil(ny, bm, 1) + bd - 1 { age -= 1; } // now < new Date(올해, b의 달, b의 날)
        age.to_string()
    }

    /// 120 ~ 146줄 `inline(raw)` — 이스케이프 → `{{{…}}}` 인라인을 자리표시자로 → 각주 `[* …]`(대괄호 짝) → [`Ren::inline_no_foot`].
    fn inline(&mut self, raw: &str) -> String {
        let e = esc(raw);
        let s = replace_with(re_brace(), &e, |c| { let h = self.brace_inline(&c[1]); self.keep(h) });
        let mut out = String::with_capacity(s.len());
        let mut i = 0;
        while i < s.len() {
            if s[i..].starts_with("[*") {
                if let Some(end) = match_end(&s, i, "[", "]") {
                    let inner = &s[i + 2..end - 1];
                    let m = re_fn_inner().captures(inner);
                    let m1 = m.as_ref().and_then(|m| grp(m, 1)).filter(|x| !x.is_empty());
                    let m2 = m.as_ref().map(|m| grp(m, 2).unwrap_or(""));
                    let label = m1.map_or_else(|| (self.foot.len() + 1).to_string(), str::to_string);
                    let existing = m1.and_then(|x| self.foot.iter().position(|f| f.label == x));
                    let id = existing.map_or(self.foot.len() + 1, |k| self.foot[k].id);
                    if existing.is_none() {
                        let html = self.inline_no_foot(m2.unwrap_or(inner));
                        self.foot.push(Foot { id, label: label.clone(), html });
                    }
                    let title = esc(&m2.map_or(String::new(), |t| re_tag().replace_all(t, "").into_owned()));
                    out.push_str(&format!(r##"<sup class="wk-fn" id="wk-rfn-{id}"><a href="#wk-fn-{id}" data-wiki-fn="{id}" title="{title}">[{}]</a></sup>"##, esc(&label)));
                    i = end;
                    continue;
                }
            }
            let ch = s[i..].chars().next().expect("글자");
            out.push(ch);
            i += ch.len_utf8();
        }
        self.inline_no_foot(&out)
    }

    /// 150 ~ 166줄 고리 `[[…]]` 하나의 HTML.
    fn link_html(&mut self, c: &Captures<'_>) -> String {
        let target = trim(&c[1]).to_string();
        let shown = match grp(c, 2) { Some(l) => l.to_string(), None => re_link_figure().replace(&target, "").into_owned() };
        let text = if trim(&shown).is_empty() { target.clone() } else { trim(&shown).to_string() };
        if re_link_cat().is_match(&target) {
            self.categories.push(trim(target.split(':').nth(1).unwrap_or("")).to_string());
            return String::new();
        }
        if re_link_file().is_match(&target) { return String::new(); }
        if re_link_http().is_match(&target) || re_link_proto().is_match(&target) {
            return format!(r#"<a class="wk-ext" href="{target}" target="_blank" rel="noopener noreferrer">{text}</a>"#);
        }
        let anchor: Vec<&str> = target.split('#').collect();
        let name = trim(anchor[0]);
        if name.is_empty() { return format!(r##"<a class="wk-link" href="#{}">{text}</a>"##, esc(anchor.get(1).copied().unwrap_or(""))); }
        let r = or(self.link.map_or(V::Undef, |f| f(name)), V::Obj(Obj::new()));
        let missing = tv(&r.get("missing")) || !tv(&r.get("uid"));
        let empty = tv(&r.get("empty"));
        let cls = if missing { " is-missing" } else if empty { " is-empty" } else { "" };
        let why = if missing { " — 연표에 없는 항목" } else if empty { " — 아직 문서 없음" } else { "" };
        let nv = V::from(name);
        format!(
            r#"<a class="wk-link{cls}" data-wiki-link="{}" data-wiki-name="{}" title="{}{why}">{text}</a>"#,
            esc_v(&or(r.get("uid"), nv.clone())), esc(name), esc_v(&or(r.get("title"), nv)),
        )
    }

    /// 147 ~ 189줄 `inlineNoFoot(s)` — 고리 · 글꼴 · 날짜 · 나이 · 틀 · 목차 · 각주 자리.
    fn inline_no_foot(&mut self, s: &str) -> String {
        let s = replace_with(re_link(), s, |c| self.link_html(c));
        let s = re_bold().replace_all(&s, T_BOLD).into_owned();
        let s = re_italic().replace_all(&s, T_ITALIC).into_owned();
        let s = re_strike().replace_all(&s, T_STRIKE).into_owned();
        let s = dash(&s);
        let s = re_under().replace_all(&s, T_UNDER).into_owned();
        let s = re_sup().replace_all(&s, T_SUP).into_owned();
        let s = re_sub().replace_all(&s, T_SUB).into_owned();
        let s = re_br().replace_all(&s, T_BR).into_owned();
        let today = esc(&self.iso_date());
        let s = re_date().replace_all(&s, NoExpand(&today)).into_owned();
        let s = replace_with(re_age(), &s, |c| self.age(&c[1], &c[2], &c[3]));
        let s = re_macro().replace_all(&s, "").into_owned();
        let s = re_toc().replace_all(&s, NoExpand(T_TOC)).into_owned();
        re_foot().replace_all(&s, NoExpand(T_FOOT)).into_owned()
    }

    /// 190 ~ 200줄 `braceInline(body)` — `{{{+2 …}}}` 크기 · `{{{#색 …}}}` 색 · 여러 줄이면 `<pre>` · 아니면 `<code>`(body는 이미 이스케이프됨).
    fn brace_inline(&mut self, body: &str) -> String {
        if let Some(m) = re_size().captures(body) {
            let inner = self.inline_no_foot(&m[3]);
            return format!(r#"<span class="wk-size {}{}">{inner}</span>"#, if &m[1] == "+" { "p" } else { "m" }, &m[2]);
        }
        if let Some(m) = re_color().captures(body) {
            let color = if re_color_ishex().is_match(&m[1]) { format!("#{}", &m[1]) } else { m[1].to_string() };
            if !safe_color(&color).is_empty() {
                let inner = self.inline_no_foot(&m[2]);
                return format!(r#"<span style="color:{color}">{inner}</span>"#);
            }
        }
        if body.contains('\n') { return format!(r#"<pre class="wk-pre">{body}</pre>"#); }
        format!(r#"<code class="wk-code">{body}</code>"#)
    }

    /// 203 ~ 240줄 `extractBlocks(text)` — `{{{#!folding` · `#!wiki` · `#!syntax` · `#!html` · 여러 줄 크기 · 여러 줄 코드를 자리표시자로(인라인 `{{{ }}}`는 그대로).
    fn extract_blocks(&mut self, text: &str) -> String {
        let mut out = String::new();
        let mut i = 0;
        while i < text.len() {
            let Some(at) = text[i..].find("{{{").map(|k| k + i) else { out.push_str(&text[i..]); break };
            let Some(end) = match_end(text, at, "{{{", "}}}") else { out.push_str(&text[i..]); break };
            let body = &text[at + 3..end - 3];
            let mut html = None;
            if let Some(h) = re_block_head().captures(body) {
                let kind = &h[1];
                let arg = trim(&h[2]);
                let inner = grp(&h, 3).unwrap_or("");
                html = Some(match kind {
                    "folding" => {
                        let summary = self.inline(if arg.is_empty() { "펼치기" } else { arg });
                        let b = self.block(inner);
                        format!(r#"<details class="wk-fold"><summary>{summary}</summary><div class="wk-fold-body">{b}</div></details>"#)
                    }
                    "wiki" => {
                        let st = re_box_style().captures(arg).map(|c| grp(&c, 1).unwrap_or("").to_string());
                        let style = esc(&safe_style(st.as_deref()));
                        let b = self.block(inner);
                        format!(r#"<div class="wk-box" style="{style}">{b}</div>"#)
                    }
                    "syntax" => format!(r#"<pre class="wk-pre" data-lang="{}">{}</pre>"#, esc(arg), esc(inner)),
                    _ => format!(r#"<pre class="wk-pre">{}</pre>"#, esc(inner)), // #!html은 안전을 위해 그대로 보여 줍니다
                });
            } else if body.contains('\n') {
                html = Some(match re_size().captures(body) {
                    Some(m) => { let b = self.block(&m[3]); format!(r#"<div class="wk-size {}{}">{b}</div>"#, if &m[1] == "+" { "p" } else { "m" }, &m[2]) }
                    None => format!(r#"<pre class="wk-pre">{}</pre>"#, esc(body)),
                });
            }
            match html {
                None => out.push_str(&text[i..end]), // 인라인 {{{ }}}는 inline()이 처리
                Some(h) => { out.push_str(&text[i..at]); let k = self.keep(h); out.push_str(&k); }
            }
            i = end;
        }
        out
    }

    /// 243 ~ 305줄 `table(lines)` — `|| 칸 ||` 표(칸 선택 `<-2>` · `<|2>` · `<bgcolor=…>` · 정렬 · 앞뒤 빈칸 정렬).
    fn table(&mut self, lines: &[&str]) -> String {
        let mut rows: Vec<String> = Vec::new();
        let mut cur = String::new();
        for l in lines {
            cur = if cur.is_empty() { (*l).to_string() } else { format!("{cur}\n{l}") };
            if trim_end(&cur).ends_with("||") { rows.push(std::mem::take(&mut cur)); }
        }
        if !cur.is_empty() { rows.push(cur); }
        let (mut table_style, mut table_align) = (String::new(), String::new());
        let mut html = String::new();
        for r in &rows {
            let inner = Str::from(trim(r)).slice16(2.0, -2.0).as_str().into_owned();
            let mut row_style = String::new();
            let mut tds = String::new();
            for cell0 in inner.split("||") {
                let mut cell = cell0.to_string();
                let (mut colspan, mut rowspan) = (1.0f64, 1.0f64);
                let (mut style, mut align) = (String::new(), String::new());
                loop {
                    let Some((whole, opt)) = re_cell_opt().captures(&cell).map(|m| (m[0].to_string(), trim(&m[1]).to_string())) else { break };
                    cell = cell[whole.len()..].to_string();
                    let cap = |re: &Regex| re.captures(&opt).map(|m| m[1].to_string());
                    let safe = |v: &String| !safe_color(v).is_empty();
                    let num = |t: String| t.parse::<f64>().unwrap_or(f64::NAN);
                    if let Some(v) = cap(re_cell_colspan()) { colspan = num(v); }
                    else if let Some(v) = cap(re_cell_rowspan()) { rowspan = num(v); }
                    else if let Some(v) = cap(re_cell_rowspan2()) { rowspan = num(v); }
                    else if opt == "(" { align = "left".into(); }
                    else if opt == ":" { align = "center".into(); }
                    else if opt == ")" { align = "right".into(); }
                    else if let Some(v) = cap(re_cell_bgcolor()).filter(safe) { style += &format!("background:{v};"); }
                    else if let Some(v) = cap(re_cell_color()).filter(safe) { style += &format!("color:{v};"); }
                    else if let Some(v) = cap(re_cell_width()) { style += &format!("width:{v};"); }
                    else if let Some(v) = cap(re_cell_height()) { style += &format!("height:{v};"); }
                    else if let Some(v) = cap(re_cell_rowbgcolor()).filter(safe) { row_style += &format!("background:{v};"); }
                    else if let Some(v) = cap(re_cell_rowcolor()).filter(safe) { row_style += &format!("color:{v};"); }
                    else if let Some(v) = cap(re_cell_table_bgcolor()).filter(safe) { table_style += &format!("background:{v};"); }
                    else if let Some(v) = cap(re_cell_table_bordercolor()).filter(safe) { table_style += &format!("border-color:{v};"); }
                    else if let Some(v) = cap(re_cell_table_width()) { table_style += &format!("width:{v};"); }
                    else if let Some(v) = cap(re_cell_table_align()) { table_align = v; }
                    else if re_cell_skip().is_match(&opt) { /* 무시 */ }
                    else { cell = whole + &cell; break; } // 옵션이 아니면 글자로 되돌립니다
                }
                // 앞뒤 공백으로 정렬 (나무위키 관행)
                if align.is_empty() {
                    let l = re_cell_lead().is_match(&cell);
                    let rr = re_cell_trail().is_match(&cell);
                    align = if l && rr { "center" } else if l { "right" } else { "" }.into();
                }
                let style = format!("{style}{}", if align.is_empty() { String::new() } else { format!("text-align:{align};") });
                let cs = if colspan > 1.0 { format!(r#" colspan="{}""#, js::num_str(colspan)) } else { String::new() };
                let rs = if rowspan > 1.0 { format!(r#" rowspan="{}""#, js::num_str(rowspan)) } else { String::new() };
                let st = if style.is_empty() { String::new() } else { format!(r#" style="{}""#, esc(&style)) };
                let body = self.inline(trim(&cell));
                tds += &format!("<td{cs}{rs}{st}>{}</td>", re_nl().replace_all(&body, T_BR));
            }
            let rs = if row_style.is_empty() { String::new() } else { format!(r#" style="{}""#, esc(&row_style)) };
            html += &format!("<tr{rs}>{tds}</tr>");
        }
        let ta = if table_align.is_empty() { String::new() } else { format!(" is-{table_align}") };
        let ts = if table_style.is_empty() { String::new() } else { format!(r#" style="{}""#, esc(&table_style)) };
        format!(r#"<div class="wk-table-wrap{ta}"><table class="wk-table"{ts}>{html}</table></div>"#)
    }

    /// 312 ~ 315줄 `flush()` — 모아 둔 문단 줄을 `<p>`로.
    fn flush(&mut self, html: &mut String, para: &mut Vec<String>) {
        if !para.is_empty() {
            let parts: Vec<String> = para.iter().map(|l| self.inline(l)).collect();
            html.push_str(&format!("<p>{}</p>", parts.join("<br>")));
        }
        para.clear();
    }

    /// 308 ~ 396줄 `block(text)` — 줄마다: 빈 줄 · 자리표시자 줄 · `[각주]` · `[목차]` · 제목 · 가로줄 · 표 · 인용 · 목록 · 그림 줄 · 문단.
    fn block(&mut self, text: &str) -> String {
        let normalized = re_crlf().replace_all(text, "\n");
        let extracted = self.extract_blocks(&normalized);
        let lines: Vec<&str> = extracted.split('\n').collect();
        let mut html = String::new();
        let mut para: Vec<String> = Vec::new();
        let mut i = 0;
        while i < lines.len() {
            let line = lines[i];
            if trim(line).is_empty() { self.flush(&mut html, &mut para); i += 1; continue; }
            // 한 줄이 통째로 블록(접기·상자·코드) 자리표시자이거나 [각주]·[목차]면 문단 밖에 둡니다
            if re_block_ph().is_match(line) { self.flush(&mut html, &mut para); html.push_str(trim(line)); i += 1; continue; }
            if re_block_foot().is_match(line) { self.flush(&mut html, &mut para); html.push_str(T_FOOT); i += 1; continue; }
            if re_block_toc().is_match(line) { self.flush(&mut html, &mut para); html.push_str(T_TOC); i += 1; continue; }
            if let Some((eq, _, title)) = heading(line) {
                self.flush(&mut html, &mut para);
                let level = eq.len();
                let id = slug(self.toc.len() + 1);
                let text = replace_with(re_link(), title, |c| match grp(c, 2) { Some(l) if !l.is_empty() => l.to_string(), _ => c[1].to_string() });
                self.toc.push(Toc { level, id: id.clone(), text, lv: 0, num: String::new() });
                let tag = (level + 1).min(6);
                let n = self.toc.len();
                let inner = self.inline(title);
                html.push_str(&format!(r#"<h{tag} class="wk-h" id="{id}"><span class="wk-hnum" data-toc="{n}"></span>{inner}</h{tag}>"#));
                i += 1;
                continue;
            }
            if re_hr().is_match(line) { self.flush(&mut html, &mut para); html.push_str(r#"<hr class="wk-hr">"#); i += 1; continue; }
            if re_table_line().is_match(line) {
                self.flush(&mut html, &mut para);
                let mut tl: Vec<&str> = Vec::new();
                while i < lines.len() && (re_table_line().is_match(lines[i]) || tl.last().is_some_and(|l| !trim_end(l).ends_with("||"))) { tl.push(lines[i]); i += 1; }
                let t = self.table(&tl);
                html.push_str(&t);
                continue;
            }
            if re_quote().is_match(line) {
                self.flush(&mut html, &mut para);
                let mut ql: Vec<String> = Vec::new();
                while i < lines.len() && re_quote().is_match(lines[i]) { ql.push(re_quote_head().replace(lines[i], "").into_owned()); i += 1; }
                let inner = self.block(&ql.join("\n"));
                html.push_str(&format!(r#"<blockquote class="wk-quote">{inner}</blockquote>"#));
                continue;
            }
            if re_list().is_match(line) {
                self.flush(&mut html, &mut para);
                let mut items: Vec<(usize, String, String)> = Vec::new();
                while i < lines.len() {
                    let Some(m) = re_list().captures(lines[i]) else { break };
                    items.push((m[1].len(), m[2].to_string(), grp(&m, 3).unwrap_or("").to_string()));
                    i += 1;
                    // 들여쓴 이어지는 줄은 같은 항목의 계속
                    while i < lines.len() && re_list_more().is_match(lines[i]) && !re_list_head().is_match(lines[i]) {
                        let more = trim(lines[i]);
                        if let Some(last) = items.last_mut() { last.2.push('\n'); last.2.push_str(more); }
                        i += 1;
                    }
                }
                let l = self.list(&items);
                html.push_str(&l);
                continue;
            }
            if let Some(image) = self.image {
                if re_image_line().is_match(line) {
                    // 문서 그림: 그 줄 앞에서 문단을 끊고 그림을 놓은 뒤, 그림 고리를 뺀 나머지 글을 새 문단으로 이어 씁니다
                    self.flush(&mut html, &mut para);
                    let rest = replace_with(re_file(), line, |c| {
                        let spec = file_spec(&c[1]);
                        let g = if spec.name.is_empty() { V::Null } else { image(&spec.name) };
                        html.push_str(&figure_html(&spec, &g));
                        String::new()
                    });
                    if !trim(&rest).is_empty() { para.push(rest); }
                    i += 1;
                    continue;
                }
            }
            para.push(line.to_string());
            i += 1;
        }
        self.flush(&mut html, &mut para);
        html
    }

    /// 397 ~ 415줄 `list(items)` — 들여쓰기 깊이로 겹 목록(같은 깊이에서 종류가 바뀌면 새 목록).
    fn list(&mut self, items: &[(usize, String, String)]) -> String {
        fn type_of(mk: &str) -> &'static str {
            if mk == "*" { "ul" } else if mk.starts_with('a') { r#"ol type="a""# } else if mk.starts_with('A') { r#"ol type="A""# }
            else if mk.starts_with('i') { r#"ol type="i""# } else if mk.starts_with('I') { r#"ol type="I""# } else { "ol" }
        }
        let tag_of = |mk: &str| type_of(mk).split(' ').next().unwrap_or("");
        let mut html = String::new();
        let mut stack: Vec<(usize, &'static str)> = Vec::new();
        for (indent, marker, text) in items {
            while stack.last().is_some_and(|s| s.0 > *indent) { let t = stack.pop().expect("있음").1; html += &format!("</li></{t}>"); }
            // 같은 깊이인데 목록 종류가 바뀌면(* → 1.) 새 목록을 시작합니다
            if stack.last().is_some_and(|s| s.0 == *indent && s.1 != tag_of(marker)) { let t = stack.pop().expect("있음").1; html += &format!("</li></{t}>"); }
            if stack.last().is_none_or(|s| s.0 < *indent) {
                let tag = type_of(marker);
                let start = re_list_start().captures(marker).map(|c| c[1].to_string());
                html += &format!(r#"<{tag}{} class="wk-list">"#, start.map_or(String::new(), |s| format!(r#" start="{s}""#)));
                stack.push((*indent, tag_of(marker)));
            } else {
                html += "</li>";
            }
            let inner = self.inline(text);
            html += &format!("<li>{}", re_nl().replace_all(&inner, T_BR));
        }
        while let Some((_, t)) = stack.pop() { html += &format!("</li></{t}>"); }
        html
    }
}

/// 106 ~ 442줄 `namu.render(src, opts)` → `{ html, toc, categories }`. JS라면 던졌을 곳(목차 자리 번호가 목차 밖 — 사용자 글로는 생기지 않음)은 오류.
pub fn render(src: &str, opts: &RenderOpts<'_>) -> crate::Result<Rendered> {
    let mut r = Ren { link: opts.link, image: opts.image, now_ms: opts.now_ms, tz_min: opts.tz_min, foot: Vec::new(), toc: Vec::new(), categories: Vec::new(), blocks: Vec::new() };
    let mut html = r.block(src);
    /* 목차 번호는 문서에서 가장 큰 제목 단계를 1로 잡습니다 (== ==로 시작하면 1. 2. 3.) */
    let min_l = r.toc.iter().map(|h| h.level).min().unwrap_or(1);
    let mut counters: Vec<Option<u64>> = Vec::new();
    for h in &mut r.toc {
        let lv = h.level - min_l + 1;
        h.lv = lv;
        counters.resize(lv, None); // counters.length = lv
        counters[lv - 1] = Some(counters[lv - 1].unwrap_or(0) + 1);
        for c in counters.iter_mut().take(lv - 1) { if c.unwrap_or(0) == 0 { *c = Some(1); } }
        h.num = counters[..lv].iter().map(|c| c.unwrap_or(0).to_string()).collect::<Vec<_>>().join(".");
    }
    let toc_html = if r.toc.is_empty() { String::new() } else {
        let items: String = r.toc.iter().map(|h| format!(r##"<li class="lv{}"><a href="#{}" data-wiki-anchor="{}"><span>{}.</span> {}</a></li>"##, h.lv, h.id, h.id, h.num, esc(&h.text))).collect();
        format!(r#"<nav class="wk-toc"><b>목차</b><ol>{items}</ol></nav>"#)
    };
    let mut fault = None;
    html = replace_with(re_hnum(), &html, |c| {
        let n: f64 = c[1].parse().unwrap_or(f64::NAN);
        match r.toc.get((n - 1.0) as usize).filter(|_| n >= 1.0 && n.is_finite()) {
            Some(h) => format!(r#"<span class="wk-hnum">{}.</span> "#, h.num),
            None => { fault.get_or_insert_with(|| format!("TypeError: 목차 자리 {} — 목차 밖(toc[{}])", &c[1], n - 1.0)); String::new() }
        }
    });
    if let Some(e) = fault { return Err(e.into()); }
    let foot_html = if r.foot.is_empty() { String::new() } else {
        let items: String = r.foot.iter().map(|f| format!(r##"<li id="wk-fn-{0}"><a href="#wk-rfn-{0}" data-wiki-anchor="wk-rfn-{0}">[{1}]</a> {2}</li>"##, f.id, esc(&f.label), f.html)).collect();
        format!(r#"<ol class="wk-footnotes">{items}</ol>"#)
    };
    let has_foot_tag = html.contains(T_FOOT);
    html = re_toc_ph().replace_all(&html, NoExpand(&toc_html)).into_owned();
    html = re_foot_ph().replace_all(&html, NoExpand(&foot_html)).into_owned();
    if !has_foot_tag && !foot_html.is_empty() { html += &foot_html; }
    if !r.categories.is_empty() {
        html += &format!(r#"<div class="wk-cats">분류: {}</div>"#, r.categories.iter().map(|c| format!("<span>{}</span>", esc(c))).collect::<Vec<_>>().join(" · "));
    }
    let once = r.restore(&html);
    let html = r.restore(&once);
    Ok(Rendered { html, toc: r.toc, categories: r.categories })
}

/// 445 ~ 453줄 `namu.links(src)` — 문서 안의 `[[링크]]` 이름 목록(처음 나온 차례 · 겹침 없이 — 분류 · 파일 · 이미지 · 바깥 고리는 뺌).
pub fn links(src: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for c in re_links().captures_iter(src) {
        let name = trim(c[1].split('#').next().unwrap_or(""));
        if !name.is_empty() && !re_links_skip().is_match(name) && !out.iter().any(|x| x == name) { out.push(name.to_string()); }
    }
    out
}

// ── 도움말 · 도구줄(456 ~ 511줄) ──

/// 456 ~ 471줄 `namu.HELP` — 문법 도움말.
pub const HELP: &str = "== 제목 == (=의 개수로 단계, 2~6개)
'''굵게''' ''기울임'' ~~취소~~ __밑줄__ ^^위첨자^^ ,,아래첨자,,
[[다른 문서]] · [[문서|표시할 글자]] · [[https://…|바깥 링크]]
[[조선/역사]] 하위 문서 · [[/역사]] 지금 문서의 하위 문서 · [[김홍집 내각]] 내각·지도자·연호 칸 문서
[* 각주 내용] · [*가 이름 있는 각주] · [각주] 자리에 각주 목록
 * 목록 (앞에 띄어쓰기 한 칸 이상)
 1. 번호 목록 · 1.#5 5부터
> 인용문
---- 가로줄
|| 칸 || 칸 || (표) · <-2> 가로 합치기 · <|2> 세로 합치기 · <bgcolor=#eee> 배경 · <(> <:> <)> 정렬
{{{#!folding 제목
접히는 내용 }}}
{{{+2 크게}}} {{{-1 작게}}} {{{#red 빨강}}} {{{코드}}}
[목차] [br] [age(1900-01-01)] [date]
[[분류:이름]] 문서 분류
[[파일:그림 이름]] 문서 그림 (오른쪽에 띄움) · |align=center 가운데 · |width=50% 크기";

/// 472 ~ 477줄 `namu.SHORTCUTS` — [단축키, 하는 일].
pub const SHORTCUTS: [(&str, &str); 18] = [
    ("Ctrl+B", "굵게"), ("Ctrl+I", "기울임"), ("Ctrl+U", "밑줄"), ("Ctrl+D", "취소선"), ("Ctrl+K", "[[링크]] (이름 자동 완성)"), ("Ctrl+Shift+K", "바깥 링크"),
    ("Ctrl+1 · 2 · 3", "== 제목 == · === === · ==== ===="), ("Ctrl+L", " * 목록"), ("Ctrl+Shift+L", " 1. 번호 목록"), ("Ctrl+Q", "> 인용"),
    ("Ctrl+Shift+F", "[* 각주]"), ("Ctrl+Shift+T", "|| 표 ||"), ("Ctrl+Shift+D", "{{{#!folding 접기}}}"), ("Ctrl+E", "{{{코드}}}"), ("Ctrl+S", "저장"),
    ("[[ 입력", "연표의 시대·사건·민족·칸 이름 자동 완성 (↑↓ Enter)"), ("Tab · Shift+Tab", "목록 들여쓰기 · 내어쓰기"), ("Enter", "목록·인용 줄에서 다음 줄도 이어 감 (빈 항목에서 Enter면 끝)"),
];

/// 493 ~ 499줄 `SNIP` — 문법 넣기의 [앞, 뒤].
fn snip(k: &str) -> (&'static str, &'static str) {
    match k {
        "h2" => ("== ", " =="), "h3" => ("=== ", " ==="), "h4" => ("==== ", " ===="),
        "b" => ("'''", "'''"), "i" => ("''", "''"), "s" => ("~~", "~~"), "u" => ("__", "__"), "sup" => ("^^", "^^"), "sub" => (",,", ",,"),
        "link" => ("[[", "]]"), "ext" => ("[[https://", "|링크 이름]]"), "fn" => ("[* ", "]"), "code" => ("{{{", "}}}"),
        "table" => ("|| 칸 || 칸 ||\n|| 칸 || 칸 ||", ""), "fold" => ("{{{#!folding 제목\n", "\n}}}"), "list" => (" * ", ""), "olist" => (" 1. ", ""), "quote" => ("> ", ""),
        "hr" => ("----", ""), "toc" => ("[목차]", ""), "big" => ("{{{+1 ", "}}}"), "small" => ("{{{-1 ", "}}}"), "color" => ("{{{#c0392b ", "}}}"), "br" => ("[br]", ""),
        _ => ("", ""),
    }
}
/// 502 ~ 506줄 `TOOLBAR` — [넣을 것, 단추 글, 단축키].
const TOOLBAR: [(&str, &str, &str); 15] = [
    ("h2", "제목", "Ctrl+1"), ("b", "<b>굵게</b>", "Ctrl+B"), ("i", "<i>기울임</i>", "Ctrl+I"), ("u", "<u>밑줄</u>", "Ctrl+U"), ("s", "<s>취소</s>", "Ctrl+D"),
    ("link", "[[링크]]", "Ctrl+K"), ("fn", "각주", "Ctrl+Shift+F"), ("list", "목록", "Ctrl+L"), ("olist", "1. 번호", "Ctrl+Shift+L"), ("quote", "인용", "Ctrl+Q"),
    ("table", "표", "Ctrl+Shift+T"), ("fold", "접기", "Ctrl+Shift+D"), ("code", "코드", "Ctrl+E"), ("toc", "목차", ""), ("hr", "가로줄", ""),
];
/// 508 ~ 511줄 `namu.toolbarHTML({ compact, image })` — 도구줄 단추(`compact`면 목차 · 가로줄 · 코드를 빼고, `image`면 '표' 옆에 그림 단추).
pub fn toolbar_html(compact: bool, image: bool) -> String {
    let mut out = String::new();
    for (k, label, key) in TOOLBAR.iter().filter(|(k, _, _)| !compact || !["toc", "hr", "code"].contains(k)) {
        let (a, b) = snip(k);
        let title = esc(trim(&re_nl().replace_all(&format!("{a}{b}"), " ")));
        let key = if key.is_empty() { String::new() } else { format!(" ({key})") };
        out += &format!(r#"<button type="button" class="btn btn-sm wk-tb" data-wiki-insert="{k}" title="{title}{key}">{label}</button>"#);
        if image && *k == "table" {
            out += r#"<button type="button" class="btn btn-sm wk-tb" data-wiki-image title="그림 넣기 — 파일을 골라 줄여 담고 커서 자리에 [[파일:이름]] (글 칸에 끌어다 놓거나 붙여넣어도 됨)">그림</button>"#;
        }
    }
    out + r#"<button type="button" class="btn btn-sm wk-tb" data-wiki-help title="문법과 단축키">?</button>"#
}

// ── 벡터 검사의 다리 ──

/// 벡터(`js-vectors.mjs`의 `WIKI_RE`)의 정규식 id 모두 — [`probe`]가 아는 것.
pub const PROBES: [&str; 76] = [
    "esc", "style.bad", "style.keep", "color.hex", "color.name", "file", "file.head", "file.opt", "file.width", "file.pct", "file.align", "restore", "brace", "fn.inner", "tag",
    "link", "link.figure", "link.cat", "link.file", "link.http", "link.proto", "bold", "italic", "strike", "dash", "under", "sup", "sub", "br", "date", "age", "macro", "toc", "foot",
    "size", "color", "color.ishex", "block.head", "box.style", "cell.opt", "cell.colspan", "cell.rowspan", "cell.rowspan2", "cell.bgcolor", "cell.color", "cell.width", "cell.height",
    "cell.rowbgcolor", "cell.rowcolor", "cell.table.bgcolor", "cell.table.bordercolor", "cell.table.width", "cell.table.align", "cell.skip", "cell.lead", "cell.trail", "nl", "crlf",
    "block.ph", "block.foot", "block.toc", "heading", "hr", "table.line", "quote", "quote.head", "list", "list.more", "list.head", "image.line", "list.start", "hnum", "toc.ph",
    "foot.ph", "links", "links.skip",
];

/// 맞음 목록 `[[UTF-16 자리, 통째, 무리 1, …] …]`(참여하지 않은 무리는 null) — 없으면 null. `global`이 아니면 첫 맞음 하나.
fn matches(re: &Regex, text: &str, global: bool) -> Value {
    let row = |c: &Captures<'_>| -> Value {
        let at = text[..c.get(0).expect("통째").start()].encode_utf16().count();
        let mut v = vec![json!(at)];
        v.extend((0..c.len()).map(|k| c.get(k).map_or(Value::Null, |m| Value::from(m.as_str()))));
        Value::Array(v)
    };
    let rows: Vec<Value> = if global { re.captures_iter(text).map(|c| row(&c)).collect() } else { re.captures(text).map(|c| row(&c)).into_iter().collect() };
    if rows.is_empty() { Value::Null } else { Value::Array(rows) }
}

/// 벡터 검사(`tests/lay_wiki.rs`)가 정규식 하나를 원본이 쓰는 꼴로 돌린다 — `.test`면 참거짓, 바꿔 넣기면 그 답의 글, 콜백 · `.match`면 맞음 목록.
/// 렌더 · 그림 고리 · 고리 목록이 부르는 것과 같은 정규식 · 같은 바꿔 넣는 글 · 같은 손 함수([`dash`] · [`heading`])다. 모르는 id면 None.
pub fn probe(id: &str, text: &str) -> Option<Value> {
    let t = |re: &Regex| Value::Bool(re.is_match(text));
    let all = |re: &Regex, tpl: &str| Value::from(re.replace_all(text, tpl).into_owned());
    let first = |re: &Regex, tpl: &str| Value::from(re.replace(text, tpl).into_owned());
    let m = |re: &Regex| matches(re, text, false);
    let g = |re: &Regex| matches(re, text, true);
    Some(match id {
        "esc" => g(re_esc()), "style.bad" => all(re_style_bad(), ""), "style.keep" => all(re_style_keep(), ""), "color.hex" => t(re_color_hex()), "color.name" => t(re_color_name()),
        "file" => g(re_file()), "file.head" => first(re_file_head(), ""), "file.opt" => m(re_file_opt()), "file.width" => t(re_file_width()), "file.pct" => t(re_file_pct()),
        "file.align" => t(re_file_align()), "restore" => g(re_restore()), "brace" => g(re_brace()), "fn.inner" => m(re_fn_inner()), "tag" => all(re_tag(), ""),
        "link" => g(re_link()), "link.figure" => first(re_link_figure(), ""), "link.cat" => t(re_link_cat()), "link.file" => t(re_link_file()), "link.http" => t(re_link_http()),
        "link.proto" => t(re_link_proto()), "bold" => all(re_bold(), T_BOLD), "italic" => all(re_italic(), T_ITALIC), "strike" => all(re_strike(), T_STRIKE), "dash" => Value::from(dash(text)),
        "under" => all(re_under(), T_UNDER), "sup" => all(re_sup(), T_SUP), "sub" => all(re_sub(), T_SUB), "br" => all(re_br(), T_BR), "date" => g(re_date()), "age" => g(re_age()),
        "macro" => all(re_macro(), ""), "toc" => all(re_toc(), T_TOC), "foot" => all(re_foot(), T_FOOT), "size" => m(re_size()), "color" => m(re_color()),
        "color.ishex" => t(re_color_ishex()), "block.head" => m(re_block_head()), "box.style" => m(re_box_style()), "cell.opt" => m(re_cell_opt()), "cell.colspan" => m(re_cell_colspan()),
        "cell.rowspan" => m(re_cell_rowspan()), "cell.rowspan2" => m(re_cell_rowspan2()), "cell.bgcolor" => m(re_cell_bgcolor()), "cell.color" => m(re_cell_color()),
        "cell.width" => m(re_cell_width()), "cell.height" => m(re_cell_height()), "cell.rowbgcolor" => m(re_cell_rowbgcolor()), "cell.rowcolor" => m(re_cell_rowcolor()),
        "cell.table.bgcolor" => m(re_cell_table_bgcolor()), "cell.table.bordercolor" => m(re_cell_table_bordercolor()), "cell.table.width" => m(re_cell_table_width()),
        "cell.table.align" => m(re_cell_table_align()), "cell.skip" => t(re_cell_skip()), "cell.lead" => t(re_cell_lead()), "cell.trail" => t(re_cell_trail()),
        "nl" => all(re_nl(), T_BR), "crlf" => all(re_crlf(), "\n"), "block.ph" => t(re_block_ph()), "block.foot" => t(re_block_foot()), "block.toc" => t(re_block_toc()),
        "heading" => match heading(text) { Some((a, b, c)) => json!([[0, text, a, b, c]]), None => Value::Null },
        "hr" => t(re_hr()), "table.line" => t(re_table_line()), "quote" => t(re_quote()), "quote.head" => first(re_quote_head(), ""), "list" => m(re_list()),
        "list.more" => t(re_list_more()), "list.head" => t(re_list_head()), "image.line" => t(re_image_line()), "list.start" => m(re_list_start()), "hnum" => g(re_hnum()),
        "toc.ph" => g(re_toc_ph()), "foot.ph" => g(re_foot_ph()), "links" => g(re_links()), "links.skip" => t(re_links_skip()),
        _ => return None,
    })
}

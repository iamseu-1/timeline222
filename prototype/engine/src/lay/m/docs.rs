//! 내보내기 모듈 `docs` — `prototype/scripts/export/docs.mjs` 1 ~ 415줄(SHA-256 앞 12자 `042e0e3b132a`)을 줄 그대로 — 한 벌 P3 과제 12b(갈래 C · 앞자리 13/20).
//! 문서(위키) 창과 하위 문서 칩이 읽는 기록 `{uid:"doc:<열쇠>", kind:"doc", json}`을 항목 기록(`out.entities`)에 싣고(그림 바이트는 `out.blobs`),
//! `ctx.shared.docsOf` · `cellDocsOf`를 쓰며, 늦은 차례가 다른 항목 기록의 `json`에 `x_docs` · `x_cellDocs`를 얹는다.
//! `json` 글은 `js::stringify`(JS의 열쇠 차례 — 판정 R24 ②: 공통 틀이 바이트로도 견줌).
//!
//! 함께 옮긴 웹 함수:
//! - `js/wiki.js` → 하위 모듈 [`wiki`](과제 12a — 이 모듈만 부른다)
//! - 날짜 글(`HT.formatRange` · `formatWhen` · `cal.describe` …) · `HT.kindName` · `HT.itemWord` · `HT.CELL_KINDS` · `HT.cellKind` · `HT.cellSpan` · `HT.cellToNow` · `HT.cmp16` ·
//!   물려받은 이름은 여러 모듈이 함께 부르는 [`crate::lay::web`] 하나(과제 Y가 모음 — 처음 옮긴 판은 이 파일과 `docs/when.rs`에 있었다)
//! - `js/core.js` — SHA-256 앞 12자 `9c786cf58566`: 5087 ~ 5121줄 `docPrefixRe` · `cellKeyRe('full')` · `HT.docKey.cell` · `HT.docKey.parse`(`split`은 `read::docs::doc_key_split`) ·
//!   3334줄 `str` · 5374 ~ 5379줄 `HT.docImageOf`
//! - `atob`(WHATWG forgiving-base64 풀기 — `sizeOf`가 그림 머리를 읽을 때)
//!
//! 정규식(옮기는 규칙): `docPrefixRe` `^(people|…|place):(.+)$` · `cellKeyRe('full')` `^cell:(.+?):(leaders|…|phases):(.+)@(-?\d+)$` · `IMAGE_RE` · `/^인물\s*:\s*(.+)$/` ·
//! `/^단체\s*:\s*(.+)$/` · `docImageOf`의 `/^(파일|이미지|file)\s*:\s*/i` — 벡터 `wiki.re`의 `docKey.*` · `docs.*`(→ `tests/lay_wiki.rs`).
//! 외톨이 서로게이트가 든 문서 열쇠 · 글은 거절한다(정규식이 `&str`에서 돈다 — 정답지 자료에는 없음).
//! JS의 `obj[이름]`이 `Object.prototype`의 이름(`constructor` · `toString` …)을 '있음'으로 읽는 곳(`pics[f.name]` · `found[name] = to`의 `__proto__`)은 그 뜻대로
//! ([`crate::lay::web::words::inherited`]).
use super::kit::some;
use crate::lay::ctx::Ctx;
use crate::lay::export::jv;
use crate::lay::js::{self, Arr, Map, Obj, Str, V};
use crate::lay::model::o;
use crate::lay::model::util::{self, s, t, tv};
use crate::lay::model::bounds;
use crate::lay::read::docs::doc_key_split;
use crate::lay::web::cells::{cell_kind, cell_span, cell_to_now, CellKind, CELL_KINDS};
use crate::lay::web::when;
use crate::lay::web::words::{cmp16, inherited, item_word, kind_name};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::OnceLock;

/// `js/wiki.js`(`HT.namu`) — 과제 12a(판정 R24-c: 공통 `lay/mod.rs`를 고치지 않게 이 모듈 아래).
pub mod wiki;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

// ── 정규식 ──

const WS: &str = r"[\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]";
const DOT: &str = r"[^\n\r\x{2028}\x{2029}]";
fn build(pattern: &str) -> Regex { Regex::new(&pattern.replace("{WS}", WS).replace("{DOT}", DOT)).unwrap_or_else(|e| panic!("docs 정규식 {pattern}: {e}")) }
macro_rules! regexes {
    ($( #[doc = $doc:literal] $name:ident = $pat:expr; )*) => {
        $( #[doc = $doc] fn $name() -> &'static Regex { static R: OnceLock<Regex> = OnceLock::new(); R.get_or_init(|| build($pat)) } )*
    };
}
regexes! {
    /// core.js 5087 ~ 5096줄 `docPrefixRe()` — `^(${HT.DOC_PREFIXES.join('|')}):(.+)$`(접두어 여덟).
    re_doc_prefix = r"^(people|track|category|house|view|map|surname|place):({DOT}+)$";
    /// core.js 5098 ~ 5105줄 `cellKeyRe('full')` — `^cell:(.+?):(${문서를 다는 칸 종류}):(.+)@(-?\d+)$`.
    re_cell_full = r"^cell:({DOT}+?):(leaders|cabinets|eras|capitals|phases):({DOT}+)@(-?[0-9]+)$";
    /// core.js 5377줄 `/^(파일|이미지|file)\s*:\s*/i`.
    re_image_head = r"^(파일|이미지|(?i-u:file)){WS}*:{WS}*";
    /// docs.mjs 42줄 `IMAGE_RE = /^data:(image\/(png|jpeg|webp));base64,/`.
    re_image = r"^data:(image/(png|jpeg|webp));base64,";
    /// docs.mjs 223줄 `/^인물\s*:\s*(.+)$/`.
    re_figure_name = r"^인물{WS}*:{WS}*({DOT}+)$";
    /// docs.mjs 225줄 `/^단체\s*:\s*(.+)$/`.
    re_group_name = r"^단체{WS}*:{WS}*({DOT}+)$";
}

// ── JS 뜻의 작은 도움 ──

fn trim(x: &str) -> &str { x.trim_matches(js::is_space) }
/// 외톨이 서로게이트가 없는 글(정규식이 `&str`에서 돈다) — 있으면 거절.
fn exact(v: &V, what: &str) -> crate::Result<String> {
    let x = js::to_str(v);
    x.exact().map(str::to_string).ok_or_else(|| format!("옮기지 않은 갈래: 외톨이 서로게이트가 든 {what} — {}", x.as_str()).into())
}

/// docs.mjs 26줄 `M(t)` — 해 좌표 → 정수 분(수가 아니거나 유한하지 않으면 null).
fn m_of(t: &V) -> V { match t { V::Num(x) if x.is_finite() => js::minute(*x).map_or(V::Num(f64::NAN), |m| V::Num(m as f64)), _ => V::Null } }
/// docs.mjs 29 ~ 34줄 `spanOf(a, b)` — 구간 → [분, 분](시작이 없으면 null · 뒤집히면 앞쪽으로).
fn span_of(a: &V, b: &V) -> V {
    let lo = m_of(a);
    if lo.is_null() { return V::Null; }
    let hi = m_of(b);
    let hi = if hi.is_null() || js::to_num(&hi) < js::to_num(&lo) { lo.clone() } else { hi };
    V::Arr(Arr::new(vec![lo, hi]))
}

/// `K.title(c, { leaderMode: 'auto' })` — 지도자는 `HT.leaderLabel(c, 'auto')`, 나머지는 `c.name`.
fn cell_title(k: CellKind, c: &V) -> V { if k.id == "leader" { util::leader_label(c) } else { c.get("name") } }

/// `HT.docKey.cell(uid, kind, c)` — `cell:<uid>:<종류>:<이름>@<시작 해>`.
fn doc_key_cell(uid: &V, kind: &str, c: &V) -> String {
    let name = js::or(c.get("docName"), c.get("name"));
    format!("cell:{}:{kind}:{}@{}", t(uid), t(&name), js::num_str((js::to_num(&c.get("start")) + 1e-9).floor()))
}
/// `HT.docKey.parse(key)`의 답(쓰는 칸만): 종류 · 접두어 키의 id · 항목 · 칸의 uid · 칸 종류(목록 열쇠) · 바탕 키.
struct KeyOf { ty: String, id: String, uid: Option<String>, cell_kind: String, base: String }
/// `HT.docKey.parse(key)`.
fn doc_key_parse(key: &str) -> KeyOf {
    let (base, _) = doc_key_split(&Str::from(key));
    let base = base.as_str().into_owned();
    if let Some(m) = re_doc_prefix().captures(&base) { return KeyOf { ty: m[1].into(), id: m[2].into(), uid: None, cell_kind: String::new(), base: base.clone() }; }
    if let Some(m) = re_cell_full().captures(&base) { return KeyOf { ty: "cell".into(), id: String::new(), uid: Some(m[1].into()), cell_kind: m[2].into(), base: base.clone() }; }
    KeyOf { ty: "item".into(), id: String::new(), uid: Some(base.clone()), cell_kind: String::new(), base }
}
/// `HT.docKey.split(key)`(글로).
fn split(key: &str) -> (String, String) {
    let (b, s) = doc_key_split(&Str::from(key));
    (b.as_str().into_owned(), s.as_str().into_owned())
}

/// core.js 3334줄 `str(v)` — null · undefined는 빈 글, 그 밖은 `String(v).trim()`.
fn str_v(v: &V) -> String { if v.is_nullish() { String::new() } else { trim(&t(v)).to_string() } }
/// 5374 ~ 5379줄 `HT.docImageOf(model, packId, ref)` — 그 팩의 그림 사전에서 id → 이름 → 소문자 이름 차례(없으면 null).
fn doc_image_of(model: &V, pack_id: &V, r: &str) -> V {
    let image_map = model.get("imageMap");
    let key = js::or(pack_id.clone(), s(""));
    let bx = match &image_map { V::Map(m) if tv(model) => m.get(&key), _ => V::Undef };
    if !tv(&bx) { return V::Null; }
    let name = re_image_head().replace(&str_v(&s(r)), "").into_owned();
    let get = |which: &str, k: &str| -> V { match bx.get(which) { V::Map(m) => m.get(&s(k)), _ => V::Undef } };
    let hit = js::or(js::or(get("byId", &name), get("byName", &name)), get("byName", &name.to_lowercase()));
    if tv(&hit) { hit } else { V::Null }
}

/// `atob(b64)`(WHATWG forgiving-base64) — 풀 수 없으면 None(JS는 던짐). 답은 바이트(= JS 이진 글의 글자 코드).
fn atob(text: &str) -> Option<Vec<u8>> {
    let mut data: Vec<u8> = text.bytes().filter(|b| !matches!(b, b'\t' | b'\n' | b'\x0C' | b'\r' | b' ')).collect();
    if text.chars().any(|c| !c.is_ascii()) { return None; }
    if data.len() % 4 == 0 {
        if data.ends_with(b"==") { data.truncate(data.len() - 2); } else if data.ends_with(b"=") { data.truncate(data.len() - 1); }
    }
    if data.len() % 4 == 1 { return None; }
    let val = |c: u8| -> Option<u32> {
        Some(match c { b'A'..=b'Z' => c - b'A', b'a'..=b'z' => c - b'a' + 26, b'0'..=b'9' => c - b'0' + 52, b'+' => 62, b'/' => 63, _ => return None } as u32)
    };
    let mut out = Vec::with_capacity(data.len() * 3 / 4);
    let (mut buf, mut bits) = (0u32, 0u32);
    for &c in &data {
        buf = (buf << 6) | val(c)?;
        bits += 6;
        if bits >= 8 { bits -= 8; out.push(((buf >> bits) & 0xff) as u8); }
    }
    Some(out)
}
/// docs.mjs 44 ~ 71줄 `sizeOf(b64)` — base64 앞부분만 풀어 그림의 픽셀 크기(png · webp · jpeg 머리). 모르면 [0, 0].
pub fn size_of(b64: &str) -> (f64, f64) {
    let head = Str::from(b64).slice16(0.0, 87384.0).as_str().into_owned();
    let Some(bin) = atob(&head) else { return (0.0, 0.0) };
    let u = |i: usize| -> u32 { bin.get(i).map_or(0, |&b| u32::from(b)) };
    let be16 = |i: usize| (u(i) << 8) | u(i + 1);
    let be32 = |i: usize| -> f64 { f64::from(u(i) << 24) + f64::from(u(i + 1) << 16) + f64::from(u(i + 2) << 8) + f64::from(u(i + 3)) };
    if bin.starts_with(b"\x89PNG") { return (be32(16), be32(20)); }
    if bin.starts_with(b"RIFF") && bin.get(8..12) == Some(b"WEBP".as_slice()) {
        let chunk = bin.get(12..16).unwrap_or(&[]);
        if chunk == b"VP8 " { return (f64::from((u(26) | (u(27) << 8)) & 0x3fff), f64::from((u(28) | (u(29) << 8)) & 0x3fff)); }
        if chunk == b"VP8L" {
            return (f64::from(1 + (((u(22) & 0x3f) << 8) | u(21))), f64::from(1 + (((u(24) & 0x0f) << 10) | (u(23) << 2) | ((u(22) & 0xc0) >> 6))));
        }
        if chunk == b"VP8X" { return (f64::from(1 + (u(24) | (u(25) << 8) | (u(26) << 16))), f64::from(1 + (u(27) | (u(28) << 8) | (u(29) << 16)))); }
        return (0.0, 0.0);
    }
    if u(0) == 0xff && u(1) == 0xd8 {
        let mut i = 2usize;
        while i + 9 < bin.len() {
            if u(i) != 0xff { return (0.0, 0.0); }
            let m = u(i + 1);
            if (0xc0..=0xcf).contains(&m) && m != 0xc4 && m != 0xc8 && m != 0xcc { return (f64::from(be16(i + 7)), f64::from(be16(i + 5))); }
            i += 2 + be16(i + 2) as usize;
        }
    }
    (0.0, 0.0)
}

// ── docs.mjs 80 ~ 245줄 `tools(ctx)` ──

/// 문서 하나하나를 풀어 주는 도구 묶음(지금 연표의 함수 이름 그대로).
struct Tools<'a> {
    ctx: &'a Ctx,
    model: V,
    keys_with_text: Vec<String>,
    with_text: std::collections::HashSet<String>,
    base_cache: std::cell::RefCell<HashMap<String, V>>,
    by_name: Map,
    figure_by_name: Map,
    group_by_name: Map,
}

impl<'a> Tools<'a> {
    fn new(ctx: &'a Ctx) -> crate::Result<Tools<'a>> {
        let model = ctx.model.clone();
        let docs = util::mp(&model.get("docs"), "model.docs");
        let mut keys_with_text = Vec::new();
        for k in docs.keys() {
            let key = exact(&k, "문서 열쇠")?;
            // 글은 원래 JS 값(`d.text`)에서 본다 — `text_of`의 글은 이미 외톨이 서로게이트를 U+FFFD로 바꾼 뒤라 거기서는 늘 통과한다(고침 1회차)
            let d = docs.get(&k);
            if tv(&d) && tv(&d.get("text")) { exact(&d.get("text"), "문서 글")?; }
            let text = text_of(&model, &key);
            if !trim(&text).is_empty() { keys_with_text.push(key); }
        }
        let with_text = keys_with_text.iter().cloned().collect();
        let mut me = Tools { ctx, model, keys_with_text, with_text, base_cache: Default::default(), by_name: Map::new(), figure_by_name: Map::new(), group_by_name: Map::new() };
        me.names();
        Ok(me)
    }

    /// 182 ~ 218줄 이름 → 바탕 키 표: 항목(시대 → 사건 → 시대 구분) → 대범위 → 민족 → 트랙(이름 · id) → 분류 → 칸 → 인물(이름 → 다른 이름) → 가문 → 단체 — 먼저 넣은 것이 이긴다.
    fn names(&mut self) {
        let put = |map: &Map, name: &V, key: V| {
            let n = trim(&t(&js::or(name.clone(), s("")))).to_lowercase();
            if !n.is_empty() && !map.has(&s(&n)) { map.set(s(&n), key); }
        };
        let m = &self.model;
        let l = |k: &str| util::list(&m.get(k));
        for p in l("periods") { put(&self.by_name, &p.get("name"), p.get("uid")); }
        for e in l("events") { put(&self.by_name, &e.get("title"), e.get("uid")); }
        for e in l("epochs") { put(&self.by_name, &e.get("name"), e.get("uid")); }
        for x in l("scopes") { put(&self.by_name, &x.get("name"), x.get("uid")); }
        for pe in l("peoples") { put(&self.by_name, &pe.get("name"), V::from(format!("people:{}", t(&pe.get("id"))))); }
        for tr in l("tracks") {
            let key = V::from(format!("track:{}", t(&tr.get("id"))));
            put(&self.by_name, &tr.get("name"), key.clone());
            put(&self.by_name, &tr.get("id"), key);
        }
        for c in l("categories") { put(&self.by_name, &c.get("name"), V::from(format!("category:{}", t(&c.get("id"))))); }
        for p in l("periods") {
            for k in CELL_KINDS.iter().filter(|k| k.doc) { // 문서를 다는 칸 종류 모두
                for c in bounds::cells_of(&p, k.list) {
                    let key = V::from(doc_key_cell(&p.get("uid"), k.list, &c));
                    for v in ["name", "temple", "title", "given"] { put(&self.by_name, &c.get(v), key.clone()); }
                }
            }
        }
        for f in l("figures") { put(&self.figure_by_name, &f.get("name"), f.get("uid")); }
        for f in l("figures") { for a in util::list(&f.get("aka")) { put(&self.figure_by_name, &a, f.get("uid")); } }
        for (n, uid) in self.figure_by_name.entries() { put(&self.by_name, &n, uid); }
        for h in l("houses") { put(&self.by_name, &h.get("name"), h.get("uid")); }
        // 단체(형식 3)는 가문 다음 — 새 기능이 이미 있던 고리의 목적지를 바꾸지 않게. "단체:이름"은 곧바로 단체로.
        for g in l("groups") { put(&self.group_by_name, &g.get("name"), g.get("uid")); }
        for (n, uid) in self.group_by_name.entries() { put(&self.by_name, &n, uid); }
    }

    /// 84 ~ 87줄 `textOf(key)`.
    fn text_of(&self, key: &str) -> String { text_of(&self.model, key) }
    /// 92줄 `trackOf(id)`.
    fn track_of(&self, id: &V) -> V {
        let hit = match self.model.get("trackMap") { V::Map(m) => m.get(id), _ => V::Undef };
        if tv(&hit) { hit } else { V::Obj(o! { "id" => id.clone(), "name" => id.clone(), "color" => "#8b8f98" }) }
    }
    /// 94 ~ 100줄 `cellWhen(c, p)` — 칸의 기간 글(끝을 비운 칸은 풀어 둔 끝으로).
    fn cell_when(&self, c: &V, p: &V) -> String {
        let use_end_y = c.get("end").is_nullish();
        let item = o! {
            "start" => c.get("start"), "startAt" => c.get("startAt"),
            "end" => if use_end_y { c.get("endY") } else { c.get("end") }, "endAt" => if use_end_y { c.get("endYAt") } else { c.get("endAt") },
            "startUnknown" => c.get("startUnknown"), "endUnknown" => js::or(c.get("endUnknown"), if use_end_y { c.get("endYAuto") } else { V::Bool(false) }),
            "ongoing" => V::Bool(cell_to_now(c, p)),
        };
        when::format_range(&self.ctx.read, &V::Obj(item))
    }

    /// 103 ~ 157줄 `baseInfo(base)` — 바탕 키의 대상(없으면 null).
    fn base_info(&self, base: &str) -> V {
        let p = doc_key_parse(base);
        let m = &self.model;
        let map_get = |name: &str, k: &str| -> V { match m.get(name) { V::Map(x) => x.get(&s(k)), _ => V::Undef } };
        let desc = |x: &V| js::or(x.get("description"), s(""));
        match p.ty.as_str() {
            "people" => {
                let pe = map_get("peopleMap", &p.id);
                return if tv(&pe) { V::Obj(o! { "title" => pe.get("name"), "meta" => "민족", "desc" => desc(&pe) }) } else { pe };
            }
            "track" => {
                let tr = map_get("trackMap", &p.id);
                let pack = js::or(self.ctx.track_pack.get(&s(&p.id)), V::Num(0.0));
                return if tv(&tr) { V::Obj(o! { "title" => tr.get("name"), "meta" => "트랙(나라·지역)", "desc" => desc(&tr), "pack" => pack }) } else { tr };
            }
            "category" => {
                let c = map_get("categoryMap", &p.id);
                return if tv(&c) { V::Obj(o! { "title" => c.get("name"), "meta" => "사건 분류", "desc" => desc(&c) }) } else { c };
            }
            "house" => {
                // 가문은 제 줄이 없다 — '연표에서'는 가문 창을 열 뿐 연표를 옮기지 않는다(span 없음).
                let h = if tv(&m.get("houseMap")) { map_get("houseMap", &p.id) } else { m.get("houseMap") };
                if !tv(&h) { return h; }
                let mut meta = "가문".to_string();
                if tv(&h.get("surname")) { meta += &format!(" · 성 {}", t(&h.get("surname"))); }
                if tv(&h.get("seat")) { meta += &format!(" · 본관 {}", t(&h.get("seat"))); }
                return V::Obj(o! { "title" => h.get("name"), "meta" => meta, "uid" => h.get("uid"), "desc" => desc(&h), "pack" => self.ctx.pack_of(&h) });
            }
            "surname" => {
                let x = if tv(&m.get("surnameMap")) { map_get("surnameMap", &p.id) } else { m.get("surnameMap") };
                if !tv(&x) { return x; }
                let n = x.get("houses").get("length");
                let meta = if tv(&n) { format!("성씨 · 가문 {}", t(&n)) } else { "성씨".to_string() };
                return V::Obj(o! { "title" => x.get("name"), "meta" => meta, "desc" => desc(&x), "pack" => self.ctx.pack_of(&x) });
            }
            "place" => {
                let x = if tv(&m.get("placeMap")) { map_get("placeMap", &p.id) } else { m.get("placeMap") };
                if !tv(&x) { return x; }
                let n = x.get("uses").get("length");
                let meta = if tv(&n) { format!("지명 · 쓰인 곳 {}", t(&n)) } else { "지명".to_string() };
                return V::Obj(o! { "title" => x.get("name"), "meta" => meta, "desc" => desc(&x), "pack" => self.ctx.pack_of(&x) });
            }
            "cell" => {
                let x = map_get("byUid", p.uid.as_deref().unwrap_or(""));
                let Some(k) = cell_kind(&p.cell_kind) else { return V::Null };
                if !tv(&x) { return V::Null; }
                let cells = bounds::cells_of(&x, k.list);
                // 칸 열쇠는 "이름@시작 해"다 — 열쇠를 만드는 규칙 그대로 맞춰 본다(날짜를 자세히 고쳐도 문서가 떨어지지 않게).
                let Some(i) = cells.iter().position(|c| doc_key_cell(&x.get("uid"), &p.cell_kind, c) == p.base) else { return V::Null };
                let c = &cells[i];
                let r = V::from(format!("{}:{i}", k.id));
                let sp = cell_span(&self.ctx.read, c, &x, &r);
                let (lo, hi) = (sp.get("lo"), sp.get("hi"));
                return V::Obj(o! {
                    "title" => cell_title(k, c), "meta" => format!("{} {} · {}", t(&x.get("name")), k.name, self.cell_when(c, &x)),
                    "uid" => x.get("uid"), "ref" => r, "at" => m_of(&c.get("start")), "span" => span_of(&lo, &hi), "parent" => x.get("uid"),
                    "desc" => desc(c), "pack" => self.ctx.pack_of(&x),
                });
            }
            _ => {}
        }
        let x = match &p.uid { Some(u) => map_get("byUid", u), None => V::Undef };
        if !tv(&x) { return V::Null; }
        let where_ = if tv(&x.get("track")) { format!(" · {}", t(&self.track_of(&x.get("track")).get("name"))) } else { String::new() };
        let kind = x.get("kind");
        let word = if matches!(&kind, V::Str(k) if k == "epoch") { "시대 구분".to_string() }
            else if matches!(&kind, V::Str(k) if k == "event") { "사건".to_string() }
            else if matches!(util::item_kind_of(&x), V::Str(k) if k == "period") { kind_name(&x.get("polityKind")).to_string() }
            else { item_word(&x).to_string() };
        let nn = |a: V, b: V| if a.is_nullish() { b } else { a };
        let span_end = nn(x.get("spanMax"), nn(x.get("endY"), x.get("end")));
        V::Obj(o! {
            "title" => js::or(x.get("title"), x.get("name")), "meta" => format!("{word} · {}{where_}", when::format_range(&self.ctx.read, &x)), "uid" => x.get("uid"),
            "span" => span_of(&nn(x.get("spanMin"), x.get("start")), &span_end),
            "desc" => desc(&x), "pack" => self.ctx.pack_of(&x),
        })
    }
    /// 160 ~ 163줄 `baseOf(base)` — 바탕마다 한 번만 푼다.
    fn base_of(&self, base: &str) -> V {
        if let Some(v) = self.base_cache.borrow().get(base) { return v.clone(); }
        let v = self.base_info(base);
        self.base_cache.borrow_mut().insert(base.to_string(), v.clone());
        v
    }
    /// 166 ~ 173줄 `docInfo(key)` — 문서 하나의 제목 · 곁글 · 길(바탕이 없으면 null).
    fn doc_info(&self, key: &str) -> V {
        let (base, sub) = split(key);
        let b = self.base_of(&base);
        if !tv(&b) { return V::Null; }
        let out = util::copy(&b); // Object.assign({}, b, …)
        if sub.is_empty() {
            for (k, v) in [("key", s(key)), ("base", s(&base)), ("sub", s("")), ("path", V::Arr(Arr::new(Vec::new())))] { out.set(k, v); }
            return V::Obj(out);
        }
        let parts: Vec<V> = sub.split("//").map(s).collect();
        let bt = t(&b.get("title"));
        let joined = sub.split("//").collect::<Vec<_>>().join("/");
        for (k, v) in [("key", s(key)), ("base", s(&base)), ("sub", s(&sub)), ("path", V::Arr(Arr::new(parts))), ("title", V::from(format!("{bt}/{joined}"))),
            ("meta", V::from(format!("{bt}의 하위 문서"))), ("baseTitle", b.get("title"))] { out.set(k, v); }
        V::Obj(out)
    }
    /// 176 ~ 180줄 `subdocsOf(key)` — 그 문서의 바로 아래 하위 문서(중간 단계가 비어 있어도 이름을 보인다).
    fn subdocs_of(&self, key: &str) -> Vec<V> {
        let pre = format!("{key}//");
        let mut subs: Vec<String> = Vec::new();
        for k in self.keys_with_text.iter().filter(|k| k.starts_with(&pre)) {
            let sub = k[pre.len()..].split("//").next().unwrap_or("").to_string();
            if !subs.contains(&sub) { subs.push(sub); }
        }
        js::sort_by(&mut subs, |a, b| cmp16(&s(a), &s(b)));
        subs.into_iter().map(|sub| V::Obj(o! { "key" => format!("{pre}{sub}"), "sub" => sub })).collect()
    }
    /// 220 ~ 228줄 `nameToBase(name)`.
    fn name_to_base(&self, name: &str) -> Option<String> {
        let n = trim(name).to_lowercase();
        if n.is_empty() { return None; }
        let found = |m: &Map, k: &str| -> Option<String> { let v = m.get(&s(k)); if tv(&v) { Some(t(&v)) } else { None } };
        if let Some(fm) = re_figure_name().captures(&n) { return found(&self.figure_by_name, trim(&fm[1])); } // "인물:이름"은 곧바로 인물로
        if let Some(gm) = re_group_name().captures(&n) { return found(&self.group_by_name, trim(&gm[1])); } // "단체:이름"은 곧바로 단체로
        found(&self.by_name, &n)
    }
    /// 231 ~ 242줄 `linkToKey(name, ctxKey)` — `[[이름]]` · `[[이름/하위]]` · `[[/하위]]` → 문서 키.
    fn link_to_key(&self, name: &str, ctx_key: &str) -> Option<String> {
        let raw = trim(name);
        if let Some(rest) = raw.strip_prefix('/') {
            if !ctx_key.is_empty() { return Some(format!("{ctx_key}//{}", rest.split('/').filter(|x| !x.is_empty()).collect::<Vec<_>>().join("//"))); }
        }
        if let Some(whole) = self.name_to_base(raw) { return Some(whole); }
        let parts: Vec<&str> = raw.split('/').collect();
        for i in (1..parts.len()).rev() {
            if let Some(base) = self.name_to_base(&parts[..i].join("/")) {
                return Some(format!("{base}//{}", parts[i..].iter().filter(|x| !x.is_empty()).copied().collect::<Vec<_>>().join("//")));
            }
        }
        None
    }
}

/// `textOf(key)` — `model.docs.get(key)`의 글(없으면 '').
fn text_of(model: &V, key: &str) -> String {
    let d = match model.get("docs") { V::Map(m) => m.get(&s(key)), _ => V::Undef };
    if tv(&d) { let x = d.get("text"); if tv(&x) { t(&x) } else { String::new() } } else { String::new() }
}

// ── contribute(247 ~ 392줄) ──

/// `contribute(ctx, out)` — 문서 기록 · 그림 · `shared.docsOf` · `cellDocsOf`.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tools = Tools::new(ctx)?;
    let tl = &tools;

    /* 1) 기록을 만들 열쇠를 모은다: 내용이 있는 문서 + 중간 단계 하위 문서 + 고리가 가리키는 곳. */
    let mut wanted: Vec<String> = Vec::new();
    let mut wanted_set: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut want = |k: String, wanted: &mut Vec<String>| { if wanted_set.insert(k.clone()) { wanted.push(k); } };
    for k in &tl.keys_with_text { want(k.clone(), &mut wanted); }
    for key in &tl.keys_with_text {
        let (base, sub) = split(key);
        let parts: Vec<&str> = if sub.is_empty() { Vec::new() } else { sub.split("//").collect() };
        for i in 1..parts.len() { want(format!("{base}//{}", parts[..i].join("//")), &mut wanted); }
        if !sub.is_empty() { want(base, &mut wanted); }
    }
    /* 2) 본문의 `[[고리]]`를 풀어 둔다 — 목적지도 기록이 있어야 창이 열린다. */
    let mut links: HashMap<String, Obj> = HashMap::new(); // 문서 열쇠 → { 이름: 목적지 }
    let mut back: HashMap<String, Vec<String>> = HashMap::new(); // 문서 열쇠 → [가리키는 문서 열쇠…]
    for key in &tl.keys_with_text {
        let found = Obj::new();
        for name in wiki::links(&tl.text_of(key)) {
            let Some(to) = tl.link_to_key(&name, key) else { continue };
            if !tv(&tl.doc_info(&to)) { continue; } // 연표에 없는 이름은 붉은 고리 — 싣지 않는다
            if name != "__proto__" { found.set(name.as_str(), V::from(to.as_str())); } // JS: found['__proto__'] = 글은 프로토타입 바꾸기(무시됨)
            want(to.clone(), &mut wanted);
            if &to != key {
                let list = back.entry(to).or_default();
                if !list.contains(key) { list.push(key.clone()); }
            }
        }
        links.insert(key.clone(), found);
    }

    /* 3) 기록을 싣는다. */
    let kinds = Obj::new();
    let mut bytes = 0usize;
    let mut empties = 0usize;
    let mut made: Vec<Value> = Vec::new();
    let mut blobs: Vec<(String, Value)> = Vec::new(); // 그림 열쇠 → { key, pack, mime, data }(문서가 쓰는 그림만 한 번씩 · 넣은 차례)
    let mut blob_bytes = 0usize;
    let mut figures = 0usize;
    let mut order = wanted.clone();
    js::sort_by(&mut order, |a, b| cmp16(&s(a), &s(b)));
    let docs_map = util::mp(&tl.model.get("docs"), "model.docs");
    for key in &order {
        let info = tl.doc_info(key);
        if !tv(&info) { continue; }
        let body = tl.text_of(key);
        let rec = docs_map.get(&s(key));
        let subs = tl.subdocs_of(key);
        /* 빵 부스러기: 칸 문서는 제 정권, 하위 문서는 바탕과 중간 단계. */
        let mut crumbs: Vec<V> = Vec::new();
        let info_sub = info.get("sub");
        if tv(&info.get("parent")) && !tv(&info_sub) {
            let parent = t(&info.get("parent"));
            let up = tl.doc_info(&parent);
            if tv(&up) { crumbs.push(V::Obj(o! { "key" => parent, "label" => up.get("title") })); }
        }
        let path = util::list(&info.get("path"));
        if tv(&info_sub) {
            let base = t(&info.get("base"));
            crumbs.push(V::Obj(o! { "key" => info.get("base"), "label" => info.get("baseTitle") }));
            for i in 0..path.len().saturating_sub(1) {
                let seg: Vec<String> = path[..=i].iter().map(t).collect();
                crumbs.push(V::Obj(o! { "key" => format!("{base}//{}", seg.join("//")), "label" => path[i].clone() }));
            }
        }
        let link = Obj::new();
        if let Some(found) = links.get(key) {
            for (name, to) in found.entries() {
                let to_s = t(&to);
                let li = tl.doc_info(&to_s);
                if !tv(&li) { continue; }
                let one = o! { "key" => to.clone(), "title" => li.get("title") };
                if !tl.with_text.contains(&to_s) { one.set("empty", V::Num(1.0)); }
                link.set(&name, V::Obj(one));
            }
        }
        let json = o! { "key" => key.as_str(), "title" => info.get("title"), "meta" => info.get("meta"), "base" => info.get("base") };
        if tv(&info.get("baseTitle")) { json.set("baseTitle", info.get("baseTitle")); }
        if tv(&info_sub) { json.set("sub", info_sub.clone()); json.set("path", info.get("path")); }
        if !body.is_empty() { json.set("body", body.as_str()); } else { json.set("empty", V::Num(1.0)); empties += 1; }
        if tv(&rec) && tv(&rec.get("packName")) { json.set("pack", rec.get("packName")); }
        if tv(&info.get("uid")) { json.set("uid", info.get("uid")); }
        if tv(&info.get("ref")) { json.set("ref", info.get("ref")); }
        if !info.get("at").is_nullish() { json.set("at", info.get("at")); }
        if tv(&info.get("span")) { json.set("span", info.get("span")); }
        if body.is_empty() && tv(&some(&info.get("desc"))) { json.set("desc", info.get("desc")); } // 본문이 없는 창이 대신 보이는 설명
        if !subs.is_empty() { json.set("subs", V::Arr(Arr::new(subs.clone()))); }
        if !crumbs.is_empty() { json.set("crumbs", V::Arr(Arr::new(crumbs.clone()))); }
        // 굵게 적는 지금 문서의 이름(빵 부스러기의 끝).
        if !crumbs.is_empty() { json.set("last", if path.is_empty() { info.get("title") } else { path[path.len() - 1].clone() }); }
        if tv(&some(&V::Obj(link.clone()))) { json.set("links", V::Obj(link)); }
        /* 문서 그림: 본문의 [[파일:이름]] → 그림 사전(그 문서 글을 적은 팩) */
        if !body.is_empty() {
            let pics = Obj::new();
            let rec_pack = if tv(&rec) { rec.get("packId") } else { rec.clone() };
            for f in wiki::files(&body) {
                if f.name.is_empty() || pics.has(f.name.as_str()) || inherited(&f.name) { continue; }
                let g = doc_image_of(&tl.model, &rec_pack, &f.name);
                let src = g.get("src");
                let V::Str(src) = (if tv(&g) { src } else { V::Undef }) else { continue };
                let src = src.as_str().into_owned();
                let Some(m) = re_image().captures(&src) else { continue };
                let mime = m[1].to_string();
                let data = src[m[0].len()..].to_string();
                let (w, h) = if tv(&g.get("width")) && tv(&g.get("height")) { (g.get("width"), g.get("height")) } else { let (w, h) = size_of(&data); (V::Num(w), V::Num(h)) };
                let len = data.encode_utf16().count() as f64;
                let pad = if data.ends_with("==") { 2.0 } else if data.ends_with('=') { 1.0 } else { 0.0 };
                let one = o! { "key" => g.get("uid"), "mime" => mime.as_str(), "bytes" => (len * 3.0 / 4.0).floor() - pad };
                if tv(&w) && tv(&h) { one.set("w", w); one.set("h", h); }
                for k in ["caption", "alt", "credit"] { if tv(&some(&g.get(k))) { one.set(k, g.get(k)); } }
                pics.set(f.name.as_str(), V::Obj(one));
                figures += 1;
                let uid = t(&g.get("uid"));
                if !blobs.iter().any(|(k, _)| *k == uid) {
                    let pack = ctx.pack_of(&V::Obj(o! { "packId" => g.get("packId") }));
                    blob_bytes += data.encode_utf16().count();
                    blobs.push((uid.clone(), json!({ "key": js::to_json(&g.get("uid")), "pack": jv(pack), "mime": mime, "data": data })));
                }
            }
            if tv(&some(&V::Obj(pics.clone()))) { json.set("images", V::Obj(pics)); }
        }
        let from: Vec<V> = back.get(key).map(|l| l.iter().map(|k| {
            let ti = tl.doc_info(k);
            let title = js::or(if tv(&ti) { ti.get("title") } else { V::Undef }, s(k));
            V::Obj(o! { "key" => k.as_str(), "title" => title })
        }).filter(|b| tv(&b.get("title"))).collect()).unwrap_or_default();
        if !from.is_empty() { json.set("back", V::Arr(Arr::new(from))); }

        let text = js::stringify(&V::Obj(json.clone()));
        bytes += text.encode_utf16().count();
        let kind = if tv(&info_sub) { "하위".to_string() } else { doc_key_parse(&t(&info.get("base"))).ty };
        kinds.set(kind.as_str(), V::Num(js::to_num(&js::or(kinds.get(kind.as_str()), V::Num(0.0))) + 1.0));
        // 자료집 귀속(pack — 배치의 packs[] 순번): 본문을 실은 DLC. 본문이 없는 문서(중간 단계 · 고리의 목적지)는 그 바탕의 DLC.
        let pack = if tv(&rec) && tv(&rec.get("packId")) { ctx.pack_of(&V::Obj(o! { "packId" => rec.get("packId") })) } else { js::to_num(&js::or(info.get("pack"), V::Num(0.0))) };
        made.push(json!({ "uid": format!("doc:{key}"), "kind": "doc", "json": text, "pack": jv(pack) }));
    }
    let n_made = made.len();
    crate::lay::export::arr_mut(out, "entities").extend(made);
    if !blobs.is_empty() {
        js::sort_by(&mut blobs, |a, b| cmp16(&s(&a.0), &s(&b.0))); // 그림이 없으면 열쇠도 없음(옛 배치 그대로)
        out["blobs"] = Value::Array(blobs.into_iter().map(|b| b.1).collect());
    }

    /* 4) 항목 기록에 실을 것을 모아 둔다(`contributeLate`와 `ctx.shared`). */
    let docs_of = Obj::new(); // 항목 uid → [{key, sub}]
    let cell_docs_of = Obj::new(); // 정권 uid → [칸 문서 열쇠…]
    for key in &tl.keys_with_text {
        let (base, sub) = split(key);
        if sub.is_empty() { continue; }
        let info = tl.doc_info(&base);
        if !tv(&info) || !tv(&info.get("uid")) || tv(&info.get("ref")) { continue; } // 칸 문서의 하위 문서는 그 칸의 몫이다
        let top = sub.split("//").next().unwrap_or("").to_string();
        let uid = t(&info.get("uid"));
        if !tv(&docs_of.get(uid.as_str())) { docs_of.set(uid.as_str(), V::Arr(Arr::new(Vec::new()))); }
        let V::Arr(list) = docs_of.get(uid.as_str()) else { continue };
        if !list.to_vec().iter().any(|d| matches!(d.get("sub"), V::Str(x) if x == top.as_str())) { list.push(V::Obj(o! { "key" => format!("{base}//{top}"), "sub" => top.as_str() })); }
    }
    for list in docs_of.values() { if let V::Arr(a) = list { a.sort_js(|x, y| cmp16(&s(&t(&x.get("sub"))), &s(&t(&y.get("sub"))))); } }
    for key in &tl.keys_with_text {
        let p = doc_key_parse(&split(key).0);
        if p.ty != "cell" { continue; }
        let uid = p.uid.clone().unwrap_or_default();
        if !tv(&cell_docs_of.get(uid.as_str())) { cell_docs_of.set(uid.as_str(), V::Arr(Arr::new(Vec::new()))); }
        let V::Arr(list) = cell_docs_of.get(uid.as_str()) else { continue };
        if !list.to_vec().iter().any(|x| matches!(x, V::Str(b) if b == p.base.as_str())) { list.push(s(&p.base)); }
    }
    let (n_docs_of, n_cell_docs_of) = (docs_of.len(), cell_docs_of.len());
    ctx.shared.set("docsOf", V::Obj(docs_of));
    ctx.shared.set("cellDocsOf", V::Obj(cell_docs_of));

    let notes = o! {
        "기록" => n_made, "본문없음" => empties, "크기MB" => js::round((bytes as f64 / 1_048_576.0) * 100.0) / 100.0,
        "하위문서를_단_항목" => n_docs_of, "칸문서를_단_항목" => n_cell_docs_of,
    };
    util::assign_obj(&notes, &kinds);
    if figures > 0 || blob_bytes > 0 {
        let n_blobs = out["blobs"].as_array().map_or(0, Vec::len);
        notes.set("그림_자리", figures);
        notes.set("그림", n_blobs);
        notes.set("그림MB", js::round((blob_bytes as f64 * 0.75 / 1_048_576.0) * 100.0) / 100.0);
    }
    ctx.notes.set("문서", V::Obj(notes));
    drop(tools);
    super::kit::fault_check("docs")?; // 날짜 글(`cal.describe`)이 남긴 잘못 — JS라면 TypeError(과제 Y)
    if let Some(name) = ctx.read.cal.missed_of() { return Err(format!("문서: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다").into()); }
    if let Some(name) = ctx.read.cal.absent_of() { return Err(format!("문서: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다").into()); }
    Ok(())
}

/// `contributeLate(ctx, out)`(399 ~ 415줄) — `entities` 모듈이 돈 뒤 항목 기록에 `x_docs`(하위 문서 칩) · `x_cellDocs`(칸 목록의 📄가 있는 칸 열쇠)를 덧붙인다.
pub fn contribute_late(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let pick = |k: &str| match ctx.shared.get(k) { V::Obj(o) => o, _ => Obj::new() };
    let (docs_of, cell_docs_of) = (pick("docsOf"), pick("cellDocsOf"));
    let mut hit = 0usize;
    for e in crate::lay::export::arr_mut(out, "entities").iter_mut() {
        if e["kind"] == "doc" { continue; }
        let uid = crate::lay::export::js_text(&e["uid"]);
        let subs = docs_of.get(uid.as_str());
        let cells = cell_docs_of.get(uid.as_str());
        if !tv(&subs) && !tv(&cells) { continue; }
        let json = js::parse(e["json"].as_str().unwrap_or_default())?;
        let o = json.as_obj().cloned().ok_or("항목 기록의 json이 객체가 아닙니다")?;
        if tv(&subs) { o.set("x_docs", subs); }
        if tv(&cells) { o.set("x_cellDocs", cells); }
        e["json"] = Value::from(js::stringify(&json));
        hit += 1;
    }
    if let V::Obj(n) = ctx.notes.get("문서") { n.set("항목에_실음", hit); }
    Ok(())
}

// ── 벡터 검사의 다리 ──

/// 벡터(`js-vectors.mjs`의 `wiki.re`)의 이 모듈 정규식 id.
pub const PROBES: [&str; 6] = ["docKey.prefix", "docKey.cell", "docImage.head", "docs.image", "docs.figure", "docs.group"];
/// 정규식 하나를 원본이 쓰는 꼴(`.match`의 첫 맞음 · 바꿔 넣은 글)로 — `wiki::probe`와 같은 꼴. 모르는 id면 None.
pub fn probe(id: &str, text: &str) -> Option<Value> {
    let m = |re: &Regex| -> Value {
        match re.captures(text) {
            Some(c) => json!([[text[..c.get(0).expect("통째").start()].encode_utf16().count(), (0..c.len()).map(|k| c.get(k).map_or(Value::Null, |g| Value::from(g.as_str()))).collect::<Vec<_>>()]]),
            None => Value::Null,
        }
    };
    let flat = |v: Value| -> Value { // [[자리, [무리…]]] → [[자리, 무리…]]
        match v { Value::Array(rows) => Value::Array(rows.into_iter().map(|r| { let mut out = vec![r[0].clone()]; out.extend(r[1].as_array().cloned().unwrap_or_default()); Value::Array(out) }).collect()), other => other }
    };
    Some(match id {
        "docKey.prefix" => flat(m(re_doc_prefix())),
        "docKey.cell" => flat(m(re_cell_full())),
        "docImage.head" => Value::from(re_image_head().replace(text, "").into_owned()),
        "docs.image" => flat(m(re_image())),
        "docs.figure" => flat(m(re_figure_name())),
        "docs.group" => flat(m(re_group_name())),
        _ => return None,
    })
}

//! 한 벌 P3 과제 12a(갈래 C) — `js/wiki.js`(`HT.namu`)를 옮긴 `lay::m::docs::wiki`가 Node와 같은 답을 내는지 벡터로 견준다.
//! 벡터: `tests/fixtures/lay/js-vectors.json`의 `wiki` 갈래(`node prototype/scripts/js-vectors.mjs` — 그 절 머리말에 행의 꼴) ·
//! 같은 파일의 `regex` 갈래(옮기는 규칙의 뜻 차이 표본 — 과제 3이 뽑아만 둔 것)도 여기서 규칙대로 옮긴 정규식으로 견준다.
//! - 정규식마다(wiki.js · docs 모듈이 쓰는 core.js · docs.mjs · calendar.js의 것 — `docs::PROBES` · `web::when::PROBES`): 원본이 쓰는 꼴(`.test` · 바꿔 넣기 · 맞음 목록) 그대로 · 갈래마다 맞은 표본이 하나 이상 · 벡터 id와 Rust의 id가 서로 빠짐없이
//! - 날짜 글(`cal.describe` · `formatT` · `HT.formatDate` · `formatRange` · `altText` — 다른 달력 · 윤달 · 해 바뀜 · 시 · 분 · 세기 …: 잘린 달력 표로) — 고침 1회차
//! - 함수(`fileSpec` · `files` · `links` · `figureHTML` · `toolbarHTML` · 상수 · `sizeOf`) · 렌더(고정 시각 셋 — `[date]`는 UTC · `[age]`는 지역) · 견본 등불 연대기 문서 모두(렌더 답의 sha12)
mod common;

use archive_engine::lay::export::jv;
use archive_engine::lay::js::{self, Obj, V};
use archive_engine::lay::m::docs::{self, wiki::{self, FileSpec, RenderOpts}};
use archive_engine::lay::web;
use regex::Regex;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::OnceLock;

fn vectors() -> &'static Value {
    static VECTORS: OnceLock<Value> = OnceLock::new();
    VECTORS.get_or_init(|| {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("lay").join("js-vectors.json");
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e} — node prototype/scripts/js-vectors.mjs", path.display()));
        serde_json::from_str(&text).expect("js-vectors.json은 JSON이어야 합니다")
    })
}
fn rows(name: &str) -> &'static Vec<Value> {
    vectors()["wiki"][name].as_array().unwrap_or_else(|| panic!("벡터 wiki.{name}이(가) 없습니다 — node prototype/scripts/js-vectors.mjs"))
}
fn text(v: &Value) -> &str { v.as_str().unwrap_or_else(|| panic!("글이 아닙니다(외톨이 서로게이트 `$s16` 표본은 두지 않음): {v}")) }

/// `2026-10-15T12:00:00+09:00` 꼴 → 1970-01-01T00:00:00Z부터의 밀리초(벡터의 시각 글만 읽는다).
fn ms_of(t: &str) -> f64 {
    let n = |a: usize, b: usize| t[a..b].parse::<i64>().unwrap_or_else(|_| panic!("시각 글이 아닙니다: {t}"));
    let (y, mo, d, h, mi, s) = (n(0, 4), n(5, 7), n(8, 10), n(11, 13), n(14, 16), n(17, 19));
    let sign = if &t[19..20] == "-" { -1 } else { 1 };
    let off = sign * (n(20, 22) * 60 + n(23, 25));
    let yy = if mo <= 2 { y - 1 } else { y };
    let era = yy.div_euclid(400);
    let yoe = yy - era * 400;
    let doy = (153 * ((mo + 9) % 12) + 2) / 5 + d - 1;
    let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468;
    ((days * 86_400 + h * 3600 + mi * 60 + s - off * 60) * 1000) as f64
}
#[test]
fn oracle_clock_is_read_right() { assert_eq!(ms_of("2026-10-15T12:00:00+09:00"), 1_792_033_200_000.0); }

/// `js-vectors.mjs`의 `WIKI_LINK`와 같은 고리 함수.
fn wiki_link(name: &str) -> V {
    let o = Obj::new();
    if name.starts_with('없') { o.set("missing", V::Bool(true)); return V::Obj(o); }
    if name.contains('빈') { o.set("uid", V::from(format!("u/{name}"))); o.set("empty", V::Bool(true)); return V::Obj(o); }
    if name.contains('무') { return V::Null; }
    o.set("uid", V::from(format!("u/{name}")));
    if name.contains("제목") { o.set("title", V::from(format!("T<{name}>"))); }
    V::Obj(o)
}
/// `js-vectors.mjs`의 `WIKI_IMAGE`와 같은 그림 함수(이름 길이는 UTF-16).
fn wiki_image(name: &str) -> V {
    if name.contains("없음") { return V::Null; }
    let o = Obj::new();
    if name.contains("빈그림") { o.set("uid", V::from(format!("img/{name}"))); return V::Obj(o); }
    let len = name.encode_utf16().count();
    let id_only = name.contains("아이디");
    o.set("uid", V::from(if id_only { String::new() } else { format!("img/{name}") }));
    o.set("id", V::from(if id_only { format!("id-{name}") } else { String::new() }));
    o.set("name", V::from(name));
    o.set("src", V::from(format!("data:image/png;base64,QUJD{len}")));
    o.set("width", V::from(if name.contains('작') { 0 } else { 64 + len }));
    o.set("height", V::from(if name.contains("납작") { 0 } else { 32 }));
    o.set("caption", V::from(if name.contains('캡') { format!("캡션 <{name}> & 글") } else { String::new() }));
    o.set("credit", V::from(if name.contains("출처") { "출처 \"글\"" } else { "" }));
    o.set("alt", V::from(if name.contains("대체") { format!("대체 '{name}'") } else { String::new() }));
    V::Obj(o)
}

fn render(src: &str, now: &str, image: bool, link: bool) -> wiki::Rendered {
    let (l, i): (&dyn Fn(&str) -> V, &dyn Fn(&str) -> V) = (&wiki_link, &wiki_image);
    let opts = RenderOpts { link: link.then_some(l), image: image.then_some(i), now_ms: ms_of(now), tz_min: 540 };
    wiki::render(src, &opts).unwrap_or_else(|e| panic!("렌더 오류 {src:?}: {e}"))
}
fn spec_json(s: &FileSpec) -> Value { json!({ "name": s.name, "width": s.width, "align": s.align }) }

/// 원본이 쓰는 꼴의 답이 '맞음'인가 — `.test`면 참, 바꿔 넣기면 글이 바뀜, 맞음 목록이면 비지 않음(빈 맞음이 나는 꼴은 없음).
fn matched(got: &Value, input: &str) -> bool {
    match got { Value::Bool(b) => *b, Value::Null => false, Value::String(s) => s != input, Value::Array(a) => !a.is_empty(), _ => true }
}
/// 늘 맞는 꼴이라 안 맞는 표본을 둘 수 없는 정규식(`^(\S*)\s?([\s\S]*)$` — 각주 속 나누기).
const ALWAYS_MATCHES: [&str; 1] = ["fn.inner"];

/// 정규식마다 표본 글 — 원본이 그 정규식을 쓰는 꼴(참거짓 · 바꿔 넣은 글 · 맞음 목록)로 Node와 같다. 그리고 Rust의 답으로 다시 단언한다(고침 1회차):
/// 벡터에 실은 갈래 목록(`wiki.branches`)의 갈래마다 맞은 표본이 하나 이상 · 갈래가 붙은 표본은 맞고 빈 갈래 표본은 안 맞음 · 정규식마다 안 맞는 표본이 하나 이상(늘 맞는 꼴 빼고).
#[test]
fn every_regex_matches_node_on_its_samples() {
    let declared: BTreeMap<&str, BTreeSet<&str>> = rows("branches").iter()
        .map(|r| (text(&r[0]), r[1].as_array().expect("갈래 목록").iter().map(text).collect())).collect();
    let mut hit: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    let mut negatives: BTreeMap<&str, usize> = BTreeMap::new();
    let mut total = 0usize;
    for r in rows("re") {
        let (id, branch, input, want) = (text(&r[0]), text(&r[1]), text(&r[2]), &r[3]);
        let got = wiki::probe(id, input).or_else(|| docs::probe(id, input)).or_else(|| web::when::probe(id, input)).unwrap_or_else(|| panic!("Rust가 모르는 정규식 id {id}"));
        assert_eq!(&got, want, "정규식 {id} · 갈래 {branch:?} · 표본 {input:?}");
        total += 1;
        let m = matched(&got, input);
        if branch.is_empty() {
            assert!(!m, "정규식 {id}: 안 맞아야 할 표본 {input:?}이(가) 맞았다");
            *negatives.entry(id).or_default() += 1;
        } else {
            assert!(m, "정규식 {id}: 갈래 {branch:?}의 표본 {input:?}이(가) 맞지 않았다");
            assert!(declared.get(id).is_some_and(|b| b.contains(branch)), "정규식 {id}: 벡터의 갈래 목록에 없는 갈래 {branch:?}");
            hit.entry(id).or_default().insert(branch);
        }
    }
    let ids: BTreeSet<&str> = declared.keys().copied().collect();
    let ours: BTreeSet<&str> = wiki::PROBES.iter().chain(docs::PROBES.iter()).chain(web::when::PROBES.iter()).copied().collect();
    assert_eq!(ids, ours, "벡터의 정규식 id와 Rust의 id(wiki · docs · when의 PROBES)가 다르다");
    for (id, branches) in &declared {
        assert!(!branches.is_empty(), "정규식 {id}: 갈래 목록이 비었다");
        let got = hit.get(id).cloned().unwrap_or_default();
        assert_eq!(&got, branches, "정규식 {id}: 맞은 표본이 없는 갈래가 있다");
        if !ALWAYS_MATCHES.contains(id) { assert!(negatives.get(id).copied().unwrap_or(0) >= 1, "정규식 {id}: 안 맞는 표본이 없다"); }
    }
    eprintln!("wiki 정규식 {}개 · 표본 {total}행 · 갈래 {}개 — Node와 같음(갈래마다 맞은 표본 · 안 맞는 표본을 Rust의 답으로 다시 확인)", declared.len(), declared.values().map(BTreeSet::len).sum::<usize>());
}

/// 날짜 글(`web::when` — docs의 곁글 · metro의 도읍 칸 기간이 쓰는 것)이 Node와 같다: `cal.describe`(음력 · 윤달 · 해 바뀜 · 같은 해 줄임 · 연월 · '부터' · 중국 음력 ·
/// 이슬람력 · 움 알쿠라 · 페르시아력 · 그레고리력 · 율리우스력 · 'x' · 시 · 분 · 세기 · 기원전 · 못 읽음) · `formatT` · `HT.formatDate` · `formatRange`(인물 포함) · `altText`.
/// 보조 달력은 정답지 자료와 같은 잘린 표(`seam_opts`)로 읽는다 — 그 표가 덮지 못한 날짜가 있으면 실패(고침 1회차).
#[test]
fn when_texts_match_node() {
    use archive_engine::lay::{cal, read};
    let rc = read::Ctx::new(&common::oracle::seam_opts(None)).expect("읽기 문맥");
    let mut seen = BTreeSet::new();
    let list = rows("when");
    for r in list {
        let (kind, branch, input, want) = (text(&r[0]), text(&r[1]), &r[2], &r[3]);
        seen.insert(branch);
        let got = match kind {
            "describe" => Value::from(cal::parse(&rc.cal, &js::from_json(input)).map_or(String::new(), |p| web::when::describe(&p))),
            "formatT" => Value::from(web::when::format_t(input[0].as_f64().unwrap_or(f64::NAN), text(&input[1]))),
            "formatDate" => Value::from(web::when::format_date(&rc, &js::from_json(&input[0]), &js::from_json(&input[1]))),
            "formatRange" => Value::from(web::when::format_range(&rc, &js::from_json(input))),
            "altText" => js::to_json(&web::when::alt_text(&rc, &js::from_json(&input[0]), &js::from_json(&input[1]))),
            other => panic!("모르는 날짜 글 종류 {other}"),
        };
        assert_eq!(&got, want, "날짜 글 {kind} · 갈래 {branch} · 입력 {input}");
    }
    assert!(rc.cal.missed_of().is_none() && rc.cal.absent_of().is_none(), "잘린 달력 표가 덮지 못한 날짜가 있다({:?} · {:?})", rc.cal.missed_of(), rc.cal.absent_of());
    let want: BTreeSet<&str> = vectors()["wiki"]["whenBranches"][0].as_array().expect("whenBranches").iter().map(text).collect();
    assert_eq!(seen, want, "날짜 글 갈래");
    eprintln!("날짜 글 {}행 · 갈래 {}개 — Node와 같음", list.len(), want.len());
}

/// `fileSpec` · `files` · `links` · `figureHTML` · `toolbarHTML` · `HELP` · `SHORTCUTS` · `FIGURE` · docs.mjs의 `sizeOf`(그림 머리 — atob)가 Node와 같다.
#[test]
fn functions_match_node() {
    let mut kinds = BTreeSet::new();
    for r in rows("fn") {
        let (name, input, want) = (text(&r[0]), &r[1], &r[2]);
        kinds.insert(name);
        let got = match name {
            "fileSpec" => spec_json(&wiki::file_spec(text(input))),
            "files" => Value::Array(wiki::files(text(input)).iter().map(spec_json).collect()),
            "links" => json!(wiki::links(text(input))),
            "figureHTML" => {
                let s = &input[0];
                let spec = FileSpec { name: text(&s["name"]).into(), width: text(&s["width"]).into(), align: text(&s["align"]).into() };
                let g = js::from_json(&input[1]);
                Value::from(wiki::figure_html(&spec, &g))
            }
            "toolbarHTML" => Value::from(wiki::toolbar_html(input["compact"].as_bool().unwrap_or(false), input["image"].as_bool().unwrap_or(false))),
            "HELP" => Value::from(wiki::HELP),
            "SHORTCUTS" => json!(wiki::SHORTCUTS.iter().map(|(k, d)| json!([k, d])).collect::<Vec<_>>()),
            "FIGURE" => Value::Object(wiki::FIGURE.iter().map(|(k, v)| (k.to_string(), json!(v))).collect()),
            "sizeOf" => { let (w, h) = docs::size_of(text(input)); json!([jv(w), jv(h)]) }
            other => panic!("모르는 함수 {other}"),
        };
        assert_eq!(&got, want, "{name}({input})");
    }
    let want: BTreeSet<&str> = ["fileSpec", "files", "links", "figureHTML", "toolbarHTML", "HELP", "SHORTCUTS", "FIGURE", "sizeOf"].into_iter().collect();
    assert_eq!(kinds, want, "함수 행의 갈래");
}

/// 렌더(`namu.render`)가 Node와 같다 — 제목 · 목차 · 각주 · 고리 · 접기 · 상자 · 표 · 인용 · 목록 · 그림 · 날짜 · 나이(시각 셋 — UTC로 하루 전 · 윤날).
#[test]
fn render_matches_node() {
    let list = rows("render");
    assert!(list.len() >= 20, "렌더 표본 {}개", list.len());
    for r in list {
        let (src, now) = (text(&r[0]), text(&r[1]));
        let got = render(src, now, r[2].as_bool().unwrap(), r[3].as_bool().unwrap());
        let want = &r[4];
        assert_eq!(got.html, text(&want["html"]), "렌더 html — 글 {src:?} · 시각 {now}");
        assert_eq!(js::to_json(&got.to_js()), *want, "렌더 toc · categories — 글 {src:?}");
    }
}

/// 견본 등불 연대기(`samples/sample-lantern.json`)의 문서 · wiki 칸 모두를 렌더한 답(JSON 글)의 sha12가 Node와 같다.
#[test]
fn sample_documents_render_like_node() {
    use sha2::{Digest, Sha256};
    // 연결 폴더(%TEMP%\ht-…)로 빌드해도 저장소 뿌리를 찾게 풀어 본다(tests/common/oracle.rs의 repo_root와 같은 길).
    let manifest = std::fs::canonicalize(env!("CARGO_MANIFEST_DIR")).expect("engine 폴더");
    let path = manifest.parent().and_then(Path::parent).expect("저장소 뿌리").join("samples").join("sample-lantern.json");
    let raw = js::parse(&std::fs::read_to_string(&path).expect("견본")).expect("견본 JSON");
    // js-vectors.mjs와 같은 차례: documents의 값 → 어디든 wiki 칸(적힌 차례 · 맨 위의 documents는 건넘)
    let mut docs: Vec<(String, String)> = Vec::new();
    if let Some(d) = raw.get("documents").as_obj() {
        for (k, v) in d.entries() {
            let t = match &v { V::Str(s) => s.as_str().into_owned(), V::Obj(_) => js::to_str(&js::or(v.get("text"), V::from(""))).as_str().into_owned(), _ => String::new() };
            docs.push((format!("documents/{k}"), t));
        }
    }
    fn walk(x: &V, at: &str, out: &mut Vec<(String, String)>) {
        match x {
            V::Arr(a) => for (i, y) in a.to_vec().iter().enumerate() { walk(y, &format!("{at}/{i}"), out); },
            V::Obj(o) => for (k, v) in o.entries() {
                if &*k.as_str() == "wiki" { if let V::Str(s) = &v { out.push((format!("{at}/wiki"), s.as_str().into_owned())); continue; } }
                if &*k.as_str() != "documents" || !at.is_empty() { walk(&v, &format!("{at}/{k}"), out); }
            },
            _ => {}
        }
    }
    walk(&raw, "", &mut docs);
    js::release(&raw);
    let want = rows("sample");
    assert_eq!(docs.len(), want.len(), "견본 문서 수");
    for ((key, body), w) in docs.iter().zip(want) {
        assert_eq!(key, text(&w[0]), "견본 문서의 차례");
        let r = render(body, "2026-10-15T12:00:00+09:00", true, true);
        let sha: String = Sha256::digest(js::stringify(&r.to_js()).as_bytes()).iter().take(6).map(|b| format!("{b:02x}")).collect();
        assert_eq!(sha, text(&w[1]), "견본 문서 {key}의 렌더가 Node와 다르다");
    }
    eprintln!("견본 문서 {}개 — 렌더가 Node와 같음", docs.len());
}

/// 옮기는 규칙(계획 머리 표)대로 JS 정규식(작은 꼴 — `\s` · `\w` · `\d` · `\b` · `.` · 글자 · 깃발 i · u · s)을 regex 패턴으로.
/// u가 없으면 `.`은 코드 단위 하나라 확장 글자(U+10000 넘음)와 맞지 않고, i는 ASCII 글자만 접는다(유니코드 접기는 u와 함께일 때만).
fn rule(src: &str, flags: &str) -> String {
    let (i, u, s) = (flags.contains('i'), flags.contains('u'), flags.contains('s'));
    let ws = r"[\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]";
    let mut out = String::new();
    let mut it = src.chars();
    while let Some(c) = it.next() {
        match c {
            '\\' => match it.next() {
                Some('s') => out += ws,
                Some('w') => out += if i && u { "(?i:[A-Za-z0-9_])" } else { "[A-Za-z0-9_]" },
                Some('d') => out += "[0-9]",
                Some('b') => out += r"(?-u:\b)",
                Some(o) => panic!("규칙 표에 없는 이스케이프 \\{o}"),
                None => panic!("끝의 \\"),
            },
            '.' => out += if s { "(?s:.)" } else if u { r"[^\n\r\x{2028}\x{2029}]" } else { r"[^\n\r\x{2028}\x{2029}\x{10000}-\x{10FFFF}]" },
            '^' | '$' => out.push(c),
            c if c.is_ascii_alphabetic() && i => out += &if u { format!("(?i:{c})") } else { format!("(?i-u:{c})") },
            c if i && u => out += &format!("(?i:{c})"),
            c => out += &regex::escape(&c.to_string()),
        }
    }
    out
}
/// 과제 3의 `regex` 갈래(뜻 차이 규칙의 표본 — JS `new RegExp(src, flags).test(글)`)가 규칙대로 옮긴 regex와 같다.
#[test]
fn regex_rule_rows_match_node() {
    let list = vectors()["regex"].as_array().expect("regex 갈래");
    assert!(list.len() >= 27, "regex 갈래 {}행", list.len());
    for r in list {
        let (src, flags, input, want) = (text(&r[0]), text(&r[1]), text(&r[2]), r[3].as_bool().unwrap());
        let re = Regex::new(&rule(src, flags)).unwrap_or_else(|e| panic!("/{src}/{flags}: {e}"));
        assert_eq!(re.is_match(input), want, "/{src}/{flags}.test({input:?})");
    }
}

/// 과제 Y(갈래 D 걱정 1 ④): `cal.describe`가 달력 표에 없는 달력(`CAL.get(r.cal)`이 undefined)을 만나면 JS는 `c.name`에서 TypeError — Rust는 조용히 다른 글
/// (C의 판 '' · D의 판 'undefined')을 내지 않고 잘못(`model::util::fault`)을 남긴다(모듈 끝에서 그 모듈의 오류). 읽기가 만든 결과는 늘 아는 달력이라 손으로 바꿔 본다.
#[test]
fn describe_of_unknown_calendar_is_a_fault() {
    use archive_engine::lay::{cal, model::util::take_fault, read};
    let rc = read::Ctx::new(&common::oracle::seam_opts(None)).expect("읽기 문맥");
    let mut r = cal::parse(&rc.cal, &V::from("음력 1592-04-13")).expect("읽힘");
    assert!(r.ok, "음력 날짜를 읽어야 합니다");
    let _ = take_fault();
    assert!(!web::when::describe(&r).is_empty());
    assert!(take_fault().is_none(), "아는 달력에서는 잘못이 없어야 합니다");
    r.cal = "가상-달력";
    assert_eq!(web::when::describe(&r), "");
    let f = take_fault().expect("모르는 달력이면 잘못이 남아야 합니다");
    assert!(f.contains("모르는 달력") && f.contains("가상-달력"), "{f}");
}

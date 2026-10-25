//! P3 정답지 도구: 자료 목록(`prototype/fixtures/oracle/list.json`) · Node가 뽑은 정답지(`prototype/results/oracle/<자료>/…`) 읽기 · 견주기.
//! 정답지는 `node prototype/scripts/layout-oracle.mjs`가 시각 · 시간대를 고정해(`2026-10-15T12:00:00+09:00` · `Asia/Seoul`) 뽑는다.
//! Rust는 같은 시각을 `Opts.now_ms` · `tz_min`(540)으로 받는다 — 아래 상수 · 머리 `$oracle`의 `now` · `tz`가 어긋나면 정답지를 믿을 수 없어 멈춘다.
//! 머리의 `rules`(웹 코드 · 내보내기 모듈의 지문 — `lay-rules.mjs`) · `icu`(뽑은 Node의 ICU)도 지금 원본 · 잘린 달력 표와 같아야 한다(판정 R58 ⑤-4 — [`check_head`]):
//! 정답지는 git 밖이라, 웹 코드를 고친 뒤 다시 뽑지 않으면 낡은 정답지로 초록이 나던 구멍을 막는다. 정답지가 아예 없어도 조용히 지나가지 않는다.
#![allow(dead_code)]
use archive_engine::lay::{same::{diff, diff_json_text}, Opts, PackIn, Scope};
use serde_json::Value;
use std::path::{Path, PathBuf};

/// 정답지가 고정한 '오늘' — `prototype/scripts/layout-oracle.mjs`의 `ORACLE_NOW`와 같은 값.
pub const ORACLE_NOW: &str = "2026-10-15T12:00:00+09:00";
/// 위 시각의 1970-01-01T00:00:00Z부터의 밀리초(2026-10-15T03:00:00Z).
pub const ORACLE_NOW_MS: f64 = 1_792_033_200_000.0;
pub const ORACLE_TZ: &str = "Asia/Seoul";
pub const ORACLE_TZ_MIN: i32 = 540;

/// 견줄 자료 하나. `inputs`는 파일로 있는 입력(내장이 아닌 기본 DLC가 있으면 그것이 첫째, 그 뒤 더 얹는 DLC 차례).
/// 내장 DLC(`builtin`)는 `prototype/fixtures/oracle/<이름>.json`이 기본 DLC다(`inputs(f)`가 맨 앞에 붙인다).
/// `oracle_base`: 정답지(oracle/one.mjs)가 기본 DLC로 읽은 것 — base를 sample → builtin → file 차례로 본다(Rust 입력은 file이 builtin보다 앞이라 다를 수 있다:
/// `{"builtin":"east-asia","file":"east-asia.json"}`이면 정답지는 내장 팩을, Rust는 굳힌 파일을 읽는다). 머리 `sources`를 견줄 때 쓴다.
/// `cal_clip`: `list.json`의 `"calClip": true` 표지 — 자료 해 ± 100년이 저장소 달력 표 밖으로 나가는 자료([`cal_clip_known`] · 판정 R64-2). `<이름>@f4`는 `@f4`를 뗀 이름의 표지를 따른다.
pub struct Fixture { pub name: String, pub inputs: Vec<PathBuf>, pub builtin: Option<String>, pub known: Option<String>, pub oracle_base: OracleBase, pub cal_clip: bool }

/// 정답지가 기본 DLC로 읽은 것(oracle/one.mjs의 base 해석 차례).
#[derive(Clone, Debug)]
pub enum OracleBase { Sample(String), Builtin(String), File(PathBuf) }

/// 저장소 뿌리(`samples/` · `prototype/`이 있는 곳). 연결 폴더(`%TEMP%\ht-…`)로 빌드해도 진짜 자리를 찾도록 풀어 본다
/// (연결 폴더 밑에서 `..`로 올라가면 저장소가 아니라 임시 폴더가 나온다).
fn repo_root() -> PathBuf {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let real = std::fs::canonicalize(manifest).unwrap_or_else(|_| manifest.to_path_buf());
    real.parent().and_then(Path::parent).expect("engine 폴더 위에 저장소 뿌리가 없습니다").to_path_buf()
}

/// `/` · `\`로 나뉜 상대 경로를 한 칸씩 이어 붙인다(`\\?\`로 풀어 낸 경로는 `/`를 구분자로 보지 않는다). 이미 절대 경로면 그대로.
fn rel(base: &Path, text: &str) -> PathBuf {
    let given = Path::new(text);
    if given.is_absolute() { return given.to_path_buf(); }
    text.split(['/', '\\']).filter(|s| !s.is_empty()).fold(base.to_path_buf(), |p, s| p.join(s))
}

/// 감독의 실자료 KoreanTimeLine v1.0.5(KTL — 저장소에 싣지 않는 선택 자료)의 옛 자리(감독 PC) — `list.json`의 extra에 이 글이 적혀 있다.
/// 검사는 [`ktl_path`]로 찾는다(판정 R58 ⑤-5 · Node 쪽은 `prototype/scripts/oracle/ktl.mjs` — 같은 규칙).
pub const KTL_DEFAULT: &str = "D:/Timeline/KoreanTimeLine-v1.0.5.htpack";

/// KTL 자리 — 환경 변수 `HT_KTL`(없으면 [`KTL_DEFAULT`]).
pub fn ktl_path() -> PathBuf {
    PathBuf::from(std::env::var("HT_KTL").ok().map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()).unwrap_or_else(|| KTL_DEFAULT.to_owned()))
}

/// `HT_REQUIRE_KTL=1`인가 — 그러면 KTL이 없을 때 건너뛰지 않고 실패한다(감독 PC · 공식 검사에서 KTL 검사가 소리 없이 빠지지 않게).
pub fn require_ktl() -> bool { std::env::var("HT_REQUIRE_KTL").is_ok_and(|v| v.trim() == "1") }

/// KTL이 없을 때 — `HT_REQUIRE_KTL=1`이면 멈추고, 아니면 까닭을 알린다(부르는 쪽이 건너뜀). `what`은 건너뛰는 검사 · 자료의 이름.
pub fn ktl_missing(what: &str) {
    let at = ktl_path();
    assert!(!require_ktl(), "{what}: KTL이 없습니다({}) — HT_REQUIRE_KTL=1이라 건너뛰지 않고 멈춥니다(자리는 HT_KTL로)", at.display());
    eprintln!("건너뜀 {what} — 감독의 실자료 KTL이 없습니다({} · 자리는 HT_KTL · 없으면 실패하게 하려면 HT_REQUIRE_KTL=1)", at.display());
}

/// `list.json`의 입력 글 하나를 경로로 — 옛 KTL 자리([`KTL_DEFAULT`])는 [`ktl_path`]로 갈아 낀다.
fn list_file(dir: &Path, text: &str) -> PathBuf { if text == KTL_DEFAULT { ktl_path() } else { rel(dir, text) } }

fn fixtures_dir() -> PathBuf { repo_root().join("prototype").join("fixtures").join("oracle") }
/// 정답지 파일이 놓이는 폴더(`prototype/results/oracle` — git 밖).
pub fn results_dir() -> PathBuf { repo_root().join("prototype").join("results").join("oracle") }

fn read_json(path: &Path) -> Value {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("{} 은(는) JSON이 아닙니다: {e}", path.display()))
}

/// 목록의 자료. 선택 자료(`optional`)의 파일이 없거나 · 내장 DLC의 JSON(`<이름>.json` — 과제 2가 굳힘)이 아직 없으면 빼고 까닭을 알린다. 선택이 아닌 자료의 파일이 없으면 멈춘다.
/// `known`(까닭)은 `f4-same-check` 전용 표시('원본과 다르다' — 예: 형식 4 올림이 옛 뜻을 바꾸는 곳)라 건너뛰는 데 쓰지 않는다:
/// 그런 자료(지금은 선택 자료 `east-asia+ktl@f4` — `lantern@f4`는 견본 2.0.1부터 다름이 없어 걷었다)도 제 정답지(`results/oracle/<그 이름>/`)로 돌린다.
/// `Fixture.known`에는 까닭을 정보로만 싣는다.
pub fn fixtures() -> Vec<Fixture> {
    let (dir, root) = (fixtures_dir(), repo_root());
    let list = read_json(&dir.join("list.json"));
    let marked: Vec<&str> = list.as_array().expect("list.json의 맨 위는 배열이어야 합니다").iter()
        .filter(|item| item["calClip"].as_bool().unwrap_or(false)).filter_map(|item| item["name"].as_str()).collect();
    let mut out = Vec::new();
    for item in list.as_array().expect("list.json의 맨 위는 배열이어야 합니다") {
        let name = item["name"].as_str().expect("list.json 자료에 name이 없습니다").to_string();
        let mut inputs = Vec::new();
        let mut builtin = None;
        let base = &item["base"];
        if let Some(sample) = base["sample"].as_str() { inputs.push(root.join("samples").join(format!("{sample}.json"))); }
        else if let Some(file) = base["file"].as_str() { inputs.push(rel(&dir, file)); }
        else if let Some(b) = base["builtin"].as_str() { builtin = Some(b.to_string()); }
        else { panic!("자료 {name}: base는 sample · builtin · file 중 하나여야 합니다"); }
        let oracle_base = if let Some(sample) = base["sample"].as_str() { OracleBase::Sample(sample.to_string()) }
            else if let Some(b) = base["builtin"].as_str() { OracleBase::Builtin(b.to_string()) }
            else { OracleBase::File(rel(&dir, base["file"].as_str().expect("base.file"))) };
        for extra in item["extra"].as_array().map(Vec::as_slice).unwrap_or(&[]) { inputs.push(list_file(&dir, extra.as_str().expect("extra는 글 목록"))); }

        let missing: Vec<&PathBuf> = inputs.iter().filter(|p| !p.exists()).collect();
        if !missing.is_empty() {
            let shown = missing.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(" · ");
            if item["optional"].as_bool().unwrap_or(false) {
                // KTL이 빠진 것이면 HT_REQUIRE_KTL=1일 때 멈춘다(판정 R58 ⑤-5) — 그 밖의 선택 파일(형식 4 사본 f4/KoreanTimeLine… 등)은 알리고 건너뜀.
                if missing.iter().any(|p| **p == ktl_path()) { ktl_missing(&format!("자료 {name}")); } else { eprintln!("건너뜀 {name} — 선택 자료의 파일이 없습니다: {shown}"); }
                continue;
            }
            panic!("자료 {name}의 파일이 없습니다: {shown}");
        }
        if let Some(b) = &builtin {
            let json = dir.join(format!("{b}.json"));
            if !json.exists() { eprintln!("건너뜀 {name} — 내장 {b}의 JSON({})이 아직 없습니다", json.display()); continue; }
        }
        let known = item["known"].as_str().map(str::to_string); // 정보 — 건너뛰는 데 쓰지 않는다
        let cal_clip = is_cal_clip(&marked, &name);
        out.push(Fixture { name, inputs, builtin, known, oracle_base, cal_clip });
    }
    out
}

/// 표지(`calClip`)가 붙은 자료 이름들(`marked`)에 `name`이 드는가 — 형식 4 사본(`<이름>@f4`)은 `@f4`를 뗀 이름으로 맞춘다(판정 R64-2 · 검토 M4).
pub fn is_cal_clip(marked: &[&str], name: &str) -> bool {
    let base = name.strip_suffix("@f4").unwrap_or(name);
    marked.contains(&base)
}

/// SHA-256 앞 12자(16진) — oracle/one.mjs의 `sha12`와 같다.
fn sha12(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes).iter().take(6).map(|b| format!("{b:02x}")).collect()
}

/// 내장 DLC의 지문 글 — oracle/builtin.mjs의 `loadBuiltin`과 같다: index.html이 싣는 `packs/<이름>/…js`를 그 차례로 `이름\n내용`으로 이어 `\n`으로 붙인 것.
/// 돌려주는 값: (파일 수, 지문 글의 바이트).
fn builtin_text(name: &str) -> (usize, Vec<u8>) {
    let root = repo_root();
    let html = std::fs::read_to_string(root.join("index.html")).expect("index.html");
    // `/<script src="(packs\/[^"]+\.js)"/g` — 따옴표 안의 값이 `packs/` + 한 글자 이상 + `.js`.
    let mut files = Vec::new();
    let mut rest = html.as_str();
    while let Some(at) = rest.find("<script src=\"") {
        rest = &rest[at + "<script src=\"".len()..];
        let Some(end) = rest.find('"') else { break };
        let value = &rest[..end];
        if value.starts_with("packs/") && value.ends_with(".js") && value.len() > "packs/".len() + ".js".len() && value.starts_with(&format!("packs/{name}/")) {
            files.push(value.to_string());
        }
    }
    assert!(!files.is_empty(), "index.html에 packs/{name}/ 의 스크립트가 없습니다");
    let parts: Vec<String> = files.iter().map(|f| {
        let text = std::fs::read_to_string(rel(&root, f)).unwrap_or_else(|e| panic!("{f} 을(를) 읽지 못했습니다: {e}"));
        format!("{f}\n{text}")
    }).collect();
    (files.len(), parts.join("\n").into_bytes())
}

/// 정답지가 읽은 입력의 (이름, 지문) — oracle/one.mjs의 `fileInput` · `builtinInput`이 머리 `sources`에 적는 것과 같은 셈.
pub fn expected_sources(f: &Fixture) -> Vec<(String, String)> {
    let file_source = |p: &Path, label: String| -> (String, String) {
        let bytes = std::fs::read(p).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e}", p.display()));
        (label, sha12(&bytes))
    };
    let mut out = Vec::new();
    match &f.oracle_base {
        OracleBase::Sample(s) => out.push(file_source(&repo_root().join("samples").join(format!("{s}.json")), format!("samples/{s}.json"))),
        OracleBase::Builtin(b) => { let (n, text) = builtin_text(b); out.push((format!("packs/{b}({n}파일)"), sha12(&text))); }
        OracleBase::File(p) => out.push(file_source(p, p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default())),
    }
    // 더 얹는 DLC: Rust 입력의 기본 DLC(내장이면 inputs에 없음 · sample이나 file이면 inputs[0]) 뒤의 것.
    let skip = if f.builtin.is_some() { 0 } else { 1 };
    for p in f.inputs.iter().skip(skip) { out.push(file_source(p, p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default())); }
    out
}

/// 내보내기 원본(웹 코드 `js/<이름>.js` · 내보내기 모듈 `prototype/scripts/export/*.mjs`)의 이름 둘 — (웹 코드, 모듈), 각각 이름 차례.
/// `prototype/scripts/lay-rules.mjs`의 `sources()`와 같은 셈(모듈은 `_`로 시작하는 옛 원본을 뺌 · 웹 코드는 모듈 글에서 따옴표(홑 · 겹 · 뒤)로 싼 `js/<이름>.js`).
pub fn js_rule_sources() -> (Vec<String>, Vec<String>) {
    let export_dir = repo_root().join("prototype").join("scripts").join("export");
    let mut mods: Vec<String> = std::fs::read_dir(&export_dir).expect("export 폴더").flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| n.ends_with(".mjs") && !n.starts_with('_')).collect();
    mods.sort();
    let mut web = std::collections::BTreeSet::new();
    for m in &mods {
        let text = std::fs::read_to_string(export_dir.join(m)).expect("모듈 글");
        // 여는 따옴표와 같은 것으로 닫힌 것만(판정 R46 Minor: 예전엔 홑따옴표만)
        for q in ['\'', '"', '`'] {
            let open = format!("{q}js/");
            let mut rest = text.as_str();
            while let Some(i) = rest.find(&open) {
                rest = &rest[i + open.len()..];
                let Some(end) = rest.find(q) else { break };
                let name = &rest[..end];
                if name.ends_with(".js") && name.bytes().all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b)) {
                    web.insert(name.to_string());
                }
            }
        }
    }
    (web.into_iter().collect(), mods)
}

/// 지금 원본의 지문 글(`lay-rules.mjs`의 `rules()` — `<파일 이름>:<LF로 맞춘 바이트의 SHA-256 앞 12자>`를 웹 코드 → 모듈 차례로 빈칸으로 이음).
/// `lay::RULES`(tests/lay_scope.rs가 견줌)와 정답지 머리의 `rules`(판정 R58 ⑤-4 — [`oracle`]이 견줌)가 이 값이어야 한다. 한 프로세스에 한 번만 셈한다.
pub fn js_rules() -> String {
    static RULES_NOW: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    RULES_NOW.get_or_init(|| {
        use sha2::{Digest, Sha256};
        let root = repo_root();
        let sha12 = |path: PathBuf| -> String {
            let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            let mut lf = Vec::with_capacity(bytes.len());
            let mut i = 0;
            while i < bytes.len() {
                if bytes[i] == b'\r' && bytes.get(i + 1) == Some(&b'\n') {
                    i += 1;
                    continue;
                }
                lf.push(bytes[i]);
                i += 1;
            }
            Sha256::digest(&lf).iter().take(6).map(|b| format!("{b:02x}")).collect()
        };
        let (web, mods) = js_rule_sources();
        let export_dir = root.join("prototype").join("scripts").join("export");
        web.iter().map(|n| format!("{n}:{}", sha12(root.join("js").join(n))))
            .chain(mods.iter().map(|n| format!("{n}:{}", sha12(export_dir.join(n))))).collect::<Vec<_>>().join(" ")
    }).clone()
}

/// 잘린 달력 표([`calendar_slice`])를 뜬 ICU 판(`icu`) — 정답지 머리의 `icu`가 이 값이어야 한다(Node의 ICU로 셈한 정답지를 이 표로 읽는 Rust와 견주므로).
pub fn slice_icu() -> String {
    let v: Value = serde_json::from_slice(&calendar_slice()).expect("calendar-slice.json은 JSON이어야 합니다");
    v["icu"].as_str().expect("calendar-slice.json에 icu가 없습니다").to_string()
}

/// 정답지 머리 `$oracle`을 지금 값과 견준다 — 시각 · 시간대(위 상수) · 입력 지문(`sources`) · 웹 코드 판(`rules` = [`js_rules`]) · ICU 판(`icu` = [`slice_icu`]).
/// 하나라도 다르면 '정답지가 낡음 — 다시 뽑으세요'로 멈춘다(판정 R58 ⑤-4: 웹 코드 · 내보내기 모듈을 고친 뒤 git 밖 정답지를 다시 뽑지 않으면 낡은 정답지로도 초록이던 구멍).
pub fn check_head(f: &Fixture, path: &Path, head: &Value) {
    assert!(head["now"] == ORACLE_NOW && head["tz"] == ORACLE_TZ,
        "정답지 {}의 시각 · 시간대({} · {})가 이 검사({ORACLE_NOW} · {ORACLE_TZ})와 다릅니다 — 다시 뽑으세요", path.display(), head["now"], head["tz"]);
    let got: Vec<(String, String)> = head["sources"].as_array().map(|list| list.iter().map(|s| {
        (s["name"].as_str().unwrap_or_default().to_string(), s["sha"].as_str().unwrap_or_default().to_string())
    }).collect()).unwrap_or_default();
    let want = expected_sources(f);
    assert!(got == want,
        "정답지 {}의 원본 지문이 지금 입력과 다릅니다 — 입력이 바뀌었으면 다시 뽑으세요: node prototype/scripts/layout-oracle.mjs --only={}\n  정답지: {got:?}\n  지금:   {want:?}",
        path.display(), f.name);
    let rules = head["rules"].as_str();
    assert!(rules == Some(js_rules().as_str()),
        "정답지가 낡음 — {}를 뽑은 뒤 웹 코드 · 내보내기 모듈(원본 지문 rules)이 바뀌었습니다{}: node prototype/scripts/layout-oracle.mjs를 다시 돌리세요",
        path.display(), if rules.is_none() { "(머리에 rules가 없음 — 판 표시 전에 뽑은 정답지)" } else { "" });
    let icu = head["icu"].as_str();
    let slice = slice_icu();
    assert!(icu == Some(slice.as_str()),
        "정답지가 낡음 — {}를 뽑은 Node의 ICU({})가 잘린 달력 표(calendar-slice.json)의 ICU({slice})와 다릅니다: 그 ICU의 Node로 node prototype/scripts/layout-oracle.mjs를 다시 돌리세요",
        path.display(), icu.unwrap_or("머리에 없음"));
}

/// 정답지 파일(`norm-0.json` · `prep.json` · `rows.json` · `upto-<모듈>.json`)을 읽는다 — 머리 `$oracle`의 시각 · 시간대가 위 상수와 다르거나,
/// 머리 `sources`(입력의 이름 · SHA-256 앞 12자)가 지금 입력 파일과 다르거나(시험 DLC나 내장 팩을 고친 뒤 정답지를 다시 뽑지 않은 것), 웹 코드 판(`rules`) ·
/// ICU 판(`icu`)이 지금과 다르면 멈춘다([`check_head`]). 파일이 없으면 뽑는 명령을 알려 주며 실패한다.
pub fn oracle(f: &Fixture, file: &str) -> Value {
    let path = results_dir().join(&f.name).join(file);
    assert!(path.exists(), "정답지 {} 이(가) 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs --only={} --seams=norm,prep,rows,out,mods", path.display(), f.name);
    let v = read_json(&path);
    check_head(f, &path, &v["$oracle"]);
    v
}

/// 이름으로 고른 자료의 정답지 파일 — 그 자료가 이 PC에 없으면(선택 자료의 파일이 없음 — [`fixtures`]가 알림) None, 있으면 [`oracle`](파일이 없거나 낡으면 멈춘다 —
/// 예전엔 파일을 바로 읽어 정답지가 없으면 건너뛰고 · 낡아도 견줬다: 판정 R58 ⑤ Minor). 목록에 없는 이름이면 멈춘다.
pub fn oracle_named(name: &str, file: &str) -> Option<Value> {
    let list = read_json(&fixtures_dir().join("list.json"));
    assert!(list.as_array().is_some_and(|l| l.iter().any(|x| x["name"] == name)), "list.json에 없는 자료: {name}");
    fixtures().into_iter().find(|f| f.name == name).map(|f| oracle(&f, file))
}

/// 이음매 ②의 정답지(`prep.json` · `rows.json`)를 JS 값으로 읽는다 — 덤프가 깊어(경로 깊이 100 넘음) serde의 되부름 한계(128)에 닿지 않게
/// 깊이 한계가 없는 `js::parse`로(얹힌 몫 7). 머리 `$oracle`의 시각 · 시간대 · 원본 지문은 [`oracle`]과 같은 검사. 돌려주는 값: 머리를 뗀 본문
/// (`js::stringify`하면 Node가 쓴 본문 글과 바이트까지 같다 — 덤프 글은 JSON.stringify 꼴이라 읽고 다시 적어도 그대로).
pub fn oracle_js(f: &Fixture, file: &str) -> archive_engine::lay::js::V {
    use archive_engine::lay::js;
    let path = results_dir().join(&f.name).join(file);
    assert!(path.exists(), "정답지 {} 이(가) 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs --only={} --seams=norm,prep,rows,out", path.display(), f.name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e}", path.display()));
    let v = js::parse(&text).unwrap_or_else(|e| panic!("{} 은(는) JSON이 아닙니다: {e}", path.display()));
    let head = js::to_json(&v.get("$oracle"));
    check_head(f, &path, &head);
    if let Some(o) = v.as_obj() { o.delete("$oracle"); }
    v
}

/// 정답지 파일 본문의 **바이트 그대로**(머리 `$oracle`만 뗌 — 고침 1회차: 읽고 다시 적지 않는다). 파일은 `{"$oracle":<머리>,<본문의 나머지>` + 줄 바꿈이므로
/// 머리 값 하나를 글 그대로 건너뛰고(따옴표 · 이스케이프를 따라 괄호를 셈) `{`를 다시 붙인다. 머리 검사는 [`oracle_js`]와 같다.
pub fn oracle_body(f: &Fixture, file: &str) -> String {
    archive_engine::lay::js::release(&oracle_js(f, file)); // 머리(시각 · 시간대 · 원본 지문) 검사
    let path = results_dir().join(&f.name).join(file);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e}", path.display()));
    const HEAD: &str = "{\"$oracle\":";
    assert!(text.starts_with(HEAD), "{}: 머리 $oracle로 시작하지 않습니다", path.display());
    let b = text.as_bytes();
    let (mut i, mut depth, mut in_str, mut esc) = (HEAD.len(), 0usize, false, false);
    loop {
        let c = *b.get(i).unwrap_or_else(|| panic!("{}: 머리가 닫히지 않았습니다", path.display()));
        i += 1;
        if in_str {
            if esc { esc = false } else if c == b'\\' { esc = true } else if c == b'"' { in_str = false }
            continue;
        }
        match c {
            b'"' => in_str = true,
            b'{' | b'[' => depth += 1,
            b'}' | b']' => { depth -= 1; if depth == 0 { break; } }
            _ => {}
        }
    }
    let rest = text[i..].strip_prefix(',').unwrap_or(&text[i..]);
    let rest = rest.strip_suffix('\n').unwrap_or(rest);
    format!("{{{rest}")
}

/// 입력 DLC의 바이트 — 첫째가 기본 DLC(내장이면 `<이름>.json`), 나머지는 켠 차례.
pub fn inputs(f: &Fixture) -> Vec<PackIn> {
    let mut paths = Vec::new();
    if let Some(b) = &f.builtin { paths.push(fixtures_dir().join(format!("{b}.json"))); }
    paths.extend(f.inputs.iter().cloned());
    paths.iter().map(|p| PackIn {
        name: p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        bytes: std::fs::read(p).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다: {e}", p.display())),
    }).collect()
}

/// 정답지와 차이 0이어야 한다 — 다르면 경로가 든 차이를 앞 20개까지 보이며 멈춘다(알려진 차이 [`cal_clip_known`]만 확인한 뒤 같게 둔다).
pub fn assert_same(f: &Fixture, what: &str, got: &Value, want: &Value) {
    const SHOWN: usize = 20;
    let (clipped, _) = cal_clip_known(f, got, want);
    let got = clipped.as_ref().unwrap_or(got);
    let d = diff(got, want, SHOWN);
    assert!(d.is_empty(), "자료 {} · {what}: 정답지와 다릅니다(앞 {}개까지)\n  {}", f.name, SHOWN, d.join("\n  "));
}

/// `json` 열쇠의 글(항목 기록 · 판 기록의 JSON 글)이 **바이트로도** 같아야 한다(과제 8-틀 고침 1회차 — 열쇠 차례 · 수 글까지). [`assert_same`] 뒤에 부른다 —
/// 값은 같은데 글만 다르면 그 자리(`entities.12.json(uid …)`)와 처음 다른 바이트의 둘레를 보이며 멈춘다. 왼쪽이 Rust · 오른쪽이 Node.
pub fn assert_same_bytes(f: &Fixture, what: &str, got: &Value, want: &Value) {
    const SHOWN: usize = 5;
    let (clipped, _) = cal_clip_known(f, got, want);
    let got = clipped.as_ref().unwrap_or(got);
    let d = diff_json_text(got, want, SHOWN);
    assert!(d.is_empty(), "자료 {} · {what}: 값은 같은데 json 글이 다릅니다(앞 {}개까지 · 왼쪽 Rust · 오른쪽 Node)\n  {}", f.name, SHOWN, d.join("\n  "));
}

/// 알려진 차이(판정 R61): Rust의 내보내기 `calendar` 모듈은 달력 표 밖 구간을 싣지 않고(`note`에 '표 밖 생략'), Node는 모자란 범위를 ICU로 다시 떠 싣는다.
/// `list.json`에서 `"calClip": true`로 표지한 자료([`Fixture::cal_clip`] · 판정 R64-2)에서만 · `entities`의 `cal:` 기록(같은 자리 · 같은 uid)의 `json` 칸만 본다 — 확인과 바꾸기는 [`cal_clip_swap`].
/// 돌려주는 값: (바꾼 사본 — 바꾼 것이 없으면 None, 잘린 기록 수). 표지 없는 자료는 늘 (None, 0).
pub fn cal_clip_known(f: &Fixture, got: &Value, want: &Value) -> (Option<Value>, usize) {
    if !f.cal_clip { return (None, 0); }
    cal_clip_swap(&f.name, got, want)
}

/// 표지와 상관없이 같은 확인을 한다(표를 한쪽만 자른 검사처럼 표지 없는 자료에 일부러 잘린 표를 넘기는 검사가 부른다): `cal:` 기록의 `json`이 다르면 Rust 표가
/// **Node 표의 이어진 한 토막**인지(같은 달력 · 이름 · 앞말 · 음력 여부 · Node 표 안 · 실제로 잘림 · Node 표를 첫 달부터 걸어 Rust 표의 첫날에 닿고 그때의 해가 `year0` · 달 글이 그 자리의 글과 같음 ·
/// `count`와 `to`가 달 글과 맞음 · `note`가 '표 밖 생략 — 자료 범위 <lo>년 ~ <hi>년 …'으로 시작하고 그 해 범위가 Node 표가 덮은 범위와 맞음) 확인한 뒤
/// 그 칸을 Node의 글로 바꾼 사본을 돌려준다(틀리면 멈춘다). 그 밖의 칸 · 자료는 그대로 — 남는 차이는 부르는 쪽([`assert_same`] · [`assert_same_bytes`])이 잡는다.
pub fn cal_clip_swap(label: &str, got: &Value, want: &Value) -> (Option<Value>, usize) {
    let (Some(g), Some(w)) = (got["entities"].as_array(), want["entities"].as_array()) else { return (None, 0) };
    let mut out: Option<Value> = None;
    let mut n = 0;
    for (i, (ge, we)) in g.iter().zip(w).enumerate() {
        if ge["kind"] != "cal" || we["kind"] != "cal" || ge["uid"] != we["uid"] || ge["json"] == we["json"] { continue; }
        let (Some(gt), Some(wt)) = (ge["json"].as_str(), we["json"].as_str()) else { continue };
        let at = format!("자료 {label} · entities.{i}({})", ge["uid"]);
        let gb: Value = serde_json::from_str(gt).unwrap_or_else(|e| panic!("{at}: Rust json이 JSON이 아닙니다 — {e}"));
        let wb: Value = serde_json::from_str(wt).unwrap_or_else(|e| panic!("{at}: Node json이 JSON이 아닙니다 — {e}"));
        check_cal_clip(&at, &gb, &wb);
        out.get_or_insert_with(|| got.clone())["entities"][i]["json"] = we["json"].clone();
        n += 1;
    }
    (out, n)
}

/// 잘린 표의 `note` 첫 토막 — `lay/m/calendar.rs`의 `clip_note`와 같은 글: `표 밖 생략 — 자료 범위 <lo>년 ~ <hi>년 가운데 저장소 달력 표가 덮는 곳만 실음`(뒤에 ` · 이 범위에서는 …`가 붙을 수 있다).
const CLIP_NOTE_HEAD: &str = "표 밖 생략 — 자료 범위 ";
const CLIP_NOTE_TAIL: &str = "년 가운데 저장소 달력 표가 덮는 곳만 실음";

/// [`cal_clip_swap`]의 확인 — Rust 표(`g`)가 Node 표(`w`)의 이어진 한 토막이다(달 글 · 날 번호 · 해까지).
pub fn check_cal_clip(at: &str, g: &Value, w: &Value) {
    for k in ["cal", "calName", "lunar", "prefix"] { assert!(g[k] == w[k], "{at}: {k}가 다릅니다({} · {})", g[k], w[k]); }
    let num = |v: &Value, k: &str| v[k].as_f64().unwrap_or_else(|| panic!("{at}: {k}가 수가 아닙니다"));
    let (gm, wm) = (g["months"].as_str().expect("months 글"), w["months"].as_str().expect("months 글"));
    let (g_from, g_to, w_from, w_to) = (num(g, "from"), num(g, "to"), num(w, "from"), num(w, "to"));
    assert!(w_from <= g_from && g_to <= w_to && (w_from < g_from || g_to < w_to), "{at}: Rust 표({g_from} ~ {g_to})가 Node 표({w_from} ~ {w_to}) 안에서 잘린 것이 아닙니다");
    let len_at = |m: &str, k: usize| archive_engine::lay::cal::month_days(m.as_bytes()[k * 2 + 1]); // 28일 이하인 달의 글자까지(리메이크 6단계 걸음 4)
    // note: '표 밖 생략 — 자료 범위 <lo>년 ~ <hi>년 …'으로 **시작**하고(판정 R64 · M5), 그 해 범위가 Node 표가 덮은 범위(자료 해의 1월 1일이 든 달 ~ 마지막 해 다음 해 1월 1일을 넘는 달)와 맞는다.
    let note = g["note"].as_str().unwrap_or_default();
    let first = note.split(" · ").next().unwrap_or_default();
    let years = first.strip_prefix(CLIP_NOTE_HEAD).and_then(|r| r.strip_suffix(CLIP_NOTE_TAIL)).and_then(|r| r.split_once("년 ~ "))
        .unwrap_or_else(|| panic!("{at}: 잘린 표의 note가 '{CLIP_NOTE_HEAD}<lo>년 ~ <hi>{CLIP_NOTE_TAIL}'으로 시작하지 않습니다 — {}", g["note"]));
    let (lo, hi): (f64, f64) = (years.0.parse().unwrap_or_else(|_| panic!("{at}: note의 시작 해가 수가 아닙니다 — {}", g["note"])), years.1.parse().unwrap_or_else(|_| panic!("{at}: note의 끝 해가 수가 아닙니다 — {}", g["note"])));
    let (data_from, data_to) = (archive_engine::lay::cal::jdn_civil(lo, 1.0, 1.0), archive_engine::lay::cal::jdn_civil(if hi == -1.0 { 1.0 } else { hi + 1.0 }, 1.0, 1.0));
    let wn0 = wm.len() / 2;
    assert!(wn0 > 0 && w_from <= data_from && data_from < w_from + len_at(wm, 0) && data_to <= w_to && w_to - len_at(wm, wn0 - 1) < data_to,
        "{at}: note의 자료 범위({lo}년 ~ {hi}년 = 날 번호 {data_from} ~ {data_to})가 Node 표({w_from} ~ {w_to})가 덮은 범위와 맞지 않습니다");
    let lunar = w["lunar"] == true;
    let (mut j, mut year, mut k) = (w_from, num(w, "year0"), 0usize);
    let wn = wm.len() / 2;
    while j < g_from && k < wn {
        j += len_at(wm, k);
        k += 1;
        if k < wn && wm.as_bytes()[k * 2] == b'C' { year = if lunar && year == -1.0 { 1.0 } else { year + 1.0 }; }
    }
    assert!(j == g_from, "{at}: Rust 표의 첫날 {g_from}이 Node 표의 달 경계가 아닙니다");
    assert!(year == num(g, "year0"), "{at}: Rust 표의 year0({})이 Node 표를 따라 센 해({year})와 다릅니다", g["year0"]);
    let gn = gm.len() / 2;
    assert!(num(g, "count") == gn as f64 && k + gn <= wn && wm[k * 2..(k + gn) * 2] == *gm, "{at}: Rust 표의 달 글이 Node 표의 {k}번째 달부터의 글과 다릅니다");
    assert!(g_from + (0..gn).map(|i| len_at(gm, i)).sum::<f64>() == g_to, "{at}: Rust 표의 to({g_to})가 달 글과 맞지 않습니다");
}

/// 정답지 파일이 있는가(큰 JSON을 풀지 않고 — 옮기지 않은 모듈의 검사가 '정답지가 있는지만' 볼 때).
pub fn oracle_exists(f: &Fixture, file: &str) -> bool { results_dir().join(&f.name).join(file).is_file() }

/// 정답지와 같은 시각 · 시간대(540분)의 선택. 범위는 전체. 보조 달력 표는 없다(표가 없을 때의 거절을 보는 검사가 쓴다 — 정답지 자료에는 [`seam_opts`]).
pub fn opts(upto: Option<&str>) -> Opts {
    Opts { now_ms: ORACLE_NOW_MS, tz_min: ORACLE_TZ_MIN, upto: upto.map(str::to_string), scope: Scope::All, calendar: None }
}

/// 검사 자료로 커밋한 **잘린 달력 표**(`tests/fixtures/lay/calendar-slice.json` — `node prototype/scripts/calendar-slice.mjs`가 정답지 자료와 읽기 벡터의
/// 보조 달력 날짜 둘레와, 내보내기 `calendar` 모듈이 자료마다 자르는 범위(자료 해 ± 100년 · 달력 다섯 — 과제 8-틀 고침 1회차)를 떠서 씀 · `calendar-cache.json`과 같은 꼴 · 판정 R18).
/// 과제 17의 '저장소 안 표'와 같은 길(`Opts.calendar`)로 넘긴다.
pub fn calendar_slice() -> std::rc::Rc<Vec<u8>> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("lay").join("calendar-slice.json");
    std::rc::Rc::new(std::fs::read(&path).unwrap_or_else(|e| panic!("{} 을(를) 읽지 못했습니다 — 뽑으세요: node prototype/scripts/calendar-slice.mjs ({e})", path.display())))
}

/// 정답지 자료를 Rust로 돌릴 때의 선택: [`opts`]에 잘린 달력 표([`calendar_slice`])를 싣는다 — 견본 등불 2.0.1의 "음력 125-08-15"처럼
/// 보조 달력 날짜가 든 자료를 정답지(Node — ICU)와 같게 읽는다(표가 없으면 Rust가 '음력 표 없음'으로 거절).
pub fn seam_opts(upto: Option<&str>) -> Opts {
    let mut o = opts(upto);
    o.calendar = Some(calendar_slice());
    o
}

/// 최상위 열쇠 거르개 — 목록에 든 열쇠만 남긴다(빈 목록 = 전부). 최상위가 객체가 아니면 그대로.
pub fn only_keys(v: Value, keys: &[&str]) -> Value {
    if keys.is_empty() { return v; }
    match v {
        Value::Object(map) => Value::Object(map.into_iter().filter(|(k, _)| keys.contains(&k.as_str())).collect()),
        other => other,
    }
}

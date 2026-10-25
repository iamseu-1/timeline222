//! 지금 연표가 계산한 줄 배치(가져오기 JSON 3판)를 새 저장소로 가져온다. 두 갈래가 있다.
//! - 노드 도구(`scripts/export-layout.mjs` → `add-dlc.mjs`)의 길: `import_layout` — 기본팩 · 얹은 DLC의 원본(.htpack)을 모두 받아 그대로 보존한다(옛 꼴 그대로).
//! - 메이커의 배치(.htlayout · 팩 파일 종류 3)를 Node 없이 받는 길: `import_with` · FFI `archive_import`(계약 2-7) — 원본은 함께 받은 것 ·
//!   지금 저장소에서 옮겨 실은 것만 품고(없으면 `meta.pack_info`에 `original:false`), 지금 저장소와 조합을 대조한다(설계 A 5-3 · 5-4).
//! 외부 사용자가 일반 JSON을 설치하는 길이 아니다 — 배치 JSON · .htlayout은 '지금 연표의 줄 배치'이고, DLC 본문은 원본 전용 팩이다.
//! 형식은 `docs/계약-아카이브-3단계.md` 4절. 빠진 열쇠는 기본값으로 읽고, 모르는 열쇠는 무시한다 —
//! 내보내기 쪽이 열을 하나씩 넓히는 동안에도 가져오기가 멈추지 않게.
use crate::builder::{AxisCellIn, Builder, CellIn, EventIn, GroupIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use crate::{htpack_raw, read_htlayout, read_htpack, Result, Store, LAYOUT_NOT_PACK, PACK_MAGIC};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::{fs, time::Instant};

/// 저장소의 자료집 한 줄을 만들 재료 — 배치의 `packs[]` 한 칸과 그 원본(.htpack 바이트 · 없으면 None).
pub struct PackPlan {
    /// DLC의 글자 id(`meta.pack_keys`). 없으면 열쇠를 남기지 않는다.
    pub key: Option<String>,
    pub name: String,
    /// DLC의 판(팩 정보의 `version` 그대로 · 모르면 빈 글).
    pub version: String,
    /// 팩 분류(`map` 지도팩 … · 모르면 빈 글).
    pub category: String,
    pub original: Option<Vec<u8>>,
}

/// 판은 글로 다룬다(팩 정보는 `"1.0.0"` 같은 글 · 옛 파일은 수일 수도 있다). 없으면 빈 글.
pub(crate) fn version_text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}

/// 배치 파일 읽기: 확장자가 `.htlayout`이면 팩 파일 종류 3(머리 · 지문 · 풀기 · 내용 점검), 아니면 가져오기 JSON 3판 그대로.
/// 확장자가 `.htlayout`이 아닌 팩 파일(.htpack · 이름을 바꾼 배치)은 JSON으로 읽지 않고 웹과 같은 글로 거절한다.
pub fn read_plan(layout: &Path) -> Result<Value> {
    if layout.extension().and_then(|s| s.to_str()).is_some_and(|s| s.eq_ignore_ascii_case("htlayout")) {
        return read_htlayout(layout);
    }
    let bytes = fs::read(layout)?;
    if bytes.starts_with(PACK_MAGIC) {
        return Err(LAYOUT_NOT_PACK.into());
    }
    Ok(serde_json::from_slice(&bytes)?)
}

/// 노드 도구의 길(옛 꼴 그대로 — `add-dlc.mjs`가 쓴다). 배치는 JSON이나 .htlayout(확장자로 가른다).
/// [extra]는 기본 DLC 뒤에 얹은 DLC들의 전용 팩(배치 JSON의 `packs[1..]`과 같은 차례 · 같은 id여야 한다) — 원본을 그대로 보존한다.
pub fn import_layout(pack: &Path, layout: &Path, target: &Path, extra: &[&Path]) -> Result<Value> {
    if target.exists() {
        return Err("기존 저장소는 덮어쓰지 않습니다".into());
    }
    let raw = read_htpack(pack)?;
    let bytes = fs::read(pack)?;
    let plan = read_plan(layout)?;
    let mut extras: Vec<(Value, Vec<u8>)> = Vec::new();
    for path in extra {
        extras.push((read_htpack(path)?, fs::read(path)?));
    }
    let packs = strict_packs(raw, bytes, extras, &plan)?;
    build(&plan, packs, target, KEPT_NOTE)
}

/// [`import_layout`]과 같은 짓기를 파일 대신 **배치 JSON 값 + 원본 바이트**로(계획 P4 과제 1b — 검사 · `apply`가 쓰는 얇은 입구).
/// `originals`는 (자료집 글자 id, .htpack 바이트)를 배치의 `packs[]` 차례대로 — 첫째가 기본팩이다. 짝짓기는 `strict_packs`와 같다
/// (같은 수 · 같은 차례 · 같은 id). 글자 id를 적었으면 배치의 그 자리 id와도 맞아야 한다(빈 글이면 보지 않는다).
pub fn import_layout_value(plan: &Value, originals: &[(String, Vec<u8>)], target: &Path) -> Result<Value> {
    import_value_into(plan, originals, target, None, None)
}

/// [`import_layout_value`] · [`build_store`]의 공통 몸 — `now`가 있으면 지은 날 `meta.now`를 그 글로(배치의 `now` 대신), `calendar`가 있으면 달력 표를
/// `blobs`의 `lay::CALENDAR_BLOB`(zlib)에 넣는다.
fn import_value_into(plan: &Value, originals: &[(String, Vec<u8>)], target: &Path, now: Option<&str>, calendar: Option<&[u8]>) -> Result<Value> {
    if target.exists() {
        return Err("기존 저장소는 덮어쓰지 않습니다".into());
    }
    let declared = list(plan, "packs");
    for (i, (key, _)) in originals.iter().enumerate() {
        let want = declared.get(i).and_then(|p| p["id"].as_str()).unwrap_or("");
        if !key.is_empty() && !want.is_empty() && key != want {
            return Err(format!("{}번째 원본({key})이 배치의 자료집({want})과 다릅니다", i + 1).into());
        }
    }
    let ((_, base), rest) = originals.split_first().ok_or("기본팩 원본이 없습니다")?;
    let raw = htpack_raw(base)?;
    let mut extras: Vec<(Value, Vec<u8>)> = Vec::with_capacity(rest.len());
    for (_, bytes) in rest {
        extras.push((htpack_raw(bytes)?, bytes.clone()));
    }
    let packs = strict_packs(raw, base.clone(), extras, plan)?;
    build_with(plan, packs, target, KEPT_NOTE, now, calendar)
}

// ---------------------------------------------------------------- Rust로 짓기(한 벌 P3 과제 17)

/// `archive-tool build`가 저장소에 굳히는 '오늘'의 글 — `--now`가 없으면 지금 시각을 서울 시간대(+09:00 — 앱의 자료 · 사용자가 한국어다)로 적는다.
pub const DEFAULT_TZ_MIN: i32 = 540;

/// ISO 시각 글(`2026-10-15T12:00:00+09:00` · `…Z` · 소수 초 받음) → (1970-01-01T00:00:00Z부터의 밀리초, 시간대 분). 시간대가 없거나 꼴이 틀리면 None.
/// `Z`(UTC)는 시간대를 모르는 글이다 — 그 글로 지은 것(Node 길 `iso_now`)은 그 PC의 지역 시각으로 셈했으므로 [`DEFAULT_TZ_MIN`]으로 본다. 이 풀이는
/// P4가 옛 저장소의 `meta.now`를 읽을 때만이다 — `archive-tool build --now`는 `Z`를 받지 않는다(시간대를 꼭 적게 — [`build_files`]).
pub fn iso_time(text: &str) -> Option<(f64, i32)> {
    let t = text.trim();
    let b = t.as_bytes();
    let num = |from: usize, len: usize| -> Option<i64> {
        let s = t.get(from..from + len)?;
        s.bytes().all(|c| c.is_ascii_digit()).then(|| s.parse().ok()).flatten()
    };
    if b.len() < 20 || b[4] != b'-' || b[7] != b'-' || !matches!(b[10], b'T' | b't' | b' ') || b[13] != b':' || b[16] != b':' { return None; }
    let (y, mo, d, h, mi, s) = (num(0, 4)?, num(5, 2)?, num(8, 2)?, num(11, 2)?, num(14, 2)?, num(17, 2)?);
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 23 || mi > 59 || s > 60 { return None; }
    let mut at = 19;
    let mut frac = 0.0;
    if b.get(at) == Some(&b'.') {
        let start = at + 1;
        at = start;
        while b.get(at).is_some_and(u8::is_ascii_digit) { at += 1; }
        if at == start { return None; }
        frac = format!("0.{}", &t[start..at]).parse().ok()?;
    }
    let tz = match b.get(at)? {
        b'Z' | b'z' if at + 1 == b.len() => DEFAULT_TZ_MIN,
        sign @ (b'+' | b'-') if at + 6 == b.len() && b[at + 3] == b':' => {
            let m = num(at + 1, 2)? * 60 + num(at + 4, 2)?;
            (if *sign == b'-' { -m } else { m }) as i32
        }
        _ => return None,
    };
    let offset = if matches!(b[at], b'Z' | b'z') { 0 } else { i64::from(tz) };
    let days = crate::span::days_from_civil(y, mo, d);
    let secs = days * 86_400 + h * 3600 + mi * 60 + s - offset * 60;
    Some(((secs as f64 + frac) * 1000.0, tz))
}

/// 밀리초 · 시간대 분 → ISO 글(`2026-10-15T12:00:00+09:00` — 초까지). [`iso_time`]이 같은 값으로 읽는다.
pub fn iso_at(ms: f64, tz_min: i32) -> String {
    let secs = (ms / 1000.0).floor() as i64 + i64::from(tz_min) * 60;
    let (year, month, day) = crate::span::civil_from_days(secs.div_euclid(86_400));
    let rest = secs.rem_euclid(86_400);
    let (sign, off) = if tz_min < 0 { ('-', -tz_min) } else { ('+', tz_min) };
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}{sign}{:02}:{:02}", rest / 3600, rest % 3600 / 60, rest % 60, off / 60, off % 60)
}

/// 지금 시각(밀리초).
pub fn now_ms() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0.0, |d| d.as_millis() as f64)
}

/// 본문(JSON 글 바이트)을 DLC 전용 팩(.htpack — 팩 파일 규격 2 · 종류 1)으로 싼다. 본문 바이트는 그대로 싣는다(열쇠 차례를 바꾸지 않게 — 다시 적지 않는다).
/// `archive-tool build`가 `.json`으로 받은 DLC의 원본을 저장소에 넣을 때 쓴다(`crate::unseal`이 그대로 푼다).
pub fn seal_dlc(plain: &[u8]) -> Vec<u8> {
    use std::io::Write;
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(plain).expect("메모리에 쓰기");
    let body = encoder.finish().expect("메모리에 쓰기");
    let mut head = PACK_MAGIC.to_vec();
    head.extend_from_slice(&[2, crate::KIND_DLC, 1, 0]);
    head.extend_from_slice(&(plain.len() as u32).to_le_bytes());
    head.extend_from_slice(&(body.len() as u32).to_le_bytes());
    let mut hash = Sha256::new();
    hash.update(&head);
    hash.update(&body);
    [head, hash.finalize().to_vec(), body].concat()
}

/// 짓기에 줄 DLC 하나: 배치가 읽는 바이트(`lay::PackIn` — .htpack 형식 1 ~ 4 · JSON)와 저장소에 넣을 원본(.htpack — JSON이면 [`seal_dlc`]로 싼 것) · 글자 id.
pub struct BuildPack {
    pub input: crate::lay::PackIn,
    pub key: String,
    pub original: Vec<u8>,
}

/// 파일 하나를 [`BuildPack`]으로 — 확장자 `.htpack`이면 그대로(머리 · 지문 확인 — `read_htpack`), 아니면 JSON 글(본문의 `format`이 DLC여야 함).
pub fn build_pack(path: &Path) -> Result<BuildPack> {
    let bytes = fs::read(path).map_err(|e| format!("DLC 파일을 읽지 못했습니다({}): {e}", path.display()))?;
    let is_pack = path.extension().and_then(|s| s.to_str()).is_some_and(|s| s.eq_ignore_ascii_case("htpack"));
    let raw: Value = if is_pack { read_htpack(path)? } else { serde_json::from_slice(&bytes)? };
    if raw["format"] != "history-timeline-dlc" {
        return Err(format!("DLC 본문이 아닙니다: {}", path.display()).into());
    }
    let key = raw["id"].as_str().filter(|s| !s.is_empty()).ok_or_else(|| format!("DLC에 id가 없습니다: {}", path.display()))?.to_owned();
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let original = if is_pack { bytes.clone() } else { seal_dlc(&bytes) };
    Ok(BuildPack { input: crate::lay::PackIn { name, bytes }, key, original })
}

/// 짓기 ①(과제 17 — 배치): 팩들(첫째가 기본 DLC, 나머지는 켠 차례)을 Rust로 배치한다 — `lay::export(Scope::All)`. 옮기지 않은 내보내기 모듈이 있으면
/// 그 모듈의 이름을 담아 거절한다(`lay::export::unported` — 조용히 다른 답을 내지 않음). 달력 표(`calendar-cache.json` 꼴의 글)는 보조 달력 날짜를 읽을 때 쓴다.
pub fn build_layout(packs: &[crate::lay::PackIn], now_ms: f64, tz_min: i32, calendar: Option<std::rc::Rc<Vec<u8>>>) -> Result<Value> {
    let opts = crate::lay::Opts { now_ms, tz_min, upto: None, scope: crate::lay::Scope::All, calendar };
    // 짓기([`build_files_with`])와 같은 길(16b 검토 ③ Minor 4 — 검사가 부르는 이것과 제품 길이 갈리지 않게) · 기록은 버린다.
    Ok(crate::lay::export::export_with_notes(packs, &opts)?.0)
}

/// 짓기 ②(과제 17 — 저장소): 배치 값(Rust ①의 답 · 또는 Node 내보내기 — 같은 꼴)으로 새 저장소를 짓는다. [`import_layout_value`]와 같은 짓기에 둘을 더한다:
/// 지은 날 `meta.now` = `now` 글 그대로(P4가 '오늘'로 읽는다) · 달력 표를 `blobs`의 `lay::CALENDAR_BLOB`(zlib)에.
/// 표는 **모든 저장소에 · 전체를 통째로**(판정 R36 — `warm-calendar.mjs` 기본 −3500 ~ 2500년 · 달력 다섯: 글 약 740KB · zlib 뒤 약 27KB). 휴대폰에서 DLC를
/// 넣고 뺄 때(`add_pack` · `remove_pack`) 엔진이 이 표로 보조 달력 날짜를 읽으므로 자료가 쓰는 해만큼 잘라 넣으면 뒤에 넣는 DLC가 '표 범위 밖'으로 거절될 수
/// 있어 자르지 않고 받은 바이트 그대로 싼다.
/// 트랙 지문을 낼 수 없는 배치(트랙 열쇠가 겹침 등)는 짓지 않는다(고침 2회차 M-6) — 가져오기 길(`fill_into`)은 지문 없이 짓고 첫 `apply`가 거절하지만,
/// 시드를 짓는 이 길에서 그러면 휴대폰의 첫 넣기 · 빼기에서야 알게 된다.
///
/// **`plan`은 그 원본들의 Rust 통째 배치만**(`lay::export` — 제품에서는 [`build_files_with`]가 유일한 부르는 곳): 이 짓기는 지금 규칙 판(`meta.rules`)을
/// 적어 'Rust가 이 원본으로 셈한 배치와 같다'고 약속한다(판정 R69-2 · 16b 고침 2회차 작은 것 6). 바깥 배치(메이커 · Node 내보내기)는 [`import_layout_value`]
/// 길로(규칙 판 없음). 검사의 Node 틈 저장소(`tests/add_pack.rs`의 `full`)가 이 길을 쓰는 것은 정답지 견줌(Node 배치 = Rust 배치)에 기댄 검사 전용이다.
pub fn build_store(plan: &Value, originals: &[(String, Vec<u8>)], target: &Path, now: &str, calendar: &[u8]) -> Result<Value> {
    crate::patch::prints(plan).map_err(|e| format!("배치의 트랙 지문을 낼 수 없어 짓지 않습니다 — {e}"))?;
    import_value_into(plan, originals, target, Some(now), Some(calendar))
}

/// `archive-tool build <새 저장소> <기본 팩> [<얹는 팩>…] --calendar=<calendar-cache.json> [--now=<ISO 시각>]`의 몸 — ① 배치 → ② 저장소.
/// 달력 표는 꼭 준다(판정 R36 — 없으면 ① 앞에서 거절). `now`가 없으면 지금 시각(서울 시간대로 적음) · 있으면 시간대를 적은 글만(`Z`는 거절 — 지은 날의
/// 지역 날짜가 시간대에 달린다). 답: ②의 수 세기 + `ms_layout`(①) · `ms_store`(②) · `now`.
pub fn build_files(target: &Path, files: &[PathBuf], now: Option<&str>, calendar: Option<&Path>) -> Result<Value> {
    build_files_with(target, files, now, calendar, false)
}

/// 달력 표가 덮어야 하는 해(`warm-calendar.mjs`의 기본 — 판정 R36 · 계획 정한 것 #7). `build`는 표의 `years`가 이보다 좁으면 거절한다.
/// DLC의 보조 달력 날짜는 이 범위 안이어야 한다(내보내기 `calendar` 모듈이 자료 해 ± 100년으로 잘라 쓰는 것은 표 안에서의 일 — 판정 R72-1).
pub const CALENDAR_YEARS: (i64, i64) = (-3500, 2500);

/// [`build_files`] — `narrow_ok`면 기본보다 좁은 달력 표(검사의 잘린 표)도 받는다(`archive-tool build --calendar-narrow` · 시험용).
pub fn build_files_with(target: &Path, files: &[PathBuf], now: Option<&str>, calendar: Option<&Path>, narrow_ok: bool) -> Result<Value> {
    if target.exists() {
        return Err("기존 저장소는 덮어쓰지 않습니다".into());
    }
    if files.is_empty() {
        return Err("지을 DLC가 없습니다".into());
    }
    let Some(calendar) = calendar else {
        return Err("달력 표가 없습니다 — 저장소마다 달력 표를 넣습니다(휴대폰에서 DLC를 넣고 뺄 때 씀). \
            `node prototype/scripts/warm-calendar.mjs`로 뜬 calendar-cache.json을 --calendar=<파일>로 주세요".into());
    };
    let now = match now {
        Some(text) if text.trim_end().ends_with(['Z', 'z']) => {
            return Err(format!("--now에 시간대를 적어 주세요(예: 2026-10-15T12:00:00+09:00) — Z(UTC)는 받지 않습니다: {text}").into());
        }
        Some(text) => text.to_owned(),
        None => iso_at(now_ms(), DEFAULT_TZ_MIN),
    };
    let (ms, tz) = iso_time(&now).ok_or_else(|| format!("--now가 ISO 시각이 아닙니다(예: 2026-10-15T12:00:00+09:00): {now}"))?;
    let table = std::rc::Rc::new(fs::read(calendar).map_err(|e| format!("달력 표를 읽지 못했습니다({}): {e}", calendar.display()))?);
    if !narrow_ok {
        let years: Value = serde_json::from_slice::<Value>(&table).map(|v| v["years"].clone())
            .map_err(|e| format!("달력 표가 JSON이 아닙니다({}): {e}", calendar.display()))?;
        let (lo, hi) = (years[0].as_i64(), years[1].as_i64());
        if !matches!((lo, hi), (Some(lo), Some(hi)) if lo <= CALENDAR_YEARS.0 && hi >= CALENDAR_YEARS.1) {
            return Err(format!("달력 표가 기본 범위({} ~ {}년)보다 좁습니다(표의 years: {years}) — `warm-calendar.mjs` 기본으로 뜬 전체 표를 주세요(시험용 잘린 표는 --calendar-narrow)",
                CALENDAR_YEARS.0, CALENDAR_YEARS.1).into());
        }
    }
    let packs: Vec<BuildPack> = files.iter().map(|p| build_pack(p)).collect::<Result<_>>()?;
    let inputs: Vec<crate::lay::PackIn> = packs.iter().map(|p| p.input.clone()).collect();
    let started = Instant::now();
    // ①과 같은 배치 + 모듈의 기록(판정 R61 M3 — 판의 `뺀판` · `어긋남` 따위를 요약에 싣는다).
    let opts = crate::lay::Opts { now_ms: ms, tz_min: tz, upto: None, scope: crate::lay::Scope::All, calendar: Some(table.clone()) };
    let (plan, notes) = crate::lay::export::export_with_notes(&inputs, &opts)?;
    let ms_layout = started.elapsed().as_secs_f64() * 1000.0;
    let originals: Vec<(String, Vec<u8>)> = packs.into_iter().map(|p| (p.key, p.original)).collect();
    let started = Instant::now();
    let mut counts = build_store(&plan, &originals, target, &now, &table)?;
    counts["ms_layout"] = json!(ms_layout);
    counts["ms_store"] = json!(started.elapsed().as_secs_f64() * 1000.0);
    counts["now"] = json!(now);
    counts["notes"] = notes;
    Ok(counts)
}

/// 옛 꼴의 원본 짝짓기: 배치의 `packs[]`와 받은 전용 팩이 같은 수 · 같은 차례 · 같은 id여야 한다(어긋나면 예전 글 그대로 거절).
fn strict_packs(raw: Value, bytes: Vec<u8>, extras: Vec<(Value, Vec<u8>)>, plan: &Value) -> Result<Vec<PackPlan>> {
    // DLC 여러 벌(계약: plan["packs"] = [{id, name}] · 첫째가 기본). 옛 JSON(packs 없음)은 한 벌이다.
    let declared = list(plan, "packs");
    if !declared.is_empty() && declared.len() != extras.len() + 1 {
        return Err(format!("배치에 DLC가 {}벌인데 전용 팩은 {}개입니다", declared.len(), extras.len() + 1).into());
    }
    if declared.is_empty() && !extras.is_empty() {
        return Err(format!("배치에 DLC 목록(packs)이 없는데 얹은 전용 팩이 {}개 있습니다", extras.len()).into());
    }
    let first = declared.first();
    // 판 · 분류는 배치의 것이 먼저, 없으면 원본의 것(노드 도구는 바로 이 원본들로 배치를 셈했다).
    let or_raw = |want: Option<&Value>, key: &str, raw: &Value| -> String {
        let mine = want.map(|w| version_text(&w[key])).unwrap_or_default();
        if mine.is_empty() { version_text(&raw[key]) } else { mine }
    };
    let mut packs = vec![PackPlan {
        key: first.and_then(|p| p["id"].as_str()).or(raw["id"].as_str()).map(str::to_owned),
        name: first.and_then(|p| p["name"].as_str()).or(raw["name"].as_str()).or(plan["name"].as_str()).unwrap_or("이름 없는 자료집").to_owned(),
        version: or_raw(first, "version", &raw),
        category: or_raw(first, "category", &raw),
        original: Some(bytes),
    }];
    for (i, (extra_raw, extra_bytes)) in extras.into_iter().enumerate() {
        let want = &declared[i + 1];
        let id = extra_raw["id"].as_str().unwrap_or("");
        if want["id"].as_str().unwrap_or("") != id {
            return Err(format!("{}번째 전용 팩의 id({id})가 배치의 것({})과 다릅니다", i + 2, want["id"]).into());
        }
        packs.push(PackPlan {
            key: Some(id.to_owned()),
            name: want["name"].as_str().or(extra_raw["name"].as_str()).unwrap_or(id).to_owned(),
            version: or_raw(Some(want), "version", &extra_raw),
            category: or_raw(Some(want), "category", &extra_raw),
            original: Some(extra_bytes),
        });
    }
    Ok(packs)
}

/// 원본을 모두 품은 저장소의 메타 `legacy` 글(예전 그대로).
pub(crate) const KEPT_NOTE: &str = "원본 전용 팩 보존 · 지금 연표의 줄 배치 그대로 가져옴";
/// 원본 없는 DLC가 있는 저장소의 메타 `legacy` 글.
pub(crate) const PARTIAL_NOTE: &str = "지금 연표의 줄 배치 그대로 가져옴 · 원본 없는 DLC가 있음(meta.pack_info의 original)";

/// 짓다가 실패하면 반쯤 지은 저장소를 정식 자료처럼 남기지 않는다.
fn discard(target: &Path) {
    let _ = fs::remove_file(target);
    let _ = fs::remove_file(target.with_extension("db-journal"));
}

fn build(plan: &Value, packs: Vec<PackPlan>, target: &Path, note: &str) -> Result<Value> {
    build_with(plan, packs, target, note, None, None)
}

/// [`build`]에 지은 날(`now` — 있으면 배치의 `now` 대신 `meta.now`로)과 달력 표(`calendar-cache.json` 꼴의 글 — zlib으로 싸서 `blobs`의
/// `lay::CALENDAR_BLOB`에 · 자료집 0)를 더한 것(과제 17).
fn build_with(plan: &Value, packs: Vec<PackPlan>, target: &Path, note: &str, now: Option<&str>, calendar: Option<&[u8]>) -> Result<Value> {
    let result = Builder::create(target).and_then(|mut b| {
        b.add_meta("legacy", note.to_owned());
        let counts = fill_into(&mut b, plan, packs, FillHow::All)?;
        if let Some(now) = now {
            b.add_meta("now", now.to_owned()); // `fill_into`가 배치의 `now`로 적은 것을 바꾼다
        }
        if let Some(table) = calendar {
            use std::io::Write;
            let mut zip = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
            zip.write_all(table)?;
            b.blob(crate::lay::CALENDAR_BLOB, 0, "application/zlib", &zip.finish()?)?;
            // 짓기(`build_store` — 달력 표를 주는 길은 이것뿐): 그 원본들의 통째 배치로 지었다 — 지금 규칙 판을 적는다(판정 R59 I-1 · R69-2 — `packs::held`가 견줌).
            b.add_meta("rules", crate::patch::rules_mark());
        }
        b.finalize(&[])?;
        Ok(counts)
    });
    if result.is_err() {
        discard(target);
    }
    result
}

/// Node 없는 가져오기의 재료(계약 2-7 `archive_import` · `archive-tool import-layout … --from-store` · `check-layout`).
pub struct ImportPlan<'a> {
    /// 배치: `.htlayout`(팩 파일 종류 3) 또는 가져오기 JSON 3판 — 확장자로 가른다.
    pub layout: &'a Path,
    /// 새 저장소(있으면 거절 — 덮어쓰지 않는다). `check_only`면 쓰지 않는다.
    pub out: Option<&'a Path>,
    /// 기본팩 원본(.htpack). 없으면 지금 저장소에서 옮겨 싣거나 원본 없이.
    pub base: Option<&'a Path>,
    /// 다른 DLC의 원본(.htpack) — id로 배치의 `packs[]`와 짝짓는다(판을 양쪽이 알면 같아야 한다).
    pub originals: Vec<&'a Path>,
    /// 지금 저장소. 주면 조합을 대조하고(설계 A 5-3) 그 저장소의 원본을 옮겨 싣는다(5-4 라).
    pub from_store: Option<&'a Path>,
    /// 짓지 않고 읽기 · 내용 점검 · 조합 대조만.
    pub check_only: bool,
}

/// FFI `archive_import`의 요청 JSON → `import_with`.
pub fn import_request(q: &Value) -> Result<Value> {
    let path = |key: &str| -> Result<Option<PathBuf>> {
        match &q[key] {
            Value::Null => Ok(None),
            Value::String(s) if s.is_empty() => Ok(None),
            Value::String(s) => Ok(Some(PathBuf::from(s))),
            _ => Err(format!("{key}는 경로 글이어야 합니다").into()),
        }
    };
    let layout = path("layout")?.ok_or("배치 파일 경로(layout)가 없습니다")?;
    let (out, base, from_store) = (path("out")?, path("base")?, path("from_store")?);
    let mut originals: Vec<PathBuf> = Vec::new();
    match &q["originals"] {
        Value::Null => {}
        Value::Array(list) => {
            for v in list {
                match v.as_str() {
                    Some(s) if !s.is_empty() => originals.push(PathBuf::from(s)),
                    _ => return Err("원본 목록(originals)은 경로 글의 목록이어야 합니다".into()),
                }
            }
        }
        _ => return Err("원본 목록(originals)은 경로 글의 목록이어야 합니다".into()),
    }
    import_with(&ImportPlan {
        layout: &layout, out: out.as_deref(), base: base.as_deref(), originals: originals.iter().map(PathBuf::as_path).collect(),
        from_store: from_store.as_deref(), check_only: q["check_only"].as_bool().unwrap_or(false),
    })
}

/// 배치가 말하는 조합(C) — `packs[]` 차례 그대로. 옛 JSON(packs 없음)은 한 벌(기본팩 원본이 있으면 그 id · 이름).
pub(crate) fn wanted_packs(plan: &Value, base: Option<&Value>) -> Vec<PackPlan> {
    let declared = list(plan, "packs");
    if declared.is_empty() {
        return vec![PackPlan {
            key: base.and_then(|r| r["id"].as_str()).map(str::to_owned),
            name: base.and_then(|r| r["name"].as_str()).or(plan["name"].as_str()).unwrap_or("이름 없는 자료집").to_owned(),
            version: base.map(|r| version_text(&r["version"])).unwrap_or_default(),
            category: base.map(|r| version_text(&r["category"])).unwrap_or_default(),
            original: None,
        }];
    }
    declared.iter().enumerate().map(|(i, d)| PackPlan {
        key: d["id"].as_str().or(if i == 0 { base.and_then(|r| r["id"].as_str()) } else { None }).map(str::to_owned),
        name: d["name"].as_str().or(d["id"].as_str()).or(if i == 0 { plan["name"].as_str() } else { None }).unwrap_or("이름 없는 자료집").to_owned(),
        version: version_text(&d["version"]),
        category: version_text(&d["category"]),
        original: None,
    }).collect()
}

/// 받은 원본의 판이 배치의 판과 맞는가(둘 다 알 때만 본다).
fn same_version(want: &PackPlan, raw: &Value) -> Result<()> {
    let have = version_text(&raw["version"]);
    if !want.version.is_empty() && !have.is_empty() && want.version != have {
        return Err(format!("원본 «{}»의 판이 배치와 다릅니다(원본 v{have} · 배치 v{})", want.name, want.version).into());
    }
    Ok(())
}

/// 지금 저장소에 든 DLC 하나(S의 한 칸).
struct Held {
    number: i64,
    key: String,
    name: String,
    /// `meta.pack_info`의 판 · 분류(없으면 빈 글 — 판은 그때 원본 BLOB에서 읽어 본다).
    version: String,
    category: String,
    has_original: bool,
}

/// 지금 저장소의 조합(S) — `meta.pack_keys` + `meta.pack_info` + `packs`.
struct Combo {
    store: Store,
    packs: Vec<Held>,
}

impl Combo {
    fn read(path: &Path) -> Result<Self> {
        let store = Store::open(path).map_err(|e| format!("지금 저장소를 열지 못했습니다: {e}"))?;
        let meta = |key: &str| -> Value {
            store.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0))
                .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_else(|| Value::Object(Map::new()))
        };
        let (keys, info) = (meta("pack_keys"), meta("pack_info"));
        let mut packs = Vec::new();
        {
            let mut stmt = store.db.prepare("SELECT id,name,original IS NOT NULL FROM packs ORDER BY id")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, bool>(2)?)))?;
            for row in rows {
                let (number, name, has_original) = row?;
                let n = number.to_string();
                packs.push(Held { number, key: keys[&n].as_str().unwrap_or("").to_owned(), name, version: version_text(&info[&n]["version"]),
                    category: version_text(&info[&n]["category"]), has_original });
            }
        }
        Ok(Self { store, packs })
    }

    /// 그 DLC의 판 · 분류 — `pack_info`가 없는 옛 저장소는 품은 원본(.htpack)의 팩 정보에서 읽는다. 둘 다 없으면 빈 글.
    fn info(&self, held: &Held) -> (String, String) {
        if !held.version.is_empty() || !held.has_original {
            return (held.version.clone(), held.category.clone());
        }
        let raw = self.original(held.number).ok().flatten().and_then(|bytes| htpack_raw(&bytes).ok()).unwrap_or(Value::Null);
        let category = if held.category.is_empty() { version_text(&raw["category"]) } else { held.category.clone() };
        (version_text(&raw["version"]), category)
    }

    fn original(&self, number: i64) -> Result<Option<Vec<u8>>> {
        Ok(self.store.db.query_row("SELECT original FROM packs WHERE id=?1", [number], |r| r.get::<_, Option<Vec<u8>>>(0))?)
    }
}

/// Node 없는 가져오기(계약 2-7). 차례:
/// 1. 배치를 읽는다(.htlayout은 머리 · 지문 · 풀기 · 내용 점검 — 글은 `js/packfile.js` 그대로).
/// 2. 받은 원본(기본팩 · DLC)을 id로 짝짓는다(판을 양쪽이 알면 같아야 한다).
/// 3. 지금 저장소를 주면 조합을 대조하고(설계 A 5-3의 다섯 규칙) 그 저장소의 원본을 옮겨 싣는다(5-4 라).
/// 4. 짓고(`check_only`면 여기서 멈춤), 표본 타일 120장으로 누락 · 중복을 본다 — 있으면 지은 파일을 지우고 실패한다.
pub fn import_with(p: &ImportPlan) -> Result<Value> {
    let started = Instant::now();
    let target = if p.check_only {
        None
    } else {
        let out = p.out.ok_or("새 저장소 경로(out)가 없습니다")?;
        if out.exists() {
            return Err("기존 저장소는 덮어쓰지 않습니다".into());
        }
        Some(out)
    };
    let plan = read_plan(p.layout)?;
    let base = match p.base {
        Some(path) => Some((read_htpack(path)?, fs::read(path)?)),
        None => None,
    };
    let mut given: Vec<(Value, Vec<u8>)> = Vec::new();
    for path in &p.originals {
        given.push((read_htpack(path)?, fs::read(path)?));
    }
    let mut wants = wanted_packs(&plan, base.as_ref().map(|b| &b.0));
    let mut warnings: Vec<String> = Vec::new();
    // 품을 원본의 판 · 분류. 배치가 판 · 분류를 말하지 않으면(A1-a 전의 메이커) 대조가 끝난 뒤 이것으로 `pack_info`를 채운다 —
    // 노드 도구의 길(`strict_packs`)이 원본의 팩 정보로 채우는 것과 같게.
    let mut spare: Vec<Option<(String, String)>> = vec![None; wants.len()];
    // (가′) 함께 받은 원본.
    if let Some((raw, bytes)) = base {
        let id = raw["id"].as_str().unwrap_or("");
        if let Some(key) = wants[0].key.as_deref() {
            if key != id {
                return Err(format!("기본팩 원본의 id({id})가 배치의 기본팩({key})과 다릅니다").into());
            }
        }
        same_version(&wants[0], &raw)?;
        wants[0].original = Some(bytes);
        spare[0] = Some((version_text(&raw["version"]), version_text(&raw["category"])));
    }
    for (raw, bytes) in given {
        let id = raw["id"].as_str().unwrap_or("");
        let at = wants.iter().position(|w| !id.is_empty() && w.key.as_deref() == Some(id))
            .ok_or_else(|| format!("원본 «{}»({id})이 이 배치에 없습니다", raw["name"].as_str().unwrap_or(id)))?;
        if wants[at].original.is_some() {
            return Err(format!("«{}»의 원본을 둘 받았습니다", wants[at].name).into());
        }
        same_version(&wants[at], &raw)?;
        wants[at].original = Some(bytes);
        spare[at] = Some((version_text(&raw["version"]), version_text(&raw["category"])));
    }
    // 조합 대조(설계 A 5-3) — C = 배치의 packs[] · S = 지금 저장소. 결과 저장소의 조합은 C다(통째로 다시 짓는다).
    let mut added: Option<Vec<bool>> = None;
    if let Some(path) = p.from_store {
        let held = Combo::read(path)?;
        // 저장소의 DLC id · 배치의 기본팩 id · 1. 기본팩이 같다 · 2. 지금 얹은 DLC가 배치에 모두 있다(새로 지으면 빠진 DLC가 사라진다) —
        // `apply`와 같은 몸(`patch::check_packs` · 모두 덮음 · 빼는 것 없음). 기본팩 id는 함께 받은 원본의 것으로 채운 목록으로 본다.
        {
            let named: Vec<(Option<&str>, &str)> = wants.iter().map(|w| (w.key.as_deref(), w.name.as_str())).collect();
            crate::patch::check_packs(&held.store.db, &named, &[], &crate::patch::Covers::All)?;
        }
        let mut fresh = Vec::with_capacity(wants.len());
        for (w, spare) in wants.iter_mut().zip(spare.iter_mut()) {
            let Some(h) = held.packs.iter().find(|h| w.key.as_deref() == Some(h.key.as_str())) else {
                // 5. 배치에만 있는 DLC — 새로 더해진다.
                fresh.push(true);
                continue;
            };
            fresh.push(false);
            // 3 · 4. 판을 양쪽이 알면 같아야 하고, 모르면 id로만 대조하고 알린다.
            let have = if w.version.is_empty() { String::new() } else { held.info(h).0 };
            if w.version.is_empty() || have.is_empty() {
                warnings.push(format!("«{}»의 판을 확인할 수 없습니다 — id로만 대조했습니다", w.name));
            } else if have != w.version {
                return Err(format!("«{}»의 판이 다릅니다(저장소 v{have} · 배치 v{})", w.name, w.version).into());
            }
            // (라) 함께 받은 원본이 없으면 지금 저장소의 원본을 그대로 옮겨 싣는다.
            if w.original.is_none() && h.has_original {
                w.original = held.original(h.number)?;
                *spare = Some(held.info(h));
            }
        }
        added = Some(fresh);
    }
    for (w, spare) in wants.iter_mut().zip(spare) {
        if let Some((version, category)) = spare {
            if w.version.is_empty() {
                w.version = version;
            }
            if w.category.is_empty() {
                w.category = category;
            }
        }
    }
    for w in &wants {
        if w.original.is_none() {
            warnings.push(format!("«{}»: 원본 없음 — 그 DLC의 .htpack을 함께 넣으면 저장소에 품습니다", w.name));
        }
    }
    let packs_answer: Vec<Value> = wants.iter().enumerate().map(|(i, w)| {
        let mut one = json!({"id":w.key.as_deref().unwrap_or(""),"name":w.name,"version":w.version,"category":w.category,"original":i64::from(w.original.is_some())});
        if let Some(fresh) = &added {
            one["added"] = json!(i64::from(fresh[i]));
        }
        one
    }).collect();
    let Some(target) = target else {
        return Ok(json!({"check_only":true,"packs":packs_answer,"events":list(&plan, "events").len(),"entities":list(&plan, "entities").len(),
            "warnings":warnings,"ms":started.elapsed().as_secs_f64()*1000.0}));
    };
    let note = if wants.iter().all(|w| w.original.is_some()) { KEPT_NOTE } else { PARTIAL_NOTE };
    let counts = build(&plan, wants, target, note)?;
    // 지은 뒤 검사(`add-dlc.mjs`의 `verify-tiles 120`과 같다). 누락 · 중복이 있으면 지은 파일을 지우고 실패한다.
    let check = match crate::verify::verify_tiles(target, 120) {
        Ok(check) => check,
        Err(e) => {
            discard(target);
            return Err(format!("지은 저장소를 검사하지 못했습니다: {e}").into());
        }
    };
    if !check.ok() {
        discard(target);
        return Err(format!("지은 저장소의 타일 검사에서 누락 {} · 중복 {}이 나와 지은 파일을 지웠습니다({})", check.missing, check.dup, check.first.unwrap_or_default()).into());
    }
    Ok(json!({"packs":packs_answer,"events":counts["events"],"entities":counts["entities"],"ms":started.elapsed().as_secs_f64()*1000.0,
        "verify":{"missing":check.missing,"dup":check.dup,"tiles":check.tiles},"warnings":warnings,"counts":counts,"bytes":fs::metadata(target)?.len()}))
}

/// 저장소가 품은 DLC 원본(.htpack)을 파일로 꺼낸다(`archive-tool pack-out`) — 앱이 저장소 옆 `DLC/` 폴더의 사본을 채울 때(판 올림 뒤 다시 들이기가
/// 믿는 사본 · 계약 2-7 '앱의 길' · 판정 R60 I-2)와 시드 잇기가 받지 않은 DLC의 원본을 둘 때(판정 R59) · 정답지 도구(`add-dlc.mjs`)가 쓴다.
pub fn pack_out(store: &Path, key: &str, out: &Path) -> Result<Value> {
    if out.extension().and_then(|s| s.to_str()).map(|s| s.eq_ignore_ascii_case("htpack")) != Some(true) {
        return Err("꺼낼 파일의 확장자는 .htpack이어야 합니다".into());
    }
    if out.exists() {
        return Err("기존 파일은 덮어쓰지 않습니다".into());
    }
    let held = Combo::read(store)?;
    let h = held.packs.iter().find(|h| !key.is_empty() && h.key == key).ok_or_else(|| format!("저장소에 DLC «{key}»가 없습니다"))?;
    let bytes = held.original(h.number)?.ok_or_else(|| format!("저장소에 «{}»의 원본이 없습니다(원본 없이 넣은 DLC)", h.name))?;
    // 꺼내기 전에 온전한 전용 팩인지 본다(지문 · 풀기).
    htpack_raw(&bytes)?;
    fs::write(out, &bytes)?;
    Ok(json!({"id":key,"name":h.name,"bytes":bytes.len(),"sha256":format!("{:x}", Sha256::digest(&bytes))}))
}

/// 그 값이 들어갈 자료집의 배치 `packs[]` 순번(`count`개 — 적어도 하나): `pack` 순번(있는 자리면) → uid의 앞머리(`<DLC id>/…` — `head`가 그 id의 순번을 준다) →
/// 첫 자료집(0 — 기본 DLC). 짓기(`fill_into`의 `pack_at`) · 지문(`patch`의 `Packs::of`) · 덧붙이기(`patch`의 `PackIds::of`)가 함께 쓴다
/// (과제 A+ 넘김 "같은 규칙 두 곳" — 셋이 같은 규칙을 따로 적었다).
pub(crate) fn pack_slot(v: &Value, uid: &str, count: usize, head: impl Fn(&str) -> Option<usize>) -> usize {
    if let Some(n) = v["pack"].as_u64().map(|n| n as usize).filter(|n| *n < count) {
        return n;
    }
    uid.split('/').next().and_then(head).unwrap_or(0)
}

/// 빠진 열쇠는 0. 참/거짓도 0/1로 읽는다.
pub(crate) fn int(v: &Value, key: &str) -> i64 {
    let at = &v[key];
    at.as_i64().or_else(|| at.as_f64().map(|f| f as i64)).or_else(|| at.as_bool().map(i64::from)).unwrap_or(0)
}

/// 빠진 열쇠는 주어진 값으로(스키마의 기본값이 0이 아닌 열).
pub(crate) fn int_or(v: &Value, key: &str, fallback: i64) -> i64 {
    if v[key].is_null() { fallback } else { int(v, key) }
}

/// 빠진 열쇠는 빈 글자.
pub(crate) fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    v[key].as_str().unwrap_or("")
}

/// 빠진 열쇠는 빈 목록.
pub(crate) fn list<'a>(v: &'a Value, key: &str) -> &'a [Value] {
    v[key].as_array().map(Vec::as_slice).unwrap_or(&[])
}

/// 옛 열쇠의 목록 뒤에 **겉 열쇠 `boards`**(집합 보기 — 10건 6 · 감독 선택 D4)의 같은 이름 목록을 잇는다.
/// 내보내기가 판마다 미리 셈한 배치(판 트랙 · 변형 kind 3 · 그 변형에서만 있는 칸 · 그릴 것 · 줄 이름 · 판 기록)를 옛 열쇠와 따로 싣는다 —
/// 판이 있어도 옛 열쇠는 1바이트도 달라지지 않고, 옛 엔진은 모르는 열쇠라 건너뛴다. 판 트랙은 옛 트랙 **뒤에** 붙어 옛 줄 번호가 그대로다.
/// `boards`가 없으면 옛 목록 그대로다.
pub(crate) fn with_boards<'a>(plan: &'a Value, key: &str) -> Vec<&'a Value> {
    list(plan, key).iter().chain(list(&plan["boards"], key).iter()).collect()
}

/// 그 값에 달린 `variant`(변형의 열쇠) → 변형 번호. 빠져 있으면 0(기본). 이번에 넣은 변형(`known`)이 먼저, 없으면 하위 배치 밖 변형
/// (`outer` — 덧붙일 때 저장소에서 찾은 번호).
fn variant_id(known: &HashMap<&str, i64>, outer: Option<&HashMap<String, i64>>, v: &Value) -> Result<i64> {
    match v["variant"].as_str() {
        None | Some("") => Ok(0),
        Some(key) => known.get(key).copied().or_else(|| outer.and_then(|o| o.get(key).copied()))
            .ok_or_else(|| format!("없는 변형을 가리킵니다: {key}").into()),
    }
}

/// 옛 번호 이어 쓰기 — 그 uid의 옛 번호가 있고 아직 쓰지 않았으면 그것(한 번만), 아니면 None(새 번호). 이름 없는 것은 늘 새 번호.
fn reuse(table: Option<&HashMap<String, i64>>, used: &mut std::collections::HashSet<i64>, uid: &str) -> Option<i64> {
    if uid.is_empty() {
        return None;
    }
    table.and_then(|t| t.get(uid).copied()).filter(|id| used.insert(*id))
}

fn geo(r: &Value) -> RowGeo {
    RowGeo {
        height: int(r, "height"), band_top: int(r, "bandTop"), band_h: int(r, "bandH"), dyn_top: int_or(r, "dynTop", -1),
        lead_top: int_or(r, "leadTop", -1), cab_top: int_or(r, "cabTop", -1), text_top: int_or(r, "textTop", -1),
        text_lines: int(r, "lines"), rail_top: int_or(r, "railTop", -1), organ_top: int_or(r, "organTop", -1),
    }
}

fn extra(r: &Value) -> RowExtra {
    RowExtra {
        kind: int(r, "kind"), group_start: int(r, "groupStart"), scope_pad: int(r, "scopePad"), phase: int(r, "phase"), rank: int(r, "rank"),
        cats: list(r, "cats").iter().filter_map(Value::as_i64).collect(),
        // figWide는 '넉넉하게' 밀도에서만 단이 늘어나는 줄에만 실려 온다 — 빠지면 fig와 같다.
        fig: int(r, "fig"), fig_wide: int_or(r, "figWide", int(r, "fig")), dep: int(r, "dep"), zones: int(r, "zones"), hem: int(r, "hem"),
        variant: 0, // 변형 번호는 아래에서 채운다(줄을 넣기 전에 변형을 먼저 만든다)
    }
}

/// 배치를 어디까지 채우는가(계획 P4 과제 5a ~ 5c).
pub enum FillHow<'a> {
    /// 통째로 — 새로 짓는 저장소(가져오기). 번호는 넣은 차례대로 난다.
    All,
    /// 덮는 트랙만 — 이미 있는 저장소에 덧붙인다(`patch::apply`의 "insert" · `Builder::append_after`). 배치는 `patch::sub_plan`이 낸 하위 배치다.
    /// 새 트랙은 새로 넣고, 다시 쓰는 트랙(부르는 쪽이 그 트랙의 것을 먼저 지웠다)은 `tracks.id` · 같은 uid의 띠 · 사건 · 같은 열쇠의 변형
    /// 번호를 그대로 쓴다(과제 5c). 하위 배치 밖 변형 열쇠(`outer.variants`) · 밖 칸 · 항목 가리기(`outer.hides`)는 [`TrackFill`]의 표로 푼다.
    Tracks(TrackFill<'a>),
}

/// [`FillHow::Tracks`]가 쓰는 재료 — 하위 배치(S) 밖을 저장소의 번호로 푸는 표. 열쇠는 모두 번호 없는 이름이다.
pub struct TrackFill<'a> {
    /// S — 넣는 트랙의 열쇠(`patch::track_key`). 하위 배치의 트랙이 꼭 이것이어야 한다.
    pub keys: &'a BTreeSet<String>,
    /// 자료집 글자 id → 저장소의 `packs.id`(배치의 `packs[]`가 모두 들어 있어야 한다 — `patch::apply`의 "packs"가 먼저 넣는다).
    pub packs: &'a HashMap<String, i64>,
    /// 트랙 열쇠 → 다시 쓰는 트랙의 옛 `tracks.id`(값만 바꿔 적는다 — `Builder::track_reuse`). 없는 열쇠는 새 트랙.
    pub tracks: &'a HashMap<String, i64>,
    /// 띠 · 사건 uid → 지운(다시 쓰는 · 사라지는) 트랙의 옛 번호(같은 uid는 옛 번호를 그대로 — 한 번씩만 쓴다. 같은 uid가 하위 배치에 둘이면
    /// 뒤엣것은 새 번호).
    pub reuse_periods: &'a HashMap<String, i64>,
    pub reuse_events: &'a HashMap<String, i64>,
    /// 변형 열쇠 → 지운 트랙의 옛 변형 번호(얹힌 몫 2 — 다시 쓰지 않은 트랙의 원소가 단 변형 번호가 맞게).
    pub reuse_variants: &'a HashMap<String, i64>,
    /// 하위 배치 밖 변형(`outer.variants` — S 안 원소가 단 S 밖 변형 열쇠) → 저장소의 변형 번호(판정 R16 가).
    pub outer_variants: &'a HashMap<String, i64>,
    /// 변형 열쇠 → 그 변형의 `outer.hides`(S 밖 칸 · 항목을 내용으로 적은 가림)를 저장소에서 찾은 (갈래, 번호) — 실린 차례대로(판정 R19).
    pub outer_hides: &'a HashMap<String, Vec<(i64, i64)>>,
    /// S 밖 띠 · 사건 uid → 저장소의 번호. S의 값이 가리키는 남의 트랙 uid(일반 항목 `ref` · 띠 번호 칸(`bandUids` — 판정 R14) · 사건 `band` ·
    /// 줄 이름의 띠 · 변형의 상위 띠 · 이사의 `ref`)를 푼다. 없는 uid는 통째 짓기와 같이 0(그 띠 · 사건이 없는 조합).
    pub outer_periods: &'a HashMap<String, i64>,
    pub outer_events: &'a HashMap<String, i64>,
    /// (S 밖 트랙 열쇠, 그 트랙 안 줄 순번) → 저장소의 줄 열쇠 — 변형의 `outer.rows` · `outer.moves` · `outer.groups`(S 밖 트랙의 줄을 가리킴)를 푼다.
    pub outer_rows: &'a HashMap<(String, i64), i64>,
}

/// 일반 항목의 칸 이름(`bandref`의 `A` ~ `D` 순번 — 하위 배치의 `bandUids` 열쇠).
const ABCD: [&str; 4] = ["a", "b", "c", "d"];

/// 하위 배치의 변형 목록 하나(`rows` · `moves` · `groups`)를 원래 차례로 — S 안 원소(제 목록)와 S 밖 원소(`outer.<목록>` · `"at"` = 원래 자리)를 섞는다.
/// 통째 짓기(밖 원소 없음)에서는 제 목록 그대로다.
pub(crate) fn merged<'v>(inner: &'v [Value], outer: &'v [Value]) -> Vec<&'v Value> {
    let total = inner.len() + outer.len();
    let mut slots: Vec<Option<&Value>> = vec![None; total];
    let mut stray = Vec::new();
    for o in outer {
        match usize::try_from(int(o, "at")).ok().filter(|at| *at < total) {
            Some(at) if slots[at].is_none() => slots[at] = Some(o),
            _ => stray.push(o),
        }
    }
    let mut rest = inner.iter();
    for slot in slots.iter_mut().filter(|s| s.is_none()) {
        *slot = rest.next();
    }
    slots.into_iter().flatten().chain(rest).chain(stray).collect()
}

/// 배치를 `b`에 채운다 — 가져오기(`import_layout` · `import_with`)의 짓기 본체. `b`를 마치는(`finalize`) 것은 부른 쪽이다
/// (여기서 적은 메타는 `Builder::add_meta`로 맡겨 두었다가 마칠 때 함께 적힌다).
/// `FillHow::All`이면 예전 `fill`과 같다(옮기기만 — 번호 · 표 내용 그대로). 새로 더한 것: 항목 기록의 넣은 차례 · 지문(`Builder::entity`)과
/// `meta.now`(배치 JSON의 `now` 글이 있으면 그것 — 없으면 지은 시각).
///
/// `FillHow::Tracks`(덧붙이기 — `b`는 `Builder::append_after`)는 하위 배치(`patch::sub_plan`)의 트랙 몫만 넣는다. `packs`는 쓰지 않는다(빈 목록 —
/// 자료집은 `TrackFill::packs`). 통째 짓기와 다른 것:
/// - 자료집 행 · 분류 · 시대 구분 · 공통 날짜 칸(track −1) · 문화권 단위 줄(`sphereLines`) · 그림 바이트 · 항목 기록 · 메타 · 트랙 지문은 넣지 않는다(부르는 쪽 몫 —
///   `patch::apply`의 "globals" · "entities" · "meta"). 항목 기록은 "entities"가 배치 전부를 uid · 지문으로 견주어 지움 · 바꿈 · 넣음 · 차례를 맞추고,
///   이번에 넣은 사건의 덧줄은 "names"가 그 뒤 저장소의 기록으로 적는다(과제 6).
/// - 다시 쓰는 트랙은 옛 `tracks.id`에 값만 바꿔 적고, 같은 uid의 띠 · 사건 · 같은 열쇠의 변형은 옛 번호로 넣는다(과제 5c). 사건의
///   트랙 안 차례(`events.ord` — 판정 R23)는 `Builder`가 센다 — 하위 배치는 넣는 트랙의 사건을 실린 차례 그대로 모두 실으므로 새 배치에서의
///   트랙 안 차례와 같다.
/// - S 밖을 가리키는 값은 [`TrackFill`]의 표로 푼다(띠 번호 칸은 `bandUids` — 판정 R14 · 밖 변형 열쇠 · 밖 칸 · 항목 가리기).
///   S 안 가리기(`hides[].at`)는 **이번에 넣은 칸 · 항목의 번호 목록**(실린 차례)으로 푼다 — '실린 차례 + 1 = 번호'를 가정하지 않는다.
pub fn fill_into(b: &mut Builder, plan: &Value, packs: Vec<PackPlan>, how: FillHow) -> Result<Value> {
    // 하위 배치를 채우는 도중에 S 밖 트랙의 것(줄 · 가리는 것)을 저장소에서 찾지 못함은 '그 트랙도 함께 다시 써야 함'(`patch::NeedsWhole` — 판정 R72-4):
    // 넣고 빼기(`packs::relayout`)는 거래를 되돌리고 모든 트랙으로 다시 하고, 메이커 `.htlayout`에는 글 그대로의 안내다.
    fn whole_needed(msg: String) -> Box<dyn std::error::Error + Send + Sync> {
        Box::new(crate::patch::NeedsWhole(msg))
    }
    let fill = match &how {
        FillHow::All => None,
        FillHow::Tracks(f) => Some(f),
    };
    if let Some(f) = fill {
        // 하위 배치 밖 변형 열쇠는 저장소의 번호로 풀 수 있어야 한다(판정 R16 가).
        for key in list(&plan["outer"], "variants") {
            let key = key.as_str().unwrap_or("");
            if !f.outer_variants.contains_key(key) {
                return Err(format!("다른 트랙의 변형 «{key}»을 저장소에서 찾지 못했습니다 — 배치와 저장소가 어긋났습니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)").into());
            }
        }
        let tracks = with_boards(plan, "tracks").len();
        for at in 0..tracks {
            let key = crate::patch::track_key(plan, at);
            if !f.keys.contains(&key) {
                return Err(format!("배치의 트랙 «{key}»이 고쳐 쓸 트랙에 없습니다(일부 트랙만 실은 배치)").into());
            }
        }
        if tracks != f.keys.len() {
            return Err(format!("배치의 트랙이 {tracks}개인데 고쳐 쓸 트랙은 {}개입니다(일부 트랙만 실은 배치)", f.keys.len()).into());
        }
        b.outer_rows(f.outer_rows.values().copied());
    }
    // S 밖 띠 · 사건 uid → 저장소의 번호(통째 짓기에는 밖이 없다).
    let outer_period = |uid: &str| fill.and_then(|f| f.outer_periods.get(uid).copied());
    let outer_event = |uid: &str| fill.and_then(|f| f.outer_events.get(uid).copied());
    let outer_variants = fill.map(|f| f.outer_variants);
    // 옛 번호 이어 쓰기(다시 쓰는 트랙 — 과제 5c). 같은 번호를 두 번 주지 않게 쓴 것을 적어 둔다.
    let mut used: std::collections::HashSet<i64> = std::collections::HashSet::new();
    // DLC 여러 벌(첫째가 기본). 자료집 번호는 배치의 `packs[]` 차례대로 1부터 난다.
    // 항목은 `pack` 열쇠(순번) → uid의 앞머리(`<DLC id>/…`) → 기본 DLC 차례로 제 DLC를 찾는다.
    let mut pack_ids: Vec<i64> = Vec::new();
    let mut pack_index: HashMap<String, i64> = HashMap::new();
    // DLC마다 판 · 분류 · 원본을 품었는가(`meta.pack_info` — `layout`의 `packs[]`와 다음 가져오기의 조합 대조가 읽는다).
    let mut pack_info: BTreeMap<String, Value> = BTreeMap::new();
    match fill {
        None => {
            for p in &packs {
                let made = b.pack(&p.name, p.original.as_deref())?;
                pack_ids.push(made);
                if let Some(key) = &p.key {
                    pack_index.insert(key.clone(), made);
                }
                pack_info.insert(made.to_string(), json!({"id":p.key.as_deref().unwrap_or(""),"version":p.version,"category":p.category,"original":p.original.is_some()}));
            }
        }
        // 덧붙이기: 자료집 행은 이미 있다 — 배치의 `packs[]` 차례 그대로 저장소의 번호로.
        Some(f) => {
            for d in list(plan, "packs") {
                let key = text(d, "id");
                let made = *f.packs.get(key).ok_or_else(|| format!("배치의 자료집 «{key}»이 저장소에 없습니다"))?;
                pack_ids.push(made);
                pack_index.insert(key.to_owned(), made);
            }
        }
    }
    let first = *pack_ids.first().ok_or("배치에 DLC가 없습니다")?;
    let pack = first;
    let pack_at = |v: &Value, uid: &str| -> i64 {
        pack_ids[pack_slot(v, uid, pack_ids.len(), |head| pack_index.get(head).and_then(|id| pack_ids.iter().position(|x| x == id)))]
    };
    // 분류 · 시대 구분 · 공통 날짜 칸은 온 판이다 — 덧붙일 때는 넣지 않는다(`patch::apply`의 "globals").
    let whole = fill.is_none();
    let categories = if whole { list(plan, "categories") } else { &[] };
    for (ord, c) in categories.iter().enumerate() {
        b.category(pack, ord as i64, text(c, "key"), text(c, "name"), int(c, "color") as u32)?;
    }
    // 트랙 안 줄 번호 → 전체 줄 번호
    let mut rows_of: Vec<Vec<i64>> = Vec::new();
    let mut tracks: Vec<i64> = Vec::new();
    // 변형(계약 3-2절)은 줄보다 먼저 만든다 — 줄의 `variant` 열이 이 번호를 가리킨다.
    // 상위 띠의 번호(`band`)는 띠를 다 넣은 뒤에 채운다(그때에야 uid → 번호를 안다).
    let mut variant_of: HashMap<&str, i64> = HashMap::new();
    for (at, track) in with_boards(plan, "tracks").into_iter().enumerate() {
        // railLevels는 스키마의 기본값이 2다(기간 막대는 적어도 두 단) — 빠져 있으면 0이 아니라 2로 읽는다.
        let t = TrackIn {
            pack: pack_at(track, ""), name: text(track, "name"), color: int(track, "color") as u32, dynasty: int(track, "dynasty"), leader: int(track, "leader"),
            cabinet: int(track, "cabinet"), organ: int(track, "organ"), rail_levels: int_or(track, "railLevels", 2),
            // 트랙의 글자 id(`mw-coast`). 항목 기록의 `track`이 이 글자다 — 내보내기가 싣지 않던 때의 JSON은 빈 글자로 읽는다.
            key: text(track, "key"),
        };
        // 다시 쓰는 트랙은 옛 번호에 값만 바꿔 적는다(과제 5c).
        let id = match fill.and_then(|f| f.tracks.get(&crate::patch::track_key(plan, at)).copied()) {
            Some(old) => b.track_reuse(old, &t)?,
            None => b.track_full(&t)?,
        };
        // 문화권(리메이크 조각 ②)의 글자 id. 판 트랙 · 옛 배치에는 없어 빈 글자로 둔다.
        b.track_sphere(id, text(track, "sphere"))?;
        tracks.push(id);
        rows_of.push(Vec::new());
    }
    for v in with_boards(plan, "variants") {
        let key = text(v, "key");
        if key.is_empty() {
            return Err("변형에 열쇠(key)가 없습니다".into());
        }
        let at = int(v, "track");
        let track = usize::try_from(at).ok().and_then(|t| tracks.get(t)).copied().ok_or_else(|| format!("없는 변형의 트랙: {at}"))?;
        // 같은 열쇠의 변형은 옛 번호로(얹힌 몫 2). 열쇠는 저장소에서 하나뿐이라(UNIQUE) 두 번 쓰일 일이 없다.
        let old = fill.and_then(|f| f.reuse_variants.get(key).copied());
        let id = b.variant_at(old, key, int(v, "kind"), track, 0, text(v, "uid"), text(v, "name"), text(v, "notes"))?;
        variant_of.insert(key, id);
    }
    for (at, track) in with_boards(plan, "tracks").iter().enumerate() {
        let mut rows = Vec::new();
        for r in list(track, "rows") {
            let mut more = extra(r);
            // 그 변형에서만 있는 줄이면 `variant`가 실려 온다(기본 줄은 빠져 있다).
            more.variant = variant_id(&variant_of, outer_variants, r)?;
            rows.push(b.row_full(tracks[at], &geo(r), &more)?);
        }
        rows_of[at] = rows;
    }
    let mut groups = 0;
    for (at, track) in with_boards(plan, "tracks").iter().enumerate() {
        for g in list(track, "groups") {
            let first = int(g, "first");
            let row = usize::try_from(first).ok().and_then(|r| rows_of[at].get(r)).copied()
                .ok_or_else(|| format!("없는 묶음의 첫 줄: 트랙 {at} · 줄 {first}"))?;
            b.group(&GroupIn { track: tracks[at], depth: int(g, "depth"), first_row: row, row_count: int(g, "count"), name: text(g, "name"), color: int(g, "color") as u32, kind: int(g, "kind") })?;
            groups += 1;
        }
    }
    let row_at = |item: &Value, key: &str| -> Result<i64> {
        let (track, row) = (int(item, "track"), int(item, key));
        usize::try_from(track).ok().and_then(|t| rows_of.get(t)).and_then(|rows| usize::try_from(row).ok().and_then(|r| rows.get(r))).copied()
            .ok_or_else(|| format!("없는 줄: 트랙 {track} · 줄 {row}").into())
    };
    let epochs = if whole { list(plan, "epochs") } else { &[] };
    for e in epochs {
        b.epoch(pack, int(e, "start"), int(e, "end"), int(e, "color") as u32, text(e, "name"))?;
    }
    // 문화권 단위의 줄(스키마 4 · 계약 1-1 — 사람 띠 · 문화권 시대 · 주기 줄). 배치 차례가 곧 id 차례이고 자료집은 띠 · 사건 · 기록과 같은 규칙.
    // 온 판이라 덧붙일 때는 넣지 않는다(`patch::apply`가 맡는다). 시간 범위(`meta.min` · `max`)는 넓히지 않는다(`builder::put_sphere_lines`).
    let sphere_lines = if whole { list(plan, "sphereLines") } else { &[] };
    b.sphere_lines(sphere_lines, pack_at)?;
    let mut axis_cells = 0;
    for a in list(plan, "axis") {
        // track: -1(또는 빠짐)이면 공통 줄. 아니면 트랙 순번 → 트랙 번호.
        let at = int_or(a, "track", -1);
        if at < 0 && !whole {
            continue; // 공통 줄은 온 판(하위 배치에 통째로 실려 온다)
        }
        axis_cells += 1;
        let track = if at < 0 { None } else {
            Some(usize::try_from(at).ok().and_then(|t| tracks.get(t)).copied().ok_or_else(|| format!("없는 날짜 칸의 트랙: {at}"))?)
        };
        b.axis_cell(&AxisCellIn { pack: pack_at(a, ""), kind: int(a, "kind"), track, lane: int(a, "lane"), start: int(a, "start"), end: int(a, "end"),
            name: text(a, "name"), color: int(a, "color") as u32, style: int(a, "style"), strip: int(a, "strip"), seq: int(a, "seq") })?;
    }
    // 같은 줄에서 띠끼리, 같은 단에서 칸끼리 겹쳐도 거절하지 않는다 — 바탕 문화 · 여러 단의 기관이 그렇게 들어온다.
    let mut period_of: HashMap<&str, i64> = HashMap::new();
    // 띠 번호 → 기간(줄 이름이 기간을 빌린다). 새 저장소에서는 번호가 넣은 차례 + 1이지만 덧붙일 때는 아니라 번호로 찾는다.
    let mut period_span: HashMap<i64, (i64, i64)> = HashMap::new();
    // 띠 · 사건의 번호 → DLC(칸 · 이름표 같은 일반 항목은 제가 딸린 띠 · 사건의 DLC를 따른다).
    let mut period_pack: HashMap<i64, i64> = HashMap::new();
    let mut event_pack: HashMap<i64, i64> = HashMap::new();
    for p in with_boards(plan, "periods") {
        let (start, end) = (int(p, "start"), int(p, "end"));
        let p_pack = pack_at(p, text(p, "uid"));
        let id = b.period_at(&PeriodIn {
            pack: p_pack, row: row_at(p, "row")?, start, end, fuzzy: int(p, "fuzzy"), color: int(p, "color") as u32,
            name: text(p, "name"), look: int(p, "look"), tag: text(p, "tag"), sub: int(p, "sub"), uid: text(p, "uid"),
            variant: variant_id(&variant_of, outer_variants, p)?,
            // 형식 4의 뜻(스키마 4 · 계약 1-1 비트) — 이 열쇠가 없는 옛 배치는 0(모름).
            form: int(p, "form"),
        }, reuse(fill.map(|f| f.reuse_periods), &mut used, text(p, "uid")))?;
        period_of.insert(text(p, "uid"), id);
        period_pack.insert(id, p_pack);
        period_span.insert(id, (start, end));
    }
    let cells = with_boards(plan, "cells");
    // 넣은 칸 · 일반 항목의 번호(배치의 자리 차례) — 변형의 가리기(`hides[].at`)가 이 자리를 가리킨다. 새 저장소에서는 자리 + 1과 같다.
    let mut cell_ids: Vec<i64> = Vec::with_capacity(cells.len());
    for c in &cells {
        let period = *period_of.get(text(c, "period")).ok_or("칸이 가리키는 띠가 배치에 없습니다")?;
        cell_ids.push(b.cell_full(&CellIn { period, kind: int(c, "kind"), start: int(c, "start"), end: int(c, "end"), name: text(c, "name"),
            lane: int(c, "lane"), style: int(c, "style"), color: int(c, "color") as u32, variant: variant_id(&variant_of, outer_variants, c)? })?);
    }
    let mut unknown = 0;
    let mut event_of: HashMap<&str, i64> = HashMap::new();
    let events = with_boards(plan, "events");
    // 띠와 사건의 번호는 셈이 따로다 — 쓴 번호도 따로 적는다.
    let mut used_events: std::collections::HashSet<i64> = std::collections::HashSet::new();
    for e in &events {
        let (start, end) = (e["start"].as_i64(), e["end"].as_i64());
        if start.is_none() {
            unknown += 1;
        }
        // 원소 JSON 그대로(`events.raw` — 읽는 곳 없음 · 보존용). 그 안의 `track`은 **믿지 말 것**: 이 배치 안의 트랙 순번이라, 덧붙이기(`FillHow::Tracks`)에서는
        // 하위 배치가 다시 매긴 순번이고, 다시 쓰지 않은 트랙의 사건은 다른 트랙이 들고 나도 옛 순번 그대로다(과제 A+ 5). 트랙은 `lane` → `rows.track`으로 읽는다.
        let raw_event = e.to_string();
        // 그 사건이 든 띠(uid → 번호). 지금 연표는 점 색 · 이름 가두기 · 묶기를 모두 제 띠 안에서 한다.
        let band = period_of.get(text(e, "band")).copied().or_else(|| outer_period(text(e, "band"))).unwrap_or(0);
        let e_pack = pack_at(e, text(e, "uid"));
        let id = b.event_at(&EventIn {
            pack: e_pack, lane: row_at(e, "row")?, start, end: end.or(start), lo: None, hi: None, importance: int_or(e, "importance", 1).clamp(1, 3),
            title: text(e, "title"), body: text(e, "body"), source: None, raw: Some(&raw_event),
            look: int(e, "look"), label: text(e, "label"), rail: int(e, "rail"), uid: text(e, "uid"), band,
            variant: variant_id(&variant_of, outer_variants, e)?,
        }, reuse(fill.map(|f| f.reuse_events), &mut used_events, text(e, "uid")))?;
        event_of.insert(text(e, "uid"), id);
        event_pack.insert(id, e_pack);
    }
    let items = with_boards(plan, "items");
    let mut item_ids: Vec<i64> = Vec::with_capacity(items.len());
    for it in &items {
        let name = text(it, "ref");
        // 가리키는 곳은 띠가 먼저, 없으면 사건, 그래도 없으면 0(가리키는 것이 없는 항목). 덧붙일 때는 S 안 → S 밖(저장소) 차례로 찾는다.
        // 띠와 사건의 번호는 서로 다른 셈이라 번호만 보고는 가릴 수 없다 — 여기서 본 것을 ref_kind로 적어 둔다(거르개가 쓴다).
        // 항목의 자료집은 가리키는 띠 · 사건의 것을 따른다(S 밖이면 저장소에서 읽는다).
        let (reference, ref_kind, ref_pack) = if let Some(band) = period_of.get(name) {
            (*band, 1, period_pack.get(band).copied())
        } else if let Some(band) = outer_period(name) {
            (band, 1, b.stored_period(band)?.map(|p| p.0))
        } else if let Some(event) = event_of.get(name) {
            (*event, 2, event_pack.get(event).copied())
        } else if let Some(event) = outer_event(name) {
            (event, 2, b.stored_event_pack(event)?)
        } else {
            (0, 0, None)
        };
        // lod: -1(또는 빠짐)이면 기간에서 셈한다.
        let lod = int_or(it, "lod", -1);
        // row2가 빠지면 한 줄짜리(row와 같다).
        let row2 = row_at(it, if it["row2"].is_null() { "row" } else { "row2" })?;
        let it_pack = ref_pack.unwrap_or_else(|| pack_at(it, ""));
        // 띠 번호 칸(`bandref`): 통째 짓기는 배치의 값 그대로('periods' 자리 + 1 = 번호). 하위 배치는 칸 값이 0이고
        // `bandUids`(칸 → 띠 uid)가 달려 온다(판정 R14) — S 안이면 이번에 넣은 번호, 밖이면 저장소의 번호, 어디에도 없으면 0.
        let mut abcd = ABCD.map(|key| int(it, key));
        if fill.is_some() {
            for (field, uid) in it["bandUids"].as_object().into_iter().flatten() {
                let at = ABCD.iter().position(|k| k == field).ok_or_else(|| format!("띠 번호 칸의 이름이 올바르지 않습니다: {field}"))?;
                let uid = uid.as_str().unwrap_or("");
                abcd[at] = period_of.get(uid).copied().or_else(|| outer_period(uid)).unwrap_or(0);
            }
        }
        item_ids.push(b.item(&ItemIn {
            pack: it_pack, section: int(it, "section"), row: row_at(it, "row")?, row2, start: int(it, "start"), end: int(it, "end"),
            lod: (lod >= 0).then_some(lod), ref_id: reference, ref_kind, name: text(it, "name"), color: int(it, "color") as u32,
            a: abcd[0], b: abcd[1], c: abcd[2], d: abcd[3], text2: text(it, "text2"),
            variant: variant_id(&variant_of, outer_variants, it)?,
        })?);
    }
    // 왼쪽 줄 이름 칸이 쓰는 후보 띠. 원소의 JSON은 통째로 보존하고, 찾아 쓰는 값(줄 · 기간 · 띠)만 열로 꺼낸다.
    let row_labels = with_boards(plan, "rowLabels");
    for label in &row_labels {
        let uid = text(label, "period");
        let period = period_of.get(uid).copied().or_else(|| outer_period(uid)).unwrap_or(0);
        // 원소에 start · end가 없으면 그 띠의 기간을 쓴다(S 밖 띠면 저장소에서).
        let span = match period_span.get(&period) {
            Some(span) => *span,
            None if period != 0 => b.stored_period(period)?.map_or((0, 0), |p| (p.1, p.2)),
            None => (0, 0),
        };
        let start = if label["start"].is_null() { span.0 } else { int(label, "start") };
        let end = if label["end"].is_null() { span.1 } else { int(label, "end") };
        b.row_label(row_at(label, "row")?, start, end, period, &label.to_string())?;
    }
    // 변형의 차례 · 이사 · 가리는 것 · 묶음. 줄 · 띠 · 사건의 번호가 다 정해진 뒤에 넣는다.
    let (mut variant_rows, mut variant_moves, mut variant_hides, mut variant_groups) = (0, 0, 0, 0);
    // 변형이 가리키는 줄: 트랙 칸(`key`)이 수면 이 배치의 트랙 순번, 글이면 하위 배치 밖 트랙의 열쇠(덧붙일 때 — 저장소의 줄 열쇠로 푼다).
    let at = |v: &Value, key: &str, row: i64| -> Result<i64> {
        if let (Some(outer), Some(f)) = (v[key].as_str(), fill) {
            return f.outer_rows.get(&(outer.to_owned(), row)).copied()
                .ok_or_else(|| whole_needed(format!("다른 트랙 «{outer}»의 {row}번째 줄을 저장소에서 찾지 못했습니다 — 배치와 저장소가 어긋났습니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)")));
        }
        let track = int(v, key);
        usize::try_from(track).ok().and_then(|t| rows_of.get(t)).and_then(|rows| usize::try_from(row).ok().and_then(|r| rows.get(r))).copied()
            .ok_or_else(|| format!("없는 변형의 줄: 트랙 {track} · 줄 {row}").into())
    };
    for v in with_boards(plan, "variants") {
        let id = *variant_of.get(text(v, "key")).ok_or("변형을 찾지 못했습니다")?;
        // 하위 배치의 `outer`(S 밖을 가리키는 원소)는 덧붙일 때만 읽는다 — 통째 짓기에는 모르는 열쇠라 예전처럼 건너뛴다
        // (P3 과제 16 · 지문 검사가 하위 배치를 통째로 지어 보는 길).
        let outer = if whole { &Value::Null } else { &v["outer"] };
        // S 밖 칸 · 항목을 가리는 것(판 변형이 원래 트랙의 것을 가림)은 부르는 쪽이 저장소에서 내용으로 찾아 둔 번호로(판정 R19 · 과제 5c).
        let outer_hides = list(outer, "hides");
        if !outer_hides.is_empty() {
            let found = fill.and_then(|f| f.outer_hides.get(text(v, "key"))).map(Vec::as_slice).unwrap_or(&[]);
            if found.len() != outer_hides.len() {
                return Err(whole_needed(format!("변형 «{}»이 다른 트랙에서 가리는 것 {}개 가운데 {}개만 저장소에서 찾았습니다 — 그 트랙도 함께 다시 써야 합니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)",
                    text(v, "key"), outer_hides.len(), found.len())));
            }
            for (kind, target) in found {
                b.variant_hide(id, *kind, *target)?;
                variant_hides += 1;
            }
        }
        // 줄 · 이사 · 묶음은 S 안 것(제 목록)과 S 밖 트랙의 줄을 가리키는 것(`outer.*` — 원래 자리 `at`)을 원래 차례로 섞어 넣는다.
        let part = |name: &str| merged(list(v, name), list(outer, name));
        for r in part("rows") {
            let after = int_or(r, "after", -1);
            // after −2 = **그 변형에서 빠지는 줄**(집합 보기가 판으로 통째로 옮긴 원래 트랙의 줄 — 앱은 쌓지 않는다).
            // 그때 ord에는 그 줄이 옮겨 간 판 줄의 전체 번호를 싣는다(`toTrack` · `to` — 없으면 −1): 앱의 '가려는 곳 펴기'가 판 줄로 잇는다.
            let (after_row, ord) = if after == -2 {
                let to = match r["to"].as_i64() {
                    Some(to) => at(r, "toTrack", to)?,
                    None => -1,
                };
                (-2, to)
            } else {
                (if after < 0 { -1 } else { at(r, "track", after)? }, int(r, "ord"))
            };
            b.variant_row(id, at(r, "track", int(r, "row"))?, after_row, ord, int(r, "new") != 0, int(r, "scopePad"), int(r, "groupStart"))?;
            variant_rows += 1;
        }
        for m in part("moves") {
            let kind = int(m, "kind");
            let name = text(m, "ref");
            let reference = match kind {
                1 => period_of.get(name).copied().or_else(|| outer_period(name)),
                2 => event_of.get(name).copied().or_else(|| outer_event(name)),
                _ => return Err(format!("모르는 변형 이사의 갈래: {kind}").into()),
            }
            .ok_or_else(|| format!("변형의 이사가 가리키는 것이 없습니다: {name}"))?;
            b.variant_move(id, kind, reference, at(m, "track", int(m, "row"))?)?;
            variant_moves += 1;
        }
        // 가리는 것: 내보내기가 적어 보낸 자리(0부터 — 이 배치의 `cells` · `items`)의 칸 · 항목을 이번에 넣은 번호로.
        // 새 저장소에서는 번호 = 자리 + 1(넣는 차례가 같다)이라 예전과 같은 값이다.
        for h in list(v, "hides") {
            let kind = int(h, "kind");
            let ids = match kind {
                3 => &cell_ids,
                4 => &item_ids,
                _ => return Err(format!("모르는 변형 가리기의 갈래: {kind}").into()),
            };
            let index = int(h, "at");
            let target = usize::try_from(index).ok().and_then(|i| ids.get(i)).ok_or_else(|| format!("변형이 가리키는 자리가 범위 밖입니다: {index}"))?;
            b.variant_hide(id, kind, *target)?;
            variant_hides += 1;
        }
        for g in part("groups") {
            let mut rows = Vec::new();
            for row in list(g, "rows") {
                rows.push(at(g, "track", row.as_i64().unwrap_or(-1))?);
            }
            b.variant_group(id, text(g, "key"), int(g, "depth"), text(g, "name"), int(g, "color") as u32, int(g, "kind"), &rows)?;
            variant_groups += 1;
        }
        let band = text(v, "band");
        if let Some(band) = period_of.get(band).copied().or_else(|| outer_period(band)) {
            b.variant_band(id, band)?;
        }
    }
    // 항목 기록은 통째로 지을 때만 넣는다. 덧붙일 때는 `patch::apply`의 "entities"가 배치의 기록 전부를 저장소와 uid · 지문으로 견주어
    // 지움 · 바꿈 · 넣음 · 차례를 맞추고(여기서 먼저 넣으면 그 견줌이 바뀐 기록을 놓친다), 이번에 넣은 사건의 덧줄은 "names"가 저장소의 기록으로 적는다(과제 6).
    let entities = if whole { with_boards(plan, "entities") } else { Vec::new() };
    let mut entity_count = 0;
    for en in &entities {
        let uid = text(en, "uid");
        if uid.is_empty() {
            return Err("항목 기록에 id가 없습니다".into());
        }
        b.entity(uid, pack_at(en, uid), text(en, "kind"), text(en, "json"))?;
        entity_count += 1;
    }
    // 그림 바이트(문서 그림 — 겉 열쇠 `blobs[]`, 없으면 빈 목록). 열쇠는 `img:<DLC id>/<그림 id>`라 '/' 앞이 DLC id가 아니므로 `pack` 순번이 먼저다.
    // 자료집에 딸린 것이라 덧붙일 때는 넣지 않는다(`patch::apply`의 "entities"가 견준다).
    let blobs = if whole { list(plan, "blobs") } else { &[] };
    for bl in blobs {
        let key = text(bl, "key");
        let mime = text(bl, "mime");
        if key.is_empty() || !mime.starts_with("image/") {
            return Err(format!("그림 바이트의 열쇠나 종류가 올바르지 않습니다: {key}").into());
        }
        let bytes = crate::base64_decode(text(bl, "data")).ok_or_else(|| format!("그림 바이트를 풀 수 없습니다(base64): {key}"))?;
        b.blob(key, pack_at(bl, key.trim_start_matches("img:")), mime, &bytes)?;
    }
    let mut counts = json!({"tracks":rows_of.len(),"rows":rows_of.iter().map(Vec::len).sum::<usize>(),"groups":groups,
        "categories":categories.len(),"periods":period_of.len(),"cells":cells.len(),
        "epochs":epochs.len(),"axis":axis_cells,"events":events.len(),"unknown":unknown,
        "items":items.len(),"entities":entity_count,"row_labels":row_labels.len(),
        "variants":variant_of.len(),"variant_rows":variant_rows,"variant_moves":variant_moves,"variant_hides":variant_hides,"variant_groups":variant_groups});
    if !blobs.is_empty() {
        counts["blobs"] = json!(blobs.len()); // 그림이 없는 배치의 답은 예전 그대로
    }
    if !sphere_lines.is_empty() {
        counts["sphere_lines"] = json!(sphere_lines.len()); // 문화권 단위 줄이 없는 배치의 답도 예전 그대로
    }
    if !whole {
        return Ok(counts); // 덧붙이기: 메타 · 트랙 지문은 부르는 쪽(`patch::apply`)이 적는다
    }
    // DLC의 글자 id(메이커가 준 `id` · 기본팩 `east-asia-base`)를 번호 옆에 남긴다 — 다시 지은 저장소에서 화면이 같은 DLC를 알아보는 열쇠다
    // (번호는 다시 지을 때마다 바뀔 수 있다). `layout`의 `packs[].key`가 이것을 읽는다.
    let pack_keys: std::collections::BTreeMap<String, String> = pack_index.iter().map(|(key, id)| (id.to_string(), key.clone())).collect();
    let mut metadata = vec![
        ("pack_keys", serde_json::to_string(&pack_keys)?),
        // 이 저장소가 어느 DLC 차례의 통째 짓기인가(배치의 `packs[]` 차례 — P4 과제 9: `add_pack`이 이 차례에 새 DLC를 뒤에 붙여 다시 셈한다).
        ("pack_order", serde_json::to_string(&packs.iter().map(|p| p.key.clone().unwrap_or_default()).collect::<Vec<_>>())?),
        ("pack_info", serde_json::to_string(&pack_info)?),
        // 규칙 판(`meta.rules`)은 여기서 적지 않는다(판정 R69-2) — 채우는 배치가 Rust가 원본으로 셈한 것인지 모른다(Node 내보내기 · 메이커 배치도 이 길).
        // 짓기([`build_store`])만 적는다.
    ];
    metadata.extend(plan_meta(plan)?.into_iter().filter_map(|(key, value)| value.map(|v| (key, v))));
    // 트랙 지문(계획 P4 과제 4) — 다음 DLC 넣고 빼기(`apply`)가 이것과 견주어 바뀐 트랙만 다시 쓴다.
    // 지문을 낼 수 없는 배치(트랙 열쇠가 겹침 · 판 트랙 열쇠가 약속과 어긋남)도 짓기는 그대로 한다 — 지문을 적지 않으면
    // 그 저장소의 첫 `apply`가 모든 트랙을 '지문 없음 → 다시 씀'으로 보고, 그때 같은 까닭으로 거절한다.
    if let Ok(prints) = crate::patch::prints(plan) {
        b.track_prints(&prints)?;
    }
    for (key, value) in metadata {
        b.add_meta(key, value);
    }
    // 지은 날(`meta.now`): 배치가 굳은 시각을 주면(P3 Rust 배치 · 같은 저장소를 다시 지을 수 있게) 그 글 그대로. 없으면 지금 시각.
    // (시계는 여기서만 본다 — `Builder::finalize`는 보지 않아 가상 자료 생성기 같은 길은 언제 지어도 같은 바이트다.)
    let now = plan["now"].as_str().filter(|s| !s.is_empty()).map_or_else(iso_now, str::to_owned);
    b.add_meta("now", now);
    Ok(counts)
}

/// 배치에서 그대로 옮겨 적는 온 판 메타 — 짓기(`fill_into`)와 덧붙이기(`patch::apply`의 "globals")가 함께 쓴다. 차례는 짓기가 적는 차례 그대로이고,
/// 배치에 없으면 None(짓기는 열쇠를 만들지 않고 · 덧붙이기는 지운다).
/// - `year_cycle` · `year_cycles`: D4 간지 설정 — 날짜 칸의 순환 하나와 DLC 차례의 후보. info가 meta의 JSON 글을 그대로 답한다.
///   설정 없는 옛 배치는 열쇠를 만들지 않는다(육십갑자 그대로). DLC 켬끔에 따른 선택은 앱의 몫이다.
/// - `spheres`: 문화권 목록(리메이크 조각 ② — 쓰인 문화권만 차례대로 `[{id, name, order, count, default}]`). 원소는 뜻을 모른 채 그대로 싣고,
///   `layout`의 최상위 `spheres`가 풀어 답한다. 없거나 빈 목록인 옛 배치는 열쇠를 만들지 않는다(답은 빈 목록).
pub(crate) fn plan_meta(plan: &Value) -> Result<[(&'static str, Option<String>); 3]> {
    let cycle = plan.get("yearCycle").filter(|v| v.is_object()).map(serde_json::to_string).transpose()?;
    let cycles = plan.get("yearCycles").filter(|v| v.as_array().is_some_and(|l| !l.is_empty())).map(serde_json::to_string).transpose()?;
    let spheres = plan.get("spheres").filter(|v| v.as_array().is_some_and(|l| !l.is_empty())).map(serde_json::to_string).transpose()?;
    Ok([("year_cycle", cycle), ("year_cycles", cycles), ("spheres", spheres)])
}

/// 지금 시각의 ISO 글(UTC · 초까지 — `2026-10-16T06:14:40Z`). 배치가 `now`를 주지 않았을 때 저장소의 `meta.now`가 된다
/// (통째 짓기와 덧붙이기 `patch::apply`가 같은 규칙으로 쓴다).
pub(crate) fn iso_now() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    let (year, month, day) = crate::span::civil_from_days(secs.div_euclid(86_400));
    let rest = secs.rem_euclid(86_400);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z", rest / 3600, rest % 3600 / 60, rest % 60)
}

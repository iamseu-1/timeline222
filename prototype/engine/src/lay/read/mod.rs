//! 읽기 — `js/core.js`의 DLC 정규화(`HT.normalizePack`)와 그것이 부르는 `HT.read*` · 공용 도움 함수를 줄 그대로 옮긴다(한 벌 P3 과제 5a ~ 5c · 이음매 ①).
//! 옮기는 규칙은 `lay::js`의 머리말(계획 `계획-한벌-P3-Rust배치.md` 머리의 표). 파일은 `core.js`의 절 차례로 나눴다:
//! - [`vocab`] — 1 ~ 459줄의 형식 상수 · 낱말 표(팩 분류 · 관계 · 한도 · 팔레트 · 기본 분류 · 확실성 · 실재성 · 승계 · 정권 종류 · 문화권 · 소속 관계 · 도읍 역할)와
//!   그 읽기(`historicity` · `normalizeSucc` · `polityKindId` · `relationId` · `capitalRole`)
//! - [`capital`] — 461 ~ 594줄의 도읍 칸 · 지도자 대수(`normalizeCapital` · `numberLeaders`)
//! - [`cells`] — 944 ~ 1724줄의 칸 · 칸 차례 · 시기 구분 · 지위 · 소속 · 대범위 참조 · 미정 · 이설 · 확실성 읽기(`readCellEdge` · `sortCells` · `readPhases` · `readRankDefs` ·
//!   `readRanks` · `readPartOf` · `compactPartOf` · `readScopeRef` … `readUncertain` · `vocab`)
//! - [`treaty`] — 1681 ~ 1878줄의 조약 규격(`readSigners` · `splitArticles` · `readTreaty`) — 5c
//! - [`groups`] — 1880 ~ 2426줄의 단체 · 주제 사전 · 제도 칸 · 법 · 선거(`groupType` · `readThemeDefs` · `readThemeList` · `readLaw` · `readElection` · `readPolityRows` ·
//!   `readGroupFrom` · `readInstPolity` · `readInstSpans`) — 5c
//! - [`names`] — 2436 ~ 2931줄의 이름 목록 · 글자 범위 · 사람 잇기 · 좌표(`NAME_KINDS` · `nameKind` · `isLangTag` · `readNames` · `parseRange` · `readPersonRef` · `readAccession` ·
//!   `readParents` · `readSpouses` · `readGroupPeople` · `readCoords`)
//! - [`misc`] — 2940 ~ 3070줄의 배열 기준 · 남북 값 · 사건의 자리 · 간지 설정 · 해시 · 색(`readRowOrder` · `readNorthSouth` · `readSpot` · `readYearCycle` · `hash` · `autoColor` · `isColor`)
//! - [`dates`] — 3216 ~ 3359줄의 날짜 칸(`yearOf` · `formatYear` · `atFits` · `endBound` · `parseYear` · `readDate` · `isOngoingText`)과 정규화의 머리(`ID_RE` · `str` · `arr` · `toYear` · `dateIn` · `PATCHABLE`)
//! - [`info`] — 3360 ~ 3841줄의 팩 정보 · 모아 보기 판 · 지도 · 글꼴(`readPackInfo` · `ownId` · `readSpan` · `readViewSettings` · `readViews` · `readMaps` · `readFonts`)
//! - [`normalize`] — 3849 ~ 5072줄 `HT.normalizePack`(절 경계로 나눈 `normalize/*.rs`와 함께)
//! - [`docs`] — 5074 ~ 5371줄의 문서 키 · 문서 그림(`HT.docKey.valid` · `readImages`) — 5c
//!
//! 값은 JS 값 그대로([`V`] — 옮기는 규칙 표의 첫 줄): 원본 DLC(`raw`)와 정규화한 팩(`pack`)이 모두 `V`이고, 이음매 ①은 `js::to_json(pack)`(= `JSON.parse(JSON.stringify(pack))`).
//! '오늘' · 시간대 · 달력 표처럼 웹 코드가 전역(`HT`)에서 읽던 값은 [`Ctx`]로 받는다.
use super::cal;
use super::js::{self, Str, V};

pub mod alts;
pub mod capital;
pub mod cells;
pub mod dates;
pub mod docs;
pub mod groups;
pub mod info;
pub mod misc;
pub mod names;
pub mod normalize;
pub mod treaty;
pub mod vocab;

pub use normalize::{normalize_pack, Normalized};

/// 웹 코드가 전역에서 읽던, 실행마다 정해지는 값.
/// - `current_year`: `HT.CURRENT_YEAR`(= `new Date().getFullYear()` — **지역** 연도) · `now_t`: `HT.NOW_T`(오늘의 해 좌표 — 지역 연 · 월 · 일).
/// - `cal`: 보조 달력의 표(`lay::cal` 머리말 — 없으면 보조 달력 날짜를 읽지 못함).
/// - `split`: `HT.F4.split`(형식 4의 옮겨 앉기 토막 내기 — 새 앱으로 내보낼 때만 참 · `export/base.mjs`의 `bootWeb`).
pub struct Ctx { pub current_year: f64, pub now_t: f64, pub cal: cal::Tables, pub split: bool }

impl Ctx {
    /// 배치 선택(`Opts`)의 시각 · 시간대 · 달력 표로 만든다. `split`은 새 앱 내보내기와 같게 참.
    pub fn new(opts: &super::Opts) -> crate::Result<Ctx> {
        let (y, m, d) = js::local_ymd(opts.now_ms, opts.tz_min); // m은 1 ~ 12(JS getMonth() + 1과 같음)
        let (y, m, d) = (f64::from(y), f64::from(m), f64::from(d));
        let tables = match &opts.calendar { Some(bytes) => cal::Tables::shared(bytes)?, None => cal::Tables::none() };
        Ok(Ctx { current_year: y, now_t: cal::t_of(cal::jdn_civil(y, m, d), 0.0), cal: tables, split: true })
    }
}

/// 알림 하나(`{ msg, kind, index }` — kind의 기본은 'info' · 'info'인 오류는 치명적이라 팩이 null).
#[derive(Debug, Clone, PartialEq)]
pub struct Note { pub msg: String, pub kind: String, pub index: Option<f64> }

// ── JS 뜻의 작은 도움(옮긴 함수가 아니라 식 하나의 뜻 — 옮기는 규칙 표를 따름) ──

/// JS `v && v[k]`(v가 거짓이면 v 그대로).
pub fn and(v: &V, k: &str) -> V { if js::truthy(v) { v.get(k) } else { v.clone() } }
/// JS `!v || typeof v !== 'object'`의 반대 — null이 아닌 객체(배열 · Map · Set 포함).
pub fn is_object(v: &V) -> bool { matches!(v, V::Arr(_) | V::Obj(_) | V::Map(_) | V::Set(_)) }
/// JS `v && typeof v === 'object' && !Array.isArray(v)`.
pub fn is_plain(v: &V) -> bool { matches!(v, V::Obj(_) | V::Map(_) | V::Set(_)) }
/// JS `v === ''`.
pub fn is_empty_str(v: &V) -> bool { matches!(v, V::Str(s) if s.is_empty()) }
/// JS `v != null && v !== ''`.
pub fn given(v: &V) -> bool { !v.is_nullish() && !is_empty_str(v) }
/// JS `Object.assign({}, o)` — 제 열쇠를 차례대로 얕게 베낀 새 객체(객체가 아니면 빈 객체 · 글이면 글자마다 열쇠).
/// **알려진 차이**: `JSON.parse`는 `"__proto__"`를 제 열쇠로 만들지만 웹의 `Object.assign`은 그 열쇠를 `[[Set]]`으로 써서 새 객체의 프로토타입을 바꾸고
/// 열쇠는 잃는다(값이 객체면 그 객체의 이름들이 물려받은 것으로 보이고, 아니면 무시). 여기서는 보통 열쇠로 베낀다 — `__proto__`를 칸 이름으로 적은 자료는
/// 웹에서도 뜻이 없다(계획 '알게 된 것'에 적음).
pub fn assign_copy(v: &V) -> js::Obj {
    let out = js::Obj::new();
    match v {
        V::Obj(o) => { for (k, x) in o.entries() { out.set(&k, x); } }
        V::Arr(a) => { for (i, x) in a.to_vec().into_iter().enumerate() { out.set(&(i as f64), x); } }
        V::Str(s) => { for i in 0..s.len16() { if let Some(c) = s.at16(i as f64) { out.set(&(i as f64), c); } } }
        _ => {}
    }
    out
}
/// JS `Object.assign(target, src)`(src가 null · undefined면 건너뜀).
pub fn assign_into(target: &js::Obj, src: &V) {
    if src.is_nullish() { return; }
    for (k, x) in assign_copy(src).entries() { target.set(&k, x); }
}
/// 글 조각을 잇는다(템플릿 글 `${…}`의 수는 `js::num_str`로 — 부르는 쪽이 넣는다).
pub fn cat(parts: &[&Str]) -> Str {
    let all: Vec<Str> = parts.iter().map(|s| (*s).clone()).collect();
    Str::join(&all, "")
}
/// 배열 값(V::Arr)을 새로 만든다.
pub fn arr_of(items: Vec<V>) -> V { V::Arr(js::Arr::new(items)) }
/// JS `Array.isArray(v) ? v : v == null || v === '' ? [] : [v]` — 목록(하나만 적은 것도 · 비면 빈 목록).
pub fn listed(v: &V) -> Vec<V> {
    match v { V::Arr(a) => a.to_vec(), x if x.is_nullish() || is_empty_str(x) => Vec::new(), x => vec![x.clone()] }
}
/// JS `s.replace(/[…]/g, '')`(지울 글자 몇 개 — 코드 단위로 견줌).
pub fn drop_units(s: &Str, units: &[u16]) -> Str {
    let kept: Vec<u16> = s.units().filter(|c| !units.contains(c)).collect();
    Str::from_units(&kept)
}
/// JS `s.split(/\r?\n/)` — `\n`마다 자르고, 자른 자리 바로 앞의 `\r` 하나를 함께 뗀다(외톨이 `\r`은 그대로).
pub fn split_crlf(s: &Str) -> Vec<Str> {
    let units = s.to_units();
    let mut out = Vec::new();
    let mut from = 0;
    for (i, &u) in units.iter().enumerate() {
        if u == 0x0A {
            let end = if i > from && units[i - 1] == 0x0D { i - 1 } else { i };
            out.push(Str::from_units(&units[from..end]));
            from = i + 1;
        }
    }
    out.push(Str::from_units(&units[from..]));
    out
}
/// JS `s.split(/[…]/)`(가름 글자 몇 개 — 코드 단위로 견줌): 가름마다 자르고 빈 조각도 남긴다(빈 글은 `['']`).
pub fn split_units(s: &Str, seps: &[u16]) -> Vec<Str> {
    let units = s.to_units();
    let mut out = Vec::new();
    let mut from = 0;
    for (i, u) in units.iter().enumerate() {
        if seps.contains(u) {
            out.push(Str::from_units(&units[from..i]));
            from = i + 1;
        }
    }
    out.push(Str::from_units(&units[from..]));
    out
}

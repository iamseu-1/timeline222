//! `js/calendar.js`(`HT.cal`)의 날짜 읽기 몫 — 한 벌 P3 과제 5a. 줄 그대로 옮긴다(JS 함수 하나 = Rust 함수 하나 · 같은 차례).
//!
//! 옮긴 원본: `js/calendar.js` — SHA-256 앞 12자 `96df71e8ba39`(저장소의 LF 바이트)
//! - 14 ~ 28줄 달력 목록(`CALENDARS` · `CAL` · `WORDS`)
//! - 31 ~ 81줄 날 번호 ↔ 율리우스력 · 그레고리력(`jdnG` · `jdnJ` · `fromG` · `fromJ` · `jdnCivil` · `fromCivil` · `yearStart` · `toAstro` · `fromAstro` · `cal.jdnCivil` · `cal.civilOf` · `monthLen`)
//! - 83 ~ 91줄 `EPS` · `cal.tOf`
//! - 124 ~ 190줄 국제화 달력(`fmtOf` · `intlParts` · `keyOf` · `intlJdn`) — **ICU 대신 달력 표**(아래)
//! - 212 ~ 407줄 날짜 글 읽기(`pad` · `numOrNull` · 정규식들 · `bad` · `cal.parse` · `parseText` · `build`)
//! - 431 ~ 438줄 `cal.centurySpan`
//! - 93 ~ 121줄 `cal.at` · `cal.dayEnd` · `cal.yearDays` · 192 ~ 204줄 `cal.partsIn` · 560 ~ 575줄 `cal.precSpan` — 과제 6(칸의 경계 `HT.cellBounds`가 씀 · 파일 끝 절)
//!
//! 옮기지 않은 것: 쓰기(`formatT` · `describe` …) · 눈금 같은 화면 몫(뒤 과제가 쓸 때 옮긴다). `parseMemo`(같은 글의 답을 기억하는 빠르기 몫 — 답이 같으므로 두지 않음).
//!
//! **국제화 달력(음력 · 이슬람력 · 페르시아력)**: 웹은 브라우저 · Node의 ICU(`Intl.DateTimeFormat`)로 날 번호 ↔ 그 달력의 날짜를 바꾼다. 엔진에는 ICU가 없으므로
//! 꾸러미가 같은 ICU로 미리 뜬 **달의 시작 표**(`prototype/scripts/export/calendar.mjs`의 `buildTable` 꼴 · `calendar-cache.json`의 `tables`)를 [`Tables`]로 받아
//! `intlParts`를 표에서 찾는다(계획 정한 것 #7). 표가 없으면 그 날짜는 '이 환경에서는 바꿀 수 없습니다'(웹에서 ICU가 그 달력을 모를 때와 같은 글)로 읽히지만
//! 그대로 두면 정답지와 조용히 갈리므로 — 표 범위 밖의 날이 필요하면 [`Tables::missed`]에, 그 달력의 표가 아예 없으면 [`Tables::absent`]에 남겨 부르는 쪽(`lay::normalized`)이 거절한다
//! (정한 것 #7 '표 범위 밖이면 거절' — 표가 없을 때도 같다: 정답지 Node에는 ICU가 늘 있으므로 '바꿀 수 없음'으로 읽으면 조용히 갈린다).
//! 표지에는 처음 걸린 달력의 이름을 남겨 거절 글이 '음력 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다' · '음력 표 범위 밖 — …'처럼 그 달력을 말한다
//! (과제 5b — 표 묶음은 있는데 그 달력만 없을 때도). 예전 글의 '컴퓨터에서 다시 짓기'는 가리킬 길이 없어 쉬운 까닭으로 바꿨다(끝 문서 과제 — 판정 R56 ·
//! 넣고 빼기는 이 글을 `packs::layout_refusal`이 `range` · `calendar`로 가르므로 '… 표 범위 밖' · '… 표 없음' 꼴은 그대로 둔다).
//!
//! 정규식(옮기는 규칙): JS `\s`는 [`WS`](JS 빈칸 목록) · `\d`는 `[0-9]` · `.`은 `[^\n\r\u{2028}\u{2029}]` · `i` 깃발은 ASCII 글자만 접히는 곳에서만 `(?i)`
//! (여기 글자들 — B · C · E · A · D · T · M · P — 은 유니코드 접기가 ASCII 접기와 같다. k · s는 다르므로 그런 곳은 손으로). 뒤참조(`RE_NUM`의 `\2`) · 앞보기(`RE_BC_MID` ·
//! 쉼표 지우기)는 손으로 — 아래 그 함수의 주석.
use crate::lay::js::{self, Str, V};
use regex::Regex;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::OnceLock;

// ── 달력 목록(14 ~ 28줄) ──

/// 달력 하나 — words: 날짜 글 앞(또는 뒤 괄호)에 붙여 달력을 고르는 말(긴 것부터 맞춤).
#[derive(Debug)]
pub struct Calendar {
    pub id: &'static str,
    pub name: &'static str,
    pub prefix: &'static str,
    pub words: &'static [&'static str],
    pub intl: Option<&'static str>,
    pub lunar: bool,
    pub era: Option<&'static str>,
}

/// `cal.CALENDARS`(`long` — 폼의 긴 이름 — 은 읽기에 쓰지 않아 뺐다).
pub const CALENDARS: [Calendar; 8] = [
    Calendar { id: "civil", name: "양력", prefix: "", words: &["양력", "서력"], intl: None, lunar: false, era: None },
    Calendar { id: "gregorian", name: "그레고리력", prefix: "그레고리력 ", words: &["그레고리력", "그레고리오력", "신력"], intl: None, lunar: false, era: None },
    Calendar { id: "julian", name: "율리우스력", prefix: "율리우스력 ", words: &["율리우스력", "구력"], intl: None, lunar: false, era: None },
    Calendar { id: "dangi", name: "음력", prefix: "음력 ", words: &["한국 음력", "음력", "陰曆", "음"], intl: Some("dangi"), lunar: true, era: None },
    Calendar { id: "chinese", name: "중국 음력", prefix: "중국 음력 ", words: &["중국 음력", "농력", "農曆", "农历"], intl: Some("chinese"), lunar: true, era: None },
    Calendar { id: "islamic", name: "이슬람력", prefix: "이슬람력 ", words: &["이슬람력", "히즈라력", "히즈라", "회교력", "AH"], intl: Some("islamic-civil"), lunar: false, era: Some("AH") },
    Calendar { id: "umalqura", name: "이슬람력(움 알쿠라)", prefix: "움알쿠라 ", words: &["움 알쿠라", "움알쿠라"], intl: Some("islamic-umalqura"), lunar: false, era: Some("AH") },
    Calendar { id: "persian", name: "페르시아력", prefix: "페르시아력 ", words: &["페르시아력", "이란력", "태양 히즈라력"], intl: Some("persian"), lunar: false, era: Some("AP") },
];

/// `CAL.get(id)`.
pub fn cal_of(id: &str) -> Option<&'static Calendar> { CALENDARS.iter().find(|c| c.id == id) }

/// `WORDS`: 모든 달력의 말을 UTF-16 길이가 긴 것부터(같으면 적힌 차례 — 안정 정렬).
fn words() -> &'static [(&'static str, &'static Calendar)] {
    static W: OnceLock<Vec<(&'static str, &'static Calendar)>> = OnceLock::new();
    W.get_or_init(|| {
        let mut list: Vec<(&'static str, &'static Calendar)> = CALENDARS.iter().flat_map(|c| c.words.iter().map(move |w| (*w, c))).collect();
        list.sort_by(|a, b| b.0.encode_utf16().count().cmp(&a.0.encode_utf16().count()));
        list
    })
}

// ── 날 번호(JDN) ↔ 율리우스력 · 그레고리력(31 ~ 81줄 — 천문 연도: 0 = 기원전 1년) ──

fn fl(x: f64) -> f64 { x.floor() }
fn jdn_g(y: f64, m: f64, d: f64) -> f64 {
    let a = fl((14.0 - m) / 12.0);
    let yy = y + 4800.0 - a;
    let mm = m + 12.0 * a - 3.0;
    d + fl((153.0 * mm + 2.0) / 5.0) + 365.0 * yy + fl(yy / 4.0) - fl(yy / 100.0) + fl(yy / 400.0) - 32045.0
}
fn jdn_j(y: f64, m: f64, d: f64) -> f64 {
    let a = fl((14.0 - m) / 12.0);
    let yy = y + 4800.0 - a;
    let mm = m + 12.0 * a - 3.0;
    d + fl((153.0 * mm + 2.0) / 5.0) + 365.0 * yy + fl(yy / 4.0) - 32083.0
}
/// 날 번호 → (해, 달, 날) — 그레고리력.
fn from_g(j: f64) -> (f64, f64, f64) {
    let a = j + 32044.0;
    let b = fl((4.0 * a + 3.0) / 146097.0);
    let c = a - fl((146097.0 * b) / 4.0);
    let d = fl((4.0 * c + 3.0) / 1461.0);
    let e = c - fl((1461.0 * d) / 4.0);
    let m = fl((5.0 * e + 2.0) / 153.0);
    (100.0 * b + d - 4800.0 + fl(m / 10.0), m + 3.0 - 12.0 * fl(m / 10.0), e - fl((153.0 * m + 2.0) / 5.0) + 1.0)
}
/// 날 번호 → (해, 달, 날) — 율리우스력.
fn from_j(j: f64) -> (f64, f64, f64) {
    let c = j + 32082.0;
    let d = fl((4.0 * c + 3.0) / 1461.0);
    let e = c - fl((1461.0 * d) / 4.0);
    let m = fl((5.0 * e + 2.0) / 153.0);
    (d - 4800.0 + fl(m / 10.0), m + 3.0 - 12.0 * fl(m / 10.0), e - fl((153.0 * m + 2.0) / 5.0) + 1.0)
}
/// 1582-10-15(그레고리력 첫날).
const GREG: f64 = 2299161.0;
fn before_greg(y: f64, m: f64, d: f64) -> bool { y < 1582.0 || (y == 1582.0 && (m < 10.0 || (m == 10.0 && d < 15.0))) }
fn jdn_civil_astro(y: f64, m: f64, d: f64) -> f64 { if before_greg(y, m, d) { jdn_j(y, m, d) } else { jdn_g(y, m, d) } }
fn from_civil(j: f64) -> (f64, f64, f64) { if j < GREG { from_j(j) } else { from_g(j) } }
/// 서력 ay년 1월 1일.
fn year_start(ay: f64) -> f64 { if ay <= 1582.0 { jdn_j(ay, 1.0, 1.0) } else { jdn_g(ay, 1.0, 1.0) } }
/// 연표 연도(기원전 = 음수, 0 없음) → 천문 연도.
pub fn to_astro(y: f64) -> f64 { if y < 0.0 { y + 1.0 } else { y } }
/// 천문 연도 → 연표 연도.
pub fn from_astro(a: f64) -> f64 { if a <= 0.0 { a - 1.0 } else { a } }
/// `cal.jdnCivil(y, m, d)` — 연표 연도의 서력 날짜 → 날 번호.
pub fn jdn_civil(y: f64, m: f64, d: f64) -> f64 { jdn_civil_astro(to_astro(y), m, d) }
/// `cal.civilOf(J)` → (연표 연도, 달, 날).
pub fn civil_of(j: f64) -> (f64, f64, f64) {
    let (y, m, d) = from_civil(j);
    (from_astro(y), m, d)
}
/// 그 달의 날수(`id` = gregorian · julian · 그 밖은 서력).
fn month_len(id: &str, ay: f64, m: f64) -> f64 {
    let f: fn(f64, f64, f64) -> f64 = if id == "gregorian" { jdn_g } else if id == "julian" { jdn_j } else { jdn_civil_astro };
    let ny = if m == 12.0 { ay + 1.0 } else { ay };
    let nm = if m == 12.0 { 1.0 } else { m + 1.0 };
    f(ny, nm, 1.0) - f(ay, m, 1.0)
}

// ── 해 좌표 ↔ 날 번호(83 ~ 91줄) ──

const EPS: f64 = 1e-9;
/// `cal.tOf(J, frac)` — 날 번호(+ 그날 안의 비율) → 해 좌표.
pub fn t_of(j: f64, frac: f64) -> f64 {
    let mut ay = from_civil(j).0;
    while j < year_start(ay) { ay -= 1.0; }
    while j >= year_start(ay + 1.0) { ay += 1.0; }
    let s = year_start(ay);
    from_astro(ay) + (j - s + frac) / (year_start(ay + 1.0) - s)
}

// ── 국제화 달력(124 ~ 190줄) — ICU 대신 달력 표 ──

/// 달력 하나의 달의 시작 표(`export/calendar.mjs`의 `buildTable` 답 — `{ intl, start, year0, months }`)를 풀어 둔 것.
#[derive(Debug, Clone)]
struct Table {
    /// 표가 덮는 날 번호 [start, end).
    start: f64,
    end: f64,
    /// 달마다 (초하루 날 번호, 해, 달, 윤달).
    months: Vec<(f64, f64, f64, bool)>,
}

/// 달력 표 하나의 원문(`export/calendar.mjs`의 `buildTable` 답 — `{ intl, start, end, year0, months }`) — 내보내기 `calendar` 모듈이 `sliceTable(wide, c, fromJ, toJ)`과
/// 같은 규칙으로 제 범위를 잘라 싣는 데 쓴다(과제 8-틀 고침 1회차 — 모듈 갈래가 이 파일을 고치지 않게). `end`는 표의 마지막 달의 다음 초하루(`buildTable`의 `end`).
#[derive(Debug, Clone)]
pub struct RawTable { pub intl: String, pub start: f64, pub end: f64, pub year0: f64, pub months: String }

/// 푼 표들(달력의 `intl` 이름 → 표 · 달력 id → 원문) — 문맥끼리 나눠 쓴다([`Tables::shared`]).
#[derive(Debug, Default)]
struct ParsedTables { by_intl: HashMap<String, Table>, raw: HashMap<String, RawTable> }

/// 보조 달력의 표들(푼 표 — 문맥끼리 나눠 씀)과 '표 범위 밖이 필요했다' · '표가 없었다'는 표지(문맥마다 · 처음 그런 달력의 이름 — 거절 글에 넣는다).
#[derive(Debug, Default)]
pub struct Tables { parsed: Rc<ParsedTables>, missed: Cell<Option<&'static str>>, absent: Cell<Option<&'static str>> }

thread_local! {
    /// 마지막으로 푼 표(바이트의 `Rc` · 푼 것) — 같은 바이트(`Rc::ptr_eq`)면 다시 풀지 않는다(판정 R61 재기: 저장소의 전체 표 약 740KB · 달 37만을
    /// DLC 넣기 한 번에 문맥마다(닿는 트랙 둘 · 배치 하나) 다시 풀었다).
    static PARSED: RefCell<Option<(Rc<Vec<u8>>, Rc<ParsedTables>)>> = const { RefCell::new(None) };
}

/// 나눠 쓰는 푼 표([`Tables::shared`]의 한 칸)를 버린다 — DLC 넣고 빼기 한 번이 끝나면 부른다(`lay::clear_caches` — 판정 R69-5: 앱의 엔진 스레드에 약 12MB가
/// 남지 않게. 앱의 넣기끼리 나눠 쓰는 최적화는 하지 않는다).
pub fn clear_shared() {
    PARSED.with(|c| *c.borrow_mut() = None);
}

/// 나눠 쓰는 푼 표가 남아 있는가(검사가 비우는 차례를 본다).
pub fn shared_held() -> bool {
    PARSED.with(|c| c.borrow().is_some())
}

impl Tables {
    /// 표 없이 — 보조 달력은 읽지 못한다.
    pub fn none() -> Tables { Tables::default() }
    /// 달력 id(`dangi` …)의 표 원문 — 없으면 None(내보내기 `calendar` 모듈은 그때 '표 없음'으로 거절한다).
    pub fn raw(&self, id: &str) -> Option<&RawTable> { self.parsed.raw.get(id) }
    /// [`from_cache`](Self::from_cache)와 같되 같은 바이트(`Rc`)를 이미 풀었으면 그 푼 표를 나눠 쓴다(표지는 새로).
    pub fn shared(bytes: &Rc<Vec<u8>>) -> crate::Result<Tables> {
        let hit = PARSED.with(|c| c.borrow().as_ref().filter(|(b, _)| Rc::ptr_eq(b, bytes)).map(|(_, p)| p.clone()));
        let parsed = match hit {
            Some(p) => p,
            None => {
                let p = Rc::new(Self::parse(bytes)?);
                PARSED.with(|c| *c.borrow_mut() = Some((bytes.clone(), p.clone())));
                p
            }
        };
        Ok(Tables { parsed, missed: Cell::new(None), absent: Cell::new(None) })
    }
    /// `calendar-cache.json`(warm-calendar.mjs) 꼴의 글 바이트 `{ v, icu, years, tables: { <달력 id>: { intl, start, year0, months, … } } }`에서 읽는다.
    /// 해는 `buildTable`과 같은 셈으로 되살린다(달 1 · 윤달 아님마다 한 살 — 음력은 0년을 건너뜀).
    pub fn from_cache(bytes: &[u8]) -> crate::Result<Tables> {
        Ok(Tables { parsed: Rc::new(Self::parse(bytes)?), missed: Cell::new(None), absent: Cell::new(None) })
    }
    fn parse(bytes: &[u8]) -> crate::Result<ParsedTables> {
        let doc: serde_json::Value = serde_json::from_slice(bytes)?;
        let tables = doc["tables"].as_object().ok_or("달력 표에 tables가 없습니다")?;
        let mut by_intl = HashMap::new();
        let mut raw = HashMap::new();
        for (id, t) in tables {
            let c = cal_of(id).ok_or_else(|| format!("달력 표의 모르는 달력: {id}"))?;
            let intl = t["intl"].as_str().ok_or_else(|| format!("달력 표 {id}에 intl이 없습니다"))?;
            if c.intl != Some(intl) { return Err(format!("달력 표 {id}의 intl({intl})이 달력 목록과 다릅니다").into()); }
            let start = t["start"].as_f64().ok_or_else(|| format!("달력 표 {id}에 start가 없습니다"))?;
            let mut year = t["year0"].as_f64().ok_or_else(|| format!("달력 표 {id}에 year0이 없습니다"))?;
            let text = t["months"].as_str().ok_or_else(|| format!("달력 표 {id}에 months가 없습니다"))?.as_bytes();
            if text.len() % 2 != 0 { return Err(format!("달력 표 {id}의 months 길이가 홀수입니다").into()); }
            let mut months = Vec::with_capacity(text.len() / 2);
            let mut j = start;
            for (k, pair) in text.chunks(2).enumerate() {
                let code = f64::from(pair[0]) - 65.0;
                let (m, leap) = (fl(code / 2.0), code % 2.0 == 1.0);
                let len = f64::from(pair[1]) - 48.0 + 29.0;
                if !(1.0..=12.0).contains(&m) || !(29.0..=31.0).contains(&len) { return Err(format!("달력 표 {id}의 {k}번째 달이 올바르지 않습니다").into()); }
                if k > 0 && m == 1.0 && !leap { year = if c.lunar && year == -1.0 { 1.0 } else { year + 1.0 }; }
                months.push((j, year, m, leap));
                j += len;
            }
            by_intl.insert(intl.to_string(), Table { start, end: j, months });
            let year0 = t["year0"].as_f64().unwrap_or(f64::NAN);
            raw.insert(id.clone(), RawTable { intl: intl.to_string(), start, end: j, year0, months: String::from_utf8_lossy(text).into_owned() });
        }
        Ok(ParsedTables { by_intl, raw })
    }
    /// 표 범위 밖의 날이 필요했는가(그 날짜는 '그런 날짜가 없습니다'로 읽혔다 — 부르는 쪽이 거절해야 한다).
    pub fn missed(&self) -> bool { self.missed.get().is_some() }
    /// 표 범위 밖의 날이 필요했던 첫 달력의 이름(`음력` …).
    pub fn missed_of(&self) -> Option<&'static str> { self.missed.get() }
    /// [`missed`](Self::missed)를 읽고 내린다(표본마다 따로 볼 때).
    pub fn take_missed(&self) -> bool { self.missed.take().is_some() }
    /// 보조 달력의 날짜를 읽어야 했는데 그 달력의 표가 없었는가(그 날짜는 '이 환경에서는 … 바꿀 수 없습니다'로 읽혔다 — 부르는 쪽이 거절해야 한다).
    pub fn absent(&self) -> bool { self.absent.get().is_some() }
    /// 표가 없었던 첫 달력의 이름(`음력` …) — 표 묶음은 있는데 그 달력만 없을 때도.
    pub fn absent_of(&self) -> Option<&'static str> { self.absent.get() }
    /// [`absent`](Self::absent)를 읽고 내린다.
    pub fn take_absent(&self) -> bool { self.absent.take().is_some() }
    /// 표지를 세운다 — 먼저 선 이름을 지킨다.
    fn mark(cell: &Cell<Option<&'static str>>, name: &'static str) { if cell.get().is_none() { cell.set(Some(name)); } }
}

/// `fmtOf(intl)` — 그 달력을 바꿀 수 있는가(웹: ICU가 그 달력을 아는가 · 여기: 그 표가 있는가). 보조 달력 날짜를 읽는 길은 모두 여기를 지난다
/// (내보내기 `calendar` 모듈이 표를 잘라 싣는 [`Tables::raw`]는 지나지 않는다).
fn fmt_of<'a>(tables: &'a Tables, intl: &str) -> Option<&'a Table> {
    aux_read();
    tables.parsed.by_intl.get(intl)
}

#[cfg(feature = "oracle")]
thread_local! {
    /// 이 스레드에서 보조 달력 날짜를 읽으려 한 횟수([`fmt_of`] — 표가 없던 때도). 골든 검사가 '보조 달력을 읽지 않은 자료'를 가르는 표지
    /// (판정 R71-1 — 그런 자료의 배치는 달력 표가 바뀌어도 `cal:` 기록 밖은 그대로여야 한다). 검사 비계라 제품에서는 세지 않는다(판정 R69-7과 같은 까닭).
    static AUX_READS: Cell<u64> = const { Cell::new(0) };
}
#[cfg(feature = "oracle")]
#[inline]
fn aux_read() { AUX_READS.with(|c| c.set(c.get() + 1)); }
#[cfg(not(feature = "oracle"))]
#[inline(always)]
fn aux_read() {}
/// 이 스레드에서 보조 달력 날짜를 읽으려 한 횟수를 꺼내고 0으로 되돌린다(`oracle` 기능 — 검사만).
#[cfg(feature = "oracle")]
pub fn take_aux_reads() -> u64 { AUX_READS.with(|c| c.replace(0)) }

/// 그 달력의 날짜 하나.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Parts { pub y: f64, pub m: f64, pub leap: bool, pub d: f64 }

/// `intlParts(intl, J)` — 날 번호 → 그 달력의 { y, m, leap, d }(음력의 y는 그 해가 시작한 서력 연도, 연표 연도로).
/// 표가 없으면 None(`fmtOf`가 null) · 표 범위 밖이면 None이고 `missed`를 세운다.
fn intl_parts(tables: &Tables, intl: &str, j: f64) -> Option<Parts> {
    let t = fmt_of(tables, intl)?;
    if !(j >= t.start && j < t.end) {
        let name = CALENDARS.iter().find(|c| c.intl == Some(intl)).map_or("달력", |c| c.name); // 달력마다 intl이 다르다
        Tables::mark(&tables.missed, name);
        return None;
    }
    let at = t.months.partition_point(|row| row.0 <= j) - 1;
    let (s, y, m, leap) = t.months[at];
    Some(Parts { y, m, leap, d: j - s + 1.0 })
}
fn key_of(y: f64, m: f64, leap: bool, d: f64) -> f64 { y * 10000.0 + (m * 2.0 + if leap { 1.0 } else { 0.0 }) * 100.0 + d }
/// `intlJdn(c, y, m, leap, d)` — 그 달력의 날짜 → 날 번호. 없는 날(윤달이 없는 해의 윤달, 30일이 없는 달 …)이면 None.
/// 표 범위 밖의 날을 물어야 하면 None(웹은 ICU가 답한다 — `missed`가 서므로 부르는 쪽이 거절한다).
fn intl_jdn(tables: &Tables, c: &Calendar, y: f64, m: f64, leap: bool, d: f64) -> Option<f64> {
    let est = if c.lunar { jdn_g(to_astro(y), 2.0, 1.0) + js::round((m - 1.0 + if leap { 1.0 } else { 0.0 }) * 29.53) + d - 1.0 }
        else if c.era == Some("AH") { 1948440.0 + fl((y - 1.0) * 354.36667) + fl((m - 1.0) * 29.5) + d - 1.0 }
        else { jdn_g(y + 621.0, 3.0, 21.0) + js::round((m - 1.0) * 30.44) + d - 1.0 };
    let intl = c.intl?;
    let target = key_of(y, m, leap, d);
    let mut lo = est - 800.0;
    let mut hi = est + 800.0;
    let k = |j: f64| intl_parts(tables, intl, j).map(|p| key_of(p.y, p.m, p.leap, p.d));
    if k(lo)? > target || k(hi)? < target { return None; }
    while lo < hi {
        let mid = fl((lo + hi) / 2.0);
        if k(mid)? < target { lo = mid + 1.0; } else { hi = mid; }
    }
    if k(lo)? == target { Some(lo) } else { None }
}

// ── 날짜 글 읽기(212 ~ 407줄) ──

/// `pad(n)` — `String(n).padStart(2, '0')`.
fn pad(n: f64) -> String {
    let s = js::num_str(n);
    if s.encode_utf16().count() < 2 { format!("0{s}") } else { s }
}

/// JS 정규식의 `\s` — JS 빈칸(`js::is_space`와 같은 목록).
pub const WS: &str = r"[\t\n\x0B\x0C\r \xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]";
/// JS 정규식의 `.`(s 깃발 없음) — 줄 끝 넷을 뺀 글자.
pub const DOT: &str = r"[^\n\r\x{2028}\x{2029}]";

/// 정규식을 한 번만 짓는다(`\s` · `.`은 JS 뜻으로 바꿔 넣는다 — 패턴에는 `{WS}` · `{DOT}`으로 적음).
fn re(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(&pattern.replace("{WS}", WS).replace("{DOT}", DOT)).expect("달력 정규식"))
}
/// `TIME`(시각 꼬리) — `(?:\s*(?:T|\s)\s*(?:(오전|오후|AM|PM)\s*)?(\d{1,2})(?::(\d{2})|\s*시(?:\s*(\d{1,2})\s*분)?)(?:\s*(AM|PM))?)?` (`i`).
const TIME: &str = r"(?:{WS}*(?:T|{WS}){WS}*(?:(오전|오후|AM|PM){WS}*)?([0-9]{1,2})(?::([0-9]{2})|{WS}*시(?:{WS}*([0-9]{1,2}){WS}*분)?)(?:{WS}*(AM|PM))?)?";
/// `BC_WORD` · `AD_WORD`.
const BC_WORD: &str = r"(?:기원전|서기전|B\.?{WS}?C\.?(?:{WS}?E\.?)?)";
const AD_WORD: &str = r"(?:기원후|서기|A\.?{WS}?D\.?|C\.?{WS}?E\.?)";

/// `RE_KO` — `^(\d+)\s*년(?:\s*(윤)?\s*(\d{1,2})\s*월(?:\s*(\d{1,2})\s*일)?)?${TIME}$` (`i`).
fn re_ko() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, &format!(r"(?i)^([0-9]+){{WS}}*년(?:{{WS}}*(윤)?{{WS}}*([0-9]{{1,2}}){{WS}}*월(?:{{WS}}*([0-9]{{1,2}}){{WS}}*일)?)?{TIME}$"))
}
/// `RE_NUM` — `^(\d+)(?:\s*([-./])\s*(윤)?(\d{1,2})(?:\s*\2\s*(\d{1,2}))?\.?)?${TIME}$` (`i`).
/// 뒤참조 `\2`는 regex에 없으므로 가름표마다 하나씩 짓는다(`sep` = `-` · `.` · `/`): 가름표 자리에 그 글자를 넣고 `\2` 자리에도 같은 글자를 넣는다.
/// 어느 것을 쓸지는 [`re_num_for`] — 원래 정규식에서 가름표는 앞 숫자 뒤(빈칸 건너) 그 자리의 글자 하나로 정해지므로 뜻이 같다.
fn re_num(sep: char) -> &'static Regex {
    static DASH: OnceLock<Regex> = OnceLock::new();
    static DOT_: OnceLock<Regex> = OnceLock::new();
    static SLASH: OnceLock<Regex> = OnceLock::new();
    let (cell, lit) = match sep { '.' => (&DOT_, r"\."), '/' => (&SLASH, "/"), _ => (&DASH, "-") };
    re(cell, &format!(r"(?i)^([0-9]+)(?:{{WS}}*({lit}){{WS}}*(윤)?([0-9]{{1,2}})(?:{{WS}}*{lit}{{WS}}*([0-9]{{1,2}}))?\.?)?{TIME}$"))
}
/// `RE_NUM.exec(s)`: 앞 숫자(`(\d+)`는 늘 숫자를 모두 먹는다 — 덜 먹으면 다음 글자가 숫자라 가름표도 시각도 `$`도 맞지 않음) 뒤 JS 빈칸을 건넌 글자가
/// `-` · `.` · `/`면 그 가름표의 정규식, 아니면 가름표 덩이가 맞을 수 없으니 아무것(`-`의 것)이나.
fn re_num_for(s: &str) -> &'static Regex {
    let rest = s.trim_start_matches(|c: char| c.is_ascii_digit());
    match rest.trim_start_matches(js::is_space).chars().next() { Some(c @ ('-' | '.' | '/')) => re_num(c), _ => re_num('-') }
}
/// `RE_CENT` — `^(\d+)\s*세기(?:\s*(초반|초엽|초|전반|중반|중엽|중|후반|말엽|말))?$`.
fn re_cent() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, r"^([0-9]+){WS}*세기(?:{WS}*(초반|초엽|초|전반|중반|중엽|중|후반|말엽|말))?$")
}
/// `CENT_PART`.
fn cent_part(word: &str) -> &'static str {
    match word { "초" | "초반" | "초엽" => "a", "중" | "중반" | "중엽" => "b", "말" | "말엽" => "c", "전반" => "h1", "후반" => "h2", _ => "" }
}
/// `CENT_WORD`.
fn cent_word(part: &str) -> &'static str {
    match part { "a" => "초", "b" => "중반", "c" => "말", "h1" => "전반", "h2" => "후반", _ => "" }
}
/// `RE_BC_HEAD` — `^${BC_WORD}\s*` (`i`).
fn re_bc_head() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, &format!("(?i)^{BC_WORD}{{WS}}*"))
}
/// `RE_BC_TAIL` — `\s*${BC_WORD}$` (`i`).
fn re_bc_tail() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, &format!("(?i){{WS}}*{BC_WORD}$"))
}
/// `RE_AD_HEAD` — `^${AD_WORD}\s*` (`i`).
fn re_ad_head() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, &format!("(?i)^{AD_WORD}{{WS}}*"))
}
/// `RE_BC_MID` — `^(\d+)\s*(?:년\s*)?${BC_WORD}\s*(?=[-./\s]|$)` (`i`). 앞보기 `(?=…)`는 regex에 없어 그 자리를 **먹는** 덩이 `([-./\s]|$)`로 바꿨다:
/// 패턴 맨 끝의 앞보기라 먹든 안 먹든 맞는 자리(되돌아가 고르는 차례)가 같고, 바꿀 때는 먹은 그 글자(2번 덩이)를 되붙인다([`bc_mid`]).
fn re_bc_mid() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, &format!(r"(?i)^([0-9]+){{WS}}*(?:년{{WS}}*)?{BC_WORD}{{WS}}*([-./]|{{WS}}|$)"))
}
/// 맞으면 `s.replace(RE_BC_MID, (m0, y) => `${y}`)`의 답.
fn bc_mid(s: &str) -> Option<String> {
    let m = re_bc_mid().captures(s)?;
    let all = m.get(0).unwrap();
    let kept = m.get(2).map_or("", |g| g.as_str()); // 앞보기가 보기만 한 글자 — 원래 바꾸지 않는 자리
    Some(format!("{}{}{}", &m[1], kept, &s[all.end()..]))
}

/// `cal.parse`의 답. 실패면 `ok = false` · `error`(나머지 칸은 쓰지 않음).
#[derive(Debug, Clone)]
pub struct Parsed {
    pub ok: bool,
    pub error: Str,
    pub t: f64,
    /// 'y' · 'm' · 'd' · 'h' · 'min' · 'x'(소수 좌표) · 'c' · 'c2' · 'c3'(세기).
    pub prec: &'static str,
    pub cal: &'static str,
    pub y: f64,
    pub m: Option<f64>,
    pub leap: bool,
    pub d: Option<f64>,
    pub h: Option<f64>,
    pub mi: Option<f64>,
    pub j: Option<f64>,
    /// 표준 날짜 글.
    pub text: Str,
    /// 연도만 적은 서력이 아님.
    pub fine: bool,
    /// 세기: 정밀도 구간 [첫해, 마지막 해 다음 해) · 마지막 해.
    pub span: Option<(f64, f64)>,
    pub last: Option<f64>,
}

/// `bad(error)`.
fn bad(error: impl Into<Str>) -> Parsed {
    Parsed { ok: false, error: error.into(), t: f64::NAN, prec: "", cal: "", y: f64::NAN, m: None, leap: false, d: None, h: None, mi: None, j: None, text: Str::default(), fine: false, span: None, last: None }
}

/// `cal.parse(input)` — 날짜 글(또는 수)을 읽는다. 빈 값은 None. `tables` = 보조 달력의 표.
pub fn parse(tables: &Tables, input: &V) -> Option<Parsed> {
    if input.is_nullish() { return None; }
    if let V::Num(x) = input {
        let x = *x;
        if !x.is_finite() { return Some(bad("숫자가 아닙니다.")); }
        let text = Str::from(js::num_str(x));
        if x == x.trunc() { return Some(Parsed { ok: true, t: x, prec: "y", cal: "civil", y: x, text, fine: false, ..bad("") }); }
        return Some(Parsed { ok: true, t: x, prec: "x", cal: "civil", y: fl(x + EPS), text, fine: true, ..bad("") }); // 소수 좌표 그대로
    }
    let src = js::to_str(input).trim();
    if src.is_empty() { return None; }
    Some(parse_text(tables, &src.as_str()))
}

/// JS `toLowerCase()`(유니코드 기본 소문자 바꾸기 — 그리스 끝 시그마 포함).
fn lower(s: &str) -> String { s.to_lowercase() }
/// UTF-16 길이.
fn len16(s: &str) -> usize { s.encode_utf16().count() }
/// JS `s.slice(a, b)`(UTF-16 자리) — 쌍이 갈리면 U+FFFD(정규식에 넘기는 글이라 외톨이를 둘 수 없음).
fn slice16(s: &str, a: f64, b: f64) -> String { Str::from(s).slice16(a, b).as_str().into_owned() }
/// JS `s.trim()`.
fn trim(s: &str) -> String { s.trim_matches(js::is_space).to_string() }

/// `parseText(src)` — 손질한 날짜 글을 읽는다.
fn parse_text(tables: &Tables, src: &str) -> Parsed {
    // .replace(/[０-９]/g, …) — 전각 숫자를 ASCII로
    let s1: String = src.chars().map(|c| if ('\u{FF10}'..='\u{FF19}').contains(&c) { char::from_u32(c as u32 - 0xFEE0).unwrap() } else { c }).collect();
    // .replace(/(\d),(?=\d{3}(?!\d))/g, '$1') — 앞보기라 손으로: 숫자 · 쉼표 · 숫자 셋 · (숫자가 아님)이면 쉼표를 뺀다. 맞은 뒤에는 쉼표 다음부터 다시 찾는다.
    let cs: Vec<char> = s1.chars().collect();
    let mut s2 = String::with_capacity(s1.len());
    let mut i = 0;
    while i < cs.len() {
        let digit = |k: usize| cs.get(k).is_some_and(char::is_ascii_digit);
        if digit(i) && cs.get(i + 1) == Some(&',') && digit(i + 2) && digit(i + 3) && digit(i + 4) && !digit(i + 5) {
            s2.push(cs[i]);
            i += 2;
        } else {
            s2.push(cs[i]);
            i += 1;
        }
    }
    // .replace(/\s+/g, ' ').trim()
    static SPACES: OnceLock<Regex> = OnceLock::new();
    let mut s = trim(&re(&SPACES, "{WS}+").replace_all(&s2, " "));
    // 기원전 말이 달력 말보다 앞에 오면("기원전 음력 100-01-01") 달력 말 뒤로 옮긴다
    static LEAD: OnceLock<Regex> = OnceLock::new();
    let lead = re(&LEAD, &format!("(?i)^({BC_WORD}){{WS}}*({{DOT}}+)$")).captures(&s).map(|m| (m[1].to_string(), m[2].to_string()));
    if let Some((bc_word, rest)) = lead {
        let low = lower(&rest);
        if words().iter().any(|(w, _)| low.starts_with(&lower(w)) && !w.starts_with(|c: char| c.is_ascii_digit())) {
            let (w, _) = words().iter().find(|(w, _)| low.starts_with(&lower(w))).unwrap();
            let n = len16(w) as f64;
            s = format!("{} {} {}", slice16(&rest, 0.0, n), bc_word, trim(&slice16(&rest, n, f64::INFINITY)));
        }
    }
    // 달력: 앞말("음력 …") 또는 뒤 괄호("… (음력)")
    let mut cal_id = "civil";
    static TAIL: OnceLock<Regex> = OnceLock::new();
    let tail = re(&TAIL, r"{WS}*[(（]{WS}*([^)）]+?){WS}*[)）]{WS}*$").captures(&s).map(|m| (m.get(0).unwrap().start(), m[1].to_string()));
    if let Some((index, word)) = tail {
        if let Some((_, c)) = words().iter().find(|(w, _)| lower(w) == lower(&word)) {
            cal_id = c.id;
            s = trim(&s[..index]);
        }
    }
    if cal_id == "civil" {
        let low = lower(&s);
        static HEAD_OK: OnceLock<Regex> = OnceLock::new();
        static HEAD_CUT: OnceLock<Regex> = OnceLock::new();
        static ENDS_WS: OnceLock<Regex> = OnceLock::new();
        for (w, c) in words() {
            let lw = lower(w);
            let n = len16(w) as f64;
            // 앞말: 뒤에 숫자 · 기원전 같은 말이 와야 달력으로 본다("음" 한 글자도 "음 1592.4.13"처럼)
            if len16(&low) > len16(&lw) && low.starts_with(&lw) && re(&HEAD_OK, "^{WS}*[:：]?{WS}*[-0-9기서BbAaCc]").is_match(&slice16(&s, n, f64::INFINITY)) {
                cal_id = c.id;
                s = re(&HEAD_CUT, "^{WS}*[:：]?{WS}*").replacen(&slice16(&s, n, f64::INFINITY), 1, "").into_owned();
                break;
            }
            // 뒷말: "1592-04-13 음력"
            if len16(&low) > len16(&lw) && low.ends_with(&lw) && re(&ENDS_WS, "{WS}$").is_match(&slice16(&s, 0.0, -n)) {
                cal_id = c.id;
                s = trim(&slice16(&s, 0.0, -n));
                break;
            }
        }
    }
    // 어림("경" · "무렵" · "c.")
    static APPROX_TAIL: OnceLock<Regex> = OnceLock::new();
    static APPROX_HEAD: OnceLock<Regex> = OnceLock::new();
    let cut = re(&APPROX_TAIL, "{WS}*(?:경|무렵|께|쯤)$").replacen(&s, 1, "").into_owned();
    s = trim(&re(&APPROX_HEAD, r"(?i)^(?:c\.|ca\.|약){WS}*").replacen(&cut, 1, ""));
    // 기원전 · 기원후
    let mut bc = false;
    if re_bc_head().is_match(&s) {
        bc = true;
        s = re_bc_head().replacen(&s, 1, "").into_owned();
    } else if re_bc_tail().is_match(&s) {
        bc = true;
        s = re_bc_tail().replacen(&s, 1, "").into_owned();
    } else if let Some(out) = bc_mid(&s) {
        bc = true;
        s = out;
    } else if re_ad_head().is_match(&s) {
        s = re_ad_head().replacen(&s, 1, "").into_owned();
    }
    if let Some(rest) = s.strip_prefix('-') {
        bc = true;
        s = trim(rest);
    }
    // 세기: "3세기 중반" → 구간의 첫해가 자리, span이 정밀도 구간, text는 적은 대로
    if let Some(cm) = re_cent().captures(&s) {
        if cal_id != "civil" { return bad("세기로 적은 연대는 서력으로만 읽습니다."); }
        let n: f64 = cm[1].parse().unwrap_or(f64::NAN);
        if !(n >= 1.0) { return bad("세기는 1부터입니다."); }
        let part = cm.get(2).map_or("", |g| cent_part(g.as_str()));
        let span = century_span(n, part, bc);
        let last = if span.1 == 0.0 { -1.0 } else { span.1 - 1.0 };
        let text = format!("{}{}세기{}", if bc { "기원전 " } else { "" }, js::num_str(n), if part.is_empty() { String::new() } else { format!(" {}", cent_word(part)) });
        let prec = if part.is_empty() { "c" } else if part == "h1" || part == "h2" { "c2" } else { "c3" };
        return Parsed { ok: true, t: span.0, prec, cal: "civil", y: span.0, m: None, leap: false, d: None, h: None, mi: None, j: None, text: Str::from(text), fine: true, span: Some(span), last: Some(last), error: Str::default() };
    }
    // RE_KO · RE_NUM — 덩이: 해 · 윤 · 달 · 날 · 오전오후 · 시 · 분(콜론) · 분(시 분) · 오전오후(뒤)
    let grab = |m: &regex::Captures<'_>, k: usize| m.get(k).map(|g| g.as_str().to_string());
    let (y, leap, mo, d, ap, h, mi, ap2);
    if let Some(m) = re_ko().captures(&s) {
        y = grab(&m, 1);
        leap = grab(&m, 2);
        mo = grab(&m, 3);
        d = grab(&m, 4);
        ap = grab(&m, 5);
        h = grab(&m, 6);
        mi = grab(&m, 7).or_else(|| grab(&m, 8));
        ap2 = grab(&m, 9);
    } else if let Some(m) = re_num_for(&s).captures(&s) {
        y = grab(&m, 1);
        leap = grab(&m, 3);
        mo = grab(&m, 4);
        d = grab(&m, 5);
        ap = grab(&m, 6);
        h = grab(&m, 7);
        mi = grab(&m, 8).or_else(|| grab(&m, 9));
        ap2 = grab(&m, 10);
    } else {
        return bad("날짜를 읽을 수 없습니다. 예) 1592 · 1592-05-23 · 1592년 5월 23일 14시 · 음력 1592-04-13");
    }
    // numOrNull: 빈 값이면 null · 아니면 Number(글)
    let num_or_null = |v: &Option<String>| v.as_ref().filter(|t| !t.is_empty()).map(|t| t.parse::<f64>().unwrap_or(f64::NAN));
    let mut y: f64 = y.as_deref().unwrap_or("").parse().unwrap_or(f64::NAN);
    let mo = num_or_null(&mo);
    let d = num_or_null(&d);
    let mut h = num_or_null(&h);
    let mi = num_or_null(&mi);
    let leap = leap.is_some_and(|t| !t.is_empty());
    let half = ap.filter(|t| !t.is_empty()).or(ap2.filter(|t| !t.is_empty())).unwrap_or_default().to_uppercase();
    if let Some(hv) = h { if (half == "오후" || half == "PM") && hv < 12.0 { h = Some(hv + 12.0); } }
    if let Some(hv) = h { if (half == "오전" || half == "AM") && hv == 12.0 { h = Some(0.0); } }
    if !y.is_finite() { return bad("연도를 읽을 수 없습니다."); }
    if bc { y = -y; }
    if y == 0.0 && (mo.is_some() || cal_id != "civil") { return bad("0년은 없습니다. 기원전 1년 다음 해가 1년입니다."); }
    if let Some(m) = mo { if m < 1.0 || m > 12.0 { return bad("달은 1~12 사이여야 합니다."); } }
    if let Some(dv) = d { if dv < 1.0 || dv > 31.0 { return bad("날은 1~31 사이여야 합니다."); } }
    if let Some(hv) = h { if hv < 0.0 || hv > 23.0 { return bad("시는 0~23 사이여야 합니다."); } }
    if let Some(m) = mi { if m < 0.0 || m > 59.0 { return bad("분은 0~59 사이여야 합니다."); } }
    if h.is_some() && d.is_none() { return bad("시각을 적으려면 날짜(일)까지 적어 주세요."); }
    if leap && !cal_of(cal_id).is_some_and(|c| c.lunar) { return bad("윤달은 음력에만 있습니다."); }
    build(tables, cal_id, y, mo, leap, d, h, mi)
}

/// `build({ cal, y, m, leap, d, h, mi })` — 부분(달력 · 연 · 월 · 윤달 · 일 · 시 · 분) → 읽은 결과. 폼에서도 쓴다.
#[allow(clippy::too_many_arguments)]
pub fn build(tables: &Tables, cal_id: &str, y: f64, m: Option<f64>, leap: bool, d: Option<f64>, h: Option<f64>, mi: Option<f64>) -> Parsed {
    let Some(c) = cal_of(cal_id) else { return bad(format!("알 수 없는 달력입니다: {cal_id}")) };
    if !(y.is_finite() && y == y.trunc()) { return bad("연도는 정수여야 합니다."); }
    let d = if m.is_none() { None } else { d };
    let (h, mi) = if d.is_none() { (None, None) } else { (h, mi) };
    let mi = if h.is_none() { None } else { mi };
    let prec = if h.is_some() { if mi.is_some_and(|x| x != 0.0 && !x.is_nan()) { "min" } else { "h" } } else if d.is_some() { "d" } else if m.is_some() { "m" } else { "y" };
    if c.id == "civil" && prec == "y" {
        let text = if y < 0.0 { format!("기원전 {}", js::num_str(-y)) } else { js::num_str(y) };
        return Parsed { ok: true, t: y, prec, cal: c.id, y, m: None, leap: false, d: None, h: None, mi: None, j: None, text: Str::from(text), fine: false, span: None, last: None, error: Str::default() };
    }
    let j;
    if let Some(intl) = c.intl {
        if fmt_of(tables, intl).is_none() {
            Tables::mark(&tables.absent, c.name); // 웹(ICU)은 바꿀 수 있다 — 부르는 쪽이 거절하도록 남긴다(달력 이름과 함께)
            return bad(format!("이 환경에서는 {}을(를) 바꿀 수 없습니다.", c.name));
        }
        if c.era.is_some() && y < 1.0 { return bad(format!("{}은(는) 1년부터 적을 수 있습니다.", c.name)); }
        match intl_jdn(tables, c, y, or1(m), leap, or1(d)) {
            Some(x) => j = x,
            None => {
                if leap { return bad(format!("{} {}년에는 윤{}월이 없습니다.", c.name, if y < 0.0 { format!("기원전 {}", js::num_str(-y)) } else { js::num_str(y) }, js::num_str(m.unwrap_or(f64::NAN)))); }
                if let Some(dv) = d { if dv > 29.0 { return bad(format!("{} {}월에는 {}일이 없습니다.", c.name, js::num_str(m.unwrap_or(f64::NAN)), js::num_str(dv))); } }
                return bad(format!("{}에 그런 날짜가 없습니다.", c.name));
            }
        }
    } else {
        let ay = to_astro(y);
        let f: fn(f64, f64, f64) -> f64 = if c.id == "gregorian" { jdn_g } else if c.id == "julian" { jdn_j } else { jdn_civil_astro };
        let mm = m.unwrap_or(f64::NAN);
        j = f(ay, or1(m), or1(d));
        if d.is_some() {
            // 없는 날(2월 30일 등)은 다음 달로 넘어가므로 되돌려 보아 확인한다(서력 1582년 10월 5~14일은 율리우스력으로 받아들임)
            let back = if c.id == "gregorian" { from_g(j) } else if c.id == "julian" { from_j(j) } else { from_civil(j) };
            if Some(back.1) != m {
                let id = if c.id == "civil" { if before_greg(ay, mm, 1.0) { "julian" } else { "gregorian" } } else { c.id };
                let len = month_len(id, ay, mm);
                return bad(format!("{}년 {}월은 {}일까지입니다.", if y < 0.0 { format!("기원전 {}", js::num_str(-y)) } else { js::num_str(y) }, js::num_str(mm), js::num_str(len)));
            }
        }
    }
    let frac = match h { Some(hv) => (hv + mi.filter(|x| *x != 0.0 && !x.is_nan()).unwrap_or(0.0) / 60.0) / 24.0, None => 0.0 };
    let t = t_of(j, frac);
    let yt = if y < 0.0 { format!("기원전 {}", js::num_str(-y)) } else { js::num_str(y) };
    let mut text = format!("{}{}", c.prefix, yt);
    if let Some(mv) = m { text.push_str(&format!("-{}{}", if leap { "윤" } else { "" }, pad(mv))); }
    if let Some(dv) = d { text.push_str(&format!("-{}", pad(dv))); }
    if let Some(hv) = h { text.push_str(&format!(" {}:{}", pad(hv), pad(mi.filter(|x| *x != 0.0 && !x.is_nan()).unwrap_or(0.0)))); }
    Parsed { ok: true, t, prec, cal: c.id, y, m, leap, d, h, mi, j: Some(j), text: Str::from(text), fine: true, span: None, last: None, error: Str::default() }
}

/// JS `v || 1`(v는 수이거나 null).
fn or1(v: Option<f64>) -> f64 { v.filter(|x| *x != 0.0 && !x.is_nan()).unwrap_or(1.0) }

// ── 날짜 쓰기(431 ~ 438줄) ──

/// `cal.centurySpan(n, part, bc)` — 세기 구간 [첫해, 마지막 해 다음 해)(연표 연도 — 0년 없음 · 기원전 1년 다음은 0 자리).
/// part = a(초) · b(중) · c(말) · h1(전반) · h2(후반) · ''(세기 전체). 초 · 중 · 말 = 33 · 33 · 34년, 전반 · 후반 = 50년.
pub fn century_span(n: f64, part: &str, bc: bool) -> (f64, f64) {
    let first = if bc { -n * 100.0 } else { (n - 1.0) * 100.0 + 1.0 };
    let off = match part { "b" => 33.0, "c" => 66.0, "h2" => 50.0, _ => 0.0 };
    let len = if part.is_empty() { 100.0 } else if part == "h1" || part == "h2" { 50.0 } else if part == "c" { 34.0 } else { 33.0 };
    let lo = first + off;
    let last = lo + len - 1.0;
    (lo, if last == -1.0 { 0.0 } else { last + 1.0 })
}

// ── 해 좌표의 날 · 날의 끝 · 해의 날수 · 그 달력의 날짜 · 정밀도 구간(93 ~ 121줄 · 192 ~ 204줄 · 560 ~ 575줄 — 과제 6: 칸의 경계 `HT.cellBounds`가 씀) ──

/// `cal.at(t)`의 답 `{ y, ay, J, frac, m, d, len }`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct At { pub y: f64, pub ay: f64, pub j: f64, pub frac: f64, pub m: f64, pub d: f64, pub len: f64 }
/// `cal.at(t)` — 해 좌표 → 연표 연도 · 천문 연도 · 날 번호 · 그날 안의 비율 · 달 · 날 · 그해의 날수(0년 자리는 1년 1월 1일로).
pub fn at(t: f64) -> At {
    let mut y = fl(t + EPS);
    let mut pos = t - y;
    if y == 0.0 {
        y = 1.0;
        pos = 0.0;
    }
    let ay = to_astro(y);
    let s = year_start(ay);
    let len = year_start(ay + 1.0) - s;
    let day_pos = js::max(&[0.0, pos]) * len;
    let mut di = fl(day_pos + 1e-7);
    if di >= len { di = len - 1.0; }
    let frac = js::max(&[0.0, js::min(&[1.0, day_pos - di])]);
    let j = s + di;
    let (_, m, d) = from_civil(j);
    At { y, ay, j, frac, m, d, len }
}
/// `cal.dayEnd(J)` — 날 J의 끝 좌표(기원전 1년 12월 31일만은 하루 폭으로 끊는다).
pub fn day_end(j: f64) -> f64 {
    let a = t_of(j, 0.0);
    let b = t_of(j + 1.0, 0.0);
    if b - a > 0.01 { a + 1.0 / 366.0 } else { b }
}
/// `cal.yearDays(y)` — 그해의 날수(서력).
pub fn year_days(y: f64) -> f64 {
    let ay = to_astro(if y == 0.0 { 1.0 } else { y });
    year_start(ay + 1.0) - year_start(ay)
}
/// `cal.partsIn(id, J)` — 날 번호 → 그 달력의 { y, m, leap, d }. 보조 달력은 표에서(`intlParts` — 표가 없거나 범위 밖이면 None · 표지가 선다).
pub fn parts_in(tables: &Tables, id: &str, j: f64) -> Option<Parts> {
    let c = cal_of(id);
    if c.is_none() || id == "civil" {
        let (y, m, d) = civil_of(j);
        return Some(Parts { y, m, leap: false, d });
    }
    if id == "gregorian" {
        let (y, m, d) = from_g(j);
        return Some(Parts { y: from_astro(y), m, d, leap: false });
    }
    if id == "julian" {
        let (y, m, d) = from_j(j);
        return Some(Parts { y: from_astro(y), m, d, leap: false });
    }
    let c = c.expect("달력");
    match c.intl {
        Some(intl) => {
            if fmt_of(tables, intl).is_none() { Tables::mark(&tables.absent, c.name); return None; }
            intl_parts(tables, intl, j)
        }
        None => None,
    }
}
/// `cal.precSpan(r)` — 적은 정밀도가 덮는 구간 [t0, t1]: 연도만이면 그해 전체 · 달까지면 그달 · 날까지면 그날 · 시까지면 그 시간(세기는 그 구간). 분 · 소수 좌표는 None.
pub fn prec_span(tables: &Tables, r: &Parsed) -> Option<(f64, f64)> {
    if !r.ok || r.prec == "min" || r.prec == "x" { return None; }
    if let Some(span) = r.span { return Some(span); }
    if r.prec == "h" { return Some((r.t, r.t + 1.0 / 24.0 / year_days(fl(r.t + EPS)))); }
    if r.prec == "d" { return Some((r.t, day_end(r.j.unwrap_or(f64::NAN)))); }
    if r.cal == "civil" && r.prec == "y" { return Some((r.y, if r.y == -1.0 { 0.0 } else { r.y + 1.0 })); }
    let j = r.j.unwrap_or_else(|| at(r.t).j);
    if r.prec == "m" {
        let mut n = j + 27.0;
        while parts_in(tables, r.cal, n).map(|p| p.d) != Some(1.0) && n < j + 40.0 { n += 1.0; }
        return Some((r.t, t_of(n, 0.0)));
    }
    let ny = if r.y == -1.0 { 1.0 } else { r.y + 1.0 }; // 그 달력의 다음 해 첫날
    let nx = build(tables, r.cal, ny, Some(1.0), false, Some(1.0), None, None);
    Some(if nx.ok { (r.t, nx.t) } else { (r.t, r.t + 1.0) })
}

//! 타일 = (단계 L) × (통 256개) × (줄 8개)의 표시 목록. 화면은 이 이진 덩어리만 받아 그린다.
//! 사건은 통마다 '대표 최대 4개 + 나머지 개수'로 싣고, 시작 시각의 통에서 한 번만 센다 — 타일을 모두 모으면 빠짐도 중복도 없다.
//! L ≥ PRE_MIN은 넣을 때 만들어 둔 요약을 읽고, 그 아래는 이 타일의 범위만 조회해 그 자리에서 센다.
//!
//! 2판은 굳은 열 대신 **구역 표**를 둔다(계약 5절): 머리 뒤에 (구역 종류 · 항목 수 · 열 수 · 자리)의 표가 오고,
//! 구역마다 '열 × 항목'의 4바이트 배열이 이어진다. 읽는 쪽은 아는 구역 · 아는 열만 읽고 모르는 것은 건너뛴다 →
//! 묶음을 하나 옮길 때마다 열을 더해도 앞 묶음의 읽기가 깨지지 않는다.
use crate::filter::Filtered;
use crate::variant::Variants;
use crate::levels::{bucket_minutes, bucket_of, cell_lod_divisor, cell_lod_of, cell_lod_query_level, cell_min_span, host_min_span, tile_range,
    CELL_LOD_DEFAULT, CHUNK_ROWS, LEVEL_MAX, PRE_MIN, TILE_BUCKETS};
use crate::{builder::{CAT_ENTRY, REP_HEAD}, Result, Store, DAY};
use rusqlite::params;
use std::collections::{HashMap, HashSet};

pub const MAGIC: u32 = 0x3254_5448; // "HTT2"
pub const VERSION: u16 = 2;
pub const HEADER: usize = 72;
/// 구역 표 한 줄: 종류 · 항목 수 · 열 수 · 자리(4바이트 낱말).
pub const SECTION_ENTRY_WORDS: usize = 4;

/// 구역 번호. 16 이상은 items의 일반 구역(뜻은 계약 6절).
pub const SEC_BAND: u32 = 1;
pub const SEC_CELL: u32 = 2;
pub const SEC_EVENT: u32 = 3;
pub const SEC_PILL: u32 = 4;
/// 일반 구역의 첫 번호.
pub const SEC_GENERAL: u32 = 16;

/// 띠의 2판 열 수(x0 · x1 · id · color · name · row · flags · look · tag · sub).
pub const BAND_COLUMNS: u32 = 10;
/// 스키마 4(리메이크 3단계 · 계약 1-1 · 5절)에서 띠 구역 뒤에 **열 10 = `form`**(형식 4의 종류 · 관계 · 정통성 · 중요도 비트)을 더한 열 수.
/// 알약의 `cats`처럼 **form ≠ 0인 띠가 하나라도 있는 타일에만** 싣는다(아래 `band_columns`) — form 열이 없는 옛 저장소 · 모두 0인 자료의 타일은
/// 예전과 바이트까지 같다. 타일 머리의 판(`VERSION` 2)은 그대로다 — 열 수는 구역 표가 말하고, 앱 해독기는 판이 2가 아니면 모든 타일을 거절한다.
pub const BAND_FORM_COLUMNS: u32 = 11;

/// 이 타일의 띠가 몇 열인가 — form이 0이 아닌 띠가 하나라도 있으면 열하나, 아니면 2판 그대로 열.
pub fn band_columns(bands: &[Band]) -> u32 {
    if bands.iter().any(|b| b.form != 0) { BAND_FORM_COLUMNS } else { BAND_COLUMNS }
}
pub const CELL_COLUMNS: u32 = 9;
pub const EVENT_COLUMNS: u32 = 10;
/// 알약은 2판에서 네 열(x0 · x1 · count · row)이었고, 3단계에서 분류 비율 열 `cats`를 **뒤에 더했다**.
/// 옛 열의 자리는 그대로라 열 수를 보고 읽는 쪽(구역 표의 `columns`)은 고치지 않아도 예전처럼 읽는다.
/// **실을 것이 하나도 없으면 그 열을 싣지 않는다**(아래 `pill_columns`) — 분류별 수가 없는 옛 저장소의 타일은 예전과 바이트까지 같다.
pub const PILL_COLUMNS: u32 = 5;

/// 이 타일의 알약이 몇 열인가 — 분류 비율을 실은 알약이 하나라도 있으면 다섯, 아니면 2판 그대로 넷.
fn pill_columns(pills: &[Pill]) -> u32 {
    if pills.iter().any(|p| p.cats != NO_NAME) { PILL_COLUMNS } else { PILL_COLUMNS - 1 }
}
pub const ITEM_COLUMNS: u32 = 14;

/// 띠 · 칸의 표시: 타일 경계에서 잘린 쪽, 시작/끝 미정(옅은 끝).
pub const CLIP_LEFT: u32 = 1;
pub const CLIP_RIGHT: u32 = 2;
pub const FUZZY_START: u32 = 4;
pub const FUZZY_END: u32 = 8;
/// 사건의 표시: 아래 2비트는 중요도, 긴 기간 막대, 잘린 쪽, 이 타일에서 대표로 센 것.
pub const BAR: u32 = 4;
pub const EVENT_CLIP_LEFT: u32 = 8;
pub const EVENT_CLIP_RIGHT: u32 = 16;
pub const COUNTED: u32 = 32;
pub const NO_NAME: u32 = u32::MAX;

pub struct TileRequest {
    pub level: usize,
    pub x: i64,
    pub chunk: i64,
    /// 켠 자료집. 끈 자료집의 행은 읽지 않는다(다시 계산하지 않음).
    pub packs: Vec<i64>,
    /// 거르개(필터 시트의 켬끔). `None`이면 거르지 않으며, 그때의 바이트는 거르개가 없던 때와 똑같다.
    pub filter: Option<Filtered>,
    /// 켠 변형(계약 2-4절). `None`은 변형 자료가 없는 저장소이고, 켠 것이 없으면 답은 예전과 바이트까지 같다.
    pub variants: Option<Variants>,
}

impl TileRequest {
    /// 거르개 없는 요청(2판까지의 길 그대로).
    pub fn plain(level: usize, x: i64, chunk: i64, packs: Vec<i64>) -> Self {
        Self { level, x, chunk, packs, filter: None, variants: None }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Band { pub x0: f32, pub x1: f32, pub id: u32, pub color: u32, pub name: u32, pub row: u32, pub flags: u32, pub look: u32, pub tag: u32, pub sub: u32,
    /// 형식 4의 뜻(`periods.form` — 계약 1-1의 비트 · 0 = 모름). 띠 구역의 열 10이고, 그 열이 없는 타일 · 옛 저장소에서는 0이다.
    pub form: u32 }
#[derive(Debug, Clone, PartialEq)]
pub struct CellItem { pub x0: f32, pub x1: f32, pub id: u32, pub name: u32, pub row: u32, pub kind: u32, pub flags: u32, pub lane: u32, pub style: u32, pub color: u32 }
#[derive(Debug, Clone, PartialEq)]
pub struct EventItem { pub x0: f32, pub x1: f32, pub id: u32, pub name: u32, pub row: u32, pub bits: u32, pub look: u32, pub label: u32, pub rail: u32, pub band: u32 }
#[derive(Debug, Clone, PartialEq)]
pub struct Pill { pub x0: f32, pub x1: f32, pub count: u32, pub row: u32,
    /// 그 통에 든 사건의 분류별 수를 적은 글의 번호(`"3:12,7:5"` — 분류 번호 오름차순 · 이름이 없으면 `NO_NAME`).
    /// 개수 알약의 분류 비율 색줄(명세 02의 5.3)이 대표 넷이 아니라 **통 전체**의 비율을 따르게 하는 값이라,
    /// 수의 합은 알약에 적히는 `count`(대표를 뺀 나머지)보다 클 수 있다.
    pub cats: u32 }
/// 일반 구역의 항목 하나. Rust는 a~d · text2의 뜻을 모른 채 실어 나르기만 한다.
#[derive(Debug, Clone, PartialEq)]
pub struct Item { pub x0: f32, pub x1: f32, pub id: u32, pub name: u32, pub row: u32, pub flags: u32, pub row2: u32, pub reference: u32, pub color: u32,
    pub a: u32, pub b: u32, pub c: u32, pub d: u32, pub text2: u32 }

/// 일반 구역 하나(구역 번호 + 항목들).
#[derive(Debug, Clone, PartialEq)]
pub struct Section { pub kind: u32, pub items: Vec<Item> }

#[derive(Debug, Default)]
pub struct Decoded {
    pub flags: u16,
    pub level: i32,
    pub chunk: i32,
    pub x: i64,
    pub origin: i64,
    pub span: i64,
    pub bands: Vec<Band>,
    pub cells: Vec<CellItem>,
    pub events: Vec<EventItem>,
    pub pills: Vec<Pill>,
    /// 구역 번호 오름차순.
    pub sections: Vec<Section>,
    pub strings: Vec<String>,
    /// 칸을 실을 때 쓴 **시험용 손잡이**의 나눗수(계약 5-3절). 기본 8이면 **0**이라 바이트가 예전과 같고,
    /// 8이 아닌 값으로 만든 타일만 머리의 예약 낱말에 그 값이 찍힌다 — 받아 둔 타일과 섞이면 여기서 드러난다.
    pub cell_lod: u32,
}

impl Decoded {
    pub fn section(&self, kind: u32) -> &[Item] {
        self.sections.iter().find(|s| s.kind == kind).map_or(&[], |s| &s.items[..])
    }
}

#[derive(Default)]
struct Strings {
    index: HashMap<String, u32>,
    list: Vec<String>,
}

impl Strings {
    fn put(&mut self, text: String) -> u32 {
        if text.is_empty() {
            return NO_NAME;
        }
        if let Some(i) = self.index.get(&text) {
            return *i;
        }
        let i = self.list.len() as u32;
        self.index.insert(text.clone(), i);
        self.list.push(text);
        i
    }
}

/// 제목 · look · 딱지는 미리 만든 요약에서도 덮는 색인에서도 함께 온다 — 대표마다 사건 표를 찾아가지 않는다.
#[derive(Clone)]
/// `prec` = 시작 날짜의 정밀도(사건 `rail`의 8~10비트 — 요약 대표의 머리 5번째 바이트 · 옛 저장소는 0 = 해). 세기로 적은 연대의 괄호가 성긴 단계에서도 보이게(묶음 5 · 6번).
/// `rank` = 사건 제 줄(이사 전 기본 줄)의 트랙 차례(`RowMap::track_pos`) · `ord` = 트랙 안 사건 차례(`events.ord`) — 중요도가 같은 대표의
/// 동률을 번호 대신 (rank, ord)로 깬다(같으면 번호 · 판정 R23). 다시 쓰지 않은 트랙의 ord는 그대로 맞고, 이사로 한 줄에 모인 여러 트랙의 사건도
/// 통째 짓기와 같은 차례가 된다(배치의 사건은 트랙 차례로 묶여 나온다).
struct Rep { importance: i64, id: i64, rank: i64, ord: i64, start: i64, look: u32, band: u32, prec: u8, title: String, label: String }

#[derive(Default)]
struct Bucket { n: i64, reps: Vec<Rep>, cats: std::collections::BTreeMap<u8, u32> }

impl Bucket {
    /// 사건 하나를 분류별 수에 센다(분류가 없는 255는 세지 않는다).
    fn count_cat(&mut self, look: u32) {
        let cat = (look & 0xff) as u8;
        if cat != 255 {
            *self.cats.entry(cat).or_default() += 1;
        }
    }

    /// 분류별 수를 알약에 실을 글로 — `"3:12,7:5"`(분류 번호 오름차순). 빈 것은 빈 글자다.
    fn cats_text(&self) -> String {
        let mut out = String::new();
        for (cat, count) in &self.cats {
            if !out.is_empty() {
                out.push(',');
            }
            out.push_str(&format!("{cat}:{count}"));
        }
        out
    }

    /// 대표 넷 안에서의 자리(중요도 큰 순 · 트랙 차례 · 트랙 안 차례 작은 순 · 번호 작은 순). 넷 밖이면 None.
    fn place(&self, importance: i64, rank: i64, ord: i64, id: i64) -> Option<usize> {
        let at = self.reps.iter().position(|r| (-importance, rank, ord, id) < (-r.importance, r.rank, r.ord, r.id)).unwrap_or(self.reps.len());
        (at < 4).then_some(at)
    }

    fn offer(&mut self, rep: Rep) {
        if let Some(at) = self.place(rep.importance, rep.rank, rep.ord, rep.id) {
            self.reps.insert(at, rep);
            self.reps.truncate(4);
        }
    }
}

/// [`FINE_EVENTS_SQL`] · [`FINE_EVENTS_SQL_NO_ORD`]의 한 몸 — 끝 열(트랙 안 차례 · 없으면 번호)만 받는다.
macro_rules! fine_events_sql {
    ($order:literal) => {
        concat!("SELECT id,start,importance,title,look,label,band,rail,", $order,
            " FROM events INDEXED BY events_time WHERE lane=?1 AND start BETWEEN ?2 AND ?3 AND pack IN (SELECT value FROM json_each(?4))")
    };
}
/// 그 자리에서 세는 단계(L < PRE_MIN)의 사건 조회. 덮는 색인 events_time만 훑는다 — 제목 · look · 딱지 · rail(정밀도)까지,
/// 뒤에 붙는 변형 조건의 variant까지 색인에서 온다(`builder::EVENTS_TIME_INDEX_SQL`). 대표마다 사건 표를 찾아가면 1,000만 건(5GB)에서는 흩어진 자리를 읽느라 타일 하나에 44~67ms가 걸렸다.
/// 끝 열 `ord`(트랙 안 사건 차례 — 판정 R23)는 대표의 동률을 깬다(트랙 차례는 줄에서 `RowMap`으로).
pub const FINE_EVENTS_SQL: &str = fine_events_sql!("ord");
/// [`FINE_EVENTS_SQL`]의 옛 저장소 꼴 — `events.ord` 열이 없으면 차례 자리에 번호를 읽는다(동률을 예전처럼 번호로 깬다). 같은 글에서 끝 열만 다르게 짓는다
/// (과제 A+ 넘김 "같은 규칙 두 곳" — 손으로 베낀 둘째 SQL을 걷음).
const FINE_EVENTS_SQL_NO_ORD: &str = fine_events_sql!("id");

/// 타일 안에서의 가로 자리(분). 끝은 양 끝 포함이라 그리는 오른쪽 끝은 다음 분이다. 돌려주는 값: (x0, x1, 왼쪽 잘림, 오른쪽 잘림)
fn clip(start: i64, end: i64, t0: i64, t1: i64) -> (f32, f32, bool, bool) {
    ((start.max(t0) - t0) as f32, (end.min(t1) + 1 - t0) as f32, start < t0, end > t1)
}

/// 열쇠 ≠ 자리 저장소에서 줄 열쇠 범위마다 모은 행을 하나로 — 번호가 겹친 것(밖에서 이사해 온 것은 범위마다 잡힌다)은 한 번만 남기고,
/// 원래 SQL의 `ORDER BY`와 같은 차례(줄은 자리로)로 다시 늘어놓는다(안정 정렬). 그러면 싣는 차례 · 글자표 차례가 열쇠 = 자리
/// 저장소와 같아 같은 내용이면 바이트까지 같다.
fn settle<T, K: Ord>(found: &mut Vec<T>, id: impl Fn(&T) -> i64, order: impl FnMut(&T) -> K) {
    let mut seen = HashSet::new();
    found.retain(|row| seen.insert(id(row)));
    found.sort_by_key(order);
}

/// 띠 한 행: id · 줄 열쇠 · 시작 · 끝 · 미정 끝 · 색 · 이름 · look · 딱지 · sub · form(열이 없는 옛 저장소는 0).
type BandRow = (i64, i64, i64, i64, i64, i64, String, i64, String, i64, i64);
/// 칸 한 행: id · 줄 열쇠 · 시작 · 끝 · kind · 이름 · lane · style · 색 · 띠 번호 · 띠 시작 · 띠 끝.
type CellRow = (i64, i64, i64, i64, i64, String, i64, i64, i64, i64, i64, i64);
/// 사건 막대 한 행: id · 줄 열쇠 · 시작 · 끝 · 중요도 · 제목 · look · 딱지 · rail · 든 띠.
type BarRow = (i64, i64, i64, i64, i64, String, i64, String, i64, i64);
/// 일반 항목 한 행: id · 구역 · 줄 열쇠 · 끝 줄 열쇠 · 시작 · 끝 · ref · 이름 · 색 · a · b · c · d · text2 · ref_kind · 변형.
type ItemRow = (i64, i64, i64, i64, i64, i64, i64, String, i64, i64, i64, i64, i64, String, i64, i64);

pub fn build_tile(store: &Store, req: &TileRequest) -> Result<Vec<u8>> {
    if req.level > LEVEL_MAX || req.chunk < 0 || req.chunk > i32::MAX as i64 / CHUNK_ROWS {
        return Err("타일 요청의 단계 또는 줄 묶음이 범위 밖입니다".into());
    }
    let width = TILE_BUCKETS * bucket_minutes(req.level);
    req.x.checked_mul(width).and_then(|v| v.checked_add(width)).ok_or("타일 번호가 범위 밖입니다")?;
    let (t0, t1) = tile_range(req.level, req.x);
    // 줄 묶음은 **자리**(밖으로 보이는 줄 번호)의 범위다. 저장소 안(표 · R-tree)은 줄 열쇠로 말하므로 경계에서 바꾼다(계획 P4):
    // 묶음 → 열쇠 범위들(트랙마다 하나 — 범위마다 같은 SQL을 돌린다. R-tree는 OR 조건으로는 색인을 타지 못한다) · 읽은 줄 열쇠 → 자리(`pos`).
    // 열쇠 = 자리 저장소(새로 지은 것)는 범위 하나 · 읽은 대로 싣는 예전 길 그대로라 바이트도 시간도 같다(지름길).
    let (r0, r1) = (req.chunk * CHUNK_ROWS, req.chunk * CHUNK_ROWS + CHUNK_ROWS - 1);
    let map = &store.rows;
    let same = map.is_identity();
    let ranges = map.ranges_for(r0, r1);
    // 지름길은 겹침 없애기 · 다시 정렬을 하지 않으므로 범위가 하나여야 한다(`ranges_for`가 열쇠 = 자리면 하나만 낸다).
    debug_assert!(!same || ranges.len() <= 1);
    // 줄 열쇠가 이 묶음(자리 범위)에 드는가.
    let inside = |key: i64| (r0..=r1).contains(&map.pos(key));
    let day = |minute: i64| minute.div_euclid(DAY).clamp(i32::MIN as i64, i32::MAX as i64);
    let (d0, d1) = (day(t0), day(t1));
    let level = req.level as i64;
    let packs = serde_json::to_string(&req.packs)?;
    let db = &store.db;
    let mut strings = Strings::default();

    // 변형: 켠 변형의 것만 고르고(늘 있는 것은 variant = 0), 이사한 것은 도착 줄의 묶음 타일에 실린다.
    let vary = req.variants.as_ref();
    let moving = vary.is_some_and(|v| !v.bands.is_empty() || !v.events.is_empty());

    let mut bands = Vec::new();
    {
        let keep = vary.map(|v| v.keep("p.variant")).unwrap_or_default();
        // 밖에서 이 묶음으로 이사해 온 띠는 줄 번호로는 찾을 수 없다 — 번호로 따로 집어 온다.
        let incoming = vary.map(|v| v.incoming_bands(inside)).unwrap_or_default();
        let reach = if incoming.is_empty() { String::new() } else { format!(" OR p.id IN ({})", crate::variant::in_list(&incoming)) };
        // 형식 4의 뜻(스키마 4) — 열이 없는 옛 저장소는 0(모름)이라 띠 구역이 2판 그대로 열 열이다.
        let form = if store.period_form { "p.form" } else { "0" };
        let sql = format!("SELECT p.id,p.row,p.start,p.end,p.fuzzy,p.color,p.name,p.look,p.tag,p.sub,{form} FROM period_bounds b JOIN periods p ON p.id=b.id \
            WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND (( b.row_min<=?3 AND b.row_max>=?4 ){reach}) AND b.lod_max>=?5 AND p.start<=?6 AND p.end>=?7 \
            AND p.pack IN (SELECT value FROM json_each(?8)){keep} ORDER BY p.row,p.start,p.id");
        let mut stmt = db.prepare_cached(&sql)?;
        let mut put = |(id, mut row, start, end, fuzzy, color, name, look, tag, sub, form): BandRow| {
            // 거르개: 꺼진 트랙 · 꺼진 종류 · 꺼진 실재성의 띠는 타일에서 아예 빠진다(묶음 알약의 수까지 거른 뒤의 것이 되게).
            if req.filter.as_ref().is_some_and(|f| f.band_off(id)) {
                return;
            }
            if let Some(v) = vary {
                row = v.band_row(id, row);
                // 숨은 띠(도착 줄 −1 — 선반)는 자리가 −1이라 어느 묶음에도 들지 않는다 — 딸린 칸 · 사건도 같은 길로 빠진다.
                if !inside(row) {
                    return;
                }
            }
            let (x0, x1, left, right) = clip(start, end, t0, t1);
            let mut flags = 0;
            if left { flags |= CLIP_LEFT } else if fuzzy & 1 != 0 { flags |= FUZZY_START }
            if right { flags |= CLIP_RIGHT } else if fuzzy & 2 != 0 { flags |= FUZZY_END }
            bands.push(Band { x0, x1, id: id as u32, color: color as u32, name: strings.put(name), row: map.pos(row) as u32, flags,
                look: look as u32, tag: strings.put(tag), sub: sub as u32, form: form as u32 });
        };
        let mut found: Vec<BandRow> = Vec::new();
        for &(k0, k1) in &ranges {
            let mut rows = stmt.query(params![d1, d0, k1, k0, level, t1, t0, packs])?;
            while let Some(r) = rows.next()? {
                let row: BandRow = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?, r.get(10)?);
                if same { put(row) } else { found.push(row) }
            }
        }
        settle(&mut found, |b| b.0, |b| (map.pos(b.1), b.2, b.0));
        found.into_iter().for_each(&mut put);
        if moving {
            bands.sort_by_key(|b| (b.row, b.id));
            bands.sort_by(|a, b| (a.row, a.x0, a.id).partial_cmp(&(b.row, b.x0, b.id)).unwrap());
        }
    }

    let mut cells = Vec::new();
    {
        let keep = vary.map(|v| v.keep("c.variant")).unwrap_or_default();
        let incoming = vary.map(|v| v.incoming_bands(inside)).unwrap_or_default();
        let reach = if incoming.is_empty() { String::new() } else { format!(" OR c.period IN ({})", crate::variant::in_list(&incoming)) };
        let sql = format!("SELECT c.id,b.row_min,c.start,c.end,c.kind,c.name,c.lane,c.style,c.color,c.period,p.start,p.end FROM cell_bounds b JOIN cells c ON c.id=b.id JOIN periods p ON p.id=c.period \
            WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND (( b.row_min<=?3 AND b.row_max>=?4 ){reach}) AND b.lod_max>=?5 AND c.start<=?6 AND c.end>=?7 \
            AND p.pack IN (SELECT value FROM json_each(?8)){keep} ORDER BY b.row_min,c.kind,c.lane,c.start,c.id");
        let mut stmt = db.prepare_cached(&sql)?;
        // 성긴 단계의 칸 추림: 그 단계에서 **아무리 확대해도** 칸 층이 그리지 않는 칸은 싣지 않는다(계약 5절).
        // 층이 건너뛰는 칸은 앞 칸이 늘어나 빈틈을 메우므로 그림이 바뀌지 않는다.
        let (cell_min, host_min) = (cell_min_span(req.level), host_min_span(req.level));
        // 시험용 손잡이(계약 5-3절). 기본 8이면 공간 색인의 `lod_max>=level`과 뜻이 같아 아래 판정이 하나도 걸러 내지 않는다
        // — 그래서 손잡이를 건드리지 않은 타일은 **바이트까지 예전과 같다**.
        let lod_knob = cell_lod_divisor() != CELL_LOD_DEFAULT;
        let mut put = |(id, mut row, start, end, kind, name, lane, style, color, period, host_start, host_end): CellRow| {
            if lod_knob && cell_lod_of(end - start) < level {
                return;
            }
            // 칸이 1px도 안 되거나, 띠가 좁아 제 칸을 하나도 그릴 수 없으면 뺀다.
            if end - start + 1 < cell_min || host_end - host_start + 1 < host_min {
                return;
            }
            // 거르개: 꺼진 띠의 칸은 띠와 함께 빠진다.
            if req.filter.as_ref().is_some_and(|f| f.band_off(period)) {
                return;
            }
            if let Some(v) = vary {
                if v.hidden_cells.contains(&id) {
                    return; // 이 변형에서는 변형 판이 대신 나온다
                }
                row = v.band_row(period, row);
                if !inside(row) {
                    return;
                }
            }
            let (x0, x1, left, right) = clip(start, end, t0, t1);
            let flags = if left { CLIP_LEFT } else { 0 } | if right { CLIP_RIGHT } else { 0 };
            cells.push(CellItem { x0, x1, id: id as u32, name: strings.put(name), row: map.pos(row) as u32, kind: kind as u32, flags,
                lane: lane as u32, style: style as u32, color: color as u32 });
        };
        let mut found: Vec<CellRow> = Vec::new();
        for &(k0, k1) in &ranges {
            let mut rows = stmt.query(params![d1, d0, k1, k0, cell_lod_query_level(req.level), t1, t0, packs])?;
            while let Some(r) = rows.next()? {
                let row: CellRow = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?, r.get(10)?, r.get(11)?);
                if same { put(row) } else { found.push(row) }
            }
        }
        settle(&mut found, |c| c.0, |c| (map.pos(c.1), c.4, c.6, c.2, c.0));
        found.into_iter().for_each(&mut put);
        if moving {
            cells.sort_by(|a, b| (a.row, a.kind, a.lane, a.x0, a.id).partial_cmp(&(b.row, b.kind, b.lane, b.x0, b.id)).unwrap());
        }
    }

    // 긴 기간 막대: 이 단계에서 2px보다 굵은 것만. 대표로 뽑힌 것은 아래에서 COUNTED를 붙인다.
    let mut events: Vec<EventItem> = Vec::new();
    let mut bar_at: HashMap<i64, usize> = HashMap::new();
    {
        let keep = vary.map(|v| v.keep("e.variant")).unwrap_or_default();
        let mut reach = String::new();
        if let Some(v) = vary {
            let (ev, bd) = (v.incoming_events(inside), v.incoming_bands(inside));
            if !ev.is_empty() {
                reach.push_str(&format!(" OR e.id IN ({})", crate::variant::in_list(&ev)));
            }
            if !bd.is_empty() {
                reach.push_str(&format!(" OR e.band IN ({})", crate::variant::in_list(&bd)));
            }
        }
        let sql = format!("SELECT e.id,e.lane,e.start,e.end,e.importance,e.title,e.look,e.label,e.rail,e.band FROM span_bounds b JOIN events e ON e.id=b.id \
            WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND (( b.lane_min<=?3 AND b.lane_max>=?4 ){reach}) AND b.lod_max>=?5 AND e.start<=?6 AND e.end>=?7 \
            AND e.pack IN (SELECT value FROM json_each(?8)){keep} ORDER BY e.id");
        let mut stmt = db.prepare_cached(&sql)?;
        let mut put = |(id, mut row, start, end, importance, title, look, label, rail, band): BarRow| {
            // 거르개: 꺼진 트랙 · 분류 · 중요도 미달 · 딸린 띠가 꺼진 사건은 막대도 싣지 않는다.
            if req.filter.as_ref().is_some_and(|f| f.event_off(row, look, importance, band)) {
                return;
            }
            if let Some(v) = vary {
                row = v.event_row(id, band, row);
                if !inside(row) {
                    return;
                }
            }
            let (x0, x1, left, right) = clip(start, end, t0, t1);
            let bits = importance as u32 & 3 | BAR | if left { EVENT_CLIP_LEFT } else { 0 } | if right { EVENT_CLIP_RIGHT } else { 0 };
            bar_at.insert(id, events.len());
            events.push(EventItem { x0, x1, id: id as u32, name: strings.put(title), row: map.pos(row) as u32, bits,
                look: look as u32, label: strings.put(label), rail: rail as u32, band: band as u32 });
        };
        let mut found: Vec<BarRow> = Vec::new();
        for &(k0, k1) in &ranges {
            let mut rows = stmt.query(params![d1, d0, k1, k0, level, t1, t0, packs])?;
            while let Some(r) = rows.next()? {
                let row: BarRow = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?);
                if same { put(row) } else { found.push(row) }
            }
        }
        settle(&mut found, |e| e.0, |e| e.0);
        found.into_iter().for_each(&mut put);
    }

    // (줄, 통) → 개수와 대표.
    // 거르개가 사건에 걸리면 미리 셈해 둔 요약(단계별 통)을 쓸 수 없다 — 그 자리에서 다시 센다.
    // 덮는 색인 events_time이 중요도 · look · 든 띠 · 변형까지 담고 있어 사건 표는 여전히 읽지 않는다.
    // 변형이 걸리면 미리 셈해 둔 요약(줄마다의 통)을 그대로 쓸 수 없다 — 사건이 다른 줄로 가거나, 그 변형에서만 있는 사건이 늘기 때문이다.
    let recount = req.filter.as_ref().is_some_and(Filtered::counts_events) || vary.is_some_and(|v| !v.is_plain());
    let mut buckets: HashMap<(i64, i64), Bucket> = HashMap::new();
    if req.level >= PRE_MIN && !recount {
        let (b0, b1) = (req.x * TILE_BUCKETS, req.x * TILE_BUCKETS + TILE_BUCKETS - 1);
        // 분류별 수(`cats`)는 뒤에 더한 열이다 — 그 열이 없는 옛 저장소에서는 빈 것으로 읽어 알약에 비율을 싣지 않는다.
        let cats_column = if store.summary_cats { "cats" } else { "x''" };
        // 대표마다의 트랙 안 차례(`ords` — 판정 R24): 자료집 여럿의 요약이 한 통에 합쳐질 때 동률을 사건 표를 찾아가지 않고 깬다. 한 요약 줄은
        // 한 줄(곧 한 트랙)의 것이라 트랙 차례는 같다. 그 열이 없거나 비어 있는 요약(옛 저장소 · 그 위에 열을 더한 뒤의 옛 줄)은 번호로 깬다
        // — 그런 줄은 한 트랙 안에서 모두 그렇다(트랙의 요약은 한꺼번에 지어진다).
        let ords_column = if store.summary_ords { "ords" } else { "x''" };
        let sql = format!("SELECT bucket,n,reps,{cats_column},{ords_column} FROM summaries WHERE level=?1 AND lane=?2 AND bucket BETWEEN ?3 AND ?4 AND pack IN (SELECT value FROM json_each(?5))");
        let mut stmt = db.prepare_cached(&sql)?;
        // 통은 (자리, 통)으로 모은다 — 알약 · 대표가 싣는 줄이 자리다.
        for lane in ranges.iter().flat_map(|&(k0, k1)| k0..=k1) {
            let rank = if store.event_ord { map.track_pos(lane) } else { 0 };
            let mut rows = stmt.query(params![level, lane, b0, b1, packs])?;
            while let Some(r) = rows.next()? {
                let cell = buckets.entry((map.pos(lane), r.get(0)?)).or_default();
                cell.n += r.get::<_, i64>(1)?;
                let cats: Vec<u8> = r.get(3)?;
                for slot in cats.chunks_exact(CAT_ENTRY) {
                    *cell.cats.entry(slot[0]).or_default() += u32::from_le_bytes(slot[1..5].try_into()?);
                }
                let blob: Vec<u8> = r.get(2)?;
                let ords: Vec<u8> = r.get(4)?;
                let (mut at, mut nth) = (0, 0);
                while at + REP_HEAD <= blob.len() {
                    let slot = &blob[at..];
                    let title_len = u16::from_le_bytes(slot[6..8].try_into()?) as usize;
                    let label_len = u16::from_le_bytes(slot[20..22].try_into()?) as usize;
                    let text = slot.get(REP_HEAD..REP_HEAD + title_len + label_len).ok_or("요약의 대표 글자가 잘렸습니다")?;
                    let id = u32::from_le_bytes(slot[0..4].try_into()?) as i64;
                    let ord = ords.get(nth * 4..nth * 4 + 4).map_or(id, |b| i64::from(u32::from_le_bytes([b[0], b[1], b[2], b[3]])));
                    cell.offer(Rep {
                        id, rank, ord, importance: slot[4] as i64, prec: slot[5] & 7,
                        start: i64::from_le_bytes(slot[8..16].try_into()?), look: u32::from_le_bytes(slot[16..20].try_into()?),
                        band: u32::from_le_bytes(slot[24..28].try_into()?),
                        title: std::str::from_utf8(&text[..title_len])?.to_owned(), label: std::str::from_utf8(&text[title_len..])?.to_owned(),
                    });
                    at += REP_HEAD + title_len + label_len;
                    nth += 1;
                }
            }
        }
    } else {
        // 덮는 색인만 훑는다 — 같은 날 몰린 수만 건에서도 사건 표를 찾아가지 않는다. 글자는 대표 넷 안에 드는 것만 꺼낸다.
        // 변형이 걸리면 '떠난 줄'까지 함께 훑어야 도착 줄의 수가 맞는다(이사해 온 사건은 남의 줄에 적혀 있다).
        // 훑는 것은 줄 열쇠다(묶음의 열쇠 범위들 + 이 묶음 밖의 떠난 줄). 통의 수는 훑는 차례와 상관없다.
        let mut lanes: Vec<i64> = ranges.iter().flat_map(|&(k0, k1)| k0..=k1).collect();
        if let Some(v) = vary {
            for lane in &v.from_rows {
                if !inside(*lane) {
                    lanes.push(*lane);
                }
            }
            lanes.sort_unstable();
        }
        let keep = vary.map(|v| v.keep("variant")).unwrap_or_default();
        let sql = format!("{}{keep}", if store.event_ord { FINE_EVENTS_SQL } else { FINE_EVENTS_SQL_NO_ORD });
        let mut stmt = db.prepare_cached(&sql)?;
        for lane in lanes {
            // 사건 제 줄의 트랙 차례 — 이사해 온 사건도 떠난 줄(제 줄)로 훑으므로 그 트랙의 것이다. 차례 열이 없는 옛 저장소는 예전처럼 번호로만 깬다.
            let rank = if store.event_ord { map.track_pos(lane) } else { 0 };
            let mut rows = stmt.query(params![lane, t0, t1, packs])?;
            while let Some(r) = rows.next()? {
                let (id, importance): (i64, i64) = (r.get(0)?, r.get(2)?);
                let (look, band): (i64, i64) = (r.get(4)?, r.get(6)?);
                if let Some(f) = &req.filter {
                    if f.event_off(lane, look, importance, band) {
                        continue;
                    }
                }
                let mut row = lane;
                if let Some(v) = vary {
                    row = v.event_row(id, band, lane);
                    if !inside(row) {
                        continue;
                    }
                }
                let start: i64 = r.get(1)?;
                let cell = buckets.entry((map.pos(row), bucket_of(start, req.level))).or_default();
                cell.n += 1;
                cell.count_cat(look as u32);
                let ord: i64 = r.get(8)?;
                if cell.place(importance, rank, ord, id).is_some() {
                    cell.offer(Rep { id, rank, ord, importance, start, look: look as u32, band: band as u32, prec: ((r.get::<_, i64>(7)? >> 8) & 7) as u8, title: r.get(3)?, label: r.get(5)? });
                }
            }
        }
    }

    let mut pills = Vec::new();
    {
        let bucket_width = bucket_minutes(req.level);
        // 해시 표의 순서는 실행마다 다르다. (줄, 통) 순서로 훑어야 글자표의 순서까지 같은 바이트가 나온다.
        let mut keys: Vec<(i64, i64)> = buckets.keys().copied().collect();
        keys.sort_unstable();
        for (lane, bucket) in &keys {
            let cell = &buckets[&(*lane, *bucket)];
            for rep in &cell.reps {
                if let Some(at) = bar_at.get(&rep.id) {
                    events[*at].bits |= COUNTED;
                    continue;
                }
                let x = (rep.start - t0) as f32;
                events.push(EventItem { x0: x, x1: x, id: rep.id as u32, name: strings.put(rep.title.clone()), row: *lane as u32,
                    bits: rep.importance as u32 & 3 | COUNTED, look: rep.look, label: strings.put(rep.label.clone()), rail: (rep.prec as u32) << 8, band: rep.band }); // rail은 정밀도 비트만(막대 · 연대 폭 · 이설은 성긴 단계에 없음)
            }
            let rest = cell.n - cell.reps.len() as i64;
            if rest > 0 {
                let x0 = (bucket * bucket_width - t0) as f32;
                pills.push(Pill { x0, x1: x0 + bucket_width as f32, count: rest as u32, row: *lane as u32, cats: strings.put(cell.cats_text()) });
            }
        }
    }
    events.sort_by(|a, b| (a.row, a.x0, a.id).partial_cmp(&(b.row, b.x0, b.id)).unwrap());
    pills.sort_by(|a, b| (a.row, a.x0).partial_cmp(&(b.row, b.x0)).unwrap());

    // 일반 구역: 띠 · 칸 · 사건이 아닌 모든 그릴 것. 구역 번호마다 한 구역으로 모은다.
    let mut sections: Vec<Section> = Vec::new();
    {
        // 거르개가 있을 때만 `ref_kind`(0 없음 · 1 띠 · 2 사건)를 함께 읽는다 — 그 열이 없는 옛 저장소에서는 0으로 읽는다.
        let ref_kind = if req.filter.is_some() && store.item_ref_kind { "i.ref_kind" } else { "0" };
        // 변형: 가리키는 띠 · 사건이 이사하면 항목도 따라가므로, 줄 번호로 찾지 못하는 것은 `ref`로 집어 온다.
        let ref_kind = if (req.filter.is_some() || moving) && store.item_ref_kind { "i.ref_kind" } else { ref_kind };
        let keep = vary.map(|v| v.keep("i.variant")).unwrap_or_default();
        let mut reach = String::new();
        if let Some(v) = vary {
            let (ev, bd) = (v.incoming_events(inside), v.incoming_bands(inside));
            if !ev.is_empty() {
                reach.push_str(&format!(" OR (i.ref_kind=2 AND i.ref IN ({}))", crate::variant::in_list(&ev)));
            }
            if !bd.is_empty() {
                reach.push_str(&format!(" OR (i.ref_kind=1 AND i.ref IN ({}))", crate::variant::in_list(&bd)));
            }
        }
        // 집합 보기(kind 3)의 항목은 판을 켠 자리에 이미 놓여 있다 — 그 변형 번호를 함께 읽어 가리키는 띠를 따라 옮기지 않는다(variant.rs의 boards).
        // 선반(kind 6)이 띠를 숨기면 그 띠를 가리키는 항목이 기본 판(빠짐)인지 켠 변형의 것(제자리)인지도 이 번호로 가린다(`Variants::item_rows`).
        // 변형이 걸리지 않으면(옛 저장소 포함) 0을 읽어 예전과 같은 SQL 모양 · 같은 답이다.
        let item_variant = if vary.is_some_and(|v| !v.boards.is_empty() || v.hiding) { "i.variant" } else { "0" };
        let sql = format!("SELECT i.id,i.section,i.row,i.row2,i.start,i.end,i.ref,i.name,i.color,i.a,i.b,i.c,i.d,i.text2,{ref_kind},{item_variant} FROM item_bounds b JOIN items i ON i.id=b.id \
            WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND (( b.row_min<=?3 AND b.row_max>=?4 ){reach}) AND b.lod_max>=?5 AND i.start<=?6 AND i.end>=?7 \
            AND i.pack IN (SELECT value FROM json_each(?8)){keep} ORDER BY i.section,i.row,i.start,i.id");
        // 거르개가 사건에 걸리면 항목이 가리키는 사건이 살아남았는지도 봐야 한다(빠진 사건의 기간 막대만 남지 않게).
        let mut off_events: HashSet<i64> = HashSet::new();
        if let Some(f) = &req.filter {
            if store.item_ref_kind && f.counts_events() {
                let mut stmt = db.prepare_cached(&format!(
                    "SELECT e.id,e.lane,e.look,e.importance,e.band FROM events e WHERE e.id IN \
                     (SELECT i.ref FROM item_bounds b JOIN items i ON i.id=b.id WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND b.row_min<=?3 AND b.row_max>=?4 AND b.lod_max>=?5 \
                      AND i.start<=?6 AND i.end>=?7 AND i.pack IN (SELECT value FROM json_each(?8)) AND i.ref_kind=2)"
                ))?;
                for &(k0, k1) in &ranges {
                    let mut rows = stmt.query(params![d1, d0, k1, k0, level, t1, t0, packs])?;
                    while let Some(r) = rows.next()? {
                        if f.event_off(r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?) {
                            off_events.insert(r.get(0)?);
                        }
                    }
                }
            }
        }
        let mut stmt = db.prepare_cached(&sql)?;
        let mut put = |(id, section, mut row, mut row2, start, end, reference, name, color, a, b, c, d, text2, ref_kind, variant): ItemRow| {
            if let Some(v) = vary {
                if v.hidden_items.contains(&id) {
                    return; // 이 변형에서는 변형 판이 대신 나온다
                }
                if !v.boards.contains(&variant) {
                    match v.item_rows(map, ref_kind, reference, row, row2, variant) {
                        Some(rows) => (row, row2) = rows,
                        None => return, // 가리키는 띠 · 사건이 이 변형에서 숨었다(선반 — 기본 판은 함께 숨는다)
                    }
                }
                // 두 끝은 자리 차례다(item_rows) — 묶음과 겹치지 않으면 뺀다. 자리가 없는 줄(음수 — 숨은 것)은 싣지 않는다
                // (`map.pos(−1) as u32`가 넘쳐 엉뚱한 줄이 되지 않게).
                let (p0, p1) = (map.pos(row), map.pos(row2));
                if p0 < 0 || p1 < 0 || p0 > r1 || p1 < r0 {
                    return;
                }
            }
            if let Some(f) = &req.filter {
                // 여러 줄에 걸친 것(관계선 · 테두리)은 양 끝의 줄을 본다 — 한쪽 트랙이 꺼지면 이을 곳이 없다.
                let gone = f.row_off(row)
                    || f.row_off(row2)
                    || f.figure_bar_off(section, b)
                    || (reference != 0 && match ref_kind {
                        2 => off_events.contains(&reference),
                        // 1(띠)이거나, ref_kind를 모르는 옛 저장소이거나.
                        _ => f.band_off(reference),
                    });
                if gone {
                    return;
                }
            }
            let (x0, x1, left, right) = clip(start, end, t0, t1);
            let flags = if left { CLIP_LEFT } else { 0 } | if right { CLIP_RIGHT } else { 0 };
            let item = Item { x0, x1, id: id as u32, name: strings.put(name), row: map.pos(row) as u32, flags,
                row2: map.pos(row2) as u32, reference: reference as u32, color: color as u32,
                a: a as u32, b: b as u32, c: c as u32, d: d as u32, text2: strings.put(text2) };
            let kind = section as u32;
            match sections.iter_mut().find(|s| s.kind == kind) {
                Some(slot) => slot.items.push(item),
                None => sections.push(Section { kind, items: vec![item] }),
            }
        };
        let mut found: Vec<ItemRow> = Vec::new();
        for &(k0, k1) in &ranges {
            let mut rows = stmt.query(params![d1, d0, k1, k0, level, t1, t0, packs])?;
            while let Some(r) = rows.next()? {
                let row: ItemRow = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?,
                    r.get(9)?, r.get(10)?, r.get(11)?, r.get(12)?, r.get(13)?, r.get(14)?, r.get(15)?);
                if same { put(row) } else { found.push(row) }
            }
        }
        // 구역 번호가 앞 열쇠라, 범위가 여럿이어도 구역은 번호 차례로 처음 나타난다(구역 목록이 늘 번호 차례).
        settle(&mut found, |i| i.0, |i| (i.1, map.pos(i.2), i.4, i.0));
        found.into_iter().for_each(&mut put);
        if moving {
            sections.sort_by_key(|s| s.kind);
            for s in &mut sections {
                s.items.sort_by(|a, b| (a.row, a.x0, a.id).partial_cmp(&(b.row, b.x0, b.id)).unwrap());
            }
        }
    }

    Ok(encode(&Decoded { flags: 0, level: req.level as i32, chunk: req.chunk as i32, x: req.x, origin: t0, span: width, bands, cells, events, pills, sections,
        strings: strings.list, cell_lod: if cell_lod_divisor() == CELL_LOD_DEFAULT { 0 } else { cell_lod_divisor() as u32 } }))
}

/// 구역 표에 실을 것(빈 구역은 싣지 않는다 — 없는 구역과 빈 구역은 읽는 쪽에서 같다).
fn plan(t: &Decoded) -> Vec<(u32, u32, u32)> {
    let mut plan = Vec::new();
    for (kind, count, columns) in [
        (SEC_BAND, t.bands.len(), band_columns(&t.bands)), (SEC_CELL, t.cells.len(), CELL_COLUMNS),
        (SEC_EVENT, t.events.len(), EVENT_COLUMNS), (SEC_PILL, t.pills.len(), pill_columns(&t.pills)),
    ] {
        if count > 0 {
            plan.push((kind, count as u32, columns));
        }
    }
    for s in &t.sections {
        if !s.items.is_empty() {
            plan.push((s.kind, s.items.len() as u32, ITEM_COLUMNS));
        }
    }
    plan
}

pub fn encode(t: &Decoded) -> Vec<u8> {
    let table = plan(t);
    let text_bytes: usize = t.strings.iter().map(String::len).sum();
    let data_words: usize = table.iter().map(|(_, count, columns)| *count as usize * *columns as usize).sum();
    let mut out = Vec::with_capacity(HEADER + (SECTION_ENTRY_WORDS * table.len() + data_words + t.strings.len() + 1) * 4 + text_bytes + 4);
    out.extend_from_slice(&MAGIC.to_le_bytes());
    out.extend_from_slice(&VERSION.to_le_bytes());
    out.extend_from_slice(&t.flags.to_le_bytes());
    out.extend_from_slice(&t.level.to_le_bytes());
    out.extend_from_slice(&t.chunk.to_le_bytes());
    for v in [t.x, t.origin, t.span] {
        out.extend_from_slice(&v.to_le_bytes());
    }
    for n in [table.len() as u32, t.strings.len() as u32, text_bytes as u32, t.cell_lod, 0, 0, 0, 0] {
        out.extend_from_slice(&n.to_le_bytes());
    }
    debug_assert_eq!(out.len(), HEADER);
    // 구역 표: 자리는 파일 처음부터 4바이트 낱말 단위. 구역 자료는 표 바로 뒤에 차례로 놓인다.
    let mut at = HEADER / 4 + SECTION_ENTRY_WORDS * table.len();
    for (kind, count, columns) in &table {
        for v in [*kind, *count, *columns, at as u32] {
            out.extend_from_slice(&v.to_le_bytes());
        }
        at += *count as usize * *columns as usize;
    }
    // 구조체의 배열이 아니라 배열의 구조체: 화면 쪽이 복사 없이 같은 종류의 값을 한 줄로 훑는다.
    macro_rules! column { ($items:expr, $field:ident) => { for item in $items { out.extend_from_slice(&item.$field.to_le_bytes()); } }; }
    if !t.bands.is_empty() {
        column!(&t.bands, x0); column!(&t.bands, x1); column!(&t.bands, id); column!(&t.bands, color); column!(&t.bands, name); column!(&t.bands, row);
        column!(&t.bands, flags); column!(&t.bands, look); column!(&t.bands, tag); column!(&t.bands, sub);
        if band_columns(&t.bands) == BAND_FORM_COLUMNS {
            column!(&t.bands, form);
        }
    }
    if !t.cells.is_empty() {
        column!(&t.cells, x0); column!(&t.cells, x1); column!(&t.cells, id); column!(&t.cells, name); column!(&t.cells, row);
        for c in &t.cells {
            out.extend_from_slice(&(c.kind & 0xff | c.flags << 8).to_le_bytes());
        }
        column!(&t.cells, lane); column!(&t.cells, style); column!(&t.cells, color);
    }
    if !t.events.is_empty() {
        column!(&t.events, x0); column!(&t.events, x1); column!(&t.events, id); column!(&t.events, name); column!(&t.events, row); column!(&t.events, bits);
        column!(&t.events, look); column!(&t.events, label); column!(&t.events, rail); column!(&t.events, band);
    }
    if !t.pills.is_empty() {
        column!(&t.pills, x0); column!(&t.pills, x1); column!(&t.pills, count); column!(&t.pills, row);
        if pill_columns(&t.pills) == PILL_COLUMNS {
            column!(&t.pills, cats);
        }
    }
    for s in &t.sections {
        if s.items.is_empty() {
            continue;
        }
        column!(&s.items, x0); column!(&s.items, x1); column!(&s.items, id); column!(&s.items, name); column!(&s.items, row); column!(&s.items, flags);
        column!(&s.items, row2); column!(&s.items, reference); column!(&s.items, color);
        column!(&s.items, a); column!(&s.items, b); column!(&s.items, c); column!(&s.items, d); column!(&s.items, text2);
    }
    let mut offset = 0u32;
    for s in &t.strings {
        out.extend_from_slice(&offset.to_le_bytes());
        offset += s.len() as u32;
    }
    out.extend_from_slice(&offset.to_le_bytes());
    for s in &t.strings {
        out.extend_from_slice(s.as_bytes());
    }
    out.resize(out.len().div_ceil(4) * 4, 0);
    out
}

/// 구역 하나를 열 단위로 읽는다. 없는 열은 0으로 찬 배열 — 열이 빠진 옛 타일도 읽는다.
struct Columns<'a> { words: &'a [u32], count: usize, columns: usize }

impl Columns<'_> {
    fn u32s(&self, column: usize) -> Vec<u32> {
        if column >= self.columns {
            return vec![0; self.count];
        }
        self.words[column * self.count..(column + 1) * self.count].to_vec()
    }
    fn f32s(&self, column: usize) -> Vec<f32> {
        self.u32s(column).into_iter().map(f32::from_bits).collect()
    }
}

/// 검사 · 점검 도구가 쓰는 해독기. 화면(Dart) 쪽 해독기와 같은 약속을 따른다.
pub fn decode(bytes: &[u8]) -> Result<Decoded> {
    if bytes.len() < HEADER || bytes.len() % 4 != 0 {
        return Err("타일 바이트가 모자랍니다".into());
    }
    let head = &bytes[..HEADER];
    if u32::from_le_bytes(head[0..4].try_into()?) != MAGIC || u16::from_le_bytes(head[4..6].try_into()?) != VERSION {
        return Err("타일 표지 또는 판이 다릅니다".into());
    }
    let words: Vec<u32> = bytes.chunks_exact(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).collect();
    let int = |at: usize| u32::from_le_bytes(head[at..at + 4].try_into().unwrap());
    let long = |at: usize| i64::from_le_bytes(head[at..at + 8].try_into().unwrap());
    let mut t = Decoded { flags: u16::from_le_bytes(head[6..8].try_into()?), level: int(8) as i32, chunk: int(12) as i32, x: long(16), origin: long(24), span: long(32),
        cell_lod: int(52), ..Default::default() };
    let (n_sections, n_strings, text_bytes) = (int(40) as usize, int(44) as usize, int(48) as usize);
    let table_at = HEADER / 4;
    if table_at + SECTION_ENTRY_WORDS * n_sections > words.len() {
        return Err("구역 표가 타일 바깥을 가리킵니다".into());
    }
    let mut strings_at = table_at + SECTION_ENTRY_WORDS * n_sections;
    let mut table = Vec::with_capacity(n_sections);
    for i in 0..n_sections {
        let row = &words[table_at + SECTION_ENTRY_WORDS * i..];
        let (kind, count, columns, at) = (row[0], row[1] as usize, row[2] as usize, row[3] as usize);
        let end = at.checked_add(count.checked_mul(columns).ok_or("구역의 크기가 범위 밖입니다")?).ok_or("구역의 크기가 범위 밖입니다")?;
        if at < table_at + SECTION_ENTRY_WORDS * n_sections || end > words.len() {
            return Err("구역 자료가 타일 바깥을 가리킵니다".into());
        }
        strings_at = strings_at.max(end);
        table.push((kind, Columns { words: &words[at..end], count, columns }));
    }
    for (kind, c) in &table {
        match *kind {
            SEC_BAND => {
                let (x0, x1, id, color, name, row, flags, look, tag, sub) = (c.f32s(0), c.f32s(1), c.u32s(2), c.u32s(3), c.u32s(4), c.u32s(5), c.u32s(6), c.u32s(7), c.u32s(8), c.u32s(9));
                // `form`(열 10 · 스키마 4)은 form ≠ 0인 띠가 있는 타일에만 실린다 — 없는 열은 0(모름)으로 읽는다.
                let form = c.u32s(10);
                t.bands = (0..c.count).map(|i| Band { x0: x0[i], x1: x1[i], id: id[i], color: color[i], name: name[i], row: row[i], flags: flags[i], look: look[i], tag: tag[i], sub: sub[i],
                    form: form[i] }).collect();
            }
            SEC_CELL => {
                let (x0, x1, id, name, row, kind, lane, style, color) = (c.f32s(0), c.f32s(1), c.u32s(2), c.u32s(3), c.u32s(4), c.u32s(5), c.u32s(6), c.u32s(7), c.u32s(8));
                t.cells = (0..c.count).map(|i| CellItem { x0: x0[i], x1: x1[i], id: id[i], name: name[i], row: row[i], kind: kind[i] & 0xff, flags: kind[i] >> 8, lane: lane[i], style: style[i], color: color[i] }).collect();
            }
            SEC_EVENT => {
                let (x0, x1, id, name, row, bits, look, label, rail, band) = (c.f32s(0), c.f32s(1), c.u32s(2), c.u32s(3), c.u32s(4), c.u32s(5), c.u32s(6), c.u32s(7), c.u32s(8), c.u32s(9));
                t.events = (0..c.count).map(|i| EventItem { x0: x0[i], x1: x1[i], id: id[i], name: name[i], row: row[i], bits: bits[i], look: look[i], label: label[i], rail: rail[i], band: band[i] }).collect();
            }
            SEC_PILL => {
                // `cats`는 뒤에 더한 열이라 그 열이 없는 옛 타일에서는 0으로 읽힌다 — 0은 글자표의 첫 글자이므로 없는 열은 `NO_NAME`으로 돌려놓는다.
                let (x0, x1, count, row) = (c.f32s(0), c.f32s(1), c.u32s(2), c.u32s(3));
                let cats = if c.columns > 4 { c.u32s(4) } else { vec![NO_NAME; c.count] };
                t.pills = (0..c.count).map(|i| Pill { x0: x0[i], x1: x1[i], count: count[i], row: row[i], cats: cats[i] }).collect();
            }
            kind => {
                let (x0, x1, id, name, row, flags, row2, reference, color, a, b, cc, d, text2) =
                    (c.f32s(0), c.f32s(1), c.u32s(2), c.u32s(3), c.u32s(4), c.u32s(5), c.u32s(6), c.u32s(7), c.u32s(8), c.u32s(9), c.u32s(10), c.u32s(11), c.u32s(12), c.u32s(13));
                t.sections.push(Section { kind, items: (0..c.count).map(|i| Item { x0: x0[i], x1: x1[i], id: id[i], name: name[i], row: row[i], flags: flags[i],
                    row2: row2[i], reference: reference[i], color: color[i], a: a[i], b: b[i], c: cc[i], d: d[i], text2: text2[i] }).collect() });
            }
        }
    }
    if strings_at + n_strings + 1 > words.len() {
        return Err("글자표가 타일 바깥을 가리킵니다".into());
    }
    let offsets = &words[strings_at..strings_at + n_strings + 1];
    let text_at = (strings_at + n_strings + 1) * 4;
    let text = bytes.get(text_at..text_at + text_bytes).ok_or("타일 바이트가 모자랍니다")?;
    for pair in offsets.windows(2) {
        let piece = text.get(pair[0] as usize..pair[1] as usize).ok_or("글자표의 자리가 범위 밖입니다")?;
        t.strings.push(std::str::from_utf8(piece)?.to_owned());
    }
    Ok(t)
}

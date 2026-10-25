//! 트랙 단위로 고쳐 쓰기(계획 P4 '한 벌 체제') — DLC를 넣고 뺄 때 바뀐 트랙만 한 거래로 다시 쓴다.
//! 이 파일의 앞 절반(과제 4)은 **무엇을 다시 쓸지** 정한다. 실제 지우고 넣기(`apply`)는 뒤 절반(과제 5b ~ 6 — 5b 새 트랙 더하기 ·
//! 5c 다시 쓰기 · 사라지는 트랙 · DLC 빼기(같은 uid · 열쇠는 같은 번호 · 다른 트랙의 줄 옮겨 적기) · 5d 온 판 · 항목 기록 · 범위 · 표본 대조 ·
//! 6 이름 표 · 관점 이름 · 사건 덧줄 다시 펴기).
//!
//! - [`prints`]: 배치 JSON 3판(계약 4절)에서 트랙마다의 조각을 **번호 없이** 적어 SHA-256 지문을 낸다. 트랙 순번 · 자료집 순번 ·
//!   배열 자리(띠 번호 칸 · 가리기)는 열쇠 · uid · 내용으로 바꿔 적는다 — 다른 DLC가 앞에 끼어 순번이 밀려도 지문이 그대로이게.
//!   항목 기록(entities)은 트랙 조각에 넣지 않는다(계획 정한 것 #6 — 트랙 주인과 상관없이 따로 견준다).
//! - [`choose`]: 저장소의 지문(`track_prints`)과 새 지문을 견주어 다시 쓸 트랙을 고른다 — 지문이 다른 것 ∪ 새것 ∪
//!   (모두 덮으면) 사라진 것 ∪ 가리키던 uid가 생기거나 사라진 트랙(한 겹).
//! - [`sub_plan`]: 고른 트랙만 남긴 하위 배치(과제 5의 "insert"가 넣는다).
//! - [`check_combination`]: 메이커 배치가 다른 DLC를 조용히 지우지 않게 조합을 대조한다(`legacy::import_with`도 같은 몸을 쓴다).
//!
//! 트랙 조각(지문에 드는 것 — 번호를 바꿔 적은 꼴):
//! - 트랙 항목(줄 · 묶음 포함 · `pack` → 자료집 글자 id)
//! - `track`이 그 트랙인 띠 · 사건 · 일반 항목 · 줄 이름 · 날짜 칸 · 변형, 그 트랙 띠의 칸(칸은 띠 uid로 딸린다).
//!   `track` → 트랙 열쇠 · `pack` → 그 값이 실제로 들어갈 자료집의 글자 id(`legacy::fill`의 `pack_at`과 같은 규칙).
//! - 일반 항목 `a` ~ `d` 가운데 띠 번호 칸([`band_fields`] — '배치 `periods` 자리 + 1')은 그 띠의 uid로(0은 0 — 판정 R8).
//! - 변형의 줄(`track` · `toTrack`) · 이사 · 묶음의 트랙은 열쇠로(줄은 그 트랙 안 순번 그대로 — `(트랙 열쇠, 트랙 안 줄)`),
//!   `hides[].at`은 가리는 칸 · 항목의 **내용**(`hidden_content`의 꼴 — 하위 배치의 `outer.hides`와 같은 함수 · 판정 R19)으로.
//!   다른 트랙의 것도 가린다(판 변형은 원래 트랙의 칸 · 항목을 가린다 — 내보내기 `boards.mjs`) — 그 대상 트랙은 지문의 `hides`에 적어
//!   `choose`가 대상이 바뀌면 이 트랙도 다시 쓴다(판정 R16).
//! - 날짜 칸 이음 번호(`axis[].strip` — `export/axis.mjs`가 온 판에 한 번 세는 번호)는 **그 트랙 안 거리**로(갈래마다 — 연호 · 도읍과 배도 —
//!   그 트랙의 가장 작은 번호가 1, 0은 0)(판정 R45). 변형 `notes`의 '트랙 <순번>'은 트랙 열쇠로(조합 전부의 차례 — 하위 배치면 `allTracks`).
//!   앞에 트랙이 끼어도 뒤 트랙의 지문이 그대로다 — 다시 쓰지 않는 트랙의 저장소 번호 · notes 순번은 "relink"가 새 것으로 옮긴다([`renumber_strips`] · [`renumber_notes`]).
//! - 지문 판([`PRINT_FORM`])과 Rust 배치의 규칙 판([`crate::lay::rules`]) — 둘 중 하나가 바뀐 뒤의 첫 넣기는 모든 트랙 · 온 판을 다시 쓴다.
//!
//! 온 판 조각: `name` · `packs`(id · 이름 · 판 · 분류) · `categories` · `epochs` · 공통 날짜 칸(`track` −1) · `spheres` ·
//! `yearCycle(s)` · `blobs`(열쇠 · 자료집 · 종류 · 바이트 글의 SHA-256) · 문화권 단위 줄(`sphereLines` — 스키마 4 · 배치에 있을 때만 · 자료집은 글자 id) ·
//! 지문 판 · 규칙 판.
use crate::bandref::band_fields;
use crate::builder::{Appended, Builder, Floors};
use crate::grams;
use crate::legacy::{fill_into, int, int_or, list, pack_slot, plan_meta, text, version_text, wanted_packs, with_boards, FillHow, TrackFill};
use crate::rowmap::RowMap;
use crate::write::fail_point;
use crate::Result;
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::Instant;

/// 일반 항목의 칸 이름(`bandref`의 `A` ~ `D` 순번).
const FIELDS: [&str; 4] = ["a", "b", "c", "d"];
/// `track_prints`에서 온 판 지문의 열쇠.
pub const GLOBALS: &str = "*";
/// 판 트랙의 지문 열쇠 앞머리(`board:<트랙 열쇠>`).
const BOARD: &str = "board:";
/// 판 트랙의 열쇠 앞머리 — 내보내기(`boards.mjs`)의 약속(`__board:<변형 열쇠>`). 저장소 쪽은 이것으로 판 트랙을 가린다.
const BOARD_KEY: &str = "__board:";
/// 지문 판 — [`prints`]가 조각을 적는 규칙을 바꾸면 올린다. 트랙 · 온 판 지문에 Rust 배치의 규칙 판([`crate::lay::rules`])과 함께 섞여, 판이 바뀐 뒤의
/// 첫 넣기가 저장소의 모든 트랙 · 온 판을 다시 쓴다(설계 3-4 '규칙 판' — 옛 규칙으로 지문을 적은 저장소도 그렇게 한 번 다시 써진다).
/// 판 2(판정 R45): 날짜 칸 이음 번호는 트랙 안 거리로 · 변형 notes의 트랙 순번은 열쇠로.
/// 판 3(리메이크 3단계 · 스키마 4 — 계약 1-1): 온 판 조각에 문화권 단위 줄(`sphereLines` — 자료집 순번은 글자 id로)이 든다([`globals_print`]).
pub const PRINT_FORM: &str = "지문 3";
/// 하위 배치가 싣는 '조합 전부의 트랙마다 날짜 칸 이음 번호의 첫 값'의 겉 열쇠([`strip_firsts`]).
const STRIP_FIRST: &str = "stripFirst";

/// 트랙 하나의 지문.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackPrint {
    /// 트랙 조각의 SHA-256(16진 64자).
    pub print: String,
    /// 이 트랙이 가리키는 **다른 트랙의** 띠 · 사건 uid(일반 항목 `ref` · 띠 번호 칸 · 사건 `band` · 줄 이름의 띠 ·
    /// 변형의 이사 `ref` · 변형의 상위 띠). 배치에 없는 uid도 든다 — 그것이 생길 때 이 트랙을 다시 쓰려고.
    pub needs_uids: BTreeSet<String>,
    /// 이 트랙이 줄을 가리키는 다른 트랙의 열쇠(변형 줄의 `track` · `toTrack` · 이사 · 묶음).
    pub row_targets: BTreeSet<String>,
    /// 이 트랙의 띠 · 사건 uid(변형에서만 있는 것도).
    pub uids: BTreeSet<String>,
    /// 그 가운데 띠의 uid(같은 uid가 두 트랙에 있는지 저장소에서 볼 때 — [`choose`]의 빈틈 10 지킴).
    pub bands: BTreeSet<String>,
    /// 이 트랙의 변형이 칸 · 항목을 가리는 **다른** 트랙의 열쇠(판정 R16 — 그 트랙을 다시 쓰면 가리기 번호를 다시 풀려고 이 트랙도 다시 쓴다).
    pub hides: BTreeSet<String>,
}

/// 배치 하나의 지문.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prints {
    /// 트랙 열쇠 → 지문.
    pub tracks: BTreeMap<String, TrackPrint>,
    /// 온 판 조각의 SHA-256.
    pub globals: String,
    /// 트랙 열쇠를 배치의 트랙 차례대로(옛 트랙 → 판 트랙).
    pub order: Vec<String>,
}

/// 새 배치가 덮는 트랙.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Covers {
    /// 배치가 조합 전부다 — 배치에 없는 트랙은 사라진다(Node 배치 · `add-dlc.mjs`).
    All,
    /// 이 트랙들만 덮는다 — 그 밖의 트랙은 그대로 둔다(메이커 `.htlayout` — 계획 정한 것 #8).
    Tracks(BTreeSet<String>),
    /// 조합 전부를 말하되 트랙은 닿는 것(S)만 실은 하위 배치([`sub_plan`]의 꼴 — P4 과제 9의 `add_pack` · `remove_pack` · P3 과제 16 `Scope::Tracks(S)`).
    /// 온 판 · 항목 기록 · 자료집 · 트랙 차례는 `All`처럼 조합 전부의 것이다: `order`(새 조합의 트랙 열쇠 전부 · 차례대로 — 하위 배치의 `allTracks`)에 없는
    /// 저장소의 트랙은 사라지고(DLC 빼기도 받는다), `order`에 있고 S 밖인 트랙은 **그대로라고 믿는다**(부르는 쪽 `touched`의 약속 — 지문이 바뀌는 트랙은 다 S에 든다).
    /// S 밖인데 다시 써야 하는 트랙(가리키던 uid가 생기거나 사라짐 · 가리는 변형 · 저장소에 지문이 없음 · 저장소에 없는 새 트랙 · 서거나 사라지는 판의
    /// 구성 트랙과 가림 대상 — 판정 R54 I2)이 나오면 [`Widen`]으로 거절한다 —
    /// 부르는 쪽이 S를 넓혀 다시 배치한다(아무것도 쓰기 전 "choose"에서).
    Part { tracks: BTreeSet<String>, order: Vec<String> },
}

impl Covers {
    /// 조합 전부를 말하는가(`All` · `Part`) — 온 판 · 항목 기록 · 자료집 · 트랙 차례를 고쳐 적고 DLC 빼기를 받는다.
    pub fn whole(&self) -> bool {
        !matches!(self, Covers::Tracks(_))
    }
}

/// [`Covers::Part`]에서 S 밖인데 다시 써야 하는 트랙이 나와 거절한 것 — 이 트랙들을 더 실은 하위 배치로 다시 부르면 받는다(P4 과제 9의 넓히기).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Widen(pub BTreeSet<String>);

impl std::fmt::Display for Widen {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "함께 고쳐 쓸 트랙이 {}개 더 있습니다", self.0.len())
    }
}

impl std::error::Error for Widen {}

/// 고쳐 쓰는 도중에 '다시 쓰지 않는 트랙도 함께 다시 써야 함'이 드러난 거절(밖 변형이 저장소에 없음 · 남는 변형이 지울 칸 · 항목을 가림 · 다른 트랙의 변형이 사라지거나
/// 줄어든 트랙의 줄을 가리킴 · 가리는 것을 찾지 못함). 덮는 트랙만 주는 배치(메이커 `.htlayout`)에는 글 그대로의 안내('그 DLC까지 불러와 내보내기')이고,
/// 하위 배치(`Covers::Part` — 실제 틈의 넣고 빼기)는 쓰기 전에 알 수 없던 것이라 부르는 쪽(`packs::relayout`)이 거래를 되돌리고 모든 트랙으로 넓혀 다시 한다
/// (총괄 덧붙임 — 앱은 `.htlayout`을 받지 않으므로 그 안내는 넣고 빼기 길에서 그르다).
#[derive(Debug)]
pub struct NeedsWhole(pub String);

impl std::fmt::Display for NeedsWhole {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for NeedsWhole {}

fn needs_whole(msg: String) -> Box<dyn std::error::Error + Send + Sync> {
    Box::new(NeedsWhole(msg))
}

/// 같은 uid의 띠 · 사건이 두 트랙 이상에 있음(판정 R37) — uid → 그 트랙 열쇠들. [`apply`]가 DLC · 항목 이름을 단 쉬운 글의 거절(`code` dup_uid)로 바꾼다.
#[derive(Debug, Clone, PartialEq, Eq)]
struct SharedUids(BTreeMap<String, BTreeSet<String>>);

impl std::fmt::Display for SharedUids {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let list: Vec<String> = self.0.iter().map(|(u, keys)| format!("{u}({})", keys.iter().cloned().collect::<Vec<_>>().join(" · "))).collect();
        write!(f, "같은 항목이 두 트랙에 들어 있습니다: {}", list.join(" / "))
    }
}

impl std::error::Error for SharedUids {}

/// [`SharedUids`]를 쉬운 글의 거절로(판정 R37 — `code` dup_uid): 어느 DLC의 어느 트랙에 어느 항목이 겹치는지(앞 셋) — DLC를 만든 쪽에서 고칠 일이다.
/// 트랙 · DLC 이름은 배치에서, 하위 배치에 없는 트랙(S 밖)은 저장소에서 찾는다.
fn shared_refusal(db: &Connection, plan: &Value, shared: &SharedUids) -> Result<Box<dyn std::error::Error + Send + Sync>> {
    let declared = list(plan, "packs");
    let packs = Packs::new(plan);
    let dlc_name = |id: &str| -> String {
        declared.iter().find(|p| text(p, "id") == id).map(|p| text(p, "name")).filter(|n| !n.is_empty()).unwrap_or(id).to_owned()
    };
    let mut places: HashMap<String, String> = HashMap::new();
    for (i, t) in with_boards(plan, "tracks").into_iter().enumerate() {
        places.insert(track_key(plan, i), format!("{}의 «{}»", dlc_name(packs.of(t, "")), text(t, "name")));
    }
    let mut stored = db.prepare("SELECT t.name,p.name FROM tracks t JOIN packs p ON p.id=t.pack WHERE t.key=?1")?;
    let mut names: HashMap<&str, &str> = HashMap::new();
    for p in with_boards(plan, "periods") {
        names.entry(text(p, "uid")).or_insert(text(p, "name"));
    }
    for e in with_boards(plan, "events") {
        names.entry(text(e, "uid")).or_insert(text(e, "title"));
    }
    let mut lines = Vec::new();
    for (uid, keys) in shared.0.iter().take(3) {
        let what = match names.get(uid.as_str()).filter(|n| !n.is_empty()) {
            Some(name) => format!("«{name}»({uid})"),
            None => format!("«{uid}»"),
        };
        let mut wheres = Vec::new();
        for key in keys {
            let place = match places.get(key) {
                Some(place) => place.clone(),
                None => match key.strip_prefix("n:").and_then(|rest| rest.split_once('|')) {
                    // 열쇠 없는 트랙(`n:<DLC id>|<이름>`) — 이름과 DLC id로.
                    Some((pack, name)) => format!("{}의 «{name}»", dlc_name(pack)),
                    None => stored.query_row([key.trim_start_matches(BOARD)], |r| Ok(format!("{}의 «{}»", r.get::<_, String>(1)?, r.get::<_, String>(0)?)))
                        .optional()?.unwrap_or_else(|| format!("«{key}»")),
                },
            };
            wheres.push(place);
        }
        lines.push(format!("{what} — {}", wheres.join(" · ")));
    }
    let more = if shared.0.len() > 3 { format!(" 외 {}개", shared.0.len() - 3) } else { String::new() };
    Ok(refuse("dup_uid", format!("같은 항목이 두 트랙에 들어 있어 이 DLC 조합으로는 고쳐 쓸 수 없습니다: {}{more} — 한 항목은 한 트랙에만 있어야 합니다. \
        그 DLC를 만든 쪽에서 고쳐야 합니다(저장소는 그대로)", lines.join(" / "))))
}

/// 다시 쓸 트랙.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Choice {
    /// 저장소에 있고 다시 쓸 트랙(지문이 다르거나 · 지문이 없거나 · 가리키던 uid가 생기거나 사라진 것).
    pub rewrite: BTreeSet<String>,
    /// 저장소에 없던 트랙.
    pub added: BTreeSet<String>,
    /// 사라질 트랙(`Covers::All`일 때만).
    pub removed: BTreeSet<String>,
    /// 온 판 지문이 다르다(또는 저장소에 없다).
    pub globals: bool,
    /// 다시 쓰거나 빼는 트랙에서 사라지는 uid · 다시 쓰거나 더하는 트랙에서 새로 생기는 uid.
    pub uids_gone: BTreeSet<String>,
    pub uids_new: BTreeSet<String>,
}

// ---------------------------------------------------------------- 배치 읽기

/// 자료집 순번 → 글자 id(비면 이름). `legacy::fill`의 `pack_at`과 같은 규칙으로 값의 자료집을 찾는다.
struct Packs<'a> {
    labels: Vec<String>,
    /// 글자 id → 순번(uid 앞머리로 찾을 때).
    heads: HashMap<&'a str, usize>,
}

impl<'a> Packs<'a> {
    fn new(plan: &'a Value) -> Self {
        let declared = list(plan, "packs");
        let labels = declared.iter().map(|p| {
            let id = text(p, "id");
            if id.is_empty() { text(p, "name").to_owned() } else { id.to_owned() }
        }).collect();
        let heads = declared.iter().enumerate().filter_map(|(i, p)| p["id"].as_str().filter(|id| !id.is_empty()).map(|id| (id, i))).collect();
        Self { labels, heads }
    }

    /// 그 값이 들어갈 자료집: `pack` 순번 → uid의 앞머리(`<DLC id>/…`) → 첫 자료집(`legacy::pack_slot` — 짓기와 같은 규칙). 자료집 목록이 없는 옛 배치는 빈 글.
    fn of(&self, v: &Value, uid: &str) -> &str {
        let slot = pack_slot(v, uid, self.labels.len(), |head| self.heads.get(head).copied());
        self.labels.get(slot).map(String::as_str).unwrap_or("")
    }
}

/// 트랙의 열쇠(판 앞머리 없이): `key`, 비면 `n:<자료집>|<이름>`.
fn plain_key(t: &Value, pack: &str) -> String {
    let key = text(t, "key");
    if key.is_empty() { format!("n:{pack}|{}", text(t, "name")) } else { key.to_owned() }
}

/// 배치의 트랙 열쇠 전부 — 옛 트랙 → 판 트랙 차례([`track_key`]).
pub fn track_keys(plan: &Value) -> Vec<String> {
    (0..with_boards(plan, "tracks").len()).map(|i| track_key(plan, i)).collect()
}

/// 트랙의 글자 열쇠: `tracks[].key`, 비면 `"n:<자료집 id>|<이름>"`(앱 `trackIdentity`와 같은 뜻), 판 트랙(겉 열쇠 `boards`의 트랙)은
/// `"board:<열쇠>"`. `index`는 옛 트랙 뒤에 판 트랙을 이은 순번(계약 4절) — 없는 순번이면 빈 글.
pub fn track_key(plan: &Value, index: usize) -> String {
    let tracks = with_boards(plan, "tracks");
    let Some(t) = tracks.get(index) else { return String::new() };
    let packs = Packs::new(plan);
    let key = plain_key(t, packs.of(t, ""));
    if index >= list(plan, "tracks").len() { format!("{BOARD}{key}") } else { key }
}

/// 트랙 순번 → 트랙(없으면 Err — `fill`도 그 배치를 거절한다).
fn track_index(len: usize, at: i64, what: &str) -> Result<usize> {
    usize::try_from(at).ok().filter(|t| *t < len).ok_or_else(|| format!("{what}의 트랙이 배치에 없습니다: {at}").into())
}

/// 배치를 트랙 단위로 보는 눈 — 트랙 열쇠 · 띠 uid의 트랙 · 칸 · 항목의 자리를 한 번 셈해 둔다.
struct View<'a> {
    packs: Packs<'a>,
    tracks: Vec<&'a Value>,
    keys: Vec<String>,
    /// `with_boards`로 이은 띠 · 칸 · 일반 항목(띠 번호 칸과 `hides[].at`이 이 자리를 가리킨다).
    periods: Vec<&'a Value>,
    cells: Vec<&'a Value>,
    items: Vec<&'a Value>,
    /// 띠 uid → 트랙 순번(같은 uid가 둘이면 뒤의 것 — `fill`의 `period_of`와 같다).
    period_track: HashMap<&'a str, usize>,
}

impl<'a> View<'a> {
    fn new(plan: &'a Value) -> Result<Self> {
        let packs = Packs::new(plan);
        let regular = list(plan, "tracks").len();
        let tracks = with_boards(plan, "tracks");
        let mut keys = Vec::with_capacity(tracks.len());
        let mut seen = HashSet::new();
        for (i, t) in tracks.iter().enumerate() {
            let own = plain_key(t, packs.of(t, ""));
            // 저장소 쪽([`stored_tracks`])은 열쇠의 앞머리로 판 트랙을 가린다 — 두 쪽이 어긋나면 같은 트랙을 '사라짐 + 새것'으로 본다.
            let board = i >= regular;
            if board != own.starts_with(BOARD_KEY) {
                return Err(if board {
                    format!("판 트랙의 열쇠가 {BOARD_KEY}로 시작하지 않습니다: {own}")
                } else {
                    format!("판이 아닌 트랙의 열쇠가 {BOARD_KEY}로 시작합니다: {own}")
                }.into());
            }
            let key = if board { format!("{BOARD}{own}") } else { own };
            if !seen.insert(key.clone()) {
                return Err(format!("트랙 열쇠가 겹칩니다: {key}").into());
            }
            keys.push(key);
        }
        let periods = with_boards(plan, "periods");
        let mut period_track = HashMap::new();
        for p in &periods {
            period_track.insert(text(p, "uid"), track_index(tracks.len(), int(p, "track"), "띠")?);
        }
        Ok(Self { packs, tracks, keys, periods, cells: with_boards(plan, "cells"), items: with_boards(plan, "items"), period_track })
    }

    fn track_at(&self, at: i64, what: &str) -> Result<usize> {
        track_index(self.tracks.len(), at, what)
    }

    fn track_of(&self, v: &Value, what: &str) -> Result<usize> {
        self.track_at(int(v, "track"), what)
    }

    /// 칸의 트랙 = 그 칸이 든 띠의 트랙.
    fn cell_track(&self, c: &Value) -> Result<usize> {
        self.period_track.get(text(c, "period")).copied().ok_or_else(|| "칸이 가리키는 띠가 배치에 없습니다".into())
    }

    /// 띠 번호(`periods` 자리 + 1) → 띠 uid.
    fn band_uid(&self, item: &Value, field: &str, number: i64) -> Result<&'a str> {
        usize::try_from(number - 1).ok().and_then(|i| self.periods.get(i).copied()).map(|p| text(p, "uid"))
            .ok_or_else(|| format!("일반 항목(구역 {})의 띠 번호 {field} = {number}이 배치의 띠를 벗어납니다", int(item, "section")).into())
    }

    /// 일반 항목의 띠 번호 칸(값이 0이 아닌 것) — (칸 이름, 띠 uid). 하위 배치([`sub_plan`])의 항목은 그 칸을 0으로 비우고 띠 uid를 `bandUids`에 달아 오므로
    /// (판정 R14) 그것을 읽는다 — 통째 배치와 하위 배치가 같은 답을 낸다(지문 · 가림 내용 · 하위 배치를 다시 하위 배치로 — P4 과제 9).
    fn band_refs<'v>(&self, it: &'v Value) -> Result<Vec<(&'static str, &'v str)>>
    where
        'a: 'v,
    {
        let mut out = Vec::new();
        if let Some(uids) = it["bandUids"].as_object() {
            for field in FIELDS {
                if let Some(uid) = uids.get(field).and_then(Value::as_str) {
                    out.push((field, uid));
                }
            }
            return Ok(out);
        }
        for f in band_fields(int(it, "section"), int(it, "a"), int(it, "b"), int(it, "c"), int(it, "d")) {
            let field = FIELDS[f];
            let number = int(it, field);
            if number != 0 {
                out.push((field, self.band_uid(it, field, number)?));
            }
        }
        Ok(out)
    }

    /// 변형의 줄 · 이사 · 묶음이 가리키는 트랙(`track` · `toTrack` 칸): 수면 이 배치의 트랙 순번, 글이면 하위 배치 밖 트랙의 열쇠(`sub_plan`의 `outer.*`).
    fn place_of(&self, v: &Value, field: &str, what: &str) -> Result<Place> {
        match v[field].as_str() {
            Some(key) => Ok(Place::Key(key.to_owned())),
            None => Ok(Place::At(self.track_at(int(v, field), what)?)),
        }
    }

    /// 그 자리의 트랙 열쇠.
    fn key_of<'p>(&'p self, p: &'p Place) -> &'p str {
        match p {
            Place::At(t) => &self.keys[*t],
            Place::Key(key) => key,
        }
    }

    /// 번호 없이 적은 값 하나 — `track` → 열쇠 · `pack` → 들어갈 자료집의 글자 id.
    fn plain(&self, v: &Value, track: usize, uid: &str) -> Value {
        let mut out = v.clone();
        out["track"] = json!(self.keys[track]);
        out["pack"] = json!(self.packs.of(v, uid));
        out
    }

    /// 일반 항목을 번호 없이 — 띠 번호 칸은 띠 uid로(하위 배치의 `bandUids`는 떼고 그 칸에).
    fn plain_item<'v>(&self, it: &'v Value, track: usize) -> Result<(Value, Vec<&'v str>)>
    where
        'a: 'v,
    {
        let mut out = self.plain(it, track, "");
        if let Some(o) = out.as_object_mut() {
            o.remove("bandUids");
        }
        let mut bands = Vec::new();
        for (field, uid) in self.band_refs(it)? {
            out[field] = json!(uid);
            bands.push(uid);
        }
        Ok((out, bands))
    }
}

/// 변형 원소가 가리키는 트랙 — 이 배치의 트랙 순번 또는 하위 배치 밖 트랙의 열쇠.
enum Place {
    At(usize),
    Key(String),
}

/// 변형의 목록 하나(`rows` · `moves` · `groups`)를 원래 차례로 — 하위 배치면 S 안 원소(제 목록)와 S 밖 원소(`outer.<목록>` · `"at"` = 원래 자리)를 섞는다
/// (`legacy::merged`와 같은 규칙).
fn full_list<'v>(v: &'v Value, name: &str) -> Vec<&'v Value> {
    crate::legacy::merged(list(v, name), list(&v["outer"], name))
}

/// 변형의 가림 하나 — S 안 것(`hides[]` — 이 배치의 칸 · 항목 자리 `at`) 또는 S 밖 것(`outer.hides[]` — 가리는 것의 내용과 그 주인 트랙의 열쇠).
enum Hide<'v> {
    Inner(&'v Value),
    Outer(&'v Value, &'v str),
}

/// 변형의 가림을 원래 차례로 — S 밖 것은 `outer.hideAt`(원래 자리) · `outer.hideOwners`(주인 트랙 열쇠)가 `outer.hides`와 나란히 온다([`sub_plan`]).
fn full_hides(v: &Value) -> Result<Vec<Hide<'_>>> {
    let (inner, outer) = (list(v, "hides"), list(&v["outer"], "hides"));
    let (at, owners) = (list(&v["outer"], "hideAt"), list(&v["outer"], "hideOwners"));
    if outer.len() != owners.len() {
        return Err(format!("배치가 어긋났습니다: 변형 «{}»이 다른 트랙에서 가리는 것 {}개에 그 트랙이 {}개만 적혀 있습니다(배치를 낸 쪽의 잘못)", text(v, "key"), outer.len(), owners.len()).into());
    }
    let total = inner.len() + outer.len();
    let mut slots: Vec<Option<Hide>> = (0..total).map(|_| None).collect();
    let mut stray = Vec::new();
    for (j, h) in outer.iter().enumerate() {
        let owner = owners[j].as_str().unwrap_or("");
        match at.get(j).and_then(Value::as_u64).map(|i| i as usize).filter(|i| *i < total) {
            Some(i) if slots[i].is_none() => slots[i] = Some(Hide::Outer(h, owner)),
            _ => stray.push(Hide::Outer(h, owner)),
        }
    }
    let mut rest = inner.iter();
    for slot in slots.iter_mut().filter(|s| s.is_none()) {
        *slot = rest.next().map(Hide::Inner);
    }
    Ok(slots.into_iter().flatten().chain(rest.map(Hide::Inner)).chain(stray).collect())
}

// ---------------------------------------------------------------- 지문

/// 트랙 하나의 조각을 모으는 그릇.
#[derive(Default)]
struct Acc {
    hash: Sha256,
    needs: BTreeSet<String>,
    /// 이 트랙의 변형이 줄을 가리키는 트랙의 열쇠(하위 배치 밖 트랙도 열쇠로 오므로 열쇠로 모은다).
    rows: BTreeSet<String>,
    own: BTreeSet<String>,
    bands: BTreeSet<String>,
    /// 이 트랙의 변형이 가리는 칸 · 항목의 트랙 열쇠.
    hides: BTreeSet<String>,
}

impl Acc {
    /// 조각에 값 하나를 더한다(갈래 이름 · 탭 · JSON · 줄바꿈 — JSON 글에는 날 줄바꿈이 없어 경계가 모호하지 않다).
    fn feed(&mut self, tag: &str, v: &Value) -> Result<()> {
        self.hash.update(tag.as_bytes());
        self.hash.update(b"\t");
        serde_json::to_writer(&mut self.hash, v)?;
        self.hash.update(b"\n");
        Ok(())
    }

    /// 가리키는 uid — 제 것이 아니면 needs에.
    fn need(&mut self, uid: &str) {
        if !uid.is_empty() && !self.own.contains(uid) {
            self.needs.insert(uid.to_owned());
        }
    }
}

/// 배치의 트랙마다 · 온 판의 지문(모듈 머리글의 '트랙 조각' · '온 판 조각').
/// 변형이 **다른 트랙의** 칸 · 항목을 가리면 그 대상 트랙을 `hides`에 적는다(판정 R16).
/// 트랙 열쇠가 겹치거나 판 트랙의 열쇠가 약속(`__board:`)과 어긋나도 Err.
/// 하위 배치([`sub_plan`] — P3 과제 16 `Scope::Tracks(S)`의 출력)도 받는다: 그 트랙의 지문은 통째 배치의 같은 트랙 지문과 **같다**(P4 과제 9 — 띠 번호 칸은 `bandUids`로,
/// 변형의 S 밖 줄 · 이사 · 묶음 · 가림은 `outer`에서 원래 자리로 되돌려 같은 조각을 적는다). 온 판 지문도 같다(하위 배치는 온 판을 통째로 싣는다).
pub fn prints(plan: &Value) -> Result<Prints> {
    prints_under(plan, &rules_mark())
}

/// 지금의 지문 판 · 규칙 판([`PRINT_FORM`] · [`crate::lay::rules`]) — 트랙마다 · 온 판 조각의 맨 앞에 든다.
pub fn rules_mark() -> String {
    format!("{PRINT_FORM} {}", crate::lay::rules())
}

/// [`prints`]를 규칙 판 글 `rules`로 셈한다 — 검사가 옛 규칙 판으로 지문을 적은 저장소를 흉내 낼 때(지금 판은 [`rules_mark`]).
pub fn prints_under(plan: &Value, rules: &str) -> Result<Prints> {
    let view = View::new(plan)?;
    let mut acc: Vec<Acc> = (0..view.tracks.len()).map(|_| Acc::default()).collect();
    let mark = json!(rules);
    for a in &mut acc {
        a.feed("rules", &mark)?;
    }
    // 변형 notes의 트랙 순번 → 열쇠: 조합 전부의 차례(하위 배치의 notes는 통째 배치의 순번을 그대로 싣는다).
    let all: Vec<String> = match plan["allTracks"].as_array() {
        Some(l) => l.iter().map(|k| k.as_str().unwrap_or("").to_owned()).collect(),
        None => view.keys.clone(),
    };
    let events = with_boards(plan, "events");
    // 제 uid 먼저 — 남의 것을 가리는 데 쓴다.
    for p in &view.periods {
        let t = view.track_of(p, "띠")?;
        add_own(&mut acc[t], text(p, "uid"));
        if !text(p, "uid").is_empty() {
            acc[t].bands.insert(text(p, "uid").to_owned());
        }
    }
    for e in &events {
        let t = view.track_of(e, "사건")?;
        add_own(&mut acc[t], text(e, "uid"));
    }
    for (i, t) in view.tracks.iter().enumerate() {
        let mut out = (*t).clone();
        out["pack"] = json!(view.packs.of(t, ""));
        acc[i].feed("track", &out)?;
    }
    for p in &view.periods {
        let t = view.track_of(p, "띠")?;
        acc[t].feed("period", &view.plain(p, t, text(p, "uid")))?;
    }
    for c in &view.cells {
        let t = view.cell_track(c)?;
        acc[t].feed("cell", c)?;
    }
    for e in &events {
        let t = view.track_of(e, "사건")?;
        acc[t].need(text(e, "band"));
        acc[t].feed("event", &view.plain(e, t, text(e, "uid")))?;
    }
    for it in &view.items {
        let t = view.track_of(it, "일반 항목")?;
        let (out, bands) = view.plain_item(it, t)?;
        acc[t].need(text(it, "ref"));
        for uid in bands {
            acc[t].need(uid);
        }
        acc[t].feed("item", &out)?;
    }
    for l in with_boards(plan, "rowLabels") {
        let t = view.track_of(l, "줄 이름")?;
        acc[t].need(text(l, "period"));
        // 줄 이름에는 자료집이 없다(`fill`이 원소 JSON을 통째로 싣는다) — 트랙만 열쇠로.
        let mut out = l.clone();
        out["track"] = json!(view.keys[t]);
        acc[t].feed("label", &out)?;
    }
    // 날짜 칸은 겉 열쇠 `boards`에 없다(`fill`과 같다). track −1(또는 빠짐)은 공통 줄 — 온 판 조각에 든다.
    // 이음 번호는 그 트랙 · 갈래의 가장 작은 번호에서 잰 거리 + 1로(온 판 번호가 새지 않게 — 모듈 머리글).
    let axis = list(plan, "axis");
    let firsts = strip_mins(axis);
    for a in axis {
        let at = int_or(a, "track", -1);
        if at >= 0 {
            let t = view.track_at(at, "날짜 칸")?;
            let mut out = view.plain(a, t, "");
            let strip = int(a, "strip");
            if strip != 0 {
                out["strip"] = json!(strip - firsts[&(at, strip_class(int(a, "kind")))] + 1);
            }
            acc[t].feed("axis", &out)?;
        }
    }
    for v in with_boards(plan, "variants") {
        let t = view.track_of(v, "변형")?;
        let out = plain_variant(&view, v, t, &mut acc[t], &all)?;
        acc[t].feed("variant", &out)?;
    }
    let mut tracks = BTreeMap::new();
    for (i, a) in acc.into_iter().enumerate() {
        let others = |set: &BTreeSet<String>| -> BTreeSet<String> { set.iter().filter(|k| **k != view.keys[i]).cloned().collect() };
        let (row_targets, hides) = (others(&a.rows), others(&a.hides));
        tracks.insert(view.keys[i].clone(), TrackPrint { print: format!("{:x}", a.hash.finalize()), needs_uids: a.needs, row_targets, uids: a.own, bands: a.bands, hides });
    }
    Ok(Prints { tracks, globals: globals_print(plan, &view.packs, rules)?, order: view.keys })
}

/// 날짜 칸 이음 번호의 갈래 — 연호(kind 2)는 온 판의 앞 덩이(연호 줄 전부)에서, 도읍 · 배도(3 · 4)는 뒤 덩이(도읍 줄 전부)에서 센다(`export/axis.mjs`).
fn strip_class(kind: i64) -> usize {
    usize::from(kind != 2)
}

/// 날짜 칸(`axis`)의 (트랙 순번, 갈래)마다 가장 작은 이음 번호(0이 아닌 것). 공통 줄(track −1)은 뺀다.
fn strip_mins(axis: &[Value]) -> HashMap<(i64, usize), i64> {
    let mut out: HashMap<(i64, usize), i64> = HashMap::new();
    for a in axis {
        let (at, strip) = (int_or(a, "track", -1), int(a, "strip"));
        if at >= 0 && strip != 0 {
            let first = out.entry((at, strip_class(int(a, "kind")))).or_insert(strip);
            *first = (*first).min(strip);
        }
    }
    out
}

/// 배치가 아는 트랙마다 날짜 칸 이음 번호의 첫 값 `[연호, 도읍 · 배도]`(그 갈래의 가장 작은 번호 · 없으면 0 — 둘 다 0인 트랙은 뺀다)(판정 R45).
/// 날짜 칸이 실린 트랙은 그 칸에서, 하위 배치가 덜어 낸 트랙은 겉의 `stripFirst`([`sub_plan`]이 조합 전부의 것을 적는다)에서. 다시 쓰지 않는 트랙의
/// 저장소 번호를 이 값으로 옮긴다([`renumber_strips`] — 지문은 트랙 안 거리만 보므로 거리는 같고 첫 값만 다를 수 있다).
pub fn strip_firsts(plan: &Value) -> Result<BTreeMap<String, [i64; 2]>> {
    let mut out: BTreeMap<String, [i64; 2]> = BTreeMap::new();
    for (key, v) in plan[STRIP_FIRST].as_object().into_iter().flatten() {
        out.insert(key.clone(), [v[0].as_i64().unwrap_or(0), v[1].as_i64().unwrap_or(0)]);
    }
    let regular = list(plan, "tracks").len();
    for ((at, class), first) in strip_mins(list(plan, "axis")) {
        let t = track_index(regular, at, "날짜 칸")?;
        out.entry(track_key(plan, t)).or_insert([0, 0])[class] = first;
    }
    Ok(out)
}

/// 변형 notes 글의 '트랙 <순번>'(뒤가 빈칸이나 '의' — `export/variants.mjs` · `boards.mjs`의 줄 쌓기 점검 글) → '트랙 «<열쇠>»'(판정 R45).
/// 순번이 `keys` 밖이면 그대로.
fn notes_by_key(text: &str, keys: &[String]) -> String {
    notes_tracks(text, |i| keys.get(i).map(|k| format!("«{k}»")))
}

/// notes 글의 '트랙 <순번>'(뒤가 빈칸이나 '의')마다 `f(순번)`이 주는 글로 바꾼다(None이면 그대로) — [`notes_by_key`] · [`renumber_notes`]가 함께.
fn notes_tracks(text: &str, f: impl Fn(usize) -> Option<String>) -> String {
    const HEAD: &str = "트랙 ";
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find(HEAD) {
        out.push_str(&rest[..at + HEAD.len()]);
        rest = &rest[at + HEAD.len()..];
        let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
        let tail = &rest[digits..];
        let new = (digits > 0 && (tail.starts_with(' ') || tail.starts_with('의'))).then(|| rest[..digits].parse::<usize>().ok()).flatten().and_then(&f);
        if let Some(n) = new {
            out.push_str(&n);
            rest = tail;
        }
    }
    out.push_str(rest);
    out
}

fn add_own(acc: &mut Acc, uid: &str) {
    if !uid.is_empty() {
        acc.own.insert(uid.to_owned());
    }
}

/// 변형 하나를 번호 없이 — 줄 · 이사 · 묶음의 트랙은 열쇠로, 가리기는 가리는 것의 내용으로. 가리키는 것을 `acc`에 적는다.
/// 하위 배치의 변형이면 S 밖 원소(`outer`)를 원래 자리로 되돌려 통째 배치와 같은 조각을 적는다([`full_list`] · [`full_hides`] — `outer` · 원소의 `at`은 조각에 넣지 않는다).
/// `notes`의 트랙 순번은 `all`(조합 전부의 트랙 열쇠 — 차례대로)로 열쇠가 된다([`notes_by_key`]).
fn plain_variant(view: &View, v: &Value, own: usize, acc: &mut Acc, all: &[String]) -> Result<Value> {
    let mut out = v.clone();
    if let Some(o) = out.as_object_mut() {
        o.remove("outer");
    }
    out["track"] = json!(view.keys[own]);
    if let Some(notes) = v["notes"].as_str().filter(|t| t.contains("트랙 ")) {
        out["notes"] = json!(notes_by_key(notes, all));
    }
    // 하위 배치 밖 원소에만 붙는 원래 자리(`at`)를 떼고 트랙 칸을 열쇠로.
    let plain = |x: &Value, field: &str, what: &str, acc: &mut Acc| -> Result<Value> {
        let mut y = x.clone();
        if let Some(o) = y.as_object_mut() {
            o.remove("at");
        }
        let t = view.place_of(x, field, what)?;
        let key = view.key_of(&t).to_owned();
        y[field] = json!(key);
        acc.rows.insert(key);
        Ok(y)
    };
    let mut rows = Vec::new();
    for r in full_list(v, "rows") {
        let mut x = plain(r, "track", "변형의 줄", acc)?;
        // after −2(그 변형에서 빠지는 줄)의 `toTrack` · `to` — 판 줄로 옮겨 간 자리(`fill`과 같은 조건에서만 읽는다).
        if int_or(r, "after", -1) == -2 && r["to"].as_i64().is_some() {
            let to = view.place_of(r, "toTrack", "변형의 옮겨 간 줄")?;
            let key = view.key_of(&to).to_owned();
            x["toTrack"] = json!(key);
            acc.rows.insert(key);
        }
        rows.push(x);
    }
    let mut moves = Vec::new();
    for m in full_list(v, "moves") {
        moves.push(plain(m, "track", "변형의 이사", acc)?);
        acc.need(text(m, "ref"));
    }
    let mut groups = Vec::new();
    for g in full_list(v, "groups") {
        groups.push(plain(g, "track", "변형의 묶음", acc)?);
    }
    let mut hides = Vec::new();
    for h in full_hides(v)? {
        // 다른 트랙의 것을 가려도 된다(판 변형은 원래 트랙의 칸 · 항목을 가린다 — `boards.mjs`) — 그 트랙을 다시 쓰면 가리기 번호가
        // 낡으므로 대상 트랙을 적어 두고 `choose`가 이 트랙도 다시 쓰게 한다(판정 R16).
        match h {
            Hide::Inner(h) => {
                let (owner, content) = hidden_content(view, int(h, "kind"), int(h, "at"))?;
                acc.hides.insert(view.keys[owner].clone());
                hides.push(content);
            }
            Hide::Outer(content, owner) => {
                if owner.is_empty() {
                    return Err(format!("배치가 어긋났습니다: 변형 «{}»이 다른 트랙에서 가리는 것에 그 트랙이 적혀 있지 않습니다(배치를 낸 쪽의 잘못)", text(v, "key")).into());
                }
                acc.hides.insert(owner.to_owned());
                hides.push(content.clone());
            }
        }
    }
    acc.need(text(v, "band"));
    out["rows"] = json!(rows);
    out["moves"] = json!(moves);
    out["groups"] = json!(groups);
    out["hides"] = json!(hides);
    Ok(out)
}

/// 가리기가 가리키는 자리(`cells` · `items`에서 0부터).
fn hidden<'a>(list: &[&'a Value], at: i64) -> Result<&'a Value> {
    usize::try_from(at).ok().and_then(|i| list.get(i)).copied().ok_or_else(|| format!("변형이 가리키는 자리가 범위 밖입니다: {at}").into())
}

/// 가려지는 칸 · 항목 하나의 **내용**(판정 R16 · R19) — 그 원소의 트랙과 함께. 지문의 가림과 하위 배치의 `outer.hides`가 함께 쓴다
/// (과제 5c는 S 밖 것의 번호를 이 내용으로 저장소에서 찾는다 — 같은 내용이 여럿이면 하나씩 짝짓기는 5c 몫).
/// - 칸 `{"kind":3,"variant","period":<띠 uid>,"cellKind","lane","start","end","name"}`
/// - 항목 `{"kind":4,"variant","track":<트랙 열쇠>,"row","row2"(트랙 안 줄 — 빠지면 row),"section","ref","start","end","name","color",
///   "lod"(빠지면 −1),"a","b","c","d"(띠 번호 칸은 띠 uid 글),"text2"}`
///
/// `variant`는 그 원소에 달린 변형 열쇠 — 가려지는 것은 기본 판이라 늘 빈 글이다(같은 내용의 변형 판 칸 · 판 트랙의 항목과 가른다).
/// 모양 · 색만 바뀐 변형 판 칸은 띠 · 종류 · 단 · 시작 · 끝 · 이름이 기본 칸과 같고(`boards.mjs`의 `cellKeyOf` · `cellSameOf`),
/// 판 트랙의 항목은 트랙 · 줄 · 변형만 다를 수 있다(`boards.mjs`의 `sig`).
fn hidden_content(view: &View, kind: i64, at: i64) -> Result<(usize, Value)> {
    match kind {
        3 => {
            let c = hidden(&view.cells, at)?;
            Ok((view.cell_track(c)?, json!({"kind":3,"variant":text(c, "variant"),"period":text(c, "period"),"cellKind":int(c, "kind"),
                "lane":int(c, "lane"),"start":int(c, "start"),"end":int(c, "end"),"name":text(c, "name")})))
        }
        4 => {
            let it = hidden(&view.items, at)?;
            let t = view.track_of(it, "일반 항목")?;
            let row2 = if it["row2"].is_null() { int(it, "row") } else { int(it, "row2") };
            let mut out = json!({"kind":4,"variant":text(it, "variant"),"track":view.keys[t],"row":int(it, "row"),"row2":row2,
                "section":int(it, "section"),"ref":text(it, "ref"),"start":int(it, "start"),"end":int(it, "end"),"name":text(it, "name"),
                "color":int(it, "color"),"lod":int_or(it, "lod", -1),"a":int(it, "a"),"b":int(it, "b"),"c":int(it, "c"),"d":int(it, "d"),
                "text2":text(it, "text2")});
            for (field, uid) in view.band_refs(it)? {
                out[field] = json!(uid);
            }
            Ok((t, out))
        }
        _ => Err(format!("모르는 변형 가리기의 갈래: {kind}").into()),
    }
}

/// 온 판 조각의 SHA-256(규칙 판 글 `rules` 포함 — [`prints_under`]).
/// 문화권 단위 줄(`sphereLines` — 스키마 4 · 계약 1-1)은 배치에 그 열쇠가 있을 때만 싣는다(없는 배치의 조각은 지문 판 말고는 판 2와 같은 꼴).
/// 원소의 `pack` 순번은 그 값이 들어갈 자료집의 글자 id로 바꿔 적는다(`legacy::pack_slot` — 짓기와 같은 규칙: 순번 → uid 앞머리 → 기본팩) —
/// 가운데 DLC가 빠져 순번이 밀려도 줄의 조각은 그대로이게(트랙 조각의 `pack`과 같은 까닭).
fn globals_print(plan: &Value, packs: &Packs, rules: &str) -> Result<String> {
    let declared: Vec<Value> = list(plan, "packs").iter().map(|p| json!({"id":p["id"],"name":p["name"],"version":p["version"],"category":p["category"]})).collect();
    let axis: Vec<Value> = list(plan, "axis").iter().filter(|a| int_or(a, "track", -1) < 0).map(|a| {
        let mut out = a.clone();
        out["pack"] = json!(packs.of(a, ""));
        out
    }).collect();
    let blobs: Vec<Value> = list(plan, "blobs").iter().map(|b| {
        let key = text(b, "key");
        json!({"key":key,"pack":packs.of(b, key.trim_start_matches("img:")),"mime":b["mime"],"sha256":format!("{:x}", Sha256::digest(text(b, "data").as_bytes()))})
    }).collect();
    let mut whole = json!({"name":plan["name"],"packs":declared,"categories":plan["categories"],"epochs":plan["epochs"],"axis":axis,
        "spheres":plan["spheres"],"yearCycle":plan["yearCycle"],"yearCycles":plan["yearCycles"],"blobs":blobs,"rules":rules});
    if plan.get("sphereLines").is_some() {
        let lines: Vec<Value> = list(plan, "sphereLines").iter().map(|l| {
            let mut out = l.clone();
            // 객체가 아닌 원소(깨진 배치)는 그대로 — 짓기도 빈 값으로 읽는다(`builder::SphereLineIn::read`).
            if let Some(o) = out.as_object_mut() {
                o.insert("pack".into(), json!(packs.of(l, text(l, "uid"))));
            }
            out
        }).collect();
        whole["sphereLines"] = json!(lines);
    }
    Ok(format!("{:x}", Sha256::digest(serde_json::to_vec(&whole)?)))
}

// ---------------------------------------------------------------- 저장소의 지문

fn has_table(db: &Connection, name: &str) -> Result<bool> {
    Ok(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1")?.exists([name])?)
}

/// meta의 JSON 값(없거나 읽히지 않으면 빈 객체).
fn meta_json(db: &Connection, key: &str) -> Value {
    db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0))
        .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_else(|| Value::Object(Map::new()))
}

/// 지문을 `track_prints`에 적는다(있으면 바꿔 적는다 — 온 판은 열쇠 [`GLOBALS`]). 가져오기(`legacy::fill`)가 끝에서 부르고,
/// `apply`(과제 5)가 거래 안에서 다시 쓴 트랙의 것을 적는다.
pub fn save_prints(db: &Connection, p: &Prints) -> Result<()> {
    let mut stmt = db.prepare_cached("INSERT OR REPLACE INTO track_prints(key,print,needs) VALUES(?1,?2,?3)")?;
    stmt.execute([GLOBALS, p.globals.as_str(), "{}"])?;
    for (key, t) in &p.tracks {
        let needs = json!({"uids":t.needs_uids,"rows":t.row_targets,"own":t.uids,"hides":t.hides}).to_string();
        stmt.execute([key.as_str(), t.print.as_str(), needs.as_str()])?;
    }
    Ok(())
}

/// 저장소의 트랙 열쇠 → `tracks.id`([`track_key`]와 같은 규칙 — 자료집은 `meta.pack_keys`의 글자 id, 없으면 이름).
/// 판 트랙은 열쇠가 `__board:`로 시작하는 것이다(내보내기의 약속 — 배치 쪽은 [`prints`]가 같은 약속을 지키는지 본다).
pub fn stored_tracks(db: &Connection) -> Result<BTreeMap<String, i64>> {
    let mut out = BTreeMap::new();
    for (key, id) in stored_order(db)? {
        if out.insert(key.clone(), id).is_some() {
            return Err(format!("저장소의 트랙 열쇠가 겹칩니다: {key}").into());
        }
    }
    Ok(out)
}

/// 저장소의 (트랙 열쇠, `tracks.id`) — 트랙 차례(`tracks.ord`)대로([`stored_tracks`]와 같은 열쇠 · 겹침은 보지 않음).
fn stored_order(db: &Connection) -> Result<Vec<(String, i64)>> {
    let pack_keys = meta_json(db, "pack_keys");
    let mut labels: HashMap<i64, String> = HashMap::new();
    {
        let mut stmt = db.prepare("SELECT id,name FROM packs")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))? {
            let (id, name) = row?;
            let key = pack_keys[&id.to_string()].as_str().unwrap_or("");
            labels.insert(id, if key.is_empty() { name } else { key.to_owned() });
        }
    }
    let mut out = Vec::new();
    let mut stmt = db.prepare("SELECT id,pack,key,name FROM tracks ORDER BY ord,id")?;
    for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?)))? {
        let (id, pack, key, name) = row?;
        let key = if key.is_empty() {
            format!("n:{}|{name}", labels.get(&pack).map(String::as_str).unwrap_or(""))
        } else if key.starts_with(BOARD_KEY) {
            format!("{BOARD}{key}")
        } else {
            key
        };
        out.push((key, id));
    }
    Ok(out)
}

/// 저장된 지문의 needs에서 한 갈래(`uids` · `rows` · `own`)를 읽는다(없으면 빈 목록). needs 글 풀기는 [`needs_list`] 하나로 한다
/// (과제 A+ 넘김 "같은 규칙 두 곳" — 예전에는 여기만 SQLite `json_extract`로 따로 풀었다).
fn needs_part(db: &Connection, key: &str, part: &str) -> Result<Vec<String>> {
    let text: Option<String> = db.query_row("SELECT needs FROM track_prints WHERE key=?1", [key], |r| r.get(0)).optional()?;
    match text {
        Some(text) => needs_list(&text, part),
        None => Ok(Vec::new()),
    }
}

/// 그 uid들을 가리키는 트랙(저장된 needs의 `uids`로) — [`choose`]가 쓰고, C 과제 9가 배치 범위를 넓힐 때도 쓴다.
/// 지문 표가 없는 옛 저장소에서는 빈 집합(그때는 [`choose`]가 모든 트랙을 다시 쓴다).
pub fn dependents(db: &Connection, uids: &BTreeSet<String>) -> Result<BTreeSet<String>> {
    stored_hits(db, "uids", uids)
}

/// 그 트랙들의 칸 · 항목을 가리는 변형의 주인 트랙(저장된 needs의 `hides`로 — 판정 R16). 지문 표가 없으면 빈 집합.
pub fn hiders(db: &Connection, tracks: &BTreeSet<String>) -> Result<BTreeSet<String>> {
    stored_hits(db, "hides", tracks)
}

/// [`choose`]가 한 번만 읽는 저장된 needs — 트랙 열쇠 → (`uids`, `hides`). 처음 물을 때 읽는다(지문 표가 없으면 빈 것).
#[derive(Default)]
struct StoredNeeds {
    read: Option<Vec<(String, Vec<String>, Vec<String>)>>,
}

impl StoredNeeds {
    /// [`dependents`](`part` = "uids") · [`hiders`]("hides")의 몸 — needs의 `own`(제 uid — 큰 트랙에서는 길다)은 읽지 않고 두 갈래만 꺼낸다.
    fn hits(&mut self, db: &Connection, part: &str, wanted: &BTreeSet<String>) -> Result<BTreeSet<String>> {
        if wanted.is_empty() {
            return Ok(BTreeSet::new());
        }
        if self.read.is_none() {
            let mut list = Vec::new();
            if has_table(db, "track_prints")? {
                let mut stmt = db.prepare("SELECT key,needs FROM track_prints WHERE key<>?1")?;
                let mut rows = stmt.query([GLOBALS])?;
                while let Some(r) = rows.next()? {
                    let text = r.get_ref(1)?.as_str()?;
                    list.push((r.get(0)?, needs_list(text, "uids")?, needs_list(text, "hides")?));
                }
            }
            self.read = Some(list);
        }
        let list = self.read.as_deref().unwrap_or_default();
        Ok(list.iter().filter(|(_, uids, hides)| (if part == "uids" { uids } else { hides }).iter().any(|u| wanted.contains(u)))
            .map(|(key, _, _)| key.clone()).collect())
    }
}

/// 저장된 needs의 한 갈래(`uids` · `hides`)가 `wanted`와 겹치는 트랙 — [`StoredNeeds::hits`] 한 번(같은 규칙을 두 곳에 두지 않는다 — 과제 A+ 넘김).
fn stored_hits(db: &Connection, part: &str, wanted: &BTreeSet<String>) -> Result<BTreeSet<String>> {
    StoredNeeds::default().hits(db, part, wanted)
}

/// needs 글에서 한 갈래만 꺼낸다(없으면 빈 목록). [`save_prints`]가 쓰는 꼴(열쇠 글자 차례 `{"hides":[…],"own":[…],"rows":[…],"uids":[…]}` ·
/// 빈칸 없음)이면 그 갈래의 배열만 읽는다 — 맨 앞 열쇠면 앞에서, 아니면 뒤에서 `,"<갈래>":`를 찾아(배열 속 글자는 따옴표가 `\"`로 적혀
/// 이 꼴이 나오지 않는다) 거기서 배열 하나만 푼다. 큰 트랙의 긴 `own`을 트랙마다 풀면 저장소 크기에 비례했다(과제 7c — SQLite `json_extract`는
/// 글 전체를 푼다). 꼴이 다르면 통째로 푼다.
fn needs_list(text: &str, part: &str) -> Result<Vec<String>> {
    let head = format!("{{\"{part}\":");
    let rest = text.strip_prefix(head.as_str()).or_else(|| text.rfind(&format!(",\"{part}\":")).map(|at| &text[at + head.len()..]));
    if let Some(rest) = rest {
        let mut de = serde_json::Deserializer::from_str(rest);
        if let Ok(list) = <Vec<String> as serde::Deserialize>::deserialize(&mut de) {
            return Ok(list);
        }
    }
    let whole: Value = serde_json::from_str(text)?;
    Ok(match whole.get(part) {
        Some(Value::Null) | None => Vec::new(),
        Some(v) => serde_json::from_value(v.clone())?,
    })
}

/// 다시 쓸 트랙: 지문이 다른 것 ∪ 새것 ∪ (covers가 All이면) 사라진 것 ∪ 가리키던 uid가 생기거나 사라진 트랙(한 겹).
/// - 저장소의 트랙은 `tracks` 표로 안다([`stored_tracks`]). 지문은 `track_prints`에서 — 표가 없는 옛 저장소이거나 그 트랙의 줄이 없으면
///   '지문 없음 → 다시 씀'(옛 DLC의 약속 2).
/// - `Covers::Tracks`면 그 트랙만 견주고 사라지는 트랙은 없다(배치에 없는 열쇠를 주면 Err).
/// - uid가 생기고 사라짐은 다시 쓰거나 더하거나 빼는 트랙에서만 잰다(지문이 같은 트랙은 uid도 같다). 그 uid를 가리키는 트랙은
///   저장된 needs([`dependents`])와 새 배치의 needs 둘 다로 찾고, **새 배치에 있고 저장소에도 있는 것만** 다시 쓴다
///   (새 배치에 없는 트랙은 다시 쓸 재료가 없다 — `Covers::Tracks`에서만 생긴다).
/// - 그렇게 정한 트랙(다시 씀 ∪ 새것 ∪ 사라짐)의 칸 · 항목을 가리는 변형의 주인 트랙을 더한다(저장된 needs [`hiders`] ∪ 새 needs의
///   `hides` — 판정 R16). 같은 조건(새 배치에도 저장소에도 있음)으로. 더한 주인도 다시 쓰이므로 **더 늘지 않을 때까지 거듭한다**(리메이크 3단계
///   과제 7 걸음 3 — 렌즈의 첫 트랙을 가리는 판).
/// - 다시 쓸 수 없어 낡은 번호가 남는 트랙(저장소에 있고 새 배치에도 사라지는 트랙에도 없는 것 — `Covers::Tracks`에서만 생긴다)이
///   사라지는 uid를 가리키거나 다시 쓰는 트랙의 칸 · 항목을 가리면 Err(얹힌 몫 10 — 지운 변형 · 칸 · 항목의 번호가 남지 않게).
pub fn choose(db: &Connection, new: &Prints, covers: &Covers) -> Result<Choice> {
    choose_from(db, new, covers, false)
}

/// [`choose`]의 몸 — `forget`이면 저장된 지문을 없는 것으로 본다(지문 표가 없는 옛 저장소와 같은 길 — 덮는 트랙을 모두 다시 쓴다). `apply`가 내용을 싣는
/// 열 · 표가 없던 저장소([`older_missing`] — 과제 A+ 1)에서 쓴다: 그 열을 막 더하면 다시 쓰지 않는 트랙은 빈 값으로 남는다.
fn choose_from(db: &Connection, new: &Prints, covers: &Covers, forget: bool) -> Result<Choice> {
    let stored = stored_tracks(db)?;
    let table = !forget && has_table(db, "track_prints")?;
    let mut held: HashMap<String, String> = HashMap::new();
    if table {
        let mut stmt = db.prepare("SELECT key,print FROM track_prints")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
            let (key, print) = row?;
            held.insert(key, print);
        }
    }
    let held_globals = held.remove(GLOBALS);
    let candidates: Vec<&String> = match covers {
        Covers::All => new.order.iter().collect(),
        Covers::Tracks(keys) => {
            if let Some(missing) = keys.iter().find(|k| !new.tracks.contains_key(*k)) {
                return Err(format!("덮는다는 트랙 «{missing}»이 배치에 없습니다").into());
            }
            keys.iter().collect()
        }
        Covers::Part { tracks, order } => {
            if let Some(missing) = tracks.iter().find(|k| !new.tracks.contains_key(*k)) {
                return Err(format!("고쳐 쓸 트랙 «{missing}»이 배치에 없습니다(일부 트랙만 실은 배치)").into());
            }
            if let Some(extra) = new.tracks.keys().find(|k| !tracks.contains(*k)) {
                return Err(format!("고쳐 쓰지 않을 트랙 «{extra}»이 배치에 실렸습니다(일부 트랙만 실은 배치)").into());
            }
            if let Some(stray) = tracks.iter().find(|k| !order.contains(k)) {
                return Err(format!("고쳐 쓸 트랙 «{stray}»이 DLC 조합의 트랙 차례에 없습니다").into());
            }
            tracks.iter().collect()
        }
    };
    // `Covers::Part`의 S 밖인데 다시 써야 하는 트랙(부르는 쪽이 S를 넓혀 다시 배치한다 — [`Widen`]). 새 배치(조합 전부)에 있는 트랙인가도 여기서.
    let (part, in_combo): (Option<&BTreeSet<String>>, BTreeSet<&str>) = match covers {
        Covers::Part { tracks, order } => (Some(tracks), order.iter().map(String::as_str).collect()),
        _ => (None, new.tracks.keys().map(String::as_str).collect()),
    };
    let mut widen: BTreeSet<String> = BTreeSet::new();
    let mut c = Choice::default();
    for key in candidates {
        if !stored.contains_key(key) {
            c.added.insert(key.clone());
        } else if held.get(key) != Some(&new.tracks[key].print) {
            c.rewrite.insert(key.clone());
        }
    }
    if covers.whole() {
        c.removed = stored.keys().filter(|k| !in_combo.contains(k.as_str())).cloned().collect();
    }
    if let Some(s) = part {
        // S 밖 트랙은 그대로라고 믿는다 — 저장소에 있고 지문이 있어야 한다(새 트랙 · 지문 없는 트랙 · `forget`(옛 저장소)이면 다시 배치해야 한다).
        for key in in_combo.iter().filter(|k| !s.contains(**k)) {
            if !stored.contains_key(*key) || !held.contains_key(*key) {
                widen.insert((*key).to_owned());
            }
        }
        // 저장소 대비 서거나 사라지는 판 트랙(판정 R54 I2 — 판 셈 오류로 빠지는 판이 뒤집히면 닿는 트랙(배치 없이 짐작)은 모른다): 판을 켠 배치의 변형 판
        // 항목 · 칸은 그 판의 구성 트랙(`row_targets`)에 실리고 판 변형은 그 트랙의 것을 가린다(`hides`) — 그 트랙이 S 밖이면 넓힌다(새 판은 새 지문 ·
        // 사라지는 판은 저장된 needs).
        let mut members: BTreeSet<String> = BTreeSet::new();
        for key in c.added.iter().filter(|k| k.starts_with(BOARD)) {
            let t = &new.tracks[key];
            members.extend(t.row_targets.iter().chain(&t.hides).cloned());
        }
        if table {
            for key in c.removed.iter().filter(|k| k.starts_with(BOARD)) {
                members.extend(needs_part(db, key, "rows")?);
                members.extend(needs_part(db, key, "hides")?);
            }
        }
        widen.extend(members.into_iter().filter(|k| !s.contains(k) && in_combo.contains(k.as_str())));
    }
    c.globals = held_globals.as_ref() != Some(&new.globals);
    let mut old_own = BTreeSet::new();
    if table {
        for key in c.rewrite.iter().chain(&c.removed) {
            old_own.extend(needs_part(db, key, "own")?);
        }
    }
    let new_own: BTreeSet<String> = c.rewrite.iter().chain(&c.added).flat_map(|k| new.tracks[k].uids.iter().cloned()).collect();
    c.uids_gone = old_own.difference(&new_own).cloned().collect();
    c.uids_new = new_own.difference(&old_own).cloned().collect();
    let touched: BTreeSet<String> = c.uids_gone.union(&c.uids_new).cloned().collect();
    // 저장된 needs는 한 번만 읽는다(과제 7c — 트랙마다 긴 `own`을 실은 글이라 읽기만 해도 저장소 크기에 비례한다).
    let mut needs = StoredNeeds::default();
    if !touched.is_empty() {
        let mut leaning = needs.hits(db, "uids", &touched)?;
        // 사라지는 uid를 가리키던 저장소의 트랙이 새 배치에 없으면(덮는 트랙만 주는 배치) 다시 쓸 재료가 없어 그 번호가 낡는다 — 거절한다
        // (생기는 uid만 가리키던 것은 예전처럼 둔다 — 낡은 번호를 남기지는 않는다).
        if !c.uids_gone.is_empty() {
            let stale = needs.hits(db, "uids", &c.uids_gone)?;
            if let Some(key) = stale.iter().find(|k| stored.contains_key(*k) && !new.tracks.contains_key(*k) && !c.removed.contains(*k)) {
                // 하위 배치(`Part`)면 그 트랙도 배치해 오면 된다(조합에 있으니까) — 넓히기로.
                if part.is_some() && in_combo.contains(key.as_str()) {
                    widen.insert(key.clone());
                } else {
                    return Err(format!("트랙 «{key}»이 사라지는 띠 · 사건을 가리키는데 배치에 없습니다 — 그 트랙도 함께 내보내 주세요").into());
                }
            }
        }
        leaning.extend(new.tracks.iter().filter(|(_, t)| !t.needs_uids.is_disjoint(&touched)).map(|(k, _)| k.clone()));
        for key in leaning {
            if new.tracks.contains_key(&key) && stored.contains_key(&key) {
                c.rewrite.insert(key);
            } else if part.is_some() && in_combo.contains(key.as_str()) && stored.contains_key(&key) {
                widen.insert(key);
            }
        }
    }
    // 다시 쓰거나 더하거나 빼는 트랙의 칸 · 항목을 가리는 변형의 주인은 그 새 번호로 가리기를 다시 풀어야 한다(판정 R16).
    // 판 트랙만 바뀌면 가려지는 원래 트랙은 들지 않는다(가려지는 쪽은 가리는 쪽에 기대지 않는다).
    // **닫힐 때까지 거듭한다**(리메이크 3단계 과제 7 걸음 3): 그렇게 더한 주인도 다시 쓰여 제 칸 · 항목의 번호가 바뀌므로, 그것을 가리는 변형의 주인도
    // 다시 써야 한다. 한 겹에서 멈추면 렌즈(kind 4 — 첫 트랙에 실려 모든 트랙의 칸을 가림)의 첫 트랙이 지문은 그대로인데 가림 주인으로 다시 쓰이고,
    // 그 첫 트랙의 항목을 가리는 판(지문이 그대로인 것)은 남아 "delete"의 지킴(다시 쓰지 않는 변형이 지울 트랙을 가림)에 걸렸다 — 등불에 `f4-crowns`.
    // 새로 다시 쓰게 된 트랙(하위 배치면 넓힐 트랙까지)만 다음 겹에서 보니 트랙 수만큼 안에 끝난다.
    let mut seen: BTreeSet<String> = c.rewrite.iter().chain(&c.added).chain(&c.removed).cloned().collect();
    let mut shifted = seen.clone();
    while !shifted.is_empty() {
        let mut owners = needs.hits(db, "hides", &shifted)?;
        // 얹힌 몫 10: 가리는 주인이 저장소에 있는데 새 배치에 없으면(덮는 트랙만 주는 배치) 다시 쓸 수 없어 그 변형의 가리기(variant_hides)가
        // 지운 칸 · 항목을 가리키게 된다 — 거절한다(모두 덮는 배치에서 배치에 없는 트랙은 사라지는 트랙이라 함께 지워진다).
        let mut next: BTreeSet<String> = BTreeSet::new();
        for key in owners.iter().filter(|k| stored.contains_key(*k) && !new.tracks.contains_key(*k) && !c.removed.contains(*k)) {
            // 하위 배치(`Part`)면 가리는 트랙도 배치해 오면 된다 — 넓히기로(넓힌 트랙도 다시 쓰이니 그 가림 주인도 함께 넓힌다).
            if part.is_some() && in_combo.contains(key.as_str()) {
                widen.insert(key.clone());
                next.insert(key.clone());
            } else {
                return Err(format!("트랙 «{key}»의 변형이 다시 쓰는 트랙의 칸 · 항목을 가리는데 배치에 없습니다 — 가리는 트랙도 함께 내보내 주세요").into());
            }
        }
        owners.extend(new.tracks.iter().filter(|(_, t)| !t.hides.is_disjoint(&shifted)).map(|(k, _)| k.clone()));
        for key in owners {
            if new.tracks.contains_key(&key) && stored.contains_key(&key) {
                c.rewrite.insert(key.clone());
                next.insert(key);
            }
        }
        next.retain(|k| seen.insert(k.clone()));
        shifted = next;
    }
    // 같은 uid의 띠 · 사건이 두 트랙 이상에 있으면(A 걸음 검토 검사 빈틈 10 — 지금 자료(정답지 자료 전부 · 감독의 실자료)엔 없음) 그 uid를 가리키는 값을
    // 어느 것으로 풀지가 배치의 차례(통째 짓기는 뒤에 실린 것이 이김) · 번호에 달려 트랙 지문만으로는 알 수 없다 — 트랙 차례만 바뀌어도 답이 바뀐다.
    // 조용히 다른 답을 내지 않게 거절한다(판정 R37 — 덮는 꼴(All · Tracks · Part) 모두 · 저장소 그대로 · DLC를 만든 쪽에서 고칠 일). 첫 주인만 적어 두고
    // 겹칠 때만 모은다(uid마다 트랙 모음을 만들지 않는다).
    let mut first_owner: HashMap<&str, &str> = HashMap::new();
    let mut shared: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for (key, t) in &new.tracks {
        for u in &t.uids {
            match first_owner.get(u.as_str()) {
                Some(owner) if *owner != key.as_str() => {
                    let set = shared.entry(u.clone()).or_default();
                    set.insert((*owner).to_owned());
                    set.insert(key.clone());
                }
                Some(_) => {}
                None => {
                    first_owner.insert(u.as_str(), key.as_str());
                }
            }
        }
    }
    if let Some(s) = part {
        // 하위 배치면 S 밖 트랙(저장소의 것 — 그대로라고 믿는 것)의 같은 uid 띠 · 사건도 본다(uid 색인 `periods_uid` · 부분 색인 `events_uid` — 그 조건 `uid<>''`을 함께).
        let by_id: HashMap<i64, &String> = stored.iter().map(|(k, id)| (*id, k)).collect();
        let mut bands = db.prepare("SELECT DISTINCT r.track FROM periods p JOIN rows r ON r.id=p.row WHERE p.uid=?1")?;
        let mut events = db.prepare("SELECT DISTINCT r.track FROM events e JOIN rows r ON r.id=e.lane WHERE e.uid=?1 AND e.uid<>''")?;
        for (uid, owner) in &first_owner {
            let is_band = new.tracks.get(*owner).is_some_and(|t| t.bands.contains(*uid));
            let stmt = if is_band { &mut bands } else { &mut events };
            for id in stmt.query_map([uid], |r| r.get::<_, i64>(0))? {
                if let Some(key) = by_id.get(&id?).filter(|k| !s.contains(**k) && in_combo.contains(k.as_str())) {
                    let set = shared.entry((*uid).to_owned()).or_default();
                    set.insert((*owner).to_owned());
                    set.insert((*key).clone());
                }
            }
        }
    }
    if !shared.is_empty() {
        return Err(Box::new(SharedUids(shared)));
    }
    if !widen.is_empty() {
        return Err(Box::new(Widen(widen)));
    }
    Ok(c)
}

// ---------------------------------------------------------------- 하위 배치

/// 하위 배치: 트랙 keys(S)의 것만 남기고 트랙 순번을 S만의 순번으로 다시 매긴 배치 JSON — 과제 5의 "insert" · P3 과제 16 검사가 같은 가름을 쓴다.
/// - 온 판 조각 · 항목 기록(`entities` · `boards.entities`) · 모르는 열쇠는 통째로 싣는다. 자료집 목록이 그대로라 `pack` 순번도 그대로다.
/// - 트랙 · 띠 · 칸 · 사건 · 일반 항목 · 줄 이름 · 날짜 칸 · 변형은 S의 것만, 실린 차례 그대로(겉 열쇠 `boards`의 것은 `boards`에).
///   줄은 트랙 안 순번이라 그대로다.
/// - 일반 항목의 띠 번호 칸은 하위 배치의 자리로 다시 매기지 않는다 — `"bandUids": {"<칸>": "<띠 uid>"}`를 달고 칸 값은 0(판정 R14 ·
///   과제 5c의 `fill_into(Tracks)`가 uid로 푼다). 통째 짓기(`FillHow::All`)는 모르는 열쇠라 0으로 넣는다.
/// - 변형의 `hides[].at`은 S 안 칸 · 항목이면 하위 배치의 자리로 다시 매긴다. S 밖 것(판 변형이 원래 트랙의 것을 가림)은 변형의
///   `outer.hides`로 옮겨 **가리는 원소의 내용**([`hidden_content`]의 꼴 — 지문의 가림과 같은 함수)을 싣는다(판정 R16 다 · R19 — 과제 5c가
///   저장소에서 내용으로 번호를 찾는다).
/// - 변형의 줄 · 이사 · 묶음이 S 밖 트랙의 줄을 가리면 그 원소를 변형의 `"outer": {"rows":[…],"moves":[…],"groups":[…]}`로 옮긴다 —
///   S 밖 트랙은 열쇠 글(`"track":"ta"`), S 안은 새 순번, `"at"` = 원래 목록에서의 자리. 통째 짓기는 모르는 열쇠라 건너뛰고,
///   과제 5c가 `(트랙 열쇠, 트랙 안 줄)` → 줄 열쇠(`outer_rows`)로 푼다.
/// - S 안 원소(줄 · 띠 · 칸 · 사건 · 항목 · 줄 이름)에 달린 변형 열쇠가 하위 배치에 없는 변형(예: S 밖 판 트랙의 판 변형)을 가리키면
///   원소는 그대로 두고 그 열쇠를 겉의 `"outer": {"variants":[…]}`에 적는다(판정 R16 가 — 과제 5c가 저장소에서 열쇠로 번호를 찾는다).
///   그런 하위 배치는 통째 짓기로는 지을 수 없다(없는 변형을 가리킨다).
/// - P4 과제 9(하위 배치를 그대로 `apply(Covers::Part)`에 — P3 과제 16 `Scope::Tracks(S)`의 출력이 이 꼴이다):
///   - 겉의 `"allTracks"` = 조합 전부의 트랙 열쇠([`prints`]의 `order` — 차례대로). 하위 배치만으로는 S 밖 트랙 · 차례를 알 수 없어서다.
///   - 변형의 S 밖 가림은 `outer.hides`(내용)와 나란히 `outer.hideAt`(원래 가림 목록에서의 자리) · `outer.hideOwners`(가려지는 원소의 트랙 열쇠)를 단다 —
///     지문이 통째 배치와 같은 차례 · 같은 대상 트랙을 적게(내용 자체는 그대로 — 과제 5c의 찾기가 읽는 꼴).
///   - 하위 배치를 다시 하위 배치로 줄여도(`sub_plan(sub_plan(P, S), S′)`, S′ ⊆ S) `sub_plan(P, S′)`과 같은 것을 싣는다 — "insert"가 다시 쓸 트랙만 줄여 넣는다.
/// - 겉의 `"stripFirst": {"<트랙 열쇠>": [연호, 도읍 · 배도]}` = 조합 전부의 트랙마다 날짜 칸 이음 번호의 첫 값([`strip_firsts`] — 판정 R45). 지문은 이음 번호를
///   트랙 안 거리로만 보므로 S 밖 트랙도 앞 트랙이 바뀌면 번호가 밀린다 — "relink"가 그 트랙의 저장소 번호를 이 값으로 옮긴다([`renumber_strips`]).
pub fn sub_plan(plan: &Value, keys: &BTreeSet<String>) -> Result<Value> {
    let view = View::new(plan)?;
    if let Some(missing) = keys.iter().find(|k| !view.keys.contains(k)) {
        return Err(format!("배치에 없는 트랙입니다: {missing}").into());
    }
    // 옛 트랙 → 판 트랙 차례라 S의 것을 그 차례대로 세면 S만의 순번이다(옛 트랙이 먼저).
    let mut remap: Vec<Option<usize>> = vec![None; view.tracks.len()];
    let mut next = 0;
    for (i, key) in view.keys.iter().enumerate() {
        if keys.contains(key) {
            remap[i] = Some(next);
            next += 1;
        }
    }
    let cell_owner: Vec<usize> = view.cells.iter().map(|c| view.cell_track(c)).collect::<Result<_>>()?;
    let item_owner: Vec<usize> = view.items.iter().map(|it| view.track_of(it, "일반 항목")).collect::<Result<_>>()?;
    let new_at = |owner: &[usize]| -> Vec<Option<usize>> {
        let mut n = 0;
        owner.iter().map(|t| remap[*t].map(|_| { n += 1; n - 1 })).collect()
    };
    let (cell_at, item_at) = (new_at(&cell_owner), new_at(&item_owner));
    let sub = Sub { view: &view, remap: &remap, cell_owner: &cell_owner, item_owner: &item_owner, cell_at: &cell_at, item_at: &item_at };
    let top = Part { tracks: 0, cells: 0, items: 0 };
    let mut out = sub.part(plan, &top, true)?;
    if let Some(boards) = plan.get("boards").filter(|b| b.is_object()) {
        let at = Part { tracks: list(plan, "tracks").len(), cells: list(plan, "cells").len(), items: list(plan, "items").len() };
        out.insert("boards".into(), Value::Object(sub.part(boards, &at, false)?));
    }
    // 조합 전부의 트랙 차례 — 하위 배치를 다시 줄이면 처음 배치의 것을 그대로.
    let all: Vec<String> = match plan["allTracks"].as_array() {
        Some(list) => list.iter().map(|k| k.as_str().unwrap_or("").to_owned()).collect(),
        None => view.keys.clone(),
    };
    out.insert("allTracks".into(), json!(all));
    // 조합 전부의 트랙마다 날짜 칸 이음 번호의 첫 값(판정 R45) — S 밖 트랙의 날짜 칸은 덜어 내므로 "relink"가 그 트랙의 저장소 번호를 옮길 값을 따로 싣는다.
    let firsts: Map<String, Value> = strip_firsts(plan)?.into_iter().map(|(k, f)| (k, json!(f))).collect();
    out.insert(STRIP_FIRST.into(), Value::Object(firsts));
    let mut whole = Value::Object(out);
    let outside = outside_variants(&whole);
    if !outside.is_empty() {
        whole["outer"] = json!({"variants":outside});
    }
    Ok(whole)
}

/// 하위 배치의 원소가 달았지만 하위 배치에 없는 변형 열쇠.
fn outside_variants(sub: &Value) -> BTreeSet<String> {
    let roots = [sub, &sub["boards"]];
    let have: BTreeSet<&str> = roots.into_iter().flat_map(|r| list(r, "variants")).map(|v| text(v, "key")).collect();
    let mut used = BTreeSet::new();
    for root in roots {
        let rows = list(root, "tracks").iter().flat_map(|t| list(t, "rows"));
        let rest = ["periods", "cells", "events", "items", "rowLabels"].into_iter().flat_map(|key| list(root, key));
        for v in rows.chain(rest) {
            let key = text(v, "variant");
            if !key.is_empty() && !have.contains(key) {
                used.insert(key.to_owned());
            }
        }
    }
    used
}

/// 겉 배치(또는 `boards`)의 목록이 `with_boards`로 이은 자리에서 몇째부터인가.
struct Part {
    tracks: usize,
    cells: usize,
    items: usize,
}

/// 하위 배치를 짓는 재료.
struct Sub<'a> {
    view: &'a View<'a>,
    /// 트랙 순번 → S만의 순번(S 밖이면 None).
    remap: &'a [Option<usize>],
    cell_owner: &'a [usize],
    item_owner: &'a [usize],
    /// 칸 · 항목의 이은 자리 → 하위 배치의 이은 자리(S 밖이면 None).
    cell_at: &'a [Option<usize>],
    item_at: &'a [Option<usize>],
}

impl Sub<'_> {
    /// 트랙을 하위 배치에서 가리키는 값 — S 안이면 새 순번, 밖이면 열쇠 글.
    fn place(&self, t: usize) -> Value {
        match self.remap[t] {
            Some(n) => json!(n),
            None => json!(self.view.keys[t]),
        }
    }

    /// 배치 객체 하나(겉 · `boards`)를 하위 배치로. 트랙 단위의 목록은 S의 것만, 나머지 열쇠는 통째로.
    fn part(&self, root: &Value, at: &Part, top: bool) -> Result<Map<String, Value>> {
        let view = self.view;
        let mut out = Map::new();
        for (key, value) in root.as_object().into_iter().flatten() {
            let rows = value.as_array().map(Vec::as_slice).unwrap_or(&[]);
            let kept: Vec<Value> = match key.as_str() {
                "tracks" => rows.iter().enumerate().filter(|(i, _)| self.remap[at.tracks + i].is_some()).map(|(_, t)| t.clone()).collect(),
                "periods" | "events" | "rowLabels" => {
                    let mut kept = Vec::new();
                    for v in rows {
                        if let Some(n) = self.remap[view.track_of(v, "값")?] {
                            let mut x = v.clone();
                            x["track"] = json!(n);
                            kept.push(x);
                        }
                    }
                    kept
                }
                "cells" => rows.iter().enumerate().filter(|(i, _)| self.remap[self.cell_owner[at.cells + i]].is_some()).map(|(_, c)| c.clone()).collect(),
                "items" => {
                    let mut kept = Vec::new();
                    for (i, it) in rows.iter().enumerate() {
                        let Some(n) = self.remap[self.item_owner[at.items + i]] else { continue };
                        let mut x = it.clone();
                        x["track"] = json!(n);
                        let mut uids = Map::new();
                        for (field, uid) in view.band_refs(it)? {
                            x[field] = json!(0);
                            uids.insert(field.into(), json!(uid));
                        }
                        if !uids.is_empty() {
                            x["bandUids"] = Value::Object(uids);
                        }
                        kept.push(x);
                    }
                    kept
                }
                "variants" => {
                    let mut kept = Vec::new();
                    for v in rows {
                        let own = view.track_of(v, "변형")?;
                        if self.remap[own].is_some() {
                            kept.push(self.variant(v, own)?);
                        }
                    }
                    kept
                }
                // 날짜 칸은 겉에만(`fill`과 같다) — 공통 줄(track −1)은 온 판이라 그대로.
                "axis" if top => {
                    let mut kept = Vec::new();
                    for a in rows {
                        let t = int_or(a, "track", -1);
                        if t < 0 {
                            kept.push(a.clone());
                        } else if let Some(n) = self.remap[view.track_at(t, "날짜 칸")?] {
                            let mut x = a.clone();
                            x["track"] = json!(n);
                            kept.push(x);
                        }
                    }
                    kept
                }
                "boards" if top => continue, // 따로(sub_plan)
                // 하위 배치를 다시 줄일 때: 밖 변형 열쇠(`outer`) · 조합의 트랙 차례(`allTracks`) · 이음 번호의 첫 값(`stripFirst`)은 새로 셈해 적는다(sub_plan).
                "outer" | "allTracks" | STRIP_FIRST if top => continue,
                _ => {
                    out.insert(key.clone(), value.clone());
                    continue;
                }
            };
            out.insert(key.clone(), json!(kept));
        }
        Ok(out)
    }

    /// 하위 배치에서 그 트랙을 가리키는 값(S 밖 열쇠 글은 그대로) · S 안인가.
    fn put(&self, p: &Place) -> (Value, bool) {
        match p {
            Place::At(t) => (self.place(*t), self.remap[*t].is_some()),
            Place::Key(key) => (json!(key), false),
        }
    }

    /// 변형 하나를 하위 배치로(S 안의 변형만 부른다). 들어온 것이 이미 하위 배치면(`outer`가 있음) 원래 차례로 되돌려([`full_list`] · [`full_hides`]) 다시 가른다 —
    /// S 밖 원소의 원래 자리(`at` · `hideAt`)는 늘 처음 배치의 목록에서의 자리다.
    fn variant(&self, v: &Value, own: usize) -> Result<Value> {
        let view = self.view;
        let mut out = v.clone();
        if let Some(o) = out.as_object_mut() {
            o.remove("outer");
        }
        out["track"] = self.place(own);
        let (mut rows, mut moves, mut groups) = (Vec::new(), Vec::new(), Vec::new());
        let (mut outer_rows, mut outer_moves, mut outer_groups) = (Vec::new(), Vec::new(), Vec::new());
        for (i, r) in full_list(v, "rows").into_iter().enumerate() {
            let mut x = r.clone();
            if let Some(o) = x.as_object_mut() {
                o.remove("at");
            }
            let (track, mut inside) = self.put(&view.place_of(r, "track", "변형의 줄")?);
            x["track"] = track;
            if int_or(r, "after", -1) == -2 && r["to"].as_i64().is_some() {
                let (to, to_inside) = self.put(&view.place_of(r, "toTrack", "변형의 옮겨 간 줄")?);
                x["toTrack"] = to;
                inside &= to_inside;
            }
            if inside {
                rows.push(x);
            } else {
                x["at"] = json!(i);
                outer_rows.push(x);
            }
        }
        for (part, list_of, kept, outer) in [("이사", "moves", &mut moves, &mut outer_moves), ("묶음", "groups", &mut groups, &mut outer_groups)] {
            for (i, m) in full_list(v, list_of).into_iter().enumerate() {
                let mut x = m.clone();
                if let Some(o) = x.as_object_mut() {
                    o.remove("at");
                }
                let (track, inside) = self.put(&view.place_of(m, "track", &format!("변형의 {part}"))?);
                x["track"] = track;
                if inside {
                    kept.push(x);
                } else {
                    x["at"] = json!(i);
                    outer.push(x);
                }
            }
        }
        let (mut hides, mut outer_hides, mut hide_at, mut hide_owners) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
        for (i, h) in full_hides(v)?.into_iter().enumerate() {
            let h = match h {
                Hide::Inner(h) => h,
                // 이미 S 밖이던 가림 — 내용 · 주인 그대로(원래 자리만 다시 적는다).
                Hide::Outer(content, owner) => {
                    outer_hides.push(content.clone());
                    hide_at.push(json!(i));
                    hide_owners.push(json!(owner));
                    continue;
                }
            };
            let (kind, at) = (int(h, "kind"), int(h, "at"));
            let index = |len: usize| usize::try_from(at).ok().filter(|i| *i < len).ok_or_else(|| format!("변형이 가리키는 자리가 범위 밖입니다: {at}"));
            let (places, slot) = match kind {
                3 => (self.cell_at, index(self.cell_at.len())?),
                4 => (self.item_at, index(self.item_at.len())?),
                _ => return Err(format!("모르는 변형 가리기의 갈래: {kind}").into()),
            };
            match places[slot] {
                Some(new) => {
                    let mut x = h.clone();
                    x["at"] = json!(new);
                    hides.push(x);
                }
                // S 밖 칸 · 항목 — 번호는 저장소에서 내용으로 찾는다(판정 R16 다).
                None => {
                    let (owner, content) = hidden_content(view, kind, at)?;
                    outer_hides.push(content);
                    hide_at.push(json!(i));
                    hide_owners.push(json!(view.keys[owner]));
                }
            }
        }
        for (key, kept) in [("rows", rows), ("moves", moves), ("groups", groups), ("hides", hides)] {
            if v.get(key).is_some() || !kept.is_empty() {
                out[key] = json!(kept);
            }
        }
        let mut outer = Map::new();
        let has_hides = !outer_hides.is_empty();
        for (key, list) in [("rows", outer_rows), ("moves", outer_moves), ("groups", outer_groups), ("hides", outer_hides)] {
            if !list.is_empty() {
                outer.insert(key.into(), json!(list));
            }
        }
        if has_hides {
            outer.insert("hideAt".into(), json!(hide_at));
            outer.insert("hideOwners".into(), json!(hide_owners));
        }
        if !outer.is_empty() {
            out["outer"] = Value::Object(outer);
        }
        Ok(out)
    }
}

// ---------------------------------------------------------------- 조합 대조

/// 조합 대조(설계 A 5-3 · 계획 정한 것 #8 — 지금 `import_with`의 규칙): 저장소의 DLC에 글자 id가 있다 · 배치의 기본팩에 id가 있다 ·
/// 기본팩이 같다 · (`Covers::All`이면) 지금 얹은 DLC가 배치에 다 있다(`remove`로 뺀 것만 예외). `Covers::Tracks`면 배치가 덮지 않는 DLC는
/// 그대로 둔 것으로 본다. `remove`는 저장소에 있고 배치에 없는 DLC여야 하고, 덮는 트랙만 줄 때(`Covers::Tracks`)는 받지 않는다
/// (그때는 사라지는 트랙이 없어 뺄 수 없다).
///
/// **판은 여기서 보지 않는다** — 판 대조는 원본 짝짓기와 한 몸이라 부르는 쪽이 한다: `import_with`는 저장소의 원본을 옮겨 실으므로
/// 판이 같아야 하고(모르면 알림), `apply`는 판이 바뀐 DLC의 새 원본을 받아 바꿔 넣는다(과제 5c의 `a@2` ↔ `a` · 7a의 `originals`).
pub fn check_combination(db: &Connection, plan: &Value, remove: &[String], covers: &Covers) -> Result<()> {
    let wants = wanted_packs(plan, None);
    let named: Vec<(Option<&str>, &str)> = wants.iter().map(|w| (w.key.as_deref(), w.name.as_str())).collect();
    // 하위 배치(`Part`)는 조합 전부를 말한다 — 모두 덮는 배치와 같은 대조.
    check_packs(db, &named, remove, if covers.whole() { &Covers::All } else { covers })
}

/// [`check_combination`]의 몸 — 배치가 말하는 자료집 목록(글자 id · 이름, 배치의 `packs[]` 차례)으로. `import_with`는 기본팩 원본의
/// id로 채운 목록을 준다(옛 JSON에는 `packs[]`가 없다).
pub(crate) fn check_packs(db: &Connection, wants: &[(Option<&str>, &str)], remove: &[String], covers: &Covers) -> Result<()> {
    let keys = meta_json(db, "pack_keys");
    let mut held: Vec<(String, String)> = Vec::new();
    {
        let mut stmt = db.prepare("SELECT id,name FROM packs ORDER BY id")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))? {
            let (number, name) = row?;
            held.push((keys[&number.to_string()].as_str().unwrap_or("").to_owned(), name));
        }
    }
    let Some((base_key, base_name)) = held.first() else {
        return Err("지금 저장소에 DLC가 없습니다".into());
    };
    // 글자 id가 없으면 무엇이 같은 DLC인지 알 수 없다 — 대조하지 못한 채 받으면 DLC가 조용히 사라질 수 있어 거절한다.
    if let Some((_, name)) = held.iter().find(|h| h.0.is_empty()) {
        return Err(format!("지금 저장소의 «{name}»에 DLC id가 없어 조합을 대조할 수 없습니다 — 아주 옛 저장소입니다. 새 판 시드로 옮긴 뒤 다시 해 주세요").into());
    }
    let Some(want_base) = wants.first().and_then(|w| w.0).filter(|k| !k.is_empty()) else {
        return Err("배치에 DLC id가 없어 조합을 대조할 수 없습니다 — 메이커에서 다시 내보내 주세요".into());
    };
    // 1. 기본팩이 같아야 한다.
    if want_base != base_key {
        return Err(refuse("base", format!("기본팩이 다릅니다(저장소 «{base_name}» · 배치 «{}») — 같은 기본팩으로 내보낸 배치만 받습니다", wants[0].1)));
    }
    let in_plan = |key: &str| wants.iter().any(|w| w.0 == Some(key));
    if !remove.is_empty() && *covers != Covers::All {
        return Err("덮는 트랙만 고쳐 쓰는 배치로는 DLC를 뺄 수 없습니다 — 배치 전체를 주어 빼 주세요".into());
    }
    for key in remove {
        if in_plan(key) {
            return Err(format!("빼라는 DLC «{key}»가 배치에 있습니다").into());
        }
        if !held.iter().any(|h| h.0 == *key) {
            return Err(format!("빼라는 DLC «{key}»가 지금 저장소에 없습니다").into());
        }
    }
    // 2. 지금 얹은 DLC가 배치에 모두 있어야 한다(새로 지으면 빠진 DLC가 사라진다) — 빼라고 한 것만 예외. 덮는 트랙만 주면 그대로 둔다.
    if *covers == Covers::All {
        for (key, name) in &held[1..] {
            if !in_plan(key) && !remove.contains(key) {
                return Err(format!("지금 얹은 DLC «{name}»이 이 배치에 없습니다 — 메이커에서 그 DLC도 함께 불러 내보내 주세요").into());
            }
        }
    }
    Ok(())
}

/// 배치가 지금 저장소의 DLC를 모두 싣는가 — [`apply`]의 "entities"가 항목 기록 · 그림을 지우기까지 할지를 가른다(과제 7a 얹힌 몫 7).
/// 계약 2-7의 약속: 배치는 제 조합(`packs[]`)의 항목 기록 · 그림을 **전부** 싣는다 — 덮는 트랙만 주는 하위 배치도(P3 정한 것 #12와 같은 꼴).
/// 그래서 저장소의 DLC가 모두 배치에 있으면 배치의 기록이 저장소 기록 전부의 새 모습이고(빠진 기록은 지운다), 하나라도 없으면 그 DLC의 기록은
/// 배치에 실리지 않았을 뿐 사라진 것이 아니다(넣거나 바꾸기만). 자료집은 글자 id(`meta.pack_keys`)로 견준다 — 글자 id가 없는 자료집이 있으면 거짓
/// (조합 대조가 그런 저장소를 이미 거절한다).
fn holds_every_pack(db: &Connection, plan: &Value) -> Result<bool> {
    let keys = meta_json(db, "pack_keys");
    let wants = wanted_packs(plan, None);
    let mut stmt = db.prepare("SELECT id FROM packs")?;
    let ids = stmt.query_map([], |r| r.get::<_, i64>(0))?.collect::<std::result::Result<Vec<_>, _>>()?;
    Ok(ids.iter().all(|id| keys[&id.to_string()].as_str().is_some_and(|k| !k.is_empty() && wants.iter().any(|w| w.key.as_deref() == Some(k)))))
}

// ---------------------------------------------------------------- 고쳐 쓰기(과제 5b ~ 5d)

/// [`apply`]의 재료.
pub struct ApplyIn<'a> {
    /// 새 배치(가져오기 JSON 3판). `Covers::All`이면 조합 전부, `Covers::Tracks`면 덮는 트랙을 담은 배치(메이커 `.htlayout`).
    pub plan: &'a Value,
    /// (자료집 글자 id, .htpack 바이트) — 새로 들거나 판이 바뀐 DLC의 원본(그대로인 DLC의 것은 주지 않아도 된다 — 저장소의 원본을 그대로 둔다).
    pub originals: &'a [(String, Vec<u8>)],
    pub covers: Covers,
    /// 뺄 DLC의 글자 id(`Covers::All`에서만 — [`check_combination`]).
    pub remove: &'a [String],
}

/// [`apply`]의 답. 트랙은 열쇠([`track_key`])로, 글자 차례.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ApplyReport {
    pub rewrote: Vec<String>,
    pub added: Vec<String>,
    pub removed: Vec<String>,
    /// 온 판 지문이 바뀌어 고쳐 적었다(`Covers::All`일 때만).
    pub globals: bool,
    /// 다시 쓰거나 사라지거나 새로 든 트랙 · 차례가 바뀐 트랙 가운데 가장 앞 자리(앱은 이 자리부터 타일을 버린다 — 차례만 바뀐 트랙은 판정 R27).
    /// 바뀐 것이 온 판뿐이면 0, 없으면 −1.
    pub first_pos: i64,
    /// 넣기 전 · 뒤의 전체 줄 수(자리의 수).
    pub rows_before: i64,
    pub rows_after: i64,
    /// "names"가 이름 표 · 관점 이름(과 덧줄)을 다시 폈다 — 바뀐 것이 하나도 없으면 거짓(과제 6).
    pub names: bool,
    pub ms: f64,
    /// 걸음별 ms(걸음 이름, ms — 걸음 차례대로 · 과제 7c 측정용). 걸음 이름은 [`apply`]의 실패 지점 이름과 같다.
    pub steps: Vec<(&'static str, f64)>,
}

/// 새 배치를 저장소에 고쳐 쓴다 — 부르는 쪽의 쓰기 거래(`write::write`) 안에서. 걸음마다 이름이 있고 그 이름의 [`fail_point`]가 걸린다
/// (검사가 아무 걸음에서나 실패를 일으켜 '실패하면 파일 그대로'를 잰다). 어떤 차례로 넣고 빼도 결과는 그 조합을 통째로 지은 것과 같다
/// (설계 3-4 '같음의 약속' — canon · meta 전부 · 검색 낱자 · 항목 기록으로 잰다). 걸음(과제 5b ~ 5d):
/// 1. `"choose"` — 조합 대조([`check_combination`]) · 새 지문([`prints`]) · 다시 쓸 트랙 고르기([`choose`]). 덮는 트랙만 주는 배치(`Covers::Tracks`)는
///    온 판 표(분류 · 시대 구분 · 공통 날짜 칸)를 바꿀 수 없어 다르면 Err(다른 트랙의 분류 번호 · 날짜 칸이 기댄다). 문화권 단위 줄(`sphere_lines` — 스키마 4)은
///    달라도 받되 적지 않는다(문화권 · 간지 설정 메타와 같은 갈래 — "globals" · "prints"가 그대로 둬 다음 모두 덮는 배치가 맞춘다). 덧붙임 Builder가 쓰는 내용 있는
///    열 · 표가 없던 옛 저장소([`older_missing`] — 과제 A+ 1)는 지문을 없는 것으로 보아 모든 트랙을 다시 쓰고, 덮는 트랙만 주는 배치는 저장소의 트랙을
///    다 덮어도 "배치 전체로 한 번 고쳐 써 주세요"로 거절한다(온 판은 모두 덮는 배치만 적는다 — A+ 검토 가).
/// 2. `"packs"` — 자료집 행을 맞춘다(없던 DLC는 넣고 · 원본이 바뀐 DLC는 바꿔 넣음) · `meta.pack_keys` · `pack_info`.
/// 3. `"delete"` — 옛 저장소에 없는 것을 먼저 만든다([`ensure_schema`] — `periods_row` 색인 · `events.ord` · `summaries.ords` · `entities.ord` · `sum` 열 ·
///    `track_prints` · `blobs` 표, 덮는 색인 `events_time`이 `ord` · `variant`를 품지 않으면 다시 짓기(그 색인의 통계도) — 얹힌 몫 11 · 형식 3 전의 이름 표 열 ·
///    관점 이름 · 사건 찾을 글 표 · A+ 1의 문화권 · ref_kind · 요약 분류 · 변형 열 · 표 · 스키마 4의 띠 `form` 열 · `sphere_lines` 표).
///    지우기 전 가장 큰 번호([`Floors`] — 얹힌 몫 6)를 읽고(변형 표를
///    만든 뒤라야 읽힌다), 다시 쓸 트랙의 띠 · 사건 uid → 번호 · 변형 열쇠 → 번호 · 옛 줄 덩이를 적어 두고([`Kept`]), 다시 쓸 트랙과
///    사라지는 트랙의 것을 지운다([`delete_tracks`] — 사건(검색 낱자 · 덧줄 포함) · 칸 · 띠 · 일반 항목 · 줄 이름 · 묶음 · 날짜 칸 · 변형 · 요약 ·
///    R-tree 다섯 · 줄, 사라지는 트랙은 `tracks` 행과 지문까지). 빼는 DLC(`remove`)는 항목 기록 · 자료집 행까지 지운다([`drop_packs`]).
/// 4. `"insert"` — 다시 쓸 트랙 ∪ 새 트랙의 하위 배치([`sub_plan`])를 `Builder::append_after`(지우기 전 번호 다음부터) +
///    `fill_into(FillHow::Tracks)`로 넣는다. 다시 쓰는 트랙은 `tracks.id`를 그대로(값만 바꿔 적음), 같은 uid의 띠 · 사건 · 같은 열쇠의
///    변형은 옛 번호로. S 밖을 가리키는 값은 저장소에서 찾은 번호로(`TrackFill`의 `outer_*` — 밖 변형 열쇠는 열쇠로, 밖 칸 · 항목 가림은
///    내용으로([`resolve_hides`] — 판정 R19)).
/// 5. `"relink"` — 다시 쓰지 않은 트랙의 변형이 다시 쓴 트랙의 옛 줄 덩이를 가리키던 값(이사 도착 · 변형 줄 · after · 판 줄 · 묶음 줄)을
///    새 덩이로 같은 자리만큼 옮겨 적는다([`relink`]). 새 덩이의 줄 수를 넘으면 Err(지문 규칙의 구멍).
/// 6. `"globals"` — 온 판([`put_globals`]): 모두 덮는 배치에서 온 판 지문이 바뀌었으면 분류 · 시대 구분 · 공통 날짜 칸 · 문화권 단위 줄(스키마 4) 가운데
///    배치와 다른 표만 지우고 다시 넣고 온 판 메타(문화권 · 간지 설정)를 옮겨 적는다. 하위 배치(`Covers::Part` — 닿는 트랙만 고쳐 쓰는 넣고 빼기)도
///    온 판을 통째로 실으므로 문화권 단위 줄은 늘 다시 셈한 것과 맞춘다. `meta.legacy`는 늘 통째 짓기와 같은 글로.
/// 7. `"entities"` — 항목 기록 전부를 uid · 지문으로 견주어 지움 · 바꿈 · 넣음 · 넣은 차례 다시 적기, 그림 바이트는 자료집으로([`put_entities`]).
///    지우기 · 차례 다시 적기는 배치가 기록 전부를 실었을 때만 — 모두 덮는 배치이거나, 덮는 트랙만 주되 지금 저장소의 DLC를 모두 실은 배치
///    ([`holds_every_pack`] — 과제 7a 얹힌 몫 7). "choose"에서 잰다.
/// 8. `"summaries"` — `Builder::finish_append`: 넣은 줄의 단계별 요약(대표마다 트랙 안 차례 `summaries.ords` — 판정 R24).
/// 9. `"range"` — 보는 범위(`meta.min` · `max` — [`put_range`]): 넣은 것으로 넓히고, 옛 끝값을 지운 것만 가졌으면 남은 것에서 다시 잰다
///    (문화권 단위 줄은 보지 않는다 — 짓기도 넓히지 않는다 · `builder::put_sphere_lines`).
/// 10. `"order"` — `tracks.ord`를 새 배치의 차례로 다시 적고(`RowMap`이 이 차례로 자리를 셈한다), 열쇠 ≠ 자리면 `meta.schema = '4.1'`
///     (`schema::VERSION_SPLIT` — 옛 판 '3' · '3.1' 저장소도 이 걸음이 스키마 4의 판으로 적는다).
/// 10′. `"renumber"` — 다시 쓰지 않은 트랙의 날짜 칸 이음 번호(온 판에 한 번 세는 번호 — 지문은 트랙 안 거리만 본다)를 새 배치의 번호로 옮긴다
///     ([`renumber_strips`] — 판정 R45 · R59 I-2: 덮는 꼴 셋 모두 · 배치가 말하는 트랙만). 조합 전부를 말하는 배치면 그 트랙 변형의 notes가 품은 트랙 순번도
///     새 차례로([`renumber_notes`] — 판정 R54 M6). 둘 다 표본 타일에 들지 않는다(날짜 칸은 뼈대 · notes는 점검 글) — `first_pos`는 그대로.
/// 11. `"names"` — 바뀐 것이 있으면(트랙 · 트랙 차례(판정 R27) · 항목 기록 · 온 판 · 뺀 DLC 가운데 하나라도) 사건의 덧줄(이번에 넣은 사건 · 기록이 바뀐 uid에 닿는 사건 —
///     밑동 `uid#1` 포함)을 저장소의 기록으로 다시 적고, 이름 표 · 관점 이름을 넣은 차례로 통째로 다시 편다(과제 6 — [`put_names`]).
/// 12. `"prints"` — 다시 쓴 트랙 · 새로 든 트랙 · 온 판의 지문을 `track_prints`에(온 판 지문은 온 판을 고쳐 적었을 때만 새것 — 덮는 트랙만 주는 배치는
///     저장된 것 그대로).
/// 13. `"meta"` — 수 세기(지운 만큼 빼고 넣은 만큼 더함 — 1,000만에서 `count(*)`를 피함) · 자료집별 수 · 닿는 트랙 · `meta.now`([`put_meta`]) · 하위 배치가 아니면
///     규칙 판(`meta.rules` — 판정 R59 I-1 · R69-2)을 지운다(바깥 배치일 수 있다 — 실제 틈의 모두 덮는 넣고 빼기만 [`mark_rules`]로 다시 적는다).
/// 14. `"verify"` — COMMIT 전 표본 타일 대조(`verify::verify_in` 120 — `import_with`와 같은 문턱): 누락 · 중복이 있으면 Err(거래가 되돌려진다).
///     표본을 뜰 곳(판정 R29): 넣거나 빼는 트랙 · 트랙 차례 · 온 판이 바뀌면 저장소 전체, 다시 쓰기만이면 다시 쓴 덩이와 그 덩이에 걸친 앞뒤 끝 묶음
///     ([`touched_chunks`] — 과제 7c: 쓰기 시간이 저장소 크기와 무관하게), 기본 보기만(변형 · 이름 표는 같음 검사의 몫).
///
/// 온 판(표 · 지문 · 문화권 · 간지 설정)은 `Covers::All` · `Covers::Part`(조합 전부를 말하는 하위 배치 — P4 과제 9)일 때만 고쳐 적고 답의 `globals`도 그때만 참이다 — 덮는 트랙만 주는 배치는 저장소 전체의
/// 온 판을 말하지 않는다(그 배치의 문화권 목록에는 덮지 않은 트랙의 것이 없다). 명령이 받는 길(`.htlayout` → 덮는 트랙)은 [`order_from_request`].
pub fn apply(tx: &Transaction, input: &ApplyIn) -> Result<ApplyReport> {
    let started = Instant::now();
    let mut laps = Laps::new();
    let plan = input.plan;
    // 조합 전부를 말하는 배치(`All` · 하위 배치 `Part`) — 온 판 · 항목 기록 · 자료집 · 트랙 차례를 고쳐 적고 DLC 빼기를 받는다.
    let whole = input.covers.whole();

    laps.fail_point("choose")?;
    check_combination(tx, plan, input.remove, &input.covers)?;
    let new = prints(plan)?;
    // 내용을 싣는 열 · 표가 없던 옛 저장소(과제 A+ 1): "delete"의 [`ensure_schema`]가 만들되 빈 값이라 모든 트랙을 한 번 다시 써야 통째 짓기와 같다.
    // 덮는 트랙만 주는 배치는 저장소의 트랙을 다 덮어도 거절한다(SQL 오류 글 대신): 덮지 않는 트랙은 다시 쓸 재료가 없고, 다 덮어도 온 판(문화권 ·
    // 간지 설정)은 모두 덮는 배치만 적는데 "prints"가 온 판 지문을 새것으로 적어 다음 모두 덮는 apply도 끝내 채우지 않는다(A+ 검토 가).
    let older = older_missing(tx)?;
    if !older.is_empty() && !whole {
        return Err(refuse("rebuild", format!("이 저장소는 옛 엔진으로 지어 {}이 없습니다 — 덮는 트랙만 주는 배치로는 모든 트랙과 온 판을 함께 고쳐 쓸 수 없으니 \
            조합의 DLC를 모두 담은 배치 전체로 한 번 고쳐 써 주세요", older.join(" · "))));
    }
    let choice = match choose_from(tx, &new, &input.covers, !older.is_empty()) {
        Ok(c) => c,
        Err(e) => match e.downcast_ref::<SharedUids>() {
            Some(shared) => return Err(shared_refusal(tx, plan, shared)?),
            None => return Err(e),
        },
    };
    if choice.globals && !whole {
        // 문화권 단위 줄(`sphere_lines` — 스키마 4)이 달라서는 거절하지 않는다(문화권 · 간지 설정 메타와 같은 갈래): 켠 DLC에 따라 사람 띠가 늘 달라져
        // 거절하면 메이커 `.htlayout`이 자주 막힌다. 표는 적지 않고 온 판 지문('*')도 저장된 것 그대로 두어("prints") 다음 모두 덮는 배치가 맞춘다.
        let differ = GlobalDiffer { sphere_lines: false, ..global_tables_differ(tx, plan)? };
        if differ.any() {
            return Err(format!("덮는 트랙만 주는 배치로는 {}을 바꿀 수 없습니다 — 배치 전체를 주어 넣어 주세요", differ.names().join(" · ")).into());
        }
    }
    // 항목 기록 · 그림을 지우기까지 하는가(과제 7a 얹힌 몫 7): 모두 덮는 배치, 또는 덮는 트랙만 주되 지금 저장소의 DLC를 모두 실은 배치
    // ([`holds_every_pack`] — 하위 배치도 항목 기록 · 그림은 그 조합 전부를 싣는다는 약속). 자료집 행을 맞추기("packs") 전에 잰다.
    let records_all = whole || holds_every_pack(tx, plan)?;
    let before = RowMap::load(tx)?;

    laps.fail_point("packs")?;
    let packs = put_packs(tx, plan, input.originals)?;
    let pack_ids = PackIds::new(plan, &packs)?;

    laps.fail_point("delete")?;
    ensure_schema(tx)?;
    // 지우기 전 가장 큰 번호(얹힌 몫 6) — 변형 표가 없던 옛 저장소는 [`ensure_schema`]가 만든 뒤에 읽는다.
    let floors = Floors::read(tx)?;
    let stored = stored_tracks(tx)?;
    // 고쳐 쓰기 전 트랙 차례 — 다시 쓰지 않는 트랙의 notes 순번이 이 차례다("relink"의 [`renumber_notes`]).
    let old_order: Vec<String> = stored_order(tx)?.into_iter().map(|(k, _)| k).collect();
    let ids_of = |keys: &BTreeSet<String>| -> Result<BTreeMap<String, i64>> {
        keys.iter().map(|k| stored.get(k).map(|id| (k.clone(), *id)).ok_or_else(|| format!("저장소에 없는 트랙입니다: {k}").into())).collect()
    };
    let (rewrite, removed) = (ids_of(&choice.rewrite)?, ids_of(&choice.removed)?);
    let kept = remember(tx, &rewrite, &removed, &before)?;
    let mut gone = delete_tracks(tx, &kept, &rewrite, &removed)?;
    drop_packs(tx, input.remove, &mut gone)?;

    laps.fail_point("insert")?;
    let s: BTreeSet<String> = choice.rewrite.union(&choice.added).cloned().collect();
    let builder = if s.is_empty() { None } else { Some(insert_tracks(tx, plan, &new, &s, &packs, &kept, &floors, &before)?) };

    laps.fail_point("relink")?;
    relink(tx, &kept, &rewrite, &removed, floors.rows)?;

    // 온 판(표 · 문화권 · 간지 설정 · 온 판 지문)은 조합 전부를 말하는 배치(`Covers::All` · 하위 배치 `Part`)에서만 고쳐 적는다.
    let globals = choice.globals && whole;

    laps.fail_point("globals")?;
    let global = put_globals(tx, plan, &pack_ids, globals)?;

    laps.fail_point("entities")?;
    let mut entities = put_entities(tx, plan, &pack_ids, records_all, choice.globals)?;
    entities.changed.extend(std::mem::take(&mut gone.entities));

    laps.fail_point("summaries")?;
    let appended = match builder {
        Some(b) => b.finish_append()?,
        None => Appended::default(),
    };

    laps.fail_point("range")?;
    put_range(tx, appended.span)?;

    laps.fail_point("order")?;
    let after = put_order(tx, &new, &input.covers, &choice.added)?;

    laps.fail_point("renumber")?;
    // 다시 쓰지 않은 트랙의 날짜 칸 이음 번호를 새 배치의 번호로(판정 R45 · R59 I-2 — 덮는 꼴 셋 모두) — 배치가 말하는 트랙: 하위 배치(`Part`)는 조합 전부
    // (`allTracks`), 덮는 트랙만 주는 배치는 덮는 트랙, 모두 덮는 배치는 배치의 트랙 전부.
    let speaks: Vec<String> = match &input.covers {
        Covers::Part { order, .. } => order.clone(),
        Covers::Tracks(keys) => new.order.iter().filter(|k| keys.contains(*k)).cloned().collect(),
        Covers::All => new.order.clone(),
    };
    renumber_strips(tx, plan, &speaks, &s)?;
    // notes의 트랙 순번도(판정 R54 M6) — 조합 전부를 말하는 배치만(덮는 트랙만 주는 배치의 순번은 그 배치의 것).
    if whole {
        renumber_notes(tx, &old_order, &speaks, &s)?;
    }

    laps.fail_point("names")?;
    // 트랙 차례만 바뀐 배치(판정 R27): 지문은 순번을 빼므로 다시 쓰는 트랙이 없어도 자리가 바뀐다 — 이름 표가 빌리는 줄(자리로 고른다)과
    // 앱이 버릴 타일(`first_pos`)이 이것을 따른다.
    let moved = moved_from(&before, &after);
    // 바뀐 것이 하나도 없으면(같은 배치를 다시 넣음) 이름 표 · 덧줄을 건드리지 않는다.
    let names = !s.is_empty() || !removed.is_empty() || globals || !input.remove.is_empty() || entities.reordered || !entities.changed.is_empty()
        || moved.is_some();
    if names {
        put_names(tx, &appended.named, &entities.changed)?;
    }

    laps.fail_point("prints")?;
    let held_globals: Option<String> = tx.query_row("SELECT print FROM track_prints WHERE key=?1", [GLOBALS], |r| r.get(0)).optional()?;
    let changed = Prints {
        tracks: new.tracks.iter().filter(|(key, _)| choice.added.contains(*key) || choice.rewrite.contains(*key)).map(|(k, t)| (k.clone(), t.clone())).collect(),
        globals: if globals { new.globals.clone() } else { held_globals.unwrap_or_else(|| new.globals.clone()) },
        order: Vec::new(),
    };
    save_prints(tx, &changed)?;

    laps.fail_point("meta")?;
    // DLC 차례(`meta.pack_order`)를 적을 수 있는가: 조합 전부를 말한 배치, 또는 덮는 트랙만 주되 지금 저장소의 DLC를 모두 싣고 고쳐 쓴 뒤의 저장소가
    // 배치와 꼭 맞는 것(트랙 열쇠가 같고 트랙마다 저장된 지문이 배치의 지문과 같다 — 트랙은 그 배치의 통째 짓기와 같다. 온 판은 덮는 배치가 적지 않지만
    // 다음 넣기가 온 판 지문으로 따로 견준다).
    let order_known = whole || (records_all && {
        let held: HashMap<String, String> = tx.prepare("SELECT key,print FROM track_prints")?
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?.collect::<std::result::Result<_, _>>()?;
        held.len() == new.tracks.len() + usize::from(held.contains_key(GLOBALS)) && new.tracks.iter().all(|(k, t)| held.get(k) == Some(&t.print))
    });
    put_meta(tx, plan, &appended, &gone, &global, entities.count, order_known)?;
    // 규칙 판(판정 R59 I-1 · R69-2): `meta.rules`는 'Rust가 저장소의 원본으로 셈한 배치와 같다'는 약속이라 apply는 그것을 알 수 없다 — 모두 덮는 배치 ·
    // 덮는 트랙만 주는 배치(바깥 배치 — `{"op":"apply"}` · `apply-layout` · Node 배치 JSON · 메이커 `.htlayout`)는 지운다(다음 넣기가 한 번 모든 트랙).
    // 실제 틈의 모두 덮는 넣고 빼기는 부르는 쪽(`packs::relayout`)이 이 뒤에 [`mark_rules`]로 다시 적는다. 하위 배치(`Part`)는 그 흐름에서만 오고(저장소의
    // 규칙 판이 지금 것일 때만 — `packs::held`) 그대로 둔다.
    if !matches!(input.covers, Covers::Part { .. }) {
        tx.execute("DELETE FROM meta WHERE key='rules'", [])?;
    }

    laps.fail_point("verify")?;
    let ids = stored_tracks(tx)?;
    // 표본을 뜰 곳(판정 R29): (가) 넣거나 빼는 트랙 · 트랙 차례 바뀜 · 온 판 바뀜이 있으면 저장소 전체(넣고 빼면 뒤 트랙이 모두 자리를 옮긴다 —
    // `moved`도 늘 있다) (나) 다시 쓰기만이면 다시 쓴 덩이와 그 덩이에 걸친 앞뒤 끝 묶음(과제 7c — 저장소 전체에서 뜨면 표본 타일의 사건 수가
    // 저장소의 줄마다 사건 수를 따라 늘었다) (다) 기본 보기만(변형 · 이름 표는 같음 검사의 몫). 다시 쓴 트랙도 없으면(그대로인 배치 · 기록만 바뀜) 전체.
    let rewrite_only = !globals && moved.is_none() && choice.added.is_empty() && removed.is_empty();
    let focus = if rewrite_only {
        let blocks: Vec<(i64, i64)> = choice.rewrite.iter().filter_map(|key| ids.get(key))
            .filter_map(|id| after.blocks().iter().find(|b| b.track == *id).map(|b| (b.pos0, b.n))).collect();
        Some(touched_chunks(&blocks)).filter(|c| !c.is_empty())
    } else {
        None
    };
    let check = crate::verify::verify_in(tx, VERIFY_SAMPLES, focus.as_deref())?;
    if !check.ok() {
        return Err(format!("고쳐 쓴 저장소의 표본 타일 대조에서 누락 {} · 중복 {}이 나와 되돌렸습니다({})", check.missing, check.dup,
            check.first.unwrap_or_default()).into());
    }

    // 앱이 타일을 버릴 첫 자리: 다시 쓰거나 새로 든 트랙은 지금 자리, 사라진 트랙은 옛 자리(그 뒤 트랙이 당겨진다), 차례가 바뀐 첫 자리(판정 R27).
    let pos_in = |map: &RowMap, id: i64| map.blocks().iter().find(|b| b.track == id).map(|b| b.pos0);
    let first = choice.added.iter().chain(&choice.rewrite).filter_map(|key| ids.get(key)).filter_map(|id| pos_in(&after, *id))
        .chain(removed.values().filter_map(|id| pos_in(&before, *id))).chain(moved).min();
    let steps = laps.finish();
    Ok(ApplyReport {
        rewrote: choice.rewrite.iter().cloned().collect(),
        added: choice.added.iter().cloned().collect(),
        removed: choice.removed.iter().cloned().collect(),
        globals,
        first_pos: first.unwrap_or(if globals { 0 } else { -1 }),
        rows_before: before.total(),
        rows_after: after.total(),
        names,
        ms: started.elapsed().as_secs_f64() * 1000.0,
        steps,
    })
}

/// "verify"가 다시 쓰기만인 apply에서 표본을 뜰 줄 묶음(판정 R29 나 — 번호 차례 · 겹침 없음): 다시 쓴 덩이(지금 자리 `pos0` · 줄 수 `n`)마다
/// 그 덩이가 걸친 묶음 전부 — 덩이 안에 다 든 묶음과, 덩이의 첫 줄 · 끝 줄이 이웃 트랙의 줄과 함께 놓인 **앞뒤 끝 묶음**까지(끝 줄은 덩이에서
/// 가장 자주 바뀌는 곳이다 — 줄을 더하거나 빼면 거기다). 줄이 없는 덩이는 건너뛴다(그것뿐이면 빈 목록 — 부르는 쪽이 저장소 전체로 돌린다).
fn touched_chunks(blocks: &[(i64, i64)]) -> Vec<i64> {
    use crate::levels::CHUNK_ROWS;
    let mut out = BTreeSet::new();
    for &(pos0, n) in blocks.iter().filter(|(_, n)| *n > 0) {
        out.extend(pos0 / CHUNK_ROWS..=(pos0 + n - 1) / CHUNK_ROWS);
    }
    out.into_iter().collect()
}

/// 걸음별 시간(과제 7c — 측정용): 걸음 이름의 [`fail_point`]에서 앞 걸음을 끊어 적고 그 걸음의 실패 지점을 건다.
/// 걸음의 시간 = 그 걸음의 실패 지점에서 다음 걸음의 실패 지점까지(마지막 "verify"는 표본 대조가 끝날 때까지).
struct Laps {
    at: Instant,
    current: Option<&'static str>,
    done: Vec<(&'static str, f64)>,
}

impl Laps {
    fn new() -> Self {
        Self { at: Instant::now(), current: None, done: Vec::new() }
    }

    /// 앞 걸음을 끊고 `name` 걸음을 연다 — 그 이름이 걸려 있으면 Err(`write::fail_point` — 주입한 실패).
    fn fail_point(&mut self, name: &'static str) -> Result<()> {
        self.cut();
        self.current = Some(name);
        fail_point(name)
    }

    fn cut(&mut self) {
        let now = Instant::now();
        if let Some(name) = self.current.take() {
            self.done.push((name, (now - self.at).as_secs_f64() * 1000.0));
        }
        self.at = now;
    }

    fn finish(mut self) -> Vec<(&'static str, f64)> {
        self.cut();
        self.done
    }
}

impl ApplyReport {
    /// 명령의 답(계약 2-7 — FFI `{"op":"apply"}` · `archive-tool apply-layout`). 명령은 `ms`를 명령 전체의 시간으로 바꿔 적는다.
    /// `steps`(덧붙인 칸 — 과제 7c)는 걸음별 ms를 `[[걸음 이름, ms], …]`로 걸음 차례대로.
    pub fn to_json(&self) -> Value {
        let steps: Vec<Value> = self.steps.iter().map(|(name, ms)| json!([name, ms])).collect();
        json!({"rewrote":self.rewrote,"added":self.added,"removed":self.removed,"globals":self.globals,"first_pos":self.first_pos,
            "rows_before":self.rows_before,"rows_after":self.rows_after,"names":self.names,"ms":self.ms,"steps":steps})
    }
}

// ---------------------------------------------------------------- 명령 입구(과제 7a)

/// 넣고 빼기 명령(계약 2-7)이 받은 덮는 트랙.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoversAsk {
    /// 주지 않음 — 배치 JSON은 모두 덮고, `.htlayout`은 그 배치의 트랙만.
    Default,
    /// `"all"` — 배치에 없는 트랙 · DLC는 사라진다(배치 JSON만).
    All,
    /// 이 트랙 열쇠([`track_key`])만 덮는다(배치 JSON만).
    Tracks(BTreeSet<String>),
}

/// 넣고 빼기 명령의 재료 — 파일을 다 읽은 것. FFI `{"op":"apply"}`(앱)와 `archive-tool apply-layout`(컴퓨터 도구)이 함께 쓴다.
pub struct ApplyOrder {
    pub plan: Value,
    /// (자료집 글자 id, .htpack 바이트).
    pub originals: Vec<(String, Vec<u8>)>,
    pub covers: Covers,
    pub remove: Vec<String>,
    /// 배치 JSON(노드 내보내기 — 원본으로 셈한 배치)인가. 그러면 배치의 DLC마다 원본이 저장소에 있거나 함께 와야 한다([`run_order`]).
    pub from_originals: bool,
}

/// 파일을 읽어 명령의 재료로(계약 2-7). 저장소는 만지지 않는다(잠금 없이 읽고 쓰기는 [`run_order`]가 거래 안에서).
/// - 배치: 확장자가 `.htlayout`이면 메이커의 아카이브 배치(팩 파일 종류 3) — 덮는 트랙은 **그 배치의 트랙**뿐이다(계획 정한 것 #8 — 모두 덮으면 메이커가
///   불러오지 않은 DLC가 조용히 사라진다). 그때 `covers`를 주면 거절한다. 아니면 배치 JSON(노드 내보내기) — `covers`를 주지 않으면 모두 덮는다.
/// - 원본: 전용 팩(.htpack)마다 id를 읽어 (id, 바이트)로. id가 없거나 같은 id가 둘이면 Err. 새로 들거나 판이 바뀐 DLC의 것만 주면 된다
///   (그대로인 DLC는 저장소의 원본 `packs.original`이 그대로 남는다 — 계획 정한 것 #12).
pub fn read_order(layout: &Path, originals: &[PathBuf], remove: Vec<String>, covers: CoversAsk) -> Result<ApplyOrder> {
    let maker = layout.extension().and_then(|s| s.to_str()).is_some_and(|s| s.eq_ignore_ascii_case("htlayout"));
    if matches!(&covers, CoversAsk::Tracks(keys) if keys.is_empty()) {
        return Err("덮는 트랙 목록(covers)이 비었습니다".into());
    }
    let plan = crate::legacy::read_plan(layout)?;
    let covers = match (maker, covers) {
        (true, CoversAsk::Default) => Covers::Tracks(prints(&plan)?.order.into_iter().collect()),
        (true, _) => return Err("아카이브 배치(.htlayout)는 그 배치의 트랙만 덮습니다 — 덮는 트랙(covers)을 따로 주지 않습니다".into()),
        (false, CoversAsk::Default | CoversAsk::All) => Covers::All,
        (false, CoversAsk::Tracks(keys)) => Covers::Tracks(keys),
    };
    let mut packs: Vec<(String, Vec<u8>)> = Vec::with_capacity(originals.len());
    for path in originals {
        let raw = crate::read_htpack(path).map_err(|e| format!("원본을 읽지 못했습니다({}): {e}", path.display()))?;
        let Some(id) = raw["id"].as_str().filter(|id| !id.is_empty()).map(str::to_owned) else {
            return Err(format!("원본에 DLC id가 없습니다: {}", path.display()).into());
        };
        if packs.iter().any(|(k, _)| *k == id) {
            return Err(format!("«{id}»의 원본을 둘 받았습니다").into());
        }
        packs.push((id, std::fs::read(path)?));
    }
    Ok(ApplyOrder { plan, originals: packs, covers, remove, from_originals: !maker })
}

/// 앱이 글을 읽지 않고 가를 수 있는 거절(계약 2-7 답의 `code` — 과제 8 고침 1회차 · 목록은 계약 2-7 · 2-7-1이 기준). 이 파일(`apply`)이 내는 것:
/// `rebuild` 옛 엔진으로 지은 저장소(덮는 트랙만 주는 배치로는 못 고침 — 모두 덮는 배치로 한 번 고쳐 쓰면 받는다) · `base` 기본팩이 다름 ·
/// `original` 원본이 없음(저장소에도 받은 파일에도 없거나 판이 바뀐 DLC의 새 원본이 없음) · `dup_uid` 같은 uid의 띠 · 사건이 두 트랙(판정 R37).
/// `packs`(`add_pack` · `remove_pack`)가 내는 것: `version` 같은 id의 낮은 판(판정 R15) · `calendar` 저장소의 달력 표 문제 · `range` · `layout` · `broken`
/// (이번에 받은 DLC 탓일 때만 — 판정 R62 · R70 · R72-3) · `original`. `lib`의 `path`(쓰기 요청의 저장소가 열린 저장소와 다름). 글(`error`)은 사람에게
/// 그대로이고 `detail`은 개발자 말(앱의 자세히 보기). 그 밖의 거절에는 `code`가 없다.
#[derive(Debug)]
pub struct Refusal {
    pub code: &'static str,
    pub message: String,
    /// 자세히 보기(개발자 말 그대로 — 배치 실패의 원래 글 등 · 고침 2회차 R61). 없으면 None.
    pub detail: Option<String>,
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for Refusal {}

fn refuse(code: &'static str, message: String) -> Box<dyn std::error::Error + Send + Sync> {
    Box::new(Refusal { code, message, detail: None })
}

/// FFI `{"op":"apply","layout","originals"?,"remove"?,"covers"?}`의 요청 → [`read_order`].
pub fn order_from_request(q: &Value) -> Result<ApplyOrder> {
    let layout = q["layout"].as_str().filter(|s| !s.is_empty()).ok_or("배치 경로(layout)가 없습니다")?;
    let words = |key: &str, what: &str| -> Result<Vec<String>> {
        let wrong = || -> crate::Result<Vec<String>> { Err(format!("{key}는 {what}의 목록이어야 합니다").into()) };
        match &q[key] {
            Value::Null => Ok(Vec::new()),
            Value::Array(list) => {
                let mut out = Vec::with_capacity(list.len());
                for v in list {
                    match v.as_str() {
                        Some(s) if !s.is_empty() => out.push(s.to_owned()),
                        _ => return wrong(),
                    }
                }
                Ok(out)
            }
            _ => wrong(),
        }
    };
    let originals: Vec<PathBuf> = words("originals", "경로 글")?.into_iter().map(PathBuf::from).collect();
    let remove = words("remove", "DLC id 글")?;
    let covers = match &q["covers"] {
        Value::Null => CoversAsk::Default,
        Value::String(s) if s == "all" => CoversAsk::All,
        Value::Array(_) => CoversAsk::Tracks(words("covers", "트랙 열쇠 글")?.into_iter().collect()),
        _ => return Err("covers는 \"all\" 또는 트랙 열쇠 글의 목록이어야 합니다".into()),
    };
    read_order(Path::new(layout), &originals, remove, covers)
}

/// 명령의 재료로 고쳐 쓴다 — 부르는 쪽의 쓰기 거래 안에서(앱은 `with_store_write`, 도구는 `write::write`). 배치 JSON이면 먼저
/// [`require_originals`]를 본 뒤 [`apply`].
pub fn run_order(tx: &Transaction, o: &ApplyOrder) -> Result<ApplyReport> {
    if o.from_originals {
        require_originals(tx, &o.plan, &o.originals)?;
    }
    apply(tx, &ApplyIn { plan: &o.plan, originals: &o.originals, covers: o.covers.clone(), remove: &o.remove })
}

/// 배치 JSON의 DLC마다 원본이 저장소에 있거나(`packs.original`) 함께 왔는가 — 없으면 "그 DLC 파일을 다시 골라 주세요"로 멈춘다(옛 DLC의 약속 2).
/// 배치 JSON은 원본으로 셈한 것이라(노드 내보내기) 원본 없이 받으면 그 셈의 근거가 저장소에 남지 않는다. 메이커 배치(.htlayout)로 원본 없이 든 DLC는
/// 처음 배치 JSON으로 넣을 때 그 파일을 `originals`로 주면 "packs"가 저장소 안으로 들인다(`add-dlc.mjs --apply`가 `DLC/` 폴더에서 찾아 준다).
/// 판이 바뀐 DLC(배치의 판 ≠ 저장소 `pack_info`의 판 — 둘 다 알 때)도 원본을 함께 받아야 한다("판이 바뀐 DLC는 원본을 함께 주세요").
fn require_originals(db: &Connection, plan: &Value, originals: &[(String, Vec<u8>)]) -> Result<()> {
    let keys = meta_json(db, "pack_keys");
    let mut held: HashMap<String, bool> = HashMap::new();
    {
        let mut stmt = db.prepare("SELECT id,original IS NOT NULL FROM packs")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, bool>(1)?)))? {
            let (id, has) = row?;
            if let Some(key) = keys[&id.to_string()].as_str() {
                held.insert(key.to_owned(), has);
            }
        }
    }
    let wants = wanted_packs(plan, None);
    let given = |key: &str| originals.iter().any(|(k, _)| k == key);
    let missing: Vec<String> = wants.iter().filter(|w| {
        let key = w.key.as_deref().unwrap_or("");
        !given(key) && !held.get(key).copied().unwrap_or(false)
    }).map(|w| format!("«{}»({})", w.name, w.key.as_deref().unwrap_or(""))).collect();
    if !missing.is_empty() {
        return Err(refuse("original", format!("원본이 저장소에도 받은 파일에도 없는 DLC가 있습니다: {} — 그 DLC 파일을 다시 골라 주세요", missing.join(" · "))));
    }
    // 판이 바뀐 DLC(배치의 판 ≠ 저장소 `pack_info`의 판 — 둘 다 알 때)는 새 원본을 함께 받아야 한다. 아니면 원본 바이트는 옛 판 · 자료는 새 판이 된다
    // (고침 1회차 Minor 2). 판을 견주는 것은 원본 짝짓기의 몫이다 — 조합 대조(R15)는 판을 보지 않는다.
    let info = meta_json(db, "pack_info");
    for w in &wants {
        let key = w.key.as_deref().unwrap_or("");
        if given(key) || w.version.is_empty() {
            continue;
        }
        let have = info.as_object().into_iter().flat_map(|m| m.values()).find(|v| v["id"] == key).map(|v| version_text(&v["version"])).unwrap_or_default();
        if !have.is_empty() && have != w.version {
            return Err(refuse("original", format!("«{}»의 판이 저장소와 다릅니다(저장소 v{have} · 배치 v{}) — 판이 바뀐 DLC는 원본을 함께 주세요", w.name, w.version)));
        }
    }
    Ok(())
}

/// 넣기 전 · 뒤의 자리 차례 트랙 열이 처음 갈리는 자리(판정 R27 — 트랙 차례만 바뀐 배치도 '바뀐 것'). 같으면 None.
/// 그 자리 앞의 트랙은 같은 트랙이 같은 차례로 놓였다(줄 수가 바뀐 트랙은 다시 쓴 트랙이라 `first_pos`가 따로 잡는다).
fn moved_from(before: &RowMap, after: &RowMap) -> Option<i64> {
    let (old, new) = (before.blocks(), after.blocks());
    (0..old.len().max(new.len())).find_map(|i| match (old.get(i), new.get(i)) {
        (Some(x), Some(y)) if x.track == y.track => None,
        (x, y) => x.into_iter().chain(y).map(|b| b.pos0).min(),
    })
}

/// COMMIT 전 표본 타일 대조의 표본 수(`import_with` · `add-dlc.mjs`의 `verify-tiles 120`과 같다).
const VERIFY_SAMPLES: i64 = 120;

/// meta 한 칸을 적는다(있으면 바꿔 적는다).
/// `meta.rules`에 지금 규칙 판([`rules_mark`])을 적는다 — 저장소가 지금 엔진(Rust)이 저장된 원본으로 셈한 통째 배치와 같을 때만 부른다(판정 R69-2:
/// 짓기 `legacy::build_store` · 실제 틈의 모두 덮는 넣고 빼기 `packs::relayout`).
pub fn mark_rules(db: &Connection) -> Result<()> {
    set_meta(db, "rules", &rules_mark())
}

fn set_meta(db: &Connection, key: &str, value: &str) -> Result<()> {
    db.prepare_cached("INSERT OR REPLACE INTO meta(key,value) VALUES(?1,?2)")?.execute([key, value])?;
    Ok(())
}

/// 배치의 값이 들어갈 자료집의 저장소 번호 — `legacy::fill_into`의 `pack_at`과 같은 규칙(`pack` 순번 → uid의 앞머리(`<DLC id>/…`) → 기본팩).
/// "packs"가 배치의 자료집을 모두 저장소에 맞춘 뒤에 만든다.
struct PackIds {
    /// 배치 `packs[]` 순번 → 저장소 번호.
    ids: Vec<i64>,
    by_key: HashMap<String, i64>,
}

impl PackIds {
    fn new(plan: &Value, packs: &HashMap<String, i64>) -> Result<Self> {
        let mut ids = Vec::new();
        let mut by_key = HashMap::new();
        for d in list(plan, "packs") {
            let key = text(d, "id");
            let id = *packs.get(key).ok_or_else(|| format!("배치의 자료집 «{key}»이 저장소에 없습니다"))?;
            ids.push(id);
            by_key.insert(key.to_owned(), id);
        }
        if ids.is_empty() {
            return Err("배치에 DLC가 없습니다".into());
        }
        Ok(Self { ids, by_key })
    }

    /// 기본팩(배치 `packs[]`의 첫째) — 분류 · 시대 구분의 자료집(`fill_into`와 같다).
    fn first(&self) -> i64 {
        self.ids[0]
    }

    /// 그 값이 들어갈 자료집의 저장소 번호(`legacy::pack_slot` — 짓기 · 지문과 같은 규칙).
    fn of(&self, v: &Value, uid: &str) -> i64 {
        self.ids[pack_slot(v, uid, self.ids.len(), |head| self.by_key.get(head).and_then(|id| self.ids.iter().position(|x| x == id)))]
    }
}

/// 배치와 다른 온 판 표.
#[derive(Debug, Default)]
struct GlobalDiffer {
    categories: bool,
    epochs: bool,
    axis: bool,
    /// 문화권 단위 줄(스키마 4 · 계약 1-1 — `sphere_lines`). 덮는 트랙만 주는 배치(`Covers::Tracks`)도 이것이 달라서는 거절하지 않는다([`apply`]의 "choose").
    sphere_lines: bool,
}

impl GlobalDiffer {
    fn any(&self) -> bool {
        self.categories || self.epochs || self.axis || self.sphere_lines
    }

    fn names(&self) -> Vec<&'static str> {
        [(self.categories, "분류"), (self.epochs, "시대 구분"), (self.axis, "공통 날짜 칸"), (self.sphere_lines, "문화권 줄")].into_iter()
            .filter(|(on, _)| *on).map(|(_, name)| name).collect()
    }
}

/// 표에 든 온 판(분류 · 시대 구분 · 공통 날짜 칸 · 문화권 단위 줄)이 배치와 다른가 — 값은 `fill_into`가 넣는 꼴 그대로 견준다(분류는 차례대로 · 시대 구분 ·
/// 공통 날짜 칸 · 문화권 단위 줄은 넣은 차례대로 · 공통 날짜 칸 · 문화권 단위 줄의 자료집은 글자 id로). 표가 작아 통째로 읽는다.
/// 문화권 단위 줄 표(`sphere_lines`)는 없을 수 있다(스키마 4 전의 옛 저장소 — "choose"는 [`ensure_schema`]보다 앞이다) — 그러면 빈 표로 본다.
fn global_tables_differ(db: &Connection, plan: &Value) -> Result<GlobalDiffer> {
    let packs = Packs::new(plan);
    let keys = meta_json(db, "pack_keys");
    let mut labels: HashMap<i64, String> = HashMap::new();
    {
        let mut stmt = db.prepare("SELECT id,name FROM packs")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))? {
            let (id, name) = row?;
            let key = keys[&id.to_string()].as_str().unwrap_or("");
            labels.insert(id, if key.is_empty() { name } else { key.to_owned() });
        }
    }
    let rows = |sql: &str, f: &dyn Fn(&rusqlite::Row) -> rusqlite::Result<Value>| -> Result<Vec<Value>> {
        let mut stmt = db.prepare(sql)?;
        let list = stmt.query_map([], |r| f(r))?.collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(list)
    };
    let categories: Vec<Value> = list(plan, "categories").iter().map(|c| json!([text(c, "key"), text(c, "name"), int(c, "color") as u32])).collect();
    let epochs: Vec<Value> = list(plan, "epochs").iter().map(|e| json!([int(e, "start"), int(e, "end"), int(e, "color") as u32, text(e, "name")])).collect();
    let axis: Vec<Value> = list(plan, "axis").iter().filter(|a| int_or(a, "track", -1) < 0).map(|a| json!([packs.of(a, ""), int(a, "kind"), int(a, "lane"),
        int(a, "start"), int(a, "end"), text(a, "name"), int(a, "color") as u32, int(a, "style"), int(a, "strip"), int(a, "seq")])).collect();
    // 문화권 단위 줄 — 짓기가 읽는 꼴 그대로(`builder::SphereLineIn::read` — 수는 띠와 같은 규칙 · `data`는 글 그대로 / JSON 글 / 빈 글).
    let sphere_lines: Vec<Value> = list(plan, "sphereLines").iter().map(|l| {
        let line = crate::builder::SphereLineIn::read(l, 0);
        json!([packs.of(l, line.uid), line.sphere, line.kind, line.start, line.end, line.name, line.uid, line.color, line.data.as_ref()])
    }).collect();
    let stored_lines = if has_table(db, "sphere_lines")? {
        rows("SELECT pack,sphere,kind,start,end,name,uid,color,data FROM sphere_lines ORDER BY id", &|r| {
            let pack = labels.get(&r.get::<_, i64>(0)?).cloned().unwrap_or_default();
            Ok(json!([pack, r.get::<_, String>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?, r.get::<_, i64>(4)?, r.get::<_, String>(5)?, r.get::<_, String>(6)?,
                r.get::<_, i64>(7)?, r.get::<_, String>(8)?]))
        })?
    } else {
        Vec::new()
    };
    Ok(GlobalDiffer {
        categories: categories != rows("SELECT key,name,color FROM categories ORDER BY ord,id", &|r| Ok(json!([r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?])))?,
        epochs: epochs != rows("SELECT start,end,color,name FROM epochs ORDER BY id", &|r| Ok(json!([r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, String>(3)?])))?,
        axis: axis != rows("SELECT pack,kind,lane,start,end,name,color,style,strip,seq FROM axis_cells WHERE track IS NULL ORDER BY id", &|r| {
            let pack = labels.get(&r.get::<_, i64>(0)?).cloned().unwrap_or_default();
            Ok(json!([pack, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?, r.get::<_, i64>(4)?, r.get::<_, String>(5)?, r.get::<_, i64>(6)?,
                r.get::<_, i64>(7)?, r.get::<_, i64>(8)?, r.get::<_, i64>(9)?]))
        })?,
        sphere_lines: sphere_lines != stored_lines,
    })
}

/// "globals"가 고친 것 — "meta"가 수 세기에 더한다.
#[derive(Debug, Default)]
struct GlobalsDone {
    /// 분류를 다시 넣었으면 그 수(`meta.categories`).
    categories: Option<i64>,
    /// 공통 날짜 칸 수의 바뀜(`meta.axis_cells`에 더함).
    axis: i64,
}

/// "globals" — 온 판. `rewrite`(모두 덮는 배치에서 온 판 지문이 바뀜)면 분류 · 시대 구분 · 공통 날짜 칸 · 문화권 단위 줄(스키마 4 — `sphere_lines`) 가운데
/// **배치와 다른 표만** 지우고 다시 넣고(값 · 자료집은 `legacy::fill_into`가 넣는 꼴 그대로 — 분류 · 시대 구분은 기본팩, 공통 날짜 칸 · 문화권 단위 줄은
/// 그 값의 자료집), 배치의 온 판 메타
/// (문화권 · 간지 설정 — `legacy::plan_meta`)를 옮겨 적는다(배치에 없는 것은 지움). 분류 번호(사건 `look`)가 바뀌는 배치는 그 사건들의 트랙 지문이
/// 바뀌어 이미 다시 썼다(계획 정한 것 #13). 다시 넣은 행의 번호는 이어서 나지만 이 표들의 번호는 아무도 가리키지 않는다(답의 차례는
/// 분류 `ord` · 시작 · 내용).
/// `meta.legacy`(원본을 다 품었는가의 글 — 얹힌 몫 4)는 늘 통째 짓기와 같은 규칙으로 고쳐 적는다: 자료집이 모두 원본을 품었으면 '보존', 아니면 '원본 없는 DLC가 있음'.
fn put_globals(db: &Connection, plan: &Value, packs: &PackIds, rewrite: bool) -> Result<GlobalsDone> {
    let mut done = GlobalsDone::default();
    if rewrite {
        let differ = global_tables_differ(db, plan)?;
        if differ.categories {
            db.execute("DELETE FROM categories", [])?;
            let mut add = db.prepare("INSERT INTO categories(pack,ord,key,name,color) VALUES(?1,?2,?3,?4,?5)")?;
            let categories = list(plan, "categories");
            for (ord, c) in categories.iter().enumerate() {
                add.execute(params![packs.first(), ord as i64, text(c, "key"), text(c, "name"), int(c, "color") as u32])?;
            }
            done.categories = Some(categories.len() as i64);
        }
        if differ.epochs {
            db.execute("DELETE FROM epochs", [])?;
            let mut add = db.prepare("INSERT INTO epochs(pack,start,end,color,name) VALUES(?1,?2,?3,?4,?5)")?;
            for e in list(plan, "epochs") {
                add.execute(params![packs.first(), int(e, "start"), int(e, "end"), int(e, "color") as u32, text(e, "name")])?;
            }
        }
        if differ.axis {
            let old = db.execute("DELETE FROM axis_cells WHERE track IS NULL", [])? as i64;
            let mut add = db.prepare("INSERT INTO axis_cells(pack,kind,track,lane,start,end,name,color,style,strip,seq) VALUES(?1,?2,NULL,?3,?4,?5,?6,?7,?8,?9,?10)")?;
            let mut new = 0;
            for a in list(plan, "axis").iter().filter(|a| int_or(a, "track", -1) < 0) {
                if int(a, "start") > int(a, "end") {
                    return Err("날짜 칸의 기간이 뒤집혔습니다".into());
                }
                add.execute(params![packs.of(a, ""), int(a, "kind"), int(a, "lane"), int(a, "start"), int(a, "end"), text(a, "name"), int(a, "color") as u32,
                    int(a, "style"), int(a, "strip"), int(a, "seq")])?;
                new += 1;
            }
            done.axis = new - old;
        }
        if differ.sphere_lines {
            // 통째로 지우고 배치 차례대로 다시 넣는다 — 번호가 1부터 나서 통째 짓기와 같다(`id` 차례 = 배치 차례 · 자료집은 짓기와 같은 규칙).
            // 보는 범위(`meta.min` · `max` — "range"의 [`put_range`] · [`holds`] · [`farthest`])는 이 표를 보지 않는다(짓기도 넓히지 않는다 — kind 3은 0분).
            db.execute("DELETE FROM sphere_lines", [])?;
            crate::builder::put_sphere_lines(db, list(plan, "sphereLines"), |v, uid| packs.of(v, uid))?;
        }
        for (key, value) in plan_meta(plan)? {
            match value {
                Some(value) => set_meta(db, key, &value)?,
                None => {
                    db.execute("DELETE FROM meta WHERE key=?1", [key])?;
                }
            }
        }
    }
    let missing: i64 = db.query_row("SELECT count(*) FROM packs WHERE original IS NULL", [], |r| r.get(0))?;
    set_meta(db, "legacy", if missing == 0 { crate::legacy::KEPT_NOTE } else { crate::legacy::PARTIAL_NOTE })?;
    Ok(done)
}

/// "entities"가 고친 것 — "names"가 이름 표 · 덧줄을 다시 펼지 · 어느 사건의 덧줄을 다시 적을지, "meta"가 기록 수를 정한다.
#[derive(Debug, Default)]
struct EntitiesDone {
    /// `meta.entities`의 새 값(아래 [`put_entities`]).
    count: i64,
    /// 지우거나 넣거나 바꾼(자료집 · 갈래 · 본문) 기록의 uid — 그 uid(또는 밑동이 그 uid인 `uid#1`)의 사건 덧줄을 다시 적는다(얹힌 몫 4).
    /// 빼는 DLC의 기록("delete"의 [`drop_packs`]가 지운 것)은 부르는 쪽이 더한다.
    changed: BTreeSet<String>,
    /// 넣은 차례만 바뀐 기록이 있다 — 가문 · 단체 · 제도의 이름 표 차례가 바뀐다.
    reordered: bool,
}

/// "entities" — 항목 기록을 트랙 주인과 상관없이 uid · 지문(`entities.sum` — json 글의 SHA-256 앞 16자)으로 모두 견준다(계획 정한 것 #6).
/// 지문이 없는 옛 저장소(열을 막 더해 빈 글)는 모두 바꿔 적는다(한 번).
/// - 배치가 기록 전부를 실었으면(`whole` — 모두 덮는 배치, 또는 덮는 트랙만 주되 지금 저장소의 DLC를 모두 실은 배치 · [`holds_every_pack`]):
///   배치에 없는 uid는 지우고, 자료집 · 갈래 · 지문이 다르거나 없는 것은 바꿔 넣고, 넣은 차례(`ord`)는 새 배치의
///   `entities` 배열 차례(겉 열쇠 `boards`의 것은 뒤에 이어서)로 다시 적는다 — 같은 uid가 둘이면 통째 짓기처럼 본문 · 갈래 · 자료집은 뒤엣것,
///   차례는 처음 것(`builder::EntityOrder` — 과제 6 얹힌 몫 1). 이름 표 · 관점 이름은 "names"가 다시 편다.
/// - 아니면(지금 저장소의 DLC 가운데 배치에 없는 것이 있음 — 메이커가 그 DLC를 불러오지 않고 내보낸 배치): 배치의 기록을 넣거나 바꿀 뿐 지우지 않고
///   그대로인 기록의 차례도 그대로 둔다(배치에 없는 기록은 배치가 싣지 않은 DLC의 것일 수 있다).
/// - 그림 바이트(`blobs` — 자료집에 딸린 문서 그림)는 온 판 지문이 바뀐 배치(`globals_changed`)에서만 (열쇠, 자료집, 종류, 바이트의 SHA-256)으로 견주어
///   바뀐 · 새 것은 바꿔 넣고, 기록 전부를 실었으면 빠진 것은 지운다(얹힌 몫 3 — 저장소의 그림을 모두 읽어 해시하므로 온 판이 그대로면 돌지 않는다).
///   열쇠 · 종류 · base64가 올바르지 않으면 통째 짓기와 같은 글로 Err.
///
/// `count`(`meta.entities`의 새 값)는 기록 전부를 실었으면 통째 짓기의 규칙(넣은 기록 수: 같은 uid도 따로 센다 = 배치의 기록 수), 아니면 표의 줄 수.
fn put_entities(db: &Connection, plan: &Value, packs: &PackIds, whole: bool, globals_changed: bool) -> Result<EntitiesDone> {
    let all = with_boards(plan, "entities");
    let mut want: BTreeMap<&str, (i64, i64, &str, &str, String)> = BTreeMap::new();
    let mut order = crate::builder::EntityOrder::default();
    for (at, en) in all.iter().enumerate() {
        let uid = text(en, "uid");
        if uid.is_empty() {
            return Err("항목 기록에 id가 없습니다".into());
        }
        let (json, kind) = (text(en, "json"), text(en, "kind"));
        let sum = format!("{:x}", Sha256::digest(json.as_bytes()))[..16].to_owned();
        want.insert(uid, (order.place(uid, kind, at as i64), packs.of(en, uid), kind, json, sum));
    }
    let mut have: HashMap<String, (i64, String, i64, String)> = HashMap::new();
    {
        let mut stmt = db.prepare("SELECT uid,pack,kind,ord,sum FROM entities")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, (r.get::<_, i64>(1)?, r.get::<_, String>(2)?, r.get::<_, i64>(3)?, r.get::<_, String>(4)?))))? {
            let (uid, rest) = row?;
            have.insert(uid, rest);
        }
    }
    let mut done = EntitiesDone::default();
    if whole {
        // 정해진 차례(uid 차례)로 지운다 — HashMap 차례로 지우면 같은 입력에도 쪽 배치가 달라져 저장소 바이트가 매번 갈렸다(canon은 같음 · 판정 R65).
        let mut gone: Vec<&String> = have.keys().filter(|uid| !want.contains_key(uid.as_str())).collect();
        gone.sort();
        let mut forget = db.prepare("DELETE FROM entities WHERE uid=?1")?;
        for uid in gone {
            forget.execute([uid])?;
            done.changed.insert(uid.clone());
        }
    }
    {
        let mut put = db.prepare("INSERT OR REPLACE INTO entities(uid,pack,kind,json,ord,sum) VALUES(?1,?2,?3,?4,?5,?6)")?;
        let mut reorder = db.prepare("UPDATE entities SET ord=?2 WHERE uid=?1")?;
        for (uid, (ord, pack, kind, json, sum)) in &want {
            match have.get(*uid) {
                Some((p, k, o, s)) if p == pack && k == kind && s == sum => {
                    if whole && o != ord {
                        reorder.execute(params![uid, ord])?;
                        done.reordered = true;
                    }
                }
                _ => {
                    put.execute(params![uid, pack, kind, json, ord, sum])?;
                    done.changed.insert((*uid).to_owned());
                }
            }
        }
    }
    if globals_changed {
        put_blobs(db, plan, packs, whole)?;
    }
    done.count = if whole { all.len() as i64 } else { db.query_row("SELECT count(*) FROM entities", [], |r| r.get(0))? };
    Ok(done)
}

/// "names" — 바뀐 것이 있을 때 이름 찾기 · 검색의 덧붙은 색인을 통째 짓기와 같게 다시 편다(계획 P4 과제 6 · 정한 것 #5):
/// 1. 사건의 덧줄(다른 이름 — `x_find.hay`): 이번에 넣은 사건(`named`) ∪ 기록이 바뀐 uid(`changed`)에 닿는 사건(그 uid · 밑동이 그 uid인 `uid#…`)을
///    저장소의 기록으로 다시 적는다([`crate::builder::respread_event_hay`] — 다시 쓰지 않은 트랙의 사건도 · 얹힌 몫 4). 지운 사건의 덧줄은 "delete"가 지웠다.
/// 2. 이름 표 · 관점 이름: 항목 기록을 넣은 차례(`entities.ord`)로 다시 모아 통째로 다시 펴고([`crate::builder::rebuild_names`]) `meta.names` ·
///    `meta.lens_names`를 적는다. 띠 · 칸 · 날짜 칸 · 묶음 · 항목 기록에서 펴므로 저장소 전체에 비례한다(사건 수와는 무관 — 사건은 본문 색인이 맡는다).
fn put_names(tx: &Transaction, named: &[(i64, String)], changed: &BTreeSet<String>) -> Result<()> {
    // 본문 색인이 꺼진 저장소(`meta.search` 'off')에는 덧줄이 없다 — 사건을 찾지도 않는다.
    let search: Option<String> = tx.query_row("SELECT value FROM meta WHERE key='search'", [], |r| r.get(0)).optional()?;
    if search.as_deref() != Some("off") {
        put_event_hay(tx, named, changed)?;
    }
    let (names, lens) = crate::builder::rebuild_names(tx)?;
    set_meta(tx, "names", &names.to_string())?;
    set_meta(tx, "lens_names", &lens.to_string())?;
    Ok(())
}

/// [`put_event_hay`]가 기록이 바뀐 uid u에 닿는 사건을 찾는 SQL — u 자신(?1)과 밑동이 u인 이름(`u#…` — ?2 = 'u#' 이상 ?3 = 'u$' 미만, '#' 다음 글자는 '$')을
/// 색인 찾기 두 번으로. 사건의 이름 색인은 `uid<>''`인 부분 색인(`events_uid`)이라 그 조건을 두 갈래 모두에 적는다. 두 갈래는 겹치지 않는다(u < 'u#…').
/// 예전에는 `uid=?1 OR (uid>=?2 AND uid<?3)` 하나로 물었는데, 통계(ANALYZE)가 있는 저장소에서 SQLite가 이 OR를 색인 찾기로 풀지 못하고
/// 색인을 **통째로 훑어**(SCAN … USING COVERING INDEX events_uid) 바뀐 기록 하나마다 사건 표 전체를 읽었다 — 바뀐 기록 수 × 사건 수.
/// DLC를 넣고 빼면 바뀐 기록 ≈ 그 DLC의 사건 수라 넣기 · 빼기 시간의 99%가 여기였다(과제 perf — 잰 값은 계획 P4 과제 11).
const EVENTS_OF_UID_SQL: &str = "SELECT id,uid FROM events WHERE uid<>'' AND uid=?1 \
    UNION ALL SELECT id,uid FROM events WHERE uid<>'' AND uid>=?2 AND uid<?3";

/// [`put_names`]의 1 — 이번에 넣은 사건 ∪ 기록이 바뀐 uid에 닿는 사건의 덧줄을 다시 적는다.
fn put_event_hay(tx: &Transaction, named: &[(i64, String)], changed: &BTreeSet<String>) -> Result<()> {
    let mut events: BTreeMap<i64, String> = named.iter().cloned().collect();
    if !changed.is_empty() {
        let mut stmt = tx.prepare(EVENTS_OF_UID_SQL)?;
        for uid in changed {
            for row in stmt.query_map(params![uid, format!("{uid}#"), format!("{uid}$")], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))? {
                let (id, uid) = row?;
                events.insert(id, uid);
            }
        }
    }
    crate::builder::respread_event_hay(tx, &events)?;
    Ok(())
}

/// 그림 바이트를 배치와 맞춘다([`put_entities`] — 열쇠 · 자료집 · 종류 · 바이트의 SHA-256으로 견줌). 같은 열쇠가 둘이면 뒤엣것(통째 짓기의
/// INSERT OR REPLACE와 같다).
fn put_blobs(db: &Connection, plan: &Value, packs: &PackIds, whole: bool) -> Result<()> {
    // 열쇠 · 종류를 먼저 다 본다(쓰기 전에 거절). 바이트는 아래에서 하나씩 풀어 견주고 버린다(고침 2회차 M-2 — 그림을 한꺼번에 풀어 쥐지 않는다).
    let mut want: BTreeMap<&str, &Value> = BTreeMap::new();
    for bl in list(plan, "blobs") {
        let (key, mime) = (text(bl, "key"), text(bl, "mime"));
        if key.is_empty() || !mime.starts_with("image/") {
            return Err(format!("그림 바이트의 열쇠나 종류가 올바르지 않습니다: {key}").into());
        }
        want.insert(key, bl);
    }
    let mut have: HashMap<String, (i64, String, String)> = HashMap::new();
    {
        let mut stmt = db.prepare("SELECT key,pack,mime,bytes FROM blobs")?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            let (key, pack, mime): (String, i64, String) = (r.get(0)?, r.get(1)?, r.get(2)?);
            have.insert(key, (pack, mime, format!("{:x}", Sha256::digest(r.get_ref(3)?.as_bytes()?))));
        }
    }
    if whole {
        let mut forget = db.prepare("DELETE FROM blobs WHERE key=?1")?;
        // 저장소가 지어 넣은 것(달력 표 — `lay::CALENDAR_BLOB` · 과제 17)은 배치의 그림이 아니라 지우지 않는다.
        // 정해진 차례(열쇠 차례)로 지운다 — HashMap 차례면 같은 입력에도 바이트가 갈린다(판정 R65 · R70-2).
        let mut gone: Vec<&String> = have.keys().filter(|k| !want.contains_key(k.as_str()) && k.as_str() != crate::lay::CALENDAR_BLOB).collect();
        gone.sort();
        for key in gone {
            forget.execute([key])?;
        }
    }
    let mut put = db.prepare("INSERT OR REPLACE INTO blobs(key,pack,mime,bytes) VALUES(?1,?2,?3,?4)")?;
    for (key, bl) in &want {
        let (pack, mime) = (packs.of(bl, key.trim_start_matches("img:")), text(bl, "mime"));
        let bytes = crate::base64_decode(text(bl, "data")).ok_or_else(|| format!("그림 바이트를 풀 수 없습니다(base64): {key}"))?;
        let same = have.get(*key).is_some_and(|(p, m, sha)| *p == pack && m == mime && *sha == format!("{:x}", Sha256::digest(&bytes)));
        if !same {
            put.execute(params![key, pack, mime, bytes])?;
        }
    }
    Ok(())
}

/// 보는 범위의 한쪽 끝.
#[derive(Clone, Copy)]
enum End {
    Low,
    High,
}

/// 날짜 있는 기본 판 사건 — `Builder::event_at`이 보는 범위를 넓히는 사건(변형에서만 있는 사건 · 날짜 없는 사건은 넓히지 않는다).
const SPAN_EVENT: &str = "e.start IS NOT NULL AND e.end IS NOT NULL AND e.lo IS NOT NULL AND e.hi IS NOT NULL AND e.variant=0";

/// 그 값을 끝값으로 가진 행이 아직 있는가 — 띠 · 일반 항목 · 사건은 공간 색인으로 그 끝의 하루 둘레만 훑는다.
/// 공간 색인을 바깥 고리로 묶는다(`CROSS JOIN` — SQLite는 이것으로 표의 차례를 정한다): 그냥 JOIN이면 조회 계획이 사건 표를 통째로 훑고
/// 공간 색인을 번호로 찾아 1,000만에서 저장소 크기에 비례했다(과제 7c — 100만 장면에서 한 번에 230ms).
fn holds(db: &Connection, end: End, value: i64) -> Result<bool> {
    let (bound, edge, ev) = match end {
        End::Low => ("b.lo_day<=?2", "start", "lo"),
        End::High => ("b.hi_day>=?2", "end", "hi"),
    };
    let sql = format!(
        "SELECT EXISTS(SELECT 1 FROM period_bounds b CROSS JOIN periods p ON p.id=b.id WHERE {bound} AND p.{edge}=?1)
             OR EXISTS(SELECT 1 FROM item_bounds b CROSS JOIN items i ON i.id=b.id WHERE {bound} AND i.{edge}=?1)
             OR EXISTS(SELECT 1 FROM bounds b CROSS JOIN events e ON e.id=b.id WHERE {bound} AND e.{ev}=?1 AND {SPAN_EVENT})
             OR EXISTS(SELECT 1 FROM axis_cells WHERE {edge}=?1) OR EXISTS(SELECT 1 FROM epochs WHERE {edge}=?1)");
    Ok(db.query_row(&sql, params![value, value.div_euclid(crate::DAY)], |r| r.get(0))?)
}

/// 남은 모든 것에서 그 끝을 다시 잰다 — 띠 · 일반 항목 · 날짜 칸 · 시대 구분을 먼저 재고, 사건은 그 값을 넘지 않는 쪽만 공간 색인으로 훑는다
/// (그보다 바깥의 사건만 끝을 바꿀 수 있다 — 공간 색인을 바깥 고리로 · [`holds`]와 같은 까닭). 아무것도 없으면 None.
/// 띠 · 일반 항목 · 날짜 칸 · 시대 구분의 MIN/MAX는 색인 없이 그 표를 훑는다(띠 수에 비례 — 사건 수와는 무관 · 과제 7c에 잰 값).
fn farthest(db: &Connection, end: End) -> Result<Option<i64>> {
    let (agg, edge, ev, bound) = match end {
        End::Low => ("MIN", "start", "lo", "b.lo_day<=?1"),
        End::High => ("MAX", "end", "hi", "b.hi_day>=?1"),
    };
    let other: Option<i64> = db.query_row(&format!("SELECT {agg}(v) FROM (SELECT {agg}({edge}) v FROM periods UNION ALL SELECT {agg}({edge}) FROM items \
        UNION ALL SELECT {agg}({edge}) FROM axis_cells UNION ALL SELECT {agg}({edge}) FROM epochs)"), [], |r| r.get(0))?;
    let events: Option<i64> = match other {
        Some(v) => db.query_row(&format!("SELECT {agg}(e.{ev}) FROM bounds b CROSS JOIN events e ON e.id=b.id WHERE {bound} AND {SPAN_EVENT}"),
            [v.div_euclid(crate::DAY)], |r| r.get(0))?,
        None => db.query_row(&format!("SELECT {agg}(e.{ev}) FROM events e WHERE {SPAN_EVENT}"), [], |r| r.get(0))?,
    };
    Ok(match (other, events, end) {
        (Some(a), Some(b), End::Low) => Some(a.min(b)),
        (Some(a), Some(b), End::High) => Some(a.max(b)),
        (a, b, _) => a.or(b),
    })
}

/// "range" — 보는 범위(`meta.min` · `max` — 앱이 이것으로 화면 범위를 정한다 · 계획 정한 것 #7)를 통째 짓기와 같은 규칙으로 적는다
/// (`Builder::stretch` — 띠 · 일반 항목 · 날짜 칸 · 시대 구분의 시작 · 끝과 날짜 있는 기본 판 사건의 `lo` · `hi`, 아무것도 없으면 0 · 하루).
/// 끝마다: 옛 끝값을 남은 것이 아직 가지면 넣은 것(덧붙인 것 `added` · 온 판 — 작아 늘 다시 본다)으로 넓히기만 하고, 아무도 갖지 않으면
/// (지운 것만 그 값을 가졌다) 남은 것에서 다시 잰다([`farthest`]). 옛 값이 없는 저장소도 다시 잰다.
/// 문화권 단위 줄(`sphere_lines` — 스키마 4)은 [`holds`] · [`farthest`] · 이 함수 모두 보지 않는다 — 짓기도 그 줄로 넓히지 않아서다
/// (`builder::put_sphere_lines` — kind 3은 0분이라 넓히면 고대만 있는 자료의 1배 화면이 바뀐다).
fn put_range(db: &Connection, added: Option<(i64, i64)>) -> Result<()> {
    let read = |key: &str| -> Result<Option<i64>> {
        let text: Option<String> = db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get(0)).optional()?;
        Ok(text.and_then(|t| t.parse().ok()))
    };
    let small: (Option<i64>, Option<i64>) = db.query_row("SELECT MIN(s),MAX(e) FROM (SELECT start s,end e FROM epochs UNION ALL \
        SELECT start,end FROM axis_cells WHERE track IS NULL)", [], |r| Ok((r.get(0)?, r.get(1)?)))?;
    let lo_in = [added.map(|s| s.0), small.0].into_iter().flatten().min();
    let hi_in = [added.map(|s| s.1), small.1].into_iter().flatten().max();
    let min = match read("min")? {
        Some(old) if holds(db, End::Low, old)? => Some(lo_in.map_or(old, |lo| lo.min(old))),
        _ => farthest(db, End::Low)?,
    };
    let max = match read("max")? {
        Some(old) if holds(db, End::High, old)? => Some(hi_in.map_or(old, |hi| hi.max(old))),
        _ => farthest(db, End::High)?,
    };
    let (min, max) = match (min, max) {
        (Some(lo), Some(hi)) if lo <= hi => (lo, hi),
        _ => (0, crate::DAY),
    };
    set_meta(db, "min", &min.to_string())?;
    set_meta(db, "max", &max.to_string())?;
    Ok(())
}

/// "packs" — 배치의 자료집을 저장소에 맞춘다. 없던 DLC는 행을 넣고(원본을 함께 받았으면 품는다 — 없으면 `original` 없이: `import_with`와 같다),
/// 있던 DLC는 원본을 함께 받았고 지문이 다르면 원본을 바꿔 넣는다(판이 바뀐 DLC). 받은 원본은 전용 팩으로 풀어 보고 id · 판(둘 다 알 때)이
/// 배치와 맞아야 한다. `meta.pack_keys` · `pack_info`를 배치의 자료집 몫만 고쳐 적는다(판 · 분류는 배치의 것 → 받은 원본의 것 → 적혀 있던 것).
/// 빼는 DLC의 행 지우기는 "delete"의 [`drop_packs`]. 자료집 글자 id → 저장소 번호를 돌려준다.
fn put_packs(db: &Connection, plan: &Value, originals: &[(String, Vec<u8>)]) -> Result<HashMap<String, i64>> {
    let wants = wanted_packs(plan, None);
    let mut keys = meta_json(db, "pack_keys");
    let mut info = meta_json(db, "pack_info");
    let mut held: HashMap<String, (i64, String, Option<String>)> = HashMap::new();
    {
        let mut stmt = db.prepare("SELECT id,name,sha256 FROM packs")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<String>>(2)?)))? {
            let (id, name, sha) = row?;
            if let Some(key) = keys[&id.to_string()].as_str().filter(|k| !k.is_empty()) {
                held.insert(key.to_owned(), (id, name, sha));
            }
        }
    }
    for (key, _) in originals {
        if !wants.iter().any(|w| w.key.as_deref() == Some(key.as_str())) {
            return Err(format!("원본 «{key}»이 이 배치에 없습니다").into());
        }
    }
    let mut out = HashMap::new();
    for w in &wants {
        let key = w.key.as_deref().filter(|k| !k.is_empty()).ok_or_else(|| format!("배치의 자료집 «{}»에 DLC id가 없습니다", w.name))?;
        let given = originals.iter().find(|(k, _)| k == key).map(|(_, bytes)| bytes.as_slice());
        let raw = match given {
            Some(bytes) => {
                let raw = crate::htpack_raw(bytes)?;
                let id = raw["id"].as_str().unwrap_or("");
                if id != key {
                    return Err(format!("원본의 id({id})가 배치의 자료집({key})과 다릅니다").into());
                }
                let have = version_text(&raw["version"]);
                if !w.version.is_empty() && !have.is_empty() && w.version != have {
                    return Err(format!("원본 «{}»의 판이 배치와 다릅니다(원본 v{have} · 배치 v{})", w.name, w.version).into());
                }
                raw
            }
            None => Value::Null,
        };
        let sha = given.map(|bytes| format!("{:x}", Sha256::digest(bytes)));
        let id = match held.get(key) {
            Some((id, name, old)) => {
                if sha.is_some() && *old != sha {
                    db.execute("UPDATE packs SET original=?2,sha256=?3 WHERE id=?1", params![id, given, sha])?;
                }
                if *name != w.name {
                    db.execute("UPDATE packs SET name=?2 WHERE id=?1", params![id, w.name])?;
                }
                *id
            }
            None => {
                db.execute("INSERT INTO packs(name,original,sha256) VALUES(?1,?2,?3)", params![w.name, given, sha])?;
                db.last_insert_rowid()
            }
        };
        let at = id.to_string();
        let pick = |field: &str, mine: &str| -> String {
            let from_raw = version_text(&raw[field]);
            if !mine.is_empty() {
                mine.to_owned()
            } else if !from_raw.is_empty() {
                from_raw
            } else {
                version_text(&info[&at][field])
            }
        };
        let (version, category) = (pick("version", &w.version), pick("category", &w.category));
        let original: bool = db.query_row("SELECT original IS NOT NULL FROM packs WHERE id=?1", [id], |r| r.get(0))?;
        info[&at] = json!({"id":key,"version":version,"category":category,"original":original});
        keys[&at] = json!(key);
        out.insert(key.to_owned(), id);
    }
    set_meta(db, "pack_keys", &keys.to_string())?;
    set_meta(db, "pack_info", &info.to_string())?;
    Ok(out)
}

/// "insert" — 넣는 트랙 S(다시 쓰는 트랙 ∪ 새 트랙)의 하위 배치를 덧붙인다(`Builder::append_after` + `fill_into(FillHow::Tracks)`).
/// 마치기(`finish_append`)는 부르는 쪽("summaries"). 새 번호는 지우기 전 가장 큰 번호(`floors`) 다음부터, 다시 쓰는 트랙의 것은 `kept`의 옛 번호로.
/// S 밖을 가리키는 값은 새 지문이 말하는 만큼만 저장소에서 찾는다: `needs_uids`(남의 트랙 띠 · 사건 uid → 번호 — 같은 uid가 여럿이면 가장 큰 번호,
/// 통째 짓기의 '뒤에 넣은 것이 이김'과 같게) · `row_targets`(남의 트랙 열쇠 → 그 트랙의 줄 순번 → 줄 열쇠) · 하위 배치의 `outer.variants`(열쇠 →
/// 번호) · 변형의 `outer.hides`(내용 → 번호 — [`resolve_hides`]). 사건의 트랙 안 차례(`events.ord`)는 Builder가 센다(판정 R23).
fn insert_tracks<'t>(tx: &'t Transaction, plan: &Value, new: &Prints, s: &BTreeSet<String>, packs: &HashMap<String, i64>, kept: &Kept,
    floors: &Floors, before: &RowMap) -> Result<Builder<'t>> {
    let sub = sub_plan(plan, s)?;
    let (mut needs, mut targets) = (BTreeSet::new(), BTreeSet::new());
    for key in s {
        let t = &new.tracks[key];
        needs.extend(t.needs_uids.iter());
        targets.extend(t.row_targets.iter().filter(|k| !s.contains(*k)));
    }
    let (mut outer_periods, mut outer_events) = (HashMap::new(), HashMap::new());
    {
        let mut period = tx.prepare("SELECT MAX(id) FROM periods WHERE uid=?1")?;
        let mut event = tx.prepare("SELECT MAX(id) FROM events WHERE uid=?1 AND uid<>''")?;
        for uid in needs {
            if let Some(id) = period.query_row([uid], |r| r.get::<_, Option<i64>>(0))? {
                outer_periods.insert(uid.clone(), id);
            }
            if let Some(id) = event.query_row([uid], |r| r.get::<_, Option<i64>>(0))? {
                outer_events.insert(uid.clone(), id);
            }
        }
    }
    let stored = stored_tracks(tx)?;
    let mut outer_rows = HashMap::new();
    {
        // 그 트랙의 줄 덩이(지우기 전 자리 표 `before` — S 밖 트랙이라 그대로다)의 열쇠 범위로 읽는다(줄 표를 훑지 않는다 — 과제 A+ 넘김 `rows(track)` 훑기).
        let mut stmt = tx.prepare(BLOCK_ROWS_SQL)?;
        for key in targets {
            let id = *stored.get(key).ok_or_else(|| format!("새 트랙이 줄을 가리키는 트랙 «{key}»이 저장소에 없습니다"))?;
            let Some(b) = before.blocks().iter().find(|b| b.track == id) else { continue };
            for row in stmt.query_map([b.key0, b.key0 + b.n - 1], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?)))? {
                let (ord, row) = row?;
                outer_rows.insert((key.clone(), ord), row);
            }
        }
    }
    // 하위 배치 밖 변형 열쇠(S 안 원소가 단 S 밖 변형 — 판정 R16 가)는 저장소에서 열쇠로.
    let mut outer_variants = HashMap::new();
    {
        let mut stmt = tx.prepare("SELECT id FROM variants WHERE key=?1")?;
        for key in list(&sub["outer"], "variants") {
            let key = key.as_str().unwrap_or("");
            let id = stmt.query_row([key], |r| r.get::<_, i64>(0)).optional()?
                .ok_or_else(|| needs_whole(format!("다른 트랙의 변형 «{key}»이 저장소에 없습니다 — 배치와 저장소가 어긋났습니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)")))?;
            outer_variants.insert(key.to_owned(), id);
        }
    }
    let outer_hides = resolve_hides(tx, &sub, before, kept)?;
    // 사건의 트랙 안 차례(`events.ord` — 판정 R23)는 Builder가 트랙마다 센다 — 하위 배치는 S 트랙의 사건을 실린 차례 그대로 모두 싣는다.
    let mut b = Builder::append_after(tx, floors)?;
    fill_into(&mut b, &sub, Vec::new(), FillHow::Tracks(TrackFill {
        keys: s, packs, tracks: &kept.tracks, reuse_periods: &kept.periods, reuse_events: &kept.events, reuse_variants: &kept.variants,
        outer_variants: &outer_variants, outer_hides: &outer_hides,
        outer_periods: &outer_periods, outer_events: &outer_events, outer_rows: &outer_rows,
    }))?;
    Ok(b)
}

/// 줄 덩이(열쇠 범위) 하나의 (트랙 안 차례, 줄 열쇠) — 번호 범위로 읽는다(줄 표에 트랙 색인이 없다 — `WHERE track=?`는 표를 통째로 훑는다 · 과제 A+ 넘김).
const BLOCK_ROWS_SQL: &str = "SELECT ord,id FROM rows WHERE id BETWEEN ?1 AND ?2";
/// "insert"가 넣은 그 트랙의 새 덩이(지우기 전 가장 큰 열쇠 뒤의 열쇠만 — 넣은 만큼만 훑는다).
const NEW_BLOCK_SQL: &str = "SELECT MIN(id),COUNT(id) FROM rows WHERE id>?1 AND track=?2";

/// 덧붙임 Builder가 가림 없이 쓰는, 내용을 싣는 열(과제 A+ 1) — (표, 열, `schema.rs`와 같은 꼴). `Store::on`은 이것이 없는 옛 저장소도 가려 읽는다.
/// 차례가 곧 `ALTER TABLE … ADD COLUMN`의 차례라, 같은 표의 열은 `schema.rs`의 열 차례대로 둔다(`periods.variant` 뒤에 `periods.form` — 맨 끝 열).
/// 스키마 4의 띠 `form`(계약 1-1)도 여기 든다: 이 열이 없던 옛 저장소(판 '3' · '3.1')의 첫 모두 덮는 고쳐 쓰기는 모든 트랙을 다시 써 판 4로 적는다.
const OLDER_COLUMNS: [(&str, &str, &str); 9] = [
    ("tracks", "sphere", "TEXT NOT NULL DEFAULT ''"),
    ("items", "ref_kind", "INTEGER NOT NULL DEFAULT 0"),
    ("summaries", "cats", "BLOB NOT NULL DEFAULT x''"),
    ("rows", "variant", "INTEGER NOT NULL DEFAULT 0"),
    ("periods", "variant", "INTEGER NOT NULL DEFAULT 0"),
    ("cells", "variant", "INTEGER NOT NULL DEFAULT 0"),
    ("events", "variant", "INTEGER NOT NULL DEFAULT 0"),
    ("items", "variant", "INTEGER NOT NULL DEFAULT 0"),
    ("periods", "form", "INTEGER NOT NULL DEFAULT 0"),
];

/// 변형 표 다섯(과제 A+ 1) — `schema.rs`와 같은 꼴.
const OLDER_TABLES: [(&str, &str); 5] = [
    ("variants", "CREATE TABLE variants(id INTEGER PRIMARY KEY,key TEXT NOT NULL UNIQUE,kind INTEGER NOT NULL,track INTEGER NOT NULL,
        band INTEGER NOT NULL DEFAULT 0,uid TEXT NOT NULL DEFAULT '',name TEXT NOT NULL DEFAULT '',notes TEXT NOT NULL DEFAULT '')"),
    ("variant_rows", "CREATE TABLE variant_rows(variant INTEGER NOT NULL,row INTEGER NOT NULL,after INTEGER NOT NULL,ord INTEGER NOT NULL,
        is_new INTEGER NOT NULL DEFAULT 0,scope_pad INTEGER NOT NULL DEFAULT 0,group_start INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(variant,row)) WITHOUT ROWID"),
    ("variant_moves", "CREATE TABLE variant_moves(variant INTEGER NOT NULL,kind INTEGER NOT NULL,ref INTEGER NOT NULL,row INTEGER NOT NULL,
        PRIMARY KEY(variant,kind,ref)) WITHOUT ROWID"),
    ("variant_hides", "CREATE TABLE variant_hides(variant INTEGER NOT NULL,kind INTEGER NOT NULL,ref INTEGER NOT NULL,
        PRIMARY KEY(variant,kind,ref)) WITHOUT ROWID"),
    ("variant_groups", "CREATE TABLE variant_groups(id INTEGER PRIMARY KEY,variant INTEGER NOT NULL,key TEXT NOT NULL,depth INTEGER NOT NULL,
        name TEXT NOT NULL,color INTEGER NOT NULL,kind INTEGER NOT NULL,rows TEXT NOT NULL)"),
];

/// 저장소에 없는 [`OLDER_COLUMNS`] · [`OLDER_TABLES`] · 스키마 4의 `sphere_lines` 표(`표.열` · 표 이름) — 비면 지금 엔진의 모양이다.
/// "choose"가 읽는다(그 뒤 "delete"가 만든다). `sphere_lines`는 [`OLDER_TABLES`]에 넣지 않는다 — 그 목록의 표를 만들면 [`ensure_schema`]가
/// 변형 표를 막 만든 것으로 보아 변형 수 세기 메타를 지운다.
pub(crate) fn older_missing(db: &Connection) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for (table, column, _) in OLDER_COLUMNS {
        if !db.prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name=?1"))?.exists([column])? {
            out.push(format!("{table}.{column}"));
        }
    }
    for (table, _) in OLDER_TABLES {
        if !has_table(db, table)? {
            out.push(table.to_owned());
        }
    }
    if !has_table(db, "sphere_lines")? {
        out.push("sphere_lines".to_owned());
    }
    Ok(out)
}

/// "delete" 첫머리 — 옛 저장소(이 계획 전에 지은 것 · 판 '3' · '3.1')에 없는 것을 만든다(DDL도 거래 안이라 실패하면 함께 되돌려진다). 열 · 표는
/// `pragma_table_info` · `sqlite_master`로 가린다(계약 1절 규칙). 표 · 열의 모양은 `schema.rs`와 같다.
/// - `periods_row` 색인(얹힌 몫 11) — 줄을 지울 때 외래 열쇠 확인이 띠 표를 훑지 않게.
/// - `events.ord` 열(얹힌 몫 4 · 판정 R23) — 덧붙여 넣는 사건이 트랙 안 차례를 적는다. 열을 더하면 그 전 사건은 0이라 그 트랙 안의 동률은
///   예전처럼 번호로 깨진다(트랙 안 차례라 트랙마다 따로 — 다시 쓴 트랙은 제 차례를 받는다).
/// - 덮는 색인 `events_time`이 `ord`를 품지 않으면(열을 막 더했거나 옛 모양) 다시 짓는다(5d 얹힌 몫 11 — 다시 짓기 전에는 촘촘한 단계의
///   타일이 사건 표를 찾아가 느리다 · 답은 같다). 사건 수에 비례하지만 옛 저장소의 첫 apply 한 번뿐이다(그때는 모든 트랙을 다시 쓴다).
///   색인을 지우면 `sqlite_stat1`의 그 색인 줄도 지워지므로 그 색인만 다시 잰다(`ANALYZE events_time` — `builder::reindex`처럼 · 과제 6 얹힌 몫 5).
/// - `summaries.ords` 열(판정 R24) — 덧붙여 짓는 요약이 대표마다의 트랙 안 차례를 싣는다. 열을 더하기 전의 요약은 빈 값이라 번호로 깬다.
/// - `entities.ord` · `sum` 열(계획 정한 것 #5 · #6) — 지문이 빈 글이라 "entities"가 모든 기록을 한 번 바꿔 적는다(옛 DLC의 약속 2).
/// - `track_prints` 표(과제 4) — 없던 저장소는 "choose"가 모든 트랙을 '지문 없음 → 다시 씀'으로 골랐고, "prints"가 그 지문을 여기에 적는다.
/// - `blobs` 표(문서 그림 — 그 전의 저장소) — "entities"가 그림을 견준다.
/// - 이름 표의 칸 참조 · 찾을 글 열(`names.cell_ref` · `hay`) · 관점 이름 표(`lens_names`) · 사건 찾을 글 표(`event_hay`)(형식 3을 잇기 전의 저장소 —
///   과제 6) — "names"가 이름 표를 통째로 다시 펴고 사건의 덧줄을 적는다(기록이 바뀐 사건 · 다시 쓴 트랙의 사건).
/// - 덧붙임 Builder가 가림 없이 쓰는 열 · 표(과제 A+ 1 — [`OLDER_COLUMNS`] · [`OLDER_TABLES`]): `tracks.sphere` · `items.ref_kind` · `summaries.cats` ·
///   `rows` · `periods` · `cells` · `events` · `items`의 `variant` · 변형 표 다섯(+ `variant_moves_to` 색인). 내용을 싣는 것이라 이것이 없던 저장소는
///   "choose"가 모든 트랙을 다시 쓰게 했다(덮는 트랙만 주는 배치는 거절). 변형 표를 막 만들었으면 수 세기 열쇠(`meta.variants` · `variant_rows` ·
///   `variant_moves`)의 옛 값을 지워 "meta"가 표에서 다시 세게 한다.
/// - 스키마 4(계약 1-1): 띠의 `form` 열([`OLDER_COLUMNS`]의 끝) · 문화권 단위 줄 표 `sphere_lines`(`schema::SPHERE_LINES` — 새로 짓는 저장소와 같은 글).
///   둘 다 [`older_missing`]에 들어, 없던 저장소의 첫 모두 덮는 고쳐 쓰기는 모든 트랙을 다시 쓰고 판을 '4'(열쇠 ≠ 자리면 '4.1')로 적는다("order").
fn ensure_schema(tx: &Transaction) -> Result<()> {
    tx.execute_batch(crate::builder::PERIODS_ROW_INDEX_SQL)?;
    let has = |table: &str, column: &str| -> Result<bool> {
        Ok(tx.prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name=?1"))?.exists([column])?)
    };
    for (table, column, ddl) in OLDER_COLUMNS {
        if !has(table, column)? {
            tx.execute_batch(&format!("ALTER TABLE {table} ADD COLUMN {column} {ddl}"))?;
        }
    }
    let mut made_variants = false;
    for (table, ddl) in OLDER_TABLES {
        if !has_table(tx, table)? {
            tx.execute_batch(ddl)?;
            made_variants = true;
        }
    }
    if made_variants {
        tx.execute_batch("CREATE INDEX IF NOT EXISTS variant_moves_to ON variant_moves(variant,row);
            DELETE FROM meta WHERE key IN ('variants','variant_rows','variant_moves');")?;
    }
    if !has("events", "ord")? {
        tx.execute_batch("ALTER TABLE events ADD COLUMN ord INTEGER NOT NULL DEFAULT 0")?;
    }
    // 덮는 색인은 `variant` · `ord`를 품어야 한다(`builder::EVENTS_TIME_INDEX_SQL`) — 둘 가운데 하나라도 빠졌으면(열을 막 더했거나 옛 모양) 다시 짓는다.
    let indexed = |column: &str| -> Result<bool> { Ok(tx.prepare("SELECT 1 FROM pragma_index_info('events_time') WHERE name=?1")?.exists([column])?) };
    if !indexed("ord")? || !indexed("variant")? {
        crate::builder::rebuild_events_time(tx)?;
        tx.execute_batch("ANALYZE events_time")?;
    }
    for column in ["cell_ref", "hay"] {
        if !has("names", column)? {
            tx.execute_batch(&format!("ALTER TABLE names ADD COLUMN {column} TEXT NOT NULL DEFAULT ''"))?;
        }
    }
    if !has("summaries", "ords")? {
        tx.execute_batch("ALTER TABLE summaries ADD COLUMN ords BLOB NOT NULL DEFAULT x''")?;
    }
    if !has("entities", "ord")? {
        tx.execute_batch("ALTER TABLE entities ADD COLUMN ord INTEGER NOT NULL DEFAULT 0")?;
    }
    if !has("entities", "sum")? {
        tx.execute_batch("ALTER TABLE entities ADD COLUMN sum TEXT NOT NULL DEFAULT ''")?;
    }
    // P4가 더한 표 넷(사건 찾을 글 · 관점 이름 · 그림 바이트 · 트랙 지문) — 새로 짓는 저장소와 같은 글(`schema::P4_TABLES` — 한 곳).
    for (_, ddl) in crate::schema::P4_TABLES {
        tx.execute_batch(&format!("CREATE TABLE IF NOT EXISTS {ddl};"))?;
    }
    // 스키마 4의 문화권 단위 줄 표 — 새로 짓는 저장소와 같은 글(`schema::SPHERE_LINES` — 한 곳). [`OLDER_TABLES`] 밖이라 변형 수 세기는 그대로다.
    tx.execute_batch(&format!("CREATE TABLE IF NOT EXISTS {};", crate::schema::SPHERE_LINES))?;
    Ok(())
}

/// 다시 쓰는 트랙에서 **지우기 전에** 적어 두는 것(과제 5c의 "delete" 첫머리) — "insert"가 옛 번호를 이어 쓰고 "relink"가 옛 줄 덩이를 옮겨 적는다.
#[derive(Debug, Default)]
struct Kept {
    /// 트랙 열쇠 → 옛 `tracks.id`(다시 쓰는 트랙).
    tracks: HashMap<String, i64>,
    /// 띠 · 사건 uid → 옛 번호(다시 쓰는 트랙 · 사라지는 트랙의 것. 같은 uid가 여럿이면 가장 작은 번호 — 통째 짓기에서 먼저 넣은 것).
    periods: HashMap<String, i64>,
    events: HashMap<String, i64>,
    /// 변형 열쇠 → 옛 번호(같은 두 갈래의 트랙).
    variants: HashMap<String, i64>,
    /// 트랙 번호 → 옛 줄 덩이(첫 열쇠, 줄 수) — 다시 쓰는 트랙과 사라지는 트랙 모두(줄이 없는 트랙은 없음).
    blocks: BTreeMap<i64, (i64, i64)>,
}

/// [`Kept`]를 읽는다. 띠 · 사건 · 변형 번호는 다시 쓰는 트랙과 **사라지는 트랙** 모두에서 적는다 — uid가 사라지는 트랙에서 다시 쓰거나 새로 드는
/// 트랙으로 옮겨 가면 그 uid는 생기지도 사라지지도 않아 그것을 가리키던 트랙을 다시 쓰지 않으므로, 옛 번호를 그대로 받아야 가리킴이 맞는다.
/// 옛 줄 덩이는 지우기 전 자리 표(`before` — 열 때 읽은 `RowMap`)에서 읽는다(줄 표에 트랙 색인이 없어 `WHERE track=?`는 표를 통째로 훑는다 — 과제 A+ 넘김 `rows(track)` 훑기).
fn remember(tx: &Transaction, rewrite: &BTreeMap<String, i64>, removed: &BTreeMap<String, i64>, before: &RowMap) -> Result<Kept> {
    let mut kept = Kept { tracks: rewrite.iter().map(|(k, id)| (k.clone(), *id)).collect(), ..Kept::default() };
    let variants = has_table(tx, "variants")?;
    for id in rewrite.values().chain(removed.values()) {
        if let Some(b) = before.blocks().iter().find(|b| b.track == *id).filter(|b| b.n > 0) {
            kept.blocks.insert(*id, (b.key0, b.n));
        }
    }
    for (k0, n) in kept.blocks.values() {
        let k1 = k0 + n - 1;
        for (table, column, map) in [("periods", "row", &mut kept.periods), ("events", "lane", &mut kept.events)] {
            let mut stmt = tx.prepare(&format!("SELECT uid,id FROM {table} WHERE {column} BETWEEN ?1 AND ?2 AND uid<>'' ORDER BY id"))?;
            for row in stmt.query_map([k0, &k1], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))? {
                let (uid, id) = row?;
                map.entry(uid).and_modify(|old| *old = (*old).min(id)).or_insert(id);
            }
        }
    }
    if variants {
        let mut stmt = tx.prepare("SELECT key,id FROM variants WHERE track=?1")?;
        for id in rewrite.values().chain(removed.values()) {
            for row in stmt.query_map([id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))? {
                let (key, id) = row?;
                kept.variants.insert(key, id);
            }
        }
    }
    Ok(kept)
}

/// "delete"가 지운 것 — "meta"가 수 세기 · 자료집별 수 · 닿는 트랙에서 뺀다.
#[derive(Debug, Default)]
struct Gone {
    tracks: i64,
    rows: i64,
    periods: i64,
    cells: i64,
    events: i64,
    unknown: i64,
    groups: i64,
    axis_cells: i64,
    items: i64,
    row_labels: i64,
    variants: i64,
    variant_rows: i64,
    variant_moves: i64,
    /// 자료집 번호 → 지운 사건 · 띠 수.
    pack_events: BTreeMap<i64, i64>,
    pack_periods: BTreeMap<i64, i64>,
    /// 지우고 다시 쓰거나 사라진 트랙 — 자료집이 닿는 트랙에서 먼저 빼고 넣은 것으로 다시 더한다.
    cleared: BTreeSet<i64>,
    /// 뺀 자료집 번호.
    packs: BTreeSet<i64>,
    /// 뺀 자료집과 함께 지운 항목 기록의 uid — "names"가 그 uid에 닿는 사건의 덧줄을 다시 적는다.
    entities: BTreeSet<String>,
}

/// "delete" — 다시 쓸 트랙(`rewrite`)과 사라지는 트랙(`removed`)의 것을 지운다. 줄 덩이로 고르므로 지우는 양은 그 트랙 크기에 비례한다
/// (일반 항목은 공간 색인 `item_bounds`의 줄 범위로 찾는다 — 표에 줄 색인이 없다).
/// - 사건: 본문 색인이 켜진 저장소(`meta.search`)면 넣을 때와 같은 낱자로 `'delete'`(contentless FTS는 넣은 낱자와 똑같아야 지워진다) —
///   제목 · 본문의 `grams`와 덧줄(rowid −번호 · `event_hay.hay`의 `grams`). 그리고 `event_hay` · `bounds` · `span_bounds` · 사건.
/// - 칸(띠로) · 띠 · 일반 항목 · 줄 이름 · 요약(그 줄) · 줄 · 묶음 · 날짜 칸(그 트랙) · 변형(+ 줄 · 이사 · 가림 · 묶음) ·
///   R-tree 다섯(번호로). 사라지는 트랙은 `tracks` 행과 지문(`track_prints`)까지. 이름 표 · 관점 이름은 "names"가 통째로 다시 편다(과제 6).
/// - 남는 변형(지우지 않는 트랙의 것)이 지울 칸 · 항목을 가리면 Err — 그 변형의 트랙도 다시 써야 했다(얹힌 몫 10 · 지문 규칙의 구멍).
fn delete_tracks(tx: &Transaction, kept: &Kept, rewrite: &BTreeMap<String, i64>, removed: &BTreeMap<String, i64>) -> Result<Gone> {
    let mut gone = Gone::default();
    let search: Option<String> = tx.query_row("SELECT value FROM meta WHERE key='search'", [], |r| r.get(0)).optional()?;
    let search = search.as_deref() != Some("off");
    let (hay, variants, prints) = (has_table(tx, "event_hay")?, has_table(tx, "variants")?, has_table(tx, "track_prints")?);
    let tracks: Vec<(&String, i64)> = rewrite.iter().chain(removed.iter()).map(|(k, id)| (k, *id)).collect();
    let all: Vec<i64> = tracks.iter().map(|(_, id)| *id).collect();
    // 지울 변형 — 이것 밖의 변형이 지울 칸 · 항목을 가리면 안 된다.
    let doomed: Vec<i64> = if variants {
        let mut stmt = tx.prepare(&format!("SELECT id FROM variants WHERE track IN ({})", crate::variant::in_list(&all)))?;
        let list = stmt.query_map([], |r| r.get(0))?.collect::<std::result::Result<Vec<i64>, _>>()?;
        list
    } else {
        Vec::new()
    };
    let doomed_list = crate::variant::in_list(&doomed);
    let run = |sql: &str, k0: i64, k1: i64| -> Result<usize> { Ok(tx.prepare_cached(sql)?.execute([k0, k1])?) };
    let count = |sql: &str, k0: i64, k1: i64| -> Result<i64> { Ok(tx.prepare_cached(sql)?.query_row([k0, k1], |r| r.get(0))?) };
    for (key, track) in &tracks {
        if let Some(&(k0, n)) = kept.blocks.get(track) {
            let k1 = k0 + n - 1;
            // 남는 변형의 가림이 이 트랙의 칸 · 항목을 가리키는가(얹힌 몫 10).
            if variants {
                let stale = count(&format!("SELECT count(*) FROM variant_hides WHERE variant NOT IN ({doomed_list}) AND \
                    ((kind=3 AND ref IN (SELECT c.id FROM cells c JOIN periods p ON p.id=c.period WHERE p.row BETWEEN ?1 AND ?2)) \
                     OR (kind=4 AND ref IN (SELECT id FROM item_bounds WHERE row_min>=?1 AND row_max<=?2)))"), k0, k1)?;
                if stale > 0 {
                    return Err(needs_whole(format!("다시 쓰지 않는 변형 {stale}개가 지울 트랙 «{key}»의 칸 · 항목을 가립니다 — 그 트랙도 함께 다시 써야 합니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)")));
                }
            }
            // 사건 — 본문 색인의 낱자부터(넣을 때와 같은 글로).
            let mut ids: Vec<i64> = Vec::new();
            {
                let mut read = tx.prepare_cached("SELECT id,title,body FROM events WHERE lane BETWEEN ?1 AND ?2")?;
                let mut forget = tx.prepare_cached("INSERT INTO search(search,rowid,terms) VALUES('delete',?1,?2)")?;
                let mut rows = read.query([k0, k1])?;
                while let Some(r) = rows.next()? {
                    let (id, title, body): (i64, String, String) = (r.get(0)?, r.get(1)?, r.get(2)?);
                    if search {
                        forget.execute(params![id, grams(&format!("{title} {body}")).join(" ")])?;
                    }
                    ids.push(id);
                }
                if search && hay {
                    let mut read = tx.prepare_cached("SELECT h.id,h.hay FROM event_hay h JOIN events e ON e.id=h.id WHERE e.lane BETWEEN ?1 AND ?2")?;
                    let mut rows = read.query([k0, k1])?;
                    while let Some(r) = rows.next()? {
                        let (id, text): (i64, String) = (r.get(0)?, r.get(1)?);
                        let terms = grams(&text);
                        if !terms.is_empty() {
                            forget.execute(params![-id, terms.join(" ")])?;
                        }
                    }
                }
            }
            if hay {
                run("DELETE FROM event_hay WHERE id IN (SELECT id FROM events WHERE lane BETWEEN ?1 AND ?2)", k0, k1)?;
            }
            {
                let mut bounds = tx.prepare_cached("DELETE FROM bounds WHERE id=?1")?;
                let mut spans = tx.prepare_cached("DELETE FROM span_bounds WHERE id=?1")?;
                for id in &ids {
                    bounds.execute([id])?;
                    spans.execute([id])?;
                }
            }
            {
                let mut stmt = tx.prepare_cached("SELECT pack,count(*),sum(start IS NULL) FROM events WHERE lane BETWEEN ?1 AND ?2 GROUP BY pack")?;
                for row in stmt.query_map([k0, k1], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?)))? {
                    let (pack, n, unknown) = row?;
                    *gone.pack_events.entry(pack).or_default() += n;
                    gone.events += n;
                    gone.unknown += unknown;
                }
            }
            run("DELETE FROM events WHERE lane BETWEEN ?1 AND ?2", k0, k1)?;
            // 칸(띠로) — 공간 색인은 번호로.
            {
                let mut read = tx.prepare_cached("SELECT c.id FROM cells c JOIN periods p ON p.id=c.period WHERE p.row BETWEEN ?1 AND ?2")?;
                let cells = read.query_map([k0, k1], |r| r.get::<_, i64>(0))?.collect::<std::result::Result<Vec<_>, _>>()?;
                let mut bounds = tx.prepare_cached("DELETE FROM cell_bounds WHERE id=?1")?;
                for id in &cells {
                    bounds.execute([id])?;
                }
                gone.cells += cells.len() as i64;
            }
            run("DELETE FROM cells WHERE period IN (SELECT id FROM periods WHERE row BETWEEN ?1 AND ?2)", k0, k1)?;
            // 띠.
            {
                let mut read = tx.prepare_cached("SELECT id,pack FROM periods WHERE row BETWEEN ?1 AND ?2")?;
                let periods = read.query_map([k0, k1], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?)))?.collect::<std::result::Result<Vec<_>, _>>()?;
                let mut bounds = tx.prepare_cached("DELETE FROM period_bounds WHERE id=?1")?;
                for (id, pack) in &periods {
                    bounds.execute([id])?;
                    *gone.pack_periods.entry(*pack).or_default() += 1;
                }
                gone.periods += periods.len() as i64;
            }
            run("DELETE FROM periods WHERE row BETWEEN ?1 AND ?2", k0, k1)?;
            // 일반 항목 — 줄 색인이 없어 공간 색인의 줄 범위로 찾는다(항목은 제 트랙의 줄에만 걸친다).
            {
                let mut read = tx.prepare_cached("SELECT id FROM item_bounds WHERE row_min>=?1 AND row_max<=?2")?;
                let items = read.query_map([k0, k1], |r| r.get::<_, i64>(0))?.collect::<std::result::Result<Vec<_>, _>>()?;
                let mut item = tx.prepare_cached("DELETE FROM items WHERE id=?1")?;
                let mut bounds = tx.prepare_cached("DELETE FROM item_bounds WHERE id=?1")?;
                for id in &items {
                    item.execute([id])?;
                    bounds.execute([id])?;
                }
                gone.items += items.len() as i64;
            }
            gone.row_labels += run("DELETE FROM row_labels WHERE row BETWEEN ?1 AND ?2", k0, k1)? as i64;
            for level in 0..=crate::levels::LEVEL_MAX as i64 {
                tx.prepare_cached("DELETE FROM summaries WHERE level=?1 AND lane BETWEEN ?2 AND ?3")?.execute([level, k0, k1])?;
            }
            gone.rows += run("DELETE FROM rows WHERE id BETWEEN ?1 AND ?2", k0, k1)? as i64;
        }
        gone.groups += tx.prepare_cached("DELETE FROM groups WHERE track=?1")?.execute([track])? as i64;
        gone.axis_cells += tx.prepare_cached("DELETE FROM axis_cells WHERE track=?1")?.execute([track])? as i64;
        if variants {
            let ids = {
                let mut stmt = tx.prepare_cached("SELECT id FROM variants WHERE track=?1")?;
                let list = stmt.query_map([track], |r| r.get::<_, i64>(0))?.collect::<std::result::Result<Vec<_>, _>>()?;
                list
            };
            for id in &ids {
                gone.variant_rows += tx.prepare_cached("DELETE FROM variant_rows WHERE variant=?1")?.execute([id])? as i64;
                gone.variant_moves += tx.prepare_cached("DELETE FROM variant_moves WHERE variant=?1")?.execute([id])? as i64;
                tx.prepare_cached("DELETE FROM variant_hides WHERE variant=?1")?.execute([id])?;
                tx.prepare_cached("DELETE FROM variant_groups WHERE variant=?1")?.execute([id])?;
            }
            gone.variants += tx.prepare_cached("DELETE FROM variants WHERE track=?1")?.execute([track])? as i64;
        }
        if removed.contains_key(*key) {
            tx.prepare_cached("DELETE FROM tracks WHERE id=?1")?.execute([track])?;
            if prints {
                tx.prepare_cached("DELETE FROM track_prints WHERE key=?1")?.execute([key.as_str()])?;
            }
            gone.tracks += 1;
        }
        gone.cleared.insert(*track);
    }
    Ok(gone)
}

/// "delete"의 끝 — 빼는 DLC(`remove` — 글자 id)의 항목 기록과 자료집 행을 지우고 `meta.pack_keys` · `pack_info`에서 뺀다(지운 기록의 uid는
/// `gone.entities`에 — "names"가 그 uid에 닿는 사건의 덧줄을 다시 적고 이름 표 · 관점 이름을 통째로 다시 편다).
/// 그 DLC가 남긴 띠 · 사건 · 날짜 칸은 그것이 놓인 트랙이 다시 쓰이거나 사라지며 지워졌다(지문에 든다). 공통 날짜 칸 · 그림은 온 판이라
/// "globals" · "entities"가 배치와 맞춘다(자료집을 빼면 온 판 지문이 바뀐다). 남은 것이 그 자료집을 가리키면 COMMIT의 외래 열쇠 확인이 되돌린다
/// (이름 표 · 관점 이름에는 외래 열쇠가 없다 — "names"가 다시 펴서 뺀 자료집의 줄이 남지 않는다).
fn drop_packs(tx: &Transaction, remove: &[String], gone: &mut Gone) -> Result<()> {
    if remove.is_empty() {
        return Ok(());
    }
    let mut keys = meta_json(tx, "pack_keys");
    let mut info = meta_json(tx, "pack_info");
    for key in remove {
        let at = keys.as_object().and_then(|m| m.iter().find(|(_, v)| v.as_str() == Some(key.as_str()))).map(|(id, _)| id.clone())
            .ok_or_else(|| format!("빼라는 DLC «{key}»가 지금 저장소에 없습니다"))?;
        let id: i64 = at.parse().map_err(|_| format!("자료집 번호가 올바르지 않습니다: {at}"))?;
        {
            let mut stmt = tx.prepare("SELECT uid FROM entities WHERE pack=?1")?;
            for uid in stmt.query_map([id], |r| r.get::<_, String>(0))? {
                gone.entities.insert(uid?);
            }
        }
        tx.execute("DELETE FROM entities WHERE pack=?1", [id])?;
        tx.execute("DELETE FROM packs WHERE id=?1", [id])?;
        if let Some(m) = keys.as_object_mut() {
            m.remove(&at);
        }
        if let Some(m) = info.as_object_mut() {
            m.remove(&at);
        }
        gone.packs.insert(id);
    }
    set_meta(tx, "pack_keys", &keys.to_string())?;
    set_meta(tx, "pack_info", &info.to_string())?;
    Ok(())
}

/// "relink" — 다시 쓰지 않은 트랙의 변형(트랙이 S 밖인 변형)이 다시 쓴 트랙의 **옛** 줄 덩이를 가리키던 값을 새 덩이로 같은 자리만큼 옮겨 적는다
/// (`열쇠 − 옛 key0 + 새 key0`): `variant_moves.row`(이사 도착) · `variant_rows.row` · `after`(0 이상) · `ord`(`after = −2` — 판 줄) ·
/// `variant_groups.rows`. 새 덩이는 지우기 전 가장 큰 열쇠 뒤에 들어서 옛 덩이와 겹치지 않으므로 덩이마다 차례로 옮겨도 두 번 옮기지 않는다.
/// - 새 덩이의 줄 수를 넘는 자리를 가리키면 Err — 그 트랙은 줄 수에 기대므로 다시 썼어야 한다(지문 규칙의 구멍을 알림).
/// - 사라진 트랙의 옛 덩이를 가리키는 값이 남아도 Err(같은 까닭).
fn relink(tx: &Transaction, kept: &Kept, rewrite: &BTreeMap<String, i64>, removed: &BTreeMap<String, i64>, floor_rows: i64) -> Result<()> {
    if kept.blocks.is_empty() || !has_table(tx, "variants")? {
        return Ok(());
    }
    // 다시 쓰지 않은 트랙의 변형 — 다시 쓴 트랙 · 새 트랙의 변형은 새 번호로 넣었다(넣은 트랙은 모두 `rewrite` ∪ 새 트랙이고, 새 트랙은 옛 덩이를 가리킬 수 없다
    // — 옛 덩이의 줄은 이미 지웠다). 그래서 '옛 덩이를 가리키는 값'은 남은 변형의 것뿐이고, 고르지 않고 값의 범위로 찾는다.
    // 묶음 목록은 한 번 읽는다(목록으로 읽히지 않는 묶음은 Err — 고침 1회차 · Minor 6). 옮기기는 `rowmap::rekey_track`과 한 몸(`shift_variant_rows`).
    let mut groups = crate::rowmap::VariantGroups::read(tx)?;
    // 새 덩이: "insert"가 지우기 전 가장 큰 줄 열쇠(`floors.rows`) 뒤에 넣었다 — 그 뒤의 열쇠만 본다(줄 표에 트랙 색인이 없어 `WHERE track=?`만이면 표를 통째로 훑는다 —
    // 과제 A+ 넘김 `rows(track)` 훑기).
    let new_block = |track: i64| -> Result<(i64, i64)> {
        let (k0, n): (Option<i64>, i64) = tx.query_row(NEW_BLOCK_SQL, [floor_rows, track], |r| Ok((r.get(0)?, r.get(1)?)))?;
        Ok((k0.unwrap_or(0), n))
    };
    let named: HashMap<i64, &String> = rewrite.iter().chain(removed.iter()).map(|(k, id)| (*id, k)).collect();
    for (track, &(a, n_old)) in &kept.blocks {
        let b = a + n_old - 1;
        let key = named.get(track).map(|k| k.as_str()).unwrap_or("");
        let (k0, n_new) = if removed.values().any(|id| id == track) { (0, 0) } else { new_block(*track)? };
        // 넘는 자리: [a + n_new, b].
        if n_new < n_old {
            let (lo, hi) = (a + n_new, b);
            let over: i64 = tx.query_row(
                "SELECT (SELECT count(*) FROM variant_moves WHERE row BETWEEN ?1 AND ?2)+(SELECT count(*) FROM variant_rows WHERE row BETWEEN ?1 AND ?2)\
                 +(SELECT count(*) FROM variant_rows WHERE after BETWEEN ?1 AND ?2)+(SELECT count(*) FROM variant_rows WHERE after=-2 AND ord BETWEEN ?1 AND ?2)",
                [lo, hi], |r| r.get(0))?;
            let over_groups = groups.any_in(lo, hi);
            if over > 0 || over_groups {
                return Err(needs_whole(if n_new == 0 {
                    format!("사라진 트랙 «{key}»의 줄을 다른 트랙의 변형이 아직 가리킵니다 — 그 트랙도 함께 다시 써야 합니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)")
                } else {
                    format!("다른 트랙의 변형이 다시 쓴 트랙 «{key}»의 {}번째 줄 너머를 가리키는데 새 덩이는 {n_new}줄뿐입니다 — 그 트랙도 함께 다시 써야 합니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)", n_new + 1)
                }));
            }
        }
        if n_new == 0 {
            continue;
        }
        crate::rowmap::shift_variant_rows(tx, &mut groups, a, b, k0 - a)?;
    }
    groups.write(tx)
}

/// "relink"의 둘째 몫(판정 R45): 다시 쓰지 않은 트랙의 날짜 칸 이음 번호(`axis_cells.strip`)를 새 배치의 번호로 옮긴다. 이음 번호는 온 판에 한 번 센다
/// (`export/axis.mjs` — 연호 줄 전부 → 도읍 · 배도 줄 전부, 트랙 차례)인데 지문은 그것을 트랙 안 거리로만 본다(모듈 머리글) — 앞 트랙이 바뀌어 번호가 밀린
/// 트랙도 다시 쓰지 않으므로, 갈래(연호 · 도읍과 배도)마다 '배치의 첫 값 − 저장소의 첫 값'만큼 옮기면 통째 짓기의 번호와 같다(트랙 안 거리가 같다).
/// 배치가 말하는 트랙(`speaks`)만 본다 — `All` · `Part`는 조합의 트랙 전부(`Part`의 S 밖 트랙은 하위 배치의 `stripFirst`), `Tracks`는 그 배치의 트랙.
/// 다시 쓰거나 새로 든 트랙(`written`)은 배치의 번호로 들어갔으므로 건너뛴다. 한쪽에만 이음이 있으면(지문이 같으면 그럴 수 없다 — 배치나 저장소가 어긋남) Err.
fn renumber_strips(tx: &Transaction, plan: &Value, speaks: &[String], written: &BTreeSet<String>) -> Result<()> {
    let want = strip_firsts(plan)?;
    let ids = stored_tracks(tx)?;
    // 저장소의 트랙 번호 → 갈래마다 가장 작은 이음 번호(0이 아닌 것 · 없으면 0).
    let mut held: HashMap<i64, [i64; 2]> = HashMap::new();
    let mut q = tx.prepare("SELECT track,MIN(CASE WHEN kind=2 THEN strip END),MIN(CASE WHEN kind<>2 THEN strip END) FROM axis_cells \
        WHERE track IS NOT NULL AND strip<>0 GROUP BY track")?;
    let rows = q.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, Option<i64>>(1)?, r.get::<_, Option<i64>>(2)?)))?;
    for row in rows {
        let (track, era, cap) = row?;
        held.insert(track, [era.unwrap_or(0), cap.unwrap_or(0)]);
    }
    let mut shift = tx.prepare("UPDATE axis_cells SET strip=strip+?1 WHERE track=?2 AND strip<>0 AND (kind=2)=?3")?;
    for key in speaks.iter().filter(|k| !written.contains(*k)) {
        let Some(id) = ids.get(key) else { continue };
        let (have, new) = (held.get(id).copied().unwrap_or([0, 0]), want.get(key).copied().unwrap_or([0, 0]));
        for class in 0..2 {
            match (have[class], new[class]) {
                (h, w) if h == w => {}
                (h, w) if h != 0 && w != 0 => {
                    shift.execute(params![w - h, id, class == 0])?;
                }
                (h, w) => return Err(format!("트랙 «{key}»의 날짜 칸 이음({})이 저장소({h})와 배치({w})에서 어긋납니다 — 지문은 같은데 이음의 있고 없음이 다릅니다",
                    if class == 0 { "연호" } else { "도읍 · 배도" }).into()),
            }
        }
    }
    Ok(())
}

/// "relink"의 셋째 몫(판정 R45 · R54 M6): 다시 쓰지 않은 트랙의 변형 notes(줄 쌓기 자체 점검의 글 — `variants.notes`)의 '트랙 <순번>'을 새 배치의 순번으로.
/// notes는 조합 전부의 트랙 순번을 글로 품는데 지문은 그것을 열쇠로 적어 보므로(모듈 머리글) 앞에 트랙이 끼거나 빠져 순번만 밀린 트랙은 다시 쓰지 않는다 —
/// 옛 차례(`old` — 고쳐 쓰기 전 저장소의 트랙 차례 · 그 트랙을 지은 배치의 순번)의 열쇠를 새 차례(`order`)의 자리로 옮기면 통째 짓기의 글과 같다.
/// 조합 전부를 말하는 배치(`All` · `Part`)에서만 부른다(덮는 트랙만 주는 배치의 notes는 그 배치의 순번이다). 새 차례에 없는 열쇠면 그대로 둔다.
fn renumber_notes(tx: &Transaction, old: &[String], order: &[String], written: &BTreeSet<String>) -> Result<()> {
    if old == order {
        return Ok(());
    }
    let ids = stored_tracks(tx)?;
    let at: HashMap<&str, usize> = order.iter().enumerate().map(|(i, k)| (k.as_str(), i)).collect();
    let mut read = tx.prepare("SELECT id,notes FROM variants WHERE track=?1 AND instr(notes,'트랙 ')>0")?;
    let mut put = tx.prepare("UPDATE variants SET notes=?1 WHERE id=?2")?;
    for id in order.iter().filter(|k| !written.contains(*k)).filter_map(|k| ids.get(k)) {
        let rows: Vec<(i64, String)> = read.query_map([id], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?;
        for (variant, notes) in rows {
            let fixed = notes_tracks(&notes, |i| old.get(i).and_then(|k| at.get(k.as_str())).map(|n| n.to_string()));
            if fixed != notes {
                put.execute(params![fixed, variant])?;
            }
        }
    }
    Ok(())
}

/// [`resolve_hides`]의 항목 후보(과제 A+ 3) — 공간 색인(`item_bounds`)에서 줄 · 끝 줄의 열쇠와 시작 · 끝 날이 같은 것만 골라(공간 색인을 바깥 고리로 —
/// `holds`와 같은 까닭으로 `CROSS JOIN`) 번호로 항목을 읽는다. 일반 항목 표에는 줄 색인이 없어 예전처럼 내용으로만 찾으면 가림마다 표를 통째로 훑었다.
const HIDDEN_ITEMS_SQL: &str = "SELECT i.id,i.ref,i.ref_kind,i.a,i.b,i.c,i.d,b.lod_min FROM item_bounds b CROSS JOIN items i ON i.id=b.id \
    WHERE b.row_min=?1 AND b.row_max=?2 AND b.lo_day=?3 AND b.hi_day=?4 AND i.section=?5 AND i.start=?6 AND i.end=?7 AND i.name=?8 AND i.color=?9 \
    AND i.text2=?10 AND i.variant=?11 ORDER BY i.id";

/// 하위 배치의 변형마다 `outer.hides`(S 밖 칸 · 항목을 **내용**으로 적은 가림 — [`hidden_content`]의 꼴 · 판정 R19)를 저장소에서 찾아
/// (갈래, 번호)로 — 실린 차례대로. 같은 내용이 여럿이면 **한 변형 안에서** 가림마다 서로 다른 번호를 번호 차례로 하나씩 짝짓는다(두 변형이 같은
/// 칸을 가리는 것은 흔하다 — 판 둘이 같은 원래 칸을 바꿈). 못 찾으면 Err(지문 규칙의 구멍을 알림).
/// - 칸: 띠 uid · 종류 · 단 · 시작 · 끝 · 이름 · 변형(빈 글이면 0)이 같은 칸.
/// - 항목: 구역 · 시작 · 끝 · 이름 · 색 · 곁글 · 변형이 같고, 줄 · 끝 줄이 (트랙 열쇠, 트랙 안 순번)으로 같고, `ref`가 가리키는 띠 · 사건의 uid가 같고
///   (못 푼 것은 0), `a` ~ `d`는 띠 번호 칸(`bandref`)이면 그 띠의 uid로 · 아니면 수로 같고, `lod`가 −1이 아니면 `item_bounds`의 단계와 같은 것.
///   후보는 그 트랙의 줄 열쇠(`rows` — 지우기 전 줄 덩이 `before` 안에서 트랙 안 순번으로 · 가려지는 트랙은 S 밖이라 덩이가 그대로다)와 날로 공간 색인에서
///   좁힌다([`HIDDEN_ITEMS_SQL`] — 과제 A+ 3). 그 트랙 · 줄이 저장소에 없으면 후보가 없다(못 찾음 Err).
/// 가려지는 항목의 `ref` · 띠 번호 칸이 **이번에 다시 쓰는 트랙**의 띠 · 사건을 가리키면 그 번호는 "delete"가 지운 뒤라 표에 없다 — 같은 uid는 같은 번호로 다시 들므로
/// 지우기 전에 적어 둔 번호(`kept` — uid → 옛 번호)를 거꾸로 읽어 uid를 찾는다(갈래 1 · P4 과제 9가 등불 연대기 무작위 판에서 찾음 — 판 트랙과 띠의 주인 트랙을
/// 함께 다시 쓰고 가려지는 관계선의 트랙은 그대로인 장면).
fn resolve_hides(tx: &Transaction, sub: &Value, before: &RowMap, kept: &Kept) -> Result<HashMap<String, Vec<(i64, i64)>>> {
    let mut out = HashMap::new();
    let wanted: Vec<&Value> = with_boards(sub, "variants").into_iter().filter(|v| !list(&v["outer"], "hides").is_empty()).collect();
    if wanted.is_empty() {
        return Ok(out);
    }
    let track_ids = stored_tracks(tx)?;
    // (트랙 열쇠, 트랙 안 순번) → 줄 열쇠. 덩이의 열쇠 범위 안에서 순번으로 찾는다(번호 색인 — 줄 표를 훑지 않는다).
    let row_key = |track: &str, ord: i64| -> Result<Option<i64>> {
        let Some(block) = track_ids.get(track).and_then(|id| before.blocks().iter().find(|b| b.track == *id)) else { return Ok(None) };
        Ok(tx.prepare_cached("SELECT id FROM rows WHERE id BETWEEN ?1 AND ?2 AND ord=?3")?
            .query_row(params![block.key0, block.key0 + block.n - 1, ord], |r| r.get(0)).optional()?)
    };
    let variant_no = |key: &str| -> Result<Option<i64>> {
        if key.is_empty() {
            return Ok(Some(0));
        }
        Ok(tx.prepare_cached("SELECT id FROM variants WHERE key=?1")?.query_row([key], |r| r.get(0)).optional()?)
    };
    let (gone_periods, gone_events): (HashMap<i64, &String>, HashMap<i64, &String>) =
        (kept.periods.iter().map(|(u, id)| (*id, u)).collect(), kept.events.iter().map(|(u, id)| (*id, u)).collect());
    let period_uid = |id: i64| -> Result<Option<String>> {
        let found: Option<String> = tx.prepare_cached("SELECT uid FROM periods WHERE id=?1")?.query_row([id], |r| r.get(0)).optional()?;
        Ok(found.or_else(|| gone_periods.get(&id).map(|u| (*u).clone())))
    };
    let event_uid = |id: i64| -> Result<Option<String>> {
        let found: Option<String> = tx.prepare_cached("SELECT uid FROM events WHERE id=?1")?.query_row([id], |r| r.get(0)).optional()?;
        Ok(found.or_else(|| gone_events.get(&id).map(|u| (*u).clone())))
    };
    for v in wanted {
        let mut taken: HashSet<(i64, i64)> = HashSet::new();
        let mut found = Vec::new();
        for h in list(&v["outer"], "hides") {
            let kind = int(h, "kind");
            let Some(variant) = variant_no(text(h, "variant"))? else {
                return Err(format!("변형 «{}»이 가리는 것의 변형 «{}»이 저장소에 없습니다", text(v, "key"), text(h, "variant")).into());
            };
            let mut candidates: Vec<i64> = Vec::new();
            match kind {
                3 => {
                    let mut stmt = tx.prepare_cached("SELECT c.id FROM cells c JOIN periods p ON p.id=c.period WHERE p.uid=?1 AND c.kind=?2 AND c.lane=?3 \
                        AND c.start=?4 AND c.end=?5 AND c.name=?6 AND c.variant=?7 ORDER BY c.id")?;
                    candidates = stmt.query_map(params![text(h, "period"), int(h, "cellKind"), int(h, "lane"), int(h, "start"), int(h, "end"), text(h, "name"), variant],
                        |r| r.get(0))?.collect::<std::result::Result<Vec<i64>, _>>()?;
                }
                4 => {
                    type Row = (i64, i64, i64, i64, i64, i64, i64, i64);
                    let track = text(h, "track");
                    let (start, end) = (int(h, "start"), int(h, "end"));
                    let rows: Vec<Row> = match (row_key(track, int(h, "row"))?, row_key(track, int(h, "row2"))?) {
                        (Some(from), Some(to)) => {
                            let mut stmt = tx.prepare_cached(HIDDEN_ITEMS_SQL)?;
                            let list = stmt.query_map(params![from, to, start.div_euclid(crate::DAY), end.div_euclid(crate::DAY), int(h, "section"), start, end,
                                text(h, "name"), int(h, "color"), text(h, "text2"), variant],
                                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?)))?
                                .collect::<std::result::Result<Vec<_>, _>>()?;
                            list
                        }
                        _ => Vec::new(),
                    };
                    'item: for (id, reference, ref_kind, a, b, c, d, level) in rows {
                        let target = match ref_kind {
                            1 => period_uid(reference)?,
                            2 => event_uid(reference)?,
                            _ => None,
                        };
                        // 못 푼 ref(0)는 배치의 글이 무엇이었든 0으로 들었다 — 견주지 않는다.
                        if reference != 0 && target.as_deref() != Some(text(h, "ref")) {
                            continue;
                        }
                        let values = [a, b, c, d];
                        let bands = band_fields(int(h, "section"), a, b, c, d);
                        for (at, field) in FIELDS.iter().enumerate() {
                            let want = &h[*field];
                            let same = match want.as_str() {
                                Some(uid) if bands.contains(&at) => values[at] != 0 && period_uid(values[at])?.as_deref() == Some(uid),
                                _ => want.as_i64() == Some(values[at]),
                            };
                            if !same {
                                continue 'item;
                            }
                        }
                        let lod = int_or(h, "lod", -1);
                        if lod >= 0 && level != lod {
                            continue;
                        }
                        candidates.push(id);
                    }
                }
                _ => return Err(format!("모르는 변형 가리기의 갈래: {kind}").into()),
            }
            let id = candidates.into_iter().find(|id| !taken.contains(&(kind, *id)))
                .ok_or_else(|| {
                    let what = match kind { 3 => format!("칸 «{}»", text(h, "name")), 4 => format!("항목 «{}»", text(h, "name")), _ => "것".to_owned() };
                    needs_whole(format!("변형 «{}»이 가리는 {what}을 저장소에서 찾지 못했습니다 — 그 트랙도 함께 다시 써야 합니다(그 트랙까지 덮는 배치로 다시 넣어 주세요 — 메이커에서 그 DLC까지 불러와 내보내기 · 저장소는 그대로)", text(v, "key")))
                })?;
            taken.insert((kind, id));
            found.push((kind, id));
        }
        out.insert(text(v, "key").to_owned(), found);
    }
    Ok(out)
}

/// "order" — `tracks.ord`를 새 차례로 다시 적고(바뀐 것만) 줄 열쇠 ↔ 자리 표를 다시 읽어 판(`meta.schema`)을 맞춘다: 열쇠 = 자리면 '4'(`schema::VERSION`),
/// 아니면 '4.1'(`schema::VERSION_SPLIT`). 이 걸음 전에 "delete"가 스키마 4의 열 · 표를 만들었으므로 옛 판 '3' · '3.1'도 여기서 판 4로 적힌다.
/// - `Covers::All`: 새 배치의 트랙 차례 그대로(저장소의 트랙은 모두 배치에 있다 — 사라지는 트랙은 앞 걸음에서 지운다).
/// - `Covers::Tracks`: 저장소의 차례를 두고, 새로 든 트랙만 새 배치에서 바로 앞의 같은 갈래(보통 · 판) 트랙 뒤에(앞이 없으면 바로 뒤의 같은 갈래 트랙 앞에 ·
///   둘 다 없으면 보통 트랙 전부 뒤) 끼운다([`place_added`] — 과제 A+ 4).
fn put_order(db: &Connection, new: &Prints, covers: &Covers, added: &BTreeSet<String>) -> Result<RowMap> {
    let stored = stored_tracks(db)?;
    let order: Vec<String> = match covers {
        Covers::All => new.order.clone(),
        // 하위 배치: 조합 전부의 차례(`allTracks`) — S 밖 트랙은 저장소에 그대로 있다(`choose`가 확인).
        Covers::Part { order, .. } => order.clone(),
        Covers::Tracks(_) => {
            let by_id: HashMap<i64, &String> = stored.iter().map(|(k, id)| (*id, k)).collect();
            let mut list: Vec<String> = Vec::with_capacity(stored.len());
            {
                let mut stmt = db.prepare("SELECT id FROM tracks ORDER BY ord,id")?;
                for id in stmt.query_map([], |r| r.get::<_, i64>(0))? {
                    let key = *by_id.get(&id?).ok_or("열쇠를 셈하지 못한 트랙이 있습니다")?;
                    if !added.contains(key) {
                        list.push(key.clone());
                    }
                }
            }
            place_added(list, &new.order, added)
        }
    };
    if order.len() != stored.len() {
        return Err(format!("트랙 차례를 다시 적지 못했습니다(저장소 {}개 · 새 차례 {}개)", stored.len(), order.len()).into());
    }
    {
        let mut stmt = db.prepare("UPDATE tracks SET ord=?2 WHERE id=?1 AND ord<>?2")?;
        for (ord, key) in order.iter().enumerate() {
            let id = stored.get(key).ok_or_else(|| format!("저장소에 없는 트랙의 차례입니다: {key}"))?;
            stmt.execute(params![id, ord as i64])?;
        }
    }
    let map = RowMap::load(db)?;
    set_meta(db, "schema", if map.is_identity() { crate::schema::VERSION } else { crate::schema::VERSION_SPLIT })?;
    Ok(map)
}

/// [`put_order`]의 `Covers::Tracks` — 저장소의 차례(`list` — 새로 든 트랙 없이)에 새로 든 트랙(`added`)을 새 배치의 차례(`order`)를 보고 끼운다.
/// 이웃은 **같은 갈래끼리만** 찾는다(과제 A+ 4 — 통째 짓기는 보통 트랙 → 판 트랙 차례다): 새 배치에서 바로 앞의 같은 갈래 트랙 뒤, 없으면 바로 뒤의
/// 같은 갈래 트랙 앞, 그것도 없으면 보통 트랙 전부 뒤(첫 판 트랙 앞 · 판이 없으면 끝). 메이커가 DLC 일부만 불러 판을 만든 배치(`[그 DLC 트랙…, 판]`)에서
/// 판의 앞 이웃은 보통 트랙이라 그 뒤에 끼우면 판이 저장소의 다른 DLC 트랙들 앞에 섰다.
/// 판끼리의 차례는 새 배치에 이웃이 없으면 알 수 없다(통째 짓기는 DLC 차례의 판 → 시대 구분 판) — 그때는 판 무리의 맨 앞에 든다.
fn place_added(mut list: Vec<String>, order: &[String], added: &BTreeSet<String>) -> Vec<String> {
    let board = |k: &str| k.starts_with(BOARD);
    for (i, key) in order.iter().enumerate().filter(|(_, k)| added.contains(*k)) {
        let kin = |k: &&String| board(k) == board(key);
        let before = order[..i].iter().rev().filter(kin).find_map(|k| list.iter().position(|x| x == k)).map(|p| p + 1);
        let at = before.or_else(|| order[i + 1..].iter().filter(kin).find_map(|k| list.iter().position(|x| x == k)))
            .unwrap_or_else(|| list.iter().position(|x| board(x)).unwrap_or(list.len()));
        list.insert(at, key.clone());
    }
    list
}

/// 자료집별 수 · 닿는 트랙을 처음부터 세는 SQL(통째 짓기와 같은 셈 — 띠 · 사건이 놓인 줄의 트랙). 저장소에 그 열쇠가 없을 때만 쓴다.
const PACK_SQL: [(&str, &str); 3] = [
    ("pack_events", "SELECT pack,count(*) FROM events GROUP BY pack"),
    ("pack_periods", "SELECT pack,count(*) FROM periods GROUP BY pack"),
    ("pack_tracks", "SELECT p.pack,r.track FROM periods p JOIN rows r ON r.id=p.row UNION SELECT e.pack,r.track FROM events e JOIN rows r ON r.id=e.lane"),
];

/// "meta" — 수 세기(`count` · `rows` · `periods` · …)는 지운 수(`g`)를 빼고 넣은 수(`a` · 온 판 `done`)를 더한다(1,000만에서 `count(*)`를 피함).
/// 저장소에 그 열쇠가 없으면 그 표를 처음부터 세어 넣는다(얹힌 몫 4 — 통째 짓기에는 늘 있는 열쇠). 자료집 수는 자료집 표(행이 적다)를 세고,
/// 항목 기록 수는 "entities"가 낸 값(`entities` — 통째 짓기의 규칙: 넣은 기록 수)으로 적는다.
/// 자료집별 사건 · 띠 수도 지운 만큼 빼고 넣은 만큼 더하고(0이 되면 열쇠를 지움 — 통째 짓기는 하나도 없는 자료집의 열쇠를 만들지 않는다),
/// 닿는 트랙은 지우고 다시 쓴 트랙 · 사라진 트랙을 빼고 넣은 것으로 다시 더하고(빈 목록은 지움), 뺀 자료집의 열쇠를 지운다 — 그 열쇠가 없던
/// 저장소는 처음부터 센다. `meta.now`는 통째 짓기와 같은 규칙으로 바꿔 적는다 — 배치의 `now` 글, 없으면 지금 시각(`legacy::iso_now`).
/// Node 배치는 `now`를 싣지 않고 배치 전부를 오늘로 다시 셈하므로 apply 뒤 '오늘'은 지금이다(계획 정한 것 #9 · `now`가 없던 옛 저장소도 같다).
/// 보는 범위는 "range", 온 판 메타는 "globals"가 적는다.
fn put_meta(db: &Connection, plan: &Value, a: &Appended, g: &Gone, done: &GlobalsDone, entities: i64, order_known: bool) -> Result<()> {
    let held = |key: &str| -> Result<bool> { Ok(db.prepare_cached("SELECT 1 FROM meta WHERE key=?1")?.exists([key])?) };
    let count = |sql: &str| -> Result<i64> { Ok(db.query_row(sql, [], |r| r.get::<_, i64>(0))?) };
    {
        let mut add = db.prepare("UPDATE meta SET value=CAST(CAST(value AS INTEGER)+?2 AS TEXT) WHERE key=?1")?;
        // (수 세기 열쇠, 이번에 바뀐 수, 그 열쇠가 없을 때 처음부터 세는 SQL — 통째 짓기 `Builder::finalize`와 같은 셈 · 얹힌 몫 4) — 한 줄에 함께 적어
        // 열쇠와 셈이 어긋날 수 없게 한다(과제 6 얹힌 몫 5 — 예전의 두 표 짝 확인은 release에서 빠지는 debug_assert였다).
        let counts = [
            ("count", a.events - g.events, "SELECT count(*) FROM events"),
            ("unknown", a.unknown - g.unknown, "SELECT count(*) FROM events WHERE start IS NULL"),
            ("tracks", a.tracks - g.tracks, "SELECT count(*) FROM tracks"),
            ("rows", a.rows - g.rows, "SELECT count(*) FROM rows"),
            ("periods", a.periods - g.periods, "SELECT count(*) FROM periods"),
            ("cells", a.cells - g.cells, "SELECT count(*) FROM cells"),
            ("groups", a.groups - g.groups, "SELECT count(*) FROM groups"),
            ("categories", 0, "SELECT count(*) FROM categories"),
            ("axis_cells", a.axis_cells - g.axis_cells + done.axis, "SELECT count(*) FROM axis_cells"),
            ("items", a.items - g.items, "SELECT count(*) FROM items"),
            ("row_labels", a.row_labels - g.row_labels, "SELECT count(*) FROM row_labels"),
            ("variants", a.variants - g.variants, "SELECT count(*) FROM variants"),
            ("variant_rows", a.variant_rows - g.variant_rows, "SELECT count(*) FROM variant_rows"),
            ("variant_moves", a.variant_moves - g.variant_moves, "SELECT count(*) FROM variant_moves"),
        ];
        for (key, n, sql) in counts {
            if !held(key)? {
                set_meta(db, key, &count(sql)?.to_string())?;
            } else if n != 0 {
                add.execute(params![key, n])?;
            }
        }
    }
    if let Some(n) = done.categories {
        set_meta(db, "categories", &n.to_string())?;
    }
    set_meta(db, "packs", &count("SELECT count(*) FROM packs")?.to_string())?;
    set_meta(db, "entities", &entities.to_string())?;
    let recount = |key: &str| -> Result<String> {
        let sql = PACK_SQL.iter().find(|(k, _)| *k == key).map(|(_, sql)| *sql).ok_or("모르는 자료집별 수")?;
        let mut stmt = db.prepare(sql)?;
        let pairs = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?)))?.collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(if key == "pack_tracks" {
            let mut table: BTreeMap<String, BTreeSet<i64>> = BTreeMap::new();
            for (pack, track) in pairs {
                table.entry(pack.to_string()).or_default().insert(track);
            }
            json!(table).to_string()
        } else {
            json!(pairs.into_iter().map(|(pack, n)| (pack.to_string(), n)).collect::<BTreeMap<_, _>>()).to_string()
        })
    };
    for (key, more, less) in [("pack_events", &a.pack_events, &g.pack_events), ("pack_periods", &a.pack_periods, &g.pack_periods)] {
        if !held(key)? {
            set_meta(db, key, &recount(key)?)?;
            continue;
        }
        if more.is_empty() && less.is_empty() && g.packs.is_empty() {
            continue;
        }
        let mut v = meta_json(db, key);
        for pack in more.keys().chain(less.keys()).collect::<BTreeSet<_>>() {
            let at = pack.to_string();
            let n = v[&at].as_i64().unwrap_or(0) + more.get(pack).copied().unwrap_or(0) - less.get(pack).copied().unwrap_or(0);
            match v.as_object_mut() {
                Some(m) if n == 0 => {
                    m.remove(&at);
                }
                _ => v[&at] = json!(n),
            }
        }
        if let Some(m) = v.as_object_mut() {
            for pack in &g.packs {
                m.remove(&pack.to_string());
            }
        }
        set_meta(db, key, &v.to_string())?;
    }
    if !held("pack_tracks")? {
        set_meta(db, "pack_tracks", &recount("pack_tracks")?)?;
    } else if !a.pack_tracks.is_empty() || !g.cleared.is_empty() || !g.packs.is_empty() {
        let mut v = meta_json(db, "pack_tracks");
        let mut table: BTreeMap<String, BTreeSet<i64>> = v.as_object().into_iter().flatten()
            .map(|(pack, list)| (pack.clone(), list.as_array().into_iter().flatten().filter_map(Value::as_i64).filter(|t| !g.cleared.contains(t)).collect()))
            .collect();
        for (pack, tracks) in &a.pack_tracks {
            table.entry(pack.to_string()).or_default().extend(tracks);
        }
        for pack in &g.packs {
            table.remove(&pack.to_string());
        }
        v = json!(table.into_iter().filter(|(_, list)| !list.is_empty()).collect::<BTreeMap<_, _>>());
        set_meta(db, "pack_tracks", &v.to_string())?;
    }
    let now = plan["now"].as_str().filter(|s| !s.is_empty()).map_or_else(crate::legacy::iso_now, str::to_owned);
    set_meta(db, "now", &now)?;
    // DLC 차례(P4 과제 9): 조합 전부를 말한 배치(또는 저장소를 다 덮은 배치 — `order_known`)면 그 `packs[]` 차례(통째 짓기 `fill_into`와 같은 값).
    // 일부만 덮은 배치(메이커 `.htlayout`) 뒤에는 저장소가 어느 차례의 통째 짓기와도 같다고 말할 수 없으므로 지운다 — 다음 `add_pack`은 모든 트랙을 한 번 다시 셈한다.
    if order_known {
        let order: Vec<String> = wanted_packs(plan, None).into_iter().map(|w| w.key.unwrap_or_default()).collect();
        set_meta(db, "pack_order", &serde_json::to_string(&order)?)?;
    } else {
        db.execute("DELETE FROM meta WHERE key='pack_order'", [])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 판정 R29 (나): 다시 쓴 덩이가 걸친 묶음 전부 — 묶음 경계에 맞든(자리 16) 안 맞든(19) 첫 줄 · 끝 줄이 놓인 앞뒤 끝 묶음이 든다.
    #[test]
    fn touched_chunks_take_the_edge_chunks_of_each_block() {
        // (자리, 줄 수) → 묶음(8줄씩).
        let cases: [((i64, i64), &[i64]); 12] = [
            ((16, 1), &[2]), ((19, 1), &[2]),
            ((16, 7), &[2]), ((19, 7), &[2, 3]),
            ((16, 8), &[2]), ((19, 8), &[2, 3]),
            ((16, 9), &[2, 3]), ((19, 9), &[2, 3]),
            ((16, 16), &[2, 3]), ((19, 16), &[2, 3, 4]),
            ((16, 17), &[2, 3, 4]), ((19, 17), &[2, 3, 4]),
        ];
        for ((pos0, n), want) in cases {
            assert_eq!(touched_chunks(&[(pos0, n)]), want.to_vec(), "자리 {pos0} · 줄 {n}");
        }
        // 덩이 둘이 한 묶음을 나누면 한 번만 · 번호 차례.
        assert_eq!(touched_chunks(&[(30, 3), (19, 9)]), vec![2, 3, 4]);
        // 줄이 없는 덩이는 건너뛰고, 그것뿐이면 빈 목록(부르는 쪽이 저장소 전체로 돌린다).
        assert_eq!(touched_chunks(&[(40, 0)]), Vec::<i64>::new());
        assert_eq!(touched_chunks(&[]), Vec::<i64>::new());
    }

    /// 과제 A+ 검토 (다): 옛 저장소에 만들어 넣는 열 · 표([`OLDER_COLUMNS`] · [`OLDER_TABLES`])의 꼴이 새로 짓는 저장소(`schema.rs`)와 같다 —
    /// 한쪽만 고치면 메운 저장소와 통째로 지은 저장소의 열 모양(형 · NOT NULL · 기본값 · 열쇠 · WITHOUT ROWID)이 갈린다.
    #[test]
    fn older_ddl_matches_the_schema() {
        type Column = (String, String, i64, Option<String>, i64);
        let info = |db: &Connection, table: &str| -> Vec<Column> {
            db.prepare(&format!("SELECT name,type,\"notnull\",dflt_value,pk FROM pragma_table_info('{table}') ORDER BY cid")).unwrap()
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).unwrap().map(|c| c.unwrap()).collect()
        };
        let rowid = |db: &Connection, table: &str| -> i64 {
            db.query_row("SELECT wr FROM pragma_table_list WHERE name=?1", [table], |r| r.get(0)).unwrap()
        };
        let fresh = Connection::open_in_memory().unwrap();
        crate::schema::create(&fresh).unwrap();
        let made = Connection::open_in_memory().unwrap();
        for (table, ddl) in OLDER_TABLES {
            made.execute_batch(ddl).unwrap();
            assert_eq!(info(&made, table), info(&fresh, table), "{table}");
            assert_eq!(rowid(&made, table), rowid(&fresh, table), "{table}: WITHOUT ROWID");
        }
        for (table, column, ddl) in OLDER_COLUMNS {
            // 그 열만 더해 본 표(앞의 열은 상관없다) — `ensure_schema`가 하는 `ALTER TABLE … ADD COLUMN`과 같은 꼴.
            let probe = Connection::open_in_memory().unwrap();
            probe.execute_batch(&format!("CREATE TABLE {table}(x INTEGER); ALTER TABLE {table} ADD COLUMN {column} {ddl}")).unwrap();
            let pick = |list: Vec<Column>| list.into_iter().find(|c| c.0 == column);
            let want = pick(info(&fresh, table)).unwrap_or_else(|| panic!("{table}.{column}이 schema.rs에 없습니다"));
            assert_eq!(pick(info(&probe, table)), Some(want), "{table}.{column}");
        }
        // 스키마 4(계약 1-1): `ALTER TABLE … ADD COLUMN`은 열을 맨 끝에 붙이므로 `form`이 periods의 마지막 열이어야 메운 저장소와 열 차례까지 같다.
        assert_eq!(info(&fresh, "periods").last().map(|c| c.0.as_str()), Some("form"), "periods의 마지막 열");
        // `ensure_schema`가 옛 저장소에 만드는 `sphere_lines`의 정의 글이 새로 짓는 저장소의 것과 같다(`CREATE TABLE IF NOT EXISTS` — SQLite가 IF NOT EXISTS를
        // 떼고 적는다) · 꼴(형 · NOT NULL · 기본값 · 열쇠)도 같다. 표를 지운 저장소를 메워 본다 — 변형 수 세기 메타는 그대로다(OLDER_TABLES 밖).
        let master = |db: &Connection| -> String {
            db.query_row("SELECT sql FROM sqlite_master WHERE type='table' AND name='sphere_lines'", [], |r| r.get(0)).unwrap()
        };
        let mut filled = Connection::open_in_memory().unwrap();
        crate::schema::create(&filled).unwrap();
        filled.execute_batch("DROP TABLE sphere_lines; INSERT INTO meta VALUES('variants','0');").unwrap();
        assert_eq!(older_missing(&filled).unwrap(), vec!["sphere_lines".to_owned()]);
        let tx = filled.transaction().unwrap();
        ensure_schema(&tx).unwrap();
        tx.commit().unwrap();
        assert_eq!(master(&filled), master(&fresh), "sphere_lines의 정의 글");
        assert_eq!(info(&filled, "sphere_lines"), info(&fresh, "sphere_lines"), "sphere_lines의 꼴");
        assert!(older_missing(&filled).unwrap().is_empty());
        let kept: Option<String> = filled.query_row("SELECT value FROM meta WHERE key='variants'", [], |r| r.get(0)).optional().unwrap();
        assert_eq!(kept.as_deref(), Some("0"), "sphere_lines만 만들면 변형 수 세기 메타를 지우지 않는다");
    }

    /// 과제 A+ 넘김(`rows(track)` 훑기): "insert"의 S 밖 줄 · "relink"의 새 덩이는 줄 표를 통째로 훑지 않는다 — 번호(열쇠) 범위로 찾는다.
    #[test]
    fn row_lookups_do_not_scan_the_row_table() {
        let db = Connection::open_in_memory().unwrap();
        crate::schema::create(&db).unwrap();
        for sql in [BLOCK_ROWS_SQL, NEW_BLOCK_SQL] {
            let mut stmt = db.prepare(&format!("EXPLAIN QUERY PLAN {sql}")).unwrap();
            let nulls = std::iter::repeat_n(rusqlite::types::Null, stmt.parameter_count());
            let plan: Vec<String> = stmt.query_map(rusqlite::params_from_iter(nulls), |r| r.get::<_, String>(3)).unwrap().map(|d| d.unwrap()).collect();
            assert!(plan.iter().any(|d| d.contains("INTEGER PRIMARY KEY")), "{sql}: 번호 범위로 찾아야 함: {plan:?}");
            assert!(!plan.iter().any(|d| d.starts_with("SCAN rows")), "{sql}: 줄 표를 통째로 훑음: {plan:?}");
        }
    }

    /// 과제 perf: "names"가 기록이 바뀐 uid에 닿는 사건을 찾을 때 사건의 이름 색인을 통째로 훑지 않는다 — 두 갈래 모두 색인 찾기다
    /// (바뀐 기록 하나마다 훑으면 바뀐 기록 수 × 사건 수 — DLC 넣기 20만 건에서 이 걸음이 6,600초였다). 지은 저장소처럼 통계(`sqlite_stat1`)를
    /// 둔 채 잰다 — 예전의 OR 하나짜리 SQL은 통계가 있을 때 훑었다.
    #[test]
    fn event_hay_lookups_do_not_scan_the_event_table() {
        let db = Connection::open_in_memory().unwrap();
        crate::schema::create(&db).unwrap();
        db.execute_batch(crate::builder::QUERY_INDEX_SQL).unwrap();
        db.execute_batch("ANALYZE; INSERT INTO sqlite_stat1(tbl,idx,stat) VALUES('events','events_uid','10000 1'); ANALYZE sqlite_schema;").unwrap();
        let plan_of = |sql: &str| -> Vec<String> {
            let mut stmt = db.prepare(&format!("EXPLAIN QUERY PLAN {sql}")).unwrap();
            stmt.query_map(params!["u", "u#", "u$"], |r| r.get::<_, String>(3)).unwrap().map(|d| d.unwrap()).collect()
        };
        let plan = plan_of(EVENTS_OF_UID_SQL);
        assert_eq!(plan.iter().filter(|d| d.starts_with("SEARCH events USING COVERING INDEX events_uid")).count(), 2, "두 갈래 모두 색인 찾기여야 함: {plan:?}");
        assert!(!plan.iter().any(|d| d.starts_with("SCAN events")), "사건의 이름 색인을 통째로 훑음: {plan:?}");
        // 이 검사가 그 함정을 잡는지(통계를 둔 이 판에서 예전 SQL은 훑는다) — SQLite가 나중에 OR를 풀게 되면 이 단언만 빼도 된다.
        let old = plan_of("SELECT id,uid FROM events WHERE uid<>'' AND (uid=?1 OR (uid>=?2 AND uid<?3))");
        assert!(old.iter().any(|d| d.starts_with("SCAN events")), "예전 SQL이 이 판에서 훑지 않음 — 검사가 함정을 못 잡는다: {old:?}");
    }

    /// 과제 A+ 3: 가림의 항목 후보는 일반 항목 표를 통째로 훑지 않는다 — 공간 색인(`item_bounds`)의 줄 · 날 범위로 좁힌 뒤 번호로 찾는다
    /// (가림 하나마다 항목 표 전체를 훑으면 판 트랙을 다시 쓸 때 저장소 크기에 비례한다).
    #[test]
    fn hidden_item_candidates_do_not_scan_the_item_table() {
        let db = Connection::open_in_memory().unwrap();
        crate::schema::create(&db).unwrap();
        let mut stmt = db.prepare(&format!("EXPLAIN QUERY PLAN {HIDDEN_ITEMS_SQL}")).unwrap();
        let nulls = std::iter::repeat_n(rusqlite::types::Null, stmt.parameter_count());
        let plan: Vec<String> = stmt.query_map(rusqlite::params_from_iter(nulls), |r| r.get::<_, String>(3)).unwrap().map(|d| d.unwrap()).collect();
        assert!(plan.iter().any(|d| d.contains("VIRTUAL TABLE INDEX")), "공간 색인을 타야 함: {plan:?}");
        assert!(!plan.iter().any(|d| d.starts_with("SCAN items") || d.starts_with("SCAN i ") || d == "SCAN i"), "일반 항목 표를 통째로 훑음: {plan:?}");
    }

    /// 과제 A+ 4: 덮는 트랙만 주는 배치의 새 트랙 자리 — 판 트랙(`board:`)은 판끼리, 보통 트랙은 보통 트랙끼리 이웃을 찾는다. 같은 갈래의 이웃이 새 배치에
    /// 없으면 보통 트랙 전부 뒤(첫 판 트랙 앞)에 든다(통째 짓기는 보통 트랙 → 판 트랙 차례다).
    #[test]
    fn place_added_keeps_board_tracks_after_every_regular_track() {
        let keys = |list: &[&str]| -> Vec<String> { list.iter().map(|k| k.to_string()).collect() };
        let set = |list: &[&str]| -> BTreeSet<String> { list.iter().map(|k| k.to_string()).collect() };
        // (저장소의 차례, 새 배치의 차례, 새로 든 것, 기대)
        let cases: [(&[&str], &[&str], &[&str], &[&str]); 6] = [
            // 메이커가 DLC 일부만 불러 판을 만든 배치 — 판의 앞 이웃(tb)은 보통 트랙이라 쓰지 않는다.
            (&["ta", "tb", "tc"], &["ta", "tb", "board:b1"], &["board:b1"], &["ta", "tb", "tc", "board:b1"]),
            (&["ta", "tb", "tc", "board:a1"], &["ta", "tb", "board:b1"], &["board:b1"], &["ta", "tb", "tc", "board:b1", "board:a1"]),
            // 판 이웃이 새 배치에 있으면 그 뒤 · 앞.
            (&["ta", "tc", "board:a1", "board:c1"], &["ta", "board:a1", "board:b1"], &["board:b1"], &["ta", "tc", "board:a1", "board:b1", "board:c1"]),
            (&["ta", "tc", "board:a1", "board:c1"], &["ta", "board:b1", "board:c1"], &["board:b1"], &["ta", "tc", "board:a1", "board:b1", "board:c1"]),
            // 보통 트랙: 앞 이웃 뒤 · 없으면 뒤 이웃 앞 · 둘 다 없으면 보통 트랙 끝(판 앞).
            (&["ta", "tc", "board:a1"], &["tb", "tc"], &["tb"], &["ta", "tb", "tc", "board:a1"]),
            (&["ta", "tc", "board:a1"], &["tb", "board:a1"], &["tb"], &["ta", "tc", "tb", "board:a1"]),
        ];
        for (stored, order, added, want) in cases {
            assert_eq!(place_added(keys(stored), &keys(order), &set(added)), keys(want), "저장소 {stored:?} · 배치 {order:?}");
        }
    }

    /// 판정 R45: 변형 notes의 '트랙 <순번>'(뒤가 빈칸이나 '의')만 열쇠로 — 범위 밖 · 다른 꼴(뒤가 숫자 아님 · 다른 낱말)은 그대로.
    #[test]
    fn notes_name_tracks_by_key() {
        let keys: Vec<String> = ["ta", "tb", "board:__board:view:x"].iter().map(|k| k.to_string()).collect();
        assert_eq!(notes_by_key("트랙 1 줄 3 ≠ 트랙 2의 줄 0", &keys), "트랙 «tb» 줄 3 ≠ 트랙 «board:__board:view:x»의 줄 0");
        assert_eq!(notes_by_key("트랙 9 줄 3 · 트랙 0줄 · 트랙 x · 트랙 끝", &keys), "트랙 9 줄 3 · 트랙 0줄 · 트랙 x · 트랙 끝");
        assert_eq!(notes_by_key("트랙 0", &keys), "트랙 0");
        assert_eq!(notes_by_key("", &keys), "");
    }

    /// 판정 R45: 이음 번호의 첫 값 — 갈래(연호 kind 2 · 그 밖)마다 가장 작은 0 아닌 번호, 공통 줄(track −1)은 빼고, 하위 배치가 실은 `stripFirst`와 합친다.
    #[test]
    fn strip_firsts_take_the_smallest_strip_per_class() {
        let plan = json!({"tracks":[{"key":"ta"},{"key":"tb"},{"key":"tc"}],
            "axis":[{"kind":2,"track":0,"strip":9},{"kind":2,"track":0,"strip":7},{"kind":3,"track":0,"strip":30},{"kind":4,"track":0,"strip":31},
                {"kind":1,"track":1,"strip":0},{"kind":2,"track":-1,"strip":4},{"kind":4,"track":2,"strip":40}],
            "stripFirst":{"tz":[2,50]}});
        let got = strip_firsts(&plan).unwrap();
        let want: BTreeMap<String, [i64; 2]> = [("ta", [7, 30]), ("tc", [0, 40]), ("tz", [2, 50])].into_iter().map(|(k, v)| (k.to_string(), v)).collect();
        assert_eq!(got, want);
    }

    /// `needs_list`: `save_prints`의 꼴이면 그 갈래만 읽고, 꼴이 다르거나(빈칸 · 다른 차례 · 열쇠 없음) 값이 null이면 통째로 풀어 같은 답을 낸다.
    #[test]
    fn needs_list_reads_one_part_and_falls_back_to_the_whole_text() {
        let saved = json!({"hides":["tb"],"own":["a/1","a/2"],"rows":["tc"],"uids":["b/9"]}).to_string();
        assert!(saved.starts_with("{\"hides\":") && saved.contains(",\"uids\":["), "save_prints의 꼴: {saved}");
        assert_eq!(needs_list(&saved, "uids").unwrap(), vec!["b/9"]);
        assert_eq!(needs_list(&saved, "hides").unwrap(), vec!["tb"]);
        assert_eq!(needs_list(&saved, "rows").unwrap(), vec!["tc"]);
        // 제 uid 글자 속의 `,"uids":`는 따옴표가 `\"`로 적혀 뒤에서 찾는 꼴에 걸리지 않는다.
        let tricky = json!({"hides":[],"own":["x\",\"uids\":[\"가짜\"]"],"rows":[],"uids":["진짜"]}).to_string();
        assert_eq!(needs_list(&tricky, "uids").unwrap(), vec!["진짜"]);
        // 꼴이 다름(빈칸 · 다른 차례 · 갈래 없음) → 통째로.
        let spaced = "{ \"uids\" : [\"u\"], \"own\": [\"o\"] }";
        assert_eq!(needs_list(spaced, "uids").unwrap(), vec!["u"]);
        assert_eq!(needs_list(spaced, "hides").unwrap(), Vec::<String>::new());
        // null → 빈 목록(앞 · 뒤 어느 쪽 갈래든).
        let nulls = "{\"hides\":null,\"own\":[],\"uids\":null}";
        assert_eq!(needs_list(nulls, "hides").unwrap(), Vec::<String>::new());
        assert_eq!(needs_list(nulls, "uids").unwrap(), Vec::<String>::new());
        // JSON이 아니면 Err.
        assert!(needs_list("uids", "uids").is_err());
    }
}

//! 지은 저장소의 표본 타일을 사건 표의 전수 조사와 견준다(누락 · 중복).
//! `archive-tool verify-tiles`와 Node 없는 가져오기(`archive_import` — 지은 뒤 표본 120, `add-dlc.mjs`의 `verify-tiles 120`과 같다)가 함께 쓴다.
use crate::levels::{tile_of, tile_range, CHUNK_ROWS, LEVEL_MAX};
use crate::tile::{build_tile, decode, TileRequest, COUNTED};
use crate::{Result, Store};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::{path::Path, time::Instant};

/// 표본 검사의 결과. `first`는 처음 어긋난 곳의 글(없으면 맞음).
#[derive(Debug, Clone, Default)]
pub struct TileCheck {
    /// 견준 타일 수(같은 타일은 한 번만).
    pub tiles: usize,
    /// 타일이 실은 사건 수(대표 + 알약 개수)의 합.
    pub events: i64,
    /// 전수 조사보다 모자란 수.
    pub missing: i64,
    /// 같은 대표가 두 번 실렸거나 전수 조사보다 많은 수.
    pub dup: i64,
    pub seconds: f64,
    pub first: Option<String>,
}

impl TileCheck {
    pub fn ok(&self) -> bool {
        self.missing == 0 && self.dup == 0
    }
    /// `archive-tool verify-tiles`가 찍던 꼴 그대로.
    pub fn summary(&self) -> Value {
        json!({"타일":self.tiles,"견준_사건":self.events,"누락_중복":self.missing+self.dup,"초":self.seconds})
    }
}

pub fn meta_int(store: &Store, key: &str) -> Result<i64> {
    Ok(store.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0))?.parse()?)
}

pub fn all_packs(store: &Store) -> Result<Vec<i64>> {
    let mut stmt = store.db.prepare("SELECT id FROM packs ORDER BY id")?;
    let ids = stmt.query_map([], |r| r.get(0))?.collect::<std::result::Result<Vec<i64>, _>>()?;
    Ok(ids)
}

/// 저장소 파일을 열어 표본 타일을 견준다.
pub fn verify_tiles(path: &Path, samples: i64) -> Result<TileCheck> {
    verify_store(&Store::open(path)?, samples)
}

/// 쓰기 거래 안에서(COMMIT 전) 그 연결 그대로 표본 타일을 견준다 — `patch::apply`의 "verify"(계획 P4 과제 5d · `import_with`와 같은 문턱).
/// `chunks`를 주면 표본을 그 줄 묶음에서만 뜬다([`verify_chunks`] — 과제 7c · 판정 R29: 다시 쓰기만인 apply는 다시 쓴 덩이와 걸친 끝 묶음만 보아
/// 저장소 크기와 무관하게).
pub fn verify_in(db: &rusqlite::Connection, samples: i64, chunks: Option<&[i64]>) -> Result<TileCheck> {
    Store::within(db, |store| verify_chunks(store, samples, chunks))
}

/// 표본 타일의 '대표 + 알약 개수'를 사건 표의 전수 조사와 견준다. 넷에 하나는 홀수 번호 자료집만 켜서 잰다.
/// 어긋나도 멈추지 않고 끝까지 세어 누락 · 중복의 수를 낸다(처음 어긋난 곳은 `first`).
pub fn verify_store(store: &Store, samples: i64) -> Result<TileCheck> {
    verify_chunks(store, samples, None)
}

/// [`verify_store`]의 몸 — `chunks`(줄 묶음 번호 목록)를 주면 표본의 묶음을 그 목록(저장소에 있는 묶음만)에서 고르고, 주지 않거나 고를 묶음이
/// 하나도 남지 않으면 저장소의 모든 묶음에서 고른다(빈 목록을 받아 대조 없이 통과하는 길이 없게). 단계 · 시각 · 자료집을 고르는 규칙은 같다.
pub fn verify_chunks(store: &Store, samples: i64, chunks: Option<&[i64]>) -> Result<TileCheck> {
    let (min, max) = (meta_int(store, "min")?, meta_int(store, "max")?);
    // 줄 묶음은 자리로 나뉜다 — 수는 열 때 센 전체 줄 수로(넣기 · 빼기가 `meta.rows`를 늦게 고칠 수 있다 · 계획 P4).
    let total = (store.rows.total() + CHUNK_ROWS - 1) / CHUNK_ROWS;
    let picked: Vec<i64> = chunks.unwrap_or_default().iter().copied().filter(|c| (0..total).contains(c)).collect();
    let list: Vec<i64> = if picked.is_empty() { (0..total.max(0)).collect() } else { picked };
    let started = Instant::now();
    let mut check = TileCheck::default();
    if list.is_empty() {
        // 줄이 하나도 없는 저장소는 견줄 타일이 없다.
        return Ok(check);
    }
    let packs = all_packs(store)?;
    let odd: Vec<i64> = packs.iter().copied().filter(|p| p % 2 == 1).collect();
    let mut done = BTreeSet::new();
    // 변형에서만 나오는 사건은 켠 변형이 없는 타일에 실리지 않는다 — 전수 조사도 같은 조건으로 센다.
    let variant_only = if store.has_variants { " AND variant=0" } else { "" };
    // 전수 조사는 줄마다 덮는 색인(lane, start)의 시간 범위만 센다 — `lane BETWEEN`이면 그 줄들의 사건을 시간과 상관없이 모두 훑어 줄의 사건 수에
    // 비례했다(과제 7c). 줄 묶음 안의 열쇠 범위는 한 묶음(8줄)을 넘지 않는다 — 넘으면 예전 꼴로.
    let mut oracle = store.db.prepare(&format!("SELECT count(*) FROM events WHERE lane IN (?1,?1+1,?1+2,?1+3,?1+4,?1+5,?1+6,?1+7) AND lane<=?2 \
        AND start BETWEEN ?3 AND ?4 AND pack IN (SELECT value FROM json_each(?5)){variant_only}"))?;
    let mut oracle_wide = store.db.prepare(&format!("SELECT count(*) FROM events WHERE lane BETWEEN ?1 AND ?2 AND start BETWEEN ?3 AND ?4 AND pack IN (SELECT value FROM json_each(?5)){variant_only}"))?;
    fn note(check: &mut TileCheck, text: String) {
        if check.first.is_none() {
            check.first = Some(text);
        }
    }
    for i in 0..samples {
        let level = (i % (LEVEL_MAX as i64 + 1)) as usize;
        let minute = min + ((i * 7919) % 1000) * ((max - min) / 1000);
        let chosen = if i % 4 == 3 { &odd } else { &packs };
        let chunk = list[((i * 7) % list.len() as i64) as usize];
        let req = TileRequest { level, x: tile_of(minute, level), chunk, packs: chosen.clone(), filter: None, variants: store.variants_of(&json!({}))? };
        if !done.insert((level, req.x, req.chunk, i % 4 == 3)) {
            continue;
        }
        let tile = decode(&build_tile(store, &req)?)?;
        let mut ids = BTreeSet::new();
        for e in tile.events.iter().filter(|e| e.bits & COUNTED != 0) {
            if !ids.insert(e.id) {
                check.dup += 1;
                note(&mut check, format!("단계 {level} 타일 {} 묶음 {}: 대표 {}번이 두 번", req.x, req.chunk, e.id));
            }
        }
        let total = ids.len() as i64 + tile.pills.iter().map(|p| p.count as i64).sum::<i64>();
        let (t0, t1) = tile_range(level, req.x);
        // 타일의 줄 묶음은 자리의 범위다 — 전수 조사도 그 자리에 놓인 줄 열쇠 범위마다 세어 더한다(열쇠 = 자리면 범위 하나 그대로).
        let mut wanted = 0i64;
        for (k0, k1) in store.rows.ranges_for(req.chunk * CHUNK_ROWS, req.chunk * CHUNK_ROWS + CHUNK_ROWS - 1) {
            let stmt = if k1 - k0 < CHUNK_ROWS { &mut oracle } else { &mut oracle_wide };
            wanted += stmt.query_row(rusqlite::params![k0, k1, t0, t1, serde_json::to_string(chosen)?], |r| r.get::<_, i64>(0))?;
        }
        if total != wanted {
            if total < wanted {
                check.missing += wanted - total;
            } else {
                check.dup += total - wanted;
            }
            note(&mut check, format!("단계 {level} 타일 {} 묶음 {}: 타일 {total}개 ≠ 전수 조사 {wanted}개", req.x, req.chunk));
        }
        check.events += total;
    }
    check.tiles = done.len();
    check.seconds = started.elapsed().as_secs_f64();
    Ok(check)
}

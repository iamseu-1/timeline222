//! 줄의 열쇠(rows.id — 띠 · 사건 · 항목 · 줄 이름 · 묶음 · 변형 · 요약 · 이름 표 · R-tree가 가리키는 번호)와
//! 자리(밖으로 보이는 '전체 줄 번호' — 0부터 빈틈없이, 트랙 차례대로)를 잇는다(계획 P4 · 설계 3-4).
//! 새로 지은 저장소는 둘이 같다(열쇠 = 자리). 트랙을 고쳐 쓰면(patch) 그 트랙의 줄은 끝 번호 뒤에 새 덩이로 들어가
//! 다른 트랙의 행은 그대로이고, 열쇠와 자리가 갈린다. 약속: 트랙 하나의 줄 열쇠는 늘 이어진 덩이이고 덩이 안의 차례가 자리 차례다.
//!
//! 안 · 밖의 경계: 저장소 안(표 · R-tree)은 열쇠로만 말하고, 조회 · 타일이 밖으로 내보내거나 밖에서 받는 줄은 자리다.
//! 바꾸는 곳은 경계 하나씩이다 — 받을 때는 [`RowMap::key_ranges`] · [`RowMap::key`], 내보낼 때는 [`RowMap::pos`] · [`RowMap::outward`].
use crate::levels::LEVEL_MAX;
use crate::Result;
use rusqlite::{params, Connection, Transaction};
use serde_json::Value;

/// 트랙 하나의 줄 덩이: 열쇠 `[key0, key0 + n)` ↔ 자리 `[pos0, pos0 + n)`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Block {
    pub track: i64,
    pub key0: i64,
    pub pos0: i64,
    pub n: i64,
}

/// 덩이(자리 차례) · 열쇠 차례 색인 · 전체 줄 수 · 열쇠 = 자리 여부. 저장소를 열 때 한 번 읽어 메모리에 둔다.
#[derive(Clone, Debug, Default)]
pub struct RowMap {
    blocks: Vec<Block>,
    by_key: Vec<usize>,
    total: i64,
    identity: bool,
}

impl RowMap {
    /// 트랙 차례는 `tracks.ord`(같으면 id)다. 줄 열쇠가 이어진 덩이가 아닌 트랙이 있으면 실패한다.
    pub fn load(db: &Connection) -> Result<Self> {
        let sql = "SELECT t.id,MIN(r.id),MAX(r.id),COUNT(r.id) FROM tracks t JOIN rows r ON r.track=t.id GROUP BY t.id ORDER BY t.ord,t.id";
        let (mut blocks, mut pos) = (Vec::new(), 0);
        let mut stmt = db.prepare(sql)?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            let (track, k0, k1, n): (i64, i64, i64, i64) = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?);
            if k1 - k0 + 1 != n {
                return Err(format!("트랙 {track}의 줄 열쇠가 이어지지 않습니다({k0}~{k1} · {n}줄)").into());
            }
            blocks.push(Block { track, key0: k0, pos0: pos, n });
            pos += n;
        }
        let identity = blocks.iter().all(|b| b.key0 == b.pos0);
        let mut by_key: Vec<usize> = (0..blocks.len()).collect();
        by_key.sort_by_key(|&i| blocks[i].key0);
        Ok(Self { blocks, by_key, total: pos, identity })
    }

    /// 모든 트랙에서 열쇠 = 자리인가(새로 지은 저장소).
    pub fn is_identity(&self) -> bool {
        self.identity
    }

    /// 전체 줄 수(= 자리의 끝 + 1).
    pub fn total(&self) -> i64 {
        self.total
    }

    /// 자리 차례의 덩이들(트랙마다 하나 — 줄이 없는 트랙은 없다).
    pub fn blocks(&self) -> &[Block] {
        &self.blocks
    }

    /// 열쇠 → 자리. 모르는 열쇠(음수 포함)는 -1.
    pub fn pos(&self, key: i64) -> i64 {
        if self.identity {
            return if (0..self.total).contains(&key) { key } else { -1 };
        }
        let i = self.by_key.partition_point(|&i| self.blocks[i].key0 <= key);
        match i.checked_sub(1).map(|j| self.blocks[self.by_key[j]]) {
            Some(b) if key < b.key0 + b.n => b.pos0 + (key - b.key0),
            _ => -1,
        }
    }

    /// 열쇠 → 그 줄이 든 트랙의 차례(그 트랙 덩이의 첫 자리 — 트랙 차례대로 커진다). 모르는 열쇠는 -1.
    /// 타일 대표의 동률을 (사건 제 줄의 트랙 차례, 트랙 안 차례)로 깰 때 쓴다(계획 P4 판정 R23 — 사건 표를 더 읽지 않는다).
    pub fn track_pos(&self, key: i64) -> i64 {
        let i = self.by_key.partition_point(|&i| self.blocks[i].key0 <= key);
        match i.checked_sub(1).map(|j| self.blocks[self.by_key[j]]) {
            Some(b) if key < b.key0 + b.n => b.pos0,
            _ => -1,
        }
    }

    /// 자리 → 열쇠. 범위 밖(음수 포함)은 -1.
    pub fn key(&self, pos: i64) -> i64 {
        if self.identity {
            return if (0..self.total).contains(&pos) { pos } else { -1 };
        }
        let i = self.blocks.partition_point(|b| b.pos0 <= pos);
        match i.checked_sub(1).map(|j| self.blocks[j]) {
            Some(b) if pos < b.pos0 + b.n => b.key0 + (pos - b.pos0),
            _ => -1,
        }
    }

    /// 자리 범위 `[pos0, pos1]`(양 끝 포함)가 걸친 열쇠 범위들 — 자리 차례 · 트랙마다 하나(열쇠는 트랙 사이에서 이어지지 않는다).
    pub fn key_ranges(&self, pos0: i64, pos1: i64) -> Vec<(i64, i64)> {
        if pos1 < pos0 {
            return Vec::new();
        }
        self.blocks.iter().filter(|b| b.pos0 <= pos1 && b.pos0 + b.n - 1 >= pos0)
            .map(|b| (b.key0 + pos0.max(b.pos0) - b.pos0, b.key0 + pos1.min(b.pos0 + b.n - 1) - b.pos0)).collect()
    }

    /// 자리 범위 `[pos0, pos1]`를 물을 때 SQL에 넣을 열쇠 범위들. 열쇠 = 자리면 받은 범위 하나 그대로라(지름길)
    /// 예전과 같은 물음 · 같은 답이고, 아니면 [`RowMap::key_ranges`](트랙마다 하나 · 자리 차례)다.
    pub fn ranges_for(&self, pos0: i64, pos1: i64) -> Vec<(i64, i64)> {
        if self.identity {
            return if pos1 < pos0 { Vec::new() } else { vec![(pos0, pos1)] };
        }
        self.key_ranges(pos0, pos1)
    }

    /// 답(layout · 조회)의 JSON을 훑어, 이름이 `row_keys`에 든 정수(또는 정수 배열) 값을 열쇠에서 자리로 바꾼다.
    /// 열쇠 = 자리면 아무것도 하지 않는다. 음수와 모르는 열쇠는 그대로 둔다(`-1` = 줄 없음 같은 값을 지키려고).
    /// 안의 열쇠를 밖으로 내보내는 곳이 이 함수 하나다 — 리메이크가 `layout()` 답의 줄 열을 바꾸면 여기에 이름만 더한다.
    pub fn outward(&self, v: &mut Value, row_keys: &[&str]) {
        if self.identity {
            return;
        }
        self.outward_value(v, row_keys);
    }

    fn outward_value(&self, v: &mut Value, row_keys: &[&str]) {
        match v {
            Value::Object(map) => {
                for (name, child) in map.iter_mut() {
                    if row_keys.contains(&name.as_str()) {
                        self.outward_row(child, row_keys);
                    } else {
                        self.outward_value(child, row_keys);
                    }
                }
            }
            Value::Array(list) => list.iter_mut().for_each(|child| self.outward_value(child, row_keys)),
            _ => {}
        }
    }

    /// 줄 열쇠 이름의 값: 정수는 바로, 배열은 원소마다, 그 밖(객체 · 글)은 그 안을 다시 훑는다.
    fn outward_row(&self, v: &mut Value, row_keys: &[&str]) {
        match v {
            Value::Number(n) => {
                if let Some(key) = n.as_i64() {
                    let pos = self.pos(key);
                    if pos >= 0 {
                        *v = Value::from(pos);
                    }
                }
            }
            Value::Array(list) => list.iter_mut().for_each(|child| self.outward_row(child, row_keys)),
            Value::Object(_) => self.outward_value(v, row_keys),
            _ => {}
        }
    }
}

/// 그 트랙의 줄 덩이를 `key0`부터로 옮긴다 — 줄 하나하나의 열쇠가 `d = key0 − (옛 첫 열쇠)`만큼 바뀐다(차례는 그대로).
/// 부르는 쪽 거래 안에서 쓴다. 외래 열쇠(`periods.row` · `events.lane` · `row_labels.row` → `rows`)는 `ON DELETE · ON UPDATE`가 없으므로
/// 부르는 쪽이 먼저 `PRAGMA defer_foreign_keys=ON`을 켜 둔다(COMMIT에서 맞는지 확인된다).
/// 판(`meta.schema`)은 건드리지 않는다 — 열쇠 ≠ 자리를 만든 쪽이 `'4.1'`(`schema::VERSION_SPLIT`)로 적는다.
///
/// 옮기는 값: `rows.id` · `periods.row` · `events.lane` · `items.row`/`row2` · `row_labels.row` · `groups.first_row` ·
/// `variant_rows.row`/`after`(0 이상)/`ord`(`after = −2`일 때 — 판 줄을 가리킨다) · `variant_moves.row` · `variant_groups.rows`(JSON) ·
/// `summaries.lane` · `names.row` · R-tree 다섯(`bounds` · `span_bounds`의 `lane_min`/`lane_max` · `period_bounds` · `cell_bounds` · `item_bounds`의 `row_min`/`row_max`).
/// 다른 트랙에 속한 값이라도 이 덩이 안의 열쇠를 가리키면 함께 옮긴다(예: 판 줄의 `ord` · 이사의 도착 줄).
/// 새 범위에 다른 트랙의 줄이 있으면 실패한다. 옛 범위와 겹치는 이동(`key0`가 옛 덩이 안)은 빈 자리를 거쳐 두 걸음에 한다.
/// **제품 길은 부르지 않는다** — 열쇠 ≠ 자리를 흉내 내는 검사(`rowkeys.rs` · `write_tx.rs` 등)가 쓴다. 변형 값 옮기기는 `patch::apply`의 "relink"와 한 몸([`shift_variant_rows`]).
pub fn rekey_track(tx: &Transaction, track: i64, key0: i64) -> Result<()> {
    let (first, last, n): (Option<i64>, Option<i64>, i64) =
        tx.query_row("SELECT MIN(id),MAX(id),COUNT(id) FROM rows WHERE track=?1", [track], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?;
    let (Some(a), Some(b)) = (first, last) else {
        // 줄이 없는 트랙은 옮길 것이 없다. 트랙 자체가 없으면 부른 쪽의 착오다.
        let known: i64 = tx.query_row("SELECT count(*) FROM tracks WHERE id=?1", [track], |r| r.get(0))?;
        return if known == 0 { Err(format!("없는 트랙입니다: {track}").into()) } else { Ok(()) };
    };
    if b - a + 1 != n {
        return Err(format!("트랙 {track}의 줄 열쇠가 이어지지 않습니다({a}~{b} · {n}줄)").into());
    }
    let end = key0 + n - 1;
    if key0 < 0 || end > i64::from(i32::MAX) {
        return Err(format!("줄 열쇠의 범위를 벗어납니다: {key0}~{end} (R-tree는 0 이상의 32비트 정수만 받습니다)").into());
    }
    if key0 == a {
        return Ok(());
    }
    let foreign: i64 = tx.query_row("SELECT count(*) FROM rows WHERE id BETWEEN ?1 AND ?2 AND track<>?3", params![key0, end, track], |r| r.get(0))?;
    if foreign != 0 {
        return Err(format!("새 줄 범위 {key0}~{end}에 다른 트랙의 줄이 있습니다").into());
    }
    if key0 <= b && end >= a {
        // 옛 덩이와 겹치는 이동 — 한 문장으로 하면 옮기는 도중 열쇠가 부딪친다. 가장 큰 번호 뒤로 한 번 나갔다 돌아온다.
        let top: i64 = tx.query_row("SELECT MAX(id) FROM rows", [], |r| r.get(0))?;
        rekey_track(tx, track, top.max(end) + 1)?;
        return rekey_track(tx, track, key0);
    }
    let d = key0 - a;
    // 자식 표 · 열. 새 범위는 비어 있고(위에서 확인) 옛 덩이 안의 값만 고르므로, 한 문장 안에서 옮긴 값을 다시 잡는 일이 없다.
    let shift = |sql: &str| -> Result<()> {
        tx.execute(sql, params![d, a, b])?;
        Ok(())
    };
    shift("UPDATE rows SET id=id+?1 WHERE id BETWEEN ?2 AND ?3")?;
    shift("UPDATE periods SET row=row+?1 WHERE row BETWEEN ?2 AND ?3")?;
    shift("UPDATE events SET lane=lane+?1 WHERE lane BETWEEN ?2 AND ?3")?;
    // 두 열이 한 문장에서 함께 바뀌어야 `CHECK(row<=row2)`가 중간에 깨지지 않는다.
    shift("UPDATE items SET row=CASE WHEN row BETWEEN ?2 AND ?3 THEN row+?1 ELSE row END,\
                            row2=CASE WHEN row2 BETWEEN ?2 AND ?3 THEN row2+?1 ELSE row2 END \
           WHERE row BETWEEN ?2 AND ?3 OR row2 BETWEEN ?2 AND ?3")?;
    shift("UPDATE row_labels SET row=row+?1 WHERE row BETWEEN ?2 AND ?3")?;
    shift("UPDATE groups SET first_row=first_row+?1 WHERE first_row BETWEEN ?2 AND ?3")?;
    // 변형이 줄을 가리키는 값 — `patch::apply`의 "relink"와 같은 몸(`shift_variant_rows`).
    let mut groups = VariantGroups::read(tx)?;
    shift_variant_rows(tx, &mut groups, a, b, d)?;
    groups.write(tx)?;
    // 요약의 기본 키는 (level, lane, bucket, pack) — 단계마다 앞머리를 짚어 그 줄의 통만 찾아 지우고 넣는다.
    for level in 0..=LEVEL_MAX as i64 {
        tx.execute("UPDATE summaries SET lane=lane+?1 WHERE level=?4 AND lane BETWEEN ?2 AND ?3", params![d, a, b, level])?;
    }
    shift("UPDATE names SET row=row+?1 WHERE row BETWEEN ?2 AND ?3")?;
    // R-tree. 사건 · 띠 · 칸은 한 줄(min = max)이라 두 끝을 함께 옮긴다. 일반 항목은 두 줄에 걸칠 수 있어 끝마다 가린다.
    shift("UPDATE bounds SET lane_min=lane_min+?1,lane_max=lane_max+?1 WHERE lane_min>=?2 AND lane_max<=?3")?;
    shift("UPDATE span_bounds SET lane_min=lane_min+?1,lane_max=lane_max+?1 WHERE lane_min>=?2 AND lane_max<=?3")?;
    shift("UPDATE period_bounds SET row_min=row_min+?1,row_max=row_max+?1 WHERE row_min>=?2 AND row_max<=?3")?;
    shift("UPDATE cell_bounds SET row_min=row_min+?1,row_max=row_max+?1 WHERE row_min>=?2 AND row_max<=?3")?;
    shift("UPDATE item_bounds SET row_min=CASE WHEN row_min BETWEEN ?2 AND ?3 THEN row_min+?1 ELSE row_min END,\
                                  row_max=CASE WHEN row_max BETWEEN ?2 AND ?3 THEN row_max+?1 ELSE row_max END \
           WHERE row_min BETWEEN ?2 AND ?3 OR row_max BETWEEN ?2 AND ?3")?;
    Ok(())
}

/// 변형 묶음의 줄 목록(`variant_groups.rows` — 전체 줄 열쇠의 JSON 배열)을 한 번 읽어 두고 옮긴 뒤 바뀐 것만 다시 쓴다
/// ([`rekey_track`] · `patch::apply`의 "relink"가 함께 쓴다 — 덩이가 여럿이어도 한 번만 읽는다).
pub(crate) struct VariantGroups {
    list: Vec<(i64, Vec<Value>)>,
    changed: std::collections::BTreeSet<usize>,
}

impl VariantGroups {
    /// 변형 묶음 전부. 목록으로 읽히지 않는 묶음은 옮겨 적을 수 없어 Err(조용히 건너뛰면 그 묶음이 낡은 줄을 가리킨 채 남는다 — P4 과제 5c 고침 1회차 Minor 6).
    pub(crate) fn read(tx: &Transaction) -> Result<Self> {
        let mut list = Vec::new();
        let mut stmt = tx.prepare("SELECT id,rows FROM variant_groups")?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            let (id, text): (i64, String) = (r.get(0)?, r.get(1)?);
            match serde_json::from_str::<Value>(&text) {
                Ok(Value::Array(items)) => list.push((id, items)),
                _ => return Err(format!("변형 묶음 {id}의 줄 목록이 배열이 아닙니다: {text}").into()),
            }
        }
        Ok(Self { list, changed: Default::default() })
    }

    /// `[lo, hi]` 안의 줄을 가리키는 묶음이 있는가.
    pub(crate) fn any_in(&self, lo: i64, hi: i64) -> bool {
        self.list.iter().any(|(_, items)| items.iter().any(|v| v.as_i64().is_some_and(|x| (lo..=hi).contains(&x))))
    }

    /// `[a, b]` 안의 값만 `d`만큼 옮긴다(메모리에서 — [`VariantGroups::write`]가 쓴다).
    fn shift(&mut self, a: i64, b: i64, d: i64) {
        for (at, (_, items)) in self.list.iter_mut().enumerate() {
            for v in items.iter_mut() {
                if let Some(x) = v.as_i64().filter(|x| (a..=b).contains(x)) {
                    *v = Value::from(x + d);
                    self.changed.insert(at);
                }
            }
        }
    }

    /// 바뀐 묶음만 다시 쓴다.
    pub(crate) fn write(&self, tx: &Transaction) -> Result<()> {
        let mut write = tx.prepare("UPDATE variant_groups SET rows=?2 WHERE id=?1")?;
        for at in &self.changed {
            let (id, items) = &self.list[*at];
            write.execute(params![id, serde_json::to_string(items)?])?;
        }
        Ok(())
    }
}

/// 변형이 줄을 가리키는 값 가운데 `[a, b]` 안의 것을 `d`만큼 옮긴다 — 이사 도착(`variant_moves.row`) · 변형 줄(`variant_rows.row`) · `after`(0 이상) ·
/// `ord`(`after = −2`일 때만 — 판 줄의 열쇠. 그 밖의 `ord`는 같은 자리의 차례일 뿐) · 묶음의 줄(`groups` — 메모리, 부르는 쪽이 끝에 쓴다).
/// [`rekey_track`](한 트랙의 덩이 옮기기)과 `patch::apply`의 "relink"(다시 쓴 트랙의 옛 덩이 → 새 덩이)의 한 몸(과제 A+ 넘김 "같은 규칙 두 곳").
/// 변형 표는 기본 키가 (variant, row)인 WITHOUT ROWID라 열쇠 갱신은 지우고 넣기로 돈다 — 새 범위가 비어 있어야 충돌하지 않는다(부르는 쪽이 지킨다).
pub(crate) fn shift_variant_rows(tx: &Transaction, groups: &mut VariantGroups, a: i64, b: i64, d: i64) -> Result<()> {
    for sql in ["UPDATE variant_moves SET row=row+?1 WHERE row BETWEEN ?2 AND ?3",
        "UPDATE variant_rows SET row=row+?1 WHERE row BETWEEN ?2 AND ?3",
        "UPDATE variant_rows SET after=after+?1 WHERE after BETWEEN ?2 AND ?3",
        "UPDATE variant_rows SET ord=ord+?1 WHERE after=-2 AND ord BETWEEN ?2 AND ?3"] {
        tx.execute(sql, params![d, a, b])?;
    }
    groups.shift(a, b, d);
    Ok(())
}

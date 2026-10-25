//! 변형(variant) — 켤 수 있는 것 하나마다 '기본 상태와의 차이'를 자료로 들고 있다가, 조회할 때 얹는다.
//! 약속은 `docs/계약-아카이브-3단계.md` 2-4절(조회 명령의 `variants`) · 3-2절(줄 쌓기).
//!
//! 세 가지다:
//!   `host:<상위 띠 uid>`  소속 펼치기 — 상위 띠 아래 접혀 있던 소속이 제 줄을 갖는다(새 줄 · 새 띠 · 사건의 이사).
//!   `scope:<대범위 uid>`  대범위 모아 보기 — 구성 정권의 줄이 대범위 가지로 **옮겨 쌓인다**(줄 번호는 그대로).
//!   `view:<판 id>`        집합 보기(kind 3 — 10건 6 · 감독 선택 D4) — 구성 나라의 줄이 **트랙을 넘어** 맨 위 판 트랙의 새 줄로 옮겨 간다
//!                         (띠는 이사로, 원래 트랙의 그 줄은 `variant_rows.after = −2`로 빠진다 — 앱이 쌓지 않는다).
//!                         그 변형에서만 있는 일반 항목은 **판을 켠 자리에 이미 놓여** 실려 오므로 가리키는 띠를 따라 다시 옮기지 않는다([Variants::boards]).
//!   `shelf:<그릇 uid>`    선반(kind 6 — 리메이크 4단계 · 감독 결정 2026-10-25 '선반 = 엔진 변형 길') — 그 그릇 하나만 켠 배치에서 구성원 가운데
//!                         상위 몇만 제 줄에 남고 나머지 띠는 **숨는다**(이사의 도착 줄 −1 — [`HIDDEN_ROW`]). 다시 지은 줄은 새 줄 · 이사로,
//!                         구성원이 다 떠난 기본 줄은 `after = −2`(ord −1 — 옮겨 간 판 줄이 없다)로 빠진다. 그 그릇의 `scope:` 변형을 **대신**한다(함께 켜지 않는다).
//!                         숨은 띠를 가리키는 일반 항목은 기본 판이면 빠지고, 켠 변형의 항목(숨긴 구성원 꼬리표 같은 것)이면 제자리에 남는다([Variants::item_rows]).
//!
//! 자료의 얼개:
//!   - `rows.variant` · `periods.variant` · `cells.variant` · `events.variant` · `items.variant`
//!     = 0이면 늘 있는 것, 아니면 **그 변형을 켰을 때만** 있는 것.
//!   - `variant_rows`  그 변형에서 줄을 쌓는 차례(`after` · `ord`)와 덮어쓰는 값 — 화면(Dart)이 읽는다.
//!   - `variant_moves` 줄이 옮겨 쌓이는 것으로 설명되지 않는 이사(띠 · 사건이 다른 줄로 간 것). 도착 줄 −1은 '그 변형에서 숨는다'(선반)이고,
//!     딸린 것(칸 · 사건 · 기본 판 일반 항목)도 함께 숨는다 — 타일 · `rows_near` · 줄 이름 어디에도 −1 줄은 나가지 않는다.
//!   - `variant_hides` 그 변형이 켜지면 가려지는 기본 판(대신 `variant`를 단 변형 판이 나온다).
//!
//! **변형을 주지 않으면 답은 예전과 바이트까지 같다** — 켠 것이 없으면 `variant=0`만 고르는 조건이 붙는데,
//! 변형 자료가 없던 저장소의 모든 줄이 이미 `variant=0`이라 고르는 것이 하나도 달라지지 않는다.
use crate::rowmap::RowMap;
use crate::{Result, Store};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

/// 집합 보기 변형의 갈래 번호(계약 부록 가-9의 예약 kind 3).
pub const KIND_VIEW: i64 = 3;
/// 대범위 모아 보기(그릇) 변형의 갈래 번호(계약 2-4절 — kind 2 · uid = 대범위의 이름). P3-18의 포개짐 `within`은 이 갈래에만 싣는다.
pub const SCOPE_KIND: i64 = 2;
/// 선반 변형의 갈래 번호(계약 2-4절 — kind 6 · 열쇠 `shelf:<그릇 uid>` · uid = 그 그릇). 그 그릇의 [`SCOPE_KIND`] 변형을 대신한다.
pub const SHELF_KIND: i64 = 6;
/// 이사의 도착 줄이 이 값이면 그 띠 · 사건은 **그 변형에서 숨는다**(선반 — 계약 2-4절). 줄 열쇠는 0 이상이라 겹치지 않고,
/// 열쇠 ↔ 자리 바꾸기(`RowMap::pos` · `outward`)도 음수를 '줄 없음'으로 그대로 둔다.
pub const HIDDEN_ROW: i64 = -1;
/// 숨긴 구성원 꼬리표의 일반 항목 구역(계약 6-10절 — 선반 변형에만 · 숨은 띠마다 하나 · 가지 끝 줄). `layout`이 선반 변형의 `shelf` 목록을 이 구역에서 읽는다.
pub const SHELF_SECTION: i64 = 59;

/// 이사의 갈래.
pub const MOVE_BAND: i64 = 1;
pub const MOVE_EVENT: i64 = 2;
/// 가리는 것의 갈래.
pub const HIDE_CELL: i64 = 3;
pub const HIDE_ITEM: i64 = 4;

/// 요청에 실려 온 변형을 저장소에 비추어 푼 것.
#[derive(Debug, Clone, Default)]
pub struct Variants {
    /// 켠 변형의 번호(오름차순 · 중복 없음).
    pub on: Vec<i64>,
    /// 띠 번호 → 이사한 줄.
    pub bands: HashMap<i64, i64>,
    /// 사건 번호 → 이사한 줄.
    pub events: HashMap<i64, i64>,
    /// 가려지는 칸 · 일반 항목의 번호.
    pub hidden_cells: HashSet<i64>,
    pub hidden_items: HashSet<i64>,
    /// 이사로 줄을 떠난 것이 있는 줄(그 줄이 비었는지 다시 봐야 한다).
    pub from_rows: HashSet<i64>,
    /// 켠 변형 가운데 집합 보기(kind 3)의 번호. 그 변형에서만 있는 일반 항목은 판을 켠 자리에 놓여 실려 오므로
    /// [Variants::item_rows]로 옮기지 않는다(옮기면 판 안의 승계선이 한 줄로 오그라든다 — 두 끝이 모두 이사한 줄이라).
    pub boards: HashSet<i64>,
    /// 이사의 도착 줄이 [`HIDDEN_ROW`]인 것(숨는 띠 · 사건)이 하나라도 있는가 — 타일이 일반 항목의 변형 번호를 함께 읽을지 정한다.
    /// 선반 변형을 켜지 않으면 늘 거짓이라 예전과 같은 SQL · 같은 답이다.
    pub hiding: bool,
}

impl Variants {
    /// 켠 것이 하나도 없고 이사도 없는가 — 그때의 답은 변형을 넣기 전과 같다.
    pub fn is_plain(&self) -> bool {
        self.on.is_empty()
    }

    /// 조회가 `AND …`로 끼워 쓰는 조각: 늘 있는 것(0)과 켠 변형의 것만 고른다.
    pub fn keep(&self, column: &str) -> String {
        if self.on.is_empty() {
            return format!(" AND {column}=0");
        }
        let list: Vec<String> = std::iter::once("0".to_owned()).chain(self.on.iter().map(i64::to_string)).collect();
        format!(" AND {column} IN ({})", list.join(","))
    }

    /// 띠가 이사한 줄(이사하지 않았으면 제자리).
    pub fn band_row(&self, band: i64, row: i64) -> i64 {
        self.bands.get(&band).copied().unwrap_or(row)
    }

    /// 사건이 그려지는 줄 — 제 이사가 먼저, 없으면 든 띠의 이사를 따른다.
    pub fn event_row(&self, event: i64, band: i64, lane: i64) -> i64 {
        if let Some(row) = self.events.get(&event) {
            return *row;
        }
        if band != 0 {
            if let Some(row) = self.bands.get(&band) {
                return *row;
            }
        }
        lane
    }

    /// 그 띠가 켠 변형에서 숨었는가(이사의 도착 줄 [`HIDDEN_ROW`] — 선반).
    pub fn band_hidden(&self, band: i64) -> bool {
        self.bands.get(&band) == Some(&HIDDEN_ROW)
    }

    /// 일반 항목이 그려지는 줄 범위 — 가리키는 띠 · 사건이 이사하면 그쪽 끝이 따라간다.
    /// `ref_kind`: 1 띠 · 2 사건 · 그 밖은 '모름'이라 제자리다. `variant`: 그 항목의 변형 번호(0 = 기본 판).
    /// 가리키는 것이 켠 변형에서 **숨었으면**([`HIDDEN_ROW`] — 선반) 기본 판 항목은 `None`(싣지 않는다)이고, 켠 변형의 항목(숨긴 구성원을
    /// 가리키는 꼬리표 같은 것)은 제자리다 — 그 변형이 숨긴 것을 일부러 가리키려고 거기 놓인 것이다.
    /// 줄은 열쇠로 받고 열쇠로 내지만, 두 끝의 차례는 **자리**로 정한다 — 열쇠 ≠ 자리 저장소에서는 다른 트랙의 열쇠가 거꾸로 놓일 수 있다(계획 P4).
    pub fn item_rows(&self, rows: &RowMap, ref_kind: i64, reference: i64, row: i64, row2: i64, variant: i64) -> Option<(i64, i64)> {
        let moved = match ref_kind {
            MOVE_BAND => self.bands.get(&reference).copied(),
            MOVE_EVENT => self.events.get(&reference).copied(),
            _ => None,
        };
        let Some(to) = moved else { return Some((row, row2)) };
        if to == HIDDEN_ROW {
            return (variant != 0).then_some((row, row2));
        }
        if row == row2 {
            return Some((to, to));
        }
        // 두 줄에 걸친 것(관계선 · 테두리): 가리키는 쪽 끝만 옮기고 다시 min · max를 잡는다.
        let other = if self.bands.values().chain(self.events.values()).any(|r| *r == row) || row2 == to { row } else { row2 };
        if rows.is_identity() {
            return Some((to.min(other), to.max(other)));
        }
        Some(if rows.pos(to) <= rows.pos(other) { (to, other) } else { (other, to) })
    }

    /// 도착 줄(열쇠)이 `inside`에 드는 띠 — 타일이 '밖에서 들어온 것'을 따로 찾을 때 쓴다. 타일은 묶음의 **자리** 범위로 가린다.
    /// 숨은 것(도착 줄 −1)은 어느 묶음에도 들지 않는다(`inside`가 자리 −1을 거짓으로 답한다).
    pub fn incoming_bands(&self, inside: impl Fn(i64) -> bool) -> Vec<i64> {
        let mut out: Vec<i64> = self.bands.iter().filter(|(_, row)| inside(**row)).map(|(id, _)| *id).collect();
        out.sort_unstable();
        out
    }

    pub fn incoming_events(&self, inside: impl Fn(i64) -> bool) -> Vec<i64> {
        let mut out: Vec<i64> = self.events.iter().filter(|(_, row)| inside(**row)).map(|(id, _)| *id).collect();
        out.sort_unstable();
        out
    }
}

/// 번호 목록을 SQL의 `IN (…)` 글로(값은 모두 검사를 지난 정수다).
pub fn in_list(values: &[i64]) -> String {
    values.iter().map(i64::to_string).collect::<Vec<_>>().join(",")
}

impl Store {
    /// 요청의 `"variants":["host:…","scope:…"]`를 이 저장소에 비추어 푼다.
    /// 변형 자료가 없는 저장소는 `None`이고, 그때 `variants`를 주면 까닭과 함께 실패한다.
    pub fn variants_of(&self, q: &Value) -> Result<Option<Variants>> {
        let asked: Vec<String> = match &q["variants"] {
            Value::Null => Vec::new(),
            Value::Array(list) => {
                let mut out = Vec::with_capacity(list.len());
                for item in list {
                    let key = item.as_str().ok_or("변형(variants)은 열쇠 글의 목록입니다")?;
                    if key.is_empty() {
                        return Err("변형의 열쇠가 비었습니다".into());
                    }
                    if !out.iter().any(|k: &String| k == key) {
                        out.push(key.to_owned());
                    }
                }
                out
            }
            _ => return Err("변형(variants)은 열쇠 글의 목록입니다".into()),
        };
        if !self.has_variants {
            if asked.is_empty() {
                return Ok(None);
            }
            return Err("이 저장소에는 변형 자료가 없습니다. 3단계 도구로 다시 만들어야 합니다".into());
        }
        let mut on: Vec<i64> = Vec::with_capacity(asked.len());
        let mut boards: HashSet<i64> = HashSet::new();
        {
            let mut stmt = self.db.prepare_cached("SELECT id,kind FROM variants WHERE key=?1")?;
            for key in &asked {
                let found: Option<(i64, i64)> = stmt.query_row([key], |r| Ok((r.get(0)?, r.get(1)?))).ok();
                let (id, kind) = found.ok_or_else(|| format!("없는 변형입니다: {key}"))?;
                on.push(id);
                if kind == KIND_VIEW {
                    boards.insert(id);
                }
            }
        }
        on.sort_unstable();
        let mut v = Variants { on, boards, ..Default::default() };
        if v.on.is_empty() {
            return Ok(Some(v));
        }
        let ids = in_list(&v.on);
        {
            // 이사: 대범위가 소속을 이긴다 — 같은 것을 둘이 옮기려 하면 번호가 큰 갈래(대범위 kind 2)가 마지막에 쓴다.
            // 선반(kind 6)은 그보다 뒤라 숨김(도착 줄 −1)이 이긴다 — 펼친 소속이라도 선반이 숨긴 띠는 숨는다.
            let sql = format!(
                "SELECT m.kind,m.ref,m.row FROM variant_moves m JOIN variants v ON v.id=m.variant WHERE m.variant IN ({ids}) ORDER BY v.kind,m.variant"
            );
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let (kind, reference, row): (i64, i64, i64) = (r.get(0)?, r.get(1)?, r.get(2)?);
                match kind {
                    MOVE_BAND => {
                        v.bands.insert(reference, row);
                    }
                    MOVE_EVENT => {
                        v.events.insert(reference, row);
                    }
                    _ => {}
                }
            }
        }
        v.hiding = v.bands.values().chain(v.events.values()).any(|row| *row == HIDDEN_ROW);
        {
            let sql = format!("SELECT kind,ref FROM variant_hides WHERE variant IN ({ids})");
            let mut stmt = self.db.prepare(&sql)?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let (kind, reference): (i64, i64) = (r.get(0)?, r.get(1)?);
                if kind == HIDE_CELL {
                    v.hidden_cells.insert(reference);
                } else if kind == HIDE_ITEM {
                    v.hidden_items.insert(reference);
                }
            }
        }
        if !v.bands.is_empty() {
            let list = in_list(&v.bands.keys().copied().collect::<Vec<_>>());
            let mut stmt = self.db.prepare(&format!("SELECT row FROM periods WHERE id IN ({list})"))?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                v.from_rows.insert(r.get(0)?);
            }
        }
        if !v.events.is_empty() {
            let list = in_list(&v.events.keys().copied().collect::<Vec<_>>());
            let mut stmt = self.db.prepare(&format!("SELECT lane FROM events WHERE id IN ({list})"))?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                v.from_rows.insert(r.get(0)?);
            }
        }
        Ok(Some(v))
    }

    /// 화면이 열 때 한 번 받는 변형의 목록과 줄 쌓기(계약 2-4절의 `layout`에 실린다).
    pub fn variant_layout(&self) -> Result<Value> {
        if !self.has_variants {
            return Ok(Value::Array(Vec::new()));
        }
        let mut out: Vec<Value> = Vec::new();
        let mut at: HashMap<i64, usize> = HashMap::new();
        {
            let mut stmt = self.db.prepare("SELECT id,key,kind,track,band,uid,name,notes FROM variants ORDER BY id")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let id: i64 = r.get(0)?;
                at.insert(id, out.len());
                out.push(serde_json::json!({"id":id,"key":r.get::<_,String>(1)?,"kind":r.get::<_,i64>(2)?,"track":r.get::<_,i64>(3)?,
                    "band":r.get::<_,i64>(4)?,"uid":r.get::<_,String>(5)?,"name":r.get::<_,String>(6)?,"notes":r.get::<_,String>(7)?,
                    "rows":[],"groups":[]}));
            }
        }
        {
            let mut stmt = self.db.prepare("SELECT variant,row,after,ord,is_new,scope_pad,group_start FROM variant_rows ORDER BY variant,ord,row")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let variant: i64 = r.get(0)?;
                let Some(index) = at.get(&variant) else { continue };
                let scope_pad: i64 = r.get(5)?;
                let mut row = serde_json::json!({"row":r.get::<_,i64>(1)?,"after":r.get::<_,i64>(2)?,
                    "ord":r.get::<_,i64>(3)?,"new":r.get::<_,i64>(4)?,"scope_pad":scope_pad,"group_start":r.get::<_,i64>(6)?});
                // P3-18 — 변형이 덮어쓰는 그릇 여백도 머리 수 · 발 · 매달림 수로 갈라 함께 싣는다(줄 답과 같은 칸).
                crate::layout::add_scope_split(row.as_object_mut().unwrap(), scope_pad);
                out[*index]["rows"].as_array_mut().unwrap().push(row);
            }
        }
        {
            let mut stmt = self.db.prepare("SELECT variant,key,depth,name,color,kind,rows FROM variant_groups ORDER BY id")?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                let variant: i64 = r.get(0)?;
                let Some(index) = at.get(&variant) else { continue };
                let list: String = r.get(6)?;
                out[*index]["groups"].as_array_mut().unwrap().push(serde_json::json!({"key":r.get::<_,String>(1)?,"depth":r.get::<_,i64>(2)?,
                    "name":r.get::<_,String>(3)?,"color":r.get::<_,i64>(4)?,"kind":r.get::<_,i64>(5)?,
                    "rows":serde_json::from_str::<Value>(&list).unwrap_or_else(|_| serde_json::json!([]))}));
            }
        }
        // P3-18 — 그릇(대범위 모아 보기 · kind 2) 변형의 포개짐 `within`: 같은 트랙에서 제 묶음 줄을 모두 품고 더 큰 그릇 변형의 id 목록(정적 · 번호 차례).
        // 앱이 켠 그릇마다 `containsAll`로 셈하던 것 — 이제 앱은 그 가운데 켠 것의 수를 깊이로 쓴다. 줄 열쇠로 견주어도 자리로 견주어도 같다.
        let scopes: Vec<(usize, i64, i64, std::collections::BTreeSet<i64>)> = out.iter().enumerate()
            .filter(|(_, v)| v["kind"].as_i64() == Some(SCOPE_KIND))
            .map(|(i, v)| {
                let rows = v["groups"].as_array().into_iter().flatten()
                    .flat_map(|g| g["rows"].as_array().into_iter().flatten().filter_map(Value::as_i64).collect::<Vec<_>>()).collect();
                (i, v["id"].as_i64().unwrap_or(0), v["track"].as_i64().unwrap_or(0), rows)
            }).collect();
        for (i, _, track, rows) in &scopes {
            let within: Vec<i64> = scopes.iter()
                .filter(|(j, _, t2, r2)| j != i && t2 == track && r2.len() > rows.len() && rows.is_subset(r2))
                .map(|(_, id2, _, _)| *id2).collect();
            out[*i]["within"] = serde_json::json!(within);
        }
        self.shelf_lists(&mut out)?;
        self.outward_variant_rows(&mut out);
        Ok(Value::Array(out))
    }

    /// 선반(kind 6 — 리메이크 4단계 선반 갈래 걸음 4) 변형마다 숨긴 구성원 목록 `shelf` = 그 변형의 구역 [`SHELF_SECTION`] 항목(숨긴 구성원 꼬리표)을
    /// 그릇 안 차례(`a`) 차례로 — `{uid(= text2 · 그 띠의 uid), name, color, start, end(분 — 띠의 바깥 끝), ord(= a — 숨은 첫째가 shelfKeep 5)}`. 다른 갈래에는 싣지 않는다.
    /// 꼬리표는 가지 끝 줄(그 변형의 그릇 묶음 줄 가운데 하나)에 놓이므로 일반 항목 표를 통째로 훑지 않고 공간 색인(`item_bounds` — 줄은 열쇠)의 그 줄 범위에서 고른다.
    /// 묶음의 줄이 아직 열쇠일 때(`outward_variant_rows` 앞) 부른다. 답에 줄 값이 없어 열쇠 ≠ 자리 저장소에서도 같은 값이다.
    fn shelf_lists(&self, out: &mut [Value]) -> Result<()> {
        if !out.iter().any(|v| v["kind"].as_i64() == Some(SHELF_KIND)) {
            return Ok(());
        }
        let mut stmt = self.db.prepare(&format!(
            "SELECT i.text2,i.name,i.color,i.start,i.end,i.a FROM item_bounds b CROSS JOIN items i ON i.id=b.id \
             WHERE b.row_min>=?1 AND b.row_max<=?2 AND i.section={SHELF_SECTION} AND i.variant=?3 ORDER BY i.a,i.id"
        ))?;
        for v in out.iter_mut().filter(|v| v["kind"].as_i64() == Some(SHELF_KIND)) {
            let rows: Vec<i64> = v["groups"].as_array().into_iter().flatten()
                .flat_map(|g| g["rows"].as_array().into_iter().flatten().filter_map(Value::as_i64)).collect();
            let mut list: Vec<Value> = Vec::new();
            if let (Some(lo), Some(hi)) = (rows.iter().min(), rows.iter().max()) {
                let mut found = stmt.query(rusqlite::params![lo, hi, v["id"].as_i64().unwrap_or(0)])?;
                while let Some(r) = found.next()? {
                    list.push(serde_json::json!({"uid":r.get::<_,String>(0)?,"name":r.get::<_,String>(1)?,"color":r.get::<_,i64>(2)?,
                        "start":r.get::<_,i64>(3)?,"end":r.get::<_,i64>(4)?,"ord":r.get::<_,i64>(5)?}));
                }
            }
            v["shelf"] = Value::Array(list);
        }
        Ok(())
    }

    /// 변형의 줄 쌓기 · 묶음을 밖으로(계획 P4): `row` · `after`(0 이상) · 묶음의 `rows`는 줄 열쇠이고, `ord`는 `after = −2`일 때만
    /// 판 줄의 열쇠다(그 밖은 같은 자리의 차례 · 옮겨 간 판 줄이 없는 빠지는 줄 — 선반 — 은 −1이라 그대로 −1로 나간다). 자리로 바꾼 뒤 `ORDER BY variant,ord,row`를 자리로 다시 늘어놓는다 —
    /// 열쇠 차례로 고른 것이라 그대로 두면 통째로 지은 저장소와 차례가 다르다. 묶음은 지은 차례(`id`) 그대로다. 열쇠 = 자리면 아무것도 하지 않는다.
    fn outward_variant_rows(&self, out: &mut [Value]) {
        if self.rows.is_identity() {
            return;
        }
        let pos = |v: &Value| v.as_i64().map(|key| self.rows.pos(key)).filter(|p| *p >= 0);
        for variant in out.iter_mut() {
            if let Some(list) = variant["rows"].as_array_mut() {
                for r in list.iter_mut() {
                    if r["after"] == -2 {
                        if let Some(p) = pos(&r["ord"]) {
                            r["ord"] = Value::from(p);
                        }
                    }
                }
            }
            self.rows.outward(&mut variant["rows"], &["row", "after"]);
            if let Some(list) = variant["rows"].as_array_mut() {
                list.sort_by_key(|r| (r["ord"].as_i64(), r["row"].as_i64()));
            }
            self.rows.outward(&mut variant["groups"], &["rows"]);
        }
    }
}

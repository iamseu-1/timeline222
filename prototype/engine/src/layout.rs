//! 화면이 열 때 한 번 받는 뼈대(`{"op":"layout"}`)와, 보는 범위에 내용이 있는 줄을 묻는 길(`{"op":"rows_near"}`),
//! 상세 창이 읽는 항목 기록(`{"op":"entity"}`). 줄 자리(누적 높이)는 화면이 켠 자료집과 보기 조건에 맞춰 셈한다.
//! 약속은 `docs/계약-아카이브-3단계.md` 2절.
use crate::levels::{bucket_of, LEVEL_MAX, PRE_MIN, TILE_BUCKETS};
use crate::{Result, Store, DAY};
use serde_json::{json, Map, Value};
use std::collections::BTreeSet;

/// 한 벌 P3-18 — 줄 값 비트 풀기(계약 3-3 · 6-5): `fig_wide` 한 정수를 이름 붙은 칸으로 풀어 줄 답에 더한다. 앱 `scene/layout.dart`가 하던 셈을
/// 그대로 옮긴 것이라(옛 저장소 — 비트 3 ~ 5가 0 — 의 예외 규칙까지) 앱은 읽기만 한다. 원래 정수 `fig_wide`도 답에 그대로 남는다(검사 · 도구가 읽음).
///   `fig_wide_levels` 넉넉하게의 인물 단 수(0 ~ 3) · `rail` 그 줄의 기간 막대 단 수(−1 = 실리지 않은 옛 저장소 — 트랙 값을 쓴다) ·
///   `organ` · `power` · `real` 기관 · 집권 · 실권 칸 · `hang` 매달린 속국 이름표 줄 수(`zones`로 자름) · `raised` 위로 솟는 줄 ·
///   `contained` 그릇의 줄 · `cell_rows` 비트 16 ~ 18을 실었다는 표시 · `dynasty` · `leader` · `cabinet` 그 줄의 칸 · `events` 그 줄에 사건(표시가 없으면 참).
pub(crate) fn add_row_flags(row: &mut Map<String, Value>, packed: i64, zones: i64) {
    let rail_bits = (packed >> 3) & 7;
    let carried = rail_bits != 0; // 줄 단위 트랙 값이 실렸는가 — 옛 저장소는 0이라 비트 6 ~ 15 · 19 ~ 20을 읽지 않는다
    let on = |bit: u32| carried && (packed & (1 << bit)) != 0;
    let flag = |b: bool| Value::from(i64::from(b));
    let cell_rows = on(19);
    row.insert("fig_wide_levels".into(), Value::from(if carried { packed & 7 } else { packed }));
    row.insert("rail".into(), Value::from(if carried { rail_bits - 1 } else { -1 }));
    row.insert("organ".into(), flag(on(6)));
    row.insert("power".into(), flag(on(7)));
    row.insert("real".into(), flag(on(8)));
    row.insert("hang".into(), Value::from(if carried { ((packed >> 9) & 31).min(zones).max(0) } else { 0 }));
    row.insert("raised".into(), flag(on(14)));
    row.insert("contained".into(), flag(on(15)));
    row.insert("cell_rows".into(), flag(cell_rows));
    // 왕조 · 지도자 · 내각 칸 비트는 표시(비트 19)와 상관없이 그대로 읽는다 — 앱이 그렇게 읽어 왔다(뜻은 표시가 설 때만 있다).
    row.insert("dynasty".into(), flag((packed & (1 << 16)) != 0));
    row.insert("leader".into(), flag((packed & (1 << 17)) != 0));
    row.insert("cabinet".into(), flag((packed & (1 << 18)) != 0));
    row.insert("events".into(), flag(!cell_rows || (packed & (1 << 20)) != 0));
}

/// 한 벌 P3-18 — 대범위(그릇) 여백 `scope_pad`(px — 내보내기의 머리 16 · 발 6 · 본국 줄에 매달린 머리 −4의 합 · 계약 3-1절 끝)를
/// 머리 수 · 발(0/1) · 매달린 머리 수로 가른다. 앱 `_scopePadOf`의 앞 절반 그대로: 발을 먼저 떼어 보고 안 되면 발 없이(한 줄에 발은
/// 많아야 하나, 머리는 여럿). px로 되돌리는 뒷 절반(폴더 · 조감 · 상자의 자)은 보기 상태에 달려 앱에 남는다. 갈라지지 않는 값은 None.
pub(crate) fn scope_split(stored: i64) -> Option<(i64, i64, i64)> {
    use crate::lay::rows::G0;
    let (head, foot) = (G0.scope_head as i64, G0.scope_foot as i64);
    let hung = head + 2 - G0.gap as i64 - G0.group_gap as i64; // −4
    if stored == 0 {
        return Some((0, 0, 0));
    }
    for f in [1, 0] {
        let rest = stored - f * foot;
        if rest == hung {
            return Some((0, f, 1));
        }
        if rest >= 0 && rest % head == 0 {
            return Some((rest / head, f, 0));
        }
    }
    None
}

/// 가른 값을 줄 답에 `scope_head` · `scope_foot` · `scope_hung`으로 더한다 — 갈라지지 않는 값이면 셋 다 −1(앱은 그때 `scope_pad` px를 그대로 쓴다).
/// 칸이 아예 없는 답(옛 엔진 · 손으로 쓴 검사 답)과 갈라지지 않는 값을 앱이 가르도록 늘 싣는다.
pub(crate) fn add_scope_split(row: &mut Map<String, Value>, stored: i64) {
    let (head, foot, hung) = scope_split(stored).unwrap_or((-1, -1, -1));
    row.insert("scope_head".into(), Value::from(head));
    row.insert("scope_foot".into(), Value::from(foot));
    row.insert("scope_hung".into(), Value::from(hung));
}

/// 그 범위가 통 256개 안에 드는 가장 촘촘한 단계. 한 단계 아래는 256개를 넘으므로 이 단계의 통은 대개 64개를 넘는다.
fn summary_level(lo: i64, hi: i64) -> usize {
    (0..=LEVEL_MAX)
        .find(|level| bucket_of(hi, *level) - bucket_of(lo, *level) + 1 <= TILE_BUCKETS)
        .unwrap_or(LEVEL_MAX)
}

impl Store {
    pub fn layout(&self) -> Result<Value> {
        let meta_json = |key: &str| -> Value {
            self.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0))
                .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_else(|| Value::Object(Map::new()))
        };
        let counts = meta_json("pack_events");
        // 자료집별 띠 수 · 닿는 트랙(남의 트랙에 얹은 것까지 — 옛 저장소에는 없어 0 · 빈 목록). DLC 관리 카드가 "사건 0건 · 트랙 없음" 대신 담긴 것을 적는 근거.
        let periods = meta_json("pack_periods");
        let touches = meta_json("pack_tracks");
        // DLC의 글자 id(`meta.pack_keys` — 가져오기가 남긴다). 옛 저장소에는 없어 빈 글이다.
        let keys: Value = self.db.query_row("SELECT value FROM meta WHERE key='pack_keys'", [], |r| r.get::<_, String>(0))
            .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_else(|| Value::Object(Map::new()));
        // DLC마다 판 · 분류(`meta.pack_info` — 가져오기가 남긴다. 옛 저장소에는 없어 빈 글이다).
        let info = meta_json("pack_info");
        let mut packs = Vec::new();
        // `original`: 원본 팩(.htpack)을 저장소에 품었으면 1. 원본 없이 넣은 DLC(Node 없이 .htlayout만 받은 것)는 0 —
        // DLC 관리 카드의 '원본 없음'이다 — 엔진의 넣고 빼기(`add_pack` · `remove_pack`)는 원본 없는 DLC가 새 조합에 남으면 `code` original로 거절하고
        // 앱은 그 DLC의 .htpack을 함께 고르라고 알린다(계약 2-7-1 · 설계 A 5-4 다 — 예전 Node 다시 짓기 길은 걷었다).
        for row in self.db.prepare("SELECT id,name,original IS NOT NULL FROM packs ORDER BY id")?
            .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, bool>(2)?)))? {
            let (id, name, original) = row?;
            let n = id.to_string();
            packs.push(json!({"id":id,"name":name,"events":counts[&n].as_i64().unwrap_or(0),"key":keys[&n].as_str().unwrap_or(""),
                "periods":periods[&n].as_i64().unwrap_or(0),"touches":touches[&n].as_array().cloned().unwrap_or_default(),
                "version":info[&n]["version"].as_str().unwrap_or(""),"category":info[&n]["category"].as_str().unwrap_or(""),"original":i64::from(original)}));
        }
        let mut tracks: Vec<Value> = Vec::new();
        // `key`는 트랙의 글자 id(`mw-coast`) — 항목 기록(entities)의 `track`이 이 글자라, 대범위 칩이 제 트랙을 찾는다.
        // `sphere`는 트랙이 든 문화권의 글자 id(리메이크 조각 ②) — 열이 없는 옛 저장소 · 판 트랙은 빈 글자다.
        let sphere_column = if self.track_sphere { "sphere" } else { "''" };
        // 트랙 차례는 `RowMap::load`와 같다(`ord`가 같으면 번호) — 줄 자리가 이 차례로 이어진다.
        for row in self.db.prepare(&format!("SELECT id,pack,ord,name,color,dynasty,leader,cabinet,organ,rail_levels,key,{sphere_column} FROM tracks ORDER BY ord,id"))?
            .query_map([], |r| Ok(json!({"id":r.get::<_,i64>(0)?,"pack":r.get::<_,i64>(1)?,"ord":r.get::<_,i64>(2)?,"name":r.get::<_,String>(3)?,
                "color":r.get::<_,i64>(4)?,"dynasty":r.get::<_,i64>(5)?,"leader":r.get::<_,i64>(6)?,"cabinet":r.get::<_,i64>(7)?,"organ":r.get::<_,i64>(8)?,
                "rail_levels":r.get::<_,i64>(9)?,"key":r.get::<_,String>(10)?,"sphere":r.get::<_,String>(11)?,"rows":[],"groups":[]})))? {
            tracks.push(row?);
        }
        // 문화권 목록(`meta.spheres` — 가져오기가 배치의 최상위 `spheres`를 그대로 남긴다). 없는 저장소는 빈 목록이다.
        let spheres: Value = self.db.query_row("SELECT value FROM meta WHERE key='spheres'", [], |r| r.get::<_, String>(0))
            .ok().and_then(|text| serde_json::from_str::<Value>(&text).ok()).filter(Value::is_array).unwrap_or_else(|| json!([]));
        // P3-18 — 트랙의 문화권 자리 `sphere_at`(최상위 `spheres` 목록에서의 자리 · 문화권 밖이거나 모르는 id면 −1) — 앱이 하던 찾기.
        let sphere_ids: Vec<String> = spheres.as_array().map(|list| list.iter().map(|x| x["id"].as_str().unwrap_or("").to_string()).collect()).unwrap_or_default();
        for track in tracks.iter_mut() {
            let id = track["sphere"].as_str().unwrap_or("");
            let at = if id.is_empty() { -1 } else { sphere_ids.iter().position(|x| x == id).map_or(-1, |p| p as i64) };
            track["sphere_at"] = Value::from(at);
        }
        let at: std::collections::HashMap<i64, usize> = tracks.iter().enumerate().map(|(i, t)| (t["id"].as_i64().unwrap(), i)).collect();
        let variant_column = if self.has_variants { "variant" } else { "0" };
        let mut stmt = self.db.prepare(&format!("SELECT track,id,height,band_top,band_h,dyn_top,lead_top,cab_top,text_top,text_lines,rail_top,organ_top,\
            kind,group_start,scope_pad,phase,rank,cats,fig,dep,zones,hem,fig_wide,{variant_column} FROM rows ORDER BY id"))?;
        let rows = stmt.query_map([], |r| {
            let cats: String = r.get(17)?;
            let (scope_pad, zones, fig_wide) = (r.get::<_, i64>(14)?, r.get::<_, i64>(20)?, r.get::<_, i64>(22)?);
            let mut geo = json!({"id":r.get::<_,i64>(1)?,"height":r.get::<_,i64>(2)?,"band_top":r.get::<_,i64>(3)?,"band_h":r.get::<_,i64>(4)?,
                "dyn_top":r.get::<_,i64>(5)?,"lead_top":r.get::<_,i64>(6)?,"cab_top":r.get::<_,i64>(7)?,"text_top":r.get::<_,i64>(8)?,
                "text_lines":r.get::<_,i64>(9)?,"rail_top":r.get::<_,i64>(10)?,"organ_top":r.get::<_,i64>(11)?,
                "kind":r.get::<_,i64>(12)?,"group_start":r.get::<_,i64>(13)?,"scope_pad":scope_pad,"phase":r.get::<_,i64>(15)?,
                "rank":r.get::<_,i64>(16)?,"cats":serde_json::from_str::<Value>(&cats).unwrap_or_else(|_| json!([])),
                "fig":r.get::<_,i64>(18)?,"fig_wide":fig_wide,"dep":r.get::<_,i64>(19)?,"zones":zones,"hem":r.get::<_,i64>(21)?,
                "variant":r.get::<_,i64>(23)?});
            // P3-18 — 앱이 다시 가르던 정적인 값(줄 깃발 · 그릇 머리 · 발 · 매달림 수)을 여기서 풀어 함께 싣는다.
            let geo_map = geo.as_object_mut().unwrap();
            add_row_flags(geo_map, fig_wide, zones);
            add_scope_split(geo_map, scope_pad);
            Ok((r.get::<_, i64>(0)?, geo))
        })?;
        for row in rows {
            let (track, geo) = row?;
            let index = *at.get(&track).ok_or("줄이 가리키는 트랙이 없습니다")?;
            tracks[index]["rows"].as_array_mut().unwrap().push(geo);
        }
        let mut group_stmt = self.db.prepare("SELECT track,depth,first_row,row_count,name,color,kind FROM groups ORDER BY id")?;
        let groups = group_stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, json!({"depth":r.get::<_,i64>(1)?,"first":r.get::<_,i64>(2)?,"count":r.get::<_,i64>(3)?,
            "name":r.get::<_,String>(4)?,"color":r.get::<_,i64>(5)?,"kind":r.get::<_,i64>(6)?}))))?;
        for row in groups {
            let (track, group) = row?;
            let index = *at.get(&track).ok_or("묶음이 가리키는 트랙이 없습니다")?;
            tracks[index]["groups"].as_array_mut().unwrap().push(group);
        }
        let mut categories = Vec::new();
        for row in self.db.prepare("SELECT id,key,name,color FROM categories ORDER BY ord,id")?
            .query_map([], |r| Ok(json!({"id":r.get::<_,i64>(0)?,"key":r.get::<_,String>(1)?,"name":r.get::<_,String>(2)?,"color":r.get::<_,i64>(3)?})))? {
            categories.push(row?);
        }
        let mut epochs = Vec::new();
        for row in self.db.prepare("SELECT id,pack,start,end,color,name FROM epochs ORDER BY start,id")?
            .query_map([], |r| Ok(json!({"id":r.get::<_,i64>(0)?,"pack":r.get::<_,i64>(1)?,"start":r.get::<_,i64>(2)?,"end":r.get::<_,i64>(3)?,"color":r.get::<_,i64>(4)?,"name":r.get::<_,String>(5)?})))? {
            epochs.push(row?);
        }
        // 날짜 칸은 줄이 아니라 칸의 목록이다(공통 줄이면 track 0). 시작 순.
        let mut axis = Vec::new();
        for row in self.db.prepare("SELECT kind,track,lane,start,end,name,color,style,strip,seq FROM axis_cells ORDER BY start,id")?
            .query_map([], |r| Ok(json!([r.get::<_,i64>(0)?, r.get::<_,Option<i64>>(1)?.unwrap_or(0), r.get::<_,i64>(2)?, r.get::<_,i64>(3)?, r.get::<_,i64>(4)?,
                r.get::<_,String>(5)?, r.get::<_,i64>(6)?, r.get::<_,i64>(7)?, r.get::<_,i64>(8)?, r.get::<_,i64>(9)?])))? {
            axis.push(row?);
        }
        let sphere_lines = self.sphere_lines()?;
        let mut answer = json!({"packs":packs,"tracks":tracks,"spheres":spheres,"categories":categories,"epochs":epochs,"axis":axis,"variants":self.variant_layout()?,
            "sphereLines":sphere_lines});
        self.outward_layout(&mut answer);
        Ok(answer)
    }

    /// 문화권 단위 줄(스키마 4 · 계약 1-1 `sphere_lines`) — layout 답 맨 위 `sphereLines`. 표 전부 · id 차례(앞뒤 차례도 약속이다 — 배치 차례 그대로).
    /// 원소 `{id, pack, sphere, kind, start, end, name, uid, color, data}`: `pack`은 저장소의 자료집 번호(`packs[].id` — `epochs`의 `pack`과 같은 뜻),
    /// `data`는 표의 글 그대로(사람 띠의 왕관 목록 · 주기 줄의 설정 JSON 글 · 없으면 빈 글 — 푸는 것은 읽는 쪽). 줄 · 띠를 가리키는 번호가 없어
    /// 열쇠 ≠ 자리 저장소에서도 바꿀 것이 없다(`outward_layout` 밖). 수가 적어(사람 띠는 왕관 둘 이상인 사람만) 통째로 답한다.
    /// 표가 없는 옛 저장소(판 '3' · '3.1')는 빈 목록(`spheres`가 없을 때와 같은 꼴).
    fn sphere_lines(&self) -> Result<Vec<Value>> {
        if !self.has_sphere_lines {
            return Ok(Vec::new());
        }
        let mut out = Vec::new();
        for row in self.db.prepare("SELECT id,pack,sphere,kind,start,end,name,uid,color,data FROM sphere_lines ORDER BY id")?
            .query_map([], |r| Ok(json!({"id":r.get::<_,i64>(0)?,"pack":r.get::<_,i64>(1)?,"sphere":r.get::<_,String>(2)?,"kind":r.get::<_,i64>(3)?,
                "start":r.get::<_,i64>(4)?,"end":r.get::<_,i64>(5)?,"name":r.get::<_,String>(6)?,"uid":r.get::<_,String>(7)?,"color":r.get::<_,i64>(8)?,
                "data":r.get::<_,String>(9)?})))? {
            out.push(row?);
        }
        Ok(out)
    }

    /// layout 답의 줄을 밖으로(계획 P4): 위에서 지은 답은 줄 열쇠로 말한다 — 트랙의 줄 `id` · 묶음의 `first`를 자리로 바꾼다.
    /// 트랙 하나의 줄은 이어진 덩이라 열쇠 차례(`ORDER BY id`)가 곧 자리 차례다. 변형의 줄 쌓기는 `variant_layout`이 자리로 낸다.
    /// 리메이크가 줄을 가리키는 열을 더하면 여기에 이름을 더한다. 열쇠 = 자리면 아무것도 하지 않는다.
    fn outward_layout(&self, answer: &mut Value) {
        for track in answer["tracks"].as_array_mut().into_iter().flatten() {
            self.rows.outward(&mut track["rows"], &["id"]);
            self.rows.outward(&mut track["groups"], &["first"]);
        }
    }

    /// 왼쪽 줄 이름 칸이 쓰는 후보 띠들(계약 6-8절). 줄마다 시작 순으로 모아 준다.
    /// `at`(보는 때)은 아직 쓰지 않는다 — 어느 띠를 고르는지는 화면 쪽이 6-8절대로 정한다.
    /// `rows`는 **자리**(밖으로 보이는 줄 번호)이고 답의 `row`도 받은 자리 그대로다 — 저장소 안은 열쇠라 줄마다 열쇠로 바꿔 찾는다(계획 P4).
    /// 없는 자리는 열쇠 −1이 되어 이름이 없다(예전에도 없는 줄은 빈 목록이었다).
    pub fn row_labels(&self, rows: &[i64], filter: Option<&crate::filter::Filtered>, variants: Option<&crate::variant::Variants>) -> Result<Value> {
        let mut stmt = self.db.prepare_cached("SELECT json,period FROM row_labels WHERE row=?1 ORDER BY start,rowid")?;
        // 변형: 켜지 않은 변형의 줄은 이름이 없다(그 줄 자체가 없는 것과 같다). 줄 열쇠의 모음이다.
        let off = self.rows_off(variants)?;
        let mut out = Vec::with_capacity(rows.len());
        for row in rows {
            let key = self.rows.key(*row);
            let mut items = Vec::new();
            // 거르개: 꺼진 트랙의 줄은 이름이 없고, 꺼진 띠는 후보에서 빠진다(거른 뒤의 자료로 이름 자리가 정해지게).
            if !filter.is_some_and(|f| f.row_off(key)) && !off.contains(&key) {
                let mut got = stmt.query([key])?;
                while let Some(r) = got.next()? {
                    if filter.is_some_and(|f| f.band_off(r.get(1).unwrap_or(0))) {
                        continue;
                    }
                    let text: String = r.get(0)?;
                    items.push(serde_json::from_str::<Value>(&text).unwrap_or(Value::String(text)));
                }
            }
            out.push(json!({"row":row,"items":items}));
        }
        Ok(json!({"labels":out}))
    }

    /// 상세 창이 읽는 항목 기록. 넣을 때 정규화한 글자 그대로 돌려준다.
    /// 항목 기록 하나. 공동 사건의 **둘째 자리**(`…#1`)와 여러 줄에 깔린 바탕 문화(`…#u3`)는 제 기록이 없고
    /// 밑동(`#` 앞)의 기록을 함께 쓴다 — 그대로 찾지 못하면 밑동으로 한 번 더 찾는다(계약 6-1 · 6-6).
    pub fn entity(&self, uid: &str) -> Result<Value> {
        let mut stmt = self.db.prepare_cached("SELECT kind,json FROM entities WHERE uid=?1")?;
        let mut got = stmt.query_map([uid], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        let found = match got.next() {
            Some(row) => Some(row?),
            None => match crate::query::uid_stem(uid) {
                Some(stem) => self.db.query_row("SELECT kind,json FROM entities WHERE uid=?1", [stem], |r| Ok((r.get(0)?, r.get(1)?))).ok(),
                None => None,
            },
        };
        let (kind, json) = found.ok_or_else(|| format!("그 이름의 항목 기록이 없습니다: {uid}"))?;
        Ok(json!({"uid":uid,"kind":kind,"json":json}))
    }

    /// 그 범위에 내용이 있는 줄(오름차순 · 중복 없음). 켠 자료집만 본다.
    /// 띠는 공간 색인(시작 · 끝 미정인 쪽은 fade분만큼 넓혀서), 사건은 단계별 요약(촘촘하면 덮는 색인), 긴 기간은 기간 색인.
    /// 바탕 문화(띠의 look · sub로 표시된 것)의 값의 뜻은 계약 6절을 내보내기 담당이 채우는 중이라,
    /// 지금은 '띠가 있는 줄'에 함께 들어간다 — 뜻이 정해지면 그 표시를 가진 띠가 깔리는 줄들까지 더한다.
    /// 켜지 않은 변형의 줄(그 줄은 아예 없는 것과 같다). 줄 **열쇠**의 모음이다 — 안에서만 쓰고, 밖으로 낼 때 자리로 바꾼다(계획 P4).
    pub fn rows_off(&self, variants: Option<&crate::variant::Variants>) -> Result<std::collections::HashSet<i64>> {
        let mut out = std::collections::HashSet::new();
        let Some(v) = variants else { return Ok(out) };
        let keep = v.keep("variant");
        let mut stmt = self.db.prepare(&format!("SELECT id FROM rows WHERE NOT (1=1{keep})"))?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            out.insert(r.get(0)?);
        }
        Ok(out)
    }

    pub fn rows_near(&self, lo: i64, hi: i64, fade: i64, packs: &[i64], filter: Option<&crate::filter::Filtered>, variants: Option<&crate::variant::Variants>) -> Result<Vec<i64>> {
        if hi < lo {
            return Err("조회 범위 오류".into());
        }
        let fade = fade.max(0);
        let mut found: BTreeSet<i64> = BTreeSet::new();
        if packs.is_empty() {
            return Ok(Vec::new());
        }
        let list = serde_json::to_string(packs)?;
        let (wide_lo, wide_hi) = (lo.saturating_sub(fade), hi.saturating_add(fade));
        let day = |minute: i64| minute.div_euclid(DAY).clamp(i32::MIN as i64, i32::MAX as i64);
        // 거르개: 거른 뒤에 아무것도 없는 줄은 '내용이 없는 줄'이라 접힌다(가까운 쪽에도 먼 쪽에도 없다).
        let band_keep = filter.map(|f| f.band_keep("p")).unwrap_or_default();
        let event_keep = filter.map(|f| f.event_keep("e")).unwrap_or_default();
        // 변형: 켠 것만 보고, 이사한 띠 · 사건은 도착한 줄에 내용이 있다고 답한다(떠난 줄은 비면 접힌다).
        let band_vary = variants.map(|v| v.keep("p.variant")).unwrap_or_default();
        let event_vary = variants.map(|v| v.keep("e.variant")).unwrap_or_default();
        let moving = variants.is_some_and(|v| !v.bands.is_empty() || !v.events.is_empty());
        {
            let column = if moving { "p.id,p.row" } else { "p.row,p.row" };
            let sql = format!("SELECT DISTINCT {column} FROM period_bounds b JOIN periods p ON p.id=b.id \
                WHERE b.lo_day<=?1 AND b.hi_day>=?2 \
                AND p.start-(CASE WHEN p.fuzzy&1 THEN ?3 ELSE 0 END)<=?4 AND p.end+(CASE WHEN p.fuzzy&2 THEN ?3 ELSE 0 END)>=?5 \
                AND p.pack IN (SELECT value FROM json_each(?6)){band_keep}{band_vary}");
            let mut stmt = self.db.prepare_cached(&sql)?;
            let mut rows = stmt.query(rusqlite::params![day(wide_hi), day(wide_lo), fade, hi, lo, list])?;
            while let Some(r) = rows.next()? {
                let (id, row): (i64, i64) = (r.get(0)?, r.get(1)?);
                found.insert(match variants {
                    Some(v) if moving => v.band_row(id, row),
                    _ => row,
                });
            }
        }
        {
            let column = if moving { "e.id,e.lane,e.band" } else { "e.lane,e.lane,e.lane" };
            let sql = format!("SELECT DISTINCT {column} FROM span_bounds b JOIN events e ON e.id=b.id \
                WHERE b.lo_day<=?1 AND b.hi_day>=?2 AND e.start<=?3 AND e.end>=?4 AND e.pack IN (SELECT value FROM json_each(?5)){event_keep}{event_vary}");
            let mut stmt = self.db.prepare_cached(&sql)?;
            let mut rows = stmt.query(rusqlite::params![day(hi), day(lo), hi, lo, list])?;
            while let Some(r) = rows.next()? {
                let (id, lane, band): (i64, i64, i64) = (r.get(0)?, r.get(1)?, r.get(2)?);
                found.insert(match variants {
                    Some(v) if moving => v.event_row(id, band, lane),
                    _ => lane,
                });
            }
        }
        let level = summary_level(lo, hi);
        // 미리 셈해 둔 요약은 거르기 전의 수다 — 사건에 걸리는 거르개가 있으면 덮는 색인을 줄마다 짚는다.
        let recount = filter.is_some_and(crate::filter::Filtered::counts_events) || variants.is_some_and(|v| !v.is_plain());
        if level >= PRE_MIN && !recount {
            let mut stmt = self.db.prepare_cached("SELECT DISTINCT lane FROM summaries WHERE level=?1 AND bucket BETWEEN ?2 AND ?3 AND pack IN (SELECT value FROM json_each(?4))")?;
            let mut rows = stmt.query(rusqlite::params![level as i64, bucket_of(lo, level), bucket_of(hi, level), list])?;
            while let Some(r) = rows.next()? {
                found.insert(r.get(0)?);
            }
        } else {
            // 촘촘한 범위는 요약이 없다. 줄마다 덮는 색인을 한 번씩만 짚는다(사건 표는 읽지 않는다).
            // 줄은 열쇠로 돈다 — 트랙 덩이마다(열쇠 = 자리면 0부터 전체 줄 수까지 차례로 — 예전과 같다).
            let keys = || self.rows.blocks().iter().flat_map(|b| b.key0..b.key0 + b.n);
            let off = self.rows_off(variants)?;
            if moving {
                // 이사가 걸리면 '어느 줄에 있는가'가 사건마다 달라진다 — 줄마다 있고 없음만 묻지 않고 번호를 받아 옮긴다.
                let sql = format!("SELECT e.id,e.lane,e.band FROM events e INDEXED BY events_time WHERE e.lane=?1 AND e.start BETWEEN ?2 AND ?3 AND e.pack IN (SELECT value FROM json_each(?4)){event_keep}{event_vary}");
                let mut stmt = self.db.prepare_cached(&sql)?;
                let v = variants.expect("이사가 있으면 변형이 있다");
                for lane in keys() {
                    if off.contains(&lane) || filter.is_some_and(|f| f.row_off(lane)) {
                        continue;
                    }
                    let mut got = stmt.query(rusqlite::params![lane, lo, hi, list])?;
                    while let Some(r) = got.next()? {
                        found.insert(v.event_row(r.get(0)?, r.get(2)?, lane));
                    }
                }
            } else {
                let sql = format!("SELECT 1 FROM events e INDEXED BY events_time WHERE e.lane=?1 AND e.start BETWEEN ?2 AND ?3 AND e.pack IN (SELECT value FROM json_each(?4)){event_keep}{event_vary} LIMIT 1");
                let mut stmt = self.db.prepare_cached(&sql)?;
                for lane in keys() {
                    if found.contains(&lane) || off.contains(&lane) {
                        continue;
                    }
                    if filter.is_some_and(|f| f.row_off(lane)) {
                        continue;
                    }
                    if stmt.exists(rusqlite::params![lane, lo, hi, list])? {
                        found.insert(lane);
                    }
                }
            }
        }
        // 켜지 않은 변형의 줄은 아예 없는 것과 같다(이사해 온 것이 없는 한 답에 들 일도 없지만, 한 번 걸러 둔다).
        if variants.is_some() {
            let off = self.rows_off(variants)?;
            found.retain(|row| !off.contains(row));
        }
        // 위에서는 줄 열쇠로 모았다 — 답은 자리(오름차순). 열쇠 = 자리면 그대로.
        if self.rows.is_identity() {
            return Ok(found.into_iter().collect());
        }
        let mut out: Vec<i64> = found.into_iter().map(|key| self.rows.pos(key)).filter(|p| *p >= 0).collect();
        out.sort_unstable();
        Ok(out)
    }

    /// `{"op":"rows_near","near":[lo,hi],"far":[lo,hi],"fade":분,"packs":[…]}`
    pub fn rows_near_call(&self, q: &Value) -> Result<Value> {
        let fade = q["fade"].as_i64().unwrap_or(0);
        let packs: Vec<i64> = q["packs"].as_array().map(|list| list.iter().filter_map(Value::as_i64).collect()).unwrap_or_default();
        let filter = self.filter_of(q)?;
        let variants = self.variants_of(q)?;
        let range = |key: &str| -> Result<Vec<i64>> {
            match q[key].as_array() {
                Some(pair) if pair.len() == 2 => {
                    let (lo, hi) = (pair[0].as_i64().ok_or("범위의 값이 정수가 아닙니다")?, pair[1].as_i64().ok_or("범위의 값이 정수가 아닙니다")?);
                    self.rows_near(lo, hi, fade, &packs, filter.as_ref(), variants.as_ref())
                }
                Some(_) => Err("범위는 [시작, 끝] 두 값입니다".into()),
                None => Ok(Vec::new()),
            }
        };
        Ok(json!({"near":range("near")?,"far":range("far")?}))
    }
}

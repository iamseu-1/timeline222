//! 같음의 눈(계획 P4 과제 1b) — 저장소의 답을 **번호(id) 없이** uid · 열쇠 · 내용으로 적은 한 묶음.
//! 띠 · 사건 · 칸 · 항목 · 트랙 · 자료집 · 변형의 번호는 지을 때마다(통째로 지은 것 · 트랙만 고쳐 쓴 것) 달라질 수 있어,
//! 두 저장소의 답을 그대로 견주면 같은 것도 다르게 보인다. 이 묶음이 같으면 '어떤 차례로 넣고 빼도 그 조합을 통째로 지은 것과
//! 같다'(계획 P4의 약속)를 잰 것이다. 검사 도구다 — 앱 · FFI는 부르지 않는다.
//!
//! 담는 것:
//! - `layout`: `{"op":"layout"}` 답. 자료집 `id` → 자료집 글자 id(없으면 이름 · 첫째(기본 DLC) 뒤는 글자 id 차례로 — 판정 R20), 트랙 `id` → 트랙 열쇠(`tracks.key`, 비면
//!   `n:<자료집 글자 id>|<이름>`), `pack` → 자료집 글자 id, `touches` → 트랙 열쇠(글자 차례), 변형 번호 → 변형 열쇠,
//!   변형의 상위 띠 → 띠 uid, 날짜 칸의 트랙 → 트랙 열쇠. 줄은 답 그대로(밖으로 보이는 자리) — 줄의 `id`는 `pos`로 이름만 바꾼다.
//!   번호 말고는 뜻이 없는 `id`(분류 · 시대 구분 · 변형 · 문화권 단위 줄 `sphereLines`)는 뺀다 — `sphereLines`의 `pack`도 글자 id로, 차례는 답 그대로(id 차례).
//!   트랙의 `ord`는 차례(0부터)로 — 앱은 그 차례로만 쓴다. 타일의 띠는 형식 4의 뜻 `form`(스키마 4 — 열이 없으면 0)까지 적는다.
//!   차례가 번호에 기대는 목록(시대 구분 · 날짜 칸의 같은 시작 · 변형)은 내용으로 다시 늘어놓는다.
//! - `views`: 보기마다(모든 자료집을 켜고 · 변형 없음 / 변형 하나씩 — 이사 · 가리기는 변형을 켜야 타일에 드러난다) 단계 `levels`마다 ·
//!   줄 묶음 `0..ceil(전체 줄/8)`마다 · 가로 타일 = 그 단계에서 `meta.min ~ max`를 덮는 열(많으면 고르게 `max_x`개)
//!   ∪ 띠 · 칸 · 사건 · 일반 항목의 시작 · 끝이 놓인 열(내용으로 정해짐 — 촘촘한 단계에서도 자료가 있는 곳을 다 본다)을 풀어
//!   띠 → 띠 uid · 사건 → 사건 uid(든 띠도 uid) · 칸 → `[띠 uid, kind, lane, 시작]` · 일반 항목 → `[구역, ref의 uid, 시작, 끝,
//!   이름, a, b, c, d, text2]`로 바꿔 적는다. `a` ~ `d` 가운데 띠 번호를 싣는 칸(`bandref`)은 띠 uid로(0은 0).
//!   글자는 글자표 번호가 아니라 글 그대로. 구역 · 항목은 내용으로 정렬한다
//!   (바이트 · 글자표 차례 · 같은 자리의 번호 차례는 견주지 않는다). 빈 타일은 싣지 않는다.
//! - `queries`(`CanonOpts.queries`일 때 — 과제 2): 조회 명령의 답. 물음은 내용으로 고른다(띠 · 사건은 uid 차례에서 고르게 셋,
//!   시각은 `meta.min ~ max`를 넷으로 나눈 자리 셋, 낱말은 저장소 내용 — 사건 제목 · 띠 · 칸 이름의 낱말 가운데 엔진에 물어 한 쪽을 넘지 않는 것
//!   (5d 얹힌 몫 8 — 장면 상수는 실자료에서 0건일 수 있다)). 보기는 '기본' · 변형 하나씩 · 첫 트랙을 끈 거르개.
//!   `rows_near`(시각 셋) · `row_labels`(줄 전부) · `events_in`(트랙마다 줄 하나하나 · 고른 띠) · `same_year`(사건 셋) · `echo`(띠 셋) ·
//!   `search`(사건 제목의 낱말 셋 · 이름까지 찾는 `kinds`의 낱말 둘) · `variant_views`(변형 하나씩 켠 보기마다 고른 띠의 `events_in` · `same_year` ·
//!   `echo` · `search` — 변형의 이사 · 옮겨 적은 줄에 기대는 답) · `search_words`(고른 낱말 수 — 넓힌 검색 낱말은 옛 검색 낱말과 겹치지 않게 고른다) ·
//!   `search_plain`(거르개를 건 옛 검색) · `list`(보기마다 쪽 둘 — 시작 차례) ·
//!   `event`(셋) · `id_of` · `uid_of` · `ids_of` · `cells_of`(띠 셋) · `scopes` · `entity`(전부) · `range`(줄 묶음마다) ·
//!   `verify_store`(표본 200의 누락 · 중복) · `info`(수 세기 · `min` · `max` · 자료집별 수는 글자 id로).
//!   답의 번호는 layout · 타일과 같은 규칙으로 바꾼다 — 사건 → uid · 띠 → uid · 칸 → `[띠 uid, kind, lane, 시작]` · 트랙 → 열쇠 ·
//!   자료집 → 글자 id · 출처 → 제목 · 줄 이름 원소 JSON 안의 `track`(배치 트랙 순번) → 그 줄의 트랙 열쇠(판정 R17).
//!   줄(`row` · `lane`)은 답 그대로(밖으로 보이는 자리)다. 차례는 엔진이 낸 그대로 둔다 —
//!   엔진이 번호 대신 넣은 차례로 동률을 깨는 곳(타일 대표 — 판정 R9 · R23 · `same_year`의 사건 — 판정 R67: (트랙 차례, 트랙 안 사건 차례 `events.ord`))은
//!   고쳐 쓴 저장소에서도 통째 짓기와 같아 그대로 견준다. 번호로만 갈리는 차례는 계약 밖이라(판정 R12 · 계약 2-1 `same_year`의 띠 · 칸 · 인물 —
//!   시작이 같으면 번호 차례) 실자료에서 갈린 것만 내용 차례로 늘어놓는다(과제 7b): `echo`의 같은 자리 묶음(R28) · `range`(번호 차례로만 내는 옛 줄
//!   범위 조회). `same_year`의 띠 동률은 아직 갈린 적이 없어 그대로다(과제 perf 검토 Minor 2 — 갈리면 여기서 (시작, uid)로).
//!
//! 줄 열쇠와 자리가 갈린 저장소(`RowMap`이 열쇠 ≠ 자리)에서도 돈다 — 줄 묶음의 수는 자리의 수로 세고, 줄 값은 답이 준 그대로 적는다.
//!
//! 값: 타일 하나를 뜨는 데 작은 저장소에서도 1ms 남짓이라 시간은 (1 + 변형 수) × 단계 × 가로 열 × 줄 묶음에 비례한다.
//! 가로 열은 촘촘한 단계일수록 자료가 놓인 열만큼 는다(사건 수에 가깝다). 자주 견주는 검사는 단계를 줄여 쓴다.
use crate::bandref::band_fields;
use crate::levels::{tile_of, CHUNK_ROWS, LEVEL_MAX};
use crate::tile::{build_tile, decode, Decoded, TileRequest, NO_NAME};
use crate::verify::{all_packs, meta_int};
use crate::{Result, Store};
use serde_json::{json, Map, Value};
use std::collections::{BTreeSet, HashMap};
use std::path::Path;

/// 무엇을 얼마나 적을지.
pub struct CanonOpts {
    /// 타일을 뜰 단계(0 ~ 14).
    pub levels: Vec<usize>,
    /// 단계마다 가로 타일을 이만큼까지(넘으면 `meta.min ~ max`에서 고르게 고른다). 0이면 타일을 뜨지 않는다.
    pub max_x: usize,
    /// 조회 목록의 답도 적을지(과제 2).
    pub queries: bool,
}

/// 저장소를 열어 번호 없이 적은 답 묶음을 만든다.
pub fn canon_store(path: &Path, o: &CanonOpts) -> Result<Value> {
    let store = Store::open(path)?;
    let mut names = Names::read(&store)?;
    let layout = canon_layout(store.layout()?, &mut names)?;
    let views = canon_views(&store, &mut names, o)?;
    let mut out = json!({"layout":layout,"views":views});
    if o.queries {
        out["queries"] = canon_queries(&store, &mut names)?;
    }
    Ok(out)
}

/// meta의 JSON 값(없거나 읽히지 않으면 빈 객체).
fn meta_json(store: &Store, key: &str) -> Value {
    store.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0))
        .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_else(|| Value::Object(Map::new()))
}

/// 번호 → 번호 없는 이름. 자료집 · 트랙 · 변형은 열 때 다 읽고, 띠 · 사건 · 칸 · 항목은 만난 것만 찾아 둔다.
struct Names<'a> {
    store: &'a Store,
    packs: HashMap<i64, String>,
    tracks: HashMap<i64, String>,
    variants: HashMap<i64, String>,
    periods: HashMap<i64, String>,
    events: HashMap<i64, String>,
    cells: HashMap<i64, Value>,
    /// 항목 번호 → (내용, ref_kind — 0 없음 · 1 띠 · 2 사건 · −1 그 열이 없는 옛 저장소).
    items: HashMap<i64, (Value, i64)>,
}

impl<'a> Names<'a> {
    fn read(store: &'a Store) -> Result<Self> {
        let keys = meta_json(store, "pack_keys");
        let mut packs = HashMap::new();
        {
            let mut stmt = store.db.prepare("SELECT id,name FROM packs")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
            for row in rows {
                let (id, name) = row?;
                let key = keys[&id.to_string()].as_str().unwrap_or("");
                packs.insert(id, if key.is_empty() { name } else { key.to_owned() });
            }
        }
        let mut tracks = HashMap::new();
        {
            let mut stmt = store.db.prepare("SELECT id,pack,key,name FROM tracks")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?)))?;
            for row in rows {
                let (id, pack, key, name) = row?;
                let key = if key.is_empty() { format!("n:{}|{name}", packs.get(&pack).map(String::as_str).unwrap_or("")) } else { key };
                tracks.insert(id, key);
            }
        }
        let mut variants = HashMap::new();
        if store.has_variants {
            let mut stmt = store.db.prepare("SELECT id,key FROM variants")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
            for row in rows {
                let (id, key) = row?;
                variants.insert(id, key);
            }
        }
        Ok(Self { store, packs, tracks, variants, periods: HashMap::new(), events: HashMap::new(), cells: HashMap::new(), items: HashMap::new() })
    }

    fn pack(&self, id: i64) -> Result<String> {
        self.packs.get(&id).cloned().ok_or_else(|| format!("없는 자료집을 가리킵니다: {id}").into())
    }

    /// 0은 '트랙 없음'(공통 날짜 칸)이라 빈 글.
    fn track(&self, id: i64) -> Result<String> {
        if id == 0 {
            return Ok(String::new());
        }
        self.tracks.get(&id).cloned().ok_or_else(|| format!("없는 트랙을 가리킵니다: {id}").into())
    }

    /// 조회 답의 트랙 번호 — 0 이하(트랙 없음 · 모름 −1)는 빈 글.
    fn track_any(&self, id: i64) -> Result<String> {
        if id <= 0 {
            return Ok(String::new());
        }
        self.track(id)
    }

    /// 출처 번호 → 제목.
    fn source(&self, id: i64) -> Result<String> {
        self.store.db.prepare_cached("SELECT title FROM sources WHERE id=?1")?
            .query_row([id], |r| r.get(0)).map_err(|_| format!("없는 출처를 가리킵니다: {id}").into())
    }

    /// 0은 '늘 있는 것'이라 빈 글.
    fn variant(&self, id: i64) -> Result<String> {
        if id == 0 {
            return Ok(String::new());
        }
        self.variants.get(&id).cloned().ok_or_else(|| format!("없는 변형을 가리킵니다: {id}").into())
    }

    /// 0은 '띠 없음'이라 빈 글.
    fn period(&mut self, id: i64) -> Result<String> {
        if id == 0 {
            return Ok(String::new());
        }
        if let Some(uid) = self.periods.get(&id) {
            return Ok(uid.clone());
        }
        let uid: String = self.store.db.prepare_cached("SELECT uid FROM periods WHERE id=?1")?
            .query_row([id], |r| r.get(0)).map_err(|_| format!("없는 띠를 가리킵니다: {id}"))?;
        self.periods.insert(id, uid.clone());
        Ok(uid)
    }

    fn event(&mut self, id: i64) -> Result<String> {
        if let Some(uid) = self.events.get(&id) {
            return Ok(uid.clone());
        }
        let uid: String = self.store.db.prepare_cached("SELECT uid FROM events WHERE id=?1")?
            .query_row([id], |r| r.get(0)).map_err(|_| format!("없는 사건을 가리킵니다: {id}"))?;
        self.events.insert(id, uid.clone());
        Ok(uid)
    }

    /// 칸 → `[띠 uid, kind, lane, 시작]`.
    fn cell(&mut self, id: i64) -> Result<Value> {
        if let Some(v) = self.cells.get(&id) {
            return Ok(v.clone());
        }
        let (uid, kind, lane, start): (String, i64, i64, i64) = self.store.db
            .prepare_cached("SELECT p.uid,c.kind,c.lane,c.start FROM cells c JOIN periods p ON p.id=c.period WHERE c.id=?1")?
            .query_row([id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map_err(|_| format!("없는 칸을 가리킵니다: {id}"))?;
        let v = json!([uid, kind, lane, start]);
        self.cells.insert(id, v.clone());
        Ok(v)
    }

    /// `ref`(띠 또는 사건 번호) → uid. `ref_kind`를 모르는 옛 저장소는 띠로 본다(가져오기가 띠를 먼저 찾는다).
    fn reference(&mut self, reference: i64, kind: i64) -> Result<String> {
        match (reference, kind) {
            (0, _) => Ok(String::new()),
            (_, 2) => self.event(reference),
            _ => self.period(reference),
        }
    }

    /// 일반 항목 → (`[구역, ref의 uid, 시작, 끝, 이름, a, b, c, d, text2]`, ref_kind).
    fn item(&mut self, id: i64) -> Result<(Value, i64)> {
        if let Some(v) = self.items.get(&id) {
            return Ok(v.clone());
        }
        let ref_kind = if self.store.item_ref_kind { "ref_kind" } else { "-1" };
        type Row = (i64, i64, i64, i64, i64, String, i64, i64, i64, i64, String);
        let row: Row = self.store.db
            .prepare_cached(&format!("SELECT section,ref,{ref_kind},start,end,name,a,b,c,d,text2 FROM items WHERE id=?1"))?
            .query_row([id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?, r.get(10)?)))
            .map_err(|_| format!("없는 일반 항목을 가리킵니다: {id}"))?;
        let (section, reference, kind, start, end, name, a, b, c, d, text2) = row;
        let uid = self.reference(reference, kind)?;
        let [a, b, c, d] = self.abcd(section, [a, b, c, d])?;
        let v = (json!([section, uid, start, end, name, a, b, c, d, text2]), kind);
        self.items.insert(id, v.clone());
        Ok(v)
    }

    /// 일반 항목의 `a` ~ `d` — 띠 번호를 싣는 칸([`crate::bandref::band_fields`])은 띠 uid로, 나머지는 수 그대로. 띠 번호 0('띠 없음')은 0.
    fn abcd(&mut self, section: i64, v: [i64; 4]) -> Result<[Value; 4]> {
        let mut out = v.map(Value::from);
        for at in band_fields(section, v[0], v[1], v[2], v[3]) {
            if v[at] != 0 {
                out[at] = json!(self.period(v[at])?);
            }
        }
        Ok(out)
    }
}

/// 값의 JSON 글 차례로 늘어놓는다(열쇠는 늘 글자 차례로 적히므로 같은 내용은 같은 글이다).
fn sort_by_text(list: &mut [Value]) {
    list.sort_by_cached_key(Value::to_string);
}

fn array_mut<'v>(v: &'v mut Value, key: &str) -> Option<&'v mut Vec<Value>> {
    v.get_mut(key).and_then(Value::as_array_mut)
}

fn int(v: &Value, key: &str) -> Result<i64> {
    v[key].as_i64().ok_or_else(|| format!("layout 답에 정수 {key}가 없습니다").into())
}

/// `{"op":"layout"}` 답의 번호를 열쇠 · uid로 바꾼다.
fn canon_layout(mut v: Value, n: &mut Names) -> Result<Value> {
    if let Some(packs) = array_mut(&mut v, "packs") {
        for p in packs.iter_mut() {
            p["id"] = json!(n.pack(int(p, "id")?)?);
            let mut touches = Vec::new();
            for t in p["touches"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
                touches.push(n.track(t.as_i64().ok_or("자료집이 닿는 트랙 번호가 정수가 아닙니다")?)?);
            }
            touches.sort();
            p["touches"] = json!(touches);
        }
        // 자료집 차례는 '기본 DLC가 첫째'만 약속이다(판정 R20 — `apply`는 새 자료집에 끝 번호를 준다 · 넣은 차례). 첫째는 두고 나머지는 글자 id 차례로.
        if packs.len() > 2 {
            packs[1..].sort_by_cached_key(|p| p["id"].as_str().unwrap_or("").to_owned());
        }
    }
    if let Some(tracks) = array_mut(&mut v, "tracks") {
        for (at, t) in tracks.iter_mut().enumerate() {
            t["id"] = json!(n.track(int(t, "id")?)?);
            t["pack"] = json!(n.pack(int(t, "pack")?)?);
            t["ord"] = json!(at);
            for r in array_mut(t, "rows").map(|l| l.iter_mut()).into_iter().flatten() {
                let row = r.as_object_mut().ok_or("줄이 객체가 아닙니다")?;
                let pos = row.remove("id").unwrap_or(Value::Null);
                row.insert("pos".to_owned(), pos);
                let variant = row.get("variant").and_then(Value::as_i64).unwrap_or(0);
                row.insert("variant".to_owned(), json!(n.variant(variant)?));
            }
        }
    }
    if let Some(categories) = array_mut(&mut v, "categories") {
        for c in categories.iter_mut().filter_map(Value::as_object_mut) {
            c.remove("id");
        }
    }
    if let Some(epochs) = array_mut(&mut v, "epochs") {
        for e in epochs.iter_mut() {
            e["pack"] = json!(n.pack(int(e, "pack")?)?);
            if let Some(e) = e.as_object_mut() {
                e.remove("id");
            }
        }
        epochs.sort_by_cached_key(|e| (e["start"].as_i64(), e.to_string()));
    }
    // 날짜 칸: [kind, track, lane, start, end, name, color, style, strip, seq] — track(0 = 공통 줄)만 번호다.
    if let Some(axis) = array_mut(&mut v, "axis") {
        for a in axis.iter_mut() {
            let track = a[1].as_i64().ok_or("날짜 칸의 트랙 번호가 정수가 아닙니다")?;
            a[1] = json!(n.track(track)?);
        }
        axis.sort_by_cached_key(|a| (a[3].as_i64(), a.to_string()));
    }
    if let Some(variants) = array_mut(&mut v, "variants") {
        for x in variants.iter_mut() {
            x["track"] = json!(n.track(int(x, "track")?)?);
            x["band"] = json!(n.period(int(x, "band")?)?);
            // 그릇의 포개짐 `within`(한 벌 P3-18)은 변형 번호 목록이라 열쇠로 바꾸고 정렬한다(고쳐 쓴 저장소는 번호가 달라도 열쇠는 같다).
            if let Some(ids) = x.get("within").and_then(Value::as_array).cloned() {
                let mut keys = Vec::with_capacity(ids.len());
                for id in &ids {
                    keys.push(n.variant(id.as_i64().ok_or("within의 변형 번호가 정수가 아닙니다")?)?);
                }
                keys.sort();
                x["within"] = json!(keys);
            }
            if let Some(x) = x.as_object_mut() {
                x.remove("id");
            }
        }
        variants.sort_by_cached_key(|x| x["key"].as_str().unwrap_or("").to_owned());
    }
    // 문화권 단위 줄(스키마 4 · 계약 1-1 `sphere_lines`): 자료집 번호 → 글자 id, 번호 말고는 뜻이 없는 `id`는 뺀다. 차례는 답 그대로(id 차례 —
    // 넣고 빼기는 이 표를 통째로 지우고 배치 차례대로 다시 넣으므로 차례도 통째 짓기와 같아야 한다 · 견줌에 든다).
    if let Some(lines) = array_mut(&mut v, "sphereLines") {
        for l in lines.iter_mut() {
            l["pack"] = json!(n.pack(int(l, "pack")?)?);
            if let Some(l) = l.as_object_mut() {
                l.remove("id");
            }
        }
    }
    Ok(v)
}

/// 자료가 놓인 분 — 띠 · 칸 · 사건(날짜 있는 것) · 일반 항목의 시작과 끝(오름차순 · 겹침 없음). 그 변형에서만 있는 것도 든다.
/// 내용으로만 정해지므로 같은 내용의 두 저장소에서 같다(번호 · 줄 열쇠와 무관).
fn content_minutes(store: &Store) -> Result<Vec<i64>> {
    let mut out = Vec::new();
    for sql in ["SELECT start,end FROM periods", "SELECT start,end FROM cells", "SELECT start,end FROM events WHERE start IS NOT NULL AND end IS NOT NULL",
        "SELECT start,end FROM items"] {
        let mut stmt = store.db.prepare(sql)?;
        let mut rows = stmt.query([])?;
        while let Some(r) = rows.next()? {
            out.push(r.get::<_, i64>(0)?);
            out.push(r.get::<_, i64>(1)?);
        }
    }
    out.sort_unstable();
    out.dedup();
    Ok(out)
}

/// 그 단계에서 뜰 가로 타일 번호(오름차순 · 겹침 없음) = `min ~ max`를 덮는 열에서 고르게 고른 것(`max_x`개를 넘으면 양 끝을 넣고 고르게)
/// ∪ 자료의 시작 · 끝이 놓인 열(`minutes`). 촘촘한 단계는 열이 수천 ~ 수만이라 고르게만 뜨면 사건이 거의 잡히지 않는다(판정 R10).
/// `max_x`가 0이면 타일을 뜨지 않는다.
fn columns(min: i64, max: i64, level: usize, max_x: usize, minutes: &[i64]) -> Vec<i64> {
    let (first, last) = (tile_of(min, level), tile_of(max, level));
    if max_x == 0 {
        return Vec::new();
    }
    let mut out: BTreeSet<i64> = minutes.iter().map(|m| tile_of(*m, level)).collect();
    if last >= first {
        let count = last - first + 1;
        let want = max_x as i64;
        if count <= want {
            out.extend(first..=last);
        } else if want == 1 {
            out.insert(first + (count - 1) / 2);
        } else {
            out.extend((0..want).map(|i| first + i * (count - 1) / (want - 1)));
        }
    }
    out.into_iter().collect()
}

/// 보기마다 타일을 떠서 풀어 적는다. 보기 = (켠 자료집, 켠 변형).
fn canon_views(store: &Store, n: &mut Names, o: &CanonOpts) -> Result<Vec<Value>> {
    if let Some(level) = o.levels.iter().find(|l| **l > LEVEL_MAX) {
        return Err(format!("타일 단계가 범위 밖입니다: {level}").into());
    }
    let (min, max) = (meta_int(store, "min")?, meta_int(store, "max")?);
    // 줄 묶음은 자리로 나뉜다 — 열쇠 ≠ 자리인 저장소에서도 자리의 수(= 전체 줄 수)로 센다.
    let chunks = (store.rows.total() + CHUNK_ROWS - 1) / CHUNK_ROWS;
    let packs = all_packs(store)?;
    let minutes = content_minutes(store)?;
    let mut keys: Vec<String> = n.variants.values().cloned().collect();
    keys.sort();
    let mut plans: Vec<(Vec<i64>, Vec<String>)> = vec![(packs.clone(), Vec::new())];
    plans.extend(keys.into_iter().map(|key| (packs.clone(), vec![key])));
    let mut out = Vec::with_capacity(plans.len());
    for (on, variants) in plans {
        let resolved = store.variants_of(&json!({ "variants": variants }))?;
        let mut tiles = Vec::new();
        for &level in &o.levels {
            for x in columns(min, max, level, o.max_x, &minutes) {
                for chunk in 0..chunks {
                    let req = TileRequest { level, x, chunk, packs: on.clone(), filter: None, variants: resolved.clone() };
                    let tile = decode(&build_tile(store, &req)?)?;
                    if let Some(v) = canon_tile(&tile, n)? {
                        tiles.push(v);
                    }
                }
            }
        }
        let mut labels = on.iter().map(|p| n.pack(*p)).collect::<Result<Vec<_>>>()?;
        labels.sort();
        out.push(json!({"packs":labels,"variants":variants,"tiles":tiles}));
    }
    Ok(out)
}

/// 글자표 번호 → 글(이름 없음은 null).
fn text(t: &Decoded, at: u32) -> Result<Value> {
    if at == NO_NAME {
        return Ok(Value::Null);
    }
    t.strings.get(at as usize).map(|s| json!(s)).ok_or_else(|| format!("타일 글자표 밖의 글자 번호: {at}").into())
}

/// 풀어 낸 타일 하나를 번호 없이 적는다. 아무것도 없는 타일은 None.
fn canon_tile(t: &Decoded, n: &mut Names) -> Result<Option<Value>> {
    if t.bands.is_empty() && t.cells.is_empty() && t.events.is_empty() && t.pills.is_empty() && t.sections.iter().all(|s| s.items.is_empty()) {
        return Ok(None);
    }
    let mut bands = Vec::with_capacity(t.bands.len());
    for b in &t.bands {
        bands.push(json!({"uid":n.period(i64::from(b.id))?,"x0":b.x0,"x1":b.x1,"color":b.color,"name":text(t, b.name)?,"row":b.row,"flags":b.flags,
            "look":b.look,"tag":text(t, b.tag)?,"sub":b.sub,"form":b.form}));
    }
    let mut cells = Vec::with_capacity(t.cells.len());
    for c in &t.cells {
        cells.push(json!({"cell":n.cell(i64::from(c.id))?,"x0":c.x0,"x1":c.x1,"name":text(t, c.name)?,"row":c.row,"kind":c.kind,"flags":c.flags,
            "lane":c.lane,"style":c.style,"color":c.color}));
    }
    let mut events = Vec::with_capacity(t.events.len());
    for e in &t.events {
        events.push(json!({"uid":n.event(i64::from(e.id))?,"x0":e.x0,"x1":e.x1,"name":text(t, e.name)?,"row":e.row,"bits":e.bits,"look":e.look,
            "label":text(t, e.label)?,"rail":e.rail,"band":n.period(i64::from(e.band))?}));
    }
    let mut pills = Vec::with_capacity(t.pills.len());
    for p in &t.pills {
        pills.push(json!({"x0":p.x0,"x1":p.x1,"count":p.count,"row":p.row,"cats":text(t, p.cats)?}));
    }
    let mut sections = Vec::with_capacity(t.sections.len());
    for s in t.sections.iter().filter(|s| !s.items.is_empty()) {
        let mut items = Vec::with_capacity(s.items.len());
        for it in &s.items {
            let (item, kind) = n.item(i64::from(it.id))?;
            let [a, b, c, d] = n.abcd(i64::from(s.kind), [it.a, it.b, it.c, it.d].map(i64::from))?;
            items.push(json!({"item":item,"ref":n.reference(i64::from(it.reference), kind)?,"x0":it.x0,"x1":it.x1,"name":text(t, it.name)?,
                "row":it.row,"flags":it.flags,"row2":it.row2,"color":it.color,"a":a,"b":b,"c":c,"d":d,"text2":text(t, it.text2)?}));
        }
        sort_by_text(&mut items);
        sections.push(json!({"kind":s.kind,"items":items}));
    }
    sections.sort_by_key(|s| s["kind"].as_u64());
    for list in [&mut bands, &mut cells, &mut events, &mut pills] {
        sort_by_text(list);
    }
    Ok(Some(json!({"level":t.level,"x":t.x,"chunk":t.chunk,"bands":bands,"cells":cells,"events":events,"pills":pills,"sections":sections})))
}

// ---- 조회 목록(과제 2) ----

/// 검색 낱말 후보로 삼는 낱말의 빈도 한도 — 그 낱말을 낱말로 품은 글이 이 수 이하인 것만(한 쪽을 넘지 않을 것 같은 것). 실제로 한 쪽을
/// 넘지 않는지는 엔진에 물어 확인한다([`search_words`]).
const WORD_HITS_MAX: usize = 40;

/// 조회 목록이 쓰는 검색 낱말(얹힌 몫 8 — 장면에 맞춘 상수는 실자료에서 0건일 수 있어 **저장소 내용**에서 고른다).
struct Words {
    /// 사건만 찾는 옛 검색(`search` — kinds 없음)의 낱말 셋 — 사건 제목의 낱말에서.
    plain: Vec<String>,
    /// 거르개(첫 트랙을 끔)를 건 옛 검색의 낱말 — 첫 트랙 밖의 사건이 잡히는 것.
    filtered: Option<String>,
    /// 이름까지 찾는 넓힌 검색(`kinds` 모두)의 낱말 — 띠 이름에서 하나 · 칸 이름에서 하나.
    wide: Vec<String>,
}

/// 글들을 빈칸으로 가른 낱말 → 그 낱말을 품은 글의 수(소문자 · 글자 차례).
fn word_counts(list: &[String]) -> std::collections::BTreeMap<String, usize> {
    let mut out = std::collections::BTreeMap::new();
    for text in list {
        let words: BTreeSet<String> = text.split_whitespace().map(str::to_lowercase).filter(|w| w.chars().count() <= 64).collect();
        for w in words {
            *out.entry(w).or_insert(0) += 1;
        }
    }
    out
}

/// 후보(글자 차례)에서 `at`(0 이상 1 이하의 자리)부터 차례로 훑어 `ok`인 첫 낱말(이미 고른 것은 건너뜀). 한 바퀴 돌아도 없으면 None.
fn pick_from(candidates: &[String], at: f64, taken: &[String], ok: &mut dyn FnMut(&str) -> Result<bool>) -> Result<Option<String>> {
    if candidates.is_empty() {
        return Ok(None);
    }
    let start = ((candidates.len() - 1) as f64 * at).round() as usize;
    for k in 0..candidates.len() {
        let word = &candidates[(start + k) % candidates.len()];
        if !taken.contains(word) && ok(word)? {
            return Ok(Some(word.clone()));
        }
    }
    Ok(None)
}

/// [`Words`]를 저장소 내용에서 고른다. 후보는 빈도가 1 ~ [`WORD_HITS_MAX`]인 낱말(글자 차례)이고, 엔진에 물어 답이 비지 않고 한 쪽(옛 검색 50건 ·
/// 넓힌 검색 200건)을 넘지 않는 것만 쓴다 — 번호 차례로 자른 쪽이 생기지 않게. 내용과 자리(첫 트랙)로만 정해지므로 같은 내용의 두 저장소에서 같다.
fn search_words(store: &Store, first_off: Option<&Value>) -> Result<Words> {
    let eligible = |list: Vec<String>| -> Vec<String> {
        word_counts(&list).into_iter().filter(|(_, n)| (1..=WORD_HITS_MAX).contains(n)).map(|(w, _)| w).collect()
    };
    let plain_candidates = eligible(texts(store, "SELECT title FROM events")?);
    let fits = |q: Value| -> Result<bool> {
        let v = store.call(&q)?;
        Ok(v["has_more"] == false && v["items"].as_array().is_some_and(|l| !l.is_empty()))
    };
    let mut plain = Vec::new();
    for at in [0.0, 0.5, 1.0] {
        if let Some(word) = pick_from(&plain_candidates, at, &plain, &mut |w| fits(json!({"op":"search","text":w})))? {
            plain.push(word);
        }
    }
    let filtered = match first_off {
        Some(view) => pick_from(&plain_candidates, 0.0, &[], &mut |w| Ok(fits(json!({"op":"search","text":w}))? && fits(with(json!({"op":"search","text":w}), view))?))?,
        None => None,
    };
    let mut wide: Vec<String> = Vec::new();
    for sql in ["SELECT name FROM periods", "SELECT name FROM cells"] {
        let candidates = eligible(texts(store, sql)?);
        // 옛 검색의 낱말과도 겹치지 않게 — 겹치면 `search`의 한 열쇠에 두 답이 겹쳐 한쪽이 사라진다(과제 6 얹힌 몫 5).
        let taken: Vec<String> = plain.iter().chain(&wide).cloned().collect();
        if let Some(word) = pick_from(&candidates, 0.5, &taken, &mut |w| fits(json!({"op":"search","text":w,"kinds":crate::query::SEARCH_KINDS,"limit":200})))? {
            wide.push(word);
        }
    }
    Ok(Words { plain, filtered, wide })
}

/// `info`의 meta에서 적는 수(세기 · 보는 범위). 판(`schema`)은 열쇠 ≠ 자리면 '4.1'(옛 저장소는 '3' · '3.1')이라 뺀다.
const COUNT_KEYS: [&str; 20] = ["count", "unknown", "min", "max", "packs", "tracks", "rows", "periods", "cells", "groups", "categories",
    "axis_cells", "items", "entities", "row_labels", "variants", "variant_rows", "variant_moves", "names", "lens_names"];
/// 한 해(분) — 같은 해 보기의 앞뒤 범위를 잡는 어림값.
const YEAR: i64 = 525_600;

/// 목록에서 고르게 셋(처음 · 가운데 · 끝). 셋 이하면 모두.
fn pick3<T: Clone>(list: &[T]) -> Vec<T> {
    if list.len() <= 3 {
        return list.to_vec();
    }
    vec![list[0].clone(), list[list.len() / 2].clone(), list[list.len() - 1].clone()]
}

fn texts(store: &Store, sql: &str) -> Result<Vec<String>> {
    let mut stmt = store.db.prepare(sql)?;
    let list = stmt.query_map([], |r| r.get(0))?.collect::<std::result::Result<Vec<String>, _>>()?;
    Ok(list)
}

/// 물음에 보기(변형 · 거르개)를 얹는다.
fn with(mut q: Value, view: &Value) -> Value {
    for (key, v) in view.as_object().into_iter().flatten() {
        q[key] = v.clone();
    }
    q
}

/// 사건 번호 → uid(정수일 때만).
fn event_id(v: &mut Value, n: &mut Names) -> Result<()> {
    if let Some(id) = v.as_i64() {
        *v = json!(n.event(id)?);
    }
    Ok(())
}

/// 띠 번호 → uid(정수일 때만 · 0은 빈 글).
fn band_id(v: &mut Value, n: &mut Names) -> Result<()> {
    if let Some(id) = v.as_i64() {
        *v = json!(n.period(id)?);
    }
    Ok(())
}

/// 트랙 번호 → 열쇠(정수일 때만 · 0 이하는 빈 글).
fn track_id(v: &mut Value, n: &Names) -> Result<()> {
    if let Some(id) = v.as_i64() {
        *v = json!(n.track_any(id)?);
    }
    Ok(())
}

fn each_mut<'v>(v: &'v mut Value, key: &str) -> impl Iterator<Item = &'v mut Value> {
    v.get_mut(key).and_then(Value::as_array_mut).into_iter().flatten()
}

/// 사건 한 줄(`event` · `list` · `range` · 옛 검색의 줄): 번호 · 자료집 · 출처를 이름으로.
fn event_row(v: &mut Value, n: &mut Names) -> Result<()> {
    event_id(&mut v["id"], n)?;
    if let Some(pack) = v["pack"].as_i64() {
        v["pack"] = json!(n.pack(pack)?);
    }
    if let Some(source) = v["source"].as_i64() {
        v["source"] = json!(n.source(source)?);
    }
    Ok(())
}

/// 옛 검색 · 목록의 답: 줄마다 사건 한 줄, 이어 받기 표(`next` — 사건 번호 또는 [시작, 사건 번호])도 uid로.
fn event_page(mut v: Value, n: &mut Names) -> Result<Value> {
    for row in each_mut(&mut v, "items") {
        event_row(row, n)?;
    }
    match v.get_mut("next") {
        Some(Value::Array(pair)) if pair.len() == 2 => event_id(&mut pair[1], n)?,
        Some(next) => event_id(next, n)?,
        None => {}
    }
    Ok(v)
}

/// `events_in`: 줄의 사건 번호를 uid로(같은 배열인 `events`도 함께).
fn canon_events_in(mut v: Value, n: &mut Names) -> Result<Value> {
    for row in each_mut(&mut v, "items") {
        event_id(&mut row["id"], n)?;
    }
    v["events"] = v["items"].clone();
    Ok(v)
}

/// `same_year`: 트랙 · 띠 · 사건 번호를 이름으로.
fn canon_same_year(mut v: Value, n: &mut Names) -> Result<Value> {
    for t in each_mut(&mut v, "tracks") {
        track_id(&mut t["track"], n)?;
        for b in each_mut(t, "bands") {
            band_id(&mut b["id"], n)?;
        }
        for c in each_mut(t, "cells") {
            band_id(&mut c["band"], n)?;
        }
        for e in each_mut(t, "events") {
            event_id(&mut e["id"], n)?;
        }
    }
    for key in ["eras", "phases", "figures"] {
        for g in each_mut(&mut v, key) {
            track_id(&mut g["track"], n)?;
        }
    }
    for e in each_mut(&mut v, "events") {
        event_id(&mut e["id"], n)?;
    }
    Ok(v)
}

/// 메아리 묶음이 놓이는 자리 — 엔진(`query.rs` `echo_groups`)과 같은 셈: 띠 묶음은 그 띠 줄의 자리, 띠 없는 묶음은 그 트랙 마지막 자리 + 0.5.
/// 번호(띠 · 트랙)는 그 저장소의 것이라 바꾸기 전에 잰다.
fn echo_seat(n: &Names, group: &Value) -> Result<f64> {
    let rows = &n.store.rows;
    let band = group["band"].as_i64().unwrap_or(0);
    if band != 0 {
        let row: i64 = n.store.db.prepare_cached("SELECT row FROM periods WHERE id=?1")?
            .query_row([band], |r| r.get(0)).map_err(|_| format!("메아리 묶음이 없는 띠를 가리킵니다: {band}"))?;
        return Ok(rows.pos(row) as f64);
    }
    let track = group["track"].as_i64().unwrap_or(-1);
    let last: i64 = n.store.db.prepare_cached("SELECT COALESCE(max(id),-1) FROM rows WHERE track=?1")?.query_row([track], |r| r.get(0))?;
    Ok(rows.pos(last) as f64 + 0.5)
}

/// `echo`: 제 것 · 메아리 · 묶음의 사건 번호 · 띠 번호 · 트랙 번호를 이름으로.
/// 묶음(`groups`)은 엔진이 연표 위에서 아래(자리) 차례로 늘어놓고 **같은 자리는 열쇠 `b:<띠 번호>`의 글자 견줌**으로 깬다 — 번호 동률이라
/// 계약 밖이다(판정 R28 · R12 — 엔진은 그대로 둔다). 같은 자리에 이어 선 묶음끼리만 바꿔 적은 내용의 글 차례로 다시 늘어놓는다
/// (자리가 다른 묶음의 차례는 엔진이 낸 그대로 — 그 차례가 갈리면 여전히 드러난다).
fn canon_echo(mut v: Value, n: &mut Names) -> Result<Value> {
    for key in ["own", "echo"] {
        for row in each_mut(&mut v, key) {
            event_id(&mut row["id"], n)?;
        }
    }
    for id in each_mut(&mut v, "echoIds") {
        event_id(id, n)?;
    }
    let seats = each_mut(&mut v, "groups").map(|g| echo_seat(n, g)).collect::<Result<Vec<f64>>>()?;
    for g in each_mut(&mut v, "groups") {
        track_id(&mut g["track"], n)?;
        band_id(&mut g["band"], n)?;
        for row in each_mut(g, "events") {
            event_id(&mut row["id"], n)?;
        }
    }
    if let Some(groups) = array_mut(&mut v, "groups") {
        let mut at = 0;
        while at < groups.len() {
            let end = (at..groups.len()).find(|&k| seats[k] != seats[at]).unwrap_or(groups.len());
            sort_by_text(&mut groups[at..end]);
            at = end;
        }
    }
    Ok(v)
}

/// 줄 이름 답(`{"labels":[{"row","items":[원소 JSON…]}]}`)의 원소 안 `track`(배치의 트랙 순번 — `fill`이 원소를 통째로 싣는다)을
/// 트랙 열쇠로(판정 R17). 순번은 그 배치에서의 차례라, 트랙을 고쳐 쓴 저장소(하위 배치 · 순번만 밀린 트랙)에서는 통째 짓기와 다를 수 있다
/// (앱은 이 값을 읽지 않는다). 원소는 제 `track` · `row`로 줄이 풀렸으므로 **원소가 든 줄(`row` — 자리)의 트랙**이 곧 그 트랙이다 —
/// 낡은 순번을 읽지 않고 그 트랙의 열쇠로 바꿔 적는다.
fn canon_row_labels(mut v: Value, blocks: &[crate::rowmap::Block], n: &Names) -> Result<Value> {
    for entry in each_mut(&mut v, "labels") {
        let row = entry["row"].as_i64().unwrap_or(-1);
        let Some(block) = blocks.iter().find(|b| b.pos0 <= row && row < b.pos0 + b.n) else { continue };
        let key = n.track(block.track)?;
        for item in each_mut(entry, "items") {
            if item.get("track").is_some() {
                item["track"] = json!(key);
            }
        }
    }
    Ok(v)
}

/// 조회 목록의 답을 번호 없이 적는다(모듈 머리글의 `queries`).
fn canon_queries(store: &Store, n: &mut Names) -> Result<Value> {
    let ask = |q: Value| store.call(&q);
    let (min, max) = (meta_int(store, "min")?, meta_int(store, "max")?);
    let span = (max - min).max(1);
    let total = store.rows.total();
    let packs = all_packs(store)?;
    let blocks = store.rows.blocks().to_vec();
    // 보기: 기본 · 변형 하나씩 · 첫 트랙(자리 차례)을 끈 거르개. 이름은 번호 없이.
    let mut views: Vec<(String, Value)> = vec![("기본".to_owned(), json!({}))];
    let mut keys: Vec<String> = n.variants.values().cloned().collect();
    keys.sort();
    views.extend(keys.iter().map(|k| (format!("변형 {k}"), json!({ "variants": [k] }))));
    let first_off = blocks.first().map(|b| json!({"filter":{"tracks_off":[b.track]}}));
    if let (Some(b), Some(view)) = (blocks.first(), &first_off) {
        views.push((format!("거르개 {}", n.track(b.track)?), view.clone()));
    }
    // 띠 · 사건은 uid가 하나뿐인 것에서 uid 차례로 고르게 셋.
    let bands = pick3(&texts(store, "SELECT uid FROM periods WHERE uid<>'' GROUP BY uid HAVING count(*)=1 ORDER BY uid")?);
    let events = pick3(&texts(store, "SELECT uid FROM events WHERE uid<>'' AND start IS NOT NULL GROUP BY uid HAVING count(*)=1 ORDER BY uid")?);
    let band_of = |uid: &str| -> Result<(i64, i64, i64)> {
        Ok(store.db.query_row("SELECT id,start,end FROM periods WHERE uid=?1", [uid], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?)
    };
    let event_of = |uid: &str| -> Result<(i64, i64)> {
        Ok(store.db.query_row("SELECT id,start FROM events WHERE uid=?1", [uid], |r| Ok((r.get(0)?, r.get(1)?)))?)
    };
    let mut out = Map::new();

    // rows_near — 시각 셋(보는 범위를 넷으로 나눈 자리) · 보기마다.
    let width = (span / 20).max(1);
    let mut near = Map::new();
    for (label, view) in &views {
        let mut list = Vec::new();
        for k in 1..=3 {
            let at = min + span * k / 4;
            list.push(ask(with(json!({"op":"rows_near","near":[at - width, at + width],"far":[at - 4 * width, at + 4 * width],"fade":width,"packs":packs}), view))?);
        }
        near.insert(label.clone(), json!(list));
    }
    out.insert("rows_near".into(), Value::Object(near));

    // row_labels — 줄 전부 · 보기마다.
    let mut labels = Map::new();
    let rows: Vec<i64> = (0..total).collect();
    for (label, view) in &views {
        labels.insert(label.clone(), canon_row_labels(ask(with(json!({"op":"row_labels","rows":rows}), view))?, &blocks, n)?);
    }
    out.insert("row_labels".into(), Value::Object(labels));

    // events_in — 트랙마다 그 줄 하나하나(줄 자리로 묻는다) · 고른 띠(uid로 묻는다).
    let mut by_track = Map::new();
    for b in &blocks {
        let mut list = Vec::new();
        for row in b.pos0..b.pos0 + b.n {
            list.push(canon_events_in(ask(json!({"op":"events_in","row":row,"lo":min,"hi":max + 1,"limit":200}))?, n)?);
        }
        by_track.insert(n.track(b.track)?, json!(list));
    }
    out.insert("events_in".into(), json!({"tracks":by_track}));

    // 띠 · 사건 · 낱말로 묻는 것(events_in의 띠 · same_year · echo · search) — 기본 보기와 변형을 하나씩 켠 보기마다(얹힌 몫 8 — 변형의 이사 ·
    // 옮겨 적은 줄(relink)에 기대는 답이다). 기본 보기의 답은 예전 자리(`events_in.bands` · `same_year` · `echo` · `search`)에, 변형 보기의 답은
    // `variant_views.<변형 열쇠>`에 같은 꼴로 싣는다. 낱말은 저장소 내용에서 고른다([`search_words`]).
    let words = search_words(store, first_off.as_ref())?;
    let by_view = |view: &Value, n: &mut Names| -> Result<Map<String, Value>> {
        let mut part = Map::new();
        // events_in — 고른 띠(uid로 묻는다).
        let mut by_band = Map::new();
        for uid in &bands {
            by_band.insert(uid.clone(), canon_events_in(ask(with(json!({"op":"events_in","band":uid,"lo":min,"hi":max + 1,"limit":200}), view))?, n)?);
        }
        part.insert("events_in_bands".into(), Value::Object(by_band));
        // same_year — 고른 사건의 때(앞뒤 다섯 해).
        let mut same = Map::new();
        for uid in &events {
            let (_, start) = event_of(uid)?;
            same.insert(uid.clone(), canon_same_year(ask(with(json!({"op":"same_year","at":start,"window":5 * YEAR}), view))?, n)?);
        }
        part.insert("same_year".into(), Value::Object(same));
        // echo — 고른 띠 하나씩을 그 띠의 구간으로 비춘다.
        let mut echo = Map::new();
        for uid in &bands {
            let (_, start, end) = band_of(uid)?;
            echo.insert(uid.clone(), canon_echo(ask(with(json!({"op":"echo","spots":[{"uid":uid,"start":start,"end":end}]}), view))?, n)?);
        }
        part.insert("echo".into(), Value::Object(echo));
        // search — 사건만 찾는 옛 검색의 낱말 · 이름까지 찾는 넓힌 검색의 낱말.
        let mut search = Map::new();
        for word in &words.plain {
            search.insert(word.clone(), event_page(ask(with(json!({"op":"search","text":word}), view))?, n)?);
        }
        for word in &words.wide {
            let mut v = ask(with(json!({"op":"search","text":word,"kinds":crate::query::SEARCH_KINDS,"limit":200}), view))?;
            for row in each_mut(&mut v, "items") {
                event_id(&mut row["id"], n)?;
            }
            search.insert(word.clone(), v);
        }
        part.insert("search".into(), Value::Object(search));
        Ok(part)
    };
    let mut base = by_view(&json!({}), n)?;
    let mut variant_views = Map::new();
    for key in &keys {
        variant_views.insert(key.clone(), Value::Object(by_view(&json!({ "variants": [key] }), n)?));
    }
    out["events_in"]["bands"] = base.remove("events_in_bands").unwrap_or(Value::Null);
    for key in ["same_year", "echo", "search"] {
        out.insert(key.into(), base.remove(key).unwrap_or(Value::Null));
    }
    out.insert("variant_views".into(), Value::Object(variant_views));
    // 고른 낱말의 수(과제 6 얹힌 몫 5) — 한쪽 저장소만 낱말을 못 골라 검색을 덜 견준 것이 '같음'으로 묻히지 않게 함께 적는다.
    out.insert("search_words".into(), json!({"plain":words.plain.len(),"filtered":words.filtered.is_some(),"wide":words.wide.len()}));
    // search_plain — 거르개(첫 트랙을 끔)를 건 옛 검색.
    let plain = match (&first_off, &words.filtered) {
        (Some(view), Some(word)) => event_page(ask(with(json!({"op":"search","text":word}), view))?, n)?,
        _ => Value::Null,
    };
    out.insert("search_plain".into(), plain);

    // list — 보기마다 쪽 둘(시작 차례 · 둘째 자리부터 끝까지 — 트랙 덩이 가운데서 시작한다).
    let lane = if total > 1 { 1 } else { 0 };
    let lanes = (total - lane).clamp(1, 32);
    let mut lists = Map::new();
    for (label, view) in &views {
        let ask_page = |after: &Value| ask(with(json!({"op":"list","lo":min,"hi":max,"lane":lane,"lanes":lanes,"order":"start","limit":20,"after":after}), view));
        let first = ask_page(&Value::Null)?;
        let second = if first["has_more"] == true { event_page(ask_page(&first["next"])?, n)? } else { Value::Null };
        lists.insert(label.clone(), json!([event_page(first, n)?, second]));
    }
    out.insert("list".into(), Value::Object(lists));

    // event · uid_of · id_of · ids_of · cells_of — 고른 사건 셋 · 띠 셋(번호는 그 저장소에서 uid로 찾아 묻는다).
    let (mut event, mut uid_of, mut id_of, mut cells_of) = (Map::new(), Map::new(), Map::new(), Map::new());
    for uid in &events {
        let (id, _) = event_of(uid)?;
        let mut row = ask(json!({"op":"event","id":id}))?;
        event_row(&mut row, n)?;
        event.insert(uid.clone(), row);
        uid_of.insert(uid.clone(), ask(json!({"op":"uid_of","kind":"event","id":id}))?);
    }
    for uid in &bands {
        let (id, _, _) = band_of(uid)?;
        uid_of.insert(uid.clone(), ask(json!({"op":"uid_of","kind":"band","id":id}))?);
        let mut cells = ask(json!({"op":"cells_of","band":id}))?;
        // 칸 번호 → `[띠 uid, kind, lane, 시작]`(타일의 칸과 같은 이름 `cell`로).
        for c in cells.as_array_mut().into_iter().flatten() {
            if let Some(cell) = c.as_object_mut().and_then(|m| m.remove("id")).and_then(|v| v.as_i64()) {
                c["cell"] = n.cell(cell)?;
            }
        }
        cells_of.insert(uid.clone(), cells);
    }
    let mut asked: Vec<String> = bands.iter().chain(events.iter()).cloned().collect();
    asked.push("없는/이름".to_owned());
    for uid in &asked {
        let mut v = ask(json!({"op":"id_of","uid":uid}))?;
        band_id(&mut v["band"], n)?;
        event_id(&mut v["event"], n)?;
        id_of.insert(uid.clone(), v);
    }
    let mut ids = ask(json!({"op":"ids_of","uids":asked}))?;
    for b in each_mut(&mut ids, "bands") {
        band_id(&mut b["id"], n)?;
    }
    for e in each_mut(&mut ids, "events") {
        event_id(&mut e["id"], n)?;
    }
    out.insert("event".into(), Value::Object(event));
    out.insert("uid_of".into(), Value::Object(uid_of));
    out.insert("id_of".into(), Value::Object(id_of));
    out.insert("ids_of".into(), ids);
    out.insert("cells_of".into(), Value::Object(cells_of));

    // scopes · entity(전부).
    let mut scopes = ask(json!({"op":"scopes"}))?;
    for s in each_mut(&mut scopes, "scopes") {
        track_id(&mut s["track"], n)?;
    }
    out.insert("scopes".into(), scopes);
    let mut entity = Map::new();
    for uid in texts(store, "SELECT uid FROM entities ORDER BY uid")? {
        entity.insert(uid.clone(), ask(json!({"op":"entity","uid":uid}))?);
    }
    out.insert("entity".into(), Value::Object(entity));

    // range(옛 줄 범위 조회) — 줄 묶음(8줄)마다 모든 사건. 엔진은 **사건 번호 차례**로만 낸다(이어 받기도 번호) — 덧붙여 넣은 사건은 끝 번호를 받아
    // 통째 짓기와 차례가 갈린다(과제 7b 실자료 nest-scene). 번호로만 정해지는 차례라 계약 밖이다(판정 R12) — 묶음마다 바꿔 적은 내용의 글 차례로
    // 늘어놓는다. 한 묶음을 `MAX_SHAPES + 1`까지 받으므로 번호 차례로 잘린 쪽은 없다(잘리면 담긴 사건이 달라 그대로 드러난다).
    let mut range = Vec::new();
    for chunk in 0..(total + CHUNK_ROWS - 1) / CHUNK_ROWS {
        let mut list = store.range(min, max, chunk * CHUNK_ROWS, CHUNK_ROWS, 0, crate::MAX_SHAPES + 1)?;
        for row in list.iter_mut() {
            event_row(row, n)?;
        }
        sort_by_text(&mut list);
        range.push(json!(list));
    }
    out.insert("range".into(), json!(range));

    // verify_store — 표본 200의 누락 · 중복.
    let check = crate::verify::verify_store(store, 200)?;
    out.insert("verify_store".into(), json!({"missing":check.missing,"dup":check.dup}));

    // info — 수 세기 · 보는 범위 · 자료집별 수(글자 id로).
    let told = store.info()?;
    let meta = &told["meta"];
    let mut info = Map::new();
    for key in COUNT_KEYS {
        info.insert(key.to_owned(), meta[key].as_str().and_then(|s| s.parse::<i64>().ok()).map_or(Value::Null, Value::from));
    }
    for key in ["pack_events", "pack_periods"] {
        let raw: Value = meta[key].as_str().and_then(|text| serde_json::from_str(text).ok()).unwrap_or_else(|| json!({}));
        let mut by_pack = Map::new();
        for (id, count) in raw.as_object().into_iter().flatten() {
            by_pack.insert(n.pack(id.parse()?)?, count.clone());
        }
        info.insert(key.to_owned(), Value::Object(by_pack));
    }
    out.insert("info".into(), Value::Object(info));
    Ok(Value::Object(out))
}

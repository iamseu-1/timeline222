//! 같음의 약속(설계 3-4) 견주기 — 고쳐 쓴 저장소가 그 조합을 통째로 지은 것과 같은가. `tests/apply.rs` · `tests/add_pack.rs`가 함께 쓴다(고침 1회차 —
//! 두 벌이던 도우미를 하나로): canon(단계를 줄인 것 + 조회 목록) · meta 전부(판 `schema`만 빼고 · 자료집 번호로 적힌 것은 글자 id로) · 본문 색인 낱자 ·
//! 사건의 트랙 안 차례 · 항목 기록 · 스키마 4의 띠 `form` · 문화권 단위 줄(`sphere_lines` — canon이 아직 싣지 않아 표에서 바로).
#![allow(dead_code)]
use archive_engine::canon::{canon_store, CanonOpts};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::Path;

/// 단계를 줄인 canon(그 자리에서 세는 단계 6 · 요약을 읽는 단계 8 · 11 · 14 · 가장 촘촘한 단계 0 · 4는 다른 검사가 본다).
pub fn quick() -> CanonOpts {
    CanonOpts { levels: vec![6, 8, 11, 14], max_x: 16, queries: false }
}

/// [`quick`] + 조회 목록.
pub fn quick_q() -> CanonOpts {
    CanonOpts { queries: true, ..quick() }
}

pub fn meta(path: &Path) -> BTreeMap<String, String> {
    let db = rusqlite::Connection::open(path).unwrap();
    let mut stmt = db.prepare("SELECT key,value FROM meta").unwrap();
    let out = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    out
}

pub fn pairs(path: &Path, sql: &str) -> Vec<(String, String)> {
    let db = rusqlite::Connection::open(path).unwrap();
    let mut stmt = db.prepare(sql).unwrap();
    let out = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    out
}

/// 자료집 번호로 적힌 meta 하나를 글자 id로(닿는 트랙은 트랙 열쇠의 글자 차례로). `pack_keys`는 글자 id의 목록으로.
pub fn by_pack(path: &Path, key: &str) -> serde_json::Value {
    let m = meta(path);
    let keys: serde_json::Value = serde_json::from_str(&m["pack_keys"]).unwrap();
    let raw: serde_json::Value = m.get(key).map_or(serde_json::Value::Null, |text| serde_json::from_str(text).unwrap());
    let tracks: HashMap<String, String> = pairs(path, "SELECT CAST(id AS TEXT),key FROM tracks").into_iter().collect();
    let mut out = serde_json::Map::new();
    for (pack, value) in raw.as_object().into_iter().flatten() {
        let label = keys[pack].as_str().unwrap_or_else(|| panic!("meta.{key}의 자료집 {pack}에 글자 id가 없습니다")).to_owned();
        let value = match key {
            "pack_keys" => serde_json::json!(true),
            "pack_tracks" => {
                let mut list: Vec<String> = value.as_array().unwrap().iter().map(|id| tracks[&id.to_string()].clone()).collect();
                list.sort();
                serde_json::json!(list)
            }
            _ => value.clone(),
        };
        assert!(out.insert(label.clone(), value).is_none(), "meta.{key}: 글자 id {label}이 둘");
    }
    serde_json::Value::Object(out)
}

/// meta가 통째 짓기와 같은가 — 판(`schema` — 열쇠 ≠ 자리면 '4.1' · 옛 저장소는 '3' · '3.1')만 뺀다. `skip`에 더 뺄 열쇠.
pub fn same_meta(path: &Path, want: &Path, tag: &str, skip: &[&str]) {
    const BY_PACK: [&str; 5] = ["pack_keys", "pack_info", "pack_events", "pack_periods", "pack_tracks"];
    let plain = |p: &Path| -> BTreeMap<String, String> {
        meta(p).into_iter().filter(|(k, _)| k != "schema" && !skip.contains(&k.as_str()) && !BY_PACK.contains(&k.as_str())).collect()
    };
    assert_eq!(plain(path), plain(want), "{tag}: meta");
    for key in BY_PACK {
        assert_eq!(by_pack(path, key), by_pack(want, key), "{tag}: meta.{key}");
    }
}

/// 본문 색인(contentless FTS)의 낱자마다 맞는 사건 uid(덧줄은 `덧 <uid>`). 낱자 · 문서 짝을 `fts5vocab`의 'instance'로 한 번에 읽는다(고침 1회차 —
/// 낱자마다 MATCH를 부르던 [`search_terms_by_match`]는 글이 많은 저장소에서 수십 분이 걸렸다 · 두 길이 같은지는 [`same_records`]가 작은 장면마다 본다).
pub fn search_terms(path: &Path) -> BTreeMap<String, BTreeSet<String>> {
    let db = rusqlite::Connection::open(path).unwrap();
    db.execute_batch("CREATE VIRTUAL TABLE temp.vocab USING fts5vocab('main','search','instance')").unwrap();
    let uids: HashMap<i64, String> = db.prepare("SELECT id,uid FROM events").unwrap().query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    let uid_of = |id: i64| uids.get(&id).cloned().unwrap_or_else(|| format!("없는 사건 {id}"));
    let mut out: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut stmt = db.prepare("SELECT term,doc FROM temp.vocab").unwrap();
    for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))).unwrap() {
        let (term, id) = row.unwrap();
        out.entry(term).or_default().insert(if id < 0 { format!("덧 {}", uid_of(-id)) } else { uid_of(id) });
    }
    out
}

/// [`search_terms`]의 옛 길 — 낱자마다 MATCH(느리다 · 두 길이 같은지 볼 때만).
pub fn search_terms_by_match(path: &Path) -> BTreeMap<String, BTreeSet<String>> {
    let db = rusqlite::Connection::open(path).unwrap();
    db.execute_batch("CREATE VIRTUAL TABLE temp.vocab USING fts5vocab('main','search','row')").unwrap();
    let terms: Vec<String> = db.prepare("SELECT term FROM temp.vocab ORDER BY term").unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    let uid_of = |id: i64| -> String {
        db.query_row("SELECT uid FROM events WHERE id=?1", [id], |r| r.get::<_, String>(0)).unwrap_or_else(|_| format!("없는 사건 {id}"))
    };
    let mut out = BTreeMap::new();
    for term in terms {
        let ids: Vec<i64> = db.prepare("SELECT rowid FROM search WHERE search MATCH ?1").unwrap()
            .query_map([format!("\"{term}\"")], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
        let hits: BTreeSet<String> = ids.into_iter().map(|id| if id < 0 { format!("덧 {}", uid_of(-id)) } else { uid_of(id) }).collect();
        if !hits.is_empty() {
            out.insert(term, hits);
        }
    }
    out
}

/// 항목 기록(uid · 자료집 글자 id · 갈래 · 넣은 차례 · 지문 · 본문).
fn records(path: &Path) -> Vec<(String, String)> {
    let keys: serde_json::Value = serde_json::from_str(&meta(path)["pack_keys"]).unwrap();
    pairs(path, "SELECT uid,CAST(pack AS TEXT)||'|'||kind||'|'||ord||'|'||sum||'|'||json FROM entities ORDER BY uid").into_iter()
        .map(|(uid, rest)| {
            let (pack, rest) = rest.split_once('|').unwrap();
            (uid, format!("{}|{rest}", keys[pack].as_str().unwrap_or("?")))
        }).collect()
}

/// 항목 기록(uid · 자료집 글자 id · 갈래 · 넣은 차례 · 지문 · 본문)이 통째 짓기와 같은가(과제 5d의 "entities").
pub fn same_entities(path: &Path, want: &Path, tag: &str) {
    assert_eq!(records(path), records(want), "{tag}: 항목 기록");
}

/// 띠의 형식 4 뜻(스키마 4 — `periods.form`)을 (uid, form)으로 · 글자 차례(같은 uid도 따로). 열이 없는 옛 저장소는 None.
fn forms(path: &Path) -> Option<Vec<(String, i64)>> {
    let db = rusqlite::Connection::open(path).unwrap();
    let has = db.prepare("SELECT 1 FROM pragma_table_info('periods') WHERE name='form'").unwrap().exists([]).unwrap();
    if !has {
        return None;
    }
    let mut list: Vec<(String, i64)> = db.prepare("SELECT uid,form FROM periods").unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    list.sort();
    Some(list)
}

/// 문화권 단위 줄(스키마 4 — `sphere_lines`)의 내용을 id 차례로 — 번호(`id`)는 빼고 자료집은 글자 id(`meta.pack_keys`)로. 표가 없는 옛 저장소는 None.
fn sphere_lines(path: &Path) -> Option<Vec<String>> {
    let db = rusqlite::Connection::open(path).unwrap();
    let has = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='sphere_lines'").unwrap().exists([]).unwrap();
    if !has {
        return None;
    }
    let keys: serde_json::Value = serde_json::from_str(&meta(path)["pack_keys"]).unwrap();
    let mut stmt = db.prepare("SELECT pack,sphere,kind,start,end,name,uid,color,data FROM sphere_lines ORDER BY id").unwrap();
    let rows = stmt.query_map([], |r| {
        let pack: i64 = r.get(0)?;
        Ok(format!("{}|{}|{}|{}|{}|{}|{}|{}|{}", keys[&pack.to_string()].as_str().unwrap_or("?"), r.get::<_, String>(1)?, r.get::<_, i64>(2)?,
            r.get::<_, i64>(3)?, r.get::<_, i64>(4)?, r.get::<_, String>(5)?, r.get::<_, String>(6)?, r.get::<_, i64>(7)?, r.get::<_, String>(8)?))
    }).unwrap().map(Result::unwrap).collect();
    Some(rows)
}

/// 스키마 4의 값(띠 `form` · 문화권 단위 줄)이 통째 짓기와 같은가 — canon이 아직 싣지 않는 값을 표에서 바로 견준다(리메이크 3단계 걸음 3).
pub fn same_schema4(path: &Path, want: &Path, tag: &str) {
    assert_eq!(forms(path), forms(want), "{tag}: 띠의 form");
    assert_eq!(sphere_lines(path), sphere_lines(want), "{tag}: 문화권 단위 줄(sphere_lines)");
}

/// meta(지은 날 `now` 말고) · 검색 낱자(통째 짓기에 낱자가 있어야 함) · 사건의 트랙 안 차례 · 항목 기록까지 통째 짓기와 같은가(`tests/apply.rs`의 견줌).
pub fn same_records(path: &Path, want: &Path, tag: &str) {
    same_meta(path, want, tag, &["now"]);
    let (got, full_terms) = (search_terms(path), search_terms(want));
    assert!(!full_terms.is_empty(), "{tag}: 통째 짓기에 검색 낱자가 없습니다");
    assert_eq!(search_terms_by_match(path), got, "{tag}: 낱자 읽는 두 길(instance · MATCH)이 다릅니다");
    assert_eq!(got, full_terms, "{tag}: 검색 낱자");
    // 얹힌 몫 14: 덧붙임 · 다시 쓰기 Builder가 적은 트랙 안 차례(판정 R23)가 uid마다 통째 짓기와 같다.
    let ords = "SELECT uid,CAST(ord AS TEXT) FROM events ORDER BY uid";
    assert_eq!(pairs(path, ords), pairs(want, ords), "{tag}: events.ord");
    same_entities(path, want, tag);
    same_schema4(path, want, tag);
}

/// 같음의 약속 전부: canon([`quick_q`]) + [`same_but_canon`].
pub fn same_store(path: &Path, want: &Path, tag: &str, skip: &[&str]) {
    assert!(canon_store(path, &quick_q()).unwrap() == canon_store(want, &quick_q()).unwrap(), "{tag}: canon이 통째 짓기와 다릅니다");
    same_but_canon(path, want, tag, skip);
}

/// canon 말고 같음의 약속: meta(`skip` 말고) · 검색 낱자 · 사건의 트랙 안 차례 · 항목 기록 · 트랙 지문(canon은 부르는 쪽이 — 통째 짓기의 canon을 한 번만 셈할 때).
pub fn same_but_canon(path: &Path, want: &Path, tag: &str, skip: &[&str]) {
    assert_eq!(search_terms(path), search_terms(want), "{tag}: 검색 낱자");
    same_light(path, want, tag, skip);
}

/// 큰 저장소(등불 연대기 견본처럼 글이 많은 것)의 걸음마다 견줌: meta · 사건의 트랙 안 차례 · 항목 기록 · 트랙 지문(canon과 본문 색인 낱자는 뺀다 —
/// 한 걸음에 수십 분이 걸려서. canon은 판 끝에 [`light_canon`]으로 한 번).
pub fn same_light(path: &Path, want: &Path, tag: &str, skip: &[&str]) {
    same_meta(path, want, tag, skip);
    let ords = "SELECT uid,CAST(ord AS TEXT) FROM events ORDER BY uid";
    assert_eq!(pairs(path, ords), pairs(want, ords), "{tag}: events.ord");
    same_entities(path, want, tag);
    same_schema4(path, want, tag);
    let prints = "SELECT key,print FROM track_prints ORDER BY key";
    assert_eq!(pairs(path, prints), pairs(want, prints), "{tag}: 트랙 지문");
}

/// 큰 저장소의 canon — 성긴 단계(8 · 11 · 14 · 가로 8열)의 타일 · layout만(조회 목록 없이).
pub fn light_canon() -> CanonOpts {
    CanonOpts { levels: vec![8, 11, 14], max_x: 8, queries: false }
}

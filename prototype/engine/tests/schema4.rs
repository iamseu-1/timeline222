//! 스키마 4(리메이크 3단계 · 계약 1-1 · 계획 과제 3의 검사 '옛 저장소 검사'): 판 글자 · 모양 · 값 왕복 · 옛 저장소.
//! - 판 글자: 새로 지은 저장소는 '4'. '3' · '3.1' · '4' · '4.1'은 열리고, 그 밖('1' · '2' · '4.2' · '5' · '9')은 "다시 만들어야 합니다"로 거절된다.
//! - 모양: `sphere_lines`의 정의 글이 계약 1-1의 DDL 그대로 · `periods`의 마지막 열이 `form INTEGER NOT NULL DEFAULT 0` ·
//!   옛 저장소를 모두 덮는 apply로 고친 것(`patch::ensure_schema`)과 표마다 열 차례(`SELECT *`)가 같다.
//! - 값 왕복: 장면(`common::plans`)의 띠 `form` · 최상위 `sphereLines`가 layout의 `sphereLines` · `same_year`의 띠 · 타일 띠 구역 열 10으로 돌아온다.
//! - 옛 저장소 = 새 값을 지운 저장소: 이 계획 전의 엔진이 지은 판 3 저장소(흉내 — [`common::strip_schema4`])를 새 엔진이 읽은 답(layout · 타일 바이트 ·
//!   항목 기록 · `same_year` · `info` · 조회 목록이 든 canon)은, 같은 배치로 지어 form을 0으로 · 줄을 비운 저장소의 답과 같다.
//!   진짜 판 3 저장소(배포본 0.0.4)를 옛 도구와 새 도구로 견주는 것은 `prototype/scripts/schema4-old-store-check.mjs`.
mod common;
use archive_engine::canon::canon_store;
use archive_engine::legacy::import_layout_value;
use archive_engine::levels::{tile_of, CHUNK_ROWS};
use archive_engine::patch::{apply, ApplyIn, Covers};
use archive_engine::schema;
use archive_engine::tile::{build_tile, decode, TileRequest};
use archive_engine::write::write;
use archive_engine::Store;
use common::plans::{packs_of, plan, FORMS};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

/// 장면의 조합 — b의 사람 띠 · c의 주기 줄까지 문화권 단위 줄 넷과 form ≠ 0인 띠 넷이 다 든다.
const SET: [&str; 3] = ["a", "b", "c"];

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-schema4-{}-{name}.db", std::process::id())); // common::SCRATCH_KINDS의 꼴(끝난 검사의 것은 치움)
    let _ = std::fs::remove_file(&path);
    path
}

/// 장면 [`SET`]을 통째로 지은 저장소(판 '4').
fn built(name: &str) -> PathBuf {
    let path = scratch(name);
    import_layout_value(&plan(&SET), &packs_of(&SET), &path).unwrap();
    path
}

fn copy(src: &Path, name: &str) -> PathBuf {
    let dst = scratch(name);
    std::fs::copy(src, &dst).unwrap();
    dst
}

/// 저장소를 복사해 트랙을 거꾸로 차례로 끝 번호 + 3으로 옮긴다([`common::split_keys`] — `tests/rowkeys.rs`의 `scrambled`와 같은 옮김) — 모든 트랙의
/// 줄 열쇠가 자리와 갈리고 판은 '4.1'.
fn split_keys(src: &Path, name: &str) -> PathBuf {
    let dst = copy(src, name);
    common::split_keys(&dst);
    dst
}

fn schema_of(path: &Path) -> String {
    Connection::open(path).unwrap().query_row("SELECT value FROM meta WHERE key='schema'", [], |r| r.get(0)).unwrap()
}

fn count(path: &Path, sql: &str) -> i64 {
    Connection::open(path).unwrap().query_row(sql, [], |r| r.get(0)).unwrap()
}

fn call(s: &Store, q: Value) -> Value {
    s.call(&q).unwrap_or_else(|e| panic!("{q}: {e}"))
}

fn remove(paths: &[&PathBuf]) {
    for p in paths {
        let _ = std::fs::remove_file(p);
    }
}

/// 계약 문서(`docs/계약-아카이브-3단계.md` 1-1)의 ```sql 덩이 가운데 `CREATE TABLE sphere_lines(`로 시작하는 정의 — 주석 줄(`--`)을 빼고
/// 줄마다 앞뒤 빈칸을 걷어 이은 글(끝의 `;`는 뺌). 저장소의 `sqlite_master.sql`과 바로 견줄 수 있는 꼴이다.
/// 문서는 `prototype` 밖이라 저장소 뿌리를 [`common::node::repo_root`]로 찾는다 — `CARGO_MANIFEST_DIR`에서 `..`를 두 번 올라가면
/// 연결 폴더(`dev.ps1 -Junction` · `%TEMP%\ht-…\engine`)로 빌드할 때 임시 폴더 옆을 가리켜 문서를 못 찾는다(과제 9 공식 검사에서 드러남).
fn contract_ddl() -> String {
    let file = common::node::repo_root().join("docs").join("계약-아카이브-3단계.md");
    let doc = std::fs::read_to_string(&file).unwrap_or_else(|e| panic!("{}: {e}", file.display()));
    let mut found = Vec::new();
    for block in doc.split("```sql").skip(1) {
        let body = block.split("```").next().unwrap_or("");
        let text: String = body.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with("--")).collect();
        if text.starts_with("CREATE TABLE sphere_lines(") {
            found.push(text.trim_end_matches(';').to_owned());
        }
    }
    assert_eq!(found.len(), 1, "계약 문서에 sphere_lines 정의가 하나여야 합니다: {found:?}");
    found.pop().unwrap()
}

/// 표의 열(cid · 이름 · 꼴 · NOT NULL · 기본값 · 열쇠) — `SELECT *`의 열 차례와 모양.
fn columns(path: &Path, table: &str) -> Vec<(i64, String, String, i64, Option<String>, i64)> {
    let db = Connection::open(path).unwrap();
    let mut stmt = db.prepare("SELECT cid,name,type,\"notnull\",dflt_value,pk FROM pragma_table_info(?1) ORDER BY cid").unwrap();
    let out = stmt.query_map([table], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))).unwrap().map(Result::unwrap).collect();
    out
}

fn table_sql(path: &Path, table: &str) -> String {
    Connection::open(path).unwrap().query_row("SELECT sql FROM sqlite_master WHERE type='table' AND name=?1", [table], |r| r.get(0))
        .unwrap_or_else(|e| panic!("{}: {table} 표가 없습니다 — {e}", path.display()))
}

/// 저장소의 보통 표 이름(SQLite 안의 것 · 검색 색인의 그림자 표 빼고 — 둘 다 짓기가 같은 글로 만든다).
fn tables(path: &Path) -> Vec<String> {
    let db = Connection::open(path).unwrap();
    let mut stmt = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").unwrap();
    let out = stmt.query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    out
}

#[test]
fn 판_글자_3_3_1_4_4_1은_열리고_그_밖은_다시_만들어야로_거절된다() {
    let _t = common::clock("schema4 판 글자");
    assert_eq!((schema::VERSION, schema::VERSION_SPLIT), ("4", "4.1"));
    assert_eq!(schema::OPENS, ["3", "3.1", "4", "4.1"]);
    let fresh = built("ver-4");
    assert_eq!(schema_of(&fresh), "4", "새로 지은 저장소의 판");
    let split = split_keys(&fresh, "ver-4.1");
    let (old, old_split) = (copy(&fresh, "ver-3"), copy(&split, "ver-3.1"));
    common::strip_schema4(&old, "3");
    common::strip_schema4(&old_split, "3.1");
    // (저장소, 판, 스키마 4의 열 · 표가 있나, 열쇠 = 자리인가)
    for (path, version, four, identity) in [(&fresh, "4", true, true), (&split, "4.1", true, false), (&old, "3", false, true), (&old_split, "3.1", false, false)] {
        assert_eq!(schema_of(path), version);
        let s = Store::open(path).unwrap_or_else(|e| panic!("판 {version}이 열리지 않습니다: {e}"));
        assert_eq!((s.period_form, s.has_sphere_lines), (four, four), "판 {version}의 깃발");
        assert_eq!(s.rows.is_identity(), identity, "판 {version}의 줄 열쇠");
        let lines = call(&s, json!({"op":"layout"}))["sphereLines"].as_array().unwrap().len();
        assert_eq!(lines, if four { 4 } else { 0 }, "판 {version}의 sphereLines");
    }
    // 모르는 판은 거절한다 — 판 4 다음의 열쇠 ≠ 자리 글자('4.2')도, 앞으로의 판('5' · '9')도, 스키마 3 전의 판('1' · '2')도.
    let odd = copy(&fresh, "ver-odd");
    for bad in ["1", "2", "4.2", "5", "9"] {
        Connection::open(&odd).unwrap().execute("UPDATE meta SET value=?1 WHERE key='schema'", [bad]).unwrap();
        let err = match Store::open(&odd) {
            Ok(_) => panic!("판 {bad}이 열렸습니다"),
            Err(e) => e.to_string(),
        };
        assert!(err.contains("다시 만들어야"), "판 {bad}의 거절 글: {err}");
    }
    remove(&[&fresh, &split, &old, &old_split, &odd]);
}

#[test]
fn 스키마_4의_모양은_계약_1_1_그대로이고_고쳐_쓴_옛_저장소와_열_차례가_같다() {
    let _t = common::clock("schema4 모양");
    let ddl = contract_ddl();
    assert_eq!(format!("CREATE TABLE {}", schema::SPHERE_LINES), ddl, "schema.rs의 정의 글이 계약 1-1과 다릅니다");
    let fresh = built("shape");
    assert_eq!(table_sql(&fresh, "sphere_lines"), ddl, "새로 지은 저장소의 sphere_lines");
    let last = columns(&fresh, "periods").pop().unwrap();
    assert_eq!((last.1.as_str(), last.2.as_str(), last.3, last.4.as_deref(), last.5), ("form", "INTEGER", 1, Some("0"), 0), "periods의 마지막 열");
    // 옛 저장소(판 '3')를 같은 배치의 모두 덮는 apply로 고쳐 쓴다 — "delete" 첫머리의 ensure_schema가 form 열(맨 끝)과 sphere_lines 표를 만든다.
    let fixed = copy(&fresh, "shape-fixed");
    common::strip_schema4(&fixed, "3");
    assert!(!common::has_column(&fixed, "periods", "form") && common::index_sql(&fixed, "sphere_lines").is_empty(), "흉내 낸 옛 저장소에는 새 열 · 표가 없다");
    let (p, o) = (plan(&SET), packs_of(&SET));
    let report = write(&fixed, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
    assert!(!report.rewrote.is_empty(), "옛 저장소의 첫 모두 덮는 apply는 트랙을 다시 쓴다");
    assert!(schema::OPENS[2..].contains(&schema_of(&fixed).as_str()), "고쳐 쓴 뒤의 판: {}", schema_of(&fixed));
    assert_eq!(table_sql(&fixed, "sphere_lines"), ddl, "ensure_schema가 만든 sphere_lines");
    assert_eq!(tables(&fixed), tables(&fresh), "표 목록");
    for table in tables(&fresh) {
        assert_eq!(columns(&fixed, &table), columns(&fresh, &table), "{table}의 열 차례 · 모양");
    }
    // SELECT *의 열 이름 차례(앱 · 도구가 열 자리로 읽는 곳이 있어도 같게).
    for table in ["periods", "sphere_lines"] {
        let names = |path: &Path| -> Vec<String> {
            let db = Connection::open(path).unwrap();
            let stmt = db.prepare(&format!("SELECT * FROM {table}")).unwrap();
            let out = stmt.column_names().into_iter().map(str::to_owned).collect();
            out
        };
        assert_eq!(names(&fixed), names(&fresh), "SELECT * FROM {table}");
    }
    assert_eq!(count(&fixed, "SELECT count(*) FROM sphere_lines"), 4, "고쳐 쓴 저장소에 문화권 단위 줄이 들었다");
    assert_eq!(count(&fixed, "SELECT count(*) FROM periods WHERE form<>0"), count(&fresh, "SELECT count(*) FROM periods WHERE form<>0"));
    remove(&[&fresh, &fixed]);
}

#[test]
fn 지은_form과_문화권_단위_줄이_layout_same_year_타일로_돌아온다() {
    let _t = common::clock("schema4 값 왕복");
    let path = built("trip");
    let p = plan(&SET);
    let s = Store::open(&path).unwrap();
    assert!(s.period_form && s.has_sphere_lines);
    // layout의 sphereLines — 표 전부 · id 차례(= 배치 차례) · 자료집은 저장소 번호 · data는 글(객체는 JSON 글 · 없으면 빈 글).
    let layout = call(&s, json!({"op":"layout"}));
    let number = |i: u64| -> i64 {
        let id = &p["packs"][i as usize]["id"];
        layout["packs"].as_array().unwrap().iter().find(|x| x["key"] == *id).unwrap_or_else(|| panic!("자료집 {id}가 layout에 없습니다"))["id"].as_i64().unwrap()
    };
    let want: Vec<Value> = p["sphereLines"].as_array().unwrap().iter().enumerate().map(|(k, l)| json!({
        "id": k as i64 + 1, "pack": number(l["pack"].as_u64().unwrap()), "sphere": l["sphere"], "kind": l["kind"], "start": l["start"], "end": l["end"],
        "name": l["name"], "uid": l["uid"], "color": l["color"],
        "data": match &l["data"] { Value::String(text) => json!(text), Value::Null => json!(""), other => json!(other.to_string()) },
    })).collect();
    assert_eq!(want.iter().map(|l| l["kind"].as_i64().unwrap()).collect::<Vec<_>>(), vec![1, 1, 2, 3], "장면의 줄 넷");
    assert_eq!(layout["sphereLines"], json!(want), "layout의 sphereLines");
    assert_ne!(want[1]["pack"], want[0]["pack"], "b의 사람 띠는 b의 자료집 번호");
    assert!(want[3]["data"].as_str().unwrap().starts_with('{'), "주기 줄의 data는 JSON 글");

    // same_year — form ≠ 0인 띠는 그 값, 나머지 띠는 0.
    let forms: BTreeMap<&str, i64> = FORMS.into_iter().collect();
    let spans: Vec<(String, i64, i64)> = {
        let db = Connection::open(&path).unwrap();
        let mut stmt = db.prepare("SELECT uid,start,end FROM periods WHERE uid<>'' ORDER BY id").unwrap();
        let out = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap().map(Result::unwrap).collect();
        out
    };
    let mut seen = BTreeSet::new();
    for (uid, start, end) in &spans {
        let at = start + (end - start) / 2;
        let got = call(&s, json!({"op":"same_year","at":at,"end":at}));
        for b in got["tracks"].as_array().unwrap().iter().flat_map(|t| t["bands"].as_array().unwrap()) {
            let u = b["uid"].as_str().unwrap();
            assert_eq!(b["form"].as_i64(), Some(forms.get(u).copied().unwrap_or(0)), "same_year {at}: {u}의 form");
            if u == uid {
                seen.insert(uid.clone());
            }
        }
    }
    for uid in forms.keys() {
        assert!(seen.contains(*uid), "same_year에서 {uid}를 보지 못했습니다");
    }

    // 타일 — 띠 구역 열 10(form ≠ 0인 띠가 든 타일에만 실린다 · 자세한 바이트는 tests/tiles.rs)을 풀면 지은 값.
    let uid_of: BTreeMap<u32, String> = {
        let db = Connection::open(&path).unwrap();
        let mut stmt = db.prepare("SELECT id,uid FROM periods").unwrap();
        let out = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
        out
    };
    let packs: Vec<i64> = layout["packs"].as_array().unwrap().iter().map(|x| x["id"].as_i64().unwrap()).collect();
    let chunks = (s.rows.total() + CHUNK_ROWS - 1) / CHUNK_ROWS;
    let mut carried = BTreeSet::new();
    for level in [4usize, 8, 11] {
        let xs: BTreeSet<i64> = spans.iter().flat_map(|(_, a, b)| [tile_of(*a, level), tile_of(a + (b - a) / 2, level), tile_of(*b, level)]).collect();
        for x in xs {
            for chunk in 0..chunks {
                let t = decode(&build_tile(&s, &TileRequest { level, x, chunk, packs: packs.clone(), filter: None, variants: None }).unwrap()).unwrap();
                for b in &t.bands {
                    let uid = uid_of[&b.id].as_str();
                    assert_eq!(i64::from(b.form), forms.get(uid).copied().unwrap_or(0), "단계 {level} 타일 {x} 묶음 {chunk}: {uid}의 form");
                    if b.form != 0 {
                        carried.insert(uid.to_owned());
                    }
                }
            }
        }
    }
    assert_eq!(carried, forms.keys().map(|u| u.to_string()).collect::<BTreeSet<_>>(), "타일에 실린 form ≠ 0 띠");
    drop(s);
    remove(&[&path]);
}

/// 자료가 놓인 분(띠 · 칸 · 사건 · 일반 항목의 시작 · 끝) — 견줄 가로 타일을 고른다(`tests/rowkeys.rs`와 같은 꼴).
fn content_minutes(store: &Store) -> Vec<i64> {
    let mut out = Vec::new();
    for sql in ["SELECT start,end FROM periods", "SELECT start,end FROM cells", "SELECT start,end FROM events WHERE start IS NOT NULL AND end IS NOT NULL",
        "SELECT start,end FROM items"] {
        let mut stmt = store.db.prepare(sql).unwrap();
        let mut rows = stmt.query([]).unwrap();
        while let Some(r) = rows.next().unwrap() {
            out.push(r.get::<_, i64>(0).unwrap());
            out.push(r.get::<_, i64>(1).unwrap());
        }
    }
    out.sort_unstable();
    out.dedup();
    out
}

/// 보기: 기본 · 변형 하나씩 · 첫 트랙을 끈 거르개 · 변형 + 중요도 거르개.
fn views(s: &Store) -> Vec<Value> {
    let tracks: Vec<i64> = s.db.prepare("SELECT id FROM tracks ORDER BY ord,id").unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    let keys: Vec<String> = s.db.prepare("SELECT key FROM variants ORDER BY key").unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    assert_eq!(keys.len(), 3, "장면의 변형 셋");
    let mut out = vec![json!({})];
    out.extend(keys.iter().map(|k| json!({ "variants": [k] })));
    out.push(json!({"filter":{"tracks_off":[tracks[0]]}}));
    out.push(json!({"variants":[keys[0]],"filter":{"min_importance":2}}));
    out
}

fn viewed(mut q: Value, view: &Value) -> Value {
    for (k, v) in view.as_object().unwrap() {
        q[k] = v.clone();
    }
    q
}

/// 옛 판 저장소(`old`)와 새 값을 지운 저장소(`zero`)의 답이 같은가 — layout · 타일 바이트 · 항목 기록 · same_year · info · 조회 목록이 든 canon.
fn same_answers(old: &Path, zero: &Path, tag: &str) {
    let (o, z) = (Store::open(old).unwrap(), Store::open(zero).unwrap());
    assert!(!o.period_form && !o.has_sphere_lines, "{tag}: 옛 판 저장소의 깃발 둘은 false");
    assert!(z.period_form && z.has_sphere_lines, "{tag}: 지운 저장소에는 열 · 표가 있다");
    assert_eq!(o.rows.is_identity(), z.rows.is_identity(), "{tag}: 줄 열쇠");
    // layout — sphereLines는 둘 다 빈 목록(표가 없음 · 표가 빔).
    let (lo, lz) = (call(&o, json!({"op":"layout"})), call(&z, json!({"op":"layout"})));
    assert_eq!(lo["sphereLines"], json!([]), "{tag}: 옛 판의 sphereLines");
    assert_eq!(lo, lz, "{tag}: layout 답");
    // info — 판(meta.schema)만 다르다.
    let (mut io, mut iz) = (call(&o, json!({"op":"info"})), call(&z, json!({"op":"info"})));
    let (vo, vz) = (io["meta"]["schema"].take(), iz["meta"]["schema"].take());
    assert_eq!((vo.as_str(), vz.as_str()), if o.rows.is_identity() { (Some("3"), Some("4")) } else { (Some("3.1"), Some("4.1")) }, "{tag}: 판");
    assert_eq!(io, iz, "{tag}: info(판 빼고)");
    // 항목 기록 — 모든 uid.
    let uids: Vec<String> = o.db.prepare("SELECT uid FROM entities ORDER BY uid").unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    assert!(uids.len() >= 10, "{tag}: 항목 기록 {}개", uids.len());
    for uid in &uids {
        let q = json!({"op":"entity","uid":uid});
        assert_eq!(call(&o, q.clone()), call(&z, q), "{tag}: entity {uid}");
    }
    // same_year · 타일 — 보기마다.
    let packs: Vec<i64> = o.db.prepare("SELECT id FROM packs ORDER BY id").unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    let minutes = content_minutes(&o);
    let times: BTreeSet<i64> = {
        let mut stmt = o.db.prepare("SELECT start,end FROM periods").unwrap();
        let spans: Vec<(i64, i64)> = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
        spans.into_iter().flat_map(|(a, b)| [a, a + (b - a) / 2, b]).collect()
    };
    let chunks = (o.rows.total() + CHUNK_ROWS - 1) / CHUNK_ROWS;
    let (mut years, mut tiles, mut bands) = (0, 0, 0);
    for view in views(&o) {
        for &at in &times {
            let q = viewed(json!({"op":"same_year","at":at,"end":at}), &view);
            let got = call(&o, q.clone());
            for b in got["tracks"].as_array().unwrap().iter().flat_map(|t| t["bands"].as_array().unwrap()) {
                assert_eq!(b["form"], json!(0), "{tag}: {q}의 띠 {}", b["uid"]);
                bands += 1;
            }
            assert_eq!(got, call(&z, q.clone()), "{tag}: {q}");
            years += 1;
        }
        let (vo, vz) = (o.variants_of(&view).unwrap(), z.variants_of(&view).unwrap());
        for level in [0usize, 4, 7, 8, 11, 14] {
            let xs: BTreeSet<i64> = minutes.iter().map(|m| tile_of(*m, level)).collect();
            for x in xs {
                for chunk in 0..chunks {
                    let a = build_tile(&o, &TileRequest { level, x, chunk, packs: packs.clone(), filter: o.filter_of(&view).unwrap(), variants: vo.clone() }).unwrap();
                    let b = build_tile(&z, &TileRequest { level, x, chunk, packs: packs.clone(), filter: z.filter_of(&view).unwrap(), variants: vz.clone() }).unwrap();
                    assert_eq!(a, b, "{tag}: 타일 {view} 단계 {level} x {x} 묶음 {chunk}");
                    tiles += 1;
                }
            }
        }
    }
    assert!(years > 50 && tiles > 500 && bands > 50, "{tag}: 견준 same_year {years} · 띠 {bands} · 타일 {tiles}");
    // 조회 목록이 든 같음의 눈(canon — 판은 싣지 않는다) — 위에서 손으로 고른 것 밖의 조회도.
    let opts = common::same::quick_q();
    assert!(canon_store(old, &opts).unwrap() == canon_store(zero, &opts).unwrap(), "{tag}: canon(조회 목록 포함)");
}

#[test]
fn 옛_판_저장소를_새_엔진이_읽으면_새_값을_지운_저장소와_답이_같다() {
    let _t = common::clock("schema4 옛 저장소");
    let fresh = built("old-base");
    let split = split_keys(&fresh, "old-base-split");
    for (base, version) in [(&fresh, "3"), (&split, "3.1")] {
        // 지우기 전에 새 값이 실제로 있어야 견줌이 뜻이 있다(장면의 form ≠ 0 띠 넷 · 줄 넷).
        assert_eq!(count(base, "SELECT count(*) FROM periods WHERE form<>0"), FORMS.len() as i64, "판 {version}의 바탕");
        assert_eq!(count(base, "SELECT count(*) FROM sphere_lines"), 4, "판 {version}의 바탕");
        let (old, zero) = (copy(base, &format!("old-{version}")), copy(base, &format!("zero-{version}")));
        common::strip_schema4(&old, version);
        Connection::open(&zero).unwrap().execute_batch("UPDATE periods SET form=0; DELETE FROM sphere_lines;").unwrap();
        same_answers(&old, &zero, &format!("판 {version}"));
        remove(&[&old, &zero]);
    }
    remove(&[&fresh, &split]);
}

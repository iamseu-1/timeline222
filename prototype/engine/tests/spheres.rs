//! 리메이크 조각 ② 문화권 단 — 배치의 `tracks[].sphere`와 최상위 `spheres`를 저장소(`tracks.sphere` · `meta.spheres`)에 싣고
//! `{"op":"layout"}` 답(트랙마다 `sphere` · 최상위 `spheres`)으로 앱까지 나른다.
//! 문화권이 없는 배치 · 열이 없는 옛 저장소는 빈 글자 · 빈 목록이고, 그 밖의 답과 타일은 그대로다. 이름은 모두 가상이다.
use archive_engine::legacy::{import_layout, import_with, ImportPlan};
use archive_engine::tile::{build_tile, TileRequest};
use archive_engine::Store;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::{Path, PathBuf};

/// 팩 파일(머리 52바이트 + zlib 본문 — `js/packfile.js`의 `seal`과 같은 꼴). 종류 1 DLC · 3 아카이브 배치.
fn seal(kind: u8, raw: &Value) -> Vec<u8> {
    let plain = serde_json::to_vec(raw).unwrap();
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(&plain).unwrap();
    let body = encoder.finish().unwrap();
    let mut head = b"HTPACK\r\n".to_vec();
    head.extend_from_slice(&[2, kind, 1, 0]);
    head.extend_from_slice(&(plain.len() as u32).to_le_bytes());
    head.extend_from_slice(&(body.len() as u32).to_le_bytes());
    let mut hash = Sha256::new();
    hash.update(&head);
    hash.update(&body);
    [head, hash.finalize().to_vec(), body].concat()
}

fn row() -> Value {
    json!({"height":40,"bandTop":0,"bandH":40,"dynTop":-1,"leadTop":-1,"cabTop":-1,"textTop":0,"lines":1,"railTop":-1,"organTop":-1})
}

/// 문화권이 없는 배치: 트랙 둘(옛 트랙) + 판 트랙 하나(`boards.tracks` — 문화권이 없다).
fn plan() -> Value {
    json!({
        "name":"문화권 검사", "packs":[{"id":"sphere-base","name":"문화권 검사"}],
        "categories":[], "epochs":[], "axis":[], "cells":[], "events":[], "items":[], "entities":[],
        "tracks":[
            {"key":"sp-river","name":"물결 땅","color":0xa0bcc5,"rows":[row()]},
            {"key":"sp-grass","name":"너른 들","color":0x9dbea8,"rows":[row()]}
        ],
        "periods":[
            {"uid":"sphere-base/river","track":0,"row":0,"start":0,"end":5256000,"name":"물결 나라","color":0xa0bcc5},
            {"uid":"sphere-base/grass","track":1,"row":0,"start":0,"end":5256000,"name":"너른 나라","color":0x9dbea8}
        ],
        "boards":{"tracks":[{"key":"__board:view:v1","name":"판","rows":[]}]}
    })
}

/// 문화권을 실은 배치: 첫 트랙은 `east-river`, 둘째는 `grass-sea`, 판 트랙은 그대로 없음.
fn with_spheres() -> Value {
    let mut p = plan();
    p["tracks"][0]["sphere"] = json!("east-river");
    p["tracks"][1]["sphere"] = json!("grass-sea");
    p["spheres"] = json!([
        {"id":"east-river","name":"물가 문화권","order":1,"count":1,"default":true},
        {"id":"grass-sea","name":"풀바다 문화권","order":2,"count":1,"default":false}
    ]);
    p
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-spheres-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// 노드 도구의 길(배치 JSON + 원본 전용 팩).
fn build(name: &str, plan: &Value) -> (PathBuf, PathBuf) {
    let dir = scratch(name);
    let pack = dir.join("pack.htpack");
    std::fs::write(&pack, seal(1, &json!({"format":"history-timeline-dlc","id":"sphere-base","name":"문화권 검사"}))).unwrap();
    let file = dir.join("layout.json");
    std::fs::write(&file, serde_json::to_vec(plan).unwrap()).unwrap();
    let target = dir.join("archive.db");
    import_layout(&pack, &file, &target, &[]).unwrap();
    (dir, target)
}

fn layout(path: &Path) -> Value {
    Store::open(path).unwrap().call(&json!({"op":"layout"})).unwrap()
}

fn spheres_of(answer: &Value) -> Vec<&str> {
    answer["tracks"].as_array().unwrap().iter().map(|t| t["sphere"].as_str().expect("트랙마다 sphere 글")).collect()
}

fn meta(path: &Path) -> Value {
    Store::open(path).unwrap().call(&json!({"op":"info"})).unwrap()["meta"].clone()
}

/// 문화권 값을 걷어 낸 답 — 문화권 밖의 답이 그대로인지 견줄 때 쓴다.
fn without_spheres(mut answer: Value) -> Value {
    answer.as_object_mut().unwrap().remove("spheres");
    for t in answer["tracks"].as_array_mut().unwrap() {
        t.as_object_mut().unwrap().remove("sphere");
        t.as_object_mut().unwrap().remove("sphere_at"); // 문화권 자리(한 벌 P3-18)도 문화권 몫이다
    }
    answer
}

#[test]
fn 배치의_문화권이_layout_답에_그대로_돌아온다() {
    let (dir, target) = build("given", &with_spheres());
    let answer = layout(&target);
    assert_eq!(spheres_of(&answer), vec!["east-river", "grass-sea", ""], "판 트랙은 문화권이 없다");
    assert_eq!(answer["spheres"], with_spheres()["spheres"], "문화권 목록은 원소 그대로 · 차례 그대로");
    assert_eq!(serde_json::from_str::<Value>(meta(&target)["spheres"].as_str().unwrap()).unwrap(), with_spheres()["spheres"], "meta에 JSON 글로");
    let store = Store::open(&target).unwrap();
    assert!(store.track_sphere, "새 저장소에는 문화권 열이 있다");
    let stored: Vec<String> = store.db.prepare("SELECT sphere FROM tracks ORDER BY ord").unwrap()
        .query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
    assert_eq!(stored, vec!["east-river", "grass-sea", ""]);
    drop(store);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 문화권이_없으면_빈_글자와_빈_목록이고_나머지_답과_타일은_그대로다() {
    let (plain_dir, plain) = build("absent", &plan());
    let answer = layout(&plain);
    assert_eq!(spheres_of(&answer), vec!["", "", ""]);
    assert_eq!(answer["spheres"], json!([]));
    assert!(meta(&plain).get("spheres").is_none(), "목록이 없으면 meta 열쇠를 만들지 않는다");
    // 빈 목록 · 빈 글자로 실려 와도 같다.
    let mut empty = plan();
    empty["spheres"] = json!([]);
    empty["tracks"][0]["sphere"] = json!("");
    let (empty_dir, empty_target) = build("empty", &empty);
    assert_eq!(layout(&empty_target), answer);
    assert!(meta(&empty_target).get("spheres").is_none());
    // 문화권을 실어도 그 밖의 layout 답 · 줄 조회 · 타일은 1바이트도 달라지지 않는다.
    let (given_dir, given) = build("same", &with_spheres());
    assert_eq!(without_spheres(layout(&given)), without_spheres(answer));
    let (a, b) = (Store::open(&plain).unwrap(), Store::open(&given).unwrap());
    let near = json!({"op":"rows_near","near":[0,5256000],"far":[0,5256000],"fade":0,"packs":[1]});
    assert_eq!(a.call(&near).unwrap(), b.call(&near).unwrap());
    for level in [4usize, 8, 12, 14] {
        let req = TileRequest { level, x: 0, chunk: 0, packs: vec![1], filter: None, variants: None };
        assert_eq!(build_tile(&a, &req).unwrap(), build_tile(&b, &req).unwrap(), "타일 단계 {level}");
    }
    drop((a, b));
    for dir in [plain_dir, empty_dir, given_dir] {
        std::fs::remove_dir_all(dir).unwrap();
    }
}

#[test]
fn 문화권_열이_없는_옛_저장소도_열리고_빈_글자를_준다() {
    let (plain_dir, plain) = build("old-plain", &plan());
    let (dir, old) = build("old", &with_spheres());
    // 열과 meta 열쇠를 지워 옛 저장소를 흉내 낸다(읽기 전용으로 열기 전에).
    let db = rusqlite::Connection::open(&old).unwrap();
    db.execute_batch("ALTER TABLE tracks DROP COLUMN sphere; DELETE FROM meta WHERE key='spheres';").unwrap();
    drop(db);
    let store = Store::open(&old).unwrap();
    assert!(!store.track_sphere, "옛 저장소에는 문화권 열이 없다");
    let answer = store.call(&json!({"op":"layout"})).unwrap();
    assert_eq!(spheres_of(&answer), vec!["", "", ""]);
    assert_eq!(answer["spheres"], json!([]));
    assert_eq!(answer, layout(&plain), "문화권 없는 새 저장소와 같은 답");
    drop(store);
    for dir in [plain_dir, dir] {
        std::fs::remove_dir_all(dir).unwrap();
    }
}

#[test]
fn 메이커의_htlayout도_문화권을_나른다() {
    let dir = scratch("htlayout");
    let file = dir.join("배치.htlayout");
    std::fs::write(&file, seal(3, &with_spheres())).unwrap();
    let target = dir.join("archive.db");
    // 원본 없이(Node 없는 길 — 계약 2-7) 짓는다.
    import_with(&ImportPlan { layout: &file, out: Some(&target), base: None, originals: Vec::new(), from_store: None, check_only: false }).unwrap();
    let answer = layout(&target);
    assert_eq!(spheres_of(&answer), vec!["east-river", "grass-sea", ""]);
    assert_eq!(answer["spheres"], with_spheres()["spheres"]);
    // 배치 JSON(노드 도구)의 길과 같은 문화권 답.
    let (json_dir, json_target) = build("htlayout-json", &with_spheres());
    let other = layout(&json_target);
    assert_eq!((&answer["spheres"], spheres_of(&answer)), (&other["spheres"], spheres_of(&other)));
    for dir in [dir, json_dir] {
        std::fs::remove_dir_all(dir).unwrap();
    }
}

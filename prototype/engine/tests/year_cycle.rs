//! D4 간지 설정 — 내보내기의 순환과 DLC 차례를 진짜 저장소의 meta로 나른다.
//! 설정 없는 저장소·타일·기존 조회는 그대로이고, 설정을 적은 DLC를 끌 때 앱이 다음 후보를 고를 수 있어야 한다.
use archive_engine::legacy::import_layout;
use archive_engine::tile::{build_tile, TileRequest};
use archive_engine::Store;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::PathBuf;

fn htpack(raw: &Value) -> Vec<u8> {
    let plain = serde_json::to_vec(raw).unwrap();
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(&plain).unwrap();
    let body = encoder.finish().unwrap();
    let mut head = b"HTPACK\r\n".to_vec();
    head.extend_from_slice(&[2, 1, 1, 0]);
    head.extend_from_slice(&(plain.len() as u32).to_le_bytes());
    head.extend_from_slice(&(body.len() as u32).to_le_bytes());
    let mut hash = Sha256::new();
    hash.update(&head);
    hash.update(&body);
    [head, hash.finalize().to_vec(), body].concat()
}

fn plan() -> Value {
    // 지은 날(`meta.now` — 계획 P4 과제 5a)을 굳힌다: 두 저장소의 메타를 통째로 견주는데, 없으면 지은 시각(초)이 적혀 초가 바뀌는 순간 갈린다.
    json!({
        "name":"순환 검사", "now":"2026-10-16T00:00:00Z", "packs":[{"id":"cycle-base","name":"순환 검사"}],
        "categories":[], "epochs":[], "axis":[], "cells":[], "events":[], "items":[], "entities":[],
        "tracks":[{"key":"cycle-land","name":"샘물 땅","color":0xa0bcc5,"dynasty":0,"leader":0,"cabinet":0,
            "rows":[{"height":40,"bandTop":0,"bandH":40,"dynTop":-1,"leadTop":-1,"cabTop":-1,"textTop":0,"lines":1,"railTop":-1,"organTop":-1}]}],
        "periods":[{"uid":"cycle-base/first","track":0,"row":0,"start":0,"end":5256000,"name":"샘물 나라","color":0xa0bcc5}]
    })
}

fn build(name: &str, plan: &Value) -> (PathBuf, Store) {
    let dir = std::env::temp_dir().join(format!("archive-year-cycle-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let packs: Vec<_> = plan["packs"].as_array().unwrap().iter().enumerate().map(|(i, pack)| {
        let path = dir.join(format!("pack-{i}.htpack"));
        std::fs::write(&path, htpack(&json!({"format":"history-timeline-dlc","id":pack["id"],"name":pack["name"]}))).unwrap();
        path
    }).collect();
    let file = dir.join("layout.json");
    std::fs::write(&file, serde_json::to_vec(plan).unwrap()).unwrap();
    let target = dir.join("archive.db");
    let extra: Vec<_> = packs.iter().skip(1).map(|p| p.as_path()).collect();
    import_layout(&packs[0], &file, &target, &extra).unwrap();
    let store = Store::open(&target).unwrap();
    (dir, store)
}

fn meta(store: &Store) -> Value {
    store.call(&json!({"op":"info"})).unwrap()["meta"].clone()
}

fn stored(meta: &Value, key: &str) -> Value {
    serde_json::from_str(meta[key].as_str().unwrap()).unwrap()
}

fn release(dir: PathBuf, store: Store) {
    drop(store);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 설정이_없으면_순환_열쇠를_만들지_않는다() {
    let (dir, store) = build("absent", &plan());
    let answer = meta(&store);
    assert!(answer.get("year_cycle").is_none());
    assert!(answer.get("year_cycles").is_none());
    release(dir, store);
}

#[test]
fn 이름과_첫해와_줄제목을_싣되_기존_조회와_타일은_그대로다() {
    let (plain_dir, plain) = build("plain", &plan());
    let mut custom = plan();
    let cycle = json!({"names":["샘물","바람","새벽"],"start":-2,"label":"세차","packId":"cycle-base","packName":"순환 검사"});
    custom["yearCycle"] = cycle.clone();
    custom["yearCycles"] = json!([cycle]);
    let (dir, store) = build("custom", &custom);
    let mut answer = meta(&store);
    assert_eq!(stored(&answer, "year_cycle"), custom["yearCycle"]);
    assert_eq!(stored(&answer, "year_cycles"), custom["yearCycles"]);
    answer.as_object_mut().unwrap().remove("year_cycle");
    answer.as_object_mut().unwrap().remove("year_cycles");
    assert_eq!(answer, meta(&plain), "순환 밖의 메타는 그대로");
    for query in [json!({"op":"layout"}), json!({"op":"rows_near","near":[0,5256000],"far":[0,5256000],"fade":0,"packs":[1]})] {
        assert_eq!(plain.call(&query).unwrap(), store.call(&query).unwrap(), "기존 조회 {query}");
    }
    for level in [4usize, 8, 12, 14] {
        let req = TileRequest { level, x: 0, chunk: 0, packs: vec![1], filter: None, variants: None };
        assert_eq!(build_tile(&plain, &req).unwrap(), build_tile(&store, &req).unwrap(), "기존 타일 단계 {level}");
    }
    release(dir, store);
    release(plain_dir, plain);
}

#[test]
fn 끈_설정과_다음_자료집의_순환을_차례대로_보존한다() {
    let mut custom = plan();
    custom["packs"].as_array_mut().unwrap().push(json!({"id":"cycle-next","name":"다음 순환"}));
    let off = json!({"off":true,"packId":"cycle-base","packName":"순환 검사"});
    let next = json!({"names":["온빛","찬빛"],"start":4,"packId":"cycle-next","packName":"다음 순환"});
    custom["yearCycle"] = off.clone();
    custom["yearCycles"] = json!([off, next]);
    let (dir, store) = build("off-order", &custom);
    let answer = meta(&store);
    assert_eq!(stored(&answer, "year_cycle"), custom["yearCycle"]);
    assert_eq!(stored(&answer, "year_cycles"), custom["yearCycles"]);
    let layout = store.call(&json!({"op":"layout"})).unwrap();
    assert_eq!(layout["packs"][0]["key"], "cycle-base");
    assert_eq!(layout["packs"][1]["key"], "cycle-next");
    release(dir, store);
}

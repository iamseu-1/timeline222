//! 문서 그림 바이트(형식 3 images — 10건 D3)의 길: 가져오기 JSON의 겉 열쇠 `blobs[]` → 저장소의 `blobs` 표 →
//! `Store::blob` · 조회 명령 `{"op":"blob"}`(base64) · FFI `archive_blob`(바이트 그대로 · `archive_tile`과 같은 꼴).
//! 그림이 없는 배치의 답(가져온 수)은 예전 그대로이고, `blobs` 표가 없는 옛 저장소에서는 그림이 '없음'이다(판 '3' 그대로).
//! 이름은 모두 가상이다.
use archive_engine::legacy::import_layout;
use archive_engine::{archive_blob, archive_call, archive_free, archive_free_bytes, base64_decode, base64_encode, Store};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::ffi::{CStr, CString};
use std::io::Write;
use std::path::PathBuf;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-blobs-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

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

/// 작은 가짜 그림 바이트(png 머리 + 차례 바이트) — 내용은 보지 않고 바이트가 그대로 오가는지만 본다.
fn picture(n: usize, seed: u8) -> Vec<u8> {
    let mut b = b"\x89PNG\r\n\x1a\n".to_vec();
    b.extend((0..n).map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed)));
    b
}

fn layout(blobs: Option<Value>) -> Value {
    let mut plan = json!({
        "name": "그림 검사",
        "packs": [{"id":"img-base","name":"그림 검사"}, {"id":"img-more","name":"더 얹은 그림"}],
        "tracks": [{"name":"바다","rows":[{"height":120,"bandTop":19,"bandH":101,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1}]}],
        "periods": [{"uid":"img-base/p","track":0,"row":0,"start":0,"end":1000,"fuzzy":0,"color":0xa0bcc5,"name":"물결국"}],
        "cells": [], "events": [], "items": [], "epochs": [], "axis": [], "categories": [],
        "entities": [
            {"uid":"doc:img-base/p","kind":"doc","pack":0,"json":"{\"key\":\"img-base/p\",\"title\":\"물결국\",\"body\":\"[[파일:바다.webp]]\",\"images\":{\"바다.webp\":{\"key\":\"img:img-base/sea\",\"mime\":\"image/webp\",\"w\":800,\"h\":450}}}"}
        ]
    });
    if let Some(b) = blobs {
        plan["blobs"] = b;
    }
    plan
}

fn import(name: &str, plan: &Value) -> (PathBuf, Value) {
    let dir = scratch(name);
    let pack = dir.join("그림.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"img-base","name":"그림 검사"}))).unwrap();
    let more = dir.join("더.htpack");
    std::fs::write(&more, htpack(&json!({"format":"history-timeline-dlc","id":"img-more","name":"더 얹은 그림"}))).unwrap();
    let file = dir.join("layout.json");
    std::fs::write(&file, serde_json::to_vec(plan).unwrap()).unwrap();
    let target = dir.join("out").join("archive.db");
    let counts = import_layout(&pack, &file, &target, &[&more]).unwrap();
    (target, counts)
}

#[test]
fn base64는_되돌릴_수_있고_틀린_글자는_거절한다() {
    for n in 0..70 {
        let bytes: Vec<u8> = (0..n).map(|i| (i * 37 + 11) as u8).collect();
        let text = base64_encode(&bytes);
        assert_eq!(text.len() % 4, 0, "{n}바이트의 base64 길이가 4의 배수가 아님");
        assert_eq!(base64_decode(&text).unwrap(), bytes, "{n}바이트 되돌리기");
    }
    assert_eq!(base64_encode(b"Man"), "TWFu");
    assert_eq!(base64_encode(b"Ma"), "TWE=");
    assert_eq!(base64_encode(b"M"), "TQ==");
    assert!(base64_decode("TW*u").is_none());
    assert!(base64_decode("T").is_none(), "한 글자만 남은 꼬리는 틀림");
    assert!(base64_decode("TQ===").is_none(), "채움이 셋은 틀림");
}

#[test]
fn 그림이_없는_배치는_답도_표도_예전_그대로다() {
    let (target, counts) = import("none", &layout(None));
    assert!(counts.get("blobs").is_none(), "그림이 없는데 가져온 수에 blobs가 생김: {counts}");
    let s = Store::open(&target).unwrap();
    assert!(s.has_blobs);
    assert_eq!(s.db.query_row("SELECT count(*) FROM blobs", [], |r| r.get::<_, i64>(0)).unwrap(), 0);
    assert!(s.blob("img:img-base/sea").unwrap().is_none());
    let err = s.call(&json!({"op":"blob","key":"img:img-base/sea"})).unwrap_err().to_string();
    assert!(err.contains("그림이 저장소에 없습니다"), "{err}");
}

#[test]
fn 그림_바이트는_열쇠로_그대로_돌아오고_자료집에_붙는다() {
    let sea = picture(5000, 3);
    let isle = picture(300, 9);
    let blobs = json!([
        {"key":"img:img-base/sea","pack":0,"mime":"image/webp","data":base64_encode(&sea)},
        {"key":"img:img-more/isle","pack":1,"mime":"image/png","data":base64_encode(&isle)}
    ]);
    let (target, counts) = import("some", &layout(Some(blobs)));
    assert_eq!(counts["blobs"], 2);
    let s = Store::open(&target).unwrap();
    let (mime, bytes) = s.blob("img:img-base/sea").unwrap().unwrap();
    assert_eq!((mime.as_str(), bytes.as_slice()), ("image/webp", sea.as_slice()));
    let packs: Vec<(String, i64)> = s.db.prepare("SELECT key,pack FROM blobs ORDER BY key").unwrap().query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    assert_eq!(packs, vec![("img:img-base/sea".to_owned(), 1), ("img:img-more/isle".to_owned(), 2)], "pack 순번 → 자료집 번호(1부터)");
    let answer = s.call(&json!({"op":"blob","key":"img:img-more/isle"})).unwrap();
    assert_eq!(answer["mime"], "image/png");
    assert_eq!(answer["bytes"], isle.len());
    assert_eq!(base64_decode(answer["data"].as_str().unwrap()).unwrap(), isle);
    // 문서 기록은 그대로 실려 있고(엔진은 뜻을 모르고 나른다) 그 열쇠로 그림을 찾는다.
    let doc = s.call(&json!({"op":"entity","uid":"doc:img-base/p"})).unwrap();
    let rec: Value = serde_json::from_str(doc["json"].as_str().unwrap()).unwrap();
    assert_eq!(rec["images"]["바다.webp"]["key"], "img:img-base/sea");
    assert!(s.blob(rec["images"]["바다.webp"]["key"].as_str().unwrap()).unwrap().is_some());

    // FFI: 저장소를 열고 바이트 그대로 받기 · 없는 열쇠는 null + 까닭.
    unsafe {
        let ask = |q: Value| -> Value {
            let input = CString::new(q.to_string()).unwrap();
            let out = archive_call(input.as_ptr());
            let v: Value = serde_json::from_str(CStr::from_ptr(out).to_str().unwrap()).unwrap();
            archive_free(out);
            v
        };
        assert_eq!(ask(json!({"op":"open","path":target.to_string_lossy()}))["ok"], true);
        let mut len = 0usize;
        let req = CString::new(json!({"key":"img:img-base/sea"}).to_string()).unwrap();
        let ptr = archive_blob(req.as_ptr(), &mut len);
        assert!(!ptr.is_null());
        assert_eq!(std::slice::from_raw_parts(ptr, len), sea.as_slice());
        archive_free_bytes(ptr, len);
        let missing = CString::new(json!({"key":"img:img-base/없음"}).to_string()).unwrap();
        let ptr = archive_blob(missing.as_ptr(), &mut len);
        assert!(ptr.is_null() && len == 0);
        assert!(ask(json!({"op":"last_error"}))["data"]["error"].as_str().unwrap().contains("그림이 저장소에 없습니다"));
        let bad = CString::new("{}").unwrap();
        assert!(archive_blob(bad.as_ptr(), &mut len).is_null());
        assert_eq!(ask(json!({"op":"close"}))["ok"], true);
    }
}

#[test]
fn 틀린_그림_바이트는_가져오기를_멈춘다() {
    let dir = scratch("bad");
    let pack = dir.join("그림.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"img-base","name":"그림 검사"}))).unwrap();
    let more = dir.join("더.htpack");
    std::fs::write(&more, htpack(&json!({"format":"history-timeline-dlc","id":"img-more","name":"더 얹은 그림"}))).unwrap();
    for (name, blobs) in [
        ("글자", json!([{"key":"img:img-base/sea","pack":0,"mime":"image/webp","data":"**"}])),
        ("종류", json!([{"key":"img:img-base/sea","pack":0,"mime":"text/plain","data":"TWFu"}])),
        ("열쇠", json!([{"key":"","pack":0,"mime":"image/png","data":"TWFu"}])),
    ] {
        let file = dir.join(format!("{name}.json"));
        std::fs::write(&file, serde_json::to_vec(&layout(Some(blobs))).unwrap()).unwrap();
        let target = dir.join(name).join("archive.db");
        let err = import_layout(&pack, &file, &target, &[&more]).unwrap_err().to_string();
        assert!(err.contains("그림 바이트"), "{name}: {err}");
    }
}

#[test]
fn 그림_표가_없는_옛_저장소에서는_그림이_없음이다() {
    let (target, _) = import("old", &layout(Some(json!([{"key":"img:img-base/sea","pack":0,"mime":"image/webp","data":base64_encode(&picture(10, 1))}]))));
    {
        let db = rusqlite::Connection::open(&target).unwrap();
        db.execute_batch("DROP TABLE blobs").unwrap();
    }
    let s = Store::open(&target).unwrap();
    assert!(!s.has_blobs);
    assert!(s.blob("img:img-base/sea").unwrap().is_none());
    assert!(s.call(&json!({"op":"blob","key":"img:img-base/sea"})).is_err());
}

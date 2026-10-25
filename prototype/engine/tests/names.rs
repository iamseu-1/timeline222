//! 원어 병기 · 글꼴(10건 3 · 9 — 갈래 D2)의 엔진 조회 둘 — `names_info`(이름 목록이 있는 자료집 · 글꼴 목록) · `font_data`(품은 원본에서 꺼낸 글꼴 파일).
//! 스키마 판 '3' 그대로(표 · 열을 더하지 않음)라 옛 저장소(이름 목록 · 글꼴이 없는 것)는 빈 목록으로 답하는지도 본다.
//! 검사 자료는 모두 가상이다(별여울국 · 달글씨 …). 전용 팩은 검사 안에서 `sha2` · `flate2`로 만든다(`js/packfile.js`의 `seal`과 같은 꼴 — htlayout.rs와 같다).
use archive_engine::legacy::{import_layout, import_with, ImportPlan};
use archive_engine::{archive_call, archive_free, Store, DAY};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::ffi::{CStr, CString};
use std::io::Write;
use std::path::PathBuf;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-names-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn seal(kind: u8, plain: &[u8]) -> Vec<u8> {
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(plain).unwrap();
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

/// 글꼴 파일 자리의 바이트(내용은 검사만 — 엔진은 글꼴을 읽지 않고 base64를 그대로 나른다).
const MOON_B64: &str = "AAEAAAAKAIAAAwAgT1MvMkiFTJI=";
const STAR_B64: &str = "d09GMgABAAAAAAQ=";

fn base_dlc() -> Value {
    json!({"format":"history-timeline-dlc","formatVersion":3,"id":"base-pack","name":"기본 기록집","version":"1.0.0"})
}

/// 얹은 DLC 원본 — 글꼴 둘(달글씨 ttf · 별글씨 woff2)과 꼴이 틀린 글꼴 하나(검사용 — 메이커는 이런 것을 싣지 않는다).
fn extra_dlc() -> Value {
    json!({"format":"history-timeline-dlc","formatVersion":3,"id":"extra-pack","name":"얹은 기록집","version":"2.0.0","fonts":[
        {"id":"moon","family":"달글씨","src":format!("data:font/ttf;base64,{MOON_B64}"),"license":"검사용","scripts":["Qaaa"],"ranges":["U+F1A00-F1A0B"]},
        {"id":"star","family":"별글씨","src":format!("data:font/woff2;base64,{STAR_B64}"),"license":"검사용"},
        {"id":"bent","family":"굽은 글씨","src":"data:image/png;base64,AAAA","license":"검사용"}
    ]})
}

fn row(height: i64) -> Value {
    json!({"height":height,"bandTop":19,"bandH":height-19,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1,
        "kind":0,"groupStart":0,"scopePad":0,"phase":1,"rank":0,"cats":[],"fig":1,"dep":0,"zones":0,"hem":0})
}

/// 배치 하나: 기본팩의 띠 둘(하나는 이름 목록 x_names · 칸의 이름 x_cellNames) + 얹은 DLC의 띠 하나와 글꼴 기록 넷(기록만 있고 원본에 없는 것 하나 포함).
/// `names`가 거짓이면 형식 3 전의 배치(이름 목록 · 글꼴 기록 없음).
fn layout(names: bool) -> Value {
    let year = 525_600i64;
    let mut events = Vec::new();
    for i in 0..60i64 {
        let on_extra = i % 4 == 3;
        let start = -1_000 * year + i * 31 * year + (i % 5) * DAY;
        let mut e = json!({"uid": if on_extra { format!("extra-pack/e{i}") } else { format!("e{i}") }, "track": i64::from(on_extra), "row": 0, "start": start,
            "end": start, "importance": 1 + i % 3, "title": format!("가상 사건 {i}"), "body": "", "look": i % 3, "label":"", "rail":0,
            "band": if on_extra { "extra-pack/p-c" } else { "p-a" }});
        if on_extra {
            e["pack"] = json!(1);
        }
        events.push(e);
    }
    let font = |id: &str, family: &str, extra: Value| {
        let mut body = json!({"id":id,"family":family,"license":"검사용","src":{"$bytes":40},"itemKind":"font","uid":format!("font:{id}"),"packId":"extra-pack","warnings":[]});
        for (k, v) in extra.as_object().unwrap() {
            body[k] = v.clone();
        }
        json!({"uid":format!("font:{id}"),"kind":"font","pack":1,"json":body.to_string()})
    };
    let mut entities = vec![
        if names {
            json!({"uid":"p-a","kind":"period","json":json!({"uid":"p-a","name":"별여울국","x_names":{"main":[{"text":"星灘國","lang":"lzh","tag":"원어 · 한문"}]},
                "x_nameHead":{"first":{"text":"星灘國","lang":"lzh","langName":"한문","kind":"원어"}}}).to_string()})
        } else {
            json!({"uid":"p-a","kind":"period","json":"{\"uid\":\"p-a\",\"name\":\"별여울국\"}"})
        },
        json!({"uid":"p-b","kind":"period","json":"{\"uid\":\"p-b\",\"name\":\"해솔국\"}"}),
        if names {
            json!({"uid":"extra-pack/p-c","kind":"period","pack":1,"json":json!({"uid":"extra-pack/p-c","name":"은빛 나루",
                "x_cellNames":{"leader:0":{"main":[{"text":"銀津","lang":"lzh","tag":"원어 · 한문"}]}}}).to_string()})
        } else {
            json!({"uid":"extra-pack/p-c","kind":"period","pack":1,"json":"{\"uid\":\"extra-pack/p-c\",\"name\":\"은빛 나루\"}"})
        },
    ];
    if names {
        entities.push(font("moon", "달글씨", json!({"scripts":["Qaaa"],"ranges":["U+F1A00-F1A0B"],"note":"가상 문자"})));
        entities.push(font("star", "별글씨", json!({})));
        entities.push(font("bent", "굽은 글씨", json!({})));
        entities.push(font("gone", "사라진 글씨", json!({})));
    }
    json!({
        "name": "검사 조합",
        "packs": [{"id":"base-pack","name":"기본 기록집","version":"1.0.0"},{"id":"extra-pack","name":"얹은 기록집","version":"2.0.0"}],
        "categories": [{"key":"govern","name":"다스림","color":0x8f7fb0}],
        "tracks": [
            {"key":"t-first","name":"첫 트랙","color":0xc8b193,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,"rows":[row(126), row(140)],"groups":[]},
            {"key":"t-second","name":"둘째 트랙","pack":1,"rows":[row(133)]}
        ],
        "epochs": [],
        "axis": [],
        "periods": [
            {"uid":"p-a","track":0,"row":0,"start":-1_000 * year,"end":-1 * year,"color":0xa0bcc5,"name":"별여울국"},
            {"uid":"p-b","track":0,"row":1,"start":-900 * year,"end":900 * year,"color":0x9dbea8,"name":"해솔국"},
            {"uid":"extra-pack/p-c","track":1,"row":0,"start":-1_000 * year,"end":1_000 * year,"color":0xd7c18e,"name":"은빛 나루","pack":1}
        ],
        "cells": [{"period":"extra-pack/p-c","kind":1,"start":-1_000 * year,"end":0,"name":"나루 지기"}],
        "events": events,
        "items": [],
        "entities": entities,
        "rowLabels": [{"period":"p-a","track":0,"row":0,"kind":0,"name":"별여울국","color":0xa0bcc5,"orig":[{"text":"星灘國"}]}]
    })
}

/// 저장소 하나를 짓는다 — `with_extra_original`이 거짓이면 얹은 DLC의 원본 없이(Node 없이 .htlayout만 받은 것과 같다).
fn store(name: &str, names: bool, with_extra_original: bool) -> PathBuf {
    let dir = scratch(name);
    let base = dir.join("기본.htpack");
    std::fs::write(&base, seal(1, &serde_json::to_vec(&base_dlc()).unwrap())).unwrap();
    let extra = dir.join("얹은.htpack");
    std::fs::write(&extra, seal(1, &serde_json::to_vec(&extra_dlc()).unwrap())).unwrap();
    let plan = dir.join("배치.json");
    std::fs::write(&plan, serde_json::to_vec(&layout(names)).unwrap()).unwrap();
    let target = dir.join("archive.db");
    if with_extra_original {
        import_layout(&base, &plan, &target, &[&extra]).unwrap();
    } else {
        let answer = import_with(&ImportPlan { layout: &plan, out: Some(&target), base: Some(&base), originals: Vec::new(), from_store: None, check_only: false }).unwrap();
        assert_eq!(answer["packs"][1]["original"], 0, "얹은 DLC는 원본 없이");
    }
    target
}

fn pack_id(s: &Store, key: &str) -> i64 {
    let keys: Value = serde_json::from_str(&s.db.query_row("SELECT value FROM meta WHERE key='pack_keys'", [], |r| r.get::<_, String>(0)).unwrap()).unwrap();
    keys.as_object().unwrap().iter().find(|(_, v)| v.as_str() == Some(key)).map(|(k, _)| k.parse().unwrap()).unwrap()
}

#[test]
fn names_info_lists_packs_with_names_and_fonts() {
    let path = store("info", true, true);
    let s = Store::open(&path).unwrap();
    let (base, extra) = (pack_id(&s, "base-pack"), pack_id(&s, "extra-pack"));
    let info = s.call(&json!({"op":"names_info"})).unwrap();
    // 이름 목록: 기본팩은 띠의 x_names, 얹은 DLC는 칸의 x_cellNames로 — 둘 다 든다(자료집 번호 차례).
    assert_eq!(info["packs"], json!([base, extra]));
    // 글꼴: 기록의 본문에서 — 파일 크기 자리({"$bytes"}) · 내부 칸(itemKind · warnings …)은 싣지 않는다. 차례는 자료집 → uid.
    assert_eq!(info["fonts"], json!([
        {"uid":"font:bent","pack":extra,"id":"bent","family":"굽은 글씨","license":"검사용"},
        {"uid":"font:gone","pack":extra,"id":"gone","family":"사라진 글씨","license":"검사용"},
        {"uid":"font:moon","pack":extra,"id":"moon","family":"달글씨","license":"검사용","scripts":["Qaaa"],"ranges":["U+F1A00-F1A0B"],"note":"가상 문자"},
        {"uid":"font:star","pack":extra,"id":"star","family":"별글씨","license":"검사용"}
    ]));
}

#[test]
fn names_info_is_empty_for_old_stores() {
    // 형식 3 전의 배치(이름 목록 · 글꼴 기록 없음) — 동아시아 · 월흔해와 같다. 새 표 · 열이 없으니 옛 저장소도 같은 답이다.
    let path = store("old", false, true);
    let s = Store::open(&path).unwrap();
    assert_eq!(s.call(&json!({"op":"names_info"})).unwrap(), json!({"packs":[],"fonts":[]}));
    assert_eq!(s.call(&json!({"op":"font_data","uids":["font:moon"]})).unwrap(),
        json!({"fonts":[],"missing":[{"uid":"font:moon","why":"그 글꼴 기록이 없습니다"}]}));
}

#[test]
fn font_data_reads_the_kept_original() {
    let path = store("data", true, true);
    let s = Store::open(&path).unwrap();
    let answer = s.call(&json!({"op":"font_data","uids":["font:moon","font:star","font:moon","font:bent","font:gone","font:none"]})).unwrap();
    // 같은 이름을 두 번 물어도 한 번 — base64는 원본 그대로(엔진은 풀지 않는다).
    assert_eq!(answer["fonts"], json!([
        {"uid":"font:moon","family":"달글씨","mime":"font/ttf","data":MOON_B64},
        {"uid":"font:star","family":"별글씨","mime":"font/woff2","data":STAR_B64}
    ]));
    assert_eq!(answer["missing"], json!([
        {"uid":"font:bent","why":"글꼴 파일이 data:font/…;base64 꼴이 아닙니다"},
        {"uid":"font:gone","why":"원본에 그 글꼴이 없습니다"},
        {"uid":"font:none","why":"그 글꼴 기록이 없습니다"}
    ]));
    // 한도와 꼴.
    let many: Vec<String> = (0..33).map(|i| format!("font:f{i}")).collect();
    assert_eq!(s.call(&json!({"op":"font_data","uids":many})).unwrap_err().to_string(), "글꼴은 한 번에 32개까지 묻습니다");
    assert_eq!(s.call(&json!({"op":"font_data"})).unwrap_err().to_string(), "글꼴 이름 목록(uids) 누락");
}

#[test]
fn font_data_without_original_says_why() {
    // Node 없이 .htlayout만 받은 DLC — 원본이 없어 글꼴 파일을 꺼낼 수 없다(앱은 기본 글꼴 + 다음 표기로 그린다).
    let path = store("bare", true, false);
    let s = Store::open(&path).unwrap();
    assert_eq!(s.call(&json!({"op":"names_info"})).unwrap()["fonts"].as_array().unwrap().len(), 4, "목록은 기록에서 읽으므로 그대로");
    assert_eq!(s.call(&json!({"op":"font_data","uids":["font:moon","font:star"]})).unwrap(), json!({"fonts":[],"missing":[
        {"uid":"font:moon","why":"원본 없이 넣은 DLC라 글꼴 파일을 꺼낼 수 없습니다"},
        {"uid":"font:star","why":"원본 없이 넣은 DLC라 글꼴 파일을 꺼낼 수 없습니다"}
    ]}));
}

#[test]
fn ffi_answers_both_ops() {
    // 앱이 쓰는 길(archive_call — 열기 · 묻기). 작업자 하나가 저장소 하나를 연다.
    let path = store("ffi", true, true);
    let call = |q: Value| -> Value {
        let input = CString::new(q.to_string()).unwrap();
        let ptr = unsafe { archive_call(input.as_ptr()) };
        let text = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_owned();
        unsafe { archive_free(ptr) };
        serde_json::from_str(&text).unwrap()
    };
    assert_eq!(call(json!({"op":"open","path":path.to_str().unwrap()}))["ok"], true);
    let info = call(json!({"op":"names_info"}));
    assert_eq!(info["ok"], true);
    assert_eq!(info["data"]["fonts"].as_array().unwrap().len(), 4);
    let data = call(json!({"op":"font_data","uids":["font:moon"]}));
    assert_eq!(data["data"]["fonts"][0]["data"], MOON_B64);
    call(json!({"op":"close"}));
}

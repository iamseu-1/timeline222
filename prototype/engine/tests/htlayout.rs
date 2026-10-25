//! 메이커의 아카이브 배치(.htlayout · 팩 파일 종류 3)를 Node 없이 저장소로 가져오는 길의 검사(설계 A 5-5 · 계약 2-7 초안).
//! 종류 3 파일은 검사 안에서 `sha2` · `flate2`로 만든다(`js/packfile.js`의 `seal`과 같은 머리 52바이트 · zlib 본문 · 지문).
//! 이름은 모두 가상이다.
use archive_engine::legacy::{import_layout, import_with, pack_out, read_plan, ImportPlan};
use archive_engine::levels::{tile_of, LEVEL_MAX};
use archive_engine::tile::{build_tile, TileRequest};
use archive_engine::{archive_call, archive_free, archive_import, read_htlayout, read_htpack, Store, DAY};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::ffi::{CStr, CString};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-htlayout-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn zlib(plain: &[u8]) -> Vec<u8> {
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(plain).unwrap();
    encoder.finish().unwrap()
}

/// 머리 52바이트(표지 · 규격 2 · 종류 · 1 · 0 · 풀린 크기 · 압축 크기 · 지문) + 본문. 선언한 크기와 본문을 마음대로 줄 수 있다(지문은 늘 맞게).
fn seal_raw(kind: u8, declared_plain: u32, body: &[u8]) -> Vec<u8> {
    let mut head = b"HTPACK\r\n".to_vec();
    head.extend_from_slice(&[2, kind, 1, 0]);
    head.extend_from_slice(&declared_plain.to_le_bytes());
    head.extend_from_slice(&(body.len() as u32).to_le_bytes());
    let mut hash = Sha256::new();
    hash.update(&head);
    hash.update(body);
    [head, hash.finalize().to_vec(), body.to_vec()].concat()
}

fn seal(kind: u8, plain: &[u8]) -> Vec<u8> {
    seal_raw(kind, plain.len() as u32, &zlib(plain))
}

fn htpack(raw: &Value) -> Vec<u8> {
    seal(1, &serde_json::to_vec(raw).unwrap())
}

fn htlayout(plan: &Value) -> Vec<u8> {
    seal(3, &serde_json::to_vec(plan).unwrap())
}

fn dlc(id: &str, name: &str, version: &str) -> Value {
    json!({"format":"history-timeline-dlc","formatVersion":1,"id":id,"name":name,"version":version})
}

fn row(height: i64) -> Value {
    json!({"height":height,"bandTop":19,"bandH":height-19,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1,
        "kind":0,"groupStart":0,"scopePad":0,"phase":1,"rank":0,"cats":[],"fig":1,"dep":0,"zones":0,"hem":0})
}

/// 기본팩(기본 기록집 v1.0.0) + 얹은 DLC(얹은 기록집 v2.0.0)를 함께 셈한 배치. 둘째 트랙 · 그 띠 · 사건은 얹은 DLC의 것이다.
fn layout() -> Value {
    let year = 525_600i64;
    let mut events = Vec::new();
    for i in 0..240i64 {
        let on_extra = i % 4 == 3;
        let (track, row) = if on_extra { (1, 0) } else { (0, i % 2) };
        let start = -2_000 * year + i * 17 * year + (i % 5) * DAY;
        let mut e = json!({"uid": if on_extra { format!("extra-pack/e{i}") } else { format!("e{i}") }, "track":track,"row":row,"start":start,
            "end": if i % 7 == 0 { start + 40 * year } else { start }, "importance": 1 + i % 3, "title": format!("가상 사건 {i}"),
            "body": if i % 3 == 0 { "물결 마을의 이야기" } else { "" }, "look": i % 3, "label":"", "rail":0,
            "band": if on_extra { "extra-pack/p-c" } else if row == 0 { "p-a" } else { "p-b" }});
        if on_extra {
            e["pack"] = json!(1);
        }
        events.push(e);
    }
    json!({
        "name": "검사 조합",
        "packs": [{"id":"base-pack","name":"기본 기록집","version":"1.0.0","category":""},{"id":"extra-pack","name":"얹은 기록집","version":"2.0.0","category":"nation"}],
        "categories": [{"key":"govern","name":"다스림","color":0x8f7fb0}, {"key":"lore","name":"이야기","color":0x9a6f8a}],
        "tracks": [
            {"key":"t-first","name":"첫 트랙","color":0xc8b193,"dynasty":1,"leader":1,"cabinet":1,"organ":0,"railLevels":2,"rows":[row(126), row(140)],
             "groups":[{"depth":0,"first":0,"count":2,"name":"윗물 겨레","color":0xbcd8c1,"kind":0}]},
            {"key":"t-second","name":"둘째 트랙","pack":1,"rows":[row(133)]}
        ],
        "epochs": [{"start":-2_000 * year,"end":2_200 * year,"color":0xc8b193,"name":"첫 시대"}],
        "axis": [{"kind":1,"track":-1,"lane":0,"start":-2_000 * year,"end":2_200 * year,"name":"첫 시대","color":0xc8b193,"style":0,"strip":0,"seq":0},
                 {"kind":2,"track":0,"lane":0,"start":-1_900 * year,"end":-1_000 * year,"name":"첫길 연호","color":0x9dbea8,"style":0,"strip":1,"seq":0}],
        "periods": [
            {"uid":"p-a","track":0,"row":0,"start":-2_000 * year,"end":-1 * year,"fuzzy":1,"color":0xa0bcc5,"name":"별여울국"},
            {"uid":"p-b","track":0,"row":1,"start":-1_500 * year,"end":1_800 * year,"color":0x9dbea8,"name":"해솔국"},
            {"uid":"extra-pack/p-c","track":1,"row":0,"start":-1_900 * year,"end":2_100 * year,"color":0xd7c18e,"name":"은빛 나루","pack":1}
        ],
        "cells": [
            {"period":"p-a","kind":1,"start":-2_000 * year,"end":-1_200 * year,"name":"첫째 지도자"},
            {"period":"p-a","kind":1,"start":-1_199 * year,"end":-1 * year,"name":"둘째 지도자","lane":1,"style":4,"color":0xd1a9b9},
            {"period":"extra-pack/p-c","kind":1,"start":-1_900 * year,"end":0,"name":"나루 지기"}
        ],
        "events": events,
        "items": [
            {"section":16,"track":0,"row":0,"row2":0,"start":-1_500 * year,"end":-900 * year,"lod":-1,"ref":"p-a","name":"별여울 속국","color":0xa0bcc5,"a":1,"b":2,"c":3,"d":4,"text2":"곁글"},
            {"section":17,"track":1,"row":0,"start":0,"end":0,"lod":12,"ref":"extra-pack/e3"}
        ],
        "entities": [
            {"uid":"p-a","kind":"period","json":"{\"uid\":\"p-a\",\"name\":\"별여울국\"}"},
            {"uid":"extra-pack/p-c","kind":"period","json":"{\"uid\":\"extra-pack/p-c\",\"name\":\"은빛 나루\"}"},
            {"uid":"house:h-sol","kind":"house","pack":1,"json":"{\"name\":\"솔바위 가문\"}"}
        ],
        "rowLabels": [{"period":"p-a","track":0,"row":0,"kind":0,"name":"별여울국","color":0xa0bcc5}],
        // 스키마 4의 문화권 단위 줄(계약 1-1) — 얹은 DLC의 사람 띠 · 기본팩의 주기 줄.
        "sphereLines": [
            {"kind":1,"sphere":"","start":-1_900 * year,"end":-year,"name":"두 나라 지기","uid":"extra-pack/f-1","color":0,
             "data":"[{\"uid\":\"p-a\",\"cell\":1},{\"uid\":\"extra-pack/p-c\",\"cell\":0}]","pack":1},
            {"kind":3,"sphere":"","start":0,"end":0,"name":"첫 간지","uid":"","color":0,"data":"{\"names\":[\"갑\",\"을\"],\"start\":4,\"label\":\"첫 간지\"}","pack":0}
        ]
    })
}

/// 검사 자료 한 벌: 기본팩 · 얹은 DLC 원본, 배치 JSON과 같은 배치의 .htlayout.
struct Kit {
    dir: PathBuf,
    base: PathBuf,
    extra: PathBuf,
    json: PathBuf,
    layout: PathBuf,
}

fn kit(name: &str, plan: &Value) -> Kit {
    let dir = scratch(name);
    let base = dir.join("기본.htpack");
    std::fs::write(&base, htpack(&dlc("base-pack", "기본 기록집", "1.0.0"))).unwrap();
    let extra = dir.join("얹은.htpack");
    std::fs::write(&extra, htpack(&dlc("extra-pack", "얹은 기록집", "2.0.0"))).unwrap();
    let json = dir.join("배치.json");
    std::fs::write(&json, serde_json::to_vec(plan).unwrap()).unwrap();
    let layout = dir.join("배치.htlayout");
    std::fs::write(&layout, htlayout(plan)).unwrap();
    Kit { dir, base, extra, json, layout }
}

fn plan_of<'a>(layout: &'a Path) -> ImportPlan<'a> {
    ImportPlan { layout, out: None, base: None, originals: Vec::new(), from_store: None, check_only: false }
}

fn rows_of(s: &Store, sql: &str) -> Vec<Value> {
    let mut st = s.db.prepare(sql).unwrap();
    let n = st.column_count();
    let v = st.query_map([], |r| {
        Ok(Value::Array((0..n).map(|i| match r.get_ref(i).unwrap() {
            rusqlite::types::ValueRef::Null => Value::Null,
            rusqlite::types::ValueRef::Integer(x) => json!(x),
            rusqlite::types::ValueRef::Real(x) => json!(x),
            rusqlite::types::ValueRef::Text(t) => json!(String::from_utf8_lossy(t)),
            rusqlite::types::ValueRef::Blob(b) => json!(format!("{:x}", Sha256::digest(b))),
        }).collect()))
    }).unwrap().map(|r| r.unwrap()).collect();
    v
}

fn meta(s: &Store, key: &str) -> Option<String> {
    s.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get(0)).ok()
}

/// 두 저장소가 화면에 같은 것을 주는가: `layout` 답 · 띠 · 칸 · 사건 · 일반 항목 · 항목 기록 · 줄 이름 · 문화권 단위 줄(스키마 4) · 표본 타일의 바이트.
/// `with_originals`가 거짓이면 자료집의 원본(BLOB · 지문)과 `original` 표시는 견주지 않는다.
fn same_store(a: &Path, b: &Path, with_originals: bool) {
    let (sa, sb) = (Store::open(a).unwrap(), Store::open(b).unwrap());
    let (mut la, mut lb) = (sa.call(&json!({"op":"layout"})).unwrap(), sb.call(&json!({"op":"layout"})).unwrap());
    if !with_originals {
        for l in [&mut la, &mut lb] {
            for p in l["packs"].as_array_mut().unwrap() {
                p["original"] = json!(null);
            }
        }
    }
    assert_eq!(la, lb, "layout 답");
    for sql in [
        "SELECT * FROM periods ORDER BY id", "SELECT * FROM cells ORDER BY id", "SELECT * FROM events ORDER BY id", "SELECT * FROM items ORDER BY id",
        "SELECT * FROM entities ORDER BY uid", "SELECT * FROM row_labels ORDER BY rowid", "SELECT * FROM axis_cells ORDER BY id", "SELECT * FROM names ORDER BY rowid",
        "SELECT * FROM summaries ORDER BY level,lane,bucket,pack", "SELECT * FROM sphere_lines ORDER BY id",
    ] {
        assert_eq!(rows_of(&sa, sql), rows_of(&sb, sql), "{sql}");
    }
    if with_originals {
        assert_eq!(rows_of(&sa, "SELECT * FROM packs ORDER BY id"), rows_of(&sb, "SELECT * FROM packs ORDER BY id"), "자료집 · 원본");
    } else {
        assert_eq!(rows_of(&sa, "SELECT id,name FROM packs ORDER BY id"), rows_of(&sb, "SELECT id,name FROM packs ORDER BY id"), "자료집");
    }
    for key in ["count", "min", "max", "rows", "pack_keys", "pack_events", "pack_periods", "pack_tracks", "names"] {
        assert_eq!(meta(&sa, key), meta(&sb, key), "meta.{key}");
    }
    let packs: Vec<i64> = rows_of(&sa, "SELECT id FROM packs ORDER BY id").iter().map(|r| r[0].as_i64().unwrap()).collect();
    let (min, max): (i64, i64) = (meta(&sa, "min").unwrap().parse().unwrap(), meta(&sa, "max").unwrap().parse().unwrap());
    let mut tiles = 0;
    for level in [0usize, 3, 6, 9, 12, LEVEL_MAX] {
        for step in 0..6i64 {
            let minute = min + (max - min) / 6 * step;
            for chosen in [packs.clone(), vec![packs[0]]] {
                let req = |s: &Store| TileRequest { level, x: tile_of(minute, level), chunk: 0, packs: chosen.clone(), filter: None, variants: s.variants_of(&json!({})).unwrap() };
                assert_eq!(build_tile(&sa, &req(&sa)).unwrap(), build_tile(&sb, &req(&sb)).unwrap(), "타일 단계 {level} · {minute}분");
                tiles += 1;
            }
        }
    }
    assert!(tiles > 0);
}

#[test]
fn htlayout으로_지은_저장소는_같은_json으로_지은_저장소와_같다() {
    let k = kit("same", &layout());
    // 종류 3을 풀면 JSON과 같은 값이다(웹 parseLayout의 text와 노드 도구의 JSON이 같은 글인 것처럼).
    assert_eq!(read_htlayout(&k.layout).unwrap(), read_plan(&k.json).unwrap());
    let from_json = k.dir.join("json.db");
    import_layout(&k.base, &k.json, &from_json, &[&k.extra]).unwrap();
    // 옛 꼴(기본팩 · 배치 · 얹은 원본)에 .htlayout을 주어도 확장자로 갈라 같은 저장소를 짓는다.
    let strict = k.dir.join("strict.db");
    import_layout(&k.base, &k.layout, &strict, &[&k.extra]).unwrap();
    same_store(&from_json, &strict, true);
    // Node 없는 길: 원본을 id로 짝지어 받는다(차례를 바꿔 주어도 된다).
    let lenient = k.dir.join("lenient.db");
    let answer = import_with(&ImportPlan { out: Some(&lenient), originals: vec![&k.extra, &k.base], ..plan_of(&k.layout) }).unwrap();
    assert_eq!(answer["packs"], json!([
        {"id":"base-pack","name":"기본 기록집","version":"1.0.0","category":"","original":1},
        {"id":"extra-pack","name":"얹은 기록집","version":"2.0.0","category":"nation","original":1}]));
    assert_eq!((answer["events"].as_i64(), answer["entities"].as_i64()), (Some(240), Some(3)));
    assert_eq!(answer["verify"]["missing"], 0);
    assert_eq!(answer["verify"]["dup"], 0);
    assert!(answer["verify"]["tiles"].as_i64().unwrap() > 0, "지은 뒤 표본 타일을 견주었다");
    assert_eq!(answer["warnings"], json!([]));
    same_store(&from_json, &lenient, true);
    // 판 · 분류 · 원본을 품었는가가 남는다(`meta.pack_info` → `layout`의 packs[]).
    let s = Store::open(&lenient).unwrap();
    assert_eq!(serde_json::from_str::<Value>(&meta(&s, "pack_info").unwrap()).unwrap(), json!({
        "1":{"id":"base-pack","version":"1.0.0","category":"","original":true},
        "2":{"id":"extra-pack","version":"2.0.0","category":"nation","original":true}}));
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    assert_eq!((shape["packs"][1]["version"].as_str(), shape["packs"][1]["category"].as_str(), shape["packs"][1]["original"].as_i64()), (Some("2.0.0"), Some("nation"), Some(1)));
    assert_eq!(meta(&s, "legacy").as_deref(), Some("원본 전용 팩 보존 · 지금 연표의 줄 배치 그대로 가져옴"));
    // 귀속: `pack`이 있는 `/` 없는 uid(house:)도 얹은 DLC로 붙는다.
    let house: i64 = s.db.query_row("SELECT pack FROM entities WHERE uid='house:h-sol'", [], |r| r.get(0)).unwrap();
    assert_eq!(house, 2);
    drop(s);
    // 웹 TextDecoder처럼 맨 앞의 BOM은 건너뛴다.
    let bom = k.dir.join("bom.htlayout");
    std::fs::write(&bom, seal(3, &[b"\xEF\xBB\xBF".as_slice(), &serde_json::to_vec(&layout()).unwrap()].concat())).unwrap();
    assert_eq!(read_htlayout(&bom).unwrap(), read_plan(&k.json).unwrap());
    std::fs::remove_dir_all(&k.dir).unwrap();
}

#[test]
fn 깨지거나_잘리거나_종류가_틀린_배치는_웹과_같은_글로_거절하고_저장소를_남기지_않는다() {
    let k = kit("broken", &layout());
    let good = std::fs::read(&k.layout).unwrap();
    let plain = serde_json::to_vec(&layout()).unwrap();
    let body = zlib(&plain);
    let mut no_items = layout();
    no_items.as_object_mut().unwrap().remove("items");
    let mut no_packs = layout();
    no_packs["packs"] = json!([]);
    let mut entities_object = layout();
    entities_object["entities"] = json!({});
    let poke = |at: usize, value: u8| { let mut b = good.clone(); b[at] = value; b };
    let cases: Vec<(&str, &str, Vec<u8>, &str)> = vec![
        ("확장자", "배치.htpack", good.clone(), "아카이브 배치 파일(.htlayout)이 아닙니다."),
        ("팩이 아님", "글.htlayout", plain.clone(), "아카이브 배치 파일(.htlayout)이 아닙니다."),
        ("머리 잘림", "a.htlayout", good[..30].to_vec(), "팩 파일의 머리 부분이 잘렸습니다."),
        ("규격", "a.htlayout", poke(8, 3), "지원하지 않는 팩 형식입니다. 메이커와 연표의 버전을 확인하세요."),
        ("DLC 팩", "a.htlayout", htpack(&dlc("base-pack", "기본 기록집", "1.0.0")), "DLC · 백업 팩(.htpack)입니다 — 아카이브 배치 파일(.htlayout)이 아닙니다."),
        ("백업 팩", "a.htlayout", seal(2, br#"{"format":"history-timeline-backup","installed":[]}"#), "DLC · 백업 팩(.htpack)입니다 — 아카이브 배치 파일(.htlayout)이 아닙니다."),
        ("모르는 종류", "a.htlayout", poke(9, 7), "팩 파일의 머리 부분이 올바르지 않습니다."),
        ("예약 자리", "a.htlayout", poke(10, 2), "팩 파일의 머리 부분이 올바르지 않습니다."),
        ("본문 잘림", "a.htlayout", good[..good.len() - 10].to_vec(), "팩 파일이 잘렸거나 불필요한 내용이 붙었습니다."),
        ("꼬리 붙음", "a.htlayout", [good.clone(), vec![0, 0]].concat(), "팩 파일이 잘렸거나 불필요한 내용이 붙었습니다."),
        ("지문", "a.htlayout", poke(good.len() - 5, good[good.len() - 5] ^ 0x5a), "팩 파일이 손상되었거나 바뀌었습니다. 원본을 다시 받거나 메이커에서 새로 저장하세요."),
        ("머리의 크기를 고침", "a.htlayout", poke(12, good[12] ^ 1), "팩 파일이 손상되었거나 바뀌었습니다. 원본을 다시 받거나 메이커에서 새로 저장하세요."),
        ("빈 본문", "a.htlayout", seal_raw(3, 0, &body), "팩을 풀면 허용 크기(128MB)를 넘거나 내용이 없습니다."),
        ("너무 큰 선언", "a.htlayout", seal_raw(3, 129 * 1024 * 1024, &body), "팩을 풀면 허용 크기(128MB)를 넘거나 내용이 없습니다."),
        ("압축 아님", "a.htlayout", seal_raw(3, plain.len() as u32, &plain), "팩 내용을 풀 수 없습니다. 파일이 손상되었습니다."),
        ("압축 뒤 군더더기", "a.htlayout", seal_raw(3, plain.len() as u32, &[body.clone(), b"junk".to_vec()].concat()), "팩 내용을 풀 수 없습니다. 파일이 손상되었습니다."),
        ("선언보다 큰 본문", "a.htlayout", seal_raw(3, plain.len() as u32 - 1, &body), "팩을 풀면 허용 크기(0MB)를 넘습니다."),
        ("선언보다 작은 본문", "a.htlayout", seal_raw(3, plain.len() as u32 + 1, &body), "팩 내용의 크기가 맞지 않습니다."),
        ("JSON 아님", "a.htlayout", seal(3, "배치가 아닌 글".as_bytes()), "팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다."),
        ("UTF-8 아님", "a.htlayout", seal(3, &[0xff, 0xfe, b'{', b'}']), "팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다."),
        ("목록이 빠짐", "a.htlayout", htlayout(&no_items), "팩 종류와 내용이 맞지 않습니다."),
        ("DLC 목록이 빔", "a.htlayout", htlayout(&no_packs), "팩 종류와 내용이 맞지 않습니다."),
        ("목록이 아님", "a.htlayout", htlayout(&entities_object), "팩 종류와 내용이 맞지 않습니다."),
        ("배열 본문", "a.htlayout", seal(3, b"[1,2]"), "팩 종류와 내용이 맞지 않습니다."),
    ];
    for (name, file, bytes, want) in cases {
        let path = k.dir.join(file);
        std::fs::write(&path, &bytes).unwrap();
        assert_eq!(read_htlayout(&path).unwrap_err().to_string(), want, "{name}");
        // 가져오기(옛 꼴 · Node 없는 길 · 점검만)도 같은 글로 거절하고 저장소를 남기지 않는다.
        let target = k.dir.join(format!("{name}.db"));
        assert_eq!(import_with(&ImportPlan { out: Some(&target), base: Some(&k.base), ..plan_of(&path) }).unwrap_err().to_string(), want, "{name}");
        assert_eq!(import_with(&ImportPlan { check_only: true, ..plan_of(&path) }).unwrap_err().to_string(), want, "{name} 점검만");
        assert_eq!(import_layout(&k.base, &path, &target, &[&k.extra]).unwrap_err().to_string(), want, "{name} 옛 꼴");
        assert!(!target.exists(), "{name}: 실패한 가져오기는 저장소를 남기지 않는다");
        std::fs::remove_file(&path).unwrap();
    }
    // 전용 팩 읽기(종류 1)는 떼어 낸 뒤에도 예전 글 그대로다.
    let wrong = k.dir.join("배치를-팩으로.htpack");
    std::fs::write(&wrong, &good).unwrap();
    assert_eq!(read_htpack(&wrong).unwrap_err().to_string(), "지원하지 않는 전용 팩 머리");
    let mut broken = std::fs::read(&k.base).unwrap();
    let last = broken.len() - 1;
    broken[last] ^= 0x5a;
    std::fs::write(&wrong, &broken).unwrap();
    assert_eq!(read_htpack(&wrong).unwrap_err().to_string(), "전용 팩 지문 오류");
    std::fs::write(&wrong, &broken[..broken.len() - 3]).unwrap();
    assert_eq!(read_htpack(&wrong).unwrap_err().to_string(), "전용 팩 선언 크기 오류");
    std::fs::write(&wrong, seal_raw(1, 10, &zlib(&serde_json::to_vec(&dlc("x", "x", "1")).unwrap()))).unwrap();
    assert_eq!(read_htpack(&wrong).unwrap_err().to_string(), "전용 팩 풀린 크기 오류");
    std::fs::write(&wrong, htpack(&json!({"format":"다른 것"}))).unwrap();
    assert_eq!(read_htpack(&wrong).unwrap_err().to_string(), "DLC 본문이 아닙니다");
    std::fs::remove_dir_all(&k.dir).unwrap();
}

#[test]
fn 원본_없이_넣으면_original이_null이고_pack_keys와_pack_info가_남는다() {
    let k = kit("bare", &layout());
    let from_json = k.dir.join("json.db");
    import_layout(&k.base, &k.json, &from_json, &[&k.extra]).unwrap();
    let bare = k.dir.join("bare.db");
    let answer = import_with(&ImportPlan { out: Some(&bare), ..plan_of(&k.layout) }).unwrap();
    assert_eq!(answer["packs"][0]["original"], 0);
    assert_eq!(answer["packs"][1]["original"], 0);
    assert_eq!(answer["warnings"], json!([
        "«기본 기록집»: 원본 없음 — 그 DLC의 .htpack을 함께 넣으면 저장소에 품습니다",
        "«얹은 기록집»: 원본 없음 — 그 DLC의 .htpack을 함께 넣으면 저장소에 품습니다"]));
    // 원본만 빠졌을 뿐 화면이 받는 것은 같다.
    same_store(&from_json, &bare, false);
    let s = Store::open(&bare).unwrap();
    assert_eq!(rows_of(&s, "SELECT id,original,sha256 FROM packs ORDER BY id"), vec![json!([1, null, null]), json!([2, null, null])]);
    assert_eq!(serde_json::from_str::<Value>(&meta(&s, "pack_keys").unwrap()).unwrap(), json!({"1":"base-pack","2":"extra-pack"}));
    assert_eq!(serde_json::from_str::<Value>(&meta(&s, "pack_info").unwrap()).unwrap(), json!({
        "1":{"id":"base-pack","version":"1.0.0","category":"","original":false},
        "2":{"id":"extra-pack","version":"2.0.0","category":"nation","original":false}}));
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    assert_eq!(shape["packs"].as_array().unwrap().iter().map(|p| p["original"].as_i64().unwrap()).collect::<Vec<_>>(), vec![0, 0]);
    assert_eq!(meta(&s, "legacy").as_deref(), Some("지금 연표의 줄 배치 그대로 가져옴 · 원본 없는 DLC가 있음(meta.pack_info의 original)"));
    assert_eq!(s.call(&json!({"op":"info"})).unwrap()["meta"]["packs"], "2");
    drop(s);
    // 원본이 없는 DLC는 꺼낼 수 없다.
    assert_eq!(pack_out(&bare, "extra-pack", &k.dir.join("꺼냄.htpack")).unwrap_err().to_string(), "저장소에 «얹은 기록집»의 원본이 없습니다(원본 없이 넣은 DLC)");
    // 옛 JSON 저장소에서 원본을 꺼내 다시 넣을 수 있다(PC에서 다시 지을 때).
    let out = k.dir.join("꺼냄.htpack");
    let got = pack_out(&from_json, "extra-pack", &out).unwrap();
    assert_eq!(std::fs::read(&out).unwrap(), std::fs::read(&k.extra).unwrap());
    assert_eq!(got["sha256"], format!("{:x}", Sha256::digest(std::fs::read(&k.extra).unwrap())));
    assert!(pack_out(&from_json, "extra-pack", &out).unwrap_err().to_string().contains("덮어쓰지"));
    assert!(pack_out(&from_json, "없는-dlc", &k.dir.join("x.htpack")).unwrap_err().to_string().contains("없는-dlc"));
    std::fs::remove_dir_all(&k.dir).unwrap();
}

#[test]
fn 지금_저장소를_주면_그_저장소의_원본을_옮겨_싣는다() {
    let k = kit("carry", &layout());
    let held = k.dir.join("held.db");
    import_layout(&k.base, &k.json, &held, &[&k.extra]).unwrap();
    let carried = k.dir.join("carried.db");
    let answer = import_with(&ImportPlan { out: Some(&carried), from_store: Some(&held), ..plan_of(&k.layout) }).unwrap();
    assert_eq!(answer["warnings"], json!([]), "판을 양쪽이 알고 같다 · 원본은 옮겨 실었다");
    assert_eq!(answer["packs"].as_array().unwrap().iter().map(|p| (p["original"].as_i64().unwrap(), p["added"].as_i64().unwrap())).collect::<Vec<_>>(), vec![(1, 0), (1, 0)]);
    same_store(&held, &carried, true);
    // 함께 받은 원본이 옮겨 실을 원본보다 먼저다(같은 id · 같은 판).
    let newer = k.dir.join("새 원본.htpack");
    let mut raw = dlc("extra-pack", "얹은 기록집", "2.0.0");
    raw["summary"] = json!("새로 받은 원본");
    std::fs::write(&newer, htpack(&raw)).unwrap();
    let mixed = k.dir.join("mixed.db");
    import_with(&ImportPlan { out: Some(&mixed), from_store: Some(&held), originals: vec![&newer], ..plan_of(&k.layout) }).unwrap();
    let s = Store::open(&mixed).unwrap();
    let originals: Vec<Vec<u8>> = { let mut st = s.db.prepare("SELECT original FROM packs ORDER BY id").unwrap(); let v = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(originals, vec![std::fs::read(&k.base).unwrap(), std::fs::read(&newer).unwrap()]);
    drop(s);
    // 받은 원본의 판이 배치와 다르면 거절한다.
    let other = k.dir.join("다른 판.htpack");
    std::fs::write(&other, htpack(&dlc("extra-pack", "얹은 기록집", "1.9.0"))).unwrap();
    let refused = k.dir.join("refused.db");
    assert_eq!(import_with(&ImportPlan { out: Some(&refused), originals: vec![&other], ..plan_of(&k.layout) }).unwrap_err().to_string(),
        "원본 «얹은 기록집»의 판이 배치와 다릅니다(원본 v1.9.0 · 배치 v2.0.0)");
    // 배치에 없는 DLC의 원본 · 기본팩이 아닌 기본팩 원본도 거절한다.
    let stray = k.dir.join("남의 것.htpack");
    std::fs::write(&stray, htpack(&dlc("stray-pack", "떠돌이 기록집", "1"))).unwrap();
    assert_eq!(import_with(&ImportPlan { out: Some(&refused), originals: vec![&stray], ..plan_of(&k.layout) }).unwrap_err().to_string(),
        "원본 «떠돌이 기록집»(stray-pack)이 이 배치에 없습니다");
    assert_eq!(import_with(&ImportPlan { out: Some(&refused), base: Some(&k.extra), ..plan_of(&k.layout) }).unwrap_err().to_string(),
        "기본팩 원본의 id(extra-pack)가 배치의 기본팩(base-pack)과 다릅니다");
    assert!(!refused.exists());
    std::fs::remove_dir_all(&k.dir).unwrap();
}

/// 조합 대조(설계 A 5-3)의 다섯 경우. S = 기본 기록집 v1.0.0 + 얹은 기록집 v2.0.0.
#[test]
fn 조합_대조는_다섯_경우로_갈린다() {
    let k = kit("combo", &layout());
    let held = k.dir.join("held.db");
    import_layout(&k.base, &k.json, &held, &[&k.extra]).unwrap();
    let try_plan = |name: &str, plan: &Value| -> Result<Value, String> {
        let path = k.dir.join(format!("{name}.htlayout"));
        std::fs::write(&path, htlayout(plan)).unwrap();
        let out = k.dir.join(format!("{name}.db"));
        // 점검만으로도 같은 답(짓지 않는다)이 나와야 한다.
        let checked = import_with(&ImportPlan { from_store: Some(&held), check_only: true, ..plan_of(&path) });
        assert!(!out.exists());
        let built = import_with(&ImportPlan { out: Some(&out), from_store: Some(&held), ..plan_of(&path) });
        match (&checked, &built) {
            (Ok(c), Ok(b)) => {
                assert_eq!(c["check_only"], true);
                assert_eq!((&c["packs"], &c["warnings"]), (&b["packs"], &b["warnings"]), "{name}: 점검과 짓기의 판단이 같다");
                assert!(out.exists());
            }
            (Err(c), Err(b)) => {
                assert_eq!(c.to_string(), b.to_string(), "{name}");
                assert!(!out.exists(), "{name}: 거절하면 짓지 않는다");
            }
            _ => panic!("{name}: 점검({checked:?})과 짓기({built:?})가 다르게 갈림"),
        }
        built.map_err(|e| e.to_string())
    };
    // 1. 기본팩이 다르면 거절.
    let mut other_base = layout();
    other_base["packs"][0]["id"] = json!("other-base");
    other_base["packs"][0]["name"] = json!("다른 기본 기록집");
    assert_eq!(try_plan("1-기본팩", &other_base).unwrap_err(), "기본팩이 다릅니다(저장소 «기본 기록집» · 배치 «다른 기본 기록집») — 같은 기본팩으로 내보낸 배치만 받습니다");
    // 2. 지금 얹은 DLC가 배치에 없으면 거절(새로 지으면 사라진다).
    let mut only_base = layout();
    only_base["packs"] = json!([{"id":"base-pack","name":"기본 기록집","version":"1.0.0"}]);
    assert_eq!(try_plan("2-빠짐", &only_base).unwrap_err(), "지금 얹은 DLC «얹은 기록집»이 이 배치에 없습니다 — 메이커에서 그 DLC도 함께 불러 내보내 주세요");
    // 3. 같은 id인데 판을 양쪽이 알고 다르면 거절.
    let mut newer = layout();
    newer["packs"][1]["version"] = json!("3.0.0");
    assert_eq!(try_plan("3-판", &newer).unwrap_err(), "«얹은 기록집»의 판이 다릅니다(저장소 v2.0.0 · 배치 v3.0.0)");
    // 4. 판을 모르면(A1-a 전의 메이커가 낸 배치) id로만 대조하고 받되 알린다.
    let mut unknown = layout();
    unknown["packs"][1].as_object_mut().unwrap().remove("version");
    let got = try_plan("4-판 모름", &unknown).unwrap();
    assert_eq!(got["warnings"], json!(["«얹은 기록집»의 판을 확인할 수 없습니다 — id로만 대조했습니다"]));
    assert_eq!(got["packs"][1]["original"], 1, "판을 몰라도 id가 같으면 원본을 옮겨 싣는다");
    assert_eq!(got["packs"][1]["version"], "2.0.0", "배치가 판을 말하지 않으면 옮겨 실은 원본의 판을 적는다(노드 도구의 길과 같게)");
    // 5. 배치에만 있는 DLC는 새로 더해진다(원본은 함께 받지 않으면 없음).
    let mut more = layout();
    more["packs"].as_array_mut().unwrap().push(json!({"id":"third-pack","name":"셋째 기록집","version":"1.0.0"}));
    more["events"].as_array_mut().unwrap().push(json!({"uid":"third-pack/e-new","track":1,"row":0,"start":0,"end":0,"importance":2,"title":"셋째의 새 일","body":"","pack":2}));
    let got = try_plan("5-더함", &more).unwrap();
    assert_eq!(got["packs"].as_array().unwrap().iter().map(|p| (p["id"].as_str().unwrap(), p["added"].as_i64().unwrap(), p["original"].as_i64().unwrap())).collect::<Vec<_>>(),
        vec![("base-pack", 0, 1), ("extra-pack", 0, 1), ("third-pack", 1, 0)]);
    assert_eq!(got["warnings"], json!(["«셋째 기록집»: 원본 없음 — 그 DLC의 .htpack을 함께 넣으면 저장소에 품습니다"]));
    let s = Store::open(&k.dir.join("5-더함.db")).unwrap();
    assert_eq!(serde_json::from_str::<Value>(&meta(&s, "pack_keys").unwrap()).unwrap(), json!({"1":"base-pack","2":"extra-pack","3":"third-pack"}));
    assert_eq!(s.call(&json!({"op":"layout"})).unwrap()["packs"][2]["events"], 1);
    drop(s);

    // `pack_info`가 없는 옛 저장소: 판은 품은 원본(.htpack)의 팩 정보에서 읽는다 — 같으면 경고 없이, 다르면 거절.
    let old = k.dir.join("old.db");
    std::fs::copy(&held, &old).unwrap();
    rusqlite::Connection::open(&old).unwrap().execute("DELETE FROM meta WHERE key='pack_info'", []).unwrap();
    let out = k.dir.join("old-ok.db");
    let got = import_with(&ImportPlan { out: Some(&out), from_store: Some(&old), ..plan_of(&k.layout) }).unwrap();
    assert_eq!(got["warnings"], json!([]));
    let path = k.dir.join("3-판.htlayout");
    assert_eq!(import_with(&ImportPlan { out: Some(&k.dir.join("old-no.db")), from_store: Some(&old), ..plan_of(&path) }).unwrap_err().to_string(),
        "«얹은 기록집»의 판이 다릅니다(저장소 v2.0.0 · 배치 v3.0.0)");
    // 원본도 판도 없는 저장소(원본 없이 넣은 것): 판을 확인할 수 없다고 알린다.
    let bare = k.dir.join("bare.db");
    import_with(&ImportPlan { out: Some(&bare), ..plan_of(&k.dir.join("4-판 모름.htlayout")) }).unwrap();
    let got = import_with(&ImportPlan { out: Some(&k.dir.join("bare-again.db")), from_store: Some(&bare), ..plan_of(&k.layout) }).unwrap();
    assert_eq!(got["warnings"], json!([
        "«얹은 기록집»의 판을 확인할 수 없습니다 — id로만 대조했습니다",
        "«기본 기록집»: 원본 없음 — 그 DLC의 .htpack을 함께 넣으면 저장소에 품습니다",
        "«얹은 기록집»: 원본 없음 — 그 DLC의 .htpack을 함께 넣으면 저장소에 품습니다"]));
    // 글자 id가 없는 저장소는 무엇이 같은 DLC인지 몰라 대조하지 못한다 — 거절.
    let nameless = k.dir.join("nameless.db");
    let mut plain = layout();
    plain.as_object_mut().unwrap().remove("packs");
    for e in plain["events"].as_array_mut().unwrap() {
        e.as_object_mut().unwrap().remove("pack");
    }
    plain["tracks"][1].as_object_mut().unwrap().remove("pack");
    plain["periods"][2].as_object_mut().unwrap().remove("pack");
    plain["entities"][2].as_object_mut().unwrap().remove("pack");
    let plain_path = k.dir.join("packs-없음.json");
    std::fs::write(&plain_path, serde_json::to_vec(&plain).unwrap()).unwrap();
    let anonymous = k.dir.join("이름 없는.htpack");
    std::fs::write(&anonymous, htpack(&json!({"format":"history-timeline-dlc","name":"이름 없는 기록집"}))).unwrap();
    import_layout(&anonymous, &plain_path, &nameless, &[]).unwrap();
    assert_eq!(import_with(&ImportPlan { check_only: true, from_store: Some(&nameless), ..plan_of(&k.layout) }).unwrap_err().to_string(),
        "지금 저장소의 «이름 없는 기록집»에 DLC id가 없어 조합을 대조할 수 없습니다 — 아주 옛 저장소입니다. 새 판 시드로 옮긴 뒤 다시 해 주세요");
    std::fs::remove_dir_all(&k.dir).unwrap();
}

fn ffi(f: unsafe extern "C" fn(*const std::ffi::c_char) -> *mut std::ffi::c_char, request: &Value) -> Value {
    let text = CString::new(request.to_string()).unwrap();
    unsafe {
        let answer = f(text.as_ptr());
        let value: Value = serde_json::from_str(CStr::from_ptr(answer).to_str().unwrap()).unwrap();
        archive_free(answer);
        value
    }
}

/// 큰 배치: 한 트랙 64줄에 사건이 많다(짓기가 눈에 띄게 걸리도록).
fn big_layout(events: i64) -> Value {
    let year = 525_600i64;
    let rows: Vec<Value> = (0..64).map(|_| row(126)).collect();
    let list: Vec<Value> = (0..events).map(|i| json!({"uid":format!("big/e{i}"),"track":0,"row":i % 64,"start":-3_000 * year + (i * 7919 % 5_000) * year + i % 1000,
        "end":-3_000 * year + (i * 7919 % 5_000) * year + i % 1000,"importance":1 + i % 3,"title":format!("큰 물결 {i}"),"body":"가상 본문","look":i % 3})).collect();
    json!({"name":"큰 조합","packs":[{"id":"big","name":"큰 기록집","version":"1"}],"tracks":[{"key":"big-track","name":"큰 트랙","rows":rows}],
        "periods":[],"cells":[],"events":list,"items":[],"entities":[]})
}

#[test]
fn archive_import는_잠금을_잡지_않아_가져오는_동안에도_archive_call이_답한다() {
    let k = kit("ffi", &layout());
    // 화면이 열어 둔 저장소.
    let open = k.dir.join("open.db");
    import_layout(&k.base, &k.json, &open, &[&k.extra]).unwrap();
    assert_eq!(ffi(archive_call, &json!({"op":"open","path":open.to_str().unwrap()}))["ok"], true);
    // 요청의 잘못은 archive_call과 같은 겉으로 답한다.
    unsafe {
        let answer = archive_import(std::ptr::null());
        assert_eq!(serde_json::from_str::<Value>(CStr::from_ptr(answer).to_str().unwrap()).unwrap(), json!({"ok":false,"error":"빈 요청"}));
        archive_free(answer);
    }
    assert_eq!(ffi(archive_import, &json!({"out":"x.db"})), json!({"ok":false,"error":"배치 파일 경로(layout)가 없습니다"}));
    assert_eq!(ffi(archive_import, &json!({"layout":k.layout.to_str().unwrap()})), json!({"ok":false,"error":"새 저장소 경로(out)가 없습니다"}));
    assert_eq!(ffi(archive_import, &json!({"layout":k.layout.to_str().unwrap(),"out":open.to_str().unwrap()})), json!({"ok":false,"error":"기존 저장소는 덮어쓰지 않습니다"}));
    assert_eq!(ffi(archive_import, &json!({"layout":k.layout.to_str().unwrap(),"originals":"x"}))["error"], "원본 목록(originals)은 경로 글의 목록이어야 합니다");
    let checked = ffi(archive_import, &json!({"layout":k.layout.to_str().unwrap(),"from_store":open.to_str().unwrap(),"check_only":true}));
    assert_eq!((checked["ok"].as_bool(), checked["data"]["check_only"].as_bool()), (Some(true), Some(true)), "{checked}");

    let big = k.dir.join("큰 배치.htlayout");
    std::fs::write(&big, htlayout(&big_layout(60_000))).unwrap();
    let target = k.dir.join("big.db");
    let request = json!({"layout":big.to_str().unwrap(),"out":target.to_str().unwrap()});
    let done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let flag = done.clone();
    let worker = std::thread::spawn(move || {
        let started = Instant::now();
        let answer = ffi(archive_import, &request);
        flag.store(true, std::sync::atomic::Ordering::SeqCst);
        (answer, started.elapsed())
    });
    // 가져오는 동안 화면 쪽 호출(뼈대 · 검색)이 줄곧 짧게 답하는가.
    let (mut calls, mut slowest) = (0, Duration::ZERO);
    while !done.load(std::sync::atomic::Ordering::SeqCst) {
        let t = Instant::now();
        let answer = ffi(archive_call, &json!({"op": if calls % 2 == 0 { "layout" } else { "info" }}));
        let took = t.elapsed();
        assert_eq!(answer["ok"], true);
        if !done.load(std::sync::atomic::Ordering::SeqCst) {
            calls += 1;
            slowest = slowest.max(took);
        }
    }
    let (answer, import_took) = worker.join().unwrap();
    assert_eq!(answer["ok"], true, "{answer}");
    assert_eq!(answer["data"]["events"], 60_000);
    assert_eq!(answer["data"]["verify"]["missing"], 0);
    // 짓기가 잠금을 잡았다면 그동안의 호출은 짓기가 끝날 때까지 기다렸다.
    assert!(calls >= 5, "가져오는 동안({import_took:?}) 답한 호출이 {calls}번뿐");
    assert!(slowest < import_took / 3, "가장 느린 호출 {slowest:?} · 가져오기 {import_took:?}");
    // 지은 저장소는 바로 열린다.
    assert_eq!(ffi(archive_call, &json!({"op":"open","path":target.to_str().unwrap()}))["data"]["meta"]["count"], "60000");
    assert_eq!(ffi(archive_call, &json!({"op":"close"}))["data"]["closed"], true);
    eprintln!("가져오기 {import_took:?} 동안 archive_call {calls}번 · 가장 느린 것 {slowest:?}");
    std::fs::remove_dir_all(&k.dir).unwrap();
}

/// `archive-tool`의 명령 셋(옛 꼴 그대로 · Node 없는 꼴 · 점검 · 원본 꺼내기).
#[test]
fn archive_tool의_가져오기_점검_꺼내기_명령() {
    let k = kit("tool", &layout());
    let tool = env!("CARGO_BIN_EXE_archive-tool");
    let run = |args: &[&Path]| -> (bool, String) {
        let out = std::process::Command::new(tool).args(args).output().unwrap();
        (out.status.success(), if out.status.success() { String::from_utf8_lossy(&out.stdout).into_owned() } else { String::from_utf8_lossy(&out.stderr).into_owned() })
    };
    let p = |s: &str| PathBuf::from(s);
    // 옛 꼴: 기본팩 · 배치.json · 새 저장소 · 얹은 원본(차례 · 수가 맞아야 — add-dlc.mjs).
    let old = k.dir.join("old.db");
    let (ok, text) = run(&[&p("import-layout"), &k.base, &k.json, &old, &k.extra]);
    assert!(ok, "{text}");
    assert!(text.contains("\"가져옴\""), "{text}");
    let (ok, text) = run(&[&p("import-layout"), &k.base, &k.json, &k.dir.join("x.db")]);
    assert!(!ok && text.contains("배치에 DLC가 2벌인데 전용 팩은 1개입니다"), "옛 꼴은 예전처럼 엄격하다: {text}");
    // Node 없는 꼴: 기본팩 없이(-) .htlayout과 지금 저장소.
    let fresh = k.dir.join("fresh.db");
    let (ok, text) = run(&[&p("import-layout"), &p("-"), &k.layout, &fresh, &p("--from-store"), &old]);
    assert!(ok, "{text}");
    let answer: Value = serde_json::from_str(text.trim()).unwrap();
    assert_eq!(answer["packs"][1]["original"], 1);
    assert_eq!(answer["verify"]["dup"], 0);
    same_store(&old, &fresh, true);
    // 점검만.
    let (ok, text) = run(&[&p("check-layout"), &k.layout, &p("--from-store"), &old]);
    assert!(ok, "{text}");
    assert_eq!(serde_json::from_str::<Value>(text.trim()).unwrap()["check_only"], true);
    let (ok, text) = run(&[&p("check-layout"), &k.base]);
    assert!(!ok && text.contains("아카이브 배치 파일(.htlayout)이 아닙니다."), "{text}");
    // 원본 꺼내기.
    let out = k.dir.join("꺼냄.htpack");
    let (ok, text) = run(&[&p("pack-out"), &fresh, &p("base-pack"), &out]);
    assert!(ok, "{text}");
    assert_eq!(std::fs::read(&out).unwrap(), std::fs::read(&k.base).unwrap());
    // 표본 타일 검사는 lib로 옮긴 뒤에도 같은 꼴로 찍는다.
    let (ok, text) = run(&[&p("verify-tiles"), &fresh, &p("120")]);
    assert!(ok, "{text}");
    assert!(text.contains("\"누락_중복\":0"), "{text}");
    std::fs::remove_dir_all(&k.dir).unwrap();
}

//! 집합 보기(10건 6 · 감독 선택 D4 결정 1 A · 2 A · 5 A)의 엔진 몫 — 내보내기(`export/boards.mjs`)가 판마다 미리 셈해
//! 겉 열쇠 `boards`에 싣는 판 트랙 · 변형 kind 3(`view:<id>`)을 가져오기 · 타일 · `rows_near` · `layout`이 나르는지 본다.
//! 이름은 모두 가상이다.
//!
//! 확인하는 것:
//! - `boards`를 실어도 **변형을 켜지 않은 답은 `boards`가 없는 저장소와 바이트까지 같다**(타일 · rows_near).
//! - 판 트랙은 옛 트랙 **뒤에** 붙고(옛 줄 번호 그대로) `layout`의 변형에 kind 3 · 쌓는 차례 · 묶음(원래 트랙 칩 kind 3)이 실린다.
//! - 원래 트랙에서 판으로 옮긴 줄은 `after −2`이고 `ord`에 그 줄이 옮겨 간 판 줄의 **전체 번호**가 실린다.
//! - 판을 켜면 띠가 판 줄로 옮겨 가고(칸 · 사건이 따라간다) 기본 판을 가린 항목은 빠지며,
//!   **판의 항목은 가리키는 띠를 따라 다시 옮기지 않는다** — 두 끝이 모두 이사한 판 안의 승계선이 한 줄로 오그라들지 않는다.
//! - `rows_near`가 판 줄을 내용 있는 줄로, 떠난 줄을 빈 줄로 답한다.
use archive_engine::legacy::import_layout;
use archive_engine::tile::{build_tile, decode, Decoded, TileRequest};
use archive_engine::Store;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::PathBuf;

/// 한 해 ≈ 분(검사 안에서만 쓰는 어림값).
const Y: i64 = 525_600;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-boards-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// 규격 2 전용 팩(머리 20바이트 + 지문 32바이트 + zlib 본문 — `tests/format3.rs`와 같은 꼴).
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

fn row() -> Value {
    json!({"height":126,"bandTop":19,"bandH":107,"dynTop":-1,"leadTop":23,"cabTop":-1,"textTop":46,"lines":2,"railTop":88,"organTop":-1})
}

fn band(uid: &str, track: i64, row: i64, from: i64, to: i64) -> Value {
    json!({"uid":uid,"track":track,"row":row,"start":from * Y,"end":to * Y,"fuzzy":0,"color":0xa0bcc5,"name":uid,"look":0,"tag":"","sub":0})
}

fn event(uid: &str, track: i64, row: i64, at: i64, band: &str) -> Value {
    json!({"uid":uid,"track":track,"row":row,"start":at * Y,"end":at * Y,"importance":2,"title":uid,"band":band})
}

/// 관계선(구역 21) 하나 — 가리키는 것(ref)은 **위쪽 끝**의 띠.
fn link(track: i64, row: i64, row2: i64, from: &str, to: &str) -> Value {
    json!({"section":21,"track":track,"row":row,"row2":row2,"start":100 * Y,"end":100 * Y,"lod":14,"ref":from,"name":format!("{from} → {to}"),
        "color":0xa0bcc5,"a":0,"b":0,"c":0,"d":0,"text2":to})
}

/// 옛 열쇠만 있는 배치: 트랙 둘(가 · 나) · 줄 셋씩.
///   가 트랙: 줄 0 = 갑 왕국(bd/a) · 줄 1 = 을 왕국(bd/b) · 줄 2 = 빈 줄 — 갑 → 을 승계선(줄 0~1)
///   나 트랙: 줄 0 = 병 왕국(bd/d) · 줄 1 = 정 왕국(bd/c) · 줄 2 = 빈 줄
fn base_plan() -> Value {
    json!({
        "name":"집합 보기 검사",
        "packs":[{"id":"bd","name":"집합 보기 검사"}],
        "categories":[{"key":"etc","name":"기타","color":0xa4b1b7}],
        "tracks":[
            {"key":"ta","name":"가 트랙","color":0xa0bcc5,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,"rows":[row(),row(),row()],"groups":[]},
            {"key":"tb","name":"나 트랙","color":0xbcd8c1,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,"rows":[row(),row(),row()],"groups":[]}
        ],
        "epochs":[], "axis":[],
        "periods":[band("bd/a",0,0,0,200), band("bd/b",0,1,150,400), band("bd/d",1,0,0,300), band("bd/c",1,1,100,350)],
        "cells":[{"period":"bd/a","kind":1,"lane":0,"start":0,"end":100 * Y,"name":"갑 첫 임금","style":0,"color":0}],
        "events":[event("ev-a",0,0,50,"bd/a"), event("ev-c",1,1,120,"bd/c"), event("ev-d",1,0,60,"bd/d")],
        "items":[link(0,0,1,"bd/a","bd/b")],
        "entities":[], "rowLabels":[], "variants":[]
    })
}

/// 판 하나(`view:v1` — 갑 왕국 · 정 왕국)를 겉 열쇠 `boards`로 더한 배치. 판 트랙 = 트랙 2(전체 줄 6 · 7).
fn board_plan() -> Value {
    let mut plan = base_plan();
    let mut board_row = row();
    board_row["variant"] = json!("view:v1");
    let mut board_link = link(2, 0, 1, "bd/a", "bd/c");
    board_link["variant"] = json!("view:v1");
    plan["boards"] = json!({
        "tracks":[{"key":"__board:view:v1","name":"집합 보기","color":0xd7c18e,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,
            "rows":[board_row.clone(), board_row],"groups":[],"pack":0}],
        "variants":[{
            "key":"view:v1","kind":3,"track":2,"band":"","uid":"view:v1","name":"두 나라 견주기","notes":"",
            "rows":[
                {"track":2,"row":0,"after":-1,"ord":0,"new":1,"scopePad":16,"groupStart":1},
                {"track":2,"row":1,"after":0,"ord":0,"new":1,"scopePad":0,"groupStart":1},
                {"track":0,"row":0,"after":-2,"ord":0,"new":0,"scopePad":0,"groupStart":0,"toTrack":2,"to":0},
                {"track":1,"row":1,"after":-2,"ord":0,"new":0,"scopePad":0,"groupStart":0,"toTrack":2,"to":1},
                {"track":0,"row":1,"after":-1,"ord":0,"new":0,"scopePad":0,"groupStart":0}
            ],
            "moves":[{"kind":1,"ref":"bd/a","track":2,"row":0},{"kind":1,"ref":"bd/c","track":2,"row":1}],
            "hides":[{"kind":4,"at":0}],
            "groups":[
                {"track":2,"key":"__from:ta#0","depth":0,"name":"가 트랙","color":0xa0bcc5,"kind":3,"rows":[0]},
                {"track":2,"key":"__from:tb#1","depth":0,"name":"나 트랙","color":0xbcd8c1,"kind":3,"rows":[1]}
            ]
        }],
        "items":[board_link],
        "entities":[{"uid":"board:view:v1","kind":"board","pack":0,"json":json!({"key":"view:v1","name":"두 나라 견주기","present":2}).to_string()}]
    });
    plan
}

fn build(name: &str, plan: &Value) -> (PathBuf, Store) {
    let dir = scratch(name);
    let pack = dir.join("검사.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"bd","name":"집합 보기 검사"}))).unwrap();
    let file = dir.join("layout.json");
    std::fs::write(&file, serde_json::to_vec(plan).unwrap()).unwrap();
    let target = dir.join("archive.db");
    import_layout(&pack, &file, &target, &[]).unwrap();
    let store = Store::open(&target).unwrap();
    (dir, store)
}

fn ask(s: &Store, q: Value) -> Value {
    s.call(&q).unwrap_or_else(|e| panic!("{q}: {e}"))
}

fn tile(s: &Store, level: usize, x: i64, chunk: i64, variants: &[&str]) -> Vec<u8> {
    let v = s.variants_of(&json!({ "variants": variants })).unwrap();
    build_tile(s, &TileRequest { level, x, chunk, packs: vec![1], filter: None, variants: v }).unwrap()
}

fn section(t: &Decoded, kind: u32) -> Vec<(u32, u32, String)> {
    t.sections
        .iter()
        .filter(|s| s.kind == kind)
        .flat_map(|s| s.items.iter().map(|i| (i.row, i.row2, t.strings[i.name as usize].clone())))
        .collect()
}

#[test]
fn 판이_없으면_답은_예전과_같다() {
    let (_d0, plain) = build("plain", &base_plan());
    let (_d1, boards) = build("boards", &board_plan());
    for level in [4usize, 8, 12, 14] {
        let x = archive_engine::levels::tile_of(100 * Y, level);
        assert_eq!(tile(&plain, level, x, 0, &[]), tile(&boards, level, x, 0, &[]), "단계 {level}: 판을 켜지 않은 타일이 달라졌다");
    }
    let near = |s: &Store| ask(s, json!({"op":"rows_near","near":[0, 500 * Y],"far":[0, 500 * Y],"fade":0,"packs":[1]}));
    let base = near(&plain);
    // 판 트랙의 줄(6 · 7)은 그 변형의 줄이라 켜지 않으면 없는 것과 같다.
    assert_eq!(base, near(&boards));
    assert_eq!(base["near"], json!([0, 1, 3, 4]));
}

#[test]
fn 판_트랙과_변형이_layout에_실린다() {
    let (_d, s) = build("layout", &board_plan());
    let layout = ask(&s, json!({"op":"layout"}));
    let tracks = layout["tracks"].as_array().unwrap();
    assert_eq!(tracks.len(), 3);
    assert_eq!(tracks[2]["key"], "__board:view:v1", "판 트랙은 옛 트랙 뒤에");
    let rows: Vec<i64> = tracks[2]["rows"].as_array().unwrap().iter().map(|r| r["id"].as_i64().unwrap()).collect();
    assert_eq!(rows, vec![6, 7], "옛 줄 번호는 그대로 · 판 줄은 그 뒤");
    assert!(tracks[2]["rows"].as_array().unwrap().iter().all(|r| r["variant"].as_i64().unwrap() > 0), "판 줄은 모두 그 변형의 줄");
    let v = layout["variants"].as_array().unwrap().iter().find(|v| v["key"] == "view:v1").expect("판 변형");
    assert_eq!(v["kind"], 3);
    assert_eq!(v["track"], tracks[2]["id"]);
    let rows = v["rows"].as_array().unwrap();
    let of = |row: i64| rows.iter().find(|r| r["row"] == row).unwrap_or_else(|| panic!("줄 {row}"));
    assert_eq!(of(0)["after"], -2, "판으로 옮긴 줄은 빠진다");
    assert_eq!(of(0)["ord"], 6, "옮겨 간 판 줄의 전체 번호");
    assert_eq!(of(4)["after"], -2);
    assert_eq!(of(4)["ord"], 7);
    assert_eq!(of(1)["after"], -1, "남은 줄은 트랙 맨 위로");
    assert_eq!(of(6)["after"], -1);
    assert_eq!(of(7)["after"], 6);
    assert_eq!(of(6)["scope_pad"], 16);
    let groups = v["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0]["kind"], 3, "원래 트랙 칩");
    assert_eq!(groups[0]["rows"], json!([6]));
    assert_eq!(groups[1]["rows"], json!([7]));
    // 판 기록은 항목 기록으로(이름 표에는 들지 않는다).
    let rec = ask(&s, json!({"op":"entity","uid":"board:view:v1"}));
    assert_eq!(rec["kind"], "board");
}

#[test]
fn 판을_켜면_줄이_판으로_모이고_판_안의_선은_오그라들지_않는다() {
    let (_d, s) = build("on", &board_plan());
    let level = 12usize;
    let x = archive_engine::levels::tile_of(100 * Y, level);
    let t = decode(&tile(&s, level, x, 0, &["view:v1"])).unwrap();
    let mut bands: Vec<(String, u32)> = t.bands.iter().map(|b| (t.strings[b.name as usize].clone(), b.row)).collect();
    bands.sort();
    assert_eq!(bands, vec![("bd/a".into(), 6), ("bd/b".into(), 1), ("bd/c".into(), 7), ("bd/d".into(), 3)]);
    // 칸은 제 띠를 따라간다.
    assert!(t.cells.iter().all(|c| c.row == 6), "갑 왕국의 칸은 판 줄 6으로");
    // 사건은 든 띠를 따라간다(따로 옮기지 않아도).
    let mut events: Vec<(String, u32)> = t.events.iter().map(|e| (t.strings[e.name as usize].clone(), e.row)).collect();
    events.sort();
    assert_eq!(events, vec![("ev-a".into(), 6), ("ev-c".into(), 7), ("ev-d".into(), 3)]);
    // 기본의 갑 → 을 선(가린 것)은 없고, 판 안의 갑 → 정 선은 6~7 그대로(가리키는 갑 왕국이 줄 6으로 이사했어도 오그라들지 않는다).
    assert_eq!(section(&t, 21), vec![(6, 7, "bd/a → bd/c".to_owned())]);
    // 판을 끄면 그대로.
    let off = decode(&tile(&s, level, x, 0, &[])).unwrap();
    assert_eq!(section(&off, 21), vec![(0, 1, "bd/a → bd/b".to_owned())]);
    // rows_near: 판 줄(6 · 7)과 남은 줄(1 · 3)만 — 떠난 줄(0 · 4)은 빈 줄이다.
    let near = ask(&s, json!({"op":"rows_near","near":[0, 500 * Y],"far":[0, 500 * Y],"fade":0,"packs":[1],"variants":["view:v1"]}));
    assert_eq!(near["near"], json!([1, 3, 6, 7]));
}

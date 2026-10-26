//! 지금 연표가 계산한 줄 배치(JSON 3판)를 새 저장소로 가져오는 길의 검사.
//! 내보내기 쪽이 열을 하나씩 넓히는 중이므로, 빠진 열쇠는 기본값으로 읽고 모르는 열쇠는 무시해야 한다.
mod common;
use archive_engine::legacy::{import_layout, import_layout_value};
use archive_engine::levels::lod_of;
use archive_engine::span::days_from_civil;
use archive_engine::Store;
use common::plans::{packs_of, plan as scene};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::PathBuf;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-import-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// 규격 2 전용 팩을 검사 안에서 만든다(머리 20바이트 + 지문 32바이트 + zlib 본문).
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

/// 새 열을 모두 갖춘 줄.
fn row(height: i64) -> Value {
    json!({"height":height,"bandTop":19,"bandH":height-19,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1,
        "kind":1,"groupStart":1,"scopePad":6,"phase":2,"rank":1,"cats":[0,2],"fig":2,"figWide":3,"dep":25,"zones":2,"hem":1})
}

/// 2판의 열만 있는 줄(3판의 열은 모두 빠졌다).
fn bare_row(height: i64) -> Value {
    json!({"height":height,"bandTop":19,"bandH":height-19,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1})
}

fn layout() -> Value {
    json!({
        "name": "검사 기록집",
        "categories": [{"key":"govern","name":"다스림","color":0x8f7fb0}, {"key":"lore","name":"이야기","color":0x9a6f8a}],
        "tracks": [
            {"name":"첫 트랙","color":0xc8b193,"dynasty":1,"leader":1,"cabinet":1,"organ":0,"railLevels":3,"rows":[row(126), bare_row(140)],
             "groups":[{"depth":0,"first":0,"count":2,"name":"윗물 겨레","color":0xbcd8c1,"kind":0}], "모르는 열쇠":"무시한다"},
            {"name":"둘째 트랙","rows":[bare_row(133)]}
        ],
        "epochs": [{"start":-5000,"end":9000,"color":0xc8b193,"name":"첫 시대"}],
        "axis": [
            {"kind":1,"track":-1,"lane":0,"start":-5000,"end":9000,"name":"첫 시대","color":0xc8b193,"style":0,"strip":0,"seq":0},
            {"kind":2,"track":0,"lane":1,"start":-4000,"end":-1,"name":"첫길 연호","color":0x9dbea8,"style":1,"strip":7,"seq":2},
            {"kind":3,"track":1,"start":0,"end":100,"name":"별여울 도읍"}
        ],
        "periods": [
            {"uid":"p-a","track":0,"row":0,"start":-4000,"end":-1,"fuzzy":1,"color":0xa0bcc5,"name":"별여울국","look":0x21,"tag":"전해 오는 이야기","sub":3},
            {"uid":"p-b","track":0,"row":0,"start":0,"end":5000,"fuzzy":0,"color":0x9dbea8,"name":"해솔국"},
            {"uid":"p-c","track":0,"row":1,"start":100,"end":900,"fuzzy":0,"color":0xd7c18e,"name":"은빛 나루"},
            {"uid":"p-d","track":1,"row":0,"start":-300,"end":8000,"fuzzy":2,"color":0xbbacc8,"name":"여울 연맹"},
            {"uid":"p-e","track":0,"row":0,"start":-3000,"end":2000,"color":0xb6c398,"name":"바탕 문화","look":9}
        ],
        "cells": [
            {"period":"p-a","kind":1,"start":-4000,"end":-2000,"name":"첫째 지도자"},
            {"period":"p-a","kind":1,"start":-1999,"end":-1,"name":"둘째 지도자","lane":1,"style":4,"color":0xd1a9b9},
            {"period":"p-a","kind":1,"start":-3000,"end":-2500,"name":"겹쳐 깔린 칸","lane":1},
            {"period":"p-b","kind":2,"start":0,"end":2500,"name":"첫 내각"},
            {"period":"p-d","kind":0,"start":-300,"end":8000,"name":"여울 왕조"},
            {"period":"p-d","kind":3,"start":10,"end":700,"name":"나루 관청"}
        ],
        "events": [
            {"uid":"e1","track":0,"row":0,"start":-3500,"end":-3500,"importance":3,"title":"별여울의 첫 기록","body":"가상 본문","look":2,"label":"12년","rail":1,"band":"p-a"},
            {"uid":"e2","track":0,"row":0,"start":10,"end":10,"importance":1,"title":"해솔의 나루 열기","body":"","band":"없는 띠"},
            {"uid":"e3","track":0,"row":1,"start":200,"end":700,"importance":2,"title":"은빛 나루의 긴 공사","body":""},
            {"uid":"e4","track":1,"row":0,"start":0,"end":0,"importance":1,"title":"여울 모임","body":""},
            {"uid":"e5","track":1,"row":0,"start":null,"end":null,"importance":1,"title":"날짜를 모르는 일","body":""},
            {"uid":"e6","track":1,"row":0,"start":7000,"end":7000,"importance":2,"title":"연맹의 새 약속","body":""},
            {"uid":"e7","track":0,"row":1,"start":150,"end":150,"importance":1,"title":"작은 일 하나","body":""},
            {"uid":"e8","track":0,"row":1,"start":151,"end":151,"importance":1,"title":"작은 일 둘","body":""},
            {"uid":"e9","track":0,"row":0,"start":4999,"end":4999,"importance":3,"title":"해솔국의 마지막 해","body":""}
        ],
        "items": [
            {"section":16,"track":0,"row":0,"row2":0,"start":-4000,"end":-1,"lod":-1,"ref":"p-a","name":"별여울 속국","color":0xa0bcc5,"a":1,"b":2,"c":3,"d":4,"text2":"곁글"},
            {"section":17,"track":0,"row":0,"row2":1,"start":0,"end":0,"lod":12,"ref":"e3"},
            {"section":18,"track":1,"row":0,"start":-300,"end":8000,"ref":"없는 이름","모르는 열쇠":1}
        ],
        "entities": [
            {"uid":"p-a","kind":"period","json":"{\"uid\":\"p-a\",\"name\":\"별여울국\"}"},
            {"uid":"e1","kind":"event","json":"{\"uid\":\"e1\"}"}
        ],
        "rowLabels": [
            {"period":"p-b","track":0,"row":0,"kind":0,"name":"해솔국","years":"0–5000","color":0x9dbea8,"start":0,"end":5000,"cap":1,"member":0,"lanes":[0,2]},
            {"period":"p-a","track":0,"row":0,"kind":0,"name":"별여울국","years":"BC 4000–1","color":0xa0bcc5,"cap":0,"member":0,"lanes":[]},
            {"period":"","track":1,"row":0,"kind":1,"name":"그 밖","color":0x9c978d}
        ]
    })
}

fn imported(name: &str) -> (PathBuf, PathBuf, Value) {
    imported_with(name, &layout())
}

/// [`imported`]와 같되 배치를 직접 준다.
fn imported_with(name: &str, layout: &Value) -> (PathBuf, PathBuf, Value) {
    let dir = scratch(name);
    let pack = dir.join("검사.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","name":"검사 기록집"}))).unwrap();
    let plan = dir.join("layout.json");
    std::fs::write(&plan, serde_json::to_vec(layout).unwrap()).unwrap();
    let target = dir.join("out").join("archive.db");
    let counts = import_layout(&pack, &plan, &target, &[]).unwrap();
    (dir, target, counts)
}

#[test]
fn 배치를_가져오면_트랙_줄_띠_칸_사건이_전체_줄_번호로_들어간다() {
    let dir = scratch("ok");
    let pack = dir.join("검사.htpack");
    let bytes = htpack(&json!({"format":"history-timeline-dlc","name":"검사 기록집"}));
    std::fs::write(&pack, &bytes).unwrap();
    let plan = dir.join("layout.json");
    std::fs::write(&plan, serde_json::to_vec(&layout()).unwrap()).unwrap();
    let target = dir.join("out").join("archive.db");
    let counts = import_layout(&pack, &plan, &target, &[]).unwrap();
    assert_eq!(counts, json!({"tracks":2,"rows":3,"groups":1,"categories":2,"periods":5,"cells":6,"epochs":1,"axis":3,"events":9,"unknown":1,"items":3,"entities":2,"row_labels":3,
        "variants":0,"variant_rows":0,"variant_moves":0,"variant_hides":0,"variant_groups":0}));

    let s = Store::open(&target).unwrap();
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    assert_eq!(shape["packs"], json!([{"id":1,"name":"검사 기록집","events":9,"key":"","periods":5,"touches":[1,2],"version":"","category":"","original":1}]), "id가 없는 전용 팩은 열쇠가 빈 글 · 판을 모르면 빈 글 · 원본을 품었으면 1");
    let tracks = shape["tracks"].as_array().unwrap();
    assert_eq!(tracks.len(), 2);
    assert_eq!(tracks[0]["name"], "첫 트랙");
    assert_eq!(tracks[0]["rows"].as_array().unwrap().iter().map(|r| r["id"].as_i64().unwrap()).collect::<Vec<_>>(), vec![0, 1]);
    assert_eq!(tracks[1]["rows"][0]["id"], 2);
    // 한 벌 P3-18의 이름 붙은 칸(줄 깃발 · 그릇 여백의 가름)도 곁에 붙는다.
    assert_eq!(tracks[0]["rows"][1], json!({"id":1,"height":140,"band_top":19,"band_h":121,"dyn_top":-1,"lead_top":23,"cab_top":46,"text_top":66,"text_lines":2,"rail_top":108,"organ_top":-1,
        "kind":0,"group_start":0,"scope_pad":0,"phase":0,"rank":0,"cats":[],"fig":0,"fig_wide":0,"dep":0,"zones":0,"hem":0,"variant":0,
        "fig_wide_levels":0,"rail":-1,"organ":0,"power":0,"real":0,"hang":0,"raised":0,"contained":0,"cell_rows":0,"dynasty":0,"leader":0,"cabinet":0,"events":1,
        "scope_head":0,"scope_foot":0,"scope_hung":0}));
    assert_eq!(shape["epochs"], json!([{"id":1,"pack":1,"start":-5000,"end":9000,"color":0xc8b193,"name":"첫 시대"}]));

    // 둘째 트랙의 첫 줄은 전체 줄 번호 2다 — 띠 · 칸의 색인 · 사건 · 일반 항목이 모두 그 번호로 들어간다.
    let row_of = |sql: &str| -> Vec<i64> { let mut st = s.db.prepare(sql).unwrap(); let v = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(row_of("SELECT row FROM periods ORDER BY id"), vec![0, 0, 1, 2, 0]);
    assert_eq!(row_of("SELECT lane FROM events ORDER BY id"), vec![0, 0, 1, 2, 2, 2, 1, 1, 0]);
    assert_eq!(row_of("SELECT row_min FROM cell_bounds ORDER BY id"), vec![0, 0, 0, 0, 2, 2]);
    assert_eq!(row_of("SELECT kind FROM cells ORDER BY id"), vec![1, 1, 1, 2, 0, 3]);
    assert_eq!(row_of("SELECT row FROM items ORDER BY id"), vec![0, 0, 2]);
    assert_eq!(row_of("SELECT row2 FROM items ORDER BY id"), vec![0, 1, 2], "row2가 빠지면 한 줄짜리");
    let kept: (Vec<u8>, String) = s.db.query_row("SELECT original,sha256 FROM packs WHERE id=1", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    assert_eq!(kept.0, bytes, "원본 전용 팩을 그대로 보존");
    assert_eq!(kept.1, format!("{:x}", Sha256::digest(&bytes)));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 새_열은_그대로_들어가고_빠진_열쇠는_기본값이_된다() {
    let (dir, target, _) = imported("defaults");
    let s = Store::open(&target).unwrap();
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    let tracks = shape["tracks"].as_array().unwrap();
    assert_eq!((tracks[0]["color"].as_i64(), tracks[0]["organ"].as_i64(), tracks[0]["rail_levels"].as_i64()), (Some(0xc8b193), Some(0), Some(3)));
    // 둘째 트랙은 색 · 단 · 묶음이 모두 빠졌다. railLevels만은 스키마의 기본값 2다(막대는 적어도 두 단).
    assert_eq!((tracks[1]["color"].as_i64(), tracks[1]["dynasty"].as_i64(), tracks[1]["leader"].as_i64(), tracks[1]["rail_levels"].as_i64()), (Some(0), Some(0), Some(0), Some(2)));
    assert_eq!(tracks[1]["groups"], json!([]));
    let first = &tracks[0]["rows"][0];
    assert_eq!((first["kind"].as_i64(), first["group_start"].as_i64(), first["scope_pad"].as_i64(), first["phase"].as_i64()), (Some(1), Some(1), Some(6), Some(2)));
    assert_eq!((first["rank"].as_i64(), first["fig"].as_i64(), first["dep"].as_i64(), first["zones"].as_i64(), first["hem"].as_i64()), (Some(1), Some(2), Some(25), Some(2), Some(1)));
    assert_eq!(first["cats"], json!([0, 2]));
    // figWide는 '넉넉하게'에서만 단이 느는 줄에 실려 온다. 빠진 줄은 fig와 같다.
    assert_eq!((first["fig_wide"].as_i64(), tracks[0]["rows"][1]["fig_wide"].as_i64()), (Some(3), Some(0)));
    assert_eq!(shape["categories"], json!([{"id":1,"key":"govern","name":"다스림","color":0x8f7fb0},{"id":2,"key":"lore","name":"이야기","color":0x9a6f8a}]));
    // 날짜 칸: track −1은 공통 줄(0), 빠진 lane · style · strip · seq는 0.
    assert_eq!(shape["axis"], json!([
        [1, 0, 0, -5000, 9000, "첫 시대", 0xc8b193, 0, 0, 0],
        [2, 1, 1, -4000, -1, "첫길 연호", 0x9dbea8, 1, 7, 2],
        [3, 2, 0, 0, 100, "별여울 도읍", 0, 0, 0, 0]]));
    // 띠 · 칸 · 사건의 새 열
    let band: (i64, String, i64, String) = s.db.query_row("SELECT look,tag,sub,uid FROM periods WHERE id=1", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).unwrap();
    assert_eq!(band, (0x21, "전해 오는 이야기".to_owned(), 3, "p-a".to_owned()));
    let plain: (i64, String, i64) = s.db.query_row("SELECT look,tag,sub FROM periods WHERE id=2", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap();
    assert_eq!(plain, (0, String::new(), 0));
    let cell: (i64, i64, i64) = s.db.query_row("SELECT lane,style,color FROM cells WHERE id=2", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap();
    assert_eq!(cell, (1, 4, 0xd1a9b9));
    let event: (i64, String, i64, String, i64) = s.db.query_row("SELECT look,label,rail,uid,band FROM events WHERE id=1", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).unwrap();
    assert_eq!(event, (2, "12년".to_owned(), 1, "e1".to_owned(), 1), "band는 uid가 가리키는 띠의 번호");
    let bare: (i64, String, i64, i64) = s.db.query_row("SELECT look,label,rail,band FROM events WHERE id=2", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).unwrap();
    assert_eq!(bare, (0, String::new(), 0, 0), "없는 띠를 가리키면 0");
    assert_eq!(s.call(&json!({"op":"entity","uid":"p-a"})).unwrap()["kind"], "period");
    // 줄 이름 후보: 트랙/줄 번호 → 전체 줄 번호 · period uid → 띠 번호 · start · end가 없으면 그 띠의 기간.
    let labels = s.call(&json!({"op":"row_labels","rows":[0,2]})).unwrap();
    assert_eq!(labels["labels"][0]["items"].as_array().unwrap().len(), 2);
    assert_eq!(labels["labels"][0]["items"][0]["name"], "별여울국", "시작 순");
    assert_eq!(labels["labels"][1]["items"][0]["kind"], 1);
    let spans: Vec<(i64, i64, i64, i64)> = { let mut st = s.db.prepare("SELECT row,start,end,period FROM row_labels ORDER BY rowid").unwrap();
        let v = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(spans, vec![(0, 0, 5000, 2), (0, -4000, -1, 1), (2, 0, 0, 0)]);
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 일반_항목의_가리킴과_가늘기_등급() {
    let (dir, target, _) = imported("items");
    let s = Store::open(&target).unwrap();
    let refs: Vec<i64> = { let mut st = s.db.prepare("SELECT ref FROM items ORDER BY id").unwrap(); let v = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect(); v };
    // p-a는 띠 1번, e3은 사건 3번, 없는 이름은 0.
    assert_eq!(refs, vec![1, 3, 0]);
    let lods: Vec<i64> = { let mut st = s.db.prepare("SELECT lod_max FROM item_bounds ORDER BY id").unwrap(); let v = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect(); v };
    // lod −1은 기간에서 셈하고, 값이 있으면 그대로, 빠지면 −1과 같다.
    assert_eq!(lods, vec![lod_of(3999), 12, lod_of(8300)]);
    let one: (i64, i64, i64, i64, i64, String) = s.db.query_row("SELECT a,b,c,d,color,text2 FROM items WHERE id=1", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))).unwrap();
    assert_eq!(one, (1, 2, 3, 4, 0xa0bcc5, "곁글".to_owned()));
    let empty: (i64, i64, String) = s.db.query_row("SELECT a,color,name FROM items WHERE id=3", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap();
    assert_eq!(empty, (0, 0, String::new()));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 겹쳐_깔린_띠와_겹친_단의_칸도_받아들인다() {
    // 3단계에서는 바탕 문화처럼 같은 줄에 겹쳐 깔리는 띠와, 같은 단에 겹치는 칸이 들어온다.
    let (dir, target, counts) = imported("overlap");
    assert_eq!(counts["periods"], 5);
    let s = Store::open(&target).unwrap();
    let same: i64 = s.db.query_row("SELECT count(*) FROM periods WHERE row=0 AND start<=2000 AND end>=-3000", [], |r| r.get(0)).unwrap();
    assert!(same >= 3, "같은 줄의 같은 때에 띠가 셋 이상: {same}");
    let lanes: i64 = s.db.query_row("SELECT count(*) FROM cells WHERE lane=1 AND kind=1", [], |r| r.get(0)).unwrap();
    assert_eq!(lanes, 2, "같은 단에 겹친 칸 둘");
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 없는_띠를_가리키는_칸이나_없는_줄의_사건은_거절하고_저장소를_남기지_않는다() {
    for (name, damage) in [
        ("cell", Box::new(|v: &mut Value| v["cells"][0]["period"] = json!("p-없음")) as Box<dyn Fn(&mut Value)>),
        ("row", Box::new(|v: &mut Value| v["events"][0]["row"] = json!(7))),
        ("track", Box::new(|v: &mut Value| v["periods"][0]["track"] = json!(9))),
        ("item-row", Box::new(|v: &mut Value| v["items"][0]["row2"] = json!(9))),
        ("entity-uid", Box::new(|v: &mut Value| v["entities"][0]["uid"] = json!(""))),
    ] {
        let dir = scratch(name);
        let pack = dir.join("검사.htpack");
        std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","name":"검사 기록집"}))).unwrap();
        let mut broken = layout();
        damage(&mut broken);
        let plan = dir.join("layout.json");
        std::fs::write(&plan, serde_json::to_vec(&broken).unwrap()).unwrap();
        let target = dir.join("archive.db");
        assert!(import_layout(&pack, &plan, &target, &[]).is_err(), "{name}");
        assert!(!target.exists(), "{name}: 실패한 가져오기는 저장소를 남기지 않는다");
        std::fs::remove_dir_all(dir).unwrap();
    }
}

#[test]
fn 얹은_dlc의_글자_id가_열쇠로_남아_다시_지어도_같은_dlc를_알아본다() {
    let dir = scratch("pack-keys");
    let pack = dir.join("기본.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"base-pack","name":"기본 기록집"}))).unwrap();
    let extra = dir.join("얹은.htpack");
    std::fs::write(&extra, htpack(&json!({"format":"history-timeline-dlc","id":"extra-pack","name":"얹은 기록집","version":2}))).unwrap();
    let mut plan = layout();
    plan["packs"] = json!([{"id":"base-pack","name":"기본 기록집"},{"id":"extra-pack","name":"얹은 기록집"}]);
    // 둘째 트랙과 그 줄의 사건 하나는 얹은 DLC의 것이다(`pack` 순번).
    plan["tracks"][1]["pack"] = json!(1);
    plan["events"][3]["pack"] = json!(1);
    let plan_path = dir.join("layout.json");
    std::fs::write(&plan_path, serde_json::to_vec(&plan).unwrap()).unwrap();
    let target = dir.join("out").join("archive.db");
    import_layout(&pack, &plan_path, &target, &[&extra]).unwrap();
    let s = Store::open(&target).unwrap();
    let keys: String = s.db.query_row("SELECT value FROM meta WHERE key='pack_keys'", [], |r| r.get(0)).unwrap();
    assert_eq!(serde_json::from_str::<Value>(&keys).unwrap(), json!({"1":"base-pack","2":"extra-pack"}));
    let shape = s.call(&json!({"op":"layout"})).unwrap();
    assert_eq!(shape["packs"][0]["key"], "base-pack");
    // 담긴 것: 띠는 모두 기본 DLC의 것(uid에 앞머리가 없다) · 얹은 DLC는 사건 하나를 둘째 트랙(id 2)에 두었다 → 그 트랙에 '닿는다'.
    assert_eq!(shape["packs"][0]["periods"], 5);
    assert_eq!(shape["packs"][0]["touches"], json!([1, 2]));
    assert_eq!(shape["packs"][1], json!({"id":2,"name":"얹은 기록집","events":1,"key":"extra-pack","periods":0,"touches":[2],"version":"2","category":"","original":1}), "판은 배치에 없으면 원본의 팩 정보에서");
    assert_eq!(shape["tracks"][1]["pack"], 2, "둘째 트랙은 얹은 DLC의 것");
    let periods_meta: String = s.db.query_row("SELECT value FROM meta WHERE key='pack_periods'", [], |r| r.get(0)).unwrap();
    assert_eq!(serde_json::from_str::<Value>(&periods_meta).unwrap(), json!({"1":5}));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

/// 항목 기록 json의 지문 — SHA-256 16진 글의 앞 16자(계획 P4 과제 5a).
fn sum16(json: &str) -> String {
    format!("{:x}", Sha256::digest(json.as_bytes()))[..16].to_owned()
}

fn meta_text(s: &Store, key: &str) -> Option<String> {
    s.db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get(0)).ok()
}

/// `2026-10-16T06:14:40Z` 꼴의 글 → 1970년부터의 초(꼴이 다르면 None).
fn iso_secs(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    let shaped = text.is_ascii() && b.len() == 20 && b[4] == b'-' && b[7] == b'-' && b[10] == b'T' && b[13] == b':' && b[16] == b':' && b[19] == b'Z';
    if !shaped {
        return None;
    }
    let n = |from: usize, to: usize| text[from..to].parse::<i64>().ok();
    Some(days_from_civil(n(0, 4)?, n(5, 7)?, n(8, 10)?) * 86_400 + n(11, 13)? * 3600 + n(14, 16)? * 60 + n(17, 19)?)
}

fn unix_secs() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64
}

#[test]
fn 항목_기록은_배열의_넣은_차례와_json_지문을_적는다() {
    let (dir, target, _) = imported("entity-ord-sum");
    let s = Store::open(&target).unwrap();
    let rows: Vec<(String, i64, String)> = { let mut st = s.db.prepare("SELECT uid,ord,sum FROM entities ORDER BY uid").unwrap();
        let v = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap().map(|r| r.unwrap()).collect(); v };
    // 표는 uid 차례(e1 < p-a)로 놓이지만 ord는 배열(p-a, e1)의 차례 — 0부터. sum은 json 글의 SHA-256 앞 16자.
    assert_eq!(rows, vec![
        ("e1".to_owned(), 1, sum16(r#"{"uid":"e1"}"#)),
        ("p-a".to_owned(), 0, sum16(r#"{"uid":"p-a","name":"별여울국"}"#)),
    ]);
    assert!(rows.iter().all(|(_, _, sum)| sum.len() == 16 && sum.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 장면의_항목_기록은_겉_열쇠_판_기록까지_배열_차례_그대로_ord가_난다() {
    // 장면은 자료집 셋 · 기본 기록 + 판(boards) 기록이 있다. 지금 연표가 내보낸 차례(옛 열쇠 → 판 열쇠 뒤)가 ord다.
    let packs = ["a", "b", "c"];
    let plan = scene(&packs);
    let want: Vec<String> = plan["entities"].as_array().unwrap().iter().chain(plan["boards"]["entities"].as_array().unwrap())
        .map(|e| e["uid"].as_str().unwrap().to_owned()).collect();
    assert!(want.len() > 10 && want.iter().any(|u| u.starts_with("board:")), "장면에 판 기록이 있어야 이 검사가 뜻이 있다");
    let path = common::scratch("import-ord-scene");
    import_layout_value(&plan, &packs_of(&packs), &path).unwrap();
    let s = Store::open(&path).unwrap();
    let by_ord: Vec<String> = { let mut st = s.db.prepare("SELECT uid FROM entities ORDER BY ord").unwrap();
        let v = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(by_ord, want, "ord 차례가 배열 차례");
    let ords: Vec<i64> = { let mut st = s.db.prepare("SELECT ord FROM entities ORDER BY ord").unwrap();
        let v = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(ords, (0..want.len() as i64).collect::<Vec<_>>(), "빈틈 없이 0부터");
    let mut st = s.db.prepare("SELECT uid,json,sum FROM entities").unwrap();
    for row in st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?))).unwrap() {
        let (uid, json, sum) = row.unwrap();
        assert_eq!(sum, sum16(&json), "{uid}의 지문");
    }
}

#[test]
fn 저장소는_지은_날을_메타에_적는다_배치의_now가_있으면_그_글_그대로() {
    // 배치가 `now`를 주면(P3 Rust 배치가 굳은 시각으로 적는다) 그 글 그대로 — 같은 저장소를 다시 지을 수 있게.
    let mut given = layout();
    given["now"] = json!("2026-10-15T12:00:00+09:00");
    let (dir, target, _) = imported_with("now-given", &given);
    let s = Store::open(&target).unwrap();
    assert_eq!(meta_text(&s, "now").as_deref(), Some("2026-10-15T12:00:00+09:00"));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();

    // 없으면 지은 시각의 ISO 글(UTC · 초까지).
    let before = unix_secs();
    let (dir, target, _) = imported("now-made");
    let after = unix_secs();
    let s = Store::open(&target).unwrap();
    let text = meta_text(&s, "now").expect("meta.now");
    let made = iso_secs(&text).unwrap_or_else(|| panic!("UTC 초까지의 ISO 글이 아닙니다: {text}"));
    assert!((before..=after).contains(&made), "지은 시각이 아닙니다: {text} ({before}..{after})");
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

/// 스키마 4(계약 1-1)를 싣는 고대만의 배치 — 자료집 둘(기본 · 얹은 것) · 띠의 `form` · 최상위 `sphereLines`(kind 1 · 2 · 3).
/// 모든 값이 0분(1970년)보다 이르다 — kind 3의 start · end = 0이 자료 범위 밖이어서, 짓기가 그것으로 시간 범위를 넓히면 `meta.max`가 바뀐다.
fn ancient(lines: bool) -> Value {
    let mut plan = json!({
        "packs": [{"id":"base-pack","name":"기본 기록집"},{"id":"extra-pack","name":"얹은 기록집"}],
        "tracks": [{"name":"동녘 트랙","key":"east-old","sphere":"east","rows":[bare_row(126)]}],
        "periods": [
            // 종류 0(국가) + 1 · 관계 2(봉국) · 정통성 0(정통) + 1 · 중요도 2 + 1
            {"uid":"p-a","track":0,"row":0,"start":-9000,"end":-5000,"name":"옛 동녘국","form":1 | (2 << 5) | (1 << 10) | (3 << 13)},
            {"uid":"extra-pack/p-b","track":0,"row":0,"start":-4000,"end":-2000,"name":"뒤 동녘국","form":19},
            {"uid":"p-c","track":0,"row":0,"start":-6000,"end":-3000,"name":"바탕 문화","look":9}
        ],
        "cells": [
            {"period":"p-a","kind":1,"start":-9000,"end":-7000,"name":"첫 왕"},
            {"period":"extra-pack/p-b","kind":1,"start":-4000,"end":-3000,"name":"첫 왕"}
        ],
        "events": [{"uid":"e1","track":0,"row":0,"start":-8000,"end":-8000,"importance":2,"title":"동녘의 첫 기록","body":""}]
    });
    if lines {
        plan["sphereLines"] = json!([
            // 사람 띠 — 자료집은 uid의 앞머리(extra-pack → 저장소 2). data는 글 그대로.
            {"kind":1,"sphere":"east","start":-9000,"end":-3000,"name":"두 왕관의 왕","uid":"extra-pack/king","color":0,
             "data":"[{\"uid\":\"p-a\",\"cell\":0},{\"uid\":\"extra-pack/p-b\",\"cell\":0}]"},
            // 문화권 시대 — `pack` 순번이 앞머리보다 먼저(1 → 저장소 2) · data가 빠짐 → 빈 글자
            {"kind":2,"sphere":"east","start":-8000,"end":-6000,"name":"동녘 옛 시대","uid":"base-pack/ep-east","color":0xc8b193,"pack":1},
            // 문화권 주기 줄 — start · end = 0(자료 범위 밖) · data가 글이 아니면 JSON 글로
            {"kind":3,"sphere":"east","start":0,"end":0,"name":"동녘 간지","uid":"","color":0,"data":{"era":"동녘","from":1,"step":1,"label":"동녘 간지"},"pack":0},
            // 문화권 주기 줄 — data null → 빈 글자 · 자료집은 첫 것(저장소 1)
            {"kind":3,"sphere":"west","start":0,"end":0,"name":"서녘 주기","data":null}
        ]);
    }
    plan
}

/// 배치를 자료집 둘로 짓는다(`base-pack` · `extra-pack`).
fn imported_two(name: &str, plan: &Value) -> Result<(PathBuf, PathBuf, Value), String> {
    let dir = scratch(name);
    let pack = dir.join("기본.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"base-pack","name":"기본 기록집"}))).unwrap();
    let extra = dir.join("얹은.htpack");
    std::fs::write(&extra, htpack(&json!({"format":"history-timeline-dlc","id":"extra-pack","name":"얹은 기록집"}))).unwrap();
    let plan_path = dir.join("layout.json");
    std::fs::write(&plan_path, serde_json::to_vec(plan).unwrap()).unwrap();
    let target = dir.join("out").join("archive.db");
    match import_layout(&pack, &plan_path, &target, &[&extra]) {
        Ok(counts) => Ok((dir, target, counts)),
        Err(e) => {
            assert!(!target.exists(), "실패한 가져오기는 저장소를 남기지 않는다");
            std::fs::remove_dir_all(dir).unwrap();
            Err(e.to_string())
        }
    }
}

#[test]
fn 스키마_4_띠의_form과_문화권_단위_줄을_배치_그대로_적는다() {
    let (dir, target, counts) = imported_two("schema4-lines", &ancient(true)).unwrap();
    assert_eq!(counts["sphere_lines"], 4, "문화권 단위 줄이 있으면 답의 수 세기에 싣는다");
    let s = Store::open(&target).unwrap();
    assert_eq!(meta_text(&s, "schema").as_deref(), Some("4"));
    // 줄은 배치 차례가 곧 id 차례 · 자료집 순번은 저장소 번호로(`pack` → uid 앞머리 → 기본팩) · data는 글 그대로 / JSON 글 / 빈 글자.
    // `sphere_lines` 한 줄 — id · pack · sphere · kind · start · end · name · uid · color · data.
    type Line = (i64, i64, String, i64, i64, i64, String, String, i64, String);
    let rows: Vec<Line> = {
        let mut st = s.db.prepare("SELECT id,pack,sphere,kind,start,end,name,uid,color,data FROM sphere_lines ORDER BY id").unwrap();
        let v = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?)))
            .unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(rows, vec![
        (1, 2, "east".to_owned(), 1, -9000, -3000, "두 왕관의 왕".to_owned(), "extra-pack/king".to_owned(), 0,
            r#"[{"uid":"p-a","cell":0},{"uid":"extra-pack/p-b","cell":0}]"#.to_owned()),
        (2, 2, "east".to_owned(), 2, -8000, -6000, "동녘 옛 시대".to_owned(), "base-pack/ep-east".to_owned(), 0xc8b193, String::new()),
        // 글이 아닌 data는 serde_json의 JSON 글(열쇠 차례는 serde_json을 따름 — 내보내기는 늘 글로 싣는다)
        (3, 1, "east".to_owned(), 3, 0, 0, "동녘 간지".to_owned(), String::new(), 0, json!({"era":"동녘","from":1,"step":1,"label":"동녘 간지"}).to_string()),
        (4, 1, "west".to_owned(), 3, 0, 0, "서녘 주기".to_owned(), String::new(), 0, String::new()),
    ]);
    // 띠의 form은 배치 값 그대로 · 열쇠가 없는 띠는 0(모름).
    let forms: Vec<(String, i64)> = { let mut st = s.db.prepare("SELECT uid,form FROM periods ORDER BY id").unwrap();
        let v = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(|r| r.unwrap()).collect(); v };
    assert_eq!(forms, vec![("p-a".to_owned(), 1 | (2 << 5) | (1 << 10) | (3 << 13)), ("extra-pack/p-b".to_owned(), 19), ("p-c".to_owned(), 0)]);
    let with_lines = (meta_text(&s, "min"), meta_text(&s, "max"));
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();

    // 줄이 없는 같은 배치: 시간 범위가 같다(kind 3의 0분으로 넓히지 않음) · 답의 수 세기에 sphere_lines 열쇠가 없다(옛 답 그대로) · 표는 비었다.
    let (dir, target, counts) = imported_two("schema4-bare", &ancient(false)).unwrap();
    assert!(counts.get("sphere_lines").is_none(), "줄이 없는 배치의 답은 예전 그대로: {counts}");
    let s = Store::open(&target).unwrap();
    assert_eq!((meta_text(&s, "min"), meta_text(&s, "max")), with_lines, "문화권 단위 줄은 시간 범위를 넓히지 않는다");
    assert_eq!(with_lines, (Some("-9000".to_owned()), Some("-2000".to_owned())));
    let n: i64 = s.db.query_row("SELECT count(*) FROM sphere_lines", [], |r| r.get(0)).unwrap();
    assert_eq!(n, 0);
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn 기간이_뒤집힌_문화권_단위_줄은_그_줄을_말하며_거절한다() {
    let mut plan = ancient(true);
    plan["sphereLines"][1]["end"] = json!(-8500);
    let err = imported_two("schema4-reversed", &plan).unwrap_err();
    assert!(err.contains("문화권 단위 줄 1번째") && err.contains("동녘 옛 시대") && err.contains("뒤집혔습니다"), "{err}");
}

//! 문서 대문의 조회 `doc_list` 검사 — 본문 있는 문서만 · 하위 문서는 바탕의 수로 · 갈래 · 켠 자료집 · 앞부분 글.
use archive_engine::builder::{Builder, EventIn, RowExtra, RowGeo, TrackIn};
use archive_engine::Store;
use serde_json::{json, Value};
use std::path::PathBuf;

const GEO: RowGeo = RowGeo { height: 126, band_top: 19, band_h: 107, dyn_top: 12, lead_top: 23, cab_top: 46, text_top: 66, text_lines: 2, rail_top: 108, organ_top: -1 };

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("archive-doclist-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    path
}

fn build(path: &PathBuf) -> (i64, i64) {
    let mut b = Builder::create(path).unwrap();
    let p1 = b.pack("검사용 하나", None).unwrap();
    let p2 = b.pack("검사용 둘", None).unwrap();
    let t1 = b.track_full(&TrackIn { pack: p1, name: "첫 트랙", color: 0xc8_b193, dynasty: 0, leader: 1, cabinet: 0, organ: 0, rail_levels: 2, key: "mw-first" }).unwrap();
    let r0 = b.row_full(t1, &GEO, &RowExtra::default()).unwrap();
    b.event(&EventIn { pack: p1, lane: r0, start: Some(0), end: Some(0), lo: None, hi: None, importance: 2, title: "나루의 맹세", body: "검사 본문",
        source: None, raw: None, look: 0, label: "1970년", rail: 0, uid: "ev-oath", band: 0, variant: 0 }).unwrap();
    b.entity("b-hanki", p1, "period", r#"{"uid":"b-hanki","name":"한기 나라"}"#).unwrap();
    // 항목 문서(하위 문서 둘) · 그 하위 문서 · 본문 없는 중간 단계 · 사건 문서 · 가문 문서 · 꺼질 자료집의 트랙 문서.
    b.entity("doc:b-hanki", p1, "doc", r#"{"key":"b-hanki","title":"한기 나라","meta":"나라 · 기원전 500년","base":"b-hanki","uid":"b-hanki","span":[-100,-50],"pack":"검사용 하나","body":"== 개요 ==\n'''한기 나라'''는 들판의 나라다.","subs":[{"key":"b-hanki//역사","label":"역사"},{"key":"b-hanki//풍속","label":"풍속"}]}"#).unwrap();
    b.entity("doc:b-hanki//역사", p1, "doc", r#"{"key":"b-hanki//역사","title":"한기 나라","base":"b-hanki","sub":"역사","path":["역사"],"body":"== 전기 ==\n이야기"}"#).unwrap();
    b.entity("doc:b-hanki//풍속", p1, "doc", r#"{"key":"b-hanki//풍속","title":"한기 나라","base":"b-hanki","sub":"풍속","path":["풍속"],"empty":1}"#).unwrap();
    b.entity("doc:ev-oath", p1, "doc", r#"{"key":"ev-oath","title":"나루의 맹세","base":"ev-oath","uid":"ev-oath","at":0,"body":"맹세의 글"}"#).unwrap();
    b.entity("doc:house:h-namu", p1, "doc", r#"{"key":"house:h-namu","title":"나무 가문","base":"house:h-namu","body":"가문 이야기"}"#).unwrap();
    b.entity("doc:track:mw-second", p2, "doc", r#"{"key":"track:mw-second","title":"둘째 트랙","base":"track:mw-second","body":"트랙 이야기"}"#).unwrap();
    b.entity("doc:b-blank", p1, "doc", r#"{"key":"b-blank","title":"빈 나라","base":"b-blank","empty":1}"#).unwrap();
    b.finalize(&[("seed", "문서 대문 검사".to_owned())]).unwrap();
    (p1, p2)
}

fn with_store(name: &str, body: impl FnOnce(&Store, i64, i64)) {
    let path = scratch(name);
    let (p1, p2) = build(&path);
    let store = Store::open(&path).unwrap();
    body(&store, p1, p2);
    drop(store);
    let _ = std::fs::remove_file(&path);
}

fn keys(answer: &Value) -> Vec<String> {
    answer["items"].as_array().unwrap().iter().map(|i| i["key"].as_str().unwrap().to_owned()).collect()
}

#[test]
fn 본문_있는_문서만_하위는_수로() {
    with_store("all", |store, _, _| {
        let answer = store.call(&json!({"op":"doc_list"})).unwrap();
        assert_eq!(keys(&answer), ["b-hanki", "ev-oath", "house:h-namu", "track:mw-second"]);
        assert_eq!(answer["count"], 4);
        let first = &answer["items"][0];
        assert_eq!(first["title"], "한기 나라");
        assert_eq!(first["group"], "period");
        assert_eq!(first["subs"], 2);
        assert_eq!(first["meta"], "나라 · 기원전 500년");
        assert_eq!(first["span"], json!([-100, -50]));
        assert_eq!(first["pack"], "검사용 하나");
        assert!(first["head"].as_str().unwrap().starts_with("== 개요 =="));
        assert_eq!(answer["items"][1]["group"], "event");
        assert_eq!(answer["items"][1]["at"], 0);
        assert!(answer["items"][1].get("subs").is_none());
        assert_eq!(answer["items"][2]["group"], "house");
        assert_eq!(answer["items"][3]["group"], "track");
    });
}

#[test]
fn 켠_자료집만() {
    with_store("packs", |store, p1, p2| {
        assert_eq!(keys(&store.call(&json!({"op":"doc_list","packs":[p1]})).unwrap()), ["b-hanki", "ev-oath", "house:h-namu"]);
        assert_eq!(keys(&store.call(&json!({"op":"doc_list","packs":[p2]})).unwrap()), ["track:mw-second"]);
        assert_eq!(store.call(&json!({"op":"doc_list","packs":[]})).unwrap()["count"], 0);
    });
}

#[test]
fn 앞부분은_320자까지() {
    let path = scratch("head");
    let mut b = Builder::create(&path).unwrap();
    let p = b.pack("검사용", None).unwrap();
    let long = "가".repeat(500);
    b.entity("doc:b-long", p, "doc", &json!({"key":"b-long","title":"긴 글","base":"b-long","body":long}).to_string()).unwrap();
    b.finalize(&[("seed", "문서 대문 검사".to_owned())]).unwrap();
    let store = Store::open(&path).unwrap();
    let answer = store.call(&json!({"op":"doc_list"})).unwrap();
    assert_eq!(answer["items"][0]["head"].as_str().unwrap().chars().count(), 320);
    assert_eq!(answer["items"][0]["group"], "item");
    drop(store);
    let _ = std::fs::remove_file(&path);
}

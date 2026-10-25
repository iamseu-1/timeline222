//! 형식 3을 새 앱(아카이브) 안의 연표까지 — 엔진 쪽(A1-b) 검사. 설계 `docs/설계-10건/A-아카이브-이음.md` 4-2의 A1-b.
//!
//! 내보내기가 아직 `x_find`를 싣지 않으므로(A1-a 몫) 손으로 쓴 배치 JSON으로 저장소를 짓는다(`tests/import.rs`의 `htpack()` 꼴).
//! 확인하는 것:
//! - 로마자 · 옛 이름 · 도읍 지명 원어(찾을 글 `x_find`)로 정권 · 칸 · 가문이 찾히고, 결과는 본 이름이다.
//! - `kinds:["group"]` · `["institution"]`이 곁글 · 줄 · 기간 · 색과 함께 오고, 그 줄의 트랙을 끄면 숨는다.
//! - 사건의 다른 이름(본문 색인의 덧줄)으로 찾히고, 한 사건은 한 번만 나온다(공동 사건의 둘째 자리는 밑동 기록으로).
//! - `kinds`가 없는 옛 모양 `search`는 덧줄을 보지 않는다. 본 문서는 여전히 빠진다.
//! - `themes` · `view` · `map` · `font` · `place` · `surname`은 이름 표에 들지 않는다.
//! - 같은 도시를 쓴 정권들에서 도읍 칸의 주인이 맞다(설계 2-2의 결함 4).
//! - 결과 차례가 지금 연표와 같다: 항목 → 칸 → 하위 문서 → 가문 → 단체 → 제도(뒤의 셋은 넣은 차례).
//! - **옛 저장소**(hay 열을 지우고 덧줄을 뺀 사본)는 예전 규칙 그대로 답한다.
//! - (A3 바닥) 칸 종류 8 · 구역 48 · 변형 kind 3 · 4가 가져오기 · 타일 · 거르개 · 변형을 그대로 지나간다.
use archive_engine::legacy::import_layout;
use archive_engine::tile::{build_tile, decode, TileRequest};
use archive_engine::{grams, Store};
use rusqlite::Connection;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::{Path, PathBuf};

/// 한 해 ≈ 분(검사 안에서만 쓰는 어림값 — 기간의 앞뒤만 본다).
const Y: i64 = 525_600;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-format3-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// 규격 2 전용 팩을 검사 안에서 만든다(머리 20바이트 + 지문 32바이트 + zlib 본문 — `tests/import.rs`와 같은 꼴).
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
    json!({"height":126,"bandTop":19,"bandH":107,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1})
}

/// 항목 기록 한 줄(본문은 JSON 글).
fn entity(uid: &str, kind: &str, body: Value) -> Value {
    json!({"uid":uid,"kind":kind,"pack":0,"json":body.to_string()})
}

/// 지도자 칸의 `style` — 칸 참조 번호(순번 + 1)를 15~26비트에 싣는다(계약 6-2).
fn leader_style(seq: i64) -> i64 {
    (seq + 1) << 15
}

/// 형식 3의 기록을 품은 작은 배치. 트랙 둘(윗물 `tw` · 아랫물 `tb`), 정권 셋:
/// - 갑 왕국(윗물)과 병 왕국(윗물 · 갑 다음)은 도읍 칸이 둘 다 '푸른 벼랑'이고(같은 도시를 같은 이름으로),
/// - 을 공국(아랫물)의 도읍은 '을 나루'지만 그 도시(`city`)가 '푸른 벼랑'이다 — 예전 엔진은 갑의 도읍 칸을 다른 정권에 붙였다.
///
/// `track_keys`가 거짓이면 트랙의 글자 id를 싣지 않는다(옛 내보내기) — 그때는 기간 겹침으로 가린다.
fn layout(track_keys: bool) -> Value {
    let key = |k: &str| if track_keys { k.to_owned() } else { String::new() };
    json!({
        "name": "형식 3 검사",
        "packs": [{"id":"f3","name":"형식 3 검사"}],
        "categories": [{"key":"lore","name":"이야기","color":0x9a6f8a}],
        "tracks": [
            {"name":"윗물 트랙","key":key("tw"),"color":0xc8b193,"dynasty":1,"leader":1,"cabinet":1,"organ":0,"rows":[row(), row()]},
            {"name":"아랫물 트랙","key":key("tb"),"color":0x9dbea8,"dynasty":1,"leader":1,"cabinet":1,"organ":0,"rows":[row()]}
        ],
        "axis": [
            {"kind":2,"track":0,"lane":0,"start":-1000*Y,"end":-900*Y,"name":"첫빛","color":0xc8b193,"seq":0},
            {"kind":3,"track":0,"lane":0,"start":-1000*Y,"end":-800*Y,"name":"푸른 벼랑","color":0xc8b193,"strip":1,"seq":0},
            {"kind":3,"track":1,"lane":0,"start":-900*Y,"end":-600*Y,"name":"을 나루","color":0x9dbea8,"strip":2,"seq":0},
            {"kind":3,"track":0,"lane":0,"start":-700*Y,"end":-500*Y,"name":"푸른 벼랑","color":0xd1a9b9,"strip":3,"seq":0},
            {"kind":4,"track":0,"lane":1,"start":-650*Y,"end":-450*Y,"name":"두 보조도읍","color":0xd1a9b9,"strip":4,"seq":1}
        ],
        "periods": [
            {"uid":"f3/p-gap","track":0,"row":0,"start":-1000*Y,"end":-700*Y-1,"color":0xa0bcc5,"name":"갑 왕국"},
            {"uid":"f3/p-byeong","track":0,"row":0,"start":-700*Y,"end":-400*Y-1,"color":0xd1a9b9,"name":"병 왕국"},
            {"uid":"f3/p-eul","track":1,"row":0,"start":-900*Y,"end":-500*Y,"color":0xbcd8c1,"name":"을 공국"}
        ],
        "cells": [
            {"period":"f3/p-gap","kind":1,"start":-1000*Y,"end":-950*Y,"name":"갑 첫왕","style":leader_style(0)},
            {"period":"f3/p-gap","kind":1,"start":-950*Y+1,"end":-700*Y-1,"name":"갑 둘째왕","style":leader_style(1)}
        ],
        "events": [
            {"uid":"f3/e-sea","track":0,"row":0,"start":-800*Y,"end":-800*Y,"importance":3,"title":"바다 건너기","body":"나루에서 배를 띄웠다","band":"f3/p-gap"},
            {"uid":"f3/e-sea#1","track":1,"row":0,"start":-800*Y,"end":-800*Y,"importance":3,"title":"바다 건너기","body":"나루에서 배를 띄웠다","band":"f3/p-eul"},
            {"uid":"f3/e-quiet","track":0,"row":1,"start":-750*Y,"end":-750*Y,"importance":1,"title":"조용한 해","body":"아무 일도 없었다"}
        ],
        "entities": [
            entity("f3/p-gap", "period", json!({"uid":"f3/p-gap","name":"갑 왕국","description":"바다를 낀 나라","track":"tw",
                "capitals":[{"name":"푸른 벼랑","city":"푸른 벼랑"}],"eras":[{"name":"첫빛"}],
                "x_find":{"hay":"gap-wangguk 옛갑나라 윗물 트랙","cells":{"leader:0":"gap the first 바다왕","leader:1":"gap second","capital:0":"cheongbyeok 靑壁"}}})),
            entity("f3/p-eul", "period", json!({"uid":"f3/p-eul","name":"을 공국","track":"tb",
                "capitals":[{"name":"을 나루","city":"푸른 벼랑"}],"x_find":{"hay":"eul-gongguk 아랫물 트랙"}})),
            entity("f3/p-byeong", "period", json!({"uid":"f3/p-byeong","name":"병 왕국","track":"tw",
                "capitals":[{"name":"푸른 벼랑","city":"푸른 벼랑"},{"name":"뿌리종","city":"뿌리종","group":"두 보조도읍","role":"secondary"}],
                "x_find":{"hay":"byeong 윗물 트랙","cells":{"capital:0":"cheongbyeok 靑壁 둘째"}}})),
            entity("f3/e-sea", "event", json!({"uid":"f3/e-sea","title":"바다 건너기","x_find":{"hay":"crossing the sea 옛물길 윗물 트랙"}})),
            entity("f3/f-arin", "figure", json!({"uid":"f3/f-arin","name":"Ärin 벼리","x_find":{"hay":"arin"}})),
            entity("f3/ep-1", "epoch", json!({"uid":"f3/ep-1","name":"첫 시대","description":"바다 이야기"})),
            // 가문은 넣은 차례가 uid 차례(a-later가 먼저) · 이름 차례(가람이 먼저)와 다르다.
            entity("house:h-sol", "house", json!({"name":"솔바위 가문","x_find":{"hay":"solbawi 松巖 바다"}})),
            entity("house:a-later", "house", json!({"name":"가람 가문"})),
            // 단체 둘 — 넣은 차례(동쪽 동맹이 먼저)가 uid 차례 · 시작 차례와 다르다.
            entity("f3/gr-east", "group", json!({"uid":"f3/gr-east","name":"동쪽 동맹","description":"바다 건너 맺은 동맹",
                "x_find":{"hay":"east league 단체","sub":"단체 · 동맹","span":[-850*Y,-600*Y],"color":"#a0bcc5","row":"f3/p-eul"}})),
            entity("f3/gr-alpha", "group", json!({"uid":"f3/gr-alpha","name":"알파 회",
                "x_find":{"hay":"alpha circle","sub":"단체 · 모임","span":[-990*Y,-900*Y],"color":"#bcd8c1","row":"f3/p-gap"}})),
            entity("f3/in-sea", "institution", json!({"uid":"f3/in-sea","name":"바다 법",
                "x_find":{"hay":"sea law 제도","sub":"제도 · 법","span":[-950*Y,-700*Y],"color":"#9dbea8","row":"f3/p-gap"}})),
            // 문서: 본 문서(곁글 없음)는 빠지고 하위 문서만 찾는다.
            entity("doc:f3/p-gap", "doc", json!({"key":"f3/p-gap","title":"갑 왕국","sub":""})),
            entity("doc:f3/p-gap//바다", "doc", json!({"key":"f3/p-gap//바다","title":"갑 왕국/바다 역사","sub":"바다 역사"})),
            // 이름이 있어도 이름 표에 넣지 않는 기록(허용 목록 밖).
            entity("place:pl-blue", "place", json!({"name":"푸른 벼랑","names":[{"text":"cheongbyeok"}]})),
            entity("surname:sn-sol", "surname", json!({"name":"솔"})),
            entity("view:v-sea", "view", json!({"name":"바다 판"})),
            entity("map:m-sea", "map", json!({"name":"바다 지도","image":{"$bytes":12}})),
            entity("font:f-sea", "font", json!({"name":"바다 글꼴","family":"바다 글꼴"})),
            entity("themes", "themes", json!({"name":"바다 주제","list":[{"id":"t1","name":"바다","color":"#a0bcc5","order":0}]}))
        ]
    })
}

/// 배치를 가져와 저장소를 짓는다.
fn build(name: &str, plan: &Value) -> (PathBuf, PathBuf) {
    let dir = scratch(name);
    let pack = dir.join("검사.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"f3","name":"형식 3 검사"}))).unwrap();
    let file = dir.join("layout.json");
    std::fs::write(&file, serde_json::to_vec(plan).unwrap()).unwrap();
    let target = dir.join("archive.db");
    import_layout(&pack, &file, &target, &[]).unwrap();
    (dir, target)
}

fn ask(s: &Store, q: Value) -> Value {
    s.call(&q).unwrap_or_else(|e| panic!("{q}: {e}"))
}

fn names(v: &Value) -> Vec<String> {
    v["items"].as_array().unwrap().iter().map(|x| x["name"].as_str().unwrap().to_owned()).collect()
}

fn kinds_of(v: &Value) -> Vec<String> {
    v["items"].as_array().unwrap().iter().map(|x| x["kind"].as_str().unwrap().to_owned()).collect()
}

const ALL: [&str; 14] = ["event", "treaty", "period", "organ", "culture", "dynasty", "figure", "epoch", "scope", "house", "cell", "doc", "group", "institution"];

/// 이 일 전의 저장소를 흉내 낸 사본: 이름 표의 `hay` 열 · 사건의 찾을 글 표(`event_hay`)를 지우고 본문 색인의 덧줄을 뺀다.
fn old_copy(src: &Path, dir: &Path) -> PathBuf {
    let path = dir.join("old.db");
    std::fs::copy(src, &path).unwrap();
    let db = Connection::open(&path).unwrap();
    // 덧줄(rowid = −사건 번호)을 지운다 — 내용 없는 본문 색인은 넣을 때의 낱자를 그대로 주어야 지워진다.
    let extra: Vec<(i64, String)> = {
        let mut stmt = db.prepare(
            "SELECT e.id,json_extract(en.json,'$.x_find.hay') FROM events e JOIN entities en
               ON en.uid=(CASE WHEN instr(e.uid,'#')>1 THEN substr(e.uid,1,instr(e.uid,'#')-1) ELSE e.uid END)
              WHERE json_extract(en.json,'$.x_find.hay') IS NOT NULL").unwrap();
        let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(|r| r.unwrap()).collect();
        rows
    };
    assert!(!extra.is_empty(), "검사 배치에는 덧줄이 있어야 한다");
    for (id, hay) in extra {
        db.execute("INSERT INTO search(search,rowid,terms) VALUES('delete',?1,?2)", rusqlite::params![-id, grams(&hay.to_lowercase()).join(" ")]).unwrap();
    }
    db.execute_batch("ALTER TABLE names DROP COLUMN hay; DROP TABLE event_hay;").unwrap();
    path
}

#[test]
fn 원어_옛_이름_로마자로_정권_칸_가문이_찾히고_결과는_본_이름이다() {
    let (_dir, path) = build("hay", &layout(true));
    let s = Store::open(&path).unwrap();
    // 정권: 로마자 · 옛 이름(찾을 글) · 설명.
    for text in ["gap-wangguk", "옛갑나라", "GAP-WANGGUK", "낀 나라"] {
        let got = ask(&s, json!({"op":"search","text":text,"kinds":["period"]}));
        assert_eq!(names(&got), vec!["갑 왕국"], "{text}");
        assert_eq!(got["items"][0]["uid"], "f3/p-gap");
    }
    // 칸: 지도자 칸의 찾을 글. 낱말 셋이 모두 한 칸의 이름 · 곁글 · 찾을 글 어딘가에 있어야 한다.
    let leader = ask(&s, json!({"op":"search","text":"gap the first","kinds":["cell"]}));
    assert_eq!(names(&leader), vec!["갑 첫왕"]);
    assert_eq!(leader["items"][0]["cell"], "leader:0");
    // 도읍 칸: 지명 원어(내보내기가 도읍 칸의 찾을 글에 지명의 원어를 담는다) — 같은 이름의 두 도읍 칸이 제 주인으로.
    let capital = ask(&s, json!({"op":"search","text":"靑壁","kinds":["cell"]}));
    assert_eq!(names(&capital), vec!["푸른 벼랑", "푸른 벼랑"]);
    let owners: Vec<&str> = capital["items"].as_array().unwrap().iter().map(|v| v["uid"].as_str().unwrap()).collect();
    assert_eq!(owners, vec!["f3/p-gap", "f3/p-byeong"]);
    assert_eq!(capital["items"][0]["cell"], "capital:0");
    // 둘째 도읍 칸에만 있는 낱말.
    assert_eq!(ask(&s, json!({"op":"search","text":"cheongbyeok 둘째","kinds":["cell"]}))["items"][0]["uid"], "f3/p-byeong");
    // 가문: 로마자 · 한자. 결과는 본 이름이다.
    for text in ["solbawi", "松巖"] {
        let got = ask(&s, json!({"op":"search","text":text,"kinds":["house"]}));
        assert_eq!(names(&got), vec!["솔바위 가문"], "{text}");
        assert_eq!(got["items"][0]["uid"], "house:h-sol");
    }
    // SQLite의 lower()가 바꾸지 못하는 대문자(Ä)가 든 이름도 소문자로 찾힌다(지금 연표의 toLowerCase처럼).
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"ärin","kinds":["figure"]}))), vec!["Ärin 벼리"]);
    // 시대 구분은 설명으로 찾지 않는다(지금 연표는 이름 · 메모 · 트랙 이름만 본다).
    assert_eq!(ask(&s, json!({"op":"search","text":"이야기","kinds":["epoch"]}))["items"], json!([]));
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"첫 시대","kinds":["epoch"]}))), vec!["첫 시대"]);
}

#[test]
fn 단체와_제도는_곁글_줄_기간_색과_함께_오고_트랙을_끄면_숨는다() {
    let (_dir, path) = build("group", &layout(true));
    let s = Store::open(&path).unwrap();
    let got = ask(&s, json!({"op":"search","text":"동맹","kinds":["group"]}));
    assert_eq!(got["items"].as_array().unwrap().len(), 1);
    let east = &got["items"][0];
    assert_eq!(east["kind"], "group");
    assert_eq!(east["uid"], "f3/gr-east");
    assert_eq!(east["name"], "동쪽 동맹");
    assert_eq!(east["sub"], "단체 · 동맹");
    assert_eq!(east["start"], json!(-850 * Y));
    assert_eq!(east["end"], json!(-600 * Y));
    assert_eq!(east["color"], json!(0xa0bcc5));
    assert_eq!(east["cell"], Value::Null);
    assert_eq!(east["id"], Value::Null);
    // 줄은 x_find.row(을 공국)의 띠 줄을 빌린다 — 아랫물 트랙의 첫 줄(전체 줄 번호 2).
    assert_eq!(east["row"], json!(2));
    assert_eq!(east["track"], "아랫물 트랙");
    // 때 글은 기간에서(검사의 해 어림값은 1970년에서 센다).
    assert_eq!(east["when"], "1120년–1370년");
    // 넣은 차례(동쪽 동맹 → 알파 회)로 답한다 — uid 차례 · 시작 차례(알파 회가 먼저)가 아니다.
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"단체","kinds":["group"]}))), vec!["동쪽 동맹", "알파 회"]);
    // 그 줄의 트랙을 끄면 숨는다.
    let lower: i64 = s.db.query_row("SELECT id FROM tracks WHERE name='아랫물 트랙'", [], |r| r.get(0)).unwrap();
    let upper: i64 = s.db.query_row("SELECT id FROM tracks WHERE name='윗물 트랙'", [], |r| r.get(0)).unwrap();
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"단체","kinds":["group"],"filter":{"tracks_off":[lower]}}))), vec!["알파 회"]);
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"단체","kinds":["group"],"filter":{"tracks_off":[upper]}}))), vec!["동쪽 동맹"]);
    // 제도.
    let law = ask(&s, json!({"op":"search","text":"sea law","kinds":["institution"]}));
    assert_eq!(names(&law), vec!["바다 법"]);
    assert_eq!(law["items"][0]["sub"], "제도 · 법");
    assert_eq!(law["items"][0]["row"], json!(0));
    assert_eq!(law["items"][0]["track"], "윗물 트랙");
    assert_eq!(law["items"][0]["color"], json!(0x9dbea8));
    assert_eq!(ask(&s, json!({"op":"search","text":"바다","kinds":["institution"],"filter":{"tracks_off":[upper]}}))["items"], json!([]));
    // 켠 자료집 밖이면 없다.
    assert_eq!(ask(&s, json!({"op":"search","text":"동맹","kinds":["group"],"packs":[]}))["items"], json!([]));
    // 날짜 검색은 두 갈래를 받아도 빈 결과다(지금 연표도 날짜 · 간지 검색에서는 단체 · 제도 · 가문을 찾지 않는다).
    assert_eq!(ask(&s, json!({"op":"search_year","at":-800*Y,"kinds":["group","institution","house"]}))["items"], json!([]));
    // 모르는 갈래는 여전히 실패한다.
    assert!(s.call(&json!({"op":"search","text":"동맹","kinds":["band"]})).unwrap_err().to_string().contains("모르는 갈래"));
}

#[test]
fn 사건은_다른_이름으로도_찾히고_한_번만_나온다() {
    let (_dir, path) = build("event", &layout(true));
    let s = Store::open(&path).unwrap();
    // 다른 이름만으로 — 두 자리(둘째 자리 `#1`은 밑동 기록의 찾을 글로).
    let alias = ask(&s, json!({"op":"search","text":"crossing","kinds":["event"]}));
    let uids: Vec<&str> = alias["items"].as_array().unwrap().iter().map(|v| v["uid"].as_str().unwrap()).collect();
    assert_eq!(uids, vec!["f3/e-sea", "f3/e-sea#1"]);
    assert_eq!(alias["total"], json!(2));
    // 제목의 낱말과 다른 이름의 낱말이 갈라 들어도 찾힌다(웹은 한 찾을 글에서 맞춘다).
    assert_eq!(ask(&s, json!({"op":"search","text":"건너기 옛물길","kinds":["event"]}))["total"], json!(2));
    // 제목 · 설명으로 찾을 때 덧줄 때문에 겹쳐 나오지 않는다(찾을 글에도 '바다'가 든 사건).
    let sea = ask(&s, json!({"op":"search","text":"sea 바다","kinds":["event"]}));
    let ids: Vec<i64> = sea["items"].as_array().unwrap().iter().map(|v| v["id"].as_i64().unwrap()).collect();
    assert_eq!(ids.len(), 2);
    assert!(ids.iter().all(|id| *id > 0), "사건 번호는 양수 그대로: {ids:?}");
    // 없는 조합은 찾지 않는다(낱자는 다 있어도 글이 다르면 — 확인 조건).
    assert_eq!(ask(&s, json!({"op":"search","text":"crossingsea","kinds":["event"]}))["items"], json!([]));
    // 다른 이름이 없는 사건은 예전처럼 제목 · 설명으로.
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"아무 일","kinds":["event"]}))), vec!["조용한 해"]);
    // kinds가 없는 옛 모양은 덧줄을 보지 않는다 — 사건 번호(양수)로만 잇는다.
    assert_eq!(ask(&s, json!({"op":"search","text":"crossing"}))["items"], json!([]));
    let old = ask(&s, json!({"op":"search","text":"바다"}));
    let old_ids: Vec<i64> = old["items"].as_array().unwrap().iter().map(|v| v["id"].as_i64().unwrap()).collect();
    assert_eq!(old_ids, vec![1, 2]);
    assert!(old["items"][0].get("kind").is_none(), "옛 모양에는 kind가 없다");
    // 덧줄은 사건 기록의 찾을 글이 있는 사건 수만큼(공동 사건의 두 자리 → 둘). 같은 글이 event_hay에도 있다.
    let extra: i64 = s.db.query_row("SELECT count(*) FROM search WHERE rowid<0", [], |r| r.get(0)).unwrap();
    assert_eq!(extra, 2);
    let kept: Vec<(i64, String)> = {
        let mut stmt = s.db.prepare("SELECT id,hay FROM event_hay ORDER BY id").unwrap();
        let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(|r| r.unwrap()).collect();
        rows
    };
    assert_eq!(kept, vec![(1, "crossing the sea 옛물길 윗물 트랙".to_owned()), (2, "crossing the sea 옛물길 윗물 트랙".to_owned())]);
}

#[test]
fn 사건의_찾을_글_표가_없으면_항목_기록에서_꺼내_같은_답을_낸다() {
    let (dir, path) = build("event-json", &layout(true));
    let copy = dir.join("no-event-hay.db");
    std::fs::copy(&path, &copy).unwrap();
    Connection::open(&copy).unwrap().execute_batch("DROP TABLE event_hay;").unwrap();
    let (fresh, slow) = (Store::open(&path).unwrap(), Store::open(&copy).unwrap());
    for text in ["crossing", "건너기 옛물길", "sea 바다", "아무 일", "crossingsea"] {
        let q = json!({"op":"search","text":text,"kinds":ALL});
        assert_eq!(ask(&slow, q.clone()), ask(&fresh, q), "{text}");
    }
}

#[test]
fn 통틀어_몇_건인지는_쪽을_넘어_물어도_맞다() {
    let (_dir, path) = build("total", &layout(true));
    let s = Store::open(&path).unwrap();
    let whole = ask(&s, json!({"op":"search","text":"바다","kinds":ALL}));
    assert_eq!(whole["total"], json!(8));
    assert_eq!(ask(&s, json!({"op":"search","text":"바다","kinds":ALL,"limit":3,"after":6}))["total"], json!(8));
    let beyond = ask(&s, json!({"op":"search","text":"바다","kinds":ALL,"limit":3,"after":20}));
    assert_eq!(beyond["items"], json!([]));
    assert_eq!(beyond["total"], json!(8), "끝을 넘어 물으면 따로 센다");
    assert_eq!(ask(&s, json!({"op":"search","text":"없는말","kinds":ALL}))["total"], json!(0));
}

#[test]
fn 결과_차례는_항목_칸_하위_문서_가문_단체_제도다() {
    let (_dir, path) = build("order", &layout(true));
    let s = Store::open(&path).unwrap();
    let got = ask(&s, json!({"op":"search","text":"바다","kinds":ALL}));
    assert_eq!(names(&got), vec!["갑 왕국", "바다 건너기", "바다 건너기", "갑 첫왕", "갑 왕국/바다 역사", "솔바위 가문", "동쪽 동맹", "바다 법"]);
    assert_eq!(kinds_of(&got), vec!["period", "event", "event", "cell", "doc", "house", "group", "institution"]);
    // 가문은 넣은 차례(솔바위 → 가람) — 이름 차례 · uid 차례가 아니다.
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"가문","kinds":["house"]}))), vec!["솔바위 가문", "가람 가문"]);
    // 나눠 받아도 한 번에 받은 것과 같다.
    let mut joined = Vec::new();
    let mut after = 0;
    loop {
        let page = ask(&s, json!({"op":"search","text":"바다","kinds":ALL,"limit":3,"after":after}));
        joined.extend(names(&page));
        if page["has_more"] != json!(true) {
            break;
        }
        after = page["next"].as_i64().unwrap();
    }
    assert_eq!(joined, names(&got));
    // 본 문서는 여전히 빠지고 하위 문서만 찾는다.
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"갑 왕국","kinds":["doc"]}))), vec!["갑 왕국/바다 역사"]);
}

#[test]
fn 허용_목록_밖의_기록은_이름_표에_들지_않는다() {
    let (_dir, path) = build("allow", &layout(true));
    let s = Store::open(&path).unwrap();
    let mut stmt = s.db.prepare("SELECT DISTINCT kind FROM names ORDER BY kind").unwrap();
    let kinds: Vec<String> = stmt.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
    assert_eq!(kinds, vec!["cell", "doc", "epoch", "figure", "group", "house", "institution", "period"]);
    for uid in ["place:pl-blue", "surname:sn-sol", "view:v-sea", "map:m-sea", "font:f-sea", "themes"] {
        let n: i64 = s.db.query_row("SELECT count(*) FROM names WHERE uid=?1", [uid], |r| r.get(0)).unwrap();
        assert_eq!(n, 0, "{uid}");
        // 기록 자체는 그대로 열린다.
        assert_eq!(ask(&s, json!({"op":"entity","uid":uid}))["uid"], uid);
    }
    // 지명의 원어(cheongbyeok)는 도읍 칸의 찾을 글로만 찾힌다 — 지명 기록이 결과 줄로 나오지 않는다.
    let all = ask(&s, json!({"op":"search","text":"cheongbyeok","kinds":ALL}));
    assert_eq!(kinds_of(&all), vec!["cell", "cell"]);
}

#[test]
fn 같은_도시를_쓴_정권들에서_도읍_칸의_주인이_맞다() {
    for track_keys in [true, false] {
        let (_dir, path) = build(if track_keys { "capital-key" } else { "capital-nokey" }, &layout(track_keys));
        let s = Store::open(&path).unwrap();
        let owner = |name: &str, start: i64| -> (String, String) {
            s.db.query_row("SELECT uid,cell_ref FROM names WHERE kind='cell' AND name=?1 AND start=?2", rusqlite::params![name, start], |r| Ok((r.get(0)?, r.get(1)?))).unwrap()
        };
        // 갑의 도읍 칸 '푸른 벼랑' — 후보는 갑(name) · 병(name) · 을(city). 트랙(또는 기간)과 맞은 칸으로 갑.
        assert_eq!(owner("푸른 벼랑", -1000 * Y), ("f3/p-gap".to_owned(), "capital:0".to_owned()), "트랙 id {track_keys}");
        // 병의 도읍 칸도 같은 이름 — 기간이 겹치는 병.
        assert_eq!(owner("푸른 벼랑", -700 * Y).0, "f3/p-byeong", "트랙 id {track_keys}");
        assert_eq!(owner("을 나루", -900 * Y).0, "f3/p-eul");
        // 배도 칸은 묶음 이름(group)으로 — 그 묶음의 첫 도읍 순번(capital:1).
        assert_eq!(owner("두 보조도읍", -650 * Y), ("f3/p-byeong".to_owned(), "capital:1".to_owned()));
        assert_eq!(owner("첫빛", -1000 * Y), ("f3/p-gap".to_owned(), "era:0".to_owned()));
    }
}

#[test]
fn 옛_저장소는_예전_규칙_그대로_답한다() {
    let (dir, path) = build("old", &layout(true));
    let old = old_copy(&path, &dir);
    let s = Store::open(&old).unwrap();
    // 찾을 글로만 찾히던 것은 찾히지 않는다(예전처럼 이름 · 곁글 · 제목 · 설명만).
    for (text, kinds) in [("gap-wangguk", json!(["period"])), ("solbawi", json!(["house"])), ("靑壁", json!(["cell"])),
                          ("crossing", json!(["event"])), ("ärin", json!(["figure"])), ("낀 나라", json!(["period"]))] {
        assert_eq!(ask(&s, json!({"op":"search","text":text,"kinds":kinds}))["items"], json!([]), "{text}");
    }
    // 예전 차례: (시작 없음이 뒤) → 시작 → 갈래 → 이름. 가문은 이름 차례.
    let got = ask(&s, json!({"op":"search","text":"바다","kinds":ALL}));
    assert_eq!(names(&got), vec!["바다 법", "바다 건너기", "바다 건너기", "갑 왕국/바다 역사"]);
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"가문","kinds":["house"]}))), vec!["가람 가문", "솔바위 가문"]);
    // 옛 모양 search는 새 저장소와 사본이 같은 답이다.
    let fresh = Store::open(&path).unwrap();
    for text in ["바다", "나루", "조용한"] {
        assert_eq!(ask(&s, json!({"op":"search","text":text})), ask(&fresh, json!({"op":"search","text":text})), "{text}");
    }
    // 이름 · 제목으로만 찾는 물음은 새 저장소와 같은 것을 찾는다.
    for (text, kinds) in [("갑 왕국", json!(["period"])), ("조용한", json!(["event"])), ("갑 첫왕", json!(["cell"])), ("동쪽", json!(["group"]))] {
        assert_eq!(ask(&s, json!({"op":"search","text":text,"kinds":kinds}))["items"],
                   ask(&fresh, json!({"op":"search","text":text,"kinds":kinds}))["items"], "{text}");
    }
}

/// A3의 바닥(설계 6절 바닥 2): 예약한 번호(칸 종류 8 · 구역 48 · 변형 kind 3 · 4)가 가져오기 · 타일 · 거르개 · 변형을
/// 뜻을 모른 채 그대로 지나가는지 본다. Rust는 고치지 않고 검사만 둔다.
#[test]
fn 예약한_번호의_칸_구역_변형은_그대로_지나간다() {
    let mut plan = layout(true);
    plan["variants"] = json!([
        {"key":"view:v-sea","kind":3,"track":0,"uid":"view:v-sea","name":"바다 판","rows":[{"track":0,"row":2,"after":0,"ord":0,"new":1}]},
        {"key":"theme:t1","kind":4,"track":0,"uid":"theme:t1","name":"바다 주제"}
    ]);
    // 판 변형에서만 있는 줄 하나(윗물 트랙의 셋째 줄)와 그 줄의 띠.
    plan["tracks"][0]["rows"].as_array_mut().unwrap().push(json!({"height":126,"bandTop":19,"bandH":107,"lines":2,"variant":"view:v-sea"}));
    plan["periods"].as_array_mut().unwrap().push(json!({"uid":"f3/p-view","track":0,"row":2,"start":-900*Y,"end":-800*Y,"color":0xa0bcc5,"name":"판에만 있는 띠","variant":"view:v-sea"}));
    // 공용 칸 단(칸 종류 8) — 하나는 늘 있고, 하나는 주제 변형에서만. style 27~29비트는 단 갈래(예약).
    plan["cells"].as_array_mut().unwrap().push(json!({"period":"f3/p-gap","kind":8,"start":-990*Y,"end":-900*Y,"name":"공용 칸","style":1<<27}));
    plan["cells"].as_array_mut().unwrap().push(json!({"period":"f3/p-gap","kind":8,"start":-890*Y,"end":-800*Y,"name":"주제 칸","style":2<<27,"variant":"theme:t1"}));
    // 구역 48(띠 위 원어 글 — 예약).
    plan["items"] = json!([{"section":48,"track":0,"row":0,"start":-1000*Y,"end":-700*Y,"ref":"f3/p-gap","name":"Gap","color":0xa0bcc5,"a":1,"text2":"x-gap"}]);
    let (_dir, path) = build("a3", &plan);
    let s = Store::open(&path).unwrap();
    let shape = ask(&s, json!({"op":"layout"}));
    assert_eq!(shape["tracks"][0]["rows"].as_array().unwrap().len(), 3);
    let level = 10usize;
    let x = (-900 * Y).div_euclid(256 * (1i64 << (2 * level)));
    let tile = |variants: Value, filter: Value| {
        let q = json!({"variants":variants,"filter":filter});
        let req = TileRequest { level, x, chunk: 0, packs: vec![1], filter: s.filter_of(&q).unwrap(), variants: s.variants_of(&q).unwrap() };
        decode(&build_tile(&s, &req).unwrap()).unwrap()
    };
    let plain = tile(json!([]), Value::Null);
    let cell8: Vec<_> = plain.cells.iter().filter(|c| c.kind == 8).collect();
    assert_eq!(cell8.len(), 1, "변형을 켜지 않으면 늘 있는 칸 하나만");
    assert_eq!(plain.strings[cell8[0].name as usize], "공용 칸");
    assert_eq!(cell8[0].style, 1 << 27, "style의 예약 비트도 그대로");
    let s48 = plain.section(48);
    assert_eq!(s48.len(), 1);
    assert_eq!(plain.strings[s48[0].text2 as usize], "x-gap");
    assert!(plain.bands.iter().all(|b| plain.strings[b.name as usize] != "판에만 있는 띠"));
    // 주제 변형(kind 4)을 켜면 그 칸이 함께 온다.
    let themed = tile(json!(["theme:t1"]), Value::Null);
    assert_eq!(themed.cells.iter().filter(|c| c.kind == 8).count(), 2);
    // 판 변형(kind 3)을 켜면 그 줄의 띠가 온다.
    let viewed = tile(json!(["view:v-sea"]), Value::Null);
    assert!(viewed.bands.iter().any(|b| viewed.strings[b.name as usize] == "판에만 있는 띠"));
    // 거르개: 윗물 트랙을 끄면 칸 종류 8과 구역 48도 함께 빠진다.
    let upper: i64 = s.db.query_row("SELECT id FROM tracks WHERE name='윗물 트랙'", [], |r| r.get(0)).unwrap();
    let off = tile(json!(["theme:t1"]), json!({"tracks_off":[upper]}));
    assert_eq!(off.cells.iter().filter(|c| c.kind == 8).count(), 0);
    assert!(off.section(48).is_empty());
    // 칸 종류 8은 이름 표에 들지 않는다(상세 창이 여는 칸이 아니다 — 뜻은 A3가 정한다).
    let n: i64 = s.db.query_row("SELECT count(*) FROM names WHERE kind='cell' AND cell=8", [], |r| r.get(0)).unwrap();
    assert_eq!(n, 0);
}

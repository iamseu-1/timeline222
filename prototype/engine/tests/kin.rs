//! 10건 1 · 2(D1 — 승계표 · 세계표 · 가문)의 엔진 확인(D1-B). 설계 `docs/설계-10건/1-2-계승과-가문-확정.md` 8-1 · 8-2 · 9-2 D1-B.
//!
//! 엔진 스키마 · 판(`'3'`)은 그대로다. 내보내기(D1-E)가 항목 기록에 싣는 것을 손으로 쓴 배치 JSON(`tests/import.rs`의 `htpack()` 꼴)으로 넣어 본다.
//! 확인하는 것:
//! - 새 갈래 `kin` 기록(열 꼴 뼈대 — 8-1)이 해석 없이 들어가 `entity` · `entities`로 **바이트까지 그대로** 돌아온다.
//!   uid 꼴 넷: `kin:<뿌리 가문 id>` · `kin:polity:<정권 uid>` · 나눈 덩어리 `kin:<파 가문 id>` · `kin:<뿌리>#<안정 열쇠>`.
//!   `#`이 든 덩어리가 없으면 엔진은 밑동(`#` 앞 = `kin:<뿌리>`)을 돌려준다(공동 사건의 `uid#1`과 같은 길) —
//!   그래서 앱은 답의 `json.key`가 물은 uid와 같은지 보고, 다르면 '없는 덩어리'로 읽는다.
//! - `kin` 기록은 이름 표에 들지 않고 검색 갈래도 아니다(`kinds:["kin"]`은 '모르는 갈래').
//! - 기간 없는 계보 전용 인물(kind `figure` · 활동 막대 없음)이 이름 표 · `search`에 든다.
//!   곁글은 기록의 `x_find.sub`('계보 전용 · ○○파'), 기간 · 줄 · 트랙은 비고(때 글 '미정'),
//!   차례는 기간이 있는 항목 뒤 · 칸 앞에서 갈래 → 이름 → uid 차례다.
//!   이름 미상(본문 `lineageOnly: true` + 이름이 '미상' 꼴 — 웹 `HT.isUnknownWho`)은 이름 표에 넣지 않는다(설계 2-4 다 — 이름 찾기 · 검색에 넣지 않음).
//! - 가문 · 정권 · 성씨 기록의 새 미리 푼 값(`x_kin` · `x_head` · `x_spots` · `x_under` · `x_eras` · `x_memberCount` · `x_lineage[ref]`의 덧칸)은
//!   그대로 실려 오고, 가문 · 정권의 이름 표 줄은 그대로다.
//! - 계보 기록을 더해도 다른 답(layout · 타일 바이트 · 날짜 검색 · 계보 밖 검색 · 옛 모양 search · 표)은 그대로다.
//! - 큰 뼈대 기록(5만 · 5MB)의 `entity` 시간(저장소 조회 · FFI 한 번) — 예산은 설계 6-2(5만 · 2.4MB 받기 ≤ 10ms).
//! - D1-E의 실제 기록(`prototype/app/test/fixtures/kin-*.json` · `kin-chunks-*.json`)이 있으면 그대로 넣어 위 규칙을 다시 본다
//!   (없으면 건너뜀 — 결합 때 저절로 붙는다. `D1_KIN_FIXTURES=<폴더>`로 대역 자료를 줄 수 있다).
//!
//! 위의 손 고정 자료는 '구현 이음새 기록'의 D1-E 꼴(머리 `uid` · 열쇠 차례 · `kinAt` · `x_kin` · `x_under` · 덩어리 `root` · `extraFar`)을 따른 대역이다.
use archive_engine::legacy::import_layout;
use archive_engine::levels::tile_of;
use archive_engine::tile::{build_tile, TileRequest};
use archive_engine::{archive_call, archive_free, Store};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::ffi::{CStr, CString};
use std::io::Write;
use std::path::PathBuf;
use std::time::Instant;

/// 한 해 ≈ 분(검사 안에서만 쓰는 어림값 — 1970년이 0분).
const Y: i64 = 525_600;

fn year(y: i64) -> i64 {
    (y - 1970) * Y
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("archive-kin-{}-{name}", std::process::id()));
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

/// 항목 기록 한 줄(본문은 JSON 글 — 내보내기의 `JSON.stringify`처럼 빈칸 없는 글).
fn entity(uid: &str, kind: &str, body: &Value) -> Value {
    json!({"uid":uid,"kind":kind,"pack":0,"json":body.to_string()})
}

/// 지도자 칸의 `style` — 칸 참조 번호(순번 + 1)를 15~26비트에 싣는다(계약 6-2).
fn leader_style(seq: i64) -> i64 {
    (seq + 1) << 15
}

/// 설계 8-1의 열 꼴 뼈대 예시(2-6 견본을 줄인 것) — 물빛 온씨 본가의 뼈대. 머리 · 열쇠 차례는 '구현 이음새 기록'의 D1-E ②
/// (머리 `uid` · 열 `key` · 차례 고정)를 따른 **내보내기의 글 그대로**(`JSON.stringify` — 빈칸 없음 · 한글 · 한자를 그대로 둠).
/// 글 열에 따옴표 · 역빗금 · 한자 · 넷째 평면 글자를 하나씩 섞어, 기록이 **글자 그대로** 오가는지 함께 본다.
const KIN_ON: &str = r##"{"v":1,"uid":"kin:h-on","n":7,"gens":5,"par":[-1,0,1,2,3,3,0],"size":[7,5,4,3,1,1,1],"gen":[0,1,2,3,4,4,1],"bits":[33,81,81,67,65,65,33],"edge":[0,0,0,0,0,0,0],"branch":[0,1,2,2,2,2,0],"color":[1,0,0,0,0,0,1],"color2":[],"name":["첫 임금","바람대군","솔군","미상","온 가람","온 나래","둘째 임금"],"sub":["가람 나라 1대 · 1400~1418","1402~","\"솔\\군\" 溫","","𠀋","","가람 나라 2대 · 1418~1450"],"key":["c:kin-example/garam|leader:0","f:kin-example/f-baram","f:kin-example/f-sol","f:kin-example/f-sol-x","f:kin-example/f-ga","f:kin-example/f-na","c:kin-example/garam|leader:1"],"extra":[],"colors":["","#a0bcc5"],"branches":[{"uid":"house:h-on","name":"물빛 온씨","color":"#a0bcc5","at":0,"up":-1},{"uid":"house:h-on-baram","name":"바람대군파","color":"#b5a3c4","at":1,"up":0},{"uid":"house:h-on-sol","name":"솔군파","color":"#c4b38f","at":2,"up":1}],"cells":{"kin-example/garam|leader:0":0,"kin-example/garam|leader:1":6},"stubs":{},"warnings":[]}"##;

/// 나라의 뼈대(가문이 없는 지도자들) — `kin:polity:<정권 uid>`. 같은 차례의 글.
const KIN_POLITY: &str = r##"{"v":1,"uid":"kin:polity:kin-example/haneul","n":2,"gens":2,"par":[-1,0],"size":[2,1],"gen":[0,1],"bits":[33,33],"edge":[0,0],"branch":[0,0],"color":[1,1],"color2":[],"name":["하늘 첫 임금","하늘 둘째 임금"],"sub":["",""],"key":["c:kin-example/haneul|leader:0","c:kin-example/haneul|leader:1"],"extra":[],"colors":["","#9dbea8"],"branches":[],"cells":{"kin-example/haneul|leader:0":0,"kin-example/haneul|leader:1":1},"stubs":{},"warnings":[]}"##;

/// 나눈 덩어리(D1-E ③) — 파 가문(`kin:<파 가문 id>`)과, 파가 없을 때의 안정 열쇠(`kin:<뿌리>#<안정 열쇠>`).
/// 머리 뒤에 `root`(뿌리 뼈대 · 한 벌 번호 · 꼬투리를 가진 기록 · 그 안 번호)와 `extraFar`가 붙는다. 엔진은 풀지 않는다.
fn kin_chunk(uid: &str, at: i64, names: &[&str]) -> String {
    let n = names.len();
    let ints = |f: &dyn Fn(usize) -> i64| (0..n).map(f).map(|v| v.to_string()).collect::<Vec<_>>().join(",");
    let texts = |f: &dyn Fn(usize) -> String| (0..n).map(f).map(|v| Value::from(v).to_string()).collect::<Vec<_>>().join(",");
    format!(
        r##"{{"v":1,"uid":{uid},"n":{n},"gens":{gens},"par":[{par}],"size":[{size}],"gen":[{gen}],"bits":[{bits}],"edge":[{zero}],"branch":[{branch}],"color":[{zero}],"color2":[],"name":[{name}],"sub":[{sub}],"key":[{key}],"extra":[],"colors":["","#a0bcc5"],"branches":[],"cells":{{}},"stubs":{{}},"warnings":[],"root":{{"uid":"kin:h-on","at":{at},"up":"kin:h-on","upAt":{at}}},"extraFar":[{{"from":"f:kin-example/f-baram","fromAt":1,"to":0,"kind":1,"gen":1}}]}}"##,
        uid = Value::from(uid),
        gens = at + n as i64,
        par = ints(&|i| i as i64 - 1),
        size = ints(&|i| (n - i) as i64),
        gen = ints(&|i| at + i as i64),
        bits = ints(&|_| 65),
        zero = ints(&|_| 0),
        branch = ints(&|_| 2),
        name = texts(&|i| names[i].to_owned()),
        sub = texts(&|_| String::new()),
        key = texts(&|i| format!("n:{}", names[i])),
    )
}

/// 계보 전용 인물 기록 — 내보내기가 `plain`에서 `services` · `service` · `importance`를 뺀 것(8-1 · D1-E ⑤). 날짜 · 활동 막대가 없다.
fn lineage_figure(id: &str, name: &str, at: i64, sub: &str, more: Value) -> Value {
    let mut body = json!({"id":id,"track":"garam","name":name,"lineageOnly":true,"kind":"figure","itemKind":"figure",
        "uid":format!("kin-example/{id}"),"packId":"kin-example","x_kin":{"key":"kin:h-on","at":at},
        "x_names":{"main":name},"x_find":{"hay":"가람","sub":sub}});
    for (k, v) in more.as_object().unwrap() {
        body[k] = v.clone();
    }
    body
}

/// 계보 기록이 든 작은 배치(2-6 견본의 꼴). `with_kin`이 거짓이면 같은 배치에서 D1이 더하는 것 — `kin` 기록 · 계보 전용 인물 ·
/// 가문 · 정권 · 성씨의 새 미리 푼 값 — 만 뺀다(형식 3 계보가 없는 자료).
fn layout(with_kin: bool) -> Value {
    let garam = "kin-example/garam";
    let mut plan = json!({
        "name": "계보 예시",
        "packs": [{"id":"kin-example","name":"계보 예시"}],
        "categories": [{"key":"lore","name":"이야기","color":0x9a6f8a}],
        "tracks": [
            {"name":"가람","key":"garam","color":0xc8b193,"dynasty":1,"leader":1,"cabinet":0,"organ":0,"rows":[row(), row()]},
            {"name":"하늘","key":"haneul","color":0x9dbea8,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"rows":[row()]}
        ],
        "axis": [],
        "periods": [
            {"uid":garam,"track":0,"row":0,"start":year(1400),"end":year(1650),"color":0xa0bcc5,"name":"가람 나라"},
            {"uid":"kin-example/haneul","track":1,"row":0,"start":year(1300),"end":year(1500),"color":0x9dbea8,"name":"하늘 나라"}
        ],
        "cells": [
            {"period":garam,"kind":1,"start":year(1400),"end":year(1418),"name":"첫 임금","style":leader_style(0)},
            {"period":garam,"kind":1,"start":year(1418),"end":year(1450),"name":"둘째 임금","style":leader_style(1)},
            {"period":"kin-example/haneul","kind":1,"start":year(1300),"end":year(1350),"name":"하늘 첫 임금","style":leader_style(0)},
            {"period":"kin-example/haneul","kind":1,"start":year(1350),"end":year(1400),"name":"하늘 둘째 임금","style":leader_style(1)}
        ],
        "events": [
            {"uid":"kin-example/e-first","track":0,"row":0,"start":year(1401),"end":year(1401),"importance":3,"title":"가람의 첫 기록","body":"나라를 열었다","band":garam},
            {"uid":"kin-example/e-sky","track":1,"row":0,"start":year(1320),"end":year(1320),"importance":2,"title":"하늘의 큰비","body":""}
        ],
        // 띠 인물(달 왕비)의 활동 막대(구역 37) — 이름 표가 이 막대에서 줄 · 기간을 빌린다.
        "items": [
            {"section":37,"track":0,"row":1,"row2":1,"start":year(1405),"end":year(1440),"lod":13,"ref":garam,"name":"달 왕비","color":0xa0bcc5,
             "text2":format!("kin-example/f-dal|{}|{}|h-on", year(1385), year(1450))}
        ],
        "entities": [
            entity(garam, "period", &json!({"uid":garam,"name":"가람 나라","track":"garam","house":"h-on",
                "x_lineage":{"leader:1":{"kin":"아들","kinId":"son","how":"선양","howId":"abdicate","from":{"uid":garam,"ref":"leader:0","name":"첫 임금"}}},
                "x_find":{"hay":"누리족 가람"}})),
            entity("kin-example/haneul", "period", &json!({"uid":"kin-example/haneul","name":"하늘 나라","track":"haneul","x_find":{"hay":"하늘"}})),
            entity("kin-example/f-dal", "figure", &json!({"uid":"kin-example/f-dal","name":"달 왕비","track":"garam","role":"왕비","x_find":{"hay":"왕비 가람"}})),
            entity("kin-example/e-first", "event", &json!({"uid":"kin-example/e-first","title":"가람의 첫 기록","x_find":{"hay":"가람"}})),
            entity("house:h-on", "house", &json!({"id":"h-on","uid":"house:h-on","itemKind":"house","name":"물빛 온씨","surname":"온","seat":"물빛",
                "founder":"가람 나라:첫 임금@1400","x_find":{"hay":"온 물빛 가람 나라:첫 임금@1400"}})),
            entity("house:h-on-baram", "house", &json!({"id":"h-on-baram","uid":"house:h-on-baram","itemKind":"house","name":"바람대군파","parent":"h-on","founder":"f-baram"})),
            entity("house:h-on-sol", "house", &json!({"id":"h-on-sol","uid":"house:h-on-sol","itemKind":"house","name":"솔군파","parent":"h-on-baram","founder":"f-sol"})),
            entity("surname:sn-on", "surname", &json!({"id":"sn-on","uid":"surname:sn-on","name":"온","houses":["h-on"]}))
        ]
    });
    if !with_kin {
        return plan;
    }
    let list = plan["entities"].as_array_mut().unwrap();
    // 정권 · 가문 · 성씨 기록에 D1의 미리 푼 값을 더한다(같은 uid의 기록을 바꾼다 — 넣은 차례는 그대로).
    let mut with = |uid: &str, more: Value| {
        let slot = list.iter_mut().find(|e| e["uid"] == uid).unwrap();
        let mut body: Value = serde_json::from_str(slot["json"].as_str().unwrap()).unwrap();
        for (k, v) in more.as_object().unwrap() {
            if k == "x_lineage" {
                for (r, add) in v.as_object().unwrap() {
                    for (k2, v2) in add.as_object().unwrap() {
                        body["x_lineage"][r][k2] = v2.clone();
                    }
                }
            } else {
                body[k] = v.clone();
            }
        }
        slot["json"] = Value::from(body.to_string());
    };
    // 정권의 승계 덧칸(선 갈래 · 이음매 글 · 뼈대 자리 — D1-E ①: A1-a의 `kin`(관계 글)과 부딪지 않게 `kinAt`)과 머리 칩.
    with(garam, json!({"x_lineage":{"leader:0":{"line":0},"leader:1":{"line":1,"seam":"전임자 첫 임금의 아들 · 선양","kinAt":["kin:h-on",6]}},
        "x_head":[{"role":"track","text":"가람","uid":"track:garam"},{"role":"people","text":"누리족"},{"role":"name","text":"가람 나라"},{"role":"tag","text":"통일 왕조"}]}));
    // 가문(D1-E ④): 뿌리 가문의 x_kin에는 at이 없다 · x_under는 가문 id 글(자기 포함 — 자기 하나면 싣지 않음).
    with("house:h-on", json!({
        "x_kin":{"key":"kin:h-on","n":7,"gens":5,"branches":[{"uid":"house:h-on-baram","name":"바람대군파","color":"#b5a3c4","n":5},{"uid":"house:h-on-sol","name":"솔군파","color":"#c4b38f","n":4}]},
        "x_head":[{"role":"track","text":"가람","auto":1},{"role":"people","text":"누리족","auto":1},{"role":"seat","text":"물빛 온씨"},{"role":"tag","text":"왕실"}],
        "x_spots":[{"uid":garam,"start":year(1400),"end":year(1450)}],
        "x_under":["h-on","h-on-baram","h-on-sol"],
        "x_eras":[{"uid":garam,"name":"가람 나라","color":"#a0bcc5","span":[year(1400),year(1650)],"cells":[[year(1400),year(1450)]]}],
        "x_memberCount":3}));
    with("house:h-on-baram", json!({"x_kin":{"key":"kin:h-on","at":1,"n":5,"gens":4,"branches":[{"uid":"house:h-on-sol","name":"솔군파","color":"#c4b38f","n":4}]},
        "x_under":["h-on-baram","h-on-sol"],
        "x_head":[{"role":"track","text":"가람","auto":1},{"role":"seat","text":"물빛 온씨"},{"role":"name","text":"바람대군파"}]}));
    with("house:h-on-sol", json!({"x_kin":{"key":"kin:h-on","at":2,"chunk":"kin:h-on-sol","n":4,"gens":3,"branches":[]}}));
    with("surname:sn-on", json!({"x_spots":[{"uid":garam,"start":year(1400),"end":year(1450)}]}));
    // 계보 전용 인물 다섯(2-6 견본) — 하나는 이름 미상(빈 고리 · 형제 둘의 공유 아버지).
    list.extend([
        entity("kin-example/f-baram", "figure", &lineage_figure("f-baram", "바람대군", 1, "계보 전용 · 바람대군파", json!({"role":"왕자","birth":1402}))),
        entity("kin-example/f-sol", "figure", &lineage_figure("f-sol", "솔군", 2, "계보 전용 · 솔군파", json!({}))),
        entity("kin-example/f-sol-x", "figure", &lineage_figure("f-sol-x", "미상", 3, "계보 전용 · 솔군파", json!({}))),
        entity("kin-example/f-ga", "figure", &lineage_figure("f-ga", "온 가람", 4, "계보 전용 · 솔군파", json!({}))),
        entity("kin-example/f-na", "figure", &lineage_figure("f-na", "온 나래", 5, "계보 전용 · 솔군파", json!({"description":"바다 건너 이름을 남겼다"}))),
    ]);
    // 뼈대 기록 — 뿌리 가문 · 나라 · 나눈 덩어리 둘. 본문은 내보내기의 글 그대로 싣는다(엔진이 다시 쓰지 않는지 보려고).
    for (uid, text) in [
        ("kin:h-on", KIN_ON.to_owned()),
        ("kin:polity:kin-example/haneul", KIN_POLITY.to_owned()),
        ("kin:h-on-sol", kin_chunk("kin:h-on-sol", 2, &["솔군", "미상", "온 가람", "온 나래"])),
        ("kin:h-on#f:kin-example/f-ga", kin_chunk("kin:h-on#f:kin-example/f-ga", 4, &["온 가람"])),
    ] {
        list.push(json!({"uid":uid,"kind":"kin","pack":0,"json":text}));
    }
    plan
}

/// 배치를 가져와 저장소를 짓는다.
fn build(name: &str, plan: &Value) -> (PathBuf, PathBuf) {
    let dir = scratch(name);
    let pack = dir.join("검사.htpack");
    std::fs::write(&pack, htpack(&json!({"format":"history-timeline-dlc","id":"kin-example","name":"계보 예시"}))).unwrap();
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

/// 배치에 실은 항목 기록 본문(글) — uid로.
fn sent(plan: &Value, uid: &str) -> String {
    plan["entities"].as_array().unwrap().iter().find(|e| e["uid"] == uid).unwrap()["json"].as_str().unwrap().to_owned()
}

#[test]
fn kin_기록은_해석_없이_들어가_entity로_글자_그대로_돌아온다() {
    let plan = layout(true);
    let (_dir, path) = build("record", &plan);
    let s = Store::open(&path).unwrap();
    for uid in ["kin:h-on", "kin:polity:kin-example/haneul", "kin:h-on-sol", "kin:h-on#f:kin-example/f-ga"] {
        let got = ask(&s, json!({"op":"entity","uid":uid}));
        assert_eq!(got["uid"], uid);
        assert_eq!(got["kind"], "kin", "{uid}");
        assert_eq!(got["json"].as_str().unwrap(), sent(&plan, uid), "{uid}: 본문이 글자 그대로");
        // 풀어 보면 열 꼴 그대로 — 판 · 머리 uid(D1-E ② — 열 `key`와 겹치지 않게 머리는 uid).
        let body: Value = serde_json::from_str(got["json"].as_str().unwrap()).unwrap();
        assert_eq!(body["v"], 1);
        assert_eq!(body["uid"], uid, "기록의 머리 uid는 제 uid");
        assert_eq!(body["key"].as_array().unwrap().len() as i64, body["n"].as_i64().unwrap(), "열 key는 마디마다 안정 열쇠");
    }
    assert_eq!(ask(&s, json!({"op":"entity","uid":"kin:h-on"}))["json"].as_str().unwrap(), KIN_ON, "8-1 예시의 열이 한 글자도 바뀌지 않는다");
    let on: Value = serde_json::from_str(KIN_ON).unwrap();
    assert_eq!(on["sub"][2], "\"솔\\군\" 溫");
    assert_eq!(on["sub"][4], "𠀋");
    let chunk: Value = serde_json::from_str(ask(&s, json!({"op":"entity","uid":"kin:h-on-sol"}))["json"].as_str().unwrap()).unwrap();
    assert_eq!(chunk["root"], json!({"uid":"kin:h-on","at":2,"up":"kin:h-on","upAt":2}), "나눈 덩어리의 덧칸도 그대로");
    // 여러 기록을 한 번에(`entities` — 상세 창이 칩을 펼 때 쓰는 길).
    let many = ask(&s, json!({"op":"entities","uids":["kin:h-on","kin:h-on-sol","house:h-on"]}));
    let got: Vec<(&str, &str)> = many.as_array().unwrap().iter().map(|v| (v["uid"].as_str().unwrap(), v["kind"].as_str().unwrap())).collect();
    assert_eq!(got, vec![("kin:h-on", "kin"), ("kin:h-on-sol", "kin"), ("house:h-on", "house")]);
    assert_eq!(many[1]["json"].as_str().unwrap(), sent(&plan, "kin:h-on-sol"));
    // 없는 덩어리: `#`이 든 uid는 밑동(`kin:h-on`)이 대신 온다 — 답의 uid는 물은 그대로지만 기록의 key가 다르다.
    let missing = ask(&s, json!({"op":"entity","uid":"kin:h-on#f:kin-example/없는-사람"}));
    assert_eq!(missing["uid"], "kin:h-on#f:kin-example/없는-사람");
    let body: Value = serde_json::from_str(missing["json"].as_str().unwrap()).unwrap();
    assert_eq!(body["uid"], "kin:h-on", "앱은 기록의 머리 uid ≠ 물은 uid이면 없는 덩어리로 읽는다");
    // `#`이 없는 없는 덩어리는 실패한다(앱은 '기록 없음'으로 읽는다).
    assert!(s.call(&json!({"op":"entity","uid":"kin:h-none"})).unwrap_err().to_string().contains("항목 기록이 없습니다"));
    // 가져오기 수: 항목 기록에 kin 넷이 함께 센다(자료집 · 줄 · 띠 · 사건 수는 그대로).
    let count: i64 = s.db.query_row("SELECT count(*) FROM entities WHERE kind='kin'", [], |r| r.get(0)).unwrap();
    assert_eq!(count, 4);
    let pack: i64 = s.db.query_row("SELECT pack FROM entities WHERE uid='kin:h-on'", [], |r| r.get(0)).unwrap();
    assert_eq!(pack, 1, "pack 번호(배치의 packs 순번)가 그대로 — 뿌리 가문의 DLC");
}

#[test]
fn kin_기록은_이름_표에_들지_않고_검색_갈래도_아니다() {
    let (_dir, path) = build("names", &layout(true));
    let s = Store::open(&path).unwrap();
    let n: i64 = s.db.query_row("SELECT count(*) FROM names WHERE kind='kin' OR uid LIKE 'kin:%'", [], |r| r.get(0)).unwrap();
    assert_eq!(n, 0);
    // 뼈대의 이름 열에만 있는 이름(나라 뼈대의 '하늘 첫 임금'은 칸 이름이기도 하다 — 칸 줄로만 나온다).
    let sky = ask(&s, json!({"op":"search","text":"하늘 첫 임금","kinds":ALL}));
    assert_eq!(kinds_of(&sky), vec!["cell"]);
    assert_eq!(sky["items"][0]["uid"], "kin-example/haneul");
    // 어떤 검색에서도 kin 기록이 결과 줄로 나오지 않는다.
    for text in ["온", "가람", "솔군", "미상", "하늘", "1418"] {
        let got = ask(&s, json!({"op":"search","text":text,"kinds":ALL,"limit":200}));
        assert!(got["items"].as_array().unwrap().iter().all(|v| !v["uid"].as_str().unwrap().starts_with("kin:")), "{text}: {got}");
    }
    let err = s.call(&json!({"op":"search","text":"온","kinds":["kin"]})).unwrap_err().to_string();
    assert!(err.contains("모르는 갈래"), "{err}");
    let err = s.call(&json!({"op":"search_year","at":year(1420),"kinds":["kin"]})).unwrap_err().to_string();
    assert!(err.contains("모르는 갈래"), "{err}");
    // 관점 이름 표 · 날짜 칸 주인도 kin 기록을 읽지 않는다.
    assert_eq!(ask(&s, json!({"op":"lens_names","lens":"local"})), json!({"events":{},"bands":{}}));
}

#[test]
fn 기간_없는_계보_전용_인물은_이름_표와_검색에_든다() {
    let mut plan = layout(true);
    // 이름 미상의 다른 꼴(웹 HT.isUnknownWho — 대소문자 · 앞뒤 빈칸 무시)과, 이름이 '미상'인 **보통** 인물(띠 인물 — 넣는다).
    plan["entities"].as_array_mut().unwrap().extend([
        entity("kin-example/f-unk", "figure", &lineage_figure("f-unk", " UNKNOWN\u{3000}", 6, "계보 전용 · 솔군파", json!({}))),
        entity("kin-example/f-q", "figure", &lineage_figure("f-q", "?", 7, "계보 전용", json!({}))),
        entity("kin-example/f-plain-x", "figure", &json!({"uid":"kin-example/f-plain-x","name":"미상","track":"garam","x_find":{"hay":"들판"}})),
    ]);
    let (_dir, path) = build("lineage", &plan);
    let s = Store::open(&path).unwrap();
    // 이름 표 줄: 갈래 figure · 기간 없음 · 줄 없음 · 곁글은 x_find.sub.
    let rows: Vec<(String, String, String, Option<i64>, Option<i64>, i64)> = {
        let mut stmt = s.db.prepare("SELECT uid,name,sub,start,end,row FROM names WHERE kind='figure' ORDER BY id").unwrap();
        let v = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))).unwrap().map(|r| r.unwrap()).collect();
        v
    };
    let lineage: Vec<_> = rows.iter().filter(|r| r.0 != "kin-example/f-dal" && r.0 != "kin-example/f-plain-x").cloned().collect();
    let plain_unknown = rows.iter().find(|r| r.0 == "kin-example/f-plain-x").expect("보통 인물은 이름이 '미상'이어도 이름 표에 든다");
    assert_eq!(plain_unknown.2, "", "x_find.sub가 없으면 곁글은 빈 글(예전 그대로)");
    // (이름 표의 번호는 항목 기록 표의 차례 = uid 차례로 붙는다 — 결과의 차례는 아래 검색 차례가 정한다.)
    assert_eq!(lineage, vec![
        ("kin-example/f-baram".to_owned(), "바람대군".to_owned(), "계보 전용 · 바람대군파".to_owned(), None, None, -1),
        ("kin-example/f-ga".to_owned(), "온 가람".to_owned(), "계보 전용 · 솔군파".to_owned(), None, None, -1),
        ("kin-example/f-na".to_owned(), "온 나래".to_owned(), "계보 전용 · 솔군파".to_owned(), None, None, -1),
        ("kin-example/f-sol".to_owned(), "솔군".to_owned(), "계보 전용 · 솔군파".to_owned(), None, None, -1),
    ], "이름 미상(f-sol-x · f-unk · f-q)은 빠진다");
    // 띠 인물은 예전 그대로 — 곁글 없음 · 활동 막대에서 줄 · 기간을 빌린다.
    let dal = rows.iter().find(|r| r.0 == "kin-example/f-dal").unwrap();
    assert_eq!((dal.2.as_str(), dal.3, dal.4, dal.5), ("", Some(year(1405)), Some(year(1440)), 1));
    // 이름 미상의 기록 자체는 열린다(세계표 카드를 누르면 그 창).
    assert_eq!(ask(&s, json!({"op":"entity","uid":"kin-example/f-sol-x"}))["kind"], "figure");
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"미상","kinds":ALL}))), vec!["미상"]);
    assert_eq!(ask(&s, json!({"op":"search","text":"미상","kinds":ALL}))["items"][0]["uid"], "kin-example/f-plain-x", "보통 인물만");
    assert_eq!(ask(&s, json!({"op":"search","text":"unknown","kinds":ALL}))["items"], json!([]));

    // 검색 결과 줄의 꼴.
    let got = ask(&s, json!({"op":"search","text":"바람대군","kinds":["figure"]}));
    assert_eq!(got["items"].as_array().unwrap().len(), 1);
    let baram = &got["items"][0];
    assert_eq!(baram["kind"], "figure");
    assert_eq!(baram["uid"], "kin-example/f-baram");
    assert_eq!(baram["name"], "바람대군");
    assert_eq!(baram["sub"], "계보 전용 · 바람대군파");
    assert_eq!((baram["start"].clone(), baram["end"].clone(), baram["row"].clone()), (Value::Null, Value::Null, Value::Null));
    assert_eq!(baram["when"], "미정");
    assert_eq!(baram["track"], "", "제 줄이 없으니 트랙 이름도 없다");
    assert_eq!((baram["cell"].clone(), baram["id"].clone()), (Value::Null, Value::Null));
    // 곁글 · 찾을 글 · 설명으로도 찾힌다(이름 표의 lower(name||' '||sub) · hay).
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"바람대군파","kinds":["figure"]}))), vec!["바람대군"]);
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"계보 전용 솔군파","kinds":["figure"]}))), vec!["솔군", "온 가람", "온 나래"]);
    assert_eq!(names(&ask(&s, json!({"op":"search","text":"바다 건너","kinds":["figure"]}))), vec!["온 나래"]);
    // 차례: 기간이 있는 항목(시작 순) → 기간 없는 항목(갈래 → 이름 → uid) → 칸 → 가문.
    let all = ask(&s, json!({"op":"search","text":"가람","kinds":ALL,"limit":200}));
    assert_eq!(names(&all), vec!["가람 나라", "가람의 첫 기록", "달 왕비", "바람대군", "솔군", "온 가람", "온 나래", "첫 임금", "둘째 임금", "물빛 온씨"]);
    assert_eq!(kinds_of(&all), vec!["period", "event", "figure", "figure", "figure", "figure", "figure", "cell", "cell", "house"]);
    assert_eq!(all["total"], json!(10));
    // 나눠 받아도 같다.
    let mut joined = Vec::new();
    let mut after = 0;
    loop {
        let page = ask(&s, json!({"op":"search","text":"가람","kinds":ALL,"limit":3,"after":after}));
        joined.extend(names(&page));
        if page["has_more"] != json!(true) {
            break;
        }
        after = page["next"].as_i64().unwrap();
    }
    assert_eq!(joined, names(&all));
    // 거르개: 트랙을 꺼도 제 줄이 없는 계보 전용 인물은 숨지 않는다(띠 인물 · 정권 · 칸은 숨는다).
    let garam: i64 = s.db.query_row("SELECT id FROM tracks WHERE name='가람'", [], |r| r.get(0)).unwrap();
    let off = ask(&s, json!({"op":"search","text":"가람","kinds":ALL,"limit":200,"filter":{"tracks_off":[garam]}}));
    assert_eq!(names(&off), vec!["바람대군", "솔군", "온 가람", "온 나래", "물빛 온씨"]);
    // 켠 자료집 밖이면 없다.
    assert_eq!(ask(&s, json!({"op":"search","text":"바람대군","kinds":["figure"],"packs":[]}))["items"], json!([]));
    // 날짜 검색에는 들지 않는다(기간이 없다 — 인물은 날짜 검색의 갈래가 아니기도 하다).
    let at = ask(&s, json!({"op":"search_year","at":year(1420),"limit":200}));
    assert!(names(&at).iter().all(|n| !["바람대군", "솔군", "온 가람", "온 나래"].contains(&n.as_str())), "{at}");
}

#[test]
fn 가문_정권_성씨의_새_미리_푼_값은_그대로_오고_이름_표_줄은_그대로다() {
    let (plain_plan, kin_plan) = (layout(false), layout(true));
    let (_d1, plain_path) = build("x-plain", &plain_plan);
    let (_d2, kin_path) = build("x-kin", &kin_plan);
    let (plain, kin) = (Store::open(&plain_path).unwrap(), Store::open(&kin_path).unwrap());
    for uid in ["house:h-on", "house:h-on-baram", "kin-example/garam", "surname:sn-on"] {
        let got = ask(&kin, json!({"op":"entity","uid":uid}));
        assert_eq!(got["json"].as_str().unwrap(), sent(&kin_plan, uid), "{uid}");
    }
    let house: Value = serde_json::from_str(ask(&kin, json!({"op":"entity","uid":"house:h-on"}))["json"].as_str().unwrap()).unwrap();
    assert_eq!(house["x_kin"]["key"], "kin:h-on");
    assert_eq!(house["x_under"], json!(["h-on", "h-on-baram", "h-on-sol"]));
    assert_eq!(house["x_spots"][0]["start"], json!(year(1400)));
    let polity: Value = serde_json::from_str(ask(&kin, json!({"op":"entity","uid":"kin-example/garam"}))["json"].as_str().unwrap()).unwrap();
    assert_eq!(polity["x_lineage"]["leader:1"]["kin"], "아들", "A1-a의 칸(관계 글)은 그대로");
    assert_eq!(polity["x_lineage"]["leader:1"]["kinAt"], json!(["kin:h-on", 6]));
    assert_eq!(polity["x_lineage"]["leader:1"]["line"], 1);
    // 이름 표에서 가문 · 정권 · 칸 줄(계보 전용 인물 밖)은 두 저장소가 같다.
    let table = |s: &Store| -> Vec<String> {
        let mut stmt = s.db.prepare("SELECT kind,uid,name,sub,cell,start,end,row,color,cell_ref,hay FROM names WHERE NOT (kind='figure' AND uid<>'kin-example/f-dal') ORDER BY id").unwrap();
        let v = stmt.query_map([], |r| {
            let mut parts = Vec::new();
            for i in 0..11 {
                parts.push(format!("{:?}", r.get::<_, rusqlite::types::Value>(i)?));
            }
            Ok(parts.join(" | "))
        }).unwrap().map(|r| r.unwrap()).collect();
        v
    };
    assert_eq!(table(&kin), table(&plain));
    // 가문은 넣은 차례 그대로 · 곁글 없음.
    assert_eq!(names(&ask(&kin, json!({"op":"search","text":"파","kinds":["house"]}))), vec!["바람대군파", "솔군파"]);
    assert_eq!(ask(&kin, json!({"op":"search","text":"물빛","kinds":["house"]}))["items"], ask(&plain, json!({"op":"search","text":"물빛","kinds":["house"]}))["items"]);
}

/// 저장소의 모든 표본 타일(단계 여럿 × 자료 범위 전부 × 묶음 하나)을 바이트 지문으로.
fn tile_prints(s: &Store) -> Vec<(usize, i64, String)> {
    let mut out = Vec::new();
    for level in [13usize, 12, 11, 10, 9, 8, 7, 5, 3, 0] {
        let (lo, hi) = (tile_of(year(1290), level), tile_of(year(1660), level));
        for x in lo..=hi.min(lo + 40) {
            let req = TileRequest { level, x, chunk: 0, packs: vec![1], filter: None, variants: None };
            let bytes = build_tile(s, &req).unwrap();
            out.push((level, x, format!("{:x}", Sha256::digest(&bytes))));
        }
    }
    out
}

#[test]
fn 계보_기록을_더해도_다른_답은_그대로다() {
    let (_d1, plain_path) = build("same-plain", &layout(false));
    let (_d2, kin_path) = build("same-kin", &layout(true));
    let (plain, kin) = (Store::open(&plain_path).unwrap(), Store::open(&kin_path).unwrap());
    assert_eq!(ask(&kin, json!({"op":"layout"})), ask(&plain, json!({"op":"layout"})));
    let (a, b) = (tile_prints(&plain), tile_prints(&kin));
    assert!(a.len() > 50, "표본 타일 {}장", a.len());
    assert_eq!(b, a, "타일 바이트가 같다");
    for q in [
        json!({"op":"search_year","at":year(1420)}),
        json!({"op":"search_year","at":year(1300),"end":year(1660),"limit":200}),
        json!({"op":"search","text":"첫","kinds":ALL}),
        json!({"op":"search","text":"하늘","kinds":ALL}),
        json!({"op":"search","text":"가람"}),
        json!({"op":"search","text":"왕비","kinds":["figure"]}),
        json!({"op":"table","limit":200}),
        json!({"op":"table","with_periods":true,"lo":year(1300),"hi":year(1660),"limit":200}),
        json!({"op":"row_labels","rows":[0,1,2]}),
        json!({"op":"rows_near","t0":year(1300),"t1":year(1660)}),
        json!({"op":"cells_of","uid":"kin-example/garam","kind":1}),
    ] {
        let (x, y) = (plain.call(&q).map_err(|e| e.to_string()), kin.call(&q).map_err(|e| e.to_string()));
        assert_eq!(y, x, "{q}");
    }
    // 기간 범위를 주지 않은 표(시대 · 인물 포함)에도 계보 전용 인물은 싣지 않는다 — 웹 표(viewer.js tableItems)가 띠 인물만 싣는 것과 같게.
    // (D1n 결합에서 query.rs table_union이 본문 lineageOnly를 거르게 했다. 그 전에는 기간 없는 줄 넷이 표 끝에 붙었다.)
    let (x, y) = (ask(&plain, json!({"op":"table","with_periods":true,"limit":200})), ask(&kin, json!({"op":"table","with_periods":true,"limit":200})));
    assert_eq!(y, x, "기간 범위 없는 표도 같다 — 계보 전용 인물 줄 없음");
    let rows = y["rows"].as_array().or_else(|| y["items"].as_array()).unwrap();
    assert!(rows.iter().all(|r| r.to_string().find("바람대군").is_none()), "계보 전용 인물(바람대군)은 표에 없다");
    assert!(names(&ask(&kin, json!({"op":"search","text":"바람대군","kinds":["figure"]}))).contains(&"바람대군".to_owned()), "검색에는 그대로 든다");
}

/// 가상 대가족의 열 꼴 뼈대 — 사람 `n`명(결정적 · 이름은 가상 음절 조합).
fn big_kin(n: usize) -> String {
    const A: [&str; 8] = ["가", "나", "다", "라", "마", "바", "사", "아"];
    const B: [&str; 8] = ["람", "래", "솔", "빛", "결", "울", "온", "늘"];
    let par: Vec<i64> = (0..n as i64).map(|i| if i == 0 { -1 } else { (i - 1) / 3 }).collect();
    let gen: Vec<i64> = {
        let mut g = vec![0i64; n];
        for i in 1..n {
            g[i] = g[par[i] as usize] + 1;
        }
        g
    };
    let name: Vec<String> = (0..n).map(|i| format!("온 {}{}{}", A[i % 8], B[(i / 8) % 8], A[(i / 64) % 8])).collect();
    let key: Vec<String> = (0..n).map(|i| format!("f:kin-big/f-{i}")).collect();
    json!({"v":1,"uid":"kin:h-big","n":n,"gens":gen.iter().max().unwrap() + 1,
        "par":par,"size":vec![1; n],"gen":gen,"bits":(0..n).map(|i| if i % 50 == 0 { 81 } else { 65 }).collect::<Vec<_>>(),
        "edge":(0..n).map(|i| (i % 97 == 0) as i64).collect::<Vec<_>>(),"branch":(0..n).map(|i| (i % 12) as i64).collect::<Vec<_>>(),
        "color":vec![0; n],"color2":[],"name":name,"sub":(0..n).map(|i| if i % 4 == 0 { format!("{}~", 1400 + i % 300) } else { String::new() }).collect::<Vec<_>>(),
        "key":key,"extra":[],"colors":[""],"branches":[],"cells":{},"stubs":{},"warnings":[]}).to_string()
}

fn ffi(request: &Value) -> (String, f64) {
    let text = CString::new(request.to_string()).unwrap();
    let started = Instant::now();
    unsafe {
        let answer = archive_call(text.as_ptr());
        let got = CStr::from_ptr(answer).to_str().unwrap().to_owned();
        archive_free(answer);
        (got, started.elapsed().as_secs_f64() * 1000.0)
    }
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

/// 큰 뼈대 기록의 `entity` 시간. 설계 6-2의 예산은 5만 · 2.4MB 받기 ≤ 10ms(엔진 한 번), 9-2 D1-B는 5MB 기록의 시간을 잰다.
/// 이 상자는 작업자 여럿이 함께 돌아 시간이 흔들린다 — 단언은 넉넉히(예산의 열 배) 두고, 잰 값은 찍어 보고에 옮긴다.
#[test]
fn 큰_뼈대_기록의_entity_시간() {
    let mut plan = layout(false);
    let mut sizes = Vec::new();
    for (uid, n) in [("kin:h-big-50k", 50_000usize), ("kin:h-big-5mb", 105_000)] {
        let text = big_kin(n).replacen("\"kin:h-big\"", &format!("\"{uid}\""), 1);
        sizes.push((uid, n, text.len()));
        plan["entities"].as_array_mut().unwrap().push(json!({"uid":uid,"kind":"kin","pack":0,"json":text}));
    }
    assert!(sizes[1].2 >= 5_000_000, "5MB 기록: {} 바이트", sizes[1].2);
    let started = Instant::now();
    let (_dir, path) = build("big", &plan);
    let import_ms = started.elapsed().as_secs_f64() * 1000.0;
    let s = Store::open(&path).unwrap();
    let mut report = Vec::new();
    for (uid, n, bytes) in &sizes {
        let want = sent(&plan, uid);
        // 저장소 조회(Store::call)와 FFI 겉(archive_call — 답을 JSON 글로 감싸 C 글자열로 넘김)을 따로 잰다.
        let mut call_ms = Vec::new();
        for _ in 0..7 {
            let t = Instant::now();
            let got = ask(&s, json!({"op":"entity","uid":uid}));
            call_ms.push(t.elapsed().as_secs_f64() * 1000.0);
            assert_eq!(got["json"].as_str().unwrap().len(), want.len());
        }
        report.push((uid.to_string(), *n, *bytes, median(call_ms)));
    }
    // FFI: 이 검사 파일에서 전역 저장소를 여는 것은 이 검사 하나뿐이다.
    let (opened, _) = ffi(&json!({"op":"open","path":path.to_str().unwrap()}));
    assert!(opened.contains("\"ok\":true"), "{opened}");
    let mut ffi_report = Vec::new();
    for (uid, _, bytes) in &sizes {
        let mut times = Vec::new();
        let mut answer_bytes = 0;
        for _ in 0..7 {
            let (got, ms) = ffi(&json!({"op":"entity","uid":uid}));
            times.push(ms);
            answer_bytes = got.len();
            if times.len() == 1 {
                let v: Value = serde_json::from_str(&got).unwrap();
                assert_eq!(v["ok"], true);
                assert_eq!(v["data"]["json"].as_str().unwrap(), sent(&plan, uid), "FFI로도 글자 그대로");
            }
        }
        ffi_report.push((uid.to_string(), *bytes, answer_bytes, median(times)));
    }
    ffi(&json!({"op":"close"}));
    eprintln!("[D1-B] 큰 뼈대 기록 — 가져오기(두 기록 함께) {import_ms:.1}ms");
    for ((uid, n, bytes, call), (_, _, answer, ffi_ms)) in report.iter().zip(&ffi_report) {
        eprintln!("[D1-B] {uid}: 사람 {n} · 기록 {bytes}B · Store::call entity 중앙 {call:.2}ms · FFI archive_call 중앙 {ffi_ms:.2}ms(답 {answer}B)");
    }
    // 예산(5만 · 2.4MB ≤ 10ms)의 열 배를 넘으면 잘못이다 — 기록 크기에 비례해 5MB는 그 두 배.
    assert!(report[0].3 <= 100.0 && ffi_report[0].3 <= 100.0, "5만: {report:?} {ffi_report:?}");
    assert!(report[1].3 <= 200.0 && ffi_report[1].3 <= 200.0, "5MB: {report:?} {ffi_report:?}");
}

/// D1-E의 실제 기록(`prototype/app/test/fixtures/kin-<견본>.json` — 엔진 `entity` 답 꼴 `[{ uid, kind, json }]`,
/// 덩어리는 `kin-chunks-<견본>.json`의 `{ limit, records }`)이 있으면 그대로 저장소에 넣어 본다. 없으면 건너뛴다(결합 때 붙음).
/// 정답 자리(`kin-golden-*`)는 엔진이 읽지 않는다. 환경 변수 `D1_KIN_FIXTURES`로 다른 폴더를 줄 수 있다(대역 자료로 이 검사를 볼 때).
fn e_fixtures() -> Vec<(String, Vec<Value>)> {
    let dir = std::env::var_os("D1_KIN_FIXTURES").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../app/test/fixtures"));
    let mut files: Vec<PathBuf> = match std::fs::read_dir(&dir) {
        Ok(list) => list.filter_map(|e| e.ok().map(|e| e.path())).collect(),
        Err(_) => return Vec::new(),
    };
    files.sort();
    let mut out = Vec::new();
    for path in files {
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("").to_owned();
        if !name.starts_with("kin-") || !name.ends_with(".json") || name.starts_with("kin-golden-") {
            continue;
        }
        let doc: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap_or_else(|e| panic!("{name}: {e}"));
        let records = match &doc {
            Value::Array(list) => list.clone(),
            Value::Object(map) => map.get("records").and_then(Value::as_array).cloned().unwrap_or_default(),
            _ => Vec::new(),
        };
        let records: Vec<Value> = records.into_iter().filter(|r| r["uid"].is_string() && r["json"].is_string()).collect();
        if !records.is_empty() {
            out.push((name, records));
        }
    }
    out
}

#[test]
fn d1_e의_실제_기록이_있으면_그대로_들어가고_같은_규칙을_지킨다() {
    let sets = e_fixtures();
    if sets.is_empty() {
        eprintln!("[D1-B] D1-E의 kin-*.json이 아직 없음 — 건너뜀(결합 때 붙음)");
        return;
    }
    for (name, records) in sets {
        // 띠 · 칸이 없는 빈 배치에 기록만 싣는다(같은 uid는 뒤엣것이 이긴다 — 항목 기록 표와 같게 맨 뒤 것만 견준다).
        let mut plan = layout(false);
        for key in ["periods", "cells", "events", "items"] {
            plan[key] = json!([]);
        }
        plan["entities"] = Value::Array(records.iter().map(|r| json!({"uid":r["uid"],"kind":r["kind"].as_str().unwrap_or("kin"),"pack":0,"json":r["json"]})).collect());
        let mut last: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
        for r in &records {
            last.insert(r["uid"].as_str().unwrap().to_owned(), r.clone());
        }
        let started = Instant::now();
        let (_dir, path) = build(&format!("e-{}", name.trim_end_matches(".json")), &plan);
        let import_ms = started.elapsed().as_secs_f64() * 1000.0;
        let s = Store::open(&path).unwrap();
        let (mut kin, mut lineage, mut unknown, mut bytes) = (0, 0, 0, 0usize);
        for (uid, r) in &last {
            let got = ask(&s, json!({"op":"entity","uid":uid}));
            assert_eq!(got["json"], r["json"], "{name} {uid}: 글자 그대로");
            let body: Value = serde_json::from_str(r["json"].as_str().unwrap()).unwrap();
            let in_names: i64 = s.db.query_row("SELECT count(*) FROM names WHERE uid=?1 AND kind<>'cell'", [uid], |q| q.get(0)).unwrap();
            match r["kind"].as_str().unwrap_or("") {
                "kin" => {
                    kin += 1;
                    bytes += r["json"].as_str().unwrap().len();
                    assert_eq!(body["uid"], uid.as_str(), "{name}: 뼈대 기록의 머리 uid = 기록 uid");
                    assert_eq!(in_names, 0, "{name} {uid}: kin 기록은 이름 표 밖");
                }
                "figure" if body["lineageOnly"] == json!(true) => {
                    let who = body["name"].as_str().unwrap_or("").trim().to_lowercase();
                    if archive_engine::builder::UNKNOWN_WHO.contains(&who.as_str()) {
                        unknown += 1;
                        assert_eq!(in_names, 0, "{name} {uid}: 이름 미상은 이름 표 밖");
                    } else {
                        lineage += 1;
                        assert_eq!(in_names, 1, "{name} {uid}: 계보 전용 인물은 이름 표에");
                        let (sub, start, row): (String, Option<i64>, i64) = s.db.query_row("SELECT sub,start,row FROM names WHERE uid=?1 AND kind='figure'", [uid], |q| Ok((q.get(0)?, q.get(1)?, q.get(2)?))).unwrap();
                        assert_eq!(sub, body["x_find"]["sub"].as_str().unwrap_or(""), "{name} {uid}: 곁글 = x_find.sub");
                        assert_eq!((start, row), (None, -1), "{name} {uid}: 기간 · 줄 없음");
                    }
                }
                _ => {}
            }
        }
        eprintln!("[D1-B] {name}: 기록 {} · kin {kin}({bytes}B) · 계보 전용 이름 줄 {lineage} · 이름 미상 {unknown} · 가져오기 {import_ms:.1}ms", last.len());
    }
}

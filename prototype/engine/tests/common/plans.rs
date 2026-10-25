//! 작은 배치 장면(계획 P4 과제 1b) — 자료집 조합마다 가져오기 JSON 3판(계약 4절)과 그 원본(.htpack)을 짓는다.
//! 과제 1c · 2 · 4 · 5a ~ 5d · 6 · 7의 검사가 함께 쓴다. 이름은 모두 가상이다.
//!
//! 자료집 넷(첫째가 기본):
//! - `a`(기본 · v1.0.0): 트랙 `ta`(줄 넷 · 묶음 하나) · 판 트랙 하나(`__board:view:a1` — 변형 kind 3 · 내보내기 `boards.mjs` 꼴로
//!   **`ta`의** 칸 하나 · 관계선 하나를 가리고(`BOARD_CELL` · `BOARD_ITEM`), 칸의 변형 판은 겉 열쇠 `boards.cells`에 판 변형 열쇠를 달고
//!   `ta`의 띠에 딸린다) · 분류 셋 · 시대 구분 둘 ·
//!   공통 날짜 칸 · `ta`의 연호 칸 · `ta`의 띠 넷(`a/ta-now`는 진행 중 — 끝 = [`NOW`]) · 칸 · 사건 300건(한 줄에 몰린 100건 —
//!   요약 단계에 알약이 차게) · 일반 항목 · 줄 이름 · 변형 `host:a/ta-host`(소속 펼치기 — 그 변형에서만 있는 줄 · 띠 · 칸 · 사건 ·
//!   항목 · 사건 이사 · `hides` 칸 하나와 항목 하나) · 항목 기록(트랙 있는 것 · 없는 것 · 가문 둘 · 단체 둘 — 가문 · 단체는
//!   uid 차례와 거꾸로 넣어 **넣은 차례**가 이름 찾기에 드러난다).
//! - `b`(v1.0.0): `ta`에 줄 하나(`a`의 줄 넷 뒤) · 그 줄의 띠 `b/ta-late` · `ta`에 사건을 **얹음**(제 줄과 `a`의 첫 줄) ·
//!   제 트랙 `tb` · 새 문화권 `s-west`(온 판) · 트랙 없는 항목 기록 하나(가문) · `tb`가 600년부터라 보는 범위가 넓어진다.
//! - `c`(v1.0.0): 트랙 `tc` · 일반 항목 둘(구역 60 — 장면 전용 · 뜻 없음)이 남의 트랙 띠를 `ref`로 —
//!   하나는 `a/ta-2`(늘 있음), 하나는 `b/ta-late`(b가 없으면 풀리지 않음) · 변형 `scope:c/sc-1`의 이사가 `c/tc-1`을 `ta`의 줄 3으로
//!   (그 변형의 묶음도 `ta`의 줄 3을 가리킨다).
//! - `a@2`(v2.0.0): `a`와 같은 uid · 같은 꼴로 `ta` 첫 띠(`a/ta-1`)의 색만 바꾼 판.
//!
//! 줄 · 트랙은 계약 4절대로 순번으로 가리킨다(트랙 = `tracks`의 순번 · 줄 = 그 트랙 안의 순번). `ta`는 늘 트랙 0이고, 다른 트랙은
//! 자료집 차례대로 뒤에 붙으며, 판 트랙은 겉 열쇠 `boards`로 맨 뒤에 붙는다. `ta`의 줄: 0 ~ 3 `a`의 줄 · (b가 있으면) 4 `b`의 줄 ·
//! 마지막 하나 = 소속 펼치기에서만 있는 줄. 변형의 `hides[].at`은 `cells` · `items`에서의 자리라 `a`의 것을 늘 맨 앞에 싣는다.
//! 사건 · 띠의 자료집은 uid의 앞머리(`a/` · `b/` · `c/`)로, 트랙 · 항목 기록 · 날짜 칸 · 일반 항목은 `pack`(그 배치의 `packs[]` 순번)으로 간다.
//! 사건 목록은 진짜 내보내기처럼 트랙 차례로 묶여 나간다(자료집 차례가 아니다 — 판정 R25).
//! 일반 항목의 **띠 번호 칸**(`archive_engine::bandref` — 내보내기처럼 '`periods` 배열 자리 + 1')에는 진짜 값이 든다:
//! 같은 트랙 띠(`a`의 구역 16 `d` = `a/ta-member` · 21 `b` = `a/ta-2` · 판의 21 `b` = `a/ta-2`)와 남의 트랙 띠(`c`의 구역 47 `d` = `a/ta-2` ·
//! 49 `b` = `b/ta-late` — b가 없으면 0). 자리는 조합마다 다르므로 띠를 다 모은 뒤에 셈한다.
//!
//! 스키마 4(계약 1-1 · 리메이크 3단계): 띠 몇에 형식 4의 뜻 `form`([`FORMS`] — 조합과 상관없이 늘 같은 값)이 있고, 최상위 `sphereLines`(문화권 단위 줄 —
//! 온 판)는 조합마다 다르다([`sphere_lines`]): `a`의 사람 띠(kind 1) · 문화권 시대(kind 2)는 늘, `b`가 있으면 `b`의 사람 띠(kind 1 · 자료집 순번 = b의 순번),
//! `c`가 있으면 `c`의 주기 줄(kind 3 · 시작 = 끝 = 0 · `data`가 객체).
#![allow(dead_code)]
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Write;

/// 한 해(분) — 장면 안의 어림값(달력 셈이 아니다).
pub const Y: i64 = 525_600;
/// 장면의 '오늘'(진행 중 띠의 끝) — P3 정답지가 고정한 시각 2026-10-15T03:00Z의 분. 기기 시계를 읽지 않아 장면이 늘 같다.
pub const NOW: i64 = 29_867_220;
/// 소속 펼치기가 가리는 `a`의 칸(`cells`에서의 자리) · 일반 항목(`items`에서의 자리).
pub const HIDDEN_CELL: i64 = 2;
pub const HIDDEN_ITEM: i64 = 0;
/// 판(`view:a1`)이 가리는 `ta`의 칸(`cells`에서의 자리 — `a/ta-1`의 둘째 임금) · 일반 항목(`items`에서의 자리 — 구역 21 관계선).
/// 내보내기 `boards.mjs`의 꼴: 판 변형은 원래 트랙의 칸 · 항목을 가리고, 칸의 변형 판은 판 변형 열쇠를 달고 원래 트랙의 띠에 딸린다.
pub const BOARD_CELL: i64 = 1;
pub const BOARD_ITEM: i64 = 2;

/// 그 해의 첫 분(1970년이 0 — 어림값).
pub fn yr(year: i64) -> i64 {
    (year - 1970) * Y
}

/// 자료집 하나의 글자 id · 이름 · 판.
struct Def {
    id: &'static str,
    name: &'static str,
    version: &'static str,
}

fn def(key: &str) -> Def {
    match key {
        "a" => Def { id: "a", name: "가 기록집", version: "1.0.0" },
        "a@2" => Def { id: "a", name: "가 기록집", version: "2.0.0" },
        "b" => Def { id: "b", name: "나 기록집", version: "1.0.0" },
        "c" => Def { id: "c", name: "다 기록집", version: "1.0.0" },
        "big" => Def { id: "big", name: "큰 장면", version: "1.0.0" },
        other => panic!("장면에 없는 자료집입니다: {other}"),
    }
}

/// 규격 2 전용 팩(머리 20바이트 + 지문 32바이트 + zlib 본문 — `tests/import.rs`의 `htpack()`과 같은 꼴).
pub fn htpack(raw: &Value) -> Vec<u8> {
    seal(1, raw)
}

/// 메이커의 아카이브 배치(.htlayout — 팩 파일 종류 3)로 싼 배치 JSON(과제 7a — 명령이 `.htlayout`을 받는 길).
pub fn htlayout(plan: &Value) -> Vec<u8> {
    seal(3, plan)
}

/// 팩 파일 규격 2로 싼다(`kind` — 1 DLC · 3 아카이브 배치).
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

/// 그 조합의 원본 — (자료집 글자 id, .htpack 바이트)를 배치의 `packs[]` 차례대로. `big`(과제 7c의 큰 배치)도 받는다.
pub fn packs_of(packs: &[&str]) -> Vec<(String, Vec<u8>)> {
    packs.iter().map(|key| {
        let d = def(key);
        (d.id.to_owned(), htpack(&json!({"format":"history-timeline-dlc","id":d.id,"name":d.name,"version":d.version})))
    }).collect()
}

/// 새 열을 모두 갖춘 줄(`tests/import.rs`의 `row()`와 같은 꼴).
fn row() -> Value {
    json!({"height":126,"bandTop":19,"bandH":107,"dynTop":-1,"leadTop":23,"cabTop":46,"textTop":66,"lines":2,"railTop":108,"organTop":-1,
        "kind":0,"groupStart":0,"scopePad":0,"phase":0,"rank":0,"cats":[0],"fig":0,"figWide":0,"dep":0,"zones":0,"hem":0})
}

/// 그 변형에서만 있는 줄.
fn row_in(variant: &str) -> Value {
    let mut r = row();
    r["variant"] = json!(variant);
    r
}

fn band(uid: &str, track: usize, row: i64, start: i64, end: i64, color: u32, name: &str) -> Value {
    json!({"uid":uid,"track":track,"row":row,"start":start,"end":end,"fuzzy":0,"color":color,"name":name,"look":0,"tag":"","sub":0})
}

fn event(uid: &str, track: usize, row: i64, start: i64, band: &str, title: &str) -> Value {
    json!({"uid":uid,"track":track,"row":row,"start":start,"end":start,"importance":1,"title":title,"body":"","look":0,"label":"","rail":0,"band":band})
}

/// 일반 항목 하나(lod −1 = 기간에서 셈).
fn item(section: i64, track: usize, rows: (i64, i64), span: (i64, i64), reference: &str, name: &str, abcd: [i64; 4], text2: &str) -> Value {
    json!({"section":section,"track":track,"row":rows.0,"row2":rows.1,"start":span.0,"end":span.1,"lod":-1,"ref":reference,"name":name,"color":0x8a8f96,
        "a":abcd[0],"b":abcd[1],"c":abcd[2],"d":abcd[3],"text2":text2})
}

/// 항목 기록 하나 — `body`는 정규화된 항목 그대로(글로 싣는다).
fn entity(uid: &str, kind: &str, pack: usize, body: Value) -> Value {
    json!({"uid":uid,"kind":kind,"pack":pack,"json":body.to_string()})
}

fn label(period: &str, track: usize, row: i64, name: &str, years: &str, color: u32) -> Value {
    json!({"period":period,"track":track,"row":row,"kind":0,"name":name,"years":years,"color":color,"cap":0,"member":0,"lanes":[0]})
}

/// 일반 항목의 띠 번호 칸(`archive_engine::bandref`)에 넣을 값 — 그 uid의 띠를 가리킨다는 표지. `plan()`이 끝에서
/// 내보내기와 같이 '`periods` 배열에서의 자리 + 1'(없으면 0)로 바꾼다(조합마다 자리가 달라 띠를 다 모은 뒤에 셈한다).
fn band_no(uid: &str) -> Value {
    json!(format!("{BAND_NO}{uid}"))
}
const BAND_NO: &str = "띠 번호:";

/// 항목들의 띠 번호 표지를 그 배치의 띠 번호로 바꾼다.
fn resolve_band_numbers(items: &mut [Value], periods: &[Value]) {
    for it in items.iter_mut() {
        for key in ["a", "b", "c", "d"] {
            if let Some(uid) = it[key].as_str().and_then(|v| v.strip_prefix(BAND_NO)).map(str::to_owned) {
                it[key] = json!(periods.iter().position(|p| p["uid"] == uid.as_str()).map_or(0, |i| i + 1));
            }
        }
    }
}

/// 그 변형에서만 있는 것으로 표시한다.
fn only_in(mut v: Value, variant: &str) -> Value {
    v["variant"] = json!(variant);
    v
}

/// 형식 4의 뜻(`form` — 계약 1-1의 비트: 0 ~ 4 종류 + 1 · 5 ~ 9 관계 · 10 ~ 12 정통성 + 1 · 13 ~ 15 중요도 + 1)이 있는 띠. 나머지 띠는 열쇠가 없다(0).
/// `a/ta-1` 국가 · 정통 · 중요도 2 · `a/ta-2` 제후국 · 봉국 · `b/tb-1` 국가 · 중요도 0 · `c/tc-2` 도시.
pub const FORMS: [(&str, i64); 4] = [("a/ta-1", 1 | 1 << 10 | 3 << 13), ("a/ta-2", 3 | 2 << 5), ("b/tb-1", 1 | 1 << 13), ("c/tc-2", 4)];

/// 그 조합의 문화권 단위 줄(`sphereLines` — 원소는 내보내기 `persons.mjs` · `axis.mjs`의 꼴). 차례는 손으로 정한 것(사람 띠 먼저 — 저장소는 어느 차례든
/// 배치 차례 그대로 적는다는 것을 본다). 진짜 내보내기는 모듈 차례대로 문화권 시대 · 주기 줄(axis)이 먼저다(`tests/lay_m_persons.rs`). `pb` · `pc`는 b · c의 자료집 순번.
fn sphere_lines(pb: Option<usize>, pc: Option<usize>) -> Vec<Value> {
    let crowns = |list: &[(&str, i64)]| -> String {
        json!(list.iter().map(|(uid, cell)| json!({"uid":uid,"cell":cell})).collect::<Vec<_>>()).to_string()
    };
    let mut out = vec![json!({"kind":1,"sphere":"s-east","start":yr(1000),"end":yr(1800),"name":"가람 사람","uid":"a/fig-1","color":0,
        "data":crowns(&[("a/ta-1", 0), ("a/ta-2", 3)]),"pack":0})];
    if let Some(p) = pb {
        out.push(json!({"kind":1,"sphere":"s-east","start":yr(1200),"end":yr(1700),"name":"나루 임금","uid":"b/fig-2","color":0,
            "data":crowns(&[("a/ta-1", 1), ("b/ta-late", 5)]),"pack":p}));
    }
    out.push(json!({"kind":2,"sphere":"s-east","start":yr(1000),"end":yr(1500) - 1,"name":"동녘 이른 시대","uid":"a/ep-east","color":0xc8b193,"data":"","pack":0}));
    if let Some(p) = pc {
        out.push(json!({"kind":3,"sphere":"s-east","start":0,"end":0,"name":"다 간지","uid":"","color":0,
            "data":{"names":["갑", "을", "병"],"start":4,"label":"다 간지"},"pack":p}));
    }
    out
}

/// 자료집 조합(`["a"]` · `["a","b","c"]` · `["a@2","c"]` …)의 배치 JSON 3판. 첫째는 `a` 또는 `a@2`, 나머지는 `b` · `c`(차례는 자유 — 배치의 `packs[]` 차례).
pub fn plan(packs: &[&str]) -> Value {
    assert!(matches!(packs.first(), Some(&"a") | Some(&"a@2")), "장면의 기본 자료집은 a 또는 a@2입니다: {packs:?}");
    for (i, key) in packs.iter().enumerate().skip(1) {
        assert!(matches!(*key, "b" | "c") && !packs[..i].contains(key), "장면에 없거나 겹친 자료집입니다: {packs:?}");
    }
    let second = packs[0] == "a@2";
    let pack_at = |key: &str| packs.iter().position(|p| *p == key);
    let (pb, pc) = (pack_at("b"), pack_at("c"));
    // 트랙 순번: ta = 0, 그 뒤 자료집 차례대로 tb · tc, 판 트랙은 맨 뒤.
    let mut order = vec!["ta"];
    for key in &packs[1..] {
        order.push(if *key == "b" { "tb" } else { "tc" });
    }
    let track_at = |key: &str| order.iter().position(|t| *t == key).unwrap();
    let board = order.len();
    // ta의 줄: a의 넷 · (b의 하나) · 소속 펼치기의 하나.
    let host_row: i64 = if pb.is_some() { 5 } else { 4 };
    const HOST: &str = "host:a/ta-host";

    let (mut tracks, mut periods, mut cells, mut events, mut items) = (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let (mut entities, mut labels, mut variants, mut axis) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());

    // ---- a ----
    let first_color: u32 = if second { 0xc58fa0 } else { 0xa0bcc5 };
    let mut ta_rows = vec![row(), row(), row(), row()];
    if pb.is_some() {
        ta_rows.push(row());
    }
    ta_rows.push(row_in(HOST));
    tracks.push(json!({"key":"ta","name":"가 나라","color":0xa0bcc5,"dynasty":1,"leader":1,"cabinet":1,"organ":0,"railLevels":3,"sphere":"s-east","pack":0,
        "rows":ta_rows,"groups":[{"depth":0,"first":0,"count":4,"name":"윗물 겨레","color":0xbcd8c1,"kind":0}]}));
    let mut first = band("a/ta-1", 0, 0, yr(1000), yr(1400), first_color, "가 첫 나라");
    first["fuzzy"] = json!(1); // 시작 미정
    periods.push(first);
    let mut host = band("a/ta-host", 0, 1, yr(1100), yr(1700), 0x9dbea8, "가 큰 나라");
    host["tag"] = json!("왕국");
    periods.push(host);
    periods.push(band("a/ta-2", 0, 2, yr(1300), yr(1800), 0xd7c18e, "가 둘째 나라"));
    periods.push(band("a/ta-now", 0, 3, yr(1850), NOW, 0xbbacc8, "가 오늘 나라")); // 진행 중 — 끝이 '오늘'
    periods.push(only_in(band("a/ta-member", 0, host_row, yr(1150), yr(1450), 0xb6c398, "가 딸린 나라"), HOST));
    // 칸 — 자리 2(큰 내각)를 소속 펼치기가 가리고 자리 6의 변형 판이 대신 나온다.
    cells.push(json!({"period":"a/ta-1","kind":1,"lane":0,"start":yr(1000),"end":yr(1200) - 1,"name":"첫 임금"}));
    cells.push(json!({"period":"a/ta-1","kind":1,"lane":0,"start":yr(1200),"end":yr(1400),"name":"둘째 임금"}));
    cells.push(json!({"period":"a/ta-host","kind":2,"lane":1,"start":yr(1100),"end":yr(1300),"name":"큰 내각","style":0,"color":0}));
    cells.push(json!({"period":"a/ta-host","kind":0,"lane":0,"start":yr(1100),"end":yr(1700),"name":"큰 왕조"}));
    cells.push(json!({"period":"a/ta-now","kind":1,"lane":0,"start":yr(1850),"end":NOW,"name":"오늘 임금"}));
    cells.push(only_in(json!({"period":"a/ta-member","kind":1,"lane":0,"start":yr(1150),"end":yr(1450),"name":"딸린 임금"}), HOST));
    cells.push(only_in(json!({"period":"a/ta-host","kind":2,"lane":1,"start":yr(1100),"end":yr(1300),"name":"큰 내각","style":4,"color":0xd1a9b9}), HOST));
    // 사건 300건: 앞 100건은 줄 0의 1250년에 하루씩 몰아(요약 단계의 알약), 나머지는 1000 ~ 1950년에 고루. 마지막 건은 소속 펼치기가 옮긴다.
    let a_bands = [("a/ta-1", 1000, 1400), ("a/ta-host", 1100, 1700), ("a/ta-2", 1300, 1800), ("a/ta-now", 1850, 2026)];
    for i in 0..300i64 {
        let (uid, row, year, start) = if i == 299 {
            ("a/e-move".to_owned(), 1, 1200, yr(1200) + 40 * 1440)
        } else if i < 100 {
            (format!("a/e{i}"), 0, 1250, yr(1250) + i * 1440)
        } else {
            let year = 1000 + (i * 37) % 950;
            (format!("a/e{i}"), i % 4, year, yr(year) + (i % 12) * 30 * 1440)
        };
        let (host_uid, from, to) = a_bands[row as usize];
        let inside = from <= year && year <= to;
        let mut e = event(&uid, 0, row, start, if inside { host_uid } else { "" }, &if i == 0 { "가람 나루 열기".to_owned() } else { format!("가 사건 {i}") });
        e["importance"] = json!(1 + i64::from(i % 3 == 0) + i64::from(i % 9 == 0));
        e["look"] = json!(i % 3); // 분류 번호
        if i % 25 == 5 {
            e["end"] = json!(start + 3 * Y); // 긴 기간 막대
        }
        if i % 4 == 0 {
            e["label"] = json!(format!("{year}년"));
        }
        events.push(e);
    }
    events.push(only_in(event("a/e-only", 0, host_row, yr(1300), "a/ta-member", "펼칠 때만 보이는 일"), HOST));
    // 일반 항목 — 자리 0(속국 이름표)을 소속 펼치기가 가리고 자리 4의 변형 판이 대신 나온다.
    // 띠 번호 칸(bandref): 구역 16의 d = 속국 띠 · 21의 b = 후대 띠 — 같은 트랙의 띠를 가리킨다.
    let mut hang = item(16, 0, (1, 1), (yr(1150), yr(1450)), "a/ta-host", "가 딸린 나라", [0, 0, 0, 0], "a/ta-member");
    hang["d"] = band_no("a/ta-member");
    items.push(hang);
    items.push(item(19, 0, (0, 0), (yr(1000), yr(1020)), "a/ta-1", "", [0, 1, 0, 0], ""));
    let mut line = item(21, 0, (0, 2), (yr(1300), yr(1400)), "a/ta-1", "가 첫 나라 → 가 둘째 나라", [16, 0, 0, 0], "a/ta-2");
    line["lod"] = json!(14);
    line["b"] = band_no("a/ta-2");
    items.push(line);
    items.push(item(20, 0, (3, 3), (yr(1850), NOW), "a/ta-now", "가 오늘 나라", [4, 0, 0, 0], "")); // 4 = 진행 중
    let mut hang2 = item(16, 0, (1, 1), (yr(1150), yr(1450)), "a/ta-host", "가 딸린 나라", [0, 1, 0, 0], "a/ta-member");
    hang2["d"] = band_no("a/ta-member");
    items.push(only_in(hang2, HOST));
    // 날짜 칸: 공통 줄 하나 · ta의 연호 하나.
    axis.push(json!({"kind":1,"track":-1,"lane":0,"start":yr(1000),"end":yr(1950),"name":"이른 시대","color":0xc8b193,"style":0,"strip":0,"seq":0,"pack":0}));
    axis.push(json!({"kind":2,"track":0,"lane":1,"start":yr(1100),"end":yr(1300),"name":"가 연호","color":0x9dbea8,"style":1,"strip":7,"seq":0,"pack":0}));
    // 줄 이름.
    labels.push(label("a/ta-1", 0, 0, "가 첫 나라", "1000–1400", first_color));
    labels.push(label("a/ta-host", 0, 1, "가 큰 나라", "1100–1700", 0x9dbea8));
    labels.push(label("a/ta-2", 0, 2, "가 둘째 나라", "1300–1800", 0xd7c18e));
    labels.push(label("a/ta-now", 0, 3, "가 오늘 나라", "1850–", 0xbbacc8));
    let mut member = only_in(label("a/ta-member", 0, host_row, "가 딸린 나라", "1150–1450", 0xb6c398), HOST);
    member["member"] = json!(1);
    labels.push(member);
    // 항목 기록: 트랙 있는 띠 · 트랙 없는 인물 · 가문 둘 · 단체 둘(가문 · 단체는 uid 차례와 거꾸로 넣는다).
    for (uid, name) in [("a/ta-1", "가 첫 나라"), ("a/ta-host", "가 큰 나라"), ("a/ta-2", "가 둘째 나라"), ("a/ta-member", "가 딸린 나라")] {
        entities.push(entity(uid, "period", 0, json!({"uid":uid,"name":name,"track":"ta"})));
    }
    entities.push(entity("a/ta-now", "period", 0, json!({"uid":"a/ta-now","name":"가 오늘 나라","track":"ta","ongoing":true})));
    entities.push(entity("a/fig-1", "figure", 0, json!({"uid":"a/fig-1","name":"가람 사람"})));
    entities.push(entity("house:a-zelkova", "house", 0, json!({"name":"느티 가문","surname":"느"})));
    entities.push(entity("house:a-bamboo", "house", 0, json!({"name":"대숲 가문","surname":"대"})));
    entities.push(entity("a/grp-2", "group", 0, json!({"uid":"a/grp-2","name":"늦은 모임","x_find":{"sub":"정당","span":[yr(1500), yr(1600)],"row":"a/ta-2"}})));
    entities.push(entity("a/grp-1", "group", 0, json!({"uid":"a/grp-1","name":"이른 모임","x_find":{"sub":"정당","span":[yr(1300), yr(1400)],"row":"a/ta-host"}})));
    // 소속 펼치기: 딸린 나라의 줄을 큰 나라 아래에 쌓고, 큰 나라 줄의 사건 하나를 옮기고, 칸 하나 · 항목 하나를 변형 판으로 바꾼다.
    variants.push(json!({"key":HOST,"kind":1,"track":0,"band":"a/ta-host","uid":"","name":"가 큰 나라 펼치기","notes":"",
        "rows":[{"track":0,"row":host_row,"after":1,"ord":0,"new":1,"scopePad":0,"groupStart":0}],
        "moves":[{"kind":2,"ref":"a/e-move","track":0,"row":host_row}],
        "hides":[{"kind":3,"at":HIDDEN_CELL},{"kind":4,"at":HIDDEN_ITEM}],
        "groups":[{"track":0,"key":"__host:a/ta-host","depth":1,"name":"가 큰 나라 소속","color":0x9dbea8,"kind":2,"rows":[1, host_row]}]}));

    // ---- b · c (배치의 차례대로) ----
    let mut spheres = vec![json!({"id":"s-east","name":"동녘","order":0,"count":1 + usize::from(pc.is_some()),"default":true})];
    for key in &packs[1..] {
        if *key == "b" {
            let (p, t) = (pb.unwrap(), track_at("tb"));
            // ta에 얹는 것: 줄 4의 띠 · 칸 · 사건 셋, a의 첫 줄에 사건 둘.
            periods.push(band("b/ta-late", 0, 4, yr(1500), yr(1700), 0xc8b193, "나 늦은 나라"));
            cells.push(json!({"period":"b/ta-late","kind":1,"lane":0,"start":yr(1500),"end":yr(1700),"name":"늦은 임금"}));
            for i in 0..3 {
                events.push(event(&format!("b/e-ta{i}"), 0, 4, yr(1520 + 50 * i), "b/ta-late", &format!("나 늦은 일 {i}")));
            }
            for i in 0..2 {
                events.push(event(&format!("b/e-on{i}"), 0, 0, yr(1300 + 50 * i), "a/ta-1", &format!("나 얹은 일 {i}")));
            }
            labels.push(label("b/ta-late", 0, 4, "나 늦은 나라", "1500–1700", 0xc8b193));
            // 제 트랙 tb — 600년부터(보는 범위가 넓어진다).
            tracks.push(json!({"key":"tb","name":"나 나라","color":0xbbacc8,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,"sphere":"s-west","pack":p,
                "rows":[row(), row()],"groups":[]}));
            periods.push(band("b/tb-1", t, 0, yr(600), yr(1100), 0xbbacc8, "나 옛 나라"));
            periods.push(band("b/tb-2", t, 1, yr(900), yr(1300), 0xa4b1b7, "나 둘째 나라"));
            cells.push(json!({"period":"b/tb-1","kind":1,"lane":0,"start":yr(600),"end":yr(1100),"name":"옛 임금"}));
            for i in 0..10i64 {
                let (row, uid, from) = if i % 2 == 0 { (0, "b/tb-1", 650) } else { (1, "b/tb-2", 950) };
                events.push(event(&format!("b/e{i}"), t, row, yr(from + 30 * i), uid, &format!("나 사건 {i}")));
            }
            labels.push(label("b/tb-1", t, 0, "나 옛 나라", "600–1100", 0xbbacc8));
            labels.push(label("b/tb-2", t, 1, "나 둘째 나라", "900–1300", 0xa4b1b7));
            entities.push(entity("b/ta-late", "period", p, json!({"uid":"b/ta-late","name":"나 늦은 나라","track":"ta"})));
            entities.push(entity("b/tb-1", "period", p, json!({"uid":"b/tb-1","name":"나 옛 나라","track":"tb"})));
            entities.push(entity("b/tb-2", "period", p, json!({"uid":"b/tb-2","name":"나 둘째 나라","track":"tb"})));
            entities.push(entity("house:b-ferry", "house", p, json!({"name":"나루 가문","surname":"나"}))); // 트랙 없는 기록
            spheres.push(json!({"id":"s-west","name":"서녘","order":1,"count":1,"default":false}));
        } else {
            let (p, t) = (pc.unwrap(), track_at("tc"));
            tracks.push(json!({"key":"tc","name":"다 나라","color":0xd7c18e,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,"sphere":"s-east","pack":p,
                "rows":[row(), row()],"groups":[{"depth":0,"first":0,"count":2,"name":"다 겨레","color":0xd7c18e,"kind":0}]}));
            periods.push(band("c/tc-1", t, 0, yr(1400), yr(1600), 0xd7c18e, "다 첫 나라"));
            periods.push(band("c/tc-2", t, 1, yr(1550), yr(1750), 0xa0bcc5, "다 둘째 나라"));
            cells.push(json!({"period":"c/tc-1","kind":1,"lane":0,"start":yr(1400),"end":yr(1600),"name":"다 임금"}));
            for i in 0..5i64 {
                // 든 띠의 기간 안에: 줄 0(c/tc-1 · 1400 ~ 1600)은 1450년부터, 줄 1(c/tc-2 · 1550 ~ 1750)은 1560년부터.
                let (row, uid, from) = if i % 2 == 0 { (0, "c/tc-1", 1450) } else { (1, "c/tc-2", 1560) };
                events.push(event(&format!("c/e{i}"), t, row, yr(from + 20 * i), uid, &format!("다 사건 {i}")));
            }
            // 남의 트랙 띠를 가리키는 일반 항목 둘(구역 60 — 장면 전용). pack은 가리키는 띠가 없을 때의 자료집이다.
            let mut to_a = item(60, t, (0, 0), (yr(1400), yr(1500)), "a/ta-2", "다 → 가 둘째 나라", [0, 0, 0, 0], "c/tc-1");
            to_a["pack"] = json!(p);
            items.push(to_a);
            let mut to_b = item(60, t, (1, 1), (yr(1550), yr(1650)), "b/ta-late", "다 → 나 늦은 나라", [0, 0, 0, 0], "c/tc-2");
            to_b["pack"] = json!(p);
            items.push(to_b);
            // 띠 번호 칸이 남의 트랙 띠를 가리키는 항목 둘: 구역 47(뒤 장의 탭)의 d = 상국 띠 `a/ta-2` ·
            // 구역 49(동군연합 끝)의 b = 짝 띠 `b/ta-late`(b가 없으면 0 · 그 자리는 b · c의 차례에 따라 다르다).
            let mut tab = item(47, t, (0, 0), (yr(1400), yr(1600)), "c/tc-1", "가 둘째 나라", [0, 0, 0, 0], "a/ta-2");
            tab["d"] = band_no("a/ta-2");
            items.push(tab);
            let mut union = item(49, t, (1, 1), (yr(1600), yr(1650)), "c/tc-2", "동군연합 · 다 둘째 나라 · 나 늦은 나라", [0, 0, 0, 0],
                "c/tc-2|leader:0|b/ta-late|leader:0");
            union["b"] = band_no("b/ta-late");
            items.push(union);
            axis.push(json!({"kind":2,"track":t,"lane":0,"start":yr(1400),"end":yr(1500),"name":"다 연호","color":0xd7c18e,"style":0,"strip":3,"seq":0,"pack":p}));
            labels.push(label("c/tc-1", t, 0, "다 첫 나라", "1400–1600", 0xd7c18e));
            labels.push(label("c/tc-2", t, 1, "다 둘째 나라", "1550–1750", 0xa0bcc5));
            entities.push(entity("c/tc-1", "period", p, json!({"uid":"c/tc-1","name":"다 첫 나라","track":"tc"})));
            entities.push(entity("c/tc-2", "period", p, json!({"uid":"c/tc-2","name":"다 둘째 나라","track":"tc"})));
            entities.push(entity("c/grp-1", "group", p, json!({"uid":"c/grp-1","name":"다 모임","x_find":{"sub":"정당","span":[yr(1450), yr(1550)],"row":"c/tc-1"}})));
            // 대범위 모아 보기: tc의 첫 띠가 ta의 줄 3으로 이사하고, 그 변형의 묶음도 ta의 줄 3을 가리킨다.
            variants.push(json!({"key":"scope:c/sc-1","kind":2,"track":t,"band":"","uid":"c/sc-1","name":"다 모아 보기","notes":"",
                "rows":[{"track":t,"row":0,"after":-1,"ord":0,"new":0,"scopePad":6,"groupStart":1}],
                "moves":[{"kind":1,"ref":"c/tc-1","track":0,"row":3}],
                "hides":[],
                "groups":[{"track":0,"key":"__scope:c/sc-1","depth":0,"name":"다 모아 보기","color":0xd7c18e,"kind":2,"rows":[3]}]}));
        }
    }

    // ---- 판(겉 열쇠 boards — a의 것) — 판 트랙은 옛 트랙 뒤에 붙는다 ----
    const VIEW: &str = "view:a1";
    let mut board_line = only_in(item(21, board, (0, 1), (yr(1300), yr(1400)), "a/ta-1", "가 첫 나라 → 가 둘째 나라", [16, 0, 0, 0], "a/ta-2"), VIEW);
    board_line["b"] = band_no("a/ta-2");
    let mut board_items = vec![board_line];
    // 판을 켜면 ta의 관계선(자리 BOARD_ITEM)은 위의 판 트랙 관계선으로 바뀌고(구역 · ref · 기간 · 이름 · a ~ d · text2가 같고 트랙 · 줄 ·
    // 변형만 다르다), ta 띠 a/ta-1의 둘째 임금(자리 BOARD_CELL)은 모양 · 색만 바뀐 변형 판으로(단은 그대로 — `boards.mjs`의 `cellSameOf`).
    // 변형 판 칸은 판 변형 열쇠를 달고 ta의 띠에 딸린다(내보내기 `boards.mjs`의 칸 · 그릴 것 견줌과 같은 꼴).
    let board_cells = vec![only_in(json!({"period":"a/ta-1","kind":1,"lane":0,"start":yr(1200),"end":yr(1400),"name":"둘째 임금","style":4,"color":0xd1a9b9}), VIEW)];
    // 형식 4의 뜻(스키마 4) — 조합과 상관없이 그 띠에 늘 같은 값.
    for p in periods.iter_mut() {
        if let Some((_, form)) = FORMS.iter().find(|(uid, _)| p["uid"] == *uid) {
            p["form"] = json!(form);
        }
    }
    // 띠 번호 칸을 이 배치의 띠 자리로 — 띠를 다 모은 뒤에. 판 항목도 기본 배치의 자리다(판에는 제 띠가 없다 — 내보내기 `boards.mjs`와 같다).
    resolve_band_numbers(&mut items, &periods);
    resolve_band_numbers(&mut board_items, &periods);
    let boards = json!({
        "tracks":[{"key":"__board:view:a1","name":"가 모아 보기","color":0xd7c18e,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,
            "rows":[row_in(VIEW), row_in(VIEW)],"groups":[],"pack":0}],
        "variants":[{"key":VIEW,"kind":3,"track":board,"band":"","uid":VIEW,"name":"가 모아 보기","notes":"",
            "rows":[
                {"track":board,"row":0,"after":-1,"ord":0,"new":1,"scopePad":16,"groupStart":1},
                {"track":board,"row":1,"after":0,"ord":0,"new":1,"scopePad":0,"groupStart":1},
                {"track":0,"row":2,"after":-2,"ord":0,"new":0,"scopePad":0,"groupStart":0,"toTrack":board,"to":0},
                {"track":0,"row":0,"after":-2,"ord":0,"new":0,"scopePad":0,"groupStart":0,"toTrack":board,"to":1}
            ],
            "moves":[{"kind":1,"ref":"a/ta-2","track":board,"row":0},{"kind":1,"ref":"a/ta-1","track":board,"row":1}],
            "hides":[{"kind":3,"at":BOARD_CELL},{"kind":4,"at":BOARD_ITEM}],
            "groups":[{"track":board,"key":"__from:ta#2","depth":0,"name":"가 나라","color":0xa0bcc5,"kind":3,"rows":[0, 1]}]}],
        "cells":board_cells,
        "items":board_items,
        "entities":[entity("board:view:a1", "board", 0, json!({"key":VIEW,"name":"가 모아 보기","present":2}))]
    });

    // 사건은 진짜 내보내기(`export/events.mjs`의 `tl.tracks.forEach`)처럼 트랙 차례로 묶어 낸다(판정 R25) — 트랙 안 차례는 그대로다
    // (안정 정렬 · 지문은 트랙마다 실린 차례만 보므로 그대로). 그래야 통째 짓기에서 (트랙 차례, 트랙 안 차례) 차례 = 사건 번호 차례다(판정 R23).
    events.sort_by_key(|e| e["track"].as_i64().unwrap_or(0));
    let declared: Vec<Value> = packs.iter().map(|key| {
        let d = def(key);
        json!({"id":d.id,"name":d.name,"version":d.version,"category":""})
    }).collect();
    json!({
        "name":"같음의 눈 장면",
        "packs":declared,
        "categories":[{"key":"govern","name":"다스림","color":0x8f7fb0},{"key":"war","name":"싸움","color":0xb07f7f},{"key":"lore","name":"이야기","color":0x9a6f8a}],
        "tracks":tracks,
        "epochs":[{"start":yr(1000),"end":yr(1500) - 1,"color":0xc8b193,"name":"이른 시대"},{"start":yr(1500),"end":yr(1950),"color":0x9dbea8,"name":"늦은 시대"}],
        "axis":axis,
        "periods":periods,
        "cells":cells,
        "events":events,
        "items":items,
        "entities":entities,
        "rowLabels":labels,
        "variants":variants,
        "spheres":spheres,
        "sphereLines":sphere_lines(pb, pc),
        "boards":boards
    })
}

/// 과제 7c의 가상 큰 배치 — 자료집 하나(`big` — 원본은 `packs_of(&["big"])`) · 트랙 `tracks`개(열쇠 `big-t<n>`) · 트랙마다 줄 `rows`개 ·
/// 줄마다 띠 하나(1000 ~ 1900년) · 사건 `events`건을 줄마다 고루(점 사건 · 꼭 필요한 열만 — 100만 건에서도 배치가 가볍게).
/// 사건은 진짜 내보내기처럼 트랙 · 줄 차례로 묶여 나간다(사건 `i`는 줄 `i × 줄 수 / 사건 수` — 번호 · uid가 트랙마다 이어진다). 줄마다 돌려 가며
/// 나눠 주면 한 트랙의 사건이 저장소 전체에 1,000번째마다 흩어져, 트랙 하나를 고쳐 쓸 때 사건마다 다른 쪽을 건드려 큰 저장소일수록 느려 보였다
/// (과제 7c — 진짜 배치에는 없는 꼴).
pub fn big(tracks: usize, rows: usize, events: usize) -> Value {
    assert!(tracks > 0 && rows > 0, "큰 배치에는 트랙과 줄이 있어야 합니다");
    let all = tracks * rows;
    let track_list: Vec<Value> = (0..tracks).map(|t| {
        json!({"key":format!("big-t{t}"),"name":format!("큰 트랙 {t}"),"color":0xa0bcc5,"dynasty":0,"leader":1,"cabinet":0,"organ":0,"railLevels":2,"pack":0,
            "rows":vec![row(); rows],"groups":[]})
    }).collect();
    let mut periods = Vec::with_capacity(all);
    for t in 0..tracks {
        for r in 0..rows {
            periods.push(band(&format!("big/t{t}-r{r}"), t, r as i64, yr(1000), yr(1900), 0x9dbea8, &format!("큰 나라 {t}-{r}")));
        }
    }
    let span_days = 900 * 365;
    let event_list: Vec<Value> = (0..events).map(|i| {
        let at = i * all / events;
        let (t, r) = (at / rows, at % rows);
        let start = yr(1000) + ((i as i64).wrapping_mul(7919) % span_days) * 1440;
        json!({"uid":format!("big/e{i}"),"track":t,"row":r,"start":start,"title":format!("큰 사건 {i}"),"band":format!("big/t{t}-r{r}")})
    }).collect();
    json!({
        "name":"큰 장면",
        "packs":[{"id":"big","name":"큰 장면","version":"1.0.0","category":""}],
        "categories":[{"key":"govern","name":"다스림","color":0x8f7fb0}],
        "tracks":track_list,
        "epochs":[], "axis":[], "periods":periods, "cells":[], "events":event_list, "items":[], "entities":[], "rowLabels":[], "variants":[]
    })
}

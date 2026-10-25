//! 한 벌 P3 과제 X(판정 R28 · R29 · R25) — 합성 정답지 자료 `synth-lay` · `synth-lens`(`prototype/fixtures/oracle/` — 가상 이름)가
//! 다섯 모듈 갈래 보고(`.superpowers/sdd/계획-한벌-P3-Rust배치/task-lane{A..E}-report.md`)와 그 검토가 '정답지 자료가 닿지 않는다'고 적은 갈래를 **실제로 밟는지**
//! 센다. 표지는 **Node가 뽑은 정답지 파일만** 읽어 센다(`upto-lens.json` · `norm-0.json` · `notes.json` — Rust 배치 결과에 기대지 않음).
//! Rust가 그 갈래에서 Node와 같은지는 늘 하던 정답지 견줌(`lay_out` · `lay_m_*` · `lay_model` · `lay_rows` …)이 새 자료로 저절로 본다 — 이 파일은 '닿았다'만 지킨다.
//! 표지 이름은 갈래 보고의 이름 그대로(A-1 … · 구역 · 비트) — 새 자료(`NEW`)에서 표지마다 ≥ 1이어야 한다. 정답지: `node prototype/scripts/layout-oracle.mjs`.
//!
//! 덧붙여(출력에 실리지 않아 늘 하던 견줌이 못 보는 값):
//! * [`boards_dropped_notes_match_node`] — 집합 보기에서 판 하나가 오류로 빠진 목록과 그 까닭(`notes.집합보기.뺀판` — 정답지 `notes.json`)이 Node와 같다(판정 R29).
//! * [`lens_on_rows_match_node`] — 렌즈 켬 배치(lens.mjs ② — `themeLens`를 켜고 모든 트랙을 다시 배치)의 트랙마다 지도자 자리 · 줄 높이가 Node와 같다(판정 R25 선택 5 —
//!   정답지 `lens-on.json`).
//!
//! **닿을 수 없음**(원본 줄로 판단 — 표지를 세지 않는다. 고쳐 쓰면 이 목록부터):
//! * strips 기관 단 없음(`organTop < 0` — strips.mjs 205줄): 기관 칸의 주인은 `_layoutTrack`이 기관 단을 줄 때와 같은 길(숨은 띠 → `_host`)로 고르고,
//!   그 줄은 기관이 있으면 늘 기관 단을 받는다(tracks.mjs `organTop` — 줄의 `organH`) — 내보내기에서 생길 수 없음(갈래 A 검토).
//! * metro '~'(`endY` 없는 도읍 — metro.mjs 61줄 `ev == null`): `HT.resolveCapitals`(core.js)가 모델에서 도읍 칸의 `endY`를 늘 채운다(갈래 C 8절 정정).
//! * figures 구역 38 `ref=''`(figures.mjs 120줄): 인물 막대의 띠 `x.band`는 숨지 않고 · 덧그림 · 바탕 문화가 아니며 줄이 있는 띠뿐이고(timeline.js 3187 ~ 3191줄),
//!   bands.mjs(33 ~ 46줄)는 그런 띠를 모두 `bandOf`에 싣는다. REPLAY의 `bandOf`도 변형은 결과 띠 전부(variants.mjs 143 ~ 155줄 final) · 판은 기본 출력 전부(boards.mjs 112 ~ 124 · 494줄 baseBand)라 비지 않는다.
//! * links 구역 21 `b = 0`(links.mjs 159줄 `idOf(p.uid)`): 승계선의 뒤 띠는 접힘 · 숨음 · 덧그림이 아니고 줄이 있다(115 ~ 125줄). 바탕 문화면 `_row`가 깔린 첫 줄이고
//!   (timeline.js 3110 ~ 3114줄) bands.mjs가 그 첫 줄의 것을 `bandOf`에 싣는다 — 늘 0이 아니다.
//! * labels 민족 딱지의 **기본 판**(labels.mjs `rowChip`): 기본 배치의 줄은 민족 나무의 마디마다 그 마디의 정권으로만 짓고(timeline.js 2900 ~ 2917 · 3020 ~ 3030줄)
//!   덮개는 그 줄을 덮는 가장 깊은 이름 있는 묶음이라 늘 같은 민족이다. 다른 민족이 섞이는 줄(펼친 소속 · 켠 대범위)은 변형에만 있어 **변형 판**(`chip` · `chipOn`)으로 닿는다 — 아래 표지.
//! * variants '그 변형에서만 생기는 사건'(variants.mjs 351 ~ 355줄): 트랙의 사건은 `setData`가 자리(placements)마다 한 번 놓고(timeline.js 1453 ~ 1458줄)
//!   `relayout`(124 ~ 130줄)은 줄만 다시 배정한다 — REPLAY의 events가 내는 uid 집합이 기본과 같다.
//! * 계보 뼈대의 '찾지 못한 마디'(비트 4 — core.js 7291줄): 뼈대의 마디는 구성원(가문 · `kinKey`) → 부계의 이름 미상 부모 → 구성원의 자식뿐인데(core.js 7103 ~ 7120줄)
//!   못 찾은 이름의 자리(`missing` — 6474 ~ 6505줄)는 부모 · 가문이 없어(6623 ~ 6656줄) 셋 어디에도 들지 않는다(시조 `founder`로 적어도 `memberNode`가 잇지 않음 — 손으로 확인).
//!
//! **이번 자료에 넣지 않은 것**(닿을 수는 있으나 꼴이 크거나 표지가 출력에 남지 않음 — 보고서의 목록): 지명 uses의 지도 missing · 덩어리 길(벡터가 지킴) ·
//! `kinAtOf`의 칸 표 대신 길 · `rangeOf` 공통 조상 · `cellRefOf` · 사건 `start` null · `catIndex`가 분류를 새로 만드는 길.
mod common;
use archive_engine::lay::{self, ctx, js};
use common::oracle::{assert_same, fixtures, inputs, oracle, oracle_exists, seam_opts, Fixture};
use serde_json::Value;

/// 이 과제가 더한 합성 자료 — 표지마다 여기서 ≥ 1이어야 한다(다른 자료의 수는 참고로만 찍는다).
const NEW: [&str; 2] = ["synth-lay", "synth-lens"];

fn arr(v: &Value) -> &[Value] { v.as_array().map(Vec::as_slice).unwrap_or(&[]) }
/// 수 칸(없거나 수가 아니면 0) — 비트 셈은 i64로.
fn n(v: &Value, k: &str) -> i64 { v.get(k).and_then(Value::as_f64).map_or(0, |x| x as i64) }
fn s<'a>(v: &'a Value, k: &str) -> &'a str { v.get(k).and_then(Value::as_str).unwrap_or("") }
/// JS `!x.variant` — 변형 열쇠가 없거나 빈 글이면 기본 판.
fn base(v: &Value) -> bool { s(v, "variant").is_empty() }
fn truthy(v: &Value) -> bool { !(v.is_null() || v == &Value::Bool(false) || v.as_f64() == Some(0.0) || v.as_str() == Some("")) }
fn body(mut v: Value) -> Value { if let Some(m) = v.as_object_mut() { m.remove("$oracle"); } v }

/// 정답지 한 자료의 표지 수(차례 고정 — 이름, 수).
fn markers(f: &Fixture) -> Vec<(&'static str, usize)> {
    let out = body(oracle(f, "upto-lens.json"));
    let norm = body(oracle(f, "norm-0.json"));
    assert!(oracle_exists(f, "notes.json"), "정답지 {}/notes.json이 없습니다(과제 X가 mods 이음매에 더한 파일) — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs --only={}", f.name, f.name);
    let notes = body(oracle(f, "notes.json"));
    let mut m: Vec<(&'static str, usize)> = Vec::new();
    let mut add = |k: &'static str, c: usize| m.push((k, c));
    let cnt = |list: &[Value], p: &dyn Fn(&Value) -> bool| list.iter().filter(|x| p(x)).count();
    let items: Vec<Value> = arr(&out["items"]).iter().filter(|x| base(x)).cloned().collect();
    let cells: Vec<Value> = arr(&out["cells"]).iter().filter(|x| base(x)).cloned().collect();
    let axis = arr(&out["axis"]);
    let events = arr(&out["events"]);
    let periods: Vec<&Value> = arr(&out["periods"]).iter().filter(|x| base(x)).collect();
    let band_end = |uid: &str| periods.iter().find(|p| s(p, "uid") == uid).map(|p| n(p, "end"));
    // 항목 기록: (uid, kind, json 원문, 풀어 둔 값)
    let ents: Vec<(String, String, String, Value)> = arr(&out["entities"]).iter().map(|e| {
        let text = s(e, "json").to_string();
        let j: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
        (s(e, "uid").to_string(), s(e, "kind").to_string(), text, j)
    }).collect();
    let ent_j = |uid: &str| ents.iter().find(|e| e.0 == uid).map(|e| &e.3);
    let seq_of = |c: &Value| ((n(c, "style") >> 15) & 0xfff) - 1;
    let sec = |i: &Value, k: i64| n(i, "section") == k;

    // ── 갈래 A(task-laneA-report.md 5절 · 검토 바로잡음)
    add("A-1 같은 줄의 시대 구분이 겹침(packLanes 둘째 갈래)", cnt(axis, &|a| n(a, "kind") == 1 && n(a, "lane") >= 1));
    add("A-2 도읍의 시작 미정(style 1)", cnt(axis, &|a| n(a, "kind") == 3 && n(a, "style") & 1 != 0));
    add("A-2 도읍의 이설(style 32)", cnt(axis, &|a| n(a, "kind") == 3 && n(a, "style") & 32 != 0));
    add("A-3 연호의 시작 미정(style 1)", cnt(axis, &|a| n(a, "kind") == 2 && n(a, "style") & 1 != 0));
    add("B-1 '확실' 띠의 연대 폭(구역 19 b = 2)", cnt(&items, &|i| sec(i, 19) && n(i, "b") == 2));
    add("S-1 왕조 항목 자신의 이설(구역 41 a = 0)", cnt(&items, &|i| sec(i, 41) && n(i, "a") == 0));
    add("S-2 기관의 이설(구역 41 a = 3)", cnt(&items, &|i| sec(i, 41) && n(i, "a") == 3));
    add("S-2 같은 주인에 겹친 기관 둘(기관 칸 lane 1)", cnt(&cells, &|c| n(c, "kind") == 3 && n(c, "lane") >= 1));
    {
        // 시작만 적은 이설이 칸의 (풀어 둔) 끝보다 늦거나 끝만 적은 이설이 칸의 시작보다 앞섬 — 그 칸에 구역 41이 서지 않음
        let flipped = |a: &Value, l: &Value, end_y: Option<f64>| {
            let end = l["end"].as_f64().or(end_y);
            match (a["start"].as_f64(), a["end"].as_f64()) {
                (Some(st), None) if !truthy(&a["ongoing"]) => end.is_some_and(|e| st > e),
                (None, Some(en)) => l["start"].as_f64().is_some_and(|st| en < st),
                _ => false,
            }
        };
        add("S-3 이설을 통설로 채우면 뒤집힘(altFlipped — 그리지 않음)", cnt(&cells, &|c| {
            if n(c, "kind") != 1 || n(c, "style") & 128 == 0 { return false; }
            let Some(j) = ent_j(s(c, "period")) else { return false };
            let l = &j["leaders"][seq_of(c) as usize];
            arr(&l["alternatives"]).iter().any(|a| flipped(a, l, j["endY"].as_f64()))
                && !items.iter().any(|i| sec(i, 41) && n(i, "a") == 1 && s(i, "ref") == s(c, "period") && n(i, "d") == seq_of(c) + 1)
        }));
    }
    add("S-4 진행 중 이설(altSpan.ongoing → 끝 = 정권의 끝)", cnt(&items, &|i| {
        // 지도자 칸(a = 1)의 끝 쪽 유령 구분선이 띠 끝에 서고, 그 칸(d = 순번 + 1)에 ongoing 이설이 있음
        sec(i, 41) && n(i, "a") == 1 && n(i, "c") == 1 && band_end(s(i, "ref")) == Some(n(i, "start"))
            && ent_j(s(i, "ref")).is_some_and(|j| arr(&j["leaders"][(n(i, "d") - 1).max(0) as usize]["alternatives"]).iter().any(|a| a["ongoing"] == Value::Bool(true)))
    }));
    add("S-5 전승 칸의 연대 폭(구역 40 c = 1)", cnt(&items, &|i| sec(i, 40) && n(i, "c") == 1));
    add("S-5 끝 연대 폭(구역 40 d = 1)", cnt(&items, &|i| sec(i, 40) && n(i, "d") == 1));
    add("S-6 예속 '점령'(칸 7 style 모양 3)", cnt(&cells, &|c| n(c, "kind") == 7 && (n(c, "style") >> 11) & 7 == 3));
    {
        let (mut outside, mut clipped) = (0, 0);
        for p in &periods {
            let Some(j) = ent_j(s(p, "uid")) else { continue };
            let Some(leaders) = j["leaders"].as_array() else { continue };
            for (i, l) in leaders.iter().enumerate() {
                match cells.iter().find(|c| n(c, "kind") == 1 && s(c, "period") == s(p, "uid") && seq_of(c) == i as i64) {
                    None => outside += 1,
                    Some(c) => if l["end"].as_f64().zip(j["endY"].as_f64()).is_some_and(|(e, ey)| e > ey) && n(c, "end") == n(p, "end") { clipped += 1 },
                }
            }
        }
        add("S-7 칸이 띠 밖(put이 거짓)", outside);
        add("S-7 띠 끝에 잘림", clipped);
    }
    {
        let (mut hidden, mut none) = (0, 0);
        for (uid, kind, _, j) in &ents {
            if kind != "organ" || s(j, "scale") == "zone" { continue; }
            let mine: Vec<&Value> = items.iter().filter(|i| sec(i, 43) && n(i, "a") == 3 && s(i, "text2") == uid).collect();
            let hosts: Vec<&str> = arr(&j["hosts"]).iter().filter_map(|h| h["host"]["$ref"].as_str()).collect();
            // 주인 없음 = 적힌 주인 가운데 띠로 그려지지 않는 것이 있고(기관 · 왕조 …) 칸 수가 주인 수보다 적음 — 주인이 띠인데 기간이 겹치지 않아(strips.mjs `e < s`) 건너뛴 칸은 세지 않는다.
            // 숨은 소속이 주인이면 그 칸은 상위 띠에 서므로(아래 사슬) 칸 수가 모자라지 않는다.
            let band_uids: Vec<&str> = periods.iter().map(|p| s(p, "uid")).collect();
            if mine.len() < hosts.len() && hosts.iter().any(|h| !band_uids.contains(h)) { none += 1; }
            if mine.iter().any(|i| !hosts.contains(&s(i, "ref"))) { hidden += 1; }
        }
        add("기관 주인이 숨은 띠 사슬(host._hidden → _host — 적힌 주인과 다른 띠에 섬)", hidden);
        add("기관 주인 없음(strips 기관_주인없음 — 주인이 띠가 아님)", none);
    }

    // ── 갈래 B(task-laneB-report.md 6절 · 검토 바로잡음)
    let prec = |e: &Value| (n(e, "rail") >> 8) & 7;
    add("사건 날짜 글의 정밀도 'm'(cal.formatT 월)", cnt(events, &|e| prec(e) == 1));
    add("사건 날짜 글의 정밀도 'min'", cnt(events, &|e| prec(e) == 4));
    add("사건 날짜 글의 정밀도 'c2'(반세기)", cnt(events, &|e| prec(e) == 6));
    add("rails 구역 35 b 비트 0(이설에 끝)", cnt(&items, &|i| sec(i, 35) && n(i, "b") & 1 != 0));
    add("rails 구역 35 b 비트 1(통설과 다른 끝)", cnt(&items, &|i| sec(i, 35) && n(i, "b") & 2 != 0));
    add("rails 구역 35 b 비트 2(진행 중 이설)", cnt(&items, &|i| sec(i, 35) && n(i, "b") & 4 != 0));
    add("events rail 비트 6(이설의 다른 끝)", cnt(events, &|e| (n(e, "rail") >> 6) & 1 != 0));
    add("rails 구역 33 c 비트 0(시작 미정 기간 사건)", cnt(&items, &|i| sec(i, 33) && n(i, "c") & 1 != 0));
    add("rails 구역 36 b 비트 0(발효가 끝 뒤인 조약)", cnt(&items, &|i| sec(i, 36) && n(i, "b") & 1 != 0));
    add("hangs 구역 16 c 비트 4(hosts 항목 추정 — 폭 없음)", cnt(&items, &|i| sec(i, 16) && n(i, "b") != 4 && n(i, "c") & 16 != 0));
    add("hangs 구역 16 c 비트 5(hosts 항목 전승 — 폭 없음)", cnt(&items, &|i| sec(i, 16) && n(i, "b") != 4 && n(i, "c") & 32 != 0));
    add("hangs 구역 16 c 비트 6(hosts 항목 연대 폭)", cnt(&items, &|i| sec(i, 16) && n(i, "b") != 4 && n(i, "c") & 64 != 0));
    add("hangs 구역 44(이름표의 모호한 연대)", cnt(&items, &|i| sec(i, 44)));
    add("hangs 구역 47 a = 6(occupied 정권이 제 줄에 · 상국은 띠)", cnt(&items, &|i| sec(i, 47) && n(i, "a") == 6));
    add("hangs 세로 끈 c = 0(안 → 밖으로 옮긴 속국)", cnt(&items, &|i| sec(i, 16) && n(i, "b") == 4 && n(i, "c") == 0));
    add("figures 구역 39 b = 1(활동 끝 이설 경계)", cnt(&items, &|i| sec(i, 39) && n(i, "b") == 1));
    add("links 구역 21 a 비트 12(뒤 띠의 startRange)", cnt(&items, &|i| sec(i, 21) && (n(i, "a") >> 12) & 1 != 0));
    add("links 구역 21 a 비트 13(refuted 정권의 승계)", cnt(&items, &|i| sec(i, 21) && (n(i, "a") >> 13) & 1 != 0));
    add("labels 민족 딱지(변형 판 — chip · chipOn)", cnt(arr(&out["rowLabels"]), &|l| (!base(l) && truthy(&l["chip"])) || truthy(&l["chipOn"])));
    add("labels 원어 mb(BMP 밖 한자 · 𠀀)", cnt(arr(&out["rowLabels"]), &|l| base(l) && arr(&l["orig"]).iter().any(|o| arr(&o["mb"]).iter().any(|cp| cp.as_f64().is_some_and(|x| x > 65535.0)))));

    // ── 갈래 C(task-laneC-report.md 6절 · 8절 정정)
    let metros: Vec<&Value> = ents.iter().filter(|e| e.1 == "period").map(|e| &e.3["x_metro"]).filter(|x| x.is_object()).collect();
    let xfers = |m: &Value| m["xfer"].as_object().map(|o| o.values().cloned().collect::<Vec<_>>()).unwrap_or_default();
    add("metro peers 없음(도읍 있는 정권이 하나뿐인 트랙)", metros.iter().filter(|m| m.get("peers").is_none()).count());
    add("metro xfer all(한 도시를 쓴 다른 정권이 12 넘음)", metros.iter().filter(|m| xfers(m).iter().any(|l| truthy(&l[0]["all"]))).count());
    add("metro 환승의 '미정' 해", metros.iter().filter(|m| xfers(m).iter().any(|l| arr(l).iter().any(|u| s(u, "year") == "미정"))).count());
    add("metro 날짜가 있는 다른 견해(altSpan → formatRange)", metros.iter().filter(|m| m["alts"].as_object().is_some_and(|o| o.values().any(|l| arr(l).iter().any(|t| t.as_str().is_some_and(|t| t.chars().any(|c| c.is_ascii_digit()))))) ).count());
    add("metro 날짜 글(월)이 있는 도읍 칸", metros.iter().filter(|m| arr(&m["when"]).iter().any(|t| t.as_str().is_some_and(|t| t.contains('월')))).count());
    add("metro 기원전에 끝나는 정권(end: BC …)", metros.iter().filter(|m| s(m, "end").starts_with("BC ")).count());
    add("metro 시작 미정 도읍", metros.iter().filter(|m| arr(&m["when"]).iter().any(|t| t.as_str().is_some_and(|t| t.starts_with("미정")))).count());
    let docs: Vec<&Value> = ents.iter().filter(|e| e.1 == "doc").map(|e| &e.3).collect();
    let link_names = |d: &Value| d["links"].as_object().map(|o| o.iter().map(|(k, v)| (k.clone(), s(v, "key").to_string())).collect::<Vec<_>>()).unwrap_or_default();
    add("docs [[단체:이름]] 고리", docs.iter().filter(|d| link_names(d).iter().any(|(k, _)| k.starts_with("단체:") || k.starts_with("단체 :"))).count());
    add("docs [[이름/하위]] 고리(앞부분으로 바탕 찾기)", docs.iter().filter(|d| link_names(d).iter().any(|(k, key)| !k.starts_with('/') && k.contains('/') && key.contains("//"))).count());
    let anchor = regex::Regex::new(r"\[\[[^\]|#]+#[^\]]*\]\]").expect("정규식");
    add("docs [[이름#앵커]] 고리", docs.iter().filter(|d| anchor.is_match(s(d, "body")) && !link_names(d).is_empty()).count());
    {
        let no_size: Vec<&str> = arr(&norm["images"]).iter().filter(|g| !(truthy(&g["width"]) && truthy(&g["height"]))).map(|g| s(g, "name")).collect();
        add("docs 크기가 적히지 않은 그림(sizeOf)", docs.iter().filter(|d| d["images"].as_object().is_some_and(|o| o.iter().any(|(k, g)| no_size.contains(&k.as_str()) && n(g, "w") > 0))).count());
        let keys: Vec<&String> = norm["documents"].as_object().map(|o| o.keys().filter(|k| k.starts_with("view:") || k.starts_with("map:")).collect()).unwrap_or_default();
        add("docs view: · map: 문서 키(바탕 없음 — 기록 없음)", keys.iter().filter(|k| !ents.iter().any(|e| e.0 == format!("doc:{k}"))).count());
    }
    add("docs 보조 달력 날짜가 든 곁글(음력)", docs.iter().filter(|d| s(d, "meta").contains("음력")).count());

    // ── 갈래 D(task-laneD-report.md 10절 — 합성 꼴 ① ~ ⑪ · V8 덮음 목록)
    let has = |t: &str, pat: &str| t.contains(pat);
    let since = regex::Regex::new(r"\(양력[^)]*부터\)").expect("정규식");
    let ymd = regex::Regex::new(r"[0-9]+년 [0-9]+월 [0-9]+일").expect("정규식");
    let ecnt = |p: &dyn Fn(&(String, String, String, Value)) -> bool| ents.iter().filter(|e| p(e)).count();
    add("D① 앞선 단체에 how를 비운 이음(blank)", ecnt(&|e| has(&e.2, r#""kind":"blank""#)));
    add("D② 맺은 사건이 딸린 단체(x_event)", ecnt(&|e| e.1 == "group" && e.3["x_event"].is_object()));
    add("D② 이음선을 누르면 열 사건(x_groupTree edges ev)", ecnt(&|e| arr(&e.3["x_groupTree"]["edges"]).iter().any(|x| truthy(&x["ev"]))));
    add("D③ 원어 이름의 창 표 밖 글자(x_nameHead … mw)", ecnt(&|e| e.3["x_nameHead"].is_object() && e.3["x_nameHead"].to_string().contains("\"mw\"")));
    add("D④ 왕조의 house가 다른 왕조(본가 x_houseMain)", ecnt(&|e| e.1 == "dynasty" && e.3["x_houseMain"].is_object()));
    add("D④ 왕조의 house가 다른 왕조(분가 x_branches)", ecnt(&|e| e.1 == "dynasty" && !arr(&e.3["x_branches"]).is_empty()));
    add("D⑤ institutionAt — 그때의 법률", ecnt(&|e| arr(&e.3["x_lawRelated"]).iter().any(|r| s(r, "tag") == "그때의 법률")));
    add("D⑤ institutionAt — 그때의 선거 방식", ecnt(&|e| arr(&e.3["x_voteRelated"]).iter().any(|r| s(r, "tag") == "그때의 선거 방식")));
    add("D⑥ 법 간격 '일 뒤'", ecnt(&|e| arr(&e.3["x_lawHistory"]["rows"]).iter().any(|r| s(r, "gap").ends_with("일 뒤"))));
    add("D⑥ 법 간격 '개월 뒤'", ecnt(&|e| arr(&e.3["x_lawHistory"]["rows"]).iter().any(|r| s(r, "gap").ends_with("개월 뒤"))));
    add("D⑥ 원문 표기(dateNoteOf — x_lawHistory.orig)", ecnt(&|e| !s(&e.3["x_lawHistory"], "orig").is_empty()));
    add("D⑦ 과반 '넘은 모임 없음'", ecnt(&|e| s(&e.3["x_vote"], "cap").contains("넘은 모임 없음")));
    add("D⑦ 결과를 적지 않은 선거(rows 빈 목록)", ecnt(&|e| e.3["x_vote"].is_object() && arr(&e.3["x_vote"]["rows"]).is_empty()));
    add("D⑧ 가문 지도자 칸의 끝 미정(x_eras.openCells)", ecnt(&|e| arr(&e.3["x_eras"]).iter().any(|r| !arr(&r["openCells"]).is_empty())));
    add("D⑨ 달까지 적은 비서력 날짜 '(양력 …부터)'", ecnt(&|e| since.is_match(&e.2)));
    add("D⑩ 혈연 고리(kinBuild 강제 꺼냄 · 경고)", ecnt(&|e| e.1 == "kin" && arr(&e.3["warnings"]).iter().any(|w| w.as_str().is_some_and(|w| w.contains("고리")))));
    add("D⑩ 생부 + 양부를 함께 적은 사람", ecnt(&|e| has(&e.2, r#""as":"생부""#) && has(&e.2, r#""as":"양부""#)));
    add("D⑩ 생부 · 양부 · 생모를 함께 적은 사람(kinTreeRank 깊은 갈래)", ecnt(&|e| has(&e.2, r#""as":"생부""#) && has(&e.2, r#""as":"양부""#) && has(&e.2, r#""as":"생모""#)));
    add("D⑩ 자리 이음 fromUnknown(전임자 미상)", ecnt(&|e| e.1 == "period" && e.3["x_lineage"].to_string().contains("\"fromUnknown\":1")));
    add("D⑩ '전임자 미상' 이음매 글", ecnt(&|e| has(&e.2, "전임자 미상")));
    add("D⑪ 나라 없이 앞뒤 단체만 있는 단체(단체 x_groupTree)", ecnt(&|e| e.1 == "group" && e.3["x_groupTree"].is_object()));
    add("D⑪ 글꼴 기록(dropBytes)", ecnt(&|e| e.1 == "font"));
    add("D 조약 당사국의 적은 이름을 못 찾음(x_parties[].wrote)", ecnt(&|e| arr(&e.3["x_parties"]).iter().any(|r| truthy(&r["wrote"]))));
    add("D 다스린 기간 막대의 열린 내각 구간(x_eras.openReal)", ecnt(&|e| arr(&e.3["x_eras"]).iter().any(|r| !arr(&r["openReal"]).is_empty())));
    add("D 가문 띠 인물 200명 넘음(x_memberCount)", ecnt(&|e| e.1 == "house" && n(&e.3, "x_memberCount") > 200));
    add("D 못 찾은 앞선 단체(x_from missing)", ecnt(&|e| arr(&e.3["x_from"]).iter().any(|r| truthy(&r["missing"]))));
    add("D 제도 칸 짐작(x_spans guess)", ecnt(&|e| arr(&e.3["x_spans"]).iter().any(|r| truthy(&r["guess"]))));
    add("D 모아 보기 판의 못 찾은 구성 나라(x_members missing)", ecnt(&|e| e.1 == "view" && arr(&e.3["x_members"]).iter().any(|r| truthy(&r["missing"]))));
    add("D 지도 장면의 못 찾은 주인(x_scenes owners missing)", ecnt(&|e| arr(&e.3["x_scenes"]).iter().any(|sc| sc["owners"].as_object().is_some_and(|o| o.values().any(|w| truthy(&w["missing"]))))));
    add("D 날짜 글 없는 소수 해(whenText → cal.formatT 'd')", ecnt(&|e| arr(&e.3["x_nameHead"]["rest"]).iter().any(|r| ymd.is_match(s(r, "when")))));

    // ── 갈래 E — 단체 단 · 렌즈(task-laneE-report.md 중간 절 · 판정 R25)
    add("power 짝을 모르는 연정(solo — 구역 43 d = 1)", cnt(&items, &|i| sec(i, 43) && n(i, "a") == 8 && n(i, "b") == 2 && n(i, "d") == 1));
    add("power 한 나라가 연합 둘 이상에 가담(겹 탭 구역 47 a = 7 · b ≥ 1)", cnt(&items, &|i| sec(i, 47) && n(i, "a") == 7 && n(i, "b") >= 1));
    add("power 단체 집권 칸의 시작 미정(칸 8 단 2 비트 1)", cnt(&cells, &|c| n(c, "kind") == 8 && n(c, "lane") == 2 && n(c, "style") & 1 != 0));
    let lens_cells: Vec<&Value> = arr(&out["cells"]).iter().filter(|c| n(c, "kind") == 8 && s(c, "variant").starts_with("theme:")).collect();
    add("lens 짝을 모르는 연정의 붕당 칸(구역 43 d = 1)", cnt(arr(&out["items"]), &|i| s(i, "variant").starts_with("theme:") && sec(i, 43) && n(i, "a") == 8 && n(i, "b") == 0 && n(i, "d") == 1));
    add("lens 칸의 연대 폭(비트 64)", lens_cells.iter().filter(|c| n(c, "style") & 64 != 0).count());
    add("lens 칸의 추정(비트 8)", lens_cells.iter().filter(|c| n(c, "style") & 8 != 0).count());
    add("lens 칸의 시작 미정(비트 1)", lens_cells.iter().filter(|c| n(c, "style") & 1 != 0).count());
    {
        let slot: Vec<&str> = ents.iter().find(|e| e.0 == "themes" && e.1 == "themes").map(|e| arr(&e.3["x_lens"]["slot"]).iter().filter_map(Value::as_str).collect()).unwrap_or_default();
        add("렌즈 grow 트랙(지도자 없는 트랙에 렌즈 자리 — R25)", slot.iter().filter(|id| arr(&out["tracks"]).iter().any(|t| s(t, "key") == **id && n(t, "leader") == 0)).count());
    }

    // ── 갈래 E — 변형 · 집합 보기(task-laneE-report.md 뒤 절 · 판정 R29)
    let hides = |v: &Value, k: i64| arr(&v["hides"]).iter().any(|h| n(h, "kind") == k);
    add("variants 칸의 변형 판(가림 kind 3)", cnt(arr(&out["variants"]), &|v| n(v, "kind") != 4 && hides(v, 3)));
    add("variants 띠 이사(moves kind 1)", arr(&out["variants"]).iter().map(|v| arr(&v["moves"]).iter().filter(|x| n(x, "kind") == 1).count()).sum());
    let boards = &out["boards"];
    let bvs = arr(&boards["variants"]);
    add("boards 판의 칸(변형 판 · 가림 kind 3)", cnt(bvs, &|v| hides(v, 3)));
    add("boards 사건 이사(kind 2)", cnt(bvs, &|v| arr(&v["moves"]).iter().any(|x| n(x, "kind") == 2)));
    add("boards 문화 칩(왼쪽 칸 kind 1)", cnt(bvs, &|v| arr(&v["groups"]).iter().any(|g| n(g, "kind") == 1)));
    let records: Vec<Value> = arr(&boards["entities"]).iter().map(|e| serde_json::from_str(s(e, "json")).unwrap_or(Value::Null)).collect();
    add("boards 기간 없는 DLC 판(rangeFrom 'members' — 구역 23 a 비트 4)", cnt(arr(&boards["items"]), &|i| sec(i, 23) && n(i, "a") & 4 != 0));
    add("boards 기간 없는 DLC 판(판 기록에 start · end 없음)", cnt(&records, &|j| truthy(&j["view"]) && j.get("start").is_none() && j.get("end").is_none()));
    add("boards 구성 나라 일부를 못 찾은 판(missing > 0)", cnt(&records, &|j| n(j, "missing") > 0));
    add("boards 구성 나라를 모델에서 하나도 풀지 못한 DLC 판(boardsOf가 거름 — 기록 · 뺀판 없음)", cnt(arr(&norm["views"]), &|v| !arr(&boards["entities"]).iter().any(|e| s(e, "uid") == format!("board:view:{}", s(v, "id")))));
    add("boards 판 하나가 오류로 빠짐(notes.집합보기.뺀판)", arr(&notes["집합보기"]["뺀판"]).len());
    m
}

/// 표지마다 새 자료(`NEW`)에서 ≥ 1. 모든 정답지 자료의 수와 새 자료의 수를 함께 찍는다(다른 자료가 이미 닿던 것은 참고).
#[test]
fn synth_fixtures_reach_the_unreached_branches() {
    let list = fixtures();
    for name in NEW { assert!(list.iter().any(|f| f.name == name), "자료 목록(list.json)에 {name}이 없습니다"); }
    let mut total: Vec<(&'static str, usize, usize)> = Vec::new();
    for f in &list {
        let fresh = NEW.contains(&f.name.as_str());
        for (k, (name, c)) in markers(f).into_iter().enumerate() {
            if total.len() <= k { total.push((name, 0, 0)); }
            assert_eq!(total[k].0, name, "표지 차례가 자료마다 같아야 합니다");
            total[k].1 += c;
            if fresh { total[k].2 += c; }
        }
    }
    eprintln!("닿음 표지 {}개(모든 자료 / 새 자료 {}):", total.len(), NEW.join(" · "));
    for (name, all, new) in &total { eprintln!("  {}{name}: {all} / {new}", if *new > 0 { "" } else { "✗ " }); }
    let missing: Vec<&str> = total.iter().filter(|t| t.2 == 0).map(|t| t.0).collect();
    assert!(missing.is_empty(), "새 합성 자료가 닿지 않은 갈래 {}개 — {}", missing.len(), missing.join(" · "));
}

/// 집합 보기에서 판 하나가 오류로 빠진 목록과 그 까닭(`notes.집합보기.뺀판`)이 Node와 같다(판정 R29). 자료마다 Node의 `pre-variants`(+ `.shared`)를 심고
/// boards 하나만 돌린다(`lay_m_boards`와 같은 자리 — 그쪽은 out만 본다). Node에서 판이 빠지지 않은 자료는 건너뛴다(그 자료의 boards 출력은 `lay_m_boards`가 견줌).
/// 빠진 판이 있는 자료가 하나 이상이어야 한다(합성 자료 `synth-lay`의 `ep-sd`).
#[test]
fn boards_dropped_notes_match_node() {
    let o = seam_opts(Some("boards"));
    let (mut seen, mut dropped) = (0, Vec::new());
    for f in fixtures() {
        let want = body(oracle(&f, "notes.json"));
        if arr(&want["집합보기"]["뺀판"]).is_empty() { continue; } // 판이 빠지지 않은 자료 — boards 출력은 lay_m_boards가 본다
        let mut c = ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        c.shared = lay::export::shared_seed(&oracle(&f, "pre-variants.shared.json")).expect("shared 심기");
        let mut out = body(oracle(&f, "pre-variants.json"));
        lay::m::boards::contribute(&mut c, &mut out).unwrap_or_else(|e| panic!("자료 {} · 집합 보기: {e}", f.name));
        let got = js::to_json(&js::V::Obj(c.notes.clone()));
        let got = serde_json::json!({ "집합보기": { "뺀판": got["집합보기"]["뺀판"].clone() } });
        assert_same(&f, "notes.집합보기.뺀판", &got, &want);
        let n = arr(&want["집합보기"]["뺀판"]).len();
        if n > 0 { dropped.push(format!("{} {n}개 — {}", f.name, arr(&want["집합보기"]["뺀판"]).iter().filter_map(Value::as_str).collect::<Vec<_>>().join(" / "))); }
        seen += 1;
    }
    assert!(seen > 0 && !dropped.is_empty(), "판 하나가 오류로 빠지는 자료가 없습니다 — 합성 자료 synth-lay의 ep-sd를 확인하세요");
    eprintln!("집합 보기의 뺀판: 판이 빠지는 자료 {seen}개 Node와 같음(목록 · 까닭 글) — {}", dropped.join(" · "));
}

/// 렌즈 켬 배치(lens.mjs ② — `themeLens`를 켜고 모든 트랙을 다시 배치)의 트랙마다 지도자 자리 · 높이 · 줄 높이가 Node와 같다(판정 R25 선택 5 — 정답지 `lens-on.json`).
/// 지도자 자리가 새로 생기는 트랙(grow)이 하나 이상이어야 한다(합성 자료 `synth-lens`의 `ln`).
#[test]
fn lens_on_rows_match_node() {
    let o = seam_opts(Some("lens"));
    let (mut seen, mut grow) = (0, Vec::new());
    for f in fixtures() {
        assert!(oracle_exists(&f, "lens-on.json"), "정답지 {}/lens-on.json이 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs --only={}", f.name, f.name);
        let want = body(oracle(&f, "lens-on.json"));
        let mut c = ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        let before: Vec<(String, f64)> = lay::model::util::list(&c.tl.get("tracks")).iter().map(|tr| (js::to_str(&tr.get("id")).to_string(), js::to_num(&tr.get("geo").get("leaderH")))).collect();
        let lens = js::Obj::new();
        lens.set("id", js::V::from("*"));
        lens.set("name", js::V::from("*"));
        lens.set("color", js::V::from("#a4b1b7"));
        c.tl.as_obj().expect("연표 상태").set("themeLens", lens);
        lay::track::layout_all(&mut c).unwrap_or_else(|e| panic!("자료 {} · 렌즈 켬 배치: {e}", f.name));
        let tracks: Vec<Value> = lay::model::util::list(&c.tl.get("tracks")).iter().map(|tr| serde_json::json!({
            "id": js::to_json(&tr.get("id")), "leaderH": js::to_json(&tr.get("geo").get("leaderH")), "height": js::to_json(&tr.get("height")), "rowHs": js::to_json(&tr.get("rowHs")),
        })).collect();
        let got = serde_json::json!({ "tracks": tracks });
        assert_same(&f, "lens-on", &got, &want);
        for (t, (id, lead)) in arr(&want["tracks"]).iter().zip(&before) {
            if !(*lead > 0.0) && n(t, "leaderH") > 0 { grow.push(format!("{}/{id}", f.name)); }
        }
        seen += 1;
    }
    assert!(seen > 0, "견준 자료가 없습니다");
    assert!(!grow.is_empty(), "렌즈 켬으로 지도자 자리가 새로 생기는 트랙(grow)이 없습니다 — 합성 자료 synth-lens의 ln을 확인하세요");
    eprintln!("렌즈 켬 배치의 줄 높이: 자료 {seen}개 Node와 같음 — 지도자 자리가 새로 생긴 트랙: {}", grow.join(" · "));
}

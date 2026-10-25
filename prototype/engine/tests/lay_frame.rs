//! 한 벌 P3 과제 16b ② 넘겨받은 틀 손질(d0d8dfa)이 새로 받게 한 길의 단위 검사(16b 틀 손질 검토 Minor) — 정답지 자료는 이 길을 밟지 않는다:
//! `js::for_of`(JS `for … of`가 도는 것) · `kit::has_of` · `has_or_err`(Set · Map의 `.has`) · `web::cells::cell_bound`(Map이 아닌 `cellBounds`는 잘못) ·
//! `kit::try_finally`(boards의 판 하나 · lens의 렌즈 켬 배치의 `try … finally` — 남긴 잘못이 원래 까닭을 가리지 않음). 모듈 돌리기(`export::run_one`)는 그 파일의 단위 검사.
//! 그리고 자료집 판 · 분류 글의 JS `trim`(판정 R61 M4).
mod common;
use archive_engine::lay::js::{self, Arr, Map, Obj, Set, Str, V};
use archive_engine::lay::m::kit::{has_of, has_or_err, try_finally};
use archive_engine::lay::model::util::{fault, take_fault};

/// 글의 UTF-16 단위들 — 조각마다 하나씩.
fn units_of(list: &[V]) -> Vec<Vec<u16>> {
    list.iter().map(|v| match v { V::Str(s) => s.to_units(), other => panic!("글이 아닙니다: {}", js::type_of(other)) }).collect()
}

#[test]
fn for_of_walks_like_js() {
    // 배열은 원소 그대로.
    let a = Arr::new(vec![V::Num(1.0), V::from("둘")]);
    assert_eq!(js::for_of(&V::Arr(a)).map(|l| l.len()), Some(2));
    // 글은 코드 포인트: 한글 · 짝 맞는 서로게이트(😀 = D83D DE00)는 하나 · 외톨이 서로게이트(앞 D800 · 뒤 DC00)는 그대로 하나씩.
    let text = Str::from_units(&[0xAC00, 0xD83D, 0xDE00, 0xD800, 0x41, 0xDC00]);
    let got = js::for_of(&V::Str(text)).expect("글은 돈다");
    assert_eq!(units_of(&got), vec![vec![0xAC00], vec![0xD83D, 0xDE00], vec![0xD800], vec![0x41], vec![0xDC00]]);
    assert_eq!(js::for_of(&V::from("")).map(|l| l.len()), Some(0));
    // Map은 [열쇠, 값] 배열 · Set은 원소(넣은 차례).
    let m = Map::new();
    m.set(V::from("가"), V::Num(1.0));
    m.set(V::Num(2.0), V::from("나"));
    let got = js::for_of(&V::Map(m)).expect("Map은 돈다");
    assert_eq!(got.len(), 2);
    assert!(matches!(&got[0], V::Arr(p) if js::strict_eq(&p.to_vec()[0], &V::from("가")) && js::strict_eq(&p.to_vec()[1], &V::Num(1.0))));
    assert!(matches!(&got[1], V::Arr(p) if js::strict_eq(&p.to_vec()[0], &V::Num(2.0))));
    let s = Set::new();
    s.add(V::from("셋"));
    s.add(V::Num(4.0));
    let got = js::for_of(&V::Set(s)).expect("Set은 돈다");
    assert!(got.len() == 2 && js::strict_eq(&got[0], &V::from("셋")) && js::strict_eq(&got[1], &V::Num(4.0)));
    // 순회되지 않는 것(JS는 TypeError) — None.
    for (name, v) in [("undefined", V::Undef), ("null", V::Null), ("수", V::Num(3.0)), ("참거짓", V::Bool(true)), ("객체", V::Obj(Obj::new()))] {
        assert!(js::for_of(&v).is_none(), "{name}");
    }
}

#[test]
fn has_takes_sets_and_maps() {
    let k = V::Num(3.0);
    let s = Set::new();
    s.add(k.clone());
    let m = Map::new();
    m.set(k.clone(), V::Bool(false)); // 값이 거짓이어도 열쇠가 있으면 참(Map.has)
    assert_eq!(has_of(&V::Set(s.clone()), &k), Some(true));
    assert_eq!(has_of(&V::Set(s), &V::Num(4.0)), Some(false));
    assert_eq!(has_of(&V::Map(m.clone()), &k), Some(true));
    assert_eq!(has_of(&V::Map(m.clone()), &V::from("3")), Some(false)); // 같음은 엄격(SameValueZero) — 글 '3'은 다른 열쇠
    for (name, v) in [("undefined", V::Undef), ("배열", V::Arr(Arr::new(vec![k.clone()]))), ("객체", V::Obj(Obj::new())), ("글", V::from("3"))] {
        assert_eq!(has_of(&v, &k), None, "{name}");
        let e = has_or_err(&v, &k, "tr.foldedRows").unwrap_err().to_string();
        assert!(e.contains("tr.foldedRows") && e.contains(".has"), "{name}: {e}");
    }
    assert!(has_or_err(&V::Map(m), &k, "tr.hiddenRows").unwrap());
}

#[test]
fn cell_bound_faults_when_bounds_are_not_a_map() {
    use archive_engine::lay::web::cells::cell_bound;
    let p = Obj::new();
    let r = V::from("leader:0");
    // 모델은 `cellBounds`를 Map으로 둔다 — 그 칸이 없으면 null(잘못 없음).
    p.set("cellBounds", V::Map(Map::new()));
    assert!(matches!(cell_bound(&V::Obj(p.clone()), &r), V::Null));
    assert!(take_fault().is_none());
    // 참인데 Map이 아니면 JS는 `.get`에서 TypeError — 잘못을 남기고 null.
    p.set("cellBounds", V::Obj(Obj::new()));
    assert!(matches!(cell_bound(&V::Obj(p.clone()), &r), V::Null));
    assert!(take_fault().is_some_and(|f| f.contains("cellBounds")), "잘못이 남아야 합니다");
    // 없음(거짓)이면 그냥 null.
    p.set("cellBounds", V::Undef);
    assert!(matches!(cell_bound(&V::Obj(p), &r), V::Null));
    assert!(take_fault().is_none());
}

#[test]
fn try_finally_keeps_the_original_reason() {
    let ok: archive_engine::Result<u8> = Ok(7);
    let err = || -> archive_engine::Result<u8> { Err("원래 까닭".into()) };
    // 되돌림이 남긴 잘못은 앞의 것을 덮는다(JS finally가 던짐).
    let e = try_finally(err(), Some("묵은 잘못".into()), Some("되돌림 잘못".into()), "켬", "되돌림").unwrap_err().to_string();
    assert!(e.starts_with("되돌림 — 되돌림 잘못"), "{e}");
    // try가 오류면 그 오류 — 거둬 둔 잘못(pending)은 그 글을 가리지 않는다.
    assert_eq!(try_finally(err(), Some("묵은 잘못".into()), None, "켬", "되돌림").unwrap_err().to_string(), "원래 까닭");
    // try가 Ok인데 잘못을 남겼으면(JS라면 try 안에서 던졌을 것) 그것.
    let e = try_finally(ok, Some("던졌을 곳".into()), None, "켬", "되돌림").unwrap_err().to_string();
    assert!(e.starts_with("켬 — 던졌을 곳"), "{e}");
    assert_eq!(try_finally(Ok(7u8), None, None, "켬", "되돌림").unwrap(), 7);
    // 이 함수는 잘못 칸을 건드리지 않는다(부르는 쪽이 거둔 값만 받는다).
    fault("남은 것".into());
    let _ = try_finally(Ok(1u8), None, None, "켬", "되돌림");
    assert!(take_fault().is_some());
}

/// 판정 R61 M4: 배치의 자료집 판 · 분류 글은 JS `trim`으로 다듬는다 — BOM(U+FEFF)은 떼고 U+0085(NEL)는 남긴다(Rust `str::trim`은 거꾸로).
#[test]
fn pack_version_is_trimmed_like_js() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../fixtures/oracle/synth.json");
    let mut raw: serde_json::Value = serde_json::from_slice(&std::fs::read(&path).expect("synth.json")).expect("JSON");
    raw["version"] = serde_json::json!("\u{FEFF}1.0.0\u{85}");
    raw["category"] = serde_json::json!(" \u{FEFF}");
    let bytes = archive_engine::legacy::seal_dlc(&serde_json::to_vec(&raw).unwrap());
    let packs = [archive_engine::lay::PackIn { name: "synth.htpack".into(), bytes }];
    let o = common::oracle::seam_opts(Some("tracks"));
    let out = archive_engine::lay::export(&packs, &o).expect("내보내기");
    assert_eq!(out["packs"][0]["version"], "1.0.0\u{85}");
    assert!(out["packs"][0].get("category").is_none(), "빈 글이 된 분류는 싣지 않는다: {}", out["packs"][0]);
}

/// 판정 R61 M3: 모듈의 기록(`ctx.notes`)을 버리지 않는다 — `export_with_notes`가 배치와 함께 돌려주고 짓기의 요약(`build_files`)이 싣는다.
/// 합성 자료 synth-lay는 판 하나(시대 판 ep-sd)가 셈 오류로 빠진다 — 그 판이 `집합보기.뺀판`에 든다. 배치는 `export`와 같다.
#[test]
fn notes_come_back_with_the_layout() {
    let f = common::oracle::fixtures().into_iter().find(|f| f.name == "synth-lay").expect("합성 자료 synth-lay");
    let packs = common::oracle::inputs(&f);
    let o = common::oracle::seam_opts(None);
    let (out, notes) = archive_engine::lay::export::export_with_notes(&packs, &o).expect("내보내기");
    assert_eq!(out, archive_engine::lay::export(&packs, &o).unwrap(), "배치는 export와 같다");
    let dropped = notes["집합보기"]["뺀판"].to_string();
    assert!(dropped.contains("ep-sd"), "뺀 판이 기록에 없습니다: {}", notes["집합보기"]);
    assert!(notes.get("띠").is_some() && notes.get("날짜_칸").is_some(), "모듈마다의 집계: {notes}");
}

//! 과제 8-틀 — 모듈 `boards`(19/21)만 Node와 견준다(`common::modcheck` — `pre-variants`를 심고. REPLAY가 열두 모듈의 Rust `contribute`를 부르고 판 트랙의 줄 배정이 필요하다). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`. 옮기지 않았으면 건너뛴다.
//! 갈래 E(판정 R29 Important 1): 판 하나가 오류로 빠지는 길(`boards.mjs` 543 ~ 548줄 — 잡아서 `notes.뺀판`)은 정답지 21자료 어디서도 돌지 않는다 —
//! 원래 트랙 하나에 줄 목록 없는 판(`board = {}`)을 달아 그 트랙의 나라를 품은 판만 `_boardPlan`의 줄 배정에서 실패시켜 본다.
mod common;
use archive_engine::lay::{self, ctx, js};
use common::oracle::{assert_same, fixtures, inputs, oracle, seam_opts, Fixture};
use serde_json::Value;

#[test]
fn boards_contribute_matches_node() { common::modcheck::check_contribute("boards"); }

/// 판 기록(`entities`의 `board:<열쇠>`) 가운데 구성 나라가 트랙 `track`에 있는 판의 열쇠(Node 정답지의 차례).
fn keys_touching(want: &Value, track: &str) -> Vec<String> {
    want["boards"]["entities"].as_array().into_iter().flatten().filter_map(|e| {
        let rec: Value = serde_json::from_str(e["json"].as_str()?).ok()?;
        rec["members"].as_array()?.iter().any(|m| m["track"] == track).then(|| rec["key"].as_str().unwrap_or("").to_string())
    }).collect()
}
/// 판 열쇠 `k`의 결과만(판 트랙 · 변형 · 기록 · 그 판의 칸 · 그릴 것 · 줄 이름).
fn board_part(boards: &Value, k: &str) -> Value {
    let pick = |key: &str, f: &dyn Fn(&Value) -> bool| Value::Array(boards[key].as_array().into_iter().flatten().filter(|x| f(x)).cloned().collect());
    serde_json::json!({
        "track": pick("tracks", &|x| x["key"] == format!("__board:{k}").as_str()), "variant": pick("variants", &|x| x["key"] == k),
        "entity": pick("entities", &|x| x["uid"] == format!("board:{k}").as_str()), "cells": pick("cells", &|x| x["variant"] == k),
        "items": pick("items", &|x| x["variant"] == k), "rowLabels": pick("rowLabels", &|x| x["variant"] == k),
    })
}

/// 트랙 `track`에 줄 목록 없는 판을 달고 boards를 돌린다 — 그 트랙의 나라를 품은 판만 빠지고(`notes.뺀판` — 그 열쇠들), 문맥은 처음 그대로
/// (진짜 모델(`Rc` 같음) · shared 그대로 · `tl.board` · `_boardTr` · `_boardUids` null · `_boardOpen` 빈 Set · `_boardFolded` 거짓 · `tl.tracks` 차례 같음 · 그릇 수 처음으로).
/// 첫 실패 판 앞의 판은 Node와 값까지 같고, 나머지 판은 Node 차례에서 빠진 판만 뺀 열쇠 차례. 돌려주는 값: (빠진 판 수, 그대로 견준 판 수).
fn one_track_fails(f: &Fixture, track: &str) -> (usize, usize) {
    let o = seam_opts(Some("boards"));
    let base = js::live_containers();
    let want = oracle(f, "pre-boards.json");
    let failing = keys_touching(&want, track);
    assert!(!failing.is_empty(), "자료 {}: 트랙 {track}의 나라를 품은 판이 없습니다", f.name);
    let all_keys: Vec<String> = want["boards"]["variants"].as_array().into_iter().flatten().map(|v| v["key"].as_str().unwrap_or("").to_string()).collect();
    let result;
    {
        let mut c = ctx::context_of(&inputs(f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        c.shared = lay::export::shared_seed(&oracle(f, "pre-variants.shared.json")).expect("shared 심기");
        let shared_before = lay::export::shared_dump(&c);
        let model_before = c.model.clone();
        let order_before: Vec<String> = lay::model::util::list(&c.tl.get("tracks")).iter().map(|tr| js::to_str(&tr.get("id")).as_str().into_owned()).collect();
        let poisoned = lay::model::util::list(&c.tl.get("tracks")).into_iter().find(|tr| js::to_str(&tr.get("id")) == track).expect("트랙");
        poisoned.as_obj().expect("트랙").set("board", js::Obj::new());
        let mut out = oracle(f, "pre-variants.json");
        if let Some(m) = out.as_object_mut() { m.remove("$oracle"); }
        lay::m::boards::contribute(&mut c, &mut out).unwrap_or_else(|e| panic!("자료 {}: 판 하나의 오류는 잡혀야 합니다 — {e}", f.name));

        // 뺀판 = 그 트랙을 품은 판(차례 그대로) — 글은 '<열쇠>: <까닭>'
        let dropped: Vec<String> = lay::model::util::list(&c.notes.get("집합보기").get("뺀판")).iter()
            .map(|x| js::to_str(x).as_str().split_once(": ").map_or(String::new(), |(k, _)| k.to_string())).collect();
        assert_eq!(dropped, failing, "자료 {}: 뺀판의 열쇠", f.name);
        // 문맥은 처음 그대로
        assert!(js::strict_eq(&c.model, &model_before), "자료 {}: ctx.model이 진짜 모델이 아닙니다(얕은 사본이 남음)", f.name);
        assert_same(f, "shared(판이 빠진 뒤)", &lay::export::shared_dump(&c), &shared_before);
        for k in ["board", "_boardTr", "_boardUids"] { assert!(c.tl.get(k).is_null(), "자료 {}: tl.{k}가 null로 돌아오지 않았습니다", f.name); }
        assert!(c.tl.get("_boardOpen").as_set().is_some_and(|s| s.is_empty()), "자료 {}: tl._boardOpen이 빈 Set이 아닙니다", f.name);
        assert!(matches!(c.tl.get("_boardFolded"), js::V::Bool(false)), "자료 {}: tl._boardFolded가 거짓이 아닙니다", f.name);
        let order_after: Vec<String> = lay::model::util::list(&c.tl.get("tracks")).iter().map(|tr| js::to_str(&tr.get("id")).as_str().into_owned()).collect();
        assert_eq!(order_after, order_before, "자료 {}: tl.tracks 차례", f.name);
        // 다른 판은 그대로 나온다: 열쇠 차례 = Node 차례에서 빠진 판만 뺀 것 · 첫 실패 판 앞의 판은 값까지 같다(뒤의 판은 판 트랙 번호가 하나씩 당겨짐)
        let rest: Vec<String> = all_keys.iter().filter(|k| !failing.contains(k)).cloned().collect();
        let got_keys: Vec<String> = out["boards"]["variants"].as_array().into_iter().flatten().map(|v| v["key"].as_str().unwrap_or("").to_string()).collect();
        assert_eq!(got_keys, rest, "자료 {}: 남은 판의 열쇠 차례", f.name);
        if rest.is_empty() { assert!(out.get("boards").is_none(), "자료 {}: 판이 모두 빠지면 겉 열쇠 boards도 없어야 합니다", f.name); }
        let first_fail = all_keys.iter().position(|k| failing.contains(k)).unwrap_or(all_keys.len());
        for k in &all_keys[..first_fail] { assert_same(f, &format!("판 {k}(빠진 판 앞)"), &board_part(&out["boards"], k), &board_part(&want["boards"], k)); }
        result = (failing.len(), first_fail);
    }
    assert_eq!(js::live_containers(), base, "자료 {}: 판이 빠진 뒤 문맥을 버리면 그릇 수가 처음으로 돌아와야 합니다", f.name);
    result
}

/// 한 판만 빠짐: synth(판 하나 — 구성 나라의 트랙 north는 그 판에만) · lantern(판 23 — 트랙 seohae를 품은 판 아홉이 빠지고 앞의 둘은 Node와 같음 · 나머지 열넷은 차례대로).
#[test]
fn a_failing_board_is_dropped_and_the_context_restored() {
    let list = fixtures();
    let pick = |name: &str| list.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("자료 {name}이 없습니다"));
    let (n1, _) = one_track_fails(pick("synth"), "north");
    assert_eq!(n1, 1, "synth: 빠진 판 하나");
    let (n2, same) = one_track_fails(pick("lantern"), "seohae");
    assert!(n2 >= 1 && same >= 1, "lantern: 빠진 판 {n2} · 그대로 견준 판 {same}");
    eprintln!("판이 오류로 빠지는 길: synth 1판 빠짐 · lantern {n2}판 빠짐(앞의 {same}판은 Node와 같음 · 나머지는 차례대로) — 문맥 그대로 · 그릇 수 처음으로");
}

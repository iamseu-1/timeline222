//! 한 벌 P3 과제 8 ~ 15 통째(이음매 ③): 옮긴 **앞자리**(`lay::PORTED_PREFIX`)까지 `lay::export`(runModules 그대로 — contribute 전부 → 늦은 차례 → 공통 점검)가
//! Node의 `upto-<그 모듈>.json`과 차이 0이다(값 — 그리고 `json` 열쇠의 글은 바이트로도). 모듈 스물이 모두 옮겨지면 `upto-lens`(과제 15의 끝 — Node 내보내기와 차이 0).
//! 모듈 하나씩의 검사는 `tests/lay_m_<모듈>.rs`(Node의 앞 출력을 심고 그 모듈만 — 갈래가 동시에 옮김). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`(upto-<모듈>은 그 이음매가 함께 냄).
mod common;
use archive_engine::lay::{self, ported_count, same, MODULES, PORTED_PREFIX};
use common::oracle::{assert_same, assert_same_bytes, fixtures, inputs, oracle, seam_opts};
use serde_json::json;

#[test]
fn export_prefix_matches_node() {
    let k = PORTED_PREFIX;
    assert!(k > 0, "옮긴 앞자리가 없습니다(첫 모듈 tracks부터)");
    let last = MODULES[k - 1].name;
    let upto = if k == MODULES.len() { None } else { Some(last) };
    let o = seam_opts(upto);
    let mut n = 0;
    for f in fixtures() {
        let got = lay::export(&inputs(&f), &o).unwrap_or_else(|e| panic!("자료 {}: 내보내기를 하지 못했습니다 — {e}", f.name));
        let want = oracle(&f, &format!("upto-{last}.json"));
        assert_same(&f, &format!("upto-{last}"), &got, &want);
        assert_same_bytes(&f, &format!("upto-{last}"), &got, &want);
        n += 1;
    }
    assert!(n > 0, "견준 자료가 하나도 없습니다");
    eprintln!("통째(upto-{last} — 앞자리 {k}/20 · 옮긴 모듈 {}개): 자료 {n}개 Node와 같음(값 · json 글 바이트)", ported_count());
}

/// 옮기지 않은 모듈은 조용히 다른 답을 내지 않고 거절한다 — 통째(`export`)가 앞자리 밖으로 가도, 하나만(`export_one`)이어도.
#[test]
fn unported_modules_are_refused() {
    let Some(first_unported) = MODULES.iter().find(|m| !m.ported) else { eprintln!("모듈 스물이 모두 옮겨졌습니다 — 거절할 것이 없음"); return };
    let f = &fixtures()[0];
    let err = lay::export(&inputs(f), &seam_opts(Some(first_unported.name))).err().expect("옮기지 않은 모듈이 든 앞자리는 거절해야 합니다").to_string();
    assert!(err.contains("옮기지 않은 모듈") && err.contains(first_unported.name), "{err}");
    let err = lay::export_one(&inputs(f), &seam_opts(None), first_unported.name, None, None).err().expect("옮기지 않은 모듈 하나도 거절").to_string();
    assert!(err.contains("옮기지 않은 모듈"), "{err}");
}

/// `shared` 덤프 심기: seam 규칙의 `$map` · `$set`은 JS Map · Set으로 되살고, 모델 객체 참조(`$ref`)가 들면 거절한다(그 shared를 쓰는 모듈은 한 갈래로 옮겨야 함).
#[test]
fn shared_seed_restores_maps_and_sets_and_refuses_refs() {
    use archive_engine::lay::js::{self, V};
    let v = json!({ "catNo": { "$map": [["a", 0], ["b", 1]] }, "powerNominal": { "$map": [["u", { "$set": [0, 2] }]] }, "docsOf": { "u": [{ "key": "k", "sub": "s" }] } });
    let o = lay::export::shared_seed(&v).expect("심긴다");
    let V::Map(cat) = o.get("catNo") else { panic!("catNo는 Map") };
    assert_eq!(js::to_num(&cat.get(&V::from("b"))), 1.0);
    let V::Map(pn) = o.get("powerNominal") else { panic!("powerNominal은 Map") };
    let V::Set(set) = pn.get(&V::from("u")) else { panic!("값은 Set") };
    assert!(set.has(&V::Num(2.0)) && !set.has(&V::Num(1.0)));
    assert_eq!(js::to_str(&o.get("docsOf").get("u").get(&0.0).get("sub")).as_str(), "s");
    // 되감으면 같은 덤프(머리 없음)
    assert!(same::diff(&js::seam(&V::Obj(o.clone())), &v, 5).is_empty());
    js::release(&V::Obj(o));
    let err = lay::export::shared_seed(&json!({ "x": { "$ref": "uid#tracks.0" } })).err().expect("$ref는 거절").to_string();
    assert!(err.contains("$ref") || err.contains("참조"), "{err}");
}

/// `json` 열쇠 글의 바이트 견줌(고침 1회차): 값은 같은데(`diff` 0) 열쇠 차례만 다른 글을 잡고 그 자리(uid)와 처음 다른 바이트를 알린다 · 같은 글 · json이 아닌 글은 지나친다.
#[test]
fn json_text_is_compared_by_bytes() {
    let a = json!({ "entities": [{ "uid": "u1", "kind": "period", "json": "{\"a\":1,\"b\":2}" }, { "uid": "u2", "kind": "doc", "json": "{\"x\":[1,2]}" }], "name": "n" });
    let b = json!({ "entities": [{ "uid": "u1", "kind": "period", "json": "{\"b\":2,\"a\":1}" }, { "uid": "u2", "kind": "doc", "json": "{\"x\":[1,2]}" }], "name": "n" });
    assert!(same::diff(&a, &b, 5).is_empty(), "값으로는 같다");
    let d = same::diff_json_text(&a, &b, 5);
    assert_eq!(d.len(), 1, "{d:?}");
    assert!(d[0].starts_with("entities.0.json(uid u1): json 글이 다릅니다 — 2바이트째"), "{}", d[0]);
    assert!(same::diff_json_text(&a, &a, 5).is_empty());
    let c = json!({ "items": [{ "json": "글", "name": "x" }] });
    let e = json!({ "items": [{ "json": "글2", "name": "x" }] });
    assert_eq!(same::diff_json_text(&c, &e, 5).len(), 1, "json이 아닌 글도 json 열쇠 밑이면 바이트로 견준다");
}

/// 공통 점검(runModules 끝의 assert)이 JS처럼 거절한다 — 열쇠가 없으면(undefined) 비교가 거짓 · 소수 순번은 줄을 찾지 못함 · 칸의 띠 참조는 글만.
#[test]
fn common_checks_refuse_like_js() {
    let ok = json!({ "tracks": [{ "rows": [{}, {}] }], "periods": [{ "uid": "p", "track": 0, "row": 1, "start": 0, "end": 5, "name": "띠" }], "cells": [{ "period": "p", "start": 1, "end": 2, "name": "칸" }],
        "events": [{ "track": 0, "row": 0, "title": "사건" }], "items": [{ "section": 16, "track": 0, "row": 0, "row2": 1, "start": 0, "end": 0, "name": "항목" }] });
    lay::export::common_checks(&ok).expect("바른 out은 통과");
    let mut bad = ok.clone(); bad["periods"][0].as_object_mut().unwrap().remove("row");
    assert!(lay::export::common_checks(&bad).unwrap_err().to_string().contains("띠의 자리 오류"), "row가 없으면(undefined) 거절");
    let mut bad = ok.clone(); bad["events"][0]["track"] = json!(0.5);
    assert!(lay::export::common_checks(&bad).unwrap_err().to_string().contains("사건의 줄이 없습니다"), "소수 트랙 순번은 줄을 찾지 못한다");
    let mut bad = ok.clone(); bad["cells"][0]["period"] = json!(0);
    assert!(lay::export::common_checks(&bad).unwrap_err().to_string().contains("칸이 가리키는 띠"), "띠 참조는 글만");
    let mut bad = ok.clone(); bad["items"][0]["row2"] = json!(2);
    assert!(lay::export::common_checks(&bad).unwrap_err().to_string().contains("일반 항목의 자리 오류"), "줄 범위 밖");
    // `rowsOf[p.track]`은 String(p.track)으로 찾는다(16b — 넘겨받은 틀 손질): null · true · '00'은 배열 자리가 아니다(예전엔 수 0 · 1로 바꿔 찾음) · 글 '0' · 0.0은 자리 0.
    for (track, okay) in [(json!(null), false), (json!(true), false), (json!("00"), false), (json!("0"), true), (json!(0.0), true)] {
        let mut x = ok.clone(); x["events"][0]["track"] = track.clone();
        assert_eq!(lay::export::common_checks(&x).is_ok(), okay, "사건 track {track}");
        let mut x = ok.clone(); x["periods"][0]["track"] = track.clone();
        assert_eq!(lay::export::common_checks(&x).is_ok(), okay, "띠 track {track}");
    }
}

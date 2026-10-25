//! 트랙 단위 바꿔 쓰기(계획 P4 과제 5a ~ 5d · 6): 어떤 차례로 넣고 빼도 그 조합을 통째로 지은 것과 같은가(설계 3-4 '같음의 약속').
mod common;
use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::legacy::import_layout_value;
use archive_engine::patch::{apply, sub_plan, ApplyIn, ApplyReport, Covers};
use archive_engine::write::write;
use common::plans::{big, packs_of, plan};
use common::same::{meta, pairs, quick, quick_q, same_entities, same_records, search_terms};

/// meta가 통째 짓기와 같은가(얹힌 몫 15 — 모든 열쇠에서 뺄 것만 뺀다) — `common::same::same_meta`에서 지은 날(`now` — 얹힌 몫 5)을 뺀 것.
fn same_meta(path: &std::path::Path, want: &std::path::Path, tag: &str) {
    common::same::same_meta(path, want, tag, &["now"]);
}

fn opts(queries: bool) -> CanonOpts { CanonOpts { levels: vec![0, 4, 7, 8, 11, 14], max_x: 32, queries } }
fn full(set: &[&str], name: &str) -> std::path::PathBuf {
    let path = common::scratch(name);
    import_layout_value(&plan(set), &packs_of(set), &path).unwrap();
    path
}
fn step(path: &std::path::Path, set: &[&str], remove: &[String]) -> ApplyReport {
    let (p, o) = (plan(set), packs_of(set));
    write(path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove })).unwrap()
}
/// 그 조합을 통째로 지은 저장소와 canon이 같은가 — 견준 통째 짓기의 경로를 돌려준다(수 세기 · 검색 낱자를 더 견줄 때).
fn same(path: &std::path::Path, set: &[&str], tag: &str, queries: bool) -> std::path::PathBuf {
    let want = full(set, &format!("{tag}-full"));
    let expect = canon_store(&want, &opts(queries)).unwrap();
    if queries {
        // 이름까지 찾는 넓힌 검색을 실제로 견주었는가(낱말을 못 골라 비어서 같은 것이 아니게 — 과제 6 얹힌 몫 5).
        assert!(expect["queries"]["search_words"]["wide"].as_u64().is_some_and(|n| n > 0), "{tag}: 넓힌 검색 낱말을 고르지 못함");
    }
    assert_eq!(canon_store(path, &opts(queries)).unwrap(), expect, "{tag} {set:?}");
    want
}

#[test]
fn adding_a_track_only_matches_a_full_build() {
    let path = full(&["a"], "ap-add");
    let r = step(&path, &["a", "c"], &[]);
    assert_eq!((r.added.clone(), r.rewrote.clone()), (vec!["tc".to_string()], vec![]));
    assert!(r.names, "트랙이 들면 이름 표를 다시 편다");
    same(&path, &["a", "c"], "ap-add", false);
}

/// 판 트랙의 열쇠 — 장면(`plans.rs`)의 판 트랙 `__board:view:a1`에 지문 앞머리 `board:`(patch::track_key).
const BOARD: &str = "board:__board:view:a1";

#[test]
fn recolor_rewrites_only_that_track_and_keeps_numbers() {
    let path = full(&["a", "c"], "ap-recolor");
    let before = common::uid_ids(&path); // uid → (띠 · 사건) 번호
    let r = step(&path, &["a@2", "c"], &[]);
    // 판정 R18: 판이 ta를 가려 판 트랙도 한 겹 더 든다(글자 차례). tc의 ref · 이사가 그대로 맞아 번지지 않음.
    assert_eq!(r.rewrote, vec![BOARD.to_string(), "ta".to_string()]);
    assert!(r.added.is_empty() && r.removed.is_empty());
    let after = common::uid_ids(&path);
    for (uid, id) in &before { assert_eq!(after.get(uid), Some(id), "{uid}의 번호가 바뀜"); }
    // tc의 이사가 ta의 새 덩이로 relink됨 — 조회까지(5d 얹힌 몫 8: 변형을 하나씩 켠 보기의 events_in · same_year · echo · 넓힌 검색).
    let want = same(&path, &["a@2", "c"], "ap-recolor", true);
    same_records(&path, &want, "색 바꿈");
    step(&path, &["a", "c"], &[]);
    let want = same(&path, &["a", "c"], "ap-recolor-back", false);
    same_records(&path, &want, "색 되돌림");
}

#[test]
fn removing_a_track_matches_a_full_build() {
    let path = full(&["a", "c"], "ap-remove");
    let r = step(&path, &["a"], &["c".to_string()]);
    assert_eq!(r.removed, vec!["tc"]);
    let want = same(&path, &["a"], "ap-remove", false);
    same_records(&path, &want, "빼기");
}

#[test]
fn a_hidden_cell_recolored_rewrites_its_track_and_the_hider() {
    // 얹힌 몫 12: 판이 가리는 ta의 칸(BOARD_CELL)의 색만 바꾸면 그 칸의 트랙(ta)과 가리는 판 트랙 둘 다 다시 쓴다
    // (가림 내용에는 색이 없어 판의 지문은 그대로 — 저장된 hides로 한 겹 든다).
    let path = full(&["a", "c"], "ap-hidden-color");
    let mut p = plan(&["a", "c"]);
    p["cells"][common::plans::BOARD_CELL as usize]["color"] = serde_json::json!(0x123456);
    let o = packs_of(&["a", "c"]);
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
    assert_eq!(r.rewrote, vec![BOARD.to_string(), "ta".to_string()]);
    let want = common::scratch("ap-hidden-color-full");
    import_layout_value(&p, &o, &want).unwrap();
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
}

/// 리메이크 3단계 과제 7 걸음 3 — 가림 주인은 **닫힐 때까지** 든다(등불 + `f4-crowns` 거절의 작은 장면). ta의 소속 펼치기(`host:a/ta-host`)가 tc의 일반 항목
/// 하나를 더 가리게 손본 조합에서 tc의 띠 색만 바꾸면: tc(지문이 다름) → ta(tc를 가리는 주인 — 지문은 그대로) → 판(ta의 칸 · 관계선을 가리는 주인 — 지문은
/// 그대로). 한 겹에서 멈추던 때는 판을 다시 쓰지 않아 "delete"의 지킴("다시 쓰지 않는 변형 2개가 지울 트랙 «ta»의 칸 · 항목을 가립니다")에 걸렸다.
/// - 모두 덮는 배치: 셋 다 다시 쓰고 통째 짓기와 같다.
/// - 하위 배치(S = {tc}): 넓히기 한 번에 ta와 판을 함께 달라고 하고, 그것을 실어 다시 넣으면 받아 통째 짓기와 같다.
#[test]
fn hiders_of_a_hider_are_rewritten_too() {
    use archive_engine::patch::{prints, Widen};
    use serde_json::json;
    let scene = |color: u32| -> serde_json::Value {
        let mut p = plan(&["a", "c"]);
        let tc = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
        let at = p["items"].as_array().unwrap().iter().position(|it| it["track"] == tc).unwrap();
        let host = p["variants"].as_array_mut().unwrap().iter_mut().find(|v| v["key"] == "host:a/ta-host").unwrap();
        host["hides"].as_array_mut().unwrap().push(json!({"kind":4,"at":at}));
        p["periods"].as_array_mut().unwrap().iter_mut().find(|x| x["uid"] == "c/tc-2").unwrap()["color"] = json!(color);
        p
    };
    let (before, after) = (scene(0xa0bcc5), scene(0x5a7d9c));
    let (old, new) = (prints(&before).unwrap(), prints(&after).unwrap());
    let changed: Vec<&String> = new.tracks.iter().filter(|(k, t)| old.tracks[*k].print != t.print).map(|(k, _)| k).collect();
    assert_eq!(changed, vec!["tc"], "장면: 지문이 바뀌는 것은 tc뿐");
    assert!(old.tracks["ta"].hides.contains("tc") && old.tracks[BOARD].hides.contains("ta") && !old.tracks[BOARD].hides.contains("tc"), "장면: tc ← ta ← 판");
    let want = full_of(&after, &["a", "c"], "ap-hider-chain-full");
    let expect = canon_store(&want, &opts(false)).unwrap();
    // 모두 덮는 배치.
    let path = full_of(&before, &["a", "c"], "ap-hider-chain");
    let r = step_of(&path, &after, &["a", "c"]);
    assert_eq!(r.rewrote, vec![BOARD.to_string(), "ta".to_string(), "tc".to_string()], "가림 주인의 가림 주인까지");
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), expect, "모두 덮는 배치: 통째 짓기와 다릅니다");
    same_records(&path, &want, "가림 주인 사슬(모두 덮는 배치)");
    // 하위 배치 — S = {tc}에서 넓히기 한 번에 둘 다.
    let path = full_of(&before, &["a", "c"], "ap-hider-chain-part");
    let o = packs_of(&["a", "c"]);
    let part = |s: &std::collections::BTreeSet<String>| {
        let sub = sub_plan(&after, s).unwrap();
        write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &o, covers: Covers::Part { tracks: s.clone(), order: new.order.clone() }, remove: &[] }))
    };
    let mut s: std::collections::BTreeSet<String> = ["tc".to_string()].into_iter().collect();
    let err = part(&s).unwrap_err();
    let more = err.downcast_ref::<Widen>().unwrap_or_else(|| panic!("넓히기여야 함: {err}")).0.clone();
    assert_eq!(more.iter().collect::<Vec<_>>(), vec![BOARD, "ta"], "넓히기 한 번에 가림 주인의 가림 주인까지");
    s.extend(more);
    let r = part(&s).unwrap_or_else(|e| panic!("넓힌 하위 배치: {e}"));
    assert_eq!(r.rewrote, vec![BOARD.to_string(), "ta".to_string(), "tc".to_string()]);
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), expect, "하위 배치: 통째 짓기와 다릅니다");
    same_records(&path, &want, "가림 주인 사슬(하위 배치)");
}

#[test]
fn adding_a_dlc_on_another_track_rewrites_its_dependents() {
    // b는 ta에 줄 · 띠 · 사건을 얹고(ta 다시 씀 — 줄 수가 는다) 제 트랙 tb를 더한다. tc는 b/ta-late를 가리키므로(생기는 uid) 다시 쓰고,
    // 판은 ta를 가려 다시 쓴다. 띠 · 사건 · 변형 번호는 그대로 · 새 uid는 지우기 전 가장 큰 번호 다음부터.
    // b는 자료집 목록의 가운데(a · b · c)에 든다 — 새 자료집 행은 끝 번호를 받지만(넣은 차례) layout의 자료집 차례는 '기본이 첫째'만
    // 약속이고 canon은 나머지를 글자 id로 정렬해 견준다(판정 R20 · R22 — 5c는 끝에 넣어 견주었다).
    let path = full(&["a", "c"], "ap-add-b");
    let before = common::uid_ids(&path);
    let r = step(&path, &["a", "b", "c"], &[]);
    assert_eq!((r.rewrote.clone(), r.added.clone()), (vec![BOARD.to_string(), "ta".to_string(), "tc".to_string()], vec!["tb".to_string()]));
    let after = common::uid_ids(&path);
    for (uid, id) in &before { assert_eq!(after.get(uid), Some(id), "{uid}의 번호가 바뀜"); }
    // 띠 · 사건 번호는 따로 센다: b의 새 uid는 그 표의 지우기 전 가장 큰 번호보다 크다(ta · tc를 다 지워도 옛 번호를 받지 않는다).
    for tag in ["띠", "사건"] {
        let top = before.iter().filter(|(k, _)| k.starts_with(&format!("{tag} "))).map(|(_, id)| *id).max().unwrap();
        let fresh: Vec<(&String, &i64)> = after.iter().filter(|(k, _)| k.starts_with(&format!("{tag} b/"))).collect();
        assert!(!fresh.is_empty(), "{tag}");
        for (uid, id) in fresh {
            assert!(*id > top, "{uid}가 지우기 전 번호({id} ≤ {top})를 받음");
        }
    }
    let want = same(&path, &["a", "b", "c"], "ap-add-b", false);
    same_records(&path, &want, "b 더하기");
}

/// 손본 배치로 통째로 지은 저장소.
fn full_of(p: &serde_json::Value, set: &[&str], name: &str) -> std::path::PathBuf {
    let path = common::scratch(name);
    import_layout_value(p, &packs_of(set), &path).unwrap();
    path
}

/// 손본 배치를 그 조합의 원본과 함께 넣는다.
fn step_of(path: &std::path::Path, p: &serde_json::Value, set: &[&str]) -> ApplyReport {
    let o = packs_of(set);
    write(path, |tx| apply(tx, &ApplyIn { plan: p, originals: &o, covers: Covers::All, remove: &[] })).unwrap()
}

#[test]
fn one_side_of_a_board_is_rewritten_and_the_other_side_is_found_in_the_store() {
    // (가) 판의 이름만 바뀜 → 판만 다시 쓴다: 판이 가리는 ta의 칸 · 관계선(하위 배치 밖)은 저장소에서 **내용**으로 찾고(판정 R19),
    //      다시 쓰지 않은 ta의 판 칸이 단 변형 번호(view:a1)는 판 변형이 옛 번호를 이어 써 그대로 맞는다(얹힌 몫 2).
    let path = full(&["a", "c"], "ap-board-only");
    let before = common::uid_ids(&path);
    let mut p = plan(&["a", "c"]);
    p["boards"]["variants"][0]["name"] = serde_json::json!("가 다시 모아 보기");
    let r = step_of(&path, &p, &["a", "c"]);
    assert_eq!(r.rewrote, vec![BOARD.to_string()]);
    assert_eq!(common::uid_ids(&path), before);
    let want = full_of(&p, &["a", "c"], "ap-board-only-full");
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
    // (나) 판이 아무것도 가리지 않는 장면에서 ta만 다시 쓴다(색 바꿈) → ta의 판 칸이 단 view:a1(하위 배치 밖 변형 — `outer.variants`)을
    //      저장소에서 열쇠로 푼다(판정 R16 가).
    let unhide = |set: &[&str]| { let mut p = plan(set); p["boards"]["variants"][0]["hides"] = serde_json::json!([]); p };
    let path = full_of(&unhide(&["a", "c"]), &["a", "c"], "ap-ta-only");
    let r = step_of(&path, &unhide(&["a@2", "c"]), &["a@2", "c"]);
    assert_eq!(r.rewrote, vec!["ta".to_string()]);
    let want = full_of(&unhide(&["a@2", "c"]), &["a@2", "c"], "ap-ta-only-full");
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
}

#[test]
fn a_new_event_wins_ties_by_layout_order_not_by_number() {
    // 얹힌 몫 4(판정 R9 · R23): ta의 사건 맨 앞에 새 uid의 사건(중요도 3)을 끼운다 — 다시 쓴 ta에서 새 uid는 가장 큰 번호를 받지만 트랙 안 차례는 0이라,
    // 같은 통의 중요도 3 사건들과의 동률을 번호로 깨면 대표에서 밀리고(통째 짓기에서는 맨 앞) 차례로 깨면 통째 짓기와 같다.
    let path = full(&["a", "c"], "ap-ord");
    let mut p = plan(&["a", "c"]);
    let mut first = p["events"][0].clone();
    first["uid"] = serde_json::json!("a/e-first");
    first["title"] = serde_json::json!("가 맨 앞 일");
    first["importance"] = serde_json::json!(3);
    p["events"].as_array_mut().unwrap().insert(0, first);
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.rewrote.contains(&"ta".to_string()));
    let want = full_of(&p, &["a", "c"], "ap-ord-full");
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
}

#[test]
fn merged_summaries_break_ties_by_the_stored_in_track_order() {
    // 판정 R24: 성긴 단계의 요약은 자료집마다 대표 넷을 미리 골라 두고 타일이 합친다. ta 맨 앞에 b의 새 사건(중요도 3 · 1250년 몰린 날)을 끼우면
    // 다시 쓴 ta에서 그 사건은 가장 큰 번호를 받지만 트랙 안 차례는 0 — 합칠 때 동률을 요약에 실린 트랙 안 차례(`summaries.ords`)로 깨야
    // a의 중요도 3 사건들을 앞질러 통째 짓기와 같다(번호로 깨면 밀린다). 사건 표는 읽지 않는다.
    let path = full(&["a", "b"], "ap-merge");
    let mut p = plan(&["a", "b"]);
    let start = p["events"][0]["start"].as_i64().unwrap() + 5 * 1440;
    p["events"].as_array_mut().unwrap().insert(0, serde_json::json!({"uid":"b/e-first","track":0,"row":0,"start":start,"end":start,"importance":3,
        "title":"나 맨 앞 일","body":"","look":0,"label":"","rail":0,"band":"a/ta-1"}));
    let r = step_of(&path, &p, &["a", "b"]);
    assert!(r.rewrote.contains(&"ta".to_string()));
    let want = full_of(&p, &["a", "b"], "ap-merge-full");
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
}

/// 한 줄에 두 트랙의 사건이 모이는 장면(판정 R23): ta의 사건 끝에 c/e0과 같은 분(1450년)에 중요도 1 사건 넷(`a/cl0` ~ `a/cl3` · ta의 줄 3)을 두고,
/// ta 맨 앞에 새 사건 `front`개(`a/new<i>`)를 끼운다. 대범위 모아 보기(`scope:c/sc-1`)를 켜면 c/tc-1 띠가 ta의 줄 3으로 이사해 c/e0(중요도 1)이
/// a/cl*와 한 통에 모인다 — 대표 넷의 자리를 다섯이 같은 중요도로 다툰다.
fn crowded(set: &[&str], front: usize) -> serde_json::Value {
    let mut p = plan(set);
    let events = p["events"].as_array_mut().unwrap();
    let at = events.iter().position(|e| e["track"] != 0).unwrap_or(events.len());
    let start = events.iter().find(|e| e["uid"] == "c/e0").expect("장면에 c가 있어야 합니다")["start"].as_i64().unwrap();
    let one = |uid: String, row: i64, start: i64, band: &str| serde_json::json!({"uid":uid,"track":0,"row":row,"start":start,"end":start,"importance":1,
        "title":format!("가 모인 일 {uid}"),"body":"","look":0,"label":"","rail":0,"band":band});
    for i in 0..4 {
        events.insert(at + i, one(format!("a/cl{i}"), 3, start, ""));
    }
    for i in 0..front {
        events.insert(i, one(format!("a/new{i}"), 0, common::plans::yr(1001) + i as i64, "a/ta-1"));
    }
    p
}

#[test]
fn an_untouched_track_keeps_its_place_in_a_shared_row_after_a_rewrite() {
    // 판정 R23: ta 맨 앞에 사건 둘을 끼워 ta만 다시 쓴다(tc는 그대로). 대표의 동률을 (트랙 차례, 트랙 안 차례)로 깨야 tc의 차례가 낡지 않아
    // 모아 보기에서 한 통에 모인 a/cl* · c/e0 가운데 대표가 통째 짓기와 같다(배치 안 차례 하나로 깨면 tc의 낡은 차례가 a/cl3을 앞지른다).
    let path = full_of(&crowded(&["a", "c"], 0), &["a", "c"], "ap-rank");
    let p = crowded(&["a", "c"], 2);
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.rewrote.contains(&"ta".to_string()) && !r.rewrote.contains(&"tc".to_string()), "{:?}", r.rewrote);
    let want = full_of(&p, &["a", "c"], "ap-rank-full");
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
}

/// 같은 해 보기(`same_year` — 앞뒤 범위 없이)의 사건 차례를 uid로: 창 목록(`events`)과 트랙마다의 목록(`tracks[].events` — 트랙 이름과 함께).
fn same_year_uids(path: &std::path::Path, at: i64) -> serde_json::Value {
    let store = archive_engine::Store::open(path).unwrap();
    let v = store.call(&serde_json::json!({"op":"same_year","at":at,"window":0})).unwrap();
    let uids = |list: &serde_json::Value| list.as_array().unwrap().iter().map(|e| e["uid"].clone()).collect::<Vec<_>>();
    let tracks: Vec<serde_json::Value> = v["tracks"].as_array().unwrap().iter().map(|t| serde_json::json!([t["name"], uids(&t["events"])])).collect();
    serde_json::json!({"events":uids(&v["events"]),"tracks":tracks})
}

#[test]
fn same_year_breaks_ties_by_track_then_in_track_order_like_a_full_build() {
    // 과제 perf(11a old-dlc-check — 동아시아 + dep-scene + d7-test의 임진왜란 ↔ 한산도 대첩): 같은 때(· 같은 중요도)의 사건이 번호로만 갈렸다.
    // ta 맨 앞에 새 사건 둘을 끼워 ta만 다시 쓴다 — 새 uid는 가장 큰 번호를 받지만 (트랙 차례, 트랙 안 차례)는 앞이다. `a/tie-c`는 tc의 c/e0과
    // 같은 분(트랙 사이 동률 — 창 목록), `a/tie-a`는 ta 첫 사건과 같은 분 · 중요도(트랙 안 동률 — 트랙마다 12개 목록). 번호로 깨면 통째 짓기와 갈린다.
    let path = full(&["a", "c"], "ap-same-year");
    let mut p = plan(&["a", "c"]);
    let events = p["events"].as_array_mut().unwrap();
    let c0 = events.iter().find(|e| e["uid"] == "c/e0").expect("장면에 c/e0이 있어야 합니다")["start"].as_i64().unwrap();
    let first = events[0].clone();
    assert_eq!(first["track"], 0, "배치의 첫 사건은 ta의 것");
    let mut tie_a = first.clone();
    tie_a["uid"] = serde_json::json!("a/tie-a");
    tie_a["title"] = serde_json::json!("가 같은 때 일");
    let tie_c = serde_json::json!({"uid":"a/tie-c","track":0,"row":0,"start":c0,"end":c0,"importance":1,"title":"가 다와 같은 때 일","body":"",
        "look":0,"label":"","rail":0,"band":""});
    events.insert(0, tie_c);
    events.insert(0, tie_a);
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.rewrote.contains(&"ta".to_string()) && !r.rewrote.contains(&"tc".to_string()), "{:?}", r.rewrote);
    let want = full_of(&p, &["a", "c"], "ap-same-year-full");
    for (at, tie) in [(c0, ["a/tie-c", "c/e0"]), (first["start"].as_i64().unwrap(), ["a/tie-a", first["uid"].as_str().unwrap()])] {
        let (got, expect) = (same_year_uids(&path, at), same_year_uids(&want, at));
        // 견줄 동률이 실제로 답에 있는가(같은 것이 비어서 같은 것이 아니게).
        let text = expect.to_string();
        assert!(tie.iter().all(|uid| text.contains(&format!("\"{uid}\""))), "{at}: 동률 {tie:?}가 답에 없음 — {text}");
        assert_eq!(got, expect, "same_year {at}");
        // 동률의 방향(perf 검토 Minor 1 — 통째 짓기와 같다는 것만으로는 둘 다 거꾸로여도 통과): 두 동률 모두 tie[0]이 앞이다 —
        // 트랙 사이(ta가 tc보다 앞 트랙) · 트랙 안(a/tie-a가 배치에서 ta 첫 사건보다 앞). 둘이 함께 든 목록(창 목록 · 트랙마다)마다 본다.
        let lists = std::iter::once(&got["events"]).chain(got["tracks"].as_array().unwrap().iter().map(|t| &t[1]));
        let mut seen = 0;
        for list in lists {
            let at_of = |uid: &str| list.as_array().unwrap().iter().position(|u| u == uid);
            if let (Some(i), Some(j)) = (at_of(tie[0]), at_of(tie[1])) {
                assert!(i < j, "same_year {at}: 동률 {tie:?}의 차례가 거꾸로(트랙 차례 · 트랙 안 차례가 앞인 것이 먼저) — {list}");
                seen += 1;
            }
        }
        assert!(seen > 0, "same_year {at}: 동률 {tie:?}가 함께 든 목록이 없음 — {got}");
    }
}

/// 그 저장소에서 사건을 번호 차례로 훑어 (사건 제 줄의 트랙 차례, 트랙 안 차례)가 늘 커지는가 — 어긋난 수와 첫 예.
fn order_breaks(path: &std::path::Path) -> (usize, Option<String>) {
    let db = rusqlite::Connection::open(path).unwrap();
    let mut stmt = db.prepare("SELECT e.id,t.ord,e.ord,e.uid,e.variant FROM events e JOIN rows r ON r.id=e.lane JOIN tracks t ON t.id=r.track ORDER BY e.id").unwrap();
    let rows: Vec<(i64, i64, i64, String, i64)> = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).unwrap().map(Result::unwrap).collect();
    let (mut bad, mut first) = (0, None);
    for pair in rows.windows(2) {
        let ((_, t0, o0, _, _), (id, t1, o1, uid, variant)) = (&pair[0], &pair[1]);
        if (t1, o1) <= (t0, o0) {
            bad += 1;
            first.get_or_insert_with(|| format!("사건 {id} «{uid}»(변형 {variant}) — (트랙 {t1}, 차례 {o1}) ≤ 앞 사건의 (트랙 {t0}, 차례 {o0})"));
        }
    }
    (bad, first)
}

#[test]
fn full_builds_order_events_by_track_then_in_track_order_like_their_numbers_r26() {
    // 판정 R23 · R26: 새로 지은 저장소에서 (트랙 차례, 트랙 안 차례) 차례 = 사건 번호 차례여야 동률 열쇠를 바꾼 뒤에도 타일 바이트가 그대로다
    // (배치의 사건은 트랙 차례로 묶여 나온다 — 내보내기 `events.mjs`). 내보내기가 변형에서만 있는 사건을 끝에 붙이므로, 그런 사건이 앞 트랙의 것이면
    // 여기서 깨져 알린다.
    const R26: &str = "변형 전용 사건이면 열쇠 앞에 바탕/변형 구분을 더할 것(판정 R26)";
    let sets: [&[&str]; 9] = [&["a"], &["a@2"], &["a", "b"], &["a", "c"], &["a", "b", "c"], &["a", "c", "b"], &["a@2", "c"], &["a@2", "b", "c"], &["a@2", "c", "b"]];
    for set in sets {
        let path = full(set, &format!("ap-order-{}", set.join("-").replace('@', "v")));
        let (bad, first) = order_breaks(&path);
        assert_eq!(bad, 0, "장면 {set:?}: 사건 번호 차례와 (트랙 차례, 트랙 안 차례)가 {bad}곳 어긋남 — 첫 예 {first:?} · {R26}");
    }
    // 정답지 자료(`prototype/fixtures/oracle/list.json`) — 내보내기 출력(`prototype/results/oracle/<자료>/upto-lens.json` · git 밖)이 있는 것만.
    let mut read = 0;
    for f in common::oracle::fixtures() {
        let Some(path) = oracle_store(&f.name, "ap-order-oracle") else { continue };
        let (bad, first) = order_breaks(&path);
        assert_eq!(bad, 0, "정답지 자료 {}: 사건 번호 차례와 (트랙 차례, 트랙 안 차례)가 {bad}곳 어긋남 — 첫 예 {first:?} · {R26}", f.name);
        read += 1;
    }
    assert!(read > 0, "정답지 자료의 내보내기 출력을 하나도 읽지 못했습니다 — node prototype/scripts/layout-oracle.mjs로 뽑으세요");
    eprintln!("정답지 자료 {read}벌을 견줌");
}

#[test]
fn names_respread_in_place_equal_the_full_build_on_real_data() {
    // 과제 6: 실자료(정답지 자료의 내보내기 출력 — 동아시아 기본팩 · KoreanTimeLine · 등불 연대기)로 지은 저장소에서 이름 표 · 관점 이름을 제자리에서
    // 다시 펴면(`rebuild_names`) 짓기가 편 것과 번호 차례까지 줄 하나하나 같다 — 가문 · 단체 · 제도의 넣은 차례 · 찾을 글 · 날짜 칸 주인 · 빌린 줄.
    // 걸린 시간을 찍는다(보고: 동아시아 규모의 rebuild_names ms).
    let dump = |p: &std::path::Path| -> (Vec<String>, Vec<String>, String, String) {
        let db = rusqlite::Connection::open(p).unwrap();
        let rows = |sql: &str| -> Vec<String> { db.prepare(sql).unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect() };
        let names = rows("SELECT json_array(id,pack,kind,uid,name,sub,cell,start,end,row,color,cell_ref,hay) FROM names ORDER BY id");
        let lens = rows("SELECT json_array(uid,track,name,pack) FROM lens_names ORDER BY uid,track");
        let m = meta(p);
        (names, lens, m["names"].clone(), m["lens_names"].clone())
    };
    let mut read = 0;
    for name in ["east-asia", "east-asia+ktl", "lantern"] {
        let Some(path) = oracle_store(name, "ap-names-oracle") else { continue };
        let before = dump(&path);
        assert!(!before.0.is_empty(), "{name}: 이름 표가 비었습니다");
        let ((names, lens), ms) = write(&path, |tx| {
            let started = std::time::Instant::now();
            let counts = archive_engine::builder::rebuild_names(tx)?;
            Ok((counts, started.elapsed().as_secs_f64() * 1000.0))
        }).unwrap();
        eprintln!("{name}: 이름 표 {names} · 관점 이름 {lens} · 항목 기록 {} — rebuild_names {ms:.1} ms", meta(&path)["entities"]);
        assert_eq!((names.to_string(), lens.to_string()), (before.2.clone(), before.3.clone()), "{name}: 줄 수");
        assert!(dump(&path) == before, "{name}: 다시 편 이름 표 · 관점 이름이 짓기가 편 것과 다릅니다");
        read += 1;
    }
    assert!(read > 0, "정답지 자료의 내보내기 출력을 하나도 읽지 못했습니다 — node prototype/scripts/layout-oracle.mjs로 뽑으세요");
}

/// 정답지 자료 하나의 내보내기 출력(`prototype/results/oracle/<자료>/upto-lens.json` · git 밖)을 통째로 지은 저장소. 그 자료가 이 PC에 없으면(선택 자료) None —
/// 정답지 파일이 없거나 낡았으면 멈춘다(`oracle_named` — 판정 R58 ⑤ Minor: 예전엔 파일을 바로 읽어 없으면 건너뛰고 낡아도 견줬다).
fn oracle_store(name: &str, tag: &str) -> Option<std::path::PathBuf> {
    let p = common::oracle::oracle_named(name, "upto-lens.json")?;
    let packs: Vec<archive_engine::legacy::PackPlan> = p["packs"].as_array().into_iter().flatten().map(|d| archive_engine::legacy::PackPlan {
        key: d["id"].as_str().map(str::to_owned), name: d["name"].as_str().or(d["id"].as_str()).unwrap_or("자료집").to_owned(),
        version: d["version"].as_str().unwrap_or("").to_owned(), category: d["category"].as_str().unwrap_or("").to_owned(), original: None,
    }).collect();
    let path = common::scratch(&format!("{tag}-{}", name.replace(['@', '+'], "_")));
    let mut b = archive_engine::builder::Builder::create(&path).unwrap();
    archive_engine::legacy::fill_into(&mut b, &p, packs, archive_engine::legacy::FillHow::All).unwrap_or_else(|e| panic!("{name}: {e}"));
    b.finalize(&[]).unwrap();
    Some(path)
}

#[test]
fn a_covering_layout_without_the_hider_is_refused() {
    // 얹힌 몫 10: 덮는 트랙만 주는 배치(메이커)가 ta를 다시 쓰는데 ta를 가리는 판 트랙이 배치에 없으면 판의 가림(variant_hides)이
    // 지운 칸 · 항목을 가리키게 된다 — 거절하고 파일은 그대로.
    let path = full(&["a", "c"], "ap-hider-missing");
    let before = common::sha256_file(&path);
    let mut p = plan(&["a@2", "c"]);
    p.as_object_mut().unwrap().remove("boards");
    let o = packs_of(&["a@2", "c"]);
    let covers = Covers::Tracks(["ta".to_string()].into_iter().collect());
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap_err().to_string();
    assert!(err.contains(BOARD) && err.contains("가리는 트랙도 함께"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
}

/// `apply`의 걸음 이름(`patch.rs`의 `fail_point` 차례 그대로) — 걸음마다 실패를 주입하는 검사가 모든 걸음을 덮는다.
const STEPS: [&str; 15] = ["choose", "packs", "delete", "insert", "relink", "globals", "entities", "summaries", "range", "order", "renumber", "names", "prints", "meta", "verify"];

#[test]
fn the_step_list_covers_every_fail_point() {
    // 걸음을 더하거나 이름을 바꾸면 이 목록도 바꿔야 걸음마다 실패 검사가 그 걸음을 잰다.
    let source = include_str!("../src/patch.rs");
    let found: Vec<&str> = source.match_indices("fail_point(\"").map(|(at, m)| {
        let rest = &source[at + m.len()..];
        &rest[..rest.find('"').unwrap()]
    }).collect();
    assert_eq!(found, STEPS.to_vec());
}

#[test]
fn failure_while_rewriting_leaves_the_file_as_it_was() {
    // 과제 5c의 걸음(지우고 넣기 · 옮겨 적기)과 5d의 걸음(온 판 · 항목 기록 · 범위 · 표본 대조)을 포함해 걸음마다 실패를 주입한다.
    for at in STEPS {
        let path = full(&["a", "c"], &format!("ap-fail-re-{at}"));
        let before = common::sha256_file(&path);
        archive_engine::write::set_fail_point(Some(at));
        let (p, o) = (plan(&["a@2", "c"]), packs_of(&["a@2", "c"]));
        let got = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] }));
        archive_engine::write::set_fail_point(None);
        assert_eq!(got.unwrap_err().to_string(), format!("실패 주입: {at}"), "{at}에서 주입한 실패로 멈춰야 함");
        assert_eq!(common::sha256_file(&path), before, "{at}에서 실패한 뒤 파일이 바뀜");
    }
}

#[test]
fn adding_a_track_counts_and_records_like_a_full_build() {
    let path = full(&["a"], "ap-add-meta");
    let r = step(&path, &["a", "c"], &[]);
    let want = full(&["a", "c"], "ap-add-meta-full");
    // tc는 ta의 다섯 줄 뒤 · 판 트랙의 두 줄 앞에 든다(열쇠는 끝에 붙어 자리와 갈린다 — 판 '4.1').
    assert_eq!((r.globals, r.first_pos, r.rows_before, r.rows_after), (true, 5, 7, 9));
    assert_eq!(meta(&path)["schema"], "4.1");
    // 수 세기 · 보는 범위 · 자료집 메타 · 온 판 메타(모든 열쇠 — 얹힌 몫 15) · 항목 기록(넣은 차례까지 — 과제 5d의 "entities").
    same_meta(&path, &want, "tc 더하기");
    same_entities(&path, &want, "tc 더하기");
    // 지문: 새 트랙 · 온 판이 새 배치의 것으로 — 같은 배치를 다시 넣으면 고를 것이 없다.
    let prints = "SELECT key,print FROM track_prints ORDER BY key";
    assert_eq!(pairs(&path, prints), pairs(&want, prints));
}

#[test]
fn covered_tracks_put_a_new_track_after_its_neighbour() {
    // 메이커 배치(`Covers::Tracks`)는 덮는 트랙 밖의 차례를 그대로 두고, 새 트랙은 새 배치에서 바로 앞 트랙(ta) 뒤에 든다.
    let path = full(&["a"], "ap-covers");
    let (p, o) = (plan(&["a", "c"]), packs_of(&["a", "c"]));
    let covers = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap();
    assert_eq!(r.added, vec!["tc".to_string()]);
    let order: Vec<String> = pairs(&path, "SELECT key,'' FROM tracks ORDER BY ord,id").into_iter().map(|(k, _)| k).collect();
    assert_eq!(order, vec!["ta", "tc", "__board:view:a1"]);
    // 과제 6 고침(Minor 2): 덮는 트랙만 주는 배치가 받아들여지는 길에서도 새 트랙(tc)의 항목 기록이 들고 이름 표 · 관점 이름이 다시 펴진다 —
    // 이 장면은 덮지 않는 트랙의 기록 차례가 배치와 같아 통째 짓기와 같은 이름 표가 나온다(가문 · 단체 차례 포함).
    assert!(r.names, "새 트랙이 들면 이름 표를 다시 편다");
    let records = pairs(&path, "SELECT uid,kind FROM entities WHERE uid LIKE 'c/%' ORDER BY uid");
    assert_eq!(records, [("c/grp-1", "group"), ("c/tc-1", "period"), ("c/tc-2", "period")].map(|(u, k)| (u.to_string(), k.to_string())).to_vec());
    let want = full(&["a", "c"], "ap-covers-full");
    assert_eq!(name_rows(&path), name_rows(&want));
    for word in ["모임", "나라"] {
        assert_eq!(wide_hits(&path, word), wide_hits(&want, word), "넓힌 검색 {word}");
    }
}

#[test]
fn failure_at_any_step_leaves_the_file_as_it_was() {
    // 새 트랙 둘(b · c)과 b가 ta에 얹는 것(ta 다시 씀)을 한 번에 — 지울 것이 없어도 모든 걸음을 지난다. canon은 돌리지 않는다(파일 SHA-256만).
    for at in STEPS {
        let path = full(&["a"], &format!("ap-fail-{at}"));
        let before = common::sha256_file(&path);
        archive_engine::write::set_fail_point(Some(at));
        let (p, o) = (plan(&["a", "b", "c"]), packs_of(&["a", "b", "c"]));
        let got = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] }));
        archive_engine::write::set_fail_point(None);
        assert_eq!(got.unwrap_err().to_string(), format!("실패 주입: {at}"), "{at}에서 주입한 실패로 멈춰야 함");
        assert_eq!(common::sha256_file(&path), before, "{at}에서 실패한 뒤 파일이 바뀜");
    }
}

#[test]
fn a_layout_without_now_dates_the_store_today() {
    // Node 배치는 `now`를 싣지 않는다 — 통째 짓기처럼 apply 뒤 `meta.now`는 오늘이어야 한다(계획 정한 것 #9).
    let path = common::scratch("ap-now");
    let mut old = plan(&["a"]);
    old["now"] = serde_json::json!("2000-01-01T00:00:00Z");
    import_layout_value(&old, &packs_of(&["a"]), &path).unwrap();
    step(&path, &["a", "c"], &[]);
    let now = meta(&path)["now"].clone();
    assert_ne!(now, "2000-01-01T00:00:00Z", "apply 뒤에도 옛 날짜");
    let b = now.as_bytes();
    assert!(b.len() == 20 && b[4] == b'-' && b[7] == b'-' && b[10] == b'T' && b[13] == b':' && b[16] == b':' && b[19] == b'Z'
        && [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18].iter().all(|i| b[*i].is_ascii_digit()), "ISO 꼴이 아님: {now}");
    // 배치가 `now`를 주면 그 글 그대로.
    let (mut p, o) = (plan(&["a", "c"]), packs_of(&["a", "c"]));
    p["now"] = serde_json::json!("2026-10-16T12:00:00+09:00");
    write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
    assert_eq!(meta(&path)["now"], "2026-10-16T12:00:00+09:00");
}

/// 그 조합의 배치에 그림 바이트 둘(`img:a/…` — 기본팩 a의 것)을 싣는다.
fn with_pictures(set: &[&str], first: &str, second: Option<&str>) -> serde_json::Value {
    let mut p = plan(set);
    let mut blobs = vec![serde_json::json!({"key":"img:a/one","pack":0,"mime":"image/png","data":archive_engine::base64_encode(first.as_bytes())})];
    if let Some(second) = second {
        blobs.push(serde_json::json!({"key":"img:a/two","pack":0,"mime":"image/webp","data":archive_engine::base64_encode(second.as_bytes())}));
    }
    p["blobs"] = serde_json::json!(blobs);
    p
}

#[test]
fn pictures_are_compared_to_the_byte() {
    // 그림 바이트는 온 판이다(얹힌 몫 3): (열쇠, 자료집 글자 id, 종류, 바이트의 SHA-256)으로 견주어 바뀐 · 새 · 빠진 그림만 고친다 —
    // 결과의 그림 표가 그 배치를 통째로 지은 것과 바이트까지 같다.
    let o = packs_of(&["a", "c"]);
    let blobs = |p: &std::path::Path| pairs(p, "SELECT key,pack||'|'||mime||'|'||hex(bytes) FROM blobs ORDER BY key");
    let cases = [
        ("바이트만 바뀜", ("첫 그림", Some("둘째 그림")), ("다른 첫 그림", Some("둘째 그림"))),
        ("하나가 빠짐", ("첫 그림", Some("둘째 그림")), ("첫 그림", None)),
        ("하나가 듦", ("첫 그림", None), ("첫 그림", Some("둘째 그림"))),
        ("그대로", ("첫 그림", Some("둘째 그림")), ("첫 그림", Some("둘째 그림"))),
    ];
    for (i, (tag, (b1, b2), (a1, a2))) in cases.into_iter().enumerate() {
        let path = common::scratch(&format!("ap-pictures-{i}"));
        import_layout_value(&with_pictures(&["a"], b1, b2), &packs_of(&["a"]), &path).unwrap();
        let p = with_pictures(&["a", "c"], a1, a2);
        let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
        assert_eq!(r.added, vec!["tc".to_string()], "{tag}");
        let want = full_of(&p, &["a", "c"], &format!("ap-pictures-{i}-full"));
        assert_eq!(blobs(&path), blobs(&want), "{tag}");
        same_meta(&path, &want, tag);
    }
}

/// 옛 검색(사건만)으로 찾은 사건 uid — 답의 차례 그대로(같은 사건이 두 번 나오면 두 번).
fn plain_hits(path: &std::path::Path, word: &str) -> Vec<String> {
    let store = archive_engine::Store::open(path).unwrap();
    let v = store.call(&serde_json::json!({"op":"search","text":word})).unwrap();
    let db = rusqlite::Connection::open(path).unwrap();
    v["items"].as_array().unwrap().iter()
        .map(|it| db.query_row("SELECT uid FROM events WHERE id=?1", [it["id"].as_i64().unwrap()], |r| r.get(0)).unwrap()).collect()
}

/// 넓힌 검색(이름까지 — 모든 갈래)의 답 — 사건 번호(`id`)만 빼고 답 그대로(줄은 자리 · 차례는 답의 차례 · 가문 · 단체 · 제도는 넣은 차례).
fn wide_hits(path: &std::path::Path, word: &str) -> Vec<serde_json::Value> {
    let store = archive_engine::Store::open(path).unwrap();
    let v = store.call(&serde_json::json!({"op":"search","text":word,"kinds":archive_engine::query::SEARCH_KINDS,"limit":200})).unwrap();
    v["items"].as_array().unwrap().iter().map(|it| {
        let mut it = it.clone();
        it.as_object_mut().unwrap().remove("id");
        it
    }).collect()
}

/// 같음의 약속(설계 3-4): 어떤 차례로 넣고 빼도 그 조합을 통째로 지은 것과 같다 — canon(단계를 줄인 것 · 얹힌 몫 7 — 조회 목록까지: 검색 ·
/// 이름 찾기 · 관점 이름 · 항목 기록 전부 · 과제 6) · meta 전부(보는 범위 · 수 세기 · 이름 표 수 — 얹힌 몫 6 · 15) · 검색 낱자 · 사건의 트랙 안 차례 · 항목 기록.
/// 걸음마다 b의 사건 제목 낱말(`얹은` — `b/e-on0` · `b/e-on1`에만 있다)로 찾아, b가 없으면 안 나오고 있으면 두 사건이 한 번씩만 나오는지 본다
/// (contentless 본문 색인의 'delete'가 넣은 낱자와 어긋나면 지운 사건이 남거나 새 사건이 안 잡힌다 — 검토 초점 3). 이름까지 찾는 넓힌 검색(`늦은` —
/// b의 띠 · 칸 · 사건과 a의 단체)도 통째 짓기와 답 그대로 견준다. 길마다 검사 하나라 cargo가 넷을 함께 돌린다.
fn walk(w: usize, sets: &[&[&str]]) {
    let path = full(sets[0], &format!("ap-walk{w}"));
    for (i, set) in sets.iter().enumerate().skip(1) {
        let gone: Vec<String> = sets[i - 1].iter().filter(|p| !set.contains(p)).map(|p| p.to_string()).collect();
        step(&path, set, &gone);
        let tag = format!("ap-walk{w}-{i} {set:?}");
        let want = full(set, &format!("ap-walk{w}-{i}-full"));
        assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "{tag}: canon이 통째 짓기와 다릅니다");
        same_records(&path, &want, &tag);
        let hits = plain_hits(&path, "얹은");
        if set.contains(&"b") {
            assert_eq!(hits, vec!["b/e-on0", "b/e-on1"], "{tag}: b의 사건이 한 번씩 나와야 함");
        } else {
            assert!(hits.is_empty(), "{tag}: 뺀 b의 사건이 검색에 남음: {hits:?}");
        }
        assert_eq!(wide_hits(&path, "늦은"), wide_hits(&want, "늦은"), "{tag}: 넓힌 검색");
    }
}

#[test]
fn adding_b_then_c_matches_full_builds() {
    walk(0, &[&["a"], &["a", "b"], &["a", "b", "c"]]);
}

#[test]
fn adding_c_then_b_then_removing_b_matches_full_builds() {
    walk(1, &[&["a"], &["a", "c"], &["a", "b", "c"], &["a", "c"]]);
}

#[test]
fn removing_both_then_adding_them_back_matches_full_builds() {
    // 브리프 걸음 1: ["a","b","c"] → ["a"] → … → ["a","b","c"] — b의 낱말은 ["a"] 걸음에서 안 나오고 마지막 걸음에서 한 번씩만.
    walk(2, &[&["a", "b", "c"], &["a"], &["a", "b"], &["a", "b", "c"]]);
}

#[test]
fn adding_and_removing_back_and_forth_matches_full_builds() {
    walk(3, &[&["a", "b"], &["a", "b", "c"], &["a", "c"], &["a"], &["a", "c"]]);
}

#[test]
fn view_range_follows_the_packs() {
    // 얹힌 몫 6: 보는 범위(`meta.min` · `max`)는 canon 밖이라 따로 단언한다 — 넣으면 넓히고 빼면 남은 것에서 다시 잰다.
    let path = full(&["a"], "ap-range");
    let (min_a, max_a) = (common::meta_i64(&path, "min"), common::meta_i64(&path, "max"));
    step(&path, &["a", "b"], &[]);
    assert!(common::meta_i64(&path, "min") < min_a); // b가 범위를 넓힘(tb가 600년부터)
    step(&path, &["a"], &["b".to_string()]);
    assert_eq!(common::meta_i64(&path, "min"), min_a); // 빼면 다시 좁아짐
    assert_eq!(common::meta_i64(&path, "max"), max_a);
}

#[test]
fn store_from_before_this_plan_is_rewritten_once_in_place() {
    // 이 계획 전에 지은 저장소 흉내: 트랙 지문 · 항목 기록의 넣은 차례 · 지문 · meta.now · 사건 · 요약의 트랙 안 차례가 없다(옛 DLC의 약속 2).
    let path = full(&["a", "c"], "ap-old");
    // track_prints · blobs 표 · entities.ord/sum 열 · meta.now · events.ord · summaries.ords · periods_row를 지움
    common::strip_new_columns(&path);
    // 얹힌 몫 13: 열이 없을 때 읽는 길(열 가림 · NO_ORD) — 첫 apply 전에도 통째 짓기와 같다. 이 계획 전 저장소는 스키마 4 전이기도 해(판 3 — 띠 form 열 ·
    // 문화권 단위 줄 표 없음 · 리메이크 3단계) 새 값을 지운 통째 짓기(form 0 · 줄 없음)와 견준다(`tests/schema4.rs`와 같은 눈).
    assert!(!common::has_column(&path, "events", "ord") && !common::has_column(&path, "summaries", "ords") && !common::has_column(&path, "entities", "sum"));
    assert!(!common::has_column(&path, "periods", "form") && common::index_sql(&path, "sphere_lines").is_empty() && meta(&path)["schema"] == "3");
    let zero = full(&["a", "c"], "ap-old-before-zero");
    rusqlite::Connection::open(&zero).unwrap().execute_batch("UPDATE periods SET form=0; DELETE FROM sphere_lines;").unwrap();
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&zero, &opts(false)).unwrap(), "첫 apply 전의 판 3 저장소");
    let r = step(&path, &["a", "b", "c"], &[]);
    assert_eq!(r.rewrote.len() + r.added.len(), common::track_count(&path)); // 지문이 없으니 모든 트랙을 한 번 다시 씀
    // 열 · 표 · 색인이 생겼고 덮는 색인은 트랙 안 차례(ord)까지 다시 지었다(얹힌 몫 11) · '오늘'이 적혔다(얹힌 몫 5) · 판 4로 적혔다(리메이크 3단계).
    for (table, column) in [("events", "ord"), ("summaries", "ords"), ("entities", "ord"), ("entities", "sum"), ("periods", "form")] {
        assert!(common::has_column(&path, table, column), "{table}.{column}");
    }
    for name in ["track_prints", "periods_row", "blobs", "sphere_lines"] {
        assert!(!common::index_sql(&path, name).is_empty(), "{name}");
    }
    assert!(["4", "4.1"].contains(&meta(&path)["schema"].as_str()), "판: {}", meta(&path)["schema"]);
    assert!(common::index_sql(&path, "events_time").contains(",ord)"), "덮는 색인: {}", common::index_sql(&path, "events_time"));
    // 5d 검토: 덮는 색인을 다시 지으면(DROP INDEX가 sqlite_stat1의 그 줄을 지운다) 그 색인의 통계를 다시 잰다 — 촘촘한 단계의 조회 계획이 그대로이게.
    let stats: i64 = rusqlite::Connection::open(&path).unwrap()
        .query_row("SELECT count(*) FROM sqlite_stat1 WHERE idx='events_time'", [], |r| r.get(0)).unwrap();
    assert_eq!(stats, 1, "덮는 색인의 통계(sqlite_stat1)");
    assert!(meta(&path).contains_key("now"));
    // 과제 6: 검색 · 이름 찾기(가문 · 단체 차례 포함) · 관점 이름 · 항목 기록까지 — 지은 날(meta.now)이 없던 저장소에서도(얹힌 몫 2).
    let want = same(&path, &["a", "b", "c"], "ap-old", true);
    same_records(&path, &want, "옛 저장소");
    let again = step(&path, &["a", "b", "c"], &[]);
    assert!(again.rewrote.is_empty() && !again.names); // 그 뒤부터는 바뀐 트랙만(이름 표도 그대로)
}

#[test]
fn same_layout_again_does_nothing() {
    let path = full(&["a", "b", "c"], "ap-again");
    let r = step(&path, &["a", "b", "c"], &[]);
    assert!(r.rewrote.is_empty() && r.added.is_empty() && r.removed.is_empty() && !r.globals);
    assert_eq!(r.first_pos, -1);
    assert!(!r.names, "바뀐 것이 없으면 이름 표 · 덧줄을 다시 펴지 않는다(과제 6)");
}

#[test]
fn missing_meta_keys_are_counted_like_a_full_build() {
    // 얹힌 몫 4: 수 세기 · 자료집별 수 · 보는 범위 · 부분 짓기 글의 열쇠가 없는 저장소는 조용히 건너뛰지 않고 그 표를 세어(다시 재어) 넣는다 —
    // 통째 짓기에는 늘 있는 열쇠다.
    let path = full(&["a"], "ap-missing-keys");
    rusqlite::Connection::open(&path).unwrap()
        .execute("DELETE FROM meta WHERE key IN ('groups','unknown','axis_cells','categories','pack_periods','pack_tracks','legacy','min')", []).unwrap();
    step(&path, &["a", "c"], &[]);
    let want = full(&["a", "c"], "ap-missing-keys-full");
    same_meta(&path, &want, "열쇠 없음");
}

#[test]
fn entities_are_compared_by_uid_and_print() {
    // 과제 5d의 "entities": 항목 기록은 트랙 주인과 상관없이 uid · 지문(`sum`)으로 모두 견주어 지움 · 바꿈 · 넣음, 넣은 차례(`ord`)는 새 배치의
    // 배열 차례로 다시 적는다(계획 정한 것 #6). 트랙 없는 기록(가문 · 인물)만 바뀐 배치는 다시 쓸 트랙이 없다.
    let path = full(&["a", "c"], "ap-entities");
    let mut p = plan(&["a", "c"]);
    let list = p["entities"].as_array_mut().unwrap();
    let at = |list: &[serde_json::Value], uid: &str| list.iter().position(|e| e["uid"] == uid).unwrap();
    let fig = at(list, "a/fig-1");
    list[fig]["json"] = serde_json::json!(serde_json::json!({"uid":"a/fig-1","name":"가람 사람","note":"고쳐 씀"}).to_string()); // 바꿈
    let gone = at(list, "house:a-bamboo");
    list.remove(gone); // 지움
    let zelkova = list.remove(at(list, "house:a-zelkova"));
    list.push(zelkova); // 차례만 바뀜
    list.insert(0, serde_json::json!({"uid":"a/new-fig","kind":"figure","pack":0,"json":"{\"uid\":\"a/new-fig\",\"name\":\"새 사람\"}"})); // 넣음
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.rewrote.is_empty() && r.added.is_empty(), "{r:?}");
    let want = full_of(&p, &["a", "c"], "ap-entities-full");
    same_entities(&path, &want, "항목 기록");
    same_meta(&path, &want, "항목 기록");
}

#[test]
fn global_tables_are_rewritten_like_a_full_build() {
    // 과제 5d의 "globals": 분류 · 시대 구분 · 공통 날짜 칸이 바뀐 배치(5b는 거절했다)를 받아 그 표만 지우고 다시 넣는다. 공통 날짜 칸이 앞으로
    // 넓어지면 보는 범위도 넓어진다. 분류 이름만 바꾸면 사건의 분류 번호(look)는 그대로라 트랙 지문은 같다.
    let path = full(&["a", "c"], "ap-globals");
    let mut p = plan(&["a", "c"]);
    p["categories"][1]["name"] = serde_json::json!("다툼");
    p["epochs"][0]["name"] = serde_json::json!("아주 이른 시대");
    p["axis"][0]["start"] = serde_json::json!(common::plans::yr(800));
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.globals && r.rewrote.is_empty() && r.added.is_empty(), "{r:?}");
    assert_eq!(r.first_pos, 0, "바뀐 것이 온 판뿐이면 첫 자리 0");
    let want = full_of(&p, &["a", "c"], "ap-globals-full");
    assert!(canon_store(&path, &quick()).unwrap() == canon_store(&want, &quick()).unwrap(), "온 판을 고친 뒤 canon이 다릅니다");
    same_meta(&path, &want, "온 판");
    assert_eq!(common::meta_i64(&path, "min"), common::plans::yr(800));
}

#[test]
fn refused_layouts_leave_the_file_as_it_was() {
    // 얹힌 몫 9: 5d 뒤에도 남는 Err 지킴마다 싼 검사 하나 — 거절하고 파일은 SHA-256까지 그대로.
    let o = packs_of(&["a", "c"]);
    let mut other_base = plan(&["a", "c"]);
    other_base["packs"][0]["id"] = serde_json::json!("z");
    let mut twin_keys = plan(&["a", "c"]);
    twin_keys["tracks"][1]["key"] = serde_json::json!("ta");
    let mut new_names = plan(&["a", "c"]);
    new_names["categories"][0]["name"] = serde_json::json!("새 다스림");
    let only_tc = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let cases: Vec<(&str, serde_json::Value, Vec<(String, Vec<u8>)>, Covers, Vec<String>, &str)> = vec![
        ("기본팩이 다름", other_base, o.clone(), Covers::All, vec![], "기본팩이 다릅니다"),
        ("얹은 DLC가 빠짐", plan(&["a"]), packs_of(&["a"]), Covers::All, vec![], "이 배치에 없습니다"),
        ("빼라는 DLC가 배치에 있음", plan(&["a", "c"]), o.clone(), Covers::All, vec!["c".to_string()], "배치에 있습니다"),
        ("깨진 배치(트랙 열쇠가 겹침)", twin_keys, o.clone(), Covers::All, vec![], "트랙 열쇠가 겹칩니다"),
        ("원본의 판이 배치와 다름", plan(&["a", "c"]), packs_of(&["a@2", "c"]), Covers::All, vec![], "판이 배치와 다릅니다"),
        ("덮는 트랙만 주는 배치가 분류를 바꿈", new_names, o.clone(), only_tc, vec![], "배치 전체를"),
    ];
    for (i, (tag, p, originals, covers, remove, says)) in cases.into_iter().enumerate() {
        let path = full(&["a", "c"], &format!("ap-refused-{i}"));
        let before = common::sha256_file(&path);
        let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &originals, covers, remove: &remove })).unwrap_err().to_string();
        assert!(err.contains(says), "{tag}: {err}");
        assert_eq!(common::sha256_file(&path), before, "{tag}: 거절한 뒤 파일이 바뀜");
    }
}

#[test]
fn a_store_failing_the_sample_check_is_left_as_it_was() {
    // 과제 5d의 "verify": COMMIT 전 표본 타일 대조(verify_store 120)가 누락 · 중복을 찾으면 되돌린다. 다시 쓰지 않는 트랙(tc)의 요약을
    // 미리 지워 둔 저장소에 ta만 다시 쓰는 배치를 넣는다 — 성긴 단계의 타일이 tc의 사건을 세지 못한다. a@2는 자료집 판이 바뀌어 온 판 지문이
    // 바뀌므로 표본은 저장소 전체에서 뜬다(판정 R29 가). 다시 쓰기만인 좁힌 길은 아래 `a_rewrite_only_apply_samples_its_block_and_both_edge_chunks`.
    let path = full(&["a", "c"], "ap-verify");
    rusqlite::Connection::open(&path).unwrap()
        .execute("DELETE FROM summaries WHERE lane IN (SELECT r.id FROM rows r JOIN tracks t ON t.id=r.track WHERE t.key='tc')", []).unwrap();
    let before = common::sha256_file(&path);
    let (p, o) = (plan(&["a@2", "c"]), packs_of(&["a@2", "c"]));
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap_err().to_string();
    assert!(err.contains("표본 타일") && err.contains("누락"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
}

#[test]
fn a_rewritten_track_restores_its_own_summaries_before_the_sample_check() {
    // 5d 검토(위 검사의 반대): 표본 대조는 **거래 안** 내용을 본다 — 다시 쓰는 트랙(ta)의 요약을 지워 둔 저장소에 ta를 다시 쓰는 a@2를 넣으면
    // 거래 안에서 요약이 다시 생겨 받는다(COMMIT 전의 저장소 파일로 대조하면 누락으로 되돌렸을 것이다). 이것도 온 판이 바뀌어 저장소 전체 표본(R29 가).
    let path = full(&["a", "c"], "ap-verify-own");
    rusqlite::Connection::open(&path).unwrap()
        .execute("DELETE FROM summaries WHERE lane IN (SELECT r.id FROM rows r JOIN tracks t ON t.id=r.track WHERE t.key='ta')", []).unwrap();
    assert!(!archive_engine::verify::verify_tiles(&path, 120).unwrap().ok(), "장면: 지운 요약이 표본 대조에 걸려야 함");
    let r = step(&path, &["a@2", "c"], &[]);
    assert!(r.rewrote.contains(&"ta".to_string()), "{:?}", r.rewrote);
    assert!(archive_engine::verify::verify_tiles(&path, 120).unwrap().ok());
}

/// 판정 R29 (나): 다시 쓰기만인 apply(덮는 트랙만 · 온 판 그대로 · 넣고 빼는 트랙 · 차례 바뀜 없음)는 표본을 다시 쓴 덩이와 그 덩이에 걸친
/// 앞뒤 끝 묶음에서 뜬다(과제 7c 고침 — 7c 첫 판은 덩이 안에 다 든 묶음만 떠 덩이의 첫 · 끝 줄이 대조되지 않았다).
/// 장면: `big(3, 21, 3150)` — 트랙마다 21줄이라 가운데 트랙 big-t1은 자리 21 ~ 41: 묶음 2(16 ~ 23 — t0의 끝 다섯 줄과 걸침) · 3 · 4 · 5(40 ~ 47 —
/// t2의 첫 여섯 줄과 걸침). 다시 쓴 트랙의 줄은 거래 안에서 새로 지어지므로, 걸친 묶음에 함께 놓인 이웃 줄의 요약을 지워 그 묶음을 보았는지 잰다.
#[test]
fn a_rewrite_only_apply_samples_its_block_and_both_edge_chunks() {
    let (p, o) = (big(3, 21, 3150), packs_of(&["big"]));
    let keys: std::collections::BTreeSet<String> = ["big-t1".to_string()].into_iter().collect();
    let mut sub = sub_plan(&p, &keys).unwrap();
    sub["tracks"][0]["color"] = serde_json::json!(0x5a7d9c); // 색만 바꿔 big-t1을 다시 쓴다(줄 수 · 자리는 그대로)
    let run = |name: &str, broken_lanes: Option<(i64, i64)>| -> Result<ApplyReport, String> {
        let path = common::scratch(name);
        import_layout_value(&p, &o, &path).unwrap();
        if let Some((k0, k1)) = broken_lanes {
            let gone = rusqlite::Connection::open(&path).unwrap().execute("DELETE FROM summaries WHERE lane BETWEEN ?1 AND ?2", [k0, k1]).unwrap();
            assert!(gone > 0, "{name}: 지울 요약이 없습니다");
            assert!(!archive_engine::verify::verify_tiles(&path, 120).unwrap().ok(), "{name}: 장면 — 저장소 전체 표본에는 걸려야 함");
        }
        let before = common::sha256_file(&path);
        let got = write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &o, covers: Covers::Tracks(keys.clone()), remove: &[] }));
        if got.is_err() {
            assert_eq!(common::sha256_file(&path), before, "{name}: 되돌린 뒤 파일이 바뀜");
        }
        got.map_err(|e| e.to_string())
    };
    let ok = run("ap-r29-ok", None).unwrap();
    assert_eq!((ok.rewrote.clone(), ok.added.len(), ok.globals), (vec!["big-t1".to_string()], 0, false), "다시 쓰기만인 apply여야 함");
    // 앞 끝 묶음(2)의 t0 줄 16 ~ 20 · 뒤 끝 묶음(5)의 t2 줄 42 ~ 47 — 둘 다 표본에 들어 되돌린다.
    for (name, lanes) in [("ap-r29-lead", (16, 20)), ("ap-r29-tail", (42, 47))] {
        let err = run(name, Some(lanes)).unwrap_err();
        assert!(err.contains("표본 타일") && err.contains("누락"), "{name}: {err}");
    }
    // 덩이에서 먼 t2의 줄 48 ~ 62(묶음 6 · 7)는 보지 않는다 — 좁힌 길을 실제로 지났다는 표지(저장소 전체에서 떴으면 걸렸다).
    assert!(run("ap-r29-far", Some((48, 62))).is_ok(), "다시 쓰기만인 apply가 저장소 전체에서 표본을 떴습니다");
}

#[test]
fn failure_at_any_step_on_an_old_store_leaves_the_file_as_it_was() {
    // 5d 검토: 이 계획 전에 지은 저장소의 첫 apply는 표 · 열 · 색인을 만든다(DDL) — 어느 걸음에서 실패해도 그 DDL까지 되돌려져 파일이 그대로다.
    for at in STEPS {
        let path = full(&["a", "c"], &format!("ap-fail-old-{at}"));
        common::strip_new_columns(&path);
        let before = common::sha256_file(&path);
        archive_engine::write::set_fail_point(Some(at));
        let (p, o) = (plan(&["a", "b", "c"]), packs_of(&["a", "b", "c"]));
        let got = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] }));
        archive_engine::write::set_fail_point(None);
        assert_eq!(got.unwrap_err().to_string(), format!("실패 주입: {at}"), "{at}에서 주입한 실패로 멈춰야 함");
        assert_eq!(common::sha256_file(&path), before, "{at}에서 실패한 뒤 파일이 바뀜");
    }
}

#[test]
fn an_emptied_store_ranges_like_a_full_build() {
    // 5d 검토: 남은 것이 하나도 없으면 보는 범위는 통째 짓기처럼 (0, 하루) — 다시 잴 것이 없을 때의 길.
    let empty = || {
        let mut p = plan(&["a"]);
        for key in ["tracks", "periods", "cells", "events", "items", "entities", "rowLabels", "variants", "axis", "epochs", "sphereLines"] {
            p[key] = serde_json::json!([]);
        }
        p.as_object_mut().unwrap().remove("boards");
        p
    };
    let path = full(&["a"], "ap-empty");
    step_of(&path, &empty(), &["a"]);
    assert_eq!((common::meta_i64(&path, "min"), common::meta_i64(&path, "max")), (0, archive_engine::DAY));
    let want = full_of(&empty(), &["a"], "ap-empty-full");
    same_meta(&path, &want, "빈 저장소");
}

#[test]
fn a_pack_without_its_original_is_noted_like_a_partial_build() {
    // 5d 검토: 원본 없이 든 DLC가 있으면 `meta.legacy`는 '원본 없는 DLC가 있음'(통째 짓기 `import_with`와 같은 글) — 그 원본을 받으면 '보존'으로 돌아간다.
    let path = full(&["a"], "ap-partial");
    let (p, o) = (plan(&["a", "c"]), packs_of(&["a"])); // c의 원본은 주지 않는다
    write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
    assert!(meta(&path)["legacy"].contains("원본 없는 DLC가 있음"), "{}", meta(&path)["legacy"]);
    step(&path, &["a", "c"], &[]);
    assert!(meta(&path)["legacy"].contains("원본 전용 팩 보존"), "{}", meta(&path)["legacy"]);
}

/// 형식 3을 잇기 전에 지은 저장소를 흉내 낸다 — 그런 저장소는 이 계획(P4) 전이기도 하므로 [`common::strip_new_columns`] 위에, 사건의 덧줄(본문 색인의
/// rowid −번호 — contentless라 넣은 낱자 그대로 'delete')과 사건 찾을 글 표(`event_hay`) · 이름 표의 찾을 글 · 칸 참조 열 · 관점 이름 표를 지운다
/// (과제 6 고침 Minor 5 — 덧줄을 남기면 그 표가 없는 저장소에 덧줄만 있는, 현실에 없는 꼴이 된다).
fn strip_format3(path: &std::path::Path) {
    common::strip_new_columns(path);
    let db = rusqlite::Connection::open(path).unwrap();
    let lines: Vec<(i64, String)> = db.prepare("SELECT id,hay FROM event_hay").unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    for (id, hay) in lines {
        let terms = archive_engine::grams(&hay);
        if !terms.is_empty() {
            db.execute("INSERT INTO search(search,rowid,terms) VALUES('delete',?1,?2)", rusqlite::params![-id, terms.join(" ")]).unwrap();
        }
    }
    db.execute_batch("DROP TABLE event_hay; ALTER TABLE names DROP COLUMN hay; ALTER TABLE names DROP COLUMN cell_ref; DROP TABLE lens_names;").unwrap();
}

#[test]
fn a_store_from_before_format3_gets_its_name_tables_back() {
    // 과제 6: 형식 3을 잇기 전에 지은 저장소(이름 표의 찾을 글 · 칸 참조 열 · 관점 이름 표 · 사건 찾을 글 표 · 덧줄이 없음)도 apply가 그 표 · 열을 만들고
    // 이름 표를 통째로 다시 펴고 덧줄을 적어 통째 짓기와 같아진다(지문 · 기록 지문이 없어 첫 apply가 모든 트랙 · 기록을 한 번 다시 쓴다).
    let path = full_of(&records(&["a", "c"], "옛 별칭"), &["a", "c"], "ap-f3");
    assert!(search_terms(&path).values().any(|hits| hits.iter().any(|h| h.starts_with("덧 "))), "장면: 덧줄이 있어야 함");
    strip_format3(&path);
    assert!(!search_terms(&path).values().any(|hits| hits.iter().any(|h| h.starts_with("덧 "))), "흉내: 덧줄이 남음");
    let p = records(&["a@2", "c"], "옛 별칭");
    let r = step_of(&path, &p, &["a@2", "c"]);
    assert!(r.names);
    assert!(common::has_column(&path, "names", "hay") && common::has_column(&path, "names", "cell_ref"));
    assert!(!common::index_sql(&path, "lens_names").is_empty() && !common::index_sql(&path, "event_hay").is_empty());
    let want = full_of(&p, &["a@2", "c"], "ap-f3-full");
    assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "canon이 통째 짓기와 다릅니다");
    same_records(&path, &want, "형식 3 전 저장소"); // 띠 form · 문화권 단위 줄까지(`strip_new_columns`가 판 3으로 걷었다 — 리메이크 3단계)
    assert!(["4", "4.1"].contains(&meta(&path)["schema"].as_str()), "판 4로 고쳐 적어야 함 — {}", meta(&path)["schema"]);
    assert_eq!(name_rows(&path), name_rows(&want));
}

/// 항목 기록 장면(과제 6 · 얹힌 몫 4): `plan(set)`(c가 든 조합)에 더한다 —
/// - 사건 `c/e0`(tc)의 기록 — 찾을 글 `x_find.hay`가 `hay`(본문 색인의 덧줄 · 넓힌 검색이 읽는다).
/// - ta 첫 줄의 공동 사건 `c/e0#1` — 제 기록이 없어 밑동 `c/e0`의 기록을 읽는다(사건은 ta · 기록은 tc 쪽).
/// - 인물 `a/fig-1`의 활동 막대(구역 37) 둘 — ta 첫 줄 · tc 첫 줄. 제 줄이 없는 인물은 이름 찾기에서 그 가운데 **앞 자리**의 줄을 빌린다
///   (ta를 다시 쓰면 ta의 줄 열쇠가 tc보다 뒤로 가 열쇠 차례와 자리 차례가 뒤집힌다).
/// - 같은 꼴로 빌리는 갈래 셋(과제 6 고침 Minor 4): 왕조 `a/dyn-1`(같은 이름의 왕조 칸 — ta `a/ta-host` · tc `c/tc-1`) · 기관 `a/org-1`(기관 칸 —
///   ta `a/ta-2` · tc `c/tc-2`) · 대범위 `a/sc-wide`(같은 이름의 대범위 묶음 — ta · tc 트랙의 `groups`).
fn records(set: &[&str], hay: &str) -> serde_json::Value {
    use serde_json::json;
    let mut p = plan(set);
    let c = set.iter().position(|k| *k == "c").expect("장면에 c가 있어야 합니다");
    let tc = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
    p["entities"].as_array_mut().unwrap().push(json!({"uid":"c/e0","kind":"event","pack":c,
        "json":json!({"uid":"c/e0","title":"다 사건 0","x_find":{"hay":hay}}).to_string()}));
    for (uid, kind, name) in [("a/dyn-1", "dynasty", "큰 왕조"), ("a/org-1", "organ", "작은 관청"), ("a/sc-wide", "scope", "넓은 마당")] {
        p["entities"].as_array_mut().unwrap().push(json!({"uid":uid,"kind":kind,"pack":0,"json":json!({"uid":uid,"name":name}).to_string()}));
    }
    // 칸은 `cells` 끝에(변형의 가리기는 앞자리 칸만 가리킨다). ta의 왕조 칸 «큰 왕조»(`a/ta-host`)는 장면에 이미 있다.
    let cells = p["cells"].as_array_mut().unwrap();
    cells.push(json!({"period":"c/tc-1","kind":0,"lane":0,"start":common::plans::yr(1400),"end":common::plans::yr(1600),"name":"큰 왕조"}));
    cells.push(json!({"period":"a/ta-2","kind":3,"lane":0,"start":common::plans::yr(1300),"end":common::plans::yr(1500),"name":"작은 관청"}));
    cells.push(json!({"period":"c/tc-2","kind":3,"lane":0,"start":common::plans::yr(1550),"end":common::plans::yr(1700),"name":"작은 관청"}));
    for (track, first) in [(0, 2), (tc, 1)] {
        p["tracks"][track]["groups"].as_array_mut().unwrap().push(json!({"depth":0,"first":first,"count":1,"name":"넓은 마당","color":0x9dbea8,"kind":2}));
    }
    let events = p["events"].as_array_mut().unwrap();
    let at = events.iter().position(|e| e["track"] != 0).unwrap_or(events.len()); // ta의 사건 끝(사건은 트랙 차례로 묶여 나간다 — 판정 R25)
    let start = common::plans::yr(1450);
    events.insert(at, json!({"uid":"c/e0#1","track":0,"row":0,"start":start,"end":start,"importance":1,"title":"다 함께한 일","body":"","look":0,
        "label":"","rail":0,"band":""}));
    for track in [0, tc] {
        p["items"].as_array_mut().unwrap().push(json!({"section":37,"track":track,"row":0,"row2":0,"start":common::plans::yr(1400),"end":start,"lod":-1,
            "ref":"","name":"가람 사람","color":0x8a8f96,"a":0,"b":0,"c":0,"d":0,"text2":"a/fig-1|활동"}));
    }
    p
}

/// 이름 표 · 관점 이름의 줄 — 번호 없이(자료집은 글자 id · 줄은 `트랙 열쇠#트랙 안 줄`), 글자 차례로(가문 · 단체 · 제도의 차례는 넓힌 검색으로 본다).
fn name_rows(path: &std::path::Path) -> Vec<String> {
    let keys: serde_json::Value = serde_json::from_str(&meta(path)["pack_keys"]).unwrap();
    let pack = |id: i64| keys[&id.to_string()].as_str().unwrap_or("?").to_owned();
    let db = rusqlite::Connection::open(path).unwrap();
    let mut out = Vec::new();
    for (tag, sql) in [
        ("이름", "SELECT n.pack,json_array(n.kind,n.uid,n.name,n.sub,n.cell,n.start,n.end,CASE WHEN n.row<0 THEN n.row ELSE t.key||'#'||r.ord END,n.color,n.cell_ref,n.hay) \
            FROM names n LEFT JOIN rows r ON r.id=n.row LEFT JOIN tracks t ON t.id=r.track"),
        ("관점", "SELECT pack,json_array(uid,track,name) FROM lens_names"),
    ] {
        let mut stmt = db.prepare(sql).unwrap();
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))).unwrap() {
            let (p, rest) = row.unwrap();
            out.push(format!("{tag} {}|{rest}", pack(p)));
        }
    }
    out.sort();
    out
}

/// [`records`] 장면에서 제 줄 없이 줄을 빌리는 기록 넷(인물 · 왕조 · 기관 · 대범위)이 빌린 줄의 트랙 열쇠 — uid 차례.
fn borrowed(path: &std::path::Path) -> Vec<(String, String)> {
    pairs(path, "SELECT n.uid,t.key FROM names n JOIN rows r ON r.id=n.row JOIN tracks t ON t.id=r.track \
        WHERE n.uid IN ('a/fig-1','a/dyn-1','a/org-1','a/sc-wide') ORDER BY n.uid")
}

/// 넷 모두 그 트랙의 줄을 빌렸다는 기대값.
fn all_on(track: &str) -> Vec<(String, String)> {
    ["a/dyn-1", "a/fig-1", "a/org-1", "a/sc-wide"].iter().map(|u| (u.to_string(), track.to_string())).collect()
}

/// 배치 트랙 둘(순번 `x` · `y`)의 차례를 맞바꾼다 — 트랙 목록과 원소의 트랙 순번(`track` · 변형의 줄 · 이사 · 묶음의 `track` · `toTrack`)을 바꿔 적고
/// 사건은 트랙 차례로 다시 묶는다(내보내기처럼 — 판정 R25). 판 트랙(맨 뒤)의 순번은 그대로다.
fn swapped(mut p: serde_json::Value, x: usize, y: usize) -> serde_json::Value {
    fn swap(v: &mut serde_json::Value, key: &str, x: usize, y: usize) {
        match v.get(key).and_then(serde_json::Value::as_i64) {
            Some(t) if t == x as i64 => v[key] = serde_json::json!(y),
            Some(t) if t == y as i64 => v[key] = serde_json::json!(x),
            _ => {}
        }
    }
    fn fix(root: &mut serde_json::Value, x: usize, y: usize) {
        for key in ["periods", "events", "items", "rowLabels", "axis"] {
            for v in root.get_mut(key).and_then(serde_json::Value::as_array_mut).into_iter().flatten() {
                swap(v, "track", x, y);
            }
        }
        for v in root.get_mut("variants").and_then(serde_json::Value::as_array_mut).into_iter().flatten() {
            swap(v, "track", x, y);
            for part in ["rows", "moves", "groups"] {
                for r in v.get_mut(part).and_then(serde_json::Value::as_array_mut).into_iter().flatten() {
                    swap(r, "track", x, y);
                    swap(r, "toTrack", x, y);
                }
            }
        }
    }
    p["tracks"].as_array_mut().unwrap().swap(x, y);
    fix(&mut p, x, y);
    fix(&mut p["boards"], x, y);
    p["events"].as_array_mut().unwrap().sort_by_key(|e| e["track"].as_i64().unwrap_or(0));
    p
}

#[test]
fn a_layout_that_only_reorders_tracks_respreads_names_and_tells_the_first_place() {
    // 판정 R27(과제 6 고침): 트랙 차례만 바뀐 배치(ta · tc를 맞바꿈) — 지문은 순번을 빼므로 다시 쓸 트랙 · 온 판이 없지만 자리가 바뀐다.
    // 이름 표가 빌리는 줄(자리로 가장 앞 — 이제 tc)이 통째 짓기와 같아야 하고, 앱이 타일을 버릴 첫 자리는 차례가 갈린 곳(0)이다.
    let path = full_of(&records(&["a", "c"], "옛 별칭"), &["a", "c"], "ap-swap");
    assert_eq!(borrowed(&path), all_on("ta"), "장면: 맞바꾸기 전에는 ta의 줄을 빌린다");
    let p = swapped(records(&["a", "c"], "옛 별칭"), 0, 1);
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.rewrote.is_empty() && r.added.is_empty() && r.removed.is_empty() && !r.globals, "{r:?}");
    assert_eq!(r.first_pos, 0, "차례가 갈린 첫 자리");
    assert!(r.names, "차례만 바뀌어도 이름 표를 다시 편다");
    let want = full_of(&p, &["a", "c"], "ap-swap-full");
    assert_eq!(borrowed(&want), all_on("tc"), "장면: 통째 짓기는 앞 자리가 된 tc의 줄을 빌린다");
    assert_eq!(borrowed(&path), borrowed(&want));
    assert_eq!(name_rows(&path), name_rows(&want));
    for word in ["가람", "왕조", "관청", "마당"] {
        assert_eq!(wide_hits(&path, word), wide_hits(&want, word), "넓힌 검색 {word}");
    }
    same_meta(&path, &want, "차례만 바뀜");
}

#[test]
fn a_joint_event_in_a_rewritten_track_reads_its_stem_record() {
    // 과제 6: 다시 쓰는 ta에 든 공동 사건 `c/e0#1`의 덧줄은 다시 쓰지 않는 tc 쪽 기록 `c/e0`(밑동)의 찾을 글로 적는다 — 이번에 넣은 기록만 보면 빠진다.
    // 인물 · 왕조 · 기관 · 대범위가 빌리는 줄은 열쇠가 아니라 자리로 가장 앞의 것(ta)이다 — ta를 다시 쓰면 ta의 줄 열쇠가 tc보다 커져('4.1')
    // 열쇠로 고르면 tc를 고른다(Minor 4 — 갈래마다 하나씩).
    let path = full_of(&records(&["a", "c"], "옛 별칭"), &["a", "c"], "ap-joint");
    let p = records(&["a@2", "c"], "옛 별칭");
    let r = step_of(&path, &p, &["a@2", "c"]);
    assert!(r.rewrote.contains(&"ta".to_string()) && !r.rewrote.contains(&"tc".to_string()), "{:?}", r.rewrote);
    assert!(r.names);
    assert_eq!(meta(&path)["schema"], "4.1", "장면: 열쇠 ≠ 자리");
    let want = full_of(&p, &["a@2", "c"], "ap-joint-full");
    assert!(search_terms(&want).values().any(|hits| hits.contains("덧 c/e0#1")), "장면: 공동 사건에 덧줄이 있어야 함");
    same_records(&path, &want, "공동 사건");
    for word in ["별칭", "가람", "왕조", "관청", "마당"] {
        assert_eq!(wide_hits(&path, word), wide_hits(&want, word), "넓힌 검색 {word}");
    }
    assert_eq!(borrowed(&want), all_on("ta"), "장면: 통째 짓기는 앞 자리 ta의 줄을 빌린다");
    assert_eq!(borrowed(&path), borrowed(&want));
    assert_eq!(name_rows(&path), name_rows(&want));
}

#[test]
fn records_alone_respread_search_and_names() {
    // 얹힌 몫 4: 트랙은 그대로이고 항목 기록만 바뀐 배치 — 다시 쓰지 않는 트랙의 사건 덧줄(제 기록 `c/e0` · 밑동을 읽는 `c/e0#1`) · 이름 표(인물 이름) ·
    // 관점 이름 · 단체의 넣은 차례가 통째 짓기와 같다.
    let path = full_of(&records(&["a", "c"], "옛 별칭"), &["a", "c"], "ap-records");
    let mut p = records(&["a", "c"], "새 별칭");
    let list = p["entities"].as_array_mut().unwrap();
    let at = |list: &[serde_json::Value], uid: &str| list.iter().position(|e| e["uid"] == uid).unwrap();
    let fig = at(list, "a/fig-1");
    list[fig]["json"] = serde_json::json!(serde_json::json!({"uid":"a/fig-1","name":"가람 새 사람"}).to_string());
    let ta2 = at(list, "a/ta-2");
    list[ta2]["json"] = serde_json::json!(serde_json::json!({"uid":"a/ta-2","name":"가 둘째 나라","track":"ta",
        "perspectives":[{"track":"tc","title":"다 쪽 둘째 나라"}]}).to_string());
    let early = list.remove(at(list, "a/grp-1"));
    let late = at(list, "a/grp-2");
    list.insert(late, early); // 단체 차례: 이른 모임 → 늦은 모임
    let r = step_of(&path, &p, &["a", "c"]);
    assert!(r.rewrote.is_empty() && r.added.is_empty() && r.removed.is_empty() && r.names, "{r:?}");
    let want = full_of(&p, &["a", "c"], "ap-records-full");
    same_records(&path, &want, "기록만");
    for word in ["별칭", "가람", "모임"] {
        assert_eq!(wide_hits(&path, word), wide_hits(&want, word), "넓힌 검색 {word}");
    }
    assert_eq!(name_rows(&path), name_rows(&want));
    assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "canon이 통째 짓기와 다릅니다");
}

#[test]
fn a_record_given_twice_keeps_its_first_place_in_the_name_order() {
    // 얹힌 몫 1: 같은 uid의 기록이 배치에 두 번이면 본문 · 갈래 · 자료집은 뒤엣것, 넣은 차례(`entities.ord`)는 처음 것(가문 · 단체 · 제도로 처음 넣은 것) —
    // 통째 짓기의 이름 표가 가문 · 단체 · 제도를 처음 본 차례로 내는 쪽(`build_names`)에 맞춘다. Node 내보내기는 겹친 uid를 거절한다(`entities.mjs`).
    let twice = |set: &[&str]| {
        let mut p = plan(set);
        let list = p["entities"].as_array_mut().unwrap();
        list.push(serde_json::json!({"uid":"house:a-zelkova","kind":"house","pack":0,"json":"{\"name\":\"느티 가문 둘\",\"surname\":\"느\"}"}));
        if let Some(c) = set.iter().position(|k| *k == "c") {
            list.push(serde_json::json!({"uid":"house:c-reed","kind":"house","pack":c,"json":"{\"name\":\"갈대 가문\",\"surname\":\"갈\"}"}));
        }
        p
    };
    let path = full_of(&twice(&["a"]), &["a"], "ap-twice");
    step_of(&path, &twice(&["a", "c"]), &["a", "c"]);
    let want = full_of(&twice(&["a", "c"]), &["a", "c"], "ap-twice-full");
    let houses = |p: &std::path::Path| -> Vec<String> {
        wide_hits(p, "가문").iter().filter(|it| it["kind"] == "house").map(|it| format!("{} {}", it["uid"], it["name"])).collect()
    };
    assert_eq!(houses(&want), vec!["\"house:a-zelkova\" \"느티 가문 둘\"", "\"house:a-bamboo\" \"대숲 가문\"", "\"house:c-reed\" \"갈대 가문\""], "통째 짓기");
    assert_eq!(houses(&path), houses(&want));
    same_entities(&path, &want, "두 번 넣은 기록");
    same_meta(&path, &want, "두 번 넣은 기록");
}

// ---------------------------------------------------------------- 과제 7a: 밖으로 여는 문(명령 · 도구) · 덮는 트랙과 항목 기록

/// `archive_call`에 JSON 한 줄을 보내고 답 JSON을 받는다(앱이 부르는 길). 이 파일에서 전역 저장소(`STORE`)를 만지는 검사는
/// [`the_apply_command_rewrites_the_open_store_in_place`] 하나뿐이라 줄 세우지 않는다.
fn call(request: serde_json::Value) -> serde_json::Value {
    let text = std::ffi::CString::new(request.to_string()).unwrap();
    unsafe {
        let answer = archive_engine::archive_call(text.as_ptr());
        let value = serde_json::from_slice(std::ffi::CStr::from_ptr(answer).to_bytes()).unwrap();
        archive_engine::archive_free(answer);
        value
    }
}

/// 장면 파일 하나(배치 JSON · 원본 · 아카이브 배치)를 임시 자리에 쓴다.
fn put_file(name: &str, ext: &str, bytes: &[u8]) -> std::path::PathBuf {
    let path = common::scratch(name).with_extension(ext);
    std::fs::write(&path, bytes).unwrap();
    path
}

/// 그 조합의 배치 JSON 파일.
fn layout_file(name: &str, set: &[&str]) -> std::path::PathBuf {
    put_file(name, "json", &serde_json::to_vec(&plan(set)).unwrap())
}

/// 자료집 하나(`c` · `a@2` …)의 원본 파일(.htpack).
fn pack_file(name: &str, key: &str) -> std::path::PathBuf {
    put_file(name, "htpack", &packs_of(&[key])[0].1)
}

/// `meta.pack_info`에서 그 글자 id의 칸.
fn pack_info(path: &std::path::Path, key: &str) -> serde_json::Value {
    let info: serde_json::Value = serde_json::from_str(&meta(path)["pack_info"]).unwrap();
    info.as_object().unwrap().values().find(|v| v["id"] == key).cloned().unwrap_or_else(|| panic!("pack_info에 {key}가 없습니다"))
}

/// 메이커 배치(.htlayout)로 원본 없이 든 DLC를 흉내 낸다 — 그 자료집의 `packs.original` · `sha256`을 비우고 `pack_info`의 `original`을 거짓으로.
fn drop_original(path: &std::path::Path, key: &str) {
    let db = rusqlite::Connection::open(path).unwrap();
    let keys: serde_json::Value = serde_json::from_str(&meta(path)["pack_keys"]).unwrap();
    let number = keys.as_object().unwrap().iter().find(|(_, v)| *v == key).map(|(n, _)| n.clone()).unwrap();
    db.execute("UPDATE packs SET original=NULL,sha256=NULL WHERE id=?1", [&number]).unwrap();
    let mut info: serde_json::Value = serde_json::from_str(&meta(path)["pack_info"]).unwrap();
    info[&number]["original"] = serde_json::json!(false);
    db.execute("UPDATE meta SET value=?1 WHERE key='pack_info'", [info.to_string()]).unwrap();
}

#[test]
fn the_apply_command_rewrites_the_open_store_in_place() {
    use serde_json::json;
    let ok = |answer: &serde_json::Value| assert_eq!(answer["ok"], true, "{answer}");
    let tracks = || -> Vec<String> {
        let answer = call(json!({"op":"layout"}));
        assert_eq!(answer["ok"], true, "{answer}");
        answer["data"]["tracks"].as_array().unwrap().iter().map(|t| t["key"].as_str().unwrap().to_owned()).collect()
    };
    let c_pack = pack_file("ap-cmd-c", "c");
    let both = layout_file("ap-cmd-ac", &["a", "c"]);

    // 1. 열린 저장소(a)에 배치 JSON(a · c)과 c의 원본 — 바꿔 넣기 없이 제자리에서 고쳐 쓰고, 다시 연 저장소에 tc가 보인다.
    let path = full(&["a"], "ap-cmd");
    ok(&call(json!({"op":"open","path":path})));
    assert!(!tracks().contains(&"tc".to_string()));
    let answer = call(json!({"op":"apply","layout":both,"originals":[c_pack]}));
    ok(&answer);
    let d = &answer["data"];
    assert_eq!((&d["rewrote"], &d["added"], &d["removed"]), (&json!([]), &json!(["tc"]), &json!([])));
    assert_eq!((&d["globals"], &d["first_pos"], &d["rows_before"], &d["rows_after"], &d["names"]), (&json!(true), &json!(5), &json!(7), &json!(9), &json!(true)));
    assert!(d["ms"].as_f64().is_some_and(|ms| ms > 0.0), "{d}");
    assert!(tracks().contains(&"tc".to_string()), "다시 연 저장소에 tc가 보인다");
    same(&path, &["a", "c"], "ap-cmd", false);

    // 2. 깨진 배치 · 없는 파일 · 경로 없음 · 원본 목록이 목록이 아님은 실패 — 파일과 답은 그대로(`committed`가 없다 = 저장소 그대로).
    let before = (common::sha256_file(&path), call(json!({"op":"layout"}))["data"].clone());
    let broken = put_file("ap-cmd-broken", "json", b"{ \"packs\": [");
    for bad in [json!({"op":"apply","layout":broken}), json!({"op":"apply","layout":common::scratch("ap-cmd-none").with_extension("json")}),
        json!({"op":"apply"}), json!({"op":"apply","layout":both,"originals":"c.htpack"})] {
        let answer = call(bad.clone());
        assert_eq!(answer["ok"], false, "{bad} → {answer}");
        assert!(answer["error"].as_str().is_some_and(|e| !e.is_empty()) && answer.get("committed").is_none(), "{answer}");
        assert!(answer.get("code").is_none(), "앱이 가를 거절이 아니면 code가 없다: {answer}");
    }
    assert_eq!((common::sha256_file(&path), call(json!({"op":"layout"}))["data"].clone()), before);

    // 3. 메이커 배치(.htlayout)는 그 배치의 트랙만 덮는다(계획 정한 것 #8) — a만 실은 배치를 넣어도 tc는 그대로다. covers "all"은 받지 않는다.
    let only_a = put_file("ap-cmd-a", "htlayout", &common::plans::htlayout(&plan(&["a"])));
    let answer = call(json!({"op":"apply","layout":only_a,"covers":"all"}));
    assert!(answer["ok"] == false && answer["error"].as_str().unwrap().contains(".htlayout") && answer.get("code").is_none(), "{answer}");
    assert_eq!(common::sha256_file(&path), before.0);
    // 기본팩이 다른 배치는 기계용 code "base"(과제 8 고침 1회차 — 앱은 글이 아니라 code로 가른다).
    let mut other = plan(&["a"]);
    other["packs"][0]["id"] = json!("other-base");
    let other = put_file("ap-cmd-other-base", "htlayout", &common::plans::htlayout(&other));
    let answer = call(json!({"op":"apply","layout":other}));
    assert!(answer["ok"] == false && answer["code"] == "base" && answer["error"].as_str().unwrap().contains("기본팩이 다릅니다"), "{answer}");
    assert_eq!(common::sha256_file(&path), before.0);
    let answer = call(json!({"op":"apply","layout":only_a}));
    ok(&answer);
    assert_eq!((&answer["data"]["added"], &answer["data"]["removed"]), (&json!([]), &json!([])));
    assert!(tracks().contains(&"tc".to_string()), "덮지 않은 tc는 그대로");

    // 4. COMMIT 뒤 다시 열기가 실패하면(얹힌 몫 4 — 실패 주입) 실패이되 `committed`로 '저장소 그대로'와 가른다: 파일은 바뀌었고 저장소는 닫혔다.
    let before = common::sha256_file(&path);
    archive_engine::write::set_fail_point(Some("reopen"));
    let answer = call(json!({"op":"apply","layout":layout_file("ap-cmd-a-json", &["a"]),"remove":["c"]}));
    archive_engine::write::set_fail_point(None);
    assert_eq!((&answer["ok"], &answer["committed"]), (&json!(false), &json!(true)), "{answer}");
    assert!(answer["error"].as_str().unwrap().contains("다시 열지 못"), "{answer}");
    assert_ne!(common::sha256_file(&path), before, "COMMIT은 끝났다");
    assert!(call(json!({"op":"layout"}))["error"].as_str().unwrap().contains("열리지 않았습니다"));
    ok(&call(json!({"op":"open","path":path})));
    assert!(!tracks().contains(&"tc".to_string()), "다시 열면 c를 뺀 저장소");

    // 5. 원본 없이 든 DLC(.htlayout 길 흉내): 원본으로 셈한 배치 JSON을 넣을 때 그 원본을 주면 저장소 안으로 들이고(옛 DLC의 약속 2),
    //    안 주면 '다시 골라 주세요'로 멈춘다(파일 그대로).
    let bare = full(&["a", "c"], "ap-cmd-bare");
    drop_original(&bare, "c");
    assert_eq!(pack_info(&bare, "c")["original"], false);
    ok(&call(json!({"op":"open","path":bare})));
    let before = common::sha256_file(&bare);
    let answer = call(json!({"op":"apply","layout":both}));
    assert!(answer["ok"] == false && answer["error"].as_str().unwrap().contains("다시 골라") && answer["code"] == "original", "{answer}");
    assert_eq!(common::sha256_file(&bare), before);
    let answer = call(json!({"op":"apply","layout":both,"originals":[c_pack]}));
    ok(&answer);
    assert_eq!(pack_info(&bare, "c")["original"], true);
    assert!(meta(&bare)["legacy"].contains("원본 전용 팩 보존"), "{}", meta(&bare)["legacy"]);

    // 6. 걸음 중 실패한 직후 곧바로 다시 부르면 된다(A+ 6 가) — 쓰기 줄(`WRITE`) · 저장소 잠금(`STORE`) · 일지가 남지 않고, 실패한 동안 열린 저장소는
    //    옛 답 그대로다. 빼기(지우기 걸음 뒤 · 이름 표)와 넣기(표본 대조)에서 한 번씩.
    let journal = std::path::PathBuf::from(format!("{}-journal", bare.display()));
    let without_c = json!({"op":"apply","layout":layout_file("ap-cmd-retry-a", &["a"]),"remove":["c"]});
    let with_c = json!({"op":"apply","layout":both,"originals":[c_pack]});
    for (at, ask, has_c) in [("insert", &without_c, false), ("verify", &with_c, true), ("names", &without_c, false)] {
        let before = common::sha256_file(&bare);
        archive_engine::write::set_fail_point(Some(at));
        let answer = call(ask.clone());
        archive_engine::write::set_fail_point(None);
        assert!(answer["ok"] == false && answer.get("committed").is_none() && answer["error"] == format!("실패 주입: {at}"), "{at}: {answer}");
        assert_eq!(common::sha256_file(&bare), before, "{at}: 실패한 뒤 파일이 바뀜");
        assert!(!journal.exists(), "{at}: 일지가 남음");
        assert_eq!(tracks().contains(&"tc".to_string()), !has_c, "{at}: 열린 저장소는 옛 답 그대로");
        ok(&call(ask.clone()));
        assert_eq!(tracks().contains(&"tc".to_string()), has_c, "{at}: 곧바로 다시 부른 apply");
    }

    // 7. 옛 엔진으로 지은 저장소(열이 빠짐)에 메이커 배치는 code "rebuild"(앱이 모두 덮는 배치로 먼저 고쳐 쓴다 — 과제 8 얹힌 몫 4) · 파일 그대로.
    let older = full(&["a", "c"], "ap-cmd-older");
    strip_older(&older, "sphere");
    ok(&call(json!({"op":"open","path":older})));
    let before = common::sha256_file(&older);
    let answer = call(json!({"op":"apply","layout":only_a}));
    assert!(answer["ok"] == false && answer["code"] == "rebuild" && answer.get("committed").is_none(), "{answer}");
    assert_eq!(common::sha256_file(&older), before);
    assert_eq!(call(json!({"op":"close"}))["data"]["closed"], true);
}

#[test]
fn the_tools_apply_a_layout_file_and_print_canon() {
    let tool = env!("CARGO_BIN_EXE_archive-tool");
    let run = |args: &[&str]| -> (bool, String) {
        let out = std::process::Command::new(tool).args(args).output().unwrap();
        (out.status.success(), String::from_utf8_lossy(if out.status.success() { &out.stdout } else { &out.stderr }).into_owned())
    };
    let json_of = |text: &str| -> serde_json::Value { serde_json::from_str(text.trim()).unwrap_or_else(|e| panic!("{e}: {text}")) };
    let s = |p: &std::path::Path| p.to_str().unwrap().to_owned();
    // apply-layout: 판이 바뀐 a의 원본과 배치 → 저장소 파일을 제자리에서 고쳐 쓰고 답을 찍는다.
    let path = full(&["a", "c"], "ap-tool");
    // 고침 1회차 Minor 2: 판이 바뀐 DLC(배치 v2.0.0 · 저장소 v1.0.0)를 원본 없이 주면 거절 — 원본 바이트는 옛 판 · 자료는 새 판이 되지 않게(파일 그대로).
    let before = common::sha256_file(&path);
    let (ok, text) = run(&["apply-layout", &s(&path), &s(&layout_file("ap-tool-a2c-bare", &["a@2", "c"]))]);
    assert!(!ok && text.contains("판이 바뀐 DLC는 원본을 함께 주세요"), "{text}");
    assert_eq!(common::sha256_file(&path), before);
    let (ok, text) = run(&["apply-layout", &s(&path), &s(&layout_file("ap-tool-a2c", &["a@2", "c"])), &s(&pack_file("ap-tool-a2", "a@2"))]);
    assert!(ok, "{text}");
    let answer = json_of(&text);
    assert_eq!(answer["rewrote"], serde_json::json!([BOARD, "ta"]));
    assert!(answer["names"].is_boolean() && answer["ms"].is_number(), "{answer}");
    // canon: 같은 조합을 통째로 지은 저장소와 같은 묶음 — 라이브러리의 canon_store 그대로(단계 · 가로 열 · 조회 목록을 고른다).
    let want = full(&["a@2", "c"], "ap-tool-full");
    let (ok, text) = run(&["canon", &s(&path), "--levels=8,14", "--max-x=8"]);
    assert!(ok, "{text}");
    let o = CanonOpts { levels: vec![8, 14], max_x: 8, queries: false };
    assert_eq!(json_of(&text), canon_store(&want, &o).unwrap());
    let (ok, text) = run(&["canon", &s(&path), "--queries", "--levels=14", "--max-x=4"]);
    assert!(ok && json_of(&text)["queries"].is_object(), "{text}");
    // --remove로 빼고, --covers로 덮는 트랙만 주어 다시 넣는다.
    let (ok, text) = run(&["apply-layout", &s(&path), &s(&layout_file("ap-tool-a2", &["a@2"])), "--remove=c"]);
    assert!(ok, "{text}");
    assert_eq!(json_of(&text)["removed"], serde_json::json!(["tc"]));
    let (ok, text) = run(&["apply-layout", &s(&path), &s(&layout_file("ap-tool-a2c-again", &["a@2", "c"])), &s(&pack_file("ap-tool-c", "c")), "--covers=tc"]);
    assert!(ok, "{text}");
    assert_eq!(json_of(&text)["added"], serde_json::json!(["tc"]));
    // 거절하면 파일 그대로.
    let before = common::sha256_file(&path);
    let (ok, text) = run(&["apply-layout", &s(&path), &s(&layout_file("ap-tool-a", &["a@2"]))]);
    assert!(!ok && text.contains("이 배치에 없습니다"), "{text}");
    assert_eq!(common::sha256_file(&path), before);
}

#[test]
fn a_covering_layout_with_every_pack_drops_the_records_it_left_out() {
    // 얹힌 몫 7: 덮는 트랙만 주는 배치라도 지금 저장소의 DLC를 모두 실었으면(P3 정한 것 #12 — 하위 배치도 항목 기록 · 그림은 그 조합 전부를 싣는다)
    // 배치에 없는 항목 기록 · 그림을 지우고 넣은 차례도 배치대로 적는다 — 통째 짓기와 같다.
    let path = full_of(&with_pictures(&["a", "c"], "첫 그림", Some("둘째 그림")), &["a", "c"], "ap-cover-all");
    let mut p = with_pictures(&["a", "c"], "첫 그림", None);
    p["entities"].as_array_mut().unwrap().retain(|e| e["uid"] != "a/grp-1");
    let o = packs_of(&["a", "c"]);
    let covers = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap();
    assert!(r.rewrote.is_empty() && r.added.is_empty() && r.removed.is_empty() && r.names, "{r:?}");
    let want = full_of(&p, &["a", "c"], "ap-cover-all-full");
    same_entities(&path, &want, "덮는 트랙 · DLC 전부");
    assert_eq!(name_rows(&path), name_rows(&want));
    let blobs = "SELECT key,mime FROM blobs ORDER BY key";
    assert_eq!(pairs(&path, blobs), pairs(&want, blobs));
    same_meta(&path, &want, "덮는 트랙 · DLC 전부");
}

#[test]
fn a_covering_layout_missing_a_pack_keeps_that_packs_records() {
    // 얹힌 몫 7의 반대: 지금 저장소의 DLC(c)를 싣지 않은 배치(메이커가 a만 불러 내보낸 것)는 기록을 넣거나 바꾸기만 한다 — c의 기록이 남는다.
    let path = full(&["a", "c"], "ap-cover-part");
    let c_records = "SELECT uid,kind FROM entities WHERE uid LIKE 'c/%' ORDER BY uid";
    let before = pairs(&path, c_records);
    assert_eq!(before.len(), 3, "장면: c의 기록 셋");
    let (p, o) = (plan(&["a"]), packs_of(&["a"]));
    let covers = Covers::Tracks(["ta".to_string()].into_iter().collect());
    write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap();
    assert_eq!(pairs(&path, c_records), before);
    let rows: i64 = rusqlite::Connection::open(&path).unwrap().query_row("SELECT count(*) FROM entities", [], |r| r.get(0)).unwrap();
    assert_eq!(common::meta_i64(&path, "entities"), rows);
}

// ---------------------------------------------------------------- 과제 A+: B(앱이 실제 사용자 저장소에 apply를 부름) 전에 막을 것

/// 지금 엔진으로 지은 저장소에서 덧붙임 Builder가 쓰는 열 · 표 하나를 지워 그 열이 없던 때의 저장소를 흉내 낸다(A+ 1) — `Store::on`은 넷 모두
/// 가려 읽으므로 그대로 열린다. 변형은 열 다섯(`rows` · `periods` · `cells` · `events` · `items`의 `variant`)과 표 다섯을 함께 지우고, 덮는 색인
/// (`events_time` — `variant`를 품는다)은 그 열 없이 다시 짓는다(`builder::reindex` — 변형 전 저장소의 모양). 수 세기 열쇠(`meta.variants` …)는
/// 남겨 둔다(열쇠만 남은 꼴도 받아야 한다). 스키마 4(리메이크 3단계 · 계약 1-1)의 띠 `form` 열(`form`)과 문화권 단위 줄 표(`sphere_lines`)도 하나씩
/// 지울 수 있다. 어느 것을 지우든 판(`meta.schema`)은 '3'으로 적는다 — 지운 열 · 표는 모두 판 4 전의 저장소에 없던 것이라, 첫 모두 덮는 apply가
/// 판을 '4'(열쇠 ≠ 자리면 '4.1')로 고쳐 적는지 함께 본다.
fn strip_older(path: &std::path::Path, what: &str) {
    {
        let db = rusqlite::Connection::open(path).unwrap();
        let sql = match what {
            "sphere" => "ALTER TABLE tracks DROP COLUMN sphere;".to_owned(),
            "ref_kind" => "ALTER TABLE items DROP COLUMN ref_kind;".to_owned(),
            "cats" => "ALTER TABLE summaries DROP COLUMN cats;".to_owned(),
            "form" => "ALTER TABLE periods DROP COLUMN form;".to_owned(),
            "sphere_lines" => "DROP TABLE sphere_lines;".to_owned(),
            "variant" => {
                let mut sql = "DROP INDEX events_time; DROP TABLE variant_groups; DROP TABLE variant_hides; DROP TABLE variant_moves; \
                    DROP TABLE variant_rows; DROP TABLE variants;".to_owned();
                for table in ["rows", "periods", "cells", "events", "items"] {
                    sql += &format!(" ALTER TABLE {table} DROP COLUMN variant;");
                }
                sql
            }
            other => panic!("모르는 옛 열: {other}"),
        };
        db.execute_batch(&sql).unwrap();
        assert_eq!(db.execute("UPDATE meta SET value='3' WHERE key='schema'", []).unwrap(), 1, "meta.schema가 없습니다");
    }
    if what == "variant" {
        archive_engine::builder::reindex(path).unwrap();
    }
}

/// [`strip_older`]가 지우는 열의 내용을 번호 없이(A+ 1): 트랙 열쇠 → 문화권 · 일반 항목(구역 · 이름 · 기간 · 곁글 · 변형에서만 있는가) → ref_kind ·
/// 요약(트랙 열쇠#트랙 안 줄 · 단계 · 통 · 자료집 글자 id) → 분류별 수 · 변형 열쇠 → 줄 · 이사 · 가림 · 묶음 수 · 띠 uid → form ·
/// 문화권 단위 줄 번호 → 내용(자료집 글자 id · 문화권 · 갈래 · 기간 · 이름 · uid · 색 · data — 번호도 통째 짓기처럼 1부터). 글자 차례.
fn older_columns(path: &std::path::Path) -> Vec<(String, String)> {
    let mut out = pairs(path, "SELECT 'sphere '||key,sphere FROM tracks");
    out.extend(pairs(path, "SELECT 'form '||uid,CAST(form AS TEXT) FROM periods"));
    out.extend(pairs(path, "SELECT 'sphere_line '||id,json_extract((SELECT value FROM meta WHERE key='pack_keys'),'$.\"'||pack||'\"')||'|'||sphere||'|'||kind\
        ||'|'||start||'|'||end||'|'||name||'|'||uid||'|'||color||'|'||data FROM sphere_lines"));
    out.extend(pairs(path, "SELECT 'item '||section||'|'||name||'|'||start||'|'||end||'|'||text2||'|'||(variant<>0),CAST(ref_kind AS TEXT) FROM items"));
    out.extend(pairs(path, "SELECT 'summary '||t.key||'#'||r.ord||'|'||s.level||'|'||s.bucket||'|'||json_extract((SELECT value FROM meta WHERE key='pack_keys'),'$.\"'||s.pack||'\"'),\
        hex(s.cats) FROM summaries s JOIN rows r ON r.id=s.lane JOIN tracks t ON t.id=r.track"));
    out.extend(pairs(path, "SELECT 'variant '||v.key,(SELECT count(*) FROM variant_rows x WHERE x.variant=v.id)||'|'||(SELECT count(*) FROM variant_moves x WHERE x.variant=v.id)\
        ||'|'||(SELECT count(*) FROM variant_hides x WHERE x.variant=v.id)||'|'||(SELECT count(*) FROM variant_groups x WHERE x.variant=v.id) FROM variants v"));
    out.sort();
    out
}

#[test]
fn a_store_missing_an_older_column_is_rewritten_once_like_a_full_build() {
    // A+ 1: 덧붙임 Builder는 tracks.sphere · items.ref_kind · summaries.cats · 변형 열 · 표를 가림 없이 쓴다 — 그 열이 없는 옛 저장소는 열리지만
    // apply가 SQL 오류("no such column")로 거절됐다. 첫 apply가 짓기와 같은 꼴로 만들고, 내용을 싣는 열이라(빈 열로 두면 다시 쓰지 않는 트랙이
    // 통째 짓기와 달라진다) 모든 트랙을 한 번 다시 쓴다. 장면은 색 바꿈 — 지문으로는 ta와 판만 다시 쓸 배치다.
    // 리메이크 3단계(과제 7 걸음 1): 스키마 4의 띠 `form` 열 · 문화권 단위 줄 표(`sphere_lines`)가 없는 판 3 저장소도 같은 길 — 첫 apply가 열 · 표를
    // 만들고 모든 트랙을 다시 써(form) 온 판을 다시 적어(줄 — 옛 저장소는 온 판 지문을 믿지 않는다) 통째 짓기와 같고, 판을 '4'로 고쳐 적는다.
    let (p, o) = (plan(&["a@2", "c"]), packs_of(&["a@2", "c"]));
    let mut refused = Vec::new();
    for what in ["sphere", "ref_kind", "cats", "variant", "form", "sphere_lines"] {
        let path = full(&["a", "c"], &format!("ap-older-{what}"));
        strip_older(&path, what);
        assert_eq!(meta(&path)["schema"], "3", "{what}: 장면 — 판 3 저장소");
        archive_engine::Store::open(&path).unwrap_or_else(|e| panic!("{what}: 옛 저장소가 열려야 함: {e}"));
        let r = match write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })) {
            Ok(r) => r,
            Err(e) => {
                refused.push(format!("{what}: {e}"));
                continue;
            }
        };
        assert_eq!(r.rewrote.len(), common::track_count(&path), "{what}: 모든 트랙을 한 번 다시 씀 — {:?}", r.rewrote);
        let want = full(&["a@2", "c"], &format!("ap-older-{what}-full"));
        assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "{what}: canon이 통째 짓기와 다릅니다");
        same_records(&path, &want, what);
        assert_eq!(older_columns(&path), older_columns(&want), "{what}: 열의 내용");
        assert!(["4", "4.1"].contains(&meta(&path)["schema"].as_str()), "{what}: 판 4로 고쳐 적어야 함 — {}", meta(&path)["schema"]);
        let again = step(&path, &["a@2", "c"], &[]);
        assert!(again.rewrote.is_empty() && again.added.is_empty() && !again.globals, "{what}: 그 뒤부터는 바뀐 트랙만 — {again:?}");
    }
    assert!(refused.is_empty(), "옛 저장소의 첫 apply가 거절됨: {refused:#?}");
    // 견줌이 빈 값끼리 같아 지나가지 않게 — 장면의 통째 짓기에 form ≠ 0 띠와 문화권 단위 줄이 있다(a · c 조합: a/ta-1 · a/ta-2 · c/tc-2 · 줄 셋).
    let want = full(&["a@2", "c"], "ap-older-scene");
    let cols = older_columns(&want);
    assert_eq!(cols.iter().filter(|(k, v)| k.starts_with("form ") && v != "0").count(), 3, "장면의 form ≠ 0 띠");
    assert_eq!(cols.iter().filter(|(k, _)| k.starts_with("sphere_line ")).count(), 3, "장면의 문화권 단위 줄");
}

#[test]
fn a_covering_layout_on_a_store_missing_an_older_column_is_refused() {
    // A+ 1의 다른 갈래: 덮는 트랙만 주는 배치(메이커)로는 덮지 않는 트랙을 다시 쓸 재료가 없어 그 열이 빈 채 남는다 — 첫머리에서 거절하고
    // 다시 지으라고 알린다(SQL 오류 글 대신 · 파일 그대로). 저장소의 트랙을 모두 덮어도 거절한다(A+ 검토 가 — 온 판은 모두 덮는 배치만 적는다 ·
    // 다음 검사). 모두 덮는 apply 한 번이면 받는다(모두 다시 쓴다).
    let path = full(&["a", "c"], "ap-older-cover");
    strip_older(&path, "sphere");
    let before = common::sha256_file(&path);
    let (p, o) = (plan(&["a", "c"]), packs_of(&["a", "c"]));
    let covers = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap_err().to_string();
    assert!(err.contains("고쳐 써 주세요") && err.contains("tracks.sphere"), "{err}");
    assert_eq!(err.matches("이 저장소는").count(), 1, "거절 글의 '이 저장소는'은 한 번(A+ 검토 마): {err}");
    assert_eq!(common::sha256_file(&path), before);
    let all = Covers::Tracks(["ta", "tc", BOARD].into_iter().map(str::to_owned).collect());
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: all, remove: &[] })).unwrap_err().to_string();
    assert!(err.contains("고쳐 써 주세요") && err.contains("tracks.sphere"), "다 덮어도 거절: {err}");
    assert_eq!(common::sha256_file(&path), before);
    let r = step(&path, &["a", "c"], &[]);
    assert_eq!(r.rewrote.len(), 3, "{r:?}");
    let want = full(&["a", "c"], "ap-older-cover-full");
    assert_eq!(older_columns(&path), older_columns(&want));
    // 리메이크 3단계(과제 7 걸음 1): 스키마 4 전의 엔진이 지은 판 3 저장소(띠 form 열 · 문화권 단위 줄 표가 없음 — 나머지는 지금 모양)도 같은 갈래 —
    // 메이커 배치(덮는 트랙만)는 code "rebuild"로 거절하고 글에 빠진 열을 적는다(파일 그대로). 모두 덮는 apply 한 번 뒤에는 받는다.
    let path = full(&["a", "c"], "ap-older-cover-4");
    common::strip_schema4(&path, "3");
    let before = common::sha256_file(&path);
    let covers = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap_err();
    let code = err.downcast_ref::<archive_engine::patch::Refusal>().map(|r| r.code);
    let err = err.to_string();
    assert_eq!(code, Some("rebuild"), "판 3 저장소에 덮는 배치: {err}");
    assert!(err.contains("고쳐 써 주세요") && err.contains("periods.form") && err.contains("sphere_lines"), "{err}");
    assert_eq!(common::sha256_file(&path), before, "거절하면 파일 그대로");
    let r = step(&path, &["a", "c"], &[]);
    assert!(r.rewrote.len() == 3 && r.globals, "판 3 저장소의 첫 모두 덮는 apply는 모든 트랙 · 온 판을 다시 씀 — {r:?}");
    assert!(["4", "4.1"].contains(&meta(&path)["schema"].as_str()), "판 4로 고쳐 적어야 함(모든 트랙을 다시 써 열쇠 ≠ 자리면 4.1) — {}", meta(&path)["schema"]);
    assert_eq!(older_columns(&path), older_columns(&want));
    let covers = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] }))
        .unwrap_or_else(|e| panic!("판 4로 고쳐 쓴 뒤의 덮는 배치는 받아야 함: {e}"));
    assert!(r.rewrote.is_empty() && r.added.is_empty(), "같은 배치라 다시 쓸 것이 없음 — {r:?}");
}

#[test]
fn an_old_store_without_spheres_or_prints_waits_for_a_whole_apply() {
    // A+ 검토 (가): 이 계획 전 저장소(지문 표 없음 · 열 빠짐)에 `meta.spheres`까지 없는 꼴. 트랙을 다 덮는 `Covers::Tracks`를 받으면 온 판(문화권 ·
    // 간지 설정)은 적지 않은 채 "prints"가 온 판 지문을 새것으로 적어, 다음 모두 덮는 apply도 온 판이 같다고 보고 끝내 채우지 않았다 — 다 덮어도
    // 거절하고(파일 그대로), 모두 덮는 apply 한 번이 meta.spheres까지 통째 짓기와 같게 채운다.
    // 리메이크 3단계(과제 7 걸음 1): 이 계획 전 저장소는 스키마 4 전이기도 해(`common::strip_new_columns`가 판 3으로 — 띠 form 열 · 문화권 단위 줄 표
    // 없음) 온 판의 새 몫인 문화권 단위 줄도 같은 길이다 — 다 덮어도 거절하고, 모두 덮는 apply 한 번 뒤 줄이 통째 짓기와 같다(번호까지).
    let path = full(&["a", "c"], "ap-older-globals");
    common::strip_new_columns(&path);
    strip_older(&path, "sphere");
    rusqlite::Connection::open(&path).unwrap().execute("DELETE FROM meta WHERE key='spheres'", []).unwrap();
    assert!(!meta(&path).contains_key("spheres") && common::index_sql(&path, "track_prints").is_empty(), "장면: meta.spheres · 지문 표 없음");
    assert!(common::index_sql(&path, "sphere_lines").is_empty() && meta(&path)["schema"] == "3", "장면: 문화권 단위 줄 표가 없는 판 3");
    let before = common::sha256_file(&path);
    let (p, o) = (plan(&["a", "c"]), packs_of(&["a", "c"]));
    let all = Covers::Tracks(["ta", "tc", BOARD].into_iter().map(str::to_owned).collect());
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: all, remove: &[] })).unwrap_err().to_string();
    assert!(err.contains("고쳐 써 주세요") && err.contains("tracks.sphere") && err.contains("sphere_lines"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
    let r = step(&path, &["a", "c"], &[]);
    assert!(r.globals && r.rewrote.len() == 3, "{r:?}");
    let want = full(&["a", "c"], "ap-older-globals-full");
    assert!(meta(&want).contains_key("spheres"), "장면: 통째 짓기는 meta.spheres를 적는다");
    assert_eq!(meta(&path).get("spheres"), meta(&want).get("spheres"));
    same_meta(&path, &want, "옛 저장소의 온 판");
    assert_eq!(older_columns(&path), older_columns(&want));
    let lines = "SELECT CAST(id AS TEXT),pack||'|'||sphere||'|'||kind||'|'||start||'|'||end||'|'||name||'|'||uid||'|'||color||'|'||data FROM sphere_lines ORDER BY id";
    assert_eq!(pairs(&path, lines), pairs(&want, lines), "문화권 단위 줄(번호 · 자료집 번호까지)");
    assert_eq!(pairs(&want, lines).len(), 3, "장면: a · c 조합의 줄 셋");
    common::same::same_schema4(&path, &want, "옛 저장소의 온 판");
    assert!(["4", "4.1"].contains(&meta(&path)["schema"].as_str()), "판 4로 고쳐 적어야 함(모든 트랙을 다시 써 열쇠 ≠ 자리면 4.1) — {}", meta(&path)["schema"]);
}

/// 본문 색인을 끈 채(`Builder::without_search` — `meta.search` 'off') 통째로 지은 저장소(A+ 2) — `import_layout_value`와 같은 짓기에서 색인만 뺀다
/// (`meta.legacy`는 같은 조합을 보통으로 지은 것에서 옮겨 적는다).
fn full_quiet(set: &[&str], name: &str) -> std::path::PathBuf {
    let p = plan(set);
    let legacy = meta(&full(set, &format!("{name}-loud")))["legacy"].clone();
    let packs = packs_of(set).into_iter().zip(p["packs"].as_array().unwrap()).map(|((key, bytes), d)| archive_engine::legacy::PackPlan {
        key: Some(key), name: d["name"].as_str().unwrap().to_owned(), version: d["version"].as_str().unwrap().to_owned(),
        category: d["category"].as_str().unwrap_or("").to_owned(), original: Some(bytes),
    }).collect();
    let path = common::scratch(name);
    let mut b = archive_engine::builder::Builder::create(&path).unwrap().without_search();
    b.add_meta("legacy", legacy);
    archive_engine::legacy::fill_into(&mut b, &p, packs, archive_engine::legacy::FillHow::All).unwrap();
    b.finalize(&[]).unwrap();
    path
}

#[test]
fn a_store_without_search_takes_adds_rewrites_and_removals() {
    // A+ 2: 본문 색인을 끈 저장소(`meta.search` 'off')에서 apply의 지우기 · 넣기 · 이름 표가 본문 색인을 건너뛰는 길 — 더하기(ta · tc 다시 씀 ·
    // tb 듦) · 색 바꿈(ta · 판) · 빼기(b)가 실패 없이 돌고, 걸음마다 그 조합을 색인 없이 통째로 지은 것과 같다(본문 색인 · 덧줄은 끝까지 빈 채).
    let path = full_quiet(&["a", "c"], "ap-quiet");
    assert_eq!(meta(&path)["search"], "off");
    let walk: [(&[&str], &[&str]); 3] = [(&["a", "b", "c"], &[]), (&["a@2", "b", "c"], &[]), (&["a@2", "c"], &["b"])];
    for (i, (set, gone)) in walk.into_iter().enumerate() {
        let gone: Vec<String> = gone.iter().map(|k| k.to_string()).collect();
        let r = step(&path, set, &gone);
        assert!(!r.rewrote.is_empty() || !r.added.is_empty() || !r.removed.is_empty(), "{set:?}: {r:?}");
        let want = full_quiet(set, &format!("ap-quiet-{i}-full"));
        assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "{set:?}: canon이 통째 짓기와 다릅니다");
        same_meta(&path, &want, "색인 끔");
        same_entities(&path, &want, "색인 끔");
        let ords = "SELECT uid,CAST(ord AS TEXT) FROM events ORDER BY uid";
        assert_eq!(pairs(&path, ords), pairs(&want, ords), "{set:?}: events.ord");
        assert!(search_terms(&path).is_empty() && search_terms(&want).is_empty(), "{set:?}: 본문 색인이 비어야 함");
        let hay = "SELECT CAST(count(*) AS TEXT),'' FROM event_hay";
        assert_eq!(pairs(&path, hay), vec![("0".to_string(), String::new())], "{set:?}: 덧줄");
    }
}

/// 판(`view:a1`)이 가리는 ta의 칸 · 관계선과 **내용이 똑같은** 쌍둥이를 하나씩 더하고 판이 그것도 가리게 한 배치(A+ 3 — 판정 R19 '하나씩').
fn twins(set: &[&str]) -> serde_json::Value {
    let mut p = plan(set);
    for (list, at, kind) in [("cells", common::plans::BOARD_CELL, 3), ("items", common::plans::BOARD_ITEM, 4)] {
        let twin = p[list][at as usize].clone();
        let rows = p[list].as_array_mut().unwrap();
        rows.push(twin);
        let at = rows.len() - 1;
        p["boards"]["variants"][0]["hides"].as_array_mut().unwrap().push(serde_json::json!({"kind":kind,"at":at}));
    }
    p
}

#[test]
fn twin_hidden_things_pair_one_by_one_from_the_store() {
    // A+ 3(검사 빈틈 12): 판만 다시 쓸 때(이름만 바뀜) 판이 가리는 ta의 칸 · 관계선은 저장소에서 내용으로 찾는다 — 같은 내용이 둘이면 가림마다
    // 서로 다른 번호를 번호 차례로 하나씩 짝짓는다(같은 번호를 두 번 주면 쌍둥이 하나가 판을 켜도 남는다).
    let path = full_of(&twins(&["a", "c"]), &["a", "c"], "ap-twins");
    let mut p = twins(&["a", "c"]);
    p["boards"]["variants"][0]["name"] = serde_json::json!("가 다시 모아 보기");
    let r = step_of(&path, &p, &["a", "c"]);
    assert_eq!(r.rewrote, vec![BOARD.to_string()]);
    let want = full_of(&p, &["a", "c"], "ap-twins-full");
    let hidden = "SELECT CAST(h.kind AS TEXT),CAST(count(DISTINCT h.ref) AS TEXT) FROM variant_hides h JOIN variants v ON v.id=h.variant \
        WHERE v.key='view:a1' GROUP BY h.kind ORDER BY h.kind";
    assert_eq!(pairs(&want, hidden), [("3", "2"), ("4", "2")].map(|(a, b)| (a.to_string(), b.to_string())).to_vec(), "장면: 판이 쌍둥이 둘씩을 가린다");
    assert_eq!(pairs(&path, hidden), pairs(&want, hidden));
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());

    // A+ 검토 (나): ta를 먼저 다시 써(색 바꿈) 그 덩이의 열쇠를 끝으로 옮긴 뒤(열쇠 ≠ 자리 — '4.1') 판 이름만 바꾼다. 가림 후보를 덩이의 열쇠 범위 ·
    // `rows.ord`로 좁히는 길이 열쇠와 자리가 갈린 저장소에서도 쌍둥이를 하나씩 짝짓는다.
    let path = full_of(&twins(&["a", "c"]), &["a", "c"], "ap-twins-moved");
    let r = step_of(&path, &twins(&["a@2", "c"]), &["a@2", "c"]);
    assert!(r.rewrote.contains(&"ta".to_string()), "장면: ta를 다시 씀 — {r:?}");
    assert_eq!(meta(&path)["schema"], "4.1", "장면: 열쇠 ≠ 자리");
    let mut p = twins(&["a@2", "c"]);
    p["boards"]["variants"][0]["name"] = serde_json::json!("가 다시 모아 보기");
    let r = step_of(&path, &p, &["a@2", "c"]);
    assert_eq!(r.rewrote, vec![BOARD.to_string()]);
    let want = full_of(&p, &["a@2", "c"], "ap-twins-moved-full");
    assert_eq!(pairs(&path, hidden), pairs(&want, hidden));
    assert_eq!(canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
}

#[test]
fn a_hidden_thing_missing_from_the_store_is_refused() {
    // A+ 3(검사 빈틈 12): 판만 다시 쓰는데 판이 가리는 ta의 칸 · 관계선을 저장소에서 내용으로 찾지 못하면(여기서는 저장소 쪽 이름을 바꿔 둠)
    // 지문 규칙의 구멍으로 알리고 거절한다 — 파일 그대로.
    for (tag, sql) in [("cell", "UPDATE cells SET name='엉뚱한 임금' WHERE name='둘째 임금' AND variant=0"),
        ("item", "UPDATE items SET name='엉뚱한 관계선' WHERE section=21 AND variant=0")] {
        let path = full(&["a", "c"], &format!("ap-hide-lost-{tag}"));
        assert_eq!(rusqlite::Connection::open(&path).unwrap().execute(sql, []).unwrap(), 1, "{tag}: 장면");
        let before = common::sha256_file(&path);
        let mut p = plan(&["a", "c"]);
        p["boards"]["variants"][0]["name"] = serde_json::json!("가 다시 모아 보기");
        let o = packs_of(&["a", "c"]);
        let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &[] })).unwrap_err().to_string();
        assert!(err.contains("찾지 못했습니다") && err.contains("view:a1"), "{tag}: {err}");
        assert_eq!(common::sha256_file(&path), before, "{tag}");
    }
}

#[test]
fn a_row_pointer_past_a_shrunken_track_is_refused() {
    // A+ 3(검사 빈틈 12): 다시 쓰지 않는 트랙(big-t2)의 변형 묶음이 다시 쓰는 트랙(big-t1)의 넷째 줄을 가리키는데 덮는 트랙만 주는 배치가 big-t1을
    // 세 줄로 줄이면, 옮겨 적을(relink) 자리가 새 덩이를 넘는다 — 그 트랙도 다시 써야 했다(지문 규칙의 구멍)고 알리고 거절한다(파일 그대로).
    let mut p = big(3, 4, 24);
    p["variants"] = serde_json::json!([{"key":"scope:big/t2","kind":2,"track":2,"band":"","uid":"big/t2","name":"큰 모아 보기","notes":"",
        "rows":[],"moves":[],"hides":[],"groups":[{"track":1,"key":"__scope:big/t2","depth":0,"name":"큰 모아 보기","color":0,"kind":2,"rows":[3]}]}]);
    let o = packs_of(&["big"]);
    let path = common::scratch("ap-relink-over");
    import_layout_value(&p, &o, &path).unwrap();
    // big-t1의 넷째 줄(띠 · 사건 포함)을 뺀 배치 — 하위 배치는 big-t1만 싣는다(t2의 묶음은 싣지 않는다).
    let mut q = p.clone();
    q["tracks"][1]["rows"].as_array_mut().unwrap().pop();
    q["periods"].as_array_mut().unwrap().retain(|x| x["uid"] != "big/t1-r3");
    q["events"].as_array_mut().unwrap().retain(|e| !(e["track"] == 1 && e["row"] == 3));
    let keys: std::collections::BTreeSet<String> = ["big-t1".to_string()].into_iter().collect();
    let sub = sub_plan(&q, &keys).unwrap();
    let before = common::sha256_file(&path);
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &o, covers: Covers::Tracks(keys.clone()), remove: &[] })).unwrap_err().to_string();
    assert!(err.contains("big-t1") && err.contains("줄 너머") && err.contains("3줄뿐"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
}

/// a의 판을 뺀 배치(A+ 4 — 판 없는 저장소의 장면).
fn without_boards(set: &[&str]) -> serde_json::Value {
    let mut p = plan(set);
    p.as_object_mut().unwrap().remove("boards");
    p
}

/// 그 배치의 판 목록 끝에 b의 판 하나(`__board:view:b1` — 그 판에서만 있는 줄 하나)를 더한다(A+ 4 — 메이커가 b의 판을 만든 장면).
fn with_b_board(mut p: serde_json::Value) -> serde_json::Value {
    use serde_json::json;
    let b = p["packs"].as_array().unwrap().iter().position(|d| d["id"] == "b").expect("장면에 b가 있어야 합니다");
    let tb = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tb").unwrap();
    if !p["boards"].is_object() {
        p["boards"] = json!({"tracks":[],"variants":[],"cells":[],"items":[],"entities":[]});
    }
    let at = p["tracks"].as_array().unwrap().len() + p["boards"]["tracks"].as_array().unwrap().len();
    let mut row = p["tracks"][tb]["rows"][0].clone();
    row["variant"] = json!("view:b1");
    let boards = &mut p["boards"];
    boards["tracks"].as_array_mut().unwrap().push(json!({"key":"__board:view:b1","name":"나 모아 보기","color":0xbbacc8,"dynasty":0,"leader":1,"cabinet":0,
        "organ":0,"railLevels":2,"rows":[row],"groups":[],"pack":b}));
    boards["variants"].as_array_mut().unwrap().push(json!({"key":"view:b1","kind":3,"track":at,"band":"","uid":"view:b1","name":"나 모아 보기","notes":"",
        "rows":[{"track":at,"row":0,"after":-1,"ord":0,"new":1,"scopePad":16,"groupStart":1}],"moves":[],"hides":[],"groups":[]}));
    boards["entities"].as_array_mut().unwrap().push(json!({"uid":"board:view:b1","kind":"board","pack":b,"json":json!({"key":"view:b1","name":"나 모아 보기"}).to_string()}));
    p
}

#[test]
fn a_new_board_from_a_partial_layout_lands_after_every_regular_track() {
    // A+ 4: 메이커가 기본팩 a와 b만 불러 b의 판을 만든 배치(트랙 = ta · tb · 판)를 덮는 트랙만으로 넣는다. 판의 바로 앞 트랙(tb)은 보통 트랙이라
    // 그 뒤에 끼우면 저장소의 tc 앞에 선다 — 통째 짓기는 보통 트랙 → 판 차례다. 판은 보통 트랙 전부 뒤에 들어야 다음 모두 덮는 apply에서 자리가 뛰지 않는다.
    let path = full_of(&without_boards(&["a", "b", "c"]), &["a", "b", "c"], "ap-board-place");
    let maker = with_b_board(without_boards(&["a", "b"]));
    let covers = Covers::Tracks(["ta", "tb", "board:__board:view:b1"].into_iter().map(str::to_owned).collect());
    let o = packs_of(&["a", "b"]);
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &maker, originals: &o, covers, remove: &[] })).unwrap();
    assert_eq!(r.added, vec!["board:__board:view:b1".to_string()], "{r:?}");
    let order = |p: &std::path::Path| -> Vec<String> { pairs(p, "SELECT key,'' FROM tracks ORDER BY ord,id").into_iter().map(|(k, _)| k).collect() };
    assert_eq!(order(&path), vec!["ta", "tb", "tc", "__board:view:b1"]);
    // 그 조합 전부(모두 덮는 배치)를 다시 넣어도 자리가 뛰지 않고(first_pos −1) 통째 짓기와 같다.
    let whole = with_b_board(without_boards(&["a", "b", "c"]));
    let again = step_of(&path, &whole, &["a", "b", "c"]);
    assert!(again.rewrote.is_empty() && again.added.is_empty() && again.removed.is_empty() && again.first_pos == -1, "{again:?}");
    let want = full_of(&whole, &["a", "b", "c"], "ap-board-place-full");
    assert_eq!(order(&path), order(&want));
    assert!(canon_store(&path, &quick()).unwrap() == canon_store(&want, &quick()).unwrap(), "canon이 통째 짓기와 다릅니다");
}

#[test]
fn a_failed_apply_leaves_the_store_ready_for_the_next_one() {
    // A+ 6 가: 걸음 중 Err로 실패한 직후 같은 저장소에 apply가 곧바로 성공한다 — 거래가 되돌려져 일지(`-journal`)도 쓰기 잠금도 남지 않는다.
    // 걸음마다 실패를 주입하고 곧바로 같은 배치를 다시 넣는다(조합을 번갈아 — 걸음마다 실제로 고쳐 쓴다). 끝에서 통째 짓기와 같다.
    // 열린 저장소(`STORE` 잠금 · 쓰기 줄 `WRITE`)의 길은 `the_apply_command_rewrites_the_open_store_in_place`의 6.
    let path = full(&["a"], "ap-retry");
    let journal = std::path::PathBuf::from(format!("{}-journal", path.display()));
    let sets: [&[&str]; 2] = [&["a", "b", "c"], &["a"]];
    for (i, at) in STEPS.into_iter().enumerate() {
        let (to, from) = (sets[i % 2], sets[(i + 1) % 2]);
        let gone: Vec<String> = from.iter().filter(|k| !to.contains(k)).map(|k| k.to_string()).collect();
        let (p, o) = (plan(to), packs_of(to));
        let run = || write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &gone }));
        archive_engine::write::set_fail_point(Some(at));
        let failed = run();
        archive_engine::write::set_fail_point(None);
        assert_eq!(failed.unwrap_err().to_string(), format!("실패 주입: {at}"));
        assert!(!journal.exists(), "{at}: 실패한 뒤 일지가 남음");
        let r = run().unwrap_or_else(|e| panic!("{at}에서 실패한 직후 다시 넣기: {e}"));
        assert!(!r.added.is_empty() || !r.removed.is_empty(), "{at}: {r:?}");
    }
    same(&path, sets[(STEPS.len() - 1) % 2], "ap-retry", false);
}

#[test]
fn removing_a_dlc_with_pictures_and_a_shared_date_cell_matches_a_full_build() {
    // A+ 6 나: 그림(blobs)과 공통 날짜 칸(track −1 — 온 판)을 가진 DLC(c)를 빼면 그 그림 · 칸이 사라지고, 칸이 넓혀 두었던 보는 범위도 남은 것으로
    // 돌아간다 — 그 조합을 통째로 지은 것과 같다.
    use serde_json::json;
    let with_c_things = |set: &[&str]| -> serde_json::Value {
        let mut p = with_pictures(set, "첫 그림", None);
        if let Some(c) = set.iter().position(|k| *k == "c") {
            p["blobs"].as_array_mut().unwrap().push(json!({"key":"img:c/map","pack":c,"mime":"image/png","data":archive_engine::base64_encode("다 지도".as_bytes())}));
            p["axis"].as_array_mut().unwrap().push(json!({"kind":1,"track":-1,"lane":0,"start":common::plans::yr(700),"end":common::plans::yr(900),
                "name":"다 이른 시대","color":0xd7c18e,"style":0,"strip":0,"seq":0,"pack":c}));
        }
        p
    };
    let path = full_of(&with_c_things(&["a", "c"]), &["a", "c"], "ap-drop-things");
    assert_eq!(common::meta_i64(&path, "min"), common::plans::yr(700), "장면: c의 공통 날짜 칸이 보는 범위를 넓힌다");
    let p = with_c_things(&["a"]);
    let o = packs_of(&["a"]);
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &["c".to_string()] })).unwrap();
    assert_eq!(r.removed, vec!["tc".to_string()]);
    let want = full_of(&p, &["a"], "ap-drop-things-full");
    let blobs = "SELECT key,mime||'|'||hex(bytes) FROM blobs ORDER BY key";
    assert_eq!(pairs(&path, blobs), pairs(&want, blobs));
    assert_eq!(pairs(&path, blobs).len(), 1, "c의 그림이 빠짐");
    let shared = "SELECT name,start||'|'||end FROM axis_cells WHERE track IS NULL ORDER BY name";
    assert_eq!(pairs(&path, shared), pairs(&want, shared));
    same_meta(&path, &want, "그림 · 공통 날짜 칸을 가진 DLC 빼기");
    assert!(canon_store(&path, &quick()).unwrap() == canon_store(&want, &quick()).unwrap(), "canon이 통째 짓기와 다릅니다");
}

// ---------------------------------------------------------------- A 걸음 검토(Fable)의 검사 빈틈 — 과제 A+가 C 과제 9로 넘긴 몫(장부 227행)

#[test]
fn an_old_store_under_a_covering_layout_stops_at_the_hider_guard() {
    // 빈틈 2: 이 계획 전 저장소(지문 표 없음 — 저장된 needs의 가림도 없다) + 덮는 트랙만 주는 배치(.htlayout 길)의 첫 apply. ta를 다시 쓰는데 ta를 가리는
    // 판 트랙이 배치에 없으면 choose는 가리는 트랙을 모른다(저장된 needs 없음 · 새 배치에 판 없음) — "delete"의 둘째 지킴(얹힌 몫 10)만이 막아 거절하고 파일 그대로.
    // 판까지 덮어 주면 받는다 — 덮지 않은 트랙은 지문이 없어도 그대로 남고(덮은 트랙과 그것을 가리키는 tc만 다시 씀) 그 조합의 통째 짓기와 같다.
    // 스키마 4의 열 · 표는 남긴다(`strip_p4_columns`): 이 계획 전의 실제 저장소는 판 3이라(`strip_new_columns`) 덮는 배치가 첫머리에서 code "rebuild"로
    // 먼저 거절된다(`a_covering_layout_on_a_store_missing_an_older_column_is_refused`) — 여기서는 그 뒤의 지킴 하나를 따로 본다.
    let path = full(&["a", "c"], "ap-gap2");
    common::strip_p4_columns(&path);
    let before = common::sha256_file(&path);
    let mut p = plan(&["a@2", "c"]);
    p.as_object_mut().unwrap().remove("boards");
    let o = packs_of(&["a@2", "c"]);
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::Tracks(["ta".to_string()].into_iter().collect()), remove: &[] }))
        .unwrap_err().to_string();
    assert!(err.contains("가립니다") && err.contains("다시 써야"), "둘째 지킴의 글이어야 함: {err}");
    assert_eq!(common::sha256_file(&path), before, "거절하면 파일 그대로");
    let p = plan(&["a@2", "c"]);
    let covers = Covers::Tracks(["ta", BOARD].into_iter().map(str::to_owned).collect());
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap();
    assert!(r.rewrote.contains(&"ta".to_string()) && r.rewrote.contains(&BOARD.to_string()), "{r:?}");
    let want = full(&["a@2", "c"], "ap-gap2-full");
    assert!(canon_store(&path, &quick()).unwrap() == canon_store(&want, &quick()).unwrap(), "canon이 통째 짓기와 다릅니다");
}

#[test]
fn reorder_removal_and_board_hides_in_one_apply_match_a_full_build() {
    // 빈틈 3(장부 6 minor): 트랙 차례 바뀜(moved) + 트랙 빼기(removed) + 판 가림(판이 가리는 ta를 다시 씀)이 한 apply에 — first_pos는 차례가 갈린 첫 자리,
    // 표본은 저장소 전체에서. 통째 짓기와 같다.
    let path = full(&["a", "b", "c"], "ap-gap3");
    let p = swapped(plan(&["a", "c"]), 0, 1); // tc · ta · 판
    let o = packs_of(&["a", "c"]);
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &["b".to_string()] })).unwrap();
    assert_eq!(r.removed, vec!["tb".to_string()]);
    assert!(r.rewrote.contains(&"ta".to_string()) && r.rewrote.contains(&BOARD.to_string()), "{r:?}");
    assert_eq!(r.first_pos, 0, "{r:?}");
    let want = full_of(&p, &["a", "c"], "ap-gap3-full");
    // 조회 목록은 빼고 견준다: 차례가 바뀐 뒤 `search`의 답은 사건 번호 차례라(같은 uid는 옛 번호 — 옛 차례) 통째 짓기와 차례가 갈린다 — 판정 R12의
    // '번호로만 갈리는 차례는 계약 밖'(2026-10-22 이 장면에서 드러남 — 보고). 검색 낱자 · 기록은 `same_records`가 본다.
    let (got, exp) = (canon_store(&path, &opts(false)).unwrap(), canon_store(&want, &opts(false)).unwrap());
    assert!(got == exp, "canon이 통째 짓기와 다릅니다: {:?}", archive_engine::lay::same::diff(&got, &exp, 8));
    same_records(&path, &want, "차례 · 빼기 · 판 가림");
    // relink의 지킴(n_new = 0): 남는 트랙(ta)의 변형이 사라지는 트랙(tc)의 줄을 가리키는데 ta를 다시 쓰지 않으면(여기서는 저장소의 ta 지문을 새 배치의 것으로
    // 맞춰 지문 규칙의 구멍을 흉내) 그 이사가 지운 줄을 가리키게 된다 — 차례 바뀜 · 빼기와 함께여도 Err · 파일 그대로.
    let mut q = plan(&["a", "b", "c"]);
    let tc = q["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
    let host = q["variants"].as_array().unwrap().iter().position(|v| v["key"] == "host:a/ta-host").unwrap();
    q["variants"][host]["moves"].as_array_mut().unwrap().push(serde_json::json!({"kind":1,"ref":"a/ta-1","track":tc,"row":0}));
    let path = full_of(&q, &["a", "b", "c"], "ap-gap3-hole");
    let new = swapped(plan(&["a", "b"]), 0, 1);
    let ta_print = archive_engine::patch::prints(&new).unwrap().tracks["ta"].print.clone();
    rusqlite::Connection::open(&path).unwrap().execute("UPDATE track_prints SET print=?1 WHERE key='ta'", [&ta_print]).unwrap();
    let before = common::sha256_file(&path);
    let o = packs_of(&["a", "b"]);
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &new, originals: &o, covers: Covers::All, remove: &["c".to_string()] })).unwrap_err().to_string();
    assert!(err.contains("사라진 트랙") && err.contains("tc"), "{err}");
    assert_eq!(common::sha256_file(&path), before, "거절하면 파일 그대로");
}

#[test]
fn a_variant_only_event_never_stretches_the_view_range() {
    // 빈틈 7: 변형에서만 있는 사건(variant ≠ 0)이 보는 범위 끝값 밖에 있어도 통째 짓기는 범위를 넓히지 않는다(기본 판 날짜 있는 사건만 — `SPAN_EVENT`) —
    // 넣고 빼는 길(`put_range`)도 같아야 한다.
    use serde_json::json;
    let far = |set: &[&str]| -> serde_json::Value {
        let mut p = plan(set);
        if let Some(tc) = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc") {
            let y = common::plans::yr(3000);
            p["events"].as_array_mut().unwrap().push(json!({"uid":"c/e-far","track":tc,"row":0,"start":y,"end":y,"importance":1,"title":"먼 변형 사건",
                "body":"","look":0,"label":"","rail":0,"band":"","variant":"scope:c/sc-1"}));
        }
        p
    };
    let want = full_of(&far(&["a", "c"]), &["a", "c"], "ap-gap7-full");
    assert!(common::meta_i64(&want, "max") < common::plans::yr(3000), "장면: 통째 짓기는 변형 사건으로 범위를 넓히지 않는다");
    let path = full(&["a"], "ap-gap7");
    step_of(&path, &far(&["a", "c"]), &["a", "c"]);
    assert_eq!((common::meta_i64(&path, "min"), common::meta_i64(&path, "max")), (common::meta_i64(&want, "min"), common::meta_i64(&want, "max")));
    let p = far(&["a"]);
    let o = packs_of(&["a"]);
    write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers: Covers::All, remove: &["c".to_string()] })).unwrap();
    let back = full(&["a"], "ap-gap7-back");
    assert_eq!((common::meta_i64(&path, "min"), common::meta_i64(&path, "max")), (common::meta_i64(&back, "min"), common::meta_i64(&back, "max")));
}

#[test]
fn a_band_uid_in_two_tracks_is_refused_instead_of_answering_differently() {
    // 빈틈 10(경보 — 지금 자료엔 없음): 같은 uid의 띠가 두 트랙에 있으면 그 uid를 가리키는 값(일반 항목의 ref)은 통째 짓기에서 **배치에 뒤에 실린 것**으로 풀린다.
    // 트랙 차례만 바뀌어도(지문은 그대로) 이기는 쪽이 바뀌어 트랙별 고쳐 쓰기가 통째 짓기와 달라질 수 있다 — 그 uid의 주인 트랙 · 가리키는 트랙을 모두 다시 써도
    // 이 장면은 통째 짓기와 canon이 달랐다(2026-10-22 갈래 1이 잼 — 같은 uid의 옛 번호 이어 쓰기 · 번호로 깨는 조회 차례). 조용히 다른 답을 내지 않고 거절한다(저장소 그대로).
    // 판정 R37: 거절 글은 어느 DLC의 어느 트랙에 어느 항목이 겹치는지를 쉬운 말로(`code` dup_uid — DLC를 만든 쪽에서 고칠 일).
    use serde_json::json;
    let dup = |set: &[&str]| -> serde_json::Value {
        let mut p = plan(set);
        let tc = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
        let mut copy = p["periods"].as_array().unwrap().iter().find(|b| b["uid"] == "a/ta-2").unwrap().clone();
        copy["track"] = json!(tc);
        copy["row"] = json!(0);
        copy["name"] = json!("다 쪽의 같은 띠");
        p["periods"].as_array_mut().unwrap().push(copy); // tc의 띠 뒤 — 통째 짓기에서 이것이 이김
        p
    };
    let p1 = dup(&["a", "c"]);
    let path = full_of(&p1, &["a", "c"], "ap-gap10");
    // 차례를 바꾸고 띠 목록도 트랙 차례로(내보내기 꼴 — tc의 띠가 앞으로) 늘어놓는다: 이제 ta의 a/ta-2가 뒤라 이긴다.
    let mut p2 = swapped(p1.clone(), 0, 1);
    p2["periods"].as_array_mut().unwrap().sort_by_key(|b| b["track"].as_i64().unwrap_or(0));
    // 띠 번호 칸(periods 자리 + 1)을 새 자리로 다시 적는다(옮긴 띠를 가리키던 번호).
    let label = |b: &serde_json::Value| format!("{}|{}", b["uid"], b["name"]);
    let before: Vec<String> = p1["periods"].as_array().unwrap().iter().map(label).collect();
    let after: Vec<String> = p2["periods"].as_array().unwrap().iter().map(label).collect();
    let renumber = |items: &mut serde_json::Value| {
        for it in items.as_array_mut().into_iter().flatten() {
            let n = |k: &str| it[k].as_i64().unwrap_or(0);
            for f in archive_engine::bandref::band_fields(n("section"), n("a"), n("b"), n("c"), n("d")) {
                let key = ["a", "b", "c", "d"][f];
                let v = it[key].as_i64().unwrap_or(0);
                if v > 0 {
                    let at = after.iter().position(|u| *u == before[(v - 1) as usize]).unwrap();
                    it[key] = json!(at + 1);
                }
            }
        }
    };
    renumber(&mut p2["items"]);
    renumber(&mut p2["boards"]["items"]);
    let before = common::sha256_file(&path);
    let o = packs_of(&["a", "c"]);
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &p2, originals: &o, covers: Covers::All, remove: &[] })).unwrap_err();
    assert_eq!(err.downcast_ref::<archive_engine::patch::Refusal>().map(|r| r.code), Some("dup_uid"), "{err}");
    let err = err.to_string();
    assert!(err.contains("a/ta-2") && err.contains("가 기록집의 «가 나라»") && err.contains("다 기록집의 «다 나라»") && err.contains("만든 쪽에서 고쳐야")
        && !err.contains("통째로") && !err.contains("uid"), "{err}");
    assert_eq!(common::sha256_file(&path), before, "거절하면 저장소 그대로");
    // 통째로 다시 짓는 길은 그대로 받는다.
    full_of(&p2, &["a", "c"], "ap-gap10-full");
}

#[test]
fn a_shared_uid_under_covered_tracks_is_refused_too() {
    // 판정 R37 · 고침 2회차 빈틈: 덮는 트랙만 주는 배치(`Covers::Tracks` — 메이커 `.htlayout` 길)도 같은 uid의 띠가 두 트랙에 있으면 `code` dup_uid · 저장소 그대로.
    use serde_json::json;
    let dup = |color: u32| -> serde_json::Value {
        let mut p = plan(&["a", "c"]);
        let tc = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
        let mut copy = p["periods"].as_array().unwrap().iter().find(|b| b["uid"] == "a/ta-2").unwrap().clone();
        copy["track"] = json!(tc);
        copy["row"] = json!(0);
        p["periods"].as_array_mut().unwrap().push(copy);
        for b in p["periods"].as_array_mut().unwrap() {
            if b["uid"] == "c/tc-2" {
                b["color"] = json!(color);
            }
        }
        p
    };
    let path = full_of(&dup(0xa0bcc5), &["a", "c"], "ap-dup-tracks");
    let before = common::sha256_file(&path);
    let o = packs_of(&["a", "c"]);
    let covers = Covers::Tracks(["tc".to_string()].into_iter().collect());
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &dup(0x123456), originals: &o, covers, remove: &[] })).unwrap_err();
    assert_eq!(err.downcast_ref::<archive_engine::patch::Refusal>().map(|r| r.code), Some("dup_uid"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
}

#[test]
fn a_shared_uid_outside_the_part_is_refused_too() {
    // 판정 R37 · 고침 1회차: 일부 트랙만 실은 배치(`Covers::Part` — add_pack의 좁힌 배치)도 S 밖 트랙(저장소의 것)과 겹치는 uid를 본다 — 띠는 `periods_uid`로,
    // 사건은 부분 색인 `events_uid`(`uid<>''`)로. 겹치면 `code` dup_uid로 거절하고 저장소 그대로.
    use archive_engine::patch::prints;
    use serde_json::json;
    let tc_of = |p: &serde_json::Value| p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
    for (what, list, uid) in [("띠", "periods", "a/ta-2"), ("사건", "events", "a/e10")] {
        // 저장소: ta의 띠(사건)와 같은 uid를 tc에도 둔 조합(통째 짓기는 받는다).
        let dup = |color: u32| -> serde_json::Value {
            let mut p = plan(&["a", "c"]);
            let tc = tc_of(&p);
            let mut copy = p[list].as_array().unwrap().iter().find(|x| x["uid"] == uid).unwrap().clone();
            copy["track"] = json!(tc);
            copy["row"] = json!(0);
            if list == "events" {
                copy["band"] = json!("c/tc-1");
                copy["start"] = json!(common::plans::yr(1460));
                copy["end"] = copy["start"].clone();
            }
            p[list].as_array_mut().unwrap().push(copy);
            for b in p["periods"].as_array_mut().unwrap() {
                if b["uid"] == "c/tc-2" {
                    b["color"] = json!(color);
                }
            }
            if list == "events" {
                p["events"].as_array_mut().unwrap().sort_by_key(|e| e["track"].as_i64().unwrap_or(0));
            }
            p
        };
        let path = full_of(&dup(0xa0bcc5), &["a", "c"], &format!("ap-dup-part-{list}"));
        let before = common::sha256_file(&path);
        // tc만 바뀐 배치를 tc만 실어(S = {tc}) — S 안에서는 겹침이 보이지 않고, S 밖 ta의 것과 겹친다.
        let p2 = dup(0x123456);
        let order = prints(&p2).unwrap().order;
        let s: std::collections::BTreeSet<String> = ["tc".to_string()].into_iter().collect();
        let sub = sub_plan(&p2, &s).unwrap();
        let o = packs_of(&["a", "c"]);
        let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &o, covers: Covers::Part { tracks: s.clone(), order: order.clone() }, remove: &[] }))
            .unwrap_err();
        assert_eq!(err.downcast_ref::<archive_engine::patch::Refusal>().map(|r| r.code), Some("dup_uid"), "{what}: {err}");
        let err = err.to_string();
        assert!(err.contains(uid) && err.contains("가 기록집의 «가 나라»") && err.contains("다 기록집의 «다 나라»"), "{what}: {err}");
        assert_eq!(common::sha256_file(&path), before, "{what}: 거절하면 저장소 그대로");
    }
}

#[test]
fn a_board_hiding_an_item_that_points_into_a_rewritten_track_finds_it() {
    // 고침 1회차(검토 Important 7 — 등불 무작위 판이 찾은 `resolve_hides` 구멍의 결정적 장면): 판(view:a1 — 이름이 바뀌어 다시 씀)이 가리는 ta의 관계선
    // (ta는 다시 쓰지 않음 — 하위 배치 밖 가림)이 함께 다시 쓰는 tc의 띠 c/tc-1을 `ref`로 가리킨다. "insert" 때는 tc의 띠가 이미 지워져 저장소의 번호로
    // uid를 풀 수 없다 — 지우기 전 번호(`Kept`)를 거꾸로 읽어 찾아야 한다(그 전엔 "찾지 못했습니다"로 거절했다).
    use serde_json::json;
    let scene = |board: &str, color: u32| -> serde_json::Value {
        let mut p = plan(&["a", "c"]);
        let at = common::plans::BOARD_ITEM as usize;
        assert_eq!(p["items"][at]["section"], 21, "장면: 판이 가리는 ta의 관계선");
        p["items"][at]["ref"] = json!("c/tc-1");
        p["boards"]["items"][0]["ref"] = json!("c/tc-1"); // 판 쪽 관계선도 같은 내용으로
        p["boards"]["tracks"][0]["name"] = json!(board);
        for b in p["periods"].as_array_mut().unwrap() {
            if b["uid"] == "c/tc-1" {
                b["color"] = json!(color);
            }
        }
        p
    };
    let p1 = scene("가 모아 보기", 0xd7c18e);
    let path = full_of(&p1, &["a", "c"], "ap-hide-ref");
    let p2 = scene("가 다시 모아 보기", 0x123456);
    let r = step_of(&path, &p2, &["a", "c"]);
    assert_eq!(r.rewrote, vec![BOARD.to_string(), "tc".to_string()], "판 · tc만 다시 쓰고 ta는 그대로");
    let want = full_of(&p2, &["a", "c"], "ap-hide-ref-full");
    assert_eq!(canon_store(&path, &opts(true)).unwrap(), canon_store(&want, &opts(true)).unwrap());
    same_records(&path, &want, "판이 가리는 남의 트랙 관계선");
}

// ---------------------------------------------------------------- 스키마 4(리메이크 3단계 걸음 3 — 계약 1-1): 문화권 단위 줄 · 띠 form

/// 문화권 단위 줄의 번호와 내용(글자 차례가 아니라 id 차례 — 통째 짓기와 번호까지 같은지 본다).
const SPHERE_IDS: &str = "SELECT CAST(id AS TEXT),kind||'|'||sphere||'|'||name||'|'||uid FROM sphere_lines ORDER BY id";

#[test]
fn a_layout_with_only_other_sphere_lines_rewrites_the_globals_like_a_full_build() {
    // 문화권 단위 줄(`sphere_lines`)은 온 판('*')의 조각 — 그것만 바뀐 배치는 다시 쓸 트랙이 없고 온 판만 고쳐 적는다(r.globals). 표는 통째로 지우고
    // 배치 차례대로 다시 넣어 번호까지 통째 짓기와 같다.
    use serde_json::json;
    let set = ["a", "b", "c"];
    let path = full(&set, "ap-lines");
    let mut p = plan(&set);
    let lines = p["sphereLines"].as_array_mut().unwrap();
    lines[0]["name"] = json!("가람 큰 사람");
    lines.remove(1); // b의 사람 띠를 뺀다
    // 자료집 순번 없이 uid 앞머리(b/)로 자료집을 정하는 줄.
    lines.push(json!({"kind":2,"sphere":"s-west","start":common::plans::yr(1600),"end":common::plans::yr(1700),"name":"서녘 늦은 시대","uid":"b/ep-west",
        "color":0x9dbea8,"data":""}));
    let r = step_of(&path, &p, &set);
    assert!(r.globals && r.rewrote.is_empty() && r.added.is_empty() && r.removed.is_empty(), "{r:?}");
    assert_eq!(r.first_pos, 0, "바뀐 것이 온 판뿐이면 첫 자리 0");
    let want = full_of(&p, &set, "ap-lines-full");
    assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "canon이 통째 짓기와 다릅니다");
    same_records(&path, &want, "문화권 단위 줄만");
    assert_eq!(pairs(&path, SPHERE_IDS), pairs(&want, SPHERE_IDS), "번호까지 통째 짓기와 같다");
    assert_eq!(pairs(&path, SPHERE_IDS).len(), 4);
    let prints = "SELECT key,print FROM track_prints ORDER BY key";
    assert_eq!(pairs(&path, prints), pairs(&want, prints), "온 판 지문도 새것");
    // 같은 배치를 다시 넣으면 아무것도 하지 않는다.
    let again = step_of(&path, &p, &set);
    assert!(!again.globals && again.rewrote.is_empty() && !again.names, "{again:?}");
}

#[test]
fn removing_the_middle_pack_leaves_no_number_of_it_in_sphere_lines() {
    // 가운데 DLC(b)를 빼면 c의 자료집 순번이 2 → 1로 밀린다. b의 사람 띠는 사라지고, 남는 줄의 자료집 번호는 저장소에 남은 자료집의 것이다(뺀 b의 번호가 남지 않음).
    // 다시 넣으면 b는 새 번호를 받고 b의 줄도 그 번호로 — 둘 다 글자 id로 통째 짓기와 같다.
    let path = full(&["a", "b", "c"], "ap-lines-mid");
    let keys: serde_json::Value = serde_json::from_str(&meta(&path)["pack_keys"]).unwrap();
    let b_id: i64 = keys.as_object().unwrap().iter().find(|(_, v)| *v == "b").map(|(n, _)| n.parse().unwrap()).unwrap();
    let packs_of_lines = |path: &std::path::Path| -> Vec<i64> {
        let db = rusqlite::Connection::open(path).unwrap();
        let list: Vec<i64> = db.prepare("SELECT pack FROM sphere_lines ORDER BY id").unwrap().query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect();
        list
    };
    assert!(packs_of_lines(&path).contains(&b_id), "장면: b의 사람 띠가 b의 번호로 들어 있다");
    let r = step(&path, &["a", "c"], &["b".to_string()]);
    assert!(r.globals, "{r:?}");
    assert!(!packs_of_lines(&path).contains(&b_id), "뺀 b의 번호가 남음: {:?}", packs_of_lines(&path));
    let orphans: i64 = rusqlite::Connection::open(&path).unwrap()
        .query_row("SELECT count(*) FROM sphere_lines WHERE pack NOT IN (SELECT id FROM packs)", [], |r| r.get(0)).unwrap();
    assert_eq!(orphans, 0, "없는 자료집을 가리키는 줄");
    let want = full(&["a", "c"], "ap-lines-mid-full");
    same_records(&path, &want, "가운데 DLC 빼기");
    assert_eq!(pairs(&path, SPHERE_IDS), pairs(&want, SPHERE_IDS));
    // 다시 넣기 — b는 새 번호(끝)를 받는다.
    step(&path, &["a", "b", "c"], &[]);
    let want = full(&["a", "b", "c"], "ap-lines-mid-back");
    same_records(&path, &want, "가운데 DLC 다시 넣기");
    assert_eq!(pairs(&path, SPHERE_IDS), pairs(&want, SPHERE_IDS));
}

#[test]
fn sphere_lines_never_stretch_the_view_range() {
    // 보는 범위(`meta.min` · `max`)는 문화권 단위 줄을 보지 않는다(짓기와 같다 — kind 3은 0분 · 1970년). 큰 장면은 1000 ~ 1900년이라 0분도, 2100년의 사람 띠도 밖이다.
    use serde_json::json;
    let base = big(2, 2, 40);
    let mut with = base.clone();
    with["sphereLines"] = json!([
        {"kind":3,"sphere":"s","start":0,"end":0,"name":"큰 간지","uid":"","color":0,"data":{"names":["갑", "을"],"start":4,"label":"큰 간지"},"pack":0},
        {"kind":1,"sphere":"s","start":common::plans::yr(2100),"end":common::plans::yr(2200),"name":"먼 사람","uid":"big/f-1","color":0,"data":"[]"}
    ]);
    let path = full_of(&base, &["big"], "ap-lines-range");
    let range = |p: &std::path::Path| (common::meta_i64(p, "min"), common::meta_i64(p, "max"));
    let before = range(&path);
    assert!(before.1 < 0, "장면: 0분(1970년)이 보는 범위 밖 — {before:?}");
    let r = step_of(&path, &with, &["big"]);
    assert!(r.globals && r.rewrote.is_empty(), "{r:?}");
    assert_eq!(range(&path), before, "줄을 넣어도 보는 범위는 그대로");
    let want = full_of(&with, &["big"], "ap-lines-range-full");
    assert_eq!(range(&want), before, "통째 짓기도 넓히지 않는다");
    same_meta(&path, &want, "문화권 단위 줄과 보는 범위");
    common::same::same_schema4(&path, &want, "문화권 단위 줄과 보는 범위");
    // 빼도 그대로(옛 끝값을 남은 것이 여전히 가진다).
    step_of(&path, &base, &["big"]);
    assert_eq!(range(&path), before);
    assert!(pairs(&path, SPHERE_IDS).is_empty(), "배치에 줄이 없으면 표도 빈다");
}

#[test]
fn a_covering_layout_leaves_sphere_lines_and_the_globals_print_to_the_next_whole_apply() {
    // 걸음 3 ③: 덮는 트랙만 주는 배치(메이커 `.htlayout` — `Covers::Tracks`)는 문화권 단위 줄이 달라도 거절하지 않는다(켠 DLC에 따라 사람 띠가 늘 달라진다 —
    // 문화권 · 간지 설정 메타와 같은 갈래). 표도 온 판 지문('*')도 그대로 두어, 다음 모두 덮는 apply가 온 판이 다름을 보고 채운다.
    use serde_json::json;
    let set = ["a", "b", "c"];
    let path = full(&set, "ap-lines-cover");
    let star = "SELECT key,print FROM track_prints WHERE key='*'";
    let (lines_before, star_before) = (pairs(&path, SPHERE_IDS), pairs(&path, star));
    let mut p = plan(&set);
    p["sphereLines"][0]["name"] = json!("가람 큰 사람");
    let at = p["periods"].as_array().unwrap().iter().position(|x| x["uid"] == "a/ta-2").unwrap();
    p["periods"][at]["color"] = json!(0x123456); // ta도 다시 쓰게
    let o = packs_of(&set);
    let covers = Covers::Tracks(["ta".to_string()].into_iter().collect());
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &o, covers, remove: &[] })).unwrap();
    assert!(r.rewrote.contains(&"ta".to_string()) && !r.globals, "{r:?}");
    assert_eq!(pairs(&path, SPHERE_IDS), lines_before, "덮는 트랙만 주는 배치는 문화권 단위 줄을 적지 않는다");
    assert_eq!(pairs(&path, star), star_before, "온 판 지문도 그대로");
    // 다음 모두 덮는 apply가 채운다(트랙은 이미 같아 다시 쓰지 않는다).
    let r = step_of(&path, &p, &set);
    assert!(r.globals && r.rewrote.is_empty(), "{r:?}");
    let want = full_of(&p, &set, "ap-lines-cover-full");
    assert!(canon_store(&path, &quick_q()).unwrap() == canon_store(&want, &quick_q()).unwrap(), "canon이 통째 짓기와 다릅니다");
    same_records(&path, &want, "덮는 트랙 뒤 모두 덮는 apply");
    assert_eq!(pairs(&path, SPHERE_IDS), pairs(&want, SPHERE_IDS));
}

#[test]
fn a_band_form_is_rewritten_with_its_track_like_a_full_build() {
    // 띠의 `form`(스키마 4)은 트랙 조각에 든다 — 그 띠의 트랙만 다시 쓰고 값이 통째 짓기와 같다.
    use serde_json::json;
    let path = full(&["a", "c"], "ap-form");
    let mut p = plan(&["a", "c"]);
    for b in p["periods"].as_array_mut().unwrap() {
        if b["uid"] == "c/tc-1" {
            b["form"] = json!(9 | 3 << 10); // 단체 · 공동
        }
    }
    let r = step_of(&path, &p, &["a", "c"]);
    assert_eq!((r.rewrote.clone(), r.globals), (vec!["tc".to_string()], false), "{r:?}");
    let want = full_of(&p, &["a", "c"], "ap-form-full");
    same_records(&path, &want, "띠 form");
    let form: i64 = rusqlite::Connection::open(&path).unwrap().query_row("SELECT form FROM periods WHERE uid='c/tc-1'", [], |r| r.get(0)).unwrap();
    assert_eq!(form, 9 | 3 << 10);
}

//! 같음의 눈(계획 P4 과제 1b): `canon_store`가 번호(id) 대신 uid · 열쇠 · 내용으로 적은 답 묶음(layout 답 · 풀어 낸 타일)이
//! 같은 배치에서는 같고 다른 배치에서는 다르며, 번호를 하나도 흘리지 않는가. 그리고 작은 배치 장면(`tests/common/plans.rs`)이
//! 가져오기에 받아들여지고 보는 범위를 넓히는가.
mod common;
use archive_engine::bandref::band_fields;
use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::legacy::import_layout_value;
use common::plans::{big, packs_of, plan};
use serde_json::{json, Value};
use std::path::PathBuf;

/// 장면을 지은 저장소(검사마다 다른 이름).
fn built(packs: &[&str], name: &str) -> PathBuf {
    let path = common::scratch(name);
    import_layout_value(&plan(packs), &packs_of(packs), &path).unwrap_or_else(|e| panic!("{packs:?}을 짓지 못했습니다: {e}"));
    path
}

/// 단계를 고루 — 그 자리에서 세는 단계(6) · 요약을 읽는 단계(8 · 11 · 14). 가장 촘촘한 단계(0 · 4)는 자료가 놓인 열이 사건 수만큼이라
/// 한 번에 3 ~ 4초씩 들어 `dense_levels_see_one_deleted_event`만 따로 본다.
fn opts() -> CanonOpts {
    CanonOpts { levels: vec![6, 8, 11, 14], max_x: 16, queries: false }
}

fn meta_min(path: &PathBuf) -> i64 {
    let db = rusqlite::Connection::open(path).unwrap();
    db.query_row("SELECT value FROM meta WHERE key='min'", [], |r| r.get::<_, String>(0)).unwrap().parse().unwrap()
}

/// 결과 안에서 이름이 `id`인 정수를 모두 찾는다(어디에 있었는지 길로).
fn numbered_ids(v: &Value, at: &str, out: &mut Vec<String>) {
    match v {
        Value::Object(map) => {
            for (k, child) in map {
                if k == "id" && (child.is_i64() || child.is_u64()) {
                    out.push(format!("{at}.id = {child}"));
                }
                numbered_ids(child, &format!("{at}.{k}"), out);
            }
        }
        Value::Array(list) => list.iter().enumerate().for_each(|(i, child)| numbered_ids(child, &format!("{at}[{i}]"), out)),
        _ => {}
    }
}

/// 그 보기(켠 자료집 · 변형)의 타일 목록.
fn view<'a>(canon: &'a Value, packs: usize, variants: &[&str]) -> &'a [Value] {
    canon["views"].as_array().unwrap().iter()
        .find(|v| v["packs"].as_array().unwrap().len() == packs && v["variants"] == serde_json::json!(variants))
        .and_then(|v| v["tiles"].as_array()).map(Vec::as_slice).unwrap_or(&[])
}

#[test]
fn same_plan_built_twice_gives_the_same_canon() {
    let (one, two) = (built(&["a", "b", "c"], "cn-same-1"), built(&["a", "b", "c"], "cn-same-2"));
    let (x, y) = (canon_store(&one, &opts()).unwrap(), canon_store(&two, &opts()).unwrap());
    assert!(x == y, "같은 배치를 두 번 지은 저장소의 답 묶음이 다릅니다");
    // 비어서 같은 것이 아니다: 트랙 넷(ta · tb · tc · 판) · 모든 자료집을 켠 보기에 타일이 있다.
    assert_eq!(x["layout"]["tracks"].as_array().unwrap().len(), 4);
    assert!(!view(&x, 3, &[]).is_empty());
    // 큰 배치(과제 7c의 꼴)도 지어지고 두 번 지으면 같다.
    let (p, o) = (big(3, 4, 200), packs_of(&["big"]));
    let (b1, b2) = (common::scratch("cn-big-1"), common::scratch("cn-big-2"));
    import_layout_value(&p, &o, &b1).unwrap();
    import_layout_value(&p, &o, &b2).unwrap();
    assert!(canon_store(&b1, &opts()).unwrap() == canon_store(&b2, &opts()).unwrap());
}

#[test]
fn different_combination_gives_a_different_canon() {
    let ac = canon_store(&built(&["a", "c"], "cn-diff-ac"), &opts()).unwrap();
    let abc = canon_store(&built(&["a", "b", "c"], "cn-diff-abc"), &opts()).unwrap();
    assert!(ac != abc, "b가 있고 없는 저장소의 답 묶음이 같습니다");
    // a@2는 ta 첫 띠의 색만 다르다 — 그것도 드러난다.
    let a2c = canon_store(&built(&["a@2", "c"], "cn-diff-a2c"), &opts()).unwrap();
    assert!(ac != a2c, "ta 첫 띠의 색을 바꾼 판이 같게 보입니다");
    assert_eq!(ac["layout"]["tracks"], a2c["layout"]["tracks"], "띠 색 말고는 트랙의 꼴이 같아야 합니다");
}

#[test]
fn canon_leaks_no_numbers() {
    let canon = canon_store(&built(&["a", "b", "c"], "cn-ids"), &opts()).unwrap();
    let mut found = Vec::new();
    numbered_ids(&canon, "", &mut found);
    assert!(found.is_empty(), "번호가 남았습니다: {:?}", &found[..found.len().min(8)]);
    // 번호 대신 글자 id · 트랙 열쇠 · uid로 적혔다.
    let layout = &canon["layout"];
    assert_eq!(layout["packs"].as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap()).collect::<Vec<_>>(), vec!["a", "b", "c"]);
    let tracks: Vec<&str> = layout["tracks"].as_array().unwrap().iter().map(|t| t["id"].as_str().unwrap()).collect();
    assert_eq!(tracks, vec!["ta", "tb", "tc", "__board:view:a1"]);
    assert!(layout["tracks"].as_array().unwrap().iter().all(|t| t["pack"].is_string()));
    let variants: Vec<&str> = layout["variants"].as_array().unwrap().iter().map(|v| v["key"].as_str().unwrap()).collect();
    assert_eq!(variants, vec!["host:a/ta-host", "scope:c/sc-1", "view:a1"]);
    assert_eq!(layout["variants"][0]["band"], "a/ta-host", "변형의 상위 띠는 uid로");
    // 문화권 단위 줄(스키마 4 · 계약 1-1): 번호 `id`는 빠지고 자료집은 글자 id로, 차례는 표의 id 차례(= 배치 차례 — 이 합성 장면의 배치는 사람 띠를 앞에 적었다) 그대로.
    let lines = layout["sphereLines"].as_array().unwrap();
    assert_eq!(lines.iter().map(|l| (l["kind"].as_i64().unwrap(), l["pack"].as_str().unwrap(), l["uid"].as_str().unwrap())).collect::<Vec<_>>(),
        vec![(1, "a", "a/fig-1"), (1, "b", "b/fig-2"), (2, "a", "a/ep-east"), (3, "c", "")]);
    assert!(lines.iter().all(|l| l.get("id").is_none() && l["data"].is_string()), "{lines:?}");
    // 띠의 form(타일 띠 구역 열 10)도 적힌다 — 장면의 FORMS 그대로, 나머지 띠는 0.
    let all_bands: Vec<&Value> = canon["views"].as_array().unwrap().iter().flat_map(|v| v["tiles"].as_array().unwrap())
        .flat_map(|t| t["bands"].as_array().unwrap()).collect();
    for (uid, form) in common::plans::FORMS {
        assert!(all_bands.iter().any(|b| b["uid"] == uid && b["form"] == form), "{uid}의 form {form}이 타일에 없습니다");
    }
    assert!(all_bands.iter().all(|b| b["form"].is_u64()), "띠마다 form이 적힌다");
    let text = canon.to_string();
    for uid in ["a/ta-1", "b/ta-late", "c/tc-1", "a/e0", "a/e-move"] {
        assert!(text.contains(&format!("\"{uid}\"")), "{uid}가 답 묶음에 없습니다");
    }
    // c의 변형을 켜면 tc의 띠가 ta의 줄(자리 3)로 이사해 그 묶음의 타일에 실린다.
    let moved = view(&canon, 3, &["scope:c/sc-1"]).iter().any(|t| {
        t["bands"].as_array().unwrap().iter().any(|b| b["uid"] == "c/tc-1" && b["row"] == 3)
    });
    assert!(moved, "c의 이사가 ta의 줄에 보이지 않습니다");
}

#[test]
fn dense_levels_see_one_deleted_event() {
    // 촘촘한 단계는 가로 타일이 수천 ~ 수만 열이라 고르게 16열만 뜨면 사건이 거의 안 잡힌다 — 자료가 놓인 열을 함께 떠야 한다.
    let path = built(&["a", "b", "c"], "cn-dense");
    let copy = common::scratch("cn-dense-del");
    std::fs::copy(&path, &copy).unwrap();
    let gone = rusqlite::Connection::open(&copy).unwrap().execute("DELETE FROM events WHERE uid='a/e150'", []).unwrap();
    assert_eq!(gone, 1);
    for level in [0, 4] {
        let o = CanonOpts { levels: vec![level], max_x: 16, queries: false };
        assert!(canon_store(&path, &o).unwrap() != canon_store(&copy, &o).unwrap(), "단계 {level}에서 지운 사건 하나를 보지 못했습니다");
    }
}

/// 배치의 `periods` 차례를 거꾸로 하고 일반 항목의 띠 번호 칸(bandref — '`periods` 배열 자리 + 1')을 새 자리로 맞춘다.
/// 내용은 같고 띠 번호만 다른 배치다. `hides`는 칸 · 항목의 자리를 가리키므로(띠가 아님) 그대로 맞다.
fn periods_reversed(plan: &Value) -> Value {
    assert!(plan["boards"]["periods"].is_null(), "판의 띠가 있으면 띠 번호의 자리가 그 뒤로 이어진다 — 이 도움은 그 경우를 다루지 않는다");
    let old: Vec<String> = plan["periods"].as_array().unwrap().iter().map(|p| p["uid"].as_str().unwrap().to_owned()).collect();
    let new: Vec<String> = old.iter().rev().cloned().collect();
    let mut out = plan.clone();
    let mut periods = plan["periods"].as_array().unwrap().clone();
    periods.reverse();
    out["periods"] = json!(periods);
    let fix = |items: &mut Value| {
        for it in items.as_array_mut().unwrap() {
            let v = |k: &str| it[k].as_i64().unwrap_or(0);
            for f in band_fields(v("section"), v("a"), v("b"), v("c"), v("d")) {
                let key = ["a", "b", "c", "d"][f];
                let n = it[key].as_i64().unwrap();
                if n > 0 {
                    let uid = &old[n as usize - 1];
                    it[key] = json!(new.iter().position(|u| u == uid).unwrap() + 1);
                }
            }
        }
    };
    fix(&mut out["items"]);
    fix(&mut out["boards"]["items"]);
    out
}

#[test]
fn band_number_fields_compare_by_uid() {
    let packs = ["a", "b", "c"];
    let (p, q) = (plan(&packs), periods_reversed(&plan(&packs)));
    // 띠 번호 칸의 값이 실제로 다르다(c의 구역 47 d · 49 b가 남의 트랙 띠를 가리킨다).
    let pick = |plan: &Value, section: i64| plan["items"].as_array().unwrap().iter().find(|it| it["section"] == section).cloned().unwrap();
    assert_ne!(pick(&p, 47)["d"], pick(&q, 47)["d"]);
    assert_ne!(pick(&p, 49)["b"], pick(&q, 49)["b"]);
    let one = built(&packs, "cn-band-1");
    let two = common::scratch("cn-band-2");
    import_layout_value(&q, &packs_of(&packs), &two).unwrap();
    // (가) 띠 차례만 다르고 띠 번호 칸이 같은 띠를 가리키면 같다.
    assert!(canon_store(&one, &opts()).unwrap() == canon_store(&two, &opts()).unwrap(), "띠 번호만 다른 같은 배치가 다르게 보입니다");
    // (나) 띠 번호 칸 하나가 다른 띠를 가리키면 다르다.
    let other = common::scratch("cn-band-3");
    std::fs::copy(&one, &other).unwrap();
    let changed = rusqlite::Connection::open(&other).unwrap()
        .execute("UPDATE items SET d=(SELECT id FROM periods WHERE uid='a/ta-1') WHERE section=47", []).unwrap();
    assert_eq!(changed, 1);
    assert!(canon_store(&one, &opts()).unwrap() != canon_store(&other, &opts()).unwrap(), "띠 번호 칸이 다른 띠를 가리켜도 같게 보입니다");
}

/// 줄 이름의 원소 JSON에는 배치의 트랙 순번(`track`)이 통째로 실린다(`fill`). 트랙을 고쳐 쓴 저장소(하위 배치 · 순번만 밀린 트랙)에서는
/// 그 순번이 통째 짓기와 달라지므로 canon은 원소가 든 줄의 트랙 열쇠로 견준다(판정 R17) — 순번만 낡은 저장소와 통째 짓기가 같다.
#[test]
fn row_label_track_numbers_compare_by_track_key() {
    let path = built(&["a", "b", "c"], "cn-label-1");
    let stale = common::scratch("cn-label-2");
    std::fs::copy(&path, &stale).unwrap();
    // apply 뒤의 꼴을 흉내: 줄 이름 원소의 트랙 순번만 다른 수로(앱은 이 값을 읽지 않는다).
    let changed = rusqlite::Connection::open(&stale).unwrap()
        .execute("UPDATE row_labels SET json=json_set(json,'$.track',json_extract(json,'$.track')+7)", []).unwrap();
    assert!(changed > 0);
    let o = CanonOpts { levels: vec![14], max_x: 4, queries: true };
    let (x, y) = (canon_store(&path, &o).unwrap(), canon_store(&stale, &o).unwrap());
    assert!(x["queries"]["row_labels"] == y["queries"]["row_labels"], "줄 이름 원소의 트랙 순번만 다른 저장소가 다르게 보입니다");
    assert!(x == y);
    // 트랙 열쇠로 적혔다.
    let text = x["queries"]["row_labels"].to_string();
    assert!(text.contains("\"track\":\"ta\"") && text.contains("\"track\":\"tc\""), "줄 이름의 트랙이 열쇠로 적히지 않았습니다");
}

/// 메아리 묶음(`echo`의 `groups`)은 연표 위에서 아래(자리) 차례이고, 같은 자리(같은 줄)의 띠 묶음끼리는 엔진이 띠 번호의 글자 견줌으로
/// 차례를 깬다(`query.rs` `echo_groups` — 7a 고침에서 찾음 · 판정 R28). 번호 동률은 계약 밖이라 엔진은 그대로 두고(R12) canon이 같은 자리의
/// 묶음끼리 내용 차례로 늘어놓는다 — 띠 번호만 다른 같은 배치가 같다. 자리가 다른 묶음의 차례는 그대로 견준다.
#[test]
fn echo_group_ties_compare_by_content() {
    let packs = ["a", "b", "c"];
    let one = built(&packs, "cn-echo-1");
    let two = common::scratch("cn-echo-2");
    import_layout_value(&periods_reversed(&plan(&packs)), &packs_of(&packs), &two).unwrap();
    // 무르지 않음을 볼 사본(7b 검토): 옮기기 전의 `one` 둘 — 아래에서 하나만 '가 둘째 나라'를 다른 자리로 옮긴다.
    let (kept, flipped) = (common::scratch("cn-echo-3"), common::scratch("cn-echo-4"));
    std::fs::copy(&one, &kept).unwrap();
    std::fs::copy(&one, &flipped).unwrap();
    // 두 저장소 모두 '가 둘째 나라'를 '가 큰 나라'의 줄로 옮겨 같은 자리의 묶음 둘을 만든다(둘의 내용은 같다 — 띠 번호만 2 · 3 ↔ 9 · 8).
    for path in [&one, &two] {
        let moved = rusqlite::Connection::open(path).unwrap()
            .execute("UPDATE periods SET row=(SELECT row FROM periods WHERE uid='a/ta-host') WHERE uid='a/ta-2'", []).unwrap();
        assert_eq!(moved, 1);
    }
    // canon이 고르는 첫 띠('가 첫 나라' — uid 차례의 처음)를 비춘 메아리: 엔진의 묶음 차례가 실제로 갈린다(이 검사가 겨누는 동률).
    let groups = |path: &PathBuf| -> Vec<String> {
        let (start, end): (i64, i64) = rusqlite::Connection::open(path).unwrap()
            .query_row("SELECT start,end FROM periods WHERE uid='a/ta-1'", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
        let answer = archive_engine::Store::open(path).unwrap().call(&json!({"op":"echo","spots":[{"uid":"a/ta-1","start":start,"end":end}]})).unwrap();
        answer["groups"].as_array().unwrap().iter().map(|g| g["uid"].as_str().unwrap().to_owned()).collect()
    };
    let (x, y) = (groups(&one), groups(&two));
    assert!(x.contains(&"a/ta-host".to_owned()) && x.contains(&"a/ta-2".to_owned()), "같은 자리의 묶음 둘이 메아리에 없습니다: {x:?}");
    assert_ne!(x, y, "띠 번호만 다른 두 저장소의 메아리 묶음 차례가 같습니다 — 동률이 생기지 않았습니다");
    let mut sorted = (x.clone(), y.clone());
    sorted.0.sort();
    sorted.1.sort();
    assert_eq!(sorted.0, sorted.1, "묶음의 차례 말고 내용이 다릅니다");
    // canon(조회 목록까지)은 같다.
    let o = CanonOpts { levels: vec![14], max_x: 4, queries: true };
    let (p, q) = (canon_store(&one, &o).unwrap(), canon_store(&two, &o).unwrap());
    assert!(p["queries"]["echo"] == q["queries"]["echo"], "같은 자리 묶음의 동률이 canon의 메아리를 가릅니다");
    assert!(p == q, "띠 번호만 다른 같은 배치의 canon이 다릅니다");
    // 무르지 않음(7b 검토): 한 저장소에서만 '가 둘째 나라'를 '가 첫 나라'의 줄(자리 0 — '가 큰 나라'보다 위)로 옮기면 두 묶음이 다른 자리에서
    // 차례가 뒤집힌다 — 같은 자리의 동률이 아니므로 canon의 메아리도 다르다.
    let moved = rusqlite::Connection::open(&flipped).unwrap()
        .execute("UPDATE periods SET row=(SELECT row FROM periods WHERE uid='a/ta-1') WHERE uid='a/ta-2'", []).unwrap();
    assert_eq!(moved, 1);
    let (k, f) = (groups(&kept), groups(&flipped));
    let at = |list: &[String], uid: &str| list.iter().position(|g| g == uid).unwrap_or_else(|| panic!("{uid} 묶음이 메아리에 없습니다: {list:?}"));
    assert!(at(&k, "a/ta-host") < at(&k, "a/ta-2") && at(&f, "a/ta-2") < at(&f, "a/ta-host"), "자리를 옮겨도 묶음 차례가 그대로입니다: {k:?} · {f:?}");
    let (ck, cf) = (canon_store(&kept, &o).unwrap(), canon_store(&flipped, &o).unwrap());
    assert!(ck["queries"]["echo"] != cf["queries"]["echo"], "자리가 다른 묶음의 차례가 뒤집혀도 canon의 메아리가 같습니다");
}

/// 옛 줄 범위 조회(`range`)는 사건 번호 차례로만 낸다(`Store::range`). 덧붙여 넣은 사건은 끝 번호를 받아 같은 줄 묶음 안의 차례가 통째 짓기와
/// 갈린다(과제 7b 실자료 nest-scene — 앞 트랙에 사건을 더하는 DLC). 번호로만 정해지는 차례라 계약 밖이다(판정 R12) — canon은 묶음마다 내용 차례로.
#[test]
fn range_lists_compare_by_content() {
    let packs = ["a", "b", "c"];
    let one = built(&packs, "cn-range-1");
    // 사건 차례만 거꾸로 — 내용은 같고 사건 번호만 다르다(배치는 사건을 uid로만 가리킨다).
    let mut reversed = plan(&packs);
    reversed["events"].as_array_mut().unwrap().reverse();
    let two = common::scratch("cn-range-2");
    import_layout_value(&reversed, &packs_of(&packs), &two).unwrap();
    // 엔진의 답은 첫 줄 묶음의 차례가 실제로 갈린다(이 검사가 겨누는 차례) — 담긴 사건은 같다.
    let titles = |path: &PathBuf| -> Vec<String> {
        let store = archive_engine::Store::open(path).unwrap();
        let (lo, hi): (String, String) = (store.db.query_row("SELECT value FROM meta WHERE key='min'", [], |r| r.get(0)).unwrap(),
            store.db.query_row("SELECT value FROM meta WHERE key='max'", [], |r| r.get(0)).unwrap());
        store.range(lo.parse().unwrap(), hi.parse().unwrap(), 0, 8, 0, 1801).unwrap().iter().map(|e| e["title"].as_str().unwrap().to_owned()).collect()
    };
    let (x, y) = (titles(&one), titles(&two));
    assert!(x.len() > 1, "첫 줄 묶음에 사건이 둘도 없습니다");
    assert_ne!(x, y, "사건 번호만 다른 두 저장소의 줄 범위 조회 차례가 같습니다");
    let mut sorted = (x.clone(), y.clone());
    sorted.0.sort();
    sorted.1.sort();
    assert_eq!(sorted.0, sorted.1, "줄 범위 조회의 차례 말고 담긴 사건이 다릅니다");
    let o = CanonOpts { levels: vec![14], max_x: 4, queries: true };
    let (p, q) = (canon_store(&one, &o).unwrap(), canon_store(&two, &o).unwrap());
    assert!(p["queries"]["range"] == q["queries"]["range"], "사건 번호 차례가 canon의 줄 범위 조회를 가릅니다");
    // 무르지 않음(7b 검토): 사건 하나가 빠진 저장소(배치에서 a/e150 하나만 뺌)는 canon의 줄 범위 조회가 다르다 — 묶음 안 차례만 내용으로 늘어놓는다.
    let mut fewer = plan(&packs);
    let events = fewer["events"].as_array_mut().unwrap();
    let before = events.len();
    events.retain(|e| e["uid"] != "a/e150");
    assert_eq!(events.len(), before - 1);
    let three = common::scratch("cn-range-3");
    import_layout_value(&fewer, &packs_of(&packs), &three).unwrap();
    let r = canon_store(&three, &o).unwrap();
    assert!(p["queries"]["range"] != r["queries"]["range"], "사건 하나가 빠져도 canon의 줄 범위 조회가 같습니다");
}

#[test]
fn pack_b_widens_the_view_range() {
    let a = built(&["a"], "cn-range-a");
    let ab = built(&["a", "b"], "cn-range-ab");
    assert!(meta_min(&ab) < meta_min(&a), "b를 더해도 보는 범위의 시작이 그대로입니다");
}

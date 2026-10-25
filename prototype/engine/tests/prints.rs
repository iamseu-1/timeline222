//! 트랙 지문 · 가리키는 uid · 다시 쓸 트랙 고르기 · 조합 대조(계획 P4 과제 4 — `patch.rs`의 앞 절반).
//! 장면은 `common::plans`(자료집 a · b · c · `a@2`). 트랙 열쇠: `ta` · `tb` · `tc` · 판 트랙 [`BOARD`].
mod common;
use archive_engine::bandref::band_fields;
use archive_engine::legacy::import_layout_value;
use archive_engine::patch::{check_combination, choose, dependents, hiders, prints, sub_plan, Covers, Prints};
use common::plans::{packs_of, plan, yr, BOARD_CELL, BOARD_ITEM, HIDDEN_CELL, HIDDEN_ITEM};
use rusqlite::{Connection, OpenFlags};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

/// 장면의 판 트랙(`__board:view:a1`)의 지문 열쇠.
const BOARD: &str = "board:__board:view:a1";

fn keys(list: &[&str]) -> BTreeSet<String> {
    list.iter().map(|s| s.to_string()).collect()
}

/// 그 조합을 통째로 지은 저장소.
fn full(set: &[&str], name: &str) -> PathBuf {
    let path = common::scratch(name);
    import_layout_value(&plan(set), &packs_of(set), &path).unwrap();
    path
}

fn open(path: &Path) -> Connection {
    Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap()
}

fn printed(set: &[&str]) -> Prints {
    prints(&plan(set)).unwrap()
}

/// 트랙 순번 하나를 고쳐 적는다(음수 — 공통 줄 — 는 그대로).
fn remap_track(v: &mut Value, i: usize, j: usize) {
    if let Some(t) = v.as_i64().filter(|t| *t >= 0) {
        let t = t as usize;
        *v = json!(if t == i { j } else if t == j { i } else { t });
    }
}

/// 트랙 i · j의 차례를 바꾼 사본 — 트랙을 가리키는 순번(`track` · `toTrack`)을 모두 고쳐 적는다(내용 · 다른 배열의 차례는 그대로).
fn swap_tracks(plan: &Value, i: usize, j: usize) -> Value {
    let mut p = plan.clone();
    p["tracks"].as_array_mut().unwrap().swap(i, j);
    for boards in [false, true] {
        let root = if boards { &mut p["boards"] } else { &mut p };
        for list in ["periods", "events", "items", "rowLabels", "axis", "variants"] {
            for v in root.get_mut(list).and_then(Value::as_array_mut).into_iter().flatten() {
                if let Some(t) = v.get_mut("track") {
                    remap_track(t, i, j);
                }
                for part in ["rows", "moves", "groups"] {
                    for r in v.get_mut(part).and_then(Value::as_array_mut).into_iter().flatten() {
                        for key in ["track", "toTrack"] {
                            if let Some(t) = r.get_mut(key) {
                                remap_track(t, i, j);
                            }
                        }
                    }
                }
            }
        }
    }
    p
}

/// 배열에서 `pick`이 고른 것을 맨 앞으로(서로의 차례는 그대로) — 옛 자리 → 새 자리를 함께 돌려준다.
fn to_front(list: &[Value], pick: impl Fn(&Value) -> bool) -> (Vec<Value>, Vec<usize>) {
    let order: Vec<usize> = (0..list.len()).filter(|&i| pick(&list[i])).chain((0..list.len()).filter(|&i| !pick(&list[i]))).collect();
    let mut at = vec![0; list.len()];
    for (new, old) in order.iter().enumerate() {
        at[*old] = new;
    }
    (order.iter().map(|&i| list[i].clone()).collect(), at)
}

/// `c`의 띠 · 칸 · 일반 항목을 배열 맨 앞으로 옮긴 사본 — 띠 번호 칸(`bandref`)과 변형의 `hides[].at`도 새 자리로 고쳐 적는다.
/// 내용은 그대로이고 자리(번호)만 밀린다.
fn c_first(plan: &Value) -> Value {
    let mut p = plan.clone();
    let tc = p["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap();
    let (periods, period_at) = to_front(p["periods"].as_array().unwrap(), |v| v["uid"].as_str().unwrap().starts_with("c/"));
    let (cells, cell_at) = to_front(p["cells"].as_array().unwrap(), |v| v["period"].as_str().unwrap().starts_with("c/"));
    let (items, item_at) = to_front(p["items"].as_array().unwrap(), |v| v["track"] == tc);
    p["periods"] = json!(periods);
    p["cells"] = json!(cells);
    p["items"] = json!(items);
    for boards in [false, true] {
        let root = if boards { &mut p["boards"] } else { &mut p };
        for it in root["items"].as_array_mut().unwrap() {
            let n = |k: &str| it[k].as_i64().unwrap_or(0);
            for f in band_fields(n("section"), n("a"), n("b"), n("c"), n("d")) {
                let name = ["a", "b", "c", "d"][f];
                let old = it[name].as_i64().unwrap();
                if old > 0 {
                    it[name] = json!(period_at[old as usize - 1] + 1);
                }
            }
        }
    }
    // 판의 변형도 겉 배열의 자리를 가리킨다(`boards.cells` · `boards.items`는 겉 뒤에 이어지므로 그 자리는 그대로).
    for boards in [false, true] {
        let root = if boards { &mut p["boards"] } else { &mut p };
        for v in root["variants"].as_array_mut().unwrap() {
            for h in v["hides"].as_array_mut().unwrap() {
                let at = h["at"].as_u64().unwrap() as usize;
                h["at"] = json!(if h["kind"] == 3 { cell_at[at] } else { item_at[at] });
            }
        }
    }
    p
}

#[test]
fn 다른_dlc가_트랙을_더해도_제_트랙의_지문은_그대로다() {
    let (one, two) = (printed(&["a"]), printed(&["a", "c"]));
    assert_eq!(one.tracks["ta"].print, two.tracks["ta"].print, "c는 ta에 아무것도 얹지 않는다");
    assert_eq!(one.tracks[BOARD].print, two.tracks[BOARD].print, "판 트랙의 순번만 밀린다");
    assert!(!one.tracks.contains_key("tc") && two.tracks.contains_key("tc"), "tc는 새것");
    assert_eq!(one.order, vec!["ta", BOARD]);
    assert_eq!(two.order, vec!["ta", "tc", BOARD]);
    assert_eq!(two.tracks["ta"].print.len(), 64, "지문은 SHA-256 16진 글");

    // 지은 저장소의 track_prints = 그 배치의 지문(온 판은 열쇠 "*") · needs = {uids, rows, own}.
    let path = full(&["a", "c"], "pr-same");
    let db = open(&path);
    let mut stmt = db.prepare("SELECT key,print,needs FROM track_prints ORDER BY key").unwrap();
    let rows: Vec<(String, String, String)> = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).unwrap().map(Result::unwrap).collect();
    let got: BTreeSet<String> = rows.iter().map(|r| r.0.clone()).collect();
    assert_eq!(got, keys(&["*", "ta", "tc", BOARD]));
    for (key, print, needs) in &rows {
        if key == "*" {
            assert_eq!(print, &two.globals);
            continue;
        }
        let t = &two.tracks[key];
        assert_eq!(print, &t.print, "{key}");
        assert_eq!(serde_json::from_str::<Value>(needs).unwrap(), json!({"uids":t.needs_uids,"rows":t.row_targets,"own":t.uids,"hides":t.hides}), "{key}");
    }
}

#[test]
fn 트랙에_얹으면_그_트랙과_온_판의_지문이_바뀐다() {
    let (one, two) = (printed(&["a"]), printed(&["a", "b"]));
    assert_ne!(one.tracks["ta"].print, two.tracks["ta"].print, "b가 ta에 줄 · 띠 · 사건을 얹는다");
    assert!(!one.tracks.contains_key("tb") && two.tracks.contains_key("tb"), "tb는 새것");
    assert_ne!(one.globals, two.globals, "자료집 목록 · 문화권(s-west)이 바뀐다");
    assert_eq!(one.tracks[BOARD].print, two.tracks[BOARD].print, "판은 b와 상관없다");
}

#[test]
fn 순번과_자리만_밀린_배치는_지문과_가리킴이_같다() {
    // ① 트랙 차례만 바꾼 사본.
    let base = printed(&["a", "c"]);
    let swapped = prints(&swap_tracks(&plan(&["a", "c"]), 0, 1)).unwrap();
    assert_eq!(swapped.order, vec!["tc", "ta", BOARD]);
    for key in ["ta", "tc", BOARD] {
        assert_eq!(swapped.tracks[key], base.tracks[key], "{key}");
    }
    assert_eq!(swapped.globals, base.globals);
    // ② 자료집 차례(b · c)를 바꿈 — 자료집 순번 · 트랙 순번 · 띠 자리가 다 밀린다. 트랙 지문은 같고 온 판(자료집 목록)만 다르다.
    let (bc, cb) = (printed(&["a", "b", "c"]), printed(&["a", "c", "b"]));
    assert_eq!(bc.order, vec!["ta", "tb", "tc", BOARD]);
    assert_eq!(cb.order, vec!["ta", "tc", "tb", BOARD]);
    for key in ["ta", "tb", "tc", BOARD] {
        assert_eq!(cb.tracks[key], bc.tracks[key], "{key}");
    }
    assert_ne!(cb.globals, bc.globals);
    // ③ c의 띠 · 칸 · 항목을 배열 맨 앞으로 — 띠 번호 칸 · 가리기(`hides[].at`)의 자리가 밀려도 내용으로 적으므로 같다.
    let shuffled = c_first(&plan(&["a", "c"]));
    assert_ne!(shuffled["variants"][0]["hides"], plan(&["a", "c"])["variants"][0]["hides"], "가리기의 자리가 실제로 밀렸다");
    let moved = prints(&shuffled).unwrap();
    for key in ["ta", "tc", BOARD] {
        assert_eq!(moved.tracks[key], base.tracks[key], "{key}");
    }
}

#[test]
fn 남의_트랙을_가리키는_uid와_줄() {
    for set in [&["a", "c"][..], &["a", "b", "c"]] {
        let p = printed(set);
        let tc = &p.tracks["tc"];
        // 일반 항목의 ref(a/ta-2 · b/ta-late — b가 없어도 ref 글은 같다) · 띠 번호 칸(구역 47의 d = a/ta-2).
        assert_eq!(tc.needs_uids, keys(&["a/ta-2", "b/ta-late"]), "{set:?}");
        // 변형 scope:c/sc-1의 이사 · 묶음이 ta의 줄 3을 가리킨다.
        assert_eq!(tc.row_targets, keys(&["ta"]), "{set:?}");
        assert_eq!(tc.uids, keys(&["c/tc-1", "c/tc-2", "c/e0", "c/e1", "c/e2", "c/e3", "c/e4"]), "{set:?}");
        let ta = &p.tracks["ta"];
        assert!(ta.needs_uids.is_empty() && ta.row_targets.is_empty(), "{set:?}: ta는 제 것만 가리킨다");
        assert!(ta.uids.contains("a/ta-member") && ta.uids.contains("a/e-only") && ta.uids.contains("a/e-move"), "변형에서만 있는 띠 · 사건도 제 것");
        assert_eq!(ta.uids.contains("b/ta-late"), set.contains(&"b"), "b가 ta에 얹은 띠는 ta의 것");
        // 판: 관계선의 ref · 띠 번호 칸 · 이사가 ta의 띠를 · 변형 줄(after −2)이 ta의 줄을 가리킨다.
        assert_eq!(p.tracks[BOARD].needs_uids, keys(&["a/ta-1", "a/ta-2"]), "{set:?}");
        assert_eq!(p.tracks[BOARD].row_targets, keys(&["ta"]), "{set:?}");
        assert!(p.tracks[BOARD].uids.is_empty());
        // 판 변형이 ta의 칸 · 관계선을 가린다(R16) — 가리는 대상 트랙. ta의 소속 펼치기는 제 것만 가린다.
        assert_eq!(p.tracks[BOARD].hides, keys(&["ta"]), "{set:?}");
        assert!(ta.hides.is_empty() && tc.hides.is_empty(), "{set:?}");
    }
    let path = full(&["a", "b", "c"], "pr-deps");
    let db = open(&path);
    assert_eq!(dependents(&db, &keys(&["b/ta-late"])).unwrap(), keys(&["tc"]));
    assert_eq!(dependents(&db, &keys(&["a/ta-2"])).unwrap(), keys(&["tc", BOARD]));
    assert_eq!(dependents(&db, &keys(&["a/ta-1", "b/ta-late"])).unwrap(), keys(&["tc", BOARD]));
    assert!(dependents(&db, &keys(&["c/tc-1", "a/ta-host"])).unwrap().is_empty(), "제 것만 가리키는 uid는 남의 트랙이 기대지 않는다");
    assert_eq!(hiders(&db, &keys(&["ta"])).unwrap(), keys(&[BOARD]), "ta를 가리는 변형의 주인");
    assert!(hiders(&db, &keys(&["tb", "tc", BOARD])).unwrap().is_empty());
}

#[test]
fn 자료집을_더하면_얹힌_트랙과_가리키던_트랙을_다시_쓴다() {
    let path = full(&["a", "c"], "pr-add-b");
    let db = open(&path);
    let new = printed(&["a", "b", "c"]);
    let c = choose(&db, &new, &Covers::All).unwrap();
    assert_eq!(c.rewrite, keys(&["ta", "tc", BOARD]), "판이 가리는 ta를 다시 쓰므로 판도(R16)");
    assert_eq!(c.added, keys(&["tb"]));
    assert!(c.removed.is_empty() && c.uids_gone.is_empty());
    assert!(c.globals, "자료집 목록이 바뀐다");
    assert!(c.uids_new.contains("b/ta-late") && c.uids_new.contains("b/tb-1") && !c.uids_new.contains("a/ta-1"), "{:?}", c.uids_new);
    // tc의 지문이 그대로라도 가리키던 uid(b/ta-late)가 생기면 다시 쓴다(한 겹).
    let mut same_tc = new.clone();
    same_tc.tracks.get_mut("tc").unwrap().print = db.query_row("SELECT print FROM track_prints WHERE key='tc'", [], |r| r.get(0)).unwrap();
    let c = choose(&db, &same_tc, &Covers::All).unwrap();
    assert_eq!(c.rewrite, keys(&["ta", "tc", BOARD]), "b/ta-late가 생겨 tc를 다시 쓴다");
}

#[test]
fn 자료집을_빼면_사라진_트랙과_가리키던_트랙을_다시_쓴다() {
    let path = full(&["a", "b", "c"], "pr-remove-b");
    let db = open(&path);
    let new = printed(&["a", "c"]);
    let c = choose(&db, &new, &Covers::All).unwrap();
    assert_eq!(c.removed, keys(&["tb"]));
    assert_eq!(c.rewrite, keys(&["ta", "tc", BOARD]));
    assert!(c.added.is_empty() && c.uids_new.is_empty());
    assert!(c.uids_gone.contains("b/ta-late") && c.uids_gone.contains("b/tb-1") && c.uids_gone.contains("b/e-on0"), "{:?}", c.uids_gone);
    // 덮는 트랙만(ta) — 빠진 트랙은 그대로 두고(removed 없음), ta가 잃은 uid(b/ta-late)를 가리키던 tc는 다시 쓴다.
    let c = choose(&db, &new, &Covers::Tracks(keys(&["ta"]))).unwrap();
    assert!(c.removed.is_empty() && c.added.is_empty());
    assert_eq!(c.rewrite, keys(&["ta", "tc", BOARD]), "ta를 가리는 판도 다시 쓴다");
    assert!(c.uids_gone.contains("b/ta-late"));
    // 배치에 없는 트랙을 덮는다고 하면 거절.
    assert!(choose(&db, &new, &Covers::Tracks(keys(&["tb"]))).is_err());
}

#[test]
fn 색만_바꾼_판은_그_트랙과_가리는_판만_다시_쓰고_지문이_없으면_다_다시_쓴다() {
    let path = full(&["a", "c"], "pr-recolor");
    let db = open(&path);
    let c = choose(&db, &printed(&["a@2", "c"]), &Covers::All).unwrap();
    // tc의 ref · 이사는 그대로 맞아 번지지 않는다. 판은 ta의 칸 · 관계선을 가리므로 ta의 새 번호로 가리기를 다시 풀어야 한다(R16).
    assert_eq!(c.rewrite, keys(&["ta", BOARD]));
    assert_eq!(printed(&["a@2", "c"]).tracks[BOARD].print, printed(&["a", "c"]).tracks[BOARD].print, "판의 지문은 그대로다");
    assert!(c.added.is_empty() && c.removed.is_empty() && c.uids_gone.is_empty() && c.uids_new.is_empty());
    assert!(c.globals, "자료집의 판이 바뀐다");
    // 같은 배치면 아무것도 다시 쓰지 않는다.
    let c = choose(&db, &printed(&["a", "c"]), &Covers::All).unwrap();
    assert!(c.rewrite.is_empty() && c.added.is_empty() && c.removed.is_empty() && !c.globals, "{c:?}");
    drop(db);
    // 지문 표가 없는 옛 저장소(이 계획 전에 지은 것) — 모든 트랙을 '지문 없음 → 다시 씀'으로 본다(옛 DLC의 약속 2).
    let old = common::scratch("pr-old");
    std::fs::copy(&path, &old).unwrap();
    Connection::open(&old).unwrap().execute_batch("DROP TABLE track_prints").unwrap();
    let db = open(&old);
    let c = choose(&db, &printed(&["a", "c"]), &Covers::All).unwrap();
    assert_eq!(c.rewrite, keys(&["ta", "tc", BOARD]));
    assert!(c.added.is_empty() && c.removed.is_empty() && c.globals);
    let c = choose(&db, &printed(&["a", "c"]), &Covers::Tracks(keys(&["tc"]))).unwrap();
    assert_eq!(c.rewrite, keys(&["tc"]));
    assert!(dependents(&db, &keys(&["a/ta-2"])).unwrap().is_empty(), "표가 없으면 저장된 가리킴도 없다");
}

#[test]
fn 판_변형만_바뀌면_가려진_트랙은_다시_쓰지_않는다() {
    let path = full(&["a", "c"], "pr-board-only");
    let db = open(&path);
    // 판의 이름 · 가리는 것을 바꾼 배치 — 판 트랙의 지문만 다르다.
    let mut p = plan(&["a", "c"]);
    p["boards"]["variants"][0]["name"] = json!("가 다시 모아 보기");
    p["boards"]["variants"][0]["hides"] = json!([{"kind":3,"at":BOARD_CELL}]);
    let new = prints(&p).unwrap();
    assert_eq!(new.tracks["ta"], printed(&["a", "c"]).tracks["ta"]);
    let c = choose(&db, &new, &Covers::All).unwrap();
    assert_eq!(c.rewrite, keys(&[BOARD]), "판만 바뀌면 원래 트랙(ta)은 들지 않는다");
    assert!(c.added.is_empty() && c.removed.is_empty() && !c.globals);
    // 판이 다른 트랙(tc)의 것까지 가리게 되면 tc를 가리는 주인이 생길 뿐 — tc를 다시 쓰지 않는다.
    let tc_item = p["items"].as_array().unwrap().iter().position(|it| it["section"] == 60).unwrap();
    p["boards"]["variants"][0]["hides"] = json!([{"kind":3,"at":BOARD_CELL},{"kind":4,"at":tc_item}]);
    let new = prints(&p).unwrap();
    assert_eq!(new.tracks[BOARD].hides, keys(&["ta", "tc"]));
    assert_eq!(choose(&db, &new, &Covers::All).unwrap().rewrite, keys(&[BOARD]));
}

#[test]
fn 조합_대조는_다른_dlc를_조용히_지우지_않는다() {
    let path = full(&["a", "b", "c"], "pr-combo");
    let db = open(&path);
    let p = plan(&["a", "c"]);
    assert_eq!(check_combination(&db, &p, &[], &Covers::All).unwrap_err().to_string(),
        "지금 얹은 DLC «나 기록집»이 이 배치에 없습니다 — 메이커에서 그 DLC도 함께 불러 내보내 주세요");
    check_combination(&db, &p, &["b".to_string()], &Covers::All).unwrap();
    check_combination(&db, &p, &[], &Covers::Tracks(keys(&["tc"]))).unwrap();
    check_combination(&db, &plan(&["a", "b", "c"]), &[], &Covers::All).unwrap();
    // 판이 바뀐 자료집은 조합으로는 맞다(판 · 원본의 짝은 부르는 쪽이 본다 — 새 판의 원본을 받아 바꿔 넣는다).
    check_combination(&db, &plan(&["a@2", "b", "c"]), &[], &Covers::All).unwrap();
    // 기본팩이 다르면 거절.
    let mut other = plan(&["a", "b", "c"]);
    other["packs"][0]["id"] = json!("z");
    other["packs"][0]["name"] = json!("다른 기록집");
    assert_eq!(check_combination(&db, &other, &[], &Covers::All).unwrap_err().to_string(),
        "기본팩이 다릅니다(저장소 «가 기록집» · 배치 «다른 기록집») — 같은 기본팩으로 내보낸 배치만 받습니다");
    // 빼라는 것이 배치에 있거나 · 저장소에 없거나 · 덮는 트랙만 줄 때는 거절(말이 어긋남).
    assert!(check_combination(&db, &p, &["c".to_string()], &Covers::All).is_err());
    assert!(check_combination(&db, &p, &["b".to_string(), "z".to_string()], &Covers::All).is_err());
    assert!(check_combination(&db, &p, &["b".to_string()], &Covers::Tracks(keys(&["tc"]))).is_err());
}

#[test]
fn 하위_배치는_고른_트랙만_제_순번으로() {
    let whole = plan(&["a", "b", "c"]);
    let sub = sub_plan(&whole, &keys(&["tc"])).unwrap();
    // 온 판 조각 · 항목 기록은 통째로.
    for key in ["name", "packs", "categories", "epochs", "spheres", "sphereLines", "entities"] {
        assert_eq!(sub[key], whole[key], "{key}");
    }
    assert_eq!(sub["boards"]["entities"], whole["boards"]["entities"]);
    assert_eq!(sub["tracks"].as_array().unwrap().len(), 1);
    assert_eq!(sub["tracks"][0]["key"], "tc");
    assert!(sub["boards"]["tracks"].as_array().unwrap().is_empty());
    let uids = |list: &str| sub[list].as_array().unwrap().iter().map(|v| v["uid"].as_str().unwrap().to_owned()).collect::<Vec<_>>();
    assert_eq!(uids("periods"), vec!["c/tc-1", "c/tc-2"]);
    assert_eq!(uids("events"), vec!["c/e0", "c/e1", "c/e2", "c/e3", "c/e4"]);
    for list in ["periods", "events", "items", "rowLabels", "variants"] {
        assert!(sub[list].as_array().unwrap().iter().all(|v| v["track"] == 0), "{list}: S만의 순번");
    }
    assert_eq!(sub["axis"].as_array().unwrap().iter().map(|a| a["track"].as_i64().unwrap()).collect::<Vec<_>>(), vec![-1, 0], "공통 날짜 칸 + tc의 연호");
    // 띠 번호 칸은 0 + bandUids(판정 R14).
    let tab = sub["items"].as_array().unwrap().iter().find(|it| it["section"] == 47).unwrap();
    assert_eq!((tab["d"].clone(), tab["bandUids"].clone()), (json!(0), json!({"d":"a/ta-2"})));
    let union = sub["items"].as_array().unwrap().iter().find(|it| it["section"] == 49).unwrap();
    assert_eq!((union["b"].clone(), union["bandUids"].clone()), (json!(0), json!({"b":"b/ta-late"})));
    // S 밖 트랙의 줄을 가리키는 것은 `outer`로 — 트랙은 열쇠 글로.
    let scope = &sub["variants"][0];
    assert_eq!(scope["moves"], json!([]));
    assert_eq!(scope["outer"]["moves"], json!([{"kind":1,"ref":"c/tc-1","track":"ta","row":3,"at":0}]));
    assert_eq!(scope["outer"]["groups"][0]["track"], "ta");
    assert_eq!(scope["rows"][0]["track"], 0);

    // 지은 저장소의 트랙은 tc 하나 · 줄 순번이 0부터.
    let path = common::scratch("pr-sub");
    import_layout_value(&sub, &packs_of(&["a", "b", "c"]), &path).unwrap();
    let db = open(&path);
    let tracks: Vec<(String, i64)> = db.prepare("SELECT key,ord FROM tracks").unwrap().query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    assert_eq!(tracks, vec![("tc".to_string(), 0)]);
    let rows: Vec<(i64, i64)> = db.prepare("SELECT id,ord FROM rows ORDER BY id").unwrap().query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect();
    assert_eq!(rows, vec![(0, 0), (1, 1)]);

    // 가리기(`hides[].at`)는 하위 배치의 칸 · 항목 자리로 다시 매긴다 — c의 것이 앞에 끼어 밀린 자리가 제자리로 돌아온다.
    let shuffled = c_first(&plan(&["a", "c"]));
    let host = |p: &Value| p["variants"].as_array().unwrap().iter().find(|v| v["key"] == "host:a/ta-host").unwrap()["hides"].clone();
    assert_eq!(host(&shuffled), json!([{"kind":3,"at":HIDDEN_CELL + 1},{"kind":4,"at":HIDDEN_ITEM + 4}]));
    let only_a = sub_plan(&shuffled, &keys(&["ta"])).unwrap();
    assert_eq!(host(&only_a), json!([{"kind":3,"at":HIDDEN_CELL},{"kind":4,"at":HIDDEN_ITEM}]));
    assert_eq!(only_a["cells"][HIDDEN_CELL as usize], plan(&["a"])["cells"][HIDDEN_CELL as usize]);
    // 없는 트랙을 고르면 거절.
    assert!(sub_plan(&whole, &keys(&["tz"])).is_err());
}

#[test]
fn 하위_배치는_s_밖_변형과_가림을_내용으로_싣는다() {
    let whole = plan(&["a", "b", "c"]);
    // {ta}: 판 변형(S 밖)의 열쇠를 단 ta의 변형 판 칸은 그대로 두고, 그 열쇠를 `outer.variants`에(R16 가 — 5c가 열쇠로 번호를 찾음).
    let only_a = sub_plan(&whole, &keys(&["ta"])).unwrap();
    assert_eq!(only_a["outer"], json!({"variants":["view:a1"]}));
    assert_eq!(only_a["boards"]["cells"].as_array().unwrap().len(), 1, "판 변형 열쇠를 단 ta의 칸은 남는다");
    assert_eq!(only_a["boards"]["cells"][0]["variant"], "view:a1");
    assert!(only_a["boards"]["variants"].as_array().unwrap().is_empty());
    // {판}: 판 변형이 가리는 ta의 칸 · 관계선(S 밖)은 `outer.hides`에 **내용**으로(R16 다 — 5c가 저장소에서 내용으로 번호를 찾음).
    let only_board = sub_plan(&whole, &keys(&[BOARD])).unwrap();
    assert!(only_board.get("outer").is_none(), "판 트랙의 원소는 제 변형 열쇠만 단다");
    let view = &only_board["boards"]["variants"][0];
    assert_eq!(view["track"], 0);
    assert_eq!(view["hides"], json!([]));
    // 꼴(판정 R19): 대상은 기본 판(`variant` "") · 칸은 기간 끝 · 이름까지 · 항목은 대상 트랙 열쇠 · 트랙 안 줄 · 색 · lod까지.
    assert_eq!(view["outer"]["hides"], json!([
        {"kind":3,"variant":"","period":"a/ta-1","cellKind":1,"lane":0,"start":yr(1200),"end":yr(1400),"name":"둘째 임금"},
        {"kind":4,"variant":"","track":"ta","row":0,"row2":2,"section":21,"ref":"a/ta-1","start":yr(1300),"end":yr(1400),
            "name":"가 첫 나라 → 가 둘째 나라","color":0x8a8f96,"lod":14,"a":16,"b":"a/ta-2","c":0,"d":0,"text2":"a/ta-2"}
    ]));
    // 판 줄의 after −2(ta의 줄)는 S 밖 트랙의 줄이라 outer.rows로 — ta는 열쇠 글, 판은 새 순번.
    assert_eq!(view["outer"]["rows"].as_array().unwrap().iter().map(|r| (r["track"].clone(), r["toTrack"].clone())).collect::<Vec<_>>(),
        vec![(json!("ta"), json!(0)), (json!("ta"), json!(0))]);
    assert_eq!(view["rows"].as_array().unwrap().len(), 2);
    // S 안 원소를 가리면 지금처럼 하위 배치의 자리로: 판과 ta를 함께 고르면 outer.hides가 없다.
    let both = sub_plan(&whole, &keys(&["ta", BOARD])).unwrap();
    let view = &both["boards"]["variants"][0];
    assert_eq!(view["hides"], json!([{"kind":3,"at":BOARD_CELL},{"kind":4,"at":BOARD_ITEM}]));
    assert!(view["outer"].get("hides").is_none() || view["outer"]["hides"] == json!([]));
    assert!(both.get("outer").is_none());
}

#[test]
fn 남의_트랙을_가리는_변형도_지문에_담고_가리는_트랙을_적는다() {
    // 판(boards.mjs 꼴)이 ta의 칸 · 관계선을 가리는 장면 — 모든 조합에서 지문 · 고르기 · 하위 배치가 돈다(R16).
    let sets: [&[&str]; 7] = [&["a"], &["a", "b"], &["a", "c"], &["a", "b", "c"], &["a", "c", "b"], &["a@2", "c"], &["a@2", "b", "c"]];
    let path = full(&["a", "b", "c"], "pr-hides-all");
    let db = open(&path);
    for set in sets {
        let p = prints(&plan(set)).unwrap();
        choose(&db, &p, &Covers::All).unwrap();
        for key in &p.order {
            sub_plan(&plan(set), &BTreeSet::from([key.clone()])).unwrap();
        }
    }
    drop(db);
    // tc의 변형이 ta의 칸(자리 0 — a/ta-1의 첫 임금)을 가리면: tc의 조각에 가림 내용이 들고(지문이 바뀜), 가리는 대상 트랙(ta)이 hides에 든다.
    let mut p = plan(&["a", "c"]);
    let scope = p["variants"].as_array().unwrap().iter().position(|v| v["key"] == "scope:c/sc-1").unwrap();
    p["variants"][scope]["hides"] = json!([{"kind":3,"at":0}]);
    let got = prints(&p).unwrap();
    assert_eq!(got.tracks["tc"].hides, keys(&["ta"]));
    assert_ne!(got.tracks["tc"].print, printed(&["a", "c"]).tracks["tc"].print);
    assert_eq!(got.tracks["ta"], printed(&["a", "c"]).tracks["ta"], "가려지는 쪽의 지문은 그대로");
    // 하위 배치 {tc}: S 밖 칸을 가리는 것은 outer.hides에 내용으로.
    let sub = sub_plan(&p, &keys(&["tc"])).unwrap();
    assert_eq!(sub["variants"][0]["outer"]["hides"],
        json!([{"kind":3,"variant":"","period":"a/ta-1","cellKind":1,"lane":0,"start":yr(1000),"end":yr(1200) - 1,"name":"첫 임금"}]));
    // 지은 저장소에는 지문이 적힌다 · ta가 바뀌면(a@2) tc도 다시 쓴다(저장된 hides로).
    let built = common::scratch("pr-hides");
    import_layout_value(&p, &packs_of(&["a", "c"]), &built).unwrap();
    let db = open(&built);
    let n: i64 = db.query_row("SELECT count(*) FROM track_prints", [], |r| r.get(0)).unwrap();
    assert_eq!(n, 4, "* · ta · tc · 판");
    let mut q = plan(&["a@2", "c"]);
    q["variants"][scope]["hides"] = json!([{"kind":3,"at":0}]);
    assert_eq!(choose(&db, &prints(&q).unwrap(), &Covers::All).unwrap().rewrite, keys(&["ta", "tc", BOARD]));
}

/// 바깥 가림 하나의 내용과 맞는 저장소 원소의 수 — 내용에 실린 칸만으로 SQL로 훑는다(과제 5c가 번호를 찾는 길의 흉내).
fn stored_matches(db: &Connection, hide: &Value) -> i64 {
    use rusqlite::types::Value as Sql;
    let num = |v: &Value| Sql::Integer(v.as_i64().unwrap());
    let text = |v: &Value| Sql::Text(v.as_str().unwrap().to_owned());
    let cell = hide["kind"] == 3;
    let at = if cell { "c" } else { "i" };
    let (mut conds, mut args): (Vec<String>, Vec<Sql>) = (Vec::new(), Vec::new());
    for (key, v) in hide.as_object().unwrap() {
        let (cond, arg) = match key.as_str() {
            "kind" | "lod" => continue, // 저장소에는 lod 열이 없다(item_bounds의 단계로 셈해 둠) — 맞추지 않는다
            "variant" => (format!("{at}.variant=COALESCE((SELECT id FROM variants WHERE key=?),0)"), text(v)),
            "period" => ("c.period=(SELECT id FROM periods WHERE uid=?)".to_owned(), text(v)),
            "cellKind" => ("c.kind=?".to_owned(), num(v)),
            "track" => ("(SELECT t.key FROM rows r JOIN tracks t ON t.id=r.track WHERE r.id=i.row)=?".to_owned(),
                Sql::Text(v.as_str().unwrap().trim_start_matches("board:").to_owned())),
            "row" | "row2" => (format!("(SELECT ord FROM rows WHERE id=i.{key})=?"), num(v)),
            "ref" => {
                // 띠 uid면 ref_kind 1, 사건 uid면 2 — 같은 글을 두 번 쓴다.
                conds.push("((i.ref_kind=1 AND i.ref=(SELECT id FROM periods WHERE uid=?)) OR (i.ref_kind=2 AND i.ref=(SELECT id FROM events WHERE uid=?)))".to_owned());
                args.extend([text(v), text(v)]);
                continue;
            }
            "name" | "text2" => (format!("{at}.{key}=?"), text(v)),
            "a" | "b" | "c" | "d" if v.is_string() => (format!("i.{key}=(SELECT id FROM periods WHERE uid=?)"), text(v)),
            _ => (format!("{at}.{key}=?"), num(v)),
        };
        conds.push(cond);
        args.push(arg);
    }
    let sql = format!("SELECT count(*) FROM {} WHERE {}", if cell { "cells c" } else { "items i" }, conds.join(" AND "));
    db.query_row(&sql, rusqlite::params_from_iter(args), |r| r.get(0)).unwrap()
}

#[test]
fn 바깥_가림의_내용은_저장소의_원소_하나만_가리킨다() {
    // 판 변형이 가리는 ta의 관계선은 판 트랙의 관계선과 구역 · ref · 기간 · 이름 · a ~ d · text2가 같고, 가리는 칸은 모양 · 색만 바뀐
    // 변형 판 칸과 띠 · 종류 · 단 · 시작이 같다 — 내용 열쇠가 그 둘을 갈라 저장소의 원소 하나만 집어야 한다(판정 R19).
    let set = ["a", "b", "c"];
    let path = full(&set, "pr-outer-one");
    let db = open(&path);
    let sub = sub_plan(&plan(&set), &keys(&[BOARD])).unwrap();
    let hides = sub["boards"]["variants"][0]["outer"]["hides"].as_array().unwrap().clone();
    assert_eq!(hides.len(), 2);
    for hide in &hides {
        assert_eq!(stored_matches(&db, hide), 1, "{hide}");
        assert_eq!(hide["variant"], "", "가려지는 것은 기본 판");
    }
}

/// 변형의 빈 목록 칸을 지운다(하위 배치는 원래 없던 칸을 빈 목록으로 남길 수 있다 — 넣기 · 지문은 빈 목록과 없음을 같게 본다).
fn without_empty_lists(mut v: Value) -> Value {
    fn strip(list: &mut Value) {
        for x in list.as_array_mut().into_iter().flatten() {
            if let Some(o) = x.as_object_mut() {
                o.retain(|k, v| !(["rows", "moves", "groups", "hides"].contains(&k.as_str()) && v.as_array().is_some_and(Vec::is_empty)));
            }
        }
    }
    strip(&mut v["variants"]);
    if v["boards"].is_object() {
        strip(&mut v["boards"]["variants"]);
    }
    v
}

#[test]
fn 하위_배치의_지문은_통째_배치의_그_트랙_지문과_같다() {
    // P4 과제 9: 닿는 트랙 S의 하위 배치(P3 과제 16 `Scope::Tracks(S)`의 출력)를 그대로 apply(`Covers::Part`)에 넣는다 — 하위 배치에서 셈한 지문이
    // 통째 배치의 같은 트랙 지문(조각 · 가리키는 uid · 줄 대상 · 제 uid · 가리는 대상)과 같고 온 판 지문도 같아야, 다음 넣기가 바뀌지 않은 트랙을
    // 다시 쓰지 않는다(띠 번호 칸 `bandUids` · 변형의 S 밖 줄 · 이사 · 묶음 · 가림을 원래 자리로). 하위 배치를 다시 줄여도(S′ ⊆ S) 처음 배치를 S′로 줄인 것과
    // 같다("insert"가 다시 쓸 트랙만 줄여 넣는다). 장면 조합 전부 + 정답지 자료(있으면 — 판 · 변형이 많은 등불 · 동아시아 + 시험 DLC · 합성).
    let mut cases: Vec<(String, Value)> = [&["a"][..], &["a", "b"], &["a", "c"], &["a", "b", "c"], &["a", "c", "b"], &["a@2", "c"], &["a@2", "b", "c"]]
        .iter().map(|s| (format!("{s:?}"), plan(s))).collect();
    for name in ["lantern", "east-asia+nest", "east-asia+move", "synth+patch", "east-asia+ktl"] {
        // 선택 자료(KTL)가 이 PC에 없으면 건너뜀 · 정답지가 없거나 낡았으면 멈춤(판정 R58 ⑤ Minor — common::oracle::oracle_named).
        if let Some(v) = common::oracle::oracle_named(name, "upto-lens.json") { cases.push((name.to_owned(), v)); }
    }
    let mut x: u64 = 0x5ab_9_1a4;
    let mut pick = |n: usize| -> usize {
        x = x.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
        ((x >> 33) % n as u64) as usize
    };
    let mut checked = 0;
    for (name, p) in &cases {
        let whole = prints(p).unwrap();
        let order = whole.order.clone();
        for trial in 0..6 {
            // S: 하나 · 둘 · 셋(무작위) — 첫 판은 모두.
            let s: BTreeSet<String> = if trial == 0 { order.iter().cloned().collect() } else {
                (0..1 + pick(3.min(order.len()))).map(|_| order[pick(order.len())].clone()).collect()
            };
            let sub = sub_plan(p, &s).unwrap();
            assert_eq!(sub["allTracks"], json!(order), "{name}: 조합의 트랙 차례");
            let got = prints(&sub).unwrap();
            assert_eq!(got.globals, whole.globals, "{name} S={s:?}: 온 판 지문");
            assert_eq!(got.order, order.iter().filter(|k| s.contains(*k)).cloned().collect::<Vec<_>>(), "{name} S={s:?}: 트랙 차례");
            for k in &s {
                assert_eq!(got.tracks[k], whole.tracks[k], "{name} S={s:?}: 트랙 {k}의 지문");
            }
            // S′ ⊆ S
            let s2: BTreeSet<String> = s.iter().filter(|_| pick(2) == 0).cloned().collect();
            let again = sub_plan(&sub, &s2).unwrap();
            assert_eq!(without_empty_lists(again.clone()), without_empty_lists(sub_plan(p, &s2).unwrap()), "{name} S={s:?} → S′={s2:?}");
            let twice = prints(&again).unwrap();
            for k in &s2 {
                assert_eq!(twice.tracks[k], whole.tracks[k], "{name} S′={s2:?}: 트랙 {k}의 지문(두 번 줄임)");
            }
            checked += 1;
        }
    }
    eprintln!("하위 배치 지문: 배치 {} · 판 {checked}", cases.len());
}

// ---------------------------------------------------------------- 스키마 4(리메이크 3단계 · 계약 1-1)

#[test]
fn 문화권_단위_줄만_다르면_트랙_지문은_그대로이고_온_판_지문만_바뀐다() {
    // 문화권 단위 줄(`sphereLines`)은 트랙이 아니라 온 판('*')의 조각이다 — 그것만 바뀐 배치는 다시 쓸 트랙이 없고 온 판만 고쳐 적는다.
    let base = plan(&["a", "b", "c"]);
    let before = prints(&base).unwrap();
    let changed = |edit: &dyn Fn(&mut Vec<Value>)| -> Prints {
        let mut p = base.clone();
        edit(p["sphereLines"].as_array_mut().unwrap());
        prints(&p).unwrap()
    };
    for (what, after) in [
        ("이름", changed(&|l| l[0]["name"] = json!("가람 큰 사람"))),
        ("줄 하나 뺌", changed(&|l| { l.pop(); })),
        ("차례", changed(&|l| l.swap(0, 1))),
        ("data", changed(&|l| l[0]["data"] = json!("[]"))),
    ] {
        assert_eq!(after.tracks, before.tracks, "{what}: 트랙 지문은 그대로");
        assert_eq!(after.order, before.order, "{what}");
        assert_ne!(after.globals, before.globals, "{what}: 온 판 지문이 바뀐다");
    }
    // 자료집 순번은 그 값이 들어갈 자료집의 글자 id로 적는다 — b의 사람 띠를 순번 대신 uid 앞머리(`b/`)로 가리켜도 같은 지문 · 다른 자료집(c)을 가리키면 다르다.
    let b_line = |l: &mut Vec<Value>| -> usize { l.iter().position(|x| x["uid"] == "b/fig-2").unwrap() };
    let by_uid = changed(&|l| { let at = b_line(l); l[at].as_object_mut().unwrap().remove("pack"); });
    assert_eq!(by_uid.globals, before.globals, "순번 대신 uid 앞머리로 가리켜도 같은 자료집");
    let to_c = changed(&|l| { let at = b_line(l); l[at]["pack"] = json!(2); });
    assert_ne!(to_c.globals, before.globals, "다른 자료집");
    // 저장소에 견주면: 온 판만 다르고 다시 쓸 트랙은 없다.
    let path = full(&["a", "b", "c"], "pr-lines");
    let db = open(&path);
    let c = choose(&db, &changed(&|l| l[0]["name"] = json!("가람 큰 사람")), &Covers::All).unwrap();
    assert!(c.globals && c.rewrite.is_empty() && c.added.is_empty() && c.removed.is_empty(), "{c:?}");
    let c = choose(&db, &before, &Covers::All).unwrap();
    assert!(!c.globals && c.rewrite.is_empty(), "같은 배치: {c:?}");
}

#[test]
fn 조합마다_문화권_단위_줄이_달라_온_판_지문이_갈린다() {
    // 장면(`plans.rs`)의 줄은 조합마다 다르다 — 그래야 넣고 빼기의 같음 검사가 줄을 다시 셈하는 길을 지난다.
    let lines = |set: &[&str]| plan(set)["sphereLines"].as_array().unwrap().iter().map(|l| (l["kind"].as_i64().unwrap(), l["uid"].as_str().unwrap().to_owned()))
        .collect::<Vec<_>>();
    assert_eq!(lines(&["a"]), vec![(1, "a/fig-1".to_owned()), (2, "a/ep-east".to_owned())]);
    assert_eq!(lines(&["a", "b"]), vec![(1, "a/fig-1".to_owned()), (1, "b/fig-2".to_owned()), (2, "a/ep-east".to_owned())]);
    assert_eq!(lines(&["a", "c"]), vec![(1, "a/fig-1".to_owned()), (2, "a/ep-east".to_owned()), (3, String::new())]);
    assert_eq!(plan(&["a", "b", "c"])["sphereLines"].as_array().unwrap().len(), 4);
    // 띠의 form은 조합과 상관없이 같다(트랙 지문이 조합 따라 갈리지 않게).
    for set in [&["a"][..], &["a", "b", "c"]] {
        let p = plan(set);
        let ta1 = p["periods"].as_array().unwrap().iter().find(|x| x["uid"] == "a/ta-1").unwrap();
        assert_eq!(ta1["form"], json!(1 | 1 << 10 | 3 << 13), "{set:?}");
    }
}

#[test]
fn 띠의_form만_바꾸면_그_트랙만_다시_쓴다() {
    // 스키마 4의 띠 `form`은 띠 원소 그대로 트랙 조각에 든다 — 그 띠의 트랙만 지문이 바뀌고 온 판은 그대로다.
    let base = plan(&["a", "c"]);
    let before = prints(&base).unwrap();
    let mut p = base.clone();
    let at = p["periods"].as_array().unwrap().iter().position(|x| x["uid"] == "c/tc-2").unwrap();
    p["periods"][at]["form"] = json!(5); // 도시 → 정부
    let after = prints(&p).unwrap();
    assert_eq!(after.globals, before.globals, "온 판은 그대로");
    for key in &before.order {
        if key == "tc" {
            assert_ne!(after.tracks[key].print, before.tracks[key].print, "tc의 지문이 바뀐다");
        } else {
            assert_eq!(after.tracks[key], before.tracks[key], "{key}");
        }
    }
    // form이 없던 띠에 생겨도(0 → 값) 그 트랙만.
    let mut q = base.clone();
    let at = q["periods"].as_array().unwrap().iter().position(|x| x["uid"] == "a/ta-host").unwrap();
    q["periods"][at]["form"] = json!(1);
    let host = prints(&q).unwrap();
    assert_ne!(host.tracks["ta"].print, before.tracks["ta"].print);
    assert_eq!(host.tracks["tc"], before.tracks["tc"]);
    let path = full(&["a", "c"], "pr-form");
    let db = open(&path);
    let c = choose(&db, &after, &Covers::All).unwrap();
    assert_eq!(c.rewrite, keys(&["tc"]));
    assert!(!c.globals && c.added.is_empty() && c.removed.is_empty(), "{c:?}");
}

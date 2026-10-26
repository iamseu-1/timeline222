//! 선반 변형(kind 6 · `shelf:<그릇 uid>` — 리메이크 4단계 · 감독 결정 2026-10-25 '선반 = 엔진 변형 길')의 **뜻**을 Rust 배치(`lay::export`)로 바로 본다.
//! 정답지(git 밖)가 없어도 돈다 — 시험 자료 셋(`prototype/fixtures/oracle` · 저장소 안)을 그대로 내보내 기대와 견준다. 그래서 `cargo test` 전부에 든다.
//!
//! 까닭(선반 갈래 검토 고침): 선반의 뜻은 손으로 돌리는 `prototype/scripts/remake4-shelf-check.mjs`(①)만 보고 있었고, 자동으로 남는 것은 골든 해시와
//! Node = Rust 견줌뿐이었다 — 다른 갈래와 판을 합치며 골든을 '찍힌 대로' 다시 찍으면, JS와 Rust가 함께 바뀐 선반 줄은 아무 검사도 잡지 못한다.
//! 그 ①의 기대(사슬 자료 3줄 · 숨는 넷 · 꼬리표 차례 · 숨은 구성원의 사건이 숨음 · 그릇 밖 새 줄 없음 · 바탕 문화가 승계국을 따라감)를 여기로 옮겼다.
//! 출력의 꼴은 계약 `docs/계약-아카이브-3단계.md` 2-4절(변형 · 숨는 띠 · 빠지는 줄) · 6-10절(구역 59).
mod common;
use archive_engine::lay;
use common::oracle::{fixtures, inputs, seam_opts};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

/// 띠 look의 바탕 문화 비트(내보내기 `bands.mjs`의 `L.under`) — 바탕 문화 조각은 구성원이 아니다.
const UNDER: u64 = 1 << 14;
/// 선반이 제 줄에 남기는 구성원 수(`G_SEOGO.shelfKeep`) — 숨긴 구성원 꼬리표의 `a`는 숨은 첫째가 이 값.
const SHELF_KEEP: u64 = 5;

fn lantern(id: &str) -> String { format!("lantern-chronicle/{id}") }

/// 자료 하나를 내보낸다(저장소 안의 시험 자료라 없으면 멈춘다).
fn export(name: &str) -> Value {
    let f = fixtures().into_iter().find(|f| f.name == name).unwrap_or_else(|| panic!("list.json에 자료 {name}이(가) 없습니다"));
    lay::export(&inputs(&f), &seam_opts(None)).unwrap_or_else(|e| panic!("{name}: 내보내기 — {e}"))
}

fn arr(v: &Value) -> &[Value] { v.as_array().map(Vec::as_slice).unwrap_or(&[]) }
fn s(v: &Value) -> &str { v.as_str().unwrap_or("") }
fn i(v: &Value) -> i64 { v.as_i64().unwrap_or(i64::MIN) }

/// 선반 변형 하나를 읽은 것.
struct Shelf {
    track: i64,
    /// 숨은 구성원(이사 kind 1 · 줄 −1 · 바탕 문화 조각은 뺌).
    hidden: BTreeSet<String>,
    /// 띠 → 그 변형에서의 줄(이사가 없으면 기본 줄) — 기본 띠만.
    band_now: BTreeMap<String, i64>,
    /// 그릇 묶음(kind 2)의 줄 차례대로, 그 줄에 놓인 구성원 띠(바탕 문화 조각은 뺌 · 변형에만 있는 띠 포함).
    rows: Vec<Vec<String>>,
    /// 빠지는 줄(after −2).
    gone: BTreeSet<i64>,
    /// 이사 −1인 사건.
    events_hidden: BTreeSet<String>,
    /// 기본 판 사건 가운데 숨은 구성원에 든 것.
    events_of_hidden: BTreeSet<String>,
    /// 그 변형의 새 줄 가운데 그릇 묶음 밖의 것(트랙 · 줄).
    outside: Vec<(i64, i64)>,
    /// 그 변형의 공통 줄('그 밖') 이름 수.
    common_labels: usize,
    /// 변형에만 있는 바탕 문화 조각(uid → 줄).
    under_fresh: Vec<(String, i64)>,
    /// 숨긴 구성원 꼬리표(구역 59)의 띠 — `a` 차례.
    tags: Vec<String>,
    /// 같은 그릇의 scope 변형이 쌓는 그릇 묶음의 줄 수.
    scope_rows: usize,
}

fn read_shelf(out: &Value, key: &str) -> Shelf {
    let variants = arr(&out["variants"]);
    let shelves: Vec<&Value> = variants.iter().filter(|v| v["kind"] == 6).collect();
    assert_eq!(shelves.len(), 1, "선반 변형은 하나: {:?}", shelves.iter().map(|v| s(&v["key"])).collect::<Vec<_>>());
    let v = shelves[0];
    assert_eq!(s(&v["key"]), key);
    let uid = key.strip_prefix("shelf:").expect("선반 열쇠");
    assert_eq!(s(&v["uid"]), uid, "variants.uid = 그 그릇");
    let at = |k: &str| variants.iter().position(|x| s(&x["key"]) == k);
    let scope = at(&format!("scope:{uid}")).expect("같은 그릇의 scope 변형");
    let me = at(key).unwrap();
    assert!(me > scope, "선반은 variants 모듈 목록의 뒤 — 같은 그릇의 scope 변형보다 뒤");
    // 렌즈 변형(kind 4)은 뒤의 lens 모듈이 붙이므로 선반보다 뒤(계획 덧글 · variants.mjs 머리 — '앞 변형 번호 그대로'는 variants 모듈 안에서만)
    assert!(variants.iter().skip(me + 1).all(|x| x["kind"] == 4), "선반 뒤에는 렌즈 변형만");
    let track = i(&v["track"]);
    let periods = arr(&out["periods"]);
    let under: BTreeSet<&str> = periods.iter().filter(|p| p["look"].as_u64().unwrap_or(0) & UNDER != 0).map(|p| s(&p["uid"])).collect();
    let moves = arr(&v["moves"]);
    let band_moves: BTreeMap<&str, i64> = moves.iter().filter(|m| m["kind"] == 1).map(|m| (s(&m["ref"]), i(&m["row"]))).collect();
    let hidden: BTreeSet<String> = band_moves.iter().filter(|(r, row)| **row == -1 && !under.contains(*r)).map(|(r, _)| r.to_string()).collect();
    let mut band_now = BTreeMap::new();
    for p in periods.iter().filter(|p| p.get("variant").is_none() && i(&p["track"]) == track) {
        let u = s(&p["uid"]);
        band_now.insert(u.to_string(), band_moves.get(u).copied().unwrap_or(i(&p["row"])));
    }
    let groups = arr(&v["groups"]);
    let group_rows: Vec<i64> = groups.iter().find(|g| g["kind"] == 2).map(|g| arr(&g["rows"]).iter().map(i).collect()).unwrap_or_default();
    let in_group: BTreeSet<i64> = groups.iter().flat_map(|g| arr(&g["rows"]).iter().map(i)).collect();
    let rows = group_rows.iter().map(|r| {
        periods.iter().filter(|p| i(&p["track"]) == track && !under.contains(s(&p["uid"])))
            .filter(|p| match p.get("variant") {
                None => band_now.get(s(&p["uid"])) == Some(r),
                Some(k) => s(k) == key && i(&p["row"]) == *r,
            })
            .map(|p| s(&p["uid"]).to_string()).collect()
    }).collect();
    let gone = arr(&v["rows"]).iter().filter(|r| i(&r["after"]) == -2).map(|r| i(&r["row"])).collect();
    let events_hidden = moves.iter().filter(|m| m["kind"] == 2 && i(&m["row"]) == -1).map(|m| s(&m["ref"]).to_string()).collect();
    let events_of_hidden = arr(&out["events"]).iter()
        .filter(|e| e.get("variant").is_none() && i(&e["track"]) == track && hidden.contains(s(&e["band"])))
        .map(|e| s(&e["uid"]).to_string()).collect();
    let mut outside = Vec::new();
    for (t, tr) in arr(&out["tracks"]).iter().enumerate() {
        for (r, row) in arr(&tr["rows"]).iter().enumerate() {
            if row.get("variant").is_some_and(|k| s(k) == key) && (t as i64 != track || !in_group.contains(&(r as i64))) { outside.push((t as i64, r as i64)); }
        }
    }
    let common_labels = arr(&out["rowLabels"]).iter().filter(|l| l["kind"] == 1 && l.get("variant").is_some_and(|k| s(k) == key)).count();
    let under_fresh = periods.iter().filter(|p| p.get("variant").is_some_and(|k| s(k) == key) && p["look"].as_u64().unwrap_or(0) & UNDER != 0)
        .map(|p| (s(&p["uid"]).to_string(), i(&p["row"]))).collect();
    let mut tags: Vec<(u64, String)> = arr(&out["items"]).iter().filter(|it| it["section"] == 59 && it.get("variant").is_some_and(|k| s(k) == key))
        .map(|it| (it["a"].as_u64().unwrap_or(0), s(&it["ref"]).to_string())).collect();
    tags.sort();
    assert!(tags.iter().enumerate().all(|(n, (a, _))| *a == SHELF_KEEP + n as u64), "꼬리표의 a는 {SHELF_KEEP}부터 이어진 차례: {tags:?}");
    let scope_rows = arr(&variants[scope]["groups"]).iter().find(|g| g["kind"] == 2).map_or(0, |g| arr(&g["rows"]).len());
    Shelf { track, hidden, band_now, rows, gone, events_hidden, events_of_hidden, outside, common_labels, under_fresh, tags: tags.into_iter().map(|t| t.1).collect(), scope_rows }
}

/// 모든 선반에 같은 것: 숨은 구성원의 사건은 모두 숨고(이사 −1 — 공통 줄로 옮겨 가지 않음) · 새 줄은 그릇 묶음 안 · '그 밖' 줄 이름 없음 ·
/// 빠지는 줄에 이사 없이 남은 기본 띠 없음 · 꼬리표는 숨은 구성원마다 하나.
fn common_rules(name: &str, out: &Value, sh: &Shelf) {
    assert_eq!(sh.events_hidden, sh.events_of_hidden, "{name}: 이사 −1인 사건 = 숨은 구성원의 사건");
    assert!(sh.outside.is_empty(), "{name}: 그릇 묶음 밖의 새 줄 {:?}(숨은 구성원의 사건이 공통 줄로 옮겨 간 것)", sh.outside);
    assert_eq!(sh.common_labels, 0, "{name}: 그 변형의 '그 밖' 줄 이름");
    let left: Vec<&String> = sh.band_now.iter().filter(|(_, row)| sh.gone.contains(row)).map(|(u, _)| u).collect();
    assert!(left.is_empty(), "{name}: 빠지는 줄에 이사 없이 남은 기본 띠 {left:?}");
    assert_eq!(sh.tags.iter().cloned().collect::<BTreeSet<_>>(), sh.hidden, "{name}: 꼬리표 = 숨은 구성원");
    assert!(sh.track >= 0 && sh.track < arr(&out["tracks"]).len() as i64);
}

#[test]
fn 승계_사슬_그릇의_선반은_세_줄이고_숨은_넷의_사건과_바탕_문화도_따라_숨는다() {
    let _t = common::clock("lay_shelf 사슬");
    let out = export("lantern+shelf-chain");
    let sh = read_shelf(&out, "shelf:shelf-chain/shelf-chain");
    common_rules("lantern+shelf-chain", &out, &sh);
    let l = |ids: &[&str]| ids.iter().map(|x| lantern(x)).collect::<Vec<_>>();
    assert_eq!(sh.rows, vec![l(&["p-lantern", "p-revival", "p-republic"]), l(&["p-lower"]), l(&["p-upper"])], "선반 줄 셋(줄 채우기 — 승계 사슬은 한 줄)");
    assert_eq!(sh.hidden, l(&["p-prefecture", "p-union", "p-blackwater", "p-namgang"]).into_iter().collect());
    assert_eq!(sh.tags, l(&["p-union", "p-prefecture", "p-namgang", "p-blackwater"]), "꼬리표 차례(중요도가 없어 기간 길이 차례)");
    assert_eq!(sh.events_of_hidden.len(), 13, "숨은 넷의 사건(연합 왕국 8 · 의병 2 · 임시정부 2 · 총관부 1)");
    // 바탕 문화: 숨는 구성원 밑은 −1 · 다시 지은 줄로 간 구성원 밑은 그 줄. 두 구성원 밑의 문화는 첫 조각이 아랫물국 줄로 · 기본의 둘째 조각은 −1 ·
    // 변형의 둘째 조각(줄 번호가 이름에 들어 새 uid)은 새 띠로 윗물국 줄에.
    let now = |u: &str| sh.band_now.get(u).copied().unwrap_or_else(|| panic!("기본 띠 {u}가 없습니다"));
    let (upper, lower) = (now(&lantern("p-upper")), now(&lantern("p-lower")));
    assert_eq!(now("shelf-chain/c-blackwater-kiln"), -1);
    assert_eq!(now("shelf-chain/c-upper-mound"), upper);
    assert_eq!(now("shelf-chain/c-fork-reed"), lower);
    assert_eq!(now("shelf-chain/c-fork-reed#u3"), -1);
    assert!(sh.under_fresh.iter().any(|(u, r)| u.starts_with("shelf-chain/c-fork-reed#u") && *r == upper), "변형에만 있는 조각: {:?}", sh.under_fresh);
}

#[test]
fn 낱_사슬_그릇의_선반은_일곱_줄을_다섯으로_줄이고_숨은_둘의_사건을_숨긴다() {
    let _t = common::clock("lay_shelf 낱 사슬");
    let out = export("lantern+shelf-flat");
    let sh = read_shelf(&out, "shelf:shelf-flat/shelf-flat");
    common_rules("lantern+shelf-flat", &out, &sh);
    assert_eq!((sh.scope_rows, sh.rows.len()), (7, 5));
    assert_eq!(sh.hidden, [lantern("p-blackwater"), lantern("p-namgang")].into_iter().collect());
    assert_eq!(sh.events_of_hidden.len(), 4, "숨은 둘의 사건(의병 2 · 임시정부 2)");
}

#[test]
fn 연방_그릇의_선반은_열둘_가운데_다섯만_남긴다() {
    let _t = common::clock("lay_shelf 연방");
    let out = export("f4-federation-scope");
    let sh = read_shelf(&out, "shelf:f4-federation-scope/s-fed");
    common_rules("f4-federation-scope", &out, &sh);
    assert_eq!((sh.scope_rows, sh.rows.len()), (12, 5));
    assert_eq!(sh.hidden.len(), 7);
    let names: BTreeMap<&str, &str> = arr(&out["periods"]).iter().map(|p| (s(&p["uid"]), s(&p["name"]))).collect();
    let kept: Vec<&str> = sh.rows.iter().flatten().map(|u| names[u.as_str()]).collect();
    for prefix in ["쇠여울", "흰여울", "붉은바위", "범바위", "잿골"] {
        assert!(kept.iter().any(|n| n.starts_with(prefix)), "남는 다섯에 {prefix}: {kept:?}");
    }
    assert_eq!(kept.len(), 5);
}

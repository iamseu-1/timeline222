//! 한 벌 P3 과제 8-틀 — 내보내기 모듈 하나를 **따로** Node와 견주는 검사 도움(모듈마다의 `tests/lay_m_<모듈>.rs`가 부른다 — 갈래가 동시에 옮기며 제 모듈만 검사하려고).
//! 정답지(`node prototype/scripts/layout-oracle.mjs --seams=mods`): 모듈 k 뒤의 `pre-<k>.json`(늦은 차례 전 out) · `pre-<k>.shared.json`(모듈끼리 나눠 쓰는 값의 덤프) ·
//! 늦은 차례 하나 뒤의 `late-<모듈>.json`(tracks · docs · power · metro). Rust(`lay::export_one` · `export_late`)는 Node의 **앞** 출력을 심고 그 모듈 하나만 돌린다 —
//! 다른 모듈이 옮겨졌는지와 무관하게 견줄 수 있다. 견줌은 값(`same::diff` — 열쇠 차례 무시)과 **`json` 열쇠 글의 바이트**(`same::diff_json_text` — 고침 1회차) 둘 다.
//! 통째(앞자리 k개를 Rust로만)는 `tests/lay_out.rs`.
#![allow(dead_code)]
use super::oracle::{assert_same, assert_same_bytes, fixtures, inputs, oracle, oracle_exists, seam_opts, Fixture};
use archive_engine::lay::{self, module_index, MODULES};
use serde_json::Value;

fn index_of(name: &str) -> usize { module_index(name).unwrap_or_else(|| panic!("모르는 모듈: {name} — lay::MODULES에 없습니다")) }

/// 정답지 파일(머리 `$oracle`의 시각 · 시간대 · 원본 지문 검사 포함 — 없으면 뽑는 명령을 알리며 실패).
fn want(f: &Fixture, file: &str) -> Value { oracle(f, file) }

/// 정답지 파일이 있어야 한다(옮기지 않은 모듈 — 큰 JSON을 풀지 않고 있는지만).
fn must_exist(f: &Fixture, file: &str) {
    assert!(oracle_exists(f, file), "정답지 {}/{file} 이(가) 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs --only={} --seams=mods", f.name, f.name);
}

/// 모듈 `name`의 `contribute`: 자료마다 Node의 `pre-<앞 모듈>`(+ `.shared`)을 심고(첫 모듈은 빈 out) 그 모듈만 돌려 `pre-<name>`(+ `.shared`)과 값으로, 그리고 `json` 글은 바이트로 견준다(차이 0).
/// 아직 옮기지 않은 모듈(`PORTED = false`)이면 정답지 파일이 있는지만 보고(풀지 않고) 건너뛴다고 알린다 — 정답지 자료가 하나도 없으면 실패.
pub fn check_contribute(name: &str) {
    let k = index_of(name);
    let m = &MODULES[k];
    let o = seam_opts(Some(name));
    let mut n = 0;
    for f in fixtures() {
        n += 1;
        if !m.ported {
            must_exist(&f, &format!("pre-{name}.json"));
            must_exist(&f, &format!("pre-{name}.shared.json"));
            continue;
        }
        let want_out = want(&f, &format!("pre-{name}.json"));
        let want_shared = want(&f, &format!("pre-{name}.shared.json"));
        let (seed_out, seed_shared) = if k == 0 { (None, None) } else {
            let prev = MODULES[k - 1].name;
            (Some(want(&f, &format!("pre-{prev}.json"))), Some(want(&f, &format!("pre-{prev}.shared.json"))))
        };
        let (got, got_shared) = lay::export_one(&inputs(&f), &o, name, seed_out, seed_shared.as_ref()).unwrap_or_else(|e| panic!("자료 {} · 모듈 {name}: {e}", f.name));
        assert_same(&f, &format!("pre-{name}"), &got, &want_out);
        assert_same_bytes(&f, &format!("pre-{name}"), &got, &want_out);
        assert_same(&f, &format!("pre-{name}.shared"), &got_shared, &want_shared);
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다 — 자료 목록 · 정답지를 확인하세요");
    if m.ported { eprintln!("모듈 {name}({}/{}): 자료 {n}개 Node와 같음(값 · json 글 바이트) — 앞자리 출력을 심고 이 모듈만 돌림", k + 1, MODULES.len()); }
    else { eprintln!("모듈 {name}({}/{}): 아직 옮기지 않음 — 건너뜀(정답지 자료 {n}개 있음)", k + 1, MODULES.len()); }
}

/// 모듈 `name`의 늦은 차례(`contributeLate`): 자료마다 앞 늦은 모듈의 `late-<모듈>`(처음은 스물 모두의 `pre-lens`)과 `pre-lens.shared`를 심고 그 늦은 차례만 돌려 `late-<name>`과
/// 값으로, 그리고 `json` 글은 바이트로 견준다. 늦은 차례가 없는 모듈이면 실패. 아직 옮기지 않은 모듈이면 정답지 파일이 있는지만 보고 건너뛴다고 알린다.
pub fn check_late(name: &str) {
    let k = index_of(name);
    let m = &MODULES[k];
    assert!(m.late.is_some(), "모듈 {name}에는 늦은 차례(contributeLate)가 없습니다");
    let prev_late = MODULES[..k].iter().rev().find(|x| x.late.is_some()).map(|x| x.name);
    let seed_file = match prev_late { Some(p) => format!("late-{p}.json"), None => "pre-lens.json".to_string() };
    let o = seam_opts(None);
    let mut n = 0;
    for f in fixtures() {
        n += 1;
        if !m.ported { must_exist(&f, &format!("late-{name}.json")); continue; }
        let want_out = want(&f, &format!("late-{name}.json"));
        let seed_out = want(&f, &seed_file);
        let seed_shared = want(&f, "pre-lens.shared.json");
        let got = lay::export_late(&inputs(&f), &o, name, seed_out, Some(&seed_shared)).unwrap_or_else(|e| panic!("자료 {} · 모듈 {name}(늦은 차례): {e}", f.name));
        assert_same(&f, &format!("late-{name}"), &got, &want_out);
        assert_same_bytes(&f, &format!("late-{name}"), &got, &want_out);
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다 — 자료 목록 · 정답지를 확인하세요");
    if m.ported { eprintln!("모듈 {name}의 늦은 차례: 자료 {n}개 Node와 같음(값 · json 글 바이트) — {seed_file}을 심고 이 늦은 차례만 돌림"); }
    else { eprintln!("모듈 {name}의 늦은 차례: 아직 옮기지 않음 — 건너뜀(정답지 자료 {n}개 있음)"); }
}

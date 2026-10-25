//! 갈래 E — REPLAY · 다시 배치를 하는 모듈(variants · boards · lens)이 끝난 뒤 **원래 문맥이 그대로**인지(갈래 C의 알림: `js::release`는 닿는 그릇을 모두 비운다).
//! REPLAY의 sub 문맥(`lay::m::variants::Sub` — shared · notes · boards는 사건을 거른 얕은 사본 모델을 바꿔 끼움)은 되돌릴 때 바꿔 끼운 것만 되돌리고 공유 값을 풀지 않는다.
//! 자료마다 Node의 앞 모듈 출력(`pre-<앞>` · `.shared`)을 심고 그 모듈 하나만 돌린 뒤:
//! ① 연표 상태 · 모델의 덤프가 줄 배정 정답지(`rows.json`)와 같다 — 모델 · tl의 그릇이 비지 않았고 tl은 기본 배치로 돌아왔다.
//!    variants만 JS도 남기는 것이 있다(아래 [`VARIANT_LEFTOVERS`] — 그 밖의 차이는 하나도 없어야 함 · 바이트 견줌은 boards · lens만).
//! ② `ctx.shared`가 심은 그대로다(REPLAY의 새 shared가 새지 않았다) ③ 문맥을 버리면 그릇 수가 처음으로 돌아온다(새는 고리 없음).
mod common;
use archive_engine::lay::{self, ctx, js, same, Contribute};
use common::oracle::{assert_same, fixtures, inputs, oracle, oracle_body, oracle_js, seam_opts};

/// variants 뒤에 JS도 남기는 것(덤프에 **더해진** 열쇠만 — 값이 바뀐 것은 허락하지 않음):
/// - `_laneAll`: 변형(소속 · 단체 펼치기)을 켠 배치에서 보였던 소속 정권에 접힌 트랙용 막대 단이 적히고, 기본 배치로 되돌리면 그 정권은 다시 숨어
///   `assignLanes`(숨지 않은 정권만)가 지우지 않는다 — `_layoutTrack` 그대로(JS도 같은 열쇠가 남음). (`_laneRow`는 접힌 민족 줄에서만 적혀 내보내기에서 생길 수 없다 — 허락하지 않음)
/// - `model._unionPairs`: links 모듈의 `HT.unionPairs` 기억(모델 객체에 둠 — JS도 같음). REPLAY가 같은 모델로 links를 부르면 생긴다.
const VARIANT_LEFTOVERS: [&str; 2] = ["._laneAll", "model._unionPairs"];
/// 자료마다 그 남는 열쇠의 수(Node로 같은 셈을 해 굳힌 값 — 판정 R29 · `@f4` 사본도 같은 수 · 목록에 없는 자료는 0). 수가 다르면 실패.
const VARIANT_LEFTOVER_COUNTS: [(&str, usize); 11] = [
    ("lantern", 18), ("east-asia+d7", 8), ("east-asia+dep", 3), ("synth+patch", 3), ("synth", 2), ("east-asia+move", 1), ("east-asia+nest", 1), ("nest-f4", 1),
    ("synth-lay", 8), ("synth-lens", 5), // 과제 X 합성 자료(Node로 같은 셈 — 고침 1회차)
    ("f4-federation", 13), // 리메이크 3단계 정답지 자료(형식 4 가상 팩 — 연방 구성국의 소속 펼치기 · Node로 같은 셈 2026-10-24)
];

fn intact(module: &str, prev: &str, run: Contribute, leftovers: &[&str]) {
    let o = seam_opts(Some(module));
    let base = js::live_containers();
    let (mut seen, mut left) = (0, 0usize);
    for f in fixtures() {
        {
            let mut c = ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
            let seed_shared = oracle(&f, &format!("pre-{prev}.shared.json"));
            c.shared = lay::export::shared_seed(&seed_shared).expect("shared 심기");
            let shared_before = lay::export::shared_dump(&c);
            let mut out = oracle(&f, &format!("pre-{prev}.json"));
            if let Some(m) = out.as_object_mut() { m.remove("$oracle"); }
            run(&mut c, &mut out).unwrap_or_else(|e| panic!("자료 {} · {module}: {e}", f.name));
            let want = oracle_js(&f, "rows.json");
            let (got_v, want_v) = (ctx::dump(&c), js::to_json(&want));
            js::release(&want);
            if leftovers.is_empty() {
                assert_same(&f, &format!("rows({module} 뒤)"), &got_v, &want_v);
                assert!(ctx::dump_text(&c) == oracle_body(&f, "rows.json"), "자료 {} · rows({module} 뒤): 값은 같은데 덤프 글이 다릅니다", f.name);
            } else {
                let d = same::diff(&got_v, &want_v, usize::MAX);
                let (ok, bad): (Vec<&String>, Vec<&String>) = d.iter().partition(|line| {
                    let (path, rest) = line.split_once(": ").unwrap_or((line.as_str(), ""));
                    rest.ends_with("≠ (없음)") && leftovers.iter().any(|k| if k.starts_with('.') { path.ends_with(k) } else { path.starts_with(k) })
                });
                assert!(bad.is_empty(), "자료 {} · rows({module} 뒤): JS가 남기는 것 밖의 차이 {}곳(앞 20)\n  {}", f.name, bad.len(),
                    bad.iter().take(20).map(|s| s.as_str()).collect::<Vec<_>>().join("\n  "));
                let base_name = f.name.trim_end_matches("@f4");
                let want_n = VARIANT_LEFTOVER_COUNTS.iter().find(|(k, _)| *k == base_name).map_or(0, |(_, n)| *n);
                assert_eq!(ok.len(), want_n, "자료 {} · rows({module} 뒤): JS도 남기는 더해진 열쇠의 수가 Node와 다릅니다", f.name);
                left += ok.len();
            }
            assert_same(&f, &format!("shared({module} 뒤)"), &lay::export::shared_dump(&c), &shared_before);
        }
        assert_eq!(js::live_containers(), base, "자료 {} · {module}: 문맥을 버린 뒤 그릇 수가 처음과 다릅니다(새는 고리)", f.name);
        seen += 1;
    }
    assert!(seen > 0, "정답지 자료가 없습니다");
    eprintln!("{module} 뒤 원래 문맥 그대로(tl · 모델 = rows.json · shared 그대로 · 새는 고리 없음): 자료 {seen}개{}",
        if leftovers.is_empty() { " — 값 · 바이트".to_string() } else { format!(" — JS도 남기는 더해진 열쇠 {left}곳({} — 자료별 수가 Node와 같음)만 다름", leftovers.join(" · ")) });
}

#[test]
fn variants_leave_the_context_intact() { intact("variants", "power", lay::m::variants::contribute, &VARIANT_LEFTOVERS); }

#[test]
fn boards_leave_the_context_intact() { intact("boards", "variants", lay::m::boards::contribute, &[]); }

#[test]
fn lens_leaves_the_context_intact() { intact("lens", "metro", lay::m::lens::contribute, &[]); }

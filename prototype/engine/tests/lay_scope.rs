//! 한 벌 P3 과제 16a — 부분 셈의 앞 절반: 범위 갈래(`Scope::Tracks(S)`) · 닿는 트랙(`lay::touched`)의 넓이 · 규칙 판(`lay::RULES`)의 낡음.
//!
//! - [`scope_tracks_is_sub_plan_of_all`]: 정답지 자료마다 · 트랙 열쇠 집합(하나 · 둘 · 셋 — 씨앗 고정 무작위 + 다른 트랙을 가리는 트랙 하나)마다
//!   `export(Tracks(S))` = `patch::sub_plan(export(All), S)` — 그리고 그 하위 배치의 겉 `allTracks` = 조합의 트랙 차례, 트랙 지문 · 온 판 지문 = 통째의 것,
//!   변형의 S 밖 가림에 `outer.hideAt` · `outer.hideOwners`가 나란히(P4 과제 9가 더한 것 — 16b가 빠르게 해도 이 값과 같아야 한다).
//! - 넓이(`width_*`): 정답지 자료 · 합성 자료의 조합마다 넣기 · 빼기 · 판 바꿈에서 **`touched` ⊇ {앞 · 뒤 배치의 트랙 지문(`patch::prints`)이 다른 트랙} ∪ 새 트랙**
//!   · 결과 ⊆ 새 조합의 열쇠(P4 장부 'Carry → P3-16'). 합성은 P4 약속 그대로: 넣기 `touched(새것, 뒤)` · 빼기 `touched(뺀 것, 앞)` ∩ 뒤 ·
//!   판 바꿈 `touched(옛 판, 앞)` ∪ `touched(새 판, 뒤)` — 그리고 한 번에 견주는 `touch::between(앞, 뒤)`도 같은 그물로. 짐작한 트랙 열쇠 전부(`Touch.all` — 판 트랙 포함)가
//!   실제 배치의 열쇠 차례와 같은지도. 빠지면 그 트랙 열쇠와 그 트랙에서 처음 갈린 항목을 찍는다.
//! - [`ktl_touches_its_track_and_the_succession_end`]: `touched(KTL, 동아시아+KTL)` = 손으로 적은 기대 집합(감독 PC의 선택 자료 — 없으면 건너뜀).
//! - [`rules_constant_is_fresh`]: `lay::RULES`가 지금 원본의 지문과 같다(다르면 `node prototype/scripts/lay-rules.mjs --write`).
//! - [`timing_east_asia_ktl`](무시 — 따로 돌림): 걸음 5의 지금 값(ms · 힙 정점 · touched 크기).
mod common;
use archive_engine::lay::{self, js, touch, Opts, PackIn, Scope};
use archive_engine::patch;
use common::oracle::{assert_same, fixtures, inputs, seam_opts};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::atomic::{AtomicIsize, Ordering};

// ---------------------------------------------------------------- 힙 정점(걸음 5)

/// 힙을 세는 할당기 — 이 검사 바이너리에서만(걸음 5의 메모리 정점: 잴 때 정점을 지금 값으로 되돌리고 잰 뒤 정점 − 시작).
struct Counting;
static CUR: AtomicIsize = AtomicIsize::new(0);
static PEAK: AtomicIsize = AtomicIsize::new(0);
unsafe impl std::alloc::GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: std::alloc::Layout) -> *mut u8 {
        let p = std::alloc::System.alloc(l);
        if !p.is_null() {
            let c = CUR.fetch_add(l.size() as isize, Ordering::Relaxed) + l.size() as isize;
            PEAK.fetch_max(c, Ordering::Relaxed);
        }
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, l: std::alloc::Layout) {
        std::alloc::System.dealloc(p, l);
        CUR.fetch_sub(l.size() as isize, Ordering::Relaxed);
    }
    unsafe fn realloc(&self, p: *mut u8, l: std::alloc::Layout, size: usize) -> *mut u8 {
        let q = std::alloc::System.realloc(p, l, size);
        if !q.is_null() {
            let c = CUR.fetch_add(size as isize - l.size() as isize, Ordering::Relaxed) + size as isize - l.size() as isize;
            PEAK.fetch_max(c, Ordering::Relaxed);
        }
        q
    }
}
#[global_allocator]
static ALLOC: Counting = Counting;

/// `f`를 돌리는 동안의 힙 정점(시작 대비 바이트)과 답.
fn peak_of<T>(f: impl FnOnce() -> T) -> (T, isize) {
    let start = CUR.load(Ordering::Relaxed);
    PEAK.store(start, Ordering::Relaxed);
    let out = f();
    (out, PEAK.load(Ordering::Relaxed) - start)
}

// ---------------------------------------------------------------- 도움

/// 씨앗 고정 무작위(xorshift64*).
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    /// 목록에서 서로 다른 k개.
    fn pick(&mut self, from: &[String], k: usize) -> BTreeSet<String> {
        let mut left: Vec<&String> = from.iter().collect();
        let mut out = BTreeSet::new();
        while out.len() < k && !left.is_empty() {
            let i = (self.next() % left.len() as u64) as usize;
            out.insert(left.remove(i).clone());
        }
        out
    }
}

fn opts() -> Opts { seam_opts(None) }

fn export(packs: &[PackIn], what: &str) -> Value {
    lay::export(packs, &opts()).unwrap_or_else(|e| panic!("{what}: 내보내기를 하지 못했습니다 — {e}"))
}

/// 변형 목록(겉 · `boards`).
fn variants_of(plan: &Value) -> Vec<&Value> {
    let mut out: Vec<&Value> = plan["variants"].as_array().map(|l| l.iter().collect()).unwrap_or_default();
    out.extend(plan["boards"]["variants"].as_array().into_iter().flatten());
    out
}

// ---------------------------------------------------------------- 범위 갈래

/// `export(Tracks(S))` = `sub_plan(export(All), S)` — 정답지 자료마다 · 집합 셋(하나 · 둘 · 셋)마다 + 다른 트랙을 가리는 트랙이 있으면 그 하나.
#[test]
fn scope_tracks_is_sub_plan_of_all() {
    let o = opts();
    let mut rng = Rng(0x16a_5c0e);
    let (mut sets, mut outer_hides, mut n) = (0, 0, 0);
    for f in fixtures() {
        let packs = inputs(&f);
        let all = export(&packs, &f.name);
        let whole = patch::prints(&all).expect("통째 배치의 지문");
        let keys = whole.order.clone();
        let mut picks: Vec<BTreeSet<String>> = (1..=3).filter(|k| *k <= keys.len()).map(|k| rng.pick(&keys, k)).collect();
        if let Some(k) = keys.iter().find(|k| !whole.tracks[*k].hides.is_empty()) {
            picks.push(BTreeSet::from([k.clone()]));
        }
        // 과제 16b: 첫 트랙(렌즈 변형의 자리)이 빠진 집합 — 렌즈 변형이 하위 배치에 남지 않는 꼴.
        if keys.len() > 1 {
            picks.push(keys[1..].iter().take(2).cloned().collect());
        }
        for s in picks {
            let got = lay::export(&packs, &Opts { scope: Scope::Tracks(s.clone()), ..o.clone() })
                .unwrap_or_else(|e| panic!("자료 {} · S {s:?}: 범위 내보내기를 하지 못했습니다 — {e}", f.name));
            let want = patch::sub_plan(&all, &s).expect("sub_plan");
            assert_same(&f, &format!("Tracks({s:?})"), &got, &want);
            // P4 과제 9가 하위 배치에 더한 것 — 겉 allTracks · 지문이 통째와 같음 · S 밖 가림의 hideAt · hideOwners.
            assert_eq!(got["allTracks"], json!(keys), "자료 {} · S {s:?}: allTracks가 조합의 트랙 차례와 다릅니다", f.name);
            let sp = patch::prints(&got).unwrap_or_else(|e| panic!("자료 {} · S {s:?}: 하위 배치의 지문 — {e}", f.name));
            assert_eq!(sp.globals, whole.globals, "자료 {} · S {s:?}: 온 판 지문", f.name);
            assert_eq!(sp.order, keys.iter().filter(|k| s.contains(*k)).cloned().collect::<Vec<_>>(), "자료 {} · S {s:?}: 하위 배치의 트랙 차례", f.name);
            for k in &s {
                assert_eq!(sp.tracks[k], whole.tracks[k], "자료 {} · S {s:?}: 트랙 {k}의 지문이 통째의 것과 다릅니다", f.name);
            }
            // 판정 R45: 지문은 이음 번호를 트랙 안 거리로 · notes의 순번을 열쇠로 적는다(위 지문 견줌이 그 꼴) — 하위 배치는 조합 전부의 이음 첫 값을 싣는다.
            assert_eq!(got["stripFirst"], json!(patch::strip_firsts(&all).expect("이음 첫 값")), "자료 {} · S {s:?}: stripFirst", f.name);
            for v in variants_of(&got) {
                let hides = v["outer"]["hides"].as_array().map_or(0, Vec::len);
                if hides == 0 {
                    continue;
                }
                let at = v["outer"]["hideAt"].as_array().map_or(0, Vec::len);
                let owners = v["outer"]["hideOwners"].as_array().map_or(0, Vec::len);
                assert!(at == hides && owners == hides, "자료 {} · S {s:?} · 변형 {}: outer.hides {hides} · hideAt {at} · hideOwners {owners}", f.name, v["key"]);
                outer_hides += hides;
            }
            sets += 1;
        }
        n += 1;
    }
    assert!(n > 0, "견준 자료가 없습니다");
    eprintln!("범위 갈래: 자료 {n}개 · 집합 {sets}개 — export(Tracks(S)) = sub_plan(export(All), S) · allTracks · 지문 · S 밖 가림 {outer_hides}개의 hideAt · hideOwners");
}

/// 과제 16b: 닿는 트랙(`touch::touched_scope` — 실제 틈의 몸)이 남긴 '뒤' 조합의 준비를 곧이은 내보내기가 다시 써도 답은 새로 준비한 것과 같다(범위 · 통째) ·
/// 한 번 쓰면 비고 · 조합이 다른 내보내기는 그것을 쓰지 않는다(버린다).
#[test]
fn touched_scope_hands_its_prepared_context_to_export() {
    let o = opts();
    let mut n = 0;
    for f in fixtures().into_iter().filter(|f| ["synth+patch", "east-asia+d7", "synth-lay", "east-asia+ktl", "lantern"].contains(&f.name.as_str())) {
        let packs = inputs(&f);
        if packs.len() < 2 { continue; }
        let before = &packs[..packs.len() - 1];
        for whole in [false, true] {
            let scope = touch::touched_scope(before, &packs, &o).unwrap_or_else(|e| panic!("{}: touched_scope — {e}", f.name));
            assert!(lay::export::prepared_held(), "{}: 닿는 트랙이 준비를 남기지 않았습니다", f.name);
            let scoped = Opts { scope: if whole { Scope::All } else { scope }, ..o.clone() };
            let got = lay::export(&packs, &scoped).unwrap_or_else(|e| panic!("{}: 남긴 준비로 내보내기 — {e}", f.name));
            assert!(!lay::export::prepared_held(), "{}: 쓴 준비가 남았습니다", f.name);
            let want = lay::export(&packs, &scoped).expect("새로 준비해 내보내기");
            assert_same(&f, &format!("남긴 준비 · {:?}", scoped.scope), &got, &want);
            n += 1;
        }
        // 다른 조합(앞 조합)을 내보내면 남긴 것을 쓰지 않는다.
        touch::touched_scope(before, &packs, &o).expect("touched_scope");
        let got = lay::export(before, &o).expect("앞 조합");
        assert!(!lay::export::prepared_held(), "{}: 다른 조합의 내보내기 뒤에도 준비가 남았습니다", f.name);
        assert_same(&f, "다른 조합", &got, &lay::export(before, &o).unwrap());
    }
    // 필수 자료 둘(synth+patch · east-asia+d7) × (범위 · 통째) = 넷. 선택 자료 east-asia+ktl(감독 PC에만)이 있으면 여섯 — 없는 PC에서 멈추지 않게 넷을 기준으로.
    assert!(n >= 4, "견준 것이 너무 적습니다: {n}");
}

/// 범위 갈래는 배치에 없는 **판 트랙** 열쇠만 걸러 낸다(닿는 트랙이 판의 있고 없음을 짐작하므로 — `lay::export` 머리글) · 그 밖의 없는 열쇠는 `sub_plan`의 오류 그대로.
#[test]
fn scope_tracks_drops_missing_boards_only() {
    let f = fixtures().into_iter().find(|f| f.name == "synth").expect("합성 자료 synth");
    let packs = inputs(&f);
    let all = export(&packs, &f.name);
    let k = patch::prints(&all).expect("지문").order[0].clone();
    let with_board: BTreeSet<String> = [k.clone(), "board:__board:view:없는 판".to_string()].into_iter().collect();
    let got = lay::export(&packs, &Opts { scope: Scope::Tracks(with_board), ..opts() }).expect("없는 판 열쇠는 걸러 낸다");
    assert_same(&f, "없는 판 열쇠를 거른 하위 배치", &got, &patch::sub_plan(&all, &BTreeSet::from([k.clone()])).unwrap());
    let with_track: BTreeSet<String> = [k, "없는-트랙".to_string()].into_iter().collect();
    let err = lay::export(&packs, &Opts { scope: Scope::Tracks(with_track), ..opts() }).err().expect("판이 아닌 없는 열쇠는 오류").to_string();
    assert!(err.contains("배치에 없는 트랙"), "{err}");
}

// ---------------------------------------------------------------- 넓이

/// 조합 하나의 바뀜.
enum Change {
    Add(PackIn),
    Remove(PackIn),
    Version(PackIn, PackIn),
}

struct Combo {
    name: String,
    before: Vec<PackIn>,
    after: Vec<PackIn>,
    change: Change,
}

/// 내보낸 배치 · 지문 기억(같은 조합을 두 번 내보내지 않게).
#[derive(Default)]
struct Cache(HashMap<String, (Value, patch::Prints)>);
impl Cache {
    fn get(&mut self, packs: &[PackIn]) -> &(Value, patch::Prints) {
        let id: String = packs.iter().map(|p| format!("{}#{:x}", p.name, sha(&p.bytes))).collect::<Vec<_>>().join("|");
        self.0.entry(id.clone()).or_insert_with(|| {
            let plan = export(packs, &id);
            let prints = patch::prints(&plan).unwrap_or_else(|e| panic!("{id}: 지문 — {e}"));
            (plan, prints)
        })
    }
}

fn sha(bytes: &[u8]) -> u64 {
    use sha2::{Digest, Sha256};
    let d = Sha256::digest(bytes);
    u64::from_le_bytes(d[..8].try_into().unwrap())
}

/// 넓이 검사의 셈: 넓이 · 크기를 모아 둔다.
#[derive(Default)]
struct Tally {
    combos: usize,
    sizes: Vec<(usize, usize)>,
    required: usize,
    /// 모든 트랙이 된 조합(규칙 3 · 4 · 8)의 수.
    everything: usize,
    /// 짐작했으나 배치에 없는 판 트랙(판 셈 오류로 빠진 판)의 수.
    extra_boards: usize,
    /// 앞 · 뒤 배치에서 서거나 사라진 판 트랙의 수(넓히기 몫 — 판정 R54 I2).
    flipped: usize,
    fails: Vec<String>,
}

/// 트랙 하나의 조각(하위 배치에서 온 판 · 항목 기록을 뗀 것) — 빠진 트랙의 처음 갈린 항목을 찍으려고.
fn track_part(plan: &Value, key: &str) -> Value {
    let Ok(mut sub) = patch::sub_plan(plan, &BTreeSet::from([key.to_string()])) else { return Value::Null };
    if let Some(o) = sub.as_object_mut() {
        for k in ["name", "packs", "categories", "epochs", "entities", "spheres", "yearCycle", "yearCycles", "sphereLines", "blobs", "allTracks", "now"] {
            o.remove(k);
        }
        if let Some(b) = o.get_mut("boards").and_then(Value::as_object_mut) {
            b.remove("entities");
        }
    }
    sub
}

/// 조합 하나를 견준다.
fn check(c: &Combo, cache: &mut Cache, tally: &mut Tally) {
    let o = opts();
    let (plan_b, pb) = cache.get(&c.before).clone();
    let (plan_a, pa) = cache.get(&c.after).clone();
    let after_keys: BTreeSet<String> = pa.order.iter().cloned().collect();
    let required: BTreeSet<String> = pa.order.iter()
        .filter(|k| pb.tracks.get(*k).map(|t| &t.print) != Some(&pa.tracks[*k].print)).cloned().collect();
    // P4 약속의 합성
    let composed: BTreeSet<String> = match &c.change {
        Change::Add(new) => touch::touched_why(new, &c.after, &o).map(|t| t.keys).unwrap_or_else(|e| panic!("{}: touched — {e}", c.name)),
        Change::Remove(gone) => {
            // 빼기 = touched(뺀 것, 앞) ∩ keys(뒤) ∪ (keys(뒤) − keys(앞)) — 뒤에만 서는 트랙(숨기던 띠가 돌아와 다시 서는 판 트랙 따위)은 앞 조합의 열쇠에 없다.
            let (ka, kb) = (touch::keys(&c.after, &o).expect("keys(뒤)"), touch::keys(&c.before, &o).expect("keys(앞)"));
            let ka: BTreeSet<String> = ka.into_iter().collect();
            let mut s: BTreeSet<String> = touch::touched_why(gone, &c.before, &o).map(|t| t.keys).unwrap_or_else(|e| panic!("{}: touched — {e}", c.name))
                .intersection(&ka).cloned().collect();
            s.extend(ka.iter().filter(|k| !kb.contains(*k)).cloned());
            s
        }
        Change::Version(old, new) => {
            let mut s = touch::touched_why(old, &c.before, &o).map(|t| t.keys).unwrap_or_else(|e| panic!("{}: touched(옛 판) — {e}", c.name));
            s.extend(touch::touched_why(new, &c.after, &o).map(|t| t.keys).unwrap_or_else(|e| panic!("{}: touched(새 판) — {e}", c.name)));
            s.intersection(&after_keys).cloned().collect()
        }
    };
    let direct = touch::between(&c.before, &c.after, &o).unwrap_or_else(|e| panic!("{}: between — {e}", c.name));
    tally.combos += 1;
    tally.required += required.len();
    tally.everything += usize::from(direct.everything.is_some());
    tally.sizes.push((direct.keys.len(), pa.order.len()));
    // 짐작한 열쇠 = 실제 열쇠(차례까지) + 판 셈 오류로 빠진 판 트랙(`boards.mjs`의 뺀 판 — 배치 없이는 모름)만 더.
    let predicted_real: Vec<&String> = direct.all.iter().filter(|k| after_keys.contains(*k)).collect();
    let extra: Vec<&String> = direct.all.iter().filter(|k| !after_keys.contains(*k)).collect();
    if predicted_real != pa.order.iter().collect::<Vec<_>>() || extra.iter().any(|k| !k.starts_with("board:")) {
        tally.fails.push(format!("{}: 짐작한 트랙 열쇠가 실제와 다릅니다\n    짐작 {:?}\n    실제 {:?}", c.name, direct.all, pa.order));
    }
    tally.extra_boards += extra.len();
    // 판이 서거나 사라짐(판정 R54 I2 — 뺀 판(판 셈 오류로 빠지는 판)이 뒤집히면 짐작은 앞 · 뒤 모두 '있음'이라 닿는 트랙이 모른다): apply(Part)의 넓히기가
    // 저장소 대비 서거나 사라지는 판과 그 판의 구성 트랙(`row_targets`) · 가림 대상(`hides`)을 더한다(`patch::choose`) — 그 몫을 흉내 내어 더한다.
    let mut widened: BTreeSet<String> = BTreeSet::new();
    for (p, q) in [(&pa, &pb), (&pb, &pa)] {
        for k in p.order.iter().filter(|k| k.starts_with("board:") && !q.tracks.contains_key(*k)) {
            tally.flipped += 1;
            widened.insert(k.clone());
            widened.extend(p.tracks[k].row_targets.iter().chain(&p.tracks[k].hides).cloned());
        }
    }
    widened.retain(|k| after_keys.contains(k));
    for (what, got) in [("합성", &composed), ("between", &direct.keys)] {
        // 새 조합에 없는 열쇠는 짐작이 빗나간 판 트랙만 받는다(`lay::export`의 범위 갈래가 걸러 냄 — scope_tracks_drops_missing_boards_only).
        if let Some(stray) = got.iter().find(|k| !after_keys.contains(*k) && !extra.contains(k)) {
            tally.fails.push(format!("{} · {what}: 새 조합에 없는 열쇠 {stray}", c.name));
        }
        let got: &BTreeSet<String> = &got.union(&widened).cloned().collect();
        for k in required.difference(got) {
            let first = if pb.tracks.contains_key(k) {
                lay::same::diff(&track_part(&plan_a, k), &track_part(&plan_b, k), 2).join(" / ")
            } else {
                "(새 트랙)".into()
            };
            tally.fails.push(format!("{} · {what}: 지문이 바뀐 트랙 {k}이 빠짐(touched {got:?}) — 처음 갈린 곳(왼쪽 뒤 · 오른쪽 앞): {first}", c.name));
        }
    }
}

/// 셈을 찍고 어김을 돌려준다(없으면 None).
fn finish(label: &str, tally: Tally) -> Option<String> {
    let n = tally.sizes.len().max(1);
    let max = tally.sizes.iter().map(|s| s.0).max().unwrap_or(0);
    let avg = tally.sizes.iter().map(|s| s.0 as f64).sum::<f64>() / n as f64;
    let avg_all = tally.sizes.iter().map(|s| s.1 as f64).sum::<f64>() / n as f64;
    let ratio = tally.sizes.iter().map(|s| if s.1 == 0 { 0.0 } else { s.0 as f64 / s.1 as f64 }).sum::<f64>() / n as f64;
    eprintln!("넓이 {label}: 조합 {} · touched 최대 {max} · 평균 {avg:.2}(트랙 평균 {avg_all:.2} — 비율 평균 {:.0}%) · 지문이 바뀐 트랙 합 {} · 모든 트랙이 된 조합 {} · 짐작이 빗나간 판 {} · 서거나 사라진 판 {}", tally.combos, ratio * 100.0, tally.required, tally.everything, tally.extra_boards, tally.flipped);
    if tally.combos == 0 {
        return Some(format!("넓이 {label}: 견준 조합이 없습니다"));
    }
    (!tally.fails.is_empty()).then(|| format!("넓이 {label}: {}건\n  {}", tally.fails.len(), tally.fails.join("\n  ")))
}

/// 조합들을 견준다(지문은 `patch::prints` 그대로 — 판정 R45 뒤로 이음 번호 · notes의 트랙 순번이 새지 않는 꼴 하나). 같은 배치를 두 번 내보내지 않게 기억을 나눠 쓴다.
/// 답: 서거나 사라진 판 트랙의 수(넓히기 몫을 지난 수 — 빈 시험 가리기).
fn run(label: &str, combos: &[Combo]) -> usize {
    let mut cache = Cache::default();
    let mut tally = Tally::default();
    for c in combos {
        check(c, &mut cache, &mut tally);
    }
    let flipped = tally.flipped;
    if let Some(fails) = finish(label, tally) {
        panic!("{fails}");
    }
    flipped
}

/// 조합의 넣기 · 빼기(기본 DLC가 아닌 것마다): 빼기 = (P, P − i) · 넣기 = (P − i, (P − i) + [P_i]).
fn add_remove(name: &str, packs: &[PackIn], out: &mut Vec<Combo>) {
    for i in 1..packs.len() {
        let rest: Vec<PackIn> = packs.iter().enumerate().filter(|(j, _)| *j != i).map(|(_, p)| p.clone()).collect();
        let mut appended = rest.clone();
        appended.push(packs[i].clone());
        out.push(Combo { name: format!("{name} − {}", packs[i].name), before: packs.to_vec(), after: rest.clone(), change: Change::Remove(packs[i].clone()) });
        out.push(Combo { name: format!("{name} + {}", packs[i].name), before: rest, after: appended, change: Change::Add(packs[i].clone()) });
    }
}

/// 넓이 ①: 정답지 자료의 조합(DLC가 둘 이상인 것)마다 넣기 · 빼기.
#[test]
fn width_fixture_add_remove() {
    let mut combos = Vec::new();
    for f in fixtures() {
        let packs = inputs(&f);
        if packs.len() >= 2 {
            add_remove(&f.name, &packs, &mut combos);
        }
    }
    run("① 정답지 자료 넣기 · 빼기", &combos);
}

/// 넓이 ②: 합성 조합 — 동아시아 + 장면 DLC 다섯(+ KTL이 있으면)을 한꺼번에 켠 조합에서 하나씩 빼기 · 다시 넣기(형식 3 · 형식 4).
#[test]
fn width_big_combo() {
    let mut combos = Vec::new();
    for at4 in [false, true] {
        let mut packs: Vec<PackIn> = Vec::new();
        for f in fixtures() {
            let is4 = f.name.ends_with("@f4");
            if is4 != at4 || !f.name.starts_with("east-asia") {
                continue;
            }
            let ins = inputs(&f);
            if packs.is_empty() {
                packs.push(ins[0].clone());
            }
            for p in &ins[1..] {
                if !packs.iter().any(|q| q.bytes == p.bytes) {
                    packs.push(p.clone());
                }
            }
        }
        if packs.len() >= 3 {
            add_remove(if at4 { "동아시아+장면 전부@f4" } else { "동아시아+장면 전부" }, &packs, &mut combos);
        }
    }
    run("② 합성 조합(장면 전부)", &combos);
}

/// DLC 바이트 → JS 값(형식 그대로 — .htpack은 풀어서).
fn raw_of(p: &PackIn) -> js::V {
    let text = if p.bytes.starts_with(archive_engine::PACK_MAGIC) {
        String::from_utf8(archive_engine::unseal(&p.bytes, archive_engine::KIND_DLC).expect("unseal").plain).expect("UTF-8")
    } else {
        String::from_utf8(p.bytes.clone()).expect("UTF-8")
    };
    js::parse(text.trim_start_matches('\u{feff}')).expect("JSON")
}

/// JS 값 → JSON DLC 입력(이름 `<이름>.json`).
fn pack_in(name: &str, v: &js::V) -> PackIn {
    PackIn { name: format!("{name}.json"), bytes: js::stringify(v).into_bytes() }
}

/// 판 바꿈 합성: 원본을 조금 고친 새 판. 무엇을 고쳤는지 글로(못 고치면 None).
fn mutate(raw: &js::V, how: &str, other_track: &str) -> Option<(js::V, String)> {
    let v = js::parse(&js::stringify(raw)).ok()?; // 사본
    let first_of = |key: &str| -> Option<js::Obj> { v.get(key).as_arr().and_then(|a| a.to_vec().into_iter().find_map(|x| x.as_obj().cloned())) };
    let list_key = ["periods", "objects", "events"].into_iter().find(|k| first_of(k).is_some());
    match how {
        "판만" => {
            v.as_obj()?.set("version", "9.9.9");
            Some((v, "판 글만".into()))
        }
        "기간" => {
            let k = list_key?;
            let x = first_of(k)?;
            let field = if matches!(x.get("end"), js::V::Num(_)) { "end" } else { "start" };
            let js::V::Num(y) = x.get(field) else { return None };
            x.set(field, y + 7.0);
            Some((v, format!("{k}[0].{field} + 7")))
        }
        "이름" => {
            let k = list_key?;
            let x = first_of(k)?;
            let field = if k == "events" { "title" } else { "name" };
            let js::V::Str(s) = x.get(field) else { return None };
            x.set(field, format!("{}′", s.as_str()));
            Some((v, format!("{k}[0].{field} 바꿈")))
        }
        "트랙" => {
            let k = list_key?;
            let x = first_of(k)?;
            if !matches!(x.get("track"), js::V::Str(_)) || other_track.is_empty() {
                return None;
            }
            x.set("track", other_track);
            Some((v, format!("{k}[0].track → {other_track}")))
        }
        "패치" => {
            let a = v.get("patches").as_arr()?.clone();
            if a.is_empty() {
                return None;
            }
            a.borrow_mut().remove(0);
            Some((v, "patches[0] 뺌".into()))
        }
        // 트랙 객체의 이름 · 색만(판정 R54 I1 — 트랙 항목이 이 객체에서 읽는다 · 집이 비면 빠졌다).
        "트랙 이름 · 색" => {
            let t = first_of("tracks")?;
            let js::V::Str(s) = t.get("name") else { return None };
            t.set("name", format!("{}′", s.as_str()));
            t.set("color", "#123456");
            Some((v, format!("tracks[0]({}) 이름 · 색", js::to_str(&t.get("id")).as_str())))
        }
        _ => None,
    }
}

/// 넓이 ③: 판 바꿈(같은 DLC의 다른 판 — 합성) — 정답지 조합의 마지막 DLC와 합성 자료의 기본 DLC를 고친 새 판으로.
#[test]
fn width_version_change() {
    let mut combos = Vec::new();
    for f in fixtures() {
        let packs = inputs(&f);
        let last = packs.len() - 1;
        // 기본 DLC의 판 바꿈은 규칙 8(모든 트랙) — 합성 자료 둘에서만 본다(동아시아 · 등불은 큰 자료).
        let targets: Vec<usize> = if packs.len() >= 2 { vec![last] } else if f.name.starts_with("synth") || f.name.starts_with("nest-f4") { vec![0] } else { vec![] };
        let base_tracks: Vec<String> = patch::prints(&export(&packs, &f.name)).map(|p| p.order).unwrap_or_default();
        for at in targets {
            let raw = raw_of(&packs[at]);
            for how in ["판만", "기간", "이름", "트랙", "패치", "트랙 이름 · 색"] {
                // 다른 트랙: 원본의 트랙 가운데 고칠 항목의 트랙이 아닌 것 → 없으면 기본 DLC의 첫 트랙.
                let own: Vec<String> = raw.get("tracks").as_arr().map(|a| a.to_vec().iter().map(|t| js::to_str(&t.get("id")).as_str().into_owned()).collect()).unwrap_or_default();
                let other = own.iter().chain(base_tracks.iter()).find(|t| !t.starts_with("board:") && **t != first_track_of(&raw)).cloned().unwrap_or_default();
                let Some((new, what)) = mutate(&raw, how, &other) else { continue };
                let old = pack_in(&format!("{}-old", packs[at].name), &raw);
                let new = pack_in(&format!("{}-new", packs[at].name), &new);
                let mut before = packs.clone();
                before[at] = old.clone();
                let mut after = packs.clone();
                after[at] = new.clone();
                combos.push(Combo { name: format!("{} · {} 판 바꿈({what})", f.name, packs[at].name), before, after, change: Change::Version(old, new) });
            }
        }
    }
    run("③ 판 바꿈(합성)", &combos);
}

/// 고칠 항목(periods · objects · events의 첫째)의 트랙.
fn first_track_of(raw: &js::V) -> String {
    for k in ["periods", "objects", "events"] {
        if let Some(x) = raw.get(k).as_arr().and_then(|a| a.to_vec().into_iter().find(|x| x.as_obj().is_some())) {
            return js::to_str(&x.get("track")).as_str().into_owned();
        }
    }
    String::new()
}

/// 넓이 ④: 시험 DLC(합성 · 판정 R46 I3) — 바탕(동아시아 · 등불 · synth-lay · synth-lens와 그 @f4)의 실제 트랙을 **제 `tracks`에 적고**(안 적으면 정규화가 항목을 떨어뜨려 빈 시험)
/// 남의 트랙에 얹는 작은 DLC를 넣고 뺀다: 판만 · 시대만(공통 · 트랙) · 해 범위를 넓히는 띠 · 대범위 · 단체 · 인물 · 왕조 · 관청 · 제도 · 주제만 · 맨 앞 · 맨 뒤 새 트랙 · 간지 ·
/// 남의 트랙에 연호 · 다른 트랙에 매단 속국 · 남의 트랙 둘에 찍히는 사건 · 패치 · 새 분류 · 트랙만 적은 DLC(처음 말한 DLC가 바뀜) + 검토가 찾은 재현 셋
/// (C1: 동아시아 + 공통 시대 600–700 · 등불 + 공통 시대 500–600 · C2: synth-lay + 바다(bb)에 90–520 띠). 시험마다 **정규화 오류 0 · between(…).changed > 0**을 먼저 단언한다.
#[test]
fn width_probe_dlcs() {
    let o = opts();
    let mut combos = Vec::new();
    let mut checked = 0;
    for f in fixtures() {
        let plain = f.name.trim_end_matches("@f4");
        if !["east-asia", "lantern", "synth-lay", "synth-lens"].contains(&plain) {
            continue;
        }
        let packs = inputs(&f);
        let norm = lay::normalized(&packs[0], &o).expect("기본 DLC 정규화");
        let base_id = norm["id"].as_str().unwrap_or("").to_string();
        let track_name: HashMap<String, String> = norm["tracks"].as_array().into_iter().flatten()
            .map(|t| (t["id"].as_str().unwrap_or("").to_string(), t["name"].as_str().unwrap_or("").to_string())).collect();
        let periods: Vec<&Value> = norm["periods"].as_array().map(|l| l.iter().filter(|p| p["start"].is_number() && p["end"].is_number() && p["track"].is_string()).collect()).unwrap_or_default();
        let Some(p) = periods.first().copied() else { continue };
        let q = periods.iter().find(|x| x["track"] != p["track"]).copied().unwrap_or(p);
        let (ta, tb) = (p["track"].as_str().unwrap().to_string(), q["track"].as_str().unwrap().to_string());
        // (해 범위를 넓히는 띠는 ±1년 — 검사의 잘린 달력 표가 자료 해 ± 100년 둘레만 덮는다)
        // 대범위 구성: 띠가 셋 이상인 트랙(없으면 가장 많은 트랙)의 앞 셋
        let mut by_track: BTreeMap<String, Vec<&Value>> = BTreeMap::new();
        for x in &periods { by_track.entry(x["track"].as_str().unwrap().to_string()).or_default().push(x); }
        let (tc, rs) = by_track.iter().max_by_key(|(_, l)| l.len().min(3)).map(|(k, l)| (k.clone(), l.iter().take(3).copied().collect::<Vec<_>>())).unwrap();
        let (ps, pe) = (p["start"].as_f64().unwrap(), p["end"].as_f64().unwrap());
        let mid = ((ps + pe) / 2.0).floor().max(ps + 1.0);
        let lo = periods.iter().filter_map(|x| x["start"].as_f64()).fold(f64::INFINITY, f64::min);
        let hi = periods.iter().filter_map(|x| x["end"].as_f64()).fold(f64::NEG_INFINITY, f64::max);
        let pname = p["name"].clone();
        let head = |id: &str, tracks: &[&str]| json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": id, "name": format!("시험 {id}"), "version": "0.0.1",
            "tracks": tracks.iter().map(|t| json!({ "id": t, "name": track_name.get(*t).cloned().unwrap_or_else(|| t.to_string()) })).collect::<Vec<_>>() });
        let with = |mut d: Value, k: &str, v: Value| { d[k] = v; d };
        let mut probes: Vec<(String, Value)> = vec![
            ("판만".into(), with(head("pv", &[]), "views", json!([{ "id": "pv1", "name": "시험 판", "members": [format!("{ta}:{}", pname.as_str().unwrap_or("")), format!("{tb}:{}", q["name"].as_str().unwrap_or(""))] }]))),
            ("공통 시대만".into(), with(head("pe", &[]), "epochs", json!([{ "id": "pe1", "name": "시험 시대", "start": ps, "end": mid }]))),
            ("트랙 시대만".into(), with(head("pet", &[&tb]), "epochs", json!([{ "id": "pet1", "name": "시험 트랙 시대", "track": tb, "start": ps, "end": mid }]))),
            ("대범위만".into(), with(head("ps", &[&tc]), "scopes", json!([{ "id": "ps1", "track": tc, "name": "시험 모임", "members": rs.iter().map(|x| x["name"].clone()).collect::<Vec<_>>() }]))),
            ("단체만".into(), with(head("pg", &[&ta]), "groups", json!([{ "id": "pg1", "track": ta, "name": "시험 무리", "type": "faction", "start": ps, "end": pe, "within": pname }]))),
            ("인물만".into(), with(head("pf", &[&tb, &ta]), "figures", json!([{ "id": "pf1", "track": tb, "name": "시험 장수", "birth": ps, "death": pe, "start": ps, "end": mid,
                "service": [{ "track": ta, "polity": pname, "office": "장수", "start": ps, "end": mid }] }]))),
            ("왕조만".into(), with(head("pd", &[&ta]), "dynasties", json!([{ "id": "pd1", "track": ta, "name": "시험 왕조", "polities": pname, "start": ps, "end": mid }]))),
            ("관청만".into(), with(head("po", &[&ta]), "organs", json!([{ "id": "po1", "track": ta, "name": "시험 관청", "start": ps, "end": pe, "host": pname, "scale": "agency" }]))),
            ("제도만".into(), with(head("pi", &[&ta]), "institutions", json!([{ "id": "pi1", "theme": "law", "track": ta, "polity": pname, "spans": [["시험 법", ps, pe]] }]))),
            ("주제만(색)".into(), with(head("pth", &[]), "themes", json!([{ "id": "law", "name": "시험 법", "color": "#ff0000" }]))),
            ("주제만(새)".into(), with(head("pthn", &[]), "themes", json!([{ "id": "zz", "name": "새 주제", "color": "#00ff00" }]))),
            ("맨 앞 새 트랙(연호 · 도읍)".into(), {
                let mut d = head("pft", &[]);
                d["tracks"] = json!([{ "id": "pft-t", "name": "맨앞", "order": 0 }]);
                with(d, "periods", json!([{ "id": "pft1", "track": "pft-t", "name": "맨앞 나라", "start": ps, "end": pe, "eras": [{ "name": "앞원", "start": ps, "end": mid }], "capitals": [{ "city": "앞성", "start": ps }] }]))
            }),
            ("맨 뒤 새 트랙(연호 · 도읍)".into(), {
                let mut d = head("pbt", &[]);
                d["tracks"] = json!([{ "id": "pbt-t", "name": "맨뒤", "order": 99999 }]);
                with(d, "periods", json!([{ "id": "pbt1", "track": "pbt-t", "name": "맨뒤 나라", "start": ps, "end": pe, "eras": [{ "name": "끝원", "start": ps, "end": pe }], "capitals": [{ "city": "끝성", "start": ps }] }]))
            }),
            ("간지".into(), with(head("py", &[]), "yearCycle", json!(false))),
            ("남의 트랙에 연호".into(), with(head("peo", &[&ta]), "periods", json!([{ "id": "peo1", "track": ta, "name": "연호 나라", "start": ps, "end": pe, "eras": [{ "name": "새원", "start": ps, "end": pe }] }]))),
            ("다른 트랙에 매단 속국".into(), {
                let mut d = head("pvo", &[]);
                d["tracks"] = json!([{ "id": "pvo-t", "name": "속국 트랙" }]);
                with(d, "periods", json!([{ "id": "pvo1", "track": "pvo-t", "name": "먼 속국", "start": ps, "end": pe, "partOf": [{ "polity": pname, "relation": "tributary" }] }]))
            }),
            ("남의 트랙 둘에 찍히는 사건".into(), with(head("pev", &[&ta, &tb]), "events", json!([{ "id": "pev1", "track": ta, "tracks": [tb], "start": ps + 1.0, "title": "시험 공동 사건", "category": "politics", "polity": pname }]))),
            ("패치(기간)".into(), with(head("pp", &[]), "patches", json!([{ "target": format!("{base_id}/{}", p["id"].as_str().unwrap_or("")), "set": { "end": pe + 10.0 } }]))),
            ("새 분류".into(), {
                let d = with(head("pc", &[&ta]), "categories", json!([{ "id": "probe-cat", "name": "시험 분류", "color": "#123456" }]));
                with(d, "events", json!([{ "id": "pc1", "track": ta, "start": ps + 2.0, "title": "분류 시험", "category": "probe-cat" }]))
            }),
        ];
        // 해 범위(판 둘레)를 넓히는 띠 — 동아시아는 빼고: 검사의 잘린 달력 표(`calendar-slice.json`)가 동아시아 제 해 범위의 ± 100년 끝에 맞춰져 있어 넓히면 '달력 표 범위 밖'
        if plain != "east-asia" {
            probes.push(("해 범위를 넓히는 띠".into(), with(head("pw", &[&tb]), "periods", json!([{ "id": "pw1", "track": tb, "name": "시험 넓은 나라", "start": lo - 1.0, "end": hi + 1.0 }]))));
        }
        // 검토가 찾은 재현(판정 R46 C1 · C2)
        match plain {
            "east-asia" => probes.push(("C1 공통 시대 600–700".into(), with(head("eae", &[]), "epochs", json!([{ "id": "eae1", "name": "시험 공통 시대", "start": 600, "end": 700 }])))),
            "lantern" => probes.push(("C1 공통 시대 500–600".into(), with(head("lep", &[]), "epochs", json!([{ "id": "lep1", "name": "시험 공통 시대", "start": 500, "end": 600 }])))),
            "synth-lay" => probes.push(("C2 바다에 90–520 띠".into(), with(head("prb", &["bb"]), "periods", json!([{ "id": "prb1", "track": "bb", "name": "끼어든 바다 나라", "start": 90, "end": 520 }])))),
            _ => {}
        }
        let rc = lay::read::Ctx::new(&o).expect("읽기 문맥");
        for (what, d) in probes {
            let pin = PackIn { name: format!("{}.json", d["id"].as_str().unwrap()), bytes: serde_json::to_vec(&d).unwrap() };
            // 빈 시험이 아니게: 정규화 오류 0 · 모델이 실제로 바뀜
            let raw = lay::pack::raw_of(&rc, &pin, &mut Vec::new()).expect("시험 DLC 읽기");
            let normd = lay::read::normalize_pack(&rc, raw);
            assert!(normd.errors.is_empty(), "{} + 시험 DLC({what}): 정규화 오류 {:?}", f.name, normd.errors.iter().map(|e| e.msg.clone()).collect::<Vec<_>>());
            let normd_cycle = normd.pack.as_ref().is_some_and(|pk| !pk.get("yearCycle").is_undef());
            if let Some(pk) = &normd.pack { js::release(pk); }
            let mut all = packs.clone();
            all.push(pin.clone());
            let tt = touch::between(&packs, &all, &o).expect("between");
            let changed = tt.changed + usize::from(tt.everything.is_some()); // 모든 트랙(규칙 3 · 4)이면 바뀐 것으로
            // 간지만 적은 DLC는 모델 객체가 아니라 온 판(yearCycles 후보)만 바꾼다 — 그 셋은 정규화에 yearCycle이 남았나로 본다
            if what == "간지" { assert!(normd_cycle, "{} + 시험 DLC(간지): 정규화가 yearCycle을 떨어뜨렸습니다", f.name); } else { assert!(changed > 0, "{} + 시험 DLC({what}): 모델이 바뀌지 않았습니다(빈 시험)", f.name); }
            checked += 1;
            combos.push(Combo { name: format!("{} + 시험 DLC({what})", f.name), before: packs.clone(), after: all.clone(), change: Change::Add(pin.clone()) });
            combos.push(Combo { name: format!("{} + 시험 DLC({what}) − 그것", f.name), before: all, after: packs.clone(), change: Change::Remove(pin) });
        }
        // 트랙을 처음 말한 DLC만 바뀜(규칙 5): 트랙만 적은 X와, 같은 트랙(같은 글)을 적고 띠를 얹는 Y — 가운데 X를 빼면 그 트랙 항목의 `pack`만 X → Y.
        let mut x = head("probe-name-only", &[]);
        x["tracks"] = json!([{ "id": "probe-t2", "name": "시험 트랙 둘" }]);
        let mut y = head("probe-name-user", &[]);
        y["tracks"] = json!([{ "id": "probe-t2", "name": "시험 트랙 둘" }]);
        y["periods"] = json!([{ "id": "pn1", "track": "probe-t2", "name": "시험 나라 둘", "start": ps, "end": pe }]);
        let pin = |d: &Value| PackIn { name: format!("{}.json", d["id"].as_str().unwrap()), bytes: serde_json::to_vec(d).unwrap() };
        let (x, y) = (pin(&x), pin(&y));
        let mut both = packs.clone();
        both.extend([x.clone(), y.clone()]);
        let mut only_y = packs.clone();
        only_y.push(y);
        // 빈 시험이 아니게(판정 R54 M5): 그 트랙이 규칙 5(처음 말한 DLC가 다름)로 든다.
        let t5 = touch::between(&both, &only_y, &o).expect("between(규칙 5)");
        assert!(t5.why.get("probe-t2").is_some_and(|w| w.starts_with("규칙 5")), "{}: 트랙만 적은 DLC를 빼도 규칙 5로 들지 않았습니다 — {:?}", f.name, t5.why);
        combos.push(Combo { name: format!("{} + 트랙만 적은 DLC − 그것(트랙을 처음 말한 DLC가 바뀜)", f.name), before: both, after: only_y, change: Change::Remove(x) });
    }
    assert!(checked >= 4 * 20, "시험 DLC가 너무 적습니다: {checked}");
    run("④ 시험 DLC(합성)", &combos);
}

/// 넓이 ⑤(판정 R54 I2): 뺀 판(`boards.mjs`가 판 셈 오류로 빼는 판)이 서거나 사라지는 꼴 — 닿는 트랙의 짐작은 앞 · 뒤 모두 '있음'이라 구조 바뀜으로 보지 않는다.
/// 그 판을 켠 배치의 변형 판 항목이 실리는 구성 트랙은 apply(Part)의 넓히기가 잡는다(`patch::choose` — 저장소 대비 서거나 사라지는 판의 `row_targets` · `hides`) —
/// 넓이 검사(check)가 그 몫을 흉내 낸다. 검토가 찾은 재현: synth-lay + 늦은 공통 시대 250–300(xe — sd 줄을 다시 짓다 오류로 빠지는 판) · 섞은 판(xv)에
/// sdg1 시작 201(xf5) · sdg2 시작 205(xf6)를 넣고 뺀다. 판이 한 번도 뒤집히지 않으면 빈 시험.
#[test]
fn width_board_flips() {
    let f = fixtures().into_iter().find(|f| f.name == "synth-lay").expect("합성 자료 synth-lay");
    let base = inputs(&f);
    let pin = |d: Value| PackIn { name: format!("{}.json", d["id"].as_str().unwrap()), bytes: serde_json::to_vec(&d).unwrap() };
    let head = |id: &str, key: &str, body: Value| -> PackIn {
        let mut d = json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": id, "name": format!("시험 {id}"), "version": "0.0.1", "tracks": [] });
        d[key] = body;
        pin(d)
    };
    let xe = head("xe", "epochs", json!([{ "id": "xe1", "name": "늦은 공통 시대", "start": 250, "end": 300 }]));
    let xv = head("xv", "views", json!([{ "id": "xv1", "name": "섞은 판", "members": ["sd:갈래 3 나라", "sd:갈래 4 나라", "bb:바다 나라"] }]));
    let xf5 = head("xf5", "patches", json!([{ "target": "synth-lay/p-sdg1", "set": { "start": 201 } }]));
    let xf6 = head("xf6", "patches", json!([{ "target": "synth-lay/p-sdg2", "set": { "start": 205 } }]));
    let mut combos = Vec::new();
    for (tag, extra) in [("xe", &xe), ("xv", &xv)] {
        let mut packs = base.clone();
        packs.push(extra.clone());
        for (name, p) in [("xf5", &xf5), ("xf6", &xf6)] {
            let mut all = packs.clone();
            all.push(p.clone());
            combos.push(Combo { name: format!("synth-lay + {tag} + {name}"), before: packs.clone(), after: all.clone(), change: Change::Add(p.clone()) });
            combos.push(Combo { name: format!("synth-lay + {tag} + {name} − 그것"), before: all, after: packs.clone(), change: Change::Remove(p.clone()) });
        }
    }
    let flipped = run("⑤ 뺀 판이 서거나 사라짐(합성)", &combos);
    assert!(flipped > 0, "판이 서거나 사라진 조합이 없습니다(빈 시험)");
}

/// 합성 자료(`tests/fixtures/touch/<이름>.json`)를 DLC 입력으로.
fn touch_fixture(name: &str) -> PackIn {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("touch").join(format!("{name}.json"));
    PackIn { name: format!("{name}.json"), bytes: std::fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display())) }
}

/// 넓이 ⑥(리메이크 3단계 저장소 걸음 8): 형식 4의 이음 — 남의 실권(`power[].over`)과 직위 줄 빌림(`leadersFrom` · `cabinetsFrom` · `offices[].from`)은
/// 모델에 **글(객체 id · 이름)** 로 남고 내보내기가 그때 찾는다(`m/power.rs` `power_lines`의 `over` 찾기 · `m/strips.rs` `from_of`: uid → 같은 DLC의 id → 이름). 그래서 쥔 쪽 ·
/// 빌림 출처만 고친 DLC를 넣고 빼도 **실권 상대의 트랙**(구역 56 실권 밑줄의 이름 · 색)과 **빌린 쪽의 트랙**(구역 54 머리 글 · 직위 줄 더의 칸 종류 9)이 바뀐다.
/// 합성 자료 두 벌(이름은 모두 가상):
/// - `touch-links`(형식 4 · 바탕): 쥔 나라(over = 약한 나라의 id) · 쥔 나라 둘(over = 약한 나라 둘의 **이름**) · 원천 나라(지도자 · 내각 칸) ·
///   빌린 나라 하나(`leadersFrom` — 원천의 id) · 둘(`cabinetsFrom` — 원천의 **이름**/내각) · 셋(`offices[].from` — 원천의 id/지도자) · 앞줄 · 조용한 줄 —
///   모두 제 트랙 하나씩(트랙을 함께 쓰면 규칙 1이 덮어 빈 시험).
/// - `touch-links-patch`(형식 3): 쥔 나라 둘의 이름 · 색과 원천 나라의 이름 · 지도자 칸만 고치는 패치.
///
/// 빈 시험이 아니게: 두 자료의 정규화 오류 · 빌림 알림이 없고, 넣기에서 실권 상대 둘 · 빌린 쪽 셋의 지문이 실제로 바뀌며, 조용한 줄은 바뀌지도 닿지도 않는다
/// (그래야 `tests/add_pack.rs`의 같은 장면이 모든 트랙이 아닌 좁은 범위로 돈다). 넣기 · 빼기를 다른 넓이 검사와 같은 그물(`run` — 합성 · `between`)로 본다.
#[test]
fn width_format4_links() {
    let o = opts();
    let (base, patch) = (touch_fixture("touch-links"), touch_fixture("touch-links-patch"));
    let rc = lay::read::Ctx::new(&o).expect("읽기 문맥");
    for p in [&base, &patch] {
        let mut down = Vec::new(); // 형식 4 내림(`lay/f4.rs`)의 알림 — 빌려 올 객체 · 직위 줄을 못 찾으면 여기에
        let raw = lay::pack::raw_of(&rc, p, &mut down).expect("합성 자료 읽기");
        let normd = lay::read::normalize_pack(&rc, raw);
        assert!(normd.errors.is_empty(), "{}: 정규화 오류 {:?}", p.name, normd.errors.iter().map(|e| e.msg.clone()).collect::<Vec<_>>());
        let lost: Vec<String> = down.into_iter().chain(normd.warnings.iter().map(|w| w.msg.clone())).filter(|m| m.contains("찾지 못해") || m.contains("빌림") || m.contains("실권")).collect();
        assert!(lost.is_empty(), "{}: 빌림이 풀리지 않았습니다 — {lost:?}", p.name);
        if let Some(pk) = &normd.pack { js::release(pk); }
    }
    let (before, after) = (vec![base.clone()], vec![base.clone(), patch.clone()]);
    let mut cache = Cache::default();
    let pb = cache.get(&before).1.clone();
    let pa = cache.get(&after).1.clone();
    let differs = |k: &str| pb.tracks.get(k).map(|t| &t.print) != pa.tracks.get(k).map(|t| &t.print);
    for k in ["tl-weak", "tl-weak2", "tl-b1", "tl-b2", "tl-b3"] {
        assert!(differs(k), "트랙 {k}의 지문이 바뀌지 않았습니다(빈 시험)");
    }
    assert!(!differs("tl-quiet"), "조용한 줄의 지문이 바뀌었습니다(장면이 어긋남)");
    let t = touch::touched_why(&patch, &after, &o).expect("touched");
    assert!(t.everything.is_none() && !t.keys.contains("tl-quiet"), "닿는 트랙이 조용한 줄까지 넓습니다(좁은 시험이 아님) — {:?}", t.why);
    for k in ["tl-weak", "tl-weak2", "tl-b1", "tl-b2", "tl-b3"] {
        if let Some(w) = t.why.get(k) {
            eprintln!("touched(touch-links-patch) {k}: {w}");
        }
    }
    // 까닭(빠지면 아래 run이 잡는다 — 여기서는 어느 규칙으로 들었나): 실권 상대 둘(id · 이름) · id로 빌린 둘은 규칙 2(이음), 이름으로 빌린 쪽은
    // 출처의 이름이 바뀌어 찾기가 풀리지 않게 되므로 제 지문(찾은 대상의 이름표)이 바뀌어 규칙 1.
    let rule = |k: &str| t.why.get(k).map(|w| w.split(':').next().unwrap_or("").to_string()).unwrap_or_default();
    for (k, want) in [("tl-weak", "규칙 2"), ("tl-weak2", "규칙 2"), ("tl-b1", "규칙 2"), ("tl-b3", "규칙 2"), ("tl-b2", "규칙 1")] {
        assert_eq!(rule(k), want, "트랙 {k}이 든 까닭 — {:?}", t.why.get(k));
    }
    let combos = vec![
        Combo { name: "touch-links + 패치".into(), before: before.clone(), after: after.clone(), change: Change::Add(patch.clone()) },
        Combo { name: "touch-links + 패치 − 그것".into(), before: after, after: before, change: Change::Remove(patch) },
    ];
    run("⑥ 형식 4 이음(실권 · 빌림)", &combos);
}

// ---------------------------------------------------------------- KTL

/// 계획 걸음 1: `touched(KTL, 동아시아+KTL)` = KTL 원본에서 손으로 적은 기대 집합.
/// KTL 1.0.5(감독 PC의 선택 자료 — 자리는 `HT_KTL`)는 트랙 하나(`koreaA` 한국사 — 새 트랙)에 띠 52개만 싣는다(사건 · 패치 · 분류 · 주제 없음 ·
/// 민족 다섯은 동아시아에 같은 id가 있어 동아시아의 것이 이김 · 문서 둘은 제 띠의 것). 이름으로 가리키는 승계 · 소속은 같은 트랙(koreaA)에서 먼저 찾으므로 제 트랙 안에서 풀리고,
/// 풀리지 않는 둘 — 고구려 · 백제의 `succeeds: 부여` — 만 동아시아 `korea` 트랙의 부여로 풀린다(승계의 양 끝 — 부여가 승계국 둘을 얻음).
/// 동아시아 쪽 이름 참조(승계 · 소속 · 사건의 정권)는 모두 동아시아 안에서 같은 트랙으로 풀려 바뀌지 않는다. 그래서 {koreaA, korea}.
/// (판정 R45 전에는 **날짜 칸 이음 번호**(`axis[].strip` — 온 판에 한 번 세는 번호)가 더 닿았다: koreaA는 `order: 1`이라 트랙 차례의 맨 앞에 서고 연호 · 도읍이 있어
/// 뒤 트랙(china · japan · vietnam)의 이음 번호가 모두 밀렸다 — 다섯 트랙 모두. 지문이 이음 번호를 트랙 안 거리로 적고 apply가 저장소 번호를 옮기면서 빠졌다.)
#[test]
fn ktl_touches_its_track_and_the_succession_end() {
    let Some(f) = fixtures().into_iter().find(|f| f.name == "east-asia+ktl") else {
        return; // KTL이 없음 — fixtures()가 알렸다(HT_REQUIRE_KTL=1이면 거기서 멈춤 · 자리는 HT_KTL — 판정 R58 ⑤-5)
    };
    let packs = inputs(&f);
    let t = touch::touched_why(&packs[1], &packs, &opts()).expect("touched");
    // koreaA: 새 트랙 · korea: 부여(고구려 · 백제의 승계 원천 — 승계의 양 끝).
    let want: BTreeSet<String> = ["koreaA", "korea"].into_iter().map(String::from).collect();
    assert_eq!(t.keys, want, "touched(KTL, 동아시아+KTL)이 손으로 적은 기대 집합과 다릅니다 — 까닭: {:?}", t.why);
    // 승계의 양 끝은 규칙 2(이음)로 들어야 한다.
    assert!(t.why["korea"].starts_with("규칙 2") || t.why["korea"].starts_with("규칙 1"), "korea가 승계 이음으로 들지 않았습니다: {}", t.why["korea"]);
    eprintln!("touched(KTL, 동아시아+KTL) = {:?}(트랙 {}개 중 {}개) — {:?}", t.keys, t.all.len(), t.keys.len(), t.why);
}

// ---------------------------------------------------------------- 규칙 판

/// `lay::RULES`가 지금 원본(내보내기 모듈 · 웹 코드)의 지문과 같다 — 원본이 바뀌면 이 검사가 '상수가 낡았다'로 멈춘다(`prototype/scripts/lay-rules.mjs`와 같은 셈).
#[test]
fn rules_constant_is_fresh() {
    // 셈은 tests/common/oracle.rs의 `js_rules` 하나(정답지 머리 `rules`를 견주는 `oracle()`과 같은 값 — 판정 R58 ⑤-4).
    let (web, mods) = common::oracle::js_rule_sources();
    let now = common::oracle::js_rules();
    assert_eq!(lay::RULES, now, "lay::RULES가 낡았습니다(옮긴 원본이 바뀜) — 정답지를 다시 뽑아 Rust를 고친 뒤 `node prototype/scripts/lay-rules.mjs --write`");
    assert!(web.len() >= 6 && mods.len() >= 21, "원본 목록이 너무 짧습니다: 웹 {web:?} · 모듈 {}", mods.len());
    // P4 지문 · meta.rules에 섞는 것은 이 글이 아니라 판 번호(판정 R61 I1 — 배치 출력의 골든은 tests/lay_golden.rs).
    assert_eq!(lay::rules(), format!("lay {}", lay::rules::LAY_RULES_VERSION));
}

// ---------------------------------------------------------------- 걸음 5: 지금 값

/// 걸음 5의 지금 값 — 동아시아 + KTL: `export(All)` · `touched` · `export(Tracks(touched))`의 ms(release · 열 번 가운데값) · 힙 정점 · touched 크기.
/// 재는 것이라 무시해 두고 따로 돌린다: `cargo test --release --locked --test lay_scope -- --ignored --nocapture --test-threads=1 timing`.
#[test]
#[ignore]
fn timing_east_asia_ktl() {
    let Some(f) = fixtures().into_iter().find(|f| f.name == "east-asia+ktl") else {
        eprintln!("건너뜀 — KTL이 없습니다");
        return;
    };
    let packs = inputs(&f);
    let o = opts();
    // 차가운 첫 번 — 이 프로세스의 첫 배치(정규식 첫 짓기 · 달력 표 풀기가 든다 — 판정 R61: 따로 적는다). 따로 돌려야 차갑다(`--test-threads=1 timing`).
    let t0 = std::time::Instant::now();
    let ((), mem_cold) = peak_of(|| { lay::export(&packs, &o).unwrap(); });
    let ms_cold = t0.elapsed().as_secs_f64() * 1000.0;
    let median = |mut xs: Vec<f64>| -> f64 { xs.sort_by(|a, b| a.partial_cmp(b).unwrap()); (xs[4] + xs[5]) / 2.0 };
    let time = |f: &dyn Fn()| -> (f64, isize) {
        let mut ms = Vec::new();
        let mut peak = 0;
        for _ in 0..10 {
            let t0 = std::time::Instant::now();
            let ((), p) = peak_of(f);
            ms.push(t0.elapsed().as_secs_f64() * 1000.0);
            peak = peak.max(p);
        }
        (median(ms), peak)
    };
    let s = lay::touched(&packs[1], &packs, &o).expect("touched");
    let all_keys = patch::prints(&export(&packs, "통째")).unwrap().order.len();
    let (ms_all, mem_all) = time(&|| { lay::export(&packs, &o).unwrap(); });
    let (ms_touch, mem_touch) = time(&|| { lay::touched(&packs[1], &packs, &o).unwrap(); });
    let scoped = Opts { scope: Scope::Tracks(s.clone()), ..o.clone() };
    let (ms_part, mem_part) = time(&|| { lay::export(&packs, &scoped).unwrap(); });
    // 실제 틈의 차례 그대로 — 닿는 트랙(touched_scope)이 '뒤' 조합의 준비를 남기고 곧이은 범위 내보내기가 다시 쓴다(과제 16b).
    let (ms_flow, mem_flow) = time(&|| {
        let sc = touch::touched_scope(&packs[..1], &packs, &o).unwrap();
        lay::export(&packs, &Opts { scope: sc, ..o.clone() }).unwrap();
    });
    let mb = |b: isize| b as f64 / 1_048_576.0;
    eprintln!("걸음 5(빌드 설정은 돌린 쪽이 적는다): 동아시아 + KTL · touched {}/{all_keys} 트랙 {s:?}", s.len());
    eprintln!("  차가운 첫 export(All)    {ms_cold:.1}ms · 힙 정점 {:.1}MB", mb(mem_cold));
    eprintln!("  export(All)              {ms_all:.1}ms · 힙 정점 {:.1}MB", mb(mem_all));
    eprintln!("  touched(KTL, 동아시아+KTL) {ms_touch:.1}ms · 힙 정점 {:.1}MB", mb(mem_touch));
    eprintln!("  export(Tracks(touched))  {ms_part:.1}ms · 힙 정점 {:.1}MB", mb(mem_part));
    eprintln!("  touched_scope + export(범위 · 준비 다시 씀) {ms_flow:.1}ms · 힙 정점 {:.1}MB", mb(mem_flow));
}

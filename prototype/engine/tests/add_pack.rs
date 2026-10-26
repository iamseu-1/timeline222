//! 한 벌 P4 과제 9 — `add_pack` · `remove_pack`(엔진 하나로 DLC 넣고 빼기): 어떤 차례로 넣고 빼도 그 조합을 통째로 지은 것과 같다(설계 3-4 '같음의 약속').
//!
//! 배치를 내는 쪽은 틈(`packs::Layouter`)이다(판정 R35). 두 틈으로 잰다([`Side`]):
//! - **Node 통째 배치**(`common::node` — 정답지와 같은 길 · 같은 시각 · 시간대): 닿는 트랙 S를 답할 수 있어 흐름 전부(원본 + 새 파일 → 판 대조 → S →
//!   하위 배치 → `apply(Covers::Part)` · 넓히기 · 보관함 · 다른 저장소)를 지난다. 견줄 '통째 짓기'도 같은 Node 배치를 짓기 ②(`legacy::build_store`)로.
//! - **실제 틈**(`packs::RustLayouter` — P3 모듈 스물이 다 옮겨진 뒤 · 고침 1회차 · P3 과제 16b로 닿는 트랙(`lay::touch`)과 하위 배치를 답함): 통째 짓기도
//!   Rust 배치 + 짓기 ②(저장소마다 달력 표 — 판정 R36 · 검사는 잘린 표 `calendar_slice`). 시간은 `archive-tool add-pack`으로 따로 잰다(과제 16b 보고).
//!
//! 장면:
//! - 무작위 열 판(씨앗 고정 — 판마다 `#[test]` 하나라 나란히 돈다): 합성 세계(`synth.json` + 패치 둘 + 패치의 높은 판) 일곱 판 · 등불 연대기(+ `d7-test` ·
//!   `sphere-test`) 한 판(나머지 두 판은 긴 검사 — `#[ignore]`). 넣기 · 빼기(원본 버림 · 보관함에 남김) · 보관함에서 다시 넣기 · 높은 판으로 바꿔 넣기를
//!   섞는다. 닿는 트랙을 답하는 법도 판마다 바꾼다(지문이 바뀐 트랙만 · 거기에 무작위 트랙을 더 · 모름). 등불은 글이 많아 걸음마다 meta · 사건 차례 ·
//!   항목 기록 · 트랙 지문만 보고 canon(성긴 단계)은 판 끝에 한 번. 같은 조합의 통째 짓기 저장소 · canon은 판 안에서 한 번만 짓는다([`Fulls`]).
//!   긴 검사 돌리기: `cargo test --release --locked --test add_pack -- --ignored lantern --nocapture`(등불 둘째 · 셋째 판 · 실제 틈 등불 세 걸음).
//! - 실패하면 그대로(깨진 파일 · 낮은 판 · 없는 id · 기본 DLC 빼기 · 배치 실패 · 걸음마다 실패 주입) — 파일 SHA-256.
//! - 이틀 뒤에 넣어도 저장소의 '오늘'(`meta.now`)을 쓴다 — 진행 중 띠가 있는 트랙은 다시 쓰지 않는다(오늘로 셈하면 다시 쓴다).
//! - 옛 DLC 묶음(형식 3 · 4 · 동아시아 기본팩 사본 · KoreanTimeLine v1.0.5(감독 PC에 있으면)) — 그대로 넣어 통째 짓기와 같다. 실자료는 한 판만.
//! - Node 길로 지은 저장소(이 계획 전 · 뒤 · Node apply로 고친 것)에 이어서 돈다 — 이 과제 전 저장소는 첫 번에 모든 트랙을 한 번 다시 씀.
//! - 다른 저장소의 원본으로 넣기(판정 R34 D — 이미 든 것은 건너뜀) · 보관함 · 원본 없이 든 DLC(메이커 `.htlayout`)를 채우거나 빼기 · 같은 판의 다른 바이트.
//! - 달력 표 없는 저장소는 실제 틈으로 넣고 빼지 않는다(판정 R36 — `code` calendar).
//! - 하위 배치를 그대로 넣는 길(`Covers::Part`)을 장면(`plans.rs`)으로 — Node 없이.
mod common;
use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::lay::{Opts, PackIn, Scope};
use archive_engine::legacy::{build_store, import_layout_value, iso_at, seal_dlc};
use archive_engine::packs::{add_pack, kept_packs, remove_pack, AddOrder, Layouter, PackReport, RemoveOrder, RustLayouter};
use archive_engine::patch::{apply, prints, sub_plan, ApplyIn, Covers, Refusal, Widen};
use archive_engine::write::{set_fail_point, write};
use common::node::{NodeLayouter, Touch};
use common::oracle::{calendar_slice, ORACLE_NOW_MS};
use common::same::{light_canon, meta, pairs, quick_q, same_but_canon, same_light, same_store, search_terms};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};

const T: f64 = ORACLE_NOW_MS;
const TZ: i32 = 540;
const DAY_MS: f64 = 86_400_000.0;

/// 저장소 뿌리.
fn root() -> PathBuf {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    std::fs::canonicalize(manifest).unwrap_or_else(|_| manifest.to_path_buf()).parent().and_then(Path::parent).unwrap().to_path_buf()
}

/// 검사의 DLC 하나 — 글자 id · 원본(.htpack 바이트) · 그 파일.
#[derive(Clone, Debug)]
struct Dlc {
    key: String,
    bytes: Vec<u8>,
}

impl Dlc {
    fn input(&self) -> PackIn {
        PackIn { name: format!("{}.htpack", self.key), bytes: self.bytes.clone() }
    }
    /// 이 DLC의 파일(임시 폴더 — 같은 바이트는 같은 이름).
    fn file(&self) -> PathBuf {
        // 나란히 도는 검사가 같은 파일을 쓰다 만 것을 읽지 않게 — 프로세스 안에서는 자물쇠로 하나씩, 쓰기는 제 이름으로 다 쓴 뒤 옮긴다(옮기기는 잠깐 다시 해 봄).
        static FILES: std::sync::Mutex<()> = std::sync::Mutex::new(());
        let _held = FILES.lock().unwrap_or_else(|e| e.into_inner());
        let dir = std::env::temp_dir().join(format!("archive-correct-{}-ap-files", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join(format!("{}-{}.htpack", self.key, &sha(&self.bytes)[..10]));
        if !file.exists() {
            let part = dir.join(format!("{}.part", file.file_name().unwrap().to_string_lossy()));
            std::fs::write(&part, &self.bytes).unwrap();
            let mut tries = 0;
            while let Err(e) = std::fs::rename(&part, &file) {
                tries += 1;
                assert!(tries < 20, "DLC 파일을 옮기지 못했습니다({}): {e}", file.display());
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
        file
    }
}

fn sha(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    format!("{:x}", Sha256::digest(bytes))
}

/// 파일(저장소 뿌리에서의 자리)의 DLC — `.json`은 본문 그대로 싼다(`seal_dlc`). `edits`는 본문 글 고치기(판 · 이름 — 같은 글이 꼭 하나여야 함).
fn dlc(rel: &str, edits: &[(&str, &str)]) -> Dlc {
    let path = root().join(rel);
    let mut bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    if !edits.is_empty() {
        assert!(rel.ends_with(".json"), "고칠 수 있는 것은 JSON 본문뿐");
        let mut text = String::from_utf8(bytes).unwrap();
        for (from, to) in edits {
            assert_eq!(text.matches(from).count(), 1, "{rel}: «{from}»가 하나여야 함");
            text = text.replacen(from, to, 1);
        }
        bytes = text.into_bytes();
    }
    let bytes = if rel.ends_with(".json") { seal_dlc(&bytes) } else { bytes };
    let raw = archive_engine::htpack_raw(&bytes).unwrap();
    Dlc { key: raw["id"].as_str().unwrap().to_owned(), bytes }
}

const FIX: &str = "prototype/fixtures/oracle";

fn synth() -> Dlc { dlc(&format!("{FIX}/synth.json"), &[]) }
fn patch1() -> Dlc { dlc(&format!("{FIX}/synth-patch.json"), &[]) }
fn patch2() -> Dlc { dlc(&format!("{FIX}/synth-patch2.json"), &[]) }
/// 합성 학설의 높은 판 — 판 1.1.0 · 고친 사건 제목이 달라진다.
fn patch1_v11() -> Dlc { dlc(&format!("{FIX}/synth-patch.json"), &[("\"version\": \"1.0.0\"", "\"version\": \"1.1.0\""), ("\"고친 가상 사건\"", "\"새로 고친 가상 사건\"")]) }
/// 합성 학설의 낮은 판(0.9.0).
fn patch1_v09() -> Dlc { dlc(&format!("{FIX}/synth-patch.json"), &[("\"version\": \"1.0.0\"", "\"version\": \"0.9.0\"")]) }
/// 합성 학설을 판을 올리지 않고 고친 작업본(같은 판 · 다른 바이트).
fn patch1_same_version() -> Dlc { dlc(&format!("{FIX}/synth-patch.json"), &[("\"고친 가상 사건\"", "\"판을 안 올리고 고친 사건\"")]) }
fn lantern() -> Dlc { dlc("samples/sample-lantern.json", &[]) }

/// 배치를 내는 쪽 — 검사의 Node 틈 또는 실제 틈(Rust).
enum Side {
    Node(NodeLayouter),
    Rust,
}

impl Side {
    fn node(tag: &str, touch: Touch) -> Self {
        Side::Node(NodeLayouter::new(tag, touch))
    }
    fn lay(&self) -> &dyn Layouter {
        match self {
            Side::Node(n) => n,
            Side::Rust => &RustLayouter,
        }
    }
    /// 그 조합 · 날의 통째 배치(Rust는 잘린 달력 표로 — 짓기가 저장소에 넣는 표와 같은 것).
    fn plan(&self, combo: &[Dlc], now: f64) -> Value {
        let inputs: Vec<PackIn> = combo.iter().map(Dlc::input).collect();
        match self {
            Side::Node(n) => n.full(&inputs, now, TZ),
            Side::Rust => {
                let opts = Opts { now_ms: now, tz_min: TZ, upto: None, scope: Scope::All, calendar: Some(calendar_slice()) };
                archive_engine::lay::export(&inputs, &opts).unwrap_or_else(|e| panic!("Rust 배치: {e}"))
            }
        }
    }
    fn prefetch(&self, combos: &[Vec<Dlc>], now: f64) {
        if let Side::Node(n) = self {
            n.prefetch(&combos.iter().map(|c| c.iter().map(Dlc::input).collect()).collect::<Vec<_>>(), now, TZ);
        }
    }
    fn node_ref(&self) -> &NodeLayouter {
        match self {
            Side::Node(n) => n,
            Side::Rust => panic!("Node 틈이 아닙니다"),
        }
    }
}

/// 그 조합을 통째로 지은 저장소(배치 → 짓기 ② · 지은 날 `now` · 잘린 달력 표).
fn full(side: &Side, combo: &[Dlc], now: f64, tag: &str) -> PathBuf {
    let plan = side.plan(combo, now);
    let path = common::scratch(tag);
    let originals: Vec<(String, Vec<u8>)> = combo.iter().map(|d| (d.key.clone(), d.bytes.clone())).collect();
    build_store(&plan, &originals, &path, &iso_at(now, TZ), &calendar_slice()).unwrap_or_else(|e| panic!("{tag}: 통째 짓기 — {e}"));
    path
}

/// 한 판 안에서 조합마다 통째 짓기 저장소 · canon을 한 번만(같은 조합이 다시 나오면 다시 짓지 않는다).
struct Fulls<'s> {
    side: &'s Side,
    tag: String,
    stores: RefCell<HashMap<String, PathBuf>>,
    canons: RefCell<HashMap<String, Value>>,
}

impl<'s> Fulls<'s> {
    fn new(side: &'s Side, tag: &str) -> Self {
        Self { side, tag: tag.to_owned(), stores: RefCell::new(HashMap::new()), canons: RefCell::new(HashMap::new()) }
    }
    fn key(combo: &[Dlc]) -> String {
        combo.iter().map(|d| sha(&d.bytes)).collect::<Vec<_>>().join("|")
    }
    fn store(&self, combo: &[Dlc]) -> PathBuf {
        let key = Self::key(combo);
        if let Some(p) = self.stores.borrow().get(&key) {
            return p.clone();
        }
        let n = self.stores.borrow().len();
        let path = full(self.side, combo, T, &format!("{}-full{n}", self.tag));
        self.stores.borrow_mut().insert(key, path.clone());
        path
    }
    fn canon(&self, combo: &[Dlc], opts: &CanonOpts) -> Value {
        let key = format!("{}#{:?}#{}#{}", Self::key(combo), opts.levels, opts.max_x, opts.queries);
        if let Some(c) = self.canons.borrow().get(&key) {
            return c.clone();
        }
        let c = canon_store(&self.store(combo), opts).unwrap();
        self.canons.borrow_mut().insert(key, c.clone());
        c
    }
}

fn add(path: &Path, files: &[&Dlc], lay: &dyn Layouter) -> archive_engine::Result<PackReport> {
    let order = AddOrder { files: files.iter().map(|d| d.file()).collect(), ..AddOrder::default() };
    write(path, |tx| add_pack(tx, &order, lay))
}

fn add_order(path: &Path, order: &AddOrder, lay: &dyn Layouter) -> archive_engine::Result<PackReport> {
    write(path, |tx| add_pack(tx, order, lay))
}

fn remove(path: &Path, id: &str, delete: bool, lay: &dyn Layouter) -> archive_engine::Result<PackReport> {
    write(path, |tx| remove_pack(tx, &RemoveOrder { id: id.to_owned(), delete }, lay))
}

#[allow(clippy::borrowed_box)]
fn code(e: &Box<dyn std::error::Error + Send + Sync>) -> Option<&'static str> {
    e.downcast_ref::<Refusal>().map(|r| r.code)
}

/// 무작위(씨앗 고정 — LCG).
struct Rng(u64);
impl Rng {
    fn next(&mut self, n: usize) -> usize {
        self.0 = self.0.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
        ((self.0 >> 33) % n as u64) as usize
    }
}

/// 걸음 하나.
#[derive(Clone, Debug)]
enum Op {
    /// 파일로 넣기(새 DLC · 높은 판).
    File(Dlc),
    /// 보관함에서 다시 넣기.
    Kept(String),
    Remove(String, bool),
}

/// 무작위 판 하나를 미리 셈한다 — (걸음, 걸음 뒤 조합). 세계: 기본 DLC · 넣을 수 있는 DLC · (DLC 열쇠 → 높은 판).
fn walk(rng: &mut Rng, base: &Dlc, extras: &[Dlc], upgrades: &[Dlc], steps: usize) -> (Vec<Dlc>, Vec<(Op, Vec<Dlc>)>) {
    let mut now: Vec<Dlc> = vec![base.clone()];
    // 처음 조합: 넣을 수 있는 것 가운데 무작위 몇 개.
    for d in extras {
        if rng.next(2) == 0 {
            now.push(d.clone());
        }
    }
    let start = now.clone();
    let mut kept: Vec<Dlc> = Vec::new();
    let mut out = Vec::new();
    while out.len() < steps {
        let op = match rng.next(4) {
            0 | 1 => {
                // 넣기 — 빠진 것(보관함에 있으면 반쯤은 보관함에서).
                let missing: Vec<&Dlc> = extras.iter().filter(|d| !now.iter().any(|n| n.key == d.key)).collect();
                if missing.is_empty() { continue; }
                let d = missing[rng.next(missing.len())].clone();
                if let Some(k) = kept.iter().position(|k| k.key == d.key).filter(|_| rng.next(2) == 0) {
                    let k = kept.remove(k);
                    now.push(k.clone());
                    Op::Kept(k.key)
                } else {
                    kept.retain(|k| k.key != d.key);
                    now.push(d.clone());
                    Op::File(d)
                }
            }
            2 => {
                let held: Vec<usize> = (1..now.len()).collect();
                if held.is_empty() { continue; }
                let at = held[rng.next(held.len())];
                let gone = now.remove(at);
                let delete = rng.next(2) == 0;
                kept.retain(|k| k.key != gone.key);
                if !delete {
                    kept.push(gone.clone());
                }
                Op::Remove(gone.key, delete)
            }
            _ => {
                // 높은 판으로 바꿔 넣기(그 DLC가 들어 있고 아직 낮은 판일 때).
                let Some(up) = upgrades.iter().find(|u| now.iter().any(|n| n.key == u.key && n.bytes != u.bytes)) else { continue };
                let at = now.iter().position(|n| n.key == up.key).unwrap();
                now[at] = up.clone();
                kept.retain(|k| k.key != up.key);
                Op::File(up.clone())
            }
        };
        out.push((op, now.clone()));
    }
    (start, out)
}

/// 무작위 판 하나를 걷는다 — 걸음마다 통째 짓기와 같은지. `light`(등불)면 걸음마다 canon 말고 나머지(meta · 사건 차례 · 항목 기록 · 트랙 지문)만 보고
/// canon(성긴 단계)은 판 끝에 한 번. 답: (걸음, 배치 수, 좁힌 배치를 지난 걸음 수).
fn run_walk(tag: &str, seed: u64, side: &Side, base: &Dlc, extras: &[Dlc], upgrades: &[Dlc], steps: usize, light: bool) -> (usize, usize, usize) {
    let mut rng = Rng(seed);
    let (start, ops) = walk(&mut rng, base, extras, upgrades, steps);
    let mut combos = vec![start.clone()];
    combos.extend(ops.iter().map(|(_, c)| c.clone()));
    side.prefetch(&combos, T);
    let fulls = Fulls::new(side, tag);
    let path = common::scratch(&format!("{tag}-flow"));
    std::fs::copy(fulls.store(&start), &path).unwrap();
    let (mut layouts, mut narrow) = (0, 0);
    for (i, (op, combo)) in ops.iter().enumerate() {
        let report = match op {
            Op::File(d) => add(&path, &[d], side.lay()),
            Op::Kept(id) => add_order(&path, &AddOrder { ids: vec![id.clone()], ..AddOrder::default() }, side.lay()),
            Op::Remove(id, delete) => remove(&path, id, *delete, side.lay()),
        }.unwrap_or_else(|e| panic!("{tag} 걸음 {i} {op:?}: {e}"));
        let want_keys: Vec<String> = combo.iter().map(|d| d.key.clone()).collect();
        assert_eq!(report.packs, want_keys, "{tag} 걸음 {i}: 새 조합의 차례");
        layouts += report.layouts;
        narrow += usize::from(report.scope.is_some());
        let want = fulls.store(combo);
        let what = format!("{tag} 걸음 {i} {op:?} → {want_keys:?}");
        if light {
            same_light(&path, &want, &what, &[]);
        } else {
            assert!(canon_store(&path, &quick_q()).unwrap() == fulls.canon(combo, &quick_q()), "{what}: canon이 통째 짓기와 다릅니다");
            same_but_canon(&path, &want, &what, &[]);
        }
    }
    if light {
        let last = &ops.last().unwrap().1;
        assert!(canon_store(&path, &light_canon()).unwrap() == fulls.canon(last, &light_canon()), "{tag} 판 끝: canon(성긴 단계)이 통째 짓기와 다릅니다");
    }
    (ops.len(), layouts, narrow)
}

/// 합성 세계 무작위 판 하나(패치 DLC는 제 트랙이 없고 남의 트랙(합성 세계의 띠 · 사건)을 고친다: 닿는 트랙이 곧 고친 트랙이다).
fn synth_round(rust: bool, round: u64) {
    let (base, extras, upgrades) = (synth(), vec![patch1(), patch2()], vec![patch1_v11()]);
    let touch = match round % 3 { 0 => Touch::Exact, 1 => Touch::Extra(round * 7919), _ => Touch::All };
    let side = if rust { Side::Rust } else { Side::node(&format!("ap-syn{round}"), touch) };
    let tag = format!("ap-{}syn{round}", if rust { "r" } else { "" });
    let (steps, layouts, narrow) = run_walk(&tag, 0x5eed_0000 + round, &side, &base, &extras, &upgrades, 4, false);
    eprintln!("{tag}({}): 걸음 {steps} · 배치 {layouts}번(넓히기 {}번) · 좁힌 배치 {narrow}걸음", if rust { "실제 틈".to_string() } else { format!("{touch:?}") }, layouts - steps);
    if rust {
        // 실제 틈(과제 16b — `lay::touch`)은 모든 트랙이라 답하는 걸음(분류 차례 · 간지 · 트랙 차례가 바뀜 · 기본 DLC)만 넓다 — 판마다 좁힌 걸음이 있어야 한다.
        assert!(narrow > 0 && narrow <= steps, "{tag}: 실제 틈이 좁힌 배치(Covers::Part)를 지나지 않았습니다({narrow}/{steps})");
    } else {
        let narrowed = !matches!(touch, Touch::All);
        assert_eq!(narrow, if narrowed { steps } else { 0 }, "{tag}: 좁힌 배치(Covers::Part)를 지난 걸음 수");
    }
}

/// 등불 연대기 무작위 판 하나(형식 3 견본 위에 시험 DLC 둘 — 제 트랙 · 문화권).
fn lantern_round(rust: bool, round: u64, steps: usize) {
    let (base, extras) = (lantern(), vec![dlc(&format!("{FIX}/d7-test.htpack"), &[]), dlc(&format!("{FIX}/sphere-test.htpack"), &[])]);
    let touch = match round { 0 => Touch::Exact, 1 => Touch::Extra(round * 104_729), _ => Touch::All };
    let side = if rust { Side::Rust } else { Side::node(&format!("ap-lan{round}"), touch) };
    let tag = format!("ap-{}lan{round}", if rust { "r" } else { "" });
    let tag = if steps == 3 { tag } else { format!("{tag}-{steps}걸음") };
    let (steps, layouts, narrow) = run_walk(&tag, 0x1a47_0000 + round, &side, &base, &extras, &[], steps, true);
    eprintln!("{tag}: 걸음 {steps} · 배치 {layouts}번 · 좁힌 배치 {narrow}걸음");
}

#[test] fn synth_walk_0() { let _t = common::clock("synth_walk_0"); synth_round(false, 0) }
#[test] fn synth_walk_1() { let _t = common::clock("synth_walk_1"); synth_round(false, 1) }
#[test] fn synth_walk_2() { let _t = common::clock("synth_walk_2"); synth_round(false, 2) }
#[test] fn synth_walk_3() { let _t = common::clock("synth_walk_3"); synth_round(false, 3) }
#[test] fn synth_walk_4() { let _t = common::clock("synth_walk_4"); synth_round(false, 4) }
#[test] fn synth_walk_5() { let _t = common::clock("synth_walk_5"); synth_round(false, 5) }
#[test] fn synth_walk_6() { let _t = common::clock("synth_walk_6"); synth_round(false, 6) }
#[test] fn lantern_walk_0() { let _t = common::clock("lantern_walk_0"); lantern_round(false, 0, 3) }
#[test]
#[ignore = "긴 검사 — 등불 둘째 판(cargo test --release --locked --test add_pack -- --ignored lantern --nocapture)"]
fn lantern_walk_1() { let _t = common::clock("lantern_walk_1"); lantern_round(false, 1, 3) }
#[test]
#[ignore = "긴 검사 — 등불 셋째 판(cargo test --release --locked --test add_pack -- --ignored lantern --nocapture)"]
fn lantern_walk_2() { let _t = common::clock("lantern_walk_2"); lantern_round(false, 2, 3) }

// 실제 틈(Rust 배치 — 닿는 트랙은 `lay::touch` · 하위 배치는 `lay::export(Scope::Tracks)` — 과제 16b)으로 같은 판들. 등불은 기본에서 한 걸음(세 걸음 본은 긴 검사).
// 좁힌 배치 수는 실제 틈에서 판마다 하나 이상이어야 한다(`synth_round`).
#[test] fn rust_synth_walk_0() { let _t = common::clock("rust_synth_walk_0"); synth_round(true, 0) }
#[test] fn rust_synth_walk_1() { let _t = common::clock("rust_synth_walk_1"); synth_round(true, 1) }
#[test] fn rust_synth_walk_2() { let _t = common::clock("rust_synth_walk_2"); synth_round(true, 2) }
#[test] fn rust_synth_walk_3() { let _t = common::clock("rust_synth_walk_3"); synth_round(true, 3) }
#[test] fn rust_synth_walk_4() { let _t = common::clock("rust_synth_walk_4"); synth_round(true, 4) }
#[test] fn rust_synth_walk_5() { let _t = common::clock("rust_synth_walk_5"); synth_round(true, 5) }
#[test] fn rust_synth_walk_6() { let _t = common::clock("rust_synth_walk_6"); synth_round(true, 6) }
#[test] fn rust_lantern_walk_0() { let _t = common::clock("rust_lantern_walk_0"); lantern_round(true, 0, 1) }
#[test]
#[ignore = "긴 검사 — 실제 틈 등불 세 걸음(cargo test --release --locked --test add_pack -- --ignored lantern --nocapture)"]
fn rust_lantern_walk_long() { let _t = common::clock("rust_lantern_walk_long"); lantern_round(true, 0, 3) }

#[test]
fn the_walks_mix_every_kind_of_step() {
    // 고침 2회차(검토 ③): 씨앗들이 정말로 넣기(새 DLC) · 높은 판으로 바꿔 넣기 · 보관함에서 다시 넣기 · 빼며 보관 · 빼며 버림을 섞는지 센다(배치 없이 걸음만 셈).
    let _t = common::clock("the_walks_mix_every_kind_of_step");
    let count = |seeds: &[u64], base: &Dlc, extras: &[Dlc], upgrades: &[Dlc], steps: usize| -> [usize; 5] {
        let mut n = [0; 5];
        for seed in seeds {
            let (_, ops) = walk(&mut Rng(*seed), base, extras, upgrades, steps);
            for (op, _) in ops {
                let i = match op {
                    Op::File(d) if upgrades.iter().any(|u| u.bytes == d.bytes) => 1,
                    Op::File(_) => 0,
                    Op::Kept(_) => 2,
                    Op::Remove(_, false) => 3,
                    Op::Remove(_, true) => 4,
                };
                n[i] += 1;
            }
        }
        n
    };
    let syn = count(&(0..7).map(|r| 0x5eed_0000 + r).collect::<Vec<_>>(), &synth(), &[patch1(), patch2()], &[patch1_v11()], 4);
    eprintln!("합성 일곱 판의 걸음: 새 DLC {} · 높은 판 {} · 보관함에서 {} · 빼며 보관 {} · 빼며 버림 {}", syn[0], syn[1], syn[2], syn[3], syn[4]);
    assert!(syn.iter().all(|n| *n > 0), "합성 판이 걸음 갈래를 다 섞지 않습니다: {syn:?}");
    let lan = count(&[0x1a47_0000], &lantern(), &[dlc(&format!("{FIX}/d7-test.htpack"), &[]), dlc(&format!("{FIX}/sphere-test.htpack"), &[])], &[], 3);
    eprintln!("등불 기본 판의 걸음: 새 DLC {} · 보관함에서 {} · 빼며 보관 {} · 빼며 버림 {}", lan[0], lan[2], lan[3], lan[4]);
    assert!(lan[0] + lan[2] > 0 && lan[3] + lan[4] > 0, "등불 기본 판은 넣기와 빼기를 다 지나야 합니다: {lan:?}");
}

#[test]
fn the_real_layouter_cuts_the_part_like_sub_plan() {
    // 고침 2회차(검토 ③): 실제 틈의 `Scope::Tracks(S)` = `sub_plan(export(All), S ∩ 배치의 트랙)` — 배치에 없는 판 열쇠는 거른다(P3-16의 약속과 같은 값 ·
    // 16b부터 실제 틈은 `lay::export(Scope::Tracks)` 그대로).
    let _t = common::clock("the_real_layouter_cuts_the_part_like_sub_plan");
    let inputs: Vec<PackIn> = [synth(), patch1()].iter().map(Dlc::input).collect();
    let all = Opts { now_ms: T, tz_min: TZ, upto: None, scope: Scope::All, calendar: Some(calendar_slice()) };
    let whole = RustLayouter.export(&inputs, &all).unwrap();
    let real = archive_engine::patch::track_keys(&whole)[0].clone();
    let s: BTreeSet<String> = [real.clone(), "board:__board:view:없는-판".to_string()].into_iter().collect();
    let part = RustLayouter.export(&inputs, &Opts { scope: Scope::Tracks(s), ..all }).unwrap();
    assert_eq!(part, sub_plan(&whole, &[real].into_iter().collect()).unwrap());
}

#[test]
fn failures_leave_the_store_as_it_was() {
    let _t = common::clock("failures_leave_the_store_as_it_was");
    // 넣기 · 빼기가 어디서 실패해도 저장소 파일이 바이트까지 그대로(한 쓰기 거래).
    let side = Side::node("ap-fail", Touch::Exact);
    let node = side.lay();
    let path = full(&side, &[synth(), patch1()], T, "ap-fail");
    let before = common::sha256_file(&path);
    let same = |what: &str| assert_eq!(common::sha256_file(&path), before, "{what}: 저장소가 바뀜");
    // 깨진 파일 · DLC가 아닌 파일
    let broken = std::env::temp_dir().join(format!("archive-correct-{}-ap-broken.htpack", std::process::id()));
    std::fs::write(&broken, b"HTPACK\r\n\x02\x01\x01\x00garbage").unwrap();
    let err = add_order(&path, &AddOrder { files: vec![broken.clone()], ..AddOrder::default() }, node).unwrap_err().to_string();
    assert!(err.contains("전용 팩"), "{err}");
    same("깨진 파일");
    // 낮은 판(판정 R15) — code version
    let err = add(&path, &[&patch1_v09()], node).unwrap_err();
    assert_eq!(code(&err), Some("version"), "{err}");
    assert!(err.to_string().contains("판이 저장소보다 낮습니다"), "{err}");
    same("낮은 판");
    // 같은 id를 둘
    let err = add(&path, &[&patch2(), &patch2()], node).unwrap_err().to_string();
    assert!(err.contains("둘 받았습니다"), "{err}");
    same("같은 id 둘");
    // 보관함에 없는 id · 없는 DLC 빼기 · 기본 DLC 빼기
    assert!(add_order(&path, &AddOrder { ids: vec!["없는-dlc".into()], ..AddOrder::default() }, node).unwrap_err().to_string().contains("없는-dlc"));
    assert!(remove(&path, "없는-dlc", true, node).unwrap_err().to_string().contains("지금 저장소에 없습니다"));
    assert!(remove(&path, "synth-world", true, node).unwrap_err().to_string().contains("기본 DLC"));
    same("없는 id · 기본 DLC");
    // 배치(틈)가 실패
    struct Broken;
    impl Layouter for Broken {
        fn export(&self, _: &[PackIn], _: &Opts) -> archive_engine::Result<Value> { Err("배치 실패(검사)".into()) }
        fn touched(&self, _: &[PackIn], _: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> {
            Ok(Scope::All)
        }
    }
    assert!(add(&path, &[&patch2()], &Broken).unwrap_err().to_string().contains("배치 실패"));
    same("배치 실패");
    // apply의 걸음마다 실패 주입(넣기 · 빼기 모두)
    for at in ["choose", "packs", "delete", "insert", "relink", "globals", "entities", "summaries", "range", "order", "renumber", "names", "prints", "meta", "verify"] {
        set_fail_point(Some(at));
        let got = add(&path, &[&patch2()], node);
        let gone = remove(&path, "synth-patch", false, node);
        set_fail_point(None);
        assert_eq!(got.unwrap_err().to_string(), format!("실패 주입: {at}"));
        assert_eq!(gone.unwrap_err().to_string(), format!("실패 주입: {at}"));
        same(at);
    }
    // 그 뒤 곧바로 넣으면 받는다.
    let r = add(&path, &[&patch2()], node).unwrap();
    let want = full(&side, &[synth(), patch1(), patch2()], T, "ap-fail-full");
    same_store(&path, &want, "실패 뒤 넣기", &[]);
    assert!(r.apply.rows_after > 0);
}

#[test]
fn two_days_later_the_store_day_is_used() {
    let _t = common::clock("two_days_later_the_store_day_is_used");
    // 합성 학설(패치)이 띠 하나를 '진행 중'으로 만든다(끝 = 오늘). 그 저장소에 둘째 학설을 이틀 뒤에 넣어도 흐름은 저장소의 '오늘'(meta.now)로 배치하므로
    // 둘째 학설이 닿는 트랙만 바뀌고 진행 중 띠의 트랙은 다시 쓰지 않는다 — 오늘(이틀 뒤)로 다시 셈한 Node 배치를 apply하면 그 트랙도 바뀐다(대조).
    let side = Side::node("ap-day", Touch::Exact);
    let node = side.node_ref();
    let start = [synth(), patch1()];
    let path = full(&side, &start, T, "ap-day");
    let r = add(&path, &[&patch2()], node).unwrap();
    assert_eq!(node.last_now.get(), T, "배치가 받은 '오늘'은 저장소의 지은 날");
    assert_eq!(meta(&path)["now"], iso_at(T, TZ), "지은 날은 그대로");
    let want = full(&side, &[synth(), patch1(), patch2()], T, "ap-day-full");
    same_store(&path, &want, "이틀 뒤 넣기(저장소의 오늘)", &[]);
    // 대조: 같은 조합을 이틀 뒤 오늘로 배치해 모두 덮는 apply.
    let later = full(&side, &start, T, "ap-day-later");
    let plan = side.plan(&[synth(), patch1(), patch2()], T + 2.0 * DAY_MS);
    let o = vec![(patch2().key, patch2().bytes)];
    let today = write(&later, |tx| apply(tx, &ApplyIn { plan: &plan, originals: &o, covers: Covers::All, remove: &[] })).unwrap();
    let mine: BTreeSet<String> = r.apply.rewrote.iter().chain(&r.apply.added).cloned().collect();
    let theirs: BTreeSet<String> = today.rewrote.iter().chain(&today.added).cloned().collect();
    let ongoing: BTreeSet<String> = theirs.difference(&mine).cloned().collect();
    assert!(mine.is_subset(&theirs) && !ongoing.is_empty(), "오늘로 셈하면 진행 중 띠의 트랙도 바뀌어야 함 — 저장소의 날 {mine:?} · 오늘 {theirs:?}");
    eprintln!("이틀 뒤: 저장소의 날로 다시 쓴 트랙 {mine:?} · 오늘로 셈하면 더 바뀌는 트랙(진행 중 띠) {ongoing:?}");
}

/// 감독의 실자료(KoreanTimeLine v1.0.5) — 파일이 있을 때만. 자리는 환경 변수 `HT_KTL`(없으면 감독 PC의 자리 — common::oracle::ktl_path) ·
/// `HT_REQUIRE_KTL=1`이면 없을 때 건너뛰지 않고 멈춘다(판정 R58 ⑤-5).
fn ktl() -> Option<Dlc> {
    let at = common::oracle::ktl_path();
    let file = at.as_path();
    if !file.exists() {
        common::oracle::ktl_missing("add_pack의 KTL 걸음");
        return None;
    }
    Some(Dlc { key: archive_engine::read_htpack(file).unwrap()["id"].as_str().unwrap().to_owned(), bytes: std::fs::read(file).unwrap() })
}

/// 옛 DLC의 약속 1: 지금 메이커가 저장한 꼴 그대로(형식 3) · 형식 4 · 동아시아 기본팩 사본(같은 id의 형식 4 파일로 바꿔 넣기 — 같은 판 · 다른 바이트)을
/// add_pack으로 넣으면 받아져 통째 짓기와 같다. KoreanTimeLine v1.0.5(감독의 실자료)는 파일이 있으면 — 실자료는 이 한 판(읽기 · 판 대조 · apply 몫을 잰다).
fn old_dlc_case(side: &Side, tag: &str) {
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let dep = dlc(&format!("{FIX}/dep-scene.htpack"), &[]);
    let nest4 = dlc(&format!("{FIX}/f4/nest-scene.htpack"), &[]);
    let ea4 = dlc(&format!("{FIX}/f4/east-asia.htpack"), &[]);
    assert_eq!(ea4.key, ea.key, "동아시아 기본팩 사본은 같은 id");
    let mut steps: Vec<(Dlc, Vec<Dlc>)> = vec![(dep.clone(), vec![ea.clone(), dep.clone()]), (nest4.clone(), vec![ea.clone(), dep.clone(), nest4.clone()]),
        (ea4.clone(), vec![ea4.clone(), dep.clone(), nest4.clone()])];
    match ktl() {
        Some(k) => steps.push((k.clone(), vec![ea4.clone(), dep.clone(), nest4.clone(), k])),
        None => eprintln!("건너뜀 KoreanTimeLine — 파일이 없습니다"),
    }
    let mut combos = vec![vec![ea.clone()]];
    combos.extend(steps.iter().map(|(_, c)| c.clone()));
    side.prefetch(&combos, T);
    let path = full(side, &[ea.clone()], T, tag);
    for (i, (d, combo)) in steps.iter().enumerate() {
        let r = add(&path, &[d], side.lay()).unwrap_or_else(|e| panic!("{tag} {}: {e}", d.key));
        let want = full(side, combo, T, &format!("{tag}-{i}"));
        same_store(&path, &want, &format!("{tag} 옛 DLC {}", d.key), &[]);
        if d.key == ea.key {
            assert_eq!(r.replaced.len(), 1, "같은 판 · 다른 바이트로 바꿔 넣음: {:?}", r.replaced);
            assert_eq!((r.replaced[0].old_version.as_str(), r.replaced[0].new_sha256.as_str()), (r.replaced[0].new_version.as_str(), sha(&ea4.bytes).as_str()));
        }
        let steps: Vec<String> = r.apply.steps.iter().map(|(name, ms)| format!("{name} {ms:.1}")).collect();
        eprintln!("{tag} {}: 읽기 · 판 대조 {:.1}ms · apply {:.1}ms · (배치 {:.0}ms · {}번 — 시간에서 뺌) · 다시 쓴 트랙 {} · 새 트랙 {} · 범위 {:?} · 걸음 [{}]",
            d.key, r.ms_read, r.ms_apply, r.ms_layout, r.layouts, r.apply.rewrote.len(), r.apply.added.len(), r.scope, steps.join(" · "));
    }
}

#[test]
fn old_dlc_files_go_in_as_they_are() {
    let _t = common::clock("old_dlc_files_go_in_as_they_are");
    old_dlc_case(&Side::node("ap-old-dlc", Touch::Exact), "ap-old-dlc");
}

#[test]
fn rust_old_dlc_files_go_in_as_they_are() {
    let _t = common::clock("rust_old_dlc_files_go_in_as_they_are");
    old_dlc_case(&Side::Rust, "ap-rold-dlc");
}

#[test]
fn stores_from_the_node_path_take_add_pack_next() {
    let _t = common::clock("stores_from_the_node_path_take_add_pack_next");
    // Node 길로 지은 저장소에 이어서 돈다: (뒤) 이 계획의 가져오기로 지은 것(지문 · 지은 날 · DLC 차례가 있음 — 좁힌 배치) · (전) 이 계획 전의 저장소
    // (지문 표 · 지은 날 · 새 열이 없음 — 첫 번엔 모든 트랙을 한 번 다시 씀) · Node 배치를 apply로 고친 저장소(B 걸음의 앱 길).
    // 이 저장소들엔 달력 표가 없다 — Node 틈(제 ICU로 읽음)이라 흐름은 돈다(실제 틈은 거절 — 아래 `a_store_without_the_calendar_table_is_refused`).
    let side = Side::node("ap-node", Touch::Exact);
    let node = side.node_ref();
    let after = [synth(), patch1(), patch2()];
    // (뒤) — 가져오기(import_layout_value: 배치에 now가 없으면 지은 시각 → 여기서는 그 날로 맞춤).
    let inputs: Vec<PackIn> = [synth(), patch1()].iter().map(Dlc::input).collect();
    let mut plan = node.full(&inputs, T, TZ);
    plan["now"] = json!(iso_at(T, TZ));
    let originals: Vec<(String, Vec<u8>)> = [synth(), patch1()].iter().map(|d| (d.key.clone(), d.bytes.clone())).collect();
    let b = common::scratch("ap-node-b");
    import_layout_value(&plan, &originals, &b).unwrap();
    let r = add(&b, &[&patch2()], node).unwrap();
    // 가져오기(바깥 배치)는 규칙 판을 적지 않는다 — 첫 넣기는 모든 트랙 한 번(판정 R69-2 · 예전엔 좁힌 배치로 S 밖 트랙을 믿었다).
    assert_eq!(r.scope, None, "가져오기로 지은 저장소의 첫 넣기는 모든 트랙");
    // 통째 짓기(짓기 ②)는 달력 표를 넣고 가져오기 길은 넣지 않는다 — 그 표 말고 같다.
    let want = common::scratch("ap-node-want");
    let all: Vec<(String, Vec<u8>)> = after.iter().map(|d| (d.key.clone(), d.bytes.clone())).collect();
    let mut wanted = side.plan(&after, T);
    wanted["now"] = json!(iso_at(T, TZ));
    import_layout_value(&wanted, &all, &want).unwrap();
    same_store(&b, &want, "Node 길(뒤)", &["rules"]); // 가져오기로 지은 견줌 저장소는 규칙 판이 없다(판정 R69-2)
    // (전) — 이 계획 전의 저장소: 지문 표 · 지은 날 · DLC 차례 · 새 열을 지운다.
    let a = full(&side, &[synth(), patch1()], T, "ap-node-a");
    common::strip_new_columns(&a);
    rusqlite::Connection::open(&a).unwrap().execute("DELETE FROM meta WHERE key='pack_order'", []).unwrap();
    let r = add(&a, &[&patch2()], node).unwrap();
    assert_eq!(r.scope, None, "이 계획 전 저장소는 모든 트랙을 셈");
    assert_eq!(r.apply.rewrote.len() + r.apply.added.len(), common::track_count(&a), "첫 번엔 모든 트랙을 한 번 다시 씀");
    // 이 계획 전 저장소는 판 3(스키마 4 전 — `strip_new_columns`)이라 첫 넣기가 판 4로 적는다(리메이크 3단계 과제 7 걸음 2).
    assert!(["4", "4.1"].contains(&meta(&a)["schema"].as_str()), "판 4로 고쳐 적어야 함 — {}", meta(&a)["schema"]);
    // 지은 날이 없던 저장소는 지금 시각으로 셈하므로 '오늘'에 기대는 띠가 통째 짓기(T)와 다를 수 있다 — 같은 날의 통째 짓기와 견준다(표 없는 저장소 — 가져오기 길로).
    let now = archive_engine::legacy::iso_time(&meta(&a)["now"]).unwrap().0;
    let plain = |combo: &[Dlc], tag: &str| -> PathBuf {
        let path = common::scratch(tag);
        let mut p = side.plan(combo, now);
        p["now"] = json!(iso_at(now, TZ));
        import_layout_value(&p, &combo.iter().map(|d| (d.key.clone(), d.bytes.clone())).collect::<Vec<_>>(), &path).unwrap();
        path
    };
    same_store(&a, &plain(&after, "ap-node-a-full"), "Node 길(전) 첫 넣기", &["rules"]);
    let r = remove(&a, "synth-patch2", true, node).unwrap();
    assert!(r.scope.is_some(), "한 번 다시 쓴 뒤로는 좁힌 배치");
    same_store(&a, &plain(&[synth(), patch1()], "ap-node-a-full2"), "Node 길(전) 둘째", &["rules"]);
    // Node 배치를 apply로 고친 저장소(B 걸음 — add-dlc --layout-only → apply).
    let c = full(&side, &[synth()], T, "ap-node-c");
    let mut plan = node.full(&inputs, T, TZ);
    plan["now"] = json!(iso_at(T, TZ));
    write(&c, |tx| apply(tx, &ApplyIn { plan: &plan, originals: &originals[1..], covers: Covers::All, remove: &[] })).unwrap();
    add(&c, &[&patch2()], node).unwrap();
    same_store(&c, &full(&side, &after, T, "ap-node-c-full"), "Node apply 뒤", &[]);
}

/// 판정 R34 D(휴대폰 시드 잇기): 새 시드(기본 DLC만)에 옛 저장소의 사용자 DLC를 그 저장소의 원본으로 다시 넣는다(from_store + ids) — 이미 같거나 높은 판이
/// 든 id는 건너뛴다(`skipped`). 보관함: 빼되 원본을 남기면(delete: false) `kept_packs`에 들고, ids로 다시 넣으면 보관함에서 꺼낸다 · delete: true면 남기지 않는다.
fn another_store_case(side: &Side, tag: &str) {
    let lay = side.lay();
    side.prefetch(&[vec![synth(), patch1(), patch2()], vec![synth()], vec![synth(), patch2()], vec![synth(), patch2(), patch1()]], T);
    let old = full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-old"));
    let seed = full(side, &[synth()], T, &format!("{tag}-seed"));
    let r = add_order(&seed, &AddOrder { from_store: Some(old.clone()), ids: vec!["synth-patch".into(), "synth-patch2".into()], ..AddOrder::default() }, lay).unwrap();
    assert_eq!(r.packs, ["synth-world", "synth-patch", "synth-patch2"]);
    assert!(r.skipped.is_empty());
    let want = full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-want"));
    same_store(&seed, &want, "다른 저장소의 원본", &[]);
    // 다시 같은 것을 부르면 이미 같은 판이 들어 건너뛴다 — 할 일이 없어 배치하지 않는다(저장소 그대로).
    let before = common::sha256_file(&seed);
    let r = add_order(&seed, &AddOrder { from_store: Some(old.clone()), ids: vec!["synth-patch".into(), "synth-patch2".into()], ..AddOrder::default() }, lay).unwrap();
    assert_eq!((r.skipped.clone(), r.layouts, r.apply.first_pos), (vec!["synth-patch".to_string(), "synth-patch2".to_string()], 0, -1));
    assert_eq!(common::sha256_file(&seed), before, "모두 건너뛰면 저장소 그대로");
    // 원본 없이 든 DLC(메이커 배치로만) — 거절(code original) · 저장소 그대로.
    rusqlite::Connection::open(&old).unwrap().execute("UPDATE packs SET original=NULL WHERE name LIKE '%둘%'", []).unwrap();
    let fresh = full(side, &[synth()], T, &format!("{tag}-seed2"));
    let before = common::sha256_file(&fresh);
    let err = add_order(&fresh, &AddOrder { from_store: Some(old.clone()), ids: vec!["synth-patch2".into()], ..AddOrder::default() }, lay).unwrap_err();
    assert_eq!(code(&err), Some("original"), "{err}");
    assert_eq!(common::sha256_file(&fresh), before);
    // 보관함
    let r = remove(&seed, "synth-patch", false, lay).unwrap();
    assert_eq!(r.kept, ["synth-patch"]);
    let shelf = kept_packs(&rusqlite::Connection::open(&seed).unwrap()).unwrap();
    assert_eq!(shelf[0]["id"], "synth-patch");
    same_store(&seed, &full(side, &[synth(), patch2()], T, &format!("{tag}-kept")), "보관함에 남기고 뺌", &[]);
    let r = add_order(&seed, &AddOrder { ids: vec!["synth-patch".into()], ..AddOrder::default() }, lay).unwrap();
    assert_eq!(r.unkept, ["synth-patch"]);
    assert_eq!(kept_packs(&rusqlite::Connection::open(&seed).unwrap()).unwrap(), json!([]));
    same_store(&seed, &full(side, &[synth(), patch2(), patch1()], T, &format!("{tag}-back")), "보관함에서 다시 넣음(뒤에 붙음)", &[]);
    let r = remove(&seed, "synth-patch2", true, lay).unwrap();
    assert_eq!((r.kept.len(), r.deleted.clone()), (0, vec!["synth-patch2".to_string()]));
    assert_eq!(kept_packs(&rusqlite::Connection::open(&seed).unwrap()).unwrap(), json!([]));
}

#[test]
fn another_store_and_the_kept_shelf_give_their_originals() {
    let _t = common::clock("another_store_and_the_kept_shelf_give_their_originals");
    another_store_case(&Side::node("ap-from", Touch::Exact), "ap-from");
}

#[test]
fn rust_another_store_and_the_kept_shelf_give_their_originals() {
    let _t = common::clock("rust_another_store_and_the_kept_shelf_give_their_originals");
    another_store_case(&Side::Rust, "ap-rfrom");
}

/// 휴대폰이 메이커 `.htlayout`으로 `extra`를 원본 없이 넣은 저장소(`base` 조합 위에).
fn phone(side: &Side, base: &[Dlc], extra: &[Dlc], tag: &str) -> PathBuf {
    let path = full(side, base, T, tag);
    let all: Vec<Dlc> = base.iter().chain(extra).cloned().collect();
    let mut plan = side.plan(&all, T);
    plan["now"] = json!(iso_at(T, TZ));
    let layout = common::scratch(&format!("{tag}-layout")).with_extension("htlayout");
    std::fs::write(&layout, common::plans::htlayout(&plan)).unwrap();
    let order = archive_engine::patch::read_order(&layout, &[], Vec::new(), archive_engine::patch::CoversAsk::Default).unwrap();
    write(&path, |tx| archive_engine::patch::run_order(tx, &order)).unwrap();
    let db = rusqlite::Connection::open(&path).unwrap();
    let missing: i64 = db.query_row("SELECT count(*) FROM packs WHERE original IS NULL", [], |r| r.get(0)).unwrap();
    assert_eq!(missing as usize, extra.len(), "장면: 원본 없이 든 DLC 수");
    path
}

/// 고침 1회차(검토 Important 6 — 막다른 길): 휴대폰이 메이커 `.htlayout`으로 원본 없이 넣은 DLC가 있는 저장소. 그 DLC가 남는 넣기는 거절(code original)이지만,
/// 그 DLC의 파일 · 다른 저장소의 원본을 주면 채워 넣고(`replaced`의 옛 지문 없음), 그 DLC를 빼는 것은 제 원본 없이 된다(보관함에 남길 것이 없어 `deleted`).
/// 고침 2회차: 원본 없는 DLC가 둘이면 하나만 빼거나 채울 수 없고(남는 것도 원본이 없다) 두 파일을 한 번에 넣으면 된다 · 보관함에 같은 id(전에 꺼 둔 판)가 있으면
/// 원본 없는 그 DLC를 남기며 빼도 보관함은 그대로(`kept`).
fn original_less_case(side: &Side, tag: &str) {
    let lay = side.lay();
    side.prefetch(&[vec![synth()], vec![synth(), patch1()], vec![synth(), patch1(), patch2()], vec![synth(), patch2()]], T);
    // 그 DLC가 남는 넣기(다른 DLC의 높은 판)는 거절 — 저장소 그대로.
    let a = phone(side, &[synth(), patch1()], &[patch2()], &format!("{tag}-a"));
    let before = common::sha256_file(&a);
    let err = add(&a, &[&patch1_v11()], lay).unwrap_err();
    assert_eq!(code(&err), Some("original"), "{err}");
    assert!(err.to_string().contains("synth-patch2"), "{err}");
    assert_eq!(common::sha256_file(&a), before);
    // 그 DLC의 파일을 주면 채워 넣는다.
    let r = add(&a, &[&patch2()], lay).unwrap();
    assert_eq!(r.replaced.len(), 1);
    assert_eq!((r.replaced[0].id.as_str(), r.replaced[0].old_sha256.clone()), ("synth-patch2", None));
    same_store(&a, &full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-a-full")), "원본을 채움", &[]);
    // 다른 저장소의 원본으로도 채운다(같은 판이어도 원본이 없으면 건너뛰지 않는다).
    let b = phone(side, &[synth(), patch1()], &[patch2()], &format!("{tag}-b"));
    let old = full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-old"));
    let r = add_order(&b, &AddOrder { from_store: Some(old), ids: vec!["synth-patch2".into()], ..AddOrder::default() }, lay).unwrap();
    assert!(r.skipped.is_empty() && r.replaced.len() == 1, "{:?} · {:?}", r.skipped, r.replaced);
    same_store(&b, &full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-b-full")), "다른 저장소의 원본으로 채움", &[]);
    // 원본 없는 DLC를 뺀다 — 남길 원본이 없어 보관함 대신 deleted.
    let c = phone(side, &[synth(), patch1()], &[patch2()], &format!("{tag}-c"));
    let r = remove(&c, "synth-patch2", false, lay).unwrap();
    assert_eq!((r.kept.len(), r.deleted.clone()), (0, vec!["synth-patch2".to_string()]));
    assert_eq!(kept_packs(&rusqlite::Connection::open(&c).unwrap()).unwrap(), json!([]));
    same_store(&c, &full(side, &[synth(), patch1()], T, &format!("{tag}-c-full")), "원본 없는 DLC 빼기", &[]);
    // 원본 없는 DLC가 둘: 하나만 빼기 · 하나만 채우기는 거절(남는 것도 원본이 없다 — 글이 '그 DLC들의 파일을 한 번에'), 두 파일을 한 번에 넣으면 채워진다.
    let d = phone(side, &[synth()], &[patch1(), patch2()], &format!("{tag}-d"));
    let before = common::sha256_file(&d);
    let err = remove(&d, "synth-patch2", true, lay).unwrap_err();
    assert_eq!(code(&err), Some("original"), "{err}");
    assert!(err.to_string().contains("synth-patch") && err.to_string().contains("한 번에 함께"), "{err}");
    assert_eq!(code(&add(&d, &[&patch2()], lay).unwrap_err()), Some("original"));
    assert_eq!(common::sha256_file(&d), before);
    let r = add(&d, &[&patch1(), &patch2()], lay).unwrap();
    assert_eq!(r.replaced.len(), 2);
    same_store(&d, &full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-d-full")), "원본 없는 둘을 한 번에 채움", &[]);
    // 보관함에 같은 id(전에 꺼 둔 판)가 있는 원본 없는 DLC를 남기며 뺀다 — 보관함은 그대로(kept).
    let e = full(side, &[synth(), patch1(), patch2()], T, &format!("{tag}-e"));
    remove(&e, "synth-patch2", false, lay).unwrap();
    let shelf_before = kept_packs(&rusqlite::Connection::open(&e).unwrap()).unwrap();
    let mut plan = side.plan(&[synth(), patch1(), patch2()], T);
    plan["now"] = json!(iso_at(T, TZ));
    let layout = common::scratch(&format!("{tag}-e-layout")).with_extension("htlayout");
    std::fs::write(&layout, common::plans::htlayout(&plan)).unwrap();
    let order = archive_engine::patch::read_order(&layout, &[], Vec::new(), archive_engine::patch::CoversAsk::Default).unwrap();
    write(&e, |tx| archive_engine::patch::run_order(tx, &order)).unwrap();
    let r = remove(&e, "synth-patch2", false, lay).unwrap();
    assert_eq!((r.kept.clone(), r.deleted.len()), (vec!["synth-patch2".to_string()], 0));
    assert_eq!(kept_packs(&rusqlite::Connection::open(&e).unwrap()).unwrap(), shelf_before, "보관함의 원본은 그대로");
    let kept_sha: String = rusqlite::Connection::open(&e).unwrap().query_row("SELECT sha256 FROM kept_packs WHERE key='synth-patch2'", [], |r| r.get(0)).unwrap();
    assert_eq!(kept_sha, sha(&patch2().bytes));
}

#[test]
fn a_pack_without_its_original_can_be_filled_or_removed() {
    let _t = common::clock("a_pack_without_its_original_can_be_filled_or_removed");
    original_less_case(&Side::node("ap-orig", Touch::Exact), "ap-orig");
}

#[test]
fn rust_a_pack_without_its_original_can_be_filled_or_removed() {
    let _t = common::clock("rust_a_pack_without_its_original_can_be_filled_or_removed");
    original_less_case(&Side::Rust, "ap-rorig");
}

#[test]
fn a_store_without_the_calendar_table_is_refused() {
    let _t = common::clock("a_store_without_the_calendar_table_is_refused");
    // 판정 R36: 실제 틈은 저장소의 달력 표로 배치한다 — 표 없는 옛 저장소(Node 길의 가져오기로 지은 것)는 넣기 · 빼기 모두 쉬운 글로 거절(code calendar) · 저장소 그대로.
    // 고침 2회차: 깨진 표(zlib은 풀리고 JSON이 아님 · zlib이 풀리지 않음)도 같은 code로 쉬운 글 · 보관함에서만 지우기(R42)는 배치하지 않아 표 없이도 된다.
    let path = common::scratch("ap-nocal");
    let mut plan = Side::Rust.plan(&[synth(), patch1()], T);
    plan["now"] = json!(iso_at(T, TZ));
    import_layout_value(&plan, &[(synth().key, synth().bytes), (patch1().key, patch1().bytes)], &path).unwrap();
    let before = common::sha256_file(&path);
    let err = add(&path, &[&patch2()], &RustLayouter).unwrap_err();
    assert_eq!(code(&err), Some("calendar"), "{err}");
    assert!(err.to_string().contains("달력 표가 없는 옛 저장소") && err.to_string().contains("새 판 시드"), "{err}");
    let err = remove(&path, "synth-patch", true, &RustLayouter).unwrap_err();
    assert_eq!(code(&err), Some("calendar"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
    // 보관함에서만 지우기는 표 없이도(Node 틈으로 꺼 둔 뒤 실제 틈으로 지움).
    let node = Side::node("ap-nocal", Touch::Exact);
    remove(&path, "synth-patch", false, node.lay()).unwrap();
    let r = remove(&path, "synth-patch", true, &RustLayouter).unwrap();
    assert_eq!((r.deleted.clone(), r.layouts), (vec!["synth-patch".to_string()], 0));
    // 깨진 표: zlib은 풀리는데 JSON이 아님 · zlib이 풀리지 않음.
    for (n, (what, bytes)) in [("JSON 아님", {
        use std::io::Write;
        let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
        z.write_all(b"{\"v\":1,\"tables\":").unwrap();
        z.finish().unwrap()
    }), ("zlib 아님", b"\x00\xff\x00".to_vec()), ("꼴 틀림(모르는 달력 — 판정 R70-3)", {
        use std::io::Write;
        let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
        z.write_all(br#"{"v":1,"years":[-3500,2500],"tables":{"nope":{}}}"#).unwrap();
        z.finish().unwrap()
    })].into_iter().enumerate() {
        let broken = full(&Side::Rust, &[synth(), patch1()], T, &format!("ap-badcal-{n}"));
        rusqlite::Connection::open(&broken).unwrap().execute("UPDATE blobs SET bytes=?1 WHERE key='calendar:table'", [bytes]).unwrap();
        let before = common::sha256_file(&broken);
        let err = add(&broken, &[&patch2()], &RustLayouter).unwrap_err();
        assert_eq!(code(&err), Some("calendar"), "{what}: {err}");
        assert!(err.to_string().contains("달력 표가 깨졌습니다"), "{what}: {err}");
        assert_eq!(common::sha256_file(&broken), before, "{what}");
    }
    // 판정 R70-3: 아주 옛 저장소(DLC id가 없음 — 표도 없는 때의 것)도 저장소 쪽 — calendar.
    let ancient = full(&Side::Rust, &[synth(), patch1()], T, "ap-ancient");
    rusqlite::Connection::open(&ancient).unwrap().execute("DELETE FROM meta WHERE key='pack_keys'", []).unwrap();
    let before = common::sha256_file(&ancient);
    for err in [add(&ancient, &[&patch2()], &RustLayouter).unwrap_err(), remove(&ancient, "synth-patch", true, &RustLayouter).unwrap_err()] {
        assert_eq!(code(&err), Some("calendar"), "{err}");
        assert!(err.to_string().contains("아주 옛 저장소"), "{err}");
    }
    assert_eq!(common::sha256_file(&ancient), before);
}

#[test]
fn the_same_version_with_other_bytes_is_replaced_and_told() {
    let _t = common::clock("the_same_version_with_other_bytes_is_replaced_and_told");
    // 같은 판 · 다른 바이트(메이커가 판을 올리지 않고 고친 작업본)는 받아 바꿔 넣고 답의 `replaced`에 옛 · 새 지문을 적는다(앱이 알릴 수 있게).
    let side = Side::node("ap-same-ver", Touch::Exact);
    let path = full(&side, &[synth(), patch1()], T, "ap-same-ver");
    let edited = patch1_same_version();
    let r = add(&path, &[&edited], side.lay()).unwrap();
    assert_eq!(r.replaced, vec![archive_engine::packs::Replaced { id: "synth-patch".into(), old_version: "1.0.0".into(), new_version: "1.0.0".into(),
        old_sha256: Some(sha(&patch1().bytes)), new_sha256: sha(&edited.bytes) }]);
    assert_eq!(r.to_json()["replaced"][0]["new_sha256"], sha(&edited.bytes));
    same_store(&path, &full(&side, &[synth(), edited], T, "ap-same-ver-full"), "같은 판 · 다른 바이트", &[]);
}

#[test]
fn a_touched_key_outside_the_layout_is_left_out() {
    let _t = common::clock("a_touched_key_outside_the_layout_is_left_out");
    // 총괄 알림(P3-16a 검토): 닿는 트랙(`lay::touched`)에 이 조합의 배치에 없는 판 열쇠(판 셈 오류로 빠진 판)가 들 수 있다 — `Covers::Part`의 트랙은
    // S ∩ allTracks로 잡아 '배치에 없는 트랙'으로 거절하지 않는다. 지문이 바뀐 트랙에 없는 판 열쇠를 더해 답하는 틈으로 넣어도 좁힌 배치로 통째 짓기와 같다.
    struct Stray(NodeLayouter);
    impl Layouter for Stray {
        fn export(&self, p: &[PackIn], o: &Opts) -> archive_engine::Result<Value> {
            self.0.export(p, o)
        }
        fn touched(&self, b: &[PackIn], a: &[PackIn], o: &Opts) -> archive_engine::Result<Scope> {
            let Scope::Tracks(mut s) = self.0.touched(b, a, o)? else { panic!("Exact 틈은 트랙을 답한다") };
            s.insert("board:__board:view:없는-판".into());
            Ok(Scope::Tracks(s))
        }
        fn needs_calendar(&self) -> bool {
            false
        }
    }
    let side = Side::node("ap-stray", Touch::Exact);
    let stray = Stray(NodeLayouter::new("ap-stray-lay", Touch::Exact));
    let path = full(&side, &[synth(), patch1()], T, "ap-stray");
    let r = add(&path, &[&patch2()], &stray).unwrap();
    assert!(r.scope.is_some(), "좁힌 배치로");
    same_store(&path, &full(&side, &[synth(), patch1(), patch2()], T, "ap-stray-full"), "배치에 없는 열쇠를 거른 S", &[]);
    let r = remove(&path, "synth-patch", true, &stray).unwrap();
    assert!(r.scope.is_some());
    same_store(&path, &full(&side, &[synth(), patch2()], T, "ap-stray-full2"), "빼기도", &[]);
}

#[test]
fn a_lower_version_does_not_replace_the_kept_one() {
    let _t = common::clock("a_lower_version_does_not_replace_the_kept_one");
    // 고침 2회차(검토 ②-1 — 자료 손실 길): 꺼 둔(보관함에만 있는) DLC와 같은 id의 낮은 판을 넣으면 보관함의 높은 판과 견주어 `code` version으로 거절하고
    // 보관함 · 저장소는 그대로다(판정 R15). 같은 판 · 다른 바이트면 받아 넣고 `replaced`에 보관함 원본의 지문을 적는다. `prefer_given`(미리보기)이면 받는다.
    let side = Side::node("ap-kept-ver", Touch::Exact);
    let lay = side.lay();
    let path = full(&side, &[synth(), patch1_v11()], T, "ap-kept-ver");
    remove(&path, "synth-patch", false, lay).unwrap();
    let shelf = || kept_packs(&rusqlite::Connection::open(&path).unwrap()).unwrap();
    assert_eq!(shelf()[0]["version"], "1.1.0");
    let before = common::sha256_file(&path);
    let err = add(&path, &[&patch1()], lay).unwrap_err();
    assert_eq!(code(&err), Some("version"), "{err}");
    assert!(err.to_string().contains("보관함"), "{err}");
    assert_eq!(common::sha256_file(&path), before, "거절하면 저장소 · 보관함 그대로");
    // 같은 판 · 다른 바이트 — 받고 replaced에 보관함 원본의 지문.
    let edited = dlc(&format!("{FIX}/synth-patch.json"), &[("\"version\": \"1.0.0\"", "\"version\": \"1.1.0\""), ("\"고친 가상 사건\"", "\"다르게 고친 사건\"")]);
    let r = add(&path, &[&edited], lay).unwrap();
    assert_eq!(r.replaced.len(), 1, "{:?}", r.replaced);
    assert_eq!(r.replaced[0].old_sha256.as_deref(), Some(sha(&patch1_v11().bytes).as_str()));
    assert_eq!((r.replaced[0].old_version.as_str(), r.unkept.clone()), ("1.1.0", vec!["synth-patch".to_string()]));
    same_store(&path, &full(&side, &[synth(), edited.clone()], T, "ap-kept-ver-full"), "보관함과 같은 판의 다른 바이트", &[]);
    // prefer_given(미리보기)이면 보관함의 높은 판보다 낮아도 받는다.
    remove(&path, "synth-patch", false, lay).unwrap();
    let order = AddOrder { files: vec![patch1().file()], prefer_given: true, ..AddOrder::default() };
    let r = add_order(&path, &order, lay).unwrap();
    assert_eq!(r.replaced[0].new_version, "1.0.0");
    same_store(&path, &full(&side, &[synth(), patch1()], T, "ap-kept-ver-full2"), "미리보기 — 보관함보다 낮은 판", &[]);
}

/// 판정 R42: 앱의 '끄기'는 remove_pack(delete: false — 보관함으로) · '켜기'는 add_pack(ids). 꺼 둔(보관함에만 있는) DLC를 지우는 길은
/// remove_pack(그 id · delete: true) — 배치는 바뀌지 않아 apply 없이 보관함의 원본만 지운다(답은 같은 꼴 · 다시 쓴 트랙 없음).
fn shelf_case(side: &Side, tag: &str) {
    let path = full(side, &[synth(), patch1(), patch2()], T, tag);
    remove(&path, "synth-patch", false, side.lay()).unwrap();
    assert_eq!(kept_packs(&rusqlite::Connection::open(&path).unwrap()).unwrap()[0]["id"], "synth-patch");
    let err = remove(&path, "synth-patch", false, side.lay()).unwrap_err().to_string();
    assert!(err.contains("이미 꺼 둔"), "{err}");
    let r = remove(&path, "synth-patch", true, side.lay()).unwrap();
    assert_eq!((r.deleted.clone(), r.layouts, r.apply.first_pos, r.apply.rewrote.len()), (vec!["synth-patch".to_string()], 0, -1, 0));
    assert_eq!(r.packs, ["synth-world", "synth-patch2"]);
    assert_eq!(r.to_json()["deleted"], json!(["synth-patch"]));
    assert_eq!(kept_packs(&rusqlite::Connection::open(&path).unwrap()).unwrap(), json!([]));
    same_store(&path, &full(side, &[synth(), patch2()], T, &format!("{tag}-full")), "보관함에서 지움", &[]);
    assert!(remove(&path, "synth-patch", true, side.lay()).unwrap_err().to_string().contains("지금 저장소에 없습니다"), "두 번 지우면 없음");
}

#[test]
fn a_kept_pack_can_be_deleted_from_the_shelf() {
    let _t = common::clock("a_kept_pack_can_be_deleted_from_the_shelf");
    shelf_case(&Side::node("ap-shelf", Touch::Exact), "ap-shelf");
}

#[test]
fn rust_a_kept_pack_can_be_deleted_from_the_shelf() {
    let _t = common::clock("rust_a_kept_pack_can_be_deleted_from_the_shelf");
    shelf_case(&Side::Rust, "ap-rshelf");
}

/// 장면(`plans.rs` — Node 없이)을 배치로 내는 틈: DLC 바이트의 id · 판으로 장면 조합을 고른다(`a` · `a@2` · `b` · `c`). `drop_boards_with`의 DLC가 든
/// 조합은 판(`boards`)을 빼고 낸다(판 셈 오류로 판이 빠진 배치 흉내). 닿는 트랙은 지문이 바뀐 트랙 + 앞 조합에만 있던 트랙(사라진 판)의 열쇠.
struct SceneLayouter {
    drop_boards_with: &'static str,
}

impl SceneLayouter {
    fn plan_of(&self, packs: &[PackIn]) -> Value {
        let keys: Vec<String> = packs.iter().map(|p| {
            let raw = archive_engine::htpack_raw(&p.bytes).unwrap();
            let id = raw["id"].as_str().unwrap().to_owned();
            if raw["version"] == "2.0.0" { format!("{id}@2") } else { id }
        }).collect();
        let refs: Vec<&str> = keys.iter().map(String::as_str).collect();
        let mut plan = common::plans::plan(&refs);
        if refs.contains(&self.drop_boards_with) {
            plan.as_object_mut().unwrap().remove("boards");
        }
        plan
    }
}

impl Layouter for SceneLayouter {
    fn export(&self, packs: &[PackIn], opts: &Opts) -> archive_engine::Result<Value> {
        let whole = self.plan_of(packs);
        match &opts.scope {
            Scope::All => Ok(whole),
            Scope::Tracks(s) => {
                let keys: BTreeSet<String> = archive_engine::patch::track_keys(&whole).into_iter().filter(|k| s.contains(k)).collect();
                sub_plan(&whole, &keys)
            }
        }
    }
    fn touched(&self, before: &[PackIn], after: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> {
        let (b, a) = (prints(&self.plan_of(before))?, prints(&self.plan_of(after))?);
        let mut s: BTreeSet<String> = a.order.iter().filter(|k| b.tracks.get(*k).map(|t| &t.print) != Some(&a.tracks[*k].print)).cloned().collect();
        s.extend(b.order.iter().filter(|k| !a.tracks.contains_key(*k)).cloned()); // 앞에만 있던 트랙(사라진 판) — 새 조합의 배치엔 없다
        Ok(Scope::Tracks(s))
    }
    fn needs_calendar(&self) -> bool {
        false
    }
}

#[test]
fn a_board_missing_from_the_new_layout_is_left_out_of_s_and_removed() {
    let _t = common::clock("a_board_missing_from_the_new_layout_is_left_out_of_s_and_removed");
    // 고침 2회차(검토 ② 빈틈 — S ∩ allTracks): 저장소에 있던 판이 이번 배치에서 빠지면(판 셈 오류 흉내) 닿는 트랙 S에 그 판 열쇠가 들어도 `allTracks`에 없으니
    // 걸러 좁힌 배치로 넣고, 판은 조합에 없는 트랙이라 지워진다 — 그 배치를 통째로 지은 것과 같다. 다시 빼면(판이 돌아온 배치) 새 판이 든다.
    use common::plans::{packs_of, plan};
    let lay = SceneLayouter { drop_boards_with: "b" };
    let path = common::scratch("ap-scene-board");
    import_layout_value(&plan(&["a", "c"]), &packs_of(&["a", "c"]), &path).unwrap();
    // 가져오기는 규칙 판을 적지 않는다(판정 R69-2 — 바깥 배치) — 장면 저장소를 짓기로 지은 것처럼 적어 좁힌 배치 길을 본다.
    write(&path, |tx| archive_engine::patch::mark_rules(tx)).unwrap();
    let b = Dlc { key: "b".into(), bytes: packs_of(&["b"]).remove(0).1 };
    let r = add(&path, &[&b], &lay).unwrap();
    assert!(r.scope.is_some(), "좁힌 배치로");
    assert!(r.apply.removed.contains(&"board:__board:view:a1".to_string()), "사라진 판은 지워진다: {:?}", r.apply);
    let mut want_plan = plan(&["a", "c", "b"]);
    want_plan.as_object_mut().unwrap().remove("boards");
    let want = common::scratch("ap-scene-board-full");
    import_layout_value(&want_plan, &packs_of(&["a", "c", "b"]), &want).unwrap();
    same_store(&path, &want, "판이 빠진 배치", &["now", "rules"]);
    let r = remove(&path, "b", true, &lay).unwrap();
    assert!(r.apply.added.contains(&"board:__board:view:a1".to_string()), "판이 돌아온다: {:?}", r.apply);
    let want = common::scratch("ap-scene-board-full2");
    import_layout_value(&plan(&["a", "c"]), &packs_of(&["a", "c"]), &want).unwrap();
    same_store(&path, &want, "판이 돌아온 배치", &["now", "rules"]);
}

#[test]
fn a_real_out_of_range_date_is_refused_with_code_range() {
    // 판정 R69-1(16b 검토 ① I-1): 실제 틈은 닿는 트랙을 셈하며 먼저 정규화한다 — 거기서 나는 거절(보조 달력 범위 밖)도 배치 실패처럼 거절 code로
    // (`code` range · 쉬운 글 · 개발자 글은 detail). 음력 날짜를 표 범위 밖(9000년)으로 적은 DLC를 동아시아 저장소에 넣는다. 저장소 그대로.
    let _t = common::clock("a_real_out_of_range_date_is_refused_with_code_range");
    let side = Side::Rust;
    let path = full(&side, &[dlc(&format!("{FIX}/east-asia.json"), &[])], T, "ap-range");
    let before = common::sha256_file(&path);
    let d = json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": "xl", "name": "먼 음력", "version": "0.0.1",
        "tracks": [{ "id": "xl", "name": "먼 음력 트랙" }],
        "periods": [{ "id": "p1", "track": "xl", "name": "먼 나라", "start": 1000, "end": 1100 }],
        "events": [{ "id": "e1", "track": "xl", "title": "먼 음력 사건", "start": "음력 9000-04-13" }] });
    let far = Dlc { key: "xl".into(), bytes: seal_dlc(&serde_json::to_vec(&d).unwrap()) };
    let e = add(&path, &[&far], side.lay()).unwrap_err();
    let r = e.downcast_ref::<Refusal>().unwrap_or_else(|| panic!("거절(code)이어야 합니다: {e}"));
    assert_eq!(r.code, "range", "{}", r.message);
    assert!(r.message.contains("«먼 음력»") && !r.message.contains("컴퓨터에서"), "{}", r.message);
    assert!(r.detail.as_deref().is_some_and(|d| d.contains("표 범위 밖")), "{:?}", r.detail);
    assert_eq!(common::sha256_file(&path), before, "거절이면 저장소 그대로");
}

#[test]
fn a_guessed_key_missing_from_the_layout_widens_to_all() {
    // 판정 R69-4(16b 검토 ① M-4): 닿는 트랙이 짐작한 열쇠(판이 아닌 트랙)가 배치에 없으면 거절하지 않고 모든 트랙으로 넓혀 다시 배치한다 — 저장소는 통째 짓기와 같다.
    let _t = common::clock("a_guessed_key_missing_from_the_layout_widens_to_all");
    struct Stray;
    impl Layouter for Stray {
        fn export(&self, packs: &[PackIn], opts: &Opts) -> archive_engine::Result<Value> { RustLayouter.export(packs, opts) }
        fn touched(&self, _: &[PackIn], _: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> {
            Ok(Scope::Tracks(["north".to_string(), "없는-트랙".to_string()].into_iter().collect()))
        }
    }
    let side = Side::Rust;
    let path = full(&side, &[synth()], T, "ap-stray-key");
    let r = add(&path, &[&patch1()], &Stray).unwrap_or_else(|e| panic!("넓히지 않고 거절함: {e}"));
    assert_eq!(r.scope, None, "모든 트랙으로 넓혀야 합니다");
    assert_eq!(r.layouts, 2, "범위 배치 한 번 + 모두 한 번");
    // 판정 R71-3: 넓힘은 답에 남는다 — 까닭과 빗나간 열쇠 수.
    assert_eq!(r.to_json()["widened"], json!({"why": "missing", "keys": 1, "detail": "없는-트랙"}));
    same_store(&path, &full(&side, &[synth(), patch1()], T, "ap-stray-key-full"), "짐작 열쇠가 빗나간 넣기", &[]);
}

#[test]
fn a_failing_touch_falls_back_to_all() {
    // 판정 R71-2(16b 고침 1회차 재검토 Important 2): 닿는 트랙 셈의 실패(오류 · 패닉 — 저장소의 앞 원본이 지금 엔진에서 넘어지는 꼴의 흉내)는 거절하지
    // 않고 모든 트랙으로 배치한다 — 진짜 거절은 뒤 조합 배치의 가름 하나에서만(받은 DLC가 범위 밖이면 거기서도 range — 위 검사). 답의 `widened`에 까닭.
    let _t = common::clock("a_failing_touch_falls_back_to_all");
    struct TouchFails(bool);
    impl Layouter for TouchFails {
        fn export(&self, p: &[PackIn], o: &Opts) -> archive_engine::Result<Value> { RustLayouter.export(p, o) }
        fn touched(&self, _: &[PackIn], _: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> {
            if self.0 { panic!("앞 조합을 정규화하다 넘어짐(흉내)") }
            Err("synth.htpack: 앞 원본을 지금 엔진이 읽지 못함(흉내)".into())
        }
    }
    let side = Side::Rust;
    let want = full(&side, &[synth(), patch1()], T, "ap-touch-fails-full");
    for (tag, layouter) in [("err", TouchFails(false)), ("panic", TouchFails(true))] {
        let path = full(&side, &[synth()], T, &format!("ap-touch-fails-{tag}"));
        let r = add(&path, &[&patch1()], &layouter).unwrap_or_else(|e| panic!("{tag}: 모든 트랙으로 떨어뜨리지 않고 거절함: {e}"));
        assert_eq!((r.scope, r.layouts), (None, 1), "{tag}: 모든 트랙 배치 한 번");
        let w = r.to_json()["widened"].clone();
        assert_eq!((w["why"].clone(), w["keys"].clone()), (json!("touched_failed"), json!(0)), "{tag}: {w}");
        assert!(w["detail"].as_str().is_some_and(|d| d.contains("흉내")), "{tag}: {w}");
        same_store(&path, &want, tag, &[]);
    }
}

#[test]
fn a_part_that_needs_untouched_tracks_mid_write_retries_whole() {
    // 총괄 덧붙임(16b 고침 1회차 — 갈래 1 검토): 하위 배치(Part)를 고쳐 쓰는 도중에 '다시 쓰지 않는 트랙도 함께 다시 써야 함'이 드러나면(`patch::NeedsWhole` —
    // 예: 밖 변형 열쇠가 저장소에 없음) '메이커에서 그 DLC까지 불러와 내보내기'로 거절하지 않고, 그 자리로 되돌려 모든 트랙으로 다시 한다 — 통째 짓기와 같다.
    let _t = common::clock("a_part_that_needs_untouched_tracks_mid_write_retries_whole");
    struct OuterStray;
    impl Layouter for OuterStray {
        fn export(&self, p: &[PackIn], o: &Opts) -> archive_engine::Result<Value> {
            let mut plan = RustLayouter.export(p, o)?;
            if matches!(o.scope, Scope::Tracks(_)) {
                // 하위 배치의 띠 하나가 하위 배치에 없는 변형을 가리킴 → `outer.variants`의 열쇠가 저장소에 없는 꼴("insert"에서 드러남).
                if let Some(p) = plan["periods"].as_array_mut().and_then(|l| l.first_mut()) { p["variant"] = json!("없는-밖-변형"); }
            }
            Ok(plan)
        }
        fn touched(&self, b: &[PackIn], a: &[PackIn], o: &Opts) -> archive_engine::Result<Scope> { RustLayouter.touched(b, a, o) }
    }
    let side = Side::Rust;
    let (ea, d7) = (dlc(&format!("{FIX}/east-asia.json"), &[]), dlc(&format!("{FIX}/d7-test.htpack"), &[]));
    let path = full(&side, &[ea.clone()], T, "ap-needs-whole");
    let r = add(&path, &[&d7], &OuterStray).unwrap_or_else(|e| panic!("모든 트랙으로 다시 하지 않고 거절함: {e}"));
    assert_eq!(r.scope, None, "모든 트랙으로 넓혀야 합니다");
    assert_eq!(r.layouts, 2, "범위 배치 한 번 + 모두 한 번");
    let w = r.to_json()["widened"].clone();
    assert_eq!(w["why"], json!("needs_whole"), "{w}");
    assert!(w["detail"].as_str().is_some_and(|d| d.contains("없는-밖-변형")), "{w}");
    same_store(&path, &full(&side, &[ea, d7], T, "ap-needs-whole-full"), "고쳐 쓰는 도중 넓힘", &[]);
}

#[test]
fn a_part_whose_fill_misses_an_outer_row_retries_whole() {
    // 판정 R72-4(통합 검토 M4): 하위 배치를 채우는 도중(`legacy::fill_into`) S 밖 트랙의 줄을 저장소에서 찾지 못함도 '함께 다시 써야 함'(`patch::NeedsWhole`) —
    // '메이커에서 그 DLC까지 불러와 내보내기'로 거절하지 않고 모든 트랙으로 다시 한다(R69-4 · R71-2와 같은 뜻).
    let _t = common::clock("a_part_whose_fill_misses_an_outer_row_retries_whole");
    struct OuterRowStray;
    impl Layouter for OuterRowStray {
        fn export(&self, p: &[PackIn], o: &Opts) -> archive_engine::Result<Value> {
            let mut plan = RustLayouter.export(p, o)?;
            if let Scope::Tracks(s) = &o.scope {
                // S 안 트랙의 변형 하나가 S 밖 트랙의 없는 줄(99999번째) 뒤에 줄을 끼운다 → 하위 배치의 `outer.rows`가 저장소에 없는 줄을 가리키는 꼴.
                // 범위 배치는 S 안 트랙만 싣고 S 밖 트랙은 열쇠 글로 가리킨다(`allTracks`에서 고름).
                let keys = archive_engine::patch::track_keys(&plan);
                let outside = plan["allTracks"].as_array().and_then(|l| l.iter().filter_map(Value::as_str).find(|k| !s.contains(*k)))
                    .expect("장면: S 밖 트랙이 있어야 함").to_owned();
                let ours = |v: &Value| v["track"].as_u64().and_then(|t| keys.get(t as usize)).is_some_and(|k| s.contains(k));
                let in_top = plan["variants"].as_array().is_some_and(|l| l.iter().any(ours));
                let list = if in_top { &mut plan["variants"] } else { &mut plan["boards"]["variants"] };
                let v = list.as_array_mut().and_then(|l| l.iter_mut().find(|v| ours(v))).expect("장면: S 안 트랙의 변형이 있어야 함");
                if !v["rows"].is_array() { v["rows"] = json!([]); }
                v["rows"].as_array_mut().unwrap().push(json!({"track": outside, "after": 99_999, "ord": 0}));
            }
            Ok(plan)
        }
        fn touched(&self, b: &[PackIn], a: &[PackIn], o: &Opts) -> archive_engine::Result<Scope> { RustLayouter.touched(b, a, o) }
    }
    let side = Side::Rust;
    let (ea, d7) = (dlc(&format!("{FIX}/east-asia.json"), &[]), dlc(&format!("{FIX}/d7-test.htpack"), &[]));
    let path = full(&side, &[ea.clone()], T, "ap-fill-row");
    let r = add(&path, &[&d7], &OuterRowStray).unwrap_or_else(|e| panic!("모든 트랙으로 다시 하지 않고 거절함: {e}"));
    assert_eq!(r.scope, None, "모든 트랙으로 넓혀야 합니다");
    let w = r.to_json()["widened"].clone();
    assert_eq!(w["why"], json!("needs_whole"), "{w}");
    assert!(w["detail"].as_str().is_some_and(|d| d.contains("99999번째 줄")), "{w}");
    same_store(&path, &full(&side, &[ea, d7], T, "ap-fill-row-full"), "채우는 도중 넓힘", &[]);
}

#[test]
fn an_add_leaves_no_thread_caches_behind() {
    // 판정 R69-5(16b 검토 ② M7 · ③ Minor 3): 넣기가 끝나면(실패해도) 이 스레드의 푼 달력 표 · 닿는 트랙이 남긴 준비 문맥을 비운다.
    let _t = common::clock("an_add_leaves_no_thread_caches_behind");
    struct FailsAfterTouch;
    impl Layouter for FailsAfterTouch {
        fn export(&self, _: &[PackIn], _: &Opts) -> archive_engine::Result<Value> { Err("배치 실패(검사)".into()) }
        fn touched(&self, b: &[PackIn], a: &[PackIn], o: &Opts) -> archive_engine::Result<Scope> { RustLayouter.touched(b, a, o) }
    }
    let side = Side::Rust;
    let path = full(&side, &[synth()], T, "ap-caches");
    assert!(add(&path, &[&patch1()], &FailsAfterTouch).is_err());
    assert!(!archive_engine::lay::export::prepared_held() && !archive_engine::lay::cal::shared_held(), "실패한 넣기 뒤에 캐시가 남았습니다");
    add(&path, &[&patch1()], side.lay()).unwrap();
    assert!(!archive_engine::lay::export::prepared_held() && !archive_engine::lay::cal::shared_held(), "넣기 뒤에 캐시가 남았습니다");
}

#[test]
fn the_answer_keeps_the_contract_on_scope_skips_and_range() {
    let _t = common::clock("the_answer_keeps_the_contract_on_scope_skips_and_range");
    // 고침 3회차(검토 ② — 계약이 말하는데 검사 없던 것): ① `scope` = 고쳐 쓰려 실은 트랙 수(S ∩ 조합의 트랙 — 다시 쓴 · 새 트랙을 담고 조합의 트랙 수를 넘지 않음) ·
    // 모를 때 "all" ② 할 일이 없으면 `scope: 0` · `layouts: 0` ③ `from_store`는 같은 판이면 바이트가 달라도 건너뜀 ④ DLC의 보조 달력 날짜가 표 밖이면 실제 배치로도 range.
    let side = Side::node("ap-contract", Touch::Exact);
    side.prefetch(&[vec![synth(), patch1()], vec![synth(), patch1(), patch2()]], T);
    let path = full(&side, &[synth(), patch1()], T, "ap-contract");
    let r = add(&path, &[&patch2()], side.lay()).unwrap();
    let wrote: BTreeSet<&String> = r.apply.rewrote.iter().chain(&r.apply.added).collect();
    let n = r.scope.expect("닿는 트랙을 아는 틈은 좁힌 배치");
    assert!(n >= wrote.len() && n <= common::track_count(&path), "scope {n} · 다시 쓴 · 새 트랙 {} · 조합 트랙 {}", wrote.len(), common::track_count(&path));
    assert_eq!(r.to_json()["scope"], json!(n));
    let rust = full(&Side::Rust, &[synth(), patch1()], T, "ap-contract-rust");
    // 실제 틈도 닿는 트랙을 안다(P3-16b — 짓기가 적은 `meta.rules`가 지금 판이니 좁힌다): 같은 계약.
    let rr = add(&rust, &[&patch2()], &RustLayouter).unwrap();
    let wrote: BTreeSet<&String> = rr.apply.rewrote.iter().chain(&rr.apply.added).collect();
    let n = rr.scope.expect("실제 틈도 좁힌 배치(P3-16b)");
    assert!(n >= wrote.len() && n <= common::track_count(&rust), "실제 틈 scope {n} · 다시 쓴 · 새 트랙 {} · 조합 트랙 {}", wrote.len(), common::track_count(&rust));
    assert_eq!(rr.to_json()["scope"], json!(n));
    assert!(rr.to_json()["widened"].is_null(), "넓히지 않은 넣기의 widened는 null");
    // 같은 판 · 다른 바이트는 from_store에서 건너뜀(판으로만 가른다) · 할 일이 없으니 scope 0 · 배치 0 · 저장소 그대로.
    let other = full(&side, &[synth(), patch1_same_version()], T, "ap-contract-other");
    let before = common::sha256_file(&path);
    let r = add_order(&path, &AddOrder { from_store: Some(other), ids: vec!["synth-patch".into()], ..AddOrder::default() }, side.lay()).unwrap();
    assert_eq!((r.skipped.clone(), r.replaced.len(), r.layouts), (vec!["synth-patch".to_string()], 0, 0));
    assert_eq!((r.to_json()["scope"].clone(), r.to_json()["first_pos"].clone()), (json!(0), json!(-1)));
    assert_eq!(common::sha256_file(&path), before);
    // 표 밖 보조 달력 날짜(음력 2600년 — 기본 표도 2500년까지)를 쓰는 DLC는 실제 배치에서 range.
    let text = json!({"format": "history-timeline-dlc", "formatVersion": 4, "id": "far-scene", "name": "먼 앞날 시험", "version": "0.0.1",
        "tracks": [{"id": "far", "name": "먼 나라", "color": "#a0bcc5", "order": 1, "sphere": "east-asia"}],
        "objects": [{"id": "far-1", "name": "먼 나라", "track": "far", "start": "음력 2600-01-01", "end": "음력 2610-01-01", "color": "#a9c4a0"}]});
    let far = Dlc { key: "far-scene".into(), bytes: seal_dlc(text.to_string().as_bytes()) };
    let before = common::sha256_file(&rust);
    let err = add(&rust, &[&far], &RustLayouter).unwrap_err();
    assert_eq!(code(&err), Some("range"), "{err}");
    assert_eq!(common::sha256_file(&rust), before);
}

#[test]
fn removing_a_pack_with_pictures_on_copies_gives_the_same_bytes() {
    let _t = common::clock("removing_a_pack_with_pictures_on_copies_gives_the_same_bytes");
    // 판정 R70-2(R65를 그림까지): 문서 그림이 여럿인 DLC를 빼면 그 그림들(`blobs`)을 지운다 — HashMap 차례로 지우면 같은 입력에도 바이트가 갈렸다.
    // 사본 넷에 같은 빼기 → 파일 SHA-256 모두 같음.
    let side = Side::Rust;
    const PNG: &str = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
    let count = 40;
    let objects: Vec<Value> = (0..count).map(|i| json!({"id": format!("pic-{i:02}"), "name": format!("그림 나라 {i}"), "track": "pics",
        "start": 1000 + i, "end": 1010 + i, "color": "#a9c4a0"})).collect();
    let images: Vec<Value> = (0..count).map(|i| json!({"id": format!("img-{i:02}"), "name": format!("그림-{i:02}.png"), "src": format!("data:image/png;base64,{PNG}")})).collect();
    let documents: serde_json::Map<String, Value> = (0..count).map(|i| (format!("pic-{i:02}"), json!(format!("== 개요 ==\n[[파일:그림-{i:02}.png|width=32]]\n그림 나라 {i}")))).collect();
    let text = json!({"format": "history-timeline-dlc", "formatVersion": 4, "id": "pic-scene", "name": "그림 많은 시험", "version": "0.0.1",
        "tracks": [{"id": "pics", "name": "그림 나라", "color": "#a0bcc5", "order": 1, "sphere": "east-asia"}], "objects": objects, "images": images, "documents": documents});
    let pics = Dlc { key: "pic-scene".into(), bytes: seal_dlc(text.to_string().as_bytes()) };
    let base = full(&side, &[dlc(&format!("{FIX}/east-asia.json"), &[]), pics.clone()], T, "ap-pics");
    let blobs = |path: &Path| -> i64 {
        rusqlite::Connection::open(path).unwrap().query_row("SELECT count(*) FROM blobs WHERE key<>'calendar:table'", [], |r| r.get(0)).unwrap()
    };
    assert!(blobs(&base) >= 2, "장면: 그 DLC의 그림이 여럿이어야 함({})", blobs(&base));
    let mut hashes = BTreeSet::new();
    for i in 0..4 {
        let copy = common::scratch(&format!("ap-pics-{i}"));
        std::fs::copy(&base, &copy).unwrap();
        remove(&copy, &pics.key, true, side.lay()).unwrap();
        assert_eq!(blobs(&copy), 0, "뺀 DLC의 그림은 지워진다");
        hashes.insert(common::sha256_file(&copy));
    }
    assert_eq!(hashes.len(), 1, "같은 저장소에 같은 빼기는 같은 바이트: {hashes:?}");
}

#[test]
fn layout_failures_become_refusals_with_details() {
    let _t = common::clock("layout_failures_become_refusals_with_details");
    // 판정 R61 · R59 M-1: 틈의 배치 실패는 거절로 — DLC의 날짜가 달력 표 범위 밖이면 `code` range(DLC 쪽 잘못 — 판정 R62: 쉬운 까닭 · 한계 해 ·
    // '컴퓨터에서 다시 짓기'를 가리키지 않음), 저장소의 표에 그 달력이 없으면 `code` calendar(저장소 쪽 — 새 판 시드로), 그 밖은
    // `code` layout('«DLC»를 연표에 배치하지 못했습니다 — <까닭>' · 'JS라면 …' 같은 개발자 말은 `detail`로). 저장소 그대로.
    struct Fails(&'static str);
    impl Layouter for Fails {
        fn export(&self, _: &[PackIn], _: &Opts) -> archive_engine::Result<Value> { Err(self.0.into()) }
        fn touched(&self, _: &[PackIn], _: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> { Ok(Scope::All) }
        fn needs_calendar(&self) -> bool { false }
    }
    let side = Side::node("ap-layfail", Touch::Exact);
    let path = full(&side, &[synth(), patch1()], T, "ap-layfail");
    let before = common::sha256_file(&path);
    let name = archive_engine::htpack_raw(&patch2().bytes).unwrap()["name"].as_str().unwrap().to_owned();
    let refusal = |e: &Box<dyn std::error::Error + Send + Sync>| -> (&'static str, String, Option<String>) {
        let r = e.downcast_ref::<Refusal>().unwrap_or_else(|| panic!("거절이어야 함: {e}"));
        (r.code, r.message.clone(), r.detail.clone())
    };
    let raw = "synth-patch2.htpack: 음력 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다";
    let (code, message, detail) = refusal(&add(&path, &[&patch2()], &Fails(raw)).unwrap_err());
    assert_eq!(code, "range", "DLC 쪽 잘못은 저장소 쪽(calendar)과 가른다 — 판정 R62");
    // 한계 해는 실제 표의 범위(판정 R72-1 — 내보내기가 자료 해 ± 100년으로 잘라 쓰는 것은 표 안에서의 일이라 거절은 표 밖일 때뿐).
    assert!(message.contains(&format!("«{name}»")) && message.contains("음력") && message.contains("-3500 ~ 2500년") && !message.contains("-3400")
        && !message.contains("컴퓨터에서"), "{message}");
    assert_eq!(detail.as_deref(), Some(raw));
    // 달력 모듈의 글은 달력 이름이 괄호 안('달력'을 이름으로 읽지 않는다).
    let raw = "달력 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다(음력 · -3500년 ~ 2500년)";
    let (code, message, _) = refusal(&add(&path, &[&patch2()], &Fails(raw)).unwrap_err());
    assert_eq!(code, "range");
    assert!(message.contains(&format!("«{name}»")) && message.contains("보조 달력(음력) 날짜는") && !message.contains("컴퓨터에서"), "{message}");
    // 저장소의 표에 그 달력이 없음은 저장소 쪽 — calendar 그대로(ctx 꼴 · 달력 모듈 꼴 둘 다).
    let raw = "synth-patch2.htpack: 음력 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다";
    let (code, message, _) = refusal(&add(&path, &[&patch2()], &Fails(raw)).unwrap_err());
    assert_eq!(code, "calendar");
    assert!(message.starts_with("저장소의 달력 표에 «음력»이 없어") && !message.contains("컴퓨터에서"), "{message}");
    let raw = "달력 표 없음 — 그 달력의 달 시작 표를 낼 수 없습니다(이슬람력)";
    let (code, message, _) = refusal(&add(&path, &[&patch2()], &Fails(raw)).unwrap_err());
    assert_eq!(code, "calendar");
    assert!(message.starts_with("저장소의 달력 표에 «이슬람력»이 없어") && !message.contains("컴퓨터에서"), "{message}");
    let raw = "synth-patch2.htpack: 띠의 시작이 없습니다 (JS라면 TypeError: start is undefined)";
    let (code, message, detail) = refusal(&add(&path, &[&patch2()], &Fails(raw)).unwrap_err());
    assert_eq!(code, "layout");
    assert!(message.starts_with(&format!("«{name}»")) && message.ends_with("연표에 배치하지 못했습니다 — 띠의 시작이 없습니다"), "{message}");
    assert_eq!(detail.as_deref(), Some(raw));
    // 판정 R70-4: layout은 이번에 받은 DLC 탓일 때만 — 글이 이미 든 DLC를 가리키거나(넣기) 받은 DLC가 없으면(빼기) code 없이(글에 어느 DLC인지는 남김).
    let held_name = archive_engine::htpack_raw(&patch1().bytes).unwrap()["name"].as_str().unwrap().to_owned();
    let err = add(&path, &[&patch2()], &Fails("synth-patch.htpack: 띠의 시작이 없습니다")).unwrap_err();
    assert!(err.downcast_ref::<Refusal>().is_none(), "이미 든 DLC 탓은 code 없이: {err}");
    assert!(err.to_string().contains(&format!("«{held_name}»")) && err.to_string().contains("띠의 시작이 없습니다"), "{err}");
    let err = remove(&path, "synth-patch", true, &Fails("배치 실패")).unwrap_err();
    assert!(err.downcast_ref::<Refusal>().is_none(), "받은 DLC가 없으면 code 없이: {err}");
    assert_eq!(err.to_string(), "이 DLC 조합을 연표에 배치하지 못했습니다 — 배치 실패");
    // 원본이 깨져 lay가 읽지 못함은 broken(다시 해도 같다).
    let raw = "synth-patch2.htpack: DLC를 읽을 수 없습니다 — 본문이 JSON이 아닙니다";
    let (code, _, detail) = refusal(&add(&path, &[&patch2()], &Fails(raw)).unwrap_err());
    assert_eq!((code, detail.as_deref()), ("broken", Some(raw)));
    // 판정 R72-3: broken · range도 이번에 받은 DLC 탓일 때만 그 code — 이미 든 DLC · 바탕을 가리키거나 받은 DLC가 없으면(빼기) code 없이(layout과 같은 가름 —
    // 앱이 받은 파일을 탓으로 기억하지 않게). 글에 어느 DLC인지는 남는다 · lay 문맥의 '(기본)'은 바탕의 이름으로.
    let base_name = archive_engine::htpack_raw(&synth().bytes).unwrap()["name"].as_str().unwrap().to_owned();
    for raw in ["synth-patch.htpack: DLC를 읽을 수 없습니다 — 본문이 JSON이 아닙니다", "DLC를 읽을 수 없습니다(synth-patch.htpack): 본문이 JSON이 아닙니다",
        "synth-patch.htpack: 음력 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다"] {
        let err = add(&path, &[&patch2()], &Fails(raw)).unwrap_err();
        assert!(err.downcast_ref::<Refusal>().is_none(), "이미 든 DLC 탓은 code 없이: {err}");
        assert!(err.to_string().contains(&format!("«{held_name}»")), "{err}");
    }
    let err = add(&path, &[&patch2()], &Fails("DLC를 읽을 수 없습니다(기본): 본문이 JSON이 아닙니다")).unwrap_err();
    assert!(err.downcast_ref::<Refusal>().is_none(), "바탕 탓은 code 없이: {err}");
    assert!(err.to_string().contains(&format!("«{base_name}»")) && !err.to_string().contains(&format!("«{name}»")), "받은 DLC로 오인하지 않는다: {err}");
    for raw in ["synth-patch.htpack: DLC를 읽을 수 없습니다 — 본문이 JSON이 아닙니다", "달력 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다(음력 · -3500년 ~ 2500년)"] {
        let err = remove(&path, "synth-patch", true, &Fails(raw)).unwrap_err();
        assert!(err.downcast_ref::<Refusal>().is_none(), "받은 DLC가 없으면(빼기) code 없이: {err}");
    }
    // 배치가 패닉해도 code 없는 '내부 오류'가 아니라 받은 DLC 탓 layout(고침 3회차 — 열 때마다 되풀이되지 않게).
    struct Panics;
    impl Layouter for Panics {
        fn export(&self, _: &[PackIn], _: &Opts) -> archive_engine::Result<Value> { panic!("배치 중 뜻밖의 값") }
        fn touched(&self, _: &[PackIn], _: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> { Ok(Scope::All) }
        fn needs_calendar(&self) -> bool { false }
    }
    let (code, message, _) = refusal(&add(&path, &[&patch2()], &Panics).unwrap_err());
    assert_eq!(code, "layout");
    assert!(message.starts_with(&format!("«{name}»")) && message.contains("배치 중 뜻밖의 값"), "{message}");
    // apply 걸음의 DLC 내용 탓(이름 없는 항목 기록)도 받은 DLC 탓 layout.
    struct NoUid;
    impl Layouter for NoUid {
        fn export(&self, packs: &[PackIn], opts: &Opts) -> archive_engine::Result<Value> {
            let mut plan = RustLayouter.export(packs, opts)?;
            plan["entities"].as_array_mut().unwrap().push(json!({"uid": "", "kind": "doc", "json": "{}"}));
            Ok(plan)
        }
        fn touched(&self, _: &[PackIn], _: &[PackIn], _: &Opts) -> archive_engine::Result<Scope> { Ok(Scope::All) }
        fn needs_calendar(&self) -> bool { false }
    }
    let real = full(&Side::Rust, &[synth(), patch1()], T, "ap-layfail-real");
    let real_before = common::sha256_file(&real);
    let (code, message, _) = refusal(&add(&real, &[&patch2()], &NoUid).unwrap_err());
    assert_eq!(code, "layout");
    assert!(message.starts_with(&format!("«{name}»")) && message.contains("항목 기록에 id가 없습니다"), "{message}");
    assert_eq!(common::sha256_file(&real), real_before);
    assert_eq!(common::sha256_file(&path), before);
}

#[test]
fn broken_originals_are_refused_as_broken() {
    let _t = common::clock("broken_originals_are_refused_as_broken");
    // 판정 R70-1: 받은 파일의 형식 실패(몸통만 깨진 .htpack — 앱의 머리 검사는 통과하는 꼴 · JSON이 아님 · DLC 본문이 아님 · id 없음)와 다른 저장소의
    // 원본이 다른 DLC인 것은 `code` broken(다시 해도 같다). 파일을 읽지 못함(입출력 — 없는 파일)은 code 없이. 저장소 그대로.
    let side = Side::Rust;
    let path = full(&side, &[synth(), patch1()], T, "ap-broken-files");
    let before = common::sha256_file(&path);
    let dir = std::env::temp_dir().join(format!("archive-correct-{}-ap-broken-files", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut body_cut = patch2().bytes;
    let at = body_cut.len() - 3;
    body_cut[at] ^= 0x5a;
    for (what, name, bytes) in [("몸통만 깨짐", "cut.htpack", body_cut), ("JSON 아님", "text.json", b"{\"format\":".to_vec()),
        ("DLC 본문 아님", "other.json", br#"{"format":"something-else","id":"x"}"#.to_vec()),
        ("id 없음", "noid.json", r#"{"format":"history-timeline-dlc","formatVersion":4,"name":"id 없는 기록집"}"#.as_bytes().to_vec())] {
        let file = dir.join(name);
        std::fs::write(&file, bytes).unwrap();
        let err = add_order(&path, &AddOrder { files: vec![file], ..AddOrder::default() }, side.lay()).unwrap_err();
        assert_eq!(code(&err), Some("broken"), "{what}: {err}");
    }
    let err = add_order(&path, &AddOrder { files: vec![dir.join("없는.htpack")], ..AddOrder::default() }, side.lay()).unwrap_err();
    assert_eq!(code(&err), None, "입출력 실패는 code 없이: {err}");
    // 다른 저장소의 그 id 자리에 다른 DLC의 원본.
    let old = full(&side, &[synth(), patch1()], T, "ap-broken-other");
    {
        let db = rusqlite::Connection::open(&old).unwrap();
        let keys: Value = serde_json::from_str(&db.query_row("SELECT value FROM meta WHERE key='pack_keys'", [], |r| r.get::<_, String>(0)).unwrap()).unwrap();
        let number: i64 = keys.as_object().unwrap().iter().find(|(_, v)| v.as_str() == Some("synth-patch")).unwrap().0.parse().unwrap();
        db.execute("UPDATE packs SET original=?1 WHERE id=?2", rusqlite::params![patch2().bytes, number]).unwrap();
    }
    let seed = full(&side, &[synth()], T, "ap-broken-seed2");
    let err = add_order(&seed, &AddOrder { from_store: Some(old), ids: vec!["synth-patch".into()], ..AddOrder::default() }, side.lay()).unwrap_err();
    assert_eq!(code(&err), Some("broken"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn a_shelf_holding_a_higher_version_of_a_held_pack_is_not_lost() {
    let _t = common::clock("a_shelf_holding_a_higher_version_of_a_held_pack_is_not_lost");
    // 고침 3회차(검토 ① Minor 4): 조합(원본 없이 — 메이커 배치)과 보관함에 같은 id가 함께 있을 때 — 넣는 판은 보관함의 판과도 견준다(낮으면 version ·
    // 넣으면 보관함에서 빠지므로 높은 판 원본을 잃지 않게).
    let side = Side::Rust;
    let s = full(&side, &[synth(), patch1_v11()], T, "ap-shelf-held");
    remove(&s, "synth-patch", false, side.lay()).unwrap();
    let mut plan = side.plan(&[synth(), patch1()], T);
    plan["now"] = json!(iso_at(T, TZ));
    let layout = common::scratch("ap-shelf-held-layout").with_extension("htlayout");
    std::fs::write(&layout, common::plans::htlayout(&plan)).unwrap();
    let order = archive_engine::patch::read_order(&layout, &[], Vec::new(), archive_engine::patch::CoversAsk::Default).unwrap();
    write(&s, |tx| archive_engine::patch::run_order(tx, &order)).unwrap();
    let before = common::sha256_file(&s);
    let err = add(&s, &[&patch1()], side.lay()).unwrap_err();
    assert_eq!(code(&err), Some("version"), "{err}");
    assert!(err.to_string().contains("보관함"), "{err}");
    assert_eq!(common::sha256_file(&s), before);
    // 높은 판(보관함과 같은 판)은 들어간다.
    add(&s, &[&patch1_v11()], side.lay()).unwrap();
}

#[test]
fn the_same_step_on_copies_gives_the_same_bytes() {
    let _t = common::clock("the_same_step_on_copies_gives_the_same_bytes");
    // 판정 R65(perf 작업자가 찾음): 같은 저장소의 사본들에 같은 넣기 · 빼기를 하면 파일 바이트까지 같다 — 배치에서 사라진 항목 기록을 HashMap 차례로 지우면
    // canon은 같아도 쪽 배치가 달라 바이트가 갈렸다(`patch::put_entities`). 뺀 DLC 제 기록은 그 앞 걸음(`drop_packs`)이 자료집째 지우므로, 그 길에 닿는 것은
    // **남는 DLC의 기록이 사라질 때**다 — 여기서는 기록을 많이 줄인 높은 판으로 바꿔 넣기. 지우는 기록이 여러 쪽에 걸쳐야 차례가 바이트에 드러난다.
    let side = Side::Rust;
    let bulk = |version: &str, count: usize| -> Dlc {
        let objects: Vec<Value> = (0..count).map(|i| json!({"id": format!("bulk-{i:03}"), "name": format!("많은 나라 {i}"), "track": "bulk",
            "start": 1000 + i, "end": 1006 + i, "color": "#a9c4a0"})).collect();
        let text = json!({"format": "history-timeline-dlc", "formatVersion": 4, "id": "bulk-scene", "name": "많은 기록 시험", "version": version,
            "tracks": [{"id": "bulk", "name": "많은 나라", "color": "#a0bcc5", "order": 1, "sphere": "east-asia"}], "objects": objects});
        Dlc { key: "bulk-scene".into(), bytes: seal_dlc(text.to_string().as_bytes()) }
    };
    let (many, few) = (bulk("0.0.1", 400), bulk("0.0.2", 10));
    let base = full(&side, &[dlc(&format!("{FIX}/east-asia.json"), &[]), many.clone()], T, "ap-bytes");
    let uids = |path: &Path| -> BTreeSet<String> {
        let db = rusqlite::Connection::open(path).unwrap();
        let mut stmt = db.prepare("SELECT uid FROM entities").unwrap();
        let out = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap().map(Result::unwrap).collect();
        out
    };
    let steps: [(&str, &dyn Fn(&Path)); 2] = [
        ("기록을 줄인 높은 판으로 바꿔 넣기", &|p: &Path| { add(p, &[&few], side.lay()).unwrap(); }),
        ("빼기", &|p: &Path| { remove(p, &many.key, true, side.lay()).unwrap(); }),
    ];
    for (what, step) in steps {
        let mut hashes = BTreeSet::new();
        for i in 0..4 {
            let copy = common::scratch(&format!("ap-bytes-{i}"));
            std::fs::copy(&base, &copy).unwrap();
            step(&copy);
            if i == 0 {
                let gone = uids(&base).difference(&uids(&copy)).count();
                assert!(gone >= 200, "장면({what}): 지우는 항목 기록이 많아야 함({gone})");
            }
            hashes.insert(common::sha256_file(&copy));
        }
        assert_eq!(hashes.len(), 1, "같은 저장소에 같은 {what}는 같은 바이트: {hashes:?}");
    }
}

#[test]
fn an_unreadable_original_in_another_store_is_refused_as_broken() {
    let _t = common::clock("an_unreadable_original_in_another_store_is_refused_as_broken");
    // 판정 R68 ①: 다른 저장소(옛 휴대폰 저장소)의 원본이 깨져 읽을 수 없으면 `code` broken — 다시 해도 같으니 앱이 시드 잇기를 켤 때마다 되풀이하지 않게.
    let side = Side::Rust;
    let old = full(&side, &[synth(), patch1()], T, "ap-broken-old");
    {
        let db = rusqlite::Connection::open(&old).unwrap();
        let keys: Value = serde_json::from_str(&db.query_row("SELECT value FROM meta WHERE key='pack_keys'", [], |r| r.get::<_, String>(0)).unwrap()).unwrap();
        let number: i64 = keys.as_object().unwrap().iter().find(|(_, v)| v.as_str() == Some("synth-patch")).unwrap().0.parse().unwrap();
        db.execute("UPDATE packs SET original=x'00010203' WHERE id=?1", [number]).unwrap();
    }
    let seed = full(&side, &[synth()], T, "ap-broken-seed");
    let before = common::sha256_file(&seed);
    let err = add_order(&seed, &AddOrder { from_store: Some(old), ids: vec!["synth-patch".into()], ..AddOrder::default() }, side.lay()).unwrap_err();
    assert_eq!(code(&err), Some("broken"), "{err}");
    assert!(err.to_string().contains("DLC를 읽을 수 없습니다"), "{err}");
    assert_eq!(common::sha256_file(&seed), before);
}

#[test]
fn another_store_left_mid_write_is_rolled_back_and_read() {
    let _t = common::clock("another_store_left_mid_write_is_rolled_back_and_read");
    // 고침 2회차(R59 M-7): 다른 저장소(from_store)에 쓰다 죽어 남은 일지(hot journal)가 있어도 `Store::open`과 같은 길로 되돌린 뒤 읽는다
    // (읽기 전용 연결은 일지를 되돌리지 못해 SQLITE_READONLY로 실패했다).
    use rusqlite::TransactionBehavior;
    let side = Side::node("ap-hot", Touch::Exact);
    side.prefetch(&[vec![synth(), patch1(), patch2()], vec![synth()]], T);
    let old = full(&side, &[synth(), patch1(), patch2()], T, "ap-hot-old");
    let dead = common::scratch("ap-hot-dead");
    let before = common::sha256_file(&old);
    {
        let mut db = rusqlite::Connection::open(&old).unwrap();
        db.execute_batch("PRAGMA cache_size=1").unwrap();
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate).unwrap();
        tx.execute("UPDATE events SET body=body||printf('%.4000c','x')", []).unwrap(); // 쪽이 넘치게 길게
        std::fs::copy(&old, &dead).unwrap();
        std::fs::copy(format!("{}-journal", old.display()), format!("{}-journal", dead.display())).expect("캐시가 넘쳐 일지가 생겼어야 한다");
        tx.rollback().unwrap();
    }
    assert_ne!(common::sha256_file(&dead), before, "장면: 복사본은 쓰다 만 디스크(캐시가 넘쳐 파일이 이미 고쳐졌다)");
    let probe = rusqlite::Connection::open_with_flags(&dead, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let why = probe.query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get::<_, i64>(0)).expect_err("장면: 읽기 전용으로는 일지를 되돌릴 수 없다");
    drop(probe);
    assert!(matches!(&why, rusqlite::Error::SqliteFailure(e, _) if e.extended_code == 776), "{why:?}");
    let seed = full(&side, &[synth()], T, "ap-hot-seed");
    let r = add_order(&seed, &AddOrder { from_store: Some(dead.clone()), ids: vec!["synth-patch".into(), "synth-patch2".into()], ..AddOrder::default() }, side.lay()).unwrap();
    assert_eq!(r.packs, ["synth-world", "synth-patch", "synth-patch2"]);
    assert!(!Path::new(&format!("{}-journal", dead.display())).exists(), "되돌린 뒤 일지는 지워진다");
    same_store(&seed, &full(&side, &[synth(), patch1(), patch2()], T, "ap-hot-full"), "일지가 남은 다른 저장소의 원본", &[]);
}

#[test]
fn prefer_given_lets_a_lower_preview_version_in() {
    let _t = common::clock("prefer_given_lets_a_lower_preview_version_in");
    // 판정 R39: 메이커 미리보기('연표로 ↗' — 서재의 임시 사본 위에 작업본)는 같은 id면 판과 상관없이 작업본이 이긴다 — `prefer_given`이면 낮은 판도 들어가
    // 그 id를 바꾸고(`replaced`) 그 조합의 통째 짓기와 같다. 기본(거짓)은 낮은 판을 `code` version으로 거절(저장소 그대로).
    let side = Side::node("ap-prefer", Touch::Exact);
    let path = full(&side, &[synth(), patch1()], T, "ap-prefer");
    let before = common::sha256_file(&path);
    let low = patch1_v09();
    let err = add(&path, &[&low], side.lay()).unwrap_err();
    assert_eq!(code(&err), Some("version"), "{err}");
    assert_eq!(common::sha256_file(&path), before);
    let order = AddOrder { files: vec![low.file()], prefer_given: true, ..AddOrder::default() };
    let r = add_order(&path, &order, side.lay()).unwrap();
    assert_eq!((r.replaced.len(), r.replaced[0].old_version.as_str(), r.replaced[0].new_version.as_str()), (1, "1.0.0", "0.9.0"));
    same_store(&path, &full(&side, &[synth(), low], T, "ap-prefer-full"), "미리보기 작업본(낮은 판)", &[]);
    let q = archive_engine::packs::add_order(&json!({"op":"add_pack","files":["x.htpack"],"prefer_given":true})).unwrap();
    assert!(q.prefer_given && !archive_engine::packs::add_order(&json!({"op":"add_pack","files":["x.htpack"]})).unwrap().prefer_given);
}

#[test]
fn the_calendar_table_survives_add_and_remove() {
    let _t = common::clock("the_calendar_table_survives_add_and_remove");
    // 짓기(과제 17)가 넣은 달력 표는 배치의 그림이 아니다 — 넣고 빼기(온 판이 바뀌어 그림을 맞추는 길)가 지우지 않는다.
    let side = Side::node("ap-cal", Touch::Exact);
    let path = full(&side, &[synth()], T, "ap-cal");
    add(&path, &[&patch1()], side.lay()).unwrap();
    remove(&path, "synth-patch", true, side.lay()).unwrap();
    let db = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(archive_engine::lay::calendar_of(&db).unwrap().as_deref(), Some(&*calendar_slice()));
}

// ---------------------------------------------------------------- 하위 배치를 그대로(`Covers::Part`) — 장면(`plans.rs`) · Node 없이

/// 조합 `from` → `to`를 하위 배치로: S = 지문이 바뀐 트랙(새 조합의 것)으로 시작해 넓히기([`Widen`])를 따라 다시 자른다.
fn part_step(path: &Path, from: &[&str], to: &[&str]) -> (archive_engine::patch::ApplyReport, usize) {
    use common::plans::{packs_of, plan};
    let (old, new) = (prints(&plan(from)).unwrap(), plan(to));
    let p = prints(&new).unwrap();
    let mut s: BTreeSet<String> = p.order.iter().filter(|k| old.tracks.get(*k).map(|t| &t.print) != Some(&p.tracks[*k].print)).cloned().collect();
    let remove: Vec<String> = from.iter().filter(|k| !to.contains(k)).map(|k| k.trim_end_matches("@2").to_string())
        .filter(|k| !to.iter().any(|t| t.trim_end_matches("@2") == k)).collect();
    let o = packs_of(to);
    for widen in 0.. {
        let sub = sub_plan(&new, &s).unwrap();
        let covers = Covers::Part { tracks: s.clone(), order: p.order.clone() };
        match write(path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &o, covers, remove: &remove })) {
            Ok(r) => return (r, widen),
            Err(e) => {
                let w = e.downcast_ref::<Widen>().unwrap_or_else(|| panic!("{from:?} → {to:?}: {e}")).0.clone();
                assert!(!w.is_subset(&s), "넓히기가 늘지 않음: {w:?}");
                s.extend(w);
            }
        }
    }
    unreachable!()
}

#[test]
fn sub_plans_apply_like_full_builds_on_the_scenes() {
    let _t = common::clock("sub_plans_apply_like_full_builds_on_the_scenes");
    // `Covers::Part`(조합 전부를 말하되 트랙은 S만): 장면(판 · 가림 · 변형 · 남의 트랙에 얹기 · 띠 번호 칸 · 그림 없는 조합)의 넣기 · 빼기 · 색 바꿈을
    // 지문이 바뀐 트랙만 실은 하위 배치로 넣어도 통째 짓기와 같다(넓히기 포함).
    use common::plans::{packs_of, plan};
    let walks: [&[&[&str]]; 5] = [
        &[&["a"], &["a", "b"], &["a", "b", "c"]],
        &[&["a"], &["a", "c"], &["a", "b", "c"], &["a", "c"]],
        &[&["a", "b", "c"], &["a"], &["a", "b"], &["a", "b", "c"]],
        &[&["a", "b"], &["a", "b", "c"], &["a", "c"], &["a"], &["a", "c"]],
        &[&["a", "c"], &["a@2", "c"], &["a@2", "b", "c"], &["a", "b", "c"]],
    ];
    let mut widened = 0;
    for (w, sets) in walks.iter().enumerate() {
        let path = common::scratch(&format!("ap-part{w}"));
        import_layout_value(&plan(sets[0]), &packs_of(sets[0]), &path).unwrap();
        for i in 1..sets.len() {
            let (_, n) = part_step(&path, sets[i - 1], sets[i]);
            widened += n;
            let want = common::scratch(&format!("ap-part{w}-{i}-full"));
            import_layout_value(&plan(sets[i]), &packs_of(sets[i]), &want).unwrap();
            same_store(&path, &want, &format!("Part {w}-{i} {:?}", sets[i]), &["now"]);
        }
    }
    eprintln!("장면 하위 배치: 넓히기 {widened}번");
    assert!(widened > 0, "넓히기를 한 번도 지나지 않았습니다(장면 c는 b의 띠를 가리킨다)");
}

#[test]
fn a_part_layout_without_a_needed_track_widens_instead_of_writing() {
    let _t = common::clock("a_part_layout_without_a_needed_track_widens_instead_of_writing");
    // S 밖인데 다시 써야 하는 트랙이 있으면 쓰기 전에 넓히기로 거절하고 저장소는 그대로: b를 더하면 지문이 바뀌는 트랙은 ta(b가 얹음) · tb(새것)뿐인데
    // ta를 가리는 판 트랙도 가리기 번호를 다시 풀어야 한다(판정 R16 — 지문은 그대로).
    use common::plans::{packs_of, plan};
    let path = common::scratch("ap-part-widen");
    import_layout_value(&plan(&["a"]), &packs_of(&["a"]), &path).unwrap();
    let before = common::sha256_file(&path);
    let (old, new) = (prints(&plan(&["a"])).unwrap(), plan(&["a", "b"]));
    let p = prints(&new).unwrap();
    let s: BTreeSet<String> = p.order.iter().filter(|k| old.tracks.get(*k).map(|t| &t.print) != Some(&p.tracks[*k].print)).cloned().collect();
    assert_eq!(s, ["ta", "tb"].into_iter().map(str::to_owned).collect(), "장면: 지문이 바뀐 트랙");
    let sub = sub_plan(&new, &s).unwrap();
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &packs_of(&["a", "b"]), covers: Covers::Part { tracks: s.clone(), order: p.order.clone() }, remove: &[] }))
        .unwrap_err();
    let w = err.downcast_ref::<Widen>().unwrap_or_else(|| panic!("넓히기여야 함: {err}"));
    assert_eq!(w.0, ["board:__board:view:a1"].into_iter().map(str::to_owned).collect(), "{w:?}");
    assert_eq!(common::sha256_file(&path), before);
    // 조합의 트랙 차례에 없는 트랙을 S에 담으면 거절.
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &packs_of(&["a", "b"]),
        covers: Covers::Part { tracks: s.clone(), order: vec!["ta".into()] }, remove: &[] })).unwrap_err().to_string();
    assert!(err.contains("트랙 차례에 없습니다"), "{err}");
}

/// 시험 DLC — JSON 본문을 싼다(형식 3).
fn probe(id: &str, key: &str, body: Value) -> Dlc {
    let mut d = json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": id, "name": format!("시험 {id}"), "version": "0.0.1", "tracks": [] });
    d[key] = body;
    let bytes = seal_dlc(&serde_json::to_vec(&d).unwrap());
    Dlc { key: id.to_owned(), bytes }
}

#[test]
fn a_board_that_comes_or_goes_widens_to_its_member_tracks() {
    // 판정 R54 I2: 뺀 판(`boards.mjs`가 판 셈 오류로 빼는 판)이 서거나 사라지면 닿는 트랙(배치 없이 짐작 — 앞 · 뒤 모두 '있음')은 모른다. 판을 켠 배치의 변형 판
    // 항목은 구성 트랙(synth-lay의 bb)에 실리므로 apply(Part)가 저장소 대비 서거나 사라지는 판의 `row_targets` · `hides` 가운데 S 밖 트랙으로 넓힌다 —
    // 실제 틈으로 넣고 빼도 통째 짓기와 같다. 재현(검토): synth-lay + 늦은 공통 시대 250–300(xe) ± sdg2 시작 205(xf6) · sdg1 시작 201(xf5).
    let synth_lay = dlc(&format!("{FIX}/synth-lay.json"), &[]);
    let xe = probe("xe", "epochs", json!([{ "id": "xe1", "name": "늦은 공통 시대", "start": 250, "end": 300 }]));
    let xf5 = probe("xf5", "patches", json!([{ "target": "synth-lay/p-sdg1", "set": { "start": 201 } }]));
    let xf6 = probe("xf6", "patches", json!([{ "target": "synth-lay/p-sdg2", "set": { "start": 205 } }]));
    let side = Side::Rust;
    let base = [synth_lay.clone(), xe.clone()];
    let base_full = full(&side, &base, T, "ap-flip-base");
    let mut widened = 0;
    for p in [&xf6, &xf5] {
        let tag = format!("ap-flip-{}", p.key);
        let path = common::scratch(&tag);
        std::fs::copy(&base_full, &path).unwrap();
        let r = add(&path, &[p], side.lay()).unwrap_or_else(|e| panic!("{tag} 넣기: {e}"));
        eprintln!("{tag} 넣기: 범위 {:?} · 배치 {}번 · 다시 쓴 트랙 {:?} · 새 트랙 {:?} · 사라진 트랙 {:?}", r.scope, r.layouts, r.apply.rewrote, r.apply.added, r.apply.removed);
        // 16b 검토 ① M-1: 실제 틈이 좁힌 배치에서 넓히기를 지났는가(빈 시험이 아니게 — 아래에서 모아 단언).
        widened += usize::from(r.scope.is_some() && r.layouts > 1);
        let with: Vec<Dlc> = base.iter().cloned().chain([p.clone()]).collect();
        same_store(&path, &full(&side, &with, T, &format!("{tag}-full")), &format!("뺀 판 뒤집힘 — {} 넣기", p.key), &[]);
        let r = remove(&path, &p.key, true, side.lay()).unwrap_or_else(|e| panic!("{tag} 빼기: {e}"));
        eprintln!("{tag} 빼기: 범위 {:?} · 배치 {}번 · 다시 쓴 트랙 {:?} · 사라진 트랙 {:?}", r.scope, r.layouts, r.apply.rewrote, r.apply.removed);
        same_store(&path, &base_full, &format!("뺀 판 뒤집힘 — {} 빼기", p.key), &[]);
    }
    assert!(widened > 0, "실제 틈이 좁힌 배치로 넓히기를 한 번도 지나지 않았습니다(빈 시험)");
}

/// 저장소의 줄 묶음 [0, `chunks`)의 표본 타일 — `(단계, 통, 묶음, SHA-256)`(단계 넷 · 보는 범위의 통 가운데 단계마다 많아야 41장 · 묶음 많아야 스물다섯 · 켠 자료집은 저장소의 것 전부).
fn front_tiles(path: &Path, chunks: i64) -> Vec<(usize, i64, i64, String)> {
    use archive_engine::levels::tile_of;
    use archive_engine::tile::{build_tile, TileRequest};
    use sha2::Digest as _;
    let db = rusqlite::Connection::open(path).unwrap();
    let packs: Vec<i64> = db.prepare("SELECT id FROM packs ORDER BY id").unwrap().query_map([], |r| r.get(0)).unwrap().map(|x| x.unwrap()).collect();
    let meta_i = |key: &str| -> i64 { db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0)).unwrap().parse().unwrap() };
    let (lo, hi) = (meta_i("min"), meta_i("max"));
    drop(db);
    let store = archive_engine::Store::open(path).unwrap();
    // 묶음은 많아야 스물넷 남짓을 고르게 — first_pos 바로 앞 묶음(바뀐 곳에 가장 가까운 것)은 늘 든다.
    let mut picked: Vec<i64> = (0..chunks).step_by(((chunks / 24).max(1)) as usize).collect();
    if chunks > 0 && picked.last() != Some(&(chunks - 1)) {
        picked.push(chunks - 1);
    }
    let mut out = Vec::new();
    for level in [0usize, 4, 7, 11] {
        let (a, b) = (tile_of(lo, level), tile_of(hi, level));
        let step = ((b - a) / 40).max(1);
        for x in (a..=b).step_by(step as usize) {
            for &chunk in &picked {
                let req = TileRequest { level, x, chunk, packs: packs.clone(), filter: None, variants: None };
                let bytes = build_tile(&store, &req).unwrap();
                out.push((level, x, chunk, format!("{:x}", sha2::Sha256::digest(&bytes))));
            }
        }
    }
    out
}

#[test]
fn tiles_before_first_pos_keep_their_bytes() {
    // 판정 R60: 앱의 keepChunks는 'apply 답의 first_pos 앞 줄 묶음 타일은 바이트가 같다'에 기댄다 — 부분 셈(`Covers::Part`)이 S 밖 트랙의 사건 · 띠 번호를
    // 바꾸면 앞 타일이 낡은 번호를 그린다. 실제 틈으로 넣고 빼는 장면마다 first_pos 앞 묶음의 표본 타일이 고쳐 쓰기 전과 바이트까지 같다(날짜 칸 이음 번호 ·
    // notes를 옮기는 "renumber"는 타일에 들지 않는다 — 날짜 칸은 뼈대 · notes는 점검 글이라 first_pos를 앞당기지 않는다).
    use archive_engine::levels::CHUNK_ROWS;
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let (d7, dep) = (dlc(&format!("{FIX}/d7-test.htpack"), &[]), dlc(&format!("{FIX}/dep-scene.htpack"), &[]));
    let synth_lay = dlc(&format!("{FIX}/synth-lay.json"), &[]);
    let xe = probe("xe", "epochs", json!([{ "id": "xe1", "name": "늦은 공통 시대", "start": 250, "end": 300 }]));
    let xf6 = probe("xf6", "patches", json!([{ "target": "synth-lay/p-sdg2", "set": { "start": 205 } }]));
    let side = Side::Rust;
    let p2 = patch2();
    // 끝에 서는 새 트랙 하나(렌즈 자료 · 남의 항목 없음) — 첫 트랙이 다시 써지지 않아 first_pos가 0이 아닌 장면(다른 장면은 렌즈 변형이 실린 첫 트랙이
    // 다시 써져 first_pos가 0 — 견줄 앞 묶음이 없다).
    let tail = |id: &str, start: i64| -> Dlc {
        let d = json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": id, "name": format!("시험 {id}"), "version": "0.0.1",
            "tracks": [{ "id": id, "name": format!("끝 시험 트랙 {id}"), "order": 999 }],
            "periods": [{ "id": "t1", "track": id, "name": "끝 나라", "start": start, "end": start + 80 }] });
        Dlc { key: id.to_owned(), bytes: seal_dlc(&serde_json::to_vec(&d).unwrap()) }
    };
    let (ea_tail, syn_tail) = (tail("xtail", 1200), tail("ytail", 150));
    // (이름, 처음 조합, 넣을 것 — 없으면 마지막 DLC를 뺌)
    let scenes: [(&str, Vec<Dlc>, Option<&Dlc>); 10] = [
        ("동아시아 + d7", vec![ea.clone()], Some(&d7)),
        ("동아시아 + d7 − d7", vec![ea.clone(), d7.clone()], None),
        ("동아시아 + dep", vec![ea.clone()], Some(&dep)),
        ("동아시아 + 끝 트랙", vec![ea.clone()], Some(&ea_tail)),
        ("동아시아 + 끝 트랙 − 끝 트랙", vec![ea.clone(), ea_tail.clone()], None),
        ("합성 + 패치 + 패치 둘", vec![synth(), patch1()], Some(&p2)),
        ("합성 + 패치 둘 + 패치 − 패치", vec![synth(), patch2(), patch1()], None),
        ("합성 + 패치 + 끝 트랙", vec![synth(), patch1()], Some(&syn_tail)),
        ("합성 + 끝 트랙 + 패치 둘", vec![synth(), syn_tail.clone()], Some(&p2)),
        ("synth-lay + xe + xf6(판이 섬)", vec![synth_lay, xe], Some(&xf6)),
    ];
    let mut compared = 0;
    for (i, (name, start, put)) in scenes.iter().enumerate() {
        let path = full(&side, start, T, &format!("ap-front{i}"));
        let before = common::scratch(&format!("ap-front{i}-before"));
        std::fs::copy(&path, &before).unwrap();
        let r = match put {
            Some(d) => add(&path, &[d], side.lay()),
            None => remove(&path, &start.last().unwrap().key, true, side.lay()),
        }.unwrap_or_else(|e| panic!("{name}: {e}"));
        let first = r.apply.first_pos;
        let chunks = if first < 0 { (r.apply.rows_after + CHUNK_ROWS - 1) / CHUNK_ROWS } else { first / CHUNK_ROWS };
        let (old, new) = (front_tiles(&before, chunks), front_tiles(&path, chunks));
        eprintln!("{name}: 범위 {:?} · first_pos {first} · 앞 묶음 {chunks} · 타일 {}장 · 다시 쓴 트랙 {:?} · 새 트랙 {:?}", r.scope, old.len(), r.apply.rewrote, r.apply.added);
        assert_eq!(new, old, "{name}: first_pos({first}) 앞 묶음의 타일이 고쳐 쓰기 전과 다릅니다");
        compared += old.len();
    }
    assert!(compared > 0, "first_pos 앞 묶음을 하나도 견주지 못했습니다(빈 시험)");
    // 16b 검토 ① M-3: 연호 · 도읍이 있는 끝 트랙 — 연호 이음이 늘어 앞 트랙 모두의 도읍 이음 번호가 밀린다("renumber"가 옮김). 앞 타일 바이트 + 통째 짓기와 canon.
    let d = json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": "xera", "name": "시험 xera", "version": "0.0.1",
        "tracks": [{ "id": "xera", "name": "끝 연호 트랙", "order": 999 }],
        "periods": [{ "id": "t1", "track": "xera", "name": "끝 연호 나라", "start": 1200, "end": 1300,
            "eras": [{ "name": "끝원", "start": 1200, "end": 1240 }, { "name": "끝화", "start": 1240, "end": 1300 }],
            "capitals": [{ "city": "끝성", "start": 1200 }, { "city": "새끝성", "start": 1250 }] }] });
    let era_tail = Dlc { key: "xera".into(), bytes: seal_dlc(&serde_json::to_vec(&d).unwrap()) };
    let path = full(&side, &[ea.clone()], T, "ap-front-era");
    let before = common::scratch("ap-front-era-before");
    std::fs::copy(&path, &before).unwrap();
    let r = add(&path, &[&era_tail], side.lay()).unwrap();
    let chunks = r.apply.first_pos / CHUNK_ROWS;
    assert!(r.scope.is_some() && chunks > 0, "연호 끝 트랙: 좁은 넣기 · first_pos > 0이어야 합니다({:?} · {})", r.scope, r.apply.first_pos);
    assert_eq!(front_tiles(&path, chunks), front_tiles(&before, chunks), "연호 끝 트랙: first_pos 앞 묶음의 타일");
    same_store(&path, &full(&side, &[ea.clone(), era_tail], T, "ap-front-era-full"), "연호 끝 트랙", &[]);
}

/// 장면 배치의 날짜 칸 이음 번호를 트랙마다 · 갈래(연호 · 도읍과 배도)마다 옮긴다 — 앞 트랙이 바뀌어 온 판 번호가 밀린 꼴(판정 R45).
fn shift_strips(p: &Value, by: &[(i64, i64, i64)]) -> Value {
    let mut out = p.clone();
    for a in out["axis"].as_array_mut().unwrap() {
        let (t, strip, kind) = (a["track"].as_i64().unwrap(), a["strip"].as_i64().unwrap(), a["kind"].as_i64().unwrap());
        if let Some((_, era, cap)) = by.iter().find(|(track, _, _)| *track == t).filter(|_| strip != 0) {
            a["strip"] = json!(strip + if kind == 2 { era } else { cap });
        }
    }
    out
}

#[test]
fn strips_of_kept_tracks_are_renumbered_like_a_full_build() {
    // 판정 R45(1): 지문은 이음 번호를 트랙 안 거리로만 보므로(`patch::prints`) 앞 트랙이 바뀌어 번호만 밀린 트랙은 다시 쓰지 않는다 — "relink"가 그 트랙의
    // 저장소 번호를 새 번호로 옮겨 canon · 지문이 통째 짓기와 같다. 모두 덮는 배치(`All` — 배치의 날짜 칸에서)와 하위 배치(`Part` — S 밖 트랙은 `stripFirst`에서) 둘 다.
    // 장면에 도읍 칸과 연호의 틈(건너뛴 번호)을 더해 갈래마다 · 틈째 옮기는지도 본다.
    use common::plans::{packs_of, plan};
    let set = ["a", "b", "c"];
    let mut base = plan(&set);
    let ta_era = base["axis"].as_array().unwrap().iter().find(|a| a["track"] == 0 && a["kind"] == 2).cloned().unwrap();
    let mut gap = ta_era.clone(); // 연호 하나를 건너뛴 다음 이음(7 → 9)
    gap["start"] = json!(ta_era["end"].as_i64().unwrap() + 1);
    gap["end"] = json!(ta_era["end"].as_i64().unwrap() + 1000);
    gap["strip"] = json!(ta_era["strip"].as_i64().unwrap() + 2);
    gap["seq"] = json!(1);
    let mut cap = ta_era.clone();
    cap["kind"] = json!(3);
    cap["strip"] = json!(20);
    base["axis"].as_array_mut().unwrap().extend([gap, cap]);
    let tc = base["tracks"].as_array().unwrap().iter().position(|t| t["key"] == "tc").unwrap() as i64;
    let moved = shift_strips(&base, &[(0, 5, 11), (tc, 2, 0)]);
    let (pb, pm) = (prints(&base).unwrap(), prints(&moved).unwrap());
    assert_eq!(pb, pm, "이음 번호만 밀린 배치의 지문이 같아야 합니다");
    let want = common::scratch("ap-strip-full");
    import_layout_value(&moved, &packs_of(&set), &want).unwrap();
    // 모두 덮는 배치.
    let path = common::scratch("ap-strip-all");
    import_layout_value(&base, &packs_of(&set), &path).unwrap();
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &moved, originals: &packs_of(&set), covers: Covers::All, remove: &[] })).unwrap();
    assert!(r.rewrote.is_empty() && r.added.is_empty() && !r.globals, "다시 쓰는 트랙이 없어야 합니다: {r:?}");
    same_store(&path, &want, "이음 번호 옮김(All)", &["now"]);
    // 하위 배치 — 다시 쓸 트랙 없이(S = ∅) 조합 전부의 차례와 이음의 첫 값만.
    let path = common::scratch("ap-strip-part");
    import_layout_value(&base, &packs_of(&set), &path).unwrap();
    let sub = sub_plan(&moved, &BTreeSet::new()).unwrap();
    assert_eq!(sub["stripFirst"]["ta"], json!([12, 31]), "{}", sub["stripFirst"]);
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &sub, originals: &packs_of(&set), covers: Covers::Part { tracks: BTreeSet::new(), order: pm.order.clone() }, remove: &[] }))
        .unwrap();
    assert!(r.rewrote.is_empty() && r.added.is_empty(), "{r:?}");
    same_store(&path, &want, "이음 번호 옮김(Part)", &["now"]);
    // 덮는 트랙만 주는 배치(판정 R59 I-2 — 덮는 꼴 셋 모두): 덮는 트랙(ta · tc)의 저장소 번호를 배치의 번호로.
    let path = common::scratch("ap-strip-tracks");
    import_layout_value(&base, &packs_of(&set), &path).unwrap();
    let covers = Covers::Tracks(["ta", "tc"].into_iter().map(String::from).collect());
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &moved, originals: &packs_of(&set), covers, remove: &[] })).unwrap();
    assert!(r.rewrote.is_empty() && r.added.is_empty(), "{r:?}");
    same_store(&path, &want, "이음 번호 옮김(Tracks)", &["now"]);
    // 옮기기는 같은 쓰기 거래 안 — 뒤 걸음에서 실패하면 저장소 그대로(번호도).
    let path = common::scratch("ap-strip-fail");
    import_layout_value(&base, &packs_of(&set), &path).unwrap();
    let before = common::sha256_file(&path);
    set_fail_point(Some("names")); // "renumber" 다음 걸음
    let err = write(&path, |tx| apply(tx, &ApplyIn { plan: &moved, originals: &packs_of(&set), covers: Covers::All, remove: &[] }));
    set_fail_point(None);
    assert!(err.is_err(), "실패 주입이 걸려야 합니다");
    assert_eq!(common::sha256_file(&path), before, "실패하면 저장소 그대로");
}

#[test]
fn a_store_printed_under_old_rules_rewrites_every_track_once() {
    // 판정 R45(2): 지문 규칙(지문 판 `PRINT_FORM` · Rust 배치의 규칙 판 `lay::rules`)이 바뀌면 그 전에 지문을 적은 저장소의 첫 넣기는 모든 트랙 · 온 판을 한 번
    // 다시 쓴다 — 트랙마다 · 온 판 조각의 맨 앞에 규칙 판 글이 들기 때문(`patch::prints_under`). 옛 규칙 판으로 적은 지문을 흉내 낸다.
    use archive_engine::patch::{prints_under, rules_mark, save_prints};
    use common::plans::{packs_of, plan};
    let set = ["a", "b", "c"];
    let p = plan(&set);
    let path = common::scratch("ap-old-rules");
    import_layout_value(&p, &packs_of(&set), &path).unwrap();
    let (now, old) = (prints(&p).unwrap(), prints_under(&p, "지문 1 옛 규칙").unwrap());
    assert_eq!(now, prints_under(&p, &rules_mark()).unwrap());
    for (k, t) in &now.tracks {
        assert_ne!(t.print, old.tracks[k].print, "트랙 {k}: 규칙 판이 지문에 들어야 합니다");
    }
    assert_ne!(now.globals, old.globals, "온 판 지문에도 규칙 판이 들어야 합니다");
    write(&path, |tx| save_prints(tx, &old)).unwrap();
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &packs_of(&set), covers: Covers::All, remove: &[] })).unwrap();
    let all: Vec<String> = now.tracks.keys().cloned().collect();
    assert_eq!(r.rewrote, all, "옛 규칙 판의 저장소는 첫 넣기에 모든 트랙을 다시 씁니다");
    assert!(r.globals, "온 판도 다시 적습니다");
    let want = common::scratch("ap-old-rules-full");
    import_layout_value(&p, &packs_of(&set), &want).unwrap();
    same_store(&path, &want, "옛 규칙 판 → 첫 넣기", &["now"]);
    // 그 다음 넣기는 다시 쓰는 것이 없다(지문이 지금 규칙 판으로 맞춰졌다).
    let r = write(&path, |tx| apply(tx, &ApplyIn { plan: &p, originals: &packs_of(&set), covers: Covers::All, remove: &[] })).unwrap();
    assert!(r.rewrote.is_empty() && !r.globals, "{r:?}");
}

#[test]
fn a_store_from_other_rules_lays_out_whole_once() {
    // 판정 R59 I-1: 저장소의 규칙 판(`meta.rules`)이 지금 엔진과 다르면(엔진을 올린 뒤 · 규칙 판이 없는 이 과제 전 저장소) 실제 틈도 하위 배치를 쓰지 않고
    // 모든 트랙을 한 번 다시 셈한다 — 그 apply(모두 덮음)가 지금 규칙 판을 적어 다음 넣고 빼기는 규칙 판이 맞는 저장소와 같은 범위로 좁다.
    use rusqlite::OptionalExtension;
    let _t = common::clock("a_store_from_other_rules_lays_out_whole_once");
    let side = Side::Rust;
    let meta_rules = |path: &Path| -> Option<String> {
        rusqlite::Connection::open(path).unwrap().query_row("SELECT value FROM meta WHERE key='rules'", [], |r| r.get(0)).optional().unwrap()
    };
    // 대조군: 규칙 판이 맞는 동아시아 저장소 — 첫 넣기와 둘째 넣기가 다 좁은 짝을 고른다(빈 시험이 아니게).
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let (d7, dep, sphere) = (dlc(&format!("{FIX}/d7-test.htpack"), &[]), dlc(&format!("{FIX}/dep-scene.htpack"), &[]), dlc(&format!("{FIX}/sphere-test.htpack"), &[]));
    let mut tried = Vec::new();
    let mut pick = None;
    for (first, second) in [(&d7, &dep), (&dep, &d7), (&sphere, &d7), (&d7, &sphere)] {
        let control = full(&side, &[ea.clone()], T, "ap-rules-ok");
        assert_eq!(meta_rules(&control).as_deref(), Some(archive_engine::patch::rules_mark().as_str()), "짓기가 규칙 판을 적어야 합니다");
        let a = add(&control, &[first], side.lay()).unwrap().scope;
        let b = add(&control, &[second], side.lay()).unwrap().scope;
        tried.push(format!("{} → {}: {a:?} · {b:?}", first.key, second.key));
        if a.is_some() && b.is_some() {
            pick = Some((first, second, b));
            break;
        }
    }
    let Some((first, second, second_ok)) = pick else { panic!("넣기 둘이 다 좁은 대조군이 없습니다: {tried:?}") };
    for (tag, old) in [("ap-rules-old", Some("지문 1 lay 0")), ("ap-rules-none", None)] {
        let path = full(&side, &[ea.clone()], T, tag);
        {
            let db = rusqlite::Connection::open(&path).unwrap();
            match old {
                Some(v) => db.execute("UPDATE meta SET value=?1 WHERE key='rules'", [v]).unwrap(),
                None => db.execute("DELETE FROM meta WHERE key='rules'", []).unwrap(),
            };
        }
        let r = add(&path, &[first], side.lay()).unwrap_or_else(|e| panic!("{tag} 넣기: {e}"));
        assert_eq!(r.scope, None, "{tag}: 규칙 판이 다른 저장소의 첫 넣기는 모든 트랙을 셈해야 합니다");
        assert_eq!(meta_rules(&path).as_deref(), Some(archive_engine::patch::rules_mark().as_str()), "{tag}: 모두 덮는 apply가 규칙 판을 적어야 합니다");
        same_store(&path, &full(&side, &[ea.clone(), first.clone()], T, &format!("{tag}-full")), &format!("{tag} — 첫 넣기"), &[]);
        let r = add(&path, &[second], side.lay()).unwrap_or_else(|e| panic!("{tag} 둘째 넣기: {e}"));
        assert_eq!(r.scope, second_ok, "{tag}: 규칙 판을 맞춘 뒤의 넣기는 대조군과 같은 범위여야 합니다");
    }
}

#[test]
fn an_outside_layout_clears_the_rules_so_the_next_add_is_whole() {
    // 판정 R69-2(16b 검토 ① I-2 · M-2): `meta.rules`는 'Rust가 저장소의 원본으로 셈한 배치와 같다'는 약속 — 바깥 배치(메이커 `.htlayout`의 덮는 트랙만 ·
    // `{"op":"apply"}`)를 넣으면 지워져 다음 넣기는 하위 배치로 S 밖 트랙을 믿지 않고 한 번 모든 트랙을 셈한다(그때 notes 순번 · 지문도 통째 짓기로 맞춰진다).
    use rusqlite::OptionalExtension;
    let _t = common::clock("an_outside_layout_clears_the_rules_so_the_next_add_is_whole");
    let side = Side::Rust;
    let meta_rules = |path: &Path| -> Option<String> {
        rusqlite::Connection::open(path).unwrap().query_row("SELECT value FROM meta WHERE key='rules'", [], |r| r.get(0)).optional().unwrap()
    };
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let dep = dlc(&format!("{FIX}/dep-scene.htpack"), &[]);
    let d = json!({ "format": "history-timeline-dlc", "formatVersion": 3, "id": "xmk", "name": "메이커 시험", "version": "0.0.1",
        "tracks": [{ "id": "xmk", "name": "메이커 시험 트랙", "order": 999 }],
        "periods": [{ "id": "p1", "track": "xmk", "name": "메이커 나라", "start": 1200, "end": 1280 }] });
    let made = Dlc { key: "xmk".into(), bytes: seal_dlc(&serde_json::to_vec(&d).unwrap()) };
    let store = full(&side, &[ea.clone()], T, "ap-outside");
    assert_eq!(meta_rules(&store).as_deref(), Some(archive_engine::patch::rules_mark().as_str()), "짓기는 규칙 판을 적는다");
    // 메이커 배치(그 조합의 배치 · 덮는 트랙만)를 넣는다 — 바깥 배치라 규칙 판이 지워진다.
    let layout = common::scratch("ap-outside-layout").with_extension("htlayout");
    std::fs::write(&layout, common::plans::htlayout(&side.plan(&[ea.clone(), made.clone()], T))).unwrap();
    let order = archive_engine::patch::read_order(&layout, &[made.file()], Vec::new(), archive_engine::patch::CoversAsk::Default).unwrap();
    write(&store, |tx| archive_engine::patch::run_order(tx, &order)).unwrap();
    assert_eq!(meta_rules(&store), None, "바깥 배치 뒤에는 규칙 판이 없어야 합니다");
    // 다음 넣기는 모든 트랙 — 그 뒤 규칙 판이 돌아오고 통째 짓기와 같다.
    let r = add(&store, &[&dep], side.lay()).unwrap();
    assert_eq!(r.scope, None, "바깥 배치 뒤 첫 넣기는 모든 트랙이어야 합니다");
    assert_eq!(r.to_json()["scope"], json!("all"));
    assert!(r.to_json()["widened"].is_null(), "규칙 판으로 처음부터 모든 트랙 — 넓힘이 아님");
    assert_eq!(meta_rules(&store).as_deref(), Some(archive_engine::patch::rules_mark().as_str()));
    // 메이커 배치는 지은 날(`now`)을 싣지 않아 apply가 오늘로 적었다 — 견줄 통째 짓기도 그 날로.
    let now = meta(&store)["now"].clone();
    let (now_ms, _) = archive_engine::legacy::iso_time(&now).expect("meta.now");
    same_store(&store, &full(&side, &[ea, made, dep], now_ms, "ap-outside-full"), "바깥 배치 → 넣기", &["now"]);
}

#[test]
fn track_prints_from_the_flow_match_a_full_build() {
    let _t = common::clock("track_prints_from_the_flow_match_a_full_build");
    // 흐름이 적은 트랙 지문(하위 배치에서 셈)이 통째 짓기의 지문과 같아야 다음 넣기가 바뀌지 않은 트랙을 다시 쓰지 않는다.
    let side = Side::node("ap-prints", Touch::Exact);
    let path = full(&side, &[synth(), patch1()], T, "ap-prints");
    add(&path, &[&patch2()], side.lay()).unwrap();
    let want = full(&side, &[synth(), patch1(), patch2()], T, "ap-prints-full");
    let q = "SELECT key,print FROM track_prints ORDER BY key";
    assert_eq!(pairs(&path, q), pairs(&want, q));
    let r = add(&path, &[&patch2()], side.lay()).unwrap();
    assert!(r.apply.rewrote.is_empty() && r.apply.added.is_empty() && !r.apply.names && r.replaced.is_empty(), "같은 파일을 다시 넣으면 바뀌는 것이 없다: {:?}", r.apply);
}

#[test]
fn a_maker_layout_on_real_data_is_taken_or_refused_cleanly() {
    let _t = common::clock("a_maker_layout_on_real_data_is_taken_or_refused_cleanly");
    // A 걸음 검토 검사 빈틈 5: 실제 메이커 배치(.htlayout — 메이커가 불러온 조합만으로 셈한 배치 · 덮는 트랙만)를 실자료(동아시아 + KoreanTimeLine) 저장소에 넣는다.
    // apply-check는 Node 배치만 걸었다. KoreanTimeLine이 온 판 표(분류 · 시대 구분 · 공통 날짜 칸)를 바꾸는 DLC면 그것을 불러오지 않은 메이커 배치는
    // "덮는 트랙만 주는 배치로는 … 바꿀 수 없습니다"로 거절되고 저장소는 그대로여야 하며(P5 · B의 쓰임새 — 거절 글이 무엇을 다시 하라는지 알려야 함),
    // 바꾸지 않는 DLC면 받아 그 DLC의 트랙이 든다. KoreanTimeLine까지 불러온 메이커 배치는 받아 그 조합의 통째 짓기와 같은 답이다.
    let Some(ktl) = ktl() else {
        eprintln!("건너뜀 — KoreanTimeLine 파일이 없습니다");
        return;
    };
    let (ea, dep) = (dlc(&format!("{FIX}/east-asia.json"), &[]), dlc(&format!("{FIX}/dep-scene.htpack"), &[]));
    let side = Side::node("ap-maker", Touch::All);
    side.prefetch(&[vec![ea.clone(), ktl.clone()], vec![ea.clone(), dep.clone()], vec![ea.clone(), ktl.clone(), dep.clone()]], T);
    let maker = |c: &[Dlc], name: &str| -> PathBuf {
        let plan = side.plan(c, T);
        let path = common::scratch(name).with_extension("htlayout");
        std::fs::write(&path, common::plans::htlayout(&plan)).unwrap();
        path
    };
    let store = full(&side, &[ea.clone(), ktl.clone()], T, "ap-maker");
    let before = common::sha256_file(&store);
    // 1) KoreanTimeLine을 불러오지 않은 메이커 배치(동아시아 + dep-scene).
    let layout = maker(&[ea.clone(), dep.clone()], "ap-maker-dep");
    let order = archive_engine::patch::read_order(&layout, &[dep.file()], Vec::new(), archive_engine::patch::CoversAsk::Default).unwrap();
    let (with_ktl, without) = (side.plan(&[ea.clone(), ktl.clone()], T), side.plan(&[ea.clone(), dep.clone()], T));
    let common_axis = |p: &Value| -> Vec<Value> { p["axis"].as_array().unwrap().iter().filter(|a| a["track"].as_i64().unwrap_or(-1) < 0).cloned().collect() };
    let differs = with_ktl["categories"] != without["categories"] || with_ktl["epochs"] != without["epochs"] || common_axis(&with_ktl) != common_axis(&without);
    let got = write(&store, |tx| archive_engine::patch::run_order(tx, &order));
    if differs {
        let err = got.unwrap_err().to_string();
        assert!(err.contains("바꿀 수 없습니다") && err.contains("배치 전체"), "온 판이 다르면 알아듣게 거절: {err}");
        assert_eq!(common::sha256_file(&store), before, "거절하면 저장소 그대로");
        eprintln!("KoreanTimeLine이 온 판 표를 바꾼다 — 그것을 뺀 메이커 배치는 거절: {err}");
    } else {
        let r = got.unwrap();
        assert!(!r.added.is_empty(), "dep-scene의 트랙이 든다: {r:?}");
        // 메이커 배치는 KoreanTimeLine 없이 셈한 것 — 그 배치가 덮은 동아시아 트랙은 그 배치의 셈으로 바뀌어, KoreanTimeLine까지 함께 셈한 통째 짓기와 지문이 다른
        // 트랙이 생긴다(KTL의 몫이 빠진 것인지 dep의 몫이 더해진 것인지는 이 검사가 가르지 않는다). KoreanTimeLine 제 트랙은 덮지 않아 그대로다.
        // (계획 정한 것 #8의 뜻 그대로 — 알려진 꼴로 보고에 남긴다.)
        let (pk, pd) = (prints(&with_ktl).unwrap(), prints(&without).unwrap());
        let lost: Vec<&String> = pd.order.iter().filter(|k| pk.tracks.get(*k).is_some_and(|t| t.print != pd.tracks[*k].print)).collect();
        let own: Vec<&String> = pk.order.iter().filter(|k| !pd.tracks.contains_key(*k)).collect();
        let held = pairs(&store, "SELECT key,print FROM track_prints ORDER BY key");
        for k in &own {
            assert!(held.iter().any(|(key, print)| key == *k && *print == pk.tracks[*k].print), "KoreanTimeLine 제 트랙 {k}은 그대로");
        }
        eprintln!("KoreanTimeLine은 온 판 표를 바꾸지 않는다 — 메이커 배치를 받음: 새 트랙 {:?} · KTL까지 셈한 통째 짓기와 지문이 다른 덮인 트랙 {lost:?} · 그대로인 KTL 제 트랙 {own:?}", r.added);
    }
    // 2) KoreanTimeLine까지 불러온 메이커 배치(동아시아 + KTL + dep-scene) — 받고 그 조합의 통째 짓기와 타일이 같다(덮는 트랙만 주는 배치는 온 판 메타 —
    //    문화권 목록 — 를 적지 않으므로 layout 답의 문화권은 다음 모두 덮는 apply까지 옛것일 수 있다 — 2-7절).
    let store = full(&side, &[ea.clone(), ktl.clone()], T, "ap-maker-2");
    let layout = maker(&[ea.clone(), ktl.clone(), dep.clone()], "ap-maker-all");
    let order = archive_engine::patch::read_order(&layout, &[dep.file()], Vec::new(), archive_engine::patch::CoversAsk::Default).unwrap();
    write(&store, |tx| archive_engine::patch::run_order(tx, &order)).unwrap();
    let want = full(&side, &[ea, ktl, dep], T, "ap-maker-2-full");
    let (got, want) = (canon_store(&store, &quick_q()).unwrap(), canon_store(&want, &quick_q()).unwrap());
    assert!(got["views"] == want["views"], "KTL까지 불러온 메이커 배치 — 타일");
    assert_eq!(got["layout"]["tracks"], want["layout"]["tracks"], "KTL까지 불러온 메이커 배치 — 트랙");
}

/// 걸음 5(시간)의 지금 몫 — 동아시아 저장소에 KoreanTimeLine을 열 번 넣어(매번 같은 저장소 사본에서) 읽기 · 판 대조 · apply 몫의 가운데값을 찍는다.
/// Node 틈의 배치 시간은 뺀다. 실제 틈(P3 과제 16b — 닿는 트랙 · 하위 배치)은 배치까지 모두 · 몫(읽기 · 닿는 트랙과 그 밖 · 배치 · apply)을 찍는다
/// (한 프로세스 안이라 첫 번도 정규식이 데워진 뒤 — 차가운 첫 번은 `archive-tool add-pack`으로 따로 잰다). 손으로 돌림: `cargo test --release --test add_pack -- --ignored --nocapture timing`.
#[test]
#[ignore = "손으로 재는 시간(감독 PC의 KoreanTimeLine이 있을 때)"]
fn timing_of_reading_versions_and_apply_for_ktl() {
    let _t = common::clock("timing_of_reading_versions_and_apply_for_ktl");
    let Some(ktl) = ktl() else {
        eprintln!("건너뜀 — KoreanTimeLine 파일이 없습니다");
        return;
    };
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    for touch in [Touch::Exact, Touch::All] {
        let side = Side::node("ap-time", touch);
        side.prefetch(&[vec![ea.clone()], vec![ea.clone(), ktl.clone()]], T);
        let base = full(&side, &[ea.clone()], T, "ap-time-base");
        let (mut read, mut apply_ms, mut total) = (Vec::new(), Vec::new(), Vec::new());
        for i in 0..10 {
            let path = common::scratch(&format!("ap-time-{i}"));
            std::fs::copy(&base, &path).unwrap();
            let r = add(&path, &[&ktl], side.lay()).unwrap();
            read.push(r.ms_read);
            apply_ms.push(r.ms_apply);
            total.push(r.ms - r.ms_layout);
        }
        let mid = |mut v: Vec<f64>| { v.sort_by(f64::total_cmp); v[v.len() / 2] };
        eprintln!("KTL 넣기 {touch:?}: 읽기 · 판 대조 {:.1}ms · apply {:.1}ms · 배치 뺀 모두 {:.1}ms (열 번 가운데값)", mid(read), mid(apply_ms), mid(total));
    }
}

/// 재는 틀(판정 R69-6 — 시간 판단은 공식 검사(계획 걸음 7) 때 한가한 PC에서): 동아시아 저장소에 KoreanTimeLine을 실제 틈으로 열한 번 넣는다(매번 같은 저장소
/// 사본). 첫 번은 **차가운 첫 넣기**(이 프로세스의 정규식 첫 짓기 · 첫 셈), 나머지 열은 **앱 꼴 따뜻한 넣기**(같은 프로세스 · 넣기마다 저장소에서 달력 표를 다시
/// 읽어 푼다 — 넣기 끝에 캐시를 비우므로). 몫: 달력 표 풀기(따로 잼) · 읽기 · 판 대조 · 닿는 트랙 · 배치 · apply(그 안의 verify) · commit(쓰기 거래 끝) ·
/// 벽시계. 전체 달력 표로 재려면 `HT_CALENDAR_FULL=<warm-calendar.mjs로 뜬 calendar-cache.json>`(없으면 검사의 잘린 표 — 적어 둔다).
/// 예산 기준: P4 과제 9의 0.3초는 따뜻한 넣기의 벽시계. **한계**(16b 고침 2회차 작은 것 7 — 바꾸지 않음 · 걸음 7에서 판단): 정규식 첫 짓기의 몫을
/// 따로 재지 않고 차가운 첫 넣기에 섞이며, 넣기마다 새 연결을 연다(앱은 열린 연결 하나로 넣는다 — 연결 여는 몫만큼 앱보다 크다). 손으로 돌림(공식 설정 · 한가할 때): `cargo test --release --locked --test add_pack -- --ignored --nocapture timing_app`.
#[test]
#[ignore = "손으로 재는 시간(감독 PC의 KoreanTimeLine이 있을 때 · 공식 설정 · 한가할 때)"]
fn timing_app_like_adds_for_ktl() {
    use std::cell::Cell;
    use std::time::Instant;
    let Some(ktl) = ktl() else {
        eprintln!("건너뜀 — KoreanTimeLine 파일이 없습니다");
        return;
    };
    /// 닿는 트랙 · 배치에 든 시간을 따로 세는 실제 틈.
    struct Timed { touched: Cell<f64>, export: Cell<f64> }
    impl Layouter for Timed {
        fn export(&self, p: &[PackIn], o: &Opts) -> archive_engine::Result<Value> {
            let t0 = Instant::now();
            let r = RustLayouter.export(p, o);
            self.export.set(self.export.get() + t0.elapsed().as_secs_f64() * 1000.0);
            r
        }
        fn touched(&self, b: &[PackIn], a: &[PackIn], o: &Opts) -> archive_engine::Result<Scope> {
            let t0 = Instant::now();
            let r = RustLayouter.touched(b, a, o);
            self.touched.set(self.touched.get() + t0.elapsed().as_secs_f64() * 1000.0);
            r
        }
    }
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let (table, which) = match std::env::var("HT_CALENDAR_FULL") {
        Ok(p) => (std::fs::read(&p).expect("HT_CALENDAR_FULL"), "전체 표"),
        Err(_) => (calendar_slice().to_vec(), "검사의 잘린 표"),
    };
    let base = common::scratch("ap-apptime-base");
    let plan = Side::Rust.plan(&[ea.clone()], T);
    build_store(&plan, &[(ea.key.clone(), ea.bytes.clone())], &base, &iso_at(T, TZ), &table).unwrap();
    // 달력 표 풀기 한 번(넣기마다 든다 — 저장소의 zlib 풀기 + JSON · 표 짓기).
    let t0 = Instant::now();
    let db = rusqlite::Connection::open(&base).unwrap();
    let bytes = archive_engine::lay::calendar_of(&db).unwrap().unwrap();
    archive_engine::lay::cal::Tables::shared(&bytes).unwrap();
    let ms_table = t0.elapsed().as_secs_f64() * 1000.0;
    drop(db);
    archive_engine::lay::clear_caches();
    let mut rows: Vec<[f64; 9]> = Vec::new();
    let mut scope = None;
    for i in 0..11 {
        let path = common::scratch(&format!("ap-apptime-{i}"));
        std::fs::copy(&base, &path).unwrap();
        let timed = Timed { touched: Cell::new(0.0), export: Cell::new(0.0) };
        let t0 = Instant::now();
        let r = write(&path, |tx| add_pack(tx, &AddOrder { files: vec![ktl.file()], ..AddOrder::default() }, &timed)).unwrap();
        let wall = t0.elapsed().as_secs_f64() * 1000.0;
        scope = r.scope;
        let verify = r.apply.steps.iter().find(|(k, _)| *k == "verify").map_or(0.0, |s| s.1);
        // commit = 쓰기 거래(write)의 벽시계 − 넣기 몸(r.ms).
        rows.push([wall, r.ms, r.ms_read, timed.touched.get(), timed.export.get(), r.ms_apply, verify, wall - r.ms, r.layouts as f64]);
    }
    let warm = &rows[1..];
    let mid = |k: usize| { let mut v: Vec<f64> = warm.iter().map(|x| x[k]).collect(); v.sort_by(f64::total_cmp); (v[4] + v[5]) / 2.0 };
    let show = |r: &[f64; 9]| format!("벽시계 {:.1} · 넣기 {:.1} · 읽기 · 판 대조 {:.1} · 닿는 트랙 {:.1} · 배치 {:.1} · apply {:.1}(verify {:.1}) · commit {:.1}",
        r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]);
    eprintln!("KTL 넣기 실제 틈(범위 {scope:?} · 달력 {which} · 표 풀기 {ms_table:.1}ms):");
    eprintln!("  차가운 첫 넣기  {}", show(&rows[0]));
    eprintln!("  따뜻한 넣기(열 번 가운데값) {}", show(&[mid(0), mid(1), mid(2), mid(3), mid(4), mid(5), mid(6), mid(7), mid(8)]));
}

/// 자료집 글자 id의 저장소 번호(`meta.pack_keys`).
fn pack_no(path: &Path, key: &str) -> i64 {
    let keys: Value = serde_json::from_str(&meta(path)["pack_keys"]).unwrap();
    keys.as_object().unwrap().iter().find(|(_, v)| v.as_str() == Some(key)).map(|(n, _)| n.parse().unwrap()).unwrap_or_else(|| panic!("«{key}»가 저장소에 없습니다"))
}

/// 그 DLC의 항목 기록(uid · 종류 — 띠 period · 인물 figure · 시대 구분 epoch …) uid 차례로.
fn entity_kinds(path: &Path, key: &str) -> Vec<(String, String)> {
    pairs(path, &format!("SELECT uid,kind FROM entities WHERE pack={} ORDER BY uid", pack_no(path, key)))
}

/// 리메이크 5단계 과제 10 — 형식 4 가상 팩 다섯(`prototype/fixtures/f4` · 과제 0 · 이름은 모두 가상)을 `.htpack`으로 싸서 실제 틈으로 넣기 · 빼기 · 다시 넣기:
/// 거절(`code`) 없이 되고, 내림(`lay/f4.rs` — 사람 객체 → 인물 · 빌린 직위 줄 → 칸 복제 · 문화권별 주기 → 간지 하나)의 알림은 답의 `notes`로 남는다
/// (`PackReport::notes` · JSON 답의 `notes`). 넣은 뒤 그 DLC의 항목 기록(uid · 종류)은 다리로 내린 옛 꼴(`expected/<id>.legacy.json`의 `legacy` — check-format4 ⑨가
/// JS 다리와 같음을, f4-same-check가 엔진 거울과 같음을 본다)을 같은 id의 DLC로 싸서 통째로 지은 것과 같고, 띠 · 인물 · 시대 구분의 수는 그 `legacy`의
/// `periods` · `figures` · `epochs` 수다. 끝에 빌림이 깨진 사본(빌려 올 객체가 없음)을 같은 판으로 바꿔 넣어 `f4.rs`의 알림 글이 거절이 아니라 `notes`임을 본다.
#[test]
fn format4_fixture_packs_go_in_out_and_in_again() {
    let _t = common::clock("format4_fixture_packs_go_in_out_and_in_again");
    const F4: &str = "prototype/fixtures/f4";
    const DOWN: &str = "형식 4 파일을 지금 형식으로 바꿔 읽었습니다";
    let list: Value = serde_json::from_slice(&std::fs::read(root().join(F4).join("list.json")).unwrap()).unwrap();
    let files: Vec<String> = list["files"].as_array().unwrap().iter().map(|f| f["path"].as_str().unwrap().to_owned()).collect();
    assert_eq!(files.len(), 5, "형식 4 가상 팩 다섯");
    let side = Side::Rust;
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let path = full(&side, &[ea.clone()], T, "ap-f4");
    let mut legacies: Vec<Dlc> = Vec::new();
    // 지금까지 넣은 형식 4 팩 그대로(내린 옛 꼴이 아니라) — 동아시아와 함께 Rust로 통째 지은 저장소가 넣고 빼기 길의 견줌 상대(리메이크 3단계 과제 7 걸음 2).
    let mut whole_combo = vec![ea.clone()];
    for (i, file) in files.iter().enumerate() {
        let f4 = dlc(&format!("{F4}/{file}"), &[]);
        let id = file.trim_end_matches(".json");
        assert_eq!(f4.key, id, "{file}: id는 파일 이름과 같다");
        whole_combo.push(f4.clone());
        let whole = full(&side, &whole_combo, T, &format!("ap-f4-whole-{i}"));
        let whole_canon = canon_store(&whole, &quick_q()).unwrap(); // ① · ③이 함께 쓴다(한 번만 셈)
        let expected: Value = serde_json::from_slice(&std::fs::read(root().join(F4).join("expected").join(format!("{id}.legacy.json"))).unwrap()).unwrap();
        let legacy = &expected["legacy"];
        assert_eq!(legacy["id"].as_str(), Some(id));
        let want_len = |k: &str| legacy[k].as_array().map_or(0, Vec::len);
        let legacy_dlc = Dlc { key: id.to_owned(), bytes: seal_dlc(&serde_json::to_vec(legacy).unwrap()) };
        // ① 넣기 — 거절 없음 · 내림 알림은 notes(JSON 답에도).
        let r = add(&path, &[&f4], side.lay()).unwrap_or_else(|e| panic!("{id} 넣기가 거절됨(code {:?}): {e}", code(&e)));
        assert!(r.notes.iter().any(|n| n.contains(DOWN)), "{id}: 형식 4를 내렸다는 알림이 notes에 — {:?}", r.notes);
        assert!(r.notes.iter().all(|n| n.starts_with('«')), "{id}: 알림마다 DLC 이름 머리 — {:?}", r.notes);
        assert_eq!(r.to_json()["notes"], json!(r.notes), "{id}: JSON 답의 notes");
        assert!(!r.apply.added.is_empty() || !r.apply.rewrote.is_empty(), "{id}: 트랙이 들거나 다시 쓰임");
        // ①' 넣고 빼기 길로 든 저장소 = 동아시아 + 지금까지의 형식 4 팩을 Rust로 통째 지은 것 — 빌림 · 사람 띠 · 문화권 줄이 띠 form · 문화권 단위 줄
        // (sphere_lines)까지 같다(같음의 약속 전부 — canon · meta · 검색 낱자 · 사건 차례 · 항목 기록 · 스키마 4의 값 · 트랙 지문).
        assert!(canon_store(&path, &quick_q()).unwrap() == whole_canon, "{id} 넣기: canon이 통째 짓기와 다릅니다");
        same_but_canon(&path, &whole, &format!("{id} 넣기"), &[]);
        let scope = r.scope;
        // ② 항목 기록: 내린 옛 꼴을 통째로 지은 것과 같다 · 띠 · 인물 · 시대 구분 수는 expected의 legacy 수.
        let want = full(&side, &[ea.clone(), legacy_dlc.clone()], T, &format!("ap-f4-{i}"));
        let got = entity_kinds(&path, id);
        assert_eq!(got, entity_kinds(&want, id), "{id}: 항목 기록(uid · 종류)이 내린 옛 꼴의 통째 짓기와 다릅니다");
        let count = |kind: &str| got.iter().filter(|(_, k)| k == kind).count();
        assert_eq!((count("period"), count("figure"), count("epoch")), (want_len("periods"), want_len("figures"), want_len("epochs")), "{id}: 띠 · 인물 · 시대 구분 수");
        eprintln!("{id}: 띠 {} · 인물 {} · 시대 구분 {} · 알림 {} · 새 트랙 {} · 다시 쓴 트랙 {} · 범위 {scope:?} · form≠0 띠 {} · 문화권 단위 줄 {}", count("period"),
            count("figure"), count("epoch"), r.notes.len(), r.apply.added.len(), r.apply.rewrote.len(),
            pairs(&whole, "SELECT CAST(count(*) AS TEXT),'' FROM periods WHERE form<>0")[0].0, pairs(&whole, "SELECT CAST(count(*) AS TEXT),'' FROM sphere_lines")[0].0);
        // ③ 빼기(원본 버림) → 다시 넣기 — 거절 없이 · 같은 항목 기록 · 빼기의 답은 notes가 빈 목록.
        let r = remove(&path, id, true, side.lay()).unwrap_or_else(|e| panic!("{id} 빼기: {e}"));
        assert!(r.notes.is_empty(), "빼기의 답은 알림 없음");
        assert!(!pack_keys(&path).contains(&id.to_owned()), "{id}: 뺀 뒤 저장소에 없다");
        let r = add(&path, &[&f4], side.lay()).unwrap_or_else(|e| panic!("{id} 다시 넣기: {e}"));
        assert!(r.notes.iter().any(|n| n.contains(DOWN)), "{id}: 다시 넣을 때도 내림 알림");
        assert_eq!(entity_kinds(&path, id), got, "{id}: 다시 넣은 항목 기록");
        assert!(canon_store(&path, &quick_q()).unwrap() == whole_canon, "{id} 빼고 다시 넣기: canon이 통째 짓기와 다릅니다");
        same_but_canon(&path, &whole, &format!("{id} 빼고 다시 넣기"), &[]);
        legacies.push(legacy_dlc);
    }
    // ④ 다섯이 다 든 저장소의 항목 기록 전부 = 내린 옛 꼴 다섯을 통째로 지은 것.
    let mut combo = vec![ea.clone()];
    combo.extend(legacies);
    let want = full(&side, &combo, T, "ap-f4-all");
    let all = "SELECT uid,kind FROM entities ORDER BY uid";
    assert_eq!(pairs(&path, all), pairs(&want, all), "다섯이 다 든 저장소의 항목 기록");
    // ⑤ f4.rs의 알림 글은 거절이 아니다: 빌려 올 객체가 없는 사본(같은 판 · 다른 바이트)을 바꿔 넣으면 그 직위 줄만 빼고 받는다 — notes에 그 까닭.
    let broken = dlc(&format!("{F4}/f4-office.json"), &[("\"from\": \"o-seat/지도자\"", "\"from\": \"o-nowhere/지도자\"")]);
    let r = add(&path, &[&broken], side.lay()).unwrap_or_else(|e| panic!("빌림이 깨진 사본 넣기가 거절됨(code {:?}): {e}", code(&e)));
    assert!(r.notes.iter().any(|n| n.contains("빌려 올 객체") && n.contains("o-nowhere") && n.contains("찾지 못해 뺍니다")), "빌림 알림이 notes에 — {:?}", r.notes);
    assert_eq!(r.replaced.len(), 1, "같은 판 · 다른 바이트로 바꿔 넣음");
    let r = add(&path, &[&dlc(&format!("{F4}/f4-office.json"), &[])], side.lay()).unwrap();
    assert!(r.notes.iter().all(|n| !n.contains("찾지 못해")), "제대로 된 파일로 되돌리면 빌림 알림이 없다 — {:?}", r.notes);
    assert_eq!(pairs(&path, all), pairs(&want, all), "되돌린 뒤 항목 기록은 그대로");
}

/// 리메이크 3단계 과제 7 걸음 3(과제 0 걸음 4의 재현) — 등불 연대기 견본을 통째로 지은 저장소에 형식 4 가상 팩 `f4-crowns`(등불의 트랙 설령 · 백사만 ·
/// 청림에 얹는 사람 객체 · 이름은 모두 가상)를 실제 틈으로 넣기 · 빼기 · 다시 넣기. 형식 3으로 내린 사본(`expected/f4-crowns.legacy.json`의 `legacy`를
/// 같은 id로 싼 것)도 같은 걸음을 간다. 고치기 전에는 첫 넣기가 "배치와 저장소가 어긋나 … 다시 쓰지 않는 변형 7개가 지울 트랙 «hayeon»의 칸 · 항목을
/// 가립니다"로 거절됐다(두 파일 모두). 걸음마다 그 조합을 통째로 지은 저장소와 같다 — 걸음마다 [`same_light`](meta · 사건 차례 · 항목 기록 · 띠 form ·
/// 문화권 단위 줄 · 트랙 지문) · 넣기 뒤에는 검색 낱자와 canon(성긴 단계 — 등불은 글이 많아 [`light_canon`])까지.
#[test]
fn lantern_takes_f4_crowns_in_out_and_in_again() {
    let _t = common::clock("lantern_takes_f4_crowns_in_out_and_in_again");
    const F4: &str = "prototype/fixtures/f4";
    let side = Side::Rust;
    let lay = side.lay();
    let fulls = Fulls::new(&side, "ap-lc");
    let lan = lantern();
    let crowns = dlc(&format!("{F4}/f4-crowns.json"), &[]);
    let expected: Value = serde_json::from_slice(&std::fs::read(root().join(F4).join("expected").join("f4-crowns.legacy.json")).unwrap()).unwrap();
    assert_eq!(expected["legacy"]["id"].as_str(), Some(crowns.key.as_str()), "형식 3 사본의 id");
    let legacy = Dlc { key: crowns.key.clone(), bytes: seal_dlc(&serde_json::to_vec(&expected["legacy"]).unwrap()) };
    let (base, with_crowns, with_legacy) = (vec![lan.clone()], vec![lan.clone(), crowns.clone()], vec![lan.clone(), legacy.clone()]);
    let whole = |path: &Path, combo: &[Dlc], tag: &str| {
        let want = fulls.store(combo);
        same_light(path, &want, tag, &[]);
        assert_eq!(search_terms(path), search_terms(&want), "{tag}: 검색 낱자");
        assert!(canon_store(path, &light_canon()).unwrap() == fulls.canon(combo, &light_canon()), "{tag}: canon(성긴 단계)이 통째 짓기와 다릅니다");
    };
    for (which, pack, with) in [("형식 4", &crowns, &with_crowns), ("형식 3 사본", &legacy, &with_legacy)] {
        let path = common::scratch(&format!("ap-lc-{}", if which == "형식 4" { "f4" } else { "f3" }));
        std::fs::copy(fulls.store(&base), &path).unwrap();
        let put = |step: &str| -> PackReport {
            let r = add(&path, &[pack], lay).unwrap_or_else(|e| panic!("{which} {step}: 등불에 f4-crowns 넣기가 거절됨(code {:?}): {e}", code(&e)));
            eprintln!("{which} {step}: 범위 {:?} · 새 트랙 {} · 다시 쓴 트랙 {} · 배치 {}번", r.scope, r.apply.added.len(), r.apply.rewrote.len(), r.layouts);
            r
        };
        put("넣기");
        whole(&path, with, &format!("{which} 넣기"));
        let r = remove(&path, &pack.key, true, lay).unwrap_or_else(|e| panic!("{which} 빼기(code {:?}): {e}", code(&e)));
        eprintln!("{which} 빼기: 범위 {:?} · 다시 쓴 트랙 {} · 사라진 트랙 {}", r.scope, r.apply.rewrote.len(), r.apply.removed.len());
        same_light(&path, &fulls.store(&base), &format!("{which} 빼기"), &[]);
        put("다시 넣기");
        same_light(&path, &fulls.store(with), &format!("{which} 다시 넣기"), &[]);
    }
}

/// 리메이크 3단계 과제 7 걸음 2 — 판 3 저장소(스키마 4 전의 엔진이 지은 것: 띠 `form` 열 · 문화권 단위 줄 표가 없고 규칙 판이 옛것 —
/// `common::strip_schema4` 흉내 + `meta.rules`의 지문 판을 '지문 2'로)에서 시작하는 넣기 · 빼기. 실제 틈 · 동아시아 바탕 · 형식 4 가상 팩(사람 띠 `f4-crowns` ·
/// 문화권 줄 `f4-sphere` · 공국 `f4-federation`):
/// - 첫 넣기(빼기)는 옛 열이 있어 모든 트랙을 셈하고(`scope` all) 판을 '4'(열쇠 ≠ 자리면 '4.1')로 · 규칙 판을 지금 것으로 적으며, 그 조합을 통째 지은
///   저장소와 같다(같음의 약속 전부 — 띠 form · 문화권 단위 줄까지).
/// - 그다음 넣기 · 빼기는 판 4 저장소의 같은 걸음(대조군)과 같은 범위로 좁고(`scope` Some — 좁게 셈되는 공국으로 본다. 사람 띠 · 문화권 줄 넣기는
///   판 4 저장소에서도 모든 트랙을 셈한다) 역시 통째 짓기와 같다.
/// - 갈래 셋: 판 '3'에 넣기 · 판 '3'에서 빼기 · 판 '3.1'(줄 열쇠 ≠ 자리 — `common::split_keys` 뒤 걷기)에 넣기.
///
/// 같은 조합의 통째 짓기 · canon은 한 번만 셈해 나눠 쓴다([`Fulls`] — 시작 저장소 · 대조군은 그 사본).
#[test]
fn a_schema3_store_is_rewritten_to_schema4_by_its_first_add_or_remove() {
    let _t = common::clock("a_schema3_store_is_rewritten_to_schema4_by_its_first_add_or_remove");
    const F4: &str = "prototype/fixtures/f4";
    let side = Side::Rust;
    let lay = side.lay();
    let fulls = Fulls::new(&side, "ap-s3");
    let ea = dlc(&format!("{FIX}/east-asia.json"), &[]);
    let f4 = |name: &str| dlc(&format!("{F4}/{name}.json"), &[]);
    let (crowns, sphere, federation) = (f4("f4-crowns"), f4("f4-sphere"), f4("f4-federation"));
    let mark = archive_engine::patch::rules_mark();
    let old_mark = mark.replacen(archive_engine::patch::PRINT_FORM, "지문 2", 1);
    assert_ne!(old_mark, mark, "장면: 옛 규칙 판 글");
    // 그 조합의 통째 짓기 사본(이 검사가 고쳐 쓸 저장소).
    let copy_of = |combo: &[Dlc], tag: &str| -> PathBuf {
        let path = common::scratch(tag);
        std::fs::copy(fulls.store(combo), &path).unwrap();
        path
    };
    // 판 3 저장소로 만든 사본 — `split`이면 줄 열쇠를 먼저 가른다('3.1').
    let old_copy = |combo: &[Dlc], split: bool, tag: &str| -> PathBuf {
        let path = copy_of(combo, tag);
        if split {
            common::split_keys(&path);
        }
        common::strip_schema4(&path, if split { "3.1" } else { "3" });
        rusqlite::Connection::open(&path).unwrap().execute("UPDATE meta SET value=?1 WHERE key='rules'", [&old_mark]).unwrap();
        assert!(!common::has_column(&path, "periods", "form") && common::index_sql(&path, "sphere_lines").is_empty(), "장면: 스키마 4의 열 · 표 없음");
        path
    };
    // 같음의 약속 전부([`same_store`]와 같은 눈 — 통째 짓기의 canon은 나눠 쓴다).
    let same = |path: &Path, combo: &[Dlc], tag: &str| {
        assert!(canon_store(path, &quick_q()).unwrap() == fulls.canon(combo, &quick_q()), "{tag}: canon이 통째 짓기와 다릅니다");
        same_but_canon(path, &fulls.store(combo), tag, &[]);
    };
    let count = |path: &Path, sql: &str| -> i64 { pairs(path, &format!("SELECT CAST(({sql}) AS TEXT),''"))[0].0.parse().unwrap() };
    // 첫 걸음의 기대: 모든 트랙 · 판 4 · 규칙 판 · 통째 짓기와 같음(그 통째 짓기에 form ≠ 0 띠 · 문화권 단위 줄이 있어 빈 견줌이 아니다).
    let first = |path: &Path, r: &PackReport, combo: &[Dlc], tag: &str| {
        assert_eq!(r.scope, None, "{tag}: 판 3 저장소의 첫 걸음은 모든 트랙을 셈해야 합니다");
        assert_eq!(r.apply.rewrote.len() + r.apply.added.len(), common::track_count(path), "{tag}: 모든 트랙을 한 번 다시 씀");
        assert!(["4", "4.1"].contains(&meta(path)["schema"].as_str()), "{tag}: 판 4로 고쳐 적어야 함 — {}", meta(path)["schema"]);
        assert_eq!(meta(path).get("rules"), Some(&mark), "{tag}: 규칙 판을 지금 것으로");
        let want = fulls.store(combo);
        assert!(count(&want, "SELECT count(*) FROM periods WHERE form<>0") > 0 && count(&want, "SELECT count(*) FROM sphere_lines") > 0, "{tag}: 장면의 새 값");
        same(path, combo, tag);
    };
    // 판 4 저장소의 같은 걸음(대조군)의 범위 — 판 3에서 고쳐 쓴 뒤의 걸음도 같아야 한다(좁음).
    let control = |before: &[Dlc], step: &dyn Fn(&Path) -> PackReport, tag: &str| -> Option<usize> {
        let r = step(&copy_of(before, tag));
        assert!(r.scope.is_some(), "{tag}: 대조군(판 4)의 걸음이 좁아야 시험이 됩니다");
        r.scope
    };
    let add_many = |p: &Path, ds: &[&Dlc]| -> PackReport {
        add(p, ds, lay).unwrap_or_else(|e| panic!("{:?} 넣기(code {:?}): {e}", ds.iter().map(|d| &d.key).collect::<Vec<_>>(), code(&e)))
    };
    let take_ok = |p: &Path, id: &str| -> PackReport { remove(p, id, true, lay).unwrap_or_else(|e| panic!("{id} 빼기(code {:?}): {e}", code(&e))) };
    let (base, with_two, with_fed) = (vec![ea.clone()], vec![ea.clone(), crowns.clone()], vec![ea.clone(), crowns.clone(), federation.clone()]);
    let with_sphere = vec![ea.clone(), crowns.clone(), sphere.clone()];
    let with_all = vec![ea.clone(), crowns.clone(), sphere.clone(), federation.clone()];

    // ① 판 '3'에 넣기: 사람 띠 · 문화권 줄을 함께(판 4 저장소에서도 모든 트랙을 셈하는 넣기) → 그다음 넣기(공국 — 좁음).
    let path = old_copy(&base, false, "ap-s3-add");
    let r = add_many(&path, &[&crowns, &sphere]);
    first(&path, &r, &with_sphere, "ap-s3-add 첫 넣기");
    let r = add_many(&path, &[&federation]);
    assert_eq!(r.scope, control(&with_sphere, &|p| add_many(p, &[&federation]), "ap-s3-add-control"), "판 4로 고친 뒤의 넣기는 판 4 저장소와 같은 범위(좁음)");
    same(&path, &with_all, "ap-s3-add 둘째 넣기");

    // ② 판 '3'에서 빼기: 공국 빼기 → 그다음 다시 넣기 · 다시 빼기(좁음).
    let path = old_copy(&with_fed, false, "ap-s3-remove");
    let r = take_ok(&path, &federation.key);
    first(&path, &r, &with_two, "ap-s3-remove 첫 빼기");
    let r = add_many(&path, &[&federation]);
    assert_eq!(r.scope, control(&with_two, &|p| add_many(p, &[&federation]), "ap-s3-remove-control"), "판 4로 고친 뒤의 다시 넣기는 좁다");
    same(&path, &with_fed, "ap-s3-remove 다시 넣기");
    let r = take_ok(&path, &federation.key);
    assert_eq!(r.scope, control(&with_fed, &|p| take_ok(p, &federation.key), "ap-s3-remove-control2"), "판 4로 고친 뒤의 빼기는 좁다");
    same(&path, &with_two, "ap-s3-remove 다시 빼기");

    // ③ 판 '3.1'(줄 열쇠 ≠ 자리)에 넣기.
    let path = old_copy(&base, true, "ap-s31-add");
    let r = add_many(&path, &[&crowns]);
    first(&path, &r, &with_two, "ap-s31-add 첫 넣기");
}

/// 리메이크 3단계 저장소 걸음 8 — 형식 4의 이음(남의 실권 `power[].over` · 직위 줄 빌림 `leadersFrom` · `cabinetsFrom` · `offices[].from`)을 넣고 빼기가 따라간다.
/// 합성 자료 두 벌(`tests/fixtures/touch` — `tests/lay_scope.rs` `width_format4_links`와 같은 장면 · 이름은 모두 가상): 바탕 `touch-links`(형식 4)만 통째로 지은
/// 저장소에 쥔 쪽 · 빌림 출처만 고치는 패치 `touch-links-patch`를 실제 틈으로 넣고 · 빼고 · 다시 넣는다. 닿는 트랙이 이음을 모르면 실권 상대(구역 56의 이름 · 색)와
/// 빌린 쪽(구역 54 머리 글 · 칸 종류 9)의 트랙을 다시 쓰지 않아 통째 짓기와 갈린다. 걸음마다 그 조합을 통째로 지은 저장소와 같고(같음의 약속 전부),
/// 범위는 좁다(조용한 줄은 다시 쓰지 않음 — 모든 트랙으로 돌면 시험이 되지 않는다).
#[test]
fn format4_links_rewrite_the_held_and_borrowing_tracks() {
    let _t = common::clock("format4_links_rewrite_the_held_and_borrowing_tracks");
    let side = Side::Rust;
    let lay = side.lay();
    let fx = |name: &str| dlc(&format!("prototype/engine/tests/fixtures/touch/{name}.json"), &[]);
    let (base, patch) = (fx("touch-links"), fx("touch-links-patch"));
    let fulls = Fulls::new(&side, "ap-f4l");
    let (alone, both) = (vec![base.clone()], vec![base.clone(), patch.clone()]);
    let path = common::scratch("ap-f4l");
    std::fs::copy(fulls.store(&alone), &path).unwrap();
    let must = ["tl-weak", "tl-weak2", "tl-b1", "tl-b2", "tl-b3"];
    for (step, want) in [("넣기", &both), ("빼기", &alone), ("다시 넣기", &both)] {
        let r = if step == "빼기" {
            remove(&path, &patch.key, false, lay)
        } else {
            add(&path, &[&patch], lay)
        }.unwrap_or_else(|e| panic!("{step}이 거절됨(code {:?}): {e}", code(&e)));
        eprintln!("{step}: 범위 {:?} · 다시 쓴 트랙 {:?}", r.scope, r.apply.rewrote);
        assert!(r.scope.is_some(), "{step}: 범위가 모든 트랙입니다(좁은 시험이 아님)");
        assert!(!r.apply.rewrote.iter().any(|k| k == "tl-quiet"), "{step}: 조용한 줄까지 다시 썼습니다(좁은 시험이 아님)");
        // 같음의 약속 먼저(지문 · 항목 기록 · canon) — 이음을 모르면 여기서 갈린다.
        same_but_canon(&path, &fulls.store(want), step, &[]);
        assert!(canon_store(&path, &quick_q()).unwrap() == fulls.canon(want, &quick_q()), "{step}: canon이 통째 짓기와 다릅니다");
        for k in must {
            assert!(r.apply.rewrote.iter().any(|x| x == k), "{step}: 트랙 {k}을 다시 쓰지 않았습니다 — {:?}", r.apply.rewrote);
        }
    }
}

/// 저장소에 든 DLC의 글자 id 목록(`meta.pack_keys`의 값).
fn pack_keys(path: &Path) -> Vec<String> {
    let keys: Value = serde_json::from_str(&meta(path)["pack_keys"]).unwrap();
    keys.as_object().unwrap().values().filter_map(|v| v.as_str().map(str::to_owned)).collect()
}

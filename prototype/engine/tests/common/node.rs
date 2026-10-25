//! P4 과제 9 검사의 틈 — **Node 통째 배치**(`prototype/scripts/oracle/combo.mjs` — 정답지와 같은 길 `contextOf` → `runModules`를 시각 · 시간대를 정해 돌림).
//! 모듈이 다 Rust로 옮겨지기 전에 `add_pack` · `remove_pack`의 흐름 전부를 이 틈으로 GREEN까지 잰다(판정 R35). 모듈이 다 오면 같은 검사를
//! 실제 틈(`packs::RustLayouter`)으로도 돌린다(`tests/add_pack.rs`의 표시).
//! - `export`: 그 조합을 Node로 통째 배치(같은 조합 · 같은 날은 한 번만 — 기억해 둔다). `Scope::Tracks(S)`면 `patch::sub_plan(통째, S)`(P3 과제 16의 약속과 같은 값).
//! - `touched`: [`Touch`]에 따라 — `All`(모름 — 실제 틈이 P3 과제 16 전에 하는 것) · `Exact`(앞 · 뒤 조합의 통째 배치를 지문으로 견주어 지문이 바뀐 트랙 —
//!   약속의 가장 좁은 꼴) · `Extra`(그것에 무작위 트랙을 더 — 바뀌지 않은 트랙이 S에 들어도 같아야 함).
//! 여러 조합을 한 Node 프로세스로 미리 뽑아 둘 수 있다([`NodeLayouter::prefetch`] — 웹 코드를 한 번만 싣는다). 조합마다 Node 한 번이면 0.3 ~ 1초쯤.
#![allow(dead_code)]
use archive_engine::lay::{Opts, PackIn, Scope};
use archive_engine::packs::Layouter;
use archive_engine::patch::{prints, sub_plan};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};

/// 닿는 트랙을 어떻게 답하나.
#[derive(Clone, Copy, Debug)]
pub enum Touch {
    All,
    Exact,
    /// 씨앗 — 지문이 바뀐 트랙에 무작위로 몇 트랙을 더한다.
    Extra(u64),
}

pub struct NodeLayouter {
    dir: PathBuf,
    cache: RefCell<HashMap<String, Value>>,
    pub touch: Touch,
    /// Node를 띄운 수 · 통째 배치를 낸 수(기억에서 낸 것 포함) — 검사가 찍는다.
    pub spawns: Cell<usize>,
    pub exports: Cell<usize>,
    /// 마지막 `export`가 받은 '오늘'(밀리초) — 흐름이 저장소의 `meta.now`를 쓰는지 본다.
    pub last_now: Cell<f64>,
    seq: Cell<u64>,
}

/// 저장소 뿌리(연결 폴더로 빌드해도 진짜 자리 — `oracle.rs`와 같은 풀이). Windows의 `\\?\` 앞머리는 뗀다 — Node가 그 꼴의 경로로 스크립트를 찾지 못한다.
/// 검사 파일이 저장소 뿌리를 찾을 때는 이것을 쓴다(`CARGO_MANIFEST_DIR`에서 `..`로 올라가면 연결 폴더 밑에서는 임시 폴더가 나온다).
pub fn repo_root() -> PathBuf {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let real = std::fs::canonicalize(manifest).unwrap_or_else(|_| manifest.to_path_buf());
    let text = real.to_string_lossy().into_owned();
    let plain = PathBuf::from(text.strip_prefix(r"\\?\").unwrap_or(&text));
    plain.parent().and_then(Path::parent).expect("engine 폴더 위에 저장소 뿌리가 없습니다").to_path_buf()
}

/// 한 검사 프로세스가 한꺼번에 띄우는 Node 수의 상한(나란히 도는 판들이 저마다 웹 코드를 실어 PC를 메우지 않게 — 고침 2회차).
const NODE_SLOTS: usize = 3;
static SLOTS: (std::sync::Mutex<usize>, std::sync::Condvar) = (std::sync::Mutex::new(0), std::sync::Condvar::new());

struct NodeSlot;

impl NodeSlot {
    fn take() -> Self {
        let (lock, cv) = &SLOTS;
        let mut used = lock.lock().unwrap_or_else(|e| e.into_inner());
        while *used >= NODE_SLOTS {
            used = cv.wait(used).unwrap_or_else(|e| e.into_inner());
        }
        *used += 1;
        NodeSlot
    }
}

impl Drop for NodeSlot {
    fn drop(&mut self) {
        let (lock, cv) = &SLOTS;
        *lock.lock().unwrap_or_else(|e| e.into_inner()) -= 1;
        cv.notify_one();
    }
}

/// Node 배치(calendar 모듈)가 쓰는 달력 표 — 공용 표(`prototype/results/calendar-cache.json`)의 이 검사 프로세스 사본(판정 R64 넘김 · 과제 testinfra:
/// 모자라면 calendar 모듈이 표를 넓혀 갈아 쓰므로, 공용 표를 주면 검사가 build-check의 `--calendar` 기본 표를 소리 없이 바꾼다). 프로세스마다 한 번 복사 ·
/// 이름이 `archive-correct-<pid>-…`라 끝난 뒤 `common::sweep_stale`이 치운다. 공용 표가 없으면 빈 자리(Node가 처음 쓸 때 거기에 뜬다).
pub fn calendar_copy() -> PathBuf {
    static COPY: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    COPY.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("archive-correct-{}-node-calendar", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("calendar-cache.json");
        let shared = repo_root().join("prototype").join("results").join("calendar-cache.json");
        if shared.is_file() && !file.exists() {
            std::fs::copy(&shared, &file).unwrap_or_else(|e| panic!("공용 달력 표 사본을 만들지 못했습니다({}): {e}", shared.display()));
        }
        file
    }).clone()
}

fn hex(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

impl NodeLayouter {
    pub fn new(tag: &str, touch: Touch) -> Self {
        let dir = std::env::temp_dir().join(format!("archive-correct-{}-node-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Self { dir, cache: RefCell::new(HashMap::new()), touch, spawns: Cell::new(0), exports: Cell::new(0), last_now: Cell::new(f64::NAN), seq: Cell::new(0) }
    }

    /// 조합 · 날의 열쇠(팩 바이트의 SHA-256 · 차례 · 시각 · 시간대).
    fn key(packs: &[PackIn], now_ms: f64, tz_min: i32) -> String {
        let mut h = Sha256::new();
        for p in packs {
            h.update(hex(&p.bytes).as_bytes());
            h.update(b"|");
        }
        h.update(format!("{now_ms}|{tz_min}").as_bytes());
        format!("{:x}", h.finalize())
    }

    /// 팩 바이트를 파일로(Node는 확장자로 .htpack · .json을 가른다).
    fn file_of(&self, p: &PackIn) -> PathBuf {
        let ext = if p.name.to_ascii_lowercase().ends_with(".json") { "json" } else { "htpack" };
        let file = self.dir.join(format!("{}.{ext}", &hex(&p.bytes)[..16]));
        if !file.exists() {
            std::fs::write(&file, &p.bytes).unwrap();
        }
        file
    }

    /// 아직 기억에 없는 조합들을 Node 한 번으로 뽑아 둔다(같은 날 · 같은 시간대).
    pub fn prefetch(&self, combos: &[Vec<PackIn>], now_ms: f64, tz_min: i32) {
        let mut jobs = Vec::new();
        let mut keys = Vec::new();
        for c in combos {
            let key = Self::key(c, now_ms, tz_min);
            if self.cache.borrow().contains_key(&key) || keys.contains(&key) {
                continue;
            }
            let out = self.dir.join(format!("layout-{}.json", &key[..16]));
            jobs.push(serde_json::json!({"packs": c.iter().map(|p| self.file_of(p)).collect::<Vec<_>>(), "out": out}));
            keys.push(key);
        }
        if jobs.is_empty() {
            return;
        }
        let n = self.seq.get() + 1;
        self.seq.set(n);
        let list = self.dir.join(format!("jobs-{n}.json"));
        std::fs::write(&list, serde_json::to_vec(&jobs).unwrap()).unwrap();
        assert_eq!(tz_min, 540, "검사의 Node 틈은 서울 시간대(540)만 띄운다");
        let now = archive_engine::legacy::iso_at(now_ms, tz_min);
        let root = repo_root();
        let _slot = NodeSlot::take();
        let run = std::process::Command::new("node")
            .arg(root.join("prototype").join("scripts").join("oracle").join("combo.mjs"))
            .arg(format!("--jobs={}", list.display()))
            .env("TZ", "Asia/Seoul").env("HT_ORACLE_NOW", &now).env("HT_ORACLE_TZ_MIN", "540")
            .env("HT_CALENDAR_CACHE", calendar_copy())
            .current_dir(&root).output().expect("node를 띄우지 못했습니다(PATH)");
        self.spawns.set(self.spawns.get() + 1);
        assert!(run.status.success(), "Node 배치 실패: {}\n{}", String::from_utf8_lossy(&run.stderr), String::from_utf8_lossy(&run.stdout));
        for (job, key) in jobs.iter().zip(keys) {
            let out = PathBuf::from(job["out"].as_str().unwrap());
            let v: Value = serde_json::from_slice(&std::fs::read(&out).unwrap()).unwrap();
            self.cache.borrow_mut().insert(key, v);
        }
    }

    /// 그 조합의 Node 통째 배치(기억에 없으면 지금 뽑는다).
    pub fn full(&self, packs: &[PackIn], now_ms: f64, tz_min: i32) -> Value {
        let key = Self::key(packs, now_ms, tz_min);
        if !self.cache.borrow().contains_key(&key) {
            self.prefetch(&[packs.to_vec()], now_ms, tz_min);
        }
        self.cache.borrow()[&key].clone()
    }
}

impl Layouter for NodeLayouter {
    /// Node는 제 ICU로 보조 달력 날짜를 읽는다 — 저장소의 달력 표가 없어도 배치한다(Node 길로 지은 표 없는 저장소에서도 흐름을 잰다).
    fn needs_calendar(&self) -> bool {
        false
    }

    fn export(&self, packs: &[PackIn], opts: &Opts) -> archive_engine::Result<Value> {
        self.exports.set(self.exports.get() + 1);
        self.last_now.set(opts.now_ms);
        let whole = self.full(packs, opts.now_ms, opts.tz_min);
        match &opts.scope {
            Scope::All => Ok(whole),
            Scope::Tracks(s) => {
                // 실제 틈과 같은 규칙: S에 배치에 없는 열쇠가 들면 거른다.
                let keys: BTreeSet<String> = archive_engine::patch::track_keys(&whole).into_iter().filter(|k| s.contains(k)).collect();
                sub_plan(&whole, &keys)
            }
        }
    }

    fn touched(&self, before: &[PackIn], after: &[PackIn], opts: &Opts) -> archive_engine::Result<Scope> {
        if matches!(self.touch, Touch::All) {
            return Ok(Scope::All);
        }
        let (b, a) = (prints(&self.full(before, opts.now_ms, opts.tz_min))?, prints(&self.full(after, opts.now_ms, opts.tz_min))?);
        let mut s: BTreeSet<String> = a.order.iter().filter(|k| b.tracks.get(*k).map(|t| &t.print) != Some(&a.tracks[*k].print)).cloned().collect();
        if let Touch::Extra(seed) = self.touch {
            let mut x = seed ^ (a.order.len() as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15);
            for k in &a.order {
                x = x.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
                if (x >> 33) % 3 == 0 {
                    s.insert(k.clone());
                }
            }
        }
        Ok(Scope::Tracks(s))
    }
}

impl Drop for NodeLayouter {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

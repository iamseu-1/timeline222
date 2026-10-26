//! 계보 뼈대 → 항목 기록의 갈래 `kin`(열 꼴 JSON) — `prototype/scripts/export/kin.mjs`(1 ~ 523줄 · SHA-256 앞 12자 `2d22e4bdd520`)를 줄 그대로(한 벌 P3 과제 13c).
//! 모듈 `entities`가 `kinCollect`를 부른다(판정 R24 — 공통 파일에 mod 줄을 더하지 않게 제 모듈 아래 `lay/m/entities/kin.rs` · 계획의 자리 `lay/m/kin.rs`는 웹 함수 모으기 과제 때).
//!
//! 뼈대(`HT.kinSkeleton`의 값)는 `entities/people.rs`의 [`Skel`](정수 열 — JS의 Int32Array)이다. `recordOf`는 웹 뼈대가 내는 꼴만 받는다:
//! 색 표(`colors`)가 늘 있고 · 덧선은 평평한 정수 열 · 칸 표는 객체 · 경고는 글 · 파는 `at` · `up` 정수라 원본의 다른 꼴 갈래
//! (색 열에 글 · 덧선이 묶음 줄이나 객체 · 칸 표가 Map · 경고가 객체 · 파의 `id` · `founder` · `parent`)는 닿지 않는다(보고서 '닿지 않는 갈래').
//! `splitKin` · `joinKin`(덩어리 나누기 · 합치기 — 마디 5만 넘는 뼈대)은 정답지 자료가 닿지 않아 벡터로 지킨다: `js-vectors.json`의 `entities.kin`(합성 뼈대를 작은 상한으로
//! 나누기 · 합치기) · `entities.kinCollect`(견본 모델의 `kinCollect` 상한 8 · 5 · 20 — 기록 · 사람 자리 · 칸 · 가문 x_kin · `chunkAt` · 집계).
use crate::lay::js::{self, Map, Obj, Str, V};
use crate::lay::m::entities::people::{kin_of, kin_skeleton, KinCache, Skel};
use crate::lay::model::util::{is, list, s, t, tv};
use std::collections::HashMap;

/// 덩어리 상한(마디 수) — 확정 설계 8-1 · 10절 17번.
pub const KIN_LIMIT: usize = 50000;
/// 열 꼴 기록의 판. 열 이름 · 차례를 바꾸면 올린다.
pub const KIN_VERSION: i32 = 1;
/// 마디 비트(2-4 아) — 1 구성원 · 2 이름 미상 · 4 찾지 못함 · 8 옆구리 덧선 · 16 파조 · 32 지도자 · 64 계보 전용 · 128 꼬투리 · 256 두 나라.
pub mod bit { pub const MEMBER: i32 = 1; pub const UNKNOWN: i32 = 2; pub const MISSING: i32 = 4; pub const SIDE: i32 = 8; pub const FOUNDER: i32 = 16; pub const LEADER: i32 = 32; pub const LINEAGE: i32 = 64; pub const STUB: i32 = 128; pub const TWO: i32 = 256; }

/// 기록의 파 하나 `{ uid, name, color, at, up }`.
#[derive(Clone, Debug, PartialEq)]
pub struct RBranch { pub uid: Str, pub name: Str, pub color: Str, pub at: i32, pub up: i32 }
/// 꼬투리 `{ key, n }`.
#[derive(Clone, Debug, PartialEq)]
pub struct Stub { pub key: String, pub n: i32 }
/// 덩어리의 뿌리 `{ uid, at, up, upAt }`.
#[derive(Clone, Debug, PartialEq)]
pub struct RootRef { pub uid: String, pub at: i32, pub up: String, pub up_at: i32 }
/// 덩어리 밖에서 오는 덧선 `{ from, fromAt, to, kind, gen }`.
#[derive(Clone, Debug, PartialEq)]
pub struct Far { pub from: Str, pub from_at: i32, pub to: i32, pub kind: i32, pub gen: i32 }
/// 열 꼴 기록(덩어리 하나). 열쇠 차례는 [`Rec::to_v`](이음새 기록 ②) — `root` · `extraFar`는 덩어리에만 끝에 붙는다.
#[derive(Clone, Debug, PartialEq)]
pub struct Rec {
    pub v: i32, pub uid: String, pub n: usize, pub gens: i32,
    pub par: Vec<i32>, pub size: Vec<i32>, pub gen: Vec<i32>, pub bits: Vec<i32>, pub edge: Vec<i32>, pub branch: Vec<i32>, pub color: Vec<i32>, pub color2: Vec<i32>,
    pub name: Vec<Str>, pub sub: Vec<Str>, pub key: Vec<Str>, pub extra: Vec<i32>, pub colors: Vec<Str>, pub branches: Vec<RBranch>,
    pub cells: Vec<(Str, i32)>, pub stubs: Vec<(usize, Stub)>, pub warnings: Vec<String>, pub root: Option<RootRef>, pub extra_far: Option<Vec<Far>>,
}

fn ints(l: &[i32]) -> V { V::Arr(js::Arr::new(l.iter().map(|&x| V::Num(f64::from(x))).collect())) }
fn strs(l: &[Str]) -> V { V::Arr(js::Arr::new(l.iter().map(|x| V::Str(x.clone())).collect())) }
impl Rec {
    /// JS 객체(열쇠 차례 그대로) — `JSON.stringify`로 싣는다.
    pub fn to_v(&self) -> V {
        let o = Obj::new();
        o.set("v", f64::from(self.v));
        o.set("uid", self.uid.as_str());
        o.set("n", self.n as f64);
        o.set("gens", f64::from(self.gens));
        for (k, col) in [("par", &self.par), ("size", &self.size), ("gen", &self.gen), ("bits", &self.bits), ("edge", &self.edge), ("branch", &self.branch), ("color", &self.color), ("color2", &self.color2)] { o.set(k, ints(col)); }
        o.set("name", strs(&self.name));
        o.set("sub", strs(&self.sub));
        o.set("key", strs(&self.key));
        o.set("extra", ints(&self.extra));
        o.set("colors", strs(&self.colors));
        o.set("branches", V::Arr(js::Arr::new(self.branches.iter().map(|b| {
            let x = Obj::new();
            x.set("uid", b.uid.clone());
            x.set("name", b.name.clone());
            x.set("color", b.color.clone());
            x.set("at", f64::from(b.at));
            x.set("up", f64::from(b.up));
            V::Obj(x)
        }).collect())));
        let cells = Obj::new();
        for (k, v) in &self.cells { cells.set(k, f64::from(*v)); }
        o.set("cells", cells);
        let stubs = Obj::new();
        for (k, st) in &self.stubs {
            let x = Obj::new();
            x.set("key", st.key.as_str());
            x.set("n", f64::from(st.n));
            stubs.set(&(*k as f64), x);
        }
        o.set("stubs", stubs);
        o.set("warnings", V::Arr(js::Arr::new(self.warnings.iter().map(|w| V::from(w.as_str())).collect())));
        if let Some(r) = &self.root {
            let x = Obj::new();
            x.set("uid", r.uid.as_str());
            x.set("at", f64::from(r.at));
            x.set("up", r.up.as_str());
            x.set("upAt", f64::from(r.up_at));
            o.set("root", x);
        }
        if let Some(fr) = &self.extra_far { o.set("extraFar", far_v(fr)); }
        V::Obj(o)
    }
    /// 열 꼴 기록 JSON(`to_v`의 되읽기 — 벡터 검사가 Node의 기록에서 다시 지을 때).
    pub fn from_v(v: &V) -> Rec {
        let col = |k: &str| -> Vec<i32> { list(&v.get(k)).iter().map(|x| js::to_i32(js::to_num(x))).collect() };
        let txt = |k: &str| -> Vec<Str> { list(&v.get(k)).iter().map(js::to_str).collect() };
        let cells = v.get("cells").as_obj().map(|o| o.entries().into_iter().map(|(k, x)| (k, js::to_i32(js::to_num(&x)))).collect()).unwrap_or_default();
        let stubs = v.get("stubs").as_obj().map(|o| o.entries().into_iter().map(|(k, x)| (k.as_str().parse().expect("꼬투리 번호"), Stub { key: t(&x.get("key")), n: js::to_i32(js::to_num(&x.get("n"))) })).collect()).unwrap_or_default();
        let root = v.get("root");
        let far = v.get("extraFar");
        Rec {
            v: js::to_i32(js::to_num(&v.get("v"))), uid: t(&v.get("uid")), n: js::to_num(&v.get("n")) as usize, gens: js::to_i32(js::to_num(&v.get("gens"))),
            par: col("par"), size: col("size"), gen: col("gen"), bits: col("bits"), edge: col("edge"), branch: col("branch"), color: col("color"), color2: col("color2"),
            name: txt("name"), sub: txt("sub"), key: txt("key"), extra: col("extra"), colors: txt("colors"),
            branches: list(&v.get("branches")).iter().map(|b| RBranch { uid: js::to_str(&b.get("uid")), name: js::to_str(&b.get("name")), color: js::to_str(&b.get("color")), at: js::to_i32(js::to_num(&b.get("at"))), up: js::to_i32(js::to_num(&b.get("up"))) }).collect(),
            cells, stubs, warnings: list(&v.get("warnings")).iter().map(t).collect(),
            root: if tv(&root) { Some(RootRef { uid: t(&root.get("uid")), at: js::to_i32(js::to_num(&root.get("at"))), up: t(&root.get("up")), up_at: js::to_i32(js::to_num(&root.get("upAt"))) }) } else { None },
            extra_far: if tv(&far) { Some(list(&far).iter().map(|f| Far { from: js::to_str(&f.get("from")), from_at: js::to_i32(js::to_num(&f.get("fromAt"))), to: js::to_i32(js::to_num(&f.get("to"))), kind: js::to_i32(js::to_num(&f.get("kind"))), gen: js::to_i32(js::to_num(&f.get("gen"))) }).collect()) } else { None },
        }
    }
    fn stub_at(&self, k: usize) -> Option<&Stub> { self.stubs.iter().find(|x| x.0 == k).map(|x| &x.1) }
}
fn far_v(fr: &[Far]) -> V {
    V::Arr(js::Arr::new(fr.iter().map(|f| {
        let x = Obj::new();
        x.set("from", f.from.clone());
        x.set("fromAt", f64::from(f.from_at));
        x.set("to", f64::from(f.to));
        x.set("kind", f64::from(f.kind));
        x.set("gen", f64::from(f.gen));
        V::Obj(x)
    }).collect()))
}

/// `sizeOf(skel)` — 뼈대의 마디 수.
fn size_of(sk: Option<&Skel>) -> usize { sk.map_or(0, |s| s.n) }
/// `extraTuples(src)` — 덧선을 [from, to, 갈래, gen] 줄들로(웹 뼈대는 평평한 정수 열 — 넷씩).
fn extra_tuples(src: &[i32]) -> Vec<[i32; 4]> { src.chunks_exact(4).map(|q| [q[0], q[1], q[2], q[3]]).collect() }
/// `byExtra` · `flat(tuples)` — 덧선의 고정 차례 (to, from, 갈래, gen) 오름으로 펴기(같은 줄은 값이 같아 차례가 답에 닿지 않음).
fn flat(mut tuples: Vec<[i32; 4]>) -> Vec<i32> {
    tuples.sort_by(|a, b| (a[1], a[0], a[2], a[3]).cmp(&(b[1], b[0], b[2], b[3])));
    tuples.into_iter().flatten().collect()
}
/// `sortedCells(entries)` — 칸 표(칸 열쇠 → 번호)의 고정 차례 — 번호 · 열쇠 오름(같은 열쇠는 뒤의 값 · 자리는 처음).
fn sorted_cells(mut entries: Vec<(Str, i32)>) -> Vec<(Str, i32)> {
    js::sort_by(&mut entries, |a, b| { let d = f64::from(a.1) - f64::from(b.1); if d != 0.0 { d } else { match a.0.cmp16(&b.0) { std::cmp::Ordering::Less => -1.0, std::cmp::Ordering::Greater => 1.0, _ => 0.0 } } });
    let mut o: Vec<(Str, i32)> = Vec::new();
    for (k, v) in entries { match o.iter_mut().find(|x| x.0 == k) { Some(x) => x.1 = v, None => o.push((k, v)) } }
    o
}
/// `gensOf(gen)` — 가장 큰 세대 + 1.
fn gens_of(gen: &[i32]) -> i32 { gen.iter().fold(-1, |g, &v| if v > g { v } else { g }) + 1 }

/// `recordOf(skel, uid)` — 뼈대 → 나누지 않은 열 꼴 기록 하나.
pub fn record_of(sk: &Skel, uid: &str) -> Rec {
    let n = size_of(Some(sk));
    let ints = |src: &[i32], fill: i32| -> Vec<i32> { (0..n).map(|i| src.get(i).copied().unwrap_or(fill)).collect() };
    let strs = |src: &[V]| -> Vec<Str> { (0..n).map(|i| match src.get(i) { Some(x) if !x.is_nullish() => js::to_str(x), _ => Str::default() }).collect() };
    // 색: 뼈대가 색 표를 준다(웹 뼈대는 늘 — 색 열에 글을 담은 꼴은 닿지 않음)
    let colors: Vec<Str> = sk.colors.iter().map(|c| js::to_str(&js::nullish(c.clone(), s("")))).collect();
    let color = ints(&sk.color, 0);
    let mut color2 = if sk.color2.is_empty() { Vec::new() } else { ints(&sk.color2, 0) };
    if !color2.is_empty() && !color2.iter().any(|&x| x != 0) { color2 = Vec::new(); } // 두 나라 지도자가 없으면 빈 열
    let color_text = |c: &V| -> Str { match c { V::Num(x) => colors.get(*x as usize).cloned().unwrap_or_default(), x if x.is_nullish() => Str::default(), x => js::to_str(x) } };
    let branches = sk.branches.iter().map(|b| RBranch {
        uid: js::to_str(&js::or(b.uid.clone(), s(""))), name: js::to_str(&js::or(b.name.clone(), s(""))), color: color_text(&b.color), at: b.at, up: b.up,
    }).collect();
    let gen = ints(&sk.gen, 0);
    Rec {
        v: KIN_VERSION, uid: uid.to_string(), n, gens: gens_of(&gen),
        par: ints(&sk.par, -1), size: ints(&sk.size, 1), gen, bits: ints(&sk.bits, 0), edge: ints(&sk.edge, 0), branch: ints(&sk.branch, 0), color, color2,
        name: strs(&sk.name), sub: strs(&sk.sub), key: strs(&sk.key), extra: flat(extra_tuples(&sk.extra)), colors, branches,
        cells: sorted_cells(sk.cells.clone()), stubs: Vec::new(), warnings: sk.warnings.clone(), root: None, extra_far: None,
    }
}

/// `chunkUid(rec, s)` — 덩어리 uid: 꼬투리 마디가 파조면 그 파의 `kin:<파 가문 id>`, 아니면 `<뿌리 뼈대 uid>#<안정 열쇠>`.
fn chunk_uid(rec: &Rec, s_: usize) -> String {
    if rec.bits[s_] & bit::FOUNDER != 0 {
        if let Some(b) = rec.branches.iter().find(|x| x.at == s_ as i32 && !x.uid.is_empty()) {
            let u = b.uid.as_str();
            return format!("kin:{}", u.strip_prefix("house:").unwrap_or(&u));
        }
    }
    format!("{}#{}", rec.uid, rec.key[s_])
}
fn far_sort(fr: &mut [Far]) { js::sort_by(fr, |a, b| [a.to - b.to, a.from_at - b.from_at, a.kind - b.kind, a.gen - b.gen].into_iter().find(|d| *d != 0).map_or(0.0, f64::from)); }

/// `splitKin(rec, limit)` — 나누지 않은 기록 → 덩어리 기록들(뿌리 기록이 첫째). 상한을 넘지 않으면 [rec] 그대로.
pub fn split_kin(rec: &Rec, limit: usize) -> Vec<Rec> {
    let n = rec.n;
    if n <= limit { return vec![rec.clone()]; }
    let (size, par, bits) = (&rec.size, &rec.par, &rec.bits);
    let mut cut: Vec<usize> = Vec::new(); // 뗀 마디(넣은 차례 — JS Set)
    let has = |cut: &[usize], i: usize| cut.contains(&i);
    let sorted = |cut: &[usize]| -> Vec<usize> { let mut c = cut.to_vec(); c.sort_unstable(); c };
    /* 덩어리(뿌리 r — 뿌리 기록은 −1)의 마디들(앞 차례 · 꼬투리 포함) */
    let nodes_of = |cut: &[usize], r: i64| -> Vec<usize> {
        let mut out = Vec::new();
        let end = if r < 0 { n } else { r as usize + size[r as usize] as usize };
        let mut i = if r < 0 { 0 } else { r as usize };
        while i < end {
            out.push(i);
            i += if has(cut, i) && i as i64 != r { size[i] as usize } else { 1 };
        }
        out
    };
    let mut warnings: Vec<String> = Vec::new();
    for _guard in 0..n {
        let mut moved = false;
        let roots: Vec<i64> = std::iter::once(-1).chain(sorted(&cut).into_iter().map(|x| x as i64)).collect();
        for r in roots {
            loop {
                let lst = nodes_of(&cut, r);
                if lst.len() <= limit { break; }
                // 덩어리 안 하위 수(꼬투리는 1)를 뒤에서부터 모은다
                let mut sub: HashMap<usize, usize> = HashMap::new();
                for &i in lst.iter().rev() {
                    *sub.entry(i).or_insert(0) += 1;
                    let p = par[i];
                    if i as i64 != r && p >= 0 { let si = sub[&i]; *sub.entry(p as usize).or_insert(0) += si; }
                }
                let mut best: i64 = -1;
                let mut best_key: Option<(i32, usize)> = None;
                for &i in &lst {
                    if i as i64 == r || has(&cut, i) { continue; }
                    let sv = sub[&i];
                    if sv < 2 || sv >= lst.len() { continue; } // 덩어리 전체를 품는 마디는 떼어도 줄지 않는다
                    let key = (if bits[i] & bit::FOUNDER != 0 { 1 } else { 0 }, sv);
                    if best_key.is_none_or(|bk| key.0 > bk.0 || (key.0 == bk.0 && key.1 > bk.1)) { best = i as i64; best_key = Some(key); }
                }
                if best < 0 {
                    warnings.push(format!("덩어리 {}의 마디 {}개가 상한 {limit}을 넘지만 뗄 하위 나무가 없어 나누지 않았습니다.", if r < 0 { rec.uid.clone() } else { chunk_uid(rec, r as usize) }, lst.len()));
                    break;
                }
                cut.push(best as usize);
                moved = true;
            }
        }
        if !moved { break; }
    }
    if cut.is_empty() {
        let mut one = rec.clone();
        one.warnings = rec.warnings.iter().cloned().chain(warnings).collect();
        return vec![one];
    }
    // 마디마다 제 집(꼬투리가 아닌 자리로 든 덩어리의 뿌리 — 뿌리 기록은 −1)
    let mut home = vec![-1i64; n];
    for i in 0..n { home[i] = if has(&cut, i) { i as i64 } else if par[i] >= 0 { home[par[i] as usize] } else { -1 }; }
    let roots: Vec<i64> = std::iter::once(-1).chain(sorted(&cut).into_iter().map(|x| x as i64)).collect();
    let uid_of = |r: i64| if r < 0 { rec.uid.clone() } else { chunk_uid(rec, r as usize) };
    let lists: HashMap<i64, Vec<usize>> = roots.iter().map(|&r| (r, nodes_of(&cut, r))).collect();
    let local: HashMap<i64, HashMap<usize, i32>> = roots.iter().map(|&r| (r, lists[&r].iter().enumerate().map(|(k, &i)| (i, k as i32)).collect())).collect();
    let mut tuples: HashMap<i64, Vec<[i32; 4]>> = roots.iter().map(|&r| (r, Vec::new())).collect();
    let mut far: HashMap<i64, Vec<Far>> = roots.iter().map(|&r| (r, Vec::new())).collect();
    for q in rec.extra.chunks_exact(4) {
        let (from, to, kind, gen) = (q[0] as usize, q[1] as usize, q[2], q[3]);
        let h_to = home[to];
        if home[from] == h_to { tuples.get_mut(&h_to).expect("덩어리").push([local[&h_to][&from], local[&h_to][&to], kind, gen]); }
        else { far.get_mut(&h_to).expect("덩어리").push(Far { from: rec.key[from].clone(), from_at: from as i32, to: local[&h_to][&to], kind, gen }); }
    }
    let mut cells_by: HashMap<i64, Vec<(Str, i32)>> = roots.iter().map(|&r| (r, Vec::new())).collect();
    for (key, i) in &rec.cells { let h = home[*i as usize]; cells_by.get_mut(&h).expect("덩어리").push((key.clone(), local[&h][&(*i as usize)])); }
    let mut out: Vec<Rec> = Vec::new();
    for &r in &roots {
        let lst = &lists[&r];
        let map = &local[&r];
        let m = lst.len();
        let pick = |col: &[i32]| -> Vec<i32> { lst.iter().map(|&i| col[i]).collect() };
        let pick_s = |col: &[Str]| -> Vec<Str> { lst.iter().map(|&i| col[i].clone()).collect() };
        let par_l: Vec<i32> = lst.iter().map(|&i| if i as i64 == r || par[i] < 0 { -1 } else { map[&(par[i] as usize)] }).collect();
        let mut size_l = vec![1i32; m];
        for k in (1..m).rev() { if par_l[k] >= 0 { let p = par_l[k] as usize; size_l[p] += size_l[k]; } }
        let bits_l: Vec<i32> = lst.iter().map(|&i| if has(&cut, i) && i as i64 != r { bits[i] | bit::STUB } else { bits[i] }).collect();
        let stubs: Vec<(usize, Stub)> = lst.iter().enumerate().filter(|(_, &i)| has(&cut, i) && i as i64 != r).map(|(k, &i)| (k, Stub { key: uid_of(i as i64), n: size[i] })).collect();
        let gen = pick(&rec.gen);
        let mut o = Rec {
            v: rec.v, uid: uid_of(r), n: m, gens: gens_of(&gen), par: par_l, size: size_l, gen, bits: bits_l,
            edge: pick(&rec.edge), branch: pick(&rec.branch), color: pick(&rec.color),
            color2: if !rec.color2.is_empty() && lst.iter().any(|&i| rec.color2[i] != 0) { pick(&rec.color2) } else { Vec::new() },
            name: pick_s(&rec.name), sub: pick_s(&rec.sub), key: pick_s(&rec.key), extra: flat(tuples[&r].clone()), colors: rec.colors.clone(), branches: rec.branches.clone(),
            cells: sorted_cells(cells_by[&r].clone()), stubs, warnings: if r < 0 { rec.warnings.iter().cloned().chain(warnings.iter().cloned()).collect() } else { Vec::new() },
            root: None, extra_far: None,
        };
        if r >= 0 {
            let ru = r as usize;
            let up = if par[ru] >= 0 { home[par[ru] as usize] } else { -1 }; // 꼬투리를 가진 덩어리
            o.root = Some(RootRef { uid: rec.uid.clone(), at: r as i32, up: uid_of(up), up_at: local[&up][&ru] });
            let mut fr = far[&r].clone();
            if !fr.is_empty() { far_sort(&mut fr); o.extra_far = Some(fr); }
        }
        out.push(o);
    }
    // 뿌리 덩어리에 든 '다른 덩어리 부모'의 덧선은 자식 쪽에 싣는다 — far(-1)은 자식이 뿌리 덩어리에 있고 부모가 덩어리에 있는 선
    let mut root_far = far[&-1].clone();
    if !root_far.is_empty() { far_sort(&mut root_far); out[0].extra_far = Some(root_far); }
    out
}

/// `joinKin(records)` — 덩어리 기록들 → 하나로 합친 기록(앱 kin_record.dart의 본보기). 모든 덩어리를 받으면 나누지 않은 한 벌과 바이트까지 같다.
pub fn join_kin(records: &[Rec]) -> Rec {
    let main = records.iter().find(|r| r.root.is_none()).unwrap_or(&records[0]);
    let by_uid: HashMap<&str, &Rec> = { let mut m = HashMap::new(); for r in records { m.insert(r.uid.as_str(), r); } m }; // new Map — 같은 uid는 뒤의 것
    let mut seq: Vec<(&Rec, usize)> = Vec::new();
    fn walk<'a>(rec: &'a Rec, by_uid: &HashMap<&str, &'a Rec>, seq: &mut Vec<(&'a Rec, usize)>) {
        for k in 0..rec.n {
            let child = rec.stub_at(k).and_then(|st| by_uid.get(st.key.as_str()).copied());
            match child { Some(c) if !std::ptr::eq(c, rec) => walk(c, by_uid, seq), _ => seq.push((rec, k)) }
        }
    }
    walk(main, &by_uid, &mut seq);
    let n = seq.len();
    let mut at: HashMap<&str, HashMap<usize, i32>> = HashMap::new();
    for (i, (rec, k)) in seq.iter().enumerate() { at.entry(rec.uid.as_str()).or_default().insert(*k, i as i32); }
    let col = |f: fn(&Rec) -> &Vec<i32>| -> Vec<i32> { seq.iter().map(|(rec, k)| f(rec)[*k]).collect() };
    let col_s = |f: fn(&Rec) -> &Vec<Str>| -> Vec<Str> { seq.iter().map(|(rec, k)| f(rec)[*k].clone()).collect() };
    let par: Vec<i32> = seq.iter().map(|(rec, k)| {
        if rec.par[*k] >= 0 { return at[rec.uid.as_str()][&(rec.par[*k] as usize)]; }
        if let Some(root) = &rec.root {
            // 덩어리의 뿌리 — 꼬투리의 부모(꼬투리를 가진 기록 안)
            let up = by_uid.get(root.up.as_str());
            let p = up.map_or(-1, |u| u.par[root.up_at as usize]);
            return if p >= 0 { at[up.expect("위 기록").uid.as_str()][&(p as usize)] } else { -1 };
        }
        -1
    }).collect();
    let mut size = vec![1i32; n];
    for i in (1..n).rev() { if par[i] >= 0 { let p = par[i] as usize; size[p] += size[i]; } }
    let mut key_at: HashMap<Str, i32> = HashMap::new();
    for (i, (rec, k)) in seq.iter().enumerate() { key_at.insert(rec.key[*k].clone(), i as i32); }
    let mut tuples: Vec<[i32; 4]> = Vec::new();
    let mut far: Vec<Far> = Vec::new();
    for rec in records {
        let Some(map) = at.get(rec.uid.as_str()) else { continue };
        for q in rec.extra.chunks_exact(4) { tuples.push([map[&(q[0] as usize)], map[&(q[1] as usize)], q[2], q[3]]); }
        for f in rec.extra_far.iter().flatten() {
            match key_at.get(&f.from) {
                Some(&from) => tuples.push([from, map[&(f.to as usize)], f.kind, f.gen]),
                None => far.push(Far { from: f.from.clone(), from_at: f.from_at, to: map[&(f.to as usize)], kind: f.kind, gen: f.gen }),
            }
        }
    }
    let mut cells: Vec<(Str, i32)> = Vec::new();
    let mut stubs: Vec<(usize, Stub)> = Vec::new();
    for rec in records {
        let Some(map) = at.get(rec.uid.as_str()) else { continue };
        for (key, k) in &rec.cells { cells.push((key.clone(), map[&(*k as usize)])); }
        for (k, st) in &rec.stubs {
            if !by_uid.contains_key(st.key.as_str()) && map.contains_key(k) {
                let at_k = map[k] as usize;
                match stubs.iter_mut().find(|x| x.0 == at_k) { Some(x) => x.1 = st.clone(), None => stubs.push((at_k, st.clone())) }
            }
        }
    }
    stubs.sort_by_key(|x| x.0); // 정수 열쇠 객체 — 오름차순
    let gen = col(|r| &r.gen);
    let color2: Vec<i32> = seq.iter().map(|(rec, k)| if rec.color2.is_empty() { 0 } else { rec.color2[*k] }).collect();
    let mut o = Rec {
        v: main.v, uid: main.uid.clone(), n, gens: gens_of(&gen), par, size, gen,
        bits: seq.iter().map(|(rec, k)| if rec.stub_at(*k).is_some_and(|st| by_uid.contains_key(st.key.as_str())) { rec.bits[*k] & !bit::STUB } else { rec.bits[*k] }).collect(),
        edge: col(|r| &r.edge), branch: col(|r| &r.branch), color: col(|r| &r.color), color2: if color2.iter().any(|&x| x != 0) { color2 } else { Vec::new() },
        name: col_s(|r| &r.name), sub: col_s(|r| &r.sub), key: col_s(|r| &r.key), extra: flat(tuples), colors: main.colors.clone(), branches: main.branches.clone(),
        cells: sorted_cells(cells), stubs, warnings: main.warnings.iter().filter(|w| !w.starts_with("덩어리 ")).cloned().collect(), root: None, extra_far: None,
    };
    if !far.is_empty() { far_sort(&mut far); o.extra_far = Some(far); }
    o
}

/* ── 모델 → 뼈대 기록 · 사람 자리 · 가문 x_kin (entities가 부른다) ── */

/// 덩어리 구간 `{ uid, at(한 벌 번호 — 뿌리 기록은 −1), end }`.
#[derive(Clone)]
struct Part { uid: String, at: i64, end: i64 }
/// `homeOf(parts, i)` — 이 뼈대의 마디 i가 든 기록(덩어리) uid.
fn home_of(parts: &[Part], i: i64) -> String {
    let mut best = &parts[0];
    for p in parts { if p.at >= 0 && i >= p.at && i < p.end && (best.at < 0 || p.at >= best.at) { best = p; } }
    best.uid.clone()
}
/// 기록 하나 `{ uid, body, rootUid, houseId | polityUid }`.
pub struct KinRecord { pub uid: String, pub body: Rec, pub root_uid: String, pub house_id: Option<V>, pub polity_uid: Option<String> }
/// 사람 자리 → 뼈대 자리 `{ key, at, member, chunk? }`.
#[derive(Clone)]
pub struct PersonAt { pub key: String, pub at: usize, pub member: bool, pub chunk: Option<String> }
/// `kinCollect`의 답.
pub struct KinOut {
    pub records: Vec<KinRecord>,
    pub person_at: HashMap<Str, PersonAt>,
    /// '<정권 uid>|leader:3' → (뼈대 uid, 번호)
    pub cell_at: HashMap<Str, (String, i32)>,
    /// 가문 id → x_kin(JS 객체 — 열쇠 차례 그대로)
    pub house_kin: Map,
    pub notes: Obj,
    chunk_spans: HashMap<String, Vec<Part>>,
    /// 뿌리 기록의 uid(`kin.roots` — entities가 단다)
    pub roots: std::collections::HashSet<String>,
}
impl KinOut {
    /// `chunkAt(key, i)` — 한 벌 번호 → 나눈 덩어리 uid(안이면).
    pub fn chunk_at(&self, key: &str, i: i64) -> Option<String> {
        let sp = self.chunk_spans.get(key)?;
        let u = home_of(sp, i);
        if u == key { None } else { Some(u) }
    }
}
/// 뼈대 주인 `{ houseId }` · `{ polityUid }`.
enum Owner { House(V), Polity(String) }

/// `kinCollect(model, HT, { limit })` — 모델의 모든 뼈대를 지어 기록으로: 기록 · 사람 자리 → 뼈대 자리 · 칸 → 뼈대 자리 · 가문 x_kin · 집계.
/// (웹 도우미 `HT.kinSkeleton`은 늘 있다 — 옮긴 웹 코드에 있으므로 null 갈래는 모델이 없을 때뿐.)
pub fn kin_collect(cache: &mut KinCache, model: &V, limit: usize) -> Option<KinOut> {
    if !tv(model) { return None; }
    let houses = list(&model.get("houses"));
    let mut keys: Vec<(String, Owner)> = Vec::new();
    let mut seen_key: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut want = |keys: &mut Vec<(String, Owner)>, key: String, owner: Owner| {
        if key.is_empty() || seen_key.contains(&key) { return; }
        seen_key.insert(key.clone());
        keys.push((key, owner));
    };
    // 뿌리 가문(본가 길의 맨 위)마다 하나
    for h in &houses {
        let path = h.get("path");
        let top = if tv(&path) && tv(&path.get("length")) { path.get(&0.0) } else { h.get("id") };
        if js::strict_eq(&top, &h.get("id")) { want(&mut keys, format!("kin:{}", t(&h.get("id"))), Owner::House(h.get("id"))); }
    }
    // 가문이 없는 지도자가 있는 정권 — HT.kinOf가 'kin:polity:…'를 주는 것
    for p in list(&model.get("periods")) {
        if !is(&p.get("kind"), "period") { continue; }
        for i in 0..list(&p.get("leaders")).len() {
            if let Some((k, _)) = kin_of(cache, model, &p, i) {
                if let Some(rest) = k.strip_prefix("kin:polity:") { let pu = rest.to_string(); want(&mut keys, k.clone(), Owner::Polity(pu)); }
            }
        }
    }
    let mut records: Vec<KinRecord> = Vec::new();
    let mut person_at: HashMap<Str, PersonAt> = HashMap::new();
    let mut cell_at: HashMap<Str, (String, i32)> = HashMap::new();
    let house_kin = Map::new();
    let (mut n_skel, mut n_chunk, mut n_node, mut n_max) = (0.0, 0.0, 0.0, 0.0f64);
    let mut chunk_spans: HashMap<String, Vec<Part>> = HashMap::new();
    for (key, owner) in keys {
        let sk = kin_skeleton(cache, model, &key);
        let n = size_of(sk.as_deref());
        if n == 0 { continue; }
        let sk = sk.expect("뼈대");
        let rec = record_of(&sk, &key);
        let parts = split_kin(&rec, limit);
        n_skel += 1.0;
        n_chunk += (parts.len() - 1) as f64;
        n_node += n as f64;
        n_max = js::max(&[n_max, n as f64]);
        let spans: Vec<Part> = parts.iter().map(|p| match &p.root { Some(r) => Part { uid: p.uid.clone(), at: i64::from(r.at), end: i64::from(r.at) + i64::from(rec.size[r.at as usize]) }, None => Part { uid: p.uid.clone(), at: -1, end: n as i64 } }).collect();
        let chunk_of = |i: i64| -> Option<String> { let u = home_of(&spans, i); if u == key { None } else { Some(u) } };
        chunk_spans.insert(key.clone(), spans.clone());
        for p in &parts {
            records.push(KinRecord {
                uid: p.uid.clone(), body: p.clone(), root_uid: key.clone(),
                house_id: if let Owner::House(h) = &owner { Some(h.clone()) } else { None },
                polity_uid: if let Owner::Polity(u) = &owner { Some(u.clone()) } else { None },
            });
        }
        // 사람 자리 → 뼈대 자리(구성원으로 든 곳이 먼저)
        for i in 0..n {
            let k = rec.key[i].clone();
            let member = rec.bits[i] & bit::MEMBER != 0;
            if let Some(cur) = person_at.get(&k) { if cur.member || !member { continue; } }
            person_at.insert(k, PersonAt { key: key.clone(), at: i, member, chunk: chunk_of(i as i64) });
        }
        for (cell, i) in &rec.cells { cell_at.entry(cell.clone()).or_insert_with(|| (key.clone(), *i)); }
        // 가문 x_kin — 뿌리 가문과 그 아래 파마다
        let b_ = &rec.branches;
        let under = |b: usize| -> Vec<usize> {
            let mut out = Vec::new();
            for j in 0..b_.len() {
                let (mut u, mut guard) = (j as i64, 0usize);
                while u >= 0 && guard <= b_.len() {
                    if u == b as i64 { out.push(j); break; }
                    u = i64::from(b_[u as usize].up);
                    guard += 1;
                }
            }
            out
        };
        let owner_house = if let Owner::House(h) = &owner { Some(h.clone()) } else { None };
        struct Range { at: i64, n: i64, gens: i64, is_root: bool }
        let range_of = |b: usize| -> Range {
            // 파의 뿌리 번호(파조 · 못 풀면 그 파 마디를 모두 품는 가장 작은 하위 나무) · 사람 수 · 세대 줄 수
            let set: Vec<usize> = under(b);
            let in_set = |x: i32| x >= 0 && set.contains(&(x as usize));
            let mut at = i64::from(b_[b].at);
            let is_root = b_[b].up < 0 && owner_house.as_ref().is_some_and(|h| tv(h) && b_[b].uid == format!("house:{}", t(h)).as_str());
            if is_root { at = -1; }
            else if at < 0 {
                // 가장 작은 하위 나무 — 공통 조상
                let mut lca: i64 = -2;
                for i in 0..n {
                    if !in_set(rec.branch[i]) || rec.bits[i] & bit::MEMBER == 0 { continue; }
                    if lca == -2 { lca = i as i64; continue; }
                    let mut a = lca;
                    while a >= 0 && !(i as i64 >= a && (i as i64) < a + i64::from(rec.size[a as usize])) { a = i64::from(rec.par[a as usize]); }
                    lca = a;
                    if lca < 0 { break; }
                }
                at = if lca >= 0 { lca } else { -1 };
            }
            let (mut cnt, mut lo, mut hi) = (0i64, f64::INFINITY, f64::NEG_INFINITY);
            let mut take = |i: usize| { cnt += 1; let g = f64::from(rec.gen[i]); if g < lo { lo = g; } if g > hi { hi = g; } };
            if is_root { for i in 0..n { take(i); } }
            else if at >= 0 { for i in at as usize..(at as usize + rec.size[at as usize] as usize) { take(i); } }
            else { for i in 0..n { if in_set(rec.branch[i]) { take(i); } } }
            Range { at, n: cnt, gens: if cnt > 0 { (hi - lo + 1.0) as i64 } else { 0 }, is_root }
        };
        for (j, b) in b_.iter().enumerate() {
            let u = b.uid.as_str();
            let id = u.strip_prefix("house:").unwrap_or(&u).to_string();
            if id.is_empty() || house_kin.has(&V::from(id.as_str())) { continue; }
            let r = range_of(j);
            if r.n == 0 && !r.is_root { continue; }
            let o = Obj::new();
            o.set("key", key.as_str());
            if r.at >= 0 {
                o.set("at", r.at as f64);
                if let Some(ch) = chunk_of(r.at) { o.set("chunk", ch); }
            }
            o.set("n", r.n as f64);
            o.set("gens", r.gens as f64);
            o.set("branches", V::Arr(js::Arr::new(under(j).into_iter().filter(|&q| q != j).map(|q| {
                let rq = range_of(q);
                let x = Obj::new();
                x.set("uid", b_[q].uid.clone());
                x.set("name", b_[q].name.clone());
                x.set("color", b_[q].color.clone());
                x.set("n", rq.n as f64);
                V::Obj(x)
            }).collect())));
            house_kin.set(V::from(id), o);
        }
        if let Some(h) = &owner_house {
            if tv(h) && !house_kin.has(h) {
                // 파 표에 뿌리 가문이 없는 뼈대 — 뿌리 가문은 한 벌 전체
                let o = Obj::new();
                o.set("key", key.as_str());
                o.set("n", n as f64);
                o.set("gens", f64::from(rec.gens));
                o.set("branches", V::Arr(js::Arr::new(b_.iter().enumerate().map(|(j, b)| {
                    let x = Obj::new();
                    x.set("uid", b.uid.clone());
                    x.set("name", b.name.clone());
                    x.set("color", b.color.clone());
                    x.set("n", range_of(j).n as f64);
                    V::Obj(x)
                }).collect())));
                house_kin.set(h.clone(), o);
            }
        }
    }
    let notes = Obj::new();
    notes.set("뼈대", n_skel);
    notes.set("덩어리", n_chunk);
    notes.set("마디", n_node);
    notes.set("가장큰뼈대", n_max);
    Some(KinOut { records, person_at, cell_at, house_kin, notes, chunk_spans, roots: Default::default() })
}

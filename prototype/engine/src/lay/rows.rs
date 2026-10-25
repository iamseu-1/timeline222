//! 줄 배정의 둘레 — `_layoutTrack`(→ [`super::track`])이 부르는 `js/timeline.js`의 맨 위 도우미 · 연표 메서드와 `js/core.js`의 `HT.*` 몇을 줄 그대로 옮긴다(한 벌 P3 과제 7).
//!
//! 옮긴 원본: `js/timeline.js` — SHA-256 앞 12자 `8a3b02f5bf7f`(저장소의 LF 바이트)
//! - 11 ~ 23줄 `intervalIndex`(→ [`interval_index`])
//! - 50 ~ 56줄 `G`(+ `Object.assign(G, …)` 여섯 — 수 값만: `G.thin`은 그리기 몫이라 뺌) · 68줄 `HANG` · 76줄 `G_BIRD`(→ [`G`] · [`G0`] · [`HANG_PITCH`])
//! - 228줄 `overlaps` · 345 ~ 346줄 `bandStart` · `bandEnd` · 429 ~ 435줄 `SUCC_KINDS`의 `rank` · `succKind`
//! - 514 ~ 569줄 `succRank` · `chainRows` · 573 ~ 581줄 `packChains`
//! - 1757 ~ 1762줄 `_G`(조감 값 묶음의 기억 `_gb`는 답이 같아 두지 않음) · 1808 ~ 1810줄 `_hangsFolded`
//! - 3706 ~ 3720줄 `_precSpan` · 3724 ~ 3729줄 `_placeAt` · 3742 ~ 3748줄 `_extent`
//! - 6808 ~ 6810줄 `_dynOf` · 7023 ~ 7027줄 `_figSpan` · 8854 ~ 8857줄 `_foldedNow`(`BOARD_ID` 47줄)
//! - (2026-10-25 맞춤 · 4단계 배치 갈래 둘째 · `timeline.js` `b2694a223fec`) 1854 ~ 1897줄 `_leaderLanes`(→ [`leader_lanes`] · [`LeaderLanes`] — 지도자 칸의 단 나누기 ·
//!   내보내기 `strips.mjs`가 칸 종류 1의 lane으로 부름)
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`
//! - 2031 ~ 2035줄 `HT.POWER_WORDS` · `HT.powerSpanKind` · 2037줄 `lensGroupOk` · 2042 ~ 2092줄 `groupSpanCells` · 2098 ~ 2118줄 `HT.groupStrip`
//!   (정권마다의 기억 `stripMemo` · 얼린 빈 답 `STRIP_NONE`은 두지 않음 — 줄 배정은 칸 수만 읽는다. 같은 객체를 다시 받아야 하는 모듈 과제가 기억을 더한다)
//! - 2204줄 `HT.lensAny` · 3069줄 `HT.clamp` · 7763줄 `HT.northOf`
//!
//! 글자 폭(`textWidth` · `inkBottom` · `altRowPlan`)은 줄 배정 길에서 불리지 않는다(훑음 — `_layoutTrack`은 글자를 재지 않음).
use crate::lay::cal;
use crate::lay::ctx::Ctx;
use crate::lay::js::{self, Obj, Set, Str, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, at_of, eq, is, le, list, lt, n, nn, ob, or, or_cmp, sub, tv};

// ── 자리 값(px) ──

/// `G`(줄 안의 자리 값 묶음 — 수 값만). 조감이면 [`g_of`]가 `G_BIRD`로 덮은 사본.
#[derive(Clone, Copy, Debug)]
pub struct G {
    pub pad: f64, pub inset: f64, pub slot_gap: f64, pub line: f64, pub rail: f64, pub rail_pitch: f64, pub dynasty: f64, pub leader: f64, pub cabinet: f64,
    pub organ: f64, pub dep: f64, pub zone_tab: f64, pub zone_gap: f64, pub zone_lanes: f64, pub gap: f64, pub member_gap: f64, pub group_gap: f64,
    pub folded: f64, pub folded_group: f64, pub hem: f64, pub bw: f64, pub pad2: f64, pub sq: f64, pub tab: f64,
    pub figure: f64, pub fig_gap: f64, pub phase: f64, pub phase_gap: f64, pub phase_max: f64, pub rank: f64, pub rank_gap: f64, pub power: f64, pub power_gap: f64,
    pub scope_head: f64, pub scope_foot: f64, pub scope_pad_x: f64, pub mini: f64, pub mini_top: f64, pub mini_pitch: f64, pub door: f64, pub radius: f64,
}
/// `G`(조감이 아닐 때).
pub const G0: G = G {
    pad: 9.0, inset: 4.0, slot_gap: 3.0, line: 21.0, rail: 14.0, rail_pitch: 7.0, dynasty: 20.0, leader: 22.0, cabinet: 21.0, organ: 20.0, dep: 20.0,
    zone_tab: 20.0, zone_gap: 3.0, zone_lanes: 3.0, gap: 8.0, member_gap: 6.0, group_gap: 14.0, folded: 34.0, folded_group: 30.0, hem: 21.0, bw: 1.0, pad2: 3.0, sq: 7.0, tab: 18.0,
    figure: 20.0, fig_gap: 3.0, phase: 20.0, phase_gap: 3.0, phase_max: 3.0, rank: 20.0, rank_gap: 3.0, power: 20.0, power_gap: 3.0,
    scope_head: 16.0, scope_foot: 6.0, scope_pad_x: 8.0, mini: 6.0, mini_top: 5.0, mini_pitch: 8.0, door: 4.4, radius: 10.0,
};
/// `HANG.pitch` — 매달린 속국 이름표 한 줄.
pub const HANG_PITCH: f64 = 13.0;

/// `tl._G()` — 조감(`tl._bird`)이면 `Object.assign({}, G, G_BIRD, { door, radius })`, 아니면 `G`.
pub fn g_of(tl: &V) -> G {
    let b = tl.get("_bird");
    if !tv(&b) { return G0; }
    G {
        pad: 4.0, gap: 6.0, member_gap: 6.0, group_gap: 6.0, tab: 0.0, hem: 0.0, folded: 22.0, folded_group: 14.0, scope_head: 12.0, scope_foot: 4.0,
        mini: 3.0, mini_top: 1.5, mini_pitch: 4.0, door: n(&b.get("door")), radius: n(&b.get("radius")), ..G0
    }
}

// ── JS 식의 뜻(옮긴 함수가 아님) ──

/// JS `a && b`(값): a가 거짓이면 a, 아니면 b.
pub fn and(a: V, b: impl FnOnce() -> V) -> V { if tv(&a) { b() } else { a } }
/// `x || 0`(수).
pub fn or0(x: f64) -> f64 { if x == 0.0 || x.is_nan() { 0.0 } else { x } }
/// `(x || [])`의 원소.
pub fn items(v: &V) -> Vec<V> { list(&or(v.clone(), arr(Vec::new()))) }
/// `Number.isInteger(v)`.
pub fn is_integer(v: &V) -> bool { matches!(v, V::Num(x) if x.is_finite() && x.trunc() == *x) }
/// `Number.isFinite(v)`(바꾸지 않음).
pub fn is_finite_num(v: &V) -> bool { matches!(v, V::Num(x) if x.is_finite()) }
/// `list.join(sep)` — null · undefined는 빈 글, 나머지는 `String(x)`.
pub fn join(vals: &[V], sep: &str) -> Str {
    let parts: Vec<Str> = vals.iter().map(|v| if v.is_nullish() { Str::default() } else { js::to_str(v) }).collect();
    Str::join(&parts, sep)
}

// ── 맨 위 도우미 ──

/// `intervalIndex(items, extent)` — 사건의 해 범위 나무 `{ entry: { item, order, lo, hi }, left, right, min, max }`(없으면 null). 원소 차례로 `extent`를 부른다.
pub fn interval_index(items: &[V], mut extent: impl FnMut(&V) -> (V, V)) -> V {
    let mut entries: Vec<V> = items.iter().enumerate().map(|(order, item)| {
        let (lo, hi) = extent(item);
        V::Obj(o! { "item" => item.clone(), "order" => order as f64, "lo" => lo, "hi" => hi })
    }).collect();
    js::sort(&mut entries, |a, b| or_cmp(sub(&a.get("lo"), &b.get("lo")), || sub(&a.get("order"), &b.get("order"))));
    fn build(entries: &[V], lo: usize, hi: usize) -> V {
        if lo >= hi { return V::Null; }
        let mid = (lo + hi) >> 1;
        let entry = entries[mid].clone();
        let left = build(entries, lo, mid);
        let right = build(entries, mid + 1, hi);
        let lmax = if tv(&left) { n(&left.get("max")) } else { f64::NEG_INFINITY };
        let rmax = if tv(&right) { n(&right.get("max")) } else { f64::NEG_INFINITY };
        let max = js::max(&[n(&entry.get("hi")), lmax, rmax]);
        V::Obj(o! { "entry" => entry, "left" => left, "right" => right, "min" => entries[lo].get("lo"), "max" => max })
    }
    build(&entries, 0, entries.len())
}

/// `overlaps(list, l, r)` — `[a, b]` 가운데 (l, r)과 겹치는 것이 있는가.
pub fn overlaps(list: &[(f64, f64)], l: f64, r: f64) -> bool { list.iter().any(|&(a, b)| a < r && l < b) }

/// `bandStart(p)` — 연대 폭이 있으면 그 처음.
pub fn band_start(p: &V) -> V { let r = p.get("startRange"); if tv(&r) { r.get(&0.0) } else { p.get("start") } }
/// `bandEnd(p)` — 연대 폭이 있으면 그 끝.
pub fn band_end(p: &V) -> V { let r = p.get("endRange"); if tv(&r) { r.get(&1.0) } else { p.get("endY") } }
/// `byStart`(`_layoutTrack` 머리) — 시작 차례, 같으면 긴 것이 먼저.
pub fn by_start(a: &V, b: &V) -> f64 { or_cmp(sub(&band_start(a), &band_start(b)), || sub(&band_end(b), &band_end(a))) }

/// `succKind(type).rank` — 직접 0 · 간접 · 부흥 1 · 부분 2(모르는 종류는 간접).
fn succ_kind_rank(ty: &V) -> f64 {
    match ty { V::Str(t) if t == "direct" => 0.0, V::Str(t) if t == "partial" => 2.0, _ => 1.0 }
}
/// `succRank(p, q)` — p가 q를 잇는 승계의 차지 차례(이음이 없으면 Infinity).
pub fn succ_rank(p: &V, q: &V) -> f64 {
    match items(&p.get("predecessors")).into_iter().find(|x| eq(&x.get("from"), q)) { None => f64::INFINITY, Some(e) => succ_kind_rank(&e.get("type")) }
}

/// 줄 울타리 `fence(q, p)`(같은 직접 그릇끼리만 한 줄).
pub type Fence<'a> = &'a dyn Fn(&V, &V) -> bool;

/// `chainRows(list, fence)` — 승계로 이어지는 정권만 같은 줄(같은 해 무리는 직접 → 강한 이음 → 이은 수가 가장 많은 배치). 줄 안의 곧바로 이음 쌍에 `_seamR` · `_seamL`을 적는다.
pub fn chain_rows(list: &[V], fence: Option<Fence>) -> Vec<Vec<V>> {
    let mut rows: Vec<Vec<V>> = Vec::new();
    let mut i = 0;
    while i < list.len() {
        let mut j = i + 1;
        while j < list.len() && eq(&band_start(&list[j]), &band_start(&list[i])) { j += 1; }
        let grp = &list[i..j];
        let greedy = grp.len() > 8;
        let mut w = Walk { grp, fence, greedy, rows: &mut rows, pick: Vec::new(), best: None };
        w.walk(0, 0.0, 0.0, 0.0);
        let best = w.best.take().expect("배치 훑기는 늘 끝에 닿는다");
        for (k, t) in best.3.iter().enumerate() {
            if *t < 0 { rows.push(vec![grp[k].clone()]); } else { rows[*t as usize].push(grp[k].clone()); }
        }
        i = j;
    }
    for r in &rows {
        for k in 1..r.len() {
            let (q, p) = (&r[k - 1], &r[k]);
            if !q.bool("endUnknown") && !p.bool("startUnknown") && !q.bool("endRange") && !p.bool("startRange") && items(&p.get("predecessors")).iter().any(|e| eq(&e.get("from"), q)) {
                ob(q).set("_seamR", p.clone());
                ob(p).set("_seamL", q.clone());
            }
        }
    }
    rows
}
/// `chainRows`의 `walk` — 무리의 배치 훑기(best = (직접, 강함, 모두, 고른 줄)).
struct Walk<'a, 'b> { grp: &'a [V], fence: Option<Fence<'a>>, greedy: bool, rows: &'b mut Vec<Vec<V>>, pick: Vec<isize>, best: Option<(f64, f64, f64, Vec<isize>)> }
impl Walk<'_, '_> {
    fn walk(&mut self, k: usize, direct: f64, strong: f64, total: f64) {
        if k == self.grp.len() {
            let better = match &self.best {
                None => true,
                Some(b) => direct > b.0 || (direct == b.0 && (strong > b.1 || (strong == b.1 && total > b.2))),
            };
            if better { self.best = Some((direct, strong, total, self.pick.clone())); }
            return;
        }
        let p = self.grp[k].clone();
        let mut t = 0;
        while t < self.rows.len() {
            let last = self.rows[t].last().expect("줄은 비지 않는다").clone();
            let rank = if le(&band_end(&last), &band_start(&p)) && self.fence.is_none_or(|f| f(&last, &p)) { succ_rank(&p, &last) } else { f64::INFINITY };
            if rank == f64::INFINITY { t += 1; continue; }
            self.rows[t].push(p.clone());
            self.pick.push(t as isize);
            self.walk(k + 1, direct + if rank == 0.0 { 1.0 } else { 0.0 }, strong + if rank <= 1.0 { 1.0 } else { 0.0 }, total + 1.0);
            self.pick.pop();
            self.rows[t].pop();
            if self.greedy { return; }
            t += 1;
        }
        self.rows.push(vec![p]);
        self.pick.push(-1);
        self.walk(k + 1, direct, strong, total);
        self.pick.pop();
        self.rows.pop();
    }
}

/// `packChains(rows, fence)` — 사슬(줄)을 시작 차례로, 앞 줄의 마지막 띠가 그 사슬의 첫 띠보다 먼저 끝나는 첫 줄에 이어 붙인다(새 배열).
pub fn pack_chains(rows: &[Vec<V>], fence: Option<Fence>) -> Vec<Vec<V>> {
    let mut out: Vec<Vec<V>> = Vec::new();
    let mut sorted: Vec<Vec<V>> = rows.to_vec();
    js::sort_by(&mut sorted, |a, b| sub(&band_start(&a[0]), &band_start(&b[0])));
    for r in sorted {
        let into = out.iter().position(|o| lt(&band_end(o.last().expect("줄")), &band_start(&r[0])) && fence.is_none_or(|f| f(&o[0], &r[0])));
        match into { Some(k) => out[k].extend(r), None => out.push(r) }
    }
    out
}

// ── 연표 메서드 ──

/// `tl._hangsFolded(uid)`.
pub fn hangs_folded(tl: &V, uid: &V) -> bool {
    let f = tl.get("foldedHangs");
    tv(&f) && f.as_set().is_some_and(|s| s.has(uid))
}
/// `BOARD_ID`.
const BOARD_ID: &str = "__board";
/// `tl._foldedNow(id)` — 판이 서 있으면 판의 접힘, 아니면 접힘 기억(`tl.folded`).
pub fn folded_now(tl: &V, id: &V) -> V {
    if !tv(&tl.get("_boardTr")) { return V::Bool(tl.get("folded").as_set().is_some_and(|s| s.has(id))); }
    if is(id, BOARD_ID) { tl.get("_boardFolded") } else { V::Bool(!tl.get("_boardOpen").as_set().is_some_and(|s| s.has(id))) }
}
/// `tl._dynOf(p)` — 이 띠를 다스린 왕조 구간 가운데 보이는 것.
pub fn dyn_of(tl: &V, p: &V) -> Vec<V> {
    let uids = tl.get("_dynUids");
    items(&p.get("dynasties")).into_iter().filter(|d| tv(&uids) && uids.as_set().is_some_and(|s| s.has(&d.get("dynasty").get("uid")))).collect()
}
/// `tl._figSpan(s)` — 활동 막대가 차지하는 해(1년이 안 되면 가운데 1년).
pub fn fig_span(sv: &V) -> (f64, f64) {
    let (a, b) = (n(&sv.get("start")), n(&sv.get("endY")));
    if b - a >= 1.0 { return (a, b); }
    let c = (a + b) / 2.0;
    (c - 0.5, c + 0.5)
}
/// `tl._leaderLanes(p)`의 답 `{ n, lane, over }` — 단 수(1 ~ 4) · `p.leaders` 순번마다의 단 · 4단을 넘어 마지막 단에 둔 칸 수.
pub struct LeaderLanes { pub n: usize, pub lane: Vec<usize>, pub over: usize }
/// `tl._leaderLanes(p)` — 지도자 칸의 단 나누기(4단계 배치 갈래 둘째 · 감독 고름 더 정통성 넷 가 다듬은 꼴 lg2-ga · 계약 1-1 덧붙임). 자료만 보는 순수 도우미.
/// 후보 = 정통성이 섭정이 아닌 지도자 칸(시작 ~ 끝 · 끝이 없으면 `p.endY` · 수가 아니면 후보가 아니고 단 0). 공동 · 주장 칸이 다른 후보와 겹치는 띠만 나눈다
/// (겹침 = (시작, 순번) 차례로 앞 끝 > 뒤 시작). 다듬기 판 `laneOf` 그대로 첫 맞는 단 · 4단까지(넘으면 마지막 단 — `over`). 섭정은 품은 후보 → 처음 겹친 후보 → 0의 단.
pub fn leader_lanes(p: &V) -> LeaderLanes {
    struct C { i: usize, a: f64, e: f64, wide: bool }
    let list = items(&p.get("leaders"));
    let mut lane = vec![0usize; list.len()];
    let (mut cand, mut regents): (Vec<C>, Vec<C>) = (Vec::new(), Vec::new());
    for (i, c) in list.iter().enumerate() {
        if !tv(c) { continue; }
        let (a, e) = (c.get("start"), nn(c.get("end"), p.get("endY")));
        if !is_finite_num(&a) || !is_finite_num(&e) { continue; }
        let st = c.get("status");
        let u = C { i, a: n(&a), e: n(&e), wide: is(&st, "joint") || is(&st, "claim") };
        if is(&st, "regent") { regents.push(u); } else { cand.push(u); }
    }
    if !cand.iter().any(|u| u.wide) { return LeaderLanes { n: 1, lane, over: 0 }; }
    cand.sort_by(|u, v| (u.a - v.a).partial_cmp(&0.0).unwrap_or(std::cmp::Ordering::Equal).then(u.i.cmp(&v.i))); // (u, v) => u.a - v.a || u.i - v.i
    let mut open = false;
    'k: for k in 1..cand.len() {
        for j in 0..k { if cand[j].e > cand[k].a && (cand[j].wide || cand[k].wide) { open = true; break 'k; } }
    }
    if !open { return LeaderLanes { n: 1, lane, over: 0 }; }
    let mut ends: Vec<f64> = Vec::new();
    let mut over = 0;
    for u in &cand {
        let found = ends.iter().position(|&e| e <= u.a);
        if found.is_none() && ends.len() >= 4 {
            over += 1;
            ends[3] = js::max(&[ends[3], u.e]);
            lane[u.i] = 3;
            continue;
        }
        let j = found.unwrap_or(ends.len());
        if j == ends.len() { ends.push(u.e); } else { ends[j] = u.e; }
        lane[u.i] = j;
    }
    for r in &regents {
        let ward = cand.iter().find(|u| u.a <= r.a && u.e >= r.e).or_else(|| cand.iter().find(|u| u.a < r.e && r.a < u.e));
        if let Some(w) = ward { lane[r.i] = lane[w.i]; }
    }
    LeaderLanes { n: ends.len(), lane, over }
}
/// `tl._precSpan(e)` — 사건 시작의 정밀도가 덮는 구간(기억 `e._ps` · 세기 표지 `e._psCent`를 사건에 적는다).
pub fn prec_span(ctx: &Ctx, e: &V) -> V {
    let memo = e.get("_ps");
    if !memo.is_undef() { return memo; }
    let o = ob(e);
    let mut sp = V::Null;
    if !e.bool("startUnknown") {
        let at = at_of(&ctx.read, e, "start");
        let r = if tv(&at) { cal::parse(&ctx.read.cal, &at) } else { None };
        o.set("_psCent", r.as_ref().is_some_and(|r| r.span.is_some()));
        if tv(&at) {
            sp = match r.as_ref().and_then(|r| cal::prec_span(&ctx.read.cal, r)) { Some((a, b)) => arr(vec![V::Num(a), V::Num(b)]), None => V::Null };
        } else if is_integer(&e.get("start")) {
            let st = n(&e.get("start"));
            sp = arr(vec![V::Num(st), V::Num(if st == -1.0 { 0.0 } else { st + 1.0 })]);
        }
    }
    o.set("_ps", sp.clone());
    sp
}
/// `HT.clamp(v, lo, hi)`.
pub fn clamp(v: f64, lo: f64, hi: f64) -> f64 { js::min(&[hi, js::max(&[lo, v])]) }
/// `tl._placeAt(e)` — 날짜를 정확히 모르는 점 사건이 놓이는 해(정밀도 구간의 가운데 또는 `spot`).
pub fn place_at(ctx: &Ctx, e: &V) -> V {
    let sp = if lt(&e.get("start"), &e.get("endY")) { V::Null } else { prec_span(ctx, e) };
    if !tv(&sp) { return e.get("start"); }
    let spot = e.get("spot");
    let sv = if is_finite_num(&spot) { clamp(n(&spot), 0.0, 0.99) } else { 0.5 };
    let (a, b) = (n(&sp.get(&0.0)), n(&sp.get(&1.0)));
    V::Num(a + (b - a) * sv)
}
/// `tl._extent(e)` — 사건이 차지하는 해 범위 [lo, hi](연대 폭 · 이설까지).
pub fn extent(ctx: &Ctx, e: &V) -> (V, V) {
    let t = place_at(ctx, e);
    if js::strict_eq(&t, &e.get("start")) { return (nn(e.get("spanMin"), e.get("start")), nn(e.get("spanMax"), e.get("endY"))); }
    let (smin, smax) = (e.get("spanMin"), e.get("spanMax"));
    let lo = if !smin.is_nullish() && lt(&smin, &e.get("start")) { V::Num(js::min(&[n(&smin), n(&t)])) } else { t.clone() };
    let hi = if !smax.is_nullish() && lt(&e.get("endY"), &smax) { V::Num(js::max(&[n(&smax), n(&t)])) } else { t };
    (lo, hi)
}

// ── HT.* ──

/// `HT.northOf(p)` — 남북 값(수가 아니면 null · 열거되지 않는 속성 `north`).
pub fn north_of(p: &V) -> V {
    if !tv(p) { return V::Null; }
    match p.get("north") { V::Num(x) if x.is_finite() => V::Num(x), _ => V::Null }
}
/// `HT.POWER_WORDS`.
const POWER_REAL: [&str; 3] = ["실권", "섭정", "수렴청정"];
const POWER_COAL: [&str; 5] = ["연정", "공동집권", "공동", "연립", "연립정부"];
/// `HT.powerSpanKind(name)` — 빈칸을 뺀 이름이 실권 낱말이면 'real', 연정 낱말이면 'coal', 아니면 'power'.
pub fn power_span_kind(name: &V) -> &'static str {
    let text = if name.is_nullish() { Str::default() } else { js::to_str(name) };
    let squeezed: String = text.as_str().chars().filter(|c| !js::is_space(*c)).collect();
    if POWER_REAL.contains(&squeezed.as_str()) { "real" } else if POWER_COAL.contains(&squeezed.as_str()) { "coal" } else { "power" }
}
/// `lensGroupOk(g)`.
fn lens_group_ok(g: &V) -> bool { tv(g) && !is(&g.get("type"), "coalition") && !is(&g.get("type"), "regime") }
/// 단체 칸 조각(`groupSpanCells`의 `segs`).
struct Seg { g: V, c: V, a: f64, b: f64, coal: bool }
/// `groupSpanCells(p, want)` — 나라 p의 단체 칸 한 줄('power' 집권 · 'real' 실권).
pub fn group_span_cells(p: &V, want: &str) -> Vec<V> {
    let mut segs: Vec<Seg> = Vec::new();
    let mut order: Vec<V> = Vec::new();
    for l in items(&p.get("groupLinks")) {
        let g = l.get("group");
        if !is(&l.get("role"), "within") || !tv(&g) || is(&g.get("type"), "coalition") { continue; }
        let rows: Vec<V> = items(&g.get("withinList")).into_iter().filter(|w| eq(&w.get("polity"), p) || (tv(&w.get("polityUid")) && eq(&w.get("polityUid"), &p.get("uid")))).collect();
        for c in items(&g.get("powerSpans")) {
            let kind = power_span_kind(&c.get("name"));
            if (is(&g.get("type"), "regime") || kind == "real") != (want == "real") { continue; }
            for w in &rows {
                let a = js::max(&[n(&c.get("start")), n(&nn(w.get("start"), V::Num(f64::NEG_INFINITY)))]);
                let b = js::min(&[n(&c.get("end")), n(&nn(w.get("end"), V::Num(f64::INFINITY)))]);
                if !(b > a) { continue; }
                segs.push(Seg { g: g.clone(), c: c.clone(), a, b, coal: kind == "coal" });
                if !order.iter().any(|x| eq(x, &g)) { order.push(g.clone()); }
            }
        }
    }
    if segs.is_empty() { return Vec::new(); }
    let cut_set = Set::new();
    for sg in &segs { cut_set.add(sg.a); cut_set.add(sg.b); }
    let mut cuts: Vec<f64> = cut_set.values().iter().map(n).collect();
    js::sort_by(&mut cuts, |x, y| x - y);
    let mut out: Vec<V> = Vec::new();
    let mut i = 0;
    while i + 1 < cuts.len() {
        let (t0, t1) = (cuts[i], cuts[i + 1]);
        i += 1;
        let on: Vec<&Seg> = segs.iter().filter(|sg| sg.a <= t0 && sg.b >= t1).collect();
        if on.is_empty() { continue; }
        let gs: Vec<V> = order.iter().filter(|g| on.iter().any(|sg| eq(&sg.g, g))).cloned().collect();
        let solo = gs.len() == 1 && on.iter().any(|sg| sg.coal);
        let key = format!("{}{}", join(&gs.iter().map(|g| g.get("uid")).collect::<Vec<_>>(), "|"), if solo { "|solo" } else { "" });
        let end_unknown = on.iter().any(|sg| sg.b == t1 && sg.c.bool("endUnknown") && n(&sg.c.get("end")) == t1 && matches!(sg.c.get("end"), V::Num(_)));
        if let Some(last) = out.last() {
            if is(&last.get("key"), &key) && matches!(last.get("end"), V::Num(e) if e == t0) {
                let lo = last.as_obj().expect("칸");
                lo.set("end", t1);
                lo.set("endUnknown", end_unknown);
                continue;
            }
        }
        let cell = o! {
            "key" => key.as_str(), "groups" => arr(gs.clone()), "n" => gs.len() as f64,
            "name" => join(&gs.iter().map(|g| g.get("name")).collect::<Vec<_>>(), " · "),
            "short" => Str::join(&gs.iter().map(|g| js::to_str(&g.get("name")).first_code_point()).collect::<Vec<_>>(), "·"),
            "start" => t0, "end" => t1, "color" => gs[0].get("color"), "color2" => if gs.len() > 1 { gs[1].get("color") } else { V::Null },
            "colors" => arr(gs.iter().map(|g| g.get("color")).collect()), "uids" => arr(gs.iter().map(|g| g.get("uid")).collect()), "uid" => gs[0].get("uid"),
            "startUnknown" => on.iter().any(|sg| sg.a == t0 && sg.c.bool("startUnknown") && matches!(sg.c.get("start"), V::Num(x) if x == t0)),
            "endUnknown" => end_unknown,
            "note" => join(&on.iter().map(|sg| sg.c.get("note")).filter(tv).collect::<Vec<_>>(), " · "),
        };
        if solo { cell.set("solo", true); }
        if want == "real" { cell.set("real", true); }
        out.push(V::Obj(cell));
    }
    out
}
/// `HT.groupStrip(p)` — `{ power: 집권 칸, real: 실권 칸, nominal: 명목 지도자 칸의 순번(Set) }`.
pub fn group_strip(p: &V) -> Obj {
    if !tv(p) || !(tv(&p.get("groupLinks")) && tv(&p.get("groupLinks").get("length"))) {
        return o! { "power" => arr(Vec::new()), "real" => arr(Vec::new()), "nominal" => Set::new() };
    }
    let power = group_span_cells(p, "power");
    let real = group_span_cells(p, "real");
    let nominal = Set::new();
    if !real.is_empty() {
        for (i, c) in items(&p.get("leaders")).iter().enumerate() {
            let a = n(&c.get("start"));
            let b = n(&nn(c.get("end"), p.get("endY")));
            if !(b > a) { continue; }
            let over = real.iter().fold(0.0, |acc, r| acc + js::max(&[0.0, js::min(&[b, n(&r.get("end"))]) - js::max(&[a, n(&r.get("start"))])]));
            if over * 2.0 >= b - a { nominal.add(i as f64); }
        }
    }
    o! { "power" => arr(power), "real" => arr(real), "nominal" => nominal }
}
/// `HT.lensAny(p)` — 어느 렌즈로든 그릴 칸이 있는가.
pub fn lens_any(p: &V) -> bool {
    tv(p) && ((tv(&p.get("institutionList")) && tv(&p.get("institutionList").get("length")))
        || (tv(&p.get("rankSpans")) && tv(&p.get("rankSpans").get("length")))
        || items(&p.get("groupLinks")).iter().any(|l| is(&l.get("role"), "within") && lens_group_ok(&l.get("group")) && !items(&l.get("group").get("powerSpans")).is_empty()))
}

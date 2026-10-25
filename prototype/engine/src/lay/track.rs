//! 줄 배정 — `js/timeline.js`의 `_layoutTrack(tr)`을 단계 차례 그대로 옮긴다(한 벌 P3 과제 7 · 이음매 ② 뒤).
//!
//! 옮긴 원본: `js/timeline.js` 2822 ~ 3369줄 `_layoutTrack` — SHA-256 앞 12자 `8a3b02f5bf7f`(저장소의 LF 바이트). 둘레는 [`super::rows`] · [`super::scope`].
//! (2026-10-24 맞춤 · `timeline.js` `67c9f897d273`) 3545줄 `tr.rowLift` — 서고 갈래(메이커만)의 줄 올림이라 내보내기에서는 모든 줄 0. 그 밖의 서고 갈래(`opts.seogo`)는 내보내기가 켜지 않아 옮기지 않았다.
//! (2026-10-25 맞춤 · `timeline.js` `30d4c07651b3`) 서고 갈래 직위 줄 더(4단계 배치 갈래 · 감독 결정 G7 가 — 3734줄 서고 `geoFor`의 직위 줄 더 층 `officeTop` · `officeH` · `offices` ·
//! 1818줄 `_bandGeo`의 직위 줄 더 덩이 · `_officeN` · `_officeLines` · `_officeRows`) — 내보내기는 켜지 않아 옮기지 않음(내보내기의 직위 줄 더는 `m/tracks.rs` 늦은 차례의 비트).
//! (2026-10-25 맞춤 · `timeline.js` `b2694a223fec`) 4단계 배치 갈래 둘째 — 1854 ~ 1897줄 순수 도우미 `_leaderLanes`(지도자 칸의 단 나누기)만 더함. 서고 갈래가 아니고 줄 배정과도
//! 무관하다 — 내보내기 `strips.mjs`가 부르는 몫은 [`super::rows::leader_lanes`]에 옮겼다.
//! (2026-10-25 맞춤 · `timeline.js` `406363bb2a24`) 서고 갈래 지도자 두 단 · 줄어드는 층 · 기관 층 줄 값(4단계 배치 갈래 둘째 — 3794줄 서고 `geoFor`의 `leaderTiers` · `unionEnd` · 줄 값 `organH` ·
//! 3853줄 `organRows` · `tr._organHosts` · 3867줄 줄어드는 층 `shrink` · 1807줄 `_bandGeo`의 지도자 덩이 · `up` · `_lanesOf` · `_leaderSlot` · 7559줄 `_cells`의 단 거르개 · 그림(`_drawTrack` · `toSVG`)) —
//! 내보내기는 켜지 않아 옮기지 않음(내보내기의 지도자 두 단 · 줄어드는 층은 `m/strips.rs` 칸 `lane` · `m/tracks.rs` 늦은 차례의 비트).
//! (2026-10-25 맞춤 · `timeline.js` `87107b969d36` · 리메이크 4단계 선반 갈래 걸음 3) 3360 ~ 3377줄 선반 셈(그릇 상태 'shelf' — 서고만이던 것을 내보내기의
//! 선반 변형 `shelf:<uid>`도 셈: shelvedScopes를 채운 배치에서 상위 [`SHELF_KEEP`] 밖 구성원을 `_hidden`으로 · `tr._shelf`) · 9828 ~ 9836줄 `_shelfSplit`([`shelf_split`]).
//! (2026-10-25 맞춤 · `timeline.js` `b1239b1cb1fc` · 리메이크 4단계 선반 갈래 검토 고침) 3558 ~ 3579줄 3) 사건 줄 배정 — 내보내기 선반 변형(packRows)에서 선반이 숨긴 띠
//! (`tr._shelf`의 것과 그 밑에 접힌 소속)의 사건은 줄 null(공통 줄을 만들지 않음 — `m/variants.rs`가 이사 −1로 · `m/events.rs` · `m/rails.rs`는 싣지 않음). 서고는 그대로.
//! 단계(원본의 절 차례): 0) 소속 · 숨김(그릇 claim · 고리 끊기) → 0-1) 바탕 문화 → 1) 민족 나무 · 정렬 · 깊이 · 북에서 남 → 대범위 가지 → 2) 줄 만들기(울타리) →
//! `rowPeriods` · 묶음 · 그릇 가지 → 가는 막대 단 → 2-1) 밑깔림 → 2-2) 기관 · 구역 탭 → 매단 이름표 줄 → 3) 사건 줄 → 3-1) 인물 줄 → 4) 기하 → 5) 줄 위치.
//!
//! 값은 JS 값 그대로(`V` — 트랙 · 띠 · 사건 사본 · 인물 막대에 칸을 적는다: 열쇠 차례 · 나눠 가짐이 이음매 ② 덤프에 그대로 드러남). 민족 나무의 묶음도 JS 객체 꼴(`V::Obj`)로
//! 짓는다(덤프에는 들지 않지만 `_scopeNodes`가 묶음의 정권 목록을 고치는 등 같은 객체를 나눠 쓴다). 줄 목록(`rowList`)의 칸만 Rust 값([`Row`]).
//!
//! 집합 보기의 판 트랙(`tr.board` — 갈래 E · 과제 15가 거절을 걷고 옮김): `contextOf`(이음매 ②)는 판을 세우지 않지만 내보내기의 `boards` 모듈이 판마다
//! [`board_plan`](`_boardPlan`)으로 판 트랙을 세워 이 함수를 부르고 원래 트랙도 판이 선 채(`_boardTr`)로 다시 배치한다 — 판 갈래: 2942줄 판의 깊이 ·
//! 3044줄 [`board_visit`] · 3070줄 [`board_groups`] · 3074줄 [`board_branch`] · 3343줄 묶음 틈의 `gp.from`(첫 견줌은 `upto-boards`).
//! 옮긴 원본(판): `js/timeline.js` 47줄 `BOARD_ID` · 8876 ~ 9008줄 `_boardPlan` · `_boardVisit` · `_boardGroups` · `_boardBranch` — SHA-256 앞 12자 `8a3b02f5bf7f`.
use crate::lay::ctx::Ctx;
use crate::lay::js::{self, Arr, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, dated_alts, eq, is, list, lt, n, nn, ob, or, or_cmp, s, sub, t, take_fault, tv};
use crate::lay::rows::{
    and, band_end, band_start, by_start, chain_rows, dyn_of, extent, fig_span, folded_now, g_of, group_strip, hangs_folded, interval_index, items, lens_any,
    north_of, or0, overlaps, pack_chains, Fence, G, HANG_PITCH,
};
use crate::lay::scope::{scope_branches, scope_claims, scope_nodes, scope_pad};

/// 줄 목록의 칸 하나(`rowList`의 `{ periods, node, folded?, member? }` — 덤프에 들지 않음).
struct Row { periods: Vec<V>, folded: bool, member: bool }

/// 줄 블록(`visit`의 `{ start, ns, run }`).
#[derive(Clone)]
enum Run { Own(Vec<V>), Visit(V) }

/// `_layoutTrack`의 2) 줄 만들기 몫 — `collect` · `emitHosted` · `opened` · `directScope` · `fence` · `rowsOf` · `pushMembers` · `visit`가 나눠 쓰는 것.
struct Walk<'a> {
    tl: &'a V,
    tr: &'a V,
    in_track: &'a Map,
    scope_nodes: &'a [V],
    hosted_after: Map,
    emitted: Set,
    row_list: Vec<Row>,
}

impl Walk<'_> {
    /// `collect(n, out)` — 묶음과 그 아래의 숨지 않은 정권.
    fn collect(&self, node: &V, out: &mut Vec<V>) {
        for p in list(&node.get("periods")) { if !p.bool("_hidden") { out.push(p); } }
        for c in list(&node.get("children")) { self.collect(&c, out); }
    }
    /// `emitHosted(list)` — 상징적 본국이 있는 대범위 가지는 본국 줄(과 그 소속 줄) 바로 아래에.
    fn emit_hosted(&mut self, l: &[V]) {
        for p in l {
            for sn in items(&self.hosted_after.get(&p.get("uid"))) {
                if self.emitted.has(&sn) { continue; }
                self.emitted.add(sn.clone());
                self.visit(&sn, false);
            }
        }
    }
    /// `opened(uid)` — 소속 펼치기 · 단체 펼치기 가운데 하나라도 켠 상위.
    fn opened(&self, uid: &V) -> bool {
        let eg = self.tl.get("expandedGroups");
        self.tl.get("expandedHosts").as_set().is_some_and(|x| x.has(uid)) || (tv(&eg) && eg.as_set().is_some_and(|x| x.has(uid)))
    }
    /// `directScope(p)` — 이 트랙의 직접 그릇 가운데 가장 깊은 것(같으면 먼저 시작한 것) · 없으면 null.
    fn direct_scope(&self, p: &V) -> V {
        let tr_id = self.tr.get("id");
        let mut l: Vec<V> = items(&p.get("scopes")).into_iter().filter(|x| eq(&x.get("track"), &tr_id)).collect();
        js::sort(&mut l, |a, b| or_cmp(n(&or(b.get("depth"), V::Num(0.0))) - n(&or(a.get("depth"), V::Num(0.0))), || sub(&a.get("start"), &b.get("start"))));
        or(l.first().cloned().unwrap_or_default(), V::Null)
    }
    /// `rowsOf(list)` — 내보내기는 줄 채우기 + 울타리(`tl.packRows`), 아니면 사슬마다 한 줄.
    fn rows_of(&self, l: &[V]) -> Vec<Vec<V>> {
        let fence = |q: &V, p: &V| eq(&self.direct_scope(q), &self.direct_scope(p));
        if self.tl.bool("packRows") {
            let f: Fence = &fence;
            pack_chains(&chain_rows(l, Some(f)), Some(f))
        } else {
            chain_rows(l, None)
        }
    }
    /// `pushMembers(host)` — 펼친 상위 아래에 접히는 소속 정권의 줄.
    fn push_members(&mut self, host: &V) {
        if !self.opened(&host.get("uid")) { return; }
        let mut mem: Vec<V> = items(&host.get("members")).into_iter().filter(|m| {
            self.in_track.has(&m.get("uid")) && eq(&m.get("_host"), host) && !m.bool("_hidden") && !(m.bool("_scope") && !eq(&m.get("_host"), host))
        }).collect();
        js::sort(&mut mem, by_start);
        for r in self.rows_of(&mem) {
            self.row_list.push(Row { periods: r.clone(), folded: false, member: tv(host) });
            for p in &r { self.push_members(p); }
            self.emit_hosted(&r);
        }
    }
    /// `visit(node, isRoot)` — 묶음 하나의 줄: 접혔으면 한 줄, 아니면 제 정권의 사슬과 하위 묶음을 시작 해 차례로(북 → 남이면 남북 값 차례로).
    fn visit(&mut self, node: &V, is_root: bool) {
        let nd = ob(node);
        nd.set("first", self.row_list.len() as f64);
        let key = s(&format!("{}|{}", t(&self.tr.get("id")), t(&node.get("id"))));
        let folded = !is_root && self.tl.get("foldedPeoples").as_set().is_some_and(|x| x.has(&key));
        let mut folded_all: Option<Vec<V>> = None;
        if folded {
            let mut all = Vec::new();
            self.collect(node, &mut all);
            js::sort(&mut all, by_start);
            if !all.is_empty() { self.row_list.push(Row { periods: all.clone(), folded: true, member: false }); }
            folded_all = Some(all);
        } else {
            let by_s = |a: &(V, V, Run), b: &(V, V, Run)| sub(&a.0, &b.0);
            let own: Vec<V> = list(&node.get("periods")).into_iter().filter(|p| !p.bool("_member") && !p.bool("_hidden")).collect();
            let mut own_blocks: Vec<(V, V, Run)> = self.rows_of(&own).into_iter().map(|r| (band_start(&r[0]), north_of(&r[0]), Run::Own(r))).collect();
            let mut child_blocks: Vec<(V, V, Run)> = list(&node.get("children")).into_iter().map(|c| (c.get("start0"), nn(c.get("ns0"), V::Null), Run::Visit(c))).collect();
            if is_root { for sn in self.scope_nodes { if !tv(&sn.get("host")) { child_blocks.push((sn.get("start0"), V::Undef, Run::Visit(sn.clone()))); } } }
            let mut blocks = if is_root {
                js::sort_by(&mut child_blocks, by_s);
                js::sort_by(&mut own_blocks, by_s);
                child_blocks.extend(own_blocks);
                child_blocks
            } else {
                child_blocks.extend(own_blocks);
                js::sort_by(&mut child_blocks, by_s);
                child_blocks
            };
            if !is_root && is(&node.get("rule"), "northSouth") {
                // 배열 기준 '북 → 남'(byNorth) — 값이 없는 것은 뒤에 · 같으면 앞의 차례 그대로
                js::sort_by(&mut blocks, |a, b| {
                    let d = f64::from(u8::from(a.1.is_nullish())) - f64::from(u8::from(b.1.is_nullish()));
                    or_cmp(d, || if !a.1.is_nullish() && !b.1.is_nullish() { n(&b.1) - n(&a.1) } else { 0.0 })
                });
            }
            for (_, _, run) in blocks {
                match run {
                    Run::Own(r) => {
                        self.row_list.push(Row { periods: r.clone(), folded: false, member: false });
                        for p in &r { self.push_members(p); }
                        self.emit_hosted(&r);
                    }
                    Run::Visit(c) => self.visit(&c, false),
                }
            }
        }
        nd.set("count", self.row_list.len() as f64 - n(&nd.get("first")));
        if let Some(all) = folded_all { self.emit_hosted(&all); }
    }
}

/// `mkNode(pe, depth)` — 민족 나무의 묶음.
fn mk_node(pe: &V, depth: f64, tr: &V) -> V {
    V::Obj(o! {
        "id" => pe.get("id"), "name" => pe.get("name"), "color" => or(pe.get("color"), tr.get("color")), "order" => nn(pe.get("order"), V::Num(1e9)), "depth" => depth,
        "children" => arr(Vec::new()), "childMap" => Map::new(), "periods" => arr(Vec::new()), "first" => 0.0, "count" => 0.0,
    })
}
/// 묶음의 배열 칸.
fn arr_of(v: &V, k: &str) -> Arr { v.arr(k).unwrap_or_else(|| panic!("묶음의 {k}은(는) 배열")) }
/// `startOf(n)` — 묶음과 그 아래에서 가장 이른 시작.
fn start_of(node: &V) -> f64 {
    let mut xs: Vec<f64> = list(&node.get("periods")).iter().map(|p| n(&band_start(p))).collect();
    xs.extend(list(&node.get("children")).iter().map(start_of));
    js::min(&xs)
}
/// `sortNode(n)`.
fn sort_node(node: &V) {
    arr_of(node, "periods").sort_js(by_start);
    arr_of(node, "children").sort_js(|a, b| or_cmp(sub(&a.get("order"), &b.get("order")), || start_of(a) - start_of(b)));
    for c in list(&node.get("children")) { sort_node(&c); }
}
/// `measure(n)`.
fn measure(node: &V, depth: &mut f64) {
    let d = n(&node.get("depth"));
    if d >= 0.0 { *depth = js::max(&[*depth, d + 1.0]); }
    for c in list(&node.get("children")) { measure(&c, depth); }
}
/// `mark0(n)`.
fn mark0(node: &V) {
    ob(node).set("start0", start_of(node));
    for c in list(&node.get("children")) { mark0(&c); }
}
/// `any(n)` — 배열 기준 '북 → 남'인 묶음이 있는가.
fn any_north_south(node: &V) -> bool { is(&node.get("rule"), "northSouth") || list(&node.get("children")).iter().any(any_north_south) }
/// `mark1(n)` — 묶음 하나의 남북 값(그 안 줄 값 가운데 가장 북쪽).
fn mark1(node: &V) {
    let mut v = V::Null;
    let own: Vec<V> = list(&node.get("periods")).into_iter().filter(|p| !p.bool("_member")).collect();
    for r in chain_rows(&own, None) {
        let x = north_of(&r[0]);
        if !x.is_nullish() && (v.is_nullish() || lt(&v, &x)) { v = x; }
    }
    for c in list(&node.get("children")) {
        mark1(&c);
        let c0 = c.get("ns0");
        if !c0.is_nullish() && (v.is_nullish() || lt(&v, &c0)) { v = c0; }
    }
    ob(node).set("ns0", v);
}

/// `assignLanes(list, key)` — 접힌 트랙 · 접힌 민족 줄의 가는 막대 단(최대 3단 — 다 차면 가장 먼저 끝나는 단에 겹침).
fn assign_lanes(l: &[V], key: &str) {
    let mut sorted = l.to_vec();
    js::sort(&mut sorted, |a, b| or_cmp(sub(&band_start(a), &band_start(b)), || sub(&band_end(b), &band_end(a))));
    let mut ends: Vec<f64> = Vec::new();
    for p in &sorted {
        let bs = n(&band_start(p));
        let mut lane: f64 = ends.iter().position(|e| *e <= bs).map_or(-1.0, |i| i as f64);
        if lane < 0.0 {
            lane = if ends.len() >= 3 {
                let m = js::min(&ends);
                ends.iter().position(|e| *e == m).map_or(-1.0, |i| i as f64)
            } else { ends.push(f64::NEG_INFINITY); (ends.len() - 1) as f64 };
        }
        let be = n(&band_end(p));
        // 가장 이른 끝이 NaN이면 `ends.indexOf(NaN)`이 −1 — JS는 배열 칸이 아닌 속성 `ends[-1]`에 적고 다시 읽지 않으므로(단 고르기는 칸만 봄) 적지 않는다
        if lane >= 0.0 { let k = lane as usize; ends[k] = js::max(&[ends[k], be]); }
        ob(p).set(key, lane);
    }
}

/// `G_SEOGO.shelfKeep` — 선반이 제 줄에 남기는 구성원 수(서고 과제 9 · 리메이크 4단계 선반 변형).
pub const SHELF_KEEP: usize = 5;

/// `tl._shelfSplit(list)` — 그릇 하나가 차지한 구성원 목록을 중요도(수가 아니면 −1) → 기간 길이(바깥 끝 `bandEnd − bandStart`) → 시작 차례로 세워
/// (keep 상위 [`SHELF_KEEP`] · rest 나머지)로 가른다. 넘지 않으면 (목록 그대로, 빈 목록). 안정 정렬(JS `sort` — [`js::sort`])이라 값이 같으면 목록의 차례.
/// 줄 배정의 선반 셈과 내보내기 `variants`의 선반 변형 후보 고르기가 함께 쓴다.
pub fn shelf_split(l: &[V]) -> (Vec<V>, Vec<V>) {
    if l.len() <= SHELF_KEEP { return (l.to_vec(), Vec::new()); }
    let rank = |p: &V| -> (f64, f64) { (match p.get("importance") { V::Num(x) => x, _ => -1.0 }, sub(&band_end(p), &band_start(p))) };
    let mut sorted = l.to_vec();
    js::sort(&mut sorted, |a, b| {
        let (x, y) = (rank(a), rank(b));
        or_cmp(y.0 - x.0, || or_cmp(y.1 - x.1, || sub(&band_start(a), &band_start(b))))
    });
    let rest = sorted.split_off(SHELF_KEEP);
    (sorted, rest)
}

/// `contextOf`의 `for (const tr of tl.tracks) tl._layoutTrack(tr)` — 트랙마다 줄 배정. 같은 문맥에서 다시 불러도 같은 답이다(변형 REPLAY · 렌즈 · 판이 다시 배치함 — 검사
/// `lay_rows::relayout_is_idempotent`). JS라면 던졌을 곳(객체가 아닌 값에 칸 쓰기 — `model::util::fault`)이 남으면 오류. 점 사건의 날짜 글을 다시 읽어 보조 달력 표가
/// 모자라면 거절 — 정규화가 같은 날짜 글을 먼저 읽어 거기서 거절하므로 사실상 지키는 줄.
pub fn layout_all(ctx: &mut Ctx) -> crate::Result<()> {
    let tracks = list(&ctx.tl.get("tracks"));
    layout_some(ctx, &tracks)
}

/// [`layout_all`]을 트랙 몇에만 — 같은 잘못 · 보조 달력 표 거절을 본다. 트랙 하나의 줄 배정은 그 트랙의 정권과 연표 상태(펼친 상위 · 켠 그릇 · 판 · 렌즈)만
/// 읽고 남의 트랙에 쓰지 않으므로(`_layoutTrack` — `in_track`) 상태를 바꿔 다시 배치할 때 그 상태가 닿는 트랙만 돌려도 [`layout_all`]과 같다(과제 16b —
/// 변형 하나는 제 트랙만: 펼친 상위 · 단체 · 그릇이 모두 그 트랙의 것).
pub fn layout_some(ctx: &mut Ctx, tracks: &[V]) -> crate::Result<()> {
    for tr in tracks { layout_track(ctx, tr)?; }
    if let Some(msg) = take_fault() { return Err(format!("줄 배정을 하지 못했습니다 — {msg}(JS라면 TypeError)").into()); }
    if let Some(name) = ctx.read.cal.missed_of() { return Err(format!("줄 배정: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다").into()); }
    if let Some(name) = ctx.read.cal.absent_of() { return Err(format!("줄 배정: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다").into()); }
    Ok(())
}

/// `tl._layoutTrack(tr)` — 트랙 하나의 줄 배정(위 머리말의 단계 차례 · 판 트랙이면 판 갈래).
pub fn layout_track(ctx: &mut Ctx, tr: &V) -> crate::Result<()> {
    let board = tv(&tr.get("board"));
    // 판 트랙의 줄 목록(`tr.board.rows` — _boardPlan이 늘 지음)이 배열이 아니면 JS는 `.some` · `for … of`에서 TypeError — 조용히 빈 판으로 잇지 않는다
    if board && !matches!(tr.get("board").get("rows"), V::Arr(_)) { return Err("집합 보기의 줄 배정: tr.board.rows가 배열이 아닙니다(JS라면 TypeError)".into()); }
    let tl = ctx.tl.clone();
    let g: G = g_of(&tl);
    let tro = ob(tr);
    tro.set("folded", folded_now(&tl, &tr.get("id")));
    let periods = list(&tr.get("periods"));
    let in_track = Map::new();
    for p in &periods { in_track.set(p.get("uid"), p.clone()); }

    // 0) 소속(연맹 구성국 · 종속국 · 조직체): 상위 정권이 펼쳐져 있을 때만 보인다
    for p in &periods {
        let po = ob(p);
        let ov = if is(&p.get("polityKind"), "overlay") {
            and(p.get("hosts"), || V::Bool(list(&p.get("hosts")).iter().any(|h| in_track.has(&h.get("host").get("uid")))))
        } else { V::Bool(false) };
        po.set("_overlay", ov.clone());
        let host = if !tv(&ov) && p.bool("singleHost") && p.bool("partOfUid") { or(in_track.get(&p.get("partOfUid")), V::Null) } else { V::Null };
        po.set("_host", host.clone());
        po.set("_member", tv(&host));
        po.set("_row", V::Null);
        po.set("_folded", false);
        po.set("_seamR", V::Null); // `p._seamL = p._seamR = null` — 안쪽 대입(_seamR)이 먼저 열쇠를 만든다
        po.set("_seamL", V::Null);
    }
    // 대범위(7-2): 켠 대범위의 구성 정권은 다른 정권 띠 아래에 접혀 있던 자리를 떠나 대범위 가지로
    let scope_of = scope_claims(&tl, tr, &in_track);
    for p in &periods {
        let po = ob(p);
        let sc = or(scope_of.get(&p.get("uid")), V::Null);
        po.set("_scope", sc.clone());
        let h = p.get("_host");
        if tv(&sc) && tv(&h) && !eq(&scope_of.get(&h.get("uid")), &sc) {
            po.set("_host", V::Null);
            po.set("_member", false);
        }
    }
    // 소속이 돌고 도는 자료: _host를 따라가다 제 길로 돌아오면 고리의 마지막 고리를 끊는다
    {
        let done = Set::new();
        for p in &periods {
            let mut path: Vec<V> = Vec::new();
            let mut q = p.clone();
            while tv(&q) && !done.has(&q) && !path.iter().any(|x| eq(x, &q)) {
                path.push(q.clone());
                q = q.get("_host");
            }
            if tv(&q) && path.iter().any(|x| eq(x, &q)) {
                let last = ob(path.last().expect("길"));
                last.set("_host", V::Null);
                last.set("_member", false);
            }
            for x in path { done.add(x); }
        }
    }
    let hidden_memo = Map::new();
    fn is_hidden(tl: &V, memo: &Map, p: &V) -> bool {
        let host = p.get("_host");
        if !tv(&host) { return false; }
        if memo.has(&p.get("uid")) { return tv(&memo.get(&p.get("uid"))); }
        memo.set(p.get("uid"), true); // 순환 방지
        let open = if p.bool("groupUid") {
            let eg = tl.get("expandedGroups");
            tv(&eg) && eg.as_set().is_some_and(|x| x.has(&host.get("uid")))
        } else { tl.get("expandedHosts").as_set().is_some_and(|x| x.has(&host.get("uid"))) };
        let h = !open || is_hidden(tl, memo, &host);
        memo.set(p.get("uid"), h);
        h
    }
    for p in &periods { ob(p).set("_hidden", is_hidden(&tl, &hidden_memo, p)); }

    // 0-1) 바탕 문화: 승계국(국가)이 있는 문화는 제 줄을 갖지 않고 승계국 줄 밑에 깔린다
    for p in &periods {
        let po = ob(p);
        po.set("_under", false);
        po.set("_underRows", arr(Vec::new()));
    }
    let succ_in = |p: &V| -> Vec<V> {
        items(&p.get("successors")).iter().map(|e| in_track.get(&e.get("to").get("uid"))).filter(|x| tv(x) && !x.bool("_hidden")).collect()
    };
    let mut changed = true;
    while changed {
        changed = false;
        for p in &periods {
            if p.bool("_under") || !is(&p.get("polityKind"), "culture") || p.bool("_hidden") { continue; }
            if succ_in(p).iter().any(|x| !is(&x.get("polityKind"), "culture") || x.bool("_under")) {
                ob(p).set("_under", true);
                changed = true;
            }
        }
    }

    // 1) 민족 트리(대명제 → … → 민족). 정권은 어느 단계에든 붙을 수 있다
    let root = mk_node(&V::Obj(o! { "id" => "", "name" => "" }), -1.0, tr);
    let node_of = Map::new();
    for p in &periods {
        if p.bool("_under") || p.bool("_overlay") { continue; }
        let mut node = root.clone();
        for pe in items(&p.get("peoplePath")) {
            let cm = node.get("childMap");
            let cm = cm.as_map().expect("childMap");
            let mut child = cm.get(&pe.get("id"));
            if !tv(&child) {
                child = mk_node(&pe, n(&node.get("depth")) + 1.0, tr);
                ob(&child).set("rule", or(or(pe.get("rowOrder"), node.get("rule")), s("")));
                cm.set(pe.get("id"), child.clone());
                arr_of(&node, "children").push(child.clone());
            }
            node = child;
        }
        arr_of(&node, "periods").push(p.clone());
        node_of.set(p.clone(), node);
    }
    // 민족 없는 문화(고고학 문화)는 트랙 맨 위 "문화" 묶음으로
    let root_periods = list(&root.get("periods"));
    let cultures: Vec<V> = root_periods.iter().filter(|p| is(&p.get("polityKind"), "culture")).cloned().collect();
    if !cultures.is_empty() {
        let ro = ob(&root);
        ro.set("periods", arr(root_periods.iter().filter(|p| !is(&p.get("polityKind"), "culture")).cloned().collect()));
        let cn = mk_node(&V::Obj(o! { "id" => "__culture", "name" => "문화", "color" => tr.get("color"), "order" => -1.0 }), 0.0, tr);
        ob(&cn).set("culture", true);
        ob(&cn).set("periods", arr(cultures));
        root.get("childMap").as_map().expect("childMap").set(cn.get("id"), cn.clone());
        arr_of(&root, "children").borrow_mut().insert(0, cn);
    }
    sort_node(&root);
    let mut depth = 1.0;
    tro.set("depth", depth);
    measure(&root, &mut depth);
    tro.set("depth", depth);
    // 집합 보기: 왼쪽 칸은 원래 트랙 칩(첫 단) · 제 민족 칩(둘째 단)뿐(_boardGroups)
    if board { tro.set("depth", if items(&tr.get("board").get("rows")).iter().any(|r| tv(&r.get("people"))) { 2.0 } else { 1.0 }); }
    // 대범위 가지(7-2): 전원으로 지은 나무에서 묶음마다 시작 해(start0)를 먼저 정해 둔다
    mark0(&root);
    // 배열 기준 '북 → 남': 그 민족 묶음 안은 남북 값이 큰 줄 · 묶음이 위
    if any_north_south(&root) {
        let seams: Vec<(V, V, V)> = periods.iter().map(|p| (p.clone(), p.get("_seamL"), p.get("_seamR"))).collect(); // 값을 재려고 지은 줄이 이음매를 남기지 않게
        mark1(&root);
        for (p, l, r) in seams {
            let po = ob(&p);
            po.set("_seamL", l);
            po.set("_seamR", r);
        }
    }
    // 선반(서고 과제 9 · 리메이크 4단계 엔진 변형): 켠 그릇의 구성원 가운데 상위 SHELF_KEEP만 제 줄에 두고 나머지는 숨긴다(`_hidden`) — 내보내기는
    // shelvedScopes를 채운 배치(선반 변형 `shelf:<uid>`)에서만. 서고(`seogo`)는 내보내기가 켜지 않지만 문은 JS 그대로 둔다
    let seogo = tl.bool("seogo");
    let shelved = tl.get("shelvedScopes");
    let shelf_on = (seogo || tl.bool("packRows")) && shelved.as_set().is_some_and(|x| !x.is_empty());
    if seogo || shelf_on { tro.set("_shelf", Map::new()); } // 서고 · 선반 배치만 — 내보내기 기본 배치의 트랙에는 새 칸을 만들지 않음(정답지 rows가 그대로)
    else if tl.bool("packRows") { tro.delete("_shelf"); } // 앞 선반 변형이 남긴 칸을 걷음(기본으로 되돌린 뒤 boards가 다시 배치할 때 낡은 선반을 읽지 않게)
    if shelf_on {
        let shelved = shelved.as_set().expect("선반 집합");
        let by_sc = Map::new();
        for p in &periods {
            let sc = scope_of.get(&p.get("uid"));
            if tv(&sc) && shelved.has(&sc.get("uid")) && !p.bool("_hidden") && !p.bool("_under") && !p.bool("_overlay") {
                let mut cur = list(&by_sc.get(&sc));
                cur.push(p.clone());
                by_sc.set(sc, arr(cur));
            }
        }
        for (sc, l) in by_sc.entries() {
            let (_, rest) = shelf_split(&list(&l));
            if rest.is_empty() { continue; }
            for p in &rest { ob(p).set("_hidden", true); }
            tr.get("_shelf").as_map().expect("선반 칸").set(sc.get("uid"), arr(rest));
        }
    }
    let scope_node_list = scope_nodes(tr, &scope_of, &node_of, &in_track, by_start);
    let hosted_after = Map::new(); // 본국 uid → 그 줄 바로 아래에 모일 가지들
    for sn in &scope_node_list {
        let host = sn.get("host");
        if tv(&host) {
            let mut cur = items(&hosted_after.get(&host.get("uid")));
            cur.push(sn.clone());
            hosted_after.set(host.get("uid"), arr(cur));
        }
    }

    // 2) 줄 만들기(chainRows). 승계로 이어지는 정권만 같은 줄을 쓴다
    let mut w = Walk { tl: &tl, tr, in_track: &in_track, scope_nodes: &scope_node_list, hosted_after, emitted: Set::new(), row_list: Vec::new() };
    if board { board_visit(&mut w, tr)?; } // 집합 보기: 민족 나무가 아니라 구성 나라의 차례대로 옮겨 온 줄 그대로(줄 통째 — _boardPlan)
    else {
        w.visit(&root, true);
        for sn in &scope_node_list { if tv(&sn.get("host")) && !w.emitted.has(sn) { w.visit(sn, false); } } // 본국 줄을 찾지 못한 가지는 맨 아래에
    }
    let row_list = std::mem::take(&mut w.row_list);
    drop(w);

    let row_periods = Arr::default();
    let folded_rows = Set::new();
    let member_rows = Set::new();
    tro.set("rowPeriods", row_periods.clone());
    tro.set("foldedRows", folded_rows.clone());
    tro.set("memberRows", member_rows.clone());
    for (i, r) in row_list.iter().enumerate() {
        row_periods.push(arr(r.periods.clone()));
        for p in &r.periods {
            let po = ob(p);
            po.set("_row", i as f64);
            po.set("_folded", r.folded);
        }
        if r.folded { folded_rows.add(i as f64); }
        if r.member { member_rows.add(i as f64); }
    }
    let groups = Arr::default();
    tro.set("groups", groups.clone());
    let folded_peoples = tl.get("foldedPeoples");
    fn groups_of(node: &V, tr: &V, fp: &V, groups: &Arr) {
        for c in list(&node.get("children")) {
            let key = s(&format!("{}|{}", t(&tr.get("id")), t(&c.get("id"))));
            let folded = fp.as_set().is_some_and(|x| x.has(&key));
            if tv(&c.get("count")) {
                groups.push(o! {
                    "key" => c.get("id"), "name" => c.get("name"), "color" => c.get("color"), "depth" => c.get("depth"), "first" => c.get("first"), "count" => c.get("count"),
                    "folded" => folded, "culture" => c.bool("culture"),
                });
            }
            if !folded { groups_of(&c, tr, fp, groups); }
        }
    }
    if board { for gp in board_groups(tr) { groups.push(gp); } } // 집합 보기: 원래 트랙 칩 · 제 민족 칩(접지 않음)
    else { groups_of(&root, tr, &folded_peoples, &groups); }
    // 대범위 가지도 민족 묶음처럼 왼쪽 칸 하나
    for sn in &scope_node_list {
        if tv(&sn.get("count")) {
            let key = s(&format!("{}|{}", t(&tr.get("id")), t(&sn.get("id"))));
            groups.push(o! {
                "key" => sn.get("id"), "name" => sn.get("name"), "color" => sn.get("color"), "depth" => 0.0, "first" => sn.get("first"), "count" => sn.get("count"),
                "folded" => folded_peoples.as_set().is_some_and(|x| x.has(&key)), "culture" => false, "scope" => sn.get("scope").get("uid"),
            });
        }
    }
    // 집합 보기: 판 전체를 두르는 테두리 하나(대범위 테두리와 같은 말씨 · 가로 전체)
    let branches = if board { board_branch(&tro, tr)? } else { scope_branches(&tro, &scope_node_list) };
    tro.set("scopeBranches", branches);
    // 접힌 트랙 · 접힌 민족 줄의 가는 막대 단: 자료 전체로 미리 정해 둔다
    assign_lanes(&periods.iter().filter(|p| !p.bool("_hidden") && !p.bool("_overlay") && !p.bool("_under")).cloned().collect::<Vec<_>>(), "_laneAll");
    for r in folded_rows.values() { assign_lanes(&items(&V::Arr(row_periods.clone()).get(&n(&r))), "_laneRow"); }

    // 2-1) 바탕 문화의 줄: 승계국(들)의 줄. 승계국이 또 바탕 문화면 그 문화의 줄을 따른다
    let underlays = Arr::default();
    tro.set("underlays", underlays.clone());
    let under_memo = Map::new();
    fn under_rows(p: &V, depth: u32, memo: &Map, succ_in: &dyn Fn(&V) -> Vec<V>, folded_rows: &Set) -> V {
        if memo.has(&p.get("uid")) { return memo.get(&p.get("uid")); }
        memo.set(p.get("uid"), arr(Vec::new())); // 순환 방지
        let mut rows: Vec<V> = Vec::new();
        let has = |rows: &[V], r: &V| rows.iter().any(|x| matches!((x, r), (V::Num(a), V::Num(b)) if a == b));
        if depth < 20 {
            for sx in succ_in(p) {
                if sx.bool("_under") {
                    for r in list(&under_rows(&sx, depth + 1, memo, succ_in, folded_rows)) { if !has(&rows, &r) { rows.push(r); } }
                    continue;
                }
                let mut host = sx.clone();
                while tv(&host) && host.bool("_hidden") { host = host.get("_host"); }
                if tv(&host) && !host.get("_row").is_nullish() && !folded_rows.has(&host.get("_row")) && !has(&rows, &host.get("_row")) { rows.push(host.get("_row")); }
            }
        }
        js::sort(&mut rows, |a, b| sub(a, b));
        let out = arr(rows);
        memo.set(p.get("uid"), out.clone());
        out
    }
    for p in &periods {
        if !p.bool("_under") { continue; }
        let rows = under_rows(p, 0, &under_memo, &succ_in, &folded_rows);
        let po = ob(p);
        po.set("_underRows", rows.clone());
        let has_rows = tv(&rows.get("length"));
        po.set("_row", if has_rows { rows.get(&0.0) } else { V::Null }); // 승계국이 모두 접혀 있으면 그리지 않음
        if has_rows { underlays.push(p.clone()); }
    }
    let under_row_set = Set::new();
    for p in underlays.to_vec() { for r in list(&p.get("_underRows")) { under_row_set.add(r); } }
    tro.set("underRowSet", under_row_set.clone());

    // 2-2) 기관: 얹히는 시대 띠의 줄. 구역(zone)은 시대 띠 아래로 내려오는 탭(연도가 겹치면 단을 나눔 — 최대 3단)
    let overlays = Arr::default();
    tro.set("overlays", overlays.clone());
    let mut zone_lanes: Vec<(f64, Vec<Vec<(f64, f64)>>)> = Vec::new(); // 줄 → 단별 [[시작, 끝], …](넣은 차례)
    for p in &periods {
        if !p.bool("_overlay") { continue; }
        let po = ob(p);
        let mut rows: Vec<V> = Vec::new();
        let zl = Obj::new();
        po.set("_zoneLane", zl.clone());
        for h in list(&p.get("hosts")) {
            let mut host = in_track.get(&h.get("host").get("uid"));
            while tv(&host) && host.bool("_hidden") { host = host.get("_host"); }
            if !tv(&host) || host.get("_row").is_nullish() || folded_rows.has(&host.get("_row")) { continue; }
            let hr = host.get("_row");
            if !rows.iter().any(|x| js::strict_eq(x, &hr)) { rows.push(hr.clone()); }
            if !is(&p.get("scale"), "zone") { continue; }
            let st = js::max(&[n(&band_start(p)), n(&nn(h.get("start"), V::Num(f64::NEG_INFINITY))), n(&band_start(&host))]);
            let en = js::min(&[n(&band_end(p)), n(&nn(h.get("end"), V::Num(f64::INFINITY))), n(&band_end(&host))]);
            if en <= st { continue; }
            let row = n(&hr);
            let at = zone_lanes.iter().position(|(r, _)| *r == row);
            let mut lanes = at.map_or_else(Vec::new, |k| zone_lanes[k].1.clone());
            let mut lane: isize = lanes.iter().position(|l| !overlaps(l, st, en)).map_or(-1, |i| i as isize);
            if lane < 0 && (lanes.len() as f64) < g.zone_lanes { lanes.push(Vec::new()); lane = lanes.len() as isize - 1; }
            if lane < 0 { lane = lanes.len() as isize - 1; }
            lanes[lane as usize].push((st, en));
            match at { Some(k) => zone_lanes[k].1 = lanes, None => zone_lanes.push((row, lanes)) }
            zl.set(&t(&h.get("host").get("uid")), lane as f64);
        }
        let has_rows = !rows.is_empty();
        po.set("_row", if has_rows { rows[0].clone() } else { V::Null });
        if has_rows { overlays.push(p.clone()); }
    }
    let zone_row_lanes = Map::new();
    for (r, lanes) in &zone_lanes { zone_row_lanes.set(*r, lanes.len() as f64); }
    tro.set("zoneRowLanes", zone_row_lanes.clone());
    // 속국 이름표(depProxies): 이 트랙의 상국 띠마다 — 매달린 탭의 줄 수(rowCut) · 품은 칸의 줄 수(depRows)
    let hang_row_lanes = Map::new();
    tro.set("hangRowLanes", hang_row_lanes.clone());
    let proxies = tl.get("_proxies");
    for p in &periods {
        let po = ob(p);
        let dep = or(and(proxies.clone(), || proxies.as_map().map_or(V::Undef, |m| m.get(&p.get("uid")))), V::Null);
        po.set("_dep", dep.clone());
        if !tv(&dep) || p.bool("_hidden") || p.bool("_overlay") || p.bool("_under") || p.get("_row").is_nullish() || folded_rows.has(&p.get("_row")) || hangs_folded(&tl, &p.get("uid")) { continue; }
        if tv(&dep.get("outLanes")) {
            let cur = n(&or(hang_row_lanes.get(&p.get("_row")), V::Num(0.0)));
            hang_row_lanes.set(p.get("_row"), js::max(&[cur, n(&dep.get("outLanes"))]));
        }
    }

    // 3) 사건 줄 배정(접힌 민족 · 숨은 소속 정권의 사건은 보이는 상위 줄로). 내보내기 선반 변형(packRows — 위 선반 셈)에서는 선반이 숨긴 띠(와 그 밑에
    // 접힌 소속)의 사건도 숨김: 줄 null · 공통 줄을 만들지 않음(export/variants가 이사 −1로 — 엔진 계약 2-4절 '숨는 띠'). 서고는 예전처럼 공통 줄로
    let shelf_gone = if shelf_on && tl.bool("packRows") {
        let s = Set::new();
        for l in tr.get("_shelf").as_map().expect("선반 칸").values() { for p in list(&l) { s.add(p); } }
        Some(s)
    } else { None };
    let row_for = |uid: &V| -> V {
        let mut p = in_track.get(uid);
        while tv(&p) && p.bool("_hidden") {
            if shelf_gone.as_ref().is_some_and(|s| s.has(&p)) { return V::Bool(false); }
            p = p.get("_host");
        }
        if tv(&p) { p.get("_row") } else { V::Undef }
    };
    let events_arr = tr.arr("events").expect("트랙의 사건");
    let mut has_common = false;
    for e in events_arr.to_vec() {
        let place = e.get("_place");
        let pol = if tv(&place) { place.get("polityUid") } else { e.get("polityUid") };
        let row = if !pol.is_nullish() { row_for(&pol) } else { V::Undef };
        if matches!(row, V::Bool(false)) { ob(&e).set("_row", V::Null); }
        else if row.is_nullish() { ob(&e).set("_row", -1.0); has_common = true; } else { ob(&e).set("_row", row); }
    }
    let period_rows = row_periods.len() as f64;
    let rows_n = period_rows + if has_common { 1.0 } else { 0.0 };
    tro.set("rows", rows_n);
    let common_row = if has_common { period_rows } else { -1.0 };
    tro.set("commonRow", common_row);
    for e in events_arr.to_vec() { if matches!(e.get("_row"), V::Num(x) if x == -1.0) { ob(&e).set("_row", common_row); } }
    events_arr.sort_js(|a, b| sub(&a.get("start"), &b.get("start")));
    let events_by_row: Vec<Arr> = (0..rows_n as usize).map(|_| Arr::default()).collect();
    tro.set("eventsByRow", arr(events_by_row.iter().cloned().map(V::Arr).collect()));
    for e in events_arr.to_vec() {
        let r = e.get("_row");
        let slot = match &r { V::Num(x) if *x >= 0.0 && x.fract() == 0.0 && (*x as usize) < events_by_row.len() => Some(&events_by_row[*x as usize]), _ => None };
        if let Some(l) = slot { if !folded_rows.has(&r) { l.push(e.clone()); } }
    }
    let index_by_row: Vec<V> = events_by_row.iter().map(|l| interval_index(&l.to_vec(), |e| extent(ctx, e))).collect();
    tro.set("eventIndexByRow", arr(index_by_row));
    tro.set("eventParents", arr(events_arr.to_vec().into_iter().filter(|e| tv(&e.get("children")) && tv(&e.get("children").get("length"))).collect()));
    let by_uid = Map::new();
    for e in events_arr.to_vec() { by_uid.set(e.get("uid"), e.clone()); }
    tro.set("eventByUid", by_uid);

    // 3-1) 인물의 줄: 섬긴 정권의 줄(숨은 소속 정권의 인물은 보이는 상위 줄로 — band = 그 줄에서 그려지는 띠)
    let figures = items(&tr.get("figures"));
    for x in &figures {
        let mut p = in_track.get(&x.get("s").get("polity").get("uid"));
        while tv(&p) && p.bool("_hidden") { p = p.get("_host"); }
        let ok = tv(&p) && !p.bool("_overlay") && !p.bool("_under") && !p.get("_row").is_nullish() && !folded_rows.has(&p.get("_row"));
        let xo = ob(x);
        xo.set("band", if ok { p.clone() } else { V::Null });
        xo.set("row", if ok { p.get("_row") } else { V::Null });
        xo.set("lvl", -1.0);
    }

    // 4) 줄 구조: [지도자][내각][사건 줄 ×n][기간 레일][인물 단][예속 띠][기관]
    let density = n(&tl.get("density"));
    let show = tl.get("show");
    let bird = tl.get("_bird");
    let lines = if density < 0.0 { 2.0 } else if density > 0.0 { 1.0 } else if rows_n <= 6.0 { 2.0 } else { 1.0 };
    // 인물 단의 단 배정 — 줄 단위로, 활동 막대의 해로만, 중요도 높은 순 → 시작 순으로 위 단부터
    let fig_max = if tv(&bird) || matches!(show.get("figures"), V::Bool(false)) { 0.0 } else if density < 0.0 { 3.0 } else if density > 0.0 || lines == 1.0 { 1.0 } else { 2.0 };
    let mut fig_rows: Vec<f64> = vec![0.0; row_periods.len()];
    if fig_max != 0.0 {
        let mut by_row: Vec<(V, Vec<V>)> = Vec::new(); // Map(줄 → 막대 — 넣은 차례)
        for x in &figures {
            let r = x.get("row");
            if r.is_nullish() { continue; }
            match by_row.iter().position(|(k, _)| js::strict_eq(k, &r)) { Some(k) => by_row[k].1.push(x.clone()), None => by_row.push((r, vec![x.clone()])) }
        }
        for (r, mut l) in by_row {
            let mut levels: Vec<Vec<(f64, f64)>> = vec![Vec::new(); fig_max as usize];
            let lvl_of = Map::new(); // 인물 → 이 줄에서 먼저 잡은 단
            js::sort(&mut l, |a, b| {
                or_cmp(n(&or(b.get("f").get("importance"), V::Num(2.0))) - n(&or(a.get("f").get("importance"), V::Num(2.0))), || {
                    or_cmp(sub(&a.get("s").get("start"), &b.get("s").get("start")), || sub(&a.get("s").get("endY"), &b.get("s").get("endY")))
                })
            });
            for x in &l {
                let (lo, hi) = fig_span(&x.get("s"));
                let free = |levels: &Vec<Vec<(f64, f64)>>, k: usize| !levels[k].iter().any(|&(a, b)| a < hi && lo < b);
                let want = lvl_of.get(&x.get("f").get("uid"));
                let lv: isize = if !want.is_nullish() && free(&levels, n(&want) as usize) { n(&want) as isize } else { (0..levels.len()).position(|k| free(&levels, k)).map_or(-1, |k| k as isize) };
                if lv < 0 { continue; }
                levels[lv as usize].push((lo, hi));
                lvl_of.set(x.get("f").get("uid"), lv as f64);
                ob(x).set("lvl", lv as f64);
                let ri = n(&r) as usize;
                fig_rows[ri] = js::max(&[fig_rows[ri], lv as f64 + 1.0]);
            }
        }
    }
    // 왕조 칸: 다스린 왕조가 적힌 정권이 있는 트랙만
    let dynasty = if !matches!(show.get("dynasties"), V::Bool(false)) && periods.iter().any(|p| !dyn_of(&tl, p).is_empty()) { g.dynasty } else { 0.0 };
    // 렌즈를 켠 동안: 지도자 칸이 없는 트랙도 어느 렌즈로든 그릴 자료가 있으면 그 자리를 둔다
    let has_list = |p: &V, k: &str| tv(&p.get(k)) && tv(&p.get(k).get("length"));
    let leader = if (show.bool("leaders") && periods.iter().any(|p| has_list(p, "leaders"))) || (tl.bool("themeLens") && periods.iter().any(lens_any)) { g.leader } else { 0.0 };
    let cabinet = if show.bool("cabinets") && periods.iter().any(|p| has_list(p, "cabinets")) { g.cabinet } else { 0.0 };
    // 기관 칸: 통감부 같은 기관이 있는 트랙만
    let organ = if overlays.to_vec().iter().any(|p| !is(&p.get("scale"), "zone")) { g.organ } else { 0.0 };
    // 예속 칸: 상국 띠 안 맨 아래에 상국이 다스린 속국의 이름표 — 줄 단위(depRows)
    let dep_lanes = |p: &V| -> V {
        if tv(&p.get("_dep")) && !p.bool("_overlay") && !p.bool("_hidden") && !p.bool("_under") { p.get("_dep").get("inLanes") } else { V::Num(0.0) }
    };
    let dep = if periods.iter().any(|p| tv(&dep_lanes(p))) { g.dep } else { 0.0 };
    let rp_lists: Vec<Vec<V>> = row_periods.to_vec().iter().map(list).collect();
    let max0 = |xs: Vec<f64>| -> f64 { let mut v = vec![0.0]; v.extend(xs); js::max(&v) };
    let dep_rows: Vec<f64> = rp_lists.iter().enumerate().map(|(r, l)| {
        let k = if folded_rows.has(&V::Num(r as f64)) { 0.0 } else { max0(l.iter().map(|p| n(&dep_lanes(p))).collect()) };
        if k != 0.0 && !k.is_nan() { k * (g.dep + g.slot_gap) - g.slot_gap } else { 0.0 }
    }).collect();
    // 기간 막대 단 수: 한 줄에서 시기가 겹치는 기간 사건 수만큼(2 ~ 3단)
    let mut rail_levels = 2.0;
    for l in &events_by_row {
        let mut segs: Vec<(f64, f64)> = l.to_vec().iter().filter(|e| {
            !e.bool("parentUid") && (n(&e.get("endY")) - n(&e.get("start")) > 0.0 || e.bool("startRange") || e.bool("endRange") || !dated_alts(e).is_empty())
        }).map(|e| {
            let mut ys: Vec<f64> = vec![n(&e.get("start")), n(&e.get("endY"))];
            if e.bool("startRange") { ys.extend(list(&e.get("startRange")).iter().map(n)); }
            if e.bool("endRange") { ys.extend(list(&e.get("endRange")).iter().map(n)); }
            for a in dated_alts(e) { ys.push(n(&a.get("start"))); ys.push(n(&nn(a.get("end"), a.get("start")))); }
            (js::min(&ys), js::max(&ys))
        }).collect();
        js::sort_by(&mut segs, |a, b| a.0 - b.0);
        let mut ends: Vec<f64> = Vec::new();
        for (st, en) in segs {
            match ends.iter().position(|end| *end < st) { None => ends.push(en), Some(i) => ends[i] = en }
        }
        rail_levels = js::max(&[rail_levels, js::min(&[3.0, ends.len() as f64])]);
    }
    let rail_h = rail_levels * g.rail_pitch;
    // 세로 자리: [여백][왕조][틈][지도자][틈][내각][틈][사건 글줄 ×n][기간 막대 2 ~ 3단][예속 띠][틈][기관][여백]
    let dynasty_top = g.inset;
    let leader_top = dynasty_top + if dynasty != 0.0 { dynasty + g.slot_gap } else { 0.0 };
    let cabinet_top = leader_top + if leader != 0.0 { leader + g.slot_gap } else { 0.0 };
    let text_top = cabinet_top + if cabinet != 0.0 { cabinet + g.slot_gap } else { 0.0 };
    let rail_top = text_top + lines * g.line;
    let dep_top = rail_top + rail_h + g.slot_gap;
    let organ_top = dep_top + if dep != 0.0 { dep + g.slot_gap } else { 0.0 };
    let geo = o! {
        "lines" => lines, "font" => if lines > 1.0 { 12.0 } else { 11.5 }, "name" => if lines > 1.0 { 13.5 } else { 12.5 },
        "dynastyTop" => dynasty_top, "dynastyH" => dynasty, "leaderTop" => leader_top, "leaderH" => leader, "cabinetTop" => cabinet_top, "cabinetH" => cabinet,
        "organTop" => organ_top, "organH" => organ, "textTop" => text_top, "lineH" => g.line, "railTop" => rail_top, "railH" => rail_h, "railLevels" => rail_levels,
        "depTop" => dep_top, "depH" => dep,
    };
    tro.set("geo", geo.clone());
    let row_h = (if organ != 0.0 { organ_top + organ } else if dep != 0.0 { dep_top + dep } else { rail_top + rail_h }) + g.inset;
    tro.set("rowH", row_h);
    geo.set("rowH", row_h);
    // 사건 분류별 내부 글줄: 한 줄의 사건 분류가 둘 이상이면 분류마다 글줄 하나(분류 목록 차례)
    let cats = tl.get("_cats");
    let cat_index = |id: &V| -> f64 { if tv(&cats) && cats.as_map().is_some_and(|m| m.has(id)) { n(&cats.as_map().expect("분류").get(id).get("i")) } else { 9999.0 } };
    let row_cats: Vec<V> = events_by_row.iter().map(|l| {
        if density > 0.0 { return V::Null; }
        let ids = Set::new();
        for e in l.to_vec() { if !e.bool("parentUid") { ids.add(or(e.get("category"), s("etc"))); } }
        let mut ids = ids.values();
        if ids.len() >= 2 { js::sort(&mut ids, |a, b| cat_index(a) - cat_index(b)); arr(ids) } else { V::Null }
    }).collect();
    // 시기 구분(학계) 단 · 지위 단 · 단체 단 — 줄 단위 위쪽 덧단
    let phase_lanes = |p: &V| -> f64 {
        if !matches!(show.get("phases"), V::Bool(false)) && density <= 0.0 && p.bool("phaseSchemes") { js::min(&[g.phase_max, n(&p.get("phaseSchemes").get("length"))]) } else { 0.0 }
    };
    let up_rows: Vec<f64> = rp_lists.iter().enumerate().map(|(r, l)| {
        if folded_rows.has(&V::Num(r as f64)) { 0.0 } else { max0(l.iter().map(phase_lanes).collect()) * (g.phase + g.phase_gap) }
    }).collect();
    let rank_rows: Vec<f64> = rp_lists.iter().enumerate().map(|(r, l)| {
        if !folded_rows.has(&V::Num(r as f64)) && !matches!(show.get("ranks"), V::Bool(false)) && density <= 0.0 && l.iter().any(|p| p.bool("rankSpans") && n(&p.get("rankSpans").get("length")) > 1.0) { g.rank + g.rank_gap } else { 0.0 }
    }).collect();
    let groups_on = show.bool("groups") && density <= 0.0;
    let strip_rows = |want: &str| -> Vec<f64> {
        rp_lists.iter().enumerate().map(|(r, l)| {
            if groups_on && !folded_rows.has(&V::Num(r as f64)) && l.iter().any(|p| tv(&group_strip(p).get(want).get("length"))) { g.power + g.power_gap } else { 0.0 }
        }).collect()
    };
    let power_rows = strip_rows("power");
    let real_rows = strip_rows("real");
    // 줄마다의 세로 자리(글줄 수 · 예속 띠 · 위쪽 덧단 · 인물 단 수)
    let geo_for = |l_: f64, dp: f64, up: f64, rk: f64, fg: f64, pw: f64, rl: f64| -> V {
        let sh = up + rk + pw + rl;
        let tt = text_top + sh;
        let rt = tt + l_ * g.line;
        let ft = rt + rail_h + g.slot_gap;
        let fh = if fg != 0.0 { fg * g.figure + (fg - 1.0) * g.fig_gap } else { 0.0 };
        let dt = if fh != 0.0 { ft + fh + g.slot_gap } else { rt + rail_h + g.slot_gap };
        let ot = dt + if dp != 0.0 { dp + g.slot_gap } else { 0.0 };
        let out = Obj::new();
        for (k, v) in geo.entries() { out.set(&k, v); }
        let rh = (if organ != 0.0 { ot + organ } else if dp != 0.0 { dt + dp } else if fh != 0.0 { ft + fh } else { rt + rail_h }) + g.inset;
        for (k, v) in [
            ("lines", l_), ("phaseTop", leader_top), ("phaseH", up), ("rankTop", leader_top + up), ("rankH", if rk != 0.0 { g.rank } else { 0.0 }),
            ("powerTop", leader_top + up + rk), ("powerH", if pw != 0.0 { g.power } else { 0.0 }), ("realTop", leader_top + up + rk + pw), ("realH", if rl != 0.0 { g.power } else { 0.0 }),
            ("leaderTop", leader_top + sh), ("cabinetTop", cabinet_top + sh), ("textTop", tt), ("railTop", rt), ("figTop", ft), ("figH", fh), ("figLevels", fg),
            ("depTop", dt), ("depH", dp), ("organTop", ot), ("rowH", rh),
        ] { out.set(k, v); }
        V::Obj(out)
    };
    let at = |xs: &[f64], r: usize| or0(xs.get(r).copied().unwrap_or(f64::NAN));
    let geos: Vec<V> = row_cats.iter().enumerate().map(|(r, c)| {
        let l_ = if tv(c) { n(&c.get("length")) } else { lines };
        geo_for(l_, at(&dep_rows, r), at(&up_rows, r), at(&rank_rows, r), at(&fig_rows, r), at(&power_rows, r), at(&real_rows, r))
    }).collect();
    tro.set("rowCats", arr(row_cats.clone()));
    tro.set("geos", arr(geos));
    // 조감: 줄은 띠 하나뿐 — 모든 칸 · 글줄 · 막대 · 인물 · 덧단의 높이가 0
    if tv(&bird) {
        let h = n(&bird.get("h"));
        let bgeo = o! {
            "lines" => 1.0, "font" => 10.0, "name" => 10.5, "dynastyTop" => 0.0, "dynastyH" => 0.0, "leaderTop" => 0.0, "leaderH" => 0.0, "cabinetTop" => 0.0, "cabinetH" => 0.0,
            "organTop" => h, "organH" => 0.0, "textTop" => 0.0, "lineH" => h, "railTop" => h, "railH" => 0.0, "railLevels" => 0.0, "depTop" => h, "depH" => 0.0, "rowH" => h, "bird" => true,
        };
        tro.set("geo", bgeo.clone());
        tro.set("rowH", h);
        tro.set("rowCats", arr(row_cats.iter().map(|_| V::Null).collect()));
        let n_geos = list(&tr.get("geos")).len();
        tro.set("geos", arr((0..n_geos).map(|_| {
            let out = Obj::new();
            for (k, v) in bgeo.entries() { out.set(&k, v); }
            for (k, v) in [("phaseTop", 0.0), ("phaseH", 0.0), ("rankTop", 0.0), ("rankH", 0.0), ("powerTop", 0.0), ("powerH", 0.0), ("realTop", 0.0), ("realH", 0.0), ("figTop", h), ("figH", 0.0), ("figLevels", 0.0)] { out.set(k, v); }
            V::Obj(out)
        }).collect()));
    }

    // 5) 줄마다의 높이와 위쪽 위치(접힌 민족 줄은 낮고, 민족이 바뀌는 곳은 조금 더 띄운다)
    let (row_top, row_gap, row_hs, row_cut) = (Arr::default(), Arr::default(), Arr::default(), Arr::default());
    tro.set("rowTop", row_top.clone());
    tro.set("rowGap", row_gap.clone());
    tro.set("rowHs", row_hs.clone());
    tro.set("rowCut", row_cut.clone());
    let mut y = g.pad;
    let group_start = Set::new();
    for gp in groups.to_vec() { if !tv(&tr.get("board")) || gp.bool("from") { group_start.add(gp.get("first")); } }
    // 서고의 줄 올림(timeline.js 67c9f897d273 3543 ~ 3556줄 `tr.rowLift`): 메이커 미리보기(opts.seogo)만 켜는 값이라 내보내기에서는 모든 줄이 0 — 탭 자리(`_tabOf`)는 그대로
    tro.set("rowLift", arr(row_periods.to_vec().iter().map(|_| V::Num(0.0)).collect()));
    let tr_row_h = n(&tr.get("rowH"));
    let geos_now = list(&tr.get("geos"));
    let mut r = 0.0;
    while r < rows_n {
        let rv = V::Num(r);
        let tab = if folded_rows.has(&rv) || r == common_row { 0.0 } else { g.tab };
        let gap = (if r == 0.0 { 0.0 } else if member_rows.has(&rv) { g.member_gap } else { g.gap + if group_start.has(&rv) { g.group_gap } else { 0.0 } }) + tab + scope_pad(&tl, tr, r, r - 1.0);
        let hl = n(&or(hang_row_lanes.get(&rv), V::Num(0.0)));
        let zl = n(&or(zone_row_lanes.get(&rv), V::Num(0.0)));
        let cut = if tv(&bird) || folded_rows.has(&rv) { 0.0 } else {
            (if hl + zl != 0.0 && !(hl + zl).is_nan() { hl * HANG_PITCH + zl * (g.zone_tab + g.zone_gap) + 3.0 } else { 0.0 }) + if under_row_set.has(&rv) { g.hem } else { 0.0 }
        };
        row_cut.push(cut);
        let gr = geos_now.get(r as usize).cloned().unwrap_or_default();
        let h = if folded_rows.has(&rv) { g.folded_group } else { n(&or(and(gr.clone(), || gr.get("rowH")), V::Num(tr_row_h))) + cut };
        y += gap;
        row_gap.push(gap);
        row_top.push(y);
        row_hs.push(h);
        y += h;
        r += 1.0;
    }
    tro.set("height", if tr.bool("folded") { g.folded } else { js::max(&[y + g.pad, g.folded]) });
    // 화면 범위에 따라 빈 줄을 접을 때의 기준값
    tro.set("baseRowTop", arr(row_top.to_vec()));
    tro.set("baseRowGap", arr(row_gap.to_vec()));
    tro.set("baseRowHs", arr(row_hs.to_vec()));
    tro.set("baseHeight", tr.get("height"));
    tro.set("hiddenRows", Set::new());
    tro.set("_rowMemo", false);
    tro.set("_hiddenSig", V::Null);
    Ok(())
}

// ── 집합 보기(판 트랙) — js/timeline.js 8876 ~ 9008줄 `_boardPlan` · `_boardVisit` · `_boardGroups` · `_boardBranch`(갈래 E · 과제 15) ──

/// `BOARD_ID`(timeline.js 47줄) — 판 트랙의 id.
pub const BOARD_ID: &str = "__board";

/// `tl._boardPlan()` — 판(`tl.board`)을 켰으면 판 트랙을 지어 맨 앞에 넣는다: 구성 나라가 놓인 줄을 통째로(그 줄의 나라 · 사건 · 인물과 함께) 맨 위 합성 트랙 `__board`로 —
/// 원래 트랙에서는 그 줄을 뺀다(`axisPeriods`에 옮기기 전 목록). 줄은 지금 규칙의 배치(민족 묶음 접힘만 풀고)로 한 번 먼저 짓고 구성 나라의 줄을 떠 온다.
/// 판이 없으면 `_boardTr` · `_boardUids`를 비우기만. 구성 나라가 하나도 보이지 않으면 판 트랙 없이 그대로.
pub fn board_plan(ctx: &mut Ctx) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let tlo = ob(&tl);
    tlo.set("_boardTr", V::Null);
    tlo.set("_boardUids", V::Null);
    let v = tl.get("board");
    if !tv(&v) { return Ok(()); }
    let owner = Map::new(); // 정권 uid → 지금 그 정권을 든 트랙
    for tr in list(&tl.get("tracks")) { for p in items(&tr.get("periods")) { owner.set(p.get("uid"), tr.clone()); } }
    let keep = tl.get("foldedPeoples");
    tlo.set("foldedPeoples", Set::new());
    let planned = board_rows(ctx, &v, &owner); // try … finally — 접힘 기억을 늘 되돌림
    tlo.set("foldedPeoples", keep);
    let plan = planned?;
    if plan.is_empty() { return Ok(()); }
    // 줄에 딸린 것: 그 줄 정권 아래의 소속(숨었든 펼쳤든 — 판 트랙에서 다시 상위 아래로), 그 줄에 깔린 바탕 문화 · 얹힌 기관
    let moved = Set::new();
    let mut rows_of: Vec<(V, Set)> = Vec::new(); // Map(트랙 → 줄들) — 넣은 차례
    for (tr, row, l) in &plan {
        for p in l { moved.add(p.clone()); }
        match rows_of.iter().position(|(x, _)| eq(x, tr)) {
            Some(k) => rows_of[k].1.add(row.clone()),
            None => { let st = Set::new(); st.add(row.clone()); rows_of.push((tr.clone(), st)); }
        }
    }
    for (tr, rows) in &rows_of {
        let mut grew = true;
        while grew {
            grew = false;
            for p in items(&tr.get("periods")) {
                if moved.has(&p) { continue; }
                let host = p.get("_host");
                if (tv(&host) && moved.has(&host)) || ((p.bool("_under") || p.bool("_overlay")) && !p.get("_row").is_nullish() && rows.has(&p.get("_row"))) {
                    moved.add(p.clone());
                    grew = true;
                }
            }
        }
    }
    let uids = Set::new();
    for p in moved.values() { uids.add(p.get("uid")); }
    let people_of = |p: &V| -> V {
        let path = items(&p.get("peoplePath"));
        let pe = path.last().cloned().unwrap_or_default();
        if tv(&pe) { return V::Obj(o! { "id" => pe.get("id"), "name" => pe.get("name"), "color" => or(or(pe.get("color"), p.get("peopleColor")), V::Null) }); }
        if is(&p.get("polityKind"), "culture") { V::Obj(o! { "id" => "__culture", "name" => "문화", "color" => V::Null, "culture" => true }) } else { V::Null }
    };
    // JS `v.members.filter(...)`(timeline.js 8934) — 계획이 있으면 members는 배열이어야 한다: 줄 계획(board_rows)은 for…of라 글 · Map · Set도 받았지만
    // 여기서 JS는 `.filter`가 없어 TypeError(16b 틀 손질 검토 — 조용히 다른 답을 내지 않게).
    let members = v.get("members");
    if !matches!(members, V::Arr(_)) {
        return Err(format!("집합 보기: v.members가 배열이 아닙니다({} — JS라면 v.members.filter에서 TypeError)", js::type_of(&members)).into());
    }
    let present: Vec<V> = items(&members).into_iter().filter(|uid| owner.has(uid)).collect();
    let present_tracks = Set::new();
    for uid in &present { present_tracks.add(owner.get(uid).get("id")); }
    let label = format!("집합 보기 · 트랙 {} · 나라 {}", present_tracks.len(), present.len());
    let board_rows_arr = Arr::default();
    let btr = o! {
        "id" => BOARD_ID, "name" => "집합 보기", "color" => or(v.get("color"), s("#d7c18e")), "order" => -1e9, "periods" => arr(Vec::new()), "events" => arr(Vec::new()), "figures" => arr(Vec::new()),
        "board" => o! { "view" => v.clone(), "label" => label.as_str(), "rows" => board_rows_arr.clone() },
    };
    for (tr, _, l) in &plan {
        let pe = people_of(&l[0]);
        if let Some(po) = pe.as_obj() { po.set("color", or(po.get("color"), tr.get("color"))); } // Object.assign(pe, { color: pe.color || r.tr.color })
        board_rows_arr.push(o! {
            "periods" => arr(l.clone()), "track" => tr.get("id"), "trackName" => tr.get("name"), "trackColor" => tr.get("color"), "people" => pe, "first" => 0.0, "count" => 0.0,
        });
    }
    let (b_periods, b_events, b_figures) = (btr.arr("periods").expect("배열"), btr.arr("events").expect("배열"), btr.arr("figures").expect("배열"));
    for (tr, _) in &rows_of {
        let tro = ob(tr);
        let axis = tr.get("periods");
        tro.set("axisPeriods", axis.clone()); // 날짜 칸은 원래 트랙의 묶음 그대로(_buildAxis)
        let all = items(&axis);
        tro.set("periods", arr(all.iter().filter(|p| !moved.has(p)).cloned().collect()));
        for p in all.iter().filter(|p| moved.has(p)) { b_periods.push(p.clone()); }
        let mut stay = Vec::new();
        for e in items(&tr.get("events")) {
            let place = e.get("_place");
            let pol = if tv(&place) { place.get("polityUid") } else { e.get("polityUid") };
            if uids.has(&pol) { b_events.push(e); } else { stay.push(e); }
        }
        tro.set("events", arr(stay));
        let mut fstay = Vec::new();
        for x in items(&tr.get("figures")) {
            let sv = x.get("s");
            if tv(&sv) && tv(&sv.get("polity")) && uids.has(&sv.get("polity").get("uid")) { b_figures.push(x); } else { fstay.push(x); }
        }
        tro.set("figures", arr(fstay));
    }
    match tl.get("tracks") { V::Arr(a) => a.borrow_mut().insert(0, V::Obj(btr.clone())), _ => return Err("집합 보기: tl.tracks가 배열이 아닙니다(JS라면 TypeError)".into()) }
    tlo.set("_boardTr", btr);
    tlo.set("_boardUids", uids);
    Ok(())
}

/// `_boardPlan`의 `try` 몸: 구성 나라마다 그 트랙을 (한 번) 배치하고 그 나라가 놓인 줄(숨은 소속이면 그 상위의 줄)을 떠 온다 — `[(트랙, 줄, 그 줄의 숨지 않은 정권)]`.
/// 같은 줄에 든 둘째 나라는 첫째의 줄에 함께.
fn board_rows(ctx: &mut Ctx, v: &V, owner: &Map) -> crate::Result<Vec<(V, V, Vec<V>)>> {
    let laid = Set::new();
    let taken = Set::new(); // '트랙#줄'
    let mut plan = Vec::new();
    // JS `for (const uid of v.members)` — 배열 · 글 · Map · Set은 돈다(js::for_of — 16b) · 그 밖은 TypeError(과제 Y). try 몸 안이라 접힘 기억은 되돌린다.
    let Some(members) = js::for_of(&v.get("members")) else { return Err("집합 보기의 줄 배정(_boardPlan): tl.board.members가 순회되지 않습니다(JS라면 TypeError)".into()) };
    for uid in members {
        let tr = owner.get(&uid);
        if !tv(&tr) { continue; } // 거르기로 숨었거나 켜지 않은 DLC의 나라 — 판에서는 빠짐
        if !laid.has(&tr) {
            layout_track(ctx, &tr)?;
            laid.add(tr.clone());
        }
        let mut q = items(&tr.get("periods")).into_iter().find(|p| eq(&p.get("uid"), &uid)).unwrap_or_default();
        while tv(&q) && q.bool("_hidden") { q = q.get("_host"); } // 상위 띠 아래 숨은 소속은 그 상위의 줄째로
        if !tv(&q) || q.get("_row").is_nullish() { continue; }
        let row = q.get("_row");
        let key = s(&format!("{}#{}", t(&tr.get("id")), t(&row)));
        if taken.has(&key) { continue; }
        taken.add(key);
        let l: Vec<V> = items(&tr.get("rowPeriods").get(&n(&row))).into_iter().filter(|p| !p.bool("_hidden")).collect();
        if !l.is_empty() { plan.push((tr, row, l)); }
    }
    Ok(plan)
}

/// `_boardVisit(tr, rowList, pushMembers)` — 판 트랙의 줄 만들기(민족 나무의 visit 대신): 떠 온 줄을 차례대로, 줄마다 그 아래 펼친 소속 줄과 함께.
/// 같은 줄의 곧바로 이어지는 승계 쌍(이음매)은 chainRows와 같은 규칙으로 다시 적는다.
fn board_visit(w: &mut Walk, tr: &V) -> crate::Result<()> {
    for r in items(&tr.get("board").get("rows")) {
        let ro = ob(&r);
        ro.set("first", w.row_list.len() as f64);
        // JS `r.periods.filter(…)` — 배열이 아니면 TypeError(과제 Y — 갈래 E 덧붙임이 남긴 길: _boardPlan이 늘 배열을 둔다)
        if !matches!(r.get("periods"), V::Arr(_)) { return Err("집합 보기의 줄 만들기(_boardVisit): 판 줄의 periods가 배열이 아닙니다(JS라면 TypeError)".into()); }
        let l: Vec<V> = items(&r.get("periods")).into_iter().filter(|p| !p.bool("_member") && !p.bool("_hidden") && !p.bool("_under") && !p.bool("_overlay")).collect();
        for k in 1..l.len() {
            let (q, p) = (&l[k - 1], &l[k]);
            if !q.bool("endUnknown") && !p.bool("startUnknown") && !q.bool("endRange") && !p.bool("startRange") && items(&p.get("predecessors")).iter().any(|e| eq(&e.get("from"), q)) {
                ob(q).set("_seamR", p.clone());
                ob(p).set("_seamL", q.clone());
            }
        }
        if !l.is_empty() {
            w.row_list.push(Row { periods: l.clone(), folded: false, member: false });
            for p in &l { w.push_members(p); }
        }
        ro.set("count", w.row_list.len() as f64 - n(&ro.get("first")));
    }
    Ok(())
}

/// `_boardGroups(tr)` — 판 트랙의 왼쪽 칸 묶음: 원래 트랙 칩(첫 단 — from) · 제 민족 칩(둘째 단). 같은 트랙(같은 민족)이 이어진 줄은 하나로 — 접지 않음.
fn board_groups(tr: &V) -> Vec<V> {
    let mut out: Vec<V> = Vec::new();
    let rows: Vec<V> = items(&tr.get("board").get("rows")).into_iter().filter(|r| tv(&r.get("count"))).collect();
    let mut run: Option<Obj> = None;
    for r in &rows {
        let span = |x: &Obj| n(&r.get("first")) + n(&r.get("count")) - n(&x.get("first"));
        match &run {
            Some(x) if eq(&x.get("track"), &r.get("track")) => x.set("count", span(x)),
            _ => {
                let x = o! {
                    "key" => format!("__from:{}", t(&r.get("track"))).as_str(), "name" => r.get("trackName"), "color" => r.get("trackColor"), "depth" => 0.0, "first" => r.get("first"),
                    "count" => r.get("count"), "folded" => false, "culture" => false, "from" => true, "track" => r.get("track"),
                };
                out.push(V::Obj(x.clone()));
                run = Some(x);
            }
        }
    }
    let mut pr: Option<Obj> = None;
    for r in &rows {
        let pe = r.get("people");
        if !tv(&pe) { pr = None; continue; }
        let k = format!("{}|{}", t(&r.get("track")), t(&pe.get("id")));
        match &pr {
            Some(x) if is(&x.get("k"), &k) => x.set("count", n(&r.get("first")) + n(&r.get("count")) - n(&x.get("first"))),
            _ => {
                let x = o! {
                    "k" => k.as_str(), "key" => pe.get("id"), "name" => pe.get("name"), "color" => pe.get("color"), "depth" => 1.0, "first" => r.get("first"), "count" => r.get("count"),
                    "folded" => false, "culture" => pe.bool("culture"),
                };
                out.push(V::Obj(x.clone()));
                pr = Some(x);
            }
        }
    }
    out
}

/// `_boardBranch(tr)` — 판 트랙의 테두리 하나(대범위 가지와 같은 꼴 — `_scopePad`가 그대로 씀).
fn board_branch(tro: &Obj, tr: &V) -> crate::Result<V> {
    tro.set("_bundled", Set::new());
    let rp = list(&tr.get("rowPeriods"));
    if rp.is_empty() { return Ok(arr(Vec::new())); }
    let v = tr.get("board").get("view");
    // JS `v.start` — 판의 보기(view)가 없으면(null · undefined) TypeError(과제 Y — 갈래 E 덧붙임이 남긴 길: boards가 판 트랙에 늘 view를 단다)
    if v.is_nullish() { return Err("집합 보기의 테두리(_boardBranch): tr.board.view가 없습니다(JS라면 v.start에서 TypeError)".into()); }
    let start = v.get("start");
    let has = !start.is_nullish() && js::to_num(&start).is_finite();
    let end = v.get("end");
    let end_y = if has { if !end.is_nullish() && js::to_num(&end).is_finite() { end } else { start.clone() } } else { V::Num(0.0) };
    let sc = o! {
        "uid" => BOARD_ID, "name" => or(v.get("name"), s("집합 보기")), "label" => tr.get("board").get("label"), "color" => tr.get("color"),
        "start" => if has { start } else { V::Num(0.0) }, "endY" => end_y, "rangeFrom" => if has { V::Undef } else { s("members") }, "temp" => v.bool("temp"),
    };
    let flat: Vec<V> = rp.iter().flat_map(list).collect();
    Ok(arr(vec![V::Obj(o! {
        "s" => sc, "uid" => BOARD_ID, "first" => 0.0, "count" => rp.len() as f64, "host" => V::Null, "hostRow" => -1.0, "hung" => false, "list" => arr(flat), "box" => V::Null, "board" => true,
    })]))
}

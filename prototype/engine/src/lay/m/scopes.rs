//! 내보내기 모듈 `scopes` — `prototype/scripts/export/scopes.mjs`(1 ~ 139줄 · SHA-256 앞 12자 `69630cb67c94` — 저장소의 LF 바이트)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 10).
//! 대범위 테두리(구역 23) · 기간 칠(24) · 그릇 안 이름표 시대(53) — **켠 대범위에만**(지금 연표의 `_scopeNodes` · `_scopeBranches`가 만든 `tr.scopeBranches`를 그대로 읽는다) —
//! 와 풀린 그릇의 열쇠표(50 — 이 판에서 꺼 둔 대범위의 구성 띠마다). 값의 뜻은 계약 6-10절, 규칙은 명세 04-관계선 6절.
//! (2026-10-25 · 리메이크 4단계 선반 갈래 걸음 4) 숨긴 구성원 꼬리표(59 — 선반 상태로 다시 배치한 가지의 `b.shelf`마다 · 선반 변형 `shelf:<uid>`의 다시 셈에서만) —
//! 가지의 `shelf`는 줄 배정의 [`crate::lay::scope::scope_branches`]가 `tr._shelf`에서 둔다.
//! 읽는 shared · out 없음. 부르는 웹 함수: `tl.scopeOn`(→ [`scope_on`]) · `tr.scopeBranches`(줄 배정이 둠) · `model.periods`. 모듈의 `bandStart` · `bandEnd`는 `lay::rows`의 것 ·
//! `lodOf`는 `rails.mjs`의 것(→ [`lod_of`]) · `SHELF_KEEP`은 줄 배정의 [`SHELF_KEEP`](지금 연표 `G_SEOGO.shelfKeep`).
use super::kit::{lod_of, minute_val};
use super::rails::push_item;
use crate::lay::ctx::Ctx;
use crate::lay::export::color;
use crate::lay::js::{self, Map, Obj, V};
use crate::lay::model::o;
use crate::lay::model::util::{assign_obj, eq, is, list, lt, n, or, t, tv};
use crate::lay::rows::{band_end, band_start, is_finite_num, items};
use crate::lay::scope::scope_on;
use crate::lay::track::SHELF_KEEP;
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 내가 쓰는 구역 번호(계약 6-10절) — 50은 풀린 그릇의 열쇠표(리메이크 조각 ③ · 아래 [`contribute`] 끝) · 59는 숨긴 구성원 꼬리표(선반).
pub struct Section { pub scope: f64, pub scope_span: f64, pub key: f64, pub label: f64, pub shelf: f64 }
pub const SECTION: Section = Section { scope: 23.0, scope_span: 24.0, key: 50.0, label: 53.0, shelf: 59.0 };

/// 대범위의 구성으로 세지 않는 띠의 종류(지금 연표의 `_scopeClaims`와 같다).
const SKIP_KINDS: [&str; 3] = ["overlay", "culture", "dynasty"];

/// 구역 23 · 테두리의 a 비트. board(8) = **집합 보기 판의 둘레**(boards.mjs가 판을 켠 배치를 다시 돌릴 때만 생긴다).
struct Sc { hung: i32, after_host: i32, guessed: i32, board: i32 }
const SC: Sc = Sc { hung: 1, after_host: 2, guessed: 4, board: 8 };

/// 자료 전체의 시각 범위(해) — 집합 보기 판의 둘레가 어느 타일에나 실리게. 모든 정권 띠의 바깥 끝까지.
fn extent_of(ctx: &Ctx) -> (f64, f64) {
    let (mut lo, mut hi) = (f64::INFINITY, f64::NEG_INFINITY);
    for p in items(&ctx.model.get("periods")) {
        let (a, b) = (band_start(&p), band_end(&p));
        if is_finite_num(&a) && n(&a) < lo { lo = n(&a); }
        if is_finite_num(&b) && n(&b) > hi { hi = n(&b); }
    }
    (lo, hi)
}

/// `contribute(ctx, out)`.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let (mut c_border, mut c_span, mut c_label) = (0.0, 0.0, 0.0);
    let (mut s_branch, mut s_member) = (0.0, 0.0);
    let mut shelf_tags = 0.0;
    let item = |out: &mut Value, extra: Obj| {
        let base = o! { "section" => 0.0, "track" => 0.0, "row" => 0.0, "row2" => 0.0, "start" => 0.0, "end" => 0.0, "lod" => -1.0, "ref" => "", "name" => "", "color" => 0.0, "a" => 0.0, "b" => 0.0, "c" => 0.0, "d" => 0.0, "text2" => "" };
        assign_obj(&base, &extra);
        push_item(out, &base);
    };
    let tracks = list(&tl.get("tracks"));

    for (track, tr) in tracks.iter().enumerate() {
        let track = track as f64;
        let branches = items(&tr.get("scopeBranches"));
        if branches.is_empty() { s_branch += 1.0; continue; }
        for b in &branches {
            let s = b.get("s");
            let members: Vec<V> = items(&b.get("list")).into_iter().filter(|p| tv(p) && !p.get("_row").is_nullish()).collect();
            if members.is_empty() { s_member += 1.0; continue; }
            // 가로: 구성 띠 전체의 시각 범위(가로 여백 8px과 미정 꼬리 44px은 그릴 때 더한다 — 명세 6-3).
            let (mut lo, mut hi) = (f64::INFINITY, f64::NEG_INFINITY);
            for p in &members {
                lo = js::min(&[lo, n(&band_start(p))]);
                hi = js::max(&[hi, n(&band_end(p))]);
            }
            // 집합 보기의 판 둘레: 어느 시기를 보든 타일에 실리도록 자료 전체의 시각 범위로(지금 연표의 _scopeX가 판이면 화면 전체 — 기본 상태에는 없다).
            if b.bool("board") { (lo, hi) = extent_of(ctx); }
            let (start, end) = (minute_val(&V::Num(lo)), minute_val(&V::Num(hi)));
            if start.is_nullish() || end.is_nullish() || lt(&end, &start) { continue; }
            let row = b.get("first");
            let row2 = n(&js::add(&b.get("first"), &b.get("count"))) - 1.0;
            let a = (if b.bool("hung") { SC.hung } else { 0 }) | (if s.bool("afterHost") { SC.after_host } else { 0 }) | (if is(&s.get("rangeFrom"), "members") { SC.guessed } else { 0 }) | (if b.bool("board") { SC.board } else { 0 });
            let host = b.get("host");
            let host_uid = if tv(&host) { host.get("uid") } else { V::from("") };
            // b = 구성 띠 수(리메이크 조각 ③ — 폴더 탭의 라벨 '이름 수'). 0이면 수를 쓰지 않는다(옛 저장소).
            item(out, o! {
                "section" => SECTION.scope, "track" => track, "row" => row.clone(), "row2" => row2, "start" => start.clone(), "end" => end.clone(), "lod" => -1.0,
                // text2 = 그릇 uid␟성격(리메이크 2부 포개짐 — 그리는 쪽이 첫 줄로 uid를 찾지 않게 · ␟이 없으면 옛 저장소: 성격만)
                "ref" => host_uid.clone(), "name" => or(s.get("name"), V::from("")), "color" => f64::from(color(&s.get("color"), 0xa4b1b7)), "a" => f64::from(a), "b" => members.len() as f64,
                "text2" => format!("{}\u{1f}{}", t(&s.get("uid")), t(&or(s.get("label"), V::from("")))),
            });
            c_border += 1.0;
            /* 구역 53 · 그릇 안 이름표 시대(리메이크 2부 · 설계 3-3): 켠 그릇의 가지마다 그 그릇에 든 시대 구분(구성원 없는 시대 — epochs[].within)마다 하나. */
            for e in items(&s.get("labels")) {
                let (es, ee) = (minute_val(&e.get("start")), minute_val(&e.get("endY")));
                if es.is_nullish() || ee.is_nullish() || lt(&ee, &es) { continue; }
                item(out, o! { "section" => SECTION.label, "track" => track, "row" => row.clone(), "row2" => row2, "start" => es, "end" => ee, "lod" => -1.0, "ref" => "", "name" => or(e.get("name"), V::from("")), "color" => f64::from(color(&s.get("color"), 0xa4b1b7)), "text2" => e.get("uid") });
                c_label += 1.0;
            }
            /* 구역 59 · 숨긴 구성원 꼬리표(선반 — 리메이크 4단계): 선반 상태로 다시 배치한 가지(b.shelf — 줄 배정이 상위 SHELF_KEEP 밖으로 숨긴 구성원 · shelf_split 차례)의
               숨은 띠마다 하나. row = row2 = 가지 끝 줄 · start · end = 그 띠의 바깥 끝 · lod = 테(23)와 같은 단계 · ref · text2 = 띠 uid · a = 그릇 안 차례 · b = 숨은 수 */
            let shelf = items(&b.get("shelf"));
            for (i, p) in shelf.iter().enumerate() {
                let (ps, pe) = (minute_val(&band_start(p)), minute_val(&band_end(p)));
                if ps.is_nullish() || pe.is_nullish() || lt(&pe, &ps) { continue; }
                item(out, o! {
                    "section" => SECTION.shelf, "track" => track, "row" => row2, "row2" => row2, "start" => ps, "end" => pe, "lod" => lod_of(n(&end) - n(&start)),
                    "ref" => p.get("uid"), "name" => or(p.get("name"), V::from("")), "color" => f64::from(color(&p.get("color"), 0xa4b1b7)),
                    "a" => (SHELF_KEEP + i) as f64, "b" => shelf.len() as f64, "text2" => p.get("uid"),
                });
                shelf_tags += 1.0;
            }
            // 기간의 짙은 세로 구간: 시각을 a~d(u32)에 담을 수 없어 따로 낸다. 줄 범위가 23과 같아 그리는 쪽이 그 줄로 짝을 찾는다.
            // 기간을 적지 않은 집합 보기는 구간이 없다(지금 연표의 _drawScopes — rangeFrom 'members'면 그리지 않음).
            if b.bool("board") && is(&s.get("rangeFrom"), "members") { continue; }
            let (ss, se) = (minute_val(&s.get("start")), minute_val(&s.get("endY")));
            if ss.is_nullish() || se.is_nullish() || lt(&se, &ss) { continue; }
            item(out, o! { "section" => SECTION.scope_span, "track" => track, "row" => row.clone(), "row2" => row2, "start" => ss, "end" => se, "lod" => -1.0, "ref" => host_uid, "name" => "", "color" => f64::from(color(&s.get("color"), 0xa4b1b7)) });
            c_span += 1.0;
        }
    }

    // 풀린 그릇의 열쇠표(구역 50 — 리메이크 조각 ③ · 설계 4-6 #2 B '풀림'): 이 판에서 **꺼 둔** 대범위의 구성 띠마다 하나 —
    // 테가 없어지고 구성원이 제 줄에 있을 때 그릇 이름이 그 띠 위의 열쇠표로 남는다. 구성은 지금 연표의 `_scopeClaims`와 같은 셈
    // (덧그림 · 바탕 문화 · 왕조 띠와 본국은 빼고 · 그 트랙에 그려진 띠만). 줄 비트 15는 tracks.mjs의 늦은 차례가 이 구역을 보고 켠다.
    let mut keys = 0.0;
    for (track, tr) in tracks.iter().enumerate() {
        let track = track as f64;
        let off: Vec<V> = items(&tl.get("scopes")).into_iter().filter(|s| eq(&s.get("track"), &tr.get("id")) && !scope_on(&tl, s)).collect();
        if off.is_empty() { continue; }
        let in_track = Map::new();
        for p in list(&tr.get("periods")) { in_track.set(p.get("uid"), p.clone()); }
        for s in &off {
            let ss = minute_val(&s.get("start"));
            for m in items(&s.get("members")) {
                let p = in_track.get(&m.get("uid"));
                let host = s.get("host");
                if !tv(&p) || SKIP_KINDS.iter().any(|k| is(&p.get("polityKind"), k)) || (tv(&host) && eq(&host.get("uid"), &p.get("uid"))) { continue; }
                if p.bool("_hidden") || p.bool("_overlay") || p.bool("_under") || p.get("_row").is_nullish() { continue; }
                let (a, e) = (minute_val(&band_start(&p)), minute_val(&band_end(&p)));
                if a.is_nullish() || e.is_nullish() { continue; }
                // 열쇠표의 해: 띠가 그릇보다 먼저 섰으면 그릇이 선 해(목업 loosen의 max(띠 시작, 그릇 시작)).
                let start = if ss.is_nullish() { a.clone() } else { V::Num(js::min(&[js::max(&[n(&a), n(&ss)]), n(&e)])) };
                item(out, o! { "section" => SECTION.key, "track" => track, "row" => p.get("_row"), "row2" => p.get("_row"), "start" => start, "end" => e, "lod" => -1.0, "ref" => p.get("uid"), "name" => or(s.get("name"), V::from("")), "color" => f64::from(color(&s.get("color"), 0xa4b1b7)), "text2" => s.get("uid") });
                keys += 1.0;
            }
        }
    }

    // JS의 counts는 { 대범위테두리, 대범위기간칠 }로 시작하고 그릇 안 이름표는 처음 실을 때 열쇠가 생긴다(그 뒤에 풀린그릇열쇠표) — 열쇠 차례까지 같게(과제 Y — 갈래 B 검토 Minor)
    let counts = o! { "대범위테두리" => c_border, "대범위기간칠" => c_span };
    if c_label > 0.0 { counts.set("그릇안이름표", c_label); }
    if shelf_tags > 0.0 { counts.set("선반꼬리표", shelf_tags); } // 선반 변형의 다시 셈에만 — 기본 배치의 알림은 그대로
    counts.set("풀린그릇열쇠표", keys);
    ctx.notes.set("대범위", counts);
    ctx.notes.set("대범위에서_뺀_것", o! { "가지없음" => s_branch, "구성정권없음" => s_member });
    Ok(())
}

//! 대범위(그릇)의 줄 배정 몫 — `js/timeline.js`의 `scopeOn` · `_scopeClaims` · `_scopeNodes` · `_scopeBranches` · `_scopePad`를 줄 그대로 옮긴다(한 벌 P3 과제 7).
//!
//! 옮긴 원본: `js/timeline.js` — 처음 옮긴 판 SHA-256 앞 12자 `8a3b02f5bf7f`(저장소의 LF 바이트) · 줄 번호는 모두 지금 판 `414ae245f221`의 것(2026-10-26 0.1.1 맞춤 — 맞춤 항목의 지문은 그 몫을 옮긴 때의 판)
//! - 10787 ~ 10790줄 `scopeOn` · 10909 ~ 10935줄 `_scopeClaims` · 10939 ~ 10958줄 `_scopeNodes` · 10961 ~ 10982줄 `_scopeBranches` · 10987 ~ 10996줄 `_scopePad`
//! - (`_setScopes` 10902 ~ 10906줄은 과제 6이 `lay::ctx::set_scopes`로 옮김)
//! - (2026-10-25 맞춤 · `timeline.js` `87107b969d36` · 리메이크 4단계 선반 갈래 걸음 4) 10971줄 `_scopeBranches` 가지의 `shelf`(선반에 둔 구성원 — `tr._shelf`)를 옮김 —
//!   내보내기 `scopes`의 숨긴 구성원 꼬리표(구역 59)가 읽는다. 그 뒤 줄의 포개짐 몫(`kids` · `ef` · `ee` · `depthBelow`)은 서고에서만 넓어지고
//!   내보내기에서는 가지의 첫 줄 · 끝 줄과 같아 예전대로 옮기지 않는다.
//!
//! 내보내기(`contextOf`)는 모든 그릇을 꺼 두므로(`tl.scopesOn` = uid → false) 켠 그릇이 없다 — 이 길은 그릇 하나를 켠 배치(변형 `scope:<uid>` — 과제 14의 REPLAY ·
//! 과제 16의 부분 셈)에서 쓴다. 렌즈 · 판은 그릇을 켜지 않는다.
use crate::lay::js::{self, Map, Obj, Set, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, eq, is, list, n, or, or_cmp, sub, t, tv};
use crate::lay::rows::{and, band_start, g_of, items};

/// `tl.scopeOn(s)` — 기록(`scopesOn[uid]`)이 없으면 대범위의 default.
pub fn scope_on(tl: &V, sc: &V) -> bool {
    let v = if tv(sc) { tl.get("scopesOn").get(&t(&sc.get("uid"))) } else { V::Null };
    if v.is_nullish() { tv(sc) && sc.bool("default") } else { tv(&v) }
}

/// `tl._scopeClaims(tr, inTrack)` — 이 트랙에서 켠 대범위의 구성 정권 uid → 그 대범위(직접 그릇에서 부모를 따라 올라가 켠 첫 그릇).
pub fn scope_claims(tl: &V, tr: &V, in_track: &Map) -> Map {
    let out = Map::new();
    let skip = ["overlay", "culture", "dynasty"];
    let tr_id = tr.get("id");
    let mut on: Vec<V> = items(&tl.get("scopes")).into_iter().filter(|sc| eq(&sc.get("track"), &tr_id) && scope_on(tl, sc)).collect();
    js::sort(&mut on, |a, b| sub(&a.get("start"), &b.get("start")));
    let claim = |p: &V, sc: &V| {
        if !tv(p) || skip.iter().any(|k| is(&p.get("polityKind"), k)) || out.has(&p.get("uid")) || (tv(&sc.get("host")) && eq(&sc.get("host").get("uid"), &p.get("uid"))) { return; }
        out.set(p.get("uid"), sc.clone());
    };
    let first_on = |sc: &V| -> V {
        let mut x = sc.clone();
        while tv(&x) {
            if eq(&x.get("track"), &tr_id) && scope_on(tl, &x) { return x; }
            x = x.get("parent");
        }
        V::Null
    };
    for p in in_track.values() {
        let mut direct: Vec<V> = items(&p.get("scopes")).into_iter().filter(|x| eq(&x.get("track"), &tr_id)).collect();
        js::sort(&mut direct, |a, b| or_cmp(n(&or_num(b.get("depth"))) - n(&or_num(a.get("depth"))), || sub(&a.get("start"), &b.get("start"))));
        for d in &direct {
            let sc = first_on(d);
            if tv(&sc) { claim(&p, &sc); break; }
        }
    }
    for sc in &on { for m in items(&sc.get("members")) { claim(&in_track.get(&m.get("uid")), sc); } }
    out
}
/// `(x || 0)`(값).
fn or_num(x: V) -> V { if tv(&x) { x } else { V::Num(0.0) } }

/// `tl._scopeNodes(tr, scopeOf, nodeOf, inTrack, byStart)` — 구성 정권을 제 민족 묶음에서 빼어 대범위마다 합성 가지(`__scope:<uid>`)로. 본국 줄에 매달 수 있으면 host.
pub fn scope_nodes(tr: &V, scope_of: &Map, node_of: &Map, in_track: &Map, by_start: impl Fn(&V, &V) -> f64) -> Vec<V> {
    let by_sc = Map::new();
    for p in list(&tr.get("periods")) {
        let sc = scope_of.get(&p.get("uid"));
        if tv(&sc) {
            let mut cur = list(&by_sc.get(&sc));
            cur.push(p.clone());
            by_sc.set(sc, arr(cur));
        }
    }
    let mut out: Vec<V> = Vec::new();
    for (sc, l) in by_sc.entries() {
        let lst = l.as_arr().expect("목록").clone();
        for p in lst.to_vec() {
            let nd = node_of.get(&p);
            if !tv(&nd) { continue; }
            let ps = nd.arr("periods").expect("묶음의 정권");
            let i = ps.borrow().iter().position(|x| eq(x, &p));
            if let Some(i) = i { ps.borrow_mut().remove(i); }
        }
        lst.sort_js(&by_start);
        let h = if tv(&sc.get("host")) { in_track.get(&sc.get("host").get("uid")) } else { V::Null };
        let host = if tv(&h) && !h.bool("_hidden") && !h.bool("_under") && !h.bool("_overlay") && !scope_of.has(&h.get("uid")) { h } else { V::Null };
        let start0 = js::min(&lst.to_vec().iter().map(|p| n(&band_start(p))).collect::<Vec<_>>());
        out.push(V::Obj(o! {
            "id" => format!("__scope:{}", t(&sc.get("uid"))), "name" => sc.get("name"), "color" => sc.get("color"), "order" => -1.0, "depth" => 0.0,
            "children" => arr(Vec::new()), "childMap" => Map::new(), "periods" => V::Arr(lst), "first" => 0.0, "count" => 0.0, "start0" => start0, "scope" => sc.clone(), "host" => host,
        }));
    }
    js::sort(&mut out, |a, b| sub(&a.get("start0"), &b.get("start0")));
    out
}

/// `tl._scopeBranches(tr, nodes)` — 가지의 줄 범위와, 테두리로 한 줄로 묶어 그릴 부흥선(`tr._bundled`).
pub fn scope_branches(tr: &Obj, nodes: &[V]) -> V {
    let bundled = Set::new();
    tr.set("_bundled", bundled.clone());
    let row_periods = tr.get("rowPeriods");
    let shelved = tr.get("_shelf"); // 선반에 둔 구성원(그릇 uid → 띠 목록 — 서고 · 선반 배치만 · 없으면 undefined)
    let out: Vec<V> = nodes.iter().filter(|sn| tv(&sn.get("count"))).map(|sn| {
        let sc = sn.get("scope");
        let mut l: Vec<V> = Vec::new();
        let (first, count) = (n(&sn.get("first")), n(&sn.get("count")));
        let mut r = first;
        while r < first + count { l.extend(items(&row_periods.get(&r))); r += 1.0; }
        let host = sn.get("host");
        if tv(&host) && tv(&sc.get("afterHost")) {
            for p in &l { for e in items(&p.get("predecessors")) { if eq(&e.get("from"), &host) && is(&e.get("type"), "revival") { bundled.add(e); } } }
        }
        V::Obj(o! {
            "s" => sc.clone(), "uid" => sc.get("uid"), "first" => sn.get("first"), "count" => sn.get("count"), "host" => host.clone(),
            "hostRow" => if tv(&host) { host.get("_row") } else { V::Num(-1.0) }, "hung" => tv(&host) && !tv(&sc.get("afterHost")), "list" => arr(l), "box" => V::Null,
            // shelf: (tr._shelf && tr._shelf.get(s.uid)) || null — 선반에 둔 구성원(서고 과제 9 · 리메이크 4단계 선반 변형)
            "shelf" => or(and(shelved.clone(), || shelved.as_map().map_or(V::Undef, |m| m.get(&sc.get("uid")))), V::Null),
        })
    }).collect();
    arr(out)
}

/// `tl._scopePad(tr, r, prev)` — 줄 간격에 더할 대범위 몫(가지의 펴진 첫 줄이면 머리, 가지가 끝난 뒤 처음 펴진 줄이면 아래 여백).
pub fn scope_pad(tl: &V, tr: &V, r: f64, prev: f64) -> f64 {
    let g = g_of(tl);
    let mut pad = 0.0;
    for b in items(&tr.get("scopeBranches")) {
        let first = n(&b.get("first"));
        let end = first + n(&b.get("count"));
        if r >= first && r < end && prev < first {
            pad += if b.bool("hung") && prev >= 0.0 && prev == n(&b.get("hostRow")) && matches!(b.get("hostRow"), V::Num(_)) { g.scope_head + 2.0 - g.gap - g.group_gap } else { g.scope_head };
        } else if prev >= first && prev < end && r >= end {
            pad += g.scope_foot;
        }
    }
    pad
}

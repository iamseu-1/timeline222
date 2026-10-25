//! `HT.normalizePack` 안의 패치 — 4781 ~ 4967줄(과제 5c): 다른 DLC의 항목을 고치는 패치(고칠 수 있는 칸은 `PATCHABLE` — `read::dates::PATCHABLE`).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트) · 4781 ~ 4967줄
//! - 대상 꼴 `/^[^/]+\/[^/]+$/`은 손으로(`target_ok` — '/'가 꼭 하나이고 앞뒤가 비지 않음)
//! - `set`의 칸은 파일과 같은 읽기로 다시 정리한다(배치용 연도 · 날짜 칸 · 연대 폭 · 이설 · 칸 목록 · 섬긴 기록 · 이름 · 사람 잇기 · 종류 · 승계 · 시기 · 지위 ·
//!   조약 · 주제 · 법 · 선거 · 단체 · 제도 · 실재성). 열쇠 차례는 JS 객체와 같다(있는 열쇠에 쓰면 자리 그대로 · 지우고 다시 쓰면 끝으로 — `js::Obj`).
//! (2026-10-24 맞춤 · 리메이크 6단계 걸음 2 · `core.js` `b2e6b19490bf`) 5327줄 `set.faiths`(종교 — 시기 구분 · 지위 변천과 같은 다시 읽기 · D8)
use super::cell_lists::name_list;
use super::{list_of, Norm};
use crate::lay::js::{self, Obj, Str, V};
use crate::lay::read::{self as read, cells, dates, groups, misc, names, treaty, vocab};

/// `/^[^/]+\/[^/]+$/.test(target)` — '/'가 꼭 하나이고 그 앞뒤가 비지 않는다(`[^/]`은 줄 끝도 받는다).
fn target_ok(t: &Str) -> bool {
    let u = t.to_units();
    let slashes: Vec<usize> = u.iter().enumerate().filter(|(_, &c)| c == 0x2F).map(|(k, _)| k).collect();
    slashes.len() == 1 && slashes[0] > 0 && slashes[0] + 1 < u.len()
}

/// 4781 ~ 4967줄 — 패치 목록.
pub(super) fn read_patches(n: &mut Norm, pack: &Obj, raw: &V) {
    let ctx = n.ctx;
    let s = dates::str_of;
    for (i, p) in dates::arr(&raw.get("patches")).iter().enumerate() {
        if !js::truthy(p) || !read::is_object(p) { n.err(format!("패치 #{}: 형식이 올바르지 않습니다.", i + 1), "patches", Some(i)); continue; }
        let target = s(&p.get("target"));
        let label = format!("패치 #{}{}", i + 1, if target.is_empty() { String::new() } else { format!(" ({target})") });
        if !target_ok(&target) { n.err(format!("{label}: 대상은 \"DLC id/항목 id\" 형식이어야 합니다."), "patches", Some(i)); continue; }
        if read::split_units(&target, &[0x2F])[0] == pack.str("id").unwrap_or_default() {
            n.warn(format!("{label}: 이 DLC 자신을 고치는 패치입니다. 항목을 직접 고치는 편이 좋습니다."), "patches", Some(i));
        }
        let o = Obj::new();
        o.set("target", target.clone());
        if js::truthy(&p.get("hide")) { o.set("hide", true); }
        let set = Obj::new();
        let warn = |n: &mut Norm, msg: String| n.warn(msg, "patches", Some(i));
        // 배치용 연도(startHint · endHint): 패치에서는 "미정" + 숫자(startUnknown: true + start) 꼴로 옮겨 읽는다
        let set_raw = p.get("set");
        let src = read::assign_copy(&if js::truthy(&set_raw) && js::type_of(&set_raw) == "object" { set_raw } else { V::Obj(Obj::new()) });
        for k in ["start", "end"] {
            let hk = format!("{k}Hint");
            if !src.has(&hk) { continue; }
            let h = dates::to_year(ctx, &src.get(&hk));
            src.delete(&hk);
            let Some(h) = h else { continue };
            if !dates::is_unknown_text(&src.get(k)) && !matches!(src.get(&format!("{k}Unknown")), V::Bool(true)) {
                warn(n, format!("{label}: {k}Hint(배치용 연도)는 {}이 \"미정\"일 때만 써서 무시했습니다.", if k == "start" { "시작" } else { "끝" }));
            } else if h.is_nan() {
                warn(n, format!("{label}: {k}Hint(배치용 연도)를 읽을 수 없어 무시했습니다."));
            } else {
                src.set(k, h);
                src.set(&format!("{k}Unknown"), true);
                src.delete(&format!("{k}At"));
            }
        }
        for (k, v) in src.entries() {
            if !dates::patchable(&k.as_str()) {
                warn(n, format!("{label}: \"{k}\"은(는) 패치할 수 없어 무시했습니다."));
                continue;
            }
            set.set(&k, v);
        }
        for k in dates::DATE_KEYS {
            let at_k = format!("{k}At");
            let v = set.get(k);
            if v.is_nullish() || read::is_empty_str(&v) { set.delete(&at_k); continue; }
            if dates::is_unknown_text(&v) {
                let uk = format!("{k}Unknown");
                if dates::patchable(&uk) { set.set(&uk, true); } // "미정"을 받는 날짜 칸(시작 · 끝)만 — 그 밖의 칸은 값만 비운다
                set.delete(k);
                set.delete(&at_k);
                continue;
            }
            match dates::read_date(ctx, &v, &set.get(&at_k)) {
                Some(d) if !d.t.is_nan() => {
                    set.set(k, d.t);
                    set.set(&at_k, d.at.filter(|a| !a.is_empty()).map_or(V::Null, V::Str)); // 날짜 글이 없으면 null — 원래 항목의 날짜 글을 지운다
                }
                d => {
                    let why = d.and_then(|d| d.error).filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" {e}"));
                    warn(n, format!("{label}: {k} 연도를 읽을 수 없어 무시했습니다.{why}"));
                    set.delete(k);
                    set.delete(&at_k);
                }
            }
        }
        // 연대 폭 [이른, 늦은]도 날짜 글을 받는다(짝 칸 startRangeAt · endRangeAt는 없으면 null — 원래 항목의 글을 지움)
        for k in ["startRange", "endRange"] {
            let at_k = format!("{k}At");
            let v = set.get(k);
            if v.is_nullish() { set.delete(&at_k); continue; }
            let atv = set.get(&at_k);
            let at = |j: usize| match &atv { V::Arr(a) => a.get(j), _ => V::Undef };
            let ds: Vec<Option<dates::DateR>> = match &v { V::Arr(a) if a.len() == 2 => (0..2).map(|j| dates::read_date(ctx, &a.get(j), &at(j))).collect(), _ => Vec::new() };
            if ds.len() != 2 || ds.iter().any(|d| d.as_ref().is_none_or(|d| d.t.is_nan())) {
                warn(n, format!("{label}: {k}는 [이른 연도, 늦은 연도] 형식이어야 해서 무시했습니다."));
                set.delete(k);
                set.delete(&at_k);
                continue;
            }
            let ds: Vec<dates::DateR> = ds.into_iter().flatten().collect();
            let pair = if ds[0].t <= ds[1].t { [ds[0].clone(), ds[1].clone()] } else { [ds[1].clone(), ds[0].clone()] };
            set.set(k, read::arr_of(pair.iter().map(|d| V::Num(d.t)).collect()));
            let at_of = |d: &dates::DateR| d.at.clone().filter(|a| !a.is_empty());
            set.set(&at_k, if pair.iter().any(|d| at_of(d).is_some()) { read::arr_of(pair.iter().map(|d| at_of(d).map_or(V::Null, V::Str)).collect()) } else { V::Null });
        }
        // 다른 견해: 대상이 사건 · 시대인지 인물인지 파일만으로는 모르므로 가장 넓은 꼴(인물)로 읽고, 모델이 대상에 맞춰 거른다
        if let V::Arr(alts) = set.get("alternatives") {
            let list = alts.to_vec();
            let fig_like = ["birth", "death", "role", "service"].iter().any(|k| set.has(*k))
                || list.iter().any(|a| js::truthy(a) && js::type_of(a) == "object" && (!a.get("birth").is_nullish() || !a.get("death").is_nullish()));
            if !fig_like {
                for (k, a) in list.iter().enumerate() {
                    if !js::truthy(a) || !read::is_plain(a) || dates::read_date(ctx, &a.get("start"), &a.get("startAt")).is_some() { continue; }
                    let end = a.get("end");
                    if (!end.is_nullish() && !js::to_str(&end).trim().is_empty()) || matches!(a.get("ongoing"), V::Bool(true)) {
                        warn(n, format!("{label}: 이설 #{}에 시작이 없어, 고치는 대상이 사건 · 시대면 쓰이지 않습니다(인물이면 활동 끝의 이설로 읽습니다 — 근거만 적으려면 날짜를 모두 비웁니다).", k + 1));
                    }
                }
            }
            let mut msgs = Vec::new();
            let read_alts = cells::read_alternatives(ctx, &V::Arr(alts), "figure", Some(&mut |m: String| msgs.push(m)), None);
            n.warn_all(msgs, &format!("{label}: "), "patches", i);
            set.set("alternatives", read::arr_of(read_alts));
        }
        for (k, what) in [("leaders", "지도자"), ("reigns", "지도자"), ("cabinets", "내각"), ("eras", "연호")] {
            let v = set.get(k);
            if matches!(v, V::Arr(_)) { let cells_out = n.read_cells(&v, &label, "patches", i, what); set.set(k, read::arr_of(cells_out)); }
        }
        if matches!(set.get("capitals"), V::Arr(_)) { let caps = n.read_capitals(&set.get("capitals"), &label, "patches", i); set.set("capitals", read::arr_of(caps)); }
        if !set.get("service").is_nullish() { let sv = n.read_service(&set.get("service"), &label, "patches", i); set.set("service", read::arr_of(sv)); } // 인물의 섬긴 기록
        for k in ["aka", "figures"] {
            if !set.get(k).is_nullish() { set.set(k, read::arr_of(name_list(&set.get(k)).into_iter().map(V::Str).collect())); }
        }
        if !set.get("spot").is_nullish() {
            match misc::read_spot(&set.get("spot")) { // 사건의 자리 — null이면 원래 항목의 자리를 지워 가운데로
                None => { warn(n, format!("{label}: 자리(spot)는 0~1이어야 해서 무시했습니다.")); set.delete("spot"); }
                Some(v) => set.set("spot", v),
            }
        }
        // 형식 버전 3: 이름 목록 · 장소 · 부모 · 배우자도 파일과 같은 읽기로(null이면 대상의 것을 비움 — 빈 목록 []도)
        let prefix = format!("{label}: ");
        if !set.get("names").is_nullish() {
            let mut msgs = Vec::new();
            let list = names::read_names(ctx, &set.get("names"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("names", read::arr_of(list));
        }
        if !set.get("place").is_nullish() { let pl = s(&set.get("place")); set.set("place", if pl.is_empty() { V::Null } else { V::Str(pl) }); }
        if !set.get("parents").is_nullish() {
            let mut msgs = Vec::new();
            let list = names::read_parents(ctx, &set.get("parents"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("parents", read::arr_of(list));
        }
        // 계보 전용 · 형제 순서(D1): 계보 전용은 참 · 거짓(null은 대상의 것을 지움), 형제 순서는 정수(null은 지움)
        let lo = set.get("lineageOnly");
        if set.has("lineageOnly") && !lo.is_nullish() && !matches!(lo, V::Bool(_)) {
            warn(n, format!("{prefix}계보 전용(lineageOnly)은 true · false로 적습니다 — \"{}\"은(는) 무시했습니다.", s(&lo)));
            set.delete("lineageOnly");
        }
        let order = set.get("order");
        if set.has("order") && !order.is_nullish() && !read::is_empty_str(&order) {
            let num = js::to_num(&order);
            if num.is_finite() && num == num.trunc() { set.set("order", num); }
            else {
                warn(n, format!("{prefix}형제 순서(order)는 정수로 적습니다 — \"{}\"은(는) 무시했습니다.", s(&order)));
                set.delete("order");
            }
        } else if read::is_empty_str(&order) { set.set("order", V::Null); }
        if !set.get("spouses").is_nullish() {
            let mut msgs = Vec::new();
            let list = names::read_spouses(ctx, &set.get("spouses"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("spouses", read::arr_of(list));
        }
        if set.has("northSouth") {
            // 남북 위치(형식 버전 3): 수 · 비우면(null · "") 대상의 값을 지움 — 읽지 못하면 그 칸만 버림
            match misc::read_north_south(&set.get("northSouth")) {
                None => set.set("northSouth", V::Null),
                Some(ns) if ns.is_finite() => set.set("northSouth", ns),
                Some(_) => { warn(n, format!("{prefix}남북 위치(northSouth)는 수여야 해서 그 칸을 버렸습니다.")); set.delete("northSouth"); }
            }
        }
        // 정권 종류 · 승계 종류도 시대와 같은 식으로 한국어를 읽어 id로 — 모르는 종류는 시대와 같은 경고(모델에서는 국가)
        if !s(&set.get("kind")).is_empty() {
            let id = vocab::polity_kind_id(&set.get("kind"));
            let kind = if id.is_empty() { s(&set.get("kind")) } else { id };
            set.set("kind", kind.clone());
            if !vocab::is_any_kind(&kind.as_str()) { warn(n, format!("{label}: 정권 종류 \"{kind}\"을(를) 알 수 없어 국가로 봅니다.")); }
        }
        if !set.get("succeeds").is_nullish() { let sc = n.read_succ_list(&set.get("succeeds"), &label, "patches", i); set.set("succeeds", read::arr_of(sc)); }
        if !set.get("partOf").is_nullish() { n.check_part_of(&set.get("partOf"), &label, "patches", i); } // 소속 관계 · 놓는 자리는 모델이 시대와 같은 규칙으로 읽는다
        // 시기 구분 · 지위 변천: 빈 목록([])은 "대상의 것을 비움". 목록이 아니거나 적은 것이 모두 읽히지 않아 비었으면 그 칸을 정말 무시한다(알림과 결과가 같게)
        for (k, what) in [("phases", "시기 구분"), ("ranks", "지위 변천"), ("faiths", "종교 변천")] { // 종교: 6단계 D8
            if !set.has(k) { continue; }
            let v = set.get(k);
            if v.is_nullish() || read::is_empty_str(&v) {
                warn(n, format!("{label}: {what}은 목록이어야 해서 무시했습니다 (대상의 것은 그대로 둡니다 — 비우려면 빈 목록 [])."));
                set.delete(k);
                continue;
            }
            let (list, problems, warnings) = if k == "phases" { let r = cells::read_phases(ctx, &v); (r.list, r.problems, r.warnings) } else if k == "ranks" { let r = cells::read_ranks(ctx, &v); (r.list, r.problems, r.warnings) } else { let r = cells::read_faiths(ctx, &v); (r.list, r.problems, r.warnings) };
            for msg in problems.iter().chain(warnings.iter()) { warn(n, format!("{label}: {msg}")); }
            let emptied = matches!(&v, V::Arr(a) if a.is_empty());
            if !list.is_empty() || emptied { set.set(k, read::arr_of(list)); }
            else {
                let listy = if k == "phases" { js::type_of(&v) == "object" } else { matches!(v, V::Arr(_)) };
                if listy { warn(n, format!("{label}: {what}에 읽을 수 있는 것이 없어 무시했습니다 (대상의 {what}은 그대로 둡니다).")); }
                set.delete(k);
            }
        }
        if set.has("treaty") {
            // 조약 규격(비었으면 null — 조약을 뗌)
            let mut msgs = Vec::new();
            let tr = treaty::read_treaty(ctx, &set.get("treaty"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("treaty", tr.map_or(V::Null, V::Obj));
        }
        // 형식 버전 3: 사건의 주제 꼬리표 · 법 · 선거 규격과 단체 · 제도의 칸 — 파일과 같은 읽기로(규격이 비었으면 null — 그 규격을 뗌)
        let theme = set.get("theme");
        if !theme.is_nullish() {
            set.set("theme", if matches!(theme, V::Arr(_)) { read::arr_of(groups::read_theme_list(&theme).into_iter().map(V::Str).collect()) } else { V::Str(s(&theme)) });
        }
        if set.has("law") {
            let mut msgs = Vec::new();
            let law = groups::read_law(&set.get("law"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("law", law.map_or(V::Null, V::Obj));
        }
        if set.has("election") {
            let mut msgs = Vec::new();
            let el = groups::read_election(&set.get("election"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("election", el.map_or(V::Null, V::Obj));
        }
        if !set.get("type").is_nullish() {
            let ty = groups::group_type(&set.get("type"));
            set.set("type", if ty.is_empty() { s(&set.get("type")) } else { ty });
        }
        if !set.get("within").is_nullish() {
            let mut msgs = Vec::new();
            let w = groups::read_polity_rows(ctx, &set.get("within"), false, &mut |m| msgs.push(m), "있던 나라");
            n.warn_all(msgs, &format!("{label}: 있던 나라 "), "patches", i);
            set.set("within", if w.is_empty() { V::Null } else { groups::compact_polity_rows(w) });
        }
        if !set.get("from").is_nullish() {
            let mut msgs = Vec::new();
            let f = groups::read_group_from(&set.get("from"), &mut |m| msgs.push(m));
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("from", read::arr_of(f));
        }
        if matches!(set.get("power"), V::Arr(_)) { let pw = n.read_cells(&set.get("power"), &label, "patches", i, "집권"); set.set("power", read::arr_of(pw)); }
        if !set.get("members").is_nullish() {
            let mut msgs = Vec::new();
            let m = groups::read_polity_rows(ctx, &set.get("members"), true, &mut |m| msgs.push(m), "구성 나라");
            n.warn_all(msgs, &format!("{label}: 구성 나라 "), "patches", i);
            set.set("members", read::arr_of(m));
        }
        if matches!(set.get("people"), V::Arr(_)) {
            let mut msgs = Vec::new();
            let pp = names::read_group_people(ctx, &set.get("people"), &mut |m| msgs.push(m)); // 단체의 구성원 — 사람 참조 목록
            n.warn_all(msgs, &prefix, "patches", i);
            set.set("people", read::arr_of(pp));
        }
        for k in ["family", "event"] {
            if !set.get(k).is_nullish() { set.set(k, s(&set.get(k))); }
        }
        if !set.get("spans").is_nullish() {
            let sp = groups::read_inst_spans(ctx, &set.get("spans"));
            for msg in sp.problems.iter().chain(sp.warnings.iter()) { warn(n, format!("{label}: {msg}")); }
            if !sp.list.is_empty() { set.set("spans", read::arr_of(sp.list)); }
            else {
                warn(n, format!("{label}: 제도 칸(spans)에 읽을 수 있는 칸이 없어 무시했습니다 (대상의 칸은 그대로 둡니다)."));
                set.delete("spans");
            }
        }
        // 실재성: 한국어도 id로, 비우거나 실재면 null(원래 항목의 실재성을 지움)
        if set.has("historicity") {
            let hv = set.get("historicity");
            let hs = vocab::historicity(&hv);
            if hs.is_empty() && !s(&hv).is_empty() {
                warn(n, format!("{label}: 실재성 \"{}\"을(를) 알 수 없어 무시했습니다.", s(&hv)));
                set.delete("historicity");
            } else { set.set("historicity", if !hs.is_empty() && hs != "attested" { V::Str(hs) } else { V::Null }); }
        }
        if !set.is_empty() { o.set("set", set); }
        if !o.bool("hide") && !o.has("set") { n.err(format!("{label}: 바꿀 내용이 없습니다."), "patches", Some(i)); continue; }
        let note = s(&p.get("note"));
        if !note.is_empty() { o.set("note", note); }
        list_of(pack, "patches").push(V::Obj(o));
    }
}

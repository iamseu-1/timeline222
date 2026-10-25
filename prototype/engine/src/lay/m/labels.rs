//! 내보내기 모듈 `labels` — `prototype/scripts/export/labels.mjs`(1 ~ 134줄 · SHA-256 앞 12자 `0cc7aaddc105` — 저장소의 LF 바이트)를 줄 그대로 옮긴다(한 벌 P3 갈래 B · 앞자리 11).
//! 왼쪽 줄 이름 — 지금 화면 가운데 시기의 정권. 띠마다 `out.rowLabels`에 싣는다(새로 만든다 — 앞의 것은 버림). 고르는 규칙 · 줄이는 차례 · 부제의 구성은 계약 6절에 글로.
//! 읽는 shared: `catNo`(없으면 빈 Map). 모듈의 `bandStart` · `bandEnd`는 `lay::rows`의 것.
//! 함께 옮긴 웹 함수 — `js/core.js`(SHA-256 앞 12자 `9c786cf58566`):
//! - 3225 ~ 3228줄 `HT.yearOf`(→ `read::dates::year_of` — JS 값 그대로 받는 하나)
//! 부르는 웹 함수: `HT.GLYPH_BAND` · `HT.glyphMissing`(→ [`crate::lay::web::glyphs`] — 과제 Y가 모음 · 처음 옮긴 판은 이 파일에 있었다).
use crate::lay::web::glyphs::{glyph_band, glyph_missing};
use super::kit::minute_val;
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_mut, color as rgb};
use crate::lay::js::{self, Arr, Map, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, eq, is, le, list, lt, n, or, tv};
use crate::lay::read::dates::year_of;
use crate::lay::rows::{band_end, band_start, items};
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

// ── labels.mjs ──

/// 줄 이름 칸의 짧은 연도 글 — shortYears 그대로.
fn short_years(p: &V) -> String {
    let s = year_of(&p.get("start"));
    let e = if p.bool("ongoing") { None } else { Some(year_of(&p.get("endY"))) };
    let ns = js::num_str;
    let Some(e) = e else { return if s < 0.0 { format!("BC {}–", ns(-s)) } else { format!("{}–", ns(s)) } };
    if s < 0.0 && e < 0.0 { return format!("BC {}–{}", ns(-s), ns(-e)); }
    if s < 0.0 { return format!("BC {}–{}", ns(-s), ns(e)); }
    format!("{}–{}", ns(s), ns(e))
}

/// 왼쪽 줄 이름 칸에 함께 적을 원어의 후보(10건 3 · 감독 결정 D2-2 "맨 왼쪽 구분표에서만 원어" · 4 B — 갈래 D2 · 웹 HT.bandOrig):
/// [첫 원어, 첫 로마자] 차례의 `{text, mb?}` — mb = 내장 띠 표(HT.GLYPH_BAND)에 없는 글자의 코드 포인트(비면 싣지 않음).
/// 첫 원어를 내장 띠 표로 그릴 수 있으면 로마자는 쓸 일이 없어 싣지 않는다. 이름 목록이 없는 띠는 열쇠째 없다(옛 자료는 바이트까지 그대로).
fn orig_of(p: &V, band: &[(u32, u32)]) -> Option<V> {
    let V::Arr(names) = p.get("names") else { return None };
    let all: Vec<V> = names.to_vec().into_iter().filter(|x| tv(x) && x.bool("text")).collect();
    let native = all.iter().find(|x| is(&x.get("kind"), "native")).cloned();
    let roman = all.iter().find(|x| is(&x.get("kind"), "roman")).cloned();
    let mut out: Vec<V> = Vec::new();
    for x in [native, roman].into_iter().flatten() {
        let o = o! { "text" => x.get("text") };
        let mb = glyph_missing(&x.get("text"), band);
        if !mb.is_empty() { o.set("mb", arr(mb.iter().map(|c| V::Num(f64::from(*c))).collect())); }
        out.push(V::Obj(o));
        if mb.is_empty() { break; } // 내장 표로 그릴 수 있는 후보 뒤는 쓸 일이 없다
    }
    if out.is_empty() { None } else { Some(arr(out)) }
}

/// 줄의 종류: 0 정권 줄 · 1 그 밖 줄(공통) · 2 접힌 민족 줄.
struct Kind { band: f64, common: f64, folded: f64 }
const KIND: Kind = Kind { band: 0.0, common: 1.0, folded: 2.0 };

/// 민족 딱지(`.tl-pchip` — 지금 연표의 `_rowPeopleChip` 3159): 줄 r의 정권 민족이 그 줄을 덮은 민족 묶음과 다르면
/// `{id, name, color, scope, all}`, 같거나 민족이 없으면 null. 접힌 줄 · 트랙 공통 줄은 묻지 않는다. 딱지는 줄마다 하나라 그 줄의 후보 띠마다 같은 값을 싣는다(계약 6-8절).
fn row_chip(tr: &V, r: f64, folded: bool) -> Option<V> {
    let rv = V::Num(r);
    if !tr.bool("rowPeriods") || folded || eq(&rv, &tr.get("commonRow")) { return None; } // folded = tr.foldedRows.has(r)(부르는 쪽이 kit::has_or_err로 셈)
    let l: Vec<V> = items(&tr.get("rowPeriods").get(&r)).into_iter().filter(|p| p.bool("peopleId") && !p.bool("_hidden")).collect();
    if l.is_empty() { return None; }
    let mut cover: Option<V> = None;
    for gp in items(&tr.get("groups")) {
        let inside = gp.bool("name") && !gp.bool("culture") && le(&gp.get("first"), &rv) && lt(&rv, &js::add(&gp.get("first"), &gp.get("count")));
        if inside && (match &cover { None => true, Some(c) => gp.bool("scope") || (!c.bool("scope") && lt(&c.get("depth"), &gp.get("depth"))) }) { cover = Some(gp.clone()); }
    }
    let own = Map::new(); // 묶음과 다른 민족 → 그 민족 정권들의 기간 합
    for p in &l {
        if cover.as_ref().map_or(true, |c| !eq(&p.get("peopleId"), &c.get("key"))) {
            let sum = n(&js::add(&or(own.get(&p.get("peopleId")), V::Num(0.0)), &band_end(p))) - n(&band_start(p));
            own.set(p.get("peopleId"), sum);
        }
    }
    if own.is_empty() { return None; }
    let mut entries = own.entries();
    js::sort_by(&mut entries, |a, b| n(&b.1) - n(&a.1));
    let id = entries[0].0.clone();
    let p = l.iter().find(|q| eq(&q.get("peopleId"), &id)).cloned().unwrap_or(V::Undef);
    let all: Vec<V> = own.keys().iter().map(|k| {
        let hit = l.iter().find(|q| eq(&q.get("peopleId"), k));
        or(hit.map_or(V::Undef, |q| q.get("peopleName")), k.clone())
    }).collect();
    Some(V::Obj(o! {
        "id" => id.clone(), "name" => or(p.get("peopleName"), id), "color" => f64::from(rgb(&or(p.get("peopleColor"), tr.get("color")), 0xa4b1b7)),
        "scope" => if cover.as_ref().is_some_and(|c| c.bool("scope")) { 1.0 } else { 0.0 },
        "all" => arr(all),
    }))
}

/// `contribute(ctx, out)` — `out.rowLabels`를 새로 만든다.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let cats = { let c = ctx.shared.get("catNo"); if tv(&c) { c } else { V::Map(Map::new()) } };
    let V::Map(cats) = cats else { return Err("shared.catNo가 Map이 아닙니다 — JS라면 .has에서 멈춤".into()) };
    let band = glyph_band();
    let mut rows: Vec<Value> = Vec::new();
    let (mut c_band, mut c_common, mut c_folded, mut c_foldable, mut c_metro, mut c_member, mut c_chip, mut c_orig) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    for (track, tr) in list(&tl.get("tracks")).iter().enumerate() {
        let track = track as f64;
        // JS는 `tr.foldedRows.has(row)`를 공통 줄이 아닌 첫 줄에서야 부른다 — 그때 Set이 아니면 오류(트랙 머리가 아니라 · 과제 Y — 갈래 B 검토 Minor)
        let folded_v = tr.get("foldedRows");
        let row_periods = tr.get("rowPeriods");
        let mut row = 0.0;
        while row < n(&tr.get("rows")) {
            let rv = V::Num(row);
            if eq(&rv, &tr.get("commonRow")) {
                rows.push(js::to_json(&V::Obj(o! { "period" => "", "track" => track, "row" => row, "kind" => KIND.common, "name" => "그 밖", "years" => "", "color" => f64::from(rgb(&V::from("#9c978d"), 0xa4b1b7)), "cap" => 0.0, "member" => 0.0, "lanes" => arr(Vec::new()) })));
                c_common += 1.0;
                row += 1.0;
                continue;
            }
            // JS `tr.foldedRows.has(row)` — Set · Map이면 그 답(kit::has_or_err — power와 같은 판단 · 16b), 그 밖이면 여기서 멈춤
            let folded = super::kit::has_or_err(&folded_v, &rv, "tr.foldedRows")?;
            if folded {
                let gp = items(&tr.get("groups")).into_iter().find(|x| eq(&x.get("first"), &rv) && x.bool("folded"));
                let o = o! {
                    "period" => "", "track" => track, "row" => row, "kind" => KIND.folded, "name" => gp.as_ref().map_or(V::from(""), |g| g.get("name")), "years" => "",
                    "depth" => gp.as_ref().map_or(V::Num(0.0), |g| g.get("depth")), "group" => gp.as_ref().map_or(V::from(""), |g| g.get("key")),
                    "color" => f64::from(rgb(&gp.as_ref().map_or(tr.get("color"), |g| g.get("color")), 0xa4b1b7)), "cap" => 0.0, "member" => 0.0, "lanes" => arr(Vec::new()),
                    "count" => n(&or(row_periods.get(&row), arr(Vec::new())).get("length")),
                };
                rows.push(js::to_json(&V::Obj(o)));
                c_folded += 1.0;
                row += 1.0;
                continue;
            }
            let rc = tr.get("rowCats");
            let lanes: Vec<V> = items(&if tv(&rc) { rc.get(&row) } else { rc }).iter().map(|id| if cats.has(id) { cats.get(id) } else { V::Num(255.0) }).collect();
            let lanes = V::Arr(Arr::new(lanes));
            // 민족 딱지는 줄마다 하나다 — 그 줄의 후보마다 같은 값을 실어, 어느 띠의 이름을 보이든 딱지가 그려지게 한다.
            let chip = row_chip(tr, row, folded);
            if chip.is_some() { c_chip += 1.0; }
            // 그 줄의 후보 정권마다 하나 — 어느 것을 쓸지는 보는 시기(at)를 아는 그리는 쪽이 고른다(계약 6절의 고르는 규칙).
            for p in items(&row_periods.get(&row)) {
                if p.bool("_overlay") || p.bool("_under") || p.bool("_hidden") { continue; }
                let in_member = super::kit::has_or_err(&tr.get("memberRows"), &rv, "tr.memberRows")?;
                let orig = orig_of(&p, &band);
                if orig.is_some() { c_orig += 1.0; }
                let caps = p.get("capitals");
                let has_cap = tv(&caps) && tv(&caps.get("length"));
                let o = o! {
                    "period" => p.get("uid"), "track" => track, "row" => row, "kind" => KIND.band,
                    "name" => or(p.get("name"), V::from("")), "years" => short_years(&p), "color" => f64::from(rgb(&p.get("color"), 0xa4b1b7)),
                    "start" => minute_val(&p.get("start")), "end" => js::max(&[n(&minute_val(&p.get("start"))), n(&minute_val(&p.get("endY")))]),
                    "cap" => if has_cap { 1.0 } else { 0.0 },
                    "member" => if in_member { 1.0 } else { 0.0 },
                    "lanes" => lanes.clone(),
                };
                if let Some(c) = &chip { o.set("chip", c.clone()); }
                if let Some(x) = &orig { o.set("orig", x.clone()); }
                rows.push(js::to_json(&V::Obj(o)));
                c_band += 1.0;
                if has_cap { c_metro += 1.0; }
                if in_member { c_member += 1.0; }
            }
            row += 1.0;
        }
        // 민족을 접으면 그 묶음의 줄들이 한 줄로 합쳐진다 — 그때 보일 이름을 **미리** 싣는다(명세 05의 8.1절 4번). 묶음의 첫 줄에 `kind 2` 후보 하나를 얹고,
        // 한 줄에 여러 단계의 묶음이 겹칠 수 있으므로 `depth`로 가른다. **대범위 가지**(`gp.key`가 `__scope:<uid>`)는 묶음 이름(`group`)으로 가른다.
        for gp in items(&tr.get("groups")) {
            if !gp.bool("name") || gp.bool("folded") { continue; } // 이미 접힌 묶음은 위에서 실었다
            let mut cnt = 0.0;
            let mut r = gp.get("first");
            while lt(&r, &js::add(&gp.get("first"), &gp.get("count"))) {
                for p in items(&row_periods.get(&n(&r))) { if !p.bool("_hidden") { cnt += 1.0; } }
                r = V::Num(n(&r) + 1.0); // r++ (수로)
            }
            rows.push(js::to_json(&V::Obj(o! {
                "period" => "", "track" => track, "row" => gp.get("first"), "kind" => KIND.folded, "name" => gp.get("name"), "years" => "", "depth" => gp.get("depth"), "group" => gp.get("key"),
                "color" => f64::from(rgb(&gp.get("color"), 0xa4b1b7)), "cap" => 0.0, "member" => 0.0, "lanes" => arr(Vec::new()), "count" => cnt,
            })));
            c_foldable += 1.0;
        }
    }
    *arr_mut(out, "rowLabels") = rows;
    ctx.notes.set("줄이름", o! { "띠" => c_band, "그밖줄" => c_common, "접힌줄" => c_folded, "접힐줄" => c_foldable, "노선도" => c_metro, "소속줄" => c_member, "민족딱지" => c_chip, "원어" => c_orig });
    Ok(())
}

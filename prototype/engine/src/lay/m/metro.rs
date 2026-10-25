//! 내보내기 모듈 `metro` — `prototype/scripts/export/metro.mjs` 1 ~ 136줄(SHA-256 앞 12자 `905bf758b0b5` · 138 ~ 154줄 '혼자 돌려 보기'는 노드 전용이라 뺌)을 줄 그대로 —
//! 한 벌 P3 과제 15 몫(갈래 C · 앞자리 19/20). `contribute`는 빈손이고, 늦은 차례가 `out.entities`의 정권 기록(`kind: "period"`) `json`에 `x_metro`(도읍 노선도 카드가
//! 읽는 환승 · 다른 정권 단추 · 날짜 글)를 얹는다 — docs의 `x_docs` 뒤 · power 뒤(`js::parse` → 열쇠 더함 → `js::stringify`: JS 열쇠 차례 · 판정 R24 ②).
//! 부르는 웹 함수: 날짜 글(`HT.formatRange` · `formatWhen` · `formatDate` · `cal.describe` · `HT.altText` — [`crate::lay::web::when`]) · `HT.cellToNow`(`web::cells`) ·
//! `HT.yearOf`(JS 값 그대로 — `read::dates::year_of`). 과제 Y가 모음: 처음엔 docs의 `docs/when.rs`를 `#[path]`로 한 번 더 실어 두 벌로 컴파일했고, `HT.yearOf`는
//! 해를 먼저 수로 바꾸는 제 사본이었다(글로 온 해에서만 JS `y + 1e-9`의 글 잇기와 갈림). 읽는 것: `tl._cityUses`(도시 → [{p, c}] — 과제 6) · `tl.tracks[].periods`(줄을 쌓은 뒤의 차례) · `model.periods`.
//! JS의 `xfer[c.city]`가 `Object.prototype`의 이름(`constructor` …)을 '있음'으로 읽는 곳은 그 뜻대로([`crate::lay::web::words::inherited`] — docs와 하나).
use super::kit::some;
use crate::lay::ctx::Ctx;
use crate::lay::js::{self, Arr, Map, Obj, V};
use crate::lay::model::o;
use crate::lay::model::util::{t, tv};
use crate::lay::read::{dates::year_of, Ctx as RCtx};
use crate::lay::web::cells::cell_to_now;
use crate::lay::web::when;
use crate::lay::web::words::inherited;
use serde_json::Value;

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 34줄 `XFER_MAX` — 한 도시를 쓴 다른 정권을 이만큼까지만 싣는다.
const XFER_MAX: usize = 12;

fn or_empty(v: V) -> V { js::or(v, V::from("")) }
/// 39줄 `bcYear(y)` — 역 이름 아래의 해("BC 960" · "1394").
fn bc_year(y: &V) -> String {
    if js::to_num(y) < 0.0 { format!("BC {}", js::num_str(-year_of(y))) } else { js::num_str(year_of(y)) }
}
/// 41 ~ 48줄 `cellRange(c, p)` — 역 설명글의 기간(`js/timeline.js`의 `cellRange(c, 'endY', null, p)`).
fn cell_range(rc: &RCtx, c: &V, p: &V) -> String {
    let s = if c.bool("startUnknown") { "미정".to_string() } else { when::format_when(rc, c, "start") };
    if c.bool("endUnknown") || c.bool("endYAuto") { return format!("{s} ~ 미정"); }
    if c.bool("toNow") || cell_to_now(c, p) { return format!("{s} ~ 현재"); }
    let ev = js::nullish(c.get("endY"), V::Null);
    if ev.is_nullish() { return format!("{s} ~"); }
    format!("{s} ~ {}", when::format_date(rc, &ev, &js::or(c.get("endYAt"), c.get("endAt"))))
}
/// 50 ~ 53줄 `cellAlts(c)` — 다른 견해의 글(앞의 '다른 견해 — '는 카드가 붙임).
fn cell_alts(rc: &RCtx, c: &V) -> Vec<V> {
    let list = if tv(c) { c.get("alternatives") } else { V::Undef };
    let base = V::Obj(o! {
        "start" => c.get("start"), "startAt" => c.get("startAt"), "end" => js::nullish(c.get("endY"), c.get("end")), "endAt" => js::or(c.get("endYAt"), c.get("endAt")),
        "startUnknown" => c.get("startUnknown"), "endUnknown" => c.get("endUnknown"),
    });
    crate::lay::model::util::list(&js::or(list, V::Arr(Arr::new(Vec::new())))).iter().map(|a| when::alt_text(rc, a, &base)).collect()
}

/// 61 ~ 98줄 `metroOf(HT, p, cityUses, peersOf)` — 정권 하나의 `x_metro`(도읍이 없으면 None).
pub fn metro_of(rc: &RCtx, p: &V, city_uses: &Map, peers_of: &Map) -> Option<V> {
    let caps = crate::lay::model::util::list(&js::or(p.get("capitals"), V::Arr(Arr::new(Vec::new()))));
    if caps.is_empty() { return None; }
    let when: Vec<V> = caps.iter().map(|c| V::from(cell_range(rc, c, p))).collect();
    let alts = Obj::new();
    for (i, c) in caps.iter().enumerate() {
        let list = cell_alts(rc, c);
        if !list.is_empty() { alts.set(&(i as f64), V::Arr(Arr::new(list))); }
    }
    let xfer = Obj::new();
    for c in &caps {
        let city = c.get("city");
        let key = t(&city);
        if !tv(&city) || tv(&xfer.get(key.as_str())) || (!xfer.has(key.as_str()) && inherited(&key)) { continue; }
        let uses = city_uses.get(&city);
        let others: Vec<V> = crate::lay::model::util::list(&js::or(uses, V::Arr(Arr::new(Vec::new())))).into_iter().filter(|u| !js::strict_eq(&u.get("p"), p)).collect();
        if others.is_empty() { continue; }
        let list: Vec<V> = others.iter().take(XFER_MAX).map(|u| {
            let (q, uc) = (u.get("p"), u.get("c"));
            V::Obj(o! {
                "uid" => q.get("uid"), "name" => or_empty(q.get("name")), "color" => or_empty(q.get("color")),
                "cell" => or_empty(js::or(uc.get("name"), uc.get("city"))), "year" => if uc.bool("startUnknown") { "미정".to_string() } else { bc_year(&uc.get("start")) },
            })
        }).collect();
        // 잘렸으면 '외 n'이 지금 연표와 같은 수가 되게 전체 수를 함께 싣는다(첫 칸에만 적는다).
        if others.len() > list.len() { if let V::Obj(first) = &list[0] { first.set("all", others.len()); } }
        xfer.set(key.as_str(), V::Arr(Arr::new(list)));
    }
    let peers: Vec<V> = crate::lay::model::util::list(&js::or(peers_of.get(&p.get("track")), V::Arr(Arr::new(Vec::new())))).iter()
        .map(|q| V::Obj(o! { "uid" => q.get("uid"), "name" => or_empty(q.get("name")), "color" => or_empty(q.get("color")) })).collect();
    let out = o! { "range" => when::format_range(rc, p), "end" => bc_year(&p.get("endY")), "when" => V::Arr(Arr::new(when)) };
    if p.bool("ongoing") { out.set("ongoing", 1.0); }
    if tv(&some(&V::Obj(alts.clone()))) { out.set("alts", V::Obj(alts)); }
    if tv(&some(&V::Obj(xfer.clone()))) { out.set("xfer", V::Obj(xfer)); }
    if peers.len() > 1 { out.set("peers", V::Arr(Arr::new(peers))); } // 하나뿐이면 발에 단추가 서지 않는다
    Some(V::Obj(out))
}

/// 102 ~ 111줄 `indexes(ctx)` — 도시 → 쓰임(`tl._cityUses`) · 트랙 → 도읍이 있는 정권(줄을 쌓은 뒤의 `tr.periods` 차례).
fn indexes(ctx: &Ctx) -> (Map, Map) {
    let tl = &ctx.tl;
    let city_uses = match (tv(tl), tl.get("_cityUses")) { (true, V::Map(m)) => m, _ => Map::new() };
    let peers_of = Map::new();
    for tr in crate::lay::model::util::list(&tl.get("tracks")) {
        let list: Vec<V> = crate::lay::model::util::list(&tr.get("periods")).into_iter().filter(|q| tv(&q.get("capitals")) && tv(&q.get("capitals").get("length"))).collect();
        if !list.is_empty() { peers_of.set(tr.get("id"), V::Arr(Arr::new(list))); }
    }
    (city_uses, peers_of)
}

/// 114 ~ 133줄 `contributeLate(ctx, out)` — 모든 모듈이 제 몫을 실은 뒤 남이 실은 정권 기록에 `x_metro`를 얹는다.
pub fn contribute_late(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let (city_uses, peers_of) = indexes(ctx);
    let by_uid = Map::new();
    for p in crate::lay::model::util::list(&ctx.model.get("periods")) { by_uid.set(p.get("uid"), p.clone()); }
    let (mut hit, mut xfers) = (0usize, 0usize);
    for e in crate::lay::export::arr_mut(out, "entities").iter_mut() {
        if e["kind"] != "period" { continue; }
        let p = by_uid.get(&js::from_json(&e["uid"]));
        if !tv(&p) { continue; }
        let Some(x) = metro_of(&ctx.read, &p, &city_uses, &peers_of) else { continue };
        let json = js::parse(e["json"].as_str().unwrap_or_default())?;
        let o = json.as_obj().cloned().ok_or("정권 기록의 json이 객체가 아닙니다")?;
        xfers += match x.get("xfer") { V::Obj(xo) => xo.len(), _ => 0 };
        o.set("x_metro", x);
        e["json"] = Value::from(js::stringify(&json));
        hit += 1;
    }
    ctx.notes.set("노선도", V::Obj(o! { "도읍_있는_정권" => hit, "환승_도시" => xfers }));
    super::kit::fault_check("metro")?; // 날짜 글(`cal.describe`)이 남긴 잘못 — JS라면 TypeError(과제 Y)
    if let Some(name) = ctx.read.cal.missed_of() { return Err(format!("노선도: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다").into()); }
    if let Some(name) = ctx.read.cal.absent_of() { return Err(format!("노선도: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다").into()); }
    Ok(())
}

/// 136줄 `contribute()` — 제 몫이 없다(늦은 차례에만 일한다).
pub fn contribute(_ctx: &mut Ctx, _out: &mut Value) -> crate::Result<()> { Ok(()) }

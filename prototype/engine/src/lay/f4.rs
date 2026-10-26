//! `HT.F4`의 읽기 몫 — 형식 4(객체 · 그릇 · 서고) 파일을 지금 읽기기가 읽는 옛 꼴(형식 3)로 내린다(`HT.F4.down`) — 한 벌 P3 과제 5a.
//! 형식 1 ~ 4를 모두 받는다(계획 정한 것 #6): 형식 4는 여기서 내린 뒤 옛 읽기기(`read::normalize_pack`)를 그대로 탄다.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `e139acd39619`(저장소의 LF 바이트 · 2026-10-24 main 합침 — 5-18 낱말 표가 앞에 들어 32줄 밀림 · 다리는 과제 6까지 그대로)
//! (2026-10-24 맞춤 · 리메이크 3단계 과제 1 · `core.js` `7c75434e37fa`) 5683 ~ 5698줄 `STATUSES` · `statusId` · `kindOfType`(정규화가 씀 · `typeOfKind`도 공개)
//! - 5474 ~ 5742줄 공용: `VERSION` · `UNKNOWN` · `LEADERS` · `CABINETS` · `TYPES`(열아홉) · `DISPLAYS` · `typeById` · `typeId` · `STATE_DEPENDENT` · `clone` · `list` · `omit` · `toPolity` · `refOf` · `noPeriod` · `nestFor` · `setNest`
//! - 5804 ~ 5870줄 `periodOf`(5단계 과제 3: 되살릴 수 없는 종류는 `type`으로 남김 · 과제 4: 셋째 직위 줄은 `offices` · 빌린 자리는 `leadersFrom`) · 5871 ~ 5953줄 `splitMoves` · 5954 ~ 5974줄 `organOf` · `groupOf`
//! - 6018 ~ 6195줄 `down`(사람 객체 → figures · trackOf의 고리 · officeFrom · yearCycles)
//! - (2026-10-24 맞춤 · 리메이크 6단계 걸음 1 · `core.js` `dfd5d5fa3fd9`) 6073 ~ 6252줄 `down` — 6240 ~ 6250줄 최상위 간지 줄 고르기(문화권 없는 줄만 · 육십갑자 전체 줄은 비운 것과 같음 — 결정 16)
//! - (2026-10-25 맞춤 · 리메이크 6단계 · `core.js` `33ac0f36a1c2`) 6044 ~ 6168줄 `splitMoves` — 6077 ~ 6083줄 그릇 밖의 토막(within이 기간을 다 덮지 않으면 앞 · 뒤를 그릇 없는 토막으로) · 6101줄 그 토막의 within 지움 · 6113 ~ 6121줄 토막의 실권 줄(남의 실권 over는 시작 해의 토막 하나에만 · 이름만인 줄은 토막마다 — 검토 고침) · 6143 ~ 6163줄 섬김 · 실권의 상대(partOf[].of · power[].over)를 그 줄의 시작 해가 든 토막으로 · 6235 ~ 6414줄 `down`
//! - (2026-10-25 remake-int2 합침 · `core.js` `e7c6715650cc`) 위 줄 범위 그대로(kin-resolve는 7212줄 뒤만 고침)
//! 2026-10-23 리메이크 5단계 과제 1(설계 3-11 · 형식 문서 '형식 4 더하기'): 사람 종류(열아홉째) · 사람 객체 → figures · 직위 줄 빌림(offices[].from) · 문화권별 주기(yearCycles → yearCycle 하나) ·
//! partOf.as 뺌 · within 고리 알림(경로로 셈)을 JS와 같은 줄만큼 더했다.
//! 옮기지 않은 것(쓰기 몫 — 브리프): `KIND_TYPE` · `typeOfKind` · `entryOf` · `toRef` · `folds` · `objectOf` · `organObject` · `groupObject` · `up` · `project`.
//! `HT.F4.split`(옮겨 앉기의 토막 내기)은 새 앱 내보내기에서만 참 — [`read::Ctx::split`](crate::lay::read::Ctx).
use crate::lay::js::{self, Arr, Obj, Str, V};
use crate::lay::read::{self, cells, vocab, Ctx};
use std::collections::HashMap;

/// `VERSION` — 형식 4.
pub const VERSION: f64 = 4.0;
/// `UNKNOWN` — 상대를 모르는 섬김(옛 '종속 kind만 적고 partOf 없음'을 담는 자리).
const UNKNOWN: &str = "미상";
/// 직위 줄의 이름 — 옛 leaders(첫 줄) · cabinets.
const LEADERS: &str = "지도자";
const CABINETS: &str = "내각";
/// `TYPES` — 종류 열여덟(id, 이름, 내릴 때의 옛 종류). 그룹(container · ruling …)은 읽기에 쓰지 않아 뺐다.
const TYPES: [(&str, &str, &str); 19] = [
    ("era", "시대", "era"), ("realm", "나라", "state"), ("union", "동군연합", "state"), ("league", "동맹", "org"),
    ("state", "국가", "state"), ("federation", "연방", "federation"), ("principality", "제후국", "fief"), ("city", "도시", "state"),
    ("government", "정부", "exile"), ("regime", "실권 정권", "org"), ("dependency", "속령", "prefecture"), ("warlord", "군벌", "warlord"),
    ("organization", "단체", "movement"), ("faith", "교단", "org"), ("order", "기사단", "org"), ("company", "회사", "org"),
    ("office", "직위", "org"), ("group", "집단", "client"),
    ("person", "사람", "state"), // 열아홉째(설계 3-11 ①) — 옛 인물(figures). 띠로 내리지 않으므로 kind는 쓰이지 않음
];
/// `DISPLAYS` — 그리는 자리.
const DISPLAYS: [&str; 3] = ["band", "inside", "mark"];
/// `typeOfKind(k)` — 옛 kind → type(설계 3-8 표 · KIND_TYPE — 없으면 국가). period_of가 '되살릴 수 없는 종류'를 가릴 때 · 정규화가 객체 종류를 지킬 때(5단계 과제 3) 쓴다.
pub fn type_of_kind(k: &V) -> &'static str {
    match k {
        V::Str(s) => match &*s.as_str() {
            "federation" => "federation", "warlord" => "warlord", "exile" => "government", "org" => "warlord", "movement" => "organization", "era" => "era",
            "fief" => "principality", "client" => "group", "prefecture" => "dependency", _ => "state",
        },
        _ => "state",
    }
}
/// `typeById.get(id).kind`.
fn type_kind(id: &V) -> Option<&'static str> { match id { V::Str(s) => TYPES.iter().find(|t| *s == t.0).map(|t| t.2), _ => None } }
/// `kindOfType(id)` — 종류 id → 내릴 때의 옛 종류(모르면 국가의 것 — state).
pub fn kind_of_type(id: &V) -> &'static str { type_kind(id).unwrap_or("state") }
/// `STATUSES` — 정통성(설계 3-5 · 3-11): id · 한국어 이름.
const STATUSES: [(&str, &str); 6] = [("legit", "정통"), ("rival", "대립"), ("joint", "공동"), ("regent", "섭정"), ("nominal", "명목"), ("claim", "주장")];
/// `statusId(v)` — 정통성 id · 한국어 이름 → id(모르면 '').
pub fn status_id(v: &V) -> Str {
    let s = js::to_str(&js::nullish(v.clone(), V::from(""))).trim();
    if s.is_empty() { return s; }
    STATUSES.iter().find(|t| s == t.0 || s == t.1).map_or(Str::default(), |t| Str::from(t.0))
}
/// `typeId(v)` — 종류 id · 한국어 이름 → 종류 id(모르면 '').
pub fn type_id(v: &V) -> Str {
    let s = js::to_str(&js::nullish(v.clone(), V::from(""))).trim();
    if s.is_empty() { return s; }
    TYPES.iter().find(|t| s == t.0 || s == t.1).map_or(Str::default(), |t| Str::from(t.0))
}
/// `STATE_DEPENDENT` — 국가 + 관계로 옮겨 가는 종속 kind.
const STATE_DEPENDENT: [&str; 10] = ["tributary", "dominion", "vassal", "protectorate", "satellite", "puppet", "mandate", "colony", "occupied", "frontier"];
fn state_dependent(v: &V) -> bool { matches!(v, V::Str(s) if STATE_DEPENDENT.iter().any(|k| s == k)) }

/// `clone(v)` — `JSON.parse(JSON.stringify(v ?? null))`.
fn clone(v: &V) -> crate::Result<V> {
    let v = js::nullish(v.clone(), V::Null);
    js::parse(&js::stringify(&v))
}
/// `list(v)` — 배열이면 그 배열(같은 것), 비었으면 빈 배열, 하나면 그것 하나의 배열.
fn list(v: &V) -> V {
    match v {
        V::Arr(_) => v.clone(),
        x if x.is_nullish() || read::is_empty_str(x) => read::arr_of(Vec::new()),
        x => read::arr_of(vec![x.clone()]),
    }
}
/// `list(v)`의 원소들(그때의 사본).
fn items(v: &V) -> Vec<V> { if let V::Arr(a) = list(v) { a.to_vec() } else { Vec::new() } }
/// `omit(o, keys)` — `Object.assign({}, o)`에서 keys를 지운 새 객체.
fn omit(o: &V, keys: &[&str]) -> Obj {
    let r = read::assign_copy(o);
    for k in keys { r.delete(*k); }
    r
}
/// `toPolity(w)` — 형식 4의 `{ of, … }` 줄 → 옛 `{ polity, … }` 줄.
fn to_polity(w: &V) -> V {
    let o = Obj::new();
    o.set("polity", w.get("of"));
    read::assign_into(&o, &V::Obj(omit(w, &["of"])));
    V::Obj(o)
}
/// `refOf(x)` — 형식 4의 그릇 · 섬김 줄 하나(글 하나 "이름"도 받음). of가 비면 None.
fn ref_of(x: &V) -> Option<V> {
    let o = match x {
        V::Str(_) => { let o = Obj::new(); o.set("of", x.clone()); o }
        v if js::truthy(v) && read::is_plain(v) => read::assign_copy(v),
        _ => return None,
    };
    let of = js::to_str(&js::nullish(o.get("of"), V::from(""))).trim();
    o.set("of", of.clone());
    if of.is_empty() { None } else { Some(V::Obj(o)) }
}
/// `list(v).map(refOf).filter(Boolean)`.
fn refs(v: &V) -> Vec<V> { items(v).iter().filter_map(ref_of).collect() }
/// `noPeriod(e)` — 기간이 없다.
fn no_period(e: &V) -> bool {
    e.get("start").is_nullish() && e.get("end").is_nullish() && !js::truthy(&e.get("startUnknown")) && !js::truthy(&e.get("endUnknown"))
}
/// `nestFor(n, e, folded)` — 옛 nest를 가장 짧게: 비운 nest의 뜻과 같으면 지우고(None), 다르면 true · false.
fn nest_for(n: usize, e: &V, folded: bool) -> Option<bool> {
    let rel = e.get("relation");
    let implied = n == 1 && no_period(e) && (!js::truthy(&rel) || matches!(&rel, V::Str(s) if *s == "member"));
    if folded { if implied { None } else { Some(true) } } else if implied { Some(false) } else { None }
}
/// `setNest(e, v)`.
fn set_nest(e: &Obj, v: Option<bool>) {
    match v { None => { e.delete("nest"); } Some(b) => e.set("nest", b) }
}

/// `periodOf(o, eraRef, warn)` — 객체 하나 → 옛 시대(정권). eraRef(w) = 이 within이 시대 그릇을 가리키는지(가리키면 소속이 아니라 대범위 구성원).
fn period_of(o: &V, era_ref: &dyn Fn(&V) -> bool, warn: &mut dyn FnMut(String)) -> V {
    let mut kind: V = if matches!(o.get("display"), V::Str(s) if s == "band") { V::from("era") }
        else { V::from(type_kind(&o.get("type")).unwrap_or("state")) };
    let p = omit(o, &["type", "display", "subtype", "within", "partOf", "offices"]);
    let mut rest = refs(&o.get("partOf"));
    let mut rows: Vec<(Obj, bool)> = Vec::new();
    for w in refs(&o.get("within")) {
        if era_ref(&w) { continue; }
        let i = rest.iter().position(|x| js::strict_eq(&x.get("of"), &w.get("of")) && no_period(x));
        let pe = i.map(|i| rest.remove(i));
        let e = Obj::new();
        e.set("polity", w.get("of"));
        read::assign_into(&e, &V::Obj(omit(&w, &["of"])));
        if let Some(pe) = pe { read::assign_into(&e, &V::Obj(omit(&pe, &["of"]))); }
        rows.push((e, true));
    }
    let name0 = js::to_str(&js::or(js::or(o.get("name"), o.get("id")), V::from("?")));
    for x in &rest {
        let as_ = x.get("as");
        if !as_.is_nullish() { // 어느 자격으로 섬겼나(as) — 두지 않기로 함(설계 3-11 ④)
            warn(format!("객체 \"{name0}\"의 섬김 \"{}\"에 적은 as(\"{}\")는 형식 4에 없는 칸이라 뺍니다 — 그 자격의 영지를 객체로 세우고 지도자 칸의 person으로 이으세요.", js::to_str(&x.get("of")), js::to_str(&as_)));
            if let V::Obj(xo) = x { xo.delete("as"); }
        }
        let rel = js::or(V::Str(vocab::relation_id(&x.get("relation"))), x.get("relation"));
        if matches!(x.get("of"), V::Str(s) if s == UNKNOWN) && matches!(o.get("type"), V::Str(s) if s == "state") && state_dependent(&rel) {
            kind = rel;
            continue;
        }
        let e = Obj::new();
        e.set("polity", x.get("of"));
        read::assign_into(&e, &V::Obj(omit(x, &["of"])));
        rows.push((e, false));
    }
    let n = rows.len();
    // 지금 화면은 상위 하나 · 기간 없음일 때만 접는다 — 기간 있는 · 여럿인 within은 알리고 소속(제 줄)으로(그릇의 배치는 2단계)
    let name = js::to_str(&js::or(js::or(o.get("name"), o.get("id")), V::from("?")));
    for (e, folded) in &rows {
        if *folded && (n > 1 || !no_period(&V::Obj(e.clone()))) {
            warn(format!("객체 \"{name}\"의 그릇 \"{}\"은(는) {} 지금 화면에서는 접지 않고 소속(제 줄)으로 그립니다(그릇의 배치는 2단계).",
                js::to_str(&e.get("polity")), if n > 1 { "그릇 · 섬김이 여럿이라" } else { "기간이 있어" }));
        }
    }
    let out: Vec<V> = rows.into_iter().map(|(e, folded)| {
        let raw_rel = e.get("relation");
        let rel = js::or(V::Str(vocab::relation_id(&raw_rel)), raw_rel);
        if js::truthy(&rel) { e.set("relation", rel); } else { e.delete("relation"); }
        let ev = V::Obj(e.clone());
        set_nest(&e, nest_for(n, &ev, folded && n == 1 && no_period(&ev)));
        V::Obj(e)
    }).collect();
    if !out.is_empty() { p.set("partOf", cells::compact_part_of(out)); }
    if !matches!(&kind, V::Str(s) if *s == "state") { p.set("kind", kind.clone()); }
    let type_ = js::to_str(&js::nullish(o.get("type"), V::from("state")));
    if type_.as_str() != "state" && type_of_kind(&kind) != type_.as_str() { p.set("type", V::Str(type_)); } // 옛 종류로 되살릴 수 없는 종류는 적어 둔다(5단계 과제 3)
    // 직위 줄 → 지도자 · 내각 칸(두 자리) + 셋째 줄부터는 offices(5단계 과제 4 — 정규화 · 메이커가 지킴)
    let offs: Vec<V> = items(&o.get("offices")).into_iter().filter(|f| js::truthy(f) && read::is_plain(f)).collect();
    let name_is = |f: &V, s: &str| matches!(f.get("name"), V::Str(t) if t == s);
    let lead = offs.iter().find(|f| name_is(f, LEADERS)).or_else(|| offs.iter().find(|f| !js::truthy(&f.get("name"))))
        .or_else(|| offs.iter().find(|f| !name_is(f, CABINETS))).cloned();
    let is_lead = |f: &V| lead.as_ref().is_some_and(|l| js::strict_eq(l, f));
    let cab = offs.iter().find(|f| !is_lead(f) && name_is(f, CABINETS)).or_else(|| offs.iter().find(|f| !is_lead(f))).cloned();
    // 빌린 줄(from) → 옛 자리의 빌림 { name?, from } (5단계 과제 4 — 칸은 위에서 복제됨)
    let borrow = |f: &V, word: &str| -> Option<V> {
        let from = f.get("from");
        if from.is_nullish() || read::is_empty_str(&from) { return None; }
        let b = Obj::new();
        if js::truthy(&f.get("name")) && !name_is(f, word) { b.set("name", f.get("name")); }
        b.set("from", from);
        Some(V::Obj(b))
    };
    if let Some(l) = &lead {
        if !items(&l.get("cells")).is_empty() { p.set("leaders", list(&l.get("cells"))); }
        if let Some(b) = borrow(l, LEADERS) { p.set("leadersFrom", b); }
    }
    if let Some(c) = &cab {
        if !items(&c.get("cells")).is_empty() { p.set("cabinets", list(&c.get("cells"))); }
        if let Some(b) = borrow(c, CABINETS) { p.set("cabinetsFrom", b); }
    }
    // 셋째 줄부터 — 정규화가 지키는 offices로(빌린 줄은 복제한 칸을 뺀다)
    let is_cab = |f: &V| cab.as_ref().is_some_and(|c| js::strict_eq(c, f));
    let more: Vec<V> = offs.iter().filter(|f| !is_lead(f) && !is_cab(f)).map(|f| {
        let from = f.get("from");
        if from.is_nullish() || read::is_empty_str(&from) { f.clone() } else { V::Obj(omit(f, &["cells"])) }
    }).collect();
    if !more.is_empty() { p.set("offices", read::arr_of(more)); }
    V::Obj(p)
}

/// `num(v)` — 유한한 수면 그 값.
fn num(v: &V) -> Option<f64> { v.as_num().filter(|x| x.is_finite()) }

/// `clip(cells, from, to)` — 칸 목록을 [from, to)로 잘라(걸치면 양쪽으로) 담는다. 빈 칸(null)은 빠진다.
fn clip(cells: &V, from: Option<f64>, to: Option<f64>) -> V {
    let out: Vec<V> = items(cells).into_iter().map(|c| {
        let arr = matches!(c, V::Arr(_));
        let a = num(&if arr { c.get(&1.0) } else { read::and(&c, "start") });
        let b = num(&if arr { c.get(&2.0) } else { read::and(&c, "end") });
        let Some(a) = a else { return c };
        let e = b.unwrap_or(a);
        if from.is_some_and(|f| e <= f) || to.is_some_and(|t| a >= t) { return V::Null; }
        let na = match from { Some(f) if a < f => f, _ => a };
        let nb = match (b, to) { (Some(b), Some(t)) if b > t => Some(t), (b, _) => b };
        if let V::Arr(src) = &c {
            let r = Arr::new(src.to_vec());
            r.set(1, na);
            if b.is_some() { r.set(2, nb.unwrap()); }
            return V::Arr(r);
        }
        let q = read::assign_copy(&c);
        q.set("start", na);
        if b.is_some() { q.set("end", nb.unwrap()); }
        V::Obj(q)
    }).filter(|c| !c.is_nullish()).collect();
    read::arr_of(out)
}

/// 토막 하나와 그것이 덮는 [from, to).
struct Piece { q: Obj, from: Option<f64>, to: Option<f64> }

/// `splitMoves(objects, eraRef, src)` — 옮겨 앉기(리메이크 2부 · 설계 3-3 · 결정 #3 A — 내보내기만):
/// 기간 있는 within이 둘 이상이고 모두 시대 그릇이며 경계가 정해져 겹치지 않고 섬김(partOf)이 없으면, 객체를 경계 해마다 **토막**으로 나눈다 —
/// 첫 토막은 원 id, 뒤 토막은 '<원 id>.mv<경계 해>'. 토막마다 그 그릇 하나에 기간 없이 들고, 지도자 · 내각 칸은 기간으로 나눠 담는다(걸치면 양쪽으로 잘라).
/// 그 객체를 가리킨 사건은 해가 든 토막으로, 그 객체를 앞선 나라로 적은 승계는 마지막 토막으로 돌린다.
/// 그릇 밖의 토막(리메이크 6단계): within이 객체 기간을 다 덮지 않으면(첫 그릇이 늦게 들거나 끝 그릇이 일찍 끝남) 그 앞 · 뒤도
/// 그릇 없는 토막으로 센다 — within 하나(분열기 그릇 안에 통일한 해까지만 들고 그 뒤로 이어지는 나라)도 옮겨 앉기. 기간을 다 덮는 within 하나는 그대로.
/// 섬김 · 실권의 상대가 토막 난 객체면(리메이크 6단계) 그 줄의 시작 해(비우면 가리킨 쪽 객체의 시작 해)가 든 토막으로 돌린다.
/// 토막 난 객체가 쥔 남의 실권(`power[].over`)은 그 줄의 시작 해(비우면 객체의 시작 해)가 든 토막 하나에만 둔다(리메이크 6단계 검토 — 이름만인 줄은 토막마다).
fn split_moves(objects: &mut Vec<V>, era_ref: &dyn Fn(&V) -> bool, src: &V) {
    let mut out: Vec<V> = Vec::new();
    let mut pieces: Vec<(Str, std::rc::Rc<Vec<Piece>>)> = Vec::new(); // 원 객체의 열쇠(id · 이름) → 토막들(Map — 같은 열쇠는 뒤가 덮음)
    for o in objects.iter() {
        let ws = refs(&o.get("within"));
        if ws.is_empty() || !ws.iter().all(era_ref) || !items(&o.get("partOf")).is_empty() {
            out.push(o.clone());
            continue;
        }
        #[derive(Clone)]
        struct Seg { of: V, a: Option<f64>, b: Option<f64> }
        let mut segs: Vec<Seg> = ws.iter().map(|w| Seg { of: w.get("of"), a: num(&w.get("start")), b: num(&w.get("end")) }).collect();
        js::sort_by(&mut segs, |x, y| x.a.unwrap_or(f64::NEG_INFINITY) - y.a.unwrap_or(f64::NEG_INFINITY));
        let (os, oe) = (num(&o.get("start")), num(&o.get("end")));
        if let (Some(a), Some(s)) = (segs[0].a, os) { if a > s { segs.insert(0, Seg { of: V::Null, a: None, b: Some(a) }); } } // 그릇 밖의 토막: 늦게 든 그릇의 앞
        if let Some(b) = segs[segs.len() - 1].b { if oe.is_none_or(|e| b < e) { segs.push(Seg { of: V::Null, a: Some(b), b: None }); } } // 일찍 떠난 그릇의 뒤
        if segs.len() < 2 {
            out.push(o.clone());
            continue;
        }
        let mut cuts: Vec<f64> = Vec::new();
        for i in 1..segs.len() {
            let (prev, cur) = (&segs[i - 1], &segs[i]);
            let cut = cur.a.or(prev.b);
            let broken = match cut {
                None => true,
                Some(c) => (prev.b.is_some() && cur.a.is_some() && prev.b != cur.a) || cuts.last().is_some_and(|l| c <= *l),
            };
            if broken { cuts.clear(); break; }
            cuts.push(cut.unwrap());
        }
        if cuts.len() != segs.len() - 1 || os.is_some_and(|s| cuts.first().is_some_and(|c| *c <= s)) || oe.is_some_and(|e| cuts.last().is_some_and(|c| *c >= e)) {
            out.push(o.clone());
            continue;
        }
        let id = o.get("id");
        let base = if !id.is_nullish() && !read::is_empty_str(&id) { js::to_str(&id) } else { js::to_str(&js::or(o.get("name"), V::from(""))) };
        let made: Vec<Piece> = segs.iter().enumerate().map(|(i, sg)| {
            let q = read::assign_copy(o);
            let w = Obj::new();
            w.set("of", sg.of.clone());
            q.set("within", read::arr_of(vec![V::Obj(w)]));
            if sg.of.is_nullish() { q.delete("within"); } // 그릇 밖의 토막 — 트랙 뿌리에(대범위 구성원이 아님)
            let from = if i == 0 { None } else { Some(cuts[i - 1]) };
            let to = if i == segs.len() - 1 { None } else { Some(cuts[i]) };
            if let Some(f) = from {
                q.set("id", Str::from(format!("{base}.mv{}", js::num_str(f))));
                q.set("start", f);
                for k in ["startUnknown", "startRange", "startAt", "succeeds"] { q.delete(k); }
            }
            if let Some(t) = to {
                q.set("end", t);
                for k in ["endUnknown", "endRange", "endAt", "ongoing"] { q.delete(k); }
            }
            let offices = o.get("offices");
            if js::truthy(&offices) {
                let list: Vec<V> = items(&offices).into_iter().map(|f| if js::truthy(&f) && read::is_plain(&f) {
                    let g = read::assign_copy(&f);
                    g.set("cells", clip(&f.get("cells"), from, to));
                    V::Obj(g)
                } else { f }).collect();
                q.set("offices", read::arr_of(list));
            }
            // 실권 줄(리메이크 6단계 검토): 남의 실권(over)은 그 줄의 시작 해(비우면 객체의 시작 해)가 든 토막 하나에만 — 토막마다 실으면 상대 띠에 같은 밑줄 · 이름이 겹쳐 실림.
            // 제 안의 실권자(over 없이 이름만)는 토막마다 그대로(제 띠 안으로 잘려 그려짐)
            if let V::Arr(power) = o.get("power") {
                let keep: Vec<V> = power.to_vec().into_iter().filter(|w| {
                    let over = w.get("over");
                    if !(js::truthy(w) && read::is_plain(w) && !over.is_nullish() && !js::to_str(&over).trim().is_empty()) { return true; }
                    match num(&w.get("start")).or(os) {
                        None => from.is_none(),
                        Some(y) => from.is_none_or(|f| y >= f) && to.is_none_or(|t| y < t),
                    }
                }).collect();
                q.set("power", read::arr_of(keep));
            }
            Piece { q, from, to }
        }).collect();
        let made = std::rc::Rc::new(made);
        for k in [o.get("id"), o.get("name")] {
            if k.is_nullish() || read::is_empty_str(&k) { continue; }
            let key = js::to_str(&k);
            match pieces.iter_mut().find(|(x, _)| *x == key) { Some(slot) => slot.1 = made.clone(), None => pieces.push((key, made.clone())) }
        }
        out.extend(made.iter().map(|p| V::Obj(p.q.clone())));
    }
    if pieces.is_empty() { return; }
    *objects = out;
    let find = |key: &V| -> Option<std::rc::Rc<Vec<Piece>>> { let k = js::to_str(key); pieces.iter().find(|(x, _)| *x == k).map(|(_, m)| m.clone()) };
    let piece_at = |made: &[Piece], y: f64| -> Obj {
        made.iter().find(|q| q.from.is_none_or(|f| y >= f) && q.to.is_none_or(|t| y < t)).unwrap_or(&made[0]).q.clone()
    };
    let id_of = |q: &Obj| { let id = q.get("id"); if !id.is_nullish() && !read::is_empty_str(&id) { id } else { q.get("name") } };
    for e in items(&src.get("events")) {
        let polity = read::and(&e, "polity");
        let made = if js::truthy(&e) && !polity.is_nullish() { find(&polity) } else { None };
        if let (Some(made), Some(start)) = (made, num(&e.get("start"))) {
            if let V::Obj(eo) = &e { eo.set("polity", id_of(&piece_at(&made, start))); }
        }
    }
    for q in objects.iter() {
        for r in items(&q.get("succeeds")) {
            let from = read::and(&r, "from");
            let made = if js::truthy(&r) && !from.is_nullish() { find(&from) } else { None };
            if let Some(made) = made {
                if !made.iter().any(|p| js::strict_eq(&V::Obj(p.q.clone()), q)) {
                    if let V::Obj(ro) = &r { ro.set("from", id_of(&made[made.len() - 1].q)); }
                }
            }
        }
    }
    // 섬김 · 실권의 상대(partOf[].of · power[].over)가 토막 난 객체면 그 줄의 시작 해(비우면 가리킨 쪽 객체의 시작 해)가 든 토막으로(리메이크 6단계 —
    // 0 ~ 100인 x가 50년에 그릇을 떠나 x · x.mv50으로 나뉘면 60년에 시작한 줄은 x.mv50으로). 경계를 걸친 줄도 나누지 않고 시작 해의 토막에.
    for q in objects.iter() {
        let y0 = num(&q.get("start"));
        let parts = q.get("partOf");
        for (i, r) in items(&parts).into_iter().enumerate() {
            let Some(w) = ref_of(&r) else { continue };
            let Some(made) = find(&w.get("of")) else { continue };
            let Some(y) = num(&w.get("start")).or(y0) else { continue };
            if made.iter().any(|p| js::strict_eq(&V::Obj(p.q.clone()), q)) { continue; }
            let to = id_of(&piece_at(&made, y));
            match (&r, &parts) {
                (V::Str(_), V::Arr(a)) => a.set(i, to),
                (V::Str(_), _) => { if let V::Obj(qo) = q { qo.set("partOf", to); } }
                (V::Obj(ro), _) => ro.set("of", to),
                _ => {}
            }
        }
        for r in items(&q.get("power")) {
            if !(js::truthy(&r) && read::is_plain(&r)) || r.get("over").is_nullish() { continue; }
            let key: V = js::to_str(&r.get("over")).trim().into();
            let Some(made) = find(&key) else { continue };
            let Some(y) = num(&r.get("start")).or(y0) else { continue };
            if made.iter().any(|p| js::strict_eq(&V::Obj(p.q.clone()), q)) { continue; }
            if let V::Obj(ro) = &r { ro.set("over", id_of(&piece_at(&made, y))); }
        }
    }
    // q._from · q._to는 토막 표(Piece)에 따로 들고 있었으므로 지울 것이 없다.
}

/// `organOf(o)` — 객체 → 옛 기관.
fn organ_of(o: &V) -> V {
    let g = omit(o, &["type", "display", "subtype", "within", "partOf", "offices"]);
    if !js::truthy(&g.get("scale")) && matches!(o.get("type"), V::Str(s) if s == "dependency") { g.set("scale", "zone"); } // 기관(agency)은 기본값이라 옛 정규화도 적지 않음
    let host: Vec<V> = refs(&o.get("within")).iter().map(to_polity).collect();
    if !host.is_empty() { g.set("host", cells::compact_part_of(host)); }
    V::Obj(g)
}

/// `groupOf(o)` — 객체 → 옛 단체.
fn group_of(o: &V) -> V {
    let g = omit(o, &["type", "display", "subtype", "within", "partOf", "offices", "persons", "people", "succeeds"]);
    let t = o.get("type");
    let sub = js::or(o.get("subtype"), V::from(if matches!(&t, V::Str(s) if s == "league") { "coalition" } else if matches!(&t, V::Str(s) if s == "regime") { "regime" } else { "" }));
    if js::truthy(&sub) { g.set("type", sub); }
    let w: Vec<V> = refs(&o.get("within")).iter().map(to_polity).collect();
    if !w.is_empty() { g.set("within", cells::compact_part_of(w)); }
    if !o.get("persons").is_nullish() { g.set("people", o.get("persons")); }
    let from: Vec<V> = items(&o.get("succeeds")).into_iter().filter(|s| js::truthy(s) && read::is_plain(s)).map(|s| {
        let x = Obj::new();
        x.set("group", s.get("from"));
        read::assign_into(&x, &V::Obj(omit(&s, &["from", "type"])));
        V::Obj(x)
    }).collect();
    if !from.is_empty() { g.set("from", read::arr_of(from)); }
    V::Obj(g)
}

/// `down(J4, warn)` — 형식 4 → 지금 읽기기가 읽는 옛 꼴(형식 3). `ctx.split`이면 옮겨 앉기를 토막으로 나눈다.
pub fn down(ctx: &Ctx, j4: &V, warn: &mut dyn FnMut(String)) -> crate::Result<V> {
    let src = { let c = clone(j4)?; if js::truthy(&c) { c } else { V::Obj(Obj::new()) } };
    for k in ["periods", "epochs", "scopes", "organs", "groups", "figures"] {
        if !src.get(k).is_nullish() { warn(format!("형식 4 파일의 \"{k}\"는 읽지 않습니다 — 항목은 objects에 적습니다.")); }
    }
    let mut objects: Vec<V> = items(&src.get("objects")).into_iter().filter(|o| js::truthy(o) && read::is_plain(o)).map(|o| V::Obj(read::assign_copy(&o))).collect();
    let label = |o: &V| js::to_str(&js::or(js::or(o.get("name"), o.get("id")), V::from("?")));
    for o in &objects {
        let V::Obj(oo) = o else { continue };
        let ty = o.get("type");
        let t = if ty.is_nullish() || read::is_empty_str(&ty) { Str::from("state") } else { type_id(&ty) };
        if t.is_empty() { warn(format!("객체 \"{}\"의 종류 \"{}\"을(를) 알 수 없어 국가로 읽습니다.", label(o), js::to_str(&ty))); }
        oo.set("type", if t.is_empty() { Str::from("state") } else { t });
        let display = o.get("display");
        if !display.is_nullish() && !matches!(&display, V::Str(s) if DISPLAYS.iter().any(|d| s == d)) {
            warn(format!("객체 \"{}\"의 그리는 자리 \"{}\"을(를) 알 수 없어 종류대로 그립니다.", label(o), js::to_str(&display)));
            oo.delete("display");
        }
    }
    // 사람 객체(설계 3-11 ①) → 옛 인물(figures) — 칸은 그대로. 사람은 그릇에 들지 않고 섬기지 않으며 직위 줄 · 실권을 갖지 않는다(그 자리는 지도자 칸의 person이 말함)
    let mut figures: Vec<V> = Vec::new();
    objects.retain(|o| {
        if !matches!(o.get("type"), V::Str(t) if t == "person") { return true; }
        for (k, word) in [("offices", "직위 줄"), ("power", "실권"), ("within", "든 그릇"), ("partOf", "섬김")] {
            if o.get(k).is_nullish() { continue; }
            warn(format!("사람 \"{}\"의 {word}은(는) 사람 객체에 적지 않아 뺍니다(칭호는 지도자 칸의 person으로).", label(o)));
            if let V::Obj(oo) = o { oo.delete(k); }
        }
        figures.push(V::Obj(omit(o, &["type"])));
        false
    });
    // 트랙을 비운 객체는 within 사슬을 따라 그릇의 트랙을 물려받는다(설계 3-7)
    let mut by_key: HashMap<Str, V> = HashMap::new();
    for o in &objects {
        for k in [o.get("id"), o.get("name")] {
            if k.is_nullish() || read::is_empty_str(&k) { continue; }
            by_key.entry(js::to_str(&k)).or_insert_with(|| o.clone());
        }
    }
    // 그릇(within)이 고리를 이룬 객체는 한 번만 알린다(5단계 과제 1 검사 규칙) — JS trackOf(o, path)와 같이 지나온 경로로 센다
    fn track_of(o: &V, by_key: &HashMap<Str, V>, path: &mut Vec<V>, cycled: &mut Vec<V>, warn: &mut dyn FnMut(String)) -> Str {
        if js::truthy(&o.get("track")) { return js::to_str(&o.get("track")); }
        if path.iter().any(|s| js::strict_eq(s, o)) {
            if !cycled.iter().any(|s| js::strict_eq(s, o)) {
                cycled.push(o.clone());
                warn(format!("객체 \"{}\"의 그릇(within)이 고리를 이룹니다 — 트랙을 물려받지 못합니다.", js::to_str(&js::or(js::or(o.get("name"), o.get("id")), V::from("?")))));
            }
            return Str::default();
        }
        path.push(o.clone());
        let mut out = Str::default();
        for w in refs(&o.get("within")) {
            let of = js::to_str(&w.get("of"));
            let t = match by_key.get(&of) { Some(x) => track_of(x, by_key, path, cycled, warn), None => Str::default() };
            if !t.is_empty() { out = t; break; }
        }
        path.pop();
        out
    }
    let mut cycled: Vec<V> = Vec::new();
    for o in &objects {
        if js::truthy(&o.get("track")) { continue; }
        let t = track_of(o, &by_key, &mut Vec::new(), &mut cycled, warn);
        if !t.is_empty() { if let V::Obj(oo) = o { oo.set("track", t); } }
    }
    // 직위 줄 빌려 보기(offices[].from — 설계 3-11 ③): "객체 id" 또는 "객체 id/직위 이름" → 그 객체의 직위 줄 칸을 복제해 옛 꼴로 내린다. from과 cells를 함께 적으면 from만.
    // 빌려 올 객체 · 직위 줄이 없거나 빌림이 고리를 이루면 알리고 그 줄을 뺀다. 찾기는 고치기 전의 직위 줄(orig)에서 — 객체 차례에 기대지 않게
    fn office_from(o: &V, f: &V, by_key: &HashMap<Str, V>, orig: &[(V, V)], seen: &mut Vec<V>, warn: &mut dyn FnMut(String)) -> Option<V> {
        let raw: String = js::to_str(&js::or(f.get("from"), V::from(""))).as_str().to_string();
        let r = raw.trim();
        let (key, want) = match r.find('/') { Some(i) => (r[..i].trim().to_string(), r[i + 1..].trim().to_string()), None => (r.to_string(), String::new()) };
        let fname = js::to_str(&js::or(js::or(f.get("name"), V::from(want.as_str())), V::from("?")));
        let label = format!("객체 \"{}\"의 직위 줄 \"{}\"", js::to_str(&js::or(js::or(o.get("name"), o.get("id")), V::from("?"))), if fname.is_empty() { Str::from("?") } else { fname });
        let Some(from) = by_key.get(&Str::from(key.as_str())) else {
            warn(format!("{label}이(가) 빌려 올 객체 \"{key}\"을(를) 찾지 못해 뺍니다."));
            return None;
        };
        let offs: Vec<V> = orig.iter().find(|(k, _)| js::strict_eq(k, from)).map(|(_, v)| items(v)).unwrap_or_default().into_iter().filter(|x| js::truthy(x) && read::is_plain(x)).collect();
        let hit = if !want.is_empty() { offs.iter().find(|x| matches!(x.get("name"), V::Str(t) if t == want.as_str())) }
            else { offs.iter().find(|x| matches!(x.get("name"), V::Str(t) if t == LEADERS)).or(offs.first()) };
        let Some(hit) = hit.cloned() else {
            warn(format!("{label}이(가) 빌려 올 직위 줄 \"{}\"을(를) 객체 \"{key}\"에서 찾지 못해 뺍니다.", if want.is_empty() { LEADERS } else { want.as_str() }));
            return None;
        };
        let hf = hit.get("from");
        if !hf.is_nullish() && !read::is_empty_str(&hf) {
            if seen.iter().any(|x| js::strict_eq(x, &hit)) {
                warn(format!("{label}의 빌림이 고리를 이룹니다 — 뺍니다."));
                return None;
            }
            seen.push(hit.clone());
            return office_from(from, &hit, by_key, orig, seen, warn);
        }
        Some(list(&hit.get("cells")))
    }
    let orig: Vec<(V, V)> = objects.iter().map(|o| (o.clone(), list(&o.get("offices")))).collect();
    for o in &objects {
        let V::Obj(oo) = o else { continue };
        let offs = o.get("offices");
        if !matches!(offs, V::Arr(_)) { continue; }
        let mut out: Vec<V> = Vec::new();
        for f in items(&offs) {
            let from = f.get("from");
            if !(js::truthy(&f) && read::is_plain(&f)) || from.is_nullish() || read::is_empty_str(&from) { out.push(f); continue; }
            if !items(&f.get("cells")).is_empty() {
                warn(format!("객체 \"{}\"의 직위 줄 \"{}\"에 from과 cells가 함께 적혀 있어 from만 씁니다.", label(o), js::to_str(&js::or(f.get("name"), V::from("?")))));
            }
            let mut seen = vec![f.clone()];
            if let Some(cells) = office_from(o, &f, &by_key, &orig, &mut seen, warn) {
                let nf = omit(&f, &["cells"]); // from은 둔다 — period_of가 자리의 빌림(leadersFrom …)으로 내림(5단계 과제 4)
                nf.set("cells", clone(&cells)?);
                out.push(V::Obj(nf));
            }
        }
        oo.set("offices", read::arr_of(out));
    }
    let is_s = |v: V, s: &str| matches!(v, V::Str(t) if t == s);
    let is_era = |o: &V| is_s(o.get("type"), "era") && !is_s(o.get("display"), "band");
    let is_mark = |o: &V| is_s(o.get("display"), "mark");
    let is_inside = |o: &V| is_s(o.get("display"), "inside");
    // 시대 그릇을 가리키는 within — id나 이름. 이름은 같은 이름 · id의 다른 객체가 없을 때만(옛 찾기처럼 id가 앞섬)
    let mut era_of: HashMap<Str, V> = HashMap::new();
    for o in &objects {
        let id = o.get("id");
        if is_era(o) && !id.is_nullish() && !read::is_empty_str(&id) { era_of.insert(js::to_str(&id), o.clone()); }
    }
    for o in &objects {
        let name = o.get("name");
        if !is_era(o) || name.is_nullish() || read::is_empty_str(&name) || era_of.contains_key(&js::to_str(&name)) { continue; }
        if !objects.iter().any(|q| !js::strict_eq(q, o) && !is_era(q) && (js::strict_eq(&q.get("name"), &name) || js::strict_eq(&q.get("id"), &name))) {
            era_of.insert(js::to_str(&name), o.clone());
        }
    }
    let era_ref = |w: &V| matches!(w.get("of"), V::Str(s) if era_of.contains_key(&s));
    if ctx.split { split_moves(&mut objects, &era_ref, &src); } // 옮겨 앉기의 토막(내보내기만)
    // 시대 그릇의 구성원 — 시대를 within으로 가리킨 객체(객체 차례대로 · 옛 단체 · 기관은 대범위에 들 수 없음)
    let mut members: Vec<(V, Vec<V>)> = Vec::new(); // Map(그릇 객체 → 구성원)
    let members_of = |members: &Vec<(V, Vec<V>)>, era: &V| members.iter().find(|(k, _)| js::strict_eq(k, era)).map(|(_, m)| m.clone()).unwrap_or_default();
    for o in &objects {
        if is_era(o) || is_mark(o) || is_inside(o) { continue; }
        for w in refs(&o.get("within")) {
            if !era_ref(&w) { continue; }
            let era = era_of[&js::to_str(&w.get("of"))].clone();
            match members.iter_mut().find(|(k, _)| js::strict_eq(k, &era)) {
                Some((_, got)) => { if !got.iter().any(|g| js::strict_eq(g, o)) { got.push(o.clone()); } }
                None => members.push((era, vec![o.clone()])),
            }
        }
    }
    // 포개짐(리메이크 2부 · 설계 3-3): 트랙이 있고 구성원이 있는 시대 = 그릇(대범위). 시대의 within이 그릇을 가리키면 '그릇 안의 그릇'(scopes[].within)
    // 또는 '그릇 안 이름표 시대'(구성원 없음 — epochs[].within), 그릇이 아닌 시대를 가리키면 지금처럼 같은 뜻의 시대 구분(scopes[].epoch)
    let is_scope_era = |o: &V| is_era(o) && js::truthy(&o.get("track")) && (!members_of(&members, o).is_empty() || !items(&o.get("members")).is_empty());
    let parent_of = |o: &V| -> Option<V> {
        let ep = refs(&o.get("within")).into_iter().next()?;
        let parent = era_of.get(&js::to_str(&ep.get("of")))?;
        if !js::strict_eq(parent, o) && is_scope_era(parent) && js::strict_eq(&parent.get("track"), &o.get("track")) { Some(ep.get("of")) } else { None }
    };
    let (mut periods, mut epochs, mut scopes, mut organs, mut groups) = (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
    for o in &objects {
        if is_inside(o) { organs.push(organ_of(o)); continue; }
        if is_mark(o) { groups.push(group_of(o)); continue; }
        if !is_era(o) { periods.push(period_of(o, &era_ref, warn)); continue; }
        let own = members_of(&members, o);
        let outside = items(&o.get("members"));
        let base = V::Obj(omit(o, &["type", "display", "subtype", "within", "members", "partOf", "offices"]));
        // 트랙이 있고 구성원이 있는 시대 = 대범위(그릇). 트랙을 비운 공통 시대는 가리키는 이가 있어도 끌지 않는다 — 시대 구분(이름표)으로(설계 3-3)
        if js::truthy(&o.get("track")) && (!own.is_empty() || !outside.is_empty()) {
            let s = omit(&base, &["alternatives"]);
            let ep = refs(&o.get("within")).into_iter().next();
            if let Some(parent) = parent_of(o) { s.set("within", parent); } // 그릇 안의 그릇
            else if let Some(ep) = ep { s.set("epoch", ep.get("of")); }
            let mut list: Vec<V> = own.iter().map(|m| {
                // HT.compactScopeRef(m.track !== o.track ? { track: m.track, polity: m.id || m.name } : { polity: m.id || m.name })
                let polity = js::or(m.get("id"), m.get("name"));
                let track = if !js::strict_eq(&m.get("track"), &o.get("track")) { m.get("track") } else { V::Undef };
                cells::compact_scope_ref(&track, &polity)
            }).collect();
            list.extend(outside);
            s.set("members", read::arr_of(list));
            scopes.push(V::Obj(s));
        } else {
            if !own.is_empty() { warn(format!("시대 \"{}\"는 트랙이 없어(공통 시대) 구성원을 모으지 않고 시대 구분으로 읽습니다.", js::to_str(&js::or(o.get("name"), o.get("id"))))); }
            let e = omit(&base, &["label", "default", "host"]);
            if let Some(parent) = parent_of(o) { e.set("within", parent); } // 그릇 안 이름표 시대(그 그릇 윗변의 둘째 탭)
            epochs.push(V::Obj(e));
        }
    }
    let json = omit(&src, &["objects", "periods", "epochs", "scopes", "organs", "groups", "figures"]);
    json.set("formatVersion", vocab::FORMAT_VERSION); // 지금 읽는 옛 형식으로 — 저장은 5단계 과제 2부터 형식 4
    json.set("periods", read::arr_of(periods));
    json.set("epochs", read::arr_of(epochs));
    if !scopes.is_empty() { json.set("scopes", read::arr_of(scopes)); }
    if !organs.is_empty() { json.set("organs", read::arr_of(organs)); }
    if !groups.is_empty() { json.set("groups", read::arr_of(groups)); }
    if !figures.is_empty() { json.set("figures", read::arr_of(figures)); }
    // 문화권별 주기 줄(yearCycles — 설계 3-11 ⑤): 지금 날짜 칸의 간지 줄은 하나뿐 — 최상위 yearCycle이 없으면 전체 줄(sphere 없음)을 yearCycle로.
    // 문화권 줄은 고르지 않는다(6단계 결정 16) · 전체 줄이 내장 육십갑자(예약 값 · 표지 builtin)면 yearCycle을 비운 것과 같아 두지 않는다.
    // yearCycles · 시대 구분의 sphere · 객체의 importance · 칸의 status는 그대로 실어 둔다(옛 읽기기는 모르는 칸을 버림)
    if json.get("yearCycle").is_nullish() && matches!(json.get("yearCycles"), V::Arr(_)) {
        let cs: Vec<V> = items(&json.get("yearCycles")).into_iter().filter(|c| js::truthy(c) && read::is_plain(c)).collect();
        let pick = cs.iter().find(|c| { let s = c.get("sphere"); s.is_nullish() || read::is_empty_str(&s) }).cloned();
        if let Some(p) = pick.filter(|p| !read::misc::is_sexagenary_row(p)) {
            json.set("yearCycle", V::Obj(omit(&p, &["sphere", "era", "from", "step", "builtin"])));
            warn(format!("문화권별 주기 줄 {}개 가운데 \"{}\"만 날짜 칸의 간지 줄로 읽습니다(문화권마다의 줄은 아직).", cs.len(), js::to_str(&js::or(js::or(p.get("label"), p.get("era")), V::from("?")))));
        }
    }
    Ok(V::Obj(json))
}

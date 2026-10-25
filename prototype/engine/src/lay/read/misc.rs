//! `js/core.js` 2940 ~ 3070줄 가운데 읽기가 쓰는 것 — 배열 기준 · 남북 값 · 간지 설정 · 해시 · 색 — 한 벌 P3 과제 5a · 5b.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 2940 ~ 2952줄 `HT.ROW_ORDERS` · `ROW_ORDER_WORDS` · `HT.readRowOrder`
//! - (5b) 2955 ~ 2959줄 `HT.readNorthSouth`
//! - (5c) 2961 ~ 2964줄 `HT.readSpot`
//! - 2965 ~ 3004줄 `HT.YEAR_CYCLE_LIMITS` · `YEAR_CYCLE_KEYS` · `HT.readYearCycle`
//! - 3062 ~ 3070줄 `HT.hash` · `HT.autoColor` · `HT.isColor`
//!
//! 옮기지 않은 것(뒤 과제): 간지 셈(`HT.cycleIndex` …) · 화면 도움.
use super::{dates, vocab, Ctx};
use crate::lay::js::{self, Obj, Str, V};

/// `HT.ROW_ORDERS`의 id.
const ROW_ORDERS: [&str; 2] = ["start", "northSouth"];
/// `ROW_ORDER_WORDS`(한국어 낱말 · 소문자 영문).
const ROW_ORDER_WORDS: [(&str, &str); 12] = [
    ("시작", "start"), ("시작 해", "start"), ("시작해", "start"), ("시작 연도", "start"), ("연도", "start"), ("남북", "northSouth"), ("북남", "northSouth"),
    ("북 → 남", "northSouth"), ("북→남", "northSouth"), ("북에서 남", "northSouth"), ("north-south", "northSouth"), ("northsouth", "northSouth"),
];
/// `HT.readRowOrder(v)` — 배열 기준 글 → `Some("start" | "northSouth")` · 빈 값 `Some("")` · 모르는 값 `None`(JS의 null).
pub fn read_row_order(v: &V) -> Option<Str> {
    let s = js::to_str(&js::nullish(v.clone(), V::from(""))).trim();
    if s.is_empty() { return Some(s); }
    if ROW_ORDERS.iter().any(|o| s == *o) { return Some(s); }
    let text = s.as_str();
    let word = |k: &str| ROW_ORDER_WORDS.iter().find(|(w, _)| *w == k).map(|(_, id)| *id);
    let lowered = text.to_lowercase();
    let k = if word(&text).is_some() { text.into_owned() } else { lowered };
    word(&k).map(Str::from)
}

/// `HT.readNorthSouth(v)` — 남북 값 → 수(빈 값 None — JS의 undefined · 읽지 못하면 `Some(NaN)`). 글로 적은 수("38.5")도 읽는다.
pub fn read_north_south(v: &V) -> Option<f64> {
    if v.is_nullish() || matches!(v, V::Str(s) if s.trim().is_empty()) { return None; }
    let n = match v { V::Num(n) => *n, V::Str(s) => js::to_num(&V::Str(s.trim())), _ => f64::NAN };
    Some(if n.is_finite() { n } else { f64::NAN })
}

/// `HT.readSpot(v)`(5c) — 사건의 자리(spot) → 0 ~ 1의 수(소수 셋째 자리까지 — `Math.round(n * 1000) / 1000`) · 읽지 못하거나 범위 밖이면 None(JS의 undefined).
/// 글로 적은 수("0.3")도 읽는다.
pub fn read_spot(v: &V) -> Option<f64> {
    let n = match v { V::Num(n) => *n, V::Str(s) if !s.trim().is_empty() => js::to_num(&V::Str(s.trim())), _ => f64::NAN };
    if n.is_finite() && (0.0..=1.0).contains(&n) { Some(js::round(n * 1000.0) / 1000.0) } else { None }
}

/// `HT.YEAR_CYCLE_LIMITS`.
const YC_NAMES: usize = 240;
const YC_NAME_LEN: usize = 20;
const YC_LABEL: usize = 20;
/// `YEAR_CYCLE_KEYS`.
const YEAR_CYCLE_KEYS: [&str; 4] = ["names", "start", "startAt", "label"];

/// `HT.readYearCycle(v, warn)` — 간지 설정 읽기 → undefined(적지 않음 · 육십갑자) · false(간지 줄 기본 끔) · `{ names, start, label? }`.
/// 읽지 못한 것은 `warn`으로 알리고 버린다.
pub fn read_year_cycle(ctx: &Ctx, v: &V, warn: &mut dyn FnMut(String)) -> V {
    if v.is_nullish() { return V::Undef; }
    let trimmed = |v: &V| if let V::Str(s) = v { Some(s.trim()) } else { None };
    if matches!(v, V::Bool(false)) || trimmed(v).is_some_and(|t| t == "끔" || t == "off" || t == "false") { return V::Bool(false); }
    if matches!(v, V::Bool(true)) || trimmed(v).is_some_and(|t| t.is_empty()) {
        if matches!(v, V::Bool(true)) { warn("간지 설정(yearCycle)의 true는 적지 않은 것과 같아(육십갑자) 뺐습니다 — 끄려면 false, 다른 순환이면 { \"names\", \"start\" }.".into()); }
        return V::Undef;
    }
    if !matches!(v, V::Obj(_) | V::Map(_) | V::Set(_)) {
        warn("간지 설정(yearCycle)은 false나 { \"names\", \"start\", \"label\" } 꼴이어야 해서 무시했습니다.".into());
        return V::Undef;
    }
    if let V::Obj(o) = v {
        for k in o.keys() { if !YEAR_CYCLE_KEYS.iter().any(|x| k == *x) { warn(format!("간지 설정(yearCycle)의 \"{k}\"은(는) 모르는 칸이라 버렸습니다.")); } }
    }
    let raw_names = v.get("names");
    let list: Vec<V> = match &raw_names {
        V::Arr(a) => a.to_vec(),
        V::Str(s) => super::split_units(s, &[0x2C, 0xFF0C]).into_iter().map(V::Str).collect(),
        _ => Vec::new(),
    };
    let mut names: Vec<Str> = list.iter().map(|x| js::to_str(&js::nullish(x.clone(), V::from(""))).trim()).filter(|x| !x.is_empty()).collect();
    if names.iter().any(|x| x.len16() > YC_NAME_LEN) {
        warn(format!("간지 설정: 명칭은 하나에 {YC_NAME_LEN}자까지라 넘친 것을 잘랐습니다."));
        names = names.iter().map(|x| x.slice16(0.0, YC_NAME_LEN as f64)).collect();
    }
    if names.len() > YC_NAMES {
        warn(format!("간지 설정: 명칭은 {YC_NAMES}개까지라 뒤의 것을 버렸습니다."));
        names.truncate(YC_NAMES);
    }
    if names.len() < 2 {
        warn("간지 설정(yearCycle)의 명칭 목록(names)이 둘 이상이어야 해서 무시했습니다(육십갑자 그대로).".into());
        return V::Undef;
    }
    let o = Obj::new();
    o.set("names", super::arr_of(names.into_iter().map(V::Str).collect()));
    let start = v.get("start");
    let d = if start.is_nullish() || super::is_empty_str(&start) { None } else { dates::read_date(ctx, &start, &v.get("startAt")) };
    match &d {
        Some(d) if !d.t.is_nan() && (d.t + 1e-9).floor() != 0.0 => o.set("start", (d.t + 1e-9).floor()),
        _ => {
            warn(format!("간지 설정: 기준 연도(start — 첫 명칭의 해){} 1년으로 봅니다.", if d.is_some() { "를 읽을 수 없어" } else { "가 없어" }));
            o.set("start", 1.0);
        }
    }
    let label = js::to_str(&js::nullish(v.get("label"), V::from(""))).trim();
    if !label.is_empty() { o.set("label", label.slice16(0.0, YC_LABEL as f64)); }
    if label.len16() > YC_LABEL { warn(format!("간지 설정: 줄 제목(label)은 {YC_LABEL}자까지라 잘랐습니다.")); }
    V::Obj(o)
}

/// `YEAR_CYCLES_KEYS` — 문화권별 주기 줄의 칸.
const YEAR_CYCLES_KEYS: [&str; 9] = ["sphere", "names", "start", "startAt", "label", "era", "from", "fromAt", "step"];

/// (2026-10-24 맞춤 · 리메이크 3단계 과제 1 · `core.js` `7c75434e37fa`) 3059 ~ 3108줄 — `HT.readYearCycles(v, warn)`(5단계 과제 6) — 문화권별 주기 줄(yearCycles) 읽기 → 읽힌 줄의 목록. 읽지 못한 줄은 `warn(글, 줄 번호)`로 알리고 버린다.
/// 줄 = 이름 돌림 `{ sphere?, names, start, label? }`(최상위 yearCycle과 같은 읽기) 또는 연호 눈금 `{ sphere?, era, from, step, label? }` · 문화권마다 한 줄(겹치면 뒤의 것을 뺌).
pub fn read_year_cycles(ctx: &Ctx, v: &V, warn: &mut dyn FnMut(String, Option<usize>)) -> Vec<V> {
    if v.is_nullish() { return Vec::new(); }
    let V::Arr(a) = v else {
        warn("문화권별 주기 줄(yearCycles)은 목록이어야 해서 무시했습니다.".into(), None);
        return Vec::new();
    };
    let mut out: Vec<V> = Vec::new();
    for (i, c) in a.to_vec().iter().enumerate() {
        let label = format!("주기 줄 #{}", i + 1);
        let V::Obj(co) = c else { warn(format!("{label}: 형식이 올바르지 않습니다."), Some(i)); continue; };
        for k in co.keys() { if !YEAR_CYCLES_KEYS.iter().any(|x| k == *x) { warn(format!("{label}: \"{k}\"은(는) 모르는 칸이라 버렸습니다."), Some(i)); } }
        let o = Obj::new();
        let sp = js::to_str(&js::nullish(c.get("sphere"), V::from(""))).trim();
        if !sp.is_empty() {
            if !dates::id_ok(&sp) { warn(format!("{label}: 문화권 id \"{sp}\"이(가) 올바르지 않아 줄을 뺐습니다."), Some(i)); continue; }
            o.set("sphere", sp);
        }
        let has_names = match c.get("names") { V::Arr(n) => n.len() > 0, V::Str(s) => !s.trim().is_empty(), _ => false };
        let era = js::to_str(&js::nullish(c.get("era"), V::from(""))).trim();
        if has_names {
            if !era.is_empty() { warn(format!("{label}: 이름 돌림(names)과 연호 눈금(era)을 함께 적어 이름 돌림으로 읽고 연호 눈금은 버렸습니다."), Some(i)); }
            let arg = Obj::new();
            for k in ["names", "start", "startAt", "label"] { arg.set(k, c.get(k)); }
            let mut sub = Vec::new();
            let yc = read_year_cycle(ctx, &V::Obj(arg), &mut |m| sub.push(m));
            for m in sub { warn(format!("{label}: {m}"), Some(i)); }
            let V::Obj(yo) = yc else { continue };
            for (k, x) in yo.entries() { o.set(&k, x); }
        } else if !era.is_empty() {
            if era.len16() > YC_LABEL { warn(format!("{label}: 연호(era)는 {YC_LABEL}자까지라 잘랐습니다."), Some(i)); }
            o.set("era", era.slice16(0.0, YC_LABEL as f64));
            let from = c.get("from");
            let d = if from.is_nullish() || super::is_empty_str(&from) { None } else { dates::read_date(ctx, &from, &c.get("fromAt")) };
            match &d {
                Some(d) if !d.t.is_nan() => o.set("from", (d.t + 1e-9).floor()),
                _ => { warn(format!("{label}: 연호 눈금의 원년(from){} 줄을 뺐습니다.", if d.is_some() { "을 읽을 수 없어" } else { "이 없어" }), Some(i)); continue; }
            }
            let step = c.get("step");
            let st = if step.is_nullish() || super::is_empty_str(&step) { 1.0 } else { js::to_num(&step) };
            if !(st.is_finite() && st.fract() == 0.0) || st < 1.0 {
                warn(format!("{label}: 눈금 간격(step)은 1 이상의 정수여야 해서 1로 봅니다."), Some(i));
                o.set("step", 1.0);
            } else { o.set("step", st); }
            let lb = js::to_str(&js::nullish(c.get("label"), V::from(""))).trim();
            if lb.len16() > YC_LABEL { warn(format!("{label}: 줄 제목(label)은 {YC_LABEL}자까지라 잘랐습니다."), Some(i)); }
            if !lb.is_empty() { o.set("label", lb.slice16(0.0, YC_LABEL as f64)); }
        } else { warn(format!("{label}: 이름 돌림(names)도 연호 눈금(era)도 없어 줄을 뺐습니다."), Some(i)); continue; }
        let key = |x: &V| js::to_str(&js::or(x.get("sphere"), V::from("")));
        let me = key(&V::Obj(o.clone()));
        if out.iter().any(|x| key(x) == me) {
            warn(format!("{label}: {}의 주기 줄이 앞에 있어 뒤의 것을 뺐습니다(문화권마다 한 줄).", if me.is_empty() { "전체".to_string() } else { format!("문화권 \"{me}\"") }), Some(i));
            continue;
        }
        out.push(V::Obj(o));
    }
    out
}

/// `HT.hash(str)` — djb2(UTF-16 코드 단위 · 32비트 감김) → 부호 없는 값의 36진 글.
pub fn hash(s: &Str) -> Str {
    let mut h: i32 = 5381;
    for u in s.units() { h = h.wrapping_shl(5).wrapping_add(h).wrapping_add(i32::from(u)); }
    Str::from(radix36(h as u32))
}
/// `(n).toString(36)`(부호 없는 정수).
fn radix36(mut n: u32) -> String {
    if n == 0 { return "0".into(); }
    let mut digits = Vec::new();
    while n > 0 {
        digits.push(b"0123456789abcdefghijklmnopqrstuvwxyz"[(n % 36) as usize]);
        n /= 36;
    }
    digits.reverse();
    String::from_utf8(digits).expect("ASCII")
}
/// `HT.autoColor(key)` — 열쇠의 해시로 팔레트의 한 색.
pub fn auto_color(key: &V) -> &'static str {
    let h = hash(&js::to_str(key));
    let n = u64::from_str_radix(&h.as_str(), 36).expect("hash는 36진 글");
    vocab::PALETTE[(n % vocab::PALETTE.len() as u64) as usize]
}
/// `HT.isColor(c)` — `#rgb` · `#rrggbb`(16진 · 대소문자 무관)인 글인가.
pub fn is_color(c: &V) -> bool {
    let V::Str(s) = c else { return false };
    let Some(t) = s.exact() else { return false };
    let Some(hex) = t.strip_prefix('#') else { return false };
    (hex.len() == 3 || hex.len() == 6) && hex.bytes().all(|b| b.is_ascii_hexdigit())
}

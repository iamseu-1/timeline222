//! 내보내기 모듈이 함께 쓰는 작은 도움 · 상수 — JS 모듈(`prototype/scripts/export/*.mjs`)도 파일마다 제 사본을 두고 갈래들도 그대로 베껴 옮겼던 것을 하나로(한 벌 P3 과제 Y).
//! 몸이 같은 사본만 모았다 — 뜻이 다른 같은 이름(예: entities.mjs 68줄의 `some`은 빈 글을 남긴다 · axis.mjs의 `ST`는 다른 비트 표)은 제 모듈에 그대로 둔다.
//! - `lodOf` — strips.mjs 22 ~ 26줄 · hangs.mjs 36 ~ 41줄 · rails.mjs · power.mjs · lens.mjs(같은 식 — engine/src/levels.rs의 lod_of) → [`lod_of`]
//! - `styleWith` — strips.mjs 19줄 · lens.mjs `(style, alt, seq)` · power.mjs `(style, seq)`(alt 없음 — 같은 식에 alt = 거짓) → [`style_with`]
//! - `cellStyle` — strips.mjs 29 ~ 35줄 · lens.mjs(같은 식) → [`cell_style`]
//! - 계약 6-2의 칸 모습 비트 `ST`(strips.mjs 9 ~ 11줄 — power.mjs · lens.mjs는 그 일부를 베낌) → [`st`] · 단의 종류 `STRIP`(strips.mjs 7줄) → [`strip`] ·
//!   공용 칸 단의 종류 8(power · lens) → [`KIND_COMMON`] · 단 갈래의 자리(style 27 ~ 29 — power · lens) → [`BAND_SHIFT`] · 일반 항목 구역 43(strips · power · lens) → [`SECTION_ITEM`]
//! - base.mjs `minute`을 `Number.isFinite`로 거른 꼴(power · lens — 수가 아니면 null) → [`minute_of`](JS 값 꼴은 [`minute_val`] — rails가 갈래 B 모듈에 내주던 것)
//! - `x == null || !isFinite(x) ? fallback : x`(power · lens) → [`finite_or`] · JSON 값의 참거짓(`!!x`) · 엄격 같음(`x === k`)(power · lens) → [`jtruthy`] · [`jis`]
//! - `some(v)` — docs.mjs 74줄 · metro.mjs 31줄(같은 식: 빈 것(없음 · 빈 글 · 빈 목록 · 빈 표)은 null) → [`some`] · `idOf(uid)`(hangs · links) → [`band_id`]
//! - 모듈이 남긴 잘못(`model::util::fault`)을 그 모듈의 오류로 → [`fault_check`]
//! - `x.has(k)`(Set · Map — `tr.foldedRows` · `hiddenRows` · `memberRows`) → [`has_of`] · 그 자리에서 멈추는 꼴 [`has_or_err`]
use crate::lay::js::{self, V};
use crate::lay::model::util::{is, lt, n, take_fault, tv};
use serde_json::Value;

/// 계약 6-2의 칸 모습 비트(strips.mjs 9 ~ 11줄 `ST`).
pub mod st {
    pub const UNK_S: i32 = 1;
    pub const UNK_E: i32 = 2;
    pub const JOIN_L: i32 = 4;
    pub const ESTIMATED: i32 = 8;
    pub const LEGEND: i32 = 16;
    pub const TAGGED: i32 = 32;
    pub const RANGE: i32 = 64;
    pub const ALT: i32 = 128;
    /// 0x700 — 지위 서열 단계 + 1의 자리(밀기).
    pub const RANK: u32 = 8;
    /// 0x3800 — 예속 이름표 모양 + 1의 자리(밀기).
    pub const DEP: u32 = 11;
}
/// 단의 종류(계약 5절 — strips.mjs 7줄 `STRIP`) — 6 인물은 figures.mjs의 몫.
pub mod strip {
    pub const DYNASTY: f64 = 0.0;
    pub const LEADER: f64 = 1.0;
    pub const CABINET: f64 = 2.0;
    pub const ORGAN: f64 = 3.0;
    pub const PHASE: f64 = 4.0;
    pub const RANK: f64 = 5.0;
    pub const DEP: f64 = 7.0;
}
/// 칸 종류 8 — 공용 칸 단(power의 단체 단 · lens의 렌즈 칸).
pub const KIND_COMMON: f64 = 8.0;
/// 공용 칸 단의 단 갈래(style 27 ~ 29)의 자리.
pub const BAND_SHIFT: u32 = 27;
/// 일반 항목 구역 43 — 칸이 가리키는 항목의 uid(strips · power · lens).
pub const SECTION_ITEM: f64 = 43.0;

/// `lodOf(duration)` — 단계 · 통 산수(engine/src/levels.rs의 lod_of와 같은 식): 기간이 통 너비(4^L분)의 1/8 이상인 가장 성긴 단계.
/// 칸 · 이름표에 딸린 항목은 그 칸과 같은 단계까지 실린다.
pub fn lod_of(duration: f64) -> f64 {
    let wide = js::max(&[0.0, duration]) * 8.0;
    for level in (0..=14).rev() { if wide >= 4f64.powi(level) { return f64::from(level); } }
    0.0
}

/// `seq == null || seq < 0 ? 0 : Math.min(4095, seq + 1)` — 그 목록에서의 순번 + 1(0 없음 · 4095 넘침).
pub fn nth_of(seq: &V) -> f64 {
    if seq.is_nullish() || lt(seq, &V::Num(0.0)) { 0.0 } else { js::min(&[4095.0, n(&js::add(seq, &V::Num(1.0)))]) }
}
/// `styleWith(style, alt, seq)`(strips.mjs 19줄) — style에 함께 싣는 값(계약 6-2): 비트 14 번갈아 짙기(is-alt) · 15 ~ 26 그 목록에서의 순번 + 1.
/// power.mjs의 `styleWith(style, seq)`는 alt가 없는 같은 식(`alt = false` · seq는 수).
pub fn style_with(style: i32, alt: bool, seq: &V) -> i32 { style | (if alt { 1 << 14 } else { 0 }) | js::to_i32(nth_of(seq)).wrapping_shl(15) }

/// `cellStyle(c)`(strips.mjs 29 ~ 35줄) — 칸 하나의 style 가운데 칸 자료에서 곧바로 나오는 몫.
pub fn cell_style(c: &V) -> i32 {
    if !tv(c) { return 0; }
    let cert = c.get("certainty");
    (if c.bool("startUnknown") { st::UNK_S } else { 0 })
        | (if c.bool("endUnknown") || c.bool("endYAuto") { st::UNK_E } else { 0 })
        | (if is(&cert, "estimated") { st::ESTIMATED } else if is(&cert, "legend") { st::LEGEND } else { 0 })
        | (if c.bool("startRange") || c.bool("endRange") { st::RANGE } else { 0 })
        | (if c.bool("alternatives") && c.get("alternatives").bool("length") { st::ALT } else { 0 })
}

/// base.mjs `minute(y)` — 해가 수(유한)가 아니면 null(`Number.isFinite` — 바꾸지 않음), 아니면 정수 분.
/// `minute(v)`(base.mjs 51 ~ 58줄) 그대로 — 수가 아니거나 유한하지 않으면 None(JS null) · 유한한데 Date 범위(약 ±27만 년) 밖이면 Some(NaN)(JS의 NaN — `??`로 넘어가지 않고
/// 견줌은 거짓 · JSON에서 null). [`minute_of`]는 범위 밖도 None이라 `?? 대체값`을 쓰는 자리(리메이크 3단계 거울 검토가 찾음)에서는 이것을 쓴다.
pub fn minute_js(v: &V) -> Option<f64> { match v { V::Num(x) if x.is_finite() => Some(js::minute(*x).map_or(f64::NAN, |m| m as f64)), _ => None } }
pub fn minute_of(v: &V) -> Option<f64> { match v { V::Num(x) => js::minute(*x).map(|m| m as f64), _ => None } }
/// [`minute_of`]를 JS 값으로(null 또는 수 — 템플릿 글 · 견줌에 쓰고, `Math.max`에 넣을 때 `n()`은 null을 0으로).
pub fn minute_val(v: &V) -> V { minute_of(v).map_or(V::Null, V::Num) }

/// `x == null || !isFinite(x) ? fallback : x`(전역 `isFinite` — 글이면 수로 바꿔 봄).
pub fn finite_or(x: V, fallback: V) -> V { if x.is_nullish() || !js::to_num(&x).is_finite() { fallback } else { x } }

/// JSON 값의 참거짓(JS `!!x` — null · false · 0 · NaN · 빈 글이 거짓).
pub fn jtruthy(v: &Value) -> bool {
    match v { Value::Null => false, Value::Bool(b) => *b, Value::Number(x) => x.as_f64().is_some_and(|x| x != 0.0), Value::String(t) => !t.is_empty(), _ => true }
}
/// JSON 값이 그 수와 엄격히 같은가(`x === k`).
pub fn jis(v: &Value, k: f64) -> bool { v.as_f64() == Some(k) }

/// `idOf(uid)`(hangs.mjs 46줄 · links.mjs 31줄 — 같은 몸) — `bandOf.has(uid) ? bandOf.get(uid) + 1 : 0`: 띠 번호(`out.periods`의 순번 + 1 · 없으면 0).
/// `+`는 JS 뜻 그대로(`js::add`). bandOf가 Map이 아니면 JS는 `.has`에서 TypeError — 오류. (과제 Y — 갈래 B 검토 Minor: hangs는 수로, links는 JS 값으로 돌려주던 꼴을 하나로.)
pub fn band_id(band_of: &V, uid: &V) -> crate::Result<V> {
    let V::Map(m) = band_of else { return Err("shared.bandOf가 Map이 아닙니다 — JS라면 .has에서 멈춤".into()) };
    Ok(if m.has(uid) { js::add(&m.get(uid), &V::Num(1.0)) } else { V::Num(0.0) })
}

/// 렌즈의 공용 칸 단 갈래 '지도자'(`LENS_BAND.leader` — lens.mjs) — 렌즈가 지도자 칸을 내린 자리. lens가 싣고 power의 늦은 차례가 그 칸에 명목 비트를 켠다
/// (16b 검토 ③ Minor 8 — 예전엔 power가 lens를 불렀다).
pub const LENS_BAND_LEADER: i32 = 4;

/// 모듈을 도는 동안 남은 잘못(`model::util::fault` — JS라면 TypeError로 멈췄을 곳)을 그 모듈의 오류로(조용히 다른 답을 내지 않게 — 과제 Y).
/// 내보내기의 모듈 돌리기(`export::run_one`)가 모듈마다 끝에서 부른다(16b 넘겨받은 틀 손질 — 모듈이 오류로 돌아가면 남은 잘못은 거두고 그 오류가 나간다).
/// 모듈 안에서 몫 하나를 끝낸 자리에서 먼저 부르는 곳(docs의 날짜 글)도 있다. REPLAY(variants · boards)는 다시 돌린 모듈마다 따로 본다.
pub fn fault_check(module: &str) -> crate::Result<()> {
    match take_fault() { Some(f) => Err(format!("{module} 모듈 — {f}").into()), None => Ok(()) }
}

/// JS `try { 켬 } finally { 되돌림 }`에서 나가는 것(16b 틀 손질 검토 — boards의 판 하나 · lens의 렌즈 켬 배치가 함께): 되돌림이 남긴 잘못(`restored`)이 있으면
/// 그것(JS finally가 던지면 앞의 것을 덮는다), 아니면 try의 오류, try가 Ok인데 남긴 잘못(`pending` — JS라면 try 안에서 이미 던졌을 것: 되돌리기 전에 거둬
/// 둔다)이 있으면 그것, 아니면 try의 값. try가 오류면 `pending`은 버린다(오류가 원래 까닭 — 묵은 잘못이 그 글을 가리지 않게).
/// 잘못의 글은 `<on 또는 off> — <잘못>(JS라면 TypeError)`.
/// **부르는 차례**(16b 검토 ③ Minor 2 — 이 함수는 잘못 칸을 만지지 않으므로 차례는 부르는 쪽의 약속): ① try 몸 → ② `pending = take_fault()`(되돌리기 **전**) →
/// ③ 되돌림 → ④ `restored = take_fault()`를 넘김. ②를 ③ 뒤로 미루면 try의 잘못이 되돌림의 것으로 갈린다(`boards::board_one` · `lens::contribute`가 이 차례).
pub fn try_finally<T>(tried: crate::Result<T>, pending: Option<String>, restored: Option<String>, on: &str, off: &str) -> crate::Result<T> {
    if let Some(msg) = restored { return Err(format!("{off} — {msg}(JS라면 TypeError)").into()); }
    match (tried, pending) {
        (Err(e), _) => Err(e),
        (Ok(_), Some(msg)) => Err(format!("{on} — {msg}(JS라면 TypeError)").into()),
        (Ok(x), None) => Ok(x),
    }
}

/// `out.periods[i]` — 배열 자리(0 이상의 정수 · 범위 안)면 그 띠, 아니면 undefined(None). (power · lens가 함께 — 16b 층 손질로 power에서 옮김)
pub fn band_at(out: &serde_json::Value, i: &V) -> Option<serde_json::Value> {
    match i { V::Num(x) if *x >= 0.0 && x.fract() == 0.0 => out["periods"].get(*x as usize).cloned(), _ => None }
}
/// 띠를 읽는 자리: undefined면 JS의 TypeError(`band.end`)처럼 오류.
pub fn band_or_err<'a>(band: &'a Option<serde_json::Value>, p: &V) -> crate::Result<&'a serde_json::Value> {
    band.as_ref().ok_or_else(|| format!("띠 {}의 순번(shared.bandOf)이 out.periods 밖입니다(JS라면 TypeError)", js::to_str(&p.get("uid")).as_str()).into())
}

/// JS `x.has(k)` — Set · Map(둘 다 `has`가 있다)이면 그 답, 그 밖이면 None(JS는 TypeError). `tr.foldedRows` · `hiddenRows` · `memberRows`의 `.has(row)`
/// (labels · power · hangs · links · figures)를 한 판단으로(16b 넘겨받은 틀 손질 — 예전엔 Set만 받는 곳과 Map도 받는 곳이 섞였다).
/// 오류로 낼지(그 자리에서 멈춤 — [`has_or_err`]) 잘못으로 남길지(power)는 부르는 쪽.
pub fn has_of(x: &V, k: &V) -> Option<bool> {
    match x {
        V::Set(s) => Some(s.has(k)),
        V::Map(m) => Some(m.has(k)),
        _ => None,
    }
}

/// [`has_of`]를 그 자리에서 멈추는 꼴로: `has`가 없으면(Set · Map이 아님) 오류 — `what`은 JS의 그 값 이름(예: `tr.foldedRows`).
pub fn has_or_err(x: &V, k: &V, what: &str) -> crate::Result<bool> {
    has_of(x, k).ok_or_else(|| format!("{what}가 Set · Map이 아닙니다 — JS라면 .has에서 멈춤").into())
}

/// `some(v)`(docs.mjs 74줄 · metro.mjs 31줄) — 빈 것(없음 · 빈 글 · 빈 목록 · 빈 표(Map · Set은 `Object.keys`가 비어 빈 표))은 null, 아니면 그 값.
pub fn some(v: &V) -> V {
    let empty = match v {
        V::Undef | V::Null => true,
        V::Str(x) => x.is_empty(),
        V::Arr(a) => a.is_empty(),
        V::Obj(o) => o.is_empty(),
        V::Map(_) | V::Set(_) => true,
        _ => false,
    };
    if empty { V::Null } else { v.clone() }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// (갈래 A strips의 단위 검사를 옮겨 옴 + power의 alt 없는 꼴)
    #[test]
    fn lod_and_style_follow_strips_mjs() {
        assert_eq!(lod_of(0.0), 0.0);
        assert_eq!(lod_of(-5.0), 0.0);
        assert_eq!(lod_of(f64::NAN), 0.0);
        assert_eq!(lod_of(2.0), 2.0); // 16 >= 4²
        assert_eq!(lod_of(1e12), 14.0);
        assert_eq!(style_with(3, true, &V::Num(0.0)), 3 | (1 << 14) | (1 << 15));
        assert_eq!(style_with(0, false, &V::Null), 0);
        assert_eq!(style_with(0, false, &V::Num(-1.0)), 0);
        assert_eq!(style_with(0, false, &V::Num(9999.0)), 4095 << 15);
        assert_eq!(style_with(0, false, &V::Num(f64::NAN)), 0); // power: Math.min(4095, NaN) | 0 = 0
    }
}

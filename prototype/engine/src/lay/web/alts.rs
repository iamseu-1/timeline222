//! 이설 — `js/core.js`의 `HT.altSpan` · `altFlipSide` · `HT.altFlipped` · `HT.altDated` · `altEdges`(과제 Y가 모은 판).
//! **몸은 읽기 층 [`crate::lay::read::alts`]에 있다**(16b 층 손질 — 읽기(`read::cells`의 `altFlipSide`)가 부르므로: 예전엔 `read::cells` → `web::alts` → `model::util`로
//! 층이 거꾸로 섰다). 여기서는 모듈(strips · hangs · figures)이 쓰던 이름 그대로 다시 내보내기만 한다 — 동작은 그대로.
//!
//! 모은 판(과제 Y): 갈래 A(strips)의 판 — 짝을 돌려주는 `altFlipSide`(읽기의 뺀 까닭 글이 쓴다) · 진행 중일 때 JS `o.end = o.endAt = undefined`의 차례(`endAt` → `end`).
//! 버린 판과의 차이: 갈래 B(figures)는 참거짓만 돌려주고 진행 중이면 `end` → `endAt` 차례로 비웠다(keys에 `end`가 없을 때만 열쇠 차례가 갈림 — 부르는 곳은 늘 `end`를 줌) ·
//! 갈래 C(`docs/when.rs`)는 열쇠를 start · end로 고정했다(같은 몸).
pub use crate::lay::read::alts::{alt_dated, alt_edges, alt_flip_side, alt_flipped, alt_span, alts_of, KEYS};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lay::js::V;
    use crate::lay::model::o;
    use crate::lay::model::util::n;

    /// (갈래 A strips의 단위 검사를 옮겨 옴)
    #[test]
    fn alt_span_fills_from_base() {
        let a = V::Obj(o! { "start" => 10.0 });
        let base = V::Obj(o! { "start" => 5.0, "end" => 20.0, "endUnknown" => true, "ongoing" => false });
        let f = alt_span(&a, &base, &KEYS);
        assert!(f.get("own").bool("start") && !f.get("own").bool("end"));
        assert_eq!(n(&f.get("start")), 10.0);
        assert_eq!(n(&f.get("end")), 20.0);
        assert!(f.bool("endUnknown") && !f.bool("ongoing"));
        let g = alt_span(&V::Obj(o! { "start" => 1.0, "ongoing" => true }), &base, &KEYS);
        assert!(g.bool("ongoing") && g.get("end").is_undef() && g.has("endAt"));
        // `o.end = o.endAt = undefined` — keys에 end가 없으면 endAt이 먼저 생긴다(JS 열쇠 차례)
        let h = alt_span(&V::Obj(o! { "start" => 1.0, "ongoing" => true }), &base, &["start"]);
        let keys: Vec<String> = h.keys().iter().map(|k| k.as_str().into_owned()).collect();
        assert_eq!(keys, ["own", "start", "startAt", "ongoing", "endAt", "end"]);
    }
}

//! 칸의 종류 · 구간 · 경계 · 참조 — `js/core.js`(SHA-256 앞 12자 `9c786cf58566` — 저장소의 LF 바이트)를 줄 그대로:
//! - 613 ~ 636 · 1027 · 1381줄 `HT.CELL_KINDS`(id · 목록 열쇠 · 이름 · 문서를 다는가 — 그 차례) → [`CELL_KINDS`] · [`CELL_KIND_IDS`] · `HT.cellKind` → [`cell_kind`]
//! - 657 ~ 664줄 `HT.cellSpan` → [`cell_span`](`rawCellSpan`은 `model::bounds::raw_cell_span` · `HT.cellsOf`는 `model::bounds::cells_of`)
//! - 667줄 `HT.cellToNow` → [`cell_to_now`] · 795줄 `HT.cellBound` → [`cell_bound`] · 797 ~ 804줄 `HT.cellRefOf` → [`cell_ref_of`]
//!
//! 모은 판(과제 Y): 갈래 A(strips)의 판. 버린 판과의 차이 —
//! - 갈래 B(links)의 `cellSpan`은 칸 참조를 주지 않은 길(`ref === undefined` → `HT.cellRefOf`)을 옮기지 않아, `ref`가 undefined면 경계를 찾지 않고 `lo = c.start`로 갔다
//!   (부르는 `unionPairs`는 늘 `ref`를 줘서 닿지 않음). 답 객체의 열쇠 차례도 JS(`… hi, lo`)와 달랐다(값만 읽어 출력에는 없음).
//! - 갈래 C(docs)의 `cellBound`는 Map 값이 거짓(0 · '' · false)이어도 그 값을, 갈래 D(entities)의 `cellSpan`은 답을 구조체(`lo` · `hi` …)로 돌려줬다 —
//!   Map의 값은 늘 경계 객체라 닿지 않음. 같은 뜻 그대로 여기 하나로.
use crate::lay::js::{self, Obj, V};
use crate::lay::model::bounds::{cells_of, raw_cell_span};
use crate::lay::model::o;
use crate::lay::model::util::{index_of, or, tv};
use crate::lay::read;

/// `HT.CELL_KINDS` 표는 모델 층의 잎(`model::kinds`)에 둔다 — `model::util`도 쓰므로(16b 층 손질: 예전엔 model::util ↔ web::cells가 서로 가리킴). 여기서는 다시 내보내기만.
pub use crate::lay::model::kinds::{cell_kind, CellKind, CELL_KINDS, CELL_KIND_IDS};

/// `HT.cellBound(p, ref)`(795줄) — 모델이 채워 둔 칸 하나의 경계 `{ lo, hi, prev, next, succ }`(없으면 null). `p.cellBounds`는 열거되지 않는 속성(Map).
/// `p.cellBounds`가 참인데 Map이 아니면 JS는 `.get`에서 TypeError — 잘못으로 남기고 null(16b 넘겨받은 틀 손질 — 예전엔 조용히 null · 모델은 늘 Map을 둔다).
pub fn cell_bound(p: &V, r: &V) -> V {
    if !(tv(p) && tv(r) && tv(&p.get("cellBounds"))) { return V::Null; }
    let got = match p.get("cellBounds") {
        V::Map(m) => m.get(r),
        other => { crate::lay::model::util::fault(format!("cellBounds가 Map이 아닙니다({}) — JS라면 .get에서 TypeError", js::type_of(&other))); V::Undef }
    };
    or(got, V::Null)
}

/// `HT.cellRefOf(p, c)`(797 ~ 804줄) — 칸 객체 → 그 정권의 칸 참조('leader:3'). 모델의 칸 목록에 있는 그 칸이어야 한다(복사본이면 null).
pub fn cell_ref_of(p: &V, c: &V) -> V {
    if !tv(p) || !tv(c) { return V::Null; }
    for k in CELL_KIND_IDS {
        let i = index_of(&cells_of(p, k), c);
        if i >= 0.0 { return V::from(format!("{k}:{}", js::num_str(i))); }
    }
    V::Null
}

/// `HT.cellSpan(c, p, ref)`(657 ~ 664줄) — 칸이 연표에 놓이는 구간 `{ start, startAt, end, endAt, hi, lo }`(JS 답의 열쇠 차례 그대로 — `exact`는 지움).
/// `r`가 undefined면(JS `ref === undefined`) 그 정권의 칸 목록에서 같은 칸을 찾는다(`HT.cellRefOf`).
pub fn cell_span(rc: &read::Ctx, c: &V, p: &V, r: &V) -> Obj {
    let raw = raw_cell_span(rc, c, p);
    let sp = o! { "start" => raw.start, "startAt" => raw.start_at, "end" => raw.end, "endAt" => raw.end_at, "exact" => raw.exact, "hi" => raw.hi };
    let key = if r.is_undef() { cell_ref_of(p, c) } else { r.clone() };
    let b = cell_bound(p, &key);
    sp.set("lo", if tv(&b) { b.get("lo") } else { sp.get("start") });
    if tv(&b) { sp.set("hi", b.get("hi")); }
    sp.delete("exact");
    sp
}

/// `HT.cellToNow(c, p)`(667줄) — 칸의 끝이 진행 중인 정권의 끝(오늘)까지인지: 끝을 비워 정권의 끝으로 채운 칸(지도자 · 내각 · 연호, 다음 정도가 없는 도읍,
/// 시기 · 지위의 endPolity). `!!(p && p.ongoing && c && !c.endUnknown && !c.endYAuto && (c.endPolity || (c.end == null && !c.endYNext)))`.
pub fn cell_to_now(c: &V, p: &V) -> bool {
    tv(p) && p.bool("ongoing") && tv(c) && !c.bool("endUnknown") && !c.bool("endYAuto") && (c.bool("endPolity") || (c.get("end").is_nullish() && !c.bool("endYNext")))
}

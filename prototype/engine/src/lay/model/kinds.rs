//! `HT.CELL_KINDS` 표 — 칸 종류(id · 목록 열쇠 · 이름 · 문서를 다는가). 다른 모델 모듈을 쓰지 않는 잎이다: `model::util`(문서를 다는 칸의 목록) ·
//! `model::bounds`(칸 목록) · `web::cells`(다시 내보내기)가 함께 쓴다(16b 틀 손질 검토 — 예전엔 `model::bounds`에 두어 util ↔ bounds가 서로 가리켰다).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 613 ~ 628줄 `HT.CELL_KINDS`(넷) · 1027줄 시기 · 1381줄 지위(그 차례로 더함) → [`CELL_KINDS`] · [`CELL_KIND_IDS`] · `HT.cellKind` → [`cell_kind`]

/// `HT.CELL_KINDS`의 한 줄 — id · 목록 열쇠 · 이름 · 문서를 다는가(`doc !== false`).
#[derive(Clone, Copy, Debug)]
pub struct CellKind { pub id: &'static str, pub list: &'static str, pub name: &'static str, pub doc: bool }
/// `HT.CELL_KINDS`(613 ~ 628줄 넷 + 1027줄 시기 + 1381줄 지위 — 그 차례).
pub const CELL_KINDS: [CellKind; 6] = [
    CellKind { id: "leader", list: "leaders", name: "지도자", doc: true },
    CellKind { id: "cabinet", list: "cabinets", name: "내각", doc: true },
    CellKind { id: "era", list: "eras", name: "연호", doc: true },
    CellKind { id: "capital", list: "capitals", name: "도읍", doc: true },
    CellKind { id: "phase", list: "phases", name: "시기", doc: true },
    CellKind { id: "rank", list: "ranks", name: "지위", doc: false },
];
/// `HT.CELL_KINDS`의 id 차례 — `HT.cellRefOf`가 이 차례로 찾는다.
pub const CELL_KIND_IDS: [&str; 6] = [CELL_KINDS[0].id, CELL_KINDS[1].id, CELL_KINDS[2].id, CELL_KINDS[3].id, CELL_KINDS[4].id, CELL_KINDS[5].id];
/// `HT.cellKind(key)` — id로도 목록 열쇠로도.
pub fn cell_kind(key: &str) -> Option<CellKind> { CELL_KINDS.iter().copied().find(|k| k.id == key || k.list == key) }

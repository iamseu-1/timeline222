//! 글자 범위 — `js/core.js`(SHA-256 앞 12자 `9c786cf58566`)를 줄 그대로: 2591 ~ 2600줄 `mergeRanges` → [`merge_ranges`] · 2618 ~ 2635줄 `HT.GLYPH_BAND` → [`glyph_band`] ·
//! 2636 ~ 2638줄 `HT.GLYPH_WINDOW` → [`glyph_window`] · 2703 ~ 2714줄 `inRanges` → [`in_ranges`] · 2716 ~ 2723줄 `HT.glyphMissing` → [`glyph_missing`].
//!
//! 모은 판(과제 Y): 갈래 B(labels)와 갈래 D(entities)의 판을 합침 — 정렬은 B처럼 JS `sort`(V8 TimSort · 같은 처음은 차례대로 — D의 Rust 안정 정렬과 답이 같음) ·
//! 이어짐 견줌 `r[0] <= last[1] + 1`은 D처럼 넓은 수로(B의 `u32`는 끝이 `u32::MAX`인 범위에서 넘쳤다 — 코드 포인트 표에는 없음). 표는 한 번만 합쳐 둔다(B는 부를 때마다 합쳤다).
use crate::lay::js::{self, V};
use std::sync::OnceLock;

/// `mergeRanges(list)` — 겹치거나 이어진 범위를 합친 차례 목록 [[처음, 끝], …](끝 포함).
pub fn merge_ranges(l: &[(u32, u32)]) -> Vec<(u32, u32)> {
    let mut s: Vec<(u32, u32)> = l.iter().filter(|r| r.0 <= r.1).copied().collect();
    js::sort_by(&mut s, |a, b| f64::from(a.0) - f64::from(b.0));
    let mut out: Vec<(u32, u32)> = Vec::new();
    for r in s {
        match out.last_mut() {
            Some(last) if u64::from(r.0) <= u64::from(last.1) + 1 => last.1 = last.1.max(r.1),
            _ => out.push(r),
        }
    }
    out
}
/// `HT.GLYPH_BAND`의 원래 목록(띠 표 — 내장): 글자 그림판이 한 글자씩 그릴 수 있는 범위.
const GLYPH_BAND_RAW: [(u32, u32); 16] = [
    (0x20, 0x7e), // 라틴 기본(보이는 ASCII)
    (0xa0, 0x24f), // 라틴-1 보충 · 라틴 확장 A · B
    (0x2b0, 0x2ff), // 간격 조정 문자(하와이 ʻ오키나 U+02BB 등 — 2026-10-23 세계사 확장 점검 4-3 · 웹 core.js와 함께)
    (0x370, 0x3ff), // 그리스
    (0x400, 0x4ff), // 키릴
    (0x1e00, 0x1eff), // 라틴 확장 추가(베트남어처럼 미리 합친 글자)
    (0x1f00, 0x1fff), // 그리스 확장(고전 그리스어의 숨표 · 악센트 붙은 글자 — 2026-10-23)
    (0x2010, 0x2027), // 일반 문장 부호 — 줄표 · 따옴표 · 가운뎃점 · 줄임표(보이지 않는 방향 · 이음 표시는 뺌)
    (0x2030, 0x205e),
    (0x3000, 0x303f), // CJK 기호 · 문장 부호
    (0x3040, 0x30ff), // 가나(히라가나 · 가타카나)
    (0x3130, 0x318f), // 한글 호환 자모
    (0x4e00, 0x9fff), // 기본 한자(CJK 통합 한자)
    (0xac00, 0xd7a3), // 한글 음절
    (0xff01, 0xff60), // 전각 꼴(전각 괄호 · 숫자)
    (0xffe0, 0xffe6),
];
/// `HT.GLYPH_BAND`(띠 표 — 합친 꼴).
pub fn glyph_band() -> &'static [(u32, u32)] {
    static T: OnceLock<Vec<(u32, u32)>> = OnceLock::new();
    T.get_or_init(|| merge_ranges(&GLYPH_BAND_RAW))
}
/// `HT.GLYPH_WINDOW`(창 표 — 띠 표 + 히브리 · 아랍 · 일반 문장 부호 전부).
pub fn glyph_window() -> &'static [(u32, u32)] {
    static T: OnceLock<Vec<(u32, u32)>> = OnceLock::new();
    T.get_or_init(|| {
        let mut all = glyph_band().to_vec();
        all.extend([(0x590, 0x5ff), (0x600, 0x6ff), (0x750, 0x77f), (0x8a0, 0x8ff), (0x2000, 0x206f), (0xfb1d, 0xfb4f), (0xfb50, 0xfdff), (0xfe70, 0xfefe)]);
        merge_ranges(&all)
    })
}
/// `inRanges(table, cp)` — 이분 찾기.
pub fn in_ranges(table: &[(u32, u32)], cp: u32) -> bool {
    let (mut lo, mut hi) = (0i64, table.len() as i64 - 1);
    while lo <= hi {
        let mid = (lo + hi) >> 1;
        let r = table[mid as usize];
        if cp < r.0 { hi = mid - 1; } else if cp > r.1 { lo = mid + 1; } else { return true; }
    }
    false
}
/// `HT.glyphMissing(text, table)` — 표에 없는 글자들의 코드 포인트(겹치지 않게 · 나온 차례). 글은 `String(text ?? '')`를 코드 포인트로(`for … of` — 외톨이 서로게이트는 그 코드 단위).
pub fn glyph_missing(text: &V, table: &[(u32, u32)]) -> Vec<u32> {
    let units = js::to_str(&js::nullish(text.clone(), V::from(""))).to_units();
    let mut out: Vec<u32> = Vec::new();
    let mut i = 0;
    while i < units.len() {
        let u = u32::from(units[i]);
        let cp = if (0xd800..0xdc00).contains(&u) && i + 1 < units.len() && (0xdc00..0xe000).contains(&u32::from(units[i + 1])) {
            i += 1;
            0x10000 + ((u - 0xd800) << 10) + (u32::from(units[i]) - 0xdc00)
        } else { u };
        i += 1;
        if !in_ranges(table, cp) && !out.contains(&cp) { out.push(cp); }
    }
    out
}

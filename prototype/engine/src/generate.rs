//! 가상 자료 생성기 3. 난수 없이 고정 산술 순열만 써서, 같은 사건 수면 언제 만들어도 같은 자료가 나온다(씨앗 20260921).
//! 실제 역사 이름은 쓰지 않는다. 자료집 8(여덟째는 제 트랙 없이 남의 줄에 사건만 덧붙임) · 트랙 56 · 줄 252 · 띠 수만 개 · 칸 수십만 개.
//! 3단계의 표현(트랙 색 · 민족 묶음 · 분류 · 나라별 시대 구분 줄 · 띠와 칸의 표현 값 · 사건의 분류와 날짜 글 · 일반 항목)까지 품는다.
use crate::builder::{AxisCellIn, Builder, CellIn, EventIn, GroupIn, ItemIn, PeriodIn, RowExtra, RowGeo, TrackIn};
use crate::{Result, DAY};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{fs, path::Path, time::Instant};

pub const SEED: i64 = 20_260_921;
const YEAR: i64 = 525_960; // 365.25일
const T0: i64 = -1_300_000 * DAY; // 기원전 1590년 무렵
const T1: i64 = 20_000 * DAY; // 2024년 무렵
const DENSE_DAY: i64 = 18_500;
const PALETTE: [u32; 10] = [0xc8b193, 0x9dbea8, 0xabb3c9, 0xbbacc8, 0xdab195, 0xb6c398, 0xa0bcc5, 0xa4b1b7, 0xbba395, 0xd1a9b9];
/// 트랙 색: 파스텔 12색을 돌려 쓴다.
const TRACK_PALETTE: [u32; 12] = [0xd9c2a7, 0xbcd8c1, 0xc3cbe6, 0xd7c3e3, 0xefd3b4, 0xcfe0b0, 0xb6d4dd, 0xc6cfd4, 0xe0c6b6, 0xeec8d6, 0xc9ddd2, 0xdcd3ab];
const CATEGORIES: [(&str, &str, u32); 5] = [
    ("govern", "다스림", 0x8f7fb0), ("build", "지음", 0x6f9a86), ("trade", "주고받음", 0xb08a5a), ("lore", "이야기", 0x9a6f8a), ("sky", "하늘글", 0x5f86ad),
];
const HEADS: [&str; 12] = ["별여울", "해솔", "은빛", "여울", "나루", "푸른", "새벽", "달무리", "솔바람", "물안개", "하늘못", "긴내"];
const TAILS: [&str; 8] = ["국", "연맹", "나루", "고을", "성", "벌", "마루", "터"];
const GIVEN: [&str; 16] = ["가람", "나래", "다온", "라온", "마루", "바다", "새론", "아라", "자올", "차미", "하늬", "보늬", "미르", "도담", "슬기", "한울"];
const CLANS: [&str; 6] = ["윗물 겨레", "아랫벌 겨레", "먼바다 겨레", "들마루 겨레", "숲그늘 겨레", "찬비 겨레"];
const ERAS: [&str; 8] = ["첫길", "돌바람", "긴물", "잿빛", "새싹", "높뫼", "늦볕", "끝나루"];
const BODY: &str = "별여울의 나루 기록. 푸른 배가 은빛 나루에 머물렀다. 星河 기록과 두 글자 이름 해솔, 별칭 여울을 함께 보관한다. 실제 역사 자료가 아닌 검사 원문이다.";
const SHORT: &str = "가상 기록집의 원문과 출처를 연결한 사건. 은빛 나루의 별칭은 여울이다.";

/// 줄 쌓기의 상수(계약 3절). 띠 위의 틈 19 = gap 8 + tab 11.
const TAB_GAP: i64 = 19;
const INSET: i64 = 4;
const SLOT_GAP: i64 = 3;
const LINE: i64 = 21;
const RAIL_PITCH: i64 = 7;

/// 줄 하나가 어떤 단을 품는가. 자리는 여기서 계약 3절대로 쌓는다.
#[derive(Clone, Copy)]
struct Shape {
    dynasty: bool,
    phase: i64,
    rank: i64,
    leader: bool,
    cabinet: bool,
    lines: i64,
    rails: i64,
    fig: i64,
    fig_wide: i64,
    dep: i64,
    organ: bool,
    zones: i64,
    hem: i64,
}

/// 계약 3절의 띠 안 쌓기. 돌려주는 자리는 줄 안 상대값(없는 단은 −1)이고, height는 띠 위의 틈과 띠 아래 탭까지 품는다.
fn geo3(s: &Shape) -> RowGeo {
    let mut y = TAB_GAP + INSET;
    let mut end = y;
    let step = |height: i64, gap: i64, y: &mut i64, end: &mut i64| -> i64 {
        let top = *y;
        *end = top + height;
        *y = *end + gap;
        top
    };
    let dyn_top = if s.dynasty { step(15, SLOT_GAP, &mut y, &mut end) } else { -1 };
    for _ in 0..s.phase {
        step(13, 2, &mut y, &mut end);
    }
    if s.rank != 0 {
        step(13, SLOT_GAP, &mut y, &mut end);
    }
    let lead_top = if s.leader { step(20, SLOT_GAP, &mut y, &mut end) } else { -1 };
    let cab_top = if s.cabinet { step(17, SLOT_GAP, &mut y, &mut end) } else { -1 };
    let text_top = step(s.lines * LINE, 0, &mut y, &mut end);
    let rail_top = step(s.rails * RAIL_PITCH, 0, &mut y, &mut end);
    if s.fig > 0 {
        y += SLOT_GAP;
        step(s.fig * 15 + (s.fig - 1) * 2, SLOT_GAP, &mut y, &mut end);
    } else {
        y += 1;
    }
    if s.dep > 0 {
        step(s.dep, SLOT_GAP, &mut y, &mut end);
    }
    let organ_top = if s.organ { step(15, 0, &mut y, &mut end) } else { -1 };
    let band_h = end + INSET - TAB_GAP;
    let cut = (if s.zones > 0 { s.zones * 14 + 3 } else { 0 }) + (if s.hem != 0 { 12 } else { 0 });
    RowGeo { height: TAB_GAP + band_h + cut, band_top: TAB_GAP, band_h, dyn_top, lead_top, cab_top, text_top, text_lines: s.lines, rail_top, organ_top }
}

pub fn generate(path: &Path, count: i64, fixtures: &Path, search: bool) -> Result<Value> {
    if !(1..=10_000_000).contains(&count) {
        return Err("이번 생성기의 시험 범위는 1~1,000만입니다".into());
    }
    let started = Instant::now();
    let mut b = Builder::create(path)?;
    if !search {
        b = b.without_search();
    }
    let root = path.parent().ok_or("자료 폴더 필요")?;
    fs::create_dir_all(root.join("originals"))?;

    let mut packs = Vec::new();
    for i in 0..8 {
        packs.push(b.pack(&if i == 7 { "별여울 덧붙임 기록집".to_owned() } else { format!("별여울 가상 기록집 {}", i + 1) }, None)?);
    }
    for (ord, (key, name, color)) in CATEGORIES.iter().enumerate() {
        b.category(packs[0], ord as i64, key, name, *color)?;
    }
    let source = b.source("별여울 원문 · 첫째 권", BODY)?;
    for (name, kind) in [("별여울-원문.pdf", "pdf"), ("별여울-삽화.png", "image"), ("별여울-본문.txt", "text")] {
        let bytes = fs::read(fixtures.join(name))?;
        let sha = format!("{:x}", Sha256::digest(&bytes));
        let rel = format!("originals/{sha}.{}", name.rsplit('.').next().unwrap());
        fs::write(root.join(&rel), &bytes)?;
        b.file(source, kind, &rel, &sha, bytes.len() as i64)?;
    }

    // 트랙 56(자료집 1~7에 8개씩) · 트랙마다 줄 4 또는 5. 단(왕조 · 지도자 · 내각 · 기관)은 트랙 단위로 정한다.
    let mut row_pack: Vec<i64> = Vec::new();
    let mut row_track: Vec<usize> = Vec::new();
    let mut row_shape: Vec<Shape> = Vec::new();
    let mut track_ids: Vec<i64> = Vec::new();
    let mut track_rows: Vec<Vec<i64>> = Vec::new();
    let mut groups = 0i64;
    for t in 0..56usize {
        let pack = packs[t / 8];
        let (dynasty, organ, rails) = (t % 2 == 0, t % 3 != 2, if t % 5 == 0 { 3 } else { 2 });
        let track = b.track_full(&TrackIn {
            pack, name: &format!("{} {} 갈래", HEADS[t % 12], TAILS[(t / 12) % 8]), color: TRACK_PALETTE[t % 12],
            dynasty: i64::from(dynasty), leader: 1, cabinet: 1, organ: i64::from(organ), rail_levels: rails, key: "",
        })?;
        let count_rows = 4 + t % 2;
        let mut rows = Vec::new();
        for r in 0..count_rows {
            // 새 단은 10~20% 안팎으로만 켠다 — 지금 연표에서도 늘 켜져 있는 줄은 드물다.
            let cats: Vec<i64> = if (t + r) % 6 == 0 { vec![0, 2] } else { Vec::new() };
            let fig = if (t * 3 + r) % 9 == 0 { 2 } else { 0 };
            let shape = Shape {
                dynasty, phase: if (t + r) % 7 == 0 { 1 } else { 0 }, rank: i64::from((t + r) % 11 == 0), leader: true, cabinet: true,
                lines: if cats.is_empty() { 2 } else { cats.len() as i64 }, rails,
                // fig는 자동 밀도의 값, fig_wide는 '넉넉하게'에서 늘어나는 줄만 하나 더(계약 6-5절).
                fig, fig_wide: if (t + r) % 4 == 0 { fig + 1 } else { fig },
                dep: if (t + 2 * r) % 13 == 0 { 2 * 13 - 1 } else { 0 },
                organ, zones: i64::from((t + r) % 5 == 0), hem: i64::from((t + r) % 8 == 0),
            };
            // 민족 묶음의 첫 줄(줄 넷이면 0 · 2, 다섯이면 0 · 2에서 시작한다)
            let more = RowExtra {
                kind: if r + 1 == count_rows && t % 3 == 0 { 2 } else { i64::from(r % 4 == 3) },
                group_start: i64::from(r == 0 || r == 2), scope_pad: if t % 17 == 0 { 6 } else { 0 },
                phase: shape.phase, rank: shape.rank, cats, fig: shape.fig, fig_wide: shape.fig_wide, dep: shape.dep, zones: shape.zones, hem: shape.hem, variant: 0,
            };
            let row = b.row_full(track, &geo3(&shape), &more)?;
            rows.push(row);
            row_pack.push(pack);
            row_track.push(t);
            row_shape.push(shape);
        }
        // 묶음 2~3개: 줄 넷이면 민족 둘, 다섯이면 문화 하나가 민족 둘을 품는다(깊이 0~1).
        if count_rows == 4 {
            for (at, size) in [(0usize, 2i64), (2, 2)] {
                b.group(&GroupIn { track, depth: 0, first_row: rows[at], row_count: size, name: CLANS[(t + at) % 6], color: TRACK_PALETTE[(t + at) % 12], kind: 0 })?;
                groups += 1;
            }
        } else {
            b.group(&GroupIn { track, depth: 0, first_row: rows[0], row_count: 5, name: &format!("{} 문화", HEADS[(t + 3) % 12]), color: TRACK_PALETTE[(t + 5) % 12], kind: 1 })?;
            for (at, size) in [(0usize, 2i64), (2, 3)] {
                b.group(&GroupIn { track, depth: 1, first_row: rows[at], row_count: size, name: CLANS[(t + at) % 6], color: TRACK_PALETTE[(t + at) % 12], kind: 0 })?;
                groups += 1;
            }
            groups += 1;
        }
        track_ids.push(track);
        track_rows.push(rows);
    }
    let rows = row_pack.len() as i64;

    let slice = (T1 - T0) / 12;
    for i in 0..12i64 {
        b.epoch(packs[0], T0 + i * slice, T0 + (i + 1) * slice - 1, PALETTE[(i % 10) as usize], &format!("{} 시대", ["첫째", "둘째", "셋째", "넷째", "다섯째", "여섯째", "일곱째", "여덟째", "아홉째", "열째", "열한째", "열두째"][i as usize]))?;
    }
    // 나라별 시대 구분 줄: 트랙 56 가운데 12개에 여덟 칸씩(kind 1 · 그 트랙의 줄).
    let mut axis_cells = 0i64;
    for t in (0..56usize).step_by(5) {
        let era = (T1 - T0) / 8;
        for i in 0..8i64 {
            let style = if i == 0 { 1 } else if i == 7 { 2 } else { 0 };
            b.axis_cell(&AxisCellIn {
                pack: packs[t / 8], kind: 1, track: Some(track_ids[t]), lane: 0, start: T0 + i * era, end: T0 + (i + 1) * era - 1,
                name: &format!("{} 때", ERAS[(i as usize + t) % 8]), color: PALETTE[((i + t as i64) % 10) as usize], style, strip: 0, seq: i,
            })?;
            axis_cells += 1;
        }
    }

    // 줄마다 띠를 이어 붙인다: 기간 3~60년 · 사이 틈 0~5년. 40번째마다 시작 또는 끝 미정.
    // 줄마다 (시작, 끝, 띠 번호)를 시간 순으로 모아 둔다 — 사건이 든 띠(events.band)를 이분 검색으로 찾는다.
    let (mut periods, mut cells, mut items, mut entities, mut k) = (0i64, 0i64, 0i64, 0i64, 0i64);
    let mut row_bands: Vec<Vec<(i64, i64, i64)>> = vec![Vec::new(); rows as usize];
    let mut labels = 0i64;
    for row in 0..rows {
        let shape = row_shape[row as usize];
        let track = row_track[row as usize];
        let mut t = T0;
        while t <= T1 {
            k += 1;
            let years = 3 + (k * k * 31 + k * 17 + SEED) % 58;
            let (start, end) = (t, t + years * YEAR - 1);
            let head = HEADS[(k % 12) as usize];
            let fuzzy = if k % 40 == 0 { 1 + (k / 40) % 2 } else { 0 };
            let name = format!("{head}{} {}", TAILS[((k / 12) % 8) as usize], k % 97 + 1);
            let uid = format!("v3-p-{k}");
            let id = b.period_full(&PeriodIn {
                pack: row_pack[row as usize], row, start, end, fuzzy, color: PALETTE[(k % 10) as usize], name: &name,
                // 표현 값은 0이 주다 — 열에 하나쯤만 0이 아니다.
                look: if k % 10 == 0 { 1 + (k / 10) % 7 } else { 0 },
                tag: if k % 37 == 0 { "전해 오는 이야기" } else { "" },
                sub: if k % 23 == 0 { 2 } else { 0 },
                // form(스키마 4)은 늘 0 — 값을 넣으면 타일 띠 구역이 열 10을 달아 앱의 고정 타일 · data/v3-100k가 바뀐다.
                uid: &uid, variant: 0, form: 0,
            })?;
            periods += 1;
            row_bands[row as usize].push((start, end, id));
            // 왼쪽 줄 이름 칸의 후보(계약 6-8절): 띠마다 하나.
            let year = |minute: i64| minute.div_euclid(YEAR) + 1970;
            b.row_label(row, start, end, id, &json!({"period":&uid,"track":track,"row":row,"kind":0,"name":&name,
                "years":format!("{}–{}", year(start), year(end)),"color":PALETTE[(k % 10) as usize],"start":start,"end":end,
                "cap":i64::from(k % 11 == 0),"member":0,"lanes":[],"count":0}).to_string())?;
            labels += 1;
            if k % 200 == 0 {
                b.entity(&uid, row_pack[row as usize], "period", &json!({"uid":&uid,"name":&name,"start":start,"end":end,"seed":SEED}).to_string())?;
                entities += 1;
            }
            if shape.dynasty && k % 5 == 0 {
                b.cell(id, 0, start, end, &format!("{head} 왕조"))?;
                cells += 1;
            }
            for (kind, base, spread, a, c) in [(1i64, 3i64, 23i64, 13i64, 7i64), (2, 1, 6, 11, 5)] {
                let (mut at, mut j) = (start, 0i64);
                while at <= end {
                    let until = (at + (base + ((k + j) * a + j * j * c) % spread) * YEAR - 1).min(end);
                    let name = if kind == 1 { format!("{}대 {}", j + 1, GIVEN[((k + j) % 16) as usize]) } else { format!("{head} 내각 {}", j + 1) };
                    b.cell_full(&CellIn {
                        period: id, kind, start: at, end: until, name: &name,
                        lane: i64::from((k + j) % 11 == 0), style: if (k + j) % 13 == 0 { 4 } else { 0 },
                        color: if (k + j) % 17 == 0 { PALETTE[((k + j) % 10) as usize] } else { 0 }, variant: 0,
                    })?;
                    cells += 1;
                    at = until + 1;
                    j += 1;
                }
            }
            if shape.organ && k % 7 == 0 {
                b.cell(id, 3, start + (end - start) / 3, start + (end - start) * 2 / 3, &format!("{head} 관청"))?;
                cells += 1;
            }
            // 일반 항목: 구역 16 속국 이름표(그 띠에 붙는 한 줄) · 구역 17 관계선(다음 줄까지 걸친다).
            if k % 30 == 0 {
                b.item(&ItemIn { pack: row_pack[row as usize], section: 16, row, row2: row, start, end, lod: None, ref_id: id, ref_kind: 1,
                    name: &format!("{head} 속국"), color: PALETTE[(k % 10) as usize], a: 1, b: 0, c: 0, d: 0, text2: "", variant: 0 })?;
                items += 1;
            }
            let last_row = *track_rows[track].last().unwrap();
            if k % 50 == 0 && row < last_row {
                b.item(&ItemIn { pack: row_pack[row as usize], section: 17, row, row2: row + 1, start, end: start, lod: Some(9), ref_id: id, ref_kind: 1,
                    name: "", color: 0x8a8f96, a: 1, b: 2, c: 0, d: 0, text2: "", variant: 0 })?;
                items += 1;
            }
            t = end + 1 + ((k * 7 + row) % 6) * YEAR;
        }
    }

    let (mut unknown, mut long, mut alternate, mut dense) = (0i64, 0i64, 0i64, 0i64);
    let total_days = (T1 - T0) / DAY;
    for id in 1..=count {
        let lane = (id * 17) % rows;
        let mut start = T0 + ((id * 104_729) % total_days) * DAY + id % 1440;
        if id % 10 == 0 {
            start = DENSE_DAY * DAY + id % 1440;
            dense += 1;
        }
        let duration = if id % 997 == 0 { long += 1; 200_000 * DAY } else if id % 17 == 0 { (id % 400) * DAY } else { 0 };
        let delta = if id % 101 == 0 { alternate += 1; 100 * DAY } else { 0 };
        let absent = id % 1009 == 0;
        if absent {
            unknown += 1;
        }
        let grand = id % 97 == 0;
        let title = if grand { format!("해솔 星河 나루의 긴 기록 {id:07}") } else { format!("별여울 기록 {id:07}") };
        let raw = json!({"id":format!("synthetic-{id}"),"unknown":absent,"alternative_minutes":delta,"seed":SEED}).to_string();
        // 이름 옆 날짜 글. 사건의 look은 아래 8비트가 분류 번호(0~4), 그 위 4비트가 모양이다.
        let year = start.div_euclid(YEAR) + 1970;
        let label = if absent { String::new() } else if year > 0 { format!("{year}년") } else { format!("기원전 {}년", 1 - year) };
        // 그 사건이 든 띠: 같은 줄에서 시작 시각을 품은 띠(띠는 시간 순 · 겹치지 않는다).
        let bands = &row_bands[lane as usize];
        let band = if absent { 0 } else {
            match bands.binary_search_by(|(from, to, _)| if *to < start { std::cmp::Ordering::Less } else if *from > start { std::cmp::Ordering::Greater } else { std::cmp::Ordering::Equal }) {
                Ok(at) => bands[at].2,
                Err(_) => 0,
            }
        };
        b.event(&EventIn {
            pack: if id % 8 == 0 { packs[7] } else { row_pack[lane as usize] },
            lane,
            start: (!absent).then_some(start),
            end: (!absent).then_some(start + duration),
            lo: (!absent).then_some(start - delta),
            hi: (!absent).then_some(start + duration + delta),
            importance: if grand { 3 } else if id % 7 == 0 { 2 } else { 1 },
            title: &title,
            body: if grand { BODY } else { SHORT },
            source: Some(source),
            raw: Some(&raw),
            look: id % 5 | ((id / 7) % 4) << 8,
            label: &label,
            rail: if duration >= 45 * DAY { id % 2 } else { 0 },
            uid: "",
            band,
            variant: 0,
        })?;
    }
    b.finalize(&[
        ("seed", SEED.to_string()), ("generator", "3".to_owned()), ("dense", dense.to_string()), ("long", long.to_string()),
        ("alternatives", alternate.to_string()), ("dense_day", DENSE_DAY.to_string()),
    ])?;
    Ok(json!({"events":count,"packs":8,"tracks":56,"rows":rows,"groups":groups,"categories":CATEGORIES.len(),"axis_cells":axis_cells,
        "periods":periods,"cells":cells,"items":items,"entities":entities,"row_labels":labels,"unknown":unknown,"long":long,"alternatives":alternate,"dense":dense,
        "seconds":started.elapsed().as_secs_f64(),"bytes":fs::metadata(path)?.len(),"search":search}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 줄_쌓기는_모두_켠_2판의_자리와_같다() {
        // 2판 생성기의 굳은 값: 왕조가 있는 줄과 없는 줄(글줄 2 · 막대 2단 · 기관 있음 · 인물 · 예속 · 탭 없음).
        let with = geo3(&with_shape());
        assert_eq!((with.height, with.band_top, with.band_h), (160, 19, 141));
        assert_eq!((with.dyn_top, with.lead_top, with.cab_top, with.text_top, with.rail_top, with.organ_top), (23, 41, 64, 84, 126, 141));
        let without = geo3(&Shape { dynasty: false, ..with_shape() });
        assert_eq!((without.height, without.band_h, without.dyn_top), (142, 123, -1));
        assert_eq!((without.lead_top, without.cab_top, without.text_top, without.rail_top, without.organ_top), (23, 46, 66, 108, 123));
    }

    fn with_shape() -> Shape {
        Shape { dynasty: true, phase: 0, rank: 0, leader: true, cabinet: true, lines: 2, rails: 2, fig: 0, fig_wide: 0, dep: 0, organ: true, zones: 0, hem: 0 }
    }

    #[test]
    fn 띠_아래_탭과_바탕_문화_이름은_줄_높이에만_더해진다() {
        let plain = geo3(&with_shape());
        let tabbed = geo3(&Shape { zones: 2, hem: 1, ..with_shape() });
        assert_eq!(tabbed.band_h, plain.band_h, "띠 자체의 높이는 그대로");
        assert_eq!(tabbed.height, plain.height + (2 * 14 + 3) + 12);
    }

    #[test]
    fn 시기와_지위와_인물과_예속은_아래_단을_밀어낸다() {
        let base = geo3(&with_shape());
        let more = geo3(&Shape { phase: 2, rank: 1, fig: 2, dep: 25, ..with_shape() });
        assert_eq!(more.lead_top - base.lead_top, 2 * (13 + 2) + 13 + 3);
        // 인물: 막대 뒤 '없으면 +1' 대신 +3 · 2×15+2 · +3, 예속: 25 + 3
        assert_eq!(more.band_h - base.band_h, 2 * (13 + 2) + 13 + 3 + (3 + 32 + 3 - 1) + (25 + 3));
    }
}

//! 내보내기 모듈 `calendar` — `prototype/scripts/export/calendar.mjs` 1 ~ 215줄(SHA-256 앞 12자 `832000855c1f`)을 줄 그대로 — 한 벌 P3 과제 12b(갈래 C · 앞자리 14/20).
//! 보조 달력(음력 · 중국 음력 · 이슬람력 · 움 알쿠라 · 페르시아력)의 **달의 시작 표**를 항목 기록 `{uid:'cal:<달력>', kind:'cal', json, pack: 0}`으로 싣는다.
//! Node는 ICU로 바로 뜨거나(`buildTable`) 미리 뜬 넓은 표(`calendar-cache.json`)에서 자른다(`sliceTable` — 잘라 낸 표는 바로 뜬 표와 글자까지 같다:
//! `calendar-cache-check.mjs`). Rust에는 ICU가 없으므로 `opts.calendar`의 표(`lay::cal::Tables::raw` — 계획 정한 것 #7)에서 `sliceTable` 규칙으로만 자르고,
//! 그 달력의 표가 없으면 거절한다("달력 표 없음 — …"). **표가 자료 범위를 다 덮지 못하면 표와 겹치는 구간만 싣는다**(판정 R61 — 처음에는 "달력 표 범위 밖"으로
//! 배치 전체를 거절해, 보조 달력을 쓰지 않는 DLC도 자료 해 ± 100년이 저장소 표(−3500 ~ 2500년 — 판정 R36) 밖이면 어디서도 넣을 수 없었다): 표 밖은 `note`에
//! '표 밖 생략'으로 적고, 겹치는 구간이 없으면 그 달력의 기록을 싣지 않는다(앱은 표가 없는 달력의 눈금을 비워 둔다 — `aux_calendar.dart`의 `AuxCalendarStore`).
//! 실제 보조 달력 **날짜**가 표 밖이면 여기가 아니라 날짜를 읽는 곳이 거절한다(`lay::cal::Tables::missed` — `lay::normalized` · `lay::ctx`).
//! Node와 다른 점(알려진 차이 — 계획 P3 '과제 calclip'): Node는 모자란 범위를 ICU로 다시 떠 표 밖 구간까지 싣는다. 정답지 견줌은 그 차이를 자료(`synth-calclip`)와
//! 칸(`cal:` 기록의 `json`)으로만 안다(`tests/common/oracle.rs`의 `cal_clip_known` — Rust 표가 Node 표의 이어진 한 토막인지 확인한 뒤 같게 둔다). `json` 글은 `js::stringify`(JS의 열쇠 차례).
//! 옮기지 않은 것(노드 전용 · ICU): `buildTable` · `warmTables` · `cachedTables`(파일 읽고 쓰기) · `cacheFile`. 알림의 `ms`(걸린 시간)는 0으로 적는다(배치 결과가 아님).
//! 함께 옮긴 웹 함수: `HT.cal.jdnCivil`(`lay::cal::jdn_civil`) · `HT.cal.CALENDARS`의 국제화 달력(`lay::cal::CALENDARS` — `supports`는 '표가 있는가'로).
use crate::lay::cal::{self, CALENDARS};
use crate::lay::ctx::Ctx;
use crate::lay::js::{self, Obj, V};
use crate::lay::model::o;
use crate::lay::model::util;
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 39줄 `PAD_YEARS` — 자료의 앞뒤로 더 떠 두는 햇수.
const PAD_YEARS: f64 = 100.0;

/// 48 ~ 60줄 `dataYears(model)` — 자료가 놓인 해의 범위(띠 · 사건 · 시대 구분 · 인물의 양 끝) ± 100년. 없으면 [1, 1].
fn data_years(model: &V) -> (f64, f64) {
    let (mut lo, mut hi) = (f64::INFINITY, f64::NEG_INFINITY);
    let mut see = |a: &V, b: &V| {
        if let V::Num(a) = a { if a.is_finite() && *a < lo { lo = *a; } }
        if let V::Num(b) = b { if b.is_finite() && *b > hi { hi = *b; } }
    };
    let nn = |x: V, y: V| if x.is_nullish() { y } else { x };
    for p in util::list(&model.get("periods")) {
        let a = if js::truthy(&p.get("startRange")) { p.get("startRange").get("0") } else { p.get("start") };
        let b = if js::truthy(&p.get("endRange")) { p.get("endRange").get("1") } else { p.get("endY") };
        see(&a, &b);
    }
    for e in util::list(&model.get("events")) { see(&e.get("start"), &nn(e.get("endY"), e.get("start"))); }
    for e in util::list(&model.get("epochs")) { see(&e.get("start"), &nn(e.get("endY"), e.get("end"))); }
    for f in util::list(&model.get("figures")) { see(&nn(f.get("birth"), f.get("start")), &nn(f.get("death"), f.get("endY"))); }
    if !lo.is_finite() || !hi.is_finite() { return (1.0, 1.0); }
    (lo.floor() - PAD_YEARS, hi.ceil() + PAD_YEARS)
}

/// `sliceTable`의 답 `{ start, year0, months, count, end }`(`bad`는 늘 '').
struct Cut { start: f64, year0: f64, months: String, count: usize, end: f64 }

/// 105 ~ 119줄 `sliceTable(wide, c, fromJ, toJ)` — 넓은 표에서 [fromJ, toJ)의 표를 잘라 낸다(`buildTable`과 글자까지 같은 답 — 첫 달은 fromJ가 든 달,
/// 해는 같은 셈: 달 1 · 윤달 아님마다 한 살 · 음력은 0년을 건너뜀). 넓은 표가 그 범위를 덮지 못하면 None.
fn slice_table(wide: &cal::RawTable, lunar: bool, from_j: f64, to_j: f64) -> Option<Cut> {
    if !(wide.start <= from_j) || !(to_j <= wide.end) { return None; }
    let months = wide.months.as_bytes();
    let n = months.len() / 2;
    let len_at = |k: usize| f64::from(months[k * 2 + 1]) - 48.0 + 29.0;
    let new_year = |k: usize| months[k * 2] == 67; // 'C' = 달 1 · 윤달 아님(encodeMonth)
    let (mut j, mut year, mut i) = (wide.start, wide.year0, 0usize);
    while i < n && j + len_at(i) <= from_j {
        j += len_at(i);
        i += 1;
        if i < n && new_year(i) { year = if lunar && year == -1.0 { 1.0 } else { year + 1.0 }; }
    }
    let (first, start, year0) = (i, j, year);
    while j < to_j && i < n { j += len_at(i); i += 1; }
    if j < to_j || first >= n { return None; }
    Some(Cut { start, year0, months: wide.months[first * 2..i * 2].to_string(), count: i - first, end: j })
}

/// 판정 R61: 자료 범위 [from_j, to_j) 가운데 표(`wide`)와 겹치는 구간 — 겹치지 않으면 None. 잘렸으면 `clipped`.
/// 겹치는 구간은 표 안이므로 [`slice_table`]이 늘 답한다(첫 달은 그 구간의 첫날이 든 달 · 끝은 표의 끝을 넘지 않는다).
fn overlap(wide: &cal::RawTable, from_j: f64, to_j: f64) -> Option<(f64, f64, bool)> {
    let (lo, hi) = (from_j.max(wide.start), to_j.min(wide.end));
    (lo < hi).then_some((lo, hi, lo > from_j || hi < to_j))
}

/// 181 ~ 215줄 `contribute(ctx, out)` — 국제화 달력마다 자료 범위의 표를 잘라 `cal:<달력>` 기록으로(표 밖은 생략 — 판정 R61 · 머리말).
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let (lo_year, hi_year) = data_years(&ctx.model);
    let from_j = cal::jdn_civil(lo_year, 1.0, 1.0);
    let to_j = cal::jdn_civil(if hi_year == -1.0 { 1.0 } else { hi_year + 1.0 }, 1.0, 1.0);
    let notes_cals = Obj::new();
    let mut bytes = 0usize;
    let mut digests: Vec<(String, &'static str)> = Vec::new();
    let mut rows = 0.0;
    // 표 밖 생략의 메모(Node의 `table.bad` 자리 — ICU가 달을 더 주지 못한 곳과 같은 뜻: 이 밖은 '모르는 범위').
    let clip_note = format!("표 밖 생략 — 자료 범위 {}년 ~ {}년 가운데 저장소 달력 표가 덮는 곳만 실음", js::num_str(lo_year), js::num_str(hi_year));
    // 122줄 `wantedCalendars` — 국제화 달력(ICU가 아는 것 — 여기서는 표가 있어야 하고, 없으면 거절)
    for c in CALENDARS.iter().filter(|c| c.intl.is_some()) {
        let wide = ctx.read.cal.raw(c.id).ok_or_else(|| format!("달력 표 없음 — 그 달력의 달 시작 표를 낼 수 없습니다({})", c.name))?;
        let Some((lo_j, hi_j, clipped)) = overlap(wide, from_j, to_j) else {
            // 겹치는 구간이 없다 — 이 달력의 기록은 싣지 않는다(알림에만).
            notes_cals.set(c.id, V::Obj(o! { "달" => 0.0, "글자" => 0.0, "ms" => 0.0, "표" => "표 밖 생략", "메모" => clip_note.as_str() }));
            continue;
        };
        let table = slice_table(wide, c.lunar, lo_j, hi_j).ok_or_else(|| format!("달력 표가 올바르지 않습니다({} · 날 번호 {} ~ {})", c.name, js::num_str(lo_j), js::num_str(hi_j)))?;
        let key = format!("{}|{}", js::num_str(table.start), table.months);
        let same = digests.iter().find(|(k, _)| *k == key).map(|(_, id)| *id);
        if same.is_none() { digests.push((key, c.id)); }
        let note: Vec<String> = [if clipped { clip_note.clone() } else { String::new() }, match same { Some(id) if id != c.id => format!("이 범위에서는 {id}와 같은 답이다"), _ => String::new() }]
            .into_iter().filter(|x| !x.is_empty()).collect();
        let body = o! {
            "cal" => c.id, "calName" => c.name, "lunar" => c.lunar, "prefix" => c.prefix,
            "from" => table.start, "to" => table.end, "year0" => table.year0, "count" => table.count,
            "months" => table.months.as_str(), "note" => note.join(" · "),
        };
        let text = js::stringify(&V::Obj(body));
        bytes += text.encode_utf16().count();
        crate::lay::export::arr_mut(out, "entities").push(json!({ "uid": format!("cal:{}", c.id), "kind": "cal", "json": text, "pack": 0 }));
        let one = o! { "달" => table.count, "글자" => text.encode_utf16().count(), "ms" => 0.0, "표" => "잘라 씀" };
        if !note.is_empty() { one.set("메모", note.join(" · ")); }
        notes_cals.set(c.id, V::Obj(one));
        rows += table.count as f64 * 24.0;
    }
    let notes = o! {
        "해범위" => V::Arr(js::Arr::new(vec![V::Num(lo_year), V::Num(hi_year)])), "달력" => V::Obj(notes_cals), "글자합" => bytes, "줄로실었다면" => rows,
    };
    ctx.notes.set("calendar", V::Obj(notes));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table(start: f64, end: f64) -> cal::RawTable { cal::RawTable { intl: String::new(), start, end, year0: 1.0, months: String::new() } }

    /// 판정 R64 · M2: 자료 범위 [from, to)와 표 [start, end)는 반열린 구간이다 — 맞닿기만 하면 겹치지 않고(표 밖), 한 달만 겹쳐도 겹친다.
    #[test]
    fn overlap_is_half_open_and_one_month_counts() {
        let wide = table(100.0, 200.0);
        // 맞닿기만 함: 자료 끝 = 표 시작 · 자료 시작 = 표 끝 → 겹침 없음(`lo < hi`가 `<=`면 빈 구간을 겹침으로 본다)
        assert_eq!(overlap(&wide, 0.0, 100.0), None, "자료 끝 = 표 시작");
        assert_eq!(overlap(&wide, 200.0, 300.0), None, "자료 시작 = 표 끝");
        assert_eq!(overlap(&wide, 0.0, 50.0), None, "표 앞에 완전히 떨어짐");
        assert_eq!(overlap(&wide, 250.0, 300.0), None, "표 뒤에 완전히 떨어짐");
        // 하루(한 달)만 겹침: 잘린 것으로 본다
        assert_eq!(overlap(&wide, 0.0, 101.0), Some((100.0, 101.0, true)), "표의 첫날만");
        assert_eq!(overlap(&wide, 199.0, 300.0), Some((199.0, 200.0, true)), "표의 마지막 날만");
        let one_month = table(100.0, 129.0);
        assert_eq!(overlap(&one_month, 128.0, 500.0), Some((128.0, 129.0, true)), "한 달짜리 표의 끝 하루");
        assert_eq!(overlap(&one_month, 100.0, 129.0), Some((100.0, 129.0, false)), "한 달짜리 표를 통째로 덮음");
        // 앞만 · 뒤만 · 양쪽 · 안 잘림
        assert_eq!(overlap(&wide, 50.0, 150.0), Some((100.0, 150.0, true)), "앞만 잘림(`clipped`가 `&&`면 놓친다)");
        assert_eq!(overlap(&wide, 150.0, 250.0), Some((150.0, 200.0, true)), "뒤만 잘림");
        assert_eq!(overlap(&wide, 50.0, 250.0), Some((100.0, 200.0, true)), "양쪽 잘림");
        assert_eq!(overlap(&wide, 100.0, 200.0), Some((100.0, 200.0, false)), "표와 꼭 같음 — 안 잘림");
        assert_eq!(overlap(&wide, 120.0, 180.0), Some((120.0, 180.0, false)), "표 안에 듦 — 안 잘림");
    }
}

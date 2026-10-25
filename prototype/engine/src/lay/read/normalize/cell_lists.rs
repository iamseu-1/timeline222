//! `HT.normalizePack` 안의 칸 읽기 — 4128 ~ 4284줄(과제 5b가 옮김 · 과제 5c 머리에 [`super`]에서 이 파일로 나눔 — 동작 그대로 · 섬긴 기록은 5c).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! (2026-10-25 맞춤 · 4단계 배치 갈래 걸음 4 · `core.js` `53696cece459`) 4334 ~ 4339줄 칸의 정통성(status — 지도자 · 내각 · 직위 줄 더의 칸만 · `HT.F4.statusId` = [`crate::lay::f4::status_id`] · 모르는 값은 알리고 뺌)
//! - 4128 ~ 4227줄 `readCells` · `readCapitals` · `readSuccList` · `warnPartOfUnknown` · `readUncertainty`([`Norm`] 메서드)
//!   (2026-10-24 · `core.js` `dfd5d5fa3fd9` — 4409줄 `readSuccList`: 몸은 그대로, 승계 한 줄의 방식(how)은 [`vocab::normalize_succ`]가 읽는다 · 리메이크 6단계 걸음 1)
//!   (2026-10-24 맞춤 · 리메이크 6단계 걸음 2 · `core.js` `b2e6b19490bf`) 4444 ~ 4519줄 `readCells` — 4455줄 이름 번호 읽기(`HT.readRegnal`) · 4482 ~ 4483줄 지도자 칸의 regnal(틀린 값은 알리고 뺌 — D2)
//! - 4230줄 `readNames`(쉼표 목록 — 시대 · 가문의 꼬리표가 부름 · 이 파일의 `name_list`)
//! - (5c) 4234줄 `FIGURE_DATE_WORDS`(`figure_date_word`) · 4235 ~ 4284줄 `readService`([`Norm`] 메서드)
use super::Norm;
use crate::lay::f4;
use crate::lay::js::{self, Obj, Str, V};
use crate::lay::read::{self as read, capital, cells, dates, vocab};

impl<'c> Norm<'c> {
    /// `readCells(list, label, kind, i, what)` — 지도자 · 내각 · 연호 같은 칸 목록. 지도자는 묘호(temple) · 시호(title) · 이름(given) · 대수(ordinal)를 따로 적을 수 있고,
    /// name이 없으면 묘호 → 시호 → 이름 순으로 대표 이름을 삼는다. 대수가 빠진 지도자는 앞 지도자에 이어 자동으로 매긴다. 시작 · 끝에 "미정"도 된다.
    /// 원본의 `.map` · `.map` · `.filter` · `.map`은 단계마다 목록 전체를 돈다 — 알림 차례(거른 것의 알림이 모두 먼저)가 그 차례를 따른다.
    pub(super) fn read_cells(&mut self, list: &V, label: &str, kind: &str, i: usize, what: &str) -> Vec<V> {
        /// 첫 `.map`의 칸(원본 객체의 열쇠 이름 그대로).
        struct Cell {
            name: Str, temple: Str, title: Str, given: Str, ordinal_unknown: bool, ordinal: Option<f64>, regnal: Option<f64>,
            start: Option<f64>, start_at: V, end: Option<f64>, end_at: V, error: Str, start_unknown: bool, end_unknown: bool,
            note: Str, dynasty: Str, rank: Str, house: Str, raw: V,
        }
        let ctx = self.ctx;
        let s = dates::str_of;
        let is_leader = what == "지도자";
        let t_of = |e: &Option<cells::Edge>| match e { Some(cells::Edge::Unknown(t)) => *t, Some(cells::Edge::Date(d)) => Some(d.t), None => None };
        let at_of = |e: &Option<cells::Edge>| match e { Some(cells::Edge::Date(d)) => d.at.clone().map_or(V::Null, V::Str), _ => V::Undef };
        let err_of = |e: &Option<cells::Edge>| match e { Some(cells::Edge::Date(d)) => d.error.clone().filter(|x| !x.is_empty()), _ => None };
        let cells_in: Vec<Cell> = dates::arr(list)
            .iter()
            .map(|c| match c { V::Arr(a) => cells::cell_of_tuple(a), c => js::or(c.clone(), V::Obj(Obj::new())) })
            .map(|c| {
                let sd = cells::read_cell_edge(ctx, &c, "start");
                let ed = cells::read_cell_edge(ctx, &c, "end");
                let ord = c.get("ordinal");
                Cell {
                    name: s(&c.get("name")), temple: s(&c.get("temple")), title: s(&c.get("title")), given: s(&c.get("given")),
                    ordinal_unknown: matches!(c.get("ordinalUnknown"), V::Bool(true)) || cells::is_unknown_ordinal(&ord), // 대수 미상 (묶음 5 · 4번)
                    ordinal: if read::is_empty_str(&ord) || ord.is_nullish() || !js::to_num(&ord).is_finite() { None } else { Some(js::round(js::to_num(&ord))) },
                    regnal: capital::read_regnal(&c.get("regnal")), // 이름 번호 (6단계 D2 — 양의 정수 · 틀리면 NaN: 아래에서 알리고 뺌)
                    start: t_of(&sd), start_at: at_of(&sd), end: t_of(&ed), end_at: at_of(&ed),
                    error: err_of(&sd).or_else(|| err_of(&ed)).unwrap_or_default(),
                    start_unknown: matches!(sd, Some(cells::Edge::Unknown(_))), end_unknown: matches!(ed, Some(cells::Edge::Unknown(_))),
                    note: s(&c.get("note")), dynasty: s(&c.get("dynasty")),
                    rank: s(&c.get("rank")), // 지위 (지도자만)
                    house: s(&c.get("house")),
                    raw: c, // 확실성 · 연대 폭 · 이설은 아래에서 원본으로 읽는다(이름이 정해진 뒤에 알림 글을 달려고)
                }
            })
            .collect();
        let shown = |c: &Cell| [&c.name, &c.temple, &c.title, &c.given].into_iter().find(|x| !x.is_empty()).cloned().unwrap_or_default();
        let mut kept = Vec::new();
        for c in cells_in {
            let ok = !shown(&c).is_empty() && (c.start_unknown || c.start.is_some_and(|t| !t.is_nan()));
            if !ok {
                let why = if c.error.is_empty() { String::new() } else { format!(" ({}: {})", if c.name.is_empty() { Str::from("이름 없음") } else { c.name.clone() }, c.error) };
                self.warn(format!("{label}: {what} 항목 중 이름이나 연도가 없는 것을 뺐습니다(연도를 모르면 \"미정\"이라고 적습니다).{why}"), kind, Some(i));
            } else if c.start_unknown && c.end_unknown && c.start.is_none() && c.end.is_none() {
                self.warn(format!("{label}: {what} \"{}\"은(는) 시작과 끝이 모두 미정이고 배치용 연도가 없어, 앞뒤 칸이나 정권의 기간에 맞춰 놓습니다.", shown(&c)), kind, Some(i));
            }
            if ok { kept.push(c); }
        }
        let mut out = Vec::new();
        for c in kept {
            let o = Obj::new();
            let name = shown(&c);
            o.set("name", name.clone());
            if let Some(t) = c.start { o.set("start", t); }
            if js::truthy(&c.start_at) { o.set("startAt", c.start_at.clone()); }
            if c.start_unknown { o.set("startUnknown", true); }
            if is_leader {
                if !c.temple.is_empty() { o.set("temple", c.temple.clone()); }
                if !c.title.is_empty() { o.set("title", c.title.clone()); }
                if !c.given.is_empty() { o.set("given", c.given.clone()); }
                if c.ordinal_unknown { o.set("ordinalUnknown", true); }
                else if let Some(n) = c.ordinal { o.set("ordinal", n); }
                // 이름 번호 — 표시는 대표 이름 뒤 'n세'(HT.leaderLabel) · 하나라도 있으면 그 줄은 대수를 자동으로 매기지 않음(HT.numberLeaders)
                if let Some(rg) = c.regnal {
                    if rg > 0.0 { o.set("regnal", rg); }
                    else { self.warn(format!("{label}: {what} \"{name}\"의 이름 번호(regnal) \"{}\"은(는) 양의 정수가 아니라 뺐습니다.", js::to_str(&c.raw.get("regnal"))), kind, Some(i)); }
                }
                if !c.dynasty.is_empty() { o.set("dynasty", c.dynasty.clone()); } // 왕조 (비우면 그 정권의 왕조 구간으로 채움)
                if !c.rank.is_empty() { o.set("rank", c.rank.clone()); } // 지위 (비우면 시작한 해의 정권 지위로 채움 — 모델의 rankAuto)
            }
            if let Some(e) = c.end.filter(|e| !e.is_nan()) {
                o.set("end", e);
                if js::truthy(&c.end_at) { o.set("endAt", c.end_at.clone()); }
            }
            if c.end_unknown { o.set("endUnknown", true); }
            if !c.note.is_empty() { o.set("note", c.note.clone()); }
            if !c.house.is_empty() && (is_leader || what == "내각") { o.set("house", c.house.clone()); } // 가문(이름이나 id) — 지도자 · 내각 칸만
            let mut msgs = Vec::new();
            let unc = cells::read_uncertain(ctx, &c.raw, "cell", Some(&mut |m: String| msgs.push(m)), o.get("start").as_num(), o.get("end").as_num(), None);
            self.warn_all(msgs, &format!("{label}: {what} \"{name}\" — "), kind, i);
            for (k, v) in unc.entries() { o.set(&k, v); }
            // 칸의 정통성(status — 4단계 배치 갈래 · 계약 1-1 구역 57): 지도자 · 내각 · 직위 줄 더의 칸만. 객체의 정통성과 같은 값(한국어 이름도 받음) · 모르는 값은 알리고 뺀다
            if is_leader || what == "내각" || what.starts_with("직위 줄 ") {
                let st = f4::status_id(&c.raw.get("status"));
                let said = s(&c.raw.get("status"));
                if !st.is_empty() { o.set("status", st); }
                else if !said.is_empty() { self.warn(format!("{label}: {what} \"{name}\" — 정통성 \"{said}\"을(를) 알 수 없어 뺐습니다(정통 · 대립 · 공동 · 섭정 · 명목 · 주장)."), kind, Some(i)); }
            }
            // 형식 버전 3: 이름 목록(지도자 · 내각 · 연호) · 사람(지도자 · 내각) · 자리 이음 · 부모 · 배우자(지도자) — 짧은 꼴 [이름, 시작, 끝, 메모]에는 없음
            if js::truthy(&c.raw) && read::is_plain(&c.raw) {
                let cl = format!("{label}: {what} \"{name}\"");
                if what != "집권" { self.put_names(&o, &c.raw.get("names"), &cl, kind, i); } // 단체의 집권 칸(power)에는 이름 목록이 없음
                self.put_lineage(&o, &c.raw, &cl, kind, i, is_leader || what == "내각", is_leader, is_leader);
            }
            out.push(V::Obj(o));
        }
        let sorted = cells::sort_cells(out); // 시작 순 (시작이 미정인 칸은 끝 · 적힌 차례로)
        if is_leader { capital::number_leaders(&sorted); }
        sorted
    }
    /// `readCapitals(list, label, kind, i)` — 도읍: `[도시, 시작, 끝, 역할|메모]` 또는 `{ city, start, end, role, as, label, group, event, note }`(`HT.normalizeCapital`) — 시작 순.
    pub(super) fn read_capitals(&mut self, list: &V, label: &str, kind: &str, i: usize) -> Vec<V> {
        let ctx = self.ctx;
        let mut out = Vec::new();
        for c in dates::arr(list) {
            let mut msgs = Vec::new();
            let o = capital::normalize_capital(ctx, &c, Some(&mut |m: String| msgs.push(m)));
            self.warn_all(msgs, &format!("{label}: "), kind, i);
            match o {
                None => self.warn(format!("{label}: 도읍 항목 중 도시나 시작 연도가 없는 것을 뺐습니다(연도를 모르면 \"미정\"이라고 적습니다)."), kind, Some(i)),
                Some(o) => {
                    if o.bool("startUnknown") && o.bool("endUnknown") && o.get("start").is_nullish() && o.get("end").is_nullish() {
                        self.warn(format!("{label}: 도읍 \"{}\"은(는) 시작과 끝이 모두 미정이고 배치용 연도가 없어, 앞 정도의 끝이나 정권의 기간에 맞춰 놓습니다.", js::to_str(&o.get("city"))), kind, Some(i));
                    }
                    out.push(V::Obj(o));
                }
            }
        }
        cells::sort_cells(out)
    }
    /// `readSuccList(list, label, kind, i)` — 승계 목록(시대의 succeeds): `HT.normalizeSucc`로 읽고, 한 쌍(선대 · 후대)에는 선 하나 — 같은 선대를 두 번 적으면 첫 줄만.
    pub(super) fn read_succ_list(&mut self, list: &V, label: &str, kind: &str, i: usize) -> Vec<V> {
        let mut out: Vec<Obj> = Vec::new();
        for x in dates::arr(list) {
            let mut msgs = Vec::new();
            let o = vocab::normalize_succ(&x, &mut |m| msgs.push(m));
            self.warn_all(msgs, &format!("{label}: "), kind, i);
            let Some(o) = o else { continue };
            if out.iter().any(|y| js::strict_eq(&y.get("from"), &o.get("from"))) {
                self.warn(format!("{label}: 승계 \"{}\"이(가) 두 번 적혀 있어 첫 줄만 씁니다 (한 쌍에는 선 하나 — 둘 중 하나의 종류를 고릅니다).", js::to_str(&o.get("from"))), kind, Some(i));
                continue;
            }
            out.push(o);
        }
        out.into_iter().map(V::Obj).collect()
    }
    /// `warnPartOfUnknown(refs, label, kind, i, what, where)` — 소속 기간(`HT.readPartOf`로 읽은 것)의 시작과 끝이 모두 미정이고 배치용 연도가 없으면 알린다.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn warn_part_of_unknown(&mut self, refs: &[V], label: &str, kind: &str, i: usize, what: &str, place: &str) {
        for x in refs {
            if x.bool("startUnknown") && x.bool("endUnknown") && x.get("start").is_nullish() && x.get("end").is_nullish() {
                self.warn(format!("{label}: {what} \"{}\"의 기간은 시작과 끝이 모두 미정이고 배치용 연도가 없어, {place} 놓습니다.", js::to_str(&x.get("polity"))), kind, Some(i));
            }
        }
    }
    /// `readUncertainty(x, label, kind, i, start)` — 확실성 등급 · 연대 폭 · 이설 · 쟁점(`HT.readUncertain` — 항목 꼴).
    pub(super) fn read_uncertainty(&mut self, x: &V, label: &str, kind: &str, i: usize, start: f64) -> Obj {
        let mut msgs = Vec::new();
        let o = cells::read_uncertain(self.ctx, x, "item", Some(&mut |m: String| msgs.push(m)), Some(start), None, None);
        self.warn_all(msgs, &format!("{label}: "), kind, i);
        o
    }
}

/// `readNames(v)`(4230줄 — 정규화 안의 이름 목록: 관련 인물 · 다른 이름 · 태그 — 과제 5b가 옮김: 시대 · 가문의 꼬리표가 부름): 배열이나 쉼표로 이은 글 → 빈 것 · 겹친 것을 뺀 목록.
/// 쉼표 가름 `/[,，]/`은 코드 단위로(`read::split_units`). 가문의 tags(3991줄)는 같은 식을 그 자리에 적었다 — 같은 함수로 부른다.
pub(super) fn name_list(v: &V) -> Vec<Str> {
    let items: Vec<V> = match v { V::Arr(a) => a.to_vec(), x => read::split_units(&dates::str_of(x), &[0x2C, 0xFF0C]).into_iter().map(V::Str).collect() };
    let mut out: Vec<Str> = Vec::new();
    for x in &items {
        let s = dates::str_of(x);
        if !s.is_empty() && !out.contains(&s) { out.push(s); }
    }
    out
}

/// `FIGURE_DATE_WORDS`(4234줄 — 과제 5c) — 인물 날짜 칸의 이름(알림 글).
pub(super) fn figure_date_word(k: &str) -> &'static str {
    match k { "birth" => "출생", "death" => "사망", "start" => "활동 시작", _ => "활동 끝" }
}

impl<'c> Norm<'c> {
    /// `readService(list, label, kind, i)`(4235 ~ 4284줄 — 과제 5c) — 인물의 섬긴 기록: `[{ track?, polity, office(직함), start, end, note }]` — 적은 차례 그대로(첫 줄이 대표 정권).
    /// 기간의 시작 · 끝에 "미정"도 된다(칸의 미정). 다른 트랙의 정권도 가리킬 수 있고(track을 비우면 인물의 트랙), 글로 적은 "트랙:정권" · "정권"도 읽는다.
    /// 그 track은 여기서 검사하지 않는다(기본팩 같은 다른 DLC의 트랙일 수 있음).
    pub(super) fn read_service(&mut self, list: &V, label: &str, kind: &str, i: usize) -> Vec<V> {
        let ctx = self.ctx;
        let s = dates::str_of;
        let mut out = Vec::new();
        for raw0 in read::listed(list) {
            let x = match &raw0 {
                V::Str(t) => {
                    let j = t.index_of16(&Str::from(":"), 0.0);
                    let o = Obj::new();
                    if j > 0.0 { o.set("track", t.slice16(0.0, j)); o.set("polity", t.slice16(j + 1.0, f64::INFINITY)); } else { o.set("polity", t.clone()); }
                    V::Obj(o)
                }
                v => v.clone(),
            };
            if !js::truthy(&x) || js::type_of(&x) != "object" { continue; }
            let polity = s(&js::nullish(x.get("polity"), x.get("name")));
            if polity.is_empty() {
                self.warn(format!("{label}: 활동 기록 가운데 정권이 없는 줄을 뺐습니다."), kind, Some(i));
                continue;
            }
            let o = Obj::new();
            let track = s(&x.get("track"));
            if !track.is_empty() { o.set("track", track); }
            o.set("polity", polity.clone());
            let office = s(&js::nullish(x.get("office"), x.get("title")));
            if !office.is_empty() { o.set("office", office); }
            for k in ["start", "end"] {
                // 칸의 미정: "미정" 글 · startUnknown · startHint → 미정 + (있으면) 배치용 연도 — 없으면 비운 것과 같은 자리(활동 시작 · 끝)
                match cells::read_cell_edge(ctx, &x, k) {
                    None => continue,
                    Some(cells::Edge::Unknown(t)) => {
                        if let Some(t) = t { o.set(k, t); }
                        o.set(&format!("{k}Unknown"), true);
                    }
                    Some(cells::Edge::Date(d)) if d.t.is_nan() => {
                        let why = d.error.as_ref().filter(|e| !e.is_empty()).map_or(String::new(), |e| format!(" {e}"));
                        self.warn(format!("{label}: 활동 기록 \"{polity}\"의 {} 날짜를 읽을 수 없어 비웠습니다.{why}", if k == "start" { "시작" } else { "끝" }), kind, Some(i));
                    }
                    Some(cells::Edge::Date(d)) => {
                        o.set(k, d.t);
                        if let Some(at) = d.at.filter(|a| !a.is_empty()) { o.set(&format!("{k}At"), at); }
                    }
                }
            }
            if !o.get("start").is_nullish() && !o.get("end").is_nullish() && js::to_num(&dates::end_bound(ctx, &o.get("end"), &o.get("endAt"))) < o.num("start") {
                // 거꾸로면 짐작인 쪽을 버린다(활동 시기 · 지위 변천과 같은 규칙): 시작만 미정이면 시작의 배치용 연도 — 적은 끝은 사실이라 남김
                if o.bool("startUnknown") && !o.bool("endUnknown") {
                    self.warn(format!("{label}: 활동 기록 \"{polity}\"의 끝이 시작보다 앞서서 시작의 배치용 연도를 버렸습니다(미정인 시작 — 적은 끝은 그대로)."), kind, Some(i));
                    o.delete("start");
                } else {
                    let tail = if o.bool("endUnknown") { "(미정인 끝의 배치용 연도를 버림)" } else { "" };
                    self.warn(format!("{label}: 활동 기록 \"{polity}\"의 끝이 시작보다 앞서서 끝을 비웠습니다{tail}."), kind, Some(i));
                    o.delete("end");
                    o.delete("endAt");
                }
            }
            let note = s(&x.get("note"));
            if !note.is_empty() { o.set("note", note); }
            let mut msgs = Vec::new();
            let (start, end) = (o.get("start").as_num(), o.get("end").as_num());
            let unc = cells::read_uncertain(ctx, &x, "cell", Some(&mut |m: String| msgs.push(m)), start, end, None); // 확실성 · 연대 폭 · 이설(다른 칸과 같은 읽기)
            self.warn_all(msgs, &format!("{label}: 활동 기록 \"{polity}\" — "), kind, i);
            for (k, v) in unc.entries() { o.set(&k, v); }
            out.push(V::Obj(o));
        }
        out
    }
}

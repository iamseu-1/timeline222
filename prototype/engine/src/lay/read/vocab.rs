//! `js/core.js` 1 ~ 459줄 가운데 읽기가 쓰는 형식 상수 · 낱말 표와 그 읽기(`HT.historicity` · `HT.normalizeSucc` · `HT.polityKindId` · `HT.relationId` ·
//! `HT.capitalRole` …) — 한 벌 P3 과제 5a · 5b.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 6 ~ 21줄 `HT.FORMAT` · `HT.FORMAT_VERSION` · `HT.USER_PACK` (`HT.CURRENT_YEAR`는 `read::Ctx`)
//! - 68 ~ 87줄 `HT.PACK_CATEGORIES` · `HT.PACK_RELATIONS` · `HT.PACK_LIMITS`(+ 5332줄의 문서 그림 한도 — 5c)
//! - 113 ~ 126줄 `HT.PASTEL` · `PALETTE` · `HT.DEFAULT_CATEGORIES`
//! - 171 ~ 177줄 `HT.CERTAINTY`(171 주석 · 172 ~ 177 배열 — 5b가 이름도 둠: 혈연의 확실성은 이름으로도 읽는다)
//! - (5b) 185 ~ 201줄 `HT.HISTORICITY` · `HISTORICITY_WORDS` · `HT.historicity`
//! - (5b) 225 ~ 303줄 `HT.SUCCESSION` · `SUCCESSION_WORDS` · `HT.successionType` · `HT.SUCC_DEGREE_DEFAULT` · `DEGREE_WORDS` · `HT.succDegree` · `HT.SUCC_PARTS` ·
//!   `PART_WORDS` · `HT.succPart` · `HT.normalizeSucc`
//! - 320 ~ 356줄 `HT.POLITY_KINDS`(종류 · 갈래 · 자율성 · 화면 차례) · `HT.kindFamily`
//! - (5b) 357 ~ 369줄 `KIND_WORDS` · `HT.polityKindId`
//! - (376 ~ 405줄의 `HT.SPHERES` · `HT.FANTASY_SPHERES` · `HT.isSphere`는 2026-10-23 웹 코드에서 없어졌다 — 문화권은 켠 DLC의 `spheres`뿐:
//!   읽기 `read::cells::read_spheres` · 모델의 사전 `model::util::merge_spheres`)
//! - 407 ~ 419줄 `HT.RELATIONS` · `RELATION_WORDS` · `HT.relationId`
//! - (5c) 425 ~ 430줄 `HT.EXTRA_KINDS` · `HT.ALL_KINDS`
//! - (5b) 446 ~ 459줄 `HT.CAPITAL_ROLES` · `ROLE_WORDS` · `HT.capitalRole`
//!
//! 표의 이름(`name`) · 짧은 이름(`short`)은 읽을 때 낱말을 id로 바꾸는 데 쓰이므로 그대로 둔다. 풀이(`hint`) 같은 화면 글은 뺐다.
//! **알려진 차이(물려받은 이름)**: 낱말 표(`RELATION_WORDS` · 5b의 `HISTORICITY_WORDS` · `SUCCESSION_WORDS` · `DEGREE_WORDS` · `PART_WORDS` · `KIND_WORDS` · `ROLE_WORDS`)를
//! 웹은 평범한 객체로 `WORDS[s]`처럼 찾아 `constructor` · `toString` · `valueOf` · `hasOwnProperty` · `__proto__` 같은 `Object.prototype`의 이름도 '찾음'으로 읽는다
//! (함수 · 객체 값 — 형식 4 내림의 `relation`에 함수가 들어가 JSON에서 빠지는 식). 5b의 것: 실재성 · 도읍 역할에 그런 글을 적으면 웹은 알림 없이 칸에 함수를 넣어
//! JSON에서 빠지고(Rust는 '알 수 없음' 알림 · 도읍은 역할 없음), 정권 종류는 웹이 함수의 글을 알림에 넣고, 승계 종류는 웹이 `type`을 JSON에서 잃고(Rust는 'indirect'),
//! 부분 승계의 정도 · 이어진 것은 웹이 함수를 넣는다. 여기서는 적힌 낱말만 찾는다(그런 글을 적은 자료는 웹에서도 뜻이 없다 · 계획 '알게 된 것'에 적음).
//! `ROW_ORDER_WORDS` · `vocab`(이름 종류 · 자리 이음 · 혈연 낱말)은 웹도 제 낱말만 찾아 차이가 없다.
use super::dates;
use crate::lay::js::{self, Obj, Str, V};

/// 낱말 표(`(낱말, 값)`)에서 적힌 낱말만 찾는다(위 '알려진 차이').
fn word<T: Copy>(table: &[(&str, T)], s: &str) -> Option<T> { table.iter().find(|(k, _)| *k == s).map(|(_, v)| *v) }

/// `HT.FORMAT`.
pub const FORMAT: &str = "history-timeline-dlc";
/// `HT.FORMAT_VERSION` — 이 프로그램이 읽는 가장 새 형식.
pub const FORMAT_VERSION: f64 = 3.0;
/// `HT.USER_PACK.id` — 프로그램이 쓰는 예약 DLC id.
pub const USER_PACK_ID: &str = "user";

/// `HT.PACK_CATEGORIES`의 id(차례 그대로 — 끝의 `map`은 76줄의 push).
pub const PACK_CATEGORIES: [&str; 7] = ["expansion", "region", "nation", "theory", "world", "docs", "map"];
/// `HT.PACK_RELATIONS`의 id.
pub const PACK_RELATIONS: [&str; 3] = ["needs", "conflicts", "after"];

/// `HT.PACK_LIMITS`(84 · 87 · 5332줄).
pub struct PackLimits {
    pub tags: usize, pub tag_len: usize, pub summary: usize, pub highlights: usize, pub highlight_len: usize, pub changelog: usize, pub note_len: usize, pub cover: usize,
    pub map_image: usize, pub font: usize, pub fonts: usize, pub font_total: usize,
    /// 5332줄(문서 그림 — 과제 5c): 한 장 · 팩의 그림 합 · 설명 · 대체 글 · 출처의 글자 수.
    pub doc_image: usize, pub doc_image_total: usize, pub doc_image_text: usize,
}
pub const PACK_LIMITS: PackLimits = PackLimits {
    tags: 5, tag_len: 20, summary: 120, highlights: 10, highlight_len: 120, changelog: 200, note_len: 500, cover: 2_000_000,
    map_image: 2_000_000, font: 4_000_000, fonts: 8, font_total: 12_000_000,
    doc_image: 2_000_000, doc_image_total: 20_000_000, doc_image_text: 500,
};

/// `PALETTE`(= `HT.PASTEL`의 id 차례) — `HT.autoColor`가 고른다.
pub const PALETTE: [&str; 12] = ["#d4a39b", "#dab195", "#d7c18e", "#b6c398", "#9dbea8", "#a0bcc5", "#abb3c9", "#bbacc8", "#d1a9b9", "#c8b193", "#a4b1b7", "#bba395"];

/// `HT.DEFAULT_CATEGORIES`의 id(정규화의 `catIds` 바탕).
pub const DEFAULT_CATEGORIES: [&str; 5] = ["politics", "war", "diplomacy", "society", "culture"];

/// `HT.CERTAINTY`의 (id, 이름).
pub const CERTAINTY: [(&str, &str); 4] = [("certain", "확실"), ("accepted", "통설"), ("estimated", "추정"), ("legend", "전승")];

// ── 실재성(185 ~ 201줄 — 5b) ──

/// `HT.HISTORICITY`의 id.
pub const HISTORICITY: [&str; 5] = ["attested", "semi", "legendary", "disputed", "refuted"];
/// `HISTORICITY_WORDS`.
const HISTORICITY_WORDS: [(&str, &str); 9] = [
    ("실재", "attested"), ("반전설", "semi"), ("반(半)전설", "semi"), ("전설", "legendary"), ("신화", "legendary"), ("논쟁", "disputed"), ("실재 논쟁", "disputed"),
    ("부정", "refuted"), ("부정됨", "refuted"),
];
/// `HT.historicity(v)` — 실재성 글(id 또는 한국어) → id. 모르는 글이면 ''.
pub fn historicity(v: &V) -> Str {
    let s = dates::str_of(v);
    if s.is_empty() || HISTORICITY.iter().any(|h| s == *h) { return s; }
    Str::from(word(&HISTORICITY_WORDS, &s.as_str()).unwrap_or(""))
}

// ── 승계(225 ~ 303줄 — 5b) ──

/// `HT.SUCCESSION`의 id(직접 · 간접 + 231줄 부흥 · 235줄 부분).
pub const SUCCESSION: [&str; 4] = ["direct", "indirect", "revival", "partial"];
/// `SUCCESSION_WORDS`(237줄 + 238줄의 옛 낱말).
const SUCCESSION_WORDS: [(&str, &str); 12] = [
    ("직접", "direct"), ("직접 승계", "direct"), ("간접", "indirect"), ("간접 승계", "indirect"), ("부흥", "revival"), ("부흥 승계", "revival"), ("부분", "partial"), ("부분 승계", "partial"),
    ("직접 계승", "direct"), ("간접 계승", "indirect"), ("부흥 계승", "revival"), ("부분 계승", "partial"),
];
/// `HT.successionType(v)` — 승계 종류를 id로(한국어도). 모르는 값 · 빈 값은 간접 승계.
pub fn succession_type(v: &V) -> Str {
    let s = dates::str_of(v);
    if SUCCESSION.iter().any(|x| s == *x) { return s; }
    Str::from(word(&SUCCESSION_WORDS, &s.as_str()).unwrap_or("indirect"))
}
/// `HT.SUCC_DEGREE_DEFAULT`(중).
pub const SUCC_DEGREE_DEFAULT: f64 = 2.0;
/// `DEGREE_WORDS`.
const DEGREE_WORDS: [(&str, f64); 9] = [("약", 1.0), ("중", 2.0), ("강", 3.0), ("weak", 1.0), ("medium", 2.0), ("strong", 3.0), ("약함", 1.0), ("중간", 2.0), ("강함", 3.0)];
/// `HT.succDegree(v)` — 정도 글 · 수 → 1 · 2 · 3, 읽지 못하면 None(null). 정규식 `/^[123]$/`은 손으로(글 전체가 '1' · '2' · '3' 한 글자).
pub fn succ_degree(v: &V) -> Option<f64> {
    if let V::Num(n) = v { return if *n == 1.0 || *n == 2.0 || *n == 3.0 { Some(*n) } else { None }; }
    let s = dates::str_of(v);
    match s.exact() {
        Some("1") => return Some(1.0),
        Some("2") => return Some(2.0),
        Some("3") => return Some(3.0),
        _ => {}
    }
    let text = s.as_str();
    word(&DEGREE_WORDS, &text).or_else(|| word(&DEGREE_WORDS, &text.to_lowercase()))
}
/// `HT.SUCC_PARTS`의 id(늘 이 차례 — 지배층 → 문화).
pub const SUCC_PARTS: [&str; 5] = ["elite", "people", "land", "institutions", "culture"];
/// `PART_WORDS`.
const PART_WORDS: [(&str, &str); 7] = [("지배층", "elite"), ("백성", "people"), ("유민", "people"), ("영역", "land"), ("영토", "land"), ("제도", "institutions"), ("문화", "culture")];
/// `HT.succPart(v)` — 이어진 것 한 낱말 → id(모르면 '').
pub fn succ_part(v: &V) -> Str {
    let s = dates::str_of(v);
    if SUCC_PARTS.iter().any(|x| s == *x) { return s; }
    Str::from(word(&PART_WORDS, &s.as_str()).unwrap_or(""))
}
/// `HT.normalizeSucc(x, warn)` — 승계 한 줄 읽기: 이름만 적은 글 · `{ from, type, degree, parts, note }` → 정리한 줄(선대가 없으면 None).
/// 부분 승계는 정도를 늘 적고(적지 않았으면 중), 이어진 것은 있을 때만 · 겹친 것은 한 번 — 다른 종류에 적힌 정도 · 이어진 것은 버린다.
/// `parts` 글의 가름 `/[,，、·]/`은 코드 단위로 자른다(`read::split_units`).
pub fn normalize_succ(x: &V, warn: &mut dyn FnMut(String)) -> Option<Obj> {
    let s = match x {
        V::Str(_) => { let o = Obj::new(); o.set("from", x.clone()); V::Obj(o) }
        v if js::truthy(v) && super::is_object(v) => v.clone(),
        _ => V::Obj(Obj::new()),
    };
    let t = dates::str_of;
    let from = t(&s.get("from"));
    if from.is_empty() { return None; }
    let kind = succession_type(&s.get("type"));
    let o = Obj::new();
    o.set("from", from.clone());
    o.set("type", kind.clone());
    if kind == "partial" {
        let degree = s.get("degree");
        let d = if degree.is_nullish() || super::is_empty_str(&degree) { Some(SUCC_DEGREE_DEFAULT) } else { succ_degree(&degree) };
        let d = d.unwrap_or_else(|| {
            warn(format!("부분 승계 \"{from}\"의 정도 \"{}\"을(를) 알 수 없어 중으로 봅니다(약 · 중 · 강 또는 1 · 2 · 3).", t(&degree)));
            SUCC_DEGREE_DEFAULT
        });
        o.set("degree", d);
        let parts_v = s.get("parts");
        let raw: Vec<V> = match &parts_v {
            V::Arr(a) => a.to_vec(),
            p if !t(p).is_empty() => super::split_units(&t(p), &[0x2C, 0xFF0C, 0x3001, 0xB7]).into_iter().map(V::Str).collect(),
            _ => Vec::new(),
        };
        let mut parts: Vec<Str> = Vec::new();
        for w in &raw {
            let id = succ_part(w);
            if !id.is_empty() && !parts.contains(&id) { parts.push(id); }
            else if id.is_empty() && !t(w).is_empty() { warn(format!("부분 승계 \"{from}\"의 이어진 것 \"{}\"을(를) 알 수 없어 뺐습니다(지배층 · 백성 · 영역 · 제도 · 문화).", t(w))); }
        }
        if !parts.is_empty() { o.set("parts", super::arr_of(SUCC_PARTS.iter().filter(|id| parts.iter().any(|p| p == **id)).map(|id| V::from(*id)).collect())); }
    }
    let note = t(&s.get("note"));
    if !note.is_empty() { o.set("note", note); }
    Some(o)
}

/// 정권 종류 하나(`HT.POLITY_KINDS`의 원소 — 화면 풀이는 뺌).
#[derive(Debug, Clone, Copy)]
pub struct Kind { pub id: &'static str, pub name: &'static str, pub short: Option<&'static str>, pub family: &'static str, pub autonomy: Option<u8> }

/// `HT.POLITY_KINDS` — 320 ~ 354줄을 거친 꼴(다섯 + push한 열다섯을 `KIND_ORDER`로 정렬한 차례).
pub const POLITY_KINDS: [Kind; 20] = [
    Kind { id: "state", name: "국가", short: None, family: "sovereign", autonomy: Some(4) },
    Kind { id: "tributary", name: "조공·책봉국", short: Some("조공"), family: "dependent", autonomy: Some(3) },
    Kind { id: "fief", name: "봉국·제후국", short: Some("봉국"), family: "dependent", autonomy: Some(3) },
    Kind { id: "dominion", name: "자치령", short: Some("자치"), family: "dependent", autonomy: Some(3) },
    Kind { id: "warlord", name: "군벌·할거 세력", short: Some("군벌"), family: "dependent", autonomy: Some(3) },
    Kind { id: "client", name: "복속 세력·부용", short: Some("복속"), family: "dependent", autonomy: Some(3) },
    Kind { id: "frontier", name: "기미·번부·토사", short: Some("기미"), family: "dependent", autonomy: Some(3) },
    Kind { id: "vassal", name: "종속국", short: Some("종속"), family: "dependent", autonomy: Some(2) },
    Kind { id: "protectorate", name: "보호국", short: Some("보호"), family: "dependent", autonomy: Some(2) },
    Kind { id: "satellite", name: "위성국", short: Some("위성"), family: "dependent", autonomy: Some(2) },
    Kind { id: "puppet", name: "괴뢰국", short: Some("괴뢰"), family: "dependent", autonomy: Some(1) },
    Kind { id: "mandate", name: "위임·신탁 통치령", short: Some("위임"), family: "dependent", autonomy: Some(1) },
    Kind { id: "colony", name: "식민지·속령", short: Some("식민"), family: "dependent", autonomy: Some(0) },
    Kind { id: "prefecture", name: "직할령·군현", short: Some("군현"), family: "dependent", autonomy: Some(0) },
    Kind { id: "occupied", name: "점령지·군정", short: Some("점령"), family: "dependent", autonomy: Some(0) },
    Kind { id: "federation", name: "연맹", short: Some("연맹"), family: "special", autonomy: None },
    Kind { id: "org", name: "조직체", short: Some("조직"), family: "special", autonomy: None },
    Kind { id: "era", name: "시대 이름", short: Some("시대"), family: "special", autonomy: None },
    Kind { id: "exile", name: "망명 정부", short: Some("망명"), family: "special", autonomy: None },
    Kind { id: "movement", name: "부흥·저항 세력", short: Some("세력"), family: "special", autonomy: None },
];
/// `HT.kindFamily(id)` — 모르면 ''.
pub fn kind_family(id: &str) -> &'static str { POLITY_KINDS.iter().find(|k| k.id == id).map_or("", |k| k.family) }
/// `KIND_WORDS`(358 ~ 362줄 — 한국어 → 종류 id).
const KIND_WORDS: &[(&str, &str)] = &[
    ("나라", "state"), ("조공국", "tributary"), ("책봉국", "tributary"), ("봉국", "fief"), ("제후국", "fief"), ("번국", "fief"), ("군벌", "warlord"), ("할거 세력", "warlord"),
    ("속국", "vassal"), ("보호령", "protectorate"), ("괴뢰 정권", "puppet"), ("위임 통치령", "mandate"), ("신탁 통치령", "mandate"), ("식민지", "colony"), ("속령", "colony"),
    ("점령지", "occupied"), ("군정", "occupied"), ("조직", "org"), ("망명정부", "exile"), ("부흥 세력", "movement"), ("저항 세력", "movement"), ("부흥 운동", "movement"),
    ("복속 세력", "client"), ("복속", "client"), ("부용", "client"), ("부용국", "client"), ("기미", "frontier"), ("기미주", "frontier"), ("토사", "frontier"), ("번부", "frontier"),
    ("군현", "prefecture"), ("도호부", "prefecture"), ("도독부", "prefecture"), ("총관부", "prefecture"), ("직할령", "prefecture"),
    ("부마국", "vassal"), ("번", "fief"), ("특별행정구", "dominion"), ("자치구", "dominion"), ("절도사", "warlord"), ("번진", "warlord"),
];
/// `HT.polityKindId(v)` — 종류 id · 이름 · 짧은 이름 · 낱말 → 종류 id(모르면 '').
pub fn polity_kind_id(v: &V) -> Str {
    let s = dates::str_of(v);
    if s.is_empty() { return s; }
    let text = s.as_str();
    if let Some(k) = POLITY_KINDS.iter().find(|k| k.id == text || k.name == text || k.short == Some(&*text)) { return Str::from(k.id); }
    Str::from(word(KIND_WORDS, &text).unwrap_or(""))
}

/// 소속 관계 하나(`HT.RELATIONS`의 원소).
#[derive(Debug, Clone, Copy)]
pub struct Relation { pub id: &'static str, pub name: &'static str, pub short: &'static str }
/// `HT.RELATIONS` — 종속 갈래의 종류(군벌 빼고 · 정권 종류 차례) · 자율성이 3보다 작은 첫 자리에 '명목상' · 끝에 구성국 · 동군연합.
pub const RELATIONS: [Relation; 16] = [
    Relation { id: "tributary", name: "조공·책봉국", short: "조공" },
    Relation { id: "fief", name: "봉국·제후국", short: "봉국" },
    Relation { id: "dominion", name: "자치령", short: "자치" },
    Relation { id: "client", name: "복속 세력·부용", short: "복속" },
    Relation { id: "frontier", name: "기미·번부·토사", short: "기미" },
    Relation { id: "nominal", name: "명목상 소속", short: "명목" },
    Relation { id: "vassal", name: "종속국", short: "종속" },
    Relation { id: "protectorate", name: "보호국", short: "보호" },
    Relation { id: "satellite", name: "위성국", short: "위성" },
    Relation { id: "puppet", name: "괴뢰국", short: "괴뢰" },
    Relation { id: "mandate", name: "위임·신탁 통치령", short: "위임" },
    Relation { id: "colony", name: "식민지·속령", short: "식민" },
    Relation { id: "prefecture", name: "직할령·군현", short: "군현" },
    Relation { id: "occupied", name: "점령지·군정", short: "점령" },
    Relation { id: "member", name: "구성국", short: "구성" },
    Relation { id: "union", name: "동군연합", short: "동군" },
];
/// `RELATION_WORDS`(410 ~ 413줄).
const RELATION_WORDS: &[(&str, &str)] = &[
    ("조공", "tributary"), ("책봉", "tributary"), ("조공국", "tributary"), ("책봉국", "tributary"), ("봉국", "fief"), ("제후국", "fief"), ("번국", "fief"), ("자치", "dominion"),
    ("명목상", "nominal"), ("명목", "nominal"), ("종속", "vassal"), ("속국", "vassal"), ("보호", "protectorate"), ("보호령", "protectorate"), ("위성", "satellite"), ("괴뢰", "puppet"),
    ("괴뢰 정권", "puppet"), ("위임", "mandate"), ("신탁", "mandate"), ("위임 통치령", "mandate"), ("신탁 통치령", "mandate"), ("식민", "colony"), ("식민지", "colony"), ("속령", "colony"),
    ("점령", "occupied"), ("점령지", "occupied"), ("군정", "occupied"), ("구성", "member"), ("가맹국", "member"), ("동군", "union"), ("동군 연합", "union"),
    ("복속", "client"), ("부용", "client"), ("기미", "frontier"), ("토사", "frontier"), ("번부", "frontier"), ("직할", "prefecture"), ("군현", "prefecture"), ("도호부", "prefecture"), ("총관부", "prefecture"),
    ("부마", "vassal"), ("부마국", "vassal"), ("번", "fief"), ("특별행정구", "dominion"), ("자치구", "dominion"), ("절도사", "nominal"), ("번진", "nominal"),
];
fn relation_word(s: &str) -> &'static str {
    RELATION_WORDS.iter().find(|(k, _)| *k == s).map_or("", |(_, v)| v)
}
/// `HT.relationId(v)` — 관계 id · 이름 · 짧은 이름 · 낱말 → 관계 id(모르면 '').
pub fn relation_id(v: &V) -> Str {
    let s = js::to_str(&js::nullish(v.clone(), V::from(""))).trim();
    if s.is_empty() { return s; }
    let text = s.as_str();
    if let Some(r) = RELATIONS.iter().find(|r| r.id == text || r.name == text || r.short == text) { return Str::from(r.id); }
    Str::from(relation_word(&text))
}

// ── 시대와 별개인 항목의 종류(425 ~ 430줄 — 5c) ──

/// `HT.EXTRA_KINDS`의 id(문화 · 기관 · 왕조 — 옛 형식의 시대 kind).
pub const EXTRA_KINDS: [&str; 3] = ["culture", "overlay", "dynasty"];
/// `HT.ALL_KINDS.some(x => x.id === id)` — `HT.ALL_KINDS = HT.POLITY_KINDS.concat(HT.EXTRA_KINDS)`(패치의 종류 검사가 씀).
pub fn is_any_kind(id: &str) -> bool { POLITY_KINDS.iter().any(|k| k.id == id) || EXTRA_KINDS.contains(&id) }

// ── 도읍의 역할(446 ~ 459줄 — 5b) ──

/// `HT.CAPITAL_ROLES`의 id(정도 · 공동 정도 · 배도 · 임시 · 망명).
pub const CAPITAL_ROLES: [&str; 5] = ["main", "co", "secondary", "temporary", "exile"];
/// `ROLE_WORDS`.
const ROLE_WORDS: [(&str, &str); 11] = [
    ("정도", "main"), ("공동", "co"), ("공동 정도", "co"), ("배도", "secondary"), ("별도", "secondary"), ("소경", "secondary"), ("5경", "secondary"), ("임시", "temporary"),
    ("피난", "temporary"), ("행재", "temporary"), ("망명", "exile"),
];
/// `HT.capitalRole(v)` — 역할 id · 한국어 → id(모르면 '').
pub fn capital_role(v: &V) -> Str {
    let s = dates::str_of(v);
    if s.is_empty() || CAPITAL_ROLES.iter().any(|r| s == *r) { return s; }
    Str::from(word(&ROLE_WORDS, &s.as_str()).unwrap_or(""))
}

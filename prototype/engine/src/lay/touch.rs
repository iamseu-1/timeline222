//! 닿는 트랙 — 한 벌 P3 과제 16a(계획 과제 16의 인터페이스 `touched` · 걸음 1 ~ 4의 '옳은 첫 판').
//!
//! DLC 하나를 넣거나 · 빼거나 · 판을 바꿀 때 **배치 지문(`patch::prints`)이 바뀔 수 있는 트랙**을 고른다. P4(`packs::Layouter::touched`)가 이 집합 S만
//! 하위 배치(`Scope::Tracks(S)` — `patch::sub_plan(통째, S)` 꼴)로 받아 `Covers::Part`로 고쳐 쓴다. P4 장부 'Carry → P3-16'의 약속:
//! - **touched ⊇ {넣기 전 · 뒤 배치의 지문이 다른 트랙 전부} ∪ 새 트랙** — S 밖 트랙은 `apply`가 '그대로'라고 믿으므로 이 어김은 흐름이 알아챌 수 없다
//!   (`tests/lay_scope.rs`의 넓이 검사가 유일한 그물). **모르면 넓게**(모든 트랙) — 좁게 틀리는 것보다 낫다.
//! - 결과는 **새 조합의 트랙 열쇠만**(`patch::track_key`와 같은 열쇠 — 판 트랙은 `board:__board:<판 열쇠>`). 뺀 DLC의 제 트랙은 거른다
//!   (하나 예외: 판 셈 오류로 빠지는 판 트랙은 짐작이 빗나가 들 수 있다 — 아래 '판 트랙의 있고 없음').
//! - 합성: 넣기 = `touched(새것, 뒤)` · 빼기 = `touched(뺀 것, 앞)` ∩ [`keys`]`(뒤)` **∪ (`keys(뒤)` − `keys(앞)`)** · 판 바꿈 = `touched(옛 판, 앞)` ∪ `touched(새 판, 뒤)`(∩ 뒤의 열쇠).
//!   빼기의 뒤 몫은 P4 약속('빼기는 앞 조합으로')에 더한 것 — 뺀 DLC가 숨기던 띠가 돌아와 **뒤에만 서는 트랙**(판 트랙 따위)은 앞 조합의 열쇠에 없어서다(넓이 검사 ④가 잡음).
//!   [`touched_scope`]는 앞 · 뒤 조합을 한 번에 견준다(같은 규칙 · 모델 두 벌 — 뒤에만 있는 트랙도 저절로 듦 · 넓이 검사가 같은 그물로 지킨다).
//!
//! 셈(배치 모듈을 돌리지 않는다 — 정규화 → 모델 → 연표 상태의 준비까지, 줄 배정 없음: `ctx::context_of(…, false)`):
//! 그 DLC가 **없는** 조합과 **있는** 조합의 모델을 짓고, 모델 객체(트랙 · 띠 · 사건 · 인물 · 시대 · 대범위 · 판 · 단체 · 제도 · 민족 · 분류 · 주제 · …)마다
//! **내용 지문**을 낸다 — 다른 모델 객체를 가리키는 자리는 그 객체의 이름표(`period:<uid>` 꼴)로만 적고(그 객체의 내용은 넣지 않음) 이음으로 적는다.
//! 그러면 패치 · 이름으로 찾기(소속 · 승계 · 사건의 정권)가 다른 객체로 풀림 · 자동 색(트랙 안 차례의 팔레트) · 문서의 wiki 글 덮기처럼
//! **다른 DLC의 객체가 바뀌는 것도** 내용 지문이 바뀐 객체로 잡힌다. 그 다음 아래 규칙 표로 트랙을 모은다.
//!
//! | # | 무엇을 넣는가 | 원본 근거 |
//! | --- | --- | --- |
//! | 1 | 내용이 바뀌었거나 생기거나 사라진 모델 객체의 **제 트랙** — 객체(와 그 안의 객체 아닌 칸)의 `track` 칸: 띠 · 시대 · 대범위 · 단체의 `track`, 사건의 자리 `placements[].track`(공동 사건 · 조약 당사국 — 남의 트랙에 찍힘), 인물의 섬김 `services[].track`(남의 트랙의 인물 단), 조약 당사국 `treatyRefs.parties[].track` · 트랙 객체(`trackMap`)는 그 트랙 자신(트랙 항목의 이름 · 색 · 문화권 — 판정 R54 I1) | `base.mjs` `contextOf`(사건 · 인물을 트랙에 나눔) · `core.js` `buildModel` |
//! | 2 | 그 객체와 **이어진** 객체(가리키거나 가리켜지는 — 소속 `hosts` · `members` · 왕조 · 승계 `predecessors` · `successors` · 사건의 정권 · 부모 사건 · 대범위 구성 · 판 구성 · 민족 경로 · uid 글로 가리킴 · **형식 4의 글 이음**: 남의 실권 `power[].over` · 직위 줄 빌림 `leadersFrom` · `cabinetsFrom`의 `from` · `offices[].from`)의 제 트랙(한 겹) — 승계 · 소속의 양 끝, 매단 속국 이름표(`hangs` — 상국 트랙에 그림), 승계선(`links`), 단체 칸(`power`), 남의 트랙에 찍힌 사건, 실권 상대 띠의 실권 밑줄(구역 56 — 쥔 쪽의 이름 · 색), 빌린 쪽 띠의 빌림 머리 글(구역 54 — 출처의 이름) · 직위 줄 더의 칸(칸 종류 9 — 출처의 직위 줄 칸). 형식 4 이음은 모델에 글(uid · id · 이름)로 남아 내보내기가 그때 찾으므로 **같은 찾기**(uid → 같은 DLC의 id → 이름 · 빌림은 첫 `/` 앞)로 푼 객체의 이름표로 잇고 그 이름표(못 찾으면 `?`)를 쥔 쪽 · 빌린 쪽의 지문에도 넣는다(찾기가 다른 객체로 풀리면 그 객체가 바뀐 것) · 찾은 것이 모델 객체가 아니면 **모든 트랙**(모르면 넓게) | `timeline.js` `depProxies` · `export/hangs.mjs` · `links.mjs` · `power.mjs`(실권 밑줄 — Rust `m/power.rs` `power_lines`의 `over` 찾기) · `strips.mjs` `fromOf`(Rust `m/strips.rs` `from_of`) · `events.mjs` |
//! | 3 | 분류 번호(`tl._cats`의 차례 — 줄의 `cats` · 사건의 분류 번호)가 다르면 **모든 트랙** | 계획 정한 것 #13 · `export/tracks.mjs` `catNo` |
//! | 4 | 트랙의 상대 차례(모델 `tracks` — 문화권 → order → 넣은 차례)나 간지 설정(`yearCycle`)이 다르면 **모든 트랙** | `export/boards.mjs` `echoBands`(트랙 순번) · `axis.mjs` |
//! | 5 | 트랙을 처음 말한 DLC(`ctx.track_pack` — 트랙 항목의 `pack`)가 다르면 그 트랙 | `export/tracks.mjs` 트랙 항목 |
//! | 6 | **판 트랙**(집합 보기 — `view:<id>` · 시대의 임시 판 `view:epoch:<uid>` · 판정 R46으로 고침): 판을 켠 배치의 차이는 판 트랙만이 아니라 **구성 나라의 트랙**(`boards.mjs`의 `itemsOutside` — 변형 판 항목 · 칸)에도 실린다 — 판이 새로 서거나 · 사라지거나(앞에만 있는 판도 돎) · 근원(모아 보기 판 · 시대)이 바뀌거나 · 구성 띠의 집합이 바뀌면 그 판과 구성 나라의 트랙(앞 ∪ 뒤) 전부 · 판 둘레(`scopes.mjs`의 `extentOf` — 자료 전체 해 범위)가 바뀌면 판 트랙 전부 · 구성 나라의 트랙이 닿으면 그 판(더 늘지 않을 때까지) | `export/boards.mjs` `boardsOf` · `boardOne` · `itemsOutside` · `export/scopes.mjs` `extentOf` |
//! | 7 | **렌즈**: 무엇이든 바뀌면 앞 · 뒤의 **첫 트랙**(뒤에 있는 것) — 렌즈 변형 kind 4는 `track: 0`에 실리고 모든 트랙의 칸 · 항목을 가린다. 내장 주제가 8개라 조건(주제가 있음)은 늘 참이다. 판(6)보다 먼저 셈하되 규칙 7로만 든 첫 트랙은 판을 끌지 않는다(렌즈 변형은 판을 켠 배치에 들지 않음 — 판정 R54 M3) | `export/lens.mjs` |
//! | 8 | 그 DLC가 기본 DLC(첫째)거나 · 그 DLC가 없는 조합을 읽지 못하면 **모든 트랙** | 기본 DLC는 판 전체(이름 · 차례)의 바탕 |
//!
//! 9 · 10은 걷었다(번호는 비워 둠): 지문(`patch::prints`)이 트랙 순번 · 온 판 번호를 그대로 적던 두 곳('번호가 새는 곳' — 날짜 칸 이음 번호 `axis[].strip`은
//! 온 판에 한 번 세고 · 변형 `notes`는 '트랙 <순번>'을 품는다)이라 트랙 하나만 바뀌어도 여러 트랙의 지문이 흔들려 touched가 넓었다(KTL에서 5/5).
//! **판정 R45(길 ②)**로 P4 지문이 이음 번호를 트랙 안 거리로 · notes의 순번을 트랙 열쇠로 적고(지문 판 2) apply가 같은 쓰기 거래 안에서 다시 쓰지 않는 트랙의
//! 저장소 번호를 새 번호로 옮기므로(`patch::renumber_strips`) 두 규칙이 필요 없다(KTL은 {koreaA, korea}).
//! 3 · 4는 넓은 쪽으로 둔 규칙이다(돌연변이로 꺼도 지금 자료의 넓이 검사가 물지 않음 — 다른 규칙이 이미 덮음).
//!
//! 판 트랙의 있고 없음은 배치 없이 `boardsOf`의 규칙(모아 보기 판의 구성 나라가 하나라도 · 시대와 기간이 겹치는 나라가 하나라도 — 그리고 그 나라가 연표 트랙에
//! 든다)으로 짐작한다. `boards.mjs`의 `boardOne`이 판 하나의 **셈 오류**로 그 판을 빼는 길(뺀 판)은 배치 없이는 모른다(합성 자료 `synth-lay`의
//! `view:epoch:synth-lay/ep-sd` — 구성 나라는 줄에 있으나 판 셈이 거절됨): 그런 판 열쇠는 결과 · [`Touch::all`]에 들 수 있고 새 조합에는 없다 —
//! `lay::export`의 범위 갈래가 배치에 없는 **판** 열쇠만 걸러 낸다. P4는 `Covers::Part`의 트랙을 S가 아니라 하위 배치에 실린 열쇠(S ∩ `allTracks`)로 잡아야 한다.
//! 넓이 검사가 '짐작 = 실제 + 빠진 판만'인지 견준다.
use crate::lay::ctx::{self, Ctx};
use crate::lay::js::{self, Map, Set, Str, V};
use crate::lay::model::util::{eq, item_kind_of, lt, nn, s, tv};
use crate::lay::{Opts, PackIn, Scope};
use crate::Result;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// 판 트랙의 열쇠 앞머리 — `patch::track_key`(판 트랙 `board:`) + 내보내기의 판 트랙 id(`__board:` — `lay::track::BOARD_ID`).
const BOARD_PREFIX: &str = "board:__board:";

/// 닿는 트랙과 그 까닭.
#[derive(Debug, Clone, Default)]
pub struct Touch {
    /// 새 조합의 트랙 열쇠(차례 없음).
    pub keys: BTreeSet<String>,
    /// 새 조합의 트랙 열쇠 전부(옛 트랙 → 짐작한 판 트랙 — 내보내기의 차례). 판 셈 오류로 빠지는 판은 배치에 없을 수 있다(모듈 머리글).
    pub all: Vec<String>,
    /// 트랙 열쇠 → 처음 넣은 까닭(규칙 번호와 객체 — 검사가 빠진 트랙을 찍을 때 · 보고).
    pub why: BTreeMap<String, String>,
    /// 모든 트랙이 된 까닭(규칙 2의 모르는 이음 · 3 · 4 · 8) — 없으면 None.
    pub everything: Option<String>,
    /// 내용이 바뀐 모델 객체의 수(앞 · 뒤 어느 한쪽에만 있는 것 포함).
    pub changed: usize,
}

impl Touch {
    fn add(&mut self, key: &str, why: impl FnOnce() -> String) {
        if self.keys.insert(key.to_owned()) {
            self.why.insert(key.to_owned(), why());
        }
    }
    fn all_tracks(all: Vec<String>, why: String) -> Touch {
        let mut t = Touch { all, everything: Some(why.clone()), ..Touch::default() };
        for k in t.all.clone() {
            t.add(&k, || why.clone());
        }
        t
    }
}

/// 그 DLC(`new`)가 조합 `all`(첫째가 기본 · 나머지는 켠 차례 — `new`가 들어 있어야 한다)에서 닿는 트랙 — `all`의 트랙 열쇠(`patch::track_key`와 같은 열쇠).
/// `new`는 바이트가 같은 것, 없으면 DLC id가 같은 것을 `all`에서 찾는다(없으면 오류). 그 DLC가 없는 조합(`all` − `new`)과 견준다(모듈 머리글의 규칙 표).
/// 넣기는 `touched(새것, 뒤)`, 빼기는 `touched(뺀 것, 앞)` ∩ [`keys`]`(뒤)` ∪ (`keys(뒤)` − `keys(앞)`), 판 바꿈은 `touched(옛 판, 앞)` ∪ `touched(새 판, 뒤)`
/// (모듈 머리글의 합성 — 한 번에는 [`touched_scope`]).
pub fn touched(new: &PackIn, all: &[PackIn], opts: &Opts) -> Result<BTreeSet<String>> {
    Ok(touched_why(new, all, opts)?.keys)
}

/// [`touched`]와 같은 셈 — 까닭까지([`Touch`]).
pub fn touched_why(new: &PackIn, all: &[PackIn], opts: &Opts) -> Result<Touch> {
    let at = position(new, all, opts)?;
    if at == 0 {
        // 규칙 8: 기본 DLC — 그것이 없는 조합은 판 전체가 다르다.
        let after = Snap::of(all, opts)?;
        return Ok(Touch::all_tracks(after.keys, "규칙 8: 기본 DLC(첫째)".into()));
    }
    let before: Vec<PackIn> = all.iter().enumerate().filter(|(i, _)| *i != at).map(|(_, p)| p.clone()).collect();
    between(&before, all, opts)
}

/// 앞 조합 → 뒤 조합으로 바뀔 때 닿는 트랙(뒤의 열쇠만) — 넣기 · 빼기 · 판 바꿈 · 여럿을 함께 바꿈 모두 같은 셈(모델 두 벌을 견줌).
/// 뒤를 읽지 못하면 오류, 앞을 읽지 못하면 모든 트랙(규칙 8).
pub fn between(before: &[PackIn], after: &[PackIn], opts: &Opts) -> Result<Touch> {
    let a = Snap::of(after, opts)?;
    let b = match Snap::of(before, opts) {
        Ok(b) => b,
        Err(e) => return Ok(Touch::all_tracks(a.keys, format!("규칙 8: 앞 조합을 읽지 못함 — {e}"))),
    };
    Ok(compare(&b, &a))
}

/// P4 틈(`packs::Layouter::touched`)의 꼴 — 앞 · 뒤 조합 → `Scope::Tracks(S)`(S = [`between`]의 열쇠). 모든 트랙이면 `Scope::All`.
/// 실제 틈 `packs::RustLayouter::touched`의 몸(과제 16b). 견주려고 준비한 '뒤' 조합의 문맥은 곧이어 그 조합을 내보낼 때 다시 쓰게 남긴다
/// (`lay::export::keep_prepared` — 넣기 한 번의 준비가 세 벌에서 두 벌로).
pub fn touched_scope(before: &[PackIn], after: &[PackIn], opts: &Opts) -> Result<Scope> {
    let ctx = ctx::context_of(after, opts, false)?;
    let a = Snap::read(&ctx);
    let t = match Snap::of(before, opts) {
        Ok(b) => compare(&b, &a),
        Err(e) => Touch::all_tracks(a.keys, format!("규칙 8: 앞 조합을 읽지 못함 — {e}")),
    };
    crate::lay::export::keep_prepared(after, opts, ctx);
    Ok(if t.everything.is_some() || t.keys.len() == t.all.len() { Scope::All } else { Scope::Tracks(t.keys) })
}

/// 조합의 트랙 열쇠(배치 없이 짐작 — 옛 트랙 → 판 트랙, 내보내기 차례). 빼기의 합성에서 '뒤에만 있는 트랙'(뺀 DLC가 숨기던 띠가 돌아와 다시 서는 판 트랙 따위)을
/// 더할 때 쓴다: 빼기 = `touched(뺀 것, 앞)` ∩ `keys(뒤)` ∪ (`keys(뒤)` − `keys(앞)`).
pub fn keys(packs: &[PackIn], opts: &Opts) -> Result<Vec<String>> {
    Ok(Snap::of(packs, opts)?.keys)
}

/// `all`에서 `new`의 자리 — 바이트가 같은 것, 없으면 DLC id가 같은 것.
fn position(new: &PackIn, all: &[PackIn], opts: &Opts) -> Result<usize> {
    if let Some(at) = all.iter().position(|p| p.bytes == new.bytes) {
        return Ok(at);
    }
    let rc = crate::lay::read::Ctx::new(opts)?;
    let id_of = |p: &PackIn| -> Result<String> {
        let raw = crate::lay::pack::raw_of(&rc, p, &mut Vec::new())?;
        let id = js::to_str(&raw.get("id")).as_str().into_owned();
        js::release(&raw);
        Ok(id)
    };
    let want = id_of(new)?;
    for (i, p) in all.iter().enumerate() {
        if id_of(p)? == want {
            return Ok(i);
        }
    }
    Err(format!("닿는 트랙: «{}»(DLC id {want})이 조합에 없습니다", new.name).into())
}

// ---------------------------------------------------------------- 한 조합의 모습

/// 모델 객체 하나.
struct Node {
    /// 내용 지문(다른 모델 객체는 이름표로만).
    digest: [u8; 32],
    /// 제 트랙(`track` 칸 — 트랙 id).
    home: BTreeSet<String>,
    /// 가리키는 모델 객체(이름표 자리).
    refs: BTreeSet<usize>,
}

/// 짐작한 판 트랙 하나.
struct Board {
    /// 판 트랙 열쇠(`board:__board:<판 열쇠>`).
    key: String,
    /// 판의 근원 객체의 이름표(`view:…` · `epoch:…`).
    source: String,
    /// 구성 나라가 든 트랙 id.
    members: BTreeSet<String>,
    /// 구성 나라(띠) uid — 판의 구성이 바뀌었나(판정 R46 C1).
    uids: BTreeSet<String>,
}

/// 한 조합의 모습 — 트랙 열쇠 · 모델 객체의 지문 · 판 · 전역 값.
struct Snap {
    /// 트랙 열쇠(옛 트랙 → 짐작한 판 트랙 — 내보내기 차례).
    keys: Vec<String>,
    /// 옛 트랙 id → 열쇠(차례대로).
    tracks: Vec<(String, String)>,
    /// 트랙 id → 그 트랙을 처음 말한 DLC id(트랙 항목의 `pack`).
    first_pack: HashMap<String, String>,
    /// 분류 번호 차례(`tl._cats`를 `i`로 정렬한 id).
    cats: Vec<String>,
    /// 간지 설정의 글(`model.yearCycle`).
    year_cycle: String,
    /// 주제가 있는가(렌즈 — 규칙 7).
    themes: bool,
    /// 모델 객체: 이름표 → 자리.
    index: HashMap<String, usize>,
    names: Vec<String>,
    nodes: Vec<Node>,
    boards: Vec<Board>,
    /// 판 둘레 — 자료 전체 띠의 해 범위(`scopes.mjs`의 `extentOf` 그대로 · 판정 R46 C2).
    extent: (f64, f64),
    /// 형식 4 이음(규칙 2)이 모델 객체가 아닌 것으로 풀림 — 그 대상의 트랙을 모르니 모든 트랙(모르면 넓게 · 지금 모델에서는 생기지 않음: `byUid`의 값도 모델 객체로 적힌다).
    unknown: Option<String>,
}

impl Snap {
    /// 조합을 준비까지 짓고(줄 배정 없음) 모습을 뜬다. 문맥은 버린다(Drop이 그래프를 푼다).
    fn of(packs: &[PackIn], opts: &Opts) -> Result<Snap> {
        let ctx = ctx::context_of(packs, opts, false)?;
        Ok(Snap::read(&ctx))
    }

    fn read(ctx: &Ctx) -> Snap {
        let model = &ctx.model;
        // 트랙 열쇠: 내보내기의 트랙 항목(`key` = 트랙 id · 비면 `n:<자료집>|<이름>` — patch::plain_key)과 같은 차례(tl.tracks).
        let labels: Vec<String> = ctx.packs.iter().map(|p| {
            let id = text_of(&p.get("id"));
            if id.is_empty() { text_of(&p.get("name")) } else { id }
        }).collect();
        let mut first_pack = HashMap::new();
        let mut tracks = Vec::new();
        for tr in list(&ctx.tl.get("tracks")) {
            let id = text_of(&tr.get("id"));
            let at = ctx.track_pack.get(&tr.get("id"));
            let label = labels.get(if let V::Num(x) = at { x as usize } else { 0 }).cloned().unwrap_or_default();
            let key = match tr.get("id") {
                V::Str(s) if !s.is_empty() => s.as_str().into_owned(),
                _ => format!("n:{label}|{}", match js::or(tr.get("name"), tr.get("id")) { V::Str(s) => s.as_str().into_owned(), _ => String::new() }),
            };
            first_pack.insert(id.clone(), label);
            tracks.push((id, key));
        }
        // 분류 번호 차례(export/tracks.mjs: tl._cats를 i로 정렬한 자리가 분류 번호).
        let mut cats: Vec<(String, f64)> = match ctx.tl.get("_cats") {
            V::Map(m) => m.entries().into_iter().map(|(k, c)| (text_of(&k), js::to_num(&c.get("i")))).collect(),
            _ => Vec::new(),
        };
        cats.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
        let year_cycle = match model.get("yearCycle") { V::Undef => "undefined".to_string(), y => js::stringify(&y) };
        let themes = match model.get("themeMap") { V::Map(m) => !m.is_empty(), _ => false } || !list(&model.get("themes")).is_empty();

        let mut snap = Snap {
            keys: Vec::new(), tracks, first_pack, cats: cats.into_iter().map(|c| c.0).collect(), year_cycle, themes,
            index: HashMap::new(), names: Vec::new(), nodes: Vec::new(), boards: Vec::new(), extent: (f64::INFINITY, f64::NEG_INFINITY), unknown: None,
        };
        let track_ids: BTreeSet<String> = snap.tracks.iter().map(|t| t.0.clone()).collect();
        let objs = snap.register(model);
        snap.digest_all(model, &objs.0, &objs.1, &track_ids);
        snap.boards = boards_of(ctx, &snap.index);
        snap.keys = snap.tracks.iter().map(|t| t.1.clone()).chain(snap.boards.iter().map(|b| b.key.clone())).collect();
        drop(objs); // 자리 표는 모델 객체의 Rc 사본을 쥘 뿐 — 버리기만 한다(풀면 모델이 빈다 · 문맥의 Drop이 그래프를 푼다)
        snap.extent = extent_of(ctx);
        snap
    }

    /// 모델 객체를 이름표로 적는다(차례: 아래 목록 → 모델의 나머지 열쇠). 같은 객체가 두 곳에 있으면(예: `periods`와 `byUid`) 처음 것.
    /// 돌려주는 것: (자리 → 객체, 객체 → 자리의 표).
    fn register(&mut self, model: &V) -> (Vec<V>, Map) {
        const FIRST: [(&str, &str); 13] = [
            ("trackMap", "track"), ("periods", "period"), ("events", "event"), ("figures", "figure"), ("lineageFigures", "figure"), ("epochs", "epoch"),
            ("scopes", "scope"), ("views", "view"), ("groups", "group"), ("institutions", "inst"), ("peopleMap", "people"), ("categoryMap", "cat"), ("themeMap", "theme"),
        ];
        let at = Map::new();
        let mut objs: Vec<V> = Vec::new();
        let Some(mo) = model.as_obj() else { return (objs, at) };
        let mut put = |snap: &mut Snap, kind: &str, v: &V, fallback: String| {
            if !matches!(v, V::Obj(_)) || at.has(v) {
                return;
            }
            let base = match (v.get("uid"), v.get("id")) {
                (V::Str(u), _) if !u.is_empty() => format!("{kind}:{}", u.as_str()),
                (_, V::Str(i)) if !i.is_empty() => format!("{kind}:{}", i.as_str()),
                (_, V::Num(x)) => format!("{kind}:{}", js::num_str(x)),
                _ => fallback,
            };
            // 같은 이름표가 둘이면(같은 id를 둘이 씀) 뒤에 번호 — 앞 · 뒤 조합에서 차례가 같으면 같은 이름표.
            let mut name = base.clone();
            let mut k = 2;
            while snap.index.contains_key(&name) {
                name = format!("{base}#{k}");
                k += 1;
            }
            at.set(v.clone(), V::Num(objs.len() as f64));
            snap.index.insert(name.clone(), objs.len());
            snap.names.push(name);
            objs.push(v.clone());
        };
        let mut walk = |snap: &mut Snap, coll: &str, kind: &str| match mo.get(coll) {
            V::Arr(l) => {
                for (i, v) in l.to_vec().iter().enumerate() {
                    put(snap, kind, v, format!("{kind}#{i}"));
                }
            }
            V::Map(m) => {
                for (k, v) in m.entries() {
                    put(snap, kind, &v, format!("{kind}:{}", text_of(&k)));
                }
            }
            _ => {}
        };
        for (coll, kind) in FIRST {
            walk(self, coll, kind);
        }
        for k in mo.keys() {
            let coll = k.as_str().into_owned();
            if FIRST.iter().any(|(c, _)| *c == coll) {
                continue;
            }
            walk(self, &coll, &coll);
        }
        (objs, at)
    }

    /// 객체마다 내용 지문 · 제 트랙 · 가리키는 객체.
    fn digest_all(&mut self, model: &V, objs: &[V], at: &Map, track_ids: &BTreeSet<String>) {
        // uid 글 → 자리(uid 글로 가리키는 이음 — polityUid · parentUid · partOfUid 같은 칸).
        let mut by_uid: HashMap<String, usize> = HashMap::new();
        for (i, v) in objs.iter().enumerate() {
            if let V::Str(u) = v.get("uid") {
                if !u.is_empty() {
                    by_uid.entry(u.as_str().into_owned()).or_insert(i);
                }
            }
        }
        // 규칙 2의 형식 4 이음 — 띠(`model.periods`)마다 내보내기와 같은 찾기로 푼 대상의 자리(못 찾으면 None).
        let periods = list(&model.get("periods"));
        let uid_map = model.get("byUid");
        let mut links: HashMap<usize, Vec<Option<usize>>> = HashMap::new();
        for p in &periods {
            let V::Num(i) = at.get(p) else { continue };
            let found: Vec<Option<usize>> = format4_links(p, &periods, &uid_map).into_iter().map(|x| match at.get(&x) {
                V::Num(j) => Some(j as usize),
                _ => {
                    if tv(&x) && self.unknown.is_none() {
                        self.unknown = Some(format!("규칙 2: {}의 형식 4 이음이 모델 객체가 아닌 것으로 풀림", self.names[i as usize]));
                    }
                    None
                }
            }).collect();
            if !found.is_empty() {
                links.insert(i as usize, found);
            }
        }
        for (i, v) in objs.iter().enumerate() {
            let mut node = digest_one(i, v, at, &self.names, &by_uid, track_ids, links.get(&i).map_or(&[][..], Vec::as_slice));
            // 트랙 객체(`trackMap` — 이름표 `track:<id>`)는 제 트랙이 곧 집이다: 트랙 항목(`tracks.mjs`)의 이름 · 색 · 문화권을 이 객체에서 읽는다
            // (판정 R54 I1 — `track` 칸이 없어 집이 비면 이름 · 색만 바뀐 판 바꿈에서 그 트랙이 빠졌다).
            if self.names[i].starts_with("track:") {
                let id = text_of(&v.get("id"));
                if track_ids.contains(&id) {
                    node.home.insert(id);
                }
            }
            self.nodes.push(node);
        }
    }
}

/// 값의 글(글이 아니면 `String(x)` — 수 · 참거짓 · null · undefined만 쓴다).
fn text_of(v: &V) -> String {
    match v {
        V::Str(s) => s.as_str().into_owned(),
        V::Num(x) => js::num_str(*x),
        V::Bool(b) => b.to_string(),
        V::Null => "null".into(),
        V::Undef => "undefined".into(),
        _ => String::new(),
    }
}

/// 배열의 원소(배열이 아니면 빈 것).
fn list(v: &V) -> Vec<V> {
    if let V::Arr(a) = v { a.to_vec() } else { Vec::new() }
}

/// 객체 하나의 내용 지문. 다른 모델 객체(`at`에 든 그릇)는 그 **이름표**(`names` — 조합이 달라도 같은 객체면 같은 글 · 자리 번호는 앞에 객체가 끼면 밀리므로 쓰지 않음)로만
/// 적고 이음에 넣는다. 그 밖의 그릇은 안으로 들어가 적되 한 객체 안에서 두 번 만나면(고리 · 나눠 가짐) `@`. 글이 어떤 객체의 uid면 이음에 넣는다(글은 그대로 적음).
/// `track` 칸의 글이 트랙 id면 제 트랙. 되부름 없이(깊이 한계 없음) 쌓개로 돈다.
/// `links`는 형식 4 이음([`format4_links`] — 글로 남아 내보내기가 그때 찾는 대상)을 푼 자리: 이음에 넣고 그 이름표(못 찾으면 `?`)를 지문 끝에 적는다 —
/// 찾기가 다른 객체로 풀리면(패치가 이름을 바꾸거나 · 숨기거나) 이 객체가 바뀐 것으로 잡혀 앞 · 뒤의 대상이 모두 든다.
fn digest_one(me: usize, root: &V, at: &Map, names: &[String], by_uid: &HashMap<String, usize>, track_ids: &BTreeSet<String>, links: &[Option<usize>]) -> Node {
    enum Work {
        Val(V, bool),
        Tag(&'static [u8]),
        Key(String),
    }
    let mut h = Sha256::new();
    let mut home = BTreeSet::new();
    let mut refs = BTreeSet::new();
    let seen = Set::new();
    let mut stack: Vec<Work> = vec![Work::Val(root.clone(), false)];
    let mut first = true;
    while let Some(w) = stack.pop() {
        let (v, is_track) = match w {
            Work::Tag(t) => {
                h.update(t);
                continue;
            }
            Work::Key(k) => {
                h.update(b"k");
                h.update((k.len() as u64).to_le_bytes());
                h.update(k.as_bytes());
                continue;
            }
            Work::Val(v, is_track) => (v, is_track),
        };
        match &v {
            V::Undef => h.update(b"u"),
            V::Null => h.update(b"n"),
            V::Bool(b) => h.update(if *b { b"t" } else { b"f" }),
            V::Num(x) => {
                h.update(b"#");
                h.update(x.to_bits().to_le_bytes());
            }
            V::Str(s) => {
                let text = s.as_str();
                h.update(b"s");
                h.update((text.len() as u64).to_le_bytes());
                h.update(text.as_bytes());
                if let Some(&i) = by_uid.get(text.as_ref()) {
                    if i != me {
                        refs.insert(i);
                    }
                }
                if is_track && track_ids.contains(text.as_ref()) {
                    home.insert(text.into_owned());
                }
            }
            V::Arr(_) | V::Obj(_) | V::Map(_) | V::Set(_) => {
                // 다른 모델 객체 → 이름표 자리만.
                if !first {
                    if let V::Num(i) = at.get(&v) {
                        let i = i as usize;
                        h.update(b">");
                        h.update((names[i].len() as u64).to_le_bytes());
                        h.update(names[i].as_bytes());
                        if i != me {
                            refs.insert(i);
                        }
                        continue;
                    }
                }
                first = false;
                if seen.has(&v) {
                    h.update(b"@");
                    continue;
                }
                seen.add(v.clone());
                // 닫는 표를 먼저 쌓고 안의 것을 거꾸로 쌓는다(쌓개라 차례대로 나옴).
                match &v {
                    V::Arr(a) => {
                        h.update(b"[");
                        stack.push(Work::Tag(b"]"));
                        for x in a.to_vec().into_iter().rev() {
                            stack.push(Work::Val(x, false));
                        }
                    }
                    V::Obj(o) => {
                        h.update(b"{");
                        stack.push(Work::Tag(b"}"));
                        for (k, x) in o.entries().into_iter().rev() {
                            let key = k.as_str().into_owned();
                            let track = key == "track";
                            stack.push(Work::Val(x, track));
                            stack.push(Work::Key(key));
                        }
                    }
                    V::Map(m) => {
                        h.update(b"M");
                        stack.push(Work::Tag(b")"));
                        for (k, x) in m.entries().into_iter().rev() {
                            stack.push(Work::Val(x, false));
                            stack.push(Work::Val(k, false));
                        }
                    }
                    V::Set(s) => {
                        h.update(b"S");
                        stack.push(Work::Tag(b")"));
                        for x in s.values().into_iter().rev() {
                            stack.push(Work::Val(x, false));
                        }
                    }
                    _ => unreachable!(),
                }
            }
        }
    }
    // 만난 그릇 표(Set)는 모델 그릇의 Rc 사본을 쥘 뿐 — 버리기만 한다(풀면 모델이 빈다).
    drop(seen);
    // 형식 4 이음(규칙 2) — 이음이 없는 객체는 지문에 아무것도 더하지 않는다(있던 지문 그대로).
    for l in links {
        h.update(b"L");
        match l {
            Some(j) => {
                h.update(b">");
                h.update((names[*j].len() as u64).to_le_bytes());
                h.update(names[*j].as_bytes());
                if *j != me {
                    refs.insert(*j);
                }
            }
            None => h.update(b"?"),
        }
    }
    Node { digest: h.finalize().into(), home, refs }
}

/// 띠 하나의 형식 4 이음(규칙 2) — 모델에 **글**(객체 uid · id · 이름)로 남아 내보내기가 그때 찾는 대상을 같은 찾기로 푼 것(찾은 객체 · 못 찾으면 undefined/null),
/// 내보내기가 보는 차례대로:
/// - 남의 실권 `power[].over` — `m/power.rs` `power_lines`의 `over` 찾기(`power.mjs`): uid(`model.byUid`) → 같은 DLC(`packId`)의 띠 id → 이름.
///   쥔 쪽의 이름 · 색이 상대 띠의 구역 56(실권 밑줄)에 실린다. over 없이 이름만인 줄(제 안의 실권자)은 제 띠에 실리므로 이음이 아니다.
/// - 직위 줄 빌림 `leadersFrom` · `cabinetsFrom`의 `from` · `offices[].from` — `m/strips.rs` `from_of`(`strips.mjs` `fromOf`): 글 전체가 uid면 그 객체,
///   아니면 첫 `/` 앞(직위 이름 떼고)을 같은 DLC의 띠 id → 이름. 출처의 이름이 빌린 쪽 띠의 구역 54 머리 글에, 출처의 직위 줄 칸이 직위 줄 더(칸 종류 9)에 실린다.
fn format4_links(p: &V, periods: &[V], uid_map: &V) -> Vec<V> {
    let by_uid = |k: &V| match uid_map { V::Map(m) => m.get(k), _ => V::Undef };
    let pk = p.get("packId");
    let in_pack = |field: &str, key: &V| periods.iter().find(|q| eq(&q.get("packId"), &pk) && eq(&q.get(field), key)).cloned();
    let mut out = Vec::new();
    if matches!(p.get("power"), V::Arr(_)) {
        for w in list(&p.get("power")) {
            if !tv(&w) || !tv(&w.get("over")) {
                continue;
            }
            let key = V::Str(js::to_str(&w.get("over")).trim());
            let mut target = by_uid(&key);
            if !tv(&target) { target = in_pack("id", &key).unwrap_or(V::Undef); }
            if !tv(&target) { target = in_pack("name", &key).unwrap_or(V::Undef); }
            out.push(target);
        }
    }
    let from_of = |r: &V| -> V {
        let text = js::to_str(&nn(r.clone(), s(""))).trim();
        let whole = by_uid(&V::Str(text.clone()));
        if tv(&whole) {
            return whole;
        }
        let cut = text.index_of16(&Str::from("/"), 0.0);
        let key = V::Str(if cut >= 0.0 { text.slice16(0.0, cut).trim() } else { text });
        in_pack("id", &key).or_else(|| in_pack("name", &key)).unwrap_or(V::Null)
    };
    for k in ["leadersFrom", "cabinetsFrom"] {
        let v = p.get(k);
        if tv(&v) && tv(&v.get("from")) {
            out.push(from_of(&v.get("from")));
        }
    }
    if matches!(p.get("offices"), V::Arr(_)) {
        for o in list(&p.get("offices")) {
            if !tv(&o) || matches!(o, V::Bool(_) | V::Num(_) | V::Str(_)) {
                continue;
            }
            let from = o.get("from");
            if tv(&from) {
                out.push(from_of(&from));
            }
        }
    }
    out
}

/// 판 둘레 — `export/scopes.mjs`의 `extentOf(ctx)`(59줄 · Rust `m::scopes::extent_of`)와 같은 셈: 모델의 모든 띠의 바깥 끝(`bandStart` · `bandEnd`) 가운데 유한한 값의 최소 · 최대.
/// 판 트랙의 구역 23(집합 보기 판의 둘레)이 이 값을 싣는다(판정 R46 C2).
fn extent_of(ctx: &Ctx) -> (f64, f64) {
    use crate::lay::rows::{band_end, band_start, is_finite_num};
    let (mut lo, mut hi) = (f64::INFINITY, f64::NEG_INFINITY);
    for p in list(&ctx.model.get("periods")) {
        let (a, b) = (band_start(&p), band_end(&p));
        if is_finite_num(&a) && js::to_num(&a) < lo { lo = js::to_num(&a); }
        if is_finite_num(&b) && js::to_num(&b) > hi { hi = js::to_num(&b); }
    }
    (lo, hi)
}

/// 집합 보기의 판(배치 없이 짐작) — `export/boards.mjs`의 `boardsOf`(모아 보기 판 · 시대의 임시 판 · 같은 열쇠는 처음 것)와
/// `boardOne`의 첫 거름(구성 나라가 연표 트랙에 하나도 없으면 판을 뺌 — `_boardPlan`의 `owner`)을 따른다.
fn boards_of(ctx: &Ctx, index: &HashMap<String, usize>) -> Vec<Board> {
    let (model, tl) = (&ctx.model, &ctx.tl);
    // 정권 uid → 그 정권을 든 트랙(tl.tracks[].periods — 왕조는 들지 않음).
    let owner: HashMap<String, String> = list(&tl.get("tracks")).iter()
        .flat_map(|tr| list(&tr.get("periods")).into_iter().map(move |p| (text_of(&p.get("uid")), text_of(&tr.get("id")))))
        .collect();
    let mut out: Vec<Board> = Vec::new();
    let mut keys: BTreeSet<String> = BTreeSet::new();
    let mut push = |key: String, source: String, members: Vec<V>| {
        let uids: Vec<String> = members.iter().map(|p| text_of(&p.get("uid"))).collect();
        if !uids.iter().any(|u| owner.contains_key(u)) {
            return; // 판을 켜도 판 트랙이 서지 않는다(boardOne → null)
        }
        let mut tracks: BTreeSet<String> = uids.iter().filter_map(|u| owner.get(u).cloned()).collect();
        tracks.extend(members.iter().map(|p| text_of(&p.get("track"))).filter(|t| !t.is_empty()));
        out.push(Board { key: format!("{BOARD_PREFIX}{key}"), source, members: tracks, uids: uids.into_iter().collect() });
    };
    let name_of = |kind: &str, x: &V| -> String {
        let n = format!("{kind}:{}", text_of(&x.get("uid")));
        if index.contains_key(&n) { n } else { format!("{kind}:?") }
    };
    for v in list(&model.get("views")) {
        let members: Vec<V> = list(&v.get("members")).into_iter().filter(tv).collect();
        if members.is_empty() {
            continue;
        }
        let key = text_of(&v.get("uid"));
        if !keys.insert(key.clone()) {
            continue;
        }
        push(key, name_of("view", &v), members);
    }
    for x in list(&model.get("epochs")) {
        let st = x.get("start");
        let en = if !x.get("endY").is_nullish() { x.get("endY") } else { x.get("start") };
        let (V::Num(sv), V::Num(ev)) = (&st, &en) else { continue };
        if !sv.is_finite() || !ev.is_finite() {
            continue;
        }
        let in_scopes: BTreeSet<String> = list(&x.get("scopes")).iter().flat_map(|sc| list(&sc.get("members"))).map(|p| text_of(&p.get("uid"))).collect();
        let l: Vec<V> = list(&model.get("periods")).into_iter().filter(|p| {
            let pe = if !p.get("endY").is_nullish() { p.get("endY") } else { p.get("start") };
            matches!(item_kind_of(p), V::Str(k) if k.as_str() == "period") && (!tv(&x.get("track")) || js::strict_eq(&p.get("track"), &x.get("track")))
                && lt(&p.get("start"), &en) && lt(&st, &pe) && !in_scopes.contains(&text_of(&p.get("uid")))
        }).collect();
        if l.is_empty() {
            continue;
        }
        let key = format!("view:epoch:{}", text_of(&x.get("uid")));
        if !keys.insert(key.clone()) {
            continue;
        }
        push(key, name_of("epoch", &x), l);
    }
    out
}

// ---------------------------------------------------------------- 견주기

/// 앞(b) · 뒤(a)의 모습을 견주어 뒤의 닿는 트랙을 모은다(모듈 머리글의 규칙 표).
fn compare(b: &Snap, a: &Snap) -> Touch {
    let mut t = Touch { all: a.keys.clone(), ..Touch::default() };
    // 내용이 다른 모델 객체(규칙 1 · 2의 재료) — 모든 트랙이 되는 길(규칙 3 · 4)에서도 그 수는 알린다(넓이 검사가 빈 시험을 가리는 데 씀).
    let mut changed: Vec<&str> = Vec::new();
    for (name, &i) in &a.index {
        match b.index.get(name) {
            Some(&j) if b.nodes[j].digest == a.nodes[i].digest => {}
            _ => changed.push(name.as_str()),
        }
    }
    for name in b.index.keys() {
        if !a.index.contains_key(name) {
            changed.push(name.as_str());
        }
    }
    changed.sort_unstable();
    let everything = |why: &str| { let mut x = Touch::all_tracks(a.keys.clone(), why.into()); x.changed = changed.len(); x };
    // 규칙 2의 형식 4 이음이 모델 객체가 아닌 것으로 풀림 — 모르면 넓게.
    if let Some(why) = a.unknown.as_ref().or(b.unknown.as_ref()) {
        return everything(why);
    }
    // 규칙 3 · 4: 모든 트랙.
    if a.cats != b.cats {
        return everything("규칙 3: 분류 번호 차례가 다름");
    }
    if a.year_cycle != b.year_cycle {
        return everything("규칙 4: 간지 설정이 다름");
    }
    let common: BTreeSet<&str> = a.tracks.iter().map(|x| x.0.as_str()).filter(|id| b.tracks.iter().any(|y| y.0 == *id)).collect();
    fn order<'s>(s: &'s Snap, common: &BTreeSet<&str>) -> Vec<&'s str> {
        s.tracks.iter().map(|x| x.0.as_str()).filter(|id| common.contains(id)).collect()
    }
    if order(a, &common) != order(b, &common) {
        return everything("규칙 4: 트랙의 상대 차례가 다름");
    }
    let key_of: HashMap<&str, &str> = a.tracks.iter().map(|(id, key)| (id.as_str(), key.as_str())).collect();
    let hit = |t: &mut Touch, track: &str, why: &dyn Fn() -> String| {
        if let Some(key) = key_of.get(track) {
            t.add(key, why);
        }
    };
    // 새 트랙 · 규칙 5.
    for (id, _) in &a.tracks {
        match b.first_pack.get(id) {
            None => hit(&mut t, id, &|| "새 트랙".into()),
            Some(label) if a.first_pack.get(id) != Some(label) => hit(&mut t, id, &|| "규칙 5: 트랙을 처음 말한 DLC가 다름".into()),
            _ => {}
        }
    }
    // 규칙 1 · 2: 내용이 다른 모델 객체 → 제 트랙 · 이어진 객체의 제 트랙(앞 · 뒤 두 모델에서).
    let inbound = |s: &Snap| -> Vec<Vec<usize>> {
        let mut inn = vec![Vec::new(); s.nodes.len()];
        for (i, nd) in s.nodes.iter().enumerate() {
            for &j in &nd.refs {
                inn[j].push(i);
            }
        }
        inn
    };
    let (in_a, in_b) = (inbound(a), inbound(b));
    t.changed = changed.len();
    let mut changed_set: BTreeSet<&str> = BTreeSet::new();
    for name in &changed {
        changed_set.insert(*name);
        for (s, inn, side) in [(a, &in_a, "뒤"), (b, &in_b, "앞")] {
            let Some(&i) = s.index.get(*name) else { continue };
            for tr in &s.nodes[i].home {
                hit(&mut t, tr, &|| format!("규칙 1: {name}({side})"));
            }
            for &j in s.nodes[i].refs.iter().chain(inn[i].iter()) {
                for tr in &s.nodes[j].home {
                    hit(&mut t, tr, &|| format!("규칙 2: {name}({side})과 이어진 {}", s.names[j]));
                }
            }
        }
    }
    // 규칙 7: 렌즈 — 렌즈 변형(kind 4)은 첫 트랙(`track: 0`)에 실리고 모든 트랙의 칸 · 항목을 가린다. 내장 주제(8개)가 늘 있어 사실상 무엇이든 바뀌면
    // 앞 · 뒤의 첫 트랙(뒤에 있는 것)이 든다. 판(규칙 6)보다 먼저 셈하되(판정 R46 Minor) 규칙 7로만 든 첫 트랙은 판을 끌지 않는다 — 렌즈 변형은 판을 켠 배치에
    // 들지 않아 그 판의 차이가 바뀌지 않는다(판정 R54 M3). 판의 구조가 바뀌어 구성 나라의 트랙으로도 들면 그때는 판을 끈다.
    let mut lens_only: BTreeSet<String> = BTreeSet::new();
    if (a.themes || b.themes) && (changed_set.len() + t.keys.len()) > 0 {
        for s in [a, b] {
            if let Some((id, _)) = s.tracks.first() {
                if key_of.get(id.as_str()).is_some_and(|k| !t.keys.contains(*k)) {
                    lens_only.insert(id.clone());
                }
                hit(&mut t, id, &|| "규칙 7: 렌즈 변형은 첫 트랙에 실림".into());
            }
        }
    }
    // 규칙 6: 판 트랙(판정 R46 C1 · C2로 고침). 판 하나의 차이(`boards.mjs`의 diff)는 판 트랙에만 실리지 않는다 — 판을 켠 배치의 변형 판 항목 · 칸(`itemsOutside`)이
    // **원래 트랙(구성 나라의 트랙)** 에 실린다. 그래서
    // - 판이 새로 서거나 · 사라지거나(앞에만 있는 판도 돈다) · 근원(모아 보기 판 · 시대)이 바뀌거나 · 구성 띠의 집합이 바뀌면 → 그 판(뒤에 있으면)과 구성 나라의 트랙(앞 ∪ 뒤) 전부.
    // - 판 둘레(`scopes.mjs`의 `extentOf` — 자료 전체 띠의 해 범위 · 판 트랙의 구역 23 start · end)가 다르면 → 판 트랙 전부.
    // - 구성 나라의 트랙이 닿으면 → 그 판(그 판을 다시 돌린 차이가 바뀜) — 새로 닿은 트랙이 다른 판을 닿게 할 수 있어 더 늘지 않을 때까지 돈다.
    let extent_moved = a.extent.0.to_bits() != b.extent.0.to_bits() || a.extent.1.to_bits() != b.extent.1.to_bits();
    let mut keys_all: Vec<&str> = a.boards.iter().map(|x| x.key.as_str()).collect();
    for x in &b.boards {
        if !keys_all.contains(&x.key.as_str()) {
            keys_all.push(x.key.as_str());
        }
    }
    let mut done: BTreeSet<&str> = BTreeSet::new();
    loop {
        let regular: BTreeSet<String> = t.keys.clone();
        let touched_ids: BTreeSet<String> = a.tracks.iter().filter(|(id, key)| regular.contains(key) && !lens_only.contains(id)).map(|(id, _)| id.clone())
            .chain(b.tracks.iter().filter(|(id, _)| !key_of.contains_key(id.as_str())).map(|(id, _)| id.clone())) // 사라진 트랙(앞에만)도 닿은 것
            .collect();
        let mut grew = false;
        for key in &keys_all {
            if done.contains(key) {
                continue;
            }
            let (new, old) = (a.boards.iter().find(|x| x.key == *key), b.boards.iter().find(|x| x.key == *key));
            let members: BTreeSet<&String> = new.iter().chain(old.iter()).flat_map(|x| x.members.iter()).collect();
            let structural = match (new, old) {
                (Some(_), None) => Some("새 판".to_string()),
                (None, Some(_)) => Some("사라진 판".to_string()),
                (Some(x), Some(y)) if changed_set.contains(x.source.as_str()) || changed_set.contains(y.source.as_str()) => Some(format!("판의 근원 {}이 바뀜", x.source)),
                (Some(x), Some(y)) if x.uids != y.uids => Some("판의 구성 띠가 바뀜".to_string()),
                _ => None,
            };
            let why = if let Some(w) = structural {
                // 구성 나라의 트랙에도 판을 켠 배치의 변형 판 항목 · 칸이 실린다 — 한 겹.
                for m in &members {
                    lens_only.remove(m.as_str());
                    let w = w.clone();
                    hit(&mut t, m, &move || format!("규칙 6: {key} — {w}(구성 나라의 트랙)"));
                }
                Some(format!("규칙 6: {w}"))
            } else if extent_moved {
                Some("규칙 6: 판 둘레(자료 전체 해 범위)가 바뀜".to_string())
            } else {
                members.iter().find(|m| touched_ids.contains(m.as_str())).map(|m| format!("규칙 6: 구성 나라의 트랙 {m}이 닿음"))
            };
            if let Some(why) = why {
                done.insert(key);
                grew = true;
                if new.is_some() {
                    t.add(key, || why);
                }
            }
        }
        if !grew {
            break;
        }
    }
    t
}

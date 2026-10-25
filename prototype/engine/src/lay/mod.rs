//! 한 벌 P3 — Node(`js/*.js` + `prototype/scripts/export/*.mjs`)가 하던 배치 셈을 Rust로 옮기는 자리.
//! 지금 있는 것: 입력 · 선택 꼴 · 정답지 견주기(`same`) · JS 값의 뜻(`js` — 옮기는 규칙의 바탕) · 읽기(`read` · `f4` · `cal` · `pack` — 이음매 ①) ·
//! 모델과 준비(`model` · `link` · `ctx` — 이음매 ② 앞) · 줄 배정(`track` · `rows` · `scope` — 이음매 ② 뒤) · 내보내기 틀(`export` · 모듈 `m/` — 이음매 ③ · 과제 8-틀) ·
//! 여러 모듈이 함께 부르는 웹 함수(`web` — 과제 Y가 갈래들의 겹친 사본을 하나로).
//! 옮기는 규칙 · 차례는 `docs/계획-한벌-P3-Rust배치.md`. 정답지는 Node 내보내기 결과(`node prototype/scripts/layout-oracle.mjs`)이며 Rust는 그것과 차이 0이어야 한다.
use std::collections::BTreeSet;
use std::rc::Rc;

pub mod cal;
pub mod ctx;
pub mod export;
pub mod f4;
pub mod js;
pub mod link;
pub mod m;
pub mod model;
pub mod pack;
pub mod read;
pub mod rows;
pub mod rules;
pub mod same;
pub mod scope;
pub mod touch;
pub mod track;
pub mod web;

pub use export::{export, export_late, export_one};
pub use rules::rules;
pub use touch::touched;

/// 규칙 판(계획 과제 16 · 설계 3-4 '규칙 판') — 옮긴 원본(내보내기 모듈 `prototype/scripts/export/*.mjs` · 그 모듈이 불러 쓰는 웹 코드 `js/*.js`)의
/// `<파일 이름>:<SHA-256 앞 12자>`를 파일 이름 차례(웹 코드 → 모듈)로 빈칸으로 이은 글(줄 끝 LF로 셈). 원본이 바뀌면(정답지를 다시 뽑아 Rust를 고칠 일)
/// 낡음 검사(`tests/lay_scope.rs`)가 멈춘다 — 만드는 도구: `node prototype/scripts/lay-rules.mjs [--check | --write]`.
/// P4 지문 · `meta.rules`에 섞는 것은 이 글이 아니라 판 번호 [`rules()`](`rules::LAY_RULES_VERSION` — 배치 출력이 달라질 때만 올림 · 골든 검사가 지킴 · 판정 R61 I1).
pub const RULES: &str = "calendar.js:96df71e8ba39 core.js:78517802c6cb group-tree.js:a7e15f1b80f3 packfile.js:385bb108c2c8 timeline.js:16d4297a807a wiki.js:fb6c22f7437a axis.mjs:883f2b87af64 bands.mjs:96aa9d433cdd base.mjs:a1279f6433d5 boards.mjs:d285b8d53915 calendar.mjs:57b5c258af24 docs.mjs:042e0e3b132a entities.mjs:02d5c3a469ca events.mjs:88d900fe7588 figures.mjs:cd6b411d137c hangs.mjs:bb8167868fcf kin.mjs:2d22e4bdd520 labels.mjs:0cc7aaddc105 lens.mjs:51c3b6c4e201 links.mjs:52261e5442f1 metro.mjs:905bf758b0b5 minibars.mjs:d42f01da6da0 persons.mjs:ba97541280bb power.mjs:80a830927e70 rails.mjs:abc4adab11ed scopes.mjs:b4693b280b53 strips.mjs:097509879db0 tracks.mjs:fa754953ed78 variants.mjs:5909554482c2";

/// 이 스레드에 남긴 셈 그릇을 비운다 — 푼 달력 표(`cal::clear_shared`)와 닿는 트랙이 남긴 준비 문맥(`export::clear_prepared`). DLC 넣고 빼기 한 번이
/// 끝나면(성공 · 실패 모두) `packs`가 부른다(판정 R69-5 — 앱의 엔진 스레드가 다음 넣기까지 표 · 문맥을 쥐지 않게).
pub fn clear_caches() {
    cal::clear_shared();
    export::clear_prepared();
}

/// 모듈 함수의 꼴 —`export function contribute(ctx, out)` · `contributeLate(ctx, out)`(계약 4절 · base.mjs 머리말). JS라면 던졌을 곳은 오류.
pub type Contribute = fn(&mut ctx::Ctx, &mut serde_json::Value) -> crate::Result<()>;

/// 내보내기 모듈 하나(`lay/m/<이름>.rs` = `prototype/scripts/export/<이름>.mjs`). `ported`가 거짓이면 아직 옮기지 않은 것 — `contribute`는 거절한다.
pub struct Module { pub name: &'static str, pub ported: bool, pub contribute: Contribute, pub late: Option<Contribute> }

/// 내보내기 모듈 차례(`prototype/scripts/export/base.mjs`의 `MODULES`와 같다 — 앞자리 k개의 출력이 곧 진척). 모듈마다 한 줄 — 갈래는 제 모듈 파일(`m/<이름>.rs`)만 고친다
/// (`PORTED`를 참으로 · 함수를 채움): 이 표는 손대지 않는다. 리메이크 3단계가 `persons`(사람 띠 — figures 뒤)를 더해 스물하나. 늦은 차례(`contributeLate`)가 있는 모듈은 넷(tracks · docs · power · metro — 그 차례).
pub const MODULES: [Module; 21] = [
    Module { name: "tracks", ported: m::tracks::PORTED, contribute: m::tracks::contribute, late: Some(m::tracks::contribute_late) },

    Module { name: "axis", ported: m::axis::PORTED, contribute: m::axis::contribute, late: None },

    Module { name: "bands", ported: m::bands::PORTED, contribute: m::bands::contribute, late: None },

    Module { name: "strips", ported: m::strips::PORTED, contribute: m::strips::contribute, late: None },

    Module { name: "events", ported: m::events::PORTED, contribute: m::events::contribute, late: None },

    Module { name: "hangs", ported: m::hangs::PORTED, contribute: m::hangs::contribute, late: None },

    Module { name: "figures", ported: m::figures::PORTED, contribute: m::figures::contribute, late: None },
    Module { name: "persons", ported: m::persons::PORTED, contribute: m::persons::contribute, late: None },

    Module { name: "rails", ported: m::rails::PORTED, contribute: m::rails::contribute, late: None },

    Module { name: "links", ported: m::links::PORTED, contribute: m::links::contribute, late: None },

    Module { name: "scopes", ported: m::scopes::PORTED, contribute: m::scopes::contribute, late: None },

    Module { name: "labels", ported: m::labels::PORTED, contribute: m::labels::contribute, late: None },

    Module { name: "minibars", ported: m::minibars::PORTED, contribute: m::minibars::contribute, late: None },

    Module { name: "docs", ported: m::docs::PORTED, contribute: m::docs::contribute, late: Some(m::docs::contribute_late) },

    Module { name: "calendar", ported: m::calendar::PORTED, contribute: m::calendar::contribute, late: None },

    Module { name: "entities", ported: m::entities::PORTED, contribute: m::entities::contribute, late: None },

    Module { name: "power", ported: m::power::PORTED, contribute: m::power::contribute, late: Some(m::power::contribute_late) },

    Module { name: "variants", ported: m::variants::PORTED, contribute: m::variants::contribute, late: None },

    Module { name: "boards", ported: m::boards::PORTED, contribute: m::boards::contribute, late: None },

    Module { name: "metro", ported: m::metro::PORTED, contribute: m::metro::contribute, late: Some(m::metro::contribute_late) },

    Module { name: "lens", ported: m::lens::PORTED, contribute: m::lens::contribute, late: None },
];

/// 옮긴 **앞자리**의 길이 — `export`(통째)가 돌릴 수 있는 모듈 수(`upto-<MODULES[PORTED_PREFIX-1]>`까지 Node와 같아야 한다 — `tests/lay_out.rs`).
/// 갈래가 동시에 옮기므로 옮긴 모듈이 앞자리가 아닐 수 있다 — 그것은 [`ported_count`]. (모듈 파일의 `PORTED: bool`과 이름을 가른다.)
pub const PORTED_PREFIX: usize = ported_prefix();
const fn ported_prefix() -> usize {
    let mut k = 0;
    while k < MODULES.len() && MODULES[k].ported { k += 1; }
    k
}
/// 옮긴 모듈의 수(앞자리와 무관).
pub const fn ported_count() -> usize {
    let (mut k, mut c) = (0, 0);
    while k < MODULES.len() { if MODULES[k].ported { c += 1; } k += 1; }
    c
}
/// 모듈 이름 → `MODULES`의 자리.
pub fn module_index(name: &str) -> Option<usize> { MODULES.iter().position(|m| m.name == name) }

/// 입력 DLC 하나 — `.htpack`(형식 1~4) 또는 JSON 바이트. 목록의 첫째가 기본 DLC, 나머지는 켠 차례.
#[derive(Clone, Debug)]
pub struct PackIn { pub name: String, pub bytes: Vec<u8> }

/// 배치 선택.
/// - `now_ms` · `tz_min`: '오늘'과 시간대(분 — 서울은 540). 진행 중 정권의 끝 · 문서의 나이 · `[date]`가 지역 연 · 월 · 일에 달리므로 입력이다.
/// - `upto`: 모듈 앞자리만(그 모듈까지) 돌린다. `None`은 스물 모두.
/// - `scope`: 어느 트랙을 다시 셈하나.
/// - `calendar`: 달력 표 바이트(`Store`에 들지 않고 `calendar_of`가 돌려주기만 한다 — `Rc`는 `Send`가 아님).
#[derive(Clone, Debug)]
pub struct Opts { pub now_ms: f64, pub tz_min: i32, pub upto: Option<String>, pub scope: Scope, pub calendar: Option<Rc<Vec<u8>>> }

/// 다시 셈할 범위: 전체 또는 트랙 열쇠 묶음(`patch::track_key`와 같은 열쇠 — 닿는 트랙 [`touched`]의 답). `Tracks(S)`의 내보내기는
/// `patch::sub_plan(export(All), S)`(배치에 없는 판 트랙 열쇠는 걸러 냄 — S 밖 트랙의 몫도 하위 배치의 값에 들어 셈은 통째와 같다: 과제 16b · `export` 머리글).
#[derive(Clone, Debug)]
pub enum Scope { All, Tracks(BTreeSet<String>) }

/// 이음매 ①(과제 5): 팩 하나(`.htpack` 형식 1 ~ 4 · JSON)를 정규화한 팩 — Node의 `JSON.stringify(HT.normalizePack(raw).pack)`과 같은 값.
/// 읽지 못하거나(팩 · JSON 오류) 치명적 오류(`kind: 'info'`)로 팩이 null이면 그 알림을 담은 오류. 보조 달력의 날짜가 필요했는데 표가 없거나 표 범위 밖이면 거절한다(계획 정한 것 #7).
pub fn normalized(pack: &PackIn, opts: &Opts) -> crate::Result<serde_json::Value> {
    let ctx = read::Ctx::new(opts)?;
    let mut notes = Vec::new();
    let raw = self::pack::raw_of(&ctx, pack, &mut notes)?;
    let norm = read::normalize_pack(&ctx, raw);
    // 거절 글에 그 달력의 이름(예: '음력 표 없음 — …') — 표 묶음은 있는데 그 달력만 없을 때도 같은 글. '<이름> 표 범위 밖' · '<이름> 표 없음' 꼴은
    // `packs::layout_refusal`이 읽어 `range` · `calendar`로 가른다(바꿀 때 함께).
    if let Some(name) = ctx.cal.missed_of() { return Err(format!("{}: {name} 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다", pack.name).into()); }
    if let Some(name) = ctx.cal.absent_of() { return Err(format!("{}: {name} 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다", pack.name).into()); }
    match norm.pack {
        Some(p) => Ok(js::to_json(&p)),
        None => Err(format!("{}: DLC를 읽을 수 없습니다 — {}", pack.name, norm.errors.iter().map(|e| e.msg.as_str()).collect::<Vec<_>>().join(" · ")).into()),
    }
}

/// 이음매 ② 앞(과제 6): 팩들(첫째가 기본 DLC, 나머지는 켠 차례)을 정규화해 모델을 짓고 연표 상태를 준비한 덤프 — Node의
/// `seam({ tracks, depth, cats, proxies, cityUses, scopes, model })`(줄 배정을 빈 함수로 둔 `contextOf` — `prep.json`)과 같은 값.
pub fn prepared(packs: &[PackIn], opts: &Opts) -> crate::Result<serde_json::Value> { ctx::prepared(packs, opts) }

/// 이음매 ② 뒤(과제 7): [`prepared`]에 이어 트랙마다 줄 배정(`_layoutTrack` — `lay::track`)을 마친 덤프 — Node의 `contextOf` 그대로(`rows.json`)와 같은 값.
/// JS라면 던졌을 곳(`model::util::fault` — 예: 판 트랙의 줄 목록이 배열이 아님)에 닿거나 보조 달력 표가 모자라면 오류(판 갈래는 과제 15가 옮겨 이제 거절하지 않는다).
pub fn laid(packs: &[PackIn], opts: &Opts) -> crate::Result<serde_json::Value> { ctx::laid(packs, opts) }

/// 저장소 안 달력 표의 열쇠(`blobs` 표 — 과제 17 · 계획 정한 것 #7 · 판정 R36): `archive-tool build`가 `calendar-cache.json` 꼴의 **전체 표**를 zlib으로 싸 모든 저장소에 넣는다.
pub const CALENDAR_BLOB: &str = "calendar:table";

/// 과제 17: 저장소에 지어 넣은 달력 표(`blobs`의 [`CALENDAR_BLOB`] — zlib을 푼 `calendar-cache.json` 꼴의 글 바이트) — P4 과제 9가 `Opts.calendar`로 넘긴다.
/// 표가 없으면(그림 표가 없는 옛 저장소 · Node 길로 지은 저장소) None. 판정 R36: 넣고 빼기(P4 과제 9의 실제 틈)는 **모든 DLC에** 이 표를 요구한다 — 보조 달력
/// 날짜가 없는 DLC도(어느 DLC가 그런 날짜를 쓸지 미리 모른다) — 표 없는 저장소는 거기서 쉬운 글로 거절된다. 풀지 못하면 오류.
/// 쓰기 거래 안에서도 부를 수 있게 연결을 받는다(`Transaction`은 연결로 빌린다).
pub fn calendar_of(db: &rusqlite::Connection) -> crate::Result<Option<Rc<Vec<u8>>>> {
    use rusqlite::OptionalExtension;
    use std::io::Read;
    if !db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='blobs'")?.exists([])? { return Ok(None); }
    let packed: Option<Vec<u8>> = db.query_row("SELECT bytes FROM blobs WHERE key=?1", [CALENDAR_BLOB], |r| r.get(0)).optional()?;
    let Some(packed) = packed else { return Ok(None) };
    let mut plain = Vec::new();
    flate2::read::ZlibDecoder::new(packed.as_slice()).read_to_end(&mut plain).map_err(|e| format!("저장소의 달력 표를 풀지 못했습니다: {e}"))?;
    Ok(Some(Rc::new(plain)))
}

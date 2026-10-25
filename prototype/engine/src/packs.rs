//! DLC 넣고 빼기를 엔진 하나로(한 벌 P4 과제 9 — `{"op":"add_pack"}` · `{"op":"remove_pack"}` · `archive-tool add-pack` · `remove-pack`).
//!
//! 흐름(설계 3-4 '넣기 · 빼기의 흐름' · 계획 과제 9): 저장소 안 원본(`packs.original`) + 새 파일을 읽는다 → 같은 id는 판을 견주어 높거나 같은 판만 받는다
//! (낮은 판이면 거절 — 판정 R15: 판 대조는 여기서) → 새 조합(저장소의 DLC 차례 `meta.pack_order` 그대로 · 새 DLC는 뒤에)의 **닿는 트랙 S**를 틈
//! ([`Layouter::touched`])에 묻는다 → 그 조합을 저장소의 '오늘'(`meta.now` — 계획 정한 것 #9: 안 건드린 트랙과 같은 날)과 저장소의 달력 표로 배치한다
//! ([`Layouter::export`] — S면 하위 배치) → `patch::apply`(S면 `Covers::Part` — 조합 전부를 말하되 트랙은 S만). apply가 S 밖 트랙도 다시 써야 한다고 하면
//! ([`patch::Widen`] — 가리키던 uid가 생기거나 사라짐 · 가리는 변형 · 지문 없음) S를 넓혀 다시 배치한다. 모두 부르는 쪽의 **한 쓰기 거래** 안이라 어디서
//! 실패해도 저장소는 그대로다.
//!
//! - 빼기(`remove_pack`)는 그 DLC를 뺀 조합으로 같은 흐름이다. 원본은 `delete`일 때만 버리고, 아니면 저장소 안 **보관함**(`kept_packs` 표 — 이 과제가
//!   처음 만든다)에 남긴다(설계 3-4 '뺀 DLC를 다시 넣는 것은 저장소에 원본이 남아 있으므로 같은 흐름이다'). 보관함의 DLC는 `add_pack`의 `ids`로 다시 넣는다.
//! - 다른 저장소의 원본으로 넣기(판정 R34 D — 휴대폰 시드 잇기: 새 시드에 옛 저장소의 사용자 DLC를 다시 넣는다): `from_store` + `ids`. 이 저장소에
//!   이미 같거나 높은 판(원본까지 있는 것)이 든 id는 건너뛴다(`skipped` — 전부 아니면 전무가 아니게).
//! - 원본이 없는 DLC(메이커 `.htlayout`으로만 든 것): 다시 셈할 재료가 없으므로 새 조합에 남는 한 거절한다(`code` original). 그 DLC를 받은 파일 ·
//!   다른 저장소가 주면(판 대조 뒤) 그 원본으로 채워 넣고, 그 DLC를 빼는 것은 제 원본을 요구하지 않는다(고침 1회차 — 막다른 길을 없앰).
//! - 달력 표: 실제 틈(Rust 배치)은 저장소의 달력 표(`lay::calendar_of` — 과제 17이 모든 저장소에 넣는 전체 표)로 보조 달력 날짜를 읽는다. 어느 DLC가 그런
//!   날짜를 쓸지 미리 모르므로 표가 없는 저장소(옛 저장소 · Node 길로 지은 것)는 모든 넣고 빼기를 쉬운 글로 거절한다(`code` calendar — 판정 R36).
//! - 모든 트랙을 다시 셈하는 때(S = 전부 — 옳지만 느림): 저장소에 DLC 차례(`meta.pack_order`) · '오늘'(`meta.now`) · 트랙 지문 표가 없거나 옛 열이 빠졌거나
//!   원본 없던 DLC가 있었을 때(이 과제 전 · 이 계획 전에 지은 저장소 · 메이커 `.htlayout`으로 고친 저장소 — 옛 DLC의 약속 2) · 지문을 셈한 규칙 판
//!   (`meta.rules`)이 지금 엔진의 것과 다를 때(엔진을 올린 뒤의 첫 넣기 — 판정 R59 I-1), 그리고 틈이 닿는 트랙을 모르거나 모든 트랙이라 답할 때
//!   (실제 틈은 P3 과제 16의 `lay::touch` — 분류 차례 · 간지 · 트랙 차례가 바뀌거나 기본 DLC를 바꿀 때).
//! - 배치하는 쪽은 틈 [`Layouter`]로 받는다(판정 R35): 실제는 [`RustLayouter`](Rust `lay::export`), 검사는 Node 통째 배치(`tests/common/node.rs`)와 실제 틈 둘 다.
use crate::lay::{self, Opts, PackIn, Scope};
use crate::legacy::{iso_at, iso_time, now_ms, version_text, DEFAULT_TZ_MIN};
use crate::patch::{self, ApplyIn, ApplyReport, Covers, Widen};
use crate::Result;
use rusqlite::{params, Connection, OpenFlags, OptionalExtension, Transaction};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

/// 배치를 내는 쪽(틈 — 판정 R35). 팩 목록은 첫째가 기본 DLC, 나머지는 켠 차례(`lay::PackIn` — .htpack 형식 1 ~ 4 · JSON 바이트).
pub trait Layouter {
    /// 그 조합의 배치 JSON 3판(계약 4절). `opts.scope`가 `Scope::Tracks(S)`면 S의 하위 배치(`patch::sub_plan(통째, S)` 꼴 — P3 과제 16의 약속).
    /// '오늘'과 시간대는 `opts.now_ms` · `tz_min`(저장소의 `meta.now`) · 달력 표는 `opts.calendar`(저장소의 표 — `lay::calendar_of`).
    fn export(&self, packs: &[PackIn], opts: &Opts) -> Result<Value>;
    /// 조합이 `before`에서 `after`로 바뀔 때 **지문이 바뀔 수 있는 트랙**(새 조합의 트랙 열쇠 — `patch::track_key`). 모르면 `Scope::All`.
    /// 약속: 지문이 바뀌는 트랙은 모두 담는다(더 담는 것은 괜찮다 — 그 트랙은 지문이 같으면 다시 쓰지 않는다). 가리키던 uid가 생기거나 사라져
    /// 다시 써야 하는 트랙은 몰라도 된다(apply가 넓히기로 알려 준다).
    fn touched(&self, before: &[PackIn], after: &[PackIn], opts: &Opts) -> Result<Scope>;
    /// 배치에 저장소의 달력 표가 꼭 있어야 하는가 — 실제 틈(Rust — ICU가 없다)은 참. 검사의 Node 틈은 Node의 ICU로 읽어 거짓.
    fn needs_calendar(&self) -> bool {
        true
    }
}

/// 실제 틈 — Rust 배치(`lay::export`). 옮기지 않은 모듈이 있으면 그 이름을 담아 거절한다.
pub struct RustLayouter;

impl Layouter for RustLayouter {
    fn export(&self, packs: &[PackIn], opts: &Opts) -> Result<Value> {
        // P3 과제 16: `Scope::Tracks(S)`면 S의 하위 배치(= `sub_plan(export(All), S)` — `tests/lay_scope.rs`). S에 배치에 없는 **판** 열쇠(판 셈에서 빠진 판 —
        // 닿는 트랙은 판의 있고 없음을 배치 없이 짐작한다)는 `lay::export`가 걸러 낸다. 그 밖의 없는 열쇠(짐작이 빗나감 — 넓이 검사가 지키는 '짐작 = 실제 +
        // 빠진 판만'이 깨진 때)는 `lay::export::MissingTracks`로 나오고 relayout이 모든 트랙으로 넓힌다(판정 R69-4 · 답의 `widened`). apply의 트랙은
        // relayout이 S ∩ `allTracks`로 잡는다.
        lay::export(packs, opts)
    }

    fn touched(&self, before: &[PackIn], after: &[PackIn], opts: &Opts) -> Result<Scope> {
        // P3 과제 16: 앞 · 뒤 조합의 모델을 견준 닿는 트랙(`lay::touch::touched_scope` — 모두면 `Scope::All`). 넣기 · 빼기 · 판 바꿈 · 여럿을 함께 바꿈 모두 한 번에.
        // 견주려고 준비한 '뒤' 조합의 문맥은 곧이은 `export`가 다시 쓴다(16b — 같은 입력일 때만).
        lay::touch::touched_scope(before, after, opts)
    }
}

/// `{"op":"add_pack"}`의 재료: 넣을 파일(.htpack 형식 1 ~ 4 · .json) · 다른 저장소(`from_store`)나 이 저장소의 보관함에서 꺼낼 DLC id(`ids`).
#[derive(Debug, Clone, Default)]
pub struct AddOrder {
    pub files: Vec<PathBuf>,
    pub from_store: Option<PathBuf>,
    pub ids: Vec<String>,
    /// 받은 것이 이긴다(판정 R39 — 메이커 미리보기 '연표로 ↗'의 작업본 · `add-dlc.mjs --prefer-given`과 같은 뜻): 판 대조(낮은 판 거절 · `from_store`의 건너뛰기)를
    /// 하지 않고 받은 것이 같은 id를 바꾼다(`replaced`). **미리보기용 — 서재의 임시 사본에만 쓴다**(진짜 저장소를 낮은 판으로 되돌리지 않게).
    pub prefer_given: bool,
}

/// `{"op":"remove_pack"}`의 재료: 뺄 DLC id · 원본까지 버릴지(`delete` — 아니면 보관함에 남긴다).
#[derive(Debug, Clone)]
pub struct RemoveOrder {
    pub id: String,
    pub delete: bool,
}

/// 저장소에 든 DLC를 받은 원본으로 바꿔 넣은 것(바이트가 다를 때만 — 높은 판 · 같은 판의 다른 바이트(메이커가 판을 올리지 않고 고친 작업본) ·
/// 원본 없던 DLC를 채움(`old_sha256` 없음)).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Replaced {
    pub id: String,
    pub old_version: String,
    pub new_version: String,
    pub old_sha256: Option<String>,
    pub new_sha256: String,
}

/// 넣고 빼기의 답 — `patch::apply`의 답(계약 2-7)에 배치 몫을 더한 것.
#[derive(Debug, Clone)]
pub struct PackReport {
    pub apply: ApplyReport,
    /// 배치(틈)에 쓴 ms의 합 · 배치를 몇 번 했나(넓히기마다 한 번 더 · 할 일이 없었으면 0).
    pub ms_layout: f64,
    pub layouts: usize,
    /// 마지막 배치의 범위 — `None`이면 모든 트랙, 아니면 고쳐 쓰려 실은 트랙 수(S ∩ 조합의 트랙 · 할 일이 없으면 0).
    pub scope: Option<usize>,
    /// 읽기(원본 · 파일 · 다른 저장소) · 판 대조에 쓴 ms.
    pub ms_read: f64,
    /// apply(마지막 한 번 — 넓히기로 거절된 앞 차례는 뺀다)에 쓴 ms.
    pub ms_apply: f64,
    /// 새 조합의 DLC 차례(첫째가 기본).
    pub packs: Vec<String>,
    /// 보관함에 남긴 · 보관함에서 꺼낸 · 버린 DLC id. 원본 없던 DLC를 빼면 남길 것이 없어 `deleted`에 든다.
    pub kept: Vec<String>,
    pub unkept: Vec<String>,
    pub deleted: Vec<String>,
    /// 바꿔 넣은 DLC([`Replaced`]).
    pub replaced: Vec<Replaced>,
    /// `from_store`에서 건너뛴 id — 이 저장소에 이미 같거나 높은 판이 원본까지 든 것.
    pub skipped: Vec<String>,
    /// 닿는 트랙으로 좁히려다 모든 트랙으로 넓혔으면 그 까닭(판정 R71-3 — 저장소는 같고 셈만 늘었다). 처음부터 모든 트랙이면(규칙 판 · 원본 없던 DLC …) None.
    pub widened: Option<Widened>,
    /// 받은 DLC를 읽으며 남긴 알림(거절이 아님 — 답의 `notes`): 형식 4 파일을 옛 꼴로 내린 알림(`lay::pack::raw_of`의 "형식 4 파일을 지금 형식으로 바꿔 읽었습니다" ·
    /// `lay::f4`의 글 — 사람 객체 → 인물 · 빌린 직위 줄 → 칸 복제 · 문화권별 주기 → 간지 하나 · as · 고리). 줄마다 `«DLC 이름»: ` 머리. 앱은 형식 4 알림이 있으면
    /// "이 앱 판은 사람 띠 · 빌린 직위 줄 · 문화권 줄을 아직 그리지 않습니다"를 알린다(리메이크 5단계 과제 10). 옛 저장소(달력 표 다섯)에 없는 달력으로 날짜를
    /// 적은 DLC의 건너뜀 알림(`calendar_notes` — "… 달력 표에 히브리력이 없어 …" · 감독 결정 2026-10-25 — 앱은 그 줄을 그대로 알린다). 빼기 · 조합 그대로인 답은 빈 목록.
    pub notes: Vec<String>,
    pub ms: f64,
}

/// 모든 트랙으로 넓힌 까닭(판정 R69-4 · R71-2 · R71-3) — `why`: `missing`(짐작한 열쇠가 배치에 없음 — `keys`는 그 수 · `detail`은 열쇠들) ·
/// `needs_whole`(하위 배치를 고쳐 쓰는 도중 S 밖 트랙도 함께 다시 써야 함이 드러남 — `patch::NeedsWhole`) · `touched_failed`(닿는 트랙 셈이 넘어짐 — 오류 · 패닉).
/// `detail`은 원래 글(앱의 자세히 보기 · 기록용).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Widened {
    pub why: &'static str,
    pub keys: usize,
    pub detail: String,
}

impl PackReport {
    /// 명령의 답(계약 2-7의 apply 답 + 2-7-1의 칸).
    pub fn to_json(&self) -> Value {
        let mut v = self.apply.to_json();
        v["ms"] = json!(self.ms);
        v["ms_layout"] = json!(self.ms_layout);
        v["layouts"] = json!(self.layouts);
        v["scope"] = match self.scope { None => json!("all"), Some(n) => json!(n) };
        v["ms_read"] = json!(self.ms_read);
        v["ms_apply"] = json!(self.ms_apply);
        v["packs"] = json!(self.packs);
        v["kept"] = json!(self.kept);
        v["unkept"] = json!(self.unkept);
        v["deleted"] = json!(self.deleted);
        v["replaced"] = json!(self.replaced.iter().map(|r| json!({"id":r.id,"old_version":r.old_version,"new_version":r.new_version,
            "old_sha256":r.old_sha256,"new_sha256":r.new_sha256})).collect::<Vec<_>>());
        v["skipped"] = json!(self.skipped);
        v["notes"] = json!(self.notes);
        v["widened"] = match &self.widened {
            None => Value::Null,
            Some(w) => json!({"why": w.why, "keys": w.keys, "detail": w.detail}),
        };
        v
    }
}

/// 보관함 표 — 빼되 원본은 남긴 DLC(`remove_pack`의 `delete: false`). 넣을 때 그 id는 보관함에서 꺼낸다.
const KEPT_TABLE: &str = "CREATE TABLE IF NOT EXISTS kept_packs(key TEXT PRIMARY KEY,name TEXT NOT NULL,version TEXT NOT NULL,original BLOB NOT NULL,sha256 TEXT NOT NULL)";

/// DLC 하나 — 글자 id · 이름 · 판 · 원본(.htpack 바이트 — 저장소에 원본 없이 든 DLC면 None).
#[derive(Debug, Clone)]
struct Pack {
    key: String,
    name: String,
    version: String,
    /// 원본 바이트는 한 벌만 두고 빌려 쓴다(`Rc` — 휴대폰 메모리 · 고침 2회차 M-2). 배치에 줄 때(`PackIn`)만 복사한다.
    original: Option<Rc<[u8]>>,
    /// 원본이 형식 4 파일인가(`formatVersion` 4 — 배치가 옛 꼴로 내려 읽는다 · `lay::pack::raw_of`). 받은 파일 · 꺼낸 원본([`pack_of`])만 안다 — 저장소에 든 것은 거짓.
    format4: bool,
}

impl Pack {
    /// 배치에 줄 입력 — 원본이 있는 DLC만 부른다([`missing_originals`]를 먼저 본다).
    fn input(&self) -> PackIn {
        debug_assert!(self.original.is_some(), "원본 없는 DLC «{}»를 배치에 주려 함 — missing_originals를 먼저", self.key);
        PackIn { name: format!("{}.htpack", self.key), bytes: self.original.as_deref().map(<[u8]>::to_vec).unwrap_or_default() }
    }
}

fn sha256(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    format!("{:x}", Sha256::digest(bytes))
}

/// 원본(.htpack) 바이트에서 id · 이름 · 판을 읽는다 — 읽지 못하면 그 까닭(`what` = 어디서 온 것).
fn pack_of(bytes: Vec<u8>, what: &str) -> Result<Pack> {
    // 원본이 깨져 읽을 수 없음은 다시 해도 같다 — `code` broken(판정 R68 ① — 옛 저장소의 원본 · 보관함 · 받은 파일 모두).
    // 형식 실패(봉인 · 지문 · 머리 · JSON · DLC 본문 아님 · id 없음)는 모두 broken(판정 R70-1).
    let raw = crate::htpack_raw(&bytes).map_err(|e| refuse("broken", format!("DLC를 읽을 수 없습니다({what}): {e}")))?;
    if raw["format"] != "history-timeline-dlc" {
        return Err(refuse("broken", format!("DLC 본문이 아닙니다({what})")));
    }
    let key = raw["id"].as_str().filter(|s| !s.is_empty()).ok_or_else(|| refuse("broken", format!("DLC에 id가 없습니다({what})")))?.to_owned();
    let name = raw["name"].as_str().filter(|s| !s.is_empty()).unwrap_or(&key).to_owned();
    Ok(Pack { name, version: version_text(&raw["version"]), key, original: Some(Rc::from(bytes)), format4: raw["formatVersion"] == 4 })
}

/// 받은 DLC 가운데 형식 4 파일([`Pack::format4`])을 옛 꼴로 내릴 때의 알림(리메이크 5단계 과제 10) — `«DLC 이름»: <알림>`. 배치(`lay::ctx::prepare`)도 같은 길로
/// 내리지만 그 알림을 버리므로 형식 4 파일만 여기서 한 번 더 읽는다(달력 표 없이 — 내림은 표를 쓰지 않는다). 내리지 못하면 여기서는 말하지 않는다(배치가 같은 길로
/// 읽어 거절한다 — `layout_refusal`).
fn format4_notes(incoming: &[Pack], h: &Held) -> Vec<String> {
    let mut out = Vec::new();
    if !incoming.iter().any(|p| p.format4 && p.original.is_some()) {
        return out;
    }
    let opts = Opts { now_ms: h.now_ms, tz_min: h.tz_min, upto: None, scope: Scope::All, calendar: None };
    let Ok(ctx) = lay::read::Ctx::new(&opts) else { return out };
    for p in incoming.iter().filter(|p| p.format4 && p.original.is_some()) {
        let mut notes = Vec::new();
        if let Ok(raw) = lay::pack::raw_of(&ctx, &p.input(), &mut notes) {
            lay::js::release(&raw);
            out.extend(notes.into_iter().map(|m| format!("«{}»: {m}", p.name)));
        }
    }
    out
}

/// 받은 DLC가 저장소의 달력 표에 없는 달력으로 날짜를 적었을 때의 알림(감독 결정 2026-10-25 — 거절하지 않고 건너뜀): 옛 저장소(달력 표 다섯 — 리메이크 6단계
/// 전에 지음)의 표에는 나중에 더한 달력(`lay::cal::LATER` — 히브리력 · 에티오피아력 · 콥트력 · 사카력)이 없다. 배치는 그 달력을 건너뛰어(`lay::cal::Tables::skips`)
/// 그 날짜를 쓴 항목 · 칸은 읽지 못한 날짜로 빠지고 날짜 칸에도 그 달력의 줄(`cal:` 기록)이 없다 — 받은 DLC마다 그런 날짜를 썼으면 한 줄(`«DLC 이름»: …`).
/// 표에 그 넷이 다 있으면(새 저장소) 읽지 않는다. 배치(`lay::ctx::prepare`)도 같은 길로 읽지만 그 표지를 버리므로 받은 DLC만 여기서 한 번 더 정규화한다
/// (모델이 다시 읽는 날짜 글도 정규화가 먼저 읽는다 — 정규화가 거른 날짜는 모델에 닿지 않음). 저장소의 표는 건드리지 않는다.
fn calendar_notes(incoming: &[Pack], h: &Held, cal: &Calendar) -> Vec<String> {
    let mut out = Vec::new();
    let Some(table) = cal.table() else { return out };
    let opts = Opts { now_ms: h.now_ms, tz_min: h.tz_min, upto: None, scope: Scope::All, calendar: Some(table) };
    let Ok(ctx) = lay::read::Ctx::new(&opts) else { return out };
    if !lay::cal::LATER.iter().any(|id| ctx.cal.skips(id)) {
        return out;
    }
    for p in incoming.iter().filter(|p| p.original.is_some()) {
        let mut notes = Vec::new();
        let Ok(raw) = lay::pack::raw_of(&ctx, &p.input(), &mut notes) else { continue };
        let norm = lay::read::normalize_pack(&ctx, raw.clone());
        lay::js::release(&raw);
        if let Some(pack) = &norm.pack {
            lay::js::release(pack);
        }
        let names = ctx.cal.take_skipped();
        if !names.is_empty() {
            let list = names.join(" · ");
            out.push(format!("«{}»: 이 저장소의 달력 표에 {list}{} 없어 그 달력으로 적은 날짜를 읽지 못했습니다 — 그 날짜를 쓴 항목은 빼고 넣었고 날짜 칸에도 \
                그 달력 줄이 없습니다(새 판 자료로 옮기면 함께 보입니다)", p.name, josa(&list, "이", "가")));
        }
    }
    out
}

/// 판 글을 마디마다 수로(`"1.0.3"` → [1, 0, 3] — `add-dlc.mjs`의 `versionOf`와 같은 규칙: 수가 아닌 마디는 0).
fn version_parts(text: &str) -> Vec<i64> {
    text.split('.').map(|p| {
        let digits: String = p.trim().chars().take_while(char::is_ascii_digit).collect();
        digits.parse().unwrap_or(0)
    }).collect()
}

/// 판 견주기(`add-dlc.mjs`의 `compareVersion`) — 빈 마디는 0.
fn compare_versions(a: &str, b: &str) -> std::cmp::Ordering {
    let (a, b) = (version_parts(a), version_parts(b));
    (0..a.len().max(b.len())).map(|i| a.get(i).copied().unwrap_or(0).cmp(&b.get(i).copied().unwrap_or(0)))
        .find(|o| o.is_ne()).unwrap_or(std::cmp::Ordering::Equal)
}

/// 거절(계약 2-7의 `code`) — `patch::Refusal`과 같은 꼴.
fn refuse(code: &'static str, message: String) -> Box<dyn std::error::Error + Send + Sync> {
    Box::new(patch::Refusal { code, message, detail: None })
}

/// [`refuse`]에 자세히 보기 글(`detail` — 개발자 말 그대로)을 더한 것.
fn refuse_detail(code: &'static str, message: String, detail: String) -> Box<dyn std::error::Error + Send + Sync> {
    Box::new(patch::Refusal { code, message, detail: Some(detail) })
}

fn meta_text(db: &Connection, key: &str) -> Result<Option<String>> {
    Ok(db.query_row("SELECT value FROM meta WHERE key=?1", [key], |r| r.get::<_, String>(0)).optional()?)
}

fn meta_json(db: &Connection, key: &str) -> Result<Value> {
    Ok(meta_text(db, key)?.and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_else(|| json!({})))
}

fn has_table(db: &Connection, name: &str) -> Result<bool> {
    Ok(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1")?.exists([name])?)
}

/// 저장소의 지금 조합.
struct Held {
    /// DLC 차례대로(첫째가 기본) — `meta.pack_order`, 없으면 자료집 번호 차례. 원본 없이 든 DLC도 든다(`original` None).
    packs: Vec<Pack>,
    /// 지은 날의 글 · 밀리초 · 시간대 — 없으면(옛 저장소) 지금 시각.
    now: String,
    now_ms: f64,
    tz_min: i32,
    /// 이 저장소가 어느 조합 · 차례 · 날 · 규칙 판의 통째 짓기와 같다고 믿을 수 없다 — 모든 트랙을 다시 셈한다(모듈 머리글).
    whole_only: Vec<&'static str>,
}

/// 넣고 빼기 한 번이 끝나면(성공 · 실패 · 배치 없는 길 모두) 이 스레드의 셈 그릇(푼 달력 표 · 닿는 트랙의 준비 문맥)을 비운다(판정 R69-5 — `lay::clear_caches`).
struct ClearCaches;
impl Drop for ClearCaches {
    fn drop(&mut self) {
        lay::clear_caches();
    }
}

/// 저장소(쓰기 거래 안)의 지금 조합을 읽는다. 원본이 없는 DLC는 `original` None으로 든다 — 거절은 새 조합을 안 뒤에([`missing_originals`]).
fn held(db: &Connection) -> Result<Held> {
    let keys = meta_json(db, "pack_keys")?;
    let info = meta_json(db, "pack_info")?;
    let mut by_number: Vec<(i64, String, String, Option<Rc<[u8]>>)> = Vec::new();
    {
        let mut stmt = db.prepare("SELECT id,name,original FROM packs ORDER BY id")?;
        for row in stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<Vec<u8>>>(2)?)))? {
            let (id, name, original) = row?;
            let key = keys[&id.to_string()].as_str().unwrap_or("").to_owned();
            if key.is_empty() {
                // 저장소 쪽 — calendar(판정 R70-3: 그런 저장소엔 달력 표도 없다 · 앱은 '새 시드로 옮겨야 함'으로 읽는다).
                return Err(refuse("calendar", format!("지금 저장소의 «{name}»에 DLC id가 없어 조합을 대조할 수 없습니다 — 아주 옛 저장소입니다. 새 판 시드로 옮긴 뒤 다시 해 주세요")));
            }
            by_number.push((id, key, name, original.map(Rc::from)));
        }
    }
    if by_number.is_empty() {
        return Err("지금 저장소에 DLC가 없습니다".into());
    }
    let mut whole_only = Vec::new();
    if by_number.iter().any(|p| p.3.is_none()) {
        // 원본 없던 DLC의 앞 조합은 배치할 수 없다 — 닿는 트랙을 견줄 수 없으니 모든 트랙을 다시 셈한다(그 DLC를 채우거나 빼는 길만 여기까지 온다).
        whole_only.push("원본 없던 DLC");
    }
    // 차례: `meta.pack_order`가 저장소의 DLC와 꼭 맞으면 그것, 아니면 번호 차례(그때는 모든 트랙을 다시 셈한다 — 그 차례의 통째 짓기라고 믿을 수 없다).
    let order: Option<Vec<String>> = meta_text(db, "pack_order")?.and_then(|t| serde_json::from_str(&t).ok());
    let mut list = by_number.clone();
    match order {
        Some(order) if order.len() == by_number.len() && order.first() == by_number.first().map(|p| &p.1)
            && order.iter().collect::<BTreeSet<_>>() == by_number.iter().map(|p| &p.1).collect::<BTreeSet<_>>() => {
            list.sort_by_key(|p| order.iter().position(|k| *k == p.1));
        }
        _ => whole_only.push("DLC 차례(meta.pack_order)"),
    }
    let packs = list.into_iter().map(|(id, key, name, original)| {
        let version = version_text(&info[&id.to_string()]["version"]);
        Pack { key, name, version, original, format4: false }
    }).collect();
    let (now, now_ms, tz_min) = match meta_text(db, "now")?.and_then(|t| iso_time(&t).map(|(ms, tz)| (t, ms, tz))) {
        Some(found) => found,
        None => {
            whole_only.push("지은 날(meta.now)");
            // 적는 글(초까지)과 같은 값으로 셈한다 — 다음 넣기가 이 글을 읽어 같은 날 · 같은 시각으로 셈하게.
            let ms = (now_ms() / 1000.0).floor() * 1000.0;
            (iso_at(ms, DEFAULT_TZ_MIN), ms, DEFAULT_TZ_MIN)
        }
    };
    if !has_table(db, "track_prints")? {
        whole_only.push("트랙 지문(track_prints)");
    }
    if !patch::older_missing(db)?.is_empty() {
        whole_only.push("옛 열");
    }
    // 규칙 판(판정 R59 I-1): 트랙 지문을 셈한 규칙 판(`meta.rules` — 짓기와 모두 덮는 apply가 적는다)이 지금 엔진의 것(`patch::rules_mark`)과 다르면
    // 하위 배치가 S 밖 트랙을 지문 대조 없이 믿을 수 없다(엔진을 올린 뒤 배치가 달라졌을 수 있다) — 모든 트랙을 한 번 다시 셈해 맞춘다(그 apply가 새로 적는다).
    if meta_text(db, "rules")?.as_deref() != Some(patch::rules_mark().as_str()) {
        whole_only.push("규칙 판(meta.rules)");
    }
    Ok(Held { packs, now, now_ms, tz_min, whole_only })
}

/// 달력 표 증표를 짓는 곳 — 하위 모듈에 가둬 [`need_calendar`]만 [`Calendar`]를 지을 수 있다(판정 R59 'Opts는 need_calendar 뒤에' · 16b 검토 ① M-5 · ② M6).
mod gate {
    use super::{calendar_failure, lay, refuse, Connection, Layouter, Rc, Result, CALENDAR_BROKEN};

    /// 저장소의 달력 표를 읽은 증표 — 이 모듈 밖에서는 짓지 못한다. 배치 선택(`Opts`)은 이것으로만 짓는다([`super::relayout`]의 인자).
    pub(super) struct Calendar(Option<Rc<Vec<u8>>>);
    impl Calendar {
        /// 읽은 표(검사의 Node 틈이면 없을 수 있다).
        pub(super) fn table(&self) -> Option<Rc<Vec<u8>>> { self.0.clone() }
    }

    /// 실제 틈은 저장소의 달력 표가 있어야 배치한다(판정 R36) — 없으면 쉬운 글로 거절(`code` calendar).
    /// 깨진 표도 쉬운 글로 거절한다(zlib이 풀리지 않음 · 풀린 글이 달력 표가 아님 — `code` calendar). 검사의 Node 틈(표를 쓰지 않음)은 읽을 수 있는 만큼만.
    /// 표는 여기서 한 번 풀어 이 스레드에 나눠 둔다(`lay::cal::Tables::shared` — 같은 바이트로 짓는 닿는 트랙 · 배치의 문맥이 다시 풀지 않음 · 16b 검토 ② M8 —
    /// 예전엔 깨졌나 보려고 JSON으로 한 번, 배치가 또 한 번 풀었다). 넣기 끝에 비운다(`lay::clear_caches`).
    pub(super) fn need_calendar(db: &Connection, layouter: &dyn Layouter) -> Result<Calendar> {
        if !layouter.needs_calendar() {
            return Ok(Calendar(lay::calendar_of(db).ok().flatten()));
        }
        let table = lay::calendar_of(db).map_err(calendar_failure)?
            .ok_or_else(|| refuse("calendar", "달력 표가 없는 옛 저장소입니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요(이 저장소에서는 DLC를 넣거나 뺄 수 없습니다)".into()))?;
        // JSON인지만이 아니라 표의 꼴까지(`shared`는 `from_cache`와 같은 풀이 — 배치가 읽는 그대로) — 꼴이 틀린 표가 배치에서 넘어져 DLC 탓(layout)으로
        // 나가지 않게(판정 R70-3).
        lay::cal::Tables::shared(&table).map_err(|_| refuse("calendar", CALENDAR_BROKEN.into()))?;
        Ok(Calendar(Some(table)))
    }
}
use gate::{need_calendar, Calendar};

const CALENDAR_BROKEN: &str = "저장소의 달력 표가 깨졌습니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요(이 저장소에서는 DLC를 넣거나 뺄 수 없습니다)";

/// `lay::calendar_of`의 실패 가르기(판정 R68 ②): 저장소를 읽다 난 입출력 실패(SQLite의 디스크 · 잠금 · 메모리 · 가득 참 · 열기 갈래)는 환경 탓이라
/// `code` 없이(다음에 다시 하면 될 수 있다 — 앱이 '새 시드로 옮겨야 함'으로 읽지 않게), 그 밖(zlib이 풀리지 않음 · 줄 꼴이 틀림 · 파일이 깨짐)은 깨진 표 — `code` calendar.
fn calendar_failure(e: Box<dyn std::error::Error + Send + Sync>) -> Box<dyn std::error::Error + Send + Sync> {
    use rusqlite::ErrorCode::*;
    let passing = e.downcast_ref::<rusqlite::Error>().and_then(rusqlite::Error::sqlite_error_code)
        .is_some_and(|c| matches!(c, SystemIoFailure | DatabaseBusy | DatabaseLocked | OutOfMemory | DiskFull | CannotOpen));
    if passing {
        return format!("저장소의 달력 표를 읽지 못했습니다 — 잠시 뒤 다시 해 주세요(저장소는 그대로): {e}").into();
    }
    refuse("calendar", CALENDAR_BROKEN.into())
}

/// 새 조합에 원본이 없는 DLC가 남으면 거절(`code` original) — 엔진만으로는 그 DLC를 다시 셈할 재료가 없다.
fn missing_originals(after: &[Pack]) -> Result<()> {
    let missing: Vec<String> = after.iter().filter(|p| p.original.is_none()).map(|p| format!("«{}»({})", p.name, p.key)).collect();
    if !missing.is_empty() {
        return Err(refuse("original", format!("원본이 저장소에 없는 DLC가 있어 엔진만으로는 다시 셈할 수 없습니다: {} — 그 DLC들의 파일을 한 번에 함께 넣어 주세요(넣기는 파일 여럿을 함께 받습니다 · \
            원본 없는 DLC가 빼려는 그것 하나뿐이면 빼기도 됩니다)", missing.join(" · "))));
    }
    Ok(())
}

/// 파일 하나(.htpack — 머리 · 지문 확인 · .json — 본문 그대로 싼다)를 DLC로.
fn file_pack(path: &Path) -> Result<Pack> {
    // 읽기(입출력) 실패는 code 없이(환경 탓 — 다음에 다시), 읽은 바이트의 형식 실패는 broken(판정 R70-1 — 다시 해도 같다).
    // `legacy::build_pack`과 같은 규칙(.htpack은 그대로 · .json은 DLC 본문이면 봉인)이지만 실패를 가르려고 한 번만 읽어 여기서 가른다.
    let what = path.display().to_string();
    let bytes = std::fs::read(path).map_err(|e| format!("DLC 파일을 읽지 못했습니다({what}): {e}"))?;
    let is_pack = path.extension().and_then(|s| s.to_str()).is_some_and(|s| s.eq_ignore_ascii_case("htpack"));
    let original = if is_pack {
        bytes
    } else {
        let raw: Value = serde_json::from_slice(&bytes).map_err(|e| refuse("broken", format!("DLC를 읽을 수 없습니다({what}): {e}")))?;
        if raw["format"] != "history-timeline-dlc" {
            return Err(refuse("broken", format!("DLC 본문이 아닙니다({what})")));
        }
        crate::legacy::seal_dlc(&bytes)
    };
    pack_of(original, &what)
}

/// 다른 저장소(읽기 전용) 또는 이 저장소의 보관함에서 그 id들의 원본을 꺼낸다(판정 R34 D). 다른 저장소는 든 DLC(`packs`)를 먼저, 없으면 그 저장소의 보관함.
fn stored_packs(db: Option<&Connection>, here: &Connection, ids: &[String]) -> Result<Vec<Pack>> {
    let mut out = Vec::new();
    let src = db.unwrap_or(here);
    let what = if db.is_some() { "다른 저장소" } else { "이 저장소의 보관함" };
    for id in ids {
        let mut found: Option<Vec<u8>> = None;
        if db.is_some() {
            let keys = meta_json(src, "pack_keys")?;
            if let Some(number) = keys.as_object().and_then(|m| m.iter().find(|(_, v)| v.as_str() == Some(id.as_str()))).map(|(n, _)| n.clone()) {
                let number: i64 = number.parse().map_err(|_| format!("{what}의 자료집 번호가 올바르지 않습니다: {number}"))?;
                found = src.query_row("SELECT original FROM packs WHERE id=?1", [number], |r| r.get::<_, Option<Vec<u8>>>(0)).optional()?.flatten();
                if found.is_none() {
                    return Err(refuse("original", format!("{what}의 «{id}»에는 원본이 없습니다(메이커 배치로만 든 DLC) — 그 DLC 파일을 다시 골라 주세요")));
                }
            }
        }
        if found.is_none() && has_table(src, "kept_packs")? {
            found = src.query_row("SELECT original FROM kept_packs WHERE key=?1", [id], |r| r.get(0)).optional()?;
        }
        let bytes = found.ok_or_else(|| format!("{what}에 «{id}»가 없습니다"))?;
        let pack = pack_of(bytes, &format!("{what}의 {id}"))?;
        if pack.key != *id {
            return Err(refuse("broken", format!("{what}의 «{id}» 원본의 id가 «{}»입니다", pack.key)));
        }
        out.push(pack);
    }
    Ok(out)
}

/// 새 조합으로 배치해 고쳐 쓴다(넓히기 포함) — `add_pack` · `remove_pack`의 몸. `after`는 새 조합의 DLC 차례(첫째가 기본 · 모두 원본이 있다),
/// `fresh`는 저장소에 새로 들이거나 바꿔 넣을 원본(apply의 `originals`), `remove`는 뺄 DLC id. `cal`은 [`need_calendar`]가 읽은 달력 표.
#[allow(clippy::too_many_arguments)]
fn relayout(tx: &Transaction, h: &Held, cal: &Calendar, after: &[Pack], fresh: &[Pack], remove: &[String], layouter: &dyn Layouter, started: Instant, ms_read: f64)
    -> Result<PackReport> {
    let inputs: Vec<PackIn> = after.iter().map(Pack::input).collect();
    let mut opts = Opts { now_ms: h.now_ms, tz_min: h.tz_min, upto: None, scope: Scope::All, calendar: cal.table() };
    let mut widened: Option<Widened> = None;
    if h.whole_only.is_empty() {
        // 앞 조합은 모두 원본이 있다(원본 없던 DLC가 있으면 `whole_only`).
        let before: Vec<PackIn> = h.packs.iter().map(Pack::input).collect();
        // 닿는 트랙은 두 조합을 정규화 · 모델까지 짓는다 — 그 셈이 넘어지면(오류 · 패닉 — 예: 저장소의 앞 원본이 지금 엔진에서 넘어짐) 거절하지 않고 모든
        // 트랙으로(판정 R71-2 — 앞 조합 탓으로 넣기를 막지 않게). 진짜 거절은 뒤 조합 배치의 가름(`layout_refusal`) 하나에서만 — 받은 DLC의 날짜가 범위
        // 밖이면 거기서도 `range`(판정 R69-1의 뜻). 넘어진 글은 답의 `widened`에.
        match caught(|| layouter.touched(&before, &inputs, &opts)) {
            Ok(scope) => opts.scope = scope,
            Err(e) => widened = Some(Widened { why: "touched_failed", keys: 0, detail: e.to_string() }),
        }
    }
    let originals: Vec<(String, Vec<u8>)> = fresh.iter().filter_map(|p| p.original.as_deref().map(|o| (p.key.clone(), o.to_vec()))).collect();
    let (mut ms_layout, mut layouts) = (0.0, 0);
    let mut narrowed: Option<usize> = None;
    loop {
        let t0 = Instant::now();
        // 배치가 패닉해도 code 없는 '내부 오류'로 나가지 않게 잡아 같은 가름으로(고침 3회차 — 앱이 열 때마다 되풀이하지 않게).
        let got = caught(|| layouter.export(&inputs, &opts));
        ms_layout += t0.elapsed().as_secs_f64() * 1000.0;
        layouts += 1;
        // 닿는 트랙이 짐작한 열쇠가 이 배치에 없으면(판이 아닌 트랙 — 짐작이 빗나감) 거절하지 않고 모든 트랙으로 넓혀 다시 배치한다(판정 R69-4 — 저장소는 같고
        // 셈만 는다 · 답의 `scope`가 all).
        if let (Err(e), Scope::Tracks(_)) = (&got, &opts.scope) {
            if let Some(m) = e.downcast_ref::<lay::export::MissingTracks>() {
                widened = Some(Widened { why: "missing", keys: m.0.len(), detail: m.0.join(" · ") });
                opts.scope = Scope::All;
                continue;
            }
        }
        let mut plan = got.map_err(|e| layout_refusal(e, after, fresh))?;
        // 지은 날은 저장소의 것 그대로(계획 정한 것 #9 — 안 건드린 트랙과 같은 날). apply가 `meta.now`로 다시 적는다.
        plan["now"] = json!(h.now);
        let covers = match &opts.scope {
            Scope::All => Covers::All,
            Scope::Tracks(s) => {
                let order: Vec<String> = plan["allTracks"].as_array().ok_or("배치에 DLC 조합의 트랙 차례가 없습니다(배치를 낸 쪽의 잘못 — 저장소는 그대로)")?
                    .iter().map(|k| k.as_str().unwrap_or("").to_owned()).collect();
                // S ∩ allTracks — 닿는 트랙(`lay::touched`)에 이 조합의 배치에 없는 열쇠(판 셈 오류로 빠진 판 등)가 들 수 있다: 없는 트랙은 고쳐 쓸 것이
                // 없으니 거르고 '배치에 없는 트랙'으로 거절하지 않는다(그 판이 저장소에 있었다면 `allTracks`에 없으니 apply가 지운다).
                let tracks: BTreeSet<String> = s.iter().filter(|k| order.contains(k)).cloned().collect();
                narrowed = Some(tracks.len());
                Covers::Part { tracks, order }
            }
        };
        let t0 = Instant::now();
        // 하위 배치는 되돌림 자리(SAVEPOINT) 안에서 — 고쳐 쓰는 도중에 '다시 쓰지 않는 트랙도 함께'가 드러나면(`patch::NeedsWhole`) 그 자리로 되돌리고 모든
        // 트랙으로 넓혀 다시 한다(그 거절 글의 '메이커에서 내보내기' 안내는 넣고 빼기 길에서 그르다 — 총괄 덧붙임). 거래 바깥은 부르는 쪽 그대로.
        let part = matches!(covers, Covers::Part { .. });
        if part {
            tx.execute_batch("SAVEPOINT pack_part")?;
        }
        let applied = patch::apply(tx, &ApplyIn { plan: &plan, originals: &originals, covers, remove });
        if part {
            if let Some(w) = applied.as_ref().err().and_then(|e| e.downcast_ref::<patch::NeedsWhole>()) {
                widened = Some(Widened { why: "needs_whole", keys: 0, detail: w.0.clone() });
                tx.execute_batch("ROLLBACK TO pack_part; RELEASE pack_part")?;
                opts.scope = Scope::All;
                continue;
            }
            if applied.is_ok() {
                tx.execute_batch("RELEASE pack_part")?;
            } else {
                // apply가 SQLite 오류로 끝나 거래가 이미 되돌려졌으면 되돌림 자리도 없다 — 그 실패는 버리고 원래 오류를 돌려준다(16b 고침 2회차 작은 것 1).
                let _ = tx.execute_batch("ROLLBACK TO pack_part; RELEASE pack_part");
            }
        }
        match applied {
            Ok(apply) => {
                // 모든 트랙을 저장소의 원본으로 다시 셈해 넣었다 — 지금 규칙 판을 적는다(apply는 지웠다 · 판정 R69-2). 하위 배치면 그대로(이미 지금 것).
                if matches!(opts.scope, Scope::All) {
                    patch::mark_rules(tx)?;
                }
                let scope = match &opts.scope { Scope::All => None, Scope::Tracks(_) => narrowed };
                return Ok(PackReport {
                    apply, ms_layout, layouts, scope, ms_read, ms_apply: t0.elapsed().as_secs_f64() * 1000.0,
                    packs: after.iter().map(|p| p.key.clone()).collect(), kept: Vec::new(), unkept: Vec::new(), deleted: Vec::new(),
                    replaced: Vec::new(), skipped: Vec::new(), widened, notes: Vec::new(), ms: started.elapsed().as_secs_f64() * 1000.0,
                });
            }
            Err(e) => {
                // 모든 트랙을 덮는 배치에서의 '함께 다시 써야 함'은 넓힐 곳이 없다 — 배치와 저장소가 어긋난 것: 메이커 내보내기 안내(Part 길의 글)는 앱에
                // 맞지 않으니 떼고 code 없는 쉬운 글로(16b 고침 2회차 작은 것 2).
                if let Some(w) = e.downcast_ref::<patch::NeedsWhole>() {
                    let why = w.0.split("(그 트랙까지 덮는 배치로").next().unwrap_or(&w.0).trim_end().trim_end_matches(" — 배치와 저장소가 어긋났습니다");
                    return Err(format!("배치와 저장소가 어긋나 고쳐 쓰지 못했습니다 — {why} · 저장소는 그대로입니다").into());
                }
                // 넓히기: apply는 아무것도 쓰기 전("choose")에 거절했다 — S에 그 트랙들을 더해 다시 배치한다(S는 늘기만 하니 트랙 수만큼 안에 끝난다).
                let more = match e.downcast_ref::<Widen>() {
                    Some(w) => w.0.clone(),
                    None if content_fault(&*e) => return Err(layout_refusal(e, after, fresh)),
                    None => return Err(e),
                };
                let Scope::Tracks(s) = &mut opts.scope else { return Err(e) };
                let before_len = s.len();
                s.extend(more);
                if s.len() == before_len {
                    return Err(e);
                }
            }
        }
    }
}

/// 배치가 바뀌지 않는 답(배치 · apply 없음 — `layouts` 0 · `first_pos` −1 · 다시 쓴 트랙 없음): `from_store`가 모두 건너뛴 넣기 · 보관함에서만 지우는 빼기.
fn unchanged(tx: &Transaction, h: &Held, started: Instant) -> Result<PackReport> {
    let rows = crate::rowmap::RowMap::load(tx)?.total();
    let ms = started.elapsed().as_secs_f64() * 1000.0;
    Ok(PackReport {
        apply: ApplyReport { first_pos: -1, rows_before: rows, rows_after: rows, ..ApplyReport::default() },
        ms_layout: 0.0, layouts: 0, scope: Some(0), ms_read: ms, ms_apply: 0.0,
        packs: h.packs.iter().map(|p| p.key.clone()).collect(), kept: Vec::new(), unkept: Vec::new(), deleted: Vec::new(),
        replaced: Vec::new(), skipped: Vec::new(), widened: None, notes: Vec::new(), ms,
    })
}

/// 배치(틈)가 실패한 까닭을 앱이 가를 수 있는 거절로(고침 2회차 M-1 · 판정 R61 · R62): DLC의 날짜가 달력 표 범위 밖(lay의 '«달력» 표 범위 밖')은
/// `code` range — DLC 쪽 잘못(쉬운 까닭과 한계 해 · 저장소를 새 시드로 옮겨도 풀리지 않는다), 저장소의 표에 그 달력이 없음('«달력» 표 없음')은 `code` calendar —
/// 저장소 쪽(표 없음 · 깨짐과 같은 길 — 새 판 시드로), 그 밖은 `code` layout('«DLC»를 연표에 배치하지 못했습니다 — <까닭>'). 원래 글(개발자 말 — 'JS라면 TypeError' 꼴)은
/// `detail`(앱의 자세히 보기)로. DLC 탓 code(range · broken · layout)는 이번에 받은 DLC 탓일 때만 단다(판정 R70-4 · R72-3 — 아니면 code 없는 같은 글).
/// 이미 거절이면 그대로.
fn layout_refusal(e: Box<dyn std::error::Error + Send + Sync>, after: &[Pack], fresh: &[Pack]) -> Box<dyn std::error::Error + Send + Sync> {
    if e.downcast_ref::<patch::Refusal>().is_some() {
        return e;
    }
    let raw = e.to_string();
    // 어느 DLC인가 — 글에 든 입력 이름(`<id>.htpack`) · lay 문맥의 '(기본)'은 바탕(`after[0]` — 판정 R72-3: 받은 파일 탓으로 오인하지 않게), 없으면 이번에
    // 받은 DLC, 그것도 없으면 조합.
    let in_raw = after.iter().find(|p| raw.contains(&format!("{}.htpack", p.key)))
        .or_else(|| if raw.contains("DLC를 읽을 수 없습니다(기본)") { after.first() } else { None });
    let named = in_raw.or(fresh.first());
    let who = named.map_or_else(|| "이 DLC 조합".to_owned(), |p| format!("«{}»", p.name));
    // DLC 탓 code(range · broken · layout)는 **이번에 받은 DLC 탓일 때만**(판정 R70-4 · R72-3 — 앱이 받은 파일을 탓으로 기억한다): 글이 받은 DLC를
    // 가리키거나, 아무 DLC도 가리키지 않고 받은 DLC가 있을 때(앞 조합은 배치되었으니 바뀐 것은 받은 DLC). 이미 든 DLC · 바탕을 가리키거나 받은 DLC가
    // 없으면(빼기) code 없이 — 글에 어느 DLC인지는 남는다. 저장소 쪽(calendar)은 그대로.
    let blames_fresh = match in_raw {
        Some(p) => fresh.iter().any(|f| f.key == p.key),
        None => !fresh.is_empty(),
    };
    let dlc_fault = |code: &'static str, message: String| -> Box<dyn std::error::Error + Send + Sync> {
        if blames_fresh { refuse_detail(code, message, raw.clone()) } else { message.into() }
    };
    // 한계 해는 표의 범위 그대로(판정 R72-1 — 내보내기 `calendar` 모듈이 자료 해 ± 100년으로 잘라 쓰는 것은 표 안에서의 일이고(calclip), 이 거절은 실제
    // 보조 달력 날짜가 표 밖일 때만 난다).
    let (lo, hi) = crate::legacy::CALENDAR_YEARS;
    // lay의 달력 거절: '<입력>: <달력 이름> 표 범위 밖 — …' · '<입력>: <달력 이름> 표 없음 — …'(`lay::ctx`) · 달력 모듈은 이름이 괄호 안
    // ('달력 표 범위 밖 — …(음력 · -3500년 ~ 2500년)' · '달력 표 없음 — …(음력)'). 이름을 못 찾으면 None.
    let calendar_of = |mark: &str| -> Option<Option<String>> {
        let at = raw.find(mark)?;
        let head = &raw[..at];
        let mut name = head.rsplit(": ").next().unwrap_or(head).trim();
        if name == "달력" {
            name = raw[at..].split_once('(').and_then(|(_, inner)| inner.split(')').next()).and_then(|s| s.split(" · ").next()).unwrap_or("").trim();
        }
        Some((!name.is_empty() && name != "달력").then(|| name.to_owned()))
    };
    if let Some(cal) = calendar_of(" 표 범위 밖") {
        let cal = cal.map_or_else(|| "보조 달력".to_owned(), |c| format!("보조 달력({c})"));
        return dlc_fault("range", format!("{who}의 날짜가 앱이 아는 달력 범위 밖입니다 — {cal} 날짜는 {lo} ~ {hi}년 안이어야 합니다"));
    }
    if let Some(cal) = calendar_of(" 표 없음") {
        let cal = cal.map_or_else(|| "그 보조 달력이".to_owned(), |c| format!("«{c}»{}", josa(&c, "이", "가")));
        return refuse_detail("calendar", format!("저장소의 달력 표에 {cal} 없어 {who}의 날짜를 읽을 수 없습니다 — 새 판 시드로 옮긴 뒤 다시 해 주세요"), raw);
    }
    // 개발자 말을 걷은 까닭: 입력 이름 머리 · 괄호 속 'JS라면 …'을 뗀다.
    let mut reason = raw.clone();
    if let Some(p) = named {
        reason = reason.replace(&format!("{}.htpack: ", p.key), "").replace(&format!("{}.htpack", p.key), &p.name);
    }
    while let Some(at) = reason.find("(JS라면") {
        let end = reason[at..].find(')').map_or(reason.len(), |e| at + e + 1);
        reason.replace_range(at..end, "");
    }
    // 원본이 깨져 lay가 읽지 못함('<입력>: DLC를 읽을 수 없습니다 — …')은 다시 해도 같다 — broken(받은 DLC 탓일 때만 — 위 `blames_fresh`).
    if raw.contains("DLC를 읽을 수 없습니다") {
        return dlc_fault("broken", format!("{who}의 원본을 읽을 수 없습니다 — {}", reason.trim()));
    }
    let message = format!("{who}{} 연표에 배치하지 못했습니다 — {}", josa(&who, "을", "를"), reason.trim());
    dlc_fault("layout", message)
}

/// 틈(배치 · 닿는 트랙)을 부르고 패닉을 '배치 중 내부 오류' 오류로 바꾼다 — 부르는 쪽이 [`layout_refusal`]로 가른다(고침 3회차).
fn caught<T>(f: impl FnOnce() -> Result<T>) -> Result<T> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)).unwrap_or_else(|p| Err(format!("배치 중 내부 오류: {}", panic_text(&*p)).into()))
}

/// 패닉 값의 글(`&str` · `String` — 아니면 빈 글).
fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    payload.downcast_ref::<&str>().map(|s| (*s).to_owned()).or_else(|| payload.downcast_ref::<String>().cloned()).unwrap_or_default()
}

/// apply 걸음이 배치의 **DLC 내용** 때문에 거절한 글(lay가 걸러 주지 않는 것 — 고침 3회차): 이름 없는 항목 기록 · 그림의 열쇠 · 종류 · base64 · 트랙 열쇠 겹침.
/// 이것들은 배치 실패와 같이 [`layout_refusal`]로 가른다(그 밖의 apply 실패 — 입출력 · 넓히기 · 거절은 그대로).
fn content_fault(e: &(dyn std::error::Error + Send + Sync + 'static)) -> bool {
    if e.downcast_ref::<patch::Refusal>().is_some() || e.downcast_ref::<rusqlite::Error>().is_some() {
        return false;
    }
    let text = e.to_string();
    ["항목 기록에 id가 없습니다", "그림 바이트의 열쇠나 종류가 올바르지 않습니다", "그림 바이트를 풀 수 없습니다", "트랙 열쇠가 겹칩니다"].iter().any(|m| text.contains(m))
}

/// 받침에 맞는 조사(마지막 한글 글자 — 끝의 따옴표 `»`는 건너뜀 · 한글이 아니면 받침 있는 쪽).
fn josa(word: &str, with: &'static str, without: &'static str) -> &'static str {
    match word.chars().rev().find(|c| *c != '»' && !c.is_whitespace()) {
        Some(c @ '가'..='힣') if (c as u32 - 0xAC00) % 28 == 0 => without,
        _ => with,
    }
}

/// 다른 저장소를 읽기 전용으로 연다 — 쓰다 죽어 남은 일지(hot journal)가 있으면 `Store::open`과 같은 길로 되돌린 뒤 다시 연다(고침 2회차 M-7 —
/// 읽기 전용 연결은 일지를 되돌리지 못해 첫 읽기에서 SQLITE_READONLY로 실패한다).
fn open_other(path: &Path) -> Result<Connection> {
    let open = || -> Result<Connection> {
        let db = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX)
            .map_err(|e| format!("다른 저장소를 열지 못했습니다({}): {e}", path.display()))?;
        db.execute_batch("PRAGMA query_only=ON; PRAGMA busy_timeout=5000;")?;
        db.query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get::<_, i64>(0))?;
        Ok(db)
    };
    match open() {
        Err(first) if first.downcast_ref::<rusqlite::Error>().is_some_and(|e| matches!(e, rusqlite::Error::SqliteFailure(f, _) if f.code == rusqlite::ErrorCode::ReadOnly)) => {
            crate::Store::recover_journal(path).and_then(|()| open()).map_err(|_| first)
        }
        other => other,
    }
}

/// 보관함의 그 id(없으면 None).
fn shelf_pack(db: &Connection, id: &str) -> Result<Option<Pack>> {
    if !has_table(db, "kept_packs")? {
        return Ok(None);
    }
    Ok(db.query_row("SELECT key,name,version,original FROM kept_packs WHERE key=?1", [id],
        |r| Ok(Pack { key: r.get(0)?, name: r.get(1)?, version: r.get(2)?, original: Some(Rc::from(r.get::<_, Vec<u8>>(3)?)), format4: false })).optional()?)
}

/// 보관함에서 그 id들을 지운다(넣거나 버린 DLC).
fn unkeep(tx: &Transaction, ids: &[String]) -> Result<Vec<String>> {
    let mut out = Vec::new();
    if !has_table(tx, "kept_packs")? {
        return Ok(out);
    }
    for id in ids {
        if tx.execute("DELETE FROM kept_packs WHERE key=?1", [id])? > 0 {
            out.push(id.clone());
        }
    }
    Ok(out)
}

/// DLC 넣기(계약 2-7 `{"op":"add_pack"}`) — 부르는 쪽의 쓰기 거래 안에서. 받는 것: 파일 · `from_store`의 `ids`(판정 R34 D) · `from_store`가 없으면 `ids`는 이 저장소의 보관함.
/// 같은 id가 저장소에 있으면 판을 견주어 **낮으면 거절**(`code` version — 판정 R15), 같거나 높으면 그 자리에서 바꿔 넣는다(원본 없던 DLC는 채워 넣는다).
/// `from_store`의 id는 이 저장소에 같거나 높은 판이 원본까지 들어 있으면 건너뛴다(`skipped`). `prefer_given`이면 둘 다 하지 않고 받은 것이 이긴다(미리보기용).
/// 새 DLC는 지금 차례 뒤에 붙는다. 넣은 DLC는 보관함에서 꺼낸다.
pub fn add_pack(tx: &Transaction, order: &AddOrder, layouter: &dyn Layouter) -> Result<PackReport> {
    let _clear = ClearCaches;
    let started = Instant::now();
    if order.files.is_empty() && order.ids.is_empty() {
        return Err("넣을 DLC가 없습니다(files · ids)".into());
    }
    if order.from_store.is_some() && order.ids.is_empty() {
        return Err("다른 저장소(from_store)에서 꺼낼 DLC id(ids)가 없습니다".into());
    }
    let h = held(tx)?;
    let cal = need_calendar(tx, layouter)?;
    let mut incoming: Vec<Pack> = Vec::new();
    for path in &order.files {
        incoming.push(file_pack(path)?);
    }
    let other = match &order.from_store {
        Some(path) => Some(open_other(path)?),
        None => None,
    };
    let mut skipped = Vec::new();
    for p in stored_packs(other.as_ref(), tx, &order.ids)? {
        // 다른 저장소에서 온 것: 이 저장소에 같거나 높은 판이 원본까지 들었으면 건너뛴다(휴대폰 시드 잇기 — 새 시드에 이미 든 DLC).
        let have = h.packs.iter().find(|q| q.key == p.key && q.original.is_some());
        if other.is_some() && !order.prefer_given && have.is_some_and(|q| compare_versions(&q.version, &p.version).is_ge()) {
            skipped.push(p.key);
        } else {
            incoming.push(p);
        }
    }
    drop(other);
    let mut seen = BTreeSet::new();
    for p in &incoming {
        if !seen.insert(p.key.clone()) {
            return Err(format!("«{}»를 둘 받았습니다", p.key).into());
        }
    }
    if incoming.is_empty() {
        // 모두 건너뜀 — 할 일이 없다(저장소 그대로).
        let mut report = unchanged(tx, &h, started)?;
        report.skipped = skipped;
        return Ok(report);
    }
    // 판 대조(판정 R15): 같은 id의 낮은 판은 거절 — 같거나 높으면 그 자리에서 바꿔 넣는다(원본 없던 DLC는 채워 넣는다).
    let mut after = h.packs.clone();
    let mut replaced = Vec::new();
    for p in &incoming {
        match after.iter_mut().find(|q| q.key == p.key) {
            Some(q) => {
                if !order.prefer_given && compare_versions(&p.version, &q.version).is_lt() {
                    return Err(refuse("version", format!("«{}»의 판이 저장소보다 낮습니다(저장소 v{} · 받은 v{}) — 낮은 판으로는 바꾸지 않습니다", p.name, q.version, p.version)));
                }
                // 같은 id가 보관함에도 있으면(조합에는 원본 없이 — 메이커 배치로 다시 든 것) 넣으며 보관함에서 빠지므로 그 판과도 견준다(고침 3회차 — 검토 ① Minor 4).
                if let Some(k) = shelf_pack(tx, &p.key)? {
                    if !order.prefer_given && compare_versions(&p.version, &k.version).is_lt() {
                        return Err(refuse("version", format!("«{}»의 판이 보관함(꺼 둔 DLC)의 것보다 낮습니다(보관함 v{} · 받은 v{}) — 낮은 판으로는 바꾸지 않습니다",
                            p.name, k.version, p.version)));
                    }
                }
                if q.original != p.original {
                    replaced.push(Replaced { id: p.key.clone(), old_version: q.version.clone(), new_version: p.version.clone(),
                        old_sha256: q.original.as_deref().map(sha256), new_sha256: sha256(p.original.as_deref().unwrap_or_default()) });
                }
                *q = p.clone();
            }
            None => {
                // 보관함에만 있는 같은 id(꺼 둔 DLC — 넣으면 보관함에서 꺼내 지운다): 그 판과 견준다 — 낮으면 거절해 보관함의 높은 판 원본을 잃지 않게(판정 R15 ·
                // 고침 2회차 ②-1). 바이트가 다르면 `replaced`에 보관함 원본의 지문.
                if let Some(k) = shelf_pack(tx, &p.key)? {
                    if !order.prefer_given && compare_versions(&p.version, &k.version).is_lt() {
                        return Err(refuse("version", format!("«{}»의 판이 보관함(꺼 둔 DLC)의 것보다 낮습니다(보관함 v{} · 받은 v{}) — 낮은 판으로는 바꾸지 않습니다",
                            p.name, k.version, p.version)));
                    }
                    if k.original != p.original {
                        replaced.push(Replaced { id: p.key.clone(), old_version: k.version.clone(), new_version: p.version.clone(),
                            old_sha256: k.original.as_deref().map(sha256), new_sha256: sha256(p.original.as_deref().unwrap_or_default()) });
                    }
                }
                after.push(p.clone());
            }
        }
    }
    missing_originals(&after)?;
    // 형식 4 파일의 내림 알림(거절 아님 — 답의 `notes` · 과제 10): 배치 전에 읽어 둔다(배치가 거절하면 알림도 가지 않는다 — 저장소 그대로).
    // 옛 저장소(달력 표 다섯)에 없는 달력의 날짜를 쓴 DLC의 건너뜀 알림도(감독 결정 2026-10-25 — 표로 읽는 틈만: 검사의 Node 틈은 ICU로 읽어 건너뛰지 않는다).
    let mut notes = format4_notes(&incoming, &h);
    if layouter.needs_calendar() {
        notes.extend(calendar_notes(&incoming, &h, &cal));
    }
    let ms_read = started.elapsed().as_secs_f64() * 1000.0;
    let mut report = relayout(tx, &h, &cal, &after, &incoming, &[], layouter, started, ms_read)?;
    report.unkept = unkeep(tx, &incoming.iter().map(|p| p.key.clone()).collect::<Vec<_>>())?;
    report.replaced = replaced;
    report.skipped = skipped;
    report.notes = notes;
    report.ms = started.elapsed().as_secs_f64() * 1000.0;
    Ok(report)
}

/// DLC 빼기(계약 2-7 `{"op":"remove_pack"}`) — 그 DLC를 뺀 조합으로 같은 흐름. 기본 DLC(첫째)는 뺄 수 없다(연표의 바탕 — 앱은 바탕을 화면에서만 켜고 끈다 · 판정 R43).
/// 빼는 DLC 제 원본은 요구하지 않는다(원본 없던 DLC도 뺄 수 있다 — 남는 DLC는 모두 원본이 있어야 한다).
/// `delete`가 거짓이면 원본을 보관함(`kept_packs`)에 남기고, 참이면 버린다(보관함에 있던 것도). 원본이 없던 DLC는 남길 것이 없어 `deleted`에 든다.
/// 보관함에만 있는 id(꺼 둔 DLC)를 `delete`로 주면 그 원본만 지운다(판정 R42 — 배치 · apply 없이).
pub fn remove_pack(tx: &Transaction, order: &RemoveOrder, layouter: &dyn Layouter) -> Result<PackReport> {
    let _clear = ClearCaches;
    let started = Instant::now();
    let h = held(tx)?;
    let Some(at) = h.packs.iter().position(|p| p.key == order.id) else {
        // 보관함에만 있는 DLC(앱의 '꺼 둔' DLC — 판정 R42): `delete`면 그 원본만 지운다 — 조합 · 배치는 그대로라 apply 없이(달력 표도 보지 않는다).
        let shelved = has_table(tx, "kept_packs")? && tx.prepare("SELECT 1 FROM kept_packs WHERE key=?1")?.exists([&order.id])?;
        if !shelved {
            return Err(format!("빼라는 DLC «{}»가 지금 저장소에 없습니다", order.id).into());
        }
        if !order.delete {
            return Err(format!("«{}»는 이미 꺼 둔(보관함의) DLC입니다 — 지우려면 delete를 주세요", order.id).into());
        }
        let mut report = unchanged(tx, &h, started)?;
        unkeep(tx, std::slice::from_ref(&order.id))?;
        report.deleted.push(order.id.clone());
        report.ms = started.elapsed().as_secs_f64() * 1000.0;
        return Ok(report);
    };
    if at == 0 {
        return Err(format!("기본 DLC «{}»는 뺄 수 없습니다 — 연표의 바탕이라 다른 DLC만 빼거나 끌 수 있습니다", h.packs[0].name).into());
    }
    let cal = need_calendar(tx, layouter)?;
    let gone = h.packs[at].clone();
    let after: Vec<Pack> = h.packs.iter().filter(|p| p.key != order.id).cloned().collect();
    missing_originals(&after)?;
    let ms_read = started.elapsed().as_secs_f64() * 1000.0;
    let mut report = relayout(tx, &h, &cal, &after, &[], std::slice::from_ref(&order.id), layouter, started, ms_read)?;
    match (&gone.original, order.delete) {
        (Some(original), false) => {
            tx.execute_batch(KEPT_TABLE)?;
            tx.execute("INSERT OR REPLACE INTO kept_packs(key,name,version,original,sha256) VALUES(?1,?2,?3,?4,?5)",
                params![gone.key, gone.name, gone.version, &**original, sha256(original)])?;
            report.kept.push(order.id.clone());
        }
        (None, false) => {
            // 원본 없던 DLC를 남기며 뺌: 남길 원본이 없다 — 보관함에 같은 id(전에 꺼 둔 다른 판)가 있으면 그대로 두고 `kept`(그 id의 원본이 보관함에 남음),
            // 없으면 `deleted`(고침 2회차 ②).
            if shelf_pack(tx, &order.id)?.is_some() {
                report.kept.push(order.id.clone());
            } else {
                report.deleted.push(order.id.clone());
            }
        }
        (_, true) => {
            unkeep(tx, std::slice::from_ref(&order.id))?;
            report.deleted.push(order.id.clone());
        }
    }
    report.ms = started.elapsed().as_secs_f64() * 1000.0;
    Ok(report)
}

/// 보관함의 DLC(`{"op":"kept_packs"}` — 앱의 DLC 관리 창이 '꺼 둔 DLC'로 그린다) — `[{id, name, version, bytes}]`, id 차례. 표가 없으면 빈 목록.
pub fn kept_packs(db: &Connection) -> Result<Value> {
    if !has_table(db, "kept_packs")? {
        return Ok(json!([]));
    }
    let mut stmt = db.prepare("SELECT key,name,version,length(original) FROM kept_packs ORDER BY key")?;
    let list = stmt.query_map([], |r| Ok(json!({"id":r.get::<_, String>(0)?,"name":r.get::<_, String>(1)?,"version":r.get::<_, String>(2)?,"bytes":r.get::<_, i64>(3)?})))?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    Ok(json!(list))
}

/// FFI 요청 `{"op":"add_pack","files"?:[…],"from_store"?:"…","ids"?:[…],"prefer_given"?:bool}` → [`AddOrder`].
pub fn add_order(q: &Value) -> Result<AddOrder> {
    let words = |key: &str| -> Result<Vec<String>> {
        match &q[key] {
            Value::Null => Ok(Vec::new()),
            Value::Array(list) => list.iter().map(|v| v.as_str().filter(|s| !s.is_empty()).map(str::to_owned)
                .ok_or_else(|| format!("{key}는 글의 목록이어야 합니다").into())).collect(),
            _ => Err(format!("{key}는 글의 목록이어야 합니다").into()),
        }
    };
    let from_store = match &q["from_store"] {
        Value::Null => None,
        Value::String(s) if !s.is_empty() => Some(PathBuf::from(s)),
        _ => return Err("from_store는 저장소 경로 글이어야 합니다".into()),
    };
    let prefer_given = match &q["prefer_given"] {
        Value::Null => false,
        Value::Bool(b) => *b,
        _ => return Err("prefer_given은 참 · 거짓이어야 합니다".into()),
    };
    Ok(AddOrder { files: words("files")?.into_iter().map(PathBuf::from).collect(), from_store, ids: words("ids")?, prefer_given })
}

/// FFI 요청 `{"op":"remove_pack","id":"…","delete":bool}` → [`RemoveOrder`].
pub fn remove_order(q: &Value) -> Result<RemoveOrder> {
    let id = q["id"].as_str().filter(|s| !s.is_empty()).ok_or("뺄 DLC id(id)가 없습니다")?.to_owned();
    let delete = match &q["delete"] {
        Value::Null => false,
        Value::Bool(b) => *b,
        _ => return Err("delete는 참 · 거짓이어야 합니다".into()),
    };
    Ok(RemoveOrder { id, delete })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_by_parts_like_add_dlc() {
        use std::cmp::Ordering::*;
        for (a, b, want) in [("1.0.0", "1.0.0", Equal), ("1.1.0", "1.0.9", Greater), ("1.0", "1.0.0", Equal), ("2", "10", Less), ("1.0.3", "1.0.10", Less),
            ("", "0", Equal), ("1.0.0-b", "1.0.0", Equal), ("v2", "1", Less)] {
            assert_eq!(compare_versions(a, b), want, "{a} · {b}");
        }
    }

    #[test]
    fn a_calendar_read_failure_is_not_a_broken_table() {
        // 판정 R68 ②: 저장소를 읽다 난 입출력 실패(디스크 · 잠금 · 메모리)는 환경 탓 — code 없이(다음에 다시). 풀리지 않는 표 · 꼴이 틀린 줄은 깨진 표(calendar).
        let code = |e: Box<dyn std::error::Error + Send + Sync>| e.downcast_ref::<patch::Refusal>().map(|r| r.code);
        for raw in [rusqlite::ffi::SQLITE_IOERR, rusqlite::ffi::SQLITE_BUSY, rusqlite::ffi::SQLITE_LOCKED, rusqlite::ffi::SQLITE_NOMEM, rusqlite::ffi::SQLITE_FULL] {
            let e = calendar_failure(Box::new(rusqlite::Error::SqliteFailure(rusqlite::ffi::Error::new(raw), None)));
            assert_eq!(code(e), None, "SQLite {raw}");
        }
        assert_eq!(code(calendar_failure("저장소의 달력 표를 풀지 못했습니다: corrupt deflate stream".into())), Some("calendar"));
        assert_eq!(code(calendar_failure(Box::new(rusqlite::Error::InvalidColumnType(0, "bytes".into(), rusqlite::types::Type::Text)))), Some("calendar"));
        assert_eq!(code(calendar_failure(Box::new(rusqlite::Error::SqliteFailure(rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_CORRUPT), None)))),
            Some("calendar"), "저장소 파일이 깨짐은 깨짐");
    }
}

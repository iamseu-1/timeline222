//! 입력 DLC(`PackIn`)의 바이트 → 원본 DLC(JS 값 [`V`]) — 한 벌 P3 과제 5a.
//! - `.htpack`(표지 `HTPACK\r\n`): `js/packfile.js`(SHA-256 앞 12자 `874c850181a3`)의 `kindOf`(48 ~ 53줄) · `parse`(81 ~ 94줄)를 옮겼다. 머리 · 크기 · 지문 · 풀기는 엔진의 [`unseal`](crate::unseal)
//!   (`packfile.js`의 `unseal`과 같은 검사 차례 · 종류 1 = DLC만), 본문은 `TextDecoder('utf-8', { fatal: true })`처럼 엄격히(맨 앞 BOM은 버림) 읽어 `JSON.parse`([`js::parse`] — 열쇠 넣은 차례).
//!   형식 4면 여기서 옛 꼴로 내린다(`HT.F4.down` — 알림은 `notes`).
//! - 그 밖(JSON 글 — 정답지의 견본 · 굳힌 내장 팩): Node `JSON.parse(bytes.toString('utf8'))`처럼 읽는다(깨진 UTF-8은 U+FFFD · BOM은 남겨 JSON 오류).
//!   형식 4 JSON은 정규화(`HT.normalizePack`)가 내린다.
//!
//! 형식 1 ~ 4를 모두 받는다(계획 정한 것 #6 — 감독 2026-10-16 "추천대로").
use super::js::{self, V};
use super::read::{vocab, Ctx};
use super::{f4, PackIn};

/// `packfile.js`의 `kindOf(raw)` — 1(DLC) · 2(전체 백업) · 그 밖은 오류.
fn kind_of(raw: &V) -> crate::Result<u8> {
    if !matches!(raw, V::Obj(_)) { return Err("팩 내용이 올바르지 않습니다.".into()); }
    if matches!(raw.get("format"), V::Str(s) if s == vocab::FORMAT) { return Ok(1); }
    if matches!(raw.get("format"), V::Str(s) if s == "history-timeline-backup") && matches!(raw.get("installed"), V::Arr(_)) { return Ok(2); }
    Err("역사 연표의 DLC나 백업이 아닙니다.".into())
}

/// 원본 DLC 하나. `notes`는 형식 4를 내릴 때의 알림(`packFile.parse`의 `notes`).
pub fn raw_of(ctx: &Ctx, pack: &PackIn, notes: &mut Vec<String>) -> crate::Result<V> {
    if pack.bytes.starts_with(crate::PACK_MAGIC) {
        // parse(input): unseal(input, [1, 2]) — 엔진의 unseal은 한 종류만 받으므로 DLC(1)로(백업은 DLC가 아니라 정규화가 받지 않는다)
        let open = crate::unseal(&pack.bytes, crate::KIND_DLC).map_err(|e| format!("{}: 팩 파일을 열 수 없습니다 — {e:?}", pack.name))?;
        let plain = open.plain.strip_prefix(b"\xEF\xBB\xBF".as_slice()).unwrap_or(&open.plain);
        let text = std::str::from_utf8(plain).map_err(|_| format!("{}: 팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다.", pack.name))?;
        // 쉬운 글에 까닭(`JSON.parse: …` — 예: 겹침 상한 512겹)을 버리지 않고 붙인다(판정 R64 · M3). JSON 파일 길(38줄)은 이미 '… JSON이 아닙니다 — 까닭'이다.
        let raw = js::parse(text).map_err(|e| format!("{}: 팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다({e}).", pack.name))?;
        if kind_of(&raw)? != pack.bytes[9] { return Err(format!("{}: 팩 종류와 내용이 맞지 않습니다.", pack.name).into()); }
        // 형식 4(리메이크 1단계 1a): 옛 꼴로 내려 받는다
        if js::to_num(&raw.get("formatVersion")) == f4::VERSION {
            notes.push("형식 4 파일을 지금 형식으로 바꿔 읽었습니다(저장은 지금 형식으로 됩니다).".into());
            return f4::down(ctx, &raw, &mut |m| notes.push(m));
        }
        return Ok(raw);
    }
    let text = String::from_utf8_lossy(&pack.bytes);
    js::parse(&text).map_err(|e| format!("{}: JSON이 아닙니다 — {e}", pack.name).into())
}

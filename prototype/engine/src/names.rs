//! 원어 병기 · 글꼴(10건 3 · 9 — 갈래 D2)의 새 앱 몫을 돕는 조회 둘. **스키마 판 '3' 그대로 — 표 · 열을 더하지 않고 이미 있는 것만 읽는다.**
//! 설계 `docs/설계-10건/3-9-원어와-글꼴.md` 7절(구현 기록) · 감독 선택 `docs/설계-10건/감독-선택.md` D2.
//!
//! - `{"op":"names_info"}` → `{"packs":[이름 목록이 있는 자료집 번호…], "fonts":[{uid, pack, id, family, license, scripts?, ranges?, note?}]}`
//!   필터 시트의 '표기' 무리를 보일지(자료에 이름 목록이나 글꼴이 있을 때만 — 웹 viewer.js `syncNamesUi`)와 글꼴 팩의 목록이다.
//!   '이름 목록이 있다' = 그 자료집의 항목 기록에 미리 푼 이름 줄(`x_names` · `x_cellNames` — 형식 3 내보내기 A1-a부터)이 있다.
//!   글꼴은 항목 기록 `font:<id>`(갈래 font — 파일은 크기만 `{"$bytes":n}`)의 본문에서 읽는다. 차례는 자료집 번호 → uid.
//!   어느 것도 없는 저장소(동아시아 · 월흔해 · 형식 3 전의 저장소)는 빈 목록 둘이다.
//! - `{"op":"font_data","uids":["font:<id>",…]}` → `{"fonts":[{uid, family, mime, data(base64)}], "missing":[{uid, why}]}`
//!   글꼴 파일은 가져오기 JSON에 싣지 않았다(A1 — 기록에는 크기만). 저장소가 품은 그 DLC의 원본(`packs.original` — .htpack)을 풀어
//!   `fonts[].src`(`data:font/…;base64,…`)의 base64를 **그대로** 돌려준다(바이트를 저장소에 두 번 싣지 않는다 · 풀기는 앱이 한다).
//!   원본 없이 넣은 DLC(Node 없이 .htlayout만 받은 것)는 꺼낼 수 없다 — `missing`에 까닭을 적고, 앱은 기본 글꼴 + 다음 표기로 그린다.
//!   한 번에 32개까지 · 같은 자료집의 원본은 한 번만 푼다.
use crate::{Result, Store};
use serde_json::{json, Map, Value};
use std::collections::HashMap;

/// 한 번에 묻는 글꼴의 수(한 DLC에 8개 — F3 한도 — 넉넉히).
const FONT_ASK_MAX: usize = 32;

impl Store {
    /// 이름 목록이 있는 자료집과 글꼴 목록(위의 첫째 조회).
    pub fn names_info(&self) -> Result<Value> {
        let mut packs: Vec<i64> = Vec::new();
        {
            // 본문(JSON 글) 안에 열쇠 이름이 있는지만 본다 — 내보내기는 열쇠를 `"x_names":`처럼 빈칸 없이 적는다.
            let mut stmt = self.db.prepare(
                "SELECT DISTINCT pack FROM entities WHERE instr(json,'\"x_names\":')>0 OR instr(json,'\"x_cellNames\":')>0 ORDER BY pack",
            )?;
            for pack in stmt.query_map([], |r| r.get::<_, i64>(0))? {
                packs.push(pack?);
            }
        }
        let mut fonts: Vec<Value> = Vec::new();
        {
            let mut stmt = self.db.prepare("SELECT uid,pack,json FROM entities WHERE kind='font' ORDER BY pack,uid")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, String>(2)?)))?;
            for row in rows {
                let (uid, pack, text) = row?;
                let body: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
                let mut one = Map::new();
                one.insert("uid".into(), json!(uid));
                one.insert("pack".into(), json!(pack));
                let id = body["id"].as_str().map(str::to_owned).unwrap_or_else(|| uid.trim_start_matches("font:").to_owned());
                one.insert("id".into(), json!(id));
                for key in ["family", "license"] {
                    one.insert(key.into(), json!(body[key].as_str().unwrap_or("")));
                }
                for key in ["scripts", "ranges"] {
                    if let Some(list) = body[key].as_array().filter(|l| !l.is_empty()) {
                        one.insert(key.into(), Value::Array(list.iter().filter(|v| v.is_string()).cloned().collect()));
                    }
                }
                if let Some(note) = body["note"].as_str().filter(|s| !s.is_empty()) {
                    one.insert("note".into(), json!(note));
                }
                fonts.push(Value::Object(one));
            }
        }
        Ok(json!({"packs":packs,"fonts":fonts}))
    }

    /// 글꼴 파일(위의 둘째 조회). 꺼내지 못한 것은 `missing`에 까닭과 함께.
    pub fn font_data(&self, q: &Value) -> Result<Value> {
        let list = q["uids"].as_array().ok_or("글꼴 이름 목록(uids) 누락")?;
        if list.len() > FONT_ASK_MAX {
            return Err(format!("글꼴은 한 번에 {FONT_ASK_MAX}개까지 묻습니다").into());
        }
        let mut wanted: Vec<String> = Vec::with_capacity(list.len());
        for v in list {
            let uid = v.as_str().ok_or("글꼴 이름이 글자가 아닙니다")?;
            if !wanted.iter().any(|w| w == uid) {
                wanted.push(uid.to_owned());
            }
        }
        let mut fonts: Vec<Value> = Vec::new();
        let mut missing: Vec<Value> = Vec::new();
        // 자료집 번호 → 풀어 둔 원본의 fonts 목록(같은 원본을 두 번 풀지 않는다). 원본이 없거나 풀지 못하면 까닭.
        let mut opened: HashMap<i64, std::result::Result<Vec<Value>, String>> = HashMap::new();
        for uid in &wanted {
            let found: Option<(i64, String)> = self
                .db
                .query_row("SELECT pack,json FROM entities WHERE uid=?1 AND kind='font'", [uid.as_str()], |r| Ok((r.get(0)?, r.get(1)?)))
                .ok();
            let Some((pack, text)) = found else {
                missing.push(json!({"uid":uid,"why":"그 글꼴 기록이 없습니다"}));
                continue;
            };
            let body: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
            let id = body["id"].as_str().map(str::to_owned).unwrap_or_else(|| uid.trim_start_matches("font:").to_owned());
            let raws = opened.entry(pack).or_insert_with(|| self.pack_fonts(pack));
            let raws = match raws {
                Ok(list) => list,
                Err(why) => {
                    missing.push(json!({"uid":uid,"why":why.clone()}));
                    continue;
                }
            };
            let Some(raw) = raws.iter().find(|f| f["id"].as_str() == Some(id.as_str())) else {
                missing.push(json!({"uid":uid,"why":"원본에 그 글꼴이 없습니다"}));
                continue;
            };
            match split_font_url(raw["src"].as_str().unwrap_or("")) {
                Some((mime, data)) => {
                    let family = raw["family"].as_str().or(body["family"].as_str()).unwrap_or("");
                    fonts.push(json!({"uid":uid,"family":family,"mime":mime,"data":data}));
                }
                None => missing.push(json!({"uid":uid,"why":"글꼴 파일이 data:font/…;base64 꼴이 아닙니다"})),
            }
        }
        Ok(json!({"fonts":fonts,"missing":missing}))
    }

    /// 그 자료집이 품은 원본(.htpack)의 `fonts` 목록. 원본이 없거나 풀지 못하면 까닭 글.
    fn pack_fonts(&self, pack: i64) -> std::result::Result<Vec<Value>, String> {
        let original: Option<Vec<u8>> = self
            .db
            .query_row("SELECT original FROM packs WHERE id=?1", [pack], |r| r.get::<_, Option<Vec<u8>>>(0))
            .map_err(|_| "그 자료집이 저장소에 없습니다".to_owned())?;
        let bytes = original.ok_or_else(|| "원본 없이 넣은 DLC라 글꼴 파일을 꺼낼 수 없습니다".to_owned())?;
        let raw = crate::htpack_raw(&bytes).map_err(|e| format!("품은 원본을 풀지 못했습니다: {e}"))?;
        Ok(raw["fonts"].as_array().cloned().unwrap_or_default())
    }
}

/// `data:font/woff2;base64,AAAA` → (`font/woff2`, `AAAA`). 글꼴 종류(font/…)의 base64 꼴이 아니면 None.
fn split_font_url(src: &str) -> Option<(&str, &str)> {
    let (head, data) = src.trim().split_once(',')?;
    let mime = head.strip_prefix("data:")?.strip_suffix(";base64")?;
    (mime.starts_with("font/") && !data.is_empty()).then_some((mime, data))
}

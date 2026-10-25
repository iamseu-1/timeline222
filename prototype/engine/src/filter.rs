//! 거르개 — 필터 시트의 켬끔(트랙 · 분류 · 종류 · 실재성 · 중요도 문턱)을 자료 조회에 잇는 길.
//! 약속은 `docs/계약-아카이브-3단계.md` 2절의 '거르개' 소절이고, 뜻은 지금 연표의 `applyFilters`
//! (명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 6-3절) 그대로다.
//!
//! - 모든 열쇠는 선택이다. 거르개가 없거나 비었으면 **아무것도 거르지 않는다** — 그때의 답은 거르개가 없던 때와
//!   바이트 단위로 같다(부르는 쪽이 `Option<Filtered>`의 `None`으로 옛 길을 그대로 탄다).
//! - 잘못된 값(글자 · 음수)은 까닭을 적은 한국어 글로 실패한다.
//! - 켠 자료집(`packs`)과는 따로 논다 — 자료집은 '무엇을 보는가', 거르개는 '본 것 가운데 무엇을 그리는가'다.
use crate::{Result, Store};
use serde_json::Value;
use std::collections::HashSet;

/// 인물의 활동 막대가 실리는 일반 구역(계약 6-7).
pub const SECTION_FIGURE_BAR: i64 = 37;

/// 요청에 실려 오는 거르개 그대로. 번호 목록은 오름차순 · 중복 없이 다듬어 둔다.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Filter {
    /// 꺼진 트랙의 번호(`tracks.id`).
    pub tracks_off: Vec<i64>,
    /// 꺼진 분류의 번호(사건의 `look & 0xFF`).
    pub cats_off: Vec<i64>,
    /// 꺼진 정권 종류의 번호(띠의 `look & 0x1F` — 계약 6-1).
    pub kinds_off: Vec<i64>,
    /// 꺼진 실재성의 번호(띠의 `(look >> 8) & 7` — 계약 6-1).
    pub hist_off: Vec<i64>,
    /// 중요도 문턱(1 모든 사건 · 2 보통 이상 · 3 중요 사건만). 0과 1은 거르지 않는 것과 같다.
    pub min_importance: i64,
}

/// 번호 목록 하나 읽기. 없으면 빈 목록, 정수가 아니거나 음수면 까닭과 함께 실패한다.
fn ids(filter: &Value, key: &str) -> Result<Vec<i64>> {
    match &filter[key] {
        Value::Null => Ok(Vec::new()),
        Value::Array(list) => {
            let mut out: Vec<i64> = Vec::with_capacity(list.len());
            for item in list {
                let n = item.as_i64().ok_or_else(|| format!("거르개의 {key}에 정수가 아닌 값이 있습니다"))?;
                if n < 0 {
                    return Err(format!("거르개의 {key}는 0 이상의 번호입니다").into());
                }
                if !out.contains(&n) {
                    out.push(n);
                }
            }
            out.sort_unstable();
            Ok(out)
        }
        _ => Err(format!("거르개의 {key}는 번호의 목록입니다").into()),
    }
}

/// 번호 목록을 SQL의 `IN (…)` 글로. 값은 모두 검사를 지난 정수라 그대로 적어도 안전하다.
fn in_list(expr: &str, values: &[i64]) -> Option<String> {
    (!values.is_empty()).then(|| {
        let text: Vec<String> = values.iter().map(i64::to_string).collect();
        format!("{expr} IN ({})", text.join(","))
    })
}

impl Filter {
    /// 요청의 `filter`를 읽는다. 없거나 비었으면 `None`(거르지 않음)이다.
    pub fn of(q: &Value) -> Result<Option<Filter>> {
        let raw = &q["filter"];
        match raw {
            Value::Null => Ok(None),
            Value::Object(_) => {
                let min = match &raw["min_importance"] {
                    Value::Null => 0,
                    v => {
                        let n = v.as_i64().ok_or("거르개의 min_importance는 정수입니다")?;
                        if n < 0 {
                            return Err("거르개의 min_importance는 0 이상입니다".into());
                        }
                        n
                    }
                };
                let filter = Filter {
                    tracks_off: ids(raw, "tracks_off")?,
                    cats_off: ids(raw, "cats_off")?,
                    kinds_off: ids(raw, "kinds_off")?,
                    hist_off: ids(raw, "hist_off")?,
                    min_importance: min,
                };
                Ok((!filter.is_empty()).then_some(filter))
            }
            _ => Err("거르개(filter)는 열쇠 표입니다".into()),
        }
    }

    /// 아무것도 거르지 않는가.
    pub fn is_empty(&self) -> bool {
        self.tracks_off.is_empty() && self.cats_off.is_empty() && self.kinds_off.is_empty() && self.hist_off.is_empty() && self.min_importance <= 1
    }
}

/// 저장소에 비추어 푼 거르개. 꺼진 줄과 꺼진 띠를 미리 모아 두어, 타일은 번호를 짚어 보기만 한다.
/// 줄은 모두 저장소 안의 줄 **열쇠**(`rows.id` · `events.lane` · `periods.row`)로 말한다 — 밖에서 받은 자리(조회의 `row` 같은)는
/// 부르는 쪽이 먼저 열쇠로 바꿔 넘긴다(계획 P4 · `rowmap`). 거르개 자체는 트랙 · 분류 · 종류 번호만 받아 줄 자리와 상관없다.
#[derive(Debug, Clone)]
pub struct Filtered {
    pub filter: Filter,
    /// 꺼진 트랙에 든 줄의 열쇠.
    off_rows: HashSet<i64>,
    /// 꺼진 띠의 번호(트랙 · 종류 · 실재성 가운데 하나라도 꺼진 띠).
    off_bands: HashSet<i64>,
}

impl Filtered {
    /// 꺼진 줄인가(꺼진 트랙의 줄). `row`는 줄 열쇠다.
    pub fn row_off(&self, row: i64) -> bool {
        self.off_rows.contains(&row)
    }

    /// 꺼진 띠인가.
    pub fn band_off(&self, band: i64) -> bool {
        self.off_bands.contains(&band)
    }

    /// 꺼진 사건인가 — 트랙이 꺼짐 · 분류가 꺼짐 · 중요도 미달 · 딸린 띠가 꺼짐(명세 6-3).
    pub fn event_off(&self, row: i64, look: i64, importance: i64, band: i64) -> bool {
        self.row_off(row)
            || self.filter.cats_off.binary_search(&(look & 0xFF)).is_ok()
            || importance < self.filter.min_importance
            || (band != 0 && self.band_off(band))
    }

    /// 타일이 미리 셈해 둔 사건 수(단계별 요약)를 그대로 쓸 수 있는가.
    /// 사건에 걸리는 거르개가 하나라도 있으면 그 자리에서 다시 세야 한다.
    pub fn counts_events(&self) -> bool {
        !self.filter.cats_off.is_empty() || self.filter.min_importance > 1 || !self.off_rows.is_empty() || !self.off_bands.is_empty()
    }

    /// 인물 막대(구역 37)는 사건처럼 중요도 문턱에 걸린다(명세 6-3의 '인물'). 중요도는 `b`의 아래 2비트다(계약 6-7).
    /// 일반 항목의 뜻은 그리는 쪽의 몫이지만, 거르기만은 이 한 구역을 알아야 한다.
    pub fn figure_bar_off(&self, section: i64, b: i64) -> bool {
        section == SECTION_FIGURE_BAR && (b & 3) < self.filter.min_importance
    }

    // ---- 조회 명령이 SQL에 끼워 쓰는 조각 ----

    /// 꺼진 줄의 조건. `row_expr`은 줄 열쇠를 내는 글(`p.row` · `e.lane`)이다.
    /// 줄 번호가 없는 줄(-1 · NULL)은 트랙을 물을 수 없다 — 그때는 -1로 보아 걸리지 않게 한다
    /// (`NOT (NULL IN …)`은 NULL이라 조건이 거짓이 되어 멀쩡한 줄까지 사라진다).
    fn row_off_sql(&self, row_expr: &str) -> Option<String> {
        in_list(&format!("COALESCE((SELECT track FROM rows WHERE id={row_expr}),-1)"), &self.filter.tracks_off)
    }

    /// 꺼진 띠의 조건. `p`는 `periods`의 별칭이다.
    fn band_off_sql(&self, p: &str) -> Option<String> {
        let parts: Vec<String> = [
            self.row_off_sql(&format!("{p}.row")),
            in_list(&format!("({p}.look&31)"), &self.filter.kinds_off),
            in_list(&format!("(({p}.look>>8)&7)"), &self.filter.hist_off),
        ]
        .into_iter()
        .flatten()
        .collect();
        (!parts.is_empty()).then(|| format!("({})", parts.join(" OR ")))
    }

    /// 살아남는 띠만 고르는 `AND …`(거를 것이 없으면 빈 글).
    pub fn band_keep(&self, p: &str) -> String {
        self.band_off_sql(p).map(|cond| format!(" AND NOT {cond}")).unwrap_or_default()
    }

    /// 살아남는 줄만 고르는 `AND …`.
    pub fn row_keep(&self, row_expr: &str) -> String {
        self.row_off_sql(row_expr).map(|cond| format!(" AND NOT {cond}")).unwrap_or_default()
    }

    /// 살아남는 사건만 고르는 `AND …`. `e`는 `events`의 별칭이다.
    pub fn event_keep(&self, e: &str) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(cond) = self.row_off_sql(&format!("{e}.lane")) {
            parts.push(cond);
        }
        if let Some(cond) = in_list(&format!("({e}.look&255)"), &self.filter.cats_off) {
            parts.push(cond);
        }
        if self.filter.min_importance > 1 {
            parts.push(format!("{e}.importance<{}", self.filter.min_importance));
        }
        if let Some(cond) = self.band_off_sql("bp") {
            parts.push(format!("EXISTS(SELECT 1 FROM periods bp WHERE bp.id={e}.band AND {cond})"));
        }
        if parts.is_empty() { String::new() } else { format!(" AND NOT ({})", parts.join(" OR ")) }
    }
}

impl Store {
    /// 요청의 거르개를 이 저장소에 비추어 푼다. 거르개가 없거나 비었으면 `None`이다.
    pub fn filter_of(&self, q: &Value) -> Result<Option<Filtered>> {
        let Some(filter) = Filter::of(q)? else { return Ok(None) };
        let mut off_rows: HashSet<i64> = HashSet::new();
        if let Some(cond) = in_list("track", &filter.tracks_off) {
            let mut stmt = self.db.prepare(&format!("SELECT id FROM rows WHERE {cond}"))?;
            let mut rows = stmt.query([])?;
            while let Some(r) = rows.next()? {
                off_rows.insert(r.get(0)?);
            }
        }
        let mut off_bands: HashSet<i64> = HashSet::new();
        {
            let mut parts: Vec<String> = [in_list("(look&31)", &filter.kinds_off), in_list("((look>>8)&7)", &filter.hist_off)]
                .into_iter()
                .flatten()
                .collect();
            if !off_rows.is_empty() {
                // 꺼진 줄은 방금 모았다 — 번호로 바로 짚는 편이 트랙을 다시 잇는 것보다 짧다.
                let mut list: Vec<i64> = off_rows.iter().copied().collect();
                list.sort_unstable();
                parts.push(in_list("row", &list).unwrap_or_default());
            }
            if !parts.is_empty() {
                let mut stmt = self.db.prepare(&format!("SELECT id FROM periods WHERE {}", parts.join(" OR ")))?;
                let mut rows = stmt.query([])?;
                while let Some(r) = rows.next()? {
                    off_bands.insert(r.get(0)?);
                }
            }
        }
        Ok(Some(Filtered { filter, off_rows, off_bands }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn 빈_거르개와_없는_거르개는_모두_거르지_않는다() {
        assert_eq!(Filter::of(&json!({})).unwrap(), None);
        assert_eq!(Filter::of(&json!({"filter":{}})).unwrap(), None);
        assert_eq!(Filter::of(&json!({"filter":{"tracks_off":[],"min_importance":1}})).unwrap(), None);
    }

    #[test]
    fn 잘못된_거르개는_까닭과_함께_실패한다() {
        assert!(Filter::of(&json!({"filter":{"tracks_off":["가"]}})).is_err());
        assert!(Filter::of(&json!({"filter":{"cats_off":[-1]}})).is_err());
        assert!(Filter::of(&json!({"filter":{"min_importance":"셋"}})).is_err());
        assert!(Filter::of(&json!({"filter":{"min_importance":-2}})).is_err());
        assert!(Filter::of(&json!({"filter":[1,2]})).is_err());
        assert!(Filter::of(&json!({"filter":{"kinds_off":3}})).is_err());
    }

    #[test]
    fn 번호_목록은_오름차순에_중복이_없다() {
        let filter = Filter::of(&json!({"filter":{"kinds_off":[5,1,5,0]}})).unwrap().unwrap();
        assert_eq!(filter.kinds_off, vec![0, 1, 5]);
    }
}

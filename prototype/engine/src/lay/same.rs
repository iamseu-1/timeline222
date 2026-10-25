//! 정답지 견주기: 열쇠를 정렬해 견주어 차이 0이어야 같다('거의 같음'은 없다).
//! - 객체: 열쇠 차례는 무시(열쇠 합집합을 정렬해 차례로) · 배열: 차례대로, 길이가 다르면 `경로.length`도 알린다.
//! - 수: `as_f64()`로 값을 정확히 견준다(10과 10.0은 같다).
//! - `json` 열쇠에 든 JSON 글은 둘 다 `{` 또는 `[`로 시작하고 풀리면 풀어서 견준다(글 안의 열쇠 차례는 무시 — 바이트 견주기는 [`diff_json_text`]).
//! - 열쇠 `$oracle`(정답지 머리 — 시각 · 시간대 · 원본 지문)은 어느 깊이에서도 건너뛴다.
use serde_json::Value;

/// 두 JSON 값의 차이를 `"경로: 왼쪽 ≠ 오른쪽"` 꼴로 앞 `limit`개까지 돌려준다. 같으면 빈 목록.
/// 경로는 `a.b.0.c` 꼴(맨 위가 곧바로 다르면 `(루트)`) · 빠진 쪽은 `(없음)` · 값 글은 60자에서 자른다.
pub fn diff(a: &Value, b: &Value, limit: usize) -> Vec<String> {
    let mut out = Vec::new();
    walk(a, b, "", &mut out, limit);
    out
}

/// 값 글(JSON 한 줄)을 60자에서 자른다.
fn show(v: &Value) -> String {
    let text = v.to_string();
    if text.chars().count() <= 60 { text } else { format!("{}…", text.chars().take(60).collect::<String>()) }
}

fn join(path: &str, key: &str) -> String {
    if path.is_empty() { key.to_string() } else { format!("{path}.{key}") }
}

fn note(path: &str, left: String, right: String, out: &mut Vec<String>, limit: usize) {
    if out.len() < limit { out.push(format!("{}: {left} ≠ {right}", if path.is_empty() { "(루트)" } else { path })); }
}

/// `json` 열쇠 밑의 글이 JSON 글(`{`나 `[`로 시작)이고 풀리면 그 값.
fn json_text(v: &Value) -> Option<Value> {
    let text = v.as_str()?;
    if !(text.starts_with('{') || text.starts_with('[')) { return None; }
    serde_json::from_str(text).ok()
}

fn walk(a: &Value, b: &Value, path: &str, out: &mut Vec<String>, limit: usize) {
    if out.len() >= limit { return; }
    match (a, b) {
        (Value::Object(x), Value::Object(y)) => {
            let mut keys: Vec<&String> = x.keys().chain(y.keys()).filter(|k| k.as_str() != "$oracle").collect();
            keys.sort();
            keys.dedup();
            for key in keys {
                if out.len() >= limit { return; }
                let at = join(path, key);
                match (x.get(key), y.get(key)) {
                    (Some(l), Some(r)) => {
                        if key == "json" {
                            if let (Some(pl), Some(pr)) = (json_text(l), json_text(r)) { walk(&pl, &pr, &at, out, limit); continue; }
                        }
                        walk(l, r, &at, out, limit);
                    }
                    (Some(l), None) => note(&at, show(l), "(없음)".into(), out, limit),
                    (None, Some(r)) => note(&at, "(없음)".into(), show(r), out, limit),
                    (None, None) => {}
                }
            }
        }
        (Value::Array(x), Value::Array(y)) => {
            if x.len() != y.len() { note(&join(path, "length"), x.len().to_string(), y.len().to_string(), out, limit); }
            for (i, (l, r)) in x.iter().zip(y.iter()).enumerate() {
                if out.len() >= limit { return; }
                walk(l, r, &join(path, &i.to_string()), out, limit);
            }
        }
        (Value::Number(x), Value::Number(y)) => {
            if x.as_f64() != y.as_f64() { note(path, show(a), show(b), out, limit); }
        }
        _ => {
            if a != b { note(path, show(a), show(b), out, limit); }
        }
    }
}

/// `json` 열쇠의 글을 **바이트로** 견준다(과제 8-틀 고침 1회차 — 항목 기록의 `json` 글은 열쇠 차례 · 수 글까지 Node와 같아야 한다 · 계획 과제 13d).
/// [`diff`]가 0이어도 글이 다르면 그 자리(`entities.12.json(uid …)`)와 처음 다른 바이트의 자리 · 둘레를 알린다 — 앞 `limit`개까지. 같으면 빈 목록.
/// 짜임이 다른 곳(배열 길이 · 종류)은 [`diff`]의 몫이라 여기서는 지나친다 · `$oracle`은 건너뛴다.
pub fn diff_json_text(a: &Value, b: &Value, limit: usize) -> Vec<String> {
    let mut out = Vec::new();
    walk_json_text(a, b, "", &mut out, limit);
    out
}

fn walk_json_text(a: &Value, b: &Value, path: &str, out: &mut Vec<String>, limit: usize) {
    if out.len() >= limit { return; }
    match (a, b) {
        (Value::Object(x), Value::Object(y)) => {
            for (key, l) in x {
                if out.len() >= limit { return; }
                if key == "$oracle" { continue; }
                let Some(r) = y.get(key) else { continue };
                let at = join(path, key);
                if key == "json" {
                    if let (Value::String(sl), Value::String(sr)) = (l, r) {
                        if sl != sr {
                            let who = x.get("uid").and_then(Value::as_str).map(|u| format!("(uid {u})")).unwrap_or_default();
                            out.push(format!("{at}{who}: json 글이 다릅니다 — {}", first_diff(sl, sr)));
                        }
                        continue;
                    }
                }
                walk_json_text(l, r, &at, out, limit);
            }
        }
        (Value::Array(x), Value::Array(y)) => {
            for (i, (l, r)) in x.iter().zip(y.iter()).enumerate() {
                if out.len() >= limit { return; }
                walk_json_text(l, r, &join(path, &i.to_string()), out, limit);
            }
        }
        _ => {}
    }
}

/// 두 글의 처음 다른 바이트 자리와 그 둘레(앞뒤 60자).
fn first_diff(a: &str, b: &str) -> String {
    let (x, y) = (a.as_bytes(), b.as_bytes());
    let at = x.iter().zip(y.iter()).position(|(p, q)| p != q).unwrap_or(x.len().min(y.len()));
    let around = |s: &str| { let lo = s.floor_char_boundary(at.saturating_sub(60)); let hi = s.ceil_char_boundary((at + 60).min(s.len())); s[lo..hi].to_string() };
    format!("{at}바이트째(길이 왼쪽 {} · 오른쪽 {}) 왼쪽 …{}… / 오른쪽 …{}…", x.len(), y.len(), around(a), around(b))
}

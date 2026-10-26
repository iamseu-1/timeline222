//! P3 정답지 견주기(lay::same): 열쇠 차례는 무시 · 배열은 차례대로 · 수는 값으로 정확히 · json 열쇠의 JSON 글은 풀어서.
use archive_engine::lay::same::diff;
use serde_json::json;

#[test]
fn key_order_is_ignored_but_array_order_is_not() {
    assert!(diff(&json!({"a":1,"b":[1,2]}), &json!({"b":[1,2],"a":1}), 5).is_empty());
    assert_eq!(diff(&json!({"b":[1,2]}), &json!({"b":[2,1]}), 5), vec!["b.0: 1 ≠ 2", "b.1: 2 ≠ 1"]);
}
#[test]
fn numbers_compare_by_value() {
    assert!(diff(&json!({"x":10}), &serde_json::from_str::<serde_json::Value>(r#"{"x":10.0}"#).unwrap(), 5).is_empty());
    assert_eq!(diff(&json!({"x":0.1}), &json!({"x":0.1000000001}), 5).len(), 1);
}
/// 정답지의 수는 JS `Number(글)`과 비트까지 같게 읽혀야 한다(`serde_json`의 `float_roundtrip` 기능) — 기본 읽기는 이 수들에서 1 ULP 어긋난다.
#[test]
fn numbers_are_read_to_the_last_bit() {
    let cases: [(&str, f64); 4] = [
        ("936.0355191256831", 936.0355191256831_f64),
        ("1116.3306010928961", 1116.3306010928961_f64),
        ("1910.6575342465753", 1910.6575342465753_f64),
        ("1945.6191780821919", 1945.6191780821919_f64),
    ];
    for (text, want) in cases {
        let got = serde_json::from_str::<serde_json::Value>(text).unwrap().as_f64().unwrap();
        assert_eq!(got.to_bits(), want.to_bits(), "{text}: 읽은 값 {got:?} ≠ {want:?}");
    }
}
#[test]
fn json_text_under_json_key_is_parsed() {
    let a = json!({"entities":[{"uid":"u","json":"{\"a\":1,\"b\":2}"}]});
    let b = json!({"entities":[{"uid":"u","json":"{\"b\":2,\"a\":1}"}]});
    assert!(diff(&a, &b, 5).is_empty());
}
#[test]
fn missing_and_extra_keys_are_reported_with_path() {
    assert_eq!(diff(&json!({"t":[{"a":1}]}), &json!({"t":[{"a":1,"z":0}]}), 5), vec!["t.0.z: (없음) ≠ 0"]);
}
#[test]
fn limit_caps_the_report() {
    assert_eq!(diff(&json!([1,2,3,4]), &json!([5,6,7,8]), 2).len(), 2);
}

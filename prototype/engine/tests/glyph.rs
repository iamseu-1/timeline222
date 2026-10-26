// DirectWrite 글자 굽기(설계 3-2) — Windows에서만 돈다.
#![cfg(windows)]
use archive_engine::{archive_call, archive_free, archive_free_bytes, archive_glyphs, glyph};
use serde_json::{json, Value};
use std::ffi::{CStr, CString};

fn font() -> String {
    format!("{}/../app/assets/fonts/Pretendard-Bold.otf", env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn 한글은_clear_type_덮임으로_구워진다() {
    let out = glyph::bake(&json!({"font": font(), "size": 8.5, "glyphs": [{"rune": '임' as u32, "phase": 0}]})).unwrap();
    let g = glyph::parse(&out).unwrap();
    assert_eq!(g.len(), 1);
    assert!(g[0].ok && g[0].w > 0 && g[0].h > 0);
    assert_eq!(g[0].cov.len(), g[0].w as usize * g[0].h as usize * 3);
    // ClearType: 빨강 · 파랑 칸의 덮임이 크게 다른 화소가 있다(회색이면 셋이 같다)
    assert!(g[0].cov.chunks(3).any(|p| p[0].abs_diff(p[2]) > 30));
    // 바탕선 위로 솟는다(top < 0)
    assert!(g[0].top < 0);
}

#[test]
fn 부분_자리가_다르면_덮임도_다르다() {
    let out = glyph::bake(&json!({"font": font(), "size": 8.5, "glyphs": [{"rune": '임' as u32, "phase": 0}, {"rune": '임' as u32, "phase": 1}]})).unwrap();
    let g = glyph::parse(&out).unwrap();
    assert_ne!(g[0].cov, g[1].cov);
}

#[test]
fn 글꼴에_없는_글자는_ok가_거짓() {
    // 태국 글자 — 프리텐다드에 없다
    let out = glyph::bake(&json!({"font": font(), "size": 10.0, "glyphs": [{"rune": 0x0E01, "phase": 0}]})).unwrap();
    let g = glyph::parse(&out).unwrap();
    assert!(!g[0].ok && g[0].w == 0 && g[0].cov.is_empty());
}

#[test]
fn 없는_글꼴_파일은_까닭과_함께_실패() {
    let e = glyph::bake(&json!({"font": "C:/없는/글꼴.otf", "size": 10.0, "glyphs": []})).unwrap_err();
    assert!(e.to_string().contains("글꼴"));
}

#[test]
fn 설정을_읽는다() {
    let v = glyph::info();
    assert!(v["on"].is_boolean() && v["bgr"].is_boolean());
}

// ── 외부 길(FFI): `archive_glyphs` · `archive_call({"op":"cleartype"})` — `tests/blobs.rs`의 `archive_blob`과 같은 꼴로 겨눈다.
// 이 검사 파일은 따로 한 프로세스라 다른 검사 파일의 저장소와 겹치지 않는다. 다만 `LAST_ERROR`는 이 프로세스에서 함께 쓰므로,
// 실패 길의 검사(까닭 읽기)는 한 검사 안에서 차례로 한다 — 나눠 두면 둘이 동시에 돌며 서로의 까닭을 덮어쓴다.
/// `archive_call`에 JSON 한 줄을 보내고 답 JSON을 받는다(답 글은 `archive_free`로 놓는다).
fn ask(q: Value) -> Value {
    let input = CString::new(q.to_string()).unwrap();
    unsafe {
        let out = archive_call(input.as_ptr());
        let v: Value = serde_json::from_str(CStr::from_ptr(out).to_str().unwrap()).unwrap();
        archive_free(out);
        v
    }
}

#[test]
fn 외부_길로_구우면_바이트를_받고_놓는다() {
    let req = CString::new(json!({"font": font(), "size": 8.5, "glyphs": [{"rune": '임' as u32, "phase": 0}]}).to_string()).unwrap();
    unsafe {
        let mut len = 0usize;
        let ptr = archive_glyphs(req.as_ptr(), &mut len);
        assert!(!ptr.is_null() && len > 8, "구운 바이트와 길이를 돌려준다");
        let bytes = std::slice::from_raw_parts(ptr, len).to_vec();
        archive_free_bytes(ptr, len);
        assert_eq!(&bytes[0..4], b"HTGL");
        let g = glyph::parse(&bytes).unwrap();
        assert_eq!(g.len(), 1);
        assert!(g[0].rune == '임' as u32 && g[0].ok && g[0].w > 0 && g[0].h > 0);
        assert_eq!(g[0].cov.len(), g[0].w as usize * g[0].h as usize * 3);
    }
}

#[test]
fn 외부_길의_실패는_null과_길이_0과_까닭이다() {
    unsafe {
        // 없는 글꼴 — 길이가 0으로 되돌려지고 까닭은 last_error로 읽는다.
        let missing = CString::new(json!({"font": "C:/없는/글꼴.otf", "size": 10.0, "glyphs": []}).to_string()).unwrap();
        let mut len = 7usize;
        assert!(archive_glyphs(missing.as_ptr(), &mut len).is_null() && len == 0);
        let e = ask(json!({"op": "last_error"}));
        assert!(e["data"]["error"].as_str().unwrap().contains("글꼴"), "{e}");

        // 읽을 수 없는 요청 글 — 마찬가지로 null과 길이 0.
        let bad = CString::new("{").unwrap();
        len = 7;
        assert!(archive_glyphs(bad.as_ptr(), &mut len).is_null() && len == 0);

        // 빈 요청(null 글 · null 길이)은 멈추지 않고 null을 돌려준다. 길이 자리가 null이면 쓰지 않는다.
        len = 7;
        assert!(archive_glyphs(std::ptr::null(), &mut len).is_null() && len == 0);
        assert!(ask(json!({"op": "last_error"}))["data"]["error"].as_str().unwrap().contains("빈 요청"));
        let ok = CString::new(json!({"font": font(), "size": 10.0, "glyphs": []}).to_string()).unwrap();
        assert!(archive_glyphs(ok.as_ptr(), std::ptr::null_mut()).is_null());
        assert!(archive_glyphs(std::ptr::null(), std::ptr::null_mut()).is_null());
    }
}

#[test]
fn cleartype_명령은_저장소를_열지_않아도_답한다() {
    // 이 프로세스에는 열린 저장소가 없다 — 저장소가 필요한 명령은 거절된다(전제).
    let closed = ask(json!({"op": "probe"}));
    assert_eq!(closed["ok"], false);
    assert!(closed["error"].as_str().unwrap().contains("저장소가 열리지 않았습니다"), "{closed}");
    // 그래도 cleartype은 답한다: ok:true · data.on · data.bgr은 불리언.
    let v = ask(json!({"op": "cleartype"}));
    assert_eq!(v["ok"], true, "{v}");
    assert!(v["data"]["on"].is_boolean() && v["data"]["bgr"].is_boolean(), "{v}");
    // 직접 읽은 설정과 같다.
    assert_eq!(v["data"], glyph::info());
}

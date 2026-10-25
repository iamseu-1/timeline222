//! Windows 글자 굽기 — DirectWrite(크롬이 Windows에서 글자를 굽는 길)로 글자마다 ClearType 3x1 덮임을 만든다.
//! 설계 docs/설계-한벌-체제-목업판-ClearType.md 3-2 · 계획 docs/계획-한벌-P2-ClearType.md 과제 1(요청 · 답의 꼴).
//! 글꼴 얼굴은 스레드마다 한 번 열어 둔다(DirectWrite 객체를 스레드 사이로 넘기지 않으려고 thread_local).
use std::cell::RefCell;
use std::collections::HashMap;

use serde_json::{json, Value};
use windows::core::PCWSTR;
use windows::Win32::Graphics::DirectWrite::*;
use windows::Win32::UI::WindowsAndMessaging::{SystemParametersInfoW, SPI_GETFONTSMOOTHING, SPI_GETFONTSMOOTHINGORIENTATION, SPI_GETFONTSMOOTHINGTYPE, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS};

use crate::Result;

pub struct Baked { pub rune: u32, pub phase: u8, pub ok: bool, pub left: i16, pub top: i16, pub w: u16, pub h: u16, pub advance: f32, pub cov: Vec<u8> }

thread_local! {
    static FACTORY: RefCell<Option<IDWriteFactory>> = const { RefCell::new(None) };
    static FACES: RefCell<HashMap<String, IDWriteFontFace>> = RefCell::new(HashMap::new());
}

fn wide(s: &str) -> Vec<u16> { s.encode_utf16().chain(std::iter::once(0)).collect() }

fn factory() -> Result<IDWriteFactory> {
    FACTORY.with(|f| {
        if let Some(x) = f.borrow().as_ref() { return Ok(x.clone()); }
        let made: IDWriteFactory = unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED) }.map_err(|e| format!("DirectWrite를 열 수 없습니다: {e}"))?;
        *f.borrow_mut() = Some(made.clone());
        Ok(made)
    })
}

fn face(path: &str) -> Result<IDWriteFontFace> {
    if let Some(x) = FACES.with(|m| m.borrow().get(path).cloned()) { return Ok(x); }
    if !std::path::Path::new(path).is_file() { return Err(format!("글꼴 파일이 없습니다: {path}").into()); }
    let f = factory()?;
    let w = wide(path);
    let made = unsafe {
        let file = f.CreateFontFileReference(PCWSTR(w.as_ptr()), None).map_err(|e| format!("글꼴 파일을 열 수 없습니다({path}): {e}"))?;
        let kind = if path.to_ascii_lowercase().ends_with(".otf") { DWRITE_FONT_FACE_TYPE_CFF } else { DWRITE_FONT_FACE_TYPE_TRUETYPE };
        f.CreateFontFace(kind, &[Some(file)], 0, DWRITE_FONT_SIMULATIONS_NONE).map_err(|e| format!("글꼴 얼굴을 만들 수 없습니다({path}): {e}"))?
    };
    FACES.with(|m| m.borrow_mut().insert(path.to_owned(), made.clone()));
    Ok(made)
}

/// 요청(계획 과제 1의 꼴)을 굽는다.
pub fn bake(q: &Value) -> Result<Vec<u8>> {
    let path = q["font"].as_str().ok_or("글꼴 경로 누락")?;
    let size = q["size"].as_f64().ok_or("글자 크기 누락")? as f32;
    if !(size > 0.0 && size < 512.0) { return Err(format!("글자 크기가 범위 밖입니다: {size}").into()); }
    let mode = if q["mode"] == "natural" { DWRITE_RENDERING_MODE_NATURAL } else { DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC };
    let list = q["glyphs"].as_array().ok_or("글자 목록 누락")?;
    let ff = face(path)?;
    let f = factory()?;
    let mut fm = DWRITE_FONT_METRICS::default();
    unsafe { ff.GetMetrics(&mut fm) };
    let mut out = Vec::with_capacity(8 + list.len() * 64);
    out.extend_from_slice(b"HTGL");
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&(list.len() as u16).to_le_bytes());
    for one in list {
        let rune = one["rune"].as_u64().ok_or("글자 코드 누락")? as u32;
        let phase = (one["phase"].as_u64().unwrap_or(0) as u8).min(2);
        let mut index = 0u16;
        unsafe { ff.GetGlyphIndices(&rune, 1, &mut index) }.map_err(|e| format!("글자 번호를 얻을 수 없습니다: {e}"))?;
        let mut gm = DWRITE_GLYPH_METRICS::default();
        let mut advance = 0f32;
        let (mut left, mut top, mut w, mut h, mut cov) = (0i16, 0i16, 0u16, 0u16, Vec::new());
        let ok = index != 0;
        if ok {
            unsafe { ff.GetDesignGlyphMetrics(&index, 1, &mut gm, false) }.map_err(|e| format!("글자 치수를 얻을 수 없습니다: {e}"))?;
            advance = gm.advanceWidth as f32 * size / fm.designUnitsPerEm as f32;
            let run = DWRITE_GLYPH_RUN {
                fontFace: std::mem::ManuallyDrop::new(Some(ff.clone())),
                fontEmSize: size,
                glyphCount: 1,
                glyphIndices: &index,
                glyphAdvances: &advance,
                glyphOffsets: std::ptr::null(),
                isSideways: false.into(),
                bidiLevel: 0,
            };
            let analysis = unsafe { f.CreateGlyphRunAnalysis(&run, 1.0, None, mode, DWRITE_MEASURING_MODE_NATURAL, phase as f32 / 3.0, 0.0) }
                .map_err(|e| format!("글자를 굽지 못했습니다: {e}"))?;
            let r = unsafe { analysis.GetAlphaTextureBounds(DWRITE_TEXTURE_CLEARTYPE_3x1) }.map_err(|e| format!("글자 자리를 얻지 못했습니다: {e}"))?;
            if r.right > r.left && r.bottom > r.top {
                let (ww, hh) = (r.right - r.left, r.bottom - r.top);
                cov = vec![0u8; (ww * hh * 3) as usize];
                unsafe { analysis.CreateAlphaTexture(DWRITE_TEXTURE_CLEARTYPE_3x1, &r, &mut cov) }.map_err(|e| format!("덮임을 만들지 못했습니다: {e}"))?;
                (left, top, w, h) = (r.left as i16, r.top as i16, ww as u16, hh as u16);
            }
        }
        out.extend_from_slice(&rune.to_le_bytes());
        out.push(phase);
        out.push(ok as u8);
        out.extend_from_slice(&left.to_le_bytes());
        out.extend_from_slice(&top.to_le_bytes());
        out.extend_from_slice(&w.to_le_bytes());
        out.extend_from_slice(&h.to_le_bytes());
        out.extend_from_slice(&advance.to_le_bytes());
        out.extend_from_slice(&cov);
    }
    Ok(out)
}

/// 답 바이트를 읽는다(검사 · 도구용 — 앱은 Dart로 같은 꼴을 읽는다).
pub fn parse(b: &[u8]) -> Result<Vec<Baked>> {
    if b.len() < 8 || &b[0..4] != b"HTGL" { return Err("글자 답의 머리가 아닙니다".into()); }
    let n = u16::from_le_bytes([b[6], b[7]]) as usize;
    let mut p = 8;
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        if p + 18 > b.len() { return Err("글자 답이 잘렸습니다".into()); }
        let rune = u32::from_le_bytes(b[p..p + 4].try_into().unwrap());
        let (phase, ok) = (b[p + 4], b[p + 5] != 0);
        let left = i16::from_le_bytes([b[p + 6], b[p + 7]]);
        let top = i16::from_le_bytes([b[p + 8], b[p + 9]]);
        let w = u16::from_le_bytes([b[p + 10], b[p + 11]]);
        let h = u16::from_le_bytes([b[p + 12], b[p + 13]]);
        let advance = f32::from_le_bytes(b[p + 14..p + 18].try_into().unwrap());
        p += 18;
        let len = w as usize * h as usize * 3;
        if p + len > b.len() { return Err("글자 덮임이 잘렸습니다".into()); }
        out.push(Baked { rune, phase, ok, left, top, w, h, advance, cov: b[p..p + len].to_vec() });
        p += len;
    }
    Ok(out)
}

/// Windows의 글자 다듬기 설정: ClearType 켬(글자 다듬기 켬 + 종류가 ClearType) · 칸 차례(파초빨이면 bgr).
pub fn info() -> Value {
    unsafe {
        let (mut smooth, mut kind, mut orient) = (0i32, 0u32, 1u32);
        let none = SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0);
        let _ = SystemParametersInfoW(SPI_GETFONTSMOOTHING, 0, Some(&mut smooth as *mut _ as *mut _), none);
        let _ = SystemParametersInfoW(SPI_GETFONTSMOOTHINGTYPE, 0, Some(&mut kind as *mut _ as *mut _), none);
        let _ = SystemParametersInfoW(SPI_GETFONTSMOOTHINGORIENTATION, 0, Some(&mut orient as *mut _ as *mut _), none);
        // FE_FONTSMOOTHINGCLEARTYPE = 2 · FE_FONTSMOOTHINGORIENTATIONBGR = 0
        json!({"on": smooth != 0 && kind == 2, "bgr": orient == 0})
    }
}

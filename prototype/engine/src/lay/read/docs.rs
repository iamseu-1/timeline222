//! `js/core.js` 5074 ~ 5371줄 가운데 읽기가 쓰는 것 — 문서 키의 꼴 검사 · 문서 그림 사전 — 한 벌 P3 과제 5c.
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 5106 ~ 5111줄 `HT.docKey.split` · 5122 ~ 5125줄 `HT.docKey.valid`(정규식 `/\/\//`은 '글 안에 "//"가 있나'와 같은 뜻)
//! - 5332줄 `HT.PACK_LIMITS`의 문서 그림 한도(→ `read::vocab::PACK_LIMITS`) · 5336 ~ 5371줄 `HT.readImages`(그림 글 `COVER_RE`는 `read::info::cover_ok`)
//!
//! 옮기지 않은 것(뒤 과제 — 모델 · 문서 · 쓰기): `HT.docKey`의 나머지(`join` · `cell` · `parse` · `absolute` · `relative`) · `HT.unfoldDates` · 형식 버전 셈(`HT.NEW_FORMAT_KEYS` …) ·
//! `HT.packToJSON` · `HT.docImageOf` · `linkDocImages`.
use super::{dates, info, misc, vocab};
use crate::lay::js::{self, Obj, Str, V};

/// `HT.docKey.split(key)` — 문서 키 → (바탕 키, 하위 문서 이름): 처음 나온 "//"에서 나눈다(없으면 하위 문서 없음).
pub fn doc_key_split(key: &Str) -> (Str, Str) {
    let i = key.index_of16(&Str::from("//"), 0.0);
    if i < 0.0 { (key.clone(), Str::default()) } else { (key.slice16(0.0, i), key.slice16(i + 2.0, f64::INFINITY)) }
}
/// `HT.docKey.valid(key)` — 바탕 키가 비지 않고, "//"가 없고(나눈 바탕 키라 늘 참), 300자(UTF-16) 미만.
pub fn doc_key_valid(key: &Str) -> bool {
    let (base, _) = doc_key_split(key);
    !base.is_empty() && base.index_of16(&Str::from("//"), 0.0) < 0.0 && base.len16() < 300
}

/// `HT.readImages(list, report)` — 문서 그림 사전 `[{ id, name, src, caption?, alt?, credit?, width?, height? }]` 읽기: id(없으면 이름에서 'img-' + 해시) ·
/// 그림(src)이 없거나 틀리거나 한도를 넘으면 오류로 그 그림만 뺀다(합이 넘으면 뒤의 그림부터). width · height는 원본 그림의 픽셀 크기(1 ~ 20000의 정수).
pub fn read_images(list: &V, report: &mut dyn info::Report) -> Vec<V> {
    let l = &vocab::PACK_LIMITS;
    let s = dates::str_of;
    let mut out: Vec<Obj> = Vec::new();
    let mut total = 0usize;
    for (i, g) in dates::arr(list).iter().enumerate() {
        if !js::truthy(g) || !super::is_plain(g) { report.err(format!("문서 그림 #{}: 형식이 올바르지 않습니다.", i + 1), i); continue; }
        let name = s(&g.get("name"));
        let mut id = s(&g.get("id"));
        let shown = if name.is_empty() { id.clone() } else { name.clone() };
        let label = format!("문서 그림 #{}{}", i + 1, if shown.is_empty() { String::new() } else { format!(" \"{shown}\"") });
        if id.is_empty() && !name.is_empty() { id = super::cat(&[&Str::from("img-"), &misc::hash(&name)]); }
        if !dates::id_ok(&id) { report.err(format!("{label}: id가 비었거나 올바르지 않습니다."), i); continue; }
        if out.iter().any(|x| js::strict_eq(&x.get("id"), &V::Str(id.clone()))) { report.warn(format!("{label}: id \"{id}\"가 겹쳐 뒤의 것을 무시했습니다."), i); continue; }
        let src = match g.get("src") { V::Str(t) => t.trim(), _ => Str::default() };
        if src.is_empty() { report.err(format!("{label}: 그림(src)이 비어 있습니다."), i); continue; }
        if src.len16() > l.doc_image { report.err(format!("{label}: 그림이 너무 커서(data URL {}자 — 약 1.5MB 넘음) 뺐습니다.", l.doc_image), i); continue; }
        if !info::cover_ok(&src) { report.err(format!("{label}: 그림(src)이 png · jpeg · webp의 data URL이 아닙니다."), i); continue; }
        if total + src.len16() > l.doc_image_total { report.err(format!("{label}: 문서 그림을 모두 합친 크기가 한도(data URL {}자 — 약 15MB)를 넘어 뺐습니다.", l.doc_image_total), i); continue; }
        total += src.len16();
        if !name.is_empty() && out.iter().any(|x| js::strict_eq(&x.get("name"), &V::Str(name.clone()))) {
            report.warn(format!("{label}: 이름이 앞 그림과 같아 [[파일:{name}]]은 앞 그림을 가리킵니다 — 이 그림은 id({id})로 적으세요."), i);
        }
        let o = Obj::new();
        o.set("id", id.clone());
        o.set("name", if name.is_empty() { id } else { name });
        o.set("src", src);
        for (k, word) in [("caption", "설명"), ("alt", "대체 글"), ("credit", "출처")] {
            let v = s(&g.get(k));
            if v.is_empty() { continue; }
            if v.len16() > l.doc_image_text { report.warn(format!("{label}: {word}이(가) {}자를 넘어 뒤를 잘랐습니다.", l.doc_image_text), i); }
            o.set(k, v.slice16(0.0, l.doc_image_text as f64));
        }
        for (k, word) in [("width", "폭(width)"), ("height", "높이(height)")] {
            let x = g.get(k);
            if x.is_nullish() || super::is_empty_str(&x) { continue; }
            let n = js::to_num(&x);
            if n.is_finite() && n == n.trunc() && n > 0.0 && n <= 20000.0 { o.set(k, n); }
            else { report.warn(format!("{label}: {word} «{}»는 1~20000의 정수가 아니어서 뺐습니다.", js::to_str(&x)), i); }
        }
        out.push(o);
    }
    out.into_iter().map(V::Obj).collect()
}

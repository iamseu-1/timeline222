//! `HT.normalizePack` 안의 기관 · 문화 · 왕조 · 시대 — 4381 ~ 4551줄(과제 5b가 옮김 · 과제 5c 머리에 [`super`]에서 이 파일로 나눔 — 동작 그대로).
//!
//! 옮긴 원본: `js/core.js` — SHA-256 앞 12자 `9c786cf58566`(저장소의 LF 바이트)
//! - 4381 ~ 4472줄 `readOrgan`(정규식 `/조계|조차|…|倭館/`은 손으로 — `zone_word`) · `readCulture` · `readDynasty` · `checkPartOf`([`Norm`] 메서드)
//! - 4474 ~ 4551줄 시대(지도자 · 내각 · 연호 · 도읍 · 시기 · 지위 · 미정 · 이설 · 실재성 · 부분 승계) · 기관 · 문화 · 왕조 목록([`read_bands`])
//! (2026-10-24 맞춤 · 리메이크 3단계 과제 1 · `core.js` `7c75434e37fa`) 4658 ~ 4675줄 형식 4의 칸(type · status · importance — [`crate::lay::f4`]의 type_id · kind_of_type · type_of_kind · status_id) · 4693 ~ 4746줄 직위 줄 더(offices) · 두 자리의 빌림(leadersFrom · cabinetsFrom) · 실권(power — over 없이 이름만 = 제 안의 실권자)
use super::cell_lists::name_list;
use super::{apply_range, floor_text, list_of, Norm};
use crate::lay::js::{self, Obj, Str, V};
use crate::lay::f4;
use crate::lay::read::{self as read, cells, dates, misc, vocab};

impl<'c> Norm<'c> {
    /// `readOrgan(g, i, legacy)` — 기관: 주권 정권 위에 얹힌 외세 기관 · 특수 구역. 옛 형식(시대의 kind: "overlay")도 여기로 옮겨 읽는다.
    fn read_organ(&mut self, pack: &Obj, g: &V, i: usize, legacy: bool) {
        let ctx = self.ctx;
        let kind_key = if legacy { "periods" } else { "organs" };
        if !js::truthy(g) || !read::is_object(g) { self.err(format!("기관 #{}: 형식이 올바르지 않습니다.", i + 1), kind_key, Some(i)); return; }
        let name = dates::str_of(&js::nullish(g.get("name"), g.get("title")));
        let label = format!("기관 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { self.err(format!("{label}: 이름이 비어 있습니다."), kind_key, Some(i)); return; }
        let track = dates::str_of(&g.get("track"));
        if !self.check_track(&track, &label, kind_key, i) { return; }
        let Some(r) = self.read_range(g, &label, kind_key, i) else { return };
        let seed = read::cat(&[&track, &floor_text(r.start), &name]);
        let o = Obj::new();
        o.set("id", self.take_id(g, "g-", &seed, &label, kind_key, i));
        o.set("track", track);
        o.set("name", name.clone());
        apply_range(&o, &r);
        let mut msgs = Vec::new();
        let host = cells::read_part_of(ctx, &js::nullish(g.get("host"), g.get("partOf")), false, Some(&mut |m: String| msgs.push(m)));
        self.warn_all(msgs, &format!("{label}: 얹히는 정권 "), kind_key, i);
        if !host.is_empty() { o.set("host", cells::compact_part_of(host.clone())); }
        else { self.warn(format!("{label}: 얹히는 정권(host)이 없어 보통 띠로 그립니다."), kind_key, Some(i)); }
        self.warn_part_of_unknown(&host, &label, kind_key, i, "얹히는 정권", "기관의 기간 전체에");
        for (k, v) in self.read_uncertainty(g, &label, kind_key, i, r.start).entries() { o.set(&k, v); }
        // 크기: agency(기관 — 시대 띠 안 맨 아래의 기관 칸) · zone(조계지 · 조차지 같은 구역 — 띠 아래로 내려오는 탭). 없으면 이름으로 짐작
        let scale = dates::str_of(&g.get("scale"));
        if scale == "zone" || scale == "agency" { o.set("scale", scale); }
        else if zone_word(&name).is_some() { o.set("scale", "zone"); } // 왜관도 구역(묶음 3 · 3번)
        if misc::is_color(&g.get("color")) { o.set("color", g.get("color")); }
        for k in ["description", "note"] {
            let t = dates::str_of(&g.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !dates::str_of(&g.get("wiki")).is_empty() { o.set("wiki", js::to_str(&g.get("wiki"))); }
        list_of(pack, "organs").push(V::Obj(o));
    }
    /// `readCulture(c, i, legacy)` — 문화: 국가 이전의 고고학 문화. 승계한 국가(successors, 또는 국가 쪽의 succeeds)가 있으면 그 줄 밑에 바탕 띠로 깔린다.
    fn read_culture(&mut self, pack: &Obj, c: &V, i: usize, legacy: bool) {
        let kind_key = if legacy { "periods" } else { "cultures" };
        if !js::truthy(c) || !read::is_object(c) { self.err(format!("문화 #{}: 형식이 올바르지 않습니다.", i + 1), kind_key, Some(i)); return; }
        let name = dates::str_of(&js::nullish(c.get("name"), c.get("title")));
        let label = format!("문화 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { self.err(format!("{label}: 이름이 비어 있습니다."), kind_key, Some(i)); return; }
        let track = dates::str_of(&c.get("track"));
        if !self.check_track(&track, &label, kind_key, i) { return; }
        let Some(r) = self.read_range(c, &label, kind_key, i) else { return };
        let seed = read::cat(&[&track, &floor_text(r.start), &name]);
        let o = Obj::new();
        o.set("id", self.take_id(c, "c-", &seed, &label, kind_key, i));
        o.set("track", track);
        o.set("name", name);
        apply_range(&o, &r);
        for (k, v) in self.read_uncertainty(c, &label, kind_key, i, r.start).entries() { o.set(&k, v); }
        let succ_raw: Vec<V> = match c.get("successors") { V::Arr(a) => a.to_vec(), x => read::split_units(&dates::str_of(&x), &[0x2C]).into_iter().map(V::Str).collect() };
        let succ: Vec<V> = succ_raw.iter().map(dates::str_of).filter(|x| !x.is_empty()).map(V::Str).collect();
        if !succ.is_empty() { o.set("successors", read::arr_of(succ)); }
        let pre: Vec<V> = dates::arr(&c.get("succeeds"))
            .iter()
            .map(|x| if matches!(x, V::Str(_)) { let f = Obj::new(); f.set("from", x.clone()); V::Obj(f) } else { js::or(x.clone(), V::Obj(Obj::new())) })
            .map(|x| {
                let f = Obj::new();
                f.set("from", dates::str_of(&x.get("from")));
                f.set("type", if dates::str_of(&x.get("type")) == "direct" { "direct" } else { "indirect" });
                f
            })
            .filter(|x| x.str("from").is_some_and(|s| !s.is_empty()))
            .map(V::Obj)
            .collect();
        if !pre.is_empty() { o.set("succeeds", read::arr_of(pre)); }
        let people = dates::str_of(&c.get("people"));
        if !people.is_empty() { o.set("people", people); }
        if misc::is_color(&c.get("color")) { o.set("color", c.get("color")); }
        let description = dates::str_of(&c.get("description"));
        if !description.is_empty() { o.set("description", description); }
        if !dates::str_of(&c.get("wiki")).is_empty() { o.set("wiki", js::to_str(&c.get("wiki"))); }
        list_of(pack, "cultures").push(V::Obj(o));
    }
    /// `readDynasty(d, i, legacy)` — 왕조: 나라(국체)를 다스린 왕가. polities(다스린 정권 — 기간을 적으면 그 구간만)의 시대 띠 맨 위 왕조 칸에 그린다.
    fn read_dynasty(&mut self, pack: &Obj, d: &V, i: usize, legacy: bool) {
        let ctx = self.ctx;
        let kind_key = if legacy { "periods" } else { "dynasties" };
        if !js::truthy(d) || !read::is_object(d) { self.err(format!("왕조 #{}: 형식이 올바르지 않습니다.", i + 1), kind_key, Some(i)); return; }
        let name = dates::str_of(&js::nullish(d.get("name"), d.get("title")));
        let label = format!("왕조 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { self.err(format!("{label}: 이름이 비어 있습니다."), kind_key, Some(i)); return; }
        let track = dates::str_of(&d.get("track"));
        if !self.check_track(&track, &label, kind_key, i) { return; }
        let Some(r) = self.read_range(d, &label, kind_key, i) else { return };
        let seed = read::cat(&[&track, &floor_text(r.start), &name]);
        let o = Obj::new();
        o.set("id", self.take_id(d, "y-", &seed, &label, kind_key, i));
        o.set("track", track);
        o.set("name", name);
        apply_range(&o, &r);
        let mut msgs = Vec::new();
        let ruled_v = js::nullish(js::nullish(js::nullish(d.get("polities"), d.get("rules")), d.get("host")), d.get("partOf"));
        let ruled = cells::read_part_of(ctx, &ruled_v, false, Some(&mut |m: String| msgs.push(m)));
        self.warn_all(msgs, &format!("{label}: 다스린 정권 "), kind_key, i);
        if !ruled.is_empty() { o.set("polities", cells::compact_part_of(ruled.clone())); }
        else { self.warn(format!("{label}: 다스린 정권(polities)이 없어 연표의 시대 띠에는 그려지지 않습니다."), kind_key, Some(i)); }
        self.warn_part_of_unknown(&ruled, &label, kind_key, i, "다스린 정권", "왕조의 기간 전체에");
        for (k, v) in self.read_uncertainty(d, &label, kind_key, i, r.start).entries() { o.set(&k, v); }
        let house = dates::str_of(&d.get("house"));
        if !house.is_empty() { o.set("house", house); }
        if misc::is_color(&d.get("color")) { o.set("color", d.get("color")); }
        for k in ["description", "note"] {
            let t = dates::str_of(&d.get(k));
            if !t.is_empty() { o.set(k, t); }
        }
        if !dates::str_of(&d.get("wiki")).is_empty() { o.set("wiki", js::to_str(&d.get("wiki"))); }
        self.put_names(&o, &d.get("names"), &label, kind_key, i); // 이름 목록 (형식 버전 3)
        list_of(pack, "dynasties").push(V::Obj(o));
    }
    /// `checkPartOf(v, label, where, i)` — 소속 관계 · 놓는 자리 검사: 모르는 관계와 true/false가 아닌 nest는 버리고 알린다.
    pub(super) fn check_part_of(&mut self, v: &V, label: &str, place: &str, i: usize) {
        let items = match v { V::Arr(a) => a.to_vec(), x => vec![x.clone()] };
        for x in items {
            if !js::truthy(&x) || !read::is_object(&x) { continue; }
            let relation = dates::str_of(&x.get("relation"));
            if !relation.is_empty() && vocab::relation_id(&x.get("relation")).is_empty() { self.warn(format!("{label}: 소속 관계 \"{relation}\"을(를) 알 수 없어 무시했습니다."), place, Some(i)); }
            let nest = x.get("nest");
            if !nest.is_nullish() && !read::is_empty_str(&nest) && !matches!(nest, V::Bool(_)) {
                self.warn(format!("{label}: 놓는 자리(nest)는 true나 false로 적습니다 — \"{}\"은(는) 무시했습니다.", dates::str_of(&nest)), place, Some(i));
            }
        }
    }
}

/// `/조계|조차|租界|租借|거류지|居留地|공사관 ?구역|특구|왜관|倭館/`(기관의 크기 짐작)을 손으로 — 맞은 갈래의 글(가장 왼쪽에서 맞은 것 · 같은 자리면 앞 갈래)을 돌려준다.
/// 갈래가 모두 고정 글이라 '글 안에 들었나'와 뜻이 같다(`공사관 ?구역`은 '공사관구역' · '공사관 구역' 둘).
fn zone_word(name: &Str) -> Option<&'static str> {
    const WORDS: [&str; 11] = ["조계", "조차", "租界", "租借", "거류지", "居留地", "공사관 구역", "공사관구역", "특구", "왜관", "倭館"];
    let mut best: Option<(f64, &'static str)> = None;
    for w in WORDS {
        let at = name.index_of16(&Str::from(w), 0.0);
        if at >= 0.0 && best.is_none_or(|(b, _)| at < b) { best = Some((at, w)); }
    }
    best.map(|(_, w)| w)
}

/// 4474 ~ 4551줄 — 시대 목록(옛 형식 overlay · culture · dynasty는 기관 · 문화 · 왕조로) 뒤 기관 · 문화 · 왕조 목록. `normalize_pack`이 간지 · 문서 그림 다음에 부른다.
pub(super) fn read_bands(n: &mut Norm, pack: &Obj, raw: &V) {
    let ctx = n.ctx;
    let list = |k: &str| list_of(pack, k);
    // (readOrgan · readCulture · readDynasty · checkPartOf — 위 Norm의 메서드)
    for (i, p) in dates::arr(&raw.get("periods")).iter().enumerate() {
        if !js::truthy(p) || !read::is_object(p) { n.err(format!("시대 #{}: 형식이 올바르지 않습니다.", i + 1), "periods", Some(i)); continue; }
        let legacy_kind = dates::str_of(&p.get("kind"));
        if legacy_kind == "overlay" {
            let g = read::assign_copy(p);
            g.set("host", js::nullish(p.get("host"), p.get("partOf")));
            n.read_organ(&pack, &V::Obj(g), i, true);
            continue;
        }
        if legacy_kind == "culture" { n.read_culture(&pack, p, i, true); continue; }
        if legacy_kind == "dynasty" {
            let d = read::assign_copy(p);
            d.set("polities", js::nullish(p.get("polities"), p.get("partOf")));
            n.read_dynasty(&pack, &V::Obj(d), i, true);
            continue;
        }
        let name = dates::str_of(&js::nullish(p.get("name"), p.get("title")));
        let label = format!("시대 #{}{}", i + 1, if name.is_empty() { String::new() } else { format!(" \"{name}\"") });
        if name.is_empty() { n.err(format!("{label}: 이름이 비어 있습니다."), "periods", Some(i)); continue; }
        let track = dates::str_of(&p.get("track"));
        if !n.check_track(&track, &label, "periods", i) { continue; }
        let Some(r) = n.read_range(p, &label, "periods", i) else { continue };
        let seed = read::cat(&[&track, &floor_text(r.start), &name]);
        let o = Obj::new();
        o.set("id", n.take_id(p, "p-", &seed, &label, "periods", i));
        o.set("track", track);
        o.set("name", name);
        apply_range(&o, &r);
        let kind = { let k = vocab::polity_kind_id(&p.get("kind")); if k.is_empty() { dates::str_of(&p.get("kind")) } else { k } }; // 한국어 이름("괴뢰국")도 읽는다
        if !kind.is_empty() && kind != "state" {
            if vocab::POLITY_KINDS.iter().any(|k| kind == k.id) { o.set("kind", kind); }
            else { n.warn(format!("{label}: 정권 종류 \"{kind}\"을(를) 알 수 없어 국가로 봅니다."), "periods", Some(i)); }
        }
        // 형식 4의 칸(5단계 과제 3 — 메이커의 객체 표): 객체 종류 type(열여덟 — 사람은 인물 목록) · 정통성 status · 중요도 importance.
        // 옛 종류(kind)와 나란히 둔다 — type은 다리가 옛 종류로 되살릴 수 없는 종류(도시 · 나라 · 동군연합 · 동맹 · 실권 정권 · 교단 · 기사단 · 회사 · 직위)일 때만 적힌다
        let otype = f4::type_id(&p.get("type"));
        if !otype.is_empty() && otype != "state" && otype != "person" {
            let k = f4::kind_of_type(&V::Str(otype.clone()));
            if !js::truthy(&o.get("kind")) && k != "state" { o.set("kind", k); } // 옛 종류를 비우고 객체 종류만 적은 항목은 옛 종류로 풀어 지금 화면이 그 띠로 그림
            let now = if js::truthy(&o.get("kind")) { o.get("kind") } else { V::from("state") };
            if otype != f4::type_of_kind(&now) { o.set("type", otype.clone()); }
        } else if !dates::str_of(&p.get("type")).is_empty() && otype.is_empty() {
            n.warn(format!("{label}: 객체 종류 \"{}\"을(를) 알 수 없어 옛 종류대로 봅니다.", dates::str_of(&p.get("type"))), "periods", Some(i));
        } else if otype == "person" {
            n.warn(format!("{label}: 사람은 인물 목록에 적습니다 — 옛 종류대로 봅니다."), "periods", Some(i));
        }
        let ostatus = f4::status_id(&p.get("status"));
        if !ostatus.is_empty() { o.set("status", ostatus); }
        else if !dates::str_of(&p.get("status")).is_empty() {
            n.warn(format!("{label}: 정통성 \"{}\"을(를) 알 수 없어 뺐습니다(정통 · 대립 · 공동 · 섭정 · 명목 · 주장).", dates::str_of(&p.get("status"))), "periods", Some(i));
        }
        {
            let imp = p.get("importance");
            if !imp.is_nullish() && !read::is_empty_str(&imp) {
                let x = js::to_num(&imp);
                if [0.0, 1.0, 2.0, 3.0].contains(&x) { o.set("importance", x); }
                else { n.warn(format!("{label}: 중요도는 0~3이어야 해서 뺐습니다(비우면 기간 길이로 짐작)."), "periods", Some(i)); }
            }
        }
        let mut msgs = Vec::new();
        let part_of = cells::read_part_of(ctx, &p.get("partOf"), true, Some(&mut |m: String| msgs.push(m)));
        n.warn_all(msgs, &format!("{label}: 소속 "), "periods", i);
        if !part_of.is_empty() { o.set("partOf", cells::compact_part_of(part_of.clone())); }
        // 소속 관계 · 놓는 자리 검사: 모르는 관계 · 잘못 적은 nest는 버리고 알린다. 접기(nest: true)는 상위 정권이 하나이고 기간이 없을 때만 된다
        // (기간의 한쪽이라도 "미정"이면 기간이 있는 것 — 모델의 singleHost와 같은 조건)
        n.check_part_of(&p.get("partOf"), &label, "periods", i);
        if part_of.iter().any(|x| matches!(x.get("nest"), V::Bool(true)))
            && (part_of.len() > 1 || !part_of[0].get("start").is_nullish() || !part_of[0].get("end").is_nullish() || part_of[0].bool("startUnknown") || part_of[0].bool("endUnknown"))
        {
            n.warn(format!("{label}: 상위 띠 아래에 접기(nest)는 상위 정권이 하나이고 기간을 적지 않았을 때만 됩니다 — 제 줄에 놓입니다."), "periods", Some(i));
        }
        n.warn_part_of_unknown(&part_of, &label, "periods", i, "소속", "앞뒤 소속의 기간이나 정권의 기간에 맞춰");
        if !dates::str_of(&p.get("wiki")).is_empty() { o.set("wiki", js::to_str(&p.get("wiki"))); }
        for (k, v) in n.read_uncertainty(p, &label, "periods", i, r.start).entries() { o.set(&k, v); }
        // 실재성(8-4 마): 한국어도 읽고, 실재(attested)는 기본값이라 적지 않는다
        let hs = vocab::historicity(&p.get("historicity"));
        if !hs.is_empty() && hs != "attested" { o.set("historicity", hs); }
        else if hs.is_empty() && !dates::str_of(&p.get("historicity")).is_empty() {
            n.warn(format!("{label}: 실재성 \"{}\"을(를) 알 수 없어 실재로 봅니다.", dates::str_of(&p.get("historicity"))), "periods", Some(i));
        }
        let hs_note = dates::str_of(&p.get("historicityNote"));
        if !hs_note.is_empty() { o.set("historicityNote", hs_note); }
        let leaders = n.read_cells(&js::or(p.get("leaders"), p.get("reigns")), &label, "periods", i, "지도자");
        if !leaders.is_empty() { o.set("leaders", read::arr_of(leaders)); }
        let cabinets = n.read_cells(&p.get("cabinets"), &label, "periods", i, "내각");
        if !cabinets.is_empty() { o.set("cabinets", read::arr_of(cabinets)); }
        // 형식 4의 직위 줄(5단계 과제 4): 지도자 · 내각 자리 밖의 줄(offices — 이름 + 칸, 또는 빌림 from) · 두 자리의 빌림(leadersFrom · cabinetsFrom — { from, name? }) ·
        // 실권(power — 쥔 쪽에만 적고 over가 빼앗긴 상대 객체 · over 없이 이름만 = 제 안의 실권자). 모델은 읽지 않는다 — 다리(HT.F4)가 올리고 내린다
        let mut offices: Vec<V> = Vec::new();
        for (j, f) in dates::arr(&p.get("offices")).iter().enumerate() {
            if !matches!(f, V::Obj(_)) { n.warn(format!("{label}: 직위 줄 더 {}번째: 형식이 올바르지 않습니다.", j + 1), "periods", Some(i)); continue; }
            let name = dates::str_of(&f.get("name"));
            let from = dates::str_of(&f.get("from"));
            if name.is_empty() && from.is_empty() { n.warn(format!("{label}: 직위 줄 더 {}번째: 이름이 없습니다.", j + 1), "periods", Some(i)); continue; }
            if !from.is_empty() {
                if !dates::arr(&f.get("cells")).is_empty() {
                    n.warn(format!("{label}: 직위 줄 \"{}\"에 빌림(from)과 칸이 함께 있어 빌림만 씁니다.", if name.is_empty() { &from } else { &name }), "periods", Some(i));
                }
                let x = Obj::new();
                if !name.is_empty() { x.set("name", name); }
                x.set("from", from);
                offices.push(V::Obj(x));
                continue;
            }
            let cells = n.read_cells(&f.get("cells"), &label, "periods", i, &format!("직위 줄 \"{name}\""));
            let x = Obj::new();
            x.set("name", name);
            x.set("cells", read::arr_of(cells));
            offices.push(V::Obj(x));
        }
        if !offices.is_empty() { o.set("offices", read::arr_of(offices)); }
        for (k, word) in [("leadersFrom", "지도자"), ("cabinetsFrom", "내각")] {
            let v = p.get(k);
            if v.is_nullish() || read::is_empty_str(&v) { continue; }
            let from = dates::str_of(&if matches!(v, V::Str(_)) { v.clone() } else if js::truthy(&v) { v.get("from") } else { v.clone() });
            if from.is_empty() {
                n.warn(format!("{label}: {word} 줄의 빌림({k})에 출처가 없어 뺐습니다 — \"객체 id\" 또는 \"객체 id/직위 이름\"."), "periods", Some(i));
                continue;
            }
            let b = Obj::new();
            let nm = if matches!(v, V::Obj(_) | V::Arr(_)) { dates::str_of(&v.get("name")) } else { Str::default() };
            if !nm.is_empty() && nm != word { b.set("name", nm); }
            b.set("from", from);
            o.set(k, V::Obj(b));
        }
        let mut power: Vec<V> = Vec::new();
        for (j, c) in dates::arr(&p.get("power")).iter().enumerate() {
            let x = match c {
                V::Arr(a) => { let t = Obj::new(); for (q, k) in ["name", "start", "end", "note"].iter().enumerate() { t.set(*k, a.to_vec().get(q).cloned().unwrap_or(V::Undef)); } V::Obj(t) }
                V::Obj(_) => c.clone(),
                _ => { n.warn(format!("{label}: 실권 {}번째 줄: 형식이 올바르지 않습니다.", j + 1), "periods", Some(i)); continue; }
            };
            let over = dates::str_of(&x.get("over"));
            // 상대(over) 없이 이름만 = 제 안의 실권자(세도 가문 · 권신 · 환관 — 쥔 쪽이 객체가 아닐 때 빼앗긴 쪽에 이름 글로 · 프롬프트 판 2 '실권' 9 · 2026-10-24)
            if over.is_empty() && dates::str_of(&x.get("name")).is_empty() {
                n.warn(format!("{label}: 실권 {}번째 줄: 상대(over)도 이름도 없어 뺐습니다 — 남의 실권은 쥔 쪽에 over로, 제 안의 실권자(세도 가문 · 권신)는 이름으로 적습니다.", j + 1), "periods", Some(i));
                continue;
            }
            let w = Obj::new();
            let nm = dates::str_of(&x.get("name"));
            if !nm.is_empty() { w.set("name", nm); }
            if !over.is_empty() { w.set("over", over); }
            for edge in ["start", "end"] {
                match cells::read_cell_edge(ctx, &x, edge) {
                    None => {}
                    Some(cells::Edge::Unknown(t)) => {
                        if let Some(t) = t { w.set(edge, t); }
                        w.set(&format!("{edge}Unknown"), true);
                    }
                    Some(cells::Edge::Date(d)) => {
                        if !d.t.is_nan() {
                            w.set(edge, d.t);
                            if let Some(at) = d.at.filter(|a| !a.is_empty()) { w.set(&format!("{edge}At"), at); }
                        } else {
                            n.warn(format!("{label}: 실권 {}번째 줄: {} 연도가 올바르지 않습니다.", j + 1, if edge == "start" { "시작" } else { "끝" }), "periods", Some(i));
                        }
                    }
                }
            }
            let note = dates::str_of(&x.get("note"));
            if !note.is_empty() { w.set("note", note); }
            power.push(V::Obj(w));
        }
        if !power.is_empty() { o.set("power", read::arr_of(power)); }
        let people = dates::str_of(&p.get("people"));
        if !people.is_empty() { o.set("people", people); }
        let house = dates::str_of(&p.get("house"));
        if !house.is_empty() { o.set("house", house); } // 국성: 나라를 다스린 가문(가문의 id나 이름) — 가문을 적지 않은 지도자는 이 가문으로 본다
        let succ = n.read_succ_list(&p.get("succeeds"), &label, "periods", i);
        if !succ.is_empty() { o.set("succeeds", read::arr_of(succ)); }
        let eras = n.read_cells(&p.get("eras"), &label, "periods", i, "연호");
        if !eras.is_empty() { o.set("eras", read::arr_of(eras)); }
        let capitals = n.read_capitals(&p.get("capitals"), &label, "periods", i);
        if !capitals.is_empty() { o.set("capitals", read::arr_of(capitals)); }
        // 정권 기간의 두 끝 `lo` · `hi`(원본은 시기 · 지위 덩어리마다 그 안에서 같은 식으로 셈 — 목록이 있을 때만): 시작이 미정이면 아래 끝 없음, 끝이 미정 · 진행 중이면 위 끝 없음.
        // `[c.start, c.end].some(t => t != null && (t < lo || t > hi))` — 기간이 그 밖으로 나가는 칸인가
        let outside = |x: &V| {
            let lo = if r.start_unknown { f64::NEG_INFINITY } else { r.start - 1e-9 };
            let hi = if r.end_unknown || r.ongoing { f64::INFINITY } else {
                let (e, at) = match r.end { Some(e) => (e, r.end_at.clone()), None => (r.start, r.start_at.clone()) };
                dates::end_bound_t(ctx, e, &at.map_or(V::Null, V::Str)) + 1e-9
            };
            ["start", "end"].iter().any(|k| { let t = x.get(*k); !t.is_nullish() && (js::to_num(&t) < lo || js::to_num(&t) > hi) })
        };
        // 시기 구분(학계): 체계 목록으로 정리(납작한 꼴도 체계별로 묶음) · 겹침과 정권 기간 밖의 시기는 알림
        let phases = cells::read_phases(ctx, &p.get("phases"));
        for msg in phases.problems.iter().chain(phases.warnings.iter()) { n.warn(format!("{label}: {msg}"), "periods", Some(i)); }
        if !phases.list.is_empty() {
            let spans: Vec<V> = phases.list.iter().flat_map(|g| g.arr("spans").map(|a| a.to_vec()).unwrap_or_default()).collect();
            o.set("phases", read::arr_of(phases.list));
            if let Some(out) = spans.iter().find(|sp| outside(sp)) {
                n.warn(format!("{label}: 시기 구분의 시기 \"{}\"이(가) 정권 기간 밖으로 나갑니다 — 띠 안에는 정권 기간까지만 그립니다.", js::to_str(&out.get("name"))), "periods", Some(i));
            }
        }
        // 지위 변천: 칸 목록(이름 기준 — rank도 읽음) · 시작을 비울 수 있는 것은 첫 칸뿐 · 겹침과 정권 기간 밖의 지위는 알림
        let ranks = cells::read_ranks(ctx, &p.get("ranks"));
        for msg in ranks.problems.iter().chain(ranks.warnings.iter()) { n.warn(format!("{label}: {msg}"), "periods", Some(i)); }
        if !ranks.list.is_empty() {
            let found = ranks.list.iter().find(|c| outside(c)).map(|c| js::to_str(&c.get("name")));
            o.set("ranks", read::arr_of(ranks.list));
            if let Some(name) = found { n.warn(format!("{label}: 지위 \"{name}\"의 기간이 정권 기간 밖으로 나갑니다 — 띠 안에는 정권 기간까지만 그립니다."), "periods", Some(i)); }
        }
        if misc::is_color(&p.get("color")) { o.set("color", p.get("color")); }
        let description = dates::str_of(&p.get("description"));
        if !description.is_empty() { o.set("description", description); }
        n.put_names(&o, &p.get("names"), &label, "periods", i); // 이름 목록 — 원어 · 로마자 · 국호 변천(start · end) (형식 버전 3)
        let ptags = name_list(&p.get("tags")); // 승계표 머리 끝의 꼬리표(형식 버전 3 — 사건의 tags와 같은 읽기)
        if !ptags.is_empty() { o.set("tags", read::arr_of(ptags.into_iter().map(V::Str).collect())); }
        match misc::read_north_south(&p.get("northSouth")) { // 남북 위치(형식 버전 3 — 민족의 배열 기준 '북 → 남'이 씀 · 클수록 북)
            Some(ns) if ns.is_finite() => o.set("northSouth", ns),
            Some(_) => n.warn(format!("{label}: 남북 위치(northSouth)는 수여야 해서 뺐습니다 — 클수록 북 (비우면 첫 정도의 지명 좌표)."), "periods", Some(i)),
            None => {}
        }
        list("periods").push(V::Obj(o));
    }
    for (i, g) in dates::arr(&raw.get("organs")).iter().enumerate() { n.read_organ(&pack, g, i, false); }
    for (i, c) in dates::arr(&raw.get("cultures")).iter().enumerate() { n.read_culture(&pack, c, i, false); }
    for (i, d) in dates::arr(&raw.get("dynasties")).iter().enumerate() { n.read_dynasty(&pack, d, i, false); }
}

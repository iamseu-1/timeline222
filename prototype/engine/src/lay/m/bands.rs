//! 내보내기 모듈 `bands` — 정권 띠. 2단계의 값(자리 · 기간 · 색 · 이름)에서 출발해 그 모습(계약 6절의 look · tag · sub)을 더한다. 한 벌 P3 과제 9(갈래 A) — 줄 그대로 옮긴다.
//! 모습은 지금 연표 `_drawTrack`이 띠에 붙이는 클래스(kind-* · 확실성 · 연대 폭 · 실재성 · 종속 갈래 · 깃대 · 망명 · 바탕 문화)와 책갈피 탭의 딱지(tabParts)를 비트로 옮긴 것 —
//! 화면에 달린 값(잘림 · 조명 · 흐림)은 싣지 않는다.
//!
//! 옮긴 원본:
//! - `prototype/scripts/export/bands.mjs` 1 ~ 139줄 — SHA-256 앞 12자 `96aa9d433cdd`(저장소의 LF 바이트) → [`KIND_NO`] · [`contribute`]
//!   (2026-10-24 맞춤 · 리메이크 3단계 과제 3 ~ 6 · 계약 1-1 초안) 23 ~ 48줄 띠의 form(`TYPE_NO` · `REL_NO` · `STATUS_NO` · `DRAWN_ONLY` · `formOf` → [`TYPE_NO`] · [`REL_NO`] · [`form_of`]) · 78 · 115줄 `form`을 띠에 실음
//!
//! 쓰는 shared: `bandOf`(띠의 uid → `out.periods`의 순번 — strips · events · hangs · figures · links · power · variants · lens가 읽는다). 읽는 out: `periods.length`(순번).
//! 부르는 웹 함수: `tl._hosted`(`ctx::set_scopes`가 둔 Map) · `HT.historicityOf` · `HT.historicityTag`(→ [`crate::lay::web::words`] — 과제 Y가 모음 · 처음 옮긴 판은
//! 이 파일에 있었다) · `HT.kindFamily` · `HT.POLITY_KINDS`(`read::vocab`).
//! 종류 · 확실성 · 실재성 번호 표를 JS 객체 열쇠로 찾는 곳(`KIND_NO[kind]` …)의 값은 늘 읽기가 고른 id(`HT.kindOf` · `certaintyOf` · `historicity`)라
//! `Object.prototype`의 속성 이름(`toString` …)이 열쇠로 오는 일은 없다 — 모르는 열쇠는 원본의 `??` 기본값.
use crate::lay::ctx::Ctx;
use crate::lay::export::{arr_len, arr_mut, color, jsv, jv, minute_v};
use crate::lay::js::{self, Map, V};
use crate::lay::model::o;
use crate::lay::model::util::{arr, le, list, lt, n, or, s, t, tv};
use crate::lay::read::vocab::{self, POLITY_KINDS};
use crate::lay::rows::join;
use crate::lay::web::words::{historicity_of, historicity_tag, inherited};
use crate::lay::f4;
use serde_json::{json, Value};

/// 옮겼는가 — `lay::MODULES`가 읽는다.
pub const PORTED: bool = true;

/// 띠 종류 번호(계약 6절 — bands.mjs 8 ~ 14줄 `KIND_NO`) — 지금 연표의 KIND_ORDER + 시대와 별개인 종류(문화 · 기관 · 왕조).
/// 묶음 3 · 3번(2026-09-22): 시대마다의 특별한 형태 — 번호는 뒤에 이어 붙인다(옛 저장소의 번호가 바뀌지 않게). 5비트라 31까지.
pub const KIND_NO: [(&str, i32); 23] = [
    ("state", 0), ("tributary", 1), ("fief", 2), ("dominion", 3), ("warlord", 4), ("vassal", 5), ("protectorate", 6), ("satellite", 7),
    ("puppet", 8), ("mandate", 9), ("colony", 10), ("occupied", 11), ("federation", 12), ("org", 13), ("era", 14), ("exile", 15), ("movement", 16),
    ("culture", 17), ("overlay", 18), ("dynasty", 19),
    ("client", 20), ("frontier", 21), ("prefecture", 22),
];
/// 책갈피 탭의 종류 딱지 — 지금 연표의 KIND_SHORT(js/timeline.js:563) 그대로(bands.mjs 17줄).
/// 종류 표(HT.POLITY_KINDS)의 short에 없는 문화 · 기관이 여기에서 붙고, 겹치는 것은 이 표가 이긴다(지금 연표와 같은 차례).
const KIND_SHORT: [(&str, &str); 6] = [("vassal", "종속"), ("federation", "연맹"), ("org", "조직"), ("era", "시대"), ("culture", "문화"), ("overlay", "기관")];
/// 연대의 확실성 번호 — HT.CERTAINTY의 차례(bands.mjs 19줄).
const CERT_NO: [(&str, i32); 4] = [("certain", 0), ("accepted", 1), ("estimated", 2), ("legend", 3)];
/// 실재성 번호 — HT.HISTORICITY의 차례(bands.mjs 21줄).
const HS_NO: [(&str, i32); 5] = [("attested", 0), ("semi", 1), ("legendary", 2), ("disputed", 3), ("refuted", 4)];

/// 형식 4 종류 번호(bands.mjs 23 ~ 27줄 `TYPE_NO` — 계약 1-1 초안 · 설계 3-11 초안의 차례): 띠의 form 0 ~ 4비트에 번호 + 1로.
pub const TYPE_NO: [(&str, i32); 19] = [
    ("state", 0), ("federation", 1), ("principality", 2), ("city", 3), ("government", 4), ("regime", 5), ("dependency", 6), ("warlord", 7), ("organization", 8),
    ("faith", 9), ("order", 10), ("company", 11), ("office", 12), ("group", 13), ("era", 14), ("realm", 15), ("union", 16), ("league", 17), ("person", 18),
];
/// 관계 번호(bands.mjs 28 ~ 32줄 `REL_NO` — 계약 1-1 초안): 띠에는 옛 종속 kind의 관계만 싣는다(명목상 · 구성국 · 동군연합은 소속선 구역 22가 말함).
pub const REL_NO: [(&str, i32); 13] = [
    ("tributary", 1), ("fief", 2), ("dominion", 3), ("vassal", 4), ("protectorate", 5), ("satellite", 6), ("puppet", 7), ("mandate", 8), ("colony", 9), ("occupied", 10),
    ("client", 11), ("frontier", 12), ("prefecture", 13),
];
/// 정통성 번호 + 1(0 = 비움 — bands.mjs 34줄 `STATUS_NO` · `HT.F4.STATUSES`의 차례).
const STATUS_NO: [(&str, i32); 6] = [("legit", 1), ("rival", 2), ("joint", 3), ("regent", 4), ("nominal", 5), ("claim", 6)];
/// 그림 띠(객체가 아님 — bands.mjs 36줄 `DRAWN_ONLY`): form의 종류는 0(모름).
const DRAWN_ONLY: [&str; 3] = ["culture", "overlay", "dynasty"];

/// `formOf(HT, p, kind)`(bands.mjs 37 ~ 48줄 — 리메이크 3단계 · 계약 1-1 초안): 0 ~ 4 형식 4 종류 + 1 · 5 ~ 9 관계 · 10 ~ 12 정통성 + 1 · 13 ~ 15 중요도 + 1.
/// 종류 = 적힌 type(정규화가 지킨 것) → 단체의 띠(groupUid — 실권 정권은 옛 군벌로 내려 옴) → 옛 kind에서 되살림(`HT.F4.typeOfKind` → [`f4::type_of_kind`]).
/// JS의 `p.type in TYPE_NO`는 `Object.prototype`의 이름(`constructor` …)도 참으로 본다 — 그때 `TYPE_NO[type] + 1`은 글이 되어 `|`에서 0(NaN)이다
/// (뒤의 갈래로 넘어가지 않음). 정통성 · 관계 표의 그런 이름도 함수 값이 되어 `<<`에서 0 — 표에 없는 것과 같다. 중요도는 `[0, 1, 2, 3].includes`(수만 — 글 '2'는 아님).
pub fn form_of(p: &V, kind: &str) -> i32 {
    let mut ty: Option<String> = None;
    if !DRAWN_ONLY.contains(&kind) {
        let pt = p.get("type");
        let key = if tv(&pt) { js::to_str(&pt).as_str().into_owned() } else { String::new() };
        ty = Some(if tv(&pt) && (lookup(&TYPE_NO, &key).is_some() || inherited(&key)) { key }
            else if tv(&p.get("groupUid")) { (if kind == "warlord" { "regime" } else { "organization" }).to_string() }
            // `HT.F4.typeOfKind(kind)` = `KIND_TYPE[kind] || 'state'` — kind가 Object.prototype의 이름이면 물려받은 값(TYPE_NO에 없음 → 종류 비트 0)
            else if inherited(kind) { String::new() }
            else { f4::type_of_kind(&V::from(kind)).to_string() });
    }
    let type_bits = ty.as_deref().and_then(|k| lookup(&TYPE_NO, k)).map_or(0, |x| x + 1);
    let imp = match p.get("importance") { V::Num(x) if x == 0.0 || x == 1.0 || x == 2.0 || x == 3.0 => x as i32 + 1, _ => 0 };
    let status = p.get("status");
    let status_bits = if status.is_undef() { 0 } else { lookup(&STATUS_NO, &js::to_str(&status).as_str()).unwrap_or(0) };
    type_bits | (lookup(&REL_NO, kind).unwrap_or(0) << 5) | (status_bits << 10) | (imp << 13)
}

/// look(bands.mjs 51 ~ 56줄 `L`): 아래 5비트 종류 · 5~6 확실성 · 7 연대 폭 · 8~10 실재성 · 11~18 모습 · 19 사건 있음 · 20 칸 있음 · 21~29 가진 칸 층(tracks.mjs의 늦은 차례가 켬).
const L_CERT: i32 = 5;
const L_RANGE: i32 = 1 << 7;
const L_HS: i32 = 8;
const L_DEP: i32 = 1 << 11;
const L_FLAG: i32 = 1 << 12;
const L_EXILE: i32 = 1 << 13;
const L_UNDER: i32 = 1 << 14;
const L_UNDER_HEAD: i32 = 1 << 15;
const L_FOLDED: i32 = 1 << 16;
const L_MEMBER: i32 = 1 << 17;
const L_HOLLOW: i32 = 1 << 18;

/// 연대 폭 항목의 구역(계약 6절 — 일반 항목 19).
const SECTION_RANGE: f64 = 19.0;

// ── bands.mjs ──

/// 이름 → 번호 표에서 찾기(`TABLE[key]` — 없으면 None: 원본의 `?? 기본값`이 받는다).
fn lookup(table: &[(&str, i32)], key: &str) -> Option<i32> { table.iter().find(|(k, _)| *k == key).map(|(_, v)| *v) }

/// `o[k]`(수 열쇠 · 글 열쇠 모두 — JS 속성 열쇠는 `String(k)`).
fn at(o: &V, k: &V) -> V { match k { V::Num(x) => o.get(x), other => o.get(t(other).as_str()) } }

/// `Math.min(31, x || 0) << sh`의 `x || 0`을 수로(ToInt32 앞).
fn int32(x: f64) -> i32 { js::to_i32(x) }

/// `contribute(ctx, out)` — 트랙마다 띠(바탕 문화는 깔리는 줄마다 하나)를 `out.periods`에, 연대 폭을 일반 항목 19로 싣고 `shared.bandOf`를 만든다.
pub fn contribute(ctx: &mut Ctx, out: &mut Value) -> crate::Result<()> {
    let tl = ctx.tl.clone();
    let (mut sk_hidden, mut sk_overlay, mut sk_no_row) = (0.0, 0.0, 0.0);
    let band_of = Map::new(); // 띠의 uid → out.periods의 순번(바탕 문화는 첫 줄의 것)
    ctx.shared.set("bandOf", band_of.clone());
    let (mut c_plain, mut c_under, mut c_under_more, mut c_range) = (0.0, 0.0, 0.0, 0.0);
    let hosted = tl.get("_hosted");

    for (track_index, tr) in list(&tl.get("tracks")).iter().enumerate() {
        /* 바탕 문화(승계국 줄 밑에 깔리는 띠)도 같은 줄의 띠와 겹친 채 그대로 싣는다 — 깔리는 줄이 여럿이면 줄마다 하나씩.
           둘째 줄부터는 uid 뒤에 #u<줄>을 붙여 가리키는 곳이 헷갈리지 않게 한다(칸 · 항목 기록은 첫 줄의 uid를 쓴다). */
        let periods = list(&tr.get("periods"));
        let shown: Vec<V> = periods.iter().filter(|p| !p.bool("_overlay")).cloned().collect();
        for p in &shown {
            if p.bool("_hidden") { sk_hidden += 1.0; continue; }
            let row = p.get("_row");
            let rows: Vec<V> = if p.bool("_under") { list(&or(p.get("_underRows"), arr(Vec::new()))) }
                else if row.is_nullish() || lt(&row, &V::Num(0.0)) || le(&tr.get("rows"), &row) { Vec::new() } else { vec![row.clone()] };
            if rows.is_empty() { sk_no_row += 1.0; continue; }
            let (start, end) = (minute_v(&p.get("start")), minute_v(&p.get("endY")));
            match (start.as_i64(), end.as_i64()) {
                (Some(a), Some(b)) if a <= b => {}
                _ => return Err(format!("띠의 기간 오류: {}", t(&p.get("name"))).into()),
            }
            let kind = t(&or(p.get("polityKind"), s("state")));
            let cert = t(&or(p.get("certainty"), s("accepted")));
            let ranges = [p.get("startRange"), p.get("endRange")].into_iter().filter(tv).count();
            let hs_id = historicity_of(p);
            let hs = if hs_id.is_empty() { "attested".to_string() } else { hs_id.as_str().into_owned() };
            let dep = or(p.get("_dep"), V::Null);
            let family = vocab::kind_family(&kind);
            let form = form_of(p, &kind);
            let look = lookup(&KIND_NO, &kind).unwrap_or(0)
                | (lookup(&CERT_NO, &cert).unwrap_or(1) << L_CERT)
                | (if ranges > 0 { L_RANGE } else { 0 })
                | (lookup(&HS_NO, &hs).unwrap_or(0) << L_HS)
                | (if family == "dependent" { L_DEP } else { 0 })
                | (if kind == "movement" { L_FLAG } else { 0 })
                | (if kind == "exile" { L_EXILE } else { 0 })
                | (if p.bool("_under") { L_UNDER } else { 0 })
                | (if p.bool("_folded") { L_FOLDED } else { 0 })
                | (if p.bool("_member") { L_MEMBER } else { 0 })
                | (if tv(&hosted) && hosted.as_map().is_some_and(|m| m.has(&p.get("uid"))) { L_HOLLOW } else { 0 });

            /* 책갈피 탭의 딱지: 이름 뒤에 차례로 종류 → 실재성 → 지위. 무엇까지 들어가는지는 폭에 달렸으므로(tabParts) 후보를 모두 싣고 그리는 쪽이 고른다 */
            // 단체의 띠(리메이크 조각 ④ — core.js groupBands)는 단체의 갈래(붕당 · 정당 · 세력 …)를 딱지로
            let kind_short = KIND_SHORT.iter().find(|(k, _)| *k == kind).map(|(_, v)| *v)
                .or_else(|| POLITY_KINDS.iter().find(|k| k.id == kind).and_then(|k| k.short)).unwrap_or("");
            let short = or(p.get("groupKind"), s(kind_short));
            let mut tags: Vec<V> = Vec::new();
            if family != "dependent" && tv(&short) { tags.push(short.clone()); }
            let hs_tag = historicity_tag(&hs);
            if !hs_tag.is_empty() { tags.push(s(hs_tag)); }
            let geo = or(at(&tr.get("geos"), &rows[0]), tr.get("geo"));
            let rank_spans = p.get("rankSpans");
            // 지위 단이 없는 줄의 지위 딱지(tabRank)
            let rk = if !geo.bool("rankH") && tv(&rank_spans) && n(&rank_spans.get("length")) == 1.0 { rank_spans.get(&0.0) } else { V::Null };
            if tv(&rk) { tags.push(or(rk.get("name"), s(""))); }
            let lanes = |k: &str| -> i32 { int32(js::min(&[31.0, n(&or(if tv(&dep) { dep.get(k) } else { dep.clone() }, V::Num(0.0)))])) };
            let sub = (if tv(&rk) { int32(js::min(&[7.0, n(&js::add(&or(rk.get("level"), V::Num(0.0)), &V::Num(1.0)))])) } else { 0 })
                | (if ranges > 0 { 1 << 6 } else { 0 })
                | (lanes("outLanes") << 7)
                | (lanes("inLanes") << 12);
            let tag = join(&tags, "|");

            for (k, r) in rows.iter().enumerate() {
                let uid = if k == 0 { p.get("uid") } else { V::from(format!("{}#u{}", t(&p.get("uid")), t(r))) };
                if k == 0 { band_of.set(p.get("uid"), arr_len(out, "periods") as f64); }
                let fuzzy = (if p.bool("startUnknown") { 1 } else { 0 }) | (if p.bool("endUnknown") { 2 } else { 0 });
                arr_mut(out, "periods").push(json!({
                    "uid": jsv(&uid), "track": track_index, "row": jsv(r), "start": start.clone(), "end": end.clone(),
                    "fuzzy": fuzzy, "color": color(&p.get("color"), 0xa4b1b7), "name": jsv(&or(p.get("name"), s(""))),
                    "look": look | (if p.bool("_under") && k == 0 { L_UNDER_HEAD } else { 0 }), "tag": tag.as_str(), "sub": sub, "form": form,
                }));
                if p.bool("_under") { if k == 0 { c_under += 1.0; } else { c_under_more += 1.0; } }
                else { c_plain += 1.0; }
            }

            /* 연대 폭(흐린 끝 — 확실한 경계가 아니라 '이 사이 어딘가'): 구간이 있어야 그릴 수 있으므로 일반 항목 19로(계약 6절) */
            for (side, rg) in [(0.0, p.get("startRange")), (1.0, p.get("endRange"))] {
                if !tv(&rg) { continue; }
                let (s_, e_) = (minute_v(&rg.get(&0.0)), minute_v(&rg.get(&1.0)));
                let (Some(a), Some(b)) = (s_.as_i64(), e_.as_i64()) else { continue };
                if b < a { continue; }
                arr_mut(out, "items").push(json!({
                    "section": jv(SECTION_RANGE), "track": track_index, "row": jsv(&rows[0]), "row2": jsv(&rows[0]), "start": a, "end": b, "lod": -1,
                    "ref": jsv(&p.get("uid")), "name": "", "color": color(&p.get("color"), 0xa4b1b7),
                    // 무늬는 지금 연표의 zoneKind(확실성이 통설이면 추정의 무늬)와 같게
                    "a": jv(side), "b": if cert == "legend" { 1 } else if cert == "certain" { 2 } else { 0 }, "c": 0, "d": 0, "text2": "",
                }));
                c_range += 1.0;
            }
        }
        for p in &periods { if p.bool("_overlay") { sk_overlay += 1.0; } }
    }
    ctx.notes.set("띠", o! { "보통" => c_plain, "바탕문화" => c_under, "바탕문화_덧줄" => c_under_more, "연대폭" => c_range });
    ctx.notes.set("띠에서_뺀_것", o! { "hidden" => sk_hidden, "overlay" => sk_overlay, "noRow" => sk_no_row });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn historicity_follows_core_js() {
        let x = |h: &str| V::Obj(o! { "historicity" => h });
        assert_eq!(historicity_of(&x("attested")).as_str(), "");
        assert_eq!(historicity_of(&x("반전설")).as_str(), "semi");
        assert_eq!(historicity_of(&x(" 논쟁 ")).as_str(), "disputed");
        assert_eq!(historicity_of(&x("모름")).as_str(), "");
        assert_eq!(historicity_of(&V::Null).as_str(), "");
        assert_eq!(historicity_tag("legendary"), "전설");
        assert_eq!(historicity_tag(""), "");
        assert_eq!(historicity_tag("attested"), "");
    }
}

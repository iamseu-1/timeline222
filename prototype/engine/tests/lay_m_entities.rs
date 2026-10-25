//! 과제 8-틀 — 모듈 `entities`(16/21)만 Node와 견준다(`common::modcheck` — `pre-calendar`를 심고 값 · `json` 글 바이트). 정답지: `node prototype/scripts/layout-oracle.mjs --seams=mods`.
//! 과제 13a ~ 13d(갈래 D): 덩이마다 그 갈래(kind)의 기록을 걸러 견주는 검사를 더해 왔다 — 기록마다 uid · kind · pack과 `json` 글(풀어서 값으로, 그리고 바이트로).
//! 13d에서 뒤 덩이 열쇠 거르개를 걷고(모든 열쇠) `PORTED`를 참으로 — 통째 검사(`entities_contribute_matches_node`)가 out 전부를 값 · `json` 바이트로 견준다.
//! 덩이 검사는 `lay::m::entities::contribute`를 바로 부른다(`lay::export_one`과 같은 심기: 줄 배정까지 지은 문맥 · `pre-calendar`(+ `.shared`)).
mod common;

use archive_engine::lay::{self, js};
use common::oracle::{assert_same, fixtures, inputs, oracle, seam_opts, Fixture};
use serde_json::{json, Value};

/// 13a — 띠 · 사건 · 칸 기록(정권 · 기관 · 문화 · 왕조 · 사건 · 조약 · 시대 구분 · 대범위 · 주제 사전).
const KINDS_13A: &[&str] = &["period", "organ", "culture", "dynasty", "event", "treaty", "epoch", "scope", "themes"];
/// 13b — 인물 · 가문(· 성씨).
const KINDS_13B: &[&str] = &["figure", "house", "surname"];
/// 13c — 계보 뼈대 기록.
const KINDS_13C: &[&str] = &["kin"];
/// 13d — 단체 · 제도 · 지명 · 모아 보기 판 · 지도 · 글꼴.
const KINDS_13D: &[&str] = &["group", "institution", "place", "view", "map", "font"];
/// 갈래 목록 잇기.
fn kinds(l: &[&[&'static str]]) -> Vec<&'static str> { l.iter().flat_map(|x| x.iter().copied()).collect() }

/// 자료 하나: Node의 `pre-calendar`(+ `.shared`)를 심고 entities의 `contribute`만 돌린 out.
fn run(f: &Fixture) -> Value {
    let o = seam_opts(Some("entities"));
    let mut ctx = lay::ctx::context_of(&inputs(f), &o, true).unwrap_or_else(|e| panic!("자료 {}: 문맥 — {e}", f.name));
    ctx.shared = lay::export::shared_seed(&oracle(f, "pre-calendar.shared.json")).unwrap();
    ctx.notes = js::Obj::new();
    let mut out = oracle(f, "pre-calendar.json");
    out.as_object_mut().expect("out").remove("$oracle");
    lay::m::entities::contribute(&mut ctx, &mut out).unwrap_or_else(|e| panic!("자료 {} · 모듈 entities: {e}", f.name));
    out
}

/// out.entities 가운데 kinds의 기록만 — `json`은 JS 차례로 읽어 다시 적은 글(되읽은 글 = 원문을 단언).
fn pick(out: &Value, kinds: &[&str]) -> Vec<Value> {
    out["entities"].as_array().expect("entities").iter().filter(|e| kinds.contains(&e["kind"].as_str().unwrap_or(""))).map(|e| {
        let text = e["json"].as_str().expect("json 글");
        let body = js::parse(text).expect("json");
        // 되읽어 다시 적은 글 = 원문(그래서 거르개를 건 견줌도 원문 바이트의 견줌이다)
        assert_eq!(js::stringify(&body), text, "{}: json 글을 되읽어 다시 적으면 원문과 다릅니다", e["uid"]);
        json!({ "uid": e["uid"], "kind": e["kind"], "pack": e["pack"], "json": js::stringify(&body) })
    }).collect()
}

/// 갈래 거르개 검사: 자료마다 kinds의 기록이 값으로 같고(`json`은 풀어서) · `json` 글이 바이트까지 같다.
fn check_kinds(what: &str, kinds: &[&str]) {
    let mut n = 0;
    let mut recs = 0;
    for f in fixtures() {
        let want_out = oracle(&f, "pre-entities.json");
        let want = pick(&want_out, kinds);
        let got = pick(&run(&f), kinds);
        assert_same(&f, &format!("pre-entities[{what}]"), &Value::Array(got.clone()), &Value::Array(want.clone()));
        for (g, w) in got.iter().zip(&want) {
            assert_eq!(g["json"], w["json"], "자료 {} · {what} · {}: json 글이 바이트로 다릅니다(값은 같음 — 열쇠 차례 · 수 글)", f.name, w["uid"]);
        }
        n += 1;
        recs += want.len();
    }
    assert!(n > 0, "정답지 자료가 하나도 없습니다");
    eprintln!("entities {what}: 자료 {n}개 · 기록 {recs}개 Node와 같음(값 · json 바이트)");
}

#[test]
fn entities_13a_bands_events_cells_match_node() { check_kinds("13a 띠 · 사건 · 칸", KINDS_13A); }

#[test]
fn entities_13b_people_houses_match_node() { check_kinds("13b 인물 · 가문 · 띠의 칸 사람", &kinds(&[KINDS_13A, KINDS_13B])); }

#[test]
fn entities_13c_kin_lineage_match_node() { check_kinds("13c 승계 · 계보", &kinds(&[KINDS_13A, KINDS_13B, KINDS_13C])); }

#[test]
fn entities_13d_groups_lens_rest_match_node() { check_kinds("13d 단체 · 제도 · 렌즈 · 나머지", &kinds(&[KINDS_13A, KINDS_13B, KINDS_13C, KINDS_13D])); }

/// 덩이 갈래가 이 모듈이 내는 기록의 갈래를 모두 덮는다(정답지 자료 21개 — 새 갈래가 생기면 덩이 표에 더할 것).
#[test]
fn entities_chunk_kinds_cover_all_records() {
    let all = kinds(&[KINDS_13A, KINDS_13B, KINDS_13C, KINDS_13D]);
    let mut seen = std::collections::BTreeSet::new();
    for f in fixtures() {
        let before = oracle(&f, "pre-calendar.json")["entities"].as_array().map_or(0, Vec::len);
        for e in oracle(&f, "pre-entities.json")["entities"].as_array().expect("entities").iter().skip(before) { seen.insert(e["kind"].as_str().unwrap_or("").to_string()); }
    }
    let missing: Vec<&String> = seen.iter().filter(|k| !all.contains(&k.as_str())).collect();
    assert!(missing.is_empty(), "덩이 갈래 표에 없는 기록 갈래: {missing:?}");
    assert!(seen.len() >= 17, "정답지가 내는 기록 갈래가 적습니다: {seen:?}");
}

#[test]
fn entities_contribute_matches_node() { common::modcheck::check_contribute("entities"); }

// ── 벡터(`node prototype/scripts/js-vectors.mjs`의 갈래 `entities` — 정답지가 다 지나지 않는 셈) ──

fn vectors() -> &'static Value {
    static V: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    V.get_or_init(|| {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("lay").join("js-vectors.json");
        serde_json::from_str(&std::fs::read_to_string(&path).expect("js-vectors.json")).expect("JSON")
    })
}
fn lane(name: &str) -> &'static Vec<Value> {
    vectors()["entities"][name].as_array().unwrap_or_else(|| panic!("벡터 entities.{name}가 없습니다 — node prototype/scripts/js-vectors.mjs"))
}
/// 짓기 꼴의 원시 값(`{"$u":0}` · `{"$num":"NaN"}` …) → JS 값.
fn prim(e: &Value) -> js::V {
    match e {
        Value::Object(o) if o.contains_key("$u") => js::V::Undef,
        Value::Object(o) if o.contains_key("$num") => js::V::Num(match o["$num"].as_str().unwrap() { "NaN" => f64::NAN, "Infinity" => f64::INFINITY, "-Infinity" => f64::NEG_INFINITY, "-0" => -0.0, x => panic!("$num {x}") }),
        other => js::from_json(other),
    }
}

/// `HT.groupDigits`(P3-4 손질 — `toLocaleString('ko-KR')` 대신) — 과제 4 보고 §4의 표 + 무작위. 정답지는 1000 미만만 지난다.
#[test]
fn group_digits_match_web() {
    let rows = lane("groupDigits");
    assert!(rows.len() >= 300, "groupDigits 벡터가 너무 적습니다: {}", rows.len());
    let mut grouped = 0;
    for r in rows {
        let want = r[1].as_str().unwrap();
        assert_eq!(lay::m::entities::web::group_digits(&prim(&r[0])), want, "groupDigits({})", r[0]);
        if want.contains(',') { grouped += 1; }
    }
    assert!(grouped >= 100, "세 자리 묶음이 든 행이 적습니다: {grouped}");
}

/// `Number.prototype.toFixed(1)` — 의석 막대의 득표율 글.
#[test]
fn to_fixed1_matches_web() {
    let rows = lane("toFixed1");
    assert!(rows.len() >= 200);
    for r in rows { assert_eq!(lay::m::entities::web::to_fixed1(js::to_num(&prim(&r[0]))), r[1].as_str().unwrap(), "({}).toFixed(1)", r[0]); }
}

/// `kin.mjs`의 `splitKin` · `joinKin` — 작은 상한으로 나눈 덩어리 · 합친 기록이 바이트까지 Node와 같다(마디 5만을 넘는 뼈대는 정답지에 없음).
#[test]
fn kin_split_and_join_match_node() {
    use lay::m::entities::kin::{join_kin, split_kin, Rec};
    let rows = lane("kin");
    let mut split = 0;
    for r in rows {
        let rec = Rec::from_v(&js::parse(r[0].as_str().unwrap()).unwrap());
        assert_eq!(js::stringify(&rec.to_v()), r[0].as_str().unwrap(), "기록 되읽기 · 다시 쓰기");
        let parts = split_kin(&rec, r[1].as_u64().unwrap() as usize);
        let want: Vec<&str> = r[2].as_array().unwrap().iter().map(|x| x.as_str().unwrap()).collect();
        let got: Vec<String> = parts.iter().map(|p| js::stringify(&p.to_v())).collect();
        assert_eq!(got.len(), want.len(), "덩어리 수 (상한 {})", r[1]);
        for (g, w) in got.iter().zip(&want) { assert_eq!(g, w, "덩어리 (상한 {})", r[1]); }
        let joined = join_kin(&parts);
        assert_eq!(js::stringify(&joined.to_v()), r[3].as_str().unwrap(), "합친 기록 (상한 {})", r[1]);
        if parts.len() > 1 { split += 1; }
    }
    assert!(split >= 5, "나뉜 경우가 적습니다: {split}");
}

/// `kinCollect(model, HT, { limit })` — 견본 등불 연대기 모델(정답지와 같은 '오늘')을 상한 8 · 5 · 20으로 나눠 덩어리 길 전체가 Node와 같다:
/// 기록(uid · rootUid · 주인 · 본문 json 바이트) · 사람 자리 → 뼈대 자리(chunk 포함) · 칸 → 뼈대 자리 · 가문 x_kin(chunk 포함 · 차례) · `chunkAt`(뿌리마다 한 벌 번호 전부) ·
/// 집계(갈래 D 검토 1 · 2 · 판정 R27). 그리고 `totalOf`(꼬투리 빼기 — `kin_total`)로 센 뿌리별 한 벌 마디 수의 합이 집계의 마디 수와 같다.
#[test]
fn kin_collect_chunks_match_node() {
    use lay::m::entities::{kin::kin_collect, kin_total, people::KinCache};
    let rows = lane("kinCollect");
    let f = fixtures().into_iter().find(|f| f.name == "lantern").expect("정답지 자료 lantern");
    let ctx = lay::ctx::context_of(&inputs(&f), &seam_opts(None), false).expect("문맥");
    for limit in [8u64, 5, 20] {
        let k = kin_collect(&mut KinCache::default(), &ctx.model, limit as usize).expect("뼈대");
        let of = |tag: &'static str| rows.iter().filter(move |r| r[0] == tag && r[1].as_u64() == Some(limit));
        // 기록 — 차례까지
        let recs: Vec<&Value> = of("record").collect();
        assert_eq!(k.records.len(), recs.len(), "상한 {limit}: 기록 수");
        for (g, w) in k.records.iter().zip(&recs) {
            assert_eq!(g.uid, w[2].as_str().unwrap(), "상한 {limit}: 기록 uid");
            assert_eq!(g.root_uid, w[3].as_str().unwrap(), "상한 {limit} · {}: rootUid", g.uid);
            assert_eq!(g.house_id.as_ref().map_or(Value::Null, js::to_json), w[4], "상한 {limit} · {}: houseId", g.uid);
            assert_eq!(g.polity_uid.as_ref().map_or(Value::Null, |u| Value::from(u.as_str())), w[5], "상한 {limit} · {}: polityUid", g.uid);
            assert_eq!(js::stringify(&g.body.to_v()), w[6].as_str().unwrap(), "상한 {limit} · {}: 본문 json 글", g.uid);
        }
        // 사람 자리 · 칸
        let persons: Vec<&Value> = of("person").collect();
        assert_eq!(k.person_at.len(), persons.len(), "상한 {limit}: 사람 자리 수");
        for w in &persons {
            let p = k.person_at.get(&js::Str::from(w[2].as_str().unwrap())).unwrap_or_else(|| panic!("상한 {limit}: 사람 자리 {} 없음", w[2]));
            assert_eq!((p.key.as_str(), p.at as u64, p.member, p.chunk.as_deref()), (w[3].as_str().unwrap(), w[4].as_u64().unwrap(), w[5].as_bool().unwrap(), w[6].as_str()), "상한 {limit}: 사람 자리 {}", w[2]);
        }
        let cells: Vec<&Value> = of("cell").collect();
        assert_eq!(k.cell_at.len(), cells.len(), "상한 {limit}: 칸 수");
        for w in &cells {
            let c = k.cell_at.get(&js::Str::from(w[2].as_str().unwrap())).unwrap_or_else(|| panic!("상한 {limit}: 칸 {} 없음", w[2]));
            assert_eq!((c.0.as_str(), i64::from(c.1)), (w[3].as_str().unwrap(), w[4].as_i64().unwrap()), "상한 {limit}: 칸 {}", w[2]);
        }
        // 가문 x_kin — Map 차례까지
        let houses: Vec<&Value> = of("house").collect();
        let got: Vec<(js::V, js::V)> = k.house_kin.entries();
        assert_eq!(got.len(), houses.len(), "상한 {limit}: 가문 수");
        for ((id, o), w) in got.iter().zip(&houses) {
            assert_eq!(js::to_json(id), w[2], "상한 {limit}: 가문 차례");
            assert_eq!(js::stringify(o), w[3].as_str().unwrap(), "상한 {limit}: 가문 {} x_kin", w[2]);
        }
        // chunkAt — 뿌리마다 한 벌 번호 전부
        let chunk_at: Vec<&Value> = of("chunkAt").collect();
        let mut inside = 0;
        for w in &chunk_at {
            let got = k.chunk_at(w[2].as_str().unwrap(), w[3].as_i64().unwrap());
            assert_eq!(got.as_deref(), w[4].as_str(), "상한 {limit}: chunkAt({}, {})", w[2], w[3]);
            if got.is_some() { inside += 1; }
        }
        let notes = of("notes").next().expect("집계");
        assert_eq!(js::stringify(&js::V::Obj(k.notes.clone())), notes[2].as_str().unwrap(), "상한 {limit}: 집계");
        // totalOf(꼬투리 빼기): 뿌리별 한 벌 마디 수의 합 = 집계의 마디 수
        let kin_rec: std::collections::HashMap<&str, &lay::m::entities::kin::Rec> = k.records.iter().map(|r| (r.uid.as_str(), &r.body)).collect();
        let total: i64 = k.records.iter().filter(|r| r.uid == r.root_uid).map(|r| kin_total(&kin_rec, &r.uid).expect("totalOf")).sum();
        assert_eq!(total as f64, js::to_num(&k.notes.get("마디")), "상한 {limit}: 뿌리별 totalOf의 합");
        // 덩어리 길을 밟았는가
        assert!(k.records.iter().filter(|r| r.body.root.is_some()).count() >= 10, "상한 {limit}: 덩어리가 적습니다");
        assert!(k.records.iter().any(|r| r.body.extra_far.is_some()), "상한 {limit}: extraFar가 없습니다");
        assert!(k.person_at.values().any(|p| p.chunk.is_some()), "상한 {limit}: 사람 자리의 chunk가 없습니다");
        assert!(inside >= 40 && chunk_at.len() > inside, "상한 {limit}: chunkAt — 덩어리 안 {inside} / {}", chunk_at.len());
    }
}

/// 작은 상한(8)으로 모듈 전체를 돌려도 끝의 점검(꼬투리 빼기 `totalOf` · x_kin의 chunk · kinAt 번호)이 지나간다 — 덩어리 기록이 서로를 바르게 가리킨다
/// (Node 내보내기는 늘 상한 5만이라 이 길의 정답지는 없음 — `kin_collect_chunks_match_node`가 덩어리 자체를 Node와 견줌).
#[test]
fn small_kin_limit_passes_the_final_checks() {
    let f = fixtures().into_iter().find(|f| f.name == "lantern").expect("정답지 자료 lantern");
    let o = seam_opts(Some("entities"));
    let mut ctx = lay::ctx::context_of(&inputs(&f), &o, true).expect("문맥");
    ctx.shared = lay::export::shared_seed(&oracle(&f, "pre-calendar.shared.json")).unwrap();
    ctx.notes = js::Obj::new();
    let mut out = oracle(&f, "pre-calendar.json");
    out.as_object_mut().expect("out").remove("$oracle");
    lay::m::entities::contribute_limit(&mut ctx, &mut out, 8).unwrap_or_else(|e| panic!("상한 8: {e}"));
    let ents = out["entities"].as_array().unwrap();
    let body = |e: &Value| js::parse(e["json"].as_str().unwrap()).unwrap();
    let chunks = ents.iter().filter(|e| e["kind"] == "kin" && !body(e).get("root").is_undef()).count();
    assert!(chunks >= 20, "덩어리 기록이 적습니다: {chunks}");
    // 같은 기록에서: x_kin이 있고 그 x_kin에 chunk가 있음(가문 · 계보 전용 인물)
    let with_chunk = ents.iter().filter(|e| { let x = body(e).get("x_kin"); !x.is_undef() && !x.get("chunk").is_undef() }).count();
    assert!(with_chunk >= 3, "x_kin.chunk가 든 기록이 적습니다: {with_chunk}");
}

// ── 과제 Y: JS라면 TypeError로 멈췄을 곳(갈래 D 걱정 1)은 오류 ──

/// 자료 `name`의 문맥을 짓고(줄 배정까지 · `pre-calendar`(+ `.shared`)를 심고) 모델을 `poison`으로 고친 뒤 entities를 돌린 오류 글(오류가 아니면 실패).
/// 정답지 자료는 이 길을 밟지 않는다 — 모델을 손으로 고쳐 그 길만 밟게 한다. 오류 뒤에 잘못이 남지 않아야 한다(다음 모듈에 새지 않게).
fn poisoned(name: &str, poison: impl FnOnce(&js::V)) -> String {
    let list = fixtures();
    let f = list.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("자료 {name}이 없습니다"));
    let o = seam_opts(Some("entities"));
    let mut ctx = lay::ctx::context_of(&inputs(f), &o, true).unwrap_or_else(|e| panic!("자료 {name}: 문맥 — {e}"));
    ctx.shared = lay::export::shared_seed(&oracle(f, "pre-calendar.shared.json")).unwrap();
    ctx.notes = js::Obj::new();
    let mut out = oracle(f, "pre-calendar.json");
    out.as_object_mut().expect("out").remove("$oracle");
    poison(&ctx.model);
    let err = lay::m::entities::contribute(&mut ctx, &mut out).err().unwrap_or_else(|| panic!("자료 {name}: 오류여야 합니다")).to_string();
    assert!(lay::model::util::take_fault().is_none(), "자료 {name}: 오류 뒤에 잘못이 남았습니다");
    assert!(err.starts_with("entities 모듈 — "), "{err}");
    err
}
/// 모델의 목록 `key`에서 `pick`이 맞는 첫 항목(없으면 실패).
fn first_of(model: &js::V, key: &str, what: &str, pick: impl Fn(&js::V) -> bool) -> js::V {
    lay::model::util::list(&model.get(key)).into_iter().find(|x| pick(x)).unwrap_or_else(|| panic!("모델에 {what}이(가) 없습니다"))
}
fn arr_len(v: &js::V) -> usize { lay::model::util::list(v).len() }
fn arr_set(v: &js::V, i: usize, x: js::V) { if let js::V::Arr(a) = v { a.set(i, x); } else { panic!("배열이 아닙니다") } }

/// ① 사람 고리(kinLinesHTML)의 배우자 줄에 사람 자리가 없음 — JS `has(ring(null), 'when', 기간)`에서 TypeError.
#[test]
fn kin_line_without_person_is_an_error() {
    let err = poisoned("lantern", |model| {
        let js::V::Map(ix) = model.get("personIndex") else { panic!("personIndex") };
        for nd in ix.values() {
            let bad = js::V::Obj(js::Obj::new());
            if let js::V::Obj(o) = &bad { o.set("node", js::V::Null); o.set("start", 1000.0); }
            if let js::V::Obj(o) = &nd { o.set("spouses", js::V::Arr(js::Arr::new(vec![bad]))); }
        }
    });
    assert!(err.contains("배우자 줄에 사람 자리가 없습니다"), "{err}");
}

/// ② 목록 한 줄(brief)의 상대가 없음 — 소속 상대(hostRow) · 구성원(memberRow) · 다스린 나라(x_ruled) · 대범위 구성원(x_members). JS는 인자를 셈하거나 `o.when =`에서 TypeError.
#[test]
fn brief_without_target_is_an_error() {
    let err = poisoned("lantern", |model| {
        let p = first_of(model, "periods", "상국이 있는 정권", |p| !lay::model::util::is(&p.get("polityKind"), "dynasty") && arr_len(&p.get("hosts")) > 0);
        if let js::V::Obj(h) = p.get("hosts").get(&0.0) { h.set("host", js::V::Null); }
    });
    assert!(err.contains("hostRow"), "{err}");
    let err = poisoned("lantern", |model| {
        let p = first_of(model, "periods", "구성원이 있는 정권", |p| arr_len(&p.get("members")) > 0);
        arr_set(&p.get("members"), 0, js::V::Null);
    });
    assert!(err.contains("memberRow"), "{err}");
    let err = poisoned("lantern", |model| {
        let s = first_of(model, "scopes", "구성원이 있는 대범위", |s| arr_len(&s.get("members")) > 0);
        arr_set(&s.get("members"), 0, js::V::Null);
    });
    assert!(err.contains("x_members"), "{err}");
}

/// ② 다스린 나라(x_ruled) — 왕조의 상국이 없음(JS `h.host.start`에서 TypeError). 왕조가 상국을 둔 자료에서.
#[test]
fn dynasty_without_host_is_an_error() {
    let has = |name: &str| -> bool {
        let list = fixtures();
        let Some(f) = list.iter().find(|f| f.name == name) else { return false };
        let ctx = lay::ctx::context_of(&inputs(f), &seam_opts(None), false).expect("문맥");
        let found = lay::model::util::list(&ctx.model.get("periods")).iter().any(|p| lay::model::util::is(&p.get("polityKind"), "dynasty") && arr_len(&p.get("hosts")) > 0);
        found
    };
    let name = ["lantern", "synth", "east-asia"].into_iter().find(|n| has(n)).expect("상국을 둔 왕조가 있는 자료가 없습니다");
    let err = poisoned(name, |model| {
        let p = first_of(model, "periods", "상국을 둔 왕조", |p| lay::model::util::is(&p.get("polityKind"), "dynasty") && arr_len(&p.get("hosts")) > 0);
        if let js::V::Obj(h) = p.get("hosts").get(&0.0) { h.set("host", js::V::Null); }
    });
    assert!(err.contains("x_ruled"), "자료 {name}: {err}");
}

/// ③ 계보 뼈대의 아래 파가 가문 표에 없음(JS `h.uid`에서 TypeError) · ⑤ 가문의 members가 배열이 아님(`h.members.filter`) · ⑥ 사람 자리의 seq가 없음
/// (JS는 `loc[undefined]`에 적고 읽어 다른 뼈대가 됨 — 조용히 다른 답 대신 오류).
#[test]
fn house_and_seat_shapes_are_errors() {
    let err = poisoned("lantern", |model| {
        for h in lay::model::util::list(&model.get("houses")) {
            let mut ch = lay::model::util::list(&h.get("children"));
            ch.push(js::V::from("가상-없는-파"));
            if let js::V::Obj(o) = &h { o.set("children", js::V::Arr(js::Arr::new(ch))); }
        }
    });
    assert!(err.contains("아래 파") && err.contains("가상-없는-파"), "{err}");
    let err = poisoned("lantern", |model| {
        let h = first_of(model, "houses", "가문", |_| true);
        if let js::V::Obj(o) = &h { o.set("members", js::V::Null); }
    });
    assert!(err.contains("members가 배열이 아닙니다"), "{err}");
    let err = poisoned("lantern", |model| {
        for p in lay::model::util::list(&model.get("persons")) { if let js::V::Obj(o) = &p { o.set("seq", js::V::Null); } }
    });
    assert!(err.contains("모델 차례(seq)"), "{err}");
}

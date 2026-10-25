//! 한 벌 P3 과제 6 — 모델과 준비(이음매 ② 앞): 자료마다 Rust의 `lay::prepared`(정규화 → `buildModel` · `link*` → `contextOf`의 준비)가
//! Node의 `prep.json`(줄 배정을 빈 함수로 둔 `contextOf`의 `seam({ tracks, depth, cats, proxies, cityUses, scopes, model })`)과 차이 0이다 —
//! 값으로(`lay::same::diff` — 경로가 든 차이) 그리고 덤프 글의 바이트로(처음 만난 경로 · `$ref`까지 — 객체를 나눠 가짐 · 열쇠 차례가 JS와 같아야 같다).
//! 정답지: `node prototype/scripts/layout-oracle.mjs --seams=prep`(→ `prototype/results/oracle/<자료>/prep.json`). 합성 자료 `synth` · `synth+patch`(고침 1회차 —
//! 실제 사용자 자료가 흔히 지나는데 다른 정답지 자료가 닿지 않던 갈래)는 [`synth_fixtures_reach_the_model_branches`]가 그 갈래에 닿았는지 센다.
mod common;
use archive_engine::lay::{self, ctx, js};
use common::oracle::{assert_same, fixtures, inputs, oracle_body, oracle_js, results_dir, seam_opts};

/// 두 글의 처음 다른 자리와 그 둘레(차이를 좇을 때).
fn first_diff(a: &str, b: &str) -> String {
    let (x, y) = (a.as_bytes(), b.as_bytes());
    let at = x.iter().zip(y.iter()).position(|(p, q)| p != q).unwrap_or(x.len().min(y.len()));
    let around = |s: &str| { let lo = s.floor_char_boundary(at.saturating_sub(160)); let hi = s.ceil_char_boundary((at + 160).min(s.len())); s[lo..hi].to_string() };
    format!("{at}바이트째(길이 Rust {} · Node {})\n  Rust: …{}…\n  Node: …{}…", x.len(), y.len(), around(a), around(b))
}

#[test]
fn prepared_matches_node() {
    assert!(results_dir().is_dir(), "정답지 폴더 {}가 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs", results_dir().display());
    let o = seam_opts(None);
    let mut compared = Vec::new();
    for f in fixtures() {
        let want = oracle_js(&f, "prep.json");
        let want_text = oracle_body(&f, "prep.json"); // 정답지 파일 본문의 바이트 그대로(고침 1회차 — 다시 적은 글이 아니라)
        let got_text = ctx::prepared_text(&inputs(&f), &o).unwrap_or_else(|e| panic!("자료 {}: 준비하지 못했습니다 — {e}", f.name));
        if got_text != want_text {
            let got = lay::prepared(&inputs(&f), &o).expect("같은 입력");
            assert_same(&f, "prep", &got, &js::to_json(&want));
            panic!("자료 {} · prep: 값은 같은데 덤프 글이 다릅니다(열쇠 차례 · 나눠 가짐) — {}", f.name, first_diff(&got_text, &want_text));
        }
        // 값으로도(브리프의 견줌 — 덤프 글이 같으면 늘 같다)
        assert_same(&f, "prep", &lay::prepared(&inputs(&f), &o).expect("같은 입력"), &js::to_json(&want));
        js::release(&want);
        compared.push(f.name.clone());
    }
    assert!(!compared.is_empty(), "견준 자료가 하나도 없습니다 — 자료 목록 · 정답지를 확인하세요");
    eprintln!("이음매 ② 앞(prep): 자료 {}개 같음 — {}", compared.len(), compared.join(" · "));
}

/// 칸의 경계(`HT.cellBounds` — 열거되지 않는 속성이라 `prep.json`에 들지 않는다): 정권마다 칸 참조 → { lo, hi, prev, next, succ }가
/// Node 벡터(`node prototype/scripts/bounds-vectors.mjs` → tests/fixtures/lay/cell-bounds.json — 정답지와 같은 시각 · 시간대)와 글자까지 같다.
#[test]
fn cell_bounds_match_node_vectors() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("lay").join("cell-bounds.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{} — 먼저 뽑으세요: node prototype/scripts/bounds-vectors.mjs ({e})", path.display()));
    let vectors = js::parse(&text).expect("cell-bounds.json은 JSON");
    assert_eq!(js::to_json(&vectors.get("now")), serde_json::json!(common::oracle::ORACLE_NOW), "벡터의 시각이 정답지와 다릅니다 — 다시 뽑으세요");
    let o = seam_opts(None);
    let list = fixtures();
    let (mut sets, mut bounds) = (0, 0);
    for fx in vectors.arr("fixtures").expect("fixtures").to_vec() {
        let name = js::to_str(&fx.get("name")).to_string();
        let f = list.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("벡터의 자료 {name}이(가) 자료 목록에 없습니다"));
        let c = ctx::context_of(&inputs(f), &o, false).unwrap_or_else(|e| panic!("자료 {name}: {e}"));
        let mut rows = Vec::new();
        for p in c.model.arr("periods").expect("periods").to_vec() {
            let b = p.as_obj().expect("정권은 객체").hidden("cellBounds");
            let Some(m) = b.as_map() else { continue };
            if m.is_empty() { continue; }
            let entries: Vec<js::V> = m.entries().into_iter().map(|(r, x)| {
                let succ: Vec<js::V> = x.arr("succ").expect("succ").to_vec().iter().map(|q| q.get("uid")).collect();
                js::V::Arr(js::Arr::new(vec![r, x.get("lo"), x.get("hi"), x.get("prev"), x.get("next"), js::V::Arr(js::Arr::new(succ))]))
            }).collect();
            bounds += entries.len();
            rows.push(js::V::Arr(js::Arr::new(vec![p.get("uid"), js::V::Arr(js::Arr::new(entries))])));
        }
        let got = js::stringify(&js::V::Arr(js::Arr::new(rows)));
        let want = js::stringify(&fx.get("periods"));
        if got != want { panic!("자료 {name} · 칸의 경계가 Node와 다릅니다 — {}", first_diff(&got, &want)); }
        c.release();
        sets += 1;
    }
    js::release(&vectors);
    assert!(sets > 0 && bounds > 0, "견준 경계가 없습니다");
    eprintln!("칸의 경계: 자료 {sets}개 · 경계 {bounds}개 같음");
}

/// 얹힌 몫 1: 모델 · 연표 상태는 서로 가리키는 고리라 버리기만 하면 새고, `js::release`로 풀면 살아 있는 그릇 수가 처음으로 돌아온다.
/// 정답지 자료 모두를 거듭(두 바퀴) 지어도 늘지 않음을 센다(객체 · Map · Set 그릇 수 — `js::live_containers`).
#[test]
fn prepared_releases_the_model_graph() {
    let o = seam_opts(None);
    let list = fixtures();
    assert!(!list.is_empty(), "자료가 없습니다");
    let base = js::live_containers();
    for round in 0..2 {
        for f in &list {
            let out = lay::prepared(&inputs(f), &o).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
            drop(out);
            assert_eq!(js::live_containers(), base, "{}바퀴 · 자료 {}: 풀고 난 뒤 살아 있는 그릇 수가 처음과 다릅니다(새는 고리)", round + 1, f.name);
        }
    }
    // 문맥은 버리기만 해도(Drop) 풀린다(고침 1회차 Minor 3) — 그 뒤에도 그대로
    let f = list.iter().find(|f| f.name == "lantern").unwrap_or(&list[0]);
    drop(ctx::context_of(&inputs(f), &o, false).expect("준비"));
    assert_eq!(js::live_containers(), base, "자료 {}: 문맥을 버렸는데(Drop) 그릇이 남았습니다", f.name);
    // 풀지 않으면 새는가(고리가 정말 있는가) — 그래야 위 검사가 뜻이 있다. 모델만 지어(문맥 없이) 그냥 버린다. 이 검사 스레드의 셈이라 다른 검사에 닿지 않는다(일부러 남김).
    let rc = lay::read::Ctx::new(&o).expect("읽기 문맥");
    let packs: Vec<js::V> = inputs(f).iter().map(|p| {
        let raw = lay::pack::raw_of(&rc, p, &mut Vec::new()).expect("원본");
        lay::read::normalize_pack(&rc, raw).pack.expect("정규화")
    }).collect();
    let model = lay::model::build_model(&rc, &packs, true).expect("모델");
    let held = js::live_containers();
    drop(model);
    drop(packs);
    let leaked = js::live_containers() - base;
    assert!(leaked > 0, "자료 {}: 풀지 않고 버렸는데 새지 않습니다 — 고리가 없다면 release 검사가 아무것도 보지 않는 것", f.name);
    eprintln!("풀기: 자료 {}개 × 2바퀴 뒤 그릇 수 그대로({base}) · 풀지 않고 버리면 {} 중 {leaked}개가 남음({})", list.len(), held - base, f.name);
}

/// 글 값(없으면 '').
fn text(v: &js::V) -> String { js::to_str(v).to_string() }
/// 배열 값의 원소(배열이 아니면 빈 목록).
fn items(v: &js::V) -> Vec<js::V> { if let js::V::Arr(a) = v { a.to_vec() } else { Vec::new() } }

/// 판정 R19(고침 1회차) · 과제 7 얹힌 몫 9: 합성 정답지 자료(`prototype/fixtures/oracle/synth.json` · `synth-patch.json` · `synth-patch2.json` — 가상 이름)가
/// 다른 정답지 자료가 닿지 않던 모델 갈래 여섯의 **하위 꼴마다** 실제로 닿는다 — 표지마다 ≥ 1. 모델은 위 검사로 Node와 같음을 이미 보았으므로
/// 여기서는 Rust 모델에서 센다(형식 4 사본 `@f4`도). 숨긴 대상의 종류는 패치 없는 바탕 자료(`synth` · `synth@f4`)의 모델에서 본다.
#[test]
fn synth_fixtures_reach_the_model_branches() {
    use archive_engine::lay::model::util::alt_dated;
    let o = seam_opts(None);
    let list = fixtures();
    let mut seen = 0;
    for (name, base_name) in [("synth+patch", "synth"), ("synth+patch@f4", "synth@f4")] {
        let f = list.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("자료 목록에 {name}이(가) 없습니다"));
        let c = ctx::context_of(&inputs(f), &o, false).unwrap_or_else(|e| panic!("자료 {name}: {e}"));
        let bf = list.iter().find(|f| f.name == base_name).unwrap_or_else(|| panic!("자료 목록에 {base_name}이(가) 없습니다"));
        let bc = ctx::context_of(&inputs(bf), &o, false).unwrap_or_else(|e| panic!("자료 {base_name}: {e}"));
        let base_by_uid = bc.model.get("byUid");
        let m = &c.model;
        let figures = items(&m.get("figures"));
        let services: Vec<js::V> = figures.iter().flat_map(|f| items(&f.get("services"))).collect();
        let warns: Vec<String> = items(&m.get("peopleWarnings")).iter().map(|w| text(&w.get("msg"))).collect();
        let warned = |part: &[&str]| warns.iter().filter(|w| part.iter().all(|p| w.contains(p))).count();
        let scopes = items(&m.get("scopes"));
        let scope_warned = |part: &str| scopes.iter().flat_map(|s| items(&s.get("warnings"))).filter(|w| text(w).contains(part)).count();
        let insts = items(&m.get("institutions"));
        let inst_warned = |part: &str| insts.iter().flat_map(|i| items(&i.get("warnings"))).filter(|w| text(w).contains(part)).count();
        let by_uid_v = m.get("byUid");
        let by_uid = by_uid_v.as_map().expect("byUid");
        let pack_scopes = items(&c.packs[0].get("scopes")).len();
        // 패치 DLC 둘(synth-patch · synth-patch2)의 패치 — 켠 차례
        let patches: Vec<js::V> = c.packs.iter().skip(1).flat_map(|p| items(&p.get("patches"))).collect();
        let patched: Vec<js::V> = by_uid.values().into_iter().filter(|x| js::truthy(&x.get("patchedBy"))).collect();
        let target = |t: &js::V| by_uid.get(t);
        let kind_is = |x: &js::V, k: &str| text(&x.get("kind")) == k;
        let has_birth = |a: &js::V| a.as_obj().is_some_and(|o| o.has("birth"));
        let patched_kind = |k: &str| patched.iter().filter(|x| kind_is(x, k)).count();
        let hidden_kind = |k: &str| patches.iter().filter(|p| {
            p.bool("hide") && target(&p.get("target")).is_undef() && kind_is(&base_by_uid.as_map().expect("바탕 byUid").get(&p.get("target")), k)
        }).count();
        // 날짜는 있으나 시작이 없는 이설: 사건 · 시대 대상이면 모델이 버린다(남은 이설 수 + 버린 수 = 패치의 이설 수)
        let alt_dropped = |k: &str| patches.iter().filter(|p| {
            let alts = items(&p.get("set").get("alternatives"));
            let gone = alts.iter().filter(|a| a.get("start").is_nullish() && alt_dated(a)).count();
            let t = target(&p.get("target"));
            gone > 0 && kind_is(&t, k) && items(&t.get("alternatives")).len() + gone == alts.len()
        }).count();
        const SPECS: [&str; 4] = ["treaty", "law", "election", "theme"];
        let rows: Vec<(&str, usize)> = vec![
            ("① 자동 활동 막대(섬긴 기록 없음 → 그 해 정권)", services.iter().filter(|s| matches!(s.get("auto"), js::V::Bool(true))).count()),
            ("① 자동 막대의 미정 끝(fromUnknown · toUnknown)", services.iter().filter(|s| s.bool("auto") && s.bool("fromUnknown") && s.bool("toUnknown")).count()),
            ("① 그 해 정권이 없어 막대 없음", figures.iter().filter(|f| items(&f.get("services")).is_empty() && f.get("polityUid").is_null() && !f.bool("lineageOnly")).count()),
            ("② 칸 사람 참조를 못 찾음", warned(&["의 사람 \"", "찾지 못했습니다."])),
            ("② 같은 이름의 인물 여럿(AMBIGUOUS) — 칸 사람", warned(&["의 사람 \"", "같은 이름의 인물이 여럿"])),
            ("② 같은 이름의 인물 여럿(AMBIGUOUS) — 부모", warned(&["부모 \"", "같은 이름의 인물이 여럿"])),
            ("② 자기 부모", warned(&["자기 자신"])),
            ("② 혈연 고리", warned(&["고리를 이룹니다"])),
            ("② 자리 이음 관계 어긋남", warned(&["어긋납니다"])),
            ("② 같은 사람인데 관계", warned(&["같은 사람인데"])),
            ("② 같은 이름의 지도자 여럿", warned(&["같은 이름의 지도자가 여럿"])),
            ("② 못 찾은 이름의 자리(missing)", items(&m.get("persons")).iter().filter(|p| p.bool("missing")).count()),
            ("② 단체 구성원 여럿(ambiguous)", items(&m.get("groups")).iter().flat_map(|g| items(&g.get("peopleList"))).filter(|r| r.bool("ambiguous")).count()),
            ("③ 자동 성씨(sn-해시)", items(&m.get("surnames")).iter().filter(|s| s.bool("auto")).count()),
            ("④ 대범위 기간 = 시대 구분(rangeFrom epoch)", scopes.iter().filter(|s| text(&s.get("rangeFrom")) == "epoch").count()),
            ("④ 대범위 기간 = 구성 정권(rangeFrom members)", scopes.iter().filter(|s| text(&s.get("rangeFrom")) == "members").count()),
            ("④ 이름 짐작(nameAuto)", scopes.iter().filter(|s| s.bool("nameAuto")).count()),
            ("④ 기간 짐작(startAuto · endAuto)", scopes.iter().filter(|s| s.bool("startAuto") && s.bool("endAuto")).count()),
            ("④ 기간을 정할 것이 없어 빠짐(continue)", pack_scopes.saturating_sub(scopes.len())),
            ("④ 알림: 본국 못 찾음 · 다른 트랙 · 본국도 구성 · 시대 구분 못 찾음(가장 적은 것)",
                [scope_warned("본국 \"없는 본국\""), scope_warned("다른 트랙에 있어 모이지"), scope_warned("구성 정권에도"), scope_warned("다른 트랙에 있어 그 줄"), scope_warned("시대 구분 \"")].into_iter().min().unwrap_or(0)),
            ("⑤ 자동 주제(theme-해시)", items(&m.get("themes")).iter().filter(|t| t.bool("auto")).count()),
            ("⑤ 사건 꼬리표의 자동 주제", items(&m.get("events")).iter().flat_map(|e| items(&e.get("themeRefs"))).filter(|r| r.bool("auto")).count()),
            ("⑤ 제도 알림 — 사전에 없는 주제", inst_warned("주제 사전에 없습니다")),
            ("⑤ 제도 알림 — 못 찾은 나라", inst_warned("연표에서 찾지 못했습니다")),
            ("⑥ 패치가 닿은 항목 — 사건", patched_kind("event")),
            ("⑥ 패치가 닿은 항목 — 시대", patched_kind("period")),
            ("⑥ 패치가 닿은 항목 — 인물", patched_kind("figure")),
            ("⑥ 패치가 닿은 항목 — 제도", patched_kind("institution")),
            ("⑥ 패치가 닿은 항목 — 단체", patched_kind("group")),
            ("⑥ 같은 대상을 둘째 패치 DLC가 다시 고침(patchedBy 이어짐)", patched.iter().filter(|x| {
                let b = items(&x.get("patchedBy"));
                b.len() >= 2 && text(&b[0].get("id")) != text(&b[b.len() - 1].get("id"))
            }).count()),
            ("⑥ 숨김(hide) — 사건", hidden_kind("event")),
            ("⑥ 숨김(hide) — 시대", hidden_kind("period")),
            ("⑥ 숨김(hide) — 인물", hidden_kind("figure")),
            ("⑥ 종류 → polityKind(before.polityKind)", patched.iter().filter(|x| items(&x.get("patchedBy")).iter().any(|b| b.get("before").as_obj().is_some_and(|o| o.has("polityKind")))).count()),
            ("⑥ 세기 글 → 연대 폭(centuryRanges)", patched.iter().filter(|x| js::truthy(&x.get("startRange")) && js::truthy(&x.get("endRange"))).count()),
            ("⑥ 끝 없는 점 사건의 세기 시작 — 연대 폭 없음(기간 아님)", patched.iter().filter(|x| {
                kind_is(x, "event") && text(&x.get("startAt")).ends_with("세기") && x.get("startRange").is_nullish() && x.get("end").is_nullish()
            }).count()),
            ("⑥ 이설 거르기(시대 — 생몰 칸 뺌)", patched.iter().filter(|x| kind_is(x, "period") && !items(&x.get("alternatives")).is_empty() && !items(&x.get("alternatives")).iter().any(has_birth)).count()),
            ("⑥ 날짜는 있고 시작이 없는 이설을 버림 — 시대", alt_dropped("period")),
            ("⑥ 날짜는 있고 시작이 없는 이설을 버림 — 사건", alt_dropped("event")),
            ("⑥ 인물 이설은 그대로(생몰 칸 남음)", patched.iter().filter(|x| kind_is(x, "figure") && items(&x.get("alternatives")).iter().any(has_birth)).count()),
            ("⑥ 인물의 시작 · 끝(세기 글이어도 연대 폭 · derive 없음)", patched.iter().filter(|x| {
                kind_is(x, "figure") && text(&x.get("startAt")).ends_with("세기") && x.get("startRange").is_nullish()
            }).count()),
            ("⑥ 진행 중으로(ongoing)", patched.iter().filter(|x| kind_is(x, "period") && matches!(x.get("ongoing"), js::V::Bool(true))).count()),
            ("⑥ 제도 주제 목록 → 첫째", patches.iter().filter(|p| {
                let (th, t) = (items(&p.get("set").get("theme")), target(&p.get("target")));
                !th.is_empty() && kind_is(&t, "institution") && text(&t.get("theme")) == text(&th[0])
            }).count()),
            ("⑥ 제도 빈 주제 목록 → 대상의 주제 그대로", patches.iter().filter(|p| {
                let t = target(&p.get("target"));
                matches!(p.get("set").get("theme"), js::V::Arr(a) if a.is_empty()) && kind_is(&t, "institution") && !text(&t.get("theme")).is_empty()
            }).count()),
            ("⑥ 조약 · 법만 담은 패치는 버림", patches.iter().filter(|p| { let t = target(&p.get("target")); !t.is_undef() && !js::truthy(&t.get("patchedBy")) }).count()),
            ("⑥ 조약 · 법 · 선거 · 주제를 버리고 남은 고침은 계속(시대)", patches.iter().filter(|p| {
                let set = p.get("set");
                let spec = set.as_obj().is_some_and(|o| SPECS.iter().any(|k| o.has(*k)));
                let t = target(&p.get("target"));
                spec && kind_is(&t, "period") && items(&t.get("patchedBy")).iter().any(|b| {
                    b.get("before").as_obj().is_some_and(|o| o.keys().iter().any(|k| !SPECS.contains(&k.as_str().as_ref())) && SPECS.iter().all(|k| !o.has(*k)))
                })
            }).count()),
            ("⑥ 대상이 없는 패치(건너뜀)", patches.iter().filter(|p| !p.bool("hide") && target(&p.get("target")).is_undef()).count()),
        ];
        eprintln!("합성 자료 {name}의 모델 갈래 표지:");
        for (label, n) in &rows { eprintln!("  {label}: {n}"); }
        let missing: Vec<&str> = rows.iter().filter(|r| r.1 == 0).map(|r| r.0).collect();
        assert!(missing.is_empty(), "자료 {name}: 닿지 않은 갈래 — {}", missing.join(" · "));
        seen += 1;
    }
    assert_eq!(seen, 2);
}

/// 예전의 알려진 거절(과제 7 얹힌 몫 9 — 과제 Y가 걷음): `HT.formatRange`가 인물이면 가는 `HT.figureRange`도 이제 옮긴 길(`web::when` — 갈래 C의 판)이다.
/// Node의 답(`HT.formatRange` — 작업 폴더의 웹 코드로 2026-10-22 확인): 인물 `"100년 ~ 150년"` · 시대 `"100년 ~ 150년"`.
#[test]
fn figure_range_is_now_ported() {
    use archive_engine::lay::web::when::format_range;
    let rc = lay::read::Ctx::new(&seam_opts(None)).expect("읽기 문맥");
    let fig = js::parse(r#"{"kind":"figure","name":"가상 인물","start":100,"end":150,"endY":150}"#).unwrap();
    assert_eq!(format_range(&rc, &fig), "100년 ~ 150년");
    let item = js::parse(r#"{"kind":"period","name":"가상 나라","start":100,"end":150,"endY":150}"#).unwrap();
    assert_eq!(format_range(&rc, &item), "100년 ~ 150년");
}

/// 예전의 알려진 거절(고침 1회차 Minor 4 — 과제 Y가 걷음): 지도 장면의 '그해에 없던 나라' 알림이 그 나라의 날짜 글을 `HT.cal.describe`로 적는 길도 이제 옮긴 길 —
/// Node와 같은 글(`… (150년 3월 1일 ~ 200년).` — 작업 폴더의 웹 코드로 2026-10-22 확인). 지은 그래프는 문맥을 버리면(Drop) 풀린다(Minor 3).
#[test]
fn describe_in_model_warning_is_now_ported_and_released() {
    let json = r#"{"format":"history-timeline-dlc","formatVersion":3,"id":"t-describe","name":"거절 검사","version":"1.0.0",
        "tracks":[{"id":"t","name":"가상 줄"}],"periods":[{"id":"p","track":"t","name":"늦은 나라","start":"0150-03-01","end":200}],
        "maps":[{"id":"m","name":"가상 지도","crs":"image","size":[100,100],"regions":[{"id":"r","name":"구역","shape":[[0,0],[10,0],[10,10]]}],
        "frames":[{"year":120,"owners":{"r":{"track":"t","polity":"늦은 나라"}}}]}]}"#;
    let pack_of = |text: String| archive_engine::lay::PackIn { name: "describe.json".into(), bytes: text.into_bytes() };
    let base = js::live_containers();
    let c = ctx::context_of(&[pack_of(json.to_string())], &seam_opts(None), false).expect("날짜 글이 있어도 짓는다");
    let w = text(&items(&c.model.get("maps"))[0].get("warnings").get(&0.0));
    assert_eq!(w, "120년 장면의 구역 \"r\" 주인 \"늦은 나라\"은(는) 그해에 연표에 없던 나라입니다 (150년 3월 1일 ~ 200년).");
    drop(c);
    assert_eq!(js::live_containers(), base, "문맥을 버리면(Drop) 그래프가 풀려야 합니다");
    // 같은 장면이라도 날짜 글이 없으면(해만) 해만 적는다
    let plain = json.replace("\"0150-03-01\"", "150");
    let c = ctx::context_of(&[pack_of(plain.clone())], &seam_opts(None), false).expect("날짜 글이 없으면 짓는다");
    let w = text(&items(&c.model.get("maps"))[0].get("warnings").get(&0.0));
    assert_eq!(w, "120년 장면의 구역 \"r\" 주인 \"늦은 나라\"은(는) 그해에 연표에 없던 나라입니다 (150년 ~ 200년).");
    drop(c);
    assert_eq!(js::live_containers(), base, "문맥을 버리면(Drop) 그래프가 풀려야 합니다");
    // 줄 배정(과제 7 — 옮긴 길)까지 지어도 문맥을 버리면 풀림
    drop(ctx::context_of(&[pack_of(plain)], &seam_opts(None), true).expect("줄 배정까지 짓는다"));
    assert_eq!(js::live_containers(), base, "줄 배정 뒤 문맥을 버리면(Drop) 그래프가 풀려야 합니다");
}

/// JS라면 던졌을 곳(Minor 6): 객체가 아닌 값에 칸 쓰기 · Map이 아닌 표(`model.docs`)는 잘못으로 남아 `build_model`이 오류로 끝낸다(지금 자료로는 닿지 않는다 —
/// 잇기 함수를 직접 불러 본다).
#[test]
fn would_throw_spots_become_errors() {
    use archive_engine::lay::model::util;
    util::take_fault();
    let _ = util::ob(&js::V::Null);
    assert!(util::take_fault().is_some_and(|m| m.contains("객체가 아닌 값(object)")), "null에 쓰기는 잘못이어야 합니다");
    let _ = util::ob(&js::V::from("글"));
    assert!(util::take_fault().is_some_and(|m| m.contains("(string)")), "글에 쓰기(엄격 모드 TypeError)도 잘못이어야 합니다");
    let rc = archive_engine::lay::read::Ctx::new(&seam_opts(None)).unwrap();
    let model = js::parse(r#"{"periods":[],"figures":[],"lineageFigures":[],"docs":null}"#).unwrap();
    archive_engine::lay::link::link_houses(&rc, &model, &[]);
    assert!(util::take_fault().is_some_and(|m| m.contains("model.docs이(가) Map이 아닙니다")), "docs가 Map이 아니면 잘못이어야 합니다(조용히 끝나지 않음)");
    assert!(util::take_fault().is_none(), "잘못은 꺼내면 비워집니다");
}

/// kin-resolve(`357e5a3` — 2026-10-25 통합 가지에 합침)의 혈연 부모 잇기 갈래는 정답지 자료 어디에도 닿지 않아(합친 뒤 정답지 2246 파일이 바이트까지 그대로),
/// 가상 자료 `tests/fixtures/lay/kin-resolve.json`으로 Rust 거울(`lay/link/people.rs`의 `resolve` · `pick_leader`)을 본다. 기대값은 Node의 답이다 —
/// `oracle/one.mjs --name=synth --packs=<이 자료> --seams=prep`(작업 폴더의 웹 코드 · 2026-10-25 확인)의 사람 자리 · 자리 이음과 같고, 그 prep 덤프와 Rust
/// `prepared_text`도 바이트까지 같았다(`HT_KIN_RESOLVE_OUT=<폴더>`를 주면 Rust 덤프를 `<폴더>/prep-rust.json`에 써서 다시 견줄 수 있다).
/// - ① 같은 나라 지도자가 먼저: 가람 한솔왕의 부모 '원도왕' → 다른 시대(1500 ~ 1550)의 같은 이름 인물이 아니라 가람 원도왕 칸(옛 길은 인물)
/// - ② 인물이 이 나라가 있던 때 살았으면 그 인물 그대로: 가람 늘봄왕의 부모 '바다왕' → 인물 바다왕(1050 ~ 1090 — 같은 나라의 바다왕 칸이 아님)
/// - ③ 같은 이름 지도자 여럿 → 생몰과 가까운 때: 인물 솔뫼(1010 ~ 1060)의 부모 '현명왕' → 가람 현명왕(1000 ~ 1020) · 다솜 다솜왕(1490 ~ 1510)의 부모와
///   앞 지도자 '현명왕' → 나래 현명왕(1450 ~ 1470)(옛 길은 셋 다 '같은 이름의 지도자가 여럿' 알림 + 이름의 자리)
#[test]
fn kin_resolve_prefers_own_polity_leader_and_near_reign() {
    let json = include_str!("fixtures/lay/kin-resolve.json");
    let pack = archive_engine::lay::PackIn { name: "kin-resolve.json".into(), bytes: json.as_bytes().to_vec() };
    let o = seam_opts(None);
    if let Some(dir) = std::env::var_os("HT_KIN_RESOLVE_OUT") {
        let text = ctx::prepared_text(std::slice::from_ref(&pack), &o).expect("준비 덤프");
        std::fs::write(std::path::Path::new(&dir).join("prep-rust.json"), text).expect("Rust 덤프 쓰기");
    }
    let c = ctx::context_of(std::slice::from_ref(&pack), &o, false).expect("가상 혈연 자료를 짓는다");
    let parents = |key: &str| -> Vec<String> {
        let nd = items(&c.model.get("persons")).into_iter().find(|p| text(&p.get("key")) == key).unwrap_or_else(|| panic!("사람 자리 {key}가 없습니다"));
        items(&nd.get("parents")).iter().map(|e| text(&e.get("node").get("key"))).collect()
    };
    let cell = |p: &str, i: usize| format!("c:t-kin-resolve/{p}|leader:{i}");
    assert_eq!(parents(&cell("p-garam", 2)), [cell("p-garam", 0)], "① 같은 나라의 원도왕 칸이 다른 시대의 같은 이름 인물보다 먼저");
    assert_eq!(parents(&cell("p-garam", 4)), ["f:t-kin-resolve/f-bada"], "② 이 나라가 있던 때 산 인물이면 인물 그대로");
    assert_eq!(parents("f:t-kin-resolve/f-solmoe"), [cell("p-garam", 3)], "③ 인물의 생몰과 가까운 때 다스린 현명왕");
    assert_eq!(parents(&cell("p-dasom", 0)), [cell("p-narae", 0)], "③ 지도자 칸의 기간과 가까운 때 다스린 현명왕");
    let from = c.model.get("accessionFrom");
    let from = from.as_map().expect("accessionFrom은 Map");
    assert_eq!(text(&from.get(&js::V::from(cell("p-dasom", 0))).get("key")), cell("p-narae", 0), "③ 앞 지도자 찾기도 가까운 때");
    let warns: Vec<String> = items(&c.model.get("peopleWarnings")).iter().map(|w| text(&w.get("msg"))).collect();
    assert!(warns.is_empty(), "알림이 없어야 합니다(옛 길은 '같은 이름의 지도자가 여럿' 셋): {warns:?}");
    assert!(!items(&c.model.get("persons")).iter().any(|p| p.bool("missing")), "이름의 자리(missing)가 없어야 합니다");
}

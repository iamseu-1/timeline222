//! 한 벌 P3 과제 7 — 줄 배정(이음매 ② 뒤): 자료마다 Rust의 `lay::laid`(정규화 → 모델 → `contextOf`의 준비 → 트랙마다 `_layoutTrack` → 연표 깊이)가
//! Node의 `rows.json`(`contextOf` 그대로의 `seam({ tracks, depth, cats, proxies, cityUses, scopes, model })`)과 차이 0이다 —
//! 값으로(`lay::same::diff`) 그리고 덤프 글의 바이트로(처음 만난 경로 · `$ref`까지 — 줄 배정이 띠 · 사건 · 인물 막대에 적는 칸의 열쇠 차례와 나눠 가짐이 JS와 같아야 같다).
//! 정답지: `node prototype/scripts/layout-oracle.mjs --seams=rows`(→ `prototype/results/oracle/<자료>/rows.json`).
mod common;
use archive_engine::lay::{self, ctx, js};
use common::oracle::{assert_same, fixtures, inputs, oracle_body, oracle_js, results_dir, seam_opts};

/// 두 글의 처음 다른 자리와 그 둘레(차이를 좇을 때).
fn first_diff(a: &str, b: &str) -> String {
    let (x, y) = (a.as_bytes(), b.as_bytes());
    let at = x.iter().zip(y.iter()).position(|(p, q)| p != q).unwrap_or(x.len().min(y.len()));
    let around = |s: &str| { let lo = s.floor_char_boundary(at.saturating_sub(200)); let hi = s.ceil_char_boundary((at + 200).min(s.len())); s[lo..hi].to_string() };
    format!("{at}바이트째(길이 Rust {} · Node {})\n  Rust: …{}…\n  Node: …{}…", x.len(), y.len(), around(a), around(b))
}

#[test]
fn laid_matches_node() {
    assert!(results_dir().is_dir(), "정답지 폴더 {}가 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs", results_dir().display());
    let o = seam_opts(None);
    let mut compared = Vec::new();
    for f in fixtures() {
        let want = oracle_js(&f, "rows.json");
        let want_text = oracle_body(&f, "rows.json"); // 정답지 파일 본문의 바이트 그대로
        let got = lay::laid(&inputs(&f), &o).unwrap_or_else(|e| panic!("자료 {}: 줄 배정을 하지 못했습니다 — {e}", f.name));
        assert_same(&f, "rows", &got, &js::to_json(&want)); // 값(브리프의 견줌) — 다르면 경로가 든 차이
        let got_text = ctx::laid_text(&inputs(&f), &o).expect("같은 입력");
        if got_text != want_text {
            panic!("자료 {} · rows: 값은 같은데 덤프 글이 다릅니다(열쇠 차례 · 나눠 가짐) — {}", f.name, first_diff(&got_text, &want_text));
        }
        js::release(&want);
        compared.push(f.name.clone());
    }
    assert!(!compared.is_empty(), "견준 자료가 하나도 없습니다 — 자료 목록 · 정답지를 확인하세요");
    eprintln!("이음매 ② 뒤(rows): 자료 {}개 같음 — {}", compared.len(), compared.join(" · "));
}

/// 과제 16b 불변식(16b 검토 ② M5): 변형 모듈은 변형마다 **그 트랙만** 다시 배치하고 되돌리며 변형이 없으면 배치를 건드리지 않는다 — 그 뒤 문맥은 모든 트랙을
/// 한 번 더 배치한 문맥과 같아야 한다(줄 배정은 트랙 국소 · 되돌림이 빠짐없음). 자료마다 `variants`까지 모듈을 돌린 덤프 = 거기에 `layout_all`을 한 번 더 돌린 덤프.
#[test]
fn variants_leave_the_layout_as_a_full_relayout_would() {
    use archive_engine::lay::{export as ex, module_index, MODULES};
    let o = seam_opts(None);
    let upto = module_index("variants").expect("variants 모듈") + 1;
    let mut n = 0;
    for f in fixtures() {
        let mut c = ctx::context_of(&inputs(&f), &o, true).expect("줄 배정까지");
        c.shared = js::Obj::new();
        c.notes = js::Obj::new();
        let mut out = ex::initial_out(&c);
        for m in &MODULES[..upto] {
            (m.contribute)(&mut c, &mut out).unwrap_or_else(|e| panic!("자료 {} · {}: {e}", f.name, m.name));
        }
        let after_variants = ctx::dump_text(&c);
        lay::track::layout_all(&mut c).expect("한 번 더 배치");
        let relaid = ctx::dump_text(&c);
        if after_variants != relaid {
            panic!("자료 {}: 변형 모듈 뒤 문맥이 모든 트랙을 다시 배치한 것과 다릅니다 — {}", f.name, first_diff(&after_variants, &relaid));
        }
        n += 1;
    }
    assert!(n >= 25, "견준 자료가 너무 적습니다: {n}");
}

/// 값 · 글 도움.
fn items(v: &js::V) -> Vec<js::V> { if let js::V::Arr(a) = v { a.to_vec() } else { Vec::new() } }
fn num(v: &js::V) -> f64 { js::to_num(v) }

/// 정답지 자료(합성 자료 `synth` · `synth+patch`의 서녘 줄 — 과제 7이 더함 — 포함)가 내보내기에서 닿을 수 있는 줄 배정 갈래에 실제로 닿는다 — 표지마다 ≥ 1.
/// 줄 배정이 Node와 같음은 [`laid_matches_node`]가 보므로 여기서는 Rust의 줄 배정 결과에서 센다. 이음매 ②(`contextOf`)의 보기 조건이 닿지 않는 갈래는 세지 않는다 —
/// 그릇 켬 · 소속 / 단체 펼침은 과제 14(변형 REPLAY), 렌즈(`themeLens`) · 판(`tr.board` · `_boardTr`)은 과제 15(`lens` · `boards` 모듈이 다시 배치)가 처음 견주고,
/// 민족 · 트랙 접음 · 조감 · 밀도 · 표시 끔은 내보내기가 쓰지 않는 보기 상태다(보고서의 목록).
#[test]
fn fixtures_reach_the_layout_branches() {
    let o = seam_opts(None);
    let mut c: std::collections::BTreeMap<&str, usize> = std::collections::BTreeMap::new();
    let mut add = |k: &'static str, v: usize| *c.entry(k).or_default() += v;
    for f in fixtures() {
        let cx = ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        add("민족 rowOrder 북 → 남", items(&cx.model.get("peoples")).iter().filter(|pe| js::to_str(&pe.get("rowOrder")) == "northSouth").count());
        for tr in items(&cx.tl.get("tracks")) {
            let ps = items(&tr.get("periods"));
            let truthy = |p: &js::V, k: &str| js::truthy(&p.get(k));
            add("기관(overlays)", items(&tr.get("overlays")).len());
            add("구역 탭이 단을 나눔(zoneRowLanes > 1)", tr.get("zoneRowLanes").as_map().map_or(0, |m| m.values().iter().filter(|n| num(n) > 1.0).count()));
            add("바탕 문화(_under)", ps.iter().filter(|p| truthy(p, "_under")).count());
            add("바탕 문화가 여러 줄에 깔림", ps.iter().filter(|p| truthy(p, "_under") && items(&p.get("_underRows")).len() > 1).count());
            add("바탕 문화 → 바탕 문화(연쇄)", ps.iter().filter(|p| truthy(p, "_under") && items(&p.get("successors")).iter().any(|e| truthy(&e.get("to"), "_under"))).count());
            add("숨은 소속(_hidden)", ps.iter().filter(|p| truthy(p, "_hidden")).count());
            add("곧바로 이음(_seamL)", ps.iter().filter(|p| truthy(p, "_seamL")).count());
            add("매단 이름표 줄(hangRowLanes)", tr.get("hangRowLanes").as_map().map_or(0, |m| m.len()));
            add("품은 칸(inLanes > 0)", ps.iter().filter(|p| truthy(p, "_dep") && num(&p.get("_dep").get("inLanes")) > 0.0 && !truthy(p, "_hidden")).count());
            add("공통 줄(commonRow)", usize::from(num(&tr.get("commonRow")) >= 0.0));
            let evs = items(&tr.get("events"));
            add("점 사건의 정밀도 구간(_ps)", evs.iter().filter(|e| matches!(e.get("_ps"), js::V::Arr(_))).count());
            add("세기 점 사건(_psCent)", evs.iter().filter(|e| matches!(e.get("_psCent"), js::V::Bool(true))).count());
            add("사건 자리(spot)", evs.iter().filter(|e| matches!(e.get("spot"), js::V::Num(x) if x.is_finite())).count());
            add("부모 사건(eventParents)", items(&tr.get("eventParents")).len());
            let figs = items(&tr.get("figures"));
            add("인물 둘째 단(lvl 1)", figs.iter().filter(|x| num(&x.get("lvl")) == 1.0).count());
            add("인물 넘침(lvl −1 · 줄 있음)", figs.iter().filter(|x| num(&x.get("lvl")) == -1.0 && !x.get("row").is_nullish()).count());
            add("인물 줄 없음(기관 · 바탕 문화를 섬김)", figs.iter().filter(|x| x.get("row").is_nullish()).count());
            add("인물 띠 = 보이는 상위(숨은 소속을 섬김)", figs.iter().filter(|x| js::truthy(&x.get("band")) && !js::strict_eq(&x.get("band"), &x.get("s").get("polity"))).count());
            let g = tr.get("geo");
            add("글줄 1(줄 7 이상)", usize::from(num(&g.get("lines")) == 1.0));
            add("왕조 칸", usize::from(num(&g.get("dynastyH")) > 0.0));
            add("내각 칸", usize::from(num(&g.get("cabinetH")) > 0.0));
            add("기관 칸", usize::from(num(&g.get("organH")) > 0.0));
            add("예속 칸", usize::from(num(&g.get("depH")) > 0.0));
            add("기간 막대 3단", usize::from(num(&g.get("railLevels")) == 3.0));
            add("분류별 글줄(rowCats)", items(&tr.get("rowCats")).iter().filter(|x| js::truthy(x)).count());
            let geos = items(&tr.get("geos"));
            for (k, label) in [("phaseH", "시기 단"), ("rankH", "지위 단"), ("powerH", "집권 단"), ("realH", "실권 단")] { add(label, geos.iter().filter(|x| num(&x.get(k)) > 0.0).count()); }
            add("인물 단 둘(figLevels 2)", geos.iter().filter(|x| num(&x.get("figLevels")) == 2.0).count());
            let groups = items(&tr.get("groups"));
            add("문화 묶음", groups.iter().filter(|x| js::truthy(&x.get("culture"))).count());
            add("하위 민족 묶음(depth ≥ 1)", groups.iter().filter(|x| num(&x.get("depth")) >= 1.0).count());
            let rows = items(&tr.get("rowPeriods"));
            add("줄 채우기(이음 없이 한 줄)", rows.iter().map(|r| { let r = items(r); (1..r.len()).filter(|&k| !items(&r[k].get("predecessors")).iter().any(|e| js::strict_eq(&e.get("from"), &r[k - 1]))).count() }).sum());
            let mut starts: Vec<f64> = ps.iter().filter(|p| !truthy(p, "_hidden") && !truthy(p, "_member") && !truthy(p, "_overlay") && !truthy(p, "_under")).map(|p| { let r = p.get("startRange"); num(&if js::truthy(&r) { r.get(&0.0) } else { p.get("start") }) }).collect();
            starts.sort_by(f64::total_cmp);
            let max_grp = starts.chunk_by(|a, b| a == b).map(<[f64]>::len).max().unwrap_or(0);
            add("같은 해 시작 무리(2 ~ 8 — 배치 훑기)", usize::from((2..=8).contains(&max_grp)));
            add("같은 해 시작 무리 9 이상(욕심 — 첫 줄만)", usize::from(max_grp >= 9));
            add("_laneAll 셋째 단", ps.iter().filter(|p| num(&p.get("_laneAll")) >= 2.0).count());
        }
        drop(cx);
    }
    eprintln!("줄 배정 갈래 표지(정답지 자료 모두):");
    for (k, v) in &c { eprintln!("  {k}: {v}"); }
    let missing: Vec<&str> = c.iter().filter(|(_, v)| **v == 0).map(|(k, _)| *k).collect();
    assert!(missing.is_empty(), "닿지 않은 줄 배정 갈래 — {}", missing.join(" · "));
}

/// 집합 보기의 판 트랙(`tr.board`)은 갈래 E(과제 15)가 판 갈래를 옮겨 이제 거절하지 않는다 — 그 길의 견줌은 `lay_m_boards`(`upto-boards` — 판을 세우는 `boards` 모듈).
/// 여기서는 판의 줄 목록(`tr.board.rows` — `_boardPlan`이 늘 지음)이 없는 판 트랙이 JS처럼 오류가 되고(조용히 빈 판이 아님) 오류 길에서도 문맥을 버리면 그래프가 풀림을 본다.
#[test]
fn board_without_rows_is_an_error() {
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "synth").unwrap_or(&list[0]);
    let base = js::live_containers();
    let mut c = ctx::context_of(&inputs(f), &seam_opts(None), false).expect("준비");
    let tr = c.tl.get("tracks").get(&0.0);
    tr.as_obj().expect("트랙").set("board", js::Obj::new());
    let err = archive_engine::lay::track::layout_track(&mut c, &tr).err().expect("줄 목록 없는 판 트랙은 오류여야 합니다").to_string();
    assert!(err.contains("tr.board.rows"), "{err}");
    drop(tr);
    drop(c);
    assert_eq!(js::live_containers(), base, "오류 뒤 문맥을 버리면 그래프가 풀려야 합니다");
}

/// 다시 배치 멱등(고침 1회차 Minor 2): 줄 배정을 마친 문맥에서 모든 트랙을 한 번 더 배치해도 `rows.json`과 값 · 바이트가 같다 —
/// 변형 REPLAY(과제 14) · 렌즈 · 판(과제 15)이 같은 트랙을 다시 배치하는 데 기댄다(이미 적힌 `_ps` 기억 · 열쇠 자리 · `_seamL` 다시 씀).
#[test]
fn relayout_is_idempotent() {
    let o = seam_opts(None);
    let mut seen = 0;
    for f in fixtures() {
        let mut c = ctx::context_of(&inputs(&f), &o, true).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name));
        archive_engine::lay::track::layout_all(&mut c).unwrap_or_else(|e| panic!("자료 {}: 다시 배치하지 못했습니다 — {e}", f.name));
        let want = oracle_js(&f, "rows.json");
        assert_same(&f, "rows(다시 배치)", &ctx::dump(&c), &js::to_json(&want));
        let got_text = ctx::dump_text(&c);
        let want_text = oracle_body(&f, "rows.json");
        if got_text != want_text { panic!("자료 {} · rows(다시 배치): 값은 같은데 덤프 글이 다릅니다 — {}", f.name, first_diff(&got_text, &want_text)); }
        js::release(&want);
        seen += 1;
    }
    assert!(seen > 0);
    eprintln!("다시 배치 멱등: 자료 {seen}개 같음");
}

/// JS라면 던졌을 곳(고침 1회차 Minor 1): 줄 배정이 객체가 아닌 값에 칸을 쓰면(`model::util::fault`) 조용히 넘어가지 않고 오류 — 트랙의 정권 목록에 null을 넣어 본다
/// (JS는 `new Map(tr.periods.map(p => [p.uid, p]))`에서 TypeError). 오류 길에서도 문맥을 버리면 그래프가 풀린다.
#[test]
fn layout_faults_become_errors() {
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "synth").unwrap_or(&list[0]);
    let base = js::live_containers();
    let mut c = ctx::context_of(&inputs(f), &seam_opts(None), false).expect("준비");
    archive_engine::lay::model::util::take_fault();
    c.tl.get("tracks").get(&0.0).arr("periods").expect("정권 목록").push(js::V::Null);
    let err = archive_engine::lay::track::layout_all(&mut c).err().expect("잘못이면 오류여야 합니다").to_string();
    assert!(err.contains("줄 배정을 하지 못했습니다") && err.contains("JS라면 TypeError"), "{err}");
    assert!(archive_engine::lay::model::util::take_fault().is_none(), "잘못은 오류로 꺼내져 비워져야 합니다");
    drop(c);
    assert_eq!(js::live_containers(), base, "오류 뒤 문맥을 버리면 그래프가 풀려야 합니다");
}

/// 줄 배정이 띠 · 사건 · 인물 막대 사이에 더 건 고리(`_host` · `_seamL` · `_dep` · `band` …)도 문맥을 버리면 풀린다 — 살아 있는 그릇 수가 처음으로 돌아온다.
#[test]
fn laid_releases_the_graph() {
    let o = seam_opts(None);
    let list = fixtures();
    assert!(!list.is_empty(), "자료가 없습니다");
    let base = js::live_containers();
    for f in &list {
        drop(lay::laid(&inputs(f), &o).unwrap_or_else(|e| panic!("자료 {}: {e}", f.name)));
        assert_eq!(js::live_containers(), base, "자료 {}: 줄 배정 뒤 풀고 난 그릇 수가 처음과 다릅니다(새는 고리)", f.name);
    }
}

/// 과제 Y(갈래 E 덧붙임이 track.rs라 남긴 '조용히 이어 가는 길' 셋): 판 갈래에서 JS가 TypeError를 던지는 꼴은 오류 — boards가 그 판을 뺀다.
/// ① `_boardPlan` — `tl.board.members`가 순회되지 않음(`for … of`) · 접힘 기억(`foldedPeoples`)은 되돌린 채 · ①′ Set이면 계획이 선 뒤 `v.members.filter` ② `_boardVisit` — 판 줄의 `periods`가 배열이 아님(`r.periods.filter`)
/// ③ `_boardBranch` — 판의 `view`가 없음(`v.start`). 정답지 자료는 이 길을 밟지 않는다(boards가 늘 그 꼴로 지음) — 문맥을 손으로 고친다. 오류 뒤 문맥을 버리면 그래프가 풀린다.
#[test]
fn board_shape_faults_are_errors() {
    use archive_engine::lay::track::{board_plan, layout_track};
    let list = fixtures();
    let f = list.iter().find(|f| f.name == "synth").unwrap_or(&list[0]);
    let base = js::live_containers();
    {
        let mut c = ctx::context_of(&inputs(f), &seam_opts(None), true).expect("줄 배정까지");
        let keep = c.tl.get("foldedPeoples");
        c.tl.as_obj().expect("tl").set("board", js::Obj::new()); // members 없음
        let err = board_plan(&mut c).err().expect("members가 배열이 아니면 오류여야 합니다").to_string();
        assert!(err.contains("_boardPlan") && err.contains("members"), "{err}");
        assert!(js::strict_eq(&c.tl.get("foldedPeoples"), &keep), "접힘 기억(foldedPeoples)이 되돌아오지 않았습니다");
        c.tl.as_obj().expect("tl").set("board", js::V::Null);
    }
    {
        // ①′(16b 틀 손질 검토): members가 Set이면 줄 계획(`for … of`)은 돌지만 계획이 서면 JS는 `v.members.filter`에서 TypeError — 조용히 판을 짓지 않는다.
        let mut c = ctx::context_of(&inputs(f), &seam_opts(None), true).expect("줄 배정까지");
        let tr = c.tl.get("tracks").get(&0.0);
        let p = lay::model::util::list(&tr.get("periods")).into_iter().find(|p| !p.bool("_hidden") && !p.get("_row").is_nullish()).expect("줄에 놓인 정권");
        let members = js::Set::new();
        members.add(p.get("uid"));
        let board = js::Obj::new();
        board.set("members", js::V::Set(members));
        c.tl.as_obj().expect("tl").set("board", board);
        let err = board_plan(&mut c).err().expect("members가 Set이면 계획 뒤에 오류여야 합니다").to_string();
        assert!(err.contains("v.members") && err.contains("filter"), "{err}");
        c.tl.as_obj().expect("tl").set("board", js::V::Null);
        drop((tr, p));
    }
    {
        let mut c = ctx::context_of(&inputs(f), &seam_opts(None), false).expect("준비");
        let tr = c.tl.get("tracks").get(&0.0);
        let row = js::Obj::new();
        row.set("periods", js::Obj::new()); // 배열이 아님
        let board = js::Obj::new();
        board.set("rows", js::V::Arr(js::Arr::new(vec![js::V::Obj(row)])));
        tr.as_obj().expect("트랙").set("board", board);
        let err = layout_track(&mut c, &tr).err().expect("판 줄의 periods가 배열이 아니면 오류여야 합니다").to_string();
        assert!(err.contains("_boardVisit") && err.contains("periods"), "{err}");
        drop(tr);
    }
    {
        let mut c = ctx::context_of(&inputs(f), &seam_opts(None), false).expect("준비");
        let tr = c.tl.get("tracks").get(&0.0);
        let ps = lay::model::util::list(&tr.get("periods"));
        assert!(!ps.is_empty(), "트랙에 정권이 없습니다");
        let row = js::Obj::new();
        row.set("periods", js::V::Arr(js::Arr::new(ps)));
        let board = js::Obj::new(); // view 없음
        board.set("rows", js::V::Arr(js::Arr::new(vec![js::V::Obj(row)])));
        tr.as_obj().expect("트랙").set("board", board);
        let err = layout_track(&mut c, &tr).err().expect("판의 view가 없으면 오류여야 합니다").to_string();
        assert!(err.contains("_boardBranch") && err.contains("view"), "{err}");
        drop(tr);
    }
    assert_eq!(js::live_containers(), base, "오류 뒤 문맥을 버리면 그래프가 풀려야 합니다");
}

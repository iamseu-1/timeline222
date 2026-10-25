//! 한 벌 P3 과제 5 — 읽기(이음매 ①): 팩마다 Rust가 정규화한 팩이 Node의 `JSON.stringify(HT.normalizePack(raw).pack)`과 차이 0이다.
//! 정답지: `node prototype/scripts/layout-oracle.mjs`(→ `prototype/results/oracle/<자료>/norm-<i>.json`). 시각 · 시간대는 `common::oracle::opts`가 정답지와 같게 준다.
//! 과제 5a · 5b가 최상위 열쇠 거르개(KEYS)를 넓혀 왔고, 과제 5c가 거르개를 걷었다 — 팩 전체(머리 `$oracle`만 뗌)를 견준다.
mod common;
use archive_engine::lay;
use common::oracle::{assert_same, fixtures, inputs, opts, oracle, results_dir, seam_opts};

/// 정답지 머리(`$oracle` — 시각 · 시간대 · 원본 지문)를 뗀 정규화한 팩. 과제 5a · 5b가 최상위 열쇠 거르개(KEYS)로 넓혀 왔고, 과제 5c가 거르개를 걷었다 — 팩 전체를 견준다.
fn without_head(v: serde_json::Value) -> serde_json::Value {
    match v {
        serde_json::Value::Object(mut m) => { m.remove("$oracle"); serde_json::Value::Object(m) }
        other => other,
    }
}

#[test]
fn normalized_packs_match_node() {
    assert!(results_dir().is_dir(), "정답지 폴더 {}가 없습니다 — 먼저 뽑으세요: node prototype/scripts/layout-oracle.mjs", results_dir().display());
    let mut compared = 0;
    // 보조 달력 표는 커밋한 잘린 표(common::oracle::seam_opts — 판정 R18): 견본 등불 2.0.1의 사건 하나가 "음력 125-08-15"라 표 없이는 Rust가 거절한다.
    let o = seam_opts(None);
    for f in fixtures() {
        for (i, p) in inputs(&f).iter().enumerate() {
            let got = lay::normalized(p, &o).unwrap_or_else(|e| panic!(
                "자료 {} · 팩 {i}({}): 읽지 못했습니다 — {e}\n  (달력 표 없음 · 범위 밖이면 자료가 새 보조 달력 날짜를 얻은 것 — 잘린 표를 다시 뽑으세요: node prototype/scripts/calendar-slice.mjs)",
                f.name, p.name));
            assert_same(&f, &format!("norm-{i}"), &got, &without_head(oracle(&f, &format!("norm-{i}.json"))));
            compared += 1;
        }
    }
    // 정답지 폴더가 비었거나 목록이 모두 건너뛰어지면 아무것도 견주지 않고 통과하게 된다 — 그것을 막는다.
    assert!(compared > 0, "견준 팩이 하나도 없습니다 — 자료 목록 · 정답지를 확인하세요");
    eprintln!("이음매 ①: 팩 {compared}개를 견줌");
}

// ── 읽기 도움 함수의 벡터(`node prototype/scripts/read-vectors.mjs` → tests/fixtures/lay/read-vectors.json) ──
// 정답지 자료가 닿지 않는 갈래(날짜 글의 꼴 · 보조 달력 · 미정 · 이설 · 확실성 · 오류 · 알림 글 · 형식 4 내림 전체)를 함수마다 Node의 답과 글자까지 견준다.

use archive_engine::lay::cal;
use archive_engine::lay::f4;
use archive_engine::lay::js::{self, Obj, Str, V};
use archive_engine::lay::read::{self, capital, cells, dates, docs, groups, info, misc, names, treaty, vocab, Ctx};
use std::path::Path;
use std::rc::Rc;

fn vectors() -> serde_json::Value {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures").join("lay").join("read-vectors.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{} — 먼저 뽑으세요: node prototype/scripts/read-vectors.mjs ({e})", path.display()));
    serde_json::from_str(&text).expect("read-vectors.json은 JSON")
}
fn ctx_with_tables(v: &serde_json::Value) -> Ctx {
    let mut o = opts(None);
    o.calendar = Some(Rc::new(serde_json::to_vec(&v["calendar"]).unwrap()));
    Ctx::new(&o).expect("달력 표")
}
fn obj(pairs: Vec<(&str, V)>) -> V {
    let o = Obj::new();
    for (k, x) in pairs { o.set(k, x); }
    V::Obj(o)
}
fn num_or_null(x: Option<f64>) -> V { x.map_or(V::Null, V::Num) }
fn str_or_null(x: Option<Str>) -> V { x.map_or(V::Null, V::Str) }
/// read-vectors.mjs의 `parseOut`.
fn parse_out(r: Option<cal::Parsed>) -> V {
    let Some(r) = r else { return V::Null };
    if !r.ok { return obj(vec![("ok", V::Bool(false)), ("error", V::Str(r.error))]); }
    obj(vec![("ok", V::Bool(true)), ("t", V::Num(r.t)), ("prec", V::from(r.prec)), ("cal", V::from(r.cal)), ("y", V::Num(r.y)), ("m", num_or_null(r.m)), ("leap", V::Bool(r.leap)),
        ("d", num_or_null(r.d)), ("h", num_or_null(r.h)), ("mi", num_or_null(r.mi)), ("J", num_or_null(r.j)), ("text", V::Str(r.text)), ("fine", V::Bool(r.fine)),
        ("span", r.span.map_or(V::Null, |(a, b)| read::arr_of(vec![V::Num(a), V::Num(b)]))), ("last", num_or_null(r.last))])
}
/// read-vectors.mjs의 `readDateOut`.
fn date_out(d: Option<dates::DateR>) -> V {
    let Some(d) = d else { return V::Null };
    let word = |s: &str| if s.is_empty() { V::Null } else { V::from(s) };
    obj(vec![("t", V::Num(d.t)), ("at", str_or_null(d.at)), ("prec", word(d.prec)), ("cal", word(d.cal)), ("error", str_or_null(d.error))])
}
fn scope_ref_out(r: &cells::ScopeRef) -> V {
    match &r.track { Some(t) => obj(vec![("track", V::Str(t.clone())), ("polity", V::Str(r.polity.clone()))]), None => obj(vec![("polity", V::Str(r.polity.clone()))]) }
}
fn notes_out(list: &[read::Note]) -> V {
    read::arr_of(list.iter().map(|n| {
        let mut pairs = vec![("msg", V::from(n.msg.as_str())), ("kind", V::from(n.kind.as_str()))];
        if let Some(i) = n.index { pairs.push(("index", V::Num(i))); }
        obj(pairs)
    }).collect())
}
fn text_of(v: &V) -> String { if v.is_undef() { "undefined".into() } else { js::stringify(v) } }
/// 글 목록을 JS 배열로.
fn texts(list: Vec<String>) -> V { read::arr_of(list.into_iter().map(V::from).collect()) }

/// 형식 3 목록 읽기의 알림 통로(read-vectors.mjs의 `notes` — ['err' | 'warn', 글, 차례]).
struct Notes(Vec<V>);
impl info::Report for Notes {
    fn err(&mut self, msg: String, i: usize) { self.0.push(read::arr_of(vec![V::from("err"), V::from(msg), V::Num(i as f64)])); }
    fn warn(&mut self, msg: String, i: usize) { self.0.push(read::arr_of(vec![V::from("warn"), V::from(msg), V::Num(i as f64)])); }
}

/// 표본 하나를 Rust로 돌린 답(JSON 글)과 알림.
fn run(ctx: &Ctx, f: &str, args: &[V]) -> (String, Vec<String>) {
    let mut warns: Vec<String> = Vec::new();
    let a = |i: usize| args.get(i).cloned().unwrap_or_default();
    let mode = f.split_once(':').map_or("", |x| x.1);
    let out: V = match f.split(':').next().unwrap() {
        "cal.parse" => parse_out(cal::parse(&ctx.cal, &a(0))),
        "readDate" => date_out(dates::read_date(ctx, &a(0), &a(1))),
        "endBound" => dates::end_bound(ctx, &a(0), &a(1)),
        "parseYear" => { let t = dates::parse_year(ctx, &a(0)); if t.is_nan() { V::from("NaN") } else { V::Num(t) } }
        "readCellEdge" => match cells::read_cell_edge(ctx, &a(0), "start") {
            None => V::Null,
            Some(cells::Edge::Unknown(t)) => obj(vec![("unknown", V::Bool(true)), ("t", num_or_null(t))]),
            Some(cells::Edge::Date(d)) => date_out(Some(d)),
        },
        "isUnknownText" => V::Bool(dates::is_unknown_text(&a(0))),
        "isOngoingText" => V::Bool(dates::is_ongoing_text(&a(0))),
        "ID_RE" => V::Bool(dates::id_ok(&js::to_str(&a(0)))),
        "isColor" => V::Bool(misc::is_color(&a(0))),
        "hash" => V::Str(misc::hash(&js::to_str(&a(0)))),
        "autoColor" => V::from(misc::auto_color(&a(0))),
        "isLangTag" => V::Bool(names::is_lang_tag(&a(0))),
        "readScopeRef" => cells::read_scope_ref(&a(0)).map_or(V::Null, |r| scope_ref_out(&r)),
        "readScopeRefs" => read::arr_of(cells::read_scope_refs(&a(0)).iter().map(scope_ref_out).collect()),
        "relationId" => V::Str(vocab::relation_id(&a(0))),
        "F4.typeId" => V::Str(f4::type_id(&a(0))),
        "readRowOrder" => misc::read_row_order(&a(0)).map_or(V::Null, V::Str),
        "readAlternatives" => {
            let base = a(1);
            let list = cells::read_alternatives(ctx, &a(0), mode, Some(&mut |m| warns.push(m)), if base.is_null() { None } else { Some(&base) });
            read::arr_of(list)
        }
        "readUncertain" => {
            let (s, e) = (a(1).as_num(), a(2).as_num());
            V::Obj(cells::read_uncertain(ctx, &a(0), mode, Some(&mut |m| warns.push(m)), s, e, None))
        }
        "readNames" => read::arr_of(names::read_names(ctx, &a(0), &mut |m| warns.push(m))),
        "readYearCycle" => misc::read_year_cycle(ctx, &a(0), &mut |m| warns.push(m)),
        "readPackInfo" => V::Obj(info::read_pack_info(&a(0), &mut |m| warns.push(m), &js::to_str(&a(1)))),
        "readViewSettings" => info::read_view_settings(&a(0), &mut |m| warns.push(m)).map_or(V::Null, V::Obj),
        "readViews" => {
            let mut notes = Notes(Vec::new());
            let out = info::read_views(ctx, &a(0), &mut notes);
            obj(vec![("out", read::arr_of(out)), ("notes", read::arr_of(notes.0))])
        }
        // ── 과제 5b ──
        "historicity" => V::Str(vocab::historicity(&a(0))),
        "successionType" => V::Str(vocab::succession_type(&a(0))),
        "succDegree" => num_or_null(vocab::succ_degree(&a(0))),
        "succPart" => V::Str(vocab::succ_part(&a(0))),
        "normalizeSucc" => vocab::normalize_succ(&a(0), &mut |m| warns.push(m)).map_or(V::Null, V::Obj),
        "polityKindId" => V::Str(vocab::polity_kind_id(&a(0))),
        "capitalRole" => V::Str(vocab::capital_role(&a(0))),
        "normalizeCapital" => {
            let o = if mode == "nowarn" { capital::normalize_capital(ctx, &a(0), None) } else { capital::normalize_capital(ctx, &a(0), Some(&mut |m| warns.push(m))) };
            o.map_or(V::Null, V::Obj)
        }
        "numberLeaders" => { let l = a(0); capital::number_leaders(&l.as_arr().map(|x| x.to_vec()).unwrap_or_default()); l }
        "sortCells" => read::arr_of(cells::sort_cells(a(0).as_arr().map(|x| x.to_vec()).unwrap_or_default())),
        "readPhases" => { let p = cells::read_phases(ctx, &a(0)); obj(vec![("list", read::arr_of(p.list)), ("problems", texts(p.problems)), ("warnings", texts(p.warnings))]) }
        "readRankDefs" => {
            let r = cells::read_rank_defs(&a(0));
            let at = read::arr_of(r.at.iter().map(|x| x.map_or(V::Null, |i| V::Num(i as f64))).collect());
            obj(vec![("list", read::arr_of(r.list)), ("problems", texts(r.problems)), ("at", at)])
        }
        "readRanks" => { let r = cells::read_ranks(ctx, &a(0)); obj(vec![("list", read::arr_of(r.list)), ("problems", texts(r.problems)), ("warnings", texts(r.warnings))]) }
        "readPartOf" => read::arr_of(cells::read_part_of(ctx, &a(0), mode == "relation", Some(&mut |m| warns.push(m)))),
        "isUnknownOrdinal" => V::Bool(cells::is_unknown_ordinal(&a(0))),
        "isUnknownWho" => V::Bool(names::is_unknown_who(&a(0))),
        "kinId" => V::Str(names::kin_id(&a(0))),
        "accessionHow" => V::Str(names::accession_how(&a(0))),
        "parentRole" => V::Str(names::parent_role(&a(0))),
        "readPersonRef" => names::read_person_ref(ctx, &a(0)),
        "personCellRe" => match names::person_cell_text(&js::to_str(&a(0))) {
            Some((p, l, s)) => read::arr_of(vec![V::Str(p), V::Str(l), str_or_null(s)]),
            None => V::Null,
        },
        "personRefText" => V::Str(names::person_ref_text(&a(0))),
        "readAccession" => names::read_accession(ctx, &a(0), &mut |m| warns.push(m)).map_or(V::Null, V::Obj),
        "readParents" => read::arr_of(names::read_parents(ctx, &a(0), &mut |m| warns.push(m))),
        "readSpouses" => read::arr_of(names::read_spouses(ctx, &a(0), &mut |m| warns.push(m))),
        "readNorthSouth" => match misc::read_north_south(&a(0)) { None => V::Undef, Some(n) if n.is_nan() => V::from("NaN"), Some(n) => V::Num(n) },
        // ── 과제 5c ──
        "treatyType" => V::Str(treaty::treaty_type(&a(0))),
        "treatyEndReason" => V::Str(treaty::treaty_end_reason(&a(0))),
        "articleTag" => V::Str(treaty::article_tag(&a(0))),
        "groupType" => V::Str(groups::group_type(&a(0))),
        "groupHow" => V::Str(groups::group_how(&a(0))),
        "lawAct" => V::Str(groups::law_act(&a(0))),
        "readSigners" => read::arr_of(treaty::read_signers(&a(0))),
        "splitArticles" => read::arr_of(treaty::split_articles(&a(0)).into_iter().map(V::Obj).collect()),
        "readTreaty" => treaty::read_treaty(ctx, &a(0), &mut |m| warns.push(m)).map_or(V::Null, V::Obj),
        "readLaw" => groups::read_law(&a(0), &mut |m| warns.push(m)).map_or(V::Null, V::Obj),
        "readElection" => groups::read_election(&a(0), &mut |m| warns.push(m)).map_or(V::Null, V::Obj),
        "readThemeDefs" => {
            let r = groups::read_theme_defs(ctx, &a(0));
            let at = read::arr_of(r.at.iter().map(|x| x.map_or(V::Undef, |i| V::Num(i as f64))).collect());
            obj(vec![("list", read::arr_of(r.list)), ("problems", texts(r.problems)), ("at", at)])
        }
        "readThemeList" => read::arr_of(groups::read_theme_list(&a(0)).into_iter().map(V::Str).collect()),
        "readPolityRows" => {
            let what = if mode == "role" { "구성 나라" } else { "있던 나라" };
            read::arr_of(groups::read_polity_rows(ctx, &a(0), mode == "role", &mut |m| warns.push(m), what))
        }
        "readGroupFrom" => read::arr_of(groups::read_group_from(&a(0), &mut |m| warns.push(m))),
        "readInstPolity" => groups::read_inst_polity(&a(0), &a(1)).map_or(V::Null, V::Obj),
        "readInstSpans" => { let r = groups::read_inst_spans(ctx, &a(0)); obj(vec![("list", read::arr_of(r.list)), ("problems", texts(r.problems)), ("warnings", texts(r.warnings))]) }
        "parseRange" => names::parse_range(&a(0)).map_or(V::Null, |(lo, hi)| read::arr_of(vec![V::Num(f64::from(lo)), V::Num(f64::from(hi))])),
        "readGroupPeople" => read::arr_of(names::read_group_people(ctx, &a(0), &mut |m| warns.push(m))),
        "readCoords" => names::read_coords(&a(0)).map_or(V::Null, |n| read::arr_of(n.into_iter().map(V::Num).collect())),
        "readSpot" => misc::read_spot(&a(0)).map_or(V::Undef, V::Num),
        "docKeyValid" => V::Bool(docs::doc_key_valid(&js::to_str(&a(0)))),
        "readImages" | "readMaps" | "readFonts" => {
            let mut notes = Notes(Vec::new());
            let out = match f.split(':').next().unwrap() {
                "readImages" => docs::read_images(&a(0), &mut notes),
                "readMaps" => info::read_maps(ctx, &a(0), &mut notes),
                _ => info::read_fonts(&a(0), &mut notes),
            };
            obj(vec![("out", read::arr_of(out)), ("notes", read::arr_of(notes.0))])
        }
        "normalizePack" => {
            let n = read::normalize_pack(ctx, a(0));
            let pack = n.pack.unwrap_or(V::Null);
            obj(vec![("pack", pack), ("errors", notes_out(&n.errors)), ("warnings", notes_out(&n.warnings))])
        }
        "F4.down" => f4::down(ctx, &a(0), &mut |m| warns.push(m)).expect("내림"),
        other => panic!("모르는 표본 함수 {other}"),
    };
    (text_of(&out), warns)
}

#[test]
fn read_helpers_match_node_vectors() {
    let v = vectors();
    let ctx = ctx_with_tables(&v);
    let cases = v["cases"].as_array().expect("cases");
    assert!(cases.len() > 400, "표본이 너무 적습니다({}개)", cases.len());
    let mut bad = Vec::new();
    let mut missed = 0;
    // 정규식 갈래마다 '실제로 맞은(그리고 견준) cal.parse 표본' 수 — 맞음은 Node가 RegExp.prototype.exec를 감싸 센 것(read-vectors.mjs의 REGEX_NAMES).
    // 손으로 옮긴 곳(RE_BC_MID의 앞보기 · RE_NUM의 뒤참조 — 가름표 셋 · 쉼표 지우기)과 \s의 넓은 빈칸 · LEAD의 옮기기를 포함한다.
    const BRANCHES: [&str; 22] = ["fullwidth", "comma", "spaces", "spacesWide", "lead", "leadMove", "tail", "calWordHead", "calWordCut", "calWordTail", "approxTail",
        "approxHead", "bcHead", "bcTail", "adHead", "bcMid", "cent", "ko", "num", "num-", "num.", "num/"];
    let mut branch_hits = std::collections::BTreeMap::<&str, usize>::new();
    // 과제 5b — core.js에서 손으로 옮긴 정규식의 갈래(read-vectors.mjs의 REGEX_5B): '<함수>/<정규식:갈래>'마다 맞은(그리고 견준) 표본 ≥ 1.
    // isUnknownOrdinal · isUnknownWho는 같은 정규식(`unknown_word`) — 함수마다 낱말 여섯을 모두. personCellRe는 정규식 그 자체(다듬지 않은 글 — 빈칸 갈래).
    let mut hits_5b = std::collections::BTreeMap::<String, usize>::new();
    let mut want_5b: Vec<String> = Vec::new();
    for f in ["isUnknownOrdinal", "isUnknownWho"] {
        for w in ["미상", "미정", "불명", "모름", "?", "unknown"] { want_5b.push(format!("{f}/unknownWord:{w}")); }
    }
    for b in ["plain", "at", "wsLeader"] { want_5b.push(format!("readPersonRef/personRef:{b}")); }
    for b in ["plain", "at", "wsLeader", "wsStart"] { want_5b.push(format!("personCellRe/personRef:{b}")); }
    for d in ["1", "2", "3"] { want_5b.push(format!("succDegree/degreeDigit:{d}")); }
    for s in [",", "，", "、", "·"] { want_5b.push(format!("normalizeSucc/succParts:{s}")); }
    for z in ["조계", "조차", "租界", "租借", "거류지", "居留地", "공사관 구역", "공사관구역", "특구", "왜관", "倭館"] { want_5b.push(format!("normalizePack/zone:{z}")); }
    for s in [",", "，"] { want_5b.push(format!("normalizePack/commaList:{s}")); }
    // 과제 5c — core.js에서 손으로 옮긴 정규식의 갈래(read-vectors.mjs의 REGEX_5C): '<함수>/<갈래>'마다 맞은(그리고 견준) 표본 ≥ 1.
    let want_5c: Vec<String> = [
        ("readSigners", &["signer:asciiClose", "signer:fullClose", "signer:emptyTitle", "signerSplit:semi", "signerSplit:fullSemi", "signerSplit:lf"][..]),
        ("splitArticles", &["head:je조", "head:je관", "head:je항", "head:article", "head:art.", "head:punct", "artNo:art", "title:(", "title:（", "title:【", "title:[", "title:wsOnly", "cr"][..]),
        ("readTreaty", &["unequal:true", "unequal:예", "unequal:네", "unequal:불평등", "langSplit:comma", "langSplit:fullComma", "langSplit:ideoComma", "party:colon", "party:split"][..]),
        ("readLaw", &["lawLines:lf", "lawLines:crlf", "cr"][..]),
        ("readElection", &["strip:comma", "strip:fullComma", "strip:ws", "won:true", "won:예", "won:네", "won:당선", "won:이김", "won:승리"][..]),
        ("readThemeList", &["comma:comma", "comma:fullComma"][..]),
        ("readGroupPeople", &["comma:comma", "comma:fullComma"][..]),
        ("readCoords", &["coordSplit:comma", "coordSplit:fullComma", "coordSplit:ws"][..]),
        ("parseRange", &["range:single", "range:sepHyphen", "range:sepDash", "range:sepTilde", "range:uPlus2"][..]),
        ("readMaps", &["none"][..]),
        ("readFonts", &["font:woff2", "font:woff", "font:ttf", "font:otf", "script4"][..]),
        ("normalizePack", &["target", "badId:dq", "badId:sq", "badId:slash", "badId:bs"][..]),
    ].iter().flat_map(|(f, names)| names.iter().map(move |b| format!("{f}/{b}"))).collect();
    // 형식 4 내림의 '미상' 섬김 → 종류 되살리기(f4::down의 period_of — 국가 객체 · `of`가 미상 · 종속 관계면 kind = 관계 · 맞추기 과제 S 고침 1회차):
    // 정답지 f4 여덟에는 이 갈래가 없다 — 'F4.down:unknown' 표본(객체 '갑' 하나씩) 가운데 Rust가 kind를 되살린 것과 되살리지 않은 짝이 저마다 1개 이상.
    const DEPENDENT: [&str; 10] = ["tributary", "dominion", "vassal", "protectorate", "satellite", "puppet", "mandate", "colony", "occupied", "frontier"];
    let (mut revived, mut kept) = (0, 0);
    for c in cases {
        let f = c["fn"].as_str().unwrap();
        let input = c["in"].as_str().unwrap();
        let args = match js::parse(input).expect("표본 입력") { V::Arr(a) => a.to_vec(), _ => panic!("표본 입력은 배열") };
        let (got, warns) = run(&ctx, f, &args);
        if f == "F4.down:unknown" {
            let out: serde_json::Value = serde_json::from_str(&got).expect("내린 팩 JSON");
            let p = out["periods"].as_array().and_then(|l| l.iter().find(|p| p["name"] == "갑")).unwrap_or_else(|| panic!("{input}: 내린 팩에 '갑'이 없습니다"));
            if p["kind"].as_str().is_some_and(|k| DEPENDENT.contains(&k)) { revived += 1 } else { kept += 1 }
        }
        // 이 표본들에는 다섯 보조 달력의 표가 다 있다 — '표 없음'이 서면 안 된다.
        assert!(!ctx.cal.take_absent(), "{f}({input}): 달력 표가 있는데 '표 없음' 표지가 섰습니다");
        // 보조 달력 표(1400 ~ 2100년) 밖이 필요한 표본은 Rust가 거절한다(계획 정한 것 #7) — 표지가 서야 하고, 답은 견주지 않는다.
        if ctx.cal.take_missed() { missed += 1; continue; }
        for h in c["hits"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
            let name = h.as_str().unwrap();
            if f != "cal.parse" {
                *hits_5b.entry(format!("{}/{name}", f.split(':').next().unwrap())).or_default() += 1;
                continue;
            }
            let known = BRANCHES.iter().find(|b| **b == name).unwrap_or_else(|| panic!("모르는 정규식 갈래 {name} — BRANCHES에 더하세요"));
            *branch_hits.entry(known).or_default() += 1;
        }
        let want = c["out"].as_str().unwrap();
        let want_warns: Vec<String> = c["warn"].as_array().map(|w| w.iter().map(|x| x.as_str().unwrap().to_string()).collect()).unwrap_or_default();
        if got != want || warns != want_warns {
            bad.push(format!("{f}({input})\n    Node: {want} {want_warns:?}\n    Rust: {got} {warns:?}"));
        }
    }
    assert!(bad.is_empty(), "Node와 다른 표본 {}개(앞 15개):\n  {}", bad.len(), bad.iter().take(15).cloned().collect::<Vec<_>>().join("\n  "));
    assert_eq!(missed, 1, "보조 달력 표 밖 표본은 '기원전 음력 100-01-01' 하나뿐이어야 합니다");
    let empty: Vec<&str> = BRANCHES.iter().copied().filter(|b| !branch_hits.contains_key(b)).collect();
    assert!(empty.is_empty(), "견준 표본이 하나도 맞지 않은 정규식 갈래: {empty:?} — read-vectors.mjs에 표본을 더하세요");
    let empty_5b: Vec<&String> = want_5b.iter().filter(|b| !hits_5b.contains_key(*b)).collect();
    assert!(empty_5b.is_empty(), "견준 표본이 하나도 맞지 않은 5b 정규식 갈래: {empty_5b:?} — read-vectors.mjs에 표본을 더하세요");
    let empty_5c: Vec<&String> = want_5c.iter().filter(|b| !hits_5b.contains_key(*b)).collect();
    assert!(empty_5c.is_empty(), "견준 표본이 하나도 맞지 않은 5c 정규식 갈래: {empty_5c:?} — read-vectors.mjs에 표본을 더하세요");
    assert!(revived >= 1 && kept >= 1, "형식 4 '미상' 섬김의 종류 되살리기 갈래 — 되살림 {revived} · 짝 {kept}: 저마다 1개 이상이어야 합니다(read-vectors.mjs의 F4.down:unknown)");
    eprintln!("읽기 벡터(형식 4 '미상' 되살리기): 되살림 {revived} · 되살리지 않은 짝 {kept}");
    // 잘린 달력 표(판정 R18 — tests/fixtures/lay/calendar-slice.json)로도 모든 표본이 Node(ICU)와 글자까지 같다. 그 표는 표본의 보조 달력 날짜 둘레를 모두 덮으므로
    // 벡터 표(1400 ~ 2100년)에서는 표 밖인 '기원전 음력 100-01-01'도 답한다 — 표 밖 · 표 없음 표지가 하나도 서지 않아야 한다.
    let sliced = Ctx::new(&seam_opts(None)).expect("잘린 달력 표");
    let mut bad_sliced = Vec::new();
    for c in cases {
        let f = c["fn"].as_str().unwrap();
        let input = c["in"].as_str().unwrap();
        let args = match js::parse(input).expect("표본 입력") { V::Arr(a) => a.to_vec(), _ => panic!("표본 입력은 배열") };
        let (got, warns) = run(&sliced, f, &args);
        assert!(!sliced.cal.take_absent() && !sliced.cal.take_missed(), "{f}({input}): 잘린 달력 표가 이 표본의 날짜를 덮지 못합니다 — node prototype/scripts/calendar-slice.mjs");
        let want_warns: Vec<String> = c["warn"].as_array().map(|w| w.iter().map(|x| x.as_str().unwrap().to_string()).collect()).unwrap_or_default();
        if got != c["out"].as_str().unwrap() || warns != want_warns { bad_sliced.push(format!("{f}({input})")); }
    }
    assert!(bad_sliced.is_empty(), "잘린 달력 표로 Node와 다른 표본 {}개(앞 10개): {:?}", bad_sliced.len(), bad_sliced.iter().take(10).collect::<Vec<_>>());
    eprintln!("읽기 벡터(잘린 달력 표): 표본 {}개 모두 같음 · 표 밖 0", cases.len());
    eprintln!("읽기 벡터: 표본 {}개 같음 · 표 밖 거절 {missed}개 · 정규식 갈래마다 맞은 표본 {branch_hits:?}", cases.len() - missed);
    eprintln!("읽기 벡터(5b 손 옮김 정규식): {}", want_5b.iter().map(|b| format!("{b} {}", hits_5b[b])).collect::<Vec<_>>().join(" · "));
    eprintln!("읽기 벡터(5c 손 옮김 정규식): {}", want_5c.iter().map(|b| format!("{b} {}", hits_5b[b])).collect::<Vec<_>>().join(" · "));
}

/// 정답지와 같은 시각 · 시간대에서 `read::Ctx`의 '오늘'이 웹의 `HT.CURRENT_YEAR` · `HT.NOW_T`와 같다(read-vectors.mjs가 시계를 고정해 실은 값).
#[test]
fn today_matches_node_at_the_oracle_instant() {
    let v = vectors();
    assert_eq!(v["now"]["text"], common::oracle::ORACLE_NOW, "벡터의 시각이 정답지와 다릅니다");
    let ctx = Ctx::new(&opts(None)).unwrap();
    assert_eq!((ctx.current_year, ctx.now_t), (v["now"]["currentYear"].as_f64().unwrap(), v["now"]["nowT"].as_f64().unwrap()));
}

/// 정답지 자료의 형식 4 파일: Rust의 내림(`f4::down`)을 `JSON.stringify`(JS 열쇠 차례)한 글의 지문 · 알림이 Node의 `HT.F4.down`과 같다.
#[test]
fn f4_down_of_fixture_files_matches_node() {
    use sha2::{Digest, Sha256};
    let v = vectors();
    let ctx = ctx_with_tables(&v);
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("fixtures").join("oracle");
    let files = v["f4files"].as_array().expect("f4files");
    assert!(files.len() >= 9, "형식 4 파일 표본이 모자랍니다");
    for f in files {
        let name = f["file"].as_str().unwrap();
        let bytes = std::fs::read(name.split('/').fold(dir.clone(), |p, s| p.join(s))).expect("형식 4 파일");
        let raw = if name.ends_with(".htpack") {
            let open = archive_engine::unseal(&bytes, archive_engine::KIND_DLC).expect("풀기");
            js::parse(std::str::from_utf8(&open.plain).unwrap()).unwrap()
        } else { js::parse(std::str::from_utf8(&bytes).unwrap()).unwrap() };
        let mut warns = Vec::new();
        let text = js::stringify(&f4::down(&ctx, &raw, &mut |m| warns.push(m)).unwrap());
        let len16 = text.encode_utf16().count() as u64; // JS 글 길이(UTF-16)
        let sha: String = Sha256::digest(text.as_bytes()).iter().take(6).map(|b| format!("{b:02x}")).collect();
        let want_warns: Vec<String> = f["warn"].as_array().unwrap().iter().map(|x| x.as_str().unwrap().to_string()).collect();
        assert_eq!((sha.as_str(), len16, &warns), (f["sha"].as_str().unwrap(), f["bytes"].as_u64().unwrap(), &want_warns), "{name}: 내린 팩이 Node와 다릅니다");
    }
}

/// 보조 달력: 표가 없으면 그 달력은 읽지 못하고(웹에서 ICU가 그 달력을 모를 때와 같은 글), 표 범위 밖이 필요하면 `normalized`가 거절한다.
#[test]
fn intl_calendar_needs_the_table() {
    // 표가 아예 없으면: 그 날짜는 웹에서 ICU가 그 달력을 모를 때와 같은 글로 읽히되 '표 없음' 표지가 서고(정답지 Node에는 ICU가 늘 있으므로), 이음매 ①이 거절한다.
    let none = Ctx::new(&opts(None)).unwrap();
    let r = cal::parse(&none.cal, &V::from("음력 1592-04-13")).unwrap();
    assert!(!r.ok && r.error == "이 환경에서는 음력을(를) 바꿀 수 없습니다.", "{r:?}");
    assert!(none.cal.absent() && !none.cal.missed(), "표가 없으면 '표 없음' 표지가 서야 합니다");
    let lunar = r#"{"format":"history-timeline-dlc","id":"x","name":"x","tracks":[{"id":"t"}],"epochs":[{"name":"e","start":"음력 1592-04-13"}]}"#;
    let err = lay::normalized(&lay::PackIn { name: "x.json".into(), bytes: lunar.as_bytes().to_vec() }, &opts(None)).unwrap_err().to_string();
    assert!(err.contains("음력 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다"), "거절 글에 달력 이름이 들어야 합니다: {err}");
    // 서력 · 그레고리력 · 율리우스력만 쓰는 팩은 표가 없어도 읽힌다(표지가 서지 않음)
    let civil = r#"{"format":"history-timeline-dlc","id":"x","name":"x","tracks":[{"id":"t"}],"epochs":[{"name":"e","start":"율리우스력 1582-10-04"}]}"#;
    assert!(lay::normalized(&lay::PackIn { name: "x.json".into(), bytes: civil.as_bytes().to_vec() }, &opts(None)).is_ok());
    let v = vectors();
    let ctx = ctx_with_tables(&v);
    assert!(cal::parse(&ctx.cal, &V::from("음력 1592-04-13")).unwrap().ok);
    assert!(!cal::parse(&ctx.cal, &V::from("음력 1000-01-01")).unwrap().ok && ctx.cal.missed(), "표 밖은 표지가 서야 합니다");
    // 이음매 ①: 표 밖 날짜가 든 팩은 거절
    let pack = r#"{"format":"history-timeline-dlc","id":"x","name":"x","tracks":[{"id":"t"}],"epochs":[{"name":"e","start":"음력 1000-01-01"}]}"#;
    let mut o = opts(None);
    o.calendar = Some(Rc::new(serde_json::to_vec(&v["calendar"]).unwrap()));
    let err = lay::normalized(&lay::PackIn { name: "x.json".into(), bytes: pack.as_bytes().to_vec() }, &o).unwrap_err().to_string();
    assert!(err.contains("음력 표 범위 밖 — 그 날짜를 양력으로 바꿀 수 없습니다"), "{err}");
    // 표 묶음은 있는데 그 달력만 없음(얹힌 몫 — 5a 검토): 음력 표만 넘기면 음력은 읽히고, 이슬람력은 그 이름으로 '표 없음' 거절 · 범위 밖 표지는 서지 않는다
    let mut only = v["calendar"].clone();
    only["tables"].as_object_mut().unwrap().retain(|k, _| k == "dangi");
    let mut o = opts(None);
    o.calendar = Some(Rc::new(serde_json::to_vec(&only).unwrap()));
    let part = Ctx::new(&o).unwrap();
    assert!(cal::parse(&part.cal, &V::from("음력 1592-04-13")).unwrap().ok && !part.cal.absent(), "음력 표가 있으면 음력은 읽혀야 합니다");
    let r = cal::parse(&part.cal, &V::from("이슬람력 1000-08-11")).unwrap();
    assert!(!r.ok && part.cal.absent_of() == Some("이슬람력") && !part.cal.missed(), "그 달력만 없으면 그 이름으로 표지가 서야 합니다: {r:?}");
    let islamic = r#"{"format":"history-timeline-dlc","id":"x","name":"x","tracks":[{"id":"t"}],"epochs":[{"name":"e","start":"음력 1592-04-13"},{"name":"f","start":"이슬람력 1000-08-11"}]}"#;
    let err = lay::normalized(&lay::PackIn { name: "x.json".into(), bytes: islamic.as_bytes().to_vec() }, &o).unwrap_err().to_string();
    assert!(err.contains("이슬람력 표 없음 — 그 달력의 날짜를 양력으로 바꿀 수 없습니다"), "{err}");
}

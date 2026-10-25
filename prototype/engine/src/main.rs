use archive_engine::canon::{canon_store, CanonOpts};
use archive_engine::legacy::{import_with, ImportPlan};
use archive_engine::levels::{tile_of, CHUNK_ROWS};
use archive_engine::patch::{read_order, run_order, CoversAsk};
use archive_engine::tile::{build_tile, decode, encode, Decoded, TileRequest};
use archive_engine::verify::{all_packs, meta_int};
use archive_engine::write::write;
use archive_engine::{read_htpack, Result, Store, DAY};
use serde_json::{json, Value};
use std::{fs, path::{Path, PathBuf}, time::Instant};

fn stats(mut values: Vec<f64>) -> Value {
    values.sort_by(f64::total_cmp);
    let n = values.len();
    let at = |p: f64| values[((n as f64 * p).ceil() as usize).clamp(1, n) - 1];
    json!({"n":n,"p50":values[n/2],"p95":at(0.95),"p99":at(0.99),"max":values[n-1],"over100":values.iter().filter(|v|**v>=100.).count()})
}

/// 전달 형식을 바꾸기 전후를 견주기 위한 검사 전용 경로: 같은 타일을 JSON 글자열로 부호화한다.
/// 띠 배열의 끝은 형식 4의 뜻 `form`(스키마 4 — 타일 띠 구역의 열 10 · 그 열이 없는 타일은 0).
fn tile_json(t: &Decoded) -> String {
    json!({"level":t.level,"chunk":t.chunk,"x":t.x,"origin":t.origin,"span":t.span,
        "bands":t.bands.iter().map(|b| json!([b.x0,b.x1,b.id,b.color,t.strings.get(b.name as usize),b.row,b.flags,b.look,t.strings.get(b.tag as usize),b.sub,b.form])).collect::<Vec<_>>(),
        "cells":t.cells.iter().map(|c| json!([c.x0,c.x1,c.id,t.strings.get(c.name as usize),c.row,c.kind,c.flags,c.lane,c.style,c.color])).collect::<Vec<_>>(),
        "events":t.events.iter().map(|e| json!([e.x0,e.x1,e.id,t.strings.get(e.name as usize),e.row,e.bits,e.look,t.strings.get(e.label as usize),e.rail,e.band])).collect::<Vec<_>>(),
        "pills":t.pills.iter().map(|p| json!([p.x0,p.x1,p.count,p.row,t.strings.get(p.cats as usize)])).collect::<Vec<_>>(),
        "sections":t.sections.iter().map(|s| json!({"kind":s.kind,"items":s.items.iter().map(|i| json!([i.x0,i.x1,i.id,t.strings.get(i.name as usize),i.row,i.flags,i.row2,i.reference,i.color,i.a,i.b,i.c,i.d,t.strings.get(i.text2 as usize)])).collect::<Vec<_>>()})).collect::<Vec<_>>()}).to_string()
}

/// 재는 단계. 성긴 쪽 셋(L11~L13)은 돋보기 구간의 병목이라(검증 보고서 9-5절) 한 단계도 건너뛰지 않는다 —
/// 칸의 시험용 손잡이(`ARCHIVE_CELL_LOD` · 계약 5-3절)를 바꿔 가며 견주는 곳이 바로 이 셋이다.
const BENCH_LEVELS: [usize; 9] = [13, 12, 11, 9, 8, 7, 5, 3, 0];

fn bench(path: &Path, out: &Path, with_filter: bool) -> Result<()> {
    let opened = Instant::now();
    let store = Store::open(path)?;
    let info = store.info()?;
    let open_ms = opened.elapsed().as_secs_f64() * 1000.;
    let mut report = Vec::new();
    {
        let (mut times, mut rows, mut payload) = (Vec::new(), Vec::new(), Vec::new());
        for i in 0..120 {
            let q = json!({"op":"search","text":(["해솔","星河","여울","은빛 나루","0000097"][i%5])});
            let t = Instant::now();
            let r = store.call(&q)?;
            let bytes = serde_json::to_vec(&r)?.len();
            times.push(t.elapsed().as_secs_f64() * 1000.);
            rows.push(r["items"].as_array().map(Vec::len).unwrap_or(0));
            payload.push(bytes);
        }
        report.push(json!({"name":"검색","ms":stats(times),"max_rows":rows.into_iter().max(),"max_bytes":payload.into_iter().max()}));
    }
    // 타일: 단계마다 자료 범위를 고르게 훑는 120장. 같은 날 밀집은 가상 자료의 몰린 날(메타 dense_day)을 지나는 타일만.
    let (min, max, rows) = (meta_int(&store, "min")?, meta_int(&store, "max")?, meta_int(&store, "rows")?);
    let chunks = (rows + CHUNK_ROWS - 1) / CHUNK_ROWS;
    let packs = all_packs(&store)?;
    let dense = meta_int(&store, "dense_day").ok();
    let mut cases: Vec<(String, usize, Option<i64>, bool)> = BENCH_LEVELS.iter().map(|l| (format!("타일 · 단계 {l}"), *l, None, false)).collect();
    if let Some(day) = dense {
        cases.extend([7usize, 4, 2, 0].iter().map(|l| (format!("타일 · 같은 날 밀집 · 단계 {l}"), *l, Some(day * DAY + 720), false)));
    }
    // 거르개를 걸면 미리 셈해 둔 요약을 못 쓰고 그 자리에서 다시 세야 한다 — 얼마나 느려지는지를 같은 타일로 견준다.
    // 거르개는 '분류 하나 끔 + 중요도 문턱 3'이다(계약 2절의 '거르개' 소절).
    let filter_query = json!({"filter":{"cats_off":[1],"min_importance":3}});
    if with_filter {
        cases.extend(BENCH_LEVELS.iter().map(|l| (format!("타일 · 거르개 · 단계 {l}"), *l, None, true)));
    }
    for (name, level, fixed, filtered) in cases {
        let (mut times, mut sizes, mut items, mut encode_ms, mut json_ms, mut json_sizes) = (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
        for i in 0..120i64 {
            let minute = fixed.unwrap_or(min + (max - min) / 120 * i + (max - min) / 240);
            let req = TileRequest { level, x: tile_of(minute, level), chunk: (i * 7) % chunks, packs: packs.clone(),
                filter: if filtered { store.filter_of(&filter_query)? } else { None }, variants: store.variants_of(&json!({}))? };
            let t = Instant::now();
            let bytes = build_tile(&store, &req)?;
            times.push(t.elapsed().as_secs_f64() * 1000.);
            let tile = decode(&bytes)?;
            items.push((tile.bands.len() + tile.cells.len() + tile.events.len() + tile.pills.len() + tile.sections.iter().map(|s| s.items.len()).sum::<usize>()) as f64);
            let t = Instant::now();
            let again = encode(&tile);
            encode_ms.push(t.elapsed().as_secs_f64() * 1000.);
            assert_eq!(again, bytes);
            let t = Instant::now();
            let text = tile_json(&tile);
            json_ms.push(t.elapsed().as_secs_f64() * 1000.);
            sizes.push(bytes.len() as f64);
            json_sizes.push(text.len() as f64);
        }
        report.push(json!({"name":name,"ms":stats(times),"bytes":stats(sizes),"items":stats(items),"encode_binary_ms":stats(encode_ms),"encode_json_ms":stats(json_ms),"json_bytes":stats(json_sizes)}));
    }
    let data = json!({"build":"release","open_ms":open_ms,"info":info,"db_bytes":fs::metadata(path)?.len(),"files":store.verify_files()?,"cases":report,
        "note":"자료 조회와 결과 부호화만 측정. 화면 간격이나 실제 입력 반응이 아니다. 운영체제 파일 캐시는 비우지 않았다. encode_json은 전달 형식을 바꾸기 전후를 견주는 검사 전용 경로."});
    fs::write(out, serde_json::to_string_pretty(&data)? + "\n")?;
    println!("칸의 시험용 손잡이 ARCHIVE_CELL_LOD = {} (기본 8 · 계약 5-3절)", archive_engine::levels::cell_lod_divisor());
    for case in data["cases"].as_array().unwrap().iter().skip(1) {
        println!("{} | ms p50 {:.2} p95 {:.2} max {:.2} | bytes p95 {} | items p95 {} | 부호화 이진 {:.3} · JSON {:.3}ms · JSON {}B", case["name"].as_str().unwrap(),
            case["ms"]["p50"].as_f64().unwrap(), case["ms"]["p95"].as_f64().unwrap(), case["ms"]["max"].as_f64().unwrap(), case["bytes"]["p95"], case["items"]["p95"],
            case["encode_binary_ms"]["p95"].as_f64().unwrap(), case["encode_json_ms"]["p95"].as_f64().unwrap(), case["json_bytes"]["p95"]);
    }
    Ok(())
}

/// 표본 타일의 '대표 + 알약 개수'를 사건 표의 전수 조사와 견준다(`archive_engine::verify` — FFI 가져오기도 같은 것을 쓴다).
fn verify_tiles(path: &Path, samples: i64) -> Result<()> {
    let check = archive_engine::verify::verify_tiles(path, samples)?;
    if let Some(first) = check.first {
        return Err(first.into());
    }
    println!("{}", check.summary());
    Ok(())
}

/// 명령 줄에서 `--from-store <저장소>`를 떼어 내고 나머지 자리 값을 돌려준다.
fn split_from_store(args: &[String]) -> Result<(Vec<&str>, Option<&str>)> {
    let (mut rest, mut from_store) = (Vec::new(), None);
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == "--from-store" {
            from_store = Some(it.next().ok_or("--from-store 뒤에 저장소 경로가 없습니다")?.as_str());
        } else {
            rest.push(a.as_str());
        }
    }
    Ok((rest, from_store))
}

fn is_htlayout(path: &str) -> bool {
    Path::new(path).extension().and_then(|s| s.to_str()).is_some_and(|s| s.eq_ignore_ascii_case("htlayout"))
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("generate2") if args.len() >= 5 => {
            let search = !(args.get(5).map(String::as_str) == Some("--search") && args.get(6).map(String::as_str) == Some("off"));
            println!("{}", archive_engine::generate::generate(Path::new(&args[2]), args[3].parse()?, Path::new(&args[4]), search)?);
            Ok(())
        }
        Some("import-layout") if args.len() >= 5 => {
            let (rest, from_store) = split_from_store(&args[2..])?;
            if rest.len() < 3 {
                return Err("사용법: import-layout <기본팩.htpack|-> <배치.json|.htlayout> <새 저장소> [원본…] [--from-store <지금 저장소>]".into());
            }
            let (base, layout, target, originals) = (rest[0], rest[1], rest[2], &rest[3..]);
            if from_store.is_none() && base != "-" && !is_htlayout(layout) {
                // 옛 꼴 그대로(add-dlc.mjs가 쓴다): 넷째부터는 더 얹은 DLC의 전용 팩(배치의 packs[1..] 차례 · 같은 수).
                let extra: Vec<&Path> = originals.iter().map(Path::new).collect();
                let counts = archive_engine::legacy::import_layout(Path::new(base), Path::new(layout), Path::new(target), &extra)?;
                println!("{}", json!({"가져옴":counts,"bytes":fs::metadata(target)?.len()}));
            } else {
                // Node 없는 길(FFI archive_import와 같다): 원본은 id로 짝짓고, 없으면 원본 없이 · 지금 저장소를 주면 조합 대조와 원본 옮겨 싣기.
                let answer = import_with(&ImportPlan {
                    layout: Path::new(layout), out: Some(Path::new(target)), base: (base != "-").then(|| Path::new(base)),
                    originals: originals.iter().map(Path::new).collect(), from_store: from_store.map(Path::new), check_only: false,
                })?;
                println!("{answer}");
            }
            Ok(())
        }
        Some("check-layout") if args.len() >= 3 => {
            let (rest, from_store) = split_from_store(&args[2..])?;
            let [layout, originals @ ..] = rest.as_slice() else {
                return Err("사용법: check-layout <배치.htlayout|.json> [원본…] [--from-store <지금 저장소>]".into());
            };
            let answer = import_with(&ImportPlan {
                layout: Path::new(layout), out: None, base: None, originals: originals.iter().map(Path::new).collect(),
                from_store: from_store.map(Path::new), check_only: true,
            })?;
            println!("{answer}");
            Ok(())
        }
        // Rust로 짓기(한 벌 P3 과제 17): 팩(.htpack 형식 1 ~ 4 · .json)을 엔진이 배치해(① `lay::export`) 새 저장소를 짓는다(② — 지은 날 · 달력 표를 저장소에).
        // 달력 표(`--calendar`)는 꼭 준다(판정 R36 — 모든 저장소에 전체 표) · `--now`는 시간대를 적은 글(`Z` 거절). `build-check.mjs`가 Node 길과 견준다.
        Some("build") if args.len() >= 4 => {
            let (mut files, mut now, mut calendar, mut narrow) = (Vec::new(), None, None, false);
            for a in &args[3..] {
                if let Some(v) = a.strip_prefix("--now=") {
                    now = Some(v.to_owned());
                } else if let Some(v) = a.strip_prefix("--calendar=") {
                    calendar = Some(PathBuf::from(v));
                } else if a == "--calendar-narrow" {
                    narrow = true; // 시험용 — 기본보다 좁은 달력 표(검사의 잘린 표)도 받는다
                } else if a.starts_with("--") {
                    return Err(format!("build가 모르는 선택입니다: {a}").into());
                } else {
                    files.push(PathBuf::from(a));
                }
            }
            println!("{}", archive_engine::legacy::build_files_with(Path::new(&args[2]), &files, now.as_deref(), calendar.as_deref(), narrow)?);
            Ok(())
        }
        // DLC 넣고 빼기를 엔진 하나로(계약 2-7-1 · 계획 P4 과제 9 — FFI `add_pack` · `remove_pack`과 같은 몸 · 열린 저장소 대신 파일). 배치는 Rust(`lay::export` —
        // 모듈 스물이 다 옮겨짐 · 닿는 트랙만 하위 배치 — P3-16) · 저장소의 달력 표로(없거나 깨졌으면 `code` calendar). 앱은 이 도구가 아니라 같은 몸을
        // FFI(`archive_call`의 `add_pack` · `remove_pack`)로 부른다(P4-10b · 11c).
        // **앱을 닫고** 돌린다 — 앱이 연 저장소를 다른 프로세스가 고쳐 쓰면 켜진 앱의 줄 열쇠 ↔ 자리 표 · 화면 배치가 옛것이라 엉뚱한 줄에 그려진다(계약 2-7).
        Some("add-pack") if args.len() >= 3 => {
            let mut order = archive_engine::packs::AddOrder::default();
            for a in &args[3..] {
                if let Some(v) = a.strip_prefix("--from-store=") {
                    order.from_store = Some(PathBuf::from(v));
                } else if let Some(v) = a.strip_prefix("--ids=") {
                    order.ids.extend(v.split(',').filter(|s| !s.is_empty()).map(str::to_owned));
                } else if a == "--prefer-given" {
                    order.prefer_given = true; // 미리보기용(판정 R39) — 임시 사본에만
                } else if a.starts_with("--") {
                    return Err(format!("add-pack이 모르는 선택입니다: {a}").into());
                } else {
                    order.files.push(PathBuf::from(a));
                }
            }
            let started = Instant::now();
            let report = write(Path::new(&args[2]), |tx| archive_engine::packs::add_pack(tx, &order, &archive_engine::packs::RustLayouter))?;
            let mut answer = report.to_json();
            answer["ms"] = json!(started.elapsed().as_secs_f64() * 1000.0);
            println!("{answer}");
            Ok(())
        }
        // **앱을 닫고** 돌린다 — 앱이 연 저장소를 다른 프로세스가 고쳐 쓰면 켜진 앱의 줄 열쇠 ↔ 자리 표 · 화면 배치가 옛것이라 엉뚱한 줄에 그려진다(계약 2-7).
        Some("remove-pack") if args.len() >= 4 => {
            let mut order = archive_engine::packs::RemoveOrder { id: args[3].clone(), delete: false };
            for a in &args[4..] {
                match a.as_str() {
                    "--delete" => order.delete = true,
                    _ => return Err(format!("remove-pack이 모르는 선택입니다: {a}").into()),
                }
            }
            let started = Instant::now();
            let report = write(Path::new(&args[2]), |tx| archive_engine::packs::remove_pack(tx, &order, &archive_engine::packs::RustLayouter))?;
            let mut answer = report.to_json();
            answer["ms"] = json!(started.elapsed().as_secs_f64() * 1000.0);
            println!("{answer}");
            Ok(())
        }
        Some("pack-out") if args.len() == 5 => {
            println!("{}", archive_engine::legacy::pack_out(Path::new(&args[2]), &args[3], Path::new(&args[4]))?);
            Ok(())
        }
        // 넣고 빼기(계약 2-7): 저장소 파일을 바꿔 넣지 않고 제자리에서 한 거래로 고쳐 쓴다(`{"op":"apply"}`와 같은 몸 — 열린 저장소 대신 파일).
        // **앱을 닫고** 돌린다 — 앱이 연 저장소를 다른 프로세스가 고쳐 쓰면 켜진 앱의 줄 열쇠 ↔ 자리 표 · 화면 배치가 옛것이라 엉뚱한 줄에 그려진다(계약 2-7).
        Some("apply-layout") if args.len() >= 4 => {
            let started = Instant::now();
            let (mut originals, mut remove, mut covers) = (Vec::new(), Vec::new(), CoversAsk::Default);
            for a in &args[4..] {
                if let Some(ids) = a.strip_prefix("--remove=") {
                    remove.extend(ids.split(',').filter(|s| !s.is_empty()).map(str::to_owned));
                } else if let Some(keys) = a.strip_prefix("--covers=") {
                    covers = if keys == "all" { CoversAsk::All } else { CoversAsk::Tracks(keys.split(',').filter(|s| !s.is_empty()).map(str::to_owned).collect()) };
                } else if a.starts_with("--") {
                    return Err(format!("apply-layout이 모르는 선택입니다: {a}").into());
                } else {
                    originals.push(PathBuf::from(a));
                }
            }
            let order = read_order(Path::new(&args[3]), &originals, remove, covers)?;
            let report = write(Path::new(&args[2]), |tx| run_order(tx, &order))?;
            let mut answer = report.to_json();
            answer["ms"] = json!(started.elapsed().as_secs_f64() * 1000.);
            println!("{answer}");
            Ok(())
        }
        // 같음의 눈(canon — 번호 없이 적은 답 묶음)을 표준 출력으로. 기본은 단계 0 · 4 · 7 · 8 · 11 · 14 · 가로 32열 · 조회 목록 없음.
        Some("canon") if args.len() >= 3 => {
            let mut o = CanonOpts { levels: vec![0, 4, 7, 8, 11, 14], max_x: 32, queries: false };
            for a in &args[3..] {
                if a == "--queries" {
                    o.queries = true;
                } else if let Some(list) = a.strip_prefix("--levels=") {
                    o.levels = list.split(',').map(str::parse).collect::<std::result::Result<_, _>>()?;
                } else if let Some(n) = a.strip_prefix("--max-x=") {
                    o.max_x = n.parse()?;
                } else {
                    return Err(format!("canon이 모르는 선택입니다: {a}").into());
                }
            }
            println!("{}", canon_store(Path::new(&args[2]), &o)?);
            Ok(())
        }
        Some("tile") if args.len() == 5 => {
            let q: Value = serde_json::from_str(&args[3])?;
            let packs = q["packs"].as_array().ok_or("packs 누락")?.iter().filter_map(Value::as_i64).collect();
            let store = Store::open(Path::new(&args[2]))?;
            let req = TileRequest { level: q["level"].as_u64().ok_or("level 누락")? as usize, x: q["x"].as_i64().ok_or("x 누락")?, chunk: q["chunk"].as_i64().ok_or("chunk 누락")?, packs, filter: None, variants: store.variants_of(&q)? };
            let bytes = build_tile(&store, &req)?;
            let t = decode(&bytes)?;
            fs::write(&args[4], &bytes)?;
            println!("{}", json!({"bytes":bytes.len(),"bands":t.bands.len(),"cells":t.cells.len(),"events":t.events.len(),"pills":t.pills.len(),
                "sections":t.sections.iter().map(|s| json!([s.kind,s.items.len()])).collect::<Vec<_>>(),"strings":t.strings.len(),"origin":t.origin,"span":t.span}));
            Ok(())
        }
        Some("verify-tiles") if args.len() >= 3 => verify_tiles(Path::new(&args[2]), args.get(3).map(|v| v.parse()).transpose()?.unwrap_or(2000)),
        // --filter를 붙이면 같은 타일을 거르개와 함께 한 번 더 재어 '거르개 · 단계 L' 줄을 덧붙인다.
        Some("bench") if args.len() == 4 || (args.len() == 5 && args[4] == "--filter") => bench(Path::new(&args[2]), Path::new(&args[3]), args.len() == 5),
        Some("reindex") if args.len() == 3 => {
            let started = Instant::now();
            archive_engine::builder::reindex(Path::new(&args[2]))?;
            println!("{}", json!({"reindexed": args[2], "seconds": started.elapsed().as_secs_f64(), "bytes": fs::metadata(&args[2])?.len()}));
            Ok(())
        }
        Some("query") if args.len() == 4 => {
            let q: Value = serde_json::from_str(&args[3])?;
            println!("{}", Store::open(Path::new(&args[2]))?.call(&q)?);
            Ok(())
        }
        // 문서 그림 하나를 파일로 꺼낸다(열쇠 `img:<DLC id>/<그림 id>` — 문서 기록의 images[이름].key). 확인용.
        Some("blob") if args.len() == 5 => {
            let store = Store::open(Path::new(&args[2]))?;
            let (mime, bytes) = store.blob(&args[3])?.ok_or_else(|| format!("그림이 저장소에 없습니다: {}", args[3]))?;
            fs::write(&args[4], &bytes)?;
            println!("{}", json!({"key":args[3],"mime":mime,"bytes":bytes.len()}));
            Ok(())
        }
        Some("check-pack") if args.len() == 4 => {
            let raw = read_htpack(Path::new(&args[2]))?;
            fs::write(&args[3], serde_json::to_vec(&raw)?)?;
            println!("전용 팩 읽기 완료");
            Ok(())
        }
        _ => Err("사용법: generate2 새저장소 사건수 원문폴더 [--search off] / build 새저장소 기본팩 [얹는팩…] --calendar=calendar-cache.json [--calendar-narrow] [--now=ISO시각(+09:00 꼴)] / add-pack 저장소 [파일…] [--from-store=저장소 --ids=id,…] [--prefer-given](앱을 닫고) / remove-pack 저장소 DLC-id [--delete](앱을 닫고) / import-layout 기본팩.htpack|- 배치.json|.htlayout 새저장소 [원본…] [--from-store 지금저장소] / check-layout 배치.htlayout [원본…] [--from-store 지금저장소] / pack-out 저장소 DLC-id 꺼낼.htpack / apply-layout 저장소 배치.json|.htlayout [원본.htpack…] [--remove=DLC-id] [--covers=트랙열쇠,…|all](앱을 닫고) / canon 저장소 [--queries] [--levels=0,4,…] [--max-x=32] / tile 저장소 요청JSON 결과.bin / verify-tiles 저장소 [표본수] / bench 저장소 결과.json [--filter] / reindex 저장소 / query 저장소 요청 / blob 저장소 그림열쇠 꺼낼파일 / check-pack 전용팩 결과".into()),
    }
}

// 측정 실행: 배포 빌드한 시제품을 측정 모드로 띄우고, 끝나면 구간별 판정을 한 줄씩 보여 준다.
// 사용: node prototype/scripts/measure.mjs --db <저장소> --out <새 결과 폴더> [--seconds 30] [--repeats 3] [--cold no]
//        [--sections 끌기,확대,돋보기,밀집,세로,자료집] [--from <분> --to <분>] [--hide cells,tabs] [--text paragraph|atlas]
//        [--capture-only [--capture-scene 밀집] [--capture-mag 1.5]] [--phone yes(휴대폰의 좁힌 왼쪽 칸 — --capture-size 1100x507과 함께)]
//        계보 창 구간(D1 — 기본 목록에는 없음): --sections 승계표,세계표 --kin-polity <정권 uid> --kin-family <뿌리 뼈대 uid>
// 구간마다 처음 1회(찬 상태 — 타일 보관을 비우고)는 따로 적고 판정에 넣지 않는다. 그 뒤 --repeats회를 재서 판정한다.
// 이미 있는 결과 폴더는 덮어쓰지 않는다. 화면 측정은 로그인한 그래픽 세션에서, 다른 빌드 · 자료 생성을 멈추고 돌린다.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = name => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };
const db = option('db'), out = option('out');
if (!db || !out) {
  console.error('사용: measure.mjs --db <저장소> --out <새 결과 폴더> [--seconds 10] [--repeats 1] [--sections 끌기,확대] [--from 분 --to 분] [--hide 층,…] [--capture-only]');
  process.exit(2);
}
const exe = path.join(prototype, 'app/build/windows/x64/runner/Release/archive_prototype.exe');
if (!fs.existsSync(exe)) { console.error('실행본이 없습니다. scripts/dev.ps1 app-build 를 먼저 돌리세요: ' + exe); process.exit(1); }
if (!fs.existsSync(db)) { console.error('저장소가 없습니다: ' + db); process.exit(1); }
const target = path.resolve(out);
if (fs.existsSync(path.join(target, '측정.json'))) { console.error('기존 측정 결과를 덮어쓰지 않습니다: ' + target); process.exit(1); }
fs.mkdirSync(target, { recursive: true });

// --memory-dir(판정 R50): 앱의 기억 자리를 결과 폴더 안으로 — 측정 모드는 기억을 읽지도 쓰지도 않지만, 운영체제의 앱 자료 폴더(감독의 %APPDATA%)를 묻지도 않게.
const pass = [`--db=${path.resolve(db)}`, `--measure=${target}`, '--exit=yes', '--offline=yes', `--memory-dir=${path.join(target, '_memory')}`];
// --text paragraph|atlas = 글자 방식, --capture-scene 밀집 · --capture-mag 1.5 = 1배 그림을 뜰 장면과 돋보기 배율
// --cold no = 구간마다의 '처음 1회(찬 상태)'를 건너뛴다
for (const name of ['seconds', 'repeats', 'sections', 'from', 'to', 'hide', 'text', 'cold', 'capture-scene', 'capture-mag', 'capture-size', 'capture-scroll', 'capture-pick', 'capture-echo', 'capture-script', 'kin-polity', 'kin-family', 'phone']) if (option(name) !== undefined) pass.push(`--${name}=${option(name)}`);
if (args.includes('--capture-only')) pass.push('--capture-only=yes');
// 기본값은 앱과 같다: 여섯 구간 · 30초 · 3회 + 처음 1회.
const seconds = Number(option('seconds') ?? 30), repeats = Number(option('repeats') ?? 3) + (option('cold') === 'no' ? 0 : 1);
const sections = (option('sections') ?? '끌기,확대,돋보기,밀집,세로,자료집').split(',').length;
// 실행 시각을 넘긴다 → 앱이 '실행부터 첫 조작이 가능해질 때까지'(다시 열기)를 시작-장면.json과 측정.json에 적는다.
pass.push(`--launched=${Date.now()}`);
const run = spawnSync(exe, pass, { cwd: path.dirname(exe), timeout: (30 + sections * repeats * (seconds + 6)) * 1000 });
if (run.error) { console.error('실행 실패: ' + run.error.message); process.exit(1); }
const failed = path.join(target, '측정-실패.txt');
if (fs.existsSync(failed)) { console.error(fs.readFileSync(failed, 'utf8')); process.exit(1); }
if (args.includes('--capture-only')) { console.log('그림 저장: ' + path.join(target, '화면-1배.png')); process.exit(0); }
const file = path.join(target, '측정.json');
if (!fs.existsSync(file)) { console.error('측정 결과가 저장되지 않았습니다'); process.exit(1); }
const report = JSON.parse(fs.readFileSync(file, 'utf8'));
const f = (v, digits = 2) => (typeof v === 'number' ? v.toFixed(digits) : '-');
console.log(`${report.result} · ${report.display_hz}Hz · 사건 ${report.database?.meta?.count} · 상주 최고 ${(report.peak_rss_bytes / 1048576).toFixed(0)}MiB · 전원 ${report.machine?.power}${report.hidden_layers?.length ? ' · 끈 층: ' + report.hidden_layers.join(',') : ''}`);
for (const c of report.cases) {
  const v = c.verdict, label = `${c.name}#${c.repeat}${c.cold ? '(처음)' : ''}`;
  if (c.valid === false) console.log(`  ${label} 무효 — 다시 재세요: ${c.outside_inputs?.length ? '측정 도중 밖에서 입력이 들어옴 ' + JSON.stringify(c.outside_inputs.slice(0, 3)) : '장면이 기대만큼 찍히지 않음(창이 가려졌나 확인)'}`);
  // 놓친 장면의 까닭: 만들기 · 칠하기가 예산을 넘었나, 일은 가벼웠는데 장면이 늦게 시작됐나(간격 — 다른 프로그램 · 화면 합성기의 흔들림).
  const why = v.missed_ratio > 0 && v.missed_by ? `(만들기 ${v.missed_by.build} · 칠하기 ${v.missed_by.raster} · 간격 ${v.missed_by.gap})` : '';
  console.log(`  ${label} ${v.pass ? '합격' : '미달'} | 장면 ${v.frames} · 놓침 ${f(v.missed_ratio * 100)}%${why} · 연달아 ${v.max_consecutive_missed} · 50ms+ ${v.over_50ms}` +
    ` | 만들기 p50 ${f(c.build_ms.p50)} p99 ${f(v.build_p99_ms)} · 칠하기 p50 ${f(c.raster_ms.p50)} p99 ${f(v.raster_p99_ms)} (한도 ${f(v.budget_ms * .8)}) · 입력→반응 p95 ${f(c.input_to_first_response_ms?.p95)}` +
    ` | 도형 p95 ${c.shapes.p95 ?? '-'} · 글자 p95 ${c.labels.p95 ?? '-'} · 새 글자 ${c.new_glyphs} | 빈 자리 ${c.blank_tiles} · 메움 ${c.cover_tiles} · 타일 왕복 p95 ${f(c.tile_round_trip_ms.p95, 1)}ms · 단계 ${c.level_at_end} · 상주 ${f(c.rss_mib?.max, 0)}MiB`);
  // 계보 창 구간(승계표 · 세계표): 창을 연 비용과 예산 대조(설계 6-1 · 6-2 — 전체 판정에는 넣지 않음, 시간은 이 PC 값으로 판정).
  if (c.kin_view) {
    const b = c.kin_budget ?? {}, mark = k => (b[k]?.pass === false ? '✗' : b[k]?.pass ? '✓' : '-');
    console.log(`    계보 ${c.kin_view}${c.kin_error ? ' 오류: ' + c.kin_error : ''} · 열기 ${f(c.kin_open_ms, 0)}ms · 기록 ${c.kin_record_bytes ?? '-'}B · 받기 ${f(c.kin_fetch_ms)}${mark('fetch_ms')} · 풀기 ${f(c.kin_decode_ms)}${mark('decode_ms')}` +
      ` · 자리 셈 p99 ${f(c.kin_layout_ms?.p99)}${mark('layout_p99_ms')} · 고르기 p99 ${f(c.kin_pick_ms?.p99, 3)}${mark('pick_p99_ms')} · 빈 자리 ${c.kin_blank}${mark('blank')} · 지은 수 최대 ${c.kin_built_max}${mark('built_max')}` +
      `${c.kin_view === 'family' ? ` · 선 최대 ${c.kin_lines_max}${mark('lines_max')}` : ''} · 예산 ${b.pass ? '안' : '넘음'}`);
  }
}

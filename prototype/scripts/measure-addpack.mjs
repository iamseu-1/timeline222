// 천만 재기의 재는 틀(한 벌 P4 과제 11 · 걸음 1 — 11a): 저장소 사본에 `archive-tool add-pack` · `remove-pack`을 돌려 시간 · 메모리 정점 · 몫을 표로 적는다.
//
// 재는 것(열 번 가운데값 — 판이 클수록 --runs로 줄임):
//   · 시간      Windows 시계로 잰 프로세스 전체 시간(wall) + 엔진 답의 `ms`(명령 전체) · `ms_read`(읽기 · 판 대조) · `ms_layout`(배치) · `ms_apply`(apply)
//   · 몫        엔진 답의 `steps`(choose · packs · delete · insert · relink · globals · entities(항목 기록 견줌) · summaries · range · order · names(이름 표 다시 펴기) · prints · meta · verify)
//   · 메모리    Windows 프로세스 정점 작업 집합(PeakWorkingSetSize — 같은 폴더의 peak-run.ps1이 GetProcessMemoryInfo로 읽음) + 정점 커밋
//   · 저장소    넣기 전 · 뒤 파일 크기 · 줄 수 · 다시 쓴 · 든 트랙 수 · 범위(scope) · 배치 횟수(layouts)
// 원본 저장소는 고치지 않는다 — 늘 작업 폴더(TMP 아래)에 사본을 만들어 거기서 돈다(회마다 새 사본). 끝나면 사본을 지운다.
// 판단 기준(10초 · 2GB)과 견주어 '넘음 / 안 넘음'만 표에 찍는다 — 결론은 이 도구가 내지 않는다.
// ※ 바탕값 주의: P3 과제 16(부분 셈 — DLC가 닿는 트랙만 배치) 전의 엔진은 `add_pack`이 배치를 통째로 셈한다. 그때 잰 값은 '부분 셈 전' 바탕값이다 — 결과 JSON의 note에 적힌다.
//
// 한 줄 명령(작업 폴더에서) — 부분 셈이 들어오면 같은 명령을 다시 돌려 견준다:
//   node prototype/scripts/measure-addpack.mjs run --store=<저장소.db> --dlc=<큰 DLC.htpack> [--label=<이름>] [--runs=10] [--profile=<어느 설정으로 지은 실행본인지>]
//   node prototype/scripts/measure-addpack.mjs matrix --file=<matrix.json> [--runs=10]      matrix.json = [{ "label": "…", "store": "…db", "dlc": "….htpack", "runs": 3 }, …]
//   node prototype/scripts/measure-addpack.mjs build --out=<새 저장소.db> --packs=<기본.htpack>,<얹는.htpack>,… [--now=<ISO>] [--calendar=<달력 표>] [--label=<이름>]
//        (저장소를 `archive-tool build`로 짓는다 — 짓는 시간 · 메모리도 같이 잰다. 이 길로 지은 저장소만 `add-pack`이 받는다: DLC id · 원본 · 지문이 저장소에 든다)
//   node prototype/scripts/measure-addpack.mjs report --file=<결과 JSON>      (저장된 결과를 표로 다시 찍는다 — run · matrix가 쓴 JSON)
//   node prototype/scripts/measure-addpack.mjs exec --label=<이름> [--mem-limit-gib=6] -- <archive-tool 인자…>      (예: generate2 — 시간 · 메모리 정점만 재고 도구 답을 결과 JSON에 적는다)
// 저장소를 다시 짓는 법(11a에서 쓴 세계 — add-pack은 **DLC id · 원본(packs.original) · 지문이 든 저장소**만 받는다. `archive-tool generate2`의 가상 저장소는 그런 것이 없어 받지 않는다):
//   node prototype/scripts/big-dlc.mjs --events=100000 --spread=even --id=bw-100k --out=<폴더>/bw-100k.htpack          (저장소 바닥이 될 가상 세계)
//   node prototype/scripts/measure-addpack.mjs build --out=<폴더>/s100k.db --packs=<폴더>/bw-100k.htpack              (그 세계를 통째로 지은 저장소)
//   node prototype/scripts/big-dlc.mjs --events=100000 --spread=even|one --id=d100k-even|d100k-one --out=<폴더>/….htpack   (얹을 큰 DLC — 새 트랙으로 든다)
// 선택:
//   --remove         remove-pack도 잰다(기본 켜짐. --no-remove로 끔) · --remove-delete 원본까지 버리는 remove-pack (기본은 보관함에 남김)
//   --tool=<archive-tool 경로>   (또는 환경 변수 HT_ARCHIVE_TOOL · 없으면 prototype/engine/target/release/archive-tool)
//   --work=<폴더>     사본 · 임시 파일을 둘 곳(기본 <TMP>/measure-addpack — 큰 저장소는 D:처럼 넉넉한 드라이브로)
//   --results=<폴더>  결과 JSON을 둘 곳(기본 prototype/results/addpack — git 밖)
//   --long-min=30     첫 회가 이보다 오래 걸리면 그 판은 한 번만 재고 멈춘다(까닭을 결과에 적음)
//   --timeout-min=120 한 번 부르는 데 이보다 오래 걸리면 죽인다(결과에 timeout으로 적음)
//   --mem-limit-gib=0 엔진 프로세스가 쓸 수 있는 메모리(커밋) 한도 GiB — 0은 한도 없음. 같은 PC에서 다른 작업이 돌 때 폭주한 실행이 남의 일을 굶기지 않게 Job Object로 건다. 넘으면 프로세스가 죽고 결과에 mem_limit으로 적힌다
// 종료 코드: 0 = 잰 것을 적음(엔진이 거절하거나 시간 초과여도 그 사실을 적고 0) / 2 = 사용법 · 도구 없음.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(scripts, '..');
const peakRun = path.join(scripts, 'peak-run.ps1');
const rawArgv = process.argv.slice(2);
const dashAt = rawArgv.indexOf('--');
const argv = dashAt >= 0 ? rawArgv.slice(0, dashAt) : rawArgv; // `exec … -- <archive-tool 인자>`: -- 뒤는 도구에 그대로 넘긴다
const passThrough = dashAt >= 0 ? rawArgv.slice(dashAt + 1) : [];
const command = argv[0] && !argv[0].startsWith('--') ? argv[0] : 'run';
const args = argv.filter((a, i) => !(i === 0 && !a.startsWith('--')));
const option = (name, fallback = '') => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const flags = new Set(['--no-remove', '--remove-delete', '--keep']);
const unknown = args.filter(a => !flags.has(a) && !/^--(store|dlc|label|runs|profile|tool|work|results|long-min|timeout-min|mem-limit-gib|file|out|packs|now|calendar)=/.test(a));
const die = (msg, code = 2) => { console.error(`measure-addpack: ${msg}`); process.exit(code); };
if (unknown.length || !['run', 'matrix', 'build', 'exec', 'report'].includes(command)) {
  die(`모르는 인자: ${unknown.join(' ') || command}\n사용: node prototype/scripts/measure-addpack.mjs run --store=<db> --dlc=<htpack> [--label=…] [--runs=10]\n      node prototype/scripts/measure-addpack.mjs matrix --file=<matrix.json> [--runs=10]\n      node prototype/scripts/measure-addpack.mjs build --out=<db> --packs=<a.htpack>,<b.htpack> [--now=<ISO>] [--calendar=<표>]`);
}
const toolNames = process.platform === 'win32' ? ['archive-tool.exe', 'archive-tool'] : ['archive-tool', 'archive-tool.exe'];
const tool = [option('tool'), process.env.HT_ARCHIVE_TOOL || '', ...toolNames.map(n => path.join(prototype, 'engine', 'target', 'release', n))]
  .find(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
if (!tool) die(`엔진 도구(${toolNames[0]})가 없습니다 — 먼저 cargo build --release --locked 또는 --tool=<경로>.`);
if (process.platform !== 'win32') die('메모리 정점은 Windows 전용입니다(peak-run.ps1).');
const tmpRoot = process.env.TMP || process.env.TEMP || os.tmpdir();
const work = path.resolve(option('work') || path.join(tmpRoot, 'measure-addpack'));
const resultsDir = path.resolve(option('results') || path.join(prototype, 'results', 'addpack'));
const runsAsked = Number(option('runs', '10'));
const longMs = Number(option('long-min', '30')) * 60_000;
const timeoutMs = Number(option('timeout-min', '120')) * 60_000;
const memLimitBytes = Math.round(Number(option('mem-limit-gib', '0')) * 1024 ** 3);
if (!Number.isInteger(runsAsked) || runsAsked < 1) die('--runs는 1 이상의 정수입니다.');
const withRemove = !args.includes('--no-remove');
const removeDelete = args.includes('--remove-delete');
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(resultsDir, { recursive: true });

// ---- 재기 ----

const MiB = 1048576;
const median = (v) => { const s = v.filter(x => typeof x === 'number' && Number.isFinite(x)).sort((a, b) => a - b); if (!s.length) return null; const n = s.length; return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2; };
const round = (x, d = 1) => (typeof x === 'number' ? Math.round(x * 10 ** d) / 10 ** d : x);
let counter = 0;
/** 프로그램 하나를 부르고 시간 · 메모리 정점을 잰다(peak-run.ps1). */
function measured(exe, exeArgs, { timeout = timeoutMs } = {}) {
  const base = path.join(work, `call-${process.pid}-${++counter}`);
  const request = `${base}.req.json`;
  fs.writeFileSync(request, JSON.stringify({ exe, args: exeArgs, stdout: `${base}.out`, stderr: `${base}.err`, cwd: '', result: `${base}.res.json`, timeout_ms: timeout, mem_limit_bytes: memLimitBytes || undefined }), 'utf8');
  const r = spawnSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', peakRun, '-Request', request], { encoding: 'utf8' });
  const resFile = `${base}.res.json`;
  if (!fs.existsSync(resFile)) throw new Error(`peak-run.ps1이 결과를 남기지 않았습니다(종료 ${r.status}): ${String(r.stderr || r.stdout).slice(0, 400)}`);
  const res = JSON.parse(fs.readFileSync(resFile, 'utf8').replace(/^﻿/, ''));
  const stdout = fs.readFileSync(`${base}.out`, 'utf8'), stderr = fs.readFileSync(`${base}.err`, 'utf8');
  for (const f of [request, resFile, `${base}.out`, `${base}.err`]) fs.rmSync(f, { force: true });
  return { ...res, stdout, stderr };
}
const lastJson = (text) => { try { return JSON.parse(String(text).trim().split('\n').pop()); } catch { return null; } };
const sizeOf = (f) => { try { return fs.statSync(f).size + (fs.existsSync(`${f}-wal`) ? fs.statSync(`${f}-wal`).size : 0); } catch { return null; } };
const sha = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const loadPercent = () => {
  const r = spawnSync('powershell', ['-NoProfile', '-Command', '(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average'], { encoding: 'utf8' });
  const v = Number(String(r.stdout).trim());
  return Number.isFinite(v) ? v : null;
};
const machine = () => ({
  cpu: os.cpus()[0]?.model, logical_cpus: os.cpus().length, ram_gib: round(os.totalmem() / 1024 ** 3), free_ram_gib_before: round(os.freemem() / 1024 ** 3), cpu_load_percent_before: loadPercent(),
  note: '같은 PC에서 다른 작업이 함께 돌 수 있다 — 위 부하 값을 보고 값을 읽는다',
});
const toolInfo = () => ({ path: tool, bytes: fs.statSync(tool).size, modified: fs.statSync(tool).mtime.toISOString(), sha256: sha(tool).slice(0, 16), profile: option('profile') || '(미기재)' });

/** 엔진 호출 한 번의 요약: 시간 · 메모리 · 엔진 답. */
function summarizeCall(r) {
  const answer = lastJson(r.stdout);
  const steps = Object.fromEntries(((answer && answer.steps) || []).map(([n, ms]) => [n, ms]));
  return {
    ok: !!(r.exit === 0 && !r.timeout && answer), exit: r.exit, timeout: r.timeout, mem_limit_gib: memLimitBytes ? round(memLimitBytes / 1024 ** 3) : null,
    mem_limit_hit: !!(memLimitBytes && r.exit !== 0 && /memory allocation|alloc|메모리/i.test(String(r.stderr)) || (memLimitBytes && r.exit !== 0 && (r.exit >>> 0) === 0xC0000409)), error: r.exit === 0 && !r.timeout ? null : (String(r.stderr).trim() || String(r.stdout).trim()).slice(0, 600),
    wall_ms: r.wall_ms, cpu_ms: r.cpu_ms, peak_ws_mib: round(r.peak_ws_bytes / MiB), peak_commit_mib: round(r.peak_commit_bytes / MiB),
    ms: answer && answer.ms, ms_read: answer && answer.ms_read, ms_layout: answer && answer.ms_layout, ms_apply: answer && answer.ms_apply, steps,
    rows_before: answer && answer.rows_before, rows_after: answer && answer.rows_after, rewrote: answer && answer.rewrote && answer.rewrote.length, added: answer && answer.added && answer.added.length,
    removed: answer && answer.removed && answer.removed.length, scope: answer && answer.scope, layouts: answer && answer.layouts, globals: answer && answer.globals, names: answer && answer.names,
    first_pos: answer && answer.first_pos, packs: answer && answer.packs, kept: answer && answer.kept, unkept: answer && answer.unkept, deleted: answer && answer.deleted,
  };
}

function aggregate(calls) {
  const ok = calls.filter(c => c.ok);
  const pick = (f) => median(ok.map(f));
  const stepNames = [...new Set(ok.flatMap(c => Object.keys(c.steps)))];
  return {
    n: calls.length, ok: ok.length,
    wall_ms: pick(c => c.wall_ms), wall_ms_min: ok.length ? Math.min(...ok.map(c => c.wall_ms)) : null, wall_ms_max: ok.length ? Math.max(...ok.map(c => c.wall_ms)) : null, cpu_ms: pick(c => c.cpu_ms), ms: pick(c => c.ms), ms_read: pick(c => c.ms_read), ms_layout: pick(c => c.ms_layout), ms_apply: pick(c => c.ms_apply),
    steps: Object.fromEntries(stepNames.map(n => [n, pick(c => c.steps[n])])),
    peak_ws_mib: pick(c => c.peak_ws_mib), peak_ws_mib_max: ok.length ? Math.max(...ok.map(c => c.peak_ws_mib)) : null, peak_commit_mib: pick(c => c.peak_commit_mib),
    wall_ms_all: calls.map(c => c.wall_ms),
    // 판단 기준(10초 · 2GB)과의 견줌 — 사실만 적는다.
    over_10s: ok.length ? pick(c => c.wall_ms) > 10_000 : null, over_2gib: ok.length ? Math.max(...ok.map(c => c.peak_ws_mib)) > 2048 : null,
  };
}

function seriesRun({ label, store, dlc, runs }) {
  const dlcId = (() => { // DLC id는 check-pack으로 읽는다(remove-pack에 쓴다)
    const probe = path.join(work, `probe-${process.pid}.json`);
    const r = spawnSync(tool, ['check-pack', dlc, probe], { encoding: 'utf8' });
    if (r.status !== 0) die(`DLC를 읽을 수 없습니다(${dlc}): ${String(r.stderr || r.stdout).trim()}`, 1);
    const raw = JSON.parse(fs.readFileSync(probe, 'utf8'));
    fs.rmSync(probe, { force: true });
    return String(raw.id);
  })();
  for (const side of ['-wal', '-shm']) if (fs.existsSync(`${store}${side}`)) console.error(`경고: 원본 저장소 옆에 ${path.basename(store)}${side}가 있습니다 — 사본에는 .db만 옮깁니다.`);
  const info = { label, store: path.resolve(store), store_bytes: sizeOf(store), store_sha256_16: null, dlc: path.resolve(dlc), dlc_bytes: sizeOf(dlc), dlc_id: dlcId, when: new Date().toISOString(), tool: toolInfo(), machine: machine(), runs_asked: runs,
    note: '부분 셈(P3 과제 16) 전 바탕값 — add_pack이 배치를 통째로 셈한다. 부분 셈이 들어온 뒤의 값과 견주려고 같은 명령을 다시 돌린다.' };
  const adds = [], removes = [];
  let stoppedBecause = null;
  for (let i = 1; i <= runs; i++) {
    const copy = path.join(work, `${label.replace(/[^\w.-]/g, '_')}-run${i}.db`);
    fs.rmSync(copy, { force: true });
    const t0 = performance.now();
    fs.copyFileSync(store, copy);
    const copyMs = performance.now() - t0;
    const before = sizeOf(copy);
    const add = summarizeCall(measured(tool, ['add-pack', copy, dlc]));
    add.store_bytes_before = before; add.store_bytes_after = sizeOf(copy); add.copy_ms = Math.round(copyMs);
    adds.push(add);
    process.stderr.write(`  [${label}] 회 ${i}/${runs} add-pack: ${add.ok ? `${round(add.wall_ms / 1000, 2)}초 · 정점 ${add.peak_ws_mib}MiB` : `실패 — ${add.timeout ? '시간 초과' : add.error}`}\n`);
    if (withRemove && add.ok) {
      const rmArgs = ['remove-pack', copy, dlcId, ...(removeDelete ? ['--delete'] : [])];
      const beforeRm = sizeOf(copy);
      const rm = summarizeCall(measured(tool, rmArgs));
      rm.store_bytes_before = beforeRm; rm.store_bytes_after = sizeOf(copy);
      removes.push(rm);
      process.stderr.write(`  [${label}] 회 ${i}/${runs} remove-pack: ${rm.ok ? `${round(rm.wall_ms / 1000, 2)}초 · 정점 ${rm.peak_ws_mib}MiB` : `실패 — ${rm.timeout ? '시간 초과' : rm.error}`}\n`);
    }
    if (!args.includes('--keep')) fs.rmSync(copy, { force: true });
    if (!add.ok) { stoppedBecause = `add-pack이 ${add.timeout ? `${timeoutMs / 60000}분 안에 끝나지 않아 죽임(시간 초과)` : '실패'}: ${add.error || ''}`.trim(); break; }
    if (i === 1 && runs > 1 && (add.wall_ms > longMs || (removes[0] && removes[0].wall_ms > longMs))) {
      stoppedBecause = `첫 회가 ${Math.round(Math.max(add.wall_ms, removes[0] ? removes[0].wall_ms : 0) / 60000)}분 걸려 ${longMs / 60000}분을 넘음 — 이 판은 한 번만 재고 멈춤`;
      break;
    }
  }
  const result = { ...info, runs_done: adds.length, stopped: stoppedBecause, add: { runs: adds, summary: aggregate(adds) }, remove: withRemove ? { runs: removes, summary: aggregate(removes) } : null };
  return result;
}

// ---- 표 ----

const sec = (ms) => (typeof ms === 'number' ? `${round(ms / 1000, ms >= 100_000 ? 0 : 2)}` : '—');
const msText = (ms) => (typeof ms === 'number' ? String(round(ms, ms >= 100 ? 0 : 1)) : '—');
const mib = (v) => (typeof v === 'number' ? (v >= 10240 ? `${round(v / 1024, 1)}GiB` : `${round(v, 0)}MiB`) : '—');
const STEP_ORDER = ['choose', 'packs', 'delete', 'insert', 'relink', 'globals', 'entities', 'summaries', 'range', 'order', 'names', 'prints', 'meta', 'verify'];
function tableOf(results, kind) {
  const rows = [];
  rows.push('시간 · 메모리(전체 = Windows 시계로 잰 프로세스 시간 · CPU = 프로세스가 쓴 CPU 시간 — 같은 PC에서 다른 작업이 돌면 전체가 늘고 CPU는 덜 늘어난다):');
  rows.push('');
  rows.push('| 판 | 잰 회 | 전체 가운데(초) | 전체 최소~최대(초) | CPU 가운데(초) | 정점 작업 집합 | 정점 커밋 | 줄 전→후 | 다시 쓴/든/뺀 트랙 | 범위 | 10초 넘음 | 2GB 넘음 |');
  rows.push('| --- | ---: | ---: | --- | ---: | ---: | ---: | --- | --- | --- | --- | --- |');
  for (const r of results) {
    const part = r[kind];
    if (!part) continue;
    const s = part.summary, first = part.runs.find(c => c.ok) || part.runs[0] || {};
    rows.push(`| ${r.label} | ${s.ok}/${s.n} | ${sec(s.wall_ms)} | ${sec(s.wall_ms_min)}~${sec(s.wall_ms_max)} | ${sec(s.cpu_ms)} | ${mib(s.peak_ws_mib_max)} | ${mib(s.peak_commit_mib)} | ${first.rows_before ?? '—'}→${first.rows_after ?? '—'} | ${first.rewrote ?? '—'}/${first.added ?? '—'}/${first.removed ?? '—'} | ${first.scope ?? '—'} · 배치 ${first.layouts ?? '—'}번 | ${s.over_10s === null ? '—' : s.over_10s ? '넘음' : '안 넘음'} | ${s.over_2gib === null ? '—' : s.over_2gib ? '넘음' : '안 넘음'} |`);
  }
  rows.push('');
  rows.push('몫(엔진 답의 ms 가운데값 — 읽기 · 판 대조 / 배치 / apply는 명령 안의 큰 몫, 그 아래는 apply의 걸음):');
  rows.push('');
  rows.push(`| 판 | 엔진 ms | 읽기·판 대조 | 배치 | apply | ${STEP_ORDER.map(n => n === 'entities' ? '항목 기록 견줌(entities)' : n === 'names' ? '이름 표 다시 펴기(names)' : n === 'verify' ? '표본 대조(verify)' : n).join(' | ')} |`);
  rows.push(`| --- | ---: | ---: | ---: | ---: | ${STEP_ORDER.map(() => '---:').join(' | ')} |`);
  for (const r of results) {
    const part = r[kind];
    if (!part) continue;
    const s = part.summary;
    rows.push(`| ${r.label} | ${msText(s.ms)} | ${msText(s.ms_read)} | ${msText(s.ms_layout)} | ${msText(s.ms_apply)} | ${STEP_ORDER.map(n => msText(s.steps[n])).join(' | ')} |`);
  }
  return rows.join(String.fromCharCode(10));
}
function report(results) {
  const lines = [];
  lines.push(`부분 셈(P3 과제 16) 전 바탕값 — 가운데값(전체 · 엔진 몫 ms) · 정점은 잰 회 가운데 가장 큰 값. 도구 ${results[0].tool.profile} · ${path.basename(tool)}`);
  lines.push('');
  lines.push('### add-pack');
  lines.push(tableOf(results, 'add'));
  if (results.some(r => r.remove)) { lines.push(''); lines.push('### remove-pack'); lines.push(tableOf(results, 'remove')); }
  for (const r of results) if (r.stopped) lines.push(`\n※ ${r.label}: ${r.stopped}`);
  return lines.join('\n');
}
const stamp = () => new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-');
function save(results, name) {
  const file = path.join(resultsDir, `${name}-${stamp()}.json`);
  fs.writeFileSync(file, JSON.stringify(results, null, 1), 'utf8');
  return file;
}

// ---- 명령 ----

if (command === 'build') {
  const out = option('out'), packs = option('packs').split(',').filter(Boolean);
  if (!out || !packs.length) die('build에는 --out=<db>와 --packs=<기본.htpack>,<얹는…>이 필요합니다.');
  if (fs.existsSync(out)) die(`이미 있는 저장소는 덮어쓰지 않습니다: ${out}`);
  const now = option('now', '2026-10-15T12:00:00+09:00');
  const calendar = option('calendar', path.join(prototype, 'engine', 'tests', 'fixtures', 'lay', 'calendar-slice.json'));
  const label = option('label') || path.basename(out, '.db');
  const call = summarizeCall(measured(tool, ['build', out, ...packs, `--now=${now}`, ...(calendar ? [`--calendar=${calendar}`] : [])]));
  const result = { label, kind: 'build', out: path.resolve(out), out_bytes: sizeOf(out), packs: packs.map(p => ({ file: p, bytes: sizeOf(p) })), now, calendar, when: new Date().toISOString(), tool: toolInfo(), machine: machine(), call };
  console.log(`build ${label}: ${call.ok ? '성공' : `실패 — ${call.timeout ? '시간 초과' : call.error}`} · ${sec(call.wall_ms)}초 · 정점 ${mib(call.peak_ws_mib)} · 저장소 ${mib((result.out_bytes || 0) / MiB)} · 줄 ${call.rows_after ?? '—'}`);
  console.log(`결과: ${save(result, `build-${label}`)}`);
  process.exit(0);
}

if (command === 'report') {
  const file = option('file');
  if (!file) die('report에는 --file=<결과 JSON>이 필요합니다.');
  console.log(report(JSON.parse(fs.readFileSync(file, 'utf8'))));
  process.exit(0);
}
if (command === 'exec') {
  if (!passThrough.length) die('exec에는 -- 뒤에 archive-tool 인자가 필요합니다.');
  const label = option('label') || passThrough[0];
  const call = summarizeCall(measured(tool, passThrough));
  const result = { label, kind: 'exec', args: passThrough, when: new Date().toISOString(), tool: toolInfo(), machine: machine(), call };
  console.log(`exec ${label}: ${call.ok ? '성공' : `실패 — ${call.timeout ? '시간 초과' : call.error}`} · ${sec(call.wall_ms)}초 · 정점 ${mib(call.peak_ws_mib)}`);
  console.log(`결과: ${save(result, `exec-${label.replace(/[^\w.-]/g, '_')}`)}`);
  process.exit(0);
}

let cells;
if (command === 'matrix') {
  const file = option('file');
  if (!file) die('matrix에는 --file=<matrix.json>이 필요합니다.');
  cells = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')).map(c => ({ ...c, runs: c.runs || runsAsked }));
} else {
  const store = option('store'), dlc = option('dlc');
  if (!store || !dlc) die('run에는 --store=<db>와 --dlc=<htpack>이 필요합니다.');
  cells = [{ label: option('label') || `${path.basename(store, '.db')}+${path.basename(dlc, '.htpack')}`, store, dlc, runs: runsAsked }];
}
for (const c of cells) {
  if (!fs.existsSync(c.store)) die(`저장소가 없습니다: ${c.store}`);
  if (!fs.existsSync(c.dlc)) die(`DLC가 없습니다: ${c.dlc}`);
}
const results = [];
for (const c of cells) {
  process.stderr.write(`\n=== ${c.label} (저장소 ${mib((sizeOf(c.store) || 0) / MiB)} · 최대 ${c.runs}회)\n`);
  const r = seriesRun(c);
  results.push(r);
  save([r], `cell-${c.label.replace(/[^\w.-]/g, '_')}`);
}
console.log(report(results));
console.log(`\n결과 JSON: ${save(results, command === 'matrix' ? 'matrix' : 'run')}`);

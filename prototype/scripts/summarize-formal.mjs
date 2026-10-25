// 정식 측정 결과(results/formal/<자료>/측정.json)를 보고서에 실을 표(Markdown)로 줄인다.
// 사용: node prototype/scripts/summarize-formal.mjs [결과 폴더=prototype/results/formal] > 표.md
// 구간마다 3회의 값은 '가운데 값(가장 나쁜 값)'으로 적는다. 처음 1회(찬 상태)는 따로 적는다.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(process.argv[2] ?? path.join(prototype, 'results', 'formal'));
const names = { '100k': '10만', '1m': '100만', '10m': '1,000만', moonwake: '월흔해' };
const f = (v, digits = 2) => (typeof v === 'number' && Number.isFinite(v) ? v.toFixed(digits) : '-');
const median = list => list.slice().sort((a, b) => a - b)[Math.floor(list.length / 2)];
const both = (list, digits = 2) => (list.length ? `${f(median(list), digits)} (${f(Math.max(...list), digits)})` : '-');

const reports = {};
for (const key of Object.keys(names)) {
  const file = path.join(root, key, '측정.json');
  if (fs.existsSync(file)) reports[key] = JSON.parse(fs.readFileSync(file, 'utf8'));
}

for (const [key, r] of Object.entries(reports)) {
  const T = 1000 / r.display_hz;
  console.log(`\n### ${names[key]} — 전체 ${r.result} · ${r.display_hz.toFixed(1)}Hz(T ${f(T)}ms) · 상주 최고 ${Math.round(r.peak_rss_bytes / 1048576)}MiB · 전원 ${r.machine?.power} · 저장소 ${f((r.database?.bytes ?? 0) / 1048576, 0)}MiB\n`);
  console.log('| 구간 | 판정(3회) | 놓침 % | 놓친 까닭(만들기 · 칠하기 · 간격) | 연달아 | 50ms+ | 만들기 p99 ms | 칠하기 p99 ms | 입력→반응 p95 ms | 빈 자리 | 도형 p95 | 글자 p95 | 상주 MiB |');
  console.log('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  const sections = [...new Set(r.cases.map(c => c.name))];
  for (const name of sections) {
    const runs = r.cases.filter(c => c.name === name && !c.cold);
    const verdicts = runs.map(c => (c.valid === false ? '무효' : c.verdict.pass ? '합격' : '미달')).join(' · ');
    const by = key2 => runs.reduce((n, c) => n + (c.verdict.missed_by?.[key2] ?? 0), 0);
    console.log(`| ${name} | ${verdicts} | ${both(runs.map(c => c.verdict.missed_ratio * 100))} | ${by('build')} · ${by('raster')} · ${by('gap')} | ${Math.max(...runs.map(c => c.verdict.max_consecutive_missed))} | ${runs.reduce((n, c) => n + c.verdict.over_50ms, 0)} | ${both(runs.map(c => c.verdict.build_p99_ms))} | ${both(runs.map(c => c.verdict.raster_p99_ms))} | ${both(runs.map(c => c.input_to_first_response_ms?.p95 ?? NaN).filter(Number.isFinite))} | ${runs.reduce((n, c) => n + c.blank_tiles, 0)} | ${f(median(runs.map(c => c.shapes.p95 ?? 0)), 0)} | ${f(median(runs.map(c => c.labels.p95 ?? 0)), 0)} | ${f(Math.max(...runs.map(c => c.rss_mib?.max ?? 0)), 0)} |`);
  }
  const cold = r.cases.filter(c => c.cold);
  if (cold.length) {
    console.log(`\n처음 1회(찬 상태 · 판정에 넣지 않음): ${cold.map(c => `${c.name} 놓침 ${f(c.verdict.missed_ratio * 100)}% · 연달아 ${c.verdict.max_consecutive_missed} · 만들기 p99 ${f(c.verdict.build_p99_ms)} · 칠하기 p99 ${f(c.verdict.raster_p99_ms)} · 메움 ${c.cover_tiles} · 빈 자리 ${c.blank_tiles}`).join(' / ')}`);
  }
}

// 자료 크기와 무관: 같은 장면 · 같은 구간의 만들기 · 칠하기 p99(3회의 가운데 값)를 크기끼리 견준다.
const sizes = ['100k', '1m', '10m'].filter(k => reports[k]);
if (sizes.length > 1) {
  console.log('\n### 자료 크기와 무관 — 3회의 가운데 값(ms)과 100만 → 1,000만의 차이\n');
  console.log(`| 구간 | 값 | ${sizes.map(k => names[k]).join(' | ')} | 100만 → 1,000만 |`);
  console.log(`| --- | --- | ${sizes.map(() => '---').join(' | ')} | --- |`);
  for (const name of ['끌기', '확대', '돋보기', '밀집', '세로', '자료집']) {
    for (const [label, pick] of [['만들기 p99', c => c.verdict.build_p99_ms], ['칠하기 p99', c => c.verdict.raster_p99_ms], ['도형 p95', c => c.shapes.p95 ?? 0]]) {
      const values = sizes.map(k => median(reports[k].cases.filter(c => c.name === name && !c.cold).map(pick)));
      const a = values[sizes.indexOf('1m')], b = values[sizes.indexOf('10m')];
      const change = a > 0 && b !== undefined ? `${b >= a ? '+' : ''}${f((b / a - 1) * 100, 0)}%` : '-';
      console.log(`| ${name} | ${label} | ${values.map(v => f(v, label.startsWith('도형') ? 0 : 2)).join(' | ')} | ${change} |`);
    }
  }
}

// 다시 열기: 100만 자료를 다시 열어 첫 조작이 가능해질 때까지(ms).
const reopen = fs.existsSync(root) ? fs.readdirSync(root).filter(n => n.startsWith('reopen-')).map(n => path.join(root, n, '측정.json')).filter(p => fs.existsSync(p)).map(p => JSON.parse(fs.readFileSync(p, 'utf8')).first_ready_ms) : [];
if (reopen.length) console.log(`\n### 다시 열기(100만 · 첫 조작까지)\n\n${reopen.map(v => f(v, 0)).join(' · ')}ms — 가운데 값 ${f(median(reopen), 0)}ms · 가장 느린 값 ${f(Math.max(...reopen), 0)}ms`);

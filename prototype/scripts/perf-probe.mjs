// 성능 살핌: 한 구간(기본 돋보기)을 여러 조건(층을 하나씩 뺌 · 엔진의 시험용 손잡이)으로 돌려 어디서 시간이 나가는지 표로 낸다.
// 실제 실행본(scripts/dev.ps1 app-build)으로 재므로 재는 동안 다른 작업을 돌리지 말고 앱 창을 가리지 말 것.
// 사용: node prototype/scripts/perf-probe.mjs --db prototype/data/v3b-1m/archive.db --out prototype/results/perf-probe/<이름> [--section 돋보기] [--seconds 10]
//       [--only 기준,칸-없이] — 조건은 아래 CASES. 결과: <out>/살핌.json · 살핌.md
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const db = path.resolve(option('--db', path.join(prototype, 'data', 'v3b-1m', 'archive.db')));
const out = path.resolve(option('--out', path.join(prototype, 'results', 'perf-probe', new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 13))));
const section = option('--section', '돋보기'), seconds = option('--seconds', '10');
const only = (option('--only', '') || '').split(',').filter(Boolean);
if (fs.existsSync(path.join(out, '살핌.json'))) { console.error('기존 결과를 덮어쓰지 않습니다: ' + out); process.exit(1); }
fs.mkdirSync(out, { recursive: true });

// 조건: hide = 그리지 않을 층(app/lib/scene의 c.hide 열쇠), env = 엔진의 시험용 손잡이.
const CASES = [
  { name: '기준', hide: '' },
  { name: '칸-없이', hide: 'cells' },
  { name: '칸-이름-없이', hide: 'cellNames' },
  { name: '사건-없이', hide: 'events' },
  { name: '띠-없이', hide: 'bands' },
  { name: '선과-이름표-막대-없이', hide: 'links,scopes,hangs,figures,rails,tabs' },
  { name: '떠오름-없이', hide: 'fade' },
  { name: '칸을-성기게-6', hide: '', env: { ARCHIVE_CELL_LOD: '6' } },
  { name: '칸을-성기게-4', hide: '', env: { ARCHIVE_CELL_LOD: '4' } },
];

const rows = [];
for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  const folder = path.join(out, one.name);
  fs.rmSync(folder, { recursive: true, force: true });
  const run = spawnSync(process.execPath, [path.join(prototype, 'scripts', 'measure.mjs'), '--db', db, '--out', folder, '--sections', section, '--seconds', seconds, '--repeats', '1', '--cold', 'no',
    ...(one.hide ? ['--hide', one.hide] : [])], { encoding: 'utf8', env: { ...process.env, ...(one.env || {}) } });
  const file = path.join(folder, '측정.json');
  if (run.status !== 0 || !fs.existsSync(file)) { console.log(`✗ ${one.name} — 실패: ${(run.stderr || run.stdout || '').slice(-200)}`); continue; }
  const c = JSON.parse(fs.readFileSync(file, 'utf8')).cases.find(x => x.name === section && !x.cold);
  const row = { name: one.name, hide: one.hide, env: one.env || {}, missed: +(c.verdict.missed_ratio * 100).toFixed(2), run: c.verdict.max_consecutive_missed,
    build: [c.build_ms.p50, c.build_ms.p95, c.build_ms.p99], raster: [c.raster_ms.p50, c.raster_ms.p95, c.raster_ms.p99], paint: [c.paint_ms.p50, c.paint_ms.p99], text: [c.text_prepare_ms.p50, c.text_prepare_ms.p99],
    shapes: c.shapes.p95, labels: c.labels.p95, blanks: c.blank_tiles, valid: c.valid };
  rows.push(row);
  console.log(`${row.name.padEnd(14)} 놓침 ${String(row.missed).padStart(6)}% · 연달아 ${String(row.run).padStart(3)} | 만들기 p95 ${row.build[1].toFixed(2)} p99 ${row.build[2].toFixed(2)} | 칠하기 p95 ${row.raster[1].toFixed(2)} p99 ${row.raster[2].toFixed(2)} | 도형 ${row.shapes} · 글자 ${row.labels} · 빈 자리 ${row.blanks}${row.valid ? '' : ' · 무효'}`);
}
fs.writeFileSync(path.join(out, '살핌.json'), JSON.stringify({ db, section, seconds: +seconds, rows }, null, 1));
fs.writeFileSync(path.join(out, '살핌.md'), `# 성능 살핌 — ${section} · ${path.basename(path.dirname(db))} · ${seconds}초\n\n| 조건 | 놓침 % | 연달아 | 만들기 p50/p95/p99 | 칠하기 p50/p95/p99 | 도형 p95 | 글자 p95 | 빈 자리 |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n`
  + rows.map(r => `| ${r.name} | ${r.missed} | ${r.run} | ${r.build.map(v => v.toFixed(2)).join(' / ')} | ${r.raster.map(v => v.toFixed(2)).join(' / ')} | ${r.shapes} | ${r.labels} | ${r.blanks} |`).join('\n') + '\n');
console.log('저장: ' + path.join(out, '살핌.md'));

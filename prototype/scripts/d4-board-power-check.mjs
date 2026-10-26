// D4 집합 보기 × 집권·실권 단 × 붕당 렌즈. 견본(등불 연대기 samples/sample-lantern.json)은 읽기만 하고 판만 담은 가상 DLC를 따로 얹는다.
// 견본의 단체: 산호 해상 동맹의 진주파 · 닻파(집권 · 연정 · 실권 1340~1352) · 하연 연합 왕국/공화국의 항로당 · 등불당(집권 · 연정) — 1000~1700년을 본다.
// 사용: node prototype/scripts/d4-board-power-check.mjs <새 결과 이름>
// 결과: prototype/results/<이름>/ · prototype/data/<이름>-lantern/archive.db (기존 결과는 덮어쓰지 않음).
// 실제 엔진의 타일을 판 끔/켬/붕당 렌즈/둘 다로 읽어 칸과 딸린 항목이 빠지거나 겹치지 않는지 대조한다. 성능은 재지 않는다.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { bootWeb, contextOf, runModules, root, prototype, minute } from './export/base.mjs';
import { useCalendarCopy } from './oracle/cal-copy.mjs';

useCalendarCopy('d4-board-power-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const name = process.argv[2];
assert.ok(name && /^[\w-]+$/.test(name), '새 결과 이름(영문·숫자·밑줄·붙임표)을 적습니다');
const output = path.join(prototype, 'results', name);
assert.ok(!fs.existsSync(output), `결과가 이미 있습니다: ${output}`);
fs.mkdirSync(output, { recursive: true });
const tool = process.env.HT_ARCHIVE_TOOL || path.join(prototype, 'engine', 'target', 'release', process.platform === 'win32' ? 'archive-tool.exe' : 'archive-tool');
assert.ok(fs.existsSync(tool), 'D4 작업 폴더의 엔진을 먼저 빌드합니다');
const HT = bootWeb();
const report = { 조합: {}, 문제: [] };
const check = (ok, text) => { if (!ok) report.문제.push(text); };
const run = args => JSON.parse(execFileSync(tool, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).trim());
const write = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');

// 이진 타일 2판(계약 5절)의 구역 표와 문자열만 푼다. 칸/딸린 항목의 실제 값을 읽기 위한 독립 대조다.
function decode(file) {
  const b = fs.readFileSync(file);
  assert.equal(b.readUInt32LE(0), 0x32545448, '타일 머리');
  assert.equal(b.readUInt16LE(4), 2, '타일 판');
  const sections = [], count = b.readUInt32LE(40), strings = b.readUInt32LE(44);
  let end = 72 + count * 16;
  for (let i = 0; i < count; i++) {
    const at = 72 + i * 16, kind = b.readUInt32LE(at), n = b.readUInt32LE(at + 4), cols = b.readUInt32LE(at + 8), data = b.readUInt32LE(at + 12) * 4;
    end = Math.max(end, data + n * cols * 4);
    sections.push({ kind, rows: Array.from({ length: n }, (_, r) => Array.from({ length: cols }, (_, c) => b.readUInt32LE(data + (c * n + r) * 4))) });
  }
  const textAt = end + (strings + 1) * 4;
  const texts = Array.from({ length: strings }, (_, i) => b.toString('utf8', textAt + b.readUInt32LE(end + i * 4), textAt + b.readUInt32LE(end + (i + 1) * 4)));
  return { sections, texts };
}

for (const sample of ['lantern']) {
  const raw = JSON.parse(fs.readFileSync(path.join(root, 'samples', `sample-${sample}.json`), 'utf8'));
  const boardId = `d4-${sample}`, boardKey = `view:${boardId}`, themeKey = 'theme:faction';
  const from = 1000, to = 1700; // 산호 해상 동맹(1031~1402) · 하연 연합 왕국(1402~1641) · 하연 공화국(1641~)의 단체가 드는 해
  const overlay = {
    format: 'history-timeline-dlc', formatVersion: 3, id: `sample-d4-board-${sample}`, name: '가상 집합 보기 · 집권과 실권', version: '1.0.0',
    views: [{ id: boardId, name: '바다 동맹과 강 왕국 견주기', start: from, end: to,
      // 원래 줄과 반대 차례로 모아 다시 돌리는 띠 번호와 기본 띠 번호가 달라도 맞는지 본다.
      members: [...raw.periods].reverse().map(p => ({ track: p.track, polity: `${raw.id}/${p.id}` })) }],
  };
  const ctx = contextOf(HT, [raw, overlay]);
  const out = await runModules(ctx);
  const board = out.boards?.variants.find(v => v.key === boardKey);
  check(!!board, `${sample}: 집합 보기 변형이 빠짐`);
  check((ctx.notes.집합보기?.뺀판 || []).length === 0, `${sample}: 판 내보내기 실패 ${JSON.stringify(ctx.notes.집합보기?.뺀판)}`);
  check(out.variants?.some(v => v.key === themeKey), `${sample}: 붕당 렌즈 변형이 빠짐`);
  const files = {
    raw: path.join(output, `sample-${sample}.htpack`), overlay: path.join(output, `d4-${sample}.htpack`),
    layout: path.join(output, `d4-${sample}-layout.json`), db: path.join(prototype, 'data', `${name}-${sample}`, 'archive.db'),
  };
  assert.ok(!fs.existsSync(files.db), `저장소가 이미 있습니다: ${files.db}`);
  fs.writeFileSync(files.raw, await HT.packFile.build(raw));
  fs.writeFileSync(files.overlay, await HT.packFile.build(overlay));
  write(path.join(output, `d4-${sample}.json`), overlay);
  write(files.layout, out);
  const one = report.조합[sample] = { 파일: files, 판: boardKey, 렌즈: themeKey, 연도: [from, to], 분: [minute(from), minute(to)], 내보내기: ctx.notes.집합보기 };
  if (!board) continue;
  one.가져오기 = run(['import-layout', files.raw, files.layout, files.db, files.overlay]);
  one.타일검증 = run(['verify-tiles', files.db, '2000']);
  check(one.타일검증.누락_중복 === 0, `${sample}: 타일 검증 누락·중복`);
  const layout = run(['query', files.db, JSON.stringify({ op: 'layout' })]);
  const variants = layout.variants.filter(v => [boardKey, themeKey].includes(v.key));
  write(path.join(output, `d4-${sample}-layout-engine.json`), layout);
  one.엔진변형 = variants.map(v => ({ key: v.key, kind: v.kind, track: v.track }));
  const totalRows = layout.tracks.reduce((n, t) => n + t.rows.length, 0), packs = layout.packs.map(p => p.id);
  const level = 10, width = 256 * 4 ** level, x0 = Math.floor(minute(from) / width), x1 = Math.floor(minute(to) / width);
  const snapshots = {};
  for (const [state, active] of Object.entries({ off: [], board: [boardKey], lens: [themeKey], both: [boardKey, themeKey] })) {
    const cells = new Map(), detail = new Map(), tabs = new Map();
    for (let chunk = 0; chunk < Math.ceil(totalRows / 8); chunk++) for (let x = x0; x <= x1; x++) {
      const file = path.join(output, `${sample}-${state}-${x}-${chunk}.bin`);
      run(['tile', files.db, JSON.stringify({ level, x, chunk, packs, variants: active }), file]);
      const tile = decode(file);
      for (const s of tile.sections) for (const r of s.rows) {
        if (s.kind === 2 && (r[5] & 255) === 8) cells.set(r[2], [tile.texts[r[3]], r[6], r[7], r[8]]);
        if (s.kind === 43 && r[9] === 8) detail.set(r[2], [r[7], r[8], ...r.slice(9, 13), tile.texts[r[13]]]);
        if (s.kind === 47 && r[9] === 7) tabs.set(r[2], [r[7], r[8], ...r.slice(9, 13), tile.texts[r[3]], tile.texts[r[13]]]);
      }
    }
    const sorted = map => [...map.values()].map(v => JSON.stringify(v)).sort();
    snapshots[state] = { cells: sorted(cells), detail: sorted(detail), tabs: sorted(tabs) };
  }
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  for (const section of ['cells', 'detail', 'tabs']) {
    check(same(snapshots.off[section], snapshots.board[section]), `${sample}: 판을 켜면 ${section}이 달라짐`);
    check(same(snapshots.lens[section], snapshots.both[section]), `${sample}: 붕당 렌즈와 판을 함께 켜면 ${section}이 달라짐`);
  }
  check(snapshots.off.cells.some(s => JSON.parse(s)[1] === 2), `${sample}: 집권 칸 검사 자료 없음`);
  check(snapshots.off.cells.some(s => JSON.parse(s)[1] === 3), `${sample}: 실권 칸 검사 자료 없음`);
  check(snapshots.lens.cells.some(s => JSON.parse(s)[1] === 0), `${sample}: 붕당 렌즈 칸 검사 자료 없음`);
  one.타일대조 = Object.fromEntries(Object.entries(snapshots).map(([state, s]) => [state, Object.fromEntries(Object.entries(s).map(([k, v]) => [k, v.length]))]));
  write(path.join(output, `d4-${sample}-tile-content.json`), snapshots);
}
write(path.join(output, '보고.json'), report);
console.log(JSON.stringify(report, null, 2));
assert.equal(report.문제.length, 0, report.문제.join('\n'));

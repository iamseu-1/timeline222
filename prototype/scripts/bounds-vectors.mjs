// 칸의 경계 벡터 뽑기(한 벌 P3 과제 6) — Node가 정답이다. `HT.buildModel`이 정권마다 두는 `p.cellBounds`(열거되지 않는 속성이라 이음매 ②의 덤프 `prep.json`에
// 들지 않는다)를 정답지 자료마다 적어, Rust `lay::model`의 `cellBounds`(`Obj::hidden`)가 같은지 prototype/engine/tests/lay_model.rs가 견준다.
// 사용(작업 폴더에서): node prototype/scripts/bounds-vectors.mjs
//   시간대가 Asia/Seoul이 아니면 스스로 TZ=Asia/Seoul을 정한 자식 프로세스로 다시 돈다. 시계는 정답지와 같은 시각(진행 중 정권의 끝이 '오늘'에 달림).
//   입력은 Rust 검사(tests/common/oracle.rs의 inputs)와 같은 파일: sample · 굳힌 내장 팩(<내장>.json) · file · extra — 선택 자료(감독 PC의 파일)는 넣지 않는다(어느 PC에서나 같은 바이트).
//   보조 달력 날짜는 ICU로 읽는다(Rust는 잘린 표 tests/fixtures/lay/calendar-slice.json — seam_opts).
// 꼴: { now, fixtures: [{ name, periods: [[uid, [[칸 참조, lo, hi, [앞 칸 참조], [뒤 칸 참조], [끝을 자른 후대 uid]], …]], …] }] } — 경계가 있는 정권만, 모델 차례.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TZ = 'Asia/Seoul';
const self = fileURLToPath(import.meta.url);
if (process.env.TZ !== TZ) {
  const r = spawnSync(process.execPath, [self, ...process.argv.slice(2)], { env: { ...process.env, TZ }, stdio: 'inherit' });
  process.exit(r.status ?? 1);
}
const here = path.dirname(self);
const NOW_TEXT = '2026-10-15T12:00:00+09:00';
(await import('./oracle/clock.mjs')).installClock(NOW_TEXT);
const { bootWeb } = await import('./export/base.mjs');
const root = path.resolve(here, '..', '..');
const fixDir = path.resolve(here, '..', 'fixtures', 'oracle');
const outFile = path.resolve(here, '..', 'engine', 'tests', 'fixtures', 'lay', 'cell-bounds.json');

const HT = bootWeb();
const list = JSON.parse(fs.readFileSync(path.join(fixDir, 'list.json'), 'utf8'));
const abs = file => (path.isAbsolute(file) ? file : path.join(fixDir, file));
const fixtures = [];
for (const f of list) {
  if (f.optional) continue;
  const files = [];
  if (f.base.sample) files.push(path.join(root, 'samples', `${f.base.sample}.json`));
  else if (f.base.file) files.push(abs(f.base.file));
  else if (f.base.builtin) files.push(path.join(fixDir, `${f.base.builtin}.json`));
  for (const x of f.extra || []) files.push(abs(x));
  const raws = [];
  for (const file of files) {
    const bytes = fs.readFileSync(file);
    raws.push(/\.htpack$/i.test(file) ? (await HT.packFile.parse(new Uint8Array(bytes))).raw : JSON.parse(bytes.toString('utf8')));
  }
  const packs = raws.map((raw, i) => {
    const norm = HT.normalizePack(raw);
    if (!norm.pack) throw new Error(`${f.name}: 팩 ${i}를 읽지 못했습니다`);
    return norm.pack;
  });
  const model = HT.buildModel(packs, null, { groupBands: true });
  const periods = [];
  for (const p of model.periods) {
    if (!p.cellBounds || !p.cellBounds.size) continue;
    periods.push([p.uid, [...p.cellBounds].map(([ref, b]) => [ref, b.lo, b.hi, b.prev, b.next, b.succ.map(q => q.uid)])]);
  }
  fixtures.push({ name: f.name, periods });
}
const text = `${JSON.stringify({ now: NOW_TEXT, fixtures })}\n`;
fs.writeFileSync(outFile, text);
console.log(`bounds-vectors: ${path.relative(process.cwd(), outFile)} · ${text.length}자 · 자료 ${fixtures.length}개 · 경계 ${fixtures.reduce((n, f) => n + f.periods.reduce((m, p) => m + p[1].length, 0), 0)}개`);

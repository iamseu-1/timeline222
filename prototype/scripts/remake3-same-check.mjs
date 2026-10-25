// 리메이크 3단계 같음 검사(계획 docs/계획-리메이크-3단계.md 과제 3 ~ 6): 내보내기 JSON에서 **스키마 4가 더하는 것**(계약 1-1 초안)만 빼면
// 고치기 전과 바이트 같은가. 더하는 것 = 띠의 form · 칸 style 27비트(종류 1 · 2 · 9) · 칸 종류 9 · 일반 항목 구역 54 ~ 56 · 최상위 sphereLines · 인물 기록의 x_titles.
// 사용(작업 폴더에서):
//   node prototype/scripts/remake3-same-check.mjs --write-before   → prototype/results/remake3-before/<자료>.json (고치기 전에 한 번 — git 밖)
//   node prototype/scripts/remake3-same-check.mjs                  → 지금 내보내기를 견줘 같음 · 다름 · 더한 것의 수를 찍음(다르면 끝 코드 1)
//   [--only=<자료>,…]  자료: lantern(견본 등불) · east-asia(기본팩) · f4-crowns · f4-office · f4-sphere · f4-federation · f4-liege(형식 4 가상 팩)
// 자료마다 자식 프로세스로 돌린다(웹 코드를 전역에 싣는 bootWeb은 한 프로세스에 한 번 — 내장 팩이 쌓이지 않게).
// '오늘'(끝이 열린 시대 · 축 줄의 끝)은 기준을 쓴 시각으로 못 박는다(oracle/clock.mjs) — 기준을 쓴 날과 견주는 날이 다르면 그 끝만 하루씩 밀려 '다름'이 되기 때문.
//   --write-before는 쓴 시각을 remake3-before/_now.json에 자료마다 적고, 견줄 때 그 시각을 쓴다(적힌 것이 없는 옛 기준은 그 파일의 고친 시각).
//   [--now=<시각>] 또는 HT_ORACLE_NOW로 갈아 낄 수 있다(예: 2026-10-24T12:00:00+09:00).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { installClock } from './oracle/clock.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const before = path.join(prototype, 'results', 'remake3-before');
const after = path.join(prototype, 'results', 'remake3-after');
const INPUTS = ['lantern', 'east-asia', 'f4-crowns', 'f4-office', 'f4-sphere', 'f4-federation', 'f4-liege', 'f4-office3'];
/** f4-office3 = f4-office에 직위 줄 더(재상)와 그 줄의 빌림 · 교단의 끝 · 제국의 제 안의 실권자를 덧댄 것 — 정답지 자료(fixtures/oracle/f4-office3.json)를 그대로 읽는다 */
const fileOf = name => (name === 'f4-office3' ? path.join(prototype, 'fixtures', 'oracle', 'f4-office3.json') : path.join(prototype, 'fixtures', 'f4', `${name}.json`));

const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));

/** 자식: 자료 하나를 내보내 파일로 쓴다. */
async function one(name, file) {
  if (process.env.HT_ORACLE_NOW) installClock(process.env.HT_ORACLE_NOW); // 웹 코드를 싣기 전에(clock.mjs 머리말)
  if (name === 'east-asia') process.env.HT_EXPORT_PACK = 'east-asia';
  const base = await import(pathToFileURL(path.join(here, 'export', 'base.mjs')).href);
  let ctx;
  if (name.startsWith('f4-')) {
    const HT = base.bootWeb();
    ctx = base.contextOf(HT, [JSON.parse(fs.readFileSync(fileOf(name), 'utf8'))]);
  } else ctx = await base.loadContext();
  const out = await base.runModules(ctx, { has: m => fs.existsSync(path.join(here, 'export', `${m}.mjs`)) });
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(out) + '\n');
}

/** 스키마 4가 더하는 것을 빼고(같음 견주기용) 더한 것을 센다. */
function strip(out) {
  const added = { form: 0, style27: 0, kind9: 0, items: {}, sphereLines: 0, x_titles: 0 };
  for (const p of out.periods || []) if ('form' in p) { if (p.form) added.form++; delete p.form; }
  out.cells = (out.cells || []).filter(c => {
    if (c.kind === 9) { added.kind9++; return false; }
    if ((c.kind === 1 || c.kind === 2) && c.style & (1 << 27)) { added.style27++; c.style &= ~(1 << 27); }
    return true;
  });
  out.items = (out.items || []).filter(it => {
    if (it.section >= 54 && it.section <= 56) { added.items[it.section] = (added.items[it.section] || 0) + 1; return false; }
    return true;
  });
  if ('sphereLines' in out) { added.sphereLines = out.sphereLines.length; delete out.sphereLines; }
  for (const e of out.entities || []) {
    if (!e.json.includes('"x_titles"')) continue;
    const body = JSON.parse(e.json);
    if (!('x_titles' in body)) continue;
    delete body.x_titles;
    e.json = JSON.stringify(body);
    added.x_titles++;
  }
  return added;
}

if ('one' in args) {
  await one(args.one, args.out);
  process.exit(0);
}

const only = (args.only || '').split(',').map(s => s.trim()).filter(Boolean);
for (const n of only) if (!INPUTS.includes(n)) { console.error(`모르는 자료 ${n} (${INPUTS.join(' · ')})`); process.exit(2); }
const chosen = INPUTS.filter(n => !only.length || only.includes(n));
const write = 'write-before' in args;
const nowFile = path.join(before, '_now.json');
const nows = (() => { try { return JSON.parse(fs.readFileSync(nowFile, 'utf8')); } catch { return {}; } })();
const given = args.now || process.env.HT_ORACLE_NOW || '';
let bad = 0;
for (const name of chosen) {
  const file = path.join(write ? before : after, `${name}.json`);
  const prev = path.join(before, `${name}.json`);
  if (!write && !fs.existsSync(prev)) { console.log(`${name}: 기준이 없음 — 먼저 --write-before`); bad++; continue; }
  const now = given || (write ? new Date().toISOString() : nows[name] || fs.statSync(prev).mtime.toISOString());
  const r = spawnSync(process.execPath, [fileURLToPath(import.meta.url), `--one=${name}`, `--out=${file}`], { stdio: ['ignore', 'ignore', 'pipe'], encoding: 'utf8', env: { ...process.env, TZ: 'Asia/Seoul', HT_ORACLE_NOW: now } });
  if (r.status !== 0) { console.log(`${name}: 내보내기 실패\n${r.stderr}`); bad++; continue; }
  if (write) {
    nows[name] = now;
    fs.writeFileSync(nowFile, JSON.stringify(nows, null, 1) + '\n');
    console.log(`${name}: 기준을 씀 ${path.relative(prototype, file)} · 오늘 ${now}`);
    continue;
  }
  const cur = JSON.parse(fs.readFileSync(file, 'utf8'));
  const added = strip(cur);
  const old = JSON.parse(fs.readFileSync(prev, 'utf8'));
  strip(old); // 기준에 더한 것이 있으면 그것도 뺀다(기준을 고친 뒤에 다시 뜬 경우)
  const same = JSON.stringify(cur) === JSON.stringify(old);
  if (!same) {
    bad++;
    // 처음 다른 곳 하나만 알린다(열쇠 차례대로)
    let where = '';
    for (const k of Object.keys(old)) {
      if (JSON.stringify(old[k]) === JSON.stringify(cur[k])) continue;
      const a = old[k], b = cur[k];
      if (Array.isArray(a) && Array.isArray(b)) {
        const i = a.findIndex((x, j) => JSON.stringify(x) !== JSON.stringify(b[j]));
        where = `${k}[${i}] (길이 ${a.length} → ${b.length})\n  전: ${JSON.stringify(a[i]).slice(0, 300)}\n  뒤: ${JSON.stringify(b[i]).slice(0, 300)}`;
      } else where = k;
      break;
    }
    console.log(`${name}: 다름 — ${where}`);
  } else console.log(`${name}: 같음 · 더한 것 ${JSON.stringify(added)}`);
}
process.exit(bad ? 1 : 0);

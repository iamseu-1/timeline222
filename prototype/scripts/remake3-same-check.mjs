// 리메이크 3단계 같음 검사(계획 docs/계획-리메이크-3단계.md 과제 3 ~ 6): 내보내기 JSON에서 **스키마 4가 더하는 것**(계약 1-1 초안)만 빼면
// 고치기 전과 바이트 같은가. 더하는 것 = 띠의 form · 칸 style 27비트(종류 1 · 2 · 9) · 칸 종류 9 · 일반 항목 구역 54 ~ 56 · 최상위 sphereLines · 인물 기록의 x_titles.
// 기준 커밋(286327b — 이 스크립트를 더한 17d3bb5의 부모) 뒤에 들어와 함께 빼는 것(통합 가지 remake-int에서 셈 — 기준을 그 커밋 코드로 새로 뜨면 드러남):
//   · 제 안의 실권자 — 정권 기록 json의 power 가운데 over 없는 줄(이름만 — remake-5b의 a82b16d가 정규화에 더해 3단계 바탕으로 들어옴 · 구역 56의 짝 · `selfPower`로 셈).
//   · 6단계 앞몫(remake-6 0f97162 — `r6`으로 셈): 달력 넷의 항목 기록 cal:hebrew · cal:ethiopic · cal:coptic · cal:indian(걸음 4 — D10 달력 아홉 · `r6.cal`)과
//     형식 더하기 입력 칸 regnal(이름 번호) · faiths(종교) · leaderLabels(표기 낱말)(걸음 2 · `r6.input`). 입력 칸 셋은 출력 곳곳(칸 이름 'n세' · 대수 글 ·
//     구역 46의 d · faithSpans)에 스며 출력에서 빼기 어렵다 — 형식 4 입력(f4-*)에서 그 칸을 지우고 내보낸다(기준 · 지금 모두. 기준 커밋 코드는 그 칸을 읽지 않으므로
//     기준 출력은 그대로 — 그 칸이 바꾸는 출력은 check-format4 ⑱ · 정답지 · build-check가 본다).
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

/** 6단계 앞몫이 형식 4 입력에 더한 칸(머리말) — 기준 커밋 코드가 읽지 않는 칸이라 양쪽 입력에서 지운다. */
const LATER_INPUT = ['regnal', 'faiths', 'leaderLabels'];
/** 6단계 앞몫의 달력 넷(D10)이 더한 항목 기록(머리말) */
const LATER_CALS = new Set(['cal:hebrew', 'cal:ethiopic', 'cal:coptic', 'cal:indian']);
/** 입력 v(형식 4 팩 JSON)에서 LATER_INPUT 칸을 어디서든 지우고 지운 수를 돌려준다. */
function dropLaterInput(v) {
  if (Array.isArray(v)) return v.reduce((n, x) => n + dropLaterInput(x), 0);
  if (!v || typeof v !== 'object') return 0;
  let n = 0;
  for (const k of LATER_INPUT) if (k in v) { delete v[k]; n++; }
  for (const k of Object.keys(v)) n += dropLaterInput(v[k]);
  return n;
}
const readInput = name => { const raw = JSON.parse(fs.readFileSync(fileOf(name), 'utf8')); return { raw, dropped: dropLaterInput(raw) }; };

/** 자식: 자료 하나를 내보내 파일로 쓴다. */
async function one(name, file) {
  if (process.env.HT_ORACLE_NOW) installClock(process.env.HT_ORACLE_NOW); // 웹 코드를 싣기 전에(clock.mjs 머리말)
  if (name === 'east-asia') process.env.HT_EXPORT_PACK = 'east-asia';
  const base = await import(pathToFileURL(path.join(here, 'export', 'base.mjs')).href);
  let ctx;
  if (name.startsWith('f4-')) {
    const HT = base.bootWeb();
    ctx = base.contextOf(HT, [readInput(name).raw]); // 6단계 앞몫의 입력 칸을 지운 것(머리말)
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
  // 기준 커밋 뒤에 더한 것(머리말): 6단계 앞몫의 달력 넷 기록 · 제 안의 실권자(정권 기록 power의 over 없는 줄)
  added.r6 = { cal: 0, input: 0 };
  added.selfPower = 0;
  if (Array.isArray(out.entities)) out.entities = out.entities.filter(e => !(LATER_CALS.has(e.uid) && ++added.r6.cal));
  for (const e of out.entities || []) {
    if (e.kind !== 'period' || !e.json.includes('"power"')) continue;
    const body = JSON.parse(e.json);
    if (!Array.isArray(body.power)) continue;
    const kept = body.power.filter(w => w && typeof w === 'object' && w.over);
    if (kept.length === body.power.length) continue;
    added.selfPower += body.power.length - kept.length;
    if (kept.length) body.power = kept; else delete body.power;
    e.json = JSON.stringify(body);
  }
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
  if (name.startsWith('f4-')) added.r6.input = readInput(name).dropped; // 자식이 입력에서 지운 칸의 수(머리말)
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

// 형식 4 같음 확인(P3 과제 2) — 옛 형식 DLC를 to-f4.mjs로 한 번 바꾼 것이 원본과 **같은 배치**를 내는지, 내장 팩을 JSON으로 굳힌 것이 내장과 같은지 본다.
// 웹 코드(js/*.js)는 읽기만 한다. list.json의 자료(이름이 `@f4`로 끝나는 것은 이 도구가 낳는 쪽이라 뺀다)마다:
//   ① 원본 그대로         — 정답지와 같은 길(oracle/one.mjs: 자식 프로세스 · TZ=Asia/Seoul · HT_ORACLE_NOW · Date 흉내 · 모듈 스물 runModules)
//   ② 팩마다 to-f4로 바꾼 것 — 기본 DLC · 더 얹는 DLC 모두를 형식 4 .htpack으로 바꿔 같은 길로(one.mjs --packs=…)
//   ③ 내장 팩의 JSON      — 기본 DLC가 내장이면 굳힌 파일(base.file — 없으면 <내장 이름>.json)로 갈아 끼워 같은 길로
//   내장 팩이 이미 형식 4로 등록된 때: ①은 그 등록 꼴을 정규화가 내려 읽은 것, ②는 내려 읽은 옛 꼴을 to-f4가 다시 올린 것
//   (형식 4 → 옛 꼴 → 형식 4 한 바퀴 — 등록 꼴이 내림 · 올림에서 뜻을 잃지 않는지), ③은 굳힌 형식 4 JSON 그대로(엔진 · Rust 검사가 읽는 것)라 셋을 그대로 견준다.
// 셋을 `lay::same`(engine/src/lay/same.rs)과 같은 규칙으로 견준다: 열쇠 차례 무시 · 배열은 차례대로 · 수는 값으로(10과 10.0은 같다) ·
// `json` 열쇠의 JSON 글은 풀어서 · 머리 `$oracle` 건너뜀. '거의 같음'은 없다 — 다르면 경로를 앞 20개까지 보인다.
// ①≠②가 '올림이 옛 뜻을 바꾸는 곳'(HT.F4.project)처럼 알고 남긴 것이면 list.json의 <자료>@f4 항목에 "known"(까닭) · "knownDiffs"(곳 수)로 적는다 —
// 곳 수가 기록과 같을 때만 '알려진 차이'로 통과하고, 늘거나 줄거나 ①=②가 되면 실패한다(고치지 않고 적어 두는 자리 — HT.F4는 리메이크 세션의 js/core.js).
// 바꾸는 쪽(to-f4)은 **다른 시각 · 다른 시간대**로 돌린다(2031-03-04 · America/Los_Angeles) — 바꾼 파일에 '오늘'이 새어 들면 ①과 달라져 걸린다.
//
// 사용(작업 폴더에서):
//   node prototype/scripts/f4-same-check.mjs [--only=<자료>,…] [--seams=norm,prep,rows,out] [--write] [--keep]
//     --seams  견줄 이음매(없으면 out = 모듈 앞자리 스물 모두 = upto-lens.json)
//     --write  바꾼 형식 4 파일을 prototype/fixtures/oracle/f4/<이름>.htpack으로 쓴다(저장소 안의 입력만 — 저장소 밖 선택 자료의 것은 임시 폴더에).
//              쓰지 않으면 임시 폴더에 두고, f4/에 이미 있는 파일과 압축을 푼 글이 같은지만 본다(낡았으면 실패).
//     --keep   임시 폴더를 지우지 않고 자리를 알린다
// 종료 코드: 다른 곳 · 낡은 f4 파일 · 실패가 하나라도 있으면 1.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { useCalendarCopy } from './oracle/cal-copy.mjs';
import { listFile, missingNote } from './oracle/ktl.mjs';

useCalendarCopy('f4-same-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

/** 정답지가 고정하는 '오늘'과 시간대 — layout-oracle.mjs · Rust tests/common/oracle.rs와 같은 값. */
const ORACLE_ENV = { TZ: 'Asia/Seoul', HT_ORACLE_NOW: '2026-10-15T12:00:00+09:00' };
/** 바꾸는 쪽의 시각 · 시간대 — 일부러 정답지와 다르게. */
const CONVERT_ENV = { TZ: 'America/Los_Angeles', HT_ORACLE_NOW: '2031-03-04T05:06:07+09:00' };
const LIMIT = 20;
const HEADER = 52; // .htpack의 머리 길이(js/packfile.js)

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const repo = path.resolve(prototype, '..');
const fixDir = path.join(prototype, 'fixtures', 'oracle');
const f4Dir = path.join(fixDir, 'f4');

const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));
const csv = text => (text || '').split(',').map(s => s.trim()).filter(Boolean);
const die = msg => { console.error(`f4-same-check: ${msg}`); process.exit(2); };
for (const k of Object.keys(args)) if (!['only', 'seams', 'write', 'keep'].includes(k)) die(`모르는 인자 --${k} (only · seams · write · keep)`);
const SEAMS = args.seams === undefined ? ['out'] : csv(args.seams);
for (const s of SEAMS) if (!['norm', 'prep', 'rows', 'out'].includes(s)) die(`모르는 이음매 ${s} (norm · prep · rows · out)`);
const WRITE = args.write !== undefined;

// ── 견주기: engine/src/lay/same.rs의 diff를 줄 그대로 ──
const showOf = v => { const t = JSON.stringify(v); return [...t].length <= 60 ? t : `${[...t].slice(0, 60).join('')}…`; };
const isObj = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const jsonText = v => { if (typeof v !== 'string' || !(v.startsWith('{') || v.startsWith('['))) return undefined; try { return { v: JSON.parse(v) }; } catch { return undefined; } };
/** 두 JSON 값의 차이를 `"경로: 왼쪽 ≠ 오른쪽"`으로 앞 limit개까지. 같으면 빈 목록. */
function diffValues(a, b, limit = LIMIT) {
  const out = [];
  const join = (p, k) => (p === '' ? String(k) : `${p}.${k}`);
  const note = (p, l, r) => { if (out.length < limit) out.push(`${p === '' ? '(루트)' : p}: ${l} ≠ ${r}`); };
  const walk = (x, y, p) => {
    if (out.length >= limit) return;
    if (isObj(x) && isObj(y)) {
      const keys = [...new Set([...Object.keys(x), ...Object.keys(y)])].filter(k => k !== '$oracle').sort();
      for (const key of keys) {
        if (out.length >= limit) return;
        const at = join(p, key), hasL = Object.hasOwn(x, key), hasR = Object.hasOwn(y, key);
        if (hasL && hasR) {
          if (key === 'json') { const pl = jsonText(x[key]), pr = jsonText(y[key]); if (pl && pr) { walk(pl.v, pr.v, at); continue; } }
          walk(x[key], y[key], at);
        } else if (hasL) note(at, showOf(x[key]), '(없음)');
        else if (hasR) note(at, '(없음)', showOf(y[key]));
      }
    } else if (Array.isArray(x) && Array.isArray(y)) {
      if (x.length !== y.length) note(join(p, 'length'), String(x.length), String(y.length));
      for (let i = 0; i < Math.min(x.length, y.length); i++) { if (out.length >= limit) return; walk(x[i], y[i], join(p, i)); }
    } else if (typeof x === 'number' && typeof y === 'number') {
      if (x !== y) note(p, showOf(x), showOf(y));
    } else if (x !== y) note(p, showOf(x), showOf(y)); // 글 · 참 거짓 · null · 모양이 다른 값
  };
  walk(a, b, '');
  return out;
}

// ── 자식 프로세스 ──
const spawn = (script, argv, env) => spawnSync(process.execPath, [path.join(here, script), ...argv], { env: { ...process.env, ...env }, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', maxBuffer: 1 << 26 });
/** 표준 오류에서 사람이 읽을 한 줄 — 'Error'가 든 첫 줄(없으면 마지막 줄). */
const errorLine = text => { const lines = (text || '').trim().split('\n').filter(Boolean); return (lines.find(l => /Error|오류|실패|않습니다|없습니다/.test(l)) || lines.pop() || '(메시지 없음)').trim(); };
const lastLine = text => text.trim().split('\n').pop();

// ── 자료 목록 ──
const list = JSON.parse(fs.readFileSync(path.join(fixDir, 'list.json'), 'utf8'));
const only = csv(args.only);
for (const name of only) if (!list.some(f => f.name === name && !f.name.endsWith('@f4'))) die(`list.json에 없는(또는 @f4인) 자료 ${name}`);
const chosen = list.filter(f => !f.name.endsWith('@f4') && (!only.length || only.includes(f.name)));

/** 자료의 입력 목록 — to-f4에 줄 원본(`origin`) · 파일 이름 줄기(`stem` — f4/<줄기>.htpack) · 저장소 안인가. 기본 DLC가 내장이면 굳힌 파일(`frozen`)도. */
function sourcesOf(f) {
  const out = [];
  const add = (origin, file, stem) => out.push({ origin, file, stem, inRepo: path.resolve(file).startsWith(`${repo}${path.sep}`) });
  const stemOf = file => path.basename(file).replace(/\.(htpack|json)$/i, '');
  const b = f.base;
  if (b.sample) { const file = path.join(repo, 'samples', `${b.sample}.json`); add(file, file, stemOf(file)); }
  else if (b.builtin) { out.push({ origin: `builtin:${b.builtin}`, file: null, stem: b.builtin, inRepo: true, frozen: path.resolve(fixDir, b.file || `${b.builtin}.json`) }); }
  else if (b.file) { const file = path.resolve(fixDir, b.file); add(file, file, stemOf(file)); }
  else die(`자료 ${f.name}: base는 sample · builtin · file 중 하나여야 합니다`);
  for (const x of f.extra || []) { const file = listFile(fixDir, x); add(file, file, stemOf(file)); } // 옛 KTL 자리는 HT_KTL로(oracle/ktl.mjs)
  return out;
}

// ── 한 번 바꾼 것은 되쓴다(내장 east-asia는 일곱 자료가 함께 씀) ──
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ht-f4-same-'));
const converted = new Map(); // origin → { file, problems, stale }
const unpack = bytes => zlib.inflateSync(bytes.subarray(HEADER)).toString('utf8');
const claimed = new Map(); // 줄기 → origin(서로 다른 입력이 같은 f4 이름을 쓰지 못하게)
function convert(src) {
  if (converted.has(src.origin)) return converted.get(src.origin);
  if (claimed.has(src.stem) && claimed.get(src.stem) !== src.origin) die(`서로 다른 입력이 같은 f4 이름(${src.stem}.htpack)을 씁니다: ${claimed.get(src.stem)} · ${src.origin}`);
  claimed.set(src.stem, src.origin);
  const home = WRITE && src.inRepo ? f4Dir : path.join(tmp, 'f4');
  const file = path.join(home, `${src.stem}.htpack`);
  fs.mkdirSync(home, { recursive: true });
  const r = spawn('to-f4.mjs', [src.origin, file], CONVERT_ENV);
  const got = { file, problems: [], stale: null, error: null };
  if (r.status !== 0) { got.error = `to-f4가 ${r.status ?? r.signal}로 끝났습니다 — ${errorLine(r.stderr)}`; }
  else {
    got.problems = r.stdout.split('\n').filter(l => l.startsWith('문제:') || l.startsWith('읽기 오류:'));
    got.summary = lastLine(r.stdout);
    const committed = path.join(f4Dir, `${src.stem}.htpack`);
    if (!(WRITE && src.inRepo) && src.inRepo) {
      got.stale = !fs.existsSync(committed) ? '없음' : unpack(fs.readFileSync(committed)) === unpack(fs.readFileSync(file)) ? null : '낡음';
    }
  }
  converted.set(src.origin, got);
  return got;
}

/** 자식(one.mjs)으로 한 자료를 뽑는다 — packs가 있으면 입력을 그 파일들로 갈아 끼운다(빈 칸은 그대로). 돌려주는 값: { dir, files } 또는 { error }. */
function extract(f, tag, packs) {
  const dir = path.join(tmp, f.name.replace(/[^\w.+-]/g, '_'), tag);
  const argv = [`--name=${f.name}`, `--out=${dir}`, `--seams=${SEAMS.join(',')}`];
  if (packs) argv.push(`--packs=${packs.join('|')}`);
  const r = spawn('oracle/one.mjs', argv, ORACLE_ENV);
  if (r.status !== 0) return { error: `뽑기가 ${r.status ?? r.signal}로 끝났습니다 — ${errorLine(r.stderr)}` };
  try { return { dir, files: JSON.parse(lastLine(r.stdout)).files }; } catch { return { error: `뽑기의 마지막 줄을 읽지 못했습니다: ${lastLine(r.stdout)}` }; }
}

/** 두 뽑기를 같은 파일마다 견준다. 돌려주는 값: 다른 곳 목록(경로 앞 limit개까지). */
function compare(a, b, limit = LIMIT) {
  const lines = [];
  for (const file of a.files) {
    if (!b.files.includes(file)) { lines.push(`${file}: (왼쪽만 있음)`); continue; }
    const d = diffValues(JSON.parse(fs.readFileSync(path.join(a.dir, file), 'utf8')), JSON.parse(fs.readFileSync(path.join(b.dir, file), 'utf8')), limit);
    for (const x of d) lines.push(`${file} · ${x}`);
  }
  return lines.slice(0, limit);
}

// ── 본 ──
// '알려진 차이'는 list.json의 <자료>@f4 항목에 "known"(까닭)과 "knownDiffs"(①≠②가 모두 몇 곳)로 적힌 것 — 올림이 옛 뜻을 바꾸는 곳 같은 것. 기록과 곳 수가 같을 때만 통과하고, 늘거나 줄면 실패한다.
let same = 0;
const known = [];
const different = [];
const total = [];
try {
  for (const f of chosen) {
    const sources = sourcesOf(f);
    const missing = sources.filter(s => s.file && !fs.existsSync(s.file));
    if (missing.length) {
      if (f.optional) {
        const note = missingNote(f.name, missing.map(s => s.file)); // HT_REQUIRE_KTL=1이면 KTL이 없을 때 실패(판정 R58 ⑤-5)
        if (!note.fail) { console.log(note.text); continue; }
        console.error(note.text); total.push(f.name); different.push(`${f.name}(KTL 없음)`); continue;
      }
      console.error(`실패 ${f.name} — 파일이 없습니다: ${missing.map(s => s.file).join(' · ')}`);
      total.push(f.name); different.push(`${f.name}(파일 없음)`);
      continue;
    }
    total.push(f.name);
    const issues = []; // 이 자료의 다른 곳 · 실패(맨 앞이 '(참고)'면 실패가 아님)
    const verdict = [];
    const record = list.find(e => e.name === `${f.name}@f4` && e.known); // 알려진 차이의 기록(있으면)
    let knownSeen = false;

    // ① 원본 그대로
    const orig = extract(f, 'orig');
    if (orig.error) { console.error(`실패 ${f.name} ① ${orig.error}`); different.push(`${f.name}(①)`); continue; }

    // ② 팩마다 to-f4로 바꾼 것
    const conv = sources.map(convert);
    const failedConv = conv.filter(c => c.error);
    if (failedConv.length) issues.push(...failedConv.map(c => `변환 실패: ${c.error}`));
    else {
      for (const c of conv) {
        if (c.problems.length) issues.push(...c.problems.map(p => `(참고) ${path.basename(c.file)} — ${p}`).slice(0, 5));
        if (c.stale) issues.push(`저장소의 f4/${path.basename(c.file)}가 ${c.stale} — 지금 to-f4의 결과와 다릅니다(--write로 다시 씀)`);
      }
      const f4 = extract(f, 'f4', conv.map(c => c.file));
      if (f4.error) issues.push(`② ${f4.error}`);
      else {
        const d = compare(orig, f4, record ? 100000 : LIMIT);
        const count = `${d.length}${!record && d.length >= LIMIT ? '+' : ''}곳`;
        if (!d.length) { verdict.push('①=②'); if (record) issues.push(`알려진 차이 기록이 낡았습니다 — ①=②가 되었으니 list.json의 ${f.name}@f4에서 known · knownDiffs를 지우세요`); }
        else if (record && d.length === record.knownDiffs) { knownSeen = true; verdict.push(`①≠② ${count}(알려진 차이 — 기록과 같음)`); issues.push(`(참고) 까닭: ${record.known}`, ...d.slice(0, LIMIT).map(x => `(참고) ①≠② ${x}`)); }
        else { verdict.push(`①≠② ${count}${record ? `(기록은 ${record.knownDiffs}곳)` : ''}`); issues.push(...d.slice(0, LIMIT).map(x => `①≠② ${x}`)); }
      }
    }

    // ③ 내장 기본 DLC의 JSON
    if (sources[0].frozen) {
      if (!fs.existsSync(sources[0].frozen)) issues.push(`③ 굳힌 파일이 없습니다: ${sources[0].frozen} — node prototype/scripts/freeze-builtin.mjs ${sources[0].stem} <그 파일>`);
      else {
        const frozen = extract(f, 'file', [sources[0].frozen, ...sources.slice(1).map(() => '')]);
        if (frozen.error) issues.push(`③ ${frozen.error}`);
        else {
          const d = compare(orig, frozen);
          verdict.push(d.length ? `①≠③ ${d.length}${d.length >= LIMIT ? '+' : ''}곳` : '①=③');
          issues.push(...d.map(x => `①≠③ ${x}`));
        }
      }
    }

    const bad = issues.filter(x => !x.startsWith('(참고)'));
    const status = bad.length ? '다름' : knownSeen ? '알려진 차이' : '같음';
    console.log(`${status} ${f.name} — ${verdict.join(' · ') || '(견줌 없음)'}`);
    for (const x of issues) console.log(`    ${x}`);
    if (bad.length) different.push(f.name); else if (knownSeen) known.push(f.name); else same++;
  }
} finally {
  if (args.keep === undefined) fs.rmSync(tmp, { recursive: true, force: true });
  else console.log(`임시 폴더: ${tmp}`);
}

console.log(`f4-same-check(자료 ${total.length} · 같음 ${same}${known.length ? ` · 알려진 차이 ${known.join(', ')}` : ''} · 다름 ${different.length ? different.join(', ') : '없음'})`);
if (different.length) process.exit(1);

// 정답지 뽑기(P3 — 한 벌 체제의 Rust 배치 옮기기): 자료마다 Node가 내는 결과를 시각 · 시간대를 고정해 파일로 굳힌다. 웹 코드 · 내보내기 모듈은 읽기만 한다.
// 사용(작업 폴더에서):
//   node prototype/scripts/layout-oracle.mjs [--only=<자료>,…] [--seams=norm,prep,rows,out,mods[,emul]] [--upto=<모듈>,…]
//     --only    prototype/fixtures/oracle/list.json의 자료 이름(없으면 전부 — 감독의 실자료 등 optional인 것은 파일이 없으면 건너뛰며 알림)
//     --seams   뽑을 이음매(없으면 다섯 모두) — norm: 정규화된 팩 · prep: 줄 배정 전 연표 상태 · rows: 줄 배정 뒤 · out: 모듈 앞자리 k개의 출력 ·
//               mods: 모듈 하나씩(과제 8-틀 — pre-<모듈> · pre-<모듈>.shared · late-<모듈> · upto-<모듈> 스물 — oracle/one.mjs 머리말) ·
//               emul: mods의 자체 점검 하나 더(Node 흉내 — 새 문맥에 앞자리를 심고 모듈 하나만 돌려 같은지 · 기본에 들지 않음 · mods와 함께 · 자료 21개에 약 1분 더)
//     --upto    out의 앞자리 끝 모듈(MODULES 이름 · 쉼표로 여럿 · 없으면 스물 모두 = upto-lens)
//   → prototype/results/oracle/<자료>/norm-<i>.json · prep.json · rows.json · upto-<모듈>.json · pre-<모듈>.json · pre-<모듈>.shared.json · late-<모듈>.json
//     (각 파일 머리 `$oracle`에 시각 · 시간대 · 원본 SHA-256 앞 12자 · 웹 코드 판 `rules`(lay-rules.mjs) · ICU 판 `icu` — Rust `oracle()`이 지금 값과 견줌)
//     자료 폴더는 비우고 새로 쓴다(oracle/one.mjs — 낡은 파일이 남지 않게). Node의 ICU가 calendar-slice.json의 `icu`와 다르면 뽑지 않는다.
// 자료마다 oracle/one.mjs를 **자식 프로세스**로 띄운다 — 환경 TZ=Asia/Seoul · HT_ORACLE_NOW(2026-10-15T12:00:00+09:00)를 정해서.
// 진행 중 정권의 끝 · 문서의 나이 · [date]가 '오늘'과 PC의 시간대에 달려 있어서, 아무 날 · 아무 PC에서 뽑아도 같은 파일이 나와야 한다(Rust의 `Opts.now_ms` · `tz_min`(540)이 같은 값).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { MODULES } from './export/base.mjs';
import { useCalendarCopy } from './oracle/cal-copy.mjs';
import { listFile, missingNote } from './oracle/ktl.mjs';

useCalendarCopy('layout-oracle'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

/** 정답지가 고정하는 '오늘'과 시간대 — Rust의 tests/common/oracle.rs와 같은 값. */
const ORACLE_NOW = '2026-10-15T12:00:00+09:00';
const ORACLE_TZ = 'Asia/Seoul';

const here = path.dirname(fileURLToPath(import.meta.url));
const prototype = path.resolve(here, '..');
const fixDir = path.join(prototype, 'fixtures', 'oracle');
const results = path.join(prototype, 'results', 'oracle');

const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));
const csv = text => (text || '').split(',').map(s => s.trim()).filter(Boolean);
const die = msg => { console.error(`layout-oracle: ${msg}`); process.exit(2); };

const known = new Set(['only', 'seams', 'upto']);
for (const k of Object.keys(args)) if (!known.has(k)) die(`모르는 인자 --${k} (only · seams · upto)`);
for (const s of csv(args.seams)) if (!['norm', 'prep', 'rows', 'out', 'mods', 'emul'].includes(s)) die(`모르는 이음매 ${s} (norm · prep · rows · out · mods · emul)`);
for (const m of csv(args.upto)) if (!MODULES.includes(m)) die(`모르는 모듈 ${m} (${MODULES.join(' · ')})`);

// ICU 판 가드(⑤ Minor · js-vectors.mjs와 같은 것): 보조 달력 날짜 · 내보내기 calendar 모듈의 표는 이 Node의 ICU로 셈하고, Rust 검사는 커밋한 잘린 달력 표
// (engine/tests/fixtures/lay/calendar-slice.json — 뜬 ICU 판이 `icu`에 적힘)로 읽는다. 판이 다르면 정답지가 Rust와 갈릴 수 있어 뽑기 전에 멈춘다
// (그 판의 Node로 돌리거나 · 표가 판 표지 밖 바이트까지 같은지 확인한 뒤 calendar-slice.mjs로 다시 뜰 것 — 판정 R66).
const sliceIcu = JSON.parse(fs.readFileSync(path.join(prototype, 'engine', 'tests', 'fixtures', 'lay', 'calendar-slice.json'), 'utf8')).icu;
if (sliceIcu !== (process.versions.icu || '')) die(`ICU 판이 잘린 달력 표와 다릅니다 — 이 Node ${process.versions.icu || '(없음)'} · calendar-slice.json ${sliceIcu}`);

const list = JSON.parse(fs.readFileSync(path.join(fixDir, 'list.json'), 'utf8'));
const only = csv(args.only);
for (const name of only) if (!list.some(f => f.name === name)) die(`list.json에 없는 자료 ${name} (${list.map(f => f.name).join(' · ')})`);
const chosen = list.filter(f => !only.length || only.includes(f.name));

/** 자료가 쓰는 파일(견본 · 파일 · 더 얹는 DLC). 내장 DLC는 웹 코드 안에 있어 따로 없다. */
const filesOf = f => [f.base.file && path.resolve(fixDir, f.base.file), ...(f.extra || []).map(x => listFile(fixDir, x))].filter(Boolean); // 옛 KTL 자리는 HT_KTL로(oracle/ktl.mjs)

let failed = 0;
for (const f of chosen) {
  const missing = filesOf(f).filter(p => !fs.existsSync(p));
  if (missing.length) {
    // 선택 자료(KTL)는 건너뛴다 — HT_REQUIRE_KTL=1이면 실패(판정 R58 ⑤-5 · oracle/ktl.mjs).
    if (f.optional) { const note = missingNote(f.name, missing); if (!note.fail) { console.log(note.text); continue; } console.error(note.text); failed++; continue; }
    console.error(`실패 ${f.name} — 파일이 없습니다: ${missing.join(' · ')}`);
    failed++;
    continue;
  }
  const childArgs = [path.join(here, 'oracle', 'one.mjs'), `--name=${f.name}`, `--out=${path.join(results, f.name)}`];
  if (args.seams !== undefined) childArgs.push(`--seams=${args.seams}`);
  if (args.upto) childArgs.push(`--upto=${args.upto}`);
  const r = spawnSync(process.execPath, childArgs, { env: { ...process.env, TZ: ORACLE_TZ, HT_ORACLE_NOW: ORACLE_NOW }, stdio: ['ignore', 'pipe', 'inherit'], encoding: 'utf8', maxBuffer: 1 << 26 });
  if (r.status !== 0) { console.error(`실패 ${f.name} — 자식 프로세스가 ${r.status ?? r.signal}로 끝났습니다`); failed++; continue; }
  try {
    const info = JSON.parse(r.stdout.trim().split('\n').pop());
    console.log(`뽑음 ${f.name} — ${info.files.join(' · ')} (${info.ms}ms)`);
  } catch { console.log(`뽑음 ${f.name}`); }
}
if (failed) { console.error(`${failed}개 자료에서 실패했습니다`); process.exit(1); }

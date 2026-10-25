// 바꿔 넣기 도구 — 옛 형식(1 ~ 3) DLC를 컴퓨터에서 **한 번** 형식 4로 바꾼다(설계 2절 #5 · 3-4 끝: 휴대폰은 바꾼 파일만 받아도 되게).
// 웹 코드(js/*.js)는 읽기만 한다: 읽기(HT.normalizePack) → 파일 꼴로(HT.packToJSON) → 올림(HT.F4.up) → 봉함(HT.packFile.build).
//
// 사용(작업 폴더에서):
//   node prototype/scripts/to-f4.mjs <입력 .json | .htpack | builtin:<이름>> <출력 .htpack>
//     입력    .json(옛 꼴 · 형식 4도 읽는 길이 내려 줌) · .htpack(전용 팩 — 형식 4면 읽는 길이 내려 줌) · builtin:<이름>(packs/<이름>/*.js — 내장 DLC)
//     출력    형식 4 DLC(.htpack — 머리 52바이트 + 압축 본문 + 지문, HT.packFile.build 그대로)
//   표준 출력에 올림의 problems(예: "id를 두 항목이 씁니다")와 읽기 오류 · 경고 수를 적는다. 읽을 수 없으면 종료 코드 2.
//
// 시각 · 시간대와 무관해야 한다 — 올린 글에 '오늘'이 들어가면 안 된다. 그래서 환경 변수 HT_ORACLE_NOW(예: 2031-03-04T05:06:07+09:00)가 있으면 그 시각으로 Date를 고정해 돌린다
// (f4-same-check.mjs가 정답지와 다른 시각 · 시간대로 바꿔 보려고 쓴다 — 보통은 비워 둔다).
// 옮겨 앉기의 토막 내기(HT.F4.split — 내보내기 전용)는 끈다: 이 도구는 뜻을 바꾸지 않고 꼴만 바꾼다.
import fs from 'node:fs';
import path from 'node:path';

// 시각 고정은 base.mjs(→ core.js가 싣는 순간 오늘의 해를 셈)를 가져오기 전에.
if (process.env.HT_ORACLE_NOW) (await import('./oracle/clock.mjs')).installClock(process.env.HT_ORACLE_NOW);
const { bootWeb, assert } = await import('./export/base.mjs');
const { loadBuiltin, clone } = await import('./oracle/builtin.mjs');

const die = msg => { console.error(`to-f4: ${msg}`); process.exit(2); };
const positional = process.argv.slice(2).filter(a => !a.startsWith('--'));
if (positional.length !== 2) die('사용: node prototype/scripts/to-f4.mjs <입력 .json | .htpack | builtin:<이름>> <출력 .htpack>');
const [input, output] = positional;
if (!/\.htpack$/i.test(output)) die(`출력은 .htpack이어야 합니다: ${output}`);

const HT = bootWeb();
HT.F4.split = false; // bootWeb은 새 앱 내보내기용으로 켠다 — 바꿔 넣기는 켜지 않는다(형식 4 입력을 내려도 토막 내지 않음)

/** 입력 → 옛 꼴의 raw(+ 읽기 알림). */
async function readInput() {
  if (input.startsWith('builtin:')) {
    const { pack } = loadBuiltin(HT, input.slice('builtin:'.length));
    return { raw: clone(pack), notes: [] };
  }
  if (!fs.existsSync(input)) die(`입력 파일이 없습니다: ${input}`);
  if (/\.htpack$/i.test(input)) {
    const { raw, notes } = await HT.packFile.parse(new Uint8Array(fs.readFileSync(input)));
    return { raw, notes };
  }
  if (/\.json$/i.test(input)) return { raw: JSON.parse(fs.readFileSync(input, 'utf8')), notes: [] };
  return die(`입력은 .json · .htpack · builtin:<이름> 중 하나여야 합니다: ${input}`);
}

let read;
try { read = await readInput(); } catch (e) { die(`입력을 읽지 못했습니다 — ${e && e.message ? e.message : e}`); }
const norm = HT.normalizePack(read.raw);
if (!norm.pack) die(`DLC를 읽을 수 없습니다: ${(norm.errors || []).map(e => e.msg).join(' · ')}`);
const { json, problems } = HT.F4.up(HT.packToJSON(norm.pack));
assert.equal(json.formatVersion, HT.F4.VERSION, '올린 결과가 형식 4가 아닙니다');
const bytes = await HT.packFile.build(json);

fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
fs.writeFileSync(output, bytes);

for (const note of read.notes) console.log(`읽기 알림: ${note}`);
for (const e of norm.errors || []) console.log(`읽기 오류: ${e.msg}`);
for (const p of problems) console.log(`문제: ${p}`);
console.log(`형식 4로 바꿈: ${input} → ${output} (${bytes.length}바이트 · 문제 ${problems.length}건 · 읽기 오류 ${(norm.errors || []).length}건 · 읽기 경고 ${(norm.warnings || []).length}건)`);

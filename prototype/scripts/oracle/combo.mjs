// 아무 조합의 Node 통째 배치를 정답지와 같은 시각 · 시간대로 낸다 — 검사 도구(한 벌 P3 과제 17 `build-check.mjs` · P4 과제 9 `tests/add_pack.rs`의 Node 틈).
// `oracle/one.mjs`(정답지)는 `fixtures/oracle/list.json`의 자료만 뽑는다. 이 도구는 파일로 준 아무 조합(첫째가 기본 DLC, 나머지는 켠 차례)을 같은 길
// (`contextOf` → `runModules` — `export/base.mjs` 그대로 · 웹 코드 · 내보내기 모듈은 읽기만)로 돌려 배치 JSON 3판(계약 4절)을 쓴다.
//
// 쓰는 법(부모가 환경을 정해 띄운다 — 시각은 `HT_ORACLE_NOW`, 시간대는 `TZ` + `HT_ORACLE_TZ_MIN`(분 · 서울 540)):
//   TZ=Asia/Seoul HT_ORACLE_NOW=2026-10-15T12:00:00+09:00 HT_ORACLE_TZ_MIN=540 node prototype/scripts/oracle/combo.mjs --jobs=<일감.json>
//   일감.json = [{"packs":["<기본 .htpack|.json>","<얹는 것>",…],"out":"<배치 .json>"},…] — 일감마다 문맥을 새로 만든다(웹 코드는 한 번만 싣는다).
//   .htpack은 형식 4면 읽는 길이 옛 꼴로 내린다(`HT.packFile.parse` — one.mjs와 같다) · .json은 그대로.
// 끝에 한 줄 JSON `{"jobs":n,"ms":[일감마다 ms]}`.
// 시각 · 시간대를 못 박는 까닭은 one.mjs 머리말과 같다(진행 중 정권의 끝 · 문서의 나이 · [date]가 지역 연 · 월 · 일에 달린다).
import fs from 'node:fs';
import path from 'node:path';

const NOW_TEXT = process.env.HT_ORACLE_NOW || '';
const TZ_MIN = Number(process.env.HT_ORACLE_TZ_MIN ?? '540');
if (!Number.isInteger(TZ_MIN)) throw new Error(`HT_ORACLE_TZ_MIN이 분(정수)이 아닙니다: ${process.env.HT_ORACLE_TZ_MIN}`);
// 지금 날짜의 오프셋으로 본다 — 서울은 1988년 뒤로 늘 +09:00이라 아무 날이든 같다.
const offset = -new Date(Date.parse(NOW_TEXT) || 0).getTimezoneOffset();
if (offset !== TZ_MIN) throw new Error(`시간대가 맞지 않습니다 — TZ=${process.env.TZ} · 오프셋 ${offset}분 · 바란 ${TZ_MIN}분. 부모가 TZ를 정해 띄우세요.`);
const RealDate = globalThis.Date;
// base.mjs(→ core.js가 싣는 순간 new Date().getFullYear()를 셈)를 가져오기 **전에** 시각을 깐다.
(await import('./clock.mjs')).installClock(NOW_TEXT);
const { bootWeb, contextOf, runModules, prototype: protoDir } = await import('../export/base.mjs');

const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));
if (!args.jobs) throw new Error('--jobs=<일감.json>이 필요합니다');
const jobs = JSON.parse(fs.readFileSync(args.jobs, 'utf8'));
if (!Array.isArray(jobs) || !jobs.length) throw new Error('일감이 비었습니다');

const HT = bootWeb();
const has = name => fs.existsSync(path.join(protoDir, 'scripts', 'export', `${name}.mjs`));
const readRaw = async file => {
  const bytes = fs.readFileSync(file);
  return /\.htpack$/i.test(file) ? (await HT.packFile.parse(new Uint8Array(bytes))).raw : JSON.parse(bytes.toString('utf8'));
};
const times = [];
for (const job of jobs) {
  if (!Array.isArray(job.packs) || !job.packs.length || !job.out) throw new Error(`일감의 꼴이 틀렸습니다: ${JSON.stringify(job)}`);
  const t0 = RealDate.now();
  const raws = [];
  for (const file of job.packs) raws.push(await readRaw(file));
  const ctx = contextOf(HT, raws, job.packs.slice(1).map(f => path.basename(f)));
  const out = await runModules(ctx, { has });
  fs.mkdirSync(path.dirname(path.resolve(job.out)), { recursive: true });
  fs.writeFileSync(job.out, JSON.stringify(out));
  times.push(RealDate.now() - t0);
}
console.log(JSON.stringify({ jobs: jobs.length, ms: times }));

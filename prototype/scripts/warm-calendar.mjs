// 보조 달력의 표를 미리 떠 둔다(export/calendar.mjs의 '미리 떠 둔 표' — 전체 표). 시드 · 꾸러미 저장소를 지을 때 build-showcase.mjs가 이것으로 뜬 표를
// 엔진 짓기(`archive-tool build --calendar`)에 넘겨 저장소마다 달력 표를 넣는다(판정 R36 — 앱 안의 엔진이 DLC를 넣고 뺄 때 쓴다 · 꾸러미에는 Node가 없다 —
// 판정 R49). 정답지(Node 내보내기)도 같은 파일을 쓴다. 표는 이 Node의 ICU로 뜬다(ICU 판이 다르면 calendar.mjs가 그 파일을 쓰지 않고 다시 뜬다).
// 사용: node prototype/scripts/warm-calendar.mjs [--years=-3500,2500] [--file=<표 파일>]
import fs from 'node:fs';
import path from 'node:path';
import { bootWeb, prototype } from './export/base.mjs';
import { warmTables, wantedCalendars } from './export/calendar.mjs';

const args = process.argv.slice(2);
const option = (name, fallback) => { const hit = args.find(a => a.startsWith(`--${name}=`)); return hit ? hit.slice(name.length + 3) : fallback; };
const [lo, hi] = option('years', '-3500,2500').split(',').map(Number);
if (!Number.isInteger(lo) || !Number.isInteger(hi) || lo >= hi) { console.error('사용: warm-calendar.mjs [--years=<처음 해>,<끝 해>] [--file=<표 파일>]'); process.exit(2); }
const file = path.resolve(option('file', path.join(prototype, 'results', 'calendar-cache.json')));
const t0 = Date.now();
const HT = bootWeb();
fs.rmSync(file, { force: true });
const body = warmTables(HT, wantedCalendars(HT), lo, hi, file);
if (!fs.existsSync(file)) { console.error(`달력 표를 쓰지 못했습니다: ${file}`); process.exit(1); }
const bad = Object.entries(body.tables).filter(([, t]) => t.bad).map(([id, t]) => `${id}: ${t.bad}`);
// 표가 범위 끝까지 닿지 못하면 실패로 끝낸다(판정 R58 ⑤ Minor — 예전엔 알리기만 해, 그 표를 받은 짓기(build-showcase · build-check)가 모자란 표를
// 저장소에 넣었다: 휴대폰에서 그 바깥 날짜를 쓰는 DLC를 넣고 빼지 못함). 파일은 지워 다음 도구가 모자란 표를 집지 않게 한다.
if (bad.length) {
  fs.rmSync(file, { force: true });
  console.error(`ICU가 끝까지 답하지 못한 달력이 있어 표를 버렸습니다(${lo}~${hi}년 — 범위를 좁히거나 이 Node의 ICU를 보세요): ${bad.join(' / ')}`);
  process.exit(1);
}
console.log(`달력 표를 떠 두었습니다: ${file} · ${lo}~${hi}년 · ICU ${body.icu} · ${Object.keys(body.tables).join(' · ')} · ${((Date.now() - t0) / 1000).toFixed(1)}초`);

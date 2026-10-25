// 견본(기본 = 등불 연대기 samples/sample-lantern.json)을 지금 연표의 정규화기와 줄 배치기(_layoutTrack)에 그대로 통과시켜, 그 결과를 새 저장소가 가져올 JSON 3판으로 내보낸다.
// "넣을 때 한 번"의 시연이다. 웹 코드는 읽기만 하고, 화면(DOM)은 만들지 않는다. 형식: docs/계약-아카이브-3단계.md 4절.
// 내보낼 것은 export/ 아래의 모듈이 나눠 맡는다(모듈 = `export function contribute(ctx, out)`). 있는 모듈만 차례로 부른다.
// 사용: node prototype/scripts/export-layout.mjs   → prototype/results/compat/lantern-layout3.json · sample-lantern.htpack
// 모듈 차례(MODULES) · 모듈 돌리기 · 공통 점검은 export/base.mjs의 runModules 하나(정답지 도구 · 검사도 같은 길).
import fs from 'node:fs';
import path from 'node:path';
import { loadContext, runModules, prototype, sampleFile } from './export/base.mjs';

// 환경 변수: HT_EXPORT_PACK=<packs 아래 폴더>(내장 DLC를 내보냄 — 예: east-asia · 없으면 등불 연대기 견본) · HT_EXPORT_SAMPLE=<samples 아래 이름>(그 견본을 기본 DLC로 — 예: sample-lantern · 형식 3 견본) ·
// HT_EXPORT_EXTRA=<.htpack>;<.htpack>(더 얹는 DLC) · HT_EXPORT_SKIP=모듈,모듈(그 모듈을 건너뜀 — 아직 받는 쪽이 준비되지 않은 모듈을 빼고 내보낼 때) · HT_EXPORT_NAME=파일 이름(기본 <내장 DLC 폴더 · 견본 이름에서 'sample-'을 뗀 것>-layout3.json — 예: lantern-layout3.json · 여럿이 동시에 돌릴 때 서로 덮어쓰지 않게).
// 견본을 내보내면 원본 전용 팩은 results/compat/<견본 이름>.htpack이다(가져오기: archive-tool import-layout <그 .htpack> <배치 JSON> <새 저장소>).
const skip = new Set((process.env.HT_EXPORT_SKIP || '').split(',').filter(Boolean));
const outName = process.env.HT_EXPORT_NAME || `${process.env.HT_EXPORT_PACK || path.basename(sampleFile(), '.json').replace(/^sample-/, '')}-layout3.json`;
const output = path.join(prototype, 'results', 'compat');
fs.mkdirSync(output, { recursive: true });

const ctx = await loadContext();
const out = await runModules(ctx, { skip, has: name => fs.existsSync(path.join(prototype, 'scripts', 'export', `${name}.mjs`)) });
const rowsOf = out.tracks.map(t => t.rows.length);

// 원본 전용 팩도 함께 만들어 둔다(가져오기가 원본을 그대로 보존한다). 기본 DLC 없이(HT_EXPORT_PACK=-) 지을 때는 첫 DLC 파일이 그대로 원본이다.
const pack = path.join(output, process.env.HT_EXPORT_PACK ? `${process.env.HT_EXPORT_PACK}.htpack` : `${path.basename(sampleFile(), '.json')}.htpack`);
if (process.env.HT_EXPORT_PACK !== '-' && !fs.existsSync(pack)) fs.writeFileSync(pack, await ctx.HT.packFile.build(ctx.raw));
fs.writeFileSync(path.join(output, outName), JSON.stringify(out) + '\n');
const sections = {};
for (const it of out.items) sections[it.section] = (sections[it.section] || 0) + 1;
console.log(JSON.stringify({
  트랙: out.tracks.length, 줄: rowsOf.reduce((a, b) => a + b, 0), 분류: out.categories.length, 띠: out.periods.length, 칸: out.cells.length, 날짜칸: out.axis.length,
  사건: out.events.length, 일반항목: sections, 항목기록: out.entities.length, 기록: ctx.notes,
}, null, 1));

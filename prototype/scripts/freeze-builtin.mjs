// 내장 DLC를 JSON 파일로 굳힌다(P3 과제 2) — Rust 엔진에는 packs/<이름>/*.js를 돌릴 길이 없어, 내장 DLC도 파일로 넘겨야 한다.
// 웹 코드(js/*.js · packs/*)는 읽기만 한다: index.html이 싣는 차례 그대로 돌려 모은 HT.getBuiltinPacks()의 그 DLC를 JSON.stringify 그대로 쓴다(끝에 줄 바꿈 하나).
// 함수 · 고리(순환) · symbol · bigint · 일반 객체가 아닌 값(Date · Map · Set …) · NaN/Infinity가 있으면 JSON이 값을 바꾸거나 잃으므로 경로와 함께 멈춘다.
// undefined 값은 JSON에서 열쇠가 빠질 뿐이라 막지 않고 수만 알린다. 굳힌 것이 내장과 같은 배치를 내는지는 f4-same-check.mjs가 본다(③).
//
// 사용(작업 폴더에서):  node prototype/scripts/freeze-builtin.mjs <이름> <출력 .json>
//   예:  node prototype/scripts/freeze-builtin.mjs east-asia prototype/fixtures/oracle/east-asia.json
//   packs/east-asia/*.js를 고친 뒤에는 차례로(판정 R58 ⑤ Minor — 굳힌 파일 하나만 바꾸면 Rust 검사 · 정답지 · 형식 4 사본이 서로 어긋난다):
//     ① 다시 굳힘(위 예) → ② node prototype/scripts/f4-same-check.mjs --write(형식 4 사본 fixtures/oracle/f4/east-asia.htpack · 굳힌 것 = 내장 확인)
//     → ③ node prototype/scripts/calendar-slice.mjs(잘린 달력 표의 해 범위 · 같은 ICU) → ④ node prototype/scripts/layout-oracle.mjs(정답지 — 머리 sources가 바뀜)
//     → ⑤ 엔진 검사(tests/lay_golden.rs가 '입력 바뀜 — 표만 다시'를 찍으면 그 표로 갈음). 시드 · 꾸러미 저장소는 build-showcase.mjs가 내장 팩에서 다시 짓는다.
import fs from 'node:fs';
import path from 'node:path';
import { bootWeb } from './export/base.mjs';
import { loadBuiltin, freeze } from './oracle/builtin.mjs';

const die = msg => { console.error(`freeze-builtin: ${msg}`); process.exit(2); };
const positional = process.argv.slice(2).filter(a => !a.startsWith('--'));
if (positional.length !== 2) die('사용: node prototype/scripts/freeze-builtin.mjs <이름> <출력 .json>');
const [name, output] = positional;
if (!/\.json$/i.test(output)) die(`출력은 .json이어야 합니다: ${output}`);

const HT = bootWeb();
let frozen;
try { frozen = freeze(loadBuiltin(HT, name).pack); } catch (e) { die(e && e.message ? e.message : String(e)); }
fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
fs.writeFileSync(output, `${frozen.text}\n`);
console.log(`굳힘: packs/${name} → ${output} (${Buffer.byteLength(frozen.text) + 1}바이트 · undefined 값 ${frozen.undefinedKeys}개는 열쇠가 빠짐)`);

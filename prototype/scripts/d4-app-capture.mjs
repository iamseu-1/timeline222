// D4 실제 앱 그림 검사. 성능 구간은 돌리지 않으며 기억은 지정한 검사 폴더에서만 읽고 쓴다.
// node prototype/scripts/d4-app-capture.mjs <저장소> <새 결과 폴더> <대본.json> [기억 폴더]
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [db, target, script, memory] = process.argv.slice(2);
if (!db || !target || !script) throw Error('저장소 · 새 결과 폴더 · 대본을 적으세요.');
const root=path.resolve(import.meta.dirname,'../..'), out=path.resolve(target);
if (fs.existsSync(out)) throw Error('기존 결과는 덮어쓰지 않습니다: '+out);
fs.mkdirSync(out,{recursive:true});
const exe=path.join(root,'prototype/app/build/windows/x64/runner/Release/archive_prototype.exe');
const args=[`--db=${path.resolve(db)}`,`--measure=${out}`,'--exit=yes','--offline=yes','--capture-only=yes','--capture-size=1920x1080',`--capture-script=${path.resolve(script)}`];
// 늘 결과 폴더 안을 기억 · 임시 자리로(--memory-dir — 판정 R50: 감독의 %APPDATA% · %TEMP%를 묻지도 않게) · 기억 폴더를 주면 기억은 그 폴더에서만
// 읽고 쓴다(--capture-memory가 앞선다 — 임시 파일 자리는 그대로 --memory-dir 아래).
args.push(`--memory-dir=${path.join(out,'_memory')}`);
if (memory) args.push(`--capture-memory=${path.resolve(memory)}`);
const result=spawnSync(exe,args,{cwd:path.dirname(exe),encoding:'utf8',timeout:180000});
fs.writeFileSync(path.join(out,'실행.log'),(result.stdout||'')+(result.stderr||'')+(result.error?.stack||''));
if(result.error || result.status!==0 || fs.existsSync(path.join(out,'측정-실패.txt'))) throw Error('실제 앱 실행 실패: '+out);
const log=JSON.parse(fs.readFileSync(path.join(out,'검증-기록.json'),'utf8'));
const failures=log.ask_failures.length+log.steps.filter(s=>s.error).length;
console.log(`실제 앱 ${log.steps.length}장 · 실패한 조회 ${log.ask_failures.length}건 · 대본 오류 ${log.steps.filter(s=>s.error).length}건`);
if(failures) process.exitCode=1;

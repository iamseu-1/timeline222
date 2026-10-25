// 현재 정규화기를 읽기 전용으로 사용한다. 외부 JSON 열기를 제품에 다시 노출하지 않는다.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const prototype=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.resolve(prototype,'..'), output=path.join(prototype,'results','compat');
fs.mkdirSync(output,{recursive:true});
const noop=()=>{},el=()=>({style:{},classList:{add:noop,remove:noop,toggle:noop,contains:()=>false},appendChild:noop,remove:noop,setAttribute:noop,addEventListener:noop,querySelector:()=>null,querySelectorAll:()=>[]});
globalThis.window=globalThis;globalThis.document={documentElement:el(),body:el(),createElement:el,querySelector:()=>null,querySelectorAll:()=>[],addEventListener:noop};
globalThis.localStorage={getItem:()=>null,setItem:noop,removeItem:noop};globalThis.matchMedia=()=>({matches:false,addEventListener:noop});globalThis.getComputedStyle=()=>({getPropertyValue:()=>''});
for(const f of ['js/calendar.js','js/core.js','js/packfile.js'])vm.runInThisContext(fs.readFileSync(path.join(root,f),'utf8'),{filename:f});
for(const m of fs.readFileSync(path.join(root,'index.html'),'utf8').matchAll(/<script src="(packs\/[^"]+)"/g))vm.runInThisContext(fs.readFileSync(path.join(root,m[1]),'utf8'),{filename:m[1]});
const raws=[...HT.getBuiltinPacks().map(raw=>({name:raw.id,raw:HT.packToJSON(HT.normalizePack(raw).pack)})),...fs.readdirSync(path.join(root,'samples')).filter(n=>n.endsWith('.json')).map(n=>({name:n.slice(0,-5),raw:JSON.parse(fs.readFileSync(path.join(root,'samples',n),'utf8'))}))];
const report=[];
for(const {name,raw} of raws){
  const bytes=await HT.packFile.build(raw),file=path.join(output,`${name}.htpack`),back=path.join(output,`${name}.read.json`);
  fs.writeFileSync(file,bytes);execFileSync(path.join(prototype,'engine/target/release/archive-tool.exe'),['check-pack',file,back]);
  const read=JSON.parse(fs.readFileSync(back,'utf8'));assert.deepEqual(read,raw);
  const a=HT.normalizePack(raw),b=HT.normalizePack(read);assert.deepEqual(HT.packToJSON(a.pack),HT.packToJSON(b.pack));
  report.push({자료:name,본문일치:true,정규화일치:true,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),문서:Object.keys(raw.documents??{}).length,패치:(raw.patches??[]).length});
}
// 투영 · 거절 검사의 바탕: 따로 세계인 견본 등불 연대기(samples/sample-lantern.json — 지금 남은 견본 하나).
const world=raws.find(x=>x.name==='sample-lantern').raw;
const model=HT.buildModel([HT.normalizePack(world).pack],null);
// 기존 해 좌표를 현재 달력의 양 끝 날짜 사이 정수 분으로 투영한다. 원래 표현은 전용 팩에 그대로 남긴다.
function minute(y){
  if(!Number.isFinite(y))return null;
  const year=Math.floor(y),a=new Date(0),b=new Date(0);
  a.setUTCFullYear(year<0?year+1:year,0,1);a.setUTCHours(0,0,0,0);
  b.setUTCFullYear(year===-1?1:year<0?year+2:year+1,0,1);b.setUTCHours(0,0,0,0);
  return Math.round((a.getTime()+(b-a)*(y-year))/60000);
}
const trackIds=model.tracks.map(t=>t.id);
const projection={name:world.name,events:model.events.map(e=>({uid:e.uid,lane:trackIds.indexOf(e.track),start:minute(e.start),end:minute(e.endY??e.start),title:e.title??e.name,body:e.description??'',original_start:e.start,original_end:e.endY}))};
fs.writeFileSync(path.join(output,'lantern-projection.json'),JSON.stringify(projection)+'\n');
// 유효한 전용 팩의 훼손·잘림·꼬리·확장자 바꾸기도 같은 Rust 읽기에서 거절되어야 한다.
const valid=fs.readFileSync(path.join(output,'sample-lantern.htpack'));let rejected=0;
for(const [name,bytes] of [['cut.htpack',valid.subarray(0,valid.length-1)],['tail.htpack',Buffer.concat([valid,Buffer.from([0])])],['plain.json',valid],['changed.htpack',Buffer.from(valid)]]){
  if(name==='changed.htpack')bytes[bytes.length-3]^=17;
  const bad=path.join(output,name);fs.writeFileSync(bad,bytes);
  assert.throws(()=>execFileSync(path.join(prototype,'engine/target/release/archive-tool.exe'),['check-pack',bad,path.join(output,'should-not-exist.json')],{stdio:'pipe'}));rejected++;
}
fs.writeFileSync(path.join(output,'결과.json'),JSON.stringify({왕복:report,거절:rejected,등불연대기:{원본사건:world.events.length,표시사건:projection.events.length,문서:Object.keys(world.documents??{}).length,한계:'기존 정규화기와 패치 적용 결과의 읽기 투영. 완전한 새 달력·관계·띠 표현 이전은 별도.'}},null,2)+'\n');
console.log(JSON.stringify({왕복:report.length,거절:rejected,등불연대기사건:projection.events.length}));

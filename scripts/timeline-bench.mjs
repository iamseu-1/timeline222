/* 실제 연표 이동·확대 측정. 자료는 시험 창 메모리에만 넣으며 기본팩과 사용자 저장소를 바꾸지 않습니다.
   node scripts/timeline-bench.mjs <검사할 폴더> <결과 폴더> <전|후>
   Playwright가 설치된 package.json 경로는 HT_PLAYWRIGHT_ROOT로 지정할 수 있습니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]||'.'),output=path.resolve(process.argv[3]||'배포/연표-성능'),tag=process.argv[4]||'측정';
const require=createRequire(process.env.HT_PLAYWRIGHT_ROOT||import.meta.url);
const {chromium}=require('playwright');
fs.mkdirSync(output,{recursive:true});
const protectedFiles=[];
for(const dir of ['packs','samples']){
  const walk=base=>{for(const ent of fs.readdirSync(base,{withFileTypes:true})){const file=path.join(base,ent.name);if(ent.isDirectory())walk(file);else protectedFiles.push(path.relative(root,file));}};
  walk(path.join(root,dir));
}
const hashes=()=>Object.fromEntries(protectedFiles.sort().map(name=>[name,createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex')]));
const before=hashes();
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
  const rel=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/+/,'')||'index.html';
  const file=path.resolve(root,rel);
  if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  try{
    let body=fs.readFileSync(file);
    if(rel==='js/viewer.js'){
      const source=body.toString('utf8'),target='/* ---------- 팩 & 모델 ---------- */';
      if(source.split(target).length!==2)throw new Error('측정 창구 위치를 확인할 수 없습니다.');
      body=Buffer.from(source.replace(target,'window.__tl=timeline;window.__state=state;\n'+target));
    }
    res.writeHead(200,{'Content-Type':(mime[path.extname(file)]||'application/octet-stream')+'; charset=utf-8','Cache-Control':'no-store'});res.end(body);
  }catch{res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({channel:process.env.HT_BROWSER||'msedge',headless:true});
const report={기준:execFileSync('git',['rev-parse','--short','HEAD'],{cwd:root,encoding:'utf8'}).trim(),화면:'1920×1080 · 배율 100%',자료지문:before,결과:[],오류:[]};
try{
  for(const count of [1200,6000,24000]){
    const context=await browser.newContext({viewport:{width:1920,height:1080},deviceScaleFactor:1,colorScheme:'light',serviceWorkers:'block',reducedMotion:'reduce'});
    const page=await context.newPage();page.on('pageerror',e=>report.오류.push(e.message));
    await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');
    await page.waitForFunction(()=>window.__tl&&window.HT);
    const modelInfo=await page.evaluate(count=>{
      const names=['가람국','누리국','다온국','라온국','마루국','바다국','새론국','아라국','여울국','온새국','푸른국','하늘국'];
      const leaders=['아린','해든','도담','나린','이솔','가온','라온','새봄'];
      const titles=['공동 회의','새 규약 공표','교역로 개방','도시 정비','연합 협정','항구 확장','행정 구역 개편','문서 편찬','수로 완공','시장 개설','경계 조정','학당 설립','새 관청 설치','통행 규정 개정','연례 회합','협약 갱신'];
      const raw={format:'history-timeline-dlc',formatVersion:3,id:'performance-fictional',name:'가상 자료 · 성능 검사',version:'1.0.0',tracks:[{id:'fictional',name:'가상 대륙',color:'#9cbbba'}],periods:[],events:[]};
      for(let row=0;row<36;row++){
        const name=names[row%12]+(row<12?'':' '+(Math.floor(row/12)+1));
        raw.periods.push({id:'p'+row,track:'fictional',name,start:80,end:1520,people:name,leaders:Array.from({length:10},(_,j)=>({name:leaders[(j+row)%8],start:80+j*140,end:Math.min(1520,220+j*140)}))});
      }
      for(let i=0;i<count;i++){
        const row=i%36,j=Math.floor(i/36),n=Math.floor((count-1-row)/36)+1,cycle=Math.floor(j/10),part=j%10,cycles=Math.ceil(n/10);
        const fraction=part<7?.16+part*.006:.54+(part-7)*.15;
        const year=Math.round(98+(cycle+fraction+(row%4)*.02)*1404/cycles);
        raw.events.push({id:'e'+i,track:'fictional',polity:'p'+row,title:titles[(j*3+row)%titles.length],start:year,importance:part>=7?3:2,category:'politics'});
      }
      const checked=HT.normalizePack(raw);
      if(!checked.pack||checked.errors.length)throw new Error(JSON.stringify(checked.errors));
      const model=HT.buildModel([checked.pack],null),tl=window.__tl;
      window.__state.model=model;
      Object.assign(tl.show,{eras:false,capitals:false,epochs:false,ganji:false});
      tl.setData(model,{enter:false});tl.setView(460,1020);tl.bodyEl.scrollTop=0;
      const methods=['_draw','_foldRows','_drawTrack','_placeRow','_linkPlan','_applyStates','_cells','_keepAnchor'];
      window.__times={};
      for(const key of methods){
        const original=tl[key];
        tl[key]=function(...args){const start=performance.now();try{return original.apply(this,args);}finally{const list=window.__times[key]||(window.__times[key]=[]);list.push(performance.now()-start);}};
      }
      return {나라:model.periods.length,사건:model.events.length};
    },count);
    await page.waitForTimeout(400);
    if(count===6000)await page.screenshot({path:path.join(output,tag+'-1920-1배.png')});
    for(const action of ['이동','확대','선택후이동']){
      const result=await page.evaluate(async action=>{
        const tl=window.__tl;
        tl.setSelected(action==='선택후이동'?tl.tracks[0].events.find(e=>e.start>=600).uid:null);
        tl.view={start:460,end:1020};tl._draw();
        tl.bodyEl.classList.add('is-dragging');
        const intervals=[],states=[];let prior=null;
        window.__times={};
        for(let i=0;i<32;i++){
          await new Promise(requestAnimationFrame);
          const now=performance.now();if(prior!=null)intervals.push(now-prior);prior=now;
          const span=action==='확대'?560*Math.pow(.55,i/31):560;
          const start=action==='확대'?740-span/2:460+i*2;
          tl.view={start,end:start+span};tl._draw();
          if(tl._perfFrame)states.push({...tl._perfFrame});
        }
        tl.bodyEl.classList.remove('is-dragging');tl._draw();
        const summarize=list=>{
          const sorted=list.slice().sort((a,b)=>a-b),at=p=>sorted[Math.min(sorted.length-1,Math.floor(sorted.length*p))]||0;
          return {횟수:list.length,평균ms:+(list.reduce((a,b)=>a+b,0)/Math.max(1,list.length)).toFixed(2),중앙ms:+at(.5).toFixed(2),상위95ms:+at(.95).toFixed(2)};
        };
        const methods=Object.fromEntries(Object.entries(window.__times).map(([key,list])=>[key,summarize(list)]));
        return {손짓:action,그리기:methods._draw,화면간격:summarize(intervals),내역:methods,범위:states,화면요소:tl.root.querySelectorAll('*').length,띠:tl.root.querySelectorAll('.tl-band').length};
      },action);
      report.결과.push({자료:modelInfo,...result});
      console.log(JSON.stringify({자료:count,손짓:action,그리기:result.그리기,화면간격:result.화면간격}));
    }
    await context.close();
  }
  if(JSON.stringify(before)!==JSON.stringify(hashes()))throw new Error('보호 자료가 바뀌었습니다.');
  report.자료보존=true;
  fs.writeFileSync(path.join(output,tag+'-측정.json'),JSON.stringify(report,null,2)+'\n');
  if(report.오류.length)throw new Error(report.오류.join('\n'));
}finally{await browser.close();server.close();}

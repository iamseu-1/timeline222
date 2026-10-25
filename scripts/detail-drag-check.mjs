/* 상세 연표의 드래그 그림·가장자리·다시 배치·입력을 실제 브라우저에서 확인합니다.
   자료는 견본 samples/sample-lantern.json(등불 연대기 — 트랙 7 · 나라 36 · 사건 75, 기원전 1400년 ~ 1698년)만 연표에 올립니다.
   장면: 전체(-1500 ~ 1750) · 밀집 세부(1010 ~ 1080 — 1031년 대격변 둘레에 네 트랙의 나라 · 사건이 몰림) · 아래 구간(400 ~ 1200, 1500px 내려 봄).
   자료와 사용자 저장소는 고치지 않고 독립 브라우저의 메모리에서만 검사합니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const root = path.resolve(process.argv[2]), output = path.resolve(process.argv[3]);
const tag = process.argv[4] || '수정';
const measure = process.argv.includes('--measure');
fs.mkdirSync(output, {recursive:true});
const raw = JSON.parse(fs.readFileSync(path.join(root, 'samples/sample-lantern.json'), 'utf8'));
const {chromium} = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
const mime = {'.html':'text/html','.css':'text/css','.js':'text/javascript','.json':'application/json','.png':'image/png'};
const server = http.createServer((req,res) => {
  try {
    const relative = decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, relative);
    if (!file.startsWith(root + path.sep)) throw Error('범위 밖');
    res.writeHead(200, {'Content-Type':mime[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store'});
    res.end(fs.readFileSync(file));
  } catch {res.writeHead(404);res.end();}
});
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
const browser = await chromium.launch({channel:'msedge',headless:true});
const report = {이름:tag,화면:'1920×1080 · 100%',오류:[],검사:[],측정:[]};
try {
  const page = await browser.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1,serviceWorkers:'block'});
  page.on('pageerror',e => report.오류.push(e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.waitForFunction(() => window.HT?.viewer?.state?.model);
  await page.evaluate(raw => {
    const model = HT.buildModel([HT.normalizePack(raw).pack],null);
    HT.viewer.state.model = model;
    window.tl = HT.viewer.timeline;
    tl.setData(model,{enter:false});
    window.prepare = async scene => {
      tl._stopCoast(); tl._stopGlide(); tl.bodyEl.classList.remove('is-dragging');
      tl.setSelected(null);tl.setHighlight(null);tl.setDensity(scene.density);
      tl.setView(scene.start,scene.end);tl.bodyEl.scrollTop=scene.scroll || 0;
      await new Promise(resolve => setTimeout(resolve,700));
    };
    window.step = (scene, pixels) => {
      const years=pixels*(scene.end-scene.start)/tl.W;
      tl.view={start:scene.start+years,end:scene.end+years};
      tl._draw();
    };
  },raw);
  const scenes = [
    {name:'전체',start:-1500,end:1750,density:0},
    {name:'밀집세부',start:1010,end:1080,density:-1},
    {name:'아래구간',start:400,end:1200,density:0,scroll:1500},
  ];
  for (const scene of scenes) {
    await page.evaluate(s => prepare(s),scene);
    await page.screenshot({path:path.join(output,`${tag}-${scene.name}-정지-1배.png`)});
    const result=await page.evaluate(async ({scene,measure}) => {
      tl.bodyEl.classList.add('is-dragging');
      const intervals=[],costs=[],rebuilds=[];let previous=null,old=null;
      const count=measure?240:22;
      for(let i=0;i<count;i++) {
        await new Promise(requestAnimationFrame);
        const at=performance.now(); if(previous!==null) intervals.push(at-previous);previous=at;
        const pixels=measure?Math.sin(i/60)*130:i*3;
        step(scene,pixels);costs.push(performance.now()-at);
        const current=tl.tracks.find(t=>t._panScene)?._panScene;
        if(current && current!==old)rebuilds.push({프레임:i,처리:costs.at(-1)});
        old=current;
      }
      const stats=a=>{const b=a.slice().sort((a,b)=>a-b);return {평균:a.reduce((s,v)=>s+v,0)/a.length,p95:b[Math.floor(b.length*.95)],최대:b.at(-1),개수:a.length,긴멈춤:a.filter(v=>v>=100).length};};
      return {장면:scene.name,화면간격:stats(intervals),처리:stats(costs),그림준비:rebuilds,재사용:!!old,
        사건:HT.viewer.state.model.events.length,보이는사건:tl.root.querySelectorAll('.tl-ev').length,
        여유그림:tl.tracks.filter(t=>t._panScene).length};
    },{scene,measure});
    report.측정.push(result);console.log(JSON.stringify(result));
    await page.screenshot({path:path.join(output,`${tag}-${scene.name}-이동-1배.png`)});
    if (!measure) {
      assert.ok(result.재사용,'상세 연표 그림 재사용');
      const checks=await page.evaluate(async scene=>{
        const result={};
        const old=tl.tracks.find(t=>t._panScene)._panScene;
        const events=[...tl.root.querySelectorAll('.tl-ev')];
        step(scene,69);
        result.사건요소유지=events.some(el=>el.isConnected);
        result.그림유지=tl.tracks.some(t=>t._panScene===old);
        const chosen=HT.viewer.state.model.events.find(e=>e.start>scene.start&&e.start<scene.end);
        tl.setSelected(chosen.uid);tl._draw();
        result.선택갱신=!tl.tracks.some(t=>t._panScene===old);
        tl.setHighlight(new Set([chosen.uid]));tl._draw();
        result.검색강조=tl.root.classList.contains('is-filtered');
        tl.setHighlight(null);tl.setSelected(null);
        tl.bodyEl.classList.remove('is-dragging');tl._draw();
        result.정착해제=!tl.tracks.some(t=>t._panScene)&&!tl.root.querySelector('.tl-pan-scene,.is-pan-cut');
        tl.zoomAt(.9,tl.W/2);await new Promise(r=>setTimeout(r,450));
        result.확대해제=!tl.root.querySelector('.tl-pan-scene');
        tl.relayout();await new Promise(r=>setTimeout(r,450));
        result.다시배치=!tl.root.querySelector('.tl-pan-scene');
        return result;
      },scene);
      assert.ok(Object.values(checks).every(Boolean),JSON.stringify(checks));
      report.검사.push({장면:scene.name,...checks});
    } else {
      await page.evaluate(()=>{tl.bodyEl.classList.remove('is-dragging');tl._draw();});
      await page.waitForTimeout(400);
    }
    await page.screenshot({path:path.join(output,`${tag}-${scene.name}-종료-1배.png`)});
  }
  assert.equal(report.오류.length,0,JSON.stringify(report.오류));
} finally {
  fs.writeFileSync(path.join(output,`${tag}-드래그검사.json`),JSON.stringify(report,null,2)+'\n');
  await browser.close();await new Promise(resolve=>server.close(resolve));
}

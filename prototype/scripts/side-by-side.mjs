// 두 그림의 같은 자리를 잘라 1배(또는 확대)로 나란히 놓은 그림을 뜬다 — 지금 연표의 기준 그림과 새 그리기를 눈으로 대조할 때.
// 사용: HT_PLAYWRIGHT_ROOT=<…/x.js> node prototype/scripts/side-by-side.mjs --a <기준.png> --b <새.png> --crop x,y,w,h [--zoom 2] [--out 그림.png] [--labels 지금,새]
//   --crop을 여러 번 주면 조각마다 한 줄씩. 조각마다 '차이 점수'(같은 자리 8×8 칸의 평균 밝기 차의 평균, 0~255 — 글꼴 차이로 0이 되지는 않는다. 나아지는지를 보는 숫자)를 적는다.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const all = name => args.flatMap((a, i) => (a === name ? [args[i + 1]] : []));
const one = (name, fallback) => all(name)[0] ?? fallback;
const a = path.resolve(one('--a')), b = path.resolve(one('--b'));
const crops = all('--crop').map(c => c.split(',').map(Number));
const zoom = Number(one('--zoom', '1'));
const out = path.resolve(one('--out', 'side-by-side.png'));
const labels = one('--labels', '지금 연표,새 그리기').split(',');
if (!crops.length) crops.push([0, 0, 1920, 1080]);
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
const html = `<!doctype html><meta charset="utf-8"><style>
body{margin:12px;background:#fcf9f3;color:#2e2820;font:12px/1.5 "Malgun Gothic",sans-serif}
.row{display:flex;gap:10px;margin-bottom:14px;align-items:flex-start}.cell p{margin:0 0 3px;font-weight:700;color:#8a5a2b}
canvas{display:block;border:1px solid rgba(90,60,20,.3);image-rendering:pixelated}
</style><div id="rows"></div><script>
const crops=${JSON.stringify(crops)},zoom=${zoom},labels=${JSON.stringify(labels)};
const load=src=>new Promise((ok,no)=>{const i=new Image();i.onload=()=>ok(i);i.onerror=no;i.src=src;});
(async()=>{const imgs=[await load(${JSON.stringify(pathToFileURL(a).href)}),await load(${JSON.stringify(pathToFileURL(b).href)})];
const scores=[];
for(const [x,y,w,h] of crops){const row=document.createElement('div');row.className='row';const datas=[];
 imgs.forEach((img,k)=>{const cell=document.createElement('div');cell.className='cell';const p=document.createElement('p');p.textContent=labels[k]+' ['+[x,y,w,h].join(', ')+']';
  const c=document.createElement('canvas');c.width=w*zoom;c.height=h*zoom;const g=c.getContext('2d');g.imageSmoothingEnabled=false;g.drawImage(img,x,y,w,h,0,0,w*zoom,h*zoom);
  const t=document.createElement('canvas');t.width=w;t.height=h;const tg=t.getContext('2d');tg.drawImage(img,x,y,w,h,0,0,w,h);datas.push(tg.getImageData(0,0,w,h).data);
  cell.append(p,c);row.append(cell);});
 let sum=0,n=0;for(let by=0;by<h;by+=8)for(let bx=0;bx<w;bx+=8){let s0=0,s1=0,m=0;for(let yy=by;yy<Math.min(h,by+8);yy++)for(let xx=bx;xx<Math.min(w,bx+8);xx++){const i=(yy*w+xx)*4;s0+=datas[0][i]*.3+datas[0][i+1]*.59+datas[0][i+2]*.11;s1+=datas[1][i]*.3+datas[1][i+1]*.59+datas[1][i+2]*.11;m++;}sum+=Math.abs(s0-s1)/m;n++;}
 const score=(sum/n).toFixed(2);scores.push(score);const note=document.createElement('div');note.className='cell';note.innerHTML='<p>차이 점수</p>'+score;row.append(note);
 document.getElementById('rows').append(row);}
window.__scores=scores;window.__done=true;})();
</script>`;
const page_ = path.join(path.dirname(out), `_${path.basename(out, '.png')}.html`);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(page_, html);
const browser = await chromium.launch({ channel: 'msedge', headless: true, args: ['--allow-file-access-from-files'] });
try {
  const page = await (await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 })).newPage();
  await page.goto(pathToFileURL(page_).href);
  await page.waitForFunction(() => window.__done, null, { timeout: 30000 });
  await page.screenshot({ path: out, fullPage: true });
  console.log('차이 점수: ' + (await page.evaluate(() => window.__scores)).join(' · ') + '\n저장: ' + out);
} finally {
  await browser.close();
  fs.rmSync(page_, { force: true });
}

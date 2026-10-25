// 비교 그림(3단계): 견본 등불 연대기(samples/sample-lantern.json)의 같은 장면들을 지금 연표(브라우저 · 1920×1080 · 100%)와 새 앱(실행본의 --capture-only · 같은 1920×1080)으로 1배로 찍어
// 같은 좌표로 나란히 놓는다 — 화면 전체(위아래로)와 묶음별 조각(옆으로 · 차이 점수와 함께). 실제 역사 이름이 없는 등불 연대기만 쓴다.
// 웹 연표의 코드 · 견본은 읽기만 한다(내보내는 길에 연표 객체를 창에 걸어 둘 뿐, 파일은 고치지 않는다).
// 사용: HT_PLAYWRIGHT_ROOT=<playwright가 있는 곳의 아무 .js> node prototype/scripts/compare-shots.mjs [--out prototype/results/compare3/<이름>] [--db prototype/data/lantern/archive.db]
//       저장소 짓기: node prototype/scripts/warm-calendar.mjs --file=<표>  →  engine/target/release/archive-tool.exe build data/lantern/archive.db ../samples/sample-lantern.json --calendar=<표>(시드와 같은 Rust 짓기 — 옛 export-layout → import-layout 길은 달력 표 없는 저장소를 지어 DLC를 넣고 빼지 못한다)
//       실행본은 scripts/dev.ps1 app-build로 만든 것. 재는 동안 새 앱의 창이 잠깐 뜬다(가리지 말 것).
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(prototype, '..');
const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 13);
const out = path.resolve(option('--out', path.join(prototype, 'results', 'compare3', stamp)));
const db = path.resolve(option('--db', path.join(prototype, 'data', 'lantern', 'archive.db')));
if (!fs.existsSync(db)) { console.error('등불 연대기 저장소가 없습니다: ' + db); process.exit(1); }
if (fs.existsSync(path.join(out, '화면-비교.html'))) { console.error('기존 비교 결과를 덮어쓰지 않습니다: ' + out); process.exit(1); }
fs.mkdirSync(out, { recursive: true });

/** 지금 연표의 해 좌표 → 1970년 기준 분. 내보내기(scripts/export/base.mjs)와 같은 투영이라 두 화면의 같은 해가 같은 자리에 온다. */
function minute(y) {
  const year = Math.floor(y), a = new Date(0), b = new Date(0);
  a.setUTCFullYear(year < 0 ? year + 1 : year, 0, 1); a.setUTCHours(0, 0, 0, 0);
  b.setUTCFullYear(year === -1 ? 1 : year < 0 ? year + 2 : year + 1, 0, 1); b.setUTCHours(0, 0, 0, 0);
  return Math.round((a.getTime() + (b - a) * (y - year)) / 60000);
}
// 조각: [이름, x, y, 폭, 높이] — 1920×1080 화면의 좌표(두 화면이 같은 좌표를 쓴다).
const scenes = [
  { name: '전체', start: -700, end: 1750, note: '등불 연대기 전체(안개 시대 ~ 헌정 시대)', crops: [['날짜 칸', 0, 60, 960, 412], ['띠와 관계선', 240, 470, 960, 600], ['왼쪽 칸', 0, 469, 260, 611]] },
  { name: '밀집-세부', start: 900, end: 1065, note: '사건이 몰린 165년(1031년 대격변)', crops: [['띠의 위쪽(탭 · 왕조 · 시기 · 지위 · 지도자 · 내각)', 240, 470, 960, 150], ['사건 글줄', 240, 612, 960, 180], ['기간 · 인물 막대', 240, 770, 960, 70], ['속국 이름표 · 기관 칸', 240, 880, 960, 190], ['왼쪽 칸', 0, 469, 260, 611]] },
  { name: '한-나라의-100년', start: 300, end: 400, note: '등불 왕국의 100년', crops: [['앱 틀과 날짜 칸', 0, 0, 960, 472], ['띠와 사건', 240, 470, 960, 460], ['왼쪽 칸', 0, 469, 260, 611]] },
];

// ---- 1) 지금 연표 ----
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
const fixture = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let data = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      const marker = '/* ---------- 팩 & 모델 ---------- */', text = data.toString('utf8');
      assert.equal(text.split(marker).length, 2, 'viewer.js에서 연표 객체를 걸 자리를 찾지 못했습니다');
      data = Buffer.from(text.replace(marker, 'window.__tl=timeline;window.__state=state;\n' + marker));
    }
    res.writeHead(200, { 'Content-Type': (mime[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(data);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: 'msedge', headless: true, args: ['--allow-file-access-from-files'] });
const errors = [];
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('http://127.0.0.1:' + server.address().port);
  await page.waitForFunction(() => window.__state?.model);
  await page.evaluate(raw => {
    const model = HT.buildModel([HT.normalizePack(raw).pack], null);
    __state.model = model;
    __tl.setData(model, { enter: false });
  }, fixture);
  for (const scene of scenes) {
    await page.evaluate(s => { __tl.setDensity(0); __tl.relayout(); __tl.setView(s.start, s.end); __tl.bodyEl.scrollTop = 0; }, scene);
    await page.waitForTimeout(900);
    await page.screenshot({ path: path.join(out, `${scene.name}-지금.png`) });
  }

  // ---- 2) 새 앱 ----
  for (const scene of scenes) {
    const folder = path.join(out, `_capture-${scene.name}`);
    fs.rmSync(folder, { recursive: true, force: true });
    const run = spawnSync(process.execPath, [path.join(prototype, 'scripts', 'measure.mjs'), '--db', db, '--out', folder, '--from', String(minute(scene.start)), '--to', String(minute(scene.end)),
      '--capture-only', '--capture-size', '1920x1080'], { encoding: 'utf8' });
    if (run.status !== 0) throw new Error('새 앱의 그림을 뜨지 못했습니다: ' + (run.stderr || run.stdout));
    fs.copyFileSync(path.join(folder, '화면-1배.png'), path.join(out, `${scene.name}-새.png`));
    fs.rmSync(folder, { recursive: true, force: true });
  }

  // ---- 3) 나란히 ----
  const html = `<!doctype html><html lang="ko"><meta charset="utf-8"><title>화면 비교 — 지금 연표와 새 앱(3단계)</title>
<style>
  body{margin:24px;background:#fcf9f3;color:#2e2820;font:14px/1.6 "Malgun Gothic",sans-serif;width:1940px}
  h1{font-size:20px;margin:0 0 4px} h2{font-size:17px;margin:34px 0 6px} h3{font-size:14px;margin:18px 0 4px} p{margin:0 0 8px;color:#655b4d}
  .pair{display:flex;gap:12px;align-items:flex-start} .label{font-weight:700;margin:0 0 3px;font-size:12px;color:#8a5a2b}
  canvas,img.full{display:block;border:1px solid rgba(90,60,20,.25);max-width:none} .score{font-size:12px;color:#655b4d}
</style>
<h1>화면 비교 — 지금 연표와 새 앱(3단계)</h1>
<p>등불 연대기 견본 · 1920×1080 · 100% · 화면 그대로 1배(늘이거나 줄이지 않음). 두 화면은 같은 창 크기 · 같은 기간 · 같은 세로 자리라 같은 것이 같은 좌표에 온다. 조각마다의 차이 점수는 같은 자리 8×8 칸의 평균 밝기 차의 평균(0~255)이다 — 글꼴을 그리는 방식이 달라 0이 되지는 않으며, 합격선이 아니라 나아지는지를 보는 숫자다.</p>
<div id="body"></div>
<script>
const scenes=${JSON.stringify(scenes)};
const load=src=>new Promise((ok,no)=>{const i=new Image();i.onload=()=>ok(i);i.onerror=no;i.src=src;});
(async()=>{const body=document.getElementById('body');const scores={};
for(const s of scenes){const a=await load(encodeURI(s.name+'-지금.png')),b=await load(encodeURI(s.name+'-새.png'));
 const h2=document.createElement('h2');h2.textContent=s.note+' — '+s.start+'년 ~ '+s.end+'년';body.append(h2);
 for(const [name,x,y,w,h] of s.crops){const h3=document.createElement('h3');body.append(h3);const row=document.createElement('div');row.className='pair';const datas=[];
  [a,b].forEach((img,k)=>{const cell=document.createElement('div');const p=document.createElement('p');p.className='label';p.textContent=k?'새 앱':'지금 연표';
   const c=document.createElement('canvas');c.width=w;c.height=h;const g=c.getContext('2d');g.drawImage(img,x,y,w,h,0,0,w,h);datas.push(g.getImageData(0,0,w,h).data);cell.append(p,c);row.append(cell);});
  let sum=0,n=0;for(let by=0;by<h;by+=8)for(let bx=0;bx<w;bx+=8){let s0=0,s1=0,m=0;for(let yy=by;yy<Math.min(h,by+8);yy++)for(let xx=bx;xx<Math.min(w,bx+8);xx++){const i=(yy*w+xx)*4;s0+=datas[0][i]*.3+datas[0][i+1]*.59+datas[0][i+2]*.11;s1+=datas[1][i]*.3+datas[1][i+1]*.59+datas[1][i+2]*.11;m++;}sum+=Math.abs(s0-s1)/m;n++;}
  const score=(sum/n).toFixed(2);(scores[s.name] ||= {})[name]=Number(score);h3.textContent=name+' ['+[x,y,w,h].join(', ')+'] · 차이 점수 '+score;body.append(row);}
 const h3=document.createElement('h3');h3.textContent='화면 전체 — 위: 지금 연표 · 아래: 새 앱';body.append(h3);
 for(const img of [a,b]){img.className='full';body.append(img);}}
window.__scores=scores;window.__done=true;})();
</script></html>
`;
  fs.writeFileSync(path.join(out, '화면-비교.html'), html);
  const sheet = await context.newPage();
  await sheet.setViewportSize({ width: 1990, height: 1200 });
  await sheet.goto(pathToFileURL(path.join(out, '화면-비교.html')).href);
  await sheet.waitForFunction(() => window.__done, null, { timeout: 60000 });
  const scores = await sheet.evaluate(() => window.__scores);
  fs.writeFileSync(path.join(out, '차이-점수.json'), JSON.stringify(scores, null, 1) + '\n');
  await sheet.screenshot({ path: path.join(out, '화면-비교.png'), fullPage: true });
  console.log(JSON.stringify(scores, null, 1));
} finally {
  await browser.close();
  server.close();
}
if (errors.length) console.error('지금 연표의 쪽에서 난 오류:', errors);
console.log('저장: ' + path.join(out, '화면-비교.html'));

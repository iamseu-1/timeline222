/* 메이커 미리보기 연표를 실제 브라우저로 찍습니다(1920×1080 · 100% — 감독 화면 1배).
   node scripts/maker-shoot.mjs <검사할 폴더> <결과 폴더> [--tag=이름] [--draft=samples/sample-lantern.json] [--from=<해> --to=<해>] [--fold-spheres=none|default] [--click=<CSS 선택자>,…]
     [--shelve=<그릇 uid>,…] [--scope-states=<그릇 uid>:<open|shelf|closed|loose>,…]
   --click: 찍기 전에 차례로 누를 것(쉼표로 여럿 — 표 탭 · 폼 열기 등 · 하나마다 0.5초 기다림). 리메이크 5단계 과제 0 — 형식 4 작업본(--draft=prototype/fixtures/f4/<파일>)의 폼 · 표 · 미리보기를 찍을 때.
   크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT(그 package.json)로 — 다른 브라우저 검사와 같게.
   작업본(기본: 등불 연대기 견본)을 독립 브라우저의 저장소에만 넣고 메이커를 띄워, 미리보기 연표를 지정한 해 범위로 맞춘 뒤 화면 전체와 연표 부분을 찍습니다.
   감독 자료(%APPDATA% · 브라우저 저장소)는 건드리지 않습니다.
   형식 4 파일(formatVersion 4)은 메이커가 파일을 열 때처럼(HT.packFile.read → HT.F4.down · HT.F4.extrasOf) 옛 꼴 작업본으로 내려 넣습니다 — 작업본 저장소는 옛 꼴만 읽어
   그대로 넣으면 객체가 하나도 그려지지 않음(4단계 배치 갈래 걸음 3에서 고침). */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const m = a.match(/^--([^=]+)=?(.*)$/); return [m[1], m[2] === '' ? true : m[2]]; }));
const plain = process.argv.slice(2).filter(a => !a.startsWith('--'));
const root = path.resolve(plain[0] || '.'), output = path.resolve(plain[1] || '배포/메이커-찍기');
const tag = args.tag || '미리보기';
const draftFile = path.resolve(root, args.draft || 'samples/sample-lantern.json');
/* --fold-spheres=none: 서고 미리보기의 문화권을 모두 펼친 채 띄움(미리보기 연표의 기억 ht.ui의 foldedSpheres = 빈 목록 — viewer.js가 읽는 자리) ·
   default(또는 주지 않음): 처음 접힘 규칙 그대로(기본 문화권 하나만 폄). 리메이크 4단계 과제 1 — 머리말에만 있던 손잡이를 채움 */
const fold = args['fold-spheres'] === true ? '' : String(args['fold-spheres'] || 'default');
if (!['none', 'default'].includes(fold)) { console.error(`--fold-spheres는 none 또는 default (받은 값: ${fold})`); process.exit(2); }
/* --shelve=<그릇 uid,…>: 그 그릇을 켠 채 선반 상태로 띄움 — 미리보기 기억 ht.ui의 shelvedScopes(선반 기억)와 scopes[uid] = true(켬)를
   --fold-spheres가 넣는 자리에 함께 넣는다(js/viewer.js가 연표를 만들 때 읽음 — shelvedScopes · scopesOn). 리메이크 4단계 과제 7 걸음 6 — 앱과 1배 나란히.
   --scope-states=<그릇 uid>:<open|shelf|closed|loose>,…: 넓힌 꼴(펼침 · 선반 = 기억에 켬(선반은 선반 기억에도) · 풂 = 기억에 끔 ·
   접음 = 켠 채 띄운 뒤 연표의 setScopeState(uid, 'closed') — 가지 접힘 열쇠에 트랙 id가 들어 띄운 뒤에 앎 · 오른쪽 클릭 '접음'과 같은 길).
   uid는 미리보기의 것(`<작업본 id>/<그릇 id>`). 찍기 전에 연표의 scopeStateOf로 모두 그 상태인지 보고, 아니면 정보에 적고 끝 코드 1. */
const SCOPE_WORDS = ['open', 'shelf', 'closed', 'loose'];
const scopeStates = [
  ...String(args.shelve === true ? '' : args.shelve || '').split(',').map(s => s.trim()).filter(Boolean).map(uid => [uid, 'shelf']),
  ...String(args['scope-states'] === true ? '' : args['scope-states'] || '').split(',').map(s => s.trim()).filter(Boolean).map(s => { const i = s.lastIndexOf(':'); return [s.slice(0, i), s.slice(i + 1)]; }),
];
for (const [uid, st] of scopeStates) if (!uid || !SCOPE_WORDS.includes(st)) { console.error(`--scope-states는 <그릇 uid>:<${SCOPE_WORDS.join('|')}> (받은 값: ${uid}:${st})`); process.exit(2); }
const view = fold === 'none' || scopeStates.length ? {} : null;
if (fold === 'none') view.foldedSpheres = [];
if (scopeStates.length) {
  view.shelvedScopes = scopeStates.filter(([, st]) => st === 'shelf').map(([uid]) => uid);
  view.scopes = Object.fromEntries(scopeStates.map(([uid, st]) => [uid, st !== 'loose']));
}
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json', '.woff2': 'font/woff2' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    const bytes = fs.readFileSync(file);
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, locale: 'ko-KR' });
let draft = JSON.parse(fs.readFileSync(draftFile, 'utf8'));
if (Number(draft.formatVersion) === 4) {
  const prep = await browser.newContext();
  const pg = await prep.newPage();
  await pg.goto(base + 'dlc-maker.html');
  await pg.waitForFunction(() => window.HT && HT.F4 && HT.F4.down);
  draft = await pg.evaluate(raw4 => {
    const notes = [];
    const d = HT.F4.down(raw4, m => notes.push(m));
    d.f4extras = HT.F4.extrasOf(raw4);
    if (notes.length) d.f4notes = notes;
    return d;
  }, draft);
  await prep.close();
}
const ui = {};
await context.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d.draft)); localStorage.setItem('ht.maker.ui', JSON.stringify(d.ui)); if (d.view) localStorage.setItem('ht.ui', JSON.stringify(d.view)); }, { draft, ui, view });
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
try {
  await page.goto(base + 'dlc-maker.html');
  await page.locator('#timeline .tl-track').first().waitFor({ timeout: 30000 });
  await page.waitForTimeout(1200);
  if (args.from && args.to) {
    await page.evaluate(([a, b]) => { const tl = HT.liveTimeline; if (tl) tl.setView(Number(a), Number(b)); }, [args.from, args.to]);
    await page.waitForTimeout(900);
  }
  const closing = scopeStates.filter(([, st]) => st === 'closed').map(([uid]) => uid);
  if (closing.length) {
    await page.evaluate(list => { const tl = HT.liveTimeline; for (const uid of list) if (tl) tl.setScopeState(uid, 'closed'); }, closing);
    await page.waitForTimeout(1200); // 접는 움직임이 가라앉을 때까지
  }
  if (args.click) {
    for (const sel of String(args.click).split(',').map(s => s.trim()).filter(Boolean)) {
      await page.locator(sel).first().click({ timeout: 10000 });
      await page.waitForTimeout(500);
    }
  }
  const info = await page.evaluate(() => {
    const tl = HT.liveTimeline || null;
    const tracks = [...document.querySelectorAll('#timeline .tl-track')].map(t => ({ id: t.dataset.track, h: t.getBoundingClientRect().height, folded: t.classList.contains('is-folded') }));
    const spheres = [...document.querySelectorAll('#timeline .tl-sphere')].map(t => ({ id: t.dataset.sphere, h: t.getBoundingClientRect().height, folded: t.classList.contains('is-folded') }));
    return { view: tl && tl.view, tracks, spheres, gutter: tl && tl.gutter };
  });
  if (scopeStates.length) {
    // 그릇 상태가 정말 그리 되었는가(미리보기 연표의 scopeStateOf — 펼침 open · 선반 shelf · 접음 closed · 풂 loose · 없는 uid는 null)
    info.scopeStates = await page.evaluate(list => list.map(([uid, want]) => ({ uid, want, got: HT.liveTimeline ? HT.liveTimeline.scopeStateOf(uid) : null })), scopeStates);
    // 선반 줄(.tl-shelf — 폴더 발의 작은 꼬리표 줄)의 화면 자리와 꼬리표 글 · '+n'(화면 밖으로 내려가 찍히지 않아도 앱과 견줄 수 있게)
    info.shelves = await page.evaluate(() => [...document.querySelectorAll('#timeline .tl-shelf')].map(el => {
      const r = el.getBoundingClientRect();
      return { top: Math.round(r.top), left: Math.round(r.left), width: Math.round(r.width), tags: [...el.querySelectorAll('.tl-stag')].map(t => ({ text: t.textContent.trim(), left: Math.round(t.getBoundingClientRect().left) })) };
    }));
    for (const x of info.scopeStates) if (x.got !== x.want) errors.push(`그릇 상태가 되지 않음: ${x.uid} 바람 ${x.want} · 지금 ${x.got}`);
  }
  await page.screenshot({ path: path.join(output, `${tag}-화면.png`) });
  const tlBox = await page.locator('#timeline').boundingBox();
  if (tlBox) await page.screenshot({ path: path.join(output, `${tag}-연표.png`), clip: tlBox });
  fs.writeFileSync(path.join(output, `${tag}-정보.json`), JSON.stringify({ info, errors }, null, 2));
  console.log(`찍음: ${output} · ${tag} · 트랙 ${info.tracks.length} · 문화권 단 ${info.spheres.length} · 오류 ${errors.length}`);
  if (errors.length) console.log(errors.join('\n'));
  if (info.scopeStates) {
    const miss = info.scopeStates.filter(x => x.got !== x.want);
    console.log(`그릇 상태 ${miss.length ? `실패 ${miss.length}` : `확인 ${info.scopeStates.length}`}(${info.scopeStates.map(x => `${x.uid} ${x.got}`).join(' · ')})`);
    if (miss.length) process.exitCode = 1;
  }
} finally {
  await browser.close();
  server.close();
}

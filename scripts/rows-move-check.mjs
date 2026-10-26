/* 메이커 연표의 줄 위아래 옮기기(0.1.1 · 감독 2026-10-26 "민족이랑 트랙 같으면 세로 중심으로 자유롭게 이동" · 끌면 남북 값을 고침 — js/maker-drag.js rowSite · rowMove)를
   실제 브라우저 · 실제 포인터(Alt+끌기)와 키(Alt+↑/↓)로 검사합니다.
   node scripts/rows-move-check.mjs <검사할 폴더> <결과 폴더>
   ㉮ 견본(samples/sample-lantern.json — 가상 자료)을 작업본으로: 하연 트랙의 하연인 묶음(배열 기준 '시작 연도')에서 갈대 공국 줄을 맨 위로 끌면
      하연인의 배열 기준이 '북 → 남' · 줄 머리 나라의 남북 위치가 차례대로 · 끈 줄만 옮겨지고 다른 줄과 위 민족(대륙인) 안 묶음 차례는 그대로 · 가로(날짜)는 그대로 ·
      다른 트랙 자리 위에서는 놓을 수 없음(까닭 글 · 놓아도 작업본 그대로) · 되돌리기 한 번에 처음으로 · 형식 4 파일로 내렸다 다시 읽어도 값이 남음
   ㉯ 견본을 불러온 팩(자물쇠 풂)으로, 작업본은 가상의 작은 DLC: 북 → 남인 청림인 묶음의 줄은 덮어쓰기(set.northSouth)만 · 불러온 팩이 '시작 연도'로 정한 하연인은 막고 알림 ·
      기준을 적지 않은 남의 민족은 내 DLC에 같은 id 민족 줄(배열 기준만)
   그림(1920×1080 · 배율 1)은 결과 폴더에. Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT에 그 package.json을, 브라우저는 HT_BROWSER(기본 msedge)로 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/줄-위아래');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    let bytes = fs.readFileSync(file);
    if (rel === 'js/viewer.js') {
      let text = bytes.toString('utf8');
      const models = '/* ---------- 팩 & 모델 ---------- */';
      const started = 'if (maker) maker.start();';
      for (const marker of [models, started]) assert.equal(text.split(marker).length, 2, `viewer.js의 표시 줄 «${marker}»이 하나가 아님`);
      text = text.replace(models, 'window.__tl=timeline;window.__state=state;\n' + models).replace(started, started + ' window.__maker = maker;');
      bytes = Buffer.from(text);
    }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = 'http://127.0.0.1:' + server.address().port;
const sample = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const P = `${sample.id}/`;
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100% · 배율 1', 검사: [], 오류: [] };
const check = (ok, text, details) => {
  report.검사.push({ 검사: text, 결과: ok ? (details === undefined ? true : details) : { 실패: details } });
  assert.ok(ok, text + (details !== undefined ? '\n' + JSON.stringify(details) : ''));
};
const newPage = async (seed, tag) => {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, serviceWorkers: 'block', reducedMotion: 'reduce' });
  await context.addInitScript(seed => {
    if (sessionStorage.getItem('rows-check-seeded')) return;
    sessionStorage.setItem('rows-check-seeded', '1');
    localStorage.clear();
    for (const [k, v] of Object.entries(seed)) localStorage.setItem(k, JSON.stringify(v));
  }, seed);
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(`${tag}: ${e.message}`));
  page.on('console', m => m.type() === 'error' && report.오류.push(`${tag}: ${m.text()}`));
  await page.goto(`${base}/dlc-maker.html`);
  await page.waitForFunction(() => window.__tl && window.__state && window.__state.model && window.__maker && document.querySelector('#mkStart').hidden);
  await page.waitForTimeout(1200);
  return page;
};
/* 페이지 안 도우미: 트랙의 줄(머리 → … 이름) · 민족 묶음의 줄 · 나라 uid의 남북 값 · 띠 상자 */
const rows = (page, track) => page.evaluate(t => { const tr = __tl.tracks.find(x => x.id === t); return tr.rowPeriods.map(r => r.map(p => p.name).join('→')); }, track);
const groupRows = (page, track, key) => page.evaluate(([t, k]) => { const tr = __tl.tracks.find(x => x.id === t), g = tr.groups.find(x => !x.scope && x.key === k); return tr.rowPeriods.slice(g.first, g.first + g.count).map(r => r.map(p => p.name).join('→')); }, [track, key]);
const box = (page, sel) => page.evaluate(s => { const n = document.querySelector(s); if (!n) return null; const b = n.getBoundingClientRect(); return { x: b.left, y: b.top, w: b.width, h: b.height }; }, sel);
const laneBox = (page, track, r) => box(page, `.tl-track[data-track="${track}"] .tl-lane[data-row="${r}"]`);
const draftText = page => page.evaluate(() => JSON.stringify(__maker.draft));
/** 트랙이 화면 가운데 오게 보기를 맞추고 고를 띠를 누름 */
async function focus(page, track, uid, view) {
  const sphere = await page.evaluate(t => { const tr = __tl.tracks.find(x => x.id === t); return tr && tr._sphereHidden && tr._sphere ? tr._sphere.id : ''; }, track); // 서고: 접힌 문화권은 펼침
  if (sphere) { await page.evaluate(id => __tl.toggleFoldSphere(id, false), sphere); await page.waitForTimeout(700); }
  const fold = await page.$(`.tl-track[data-track="${track}"].is-folded .tl-fold`); // 불러온 팩의 트랙은 접혀 열릴 수 있음
  if (fold) { await fold.click(); await page.waitForTimeout(700); }
  await page.evaluate(([t, v]) => { __tl.setView(v[0], v[1]); const el = document.querySelector(`.tl-track[data-track="${t}"]`); __tl.bodyEl.scrollTop += el.getBoundingClientRect().top - __tl.bodyEl.getBoundingClientRect().top - 40; }, [track, view]);
  await page.waitForTimeout(700);
  const b = await box(page, `#timeline .tl-band[data-uid="${uid}"]`);
  await page.mouse.click(b.x + Math.min(40, b.w / 2), b.y + b.h / 2);
  await page.waitForTimeout(500);
  await page.evaluate(() => document.activeElement && document.activeElement.blur()); // 누르면 편집 창 이름 칸에 글쇠가 감 — 연표의 Alt+↑/↓를 보려고 놓음
}
/** Alt+끌기: 띠 가운데에서 세로로 먼저 8px(세로 끌기로 가름) → 목표 y까지. shot이면 놓기 전에 찍음 */
async function altDrag(page, uid, toY, shot) {
  const b = await box(page, `#timeline .tl-band[data-uid="${uid}"]`);
  const x = b.x + Math.min(40, b.w / 2), y = b.y + b.h / 2;
  await page.keyboard.down('Alt');
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x, y + (toY < y ? -8 : 8));
  await page.mouse.move(x + 3, toY, { steps: 8 });
  await page.waitForTimeout(150);
  const live = await page.evaluate(() => ({ tip: document.querySelector('.mk-drag-date.is-row')?.textContent || '', no: !!document.querySelector('.mk-drag-date.is-no'), line: !!document.querySelector('.mk-drag-row-line:not([hidden])') }));
  if (shot) await page.screenshot({ path: path.join(output, shot) });
  await page.mouse.up();
  await page.keyboard.up('Alt');
  await page.waitForTimeout(900);
  return live;
}
/** 작업본을 형식 4 팩 파일 JSON으로 (파일로 = HT.F4.toFile) — 아무것도 안 끌면 같은 바이트인지 견줌 */
const fileText = page => page.evaluate(() => { const d = __maker.draft; return JSON.stringify(HT.F4.toFile(HT.packToJSON(HT.normalizePack(d).pack), d.f4extras)); });
const nsOf = (page, uid) => page.evaluate(u => { const p = __state.model.byUid.get(u); return HT.northOf(p); }, uid);

try {
  /* ================= ㉮ 견본을 작업본으로 ================= */
  {
    const page = await newPage({ 'ht.maker.draft': sample }, '㉮');
    const reed = sample.periods.find(p => p.name === '갈대 공국'), upper = sample.periods.find(p => p.name === '윗물국');
    await focus(page, 'hayeon', P + reed.id, [-700, 1800]);
    const before = await rows(page, 'hayeon'), beforeG = await groupRows(page, 'hayeon', 'hayeon-in');
    const startBefore = await page.evaluate(u => [__state.model.byUid.get(u).start, __state.model.byUid.get(u).end], P + reed.id);
    check(beforeG.includes('갈대 공국') && beforeG[0] !== '갈대 공국', '처음: 하연인 묶음(시작 연도)의 줄 — 갈대 공국은 맨 위가 아님', beforeG);
    const file0 = await fileText(page);
    await page.screenshot({ path: path.join(output, '1-전-1920-1배.png') });
    /* 끌다가 Esc = 그만둠: 작업본 · 파일 바이트 그대로 */
    {
      const b = await box(page, `#timeline .tl-band[data-uid="${P + reed.id}"]`), x = b.x + Math.min(40, b.w / 2), y = b.y + b.h / 2;
      const g = await page.evaluate(() => { const tr = __tl.tracks.find(x => x.id === 'hayeon'); return tr.groups.find(x => !x.scope && x.key === 'hayeon-in').first; });
      const lt = await laneBox(page, 'hayeon', g);
      await page.keyboard.down('Alt'); await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(x, y - 8); await page.mouse.move(x, lt.y + 4, { steps: 6 });
      const shown = await page.evaluate(() => !!document.querySelector('.mk-drag-row-line:not([hidden])'));
      await page.keyboard.press('Escape'); await page.mouse.up(); await page.keyboard.up('Alt'); await page.waitForTimeout(600);
      check(shown && (await fileText(page)) === file0 && JSON.stringify(await rows(page, 'hayeon')) === JSON.stringify(before), '끌다가 Esc: 작업본 · 형식 4 파일 바이트 · 줄 차례 그대로');
    }
    const first = await page.evaluate(() => { const tr = __tl.tracks.find(x => x.id === 'hayeon'); return tr.groups.find(x => !x.scope && x.key === 'hayeon-in').first; });
    const top = await laneBox(page, 'hayeon', first);
    const live = await altDrag(page, P + reed.id, top.y + 4, '2-끄는-중-1920-1배.png');
    check(/^놓으면: «.+» 위 · 남북 위치 [-\d.]+ · «하연인» 북 → 남$/.test(live.tip) && live.line && !live.no, "끄는 중: 풍선에 '놓으면: «…» 위 · 남북 위치 … · «하연인» 북 → 남' · 놓을 자리 점선", live);
    const after = await rows(page, 'hayeon'), afterG = await groupRows(page, 'hayeon', 'hayeon-in');
    const people = await page.evaluate(() => __maker.draft.peoples.find(x => x.id === 'hayeon-in').rowOrder);
    check(people === 'northSouth', "놓으면 하연인의 배열 기준이 '북 → 남'(작업본 rowOrder)", people);
    check(afterG[0] === '갈대 공국' && JSON.stringify(afterG.slice(1)) === JSON.stringify(beforeG.filter(x => x !== '갈대 공국')), '끈 줄만 맨 위로 — 나머지 줄 차례는 그대로', { 전: beforeG, 뒤: afterG });
    check(JSON.stringify(after.filter(x => x !== '갈대 공국')) === JSON.stringify(before.filter(x => x !== '갈대 공국')), '트랙의 다른 줄(소속 줄 포함) 차례는 그대로', { 전: before, 뒤: after });
    const vals = await page.evaluate(() => { const tr = __tl.tracks.find(x => x.id === 'hayeon'), g = tr.groups.find(x => !x.scope && x.key === 'hayeon-in'); return tr.rowPeriods.slice(g.first, g.first + g.count).map(r => HT.northOf(r[0])); });
    check(vals.every((v, i) => v != null && (!i || v < vals[i - 1])), '줄 머리 나라의 남북 값이 위에서 아래로 내려감', vals);
    const maxBefore = Math.max(...sample.periods.filter(p => p.people === '하연인' && p.northSouth != null).map(p => p.northSouth));
    check(vals[0] <= maxBefore, '묶음의 가장 북쪽 값은 넘지 않음(위 민족 안 자리 그대로)', { 맨위: vals[0], 전최대: maxBefore });
    const startAfter = await page.evaluate(u => [__state.model.byUid.get(u).start, __state.model.byUid.get(u).end], P + reed.id);
    check(JSON.stringify(startAfter) === JSON.stringify(startBefore), '가로(날짜)는 그대로', { 전: startBefore, 뒤: startAfter });
    await page.screenshot({ path: path.join(output, '3-놓은-뒤-1920-1배.png') });
    /* 형식 4 파일로 내렸다 다시 읽음 (파일로 = HT.F4.toFile) */
    const saved = await page.evaluate(([u, k]) => {
      const d = __maker.draft, pack = HT.normalizePack(d).pack, file = HT.F4.toFile(HT.packToJSON(pack), d.f4extras);
      const back = HT.normalizePack(JSON.parse(JSON.stringify(file))).pack;
      return { fv: file.formatVersion, rule: (back.peoples.find(x => x.id === k) || {}).rowOrder, ns: (back.periods.find(x => x.id === u) || {}).northSouth, want: d.periods.find(x => x.id === u).northSouth };
    }, [reed.id, 'hayeon-in']);
    check(saved.fv === 4 && saved.rule === 'northSouth' && saved.ns === saved.want && saved.ns != null, '형식 4 파일로 내렸다 다시 읽어도 배열 기준 · 남북 위치가 남음', saved);
    /* 다른 트랙 자리(하연 트랙 바로 아래 트랙) 위에서는 놓을 수 없음 */
    await focus(page, 'hayeon', P + upper.id, [-700, 1800]);
    const text0 = await draftText(page);
    const tb = await box(page, '.tl-track[data-track="hayeon"]');
    const ob = { y: tb.y + tb.h + 20 < 1040 ? tb.y + tb.h + 20 : tb.y - 15, h: 0 };
    const refused = await altDrag(page, P + upper.id, ob.y + ob.h / 2, '4-놓을-수-없는-곳-1920-1배.png');
    check(refused.no && !refused.line && /다른 민족 · 다른 트랙으로는 옮길 수 없습니다/.test(refused.tip), '다른 트랙 자리: 점선 없이 까닭 글만', refused);
    check((await draftText(page)) === text0, '놓을 수 없는 곳에서 놓으면 작업본 그대로');
    /* 되돌리기 한 번 = 처음으로 */
    await page.evaluate(() => __maker.undo());
    await page.waitForTimeout(900);
    const undone = { rows: await rows(page, 'hayeon'), rule: await page.evaluate(() => __maker.draft.peoples.find(x => x.id === 'hayeon-in').rowOrder), ns: await nsOf(page, P + reed.id) };
    check(JSON.stringify(undone.rows) === JSON.stringify(before) && undone.rule === 'start' && undone.ns === reed.northSouth, '되돌리기 한 번에 차례 · 배열 기준 · 남북 위치가 처음으로', undone);
    check((await fileText(page)) === file0, '되돌린 뒤 형식 4 파일 바이트가 처음과 같음');
    /* Alt+↓ = 한 칸 아래 (북 → 남인 대륙인 안 묶음이 아니라 하연인 안 줄) */
    await focus(page, 'hayeon', P + reed.id, [-700, 1800]);
    const g0 = await groupRows(page, 'hayeon', 'hayeon-in'), at = g0.indexOf('갈대 공국');
    await page.keyboard.press('Alt+ArrowDown');
    await page.waitForTimeout(900);
    const g1 = await groupRows(page, 'hayeon', 'hayeon-in');
    check(g1.indexOf('갈대 공국') === at + 1 && JSON.stringify(g1.filter(x => x !== '갈대 공국')) === JSON.stringify(g0.filter(x => x !== '갈대 공국')), 'Alt+↓: 한 칸 아래로 · 다른 줄 차례 그대로', { 전: g0, 뒤: g1 });
    await page.context().close();
  }
  /* ================= ㉯ 견본 = 불러온 팩(자물쇠 풂) · 작업본 = 가상의 작은 DLC ================= */
  {
    const own = { format: 'history-timeline-dlc', formatVersion: 3, id: 'rows-check-own', name: '가상 줄 옮기기', version: '1.0.0', tracks: [{ id: 'rc-wind', name: '바람 들', color: '#b6c398', order: 990 }], periods: [{ id: 'rc-p', track: 'rc-wind', name: '바람 나라', start: 100, end: 300 }] };
    const page = await newPage({ 'ht.packs.installed': [sample], 'ht.maker.draft': own, 'ht.maker.refs': { [own.id]: [{ id: sample.id, show: true, locked: false }] } }, '㉯');
    /* 북 → 남인 청림인 묶음(청림 트랙) — 하나뿐인 제 줄 청림 생태 자치연방을 맨 위로: 덮어쓰기만 · 민족 줄 없음 */
    const commune = sample.periods.find(p => p.name === '청림 생태 자치연방');
    await focus(page, 'cheongnim', P + commune.id, [-400, 1800]);
    const g0 = await groupRows(page, 'cheongnim', 'cheongnim-in');
    const first = await page.evaluate(() => { const tr = __tl.tracks.find(x => x.id === 'cheongnim'); return tr.groups.find(x => !x.scope && x.key === 'cheongnim-in').first; });
    const top = await laneBox(page, 'cheongnim', first);
    await altDrag(page, P + commune.id, top.y + 4, '5-남의-팩-끄는-중-1920-1배.png');
    const g1 = await groupRows(page, 'cheongnim', 'cheongnim-in');
    const d1 = await page.evaluate(u => ({ patch: (__maker.draft.patches || []).find(x => x.target === u), peoples: (__maker.draft.peoples || []).length }), P + commune.id);
    check(g1[0] === '청림 생태 자치연방' && g0[0] !== g1[0] && d1.patch && typeof d1.patch.set.northSouth === 'number' && !d1.peoples, "남의 나라(북 → 남 묶음): 덮어쓰기 set.northSouth만 · 민족 줄은 적지 않음", { 전: g0, 뒤: g1, ...d1 });
    await page.screenshot({ path: path.join(output, '6-남의-팩-놓은-뒤-1920-1배.png') });
    /* 불러온 팩이 '시작 연도'로 정한 하연인: Alt+↑는 막고 알림 */
    const reed = sample.periods.find(p => p.name === '갈대 공국');
    await focus(page, 'hayeon', P + reed.id, [-700, 1800]);
    const t0 = await draftText(page);
    await page.keyboard.press('Alt+ArrowUp');
    await page.waitForTimeout(500);
    const toast = await page.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    check(/불러온 팩 «등불 연대기[^»]*»이 '시작 연도'\(으\)로 정해 두어/.test(toast) && (await draftText(page)) === t0, "불러온 팩이 기준을 정해 둔 민족: 막고 알림(작업본 그대로)", toast);
    /* 기준을 적지 않은 남의 민족(제 줄이 둘 이상인 묶음을 찾아): 내 DLC에 같은 id 민족 줄(배열 기준만) */
    const pick = await page.evaluate(() => {
      const defs = new Set(__state.packs.flatMap(pk => (pk.peoples || []).filter(x => x.rowOrder).map(x => x.id)));
      for (const tr of __tl.tracks) for (const g of tr.groups || []) {
        if (g.scope || g.folded || defs.has(g.key) || HT.rowOrderOf(__state.model.peopleMap.get(g.key), __state.model.peopleMap) !== 'start') continue;
        const heads = tr.rowPeriods.slice(g.first, g.first + g.count).map(r => r[0]).filter(p => p && p.peopleId === g.key && !p._member);
        if (heads.length >= 2) return { track: tr.id, key: g.key, uid: heads[1].uid, name: heads[1].name };
      }
      return null;
    });
    check(!!pick, '기준을 적지 않은 남의 민족 묶음(제 줄 둘 이상)을 찾음', pick);
    await focus(page, pick.track, pick.uid, [-700, 1800]);
    const h0 = await groupRows(page, pick.track, pick.key);
    await page.keyboard.press('Alt+ArrowUp');
    await page.waitForTimeout(900);
    const h1 = await groupRows(page, pick.track, pick.key);
    const d2 = await page.evaluate(k => ({ people: (__maker.draft.peoples || []).find(x => x.id === k), rule: HT.rowOrderOf(__state.model.peopleMap.get(k), __state.model.peopleMap) }), pick.key);
    check(d2.people && d2.people.rowOrder === 'northSouth' && Object.keys(d2.people).sort().join() === 'id,name,rowOrder' && d2.rule === 'northSouth' && h1.indexOf(h0[h0.indexOf(h0.find(x => x.startsWith(pick.name)))]) === h0.findIndex(x => x.startsWith(pick.name)) - 1, '남의 민족: 내 DLC에 같은 id 민족 줄(id · 이름 · 배열 기준만) → 연표 기준이 북 → 남 · 한 칸 위로', { 전: h0, 뒤: h1, ...d2 });
    await page.screenshot({ path: path.join(output, '7-남의-민족-같은-id-1920-1배.png') });
    await page.context().close();
  }
  check(!report.오류.length, '페이지 오류 0', report.오류);
} finally {
  fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
  await browser.close();
  server.close();
}
console.log(`줄 위아래 옮기기 검사 ${report.검사.length}항목 통과 · 페이지 오류 ${report.오류.length}`);

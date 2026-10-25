/* 단체 계보 창(설계 D5 결정 4 A) · 법 · 선거 규격의 상세 창(결정 7 A)을 실제 브라우저(1920×1080 · 배율 1)에서 검사합니다.
   ① 배치 셈(HT.groupTreeLayout): 줄 · 이름 바꿈 이어 쓰기 · 합쳐짐 · 집권 n번 · 연정 m번(겹친 집권 = 연정)
   ② 창: 나라 상세의 '단체 계보' → 아래쪽 넓은 창(연표 폭 · 바닥 · 525px) · 연표는 창 위쪽까지만 · 상세 창 · 확대 단추가 창 위로 비킴
   ③ 연도 눈금이 위 연표와 같은 x(눈금 글 · 막대 머리) — 연표를 옮기면 나무도 함께
   ④ 겹침 · 돌출: 나무 안 글끼리 겹치지 않음 · 막대 이름은 제 막대의 보이는 부분 안 · 창 안 조각은 창 밖으로 나가지 않음
   ⑤ 집권 구간: 1px 짙은 테두리(감독 덧붙임) · 막대 안
   ⑥ 막대 누름 → 연표 조명(집권 덩이) · 그 나라 띠가 창 위에 보임 · 왼쪽 칸 / 두 번 누름 → 단체 창(창 위) / 이음선 → 그 일의 사건
   ⑦ Esc: 상세 창 먼저, 그다음 계보 창 · 닫으면 연표 자리가 1px도 그대로
   ⑧ '방식 미상' 그림(형식이 how: unknown을 아직 받지 않아 모델 값을 바꿔 그려 봄) · 단체 창의 '단체 계보' 단추 — 나무 전체가 보기 밖이면 나무 전체로,
      나무는 보이지만 고른 단체가 보기 밖이면 그 단체의 기간으로(조금이라도 보이면 그대로)
   ⑨ 성능: 단체 120개 나무를 다시 그리는 시간
   ⑩ 법의 내력 · 의석 막대 · 관련(결정 7) · 모임 이름이 단체면 단체 창으로
   ⑪ 메이커에서도 창이 연표(#stage) 안에 붙음
   검사 자료는 모두 가상 이름(고증 아님) — 견본 sample-lantern(등불 연대기)에 아래 TREE_DLC를 더해 설치합니다.
   계보 나무 ①~⑨는 TREE_DLC의 '솔 왕국', 견본 단체 창의 '단체 계보' 단추(산호 해상 동맹 — 진주파 · 닻파 → 항로당 · 등불당) · 법의 내력(등좌 기본법 보수 개정) · 의석 막대(첫 양원 총선)는 견본으로.
   node scripts/group-window-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge) */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/단체-계보');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
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
const report = { 화면: '1920×1080 · 100% · 1배', 검사: [], 측정: {}, 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
const sample = name => JSON.parse(fs.readFileSync(path.join(root, 'samples', name + '.json'), 'utf8'));
/** 끝이 있는 움직임(창의 slide-up 등 — 동작 줄이기여도 --t-in)이 다 끝난 뒤 두 장면. 끝없는 움직임은 기다리지 않고, 길어도 1.5초 */
const settleAnimations = page =>
  page.evaluate(() =>
    Promise.race([
      Promise.all(document.getAnimations().filter(a => { const t = a.effect && a.effect.getComputedTiming(); return t && Number.isFinite(t.endTime); }).map(a => a.finished.catch(() => null))),
      new Promise(r => setTimeout(r, 1500)),
    ]).then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))
  );

/* 가상 나라 '솔 왕국'(가상 들) 안의 가상 단체 열하나 — 설계 목업(결정 4)의 이야기와 같은 꼴 · 고증 아님 */
const TREE_DLC = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'check-group-tree', name: '검사 — 단체 계보', version: '1.0.0',
  tracks: [{ id: 'gt-land', name: '가상 들', color: '#d7c18e', order: 95 }],
  periods: [{ id: 'gt-sol', track: 'gt-land', name: '솔 왕국', start: 1500, end: 1810, leaders: [['첫 임금', 1500, 1560], ['둘째 임금', 1560, 1640], ['셋째 임금', 1640, 1720], ['넷째 임금', 1720, 1810]] }],
  events: [
    { id: 'gt-e-split1', track: 'gt-land', polity: '솔 왕국', title: '옛 무리가 둘로 갈라짐', start: 1575, category: 'politics' },
    { id: 'gt-e-split2', track: 'gt-land', polity: '솔 왕국', title: '물 무리가 다시 갈라짐', start: 1591, category: 'politics' },
    { id: 'gt-e-merge', track: 'gt-land', polity: '솔 왕국', title: '들 무리와 바위 무리가 합침', start: 1650, category: 'politics' },
    { id: 'gt-e-rename', track: 'gt-land', polity: '솔 왕국', title: '저녁 무리가 이름을 바꿈', start: 1760, category: 'politics' },
  ],
  groups: [
    { id: 'g-old', track: 'gt-land', name: '옛 무리', type: 'faction', within: '솔 왕국', start: 1560, end: 1575 },
    { id: 'g-sol', track: 'gt-land', name: '솔 무리', type: 'faction', within: '솔 왕국', start: 1575, end: 1683, from: [{ group: 'g-old', how: 'split' }], power: [['집권', 1589, 1591], ['집권', 1623, 1674], ['집권', 1680, 1683]], event: '옛 무리가 둘로 갈라짐' },
    { id: 'g-mul', track: 'gt-land', name: '물 무리', type: 'faction', within: '솔 왕국', start: 1575, end: 1591, from: [{ group: 'g-old', how: 'split' }], power: [['집권', 1575, 1589]], event: '옛 무리가 둘로 갈라짐' },
    { id: 'g-sae', track: 'gt-land', name: '새벽 무리', type: 'faction', within: '솔 왕국', start: 1683, end: 1800, from: [{ group: 'g-sol', how: 'split' }], power: [['집권', 1683, 1689], ['집권', 1694, 1720], ['집권', 1724, 1728], ['집권', 1728, 1786], ['집권', 1786, 1800]] },
    { id: 'g-jeo', track: 'gt-land', name: '저녁 무리', type: 'faction', within: '솔 왕국', start: 1683, end: 1760, from: [{ group: 'g-sol', how: 'split' }], power: [['집권', 1720, 1724], ['연정', 1728, 1760]] },
    { id: 'g-nol', track: 'gt-land', name: '노을 무리', type: 'faction', within: '솔 왕국', start: 1760, end: 1800, from: [{ group: 'g-jeo', how: 'rename' }], power: [['연정', 1760, 1786]], event: '저녁 무리가 이름을 바꿈' },
    { id: 'g-deul', track: 'gt-land', name: '들 무리', type: 'faction', within: '솔 왕국', start: 1591, end: 1650, from: [{ group: 'g-mul', how: 'split' }], power: [['집권', 1591, 1623]], event: '물 무리가 다시 갈라짐' },
    { id: 'g-bawi', track: 'gt-land', name: '바위 무리', type: 'faction', within: '솔 왕국', start: 1591, end: 1650, from: [{ group: 'g-mul', how: 'split' }], event: '물 무리가 다시 갈라짐' },
    { id: 'g-neo', track: 'gt-land', name: '너른 무리', type: 'faction', within: '솔 왕국', start: 1650, end: 1800, from: [{ group: 'g-deul', how: 'merge' }, { group: 'g-bawi', how: 'merge' }], power: [['집권', 1674, 1680], ['집권', 1689, 1694], ['연정', 1776, 1786]], event: '들 무리와 바위 무리가 합침' },
    { id: 'g-bar', track: 'gt-land', name: '바람 무리', type: 'faction', within: '솔 왕국', start: 1730, end: 1800, from: [{ group: 'g-neo' }] },
    { id: 'g-got', track: 'gt-land', name: '곧은 무리', type: 'faction', within: '솔 왕국', start: 1700, end: 1760, from: [{ group: 'g-neo' }] },
  ],
};

/** 창 안 조각 검사(페이지 안에서): 나무 글끼리 겹침 · 막대 이름이 제 막대의 보이는 부분 밖 · 창 밖으로 나간 조각 */
const AUDIT = () => {
  const out = [];
  const sheet = document.querySelector('#groupTree');
  const sr = sheet.getBoundingClientRect();
  const svgR = sheet.querySelector('.gt-svg').getBoundingClientRect();
  const scrollR = sheet.querySelector('.gt-scroll').getBoundingClientRect();
  const texts = [...sheet.querySelectorAll('.gt-svg text')].map(t => ({ t, r: t.getBoundingClientRect(), s: t.textContent }));
  const vis = r => r.bottom > scrollR.top && r.top < scrollR.bottom; // 나무 안 세로 밀기로 가려진 줄은 빼고
  for (let i = 0; i < texts.length; i++)
    for (let j = i + 1; j < texts.length; j++) {
      const a = texts[i].r, b = texts[j].r;
      if (vis(a) && vis(b) && a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5) out.push(`글 겹침: ${texts[i].s} / ${texts[j].s}`);
    }
  for (const bar of sheet.querySelectorAll('.gt-bar')) {
    const b = bar.querySelector('.gt-base').getBoundingClientRect();
    const name = bar.querySelector('.gt-name');
    if (!name) continue;
    const r = name.getBoundingClientRect();
    const left = Math.max(b.left, svgR.left), right = Math.min(b.right, svgR.right);
    if (r.left < left - 0.5 || r.right > right + 0.5 || r.top < b.top - 0.5 || r.bottom > b.bottom + 0.5) out.push(`이름이 막대 밖: ${name.textContent}`);
    for (const seg of bar.querySelectorAll('.gt-seg')) {
      const q = seg.getBoundingClientRect();
      if (q.left < b.left - 0.5 || q.right > b.right + 0.5 || q.top < b.top - 0.5 || q.bottom > b.bottom + 0.5) out.push(`집권 구간이 막대 밖: ${bar.dataset.uid}`);
    }
  }
  for (const el of sheet.querySelectorAll('.gt-head, .gt-title, .gt-legend > span, .gt-axis span, .gt-foot button, .gt-side')) {
    const r = el.getBoundingClientRect();
    if (r.width && (r.left < sr.left - 0.5 || r.right > sr.right + 0.5 || r.top < sr.top - 0.5 || r.bottom > sr.bottom + 0.5)) out.push(`창 밖: ${el.className || el.textContent}`);
  }
  const ax = [...sheet.querySelectorAll('.gt-axis span')].map(s => s.getBoundingClientRect());
  for (let i = 1; i < ax.length; i++) if (ax[i].left < ax[i - 1].right) out.push('연도 눈금 글 겹침');
  return out;
};

try {
  const view = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  await view.addInitScript(packs => { if (!localStorage.getItem('ht.packs.installed')) localStorage.setItem('ht.packs.installed', JSON.stringify(packs)); }, [sample('sample-lantern'), TREE_DLC]);
  const page = await view.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => { if (m.type() === 'error') report.오류.push(m.text()); });
  await page.goto(base + 'index.html');
  await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && (HT.viewer.state.model.groups || []).length && HT.viewer.groupTree);
  await page.evaluate(() => HT.viewer.timeline.setView(1550, 1800));
  await page.waitForTimeout(250);

  /* ① 배치 셈 */
  const lay = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    const sol = m.periods.find(p => p.name === '솔 왕국');
    const L = HT.groupTreeLayout(m, { polityUid: sol.uid });
    return {
      rows: L.rows,
      nodes: Object.fromEntries(L.nodes.map(n => [n.g.name, { row: n.row, count: n.count, segs: n.segs.map(s => `${s.kind}:${s.a}-${s.b}`) }])),
      edges: L.edges.map(e => `${e.from.name}>${e.to.name}:${e.kind}${e.same ? '=' : ''}${e.ev ? '!' : ''}`),
    };
  });
  const N = lay.nodes;
  check(lay.rows === 10 && Object.keys(N).length === 11, '배치 — 단체 열하나 · 줄 열(이름 바꿈은 같은 줄)', { rows: lay.rows });
  check(N['옛 무리'].row === 0 && N['솔 무리'].row === 1 && N['새벽 무리'].row === 2 && N['저녁 무리'].row === 3 && N['노을 무리'].row === 3 && N['물 무리'].row === 4, '배치 — 뿌리 아래 앞 줄부터 · 노을 무리는 저녁 무리 줄을 이어 씀', N);
  check(N['들 무리'].row === 5 && N['바위 무리'].row === 6 && N['너른 무리'].row === 7, '배치 — 합쳐진 너른 무리는 앞선 단체 가운데 아래 줄(바위 무리) 밑', N);
  check(N['바람 무리'].row === 8 && N['곧은 무리'].row === 9, '배치 — 한 부모의 아이는 늦게 시작한 것이 위(이음선이 막대를 가로지르지 않음)', N);
  check(N['새벽 무리'].count === '집권 4번 · 연정 1번' && N['저녁 무리'].count === '집권 1번 · 연정 1번' && N['너른 무리'].count === '집권 2번 · 연정 1번' && N['노을 무리'].count === '연정 1번' && N['바위 무리'].count === '', '집권 n번 · 연정 m번 — 맞닿은 같은 종류는 한 번, 다른 단체와 겹친 집권은 연정', Object.fromEntries(Object.entries(N).map(([k, v]) => [k, v.count])));
  check(N['새벽 무리'].segs.includes('coal:1728-1786'), '새벽 무리 1728~1786은 저녁 · 노을 · 너른 무리와 겹쳐 연정', N['새벽 무리'].segs);
  check(lay.edges.includes('옛 무리>솔 무리:split!') && lay.edges.includes('들 무리>너른 무리:merge!') && lay.edges.includes('바위 무리>너른 무리:merge!') && lay.edges.includes('저녁 무리>노을 무리:rename=!') && lay.edges.includes('너른 무리>바람 무리:blank'), '이음 — 갈라짐 · 합쳐짐 · 이름 바꿈(같은 줄) · 적지 않음 · 사건이 있는 이음(!)', lay.edges);

  /* ② 창 — 나라 상세의 '단체 계보' */
  const hostBefore = await page.evaluate(() => JSON.parse(JSON.stringify(document.querySelector('#timeline').getBoundingClientRect())));
  await page.evaluate(() => HT.viewer.openDetail(HT.viewer.state.model.periods.find(p => p.name === '솔 왕국').uid));
  await page.locator('#detail [data-act="group-tree"]').click();
  await page.waitForFunction(() => !document.querySelector('#groupTree').hidden && document.querySelectorAll('#groupTree .gt-bar').length === 11);
  await page.waitForTimeout(300);
  await settleAnimations(page); // 견본 2.0.0을 함께 그리면 첫 그리기가 길어 300ms 뒤에도 창이 나타나는 움직임(slide-up — 8px 아래에서) 중일 수 있음
  const geo = await page.evaluate(() => {
    const r = q => JSON.parse(JSON.stringify(document.querySelector(q).getBoundingClientRect()));
    return { sheet: r('#groupTree'), stage: r('#stage'), host: r('#timeline'), detail: r('#detail'), zoom: r('.zoom-controls'), sub: document.querySelector('#groupTree .gt-sub').textContent, badges: document.querySelector('#groupTree .badges').textContent };
  });
  check(Math.abs(geo.sheet.bottom - 1080) < 1 && Math.abs(geo.sheet.left - geo.stage.left) < 1 && Math.abs(geo.sheet.width - geo.stage.width) < 1 && Math.abs(geo.sheet.height - 525) < 1, '창 — 연표 폭 그대로 바닥에 붙음 · 1080 화면에서 525px', geo.sheet);
  check(geo.host.bottom <= geo.sheet.top + 0.5 && geo.detail.bottom <= geo.sheet.top && geo.zoom.bottom <= geo.sheet.top, '연표는 창 위쪽까지만 · 상세 창 · 확대 단추가 창 위로 비킴', { host: geo.host.bottom, detail: geo.detail.bottom, zoom: geo.zoom.bottom, sheet: geo.sheet.top });
  check(/솔 왕국 · 단체 11/.test(geo.sub) && /단체 계보/.test(geo.badges), '창 머리 — 나라 · 단체 수', geo.sub);
  await page.screenshot({ path: path.join(output, '단체-계보-창-상세와-함께-1920-1배.png') });

  /* ③ 연도 눈금 · 막대 머리가 연표와 같은 x */
  const align = async (uid, inL, inR) =>
    page.evaluate(([uid, inL, inR]) => {
      const tl = HT.viewer.timeline;
      const br = tl.bodyEl.getBoundingClientRect();
      const X = t => br.left + tl.gutter + ((t - tl.view.start) / (tl.view.end - tl.view.start)) * tl.W;
      const tick = [...document.querySelectorAll('.tl-axis .tl-tick')].map(s => ({ s: s.textContent, x: s.getBoundingClientRect().left + s.getBoundingClientRect().width / 2 }));
      const mine = [...document.querySelectorAll('#groupTree .gt-axis span')].map(s => ({ s: s.textContent, x: s.getBoundingClientRect().left + s.getBoundingClientRect().width / 2 }));
      const pairs = mine.map(m => [m, tick.find(t => t.s === m.s)]).filter(([, t]) => t);
      const g = HT.viewer.state.model.byUid.get(uid); // 다른 팩에 같은 이름의 단체가 있어도 헷갈리지 않게 uid로
      const bar = document.querySelector(`#groupTree .gt-bar[data-uid="${CSS.escape(g.uid)}"] .gt-base`).getBoundingClientRect();
      return { n: pairs.length, worst: Math.max(...pairs.map(([m, t]) => Math.abs(m.x - t.x))), bar: Math.abs(bar.left - X(g.start) - inL), barR: Math.abs(bar.right - X(g.endY) + inR), view: [tl.view.start, tl.view.end] };
    }, [uid, inL, inR]);
  const a1 = await align('check-group-tree/g-old', 0, 3); // 뿌리 — 머리 그대로 · 끝은 아이들이 시작하는 자리라 3px 비움
  check(a1.n >= 8 && a1.worst <= 1 && a1.bar <= 1 && a1.barR <= 1, '연도 눈금 · 막대 머리 · 끝이 위 연표와 같은 x (1px 안)', a1);
  await page.evaluate(() => HT.viewer.timeline.setView(1600, 1760));
  await page.waitForTimeout(250);
  const a2 = await align('check-group-tree/g-neo', 5, 0); // 합쳐진 단체 — 이음선이 닿는 머리는 5px 들임
  check(a2.n >= 6 && a2.worst <= 1 && a2.bar <= 1 && a2.barR <= 1, '연표를 옮기고 당기면 나무도 함께 (1600~1760)', a2);
  check((await page.evaluate(AUDIT)).length === 0, '겹침 · 돌출 없음 (1600~1760 — 잘린 막대의 이름은 보이는 부분 안)', await page.evaluate(AUDIT));
  await page.evaluate(() => HT.viewer.timeline.setView(1550, 1800));
  await page.waitForTimeout(250);
  const audit = await page.evaluate(AUDIT);
  check(audit.length === 0, '겹침 · 돌출 없음 (1550~1800)', audit);

  /* ⑤ 집권 구간의 얇은 짙은 테두리 */
  const seg = await page.evaluate(() => {
    const g = HT.viewer.state.model.groups.find(q => q.name === '새벽 무리');
    const bar = document.querySelector(`#groupTree .gt-bar[data-uid="${CSS.escape(g.uid)}"]`);
    const s = [...bar.querySelectorAll('.gt-seg')].map(e => ({ k: e.getAttribute('class'), w: getComputedStyle(e).strokeWidth, stroke: getComputedStyle(e).stroke, fill: getComputedStyle(e).fill }));
    const b = getComputedStyle(bar.querySelector('.gt-base'));
    const lum = c => {
      const m = c.match(/[\d.]+/g).map(Number);
      return c.startsWith('color(srgb') ? 0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2] : (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255;
    };
    return { n: s.length, kinds: s.map(x => x.k), w: [...new Set(s.map(x => x.w))], darker: s.every(x => lum(x.stroke) < lum(b.stroke)), coalLighter: lum(s.find(x => /is-coal/.test(x.k)).fill) > lum(s.find(x => /is-power/.test(x.k)).fill) };
  });
  check(seg.n === 5 && seg.w.length === 1 && seg.w[0] === '1px' && seg.darker && seg.coalLighter, '집권 구간 — 1px 짙은 테두리(막대 테두리보다 짙음) · 연정은 집권보다 옅은 칠', seg);

  /* ⑥ 막대 누름 → 조명 · 그 나라 띠가 창 위에 · 왼쪽 칸 */
  await page.evaluate(() => HT.viewer.closeDetail());
  await page.waitForTimeout(200);
  await page.locator('#groupTree .gt-bar', { hasText: '새벽 무리' }).first().click();
  await page.waitForTimeout(300);
  const pick = await page.evaluate(() => {
    const tl = HT.viewer.timeline;
    const sol = HT.viewer.state.model.periods.find(p => p.name === '솔 왕국');
    const band = document.querySelector(`.tl-band[data-uid="${CSS.escape(sol.uid)}"]`);
    const br = band ? band.getBoundingClientRect() : null;
    return { spots: tl.spots.map(s => `${s.start}-${s.end}`), same: tl.spots.every(s => s.uid === sol.uid), band: br && JSON.parse(JSON.stringify(br)), sheetTop: document.querySelector('#groupTree').getBoundingClientRect().top, side: document.querySelector('#groupTree .gt-side').textContent, here: document.querySelectorAll('#groupTree .gt-bar.is-here').length };
  });
  check(pick.same && pick.spots.join(',') === '1683-1689,1694-1720,1724-1728,1728-1786,1786-1800', '막대를 누르면 그 나라 띠에 집권 덩이마다 조명', pick.spots);
  check(pick.band && pick.band.bottom <= pick.sheetTop + 0.5 && pick.band.top >= 60, '그 나라 띠가 창 위의 보이는 자리에', { band: pick.band, sheetTop: pick.sheetTop });
  check(/새벽 무리/.test(pick.side) && /집권 4번 · 연정 1번/.test(pick.side) && pick.here === 1, '왼쪽 칸 — 고른 단체 · 기간 · 집권 n번 · 연정 m번', pick.side.slice(0, 80));
  await page.screenshot({ path: path.join(output, '단체-계보-창-막대-누름-1920-1배.png') });
  await page.locator('#groupTree .gt-bar', { hasText: '새벽 무리' }).first().dblclick();
  await page.waitForTimeout(250);
  const dbl = await page.evaluate(() => ({ title: document.querySelector('#detail h2').textContent, bottom: document.querySelector('#detail').getBoundingClientRect().bottom, top: document.querySelector('#groupTree').getBoundingClientRect().top, spots: HT.viewer.timeline.spots.length, btn: !!document.querySelector('#detail [data-act="group-tree"]') }));
  check(dbl.title === '새벽 무리' && dbl.bottom <= dbl.top && dbl.spots === 5 && dbl.btn, '두 번 누르면 단체 창(창 위 · 조명은 그대로 · 단체 창에 \'단체 계보\' 단추)', dbl);
  /* 이음선 → 그 일의 사건 */
  const hit = await page.evaluate(() => {
    const g = HT.viewer.state.model.groups.find(q => q.name === '노을 무리');
    const p = [...document.querySelectorAll('#groupTree .gt-hit')].find(h => h.dataset.ev === g.eventItem.uid);
    if (!p) return null;
    const r = p.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  check(!!hit, '사건이 있는 이음선에 누르는 자리');
  await page.mouse.click(hit.x, hit.y);
  await page.waitForTimeout(250);
  check((await page.evaluate(() => document.querySelector('#detail h2').textContent)) === '저녁 무리가 이름을 바꿈', '이음선(이름 바꿈 다리)을 누르면 그 일의 사건 창');

  /* ⑦ Esc 차례 · 닫으면 연표 자리 그대로 */
  await page.locator('#timeline .tl-body').focus();
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  const e1 = await page.evaluate(() => ({ detail: document.querySelector('#detail').hidden, tree: document.querySelector('#groupTree').hidden }));
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  const e2 = await page.evaluate(() => ({ tree: document.querySelector('#groupTree').hidden, cls: document.querySelector('#stage').classList.contains('has-gtree'), spots: HT.viewer.timeline.spots.length, host: JSON.parse(JSON.stringify(document.querySelector('#timeline').getBoundingClientRect())) }));
  check(e1.detail && !e1.tree && e2.tree && !e2.cls && e2.spots === 0, 'Esc — 상세 창 먼저, 그다음 계보 창(조명도 걷힘)', { e1, e2: { tree: e2.tree, cls: e2.cls, spots: e2.spots } });
  check(['x', 'y', 'width', 'height'].every(k => Math.abs(e2.host[k] - hostBefore[k]) < 0.01), '닫으면 연표 자리가 1px도 그대로', { before: hostBefore, after: e2.host });

  /* Esc — 렌즈(js/lens-ui.js)를 켠 채 계보 창이 열려 있으면 창이 먼저, 그다음 렌즈 (렌즈 단추가 없는 화면이면 건너뜀) */
  if (await page.evaluate(() => !!document.querySelector('#themeLensBtn'))) {
    await page.evaluate(() => HT.viewer.groupTree.open({ polityUid: HT.viewer.state.model.periods.find(p => p.name === '솔 왕국').uid }));
    await page.locator('#timeline .tl-body').focus();
    await page.keyboard.press('s');
    await page.waitForTimeout(150);
    const l0 = await page.evaluate(() => ({ lens: !!HT.viewer.timeline.themeLens, tree: HT.viewer.groupTree.isOpen() }));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(100);
    const l1 = await page.evaluate(() => ({ lens: !!HT.viewer.timeline.themeLens, tree: HT.viewer.groupTree.isOpen() }));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(100);
    const l2 = await page.evaluate(() => ({ lens: !!HT.viewer.timeline.themeLens, tree: HT.viewer.groupTree.isOpen() }));
    check(l0.lens && l0.tree && l1.lens && !l1.tree && !l2.lens, 'Esc — 렌즈를 켠 채면 계보 창을 먼저 닫고, 다음 Esc에 렌즈 끔', { l0, l1, l2 });
  }

  /* ⑧ '방식 미상'(how: unknown — 지금 형식은 읽을 때 빼므로 모델 값을 바꿔 그려 봄) · 단체 창에서 열기 */
  const unk = await page.evaluate(async () => {
    const m = HT.viewer.state.model;
    const got = m.groups.find(q => q.name === '곧은 무리');
    got.fromList[0].how = 'unknown';
    HT.viewer.groupTree.open({ groupUid: got.uid });
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    const t = document.querySelector('#groupTree .gt-how');
    const dotted = [...document.querySelectorAll('#groupTree .gt-lines path')].filter(p => p.getAttribute('stroke-dasharray')).length;
    const faint = [...document.querySelectorAll('#groupTree .gt-lines path')].filter(p => p.getAttribute('stroke-width') === '1').length;
    return { text: t ? t.textContent : '', dotted, faint, here: document.querySelector('#groupTree .gt-bar.is-here') ? document.querySelector('#groupTree .gt-bar.is-here').textContent : '' };
  });
  check(unk.text === '방식 미상' && unk.dotted === 1 && unk.faint === 1 && /곧은 무리/.test(unk.here), "방식 미상 = 점선 + 글 '방식 미상' · 적지 않음 = 옅은 1px 선 · 단체로 열면 그 단체를 고른 채로", unk);
  check((await page.evaluate(AUDIT)).length === 0, "겹침 · 돌출 없음 ('방식 미상' 글 포함)", await page.evaluate(AUDIT));
  await page.screenshot({ path: path.join(output, '단체-계보-창-방식-미상-1920-1배.png') });
  await page.evaluate(() => HT.viewer.groupTree.close());
  /* 견본 등불 연대기 — 단체 창의 '단체 계보' 단추로 (보기를 나무가 없는 100~400으로 옮겨 둔 채: 산호 해상 동맹의 나무는 1031년부터) */
  await page.evaluate(() => HT.viewer.timeline.setView(100, 400));
  await page.waitForTimeout(250);
  await page.evaluate(() => HT.viewer.openDetail(HT.viewer.state.model.groups.find(g => g.name === '진주파').uid));
  await page.locator('#detail [data-act="group-tree"]').click();
  await page.waitForTimeout(300);
  const pearl = await page.evaluate(() => ({ n: document.querySelectorAll('#groupTree .gt-bar').length, here: (document.querySelector('#groupTree .gt-bar.is-here') || {}).textContent || '', sub: document.querySelector('#groupTree .gt-sub').textContent, view: [Math.round(HT.viewer.timeline.view.start), Math.round(HT.viewer.timeline.view.end)] }));
  check(pearl.n === 4 && /진주파/.test(pearl.here) && /산호 해상 동맹 · 단체 4/.test(pearl.sub) && pearl.view[0] <= 1031 && pearl.view[1] >= 1402, "견본 산호 해상 동맹 — 단체 창의 '단체 계보' 단추로 열면 그 나라 단체 넷(진주파 · 닻파와 뒤를 이은 항로당 · 등불당) · 그 단체를 고름 · 보기 범위 밖이면 나무가 들어오게", pearl);
  check((await page.evaluate(AUDIT)).length === 0, '겹침 · 돌출 없음 (견본 산호 해상 동맹)', await page.evaluate(AUDIT));
  await page.screenshot({ path: path.join(output, '단체-계보-창-견본-산호해상동맹-1920-1배.png') });
  await page.evaluate(() => { HT.viewer.closeDetail(); HT.viewer.groupTree.close(); });

  /* 고른 단체가 보기 밖이면(나무의 다른 단체는 보여도) 그 단체의 기간으로 — '이 시기로'와 같은 틀(앞뒤 15% · 적어도 2년)을 상세 창이 가리지 않은 부분에.
     2026-10-14 고침: 전에는 나무 전체가 보기 밖일 때만 옮겨, 고른 단체의 막대와 위 연표의 조명이 화면 밖에 남았음(왼쪽 칸은 '연표에 조명 중') */
  const pickOut = async (uid, from, to) => {
    await page.evaluate(([a, b]) => HT.viewer.timeline.setView(a, b), [from, to]);
    await page.waitForTimeout(200);
    await page.evaluate(u => HT.viewer.openDetail(u), uid);
    await page.locator('#detail [data-act="group-tree"]').click();
    await page.waitForTimeout(500);
    return page.evaluate(u => {
      const tl = HT.viewer.timeline;
      const g = HT.viewer.state.model.byUid.get(u);
      const base = document.querySelector(`#groupTree .gt-bar[data-uid="${CSS.escape(u)}"] .gt-base`);
      const r = base && base.getBoundingClientRect();
      const svg = document.querySelector('#groupTree .gt-svg').getBoundingClientRect();
      const br = tl.bodyEl.getBoundingClientRect();
      const X = t => br.left + tl.gutter + ((t - tl.view.start) / (tl.view.end - tl.view.start)) * tl.W;
      const d = document.querySelector('#detail');
      const right = Math.min(br.left + tl.gutter + tl.W, d && !d.hidden ? d.getBoundingClientRect().left : Infinity); // 위 연표에서 상세 창이 가리지 않은 오른쪽 끝
      return {
        view: [+tl.view.start.toFixed(2), +tl.view.end.toFixed(2)],
        span: [g.start, g.endY],
        here: (document.querySelector('#groupTree .gt-bar.is-here') || {}).textContent || '',
        bar: r ? [Math.round(r.left), Math.round(r.right)] : null,
        barIn: !!r && r.left >= svg.left - 0.5 && r.right <= svg.right + 0.5,
        spots: tl.spots.map(s => [s.start, s.end]),
        spotsIn: tl.spots.length > 0 && tl.spots.every(s => X(s.start) >= br.left + tl.gutter - 0.5 && X(s.end) <= right + 0.5),
      };
    }, uid);
  };
  const out1 = await pickOut('check-group-tree/g-old', 1700, 1800); // 옛 무리 1560~1575 — 나무의 새벽 · 너른 · 노을 무리 …는 1700~1800에 보임
  check(/옛 무리/.test(out1.here) && out1.view[0] < 1560 && out1.view[1] > 1575 && out1.view[1] - out1.view[0] < 40, "고른 단체가 보기 밖이면 그 단체의 기간으로 (옛 무리 1560~1575 · 보기 1700~1800에서 단체 창의 '단체 계보')", out1);
  check(out1.barIn && out1.spotsIn, '옮긴 뒤 — 고른 단체의 막대가 나무 안에 다 보이고, 위 연표의 조명은 상세 창이 가리지 않은 자리에', out1);
  check((await page.evaluate(AUDIT)).length === 0, '겹침 · 돌출 없음 (고른 단체의 기간으로 옮긴 뒤)', await page.evaluate(AUDIT));
  await page.screenshot({ path: path.join(output, '단체-계보-창-고른-단체로-옮김-1920-1배.png') });
  await page.evaluate(() => { HT.viewer.closeDetail(); HT.viewer.groupTree.close(); });
  const out2 = await pickOut('check-group-tree/g-old', 1570, 1700); // 1570~1575가 보임
  check(out2.view[0] === 1570 && out2.view[1] === 1700 && /옛 무리/.test(out2.here), '고른 단체가 조금이라도 보이면 보기를 옮기지 않음 (옛 무리 · 보기 1570~1700)', out2);
  await page.evaluate(() => { HT.viewer.closeDetail(); HT.viewer.groupTree.close(); });

  /* ⑨ 성능: 단체 120개(가상 · 모델에 잠깐 더함) 나무를 다시 그리는 시간 */
  const perf = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    const sol = m.periods.find(p => p.name === '솔 왕국');
    const extra = [];
    for (let i = 0; i < 120; i++) {
      const s = 1500 + ((i * 7) % 280);
      const g = { uid: `perf/${i}`, id: `p${i}`, kind: 'group', name: `시험 무리 ${i + 1}`, start: s, endY: s + 30, color: '#a0bcc5', withinList: [{ polityUid: sol.uid }], powerSpans: [{ name: '집권', start: s + 5, end: s + 12 }], fromList: [], intoList: [] };
      if (i) {
        const p = extra[Math.floor((i - 1) / 2)];
        g.fromList = [{ group: p, how: 'split' }];
        (p.intoList = p.intoList || []).push({ group: g, how: 'split' });
        g.start = Math.max(g.start, p.start + 3);
      }
      extra.push(g);
      m.byUid.set(g.uid, g);
    }
    const saved = m.groups;
    m.groups = saved.concat(extra);
    const T = HT.viewer.groupTree;
    T.open({ polityUid: sol.uid });
    const times = [];
    for (let k = 0; k < 20; k++) {
      HT.viewer.timeline.view = { start: 1500 + k, end: 1800 + k };
      T.state.key = '';
      const t0 = performance.now();
      T.sync();
      times.push(performance.now() - t0);
    }
    const t1 = performance.now();
    const L = HT.groupTreeLayout(m, { polityUid: sol.uid });
    const layMs = performance.now() - t1;
    T.close();
    m.groups = saved;
    for (const g of extra) m.byUid.delete(g.uid);
    HT.viewer.timeline.setView(1550, 1800);
    times.sort((a, b) => a - b);
    return { groups: L.nodes.length, median: +times[10].toFixed(2), max: +times[19].toFixed(2), layout: +layMs.toFixed(2) };
  });
  report.측정.성능 = perf;
  check(perf.groups === 131 && perf.median < 16, '성능 — 단체 131개 나무를 다시 그리기 한 번이 16ms 안(중앙값)', perf);

  /* ⑩ 법의 내력 · 의석 막대 (결정 7 A) — 법의 내력은 견본 2.0.0의 등좌 기본법(하연 연합 왕국: 1410 권리 장전 반포 제정 → 1580 보수 개정 · 폐지 없음).
     1.0.0의 '권리 장전 고침'(1520 개정)은 2.0.0에서 다른 법(전매법)의 제정이 되어 같은 꼴(제정 → 개정 → 폐지 기록 없음)인 이 개정으로 옮김 */
  const law = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    HT.viewer.openDetail(m.events.find(e => e.title === '등좌 기본법 보수 개정 (왕실 긴급재정권 신설)').uid);
    const d = document.querySelector('#detail');
    const rows = [...d.querySelectorAll('.law-history .tr-steps li')].map(li => ({ now: li.classList.contains('is-now'), text: li.textContent.replace(/\s+/g, ' ').trim(), btn: !!li.querySelector('button[data-uid]') }));
    return { rows, aka: [...d.querySelectorAll('.aka')].map(a => a.textContent), when: !!d.querySelector('.detail-body > .when'), arts: [...d.querySelectorAll('.tr-articles .tr-art')].map(a => a.textContent.replace(/\s+/g, ' ').trim()), rel: [...d.querySelectorAll('.tr-related li')].map(a => a.textContent.replace(/\s+/g, ' ').trim()) };
  });
  check(law.rows.length === 3 && /^제정 ?1410년 권리 장전 반포/.test(law.rows[0].text) && law.rows[0].btn && law.rows[1].now && /1580년 11월 12일 이 사건/.test(law.rows[1].text) && /171년 뒤/.test(law.rows[1].text) && /^폐지 ?기록 없음/.test(law.rows[2].text), "법의 내력 — 제정 → 개정(이 사건 · 171년 뒤 — 1410년에서 1580년 11월 12일) → '폐지 기록 없음' · 다른 줄은 누르면 그 사건", law.rows);
  check(law.aka.includes('법 이름 등좌 기본법') && !law.when, '법 이름 줄 · 기본 기간 줄 자리에 내력', law.aka);
  check(law.arts.length === 4 && /^제1조 \(국왕의 긴급재정처분권 신설\) /.test(law.arts[0]) && law.arts.every(a => / ?개정$/.test(a)) && law.rel.some(r => /^앞 고침 ?권리 장전 반포/.test(r)), '조항(번호 · 제목 · 개정 딱지) · 관련(앞 고침)', { arts: law.arts.map(a => a.slice(0, 30) + ' … ' + a.slice(-8)), rel: law.rel });
  await page.screenshot({ path: path.join(output, '법-내력-1920-1배.png') });
  const vote = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    HT.viewer.openDetail(m.events.find(e => e.title === '첫 양원 총선').uid);
    const d = document.querySelector('#detail');
    const segs = [...d.querySelectorAll('.el-bar .el-seg')].map(s => ({ w: s.getBoundingClientRect().width, tag: s.tagName, uid: s.dataset.uid || '' }));
    const bar = d.querySelector('.el-bar').getBoundingClientRect();
    const box = d.querySelector('.el-box').getBoundingClientRect();
    return { segs, inside: bar.left >= box.left && bar.right <= box.right, half: d.querySelector('.el-half').textContent, rows: d.querySelectorAll('.el-table tbody tr').length, won: d.querySelectorAll('.el-table tr.is-won').length, rel: [...d.querySelectorAll('.tr-related li')].map(a => a.textContent.replace(/\s+/g, ' ').trim()), badges: [...d.querySelectorAll('.badges .badge')].map(b => b.textContent), aka: [...d.querySelectorAll('.aka')].map(a => a.textContent) };
  });
  const sw = vote.segs.map(s => s.w);
  const ratio = (sw[0] + 2 / 3) / (sw[1] + 2 / 3); // 사이 틈 2px를 셈에서 뺀 비율이 71 : 59에 가까운지
  check(vote.segs.length === 3 && Math.abs(ratio - 71 / 59) < 0.05 && vote.inside && vote.half === '과반 69석 — 항로당 71석' && vote.rows === 3 && vote.won === 1, '의석 막대 — 모임마다 의석만큼 · 과반 글 · 결과 표', { sw, half: vote.half });
  check(vote.segs[0].tag === 'BUTTON' && vote.segs[0].uid && vote.segs[1].tag === 'BUTTON' && vote.segs[2].tag === 'I', "모임 이름이 단체 이름과 같으면(항로당 · 등불당) 막대 조각을 누르면 단체 창 — 아니면(무소속) 누를 수 없음", vote.segs);
  check(vote.badges.includes('선거 · 평민원') && vote.aka.includes('뽑은 자리 평민원'), '선거 딱지 · 뽑은 자리', { badges: vote.badges, rel: vote.rel });
  await page.screenshot({ path: path.join(output, '선거-의석-막대-1920-1배.png') });
  await page.locator('#detail .el-bar button.el-seg').first().click();
  await page.waitForTimeout(200);
  check((await page.evaluate(() => document.querySelector('#detail h2').textContent)) === '항로당', '의석 막대의 단체 조각 → 단체 창');
  const vote2 = await page.evaluate(() => {
    HT.viewer.openDetail(HT.viewer.state.model.events.find(e => e.title === '바울 미르의 첫 당선').uid);
    const d = document.querySelector('#detail');
    return { segs: d.querySelectorAll('.el-bar .el-seg').length, half: d.querySelector('.el-half').textContent, rel: [...d.querySelectorAll('.tr-related li')].map(a => a.textContent.replace(/\s+/g, ' ').trim()) };
  });
  check(vote2.segs === 2 && vote2.half === '가장 많은 표 — 바울 미르 (진주파) 59.7%' && vote2.rel.some(r => /^앞 선거 ?첫 도선장 선거/.test(r)) && vote2.rel.some(r => /^다음 선거 ?바울 미르의 세 번째 당선/.test(r)), '의석을 적지 않은 선거는 득표 막대 · 관련(앞 선거 · 다음 선거)', vote2);
  const repeal = await page.evaluate(() => {
    HT.viewer.openDetail(HT.viewer.state.model.events.find(e => e.title === '빛돌 전매법 폐지').uid);
    return [...document.querySelectorAll('#detail .law-history .tr-steps li')].map(li => li.textContent.replace(/\s+/g, ' ').trim());
  });
  check(repeal.length === 1 && /^폐지 ?1032년 이 사건/.test(repeal[0]), '폐지가 마지막이면 "기록 없음" 줄을 두지 않음', repeal);
  await page.evaluate(() => HT.viewer.closeDetail());
  check(report.오류.length === 0, '연표 — 페이지 오류 없음', report.오류);
  await view.close();

  /* ⑪ 메이커: 창이 메이커의 연표(#stage) 안에 붙고, 만든 단체로 열림 */
  const mk = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const maker = await mk.newPage();
  const mkErr = [];
  maker.on('pageerror', e => mkErr.push(e.message));
  await maker.goto(base + 'dlc-maker.html');
  await maker.locator('[data-start-new]').waitFor();
  await maker.locator('[data-start-new] [name="name"]').fill('가상 계보 확인');
  await maker.locator('[data-start-new] [name="id"]').fill('group-tree-maker-check');
  await maker.locator('[data-start-new] [name="how"][value="world"]').check();
  await maker.locator('[data-start-new] button[type="submit"]').click();
  await maker.waitForFunction(() => window.HT && HT.viewer && HT.viewer.maker && HT.viewer.maker.draft && document.querySelector('#mkStart').hidden);
  await maker.evaluate(() => HT.viewer.openEditor(null, 'period'));
  await maker.locator('#editorForm [name="name"]').fill('푸른 들 나라');
  await maker.evaluate(() => { const f = document.querySelector('#editorForm'); HT.writeDateField(f, 'start', 500); HT.writeDateField(f, 'end', 900); });
  await maker.evaluate(() => HT.viewer.saveEditor());
  await maker.evaluate(() => HT.viewer.openEditor(null, 'group'));
  await maker.locator('#editorForm [name="name"]').fill('들바람 모임');
  await maker.evaluate(() => { const f = document.querySelector('#editorForm'); HT.writeDateField(f, 'start', 600); HT.writeDateField(f, 'end', 700); });
  await maker.locator('#editorForm [data-gp-add="within"]').click();
  await maker.locator('#editorForm [data-gp-within] .s-from').fill('푸른 들 나라');
  await maker.locator('#editorForm [data-gp-add="power"]').click();
  await maker.locator('#editorForm [data-gp-power] .c-name').fill('집권');
  await maker.locator('#editorForm [data-gp-power] .c-start').fill('620');
  await maker.locator('#editorForm [data-gp-power] .c-end').fill('640');
  await maker.evaluate(() => HT.viewer.saveEditor());
  const mres = await maker.evaluate(async () => {
    const g = HT.viewer.state.model.groups.find(q => q.name === '들바람 모임');
    const ok = HT.viewer.groupTree.open({ groupUid: g.uid });
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    const t = document.querySelector('#groupTree');
    return { ok, inStage: t.parentElement.id === 'stage', bars: t.querySelectorAll('.gt-bar').length, segs: t.querySelectorAll('.gt-seg').length, shown: !t.hidden };
  });
  check(mres.ok && mres.inStage && mres.shown && mres.bars === 1 && mres.segs === 1, '메이커 — 창이 메이커의 연표(#stage) 안에 붙고 만든 단체 · 집권 칸으로 열림', mres);
  await maker.screenshot({ path: path.join(output, '메이커-단체-계보-1920-1배.png') });
  check(mkErr.length === 0, '메이커 — 페이지 오류 없음', mkErr);
  await mk.close();
} finally {
  await browser.close();
  server.close();
  fs.writeFileSync(path.join(output, '검사.json'), JSON.stringify(report, null, 2) + '\n');
}
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류, 측정: report.측정, 결과: output }));

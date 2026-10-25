/* 건의 8의 6 — 같은 사람이 두 자리 이상(다른 나라 · 같은 나라 복위)을 가진 지도자 칸의 실제 브라우저 검사 (js/viewer.js seatsHTML · js/timeline.js _sameHover · css)
   ① 6-가 한 사람의 창: 배지 '인물' + 가문 · 확실성(나라 · 트랙 · 지도자 · 제n대 · 지위 배지 없음) · 제목 아래 모든 자리를 합친 기간 · '자리 N' 상자
      (시작 순 · 지금 자리는 왼쪽 3px 먹 막대 + 옅은 바탕 · 첫 줄 '나라 지도자 · n대' + 연도만 기간 · 둘째 줄 '앞 ○○ …') · 겹친 기간 한 줄 + 자리마다 가는 막대(폭 ≤ 180) ·
      혈연 줄은 '가족' 묶음 안 · 옛 '같은 사람의 다른 칸' 줄 없음 · 다른 자리를 누르면 그 나라의 그 칸(표시가 옮겨 감) · 자리가 하나뿐인 칸의 창은 예전 그대로 ·
      자리 줄 글자의 위아래 틈(줄 사이 선 · 상자 테에 닿지 않음 — 1배)
   ② 6-나 같은 사람 테: 지도자 칸에 올리면 같은 사람의 모든 칸(그 칸 자신 포함)에 먹 1.5px 테 · 둥근 6 · 바탕은 그대로, 내려오면 없어짐 · 자리 하나뿐인 칸은 그대로 ·
      칸을 고르면(창을 열면 — 조명) 올리지 않아도 테 · 그 칸이 든 나라(띠)는 흐리지 않음(1 — 띠 안의 다른 칸은 .45 · 짝 칸은 1, 같은 나라의 복위 칸도 1) ·
      올리기만 할 때는 흐림 없이 테만 · 창을 닫으면 없어짐 · 그림 내보내기(SVG)에는 없음
   node scripts/same-person-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge)
   자료는 가상 나라 · 가상 사람만(이 검사 안에서 지음), 따로 띄운 브라우저의 메모리에만 둡니다. 1920×1080 · 1배 화면 그림을 결과 폴더에 남깁니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/같은-사람-검사');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.webmanifest': 'application/manifest+json' };
const server = http.createServer((req, res) => {
  try {
    const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(fs.readFileSync(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
const report = { 화면: '1920×1080 · 100% · 1배', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };

/* 가상 팩: 해 둘째 임금은 세 자리 — 해 나라 2대(1420~1440) · 달 나라 2대(1435~1445 — 해 나라와 5년 겹침) · 해 나라 4대(1450~1470 — 복위) */
const PID = 'sp-check';
const SAME = '해 나라:해 둘째 임금@1420';
const PACK = {
  format: 'history-timeline-dlc', formatVersion: 3, version: '1.0.0', id: PID, name: '같은 사람 검사',
  tracks: [{ id: 'sp-a', name: '가상 해 들', color: '#c8b193' }, { id: 'sp-b', name: '가상 달 들', color: '#a0bcc5' }],
  periods: [
    {
      id: 'sun', track: 'sp-a', name: '해 나라', start: 1400, end: 1500,
      leaders: [
        { name: '해 첫 임금', start: 1400, end: 1420, ordinal: 1 },
        { name: '해 둘째 임금', start: 1420, end: 1440, ordinal: 2, accession: { kin: '아들', how: '세습' }, parents: [{ who: '해 나라:해 첫 임금@1400', as: '부' }] },
        { name: '해 셋째 임금', start: 1440, end: 1450, ordinal: 3, accession: { kin: '동생', how: '찬탈' } },
        { name: '해 둘째 임금', start: 1450, end: 1470, ordinal: 4, person: SAME, accession: { kin: '형', how: '복위' } },
        { name: '해 다섯째 임금', start: 1470, end: 1500, ordinal: 5, accession: { kin: '아들', how: '세습' } },
      ],
    },
    {
      id: 'moon', track: 'sp-b', name: '달 나라', start: 1430, end: 1480,
      leaders: [
        { name: '달 첫 임금', start: 1430, end: 1435, ordinal: 1 },
        { name: '해 둘째 임금', start: 1435, end: 1445, ordinal: 2, person: SAME, accession: { kin: '무관', how: '정복' } },
        { name: '달 셋째 임금', start: 1445, end: 1480, ordinal: 3 },
      ],
    },
  ],
};
const U = id => `${PID}/${id}`;
try {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block', colorScheme: 'light' });
  await context.addInitScript(packs => {
    if (sessionStorage.getItem('sp-seeded')) return;
    sessionStorage.setItem('sp-seeded', '1');
    localStorage.clear();
    localStorage.setItem('ht.packs.installed', JSON.stringify(packs));
  }, [PACK]);
  const page = await context.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  page.on('console', m => m.type() === 'error' && !/Service Worker|서비스 워커/.test(m.text()) && report.오류.push(m.text()));
  await page.goto(base + 'index.html');
  await page.waitForFunction(id => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.byUid.has(id), U('moon'), { timeout: 120000 });
  await page.evaluate(() => document.fonts.ready);
  const win = () =>
    page.evaluate(() => {
      const d = document.querySelector('#detail');
      return {
        badges: [...d.querySelectorAll('.detail-head .badges > *')].map(b => b.textContent.trim()),
        title: d.querySelector('h2').textContent,
        when: d.querySelector('.when').textContent,
        head: (d.querySelector('.seats h3') || {}).innerText || '',
        seats: [...d.querySelectorAll('.seat-list > li')].map(li => ({ text: li.innerText.replace(/\s+/g, ' ').trim(), here: li.classList.contains('is-here'), bar: getComputedStyle(li).boxShadow, bg: getComputedStyle(li).backgroundColor })),
        ov: ((d.querySelector('.seat-ov') || {}).innerText || '').replace(/\s+/g, ' ').trim(),
        bars: [...d.querySelectorAll('.seat-bars i')].map(i => { const r = i.getBoundingClientRect(); return { x: r.x, w: r.width, h: r.height, y: r.y }; }),
        barsW: (b => (b ? b.getBoundingClientRect().width : 0))(d.querySelector('.seat-bars')),
        kin: [...d.querySelectorAll('.seat-kin h3, .seat-kin .kin-line')].map(e => e.textContent.trim()),
        text: d.innerText,
        lineage: (d.querySelector('.lineage-line') || {}).textContent || '',
      };
    });

  /* ① 한 사람의 창 */
  await page.evaluate(u => HT.viewer.openDetail(u, { cell: 'leader:1' }), U('sun'));
  await page.waitForTimeout(300);
  const w1 = await win();
  check(w1.badges[0] === '인물' && !w1.badges.some(b => /해 나라|가상 해 들|지도자|지위/.test(b)), "배지: '인물'(나라 · 트랙 · 지도자 · 제n대 · 지위 배지 대신)", w1.badges);
  check(w1.title === '해 둘째 임금' && w1.when === '1420년 ~ 1470년', '제목 아래 기간 = 모든 자리를 합친 기간(가장 이른 시작 ~ 가장 늦은 끝)', { title: w1.title, when: w1.when });
  check(w1.head === '자리 3' && w1.seats.length === 3, "묶음 '자리 3'", w1.head);
  check(/^해 나라 지도자 · 2대 1420 ~ 1440 앞 해 첫 임금의 아들 · 세습$/.test(w1.seats[0].text) && /^달 나라 지도자 · 2대 1435 ~ 1445 앞 달 첫 임금 · 혈연 없음 · 정복$/.test(w1.seats[1].text) && /^해 나라 지도자 · 4대 1450 ~ 1470 앞 해 셋째 임금의 형 · 복위$/.test(w1.seats[2].text), "자리 줄: 시작 순 · '나라 지도자 · n대' + 연도만 기간 · 둘째 줄 '앞 ○○ …'", w1.seats.map(s => s.text));
  check(w1.seats[0].here && !w1.seats[1].here && !w1.seats[2].here && /rgb\(0, 0, 0\) 3px 0px 0px 0px inset/.test(w1.seats[0].bar) && w1.seats[0].bg !== 'rgba(0, 0, 0, 0)', '지금 누른 자리: 왼쪽 3px 먹 막대 + 옅은 바탕', w1.seats[0]);
  check(w1.ov === '겹친 기간 1435 ~ 1440 · 5년' && w1.bars.length === 3 && w1.barsW <= 180 && w1.bars.every(b => Math.round(b.h) === 4), "겹친 기간 한 줄 + 자리마다 가는 막대(높이 4 · 폭 ≤ 180)", { ov: w1.ov, bars: w1.bars, w: w1.barsW });
  check(w1.bars[1].x > w1.bars[0].x && w1.bars[2].x > w1.bars[1].x && w1.bars[1].y - w1.bars[0].y === 6, '막대는 합친 기간 안의 비례 자리 · 막대 사이 2px', w1.bars);
  check(w1.kin[0] === '가족' && w1.kin.includes('부모 · 조상: 부 해 첫 임금') && !/같은 사람의 다른 칸/.test(w1.text) && !w1.lineage, "혈연 줄은 '가족' 묶음 안 · 옛 '같은 사람의 다른 칸' · 자리 이음 줄 없음", w1.kin);
  /* 자리 줄 글자의 위아래 틈 — 줄 사이 선(li 위 테) · 상자 테와 글자 상자 사이 ≥ 1px (1배) */
  const gaps = await page.evaluate(() =>
    [...document.querySelectorAll('#detail .seat-list > li')].map(li => {
      const r = li.getBoundingClientRect();
      const rg = document.createRange();
      rg.selectNodeContents(li);
      const rs = [...rg.getClientRects()].filter(x => x.width > 0 && x.height > 0);
      const top = Math.min(...rs.map(x => x.top));
      const bottom = Math.max(...rs.map(x => x.bottom));
      return { above: Math.round((top - r.top - 1) * 10) / 10, below: Math.round((r.bottom - bottom - 1) * 10) / 10 };
    })
  );
  check(gaps.every(g => g.above >= 1 && g.below >= 1), '자리 줄 글자의 위아래 틈 ≥ 1px (줄 사이 선 · 상자 테에 닿지 않음)', gaps);
  const det = await page.evaluate(() => { const r = document.querySelector('#detail').getBoundingClientRect(); return { x: Math.floor(r.x), y: Math.floor(r.y), width: Math.ceil(r.width), height: Math.ceil(r.height) }; });
  await page.screenshot({ path: path.join(output, '한-사람-창-1920-1배.png'), clip: det });
  /* 다른 자리를 누르면 그 나라의 그 칸 — 같은 꼴의 창 · 표시가 옮겨 감 */
  await page.click('#detail .seat-list > li:nth-child(2) .seat-go');
  await page.waitForTimeout(300);
  const w2 = await win();
  const sel2 = await page.evaluate(() => [HT.viewer.state.selected, HT.viewer.timeline.spot && HT.viewer.timeline.spot.cell]);
  check(sel2[0] === U('moon') && sel2[1] === 'leader:1' && w2.title === '해 둘째 임금' && w2.seats.map(s => s.here).join() === 'false,true,false', '다른 나라의 자리를 누르면 그 나라의 그 칸(같은 꼴의 창 · 표시가 둘째 줄로)', { sel2, here: w2.seats.map(s => s.here) });
  await page.click('#detail .seat-list > li:nth-child(3) .seat-go');
  await page.waitForTimeout(300);
  const w3 = await win();
  const sel3 = await page.evaluate(() => [HT.viewer.state.selected, HT.viewer.timeline.spot && HT.viewer.timeline.spot.cell]);
  check(sel3[0] === U('sun') && sel3[1] === 'leader:3' && w3.seats.map(s => s.here).join() === 'false,false,true', '같은 나라의 복위 자리를 누르면 그 칸(표시가 셋째 줄로)', { sel3 });
  /* 자리가 하나뿐인 칸은 예전 그대로 */
  await page.evaluate(u => HT.viewer.openDetail(u, { cell: 'leader:2' }), U('sun'));
  await page.waitForTimeout(300);
  const w4 = await win();
  check(!w4.seats.length && w4.badges.some(b => b === '해 나라') && /지도자 · 제3대/.test(w4.badges.join(' ')) && w4.lineage === '앞 지도자 해 둘째 임금의 동생 · 찬탈', '자리가 하나뿐인 칸의 창은 예전 그대로(나라 · 지도자 · 제n대 배지 · 자리 이음 줄)', { badges: w4.badges, lineage: w4.lineage });
  await page.evaluate(() => HT.viewer.closeDetail());
  await page.waitForTimeout(300);

  /* ② 같은 사람 테 */
  await page.evaluate(() => HT.viewer.timeline.setView(1395, 1505));
  await page.waitForTimeout(600);
  const cellAt = (uid, ref) =>
    page.evaluate(([u, r]) => {
      const c = document.querySelector(`.tl-band[data-uid="${CSS.escape(u)}"] .tl-cell[data-cell="${r}"]`);
      if (!c) return null;
      c.scrollIntoView({ block: 'center' });
      const b = c.getBoundingClientRect();
      return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
    }, [uid, ref]);
  const same = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('.tl-band .tl-cell.is-same')].map(e => {
        const cs = getComputedStyle(e);
        return { k: `${e.closest('.tl-band').dataset.uid.split('/').pop()}|${e.dataset.cell}`, border: `${cs.borderTopColor} ${cs.borderTopWidth}`, shadow: cs.boxShadow, radius: cs.borderTopLeftRadius, bg: cs.backgroundColor };
      })
    );
  const bgOf = (uid, ref) => page.evaluate(([u, r]) => getComputedStyle(document.querySelector(`.tl-band[data-uid="${CSS.escape(u)}"] .tl-cell[data-cell="${r}"]`)).backgroundColor, [uid, ref]);
  const moonBg = await bgOf(U('moon'), 'leader:1');
  const p1 = await cellAt(U('sun'), 'leader:1');
  check(!!p1, '연표에 해 나라 2대 칸', p1);
  await page.mouse.move(p1.x, p1.y);
  await page.waitForTimeout(250);
  const s1 = await same();
  check(s1.map(s => s.k).sort().join() === 'moon|leader:1,sun|leader:1,sun|leader:3', '지도자 칸에 올리면 같은 사람의 모든 칸(다른 나라 · 같은 나라 복위 · 그 칸 자신)에 테', s1.map(s => s.k));
  check(s1.every(s => s.border === 'rgb(0, 0, 0) 1px' && /rgb\(0, 0, 0\) 0px 0px 0px 0.5px inset/.test(s.shadow) && s.radius === '6px'), '테: 먹 1.5px(테 1 + 안쪽 .5) · 둥근 6', s1);
  check((await bgOf(U('moon'), 'leader:1')) === moonBg, '다른 자리 칸의 바탕은 그대로', { moonBg });
  const hov = await page.evaluate(() => ({ picked: document.querySelector('.tl').classList.contains('is-picked'), sel: document.querySelectorAll('.tl-cell.is-same-sel').length }));
  check(!hov.picked && hov.sel === 0, '올리기만 할 때는 흐림 없이 테만(고름 표시 없음)', hov);
  await page.screenshot({ path: path.join(output, '같은-사람-테-올림-1920-1배.png') });
  const p0 = await cellAt(U('sun'), 'leader:0');
  await page.mouse.move(p0.x, p0.y);
  await page.waitForTimeout(250);
  check((await same()).length === 0, '자리가 하나뿐인 칸에 올리면 테 없음(그대로)');
  await page.mouse.move(5, 1075);
  await page.waitForTimeout(250);
  check((await same()).length === 0, '내려오면 테가 없어짐');
  /* 고르면(창 · 조명) 올리지 않아도 */
  await page.evaluate(u => HT.viewer.openDetail(u, { cell: 'leader:1' }), U('moon'));
  await page.waitForTimeout(400);
  const s2 = await same();
  check(s2.map(s => s.k).sort().join() === 'moon|leader:1,sun|leader:1,sun|leader:3', '칸을 고르면(창을 열면) 같은 사람의 모든 칸에 테', s2.map(s => s.k));
  const ops = await page.evaluate(([sun, moon]) => {
    const band = u => document.querySelector(`.tl-band[data-uid="${CSS.escape(u)}"]`);
    const cell = (u, r) => band(u).querySelector(`.tl-cell[data-cell="${r}"]`);
    const o = e => getComputedStyle(e).opacity;
    const tab = u => document.querySelector(`.tl-tab[data-k^="tab:${CSS.escape(u)}"]`);
    return { picked: document.querySelector('.tl').classList.contains('is-picked'), sunTab: tab(sun) ? o(tab(sun)) : '', sunBand: o(band(sun)), sunPair: o(cell(sun, 'leader:1')), sunOther: o(cell(sun, 'leader:0')), sunAgain: o(cell(sun, 'leader:3')), moonPair: o(cell(moon, 'leader:1')), moonOther: o(cell(moon, 'leader:0')) };
  }, [U('sun'), U('moon')]);
  check(ops.picked && ops.sunBand === '1' && ops.sunTab === '1' && ops.sunPair === '1' && ops.sunOther === ops.moonOther && Number(ops.sunOther) < 1, '고른 동안 같은 사람의 칸이 든 나라(띠)는 흐리지 않음(1) — 그 띠 안의 다른 칸은 고른 띠 안의 칸과 같은 흐림 · 짝 칸은 1', ops);
  check(ops.moonPair === '1' && ops.sunAgain === '1', '고른 칸 자신 · 같은 나라의 짝 칸도 흐림에서 빠짐(1)', ops);
  await page.screenshot({ path: path.join(output, '같은-사람-테-고름-1920-1배.png') });
  const svg = await page.evaluate(() => (HT.viewer.timeline.toSVG ? HT.viewer.timeline.toSVG({ width: 1200 }) : ''));
  check(typeof svg === 'string' && !/is-same/.test(svg), '그림 내보내기(SVG)에는 같은 사람 테가 없음(화면 상태)');
  await page.evaluate(() => HT.viewer.closeDetail());
  await page.waitForTimeout(300);
  check((await same()).length === 0, '창을 닫으면 테가 없어짐');
  await context.close();
} catch (e) {
  report.실패 = String(e && e.stack ? e.stack : e);
} finally {
  await browser.close();
  server.close();
  fs.writeFileSync(path.join(output, '검사-결과.json'), JSON.stringify(report, null, 2));
}
if (report.실패) {
  console.log(report.실패);
  console.log(`오류: ${JSON.stringify(report.오류)}`);
  process.exit(1);
}
console.log(`같은 사람 검사 ${report.검사.length} · 오류 ${JSON.stringify(report.오류)}`);
process.exit(report.오류.length ? 1 : 0);

/* 메이커 편집 범위 전역 확대(2026-10-23 — "dlc maker로 못 변경하는 부분이 없도록")를 실제 브라우저의 메이커에서 확인합니다.
   node scripts/maker-fields-check.mjs <검사할 폴더> <결과 폴더>   (크로미움은 HT_BROWSER(기본 msedge) · Playwright는 HT_PLAYWRIGHT_ROOT로 — 다른 브라우저 검사와 같게)
   가상 작업본(안개 섬 · 재 줄 트랙 둘 · 안개국 · 재국 · 사건 하나 · 판 하나 · 그림 하나 · 덮어쓰기 하나 · 관계 하나)을 독립 브라우저의 저장소에만 넣고:
   ① 바탕 자료 「트랙」 표의 설명 열  ② 도읍 줄의 천도 사건 칸(폼 · 하위 표 열 · 붙여넣기 머리글)  ③ 칸 줄의 미정 옆 배치용 연도 칸
   ④ 집합 보기 고치기 폼의 색 · 설명 · 메모 · 보기 설정 · 이름 목록  ⑤ 「지도」 표(바탕 칸 · JSON 칸 · 구역 · 장면 하위 표)  ⑥ 「글꼴」 표  ⑦ 그림 모음의 이름 바꾸기(문서 고리 따라감)
   ⑧ 「영토」 표(객체 하나)  ⑨ 덮어쓰기 표의 메모 열 · 사건 폼의 정권 칸  ⑩ 팩 정보의 처음 만든 날 · 판 기록 줄 더하기 · 관계의 보일 이름 — 그리고 1배 그림 · 콘솔 오류 없음 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/메이커-전역-검사');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const report = { 화면: '1920×1080 · 100%', 검사: [], 오류: [] };
const check = (ok, text, details) => { report.검사.push({ 검사: text, 결과: !!ok, ...(details !== undefined ? { 자세히: details } : {}) }); if (!ok) report.오류.push(text + (details !== undefined ? ' ' + JSON.stringify(details) : '')); };

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
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const draft = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'smoke-world', name: '검사 세계', version: '1.0.0',
  tracks: [{ id: 'fog-isles', name: '안개 섬', color: '#88aacc' }, { id: 'ash-row', name: '재 줄', color: '#ccaa88' }],
  periods: [{ id: 'p1', track: 'fog-isles', name: '안개국', start: 100, end: 300 }, { id: 'p2', track: 'ash-row', name: '재국', start: 100, end: 300 }],
  events: [{ id: 'e1', track: 'fog-isles', title: '안개 나루 천도', start: 150 }],
  views: [{ id: 'v-two', name: '두 땅 견주기', members: ['fog-isles:안개국', 'ash-row:재국'] }],
  images: [{ id: 'img-naru', name: '안개 나루.png', src: PNG, width: 1, height: 1 }],
  documents: { p1: '== 나루 ==\n[[파일:안개 나루.png]]\n나루의 그림.' },
  patches: [{ target: 'other-pack/x-1', set: { start: 120 } }],
  relations: [{ type: 'after', id: 'other-pack' }],
};
await context.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d)); localStorage.setItem('ht.maker.ui', JSON.stringify({})); }, draft);
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
const shot = name => page.screenshot({ path: path.join(output, name) });
try {
  await page.goto(base + 'dlc-maker.html');
  await page.locator('#mkMenus [data-menu="insert"]').waitFor({ timeout: 20000 });
  await page.waitForTimeout(800);
  const stored = () => page.evaluate(() => JSON.parse(localStorage.getItem('ht.maker.draft') || 'null'));
  const openTab = async tab => { await page.evaluate(t => HT.viewer.maker.openBase(t, -1, true), tab); await page.waitForTimeout(400); };
  const table = tab => page.locator(`#mkBaseBody table[data-list="${tab}"]`);

  /* ① 트랙 설명 */
  await openTab('tracks');
  const desc = table('tracks').locator('tr[data-i="0"] input[name="description"]');
  check(await desc.count() === 1, '① 바탕 자료 「트랙」 표에 설명 열');
  await desc.fill('안개가 걷히지 않는 섬');
  await page.waitForTimeout(700);
  let d = await stored();
  check(d.tracks[0].description === '안개가 걷히지 않는 섬', '① 트랙 설명이 작업본에 실림', d.tracks[0]);
  await shot('1-트랙-설명.png');

  /* ⑤ 지도 */
  await openTab('maps');
  await page.locator('#mkBaseBody [data-act="add"]').click();
  await page.waitForTimeout(400);
  const mrow = table('maps').locator('tr[data-i="0"]');
  await mrow.locator('input[name="name"]').fill('안개섬 지도');
  await mrow.locator('input[name="size"]').fill('48, 32');
  await mrow.locator('input[name="levels"]').fill('["주", "군"');
  await page.waitForTimeout(500);
  const badJson = await mrow.locator('input[name="levels"]').getAttribute('aria-invalid');
  await mrow.locator('input[name="levels"]').fill('["주", "군"]');
  await mrow.locator('input[name="places"]').fill('안개 나루, 재 포구');
  await page.waitForTimeout(700);
  d = await stored();
  const m = d.maps && d.maps[0];
  check(badJson === 'true' && m && m.name === '안개섬 지도' && Array.isArray(m.size) && m.size[0] === 48 && Array.isArray(m.levels) && m.levels[1] === '군' && m.places.length === 2, '⑤ 지도 줄의 이름 · 크기 · 행정 층위(JSON — 잘못된 글은 붉게만) · 지명이 작업본에 실림', m);
  await mrow.locator('[data-act="sub"][data-sub="regions"]').click();
  await page.waitForTimeout(300);
  await page.locator('[data-base-sub="0"][data-sub-key="regions"] [data-sub-add]').click();
  await page.waitForTimeout(300);
  const rrow = page.locator('[data-base-sub="0"][data-sub-key="regions"] tr[data-j="0"]');
  await rrow.locator('input[name="id"]').fill('north');
  await rrow.locator('input[name="name"]').fill('곶마루주');
  await rrow.locator('input[name="level"]').fill('주');
  await rrow.locator('input[name="shape"]').fill('[[4, 2], [44, 2], [44, 16], [4, 16]]');
  await page.waitForTimeout(700);
  await table('maps').locator('tr[data-i="0"] [data-act="sub"][data-sub="frames"]').click();
  await page.waitForTimeout(300);
  await page.locator('[data-base-sub="0"][data-sub-key="frames"] [data-sub-add]').click();
  await page.waitForTimeout(300);
  const frow = page.locator('[data-base-sub="0"][data-sub-key="frames"] tr[data-j="0"]');
  await frow.locator('input[name="year"]').fill('400');
  await frow.locator('input[name="owners"]').fill('{ "north": "안개국" }');
  await page.waitForTimeout(700);
  d = await stored();
  const mm = d.maps[0];
  check(mm.regions && mm.regions[0].id === 'north' && mm.regions[0].shape.length === 4 && mm.frames && mm.frames[0].year === '400' && mm.frames[0].owners.north === '안개국', '⑤ 구역 · 장면 하위 표의 줄이 작업본에 실림', { regions: mm.regions, frames: mm.frames });
  const mapFile = await page.evaluate(() => { const d = JSON.parse(localStorage.getItem('ht.maker.draft')); const r = HT.normalizePack(d); const j = HT.packToJSON(r.pack); return { v: j.formatVersion, map: j.maps && j.maps[0] && { regions: j.maps[0].regions.length, frames: j.maps[0].frames.length, levels: j.maps[0].levels.length }, errors: r.errors ? r.errors.map(e => e.msg) : [] }; });
  check(mapFile.v === 3 && mapFile.map && mapFile.map.regions === 1 && mapFile.map.frames === 1 && mapFile.map.levels === 2, '⑤ 파일로 낼 때 지도(구역 1 · 장면 1 · 층위 2) · 형식 버전 3', mapFile);
  await shot('5-지도.png');

  /* ⑥ 글꼴 */
  await openTab('fonts');
  await page.locator('#mkBaseBody [data-act="add"]').click();
  await page.waitForTimeout(400);
  const frow2 = table('fonts').locator('tr[data-i="0"]');
  check(await frow2.locator('[data-act="file"]').count() === 1 && (await frow2.locator('input[name="family"]').getAttribute('aria-invalid')) === 'true', '⑥ 글꼴 줄에 [파일] 단추 · 비운 줄은 빠지는 줄 표시');
  await frow2.locator('input[name="family"]').fill('달글씨');
  await frow2.locator('input[name="license"]').fill('만든 사람이 적은 이용 조건');
  await frow2.locator('input[name="scripts"]').fill('Qaaa');
  await frow2.locator('input[name="ranges"]').fill('U+F1A00-F1A0B');
  await page.waitForTimeout(700);
  d = await stored();
  check(d.fonts && d.fonts[0].family === '달글씨' && d.fonts[0].license && d.fonts[0].scripts[0] === 'Qaaa' && d.fonts[0].ranges[0] === 'U+F1A00-F1A0B', '⑥ 글꼴 줄의 이름 · 라이선스 · 문자 · 범위가 작업본에 실림', d.fonts && d.fonts[0]);
  await shot('6-글꼴.png');

  /* ⑧ 영토 */
  await openTab('territory');
  await page.locator('#mkBaseBody [data-act="add"]').click();
  await page.waitForTimeout(400);
  const trow = table('territory').locator('tr[data-i="0"]');
  await trow.locator('input[name="basemap"]').fill('east-asia-v3');
  await trow.locator('input[name="ownership"]').fill('{ "KOR-2306": [[1392, 1897, "korea:조선"]] }');
  await page.waitForTimeout(700);
  d = await stored();
  check(d.territory && d.territory.basemap === 'east-asia-v3' && d.territory.ownership && d.territory.ownership['KOR-2306'][0][2] === 'korea:조선' && (await page.locator('#mkBaseBody [data-act="add"]').count()) === 0, '⑧ 영토(객체 하나)의 지형 팩 · 소유 기록(JSON)이 작업본에 실리고 추가 단추는 숨음', d.territory);
  await shot('8-영토.png');
  page.once('dialog', dlg => dlg.accept());
  await trow.locator('[data-act="del"]').click();
  await page.waitForTimeout(600);
  d = await stored();
  check(!d.territory, '⑧ 영토 줄을 지우면 통째로 없어짐');

  /* ② 도읍 줄의 천도 사건 · ③ 배치용 연도 칸 · ⑨ 사건 폼의 정권 칸 (폼 조각을 몸통에 붙여 읽기) */
  const forms = await page.evaluate(async () => {
    const out = {};
    const host = document.createElement('form');
    host.innerHTML = `<div data-cells="capitals">${HT.cellRowHTML('capitals', { city: '안개성', start: 100, event: 'e1' })}</div><div data-cells="leaders">${HT.cellRowHTML('leaders', { name: '첫 임금', startUnknown: true, start: 120, end: 160 })}</div>`;
    document.body.append(host);
    await new Promise(r => setTimeout(r, 50));
    out.capEvent = HT.readCellRows(host, 'capitals', '도읍', [])[0].event;
    out.capInput = !!host.querySelector('.c-event[list="mkEventList"]');
    out.gridCols = HT.makerGrid.columns({ list: 'periods', sub: 'capitals', parent: 'p1' }).map(c => c.key);
    out.pasteField = (HT.makerPaste.FIELDS ? HT.makerPaste.FIELDS.capitals : []).some(f => f.key === 'event');
    const lrow = host.querySelector('[data-cells="leaders"] .cell-row');
    const hint = lrow.querySelector('.c-hint[data-hint-for="start"]');
    out.hintShown = !!hint && hint.value === '120';
    if (hint) { hint.value = '150'; hint.dispatchEvent(new Event('input', { bubbles: true })); }
    const read1 = HT.readCellRows(host, 'leaders', '지도자', [])[0];
    out.hintRead = read1.startUnknown === true && read1.start === 150;
    const cs = lrow.querySelector('.c-start');
    cs.value = '110'; cs.dispatchEvent(new Event('input', { bubbles: true }));
    out.hintGone = !lrow.querySelector('.c-hint');
    const ce = lrow.querySelector('.c-end');
    ce.value = '미정'; ce.dispatchEvent(new Event('input', { bubbles: true }));
    const eh = lrow.querySelector('.c-hint[data-hint-for="end"]');
    out.endHintShown = !!eh;
    if (eh) { eh.value = '-57'; eh.dispatchEvent(new Event('input', { bubbles: true })); }
    const read2 = HT.readCellRows(host, 'leaders', '지도자', [])[0];
    out.endHintRead = read2.endUnknown === true && read2.end === -57 && read2.start === 110;
    host.remove();
    const ef = document.createElement('form');
    ef.innerHTML = HT.eventFieldsHTML({ tracks: [{ id: 'fog-isles', name: '안개 섬' }], categories: [] });
    document.body.append(ef);
    HT.fillEventForm(ef, { title: '큰불', start: 200, track: 'fog-isles', polity: '안개국', importance: 2 });
    out.polityFilled = ef.elements.polity && ef.elements.polity.value === '안개국';
    ef.elements.polity.value = '재국';
    out.polityRead = HT.readEventForm(ef).event.polity === '재국';
    ef.remove();
    return out;
  });
  check(forms.capInput && forms.capEvent === 'e1' && forms.gridCols.includes('event') && forms.pasteField, '② 도읍 줄의 천도 사건 칸(폼 · 하위 표 열 · 붙여넣기 머리글)', forms);
  check(forms.hintShown && forms.hintRead && forms.hintGone && forms.endHintShown && forms.endHintRead, '③ 미정 옆 배치용 연도 칸 — 보이고 · 읽히고 · 미정을 지우면 사라짐 · 끝 칸(기원전)도', forms);
  check(forms.polityFilled && forms.polityRead, '⑨ 사건 폼의 정권 칸이 채워지고 읽힘', forms);

  /* ⑨ 덮어쓰기 표의 메모 열 */
  const patchNote = await page.evaluate(() => {
    const cols = HT.makerGrid.columns({ list: 'patches' });
    const d = JSON.parse(localStorage.getItem('ht.maker.draft'));
    const r = HT.makerGrid.plan(d, { list: 'patches' }, [{ row: 0, key: 'note', text: '청동기 문화 시작 근거' }]);
    return { cols: cols.map(c => `${c.key}:${c.type}`), note: r.draft.patches[0].note, errors: r.errors };
  });
  check(patchNote.cols.includes('note:text') && patchNote.note === '청동기 문화 시작 근거' && !patchNote.errors.length, '⑨ 덮어쓰기 표의 메모 열을 고칠 수 있음', patchNote);

  /* ④ 집합 보기 고치기 폼 */
  await page.locator('#viewsBtn').click();
  await page.waitForTimeout(400);
  await page.locator('#viewsPop [data-vw-edit="v-two"]').click();
  await page.waitForTimeout(400);
  const vf = page.locator('#viewsPop [data-vw-form]');
  check((await vf.locator('select[name="density"]').count()) === 1 && (await vf.locator('select[name="show:leaders"]').count()) === 1 && (await vf.locator('[data-vw-names]').count()) === 1, '④ 판 고치기 폼에 밀도 · 표시 체크 · 이름 목록 칸');
  await vf.locator('input[name="note"]').fill('두 땅을 나란히');
  await vf.locator('textarea[name="description"]').fill('안개국과 재국을 한 판에');
  await vf.locator('select[name="density"]').selectOption('1');
  await vf.locator('select[name="show:leaders"]').selectOption('1');
  await vf.locator('select[name="show:figures"]').selectOption('0');
  await vf.locator('details.vw-names summary').click(); // 이름 목록은 접혀 있음(아직 없을 때)
  await page.waitForTimeout(150);
  await vf.locator('[data-vw-name-add]').click();
  await page.waitForTimeout(200);
  await vf.locator('[data-vw-names] .name-row .x-text').last().fill('Two Lands');
  await vf.locator('[data-vw-names] .name-row .x-lang').last().fill('en');
  await shot('4-집합보기-폼.png');
  await vf.locator('button[type="submit"]').click();
  await page.waitForTimeout(900);
  d = await stored();
  const v = d.views[0];
  check(v && v.note === '두 땅을 나란히' && v.description === '안개국과 재국을 한 판에' && v.settings && v.settings.density === 1 && v.settings.show && v.settings.show.leaders === true && v.settings.show.figures === false && v.names && v.names[0].text === 'Two Lands' && v.names[0].lang === 'en', '④ 판의 메모 · 설명 · 보기 설정(밀도 · 표시 체크) · 이름 목록이 작업본에 실림', v);
  await page.keyboard.press('Escape');

  /* ⑦ 그림 모음 — 이름 바꾸기(문서 고리 따라감) */
  await page.evaluate(() => HT.makerImages.openGallery({ maker: HT.viewer.maker, esc: HT.escapeHtml }));
  await page.waitForTimeout(400);
  const grow = page.locator('.mk-img-dlg [data-img-row="img-naru"]');
  check((await grow.locator('input[data-k="name"]').count()) === 1 && (await grow.locator('[data-img-swap]').count()) === 1, '⑦ 그림 모음에 이름 · id 칸과 바꿔 끼우기 단추');
  await grow.locator('input[data-k="name"]').fill('나루 그림.png');
  await shot('7-그림-모음.png');
  await page.locator('.mk-img-dlg [data-img-save]').click();
  await page.waitForTimeout(900);
  d = await stored();
  check(d.images[0].name === '나루 그림.png' && /\[\[파일:나루 그림\.png\]\]/.test(d.documents.p1), '⑦ 그림 이름을 바꾸면 문서의 [[파일:…]] 고리도 따라 바뀜', { name: d.images[0].name, doc: d.documents.p1 });

  /* ⑩ 팩 정보 */
  await page.evaluate(() => HT.viewer.maker.openInfo());
  await page.waitForTimeout(500);
  const info = page.locator('#mkProps');
  await info.locator('input[name="created"]').fill('2026-01-02');
  await page.waitForTimeout(500);
  await info.locator('[data-info="cl-add"]').click();
  await page.waitForTimeout(300);
  await info.locator('[data-info-cl] li input[data-cl-f="note"]').first().fill('처음 판');
  await info.locator('[data-rel-name="other-pack"]').fill('다른 팩');
  await page.waitForTimeout(700);
  d = await stored();
  check(d.created === '2026-01-02' && d.changelog && d.changelog.length === 1 && d.changelog[0].note === '처음 판' && d.changelog[0].version === '1.0.0' && d.relations[0].name === '다른 팩', '⑩ 팩 정보의 처음 만든 날 · 판 기록 줄 · 관계의 보일 이름이 작업본에 실림', { created: d.created, changelog: d.changelog, relations: d.relations });
  await shot('10-팩-정보.png');
} catch (e) {
  report.오류.push(String(e && e.stack || e));
}
report.콘솔오류 = errors;
if (errors.length) report.오류.push(`콘솔 오류 ${errors.length}건`);
fs.writeFileSync(path.join(output, '보고.json'), JSON.stringify(report, null, 2));
await browser.close();
server.close();
console.log(report.검사.map(c => `${c.결과 ? '○' : '✗'} ${c.검사}`).join('\n'));
console.log(report.오류.length ? `오류 ${report.오류.length}건:\n${report.오류.join('\n')}` : '오류 없음');
process.exit(report.오류.length ? 1 : 0);

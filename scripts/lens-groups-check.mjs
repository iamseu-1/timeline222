/* 형식 버전 3의 단체 · 렌즈 재료(docs/구상-연표-확장-10건.md 3-7 · 3-8)를 실제 브라우저에서 검사합니다.
   ① 연표(보기 전용): 견본 sample-lantern(등불 연대기 — 단체 열하나 · 제도 일곱 · 주제 다섯 · 법 사건 열셋 · 선거 사건 여섯)을 설치한 채로 열어
      단체 창(진주파 · 항로당 · 등불당) · 제도 창(의회 — 산호 해상 동맹 ↔ 하연 연합 왕국) · 나라 상세의 단체 · 제도 칩 · 사건 상세의 주제 딱지 · 법 · 선거,
      검색 결과의 단체를 봅니다 (창을 열어도 연표가 흐려지지 않아야 함).
   ② 메이커: 새 DLC에 단체 · 제도 · 법/선거 사건을 편집 창의 폼으로 넣고 저장 → 작업본 · 정규화 · 형식 버전 3을 봅니다. 열어서 그대로 저장해도 자료가 달라지지 않는지도.
   node scripts/lens-groups-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge) */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/단체-렌즈');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
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
// 정지 화면은 글꼴과 유한한 등장 효과가 끝난 뒤 찍는다. 무한 반복 효과는 그대로 둔다.
const settleCapture = page => page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all(document.getAnimations()
    .filter(a => Number.isFinite(a.effect?.getComputedTiming().endTime))
    .map(a => a.finished.catch(() => {})));
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
});
const report = { 화면: '1920×1080 · 100% · 1배', 검사: [], 오류: [] };
const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
const sample = name => JSON.parse(fs.readFileSync(path.join(root, 'samples', name + '.json'), 'utf8'));
try {
  /* ① 연표 — 견본 등불 연대기를 설치한 채로 */
  const view = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  await view.addInitScript(packs => { if (!localStorage.getItem('ht.packs.installed')) localStorage.setItem('ht.packs.installed', JSON.stringify(packs)); }, [sample('sample-lantern')]);
  const page = await view.newPage();
  page.on('pageerror', e => report.오류.push(e.message));
  await page.goto(base + 'index.html');
  await page.waitForFunction(() => window.HT && HT.viewer && HT.viewer.state.model && (HT.viewer.state.model.groups || []).length);
  const counts = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    return { groups: m.groups.length, institutions: m.institutions.length, themes: m.themes.length, lawEvents: m.events.filter(e => e.law).length, elections: m.events.filter(e => e.election).length };
  });
  check(counts.groups === 11 && counts.institutions === 7 && counts.themes === 13 && counts.lawEvents === 13 && counts.elections === 6, '견본의 단체 열하나 · 제도 일곱 · 주제(내장 여덟 + 견본 다섯) · 법 열셋 · 선거 여섯이 모델에', counts);
  /* 단체 창: 검색으로 엶 */
  await page.locator('#searchInput').fill('진주파');
  await page.waitForTimeout(200);
  const hit = page.locator('#searchResults button').filter({ has: page.locator('.sr-title', { hasText: /^진주파 단체/ }) }).first(); // 지도자 메모 · 사건 설명에 이름이 든 항목도 함께 찾힘
  await hit.waitFor();
  check((await hit.textContent()).includes('붕당·파벌'), '검색 결과에 단체가 나옴 (종류와 함께)');
  await hit.click();
  await page.waitForFunction(() => !document.querySelector('#detail').hidden && document.querySelector('#detail h2'));
  const group = await page.evaluate(() => {
    const d = document.querySelector('#detail');
    return { title: d.querySelector('h2').textContent, text: d.textContent, picked: document.querySelector('.tl-root, #timeline .timeline, #timeline').classList.contains('is-picked') || !!document.querySelector('.is-picked'), selected: HT.viewer.timeline.selected };
  });
  check(group.title === '진주파' && /집권 기간/.test(group.text) && /뒤를 이은 단체/.test(group.text) && /항로당/.test(group.text) && /이름 바꿈/.test(group.text) && /바울 미르/.test(group.text) && /첫 도선장 선거/.test(group.text), '단체 창 — 집권 기간 · 뒤를 이은 단체(이름 바꿈) · 구성원 · 맺은 사건', { title: group.title });
  check(!group.picked && !group.selected, '단체 창을 열어도 연표는 고르지 않음(흐려지지 않음)', { selected: group.selected });
  check(/실권/.test(group.text) && /어린 도선장 물새 아라 뒤에서/.test(group.text) && /진주 여름/.test(group.text), '실권 기간(진주파 1340~1352) · 지도자 칸으로 이어진 구성원(진주 여름)');
  await settleCapture(page);
  await page.screenshot({ path: path.join(output, '단체-창-1920-1배.png') });
  /* 앞선 단체 — 합쳐짐(등불당 ← 닻파) · 이름 바꿈(항로당 ← 진주파) */
  const more = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    const by = name => m.groups.find(g => g.name === name);
    const out = {};
    HT.viewer.openDetail(by('등불당').uid);
    out.lamp = document.querySelector('#detail').textContent;
    HT.viewer.openDetail(by('항로당').uid);
    out.route = document.querySelector('#detail').textContent;
    return out;
  });
  check(/앞선 단체/.test(more.lamp) && /합쳐짐/.test(more.lamp) && /닻파/.test(more.lamp) && /온새벽/.test(more.lamp) && /앞선 단체/.test(more.route) && /이름 바꿈/.test(more.route) && /진주파/.test(more.route) && /바울 도윤 내각/.test(more.route), '앞선 단체(합쳐짐 · 이름 바꿈) · 인물 · 내각으로 이어진 구성원');
  await settleCapture(page);
  await page.screenshot({ path: path.join(output, '앞선-단체-1920-1배.png') });
  /* 나라 상세의 칩 → 제도 창 */
  const nation = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    const league = m.periods.find(p => p.name === '산호 해상 동맹');
    HT.viewer.openDetail(league.uid);
    const d = document.querySelector('#detail');
    const box = h => [...d.querySelectorAll('.sub-box')].find(b => h.test(b.querySelector('h3').textContent));
    const groups = box(/^단체/), chips = box(/^제도/);
    return { groups: groups ? [...groups.querySelectorAll('.chip')].map(c => c.textContent) : [], instChips: chips ? chips.querySelectorAll('.chip').length : 0 };
  });
  check(nation.groups.length === 2 && /진주파/.test(nation.groups[0]) && /닻파/.test(nation.groups[1]) && nation.instChips === 1, '나라 상세의 단체 칩(진주파 · 닻파) · 제도 칩(의회)', nation);
  await page.locator('#detail .sub-box .chip', { hasText: '의회' }).first().click();
  await page.waitForFunction(() => /같은 갈래의 다른 나라/.test(document.querySelector('#detail').textContent));
  const inst = await page.evaluate(() => ({ text: document.querySelector('#detail').textContent, selected: HT.viewer.timeline.selected }));
  check(/의회/.test(inst.text) && /선주 회의/.test(inst.text) && /선주 · 선원 회의/.test(inst.text) && /하연 연합 왕국/.test(inst.text) && !inst.selected, '제도 창 — 칸 목록 · 같은 갈래의 다른 나라 · 고르지 않음');
  await settleCapture(page);
  await page.screenshot({ path: path.join(output, '제도-창-1920-1배.png') });
  await page.locator('#detail .sub-box .chip', { hasText: '하연 연합 왕국' }).first().click();
  await page.waitForFunction(() => /산호 해상 동맹 «선주 · 선원 회의»에서 옴/.test(document.querySelector('#detail').textContent));
  check(true, '같은 갈래 칩 → 다른 나라(트랙)의 제도 창 (온 곳 표시)');
  /* 사건 상세: 법 · 선거 · 주제 딱지 */
  const events = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    const ev = title => m.events.find(e => e.title === title);
    HT.viewer.openDetail(ev('권리 장전 반포').uid);
    const law = { badges: [...document.querySelectorAll('#detail .badges .badge')].map(b => b.textContent), text: document.querySelector('#detail').textContent };
    HT.viewer.openDetail(ev('첫 양원 총선').uid);
    const table = document.querySelector('#detail .el-table');
    const vote = { rows: table ? table.querySelectorAll('tbody tr').length : 0, won: table ? table.querySelectorAll('tr.is-won').length : 0, text: document.querySelector('#detail').textContent };
    HT.viewer.openDetail(ev('빛돌 전매법 폐지').uid);
    const repeal = [...document.querySelectorAll('#detail .badges .badge')].map(b => b.textContent);
    HT.viewer.openDetail(ev('첫 도선장 선거').uid);
    const pact = document.querySelector('#detail').textContent;
    return { law, vote, repeal, pact };
  });
  check(events.law.badges.includes('법률') && events.law.badges.some(b => b === '법 · 제정') && /제1조\(입헌 연방 군주국\) ① 하연 연합 왕국은 연합 국왕을 원수로/.test(events.law.text), '법 사건 — 주제 딱지 · 제정 딱지 · 조항', events.law.badges);
  check(events.vote.rows === 3 && events.vote.won === 1 && /58,210/.test(events.vote.text) && /평민원/.test(events.vote.text), '선거 사건 — 결과 표(득표 · 의석 · 당선)', events.vote);
  check(events.repeal.includes('빛돌') && events.repeal.includes('법률') && events.repeal.includes('법 · 폐지'), '폐지 사건 — 두 주제 딱지', events.repeal);
  check(/이 일로 맺은 단체/.test(events.pact) && /진주파/.test(events.pact), '사건 상세 — 이 일로 맺은 단체');
  await page.evaluate(() => HT.viewer.openDetail(HT.viewer.state.model.events.find(e => e.title === '첫 양원 총선').uid));
  await settleCapture(page);
  await page.screenshot({ path: path.join(output, '선거-사건-1920-1배.png') });
  /* 문서 링크 [[단체:이름]] */
  const link = await page.evaluate(() => {
    const m = HT.viewer.state.model;
    const g = m.groups.find(x => x.name === '진주파');
    return { doc: !!(m.docs.get(g.uid) || {}).text };
  });
  check(link.doc, '단체의 문서(documents의 항목 키)가 단체 창의 문서로');
  await view.close();

  /* ② 메이커 — 새 DLC(가상 세계)에 나라 · 단체 · 제도 · 법 사건 */
  const makerContext = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
  const maker = await makerContext.newPage();
  maker.on('pageerror', e => report.오류.push(e.message));
  await maker.goto(base + 'dlc-maker.html');
  await maker.locator('[data-start-new]').waitFor();
  await maker.locator('[data-start-new] [name="name"]').fill('가상 단체 확인');
  await maker.locator('[data-start-new] [name="id"]').fill('lens-maker-check');
  await maker.locator('[data-start-new] [name="how"][value="world"]').check();
  await maker.locator('[data-start-new] button[type="submit"]').click();
  await maker.waitForFunction(() => window.HT && HT.viewer && HT.viewer.maker && HT.viewer.maker.draft && document.querySelector('#mkStart').hidden);
  const track = await maker.evaluate(() => HT.viewer.maker.draft.tracks[0].id);
  /* 나라 하나 (단체 · 제도가 가리킬 곳) */
  await maker.evaluate(() => HT.viewer.openEditor(null, 'period'));
  await maker.locator('#editorForm [name="name"]').fill('푸른 들 나라');
  await maker.evaluate(() => { const f = document.querySelector('#editorForm'); HT.writeDateField(f, 'start', 500); HT.writeDateField(f, 'end', 900); });
  await maker.evaluate(() => HT.viewer.saveEditor());
  /* 추가 메뉴에 단체 · 제도 */
  const menu = await maker.evaluate(() => { document.querySelector('#addPeriodBtn').click(); const t = document.querySelector('#ctxMenu'); return t ? t.textContent : ''; });
  check(/＋ 단체 추가/.test(menu) && /＋ 제도 추가/.test(menu), "추가 메뉴에 '＋ 단체 추가' · '＋ 제도 추가'", { menu: menu.slice(0, 200) });
  await maker.keyboard.press('Escape');
  /* 단체 */
  await maker.evaluate(() => HT.viewer.openEditor(null, 'group'));
  await maker.locator('#editorForm [name="name"]').fill('들바람 모임');
  await maker.locator('#editorForm [name="type"]').fill('붕당·파벌');
  await maker.evaluate(() => { const f = document.querySelector('#editorForm'); HT.writeDateField(f, 'start', 600); HT.writeDateField(f, 'end', 700); });
  await maker.locator('#editorForm [data-gp-add="within"]').click();
  await maker.locator('#editorForm [data-gp-within] .s-from').fill('푸른 들 나라');
  await maker.locator('#editorForm [data-gp-add="power"]').click();
  await maker.locator('#editorForm [data-gp-power] .c-name').fill('집권');
  await maker.locator('#editorForm [data-gp-power] .c-start').fill('620');
  await maker.locator('#editorForm [data-gp-power] .c-end').fill('640');
  await maker.locator('#editorForm [name="people"]').fill('가람, 나래');
  await settleCapture(maker);
  await maker.screenshot({ path: path.join(output, '메이커-단체-폼-1920-1배.png') });
  const savedGroup = await maker.evaluate(() => HT.viewer.saveEditor());
  check(!!savedGroup, '단체 폼 저장');
  /* 제도 */
  await maker.evaluate(() => HT.viewer.openEditor(null, 'institution'));
  await maker.locator('#editorForm [name="theme"]').fill('조세제도');
  await maker.locator('#editorForm [name="polity"]').fill('푸른 들 나라');
  await maker.locator('#editorForm [name="family"]').fill('고르게 나눔');
  await maker.locator('#editorForm [data-inst-spans] .c-name').first().fill('밭 나눔');
  await maker.locator('#editorForm [data-inst-spans] .c-start').first().fill('');
  await maker.locator('#editorForm [data-gp-add="spans"]').click();
  await maker.locator('#editorForm [data-inst-spans] .c-name').nth(1).fill('돈 거둠');
  await maker.locator('#editorForm [data-inst-spans] .c-start').nth(1).fill('780');
  await settleCapture(maker);
  await maker.screenshot({ path: path.join(output, '메이커-제도-폼-1920-1배.png') });
  const savedInst = await maker.evaluate(() => HT.viewer.saveEditor());
  check(!!savedInst, '제도 폼 저장');
  /* 법 · 선거 사건 */
  await maker.evaluate(() => HT.viewer.openEditor(null, 'event'));
  await maker.locator('#editorForm [name="title"]').fill('세금 법 제정');
  await maker.evaluate(() => { const f = document.querySelector('#editorForm'); HT.writeDateField(f, 'start', 780); f.querySelector('details[data-adv="lens"]').open = true; });
  await maker.locator('#editorForm [name="themes"]').fill('조세제도, 법률');
  await maker.locator('#editorForm [name="lawName"]').fill('세금 법');
  await maker.locator('#editorForm [name="lawAct"]').selectOption('enact');
  await maker.locator('#editorForm [name="lawArticles"]').fill('첫 조항\n둘째 조항');
  await maker.locator('#editorForm [data-el-add]').click();
  await maker.locator('#editorForm [data-el-results] .e-who').fill('들 모임');
  await maker.locator('#editorForm [data-el-results] .e-votes').fill('1,200');
  await maker.locator('#editorForm [data-el-results] .e-won').check();
  await maker.locator('#editorForm [name="elOffice"]').fill('의장');
  await settleCapture(maker);
  await maker.screenshot({ path: path.join(output, '메이커-사건-주제법선거-1920-1배.png') });
  const savedEvent = await maker.evaluate(() => HT.viewer.saveEditor());
  check(!!savedEvent, '사건 폼(주제 · 법 · 선거) 저장');
  const draft = await maker.evaluate(() => {
    const d = HT.viewer.maker.draft;
    const r = HT.normalizePack(d);
    const json = r.pack ? HT.packToJSON(r.pack) : null;
    return { d: JSON.parse(JSON.stringify({ groups: d.groups, institutions: d.institutions, events: d.events })), errors: r.errors.map(e => e.msg), warnings: r.warnings.map(w => w.msg), ver: json && json.formatVersion, check: HT.viewer.maker.check.warnings.map(w => w.msg) };
  });
  const g0 = draft.d.groups[0], i0 = draft.d.institutions[0], e0 = draft.d.events.find(e => e.title === '세금 법 제정');
  check(g0 && g0.type === 'faction' && g0.within === '푸른 들 나라' && g0.power.length === 1 && g0.people.join() === '가람,나래', '작업본의 단체 (종류 id · 있던 나라 · 집권 기간 · 구성원)', g0);
  check(i0 && i0.theme === '조세제도' && i0.polity === '푸른 들 나라' && i0.family === '고르게 나눔' && i0.spans.length === 2 && i0.spans[0].start == null, '작업본의 제도 (첫 칸 시작 비움 = 나라 시작부터)', i0);
  check(e0 && e0.theme.join() === '조세제도,법률' && e0.law.act === 'enact' && e0.law.articles.length === 2 && e0.election.results[0].votes === 1200 && e0.election.results[0].won === true, '작업본의 사건 (주제 꼬리표 · 법 · 선거)', e0);
  check(!draft.errors.length && draft.ver === 3, '정규화 오류 없음 · 형식 버전 3으로 나감', { errors: draft.errors, ver: draft.ver });
  /* 열어서 그대로 저장해도 자료가 달라지지 않음 (단체 · 제도 · 사건) */
  const same = await maker.evaluate(uids => {
    const before = JSON.stringify(HT.viewer.maker.draft);
    for (const uid of uids) {
      HT.viewer.openEditor(uid);
      HT.viewer.saveEditor();
    }
    return before === JSON.stringify(Object.assign({}, HT.viewer.maker.draft, { _edited: JSON.parse(before)._edited }));
  }, [savedGroup, savedInst, savedEvent]);
  check(same, '열어서 그대로 저장하면 작업본이 그대로 (단체 · 제도 · 사건)');
  /* 바탕 자료의 주제 표 · 단체 · 제도 목록 */
  const tables = await maker.evaluate(() => Object.keys(HT.makerKit.BASE_TABLES));
  check(['themes', 'groups', 'institutions'].every(k => tables.includes(k)), "바탕 자료에 '주제' 표 · '단체' · '제도' 목록", tables);
  await maker.evaluate(uid => HT.viewer.closeEditor().then(() => HT.viewer.openDetail(uid)), savedGroup);
  await maker.waitForTimeout(200);
  await settleCapture(maker);
  await maker.screenshot({ path: path.join(output, '메이커-단체-창-1920-1배.png') });
  await makerContext.close();
  check(report.오류.length === 0, '브라우저 실행 오류 없음', report.오류);
} catch (e) { report.오류.push(e.stack || String(e)); process.exitCode = 1; }
finally { await browser.close(); server.close(); fs.writeFileSync(path.join(output, '화면검사.json'), JSON.stringify(report, null, 2) + '\n'); }
console.log(JSON.stringify({ 검사: report.검사.length, 오류: report.오류, 결과: output }));

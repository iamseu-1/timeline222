/* 문서 그림(형식 3 — 10건 D3 결정 8 A · 9 B · 16건 15번)을 실제 브라우저에서 검사합니다 (노드에서 볼 수 있는 것은 dev-smoke [73]).
   ① 연표 문서 창(1920×1080 · 1배): 견본 samples/sample-lantern.json(등불 연대기)을 설치한 채로 등불 왕국의 딸린 문서 '아홉 불씨'를 열어 —
      가운데 그림(아홉 불씨 왕관 · align=center)은 띄우지 않고 본문 가운데(둥근 12) · 그림 아래 설명 · 출처 ·
      사전에 없는 그림은 '그림 없음 — 이름' 자리(검사 안의 그림 없는 옛 꼴 팩) · 그림을 누르면 화면 전체 크게 보기(Esc로 닫혀도 문서 창은 그대로) · 그림이 없는 문서는 본문 그릇이 예전 그대로.
      (오른쪽에 띄운 그림의 옆 줄 · 아래 줄 폭 · 다음 제목 · 좁은 화면에서 띄우지 않기 검사와 너비(width=) 검사는 견본 1.0.0에 오른쪽 그림 · 너비를 적은 그림이 없어 뺐습니다 — 2.0.0에는 생겼으나(청림 대공국 문서 등) 아직 되살리지 않음)
   ② 메이커: 문서 편집기 도구 줄의 '그림' 단추가 '표' 바로 옆 · 글 칸에 그림 파일을 놓으면 줄여 담고 커서 자리에 [[파일:이름]] ·
      미리 보기에 바로 보임 · 그림 띠(이 문서의 그림 · 팩 그림 합 · 그림 모음) · 되돌리기 한 걸음 · 그림 모음에서 설명 고치기 · 쓰지 않는 그림 지우기.
   ③ 그림이 없는 작업본(견본에서 나라 · 사건 · 그림 · 문서를 비운 것): 그림 갈래와 모음을 열 수 있음.
   node scripts/doc-images-check.mjs <검사할 폴더> <결과 폴더>   (Playwright가 따로 설치되어 있으면 HT_PLAYWRIGHT_ROOT · 브라우저는 HT_BROWSER — 기본 msedge)
   자료는 가상 나라 · 가상 그림만(견본 등불 연대기 · 검사 안에서 지은 팩 · 캔버스로 그린 그림), 따로 띄운 브라우저의 메모리에만 둡니다. 1920×1080 · 1배 화면 그림을 결과 폴더에 남깁니다. */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/문서-그림-검사');
const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
fs.mkdirSync(output, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json', '.mjs': 'text/javascript' };
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
const sample = JSON.parse(fs.readFileSync(path.join(root, 'samples', 'sample-lantern.json'), 'utf8'));
const P = `${sample.id}/`; // 견본 항목 uid의 머리 (lantern-chronicle/)
const DOC = `${P}p-lantern//아홉 불씨`; // 가운데 그림 하나([[파일:아홉 불씨 왕관.png|align=center]])가 있는 딸린 문서
const CROWN = sample.images.find(g => g.id === 'img-crown'); // 견본의 문서 그림 여섯 가운데 왕관 (240×96 PNG)
const NO_IMAGE_DOC = `${P}e-tr-412`; // 그림이 없는 문서
/* 그림이 없는 옛 꼴 문서 하나(형식 1 팩) — 그림 기능이 이 문서의 모습을 바꾸지 않는지 */
const OLD = { format: 'history-timeline-dlc', formatVersion: 1, version: '1.0.0', id: 'img-old', name: '그림 없는 팩', tracks: [{ id: 'old-a', name: '옛 들' }], periods: [{ id: 'k', track: 'old-a', name: '옛 나라', start: 300, end: 400 }], documents: { k: '== 개요 ==\n옛 나라의 문서입니다. [[파일:없는 그림.png]] 그림 고리가 있어도 사전이 없으면 그림 없음 자리만.\n\n둘째 문단입니다.' } };
/** 그리기가 가라앉을 때까지: 끝이 있는 움직임(문서 창 slide-in · 크게 보기의 나타남 --t-in — 동작 줄이기여도 120ms)이 끝난 뒤 두 장면 —
    그러지 않으면 1배 그림이 나타나는 도중(반투명)으로 찍힘. 끝없는 움직임은 기다리지 않고, 길어도 1.5초 */
const settle = page =>
  page.evaluate(() =>
    Promise.race([
      Promise.all(document.getAnimations().filter(a => { const t = a.effect && a.effect.getComputedTiming(); return t && Number.isFinite(t.endTime); }).map(a => a.finished.catch(() => null))),
      new Promise(r => setTimeout(r, 1500)),
    ]).then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))
  );

/** 문서 창의 그림 · 줄 자리 재기 — 본문(article) 좌표 기준 */
const measure = page =>
  page.evaluate(() => {
    const art = document.querySelector('#wikiArticle');
    const A = art.getBoundingClientRect();
    const box = r => ({ l: Math.round(r.left - A.left), t: Math.round(r.top - A.top), r: Math.round(r.right - A.left), b: Math.round(r.bottom - A.top), w: Math.round(r.width), h: Math.round(r.height) });
    const figs = [...art.querySelectorAll('.wk-fig')].map(f => ({ cls: f.className, float: getComputedStyle(f).float, box: box(f.getBoundingClientRect()), img: f.querySelector('.wk-fig-img') ? box(f.querySelector('.wk-fig-img').getBoundingClientRect()) : null, radius: f.querySelector('.wk-fig-img') ? getComputedStyle(f.querySelector('.wk-fig-img')).borderTopLeftRadius : '', caption: (f.querySelector('figcaption') || {}).textContent || '', text: f.textContent.trim().slice(0, 40) }));
    /* 줄마다: 문단 · 목록 항목의 글 조각(Range.getClientRects — 줄 상자 하나에 조각 여럿이면 그 줄의 오른쪽 끝을 씀) */
    const lines = [];
    for (const el of art.querySelectorAll('p, li')) {
      const range = document.createRange();
      range.selectNodeContents(el);
      const byTop = new Map();
      for (const r of range.getClientRects()) {
        if (r.width < 1) continue;
        const t = Math.round(r.top - A.top);
        const k = [...byTop.keys()].find(x => Math.abs(x - t) < 6) ?? t;
        const cur = byTop.get(k) || { t, b: Math.round(r.bottom - A.top), r: -1e9, l: 1e9 };
        cur.r = Math.max(cur.r, Math.round(r.right - A.left));
        cur.l = Math.min(cur.l, Math.round(r.left - A.left));
        byTop.set(k, cur);
      }
      for (const v of byTop.values()) lines.push(Object.assign({ tag: el.tagName, text: el.textContent.slice(0, 16) }, v));
    }
    const heads = [...art.querySelectorAll('.wk-h')].map(h => ({ text: h.textContent.trim(), box: box(h.getBoundingClientRect()) }));
    return { width: Math.round(A.width), figs, lines, heads };
  });

try {
  /* ① 연표 문서 창 */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(packs => { try { localStorage.setItem('ht.packs.installed', JSON.stringify(packs)); } catch (e) { /* 저장 못 함 */ } }, [sample, OLD]);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + 'index.html', { timeout: 30000 });
    await page.waitForFunction(d => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.docs.has(d), DOC, { timeout: 30000 });
    /* 그림 사전이 없는 팩의 문서: 그림 고리는 '그림 없음' 자리 하나 · 띄운 그림이 없으니 본문 그릇은 그대로 · 나머지 글은 예전 그대로 */
    const old = await page.evaluate(() => {
      HT.viewer.openWiki('img-old/k');
      const art = document.querySelector('#wikiArticle');
      return { figs: [...art.querySelectorAll('.wk-fig')].map(f => f.className), missing: (art.querySelector('.wk-fig.is-missing') || {}).textContent || '', container: getComputedStyle(art).containerType, ps: [...art.querySelectorAll('p')].map(p => p.textContent) };
    });
    check(old.figs.join() === 'wk-fig is-missing' && old.container === 'inline-size' && old.ps.length === 2 && old.ps[1] === '둘째 문단입니다.', "그림 사전이 없는 팩의 문서: 그림 고리만 '그림 없음' 자리 · 나머지 글은 그대로", old);
    check(/그림 없음 — 없는 그림\.png/.test(old.missing), "사전에 없는 그림은 '그림 없음 — 이름' 자리", old.missing);
    const plain = await page.evaluate(d => {
      HT.viewer.openWiki(d);
      const art = document.querySelector('#wikiArticle');
      const own = { figs: art.querySelectorAll('.wk-fig').length, container: getComputedStyle(art).containerType };
      HT.viewer.openWiki('track:old-a');
      const art2 = document.querySelector('#wikiArticle');
      return { own, figs: art2.querySelectorAll('.wk-fig').length, container: getComputedStyle(art2).containerType };
    }, NO_IMAGE_DOC);
    check(plain.own.figs === 0 && plain.own.container === 'normal' && plain.figs === 0 && plain.container === 'normal', '그림이 없는 문서(견본 · 옛 꼴 팩의 트랙 문서)는 본문 그릇도 예전 그대로(container-type normal)', plain);
    await page.evaluate(d => HT.viewer.openWiki(d), DOC);
    await page.waitForFunction(() => [...document.querySelectorAll('#wikiArticle .wk-fig-img img')].every(i => i.complete && i.naturalWidth > 0));
    await settle(page);
    const m = await measure(page);
    fs.writeFileSync(path.join(output, '재기-넓은-화면.json'), JSON.stringify(m, null, 2));
    const center = m.figs.find(f => /is-center/.test(f.cls));
    check(center && center.float === 'none' && Math.abs(center.box.l - (m.width - center.box.r)) <= 1 && center.box.w <= m.width && center.radius === '12px', '가운데 그림(align=center)은 띄우지 않고 본문 가운데(둥근 12)', { width: m.width, center });
    check(/아홉 불씨 왕관 — 왼쪽부터/.test(center.caption) && center.caption.includes(CROWN.credit), '그림 아래 설명 · 출처', center.caption);
    await page.screenshot({ path: path.join(output, '문서-그림-가운데.png') });
    /* 누르면 크게 보기 · Esc로 닫혀도 문서 창은 그대로 (견본 그림은 240×96이라 화면을 덮는 판 위에 제 크기 이상으로) */
    await page.click('#wikiArticle .wk-fig.is-center .wk-fig-img');
    await page.waitForFunction(() => { const z = document.querySelector('.wk-zoom'); return z && !z.hidden && z.querySelector('img').complete; });
    await settle(page);
    const zoom = await page.evaluate(() => { const z = document.querySelector('.wk-zoom'); const r = z.getBoundingClientRect(); const i = z.querySelector('img').getBoundingClientRect(); return { full: r.width === innerWidth && r.height === innerHeight, img: [Math.round(i.width), Math.round(i.height)], cap: z.querySelector('figcaption').textContent, focus: document.activeElement.className }; });
    check(zoom.full && zoom.img[0] >= CROWN.width && /아홉 불씨 왕관/.test(zoom.cap) && /wk-zoom-close/.test(zoom.focus), '그림을 누르면 화면 전체 크게 보기(설명 · 닫기 단추에 초점)', zoom);
    await page.screenshot({ path: path.join(output, '문서-그림-크게.png') });
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => document.querySelector('.wk-zoom').hidden);
    const after = await page.evaluate(() => ({ pane: !document.querySelector('#wikiPane').hidden, focus: document.activeElement.className }));
    check(after.pane && /wk-fig-img/.test(after.focus), 'Esc로 크게 보기만 닫히고 문서 창은 그대로 · 초점은 그림으로', after);
    await context.close();
  }
  /* ② 메이커 — 그림 단추 · 놓아서 넣기 · 그림 띠 · 그림 모음 */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(raw => { try { if (!sessionStorage.getItem('img-seeded')) { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); sessionStorage.setItem('img-seeded', '1'); } } catch (e) { /* 저장 못 함 */ } }, sample);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + 'dlc-maker.html', { timeout: 30000 });
    await page.waitForFunction(d => window.HT && HT.viewer && HT.viewer.state.model && HT.viewer.state.model.docs.has(d), DOC, { timeout: 30000 });
    /* 문서를 열기 전에도 구조 나무에서 같은 그림 모음을 연다. 표지와 문서 그림을 구분한다. */
    await page.click('#mkTree [data-tgroup="images"]');
    const treeImages = await page.evaluate(() => {
      const head = document.querySelector('#mkTree [data-tgroup="images"]');
      return { count: head.querySelector('small').textContent, rows: [...head.parentElement.querySelectorAll('.mk-trow')].map(r => r.textContent.trim()) };
    });
    check(treeImages.count === '7' && treeImages.rows.join('|') === '표지1장|문서 그림6장', '구조 나무의 그림: 표지 1장과 문서 그림 6장을 따로 표시(합 7)', treeImages);
    await settle(page);
    await page.screenshot({ path: path.join(output, '메이커-나무-그림-갈래-1920-1배.png') });
    await page.click('#mkTree [data-timages]');
    await page.waitForSelector('.mk-img-dlg[open]');
    const alone = await page.evaluate(() => ({
      note: !!document.querySelector('.mk-img-dlg [data-img-no-editor]'),
      puts: [...document.querySelectorAll('.mk-img-dlg [data-img-put]')].map(b => b.disabled),
      edits: document.querySelectorAll('.mk-img-dlg input[data-k]').length,
      steps: HT.viewer.maker.history.index,
      docs: JSON.stringify(HT.viewer.maker.draft.documents),
    }));
    check(alone.note && alone.puts.length === 6 && alone.puts.every(Boolean) && alone.edits === 18,'문서 미선택 모음: 넣기는 비활성 + 안내, 설명 · 대체 글 · 출처는 고칠 수 있음', alone);
    await settle(page);
    await page.screenshot({ path: path.join(output, '메이커-나무-그림-모음-1920-1배.png') });
    await page.fill('.mk-img-dlg [data-img-row="img-crown"] input[data-k="caption"]', '나무에서 고친 설명');
    await page.fill('.mk-img-dlg [data-img-row="img-crown"] input[data-k="alt"]', '가상 왕관 그림');
    await page.fill('.mk-img-dlg [data-img-row="img-crown"] input[data-k="credit"]', '가상 기록집');
    await page.click('.mk-img-dlg [data-img-save]');
    const aloneSaved = await page.evaluate(() => {
      const maker = HT.viewer.maker, image = maker.draft.images.find(g => g.id === 'img-crown');
      return { caption: image.caption, alt: image.alt, credit: image.credit, steps: maker.history.index, docs: JSON.stringify(maker.draft.documents) };
    });
    check(aloneSaved.caption === '나무에서 고친 설명' && aloneSaved.alt === '가상 왕관 그림' && aloneSaved.credit === '가상 기록집' && aloneSaved.steps === alone.steps + 1 && aloneSaved.docs === alone.docs, '나무 모음의 세 설명 칸을 한 걸음으로 저장하고 문서는 그대로', aloneSaved);
    await page.evaluate(() => HT.viewer.maker.undo());
    await page.waitForFunction(() => HT.viewer.maker.draft.images.find(g => g.id === 'img-crown').caption !== '나무에서 고친 설명');
    check(true, '나무 모음의 설명 고침을 되돌리기 한 번으로 복원');
    /* 문서에서 안 쓰는 그림도 나무 모음에서 지우고, 한 번에 되돌린다. */
    const unusedAt = await page.evaluate(() => {
      const maker = HT.viewer.maker;
      maker.setImages(all => all.concat([{ ...all[0], id: 'img-unused', name: '쓰지 않는 견본.png' }]), '검사 전용 그림');
      return maker.history.index;
    });
    await page.click('#mkTree [data-timages]');
    await page.click('.mk-img-dlg [data-img-row="img-unused"] [data-img-del]');
    await page.click('.mk-img-dlg [data-img-save]');
    const unusedGone = await page.evaluate(() => ({ left: HT.viewer.maker.draft.images.some(g => g.id === 'img-unused'), step: HT.viewer.maker.history.index }));
    check(!unusedGone.left && unusedGone.step === unusedAt + 1, '나무 모음에서 쓰지 않는 그림을 한 걸음으로 지움', unusedGone);
    await page.evaluate(() => HT.viewer.maker.undo());
    await page.waitForFunction(() => HT.viewer.maker.draft.images.some(g => g.id === 'img-unused'));
    const unusedRestored = await page.evaluate(() => {
      const images = HT.viewer.maker.draft.images;
      return images.find(g => g.id === 'img-unused').src === images.find(g => g.id === 'img-crown').src;
    });
    await page.evaluate(() => HT.viewer.maker.undo());
    await page.waitForFunction(n => HT.viewer.maker.draft.images.length === n, sample.images.length);
    check(unusedRestored, '나무 모음의 삭제를 되돌리면 그림 바이트까지 복원');
    await page.evaluate(d => HT.viewer.openWiki(d), DOC);
    await page.click('#wikiEdit');
    await page.waitForSelector('#wikiEditor:not([hidden]) .mk-imgs');
    const bar = await page.evaluate(() => [...document.querySelectorAll('#wikiInsertBar button')].map(b => b.textContent.trim()));
    const ti = bar.indexOf('표');
    check(ti >= 0 && bar[ti + 1] === '그림', "도구 줄의 '그림' 단추가 '표' 바로 옆", bar);
    await page.waitForFunction(() => [...document.querySelectorAll('#wikiPreview .wk-fig-img img')].every(i => i.complete && i.naturalWidth > 0));
    const strip0 = await page.evaluate(() => ({ chips: [...document.querySelectorAll('.mk-imgs .mk-img-chip')].map(c => c.textContent.replace(/\s+/g, ' ').trim()), total: document.querySelector('.mk-imgs-total').textContent }));
    check(strip0.chips.length === 1 && strip0.chips[0].includes(`${CROWN.name}${CROWN.width}×${CROWN.height} · `) && /\d+KB$/.test(strip0.chips[0]) && /팩 그림 합 \d+KB \/ 15MB\(20,000,000자\)/.test(strip0.total), '그림 띠: 이 문서의 그림(이름 · 크기 · 용량) · 팩 그림 합과 한도', strip0);
    await page.screenshot({ path: path.join(output, '메이커-문서-그림-띠.png') });
    /* 글 칸 끝에 커서를 두고 그림 파일을 놓음 → 줄여 담고 [[파일:이름]] 한 줄 · 미리 보기 · 되돌리기 한 걸음 */
    const dropped = await page.evaluate(async () => {
      const ta = document.querySelector('#wikiText');
      ta.focus();
      ta.setSelectionRange(ta.value.length, ta.value.length);
      const c = document.createElement('canvas');
      c.width = 2400;
      c.height = 1200;
      const g = c.getContext('2d');
      g.fillStyle = '#9fbcc6';
      g.fillRect(0, 0, 2400, 1200);
      g.fillStyle = '#b4c497';
      g.beginPath();
      g.arc(1200, 600, 400, 0, Math.PI * 2);
      g.fill();
      const blob = await new Promise(r => c.toBlob(r, 'image/png'));
      const file = new File([blob], '둥근 섬|그림.png', { type: 'image/png' });
      const dt = new DataTransfer();
      dt.items.add(file);
      const history = HT.viewer.maker.history.index;
      ta.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true }));
      for (let i = 0; i < 100 && !(HT.viewer.maker.draft.images || []).some(x => /둥근 섬/.test(x.name)); i++) await new Promise(r => setTimeout(r, 50));
      const img = (HT.viewer.maker.draft.images || []).find(x => /둥근 섬/.test(x.name));
      return { name: img && img.name, w: img && img.width, h: img && img.height, webp: img && /^data:image\/(webp|jpeg)/.test(img.src), tail: ta.value.slice(-24), steps: HT.viewer.maker.history.index - history };
    });
    check(dropped.name === '둥근 섬 그림.webp' && dropped.w === 1600 && dropped.h === 800 && dropped.webp && dropped.tail.endsWith('[[파일:둥근 섬 그림.webp]]\n') && dropped.steps === 1, '그림 파일을 놓으면 긴 변 1600px로 줄여 담고 커서 자리에 [[파일:이름]] 한 줄 · 이름의 | 는 빈칸 · 되돌리기 한 걸음', dropped);
    await page.waitForFunction(() => [...document.querySelectorAll('#wikiPreview .wk-fig')].some(f => /둥근 섬/.test(f.dataset.wikiImg || '') || (f.querySelector('img') && /둥근 섬/.test(f.querySelector('img').alt))));
    const toast = await page.evaluate(() => [...document.querySelectorAll('.toast')].map(t => `${t.className}: ${t.textContent}`).join(' / '));
    check(/그림을 줄여 넣었습니다 — 1600×800 · \d+KB/.test(toast) && !/toast-error/.test(toast), "알림: 그림을 줄여 넣었습니다 — 크기 · 용량 (창 전체의 'DLC 파일 놓기'가 그림을 가로채지 않음)", toast);
    await page.evaluate(() => document.querySelector('#mkTree [data-timages]').click());
    await page.waitForSelector('.mk-img-dlg[open]');
    const unsaved = await page.evaluate(() => {
      const row = [...document.querySelectorAll('.mk-img-dlg [data-img-row]')].find(r => /둥근 섬/.test(r.textContent));
      return { one: document.querySelectorAll('.mk-img-dlg').length, blocked: row.querySelector('[data-img-del]').disabled, put: !row.querySelector('[data-img-put]').disabled, uses: /문서 1곳에서 씀/.test(row.textContent), saved: Object.values(HT.viewer.maker.draft.documents).some(t => t.includes('둥근 섬 그림.webp')) };
    });
    check(unsaved.one === 1 && unsaved.blocked && unsaved.put && unsaved.uses && !unsaved.saved, '나무 모음도 편집 중인 최신 글을 읽어 아직 저장하지 않은 그림의 삭제를 막음 · 모음은 하나', unsaved);
    await settle(page);
    await page.screenshot({ path: path.join(output, '메이커-나무-그림-모음-편집중-1920-1배.png') });
    const beforePut = await page.evaluate(() => ({ text: document.querySelector('#wikiText').value, step: HT.viewer.maker.history.index }));
    await page.click('.mk-img-dlg [data-img-row="img-crown"] [data-img-put]');
    const afterPut = await page.evaluate(() => ({ text: document.querySelector('#wikiText').value, step: HT.viewer.maker.history.index, open: !!document.querySelector('.mk-img-dlg[open]') }));
    const putLine = `[[파일:${CROWN.name}]]`;
    check(!afterPut.open && afterPut.text.split(putLine).length === beforePut.text.split(putLine).length + 1 && afterPut.step === beforePut.step, '편집 중 나무 모음의 넣기는 기존 문서 편집기로 돌아가 커서 자리에 그림 줄을 넣음', { inserted: afterPut.text.slice(-48), steps: afterPut.step - beforePut.step });
    await page.evaluate(text => {
      const ta = document.querySelector('#wikiText');
      ta.value = text;
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    }, beforePut.text);
    /* 저장하면 작업본 문서에 그 줄이 들고 연표 쪽 문서 창에도 그림 */
    await page.click('[data-wiki-act="save"]');
    await page.waitForFunction(() => document.querySelector('#wikiEditor').hidden);
    await page.waitForFunction(() => document.querySelectorAll('#wikiArticle .wk-fig.is-right').length === 1 && [...document.querySelectorAll('#wikiArticle .wk-fig-img img')].every(i => i.complete && i.naturalWidth > 0));
    await settle(page);
    const saved = await page.evaluate(() => ({ figs: document.querySelectorAll('#wikiArticle .wk-fig').length, ver: HT.packToJSON(HT.normalizePack(HT.viewer.maker.draft).pack).formatVersion }));
    check(saved.figs === 2 && saved.ver === 3, '저장하면 문서 창에 새 그림까지 둘(가운데 왕관 · 오른쪽 새 그림) · 작업본은 형식 3', saved);
    /* 그림 모음: 설명 고치기 · 쓰지 않는 그림 지우기(쓰는 그림은 막힘) */
    await page.click('#wikiEdit');
    await page.waitForSelector('#wikiEditor:not([hidden]) .mk-imgs [data-img-gallery]');
    await page.click('.mk-imgs [data-img-gallery]');
    await page.waitForSelector('.mk-img-dlg[open]');
    await settle(page);
    await page.screenshot({ path: path.join(output, '메이커-그림-모음.png') });
    const gallery = await page.evaluate(() => [...document.querySelectorAll('.mk-img-dlg [data-img-row]')].map(r => ({ id: r.dataset.imgRow, del: !r.querySelector('[data-img-del]').disabled, uses: (r.textContent.match(/문서 (\d+)곳에서 씀/) || [])[1], inputs: [...r.querySelectorAll('input')].map(i => [i.dataset.k, i.placeholder]) })));
    check(gallery.length === 7 && gallery.filter(g => g.del).length === 0 && gallery.map(g => g.uses).join() === '1,4,3,2,2,1,1' && gallery.every(g => g.inputs.every(([, ph]) => !ph)), '그림 모음: 이 팩의 그림 일곱(견본 여섯 · 새 그림) · 쓰는 곳 수(고치는 문서는 한 번 — 왕관 1 · 오색 등불 4 · 청옥 인장 3 · 백유리 2 · 백탑 2 · 새 그림 1) · 문서에서 쓰는 그림은 지울 수 없음 · 입력 칸에 회색 예시 글 없음', gallery);
    await page.fill('.mk-img-dlg [data-img-row="img-crown"] input[data-k="caption"]', '아홉 불씨 왕관 — 고친 설명');
    await page.click('.mk-img-dlg [data-img-save]');
    await page.waitForFunction(() => (HT.viewer.maker.draft.images || []).find(x => x.id === 'img-crown').caption === '아홉 불씨 왕관 — 고친 설명');
    await page.waitForFunction(() => /아홉 불씨 왕관 — 고친 설명/.test(document.querySelector('#wikiPreview').textContent));
    check(true, '그림 모음에서 고친 설명이 작업본 · 미리 보기에 바로');
    /* 쓰지 않는 그림: 글에서 둥근 섬 줄을 지우고 저장한 뒤 모음에서 지우기 */
    const removed = await page.evaluate(async () => {
      const ta = document.querySelector('#wikiText');
      ta.value = ta.value.replace(/\n?\[\[파일:둥근 섬 그림\.webp\]\]\n?/, '\n');
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      document.querySelector('[data-wiki-act="save"]').click();
      await new Promise(r => setTimeout(r, 50));
      document.querySelector('#wikiEdit').click();
      await new Promise(r => setTimeout(r, 50));
      document.querySelector('.mk-imgs [data-img-gallery]').click();
      const row = [...document.querySelectorAll('.mk-img-dlg [data-img-row]')].find(r => /둥근 섬/.test(r.textContent));
      const can = !row.querySelector('[data-img-del]').disabled;
      row.querySelector('[data-img-del]').click();
      document.querySelector('.mk-img-dlg [data-img-save]').click();
      return { can, left: (HT.viewer.maker.draft.images || []).map(x => x.name) };
    });
    check(removed.can && removed.left.length === sample.images.length && !removed.left.some(n => /둥근 섬/.test(n)), '문서에서 쓰지 않게 된 그림은 그림 모음에서 지울 수 있음', removed);
    await context.close();
  }
  /* ③ 그림이 없는 작업본: 표지와 문서 그림이 없어도 갈래와 모음을 열 수 있다. */
  {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    const empty = { ...sample, id: 'sample-empty-images', name: '그림 없는 가상 자료집', periods: [], events: [], images: [], documents: {} };
    delete empty.cover;
    await context.addInitScript(raw => { localStorage.setItem('ht.maker.draft', JSON.stringify(raw)); }, empty);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    await page.goto(base + 'dlc-maker.html', { timeout: 30000 });
    await page.waitForSelector('#mkTree [data-tgroup="images"]:not([disabled])');
    await page.click('#mkTree [data-tgroup="images"]');
    await page.click('#mkTree [data-timages]');
    await page.waitForSelector('.mk-img-dlg[open]');
    const blank = await page.evaluate(() => ({
      count: document.querySelector('#mkTree [data-tgroup="images"] small').textContent,
      note: document.querySelector('.mk-img-dlg').textContent,
      rows: document.querySelectorAll('.mk-img-dlg [data-img-row]').length,
      save: !!document.querySelector('.mk-img-dlg [data-img-save]'),
    }));
    check(blank.count === '0' && blank.rows === 0 && !blank.save && /아직 문서 그림이 없습니다/.test(blank.note), '빈 작업본도 그림 갈래와 모음을 열어 문서 편집기의 그림 단추 안내', blank);
    await settle(page);
    await page.screenshot({ path: path.join(output, '메이커-나무-빈-그림-모음-1920-1배.png') });
    await context.close();
  }
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
console.log(`검사 ${report.검사.length} · 오류 ${JSON.stringify(report.오류)}`);
process.exit(report.오류.length ? 1 : 0);

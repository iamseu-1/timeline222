/* 공용 목업 도구 — 지금 연표(웹)를 1920×1080 · 1배로 띄워 예시 DLC를 얹고, 후보 모양을 끼워 넣어 PNG로 찍습니다.
 * 10건 목업 갈래(D1~D6)가 함께 씁니다. 저장소의 파일은 하나도 고치지 않습니다(띄우는 서버가 viewer.js를 내보낼 때만 몇 줄을 끼움).
 *
 * ── 쓰는 법 ──────────────────────────────────────────────────────────────
 *   import { openMock, makeDlc, PASTEL, VIEW_PHONE } from '/home/user/timeline/scripts/mock/lib.mjs';
 *   const m = await openMock({ dlcs: [makeDlc({ ... })], view: [500, 700] });   // 연표(index.html) + 동아시아 기본팩 + 예시 DLC
 *   const uid = await m.uidOf('해온국');            // 이름 → uid ('<팩 id>/<항목 id>')
 *   await m.reveal(uid);                            // 그 띠가 화면에 오게 (가로 · 세로)
 *   const now = await m.shot(dir + '/now.png');     // 지금 모습 (화면 전체 1920×1080)
 *   const r = await m.rect(uid);                    // 띠의 화면 좌표 { x, y, width, height, … }
 *   await m.overlay('<i class="cand">후보</i>', { x: r.x + 40, y: r.y - 14 }, { css: '.cand{…}' });  // 그 자리에 후보 도형
 *   await m.shot(dir + '/a.png', { clip: { x: 0, y: r.y - 120, width: 1920, height: 300 } });       // 잘라 찍기 (1배)
 *   await m.close();                                // 꼭 닫기 (서버는 마지막 창이 닫힐 때 함께 닫힘)
 *
 *   메이커: openMock({ app: 'maker', draft: makeDlc({...}), refs: ['east-asia-base'] }) — 작업본(고치는 DLC)으로 넣고, 불러온 팩으로 기본팩을 함께 봄.
 *   휴대폰: openMock({ viewport: VIEW_PHONE }) — 891×411 · 배율 3.5(갤럭시 S25 울트라 가로). shot은 기본 CSS 1px = 그림 1px(scale: 'css').
 *   예시: node scripts/mock/example.mjs  → .claude/research/10건/kit/ 에 그림과 판.
 *
 * ── 열기 ──
 *   openMock(opts) → Mock          opts: root(띄울 폴더 — 기본 BASE: 변하지 않는 사본) · app('timeline' | 'maker') · viewport(VIEW_PC · VIEW_PHONE · {width,height,scale,mobile})
 *                                   dlcs(예시 DLC 자료 객체 목록 — 설치 DLC로 켬) · draft(메이커 작업본) · refs(메이커가 함께 불러올 팩 id 목록)
 *                                   ui(ht.ui에 미리 얹을 보기 설정 — density · show · tracks …) · view([시작 해, 끝 해]) · builtin(false면 기본팩을 꺼 둠)
 *   startServer(root) · stopServers() · launchBrowser() — 여러 창을 한 브라우저로 돌릴 때만 직접.
 * ── 자료 ──
 *   makeDlc({ id, name, tracks, periods, events, … }) — format · formatVersion · version을 채운 DLC 자료 객체.
 *   m.installDlc(raw | [raw…]) · m.removeDlc(id) · m.enableDlc(id, on) · m.setDraft(raw, { refs })  — 바꾼 뒤 다시 띄움(진짜 설치와 같은 저장소 열쇠)
 *   m.checkDlc(raw) → { ok, errors, warnings }(설치하지 않고 읽기 검사만) · m.uidOf(이름, { kind, track }) · m.item(uid)(모델 항목 요약)
 *   sample('sample-lantern')(견본 samples/*.json — 가상 이름 — 을 예시 DLC로 · { root: REPO }면 원본의 새 견본)
 * ── 보기 맞추기 ──
 *   m.view(시작, 끝) · m.reveal(uid, { at, span }) · m.scrollToTrack(트랙 id, { at }) · m.scrollTop(px) · m.density('roomy'|'auto'|'dense'|'bird' 또는 -1·0·1·2)
 *   m.show({ leaders: false, houses: true, … })(필터의 표시 체크 — 열쇠는 HT.SHOW_DEFAULTS · altToggle은 alt)
 *   m.tracks(['korea'])(이 트랙만) · m.tracks({ japan: false })(끄기) · m.filter({ categories, kinds, minImportance }) · m.fold(트랙 id, 접기?)
 *   m.leaderLabel(표기, 대수?) · m.select(uid, { cell })(상세 창 — 메이커는 편집 창) · m.closeDetail() · m.filterBar(true|false) · m.legend(true|false)
 *   m.hover(대상) · m.click(대상)(진짜 마우스 — 풍선 · 카드 · 누르기 길) · m.unhover()
 * ── 끼워 넣기 ──
 *   m.css(글) · m.run(함수, 값)(page.evaluate) · m.rect(대상) · m.rects(대상) · m.bands({ track })(보이는 띠 목록 — uid · 이름 · 좌표)
 *   m.xOf(해)(그 해의 화면 x) · m.yearAt(x) · m.bodyRect()(연표 몸통 사각형 + gutter · W) · m.clipAround(대상, { above, below, fullWidth })(자를 사각형 — 탭 윗변부터)
 *   대상: uid 글(띠 → 사건 → 인물 → 아무 [data-uid] 차례) · { uid, part: 'band'|'tab'|'event'|'figure'|'cell'|'dyn'|'org'|'any', cell: 'leader:0' } · { sel: 'CSS 선택자' }
 *     (칸은 '<종류>:<순번>' — leader:0 · cabinet:1 …, 띠 안 칸이면 띠 아래에서 찾음. 페이지 안에서는 window.__mockFind(대상)이 같은 규칙)
 *   m.overlay(html, { x, y }, { css, clip: 'timeline' }) — 화면 좌표에 얹는 맨 위 층(누르기 막지 않음) · m.overlayAt(대상, html, { place: 'above'|'below'|'inside'|'left'|'right', dx, dy, gap })
 *   m.insertInto(대상, html) — 그 요소 안에 직접(띠와 함께 움직임 · 다시 그리면 사라지므로 m.freeze()와 함께) · m.freeze() / m.unfreeze() — 연표 다시 그리기 멈춤
 *   m.clearInjected() — 끼운 CSS · 층 · 요소를 모두 걷음
 * ── 찍기 ──
 *   m.shot(파일, { clip: {x,y,width,height} | 대상, pad, scale: 'css'|'device', transient }) → { file, width, height } · m.shotOf(대상, 파일, { pad, fullWidth })
 *   m.quiet({ cards }) — 밀려난 줄 알림 · 토스트(· 카드)를 걷음 (shot이 저절로 부름)
 *   m.settle(ms) — 움직임이 멎고 글꼴이 다 실릴 때까지 · m.errors — 페이지 오류 모음(찍기 전에 비어 있는지 확인 권장) · m.notes — 읽기 경고 같은 알림
 *   m.page — Playwright 페이지 그대로(그 밖의 조작) · 페이지 안에서는 window.__tl(연표) · __state(상태 · 모델) · __v(뷰어 함수) · __maker(메이커 부품) · HT
 * ───────────────────────────────────────────────────────────────────────── */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';

/** 목업의 '지금 모습' 기준 — HEAD 6db35c4를 풀어 둔 변하지 않는 사본 (원본 저장소는 구현 작업으로 바뀔 수 있음) */
export const BASE = '/tmp/claude-0/-home-user-timeline/cddc9061-249a-5fa0-b113-5e9053cde9a4/scratchpad/base';
export const REPO = '/home/user/timeline';
const PLAYWRIGHT = process.env.HT_PLAYWRIGHT_ROOT || '/opt/node-tools/node_modules/playwright/package.json';

/** 감독 화면: 1920×1080 · 100% */
export const VIEW_PC = { width: 1920, height: 1080, scale: 1, mobile: false };
/** 휴대폰 가로: 갤럭시 S25 울트라(3120×1440 · 배율 3.5 → CSS 891×411) */
export const VIEW_PHONE = { width: 891, height: 411, scale: 3.5, mobile: true };
/** 휴대폰 세로 (같은 기기) */
export const VIEW_PHONE_TALL = { width: 411, height: 891, scale: 3.5, mobile: true };

/** 쓸 수 있는 색 — 파스텔 열두 가지 (DLC-형식.md '색') */
export const PASTEL = {
  로즈: '#d4a39b', 피치: '#dab195', 버터: '#d7c18e', 세이지: '#b6c398', 민트: '#9dbea8', 스카이: '#a0bcc5',
  페리윙클: '#abb3c9', 라벤더: '#bbacc8', 핑크: '#d1a9b9', 샌드: '#c8b193', 슬레이트: '#a4b1b7', 모카: '#bba395',
};
/** 동아시아 기본팩의 id와 트랙 */
export const EAST_ASIA = { id: 'east-asia-base', tracks: ['korea', 'china', 'japan', 'vietnam'] };

/** 저장소 열쇠 (js/core.js HT.KEYS — 설치 DLC · 켜고 끔 · 보기 · 보기 설정 · 메이커 작업본 · 메이커가 불러온 팩) */
const KEYS = { installed: 'ht.packs.installed', packState: 'ht.packs.state', view: 'ht.view', ui: 'ht.ui', draft: 'ht.maker.draft', refs: 'ht.maker.refs' };
const APP_PAGE = { timeline: 'index.html', index: 'index.html', maker: 'dlc-maker.html' };
const DENSITY = { roomy: -1, auto: 0, dense: 1, bird: 2, 넉넉: -1, 자동: 0, 빽빽: 1, 조감: 2 };

/* ---------- 정적 서버 ----------
 * scripts/timeline-check.mjs의 서버와 같은 꼴(한글 경로 · utf-8 · 캐시 없음). js/viewer.js를 내보낼 때만 두 곳에 한 줄씩 끼워
 * 연표 · 상태 · 뷰어 안쪽 함수를 창(window)에 내놓습니다: window.__tl(연표) · window.__state(상태) · window.__v(뷰어 함수 — openDetail · applyFilters …) · window.__maker(메이커 부품) */
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.woff2': 'font/woff2', '.webmanifest': 'application/manifest+json', '.ico': 'image/x-icon' };
const VIEWER_FNS = ['openDetail', 'closeDetail', 'applyFilters', 'refresh', 'reloadPacks', 'loadPacks', 'setDensity', 'renderChips', 'setLegend', 'setFilterBar', 'goToDate', 'toggleBird', 'openWiki', 'openYearPanel', 'openDlc', 'setSpotEcho', 'openEditorFor', 'syncInset', 'packById', 'isEnabled'];
const MARK_STATE = '/* ---------- 팩 & 모델 ---------- */';
const MARK_START = '/* ---------- 시작 ---------- */';
function patchViewer(text) {
  if (text.split(MARK_STATE).length !== 2 || text.split(MARK_START).length !== 2) throw new Error('js/viewer.js의 표지(팩 & 모델 · 시작)를 찾지 못했습니다 — 목업 도구의 끼움 자리를 고쳐야 합니다');
  const expose = 'window.__v={};' + VIEWER_FNS.map(n => `try{window.__v.${n}=typeof ${n}!=='undefined'?${n}:undefined}catch(e){}`).join('') + 'try{window.__maker=maker}catch(e){}\n';
  return text.replace(MARK_STATE, 'window.__tl=timeline;window.__state=state;\n' + MARK_STATE).replace(MARK_START, expose + MARK_START);
}
const servers = new Map(); // root → { url, server, users }
/** root 폴더를 띄웁니다 (같은 root는 한 번만). 돌려줌: { url, close } */
export async function startServer(root = BASE) {
  root = path.resolve(root);
  if (servers.has(root)) return servers.get(root);
  if (!fs.existsSync(path.join(root, 'index.html'))) throw new Error(`띄울 폴더에 index.html이 없습니다: ${root}`);
  const server = http.createServer((req, res) => {
    try {
      const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
      if (rel === '__blank') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        return res.end('<!doctype html><meta charset="utf-8"><title>준비</title>');
      }
      const file = path.resolve(root, rel);
      if (!file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
      let bytes = fs.readFileSync(file);
      if (rel === 'js/viewer.js') bytes = Buffer.from(patchViewer(bytes.toString('utf8')));
      res.writeHead(200, { 'Content-Type': (TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(bytes);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const entry = { root, url: 'http://127.0.0.1:' + server.address().port + '/', server, close: () => new Promise(r => server.close(() => r())) };
  servers.set(root, entry);
  return entry;
}
export async function stopServers() {
  for (const s of servers.values()) await s.close();
  servers.clear();
}

/* ---------- 브라우저 ---------- */
let sharedBrowser = null;
let openCount = 0;
/** 크로미움 하나를 띄워 함께 씁니다 (msedge는 이 상자에 없음) */
export async function launchBrowser() {
  if (sharedBrowser && sharedBrowser.isConnected()) return sharedBrowser;
  const { chromium } = createRequire(PLAYWRIGHT)('playwright');
  sharedBrowser = await chromium.launch({ headless: true, channel: process.env.HT_BROWSER && process.env.HT_BROWSER !== 'chromium' ? process.env.HT_BROWSER : undefined });
  return sharedBrowser;
}

/** 견본 자료(samples/<이름>.json — 모두 가상 이름)를 읽어 예시 DLC로 씀. root: 읽을 폴더(기본 BASE — 형식 3 새 견본은 REPO) */
export function sample(name, { root = BASE } = {}) {
  const file = path.join(root, 'samples', name.endsWith('.json') ? name : name + '.json');
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** DLC 자료 객체 (DLC-형식.md의 꼴). 빈 칸은 채움: format · formatVersion(기본 2 — 새 열쇠를 쓰면 3을 적음) · version · 목록들 */
export function makeDlc(raw = {}) {
  const out = Object.assign({ format: 'history-timeline-dlc', formatVersion: 2, id: 'mock-check', name: '확인용 예시', version: '1.0.0', author: '목업 도구', description: '목업 확인용 예시 — 고증 아님' }, raw);
  for (const k of ['tracks', 'periods', 'events']) if (!Array.isArray(out[k])) out[k] = [];
  return out;
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
const isRect = v => v && typeof v === 'object' && ['x', 'y', 'width', 'height'].every(k => typeof v[k] === 'number');

/** (페이지 안에서 돎) 대상 → 보이는 요소 목록. 대상: uid 글(띠 → 사건 → 인물 → 조감 막대 → 아무 [data-uid]) · { uid, part, cell } · { sel } */
function mockFind(target) {
  const q = s => CSS.escape(String(s));
  const PART = { band: '.tl-band', tab: '.tl-tab', event: '.tl-ev', figure: '.tl-fig', cell: '.tl-cell', dyn: '.tl-dyn', org: '.tl-org', mini: '.tl-mini-bar', under: '.tl-under', any: '' };
  let sels;
  if (typeof target === 'string') sels = ['.tl-band', '.tl-ev', '.tl-fig', '.tl-mini-bar', ''].map(p => `${p}[data-uid="${q(target)}"]`);
  else if (target && target.sel) sels = [target.sel];
  else if (target && target.uid && target.cell) sels = [`[data-uid="${q(target.uid)}"][data-cell="${q(target.cell)}"]`, `.tl-band[data-uid="${q(target.uid)}"] [data-cell="${q(target.cell)}"]`];
  else if (target && target.uid) sels = [`${PART[target.part || 'band'] ?? ''}[data-uid="${q(target.uid)}"]`];
  else return [];
  for (const sel of sels) {
    const out = [...document.querySelectorAll(sel)].filter(el => (target.sel || !el.closest('[data-mock]')) && el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0);
    if (out.length) return out;
  }
  return [];
}

/** 연표(또는 메이커)를 띄웁니다 — 돌려주는 Mock의 함수로 보기를 맞추고 찍습니다 */
export async function openMock(opts = {}) {
  const m = new Mock(opts);
  await m._open();
  return m;
}

export class Mock {
  constructor({ root = BASE, app = 'timeline', viewport = VIEW_PC, dlcs = [], draft = null, refs = null, ui = null, view = null, builtin = true, quiet = false } = {}) {
    this.root = path.resolve(root);
    this.app = APP_PAGE[app] ? app : 'timeline';
    this.viewport = Object.assign({}, VIEW_PC, viewport);
    this.opts = { dlcs: [].concat(dlcs || []), draft, refs, ui, view, builtin, quiet };
    this.errors = []; // 페이지 오류 · 콘솔 오류
    this.notes = []; // 예시 DLC 읽기 경고 같은 알림
  }

  async _open() {
    this.server = await startServer(this.root);
    this.browser = await launchBrowser();
    const v = this.viewport;
    this.context = await this.browser.newContext({
      viewport: { width: v.width, height: v.height }, screen: { width: v.width, height: v.height }, deviceScaleFactor: v.scale || 1,
      isMobile: !!v.mobile, hasTouch: !!v.mobile, reducedMotion: 'reduce', serviceWorkers: 'block', locale: 'ko-KR', timezoneId: 'Asia/Seoul',
    });
    await this.context.addInitScript(`window.__mockFind = ${mockFind.toString()};`);
    openCount++;
    this.page = await this.context.newPage();
    this.page.on('pageerror', e => this.errors.push('페이지 오류: ' + e.message));
    this.page.on('console', msg => { if (msg.type() === 'error') this.errors.push('콘솔: ' + msg.text()); });
    /* 저장소(localStorage)를 먼저 채운 뒤 앱을 엽니다 — 진짜 설치와 같은 열쇠(설치 DLC · 켜고 끔 · 보기 설정 · 작업본) */
    await this.page.goto(this.server.url + '__blank');
    const { dlcs, draft, refs, ui, view, builtin } = this.opts;
    const seed = {};
    if (dlcs.length) {
      seed[KEYS.installed] = dlcs;
      seed[KEYS.packState] = Object.fromEntries(dlcs.map(d => [d.id, { enabled: true }]));
    }
    if (!builtin) seed[KEYS.packState] = Object.assign(seed[KEYS.packState] || {}, { [EAST_ASIA.id]: { enabled: false } });
    if (ui) seed[KEYS.ui] = ui;
    if (view) seed[KEYS.view] = { start: view[0], end: view[1] };
    if (draft) seed[KEYS.draft] = draft;
    if (draft && refs) seed[KEYS.refs] = { [draft.id]: [].concat(refs).map(id => ({ id, show: true, locked: true })) };
    await this.page.evaluate(seed => { localStorage.clear(); for (const [k, v] of Object.entries(seed)) localStorage.setItem(k, JSON.stringify(v)); }, seed);
    await this.page.goto(this.server.url + APP_PAGE[this.app]);
    await this.ready();
    for (const d of dlcs) await this._verifyPack(d);
    if (draft) await this._verifyDraft(draft);
    if (view) await this.view(view[0], view[1]);
    return this;
  }

  /** 앱이 다 떴는지: 연표 · 상태 · 모델이 있고, 글꼴이 실리고, 움직임이 멎음 */
  async ready() {
    await this.page.waitForFunction(() => window.__tl && window.__state && window.__state.model && window.__v, null, { timeout: 30000 });
    await this.settle();
  }

  /** 움직임 · 첫 등장이 끝나고 글꼴이 실릴 때까지 기다린 뒤 ms만큼 더 (정착 타이머 몫) */
  async settle(ms = 350) {
    await this.page.evaluate(async () => {
      await document.fonts.ready;
      const tl = window.__tl;
      const t0 = performance.now();
      const busy = () => tl && (tl._inMotion() || (tl.innerEl && tl.innerEl.classList.contains('is-entering')));
      while (busy() && performance.now() - t0 < 4000) await new Promise(r => setTimeout(r, 30));
      await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    });
    if (ms) await sleep(ms);
  }

  async _verifyPack(raw) {
    const r = await this.page.evaluate(id => {
      const p = window.__state.packs.find(x => x.id === id);
      const on = window.__v.isEnabled ? window.__v.isEnabled(id) : true;
      return { found: !!p, on, name: p && p.name, periods: p ? p.periods.length : 0, events: p ? p.events.length : 0 };
    }, raw.id);
    const check = await this.checkDlc(raw);
    if (!check.ok) throw new Error(`예시 DLC «${raw.id}»를 읽지 못했습니다: ${check.errors.join(' / ')}`);
    if (!r.found) throw new Error(`예시 DLC «${raw.id}»가 연표의 팩 목록에 없습니다`);
    if (check.warnings.length) this.notes.push(`«${raw.id}» 읽기 경고: ${check.warnings.join(' / ')}`);
    if (!this.opts.quiet) console.log(`  예시 DLC «${r.name}» 켬 — 시대 ${r.periods} · 사건 ${r.events}${check.warnings.length ? ` · 경고 ${check.warnings.length}` : ''}`);
  }

  async _verifyDraft(raw) {
    const r = await this.page.evaluate(id => ({ own: window.__state.model.periods.concat(window.__state.model.events).filter(x => x.packId === id).length, maker: !!window.__maker }), raw.id);
    if (!r.maker) throw new Error('메이커 부품이 없습니다 — app: "maker"로 열었는지 확인하세요');
    if (!this.opts.quiet) console.log(`  메이커 작업본 «${raw.name}» — 모델에 든 제 항목 ${r.own}`);
  }

  /* ---------- 자료 ---------- */
  /** 설치하지 않고 연표의 읽기(HT.normalizePack)로 검사만 */
  async checkDlc(raw) {
    return this.page.evaluate(raw => {
      const r = window.HT.normalizePack(JSON.parse(JSON.stringify(raw)));
      const msg = x => (x && x.msg) || String(x);
      return { ok: !!r.pack && !r.errors.length, errors: r.errors.map(msg), warnings: r.warnings.map(msg) };
    }, raw);
  }

  async _restart(mutate) {
    const view = await this.page.evaluate(() => ({ ...window.__tl.view }));
    await this.page.evaluate(mutate.fn, mutate.arg);
    await this.page.reload();
    await this.ready();
    await this.view(view.start, view.end);
  }

  /** 예시 DLC를 설치 DLC로 켭니다 (같은 id면 교체) — 연표의 설치와 같은 저장소 열쇠에 쓰고 다시 띄움 */
  async installDlc(raws) {
    raws = [].concat(raws);
    for (const raw of raws) {
      const c = await this.checkDlc(raw);
      if (!c.ok) throw new Error(`예시 DLC «${raw.id}»를 읽지 못했습니다: ${c.errors.join(' / ')}`);
    }
    await this._restart({
      fn: ({ raws, K }) => {
        const HT = window.HT;
        const installed = HT.store.get(K.installed, []).filter(p => !raws.some(r => r.id === p.id));
        installed.push(...raws); // 처음 열 때(_open)와 같이 자료 그대로 — 읽기는 연표가 켤 때 HT.normalizePack으로 (검사는 위에서 이미 함)
        HT.store.set(K.installed, installed);
        const st = HT.store.get(K.packState, {});
        for (const raw of raws) st[raw.id] = { enabled: true };
        HT.store.set(K.packState, st);
      },
      arg: { raws, K: KEYS },
    });
    for (const raw of raws) await this._verifyPack(raw);
  }
  async removeDlc(id) {
    await this._restart({ fn: ({ id, K }) => window.HT.store.set(K.installed, window.HT.store.get(K.installed, []).filter(p => p.id !== id)), arg: { id, K: KEYS } });
  }
  async enableDlc(id, on = true) {
    await this._restart({ fn: ({ id, on, K }) => { const st = window.HT.store.get(K.packState, {}); st[id] = { enabled: !!on }; window.HT.store.set(K.packState, st); }, arg: { id, on, K: KEYS } });
  }
  /** 메이커 작업본(고치는 DLC)으로 넣습니다 — refs: 함께 불러올 팩 id 목록(예: ['east-asia-base']) */
  async setDraft(raw, { refs = null } = {}) {
    if (this.app !== 'maker') throw new Error('작업본은 메이커(app: "maker")에서만 넣습니다');
    await this._restart({
      fn: ({ raw, refs, K }) => {
        window.HT.store.set(K.draft, window.HT.draft.clean(raw));
        if (refs) { const all = window.HT.store.get(K.refs, {}) || {}; all[raw.id] = refs.map(id => ({ id, show: true, locked: true })); window.HT.store.set(K.refs, all); }
      },
      arg: { raw, refs: refs ? [].concat(refs) : null, K: KEYS },
    });
    await this._verifyDraft(raw);
  }

  /** 이름 → uid. kind: 'period' | 'event' | 'figure' …(itemKind 또는 kind), track: 트랙 id로 좁힘. 여럿이면 첫째 */
  async uidOf(name, { kind = null, track = null } = {}) {
    const uid = await this.page.evaluate(({ name, kind, track }) => {
      const m = window.__state.model;
      const all = [...m.byUid.values()];
      const hit = all.find(x => (x.name === name || x.title === name) && (!kind || x.kind === kind || x.itemKind === kind) && (!track || x.track === track));
      return hit ? hit.uid : null;
    }, { name, kind, track });
    if (!uid) throw new Error(`"${name}" 항목을 모델에서 찾지 못했습니다`);
    return uid;
  }
  /** 모델 항목 요약 { uid, kind, name, track, start, end, row } (없으면 null) */
  async item(uid) {
    return this.page.evaluate(uid => {
      const x = window.__state.model.byUid.get(uid);
      if (!x) return null;
      const lane = window.__tl._laneOf(uid);
      return { uid, kind: x.itemKind || x.kind, name: x.name || x.title, track: x.track, start: x.start, end: x.endY, row: lane ? lane.row : null, color: x.color };
    }, uid);
  }

  /* ---------- 보기 맞추기 ---------- */
  /** 보이는 해 범위 */
  async view(start, end) {
    await this.page.evaluate(([s, e]) => window.__tl.setView(s, e), [start, end]);
    await this.settle();
  }
  /** 세로 스크롤(연표 몸통) */
  async scrollTop(px) {
    await this.page.evaluate(px => { window.__tl.bodyEl.scrollTop = px; }, px);
    await this.settle(150);
  }
  /** 트랙의 맨 위가 연표 몸통 위에서 at(px) 아래에 오게 */
  async scrollToTrack(trackId, { at = 0 } = {}) {
    const ok = await this.page.evaluate(({ trackId, at }) => {
      const tl = window.__tl, tr = tl.tracks.find(t => t.id === trackId);
      if (!tr || !tr.el) return false;
      tl.bodyEl.scrollTop = Math.max(0, tr.el.offsetTop - at);
      return true;
    }, { trackId, at });
    if (!ok) throw new Error(`트랙 "${trackId}"가 연표에 없습니다(필터로 꺼졌거나 없는 id)`);
    await this.settle(150);
  }
  /** 항목(uid)이 화면에 오게: 가로는 보기 밖이면 그 항목을 가운데로(span 년 폭 — 비우면 지금 폭), 세로는 그 줄이 몸통 위에서 at(px — 기본: 몸통 높이의 1/3)에.
      접힌 트랙 · 민족 · 숨은 소속은 연표의 멀리 가기(focusOn)와 같은 규칙으로 펴지 않으므로, 접혀 있으면 m.fold로 먼저 펴세요 */
  async reveal(uid, { at = null, span = null, horizontal = true } = {}) {
    const r = await this.page.evaluate(({ uid, span, horizontal }) => {
      const tl = window.__tl, x = window.__state.model.byUid.get(uid);
      if (!x) return { err: '모델에 없는 uid' };
      if (horizontal) {
        const s0 = x.start, e0 = x.endY != null ? x.endY : x.start, v = tl.view, w = span || v.end - v.start;
        if (span || e0 < v.start || s0 > v.end) { const c = (s0 + e0) / 2; tl.setView(c - w / 2, c + w / 2); }
      }
      return { ok: true };
    }, { uid, span, horizontal });
    if (r.err) throw new Error(`${uid}: ${r.err}`);
    await this.settle(150);
    const ok = await this.page.evaluate(({ uid, at }) => {
      const tl = window.__tl, a = tl._laneOf(uid);
      if (!a) return false;
      const off = at == null ? Math.round(tl.bodyEl.clientHeight / 3) : at;
      tl.bodyEl.scrollTop = Math.max(0, tl._laneAbs(a) - off);
      return true;
    }, { uid, at });
    if (!ok) this.notes.push(`${uid}: 놓인 줄이 없어(접힘 · 숨은 소속 · 왕조 · 시대 구분) 세로는 맞추지 않음`);
    await this.settle(200);
  }
  /** 밀도: 'roomy'(넉넉) · 'auto' · 'dense'(빽빽) · 'bird'(조감) 또는 -1 · 0 · 1 · 2 */
  async density(v) {
    const d = typeof v === 'number' ? v : DENSITY[v];
    if (d == null) throw new Error('밀도 값: roomy · auto · dense · bird');
    await this.page.evaluate(d => window.__v.setDensity(d), d);
    await this.settle();
  }
  /** 필터의 표시 체크 — { leaders, cabinets, dynasties, eras, capitals, ganji, epochs, succession, partOf, phases, ranks, figures, houses, spotEcho, alt } */
  async show(patch) {
    const missing = await this.page.evaluate(patch => {
      const ids = { dynasties: 'dynastyToggle', leaders: 'leaderToggle', cabinets: 'cabinetToggle', eras: 'eraToggle', capitals: 'capToggle', ganji: 'ganjiToggle', epochs: 'epochToggle', succession: 'linkToggle', partOf: 'partToggle', spotEcho: 'spotEchoToggle', phases: 'phaseToggle', ranks: 'rankToggle', figures: 'figureToggle', houses: 'houseToggle', alt: 'altToggle', ordinal: 'ordinalToggle' };
      const missing = [];
      for (const [k, on] of Object.entries(patch)) {
        const el = document.getElementById(ids[k] || k);
        if (!el) { missing.push(k); continue; }
        if (el.checked === !!on) continue;
        el.checked = !!on;
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      return missing;
    }, patch);
    if (missing.length) throw new Error('표시 체크를 찾지 못함: ' + missing.join(', '));
    await this.settle();
  }
  /** 트랙 거르기: 목록이면 그 트랙만, 객체면 { 트랙 id: 켬? } */
  async tracks(sel) {
    await this.page.evaluate(sel => {
      const st = window.__state;
      if (Array.isArray(sel)) for (const t of st.model.tracks) st.ui.tracks[t.id] = sel.includes(t.id);
      else Object.assign(st.ui.tracks, sel);
      window.__v.renderChips();
      window.__v.applyFilters();
    }, sel);
    await this.settle();
  }
  /** 분류 · 종류 · 중요도 거르기 — { categories: { war: false }, kinds: { org: false }, minImportance: 2 } */
  async filter({ categories = null, kinds = null, minImportance = null } = {}) {
    await this.page.evaluate(({ categories, kinds, minImportance }) => {
      const ui = window.__state.ui;
      if (categories) Object.assign(ui.categories, categories);
      if (kinds) Object.assign(ui.kinds, kinds);
      if (minImportance != null) { ui.minImportance = minImportance; document.getElementById('importanceSelect').value = String(minImportance); }
      window.__v.renderChips();
      window.__v.applyFilters();
    }, { categories, kinds, minImportance });
    await this.settle();
  }
  /** 트랙 접기(on = true) · 펴기(false) */
  async fold(trackId, on = true) {
    await this.page.evaluate(({ trackId, on }) => window.__tl.toggleFold(trackId, on), { trackId, on });
    await this.settle();
  }
  /** 지도자 표기('auto' · 'temple' · 'title' · 'given' · 'temple-title' · 'all')와 대수 */
  async leaderLabel(mode = 'auto', ordinal = null) {
    await this.page.evaluate(({ mode, ordinal }) => {
      const sel = document.getElementById('leaderLabelSelect');
      if (sel && mode) { sel.value = mode; sel.dispatchEvent(new Event('change', { bubbles: true })); }
      const o = document.getElementById('ordinalToggle');
      if (o && ordinal != null && o.checked !== !!ordinal) { o.checked = !!ordinal; o.dispatchEvent(new Event('change', { bubbles: true })); }
    }, { mode, ordinal });
    await this.settle();
  }
  /** 항목 고르기 — 연표를 누른 것과 같은 길(상세 창 · 메이커는 편집 창). cell: 'leader:0'처럼 칸 */
  async select(uid, { cell = null } = {}) {
    await this.page.evaluate(({ uid, cell }) => window.__tl.opts.onSelect(uid, null, cell ? { cell } : undefined), { uid, cell });
    await this.settle(450);
  }
  async closeDetail() {
    await this.page.evaluate(() => window.__v.closeDetail());
    await this.settle();
  }
  /** 진짜 마우스로 대상 가운데에 올리기 (풍선 · 묶음 카드 · 호버 모양을 찍을 때) — dx · dy로 가운데에서 옮김 */
  async hover(target, { dx = 0, dy = 0 } = {}) {
    const r = await this.rect(target);
    if (!r) throw new Error('올릴 대상을 화면에서 찾지 못했습니다: ' + JSON.stringify(target));
    await this.page.mouse.move(r.x + r.width / 2 + dx, r.y + r.height / 2 + dy);
    await this.settle(400);
    return r;
  }
  /** 진짜 마우스로 누르기 (연표의 누르기 길 그대로 — 칸 · 탭 · 단추) */
  async click(target, { dx = 0, dy = 0 } = {}) {
    const r = await this.rect(target);
    if (!r) throw new Error('누를 대상을 화면에서 찾지 못했습니다: ' + JSON.stringify(target));
    await this.page.mouse.click(r.x + r.width / 2 + dx, r.y + r.height / 2 + dy);
    await this.settle(450);
    return r;
  }
  /** 마우스를 화면 밖 구석으로 (호버를 걷음) */
  async unhover() {
    await this.page.mouse.move(this.viewport.width - 1, this.viewport.height - 1);
    await this.settle(250);
  }
  /** 필터 판(시트) 열기 · 닫기 */
  async filterBar(open = true) {
    await this.page.evaluate(open => window.__v.setFilterBar(!!open), open);
    await this.settle();
  }
  /** 범례 열기 · 닫기 */
  async legend(open = true) {
    await this.page.evaluate(open => window.__v.setLegend(!!open), open);
    await this.settle();
  }

  /* ---------- 끼워 넣기 ---------- */
  /** CSS 글을 얹습니다 (m.clearInjected로 걷음) */
  async css(text) {
    await this.page.evaluate(text => {
      const s = document.createElement('style');
      s.dataset.mock = '';
      s.textContent = text;
      document.head.appendChild(s);
    }, text);
    await this.page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  }
  /** 페이지 안에서 함수를 돌립니다 (page.evaluate 그대로) — 함수 안에서 window.__tl · __state · __v · HT를 씀 */
  async run(fn, arg) {
    return this.page.evaluate(fn, arg);
  }
  /** 대상의 화면 좌표 (보이는 첫째) — 없으면 null */
  async rect(target) {
    const all = await this.rects(target);
    return all[0] || null;
  }
  /** 대상의 화면 좌표 모두 — [{ x, y, width, height, left, top, right, bottom, uid, cls, text }] */
  async rects(target) {
    return this.page.evaluate(target =>
      window.__mockFind(target).map(el => {
        const r = el.getBoundingClientRect();
        return { x: r.x, y: r.y, width: r.width, height: r.height, left: r.left, top: r.top, right: r.right, bottom: r.bottom, uid: el.dataset.uid || null, cls: el.className && el.className.baseVal != null ? el.className.baseVal : el.className, text: (el.textContent || '').trim().slice(0, 40) };
      }), target);
  }
  /** 해 → 화면 x (연표 몸통 기준 — 후보 도형을 그 해의 자리에 얹을 때) */
  async xOf(year) {
    return this.page.evaluate(y => {
      const tl = window.__tl;
      return tl.bodyEl.getBoundingClientRect().left + tl.gutter + ((y - tl.view.start) / tl.span()) * tl.W;
    }, year);
  }
  /** 화면 x → 해 */
  async yearAt(x) {
    return this.page.evaluate(x => window.__tl.yearAtClientX(x), x);
  }
  /** 연표 몸통(띠가 그려지는 칸)의 화면 사각형 — gutter(왼쪽 이름 칸 폭) · W(그림 폭)도 함께 */
  async bodyRect() {
    return this.page.evaluate(() => {
      const tl = window.__tl, r = tl.bodyEl.getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height, left: r.left, top: r.top, right: r.right, bottom: r.bottom, gutter: tl.gutter, W: tl.W };
    });
  }
  /** 대상 둘레의 자를 사각형 — 위로 above · 아래로 below(px)만큼 넓히고, 가로는 화면 전체(fullWidth — 기본) 또는 대상 ± side.
      간지 탭이 있는 띠는 탭의 윗변부터 셈. 같은 사각형으로 '지금'과 '안'을 찍으면 나란히 견주기 쉬움 */
  async clipAround(target, { above = 120, below = 60, side = 40, fullWidth = true } = {}) {
    const r = await this.rect(target);
    if (!r) throw new Error('자를 대상을 화면에서 찾지 못했습니다: ' + JSON.stringify(target));
    const uid = typeof target === 'string' ? target : target.uid;
    const tab = uid && (typeof target === 'string' || !target.part || target.part === 'band') ? await this.rect({ uid, part: 'tab' }) : null;
    const top = Math.min(r.y, tab ? tab.y : r.y) - above, bottom = r.bottom + below;
    const W = this.viewport.width, H = this.viewport.height;
    const y = Math.max(0, Math.floor(top)), h = Math.min(H, Math.ceil(bottom)) - y;
    if (fullWidth) return { x: 0, y, width: W, height: h };
    const x = Math.max(0, Math.floor(r.x - side));
    return { x, y, width: Math.min(W, Math.ceil(r.right + side)) - x, height: h };
  }
  /** 화면에 보이는 띠 목록 — [{ uid, name, track, row, x, y, width, height }] (track으로 좁힘) */
  async bands({ track = null } = {}) {
    return this.page.evaluate(track => {
      const body = window.__tl.bodyEl.getBoundingClientRect(), m = window.__state.model;
      return [...document.querySelectorAll('.tl-band[data-uid]')]
        .map(el => ({ el, r: el.getBoundingClientRect(), x: m.byUid.get(el.dataset.uid) }))
        .filter(({ r, x }) => r.width > 0 && r.bottom > body.top && r.top < body.bottom && x && (!track || x.track === track))
        .map(({ el, r, x }) => ({ uid: el.dataset.uid, name: x.name, track: x.track, row: Number(el.dataset.row), x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) }));
    }, track);
  }
  /** 화면 좌표에 얹는 맨 위 층 — html을 { x, y }에 (왼쪽 위 기준). css를 함께 줄 수 있고, clip: 'timeline'이면 연표 몸통 밖은 잘림 */
  async overlay(html, at, { css = '', clip = null } = {}) {
    if (css) await this.css(css);
    await this.page.evaluate(({ html, at, clip }) => {
      let layer = document.getElementById(clip ? 'mk-layer-clip' : 'mk-layer');
      if (!layer) {
        layer = document.createElement('div');
        layer.id = clip ? 'mk-layer-clip' : 'mk-layer';
        layer.dataset.mock = '';
        layer.style.cssText = 'position:fixed;inset:0;z-index:2147483000;pointer-events:none;';
        if (clip) {
          const r = (clip === 'timeline' ? window.__tl.bodyEl : document.querySelector(clip)).getBoundingClientRect();
          layer.style.cssText += `clip-path:inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px);`;
        }
        document.body.appendChild(layer);
      }
      const box = document.createElement('div');
      box.dataset.mock = '';
      box.style.cssText = `position:absolute;left:${at.x}px;top:${at.y}px;`;
      box.innerHTML = html;
      layer.appendChild(box);
    }, { html, at, clip });
    await this.page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  }
  /** 대상 옆에 얹기 — place: 'above'(대상 윗변에 밑변을 붙임) · 'below' · 'inside'(대상 왼쪽 위) · 'left' · 'right'. dx · dy로 더 옮기고, gap은 떨어질 거리 */
  async overlayAt(target, html, { place = 'above', dx = 0, dy = 0, gap = 2, css = '', clip = null } = {}) {
    const r = await this.rect(target);
    if (!r) throw new Error('얹을 대상을 화면에서 찾지 못했습니다: ' + JSON.stringify(target));
    if (css) await this.css(css);
    const size = await this.page.evaluate(html => {
      const t = document.createElement('div');
      t.style.cssText = 'position:fixed;left:-9999px;top:0;';
      t.innerHTML = html;
      document.body.appendChild(t);
      const b = t.getBoundingClientRect();
      t.remove();
      return { w: b.width, h: b.height };
    }, html);
    const at = { above: { x: r.x, y: r.y - size.h - gap }, below: { x: r.x, y: r.bottom + gap }, inside: { x: r.x, y: r.y }, left: { x: r.x - size.w - gap, y: r.y }, right: { x: r.right + gap, y: r.y } }[place];
    if (!at) throw new Error('place: above · below · inside · left · right');
    await this.overlay(html, { x: at.x + dx, y: at.y + dy }, { clip });
    return { x: at.x + dx, y: at.y + dy, width: size.w, height: size.h, target: r };
  }
  /** 대상 요소 안에 html을 직접 넣습니다 (띠 · 칸 좌표계 그대로). 연표가 다시 그리면 사라지므로 m.freeze() 뒤에 쓰는 것을 권함 */
  async insertInto(target, html, { position = 'beforeend' } = {}) {
    const ok = await this.page.evaluate(({ target, html, position }) => {
      const el = window.__mockFind(target)[0];
      if (!el) return false;
      const t = document.createElement('template');
      t.innerHTML = html;
      for (const n of t.content.children) n.setAttribute('data-mock', '');
      el.insertAdjacentHTML(position, t.innerHTML);
      return true;
    }, { target, html, position });
    if (!ok) throw new Error('넣을 대상을 화면에서 찾지 못했습니다: ' + JSON.stringify(target));
    await this.page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  }
  /** 연표 다시 그리기를 멈춤 — 끼운 요소가 지워지지 않게 (찍은 뒤 unfreeze) */
  async freeze() {
    await this.page.evaluate(() => {
      const tl = window.__tl;
      if (tl.__frozen) return;
      tl.__frozen = { render: tl.render, draw: tl._draw };
      tl.render = () => {};
      tl._draw = () => {};
    });
  }
  async unfreeze() {
    await this.page.evaluate(() => {
      const tl = window.__tl;
      if (!tl.__frozen) return;
      delete tl.render;
      delete tl._draw;
      delete tl.__frozen;
      tl.render();
    });
    await this.settle();
  }
  /** 끼운 CSS · 층 · 요소를 모두 걷음 */
  async clearInjected() {
    await this.page.evaluate(() => document.querySelectorAll('[data-mock]').forEach(el => el.remove()));
  }

  /* ---------- 찍기 ---------- */
  /** 잠깐 떴다 사라지는 것을 걷음 — 밀려난 줄 알림(위로 · 아래로 밀려남) · 알림 글(토스트). cards: true면 묶음 카드 · 도읍 노선도 · 풍선도 */
  async quiet({ cards = false } = {}) {
    await this.page.evaluate(cards => {
      const tl = window.__tl;
      if (tl.hintEl) { clearTimeout(tl._hintTimer); clearTimeout(tl._hintOut); tl.hintEl.querySelectorAll('.tl-hint').forEach(p => p.classList.remove('is-in')); tl.hintEl.hidden = true; }
      document.querySelectorAll('.toast-box .toast').forEach(el => el.remove());
      if (cards) { tl.hideCard(true); tl.hideMetro(); }
    }, cards);
    await this.page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  }
  /** PNG로 찍기 — clip: 사각형 { x, y, width, height } 또는 대상(rect와 같은 꼴 — pad만큼 넓혀 자름). scale: 'css'(CSS 1px = 그림 1px · 기본) | 'device'(기기 배율).
      찍기 전에 m.quiet()로 밀려난 줄 알림 · 토스트를 걷음(transient: true면 그대로 둠) */
  async shot(file, { clip = null, pad = 0, scale = 'css', fullWidth = false, transient = false } = {}) {
    if (!transient) await this.quiet(); // 밀려난 줄 알림 · 토스트는 찍지 않음 (transient: true면 그대로)
    let box = null;
    if (clip) {
      box = isRect(clip) ? { ...clip } : await this.rect(clip);
      if (!box) throw new Error('찍을 대상을 화면에서 찾지 못했습니다: ' + JSON.stringify(clip));
      const W = this.viewport.width, H = this.viewport.height;
      let x = box.x - pad, y = box.y - pad, w = box.width + pad * 2, h = box.height + pad * 2;
      if (fullWidth) { x = 0; w = W; }
      x = Math.max(0, Math.floor(x)); y = Math.max(0, Math.floor(y));
      w = Math.min(W - x, Math.ceil(w)); h = Math.min(H - y, Math.ceil(h));
      box = { x, y, width: w, height: h };
    }
    fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
    await this.page.screenshot({ path: file, clip: box || undefined, scale, animations: 'disabled', caret: 'hide' });
    const { width, height } = pngSize(file);
    return { file: path.resolve(file), width, height };
  }
  /** 대상 둘레를 찍기 — pad(기본 24) · fullWidth면 가로는 화면 전체 */
  async shotOf(target, file, { pad = 24, fullWidth = false, scale = 'css' } = {}) {
    return this.shot(file, { clip: target, pad, fullWidth, scale });
  }

  async close() {
    try { await this.context.close(); } catch { /* 이미 닫힘 */ }
    openCount--;
    if (openCount <= 0) {
      openCount = 0;
      if (sharedBrowser) { try { await sharedBrowser.close(); } catch { /* 이미 닫힘 */ } sharedBrowser = null; }
      await stopServers();
    }
  }
}

/** PNG 파일의 가로 · 세로 (IHDR) */
export function pngSize(file) {
  const b = fs.readFileSync(file);
  if (b.length < 24 || b.toString('ascii', 1, 4) !== 'PNG') throw new Error('PNG가 아닙니다: ' + file);
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
}

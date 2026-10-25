// 리메이크 4단계 걸음 9 · 과제 7 걸음 1(7a) — 선반 길 판단 셈. 감독 결정(엔진 변형 길 · 배치 갈래 약 +6시간)의 근거라 커밋해 둔다(검토 지적 2026-10-25 —
//   처음에는 git 밖 prototype/results/remake4-shots/shelf/shelf-calc.mjs였다). 결과는 지금처럼 git 밖 prototype/results/remake4-shots/shelf/에.
// 물음: 서고 미리보기의 선반(js/timeline.js 3311 ~ 3327 — 켠 그릇의 구성원 가운데 중요도 → 기간 길이 → 시작 차례로 상위 shelfKeep(5)만 두고
//   나머지를 _hidden으로 숨긴 뒤 줄을 다시 지음)을 앱 길(엔진이 준 그릇 변형 scope:<uid>의 줄을 _variantRowsOff · 접힘과 같은 길로 숨김)로 같게 낼 수 있는가.
// 셈: 내보내기 JSON(remake3-same-check --one과 같은 길 — export/base.mjs bootWeb · contextOf · runModules)의 그릇 변형 줄 · 줄마다의 띠 · form 중요도 · 기간으로
//   상위 5 밖 구성원을 고르고 (가) 줄마다 모두 남음/모두 숨음으로 갈리는가 (나) 미리보기 DOM(메이커 · shelvedScopes)의 줄 차례와 같은가
//   (다) 앱이 고르는 값(구성원 · 중요도 · 기간)을 layout 답에서 얻는가(--engine: 실제 저장소를 지어 엔진 답을 봄)를 본다.
// 사용(작업 폴더에서):
//   node prototype/scripts/remake4-shelf-calc.mjs            내보내기 셈 + 미리보기 DOM + 엔진 답 → 표 · shelf/결과.json(표는 shelf/결과.txt로 받아 둠)
//   [--no-dom] [--no-engine] [--only=<경우>,…]
// 필요한 것: 엔진 도구 prototype/engine/target/release/archive-tool.exe · 달력 표 prototype/results/calendar-cache.json · playwright(HT_PLAYWRIGHT_ROOT)와 Edge(HT_BROWSER).
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scripts = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scripts, '..', '..');
const prototype = path.join(root, 'prototype');
/** 결과 폴더(git 밖) — 처음 셈과 같은 자리. */
const here = path.join(prototype, 'results', 'remake4-shots', 'shelf');
fs.mkdirSync(here, { recursive: true });
const NOW = '2026-10-15T12:00:00+09:00';
const KEEP = 5; // G_SEOGO.shelfKeep
const args = Object.fromEntries(process.argv.slice(2).map(a => { const m = a.match(/^--([^=]+)(?:=(.*))?$/); return m ? [m[1], m[2] ?? ''] : ['', a]; }));

const read = rel => JSON.parse(fs.readFileSync(path.join(root, rel), 'utf8'));

/** 경우: 있는 자료 둘(f4-federation · 등불) + 구성원 여섯 이상의 그릇을 덧댄 셋(있는 자료에는 그런 그릇이 없음 — 5단계 과제 9 기록과 같음). */
const CASES = {
  'f4-federation': { note: '가상 팩 그대로 — 연방 구성원은 소속(host 변형)', raw: () => read('prototype/fixtures/f4/f4-federation.json') },
  lantern: { note: '견본 등불 그대로 — 그릇 셋(구성원 2 · 5 · 2)', raw: () => read('samples/sample-lantern.json') },
  'f4-federation-scope': {
    note: '연방 구성원 열둘을 시대 그릇(s-fed)으로 — 중요도 섞임 · 구성원마다 제 사슬',
    raw: () => {
      const raw = read('prototype/fixtures/f4/f4-federation.json');
      raw.id = 'f4-federation-scope';
      for (const o of raw.objects) if (Array.isArray(o.within) && o.within.includes('o-fed')) o.within = ['s-fed'];
      raw.objects.push({ id: 's-fed', type: 'era', name: '적석 연방 영지들', track: 'jeokseok', start: 1150, end: 1650 });
      return raw;
    },
  },
  'lantern-flat': {
    note: '등불 하연에 그릇 하나 더 — 아홉 불씨 다섯 + 부흥 둘(구성원마다 제 사슬)',
    raw: () => {
      const raw = read('samples/sample-lantern.json');
      raw.scopes = (raw.scopes || []).concat([{ id: 'shelf-flat', name: '선반 시험 — 낱 사슬', track: 'hayeon', members: ['p-upper', 'p-lower', 'p-reed', 'p-bitnaru', 'p-mulangae', 'p-blackwater', 'p-namgang'] }]);
      return raw;
    },
  },
  'lantern-chain': {
    note: '등불 하연에 그릇 하나 더 — 큰 승계 사슬(등불 왕국 → … → 공화국)과 낱 사슬 넷',
    raw: () => {
      const raw = read('samples/sample-lantern.json');
      raw.scopes = (raw.scopes || []).concat([{ id: 'shelf-chain', name: '선반 시험 — 승계 사슬', track: 'hayeon',
        members: ['p-lantern', 'p-prefecture', 'p-revival', 'p-union', 'p-republic', 'p-upper', 'p-lower', 'p-blackwater', 'p-namgang'] }]);
      return raw;
    },
  },
};

const out = path.join(here, 'out');
fs.mkdirSync(out, { recursive: true });
const rawFile = name => path.join(out, `${name}.raw.json`);
const exportFile = name => path.join(out, `${name}.export.json`);

// ---- 자식: 경우 하나를 내보낸다(웹 코드는 한 프로세스에 한 번) ----
if (args.one) {
  const { installClock } = await import(pathToFileURL(path.join(prototype, 'scripts', 'oracle', 'clock.mjs')).href);
  installClock(NOW);
  const base = await import(pathToFileURL(path.join(prototype, 'scripts', 'export', 'base.mjs')).href);
  const HT = base.bootWeb();
  const raw = JSON.parse(fs.readFileSync(rawFile(args.one), 'utf8'));
  const ctx = base.contextOf(HT, [raw]);
  const o = await base.runModules(ctx, { has: m => fs.existsSync(path.join(prototype, 'scripts', 'export', `${m}.mjs`)) });
  // 엔진 변형 길이면 줄이 어떻게 되나: 내보내기의 배치기(줄 채우기 packRows 켬)에 서고의 선반 숨김을 켜고 그릇 하나씩 다시 쌓은 줄(띠 uid)
  o._shelfRows = {};
  for (const s of ctx.model.scopes || []) {
    const members = new Set();
    // 매번 새 문맥(앞 셈의 _hidden이 남지 않게) — 그 그릇만 켜고, 선반이면 서고 갈래(seogo)의 숨김을 켠다. 줄 채우기(packRows)는 내보내기 그대로 켬
    const rowsOf = shelf => {
      const c2 = base.contextOf(HT, [raw]);
      const tl = c2.tl;
      const tr = tl.tracks.find(t => t.id === s.track);
      tl.scopesOn = Object.fromEntries((c2.model.scopes || []).map(x => [x.uid, x.uid === s.uid]));
      tl.seogo = true;
      tl.shelvedScopes = new Set(shelf ? [s.uid] : []);
      tl._layoutTrack(tr);
      const claim = tl._scopeClaims(tr, new Map(tr.periods.map(p => [p.uid, p])));
      for (const p of tr.periods) if (claim.get(p.uid) && claim.get(p.uid).uid === s.uid) members.add(p.uid);
      return (tr.rowPeriods || []).map(list => (list || []).filter(p => !p._hidden && members.has(p.uid)).map(p => p.uid)).filter(x => x.length);
    };
    try {
      o._shelfRows[s.uid] = { open: rowsOf(false), shelf: rowsOf(true) };
    } catch (e) {
      o._shelfRows[s.uid] = { error: String(e).slice(0, 300) };
    }
  }
  fs.writeFileSync(exportFile(args.one), JSON.stringify(o) + '\n');
  process.exit(0);
}

const only = (args.only || '').split(',').filter(Boolean);
const names = Object.keys(CASES).filter(n => !only.length || only.includes(n));
for (const n of names) {
  fs.writeFileSync(rawFile(n), JSON.stringify(CASES[n].raw(), null, 1) + '\n');
  const r = spawnSync(process.execPath, [fileURLToPath(import.meta.url), `--one=${n}`], { encoding: 'utf8', maxBuffer: 1 << 28 });
  if (r.status !== 0) { console.error(`${n}: 내보내기 실패\n${(r.stderr || r.stdout).slice(-2000)}`); process.exit(1); }
}

const year = m => 1970 + m / 525949.2;
const fmtY = y => (y < 0 ? `BC${Math.round(-y)}` : `${Math.round(y)}`);

/** 앱의 트랙 안 줄 차례(layout.dart _chainOf) — 켠 변형 하나(v)의 덮어쓰기(after · ord)로. 켜지 않은 변형의 줄은 뺀다. */
function chainOf(track, v) {
  const n = track.rows.length;
  const off = new Set(), over = new Map();
  for (let r = 0; r < n; r++) if (track.rows[r].variant && (!v || track.rows[r].variant !== v.key)) off.add(r);
  if (v) for (const r of v.rows) over.set(r.row, r);
  const next = new Map();
  for (let r = 0; r < n; r++) {
    if (off.has(r)) continue;
    const o = over.get(r);
    const anchor = o ? o.after : r === 0 ? -1 : r - 1;
    if (!next.has(anchor)) next.set(anchor, []);
    next.get(anchor).push(r);
  }
  for (const kids of next.values()) kids.sort((a, b) => (over.get(a)?.ord ?? 0) - (over.get(b)?.ord ?? 0) || a - b);
  const order = [], seen = new Set(), stack = [...(next.get(-1) || [])].reverse();
  while (stack.length) {
    const r = stack.pop();
    if (seen.has(r)) continue;
    seen.add(r);
    order.push(r);
    const kids = next.get(r);
    if (kids) for (let i = kids.length - 1; i >= 0; i--) stack.push(kids[i]);
  }
  for (let r = 0; r < n; r++) if (!off.has(r) && !seen.has(r)) order.push(r);
  return order;
}

/** 내보내기 셈: 그릇마다 앱 길의 줄 · 띠 · 고름. */
function analyse(name) {
  const o = JSON.parse(fs.readFileSync(exportFile(name), 'utf8'));
  const ent = new Map(o.entities.map(e => [e.uid, e]));
  const body = uid => { const e = ent.get(uid); return e ? JSON.parse(e.json) : null; };
  const scopes = o.entities.filter(e => e.kind === 'scope').map(e => ({ uid: e.uid, body: JSON.parse(e.json) }));
  const res = { name, note: CASES[name].note, scopes: [], hostVariants: o.variants.filter(v => v.kind === 1).map(v => ({ key: v.key, rows: v.rows.length })) };
  for (const s of scopes) {
    const ti = o.tracks.findIndex(t => t.key === s.body.track);
    const track = o.tracks[ti];
    const v = o.variants.find(x => x.key === `scope:${s.uid}`);
    const members = (s.body.members || s.body.x_members || []).map(m => (typeof m === 'string' ? m : m.$ref || m.uid || m.name));
    const groupRows = new Set((v?.groups || []).flatMap(g => g.rows));
    const order = chainOf(track, v).filter(r => groupRows.has(r));
    // 줄마다의 띠(그 변형에서 보이는 것 — 기본 띠 + 그 변형의 띠 · 옮김은 내보내기가 싣는 moves)
    // 옮김(moves kind 1)은 띠 uid로 온다 — 그릇 둘에 든 구성원이 그 변형의 새 줄로 옮겨 갈 때
    const moved = new Map((v?.moves || []).filter(m => m.kind === 1).map(m => [m.ref, m.row]));
    const bandsOf = r => o.periods.filter(p => p.track === ti && (moved.has(p.uid) ? moved.get(p.uid) : p.row) === r && (!p.variant || p.variant === v.key));
    const rows = order.map(r => ({ row: r, bands: bandsOf(r) }));
    // 고르기 — 미리보기와 같은 셈: 중요도(없으면 −1) → 기간(바깥 끝 bandEnd − bandStart · 해) → 시작
    const info = new Map();
    for (const row of rows) for (const p of row.bands) {
      const b = body(p.uid) || {};
      const s0 = b.startRange ? b.startRange[0] : b.start, e0 = b.endRange ? b.endRange[1] : b.endY;
      const imp = typeof b.importance === 'number' ? b.importance : -1;
      const fimp = ((p.form >> 13) & 7) - 1;
      info.set(p.uid, { uid: p.uid, name: p.name, row: row.row, imp, fimp, len: e0 - s0, start: s0, minLen: year(p.end) - year(p.start), polityKind: b.polityKind || '' });
    }
    const list = [...info.values()];
    const sorted = list.slice().sort((a, b) => b.imp - a.imp || b.len - a.len || a.start - b.start);
    const kept = new Set(sorted.slice(0, KEEP).map(x => x.uid));
    const hidden = new Set(list.length > KEEP ? sorted.slice(KEEP).map(x => x.uid) : []);
    const verdict = rows.map(r => {
      const h = r.bands.filter(p => hidden.has(p.uid)).length;
      return { row: r.row, bands: r.bands.map(p => p.uid), kind: h === 0 ? '남음' : h === r.bands.length ? '숨음' : '섞임' };
    });
    const appShelf = verdict.filter(x => x.kind !== '숨음').map(x => x.bands);
    res.scopes.push({
      uid: s.uid, name: s.body.name, track: s.body.track, members: members.length, bandsInRows: list.length,
      formAgrees: list.every(x => x.imp === x.fimp), notMember: list.filter(x => !members.includes(x.uid)).map(x => x.uid),
      ranked: sorted.map(x => ({ uid: x.uid, name: x.name, imp: x.imp, len: Math.round(x.len), keep: kept.has(x.uid) && hidden.size > 0 })),
      hidden: [...hidden], rows: verdict, appOpen: rows.map(r => r.bands.map(p => p.uid)), appShelf,
      lenFromExport: list.every(x => Math.abs(x.len - x.minLen) < 1.5),
      engineWay: (o._shelfRows || {})[s.uid] || null,
    });
  }
  return res;
}

const results = names.map(analyse);

// ---- 미리보기 DOM(메이커 · shelvedScopes) ----
async function previewRows() {
  const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2' };
  const server = http.createServer((req, res) => {
    try {
      const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
      const file = path.resolve(root, rel);
      if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
      res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(fs.readFileSync(file));
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
  // 형식 4 원본은 메이커의 파일 열기처럼 옛 꼴로 내려 준다(remake4-shots makerDraft와 같은 길)
  const vm = await import('node:vm');
  const g = { console, setTimeout, clearTimeout, Intl, Math, Date, JSON };
  g.window = g; g.globalThis = g;
  vm.createContext(g);
  for (const rel of ['js/calendar.js', 'js/core.js']) vm.runInContext(fs.readFileSync(path.join(root, rel), 'utf8'), g, { filename: rel });
  const draftOf = name => {
    const raw = JSON.parse(fs.readFileSync(rawFile(name), 'utf8'));
    if (!(Number(raw.formatVersion) >= 4)) return raw;
    const d = g.HT.F4.down(JSON.parse(JSON.stringify(raw)), () => {});
    d.f4extras = g.HT.F4.extrasOf(raw);
    return d;
  };
  for (const r of results) {
    for (const s of r.scopes) {
      s.preview = {};
      for (const state of ['open', 'shelf']) {
        const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, locale: 'ko-KR' });
        const ui = { foldedSpheres: [], scopes: { [s.uid]: true }, shelvedScopes: state === 'shelf' ? [s.uid] : [] };
        await context.addInitScript(d => { localStorage.setItem('ht.maker.draft', JSON.stringify(d.draft)); localStorage.setItem('ht.maker.ui', '{}'); localStorage.setItem('ht.ui', JSON.stringify(d.ui)); }, { draft: draftOf(r.name), ui });
        const page = await context.newPage();
        const errors = [];
        page.on('pageerror', e => errors.push(String(e)));
        await page.goto(base + 'dlc-maker.html');
        await page.locator('#timeline .tl-track').first().waitFor({ timeout: 30000 });
        await page.waitForTimeout(800);
        const got = await page.evaluate(([uid, trackId]) => {
          const tl = HT.liveTimeline;
          const tr = tl.tracks.find(t => t.id === trackId);
          const st = tl.scopeStateOf(uid);
          // 줄 목록(rowPeriods — 줄 차례)의 띠 uid. 숨은(_hidden) 띠는 줄에 들지 않는다
          const rows = (tr.rowPeriods || []).map((list, i) => ({ i, uids: (list || []).filter(p => !p._hidden).map(p => p.uid) }));
          const shelf = tr._shelf && tr._shelf.get(uid) ? tr._shelf.get(uid).map(p => p.uid) : [];
          // DOM: 그 트랙의 띠 요소(data-row) — 줄 번호와 윗변
          const el = document.querySelector(`#timeline .tl-track[data-track="${CSS.escape(trackId)}"]`);
          const dom = el ? [...el.querySelectorAll('.tl-band[data-uid]')].map(b => ({ uid: b.dataset.uid, row: Number(b.dataset.row), top: Math.round(b.getBoundingClientRect().top) })) : [];
          const stags = el ? el.querySelectorAll('.tl-stag, [class*="shelf"]').length : 0;
          return { state: st, rows, shelf, dom, stags };
        }, [s.uid, s.track]);
        got.errors = errors;
        s.preview[state] = got;
        await context.close();
      }
    }
  }
  await browser.close();
  server.close();
}

if (!('no-dom' in args)) await previewRows();

// ---- 엔진 답(다): 저장소를 지어 layout · row_labels · entities · ids_of로 앱이 고를 값을 얻는가 ----
function engineAnswers() {
  const exe = path.join(prototype, 'engine', 'target', 'release', 'archive-tool.exe');
  const cal = path.join(prototype, 'results', 'calendar-cache.json');
  for (const r of results) {
    if (!r.scopes.some(s => s.members > KEEP)) continue;
    const db = path.join(out, `${r.name}.db`);
    fs.rmSync(db, { force: true });
    const b = spawnSync(exe, ['build', db, rawFile(r.name), `--now=${NOW}`, `--calendar=${cal}`], { encoding: 'utf8', maxBuffer: 1 << 26 });
    if (b.status !== 0) { r.engine = { error: (b.stderr || b.stdout).slice(-800) }; continue; }
    const q = obj => { const x = spawnSync(exe, ['query', db, JSON.stringify(obj)], { encoding: 'utf8', maxBuffer: 1 << 28 }); return x.status === 0 ? JSON.parse(x.stdout) : { error: x.stderr }; };
    const lay = q({ op: 'layout' });
    r.engine = {};
    for (const s of r.scopes) {
      if (s.members <= KEEP) continue;
      const v = (lay.variants || []).find(x => x.key === `scope:${s.uid}`);
      const groupRows = (v?.groups || []).flatMap(g => g.rows);
      const layoutKeys = v ? Object.keys(v).sort() : [];
      const rowKeys = v && v.rows[0] ? Object.keys(v.rows[0]).sort() : [];
      const hasBands = JSON.stringify(v || {}).includes('"band":') && false;
      const labels = q({ op: 'row_labels', rows: groupRows, variants: [v?.key].filter(Boolean) });
      const labelBands = (labels.labels || []).map(l => ({ row: l.row, items: (l.items || []).map(it => ({ uid: it.period, start: it.start, end: it.end })) }));
      const scopeEnt = q({ op: 'entity', uid: s.uid });
      const members = (() => { try { const b = JSON.parse(scopeEnt.json); return (b.members || []).map(m => m.$ref || m); } catch { return []; } })();
      const ents = q({ op: 'entities', uids: members });
      const ids = q({ op: 'ids_of', uids: members });
      const imp = {};
      for (const e of ents.entities || ents.items || (Array.isArray(ents) ? ents : [])) { try { const b = JSON.parse(e.json); imp[e.uid] = { importance: b.importance ?? null, startRange: b.startRange || null, endRange: b.endRange || null, start: b.start, endY: b.endY }; } catch { /* 빈 */ } }
      r.engine[s.uid] = { layoutKeys, rowKeys, hasBands, groupRows, labelBands, members, imp, entitiesKeys: Object.keys(ents), ids: ids.bands || ids };
    }
  }
}
if (!('no-engine' in args)) engineAnswers();

fs.writeFileSync(path.join(here, '결과.json'), JSON.stringify(results, null, 1) + '\n');

// ---- 표 ----
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
for (const r of results) {
  console.log(`\n## ${r.name} — ${r.note}`);
  if (!r.scopes.length) console.log(`  그릇 없음(소속 변형 ${r.hostVariants.map(h => `${h.key} 줄 ${h.rows}`).join(' · ') || '없음'}) — 미리보기에도 선반이 없다(scopeStateOf가 그릇만 봄)`);
  for (const s of r.scopes) {
    console.log(`  그릇 ${s.uid} '${s.name}' · 구성원 ${s.members} · 그릇 줄의 띠 ${s.bandsInRows} · form 중요도 = 기록 중요도: ${s.formAgrees ? '예' : '아니오'} · 줄 밖 구성원 아님 ${s.notMember.length}`);
    if (s.bandsInRows <= KEEP) { console.log(`    상위 ${KEEP} 안 — 숨는 구성원 없음(선반이 바꾸는 것 없음)`); }
    else {
      console.log(`    차례: ${s.ranked.map(x => `${x.name}(${x.imp}·${x.len}해)${x.keep ? '' : '×'}`).join(' → ')}`);
      const k = { 남음: 0, 숨음: 0, 섞임: 0 };
      for (const x of s.rows) k[x.kind]++;
      console.log(`    (가) 줄 ${s.rows.length}: 남음 ${k.남음} · 숨음 ${k.숨음} · 섞임 ${k.섞임}${k.섞임 ? ' — ' + s.rows.filter(x => x.kind === '섞임').map(x => `줄 ${x.row} [${x.bands.map(u => u.split('/')[1] + (s.hidden.includes(u) ? '×' : '')).join(' ')}]`).join(' · ') : ''}`);
    }
    if (s.preview) {
      for (const st of ['open', 'shelf']) {
        const pv = s.preview[st];
        const inScope = new Set(st === 'open' ? s.appOpen.flat() : s.appOpen.flat());
        const pvRows = pv.rows.map(x => x.uids.filter(u => inScope.has(u))).filter(x => x.length);
        const app = st === 'open' ? s.appOpen : s.appShelf;
        const ok = same(pvRows, app);
        console.log(`    (나) ${st === 'open' ? '펼침' : '선반'}: 미리보기 상태 ${pv.state} · 줄 ${pvRows.length} · 앱 길 줄 ${app.length} · ${ok ? '같음' : '다름'}${pv.shelf.length ? ` · 미리보기 선반 ${pv.shelf.length}` : ''}${pv.errors.length ? ` · 오류 ${pv.errors.length}` : ''}`);
        if (!ok) {
          console.log(`       미리보기: ${pvRows.map(x => '[' + x.map(u => u.split('/')[1]).join(' ') + ']').join(' ')}`);
          console.log(`       앱 길:    ${app.map(x => '[' + x.map(u => u.split('/')[1]).join(' ') + ']').join(' ')}`);
        }
      }
    }
    if (s.engineWay && s.bandsInRows > KEEP) {
      const w = s.engineWay;
      if (w.error) console.log(`    엔진 변형 길 셈 실패: ${w.error}`);
      else {
        const pvShelf = s.preview ? s.preview.shelf.rows.map(x => x.uids.filter(u => new Set(s.appOpen.flat()).has(u))).filter(x => x.length) : null;
        console.log(`    엔진 변형 길(내보내기 배치기 · 줄 채우기 + 선반 숨김): 펼침 줄 ${w.open.length}(앱 길 펼침과 ${same(w.open, s.appOpen) ? '같음' : '다름'}) · 선반 줄 ${w.shelf.length}${pvShelf ? `(미리보기 선반과 ${same(w.shelf, pvShelf) ? '같음' : '다름 — 줄 채우기(앱만)의 차이'})` : ''}: ${w.shelf.map(x => '[' + x.map(u => u.split('/')[1]).join(' ') + ']').join(' ')}`);
      }
    }
    const e = r.engine && r.engine[s.uid];
    if (e) {
      console.log(`    (다) layout 답의 그릇 변형 칸: ${e.layoutKeys.join(',')} · 줄 칸: ${e.rowKeys.join(',')} — 띠(구성원)는 없음`);
      console.log(`        row_labels(변형 켬) 그릇 줄 ${e.labelBands.length}: 띠 ${e.labelBands.reduce((n, l) => n + l.items.length, 0)} · entities 답 칸 ${e.entitiesKeys.join(',')} · 중요도 있는 구성원 ${Object.values(e.imp).filter(x => x.importance != null).length}/${e.members.length} · 바깥 범위 있는 구성원 ${Object.values(e.imp).filter(x => x.startRange || x.endRange).length}`);
    }
  }
}
console.log(`\n저장: ${path.relative(root, path.join(here, '결과.json'))}`);

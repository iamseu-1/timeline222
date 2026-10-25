// 렌즈 내보내기 점검(D5 결정 5 A · 6 B의 새 앱 몫 — 모듈 prototype/scripts/export/lens.mjs · 설계 docs/설계-10건/7-8-단체와-렌즈.md '구현 기록(새 앱 — 렌즈)').
//
//   ① 옛 열쇠 바이트 같음: 같은 조합을 렌즈 모듈을 건너뛰어(= 고치기 전의 출력) 한 번, 넣어 한 번 내보내 견준다 —
//      칸 · 일반 항목 · 변형 밖의 열쇠는 글자까지 같고, 칸 · 일반 항목 · 변형은 옛것이 **앞부분 그대로**이며 뒤에 붙은 것은 모두 렌즈의 것
//      (칸 종류 8 · 구역 43 · 변형 kind 4)이고, 항목 기록은 themes 기록에 `x_lens` 하나만 더해졌다(그것을 빼면 글자까지 같다).
//   ② 렌즈 자료의 꼴: 칸의 단(0 · 1) · 단 갈래(style 27~29 — 1 · 2 · 3 · 4) · 구역 43이 갈래 1 · 2 칸마다 하나 · 가림이 옛 칸의 지도자 · 지위 칸만 ·
//      가리는 띠에 그 렌즈의 칸이 있음 · x_lens의 주제 차례 = 모델의 주제 사전 차례 · slot의 트랙이 HT.lensAny인 정권을 품음 · 사건 uid가 실린 사건.
//   ③ (선택 --fixtures) 앱 고정 자료: prototype/app/test/fixtures/lens-<견본>.json — themes 기록(엔진 entity 답의 json) · 렌즈 변형 · 칸 · 구역 43 · 트랙 열쇠.
//      (옛 견본 power · groups · lens에서 뜨던 power-base.json · d5-windows.json은 그 견본을 지운 뒤 다시 뜨지 않는다 — 고정 자료로 그대로 둔다.)
//   ④ (선택 --tool <archive-tool>) 저장소 짓기: import-layout → verify-tiles(누락 · 중복 0) — 무거운 검사라 PC 몫(docs/작업-지시/10건-PC-검사-D5.md).
//
// 웹 코드(js · samples · packs · index.html)는 --web <git 판>(기본 HEAD — 같은 작업 폴더의 다른 작업자가 고치는 중인 js/core.js · js/timeline.js를 피함) ·
// --web live(작업 트리)에서 임시 폴더(HT_LENS_TMP — 기본 prototype/results/lens-check)에 거울로 펴고, 내보내기 모듈은 작업 트리의 것을 얹는다.
// 사용: node prototype/scripts/lens-export-check.mjs [--web HEAD|live|<판>] [--samples lantern] [--east-asia] [--fixtures] [--tool <archive-tool>]
//       --samples는 samples/sample-<이름>.json의 이름(쉼표 — 기본 lantern: 견본 등불 연대기 · 주제 다섯 + 숨긴 기본 렌즈 넷 · 단체 · 제도 · 지위).
// 견본 · 기본팩은 읽기만 한다. 견본의 이름은 가상이다.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { useCalendarCopy } from './oracle/cal-copy.mjs';

useCalendarCopy('lens-export-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROTOTYPE = path.resolve(HERE, '..');
const ROOT = path.resolve(PROTOTYPE, '..');
const arg = (name, fallback = null) => {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
};
const flag = name => process.argv.includes(name);

const web = arg('--web', 'HEAD');
const samples = (arg('--samples', 'lantern') || '').split(',').map(s => s.trim()).filter(Boolean);
const tool = arg('--tool', process.env.HT_ARCHIVE_TOOL || '');
const TMP = process.env.HT_LENS_TMP || path.join(PROTOTYPE, 'results', 'lens-check');
const mirror = path.join(TMP, `mirror-${web.replace(/[^\w.-]/g, '_')}`);
const eastAsia = flag('--east-asia');

/* ── 거울: 웹 코드는 고른 판, 내보내기 모듈은 작업 트리 ─────────────────────────────── */
fs.rmSync(mirror, { recursive: true, force: true });
fs.mkdirSync(mirror, { recursive: true });
const webParts = ['js', 'samples', ...(eastAsia ? ['packs', 'index.html'] : [])];
if (web === 'live') {
  for (const part of webParts) fs.cpSync(path.join(ROOT, part), path.join(mirror, part), { recursive: true });
} else {
  const tar = execFileSync('git', ['-C', ROOT, 'archive', '--format=tar', web, ...webParts], { maxBuffer: 1 << 30 });
  execFileSync('tar', ['-x', '-C', mirror], { input: tar });
}
const exportDir = path.join(mirror, 'prototype', 'scripts', 'export');
fs.mkdirSync(exportDir, { recursive: true });
for (const f of fs.readdirSync(path.join(PROTOTYPE, 'scripts', 'export'))) {
  if (f.endsWith('.mjs')) fs.copyFileSync(path.join(PROTOTYPE, 'scripts', 'export', f), path.join(exportDir, f));
}
const base = await import(pathToFileURL(path.join(exportDir, 'base.mjs')).href);
const lensMod = await import(pathToFileURL(path.join(exportDir, 'lens.mjs')).href);
const HT = base.bootWeb();
assert.equal(typeof HT.lensCellsOf, 'function', `웹 코드(${web})에 렌즈 도우미(HT.lensCellsOf)가 없습니다`);

const report = { 웹: web, 조합: {}, 문제: [] };
const problem = (where, text) => report.문제.push(`${where}: ${text}`);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** 견줄 조합: 견본 하나씩(+ 선택: 동아시아 기본팩). */
const configs = samples.map(s => ({ name: s, raws: [JSON.parse(fs.readFileSync(path.join(mirror, 'samples', `sample-${s}.json`), 'utf8'))] }));
if (eastAsia) {
  const html = fs.readFileSync(path.join(mirror, 'index.html'), 'utf8');
  const files = [...html.matchAll(/<script src="(packs\/east-asia\/[^"]+\.js)"/g)].map(m => m[1]);
  for (const f of files) base.runScript(f);
  configs.push({ name: 'east-asia', raws: [HT.getBuiltinPacks()[0]] });
}

const BAND = lensMod.LENS_BAND;
const bandOf = style => (style >> 27) & 7;

for (const cfg of configs) {
  const where = cfg.name;
  const t0 = Date.now();
  const before = await base.runModules(base.contextOf(HT, cfg.raws), { skip: new Set(['lens']) });
  const ctx = base.contextOf(HT, cfg.raws);
  const after = await base.runModules(ctx);
  const ms = Date.now() - t0;
  const row = { 시간ms: ms };

  /* ① 옛 열쇠 바이트 같음 */
  const keysA = Object.keys(before), keysB = Object.keys(after);
  for (const k of keysA) if (!keysB.includes(k)) problem(where, `열쇠 ${k}이(가) 사라졌습니다`);
  for (const k of keysB) if (!keysA.includes(k) && k !== 'variants') problem(where, `모르는 열쇠 ${k}이(가) 생겼습니다`);
  for (const k of keysA) {
    if (['cells', 'items', 'variants', 'entities'].includes(k)) continue;
    if (!same(before[k], after[k])) problem(where, `열쇠 ${k}의 값이 달라졌습니다`);
  }
  const prefix = (k, test) => {
    const a = before[k] || [], b = after[k] || [];
    if (b.length < a.length) return problem(where, `${k}이(가) 줄었습니다(${a.length} → ${b.length})`);
    for (let i = 0; i < a.length; i++) if (!same(a[i], b[i])) return problem(where, `${k}[${i}]이(가) 달라졌습니다`);
    const added = b.slice(a.length);
    added.forEach((x, i) => {
      const why = test(x);
      if (why) problem(where, `${k}에 덧붙은 ${a.length + i}번: ${why}`);
    });
    return added;
  };
  const cells = prefix('cells', c => (c.kind !== lensMod.KIND_COMMON ? `칸 종류 ${c.kind}` : !/^theme:/.test(c.variant || '') ? `변형 ${c.variant}` : '')) || [];
  const items = prefix('items', it => (it.section !== 43 || it.a !== lensMod.KIND_COMMON ? `구역 ${it.section} · a ${it.a}` : !/^theme:/.test(it.variant || '') ? `변형 ${it.variant}` : '')) || [];
  const variants = prefix('variants', v => (v.kind !== lensMod.VARIANT_KIND_THEME || !/^theme:/.test(v.key) ? `변형 ${v.key} kind ${v.kind}` : '')) || [];
  if (before.entities.length !== after.entities.length) problem(where, `항목 기록 수 ${before.entities.length} → ${after.entities.length}`);
  let xLens = null;
  before.entities.forEach((e, i) => {
    const f = after.entities[i];
    if (!f || f.uid !== e.uid || f.kind !== e.kind || f.pack !== e.pack) return problem(where, `항목 기록 ${i}(${e.uid})의 자리가 달라졌습니다`);
    if (f.json === e.json) return;
    if (e.uid !== 'themes') return problem(where, `항목 기록 ${e.uid}이(가) 달라졌습니다`);
    const body = JSON.parse(f.json);
    xLens = body.x_lens || null;
    delete body.x_lens;
    if (JSON.stringify(body) !== e.json) problem(where, 'themes 기록이 x_lens 밖에서 달라졌습니다');
  });
  if (!xLens) {
    const rec = after.entities.find(e => e.uid === 'themes');
    xLens = rec ? JSON.parse(rec.json).x_lens || null : null;
  }

  /* ② 렌즈 자료의 꼴 */
  const { model, tl } = ctx;
  const baseBands = new Set(before.periods.filter(p => !p.variant).map(p => p.uid));
  const perVariant = {};
  for (const v of variants) {
    const mine = cells.filter(c => c.variant === v.key);
    const myItems = items.filter(it => it.variant === v.key);
    const id = v.key.slice('theme:'.length);
    if (v.uid !== id) problem(where, `${v.key}: uid ${v.uid}`);
    const styles = { 1: 0, 2: 0, 3: 0, 4: 0 };
    for (const c of mine) {
      const b = bandOf(c.style);
      styles[b] = (styles[b] || 0) + 1;
      if (!baseBands.has(c.period)) problem(where, `${v.key}: 칸이 기본 띠가 아닌 ${c.period}에`);
      if (![BAND.inst, BAND.group, BAND.rank, BAND.leader].includes(b)) problem(where, `${v.key}: 단 갈래 ${b}`);
      const lanes = b === BAND.leader ? [lensMod.LENS_LANE.rank, lensMod.LENS_LANE.power] : [lensMod.LENS_LANE.leader];
      if (!lanes.includes(c.lane)) problem(where, `${v.key}: 갈래 ${b}의 단 ${c.lane}`);
      if (b === BAND.rank && id !== 'system') problem(where, `${v.key}: 지위로 대신한 칸은 체제 렌즈만`);
      if (b === BAND.leader && (c.lane === lensMod.LENS_LANE.rank ? id !== 'system' : id !== 'faction')) problem(where, `${v.key}: 내린 지도자 칸(단 ${c.lane})의 렌즈`);
      if (b === BAND.group && id !== 'faction') problem(where, `${v.key}: 단체 칸(갈래 2)은 붕당 렌즈만`); // 붕당 렌즈도 단체 자료가 없는 나라는 제도 칸(갈래 1)
      if (b === BAND.group && (!(c.style & 32) || !c.name.includes('\t'))) problem(where, `${v.key}: 단체 칸의 이름 꼴 ${c.name}`);
      if (c.start > c.end) problem(where, `${v.key}: 칸의 기간이 뒤집혔습니다`);
    }
    const want = styles[BAND.inst] + styles[BAND.group];
    if (myItems.length !== want) problem(where, `${v.key}: 구역 43 ${myItems.length}개 ≠ 갈래 1 · 2 칸 ${want}개`);
    for (const it of myItems) {
      if (!it.text2 || it.text2.startsWith('\t')) problem(where, `${v.key}: 구역 43에 누를 항목 uid가 없습니다(${it.ref})`);
      // 단체 칸의 색 점: 연정(둘째 색이 있음)은 점이 둘 이상, 짝을 모르는 연정(d 1)은 하나, 한 단체의 집권은 없음
      const dots = it.text2.includes('\t') ? it.text2.split('\t')[1].split(',') : [];
      if (dots.some(x => !/^[0-9a-f]{6}$/.test(x))) problem(where, `${v.key}: 색 점 꼴 ${it.text2}`);
      const wantDots = it.d === 1 ? dots.length === 1 : it.color ? dots.length >= 2 : dots.length === 0;
      if (!wantDots) problem(where, `${v.key}: 색 점 ${dots.length}개(d ${it.d} · 둘째 색 ${it.color})`);
      if (it.d && id !== 'faction') problem(where, `${v.key}: 짝을 모르는 연정은 붕당 렌즈만`);
    }
    const hidBands = new Set();
    for (const h of v.hides) {
      const c = before.cells[h.at];
      if (h.kind !== 3 || !c) {
        problem(where, `${v.key}: 가림 ${JSON.stringify(h)}이(가) 옛 칸 밖`);
        continue;
      }
      if (c.kind !== 1 && !(c.kind === 5 && id === 'system') && !(c.kind === lensMod.KIND_COMMON && c.lane === lensMod.LENS_LANE.power && id === 'faction')) problem(where, `${v.key}: 가린 칸의 종류 ${c.kind}`);
      hidBands.add(c.period);
    }
    const lensBands = new Set(mine.map(c => c.period));
    for (const b of hidBands) if (!lensBands.has(b)) problem(where, `${v.key}: 가린 띠 ${b}에 렌즈 칸이 없습니다`);
    perVariant[v.key] = { 칸: mine.length, 갈래: styles, 구역43: myItems.length, 가림: v.hides.length };
  }
  row.렌즈 = perVariant;
  if (!xLens) {
    if (variants.length) problem(where, '렌즈 변형이 있는데 x_lens가 없습니다');
    row.x_lens = '없음';
  } else {
    const ids = (model.themes || []).map(t => t.id);
    if (!same(xLens.themes.map(t => t.id), ids)) problem(where, `x_lens의 주제 차례 ${xLens.themes.map(t => t.id)} ≠ 사전 ${ids}`);
    for (const t of xLens.themes) {
      const v = variants.find(x => x.key === `theme:${t.id}`);
      if (!!t.v !== !!v) problem(where, `x_lens ${t.id}: v ${t.v} · 변형 ${!!v}`);
      if (t.v && !t.has) problem(where, `x_lens ${t.id}: 변형이 있는데 has 0`);
      if (t.hint !== HT.themeHint(model.themes.find(x => x.id === t.id))) problem(where, `x_lens ${t.id}: 한마디 ${t.hint}`);
      const evUids = new Set(after.events.map(e => e.uid));
      for (const u of t.ev || []) if (!evUids.has(u)) problem(where, `x_lens ${t.id}: 사건 ${u}이(가) 실리지 않았습니다`);
    }
    const keys = new Set(after.tracks.map(t => t.key));
    for (const k of xLens.slot) {
      if (!keys.has(k)) problem(where, `slot의 트랙 ${k}이(가) 없습니다`);
      const tr = tl.tracks.find(x => x.id === k);
      if (!tr || !tr.periods.some(p => HT.lensAny(p))) problem(where, `slot의 트랙 ${k}에 렌즈 자료가 없습니다`);
    }
    row.x_lens = { slot: xLens.slot, 주제: xLens.themes.map(t => `${t.id}${t.hidden ? '(숨김)' : ''}${t.has ? '' : '(자료 없음)'}${t.v ? '·변형' : ''}${t.ev ? `·사건${t.ev.length}` : ''}`) };
  }
  row.덧붙음 = { 칸: cells.length, 구역43: items.length, 변형: variants.length };
  report.조합[where] = row;

  /* ③ 앱 고정 자료 */
  if (flag('--fixtures') && xLens) {
    const rec = after.entities.find(e => e.uid === 'themes');
    const fixture = {
      note: `lens-export-check.mjs가 sample-${where}에서 뜬 렌즈 자료(웹 ${web}) — 손으로 고치지 않는다`,
      themes: rec.json,
      tracks: after.tracks.map(t => ({ key: t.key, leader: t.leader, rows: t.rows.length })),
      variants: variants.map(v => ({ key: v.key, kind: v.kind, uid: v.uid, name: v.name, hides: v.hides.length })),
      cells: cells.map(c => ({ variant: c.variant, period: c.period, lane: c.lane, start: c.start, end: c.end, name: c.name, style: c.style, color: c.color })),
      items: items.map(it => ({ variant: it.variant, ref: it.ref, b: it.b, c: it.c, name: it.name, color: it.color, d: it.d, text2: it.text2 })),
    };
    const file = path.join(PROTOTYPE, 'app', 'test', 'fixtures', `lens-${where}.json`);
    fs.writeFileSync(file, JSON.stringify(fixture, null, 1) + '\n');
    row.고정자료 = path.relative(ROOT, file);
  }

  /* ④ 저장소 짓기(선택) */
  if (tool) {
    const dir = path.join(TMP, `store-${where}`);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    const plan = path.join(dir, 'layout.json');
    fs.writeFileSync(plan, JSON.stringify(after));
    const pack = path.join(dir, 'pack.htpack');
    fs.writeFileSync(pack, await HT.packFile.build(cfg.raws[0]));
    const db = path.join(dir, 'archive.db');
    execFileSync(tool, ['import-layout', pack, plan, db], { stdio: 'pipe' });
    const verify = execFileSync(tool, ['verify-tiles', db, '200'], { encoding: 'utf8' });
    row.verify = verify.trim().split('\n').slice(-2).join(' · ');
  }
}

fs.mkdirSync(TMP, { recursive: true });
fs.writeFileSync(path.join(TMP, 'lens-export-check.json'), JSON.stringify(report, null, 1) + '\n');
console.log(JSON.stringify(report, null, 1));
if (report.문제.length) {
  console.log(`문제 ${report.문제.length}개`);
  process.exit(1);
}
console.log('문제 없음');

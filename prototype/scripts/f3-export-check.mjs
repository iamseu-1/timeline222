// 형식 3 내보내기 점검(A1-a — 설계 docs/설계-10건/A-아카이브-이음.md 4-2). 견본 등불 연대기(samples/sample-lantern.json — 형식 3의 칸을 거의 다 씀)
// 하나와, 동아시아 기본팩 위에 그것을 얹은 조합을 내보내기 모듈(export/base.mjs의
// contextOf · runModules — 노드 도구 export-layout.mjs · 메이커 일꾼과 같은 길)로 내보내고 다음을 본다:
//   ① 표: 모델에 있는 수 = 갈래별 항목 기록 수(정권 · 사건 · 인물 · 시대 구분 · 대범위 · 가문 · 단체 · 제도 · 지명 · 성씨 · 주제 · 판 · 지도 · 글꼴)
//   ② 고리: 본문의 $ref · 미리 푼 값(x_)의 uid · 구성원의 나라(nation) · 찾을 글의 빌린 줄(x_find.row)이 모두 제 기록을 가리킨다(매달린 것 0)
//   ③ 귀속: 기록마다 pack(배치 packs[] 순번)이 그 항목을 낸 DLC와 같다 — 저절로 생긴 지명 · 성씨 · 가문은 쓴 항목의 가장 앞선 DLC
//   ④ 크기: 항목 기록 MB · 미리 푼 값(x_) MB · 찾을 글(x_find) MB · 배치 파일 MB
//   ⑤ 앱 고정 자료: prototype/app/test/fixtures/f3-<견본>.json — 그 견본의 항목 기록(보조 달력 표 cal:은 뺌 — 크다) {uid, kind, json}(엔진 entity 답의 꼴)
//   (선택) HT_ARCHIVE_TOOL=<archive-tool 경로>: 가져오기(import-layout) → verify-tiles 2000(누락 · 중복 0) · 가져오기 시간 ·
//          entity lantern-chronicle/g-pearl(단체) · 동아시아 + 등불 연대기의 "휘씨"(가문)가 제 자료집(packs:[2] — 엔진의 자료집 번호는 1부터)에서만 찾힘
// 사용: node prototype/scripts/f3-export-check.mjs [--no-fixtures]
//   → prototype/results/compat/f3-<이름>.json(배치) · <견본>.htpack(원본 전용 팩) · f3-export-check.json(보고) · (선택) prototype/data/f3-<이름>/archive.db
// 견본 · 기본팩은 읽기만 한다. 견본 이름은 가상이다.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { bootWeb, contextOf, runModules, runScript, root, prototype } from './export/base.mjs';
import { useCalendarCopy } from './oracle/cal-copy.mjs';

useCalendarCopy('f3-export-check'); // 공용 달력 표(results/calendar-cache.json)를 갈지 않게 — 이 프로세스와 자식은 제 TMP의 사본을 쓴다(판정 R64 넘김 · oracle/cal-copy.mjs)

const SAMPLES = ['lantern'];
const writeFixtures = !process.argv.includes('--no-fixtures');
const compat = path.join(prototype, 'results', 'compat');
const fixtures = path.join(prototype, 'app', 'test', 'fixtures');
fs.mkdirSync(compat, { recursive: true });
const tool = process.env.HT_ARCHIVE_TOOL || '';
const MB = n => Math.round((n / 1048576) * 1000) / 1000;
const readSample = name => JSON.parse(fs.readFileSync(path.join(root, 'samples', `${name}.json`), 'utf8'));

const HT = bootWeb();
/** 내장 DLC(packs/<이름>/*.js)를 index.html이 싣는 차례 그대로 돌려 원본을 얻는다(export/base.mjs의 loadContext와 같은 길). */
const builtinRaw = (() => {
  const memo = new Map();
  return name => {
    if (memo.has(name)) return memo.get(name);
    const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
    const files = [...html.matchAll(/<script src="(packs\/[^"]+\.js)"/g)].map(m => m[1]).filter(f => f.startsWith(`packs/${name}/`));
    assert.ok(files.length, `index.html에 packs/${name}/ 의 스크립트가 없습니다`);
    for (const file of files) runScript(file);
    const packs = HT.getBuiltinPacks();
    assert.equal(packs.length, 1, `내장 DLC가 하나여야 합니다(지금 ${packs.length}개)`);
    memo.set(name, packs[0]);
    return packs[0];
  };
})();
const configs = [
  ...SAMPLES.map(s => ({ name: s, files: [`sample-${s}`] })),
  { name: 'east-asia-lantern', builtin: 'east-asia', files: ['sample-lantern'] }, // 동아시아 기본팩 위에 견본을 얹은 조합(자료집 귀속 대조)
];
const report = { 견본: {}, 문제: [] };
const problem = (where, text) => report.문제.push(`${where}: ${text}`);

for (const cfg of configs) {
  const names = [...(cfg.builtin ? [cfg.builtin] : []), ...cfg.files]; // 배치 packs[]의 차례(첫째가 기본)
  const raws = [...(cfg.builtin ? [builtinRaw(cfg.builtin)] : []), ...cfg.files.map(readSample)];
  const ctx = contextOf(HT, raws, names.slice(1));
  const out = await runModules(ctx);
  const { model } = ctx;
  const where = cfg.name;
  const row = { 팩: out.packs.map(p => `${p.id}${p.version ? `@${p.version}` : ''}${p.category ? `(${p.category})` : ''}`) };

  /* ① 모델 수 = 갈래별 기록 수 */
  const kindOf = x => x.itemKind || HT.itemKindOf(x) || x.kind;
  const want = {};
  const count = (list, kind) => {
    for (const x of list || []) {
      const k = kind || kindOf(x);
      want[k] = (want[k] || 0) + 1;
    }
  };
  count(model.periods);
  count(model.events);
  count(model.figures, 'figure');
  count(model.lineageFigures, 'figure'); // D1: 계보 전용 인물도 갈래 figure 기록(띠 인물과 함께 셈)
  count(model.epochs, 'epoch');
  count(model.scopes, 'scope');
  count(model.houses, 'house');
  count(model.groups, 'group');
  count(model.institutions, 'institution');
  count(model.places, 'place');
  count(model.surnames, 'surname');
  count(model.views, 'view');
  count(model.maps, 'map');
  count(model.fonts, 'font');
  if ((model.themes || []).length) want.themes = 1;
  const got = {};
  for (const e of out.entities) if (e.kind !== 'doc' && e.kind !== 'cal' && e.kind !== 'kin') got[e.kind] = (got[e.kind] || 0) + 1; // kin(D1 계보 뼈대 — 모델 항목이 아님)은 따로 셈
  const table = {};
  for (const k of new Set([...Object.keys(want), ...Object.keys(got)])) {
    table[k] = `${want[k] || 0} → ${got[k] || 0}`;
    if ((want[k] || 0) !== (got[k] || 0)) problem(where, `${k} 모델 ${want[k] || 0} · 기록 ${got[k] || 0}`);
  }
  row.모델_기록 = table;
  row.문서 = out.entities.filter(e => e.kind === 'doc').length;
  row.보조달력 = out.entities.filter(e => e.kind === 'cal').length;
  row.계보뼈대 = out.entities.filter(e => e.kind === 'kin').length; // D1 — 검사는 prototype/scripts/kin-export-check.mjs

  /* ② 고리 — 기록마다 본문을 다시 풀어 훑는다(내보내기 안의 점검과 따로 한 번 더) */
  const uids = new Set(out.entities.map(e => e.uid));
  assert.equal(uids.size, out.entities.length, `${where}: 항목 기록의 uid가 겹칩니다`);
  let refs = 0;
  let xLinks = 0;
  let dangling = 0;
  let xBytes = 0;
  let findBytes = 0;
  let bytes = 0;
  const xKeys = {};
  const walk = (v, inX, from) => {
    if (Array.isArray(v)) return v.forEach(q => walk(q, inX, from));
    if (!v || typeof v !== 'object') return;
    if (typeof v.$ref === 'string') {
      refs++;
      if (!uids.has(v.$ref)) {
        dangling++;
        problem(where, `매달린 $ref ${from} → ${v.$ref}`);
      }
    }
    if (inX) {
      for (const key of ['uid', 'nation']) {
        if (typeof v[key] !== 'string' || !v[key]) continue;
        xLinks++;
        if (!uids.has(v[key])) {
          dangling++;
          problem(where, `매달린 x_ 고리 ${from} → ${v[key]}`);
        }
      }
    }
    for (const k of Object.keys(v)) walk(v[k], inX || k.startsWith('x_'), from);
  };
  for (const e of out.entities) {
    bytes += e.json.length;
    const body = JSON.parse(e.json);
    walk(body, false, e.uid);
    for (const [k, v] of Object.entries(body)) {
      if (!k.startsWith('x_')) continue;
      const n = JSON.stringify(v).length;
      xBytes += n;
      xKeys[k] = (xKeys[k] || 0) + 1;
      if (k === 'x_find') {
        findBytes += n;
        if (v.row) {
          xLinks++;
          if (!uids.has(v.row)) {
            dangling++;
            problem(where, `찾을 글의 빌린 줄이 없음 ${e.uid} → ${v.row}`);
          }
        }
      }
    }
  }
  row.고리 = { 본문_ref: refs, x_고리: xLinks, 매달림: dangling };
  row.x_열쇠 = xKeys;

  /* ③ 귀속 — 모델의 packId로 따로 셈한 기댓값과 견줌 */
  const packIndex = new Map(out.packs.map((p, i) => [p.id, i]));
  const items = new Map();
  for (const list of [model.periods, model.events, model.figures, model.lineageFigures, model.epochs, model.scopes, model.houses, model.groups, model.institutions, model.places, model.surnames, model.views, model.maps, model.fonts])
    for (const x of list || []) items.set(x.uid, x);
  const ofPackId = id => (packIndex.has(id) ? packIndex.get(id) : null);
  const ofItem = x => (x && x.packId ? ofPackId(x.packId) : null) ?? (x && typeof x.uid === 'string' && x.uid.includes('/') ? ofPackId(x.uid.split('/')[0]) : null) ?? 0;
  const autoOf = (x, users) => {
    const list = users.filter(v => v != null);
    return list.length ? Math.min(...list) : 0;
  };
  const expect = new Map();
  const placePack = (pl, seen = new Set()) => {
    if (pl.packId) return ofItem(pl);
    if (seen.has(pl.id)) return null;
    seen.add(pl.id);
    return autoOf(pl, [
      ...(pl.uses || []).map(u => (u.item ? ofItem(u.item) : u.mapId && model.mapMap.get(u.mapId) ? ofItem(model.mapMap.get(u.mapId)) : null)),
      ...(pl.children || []).map(id => (model.placeMap.get(id) ? placePack(model.placeMap.get(id), seen) : null)),
    ]);
  };
  const housePack = h => (h.packId ? ofItem(h) : autoOf(h, (h.members || []).map(m => (m.item ? ofItem(m.item) : null))));
  for (const [uid, x] of items) {
    const k = kindOf(x);
    expect.set(uid, k === 'place' ? placePack(x) : k === 'house' ? housePack(x) : k === 'surname' ? (x.packId ? ofItem(x) : autoOf(x, (x.houses || []).map(id => housePack(model.houseMap.get(id))))) : ofItem(x));
  }
  const byPack = {};
  let wrong = 0;
  for (const e of out.entities) {
    byPack[e.pack] = (byPack[e.pack] || 0) + 1;
    if (typeof e.pack !== 'number' || e.pack < 0 || e.pack >= out.packs.length) {
      wrong++;
      problem(where, `pack이 없거나 범위 밖 ${e.uid} → ${e.pack}`);
      continue;
    }
    let want = expect.get(e.uid);
    if (e.kind === 'cal' || e.kind === 'themes') want = 0;
    if (e.kind === 'doc') {
      const key = e.uid.slice(4);
      const rec = model.docs.get(key);
      if (rec && rec.packId) want = ofPackId(rec.packId) ?? 0;
      else continue; // 본문 없는 문서(중간 단계 · 고리의 목적지)는 바탕의 DLC — 따로 셈하지 않는다
    }
    if (want == null) continue;
    if (e.pack !== want) {
      wrong++;
      problem(where, `귀속이 다름 ${e.uid}: ${e.pack} (기대 ${want})`);
    }
  }
  row.귀속 = { 팩별_기록: byPack, 어긋남: wrong };

  /* ④ 크기 */
  const file = path.join(compat, `f3-${cfg.name}.json`);
  const text = JSON.stringify(out) + '\n';
  fs.writeFileSync(file, text);
  // 항목 기록 · 미리 푼 값은 글자 수(계약 6-9 가의 6.9MB와 같은 셈), 배치 파일은 바이트(UTF-8).
  row.크기 = { 항목기록MB_글자: MB(bytes), 미리푼값MB_글자: MB(xBytes), 찾을글MB_글자: MB(findBytes), 배치파일MB: MB(Buffer.byteLength(text)) };

  // 원본 전용 팩(가져오기가 원본을 품는다) — 견본마다 <견본>.htpack, 이미 있으면 그대로(같은 파일에서 만든다).
  const packFiles = [];
  for (const [i, f] of names.entries()) {
    const pf = path.join(compat, `${f}.htpack`);
    if (!fs.existsSync(pf)) fs.writeFileSync(pf, await HT.packFile.build(raws[i]));
    packFiles.push(pf);
  }

  /* ⑤ 앱 고정 자료 — 견본 하나씩만(기본팩을 얹은 조합은 크다) */
  if (writeFixtures && SAMPLES.includes(cfg.name)) {
    const list = out.entities.filter(e => e.kind !== 'cal').map(e => ({ uid: e.uid, kind: e.kind, json: e.json }));
    fs.writeFileSync(path.join(fixtures, `f3-${cfg.name}.json`), JSON.stringify(list, null, 1) + '\n');
    row.고정자료 = `prototype/app/test/fixtures/f3-${cfg.name}.json (${list.length}개)`;
  }

  /* (선택) 엔진으로 가져오기 · 타일 검사 */
  if (tool) {
    const dir = path.join(prototype, 'data', `f3-${cfg.name}`);
    const db = path.join(dir, 'archive.db');
    fs.mkdirSync(dir, { recursive: true });
    for (const f of [db, `${db}-wal`, `${db}-shm`]) if (fs.existsSync(f)) fs.rmSync(f); // 이 점검이 지은 저장소만 다시 짓는다
    const t0 = Date.now();
    execFileSync(tool, ['import-layout', packFiles[0], file, db, ...packFiles.slice(1)], { stdio: ['ignore', 'pipe', 'pipe'] });
    const ms = Date.now() - t0;
    const verify = JSON.parse(execFileSync(tool, ['verify-tiles', db, '2000']).toString().trim().split('\n').pop());
    const ask = q => JSON.parse(execFileSync(tool, ['query', db, JSON.stringify(q)]).toString());
    row.엔진 = { 가져오기ms: ms, 저장소MB: MB(fs.statSync(db).size), 타일: verify.타일, 누락_중복: verify.누락_중복 };
    if (verify.누락_중복 !== 0) problem(where, `verify-tiles 누락 · 중복 ${verify.누락_중복}`);
    if (cfg.name === 'lantern') {
      const e = ask({ op: 'entity', uid: 'lantern-chronicle/g-pearl' });
      row.엔진.단체기록 = e && e.kind === 'group' ? '답함' : '없음';
      if (!(e && e.kind === 'group')) problem(where, 'entity lantern-chronicle/g-pearl가 답하지 않습니다');
    }
    if (cfg.name === 'east-asia-lantern') {
      const hit = p => ask({ op: 'search', text: '휘씨', kinds: ['house'], packs: p }).items.map(x => x.uid);
      row.엔진.휘씨 = { 'packs:[2]': hit([2]), 'packs:[1]': hit([1]) };
      if (!hit([2]).includes('house:h-hwi') || hit([1]).length) problem(where, '"휘씨"가 제 자료집(packs:[2])에서만 찾혀야 합니다');
    }
  }
  report.견본[cfg.name] = row;
}

fs.writeFileSync(path.join(compat, 'f3-export-check.json'), JSON.stringify(report, null, 1) + '\n');
console.log(JSON.stringify(report, null, 1));
if (report.문제.length) {
  console.error(`문제 ${report.문제.length}건`);
  process.exit(1);
}
console.log('문제 없음');

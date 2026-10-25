// 정답지 자료 하나를 뽑는 자식 프로세스 — `prototype/scripts/layout-oracle.mjs`가 자료마다 환경 `TZ=Asia/Seoul` · `HT_ORACLE_NOW`를 정해 띄운다.
// 웹 코드(js/*.js)와 내보내기 모듈(export/*.mjs)은 **읽기만** 한다 — Node 내보내기 결과가 곧 정답지다.
//
// 쓰는 법(직접 부를 일은 거의 없다 — 아래 인자는 부모가 만들어 준다):
//   TZ=Asia/Seoul HT_ORACLE_NOW=2026-10-15T12:00:00+09:00 node prototype/scripts/oracle/one.mjs --name=<자료> --out=<폴더> [--seams=norm,prep,rows,out,mods[,emul]] [--upto=<모듈>,…] [--packs=<경로>|<경로>…]
//   emul     mods의 자체 점검 하나를 더 돈다(기본에 들지 않음 — Node 흉내: 새 문맥에 pre-<k−1>과 .shared를 심고 모듈 하나만 돌려 pre-<k> · late-<모듈>과 바이트 같음 · 자료마다 수 초).
//   --packs  입력 DLC를 같은 순번의 파일(.htpack · .json)로 갈아 끼운다(빈 칸은 원래 입력 · 칸 수는 입력 수와 같아야 함). f4-same-check.mjs가 형식 4로 바꾼 팩 · 굳힌 내장 팩으로
//            같은 길을 돌려 보려고 쓴다. 정답지(layout-oracle.mjs)는 쓰지 않는다 — 갈아 끼우면 머리 `$oracle.sources`가 그 파일이 된다.
//   base 해석은 sample → builtin → file 차례다(둘 이상이 있으면 앞이 입력 · 뒤는 굳힌 사본 — 예: {"builtin":"east-asia","file":"east-asia.json"}은 정답지를
//   내장 팩에서 뽑고, 굳힌 파일은 Rust 검사 · f4-same-check가 읽는다).
//
// 무엇을 쓰나(폴더 <out>을 비우고 그 아래에, 모두 JSON · 맨 위 열쇠 `$oracle`에 시각 · 시간대 · 원본 파일 SHA-256 앞 12자 · 웹 코드 판 `rules` · ICU 판 `icu`):
//   norm-<i>.json   ① 팩마다(0 = 기본 DLC) JSON.stringify(HT.normalizePack(raw).pack) — raw는 그때그때 새로 읽는다(normalizePack이 raw를 바꿀 수 있으므로)
//   prep.json       ② 줄 배정 전의 연표 상태: _layoutTrack을 빈 함수로 두고 contextOf → seam({tracks, depth, cats, proxies, cityUses, scopes, model})
//   rows.json       ② 줄 배정 뒤의 같은 덤프(contextOf 그대로)
//   upto-<모듈>.json ③ 모듈 앞자리(MODULES에서 그 모듈까지)만 돌린 runModules 출력 — --upto가 없으면 스물 모두(= upto-lens.json). 앞자리마다 문맥을 새로 만든다(모듈이 tl을 바꾸므로).
//   pre-<모듈>.json · pre-<모듈>.shared.json · late-<모듈>.json · upto-<모듈>.json(스물 — upto-lens는 out 이음매의 것과 같은 바이트)
//                   ③' 모듈 하나씩(이음매 mods — 과제 8-틀): 문맥 하나에서 contribute를 MODULES 차례로 돌리며 모듈 k 뒤마다
//                      out(`pre-<k>` — 늦은 차례 전)과 모듈끼리 나눠 쓰는 값 ctx.shared의 덤프(`pre-<k>.shared` — seam 규칙 · Map은 $map · Set은 $set)를 찍고,
//                      같은 자리의 out 사본에 앞자리 k개의 늦은 차례를 돌려 `upto-<k>`(runModules와 같은 값 — 아래 자체 점검)를 찍는다.
//                      스물 모두 돈 뒤 늦은 차례(contributeLate)를 하나 돌릴 때마다 `late-<모듈>`(tracks · docs · power · metro)을 찍는다 — `late-metro` = `upto-lens`.
//                      Rust는 모듈 k 하나를 `pre-<k−1>`(+ `.shared`)을 심고 돌려 `pre-<k>`와, 늦은 차례 하나를 앞 `late-`(처음은 `pre-lens`)를 심고 돌려 `late-<모듈>`과 견준다.
//   notes.json      ③'' (mods와 함께 · 과제 X — 판정 R29) 출력에 실리지 않는 알림 가운데 Rust와 견줄 것: `{"집합보기":{"뺀판":[…]}}` — 집합 보기에서
//                      판 하나가 오류로 빠진 목록과 그 까닭(boards.mjs의 notes.뺀판). Rust는 boards 하나를 `pre-variants`를 심고 돌려 같은 목록 · 같은 글인지 본다.
//   lens-on.json    ③''' (mods와 함께 · 과제 X — 판정 R25 선택 5) 렌즈 켬 배치(lens.mjs ② — themeLens를 켜고 모든 트랙을 다시 배치)의 트랙마다
//                      `{id, leaderH, height, rowHs}` — out에 실리지 않는 값이라 따로 찍는다. Rust는 같은 문맥에 themeLens를 켜고 layout_all 뒤 같은 값인지 본다.
//   덤프 규칙은 ./seam.mjs의 머리말.
//
// 보이지 않는 입력도 못 박는다:
//   · 오늘과 시간대 — 진행 중 정권의 끝(HT.CURRENT_YEAR · HT.NOW_T) · 문서의 나이 · [date]가 **지역** 연 · 월 · 일에 달린다. 정답지는 2026-10-15T12:00:00+09:00 · Asia/Seoul로 고정한다.
//   · HT.F4.split = true · buildModel(…, { groupBands: true }) · 글자 폭 = UTF-16 길이 × 7 — 모두 export/base.mjs(bootWeb · contextOf)가 한다.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

// ── 시각 · 시간대 고정 ── base.mjs(→ core.js가 싣는 순간 new Date().getFullYear()를 셈)를 가져오기 **전에** 깐다.
const NOW_TEXT = process.env.HT_ORACLE_NOW || '';
const TZ_NAME = 'Asia/Seoul';
if (process.env.TZ !== TZ_NAME || new Date(0).getTimezoneOffset() !== -540) {
  throw new Error(`시간대가 ${TZ_NAME}(UTC+9)이 아닙니다 — TZ=${process.env.TZ} · 오프셋 ${new Date(0).getTimezoneOffset()}분. layout-oracle.mjs로 돌리세요.`);
}
const RealDate = globalThis.Date;
/** 인자 없는 new Date() · Date.now() · Date()만 정한 시각 — 인자 있는 생성 · Date.UTC · Date.parse는 원래 것(./clock.mjs). 시각이 아니면 여기서 던진다. */
const NOW = (await import('./clock.mjs')).installClock(NOW_TEXT);

const base = await import('../export/base.mjs');
const { seam } = await import('./seam.mjs');
const { loadBuiltin, clone } = await import('./builtin.mjs');
const { rules } = await import('../lay-rules.mjs');
const { listFile } = await import('./ktl.mjs');
const { bootWeb, contextOf, runModules, importModule, MODULES, assert, prototype: protoDir, root } = base;

// ── 인자 ──
const args = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), ''] : [a.slice(2, i), a.slice(i + 1)]; }));
const csv = text => (text || '').split(',').map(s => s.trim()).filter(Boolean);
const SEAMS = args.seams === undefined ? ['norm', 'prep', 'rows', 'out', 'mods'] : csv(args.seams);
for (const s of SEAMS) assert.ok(['norm', 'prep', 'rows', 'out', 'mods', 'emul'].includes(s), `모르는 이음매: ${s} (norm · prep · rows · out · mods · emul)`);
assert.ok(!SEAMS.includes('emul') || SEAMS.includes('mods'), 'emul(Node 흉내 자체 점검)은 mods와 함께 돌립니다: --seams=mods,emul');
const UPTO = args.upto ? csv(args.upto) : ['lens'];
for (const m of UPTO) assert.ok(MODULES.includes(m), `모르는 모듈: ${m}`);
assert.ok(args.name && args.out, '--name=<자료> --out=<폴더>가 필요합니다');

// ── 자료 목록에서 이 자료 ──
const fixDir = path.join(protoDir, 'fixtures', 'oracle');
const list = JSON.parse(fs.readFileSync(path.join(fixDir, 'list.json'), 'utf8'));
const fixture = list.find(f => f.name === args.name);
assert.ok(fixture, `list.json에 없는 자료: ${args.name}`);
const outDir = path.resolve(args.out);
// 폴더를 비우고 새로 쓴다(판정 R58 ⑤-4 — 옛 이음매 · 옛 모듈 이름의 파일이 낡은 채 남지 않게). --seams로 일부만 뽑으면 나머지 파일도 사라진다.
// 정답지 폴더에는 이 도구가 쓰는 .json만 있다 — 다른 것이 있으면(엉뚱한 --out) 지우지 않고 멈춘다.
if (fs.existsSync(outDir)) {
  const strange = fs.readdirSync(outDir, { withFileTypes: true }).filter(e => !(e.isFile() && e.name.endsWith('.json')));
  assert.ok(!strange.length, `--out 폴더에 정답지(.json) 밖의 것이 있어 비우지 않습니다: ${outDir} — ${strange.map(e => e.name).join(' · ')}`);
  fs.rmSync(outDir, { recursive: true, force: true });
}
fs.mkdirSync(outDir, { recursive: true });

const sha12 = bytes => crypto.createHash('sha256').update(bytes).digest('hex').slice(0, 12);
const abs = (file, dir) => (path.isAbsolute(file) ? file : path.join(dir, file));

// ── 웹 코드를 한 번만 싣는다 ──
const HT = bootWeb();

/** 입력 하나: { label, source: {name, sha}, fresh: async () => raw } — 첫째가 기본 DLC, 나머지는 켠 차례. */
const fileInput = (file, name) => {
  const bytes = fs.readFileSync(file);
  const label = name || path.basename(file);
  const isPack = /\.htpack$/i.test(file);
  return {
    label,
    source: { name: label, sha: sha12(bytes) },
    // .htpack은 형식 4면 읽는 길이 옛 꼴로 내려 준다(HT.packFile.parse) — .json은 그대로(형식 4면 normalizePack이 내린다).
    fresh: async () => (isPack ? (await HT.packFile.parse(new Uint8Array(bytes))).raw : JSON.parse(bytes.toString('utf8'))),
  };
};
/** 내장 DLC(packs/<이름>/*.js)는 index.html이 싣는 차례 그대로 돌려 모은다(./builtin.mjs — export/base.mjs의 loadContext와 같은 방식). */
const builtinInput = name => {
  const { files, text, pack } = loadBuiltin(HT, name);
  return { label: `packs/${name}`, source: { name: `packs/${name}(${files.length}파일)`, sha: sha12(text) }, fresh: async () => clone(pack) };
};
// base는 sample → builtin → file 차례로 하나를 입력으로 본다(위 머리말). 입력은 갈아 끼울 때를 위해 '만드는 함수'로 먼저 모은다 — 갈아 끼운 칸의 내장 DLC는 싣지 않는다.
const makers = [];
if (fixture.base.sample) makers.push(() => fileInput(path.join(root, 'samples', `${fixture.base.sample}.json`), `samples/${fixture.base.sample}.json`));
else if (fixture.base.builtin) makers.push(() => builtinInput(fixture.base.builtin));
else if (fixture.base.file) makers.push(() => fileInput(abs(fixture.base.file, fixDir)));
else throw new Error(`base가 sample · builtin · file 중 하나여야 합니다: ${JSON.stringify(fixture.base)}`);
for (const file of fixture.extra || []) makers.push(() => fileInput(listFile(fixDir, file))); // 옛 KTL 자리는 HT_KTL로(./ktl.mjs)
const swaps = args.packs ? args.packs.split('|') : [];
assert.ok(!swaps.length || swaps.length === makers.length, `--packs의 칸 수(${swaps.length})가 입력 수(${makers.length})와 다릅니다`);
/** 입력 목록: 첫째가 기본 DLC, 나머지는 켠 차례. */
const inputs = makers.map((make, i) => (swaps[i] ? fileInput(path.resolve(swaps[i])) : make()));

const freshRaws = async () => Promise.all(inputs.map(i => i.fresh()));
const labels = inputs.slice(1).map(i => i.label);
// 머리의 rules · icu(판정 R58 ⑤-4): 정답지를 낸 웹 코드 · 내보내기 모듈의 판(lay-rules.mjs의 rules() — Rust `lay::RULES`와 같은 셈)과 이 Node의 ICU 판.
// Rust `tests/common/oracle.rs`의 `oracle()`이 지금 원본의 지문 · 잘린 달력 표의 ICU와 견줘 다르면 '정답지가 낡음'으로 멈춘다(입력 DLC는 sources).
const RULES_NOW = rules();
const ICU_NOW = process.versions.icu || '';
const header = seamName => ({ now: NOW_TEXT, tz: TZ_NAME, fixture: fixture.name, seam: seamName, sources: inputs.map(i => i.source), rules: RULES_NOW, icu: ICU_NOW });
const written = [];
/** 머리(`$oracle`)를 맨 앞에 붙여 파일로 — 본문(JSON 글)은 한 글자도 바꾸지 않는다. */
function write(file, seamName, bodyText) {
  const head = `{"$oracle":${JSON.stringify(header(seamName))}`;
  if (!bodyText.startsWith('{')) throw new Error(`${file}: 본문이 객체가 아닙니다`);
  fs.writeFileSync(path.join(outDir, file), `${head}${bodyText === '{}' ? '' : ','}${bodyText.slice(1)}\n`);
  written.push(file);
}
const t0 = RealDate.now();

// ── ① norm ──
if (SEAMS.includes('norm')) {
  const raws = await freshRaws();
  for (const [i, raw] of raws.entries()) {
    const norm = HT.normalizePack(raw);
    assert.ok(norm.pack, `DLC를 읽을 수 없습니다(${inputs[i].label}): ${(norm.errors || []).map(e => e.msg).join(' · ')}`);
    write(`norm-${i}.json`, `norm-${i}`, JSON.stringify(norm.pack));
  }
}

/** ②의 덤프 — 줄 배정 전 · 뒤가 같은 열쇠. */
const dumpOf = ctx => seam({ tracks: ctx.tl.tracks, depth: ctx.tl.depth, cats: ctx.tl._cats, proxies: ctx.tl._proxies, cityUses: ctx.tl._cityUses, scopes: ctx.tl._scopes, model: ctx.model });

// ── ② prep(줄 배정 전) ──
if (SEAMS.includes('prep')) {
  const proto = HT.Timeline.prototype;
  const layoutTrack = proto._layoutTrack;
  proto._layoutTrack = function () {};
  try {
    write('prep.json', 'prep', dumpOf(contextOf(HT, await freshRaws(), labels)));
  } finally {
    proto._layoutTrack = layoutTrack;
  }
}
// ── ② rows(줄 배정 뒤) ──
if (SEAMS.includes('rows')) write('rows.json', 'rows', dumpOf(contextOf(HT, await freshRaws(), labels)));

// ── ③ out(모듈 앞자리 k개) ──
if (SEAMS.includes('out')) {
  const has = name => fs.existsSync(path.join(protoDir, 'scripts', 'export', `${name}.mjs`));
  for (const upto of UPTO) {
    const skip = new Set(MODULES.slice(MODULES.indexOf(upto) + 1));
    const ctx = contextOf(HT, await freshRaws(), labels); // 앞자리마다 새로 — 모듈이 tl을 바꾼다
    const out = await runModules(ctx, { skip, has });
    write(`upto-${upto}.json`, `upto-${upto}`, JSON.stringify(out));
  }
}

// ── ③' mods(모듈 하나씩 — 과제 8-틀) ──
// runModules(export/base.mjs)의 걸음을 하나씩 밟는다. base.mjs는 읽기만 하므로 그 앞부분(빈 out · packInfo · 간지 설정)을 여기 옮겨 적었다 —
// 어긋남은 끝의 자체 점검(여기서 밟은 upto-tracks · 스물 모두 + 늦은 차례가 진짜 runModules의 출력과 바이트까지 같은가)이 막는다.
if (SEAMS.includes('mods')) {
  const ctx = contextOf(HT, await freshRaws(), labels);
  ctx.shared = {};
  ctx.notes = {};
  const packInfo = p => {
    const o = { id: p.id, name: p.name || p.id };
    if (typeof p.version === 'string' && p.version.trim()) o.version = p.version.trim();
    if (typeof p.category === 'string' && p.category.trim()) o.category = p.category.trim();
    return o;
  };
  const out = { name: ctx.raw.name, packs: ctx.packs.map(packInfo), categories: [], tracks: [], epochs: [], axis: [], periods: [], cells: [], events: [], items: [], entities: [] };
  if (ctx.model.yearCycle) {
    out.yearCycle = JSON.parse(JSON.stringify(ctx.model.yearCycle));
    out.yearCycles = ctx.packs.filter(p => p.yearCycle !== undefined && p.yearCycle !== null).map(p =>
      Object.assign(p.yearCycle === false ? { off: true } : JSON.parse(JSON.stringify(p.yearCycle)), { packId: p.id, packName: p.name }));
  }
  const mods = new Map();
  for (const name of MODULES) mods.set(name, await importModule(name));
  /** 앞자리 k개의 늦은 차례를 out의 사본에 돌린 것(= runModules의 upto-<k>). 늦은 차례는 ctx · out만 읽고 tl · 모델을 바꾸지 않는다. */
  const withLate = async k => {
    const copy = JSON.parse(JSON.stringify(out));
    for (const name of MODULES.slice(0, k + 1)) {
      const mod = mods.get(name);
      if (mod.contributeLate) await mod.contributeLate(ctx, copy);
    }
    return JSON.stringify(copy);
  };
  const uptoText = {};
  for (const [k, name] of MODULES.entries()) {
    await mods.get(name).contribute(ctx, out);
    write(`pre-${name}.json`, `pre-${name}`, JSON.stringify(out));
    write(`pre-${name}.shared.json`, `pre-${name}.shared`, seam(ctx.shared));
    uptoText[name] = await withLate(k);
    write(`upto-${name}.json`, `upto-${name}`, uptoText[name]); // upto-lens는 out 이음매의 것과 같은 바이트(아래 자체 점검)
  }
  const lateText = {};
  for (const name of MODULES) {
    const mod = mods.get(name);
    if (!mod.contributeLate) continue;
    await mod.contributeLate(ctx, out);
    lateText[name] = JSON.stringify(out);
    write(`late-${name}.json`, `late-${name}`, lateText[name]);
  }
  // 출력에 실리지 않는 알림 가운데 Rust와 견줄 것(과제 X · 판정 R29 — 머리말의 notes.json): 판 하나가 오류로 빠지면 out에는 '그 판이 없다'만 남아,
  // Rust와 Node가 다른 까닭으로 같은 판을 빼도 out은 같다. 그래서 까닭 글까지 찍는다. 흔들리는 값(시각 · 크기)은 싣지 않는다 — 두 번 뽑아 같은 바이트.
  write('notes.json', 'notes', JSON.stringify({ 집합보기: { 뺀판: (ctx.notes.집합보기 || {}).뺀판 || [] } }));
  // 렌즈 켬 동안의 줄 높이(과제 X · 판정 R25 선택 5 — 머리말의 lens-on.json): lens.mjs ②는 themeLens를 켜고 모든 트랙을 다시 배치해 자체 점검만 하고 되돌린다 —
  // 그 배치의 값(트랙마다 지도자 자리 · 줄 높이 · 높이)은 out에 실리지 않아 Rust와 견줄 정답지가 없었다. 새 문맥에서 같은 켬을 해 찍는다(lens.mjs와 같은 themeLens 값).
  {
    const c = contextOf(HT, await freshRaws(), labels);
    c.tl.themeLens = { id: '*', name: '*', color: '#a4b1b7' };
    for (const tr of c.tl.tracks) c.tl._layoutTrack(tr);
    write('lens-on.json', 'lens-on', JSON.stringify({ tracks: c.tl.tracks.map(tr => ({ id: tr.id, leaderH: tr.geo.leaderH, height: tr.height, rowHs: tr.rowHs.slice() })) }));
  }
  // 자체 점검: 여기서 밟은 길이 진짜 runModules와 바이트까지 같다(앞자리 하나 · 스물 모두 — 옮겨 적은 앞부분 · 늦은 차례의 차례가 어긋나면 여기서 멈춘다).
  const has = name => fs.existsSync(path.join(protoDir, 'scripts', 'export', `${name}.mjs`));
  for (const [upto, text] of [['tracks', uptoText.tracks], ['lens', JSON.stringify(out)]]) {
    const skip = new Set(MODULES.slice(MODULES.indexOf(upto) + 1));
    const real = JSON.stringify(await runModules(contextOf(HT, await freshRaws(), labels), { skip, has }));
    assert.equal(text, real, `mods 이음매의 upto-${upto}가 runModules의 출력과 다릅니다`);
  }
  assert.equal(uptoText.lens, JSON.stringify(out), 'mods 이음매: 스물 모두의 늦은 차례 사본이 제자리 결과와 다릅니다');

  // ── emul(Node 흉내 — 과제 8-틀 고침 1회차 · 검토의 emul.mjs를 붙임): Rust export_one · export_late의 전제를 Node 쪽에서 먼저 지킨다 —
  //    **새 문맥**(contextOf)에 pre-<k−1>(JSON)과 그 .shared(되심음 — $map · $set을 Map · Set으로)를 심고 모듈 k 하나만 돌리면 pre-<k> · pre-<k>.shared와 바이트까지 같고,
  //    늦은 차례도 앞 late-(처음은 pre-lens)와 pre-lens.shared를 심어 하나만 돌리면 late-<모듈>과 같다. 모듈이 tl · 모델 · 전역에 남긴 것이 뒤 모듈에 닿으면 여기서 갈린다.
  //    자료마다 새 문맥 24개를 더 짓는다(21개 자료에 약 1분) — 기본 이음매에 들지 않는다(`--seams=…,emul`).
  if (SEAMS.includes('emul')) {
    const unseam = v => {
      if (Array.isArray(v)) return v.map(unseam);
      if (v && typeof v === 'object') {
        if (Array.isArray(v.$map)) return new Map(v.$map.map(([k, x]) => [unseam(k), unseam(x)]));
        if (Array.isArray(v.$set)) return new Set(v.$set.map(unseam));
        if ('$ref' in v) throw new Error(`emul: shared 덤프에 모델 객체 참조가 있습니다(${v.$ref})`);
        return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, unseam(x)]));
      }
      return v;
    };
    const firstDiff = (a, b) => { let i = 0; while (i < a.length && a[i] === b[i]) i++; return `${i}바이트째 — 흉내 …${a.slice(Math.max(0, i - 80), i + 80)}… / 정답지 …${b.slice(Math.max(0, i - 80), i + 80)}…`; };
    const same = (what, got, want) => assert.ok(got === want, `emul 자체 점검: ${what}이 다릅니다 — ${firstDiff(got, want)}`);
    const preText = {}, sharedText = {};
    for (const name of MODULES) { preText[name] = fs.readFileSync(path.join(outDir, `pre-${name}.json`), 'utf8'); sharedText[name] = fs.readFileSync(path.join(outDir, `pre-${name}.shared.json`), 'utf8'); }
    /** 정답지 파일 글 → 본문 JSON(머리 $oracle을 뗌). */
    const bodyOf = text => { const v = JSON.parse(text); delete v.$oracle; return v; };
    /** 본문 글이 정답지 파일 글과 같은가(머리를 같은 꼴로 다시 붙여 견줌 — write와 같은 꼴). */
    const fileText = (seamName, bodyText) => `{"$oracle":${JSON.stringify(header(seamName))}${bodyText === '{}' ? '' : ','}${bodyText.slice(1)}\n`;
    const initialOut = c => {
      const o = { name: c.raw.name, packs: c.packs.map(packInfo), categories: [], tracks: [], epochs: [], axis: [], periods: [], cells: [], events: [], items: [], entities: [] };
      if (c.model.yearCycle) {
        o.yearCycle = JSON.parse(JSON.stringify(c.model.yearCycle));
        o.yearCycles = c.packs.filter(p => p.yearCycle !== undefined && p.yearCycle !== null).map(p =>
          Object.assign(p.yearCycle === false ? { off: true } : JSON.parse(JSON.stringify(p.yearCycle)), { packId: p.id, packName: p.name }));
      }
      return o;
    };
    for (const [k, name] of MODULES.entries()) {
      const c = contextOf(HT, await freshRaws(), labels);
      c.notes = {};
      let o;
      if (k === 0) { c.shared = {}; o = initialOut(c); }
      else { const prev = MODULES[k - 1]; c.shared = unseam(bodyOf(sharedText[prev])); o = bodyOf(preText[prev]); }
      await mods.get(name).contribute(c, o);
      same(`pre-${name}(새 문맥 + 앞자리를 심고 하나만)`, fileText(`pre-${name}`, JSON.stringify(o)), preText[name]);
      same(`pre-${name}.shared`, fileText(`pre-${name}.shared`, seam(c.shared)), sharedText[name]);
    }
    let prevLate = null;
    for (const name of MODULES) {
      const mod = mods.get(name);
      if (!mod.contributeLate) continue;
      const c = contextOf(HT, await freshRaws(), labels);
      c.notes = {};
      c.shared = unseam(bodyOf(sharedText.lens));
      const o = bodyOf(prevLate ? lateText[prevLate] : preText.lens);
      await mod.contributeLate(c, o);
      same(`late-${name}(새 문맥 + 앞 늦은 차례를 심고 하나만)`, JSON.stringify(o), lateText[name]);
      prevLate = name;
    }
    written.push('(emul 자체 점검 통과)');
  }
}

console.log(JSON.stringify({ fixture: fixture.name, files: written, ms: RealDate.now() - t0 }));

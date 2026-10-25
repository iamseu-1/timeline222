// 배포용 웹 폴더 두 개 만들기 — 연표와 DLC 메이커는 따로 포장합니다(메이커 → 연표 한 방향).
//   dist/web    연표 프로그램: 메이커 파일(dlc-maker.html · js/maker.js · js/maker-shell.js · css/maker.css · js/fieldpop.js)을 뺍니다
//   dist/maker  메이커 프로그램: 메이커와 미리보기용 연표(index.html)까지 모두. manifest는 원본의 maker.webmanifest를
//               manifest.webmanifest라는 이름으로 넣으므로, 이 폴더의 html은 고치지 않아도 메이커 manifest를 가리킵니다
// 허용 목록에 있는 파일만 복사합니다(.git, docs, src-tauri, node_modules 같은 것이 앱에 섞여 들어가지 않게 하는 안전장치).
// 복사한 뒤 폴더마다 검사하고, 하나라도 걸리면 실패(종료 코드 1)합니다.
//   ① html의 <script src> · <link href> · <a href="….html">가 가리키는 파일이 그 폴더에 있는지
//   ② manifest의 시작 화면 · 아이콘 · 바로 가기 · 파일 연결이 가리키는 파일이 있는지
//   ③ 연표 폴더에 메이커 파일이 없는지
// 그리고 sw.js의 PRECACHE를 그 폴더에 실제로 있는 파일만으로 걸러 쓰고(없는 파일이 하나라도 있으면 서비스 워커 설치가
// 통째로 실패하므로), 캐시 이름 앞머리(PREFIX)를 폴더마다 달리합니다 — 연표 'ht-' · 메이커 'htm-'.
// 두 폴더를 같은 주소(origin)에 올려도 서로의 캐시를 옛 캐시로 여겨 지우지 않습니다.
// fs.cpSync 는 한글 경로에서 Node가 죽는 일이 있어 직접 복사합니다.
import { rmSync, mkdirSync, existsSync, statSync, readdirSync, copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname, posix } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 메이커에서만 쓰는 파일 — 연표 폴더에는 들어가면 안 됩니다 */
const MAKER_ONLY = ['dlc-maker.html', 'js/maker.js', 'css/maker.css', 'js/fieldpop.js', 'js/form-keys.js', 'js/maker-history.js', 'js/maker-grid.js', 'js/maker-paste.js', 'js/maker-drag.js', 'js/maker-blocks.js', 'js/maker-find.js', 'js/maker-shell.js', 'js/maker-kin.js', 'js/maker-check.js', 'js/maker-images.js', 'js/maker-templates.js'];
/** 두 폴더가 함께 쓰는 것 (지도(지도/)는 보류 — 배포에 넣지 않음) */
const COMMON = ['index.html', 'sw.js', 'css', 'js', 'packs', 'icons', 'fonts'];
/** 기본 글꼴 세 굵기 · 한자 대체 글꼴과 이용 안내 — 이 목록만 배포하고 오프라인 캐시에 빠짐없이 싣는다. */
const FONT_FILES = ['fonts/Pretendard-Regular.otf', 'fonts/Pretendard-SemiBold.otf', 'fonts/Pretendard-Bold.otf', 'fonts/Pretendard-OFL.txt', 'fonts/ChosunKm.ttf', 'fonts/ChosunKm-LICENSE.txt'];

// 검사 원본 JSON은 그대로 두고, 배포용 견본은 제품과 같은 저장기로 전용 팩을 만듭니다.
globalThis.window = globalThis;
await import('../js/packfile.js');
const sampleFiles = new Map();
for (const name of readdirSync(join(root, 'samples')).filter(n => n.endsWith('.json'))) {
  const raw = JSON.parse(readFileSync(join(root, 'samples', name), 'utf8'));
  sampleFiles.set(name.replace(/\.json$/, '.htpack'), await HT.packFile.build(raw));
}

const TARGETS = [
  {
    dir: 'web',
    title: '연표',
    copy: [...COMMON, 'manifest.webmanifest'],
    skip: MAKER_ONLY,
    prefix: 'ht-',
  },
  {
    dir: 'maker',
    title: 'DLC 메이커',
    copy: [...COMMON, 'dlc-maker.html', ['maker.webmanifest', 'manifest.webmanifest']],
    skip: [],
    prefix: 'htm-',
  },
];

/** 원본 rel(‘/’로 이음)을 dst로 복사합니다. skip에 든 파일은 건너뜁니다 */
function copy(rel, dstRel, out, skip) {
  const src = join(root, rel);
  if (skip.includes(rel)) return 0;
  if (rel.startsWith('fonts/') && !FONT_FILES.includes(rel)) return 0;
  if (statSync(src).isDirectory()) {
    mkdirSync(join(out, dstRel), { recursive: true });
    let n = 0;
    for (const e of readdirSync(src)) if (!e.startsWith('.')) n += copy(`${rel}/${e}`, `${dstRel}/${e}`, out, skip);
    return n;
  }
  copyFileSync(src, join(out, dstRel));
  return 1;
}

/** 폴더 안의 파일 목록(‘/’로 이은 상대 경로) */
function listFiles(dir, base = '') {
  const found = [];
  for (const e of readdirSync(join(dir, base))) {
    const rel = base ? `${base}/${e}` : e;
    if (statSync(join(dir, rel)).isDirectory()) found.push(...listFiles(dir, rel));
    else found.push(rel);
  }
  return found;
}

/** 이 폴더 안을 가리키는 주소인지 (http · data · # 같은 것은 빼고) — 가리키면 물음표 · # 뒤를 뗀 경로 */
function localPath(url, fromFile) {
  if (!url || /^([a-z][a-z0-9+.-]*:|\/\/|#)/i.test(url)) return null;
  const clean = url.split(/[?#]/)[0];
  if (!clean) return null;
  return posix.normalize(posix.join(posix.dirname(fromFile), clean));
}

/** html이 읽거나 잇는 파일 — 주석 속 글은 셈하지 않습니다 */
function htmlRefs(html) {
  const body = html.replace(/<!--[\s\S]*?-->/g, '');
  const refs = [];
  for (const m of body.matchAll(/<script\b[^>]*\ssrc="([^"]+)"/gi)) refs.push({ tag: 'script', url: m[1] });
  for (const m of body.matchAll(/<link\b[^>]*\shref="([^"]+)"/gi)) refs.push({ tag: 'link', url: m[1] });
  for (const m of body.matchAll(/<a\b[^>]*\shref="([^"]+\.html(?:[?#][^"]*)?)"/gi)) refs.push({ tag: 'a', url: m[1] });
  return refs;
}

function build(t) {
  const out = join(root, 'dist', t.dir);
  const problems = [];
  const warnings = [];
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  let files = 0;
  for (const item of t.copy) {
    const [rel, dstRel] = Array.isArray(item) ? item : [item, item];
    if (!existsSync(join(root, rel))) {
      problems.push(`원본에 없음: ${rel}`);
      continue;
    }
    files += copy(rel, dstRel, out, t.skip);
  }
  mkdirSync(join(out, 'samples'), { recursive: true });
  for (const [name, bytes] of sampleFiles) { writeFileSync(join(out, 'samples', name), bytes); files++; }
  const all = listFiles(out);
  if (all.some(f => f.startsWith('samples/') && !f.endsWith('.htpack'))) problems.push('배포 견본에 전용 팩이 아닌 파일이 들어 있음');
  const has = rel => all.includes(rel);

  // ① html의 참조
  const pages = all.filter(f => f.endsWith('.html'));
  const referenced = new Set();
  for (const page of pages) {
    for (const r of htmlRefs(readFileSync(join(out, page), 'utf8'))) {
      const p = localPath(r.url, page);
      if (!p) continue;
      referenced.add(p);
      if (!has(p)) problems.push(`${page}의 <${r.tag}>가 가리키는 ${p}이(가) 이 폴더에 없음`);
    }
  }

  // ② manifest
  const manifest = JSON.parse(readFileSync(join(out, 'manifest.webmanifest'), 'utf8'));
  const mRefs = [
    ['시작 화면', manifest.start_url],
    ...(manifest.icons || []).map(i => ['아이콘', i.src]),
    ...(manifest.shortcuts || []).flatMap(s => [[`바로 가기 '${s.name}'`, s.url], ...(s.icons || []).map(i => [`바로 가기 '${s.name}'의 아이콘`, i.src])]),
    ...(manifest.file_handlers || []).map(h => ['파일 연결', h.action]),
  ];
  for (const [what, url] of mRefs) {
    const p = localPath(url, 'manifest.webmanifest');
    if (p && !has(p)) problems.push(`manifest의 ${what}(${p})이(가) 이 폴더에 없음`);
  }

  // ③ 연표 폴더에 메이커 파일이 새어 들지 않았는지
  for (const f of t.skip) if (has(f)) problems.push(`메이커 파일 ${f}이(가) 들어 있음`);
  if (all.some(f => f.startsWith('prototype/'))) problems.push('배포 폴더에 내보내기 도구(prototype/)가 들어 있음 — 두 폴더 모두 필요 없음');

  for (const f of FONT_FILES) if (!has(f)) problems.push(`${f}이(가) 이 폴더에 없음 (기본 글꼴과 이용 안내)`);

  // sw.js: PRECACHE를 이 폴더에 있는 파일만으로 · 캐시 이름 앞머리를 이 폴더의 것으로
  const swPath = join(out, 'sw.js');
  const sw = readFileSync(swPath, 'utf8');
  const listM = sw.match(/const PRECACHE = \[([\s\S]*?)\];/);
  const prefixRe = /const PREFIX = '[^']*';/;
  let precache = [];
  if (!listM) problems.push('sw.js에서 PRECACHE 목록을 찾지 못함');
  if (!prefixRe.test(sw)) problems.push("sw.js에서 캐시 이름 앞머리(const PREFIX = '…';)를 찾지 못함");
  if (listM && prefixRe.test(sw)) {
    const listed = [...listM[1].matchAll(/'([^']+)'/g)].map(m => m[1]);
    precache = listed.filter(has);
    const dropped = listed.filter(p => !has(p));
    const body = precache.map(p => `  '${p}',`).join('\n');
    writeFileSync(swPath, sw.replace(listM[0], `const PRECACHE = [\n${body}\n];`).replace(prefixRe, `const PREFIX = '${t.prefix}';`));
    if (dropped.length) console.log(`  dist/${t.dir}: 서비스 워커 목록에서 뺀 것 — ${dropped.join(' · ')}`);
    // 화면이 읽는 파일이 목록에 없으면 처음 한 번은 인터넷이 있어야 합니다 (틀린 것은 아니므로 알림만)
    for (const p of referenced) if (has(p) && !precache.includes(p)) warnings.push(`화면이 읽는 ${p}이(가) 서비스 워커 목록(PRECACHE)에 없음 — 오프라인 첫 실행에서 빠질 수 있음`);
    for (const p of FONT_FILES) if (has(p) && !precache.includes(p)) problems.push(`${p}이(가) 서비스 워커 목록(PRECACHE)에 없음 — 오프라인 기본 글꼴에 필요`);
  }

  for (const w of warnings) console.warn(`  (알림) dist/${t.dir}: ${w}`);
  if (problems.length) {
    for (const p of problems) console.error(`  (문제) dist/${t.dir}: ${p}`);
    return false;
  }
  console.log(`dist/${t.dir} 준비 완료 — ${t.title} · 파일 ${files}개 · 화면 ${pages.join(' · ')} · 서비스 워커 목록 ${precache.length}개 · 캐시 이름 ${t.prefix}…`);
  return true;
}

let ok = true;
for (const t of TARGETS) ok = build(t) && ok;
if (!ok) {
  console.error('웹 폴더 만들기 실패 — 위의 (문제)를 고친 뒤 다시 실행하세요.');
  process.exit(1);
}

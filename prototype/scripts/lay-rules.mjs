// 규칙 판(한 벌 P3 과제 16a — 계획 과제 16의 `pub const RULES`): Rust 배치(`prototype/engine/src/lay`)가 옮긴 원본의 SHA-256 앞 12자를 이은 글.
// 원본이 바뀌면(정답지를 다시 뽑아 Rust를 고칠 일) 낡음 검사가 멈춘다. P4 지문에 섞는 것은 이 글이 아니라 Rust 배치의 판 번호(`lay::rules::LAY_RULES_VERSION` — 판정 R61 I1).
//
// 원본 = 내보내기 모듈 `prototype/scripts/export/*.mjs`(`_`로 시작하는 옛 원본은 뺌) + 그 모듈들이 불러 쓰는 웹 코드(따옴표(홑 · 겹 · 뒤)로 싼 `js/<이름>.js` 글 — `base.mjs`의 `bootWeb` ·
// `docs.mjs`의 wiki · `entities.mjs`의 group-tree). 파일 이름 차례(웹 코드 → 모듈)로 `<파일 이름>:<앞 12자>`를 빈칸으로 잇는다. 바이트는 줄 끝을 LF로 맞춰 셈한다
// (저장소의 LF 바이트 — 옮긴 Rust 파일 머리말의 지문과 같은 셈).
// 같은 셈을 `prototype/engine/tests/lay_scope.rs`(rules_constant_is_fresh)가 하고 `lay::RULES`와 견준다 — 원본이 바뀌면 그 검사가 '상수가 낡았다'로 멈춘다.
//
// 사용(작업 폴더에서):
//   node prototype/scripts/lay-rules.mjs           → 지금 값 · 파일마다의 지문을 찍는다
//   node prototype/scripts/lay-rules.mjs --check   → prototype/engine/src/lay/mod.rs의 RULES와 다르면 종료 코드 1
//   node prototype/scripts/lay-rules.mjs --write   → mod.rs의 RULES 줄을 지금 값으로 고쳐 쓴다
// 다른 도구가 `import { rules } from '../lay-rules.mjs'`로 가져오면 아래 명령 줄 부분은 돌지 않는다(정답지 머리 `$oracle.rules` — oracle/one.mjs · 판정 R58 ⑤-4).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const exportDir = path.join(root, 'prototype', 'scripts', 'export');
const modRs = path.join(root, 'prototype', 'engine', 'src', 'lay', 'mod.rs');

const lf = buf => Buffer.from(buf.toString('latin1').replace(/\r\n/g, '\n'), 'latin1');
const sha12 = file => crypto.createHash('sha256').update(lf(fs.readFileSync(file))).digest('hex').slice(0, 12);

/** 옮긴 원본의 목록 — [보이는 이름, 경로]. */
export function sources() {
  const mods = fs.readdirSync(exportDir).filter(f => f.endsWith('.mjs') && !f.startsWith('_')).sort();
  const web = new Set();
  for (const f of mods) {
    const text = fs.readFileSync(path.join(exportDir, f), 'utf8');
    for (const m of text.matchAll(/(['"`])js\/([A-Za-z0-9_.-]+\.js)\1/g)) web.add(m[2]); // 홑 · 겹 · 뒤 따옴표 모두(판정 R46 Minor)
  }
  return [...[...web].sort().map(f => [f, path.join(root, 'js', f)]), ...mods.map(f => [f, path.join(exportDir, f)])];
}

export function rules() {
  return sources().map(([name, file]) => `${name}:${sha12(file)}`).join(' ');
}

const RE = /pub const RULES: &str = "([^"]*)";/;
/** 명령 줄로 불렸는가(가져온 것이 아니라). */
const isMain = !!process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  const args = new Set(process.argv.slice(2));
  const now = rules();
  if (args.has('--check') || args.has('--write')) {
    const text = fs.readFileSync(modRs, 'utf8');
    const m = text.match(RE);
    if (!m) { console.error(`lay-rules: ${modRs}에 RULES 줄이 없습니다`); process.exit(2); }
    if (m[1] === now) { console.log('lay-rules: RULES가 지금 원본과 같습니다'); process.exit(0); }
    if (args.has('--write')) {
      fs.writeFileSync(modRs, text.replace(RE, `pub const RULES: &str = "${now}";`));
      console.log(`lay-rules: RULES를 고쳐 썼습니다\n  ${now}`);
      process.exit(0);
    }
    console.error(`lay-rules: RULES가 낡았습니다 — node prototype/scripts/lay-rules.mjs --write\n  mod.rs: ${m[1]}\n  지금:   ${now}`);
    process.exit(1);
  }
  for (const [name, file] of sources()) console.log(`${sha12(file)}  ${name}  (${path.relative(root, file).replace(/\\/g, '/')})`);
  console.log(`\nRULES = "${now}"`);
}

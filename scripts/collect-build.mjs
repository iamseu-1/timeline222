// 빌드 결과물을 찾기 쉬운 곳(배포/)으로 모읍니다. `npm run desktop:build` · `desktop:build:maker` 끝에 자동 실행됩니다.
//   node scripts/collect-build.mjs web     연표 프로그램 (src-tauri/tauri.conf.json)
//     배포/역사연표-설치-<버전>.exe        설치 파일 (NSIS)
//     배포/역사연표-<버전>.exe             설치 없이 바로 실행되는 단일 파일 (웹 폴더 dist/web이 안에 들어 있음)
//   node scripts/collect-build.mjs maker   DLC 메이커 프로그램 (tauri.conf.json 위에 src-tauri/tauri.maker.conf.json을 덮은 설정)
//     배포/DLC메이커-설치-<버전>.exe       설치 파일 (NSIS)
//     배포/DLC메이커-<버전>.exe            설치 없이 바로 실행되는 단일 파일 (웹 폴더 dist/maker가 안에 들어 있음)
//   node scripts/collect-build.mjs         연표 · 메이커 둘 (있는 것만)
// 두 프로그램은 같은 빌드 폴더(target/release)를 쓰므로 "빌드 → 모으기 → 다음 빌드" 차례로 돌립니다.
// 실행 파일 안에 그 프로그램의 식별자(identifier)가 들어 있는지 보고, 다른 프로그램의 것이거나 설치 파일이
// 실행 파일보다 오래됐으면(지난 빌드의 것) 모으지 않습니다.
// 빌드 폴더는 CARGO_TARGET_DIR 환경 변수가 있으면 그곳, 없으면 src-tauri/target 입니다.
import { readdirSync, mkdirSync, copyFileSync, existsSync, readFileSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const pkgVersion = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const out = join(root, '배포');
const target = process.env.CARGO_TARGET_DIR ? resolve(process.env.CARGO_TARGET_DIR) : join(root, 'src-tauri', 'target');
const release = join(target, 'release');

const readConf = f => JSON.parse(readFileSync(join(root, 'src-tauri', f), 'utf8'));
/** tauri build --config 와 같은 JSON 병합(RFC 7396): 객체는 칸마다 합치고 배열 · 값은 통째로 바꿉니다 */
const mergePatch = (base, patch) => {
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return patch;
  const r = base && typeof base === 'object' && !Array.isArray(base) ? { ...base } : {};
  for (const [k, v] of Object.entries(patch)) {
    if (v === null) delete r[k];
    else r[k] = mergePatch(r[k], v);
  }
  return r;
};
const base = readConf('tauri.conf.json');
const APPS = {
  web: { title: '연표', file: '역사연표', conf: base },
  maker: { title: 'DLC 메이커', file: 'DLC메이커', conf: mergePatch(base, readConf('tauri.maker.conf.json')) },
};

const arg = process.argv[2];
if (arg && !APPS[arg]) {
  console.error(`모을 프로그램은 web(연표) · maker(DLC 메이커)입니다: ${arg}`);
  process.exit(1);
}
const wanted = arg ? [arg] : Object.keys(APPS);

/** 실행 파일 안에 이 식별자가 들어 있는지 (설정은 빌드 때 실행 파일 안에 새겨집니다) */
const hasText = (file, text) => readFileSync(file).includes(Buffer.from(text, 'utf8'));

mkdirSync(out, { recursive: true });
let total = 0;
for (const key of wanted) {
  const app = APPS[key];
  const { conf } = app;
  const version = conf.version || pkgVersion;
  const others = Object.values(APPS).filter(a => a.conf.identifier !== conf.identifier).map(a => a.conf.identifier);
  let n = 0;
  const bin = join(release, `${conf.mainBinaryName || 'app'}.exe`);
  let binTime = 0;
  if (existsSync(bin)) {
    if (!hasText(bin, conf.identifier) || others.some(id => hasText(bin, id))) console.warn(`  (건너뜀) ${bin} 은(는) ${app.title} 프로그램의 빌드가 아닙니다 — 먼저 빌드하세요.`);
    else {
      copyFileSync(bin, join(out, `${app.file}-${pkgVersion}.exe`));
      binTime = statSync(bin).mtimeMs;
      n++;
    }
  }
  // 설치 파일 이름: <productName>_<version>_<arch>-setup.exe · <productName>_<version>_<arch>_<lang>.msi
  const mine = f => f.startsWith(`${conf.productName}_${version}_`);
  // 설치 파일은 실행 파일을 만든 뒤에 만들어집니다 — 이 프로그램의 실행 파일이 없거나 그보다 오래된 설치 파일은 지난 빌드의 것
  const fresh = f => binTime > 0 && statSync(f).mtimeMs >= binTime - 1000;
  for (const [dir, ext, name] of [
    ['nsis', '.exe', `${app.file}-설치-${pkgVersion}.exe`],
    ['msi', '.msi', `${app.file}-설치-${pkgVersion}.msi`],
  ]) {
    const d = join(release, 'bundle', dir);
    if (!existsSync(d)) continue;
    for (const f of readdirSync(d)) {
      if (!f.endsWith(ext) || !mine(f)) continue;
      if (!fresh(join(d, f))) {
        console.warn(`  (건너뜀) ${f} 은(는) 이번 빌드의 것인지 알 수 없습니다(${app.title} 실행 파일이 없거나 그보다 먼저 만든 것) — 다시 빌드하세요.`);
        continue;
      }
      copyFileSync(join(d, f), join(out, name));
      n++;
    }
  }
  console.log(n ? `  ${app.title}: 파일 ${n}개` : `  ${app.title}: 모을 빌드 결과물이 없습니다.`);
  total += n;
}

console.log(total ? `배포/ 폴더에 파일 ${total}개를 모았습니다: ${out}` : '모을 빌드 결과물이 없습니다. 먼저 npm run desktop:build (연표) · npm run desktop:build:maker (DLC 메이커)를 실행하세요.');
if (arg && !total) process.exit(1);

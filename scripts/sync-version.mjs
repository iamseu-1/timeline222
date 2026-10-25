// package.json 의 version 하나를 기준으로 나머지 파일의 버전을 맞춥니다.
//   sw.js (캐시 이름) · src-tauri/tauri.conf.json (앱 버전) · src-tauri/Cargo.toml
// `npm version patch|minor|major` 를 실행하면 자동으로 호출됩니다.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;

const edit = (rel, fn) => {
  const p = join(root, rel);
  if (!existsSync(p)) return console.log(`  (없음) ${rel}`);
  const before = readFileSync(p, 'utf8');
  const after = fn(before);
  if (after !== before) {
    writeFileSync(p, after);
    console.log(`  ${rel} → ${version}`);
  }
};

edit('sw.js', s => s.replace(/const VERSION = '[^']*';/, `const VERSION = '${version}';`));
edit('src-tauri/tauri.conf.json', s => s.replace(/"version":\s*"[^"]*"/, `"version": "${version}"`));
edit('src-tauri/Cargo.toml', s => s.replace(/^version = "[^"]*"/m, `version = "${version}"`));
console.log(`버전 ${version} 동기화 완료`);

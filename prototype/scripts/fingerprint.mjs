// 보호 자료(packs/ 와 기존 samples/*.json)의 지문을 적거나(save) 앞서 적은 것과 견준다(check).
// 사용: node prototype/scripts/fingerprint.mjs save <결과.json> | check <앞서 적은.json>
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const [mode, target] = process.argv.slice(2);
if (!['save', 'check'].includes(mode) || !target) {
  console.error('사용: fingerprint.mjs save <결과.json> | check <앞서 적은.json>');
  process.exit(2);
}

function collect() {
  const files = [];
  const walk = dir => {
    for (const name of fs.readdirSync(dir)) {
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) walk(full);
      else files.push(full);
    }
  };
  walk(path.join(root, 'packs'));
  for (const name of fs.readdirSync(path.join(root, 'samples'))) {
    if (name.endsWith('.json')) files.push(path.join(root, 'samples', name));
  }
  const out = {};
  for (const full of files.sort()) {
    const key = path.relative(root, full).split(path.sep).join('/');
    out[key] = createHash('sha256').update(fs.readFileSync(full)).digest('hex');
  }
  return out;
}

const now = collect();
const all = createHash('sha256').update(JSON.stringify(now)).digest('hex');
if (mode === 'save') {
  if (fs.existsSync(target)) {
    console.error('이미 있는 지문 기록은 덮어쓰지 않습니다: ' + target);
    process.exit(1);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify({ when: new Date().toISOString(), count: Object.keys(now).length, all, files: now }, null, 2) + '\n');
  console.log(`보호 자료 ${Object.keys(now).length}개 · 묶음 지문 ${all.slice(0, 16)}`);
} else {
  const before = JSON.parse(fs.readFileSync(target, 'utf8'));
  const changed = [];
  for (const key of new Set([...Object.keys(before.files), ...Object.keys(now)])) {
    if (before.files[key] !== now[key]) changed.push(key);
  }
  if (changed.length) {
    console.error('보호 자료가 바뀌었습니다:\n' + changed.join('\n'));
    process.exit(1);
  }
  console.log(`보호 자료 ${Object.keys(now).length}개 모두 그대로 · 묶음 지문 ${all.slice(0, 16)}`);
}

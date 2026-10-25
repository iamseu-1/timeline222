// 남의 꾸러미 목록 뽑기 — 잠금 파일 넷(Rust 크레이트 둘 · Dart 패키지 하나 · npm 하나)에서 이름 · 판 · 허락 종류를 뽑아
// 뿌리 THIRD_PARTY_NOTICES.md의 '의존 꾸러미 목록' 절(표시 줄 둘 사이)을 다시 짓는다.
//
// 사용(작업 폴더 어디서든): node prototype/scripts/third-party-list.mjs           → 표를 화면에 찍는다
//                          node prototype/scripts/third-party-list.mjs --write   → THIRD_PARTY_NOTICES.md의 표시 사이를 갈음한다
//
// 네트워크는 쓰지 않는다. 허락 종류는 이 컴퓨터에 이미 받아 둔 것에서만 읽는다:
//   · Rust 크레이트: <CARGO_HOME 또는 ~/.cargo>/registry/src/*/<이름>-<판>/Cargo.toml의 license 칸(없으면 license-file이 가리키는 글)
//   · Dart 패키지: <PUB_CACHE 또는 %LOCALAPPDATA%/Pub/Cache · ~/.pub-cache>/hosted/pub.dev/<이름>-<판>/LICENSE 글의 꼴
//                  sdk 패키지(flutter 등)는 FLUTTER_ROOT(없으면 PATH의 flutter/bin)의 packages/<이름>/LICENSE → 뿌리 LICENSE
//   · npm: package-lock.json의 license 칸(없으면 node_modules/<이름>/package.json)
// 찾지 못하면 '확인 못 함'으로 적는다(이 컴퓨터가 그 꾸러미를 받은 적이 없음 — 다른 운영체제 전용 크레이트 따위). 받은 뒤 다시 돌리면 채워진다.
// 사용자 폴더 경로는 결과에 적지 않는다(공개 저장소에 들어가므로). 결과는 같은 캐시면 몇 번을 돌려도 같은 바이트다(날짜를 적지 않음).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const NOTICES = path.join(ROOT, 'THIRD_PARTY_NOTICES.md');
const START = '<!-- third-party-list:start';
const END = '<!-- third-party-list:end -->';
const UNKNOWN = '확인 못 함';

const read = file => { try { return fs.readFileSync(file, 'utf8'); } catch { return null; } };
const isDir = dir => { try { return fs.statSync(dir).isDirectory(); } catch { return false; } };
const cell = s => String(s).replace(/\|/g, '\\|');

/** LICENSE 글의 꼴로 허락 종류를 가린다(알려진 문구만 — 모르면 null). 여러 개면 모두. */
function detect(text) {
  if (!text) return null;
  if (text.length > 100000) return '여러 허락 모음';
  const t = text.replace(/\s+/g, ' ');
  const hits = [];
  if (/Apache License,? Version 2\.0/i.test(t)) hits.push('Apache-2.0');
  if (/Permission is hereby granted, free of charge, to any person obtaining a copy/i.test(t)) hits.push('MIT');
  if (/Redistribution and use in source and binary forms/i.test(t)) {
    hits.push(/Neither the name|names of (its|the|their) contributors may be used/i.test(t) ? 'BSD-3-Clause' : 'BSD-2-Clause');
  }
  if (/Permission to use, copy, modify, and\/or distribute this software for any purpose with or without fee is hereby granted/i.test(t)) hits.push('ISC');
  if (/Mozilla Public License,? (Version |v\. ?)?2\.0/i.test(t)) hits.push('MPL-2.0');
  if (/SIL OPEN FONT LICENSE/i.test(t)) hits.push('OFL-1.1');
  if (/This is free and unencumbered software released into the public domain/i.test(t)) hits.push('Unlicense');
  if (/Boost Software License/i.test(t)) hits.push('BSL-1.0');
  if (/provided ['‘]as-is['’], without any express or implied warranty/i.test(t)) hits.push('Zlib');
  if (/UNICODE LICENSE V3|Unicode, Inc\..*COPYRIGHT AND PERMISSION NOTICE|COPYRIGHT AND PERMISSION NOTICE.*Unicode, Inc\./i.test(t)) hits.push('Unicode-3.0');
  if (/GNU LESSER GENERAL PUBLIC LICENSE/i.test(t)) hits.push('LGPL');
  else if (/GNU GENERAL PUBLIC LICENSE/i.test(t)) hits.push('GPL');
  if (/CC0 1\.0 Universal/i.test(t)) hits.push('CC0-1.0');
  return hits.length ? [...new Set(hits)].join(' · ') : null;
}

/** 폴더 안의 허락 글(LICENSE* · COPYING* · UNLICENSE)을 모두 읽어 가린다. */
function detectDir(dir) {
  let names;
  try { names = fs.readdirSync(dir); } catch { return null; }
  const files = names.filter(n => /^(LICEN[CS]E|COPYING|UNLICENSE)/i.test(n)).sort();
  if (!files.length) return null;
  const found = [...new Set(files.map(n => detect(read(path.join(dir, n)))).filter(Boolean).flatMap(s => s.split(' · ')))];
  return { license: found.length ? found.join(' · ') : '허락 글 있음 · 종류 못 가림', basis: files.join(' · ') };
}

/* ── Rust 크레이트 ── */
const cargoHome = process.env.CARGO_HOME || path.join(os.homedir(), '.cargo');
const cargoSrcRoots = (() => {
  const base = path.join(cargoHome, 'registry', 'src');
  try { return fs.readdirSync(base).map(d => path.join(base, d)).filter(isDir).sort(); } catch { return []; }
})();

function crateLicense(name, version) {
  for (const root of cargoSrcRoots) {
    const dir = path.join(root, `${name}-${version}`);
    const toml = read(path.join(dir, 'Cargo.toml'));
    if (toml == null) continue;
    const pkg = (/^\[package\]\s*$([\s\S]*?)(?=^\[)/m.exec(`${toml}\n[`) || [])[1] || '';
    const lic = /^license\s*=\s*"([^"]*)"/m.exec(pkg);
    if (lic && lic[1].trim()) return { license: lic[1].trim(), basis: 'Cargo.toml' };
    const file = /^license-file\s*=\s*"([^"]*)"/m.exec(pkg);
    if (file) {
      const d = detect(read(path.join(dir, file[1])));
      return { license: d || '허락 글 있음 · 종류 못 가림', basis: `Cargo.toml license-file(${file[1]})` };
    }
    return detectDir(dir) || { license: UNKNOWN, basis: 'Cargo.toml에 칸 없음' };
  }
  return { license: UNKNOWN, basis: '캐시에 없음' };
}

function cargoRows(lockRel) {
  const text = read(path.join(ROOT, lockRel));
  if (text == null) throw new Error(`${lockRel}을(를) 읽지 못했습니다`);
  const rows = [];
  for (const block of text.split(/^\[\[package\]\]\s*$/m).slice(1)) {
    const get = key => (new RegExp(`^${key}\\s*=\\s*"([^"]*)"`, 'm').exec(block) || [])[1];
    const name = get('name'), version = get('version'), source = get('source');
    if (!source) continue; // 이 저장소의 크레이트(작업 공간)는 남의 것이 아님
    const kind = source.startsWith('registry+') ? '' : ` (${source.split('+')[0]})`;
    rows.push({ name, version: version + kind, ...crateLicense(name, version) });
  }
  return rows;
}

/* ── Dart 패키지 ── */
const pubCache = process.env.PUB_CACHE
  || (process.platform === 'win32' && process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Pub', 'Cache') : path.join(os.homedir(), '.pub-cache'));

const flutterRoot = (() => {
  if (process.env.FLUTTER_ROOT && isDir(process.env.FLUTTER_ROOT)) return process.env.FLUTTER_ROOT;
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const exe = ['flutter', 'flutter.bat'].some(n => fs.existsSync(path.join(dir, n)));
    if (exe && path.basename(dir) === 'bin' && isDir(path.join(dir, '..', 'packages', 'flutter'))) return path.resolve(dir, '..');
  }
  return null;
})();

/** pubspec.lock(YAML)의 packages 절만 읽는 작은 읽개 — 이름(두 칸 들여씀) 아래 dependency · source · version · description.name. */
function pubPackages(text) {
  const out = [];
  let inPackages = false, cur = null;
  for (const line of text.split(/\r?\n/)) {
    if (/^\S/.test(line)) { inPackages = /^packages:\s*$/.test(line); cur = null; continue; }
    if (!inPackages) continue;
    let m;
    if ((m = /^ {2}([^\s:]+):\s*$/.exec(line))) { cur = { name: m[1] }; out.push(cur); continue; }
    if (!cur) continue;
    if ((m = /^ {4}(dependency|source|version):\s*"?([^"]*)"?\s*$/.exec(line))) cur[m[1]] = m[2];
  }
  return out;
}

function pubLicense(p) {
  if (p.source === 'hosted') {
    const hit = detectDir(path.join(pubCache, 'hosted', 'pub.dev', `${p.name}-${p.version}`));
    return hit || { license: UNKNOWN, basis: '캐시에 없음' };
  }
  if (p.source === 'sdk') {
    if (!flutterRoot) return { license: UNKNOWN, basis: 'Flutter SDK를 찾지 못함' };
    for (const dir of [path.join(flutterRoot, 'packages', p.name), path.join(flutterRoot, 'bin', 'cache', 'pkg', p.name)]) {
      const hit = detectDir(dir);
      if (hit) return { license: hit.license, basis: `Flutter SDK ${hit.basis}` };
    }
    const top = detect(read(path.join(flutterRoot, 'LICENSE')));
    return top ? { license: top, basis: 'Flutter SDK 뿌리 LICENSE' } : { license: UNKNOWN, basis: 'Flutter SDK에 허락 글 없음' };
  }
  return { license: UNKNOWN, basis: `${p.source} 출처 — 따로 확인` };
}

function pubRows(lockRel) {
  const text = read(path.join(ROOT, lockRel));
  if (text == null) throw new Error(`${lockRel}을(를) 읽지 못했습니다`);
  return pubPackages(text)
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
    .map(p => ({ name: p.name, version: p.source === 'sdk' ? 'SDK' : p.version, use: p.dependency || '', ...pubLicense(p) }));
}

/* ── npm ── */
function npmRows(lockRel) {
  const text = read(path.join(ROOT, lockRel));
  if (text == null) throw new Error(`${lockRel}을(를) 읽지 못했습니다`);
  const lock = JSON.parse(text);
  const rows = [];
  for (const [key, info] of Object.entries(lock.packages || {})) {
    if (!key) continue; // 이 저장소 자신
    const name = info.name || key.slice(key.lastIndexOf('node_modules/') + 'node_modules/'.length);
    let license = typeof info.license === 'string' ? info.license : info.license && info.license.type, basis = 'package-lock.json';
    if (!license) {
      const pkg = read(path.join(ROOT, key, 'package.json'));
      const lic = pkg && JSON.parse(pkg).license;
      license = typeof lic === 'string' ? lic : lic && lic.type;
      basis = license ? 'node_modules package.json' : '잠금 파일 · node_modules에 없음';
    }
    const use = [info.dev ? '개발' : '', info.optional ? '고를 수 있음(운영체제별)' : ''].filter(Boolean).join(' · ');
    rows.push({ name, version: info.version || '', use, license: license || UNKNOWN, basis });
  }
  return rows.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

/* ── 표 ── */
function tally(rows) {
  const n = new Map();
  for (const r of rows) n.set(r.license, (n.get(r.license) || 0) + 1);
  return [...n].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([k, v]) => `${k} ${v}`).join(' · ');
}

function table(title, lockRel, note, rows, withUse) {
  const unknown = rows.filter(r => r.license === UNKNOWN).length;
  const lines = [
    `### ${title} — \`${lockRel}\``,
    '',
    `${rows.length}개${unknown ? ` (그중 ${UNKNOWN} ${unknown}개)` : ''}. ${note}`,
    '',
    `허락 종류별: ${tally(rows)}`,
    '',
    withUse ? '| 이름 | 판 | 쓰임 | 허락 | 근거 |' : '| 이름 | 판 | 허락 | 근거 |',
    withUse ? '| --- | --- | --- | --- | --- |' : '| --- | --- | --- | --- |',
    ...rows.map(r => (withUse
      ? `| ${cell(r.name)} | ${cell(r.version)} | ${cell(r.use || '')} | ${cell(r.license)} | ${cell(r.basis)} |`
      : `| ${cell(r.name)} | ${cell(r.version)} | ${cell(r.license)} | ${cell(r.basis)} |`)),
    '',
  ];
  return lines.join('\n');
}

const sections = [
  table('Rust 크레이트 (연표 엔진)', 'prototype/engine/Cargo.lock',
    '잠금 파일의 모든 크레이트입니다(시험 · 다른 운영체제 전용 포함). 이 저장소의 크레이트(archive_engine)는 뺐습니다.',
    cargoRows('prototype/engine/Cargo.lock'), false),
  table('Rust 크레이트 (Windows 앱 · DLC 메이커 — Tauri)', 'src-tauri/Cargo.lock',
    '잠금 파일의 모든 크레이트입니다(빌드 · 다른 운영체제 전용 포함). 이 저장소의 크레이트(app)는 뺐습니다.',
    cargoRows('src-tauri/Cargo.lock'), false),
  table('Dart 패키지 (독립형 연표 앱 — Flutter)', 'prototype/app/pubspec.lock',
    '쓰임은 pubspec.lock의 dependency 칸입니다(direct main · direct dev · transitive). sdk 패키지는 Flutter SDK와 함께 오는 것입니다. '
      + 'Dart 패키지에는 허락 칸이 없어 LICENSE 글의 꼴로 가렸습니다 — 허락 칸의 \'·\'는 그 글들에서 찾은 허락을 모두 늘어놓은 것이니(고를지 · 모두 지킬지는 가리지 않음) 자세한 것은 그 글을 보십시오.',
    pubRows('prototype/app/pubspec.lock'), true),
  table('npm 꾸러미 (빌드 도구)', 'package-lock.json',
    '모두 개발용(Tauri 명령 줄 도구)이고 앱에 실리지 않습니다.',
    npmRows('package-lock.json'), true),
];

const body = [
  `${START} — 아래는 prototype/scripts/third-party-list.mjs가 짓습니다. 손으로 고치지 말고 대본을 다시 돌리십시오 -->`,
  '',
  ...sections,
  END,
].join('\n');

if (process.argv.includes('--write')) {
  const doc = read(NOTICES);
  if (doc == null) throw new Error('THIRD_PARTY_NOTICES.md가 없습니다');
  const a = doc.indexOf(START), b = doc.indexOf(END);
  if (a < 0 || b < a) throw new Error(`THIRD_PARTY_NOTICES.md에 표시 줄(${START} … ${END})이 없습니다`);
  const next = doc.slice(0, a) + body + doc.slice(b + END.length);
  fs.writeFileSync(NOTICES, next.replace(/\r\n/g, '\n'));
  const all = sections.join('\n').match(/^\| /gm).length;
  console.log(`THIRD_PARTY_NOTICES.md를 고쳤습니다 — 표 줄 ${all}개(머리 줄 포함).`);
} else {
  process.stdout.write(`${body}\n`);
}

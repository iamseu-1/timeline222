// 앱 고정 자료 names-display.json을 짓는다(10건 3 · 9 — 갈래 D2 원어 병기 · 글꼴의 새 앱 몫).
// 웹 검사 scripts/names-display-check.mjs의 가상 세계(해온국 · 달 왕국 · 별바다 · 돌샘국 · 달빛 강 연합 왕국 · 오른쪽에서 왼쪽 글자 이름의 나라)를
// 지금 내보내기 모듈(prototype/scripts/export — contextOf · runModules, 노드 도구 · 메이커 일꾼과 같은 길)로 내보내
// 앱 검사(test/names_display_test.dart)가 읽는 것만 남긴다: 이름이 있는 항목 기록({uid, kind, json} — 엔진 entity 답의 꼴)과 정권 줄의 줄 이름 후보(rowLabels).
// 모두 가상 이름(고증 아님). 사용: node prototype/app/test/fixtures/names-display.mjs  (저장소 뿌리에서 · 견본 · 기본팩은 읽지 않는다)
//   --packs <폴더>: 같은 가상 세계를 원본 전용 팩 둘로도 낸다 — d2-names.htpack(이름) · d2-font.htpack(웹 검사의 확인용 가상 문자 글꼴 둘 —
//   글꼴 바이트는 scripts/names-display-check.mjs의 FONT_TTF를 읽어 씀). PC에서 HT_EXPORT_EXTRA로 얹어 저장소를 짓고 앱 화면을 웹 검사 그림과
//   1배로 견줄 때 쓴다(docs/작업-지시/10건-PC-검사-D2.md). 고정 자료(names-display.json)는 이 선택과 상관없이 같다.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bootWeb, contextOf, runModules, root } from '../../../scripts/export/base.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUA = s => [...s].map(c => String.fromCodePoint(0xf1a00 + parseInt(c, 16))).join('');
const BYEOL = PUA('0123');
const EXTB = '\u{2546E}泉國'; // 첫 글자가 한자 확장 B(U+2546E)
const NAMES = {
  format: 'history-timeline-dlc', formatVersion: 3, id: 'd2-names', name: '확인용 가상 세계(원어)', version: '1.0.0', description: '원어 병기 검사용 가상 자료 — 고증 아님',
  tracks: [{ id: 'd2w', name: '가상 세계', color: '#9fb4c7' }],
  places: [{ id: 'pl-sea', name: '바닷골', names: [{ text: '海谷', lang: 'lzh', kind: '원어' }, { text: 'Badatgol', lang: 'ko-Latn', kind: '로마자' }] }],
  surnames: [{ id: 'sn-sea', name: '바다', description: '확인용 가상 성씨.', names: [{ text: '海', lang: 'lzh', kind: '원어' }, { text: 'Bada', kind: '로마자' }, { text: '大海', kind: '옛 이름' }] }],
  houses: [{ id: 'h-sea', name: '바다 가문', surname: 'sn-sea', names: [{ text: '海氏', lang: 'lzh', kind: '원어' }] }],
  periods: [
    {
      id: 'haeon', track: 'd2w', name: '해온국', start: 1420, end: 1500, color: '#a8c7b8', description: '확인용 가상 나라 — 이름이 넷(원어 · 로마자 · 옛 이름 · 약칭).',
      names: [{ text: '海溫國', lang: 'lzh', kind: '원어' }, { text: 'Haeon-guk', lang: 'ko-Latn', kind: '로마자' }, { text: '溫羅', lang: 'lzh', kind: '옛 이름', start: 1420, end: 1449 }, { text: '海溫', lang: 'lzh', kind: '약칭' }],
      leaders: [{ name: '바다 임금', start: 1420, names: [{ text: '海王', lang: 'lzh', kind: '원어' }, { text: 'Bada Imgeum', kind: '로마자' }] }, { name: '물빛 임금', start: 1460 }],
      capitals: [{ city: 'pl-sea', start: 1420 }],
    },
    { id: 'moon', track: 'd2w', name: '달 왕국', start: 520, end: 680, color: '#b9c6dd', names: [{ text: 'قمر', lang: 'ar', kind: '원어' }, { text: 'Qamar', kind: '로마자' }] },
    { id: 'byeol', track: 'd2w', name: '별바다', start: 540, end: 700, color: '#d8c3cf', names: [{ text: BYEOL, lang: 'x-byeol', kind: '원어' }, { text: 'Yelna Oru', kind: '로마자' }] },
    { id: 'rock', track: 'd2w', name: '돌샘국', start: 600, end: 780, color: '#c9d3b2', names: [{ text: EXTB, lang: 'lzh', kind: '원어' }, { text: 'Dolsaem', kind: '로마자' }] },
    { id: 'long', track: 'd2w', name: '달빛 강 연합 왕국', start: 1400, end: 1480, color: '#c8c0dc', names: [{ text: '月光江聯合王國', lang: 'lzh', kind: '원어' }] },
    { id: 'rtl', track: 'd2w', name: 'قمر', start: 520, end: 680, color: '#e0cfb8', description: '이름 자체가 오른쪽에서 왼쪽으로 쓰는 글자인 나라' },
  ],
  figures: [
    { id: 'f-sol', track: 'd2w', name: '솔빛', role: '학자', birth: 1430, death: 1480, service: [{ polity: '해온국', office: '기록관' }], names: [{ text: '松光', lang: 'lzh', kind: '원어' }, { text: 'Solbit', kind: '로마자' }] },
    { id: 'f-wave', track: 'd2w', name: '물결', lineageOnly: true, birth: 1380, death: 1450, aka: ['물결 어른'], description: '확인용 가상 계보 인물.', names: [{ text: '波', lang: 'lzh', kind: '원어' }, { text: 'Mulgyeol', kind: '로마자' }, { text: '小波', kind: '옛 이름' }] },
  ],
  events: [{ id: 'ev-move', track: 'd2w', title: '바닷골 천도', start: 1430, category: 'politics', place: 'pl-sea', names: [{ text: '海谷遷都', lang: 'lzh', kind: '원어' }] }],
};

const HT = bootWeb();
const ctx = contextOf(HT, [NAMES]);
const out = await runModules(ctx);
const keep = out.entities.filter(e => e.kind !== 'doc' && e.kind !== 'cal' && /"x_(nameHead|cellNameHead|surname|place)"/.test(e.json));
const rows = out.rowLabels.filter(l => l.kind === 0);
const fixture = {
  note: '갈래 D2(원어 병기 · 글꼴)의 앱 고정 자료 — prototype/app/test/fixtures/names-display.mjs가 지금 내보내기 모듈로 지었다. 가상 이름(고증 아님).',
  entities: keep.map(e => ({ uid: e.uid, kind: e.kind, json: e.json })),
  rowLabels: rows,
};
fs.writeFileSync(path.join(here, 'names-display.json'), JSON.stringify(fixture, null, 1) + '\n');
console.log(JSON.stringify({ 기록: keep.map(e => e.uid), 줄이름: rows.map(l => `${l.name}${l.orig ? ` ← ${l.orig.map(o => o.text + (o.mb ? `(띠 없음 ${o.mb.length})` : '')).join(' / ')}` : ''}`) }, null, 1));

const packsAt = process.argv.indexOf('--packs');
if (packsAt > 0) {
  const dir = path.resolve(process.argv[packsAt + 1] || '.');
  const web = fs.readFileSync(path.join(root, 'scripts', 'names-display-check.mjs'), 'utf8');
  const ttf = /const FONT_TTF = '(data:font\/ttf;base64,[A-Za-z0-9+/=]+)'/.exec(web)?.[1];
  if (!ttf) throw new Error('scripts/names-display-check.mjs에서 확인용 글꼴(FONT_TTF)을 찾지 못했습니다');
  const FONTS = {
    format: 'history-timeline-dlc', formatVersion: 3, id: 'd2-font', name: '확인용 가상 문자 글꼴', version: '1.0.0', description: '사설 영역 열두 자 — 검사용',
    fonts: [
      { id: 'byeol', family: '별바다 글씨', src: ttf, license: '확인용 — 검사 전용', scripts: ['Qaaa'], ranges: ['U+F1A00-F1A0B'] },
      { id: 'hangul-mock', family: '확인용 한글 글꼴', src: ttf, license: '확인용 — 검사 전용', scripts: ['Hang'], note: '한글을 덮는다고 적은 확인용 글꼴(실제 글자는 없음 — 고르기 길만 봄)' },
    ],
  };
  fs.mkdirSync(dir, { recursive: true });
  for (const [name, raw] of [['d2-names', NAMES], ['d2-font', FONTS]]) fs.writeFileSync(path.join(dir, `${name}.htpack`), await HT.packFile.build(raw));
  console.log(JSON.stringify({ 팩: ['d2-names.htpack', 'd2-font.htpack'].map(n => path.join(dir, n)) }));
}

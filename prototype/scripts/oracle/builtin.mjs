// 내장 DLC(packs/<이름>/*.js) 읽기 · 파일로 굳히기 — 정답지 자식 프로세스(one.mjs) · 바꿔 넣기 도구(to-f4.mjs) · 굳히기 도구(freeze-builtin.mjs)가 함께 쓴다.
// 웹 코드(js/*.js · packs/*)는 읽기만 한다. 부르기 전에 `bootWeb()`로 HT를 싣고, 시각 · 시간대를 고정해야 하는 도구(one.mjs)는 그 뒤에 이 파일을 가져온다.
import { root, runScript, assert, node } from '../export/base.mjs';

const { fs, path } = node;

/** 내장 DLC `<이름>`을 index.html이 싣는 차례 그대로 돌려 모은다(export/base.mjs의 loadContext와 같은 방식).
    돌려주는 값: { files — 실은 스크립트(저장소 뿌리 기준 · 싣는 차례), text — 그 파일들을 `이름\n내용`으로 이은 글(지문용), pack — HT.getBuiltinPacks()의 그 DLC 하나 }. */
export function loadBuiltin(HT, name) {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const files = [...html.matchAll(/<script src="(packs\/[^"]+\.js)"/g)].map(m => m[1]).filter(f => f.startsWith(`packs/${name}/`));
  assert.ok(files.length, `index.html에 packs/${name}/ 의 스크립트가 없습니다`);
  for (const file of files) runScript(file);
  const packs = HT.getBuiltinPacks();
  assert.equal(packs.length, 1, `내장 DLC가 하나여야 합니다(지금 ${packs.length}개)`);
  const text = files.map(f => `${f}\n${fs.readFileSync(path.join(root, f), 'utf8')}`).join('\n');
  return { files, text, pack: packs[0] };
}

/** 같은 구조의 새 사본(배열 · 일반 객체만 따라가고 그 밖의 값은 그대로) — 내장 팩의 raw를 그때그때 새로. */
export const clone = v => (Array.isArray(v) ? v.map(clone) : v && typeof v === 'object' && Object.getPrototypeOf(v) === Object.prototype ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, clone(x)])) : v);

/** 내장 팩이 JSON 글로 굳혀도 같은 값인지 훑어, 아니면 경로와 함께 멈춘다(함수 · symbol · bigint · 고리 · 일반 객체가 아닌 것(Date · Map · Set · 클래스 개체) ·
    NaN/Infinity — JSON이 null로 바꾼다). undefined 값은 JSON에서 열쇠가 빠질 뿐이라 막지 않고 수만 센다. 돌려주는 값: { text — JSON.stringify 그대로, undefinedKeys }. */
export function freeze(pack) {
  const open = new Set();
  let undefinedKeys = 0;
  const walk = (v, at) => {
    if (v === undefined) { undefinedKeys++; return; }
    if (v === null) return;
    switch (typeof v) {
      case 'string': case 'boolean': return;
      case 'number': if (!Number.isFinite(v)) throw new Error(`굳힐 수 없습니다 — ${at || '(루트)'}가 ${v}입니다(JSON은 null로 바꿉니다)`); return;
      case 'function': throw new Error(`굳힐 수 없습니다 — ${at || '(루트)'}가 함수입니다(JSON이 빼 버립니다)`);
      case 'symbol': case 'bigint': throw new Error(`굳힐 수 없습니다 — ${at || '(루트)'}가 ${typeof v}입니다`);
    }
    if (open.has(v)) throw new Error(`굳힐 수 없습니다 — ${at || '(루트)'}에 고리(순환)가 있습니다`);
    open.add(v);
    if (Array.isArray(v)) v.forEach((x, i) => walk(x, at ? `${at}.${i}` : String(i)));
    else {
      const proto = Object.getPrototypeOf(v);
      if (proto !== Object.prototype && proto !== null) throw new Error(`굳힐 수 없습니다 — ${at || '(루트)'}가 일반 객체가 아닙니다(${(proto.constructor && proto.constructor.name) || '이름 없는 개체'})`);
      for (const [k, x] of Object.entries(v)) walk(x, at ? `${at}.${k}` : k);
    }
    open.delete(v);
  };
  walk(pack, '');
  return { text: JSON.stringify(pack), undefinedKeys };
}

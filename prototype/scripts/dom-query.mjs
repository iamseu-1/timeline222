// 기준 덤프(dump-dom.mjs의 결과)를 골라 본다.
// 사용: node prototype/scripts/dom-query.mjs <덤프.json> [--list] [--class 글자] [--not 글자] [--in x,y,w,h] [--text 글자] [--limit n] [--items] [--tree 번호]
//   --list        첫 클래스 이름마다의 개수
//   --class tl-epoch   클래스 글에 이 글자가 든 요소만(쉼표로 여럿 = 모두 들어야 함). 모양이 같은 것끼리 묶어 개수 · 보기 하나와 함께 찍는다
//   --items       묶지 않고 요소마다 한 줄(자리 · 글)
//   --tree 번호    그 요소와 자손을 들여 써서
import fs from 'node:fs';

const [file, ...args] = process.argv.slice(2);
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null; };
const flag = name => args.includes(name);
const dump = JSON.parse(fs.readFileSync(file, 'utf8'));
const { items, styles } = dump;
items.forEach((it, i) => (it.i = i));

if (flag('--scene')) console.log(JSON.stringify(dump.scene), '\n', JSON.stringify(dump.model.tracks.map(t => ({ name: t.name, rows: t.rows, height: t.height, hidden: t.hidden.length }))));
if (flag('--list')) {
  const kinds = new Map();
  for (const it of items) { const key = it.c.startsWith('<') ? it.c.split(' ').slice(0, 2).join(' ') : it.c.split(' ')[0] + (it.c.includes('::') ? ' ' + it.c.split(' ').pop() : ''); kinds.set(key, (kinds.get(key) || 0) + 1); }
  for (const [k, n] of [...kinds].sort((a, b) => b[1] - a[1])) console.log(String(n).padStart(5), k);
  process.exit(0);
}
const tree = option('--tree');
if (tree != null) {
  const children = new Map();
  for (const it of items) if (it.p != null) children.set(it.p, (children.get(it.p) || []).concat([it]));
  const show = (it, depth) => {
    console.log(`${' '.repeat(depth * 2)}#${it.i} ${it.c} [${it.r.join(', ')}]${it.t ? ` "${it.t}"` : ''} ${JSON.stringify(styles[it.s])}`);
    for (const child of children.get(it.i) || []) show(child, depth + 1);
  };
  show(items[Number(tree)], 0);
  process.exit(0);
}
const wants = (option('--class') || '').split(',').filter(Boolean), nots = (option('--not') || '').split(',').filter(Boolean);
const region = option('--in') ? option('--in').split(',').map(Number) : null;
const text = option('--text'), limit = Number(option('--limit') || 40);
const found = items.filter(it => wants.every(w => it.c.includes(w)) && !nots.some(w => it.c.includes(w)) && (!text || (it.t || '').includes(text))
  && (!region || (it.r[0] < region[0] + region[2] && it.r[0] + it.r[2] > region[0] && it.r[1] < region[1] + region[3] && it.r[1] + it.r[3] > region[1])));
if (flag('--items')) {
  for (const it of found.slice(0, limit)) console.log(`#${it.i} p${it.p ?? '-'} ${it.c} [${it.r.join(', ')}]${it.t ? ` "${it.t}"` : ''}${it.k ? ` k=${it.k}` : ''}${it.row ? ` row=${it.row}` : ''}${it.a ? ' ' + JSON.stringify(it.a) : ''} s${it.s}`);
} else {
  const groups = new Map();
  for (const it of found) { const key = it.c.replace(/\s+/g, ' ') + '|' + it.s; if (!groups.has(key)) groups.set(key, []); groups.get(key).push(it); }
  for (const [key, list] of [...groups].sort((a, b) => b[1].length - a[1].length).slice(0, limit)) {
    const it = list[0];
    console.log(`${String(list.length).padStart(4)} × ${it.c}\n       보기 #${it.i} [${it.r.join(', ')}]${it.t ? ` "${it.t}"` : ''}\n       ${JSON.stringify(styles[it.s])}`);
    void key;
  }
}
console.log(`— ${found.length}개`);

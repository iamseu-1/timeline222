// 지도자 칸의 단 나누기 벡터 뽑기(4단계 배치 갈래 둘째 검토 고침 — 계약 1-1 덧붙임 '단 나누기') — Node가 정답이다.
// `js/timeline.js`의 순수 도우미 `_leaderLanes`(내보내기 strips.mjs가 칸 종류 1의 lane으로 부름)를 정답지 자료가 닿지 않는 갈래로 돌려
// prototype/engine/tests/fixtures/lay/leader-lanes.json에 적고, Rust 거울 `lay::rows::leader_lanes`가 같은 답을 내는지
// prototype/engine/tests/lay_rows.rs(leader_lanes_match_node_vectors)가 견준다.
// 갈래마다 손으로 적은 기댓값(expect — 그 갈래를 정말 지나는지)과 JS 답이 다르면 멈춘다(도우미의 뜻이 바뀐 것 — 계약을 먼저 본다).
// 사용(작업 폴더에서):
//   node prototype/scripts/leader-lanes-vectors.mjs           → 벡터 파일을 쓴다
//   node prototype/scripts/leader-lanes-vectors.mjs --check   → 벡터 파일이 지금 JS 답과 같은지만 본다(다르면 끝 코드 1)
// 꼴: { cases: [{ name, p: 띠(endY · leaders), want: { n, lane, over } }] } — p는 JSON 그대로(undefined는 열쇠를 뺀 것 · null은 null).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bootWeb } from './export/base.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const outFile = path.resolve(here, '..', 'engine', 'tests', 'fixtures', 'lay', 'leader-lanes.json');
const check = process.argv.includes('--check');

const HT = bootWeb();
const leaderLanes = p => HT.Timeline.prototype._leaderLanes.call(null, p); // 자료만 보는 순수 도우미(this를 쓰지 않음)
const cell = (name, start, end, status) => Object.assign({ name }, start === undefined ? null : { start }, end === undefined ? null : { end }, status ? { status } : null);

const CASES = [
  {
    name: '섭정 — 품은 후보 없이 겹친 후보만(같은 차례에서 처음 겹친 후보의 단) · 품은 후보 · 아무와도 겹치지 않음',
    p: { endY: 1100, leaders: [cell('첫왕', 1000, 1050), cell('둘째왕', 1030, 1080, 'joint'), cell('섭정 들녘', 1060, 1070, 'regent'), cell('섭정 바람', 1081, 1084, 'regent'), cell('섭정 물결', 1075, 1090, 'regent'), cell('셋째왕', 1085, 1100)] },
    expect: { n: 2, lane: [0, 1, 1, 0, 1, 0], over: 0 }, // 물결(1075 ~ 1090)은 둘째왕(단 1)과 셋째왕(단 0) 모두와 겹치고 품은 후보가 없다 → 차례가 앞인 둘째왕
  },
  {
    name: '섭정 — 겹친 후보가 여럿이면 시작이 앞인 쪽(목록 차례가 뒤여도)',
    p: { endY: 1100, leaders: [cell('셋째왕', 1085, 1100), cell('첫왕', 1000, 1050), cell('둘째왕', 1030, 1080, 'claim'), cell('섭정 물결', 1075, 1090, 'regent')] },
    expect: { n: 2, lane: [0, 0, 1, 1], over: 0 },
  },
  {
    name: '시작 · 끝이 수가 아닌 칸은 후보도 섭정도 아니고 단 0(빈 칸 · 시작 null · 글 시작 · 끝 null은 띠 끝)',
    p: { endY: 1100, leaders: [cell('가', 1000, 1050, 'joint'), null, cell('나', null, 1040), cell('다', '1030', 1060), cell('라', 1020, null), cell('마', 1025), cell('바 섭정', null, 1030, 'regent')] },
    expect: { n: 3, lane: [0, 0, 0, 0, 1, 2, 0], over: 0 },
  },
  {
    name: '띠 끝도 칸 끝도 없으면 후보가 아님',
    p: { leaders: [cell('가', 1000, 1050, 'joint'), cell('나', 1020), cell('다', 1030, 1040)] },
    expect: { n: 2, lane: [0, 0, 1], over: 0 },
  },
  {
    name: '시작이 같은 칸 — 목록 순번 차례(주장이 앞)',
    p: { endY: 1060, leaders: [cell('주장 가', 1000, 1050, 'claim'), cell('나', 1000, 1040), cell('다', 1040, 1060)] },
    expect: { n: 2, lane: [0, 1, 1], over: 0 },
  },
  {
    name: '시작이 같은 칸 — 목록 순번 차례(주장이 뒤)',
    p: { endY: 1060, leaders: [cell('나', 1000, 1040), cell('주장 가', 1000, 1050, 'claim'), cell('다', 1040, 1060)] },
    expect: { n: 2, lane: [0, 1, 0], over: 0 },
  },
  {
    name: '넘친 칸(4단 넘음 — 마지막 단)을 품은 섭정 · 넘친 뒤 빈 단',
    p: { endY: 1100, leaders: [cell('공 하나', 1000, 1020, 'joint'), cell('공 둘', 1000, 1020, 'joint'), cell('공 셋', 1000, 1020, 'joint'), cell('공 넷', 1000, 1020, 'joint'), cell('공 다섯', 1010, 1060, 'joint'), cell('섭정', 1030, 1050, 'regent'), cell('공 여섯', 1030, 1040, 'joint')] },
    expect: { n: 4, lane: [0, 1, 2, 3, 3, 3, 0], over: 1 },
  },
  {
    name: '공동 · 주장 칸이 없으면 겹쳐도 한 단(정통성 없이 겹친 옛 자료 · 명목 · 섭정만)',
    p: { endY: 1100, leaders: [cell('가', 1000, 1060), cell('나', 1040, 1100, 'nominal'), cell('다', 1050, 1070, 'regent')] },
    expect: { n: 1, lane: [0, 0, 0], over: 0 },
  },
  {
    name: '공동 칸이 맞닿기만 하면 한 단 · 공동이 아닌 칸끼리만 겹치면 한 단',
    p: { endY: 1100, leaders: [cell('가', 1000, 1050, 'joint'), cell('나', 1050, 1100), cell('다', 1060, 1080)] },
    expect: { n: 1, lane: [0, 0, 0], over: 0 },
  },
];

const cases = CASES.map(c => {
  const r = leaderLanes(JSON.parse(JSON.stringify(c.p)));
  const want = { n: r.n, lane: r.lane, over: r.over };
  if (JSON.stringify(want) !== JSON.stringify(c.expect)) throw new Error(`갈래 "${c.name}": JS 답 ${JSON.stringify(want)} ≠ 기댓값 ${JSON.stringify(c.expect)}`);
  return { name: c.name, p: c.p, want };
});
const text = `${JSON.stringify({ cases }, null, 1)}\n`;
if (check) {
  const now = fs.existsSync(outFile) ? fs.readFileSync(outFile, 'utf8') : '';
  if (now !== text) { console.error(`leader-lanes-vectors: ${path.relative(process.cwd(), outFile)}가 낡았습니다 — node prototype/scripts/leader-lanes-vectors.mjs`); process.exit(1); }
  console.log(`leader-lanes-vectors: 같음 · 갈래 ${cases.length}`);
} else {
  fs.writeFileSync(outFile, text);
  console.log(`leader-lanes-vectors: ${path.relative(process.cwd(), outFile)} · 갈래 ${cases.length}`);
}

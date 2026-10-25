/* 메이커 '만드는 묶음' 검사(10건 5(나) 1 · 2) — 줄 묶음 붙여넣기(js/maker-paste.js)와 넓힌 한꺼번에 고치기(js/maker-grid.js의 bulkPlan · bulkDialog).
   node scripts/maker-paste-check.mjs <검사할 폴더> <결과 폴더> [--node]
   ① 노드: 붙여넣기 해석(머리글 짐작 · 열 맞추기 · 날짜 · 잘못된 줄 · 예전 한 줄 글 꼴은 손대지 않음)과 일괄 고침 계산(국성 · 태그 · 대범위 · 소속 · 덮어쓰기 · 건너뛰기)
   ② 브라우저(--node가 없을 때): dlc-maker.html에 가상 나라 넷의 작업본을 두고 구조 나무에서 여럿을 골라 오른쪽 칸의 일괄 고침 → 되돌리기 한 걸음,
      소속 덮어쓰기 확인 글, 고를 수 없는 칸 감춤, 지도자 목록에 표(TSV) 붙여넣기 → 미리 보기(빨간 줄 · 열 바꾸기) → 넣기 → 저장.
   자료는 모두 가상 이름이고 별도 창의 메모리 · 그 창의 브라우저 저장소에만 둡니다. 크로미움은 HT_BROWSER · HT_PLAYWRIGHT_ROOT로 고릅니다(다른 브라우저 검사와 같음). */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

/** 노드 검사 — HT(calendar · core · maker · maker-grid · maker-drag · maker-paste를 읽은 것)를 받아 결과 글을 돌려줍니다(틀리면 assert가 던짐) */
export function checkMakerPaste(HT) {
  const P = HT.makerPaste, G = HT.makerGrid;
  assert.ok(P && typeof P.analyze === 'function' && typeof P.open === 'function', 'HT.makerPaste가 없음');
  assert.ok(G && typeof G.bulkPlan === 'function', 'HT.makerGrid.bulkPlan이 없음');
  const rows = a => a.rows.map(r => [r.cell, r.error]);
  /* 노드 맥락이 따로라(vm) 배열 · 객체의 원형이 달라 deepEqual을 못 쓰므로, 열쇠 차례를 맞춘 글로 견줍니다 */
  const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const same = (got, want, msg) => assert.equal(canon(got), canon(want), msg);
  /* 머리글 짐작: '대표 이름'이 있으면 '이름'은 본명으로, '이름'뿐이면 대표 이름으로 */
  let a = P.analyze('대수\t대표 이름\t이름\t시작\t끝\t메모\n1\t솔왕\t가온\t100\t130\t첫 임금\n2\t별왕\t나래\t130\t미정\t', 'leaders');
  assert.equal(a.head, true); same(a.map, ['ordinal', 'name', 'given', 'start', 'end', 'note']);
  same(rows(a), [[{ name: '솔왕', given: '가온', note: '첫 임금', start: 100, end: 130, ordinal: 1 }, ''], [{ name: '별왕', given: '나래', start: 130, endUnknown: true, ordinal: 2 }, '']]);
  same(P.analyze('이름\t시작\t끝\n솔왕\t100\t130', 'leaders').map, ['name', 'start', 'end']);
  same(P.analyze('묘호\t시호\t시작\t왕조\t지위\t가문\n솔조\t큰왕\t100\t솔 왕조\t왕\t갑 가문', 'leaders').rows[0].cell, { temple: '솔조', title: '큰왕', dynasty: '솔 왕조', rank: '왕', house: '갑 가문', start: 100 });
  /* 머리글이 없을 때: 내용으로 짐작(제n대 → 대수 · 날짜 둘 → 시작 · 끝 · 글 열 → 이름 · 메모 / 1 · 2 · 3 … → 대수 / 기간 한 칸) */
  a = P.analyze('제1대\t솔왕\t100\t130\t메모 하나\n제2대\t별왕\t130\t160\t', 'leaders');
  assert.equal(a.head, false); same(a.map, ['ordinal', 'name', 'start', 'end', 'note']);
  same(P.analyze('1\t솔왕\t100\t130\n2\t별왕\t130\t160\n3\t강왕\t160\t190', 'leaders').map, ['ordinal', 'name', 'start', 'end']);
  a = P.analyze('솔왕\t100-130\n별왕\t130~음력 160-02-03', 'leaders');
  same(a.map, ['name', 'range']); assert.equal(a.rows[0].cell.end, 130); assert.equal(a.rows[1].cell.endAt, '음력 160-02-03');
  /* 날짜: 기원전 · 세기 · 미정 · 날짜 글 — 기존 날짜 읽기(HT.readDate) 그대로 */
  a = P.analyze('연호\t시작\t끝\n솔 연호\t기원전 50\t-20\n별 연호\t3세기 중반\t미정\n물 연호\t미정\t300-05-01', 'eras');
  same(rows(a).map(r => r[1]), ['', '', '']);
  assert.equal(a.rows[0].cell.start, -50); assert.equal(a.rows[1].cell.startAt, '3세기 중반'); assert.equal(a.rows[1].cell.endUnknown, true); assert.equal(a.rows[2].cell.startUnknown, true); assert.equal(a.rows[2].cell.endAt, '300-05-01');
  /* 잘못된 줄: 까닭을 적고 넣지 않음(cell은 읽은 만큼) */
  a = P.analyze('대수\t이름\t시작\t끝\n1\t솔왕\t날짜 아님\t130\n가\t별왕\t100\t130\n3\t\t100\t130\n4\t강왕\t180\t170\n5\t물왕\t\t200', 'leaders');
  const errs = a.rows.map(r => r.error);
  assert.match(errs[0], /시작 "날짜 아님"을\(를\) 읽을 수 없음/); assert.match(errs[1], /대수 "가"/); assert.match(errs[2], /이름이 없음/); assert.match(errs[3], /끝이 시작보다 앞섬/); assert.match(errs[4], /시작이 없음/);
  assert.equal(P.leftoverText(a).split('\n').length, 6, '읽지 못한 줄은 머리글과 함께 글 칸에 남김');
  /* 도읍: 역할 열(정도 · 배도 …) · 모르는 역할은 까닭 */
  a = P.analyze('도시\t시작\t끝\t역할\n솔 도읍\t100\t200\t정도\n별 도읍\t150\t\t배도\n물 도읍\t160\t170\t아무거나', 'capitals');
  same(a.rows[0].cell, { city: '솔 도읍', start: 100, end: 200 }); assert.equal(a.rows[1].cell.role, 'secondary'); assert.match(a.rows[2].error, /역할 "아무거나"/);
  /* 지위 변천: 시작을 비울 수 있는 것은 첫 줄뿐 (폼에 이미 줄이 있으면 첫 줄도 안 됨) */
  a = P.analyze('지위\t시작\t끝\n공\t\t300\n왕\t\t400', 'ranks');
  assert.equal(a.rows[0].error, ''); assert.match(a.rows[1].error, /첫 줄뿐/);
  assert.match(P.analyze('지위\t시작\t끝\n공\t\t300', 'ranks', { existing: 1 }).rows[0].error, /시작이 없음/);
  /* 열 맞추기를 바꾸면: 한 칸은 한 열만(겹친 칸은 받지 않음) · 머리글 끄기 */
  a = P.analyze('이름\t시작\t끝\n솔왕\t100\t130', 'leaders', { map: ['name', 'start', 'start'] });
  same(a.map, ['name', 'start', '']); assert.equal(a.rows[0].cell.end, undefined);
  a = P.analyze('이름\t시작\t끝\n솔왕\t100\t130', 'leaders', { head: false });
  assert.equal(a.rows.length, 2); assert.match(a.rows[0].error, /시작/);
  /* 예전 한 줄 글 꼴은 이 파일이 손대지 않음(null → core.js의 HT.textToCells가 그대로) · 쉼표 표는 머리글이 있을 때만 */
  assert.equal(P.analyze('솔왕 100-130\n별왕 130~160 메모, 글', 'leaders'), null);
  assert.equal(P.analyze('솔왕,100,130', 'leaders'), null);
  same(P.analyze('이름,시작,끝\n솔왕,100,130', 'leaders').rows[0].cell, { name: '솔왕', start: 100, end: 130 });
  const probs = []; assert.equal(HT.textToCells('솔왕 100-130\n별왕 130~160', '지도자', probs).length, 2); assert.equal(probs.length, 0);
  assert.equal(P.analyze('a\tb', 'figures'), null, '모르는 줄 목록');
  /* 큰따옴표로 감싼 칸(엑셀이 줄바꿈 · 탭이 든 칸을 복사하는 꼴) */
  same(P.splitTable('"가\n나"\t1\n다\t"2""3"', '\t'), [['가\n나', '1'], ['다', '2"3']]);

  /* 일괄 고침 계산 — 가상 팩 둘(고치는 DLC b2-check · 불러온 팩 other) */
  const other = HT.draft.clean({ id: 'other', name: '불러온 가상 팩', tracks: [{ id: 't', name: '들녘' }], periods: [{ id: 'z', track: 't', name: '별나라', start: 100, end: 300, partOf: [{ polity: '솔나라', start: 120, end: 200 }, { polity: '강나라', start: 200 }] }] });
  const own = HT.draft.clean({ id: 'b2-check', name: '일괄 검사', tracks: [{ id: 't', name: '들녘' }, { id: 'u', name: '물가' }], houses: [{ id: 'h1', name: '갑 가문' }],
    periods: [{ id: 'a', track: 't', name: '솔나라', start: 100, end: 300 }, { id: 'b', track: 't', name: '강나라', start: 100, end: 300, partOf: '솔나라' }, { id: 'c', track: 'u', name: '물나라', start: 100, end: 300 }],
    events: [{ id: 'e', track: 't', title: '가상 모임', start: 150, tags: '하나, 둘' }], figures: [{ id: 'f', track: 't', name: '가상 사람', start: 120, end: 160 }],
    scopes: [{ id: 's1', track: 't', name: '들녘 모둠', members: ['솔나라'] }] });
  const packs = [HT.normalizePack(other).pack, HT.normalizePack(own).pack];
  const model = HT.buildModel(packs, null), base = HT.buildModel([packs[0]], null);
  const env = (locked = false) => ({ model, isLocked: () => locked, rawOf: x => HT.draft.findOwn(HT.draft.clean(HT.packToJSON(packs[0])), x.id).item, baseModel: () => base });
  const run = (uids, op, locked) => G.bulkPlan(structuredClone(own), uids, op, env(locked));
  const before = JSON.stringify(own);
  let r = run(['b2-check/a', 'b2-check/f', 'b2-check/e'], { key: 'house', text: '갑 가문' });
  assert.equal(r.changed, 2); assert.equal(r.skipped, 1); assert.equal(r.draft.periods[0].house, '갑 가문'); assert.equal(r.draft.figures[0].house, '갑 가문'); assert.equal(r.draft.events[0].house, undefined);
  r = run(['b2-check/e'], { key: 'tags', text: '셋, 하나', mode: 'add' }); same(r.draft.events[0].tags, ['하나', '둘', '셋']);
  r = run(['b2-check/e'], { key: 'tags', text: '하나', mode: 'remove' }); same(r.draft.events[0].tags, ['둘']);
  r = run(['b2-check/e'], { key: 'tags', text: '없는 태그', mode: 'remove' }); assert.equal(r.changed, 0); assert.equal(r.same, 1); assert.equal(r.draft.events[0].tags, '하나, 둘', '바뀌지 않는 항목은 꼴도 그대로');
  r = run(['b2-check/a', 'b2-check/b', 'b2-check/c', 'other/z', 'b2-check/e'], { key: 'scope', text: 's1', mode: 'add' });
  assert.equal(r.changed, 2); assert.equal(r.same, 1); assert.equal(r.skipped, 2); same(r.draft.scopes[0].members, ['솔나라', '강나라', '별나라']); assert.equal(r.draft.patches.length, 0, '대범위에 넣어도 남의 나라는 고치지 않음');
  assert.throws(() => run(['b2-check/a'], { key: 'scope', text: 's1', mode: 'remove' }), /하나도 남지 않습니다/);
  assert.throws(() => run(['b2-check/a'], { key: 'scope', text: '없는 대범위', mode: 'add' }), /찾지 못했습니다/);
  r = run(['b2-check/b', 'other/z', 'b2-check/a'], { key: 'partOf', text: '솔나라', relation: 'tributary' });
  assert.equal(r.changed, 2); same(r.reasons, ['제 자신을 소속으로 둘 수 없음']);
  same(r.draft.periods[1].partOf, [{ polity: '솔나라', relation: 'tributary' }]);
  same(r.draft.patches, [{ target: 'other/z', set: { partOf: [{ polity: '솔나라', relation: 'tributary' }] } }], '남의 항목은 바뀐 칸만 덮어쓰기로');
  assert.equal(HT.packToJSON(HT.normalizePack(r.draft).pack).formatVersion, 2, '소속 관계를 쓴 파일은 형식 2 (새 열쇠 없음 — 3이 아님)');
  r = run(['b2-check/b'], { key: 'partOf', text: '', relation: '' }); assert.equal('partOf' in r.draft.periods[1], false, '비우면 소속을 지움');
  r = run(['other/z'], { key: 'partOf', text: '솔나라' }, true); assert.equal(r.skipped, 1); assert.equal(r.draft.patches.length, 0, '잠긴 팩은 건너뜀');
  r = run(['b2-check/a', 'b2-check/b'], { key: 'people', text: '들녘 사람' }); same(r.draft.periods.slice(0, 2).map(p => p.people), ['들녘 사람', '들녘 사람']);
  assert.equal(JSON.stringify(own), before, '계산은 넘긴 작업본만 고침');
  /* 고를 수 없는 조합은 감춤: 사건엔 국성 · 소속 · 대범위가 없고 시대엔 태그가 없음 · 대범위는 고치는 DLC에 대범위가 있을 때만 */
  same(['house', 'tags', 'scope', 'partOf'].map(k => G.bulkFits(k, 'events', own)), [false, true, false, false]);
  same(['house', 'tags', 'scope', 'partOf'].map(k => G.bulkFits(k, 'periods', own)), [true, false, true, true]);
  assert.equal(G.bulkFits('scope', 'periods', { ...own, scopes: [] }), false);
  assert.equal(G.bulkFits('house', 'figures', own), true);
  return { 붙여넣기: '머리글 짐작 · 내용 짐작 · 기간 한 칸 · 날짜(기원전 · 세기 · 음력 · 미정) · 잘못된 줄 · 남길 글 · 도읍 역할 · 지위 첫 줄 · 열 바꾸기 · 예전 꼴 · 쉼표 표 통과', 일괄: '국성 · 가문 · 태그 · 대범위 · 소속(덮어쓰기 · 관계 · 비움 · 잠김) · 감춤 통과' };
}

/* 통째 붙여넣기 검사용 가상 답 — docs/프롬프트-DLC-메이커-칸-채우기.md의 출력 형식(칸 블록 #HT칸 1 … #끝 + 사람이 읽는 근거 · 확인 필요). 이름은 모두 가상 */
const WHOLE = `# 솔나라 — 칸 블록

조사 방법: 검색 없이 기억으로 작성
대상: 새 정권

\`\`\`
#HT칸 1
나라,솔나라,-57,935,가상 들녘,국가,솔겨레,솔씨,35.8
꼬리표,세 나라
연대,반전설,전승,,
설명,솔강 가에서 솔씨가 세운 가상 나라입니다. 935년에 별나라에 넘어갔습니다.
실재근거,초기 기록이 전설에 기댐
쟁점,건국 연대를 사서대로 볼지 고고학으로 볼지 갈립니다.
이름,率國,ko-Hani,원어,,,
이름,서라솔,ko,옛 이름,-57,503,옛 국호
소속,강나라,조공·책봉국,400,450,끔,짧은 예속
승계,옛솔,부분 승계,중,지배층 · 백성,유민이 넘어옴
승계,들마을,간접 승계,,,같은 땅
지위,왕,-57,,,스스로 일컬음
지도자,1,솔시조,-57,4,전승,나라를 세움
지도자,2,솔이왕,4,24,,
지도자,3,솔삼왕,24,3세기 중반,추정,
지도자,4,솔사왕,3세기 중반,935,,
지도자칭호,솔시조,,,솔가람
지도자칭호,솔이왕,,,솔누리
지도자계보,솔시조,,추대
지도자계보,솔이왕,아들,세습
지도자계보,솔삼왕,동생,세습
지도자계보,솔사왕,미상,정변
연호,솔빛,500,,,솔사왕
도읍,솔고을,-57,,정도,,첫 도읍
도읍,강마을,600,700,배도,추정,
도읍이름,솔고을,서라솔
도읍이름,강마을,,,두 서울
체계,가상 학자의 세 시기,가상 개설서
시기,가상 학자의 세 시기,상대,-57,654
시기,가상 학자의 세 시기,중대,654,780
시기,가상 학자의 세 시기,하대,780,
폭,지도자,솔시조,-60,-55,,
폭,나라,,-100,-50,,
이설,지도자,솔이왕,5,25,이듬해부터 셈,가상 사서,
이설,도읍,강마을,,,다른 비정지 물가설,가상 논문,
이설,나라,,100,935,고고학 연대,가상 보고서,
문서,== 개요 ==
문서,'''솔나라'''는 가상 나라다.[* 가상 사서]
이어받은나라,갑 왕국,간접 승계,가상 까닭 ([가상 출처](https://example.org/a_(b)))
이어받은나라,없는 왕국,직접 승계,가상
속했던나라,병 왕국,조공·책봉국,400,450
#끝
\`\`\`

## 근거
- 이름: 가상 사서 — 사료

## 확인 필요
- 솔사왕의 시작 — 가상 위키로만 채움
`;

/** 통째 붙여넣기 노드 검사 — 칸 블록 읽기(parseWhole) · 합치기(mergeWhole) · 요약(wholeSummary) · 알아보기(isWhole) · 다른 나라(linkOther) · 링크 풀기(unlink) */
export function checkWholePaste(HT) {
  const P = HT.makerPaste;
  assert.ok(P && typeof P.parseWhole === 'function' && typeof P.openWhole === 'function' && P.LAYERS, 'HT.makerPaste.parseWhole · LAYERS가 없음');
  const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const same = (got, want, msg) => assert.equal(canon(got), canon(want), msg);
  const tracks = [{ id: 'b2-plain', name: '가상 들녘' }, { id: 'b2-sea', name: '가상 바다' }];
  /* ① 칸 블록 하나 → 모든 칸 (블록 밖의 근거 · 확인 필요는 보지 않음) */
  let r = P.parseWhole(WHOLE, { tracks });
  same([r.problems, r.found, r.version], [[], 1, 1], '칸 블록은 문제 없음');
  const f = r.fields, L = r.lists;
  same([f.name, f.start, f.end, f.track, f.kind, f.people, f.house, f.tags, f.northSouth], ['솔나라', -57, 935, 'b2-plain', 'state', '솔겨레', '솔씨', ['세 나라'], 35.8], '나라 · 꼬리표 층');
  assert.match(f.description, /^솔강 가에서[\s\S]*넘어갔습니다\.$/);
  same(L.names, [{ text: '率國', lang: 'ko-Hani', kind: 'native' }, { text: '서라솔', lang: 'ko', kind: 'former', start: -57, end: 503, note: '옛 국호' }], '이름 층');
  same(L.partOf, [{ polity: '강나라', relation: 'tributary', start: 400, end: 450, nest: false, note: '짧은 예속' }], '소속 층');
  same(L.succeeds, [{ from: '옛솔', type: 'partial', degree: 2, parts: ['elite', 'people'], note: '유민이 넘어옴' }, { from: '들마을', type: 'indirect', note: '같은 땅' }], '승계 층');
  same(L.ranks, [{ name: '왕', start: -57, note: '스스로 일컬음' }], '지위 층');
  same(L.leaders.map(c => [c.name, c.given || '', c.ordinal, c.start, c.end, c.certainty || '']), [['솔시조', '솔가람', 1, -57, 4, 'legend'], ['솔이왕', '솔누리', 2, 4, 24, ''], ['솔삼왕', '', 3, 24, 234, 'estimated'], ['솔사왕', '', 4, 234, 935, '']], '지도자 층 + 지도자칭호');
  same([L.leaders[0].startRange, L.leaders[1].alternatives, L.leaders[0].accession, L.leaders[1].accession, L.leaders[3].accession], [[-60, -55], [{ start: 5, end: 25, label: '이듬해부터 셈', source: '가상 사서' }], { how: 'acclamation' }, { kin: 'son', how: 'hereditary' }, { kinUnknown: true, how: 'coup' }], '폭 · 이설 · 지도자계보');
  same(L.eras, [{ name: '솔빛', start: 500, note: '솔사왕' }], '연호 층');
  same(L.capitals, [{ city: '솔고을', start: -57, as: '서라솔', note: '첫 도읍' }, { city: '강마을', start: 600, end: 700, role: 'secondary', group: '두 서울', certainty: 'estimated', alternatives: [{ label: '다른 비정지 물가설', source: '가상 논문' }] }], '도읍 층 + 도읍이름 · 이설');
  same(L.phases, [{ scheme: '가상 학자의 세 시기', note: '가상 개설서', spans: [{ name: '상대', start: -57, end: 654 }, { name: '중대', start: 654, end: 780 }, { name: '하대', start: 780 }] }], '체계 · 시기 층');
  same([f.historicity, f.historicityNote, f.certainty, f.startRange, 'endRange' in f, f.debate], ['semi', '초기 기록이 전설에 기댐', 'legend', [-100, -50], false, '건국 연대를 사서대로 볼지 고고학으로 볼지 갈립니다.'], '연대 · 실재근거 · 쟁점 · 나라의 폭');
  same(L.alternatives, [{ start: 100, end: 935, label: '고고학 연대', source: '가상 보고서' }], '나라의 이설');
  assert.equal(f.wiki, "== 개요 ==\n'''솔나라'''는 가상 나라다.[* 가상 사서]", '문서 층은 줄을 이어 붙임');
  assert.equal(L.cabinets, undefined, '없는 층은 비움');
  /* ② 블록만 · 코드 블록 없이 · CRLF · 쉼표 뒤 빈칸도 같은 값 */
  const block = WHOLE.slice(WHOLE.indexOf('#HT칸'), WHOLE.indexOf('#끝') + 2);
  for (const [text, what] of [[block, '블록만'], [WHOLE.replace(/\n/g, '\r\n'), 'CRLF'], [WHOLE.replace('지도자,2,솔이왕,4,24,,', '지도자, 2, 솔이왕 , 4, 24, ,'), '빈칸']]) {
    const o = P.parseWhole(text, { tracks });
    same(o.problems, [], `${what}: 문제 없음`);
    same(o.lists.leaders.map(c => [c.name, c.certainty || '']), [['솔시조', 'legend'], ['솔이왕', ''], ['솔삼왕', 'estimated'], ['솔사왕', '']], `${what}: 지도자`);
    assert.equal(o.fields.description, f.description, `${what}: 설명`);
  }
  /* ③ 끊긴 답 + "계속"으로 이어 받은 블록: 줄을 이어 읽고 되풀이한 줄은 한 번 · 끝 표시가 없으면 알림 */
  const cut = WHOLE.slice(0, WHOLE.indexOf('지도자,3,'));
  const rest = '#HT칸 1\n' + WHOLE.slice(WHOLE.indexOf('지도자,2,'), WHOLE.indexOf('#끝')) + '#끝\n';
  r = P.parseWhole(cut + '\n' + rest, { tracks });
  same([r.lists.leaders.map(c => c.name), r.problems, r.found], [['솔시조', '솔이왕', '솔삼왕', '솔사왕'], [], 2], '이어 받은 블록');
  assert.match(P.parseWhole(cut, { tracks }).problems.join(), /끝 표시\(#끝\)가 없습니다/, '끊긴 채로 끝나면 알림');
  /* 줄 한가운데서 끊긴 답: 끊긴 블록의 마지막 줄은 버리고 이어진 블록의 온전한 줄을 씀 (글 층도 두 번 붙지 않음) */
  for (const at of ['지도자,2,솔', "문서,'''솔나라'''는"]) {
    const head = WHOLE.slice(0, WHOLE.indexOf(at) + at.length);
    const tail = '```\n\n이어서 씁니다.\n\n```\n#HT칸 1\n' + WHOLE.slice(WHOLE.indexOf(at));
    r = P.parseWhole(head + '\n' + tail, { tracks });
    same([r.lists.leaders.map(c => c.name), r.problems, r.fields.wiki], [['솔시조', '솔이왕', '솔삼왕', '솔사왕'], [], f.wiki], `"${at}"에서 끊긴 답`);
  }
  /* ④ 읽지 못한 것: 모르는 트랙 · 모르는 확실성(그 줄은 빼고 거기 붙을 폭도) · 자리 넘침 · 모르는 층 · 열쇠가 없는 덧층 */
  r = P.parseWhole(WHOLE.replace(',가상 들녘,', ',없는 들녘,').replace('지도자,1,솔시조,-57,4,전승,', '지도자,1,솔시조,-57,4,아마도,').replace('도읍이름,솔고을,서라솔', '도읍이름,솔고을,서라솔,,,넘침').replace('#끝', '지도작,1,잘못\n지도자칭호,없는 임금,,,이름\n#끝'), { tracks });
  assert.equal(r.fields.track, undefined, '모르는 트랙은 바꾸지 않음');
  const pj = r.problems.join('\n');
  for (const re of [/\(나라\): 트랙 "없는 들녘"/, /\(지도자\): 넣지 않았습니다 — 확실성 "아마도"/, /\(폭\): 지도자 "솔시조" 줄이 없습니다/, /\(도읍이름\): 자리가 4개인데 5개입니다/, /모르는 층 "지도작"/, /\(지도자칭호\): "없는 임금" 줄이 없습니다/]) assert.match(pj, re);
  assert.match(pj, /^\d+번째 줄/, '문제마다 붙여넣은 글의 줄 번호');
  same(r.lists.leaders.map(c => c.name), ['솔이왕', '솔삼왕', '솔사왕'], '읽지 못한 줄만 뺌');
  /* ⑤ 끝 '현재' · 시작 '미정' + 연대 층의 배치용 연도 */
  r = P.parseWhole(WHOLE.replace('나라,솔나라,-57,935,', '나라,솔나라,미정,현재,').replace('연대,반전설,전승,,', '연대,반전설,전승,-60,'), { tracks });
  same([r.fields.startUnknown, r.fields.start, r.fields.ongoing, 'end' in r.fields], [true, -60, true, false], '미정 시작의 배치용 연도 · 현재까지');
  /* ⑥ 합치기: 낱칸은 적힌 것만, 줄 목록은 바꾸기 · 보태기, 소속의 줄인 꼴도 목록으로 */
  r = P.parseWhole(WHOLE, { tracks });
  const cur = { name: '', start: 1, end: 2, track: 'b2-sea', color: '#a0bcc5', leaders: [{ name: '옛 임금', start: 1 }], partOf: '옛나라', cabinets: [{ name: '옛 내각', start: 1 }] };
  let m = P.mergeWhole(cur, r, 'replace');
  same([m.name, m.start, m.startAt, m.end, m.ongoing, m.track, m.color, m.leaders.length, m.partOf.length, m.cabinets.length], ['솔나라', -57, null, 935, false, 'b2-plain', '#a0bcc5', 4, 1, 1], '바꾸기: 블록에 있는 목록만 통째로 · 없는 칸은 그대로');
  m = P.mergeWhole(cur, r, 'append');
  same([m.leaders.map(c => c.name)[0], m.leaders.length, m.partOf.map(p => p.polity)], ['옛 임금', 5, ['옛나라', '강나라']], '보태기: 있는 줄 뒤에');
  m.leaders[1].name = '바뀜';
  assert.equal(r.lists.leaders[0].name, '솔시조', '합친 값을 고쳐도 읽은 답은 그대로');
  /* ⑦ 요약 · 원어 층만 따로 받은 블록 — 편집 창에 이미 있는 줄에 붙음 */
  const sum = P.wholeSummary(P.parseWhole(WHOLE, { tracks }), cur, { tracks });
  same(sum.map(x => x.label), ['기본 칸', '설명', '이름(원어 등)', '소속·예속', '승계', '지위 변천', '지도자', '연호', '도읍', '시기 구분', '나라의 이설', '남북 위치', '연대 · 실재성', '문서'], '요약 줄');
  same(sum.filter(x => x.clash).map(x => x.label), ['소속·예속', '지도자'], '있는 줄이 있는 목록만 바꾸기 · 보태기를 물음');
  r = P.parseWhole('#HT칸 1\n나라,솔나라\n원어,지도자,옛 임금,舊王,ko-Hani,원어,\n원어,연호,없는 연호,無,ko-Hani,원어,\n#끝', { tracks });
  m = P.mergeWhole(cur, r, 'replace');
  same(m.leaders[0].names, [{ text: '舊王', lang: 'ko-Hani', kind: 'native' }], '원어가 있는 줄에 붙음');
  assert.match(P.wholeSummary(r, cur, {}).find(x => x.label === '원어 이름').text, /^1개 · 줄을 찾지 못한 1개\(없는 연호\)/);
  /* ⑧ 알아보기: 칸 블록이 있는 글만(쉼표 표 · 마크다운 절은 표 붙여넣기로) */
  assert.equal(P.isWhole(WHOLE), true);
  assert.equal(P.isWhole('제목,시작\n가상 일,100'), false);
  assert.equal(P.isWhole('## 1. 기본 칸\n\n| 칸 | 값 |\n## 6. 지도자'), false);
  /* ⑨ 다른 나라 층(이어받은나라 · 속했던나라) · 링크 풀기 · 그 나라의 원본에 넣기(더함 · 같음 · 바꿈) */
  r = P.parseWhole(WHOLE, { tracks });
  same(r.others, [{ kind: 'succ', name: '갑 왕국', type: 'indirect', note: '가상 까닭 (가상 출처)' }, { kind: 'succ', name: '없는 왕국', type: 'direct', note: '가상' }, { kind: 'member', name: '병 왕국', relation: 'tributary', start: 400, end: 450 }], '다른 나라 층');
  assert.ok(P.parseWhole(WHOLE.replace('이어받은나라,없는 왕국,직접 승계,가상', '이어받은나라,없는 왕국,아무 승계,가상'), { tracks }).problems.some(p => /승계 종류 "아무 승계"/.test(p)), '모르는 승계 종류는 알림');
  same([P.unlink('설명 ([출처](https://a.org/x_(y)?q=1)) [[안쪽]]'), P.unlink('[출처](https://a.org/z)', 'source'), P.unlink('([출처](https://a.org/z))', 'namu'), P.unlink('[글](없는주소)')], ['설명 (출처) [[안쪽]]', '출처 https://a.org/z', '([[https://a.org/z|출처]])', '[글](없는주소)'], '마크다운 링크 풀기');
  assert.equal(P.parseWhole(WHOLE.replace('넘어갔습니다.\n', '넘어갔습니다. ([가상 출처](https://example.org/d))\n'), { tracks }).fields.description.endsWith('넘어갔습니다. (가상 출처)'), true, '설명의 출처 링크는 이름만');
  const gap = { name: '갑 왕국', succeeds: ['옛 왕국'] };
  assert.equal(P.linkOther(gap, r.others[0], '솔나라'), 'added');
  same(gap.succeeds, [{ from: '옛 왕국', type: 'indirect' }, { from: '솔나라', type: 'indirect', note: '가상 까닭 (가상 출처)' }], '승계 칸에 더함');
  assert.equal(P.linkOther(gap, r.others[0], '솔나라'), 'same', '두 번 넣어도 한 줄');
  assert.equal(P.linkOther(gap, Object.assign({}, r.others[0], { type: 'direct' }), '솔나라'), 'updated');
  assert.equal(gap.succeeds[1].type, 'direct', '종류가 다르면 바꿈(메모는 그대로)');
  const byeong = { name: '병 왕국', partOf: '정 왕국' };
  assert.equal(P.linkOther(byeong, r.others[2], '솔나라'), 'added');
  same(byeong.partOf, [{ polity: '정 왕국' }, { polity: '솔나라', relation: 'tributary', start: 400, end: 450 }], '소속 칸에 더함(줄인 꼴도 목록으로)');
  assert.equal(P.linkOther(byeong, r.others[2], '솔나라'), 'same');
  /* ⑩ 층 표: 층마다 자리가 있고(글 층은 text) 덧층 · 대상은 줄 목록을 가리킴 */
  for (const [tag, d] of Object.entries(P.LAYERS)) assert.ok(d.text || d.rest || (Array.isArray(d.cols) && d.cols.length), `층 ${tag}의 자리`);
  /* ⑪ 블록의 줄 묶음 붙여넣기도 확실성 열을 받음 */
  same(P.analyze('연호,시작,확실성\n솔빛,500,추정\n별빛,600,통설', 'eras').rows.map(x => x.cell), [{ name: '솔빛', start: 500, certainty: 'estimated' }, { name: '별빛', start: 600 }], '줄 묶음의 확실성 열');
  /* ⑫ 인물 층(지도자가 아닌 사람 — 즉위하지 않은 왕족 · 왕비 · 장수): 계보(기본) · 활동 · 덧층 · 원어 대상 인물 · 지도자계보의 모 · 읽지 못한 줄 */
  r = P.parseWhole(PEOPLE, { tracks });
  same(r.lists.leaders[0].parents, [{ who: '바위군', as: 'father' }, { who: '달빛 부인', as: 'mother' }], '지도자계보의 부 · 모 — 부가 인물 층의 사람');
  same(r.people.map(p => [p.name, p.lineageOnly, p.role || '']), [['바위군', true, '왕족'], ['달빛 부인', true, '왕비'], ['굳센 장수', false, '장군'], ['먼 사람', true, '']], '인물 층의 사람 · 계보/활동 · 직함');
  same([r.people[0].order, r.people[0].certainty, r.people[0].description], [1, 'legend', '솔왕의 아버지 — 오르지 않음'], '인물계보(형제 순서 · 확실성) · 메모');
  same(r.people[1].refs, { spouses: ['바위군'] }, '배우자 자리');
  const gs = r.people[2];
  same([gs.birth, gs.death, gs.refs, gs.service, gs.importance, gs.aka, gs.names, gs.description], [-40, 20, { father: '솔왕' }, { start: -20, end: 10, office: '대장군' }, 2, ['굳센', '큰칼'], [{ text: '堅將', lang: 'ko-Hani', kind: 'native' }], '북쪽을 지킴, 이름난 장수'], '활동 인물 — 인물활동 · 인물별칭 · 원어 층');
  assert.equal(r.problems.length, 3, `읽지 못한 인물 줄 셋(날짜 없는 활동 · 겹친 이름 · 미상): ${r.problems.join(' / ')}`);
  assert.ok(r.problems.every(p => /^\d+번째 줄\(인물\)/.test(p)), '문제에 줄 번호');
  same(P.wholeSummary(r, {}).find(x => x.label === '사람'), { label: '사람', text: '4명 · 계보 3 · 활동 1' }, '미리 보기 요약의 사람 줄');
  /* ⑬ 시대구분 · 대범위 층 — 읽기(others · 시대구분의 기간은 연도만 · 겹친 줄 · 이름 없음) */
  r = P.parseWhole(ERA, { tracks });
  same(r.others, [
    { kind: 'epoch', name: '세 강 시대', start: -120, end: 212 },
    { kind: 'epoch', name: '빈 시대' },
    { kind: 'epoch', name: '늦은 시대', start: 300 },
    { kind: 'scope', name: '아홉 불씨 할거', label: '할거', host: '등불 왕국' },
  ], '시대구분 · 대범위 층');
  assert.equal(r.problems.length, 3, `읽지 못한 것 셋(미정 끝 · 겹친 대범위 · 이름 없음): ${r.problems.join(' / ')}`);
  assert.ok(/^5번째 줄\(시대구분\): «늦은 시대»의 끝 "미정"/.test(r.problems[0]) && /«아홉 불씨 할거» 줄이 이미 있습니다/.test(r.problems[1]) && /이름이 없습니다/.test(r.problems[2]), `읽지 못한 것의 글: ${r.problems.join(' / ')}`);
  /* ⑭ 내 DLC의 대범위에 넣기(joinScope) — 시대 구분까지 새로 · 있는 대범위에 더함 · 같음 · 다른 트랙 · 남의 시대 구분(같은 트랙 · 공통) · 기간 없음 · 남의 대범위 · 트랙 없음 */
  const [eraIt, blankIt, , scopeIt] = r.others;
  const sol = { name: '솔나라', track: 'b2-plain' };
  const d = { epochs: [], scopes: [] };
  let j = P.joinScope(d, eraIt, sol);
  same([j.result, j.epochNew, d.epochs, d.scopes], ['new', true, [{ name: '세 강 시대', track: 'b2-plain', start: -120, end: 212 }], [{ track: 'b2-plain', epoch: '세 강 시대', members: ['솔나라'] }]], '없는 시대 구분 → 시대 구분과 그것을 가리키는 대범위를 새로');
  j = P.joinScope(d, eraIt, { name: '별나라', track: 'b2-plain' });
  same([j.result, j.epochNew, d.epochs.length, d.scopes.length, d.scopes[0].members], ['added', false, 1, 1, ['솔나라', '별나라']], '있는 시대 구분의 대범위에 더함');
  assert.equal(P.joinScope(d, eraIt, sol).result, 'same', '두 번 넣어도 한 번');
  j = P.joinScope(d, eraIt, { name: '물나라', track: 'b2-sea' });
  same([j.result, j.epochNew, d.epochs.map(e => e.track), d.scopes.map(s => s.track)], ['new', true, ['b2-plain', 'b2-sea'], ['b2-plain', 'b2-sea']], '다른 트랙의 나라는 그 트랙에 따로(대범위는 같은 트랙만 모음)');
  const ctx = { epochs: [{ name: '남의 시대', id: 'ep-x', track: 'b2-plain' }, { name: '공통 시대' }, { name: '바다 시대', track: 'b2-sea' }] };
  const d2 = { epochs: [], scopes: [] };
  same([P.joinScope(d2, { kind: 'epoch', name: '남의 시대' }, sol, ctx).result, P.joinScope(d2, { kind: 'epoch', name: '공통 시대' }, sol, ctx).result, d2.epochs.length, d2.scopes.map(s => s.epoch)], ['new', 'new', 0, ['남의 시대', '공통 시대']], '남의 시대 구분(같은 트랙 · 공통)은 이름으로 가리키고 새로 만들지 않음');
  j = P.joinScope(d2, { kind: 'epoch', name: '바다 시대' }, sol, ctx);
  assert.ok(j.result === 'none' && /기간/.test(j.why) && d2.scopes.length === 2, '다른 트랙의 시대 구분은 가리키지 않음 — 기간이 없으면 못 넣음');
  j = P.joinScope(d2, blankIt, sol, ctx);
  assert.ok(j.result === 'none' && /«빈 시대».*기간/.test(j.why) && !d2.epochs.length, `연표에 없고 기간도 없는 시대 구분: ${j.why}`);
  const d3 = { scopes: [{ track: 'b2-plain', name: '세 강 시대', members: [] }] };
  j = P.joinScope(d3, eraIt, sol);
  assert.ok(j.result === 'added' && !j.epochNew && !d3.epochs && d3.scopes[0].members[0] === '솔나라', '시대 구분을 적지 않은 같은 이름의 내 대범위에는 그대로 더함(시대 구분은 만들지 않음)');
  /* 대범위 층: 새로(성격 · 본국) · 있는 것에 더함(비운 성격 · 본국만 채움) · 이름이나 "트랙:이름" · { polity }로 이미 든 나라 · 본국이 이 나라 · 남의 대범위 · 트랙 없음 */
  const d4 = { scopes: [] };
  j = P.joinScope(d4, scopeIt, sol);
  same([j.result, d4.scopes], ['new', [{ track: 'b2-plain', name: '아홉 불씨 할거', label: '할거', host: '등불 왕국', members: ['솔나라'] }]], '없는 대범위는 새로');
  const d5 = { scopes: [{ track: 'b2-plain', name: '아홉 불씨 할거', label: '부흥', members: '별나라' }] };
  j = P.joinScope(d5, scopeIt, sol);
  same([j.result, d5.scopes[0]], ['added', { track: 'b2-plain', name: '아홉 불씨 할거', label: '부흥', members: ['별나라', '솔나라'], host: '등불 왕국' }], '있는 대범위에 더함 — 적힌 성격은 그대로, 빈 본국만 채움');
  for (const m of ['b2-plain:솔나라', { polity: '솔나라' }, { track: 'b2-plain', polity: 'p-sol' }]) {
    const d6 = { scopes: [{ track: 'b2-plain', name: '아홉 불씨 할거', members: [m] }] };
    assert.equal(P.joinScope(d6, scopeIt, { name: '솔나라', track: 'b2-plain', id: 'p-sol' }).result, 'updated', `이미 든 나라(${JSON.stringify(m)})는 더하지 않고 빈 성격 · 본국만 채움`);
  }
  j = P.joinScope({ scopes: [] }, { kind: 'scope', name: '새 묶음', host: '솔나라' }, sol);
  assert.ok(j.result === 'new' && !('host' in j.scope), '본국이 이 나라면 적지 않음');
  const d7 = { scopes: [] };
  j = P.joinScope(d7, scopeIt, sol, { scopes: [{ name: '아홉 불씨 할거', track: 'b2-plain', packName: '가상 남의 팩' }] });
  assert.ok(j.result === 'foreign' && /가상 남의 팩/.test(j.why) && !d7.scopes.length, '남의 DLC의 대범위는 고치지 못함');
  assert.ok(P.joinScope({ scopes: [] }, scopeIt, { name: '솔나라', track: '' }).result === 'none', '트랙이 없으면 못 넣음');
  /* 새 항목은 ctx.add로(메이커는 HT.draft.addItem — id를 매김) */
  const made = [];
  P.joinScope({ epochs: [], scopes: [] }, eraIt, sol, { add: (list, obj) => (made.push(list), Object.assign(obj, { id: `${list}-1` })) });
  same(made, ['epochs', 'scopes'], '새 시대 구분 · 대범위는 ctx.add로');
  return '칸 블록 · 블록만 · CRLF · 빈칸 · 이어 받은 블록(끊긴 줄) · 읽지 못한 것(줄 번호) · 미정 · 현재 · 바꾸기 · 보태기 · 원어 층 · 요약 · 알아보기 · 다른 나라 층 · 링크 풀기 · 층 표 · 줄 묶음 확실성 · 인물 층 · 시대구분 · 대범위 층 통과';
}
/* 시대구분 · 대범위 층의 꼴 보기(가상) — 넷째 줄은 끝이 미정(시대 구분의 기간은 연도만), 뒤의 두 줄은 겹친 대범위 · 이름 없는 시대구분 */
const ERA = ['#HT칸 1', '나라,솔나라,-57,935,가상 들녘', '시대구분,세 강 시대,-120,212', '시대구분,빈 시대', '시대구분,늦은 시대,300,미정',
  '대범위,아홉 불씨 할거,할거,등불 왕국', '대범위,아홉 불씨 할거', '시대구분,', '#끝'].join('\n');
/* 인물 층의 꼴 보기(가상) — 지도자계보의 부 · 모가 인물 층의 사람을 가리킴 */
const PEOPLE = ['#HT칸 1', '나라,솔나라', '지도자,1,솔왕,-57,4', '지도자계보,솔왕,,추대,,바위군,,달빛 부인',
  '인물,바위군,왕족,,,,,,,솔왕의 아버지 — 오르지 않음', '인물계보,바위군,,1,전승',
  '인물,달빛 부인,왕비,,,,,바위군,계보', '인물,굳센 장수,장군,-40,20,솔왕,,,활동,북쪽을 지킴, 이름난 장수',
  '인물활동,굳센 장수,-20,10,대장군,2', '인물별칭,굳센 장수,굳센·큰칼', '원어,인물,굳센 장수,堅將,ko-Hani,원어',
  '인물,먼 사람,,,,,,,활동', '인물,굳센 장수', '인물,미상', '#끝'].join('\n');

/* 형식 4 층(5단계 과제 7) — 객체 · 빌림 · 직위줄 · 직위칸 · 실권 */
const F4 = ['#HT칸 1', '나라,솔나라,-57,935,가상 들녘', '소속,강나라,구성국', '소속,들나라,조공·책봉국,400,450', '객체,도시,대립,3,강나라',
  '빌림,지도자,강나라/지도자,등좌', '직위줄,집정관', '직위칸,집정관,1,갑,-50,-20,전승,첫 집정관', '직위칸,집정관,2,을,-20,10', '직위줄,등좌,들나라/지도자',
  '실권,들나라,400,450,섭정,들나라의 실권을 쥠', '#끝'].join('\n');
const F4_BAD = ['#HT칸 1', '나라,솔나라', '객체,괴물,엉뚱,9,없는나라', '빌림,사람,강나라', '빌림,내각,', '직위칸,없는줄,1,갑,1,2', '직위줄,빌린줄,강나라', '직위칸,빌린줄,1,갑,1,2', '실권,,1,2', '#끝'].join('\n');
export function checkFormat4Layers(HT) {
  const P = HT.makerPaste;
  const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const same = (got, want, msg) => assert.equal(canon(got), canon(want), msg);
  const tracks = [{ id: 'b2-plain', name: '가상 들녘' }];
  const r = P.parseWhole(F4, { tracks });
  same(r.problems, [], '형식 4 층은 문제 없음');
  const f = r.fields, L = r.lists;
  same([f.type, f.status, f.importance, f.leadersFrom], ['city', 'rival', 3, { name: '등좌', from: '강나라/지도자' }], '① 객체 층의 종류 · 정통성 · 중요도 · 빌림 층');
  same(L.partOf.map(p => [p.polity, p.main === true]), [['강나라', true], ['들나라', false]], '① 으뜸은 그 소속 줄에');
  same(L.offices.map(o => [o.name, o.from || (o.cells || []).map(c => [c.ordinal, c.name, c.start, c.end, c.certainty || ''])]), [['집정관', [[1, '갑', -50, -20, 'legend'], [2, '을', -20, 10, '']]], ['등좌', '들나라/지도자']], '② 직위줄 · 직위칸(지도자 칸과 같은 자리) · 빌려 오기');
  same(L.power, [{ name: '섭정', over: '들나라', start: 400, end: 450, note: '들나라의 실권을 쥠' }], '③ 실권 층');
  const merged = P.mergeWhole({ name: '솔나라', leaders: [{ name: '옛 임금', start: 1, end: 2 }] }, r);
  same([merged.type, merged.status, merged.importance, merged.leadersFrom, merged.offices.length, merged.power.length, merged.partOf[0].main, merged.leaders.length], ['city', 'rival', 3, { name: '등좌', from: '강나라/지도자' }, 2, 1, true, 1], '④ 합치면 항목의 형식 4 칸으로(지도자 칸은 그대로)');
  const sum = P.wholeSummary(r, {}, { tracks });
  assert.ok(sum.some(x => x.label === '객체(형식 4)' && /종류 도시 · 정통성 대립 · 중요도 3 · 지도자 자리 빌림 강나라\/지도자 · 으뜸 강나라/.test(x.text)), '④ 미리 보기 요약의 객체 줄');
  assert.ok(sum.some(x => x.label === '직위 줄 더' && x.text === '2줄') && sum.some(x => x.label === '실권' && x.text === '1줄'), '④ 미리 보기 요약의 직위 줄 더 · 실권');
  const bad = P.parseWhole(F4_BAD, { tracks });
  const want = ['종류 "괴물"', '정통성 "엉뚱"', '중요도 "9"', '으뜸 "없는나라"', '자리 "사람"', '출처(', '"없는줄" 직위 줄이 없습니다', '빌린 줄이라', '상대(빼앗긴 객체'];
  for (const w of want) assert.ok(bad.problems.some(p => p.includes(w)), `틀린 줄의 알림: ${w} — ${bad.problems.join(' / ')}`);
  assert.equal(bad.fields.type, undefined);
  /* 프롬프트 문서의 예시 칸 블록은 모두 문제 없이 읽혀야 한다 */
  const doc = fs.readFileSync(path.join(root4(), 'docs/프롬프트-DLC-메이커-칸-채우기.md'), 'utf8');
  const blocks = [...doc.matchAll(/^#HT칸 \d+[\s\S]*?^#끝/gm)].map(m => m[0]).filter(b => !b.includes('〈')); // 자리표(〈…〉)가 든 틀 블록은 빼고 보기 블록만
  assert.ok(blocks.length >= 1, '프롬프트 문서에 예시 칸 블록이 있음');
  const probs = blocks.flatMap((b, i) => P.parseWhole(b, { tracks: [{ id: 'korea', name: '한국' }, { id: 'japan', name: '일본' }, { id: 'china', name: '중국' }, { id: 'b2-plain', name: '가상 들녘' }] }).problems.map(p => `블록 ${i + 1}: ${p}`));
  assert.deepEqual(probs, [], '프롬프트 예시 블록 문제 0');
  return { 형식4층: 9, 예시블록: blocks.length };
}
const root4 = () => path.resolve(process.argv[2] || '.');

/* 판 2(#HT칸 2 — 프롬프트를 형식 4 낱말로 · 5단계 잔여 과제 1) 검사용 가상 답 */
const V2 = ['#HT칸 2',
  '객체,솔나라,100,300,가상 들녘,제후국,들사람,솔씨,30,대립,2',
  '그릇,들 시대,시대',
  '시대,들 시대,50,400,가상 들녘,분열기,큰나라,들녘에 나라가 여럿 선 시대',
  '그릇,큰나라,나라,,,켬',
  '섬김,큰나라,봉국,,,봉을 받음',
  '승계,옛솔,간접 승계,선양',
  '지도자,1,솔왕,100,150',
  '지도자자리,솔왕,,,,대립',
  '직위줄,재상',
  '직위칸,재상,1,갑재상,110,140',
  '폭,직위칸,갑재상,108,112',
  '원어,직위칸,갑재상,甲,ko-Hani,원어',
  '실권,,200,250,세도 정치',
  '실권,먼나라,260,280,섭정',
  '구성원,작은솔,,,켬',
  '구성원,작은별,150,',
  '주기,동녘,갑·을·병,4,세차',
  '주기,서녘,,,,새해,622,50',
  '사람,솔부인,왕비,,,,,솔왕',
  '이어받은객체,뒷솔,직접 승계,상속,이음',
  '섬긴객체,들마을,복속,120,180',
  '#끝'].join('\n');
export function checkLayers2(HT) {
  const P = HT.makerPaste;
  const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const same = (got, want, msg) => assert.equal(canon(got), canon(want), msg);
  const tracks = [{ id: 'b2-plain', name: '가상 들녘' }];
  const spheres = [{ id: 'east-x', name: '동녘' }, { id: 'west-x', name: '서녘' }];
  const r = P.parseWhole(V2, { tracks, spheres });
  assert.equal(r.version, 2);
  const f = r.fields, L = r.lists;
  same([f.name, f.start, f.end, f.track, f.type, f.kind, f.people, f.house, f.northSouth, f.status, f.importance], ['솔나라', 100, 300, 'b2-plain', 'principality', undefined, '들사람', '솔씨', 30, 'rival', 2], '① 객체 층 — 종류는 형식 4 · 정통성 · 중요도');
  same(L.partOf.map(p => [p.polity, p.relation || '', p.nest === true, p.main === true]), [['큰나라', 'fief', true, true]], '② 그릇(나라)은 상위 띠에 접기 — 같은 상대의 기간 없는 섬김 줄이 있으면 그 줄에(으뜸)');
  same(L.power, [{ name: '세도 정치', start: 200, end: 250 }, { name: '섭정', over: '먼나라', start: 260, end: 280 }], '③ 실권 — 상대 없이 이름만 = 제 안의 실권자');
  same(L.offices[0].cells.map(c => [c.name, c.startRange || null, (c.names || []).map(n => n.text)]), [['갑재상', [108, 112], ['甲']]], '④ 대상 직위칸의 폭 · 원어');
  const ep = r.others.find(o => o.kind === 'epoch');
  same(ep, { kind: 'epoch', name: '들 시대', start: 50, end: 400, label: '분열기', host: '큰나라', description: '들녘에 나라가 여럿 선 시대' }, '⑤ 시대 그릇 → 대범위에 넣을 것(시대 줄의 제 칸 · 트랙은 이 객체의 트랙)');
  same(r.others.filter(o => o.kind === 'contain').map(o => [o.name, !!o.main]), [['작은솔', true], ['작은별', false]], '⑥ 구성원 → 그 객체의 그릇 칸에');
  same(r.others.filter(o => o.kind === 'cycle'), [{ kind: 'cycle', name: '동녘', sphere: 'east-x', names: ['갑', '을', '병'], start: 4, label: '세차' }, { kind: 'cycle', name: '서녘', sphere: 'west-x', era: '새해', from: 622, step: 50 }], '⑦ 주기 → 「주기」 표에 넣을 것');
  same(r.others.filter(o => o.kind === 'succ' || o.kind === 'member').map(o => [o.kind, o.name, o.how || '']), [['succ', '뒷솔', 'inheritance'], ['member', '들마을', '']], '⑧ 이어받은객체 · 섬긴객체는 판 1과 같은 길 · 이어받은객체의 방식은 담김(6단계 걸음 3)');
  same(L.succeeds.map(x => [x.from, x.type, x.how || '']), [['옛솔', 'indirect', 'abdication']], '⑧ 승계 층의 방식(선양)은 담김(6단계 걸음 3)');
  same(r.people.map(p => p.name), ['솔부인'], '⑨ 사람 층 = 판 1 인물');
  const want = ['(지도자자리): "솔왕" 칸의 정통성', '(구성원): «작은별»이(가) 든 기간']; // 승계 방식은 6단계 걸음 3부터 담김
  for (const w of want) assert.ok(r.problems.some(p => p.includes(w)), `⑩ 담지 못하는 것의 알림: ${w} — ${r.problems.join(' / ')}`);
  assert.equal(r.problems.length, want.length, `⑩ 알림은 그것뿐 — ${r.problems.join(' / ')}`);
  /* 합치기 · 저장 때 넣는 것 */
  const merged = P.mergeWhole({ name: '솔나라' }, r);
  same([merged.type, merged.status, merged.partOf.length, merged.power.length, merged.offices.length], ['principality', 'rival', 1, 2, 1], '⑪ 편집 창에 합침');
  /* 옛 꼴에서 담지 못하는 그릇: 기간 있는 그릇 · 상위 줄이 여럿일 때의 접기 */
  const many = P.parseWhole(['#HT칸 2', '객체,별나라', '섬김,큰나라,조공,10,20', '그릇,별 연방,연방,120,200', '#끝'].join('\n'), { tracks });
  for (const w of ['«별 연방»에 든 기간', '«별 연방»에 접기는 섬김 · 그릇 줄이 하나뿐일 때만']) assert.ok(many.problems.some(p => p.includes(w)), `② 알림: ${w} — ${many.problems.join(' / ')}`);
  const d = { id: 'mine', epochs: [], scopes: [], yearCycles: [{ sphere: 'west-x', names: ['가'], start: 1 }] };
  const js = P.joinScope(d, ep, { name: '솔나라', track: 'b2-plain' });
  same([js.result, js.epochNew, d.epochs[0], d.scopes[0]], ['new', true, { name: '들 시대', track: 'b2-plain', start: 50, end: 400, description: '들녘에 나라가 여럿 선 시대' }, { track: 'b2-plain', epoch: '들 시대', label: '분열기', host: '큰나라', members: ['솔나라'] }], '⑫ 시대 그릇 — 시대 구분 + 대범위(성격 · 본국)');
  const sp = P.joinScope({ epochs: [], scopes: [] }, Object.assign({}, ep, { sphere: 'east-x' }), { name: '솔나라', track: 'b2-plain' });
  assert.equal(sp.scope.epoch, '들 시대');
  const c1 = P.joinCycle(d, r.others.find(o => o.sphere === 'east-x')), c2 = P.joinCycle(d, r.others.find(o => o.sphere === 'west-x'));
  same([c1.result, c2.result, d.yearCycles.map(c => c.sphere)], ['new', 'same', ['west-x', 'east-x']], '⑬ 주기 — 그 문화권에 이미 있으면 그대로');
  same(d.yearCycles[1], { sphere: 'east-x', names: ['갑', '을', '병'], start: 4, label: '세차' }, '⑬ 주기 줄의 꼴');
  assert.equal(P.joinCycle(d, { kind: 'cycle', sphere: 'north-x', era: 'x' }, ['north-x']).result, 'same', '⑬ 다른 DLC에 있으면 그대로');
  const raw = { name: '작은솔', partOf: [{ polity: '솔나라', relation: 'vassal' }] };
  assert.equal(P.linkOther(raw, r.others.find(o => o.name === '작은솔'), '솔나라'), 'updated');
  same(raw.partOf, [{ polity: '솔나라', relation: 'vassal', nest: true, main: true }], '⑭ 구성원 — 그 객체의 같은 상대 줄에 접기 · 으뜸');
  const raw2 = { name: '작은별' };
  assert.equal(P.linkOther(raw2, r.others.find(o => o.name === '작은별'), '솔나라'), 'added');
  assert.equal(P.linkOther(raw2, r.others.find(o => o.name === '작은별'), '솔나라'), 'same', '⑭ 두 번 넣어도 같음');
  /* 판 1 답에 판 2의 층을 쓰면 알림이 판 2를 가리킴 · 판 1 답은 그대로(위의 checkWholePaste) */
  const mix = P.parseWhole('#HT칸 1\n나라,솔나라\n그릇,들 시대,시대\n#끝', { tracks });
  assert.ok(mix.problems.some(p => p.includes('#HT칸 2')), '⑮ 판 1 블록의 판 2 층은 알림');
  /* 정규화: 상대 없는 실권(이름만)은 남고, 둘 다 없으면 뺌 */
  const n = HT.normalizePack({ format: 'history-timeline-dlc', formatVersion: 3, id: 'v2-test', name: '판 2 시험', tracks: [{ id: 'b2-plain', name: '가상 들녘' }], periods: [{ id: 'sol', name: '솔나라', track: 'b2-plain', start: 100, end: 300, power: [{ name: '세도 정치', start: 200, end: 250 }, { start: 1 }] }] });
  same(n.pack.periods[0].power, [{ name: '세도 정치', start: 200, end: 250 }], '⑯ 정규화 — 제 안의 실권자');
  assert.ok((n.warnings || []).some(w => /상대\(over\)도 이름도 없어/.test(w.msg || w)), '⑯ 둘 다 없는 줄은 알리고 뺌');
  return { 판2: 16 };
}

/* 6단계 걸음 3(2026-10-24 · 세계사 결정 D2 · D8 · 승계 방식 how): 줄 묶음 붙여넣기의 이름 번호 열 · 종교 표, 통째 붙여넣기 판 2의 층 셋
   (지도자칭호 다섯째 자리 = 이름 번호 · 새 층 종교 · 승계 · 이어받은객체의 방식이 담김), 미리 보기 요약 줄, 다른 객체 승계에 넣는 방식, 프롬프트 문서의 층 표가 LAYERS2와 같은지. 이름은 가상 */
const W3 = ['#HT칸 2',
  '객체,높은 왕국,100,300,가상 들녘,국가',
  '승계,옛 왕국,직접 승계,선양,,,왕위를 물려받음',
  '승계,갈래 나라,부분 승계,갈라짐,중,백성,일부가 넘어옴',
  '종교,옛 신앙,100,180,,첫 국교',
  '종교,새 교회,180,,추정',
  '폭,종교,새 교회,175,185',
  '이설,종교,새 교회,190,,늦게 받아들였다는 견해,가상 연대기',
  '지도자,,헨리,100,150',
  '지도자칭호,헨리@100,,,하리,7',
  '지도자,,헨리,150,200',
  '지도자칭호,헨리@150,,큰손,,8세',
  '지도자,,에드,200,250',
  '이어받은객체,뒷 왕국,직접 승계,혼인,혼인으로 넘어감',
  '#끝'].join('\n');
export function checkWorld3(HT) {
  const P = HT.makerPaste;
  const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const same = (got, want, msg) => assert.equal(canon(got), canon(want), msg);
  const tracks = [{ id: 'b2-plain', name: '가상 들녘' }];
  let n = 0;
  /* ① 줄 묶음 붙여넣기 — 이름 번호 열(머리글 '이름 번호' · "8세"도 · 틀린 값은 그 줄을 넣지 않음) · 대수 칸의 "n세"는 이름 번호 칸으로 안내 */
  let a = P.analyze('대표 이름\t이름 번호\t시작\t끝\n헨리\t7\t100\t150\n헨리\t8세\t150\t200\n에드\t여덟\t200\t250', 'leaders');
  same(a.map, ['name', 'regnal', 'start', 'end'], '① 머리글 "이름 번호" → 이름 번호 열');
  same(a.rows.map(r => [r.cell.regnal ?? null, !!r.error]), [[7, false], [8, false], [null, true]], '① 이름 번호 7 · "8세" → 8 · 틀린 값은 넣지 않음');
  assert.match(a.rows[2].error, /이름 번호 "여덟"을\(를\) 읽을 수 없음 \(양의 정수/);
  assert.match(P.analyze('대수\t이름\t시작\n8세\t헨리\t100', 'leaders').rows[0].error, /"n세"는 이름 번호 칸에/, '① 대수 칸에 "8세"면 이름 번호 칸으로 안내');
  same(P.analyze('이름번호\t대표 이름\t시작\n0\t갑\t1', 'leaders').rows[0].error.includes('이름 번호 "0"'), true, '① 0은 이름 번호가 아님');
  n += 5;
  /* ② 종교 표 — 지위 변천과 같은 꼴(첫 줄만 시작을 비움 · 폼에 이미 줄이 있으면 첫 줄도 안 됨) · 확실성 · 별칭 머리글 */
  a = P.analyze('종교\t시작\t끝\t확실성\n옛 신앙\t\t180\t\n새 교회\t\t\t추정', 'faiths');
  assert.equal(a.rows[0].error, '', '② 첫 줄은 시작을 비워도 됨');
  assert.match(a.rows[1].error, /종교의 첫 줄뿐/, '② 둘째 줄부터는 시작이 있어야 함');
  assert.match(P.analyze('종교\t시작\n옛 신앙\t', 'faiths', { existing: 1 }).rows[0].error, /시작이 없음/, '② 폼에 이미 줄이 있으면 첫 줄도');
  same(P.analyze('신앙\t시작\t확실성\n새 교회\t180\t추정', 'faiths').rows[0].cell, { name: '새 교회', start: 180, certainty: 'estimated' }, '② 별칭 머리글 · 확실성');
  assert.match(P.analyze('종교\t시작\n\t100', 'faiths').rows[0].error, /종교가 없음/, '② 이름 없는 줄');
  n += 5;
  /* ③ 통째 붙여넣기 판 2 — 층 셋 */
  const r = P.parseWhole(W3, { tracks });
  same(r.problems, [], `③ 문제 없음: ${r.problems.join(' / ')}`);
  same(r.lists.succeeds.map(x => [x.from, x.type, x.how || '']), [['옛 왕국', 'direct', 'abdication'], ['갈래 나라', 'partial', 'split']], '③ 승계 층의 방식(선양 · 갈라짐)이 담김');
  same(r.lists.faiths.map(c => [c.name, c.start ?? null, c.end ?? null, c.certainty || '', !!c.startRange, (c.alternatives || []).length]), [['옛 신앙', 100, 180, '', false, 0], ['새 교회', 180, null, 'estimated', true, 1]], '③ 종교 층 · 대상 종교의 폭 · 이설');
  same(r.lists.leaders.map(c => [c.name, c.regnal ?? null, c.given || '', c.title || '', c.ordinal ?? null]), [['헨리', 7, '하리', '', null], ['헨리', 8, '', '큰손', null], ['에드', null, '', '', null]], '③ 지도자칭호 다섯째 자리 = 이름 번호("8세"도)');
  same(r.others.find(o => o.kind === 'succ'), { kind: 'succ', name: '뒷 왕국', type: 'direct', how: 'marriage', note: '혼인으로 넘어감' }, '③ 이어받은객체의 방식이 담김');
  n += 5;
  /* ④ 틀린 값 — 모르는 승계 방식 · 이름 없는 종교 · 이름 번호 0 · 옛 답(판 1)의 지도자칭호는 넷째 자리까지 */
  const bad = P.parseWhole(['#HT칸 2', '객체,낮은 나라,1,100,가상 들녘', '승계,옛 나라,직접 승계,세습', '종교,,10', '지도자,,갑,10', '지도자칭호,갑,,,,0', '이어받은객체,뒷 나라,직접 승계,모름', '#끝'].join('\n'), { tracks });
  for (const w of ['"옛 나라"의 방식 "세습"', '(종교): 넣지 않았습니다 — 종교가 없음', '(지도자): 넣지 않았습니다 — 이름 번호 "0"', '"뒷 나라"의 승계 방식 "모름"을(를) 알 수 없어 뺐습니다']) assert.ok(bad.problems.some(p => p.includes(w)), `④ 알림: ${w} — ${bad.problems.join(' / ')}`);
  assert.equal(bad.problems.length, 4, `④ 알림은 넷 — ${bad.problems.join(' / ')}`);
  same([bad.lists.succeeds[0].how, (bad.others[0] || {}).how], [undefined, undefined], '④ 모르는 방식은 뺌(승계 줄 · 다른 객체 줄은 남음)');
  assert.ok(P.parseWhole('#HT칸 1\n나라,솔나라\n지도자칭호,솔왕,,,,1\n#끝', { tracks }).problems.some(p => /자리가 4개인데 5개/.test(p)), '④ 판 1의 지도자칭호는 넷째 자리까지(이름 번호는 판 2)');
  n += 4;
  /* ⑤ 합치기 · 요약 */
  const cur = { name: '높은 왕국', faiths: [{ name: '옛것', start: 50 }] };
  same(P.mergeWhole(cur, r).faiths.map(c => c.name), ['옛 신앙', '새 교회'], '⑤ 바꾸기 — 종교 줄을 통째로');
  same(P.mergeWhole(cur, r, 'append').faiths.map(c => c.name), ['옛것', '옛 신앙', '새 교회'], '⑤ 보태기 — 있는 줄 뒤에');
  const sum = P.wholeSummary(r, cur, { tracks });
  const row = label => sum.find(x => x.label === label) || {};
  assert.ok(/^2줄 · 확실성 1 · 연대 폭 1 · 이설 1$/.test(row('종교').text) && row('종교').clash === true, `⑤ 요약의 종교 줄: ${JSON.stringify(row('종교'))}`);
  assert.equal(row('승계').text, '2줄 · 방식 선양 · 갈라짐', '⑤ 요약의 승계 줄에 방식');
  assert.equal(row('지도자').text, '3줄 · 이름 번호 2', '⑤ 요약의 지도자 줄에 이름 번호');
  n += 5;
  /* ⑥ 다른 객체의 승계 칸에 넣을 때 방식도 */
  const it = r.others.find(o => o.kind === 'succ');
  const raw = { name: '뒷 왕국' };
  assert.equal(P.linkOther(raw, it, '높은 왕국'), 'added');
  same(raw.succeeds, [{ from: '높은 왕국', type: 'direct', how: 'marriage', note: '혼인으로 넘어감' }], '⑥ 새 승계 줄에 방식');
  assert.equal(P.linkOther(raw, it, '높은 왕국'), 'same', '⑥ 두 번 넣어도 같음');
  const raw2 = { name: '뒷 왕국', succeeds: [{ from: '높은 왕국', type: 'direct', note: '있던 메모' }] };
  assert.equal(P.linkOther(raw2, it, '높은 왕국'), 'updated');
  same(raw2.succeeds, [{ from: '높은 왕국', type: 'direct', how: 'marriage', note: '있던 메모' }], '⑥ 있던 줄에 방식만 채움(메모는 그대로)');
  const raw3 = { name: '뒷 왕국', succeeds: [{ from: '높은 왕국', type: 'direct', how: 'conquest' }] };
  assert.equal(P.linkOther(raw3, Object.assign({}, it, { how: undefined }), '높은 왕국'), 'same', '⑥ 방식을 적지 않은 줄은 있던 방식을 지움 없이 그대로');
  n += 5;
  /* ⑦ 프롬프트 문서의 층 표 = LAYERS2(층 이름 · 자리 수) · 새 규칙(D3 넓혀 읽기 · 이름 번호와 대수 · D4 트랙 · 달력 다섯 · 방식 여덟) */
  const doc = fs.readFileSync(path.join(root4(), 'docs/프롬프트-DLC-메이커-칸-채우기.md'), 'utf8');
  const table = doc.slice(doc.indexOf('**층 표.**'), doc.indexOf('**꼴 보기'));
  const rows = [...table.matchAll(/^\| `([^`]+)` \| ([^|]+) \|/gm)].map(m => [m[1], m[2].trim()]);
  same(rows.map(x => x[0]).sort(), Object.keys(P.LAYERS2).sort(), '⑦ 문서의 층 표와 메이커의 판 2 층이 같음');
  const off = rows.filter(([tag, cols]) => { const d = P.LAYERS2[tag]; return d && d.cols && cols.split(' · ').length !== d.cols.length; }).map(([tag, cols]) => `${tag}(${cols.split(' · ').length} ≠ ${P.LAYERS2[tag].cols.length})`);
  same(off, [], '⑦ 층마다 자리 수가 같음');
  for (const piece of ['| `종교` | 종교 · 시작 · 끝 · 확실성 · 메모…', '열쇠 · 묘호 · 시호 · 본명 · 이름 번호', '`선양`', '`개명`', '방식이 여덟', '**세 자리를 넓혀 읽습니다.**', '**대수와 이름 번호는 다릅니다.**', '문화권 이름 하나로 트랙을 만들지 않습니다', '`히브리력 5784-07-15`', '`에티오피아력 2016-01-01`', '`콥트력 1740-01-01`', '`사카력 1945-01-01`', '`불기 2567-01-01`'])
    assert.ok(doc.includes(piece), `⑦ 프롬프트 문서에 "${piece}"`);
  n += 3;
  return { 걸음3: n };
}

/** 노드 검사 — 인물 층을 작업본에 적는 계획(js/maker-kin.js planPeople)과 세계표 창의 사람 더하기 계획(planRelative · applyRelative) */
export function checkPeoplePlan(HT) {
  const K = HT.makerKin;
  assert.ok(K && typeof K.planPeople === 'function' && typeof K.planRelative === 'function', 'HT.makerKin.planPeople · planRelative가 없음');
  const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(q => [q, x[q]])) : x));
  const same = (got, want, msg) => assert.equal(canon(got), canon(want), msg);
  const raw = {
    format: 'history-timeline-dlc', formatVersion: 3, id: 'pp', name: '가상 인물 층', version: '1.0.0', tracks: [{ id: 't', name: '가상 들' }],
    periods: [{ id: 'sol', track: 't', name: '솔나라', start: -57, end: 100, leaders: [{ name: '솔왕', start: -57, end: 4 }, { name: '별왕', start: 4, end: 100, parents: [{ who: '솔왕', as: 'father' }] }] }],
    figures: [{ id: 'f-old', track: 't', name: '바위군', lineageOnly: true }],
    events: [],
  };
  const model = () => HT.buildModel([HT.normalizePack(JSON.parse(JSON.stringify(raw))).pack]);
  let m = model();
  const sol = m.periods.find(p => p.name === '솔나라');
  /* 인물 층 → 있는 사람(같은 트랙 · 같은 이름의 제 인물)은 고침 · 없으면 새 사람 · 부는 이 나라의 지도자 칸 · 배우자는 이 블록의 사람 */
  const r = HT.makerPaste.parseWhole(PEOPLE, { tracks: m.tracks });
  const plan = K.planPeople(m, raw, sol, r.people);
  same([plan.add.map(f => f.name), plan.update.map(f => f.name), plan.skipped, plan.loose], [['달빛 부인', '굳센 장수', '먼 사람'], ['바위군'], [], []], '새 사람 셋 · 고침 하나');
  same(plan.update[0], { id: 'f-old', track: 't', name: '바위군', lineageOnly: true, role: '왕족', description: '솔왕의 아버지 — 오르지 않음', order: 1 }, '있는 사람은 그 id로 — 적은 칸만');
  const gs = plan.add.find(f => f.name === '굳센 장수');
  same([gs.parents, gs.service, gs.lineageOnly, gs.importance], [[{ who: '솔왕', as: 'father' }], [{ polity: '솔나라', start: -20, end: 10, office: '대장군' }], undefined, 2], '활동 인물 — 부는 지도자 칸 · 활동 기록은 이 나라');
  same(plan.add.find(f => f.name === '달빛 부인').spouses, [{ who: '바위군' }], '배우자는 이름으로(하나뿐)');
  const d = K.applyPeople(JSON.parse(JSON.stringify(raw)), plan);
  assert.equal(d.figures.length, 4, '작업본의 인물 넷');
  m = HT.buildModel([HT.normalizePack(d).pack]);
  const lead = HT.personOf(m, m.periods.find(p => p.name === '솔나라'), 'leader:0');
  assert.ok(lead && lead.children.some(e => e.node.figure && e.node.figure.name === '굳센 장수'), '넣은 뒤 모델에서 솔왕의 자식');
  /* 세계표 창의 사람 더하기: 자식(지도자 칸 아래) · 형제(같은 부모 줄) · 부모(제 지도자 칸의 부모 줄) · 형제를 이을 부모가 없으면 막음 */
  m = model();
  const s0 = HT.personOf(m, m.periods[0], 'leader:0').key;
  const s1 = HT.personOf(m, m.periods[0], 'leader:1').key;
  let p = K.planRelative(m, raw, s0, { rel: 'child', name: '새 아이', as: 'father' });
  same([p.fig.name, p.fig.track, p.fig.lineageOnly, p.fig.parents, p.edit], ['새 아이', 't', true, [{ who: '솔왕', as: 'father' }], null], '자식');
  p = K.planRelative(m, raw, s1, { rel: 'sibling', name: '별 아우' });
  same(p.fig.parents, [{ who: '솔왕', as: 'father' }], '형제 — 같은 부모 줄');
  assert.match(K.planRelative(m, raw, s0, { rel: 'sibling', name: '외톨' }).error, /부모가 적혀 있지 않아/, '부모 없는 사람의 형제는 막음');
  p = K.planRelative(m, raw, s0, { rel: 'parent', name: '솔 할아비', as: 'father' });
  const d2 = K.applyRelative(JSON.parse(JSON.stringify(raw)), p, null);
  same([d2.figures.at(-1).name, d2.periods[0].leaders[0].parents], ['솔 할아비', [{ who: '솔 할아비', as: 'father' }]], '부모 — 지도자 칸의 부모 줄에');
  assert.match(K.planRelative(m, raw, s1, { rel: 'parent', name: '또 아비', as: 'father' }).error, /이미 있습니다/, '같은 자리의 부모가 있으면 막음');
  p = K.planRelative(m, raw, s1, { rel: 'spouse', name: '별 왕비', role: '왕비' });
  same([p.fig.spouses, p.fig.role], [[{ who: '별왕' }], '왕비'], '배우자');
  assert.match(K.planRelative(m, raw, s0, { rel: 'child', name: '', unknown: false }).error, /이름/, '이름이 없으면 막음');
  assert.match(K.planRelative(m, raw, s0, { rel: 'child', name: '띠 사람', lineage: false }).error, /생 · 몰/, '띠 인물은 날짜가 있어야');
  return '인물 층 계획(고침 · 새 사람 · 지도자 칸 부 · 배우자 · 활동 기록) · 사람 더하기(자식 · 형제 · 부모 · 배우자 · 막음) 통과';
}

/** 검사할 폴더의 스크립트를 따로 된 노드 맥락에서 읽어 HT를 만듭니다 (화면 없이 — dev-smoke와 같은 빈 문서) */
function loadHT(root) {
  const noop = () => {};
  const el = () => ({ style: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false }, appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop, querySelector: () => null, querySelectorAll: () => [], getContext: () => ({ measureText: t => ({ width: String(t).length * 7 }), font: '' }) });
  const store = new Map();
  const sandbox = {
    console, setTimeout, clearTimeout, structuredClone, URL, TextEncoder, TextDecoder,
    document: { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop, removeEventListener: noop, getAnimations: () => [] },
    localStorage: { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) },
    matchMedia: () => ({ matches: false, addEventListener: noop, addListener: noop }), getComputedStyle: () => ({ getPropertyValue: () => '' }),
    requestAnimationFrame: cb => setTimeout(() => cb(Date.now()), 0), cancelAnimationFrame: id => clearTimeout(id), navigator: { userAgent: 'node' },
  };
  sandbox.window = sandbox; sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  for (const rel of ['js/calendar.js', 'js/core.js', 'js/maker.js', 'js/maker-grid.js', 'js/maker-drag.js', 'js/maker-paste.js', 'js/maker-kin.js']) vm.runInContext(fs.readFileSync(path.join(root, rel), 'utf8'), sandbox, { filename: rel });
  return sandbox.HT;
}

const main = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const root = path.resolve(process.argv[2] || '.'), output = path.resolve(process.argv[3] || '배포/메이커-묶음');
  fs.mkdirSync(output, { recursive: true });
  const report = { 화면: '1920×1080 · 100%', 노드: null, 검사: [], 오류: [] };
  const HT = loadHT(root);
  report.노드 = Object.assign(checkMakerPaste(HT), { 통째: checkWholePaste(HT), 인물: checkPeoplePlan(HT), 형식4: checkFormat4Layers(HT), 판2: checkLayers2(HT), 걸음3: checkWorld3(HT) });
  if (!process.argv.includes('--node')) await browserCheck(root, output, report);
  fs.writeFileSync(path.join(output, 'maker-paste-check.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ 노드: report.노드, 검사: report.검사.length, 오류: report.오류 }, null, 2));
  if (report.오류.length) process.exitCode = 1;
}

async function browserCheck(root, output, report) {
  const { chromium } = createRequire(process.env.HT_PLAYWRIGHT_ROOT || import.meta.url)('playwright');
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
  const server = http.createServer((req, res) => {
    try {
      const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
      const file = path.resolve(root, rel);
      if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
      const bytes = fs.readFileSync(file);
      res.writeHead(200, { 'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(bytes);
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ channel: process.env.HT_BROWSER || 'msedge', headless: true });
  const check = (condition, text, details) => { assert.ok(condition, text + (details ? '\n' + JSON.stringify(details) : '')); report.검사.push({ 검사: text, 결과: details || true }); };
  /* 가상 작업본 — 나라 넷(한 트랙 셋 + 다른 트랙 하나) · 사건 하나 · 대범위 하나 · 가문 하나. 둘째 나라는 소속이 둘(덮어쓰기 확인 글이 나와야 함) */
  const draft = {
    format: 'history-timeline-dlc', formatVersion: 2, id: 'b2-browser', name: '가상 묶음 검사', version: '1.0.0',
    tracks: [{ id: 'b2-plain', name: '가상 들녘', color: '#b6c398' }, { id: 'b2-sea', name: '가상 바다', color: '#a0bcc5' }],
    houses: [{ id: 'b2-house', name: '솔 가문' }],
    periods: [
      { id: 'pa', track: 'b2-plain', name: '갑 왕국', start: 100, end: 400 },
      { id: 'pb', track: 'b2-plain', name: '을 왕국', start: 150, end: 380, partOf: [{ polity: '갑 왕국', start: 150, end: 250 }, { polity: '병 왕국', start: 250 }] },
      { id: 'pc', track: 'b2-plain', name: '병 왕국', start: 120, end: 420, leaders: [['첫 임금', 120, 160]] },
      { id: 'pd', track: 'b2-sea', name: '정 왕국', start: 200, end: 500 },
    ],
    events: [{ id: 'ea', track: 'b2-plain', title: '가상 모임', start: 210, tags: ['모임'] }],
    scopes: [{ id: 'sa', track: 'b2-plain', name: '들녘 모둠', members: ['갑 왕국'] }],
  };
  try {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce', serviceWorkers: 'block' });
    await context.addInitScript(d => { try { if (!localStorage.getItem('ht.maker.draft')) localStorage.setItem('ht.maker.draft', JSON.stringify(d)); } catch {} }, draft);
    const page = await context.newPage();
    page.on('pageerror', e => report.오류.push(e.message));
    page.on('dialog', d => { report.오류.push('예상하지 않은 확인 창: ' + d.message()); d.dismiss(); });
    await page.goto('http://127.0.0.1:' + server.address().port + '/dlc-maker.html');
    await page.waitForFunction(() => document.querySelector('#mkStart')?.hidden && document.querySelector('[data-tuid="b2-browser/pa"]'));
    const saved = () => page.evaluate(() => JSON.parse(localStorage.getItem('ht.maker.draft')));
    const tree = uid => page.locator(`[data-tuid="b2-browser/${uid}"]`);
    const bulk = page.locator('.mk-props-bulk');
    /* ① 나라 셋을 고름 → 오른쪽 칸의 일괄 고침: 국성 · 소속 · 대범위는 보이고 태그는 감춤 */
    await tree('pa').click(); await tree('pb').click({ modifiers: ['Control'] }); await tree('pc').click({ modifiers: ['Control'] });
    await bulk.locator('select[name="field"]').waitFor();
    const fields = await bulk.locator('select[name="field"] option').evaluateAll(os => os.map(o => o.value));
    check(['house', 'scope', 'partOf'].every(k => fields.includes(k)) && !fields.includes('tags') && !fields.includes('category'), '나라만 고르면 국성 · 대범위 · 소속은 있고 태그 · 분류는 감춤', fields);
    check(await bulk.locator('select[name="field"] option[value="house"]').textContent() === '국성', '나라만 고르면 가문 칸의 이름은 국성');
    /* ② 국성 한꺼번에 → 작업본 세 나라 · 되돌리기 한 걸음 */
    await bulk.locator('select[name="field"]').selectOption('house');
    await bulk.locator('input[name="value"]').fill('솔 가문');
    await bulk.locator('button[type="submit"]').click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('ht.maker.draft')).periods.filter(p => p.house === '솔 가문').length === 3);
    let d = await saved();
    check(d.periods.map(p => p.house || '').join() === '솔 가문,솔 가문,솔 가문,', '국성을 세 나라에 한꺼번에 (고르지 않은 나라는 그대로)', d.periods.map(p => p.house));
    await page.waitForFunction(() => /3개 고침/.test(document.querySelector('.mk-props-bulk [data-bulk-result]')?.textContent || ''));
    await page.waitForFunction(() => !document.querySelector('.mk-props-bulk').hidden && /3개 한꺼번에/.test(document.querySelector('.mk-props-bulk h2').textContent));
    check(await bulk.locator('select[name="field"]').inputValue() === 'house' && /3개 고침/.test(await bulk.locator('[data-bulk-result]').textContent()), '적용한 뒤에도 세 나라가 골라진 채 고르던 칸 · 결과 글이 남음');
    await page.screenshot({ path: path.join(output, '일괄-고침-국성-1920-1배.png') });
    await page.keyboard.press('Control+z');
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('ht.maker.draft')).periods.every(p => !p.house));
    check(true, '되돌리기 한 번에 세 나라의 국성이 모두 돌아감');
    /* ③ 소속 정하기 — 소속이 둘인 을 왕국이 들어 있으면 한 번 알리고, 다시 누르면 적용 */
    if (!(await bulk.isVisible())) { await tree('pa').click(); await tree('pb').click({ modifiers: ['Control'] }); await tree('pc').click({ modifiers: ['Control'] }); }
    await bulk.locator('select[name="field"]').selectOption('partOf');
    await bulk.locator('input[name="value"]').fill('정 왕국');
    await bulk.locator('select[name="relation"]').selectOption('tributary');
    await bulk.locator('button[type="submit"]').click();
    const warn = bulk.locator('[data-bulk-warn]');
    await warn.waitFor();
    await page.screenshot({ path: path.join(output, '일괄-고침-소속-확인-1920-1배.png') });
    check(/을 왕국/.test(await warn.textContent()) && (await saved()).periods[1].partOf.length === 2, '소속이 여럿인 나라가 있으면 덮어쓰기 전에 확인 글(아직 바꾸지 않음)', await warn.textContent());
    await bulk.locator('button[type="submit"]').click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('ht.maker.draft')).periods.slice(0, 3).every(p => JSON.stringify(p.partOf) === JSON.stringify([{ polity: '정 왕국', relation: 'tributary' }])));
    check(true, '확인 뒤 세 나라의 소속이 한 줄(정 왕국 · 조공)로');
    /* ④ 대범위에 넣기 — 같은 트랙의 나라만 (정 왕국은 다른 트랙이라 건너뜀) */
    await tree('pd').click({ modifiers: ['Control'] });
    await page.waitForFunction(() => /4개 한꺼번에/.test(document.querySelector('.mk-props-bulk h2')?.textContent || ''));
    await bulk.locator('select[name="field"]').selectOption('scope');
    await bulk.locator('select[name="mode"]').selectOption('add');
    await bulk.locator('select[name="value"]').selectOption('sa');
    await bulk.locator('button[type="submit"]').click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('ht.maker.draft')).scopes[0].members.length === 3);
    d = await saved();
    check(JSON.stringify(d.scopes[0].members) === JSON.stringify(['갑 왕국', '을 왕국', '병 왕국']), '대범위에 같은 트랙의 나라만 넣음', d.scopes[0].members);
    await page.waitForFunction(() => /건너뜀 \(대범위와 트랙이 다른 나라\)/.test(document.querySelector('.mk-props-bulk [data-bulk-result]')?.textContent || ''));
    check(true, '다른 트랙의 나라는 까닭과 함께 건너뜀');
    /* ④-2 나라와 사건을 함께 고르면 국성(나라) · 태그(사건)가 함께 보이고, 태그는 사건에만 들어감(나라는 까닭과 함께 건너뜀) */
    const evRow = page.locator('[data-tuid="b2-browser/ea"]');
    for (const key of ['events', 'events:b2-plain']) { // 사건 묶음(과 그 트랙 묶음)이 접혀 있으면 펼침
      const g = page.locator(`[data-tgroup="${key}"]`);
      if (!(await evRow.count()) && await g.count() && await g.getAttribute('aria-expanded') !== 'true') await g.click();
    }
    await evRow.waitFor();
    await tree('pa').click(); await evRow.click({ modifiers: ['Control'] });
    await page.waitForFunction(() => !document.querySelector('.mk-props-bulk').hidden && /2개 한꺼번에/.test(document.querySelector('.mk-props-bulk h2').textContent));
    const mixed = await bulk.locator('select[name="field"] option').evaluateAll(os => os.map(o => o.value));
    check(['house', 'tags', 'category', 'partOf', 'scope'].every(k => mixed.includes(k)), '나라 + 사건을 고르면 두 쪽의 칸이 모두 보임', mixed);
    await bulk.locator('select[name="field"]').selectOption('tags');
    await bulk.locator('select[name="mode"]').selectOption('add');
    await bulk.locator('input[name="value"]').fill('들녘, 모임');
    await bulk.locator('button[type="submit"]').click();
    await page.waitForFunction(() => JSON.stringify(JSON.parse(localStorage.getItem('ht.maker.draft')).events[0].tags) === JSON.stringify(['모임', '들녘']));
    await page.waitForFunction(() => /1개 고침 · 1개 건너뜀 \(그 칸이 없는 항목\)/.test(document.querySelector('.mk-props-bulk [data-bulk-result]')?.textContent || ''));
    check(!(await saved()).periods[0].tags, '태그는 사건에만 더해지고(겹친 태그는 하나로) 나라는 건너뜀');
    /* ⑤ 지도자 목록에 표(TSV) 붙여넣기 — 병 왕국 편집 창 */
    await tree('pc').click();
    const form = page.locator('form:has([data-paste-text="leaders"])').first();
    await form.waitFor({ state: 'attached' });
    await form.locator('details[data-adv="cells"]').evaluate(el => { el.open = true; for (const x of el.querySelectorAll('details.cell-paste')) x.open = true; });
    const ta = form.locator('[data-paste-text="leaders"]');
    await ta.fill('대수\t대표 이름\t이름\t시작\t끝\t메모\n2\t둘째 임금\t가온\t160\t200\t\n3\t셋째 임금\t나래\t날짜 아님\t230\t\n4\t넷째 임금\t\t230\t미정\t끝을 모름');
    await form.locator('[data-cell-paste="leaders"]').click();
    const dlg = page.locator('dialog[data-row-paste="leaders"]');
    await dlg.waitFor();
    check(await dlg.locator('tbody tr').count() === 3 && await dlg.locator('tbody tr.is-bad').count() === 1 && /날짜 아님/.test(await dlg.locator('tbody tr.is-bad').textContent()), '미리 보기: 세 줄 가운데 읽지 못한 한 줄은 빨간 표시와 까닭');
    check(JSON.stringify(await dlg.locator('thead select').evaluateAll(s => s.map(x => x.value))) === JSON.stringify(['ordinal', 'name', 'given', 'start', 'end', 'note']), '첫 줄을 머리글로 짐작해 열을 맞춤');
    await page.screenshot({ path: path.join(output, '줄-묶음-붙여넣기-1920-1배.png') });
    await dlg.locator('thead select').nth(5).selectOption('');
    check(/2줄 넣기/.test(await dlg.locator('[data-paste-accept]').textContent()) && await dlg.locator('thead select').nth(5).inputValue() === '' && /날짜 아님/.test(await dlg.locator('.mk-paste-problems').textContent()), '열 바꾸기(메모 → 받지 않음) 뒤 다시 읽고, 까닭은 빨간 목록에');
    await dlg.locator('[data-paste-accept]').click();
    await dlg.waitFor({ state: 'detached' });
    const leaderRows = await form.locator('[data-cells="leaders"] .cell-row').evaluateAll(rs => rs.map(r => [r.querySelector('.c-ordinal').value, r.querySelector('.c-name').value, r.querySelector('.c-given').value, r.querySelector('.c-start').value, r.querySelector('.c-end').value, r.querySelector('.c-note').value]));
    check(JSON.stringify(leaderRows.slice(1)) === JSON.stringify([['2', '둘째 임금', '가온', '160', '200', ''], ['4', '넷째 임금', '', '230', '미정', '']]), '읽은 두 줄이 지도자 줄로 들어감', leaderRows);
    check((await ta.inputValue()).split('\n').length === 2 && /날짜 아님/.test(await ta.inputValue()), '읽지 못한 줄은 머리글과 함께 글 칸에 남음', await ta.inputValue());
    /* 예전 한 줄 글 꼴은 그대로(창 없이 바로 줄로) */
    await ta.fill('다섯째 임금 260~300');
    await form.locator('[data-cell-paste="leaders"]').click();
    check(await page.locator('dialog[data-row-paste]').count() === 0 && await form.locator('[data-cells="leaders"] .cell-row').count() === 4, '예전 한 줄 글 꼴은 미리 보기 없이 예전처럼 줄로');
    await page.keyboard.press('Control+s');
    await page.waitForFunction(() => (JSON.parse(localStorage.getItem('ht.maker.draft')).periods[2].leaders || []).length === 4);
    d = await saved();
    const L = d.periods[2].leaders.map(c => (Array.isArray(c) ? { name: c[0], start: c[1], end: c[2] } : c));
    check(JSON.stringify(L.slice(1)) === JSON.stringify([{ name: '둘째 임금', start: 160, end: 200, given: '가온', ordinal: 2 }, { name: '넷째 임금', start: 230, endUnknown: true, ordinal: 4 }, { name: '다섯째 임금', start: 260, end: 300 }]), '저장하면 작업본의 지도자 넷(붙여넣은 칸 · 미정 끝 · 예전 꼴 그대로)', d.periods[2].leaders);
    /* ⑥ 통째 붙여넣기 — 칸 채우기 답을 메이커에서 Ctrl+V: 없는 나라면 새 시대 편집 창 + 미리 보기 → 넣기 → 저장 */
    const pasteAnswer = text => page.evaluate(t => {
      document.activeElement && document.activeElement.blur && document.activeElement.blur();
      const dt = new DataTransfer();
      dt.setData('text/plain', t);
      document.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
    }, text);
    await page.keyboard.press('Escape');
    await pasteAnswer(WHOLE);
    const whole = page.locator('dialog.mk-whole[open]');
    await whole.waitFor();
    check(await page.locator('#editorTitle').textContent() === '객체 추가' && /14곳 넣기/.test(await whole.locator('[data-whole-accept]').textContent()) && await whole.locator('[data-whole-mode]').isHidden(), '없는 나라의 답 → 새 시대 편집 창 · 미리 보기 14곳 · 있는 줄이 없어 바꾸기/보태기는 숨김');
    check(await whole.locator('.mk-paste-problems').count() === 0, '칸 블록은 문제 목록 없이 읽힘');
    const othersText = (await whole.locator('.mk-whole-others li').allTextContents()).map(t => t.replace(/\s+/g, ' ').trim());
    check(othersText.length === 3 && /^갑 왕국 — 승계 «솔나라» 간접 승계 · 내 DLC에서 더함$/.test(othersText[0]) && /^없는 왕국 — .* · 연표에 없음/.test(othersText[1]) && /^병 왕국 — 소속 «솔나라» 조공·책봉국 · 내 DLC에서 더함$/.test(othersText[2]) && await whole.locator('[data-whole-others]').isChecked(), '이어받은나라 · 속했던나라 층: 나라마다 넣는 길(내 DLC · 연표에 없음)', othersText);
    await page.waitForTimeout(400); // 창이 그려진 뒤에 찍음
    await page.screenshot({ path: path.join(output, '통째-붙여넣기-새-나라-1920-1배.png') });
    await whole.locator('[data-whole-accept]').click();
    await whole.waitFor({ state: 'detached' });
    const formVals = await page.evaluate(() => {
      const it = HT.FORMS.period.read(document.querySelector('#editorForm'));
      return { problems: it.problems, name: it.item.name, track: it.item.track, leaders: it.item.leaders.length, cert: it.item.leaders.map(c => c.certainty || ''), phases: (it.item.phases || []).length, wiki: !!it.item.wiki, ns: it.item.northSouth };
    });
    check(JSON.stringify(formVals) === JSON.stringify({ problems: [], name: '솔나라', track: 'b2-plain', leaders: 4, cert: ['legend', '', 'estimated', ''], phases: 1, wiki: true, ns: 35.8 }), '넣으면 편집 창의 칸이 모두 채워지고 폼 읽기 문제 없음', formVals);
    await page.waitForTimeout(400); // 창이 그려진 뒤에 찍음
    await page.screenshot({ path: path.join(output, '통째-붙여넣기-넣은-뒤-1920-1배.png') });
    await page.keyboard.press('Control+s');
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('ht.maker.draft')).periods.some(p => p.name === '솔나라'));
    d = await saved();
    const sol = d.periods.find(p => p.name === '솔나라');
    check(sol.leaders.length === 4 && sol.capitals.length === 2 && sol.succeeds.length === 2 && sol.historicity === 'semi' && Object.values(d.documents || {}).some(w => /가상 나라다/.test(w)), '저장하면 작업본에 솔나라(지도자 · 도읍 · 승계 · 실재성 · 문서)', { leaders: sol.leaders.length, capitals: sol.capitals.length, documents: Object.keys(d.documents || {}) });
    /* 저장하면 이어받은나라 · 속했던나라 층의 나라에도 — 갑 왕국의 승계 칸 · 병 왕국의 소속 칸에 솔나라 (편집 창은 솔나라 그대로) */
    await page.waitForFunction(() => (JSON.parse(localStorage.getItem('ht.maker.draft')).periods.find(p => p.name === '갑 왕국').succeeds || []).length > 0);
    d = await saved();
    const gap = d.periods.find(p => p.name === '갑 왕국'), byeong = d.periods.find(p => p.name === '병 왕국');
    check(JSON.stringify(gap.succeeds) === JSON.stringify([{ from: '솔나라', type: 'indirect', note: '가상 까닭 (가상 출처)' }]) && JSON.stringify(byeong.partOf.slice(-1)) === JSON.stringify([{ polity: '솔나라', relation: 'tributary', start: 400, end: 450 }]) && await page.locator('#editorTitle').textContent() === '객체 수정' && await page.locator('#editorForm [name="name"]').inputValue() === '솔나라', '저장하면 다른 나라에도: 갑 왕국의 승계 · 병 왕국의 소속에 솔나라 (편집 창은 그대로)', { gap: gap.succeeds, byeong: byeong.partOf });
    /* 같은 답을 다시 붙여넣으면 그 나라의 편집 창 — 있는 줄은 바꾸기(기본)라 줄이 겹치지 않음 */
    await page.keyboard.press('Escape');
    await pasteAnswer(WHOLE);
    await whole.waitFor();
    check(await page.locator('#editorTitle').textContent() === '객체 수정' && await whole.locator('[data-whole-mode]').isVisible(), '이미 있는 나라의 답 → 그 나라의 편집 창 · 바꾸기/보태기가 보임');
    const again = (await whole.locator('.mk-whole-others li').allTextContents()).map(t => t.replace(/\s+/g, ' ').trim());
    check(/이미 있음$/.test(again[0]) && /이미 있음$/.test(again[2]), '이미 넣은 다른 나라는 이미 있음', again);
    await page.waitForTimeout(400); // 창이 그려진 뒤에 찍음
    await page.screenshot({ path: path.join(output, '통째-붙여넣기-있는-나라-1920-1배.png') });
    await whole.locator('[data-whole-accept]').click();
    await whole.waitFor({ state: 'detached' });
    check(await page.locator('#editorForm [data-cells="leaders"] .cell-row').count() === 4, '바꾸기로 넣어도 지도자는 넷');
    /* ⑦ 판 2(#HT칸 2 — 5단계 잔여 과제 1): 새 객체의 답 — 그릇(나라 → 접기 · 시대 → 대범위) · 구성원(그 객체의 그릇 칸에) · 제 안의 실권자 → 넣기 → 저장 */
    await page.keyboard.press('Control+s');
    await page.keyboard.press('Escape');
    await pasteAnswer(['#HT칸 2', '객체,물나라,300,420,가상 들녘,제후국,,,,,2', '그릇,갑 왕국,나라,,,켬', '그릇,들 시대,시대', '시대,들 시대,250,500,가상 들녘,분열기',
      '구성원,병 왕국', '실권,,350,380,세도', '지도자,1,물왕,300,350', '#끝'].join('\n'));
    await whole.waitFor();
    check(await page.locator('#editorTitle').textContent() === '객체 추가' && await whole.locator('.mk-paste-problems').count() === 0, '판 2 답 → 새 객체 편집 창 · 문제 없이 읽힘');
    const v2Others = (await whole.locator('.mk-whole-others li').allTextContents()).map(t => t.replace(/\s+/g, ' ').trim());
    check(v2Others.length === 2 && /^들 시대 — 시대 구분의 대범위\(분열기\)에 «물나라» · 내 DLC에 시대 구분과 대범위를 새로 만듦$/.test(v2Others[0]) && /^병 왕국 — 그릇 «물나라»에 접혀 듦 · 내 DLC에서 더함$/.test(v2Others[1]), '판 2: 저장할 때 넣을 것(시대 그릇 · 구성원)', v2Others);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(output, '통째-붙여넣기-판2-1920-1배.png') });
    await whole.locator('[data-whole-accept]').click();
    await whole.waitFor({ state: 'detached' });
    await page.keyboard.press('Control+s');
    await page.waitForFunction(() => { const x = JSON.parse(localStorage.getItem('ht.maker.draft')); return x.periods.some(p => p.name === '물나라') && (x.scopes || []).some(sc => sc.epoch === '들 시대'); });
    d = await saved();
    const mul = d.periods.find(p => p.name === '물나라'), byeong2 = d.periods.find(p => p.name === '병 왕국');
    const sc = (d.scopes || []).find(x => x.epoch === '들 시대'), ep = (d.epochs || []).find(x => x.name === '들 시대');
    check(JSON.stringify(mul.partOf) === JSON.stringify([{ polity: '갑 왕국', main: true }]) && JSON.stringify(mul.power) === JSON.stringify([{ name: '세도', start: 350, end: 380 }]) && mul.importance === 2
      && sc && sc.label === '분열기' && JSON.stringify(sc.members) === JSON.stringify(['물나라']) && ep && ep.start === 250 && ep.end === 500
      && byeong2.partOf.some(p => (typeof p === 'string' ? p === '물나라' : p.polity === '물나라' && p.nest !== false)),
      '판 2를 저장하면: 그릇(나라)은 접힌 소속 줄 · 으뜸 · 제 안의 실권자 · 중요도 · 시대 그릇은 시대 구분 + 대범위(성격) · 구성원은 그 객체의 소속 줄에',
      { partOf: mul.partOf, power: mul.power, importance: mul.importance, kind: mul.kind, type: mul.type, scope: sc, epoch: ep, byeong: byeong2.partOf });
    await page.screenshot({ path: path.join(output, '통째-붙여넣기-판2-저장-1920-1배.png') });
    await context.close();
  } catch (error) {
    report.오류.push(String(error && error.stack || error));
  } finally {
    await browser.close(); server.close();
  }
}

// 메이커 후속 단계의 실제 자료 계산: 잘못된 입력·이동·참조·왕복 보존을 검사합니다.
import assert from 'node:assert/strict';
export function checkMakerNext(HT) {
  const G = HT.makerGrid, M = HT.makerDrag, F = HT.makerFind;
  const raw = HT.draft.clean({ id: 'next-check', name: '후속 검사', tracks: [{ id: 't', name: '검사 들녘' }], periods: [
    { id: 'a', track: 't', name: '솔나라', start: 100, end: 300, leaders: [['첫 지도자', 100, 200], ['다음 지도자', 200, 300]], phases: [{ scheme: '두 시기', spans: [['앞', 100, 200], ['뒤', 200, 300]] }] },
    { id: 'b', track: 't', name: '강나라', start: 150, end: 350, partOf: '솔나라', succeeds: [['솔나라', 'partial', '기록', 1]] },
    { id: 'c', track: 't', name: '별나라', start: 200, end: 400 },
  ], events: [{ id: 'e', title: '가상 사건', track: 't', start: 200, polity: '솔나라', source: '가상 출처' }], documents: { a: '솔나라의 문서', 'cell:a:leaders:첫 지도자@100': '지도자 문서' } });
  const original = JSON.stringify(raw), source = { list: 'periods' };
  const a = G.plan(raw, source, [{ row: 0, key: 'name', text: '새 솔나라' }, { row: 0, key: 'start', text: '110' }, { row: 0, key: 'end', text: '310' }]);
  assert.equal(a.changed, 1); assert.equal(a.errors.length, 0); assert.equal(a.draft.periods[0].start, 110);
  for (const text of ['날짜 아님', '2023-02-29', '2020-13-01']) {
    const bad = G.plan(raw, source, [{ row: 0, key: 'start', text }]);
    assert.ok(bad.errors.length, text); assert.deepEqual(bad.draft.periods[0], raw.periods[0]);
  }
  const badRange = G.plan(raw, source, [{ row: 0, key: 'start', text: '400' }]); assert.ok(badRange.errors.length);
  const sub = G.plan(raw, { list: 'periods', parent: 'a', sub: 'leaders' }, [{ row: 0, key: 'name', text: '새 지도자' }]);
  assert.equal(sub.draft.periods[0].leaders[0].name, '새 지도자'); assert.equal(sub.draft.periods[0].leaders[0].end, 200);
  assert.equal(sub.draft.documents['cell:a:leaders:새 지도자@100'], '지도자 문서');
  const pasted = G.plan(raw, source, G.pasteWrites('이름\t시작\t끝\n구름나라\t500\t600', source, [], 3, 0));
  assert.equal(pasted.added, 1); assert.equal(pasted.draft.periods[3].name, '구름나라');
  const shift = M.shiftItem(raw.periods[0], 25);
  assert.equal(shift.start, 125); assert.equal(shift.end, 325); assert.equal(shift.leaders[0].start, 125); assert.equal(shift.phases[0].spans[1].end, 325);
  const withDocs = structuredClone(raw); G.moveCellDocuments(withDocs, 'next-check/a', raw.periods[0], shift, {part:'move', amount:25, unit:'year'});
  assert.equal(withDocs.documents['cell:a:leaders:첫 지도자@125'], '지도자 문서');
  assert.equal(M.moveDate(-1, null, 1, 'year').value, 1); assert.equal(M.moveDate(1, null, -1, 'year').value, -1);
  const feb = M.moveDate('2024-01-31', null, 1, 'month'); assert.equal(HT.cal.at(feb.value).m, 2); assert.equal(HT.cal.at(feb.value).d, 29);
  const leap = M.moveDate('2024-02-29', null, 1, 'year'); assert.equal(HT.cal.at(leap.value).d, 28);
  const bce = M.moveDate('기원전 1-12-31', null, 1, 'day'); assert.equal(HT.cal.at(bce.value).y, 1); assert.equal(HT.cal.at(bce.value).m, 1);
  const seam = M.changeItem(raw.periods[0], { part: 'seam', list: 'leaders', index: 0, date: { t: 220, at: null } });
  assert.equal(seam.leaders[0].end, 220); assert.equal(seam.leaders[1].start, 220);
  const cities = M.changeItem({ start: 100, end: 400, capitals: [['뒤 도시', 200, 400], ['앞 도시', 100, 200]] }, { part: 'seam', list: 'capitals', index: 1, nextIndex: 0, date: { t: 250 } });
  assert.equal(cities.capitals[1].end, 250); assert.equal(cities.capitals[0].start, 250); assert.equal(cities.capitals[0].city, '뒤 도시');
  assert.throws(() => M.changeItem(raw.periods[0], { part: 'seam', list: 'leaders', index: 0, date: { t: 350 } }));
  assert.throws(() => M.changeItem(raw.periods[0], { part: 'end', date: { t: 50 } }));
  assert.equal(M.changeItem({ ...raw.periods[0], endUnknown: true }, { part: 'end', date: { t: 350 } }).endUnknown, undefined);
  const base = HT.buildModel([HT.normalizePack(raw).pack], null), own = HT.draft.clean({ id: 'next-patch', name: '덮어쓰기 검사', patches: [{ target: 'next-check/a', set: { note: '앞서 쓴 메모', color: '#123456' } }] });
  const ctx = { state: { model: base } }, api = { isLocked: () => true, rawOf: () => raw.periods[0], baseModel: () => base };
  assert.equal(M.applyItems(own, ['next-check/a'], { part: 'move', amount: 1, unit: 'year' }, ctx, api).skipped, 1);
  const moved = M.applyItems(own, ['next-check/a'], { part: 'move', amount: 1, unit: 'year' }, ctx, { ...api, isLocked: () => false });
  assert.equal(moved.draft.patches[0].set.start, 101); assert.equal(moved.draft.patches[0].set.note, '앞서 쓴 메모'); assert.equal(moved.draft.patches[0].set.color, '#123456');
  const cleared = structuredClone(moved.draft); G.patchItem(cleared, base.byUid.get('next-check/a'), { color: '#123456' }, {}); assert.equal(cleared.patches[0].set.color, undefined);
  const preservedHour = M.moveDate('2024-02-28 12:30', null, 1, 'day'); assert.ok(preservedHour.at.includes('12:30')); assert.equal(HT.cal.at(preservedHour.value).d, 29);
  const options = { query: '솔나라', replacement: '새솔국', scope: 'name', refs: true };
  const replacement = F.replace(raw, options);
  assert.equal(replacement.changed, 1); assert.equal(replacement.draft.periods[1].partOf, '새솔국'); assert.equal(replacement.draft.periods[1].succeeds[0][0], '새솔국'); assert.equal(replacement.draft.events[0].polity, '새솔국');
  assert.equal(replacement.draft.documents.a, '솔나라의 문서');
  assert.equal(F.replace(raw, { ...options, refs: false }).draft.events[0].polity, '솔나라');
  assert.equal(F.find(raw, { query: '[', scope: 'all' }).length, 0);
  const shared = HT.draft.clean({ id: 'shared', name: '같은 바탕', peoples: [{ id: 'p', name: '앞 민족' }], periods: [{ id: 'p1', name: '가상 나라', track: 't', people: '앞 민족', start: 100, end: 200 }] });
  const shadows = [{ id: 'other', peoples: [{ id: 'p', name: '앞 민족' }] }];
  assert.equal(G.plan(shared, { list: 'peoples' }, [{ row: 0, key: 'name', text: '뒤 민족' }], null, shadows).draft.periods[0].people, '앞 민족');
  assert.equal(F.replace(shared, { query: '앞 민족', replacement: '뒤 민족', scope: 'name', refs: true }, null, shadows).draft.periods[0].people, '앞 민족');
  assert.throws(() => F.find(raw, { query: '[', regex: true }));
  assert.equal(F.blanks(raw).leaders.length, 2); assert.equal(F.blanks(raw).source.length, 0);
  const history = new HT.makerHistory.History(raw); history.push(a.draft, '표'); history.push(replacement.draft, '찾아 바꾸기'); history.undo();
  assert.deepEqual(history.undo(), raw); assert.equal(JSON.stringify(raw), original);
  return { table: '입력·거절·붙여넣기·하위 표 통과', dates: '기원전·윤년·월말·칸 경계·중첩 이동 통과', find: '이름 참조·문서 범위·정규식·빈 칸 통과', undo: '원본 유지·되돌리기 통과' };
}

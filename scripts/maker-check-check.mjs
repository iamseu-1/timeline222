/* 메이커 검사 창의 형식 4 검사(js/maker-check.js — 리메이크 5단계 과제 8) 검사.
   node scripts/maker-check-check.mjs [--show]  — --show는 파일마다 창에 오를 줄을 모두 찍습니다(기대값을 다시 적을 때).
   가상 팩 다섯을 일부러 틀리게 한 파일 다섯(prototype/fixtures/f4/broken/<id>.json — 모르는 종류 · 없는 출처 · 고리 빌림 · 상대 없는 실권 · 종류에 안 맞는 칸)을
   메이커가 여는 길 그대로(다리 HT.F4.down → 작업본 HT.draft.clean → 정규화 HT.normalizePack) 작업본으로 만들고, 검사 창에 오를 줄(정규화의 오류 · 경고 + HT.makerCheck.f4Checks의 경고 · 확인할 것 · 알림)의
   수와 글을 기대값과 견줍니다. 다리가 열 때 이미 빼는 것(없는 출처의 빌림 · 고리 빌림 · 모르는 종류)은 작업본에 남지 않으므로, 그 줄은 ① 다리의 알림이 작업본의 f4notes로 창에 오르는지와
   ② 객체 폼에서 같은 실수를 했을 때(작업본을 폼이 쓰는 꼴로 고쳐) 창이 잡는지로 봅니다. 메이커 부품(js/maker.js · 화면)은 부르지 않고 검사 함수만 — 노드에서 js/calendar.js · js/core.js · js/maker-check.js를 읽습니다.
   이름은 모두 가상입니다. 틀리면 assert가 던지고, 맞으면 센 수를 찍습니다 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const show = process.argv.includes('--show');

/** 작업본을 메이커가 여는 길 그대로 — 돌려주는 값 { draft, lines, fc, r } (lines = 창에 오를 줄의 글 — 낱말을 앞에 붙임) */
function open(HT, raw4, others = []) {
  const notes = [];
  const raw = HT.F4.down(raw4, m => notes.push(String(m)));
  if (notes.length) raw.f4notes = notes;
  const draft = HT.draft.clean(raw);
  return check(HT, draft, others);
}
function check(HT, draft, others = []) {
  const r = HT.normalizePack(draft);
  const fc = HT.makerCheck.f4Checks(draft, others);
  const lines = r.errors.map(x => `오류: ${x.msg}`)
    .concat(r.warnings.map(x => `경고: ${x.msg}`), fc.warnings.map(x => `경고: ${x.msg}`), fc.notes.map(x => `${x.confirm ? '확인할 것' : '알림'}: ${x.msg}`));
  return { draft, lines, fc, r };
}
const has = (lines, piece) => lines.some(l => l.includes(piece));
/** 기대값: 줄 수와 꼭 있어야 할 글 조각들 — 꼴은 { msg, kind, index }인지도 봅니다 */
function expect(label, got, count, pieces) {
  if (show) {
    console.log(`\n[${label}] 줄 ${got.lines.length}개\n  ${got.lines.join('\n  ')}`);
    return;
  }
  assert.equal(got.lines.length, count, `${label}: 창의 줄 수가 ${got.lines.length}(기대 ${count})\n  ${got.lines.join('\n  ')}`);
  for (const p of pieces) assert.ok(has(got.lines, p), `${label}: 창에 "${p}"이(가) 없음\n  ${got.lines.join('\n  ')}`);
  for (const x of got.fc.warnings.concat(got.fc.notes)) {
    assert.ok(typeof x.msg === 'string' && x.msg, `${label}: 줄에 글이 없음`);
    assert.ok(x.kind === 'info' || (x.kind === 'periods' && Number.isInteger(x.index) && x.index >= 0), `${label}: 줄의 꼴(kind · index)이 다름 — ${JSON.stringify(x)}`);
  }
}

export function checkMakerCheck(HT) {
  let n = 0;
  const read = id => JSON.parse(readFileSync(join(root, 'prototype/fixtures/f4/broken', `${id}.json`), 'utf8'));
  const period = (draft, id) => draft.periods.find(p => p.id === id);

  /* ① 모르는 종류 · 그리는 자리(다리의 알림 → 작업본의 f4notes → 창의 알림) · 정통성 · 중요도(정규화의 경고 — 겹쳐 내지 않음) */
  let got = open(HT, read('f4-crowns'));
  expect('f4-crowns(모르는 종류)', got, 4, [
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "도가니 자유시"의 종류 "citadel"을(를) 알 수 없어 국가로 읽습니다.',
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "북설 칸국"의 그리는 자리 "floating"을(를) 알 수 없어 종류대로 그립니다.',
    '정통성 "엉뚱"을(를) 알 수 없어 뺐습니다',
    '중요도는 0~3이어야 해서 뺐습니다',
  ]);
  assert.equal(got.fc.warnings.length, 0, 'f4-crowns: 형식 4 검사가 경고를 더 내면 안 됨(정규화와 겹침)');
  /* 저장 파일에는 f4notes가 실리지 않음 */
  const saved = HT.F4.toFile(HT.packToJSON(got.r.pack), got.draft.f4extras);
  assert.ok(!('f4notes' in saved) && !('f4extras' in saved), 'f4-crowns: 작업본의 f4notes · f4extras가 저장 파일에 실림');
  n++;

  /* ② 없는 출처 — 빌림의 객체가 없음(다리가 뺌 → 알림) · 실권의 상대가 없음(확인할 것) · 있는 객체의 없는 직위 줄(다리가 뺌 → 알림) */
  got = open(HT, read('f4-office'));
  expect('f4-office(없는 출처 — 연 그대로)', got, 4, [
    '경고: 객체 #2 "등불 교단": 끝이 비어 있어 한 해짜리 점 띠(시작 = 끝)로 그려집니다', // 5단계 잔여 과제 6 — 가상 팩의 교단은 끝이 비어 있음
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "등불 교단"의 직위 줄 "등좌"이(가) 빌려 올 객체 "o-nobody"을(를) 찾지 못해 뺍니다.',
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "설원 제국"의 직위 줄 "수석 재상"이(가) 빌려 올 직위 줄 "재상"을(를) 객체 "o-khan"에서 찾지 못해 뺍니다.',
    '확인할 것: 객체 #4 "북설 칸국": 실권 2번째 줄의 상대 «o-ghost»을(를) 작업본 · 불러온 팩에서 찾지 못했습니다',
  ]);
  assert.equal(got.fc.notes.filter(x => x.confirm).length, 1);
  assert.ok(!has(got.lines, 'o-emp'), 'f4-office: 있는 상대(o-emp)의 실권은 창에 오르면 안 됨');
  /* 객체 폼에서 같은 실수 — 지도자 자리의 빌려 보기에 없는 객체 · 있는 객체의 없는 직위 줄 · 직위 줄 더의 빌림을 이름으로 */
  let d = got.draft;
  period(d, 'o-faith').leadersFrom = { name: '등좌', from: 'o-nobody/지도자' };
  period(d, 'o-emp').offices = [{ name: '수석 재상', from: 'o-khan/재상' }];
  period(d, 'o-khan').cabinetsFrom = { from: '설원 제국/지도자' }; // 이름으로 적은 출처 — 풀림(알림 없음)
  got = check(HT, d);
  expect('f4-office(없는 출처 — 폼에서)', got, 6, [
    '확인할 것: 객체 #2 "등불 교단": 지도자 줄의 빌림(«등좌»)이(가) 빌려 올 객체 «o-nobody»을(를) 작업본 · 불러온 팩에서 찾지 못했습니다 — 다른 팩의 객체면 그 팩을 불러오고, 아니면 id · 이름을 확인하세요.',
    '확인할 것: 객체 #3 "설원 제국": 직위 줄 «수석 재상»이(가) 빌려 올 직위 줄 «재상»을(를) 객체 «북설 칸국»에서 찾지 못했습니다.',
  ]);
  assert.equal(got.fc.notes.filter(x => x.confirm).length, 3);
  /* 다른 팩의 객체 — 그 팩을 불러왔으면 풀리고(확인할 것 없음), 안 불러왔으면 확인할 것 */
  const other = HT.normalizePack(HT.F4.down(JSON.parse(readFileSync(join(root, 'prototype/fixtures/f4/f4-liege.json'), 'utf8')))).pack;
  period(d, 'o-khan').power[1].over = 'o-grand'; // f4-liege의 객체
  period(d, 'o-khan').cabinetsFrom = { from: 'f4-liege/o-king/지도자' }; // 팩 id/객체 id/직위 이름
  got = check(HT, d, [other]);
  assert.equal(got.fc.notes.filter(x => x.confirm).length, 2, `불러온 팩의 객체는 풀려야 함\n  ${got.lines.join('\n  ')}`);
  got = check(HT, d, []);
  assert.equal(got.fc.notes.filter(x => x.confirm).length, 4, `불러오지 않은 팩의 객체는 확인할 것\n  ${got.lines.join('\n  ')}`);
  n++;

  /* ③ 고리 빌림 — 둘이 서로 · 자기 자신(다리가 열 때 뺌 → 알림) · 폼에서 같은 실수 → 경고 */
  got = open(HT, read('f4-liege'));
  expect('f4-liege(고리 빌림 — 연 그대로)', got, 3, [
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "갈대 공국"의 직위 줄 "지도자"의 빌림이 고리를 이룹니다 — 뺍니다.',
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "백사 공국"의 직위 줄 "지도자"의 빌림이 고리를 이룹니다 — 뺍니다.',
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "수해 대공국"의 직위 줄 "대공의 재상"의 빌림이 고리를 이룹니다 — 뺍니다.',
  ]);
  d = got.draft;
  period(d, 'o-duke').leadersFrom = { from: 'o-baek' };
  period(d, 'o-baek').leadersFrom = { from: 'o-duke' };
  period(d, 'o-grand').offices = [{ name: '대공의 재상', from: 'o-grand/대공의 재상' }];
  period(d, 'o-king').cabinetsFrom = { from: 'o-grand' }; // 고리가 아닌 빌림 — 알림 없음
  got = check(HT, d);
  expect('f4-liege(고리 빌림 — 폼에서)', got, 6, [
    '경고: 객체 #3 "갈대 공국": 지도자 줄의 빌림이(가) 고리를 이룹니다(갈대 공국/지도자 → 백사 공국/지도자 → 갈대 공국/지도자) — 서고는 이 줄을 그리지 못하고, 파일을 다시 열 때 다리가 이 줄을 뺍니다.',
    '경고: 객체 #4 "백사 공국": 지도자 줄의 빌림이(가) 고리를 이룹니다(백사 공국/지도자 → 갈대 공국/지도자 → 백사 공국/지도자)',
    '경고: 객체 #2 "수해 대공국": 직위 줄 «대공의 재상»이(가) 고리를 이룹니다(수해 대공국/대공의 재상 → 수해 대공국/대공의 재상)',
  ]);
  assert.equal(got.fc.warnings.length, 3);
  /* 자리에 칸을 적어 두고 빌려 보기를 켠 채 — 출처의 칸과 다르면 경고(저장 때 빠짐), 복제한 그대로면 조용히 */
  period(d, 'o-king').cabinets = [{ name: '청림 재상', start: 1100, end: 1150 }];
  got = check(HT, d);
  assert.ok(has(got.lines, '경고: 객체 #1 "청림 왕국": 내각 칸 1개가 적혀 있지만 빌려 보기가 켜져 있어 저장 때 그 칸은 빠지고 «수해 대공국»의 «지도자» 칸을 봅니다 — 칸을 지키려면 빌려 보기를 끄세요.'), `적어 둔 칸 경고가 없음\n  ${got.lines.join('\n  ')}`);
  period(d, 'o-king').cabinets = JSON.parse(JSON.stringify(period(d, 'o-grand').leaders));
  got = check(HT, d);
  assert.ok(!has(got.lines, '내각 칸 1개가'), '복제한 그대로의 칸은 알리지 않아야 함');
  n++;

  /* ④ 상대 없는 실권 — over도 이름도 없음(정규화의 경고 · 이름만 있으면 제 안의 실권자로 맞음) · 없는 상대(확인할 것) · 자기 자신(경고) */
  got = open(HT, read('f4-sphere'));
  expect('f4-sphere(상대 없는 실권)', got, 3, [
    '경고: 시대 #4 "설족 칸국": 실권 1번째 줄: 상대(over)도 이름도 없어 뺐습니다',
    '확인할 것: 객체 #5 "설원 제국": 실권 1번째 줄의 상대 «o-nowhere»을(를) 작업본 · 불러온 팩에서 찾지 못했습니다 — 실권은 쥔 쪽에만 적고 빼앗긴 객체를 상대로 가리킵니다.',
    '경고: 객체 #3 "빛나루 자유시": 실권 1번째 줄의 상대가 자기 자신입니다 — 빼앗긴 상대 객체를 가리키세요.',
  ]);
  n++;

  /* ⑤ 종류에 안 맞는 칸 — 띠로 그리는 시대의 지도자 칸 · 실권(그리지 않음) · 사람의 칸 · 시대 그릇의 칸(저장 때 빠짐) · 으뜸 둘 */
  got = open(HT, read('f4-federation'));
  expect('f4-federation(종류에 안 맞는 칸)', got, 6, [
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "쇠여울 변경백령"의 그릇 "o-fed"은(는) 그릇 · 섬김이 여럿이라 지금 화면에서는 접지 않고 소속(제 줄)으로 그립니다',
    '알림: 파일을 열 때(형식 4 → 옛 꼴): 객체 "쇠여울 변경백령"의 그릇 "o-m02"은(는) 그릇 · 섬김이 여럿이라',
    '경고: 객체 #7 "쇠여울 변경백령": 소속 줄에 으뜸이 2개입니다 — 구조 나무 · 서고는 첫 것만 기준으로 삼습니다.',
    '경고: 객체 #15 "적석 연방 시대": 시대 종류에는 지도자 칸 · 실권이(가) 맞지 않습니다 — 저장한 파일에는 남지만 그리지 않습니다(시대는 그릇 · 이름표). 종류를 바꾸거나 칸을 비우세요.',
    '경고: 객체 #14 "협곡 바깥 왕국": 생년 · 몰년은(는) 사람의 칸이라 저장 때 빠집니다 — 사람은 인물 표에 적습니다.',
    '경고: 객체 #4 "돌못 자유시": 시대 그릇의 성격(label)은(는) 도시 객체에 없는 칸이라 저장 때 빠집니다.',
  ]);
  /* 저장(HT.F4.toFile)은 시대의 지도자 칸 · 실권을 정말 빼지 않음('그리지 않음' 글이 맞음) · 사람의 칸 · label은 정말 빠짐 */
  const file = HT.F4.toFile(HT.packToJSON(got.r.pack), got.draft.f4extras);
  const band = file.objects.find(o => o.id === 'e-band');
  assert.ok(band && band.offices && band.offices.length === 1 && band.power && band.power.length === 1, '저장 파일의 띠 시대에 직위 줄 · 실권이 남아야 함(빼면 글을 "저장 때 빠짐"으로 바꿀 것)');
  const out = file.objects.find(o => o.id === 'o-out');
  assert.ok(out && !('birth' in out) && !('death' in out), '저장 파일에서 사람의 칸은 빠져야 함');
  assert.ok(!('label' in file.objects.find(o => o.id === 'o-m03')), '저장 파일에서 도시의 label은 빠져야 함');
  /* 객체 폼에서 종류를 시대로 바꾸면 — 지도자 칸이 있는 나라 → 경고 · 비우면 사라짐 / 옛 종속 종류 + 객체 종류 · 소속 없음 → 확인할 것 */
  d = got.draft;
  period(d, 'o-fed').kind = 'era';
  got = check(HT, d);
  assert.ok(has(got.lines, '경고: 객체 #1 "적석 제후 연방": 시대 종류에는 지도자 칸이(가) 맞지 않습니다'), `종류를 시대로 바꾼 뒤 경고가 없음\n  ${got.lines.join('\n  ')}`);
  delete period(d, 'o-fed').leaders;
  got = check(HT, d);
  assert.ok(!has(got.lines, '객체 #1 "적석 제후 연방": 시대 종류에는'), '칸을 비우면 경고가 사라져야 함');
  Object.assign(period(d, 'o-out'), { kind: 'vassal', type: 'city' });
  got = check(HT, d);
  assert.ok(has(got.lines, '알림: 객체 #14 "협곡 바깥 왕국": 옛 종류 «종속국»와 객체 종류 «도시»을(를) 함께 적고 소속이 없어, 저장하면 상대 \'미상\'의 섬김 줄이 소속 줄로 남습니다'), `종속 종류 + 객체 종류 알림이 없음\n  ${got.lines.join('\n  ')}`);
  n++;

  /* ⑥ 세계사 칸(6단계 걸음 3 · D2 · D8) — 이름 번호가 양의 정수가 아님 · 종교 칸 겹침은 정규화의 경고 하나씩(겹쳐 내지 않음) ·
     직위 줄 더의 칸에 적은 이름 번호 · 묘호는 저장 때 빠짐(경고) · 같은 이름 번호 둘(확인할 것) · 시대 종류의 종교 칸(경고). 이름은 가상 */
  d = HT.draft.clean({
    format: HT.FORMAT, formatVersion: 3, id: 'w3-check', name: '세계사 칸 검사', tracks: [{ id: 't', name: '가상 들' }],
    periods: [
      { id: 'p-high', track: 't', name: '높은 왕국', start: 100, end: 300,
        leaders: [{ name: '헨리', regnal: 6, start: 100, end: 130 }, { name: '에드', regnal: 'x', start: 130, end: 140 }, { name: '헨리', regnal: 6, start: 140, end: 150 }, { name: '마르', start: 150 }],
        faiths: [['가 신앙', 100, 200], ['나 신앙', 150]],
        offices: [{ name: '재상', cells: [{ name: '갑', temple: '큰갑', regnal: 2, start: 100, end: 150 }, { name: '을', start: 150 }] }] },
      { id: 'p-era', track: 't', name: '들 시대', type: 'era', start: 100, end: 300, faiths: [['가 신앙', 100]] },
    ],
  });
  got = check(HT, d);
  expect('세계사 칸(6단계 걸음 3)', got, 5, [
    '경고: 시대 #1 "높은 왕국": 지도자 "에드"의 이름 번호(regnal) "x"은(는) 양의 정수가 아니라 뺐습니다.',
    '경고: 시대 #1 "높은 왕국": 종교 "가 신앙"와(과) "나 신앙"의 기간이 겹칩니다.',
    '경고: 객체 #1 "높은 왕국": 직위 줄 «재상»의 칸에 적은 이름 번호 · 묘호은(는) 직위 줄 더(셋째 줄부터)의 칸이 아직 싣지 않아 저장 때 빠집니다',
    '확인할 것: 객체 #1 "높은 왕국": 지도자 «헨리 6세»이(가) 2칸입니다 — 복위(같은 사람이 다시 오름)면 그대로 두고, 아니면 이름 번호를 확인하세요.',
    '경고: 객체 #2 "들 시대": 시대 종류에는 종교이(가) 맞지 않습니다',
  ]);
  assert.equal(got.lines.filter(l => l.includes('이름 번호(regnal)')).length, 1, '이름 번호의 틀린 값은 한 줄(정규화의 경고 — 검사 창이 겹쳐 내지 않음)');
  assert.equal(got.lines.filter(l => l.includes('기간이 겹칩니다')).length, 1, '종교 칸 겹침은 한 줄(정규화의 경고)');
  /* 직위 줄 더의 칸은 정말 저장 때 빠짐(경고 글이 맞음 — 정규화가 셋째 줄부터의 칸에서 지도자 칸만의 값을 읽지 않음) */
  const saved6 = HT.F4.toFile(HT.packToJSON(got.r.pack), null).objects.find(o => o.id === 'p-high');
  const cell6 = saved6.offices.find(o => o.name === '재상').cells[0];
  assert.ok(!('regnal' in cell6) && !('temple' in cell6), `직위 줄 더의 칸이 이름 번호 · 묘호를 싣게 되면 경고 글을 고칠 것: ${JSON.stringify(cell6)}`);
  /* 고치면 사라짐 */
  delete period(d, 'p-high').offices[0].cells[0].temple;
  delete period(d, 'p-high').offices[0].cells[0].regnal;
  period(d, 'p-high').leaders[2].regnal = 7;
  period(d, 'p-high').leaders[1].regnal = 1;
  period(d, 'p-high').faiths = [['가 신앙', 100, 150], ['나 신앙', 150]];
  delete period(d, 'p-era').faiths;
  got = check(HT, d);
  expect('세계사 칸(고친 뒤)', got, 0, []);
  n++;

  /* 온전한 가상 팩 다섯은 형식 4 검사의 줄을 내지 않음(다리의 알림만 — f4-liege 등은 알림 0) */
  for (const f of JSON.parse(readFileSync(join(root, 'prototype/fixtures/f4/list.json'), 'utf8')).files) {
    const g = open(HT, JSON.parse(readFileSync(join(root, 'prototype/fixtures/f4', f.path), 'utf8')));
    /* f4-office의 교단은 끝이 비어 점 띠 — 5단계 과제 9가 일부러 둔 꼴이라(엔진 add_pack 검사의 항목 수도 이 꼴) 끝이 빈 객체 경고(잔여 과제 6) 하나는 맞는 경고 */
    const known = f.path === 'f4-office.json' ? g.fc.warnings.filter(x => /"등불 교단": 끝이 비어 있어/.test(x.msg)) : [];
    assert.equal(known.length, f.path === 'f4-office.json' ? 1 : 0, `${f.path}: 끝이 빈 교단의 경고`);
    assert.equal(g.fc.warnings.length - known.length + g.fc.notes.filter(x => x.kind !== 'info').length, 0, `${f.path}: 온전한 팩에 형식 4 검사 줄이 남\n  ${g.lines.join('\n  ')}`);
    n++;
  }
  return n;
}

const main = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const noop = () => {};
  const el = () => ({ style: {}, classList: { add: noop, remove: noop, toggle: noop, contains: () => false }, appendChild: noop, remove: noop, setAttribute: noop, addEventListener: noop, querySelector: () => null, querySelectorAll: () => [], getContext: () => ({ measureText: s => ({ width: String(s).length * 7 }), font: '' }) });
  const g = globalThis;
  g.window = g;
  g.document = { documentElement: el(), body: el(), createElement: el, querySelector: () => null, querySelectorAll: () => [], addEventListener: noop, removeEventListener: noop, getAnimations: () => [] };
  const store = new Map();
  g.localStorage = { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
  g.matchMedia = () => ({ matches: false, addEventListener: noop, addListener: noop });
  g.getComputedStyle = () => ({ getPropertyValue: () => '' });
  g.requestAnimationFrame = cb => setTimeout(() => cb(Date.now()), 0);
  g.cancelAnimationFrame = id => clearTimeout(id);
  if (!g.navigator) g.navigator = { userAgent: 'node' };
  const load = rel => vm.runInThisContext(readFileSync(join(root, rel), 'utf8'), { filename: rel });
  ['js/calendar.js', 'js/core.js', 'js/maker-check.js'].forEach(load);
  try {
    const n = checkMakerCheck(g.HT);
    console.log(`메이커 검사 창(형식 4) 검사 통과 — ${n}건`);
  } catch (e) {
    console.error(`메이커 검사 창(형식 4) 검사 실패: ${e.stack || e}`);
    process.exit(1);
  }
}

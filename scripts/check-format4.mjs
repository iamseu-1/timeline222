/* 형식 4 검사 — 리메이크 1단계 1a(docs/설계-리메이크-객체-그릇-서고.md 3절 · docs/계획-리메이크-1a-형식4-뼈대.md)
   node scripts/check-format4.mjs [--extra=<.htpack 경로>] … — 혼자 돌리거나, dev-smoke가 checkFormat4(HT)로 부릅니다.
   ① 종류 ② 소속 ③ 시대 — 이음 규칙을 가상 팩으로 ④ 기본팩 · 견본 · (--extra) 실제 팩의 왕복과 모델 지킴 ⑤ 형식 4 파일의 읽기 길
   ⑩ 형식 4 더하기(5단계 과제 1 — 사람 왕복 · 빌림 · 주기 · as · 고리) ⑪ 형식 4로 저장(5단계 과제 2 — extrasOf · toFile · raw4 · ⑯ 열고 저장해도 늘지 않음) ⑫ 객체 표(5단계 과제 3 — type · status · importance · main) ⑬ 직위 줄 · 실권 · 빌림(5단계 과제 4 — offices · leadersFrom · power) ⑭ 사람 객체(5단계 과제 5 — 사람 고르기 · 칭호 묶음) ⑮ 문화권 단위 줄(5단계 과제 6 — epochs[].sphere · yearCycles) ⑯ 서고 미리보기의 형식 4 모델(5단계 과제 9 — HT.f4Preview) ⑰ 6단계 걸음 1(등록 함수의 형식 4 · 승계 방식 how · 육십갑자 예약 값 · 최상위 간지 줄 고르기) ⑱ 6단계 걸음 2(이름 번호 regnal · 지도자 표기 낱말 leaderLabels · 종교 faiths — 세계사 결정 D2 · D3 · D8) ⑲ 6단계 걸음 3(메이커가 여는 길 — 폼 · 작업본 · 형식 4 저장 두 바퀴에 네 칸이 남음) ⑧ 이음 검사용 옛 파일 묶음(prototype/fixtures/legacy — 형식 1 · 2 · 3 × 장치별) ⑨ 형식 4 가상 팩 다섯(prototype/fixtures/f4 — 새 칸 · 다리로 내린 옛 꼴을 expected/와 견줌 · --write-expected로 다시 뽑음) — 리메이크 5단계 과제 0. 문화권 단위 줄(5단계 과제 6 — 시대 구분의 sphere 왕복 · 트랙 우선 경고 · 주기 표 yearCycles 저장 왕복 · 옛 열쇠 yearCycle 호환) ⑧ 이음 검사용 옛 파일 묶음(prototype/fixtures/legacy — 형식 1 · 2 · 3 × 장치별) ⑨ 형식 4 가상 팩 다섯(prototype/fixtures/f4 — 새 칸 · 다리로 내린 옛 꼴을 expected/와 견줌 · --write-expected로 다시 뽑음) — 리메이크 5단계 과제 0.
   이름은 모두 가상입니다. 틀리면 assert가 던지고, 맞으면 센 수를 돌려줍니다 */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import vm from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const sortKeys = v => (Array.isArray(v) ? v.map(sortKeys) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sortKeys(v[k])])) : v);
const canon = v => JSON.stringify(sortKeys(v));

/** 검사 도구 — 정규화 · 견주기 · 가상 팩 · 왕복 · 모델의 모양 */
function kit(HT) {
  const t = { count: 0 };
  t.N = raw => {
    const r = HT.normalizePack(raw);
    assert.ok(r.pack, `정규화 실패: ${r.errors.map(e => e.msg).join(' / ')}`);
    return HT.packToJSON(r.pack);
  };
  t.same = (a, b, msg) => assert.equal(canon(a), canon(b), msg);
  /** 가상 팩(가 줄 ta · 나 줄 tb)을 정규화한 옛 JSON */
  t.pack = (periods, more = {}) => t.N(Object.assign({ format: HT.FORMAT, id: 'f4-unit', name: '형식 4 시험', tracks: [{ id: 'ta', name: '가 줄' }, { id: 'tb', name: '나 줄' }], periods }, more));
  t.obj = (j4, name) => j4.objects.find(o => o.name === name);
  /** 옛 → 4 → 옛이 project와 같은지 보고 형식 4를 돌려줍니다 */
  t.round = (J, label) => {
    const { json, problems } = HT.F4.up(J);
    assert.deepEqual(problems, [], `${label}: 올림 문제`);
    t.same(t.N(HT.F4.down(json)), t.N(HT.F4.project(J)), `${label}: 옛 → 4 → 옛이 project와 다름`);
    return json;
  };
  /** 모델의 접힘 · 소속 · 대범위 — project가 이것을 바꾸면 안 됩니다(관계는 종류에서 빌린 것까지 셈 · 종류 이름은 뺌) */
  t.shape = packs => {
    const m = HT.buildModel(packs.map(j => HT.normalizePack(j).pack), null);
    return m.periods
      .filter(p => p.itemKind === 'period')
      .map(p => [p.uid, p.track, !!p.singleHost, (p.hosts || []).map(h => [h.host.uid, h.relation || HT.relationOfKind(p.polityKind), h.start ?? null, h.end ?? null]), (p.scopes || []).map(s => s.uid).sort()]);
  };
  return t;
}
const P = (name, extra = {}) => Object.assign({ name, track: 'ta', start: 100, end: 300 }, extra);

/* ① 종류: 옛 kind 스무 값 → type + 관계(설계 3-8 표) */
function unitKinds(HT, t) {
  const want = {
    federation: ['federation', ''], warlord: ['warlord', 'nominal'], exile: ['government', ''], org: ['warlord', ''], movement: ['organization', ''], era: ['era', ''],
    fief: ['principality', 'fief'], client: ['group', 'client'], prefecture: ['dependency', 'prefecture'],
    tributary: [undefined, 'tributary'], dominion: [undefined, 'dominion'], vassal: [undefined, 'vassal'], protectorate: [undefined, 'protectorate'], satellite: [undefined, 'satellite'],
    puppet: [undefined, 'puppet'], mandate: [undefined, 'mandate'], colony: [undefined, 'colony'], occupied: [undefined, 'occupied'], frontier: [undefined, 'frontier'],
  };
  assert.equal(Object.keys(want).length + 1, HT.POLITY_KINDS.length, '옛 종류가 늘었는데 이 표에 없음 — 설계 3-8 표와 함께 고칠 것');
  for (const [kind, [type, rel]] of Object.entries(want)) {
    const J = t.pack([P('윗나라'), P('아랫나라', { kind, partOf: [{ polity: '윗나라', start: 150, end: 200 }] })]);
    const o = t.obj(t.round(J, `종류 ${kind}`), '아랫나라');
    assert.equal(o.type, type, `종류 ${kind} → type`);
    assert.equal(o.kind, undefined, `종류 ${kind}: kind가 남음`);
    assert.equal(o.partOf.length, 1);
    assert.equal(o.partOf[0].of, '윗나라');
    assert.equal(o.partOf[0].relation || '', rel, `종류 ${kind}: 비운 관계를 종류에서 채움`);
    assert.equal(o.within, undefined);
    assert.equal(o.display, kind === 'era' ? 'band' : undefined, `종류 ${kind}: display`);
    /* org → 군벌은 관계를 빌리는 길이 바뀜(명목상) — 설계 3-8에 적은 바뀜이라 모양 견주기에서 뺍니다 */
    if (kind !== 'org') t.same(t.shape([J]), t.shape([HT.F4.project(J)]), `종류 ${kind}: project가 모델을 바꿈`);
    t.count++;
  }
  /* 상대 없는 종속 kind → { of: '미상', relation } · 내리면 그 kind 그대로 */
  const J = t.pack([P('외딴나라', { kind: 'tributary' })]);
  const o = t.obj(t.round(J, '상대 없는 조공'), '외딴나라');
  assert.equal(o.type, undefined);
  t.same(o.partOf, [{ of: HT.F4.UNKNOWN, relation: 'tributary' }], '상대 없는 종속');
  const back = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-x', name: '내림', objects: [o] }).periods[0];
  assert.equal(back.kind, 'tributary');
  assert.equal(back.partOf, undefined);
  /* 국가(kind 없음)는 type을 적지 않음 */
  assert.equal(t.obj(t.round(t.pack([P('그냥나라')]), '국가'), '그냥나라').type, undefined);
  t.count += 2;
}

/* ② 소속: 옛 partOf · nest → within(그릇에 듦) · partOf(섬김) — 옛 접기 뜻(singleHost에서 상위의 트랙 조건만 뺀 것)을 따름 */
function unitPartOf(HT, t) {
  const cases = [
    ['관계 없음 · 하나 · 기간 없음', ['윗나라'], undefined, [{ of: '윗나라' }], undefined],
    ['구성국 · 하나 · 기간 없음', [{ polity: '윗나라', relation: 'member' }], undefined, [{ of: '윗나라' }], [{ of: '윗나라', relation: 'member' }]],
    ['조공 · nest true', [{ polity: '윗나라', relation: 'tributary', nest: true }], undefined, [{ of: '윗나라' }], [{ of: '윗나라', relation: 'tributary' }]],
    ['조공 · nest 비움', [{ polity: '윗나라', relation: 'tributary' }], undefined, undefined, [{ of: '윗나라', relation: 'tributary' }]],
    ['관계 없음 · nest false', [{ polity: '윗나라', nest: false }], undefined, undefined, [{ of: '윗나라' }]],
    ['기간 있는 둘', [{ polity: '윗나라', start: 120, end: 180, relation: 'vassal' }, { polity: '옆나라', start: 180, end: 250 }], undefined, undefined, [{ of: '윗나라', relation: 'vassal', start: 120, end: 180 }, { of: '옆나라', start: 180, end: 250 }]],
    ['nest true인데 둘(접히지 않음)', [{ polity: '윗나라', nest: true }, { polity: '옆나라', nest: true }], undefined, undefined, [{ of: '윗나라' }, { of: '옆나라' }]],
    ['종류 조공 · 관계 비움 · 하나', ['윗나라'], 'tributary', [{ of: '윗나라' }], [{ of: '윗나라', relation: 'tributary' }]],
    ['메모가 있는 접힘', [{ polity: '윗나라', note: '이름만 섬김' }], undefined, [{ of: '윗나라', note: '이름만 섬김' }], undefined],
  ];
  for (const [label, partOf, kind, within, want] of cases) {
    const J = t.pack([P('윗나라'), P('옆나라'), P('아랫나라', Object.assign({ partOf }, kind ? { kind } : null))]);
    const o = t.obj(t.round(J, `소속 ${label}`), '아랫나라');
    t.same(o.within, within, `소속 ${label}: within`);
    t.same(o.partOf, want, `소속 ${label}: partOf`);
    t.same(t.shape([J]), t.shape([HT.F4.project(J)]), `소속 ${label}: project가 모델의 접힘을 바꿈`);
    t.count++;
  }
}

/* ③ 시대: 시대 구분(epochs) · 대범위(scopes) → type 'era' 객체 · 구성원의 within(설계 3-3 · 3-8) */
function unitEras(HT, t) {
  const J = t.pack([P('첫나라'), P('둘나라'), P('셋나라', { track: 'tb' }), P('본나라')], {
    epochs: [{ id: 'ep-a', name: '가는 시대', start: 100, end: 200 }, { id: 'ep-b', name: '나 줄 시대', start: 150, end: 250, track: 'tb', alternatives: [{ note: '다른 셈' }] }],
    scopes: [{ id: 's-a', track: 'ta', name: '두 나라 할거', label: '할거', members: ['둘나라', 'ta:첫나라', 'tb:셋나라', '먼나라', '첫나라'], epoch: '가는 시대', host: '본나라', default: true }],
  });
  const j4 = t.round(J, '시대');
  t.same(j4.objects.map(o => o.id), [...J.periods.map(p => p.id), 'ep-a', 'ep-b', 's-a'], '객체 차례: 시대(정권) → 시대 구분 → 대범위');
  for (const n of ['첫나라', '둘나라', '셋나라']) t.same(t.obj(j4, n).within, [{ of: 's-a' }], `${n}: 대범위에 듦`);
  assert.equal(t.obj(j4, '본나라').within, undefined, '본국은 들지 않음');
  const s = j4.objects.find(o => o.id === 's-a');
  t.same(s, { type: 'era', id: 's-a', track: 'ta', name: '두 나라 할거', label: '할거', host: '본나라', default: true, within: [{ of: '가는 시대' }], members: ['먼나라'] }, '대범위 → 시대 그릇');
  t.same(j4.objects.find(o => o.id === 'ep-b'), Object.assign({ type: 'era' }, J.epochs[1]), '시대 구분 → 시대');
  assert.equal(j4.epochs, undefined);
  assert.equal(j4.scopes, undefined);
  t.same(t.shape([J]), t.shape([HT.F4.project(J)]), '시대: project가 대범위 구성을 바꿈');
  /* 검토할 곳 4: 같은 id를 두 목록이 쓰면 알림 */
  const dup = JSON.parse(JSON.stringify(J));
  dup.epochs[0].id = dup.periods[0].id;
  assert.equal(HT.F4.up(dup).problems.length, 1, '겹친 id 알림');
  /* 검토할 곳 2 · 3: 손으로 쓴 형식 4 — 한국어 종류 · 관계, 글 하나 within, 트랙을 비운 구성원(그릇에서 물려받음), 트랙 없는 시대(공통 — 끌지 않음) */
  const warns = [];
  const L = HT.F4.down(
    {
      format: HT.FORMAT, formatVersion: 4, id: 'f4-hand', name: '손 형식 4', tracks: [{ id: 'ta', name: '가 줄' }],
      objects: [
        { id: 'e-cont', type: '시대', name: '모인 시대', track: 'ta', start: 100, end: 300 },
        { id: 'e-free', type: '시대', name: '온 누리 시대', start: 100, end: 300 },
        { id: 'o-1', type: '국가', name: '첫 고을', start: 120, end: 200, within: ['e-cont', 'e-free'] },
        { id: 'o-2', name: '둘 고을', track: 'ta', start: 150, end: 250, partOf: [{ of: 'o-1', relation: '조공', start: 160, end: 190 }] },
      ],
    },
    m => warns.push(m)
  );
  t.same(L.periods.map(p => [p.id, p.track]), [['o-1', 'ta'], ['o-2', 'ta']], '구성원은 그릇의 트랙을 물려받음');
  t.same(L.scopes.map(x => [x.id, x.members]), [['e-cont', ['o-1']]], '트랙 있는 시대 = 대범위');
  t.same(L.epochs.map(e => e.id), ['e-free'], '트랙 없는 시대 = 시대 구분');
  assert.ok(warns.some(w => /공통 시대/.test(w)), '공통 시대 경고');
  assert.equal(L.periods[1].partOf[0].relation, 'tributary');
  const r = HT.normalizePack(L);
  assert.ok(r.pack && !r.errors.length, `손 형식 4가 정규화됨: ${r.errors.map(e => e.msg).join(' / ')}`);
  t.count += 4;
}

/* ⑥ 직위 줄 · 기관 · 단체(1b — 설계 3-5 · 3-8): 지도자 · 내각 → offices, 기관 → 속령 · 단체(나라 띠 안), 단체 → 단체 · 동맹 · 실권 정권(나라 띠 위 표지) */
function unitMore(HT, t) {
  const J = t.pack([P('윗나라', { leaders: [['첫 임금', 100, 150], ['둘 임금', 150, 300]], cabinets: [{ name: '첫 내각', start: 120, end: 140 }] }), P('옆나라', { cabinets: [{ name: '옆 내각', start: 200, end: 220 }] })], {
    organs: [
      { track: 'ta', name: '바다 관청', host: '윗나라', start: 150, end: 250 },
      { track: 'ta', name: '항구 거리', scale: 'zone', host: [{ polity: '윗나라', end: 200 }, { polity: '옆나라', start: 200 }], start: 120, end: 280 },
    ],
    groups: [
      { track: 'ta', name: '푸른 무리', type: 'faction', start: 120, end: 300, within: '윗나라', power: [['집권', 130, 160]], people: ['윗나라:첫 임금@100'] },
      { track: 'ta', name: '붉은 당', type: 'party', start: 200, end: 300, within: [{ polity: '윗나라', end: 250 }, { polity: '옆나라', start: 250 }], from: [{ group: '푸른 무리', how: 'rename', note: '이름을 바꿈' }] },
      { track: 'ta', name: '두 나라 연합', type: 'coalition', start: 150, end: 250, members: [{ polity: '윗나라', role: '맹주' }, '옆나라'] },
      { track: 'ta', name: '그림자 정권', type: 'regime', start: 160, end: 190, within: '윗나라' },
      { track: 'ta', name: '이름 없는 모임', start: 130, end: 140 },
    ],
  });
  const j4 = t.round(J, '직위 · 기관 · 단체');
  const top = t.obj(j4, '윗나라');
  t.same(top.offices.map(f => [f.name, f.cells.length]), [['지도자', 2], ['내각', 1]], '지도자 · 내각 → 직위 줄');
  assert.equal(top.leaders, undefined);
  assert.equal(top.cabinets, undefined);
  t.same(t.obj(j4, '옆나라').offices.map(f => f.name), ['내각'], '내각만 있는 나라');
  const o1 = t.obj(j4, '바다 관청');
  const o2 = t.obj(j4, '항구 거리');
  t.same([o1.type, o1.display, o1.within], ['organization', 'inside', [{ of: '윗나라' }]], '기관 → 단체 · 나라 띠 안');
  t.same([o2.type, o2.display, o2.within.map(w => w.of)], ['dependency', 'inside', ['윗나라', '옆나라']], '구역 → 속령');
  const [g1, g2, g3, g4, g5] = ['푸른 무리', '붉은 당', '두 나라 연합', '그림자 정권', '이름 없는 모임'].map(n => t.obj(j4, n));
  t.same([g1.type, g1.subtype, g1.display, g1.within], ['organization', 'faction', 'mark', [{ of: '윗나라' }]], '붕당 → 단체 · 표지');
  assert.ok(Array.isArray(g1.persons) && g1.people === undefined, '단체의 사람 목록은 persons');
  t.same(g2.succeeds, [{ from: '푸른 무리', type: 'direct', how: 'rename', note: '이름을 바꿈' }], '앞선 단체 → succeeds의 how');
  t.same([g3.type, g3.subtype], ['league', 'coalition'], '연합 → 동맹');
  assert.ok(Array.isArray(g3.members) && g3.members.length === 2, '연합의 구성 나라는 그릇의 members에 그대로');
  t.same([g4.type, g4.subtype], ['regime', 'regime'], '정권 → 실권 정권');
  t.same([g5.type, g5.subtype], ['organization', undefined], '종류 없는 단체');
  assert.equal(j4.organs, undefined);
  assert.equal(j4.groups, undefined);
  /* 손으로 쓴 형식 4: 직위 줄 셋(자리는 지도자 · 내각 둘) · 모르는 그리는 자리 */
  const warns = [];
  const L = HT.F4.down(
    {
      format: HT.FORMAT, formatVersion: 4, id: 'f4-off', name: '직위 셋', tracks: [{ id: 'ta', name: '가 줄' }],
      objects: [
        { name: '세 직위 나라', track: 'ta', start: 1, end: 100, offices: [{ name: '집정관', cells: [{ name: '갑', start: 1, end: 2 }] }, { name: '지도자', cells: [{ name: '을', start: 1, end: 50 }] }, { name: '내각', cells: [{ name: '병', start: 3, end: 4 }] }] },
        { name: '이상한 자리', track: 'ta', start: 1, end: 9, display: '하늘' },
      ],
    },
    m => warns.push(m)
  );
  t.same([L.periods[0].leaders.map(c => c.name), L.periods[0].cabinets.map(c => c.name)], [['을'], ['병']], '이름이 지도자 · 내각인 줄을 먼저');
  t.same(L.periods[0].offices, [{ name: '집정관', cells: [{ name: '갑', start: 1, end: 2 }] }], '셋째 줄은 직위 줄 더(offices)로 — 5단계 과제 4');
  assert.ok(warns.some(w => /하늘/.test(w)), '모르는 그리는 자리 알림');
  assert.equal(L.periods.length, 2, '모르는 그리는 자리는 종류대로(띠)');
  t.count += 4;
}

/* ⑦ 가지 검토(Fable · 2026-10-15)에서 나온 것: 시대를 이름으로 가리킨 within도 대범위 구성원 · 지금 화면이 접지 못하는 within(기간 있음 · 그릇 여럿)은 알리고 뜻 없는 nest를 남기지 않음 */
function unitReview(HT, t) {
  const warns = [];
  const L = HT.F4.down(
    {
      format: HT.FORMAT, formatVersion: 4, id: 'f4-rv', name: '검토', tracks: [{ id: 'ta', name: '가 줄' }],
      objects: [
        { id: 'e-1', type: 'era', name: '모인 시대', track: 'ta', start: 100, end: 300 },
        { id: 'h-1', name: '큰 나라', track: 'ta', start: 100, end: 300 },
        { id: 'h-2', name: '작은 나라', track: 'ta', start: 100, end: 300 },
        { id: 'o-1', name: '첫 고을', track: 'ta', start: 120, end: 200, within: ['모인 시대'] },
        { id: 'o-2', name: '둘 고을', track: 'ta', start: 120, end: 200, within: [{ of: 'h-1', start: 150, end: 200 }] },
        { id: 'o-3', name: '셋 고을', track: 'ta', start: 120, end: 200, within: ['h-1', 'h-2'] },
      ],
    },
    m => warns.push(m)
  );
  t.same((L.scopes || []).map(s => [s.id, s.members]), [['e-1', ['o-1']]], '시대를 이름으로 가리킨 within도 대범위 구성원');
  t.same(L.periods.find(p => p.id === 'o-2').partOf, [{ polity: 'h-1', start: 150, end: 200 }], '기간 있는 within은 소속으로(뜻 없는 nest 없이)');
  assert.ok(warns.some(w => /둘 고을/.test(w) && /접지 않/.test(w)), '기간 있는 within 알림');
  assert.ok(warns.some(w => /셋 고을/.test(w) && /접지 않/.test(w)), '그릇이 여럿인 within 알림');
  const r = HT.normalizePack(L);
  assert.ok(r.pack && !r.errors.length && !r.warnings.some(w => /접기\(nest\)/.test(w.msg)), '뜻 없는 nest가 남지 않음');
  t.count += 3;
}

/* ④ 실제 팩: 기본팩 · 견본 · (--extra) — 옛 → 4 → 옛이 project와 같고, project가 모델의 접힘 · 소속 · 대범위를 바꾸지 않음.
   내장 팩이 형식 4로 등록되어 있으면(formatVersion 4) 견주는 옛 꼴 J는 정규화가 내려 읽은 것이고, 그 등록 꼴 자체도 봄:
   내림(HT.F4.down)의 알림은 옮겨 앉기 · 기간 있는 within('접지 않고 소속(제 줄)으로')뿐 · 내림 → 정규화 → 올림의 객체 id 모둠이
   등록 꼴과 같음(id를 잃거나 새로 짓지 않음). 형식 3으로 등록된 내장 팩은 이 두 단위를 건너뜀 */
const MOVE_NOTE = /지금 화면에서는 접지 않고 소속\(제 줄\)으로 그립니다/;
async function corpus(HT, t, extra) {
  const base = HT.getBuiltinPacks().map(raw => ({ label: `기본팩 ${raw.id}`, J: t.N(raw), builtin: true }));
  for (const raw of HT.getBuiltinPacks()) {
    if (Number(raw.formatVersion) !== HT.F4.VERSION) continue;
    const notes = [];
    HT.F4.down(JSON.parse(JSON.stringify(raw)), m => notes.push(m));
    assert.deepEqual(notes.filter(m => !MOVE_NOTE.test(m)), [], `기본팩 ${raw.id}: 형식 4 등록 꼴을 내릴 때 옮겨 앉기 · 기간 있는 within 밖의 알림`);
    const ids = os => os.map(o => String(o.id)).sort();
    t.same(ids(HT.F4.up(t.N(raw)).json.objects), ids(raw.objects), `기본팩 ${raw.id}: 형식 4 등록 꼴 → 내림 → 정규화 → 올림의 객체 id가 등록 꼴과 다름`);
    t.count += 2;
  }
  const files = readdirSync(join(root, 'samples')).filter(f => f.endsWith('.json')).sort().map(f => ({ label: `견본 ${f}`, J: t.N(JSON.parse(readFileSync(join(root, 'samples', f), 'utf8'))) }));
  const more = [];
  for (const path of extra) {
    if (!HT.packFile) await import(pathToFileURL(join(root, 'js/packfile.js')).href);
    const got = await HT.packFile.parse(new Uint8Array(readFileSync(path)));
    more.push({ label: `더한 팩 ${path.split(/[\\/]/).pop()}`, J: t.N(got.raw) });
  }
  const builtins = base.map(b => b.J);
  const rows = [];
  for (const { label, J, builtin } of [...base, ...files, ...more]) {
    const j4 = t.round(J, label);
    const ctx = builtin ? [] : builtins;
    t.same(t.shape([...ctx, J]), t.shape([...ctx, HT.F4.project(J)]), `${label}: project가 모델의 접힘 · 소속 · 대범위를 바꿈`);
    rows.push({ label, objects: j4.objects.length });
    t.count++;
  }
  return rows;
}

/* ⑤ 읽기 길: 형식 4 파일은 normalizePack · 전용 팩 읽기에서 옛 꼴로 내려 열리고, 저장은 옛 형식(4가 아님) — 검토할 곳 1 · 5 */
async function loading(HT, t) {
  const J = t.pack([P('윗나라'), P('아랫나라', { kind: 'tributary', partOf: [{ polity: '윗나라', start: 150, end: 200 }] })], { epochs: [{ name: '가는 시대', start: 100, end: 200 }] });
  const j4 = HT.F4.up(J).json;
  const r = HT.normalizePack(j4);
  assert.ok(r.pack && !r.errors.length, '형식 4를 normalizePack이 읽음');
  assert.ok(!r.warnings.some(w => /더 새로운 형식/.test(w.msg)), '형식 4에 "더 새로운 형식" 경고');
  t.same(HT.packToJSON(r.pack), t.N(HT.F4.project(J)), 'normalizePack(형식 4) = 옛 → 4 → 옛');
  assert.ok(HT.packToJSON(r.pack).formatVersion <= 3, '저장은 옛 형식');
  /* 잘못 적은 형식 4도 던지지 않음 — 빈 파일 · 객체 아닌 값 · 모르는 종류 */
  assert.ok(HT.normalizePack({ format: HT.FORMAT, formatVersion: 4, id: 'f4-empty', name: '빈 형식 4' }).pack, '빈 형식 4');
  const junk = HT.normalizePack({ format: HT.FORMAT, formatVersion: 4, id: 'f4-junk', name: '어지러운 형식 4', tracks: [{ id: 'ta', name: '가 줄' }], objects: [null, 3, 'x', [], { name: '하늘섬 나라', type: '하늘섬', track: 'ta', start: 1, end: 2 }] });
  assert.ok(junk.pack && junk.pack.periods.length === 1, '어지러운 형식 4');
  assert.ok(junk.warnings.some(w => /하늘섬/.test(w.msg)), '모르는 종류 경고');
  /* 전용 팩(.htpack): 형식 4 파일은 읽을 때 옛 꼴로 받음 — 연표 설치본 · 메이커 작업본이 옛 꼴로 남게 */
  if (!HT.packFile) await import(pathToFileURL(join(root, 'js/packfile.js')).href);
  const got = await HT.packFile.parse(await HT.packFile.build(j4));
  assert.equal(got.raw.objects, undefined, '전용 팩 읽기가 형식 4를 내리지 않음');
  assert.ok(Array.isArray(got.raw.periods) && got.raw.formatVersion <= 3, '전용 팩 읽기 = 옛 꼴');
  assert.ok(got.notes.some(n => /형식 4/.test(n)), '형식 4를 바꿔 읽었다는 알림');
  /* 가지 검토: 전용 팩 읽기도 내림의 알림을 notes로 돌려주고(연표 설치 기록), 메이커 파일 열기가 그것을 알림 */
  const three = { format: HT.FORMAT, formatVersion: 4, id: 'f4-notes', name: '알림', tracks: [{ id: 'ta', name: '가 줄' }], objects: [{ name: '세 직위 나라', track: 'ta', start: 1, end: 100, display: '하늘', offices: [{ name: '집정관', cells: [{ name: '갑', start: 1, end: 2 }] }, { name: '지도자', cells: [{ name: '을', start: 1, end: 50 }] }, { name: '내각', cells: [{ name: '병', start: 3, end: 4 }] }] }] };
  const got3 = await HT.packFile.parse(await HT.packFile.build(three));
  assert.ok(got3.notes.some(n => /하늘/.test(n)), '전용 팩 읽기의 notes에 내림 알림(모르는 그리는 자리 — 셋째 직위 줄은 과제 4부터 알림 없이 offices로)');
  const maker = readFileSync(join(root, 'js/maker.js'), 'utf8');
  assert.ok(/\(\{ raw, notes = \[\](, raw4 = null)? \} = await HT\.packFile\.read\(file\)\)/.test(maker) && /notes\.join\(/.test(maker), '메이커 파일 열기가 전용 팩 읽기의 notes를 알림');
  t.count += 5;
}

/* ⑧ 이음 검사용 옛 파일 묶음(prototype/fixtures/legacy — 리메이크 5단계 과제 0 · 설계 7절): 파일이 적은 형식 판 그대로인지(그 판의 열쇠만 씀) · 옛 → 4 → 옛 = project · project가 모델을 바꾸지 않음 */
function legacyBundle(HT, t) {
  const dir = join(root, 'prototype/fixtures/legacy');
  const list = JSON.parse(readFileSync(join(dir, 'legacy.json'), 'utf8')).files;
  const rows = [];
  for (const f of list) {
    const raw = JSON.parse(readFileSync(join(dir, f.path), 'utf8'));
    const r = HT.normalizePack(raw);
    assert.ok(r.pack && !r.errors.length, `${f.path}: 정규화 오류 ${r.errors.map(e => e.msg).join(' / ')}`);
    const J = HT.packToJSON(r.pack);
    assert.equal(J.formatVersion, f.formatVersion, `${f.path}: 형식 판이 적은 것(${f.formatVersion})과 다름(${J.formatVersion}) — 묶음의 파일은 그 판의 열쇠만 써야 함`);
    const j4 = t.round(J, f.path);
    /* 설계 3-8 '옛 모습이 바뀌는 곳'에 적힌 바뀜(legacy.json의 knownChanges — 객체 id와 까닭)은 모양 비교에서 그 객체만 뺍니다 */
    const known = new Set((f.knownChanges || []).map(k => `${J.id}/${k.id}`));
    const drop = rows => rows.filter(r => !known.has(r[0]));
    t.same(drop(t.shape([J])), drop(t.shape([HT.F4.project(J)])), `${f.path}: project가 모델의 접힘 · 소속 · 대범위를 바꿈(설계 3-8에 적힌 바뀜이면 legacy.json의 knownChanges에)`);
    rows.push({ label: f.path, objects: j4.objects.length, formatVersion: f.formatVersion });
    t.count++;
  }
  return rows;
}

/* ⑨ 형식 4 가상 팩 다섯(prototype/fixtures/f4 — 세계사 장면 다섯 · '형식 4 더하기' 절의 새 칸): 정규화 오류 0 · 다리(down)로 내린 옛 꼴과 내림 알림이 expected/<id>.legacy.json과 같음.
   과제 1이 새 칸을 읽게 되면 --write-expected로 다시 뽑고 달라진 곳을 계획 문서 '알게 된 것'에 적습니다 */
function f4Bundle(HT, t, writeExpected) {
  const dir = join(root, 'prototype/fixtures/f4'), exp = join(dir, 'expected');
  const list = JSON.parse(readFileSync(join(dir, 'list.json'), 'utf8')).files;
  if (writeExpected) mkdirSync(exp, { recursive: true });
  const rows = [];
  for (const f of list) {
    const raw = JSON.parse(readFileSync(join(dir, f.path), 'utf8'));
    assert.equal(raw.formatVersion, HT.F4.VERSION, `${f.path}: formatVersion 4가 아님`);
    const notes = [];
    const L = HT.F4.down(raw, m => notes.push(String(m)));
    const r = HT.normalizePack(raw);
    assert.ok(r.pack, `${f.path}: 형식 4를 정규화하지 못함`);
    /* 새 칸을 아직 읽지 않는 동안은 오류(사람 객체의 트랙 없음 등)도 기대값에 적어 두고, 과제 1이 읽게 되면 --write-expected로 다시 뽑아 사라진 오류를 봅니다 */
    const got = { legacy: sortKeys(L), notes: notes.slice().sort(), errors: r.errors.map(e => e.msg).sort(), warnings: r.warnings.map(w => w.msg).sort() };
    const file = join(exp, `${raw.id}.legacy.json`);
    if (writeExpected) writeFileSync(file, JSON.stringify(got, null, 1) + '\n');
    assert.ok(existsSync(file), `${f.path}: 기대값 파일이 없음 — node scripts/check-format4.mjs --write-expected 로 뽑을 것`);
    const want = JSON.parse(readFileSync(file, 'utf8'));
    assert.equal(canon(got), canon(want), `${f.path}: 다리로 내린 옛 꼴(또는 내림 알림)이 expected/${raw.id}.legacy.json과 다름 — 뜻한 바뀜이면 --write-expected로 다시 뽑고 적을 것`);
    rows.push({ label: f.path, periods: (L.periods || []).length, notes: notes.length });
    t.count++;
  }
  return rows;
}

/* ⑩ 5단계 과제 1 — 형식 4 더하기(설계 3-11): 인물 ↔ 사람 객체 왕복 · 직위 줄 빌림(id · id/직위 · 없음 · 고리 · from + cells) · 문화권별 주기 → 간지 하나 · partOf.as · within 고리 · 사람 객체의 직위 줄 · 최상위 figures */
function unitNew(HT, t) {
  const fig = { id: 'fg-a', track: 'ta', name: '갑', role: '장군', birth: 140, death: 202, importance: 3, service: [{ polity: '윗나라', office: '대장군', start: 165, end: 200 }] };
  const J = t.pack([P('윗나라', { leaders: [['첫 임금', 100, 150], ['둘 임금', 150, 300]] }), P('옆나라')], { figures: [fig, { id: 'fg-b', track: 'tb', name: '무', role: '학자', start: 170, end: 215 }] });
  const j4 = t.round(J, '사람');
  const ps = j4.objects.filter(o => o.type === 'person');
  t.same(ps.map(o => o.id), ['fg-a', 'fg-b'], '인물 → 사람 객체(단체 뒤 · 차례대로)');
  t.same(ps[0], Object.assign({ type: 'person' }, fig), '사람 객체의 칸은 인물 그대로(생몰 birth · death · 활동 start · end)');
  assert.equal(j4.figures, undefined, '형식 4에 최상위 figures 없음');
  assert.equal(HT.F4.down(j4).figures.length, 2, '내리면 인물로');
  t.count++;
  /* 내림 — 사람 객체의 직위 줄 · 섬김은 뺌 · 최상위 figures는 읽지 않음 · 종류 이름(한국어)도 받음 */
  const warns = [];
  const L = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-ps', name: '사람 검사', tracks: [{ id: 'ta', name: '가 줄' }], figures: [{ name: '옛 자리' }],
    objects: [{ id: 'p-1', type: '사람', track: 'ta', name: '을', birth: 100, death: 160, offices: [{ name: '지도자', cells: [] }], partOf: [{ of: 'p-x' }] }, { id: 'o-1', name: '한 나라', track: 'ta', start: 1, end: 200 }] }, m => warns.push(m));
  t.same(L.figures, [{ id: 'p-1', track: 'ta', name: '을', birth: 100, death: 160 }], '사람 객체 → 인물(직위 줄 · 섬김은 뺌)');
  assert.ok(warns.some(w => /사람 "을"의 직위 줄/.test(w)) && warns.some(w => /사람 "을"의 섬김/.test(w)), '사람의 직위 줄 · 섬김 알림');
  assert.ok(warns.some(w => /"figures"는 읽지 않습니다/.test(w)), '최상위 figures 알림');
  assert.equal(L.periods.length, 1);
  t.count++;
  /* 빌림 */
  const SEATS = [{ name: '첫 자리', start: 10, end: 20 }, { name: '둘 자리', start: 20, end: 40 }];
  const mk = (objects, w = []) => HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-from', name: '빌림', tracks: [{ id: 'ta', name: '가 줄' }], objects }, m => w.push(m));
  const seat = { id: 'o-seat', name: '성좌령', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', cells: SEATS }, { name: '내각', cells: [{ name: '재상', start: 5, end: 9 }] }] };
  let w = [];
  let R = mk([seat, { id: 'o-f1', type: 'faith', name: '교단 하나', track: 'ta', start: 1, end: 100, offices: [{ name: '등좌', from: 'o-seat' }] },
    { id: 'o-f2', type: 'faith', name: '교단 둘', track: 'ta', start: 1, end: 100, offices: [{ name: '등좌', from: '성좌령/내각' }] },
    { id: 'o-f3', type: 'faith', name: '교단 셋', track: 'ta', start: 1, end: 100, offices: [{ name: '등좌', from: 'o-seat/지도자', cells: [{ name: '무시됨', start: 1, end: 2 }] }] }], w);
  t.same(R.periods[1].leaders, SEATS, '"객체 id"만 적으면 지도자 줄을 빌림');
  t.same(R.periods[2].leaders, [{ name: '재상', start: 5, end: 9 }], '"이름/직위 이름"으로 다른 줄을 빌림(이름으로도 찾음)');
  t.same(R.periods[3].leaders, SEATS, 'from과 cells가 함께면 from만');
  assert.ok(w.some(x => /from과 cells가 함께/.test(x)), 'from + cells 알림');
  assert.equal(R.periods[1].offices, undefined);
  t.count++;
  w = [];
  R = mk([seat, { id: 'o-g1', type: 'faith', name: '없는 데서', track: 'ta', start: 1, end: 100, offices: [{ name: '등좌', from: 'o-없음' }] },
    { id: 'o-g2', type: 'faith', name: '없는 줄', track: 'ta', start: 1, end: 100, offices: [{ name: '등좌', from: 'o-seat/원로원' }] },
    { id: 'o-c1', name: '고리 하나', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', from: 'o-c2' }] },
    { id: 'o-c2', name: '고리 둘', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', from: 'o-c1' }] },
    { id: 'o-ch', name: '사슬', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', from: 'o-f1x' }] },
    { id: 'o-f1x', type: 'faith', name: '사슬 가운데', track: 'ta', start: 1, end: 100, offices: [{ name: '등좌', from: 'o-seat' }] }], w);
  for (const [i, n] of [[1, '없는 데서'], [2, '없는 줄'], [3, '고리 하나'], [4, '고리 둘']]) assert.equal(R.periods[i].leaders, undefined, n + ': 빌리지 못하면 그 줄을 뺌');
  assert.ok(w.some(x => /"o-없음"을\(를\) 찾지 못해/.test(x)) && w.some(x => /"원로원"을\(를\) 객체 "o-seat"에서 찾지 못해/.test(x)) && w.filter(x => /고리를 이룹니다 — 뺍니다/.test(x)).length === 2, '빌림의 알림 셋');
  t.same(R.periods[5].leaders, SEATS, '빌림의 사슬(사슬 → 사슬 가운데 → 성좌령)');
  t.count++;
  /* 문화권별 주기 → 간지 하나(전체 줄만 — 6단계 결정 16: 문화권 줄은 최상위로 고르지 않음) · 최상위 yearCycle이 있으면 그대로 */
  w = [];
  const cyc = [{ sphere: 'a', names: ['한', '둘'], start: 1, label: '두해' }, { sphere: 'b', era: '빙원', from: 300, step: 10 }];
  R = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-cyc', name: '주기', tracks: [{ id: 'ta', name: '가 줄' }], yearCycles: cyc, objects: [] }, m => w.push(m));
  assert.equal(R.yearCycle, undefined, '전체 줄이 없으면 문화권 줄을 최상위 간지 줄로 고르지 않음(6단계 결정 16)');
  t.same(R.yearCycles, cyc, 'yearCycles는 그대로 실림');
  assert.ok(!w.some(x => /주기 줄 \d+개 가운데/.test(x)), '문화권 줄만 있으면 주기 알림 없음');
  R = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-cyc2', name: '주기 둘', tracks: [{ id: 'ta', name: '가 줄' }], yearCycle: false, yearCycles: cyc, objects: [] });
  assert.equal(R.yearCycle, false, '최상위 yearCycle이 있으면 그대로');
  R = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-cyc3', name: '주기 셋', tracks: [{ id: 'ta', name: '가 줄' }], yearCycles: [{ names: ['갑', '을'], start: 1 }, ...cyc], objects: [] });
  t.same(R.yearCycle, { names: ['갑', '을'], start: 1 }, 'sphere 없는 전체 줄이 먼저');
  t.count++;
  /* partOf.as는 뺌 · within 고리 알림 · 시대 객체의 sphere는 시대 구분에 그대로 */
  w = [];
  R = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-as', name: 'as · 고리', tracks: [{ id: 'ta', name: '가 줄' }], objects: [
    { id: 'o-lord', name: '대공국', track: 'ta', start: 1, end: 100 },
    { id: 'o-king', name: '왕국', track: 'ta', start: 1, end: 100, partOf: [{ of: 'o-lord', relation: 'fief', as: '갈대 공', start: 10, end: 20 }] },
    { id: 'o-r1', name: '고리 하나', start: 1, end: 100, within: ['o-r2'] },
    { id: 'o-r2', name: '고리 둘', start: 1, end: 100, within: ['o-r1'] },
    { id: 'e-s', type: 'era', name: '문화권 시대', sphere: 'a', start: 1, end: 50 },
  ] }, m => w.push(m));
  t.same(R.periods[1].partOf, [{ polity: 'o-lord', relation: 'fief', start: 10, end: 20 }], 'as를 뺀 섬김');
  assert.ok(w.some(x => /as\("갈대 공"\)는 형식 4에 없는 칸/.test(x)), 'as 알림');
  assert.equal(w.filter(x => /고리를 이룹니다 — 트랙을/.test(x)).length, 2, 'within 고리는 객체마다 한 번');
  t.same(R.epochs, [{ id: 'e-s', name: '문화권 시대', sphere: 'a', start: 1, end: 50 }], '시대 객체의 sphere는 시대 구분에 그대로');
  t.count++;
}

/* ⑪ 5단계 과제 2 — 형식 4로 저장: 열 때 따로 둔 칸(extrasOf)을 메이커의 저장 길(정규화 → packToJSON → up)에 되돌리면(toFile) 가상 팩의 새 칸이 돌아옴 · 전용 팩 읽기의 raw4 · 옛 파일도 형식 4로 */
async function unitSave(HT, t) {
  const dir = join(root, 'prototype/fixtures/f4');
  const load = id => JSON.parse(readFileSync(join(dir, `${id}.json`), 'utf8'));
  const resave = raw4 => {
    const ex = HT.F4.extrasOf(raw4);
    const r = HT.normalizePack(HT.F4.down(raw4));
    assert.ok(r.pack && !r.errors.length, '저장 길의 정규화');
    const J = HT.packToJSON(r.pack);
    return { j4: HT.F4.toFile(J, ex), ex, J };
  };
  const office = resave(load('f4-office'));
  const faith = office.j4.objects.find(o => o.id === 'o-faith');
  t.same(faith.offices, [{ name: '등좌', from: 'o-seat/지도자' }], '빌린 직위 줄은 복제된 칸 대신 from으로 돌아옴');
  assert.equal(office.j4.objects.find(o => o.id === 'o-seat').offices[0].cells.length, 7, '출처의 칸은 그대로');
  assert.equal(office.j4.formatVersion, 4, '저장은 형식 4');
  assert.ok(HT.F4.lossOf(office.ex, office.J).some(l => /직위 줄 빌림 1개/.test(l)), '옛 형식 저장의 손실 목록(작업본에서 셈)');
  /* 제 지도자 줄 + 빌린 둘째 줄: 빌린 줄은 내각 자리로 내려갔다가 제 자리로 돌아오고, 제 지도자 줄은 그대로 */
  const two = resave({ format: HT.FORMAT, formatVersion: 4, id: 'f4-two', name: '둘', tracks: [{ id: 'ta', name: '가 줄' }], objects: [
    { id: 'o-src', name: '출처', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', cells: [{ name: '갑', start: 1, end: 50 }] }] },
    { id: 'o-mix', name: '섞임', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', cells: [{ name: '을', start: 1, end: 20 }] }, { name: '등좌', from: 'o-src' }] },
  ] });
  const mixed = two.j4.objects.find(o => o.id === 'o-mix').offices;
  t.same([mixed[0].name, mixed[0].cells.map(c => c.name), mixed[1]], ['지도자', ['을'], { name: '등좌', from: 'o-src' }], '제 줄은 두고 빌린 줄만 되돌림(정규화가 더한 ordinal은 빼고 봄)');
  const sphere = resave(load('f4-sphere'));
  t.same(sphere.j4.yearCycles, load('f4-sphere').yearCycles, '문화권별 주기 줄이 돌아옴');
  assert.equal(sphere.j4.objects.find(o => o.id === 'ep-l1').sphere, 'ember-basin', '시대 구분의 문화권이 돌아옴');
  const fed = resave(load('f4-federation'));
  assert.equal(fed.j4.objects.find(o => o.id === 'o-m06').importance, 3, '중요도가 돌아옴');
  const crowns = resave(load('f4-crowns'));
  const ps = crowns.j4.objects.find(o => o.type === 'person');
  assert.ok(ps && ps.id === 'ps-harim' && ps.importance === 3, '사람 객체가 돌아옴');
  /* 전용 팩 읽기가 원본(raw4)을 함께 돌려줌 — 메이커가 extras를 만들 재료 */
  if (!HT.packFile) await import(pathToFileURL(join(root, 'js/packfile.js')).href);
  const got = await HT.packFile.parse(await HT.packFile.build(load('f4-office')));
  assert.ok(got.raw4 && Array.isArray(got.raw4.objects) && got.raw.objects === undefined, '전용 팩 읽기: 내린 raw와 원본 raw4');
  assert.ok(got.notes.some(n => /다시 형식 4로/.test(n)), '읽기 알림이 저장 꼴을 말함');
  /* 옛 파일(형식 3)은 extras 없이 올라감 — 저장은 늘 형식 4 · 옛 꼴 열쇠는 없음 */
  const L = JSON.parse(readFileSync(join(root, 'prototype/fixtures/legacy/f3-groups.json'), 'utf8'));
  const j = HT.F4.toFile(HT.packToJSON(HT.normalizePack(L).pack), null);
  assert.equal(j.formatVersion, 4);
  assert.ok(j.periods === undefined && j.groups === undefined && Array.isArray(j.objects), '옛 열쇠 없이 objects만');
  /* 메이커 코드가 저장 길을 씀 */
  const maker = readFileSync(join(root, 'js/maker.js'), 'utf8');
  assert.ok(/HT\.F4\.toFile\(HT\.packToJSON\(pack\), draft\.f4extras\)/.test(maker) && /async function exportLegacy\(\)/.test(maker) && /raw4 = null \} = await HT\.packFile\.read\(file\)/.test(maker), '메이커의 저장 · 옛 형식 저장 · 열기');
  t.count += 6;
}

/* ⑫ 객체 표 · 그릇 폼(5단계 과제 3 — 정규화가 지키는 형식 4의 칸: 객체 종류 type · 정통성 status · 중요도 importance · 소속의 으뜸 main) */
function unitObjects(HT, t) {
  /* 되살릴 수 없는 종류(도시)는 옛 → 4 → 옛을 돌아도 남고, 되살릴 수 있는 종류(제후국 = 봉국)는 적히지 않음 */
  const J = t.pack([P('윗나라'), P('나루시', { type: 'city', status: '대립', importance: 3, partOf: [{ polity: '윗나라', main: true }] }), P('봉국', { type: 'principality' }), P('옛 조직', { kind: 'org', type: 'league' })]);
  const raw = J.periods.find(p => p.name === '나루시');
  t.same([raw.type, raw.status, raw.importance, raw.partOf], ['city', 'rival', 3, [{ polity: '윗나라', main: true }]], '정규화가 객체 종류 · 정통성(한국어 → id) · 중요도 · 으뜸을 지킴');
  assert.equal(J.periods.find(p => p.name === '봉국').type, undefined, '되살릴 수 있는 종류(제후국)는 옛 종류(봉국)만 남김');
  assert.equal(J.periods.find(p => p.name === '봉국').kind, 'fief', '옛 종류를 비운 제후국은 옛 종류 봉국으로 풀림');
  const j4 = t.round(J, '객체 종류');
  const city = t.obj(j4, '나루시');
  t.same([city.type, city.status, city.importance, city.within, city.partOf], ['city', 'rival', 3, [{ of: '윗나라', main: true }], undefined], '올리면 적어 둔 종류가 앞서고 으뜸은 within에');
  t.same([t.obj(j4, '봉국').type, t.obj(j4, '옛 조직').type], ['principality', 'league'], '옛 종류 봉국으로 풀린 제후국은 올리면 다시 제후국 · 조직체 + 동맹은 동맹');
  const back = t.N(HT.F4.down(j4));
  t.same([back.periods.find(p => p.name === '옛 조직').kind, back.periods.find(p => p.name === '옛 조직').type], ['org', 'league'], '내리면 동맹은 옛 종류 조직체 + 적어 둔 종류 동맹');
  /* 모르는 종류 · 정통성 · 중요도는 알리고 뺌 · 사람은 인물 목록 */
  const r = HT.normalizePack({ format: HT.FORMAT, id: 'f4-unit', name: '형식 4 시험', tracks: [{ id: 'ta', name: '가 줄' }], periods: [P('가', { type: '괴물', status: 'x', importance: 9 }), P('나', { type: 'person' })] });
  assert.ok(r.pack && r.pack.periods.every(p => p.type === undefined && p.status === undefined && p.importance === undefined), '모르는 값은 뺌');
  assert.ok(['객체 종류 "괴물"', '정통성 "x"', '중요도는 0~3', '사람은 인물 목록'].every(s => r.warnings.some(w => w.msg.includes(s))), '알림 넷');
  /* 폼의 종류 고르기 값 ↔ { kind, type } */
  t.same([HT.objectKindValue({ kind: 'fief' }), HT.objectKindValue({ type: 'city' }), HT.objectKindValue({ kind: 'vassal' }), HT.objectKindValue({})], ['type:principality', 'type:city', 'vassal', 'type:state'], '종류 고르기 값');
  t.same([HT.readObjectKind('type:principality'), HT.readObjectKind('type:city'), HT.readObjectKind('vassal'), HT.readObjectKind('type:state'), HT.readObjectKind('type:league')], [{ kind: 'fief', type: undefined }, { kind: undefined, type: 'city' }, { kind: 'vassal', type: undefined }, { kind: undefined, type: undefined }, { kind: 'org', type: 'league' }], '종류 고르기 → 옛 종류 · 객체 종류');
  const html = HT.objectKindOptionsHTML();
  assert.ok(!/type:person/.test(html) && /value="vassal"/.test(html) && !/value="fief"/.test(html) && /value="type:principality"/.test(html), '고르기 목록: 사람 없음 · 종속국은 옛 종류 · 봉국은 제후국으로');
  /* 열 때 둔 칸(extrasOf)에 이제 지키는 칸은 들지 않음 */
  const ex = HT.F4.extrasOf({ format: HT.FORMAT, formatVersion: 4, id: 'f4-x', name: '엑스', tracks: [{ id: 'ta', name: '가 줄' }], objects: [{ id: 'o-1', type: 'city', status: 'rival', importance: 2, name: '시', track: 'ta', start: 1, end: 9, subtype: 'x' }] });
  t.same(ex.objects['o-1'], { subtype: 'x' }, '종류 · 정통성 · 중요도는 더 잃지 않음(세부 종류만)');
  t.count += 9;
}

/* ⑬ 직위 줄 · 실권 · 빌림(5단계 과제 4 — 정규화가 지키는 offices · leadersFrom · cabinetsFrom · power · 다리의 왕복).
   옛 → 4 → 옛 = project는 빌린 자리에 복제한 칸이 함께 있을 때만 성립합니다(내림이 칸을 복제하므로 — 메이커 작업본은 늘 그 꼴) */
function unitOffices(HT, t) {
  const cells = n => [{ name: n, start: 100, end: 150 }];
  const J = t.pack([
    P('윗나라', { leaders: cells('첫 임금') }),
    P('세 직위', { leaders: cells('을'), cabinets: cells('병'), offices: [{ name: '집정관', cells: cells('갑') }, { name: '등좌', from: '윗나라/지도자' }], power: [{ name: '섭정', start: 120, end: 140, over: '윗나라' }] }),
    P('빌린 나라', { leaders: cells('첫 임금'), leadersFrom: '윗나라' }),
  ]);
  const three = J.periods.find(p => p.name === '세 직위');
  t.same([three.offices.map(f => f.name), three.offices[1].from, three.power], [['집정관', '등좌'], '윗나라/지도자', [{ name: '섭정', over: '윗나라', start: 120, end: 140 }]], '정규화가 직위 줄 더 · 실권을 지킴');
  t.same(J.periods.find(p => p.name === '빌린 나라').leadersFrom, { from: '윗나라' }, '지도자 자리의 빌림(글 하나 → { from })');
  const j4 = t.round(J, '직위 줄');
  const o3 = t.obj(j4, '세 직위');
  t.same(o3.offices.map(f => [f.name, f.from || f.cells.length]), [['지도자', 1], ['내각', 1], ['집정관', 1], ['등좌', '윗나라/지도자']], '올리면 지도자 · 내각 · 더한 줄 차례');
  t.same(o3.power, three.power, '실권은 그대로');
  t.same(t.obj(j4, '빌린 나라').offices, [{ name: '지도자', from: '윗나라' }], '빌린 자리는 복제한 칸 대신 from으로 올라감');
  /* 내림: 빌린 자리는 칸을 복제하고 빌림을 leadersFrom · cabinetsFrom에 두며, 셋째 줄부터는 offices로(알림 없음) */
  const warns = [];
  const L = HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-bw', name: '빌림', tracks: [{ id: 'ta', name: '가 줄' }], objects: [
    { id: 'o-src', name: '출처', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', cells: cells('첫 임금') }] },
    { id: 'o-bw', name: '빌린 나라', track: 'ta', start: 1, end: 100, offices: [{ name: '지도자', from: 'o-src' }, { name: '등좌', from: 'o-src/지도자' }, { name: '집정관', cells: cells('갑') }, { name: '빈 자리', from: 'o-src' }] },
  ] }, m => warns.push(m));
  const back = L.periods.find(p => p.name === '빌린 나라');
  t.same([back.leaders.map(c => c.name), back.leadersFrom, back.cabinets.map(c => c.name), back.cabinetsFrom], [['첫 임금'], { from: 'o-src' }, ['첫 임금'], { name: '등좌', from: 'o-src/지도자' }], '내리면 복제한 칸 + 빌림');
  t.same(back.offices, [{ name: '집정관', cells: cells('갑') }, { name: '빈 자리', from: 'o-src' }], '셋째 줄부터는 offices로(빌린 줄은 복제한 칸을 뺌)');
  assert.ok(!warns.some(w => /자리가 없어/.test(w)), '자리 없음 알림은 더 없음');
  t.same(HT.F4.up(t.N(L)).json.objects.find(o => o.name === '빌린 나라').offices, [{ name: '지도자', from: 'o-src' }, { name: '등좌', from: 'o-src/지도자' }, { name: '집정관', cells: cells('갑') }, { name: '빈 자리', from: 'o-src' }], '내린 것을 정규화해 올리면 직위 줄이 그대로');
  /* 모르는 꼴은 알리고 뺌 · 빌림과 칸이 함께면 빌림만 · 실권의 상대 없음 · 내각 자리의 빌림 객체 */
  const r = HT.normalizePack({ format: HT.FORMAT, id: 'f4-unit', name: '형식 4 시험', tracks: [{ id: 'ta', name: '가 줄' }], periods: [P('가', { offices: [{ cells: cells('x') }, { name: '둘', from: 'a', cells: cells('y') }], leadersFrom: { name: '빈' }, cabinetsFrom: { name: '등좌', from: 'b' }, power: [{ name: '막부', start: 1 }, { start: 2 }] })] });
  const g = r.pack.periods[0];
  t.same([g.offices, g.leadersFrom, g.cabinetsFrom, g.power], [[{ name: '둘', from: 'a' }], undefined, { name: '등좌', from: 'b' }, [{ name: '막부', start: 1 }]], '빈 이름 줄 · 출처 없는 빌림은 뺌 · 상대 없이 이름만인 실권은 제 안의 실권자로 남고(프롬프트 판 2 · 2026-10-24) 둘 다 없으면 뺌 · 내각 빌림 객체는 지킴');
  assert.ok(['이름이 없습니다', '빌림만 씁니다', '출처가 없어', '상대(over)도 이름도 없어'].every(s => r.warnings.some(w => w.msg.includes(s))), '알림 넷');
  /* 옛 형식 저장의 손실 목록은 작업본(옛 꼴 JSON)에서 셈 */
  const loss = HT.F4.lossOf({ top: {}, objects: {}, offices: {} }, J);
  assert.ok(loss.some(l => /직위 줄 빌림 2개/.test(l)) && loss.some(l => /셋째부터 2개/.test(l)) && loss.some(l => /실권 1개/.test(l)), '손실 목록: 빌림 둘 · 더한 줄 둘 · 실권 하나');
  t.count += 11;
}

/* ⑭ 사람 객체(5단계 과제 5 — 사람 고르기 선택지의 꼬리말 · 칭호 묶음 · 낱말 「사람」) */
function unitPersons(HT, t) {
  assert.equal(HT.FORMS.figure.word, '사람', '폼의 부르는 말');
  assert.equal(HT.personOptionLabel({ name: '갑', birth: 140, death: 202, house: '김씨' }), '갑 · 140년–202년 · 김씨', '선택지 꼬리말');
  assert.equal(HT.personOptionLabel({ name: '을' }), '을', '생몰 · 가문 없으면 이름만');
  const html = HT.lineageListsHTML({ figures: [{ name: '갑', birth: 140, death: 202, house: '김씨' }] });
  assert.ok(/id="mkWhoList"/.test(html) && /label="갑 · 140년–202년 · 김씨"/.test(html) && /value="미상"/.test(html), '사람 목록에 꼬리말');
  const J = t.pack([P('윗나라', { leaders: [{ name: '첫 임금', start: 100, end: 150, person: 'fg-a' }, { name: '둘 임금', start: 150, end: 300 }] }), P('옆나라', { track: 'tb', cabinets: [{ name: '갑 내각', start: 200, end: 220, person: 'fg-a' }] })], { figures: [{ id: 'fg-a', track: 'ta', name: '갑', birth: 80, death: 230 }] });
  const m = HT.buildModel([HT.normalizePack(J).pack], null);
  const fig = m.figures.find(f => f.id === 'fg-a');
  const node = HT.personOf(m, fig);
  assert.ok(node, '인물의 사람 자리');
  t.same(HT.personTitles(m, node).map(x => [x.polity, x.office, x.years]), [['윗나라', '지도자', '100년–150년'], ['옆나라', '내각', '200년–220년']], '칭호 묶음: 객체 · 직위 · 기간 차례');
  t.count += 6;
}

/* ⑯ 서고 미리보기의 형식 4 모델(5단계 과제 9 — HT.f4Preview: 사람 띠 · 빌림 · 실권 · 문화권 줄) */
function unitPreview(HT, t) {
  const dir = join(root, 'prototype/fixtures/f4');
  const load = id => JSON.parse(readFileSync(join(dir, `${id}.json`), 'utf8'));
  const legacyOf = raw4 => HT.packToJSON(HT.normalizePack(HT.F4.down(raw4)).pack);
  const modelOf = J => HT.buildModel([HT.normalizePack(J).pack], null);
  /* 사람 띠: f4-crowns의 한 사람이 여러 나라의 지도자 — 왕관 둘 이상 */
  const Jc = legacyOf(load('f4-crowns'));
  const fc = HT.f4Preview(modelOf(Jc), Jc);
  assert.ok(fc.persons.length >= 1 && fc.persons.every(ps => ps.crowns.length >= 2 && ps.end > ps.start && ps.crowns.every(c => /^f4-crowns\//.test(c.uid) && Number.isInteger(c.i))), '왕관 둘 이상인 사람만 · 때 · 왕관(uid · 칸 번호)');
  const many = fc.persons.reduce((m, ps) => Math.max(m, new Set(ps.crowns.map(c => c.uid)).size), 0);
  assert.ok(many >= 3, `한 사람이 셋 이상의 나라에 — ${many}`);
  /* 빌림 · 실권: f4-office(등좌 빌림 · 실권 over) */
  const Jo = legacyOf(load('f4-office'));
  const fo = HT.f4Preview(modelOf(Jo), Jo);
  const faith = fo.borrows['f4-office/o-faith'];
  t.same(faith && faith.leader, { from: `${Jo.periods.find(p => p.id === 'o-seat').name}/지도자`, name: '등좌' }, '빌린 자리는 출처 이름/직위 · 줄 이름');
  const holders = Object.values(fo.powers).flat();
  assert.ok(holders.length >= 1 && holders.every(w => w.holder.uid.startsWith('f4-office/') && w.holder.name && (w.start == null || Number.isFinite(w.start))), '실권은 빼앗긴 객체 uid 아래에 쥔 쪽 이름 · 색 · 기간');
  assert.ok(Object.keys(fo.powers).every(k => k.startsWith('f4-office/')), '빼앗긴 쪽 uid');
  /* 문화권 줄: f4-sphere(시대 구분의 sphere · yearCycles) */
  const Js = legacyOf(load('f4-sphere'));
  const fs4 = HT.f4Preview(modelOf(Js), Js);
  const ember = fs4.sphereRows['ember-basin'], frost = fs4.sphereRows['frost-ridge'];
  assert.ok(ember && ember.epochs.length === 2 && ember.cycle && ember.cycle.names && ember.cycle.names.length === 9 && ember.cycle.label === '불씨해', '등불 분지권: 시대 줄 둘 · 이름 돌림 주기');
  assert.ok(frost && frost.epochs.length === 2 && frost.cycle && frost.cycle.era === '빙원' && frost.cycle.step === 10 && frost.cycle.from === 300, '설령 빙원권: 시대 줄 둘 · 연호 눈금 주기');
  assert.ok(!fs4.sphereRows[''] && !fs4.sphereRows.undefined, '문화권 없는 시대 구분은 줄에 들지 않음');
  /* 모델 · 작업본이 없으면 빈 묶음 */
  t.same(HT.f4Preview(null, null), { persons: [], borrows: {}, powers: {}, sphereRows: {} }, '없으면 빈 묶음');
  t.count += 9;
}

/* ⑰ 리메이크 6단계 걸음 1 — 기본팩이 형식 4를 낼 등록 길(HT.packRegistry — definePack · extendPack · describePeriods: 형식 4 선언 · 시대 객체 eras · 사람 persons ·
   덧칸 type · within · partOf · power · offices · status · importance · id 찾기) · 나라 승계 방식(how — HT.SUCC_HOWS: 왕복 · 한국어 · 모르는 방식 경고 · 손실 목록) ·
   육십갑자 예약 값(yearCycles의 names "육십갑자" · 표지 builtin) · 다리가 최상위 간지 줄로 고르는 것은 문화권 없는 줄만(결정 16). 이름은 가상 */
function unitRegistry(HT, t) {
  /* 1. 형식 3 선언은 지금 그대로 · 형식 4 선언은 objects · events만 준비 */
  const warns = [];
  const R = HT.packRegistry(new Map(), { warn: m => warns.push(m) });
  R.definePack({ id: 'f3-reg', name: '형식 3 등록', tracks: [{ id: 'ta', name: '가 줄' }] });
  const r3 = R.get('f3-reg');
  assert.ok(r3.formatVersion === HT.FORMAT_VERSION && Array.isArray(r3.periods) && Array.isArray(r3.epochs) && !('objects' in r3), '형식 3 선언은 periods · epochs를 준비(지금 그대로)');
  R.extendPack('f3-reg', { track: 'ta', periods: [[1, 9, '옛 나라', '']] });
  assert.equal(r3.periods[0].id, `ta-p${HT.hash(1 + '옛 나라')}`, '형식 3의 id 길 그대로');
  assert.throws(() => R.extendPack('f3-reg', { track: 'ta', eras: [[1, 9, '시대', '']] }), /형식 4 선언/, '형식 3 팩에는 시대 객체를 적지 않음');
  R.describePeriods('f3-reg', 'ta', { '옛 나라': { type: 'regime' } });
  assert.ok(!('type' in r3.periods[0]) && warns.some(w => /형식 4 선언 팩에만/.test(w)), '형식 3 팩은 형식 4 덧칸을 알리고 뺌');
  assert.equal(HT.getBuiltinPacks().some(p => p.id === 'f3-reg'), false, '따로 쓰는 등록부는 내장 목록을 더럽히지 않음');
  t.count += 5;
  /* 2. 형식 4 선언 — 압축 배열 · 시대 객체(이름표 + 그릇 짝 · R1) · 기간 있는 within(R2) · 옛 id 박기(R7) · 사람 · 사건 */
  warns.length = 0;
  R.definePack({ id: 'f4-reg', name: '형식 4 등록', formatVersion: 4, spheres: [{ id: 'mist-sea', name: '안개 바다권', order: 1 }], tracks: [{ id: 'ta', name: '가 줄', sphere: 'mist-sea' }],
    yearCycles: [{ sphere: 'mist-sea', names: '육십갑자', label: '간지' }] });
  const raw = R.get('f4-reg');
  assert.ok(raw.formatVersion === 4 && Array.isArray(raw.objects) && Array.isArray(raw.events) && !('periods' in raw) && !('epochs' in raw), '형식 4 선언은 objects · events만 준비');
  R.extendPack('f4-reg', {
    track: 'ta',
    eras: [[1, 99, '첫 시대', ''], [100, 400, '갈라진 시대', '날짜 칸 이름표', { id: 'ta-e-split-tag' }], [100, 400, '갈라진 시대', '그릇', { id: 'ta-e-split', label: '할거', within: 'ta-e-split-tag' }]],
    periods: [
      [1, 'now', '높은 왕국', '오래 감'],
      [150, 300, '붉은 나라', '그릇 안', { within: 'ta-e-split' }],
      [120, 500, '푸른 나라', '통일한 해까지 그릇 안', { id: 'old-blue', within: [{ of: 'ta-e-split', end: 400 }] }],
      [310, 390, '실권 무리', ''],
    ],
    persons: [[90, 160, '첫 임금', '사람'], { name: '둘째 임금', birth: 130, death: 200 }],
    events: [[200, null, 'politics', 2, '큰 싸움', '', { polity: '붉은 나라' }]],
  });
  R.describePeriods('f4-reg', 'ta', {
    '높은 왕국': { leaders: [['첫 임금', 100, 160], ['둘째 임금', 160, 200]], cabinets: [['큰 재상', 110, 150]], eras: [['한빛', 100, 120]], power: [{ name: '외척 무리', start: 200, end: 220 }], importance: 3 },
    '붉은 나라': { partOf: [{ of: '높은 왕국', relation: 'nominal' }], succeeds: [{ from: '높은 왕국', type: 'indirect', how: '갈라짐', note: '갈라섬' }] },
    '실권 무리': { type: 'regime', partOf: [{ of: '높은 왕국', relation: 'nominal' }], succeeds: [{ from: '붉은 나라', type: 'direct', how: '선양' }, ['높은 왕국', 'indirect', '옛 꼴 배열']], status: 'rival' },
    'ta-e-split': { importance: 2 },
    '없는 나라': { people: 'x' },
  });
  assert.ok(warns.length === 1 && /ta 트랙에 "없는 나라" 객체가 없습니다/.test(warns[0]), `없는 객체만 알림: ${warns.join(' / ')}`);
  const O = n => raw.objects.find(o => o.name === n && o.type !== 'era');
  assert.equal(O('높은 왕국').id, `ta-p${HT.hash(1 + '높은 왕국')}`, '형식 4도 id 길 그대로');
  assert.equal(O('푸른 나라').id, 'old-blue', '덧칸 id가 이김(R7)');
  t.same(raw.objects.filter(o => o.type === 'era').map(o => o.id), [`ta-e${HT.hash(1 + '첫 시대')}`, 'ta-e-split-tag', 'ta-e-split'], '시대 객체의 id(덧칸이 없으면 ta-e…)');
  t.same(O('높은 왕국').offices, [{ name: '지도자', cells: [['첫 임금', 100, 160], ['둘째 임금', 160, 200]] }, { name: '내각', cells: [['큰 재상', 110, 150]] }], '지도자 · 내각은 직위 줄로');
  assert.equal(raw.objects.find(o => o.id === 'ta-e-split').importance, 2, 'id로도 찾음');
  assert.equal(raw.objects.filter(o => o.type === 'person').length, 2, '사람 객체 둘');
  t.count += 8;
  /* 3. 정규화(다리로 내림) — 오류 0 · 그릇 · 이름표 · 사람 · 승계 방식 · 육십갑자 줄 */
  const r = HT.normalizePack(JSON.parse(JSON.stringify(raw)));
  assert.ok(r.pack && !r.errors.length, `등록 함수로 만든 형식 4 팩의 정규화: ${r.errors.map(e => e.msg).join(' / ')}`);
  const J = HT.packToJSON(r.pack);
  const P4 = n => J.periods.find(p => p.name === n);
  t.same(J.scopes.map(s => [s.id, s.within ?? s.epoch ?? null, s.members]), [['ta-e-split', 'ta-e-split-tag', [{ polity: P4('붉은 나라').id }, { polity: 'old-blue' }].map(HT.compactScopeRef)]], '그릇 하나 · 짝 이름표를 가리킴 · 구성원 둘');
  t.same(J.epochs.map(e => e.id).sort(), [`ta-e${HT.hash(1 + '첫 시대')}`, 'ta-e-split-tag'].sort(), '구성원 없는 시대는 날짜 칸 이름표');
  t.same(J.figures.map(f => f.name), ['첫 임금', '둘째 임금'], '사람 → 인물');
  t.same(P4('높은 왕국').leaders.map(c => c.name), ['첫 임금', '둘째 임금'], '지도자 칸');
  t.same(P4('붉은 나라').succeeds, [{ from: '높은 왕국', type: 'indirect', how: 'split', note: '갈라섬' }], '승계 방식 — 한국어 이름을 id로 지킴');
  t.same(P4('실권 무리').succeeds.map(s => s.how ?? null), ['abdication', null], '객체 꼴 · 배열 꼴 승계 줄을 함께 받음');
  assert.equal(P4('실권 무리').type, 'regime', '종류 덧칸');
  t.same(J.yearCycles, [{ sphere: 'mist-sea', names: Array.from({ length: 60 }, (_, k) => HT.ganji(4 + k)), start: 4, label: '간지', builtin: HT.SEXAGENARY }], '육십갑자 예약 값을 펴고 표지를 둠');
  assert.equal(J.yearCycle, undefined, '문화권 줄은 최상위 간지 줄이 되지 않음');
  HT.buildModel([r.pack], null);
  t.count += 10;
  /* 3-2. 옮겨 앉기의 그릇 밖 토막(HT.F4.split — 새 앱 내보내기만 · 리메이크 6단계): within이 객체 기간을 다 덮지 않으면 앞 · 뒤를 그릇 없는 토막으로 —
     within 하나도 나눔(예전에는 기간을 알림 없이 버리고 끝까지 그릇 안). 기간 없는 · 기간을 다 덮는 within 하나와 웹 · 메이커(나누지 않음)는 그대로 */
  {
    const was = HT.F4.split;
    const J5 = { format: HT.FORMAT, formatVersion: 4, id: 'f4-mv', name: '그릇 밖 토막', tracks: [{ id: 'ta', name: '가 줄' }], events: [], objects: [
      { id: 'e1', type: 'era', track: 'ta', name: '갈라진 시대', start: 100, end: 400 },
      { id: 'green', track: 'ta', name: '푸른 들', start: 50, end: 300, within: [{ of: 'e1', start: 100 }] },
      { id: 'red', track: 'ta', name: '붉은 나라', start: 150, end: 300, within: [{ of: 'e1' }] },
      { id: 'gray', track: 'ta', name: '잿빛 나라', start: 100, end: 400, within: [{ of: 'e1', start: 100, end: 400 }] },
    ] };
    const cut = (J4, names) => {
      const S = HT.F4.down(JSON.parse(JSON.stringify(J4)));
      return [S.periods.filter(p => names.includes(p.name)).map(p => [p.id, p.start, p.end, (p.leaders || []).map(c => c.name)]), (S.scopes || []).map(s => [s.id, s.members.map(m => (typeof m === 'string' ? m : m.polity))])];
    };
    try {
      HT.F4.split = true;
      t.same(cut(raw, ['푸른 나라'])[0], [['old-blue', 120, 400, []], ['old-blue.mv400', 400, 500, []]], '통일한 해까지 그릇 안(end만): 그릇 안 토막 + 그릇 밖 뒤 토막');
      assert.ok(cut(raw, ['푸른 나라'])[1].find(s => s[0] === 'ta-e-split')[1].includes('old-blue') && !cut(raw, ['푸른 나라'])[1].some(s => s[1].includes('old-blue.mv400')), '뒤 토막은 그릇 구성원이 아님');
      t.same(cut(J5, ['푸른 들', '붉은 나라', '잿빛 나라']), [[['green', 50, 100, []], ['green.mv100', 100, 300, []], ['red', 150, 300, []], ['gray', 100, 400, []]], [['e1', ['green.mv100', 'red', 'gray']]]], '늦게 든 그릇(start만): 그릇 밖 앞 토막 + 그릇 안 토막 · 기간 없는 · 다 덮는 within은 그대로');
      HT.F4.split = false;
      t.same(cut(J5, ['푸른 들'])[0], [['green', 50, 300, []]], '나누지 않을 때(웹 · 메이커)는 그대로');
    } finally {
      HT.F4.split = was;
    }
    t.count += 4;
  }
  /* 4. 승계 방식 — 낱말 · 모르는 방식 경고 · 다리 왕복 · 저장 · 손실 목록 */
  for (const [v, id] of [['선양', 'abdication'], ['abdication', 'abdication'], ['개명', 'rename'], ['이름 바꿈', 'rename'], ['합쳐짐', 'merge'], ['통합', 'merge'], ['승계 주장', 'claim'], ['혼인', 'marriage'], ['상속', 'inheritance'], ['정복', 'conquest'], ['분열', 'split'], ['constructor', ''], ['', '']]) assert.equal(HT.succHow(v), id, `방식 낱말 "${v}"`);
  assert.equal(HT.SUCC_HOWS.length, 8, '방식 여덟(설계의 일곱 + 선양)');
  let w = [];
  t.same(HT.normalizeSucc({ from: 'A', type: '직접', how: '외계 침공', note: 'n' }, m => w.push(m)), { from: 'A', type: 'direct', note: 'n' }, '모르는 방식은 뺌');
  assert.ok(w.length === 1 && /방식 "외계 침공"을\(를\) 알 수 없어 뺐습니다/.test(w[0]), '모르는 방식 경고');
  t.same(HT.normalizeSucc({ from: 'A', type: 'partial', degree: 3, how: '갈라짐', note: 'n' }), { from: 'A', type: 'partial', degree: 3, how: 'split', note: 'n' }, '부분 승계에도 방식(열쇠 차례: 정도 → 방식 → 메모)');
  const up = HT.F4.up(J).json;
  t.same(up.objects.find(o => o.name === '붉은 나라').succeeds, P4('붉은 나라').succeeds, '올림이 방식을 실음');
  t.same(t.N(HT.F4.down(up)).periods.find(p => p.name === '붉은 나라').succeeds, P4('붉은 나라').succeeds, '내림 → 정규화에서도 방식 그대로');
  t.same(HT.F4.toFile(J, null).objects.find(o => o.name === '실권 무리').succeeds[0].how, 'abdication', '저장(toFile)에 방식');
  assert.ok(HT.F4.lossOf(null, J).some(l => /승계 방식 2개/.test(l)), `옛 형식 저장의 손실 목록에 승계 방식: ${HT.F4.lossOf(null, J).join(' / ')}`);
  assert.ok(!Object.values(HT.F4.extrasOf(up).objects).some(l => 'succeeds' in l), 'extrasOf가 승계를 잃은 칸으로 모으지 않음');
  const g = t.N({ format: HT.FORMAT, id: 'f4-gh', name: '단체 방식', tracks: [{ id: 'ta', name: '가 줄' }], periods: [P('가 나라')], groups: [{ name: '옛 무리', track: 'ta', start: 100, end: 200 }, { name: '새 무리', track: 'ta', start: 200, end: 300, from: [{ group: '옛 무리', how: 'unknown' }] }] });
  t.same(g.groups[1].from, [{ group: '옛 무리', how: 'unknown' }], '단체의 from.how(미상 포함)는 그대로');
  t.count += 10;
  /* 5. 육십갑자 예약 값 — 펴기 · 표지 · 다시 읽어도 같음 · 고친 이름은 표지를 뺌 · 모르는 표지 · 셈이 내장 간지와 같음 */
  w = [];
  const six = Array.from({ length: 60 }, (_, k) => HT.ganji(4 + k));
  const ys = HT.readYearCycles([{ sphere: 'a', names: '육십갑자', start: 99 }, { names: ' sexagenary ', label: '해' }, { sphere: 'c', builtin: 'sexagenary' }, { sphere: 'd', names: ['갑', '을'], start: 4, builtin: 'sexagenary' }, { sphere: 'e', names: '갑, 을', start: 1, builtin: 'xyz' }, { sphere: 'f', names: ['육십갑자'] }], (m, i) => w.push([i, m]));
  t.same(ys.map(c => [c.sphere ?? null, c.names.length, c.start, c.builtin ?? null]), [['a', 60, 4, 'sexagenary'], [null, 60, 4, 'sexagenary'], ['c', 60, 4, 'sexagenary'], ['d', 2, 4, null], ['e', 2, 1, null], ['f', 60, 4, 'sexagenary']], '펴기(낱말 하나뿐인 목록도 — 메이커 「주기」 표) · 표지 · 고친 이름은 표지를 뺌');
  t.same(ys[0].names, six, '이름 60개 = 갑자 ~ 계해');
  assert.equal(ys[1].label, '해', '줄 제목은 그대로');
  t.same(w.map(x => x[0]), [3, 4], `표지를 뺀 줄 · 모르는 표지만 알림: ${w.map(x => x[1]).join(' / ')}`);
  for (const y of [-2333, -57, -1, 1, 4, 64, 668, 1392, 1984, 2026]) assert.equal(HT.cycleName(ys[0], y), HT.ganji(y), `${y}년의 이름이 내장 간지와 같음`);
  w = [];
  t.same(HT.readYearCycles(ys.slice(0, 3), m => w.push(m)), ys.slice(0, 3), '펴진 줄을 다시 읽어도 같음');
  assert.equal(w.length, 0, '다시 읽을 때 알림 없음');
  assert.equal(HT.wholeYearCycle(ys), null, '육십갑자 전체 줄은 옛 열쇠 yearCycle이 되지 않음(비운 것과 같음)');
  const d = { yearCycles: [ys[1]] };
  assert.ok(!HT.syncYearCycles(d, 'cycle') && d.yearCycles.length === 1, '메이커 맞춤이 육십갑자 전체 줄을 지우지 않음');
  t.count += 9;
  /* 6. 다리의 최상위 간지 줄 고르기 — 문화권 없는 줄만 · 육십갑자 전체 줄은 비운 것과 같음 */
  w = [];
  const D = yc => HT.F4.down({ format: HT.FORMAT, formatVersion: 4, id: 'f4-pick', name: '고르기', tracks: [{ id: 'ta', name: '가 줄' }], yearCycles: yc, objects: [] }, m => w.push(m));
  assert.equal(D([{ names: '육십갑자' }, { sphere: 'a', names: ['한', '둘'], start: 1 }]).yearCycle, undefined, '전체 줄이 육십갑자면 최상위 간지 줄을 두지 않음');
  assert.equal(D([{ builtin: 'sexagenary', label: '간지' }]).yearCycle, undefined, '표지만 적은 전체 줄도');
  assert.ok(!w.length, `육십갑자 전체 줄은 알림 없음: ${w.join(' / ')}`);
  t.same(D([{ sphere: 'a', names: ['한', '둘'], start: 1 }, { names: ['갑', '을'], start: 1, builtin: 'xyz' }]).yearCycle, { names: ['갑', '을'], start: 1 }, '문화권 줄 뒤의 전체 줄을 고름(표지 칸은 뺌)');
  assert.ok(w.some(x => /주기 줄 2개 가운데/.test(x)), '전체 줄을 고르면 알림');
  t.count += 5;
}

/* ⑱ 리메이크 6단계 걸음 2 — 형식 더하기 읽기(세계사 결정 D2 · D3 · D8): 이름 번호 regnal('n세' 표시 · 자동 매김 끔 · 틀린 값 알림 · 대수와 함께) ·
   지도자 표기 낱말 leaderLabels(팩 · 문화권 — 문화권이 이김 · 표기 고르기 선택지 · 다른 이름 줄) · 종교 faiths(지위 변천 꼴 · 겹침 · 기간 밖 · 모델의 faithSpans · 패치) ·
   다리 왕복 · 옛 형식(3) 손실 목록 세 줄 · 가상 팩 f4-crowns. 이름은 가상 */
function unitWorld(HT, t) {
  const base = more => Object.assign({ format: HT.FORMAT, id: 'f4-world', name: '세계사 칸', spheres: [{ id: 'mist-sea', name: '안개 바다권', order: 1 }], tracks: [{ id: 'ta', name: '가 줄', sphere: 'mist-sea' }, { id: 'tb', name: '나 줄' }] }, more);
  /* 1. 이름 번호 — 'n세' 표시(대표 이름 뒤 · 고른 칸이 비면 대표 이름으로) · 자동 매김 끔(그 줄만) · 적은 대수는 그대로 · 틀린 값은 알리고 뺌 */
  const raw1 = base({
    periods: [
      P('높은 왕국', { leaders: [{ name: '헨리', regnal: 7, start: 100, end: 150 }, { name: '헨리', regnal: '8', title: '큰손', start: 150, end: 200 }, { name: '에드', start: 200, end: 250 }, { name: '메리', regnal: 1, ordinal: 12, start: 250, end: 300 }] }),
      P('낮은 나라', { track: 'tb', leaders: [['첫 임금', 100, 150], ['둘째 임금', 150, 200], { name: '셋째 임금', regnal: '여덟', start: 200 }, { name: '넷째', regnal: 0, start: 250 }] }),
    ],
  });
  const r1 = HT.normalizePack(JSON.parse(JSON.stringify(raw1)));
  assert.ok(r1.pack && !r1.errors.length, `이름 번호의 정규화: ${r1.errors.map(e => e.msg).join(' / ')}`);
  const L1 = r1.pack.periods[0].leaders;
  t.same(L1.map(c => [c.regnal ?? null, c.ordinal ?? null]), [[7, null], [8, null], [null, null], [1, 12]], '이름 번호를 적은 줄은 빈 대수를 매기지 않음 · 적은 대수(12)는 그대로 · 수 글 "8"은 수로');
  t.same(L1.map(c => HT.leaderLabel(c)), ['헨리 7세', '헨리 8세', '에드', '메리 1세'], "기본 표기는 대표 이름 뒤 'n세'");
  assert.equal(HT.leaderLabel(L1[1], 'title'), '큰손', '고른 칸(시호 자리)이 있으면 그 글 그대로');
  assert.equal(HT.leaderLabel(L1[0], 'temple'), '헨리 7세', '고른 칸이 비면 대표 이름(이름 번호 포함)으로 — 새 앱의 구역 46 되돌림과 같은 뜻');
  assert.equal(HT.leaderLabel(L1[3], 'auto', true), '12대 메리 1세', '대수 체크는 앞에 · 이름 번호는 뒤에');
  assert.equal(HT.leaderFull(L1[3]), '제12대 메리 1세', '상세 한 줄에 대수와 이름 번호를 함께');
  const L2 = r1.pack.periods[1].leaders;
  t.same(L2.map(c => c.ordinal), [1, 2, 3, 4], '이름 번호가 없는 줄은 지금처럼 1부터 자동(틀린 값은 이름 번호가 아님)');
  assert.ok(L2.every(c => !('regnal' in c)), '틀린 이름 번호는 뺌');
  const bad = r1.warnings.filter(w => /이름 번호\(regnal\)/.test(w.msg)).map(w => w.msg);
  assert.ok(bad.length === 2 && /"셋째 임금"의 이름 번호\(regnal\) "여덟"/.test(bad[0]) && /"넷째"의 이름 번호\(regnal\) "0"/.test(bad[1]), `틀린 이름 번호 알림 둘: ${bad.join(' / ')}`);
  t.same([null, '', ' ', 3, '4', ' 5 ', 0, -1, 1.5, '1.5', '여덟', true, [2], {}].map(v => { const n = HT.readRegnal(v); return n === null ? 'null' : Number.isNaN(n) ? 'NaN' : n; }), ['null', 'null', 'null', 3, 4, 5, 'NaN', 'NaN', 'NaN', 'NaN', 'NaN', 'NaN', 'NaN', 'NaN'], 'HT.readRegnal — 양의 정수만');
  const nl = HT.numberLeaders([{}, { regnal: 2 }, {}]);
  t.same(nl.map(c => c.ordinal ?? null), [null, null, null], 'HT.numberLeaders — 이름 번호가 하나라도 있으면 그 줄 전체');
  t.count += 12;
  /* 2. 지도자 표기 낱말 — 팩 · 문화권(문화권이 칸마다 이김) · 모르는 칸 · 꼴 틀림 · 모델 도우미 · 다른 이름 줄 · 표기 고르기 선택지 */
  let w = [];
  t.same(HT.readLeaderLabels({ temple: ' 치세명 ', title: '', given: '본명', era: 'x' }, m => w.push(m)), { temple: '치세명', given: '본명' }, '빈 칸은 뺌 · 글은 다듬음');
  assert.ok(w.length === 1 && /"era"은\(는\) 모르는 칸이라 뺐습니다/.test(w[0]), '모르는 칸 알림');
  w = [];
  assert.equal(HT.readLeaderLabels(['치세명'], m => w.push(m)), null, '배열은 꼴 틀림');
  assert.ok(w.length === 1 && /꼴이어야 해서 무시했습니다/.test(w[0]), '꼴 틀림 알림');
  assert.equal(HT.readLeaderLabels({ temple: ' ' }), null, '빈 낱말뿐이면 없음');
  const raw2 = base({
    leaderLabels: { temple: '치세명', title: '별명', given: '본명' },
    spheres: [{ id: 'mist-sea', name: '안개 바다권', order: 1, leaderLabels: { title: '존호', bad: 1 } }],
    periods: [P('높은 왕국', { leaders: [{ name: '헨리', temple: '헨리', title: '큰손', given: '하리', regnal: 8, start: 100 }] }), P('낮은 나라', { track: 'tb', leaders: [['첫 임금', 100]] })],
  });
  const r2 = HT.normalizePack(JSON.parse(JSON.stringify(raw2)));
  assert.ok(r2.pack && !r2.errors.length, '표기 낱말의 정규화');
  t.same(r2.pack.leaderLabels, { temple: '치세명', title: '별명', given: '본명' }, '팩의 낱말을 지킴');
  t.same(r2.pack.spheres[0].leaderLabels, { title: '존호' }, '문화권의 낱말을 지킴(모르는 칸은 뺌)');
  assert.ok(r2.warnings.some(x => x.kind === 'spheres' && /문화권 "mist-sea": 지도자 표기 낱말\(leaderLabels\)의 "bad"/.test(x.msg)), '문화권 낱말의 모르는 칸 알림');
  const m2 = HT.buildModel([r2.pack], null);
  assert.ok(!Object.keys(m2).includes('leaderLabelMap'), '팩 낱말 표는 열거되지 않는 모델 속성(내보내기 · 저장소에 섞이지 않음)');
  const pa = m2.periods.find(p => p.name === '높은 왕국');
  const pb = m2.periods.find(p => p.name === '낮은 나라');
  t.same(HT.leaderWords(pa, m2), { temple: '치세명', title: '존호', given: '본명' }, '문화권이 칸마다 이기고 비운 칸은 팩의 것');
  t.same(HT.leaderWords(pb, m2), { temple: '치세명', title: '별명', given: '본명' }, '문화권 없는 트랙은 팩의 것');
  t.same(HT.leaderWords(pa), HT.leaderWords(pa, m2), '모델을 비우면 마지막으로 지은 모델의 표');
  t.same(HT.leaderWords({ track: 'tb', packId: 'nobody' }, m2), HT.LEADER_WORDS, '낱말이 없으면 묘호 · 시호 · 이름');
  assert.equal(HT.leaderFull(pa.leaders[0], HT.leaderWords(pa, m2)), '헨리 8세 (치세명 헨리 · 존호 큰손 · 본명 하리)', '상세 한 줄이 그 정권의 낱말을 씀');
  t.same(HT.cellKind('leader').facts(pa.leaders[0], HT.leaderWords(pa, m2)), ['치세명 헨리', '존호 큰손', '본명 하리'], '칸 종류 표의 다른 이름 줄도');
  const modes = Object.fromEntries(HT.leaderModes(m2).map(o => [o.id, o.name]));
  assert.ok(modes.auto === '기본 이름' && modes.temple === '치세명' && modes.given === '본명' && modes.all === '모두' && modes.title.split('/').sort().join() === ['별명', '존호'].sort().join() && modes['temple-title'] === `치세명·${modes.title}`, `표기 고르기의 선택지 글 — 모델에서 쓰는 낱말(서로 다르면 /): ${JSON.stringify(modes)}`);
  t.same(HT.leaderModes(null).map(o => o.name), HT.LEADER_LABELS.map(o => o.name), '모델이 없으면 지금 낱말');
  t.count += 16;
  /* 3. 종교 — 칸 꼴(배열 · 객체 · faith 열쇠) · 첫 칸의 시작을 비움 · 겹침 · 기간 밖 · 모델의 faithSpans · 패치(set.faiths · 빈 목록) */
  const raw3 = base({
    periods: [
      P('높은 왕국', { id: 'p-high', faiths: [['옛 신앙', null, 180, '메모'], { faith: '새 교회', start: 180 }] }),
      P('겹친 나라', { track: 'tb', faiths: [['가 신앙', 100, 200], ['나 신앙', 150], ['다 신앙', 250, 400], { name: '' }] }),
    ],
  });
  const fix3 = HT.normalizePack({ format: HT.FORMAT, id: 'f4-world-fix', name: '고침', tracks: [{ id: 'ta', name: '가 줄' }], patches: [{ target: 'f4-world/p-high', set: { faiths: [['고친 신앙', 120]] } }] });
  const r3 = HT.normalizePack(JSON.parse(JSON.stringify(raw3)));
  assert.ok(r3.pack && !r3.errors.length, '종교의 정규화');
  t.same(r3.pack.periods[0].faiths, [{ name: '옛 신앙', end: 180, note: '메모' }, { name: '새 교회', start: 180 }], '종교 칸 목록(지위 변천 꼴 · faith 열쇠도 읽음)');
  const fw = r3.warnings.filter(x => /종교/.test(x.msg)).map(x => x.msg);
  assert.ok(fw.some(m => /종교 변천 4번째 칸: 종교 이름이 없어 뺐습니다/.test(m)) && fw.some(m => /종교 "가 신앙"와\(과\) "나 신앙"의 기간이 겹칩니다/.test(m)) && fw.some(m => /종교 "다 신앙"의 기간이 정권 기간 밖으로/.test(m)), `종교의 알림(빈 이름 · 겹침 · 기간 밖): ${fw.join(' / ')}`);
  t.same(fix3.pack.patches[0].set.faiths, [{ name: '고친 신앙', start: 120 }], '패치의 종교도 같은 꼴로');
  assert.ok(HT.PATCHABLE.includes('faiths'), '종교는 패치로 고칠 수 있는 칸');
  const m3 = HT.buildModel([r3.pack], null);
  const q = m3.periods.find(p => p.name === '높은 왕국');
  t.same(q.faithSpans.map(c => [c.name, c.start, c.end, c.startAuto, c.endAuto, c.endPolity]), [['옛 신앙', 100, 180, true, false, false], ['새 교회', 180, 300, false, true, true]], '모델의 종교 구간 — 비운 시작은 정권 시작 · 비운 끝은 정권 끝');
  t.same(q.faiths, r3.pack.periods[0].faiths, '원문 faiths는 그대로');
  const m3p = HT.buildModel([r3.pack, fix3.pack], null);
  t.same(m3p.periods.find(p => p.name === '높은 왕국').faithSpans.map(c => c.name), ['고친 신앙'], '패치가 고친 종교로 구간');
  const r3e = HT.normalizePack(base({ periods: [P('가 나라')], patches: [{ target: 'x-pack/a', set: { faiths: [] } }, { target: 'x-pack/a', set: { faiths: null, note: '비우기 아님' } }] }));
  t.same(r3e.pack.patches[0].set.faiths, [], '빈 목록은 대상의 종교를 비움');
  assert.ok(!(r3e.pack.patches[1] && 'faiths' in r3e.pack.patches[1].set) && r3e.warnings.some(x => /종교 변천은 목록이어야 해서 무시했습니다/.test(x.msg)), 'null은 무시하고 알림');
  w = HT.readFaiths('x');
  assert.ok(w.problems.length === 1 && /종교 변천은 목록이어야/.test(w.problems[0]), 'HT.readFaiths — 목록이 아니면 알림');
  t.same(HT.readRanks([['왕', 1, 9]]).list, [{ name: '왕', start: 1, end: 9 }], '지위 변천 읽기는 그대로(몸을 함께 씀)');
  t.count += 11;
  /* 4. 다리 왕복 — 올림 · 내림이 셋을 그대로 · 저장(toFile) · 옛 형식(3) 손실 목록 세 줄 */
  const J4 = HT.packToJSON(HT.normalizePack(JSON.parse(JSON.stringify(Object.assign({}, raw2, { periods: raw2.periods.concat(raw3.periods.slice(0, 1).map(p => Object.assign({}, p, { name: '셋째 나라' }))) })))).pack);
  const up = HT.F4.up(J4).json;
  t.same(up.leaderLabels, J4.leaderLabels, '올림: 팩 낱말');
  t.same(up.spheres, J4.spheres, '올림: 문화권 낱말');
  t.same(up.objects.find(o => o.name === '높은 왕국').offices[0].cells[0].regnal, 8, '올림: 이름 번호');
  t.same(up.objects.find(o => o.name === '셋째 나라').faiths, J4.periods.find(p => p.name === '셋째 나라').faiths, '올림: 종교');
  t.same(t.N(HT.F4.down(up)), J4, '내림 → 정규화가 원래와 같음(셋 다 그대로)');
  t.same(HT.F4.toFile(J4, null).leaderLabels, J4.leaderLabels, '저장(toFile)에 팩 낱말');
  const loss = HT.F4.lossOf(null, J4);
  assert.ok(loss.some(l => /^이름 번호 1개/.test(l)) && loss.some(l => /^지도자 표기 낱말 2곳/.test(l)) && loss.some(l => /^종교 2개/.test(l)), `옛 형식 저장의 손실 목록 세 줄: ${loss.join(' / ')}`);
  assert.ok(!Object.values(HT.F4.extrasOf(up).objects).some(l => 'faiths' in l), 'extrasOf가 종교를 잃은 칸으로 모으지 않음(정규화가 지킴)');
  t.count += 8;
  /* 5. 가상 팩 f4-crowns — 형식 4 원본에서: 이름 번호 줄 · 문화권 낱말 · 종교 구간 */
  const crowns = JSON.parse(readFileSync(join(root, 'prototype/fixtures/f4/f4-crowns.json'), 'utf8'));
  const rc = HT.normalizePack(crowns);
  assert.ok(rc.pack && !rc.errors.length, 'f4-crowns 정규화');
  const mc = HT.buildModel([rc.pack], null);
  const seol = mc.periods.find(p => p.id === 'o-seol');
  t.same(seol.leaders.map(c => HT.leaderFull(c, HT.leaderWords(seol, mc))), ['눈결 2세 (별명 흰서리)', '하림 1세 (본명 은 하림)', '제12대 서리 3세 (별명 얼음손)'], 'f4-crowns 설령 왕국 — 대수는 적은 것만 · 팩 낱말');
  const baek = mc.periods.find(p => p.id === 'o-baek');
  t.same(HT.leaderWords(baek, mc), { temple: '칭호명', title: '존호', given: '본명' }, 'f4-crowns 백사 해협권 — 문화권 낱말이 이김');
  t.same(baek.faithSpans.map(c => [c.name, c.start, c.end]), [['바다 신앙', 1350, 1440], ['등불 교단', 1440, 1600]], 'f4-crowns 종교 구간');
  t.same(mc.periods.find(p => p.id === 'o-coral').leaders.map(c => c.ordinal), [1, 2, 3], '이름 번호 없는 줄은 자동 대수 그대로');
  /* 화면이 길을 씀: 필터 바 · 메이커의 표기 고르기 · 칸 창 · 연표 풍선 */
  const viewer = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  const timeline = readFileSync(join(root, 'js/timeline.js'), 'utf8');
  assert.ok(/HT\.leaderModes\(state\.model\)/.test(viewer) && /K\.facts\(c, HT\.leaderWords\(x, state\.model\)\)/.test(viewer) && /HT\.leaderFull\(c, HT\.leaderWords\(p\)\)/.test(timeline) && /HT\.leaderFacts\(c, HT\.leaderWords\(p\)\)/.test(timeline), '표기 고르기 · 칸 창 · 연표 풍선이 표기 낱말을 씀');
  t.count += 6;
}

/* ⑲ 리메이크 6단계 걸음 3 — 메이커가 여는 길로 세계사 칸 넷이 저장 한 바퀴 뒤에도 남음: 형식 4 전용 팩 → 읽기(raw · raw4) → 작업본(HT.draft.clean + extrasOf) →
   객체 폼(지도자 줄의 이름 번호 칸 · 종교 줄 · 승계 줄의 방식 — 폼 조각을 작은 읽개로 채웠다 읽음) → 작업본에 적기(HT.draft.updateOwn) → 형식 4 저장(정규화 → packToJSON → toFile) →
   다시 열어 한 바퀴 더. 팩 · 문화권의 지도자 표기 낱말(팩 정보 폼 · 「문화권」 표가 고치는 칸)도. 이름은 가상 */
/** 폼 조각(HTML 글)을 querySelector · value만 되는 작은 나무로(dev-smoke의 읽개와 같은 꼴 — 폼을 채웠다 읽는 검사용) */
function miniDom(html) {
  const unesc = s => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const root0 = { tag: '#root', attrs: {}, kids: [], parent: null };
  const VOID = new Set(['input', 'br', 'img', 'hr', 'meta', 'link']);
  let cur = root0;
  for (const m of html.matchAll(/<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:\s+[^\s=>]+(?:="[^"]*")?)*)\s*\/?>|([^<]+)/g)) {
    if (m[4] != null) continue;
    const tag = m[2].toLowerCase();
    if (m[1]) {
      let n = cur;
      while (n && n.tag !== tag) n = n.parent;
      if (n) cur = n.parent;
      continue;
    }
    const attrs = {};
    for (const a of m[3].matchAll(/([^\s=>]+)(?:="([^"]*)")?/g)) attrs[a[1]] = a[2] == null ? '' : unesc(a[2]);
    const node = { tag, attrs, kids: [], parent: cur };
    cur.kids.push(node);
    if (!VOID.has(tag)) cur = node;
  }
  const simple = (n, sel) => {
    for (const part of sel.match(/[a-z][a-z0-9-]*|\.[\w-]+|\[[^\]]+\]|:[\w-]+/gi) || []) {
      if (part[0] === ':') return false; // :scope 같은 꾸밈은 이 읽개가 따라가지 않음(없는 것으로)
      if (part[0] === '.') { if (!(n.attrs.class || '').split(/\s+/).includes(part.slice(1))) return false; }
      else if (part[0] === '[') {
        const [, k, v] = part.match(/^\[([^=\]]+)(?:="([^"]*)")?\]$/);
        if (!(k in n.attrs) || (v != null && n.attrs[k] !== v)) return false;
      } else if (n.tag !== part.toLowerCase()) return false;
    }
    return true;
  };
  const matches = (n, sel) => sel.split(',').some(one => {
    const parts = one.trim().split(/\s+/).filter(x => x !== '>');
    if (!simple(n, parts[parts.length - 1])) return false;
    let i = parts.length - 2;
    for (let p = n.parent; p && i >= 0; p = p.parent) if (p.tag !== '#root' && simple(p, parts[i])) i--;
    return i < 0;
  });
  const all = n => n.kids.flatMap(k => [k, ...all(k)]);
  const wrap = n => {
    if (!n) return null;
    if (n.w) return n.w;
    n.w = {
      tagName: n.tag.toUpperCase(),
      get children() { return n.kids.map(wrap); },
      get parentElement() { return wrap(n.parent); },
      classList: { contains: c => (n.attrs.class || '').split(/\s+/).includes(c) },
      dataset: Object.fromEntries(Object.entries(n.attrs).filter(([k]) => k.startsWith('data-')).map(([k, v]) => [k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase()), v])),
      matches: sel => matches(n, sel),
      closest: sel => { for (let p = n; p && p.tag !== '#root'; p = p.parent) if (matches(p, sel)) return wrap(p); return null; },
      querySelector: sel => wrap(all(n).find(k => matches(k, sel))),
      querySelectorAll: sel => all(n).filter(k => matches(k, sel)).map(wrap),
      get checked() { return 'checked' in n.attrs; },
      get value() {
        if (n.tag === 'select') {
          const opts = all(n).filter(k => k.tag === 'option');
          return ((opts.find(o => 'selected' in o.attrs) || opts[0] || { attrs: {} }).attrs.value) ?? '';
        }
        return n.attrs.value ?? '';
      },
    };
    return n.w;
  };
  return wrap(root0);
}
async function unitMakerWorld(HT, t) {
  const raw4 = {
    format: HT.FORMAT, formatVersion: 4, id: 'f4-w3', name: '세계사 칸 메이커 왕복', version: '1.0.0',
    leaderLabels: { temple: '치세명', given: '본명' },
    spheres: [{ id: 'mist-sea', name: '안개 바다권', order: 1, leaderLabels: { title: '존호' } }],
    tracks: [{ id: 'ta', name: '가 줄', sphere: 'mist-sea' }],
    objects: [
      { id: 'o-old', name: '옛 왕국', track: 'ta', start: 1, end: 100 },
      { id: 'o-gate', name: '문 나라', track: 'ta', start: 1, end: 100 },
      {
        id: 'o-high', name: '높은 왕국', track: 'ta', start: 100, end: 300,
        succeeds: [{ from: '옛 왕국', type: 'direct', how: 'abdication', note: '물려받음' }, { from: '문 나라', type: 'indirect' }],
        faiths: [['옛 신앙', null, 180, '첫 국교'], { faith: '새 교회', start: 180, certainty: 'estimated' }],
        offices: [{ name: '지도자', cells: [{ name: '헨리', regnal: 7, temple: '헨리', start: 100, end: 150 }, { name: '헨리', regnal: 8, title: '큰손', start: 150, end: 200 }, { name: '에드', start: 200 }] }],
      },
    ],
  };
  if (!HT.packFile) await import(pathToFileURL(join(root, 'js/packfile.js')).href);
  /** 메이커가 여는 길(js/maker.js openFile — 전용 팩 읽기 → 작업본 → extras) */
  const open = async j4 => {
    const got = await HT.packFile.parse(await HT.packFile.build(j4));
    const d = HT.draft.clean(got.raw);
    d.f4extras = HT.F4.extrasOf(got.raw4);
    return d;
  };
  /** 메이커가 저장하는 길(js/maker.js exportFile) */
  const save = d => {
    const r = HT.normalizePack(d);
    assert.ok(r.pack && !r.errors.length, `저장 길의 정규화: ${r.errors.map(e => e.msg).join(' / ')}`);
    return HT.F4.toFile(HT.packToJSON(r.pack), d.f4extras);
  };
  /** 객체 폼 한 바퀴 — 폼을 채우는 조각(HT.fillCellRows와 같은 줄 HTML)으로 채우고 폼의 읽기(HT.readCellRows · readSuccRows)로 읽어 작업본에 적음(HT.draft.updateOwn) */
  const formTrip = (d, id) => {
    const item = HT.draft.findOwn(d, id).item;
    const faithRaw = c => (c && typeof c === 'object' && !Array.isArray(c) && c.name == null ? Object.assign({}, c, { name: c.faith }) : c);
    const dom = miniDom(
      `<div class="cell-rows" data-cells="leaders">${(item.leaders || []).map(c => HT.cellRowHTML('leaders', HT.formCell('leaders', c))).join('')}</div>` +
        `<div class="cell-rows" data-cells="faiths">${(item.faiths || []).map(c => HT.cellRowHTML('faiths', HT.formCell('faiths', faithRaw(c)))).join('')}</div>` +
        `<div class="succ-rows" data-succ>${(item.succeeds || []).map(s => HT.succRowHTML(s)).join('')}</div>`
    );
    const problems = [];
    const obj = { leaders: HT.readCellRows(dom, 'leaders', '지도자', problems), faiths: HT.readCellRows(dom, 'faiths', '종교', problems), succeeds: HT.readSuccRows(dom) };
    assert.deepEqual(problems, [], `폼을 채우고 그대로 읽었는데 문제: ${problems.join(' / ')}`);
    assert.ok(HT.draft.updateOwn(d, id, obj), '작업본에 적기');
    return obj;
  };
  const check = (j4, label) => {
    const o = j4.objects.find(x => x.id === 'o-high');
    t.same(o.offices[0].cells.map(c => [c.name, c.regnal ?? null, c.ordinal ?? null]), [['헨리', 7, null], ['헨리', 8, null], ['에드', null, null]], `${label}: 이름 번호(대수는 매기지 않음)`);
    t.same(o.faiths, [{ name: '옛 신앙', end: 180, note: '첫 국교' }, { name: '새 교회', start: 180, certainty: 'estimated' }], `${label}: 종교`);
    t.same(o.succeeds.map(s => [s.from, s.type, s.how || '']), [['옛 왕국', 'direct', 'abdication'], ['문 나라', 'indirect', '']], `${label}: 승계 방식`);
    t.same([j4.leaderLabels, j4.spheres[0].leaderLabels], [{ temple: '치세명', given: '본명' }, { title: '존호' }], `${label}: 팩 · 문화권의 표기 낱말`);
    assert.equal(j4.formatVersion, 4, `${label}: 형식 4`);
  };
  /* 1. 열고 폼을 거쳐 저장 */
  let d = await open(raw4);
  const obj = formTrip(d, 'o-high');
  t.same(obj.leaders.map(c => c.regnal ?? null), [7, 8, null], '폼의 이름 번호 칸이 채워지고 읽힘');
  t.same(obj.faiths.map(c => c.name), ['옛 신앙', '새 교회'], '폼의 종교 줄이 채워지고 읽힘(faith 열쇠도)');
  t.same(obj.succeeds.map(s => s.how || ''), ['abdication', ''], '폼의 승계 줄 방식 고르기가 채워지고 읽힘');
  let j4 = save(d);
  check(j4, '한 바퀴');
  /* 2. 다시 열어 한 바퀴 더 — 같음 */
  d = await open(j4);
  formTrip(d, 'o-high');
  const j4b = save(d);
  check(j4b, '두 바퀴');
  t.same(j4b, j4, '두 바퀴째 저장이 첫 저장과 같음');
  /* 3. 메이커에서 고침 — 팩 정보 폼 · 「문화권」 표의 낱말(작업본의 leaderLabels 칸) · 폼의 이름 번호 · 종교 · 방식 */
  d.leaderLabels = { temple: '치세명', title: '별명' };
  delete d.spheres[0].leaderLabels;
  const high = HT.draft.findOwn(d, 'o-high').item;
  high.leaders[2] = Object.assign({}, high.leaders[2], { regnal: 1 });
  high.faiths = [{ name: '새 교회', start: 100 }];
  high.succeeds[1] = Object.assign({}, high.succeeds[1], { how: 'split' });
  formTrip(d, 'o-high');
  j4 = save(d);
  const o = j4.objects.find(x => x.id === 'o-high');
  t.same([j4.leaderLabels, j4.spheres[0].leaderLabels ?? null, o.offices[0].cells[2].regnal, o.faiths, o.succeeds[1].how], [{ temple: '치세명', title: '별명' }, null, 1, [{ name: '새 교회', start: 100 }], 'split'], '고친 값이 저장에 실림(비운 문화권 낱말은 빠짐)');
  /* 4. 폼이 막는 것 — 틀린 이름 번호 · 대수 칸의 "n세" · 둘째 줄의 빈 종교 시작 */
  const bad = miniDom(`<div data-cells="leaders">${HT.cellRowHTML('leaders', { name: '가', regnal: '여덟', start: 1 })}${HT.cellRowHTML('leaders', { name: '나', ordinal: '8세', start: 2 })}</div><div data-cells="faiths">${HT.faithRowHTML({ name: '가 신앙', start: 1 })}${HT.faithRowHTML({ name: '나 신앙' })}</div>`);
  const pr = [];
  HT.readCellRows(bad, 'leaders', '지도자', pr);
  HT.readCellRows(bad, 'faiths', '종교', pr);
  assert.ok(pr.some(m => /지도자 1번째 줄: 이름 번호 "여덟"은\(는\) 양의 정수로/.test(m)) && pr.some(m => /지도자 2번째 줄: 대수 칸에 "8세"을\(를\) 적었습니다/.test(m)) && pr.some(m => /종교 2번째 줄: 시작이 없습니다/.test(m)), `폼이 막는 것: ${pr.join(' / ')}`);
  /* 5. 메이커 코드가 길을 씀: 폼의 종교 구역 · 이름 번호 칸 · 팩 정보의 표기 낱말 · 「문화권」 표의 낱말 열 · 편집 표의 안쪽 열쇠 칸 */
  const core = readFileSync(join(root, 'js/core.js'), 'utf8');
  const maker = readFileSync(join(root, 'js/maker.js'), 'utf8');
  const grid = readFileSync(join(root, 'js/maker-grid.js'), 'utf8');
  assert.ok(/data-cells="faiths"/.test(HT.periodFieldsHTML({ tracks: [] })) && /class="c-regnal"/.test(HT.cellRowHTML('leaders', {})) && /period\.faiths = HT\.readCellRows\(form, 'faiths'/.test(core) && /faithHost\.innerHTML/.test(core), '객체 폼의 종교 구역 · 지도자 줄의 이름 번호 칸 · 채우기 · 읽기');
  assert.ok(/\$\{leaderWordsHTML\(\)\}/.test(maker) && /leaderLabelCols\('이 문화권'\)/.test(maker) && /kit\.nestSet\(draft, \['leaderLabels'/.test(maker) && /c\.nest\) return HT\.makerKit\.nestGet/.test(grid) && /c\.nest\) \{ HT\.makerKit\.nestSet/.test(grid), '팩 정보 · 「문화권」 표 · 편집 표의 표기 낱말 칸');
  t.count += 12;
}

export async function checkFormat4(HT, { extra = [], writeExpected = false } = {}) {
  assert.ok(HT.F4 && typeof HT.F4.up === 'function' && typeof HT.F4.down === 'function' && typeof HT.F4.project === 'function', 'HT.F4가 없음');
  const t = kit(HT);
  unitKinds(HT, t);
  unitPartOf(HT, t);
  unitEras(HT, t);
  unitMore(HT, t);
  unitReview(HT, t);
  unitNew(HT, t);
  const rows = await corpus(HT, t, extra);
  await loading(HT, t);
  await unitSave(HT, t);
  unitObjects(HT, t);
  unitOffices(HT, t);
  unitPersons(HT, t);
  unitSpheres(HT, t);
  unitPreview(HT, t);
  unitResaveStable(HT, t);
  unitRegistry(HT, t);
  unitWorld(HT, t);
  await unitMakerWorld(HT, t);
  const legacy = legacyBundle(HT, t);
  const f4 = f4Bundle(HT, t, writeExpected);
  return { units: t.count, corpus: rows, legacy, f4 };
}

/* ⑯ 열고 저장해도 늘지 않음(2026-10-24 — 5단계 잔여 과제 2 걸음 0): 기간 있는 · 여러 그릇 듦(within)은 내림이 소속 줄로 내리고 extrasOf가 within을 잃은 칸으로
   모아 두는데, 올림이 그 소속 줄을 partOf로도 올려 열고 저장할 때마다 한 벌씩 늘었다. 메이커의 길(내림 → 정규화 → 올림 + extras) 세 바퀴가 같아야 하고, 이미 겹쳐
   저장된 파일은 한 바퀴에 풀려야 하며, 메이커에서 고친 줄(짝이 없는 within)은 되돌리지 않고 고친 소속 줄이 남는다. 이름은 가상 */
function unitResaveStable(HT, t) {
  const save = raw4 => {
    const ex = HT.F4.extrasOf(raw4);
    const r = HT.normalizePack(HT.F4.down(raw4));
    assert.ok(r.pack, '저장 길의 정규화');
    return HT.F4.toFile(HT.packToJSON(r.pack), ex);
  };
  const pack = objects => ({ format: HT.FORMAT, formatVersion: 4, id: 'f4-grow', name: '늘어남 시험', tracks: [{ id: 'ta', name: '가 줄' }], objects: [
    { id: 'big', type: 'realm', name: '큰 나라', track: 'ta', start: 100, end: 400 },
    { id: 'other', type: 'realm', name: '딴 나라', track: 'ta', start: 100, end: 400 },
    ...objects,
  ] });
  const W = [{ of: 'big', start: 150, end: 250 }, { of: 'other', start: 250, end: 350 }];
  const a = j => j.objects.find(o => o.id === 'a');
  /* 1. 세 바퀴 — within 그대로 · 소속 줄 없음 · 둘째와 셋째가 같음 */
  let j = pack([{ id: 'a', type: 'state', name: '갑 왕국', track: 'ta', start: 150, end: 350, within: W }]);
  const seen = [];
  for (let k = 0; k < 3; k++) { j = save(j); seen.push(JSON.stringify(j)); }
  t.same([a(j).within, a(j).partOf], [W, undefined], '기간 있는 그릇 듦 — 세 바퀴 저장해도 within 그대로 · 소속 줄이 생기지 않음');
  assert.equal(seen[1], seen[2], '둘째 · 셋째 저장이 같음');
  /* 2. 이미 겹쳐 저장된 파일(within + 같은 소속 줄 두 벌) — 한 바퀴에 풀림 · 관계 있는 섬김 줄은 남음 */
  const healed = save(pack([{ id: 'a', type: 'state', name: '갑 왕국', track: 'ta', start: 150, end: 350, within: W,
    partOf: [...W, ...W, { of: 'big', relation: 'tributary', start: 150, end: 200 }] }]));
  t.same([a(healed).within, a(healed).partOf], [W, [{ of: 'big', relation: 'tributary', start: 150, end: 200 }]], '겹친 소속 줄은 걷고 관계 있는 섬김 줄은 남음');
  /* 3. 메이커에서 그 줄을 고침(옛 꼴 작업본의 소속 줄 기간을 바꿈) — within은 되돌리지 않고 고친 소속 줄이 남음 */
  const raw4 = pack([{ id: 'a', type: 'state', name: '갑 왕국', track: 'ta', start: 150, end: 350, within: W }]);
  const ex = HT.F4.extrasOf(raw4);
  const draft = HT.F4.down(raw4);
  const p = draft.periods.find(x => x.id === 'a');
  p.partOf = p.partOf.map(r => (String(r.polity ?? r.of ?? '') === 'big' ? Object.assign({}, r, { end: 260 }) : r));
  const edited = HT.F4.toFile(HT.packToJSON(HT.normalizePack(draft).pack), ex);
  t.same([a(edited).within, (a(edited).partOf || []).map(r => [r.of, r.start, r.end])], [[W[1]], [['big', 150, 260]]], '고친 줄은 소속 줄로 · 고치지 않은 줄만 within으로 되돌림');
  t.count += 4;
}

/* ⑮ 문화권 단위 줄(5단계 과제 6) — 시대 구분의 문화권(epochs[].sphere) · 「주기」 표(yearCycles)를 정규화가 지키고 다리가 그대로 왕복 · 트랙 우선 경고 · 옛 열쇠 yearCycle 호환(저장 · 옛 형식 내보내기) ·
   정보 창의 간지 설정과 전체 줄의 맞춤(HT.syncYearCycles). 이름은 가상 */
function unitSpheres(HT, t) {
  const base = { format: HT.FORMAT, id: 'f4-sphere-unit', name: '문화권 줄 시험', spheres: [{ id: 'mist-sea', name: '안개 바다권', order: 1 }, { id: 'ash-field', name: '재 들판권', order: 2 }], tracks: [{ id: 'ta', name: '가 줄', sphere: 'mist-sea' }], periods: [P('가 나라')] };
  /* 1. 시대 구분의 문화권 왕복: 정규화가 지킴 → 올림(objects[].sphere) → 내림(epochs[].sphere) → 다시 정규화해도 같음 · 저장(toFile)에 실림 · extrasOf의 잃은 칸이 아님 */
  const r1 = HT.normalizePack(Object.assign({}, base, { epochs: [{ name: '안개 시대', sphere: 'mist-sea', start: 1, end: 300 }, { name: '전체 시대', start: 1, end: 500 }, { name: '나쁜 id', sphere: '안개?', start: 1, end: 9 }] }));
  assert.ok(r1.pack && !r1.errors.length, '문화권을 적은 시대 구분의 정규화');
  t.same(r1.pack.epochs.map(e => e.sphere ?? null), ['mist-sea', null, null], '정규화가 sphere를 지키고 틀린 id는 뺌');
  assert.ok(r1.warnings.some(w => /문화권 id "안개\?"/.test(w.msg)), '틀린 문화권 id 경고');
  const J1 = HT.packToJSON(r1.pack);
  const up1 = HT.F4.up(J1).json;
  assert.equal(up1.objects.find(o => o.name === '안개 시대').sphere, 'mist-sea', '올림이 시대 객체의 sphere를 실음');
  t.same(t.N(HT.F4.down(up1)).epochs.map(e => e.sphere ?? null), J1.epochs.map(e => e.sphere ?? null), '내림 → 정규화에서도 sphere 그대로');
  assert.equal(HT.F4.toFile(J1, null).objects.find(o => o.name === '안개 시대').sphere, 'mist-sea', '저장(toFile)에 sphere');
  const ex1 = HT.F4.extrasOf(up1);
  assert.ok(!Object.values(ex1.objects).some(l => 'sphere' in l) && !('yearCycles' in ex1.top), 'extrasOf가 sphere · yearCycles를 더는 잃은 칸으로 모으지 않음');
  t.count += 6;
  /* 2. 트랙 우선 경고: 둘 다 적으면 둘 다 지키고 경고 */
  const r2 = HT.normalizePack(Object.assign({}, base, { epochs: [{ name: '둘 다', track: 'ta', sphere: 'mist-sea', start: 1, end: 100 }] }));
  assert.equal(r2.pack.epochs[0].track, 'ta', '트랙 그대로');
  assert.equal(r2.pack.epochs[0].sphere, 'mist-sea', '문화권도 그대로(고칠 수 있게)');
  assert.ok(r2.warnings.some(w => w.kind === 'epochs' && /트랙이 우선/.test(w.msg)), '트랙 우선 경고');
  t.count += 3;
  /* 3. 주기 표 저장 왕복: 읽힌 줄만 지키고(겹친 문화권 · 빈 줄 · 원년 없는 연호 · 틀린 id는 경고하고 뺌) 저장 → 다시 열기 같음 */
  const cycles = [{ sphere: 'mist-sea', names: ['샘물', '숲길', '볕뉘'], start: 4, label: '세차' }, { sphere: 'ash-field', era: '재력', from: 300, step: 10, label: '재력 눈금' }, { names: ['가', '나'], start: 1 }];
  const r3 = HT.normalizePack(Object.assign({}, base, { yearCycles: cycles.concat([{ sphere: 'mist-sea', era: '겹침', from: 1 }, { sphere: 'ash-field' }, { era: '원년 없음' }, { sphere: 'bad id!', names: ['a', 'b'] }]) }));
  assert.ok(r3.pack && !r3.errors.length, '주기 표의 정규화');
  t.same(r3.pack.yearCycles, cycles, '정규화가 읽힌 줄만 지킴');
  assert.equal(r3.warnings.filter(w => w.kind === 'yearCycles').length, 4, '뺀 줄마다 경고');
  const J3 = HT.packToJSON(r3.pack);
  const file3 = HT.F4.toFile(J3, null);
  t.same(file3.yearCycles, cycles, '저장(toFile)에 주기 표 그대로');
  t.same(t.N(HT.F4.down(file3)).yearCycles, cycles, '다시 열어도(내림 → 정규화) 같음');
  t.count += 5;
  /* 4. 옛 열쇠 yearCycle 호환: 정규화는 지어 넣지 않고(옛 파일 그대로), 저장 · 옛 형식 내보내기는 전체 줄의 이름 돌림을 yearCycle로도 적음 · yearCycle이 따로 있으면 그것 */
  assert.equal(J3.yearCycle, undefined, '정규화는 yearCycle을 지어 넣지 않음');
  t.same(file3.yearCycle, { names: ['가', '나'], start: 1 }, '저장은 전체 줄을 옛 열쇠 yearCycle로도 적음');
  t.same(HT.F4.legacyFile(J3).yearCycle, { names: ['가', '나'], start: 1 }, '옛 형식(3) 내보내기도');
  t.same(HT.F4.toFile(Object.assign({}, J3, { yearCycle: { names: ['x', 'y'], start: 2 } }), null).yearCycle, { names: ['x', 'y'], start: 2 }, 'yearCycle이 있으면 그대로');
  const loss = HT.F4.lossOf(null, Object.assign({}, J3, { epochs: J1.epochs }));
  assert.ok(loss.some(l => /문화권별 주기 줄 2개/.test(l)) && loss.some(l => /시대 구분의 문화권 1개/.test(l)), `옛 형식 저장의 손실 목록: ${loss.join(' / ')}`);
  /* 메이커의 맞춤: 간지 설정 → 전체 줄 · 표 → 간지 설정 · 끔(false)은 그대로 · 빈 표는 열쇠를 지움 */
  const d = { yearCycle: { names: ['가', '나'], start: 1, label: '해' }, yearCycles: [{ sphere: 'mist-sea', names: ['a', 'b'], start: 1 }] };
  assert.ok(HT.syncYearCycles(d, 'cycle') && d.yearCycles.length === 2 && !d.yearCycles[0].sphere && d.yearCycles[0].label === '해', '간지 설정이 전체 줄로');
  assert.ok(!HT.syncYearCycles(d, 'cycle'), '다시 맞춰도 바뀌지 않음');
  d.yearCycles[0].names = ['갑', '을', '병'];
  assert.ok(HT.syncYearCycles(d, 'rows') && d.yearCycle.names.join() === '갑,을,병', '표의 전체 줄이 간지 설정으로');
  d.yearCycles.shift();
  assert.ok(HT.syncYearCycles(d, 'rows') && d.yearCycle === undefined, '전체 줄을 지우면 간지 설정도 없음');
  d.yearCycle = false;
  HT.syncYearCycles(d, 'cycle');
  assert.ok(d.yearCycle === false && d.yearCycles.length === 1, '끔은 그대로 · 문화권 줄은 남음');
  d.yearCycles = [];
  HT.syncYearCycles(d, 'rows');
  assert.equal(d.yearCycles, undefined, '빈 표는 열쇠를 지움');
  /* 메이커 코드가 길을 씀: 옛 형식 내보내기 · 「주기」 표 · 시대 구분 폼의 문화권 칸 · 간지 설정의 맞춤 · 편집 창이 폼에 문화권 사전을 넘김 */
  const maker = readFileSync(join(root, 'js/maker.js'), 'utf8');
  const viewer = readFileSync(join(root, 'js/viewer.js'), 'utf8');
  assert.ok(/HT\.F4\.legacyFile\(HT\.packToJSON\(pack\)\)/.test(maker) && /BASE_TABLES\.yearCycles = \{/.test(maker) && /<select name="sphere">/.test(maker) && /HT\.syncYearCycles\(draft, 'cycle'\)/.test(maker) && /spheres: m\.spheres \|\| \[\]/.test(viewer), '메이커의 옛 형식 내보내기 · 「주기」 표 · 시대 구분 폼의 문화권 칸 · 맞춤 · 편집 창의 문화권 사전');
  t.count += 12;
}

/* 혼자 돌릴 때: node scripts/check-format4.mjs [--extra=<.htpack 경로>] … [--write-expected] (dev-smoke와 같은 노드 바탕을 꾸리고 core · 기본팩을 읽음) */
if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
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
  ['js/calendar.js', 'js/core.js'].forEach(load);
  [...readFileSync(join(root, 'index.html'), 'utf8').matchAll(/<script src="(packs\/[^"]+)"/g)].forEach(m => load(m[1]));
  const extra = process.argv.filter(a => a.startsWith('--extra=')).map(a => a.slice(8));
  try {
    const r = await checkFormat4(g.HT, { extra, writeExpected: process.argv.includes('--write-expected') });
    console.log(`형식 4 검사 통과 — 단위 ${r.units} · 실제 팩 ${r.corpus.map(c => `${c.label}(${c.objects})`).join(' · ')} · 옛 파일 묶음 ${r.legacy.map(c => `${c.label}(판 ${c.formatVersion} · 객체 ${c.objects})`).join(' · ')} · 형식 4 가상 팩 ${r.f4.map(c => `${c.label}(띠 ${c.periods} · 알림 ${c.notes})`).join(' · ')}`);
  } catch (e) {
    console.error(`형식 4 검사 실패: ${e.stack || e}`);
    process.exit(1);
  }
}

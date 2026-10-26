import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 감독 고름 그림 넷 · 그릇 꼴 셋 · 칸 그림 셋 · 선 길 · 칸 층 가로선의 스위치(scene/paint/paint_pick.dart — 찍기 · 증명 전용
// `--paint-off=ink,tag,flaw,chain,folder,lid,cycle,legit,office,body,rows,pair,mend,people,haze|all` · `--paint-rows=a|b|c|off` · 기본이 끔인 `--paint-on=cross,route`)를 읽는 검사.
// 선 길 route는 0.1.1 다-1(감독 고름 2026-10-26)부터 기본 끔 · 짝 꼬리표 pair는 route에서 떼어 제 스위치(기본 켬).
// 선 길이 아닌 0.1.1 고침 mend도 route에서 떼어 제 스위치(기본 켬 — 감독 고름 2026-10-26 떼어서 살림) · 민족 머리 줄 people(기본 켬).
// 흐림 haze(감독 고름 다 2026-10-26 — 기본 켬 · 끄면 옛 꼴).
// 그림을 고치는 걸음이 스위치를 읽게 되면, 그 걸음의 그림 검사가 스위치를 끈 그림도 본다(여기는 명령줄 읽기만 —
// 가로선 꼴 고르기는 floor_rules_test.dart도 본다).

typedef Switches = ({
  bool ink,
  bool tag,
  bool flaw,
  bool chain,
  bool folder,
  bool lid,
  bool cycle,
  bool legit,
  bool office,
  bool body,
  bool route,
  FloorRule rows,
  bool pair,
  bool mend,
  bool people,
  bool haze,
});

Switches now() => (
  ink: PaintPick.ink,
  tag: PaintPick.tag,
  flaw: PaintPick.flaw,
  chain: PaintPick.chain,
  folder: PaintPick.folder,
  lid: PaintPick.lid,
  cycle: PaintPick.cycle,
  legit: PaintPick.legit,
  office: PaintPick.office,
  body: PaintPick.body,
  route: PaintPick.route,
  rows: PaintPick.rows,
  pair: PaintPick.pair,
  mend: PaintPick.mend,
  people: PaintPick.people,
  haze: PaintPick.haze,
);

/// 기본(모두 켬 · 가로선은 꼴 b — 감독 결정 2026-10-25 · 선 길 route만 끔 — 다-1).
const Switches allOn = (
  ink: true,
  tag: true,
  flaw: true,
  chain: true,
  folder: true,
  lid: true,
  cycle: true,
  legit: true,
  office: true,
  body: true,
  route: false,
  rows: FloorRule.b,
  pair: true,
  mend: true,
  people: true,
  haze: true,
);
const Switches allOff = (
  ink: false,
  tag: false,
  flaw: false,
  chain: false,
  folder: false,
  lid: false,
  cycle: false,
  legit: false,
  office: false,
  body: false,
  route: false,
  rows: FloorRule.off,
  pair: false,
  mend: false,
  people: false,
  haze: false,
);

/// [allOn]에서 [off]의 낱말만 끈 값(rows를 끄면 꼴 off).
Switches onBut(Set<String> off) => (
  ink: !off.contains('ink'),
  tag: !off.contains('tag'),
  flaw: !off.contains('flaw'),
  chain: !off.contains('chain'),
  folder: !off.contains('folder'),
  lid: !off.contains('lid'),
  cycle: !off.contains('cycle'),
  legit: !off.contains('legit'),
  office: !off.contains('office'),
  body: !off.contains('body'),
  route: false,
  rows: off.contains('rows') ? FloorRule.off : FloorRule.b,
  pair: !off.contains('pair'),
  mend: !off.contains('mend'),
  people: !off.contains('people'),
  haze: !off.contains('haze'),
);

void main() {
  tearDown(PaintPick.reset);

  test('기본은 모두 켬(가로선은 꼴 b — 감독 결정 2026-10-25) · 선 길 route만 끔(다-1)', () {
    expect(now(), allOn);
    expect(PaintPick.allOn, isTrue);
    expect(PaintPick.off, isEmpty);
    expect(PaintPick.on, isEmpty);
    expect(
      PaintPick.names,
      ['ink', 'tag', 'flaw', 'chain', 'folder', 'lid', 'cycle', 'legit', 'office', 'body', 'rows', 'pair', 'mend', 'people', 'haze'],
      reason: '합친 차례(먹 → 꼬리표 → 흠 → 사슬 → 폴더 → 뚜껑 → 주기 → 정통성 → 직위 줄 더 → 몸통 → 가로선 → 짝 꼬리표 → 0.1.1 고침 → 민족 머리 줄 → 흐림)',
    );
    expect((PaintPick.route, PaintPick.pair, PaintPick.mend), (false, true, true));
  });

  test('route(이어 주는 선의 새 길 — 가지 line-routing)는 기본 끔 · `--paint-on=route`로만 켜고 옛 `--paint-off=route` · all · reset이 끈다', () {
    expect(PaintPick.applyArguments(['--paint-on=route']), isEmpty);
    expect(PaintPick.route, isTrue);
    expect(PaintPick.on, ['route']);
    expect(PaintPick.off, isEmpty, reason: '켜도 끈 목록에는 들지 않는다');
    expect(PaintPick.pair, isTrue, reason: '짝 꼬리표는 따로');
    expect(PaintPick.applyArguments(['--paint-off=route']), isEmpty, reason: '옛 명령줄도 받는다');
    expect(PaintPick.route, isFalse);
    expect(now(), allOn);
    PaintPick.turnOn('route');
    PaintPick.reset();
    expect(PaintPick.route, isFalse);
    PaintPick.turnOn('route');
    PaintPick.turnOff('all');
    expect(PaintPick.route, isFalse);
  });

  test('pair(짝 꼬리표 — 구역 60)는 route와 따로 꺼진다', () {
    expect(PaintPick.applyArguments(['--paint-off=pair']), isEmpty);
    expect(now(), onBut({'pair'}));
    expect(PaintPick.off, ['pair']);
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-on=route', '--paint-off=pair']), isEmpty);
    expect((PaintPick.route, PaintPick.pair), (true, false));
  });

  test('mend(선 길이 아닌 0.1.1 고침 — 떼어서 살림)는 route 끔 기본에서 켬 · route와 따로 꺼진다', () {
    expect((PaintPick.route, PaintPick.mend), (false, true));
    expect(PaintPick.applyArguments(['--paint-off=mend']), isEmpty);
    expect(now(), onBut({'mend'}));
    expect(PaintPick.off, ['mend']);
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-on=route', '--paint-off=mend']), isEmpty);
    expect((PaintPick.route, PaintPick.mend), (true, false));
  });

  test('낱말마다 그 스위치만 끈다', () {
    for (final name in PaintPick.names) {
      PaintPick.reset();
      expect(PaintPick.applyArguments(['--paint-off=$name']), isEmpty);
      expect(PaintPick.off, [name], reason: name);
      expect(PaintPick.allOn, isFalse);
    }
  });

  // 합칠 때 지킴(과제 8 걸음 4 검토): 같은 바탕에서 이 파일을 고친 갈래 넷의 낱말이 다섯 자리(names · off · allOn · reset · 'all')에 모두 들었는가 —
  // 아래 두 시험은 [PaintPick.names]만 돌아 낱말 이름을 적지 않으므로, 합친 뒤 한 자리에서 빠진 낱말을 잡는다.
  test('names의 낱말을 하나씩 모두 끄면 off = names(차례대로) · 그 뒤 reset이면 모두 켬', () {
    final seen = <String>[];
    for (final name in PaintPick.names) {
      expect(PaintPick.turnOff(name), isTrue, reason: name);
      seen.add(name);
      expect(PaintPick.off, seen, reason: '$name까지 끈 목록');
      expect(PaintPick.allOn, isFalse, reason: name);
    }
    PaintPick.reset();
    expect(PaintPick.allOn, isTrue, reason: 'reset이 모든 낱말을 켠다');
    expect(PaintPick.off, isEmpty);
    // 낱말 하나씩 끄고 reset — 어느 낱말이든 reset이 되돌린다.
    for (final name in PaintPick.names) {
      PaintPick.turnOff(name);
      PaintPick.reset();
      expect(PaintPick.allOn, isTrue, reason: '$name을 끈 뒤 reset');
      expect(PaintPick.off, isEmpty, reason: '$name을 끈 뒤 reset');
    }
  });

  test("'all'이면 off가 names 전부 · 낱말은 겹치지 않음 · 알 수 없는 낱말이 아님", () {
    expect(PaintPick.names.toSet(), hasLength(PaintPick.names.length), reason: '낱말이 겹치지 않는다');
    expect(PaintPick.names, isNot(contains('all')));
    expect(PaintPick.applyArguments(['--paint-off=all']), isEmpty);
    expect(PaintPick.off, PaintPick.names);
    expect(PaintPick.allOn, isFalse);
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=${PaintPick.names.join(',')}']), isEmpty, reason: '모든 낱말을 turnOff가 안다');
    expect(PaintPick.off, PaintPick.names);
  });

  test('과제 8 갈래의 셋(folder · lid · cycle)은 저마다 제 스위치만', () {
    expect(PaintPick.applyArguments(['--paint-off=folder']), isEmpty);
    expect(now(), onBut({'folder'}));
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=lid']), isEmpty);
    expect(now(), onBut({'lid'}));
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=cycle']), isEmpty);
    expect(now(), onBut({'cycle'}));
  });

  test('쉼표로 여럿 · all은 모두', () {
    expect(PaintPick.applyArguments(['--paint-off=chain,ink']), isEmpty);
    expect(now(), onBut({'ink', 'chain'}));
    expect(PaintPick.off, ['ink', 'chain'], reason: '꺼 둔 목록은 늘 걸음 차례');
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=cycle,folder,lid']), isEmpty);
    expect(PaintPick.off, ['folder', 'lid', 'cycle'], reason: '꺼 둔 목록은 늘 걸음 차례');
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=body,legit,office']), isEmpty);
    expect(now(), onBut({'legit', 'office', 'body'}));
    expect(PaintPick.off, ['legit', 'office', 'body'], reason: '칸 그림 셋도 걸음 차례');
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=all']), isEmpty);
    expect(now(), allOff);
    expect(PaintPick.rows, FloorRule.off, reason: 'all은 가로선 꼴도 off');
    expect(PaintPick.route, isFalse, reason: 'all은 선 길도 끈다');
    expect(PaintPick.off, PaintPick.names);
  });

  test('빈칸 · 빈 낱말 · 대문자는 너그럽게 · 모르는 낱말은 돌려주고 무시', () {
    expect(PaintPick.applyArguments(['--paint-off= Ink , ,FLAW, Lid , Office ,']), isEmpty);
    expect(now(), onBut({'ink', 'flaw', 'lid', 'office'}));
    expect(PaintPick.rows, FloorRule.b, reason: '가로선 꼴은 그대로');
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off= ROWS ,']), isEmpty);
    expect(now(), onBut({'rows'}));
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-off=inks,tag,먹,folders,bodies']), ['inks', '먹', 'folders', 'bodies']);
    expect(PaintPick.off, ['tag'], reason: '아는 낱말만 끔');
  });

  test('다른 인자 · 값 없는 열쇠는 아무것도 끄지 않음 · 여러 번 적으면 합침', () {
    expect(PaintPick.applyArguments(['--db=x.db', '--paint-offset=ink', '--paint-off', '--paint-off=', 'paint-off=all', '--paint-rows', '--paint-rows=']), isEmpty);
    expect(PaintPick.allOn, isTrue);
    expect(PaintPick.rows, FloorRule.b);
    expect(
      PaintPick.applyArguments(['--paint-off=ink', '--capture-only=yes', '--paint-off=chain', '--paint-off=cycle', '--paint-off=legit']),
      isEmpty,
    );
    expect(PaintPick.off, ['ink', 'chain', 'cycle', 'legit']);
  });

  test('가로선 꼴: --paint-rows=a|b|c|off(뒤의 것) · 끔(--paint-off=rows · all)이 이김 · 모르는 값은 돌려주고 그대로', () {
    expect(PaintPick.applyArguments(['--paint-rows=c', '--paint-rows=A']), isEmpty);
    expect(PaintPick.rows, FloorRule.a, reason: '여럿이면 뒤의 것');
    expect(PaintPick.allOn, isTrue);
    expect(PaintPick.applyArguments(['--paint-off=rows', '--paint-rows=c']), isEmpty);
    expect(PaintPick.rows, FloorRule.off, reason: '꼴 고르기를 먼저 읽고 끄기를 나중에');
    expect(PaintPick.off, ['rows']);
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-rows=e']), ['e']);
    expect(PaintPick.rows, FloorRule.b);
    expect(PaintPick.applyArguments(['--paint-rows=off']), isEmpty);
    expect(PaintPick.off, ['rows'], reason: '꼴 off는 끈 것과 같다');
  });

  test('켜는 길은 reset뿐(명령줄은 끄기만 — 가로선 꼴만 고를 수 있음)', () {
    PaintPick.turnOff('all');
    expect(PaintPick.turnOff('ink'), isTrue, reason: '이미 꺼진 것을 또 꺼도 참');
    expect(PaintPick.turnOff('on'), isFalse);
    expect(PaintPick.allOn, isFalse);
    PaintPick.reset();
    expect(PaintPick.allOn, isTrue);
    expect(now(), allOn, reason: 'reset은 그릇 꼴 셋 · 칸 그림 셋도 켜고 가로선은 꼴 b로');
    expect(PaintPick.rows, FloorRule.b);
  });

  test('민족 머리 줄(0.1.1 감독 고름 나 — people)은 기본 켬 · --paint-off=people · all로 끄고 reset이 켠다 · 켜는 후보가 아니다', () {
    expect(PaintPick.people, isTrue);
    expect(PaintPick.applyArguments(['--paint-off=People']), isEmpty);
    expect(PaintPick.people, isFalse);
    expect(PaintPick.off, ['people']);
    expect(PaintPick.allOn, isFalse);
    PaintPick.reset();
    expect(PaintPick.people, isTrue);
    expect(PaintPick.applyArguments(['--paint-on=people-b']), ['people-b'], reason: '옛 후보 낱말은 없어졌다');
    expect(PaintPick.turnOff('all'), isTrue);
    expect(PaintPick.people, isFalse);
  });

  test('1배 후보 cross(이어 주는 선 걸음 5 — 건넘 토막)는 기본 끔 · `--paint-on`으로만 켜고 reset이 끈다 — 끄는 낱말과 따로', () {
    expect(PaintPick.cross, isFalse);
    expect(PaintPick.on, isEmpty);
    expect(PaintPick.candidates, ['cross', 'route']);
    expect(PaintPick.applyArguments(['--paint-on= CROSS ', '--paint-off=pair']), isEmpty);
    expect(PaintPick.cross, isTrue);
    expect(PaintPick.on, ['cross']);
    expect(PaintPick.off, ['pair'], reason: '끄기 · 켜기를 한 줄에 함께 읽는다');
    expect(PaintPick.applyArguments(['--paint-on=ink,빛']), ['ink', '빛'], reason: '켜는 열쇠는 후보만 — 끄는 낱말(names)은 모르는 낱말');
    expect(PaintPick.turnOff('all'), isTrue);
    expect(PaintPick.cross, isTrue, reason: 'all은 끄는 낱말(names)만 끈다');
    expect(PaintPick.off, PaintPick.names);
    PaintPick.reset();
    expect(PaintPick.cross, isFalse);
    expect(PaintPick.allOn, isTrue);
  });

  test('흐림(감독 고름 다 2026-10-26)은 기본 켬 · --paint-off=haze · all이 끄고 reset이 켬 · 옛 후보 낱말 haze-a · b · c는 모르는 낱말', () {
    expect(PaintPick.haze, isTrue);
    expect(PaintPick.applyArguments(['--paint-off=HAZE']), isEmpty);
    expect(PaintPick.haze, isFalse);
    expect(PaintPick.off, ['haze']);
    expect(now(), onBut({'haze'}));
    expect(PaintPick.applyArguments(['--paint-on=haze-c']), ['haze-c']);
    PaintPick.reset();
    expect(PaintPick.haze, isTrue);
    expect(PaintPick.turnOff('all'), isTrue);
    expect(PaintPick.haze, isFalse);
  });
}

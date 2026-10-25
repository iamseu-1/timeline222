import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 감독 고름 그림 넷 · 그릇 꼴 셋 · 칸 그림 셋 · 선 길 · 칸 층 가로선의 스위치(scene/paint/paint_pick.dart — 찍기 · 증명 전용
// `--paint-off=ink,tag,flaw,chain,folder,lid,cycle,legit,office,body,route,rows|all` · `--paint-rows=a|b|c|off` · 1배 후보 `--paint-on=cross`)를 읽는 검사.
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
);

/// 기본(모두 켬 · 가로선은 꼴 b — 감독 결정 2026-10-25).
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
  route: true,
  rows: FloorRule.b,
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
  route: !off.contains('route'),
  rows: off.contains('rows') ? FloorRule.off : FloorRule.b,
);

void main() {
  tearDown(PaintPick.reset);

  test('기본은 모두 켬(가로선은 꼴 b — 감독 결정 2026-10-25)', () {
    expect(now(), allOn);
    expect(PaintPick.allOn, isTrue);
    expect(PaintPick.off, isEmpty);
    expect(
      PaintPick.names,
      ['ink', 'tag', 'flaw', 'chain', 'folder', 'lid', 'cycle', 'legit', 'office', 'body', 'route', 'rows'],
      reason: '합친 차례(먹 → 꼬리표 → 흠 → 사슬 → 폴더 → 뚜껑 → 주기 → 정통성 → 직위 줄 더 → 몸통 → 선 길 → 가로선)',
    );
    expect(PaintPick.route, isTrue);
  });

  test('route(이어 주는 선의 새 길 — 가지 line-routing)는 혼자 꺼지고 all에도 든다', () {
    expect(PaintPick.applyArguments(['--paint-off=route']), isEmpty);
    expect(PaintPick.route, isFalse);
    expect(now(), onBut({'route'}), reason: '다른 낱말은 그대로 · 가로선은 꼴 b');
    expect(PaintPick.off, ['route']);
    PaintPick.reset();
    expect(PaintPick.route, isTrue);
    PaintPick.turnOff('all');
    expect(PaintPick.route, isFalse);
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

  test('1배 후보 cross(이어 주는 선 걸음 5 — 건넘 토막)는 기본 끔 · `--paint-on`으로만 켜고 reset이 끈다 — 끄는 낱말과 따로', () {
    expect(PaintPick.cross, isFalse);
    expect(PaintPick.on, isEmpty);
    expect(PaintPick.candidates, ['cross']);
    expect(PaintPick.applyArguments(['--paint-on= CROSS ', '--paint-off=route']), isEmpty);
    expect(PaintPick.cross, isTrue);
    expect(PaintPick.on, ['cross']);
    expect(PaintPick.off, ['route'], reason: '끄기 · 켜기를 한 줄에 함께 읽는다');
    expect(PaintPick.applyArguments(['--paint-on=ink,빛']), ['ink', '빛'], reason: '켜는 열쇠는 후보만 — 끄는 낱말(names)은 모르는 낱말');
    expect(PaintPick.turnOff('all'), isTrue);
    expect(PaintPick.cross, isTrue, reason: 'all은 끄는 낱말(names)만 끈다');
    expect(PaintPick.off, PaintPick.names);
    PaintPick.reset();
    expect(PaintPick.cross, isFalse);
    expect(PaintPick.allOn, isTrue);
  });
}

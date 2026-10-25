import 'package:archive_prototype/measure/scenarios.dart';
import 'package:flutter_test/flutter_test.dart';

/// 144Hz로 [seconds]초 동안 돌린 입력 기록. 장면은 입력이 있는 동안과 그 뒤 0.3초 동안 바쁘다고 친다.
List<String> play(Scenario scenario, double seconds) {
  final log = <String>[];
  double busyUntil = -1;
  for (double now = 0; now < seconds * 1000; now += 1000 / 144) {
    final inputs = scenario.step(now, now < busyUntil);
    if (inputs.isNotEmpty) busyUntil = now + 300;
    log.addAll(inputs.map((i) => '${now.toStringAsFixed(1)} $i'));
  }
  log.addAll(scenario.finish(seconds * 1000).map((i) => 'end $i'));
  return log;
}

Scenario make(String name) => scenarioFor(name, width: 1538, height: 846, packs: const [1, 2, 8], trackless: const [8]);

void main() {
  test('구간은 여섯: 끌기 · 확대 · 돋보기 · 밀집 · 세로 · 자료집', () {
    expect(sectionNames, ['끌기', '확대', '돋보기', '밀집', '세로', '자료집']);
    for (final name in sectionNames) {
      expect(make(name).name, name);
    }
  });

  test('같은 시각 · 같은 장면 상태를 넣으면 늘 같은 입력이 나온다(결정적)', () {
    for (final name in sectionNames) {
      expect(play(make(name), 6), play(make(name), 6), reason: name);
      expect(play(make(name), 6), isNotEmpty, reason: name);
    }
  });

  test('끌기: 0.2초 쉰 뒤에 누르고, 누른 장면에서 5px 문턱을 넘고, 1.26초 뒤에 달리던 속도로 놓고, 다음에는 반대쪽으로', () {
    final inputs = <(double, Synthetic)>[];
    final scenario = make('끌기');
    double busyUntil = -1;
    for (double now = 0; now < 6000; now += 1000 / 144) {
      for (final i in scenario.step(now, now < busyUntil)) {
        inputs.add((now, i));
        busyUntil = now + 300;
      }
    }
    final downs = inputs.where((e) => e.$2 is PointerDown).toList(), ups = inputs.where((e) => e.$2 is PointerUp).toList();
    expect(downs.length, greaterThanOrEqualTo(2));
    expect(downs.first.$1, closeTo(200, 8));
    final firstMove = inputs.firstWhere((e) => e.$2 is PointerMove);
    expect(firstMove.$1, downs.first.$1, reason: '누른 장면에서 바로 문턱을 넘는다');
    expect(((firstMove.$2 as PointerMove).x - (downs.first.$2 as PointerDown).x).abs(), greaterThan(5));
    expect(ups.first.$1 - downs.first.$1, closeTo(1260, 8));
    final lastBeforeUp = inputs.lastWhere((e) => e.$2 is PointerMove && e.$1 <= ups.first.$1).$2 as PointerMove;
    expect(lastBeforeUp.x, lessThan((downs.first.$2 as PointerDown).x), reason: '첫 번은 왼쪽으로');
    final secondMove = inputs.firstWhere((e) => e.$2 is PointerMove && e.$1 >= downs[1].$1).$2 as PointerMove;
    expect(secondMove.x, greaterThan((downs[1].$2 as PointerDown).x), reason: '다음에는 오른쪽으로');
    expect(inputs.every((e) => e.$2 is! PointerMove || (e.$2 as PointerMove).y == (downs.first.$2 as PointerDown).y), isTrue, reason: '옆으로만');
  });

  test('세로: 위아래로만 끈다', () {
    final moves = <PointerMove>[];
    final scenario = make('세로');
    for (double now = 0; now < 3000; now += 1000 / 144) {
      moves.addAll(scenario.step(now, false).whereType<PointerMove>());
    }
    expect(moves, isNotEmpty);
    expect(moves.map((m) => m.x).toSet().length, 1);
    expect(moves.map((m) => m.y).toSet().length, greaterThan(20));
  });

  test('확대: 80ms마다 한 칸, 12칸 확대 뒤 12칸 축소', () {
    final wheels = <Wheel>[];
    final scenario = make('확대');
    for (double now = 0; now < 1000 * 80 * 24 / 1000 + 1; now += 1000 / 144) {
      wheels.addAll(scenario.step(now, true).whereType<Wheel>());
    }
    expect(wheels.length, 24);
    expect(wheels.take(12).every((w) => w.dy == -100), isTrue);
    expect(wheels.skip(12).every((w) => w.dy == 100), isTrue);
  });

  test('돋보기: 집기 입력으로 50%에서 300%까지 오간다', () {
    final scales = <double>[];
    final scenario = make('돋보기');
    final first = scenario.step(0, false);
    expect(first.first, isA<PinchStart>());
    for (double now = 7; now < 6000; now += 1000 / 144) {
      scales.addAll(scenario.step(now, true).whereType<PinchUpdate>().map((p) => p.scale));
    }
    expect(scales.reduce((a, b) => a > b ? a : b), closeTo(3, .02));
    expect(scales.reduce((a, b) => a < b ? a : b), closeTo(.5, .02));
    expect(scenario.finish(6000).single, isA<PinchEnd>());
  });

  test('자료집: 0.7초마다 하나씩 끄고 켠다 — 트랙 없는 자료집도 차례에 든다', () {
    final toggles = <TogglePack>[];
    final scenario = make('자료집');
    for (double now = 0; now < 6000; now += 1000 / 144) {
      toggles.addAll(scenario.step(now, false).whereType<TogglePack>());
    }
    expect(toggles.length, 8);
    expect(toggles.take(4).map((t) => '${t.pack}${t.on ? '켬' : '끔'}'), ['2끔', '2켬', '8끔', '8켬'], reason: '맨 위 자료집은 그대로 두고, 트랙 있는 것과 없는 것을 번갈아');
    expect(scenario.finish(6000), isEmpty);
  });

  test('조감(기본 목록 밖): 0.9초마다 조감을 켜고 끄고, 켠 채로 끝나면 끝에서 끈다', () {
    expect(sectionNames, isNot(contains('조감')));
    final scenario = make('조감');
    var toggles = 0;
    for (double now = 0; now < 3000; now += 1000 / 144) {
      toggles += scenario.step(now, false).whereType<ToggleBird>().length;
    }
    expect(toggles, 3);
    expect(scenario.finish(3000).single, isA<ToggleBird>());
  });

  test('자료집을 끈 채로 끝나면 끝에서 다시 켠다', () {
    final scenario = make('자료집');
    for (double now = 0; now < 1000; now += 1000 / 144) {
      scenario.step(now, false);
    }
    final end = scenario.finish(1000);
    expect(end.single, isA<TogglePack>());
    expect((end.single as TogglePack).on, isTrue);
  });
}

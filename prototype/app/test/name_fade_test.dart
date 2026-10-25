import 'package:archive_prototype/scene/name_fade.dart';
import 'package:archive_prototype/motion.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

NameShown shown(int id, {int line = 0, double at = 1000, double dx = 9}) =>
    NameShown(eventId: id, title: '별여울 $id', importance: 2, at: at, row: 0, line: line, dx: dx);

double alphaAt(MotionToken token, double from, double to, double ms, [double velocity = 0]) => SpringSimulation(Motion.spring(token), from, to, velocity).x(ms / 1000);

void main() {
  test('새로 들어온 이름은 0.2초에 걸쳐 짙어진다', () {
    final fade = NameFade()..accept([shown(1)], now: 1000);
    expect(fade.alphaOf(1, 1000), 0);
    expect(fade.alphaOf(1, 1100), closeTo(alphaAt(MotionToken.enter, 0, 1, 100), 1e-9));
    expect(fade.animating(1100), isTrue);
    expect(fade.alphaOf(1, 1200), greaterThan(.98));
    expect(fade.alphaOf(1, 1400), 1);
    expect(fade.animating(1400), isFalse);
  });

  test('빠진 이름은 제자리에서 0.16초에 걸쳐 옅어지고 사라진다', () {
    final fade = NameFade()
      ..accept([shown(1), shown(2, line: 1)], now: 0)
      ..accept([shown(1)], now: 1000);
    expect(fade.alphaOf(1, 1000), 1, reason: '남은 이름은 그대로');
    final ghost = fade.ghosts(1000).single;
    expect(ghost.name.eventId, 2);
    expect(ghost.alphaAt(1000), 1);
    expect(ghost.alphaAt(1080), closeTo(alphaAt(MotionToken.exit, 1, 0, 80), 1e-9));
    expect(fade.animating(1080), isTrue);
    expect(fade.ghosts(1320), isEmpty);
    expect(fade.animating(1320), isFalse);
  });

  test('움직이는 중에도 나타남·사라짐 토큰을 함께 쓴다', () {
    final fade = NameFade()
      ..accept([shown(1)], now: 0)
      ..accept([shown(2)], now: 1000, moving: true);
    expect(fade.alphaOf(2, 1060), closeTo(alphaAt(MotionToken.enter, 0, 1, 60), 1e-9));
    expect(fade.ghosts(1060).single.alphaAt(1060), closeTo(alphaAt(MotionToken.exit, 1, 0, 60), 1e-9));
    expect(fade.animating(1120), isTrue);
    expect(fade.animating(1400), isFalse);
  });

  test('같은 이름이 다른 글줄로 옮기면 옛 자리에서 옅어지고 새 자리에서 짙어진다', () {
    final fade = NameFade()
      ..accept([shown(1, line: 0)], now: 0)
      ..accept([shown(1, line: 2)], now: 1000);
    expect(fade.alphaOf(1, 1000), 0);
    expect(fade.ghosts(1000).single.name.line, 0);
  });

  test('자리가 1px 안에서 같으면(단계가 바뀌어 분이 조금 달라져도) 그대로 둔다', () {
    final fade = NameFade()
      ..accept([shown(1, at: 1000)], now: 0)
      ..accept([shown(1, at: 1003)], now: 1000, minutesPerPx: 8);
    expect(fade.alphaOf(1, 1000), 1);
    expect(fade.ghosts(1000), isEmpty);
  });

  test('옅어지던 이름이 제자리로 돌아오면 그 짙기에서 이어 짙어진다', () {
    final fade = NameFade()
      ..accept([shown(1)], now: 0)
      ..accept([], now: 1000)
      ..accept([shown(1)], now: 1080);
    expect(fade.ghosts(1080), isEmpty, reason: '그림자와 새 이름이 겹쳐 보이지 않는다');
    final old = SpringSimulation(Motion.spring(MotionToken.exit), 1, 0, 0);
    final value = old.x(.08), velocity = old.dx(.08);
    expect(fade.alphaOf(1, 1080), closeTo(value, 1e-9));
    expect(fade.alphaOf(1, 1080.01), lessThan(value), reason: '옅어지던 속도에서 돌아서므로 처음 위치를 덮어쓰지 않는다');
    expect(fade.alphaOf(1, 1180), closeTo(alphaAt(MotionToken.enter, value, 1, 100, velocity), 1e-9));
  });

  test('움직임 줄이기 · 옅어짐을 못 하는 글자 방식에서는 바로 바뀐다', () {
    final instant = NameFade()
      ..accept([shown(1)], now: 0, instant: true)
      ..accept([shown(2)], now: 1000, instant: true);
    expect(instant.alphaOf(2, 1000), 1);
    expect(instant.ghosts(1000), isEmpty);
    expect(instant.animating(1000), isFalse);
    final off = NameFade()
      ..enabled = false
      ..accept([shown(1)], now: 0)
      ..accept([shown(2)], now: 1000);
    expect(off.alphaOf(2, 1000), 1);
    expect(off.ghosts(1000), isEmpty);
  });

  // 건의 8의 8번: 조감 등으로 크게 바뀌는 장면에서는 옛 이름 · 그림자를 남기지 않는다.
  test('거두기(cut): 그림자와 이름을 모두 치우고, 새 판이 올 때까지 이름을 그리지 않는다', () {
    final fade = NameFade()
      ..accept([shown(1), shown(2, line: 1)], now: 0)
      ..accept([shown(1)], now: 1000); // 2는 옅어지는 중
    expect(fade.ghosts(1040), isNotEmpty);
    fade.cut(1040);
    expect(fade.ghosts(1040), isEmpty, reason: '옅어지던 그림자도 바로 지운다');
    expect(fade.alphaOf(1, 1040), 0, reason: '옛 판의 이름은 새 판이 올 때까지 그리지 않는다');
    expect(fade.heldAt(1100), isTrue);
    expect(fade.animating(1100), isTrue, reason: '기다리는 동안에도 장면의 시계가 돈다');
    fade.accept([shown(1, line: 3), shown(3)], now: 1100);
    expect(fade.heldAt(1100), isFalse);
    expect(fade.ghosts(1100), isEmpty, reason: '거둔 뒤의 첫 판에는 빠지는 이름이 없다');
    expect(fade.alphaOf(1, 1100), 0);
    expect(fade.alphaOf(3, 1200), closeTo(alphaAt(MotionToken.enter, 0, 1, 100), 1e-9), reason: '새 이름은 지금의 등장 값으로 한 번에');
  });

  test('거둔 뒤 판이 끝내 오지 않아도 0.6초 뒤에는 다시 그린다', () {
    final fade = NameFade()..accept([shown(1)], now: 0);
    fade.cut(1000);
    expect(fade.alphaOf(1, 1599), 0);
    expect(fade.heldAt(1600), isFalse);
  });

  test('그림자 없이(ghosts: false): 빠지는 이름은 바로 지우고 옮긴 이름은 짙기 그대로 새 자리로', () {
    final fade = NameFade()
      ..accept([shown(1, line: 0), shown(2, line: 1)], now: 0)
      ..accept([shown(1, line: 2)], now: 1000, ghosts: false);
    expect(fade.ghosts(1000), isEmpty);
    expect(fade.alphaOf(1, 1000), 1, reason: '옮긴 이름이 0에서 다시 떠오르지 않는다');
  });

  test('비행 도착(dropGhosts)은 그림자만 거둔다', () {
    final fade = NameFade()
      ..accept([shown(1), shown(2, line: 1)], now: 0)
      ..accept([shown(1)], now: 1000)
      ..dropGhosts();
    expect(fade.ghosts(1000), isEmpty);
    expect(fade.alphaOf(1, 1000), 1);
  });
}

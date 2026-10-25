import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/motion_spring.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('여섯 이름의 식은 Flutter 스프링과 같은 값이다', () {
    expect(Motion.level, 2);
    expect(
      [for (final token in MotionToken.values) Motion.duration(token)],
      [180, 280, 400, 200, 160, 600],
    );
    expect(Motion.spring(MotionToken.pop).stiffness, closeTo(503.551, .001));
    expect(Motion.spring(MotionToken.pop).damping, closeTo(26.9279, .001));
    expect(Motion.spring(MotionToken.move).stiffness, closeTo(246.7401, .001));
    expect(Motion.spring(MotionToken.move).damping, closeTo(25.1327, .001));
    for (final token in MotionToken.values) {
      final spring = MotionSpring(0, token: token, epsilon: 1e-12)
        ..retarget(24);
      final oracle = SpringSimulation(Motion.spring(token), 0, 24, 0);
      for (var frame = 1; frame <= 12; frame++) {
        spring.step(10);
        expect(
          spring.value,
          closeTo(oracle.x(frame / 100), 1e-9),
          reason: '$token $frame 위치',
        );
        expect(
          spring.velocity,
          closeTo(oracle.dx(frame / 100), 1e-8),
          reason: '$token $frame 속도',
        );
      }
    }
  });

  test('재입력은 현재 위치와 속도를 함께 보존한다', () {
    final spring = MotionSpring(0, maxOvershoot: 6)..retarget(200);
    spring.step(90);
    final at = spring.value, speed = spring.velocity;
    spring.retarget(-80, token: MotionToken.snap);
    expect(spring.value, at);
    expect(spring.velocity, speed);
    spring.step(.01);
    expect((spring.value - at) / .00001, closeTo(speed, 2));
  });

  test('현재 위치가 새 목표여도 남은 속도는 넘침 상한을 따른다', () {
    final spring = MotionSpring(0, maxOvershoot: 6)..retarget(1000);
    spring.step(80);
    final at = spring.value, velocity = spring.velocity;
    spring.retarget(at);
    expect(spring.velocity, velocity);
    for (var i = 0; i < 200; i++) {
      spring.step(4);
      expect((spring.value - at).abs(), lessThanOrEqualTo(6));
    }
    expect(spring.value, at);
    expect(spring.active, isFalse);
  });

  test('정착한 뒤 반대 방향으로 놓아도 새 반응을 잃지 않는다', () {
    final spring = MotionSpring(0, token: MotionToken.pop, maxOvershoot: .02)
      ..retarget(1);
    for (var i = 0; i < 200; i++) {
      spring.step(5);
    }
    expect(spring.active, isFalse);
    spring.kick(-1.2);
    spring.step(10);
    expect(spring.value, lessThan(1));
    expect(spring.value, greaterThanOrEqualTo(.98));
    for (var i = 0; i < 200; i++) {
      spring.step(5);
    }
    expect(spring.value, 1);
    expect(spring.active, isFalse);
  });

  test('장면 간격이 달라도 같은 식이고 긴 장면에서도 유한하다', () {
    final one = MotionSpring(0, token: MotionToken.move)..retarget(100);
    final many = MotionSpring(0, token: MotionToken.move)..retarget(100);
    one.step(120);
    for (var i = 0; i < 12; i++) {
      many.step(10);
    }
    expect(many.value, closeTo(one.value, 1e-10));
    expect(many.velocity, closeTo(one.velocity, 1e-9));
    one.step(5000);
    expect(one.value, 100);
    expect(one.active, isFalse);
  });

  test('세기 2의 짧은 이동은 한 번만 넘치고 화면 상한을 지킨다', () {
    final spring = MotionSpring(
      0,
      token: MotionToken.pop,
      epsilon: .001,
      maxOvershoot: 6,
    )..retarget(64);
    var maximum = 0.0, crossings = 0, wasBeyond = false;
    for (var i = 0; i < 200; i++) {
      spring.step(5);
      if (spring.value > maximum) maximum = spring.value;
      final beyond = spring.value > 64;
      if (beyond && !wasBeyond) crossings++;
      wasBeyond = beyond;
    }
    expect(maximum, inInclusiveRange(66, 70));
    expect(crossings, 1);
    expect(spring.value, 64);
    expect(spring.active, isFalse);
  });

  test('큰 거리·크기나 빠른 놓음도 같은 상한을 넘지 않는다', () {
    final spring = MotionSpring(0, token: MotionToken.move, maxOvershoot: 6)
      ..retarget(3000);
    spring.kick(10000);
    for (var i = 0; i < 400; i++) {
      spring.step(4);
      expect(spring.value, lessThanOrEqualTo(3006));
    }
    expect(spring.active, isFalse);
  });

  test('bounce 0 토큰은 빠른 이전 속도를 받아도 목표를 넘지 않는다', () {
    for (final token in [
      MotionToken.snap,
      MotionToken.enter,
      MotionToken.exit,
      MotionToken.ring,
    ]) {
      final spring = MotionSpring(0, token: token)..retarget(10);
      spring.kick(10000);
      for (var i = 0; i < 400; i++) {
        spring.step(4);
        expect(spring.value, lessThanOrEqualTo(10));
      }
      expect(spring.value, 10);
      expect(spring.active, isFalse);
    }
  });

  test('나타남·사라짐·눌림·고리는 목표를 넘지 않는다', () {
    for (final token in [
      MotionToken.snap,
      MotionToken.enter,
      MotionToken.exit,
      MotionToken.ring,
    ]) {
      final spring = MotionSpring(0, token: token, maxOvershoot: 0)
        ..retarget(1);
      var before = 0.0;
      for (var i = 0; i < 300; i++) {
        spring.step(5);
        expect(spring.value, inInclusiveRange(before, 1));
        before = spring.value;
      }
      expect(spring.value, 1);
      expect(spring.active, isFalse);
    }
  });

  testWidgets('공통 장에서 여러 값과 예약이 함께 흐르고 끝나면 쉰다', (tester) async {
    final stage = MotionStage.instance;
    final a = MotionSpring(0, token: MotionToken.pop),
        b = MotionSpring(0, token: MotionToken.pop);
    var calls = 0, scheduled = false;
    void changed() => calls++;
    stage.attach(a, changed);
    stage.attach(b, changed);
    a.retarget(10);
    b.retarget(20);
    stage.schedule(40, () => scheduled = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(b.value, closeTo(a.value * 2, 1e-8));
    expect(scheduled, isTrue);
    expect(calls, 1, reason: '한 부품의 여러 값은 한 장면에 한 번만 알린다');
    await tester.pumpAndSettle();
    expect(a.active || b.active, isFalse);
    stage.detach(a);
    stage.detach(b);
  });
}

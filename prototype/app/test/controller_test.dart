import 'dart:math' as math;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

const year = 525960.0;

/// 1920×1080 창 · 자료 범위 기원전 1590년~2024년 무렵 · 몸통 높이 5,000px.
TimelineController make() {
  final c = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-1872000000, 28800000)
    ..setContentHeight(5000);
  c.showRange(-1500 * year, -500 * year); // 자료 범위 한가운데의 1,000년
  return c;
}

/// 멎을 때까지 장면을 돌린다(144Hz). 돌린 장면 수를 돌려준다.
int settle(TimelineController c, {int limit = 2000}) {
  int n = 0;
  while (c.active.value && n < limit) {
    c.tick(1000 / 144);
    n++;
  }
  return n;
}

void main() {
  test('휠 확대는 커서 아래의 시각을 붙잡고 목표를 쫓아간다', () {
    final c = make();
    const cursor = Offset(1200, 500);
    final under = c.view.minuteAt(1200);
    final before = c.view.span;
    c.wheel(cursor, -120); // 위로 한 칸 = 확대
    expect(c.active.value, isTrue);
    expect(c.view.span, before, reason: '입력한 장면에서는 아직 움직이지 않았다');
    c.tick(1000 / 144);
    expect(c.view.span, lessThan(before));
    expect(c.view.span, greaterThan(before * math.exp(-120 * .0018)), reason: '한 장면에 다 가지 않고 70ms 시정수로 쫓아간다');
    expect(c.view.minuteAt(1200), closeTo(under, .01 / c.view.ppm), reason: '쫓아가는 도중에도 커서 아래는 그대로');
    final frames = settle(c);
    expect(frames, greaterThan(10));
    expect(c.view.span, closeTo(before * math.exp(-120 * .0018), before * 1e-9));
    expect(c.view.minuteAt(1200), closeTo(under, .01 / c.view.ppm));
    expect(c.active.value, isFalse);
  });

  test('잘게 오는 휠 입력(트랙패드)은 25ms로 쫓아간다', () {
    // 10ms 뒤에 제 목표까지 간 몫: 시정수 70ms면 13%, 25ms면 33%. (기간은 로그로 재지 않고 선형으로 쫓는다)
    double done(double delta) {
      final c = make();
      final start = c.view.span, target = start * math.exp(delta * .0018);
      c.wheel(const Offset(1000, 500), delta);
      c.tick(10);
      return (c.view.span - start) / (target - start);
    }

    expect(done(-120), closeTo(1 - math.exp(-10 / 70), 1e-6));
    expect(done(-30), closeTo(1 - math.exp(-10 / 25), 1e-6));
  });

  test('확대와 축소에는 끝이 있다', () {
    final c = make();
    for (int i = 0; i < 400; i++) {
      c.wheel(const Offset(1000, 500), -120);
    }
    settle(c, limit: 20000);
    expect(c.view.span, closeTo(TimelineController.minSpan, 1e-6));
    for (int i = 0; i < 400; i++) {
      c.wheel(const Offset(1000, 500), 120);
    }
    settle(c, limit: 20000);
    expect(c.view.span, lessThanOrEqualTo((28800000 + 1872000000) * 1.05));
    expect(c.view.lo, lessThan(-1872000000));
    expect(c.view.hi, greaterThan(28800000));
  });

  test('끌기는 5px 문턱을 넘은 자리부터 손을 따라온다', () {
    final c = make();
    final lo = c.view.lo, top = c.view.top;
    c.pointerDown(const Offset(1000, 500), 0);
    c.pointerMove(const Offset(1003, 502), 8);
    expect(c.view.lo, lo, reason: '문턱 전에는 움직이지 않는다');
    expect(c.dragging, isFalse);
    c.pointerMove(const Offset(1006, 500), 16);
    expect(c.dragging, isTrue);
    expect(c.view.lo, lo, reason: '문턱을 넘는 순간 기준점을 다시 잡아 첫 장면에 튀지 않는다');
    c.pointerMove(const Offset(1106, 440), 24);
    expect(c.view.lo, closeTo(lo - 100 / c.view.ppm, 1e-6));
    expect(c.view.top, closeTo(top + 60, 1e-9), reason: '세로로는 줄이 움직인다');
    c.pointerUp(const Offset(1106, 440), 500);
    expect(c.dragging, isFalse);
  });

  test('놓으면 손의 속도를 이어받아 미끄러지고 250ms 뒤 속도는 1/e다', () {
    final c = make();
    c.pointerDown(const Offset(1000, 500), 0);
    // 1초에 1,200px(장면마다 10px)로 왼쪽으로 끈다.
    for (int i = 1; i <= 30; i++) {
      c.pointerMove(Offset(1000 - i * 10, 500), i * (1000 / 120));
    }
    final lo = c.view.lo;
    c.pointerUp(const Offset(700, 500), 30 * (1000 / 120));
    expect(c.active.value, isTrue);
    expect(c.velocity.dx, closeTo(-1200, 30));
    double t = 0;
    while (t < 250) {
      c.tick(1);
      t += 1;
    }
    expect(c.velocity.dx, closeTo(-1200 / math.e, 30));
    settle(c);
    // 미끄러진 거리 = 속도 × 시정수(−15px/s에서 멎으므로 조금 모자란다).
    expect((c.view.lo - lo) * c.view.ppm, closeTo(1200 * .25, 8));
    expect(c.active.value, isFalse);
  });

  test('느린 손짓이나 짧은 끌기에는 관성이 없다', () {
    final slow = make();
    slow.pointerDown(const Offset(1000, 500), 0);
    for (int i = 1; i <= 30; i++) {
      slow.pointerMove(Offset(1000 - i * .3, 500), i * (1000 / 120)); // 36px/s
    }
    slow.pointerUp(const Offset(991, 500), 250);
    expect(slow.active.value, isFalse);
    final short = make();
    short.pointerDown(const Offset(1000, 500), 0);
    short.pointerMove(const Offset(990, 500), 5);
    short.pointerMove(const Offset(984, 500), 10); // 빠르지만 문턱 뒤 6px뿐
    short.pointerUp(const Offset(984, 500), 12);
    expect(short.active.value, isFalse);
  });

  test('끝에서는 멎고 되튀지 않는다', () {
    final c = make();
    c.showRange(-1872000000, -1872000000 + 200 * year);
    c.pointerDown(const Offset(600, 500), 0);
    for (int i = 1; i <= 30; i++) {
      c.pointerMove(Offset(600.0 + i * 40, 500), i * (1000 / 120)); // 오른쪽으로 세게: 더 과거로
    }
    c.pointerUp(const Offset(1800, 500), 250);
    double least = c.view.lo;
    while (c.active.value) {
      c.tick(1000 / 144);
      expect(c.view.lo, lessThanOrEqualTo(least + 1e-6), reason: '한 번도 되돌아가지 않는다');
      least = math.min(least, c.view.lo);
    }
    expect(c.view.lo, closeTo(-1872000000 - c.view.span * TimelineController.edgeMargin, 1));
    expect(c.velocity, Offset.zero);
  });

  test('세로는 몸통 안에서만 움직인다', () {
    final c = make();
    c.pointerDown(const Offset(1000, 500), 0);
    c.pointerMove(const Offset(1000, 520), 8);
    c.pointerMove(const Offset(1000, 900), 16);
    expect(c.view.top, 0, reason: '맨 위에서 더 내려 끌 수 없다');
    c.pointerMove(const Offset(1000, -9000), 24);
    expect(c.view.top, 5000 - c.view.bodyHeight);
  });

  test('돋보기는 커서 아래의 시각과 줄을 제자리에 둔다', () {
    final c = make()..scrollTo(1200);
    const cursor = Offset(1400, 700);
    final minute = c.view.minuteAt(1400), bodyY = c.view.bodyYAt(700);
    final ppm = c.view.ppm;
    c.magnify(cursor, -240); // Ctrl + 휠 위로 = 크게
    settle(c);
    expect(c.view.mag, closeTo(math.exp(240 * .0018), 1e-9));
    // 해마다의 폭은 그대로 — 묶기(_bound)가 폭 ÷ 기간을 다시 나누어 끝자리 하나쯤은 흔들릴 수 있다(왼쪽 칸 240에서 1ulp).
    expect(c.view.ppm, closeTo(ppm, ppm * 1e-12), reason: '해마다의 폭은 그대로');
    expect(c.view.minuteAt(1400 / c.view.mag), closeTo(minute, .01 / ppm));
    expect(c.view.bodyYAt(700 / c.view.mag), closeTo(bodyY, .01));
  });

  test('돋보기는 50~300%이고 100% 가까이서 멎으면 100%가 된다', () {
    final c = make();
    c.magnify(const Offset(1000, 500), -4000);
    settle(c);
    expect(c.view.mag, 3);
    c.magnify(const Offset(1000, 500), 8000);
    settle(c);
    expect(c.view.mag, .5);
    c.magnifyTo(1.02, const Offset(1000, 500));
    settle(c);
    expect(c.view.mag, 1, reason: '±3% 안에서 멎으면 100%로');
    c.magnifyTo(1.2, const Offset(1000, 500));
    settle(c);
    expect(c.view.mag, closeTo(1.2, 1e-9));
  });

  test('누르면 움직임이 그 자리에서 멎는다', () {
    final c = make();
    c.wheel(const Offset(1200, 500), -480);
    c.tick(10);
    final span = c.view.span;
    c.pointerDown(const Offset(900, 400), 20);
    expect(c.active.value, isFalse);
    c.tick(10);
    expect(c.view.span, span);
  });

  test('손이 닿아 있는 동안은 pressed다 — 5px 문턱을 넘기 전에도(빈 줄 접기의 정착이 이걸 본다)', () {
    final c = make();
    expect(c.pressed, isFalse);
    c.pointerDown(const Offset(900, 400), 0);
    expect(c.pressed, isTrue);
    expect(c.dragging, isFalse, reason: '아직 문턱을 넘지 않았다');
    c.pointerMove(const Offset(902, 400), 10);
    expect(c.pressed, isTrue);
    c.pointerUp(const Offset(902, 400), 20);
    expect(c.pressed, isFalse);
    c.pointerDown(const Offset(900, 400), 30);
    c.pointerCancel();
    expect(c.pressed, isFalse);
  });

  test('멎어 있는 동안에는 장면을 만들지 않는다', () {
    final c = make();
    c.wheel(const Offset(1200, 500), -120);
    settle(c);
    int notified = 0;
    c.addListener(() => notified++);
    for (int i = 0; i < 144; i++) {
      c.tick(1000 / 144);
    }
    expect(notified, 0);
    expect(c.active.value, isFalse);
  });

  test('움직임 줄이기에서는 곧바로 목표에 가 있다', () {
    final c = make()..reduceMotion = true;
    final before = c.view.span;
    c.wheel(const Offset(1200, 500), -120);
    expect(c.view.span, closeTo(before * math.exp(-120 * .0018), before * 1e-9));
    expect(c.active.value, isFalse);
  });

  test('움직임 상수는 움직임 원칙의 값이다', () {
    expect((Motion.micro, Motion.out, Motion.enter, Motion.move), (120, 160, 200, 400));
    expect((Motion.chaseNotch, Motion.chaseFine), (70, 25));
    expect((Motion.coastTau, Motion.coastMin, Motion.coastRest, Motion.coastTravel, Motion.coastMax), (250, 50, 15, 20, 1.5));
    expect(Motion.dragThreshold, 5);
    expect(SceneView.gutter, 240); // 리메이크 2부 — 목업 GUT 240
  });
}

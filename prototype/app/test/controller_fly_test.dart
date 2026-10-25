import 'package:archive_prototype/controller.dart';
import 'package:flutter_test/flutter_test.dart';

const year = 525960.0;

TimelineController make() {
  final c = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-1872000000, 28800000)
    ..setContentHeight(5000);
  c.showRange(-1500 * year, -500 * year);
  return c;
}

int settle(TimelineController c, {int limit = 4000}) {
  int n = 0;
  while (c.active.value && n < limit) {
    c.tick(1000 / 144);
    n++;
  }
  return n;
}

void main() {
  test('멀리 가기: 물러났다 다가가 갈 곳에 정확히 서고, 도착을 한 번 알린다', () {
    final c = make();
    int arrived = 0;
    final from = c.view.span;
    c.flyTo(-3000 * year, -2900 * year, top: 1200, onArrive: () => arrived++);
    expect(c.flying, isTrue);
    expect(c.active.value, isTrue);
    double widest = 0;
    int n = 0;
    while (c.active.value && n++ < 4000) {
      c.tick(1000 / 144);
      if (c.view.span > widest) widest = c.view.span;
    }
    expect(arrived, 1);
    expect(c.flying, isFalse);
    expect(c.view.lo, closeTo(-3000 * year, 1));
    expect(c.view.span, closeTo(100 * year, 1));
    expect(c.view.top, closeTo(1200, .01));
    expect(widest, greaterThan(from), reason: '먼 곳이면 두 시점을 함께 볼 만큼 물러난다');
  });

  test('한 시점으로 가면 보던 폭 그대로 그 시점이 가운데에 온다', () {
    final c = make();
    final span = c.view.span;
    c.flyTo(-2000 * year, -2000 * year);
    settle(c);
    expect(c.view.span, closeTo(span, 1));
    expect(c.view.lo + c.view.span / 2, closeTo(-2000 * year, 2));
  });

  test('상세 창이 가린 폭을 빼고 담는다', () {
    final c = make();
    c.flyTo(-3000 * year, -2900 * year, insetRight: 392);
    settle(c);
    final free = c.view.plotWidth - 392;
    expect(c.view.xOf(-2900 * year) - c.view.left, closeTo(free, .5), reason: '기간의 끝이 가려지지 않은 부분의 오른쪽 끝에');
  });

  test('도중에 누르면 그 자리가 끝이고 도착을 알리지 않는다', () {
    final c = make();
    int arrived = 0;
    c.flyTo(-3000 * year, -2900 * year, onArrive: () => arrived++);
    for (int i = 0; i < 20; i++) {
      c.tick(1000 / 144);
    }
    final at = c.view.lo;
    c.pointerDown(const Offset(900, 500), 0);
    expect(c.flying, isFalse);
    c.tick(1000 / 144);
    expect(c.view.lo, at);
    expect(arrived, 0);
  });

  test('도중에 휠이 들어오면 비행은 끝나고 휠이 거기서 이어 간다', () {
    final c = make();
    c.flyTo(-3000 * year, -2900 * year);
    for (int i = 0; i < 20; i++) {
      c.tick(1000 / 144);
    }
    c.wheel(const Offset(900, 500), -120);
    expect(c.flying, isFalse);
    expect(c.active.value, isTrue);
    expect(settle(c), lessThan(2000));
  });

  test('움직임 줄이기면 바로 도착한다', () {
    final c = make()..reduceMotion = true;
    int arrived = 0;
    c.flyTo(-3000 * year, -2900 * year, onArrive: () => arrived++);
    expect(c.flying, isFalse);
    expect(arrived, 1);
    expect(c.view.lo, closeTo(-3000 * year, 1));
  });
}

import 'package:archive_prototype/mock/js.dart';
import 'package:flutter_test/flutter_test.dart';

// JS 도움 함수를 노드(V8)가 낸 값과 끝자리까지 견준다. 오른쪽 값은 모두 노드에서 그대로 옮겨 적은 것.
// kit_test는 색을 #rrggbb로 · 경로를 글로 견주므로 여기서 갈리는 끝자리를 보지 못한다 — 목업을 옮기는 다른 틀이 이 함수들에 기대므로 따로 못 박는다.

void main() {
  test('jsRound = Math.round', () {
    // (v + .5).floor()는 앞의 둘에서 틀린다(더하며 반올림됨): 1 · 4503599627370498.
    expect(jsRound(0.49999999999999994), 0);
    expect(jsRound(4503599627370497), 4503599627370497);
    expect(jsRound(-2.5), -2);
    expect(jsRound(2.5), 3);
    expect(jsRound(-0.5), 0);
    expect(jsRound(-2.4), -2);
    expect(jsRound(7.49), 7);
    expect(jsRound(-7.5), -7);
  });

  test('jsNum · jsStr = String(n)', () {
    expect(jsNum(1e21), '1e+21');
    expect(jsNum(-0.0), '0');
    expect(jsNum(0.1 + 0.2), '0.30000000000000004');
    expect(jsNum(1592), '1592');
    expect(jsNum(1592.0), '1592');
    expect(jsNum(1e-7), '1e-7');
    expect(jsNum(1.2345678901234568e20), '123456789012345680000');
    expect(jsNum(-7.5), '-7.5');
    expect(jsNum(0.000001), '0.000001');
    expect(jsNum(1e15), '1000000000000000');
    expect(jsNum(9007199254740994.0), '9007199254740994');
    expect(jsStr(1592.0), '1592');
    expect(jsStr('고려'), '고려');
    expect(jsStr(null), 'null');
  });

  test('jsTruthy · jsOr = JS의 참거짓 · ||', () {
    // JS: [0, '', NaN, null, false, -0, 'a', 1, ' ', 0.5].map(v => v || 'b') → b b b b b b a 1 ' ' 0.5
    final got = [for (final v in <Object?>[0, '', double.nan, null, false, -0.0, 'a', 1, ' ', 0.5]) jsOr(v, 'b')];
    expect(got, ['b', 'b', 'b', 'b', 'b', 'b', 'a', 1, ' ', 0.5]);
    expect(jsTruthy(true), true);
    expect(jsTruthy(const <int>[]), true);
  });

  test('jsMax · jsMin = Math.max · min(두 값) · jsSorted = 안정 정렬', () {
    // 형이 섞인 동적 값 — Dart의 max<T>는 T를 첫 값(int)에 맞춰 고르면 2.5에서 형 오류
    final dynamic two = 2, half = 2.5;
    expect(jsMax(two, half), 2.5);
    expect(jsMin(half, two), 2);
    expect(jsMax(-30, -30.5), -30);
    expect(jsMin(double.nan, 1).isNaN, true); // JS: Math.min(NaN, 1) → NaN
    // JS: [['a',1],['b',0],['c',1],['d',0],['e',.5]].sort((x, y) => x[1] - y[1]) → b d e a c (같은 값은 원래 차례)
    final items = [('a', 1), ('b', 0), ('c', 1), ('d', 0), ('e', .5)];
    expect(jsSorted(items, (x, y) => x.$2 - y.$2).map((x) => x.$1), ['b', 'd', 'e', 'a', 'c']);
    expect(items.first.$1, 'a', reason: '새 목록을 돌려주고 받은 목록은 그대로');
    // 같은 값이 많은 긴 목록도 차례를 지킨다(Dart의 sort는 32개를 넘으면 안정을 약속하지 않음)
    final many = [for (var i = 0; i < 200; i++) (i, i % 3)];
    expect(jsSorted(many, (x, y) => x.$2 - y.$2).map((x) => x.$1), [for (final r in [0, 1, 2]) for (var i = r; i < 200; i += 3) i]);
  });

  test('jsHypot = Math.hypot(끝자리까지)', () {
    // sqrt(x² + y²)는 앞의 넷에서 끝자리가 다르고(98.46008457789767 등) 마지막에서 무한이 된다.
    expect(jsHypot(-37.668291170926906, -90.96970976841156), 98.46008457789769);
    expect(jsHypot(3.498155671869485, -6.497622889698307), 7.379444174283319);
    expect(jsHypot(-23.471355030066967, -83.06399033547565), 86.3164584386978);
    expect(jsHypot(18.469143807175172, 10.899967193091275), 21.445711873952405);
    expect(jsHypot(-1e300, 1e300), 1.4142135623730952e300);
    expect(jsHypot(3, 4), 5);
    expect(jsHypot(0, 0), 0);
    expect(jsHypot(double.infinity, double.nan), double.infinity);
    expect(jsHypot(double.nan, 1).isNaN, true);
  });

  test('jsCbrt = Math.cbrt(끝자리까지)', () {
    // pow(v, 1/3)은 앞의 넷에서 끝자리가 다르다(V8 기준 0.2348014420060448 등).
    expect(jsCbrt(0.012945006691343524), 0.23480144200604477);
    expect(jsCbrt(0.0000015664727394650834), 0.011613798333152103);
    expect(jsCbrt(0.007201197908244309), 0.1931085852874017);
    expect(jsCbrt(0.0000024763391764236627), 0.013529135386240267);
    expect(jsCbrt(-27), -3);
    expect(jsCbrt(0.001), 0.1);
    expect(jsCbrt(1e300), 1e100);
    expect(jsCbrt(5e-324), 1.7031839360032603e-108);
    expect(jsCbrt(-1e-310), -4.641588833612774e-104);
    expect(jsCbrt(0), 0);
  });
}

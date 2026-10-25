import 'dart:math' as math;
import 'dart:typed_data';

// 자바스크립트 목업을 줄 그대로 옮길 때의 도움. Dart의 같은 이름 연산이 JS와 다르게 셈하는 곳만 모았다.
// 끝자리 하나까지 V8과 같게 옮긴 것: Math.round · String(n) · Math.hypot · Math.cbrt(test/mock/js_test.dart가 노드의 값으로 지킨다).
// 참거짓(jsTruthy · jsOr)은 JS의 규칙 그대로. Math.max · min과 sort(안정 정렬)는 형 · 차례가 JS와 같게.
// pow(**)는 옮기지 않았다 — Dart의 pow를 쓰는 곳(kit.dart의 색 셈)에 까닭을 적었다.

/// JS `Math.round` — .5는 늘 위로(−2.5 → −2). Dart의 round()는 0에서 멀리(−2.5 → −3).
/// `(v + .5).floor()`는 0.49999999999999994에서 1이 되므로(더하며 반올림됨) 바닥과의 차로 견준다.
double jsRound(num v) {
  final f = v.floorToDouble();
  return v - f >= .5 ? f + 1 : f;
}

/// JS `String(n)` · 템플릿 글의 수처럼: 정수 값은 소수점 없이, −0은 '0'.
/// Dart의 double.toString()은 JS와 같은 가장 짧은 꼴이되 정수 값에만 '.0'을 붙인다.
String jsNum(num v) {
  if (v == 0) return '0';
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// JS `String(v)` — 수는 [jsNum]으로, 그 밖은 Dart의 글로.
String jsStr(Object? v) => v is num ? jsNum(v) : '$v';

/// JS의 참거짓 — null · false · 0 · NaN · 빈 글이 거짓.
bool jsTruthy(Object? v) => !(v == null || v == false || v == '' || (v is num && (v == 0 || v.isNaN)));

/// JS `a || b` — a가 거짓([jsTruthy])이면 b.
T jsOr<T>(T? a, T b) => jsTruthy(a) ? a as T : b;

/// JS `Math.max` · `Math.min`(두 값) — 동적 값이 섞여도 두 값을 num으로 견준다(Dart의 max는 형을 첫 값에 맞춰 고를 수 있어서).
num jsMax(num a, num b) => math.max(a, b);
num jsMin(num a, num b) => math.min(a, b);

/// JS `Array.prototype.sort(cmp)`처럼 안정 정렬 — 같은 값은 원래 차례를 지킨다(Dart의 sort는 안정을 약속하지 않음).
/// JS는 제자리에서 고치지만 이것은 새 목록을 돌려준다(옮긴 곳은 돌려받은 목록만 쓴다 — 나무 대조로 확인).
List<T> jsSorted<T>(List<T> a, num Function(T x, T y) cmp) {
  final ix = [for (var i = 0; i < a.length; i++) i]
    ..sort((i, j) {
      final d = cmp(a[i], a[j]);
      return d < 0 ? -1 : (d > 0 ? 1 : i - j);
    });
  return [for (final i in ix) a[i]];
}

/// JS `Math.hypot(x, y)` — V8처럼 가장 큰 값으로 나눠 제곱을 카핸 합으로 더한다(sqrt(x² + y²)는 셋에 하나꼴로 끝자리가 다름).
double jsHypot(num x, num y) {
  final ax = x.abs().toDouble(), ay = y.abs().toDouble();
  if (ax == double.infinity || ay == double.infinity) return double.infinity;
  if (ax.isNaN || ay.isNaN) return double.nan;
  final max = math.max(ax, ay);
  if (max == 0) return 0;
  var sum = 0.0, comp = 0.0;
  for (final v in [ax, ay]) {
    final n = v / max;
    final summand = n * n - comp;
    final pre = sum + summand;
    comp = (pre - sum) - summand;
    sum = pre;
  }
  return math.sqrt(sum) * max;
}

/// JS `Math.cbrt` — Dart에는 없고 pow(v, 1/3)은 셋에 하나꼴로 끝자리가 다르므로(1/3이 정확히 1/3이 아님),
/// V8이 쓰는 fdlibm(FreeBSD s_cbrt.c)의 셈을 그대로 옮겼다: 비트로 어림 → 다항식으로 23비트 → 뉴턴 한 걸음.
/// 옮긴 원본의 고지(V8 ieee754.cc 판의 머리 글과 함께 저장소 뿌리 THIRD_PARTY_NOTICES.md 2-2절에도 있음):
///
/// ====================================================
/// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
///
/// Developed at SunPro, a Sun Microsystems, Inc. business.
/// Permission to use, copy, modify, and distribute this
/// software is freely granted, provided that this notice
/// is preserved.
/// ====================================================
///
/// Optimized by Bruce D. Evans.
double jsCbrt(num v) {
  final x = v.toDouble();
  final bd = ByteData(8);
  int hi(double d) => (bd..setFloat64(0, d)).getUint32(0);
  double words(int h, int l) => (bd
        ..setUint32(0, h)
        ..setUint32(4, l))
      .getFloat64(0);
  var hx = hi(x);
  final low = (bd..setFloat64(0, x)).getUint32(4);
  final sign = hx & 0x80000000;
  hx ^= sign;
  if (hx >= 0x7ff00000) return x + x; // NaN · 무한은 그대로
  double t;
  if (hx < 0x00100000) {
    if ((hx | low) == 0) return x; // ±0은 그대로
    t = words(0x43500000, 0) * x; // 정규화되지 않은 수는 2⁵⁴를 곱해 올린다
    t = words(sign | ((hi(t) & 0x7fffffff) ~/ 3 + 696219795), 0);
  } else {
    t = words(sign | (hx ~/ 3 + 715094163), 0);
  }
  var r = (t * t) * (t / x);
  t = t * ((1.87595182427177009643 + r * (-1.88497979543377169875 + r * 1.621429720105354466140)) + ((r * r) * r) * (-0.758397934778766047437 + r * 0.145996192886612446982));
  // 0에서 멀어지는 쪽으로 23비트에 자른다(아래 32비트 중 위 2비트만 남김).
  bd.setFloat64(0, t);
  var h = bd.getUint32(0), l = bd.getUint32(4) + 0x80000000;
  if (l > 0xffffffff) h += 1;
  t = words(h & 0xffffffff, l & 0xc0000000);
  final s = t * t;
  r = x / s;
  final w = t + t;
  r = (r - t) / (w + r);
  return t + t * r;
}

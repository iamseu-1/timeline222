import 'dart:math' as math;

// 지금 연표의 색은 거의 모두 css의 color-mix로 제 색(--c)에서 끌어낸다: 바탕은 `in srgb`로 종이와, 테두리는 `in oklab`으로 글자색과 섞는다.
// 같은 식을 그대로 옮겨, 어떤 색의 띠가 와도 지금 연표와 같은 바탕 · 테두리 · 글자색이 나오게 한다(값의 대조는 test/color_mix_test.dart — 기준 덤프에서 읽은 색).
// 색은 0xAARRGGBB. 섞은 결과는 장면마다 다시 셈하지 않게 보관한다.

/// `color-mix(in srgb, a t, b)`: 감마 값 그대로 섞는다. 투명도가 다르면 미리 곱해 섞고 되돌린다(css와 같은 규칙).
int mixSrgb(int a, int b, double t) {
  final key = _Key(a, b, t, 0);
  return _memo[key] ??= _mix(a, b, t, (v) => v, (v) => v);
}

/// `color-mix(in oklab, a t, b)`: sRGB → 선형 → OKLab에서 섞고 되돌린다.
int mixOklab(int a, int b, double t) {
  final key = _Key(a, b, t, 1);
  return _memo[key] ??= _mixLab(a, b, t);
}

/// 투명도만 곱한다(`color-mix(in srgb, a t, transparent)`와 같다).
int withAlpha(int argb, double alpha) => ((((argb >> 24) & 0xff) * alpha).round().clamp(0, 255) << 24) | (argb & 0x00ffffff);

/// 불투명한 바탕 위에 반투명한 색을 얹은 결과(그림판 없이 미리 셈할 때).
int over(int top, int bottom) {
  final a = ((top >> 24) & 0xff) / 255;
  int channel(int shift) => (((top >> shift) & 0xff) * a + ((bottom >> shift) & 0xff) * (1 - a)).round().clamp(0, 255);
  return 0xff000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
}

final _memo = <_Key, int>{};

class _Key {
  const _Key(this.a, this.b, this.t, this.space);
  final int a, b, space;
  final double t;
  @override
  bool operator ==(Object other) => other is _Key && other.a == a && other.b == b && other.t == t && other.space == space;
  @override
  int get hashCode => Object.hash(a, b, t, space);
}

int _mix(int a, int b, double t, double Function(double) encode, double Function(double) decode) {
  final aa = ((a >> 24) & 0xff) / 255, ab = ((b >> 24) & 0xff) / 255;
  final alpha = aa * t + ab * (1 - t);
  if (alpha <= 0) return 0;
  int channel(int shift) {
    final va = encode(((a >> shift) & 0xff) / 255) * aa, vb = encode(((b >> shift) & 0xff) / 255) * ab;
    return (decode((va * t + vb * (1 - t)) / alpha) * 255).round().clamp(0, 255);
  }

  return (alpha * 255).round().clamp(0, 255) << 24 | channel(16) << 16 | channel(8) << 8 | channel(0);
}

double _toLinear(double v) => v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
double _toGamma(double v) => v <= .0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - .055;
double _cbrt(double v) => v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();

(double, double, double) _toLab(int argb) {
  final r = _toLinear(((argb >> 16) & 0xff) / 255), g = _toLinear(((argb >> 8) & 0xff) / 255), b = _toLinear((argb & 0xff) / 255);
  final l = _cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
  final m = _cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
  final s = _cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
  return (.2104542553 * l + .7936177850 * m - .0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + .4505937099 * s, .0259040371 * l + .7827717662 * m - .8086757660 * s);
}

int _mixLab(int a, int b, double t) {
  final aa = ((a >> 24) & 0xff) / 255, ab = ((b >> 24) & 0xff) / 255;
  final alpha = aa * t + ab * (1 - t);
  if (alpha <= 0) return 0;
  final la = _toLab(a), lb = _toLab(b);
  double lerp(double x, double y) => (x * aa * t + y * ab * (1 - t)) / alpha;
  final bigL = lerp(la.$1, lb.$1), bigA = lerp(la.$2, lb.$2), bigB = lerp(la.$3, lb.$3);
  final l = math.pow(bigL + .3963377774 * bigA + .2158037573 * bigB, 3).toDouble();
  final m = math.pow(bigL - .1055613458 * bigA - .0638541728 * bigB, 3).toDouble();
  final s = math.pow(bigL - .0894841775 * bigA - 1.2914855480 * bigB, 3).toDouble();
  int channel(double linear) => (_toGamma(linear.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);
  return (alpha * 255).round().clamp(0, 255) << 24 |
      channel(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s) << 16 |
      channel(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s) << 8 |
      channel(-.0041960863 * l - .7034186147 * m + 1.7076147010 * s);
}

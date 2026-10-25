import 'dart:math' as math;

import '../motion.dart';
import '../motion_spring.dart';

// 멀리 가기의 길 — 검색 · 가장자리 안내 · 상세 창의 '이 위치로'가 먼 곳으로 갈 때의 한 번의 비행.
// 지금 연표의 js/timeline.js `zoomPath`(1168줄) · `_animateTo`(4396줄) · `focusOn`(2472줄)을 순수 계산으로 옮겼다.
// 조종부(TimelineController)도 화면도 모른다: 떠날 곳 · 갈 곳 · 그림 영역의 폭만 받아 길이(ms)와 장면마다의 보기를 돌려준다.
// 값의 근거는 docs/명세-3단계/06-상세-검색-필터-도구.md 5-3절과 docs/움직임-원칙.md의 '멀리 가기'.

/// 상세 창처럼 연표의 오른쪽을 가리는 것을 갈 곳의 셈에 어떻게 넣는가(지금 연표 `setView`의 `inset`).
enum FlyInset {
  /// 가리는 것을 셈하지 않는다.
  none,

  /// 갈 곳을 가려지지 않은 부분에 꼭 담는다 — 그만큼 폭이 넓어진다. 기간이 있는 항목(`focusOn`의 `inset: true`).
  fit,

  /// 폭은 그대로 두고 갈 곳의 가운데만 가려지지 않은 부분의 가운데로. 한 시점(`focusOn`의 `inset: 'center'`).
  center,
}

/// 한 번의 멀리 가기. [Fly.plan]으로 미리 길을 짜 두고, 장면마다 [at]에 떠난 뒤로 흐른 시간(ms)을 준다.
///
/// - **길**: van Wijk & Nuij(2003)의 매끄러운 확대·이동(ρ = √2). 두 시점을 함께 볼 만큼 물러났다가 다가간다.
///   갈 곳이 같은 화면 안이면 물러나지 않고 미끄러진다 — 폭이 같을 때 길 위의 가장 넓은 폭은 `√(폭² + 거리²)`이라,
///   거리가 화면의 4분의 1이면 3%, 절반이면 12%만 넓어지고 거리가 화면의 스무 배면 스무 배로 물러난다.
/// - **시간**: 공통 move 스프링. 그림판은 목표에 닿으면 멎어 확대·이동이 되튀지 않는다.
/// - **세로**: 실린 세로 이동([toTop])은 **같은 진행값**으로 나아간다 — 대각선 한 번, 같은 장면에 도착한다.
/// - **도착**: 상세 창이 가린 폭([insetRight])을 뺀 부분의 가운데에 선다.
/// - **멈춤**: 도중에 누르면 [stop] — 그 자리가 끝이다(도착 표시도 하지 않는다).
/// - **움직임 줄이기**([reduceMotion]): 길이 1ms, 처음부터 갈 곳에 서 있다.
class Fly {
  /// 떠날 곳과 갈 곳으로 길을 짠다.
  ///
  /// [fromLo] · [toLo]는 그림 영역 왼쪽 끝의 시각(분), [fromSpan] · [toSpan]은 그림 영역에 담기는 기간(분)이다
  /// (`SceneView.lo` · `SceneView.span`).
  /// [fromTop] · [toTop]은 이 비행에 실어 함께 옮길 세로 자리(배치 px). [toTop]이 없으면 세로는 움직이지 않는다.
  /// [plotWidth]와 [insetRight]는 같은 단위의 배치 px다([SceneView.plotWidth] · 상세 창이 가린 폭 — 열려 있으면 [detailInset]).
  /// [bound]는 갈 곳을 자료의 범위 안으로 가두는 조종부의 규칙이다(폭의 최소·최대 · 끝의 여백).
  /// 가리는 폭을 뺀 **뒤에** 부르며(지금 연표의 `_insetView` → `_clampView` 차례), 길 도중의 장면은 가두지 않는다
  /// — 물러나는 동안 자료 밖이 보이는 것이 이 움직임의 뜻이다.
  Fly.plan({
    required this.fromLo,
    required this.fromSpan,
    this.fromTop = 0,
    required double toLo,
    required double toSpan,
    double? toTop,
    required double plotWidth,
    double insetRight = 0,
    FlyInset inset = FlyInset.fit,
    this.reduceMotion = false,
    (double, double) Function(double lo, double span)? bound,
  }) {
    var lo = toLo;
    var span = math.max(toSpan, _tiny);
    // 상세 창이 가린 폭: 가리는 것이 그림 영역의 절반을 넘으면(창이 화면을 다 덮을 때) 평소대로 간다.
    if (inset != FlyInset.none && insetRight > 0 && insetRight <= plotWidth / 2 && plotWidth > 0) {
      if (inset == FlyInset.fit) {
        span = span * plotWidth / (plotWidth - insetRight); // [lo, lo+span]이 가려지지 않은 부분에 꼭 담긴다
      } else {
        lo += span * insetRight / (2 * plotWidth); // 폭은 그대로, 가운데만 가려지지 않은 부분의 가운데로
      }
    }
    if (bound != null) {
      final b = bound(lo, span);
      lo = b.$1;
      span = math.max(b.$2, _tiny);
    }
    this.toLo = lo;
    this.toSpan = span;
    this.toTop = toTop ?? fromTop;

    final w0 = math.max(fromSpan, _tiny);
    final w1 = span;
    final u0 = fromLo + w0 / 2;
    final u1 = lo + w1 / 2;
    final d = u1 - u0;
    final ad = d.abs();
    _u0 = u0;
    _w0 = w0;
    _d = d;
    if (ad < 1e-9 * math.max(w0, w1)) {
      // 가운데가 거의 같다: 제자리에서 폭만 로그 눈금으로 고르게.
      _zoomOnly = true;
      _s = math.log(w1 / w0) / _rho;
      _r0 = 0;
      _ch0 = 1;
      _sh0 = 0;
    } else {
      _zoomOnly = false;
      final b0 = (w1 * w1 - w0 * w0 + _rho4 * ad * ad) / (2 * w0 * _rho2 * ad);
      final b1 = (w1 * w1 - w0 * w0 - _rho4 * ad * ad) / (2 * w1 * _rho2 * ad);
      final r0 = -_asinh(b0);
      final r1 = -_asinh(b1);
      _r0 = r0;
      _s = (r1 - r0) / _rho;
      _ch0 = _cosh(r0);
      _sh0 = _sinh(r0);
    }
    pathLength = _s.abs();
    durationMs = reduceMotion ? 1 : Motion.move;
    _frame = (fromLo, fromSpan, fromTop);
  }

  /// 상세 칸이 열렸을 때 가리는 폭(배치 px) — 앱 틀의 `Ui.detailCover`(오른쪽에 붙은 칸 380)와 같은 값이다.
  /// `lib/scene`은 앱 틀을 모르므로 여기에 같은 수를 둔다.
  static const detailInset = 380.0;


  static const _tiny = 1e-9;
  static const _rho = math.sqrt2;
  static const _rho2 = 2.0, _rho4 = 4.0;

  /// 떠난 곳: 그림 영역 왼쪽 끝의 시각(분) · 담기는 기간(분) · 세로 자리(배치 px).
  final double fromLo, fromSpan, fromTop;

  /// 갈 곳 — 가리는 폭을 빼고 [Fly.plan]의 `bound`로 가둔 **마지막** 값이다.
  late final double toLo, toSpan, toTop;

  /// 움직임 줄이기면 참(길이 1ms · 처음부터 갈 곳).
  final bool reduceMotion;

  /// 이 비행의 길이(ms).
  late final double durationMs;

  /// van Wijk 길의 길이 S. 공간의 경로만 정하며 공통 스프링의 시간은 바꾸지 않는다.
  late final double pathLength;

  late final bool _zoomOnly;
  late final double _u0, _w0, _d, _s, _r0, _ch0, _sh0;
  late (double, double, double) _frame;
  double _elapsed = 0;
  bool _stopped = false;

  /// 떠난 뒤로 [elapsedMs]가 흐른 장면의 보기: `(lo, span, top)`.
  /// `lo` = 그림 영역 왼쪽 끝의 시각(분) · `span` = 담기는 기간(분) · `top` = 세로 자리(배치 px).
  /// 처음(0 이하)과 끝(길이 이상)은 떠난 곳 · 갈 곳과 정확히 같다.
  (double lo, double span, double top) at(double elapsedMs) {
    if (_stopped) return _frame;
    if (reduceMotion || !(elapsedMs < durationMs)) {
      // 도착(길이에 닿았거나 값이 없는 시간) — 갈 곳에 정확히 선다.
      _elapsed = durationMs;
      return _frame = (toLo, toSpan, toTop);
    }
    if (elapsedMs <= 0) {
      _elapsed = 0;
      return _frame = (fromLo, fromSpan, fromTop);
    }
    _elapsed = elapsedMs;
    final p = (1 - MotionStep(MotionToken.move, elapsedMs).xx).clamp(0.0, 1.0);
    if (p == 1) _elapsed = durationMs;
    return _frame = samplePath(p);
  }

  /// 도착했거나([at]이 길이에 닿았거나) 도중에 멈춘 뒤면 참.
  bool get done => _stopped || _elapsed >= durationMs;

  /// 도중에 눌렀다 — 마지막으로 셈한 자리에서 멈춘다. 뒤로는 [at]이 그 장면만 돌려준다.
  void stop() => _stopped = true;

  /// 마지막으로 셈한 장면(아직 한 번도 셈하지 않았으면 떠난 곳).
  (double lo, double span, double top) get current => _frame;

  /// 갈 곳(가리는 폭 · 가두기를 마친 값).
  (double lo, double span, double top) get destination => (toLo, toSpan, toTop);

  /// 진행값 [p](0~1, 곡선을 먹인 값)에서의 보기 가운데(분)와 폭(분).
  (double, double) _atProgress(double p) {
    if (_zoomOnly) return (_u0 + p * _d, _w0 * math.exp(_rho * p * _s));
    final x = _rho * (p * _s) + _r0;
    final u = (_w0 / (_rho2 * _d.abs())) * (_ch0 * _tanh(x) - _sh0);
    return (_u0 + u * _d, _w0 * _ch0 / _cosh(x));
  }

  /// 시간과 독립적인 경로 표본. 경로의 비교 검사는 진행값을 직접 주어 공간의 모양을 확인한다.
  (double lo, double span, double top) samplePath(double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (p == 0) return (fromLo, fromSpan, fromTop);
    if (p == 1) return (toLo, toSpan, toTop);
    final (u, w) = _atProgress(p);
    return (u - w / 2, w, fromTop + (toTop - fromTop) * p);
  }

  static double _asinh(double x) {
    final a = x.abs();
    final v = math.log(a + math.sqrt(a * a + 1));
    return x < 0 ? -v : v;
  }

  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

  static double _tanh(double x) {
    if (x.abs() > 20) return x < 0 ? -1.0 : 1.0;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

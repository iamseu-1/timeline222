import 'dart:math' as math;

import 'package:archive_prototype/scene/fly.dart';
import 'package:archive_prototype/motion.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

// 멀리 가기의 길(lib/scene/fly.dart) — van Wijk 길 · 길이 · 곡선 · 가린 폭 · 세로 싣기.
// 값의 정답은 docs/명세-3단계/06-상세-검색-필터-도구.md 5-3절(지금 연표의 zoomPath · _animateTo · focusOn)이다.

/// 시간은 정수 분이므로 한 해는 525,960분(2단계의 약속).
const year = 525960.0;

/// 1920 창의 그림 영역 폭(배치 px) — 왼쪽 줄 이름 칸 196을 뺀 값.
const plot = 1920.0 - 196.0;

/// 검사가 저 혼자 셈하는 곡선(지금 연표의 easeInOut).
double ease(double t) => t < .5 ? 4 * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

/// 비행을 [n]번 나누어 훑는다(0 → 길이).
List<(double lo, double span, double top)> samples(Fly f, {int n = 200}) => [for (var i = 0; i <= n; i++) f.at(f.durationMs * i / n)];

/// 보기 [v]에서 시각 [minute]이 놓이는 그림 영역의 x(배치 px).
double screenX(double minute, (double, double, double) v) => (minute - v.$1) / v.$2 * plot;

void main() {
  test('처음과 끝이 정확히 맞는다', () {
    final f = Fly.plan(fromLo: -1500 * year, fromSpan: 1000 * year, fromTop: 120, toLo: 800 * year, toSpan: 40 * year, toTop: 900, plotWidth: plot, inset: FlyInset.none);
    expect(f.at(0), (-1500 * year, 1000 * year, 120.0));
    expect(f.at(-5), (-1500 * year, 1000 * year, 120.0), reason: '아직 떠나기 전이면 떠난 곳');
    expect(f.at(f.durationMs), (800 * year, 40 * year, 900.0));
    expect(f.at(f.durationMs + 500), (800 * year, 40 * year, 900.0), reason: '길이를 넘겨도 갈 곳에 서 있다');
    // 도착 직전의 장면이 갈 곳에 붙어 있다 — 마지막 장면에서 툭 튀지 않는다.
    final almost = f.at(f.durationMs - .5);
    expect(almost.$1, closeTo(800 * year, 40 * year * 1e-3));
    expect(almost.$2, closeTo(40 * year, 40 * year * 1e-3));
    expect(almost.$3, closeTo(900, 1));
  });

  test('진행은 단조롭다 — 가운데도 세로도 되돌아가지 않는다', () {
    final f = Fly.plan(fromLo: -1500 * year, fromSpan: 1000 * year, fromTop: 0, toLo: 1800 * year, toSpan: 60 * year, toTop: 2400, plotWidth: plot, inset: FlyInset.none);
    final got = samples(f);
    for (var i = 1; i < got.length; i++) {
      final before = got[i - 1], now = got[i];
      expect(now.$1 + now.$2 / 2, greaterThanOrEqualTo(before.$1 + before.$2 / 2 - 1e-3), reason: '보기의 가운데는 갈 곳 쪽으로만 간다');
      expect(now.$3, greaterThanOrEqualTo(before.$3 - 1e-9), reason: '세로도 한 방향으로만');
      expect(now.$2, greaterThan(0));
    }
    expect(got.last.$1 + got.last.$2 / 2, closeTo(1830 * year, 1e-3));
  });

  test('먼 거리에서는 물러났다가 다가간다 — 가운데의 폭이 양 끝보다 넓다', () {
    const w = 1000 * year;
    const d = 20000 * year; // 화면의 스무 배 떨어진 곳
    final f = Fly.plan(fromLo: 0, fromSpan: w, toLo: d, toSpan: w, plotWidth: plot, inset: FlyInset.none);
    final got = samples(f);
    final widest = got.map((s) => s.$2).reduce(math.max);
    expect(widest, greaterThan(w * 19), reason: '폭이 같을 때 길 위의 가장 넓은 폭은 √(폭² + 거리²)');
    expect(widest, closeTo(math.sqrt(w * w + d * d), w * .01));
    expect(f.samplePath(.5).$2, closeTo(math.sqrt(w * w + d * d), w * 1e-6), reason: '가장 넓은 곳은 공간 경로의 한가운데');
    expect(got.first.$2, w);
    expect(got.last.$2, w);
  });

  test('같은 화면 안이면 물러나지 않고 미끄러진다', () {
    const w = 1000 * year;
    for (final (gap, limit) in [(w / 4, 1.04), (w / 2, 1.12)]) {
      final f = Fly.plan(fromLo: 0, fromSpan: w, toLo: gap, toSpan: w, plotWidth: plot, inset: FlyInset.none);
      final widest = samples(f).map((s) => s.$2).reduce(math.max);
      expect(widest, lessThan(w * limit), reason: '거리가 화면의 ${gap / w}배면 폭이 거의 그대로다');
      expect(widest, greaterThanOrEqualTo(w), reason: 'van Wijk 길은 조금은 물러난다');
    }
  });

  test('가운데가 같으면 폭만 로그 눈금으로 고르게 — 길의 한가운데는 기하 평균', () {
    final f = Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: 450 * year, toSpan: 100 * year, plotWidth: plot, inset: FlyInset.none);
    expect(f.samplePath(.5).$2, closeTo(math.sqrt(1000 * year * 100 * year), year), reason: '√(1000 × 100) = 316.2년');
    for (final s in samples(f)) {
      expect(s.$1 + s.$2 / 2, closeTo(500 * year, 1e-3), reason: '가운데는 한 자리에 머문다');
    }
  });

  test('거리와 관계없이 move 한 값의 시간으로 흐른다', () {
    // 제자리 비행: S가 0이라 하한.
    final still = Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: 0, toSpan: 1000 * year, plotWidth: plot, inset: FlyInset.none);
    expect(still.pathLength, closeTo(0, 1e-9));
    expect(still.durationMs, Motion.move);
    // 아주 먼 비행: S가 커서 상한.
    final far = Fly.plan(fromLo: 0, fromSpan: 100 * year, toLo: 20000 * year, toSpan: 100 * year, plotWidth: plot, inset: FlyInset.none);
    expect(far.durationMs, Motion.move);
    // 그 사이: 식 그대로.
    final mid = Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: 1500 * year, toSpan: 1000 * year, plotWidth: plot, inset: FlyInset.none);
    expect(mid.durationMs, Motion.move);
    expect(mid.pathLength, greaterThan(still.pathLength), reason: '길은 멀어져도 스프링 값은 하나');
  });

  test('세로는 가로와 같은 진행값으로 나아가 같은 장면에 도착한다', () {
    final f = Fly.plan(fromLo: 0, fromSpan: 1000 * year, fromTop: 400, toLo: 3000 * year, toSpan: 200 * year, toTop: 1800, plotWidth: plot, inset: FlyInset.none);
    for (final t in [.1, .25, .5, .75, .9]) {
      final p = SpringSimulation(Motion.spring(MotionToken.move), 0, 1, 0).x(f.durationMs * t / 1000).clamp(0.0, 1.0);
      expect(f.at(f.durationMs * t).$3, closeTo(400 + (1800 - 400) * p, 1e-9), reason: '세로는 공통 스프링 진행값 그대로');
    }
    expect(f.at(f.durationMs).$3, 1800);
    expect(f.done, isTrue, reason: '가로와 세로가 같은 장면에 도착한다');
    // 세로를 싣지 않으면 움직이지 않는다.
    final flat = Fly.plan(fromLo: 0, fromSpan: 1000 * year, fromTop: 700, toLo: 3000 * year, toSpan: 200 * year, plotWidth: plot, inset: FlyInset.none);
    expect(samples(flat).map((s) => s.$3).toSet(), {700.0});
  });

  test('상세 창이 가린 폭을 뺀 부분의 가운데에 선다', () {
    const lo = 800 * year, span = 40 * year;

    // 기간이 있는 항목: 가려지지 않은 부분에 꼭 담는다.
    final fit = Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: lo, toSpan: span, plotWidth: plot, insetRight: Fly.detailInset);
    final fitEnd = fit.at(fit.durationMs);
    expect(fitEnd.$2, closeTo(span * plot / (plot - Fly.detailInset), 1e-6));
    expect(screenX(lo, fitEnd), closeTo(0, 1e-6), reason: '왼쪽 끝은 그림 영역의 왼쪽');
    expect(screenX(lo + span, fitEnd), closeTo(plot - Fly.detailInset, 1e-6), reason: '오른쪽 끝은 창의 왼쪽 변');
    expect(screenX(lo + span / 2, fitEnd), closeTo((plot - Fly.detailInset) / 2, 1e-6), reason: '가운데는 가려지지 않은 부분의 가운데');

    // 한 시점: 폭은 그대로 두고 가운데만 옮긴다.
    final mid = Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: lo, toSpan: span, plotWidth: plot, insetRight: Fly.detailInset, inset: FlyInset.center);
    final midEnd = mid.at(mid.durationMs);
    expect(midEnd.$2, span, reason: '폭은 그대로');
    expect(screenX(lo + span / 2, midEnd), closeTo((plot - Fly.detailInset) / 2, 1e-6));

    // 창이 없거나(0) 그림 영역의 절반을 넘게 가리면 평소대로.
    expect(Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: lo, toSpan: span, plotWidth: plot).destination, (lo, span, 0.0));
    expect(Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: lo, toSpan: span, plotWidth: plot, insetRight: plot * .6).destination, (lo, span, 0.0));
    expect(Fly.plan(fromLo: 0, fromSpan: 1000 * year, toLo: lo, toSpan: span, plotWidth: plot, insetRight: Fly.detailInset, inset: FlyInset.none).destination, (lo, span, 0.0));
  });

  test('갈 곳을 가두는 규칙은 가린 폭을 뺀 뒤에 걸린다', () {
    const lo = 800 * year, span = 40 * year;
    var asked = (.0, .0);
    final f = Fly.plan(
      fromLo: 0,
      fromSpan: 1000 * year,
      toLo: lo,
      toSpan: span,
      plotWidth: plot,
      insetRight: Fly.detailInset,
      bound: (l, s) {
        asked = (l, s);
        return (math.min(l, 700 * year), math.min(s, 30 * year));
      },
    );
    expect(asked.$2, closeTo(span * plot / (plot - Fly.detailInset), 1e-6), reason: '가린 폭을 뺀 값이 규칙에 들어간다');
    expect(f.destination, (700 * year, 30 * year, 0.0));
    expect(f.at(f.durationMs), (700 * year, 30 * year, 0.0), reason: '가둔 자리에 정확히 도착한다');
  });

  test('도중에 누르면 그 자리에서 멈춘다', () {
    final f = Fly.plan(fromLo: 0, fromSpan: 1000 * year, fromTop: 0, toLo: 3000 * year, toSpan: 200 * year, toTop: 1500, plotWidth: plot, inset: FlyInset.none);
    final held = f.at(f.durationMs * .4);
    expect(f.done, isFalse);
    f.stop();
    expect(f.done, isTrue);
    expect(f.at(f.durationMs * .9), held, reason: '멈춘 뒤로는 그 장면만');
    expect(f.at(f.durationMs), held, reason: '갈 곳으로 끌려가지 않는다');
    expect(f.current, held);
  });

  test('움직임 줄이기면 즉시 — 길이 1ms에 처음부터 갈 곳', () {
    final f = Fly.plan(fromLo: 0, fromSpan: 1000 * year, fromTop: 0, toLo: 3000 * year, toSpan: 200 * year, toTop: 1500, plotWidth: plot, inset: FlyInset.none, reduceMotion: true);
    expect(f.durationMs, 1);
    expect(f.at(0), (3000 * year, 200 * year, 1500.0));
    expect(f.done, isTrue);
  });

  test('지금 연표의 zoomPath와 같은 값을 낸다', () {
    // 기준값: js/timeline.js 1167~1190줄의 zoomPath · easeInOut를 그대로 떼어 내 같은 입력으로 돌린 것.
    // [떠난 lo, 떠난 span, 갈 lo, 갈 span, 길이(ms), t .25 · .5 · .75의 (lo, span)]
    const cases = [
      ('멀리 · 크게 확대', -1500 * year, 1000 * year, 800 * year, 40 * year, 966.308132557, [-811101276.650850, 705657761.185233, 203017670.131701, 382904659.736598, 415985480.774450, 30370385.125478]),
      ('가까이 미끄러짐', 0.0, 1000 * year, 250 * year, 1000 * year, 320.0, [6088511.951466, 529681090.561394, 57651420.643767, 542147158.712466, 121680397.487140, 529681090.561394]),
      ('가운데가 같음', 0.0, 1000 * year, 450 * year, 100 * year, 536.789500698, [35248702.242770, 455462595.514460, 179818422.092892, 166323155.814216, 232611543.366637, 60736913.266727]),
    ];
    for (final (name, fromLo, fromSpan, toLo, toSpan, _, want) in cases) {
      final f = Fly.plan(fromLo: fromLo, fromSpan: fromSpan, toLo: toLo, toSpan: toSpan, plotWidth: plot, inset: FlyInset.none);
      expect(f.durationMs, Motion.move, reason: '$name의 공통 시간');
      for (final (i, t) in [.25, .5, .75].indexed) {
        final got = f.samplePath(ease(t));
        expect(got.$1, closeTo(want[i * 2], want[i * 2].abs() * 1e-9 + 1e-3), reason: '$name t=$t의 왼쪽 끝');
        expect(got.$2, closeTo(want[i * 2 + 1], want[i * 2 + 1] * 1e-9 + 1e-3), reason: '$name t=$t의 폭');
      }
    }
  });

  test('되돌아가는 비행(뒤로 · 축소)은 가는 길을 뒤집은 것과 같다', () {
    const aLo = 0.0, aSpan = 200 * year, bLo = 3000 * year, bSpan = 1000 * year;
    final going = Fly.plan(fromLo: aLo, fromSpan: aSpan, toLo: bLo, toSpan: bSpan, plotWidth: plot, inset: FlyInset.none);
    final back = Fly.plan(fromLo: bLo, fromSpan: bSpan, toLo: aLo, toSpan: aSpan, plotWidth: plot, inset: FlyInset.none);
    expect(back.durationMs, closeTo(going.durationMs, 1e-6), reason: '길의 길이 S는 오가며 같다');
    final out = [for (var i = 0; i <= 200; i++) going.samplePath(i / 200)], home = [for (var i = 0; i <= 200; i++) back.samplePath(i / 200)];
    for (var i = 0; i <= 200; i++) {
      expect(home[200 - i].$2, closeTo(out[i].$2, out[i].$2 * 1e-6 + 1e-6));
      expect(out[i].$1.isFinite && out[i].$2.isFinite, isTrue);
    }
  });
}

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

// 2026-10-13 감독 결정: 통통 · 정갈. 시계 하나, 스프링 식 하나, 이름 붙은 값 여섯.
// 상태 변화는 한 번만 넘친다. 그림판의 손 추종 · 쫓아가기 · 관성은 기존 식을 보존한다.
// 목표가 바뀌면 지금 자리와 속도에서 이어 간다. 화면 단위 넘침 제한은 MotionSpring의 주인이 정한다.
enum MotionToken { snap, pop, move, enter, exit, ring }
abstract final class Motion {
  /// 튐 세기 하나가 화면 전체를 바꾼다(0 · 1 · 2 · 3).
  static const level = 2;

  /// 색 변화만 120ms. 나머지는 아래 여섯 스프링의 길이(ms)를 쓴다.
  static const micro = 120.0, snap = 180.0, pop = 280.0, move = 400.0;
  static const enter = 200.0, out = 160.0, ring = 600.0;
  static const microMs = 120, snapMs = 180, popMs = 280, moveMs = 400;
  static const enterMs = 200, outMs = 160, ringMs = 600;

  static double duration(MotionToken token) => switch (token) {
    MotionToken.snap => snap,
    MotionToken.pop => pop,
    MotionToken.move => move,
    MotionToken.enter => enter,
    MotionToken.exit => out,
    MotionToken.ring => ring,
  };

  static double bounce(MotionToken token) => switch (token) {
    MotionToken.pop => const [0.0, .25, .4, .5][level],
    MotionToken.move => const [0.0, .1, .2, .3][level],
    _ => 0,
  };

  static MotionToken near(double distance) => distance.abs() <= 64 ? MotionToken.pop : MotionToken.move;
  static double get releaseKick => const [0.0, .6, 1.0, 1.5][level];

  /// 질량 1, ω = 2π / d, 강성 ω², 감쇠 2(1-bounce)ω. SDK 판에 독립적인 같은 식.
  static SpringDescription spring(MotionToken token) {
    final omega = 2 * math.pi / (duration(token) / 1000);
    return SpringDescription(mass: 1, stiffness: omega * omega, damping: 2 * (1 - bounce(token)) * omega);
  }

  /// 목표를 쫓아가는 지수 감쇠의 시정수(ms): 노치 휠 · 단추 · 키 70, 잘게 오는 입력(트랙패드) 25.
  static const chaseNotch = 70.0, chaseFine = 25.0;

  /// 한 번의 휠 입력이 이 값 이상이면 노치 휠로 본다.
  static const notchDelta = 40.0;

  /// 휠 확대의 배율식 exp(dy × wheelZoom).
  static const wheelZoom = .0018;

  /// 관성: 시정수 250ms · 50px/s 미만이면 없음 · 15px/s에서 멎음 · 놓기 전 80ms의 속도를 읽음 ·
  /// 미끄러지는 거리는 그림 폭의 1.5배까지 · 20px 이상 끌었을 때만.
  static const coastTau = 250.0, coastMin = 50.0, coastRest = 15.0, coastGrab = 80.0, coastMax = 1.5, coastTravel = 20.0;

  /// 끌기로 치는 문턱(px). 넘는 순간 기준점을 다시 잡는다.
  static const dragThreshold = 5.0;

  /// 확대 표시의 들어오는 문턱과 나가는 문턱의 차이(8%).
  static const lodGap = .08;

  static const curve = Cubic(.32, .72, 0, 1);

  // ---- 느리게 보기(움직임 계측 창 · ui/motion_meter.dart) ----
  //
  // 지금 연표는 rate(1 · 0.25 · 0.1)만큼 천천히 가는 **가상 시계 하나**로 움직임의 시간을 재고(js/core.js의 HT.motion),
  // CSS 전환 · 키프레임은 매 장면 playbackRate를 그 값에 맞춘다. 여기서도 시계는 하나다. 다만 배율의 뜻을 뒤집어
  // 사람이 읽기 쉬운 쪽으로 둔다: 1이 보통 빠르기, 8이면 여덟 배 느리게.
  //
  // 배율을 타는 길은 둘뿐이고 **둘 다 [slow] 하나가 켠다**:
  //   ① 장면 시각 — Flutter는 장면 시각을 [timeDilation]으로 나눠 시계(Ticker · AnimationController)에 준다
  //      (SchedulerBinding._adjustForEpoch). 그래서 화면의 시계에서 흘러온 dt를 받는 것 — 조작부(`TimelineController.tick`) ·
  //      줄 흐름(`RowFlow.tick`) · 위젯의 `AnimatedContainer` 같은 것 — 은 **저절로** 함께 느려진다.
  //      이런 곳에서 dt를 또 나누면 배율이 제곱이 된다(4배가 16배).
  //   ② Stopwatch로 재던 흐름 — 타일 떠오름 · 이름 드나듦 · 밝기(`Emphasis.tick`) · 접힘 정착은 장면의 dt가 아니라
  //      제 시계로 잰다. 그것들은 [now]로 재야 ①과 같은 배율을 탄다.
  //
  // 측정 모드에서는 늘 1이다. 계측 창을 닫을 때 1로 돌아오지만 그것만으로는 모자란다 — 4배로 열어 둔 채 메뉴의 '측정'을
  // 누르면 그 배율 그대로 재게 된다. 그래서 `measure/runner.dart`의 `runMeasure` 들머리가 `Motion.slow = 1`을 두고,
  // `archive_app.dart`의 `quickMeasure()`는 재기 전에 계측 창을 닫는다(총괄 이음 · 필수 · ui/motion_meter.dart 머리말).

  /// 계측 창이 고르게 하는 배율 — 1배(보통) · 2 · 4 · 8배 느리게.
  static const slowRates = <double>[1, 2, 4, 8];

  static double _slow = 1;
  static final Stopwatch _watch = Stopwatch()..start();
  static double _base = 0, _baseReal = 0;

  /// 느리게 보기 배율(1 · 2 · 4 · 8). 1이 보통 빠르기다.
  static double get slow => _slow;

  /// 배율을 바꾼다. 바꾸는 순간의 가상 시각을 붙들어 두므로 이미 흐르던 움직임이 그 자리에서 튀지 않는다.
  static set slow(double value) {
    final rate = value.isFinite && value > 0 ? value : 1.0;
    if (rate == _slow) return;
    final real = _watch.elapsedMicroseconds / 1000;
    _base += (real - _baseReal) / _slow;
    _baseReal = real;
    _slow = rate;
    timeDilation = rate;
  }

  /// 느리게 보기와 함께 느려지는 한 시계(ms · 1배 기준). 배율이 1이면 그냥 흘러온 시간이다.
  /// 돌려주는 값은 늘 앞으로만 간다 — 배율을 바꿔도 뒤로 가거나 건너뛰지 않는다.
  static double now() => _base + (_watch.elapsedMicroseconds / 1000 - _baseReal) / _slow;
}

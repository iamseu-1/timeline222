import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';

import 'motion.dart';

/// 같은 스프링 식의 해석해. 장면 간격을 잘게 반복하지 않아 긴 장면에서도 안정적이다.
/// x' = xx·x + xv·v, v' = vx·x + vv·v (x는 목표에서 떨어진 거리, v는 초당 속도).
class MotionStep {
  const MotionStep._(this.xx, this.xv, this.vx, this.vv);

  factory MotionStep(MotionToken token, double dtMs) {
    final w = 2 * math.pi / (Motion.duration(token) / 1000);
    final z = 1 - Motion.bounce(token), t = math.max(0.0, dtMs) / 1000;
    final decay = math.exp(-z * w * t);
    if (z == 1) {
      return MotionStep._(
        decay * (1 + w * t),
        decay * t,
        -decay * w * w * t,
        decay * (1 - w * t),
      );
    }
    final damped = w * math.sqrt(1 - z * z);
    final sine = math.sin(damped * t) / damped, cosine = math.cos(damped * t);
    return MotionStep._(
      decay * (cosine + z * w * sine),
      decay * sine,
      -decay * w * w * sine,
      decay * (cosine - z * w * sine),
    );
  }

  final double xx, xv, vx, vv;
}

/// 자리·크기·짙기 하나의 주인. 목표를 바꿔도 지금 값과 속도는 그대로 이어진다.
/// 장면의 dt는 Flutter가 이미 느리게 만든 값이다. 여기서 배율을 또 나누지 않는다.
class MotionSpring {
  MotionSpring(
    double value, {
    this.token = MotionToken.move,
    this.epsilon = .001,
    this.maxOvershoot = double.infinity,
  }) : _value = value,
       _target = value;

  MotionToken token;
  final double epsilon;

  /// 화면 px이면 6 이하, 크기 비율이면 6 / 부품 폭 이하. 0이면 목표를 넘지 않는다.
  final double maxOvershoot;
  double _value, _target, _velocity = 0;
  double _direction = 0;
  bool _crossed = false, _active = false;
  VoidCallback? _wake, _changed;

  double get value => _value;
  double get target => _target;
  double get velocity => _velocity;
  bool get active => _active;

  void retarget(double target, {MotionToken? token}) {
    if (target == _target) return;
    if (token != null) this.token = token;
    _target = target;
    _direction = (target - _value).sign;
    if (_direction == 0) _direction = _velocity.sign;
    _crossed = false;
    _active = true;
    _wake?.call();
  }

  void jump(double value) {
    _value = _target = value;
    _velocity = 0;
    _active = _crossed = false;
    _direction = 0;
    _changed?.call();
  }

  void kick(double velocity) {
    if (!_active) {
      _direction = velocity.sign;
      _crossed = false;
    }
    _velocity += velocity;
    if (_direction == 0) _direction = _velocity.sign;
    _active = true;
    _wake?.call();
  }

  void stop() => jump(_value);

  /// 바뀌었으면 참. sharedStep은 같은 장면·토큰의 계수를 여러 값이 나누어 쓸 때 쓴다.
  bool step(double dtMs, {MotionStep? sharedStep}) {
    if (!_active || dtMs <= 0) return false;
    final m = sharedStep ?? MotionStep(token, dtMs);
    final before = _value, offset = before - _target;
    var next = _target + m.xx * offset + m.xv * _velocity;
    var speed = m.vx * offset + m.vv * _velocity;
    final beyond = (next - _target) * _direction;
    final overshootLimit = Motion.bounce(token) == 0 ? 0.0 : maxOvershoot;
    if (_direction != 0 && beyond > 0) {
      _crossed = true;
      // 극단적인 빠른 재입력도 화면의 넘침 상한을 넘지 않는다.
      if (beyond > overshootLimit) {
        next = _target + _direction * overshootLimit;
        speed = math.min(0.0, speed * _direction) * _direction;
      }
    } else if (_crossed) {
      // 첫 넘침이 돌아와 목표를 지나는 장면에 끝낸다. 두 번째 출렁임은 만들지 않는다.
      next = _target;
      speed = 0;
    }
    if ((next - _target).abs() < epsilon && speed.abs() < epsilon * 20) {
      next = _target;
      speed = 0;
      _active = false;
    }
    _value = next;
    _velocity = speed;
    return before != _value;
  }
}

/// UI 전체가 나누는 장면 시계 하나. 쉬는 동안 Ticker를 멈추고 상태가 바뀐 부품만 알린다.
/// 캔버스는 원래의 장면 시계를 쓰며 두 시계 모두 Flutter의 같은 timeDilation에 매인다.
class MotionStage {
  MotionStage._();
  static final instance = MotionStage._();

  final _owners = <MotionSpring, VoidCallback>{};
  final _timers = <Object, (double, VoidCallback)>{};
  final _dirty = <VoidCallback>{};
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _time = 0;

  void attach(MotionSpring spring, VoidCallback onChanged) {
    assert(!_owners.containsKey(spring), '값 하나에는 화면의 주인이 하나만 있다');
    _owners[spring] = onChanged;
    spring._changed = onChanged;
    spring._wake = _start;
    if (spring.active) _start();
  }

  void detach(MotionSpring spring) {
    _owners.remove(spring);
    spring._wake = spring._changed = null;
    _stopIfIdle();
  }

  Object schedule(double delayMs, VoidCallback callback) {
    final key = Object();
    _timers[key] = (_time + delayMs, callback);
    _start();
    return key;
  }

  void cancel(Object? key) {
    _timers.remove(key);
    _stopIfIdle();
  }

  void _start() {
    _ticker ??= Ticker(_tick, debugLabel: '공통 움직임 장');
    if (_ticker!.isActive) return;
    _last = Duration.zero;
    _ticker!.start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    _time += dt;
    // 예약 실행은 새 예약·취소를 할 수 있다. due 목록만 복사해 순회한다.
    final due = _timers.entries
        .where((e) => e.value.$1 <= _time)
        .map((e) => e.key)
        .toList();
    for (final key in due) {
      _timers.remove(key)?.$2.call();
    }
    final steps = <MotionToken, MotionStep>{};
    for (final entry in _owners.entries) {
      final spring = entry.key;
      if (!spring.active) continue;
      final step = steps.putIfAbsent(
        spring.token,
        () => MotionStep(spring.token, dt),
      );
      final wasActive = spring.active;
      if (spring.step(dt, sharedStep: step) || (wasActive && !spring.active)) {
        _dirty.add(entry.value);
      }
    }
    final changed = _dirty.toList();
    _dirty.clear();
    for (final callback in changed) {
      callback();
    }
    _stopIfIdle();
  }

  void _stopIfIdle() {
    if (_timers.isEmpty && !_owners.keys.any((s) => s.active)) _ticker?.stop();
  }
}

/// 기존 AnimatedBuilder와 상태 리스너를 같은 장에 잇는 얇은 어댑터.
/// 불투명도는 enter/exit 토큰과 maxOvershoot: 0, 자리는 move/snap을 쓴다.
class MotionAnimation extends Animation<double>
    with
        AnimationEagerListenerMixin,
        AnimationLocalListenersMixin,
        AnimationLocalStatusListenersMixin {
  MotionAnimation({
    double value = 0,
    this.enter = MotionToken.move,
    this.exit = MotionToken.snap,
    double maxOvershoot = .015,
    double epsilon = .0005,
  }) : _spring = MotionSpring(
         value,
         token: enter,
         epsilon: epsilon,
         maxOvershoot: maxOvershoot,
       ),
       _status = value == 0
           ? AnimationStatus.dismissed
           : AnimationStatus.completed {
    MotionStage.instance.attach(_spring, _changed);
  }

  final MotionToken enter, exit;
  final MotionSpring _spring;
  AnimationStatus _status;
  bool _forward = true;

  @override
  double get value => _spring.value;
  set value(double value) => _spring.jump(value);
  double get velocity => _spring.velocity;
  @override
  bool get isAnimating => _spring.active;
  @override
  AnimationStatus get status => _status;

  void forward({double? from}) {
    if (from != null) _spring.jump(from);
    _forward = true;
    _spring.retarget(1, token: enter);
    _changed();
  }

  void reverse({double? from}) {
    if (from != null) _spring.jump(from);
    _forward = false;
    _spring.retarget(0, token: exit);
    _changed();
  }

  void animateTo(double target, {Duration? duration, Curve? curve}) {
    _forward = true;
    _spring.retarget(target, token: enter);
    _changed();
  }

  void animateBack(double target, {Duration? duration, Curve? curve}) {
    _forward = false;
    _spring.retarget(target, token: exit);
    _changed();
  }

  void kick(double velocity) => _spring.kick(velocity);

  void stop() => _spring.stop();

  void _changed() {
    final next = _spring.active
        ? (_forward ? AnimationStatus.forward : AnimationStatus.reverse)
        : (value == 0 ? AnimationStatus.dismissed : AnimationStatus.completed);
    notifyListeners();
    if (next != _status) {
      _status = next;
      notifyStatusListeners(next);
    }
  }

  @override
  void dispose() {
    MotionStage.instance.detach(_spring);
    clearListeners();
    clearStatusListeners();
    super.dispose();
  }
}

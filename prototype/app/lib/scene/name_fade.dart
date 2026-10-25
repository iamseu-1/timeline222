import '../motion.dart';
import '../motion_spring.dart';

// 이름의 드나듦은 공통 in/out 스프링. 다시 나타나면 사라지던 자리와 속도에서 이어 간다.
// 자리는 분 · 줄 · 글줄에 매여 있어, 옅어지는 동안에도 화면과 함께 움직인다.
// 옅어짐은 글자 방식 (나)에서만 쓴다 — 글줄 방식은 색이 구워져 있어 층 없이는 투명도를 못 준다(enabled = false).

/// 그린 이름 하나. [dx]는 점에서 이름의 왼쪽 끝까지(배치 px), [size]는 그 줄의 사건 글자 크기, [look]은 계약 6-6의 모양 비트.
class NameShown {
  const NameShown({
    required this.eventId,
    required this.title,
    required this.importance,
    required this.at,
    required this.row,
    required this.line,
    required this.dx,
    this.size = 12,
    this.look = 0,
    this.band = 0,
  });
  final int eventId, importance, row, line, look;

  /// 사건이 든 띠 — 옅어지는 이름도 그 띠의 사건 칸 자리에(두 장 꼬리표의 올림).
  final int band;
  final String title;
  final double at, dx, size;

  bool samePlace(NameShown other, double minutesPerPx) =>
      row == other.row && line == other.line && (dx - other.dx).abs() < 1 && (at - other.at).abs() <= minutesPerPx;
}

class _NameAlpha {
  _NameAlpha(double from, this.at) : spring = MotionSpring(from, epsilon: .01, maxOvershoot: 0);
  final MotionSpring spring;
  double at;

  // 같은 장면의 이름들은 같은 dt와 토큰을 쓴다. 지수 계산과 행렬 객체를 이름마다 만들지 않는다.
  static double _frameAt = double.negativeInfinity;
  static final _enterSteps = <double, MotionStep>{}, _exitSteps = <double, MotionStep>{};

  double sample(double now) {
    if (now > at) {
      if (spring.active) {
        if (now != _frameAt) {
          _frameAt = now;
          _enterSteps.clear();
          _exitSteps.clear();
        }
        final dt = now - at;
        final steps = spring.token == MotionToken.enter ? _enterSteps : _exitSteps;
        final step = steps[dt] ??= MotionStep(spring.token, dt);
        spring.step(dt, sharedStep: step);
      }
      at = now;
    }
    return spring.value.clamp(0.0, 1.0);
  }
}

class _Entered {
  _Entered(this.name, double since, double duration, double from, {_NameAlpha? alpha}) : alpha = alpha ?? _NameAlpha(from, since) {
    if (duration <= 0) {
      this.alpha.spring.jump(1);
    } else {
      this.alpha.spring.retarget(1, token: MotionToken.enter);
    }
  }
  NameShown name;
  final _NameAlpha alpha;
  double alphaAt(double now) => alpha.sample(now);
}

/// 빠진 이름의 그림자.
class NameGhost {
  NameGhost(this.name, this.since, this.duration, this.from) : _alpha = _NameAlpha(from, since) {
    _alpha.spring.retarget(0, token: MotionToken.exit);
  }
  NameGhost._(this.name, this.since, this.duration, this.from, this._alpha) {
    _alpha.spring.retarget(0, token: MotionToken.exit);
  }
  final NameShown name;
  final double since, duration, from;
  final _NameAlpha _alpha;
  double alphaAt(double now) => _alpha.sample(now);
}

class NameFade {
  bool enabled = true;
  final _entered = <int, _Entered>{};
  final _ghosts = <NameGhost>[];
  double _until = double.negativeInfinity;

  /// 모두 잊는다 — 저장소를 다시 지어 사건 번호가 통째로 바뀌었을 때(옛 번호의 이름이 새 번호의 이름과 짝지어지지 않게).
  void clear() {
    _entered.clear();
    _ghosts.clear();
    _until = double.negativeInfinity;
    _heldAt = double.negativeInfinity;
  }

  /// 크게 바뀌는 장면(`TimelineScene.cutNames`): 들어와 있던 이름과 옅어지던 그림자를 모두 거두고, 다음 판이 올 때까지
  /// 이름을 그리지 않는다 — 옛 판의 이름은 옛 크기 · 옛 자리라 새 배치 위에 겹쳐 보인다. 새 판의 이름은 모두 처음 들어오는 이름이라
  /// 지금의 등장 값(in)으로 한 번에 나타난다. 판이 끝내 오지 않아도 [_holdMax] 뒤에는 다시 그린다.
  void cut(double now) {
    _entered.clear();
    _ghosts.clear();
    _until = double.negativeInfinity;
    _heldAt = now;
  }

  /// 옅어지던 그림자만 거둔다(비행 도착 — 이름은 그대로 둔다).
  void dropGhosts() => _ghosts.clear();

  double _heldAt = double.negativeInfinity;
  static const _holdMax = 600.0;

  /// [cut] 뒤 새 판을 기다리는 중인가 — 그동안 이름은 그리지 않는다.
  bool heldAt(double now) => now - _heldAt < _holdMax;

  /// 이름 자리의 새 판이 도착할 때마다 부른다. [minutesPerPx]는 같은 자리로 칠 너비(1px의 분).
  /// [ghosts]가 거짓이면(크게 바뀐 뒤 줄이 흐르는 동안 · 비행 도중) 빠지는 이름은 그림자 없이 바로 지우고, 자리를 옮긴 이름은 그 짙기 그대로 새 자리로 간다.
  void accept(List<NameShown> names, {required double now, bool moving = false, bool instant = false, bool ghosts = true, double minutesPerPx = 0}) {
    _heldAt = double.negativeInfinity;
    if (!enabled || instant) {
      _entered
        ..clear()
        ..addAll({for (final n in names) n.eventId: _Entered(n, now, 0, 1)});
      _ghosts.clear();
      _until = double.negativeInfinity;
      return;
    }
    const enter = Motion.enter, leave = Motion.out;
    _ghosts.removeWhere((g) => g.alphaAt(now) <= 0);
    final next = <int, _Entered>{};
    for (final n in names) {
      final old = _entered.remove(n.eventId);
      if (old != null && (!ghosts || old.name.samePlace(n, minutesPerPx))) {
        next[n.eventId] = old..name = n;
        continue;
      }
      if (old != null) _leave(old, now, leave);
      // 옅어지던 제 그림자가 같은 자리에 있으면 그 짙기에서 이어 간다(겹쳐 보이지 않게 그림자는 거둔다).
      _NameAlpha? alpha;
      final g = _ghosts.indexWhere((g) => g.name.eventId == n.eventId && g.name.samePlace(n, minutesPerPx));
      if (g >= 0) {
        final ghost = _ghosts.removeAt(g);
        ghost.alphaAt(now);
        alpha = ghost._alpha;
      }
      next[n.eventId] = _Entered(n, now, enter, alpha?.spring.value ?? 0, alpha: alpha);
      if (now + enter * 2 > _until) _until = now + enter * 2;
    }
    if (ghosts) {
      for (final old in _entered.values) {
        _leave(old, now, leave);
      }
    }
    _entered
      ..clear()
      ..addAll(next);
  }

  void _leave(_Entered old, double now, double duration) {
    final alpha = old.alphaAt(now);
    if (alpha <= 0) return;
    _ghosts.add(NameGhost._(old.name, now, duration, alpha, old.alpha));
    if (now + duration * 2 > _until) _until = now + duration * 2;
  }

  double alphaOf(int eventId, double now) => heldAt(now) ? 0 : _entered[eventId]?.alphaAt(now) ?? 1;

  /// 아직 옅어지는 중인 그림자들.
  List<NameGhost> ghosts(double now) {
    if (_ghosts.isNotEmpty) _ghosts.removeWhere((g) => g.alphaAt(now) <= 0);
    return _ghosts;
  }

  /// 드나드는 이름이 있는 동안에는 화면의 시계가 돌아야 한다.
  bool animating(double now) {
    if (heldAt(now)) return true;
    if (now >= _until) return false;
    for (final entry in _entered.values) {
      entry.alphaAt(now);
      if (entry.alpha.spring.active) return true;
    }
    for (final ghost in _ghosts) {
      ghost.alphaAt(now);
      if (ghost._alpha.spring.active) return true;
    }
    _until = double.negativeInfinity;
    return false;
  }
}

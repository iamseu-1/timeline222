import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'motion.dart';
import 'scene/fly.dart';
import 'scene/viewport.dart';

// 입력 → 보기. 지금 연표의 조작 규칙을 그대로 옮겼다:
// 휠 = 기간 확대(커서 아래 시각 고정, 목표를 쫓아감) · Ctrl+휠 = 돋보기(커서 아래의 시각과 줄이 제자리) ·
// 끌기(5px 문턱) + 놓으면 관성 · 끝에서는 멎고 되튀지 않음 · 누르면 그 자리에서 멎음.
// 시계는 움직이는 동안에만 돈다: [active]가 참인 동안만 화면이 [tick]을 부른다. 자료 조회는 여기서 기다리지 않는다.
class TimelineController extends ChangeNotifier {
  /// 가장 좁은 보기(분) = 0.05일, 자료 끝 너머로 보이는 여백(보기 폭의 비율), 돋보기 범위와 100%로 붙는 폭.
  static const minSpan = 72.0, edgeMargin = .02;
  static const magMin = .5, magMax = 3.0, magSnap = .03, magStep = 1.25;

  final view = SceneView();

  /// 쫓아가기 · 돋보기 · 관성 가운데 하나라도 도는 동안 참.
  final active = ValueNotifier<bool>(false);

  /// 돋보기 배율(표시용). 배율 알약은 이것만 듣는다 — 움직이는 장면마다 화면 부품을 다시 만들지 않게.
  final magnification = ValueNotifier<double>(1);
  bool reduceMotion = false;
  bool dragging = false;

  /// 손이 닿아 있는가(문턱 5px을 넘기 전에도 참). 빈 줄 접기의 정착이 이 동안 예약을 거둔다 — 끊어 끌 때 줄이 숨 쉬지 않게.
  bool pressed = false;

  double _min = 0, _max = 1440, _content = 0;
  double? _targetLo, _targetSpan, _targetMag;
  double _tau = Motion.chaseNotch;
  Offset _magAt = Offset.zero;
  double _magMinute = 0, _magBodyY = 0;
  Offset _velocity = Offset.zero;
  Offset? _downAt, _lastAt;
  double _travel = 0;
  final _samples = <(double, Offset)>[];

  /// 관성의 속도(화면 px/s, 손이 움직이던 방향).
  Offset get velocity => _velocity;
  bool get moving => dragging || pinching || active.value;
  double get maxSpan => (_max - _min) * (1 + 2 * edgeMargin);
  double get minMinute => _min;
  double get maxMinute => _max;

  void setExtent(num min, num max) {
    _min = min.toDouble();
    _max = math.max(max.toDouble(), _min + minSpan);
    _bound();
    notifyListeners();
  }

  void setContentHeight(double height) {
    _content = height;
    _bound();
    notifyListeners();
  }

  void resize(double width, double height) {
    if (width == view.width && height == view.height) return;
    final span = view.span;
    view.setSize(width, height);
    // 창이 바뀌어도 보던 기간을 그대로 둔다.
    if (span.isFinite && span > 0) view.ppm = view.plotWidth / span;
    _bound();
    notifyListeners();
  }

  /// 왼쪽 칸의 폭과 날짜 칸의 높이(배치 px)가 바뀌었다 — 보던 기간은 그대로 둔다. 바뀌었으면 참.
  /// [notify]가 거짓이면 값만 옮기고 알리지 않는다 — 그리는 도중에 부르는 쪽이 알림을 미룰 수 있게.
  bool setFrame(double left, double head, {bool notify = true}) {
    if (left == view.left && head == view.head) return false;
    final span = view.span;
    view.left = left;
    view.head = head;
    if (span.isFinite && span > 0) view.ppm = view.plotWidth / span;
    _bound();
    if (notify) notifyListeners();
    return true;
  }

  void showRange(num lo, num hi) {
    stop();
    view.ppm = view.plotWidth / (hi - lo).toDouble().clamp(minSpan, maxSpan);
    view.lo = lo.toDouble();
    _bound();
    notifyListeners();
  }

  void showAll() => showRange(_min - (_max - _min) * edgeMargin, _max + (_max - _min) * edgeMargin);

  void scrollTo(double top) {
    view.top = top;
    _bound();
    notifyListeners();
  }

  /// 측정 모드가 켜 두면 받은 입력을 적는다 — 측정 도중 밖에서 들어온 입력(사람 손 · 다른 프로그램)을 가려내기 위해.
  List<String>? inputLog;

  /// 휠: dy < 0이면 확대. 연달아 오는 입력은 목표에 쌓인다.
  void wheel(Offset screen, double dy) {
    inputLog?.add('wheel ${dy.toStringAsFixed(0)} @${screen.dx.toStringAsFixed(0)},${screen.dy.toStringAsFixed(0)}');
    _velocity = Offset.zero;
    _dropFly();
    final fromLo = _targetLo ?? view.lo, fromSpan = _targetSpan ?? view.span;
    final span = (fromSpan * math.exp(dy * Motion.wheelZoom)).clamp(minSpan, maxSpan);
    final anchor = ((screen.dx / view.mag - view.left) / view.plotWidth).clamp(0.0, 1.0);
    _chase(fromLo + anchor * (fromSpan - span), span, dy.abs() >= Motion.notchDelta ? Motion.chaseNotch : Motion.chaseFine);
  }

  // ---- 멀리 가기: 검색 · 상세 창의 '이 위치로' · 가장자리 안내가 먼 곳으로 갈 때의 한 번의 비행(길은 scene/fly.dart) ----
  Fly? _fly;
  double _flyElapsed = 0;
  bool _flyFirst = false;
  void Function()? _flyArrived;

  /// 비행 중인가(빈 줄 접기의 정착 · 묶음 카드가 이 동안을 '움직이는 중'으로 본다).
  bool get flying => _fly != null;

  /// [lo, hi](분)로 날아간다. hi가 lo와 같으면(한 시점) 보던 폭 그대로 그 시점을 가운데로. [top]은 함께 실어 옮길 세로 자리(배치 px · 없으면 세로는 그대로),
  /// [insetRight]는 상세 창이 가린 폭(배치 px), [onArrive]는 도착한 그 장면에 한 번(도중에 누르면 부르지 않는다 — 도착 고리도 없다).
  void flyTo(double lo, double hi, {double? top, double insetRight = 0, void Function()? onArrive}) {
    stop();
    final point = hi <= lo;
    final span = point ? view.span : hi - lo;
    final least = math.max(0.0, _content - view.bodyHeight);
    _fly = Fly.plan(
      fromLo: view.lo, fromSpan: view.span, fromTop: view.top,
      toLo: point ? lo - span / 2 : lo, toSpan: span, toTop: top?.clamp(0.0, least).toDouble(),
      plotWidth: view.plotWidth, insetRight: insetRight, inset: point ? FlyInset.center : FlyInset.fit, reduceMotion: reduceMotion,
      bound: (l, sp) {
        final bounded = sp.clamp(minSpan, math.max(minSpan, maxSpan)).toDouble();
        return (_boundLo(l, bounded), bounded);
      },
    );
    _flyElapsed = 0;
    _flyFirst = true;
    _flyArrived = onArrive;
    if (reduceMotion) _flyStep(1);
    _sync();
  }

  /// 휠 · 키 · 돋보기가 비행 도중에 들어오면 비행은 그 자리에서 끝나고 새 입력이 거기서 이어 간다.
  void _dropFly() {
    _fly?.stop();
    _fly = null;
    _flyArrived = null;
  }

  void _flyStep(double dt) {
    final fly = _fly!;
    // 첫 장면은 한 장면 몫(16.7ms)으로 시작한다 — 부른 뒤 첫 장면까지 걸린 시간(다시 쌓기 · 그리기)을 길에서 건너뛰지 않게.
    _flyElapsed += _flyFirst ? math.min(dt, 1000 / 60) : dt;
    _flyFirst = false;
    final f = fly.at(_flyElapsed);
    view.ppm = view.plotWidth / f.$2;
    view.lo = f.$1;
    view.top = f.$3.clamp(0.0, math.max(0.0, _content - view.bodyHeight)).toDouble();
    if (fly.done) {
      final arrived = _flyArrived;
      _fly = null;
      _flyArrived = null;
      _bound();
      arrived?.call();
    }
  }

  /// 단추 · 키의 옆으로 가기(보기 폭의 비율).
  void glide(double fraction) {
    _velocity = Offset.zero;
    _dropFly();
    final span = _targetSpan ?? view.span;
    _chase((_targetLo ?? view.lo) + span * fraction, span, Motion.chaseNotch);
  }

  void _chase(double lo, double span, double tau) {
    _targetSpan = span;
    _targetLo = _boundLo(lo, span);
    _tau = tau;
    if (reduceMotion) {
      _arrive();
      notifyListeners();
    }
    _sync();
  }

  /// 돋보기(Ctrl + 휠): dy < 0이면 크게. 커서 아래의 시각과 줄이 제자리에 머문다.
  void magnify(Offset screen, double dy) => magnifyTo((_targetMag ?? view.mag) * math.exp(-dy * Motion.wheelZoom), screen);

  void magnifyTo(double mag, Offset screen) {
    _velocity = Offset.zero;
    _dropFly();
    _magAt = screen;
    _magMinute = view.minuteAt(screen.dx / view.mag);
    _magBodyY = view.bodyYAt(screen.dy / view.mag);
    _targetMag = mag.clamp(magMin, magMax);
    if (reduceMotion) {
      _setMag(_settledMag(_targetMag!));
      _targetMag = null;
      notifyListeners();
    }
    _sync();
  }

  double _settledMag(double mag) => (mag - 1).abs() <= magSnap ? 1 : mag;

  void _setMag(double mag) {
    final span = view.span;
    view.mag = mag;
    magnification.value = mag;
    // 배치 px은 그대로 두고 그림만 키운다: 1분의 폭은 그대로, 커서 아래의 시각과 줄을 제자리에.
    view.lo = _magMinute - (_magAt.dx / mag - view.left) / view.ppm;
    view.top = _magBodyY - (_magAt.dy / mag - view.head);
    if (view.span > maxSpan) view.ppm = view.plotWidth / maxSpan;
    assert(span > 0);
    _bound();
  }

  void pointerDown(Offset screen, double timeMs) {
    stop();
    pressed = true;
    _downAt = _lastAt = screen;
    _travel = 0;
    _samples
      ..clear()
      ..add((timeMs, screen));
  }

  void pointerMove(Offset screen, double timeMs) {
    final last = _lastAt;
    if (last == null) return;
    if (!dragging) {
      if ((screen - _downAt!).distance < Motion.dragThreshold) return;
      // 문턱을 넘는 순간 기준점을 다시 잡는다 — 첫 장면에 5px만큼 튀지 않게.
      dragging = true;
      _lastAt = screen;
      _samples
        ..clear()
        ..add((timeMs, screen));
      return;
    }
    final delta = screen - last;
    _lastAt = screen;
    _travel += delta.distance;
    _samples.add((timeMs, screen));
    _samples.removeWhere((s) => timeMs - s.$1 > Motion.coastGrab);
    _moveBy(delta);
    notifyListeners();
  }

  void pointerUp(Offset screen, double timeMs) {
    final wasDragging = dragging;
    dragging = false;
    pressed = false;
    _downAt = _lastAt = null;
    if (!wasDragging) return;
    _startCoast(timeMs);
    // 관성 없이 뗐다: 끄는 동안(ClearType이 아닌 회색으로) 그린 마지막 장면을 멈춘 모습으로 한 번 더 그리게 알린다.
    // 관성이 없으면 active도 busy도 거짓이라 시계가 돌지 않으므로, 알릴 곳은 여기뿐이다(관성이 있으면 그 틱이 알린다).
    if (_velocity == Offset.zero) notifyListeners();
  }

  /// 손을 뗀 속도가 충분하면 관성을 시작한다.
  void _startCoast(double timeMs) {
    if (reduceMotion || _samples.length < 2) return;
    final first = _samples.first, last = _samples.last;
    final elapsed = last.$1 - first.$1;
    if (elapsed <= 0 || timeMs - last.$1 > Motion.coastGrab || _travel < Motion.coastTravel) return;
    var v = (last.$2 - first.$2) / elapsed * 1000;
    if (v.distance < Motion.coastMin) return;
    final most = Motion.coastMax * view.plotWidth * view.mag / (Motion.coastTau / 1000);
    if (v.distance > most) v = v / v.distance * most;
    _velocity = v;
    _sync();
  }

  void pointerCancel() {
    final wasDragging = dragging;
    dragging = false;
    pressed = false;
    _downAt = _lastAt = null;
    stop();
    if (wasDragging) notifyListeners(); // 취소로 끝난 끌기도 멈춘 모습으로 한 번 더(pointerUp과 같은 까닭)
  }

  // ---- 두 손가락(터치 화면): 벌리면 기간이 좁아지고(확대) 오므리면 넓어진다. 두 손가락의 가운데가 가리키던 시각과 줄은 손을 따라온다 ----
  // 휠과 같은 '기간 확대'다(돋보기가 아니다) — 손에 붙어 움직이므로 쫓아가기 없이 곧바로 옮긴다. 관성도 없다(되튐 없음의 연장).
  double _pinchSpan = 0, _pinchMinute = 0;
  Offset? _pinchAt;

  /// 두 손가락으로 쥐고 있는가.
  bool get pinching => _pinchAt != null;

  /// 두 번째 손가락이 닿았다. [focal]은 두 손가락의 가운데(화면 px). 하던 한 손가락 끌기는 여기서 끝난다.
  void pinchStart(Offset focal) {
    stop();
    dragging = false;
    pressed = true;
    _downAt = _lastAt = null;
    _samples.clear();
    _pinchSpan = view.span;
    _pinchMinute = view.lo + (focal.dx / view.mag - view.left) / view.ppm;
    _pinchAt = focal;
  }

  /// [scale]은 쥐기 시작할 때의 두 손가락 거리에 대한 지금 거리의 비(1보다 크면 벌린 것).
  void pinchUpdate(Offset focal, double scale) {
    final from = _pinchAt;
    if (from == null || !(scale > 0)) return;
    final span = (_pinchSpan / scale).clamp(minSpan, math.max(minSpan, maxSpan)).toDouble();
    view.ppm = view.plotWidth / span;
    view.lo = _pinchMinute - (focal.dx / view.mag - view.left) / view.ppm;
    view.top -= (focal.dy - from.dy) / view.mag;
    _pinchAt = focal;
    _bound();
    notifyListeners();
  }

  /// 손가락이 하나라도 떨어졌다 — 그 자리에서 멎는다.
  void pinchEnd() {
    if (_pinchAt == null) return;
    _pinchAt = null;
    pressed = false;
    notifyListeners();
  }

  /// 움직임을 그 자리에서 멈춘다(누름 · 키 · 새 자료).
  void stop() {
    _targetLo = _targetSpan = _targetMag = null;
    _velocity = Offset.zero;
    // 비행 도중이면 그 자리가 끝이다(도착을 알리지 않는다).
    _fly?.stop();
    _fly = null;
    _flyArrived = null;
    _sync();
  }

  /// 지금 도는 움직임의 이름(움직임 계측 창이 읽는다). 멎어 있으면 빈 글.
  String get motionName => _fly != null ? '비행' : (_targetMag != null ? '돋보기' : (_targetLo != null ? '쫓아가기' : (_velocity != Offset.zero ? '관성' : '')));

  /// 화면의 시계가 장면마다 부른다(지난 시간 ms).
  void tick(double dtMs) {
    if (!active.value) return;
    // 느리게 보기(`Motion.slow`)의 배율은 이 dt에 **이미 들어 있다** — Flutter가 장면 시각을 `timeDilation`으로 나눠
    // 화면의 시계(Ticker)에 주기 때문이다(Motion의 설명 · `test/motion_meter_test.dart`가 못 박아 둔다).
    // 여기서 또 나누면 배율이 제곱이 되므로 나누지 않는다.
    final dt = dtMs.clamp(0.0, 50.0);
    if (_fly != null) {
      _flyStep(dt);
      notifyListeners();
      _sync();
      return;
    }
    if (_targetLo != null) {
      final a = 1 - math.exp(-dt / _tau);
      final lo = view.lo + (_targetLo! - view.lo) * a, span = view.span + (_targetSpan! - view.span) * a;
      view.ppm = view.plotWidth / span;
      view.lo = lo;
      if ((_targetLo! - lo).abs() * view.ppm < .08 && (_targetSpan! - span).abs() / span * view.plotWidth < .08) _arrive();
    }
    if (_targetMag != null) {
      final a = 1 - math.exp(-dt / Motion.chaseNotch);
      var mag = view.mag + (_targetMag! - view.mag) * a;
      if ((_targetMag! - mag).abs() < .0005) {
        mag = _settledMag(_targetMag!);
        _targetMag = null;
      }
      _setMag(mag);
    } else if (_targetLo == null && _velocity != Offset.zero) {
      final decay = math.exp(-dt / Motion.coastTau);
      final before = (view.lo, view.top);
      _moveBy(_velocity * (Motion.coastTau / 1000 * (1 - decay)));
      _velocity *= decay;
      // 끝에 닿은 쪽은 거기서 멎는다. 되튀지 않는다.
      _velocity = Offset(view.lo == before.$1 ? 0 : _velocity.dx, view.top == before.$2 ? 0 : _velocity.dy);
      if (_velocity.distance < Motion.coastRest) _velocity = Offset.zero;
    }
    notifyListeners();
    _sync();
  }

  void _arrive() {
    view.ppm = view.plotWidth / _targetSpan!;
    view.lo = _targetLo!;
    _targetLo = _targetSpan = null;
  }

  /// 손이 움직인 만큼(화면 px) 내용이 따라온다.
  void _moveBy(Offset screenDelta) {
    view.lo -= screenDelta.dx / view.mag / view.ppm;
    view.top -= screenDelta.dy / view.mag;
    _bound();
  }

  double _boundLo(double lo, double span) {
    final margin = span * edgeMargin;
    final least = _min - margin, most = _max + margin - span;
    return most < least ? (least + most) / 2 : lo.clamp(least, most);
  }

  void _bound() {
    final double span = view.span.clamp(minSpan, math.max(minSpan, maxSpan)).toDouble();
    view.ppm = view.plotWidth / span;
    view.lo = _boundLo(view.lo, span);
    view.top = view.top.clamp(0.0, math.max(0.0, _content - view.bodyHeight));
  }

  void _sync() => active.value = _fly != null || _targetLo != null || _targetMag != null || _velocity != Offset.zero;

  @override
  void dispose() {
    active.dispose();
    magnification.dispose();
    super.dispose();
  }
}

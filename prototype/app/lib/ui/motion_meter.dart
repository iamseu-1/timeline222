import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../measure/frame_stats.dart';
import '../motion.dart';
import '../scene/emphasis.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'legend.dart' show legendSlot;
import 'shell_keys.dart';

// 움직임 계측 · 느리게 보기 — 감독용 도구. 지금 연표의 `js/motion-probe.js`와 메뉴의 `◔ 움직임 계측 · 느리게 보기`를 옮긴 것이다
// (`docs/움직임-원칙.md`의 '재는 도구' 절 · 명세 06의 8-2 메뉴 맨 아래 줄).
//
// 지금 연표와 새 앱은 **재는 것이 다르다.** 브라우저는 움직임 하나하나(CSS 전환 · 키프레임 · WAAPI)를
// `document.getAnimations()`로 셀 수 있어 "끝나는 시각 · 길이 종류 · 곡선 종류"를 세었지만, 새 앱은 움직임을
// 한 캔버스에 직접 그리므로 셀 '움직임 객체'가 없다. 대신 캔버스가 보여 주어야 할 것을 센다:
// **장면마다의 만들기 · 칠하기 ms와 놓친 장면**(2단계 측정과 같은 판정 — `measure/frame_stats.dart`의 [judge])과
// **지금 도는 움직임의 이름과 길이**. 느리게 보기는 그대로다.
//
// 창을 닫으면 배율은 1배로 돌아온다(지금 연표와 같다). **측정 모드에서는 늘 1배이고 이 창은 닫힌다.** 감독이 순서를 지켜야
// 값이 맞는 상태로 두지 않으려고 두 자리에서 못 박는다(총괄 이음 · 필수):
//   · `measure/runner.dart`의 `runMeasure` 들머리에 `Motion.slow = 1;` — 4배로 열어 둔 채 '측정'을 눌러도 재는 동안은 1배다.
//   · `archive_app.dart`의 `quickMeasure()`가 `measuring = true` 직전에 `MotionMeter.toggle(bus!, false)` — 창을 닫아
//     0.15초마다의 되그리기가 재는 10초에 가짜 장면을 섞지 않게 한다(창은 `frozen`이어도 살아 있다).

/// [AppBus.slot]에 쓰는 이름 — 계측 창이 열려 있는가(참/거짓). 메뉴의 ✓가 이 값을 읽는다.
const motionSlot = 'motion';

/// 지금 연표의 `--danger` · `--ok`(css/common.css 15~16줄). 앱 틀의 값 표에는 없어 여기에 둔다.
const _danger = Color(0xff000000), _ok = Color(0xff000000);

/// 되돌아본 창(ms · 실제 시간). 지금 연표의 점수표가 손을 뗀 뒤 1.5초를 지켜본 것과 같은 자리의 값이다.
const _windowMs = 2000.0;

/// 창 자체의 치수(지금 연표의 `.motion-panel`): 폭 224 · 왼쪽 12(범례가 열려 있으면 324) · 바닥에서 16 · 둥근 16.
const _width = 224.0, _left = 12.0, _leftWithLegend = 324.0, _bottom = 16.0, _radius = 16.0;

/// 장면 하나의 기록(ms). [gapMs]는 **잇따라 그린** 앞 장면과의 간격이고, 쉬다가 다시 그리기 시작한 장면은 0이다.
///
/// 시계가 둘인 까닭: [gapMs]는 엔진이 적은 장면 시각(vsync)끼리 견주어야 정확하고, 2초 창은 그 시각이
/// 어느 시계의 값인지와 상관없이 "받은 지 얼마나 됐는가"로 세어야 그리기가 멎은 뒤에도 창이 비운다.
@immutable
class MotionFrame {
  const MotionFrame({required this.seenMs, required this.buildMs, required this.rasterMs, required this.gapMs});

  /// 이 기록을 받은 때(ms · 창의 시계).
  final double seenMs;
  final double buildMs, rasterMs, gapMs;

  FrameSample get sample => FrameSample(buildMs: buildMs, rasterMs: rasterMs, vsyncGapMs: gapMs);
}

/// 최근 [_windowMs] 동안의 장면을 모아 두는 통. 화면 없이도 검사로 못 박을 수 있게 부품에서 떼어 두었다.
class MotionWindow {
  final _frames = <MotionFrame>[];
  double? _lastVsync;
  bool _lastMoving = false;

  List<MotionFrame> get frames => List.unmodifiable(_frames);
  int get length => _frames.length;
  bool get isEmpty => _frames.isEmpty;

  /// 남아 있는 첫 · 마지막 장면을 받은 때(ms · 창의 시계). 비어 있으면 0이다 — 값이 달라졌는지만 가리는 데 쓴다.
  double get firstSeenMs => _frames.isEmpty ? 0 : _frames.first.seenMs;
  double get lastSeenMs => _frames.isEmpty ? 0 : _frames.last.seenMs;

  /// 장면 기록을 더한다. 간격은 **이번 장면과 앞 장면이 둘 다 그리는 중일 때만** 센다 —
  /// 2단계 측정의 `_join`(measure/runner.dart의 `!(moving && beforeMoving)`)과 한 글자도 다르지 않은 규칙이다.
  ///
  /// 앞 장면을 함께 보는 것이 중요하다: 이번 장면만 보면 **멎어 있다 다시 움직이기 시작한 첫 장면**이
  /// 앞의 쉬던 틈을 통째로 뒤집어써, 연표에 손을 대는 순간마다 '50ms 멈춤 1 · 놓친 장면 1%'가 빨갛게 뜬다(거짓 경보).
  void add({required double vsyncMs, required double seenMs, required double buildMs, required double rasterMs, required bool moving}) {
    final last = _lastVsync;
    final gap = moving && _lastMoving && last != null && vsyncMs > last ? vsyncMs - last : 0.0;
    _lastVsync = vsyncMs;
    _lastMoving = moving;
    _frames.add(MotionFrame(seenMs: seenMs, buildMs: buildMs, rasterMs: rasterMs, gapMs: gap));
    trim(seenMs);
  }

  /// [nowMs](창의 시계)에서 [_windowMs]보다 오래된 장면을 버린다.
  void trim(double nowMs) {
    final least = nowMs - _windowMs;
    int drop = 0;
    while (drop < _frames.length && _frames[drop].seenMs < least) {
      drop++;
    }
    if (drop > 0) _frames.removeRange(0, drop);
  }

  void clear() {
    _frames.clear();
    _lastVsync = null;
    _lastMoving = false;
  }

  /// 2단계 측정과 **같은 판정**으로 이 창의 값을 낸다(놓친 장면 · 연달아 · 50ms 멈춤 · 느린 1% 경계).
  SectionVerdict judgeNow(double hz) => judge([for (final f in _frames) f.sample], hz);
}

/// 지금 도는 움직임 하나 — 이름과 그동안 흐른 시간(ms · **1배 기준**). [lengthMs]를 아는 것은 길이도 함께 적는다.
@immutable
class RunningMotion {
  const RunningMotion(this.name, this.elapsedMs, {this.lengthMs});
  final String name;
  final double elapsedMs;
  final double? lengthMs;

  String get text {
    final now = (elapsedMs / 1000).toStringAsFixed(2);
    return lengthMs == null ? '$name $now초' : '$name $now/${(lengthMs! / 1000).toStringAsFixed(2)}초';
  }
}

/// 움직임 계측 창. `Cmd.motion`(메뉴 `◔ 움직임 계측 · 느리게 보기`)으로 여닫는다.
/// 앱 틀의 Stack에 `Positioned.fill(child: MotionMeter(bus: b))`로 끼운다 — 제 자리는 스스로 잡는다.
class MotionMeter extends StatefulWidget {
  const MotionMeter({super.key, required this.bus});
  final AppBus bus;

  /// 열려 있는가(메뉴의 ✓).
  static bool isOpen(AppBus bus) => bus.slot(motionSlot).value == true;

  /// 창을 여닫는다. 닫을 때는 배율을 1배로 되돌린다.
  static void toggle(AppBus bus, [bool? open]) {
    final want = open ?? !isOpen(bus);
    if (!want) Motion.slow = 1;
    bus.slot(motionSlot).value = want;
  }

  @override
  State<MotionMeter> createState() => MotionMeterState();
}

class MotionMeterState extends State<MotionMeter> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();

  /// 최근 2초의 장면(검사가 들여다본다).
  final window = MotionWindow();

  /// 2초 창을 세는 시계(실제 시간 · 느리게 보기를 타지 않는다 — 장면 시간은 실제로 얼마나 걸렸는지가 알고 싶은 값이다).
  final _clock = Stopwatch()..start();

  /// 마지막으로 읽은 '지금 도는 움직임'. 그리는 도중에 셈하지 않으려고 0.15초마다 여기에 옮겨 적는다.
  List<RunningMotion> _running = const [];

  Timer? _refresh;

  /// 머리를 끌어 옮긴 자리(왼쪽 위 · 옮기지 않았으면 null).
  Offset? _moved;
  Offset? _grab;
  bool _listening = false;

  /// 움직임마다 '언제 시작했는가'(1배 기준 ms).
  final _started = <String, double>{};

  AppBus get _bus => widget.bus;
  bool get _open => MotionMeter.isOpen(_bus);

  @override
  void initState() {
    super.initState();
    _bus.slot(motionSlot).addListener(_onSwitch);
    _bus.slot(slotCommand).addListener(_onCommand);
    _bus.slot(legendSlot).addListener(_onLegend);
    // 다 옅어진 뒤에는 창을 아예 치운다(나타남 · 사라짐은 AnimatedBuilder가 맡으므로 바깥 build는 따로 알아야 한다).
    _enter.addStatusListener(_onEnter);
    if (_open) _onSwitch();
  }

  void _onEnter(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_open && mounted) setState(() {});
  }

  /// 동작 줄이기(운영체제 · 검사)면 나타남 · 사라짐을 건너뛴다.
  bool _instant = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _instant = MediaQuery.disableAnimationsOf(context);
    if (_instant && _enter.isAnimating) _enter.value = _open ? 1 : 0;
  }

  @override
  void dispose() {
    _bus.slot(motionSlot).removeListener(_onSwitch);
    _bus.slot(slotCommand).removeListener(_onCommand);
    _bus.slot(legendSlot).removeListener(_onLegend);
    _enter.removeStatusListener(_onEnter);
    _listen(false);
    _refresh?.cancel();
    _enter.dispose();
    // 창이 사라진 채로 느린 시계가 남지 않게.
    Motion.slow = 1;
    super.dispose();
  }

  /// 메뉴 · 단축키의 `◔ 움직임 계측`이 오면 여닫는다.
  void _onCommand() {
    final command = _bus.slot(slotCommand).value;
    if (command is AppCommand && command.name == Cmd.motion) MotionMeter.toggle(_bus);
  }

  void _onLegend() {
    // 범례가 열리고 닫히면 옮기지 않은 창은 옆으로 비킨다(지금 연표의 `.stage:has(.legend…) .motion-panel:not(.is-moved)`).
    if (_open && _moved == null && mounted) setState(() {});
  }

  void _onSwitch() {
    if (!mounted) return;
    _refresh?.cancel();
    _refresh = null;
    if (_open) {
      window.clear();
      _started.clear();
      _selfFrames.clear();
      _running = const [];
      _last = '';
      _listen(true);
      if (_instant) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
      // 장면마다 다시 그리면 이 창이 저를 재게 된다 — 0.15초마다 한 번만 값을 옮겨 적는다.
      _refresh = Timer.periodic(const Duration(milliseconds: 150), (_) => _redraw());
    } else {
      _listen(false);
      if (_instant) {
        _enter.value = 0;
      } else {
        _enter.reverse();
      }
    }
    setState(() {});
  }

  void _listen(bool on) {
    if (on == _listening) return;
    _listening = on;
    if (on) {
      SchedulerBinding.instance.addTimingsCallback(collect);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(collect);
    }
  }

  double get _nowMs => _clock.elapsedMicroseconds / 1000;

  /// 장면마다 엔진이 알려 주는 만들기 · 칠하기 시간. 여기서는 **모으기만** 한다(여기서 다시 그리면 끝없이 돈다).
  void collect(List<FrameTiming> timings) {
    // 이 묶음이 도착한 지금 그리는 중인가 — 멎어 있던 사이의 긴 틈을 놓친 장면으로 세지 않기 위한 어림이다.
    final moving = _bus.scene.busy.value || _bus.controller.dragging;
    final seen = _nowMs;
    for (final t in timings) {
      final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
      // 이 창이 스스로 불러낸 되그리기는 '그리는 중'이 아니다 — 손을 댄 채 멈춰 있을 때(끌기 중 정지)
      // 0.15초마다의 되그리기가 저희끼리 150ms의 거짓 틈을 만들지 않게.
      final self = _isSelfFrame(vsync);
      window.add(vsyncMs: vsync / 1000, seenMs: seen, buildMs: t.buildDuration.inMicroseconds / 1000, rasterMs: t.rasterDuration.inMicroseconds / 1000, moving: moving && !self);
    }
  }

  /// 이 창이 스스로 불러낸 장면의 시각(vsync µs). 기록은 [_markSelfFrame]이 남긴다.
  final _selfFrames = <int>[];

  /// [vsyncMicros]가 이 창이 부른 장면인가. 엔진이 적은 vsync와 화면 쪽이 적은 장면 시각은 조금 다를 수 있어
  /// 2단계 측정의 `_join`과 같은 3ms 안에서 짝짓는다. 못 찾으면 거짓 — 짝이 안 맞아도 예전처럼 셀 뿐 틀리지는 않는다.
  bool _isSelfFrame(int vsyncMicros) {
    for (int i = 0; i < _selfFrames.length; i++) {
      if ((_selfFrames[i] - vsyncMicros).abs() <= 3000) {
        _selfFrames.removeRange(0, i + 1); // 지나간 표시는 버린다(장면 기록은 차례대로 온다).
        return true;
      }
    }
    return false;
  }

  /// 다음 장면을 '이 창이 부른 장면'으로 표시한다. 장면이 다 그려진 뒤에야 그 장면의 시각을 알 수 있어 뒤에서 적는다.
  @visibleForTesting
  void markSelfFrame() {
    final where = _where;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // 그 사이에 손이 연표를 옮겼다면 이 장면은 그 움직임의 몫이다 — 표시하지 않는다(진짜 틈을 지우지 않게).
      if (!mounted || !_open || _where != where) return;
      _selfFrames.add(SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds);
      if (_selfFrames.length > 8) _selfFrames.removeAt(0);
    });
  }

  /// 연표가 보고 있는 자리(왼쪽 끝 · 1분의 폭 · 세로 자리 · 돋보기). 장면 사이에 이것이 달라졌으면 연표가 움직인 것이다.
  String get _where {
    final v = _bus.controller.view;
    return '${v.lo}|${v.ppm}|${v.top}|${v.mag}';
  }

  /// 값이 달라졌는지 가리는 표(0.15초마다 견준다). 같으면 다시 그리지 않는다 —
  /// 멎어 있는 동안 이 창이 장면을 만들어 내지 않게(재는 도구가 잴 것을 만들지 않는다).
  String _stamp(List<RunningMotion> now) => '${window.length}|${window.firstSeenMs}~${window.lastSeenMs}|${Motion.slow}|${now.map((m) => m.text).join('·')}';

  String _last = '';

  void _redraw() {
    if (!mounted || !_open) return;
    // 그리기가 멎으면 장면 기록도 더는 오지 않는다 — 창이 비도록 스스로 버린다.
    window.trim(_nowMs);
    final now = running();
    final stamp = _stamp(now);
    if (stamp == _last) return;
    _last = stamp;
    // 아무도 장면을 부르지 않았는데 우리가 부른다면 그 장면은 우리 것이다(움직이는 중이면 화면의 시계가 이미 불러 두었다).
    final mine = !SchedulerBinding.instance.hasScheduledFrame;
    setState(() => _running = now);
    if (mine) markSelfFrame();
  }

  /// 지금 도는 움직임의 이름과 길이. 이름이 새로 나타나면 그때를 적어 두었다가 흐른 시간을 센다.
  List<RunningMotion> running() {
    final c = _bus.controller, s = _bus.scene;
    final names = <String>[if (c.dragging) '끌기', if (c.motionName.isNotEmpty) c.motionName, if (s.layout.flowing) '줄 흐름', if (Emphasis.of(s).active) '밝기', if (s.fading) '타일 떠오름'];
    final now = Motion.now();
    _started.removeWhere((name, _) => !names.contains(name));
    for (final name in names) {
      _started.putIfAbsent(name, () => now);
    }
    return [for (final name in names) name == '줄 흐름' ? RunningMotion(name, s.layout.flowElapsed, lengthMs: Motion.move) : RunningMotion(name, now - (_started[name] ?? now))];
  }

  double get _hz {
    final rate = View.maybeOf(context)?.display.refreshRate ?? 0;
    return rate > 0 ? rate : 60;
  }

  // ---- 그리기 ----

  @override
  Widget build(BuildContext context) {
    if (!_open && _enter.isDismissed) return const SizedBox.shrink();
    final legendOpen = _bus.slot(legendSlot).value == true;
    return LayoutBuilder(
      builder: (context, box) {
        final moved = _moved;
        final left = (moved?.dx ?? (legendOpen ? _leftWithLegend : _left)).clamp(4.0, math.max(4.0, box.maxWidth - _width - 4)).toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: moved?.dy,
              bottom: moved == null ? _bottom : null,
              width: _width,
              child: AnimatedBuilder(
                animation: _enter,
                builder: (context, child) {
                  final t = _enter.value;
                  return Opacity(
                    opacity: _enter.opacity,
                    child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
                  );
                },
                child: _panel(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 창의 몸 — 끌어 옮길 때 높이를 재려고 열쇠를 둔다.
  final _panelKey = GlobalKey();

  Widget _panel() => GlassCard(
    key: _panelKey,
    radius: _radius,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    // merge다 — 앱 틀이 정한 글꼴(Pretendard → Noto Sans KR → 맑은 고딕)을 지우지 않고 크기 · 줄 높이 · 색만 덮는다.
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12, height: 1.45, color: Ui.text, fontFeatures: [FontFeature.tabularFigures()]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [_head(), const SizedBox(height: 4), _speed(), _act(), _list(), _bars(), _note()],
      ),
    ),
  );

  Widget _head() => SizedBox(
    height: 28,
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 붙잡은 자리는 **창의 왼쪽 위에서부터** 재야 옮긴 자리가 어긋나지 않는다(머리는 안쪽 여백만큼 들어가 있다).
            onPanStart: (d) {
              final panel = _panelKey.currentContext?.findRenderObject();
              _grab = panel is RenderBox ? panel.globalToLocal(d.globalPosition) : d.localPosition;
            },
            onPanUpdate: _drag,
            onPanEnd: (_) => _grab = null,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '움직임 계측',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: -.125, color: Ui.text),
                ),
              ),
            ),
          ),
        ),
        _SmallButton(
          size: 24,
          radius: 8,
          tooltip: '닫기',
          onPressed: () => MotionMeter.toggle(_bus, false),
          child: const Text('✕', style: TextStyle(fontSize: 12, color: Ui.text3)),
        ),
      ],
    ),
  );

  /// 머리를 끌어 창을 옮긴다 — 가리고 싶지 않은 것이 있으면 비켜 둘 수 있게(지금 연표의 `.mp-head`).
  void _drag(DragUpdateDetails d) {
    final box = context.findRenderObject();
    final grab = _grab;
    if (box is! RenderBox || grab == null) return;
    final at = box.globalToLocal(d.globalPosition) - grab;
    final height = _panelKey.currentContext?.size?.height ?? 300;
    setState(() {
      _moved = Offset(at.dx.clamp(4.0, math.max(4.0, box.size.width - _width - 4)), at.dy.clamp(4.0, math.max(4.0, box.size.height - height - 4)));
    });
  }

  Widget _speed() => Container(
    padding: const EdgeInsets.all(2),
    // 갈래 고르기: ink20 선의 칸 안에서 고른 칸만 반전 채움(HistoryArchive의 Segmented).
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Ui.controlRadius),
      border: Border.all(color: Ui.ink20),
    ),
    child: Row(
      children: [
        for (final rate in Motion.slowRates) ...[
          if (rate != Motion.slowRates.first) const SizedBox(width: 2),
          Expanded(
            child: _SmallButton(
              height: 26,
              radius: Ui.innerRadius,
              pressed: Motion.slow == rate,
              tooltip: rate == 1 ? '보통 빠르기' : '${_rate(rate)}배로 느리게 보기',
              onPressed: () => setState(() => Motion.slow = rate),
              child: Text(
                '${_rate(rate)}×',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Motion.slow == rate ? Ui.paper : Ui.text, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  static String _rate(double rate) => rate == rate.roundToDouble() ? '${rate.round()}' : '$rate';

  Widget _act() {
    final now = _running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 11.5, color: Ui.text3),
          children: now.isEmpty
              ? const [TextSpan(text: '멎어 있음 — 연표를 끌거나 굴려 보세요')]
              : [
                  const TextSpan(text: '지금 '),
                  TextSpan(
                    text: now.map((m) => m.text).join(' · '),
                    style: const TextStyle(color: Ui.text, fontWeight: FontWeight.w600),
                  ),
                ],
        ),
      ),
    );
  }

  Widget _list() {
    final hz = _hz, budget = 1000 / hz;
    final v = window.judgeNow(hz);
    final limit = budget * .8;
    String ms(double value) => '${value.toStringAsFixed(1)}ms';
    // 이름 · 목표 글은 짧게 — 창 폭이 224(안쪽 200)라 지금 연표처럼 한 줄에 다 들어가야 한다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('만들기', v.frames == 0 ? '—' : ms(v.buildP99), goal: '한도 ${ms(limit)}', over: v.frames == 0 ? null : v.buildP99 > limit),
        _row('칠하기', v.frames == 0 ? '—' : ms(v.rasterP99), goal: '한도 ${ms(limit)}', over: v.frames == 0 ? null : v.rasterP99 > limit),
        _row('놓친 장면', v.frames == 0 ? '—' : '${(v.missedRatio * 100).toStringAsFixed(2)}%', goal: '목표 1%', over: v.frames == 0 ? null : v.missedRatio > .01),
        _row('연달아', '${v.maxConsecutiveMissed}', goal: '목표 0', over: v.frames == 0 ? null : v.maxConsecutiveMissed >= 2),
        _row('50ms 멈춤', '${v.over50}', goal: '목표 0', over: v.frames == 0 ? null : v.over50 > 0),
      ],
    );
  }

  Widget _row(String name, String value, {String goal = '', bool? over}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(color: Ui.text2),
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w600, color: over == null ? Ui.text : (over ? _danger : _ok)),
        ),
        if (goal.isNotEmpty) ...[
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              goal,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w400, color: Ui.text3),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _bars() => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: SizedBox(
      height: 34,
      child: CustomPaint(
        painter: MotionBars(frames: window.frames, budgetMs: 1000 / _hz),
        size: Size.infinite,
      ),
    ),
  );

  Widget _note() {
    final bits = <String>[
      '최근 2초 ${window.length}장 · 막대는 만들기와 칠하기 가운데 큰 값 · 가로선은 한 장면의 예산(${(1000 / _hz).toStringAsFixed(1)}ms)',
      if (Motion.slow != 1) '${_rate(Motion.slow)}배 느리게 — 장면 시간은 실제 시간이고 움직임의 길이는 1배 기준',
      '이 창을 다시 그리는 몫도 값에 들어 있음',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(bits.join(' — '), style: const TextStyle(fontSize: 10.5, height: 1.4, color: Ui.text3)),
    );
  }
}

/// 최근 2초의 장면을 막대로. 막대 하나가 장면 하나이고 높이는 만들기 · 칠하기 가운데 큰 값이다.
/// 예산을 넘은 장면은 빨강, 예산의 80%를 넘은 장면은 주황, 나머지는 강조색이다.
class MotionBars extends CustomPainter {
  const MotionBars({required this.frames, required this.budgetMs});
  final List<MotionFrame> frames;
  final double budgetMs;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Ui.line
      ..strokeWidth = 1;
    // 가로선 = 예산. 막대 높이의 자는 예산의 두 배까지다(예산선이 한가운데에 온다).
    final full = budgetMs * 2;
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), line);
    if (frames.isEmpty) return;
    final count = math.min(frames.length, size.width ~/ 2);
    if (count <= 0) return;
    final step = size.width / count;
    final width = math.max(1.0, step - .5);
    final paint = Paint();
    for (int i = 0; i < count; i++) {
      final f = frames[frames.length - count + i];
      final value = math.max(f.buildMs, f.rasterMs);
      final over = f.buildMs > budgetMs || f.rasterMs > budgetMs || f.gapMs > budgetMs * 1.5;
      paint.color = over ? _danger : (value > budgetMs * .8 ? Ui.warn : Ui.accent.withValues(alpha: .7));
      final height = (value / full).clamp(0.0, 1.0) * size.height;
      canvas.drawRect(Rect.fromLTWH(i * step, size.height - height, width, math.max(height, 1)), paint);
    }
  }

  @override
  bool shouldRepaint(MotionBars old) => true;
}

/// 계측 창의 작은 단추(닫기 · 빠르기). 올리면 바탕이 들어오고, 고른 빠르기는 `surface`에 그림자가 진다.
class _SmallButton extends StatefulWidget {
  const _SmallButton({required this.child, required this.onPressed, this.size, this.height, this.radius = 8, this.pressed = false, this.tooltip});
  final Widget child;
  final VoidCallback onPressed;
  final double? size, height;
  final double radius;
  final bool pressed;
  final String? tooltip;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget body = AnimatedContainer(
      duration: Duration(milliseconds: Motion.micro.round()),
      curve: Ui.ease,
      height: widget.size ?? widget.height,
      width: widget.size,
      decoration: BoxDecoration(color: widget.pressed ? Ui.ink : (_hover ? Ui.surface2 : null), borderRadius: BorderRadius.circular(widget.radius)),
      child: Center(child: widget.child),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) body = Tooltip(message: tooltip, waitDuration: const Duration(milliseconds: 400), child: body);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPressed, child: body),
    );
  }
}

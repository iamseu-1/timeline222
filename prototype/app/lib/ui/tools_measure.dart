import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scene/fonts.dart';
import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'date_text.dart';
import 'shell_keys.dart';

// 기간 재기(명세 06의 7-2). 켜고 연표 위를 좌우로 끌면 그 구간에 띠가 그려지고, 손을 놓으면 잰 범위가 남는다.
// 끈 길이가 보기 폭의 0.5%보다 짧으면 없던 일로 한다(지금 연표 timeline.js:4676 그대로).
//
// 부품 둘이다:
//   [MeasureLayer] 연표와 같은 상자에 겹쳐 놓는 끌기 판 — 끈 구간에 띠와 작은 이름표를 그린다.
//   [MeasurePill]  알약 창 아래에 뜨는 결과 알약 — `📏 〈기간 글〉 · 〈길이〉 [지우기]`.
// 서로 주고받는 길은 [AppBus]의 슬롯뿐이다:
//   `bus.slot('command')`              — 단축키 · 메뉴의 [Cmd.measure]가 오면 [MeasureLayer]가 켜고 끈다(`📏` · `R`).
//   `bus.slot('measure_on')` = bool    — 켜졌는가(메뉴의 딱지도 이 값을 본다).
//   `bus.slot('measure')`    = [분, 분] — 잰 범위(작은 값이 앞). 없으면 null.
//
// 날짜 글과 길이 글(해 → 개월 → 일 → 시간)의 규칙은 `date_text.dart`의 순수 함수를 쓴다 —
// 1582년 앞을 율리우스력으로 세는 그 달력이 연표의 눈금과 같은 답을 주기 때문이다. 여기서는 계약의 시간(분)과
// 그 파일의 해 좌표를 오가는 얇은 껍데기(`measurePrec` · `measureRangeText` · `measureLengthText` · `pointText`)만 둔다.

/// `bus.slot(…)`의 이름: 잰 범위와 켬/끔.
const measureSlot = 'measure', measureOnSlot = 'measure_on';

/// 한 해 · 한 달 · 하루의 분(눈금과 앞뒤 범위를 어림하는 값 — 달력의 실제 길이는 `date_text.dart`가 센다).
const minutesPerYear = 525960.0, minutesPerMonth = minutesPerYear / 12, minutesPerDay = 1440.0;

/// 기간 재기의 자세함: 보기 폭과 잰 길이 가운데 **좁은 쪽**으로 — 넓게 보면서 짧게 재도 `0년`이 아니라 개월 · 일로 센다.
DatePrec measurePrec(double viewSpan, double length) => precFor(math.min(viewSpan, length) / minutesPerYear);

/// 한 시점의 글(분). `기원전 841년` · `841년 5월 3일`.
String pointText(double minute, DatePrec prec) => formatT(tOfMinutes(minute), prec);

/// 두 시점의 글(분). 같은 해면 뒤쪽의 겹치는 앞부분을 줄인다.
String measureRangeText(double lo, double hi, DatePrec prec) => spanRange(tOfMinutes(lo), tOfMinutes(hi), prec);

/// 잰 길이의 글(분). `1,200년` · `3개월 12일 (104일)` · `2일 5시간`.
String measureLengthText(double lo, double hi, DatePrec prec) => durationText(tOfMinutes(lo), tOfMinutes(hi), prec);

/// 잰 범위 [분, 분]을 슬롯에서 읽는다(모양이 다르면 null).
List<double>? measureRange(AppBus bus) {
  final v = bus.slot(measureSlot).value;
  if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
    final a = (v[0] as num).toDouble(), b = (v[1] as num).toDouble();
    return [math.min(a, b), math.max(a, b)];
  }
  return null;
}

/// 연표와 같은 상자에 겹쳐 놓는 끌기 판. `measure_on`이 꺼져 있으면 아무 자리도 차지하지 않는다(연표가 평소대로 움직인다).
/// 켜져 있는 동안은 이 판이 손을 받아 연표가 끌려가지 않는다 — 지금 연표도 재는 동안에는 보기를 옮기지 않는다.
class MeasureLayer extends StatefulWidget {
  const MeasureLayer({super.key, required this.bus});
  final AppBus bus;

  @override
  State<MeasureLayer> createState() => _MeasureLayerState();
}

class _MeasureLayerState extends State<MeasureLayer> {
  /// 끄는 동안의 두 끝(분). 손을 놓으면 슬롯으로 옮긴다.
  final _live = ValueNotifier<List<double>?>(null);
  bool _dragging = false;

  AppBus get _bus => widget.bus;

  @override
  void initState() {
    super.initState();
    _bus.slot(measureOnSlot).addListener(_onSwitch);
    _bus.slot(slotCommand).addListener(_onCommand);
  }

  @override
  void dispose() {
    _bus.slot(measureOnSlot).removeListener(_onSwitch);
    _bus.slot(slotCommand).removeListener(_onCommand);
    _live.dispose();
    super.dispose();
  }

  /// 단축키 · 메뉴의 `📏 기간 재기`가 오면 켜고 끈다. 켤 때는 어떻게 재는지 한 줄 알린다(지금 연표의 안내와 같은 글).
  void _onCommand() {
    final command = _bus.slot(slotCommand).value;
    if (command is! AppCommand || command.name != Cmd.measure) return;
    final on = _bus.slot(measureOnSlot).value != true;
    _bus.slot(measureOnSlot).value = on;
    if (on) _bus.slot(slotNotice).value = '연표 위에서 좌우로 드래그하면 기간을 재 줍니다. 가까이 확대하면 개월·일까지 셉니다.';
  }

  void _onSwitch() {
    if (!mounted) return;
    if (_bus.slot(measureOnSlot).value != true) {
      _dragging = false;
      _live.value = null;
      _bus.slot(measureSlot).value = null; // 끄면 잰 것도 치운다(지금 연표의 setMeasureMode(false))
    }
    setState(() {});
  }

  /// 화면 x(이 판 안의 자리) → 분. 그림 영역 밖으로는 나가지 않게 가둔다(지금 연표의 yearAtClientX).
  double _minuteAt(double x) {
    final v = _bus.controller.view;
    final inside = (x / v.mag - v.left).clamp(0.0, v.plotWidth);
    return v.lo + inside / v.ppm;
  }

  void _down(PointerDownEvent e) {
    final t = _minuteAt(e.localPosition.dx);
    _dragging = true;
    _live.value = [t, t];
  }

  void _move(PointerMoveEvent e) {
    if (!_dragging) return;
    _live.value = [_live.value![0], _minuteAt(e.localPosition.dx)];
  }

  void _up(PointerEvent e) {
    if (!_dragging) return;
    _dragging = false;
    final r = _live.value;
    _live.value = null;
    if (r == null) return;
    final a = math.min(r[0], r[1]), b = math.max(r[0], r[1]);
    // 끈 길이가 보기 폭의 0.5%보다 짧으면 없던 일로 — 재려다 만 누름이 앞서 잰 것을 지운다.
    _bus.slot(measureSlot).value = (b - a) < _bus.controller.view.span * .005 ? null : [a, b];
  }

  @override
  Widget build(BuildContext context) {
    if (_bus.slot(measureOnSlot).value != true) return const SizedBox.shrink();
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise, // css의 .tl-body.is-measuring { cursor: crosshair }
        child: CustomPaint(
          painter: MeasurePainter(bus: _bus, live: _live),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// 잰 구간의 띠(css의 `.tl-band-measure`): 바탕은 강조색 12% · 좌우 1px 선 · 위쪽 5px에 작은 이름표(`시작 ~ 끝 · 길이`).
class MeasurePainter extends CustomPainter {
  MeasurePainter({required this.bus, required this.live}) : super(repaint: Listenable.merge([bus.controller, live, bus.slot(measureSlot)]));
  final AppBus bus;

  /// 끄는 동안의 두 끝. 비어 있으면 슬롯에 남은 범위를 그린다.
  final ValueNotifier<List<double>?> live;

  @override
  void paint(Canvas canvas, Size size) {
    final r = live.value ?? measureRange(bus);
    if (r == null) return;
    final v = bus.controller.view;
    final a = math.min(r[0], r[1]), b = math.max(r[0], r[1]);
    final left = (v.left * v.mag).clamp(0.0, size.width);
    double x(double minute) => (v.xOf(minute) * v.mag).clamp(left, size.width);
    final x0 = x(a), x1 = x(b);

    canvas.drawRect(Rect.fromLTRB(x0, 0, x1, size.height), Paint()..color = Ui.accent.withValues(alpha: .12));
    final edge = Paint()
      ..color = Ui.accent
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x0 + .5, 0), Offset(x0 + .5, size.height), edge);
    canvas.drawLine(Offset(x1 - .5, 0), Offset(x1 - .5, size.height), edge);

    final prec = measurePrec(v.span, b - a);
    final label = '${measureRangeText(a, b, prec)} · ${measureLengthText(a, b, prec)}';
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: const TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xffffffff), height: 1.4),
      ),
    )..layout();
    final w = text.width + 18, h = text.height + 2;
    final cx = ((x0 + x1) / 2 - w / 2).clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx, 5, w, h), Radius.circular(h / 2)), Paint()..color = Ui.accent);
    text.paint(canvas, Offset(cx + 9, 6));
  }

  @override
  bool shouldRepaint(covariant MeasurePainter old) => old.bus != bus || old.live != live;
}

/// 잰 결과 알약(css의 `.status-pill`): 알약 창 아래 8px · 왼쪽 12px에 선다. 잰 것이 없으면 아무 자리도 차지하지 않는다.
/// 자세함이 보기 폭에 달려 있어 보기를 옮기면 글이 바뀌므로, **글이 바뀔 때만** 다시 그린다.
class MeasurePill extends StatefulWidget {
  const MeasurePill({super.key, required this.bus});
  final AppBus bus;

  @override
  State<MeasurePill> createState() => _MeasurePillState();
}

class _MeasurePillState extends State<MeasurePill> {
  String _text = '', _length = '';

  AppBus get _bus => widget.bus;

  @override
  void initState() {
    super.initState();
    _bus.slot(measureSlot).addListener(_sync);
    _bus.controller.addListener(_sync);
    _read();
  }

  @override
  void dispose() {
    _bus.slot(measureSlot).removeListener(_sync);
    _bus.controller.removeListener(_sync);
    super.dispose();
  }

  bool _read() {
    final r = measureRange(_bus);
    final prec = r == null ? DatePrec.year : measurePrec(_bus.controller.view.span, r[1] - r[0]);
    final text = r == null ? '' : measureRangeText(r[0], r[1], prec);
    final length = r == null ? '' : measureLengthText(r[0], r[1], prec);
    if (text == _text && length == _length) return false;
    _text = text;
    _length = length;
    return true;
  }

  void _sync() {
    if (mounted && _read()) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Ui.text2, height: 1.4);
    return GlassCard(
      radius: Ui.controlRadius,
      blur: Ui.blurLight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LineIcon(LineGlyph.ruler, size: 14, color: Ui.ink60),
          const SizedBox(width: 6),
          Text('$_text · ', style: style),
          Text(_length, style: style.copyWith(fontWeight: FontWeight.w700, color: Ui.text)),
          const SizedBox(width: 10),
          Linky(text: '지우기', size: 12, onTap: () => _bus.slot(measureSlot).value = null),
        ],
      ),
    );
  }
}

/// 글 속의 작은 단추(css의 `.linky`): 강조색 · 밑줄. 도구 셋이 함께 쓴다.
class Linky extends StatelessWidget {
  const Linky({super.key, required this.text, required this.onTap, this.size = 13, this.color = Ui.accent, this.italic = false, this.strike = false});
  final String text;
  final VoidCallback onTap;
  final double size;
  final Color color;

  /// 전설로만 전하는 나라는 기울임, 부정된 나라는 취소선(명세 7-1).
  final bool italic, strike;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          fontSize: size,
          color: color,
          height: 1.5,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          decoration: strike ? TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]) : TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    ),
  );
}

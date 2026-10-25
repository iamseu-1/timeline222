import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../motion_spring.dart';
import 'look.dart';

/// 보는 시기: 기존 날짜 정밀도/기원전 규칙을 지키며 큰 숫자와 작은 단위로 그린다.
/// 자리와 굴림은 붙박이 조각마다 값 하나. 새 글을 받아도 살아 있는 값과 속도를 이어 쓴다.
/// 글이 그대로인 장면에는 다시 만들지 않고, 굴러가는 동안에는 이 작은 그림만 다시 칠한다.
class RangeRoll extends StatefulWidget {
  const RangeRoll({super.key, required this.label});
  final String label;

  @override
  State<RangeRoll> createState() => _RangeRollState();
}

class _RangePiece {
  _RangePiece({
    required this.text,
    required this.kind,
    required this.width,
    required this.x,
    required this.opacity,
    required this.roll,
  });
  final String text, kind;
  final double width;
  final MotionSpring x, opacity, roll;
}

class _RangeRepaint extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _RangeRollState extends State<RangeRoll> {
  final _pieces = <String, _RangePiece>{};
  final _repaint = _RangeRepaint();
  final _glyphs = <String, TextPainter>{};
  late final MotionSpring _width;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _width = MotionSpring(1, epsilon: .05, maxOvershoot: 6);
    _sync(first: true);
    MotionStage.instance.attach(_width, _repaint.changed);
  }

  @override
  void didUpdateWidget(covariant RangeRoll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduce) {
      _width.jump(_width.target);
      for (final piece in _pieces.values) {
        piece.x.jump(piece.x.target);
        piece.roll.jump(piece.roll.target);
      }
    }
    for (final painter in _glyphs.values) {
      painter.dispose();
    }
    _glyphs.clear();
  }

  void _sync({bool first = false}) {
    final seen = <String>{};
    double x = 0;
    int side = 0;
    void put(String key, String text, String kind, double width, {int? digit}) {
      seen.add(key);
      final existing = _pieces[key];
      final piece =
          existing ??
          _RangePiece(
            text: text,
            kind: kind,
            width: width,
            x: MotionSpring(x, epsilon: .05, maxOvershoot: 6),
            opacity: MotionSpring(
              first ? 1 : 0,
              epsilon: .002,
              maxOvershoot: 0,
            ),
            roll: MotionSpring(
              -28.0 * (digit ?? 0),
              epsilon: .05,
              maxOvershoot: 6,
            ),
          );
      if (existing == null) {
        _pieces[key] = piece;
        for (final value in [piece.x, piece.opacity, piece.roll]) {
          MotionStage.instance.attach(value, _repaint.changed);
        }
      } else {
        final hidden = piece.opacity.value < .02;
        if (hidden || _reduce) {
          piece.x.jump(x);
        } else {
          piece.x.retarget(x, token: Motion.near((piece.x.target - x).abs()));
        }
        if (digit != null) {
          final y = -28.0 * digit;
          if (hidden || _reduce) {
            piece.roll.jump(y);
          } else {
            piece.roll.retarget(
              y,
              token: Motion.near((piece.roll.target - y).abs()),
            );
          }
        }
      }
      if (!first) piece.opacity.retarget(1, token: MotionToken.enter);
      x += width;
    }

    for (final match in RegExp(
      r'(기원전\s*)?(\d+)(년|월|일|시)|~',
    ).allMatches(widget.label)) {
      if (match.group(0) == '~') {
        put('dash', '–', 'dash', 18);
        side++;
        continue;
      }
      final unit = match.group(3)!;
      final prefix = '$side-$unit';
      if (match.group(1) != null) put('$prefix-bc', '기원전', 'bc', 35);
      final digits = match.group(2)!;
      for (int i = 0; i < digits.length; i++) {
        put(
          '$prefix-${digits.length - i - 1}',
          '',
          'digit',
          12,
          digit: int.parse(digits[i]),
        );
      }
      put('$prefix-unit', unit, 'unit', 15);
    }
    for (final entry in _pieces.entries) {
      if (!seen.contains(entry.key)) {
        entry.value.opacity.retarget(0, token: MotionToken.exit);
      }
    }
    if (first || _reduce) {
      _width.jump(x);
    } else {
      _width.retarget(x, token: Motion.near((x - _width.target).abs()));
    }
  }

  @override
  void dispose() {
    MotionStage.instance.detach(_width);
    for (final piece in _pieces.values) {
      for (final value in [piece.x, piece.opacity, piece.roll]) {
        MotionStage.instance.detach(value);
      }
    }
    _repaint.dispose();
    for (final painter in _glyphs.values) {
      painter.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    excludeSemantics: true,
    child: RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: 34,
        child: CustomPaint(
          painter: _RangePainter(
            _pieces,
            _width,
            DefaultTextStyle.of(context).style,
            MediaQuery.textScalerOf(context),
            _glyphs,
            _repaint,
          ),
        ),
      ),
    ),
  );
}

class _RangePainter extends CustomPainter {
  _RangePainter(
    this.pieces,
    this.width,
    this.base,
    this.scaler,
    this.glyphs,
    Listenable repaint,
  ) : super(repaint: repaint);
  final Map<String, _RangePiece> pieces;
  final MotionSpring width;
  final TextStyle base;
  final TextScaler scaler;
  final Map<String, TextPainter> glyphs;

  TextPainter glyph(String text, String kind) {
    final digit = kind == 'digit';
    final size = digit
        ? 20.0
        : (kind == 'bc' ? 11.0 : (kind == 'dash' ? 16.0 : 12.0));
    final color = digit ? Ui.ink : (kind == 'dash' ? Ui.ink40 : Ui.ink60);
    final cacheKey = '$text-$kind';
    return glyphs.putIfAbsent(
      cacheKey,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(
            fontSize: size,
            height: 1,
            fontWeight: digit
                ? FontWeight.w700
                : (kind == 'bc' ? FontWeight.w600 : FontWeight.w400),
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // 날짜가 시각까지 자세해지거나 기원전 수가 길어져도 검색 칸을 밀거나 글이 밖으로 나가지 않는다.
    final scale = math.min(1.0, size.width / math.max(1, width.value));
    canvas.translate(0, (size.height - 28 * scale) / 2);
    canvas.scale(scale);
    for (final piece in pieces.values) {
      final opacity = piece.opacity.value.clamp(0.0, 1.0);
      if (opacity < .002) continue;
      canvas.save();
      canvas.translate(piece.x.value, 0);
      canvas.clipRect(Rect.fromLTWH(0, 0, piece.width, 28));
      if (opacity < .999) {
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, piece.width, 28),
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
        );
      }
      if (piece.kind == 'digit') {
        // 그릴 수 있는 자리만 칠한다. 열 숫자 전체의 텍스트 배치/그리기는 필요 없다.
        for (int digit = 0; digit <= 9; digit++) {
          final y = digit * 28 + piece.roll.value;
          if (y <= -28 || y >= 28) continue;
          final text = glyph('$digit', 'digit');
          text.paint(
            canvas,
            Offset((12 - text.width) / 2, y + (28 - text.height) / 2),
          );
        }
      } else {
        final text = glyph(piece.text, piece.kind);
        text.paint(
          canvas,
          Offset(piece.kind == 'unit' ? 2 : 0, (28 - text.height) / 2 + 2),
        );
      }
      if (opacity < .999) canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RangePainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.scaler != scaler ||
      oldDelegate.pieces != pieces;
}

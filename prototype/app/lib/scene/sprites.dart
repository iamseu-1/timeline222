import 'dart:typed_data';
import 'dart:ui' as ui;

import 'fonts.dart';

// 작은 그림판: 점 · 점의 바탕 테두리 · 알약의 양 끝 · 숫자(+0123456789) · 띠의 둥근 모서리를 흰색으로 한 번 그려 두고,
// 장면마다 drawRawAtlas 한 번으로 수천 개를 찍는다(색은 찍을 때 입힌다). 점과 알약의 숫자를 하나씩 따로 그리면
// 그리기 호출이 수천 번이 된다 — 1단계가 글자 511개에서 이미 칠하기 한도에 닿았던 까닭이다.
// 돋보기 배율이 멎으면 그 배율로 그림판을 다시 뜬다(작아서 싸다) — 키운 그림을 그대로 두면 멎은 화면에서 점과 숫자가 흐리다.
class Sprites {
  Sprites._(this._image, this._digitWidth, this._scale);
  ui.Image _image;
  final List<double> _digitWidth;
  double _scale;

  static const _cell = 16.0, digitSize = 9.5, digitHeight = 12.0, pillHeight = 14.0;
  static const ring = ui.Rect.fromLTWH(0, 0, 13, 13), fill = ui.Rect.fromLTWH(16, 0, 7, 7);
  static const capLeft = ui.Rect.fromLTWH(32, 0, 7, 14), capRight = ui.Rect.fromLTWH(48, 0, 7, 14);

  /// 띠의 둥근 모서리(반지름 [cornerRadius]의 원을 넷으로 나눈 조각).
  static const cornerRadius = 9.0;
  static const cornerTopLeft = ui.Rect.fromLTWH(0, 32, cornerRadius, cornerRadius), cornerTopRight = ui.Rect.fromLTWH(cornerRadius, 32, cornerRadius, cornerRadius);
  static const cornerBottomLeft = ui.Rect.fromLTWH(0, 32 + cornerRadius, cornerRadius, cornerRadius);
  static const cornerBottomRight = ui.Rect.fromLTWH(cornerRadius, 32 + cornerRadius, cornerRadius, cornerRadius);
  static const _glyphs = '+0123456789';
  static const _sheetWidth = 176.0, _sheetHeight = 52.0;

  static Sprites? _shared;
  static Sprites get shared => _shared ??= Sprites._(_render(1), _measureDigits(), 1);

  double get scale => _scale;

  /// 멎은 돋보기 배율(× 화면의 px 비율)을 알려 준다. 바뀌었으면 그 배율로 다시 뜬다.
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image.dispose();
    _image = _render(next);
    _scale = next;
  }

  static ui.Paragraph _digit(int i) {
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1, fontFamily: sceneFontFamily, fontSize: digitSize, fontWeight: ui.FontWeight.w700, height: 1.2))
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xffffffff), fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback))
          ..addText(_glyphs[i]);
    return builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  static List<double> _measureDigits() {
    final widths = <double>[];
    for (int i = 0; i < _glyphs.length; i++) {
      final p = _digit(i);
      widths.add(p.maxIntrinsicWidth.ceilToDouble());
      p.dispose();
    }
    return widths;
  }

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()..color = const ui.Color(0xffffffff);
    canvas.drawCircle(const ui.Offset(6.5, 6.5), 6.5, white);
    canvas.drawCircle(const ui.Offset(16 + 3.5, 3.5), 3.5, white);
    // 알약의 양 끝: 높이 14의 반원.
    canvas.save();
    canvas.clipRect(capLeft);
    canvas.drawCircle(const ui.Offset(32 + 7, 7), 7, white);
    canvas.restore();
    canvas.save();
    canvas.clipRect(capRight);
    canvas.drawCircle(const ui.Offset(48, 7), 7, white);
    canvas.restore();
    for (int i = 0; i < _glyphs.length; i++) {
      final p = _digit(i);
      canvas.drawParagraph(p, ui.Offset(i * _cell, _cell));
      p.dispose();
    }
    canvas.drawCircle(const ui.Offset(cornerRadius, 32 + cornerRadius), cornerRadius, white);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheetWidth * scale).ceil(), (_sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }

  /// 글자 하나가 그림판의 몇 번째 숫자인가(없으면 −1). `_glyphs.indexOf(text[i])`로 찾으면 글자마다 한 글자짜리 글줄이
  /// 새로 생긴다 — 알약의 숫자는 장면마다 수백 번 지나가는 길이라 낱글자 값으로 가른다.
  static int _glyphAt(int code) {
    if (code == 0x2b) return 0; // '+'
    if (code >= 0x30 && code <= 0x39) return code - 0x30 + 1; // '0'~'9'
    return -1;
  }

  double digitsWidth(String text) {
    double w = 0;
    for (int i = 0; i < text.length; i++) {
      final g = _glyphAt(text.codeUnitAt(i));
      if (g >= 0) w += _digitWidth[g];
    }
    return w;
  }

  // 장면마다 다시 쓰는 목록: 찍을 자리(회전 없는 변환 4개씩) · 그림판의 자리(4개씩) · 색.
  Float32List _transforms = Float32List(4 * 1024), _rects = Float32List(4 * 1024);
  Int32List _colors = Int32List(1024);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 조각 하나를 왼쪽 위 자리(배치 px)에 찍는다. [size]는 조각을 줄여 찍을 비율(좁은 띠의 작은 모서리).
  void add(ui.Rect source, double left, double top, int argb, [double size = 1]) =>
      _put(source.left, source.top, source.right, source.bottom, left, top, argb, size);

  /// 그림판의 네 변을 값으로 받는 길 — 숫자처럼 자리가 뻔한 조각은 [ui.Rect]를 새로 짓지 않는다.
  void _put(double sl, double st, double sr, double sb, double left, double top, int argb, double size) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = size / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = sl * s;
    _rects[p + 1] = st * s;
    _rects[p + 2] = sr * s;
    _rects[p + 3] = sb * s;
    _colors[_n] = argb;
    _n++;
  }

  /// 숫자 글줄('+38')을 왼쪽 위 자리에서부터 찍는다. 숫자는 화면 px에 맞춘다(흐림 방지).
  void addDigits(String text, double left, double top, int argb) {
    final s = _scale;
    double x = left;
    final y = (top * s).roundToDouble() / s;
    for (int i = 0; i < text.length; i++) {
      final g = _glyphAt(text.codeUnitAt(i));
      if (g < 0) continue;
      final w = _digitWidth[g], l = g * _cell;
      _put(l, _cell, l + w, _cell + digitHeight, (x * s).roundToDouble() / s, y, argb, 1);
      x += w;
    }
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }
}

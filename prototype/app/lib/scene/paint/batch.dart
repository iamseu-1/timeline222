import 'dart:typed_data';
import 'dart:ui' as ui;

import '../text_paragraph.dart';

// 묶어 그리기의 연장들. 같은 종류의 도형은 장면마다 몇 번의 그리기 호출로 끝낸다 —
// 띠마다 · 선마다 · 글자마다 따로 그리면 하나하나가 따로 처리되어 칠하기가 한도를 넘는다(2단계의 병목 일곱 가운데 넷).

/// 네모를 색인 꼭짓점으로 내보낼 때 쓰는 색인 한 벌(네모마다 0,1,2 · 0,2,3). 한 번 만들어 모든 묶음이 다시 쓴다 —
/// 같은 차례가 되풀이될 뿐이라 장면마다 다시 지을 것이 없다.
class QuadIndices {
  /// `Uint16List` 색인이 가리킬 수 있는 꼭짓점은 65,535까지다 → 한 번에 내보내는 네모는 이만큼까지(꼭짓점 65,536).
  static const perDraw = 16384;

  static Uint16List? _all;

  /// 네모 [quads]개를 그리는 색인(길이 quads × 6). [perDraw]보다 많이 달라고 하지 않는다.
  static Uint16List of(int quads) {
    final all = _all ??= _build();
    return quads == perDraw ? all : Uint16List.sublistView(all, 0, quads * 6);
  }

  static Uint16List _build() {
    final out = Uint16List(perDraw * 6);
    for (int q = 0; q < perDraw; q++) {
      final v = q * 4, i = q * 6;
      out[i] = v;
      out[i + 1] = v + 1;
      out[i + 2] = v + 2;
      out[i + 3] = v;
      out[i + 4] = v + 2;
      out[i + 5] = v + 3;
    }
    return out;
  }
}

/// 색이 제각각인 네모를 한 번에 그린다.
/// 네모 하나에 **꼭짓점 넷 + 색인 여섯**이다 — 꼭짓점 여섯을 늘어놓으면 내보낼 때 화폭으로 베끼는 자리와 색이 1.5배가 된다.
class Quads {
  Float32List _at = Float32List(8 * 512);
  Int32List _color = Int32List(4 * 512);
  int _n = 0;
  final _paint = ui.Paint();

  int get count => _n;

  /// 한 가지 색의 네모. 장면의 도형 가운데 열에 아홉이 이 길로 온다 — [addCorners]를 거치지 않고 바로 담는다.
  void add(double l, double t, double r, double b, int argb) {
    if (_n * 8 == _at.length) _grow();
    final p = _n * 8, c = _n * 4;
    _at[p] = l; _at[p + 1] = t; _at[p + 2] = r; _at[p + 3] = t;
    _at[p + 4] = r; _at[p + 5] = b; _at[p + 6] = l; _at[p + 7] = b;
    _color[c] = argb; _color[c + 1] = argb; _color[c + 2] = argb; _color[c + 3] = argb;
    _n++;
  }

  /// 왼쪽 색에서 오른쪽 색으로 옆으로 번지는 네모(연대 미정의 옅은 끝).
  void addFade(double l, double t, double r, double b, int leftArgb, int rightArgb) => addCorners(l, t, r, b, leftArgb, rightArgb, rightArgb, leftArgb);

  /// 위 색에서 아래 색으로 세로로 번지는 네모(전설의 안개).
  void addFadeDown(double l, double t, double r, double b, int topArgb, int bottomArgb) => addCorners(l, t, r, b, topArgb, topArgb, bottomArgb, bottomArgb);

  void _grow() {
    _at = Float32List(_at.length * 2)..setRange(0, _at.length, _at);
    _color = Int32List(_color.length * 2)..setRange(0, _color.length, _color);
  }

  /// 꼭짓점마다 색을 주는 네모: 왼쪽 위 · 오른쪽 위 · 오른쪽 아래 · 왼쪽 아래.
  void addCorners(double l, double t, double r, double b, int topLeft, int topRight, int bottomRight, int bottomLeft) {
    if (_n * 8 == _at.length) _grow();
    // 꼭짓점 차례: 왼쪽 위 · 오른쪽 위 · 오른쪽 아래 · 왼쪽 아래. 색인이 (0,1,2)(0,2,3)으로 두 세모를 만든다.
    final p = _n * 8, c = _n * 4;
    _at[p] = l; _at[p + 1] = t; _at[p + 2] = r; _at[p + 3] = t;
    _at[p + 4] = r; _at[p + 5] = b; _at[p + 6] = l; _at[p + 7] = b;
    _color[c] = topLeft; _color[c + 1] = topRight; _color[c + 2] = bottomRight; _color[c + 3] = bottomLeft;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    // 색인의 한도를 넘으면 나눠 내보낸다(자리 · 색은 그 몫만 보기로 얹고, 색인은 늘 0에서 시작하는 같은 한 벌이다).
    for (int from = 0; from < _n; from += QuadIndices.perDraw) {
      final left = _n - from, count = left < QuadIndices.perDraw ? left : QuadIndices.perDraw;
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_at, from * 8, (from + count) * 8),
        colors: Int32List.sublistView(_color, from * 4, (from + count) * 4),
        indices: QuadIndices.of(count),
      );
      canvas.drawVertices(vertices, ui.BlendMode.dst, _paint);
      vertices.dispose();
    }
    _n = 0;
  }
}

/// 색이 같은 1px 가로 · 세로선을 한 번에 그린다. 선을 선으로 그리면(drawRawPoints) 매끈한 가는 선 하나하나가 따로 처리되어
/// 600개에 칠하기 2ms가 들었다 — 정수 px에 맞춘 1px 네모로 바꿔 네모 묶음 한 번으로 끝낸다.
class Lines {
  Lines(this.argb);
  final int argb;
  final _quads = Quads();

  void add(double x0, double y0, double x1, double y1) {
    if (x0 == x1) {
      final x = x0.floorToDouble();
      _quads.add(x, y0, x + 1, y1, argb);
    } else {
      final y = y0.floorToDouble();
      _quads.add(x0, y, x1, y + 1, argb);
    }
  }

  void flush(ui.Canvas canvas) => _quads.flush(canvas);
}

/// 색이 제각각인 1px(또는 굵기만큼의) 선과, 끊어 그리는 점선 · 파선. 모두 네모로 바꿔 [Quads]에 모은다.
extension DashedQuads on Quads {
  /// 가로선. [dash] · [gap]을 주면 끊어 그린다(phase는 무늬가 시작하는 자리 — 옆으로 움직여도 무늬가 제 해에 붙어 있게 세계 좌표로 준다).
  void hLine(double x0, double x1, double y, int argb, {double width = 1, double dash = 0, double gap = 0, double phase = 0}) {
    final top = y.floorToDouble();
    if (dash <= 0) {
      add(x0, top, x1, top + width, argb);
      return;
    }
    final period = dash + gap;
    var x = x0 - ((x0 - phase) % period + period) % period;
    for (; x < x1; x += period) {
      final a = x < x0 ? x0 : x, b = x + dash > x1 ? x1 : x + dash;
      if (b > a) add(a, top, b, top + width, argb);
    }
  }

  /// 세로선. 점선이면 위에서부터 끊는다.
  void vLine(double x, double y0, double y1, int argb, {double width = 1, double dash = 0, double gap = 0, double phase = 0}) {
    final left = x.floorToDouble();
    if (dash <= 0) {
      add(left, y0, left + width, y1, argb);
      return;
    }
    final period = dash + gap;
    var y = y0 - ((y0 - phase) % period + period) % period;
    for (; y < y1; y += period) {
      final a = y < y0 ? y0 : y, b = y + dash > y1 ? y1 : y + dash;
      if (b > a) add(left, a, left + width, b, argb);
    }
  }
}

/// 글자는 층의 끝에 몰아 그린다 — 글자 그리기끼리 이어져야 한 번에 묶인다.
///
/// 자리와 투명도는 `List<double>`이 아니라 typed 배열이다: `List<double>`에 담으면 소수마다 상자가 하나씩 생겨
/// 장면마다 수천 개가 쌓인다(글줄 1,400개면 4,200개). 배열은 비우지 않고 늘리기만 한다 — 장면마다 담을 자리를 다시 잡지 않게.
class TextQueue {
  List<String?> _kind = List<String?>.filled(256, null), _what = List<String?>.filled(256, null);
  List<TextLook?> _look = List<TextLook?>.filled(256, null);
  Float64List _x = Float64List(256), _y = Float64List(256), _alpha = Float64List(256);
  int _n = 0;

  /// 아직 그리지 않고 모아 둔 글줄의 수.
  int get count => _n;

  void add(String kind, String what, TextLook look, double x, double y, [double alpha = 1]) {
    if (_n == _x.length) _grow();
    _kind[_n] = kind;
    _what[_n] = what;
    _look[_n] = look;
    _x[_n] = x;
    _y[_n] = y;
    _alpha[_n] = alpha;
    _n++;
  }

  void _grow() {
    final size = _x.length * 2;
    _kind = List<String?>.filled(size, null)..setRange(0, _n, _kind);
    _what = List<String?>.filled(size, null)..setRange(0, _n, _what);
    _look = List<TextLook?>.filled(size, null)..setRange(0, _n, _look);
    _x = Float64List(size)..setRange(0, _n, _x);
    _y = Float64List(size)..setRange(0, _n, _y);
    _alpha = Float64List(size)..setRange(0, _n, _alpha);
  }

  /// 모아 둔 글자를 그리고 비운다. 그린 글줄의 수를 돌려준다. [onPainted]는 검사용 기록.
  int paint(ui.Canvas canvas, SceneText text, {void Function(String kind, String what, double x, double y, double alpha)? onPainted}) {
    int painted = 0;
    for (int i = 0; i < _n; i++) {
      final what = _what[i]!;
      if (!text.paint(canvas, what, _look[i]!, _x[i], _y[i], alpha: _alpha[i])) continue;
      painted++;
      onPainted?.call(_kind[i]!, what, _x[i], _y[i], _alpha[i]);
    }
    _n = 0;
    text.flush(canvas);
    return painted;
  }
}

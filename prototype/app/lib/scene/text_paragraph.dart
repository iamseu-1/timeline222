import 'dart:ui' as ui;

import 'fonts.dart';

// 글자 방식 (가): 모양을 잡은 글줄(Paragraph)을 보관해 두고 그린다.
// 글자 모양 잡기는 비싸다 — 한 번 잡은 것은 다시 만들지 않고, 새 글줄은 장면마다 정해진 만큼만 준비한다.
// 예산이 떨어지면 그 이름은 이번 장면에 그리지 않고 다음 장면에 이어 간다(starved).

/// 글자의 생김새. [id]는 보관 열쇠에 쓰인다.
class TextLook {
  const TextLook(this.size, this.weight, this.color, {this.italic = false, this.spacing = 0, this.wght});
  final double size;
  final ui.FontWeight weight;
  final int color;

  /// 기울인 글자(추정 · 전승 연대의 이름).
  final bool italic;

  /// 글자 사이(px, css의 letter-spacing).
  final double spacing;

  /// 굵기를 100 단위 밖의 값으로(css의 font-weight: 650 — 굵기가 이어지는 글꼴에서만 먹는다). 없으면 [weight].
  final double? wght;

  /// 글자 모양을 가르는 열쇠(크기와 색은 따로): 굵기 × 2 + 기울임.
  int get shapeKey => (wght ?? weight.value.toDouble()).round() * 2 + (italic ? 1 : 0);

  TextLook withColor(int argb) => TextLook(size, weight, argb, italic: italic, spacing: spacing, wght: wght);

  ui.ParagraphStyle paragraphStyle(double scale) =>
      ui.ParagraphStyle(maxLines: 1, fontFamily: sceneFamilyNow, fontSize: size * scale, fontWeight: weight, fontStyle: italic ? ui.FontStyle.italic : ui.FontStyle.normal, height: 1.2);

  ui.TextStyle textStyle(int argb, double scale) => ui.TextStyle(
    color: ui.Color(argb), fontFamily: sceneFamilyNow, fontFamilyFallback: sceneFallbackNow, letterSpacing: spacing == 0 ? null : spacing * scale,
    fontVariations: wght == null ? null : [ui.FontVariation('wght', wght!)],
  );
}

/// 글 상자 기록(찍기 · 검사 전용 — 측정기 `--capture-text=yes`): 그린 글줄마다 그림판 좌표계의 상자와 그때의 자르기를 모은다.
/// 축소할 때 글끼리 겹치는 곳을 그림이 아니라 상자로 찾으려고 둔다(2026-10-25). [SceneText.probe]가 null이면(늘 그렇다) 아무 일도 하지 않는다.
class TextProbe {
  /// 뒷단마다 마지막 장면에 그린 글줄 — `[글, x0, y0, x1, y1, 자르기 x0, y0, x1, y1, 크기, 옅음]`(그림판 기준 px · 레이어 원점).
  final frames = <SceneText, List<List<Object>>>{};

  /// 그리개가 장면을 시작할 때 — 그 뒷단의 지난 장면 기록을 비운다.
  void begin(SceneText text) => frames[text] = [];

  void add(SceneText owner, ui.Canvas canvas, String text, TextLook look, double x, double y, double width, double alpha) {
    final list = frames[owner];
    if (list == null) return;
    final m = canvas.getTransform();
    final clip = canvas.getDestinationClipBounds();
    double dx(double px, double py) => m[0] * px + m[4] * py + m[12];
    double dy(double px, double py) => m[1] * px + m[5] * py + m[13];
    list.add([text, dx(x, y), dy(x, y), dx(x + width, y + look.size * 1.2), dy(x + width, y + look.size * 1.2), clip.left, clip.top, clip.right, clip.bottom, look.size, alpha]);
  }
}

/// 그리는 쪽이 쓰는 글자 그리기의 약속. 두 방식 — (가) 글줄 보관, (나) 그림판에 찍어 두고 묶어 그리기 — 이 같은 약속을 따라
/// 같은 장면으로 재서 고를 수 있다.
abstract class SceneText {
  /// 글 상자 기록(검사 전용 — [TextProbe]). 없으면 기록하지 않는다.
  static TextProbe? probe;

  /// 한 장면에 새로 준비하는 글줄(또는 글자)의 한도.
  int maxNewPerFrame = 40, budgetMicros = 1500;
  int get newThisFrame;
  bool get starved;
  double get spentMs;
  void beginFrame();

  /// 글줄의 폭(px). 아직 준비가 안 됐고 예산도 없으면 null.
  double? widthOf(String text, TextLook look);

  /// 글줄을 그린다(또는 그릴 목록에 모은다). 그릴 수 있었으면 참. [alpha]는 옅어짐용 — 글줄 방식은 무시한다.
  bool paint(ui.Canvas canvas, String text, TextLook look, double x, double y, {double alpha = 1});

  /// 모아 둔 것을 내보낸다(층의 끝마다 부른다).
  void flush(ui.Canvas canvas);

  /// 돋보기 배율이 멎었을 때 알려 준다.
  void setScale(double scale);

  /// 옅어짐을 층 없이 할 수 있는가.
  bool get canFade;
  void dispose();
}

class _Made {
  _Made(this.paragraph, this.width);
  final ui.Paragraph paragraph;
  final double width;
}

class ParagraphText extends SceneText {
  ParagraphText({this.capacity = 4096});
  final int capacity;

  // 한 장면에 새로 만드는 글줄의 한도(개수와 시간 µs)는 SceneText의 값. 보관이 비어 있는 첫 장면은 시간을 네 배까지 쓴다.
  final _made = <(String, double, int, int, double), _Made>{};
  final _watch = Stopwatch();
  @override
  int newThisFrame = 0;
  @override
  bool starved = false;
  bool _cold = true;

  int get count => _made.length;
  @override
  double get spentMs => _watch.elapsedMicroseconds / 1000;
  @override
  bool get canFade => false;
  @override
  void flush(ui.Canvas canvas) {}
  @override
  void setScale(double scale) {}

  @override
  void beginFrame() {
    _cold = _made.isEmpty;
    newThisFrame = 0;
    starved = false;
    _watch
      ..reset()
      ..stop();
  }

  /// 폭만 따로 보관한다 — 폭은 (글 · 크기 · 굵기 · 자간)만으로 정해지고 **색과는 상관이 없다**.
  /// 글줄 보관의 열쇠에는 색이 들어 있어, 같은 이름을 고른 색 · 흐린 색으로 재면 글줄을 한 벌 더 만들어야 했다.
  final _widths = <(String, double, int, double), double>{};

  @override
  double? widthOf(String text, TextLook look) {
    final key = (text, look.size, look.shapeKey, look.spacing);
    final known = _widths[key];
    if (known != null) return known;
    return _get(text, look)?.width;
  }

  /// 글줄은 색이 구워져 있어 [alpha]를 줄 수 없다(층 없이는) — 글줄 방식의 이름은 옅어짐 없이 드나든다.
  @override
  bool paint(ui.Canvas canvas, String text, TextLook look, double x, double y, {double alpha = 1}) {
    final made = _get(text, look);
    if (made == null) return false;
    canvas.drawParagraph(made.paragraph, ui.Offset(x, y));
    SceneText.probe?.add(this, canvas, text, look, x, y, made.width, alpha);
    return true;
  }

  _Made? _get(String text, TextLook look) {
    final key = (text, look.size, look.shapeKey, look.color, look.spacing);
    final hit = _made.remove(key);
    if (hit != null) {
      _made[key] = hit; // 방금 쓴 것을 맨 뒤로(LRU)
      return hit;
    }
    if (newThisFrame >= maxNewPerFrame || _watch.elapsedMicroseconds > (_cold ? budgetMicros * 4 : budgetMicros)) {
      starved = true;
      return null;
    }
    _watch.start();
    final builder = ui.ParagraphBuilder(look.paragraphStyle(1))
      ..pushStyle(look.textStyle(look.color, 1))
      ..addText(text);
    final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    _watch.stop();
    newThisFrame++;
    final made = _Made(paragraph, paragraph.maxIntrinsicWidth);
    _made[key] = made;
    _widths[(text, look.size, look.shapeKey, look.spacing)] = made.width;
    if (_made.length > capacity) {
      final oldest = _made.keys.first;
      _made.remove(oldest)!.paragraph.dispose();
    }
    // 폭은 소수 하나뿐이라 글줄보다 넉넉히 둔다(글줄을 버려도 폭은 남겨 다시 재지 않게).
    if (_widths.length > capacity * 2) _widths.remove(_widths.keys.first);
    return made;
  }

  @override
  void dispose() {
    for (final m in _made.values) {
      m.paragraph.dispose();
    }
    _made.clear();
    _widths.clear();
  }
}
